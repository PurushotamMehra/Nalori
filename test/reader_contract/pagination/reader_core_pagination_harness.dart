import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_display_segment.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reader_compatibility.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';

import '../support/reader_contract_layout_environment.dart';
import '../support/reader_contract_fixture.dart';
import 'reader_card_pagination_evidence.dart';

const readerCoreFixtureId = 'reader-core-micro-v1';
const readerCoreStandardLayoutId = 'p03-controlled-lexend-layout';
const readerCoreSplitStressLayoutId = 'p03-controlled-lexend-split-stress-v1';

const readerCoreReviewedStandardRanges = <String>[
  '0:0-20,1:0-22',
  '2:0-20,3:0-23',
  '4:0-10,5:0-10,6:0-12,7:0-198',
  '8:0-33',
  '9:0-19,10:0-18',
  '11:0-1',
  '12:0-56,13:0-50,14:0-37,15:0-63',
  '16:0-22',
  '17:0-52,18:0-33,19:0-55',
];

const readerCoreReviewedStandardPhysicalSignatures = <String>[
  '3f27702d77cf7eafc56e3eb12b7de0cabf19b216b712b6bd8cbf5696a01a9e79',
  '68de2d916ad4d9611b4b7e3c6fc94fada8ace6a6ec964d7e71f58bfe454be84b',
  'aff523a0850637ed2f2f12400a33d5667832a1a805589237b7318acdd59d4295',
  '6f82dc719931c405d9b6eb327df84bbcba006c4082e7d063ec12dd0f1e3ba5c8',
  '8c0dbd53308d12f402dc6f3a1ad64a868dc1302df123786d48d3c96e9f2c3e58',
  'e99fbe116c39d6842abb2d8ba459996e30515208d87920a96f99c75f9336bd8a',
  'c16cf34e3db4017446460407c71d39298bd8c4a02cb4ffad285d5c68fd3240c5',
  'bcca2d33d48c3f25a1eb2c9973bf4ddbdc6252b8ff28e222ca49a1836fb552a8',
  '05402dceb87fd09959ab8d6f36cc949ddf775d2735864b4f499c3a23c2d49580',
];

const readerCoreReadableSourceExtents = <int, int>{
  0: 20,
  1: 22,
  2: 20,
  3: 23,
  4: 10,
  5: 10,
  6: 12,
  7: 198,
  8: 33,
  9: 19,
  10: 18,
  11: 136,
  12: 56,
  13: 50,
  14: 37,
  15: 63,
  16: 22,
  17: 52,
  18: 33,
  19: 55,
};

final class ReaderCoreParsedFixture {
  ReaderCoreParsedFixture._(
    this.temporaryDirectory,
    this.epubFile,
    this.sourceChunks,
  );

  final Directory temporaryDirectory;
  final File epubFile;
  final List<BookChunk> sourceChunks;

  static Future<ReaderCoreParsedFixture> load(String temporaryPrefix) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      temporaryPrefix,
    );
    final fixture = (await loadReaderContractFixtureManifest()).fixture(
      readerCoreFixtureId,
    );
    final epub = await buildReaderContractFixtureEpub(
      fixture: fixture,
      outputDirectory: temporaryDirectory,
    );
    final sourceChunks = (await EpubParserService().loadAndParseFromFile(
      epub,
    )).chunks;
    return ReaderCoreParsedFixture._(temporaryDirectory, epub, sourceChunks);
  }

  Future<void> close() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}

enum ReaderCorePaginationLayout { standard, splitStress }

extension ReaderCorePaginationLayoutDeclaration on ReaderCorePaginationLayout {
  String get identity => switch (this) {
    ReaderCorePaginationLayout.standard => readerCoreStandardLayoutId,
    ReaderCorePaginationLayout.splitStress => readerCoreSplitStressLayoutId,
  };

  ReaderContractLayoutInputs get inputs => switch (this) {
    ReaderCorePaginationLayout.standard =>
      ReaderContractLayoutInputs.standard(),
    ReaderCorePaginationLayout.splitStress =>
      ReaderContractLayoutInputs.splitStress(),
  };
}

final class ReaderPaginationConstruction {
  const ReaderPaginationConstruction({
    required this.label,
    required this.layoutIdentity,
    required this.requestedRanges,
    required this.state,
    required this.evidence,
    required this.results,
    this.targetSourceIndex,
    this.initialEvidence,
  });

  final String label;
  final String layoutIdentity;
  final List<String> requestedRanges;
  final ProgressiveDisplayState state;
  final ReaderCardPaginationEvidence evidence;
  final List<DisplayRangeResult> results;
  final int? targetSourceIndex;
  final ReaderCardPaginationEvidence? initialEvidence;
}

final class ReaderCanonicalSegmentConstruction {
  const ReaderCanonicalSegmentConstruction({
    required this.construction,
    required this.records,
    required this.maxSourceWork,
    required this.maxCardsPublished,
  });

  final ReaderPaginationConstruction construction;
  final List<CanonicalDisplaySegmentRecord> records;
  final int maxSourceWork;
  final int maxCardsPublished;
}

/// Drives only the extracted production paginator and the production
/// append/prepend owner. It contains no splitting, packing, merging, flushing,
/// rebalancing, or card-identity rules.
final class ReaderCorePaginationHarness {
  ReaderCorePaginationHarness._({
    required this.sourceChunks,
    required this.layoutKind,
    required this.environment,
    required this.paginatorLayout,
    required this.bootstrapFontEvidence,
    required this.controlledLayoutIdentity,
    required this.scheduler,
    required this.bookId,
    required this.publicationFingerprint,
    required this.stateCacheKey,
  });

