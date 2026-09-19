import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/reader_screen.dart'
    show readerDisplayIndexContainingSourceOffset;
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new-contract full/target/forward/backward construction smoke', () async {
    final sources = <BookChunk>[
      for (var index = 0; index < 8; index++)
        BookChunk(
          index: index,
          type: BookChunkType.text,
          sourceFile: 'chapter-${index ~/ 10}.xhtml',
          logicalParagraphId: 'paragraph-$index',
          text: 'Stable source $index keeps exact UTF-16 ownership.',
        ),
    ];
    final keys = <CanonicalPaginationSourceKey>[
      for (var index = 0; index < sources.length; index++)
        CanonicalPaginationSourceKey(
          sourceIdentity: '${sources[index].sourceFile}|paragraph-$index|text',
          sectionIdentity: sources[index].sourceFile!,
          spineIdentity: sources[index].sourceFile!,
          sourceOrdinalHint: index,
        ),
    ];
    final snapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: 'p05-layout-smoke',
      publicationFingerprint: 'publication-v1',
      parserSourceIdentity: 'parser-v1',
      sourceRevision: readerSha256(
        keys.map((key) => key.sourceIdentity).toList(growable: false),
      ),
      sourceChunks: sources,
      sourceKeys: keys,
    );
    final gate = ReaderFontEvidenceGate();
    final terminal = await gate.capture(
      settings: const ReadingSettings(),
      stableSourceIdentity: 'delivery-source',
      sourceStartUtf16: 0,
      sourceText: sources.first.text!,
      locale: 'en-US',
    );
    expect(terminal, isA<ReaderFontReadyTerminalBundled>());
    final built = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: const Size(390, 360),
        mediaQuerySize: const Size(390, 360),
        viewPadding: const EdgeInsets.fromLTRB(0, 24, 0, 18),
        locale: const Locale('en', 'US'),
        defaultDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        settings: const ReadingSettings(),
        fontOutcome: terminal,
        captureFreshnessEvidence: 'generation-1',
        publicationFingerprint: snapshot.publicationFingerprint,
        parserSourceSchemaIdentity: snapshot.parserSourceIdentity,
        sourceRevision: snapshot.sourceRevision,
        sourceSnapshotDigest: snapshot.snapshotDigest,
      ),
    );
    expect(built, isA<ReaderLayoutContractReady>());
    final contract = (built as ReaderLayoutContractReady).contract;

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
        final outcome = gate.capturePrepared(
          settings: const ReadingSettings(),
          stableSourceIdentity: '$owner|$start:$end',
          sourceStartUtf16: start,
          sourceText: text.substring(start, end),
          locale: 'en-US',
        );
        if (outcome is! ReaderFontReadyTerminalBundled) {
          throw StateError('No font authority: ${outcome.type.name}');
        }
        result.add(outcome.sourceEvidence);
        start = end;
      } while (start < text.length);
      return result;
    }

    final body = contract.typography[ReaderLayoutTextRole.body];
    final heading = contract.typography[ReaderLayoutTextRole.heading];
    final layout = ReaderCardPaginatorLayout(
      availableWidth: contract.geometry.bodySize.width,
      pageHeightBudget: contract.geometry.ordinaryPaginationHeightBudget,
      physicalTextBudget: contract.geometry.publisherPaginationHeightBudget,
      minUsefulHeight: contract.geometry.minUsefulHeight,
      tinyWordCount: contract.settingsPolicy.densityTinyWordCount,
      tinyHeightRatio: contract.settingsPolicy.densityTinyHeightRatio,
      settings: const ReadingSettings(),
      bodyStyle: body.toTextStyle(),
      headingStyle: heading.toTextStyle(),
      bodyStrut: body.toStrutStyle(),
      headingStrut: heading.toStrutStyle(),
      textScaler: TextScaler.noScaling,
      contract: contract,
      fontEvidenceResolver: evidence,
    );

    var generation = 0;
    final scheduler = FrameBudgetedRangeScheduler(yieldToFrame: () async {});
    addTearDown(scheduler.dispose);

    CanonicalPaginationOperationControls operation(
      DisplayRangeTaskPriority priority,
    ) {
      final current = ++generation;
      return CanonicalPaginationOperationControls(
        generationToken: current,
        scheduler: scheduler,
        priority: priority,
        isCancelled: () => false,
        currentGenerationToken: () => current,
        diagnosticBookId: 'p05-layout-smoke',
      );
    }

    CanonicalReaderPaginationSession session() =>
        CanonicalReaderPaginationSession(
          sourceSnapshot: snapshot,
          controlledLayoutIdentity: contract.identity,
          layout: layout,
        );

    CanonicalPaginationTargetCursor target(
      CanonicalReaderPaginationSession value,
      int ordinal,
    ) {
      final owner = snapshot.ownerAt(ordinal);
      return value.targetForStableOwner(
        sourceIdentity: owner.sourceIdentity,
        sectionIdentity: owner.sectionIdentity,
        sourceOrdinalHint: ordinal,
        textOffsetUtf16: 0,
      );
    }

    ProgressiveDisplayState state() => ProgressiveDisplayState(
      signature: DisplayGenerationSignature(
        bookId: 'p05-layout-smoke',
        parsedContentVersion: 1,
        layoutSignature: contract.identity,
        settingsSignature: 'settings',
        viewportSignature: '390x360',
        cacheKey: 'no-cache',
      ),
      sourceChunkCount: sources.length,
    );

    DisplayRangeResult display(
      CanonicalReaderPaginationPathAccepted accepted,
      DisplayRangeDirection direction,
      int start,
      String reason,
    ) => canonicalPathDisplayResult(
      accepted: accepted,
      request: DisplayRangeRequest(
        direction: direction,
        sourceRange: SourceChunkRange(start, sources.length),
        generationId: generation,
        reason: reason,
      ),
      publicationStart: start,
    );

    Future<void> appendToEnd(
      CanonicalReaderPaginationSession canonical,
      ProgressiveDisplayState output,
    ) async {
      for (var attempt = 0; attempt < 64; attempt++) {
        final boundary = canonical.publishedSuffixBoundary(
          card: output.displayChunks.last,
          sourceOrdinals: output.displayToOriginal.last,
        );
        expect(boundary, isNotNull);
        final outcome = await canonical.generateForward(
          acceptedPublishedSuffix: boundary!,
          operation: operation(DisplayRangeTaskPriority.speculativeLookahead),
        );
        expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
        final accepted = outcome as CanonicalReaderPaginationPathAccepted;
        if (accepted.publishableCards.isNotEmpty) {
          final start = output.ranges.last.sourceRange.endExclusive;
          output.append(
            display(
              accepted,
              DisplayRangeDirection.forward,
              start,
              'forward-$attempt',
            ),
          );
        }
        if (outcome is CanonicalReaderLogicalEnd) return;
      }
      fail('Forward generation did not reach logical end.');
    }

    Future<List<CanonicalFinalizedReaderCard>> fullConstruction() async {
      final canonical = session();
      final output = state();
      final outcome = await canonical.generateInitial(
        restart: const CanonicalPaginationPublicationStart(),
        operation: operation(DisplayRangeTaskPriority.initialVisible),
      );
      expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
      output.publishInitial(
        display(
          outcome as CanonicalReaderPaginationPathAccepted,
          DisplayRangeDirection.initial,
          0,
          'full',
        ),
      );
      if (outcome is! CanonicalReaderLogicalEnd) {
        await appendToEnd(canonical, output);
      }
      return canonical.acceptedPublishedCards;
    }

    Future<List<CanonicalFinalizedReaderCard>> targetConstruction() async {
      final canonical = session();
      final output = state();
      const targetOrdinal = 4;
      final outcome = await canonical.generateTarget(
        target: target(canonical, targetOrdinal),
        operation: operation(DisplayRangeTaskPriority.directTarget),
      );
      expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
      final accepted = outcome as CanonicalReaderPaginationPathAccepted;
      output.publishInitial(
        display(
          accepted,
          DisplayRangeDirection.target,
          targetOrdinal,
          'target',
        ),
      );
      if (outcome is! CanonicalReaderLogicalEnd) {
        await appendToEnd(canonical, output);
      }

      for (
        var attempt = 0;
        output.ranges.first.sourceRange.start > 0 && attempt < 32;
        attempt++
      ) {
        final committedIndex = readerDisplayIndexContainingSourceOffset(
          displayChunks: output.displayChunks,
          originalChunkIndex: targetOrdinal,
          textOffset: 0,
        );
        expect(committedIndex, isNotNull);
        final prefix = canonical.acceptedPublishedCard(
          card: output.displayChunks.first,
          sourceOrdinals: output.displayToOriginal.first,
        );
        final committed = canonical.acceptedPublishedCard(
          card: output.displayChunks[committedIndex!],
          sourceOrdinals: output.displayToOriginal[committedIndex],
        );
        expect(prefix, isNotNull);
        expect(committed, isNotNull);
        final successor = canonical.acceptedSuccessorStartCursorFor(committed!);
        expect(successor, isNotNull);
        final desired = math.max(0, output.ranges.first.sourceRange.start - 4);
        final backward = await canonical.generateBackward(
          desiredPredecessor: target(canonical, desired),
          acceptedPublishedPrefix: prefix!,
          committedCurrentCard: committed,
          acceptedSuccessorStartCursor: successor!,
          operation: operation(DisplayRangeTaskPriority.speculativeLookahead),
        );
        expect(backward, isA<CanonicalReaderBackwardPreparationAccepted>());
        final acceptedBackward =
            backward as CanonicalReaderBackwardPreparationAccepted;
        output.prepend(
          display(
            acceptedBackward,
            DisplayRangeDirection.backward,
            desired,
            'backward-$attempt',
          ),
        );
      }
      expect(output.ranges.first.sourceRange.start, 0);
      return canonical.acceptedPublishedCards;
    }

    List<String> projection(List<CanonicalFinalizedReaderCard> cards) => [
      for (final value in cards)
        '${value.sourceSlices.map((slice) => slice.toCanonicalJson()).join()}|'
            '${value.identity.signature}|'
            '${value.resolvedLayout?.physicalLayoutCompositeFingerprint}',
    ];

    final full = await fullConstruction();
    final repeatedForward = await fullConstruction();
    final targetFirst = await targetConstruction();
    expect(projection(repeatedForward), projection(full));
    expect(projection(targetFirst), projection(full));
    expect(full.every((value) => value.resolvedLayout != null), isTrue);
    final orderedOrdinals = <int>[
      for (final value in full)
        for (final slice in value.sourceSlices) slice.sourceOrdinalHint,
    ];
    expect(orderedOrdinals, orderedEquals(List.generate(8, (i) => i)));
  });
}
