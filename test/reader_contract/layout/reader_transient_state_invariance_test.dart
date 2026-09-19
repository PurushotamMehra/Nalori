// ignore_for_file: avoid_redundant_argument_values, prefer_const_constructors

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nalori/controllers/speed_read_controller.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/services/reader_character_match_service.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';
import 'package:nalori/widgets/reading_card.dart';
import 'package:nalori/widgets/reading_card_deck.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'U-10 active/preview/Speed Reader states preserve current contract geometry',
    (tester) async {
      final fixture = await _P05Fixture.create();
      addTearDown(fixture.dispose);
      final candidate = await fixture.generateCandidate(fixture.contract, 1);
      final publication = fixture.publicationState(fixture.contract);
      final accepted = publication.publishCanonical(
        fixture.publicationRequest(candidate, generation: 1),
      );
      expect(accepted, isA<CanonicalDisplayPublicationAccepted>());
      expect(candidate.session.commitPublication(candidate.accepted), isTrue);

      final baseline = fixture.evidence(publication);
      final key = GlobalKey<_TransientReaderHarnessState>();
      final entries = fixture.entriesFor(fixture.contract);
      await tester.pumpWidget(
        _TransientReaderHarness(
          key: key,
          contract: fixture.contract,
          entries: entries,
        ),
      );
      final state = key.currentState!;
      final previewSize = _paragraphSize(tester, 1);
      final activeSize = _paragraphSize(tester, 0);

      state.setControlsVisible(true);
      await tester.pump();
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 0), activeSize);

      state.setKeyboardInset(240);
      await tester.pump();
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 0), activeSize);

      state.setActiveIndex(1);
      await tester.pump();
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 1), previewSize);
      expect(find.byType(SelectionArea), findsWidgets);

      state.setDecorationsEnabled(true);
      await tester.pump();
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 1), previewSize);

      state.setStructuralReservationValues(
        bookmark: Bookmark(
          chunkIndex: 1,
          originalStartOffset: 0,
          name: 'Transient bookmark',
          createdAt: DateTime.utc(2026, 9, 10),
          colorIndex: 2,
        ),
        chapterTitle: 'Changed chapter label',
        chapterPageLabel: '99 of 99',
        chapterProgress: 0.99,
      );
      await tester.pump();
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 1), previewSize);

      state.speedReadController.start(entries[1].chunk.text!, 1);
      state.speedReadController.pause();
      state.speedReadController.setWPM(420);
      state.speedReadController.jumpToWord(2);
      await tester.pump();
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 1), previewSize);

      state.setSpeedReadDisplayMode(SpeedReadDisplayMode.lyrics);
      await tester.pump();
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 1), previewSize);

      state.setSpeedReadDisplayMode(SpeedReadDisplayMode.window);
      await tester.pump();
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 1), previewSize);

      final navigation = state.deckController.startNavigation(
        0,
        Duration.zero,
        Curves.linear,
      );
      expect(navigation.started, isTrue);
      await tester.pump();
      expect(await navigation.completed, isTrue);
      _expectUnchanged(fixture.evidence(publication), baseline);
      expect(_paragraphSize(tester, 0), activeSize);
      expect(find.byType(Transform), findsWidgets);

      state.setControlsVisible(false);
      await tester.pump();
      state.setKeyboardInset(0);
      await tester.pump();
      state.setDecorationsEnabled(false);
      await tester.pump();
      state.speedReadController.stop();
      await tester.pump();
      final firstRepeat = fixture.evidence(publication);
      _expectUnchanged(firstRepeat, baseline);

      state.setControlsVisible(true);
      await tester.pump();
      state.setKeyboardInset(240);
      await tester.pump();
      state.setControlsVisible(false);
      await tester.pump();
      state.setKeyboardInset(0);
      await tester.pump();
      expect(fixture.evidence(publication), firstRepeat);

      expect(state.transientTransitionCount, 14);
      expect(fixture.paginationOperationsAfterInitialPublication, 0);
      expect(fixture.publicationAuthorityChangesAfterInitialPublication, 0);
      // ignore: avoid_print
      print(
        'P05_TRANSIENT_MAX contract=${fixture.maximumContractBytes} '
        'block=${fixture.maximumBlockBytes} card=${fixture.maximumCardBytes} '
        'transitions=${state.transientTransitionCount} '
        'transientPagination=${fixture.paginationOperationsAfterInitialPublication} '
        'transientAuthority=${fixture.publicationAuthorityChangesAfterInitialPublication}',
      );
    },
  );

  test(
    'REQ-014/REQ-016 stable viewPadding changes are genuine while viewInsets are excluded',
    () async {
      final fixture = await _P05Fixture.create();
      addTearDown(fixture.dispose);
      final base = fixture.contract;
      final bottom = await fixture.buildContract(
        const EdgeInsets.fromLTRB(3, 24, 5, 42),
      );
      final top = await fixture.buildContract(
        const EdgeInsets.fromLTRB(3, 39, 5, 18),
      );
      final left = await fixture.buildContract(
        const EdgeInsets.fromLTRB(17, 24, 5, 18),
      );
      final right = await fixture.buildContract(
        const EdgeInsets.fromLTRB(3, 24, 21, 18),
      );

      expect(bottom.identity, isNot(base.identity));
      expect(
        bottom.geometry.bodySize.height,
        base.geometry.bodySize.height - 24,
      );
      expect(top.identity, isNot(base.identity));
      expect(top.geometry.bodySize.height, base.geometry.bodySize.height - 15);
      expect(left.identity, isNot(base.identity));
      expect(left.geometry.bodySize.width, base.geometry.bodySize.width - 14);
      expect(right.identity, isNot(base.identity));
      expect(right.geometry.bodySize.width, base.geometry.bodySize.width - 16);

      // viewInsets intentionally has no build-input field: identical stable
      // geometry and evidence must therefore build the same immutable contract.
      final sameStableEnvironment = await fixture.buildContract(
        const EdgeInsets.fromLTRB(3, 24, 5, 18),
      );
      expect(sameStableEnvironment.identity, base.identity);
      expect(sameStableEnvironment.geometry.bodySize, base.geometry.bodySize);
      expect(
        sameStableEnvironment.geometry.contentPadding,
        base.geometry.contentPadding,
      );
    },
  );

  testWidgets(
    'U-10 cached deck previews do not survive a genuine contract replacement',
    (tester) async {
      final fixture = await _P05Fixture.create();
      addTearDown(fixture.dispose);
      final key = GlobalKey<_TransientReaderHarnessState>();
      await tester.pumpWidget(
        _TransientReaderHarness(
          key: key,
          contract: fixture.contract,
          entries: fixture.entriesFor(fixture.contract),
        ),
      );
      final oldPadding = fixture.contract.geometry.contentPadding;
      expect(_contentPaddingCount(tester, oldPadding), greaterThan(0));

      final changed = await fixture.buildContract(
        const EdgeInsets.fromLTRB(3, 24, 5, 42),
      );
      key.currentState!.replaceAcceptedLayout(
        changed,
        fixture.entriesFor(changed),
        const EdgeInsets.fromLTRB(3, 24, 5, 42),
      );
      await tester.pump();

      expect(
        _contentPaddingCount(tester, changed.geometry.contentPadding),
        greaterThan(0),
      );
      expect(_contentPaddingCount(tester, oldPadding), 0);
      expect(key.currentState!.staleCachedPreviewCards, 0);
      // ignore: avoid_print
      print('P05_STALE_PREVIEW_MAX 0');
    },
  );

  test(
    'U-10 stale and incomplete candidates preserve accepted publication authority byte-equivalently',
    () async {
      final fixture = await _P05Fixture.create();
      addTearDown(fixture.dispose);
      final first = await fixture.generateCandidate(fixture.contract, 1);
      final state = fixture.publicationState(fixture.contract);
      final initial = state.publishCanonical(
        fixture.publicationRequest(first, generation: 1),
      );
      expect(initial, isA<CanonicalDisplayPublicationAccepted>());
      expect(first.session.commitPublication(first.accepted), isTrue);

      final changed = await fixture.buildContract(
        const EdgeInsets.fromLTRB(3, 24, 5, 42),
      );
      final newer = await fixture.generateCandidate(changed, 2);
      final replacement = state.publishCanonical(
        fixture.publicationRequest(
          newer,
          generation: 2,
          operation: CanonicalDisplayPublicationOperation.replacement,
        ),
      );
      expect(replacement, isA<CanonicalDisplayPublicationAccepted>());
      expect(newer.session.commitPublication(newer.accepted), isTrue);
      final acceptedBytes = _publicationBytes(state);

      final stale = await fixture.generateCandidate(fixture.contract, 3);
      final staleResult = state.publishCanonical(
        fixture.publicationRequest(
          stale,
          generation: 3,
          operation: CanonicalDisplayPublicationOperation.append,
        ),
      );
      expect(
        staleResult.kind,
        CanonicalDisplayPublicationOutcomeKind.staleGenerationOrSession,
      );
      expect(staleResult.hasCacheWriteAuthority, isFalse);
      expect(staleResult.hasCheckpointOrSettlementAuthority, isFalse);
      expect(_publicationBytes(state), acceptedBytes);

      final incompleteResult = state.publishCanonical(
        fixture.publicationRequest(
          newer,
          generation: 2,
          finalizedCards: const <CanonicalFinalizedReaderCard>[],
        ),
      );
      expect(
        incompleteResult.kind,
        CanonicalDisplayPublicationOutcomeKind.provisionalResultRejected,
      );
      expect(incompleteResult.hasCacheWriteAuthority, isFalse);
      expect(incompleteResult.hasCheckpointOrSettlementAuthority, isFalse);
      expect(_publicationBytes(state), acceptedBytes);
    },
  );
}