  static Future<ReaderCorePaginationHarness> install({
    required WidgetTester tester,
    required List<BookChunk> sourceChunks,
    ReaderCorePaginationLayout layout = ReaderCorePaginationLayout.standard,
    String bookId = readerCoreFixtureId,
    String publicationFingerprint = readerCoreFixtureId,
    String? stateCacheKey,
    FrameBudgetedRangeScheduler? scheduler,
  }) async {
    final environment = await ReaderContractLayoutEnvironment.install(
      tester,
      inputs: layout.inputs,
    );
    addTearDown(() => environment.close(tester));
    const settings = ReadingSettings();
    final inputs = environment.inputs;
    final sourceKeys = <CanonicalPaginationSourceKey>[
      for (var ordinal = 0; ordinal < sourceChunks.length; ordinal++)
        CanonicalPaginationSourceKey(
          sourceIdentity:
              '${sourceChunks[ordinal].sourceFile}|${sourceChunks[ordinal].logicalParagraphId}|${sourceChunks[ordinal].type.name}',
          sectionIdentity:
              sourceChunks[ordinal].sourceFile ??
              sourceChunks[ordinal].section.name,
          spineIdentity:
              sourceChunks[ordinal].sourceFile ??
              sourceChunks[ordinal].section.name,
          sourceOrdinalHint: ordinal,
        ),
    ];
    final snapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      parserSourceIdentity: 'reader-core-fixture-parser',
      sourceRevision: readerSha256(
        sourceKeys.map((key) => key.sourceIdentity).toList(growable: false),
      ),
      sourceChunks: sourceChunks,
      sourceKeys: sourceKeys,
    );
    final gate = ReaderFontEvidenceGate();
    final bootstrapText = sourceChunks.first.text ?? '';
    final bootstrapEnd = math.min(
      bootstrapText.length,
      ReaderSourceFontProbePlan.maximumSourceSliceUtf16,
    );
    final bootstrapOwner = canonicalBookChunkOwnershipDigest(
      sourceChunks.first,
    );
    final terminal = await gate.capture(
      settings: settings,
      stableSourceIdentity: bootstrapText.isEmpty
          ? '$bootstrapOwner|0:$bootstrapEnd'
          : 'transition-delivery',
      sourceStartUtf16: 0,
      sourceText: bootstrapText.substring(0, bootstrapEnd),
      locale: inputs.locale.toLanguageTag(),
      textScaler: TextScaler.linear(inputs.textScaleFactor),
    );
    if (terminal is! ReaderFontReadyTerminalBundled) {
      throw StateError('P03 font evidence has no terminal authority.');
    }
    final built = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: inputs.viewportSize,
        mediaQuerySize: inputs.viewportSize,
        viewPadding: inputs.safeArea,
        locale: inputs.locale,
        defaultDirection: inputs.textDirection,
        textScaler: TextScaler.linear(inputs.textScaleFactor),
        settings: settings,
        fontOutcome: terminal,
        captureFreshnessEvidence: 'p03-reviewed-transition',
        publicationFingerprint: snapshot.publicationFingerprint,
        parserSourceSchemaIdentity: snapshot.parserSourceIdentity,
        sourceRevision: snapshot.sourceRevision,
        sourceSnapshotDigest: snapshot.snapshotDigest,
      ),
    );
    if (built is! ReaderLayoutContractReady) {
      throw StateError('P03 layout contract has no authority: ${built.type}.');
    }
    final contract = built.contract;
    List<ReaderSourceFontMetricEvidence> evidence(
      BookChunk chunk,
      String text,
    ) {
      final owner = canonicalBookChunkOwnershipDigest(chunk);
      final result = <ReaderSourceFontMetricEvidence>[];
      var start = 0;
      do {
        final end = math.min(
          text.length,
          start + ReaderSourceFontProbePlan.maximumSourceSliceUtf16,
        );
        final captured = gate.capturePrepared(
          settings: settings,
          stableSourceIdentity: '$owner|$start:$end',
          sourceStartUtf16: start,
          sourceText: text.substring(start, end),
          locale: inputs.locale.toLanguageTag(),
          textScaler: TextScaler.linear(inputs.textScaleFactor),
        );
        if (captured is! ReaderFontReadyTerminalBundled) {
          throw StateError('P03 source font evidence has no authority.');
        }
        result.add(captured.sourceEvidence);
        start = end;
      } while (start < text.length);
      return result;
    }

    final body = contract.typography[ReaderLayoutTextRole.body];
    final heading = contract.typography[ReaderLayoutTextRole.heading];
    final effectiveScheduler =
        scheduler ?? FrameBudgetedRangeScheduler(yieldToFrame: () async {});
    addTearDown(effectiveScheduler.dispose);

    return ReaderCorePaginationHarness._(
      sourceChunks: sourceChunks,
      layoutKind: layout,
      environment: environment,
      paginatorLayout: ReaderCardPaginatorLayout(
        availableWidth: contract.geometry.bodySize.width,
        pageHeightBudget: contract.geometry.ordinaryPaginationHeightBudget,
        physicalTextBudget: contract.geometry.publisherPaginationHeightBudget,
        minUsefulHeight: contract.geometry.minUsefulHeight,
        tinyWordCount: contract.settingsPolicy.densityTinyWordCount,
        tinyHeightRatio: contract.settingsPolicy.densityTinyHeightRatio,
        settings: settings,
        bodyStyle: body.toTextStyle(),
        headingStyle: heading.toTextStyle(),
        bodyStrut: body.toStrutStyle(),
        headingStrut: heading.toStrutStyle(),
        textScaler: TextScaler.noScaling,
        contract: contract,
        fontEvidenceResolver: evidence,
      ),
      bootstrapFontEvidence: terminal.sourceEvidence,
      controlledLayoutIdentity: contract.identity,
      scheduler: effectiveScheduler,
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      stateCacheKey: stateCacheKey ?? 'p03-no-cache-${layout.identity}',
    );
  }

  final List<BookChunk> sourceChunks;
  final ReaderCorePaginationLayout layoutKind;
  final ReaderContractLayoutEnvironment environment;
  final ReaderCardPaginatorLayout paginatorLayout;
  final ReaderSourceFontMetricEvidence bootstrapFontEvidence;
  final String controlledLayoutIdentity;
  final FrameBudgetedRangeScheduler scheduler;
  final String bookId;
  final String publicationFingerprint;
  final String stateCacheKey;
  int _generation = 4000;
  final Map<String, CanonicalFinalizedReaderCard> _finalizedCardsByDigest =
      <String, CanonicalFinalizedReaderCard>{};

  String get layoutIdentity => controlledLayoutIdentity;

  String get layoutDiagnostics => environment.diagnosticOutput;

  CanonicalReaderPaginationSession canonicalSessionForP04({
    bool deferPublicationCommit = false,
  }) => _newCanonicalSession(deferPublicationCommit: deferPublicationCommit);

  CanonicalPaginationTargetCursor canonicalTargetForP04(
    CanonicalReaderPaginationSession session,
    int sourceOrdinal, {
    int textOffsetUtf16 = 0,
  }) {
    final owner = session.sourceSnapshot.ownerAt(sourceOrdinal);
    return session.targetForStableOwner(
      sourceIdentity: owner.sourceIdentity,
      sectionIdentity: owner.sectionIdentity,
      sourceOrdinalHint: owner.sourceOrdinalHint,
      textOffsetUtf16: textOffsetUtf16,
    );
  }

  CanonicalPaginationOperationControls canonicalOperationForP04({
    bool Function()? isCancelled,
    int Function()? currentGenerationToken,
    DisplayRangeTaskPriority priority =
        DisplayRangeTaskPriority.speculativeLookahead,
  }) {
    final generation = ++_generation;
    return CanonicalPaginationOperationControls(
      generationToken: generation,
      scheduler: scheduler,
      priority: priority,
      isCancelled: isCancelled ?? () => false,
      currentGenerationToken: currentGenerationToken ?? () => generation,
      diagnosticBookId: bookId,
    );
  }

  Future<ReaderCanonicalSegmentConstruction> canonicalColdSegments({
    required String bookStorageScopeDigest,
    String label = 'p06-cold-canonical-segments',
  }) async {
    final canonical = _newCanonicalSession(deferPublicationCommit: true);
    final state = _newState();
    final records = <CanonicalDisplaySegmentRecord>[];
    final results = <DisplayRangeResult>[];
    var maxSourceWork = 0;
    var maxCardsPublished = 0;
    CanonicalReaderPaginationPathResult outcome = await canonical
        .generateInitial(
          restart: const CanonicalPaginationPublicationStart(),
          operation: _canonicalOperation(
            DisplayRangeTaskPriority.initialVisible,
          ),
        );
    for (var operation = 0; operation < 64; operation++) {
      if (outcome is! CanonicalReaderPaginationPathAccepted ||
          outcome.publishableCards.isEmpty) {
        throw StateError('Bounded canonical segment generation was rejected.');
      }
      final predecessor = state.acceptedCanonicalContinuation;
      final start = state.canonicalCards.isEmpty
          ? 0
          : state.ranges.last.sourceRange.endExclusive;
      final request = DisplayRangeRequest(
        direction: state.canonicalCards.isEmpty
            ? DisplayRangeDirection.initial
            : DisplayRangeDirection.forward,
        sourceRange: SourceChunkRange(start, sourceChunks.length),
        generationId: _generation,
        reason: '${label}_$operation',
      );
      final result = canonicalPathDisplayResult(
        accepted: outcome,
        request: request,
        publicationStart: start,
      );
      final publication = state.publishCanonical(
        CanonicalDisplayPublicationRequest(
          operation: state.canonicalCards.isEmpty
              ? CanonicalDisplayPublicationOperation.initial
              : CanonicalDisplayPublicationOperation.append,
          sessionIdentity: '$stateCacheKey|$label',
          generationIdentity: request.generationId,
          currentGenerationIdentity: () => request.generationId,
          sourceSnapshot: canonical.sourceSnapshot,
          controlledLayoutIdentity: layoutIdentity,
          paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
          finalizedCards: outcome.publishableCards,
          continuation: outcome.continuation,
          predecessorContinuation: predecessor,
          committedCard: state.canonicalCards.isEmpty
              ? null
              : state.canonicalCards.first,
          isCancelled: () => false,
        ),
      );
      if (publication is! CanonicalDisplayPublicationAccepted ||
          !canonical.commitPublication(outcome)) {
        throw StateError(
          'Canonical segment publication failed: ${publication.kind}',
        );
      }
      final compatibility =
          CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
            ReaderCompatibilityEvidence.fromIdentity(
              paginatorLayout.contract!.identities.readerCompatibilityIdentity,
            ),
          );
      records.add(
        CanonicalDisplaySegmentRecordBuilder.build(
          bookStorageScopeDigest: bookStorageScopeDigest,
          compatibilityEvidence: compatibility,
          sourceSnapshot: canonical.sourceSnapshot,
          finalizedCards: outcome.publishableCards,
          continuation: outcome.continuation,
          acceptedRestart: predecessor,
        ),
      );
      results.add(result);
      maxSourceWork = math.max(
        maxSourceWork,
        outcome.boundedWorkEntriesConsumed,
      );
      maxCardsPublished = math.max(
        maxCardsPublished,
        outcome.publishableCards.length,
      );
      if (outcome is CanonicalReaderLogicalEnd) {
        return ReaderCanonicalSegmentConstruction(
          construction: _construction(
            label: label,
            state: state,
            results: results,
            requestedRanges: results
                .map((value) => value.request.sourceRange.toString())
                .toList(growable: false),
          ),
          records: List<CanonicalDisplaySegmentRecord>.unmodifiable(records),
          maxSourceWork: maxSourceWork,
          maxCardsPublished: maxCardsPublished,
        );
      }
      final boundary = canonical.publishedSuffixBoundary(
        card: state.displayChunks.last,
        sourceOrdinals: state.displayToOriginal.last,
      );
      if (boundary == null) {
        throw StateError('Canonical segment suffix boundary is missing.');
      }
      outcome = await canonical.generateForward(
        acceptedPublishedSuffix: boundary,
        operation: _canonicalOperation(
          DisplayRangeTaskPriority.speculativeLookahead,
        ),
      );
    }
    throw StateError('Canonical segment generation exceeded its bound.');
  }

  Future<ReaderCanonicalSegmentConstruction> canonicalInitialSegment({
    required String bookStorageScopeDigest,
    String label = 'p06-initial-canonical-segment',
  }) async {
    final canonical = _newCanonicalSession(deferPublicationCommit: true);
    final state = _newState();
    final outcome = await canonical.generateInitial(
      restart: const CanonicalPaginationPublicationStart(),
      operation: _canonicalOperation(DisplayRangeTaskPriority.initialVisible),
    );
    if (outcome is! CanonicalReaderPaginationPathAccepted ||
        outcome.publishableCards.isEmpty) {
      throw StateError('Bounded initial canonical generation was rejected.');
    }
    final request = DisplayRangeRequest(
      direction: DisplayRangeDirection.initial,
      sourceRange: SourceChunkRange(0, sourceChunks.length),
      generationId: _generation,
      reason: label,
    );
    final result = canonicalPathDisplayResult(
      accepted: outcome,
      request: request,
      publicationStart: 0,
    );
    final publication = state.publishCanonical(
      CanonicalDisplayPublicationRequest(
        operation: CanonicalDisplayPublicationOperation.initial,
        sessionIdentity: '$stateCacheKey|$label',
        generationIdentity: request.generationId,
        currentGenerationIdentity: () => request.generationId,
        sourceSnapshot: canonical.sourceSnapshot,
        controlledLayoutIdentity: layoutIdentity,
        paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
        finalizedCards: outcome.publishableCards,
        continuation: outcome.continuation,
        isCancelled: () => false,
      ),
    );
    if (publication is! CanonicalDisplayPublicationAccepted ||
        !canonical.commitPublication(outcome)) {
      throw StateError(
        'Initial canonical segment publication failed: ${publication.kind}',
      );
    }
    final compatibility =
        CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
          ReaderCompatibilityEvidence.fromIdentity(
            paginatorLayout.contract!.identities.readerCompatibilityIdentity,
          ),
        );
    final record = CanonicalDisplaySegmentRecordBuilder.build(
      bookStorageScopeDigest: bookStorageScopeDigest,
      compatibilityEvidence: compatibility,
      sourceSnapshot: canonical.sourceSnapshot,
      finalizedCards: outcome.publishableCards,
      continuation: outcome.continuation,
    );
    return ReaderCanonicalSegmentConstruction(
      construction: _construction(
        label: label,
        state: state,
        results: <DisplayRangeResult>[result],
        requestedRanges: <String>[request.sourceRange.toString()],
      ),
      records: <CanonicalDisplaySegmentRecord>[record],
      maxSourceWork: outcome.boundedWorkEntriesConsumed,
      maxCardsPublished: outcome.publishableCards.length,
    );
  }

  Future<ReaderPaginationConstruction> fullRange() async {
    final range = SourceChunkRange(0, sourceChunks.length);
    final construction = await forwardFirst(<SourceChunkRange>[range]);
    if (layoutKind == ReaderCorePaginationLayout.standard &&
        publicationFingerprint == readerCoreFixtureId) {
      _validateReviewedStandardOracle(
        _finalizedCardsForState(construction.state),
      );
    }
    return ReaderPaginationConstruction(
      label: 'full-range',
      layoutIdentity: construction.layoutIdentity,
      requestedRanges: construction.requestedRanges,
      state: construction.state,
      evidence: construction.evidence,
      results: construction.results,
    );
  }

  void _validateReviewedStandardOracle(
    List<CanonicalFinalizedReaderCard> cards,
  ) {
    final ranges = <String>[
      for (final card in cards)
        card.sourceSlices
            .map(
              (slice) =>
                  '${slice.sourceOrdinalHint}:${slice.startUtf16 ?? 0}-${slice.endUtf16 ?? 1}',
            )
            .join(','),
    ];
    final signatures = <String>[
      for (final card in cards) card.identity.signature,
    ];
    if (!listEquals(ranges, readerCoreReviewedStandardRanges) ||
        !listEquals(signatures, readerCoreReviewedStandardPhysicalSignatures)) {
      throw StateError(
        'Reviewed P03 physical oracle mismatch: ranges=$ranges '
        'signatures=$signatures',
      );
    }
  }

  Future<ReaderPaginationConstruction> targetFirst(int target) async {
    final canonical = _newCanonicalSession();
    final state = _newState();
    final targetRange = state.targetRange(
      targetOriginalIndex: target,
      lookBehind: 1,
      lookAhead: 1,
      minimumWindow: 3,
    );
    final results = <DisplayRangeResult>[];
    final requested = <String>[];
    final targetOutcome = await canonical.generateTarget(
      target: _canonicalTarget(canonical, target),
      operation: _canonicalOperation(DisplayRangeTaskPriority.directTarget),
    );
    final initial = _displayResult(
      outcome: targetOutcome,
      request: DisplayRangeRequest(
        direction: DisplayRangeDirection.target,
        sourceRange: targetRange,
        generationId: _generation,
        reason: 'p03_target_first',
        targetOriginalIndex: target,
      ),
      publicationStart: targetRange.start,
    );
    results.add(initial);
    requested.add(targetRange.toString());
    state.publishInitial(initial);
    final initialEvidence = _projectState(state);

    if (targetOutcome is! CanonicalReaderLogicalEnd) {
      await _appendCanonicalToEnd(
        canonical: canonical,
        state: state,
        results: results,
        requested: requested,
        reason: 'p03_target_first_forward',
        targetOriginalIndex: target,
      );
    }
    final backward = SourceChunkRange(0, state.ranges.first.sourceRange.start);
    if (!backward.isEmpty) {
      await _prependCanonicalBoundedToStart(
        canonical: canonical,
        state: state,
        results: results,
        requested: requested,
        reason: 'p03_target_first_backward',
        committedSourceIndex: target,
      );
    }
    return _construction(
      label: 'target-first-forward-then-backward',
      state: state,
      results: results,
      requestedRanges: requested,
      targetSourceIndex: target,
      initialEvidence: initialEvidence,
    );
  }

  Future<ReaderPaginationConstruction> forwardFirst(
    List<SourceChunkRange> partitions,
  ) async {
    _validatePartitions(partitions);
    final canonical = _newCanonicalSession();
    final state = _newState();
    final results = <DisplayRangeResult>[];
    final initialOutcome = await canonical.generateInitial(
      restart: const CanonicalPaginationPublicationStart(),
      operation: _canonicalOperation(DisplayRangeTaskPriority.initialVisible),
    );
    final initial = _displayResult(
      outcome: initialOutcome,
      request: DisplayRangeRequest(
        direction: DisplayRangeDirection.initial,
        sourceRange: partitions.first,
        generationId: _generation,
        reason: 'p03_forward_partition_0',
      ),
      publicationStart: 0,
    );
    results.add(initial);
    state.publishInitial(initial);
    await _appendCanonicalToEnd(
      canonical: canonical,
      state: state,
      results: results,
      requested: null,
      reason: 'p03_forward_partition',
    );
    return _construction(
      label: 'forward-first',
      state: state,
      results: results,
      requestedRanges: partitions.map((range) => range.toString()).toList(),
    );
  }

  Future<ReaderPaginationConstruction> backwardFirst(
    List<SourceChunkRange> partitions,
  ) async {
    _validatePartitions(partitions);
    final canonical = _newCanonicalSession();
    final state = _newState();
    final results = <DisplayRangeResult>[];
    final target = layoutKind == ReaderCorePaginationLayout.splitStress
        ? partitions[partitions.length - 2].start
        : partitions.last.start;
    if (target > 0) {
      await _seedCanonicalRestartBeforeTarget(canonical, target);
    }
    final targetOutcome = await canonical.generateTarget(
      target: _canonicalTarget(canonical, target),
      operation: _canonicalOperation(DisplayRangeTaskPriority.directTarget),
    );
    final initial = _displayResult(
      outcome: targetOutcome,
      request: DisplayRangeRequest(
        direction: DisplayRangeDirection.target,
        sourceRange: partitions.last,
        generationId: _generation,
        reason: 'p03_backward_partition_${partitions.length - 1}',
        targetOriginalIndex: target,
      ),
      publicationStart: partitions.last.start,
    );
    results.add(initial);
    state.publishInitial(initial);
    if (targetOutcome is! CanonicalReaderLogicalEnd) {
      await _appendCanonicalToEnd(
        canonical: canonical,
        state: state,
        results: results,
        requested: null,
        reason: 'p03_backward_suffix',
        targetOriginalIndex: target,
      );
    }
    for (var index = partitions.length - 2; index >= 0; index--) {
      await _prependCanonicalToStart(
        canonical: canonical,
        state: state,
        results: results,
        requested: null,
        reason: 'p03_backward_partition_$index',
        committedSourceIndex: target,
        desiredStart: partitions[index].start,
      );
    }
    return _construction(
      label: 'backward-prepend-first',
      state: state,
      results: results,
      requestedRanges: results
          .map((result) => result.request.sourceRange.toString())
          .toList(),
    );
  }

  Future<ReaderPaginationConstruction> legacyForwardFirst(
    List<SourceChunkRange> partitions,
  ) async {
    _validatePartitions(partitions);
    final state = _newState();
    final results = <DisplayRangeResult>[];
    for (var index = 0; index < partitions.length; index++) {
      final result = await _paginate(
        direction: index == 0
            ? DisplayRangeDirection.initial
            : DisplayRangeDirection.forward,
        sourceRange: partitions[index],
        reason: 'p03_cache_legacy_forward_partition_$index',
      );
      results.add(result);
      if (index == 0) {
        state.publishInitial(result);
      } else {
        state.append(result);
      }
    }
    return _construction(
      label: 'legacy-forward-first-cache-characterization',
      state: state,
      results: results,
      requestedRanges: partitions.map((range) => range.toString()).toList(),
    );
  }

  Future<ReaderPaginationConstruction> regenerateCanonicalAfterCacheRecords({
    required String label,
    required List<DisplayRangeResult> cachedResults,
    required List<String> requestedRanges,
  }) async {
    if (cachedResults.isEmpty) {
      throw ArgumentError.value(
        cachedResults,
        'cachedResults',
        'must not be empty',
      );
    }
    final state = _newState();
    for (final cached in cachedResults) {
      final rejection = state.rejectNonCanonicalCachePublication(
        cacheKind: cached.request.reason,
      );
      if (rejection.kind !=
          CanonicalDisplayPublicationOutcomeKind
              .canonicalRegenerationRequired) {
        throw StateError('Legacy cache record was not rejected fail-closed.');
      }
    }

    final canonical = _newCanonicalSession(deferPublicationCommit: true);
    final results = <DisplayRangeResult>[];
    CanonicalReaderPaginationPathResult outcome = await canonical
        .generateInitial(
          restart: const CanonicalPaginationPublicationStart(),
          operation: _canonicalOperation(
            DisplayRangeTaskPriority.initialVisible,
          ),
        );
    for (var operation = 0; operation < 64; operation++) {
      if (outcome is! CanonicalReaderPaginationPathAccepted ||
          outcome.publishableCards.isEmpty) {
        throw StateError('Bounded canonical cache regeneration was rejected.');
      }
      final start = state.canonicalCards.isEmpty
          ? 0
          : state.ranges.last.sourceRange.endExclusive;
      final request = DisplayRangeRequest(
        direction: state.canonicalCards.isEmpty
            ? DisplayRangeDirection.initial
            : DisplayRangeDirection.forward,
        sourceRange: SourceChunkRange(start, sourceChunks.length),
        generationId: _generation,
        reason: 'p04_cache_canonical_regeneration_$operation',
      );
      final result = canonicalPathDisplayResult(
        accepted: outcome,
        request: request,
        publicationStart: start,
      );
      final publication = state.publishCanonical(
        CanonicalDisplayPublicationRequest(
          operation: state.canonicalCards.isEmpty
              ? CanonicalDisplayPublicationOperation.initial
              : CanonicalDisplayPublicationOperation.append,
          sessionIdentity: '$stateCacheKey|cache-regeneration',
          generationIdentity: request.generationId,
          currentGenerationIdentity: () => request.generationId,
          sourceSnapshot: canonical.sourceSnapshot,
          controlledLayoutIdentity: layoutIdentity,
          paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
          finalizedCards: outcome.publishableCards,
          continuation: outcome.continuation,
          predecessorContinuation: state.acceptedCanonicalContinuation,
          committedCard: state.canonicalCards.isEmpty
              ? null
              : state.canonicalCards.first,
          isCancelled: () => false,
        ),
      );
      if (publication is! CanonicalDisplayPublicationAccepted ||
          !canonical.commitPublication(outcome)) {
        throw StateError(
          'Canonical cache regeneration publication failed: ${publication.kind}',
        );
      }
      results.add(result);
      if (outcome is CanonicalReaderLogicalEnd) {
        return _construction(
          label: label,
          state: state,
          results: results,
          requestedRanges: requestedRanges,
        );
      }
      final boundary = canonical.publishedSuffixBoundary(
        card: state.displayChunks.last,
        sourceOrdinals: state.displayToOriginal.last,
      );
      if (boundary == null) {
        throw StateError('Canonical regenerated suffix boundary is missing.');
      }
      outcome = await canonical.generateForward(
        acceptedPublishedSuffix: boundary,
        operation: _canonicalOperation(
          DisplayRangeTaskPriority.speculativeLookahead,
        ),
      );
    }
    throw StateError(
      'Canonical cache regeneration exceeded its operation bound.',
    );
  }

  Future<ReaderPaginationConstruction> singletonThenExpand({
    required int target,
    required bool forwardFirst,
  }) async {
    final state = _newState();
    final singleton = SourceChunkRange(target, target + 1);
    final canonical = _newCanonicalSession();
    final targetOutcome = await canonical.generateTarget(
      target: _canonicalTarget(canonical, target),
      operation: _canonicalOperation(DisplayRangeTaskPriority.directTarget),
    );
    final initial = _displayResult(
      outcome: targetOutcome,
      request: DisplayRangeRequest(
        direction: DisplayRangeDirection.target,
        sourceRange: singleton,
        generationId: _generation,
        reason: 'p03_singleton_target',
        targetOriginalIndex: target,
      ),
      publicationStart: target,
    );
    state.publishInitial(initial);
    final initialEvidence = _projectState(state);
    final results = <DisplayRangeResult>[initial];
    final requested = <String>[singleton.toString()];

    Future<void> expandForward() async {
      if (targetOutcome is CanonicalReaderLogicalEnd) return;
      await _appendCanonicalToEnd(
        canonical: canonical,
        state: state,
        results: results,
        requested: requested,
        reason: 'p03_singleton_expand_forward',
        targetOriginalIndex: target,
      );
    }

    Future<void> expandBackward() async {
      final range = SourceChunkRange(0, state.ranges.first.sourceRange.start);
      if (range.isEmpty) return;
      await _prependCanonicalBoundedToStart(
        canonical: canonical,
        state: state,
        results: results,
        requested: requested,
        reason: 'p03_singleton_expand_backward',
        committedSourceIndex: target,
      );
    }

    if (forwardFirst) {
      await expandForward();
      await expandBackward();
    } else {
      await expandBackward();
      await expandForward();
    }
    return _construction(
      label: forwardFirst
          ? 'singleton-forward-then-backward'
          : 'singleton-backward-then-forward',
      state: state,
      results: results,
      requestedRanges: requested,
      targetSourceIndex: target,
      initialEvidence: initialEvidence,
    );
  }

  /// Replays cache-derived production results through the same progressive
  /// publication owner used by ReaderScreen. The results must be in ascending,
  /// adjacent source order; this method never joins their cards itself.
  ReaderPaginationConstruction publishForwardResults({
    required String label,
    required List<DisplayRangeResult> results,
    required List<String> requestedRanges,
  }) {
    if (results.isEmpty) {
      throw ArgumentError.value(results, 'results', 'must not be empty');
    }
    final state = _newState()..publishInitial(results.first);
    for (final result in results.skip(1)) {
      state.append(result);
    }
    return _construction(
      label: label,
      state: state,
      results: results,
      requestedRanges: requestedRanges,
    );
  }

  Future<DisplayRangeResult> _paginate({
    required DisplayRangeDirection direction,
    required SourceChunkRange sourceRange,
    required String reason,
    int? targetOriginalIndex,
  }) async {
    final result = await const ReaderCardPaginator().paginateLegacyForP02(
      ReaderCardPaginatorRequest(
        range: DisplayRangeRequest(
          direction: direction,
          sourceRange: sourceRange,
          generationId: ++_generation,
          reason: reason,
          targetOriginalIndex: targetOriginalIndex,
        ),
        sourceChunks: sourceChunks,
        layout: paginatorLayout,
        scheduler: scheduler,
        priority: direction == DisplayRangeDirection.target
            ? DisplayRangeTaskPriority.directTarget
            : direction == DisplayRangeDirection.initial
            ? DisplayRangeTaskPriority.initialVisible
            : DisplayRangeTaskPriority.speculativeLookahead,
        isCancelled: () => false,
        diagnosticBookId: bookId,
        parentGeneration: _generation,
      ),
    );
    if (!result.succeeded) {
      throw StateError(
        'Production paginator did not succeed for $reason $sourceRange: '
        'cancelled=${result.cancelled}; error=${result.error}',
      );
    }
    return result;
  }

  CanonicalReaderPaginationSession _newCanonicalSession({
    bool deferPublicationCommit = false,
  }) {
    final sourceKeys = <CanonicalPaginationSourceKey>[
      for (var ordinal = 0; ordinal < sourceChunks.length; ordinal++)
        CanonicalPaginationSourceKey(
          sourceIdentity:
              '${sourceChunks[ordinal].sourceFile ?? sourceChunks[ordinal].section.name}|'
              '${sourceChunks[ordinal].logicalParagraphId ?? 'missing-owner'}|'
              '${sourceChunks[ordinal].type.name}',
          sectionIdentity:
              sourceChunks[ordinal].sourceFile ??
              sourceChunks[ordinal].section.name,
          spineIdentity:
              sourceChunks[ordinal].sourceFile ??
              sourceChunks[ordinal].section.name,
          sourceOrdinalHint: ordinal,
        ),
    ];
    final snapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      parserSourceIdentity: 'reader-core-fixture-parser',
      sourceRevision: readerSha256(
        sourceKeys.map((key) => key.sourceIdentity).toList(growable: false),
      ),
      sourceChunks: sourceChunks,
      sourceKeys: sourceKeys,
    );
    return CanonicalReaderPaginationSession(
      sourceSnapshot: snapshot,
      controlledLayoutIdentity: layoutIdentity,
      layout: paginatorLayout,
      deferPublicationCommit: deferPublicationCommit,
    );
  }

  CanonicalPaginationTargetCursor _canonicalTarget(
    CanonicalReaderPaginationSession session,
    int sourceOrdinal,
  ) {
    final owner = session.sourceSnapshot.ownerAt(sourceOrdinal);
    return session.targetForStableOwner(
      sourceIdentity: owner.sourceIdentity,
      sectionIdentity: owner.sectionIdentity,
      sourceOrdinalHint: owner.sourceOrdinalHint,
      textOffsetUtf16: 0,
    );
  }

  CanonicalPaginationOperationControls _canonicalOperation(
    DisplayRangeTaskPriority priority,
  ) => canonicalOperationForP04(priority: priority);

  DisplayRangeResult _displayResult({
    required CanonicalReaderPaginationPathResult outcome,
    required DisplayRangeRequest request,
    required int publicationStart,
  }) {
    if (outcome is! CanonicalReaderPaginationPathAccepted) {
      final detail = outcome is CanonicalReaderPaginationPathRejected
          ? '${outcome.rejection.reason}: ${outcome.rejection.message}'
          : outcome is CanonicalReaderRequiredEarlierRestart
          ? outcome.message
          : outcome is CanonicalReaderBackwardPreparationPending
          ? '${outcome.message}; work=${outcome.boundedWorkEntriesConsumed}; '
                'cards=${outcome.diagnostics.cardsFinalized}'
          : '$outcome';
      throw StateError('Canonical production path rejected: $detail');
    }
    final result = canonicalPathDisplayResult(
      accepted: outcome,
      request: request,
      publicationStart: publicationStart,
    );
    for (var index = 0; index < result.displayChunks.length; index++) {
      _finalizedCardsByDigest[canonicalBookChunkOwnershipDigest(
            result.displayChunks[index],
          )] =
          outcome.publishableCards[index];
    }
    return result;
  }

  Future<void> _appendCanonicalToEnd({
    required CanonicalReaderPaginationSession canonical,
    required ProgressiveDisplayState state,
    required List<DisplayRangeResult> results,
    required List<String>? requested,
    required String reason,
    int? targetOriginalIndex,
  }) async {
    for (var operation = 0; operation < 64; operation++) {
      final lastCard = state.displayChunks.last;
      final lastSources = state.displayToOriginal.last;
      final boundary = canonical.publishedSuffixBoundary(
        card: lastCard,
        sourceOrdinals: lastSources,
      );
      if (boundary == null) {
        throw StateError('Published suffix did not match canonical output.');
      }
      final outcome = await canonical.generateForward(
        acceptedPublishedSuffix: boundary,
        operation: _canonicalOperation(
          DisplayRangeTaskPriority.speculativeLookahead,
        ),
      );
      if (outcome is! CanonicalReaderPaginationPathAccepted) {
        final detail = outcome is CanonicalReaderPaginationPathRejected
            ? '${outcome.rejection.reason}: ${outcome.rejection.message}'
            : outcome is CanonicalReaderRequiredEarlierRestart
            ? outcome.message
            : '$outcome';
        throw StateError('Canonical forward path rejected: $detail');
      }
      final start = state.ranges.last.sourceRange.endExclusive;
      if (outcome.publishableCards.isNotEmpty) {
        final request = DisplayRangeRequest(
          direction: DisplayRangeDirection.forward,
          sourceRange: SourceChunkRange(start, sourceChunks.length),
          generationId: _generation,
          reason: '${reason}_$operation',
          targetOriginalIndex: targetOriginalIndex,
        );
        final result = _displayResult(
          outcome: outcome,
          request: request,
          publicationStart: start,
        );
        results.add(result);
        requested?.add(result.request.sourceRange.toString());
        state.append(result);
      }
      if (outcome is CanonicalReaderLogicalEnd) return;
    }
    throw StateError('Canonical forward generation did not reach logical end.');
  }

  Future<void> _prependCanonicalBoundedToStart({
    required CanonicalReaderPaginationSession canonical,
    required ProgressiveDisplayState state,
    required List<DisplayRangeResult> results,
    required List<String>? requested,
    required String reason,
    required int committedSourceIndex,
  }) async {
    var window = 0;
    while (state.ranges.first.sourceRange.start > 0) {
      final desiredStart = math.max(
        0,
        state.ranges.first.sourceRange.start - 4,
      );
      await _prependCanonicalToStart(
        canonical: canonical,
        state: state,
        results: results,
        requested: requested,
        reason: '${reason}_${window++}',
        committedSourceIndex: committedSourceIndex,
        desiredStart: desiredStart,
      );
    }
  }

  Future<void> _prependCanonicalToStart({
    required CanonicalReaderPaginationSession canonical,
    required ProgressiveDisplayState state,
    required List<DisplayRangeResult> results,
    required List<String>? requested,
    required String reason,
    required int committedSourceIndex,
    int desiredStart = 0,
  }) async {
    final range = SourceChunkRange(
      desiredStart,
      state.ranges.first.sourceRange.start,
    );
    if (range.isEmpty) return;
    final committedDisplay = readerDisplayIndexContainingSourceOffset(
      displayChunks: state.displayChunks,
      originalChunkIndex: committedSourceIndex,
      textOffset: 0,
    );
    if (committedDisplay == null) {
      throw StateError('Committed target is absent before backward work.');
    }
    final prefix = canonical.acceptedPublishedCard(
      card: state.displayChunks.first,
      sourceOrdinals: state.displayToOriginal.first,
    );
    final committed = canonical.acceptedPublishedCard(
      card: state.displayChunks[committedDisplay],
      sourceOrdinals: state.displayToOriginal[committedDisplay],
    );
    if (prefix == null || committed == null) {
      throw StateError('Published canonical evidence is unavailable.');
    }
    final successorStart = canonical.acceptedSuccessorStartCursorFor(committed);
    if (successorStart == null) {
      throw StateError('Committed successor cursor is unavailable.');
    }
    final outcome = await canonical.generateBackward(
      desiredPredecessor: _canonicalTarget(canonical, range.start),
      acceptedPublishedPrefix: prefix,
      committedCurrentCard: committed,
      acceptedSuccessorStartCursor: successorStart,
      operation: _canonicalOperation(
        DisplayRangeTaskPriority.speculativeLookahead,
      ),
    );
    final result = _displayResult(
      outcome: outcome,
      request: DisplayRangeRequest(
        direction: DisplayRangeDirection.backward,
        sourceRange: range,
        generationId: _generation,
        reason: reason,
        targetOriginalIndex: committedSourceIndex,
      ),
      publicationStart: range.start,
    );
    results.add(result);
    requested?.add(result.request.sourceRange.toString());
    state.prepend(result);
  }

  Future<void> _seedCanonicalRestartBeforeTarget(
    CanonicalReaderPaginationSession canonical,
    int target,
  ) async {
    final seedThrough = math.max(0, target - 1);
    CanonicalPaginationRestart restart =
        const CanonicalPaginationPublicationStart();
    for (var operation = 0; operation < 16; operation++) {
      final remaining =
          seedThrough -
          (restart is CanonicalPaginationContinuation
              ? restart.nextSourceCursor.sourceOrdinalHint
              : 0);
      if (remaining <= 0) return;
      final outcome = await canonical.generateInitial(
        restart: restart,
        operation: _canonicalOperation(
          DisplayRangeTaskPriority.speculativeLookahead,
        ),
        budget: CanonicalPaginationWorkBudget(
          maxSourceChunks: remaining.clamp(
            1,
            CanonicalPaginationBounds.checkpointSourceStride,
          ),
        ),
      );
      if (outcome is! CanonicalReaderPaginationPathAccepted) {
        throw StateError('Unable to seed bounded target restart: $outcome');
      }
      restart = outcome.continuation;
      if (restart.terminal) return;
    }
    throw StateError('Bounded target restart seeding did not converge.');
  }

  ProgressiveDisplayState _newState() => ProgressiveDisplayState(
    signature: DisplayGenerationSignature(
      bookId: bookId,
      parsedContentVersion: 1,
      layoutSignature: layoutIdentity,
      settingsSignature: 'p03-default-reading-settings',
      viewportSignature: environment.inputs.diagnosticJson,
      cacheKey: stateCacheKey,
    ),
    sourceChunkCount: sourceChunks.length,
  );

  ReaderPaginationConstruction _construction({
    required String label,
    required ProgressiveDisplayState state,
    required List<DisplayRangeResult> results,
    required List<String> requestedRanges,
    int? targetSourceIndex,
    ReaderCardPaginationEvidence? initialEvidence,
  }) => ReaderPaginationConstruction(
    label: label,
    layoutIdentity: layoutIdentity,
    requestedRanges: List<String>.unmodifiable(requestedRanges),
    state: state,
    evidence: _projectState(state),
    results: List<DisplayRangeResult>.unmodifiable(results),
    targetSourceIndex: targetSourceIndex,
    initialEvidence: initialEvidence,
  );

  ReaderCardPaginationEvidence _projectState(ProgressiveDisplayState state) {
    final finalized = state.canonicalCards.length == state.displayChunks.length
        ? state.canonicalCards
        : _finalizedCardsForState(state);
    return ReaderCardPaginationEvidence.projectSnapshot(
      requestedSourceRange: '[0,${sourceChunks.length})',
      displayChunks: state.displayChunks,
      displayToOriginal: state.displayToOriginal,
      sourceChunks: sourceChunks,
      readableSourceExtents: readerCoreReadableSourceExtents,
      publicationFingerprint: publicationFingerprint,
      layoutFingerprint: layoutIdentity,
      cardIdentities: finalized.length == state.displayChunks.length
          ? finalized.map((card) => card.identity).toList()
          : null,
    );
  }

  List<CanonicalFinalizedReaderCard> _finalizedCardsForState(
    ProgressiveDisplayState state,
  ) => <CanonicalFinalizedReaderCard>[
    for (final card in state.displayChunks)
      if (_finalizedCardsByDigest[canonicalBookChunkOwnershipDigest(card)]
          case final finalized?)
        finalized,
  ];

  void _validatePartitions(List<SourceChunkRange> partitions) {
    if (partitions.isEmpty ||
        partitions.first.start != 0 ||
        partitions.last.endExclusive != sourceChunks.length) {
      throw ArgumentError('Partitions must cover the complete source range.');
    }
    for (var index = 1; index < partitions.length; index++) {
      if (!partitions[index].isAdjacentAfter(partitions[index - 1])) {
        throw ArgumentError('Partitions must be ordered and adjacent.');
      }
    }
  }
}

