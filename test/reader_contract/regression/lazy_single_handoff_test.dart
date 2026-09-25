import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/lazy_section_input.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_epub_index_service.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/lazy_snapshot_handoff_service.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';

import '../pagination/reader_core_pagination_harness.dart';
import 'support/lazy_address_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'J01 known successor seals input without a terminal continuation',
    (tester) async {
      final run = await _Run.open(tester);
      expect(run.a.receipt, isNotNull);
      expect(run.a.session.inputExhaustedAwaitingSuccessor, isTrue);
      expect(run.a.session.acceptedSuffix, isNull);
      expect(run.state.acceptedCanonicalContinuation, isNull);
      expect(run.state.generationComplete, isFalse);
      expect(run.a.input.nextCandidate!.spineIndex, 1);
      final receipt = jsonDecode(run.a.receipt!.canonicalEncoding) as Map;
      expect((receipt['sectionEndPosition'] as Map)['kind'], 'sectionEnd');
      expect(
        receipt['emptyFrontierDigest'],
        readerSha256(const CanonicalPaginationFrontier().toCanonicalJson()),
      );
      expect(run.a.session.checkpointIndex.records, isEmpty);
    },
  );

  testWidgets(
    'J02 one adjacent transfer preserves A and atomically appends only B',
    (tester) async {
      final run = await _Run.open(tester);
      final before = run.state.lazyPublication!;
      final bytes = _bytes(run.state);
      final guards = run.a.cardGuards;
      final oldSnapshot = run.a.input.snapshot.snapshotDigest;
      final b = await run.prepareB(tester);
      expect(_bytes(run.state), bytes);
      expect(
        b.session.acceptedPublishedCards.every(
          (c) => c.sourceSlices.every(
            (s) =>
                s.sectionIdentity == b.input.sectionAuthorities.last.sectionKey,
          ),
        ),
        isTrue,
      );
      final handoff = buildLazySnapshotHandoff(old: before, successor: b);
      expect(handoff.fields['previousHandoffDigest'], isNull);
      expect(handoff.fields['handoffOrdinal'], 1);
      final accepted = run.state.publishSnapshotHandoff(
        successor: b,
        handoff: handoff,
        operation: run.operation,
        beforeCommit: () {
          expect(identical(run.state.lazyPublication, before), isTrue);
          expect(_bytes(run.state), bytes);
        },
      );
      expect(accepted.accepted, isTrue, reason: accepted.message);
      expect(run.state.lazyPublication!.revision, 1);
      expect(
        identical(run.state.lazyPublication!.current.session, b.session),
        isTrue,
      );
      expect(run.a.input.snapshot.snapshotDigest, oldSnapshot);
      expect(run.a.session.acceptedSuffix, isNull);
      expect(run.a.receipt, isNotNull);
      expect(
        run.state.canonicalCards.length,
        run.a.cards.length + b.cards.length,
      );
      for (var i = 0; i < run.a.cards.length; i++) {
        expect(identical(run.state.canonicalCards[i], run.a.cards[i]), isTrue);
        expect(lazyCanonicalCardGuard(run.state.canonicalCards[i]), guards[i]);
        expect(
          run.state.lazyPublication!.bodies[i].canonicalEncoding,
          run.a.bodies[i].canonicalEncoding,
        );
        expect(
          () => ReaderLayoutRenderingAdapter.block(
            contract: b.session.layout.contract!,
            card: run.a.cards[i].resolvedLayout!,
          ),
          throwsStateError,
        );
        expect(
          LazyHandoffRenderingAdapter.block(
            retained: run.a,
            cardIndex: i,
            successor: b,
          ),
          same(run.a.cards[i].resolvedLayout!.blocks.single),
        );
      }
      expect(run.state.displayToOriginal.expand((s) => s).toSet(), {
        for (var i = 0; i < b.input.snapshot.sourceCount; i++) i,
      });
      expect(
        run.state.canonicalCards
            .expand((c) => c.sourceSlices)
            .map((s) => s.sourceIdentity)
            .toList(),
        b.input.snapshot.owners.map((s) => s.sourceIdentity).toList(),
      );
      expect(b.continuation!.chainOrdinal, 0);
      expect(b.continuation!.parentDigest, isNull);
      expect(
        b.continuation!.key.sourceSnapshotDigest,
        b.input.snapshot.snapshotDigest,
      );
      expect(run.state.generationComplete, isTrue);
    },
  );

  testWidgets(
    'J03 genuine final section retains valid terminal codec and rejects resume',
    (tester) async {
      final run = await _Run.open(tester);
      final b = await run.prepareB(tester);
      expect(b.receipt, isNull);
      expect(b.input.verifiedBookEnd, isTrue);
      final terminal = b.continuation!;
      expect(terminal.terminal, isTrue);
      expect(terminal.nextSourceCursor.isLogicalEnd, isTrue);
      expect(terminal.frontier.cardCandidateCount, 0);
      expect(
        CanonicalPaginationContinuationCodec.decode(terminal.canonicalEncoding),
        isA<CanonicalPaginationContinuationAccepted>(),
      );
      final resumed = await b.session.generateForward(
        acceptedPublishedSuffix: terminal.previousFinalizedBoundary,
        operation: run.operation.pagination,
      );
      expect(resumed, isA<CanonicalReaderPaginationPathRejected>());
      expect(b.continuation!.canonicalEncoding, terminal.canonicalEncoding);
    },
  );

  for (final change in [
    'cancel-before',
    'cancel-at-commit',
    'switch-at-commit',
    'owner-at-commit',
  ]) {
    testWidgets('J04 $change rejects without publication changes', (
      tester,
    ) async {
      final run = await _Run.open(tester);
      final b = await run.prepareB(tester);
      final old = run.state.lazyPublication!;
      final bytes = _bytes(run.state);
      final h = buildLazySnapshotHandoff(old: old, successor: b);
      if (change == 'cancel-before') run.cancelled = true;
      final result = run.state.publishSnapshotHandoff(
        successor: b,
        handoff: h,
        operation: run.operation,
        beforeCommit: () {
          if (change == 'cancel-at-commit') run.cancelled = true;
          if (change == 'switch-at-commit') {
            run.currentOwner = (bookOpenEpoch: 2, displayOwner: 1, attempt: 0);
          }
          if (change == 'owner-at-commit') {
            run.currentOwner = (bookOpenEpoch: 1, displayOwner: 2, attempt: 0);
          }
        },
      );
      expect(result.accepted, isFalse);
      expect(
        result.outcome,
        change.startsWith('cancel')
            ? LazySnapshotPublicationOutcome.cancelled
            : LazySnapshotPublicationOutcome.stale,
      );
      expect(identical(run.state.lazyPublication, old), isTrue);
      expect(_bytes(run.state), bytes);
    });
  }

  testWidgets('J05 consumed handoff cannot replay or append twice', (
    tester,
  ) async {
    final run = await _Run.open(tester);
    final b = await run.prepareB(tester);
    final h = buildLazySnapshotHandoff(
      old: run.state.lazyPublication!,
      successor: b,
    );
    expect(
      run.state
          .publishSnapshotHandoff(
            successor: b,
            handoff: h,
            operation: run.operation,
          )
          .accepted,
      isTrue,
    );
    final bytes = _bytes(run.state);
    expect(
      run.state
          .publishSnapshotHandoff(
            successor: b,
            handoff: h,
            operation: run.operation,
          )
          .outcome,
      LazySnapshotPublicationOutcome.replayed,
    );
    expect(_bytes(run.state), bytes);
  });

  for (final field in [
    'sectionEndReceiptDigest',
    'acceptedPublicationDigest',
    'prefixOwnersAndRecordsDigest',
    'nextExpectedSourceOwner',
    'firstNewCardSignature',
    'packingIdentity',
    'successorSessionDigest',
  ]) {
    testWidgets(
      'J06 invalid $field latches only that attempt and preserves publication',
      (tester) async {
        final run = await _Run.open(tester);
        final b = await run.prepareB(tester);
        final old = run.state.lazyPublication!;
        final bytes = _bytes(run.state);
        final valid = buildLazySnapshotHandoff(old: old, successor: b);
        final invalid = LazySnapshotHandoffV1({
          ...valid.fields,
          field: 'invalid',
        });
        final result = run.state.publishSnapshotHandoff(
          successor: b,
          handoff: invalid,
          operation: run.operation,
        );
        expect(result.outcome, LazySnapshotPublicationOutcome.invalid);
        expect(_bytes(run.state), bytes);
        expect(identical(run.state.lazyPublication, old), isTrue);
        expect(
          run.state
              .publishSnapshotHandoff(
                successor: b,
                handoff: valid,
                operation: run.operation,
              )
              .outcome,
          LazySnapshotPublicationOutcome.failedAttempt,
        );
      },
    );
  }

  testWidgets(
    'J07 exact prefix rejects changed source records and skipped successor',
    (tester) async {
      final run = await _Run.open(tester, sectionCount: 3);
      final bSection = run.sections[1];
      final aJson = run.sections[0].toJson();
      final chunks = (aJson['chunks'] as List)
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
      chunks[0]['tx'] = 'mutated prefix';
      final changed = ParsedSection.fromJson({...aJson, 'chunks': chunks});
      final bad = LazySectionInput.capture(
        publication: run.publication,
        sections: [changed, bSection],
      );
      expect(() => bad.validateExtensionOf(run.a.input), throwsStateError);
      expect(() => run.a.input.append(run.sections[2]), throwsStateError);
      expect(
        () => run.a.input.append(bSection).append(run.sections[2]),
        throwsStateError,
      );
      expect(run.state.lazyPublication!.revision, 0);
    },
  );

  testWidgets('J08 ordinary append cannot adopt successor root', (
    tester,
  ) async {
    final run = await _Run.open(tester);
    final b = await run.prepareB(tester);
    final bytes = _bytes(run.state);
    final result = run.state.publishCanonical(
      CanonicalDisplayPublicationRequest(
        operation: CanonicalDisplayPublicationOperation.append,
        sessionIdentity: b.sessionDigest,
        generationIdentity: 1,
        currentGenerationIdentity: () => 1,
        sourceSnapshot: b.input.snapshot,
        controlledLayoutIdentity: b.session.controlledLayoutIdentity,
        paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
        finalizedCards: b.cards,
        continuation: b.continuation!,
        isCancelled: () => false,
      ),
    );
    expect(result.accepted, isFalse);
    expect(
      result.kind,
      CanonicalDisplayPublicationOutcomeKind.staleGenerationOrSession,
    );
    expect(_bytes(run.state), bytes);
  });

  testWidgets(
    'J09 successor with another known section emits another receipt, no repeated transfer claim',
    (tester) async {
      final run = await _Run.open(tester, sectionCount: 3);
      final b = await run.prepareB(tester);
      expect(b.receipt, isNotNull);
      expect(b.continuation, isNull);
      final h = buildLazySnapshotHandoff(
        old: run.state.lazyPublication!,
        successor: b,
      );
      expect(
        run.state
            .publishSnapshotHandoff(
              successor: b,
              handoff: h,
              operation: run.operation,
            )
            .accepted,
        isTrue,
      );
      expect(run.state.generationComplete, isFalse);
      expect(run.state.acceptedCanonicalContinuation, isNull);
      expect(b.input.nextCandidate!.spineIndex, 2);
      expect(() => b.input.append(run.sections[2]), throwsStateError);
    },
  );

  testWidgets(
    'J10 rich production EPUB transfers headings, lists and tables without rewriting A',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => ReaderCoreParsedFixture.load('single-rich-'),
      ))!;
      try {
        final run = await _Run.open(tester, fixture: fixture.epubFile);
        final b = await run.prepareB(tester);
        final before = run.a.cardGuards;
        final h = buildLazySnapshotHandoff(
          old: run.state.lazyPublication!,
          successor: b,
        );
        final result = run.state.publishSnapshotHandoff(
          successor: b,
          handoff: h,
          operation: run.operation,
        );
        expect(result.accepted, isTrue, reason: result.message);
        expect(
          run.state.canonicalCards
              .take(before.length)
              .map(lazyCanonicalCardGuard)
              .toList(),
          before,
        );
        validateCompleteSectionCoverage(run.a.input, run.a.cards);
        validateCompleteSectionCoverage(b.input, b.cards);
        expect(run.state.generationComplete, isTrue);
      } finally {
        await tester.runAsync(fixture.close);
      }
    },
  );

  testWidgets('J11 wrong F202 source contract rejects private preparation', (
    tester,
  ) async {
    final run = await _Run.open(tester);
    final bytes = _bytes(run.state);
    await expectLater(
      LazyPreparedSection.prepare(
        input: run.a.input.append(run.sections[1]),
        layout: run.a.session.layout,
        operation: run.operation,
      ),
      throwsStateError,
    );
    expect(_bytes(run.state), bytes);
  });

  testWidgets('J12 stale per-source font evidence rejects transfer', (
    tester,
  ) async {
    final run = await _Run.open(tester);
    final b = await run.prepareB(tester);
    final h = buildLazySnapshotHandoff(
      old: run.state.lazyPublication!,
      successor: b,
    );
    final bytes = _bytes(run.state);
    run.invalidFontEvidence = true;
    final result = run.state.publishSnapshotHandoff(
      successor: b,
      handoff: h,
      operation: run.operation,
    );
    expect(result.outcome, LazySnapshotPublicationOutcome.invalid);
    expect(_bytes(run.state), bytes);
  });

  testWidgets('J13 racing proposals cannot overwrite an accepted transfer', (
    tester,
  ) async {
    final run = await _Run.open(tester);
    final b = await run.prepareB(tester);
    final h = buildLazySnapshotHandoff(
      old: run.state.lazyPublication!,
      successor: b,
    );
    final outer = run.state.publishSnapshotHandoff(
      successor: b,
      handoff: h,
      operation: run.operation,
      beforeCommit: () {
        expect(
          run.state
              .publishSnapshotHandoff(
                successor: b,
                handoff: h,
                operation: run.operation,
              )
              .accepted,
          isTrue,
        );
      },
    );
    expect(outer.outcome, LazySnapshotPublicationOutcome.stale);
    expect(run.state.lazyPublication!.revision, 1);
    expect(
      run.state.canonicalCards.length,
      run.a.cards.length + b.cards.length,
    );
  });

  testWidgets('J14 immutable spine proof ignores later caller index mutation', (
    tester,
  ) async {
    final run = await _Run.open(tester);
    final nextKey = run.a.input.nextCandidate!.stableKey;
    run.originalIndex.spine.removeLast();
    expect(run.publication.successorOf(run.sections.first)!.stableKey, nextKey);
    final b = await run.prepareB(tester);
    final h = buildLazySnapshotHandoff(
      old: run.state.lazyPublication!,
      successor: b,
    );
    expect(
      run.state
          .publishSnapshotHandoff(
            successor: b,
            handoff: h,
            operation: run.operation,
          )
          .accepted,
      isTrue,
    );
  });

  testWidgets('J15 old prepared work cannot be relabelled as a fresh attempt', (
    tester,
  ) async {
    final run = await _Run.open(tester);
    final b = await run.prepareB(tester);
    final h = buildLazySnapshotHandoff(
      old: run.state.lazyPublication!,
      successor: b,
    );
    final bytes = _bytes(run.state);
    const next = (bookOpenEpoch: 1, displayOwner: 1, attempt: 1);
    run.currentOwner = next;
    final operation = LazyHandoffOperation(
      owner: next,
      currentOwner: () => run.currentOwner,
      pagination: run.operation.pagination,
    );
    final result = run.state.publishSnapshotHandoff(
      successor: b,
      handoff: h,
      operation: operation,
    );
    expect(result.outcome, LazySnapshotPublicationOutcome.stale);
    expect(_bytes(run.state), bytes);
    final input = run.a.input.append(run.sections[1]);
    final fresh = await LazyPreparedSection.prepare(
      input: input,
      layout: await run.layout(input),
      operation: operation,
    );
    final valid = buildLazySnapshotHandoff(
      old: run.state.lazyPublication!,
      successor: fresh,
    );
    expect(
      run.state
          .publishSnapshotHandoff(
            successor: fresh,
            handoff: valid,
            operation: operation,
          )
          .accepted,
      isTrue,
    );
  });
}