void _expectUnchanged(_P05Evidence actual, _P05Evidence expected) {
  expect(actual, expected);
}

Size _paragraphSize(WidgetTester tester, int index) {
  final card = find.byKey(ValueKey<String>('p05-card-$index'));
  final paragraph = find.descendant(
    of: card,
    matching: find.byKey(
      const ValueKey<String>('reader-resolved-paragraph-layout'),
    ),
  );
  return tester.getSize(paragraph);
}

int _contentPaddingCount(WidgetTester tester, EdgeInsets expected) => tester
    .widgetList<Padding>(find.byType(Padding))
    .where((padding) => padding.padding == expected)
    .length;

String _publicationBytes(ProgressiveDisplayState state) =>
    canonicalJsonEncode(<String, Object?>{
      'cards': <Object?>[
        for (final card in state.canonicalCards)
          <String, Object?>{
            'identity': card.identity.toJson(),
            'slices': card.sourceSlices
                .map((slice) => slice.toCanonicalJson())
                .toList(growable: false),
          },
      ],
      'continuation': state.acceptedCanonicalContinuation?.canonicalEncoding,
      'authority': state.hasCanonicalCacheWriteAuthority,
    });

final class _P05Fixture {
  _P05Fixture._({
    required this.gate,
    required this.sources,
    required this.snapshot,
    required this.contract,
    required this.settings,
    required this.terminal,
  });