String? compareConstructionToFull({
  required String scenario,
  required ReaderPaginationConstruction full,
  required ReaderPaginationConstruction actual,
}) {
  return readerCardPaginationEvidenceMismatch(
    scenario: scenario,
    constructionLabel: actual.label,
    controlledLayoutIdentity: actual.layoutIdentity,
    requestedRanges: actual.requestedRanges,
    targetSourceIndex: actual.targetSourceIndex,
    expected: full.evidence,
    actual: actual.evidence,
  );
}

String compactConstructionMismatchEvidence({
  required String failureId,
  required ReaderPaginationConstruction full,
  required ReaderPaginationConstruction actual,
}) =>
    '$failureId|${readerCardPaginationCompactMismatch(expected: full.evidence, actual: actual.evidence)}';

String describeSingletonOutcome({
  required ReaderPaginationConstruction full,
  required ReaderPaginationConstruction actual,
}) {
  final target = actual.targetSourceIndex!;
  final initial = actual.initialEvidence!;
  ReaderCardEvidence? cardFor(
    ReaderCardPaginationEvidence evidence,
    int sourceIndex,
  ) {
    for (final card in evidence.cards) {
      if (card.sourceRanges.any((range) => range.sourceIndex == sourceIndex)) {
        return card;
      }
    }
    return null;
  }

  String membership(ReaderCardEvidence? card) => card == null
      ? 'missing'
      : card.sourceRanges
            .map(
              (range) =>
                  '${range.sourceIndex}:'
                  '[${range.sourceStartUtf16},${range.sourceEndUtf16})',
            )
            .join(',');
  final singletonCard = cardFor(initial, target);
  final finalCard = cardFor(actual.evidence, target);
  final referenceCard = cardFor(full.evidence, target);
  final initialMembership = membership(singletonCard);
  final finalMembership = membership(finalCard);
  final referenceMembership = membership(referenceCard);
  final finalIndex = finalCard == null
      ? -1
      : actual.evidence.cards.indexOf(finalCard);
  final predecessor = finalIndex > 0
      ? membership(actual.evidence.cards[finalIndex - 1])
      : 'none';
  final successor =
      finalIndex >= 0 && finalIndex + 1 < actual.evidence.cards.length
      ? membership(actual.evidence.cards[finalIndex + 1])
      : 'none';
  return 'singleton target=$target; initialMembership=$initialMembership; '
      'finalMembership=$finalMembership; '
      'referenceMembership=$referenceMembership; '
      'membershipChanged=${initialMembership != finalMembership}; '
      'initialMembershipRetained=${initialMembership == finalMembership}; '
      'independentlyFlushedIsland=${initialMembership == finalMembership && finalMembership != referenceMembership}; '
      'identityInitial=${singletonCard?.identity.signature}; '
      'identityFinal=${finalCard?.identity.signature}; '
      'identityReference=${referenceCard?.identity.signature}; '
      'identityDiffersFromReference=${finalCard?.identity.signature != referenceCard?.identity.signature}; '
      'predecessor=$predecessor; successor=$successor; '
      'coverageDuplicates=${actual.evidence.coverage.duplicates}; '
      'coverageOverlaps=${actual.evidence.coverage.overlaps}';
}