String _bytes(ProgressiveDisplayState state) => canonicalJsonEncode([
  state.canonicalCards.map(lazyCanonicalCardGuard).toList(),
  state.displayChunks.map((c) => c.toJson()).toList(),
  state.displayToOriginal,
  state.originalToDisplay.map((k, v) => MapEntry('$k', v)),
  state.lazyPublication!.bodies.map((b) => b.canonicalEncoding).toList(),
  state.lazyPublication!.sessionDigest,
  state.lazyPublication!.revision,
  state.acceptedCanonicalContinuation?.canonicalEncoding,
  state.generationComplete,
]);

class _Run {
  late PublicationSpineAuthority publication;
  late LazyEpubIndex originalIndex;
  late List<ParsedSection> sections;
  late LazyPreparedSection a;
  late ProgressiveDisplayState state;
  late ReaderCorePaginationHarness harness;
  bool cancelled = false;
  bool invalidFontEvidence = false;
  final LazyPublicationOwner owner = (
    bookOpenEpoch: 1,
    displayOwner: 1,
    attempt: 0,
  );
  LazyPublicationOwner currentOwner = (
    bookOpenEpoch: 1,
    displayOwner: 1,
    attempt: 0,
  );
  LazyHandoffOperation get operation {
    final controls = harness.canonicalOperationForP04();
    return LazyHandoffOperation(
      owner: owner,
      currentOwner: () => currentOwner,
      pagination: CanonicalPaginationOperationControls(
        generationToken: controls.generationToken,
        scheduler: controls.scheduler,
        priority: controls.priority,
        isCancelled: () => cancelled,
      ),
    );
  }