  final ReaderFontEvidenceGate gate;
  final List<BookChunk> sources;
  final CanonicalPaginationSourceSnapshot snapshot;
  final ReaderLayoutContract contract;
  final ReadingSettings settings;
  final ReaderFontReadyTerminalBundled terminal;

  int maximumContractBytes = 0;
  int maximumBlockBytes = 0;
  int maximumCardBytes = 0;
  final int _paginationOperations = 0;
  final int _publicationAuthorityChanges = 0;

  int get paginationOperationsAfterInitialPublication => _paginationOperations;
  int get publicationAuthorityChangesAfterInitialPublication =>
      _publicationAuthorityChanges;

  static Future<_P05Fixture> create() async {
    const settings = ReadingSettings(enableCardDepth: true);
    final sources = <BookChunk>[
      for (var index = 0; index < 3; index++)
        BookChunk(
          index: index,
          type: BookChunkType.text,
          sourceFile: 'chapter-one.xhtml',
          logicalParagraphId: 'p05-paragraph-$index',
          text: 'Source $index retains stable text metrics.',
          links: const <LinkMetadata>[
            LinkMetadata(start: 0, end: 6, url: 'https://example.invalid'),
          ],
        ),
    ];
    final keys = <CanonicalPaginationSourceKey>[
      for (var index = 0; index < sources.length; index++)
        CanonicalPaginationSourceKey(
          sourceIdentity: 'chapter-one.xhtml|p05-paragraph-$index|text',
          sectionIdentity: 'chapter-one.xhtml',
          spineIdentity: 'chapter-one.xhtml',
          sourceOrdinalHint: index,
        ),
    ];
    final snapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: 'p05-transient-invariance',
      publicationFingerprint: 'p05-publication',
      parserSourceIdentity: 'p05-parser',
      sourceRevision: readerSha256(
        keys.map((key) => key.sourceIdentity).toList(growable: false),
      ),
      sourceChunks: sources,
      sourceKeys: keys,
    );
    final gate = ReaderFontEvidenceGate();
    final outcome = await gate.capture(
      settings: settings,
      stableSourceIdentity: 'p05-delivery-source',
      sourceStartUtf16: 0,
      sourceText: sources.first.text!,
      locale: 'en-US',
    );
    expect(outcome, isA<ReaderFontReadyTerminalBundled>());
    final fixture = _P05Fixture._(
      gate: gate,
      sources: sources,
      snapshot: snapshot,
      contract: await _buildContract(
        gate: gate,
        settings: settings,
        snapshot: snapshot,
        terminal: outcome as ReaderFontReadyTerminalBundled,
        padding: const EdgeInsets.fromLTRB(3, 24, 5, 18),
      ),
      settings: settings,
      terminal: outcome,
    );
    fixture.maximumContractBytes = fixture.contract.retainedStateBytes;
    return fixture;
  }

  Future<ReaderLayoutContract> buildContract(EdgeInsets padding) async {
    final built = await _buildContract(
      gate: gate,
      settings: settings,
      snapshot: snapshot,
      terminal: terminal,
      padding: padding,
    );
    maximumContractBytes = math.max(
      maximumContractBytes,
      built.retainedStateBytes,
    );
    return built;
  }

  List<_P05CardEntry> entriesFor(ReaderLayoutContract value) {
    final entries = <_P05CardEntry>[];
    for (final source in sources) {
      final owner = canonicalBookChunkOwnershipDigest(source);
      final block = ReaderBlockLayoutResolver.resolve(
        contract: value,
        chunk: source,
        stableBlockOwner: owner,
        sourceStructureDigestLink: owner,
        fontEvidence: _fontEvidence(value, source, source.text!),
      );
      final card = ReaderCardLayoutResolver.resolve(
        contract: value,
        block: block,
        physicalSourceIdentity: owner,
      );
      maximumBlockBytes = math.max(maximumBlockBytes, block.retainedStateBytes);
      maximumCardBytes = math.max(maximumCardBytes, card.retainedStateBytes);
      entries.add(_P05CardEntry(source, block, card));
    }
    return List<_P05CardEntry>.unmodifiable(entries);
  }

  Future<_P05Candidate> generateCandidate(
    ReaderLayoutContract value,
    int generation,
  ) async {
    final layout = ReaderCardPaginatorLayout(
      availableWidth: value.geometry.bodySize.width,
      pageHeightBudget: value.geometry.ordinaryPaginationHeightBudget,
      physicalTextBudget: value.geometry.publisherPaginationHeightBudget,
      minUsefulHeight: value.geometry.minUsefulHeight,
      tinyWordCount: value.settingsPolicy.densityTinyWordCount,
      tinyHeightRatio: value.settingsPolicy.densityTinyHeightRatio,
      settings: settings,
      bodyStyle: value.typography[ReaderLayoutTextRole.body].toTextStyle(),
      headingStyle: value.typography[ReaderLayoutTextRole.heading]
          .toTextStyle(),
      bodyStrut: value.typography[ReaderLayoutTextRole.body].toStrutStyle(),
      headingStrut: value.typography[ReaderLayoutTextRole.heading]
          .toStrutStyle(),
      textScaler: TextScaler.noScaling,
      contract: value,
      fontEvidenceResolver: (chunk, text) => _fontEvidence(value, chunk, text),
    );
    final scheduler = FrameBudgetedRangeScheduler(yieldToFrame: () async {});
    final session = CanonicalReaderPaginationSession(
      sourceSnapshot: snapshot,
      controlledLayoutIdentity: value.identity,
      layout: layout,
      deferPublicationCommit: true,
    );
    final accepted = await session.generateInitial(
      restart: const CanonicalPaginationPublicationStart(),
      operation: CanonicalPaginationOperationControls(
        generationToken: generation,
        scheduler: scheduler,
        priority: DisplayRangeTaskPriority.initialVisible,
        isCancelled: () => false,
        currentGenerationToken: () => generation,
        diagnosticBookId: 'p05-transient-invariance',
      ),
    );
    scheduler.dispose();
    if (accepted is CanonicalReaderPaginationPathRejected) {
      throw StateError(
        'P05 candidate rejected: ${accepted.rejection.reason}: '
        '${accepted.rejection.message}',
      );
    }
    expect(accepted, isA<CanonicalReaderPaginationPathAccepted>());
    final path = accepted as CanonicalReaderPaginationPathAccepted;
    expect(path.publishableCards, isNotEmpty);
    return _P05Candidate(session, path);
  }

  ProgressiveDisplayState publicationState(ReaderLayoutContract value) =>
      ProgressiveDisplayState(
        signature: DisplayGenerationSignature(
          bookId: snapshot.bookId,
          parsedContentVersion: 1,
          layoutSignature: value.identity,
          settingsSignature: 'p05-settings',
          viewportSignature: '390x420',
          cacheKey: 'p05-no-cache',
        ),
        sourceChunkCount: sources.length,
      );

  CanonicalDisplayPublicationRequest publicationRequest(
    _P05Candidate candidate, {
    required int generation,
    CanonicalDisplayPublicationOperation operation =
        CanonicalDisplayPublicationOperation.initial,
    List<CanonicalFinalizedReaderCard>? finalizedCards,
  }) => CanonicalDisplayPublicationRequest(
    operation: operation,
    sessionIdentity: '${snapshot.snapshotDigest}|$generation',
    generationIdentity: generation,
    currentGenerationIdentity: () => generation,
    sourceSnapshot: snapshot,
    controlledLayoutIdentity: candidate.session.controlledLayoutIdentity,
    paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
    finalizedCards: finalizedCards ?? candidate.accepted.publishableCards,
    continuation: candidate.accepted.continuation,
    targetContainment: candidate.accepted.targetContainment,
    isCancelled: () => false,
  );

  _P05Evidence evidence(ProgressiveDisplayState state) => _P05Evidence(
    contractIdentity: contract.identity,
    bodySize: contract.geometry.bodySize,
    contentPadding: contract.geometry.contentPadding,
    orderedBlockLayouts: entriesFor(contract)
        .map((entry) => entry.block.blockLayoutFingerprint)
        .toList(growable: false),
    resolvedLayouts: entriesFor(contract)
        .map((entry) => entry.card.physicalLayoutCompositeFingerprint)
        .toList(growable: false),
    orderedSourceSlices: <String>[
      for (final card in state.canonicalCards)
        for (final slice in card.sourceSlices)
          canonicalJsonEncode(slice.toCanonicalJson()),
    ],
    physicalCardSignatures: state.canonicalCards
        .map((card) => card.identity.signature)
        .toList(growable: false),
  );

  List<ReaderSourceFontMetricEvidence> _fontEvidence(
    ReaderLayoutContract value,
    BookChunk chunk,
    String text,
  ) {
    final owner = canonicalBookChunkOwnershipDigest(chunk);
    final evidence = <ReaderSourceFontMetricEvidence>[];
    var start = 0;
    do {
      final end = math.min(
        text.length,
        start + ReaderSourceFontProbePlan.maximumSourceSliceUtf16,
      );
      final outcome = gate.capturePrepared(
        settings: settings,
        stableSourceIdentity: '$owner|$start:$end',
        sourceStartUtf16: start,
        sourceText: text.substring(start, end),
        locale: value.environment.locale.tag,
      );
      if (outcome is! ReaderFontReadyTerminalBundled) {
        throw StateError('P05 font evidence rejected: ${outcome.type.name}');
      }
      evidence.add(outcome.sourceEvidence);
      start = end;
    } while (start < text.length);
    return List<ReaderSourceFontMetricEvidence>.unmodifiable(evidence);
  }

  void dispose() {}
}