void expectReaderCoreStructuralInvariants(
  ReaderPaginationConstruction construction,
) {
  final evidence = construction.evidence;
  expect(evidence.coverage.complete, isTrue, reason: evidence.describe());
  final compressedOrder = <int>[];
  for (final range in evidence.cards.expand((card) => card.sourceRanges)) {
    if (compressedOrder.isEmpty || compressedOrder.last != range.sourceIndex) {
      compressedOrder.add(range.sourceIndex);
    }
  }
  expect(compressedOrder, List<int>.generate(20, (index) => index));

  final expectedOwners = <int, (String, String, String)>{
    0: ('nav.xhtml', 'nav.xhtml#list-0#item-0#block-0', 'paragraph'),
    1: ('nav.xhtml', 'nav.xhtml#list-0#item-1#block-0', 'paragraph'),
    2: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#paragraph-0',
      'heading',
    ),
    3: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#paragraph-1',
      'heading',
    ),
    8: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#paragraph-6',
      'paragraph',
    ),
    9: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#list-0#item-0#block-0',
      'paragraph',
    ),
    10: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#list-0#item-1#block-0',
      'paragraph',
    ),
    11: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#paragraph-9',
      'table',
    ),
    12: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#paragraph-10',
      'paragraph',
    ),
    13: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#paragraph-11',
      'paragraph',
    ),
    14: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#paragraph-12',
      'paragraph',
    ),
    15: (
      'text/chapter-one.xhtml',
      'text/chapter-one.xhtml#paragraph-13',
      'paragraph',
    ),
    16: (
      'text/chapter-two.xhtml',
      'text/chapter-two.xhtml#paragraph-0',
      'heading',
    ),
    17: (
      'text/chapter-two.xhtml',
      'text/chapter-two.xhtml#paragraph-1',
      'paragraph',
    ),
    18: (
      'text/chapter-two.xhtml',
      'text/chapter-two.xhtml#paragraph-2',
      'paragraph',
    ),
    19: (
      'text/chapter-two.xhtml',
      'text/chapter-two.xhtml#paragraph-3',
      'paragraph',
    ),
  };
  for (final card in evidence.cards) {
    for (final range in card.sourceRanges) {
      final owner = expectedOwners[range.sourceIndex];
      if (owner == null) continue;
      expect(
        (range.sectionIdentity, range.logicalBlockId, range.structuralType),
        owner,
        reason: evidence.describe(),
      );
    }
  }

  List<BookChunk> cardsFor(int sourceIndex) => construction.state.displayChunks
      .where(
        (card) => card.effectiveSourceRanges.any(
          (range) => range.originalChunkIndex == sourceIndex,
        ),
      )
      .toList(growable: false);

  for (final sourceIndex in const [2, 3, 16]) {
    expect(cardsFor(sourceIndex).every((card) => card.isHeading), isTrue);
  }
  final repeatedOne = evidence.cards.singleWhere(
    (card) => card.sourceRanges.any((range) => range.sourceIndex == 8),
  );
  final repeatedTwo = evidence.cards.singleWhere(
    (card) => card.sourceRanges.any((range) => range.sourceIndex == 18),
  );
  expect(
    repeatedOne.visibleText,
    contains('The repeated marker appears here.'),
  );
  expect(
    repeatedTwo.visibleText,
    contains('The repeated marker appears here.'),
  );
  expect(
    repeatedOne.sourceRanges
        .singleWhere((range) => range.sourceIndex == 8)
        .logicalBlockId,
    isNot(
      repeatedTwo.sourceRanges
          .singleWhere((range) => range.sourceIndex == 18)
          .logicalBlockId,
    ),
  );

  expect(
    cardsFor(9).every((card) => card.effectiveListDisplaySegments.isNotEmpty),
    isTrue,
  );
  expect(
    cardsFor(10).every((card) => card.effectiveListDisplaySegments.isNotEmpty),
    isTrue,
  );
  final table = cardsFor(11).single;
  expect(table.blockRole, BookBlockRole.table);
  final tableEvidence = evidence.cards.singleWhere(
    (card) => card.sourceRanges.any((range) => range.sourceIndex == 11),
  );
  expect(tableEvidence.visibleText, 'Column Value North Seven');

  final inline = cardsFor(12).single;
  expect(inline.inlineStyles, isNotEmpty);
  expect(inline.text, contains('bold token'));
  expect(inline.text, contains('italic token'));
  expect(cardsFor(0).single.links, isNotEmpty);
  final link = cardsFor(13).single;
  expect(link.footnotes, isNotEmpty);
  expect(link.text, contains('[linked note]'));
  expect(
    cardsFor(14).single.text,
    contains('Footnote body from the first section.'),
  );

  expect(cardsFor(15).single.sourceFile, 'text/chapter-one.xhtml');
  expect(cardsFor(16).single.sourceFile, 'text/chapter-two.xhtml');
  expect(cardsFor(17).single.sourceFile, 'text/chapter-two.xhtml');
}
