import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';

import '../pagination/reader_core_pagination_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('standard fixture records the P05-003 boundary transition', () async {
    final fixture = await ReaderCoreParsedFixture.load(
      'p05-layout-transition-',
    );
    addTearDown(fixture.close);
    final sources = fixture.sourceChunks;
    final keys = <CanonicalPaginationSourceKey>[
      for (var index = 0; index < sources.length; index++)
        CanonicalPaginationSourceKey(
          sourceIdentity:
              '${sources[index].sourceFile}|${sources[index].logicalParagraphId}|${sources[index].type.name}',
          sectionIdentity:
              sources[index].sourceFile ?? sources[index].section.name,
          spineIdentity:
              sources[index].sourceFile ?? sources[index].section.name,
          sourceOrdinalHint: index,
        ),
    ];
    final snapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: readerCoreFixtureId,
      publicationFingerprint: readerCoreFixtureId,
      parserSourceIdentity: 'reader-core-fixture-parser',
      sourceRevision: readerSha256(
        keys.map((key) => key.sourceIdentity).toList(),
      ),
      sourceChunks: sources,
      sourceKeys: keys,
    );
    final gate = ReaderFontEvidenceGate();
    final terminal = await gate.capture(
      settings: const ReadingSettings(),
      stableSourceIdentity: 'transition-delivery',
      sourceStartUtf16: 0,
      sourceText: sources.first.text!,
      locale: 'en-US',
    );
    expect(terminal, isA<ReaderFontReadyTerminalBundled>());
    final outcome = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: const Size(390, 844),
        mediaQuerySize: const Size(390, 844),
        viewPadding: const EdgeInsets.only(top: 24, bottom: 16),
        locale: const Locale('en', 'US'),
        defaultDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        settings: const ReadingSettings(),
        fontOutcome: terminal,
        captureFreshnessEvidence: 'transition-generation',
        publicationFingerprint: snapshot.publicationFingerprint,
        parserSourceSchemaIdentity: snapshot.parserSourceIdentity,
        sourceRevision: snapshot.sourceRevision,
        sourceSnapshotDigest: snapshot.snapshotDigest,
      ),
    );
    final contract = (outcome as ReaderLayoutContractReady).contract;
    final evidenceCache = <String, List<ReaderSourceFontMetricEvidence>>{};

    List<ReaderSourceFontMetricEvidence> evidence(
      BookChunk chunk,
      String text,
    ) {
      final owner = canonicalBookChunkOwnershipDigest(chunk);
      final key = '$owner|${readerSha256(text)}';
      return evidenceCache.putIfAbsent(key, () {
        final values = <ReaderSourceFontMetricEvidence>[];
        var start = 0;
        do {
          final end = math.min(text.length, start + 2048);
          final captured = gate.capturePrepared(
            settings: const ReadingSettings(),
            stableSourceIdentity: '$owner|$start:$end',
            sourceStartUtf16: start,
            sourceText: text.substring(start, end),
            locale: 'en-US',
          );
          if (captured is! ReaderFontReadyTerminalBundled) {
            throw StateError('Missing transition font evidence.');
          }
          values.add(captured.sourceEvidence);
          start = end;
        } while (start < text.length);
        return values;
      });
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
    final scheduler = FrameBudgetedRangeScheduler(yieldToFrame: () async {});
    addTearDown(scheduler.dispose);
    var generation = 0;
    CanonicalPaginationOperationControls operation() {
      final value = ++generation;
      return CanonicalPaginationOperationControls(
        generationToken: value,
        scheduler: scheduler,
        priority: DisplayRangeTaskPriority.initialVisible,
        isCancelled: () => false,
        currentGenerationToken: () => value,
      );
    }

    final session = CanonicalReaderPaginationSession(
      sourceSnapshot: snapshot,
      controlledLayoutIdentity: contract.identity,
      layout: layout,
    );
    var result = await session.generateInitial(
      restart: const CanonicalPaginationPublicationStart(),
      operation: operation(),
    );
    expect(result, isA<CanonicalReaderPaginationPathAccepted>());
    while (result is! CanonicalReaderLogicalEnd) {
      final accepted = result as CanonicalReaderPaginationPathAccepted;
      final boundary = accepted.continuation.previousFinalizedBoundary;
      result = await session.generateForward(
        acceptedPublishedSuffix: boundary,
        operation: operation(),
      );
      expect(result, isA<CanonicalReaderPaginationPathAccepted>());
    }
    final cards = session.acceptedPublishedCards;
    final ranges = <String>[
      for (final card in cards)
        card.sourceSlices
            .map(
              (slice) =>
                  '${slice.sourceOrdinalHint}:${slice.startUtf16 ?? 0}-${slice.endUtf16 ?? 1}',
            )
            .join(','),
    ];
    final signatures = [for (final card in cards) card.identity.signature];
    // ignore: avoid_print
    print('P05_LAYOUT_TRANSITION ranges=${ranges.join(' | ')}');
    // ignore: avoid_print
    print('P05_LAYOUT_TRANSITION signatures=${signatures.join(',')}');
    expect(cards.every((card) => card.resolvedLayout != null), isTrue);
    final covered = <int>[
      for (final card in cards)
        for (final slice in card.sourceSlices) slice.sourceOrdinalHint,
    ];
    expect(
      covered.toSet(),
      containsAll(List.generate(sources.length, (i) => i)),
    );
  });
}