Future<ReaderLayoutContract> _buildContract({
  required ReaderFontEvidenceGate gate,
  required ReadingSettings settings,
  required CanonicalPaginationSourceSnapshot snapshot,
  required ReaderFontReadyTerminalBundled terminal,
  required EdgeInsets padding,
}) async {
  final built = ReaderLayoutContractBuilder.build(
    ReaderLayoutContractBuildInput(
      deckSize: const Size(390, 420),
      mediaQuerySize: const Size(390, 420),
      viewPadding: padding,
      locale: const Locale('en', 'US'),
      defaultDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      settings: settings,
      fontOutcome: terminal,
      captureFreshnessEvidence: 'p05-generation',
      publicationFingerprint: snapshot.publicationFingerprint,
      parserSourceSchemaIdentity: snapshot.parserSourceIdentity,
      sourceRevision: snapshot.sourceRevision,
      sourceSnapshotDigest: snapshot.snapshotDigest,
    ),
  );
  expect(built, isA<ReaderLayoutContractReady>());
  return (built as ReaderLayoutContractReady).contract;
}

final class _P05Candidate {
  const _P05Candidate(this.session, this.accepted);

  final CanonicalReaderPaginationSession session;
  final CanonicalReaderPaginationPathAccepted accepted;
}

final class _P05CardEntry {
  const _P05CardEntry(this.chunk, this.block, this.card);