  static Future<_Run> open(
    WidgetTester tester, {
    int sectionCount = 2,
    File? fixture,
  }) async {
    final run = _Run();
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('nalori-one-handoff-');
      final file =
          fixture ??
          await File(
            '${root.path}/book.epub',
          ).writeAsBytes(buildAddressFixture(sectionCount: sectionCount));
      final lazy = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory('${root.path}/cache'),
          ),
          workCoordinator: SharedLazySectionWorkCoordinator(),
        ),
      );
      try {
        final index = await lazy.open(file);
        run.originalIndex = index;
        run.publication = PublicationSpineAuthority.capture(index);
        run.sections = [
          for (var i = 0; i < sectionCount; i++) await lazy.loadSection(i),
        ];
      } finally {
        await lazy.close();
        await root.delete(recursive: true);
      }
    });
    final input = LazySectionInput.capture(
      publication: run.publication,
      sections: [run.sections.first],
    );
    run.harness = await ReaderCorePaginationHarness.install(
      tester: tester,
      sourceChunks: [
        for (var i = 0; i < input.snapshot.sourceCount; i++)
          input.snapshot.resolveOrdinalSource(i),
      ],
      bookId: input.snapshot.bookId,
      publicationFingerprint: input.snapshot.publicationFingerprint,
    );
    run.a = await LazyPreparedSection.prepare(
      input: input,
      layout: await run.layout(input),
      operation: run.operation,
    );
    run.state = ProgressiveDisplayState(
      signature: DisplayGenerationSignature(
        bookId: input.snapshot.bookId,
        parsedContentVersion: 1,
        layoutSignature: run.a.session.controlledLayoutIdentity,
        settingsSignature: 'single-handoff',
        viewportSignature: 'single-handoff',
        cacheKey: 'single-handoff',
      ),
      sourceChunkCount: input.snapshot.sourceCount,
    );
    final accepted = run.state.publishLazyInitial(
      prepared: run.a,
      operation: run.operation,
    );
    expect(accepted.accepted, isTrue, reason: accepted.message);
    return run;
  }

  Future<LazyPreparedSection> prepareB(WidgetTester tester) async {
    final input = a.input.append(sections[1]);
    return LazyPreparedSection.prepare(
      input: input,
      layout: await layout(input),
      operation: operation,
    );
  }

  Future<ReaderCardPaginatorLayout> layout(LazySectionInput input) async {
    final env = harness.environment.inputs;
    final base = harness.paginatorLayout;
    final snapshot = input.snapshot;
    final font = await ReaderFontEvidenceGate().capture(
      settings: base.settings,
      stableSourceIdentity: snapshot.owners.last.sourceIdentity,
      sourceStartUtf16: 0,
      sourceText:
          snapshot.resolveOrdinalSource(snapshot.sourceCount - 1).text ?? '',
      locale: env.locale.toLanguageTag(),
      textScaler: TextScaler.linear(env.textScaleFactor),
    );
    final result = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: env.viewportSize,
        mediaQuerySize: env.viewportSize,
        viewPadding: env.safeArea,
        locale: env.locale,
        defaultDirection: env.textDirection,
        textScaler: TextScaler.linear(env.textScaleFactor),
        settings: base.settings,
        fontOutcome: font,
        captureFreshnessEvidence: 'single-handoff',
        publicationFingerprint: snapshot.publicationFingerprint,
        parserSourceSchemaIdentity: snapshot.parserSourceIdentity,
        sourceRevision: snapshot.sourceRevision,
        sourceSnapshotDigest: snapshot.snapshotDigest,
      ),
    );
    expect(result, isA<ReaderLayoutContractReady>());
    final contract = (result as ReaderLayoutContractReady).contract;
    final body = contract.typography[ReaderLayoutTextRole.body];
    final heading = contract.typography[ReaderLayoutTextRole.heading];
    return ReaderCardPaginatorLayout(
      availableWidth: contract.geometry.bodySize.width,
      pageHeightBudget: contract.geometry.ordinaryPaginationHeightBudget,
      physicalTextBudget: contract.geometry.publisherPaginationHeightBudget,
      minUsefulHeight: contract.geometry.minUsefulHeight,
      tinyWordCount: contract.settingsPolicy.densityTinyWordCount,
      tinyHeightRatio: contract.settingsPolicy.densityTinyHeightRatio,
      settings: base.settings,
      bodyStyle: body.toTextStyle(),
      headingStyle: heading.toTextStyle(),
      bodyStrut: body.toStrutStyle(),
      headingStrut: heading.toStrutStyle(),
      textScaler: TextScaler.noScaling,
      contract: contract,
      fontEvidenceResolver: (chunk, text) =>
          invalidFontEvidence ? [] : base.fontEvidenceResolver!(chunk, text),
      imageEvidenceResolver: base.imageEvidenceResolver,
    );
  }
}