  final BookChunk chunk;
  final ResolvedReaderBlockLayout block;
  final ResolvedReaderCardLayout card;
}

final class _P05Evidence {
  const _P05Evidence({
    required this.contractIdentity,
    required this.bodySize,
    required this.contentPadding,
    required this.orderedBlockLayouts,
    required this.resolvedLayouts,
    required this.orderedSourceSlices,
    required this.physicalCardSignatures,
  });

  final String contractIdentity;
  final Size bodySize;
  final EdgeInsets contentPadding;
  final List<String> orderedBlockLayouts;
  final List<String> resolvedLayouts;
  final List<String> orderedSourceSlices;
  final List<String> physicalCardSignatures;

  @override
  bool operator ==(Object other) =>
      other is _P05Evidence &&
      other.contractIdentity == contractIdentity &&
      other.bodySize == bodySize &&
      other.contentPadding == contentPadding &&
      _sameList(other.orderedBlockLayouts, orderedBlockLayouts) &&
      _sameList(other.resolvedLayouts, resolvedLayouts) &&
      _sameList(other.orderedSourceSlices, orderedSourceSlices) &&
      _sameList(other.physicalCardSignatures, physicalCardSignatures);

  @override
  int get hashCode => Object.hash(
    contractIdentity,
    bodySize,
    contentPadding,
    Object.hashAll(orderedBlockLayouts),
    Object.hashAll(resolvedLayouts),
    Object.hashAll(orderedSourceSlices),
    Object.hashAll(physicalCardSignatures),
  );
}

bool _sameList<T>(List<T> first, List<T> second) =>
    first.length == second.length &&
    Iterable<int>.generate(
      first.length,
    ).every((index) => first[index] == second[index]);

final class _TransientReaderHarness extends StatefulWidget {
  const _TransientReaderHarness({
    super.key,
    required this.contract,
    required this.entries,
  });

  final ReaderLayoutContract contract;
  final List<_P05CardEntry> entries;

  @override
  State<_TransientReaderHarness> createState() =>
      _TransientReaderHarnessState();
}

final class _TransientReaderHarnessState
    extends State<_TransientReaderHarness> {
  late ReaderLayoutContract _contract = widget.contract;
  late List<_P05CardEntry> _entries = widget.entries;
  final SpeedReadController speedReadController = SpeedReadController();
  final ReadingCardDeckController deckController = ReadingCardDeckController();
  ReadingSettings _settings = const ReadingSettings(enableCardDepth: true);
  var _controlsVisible = false;
  var _keyboardInset = 0.0;
  var _decorationsEnabled = false;
  var _activeIndex = 0;
  EdgeInsets _viewPadding = const EdgeInsets.fromLTRB(3, 24, 5, 18);
  Bookmark? _bookmark;
  String? _chapterTitle;
  String? _chapterPageLabel;
  double? _chapterProgress;
  int transientTransitionCount = 0;
  int staleCachedPreviewCards = 0;

  @override
  void dispose() {
    speedReadController.stop();
    speedReadController.dispose();
    super.dispose();
  }

  void setControlsVisible(bool value) {
    setState(() {
      _controlsVisible = value;
      transientTransitionCount++;
    });
  }

  void setKeyboardInset(double value) {
    setState(() {
      _keyboardInset = value;
      transientTransitionCount++;
    });
  }

  void setActiveIndex(int value) {
    setState(() {
      _activeIndex = value;
      transientTransitionCount++;
    });
  }

  void setDecorationsEnabled(bool value) {
    setState(() {
      _decorationsEnabled = value;
      transientTransitionCount++;
    });
  }

  void setSpeedReadDisplayMode(SpeedReadDisplayMode value) {
    setState(() {
      _settings = _settings.copyWith(speedReadDisplayMode: value);
      transientTransitionCount++;
    });
  }

  void setStructuralReservationValues({
    required Bookmark bookmark,
    required String chapterTitle,
    required String chapterPageLabel,
    required double chapterProgress,
  }) {
    setState(() {
      _bookmark = bookmark;
      _chapterTitle = chapterTitle;
      _chapterPageLabel = chapterPageLabel;
      _chapterProgress = chapterProgress;
      transientTransitionCount++;
    });
  }

  void replaceAcceptedLayout(
    ReaderLayoutContract value,
    List<_P05CardEntry> entries,
    EdgeInsets viewPadding,
  ) {
    setState(() {
      _contract = value;
      _entries = entries;
      _viewPadding = viewPadding;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: SizedBox(
        width: 390,
        height: 420,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 420),
            viewPadding: _viewPadding,
            viewInsets: EdgeInsets.only(bottom: _keyboardInset),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                Positioned.fill(
                  child: ReadingCardDeck(
                    controller: deckController,
                    currentIndex: _activeIndex,
                    itemCount: _entries.length,
                    cacheCardWidgetsDuringDrag: true,
                    onIndexChanged: (index) =>
                        setState(() => _activeIndex = index),
                    cardBuilder: (context, index, progress, isCurrent) {
                      final entry = _entries[index];
                      return ReadingCard(
                        key: ValueKey<String>('p05-card-$index'),
                        isActivePage: isCurrent && index == _activeIndex,
                        enableTextSelection: isCurrent && index == _activeIndex,
                        chunk: entry.chunk,
                        settings: _settings,
                        layoutContract: _contract,
                        resolvedLayout: entry.card,
                        speedReadController: isCurrent
                            ? speedReadController
                            : null,
                        bookmark: _bookmark,
                        chapterTitle: _chapterTitle,
                        chapterPageLabel: _chapterPageLabel,
                        chapterProgress: _chapterProgress,
                        depthLiftProgress: progress,
                        showStackLayers: false,
                        highlights: _decorationsEnabled
                            ? <Highlight>[
                                Highlight(
                                  id: 'p05-highlight-$index',
                                  originalChunkIndex: entry.chunk.index,
                                  startOffset: 0,
                                  endOffset: 6,
                                  text: 'Source',
                                  createdAt: DateTime.utc(2026, 9, 10),
                                ),
                                Highlight(
                                  id: 'p05-note-$index',
                                  originalChunkIndex: entry.chunk.index,
                                  startOffset: 8,
                                  endOffset: 16,
                                  text: 'paragraph',
                                  type: HighlightType.note,
                                  note: 'Paint-only note',
                                  createdAt: DateTime.utc(2026, 9, 10),
                                ),
                              ]
                            : const <Highlight>[],
                        generatedCharacterRanges: _decorationsEnabled
                            ? const <ReaderCharacterDisplayRange>[
                                ReaderCharacterDisplayRange(
                                  declarationId: 'p05-character',
                                  startOffset: 0,
                                  endOffset: 6,
                                  colorValue: 0xFFB266FF,
                                ),
                              ]
                            : const <ReaderCharacterDisplayRange>[],
                      );
                    },
                  ),
                ),
                if (_controlsVisible)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      key: ValueKey<String>('p05-transient-controls'),
                      height: 72,
                      child: ColoredBox(color: Color(0x33000000)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
