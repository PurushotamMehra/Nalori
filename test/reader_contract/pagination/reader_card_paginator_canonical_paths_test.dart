import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('p04-004-canonical-paths-');
  });

  tearDownAll(() async {
    await fixture.close();
  });

  group('[TASK-P04-004] canonical production paths', () {
    testWidgets('publication and trusted-section initial restarts finalize', (
      tester,
    ) async {
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: fixture.sourceChunks,
      );
      final publication = harness.canonicalSessionForP04();
      final publicationResult = await publication.generateInitial(
        restart: const CanonicalPaginationPublicationStart(),
        operation: harness.canonicalOperationForP04(),
      );

      expect(publicationResult, isA<CanonicalReaderPaginationPathAccepted>());
      final publicationAccepted =
          publicationResult as CanonicalReaderPaginationPathAccepted;
      expect(publicationAccepted.publishableCards, isNotEmpty);
      expect(
        publicationAccepted.continuation.checkpointReason,
        isNot(CanonicalPaginationCheckpointReason.requestExhaustedProvisional),
      );

      final sectionOrdinal = _secondSectionStart(publication.sourceSnapshot);
      final owner = publication.sourceSnapshot.ownerAt(sectionOrdinal);
      final section = harness.canonicalSessionForP04();
      final sectionResult = await section.generateInitial(
        restart: CanonicalPaginationTrustedSectionStart(
          sectionIdentity: owner.sectionIdentity,
          sourceIdentity: owner.sourceIdentity,
          sourceOrdinalHint: sectionOrdinal,
        ),
        operation: harness.canonicalOperationForP04(),
      );

      expect(sectionResult, isA<CanonicalReaderPaginationPathAccepted>());
      final sectionAccepted =
          sectionResult as CanonicalReaderPaginationPathAccepted;
      expect(sectionAccepted.publishableCards, isNotEmpty);
      expect(
        sectionAccepted.publishableCards
            .expand((card) => card.sourceSlices)
            .map((slice) => slice.sourceOrdinalHint),
        everyElement(greaterThanOrEqualTo(sectionOrdinal)),
      );
    });

    testWidgets(
      'stable repeated-text targets resolve uniquely after finalization',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final firstSession = harness.canonicalSessionForP04();
        final secondSession = harness.canonicalSessionForP04();
        expect(fixture.sourceChunks[8].text, fixture.sourceChunks[18].text);

        final seed =
            await firstSession.generateInitial(
                  restart: const CanonicalPaginationPublicationStart(),
                  operation: harness.canonicalOperationForP04(),
                )
                as CanonicalReaderPaginationPathAccepted;
        final firstTarget = harness.canonicalTargetForP04(firstSession, 8);
        final predecessors = firstSession.checkpointIndex
            .predecessorsAtOrBefore(firstTarget);
        expect(predecessors, isNotEmpty);
        expect(
          predecessors.first.integrityDigest,
          seed.continuation.integrityDigest,
        );

        final first = await firstSession.generateTarget(
          target: firstTarget,
          operation: harness.canonicalOperationForP04(),
        );
        final second = await secondSession.generateTarget(
          target: harness.canonicalTargetForP04(secondSession, 18),
          operation: harness.canonicalOperationForP04(),
        );

        for (final result in [first, second]) {
          expect(result, isA<CanonicalReaderPaginationPathAccepted>());
          final accepted = result as CanonicalReaderPaginationPathAccepted;
          expect(accepted.targetContainment, isNotNull);
          expect(accepted.publishableCards, isNotEmpty);
          expect(accepted.usedEarlierCheckpointRecovery, isFalse);
          expect(
            accepted.privatePredecessorCardsDiscarded,
            lessThanOrEqualTo(7),
          );
          expect(
            accepted.boundedWorkEntriesConsumed,
            lessThanOrEqualTo(CanonicalPaginationBounds.normalWorkEnvelope),
          );
          expect(
            accepted.publishableCards.first.identity.signature,
            accepted.targetContainment!.cardIdentity.signature,
          );
        }
        expect(
          (first as CanonicalReaderPaginationPathAccepted)
              .targetContainment!
              .target
              .sourceIdentity,
          isNot(
            (second as CanonicalReaderPaginationPathAccepted)
                .targetContainment!
                .target
                .sourceIdentity,
          ),
        );
        expect(first.targetContainment!.containingSlice.sourceOrdinalHint, 8);
        expect(second.targetContainment!.containingSlice.sourceOrdinalHint, 18);
      },
    );

    testWidgets(
      'provisional exhaustion publishes no tail and is not logical end',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final session = harness.canonicalSessionForP04();
        final result = await session.generateInitial(
          restart: const CanonicalPaginationPublicationStart(),
          operation: harness.canonicalOperationForP04(),
          budget: const CanonicalPaginationWorkBudget(
            maxSourceChunks: 1,
            maxAtomicFragments: 1,
          ),
        );

        expect(result, isA<CanonicalReaderProvisionalBudgetExhaustion>());
        final provisional =
            result as CanonicalReaderProvisionalBudgetExhaustion;
        expect(provisional.publishableCards, isEmpty);
        expect(provisional.continuation.terminal, isFalse);
        expect(
          provisional.continuation.checkpointReason,
          CanonicalPaginationCheckpointReason.requestExhaustedProvisional,
        );
        expect(provisional.hasCacheWriteAuthority, isTrue);
      },
    );

    testWidgets(
      'forward resumes exact accepted suffix and rejects a mismatched seam',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final session = harness.canonicalSessionForP04();
        final initial =
            await session.generateInitial(
                  restart: const CanonicalPaginationPublicationStart(),
                  operation: harness.canonicalOperationForP04(),
                )
                as CanonicalReaderPaginationPathAccepted;
        final suffixCard = initial.publishableCards.last;
        final suffix = session.publishedSuffixBoundary(
          card: suffixCard.card,
          sourceOrdinals: suffixCard.sourceSlices
              .map((slice) => slice.sourceOrdinalHint)
              .toSet()
              .toList(growable: false),
        );
        expect(suffix, isNotNull);

        final forward = await session.generateForward(
          acceptedPublishedSuffix: suffix!,
          operation: harness.canonicalOperationForP04(),
        );
        expect(forward, isA<CanonicalReaderPaginationPathAccepted>());
        final acceptedForward =
            forward as CanonicalReaderPaginationPathAccepted;
        expect(
          acceptedForward.publishableCards.every(
            (card) => card.identity.signature != suffixCard.identity.signature,
          ),
          isTrue,
        );
        expect(
          acceptedForward.boundedWorkEntriesConsumed,
          lessThanOrEqualTo(CanonicalPaginationBounds.normalWorkEnvelope),
        );

        final mismatch = CanonicalPaginationFinalizedBoundary(
          kind: suffix.kind,
          endCursor: suffix.endCursor,
          cardIdentity: null,
        );
        final rejected = await session.generateForward(
          acceptedPublishedSuffix: mismatch,
          operation: harness.canonicalOperationForP04(),
        );
        expect(rejected, isA<CanonicalReaderPaginationPathRejected>());
        expect(rejected.publishableCards, isEmpty);
        expect(rejected.hasCacheWriteAuthority, isFalse);
        expect(rejected.hasAcceptedRestartAuthority, isFalse);
      },
    );

    testWidgets(
      'cancelled and stale results insert no checkpoint or publication',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        for (final operation in [
          harness.canonicalOperationForP04(isCancelled: () => true),
          harness.canonicalOperationForP04(currentGenerationToken: () => -1),
        ]) {
          final session = harness.canonicalSessionForP04();
          final before = session.checkpointIndex.records.length;
          final result = await session.generateInitial(
            restart: const CanonicalPaginationPublicationStart(),
            operation: operation,
          );
          expect(result, isA<CanonicalReaderPaginationPathRejected>());
          expect(result.publishableCards, isEmpty);
          expect(result.hasCacheWriteAuthority, isFalse);
          expect(session.checkpointIndex.records.length, before);
        }
      },
    );

    testWidgets(
      'publication, snapshot, and layout-incompatible restarts reject',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final source = harness.canonicalSessionForP04();
        final sourceResult =
            await source.generateInitial(
                  restart: const CanonicalPaginationPublicationStart(),
                  operation: harness.canonicalOperationForP04(),
                )
                as CanonicalReaderPaginationPathAccepted;

        for (final incompatible in [
          _session(harness, bookId: 'another-book'),
          _session(harness, publicationFingerprint: 'another-publication'),
          _session(harness, sourceRevision: 'another-source-revision'),
          _session(harness, layoutIdentity: 'another-layout'),
        ]) {
          final result = await incompatible.generateInitial(
            restart: sourceResult.continuation,
            operation: harness.canonicalOperationForP04(),
          );
          expect(result, isA<CanonicalReaderPaginationPathRejected>());
          expect(result.publishableCards, isEmpty);
          expect(result.hasAcceptedRestartAuthority, isFalse);
        }
      },
    );

    testWidgets('nearest invalid checkpoint uses only one earlier recovery', (
      tester,
    ) async {
      final sources = <BookChunk>[
        for (var index = 0; index < 31; index++)
          BookChunk(
            index: index,
            type: BookChunkType.text,
            text: 'bounded source $index',
            sourceFile: 'chapter.xhtml',
            logicalParagraphId: 'paragraph-$index',
            logicalParagraphEndOffset: 'bounded source $index'.length,
          ),
      ];
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: sources,
        bookId: 'p04-recovery-book',
        publicationFingerprint: 'p04-recovery-publication',
      );
      final session = harness.canonicalSessionForP04();
      CanonicalReaderPaginationPathResult result = await session
          .generateInitial(
            restart: const CanonicalPaginationPublicationStart(),
            operation: harness.canonicalOperationForP04(),
            budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
          );
      while (result is! CanonicalReaderLogicalEnd) {
        final accepted = result as CanonicalReaderPaginationPathAccepted;
        result = await session.generateInitial(
          restart: accepted.continuation,
          operation: harness.canonicalOperationForP04(),
          budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
        );
      }
      expect(session.checkpointIndex.records.length, 25);

      int? recoveryTargetOrdinal;
      for (var ordinal = 0; ordinal < sources.length; ordinal++) {
        final target = harness.canonicalTargetForP04(session, ordinal);
        final candidates = session.checkpointIndex.predecessorsAtOrBefore(
          target,
        );
        if (candidates.length == 2 &&
            !session.checkpointIndex.forkAt(candidates.first).accepted &&
            session.checkpointIndex.forkAt(candidates.last).accepted) {
          recoveryTargetOrdinal = ordinal;
          break;
        }
      }
      expect(recoveryTargetOrdinal, isNotNull);

      final target = await session.generateTarget(
        target: harness.canonicalTargetForP04(session, recoveryTargetOrdinal!),
        operation: harness.canonicalOperationForP04(),
      );
      expect(target, isA<CanonicalReaderPaginationPathAccepted>());
      final accepted = target as CanonicalReaderPaginationPathAccepted;
      expect(accepted.usedEarlierCheckpointRecovery, isTrue);
      expect(accepted.privatePredecessorCardsDiscarded, lessThanOrEqualTo(15));
      expect(
        accepted.boundedWorkEntriesConsumed,
        lessThanOrEqualTo(CanonicalPaginationBounds.recoveryWorkEnvelope),
      );

      final foreign = _session(harness, bookId: 'foreign-book');
      final foreignResult =
          await foreign.generateInitial(
                restart: const CanonicalPaginationPublicationStart(),
                operation: harness.canonicalOperationForP04(),
              )
              as CanonicalReaderPaginationPathAccepted;
      final missing = session.checkpointIndex.forkAt(
        foreignResult.continuation,
      );
      expect(missing.accepted, isFalse);
      expect(
        missing.rejection!.kind,
        CanonicalPaginationContinuationValidationKind.requiredEarlierRestart,
      );
    });

    testWidgets(
      'source-267 continuation resumes to exact source-280 containment',
      (tester) async {
        final sources = _syntheticSources(320);
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
          bookId: 'p04-target-280-book',
          publicationFingerprint: 'p04-target-280-publication',
        );
        final session = harness.canonicalSessionForP04(
          deferPublicationCommit: true,
        );
        CanonicalPaginationRestart restart =
            const CanonicalPaginationPublicationStart();
        var operationCount = 0;
        var maximumEntered = 0;
        var maximumFrontierEntries = 0;
        while (operationCount < 64) {
          final outcome = await session.generateInitial(
            restart: restart,
            operation: harness.canonicalOperationForP04(),
            budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 8),
          );
          expect(
            outcome,
            isA<CanonicalReaderPaginationPathAccepted>(),
            reason: 'operation=$operationCount',
          );
          final accepted = outcome as CanonicalReaderPaginationPathAccepted;
          maximumEntered = math.max(
            maximumEntered,
            accepted.diagnostics.sourceChunksEntered,
          );
          maximumFrontierEntries = math.max(
            maximumFrontierEntries,
            accepted.diagnostics.peakFrontierEntries,
          );
          expect(
            accepted.diagnostics.sourceChunksEntered,
            lessThanOrEqualTo(8),
          );
          if (accepted.publishableCards.isNotEmpty) {
            expect(session.commitPublication(accepted), isTrue);
          }
          restart = accepted.continuation;
          operationCount++;
          if (!accepted.continuation.nextSourceCursor.isLogicalEnd &&
              accepted.continuation.nextSourceCursor.sourceOrdinalHint >= 267) {
            expect(
              accepted.continuation.nextSourceCursor.sourceOrdinalHint,
              267,
            );
            break;
          }
        }

        expect(operationCount, 37);
        expect(session.checkpointIndex.records, hasLength(25));
        final outcome = await session.generateTarget(
          target: harness.canonicalTargetForP04(session, 280),
          operation: harness.canonicalOperationForP04(),
        );
        expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
        expect(
          outcome,
          isNot(isA<CanonicalReaderProvisionalBudgetExhaustion>()),
        );
        final accepted = outcome as CanonicalReaderPaginationPathAccepted;
        expect(accepted.targetContainment, isNotNull);
        expect(
          accepted.targetContainment!.containingSlice.sourceOrdinalHint,
          280,
        );
        expect(
          accepted.publishableCards.any(
            (card) =>
                card.identity.signature ==
                accepted.targetContainment!.cardIdentity.signature,
          ),
          isTrue,
        );
        expect(
          accepted.boundedWorkEntriesConsumed,
          lessThanOrEqualTo(CanonicalPaginationBounds.normalWorkEnvelope),
        );
        expect(accepted.continuation.copiedSourceTextUtf16, 0);
        expect(session.checkpointIndex.records, hasLength(25));
        // ignore: avoid_print
        print(
          'P04-020 target summary: operations=$operationCount; '
          'start=267; target=280; targetWork='
          '${accepted.boundedWorkEntriesConsumed}; maxEntered=$maximumEntered; '
          'maxFrontierEntries=$maximumFrontierEntries; records='
          '${session.checkpointIndex.records.length}; copiedText='
          '${accepted.continuation.copiedSourceTextUtf16}',
        );
      },
    );

    test('ReaderScreen canonical routes leave legacy only to frozen P02', () {
      final source = File('lib/screens/reader_screen.dart').readAsStringSync();
      expect(RegExp(r'paginateLegacyForP02\(').allMatches(source), isEmpty);
      expect(source, contains('canonicalSession.generateInitial'));
      expect(source, contains('canonicalSession.generateTarget'));
      expect(source, contains('canonicalSession.generateForward'));
      expect(source, contains('canonicalSession.generateBackward'));
      expect(source, contains('CanonicalReaderProvisionalBudgetExhaustion'));
      expect(source, isNot(contains('legacyRequestEnd')));
    });
  });
}

List<BookChunk> _syntheticSources(int count) => <BookChunk>[
  for (var index = 0; index < count; index++)
    BookChunk(
      index: index,
      type: BookChunkType.text,
      text:
          'Synthetic bounded source ${index.toString().padLeft(3, '0')} '
          'contains deterministic test prose.',
      sourceFile: index < 100
          ? 'synthetic-one.xhtml'
          : index < 200
          ? 'synthetic-two.xhtml'
          : 'synthetic-three.xhtml',
      logicalParagraphId: 'synthetic-paragraph-$index',
      logicalParagraphEndOffset:
          'Synthetic bounded source ${index.toString().padLeft(3, '0')} '
                  'contains deterministic test prose.'
              .length,
    ),
];

int _secondSectionStart(CanonicalPaginationSourceSnapshot snapshot) {
  final first = snapshot.ownerAt(0).sectionIdentity;
  for (var ordinal = 1; ordinal < snapshot.sourceCount; ordinal++) {
    if (snapshot.ownerAt(ordinal).sectionIdentity != first) return ordinal;
  }
  throw StateError('Fixture has no second trusted section.');
}

CanonicalReaderPaginationSession _session(
  ReaderCorePaginationHarness harness, {
  String? bookId,
  String? publicationFingerprint,
  String? sourceRevision,
  String? layoutIdentity,
}) {
  final sourceKeys = <CanonicalPaginationSourceKey>[
    for (var ordinal = 0; ordinal < harness.sourceChunks.length; ordinal++)
      CanonicalPaginationSourceKey(
        sourceIdentity:
            '${harness.sourceChunks[ordinal].sourceFile ?? harness.sourceChunks[ordinal].section.name}|'
            '${harness.sourceChunks[ordinal].logicalParagraphId ?? 'source'}|$ordinal',
        sectionIdentity:
            harness.sourceChunks[ordinal].sourceFile ??
            harness.sourceChunks[ordinal].section.name,
        spineIdentity:
            harness.sourceChunks[ordinal].sourceFile ??
            harness.sourceChunks[ordinal].section.name,
        sourceOrdinalHint: ordinal,
      ),
  ];
  final snapshot = CanonicalPaginationSourceSnapshot.pin(
    bookId: bookId ?? harness.bookId,
    publicationFingerprint:
        publicationFingerprint ?? harness.publicationFingerprint,
    parserSourceIdentity: 'reader-core-fixture-parser',
    sourceRevision:
        sourceRevision ??
        readerSha256(
          sourceKeys.map((key) => key.sourceIdentity).toList(growable: false),
        ),
    sourceChunks: harness.sourceChunks,
    sourceKeys: sourceKeys,
  );
  return CanonicalReaderPaginationSession(
    sourceSnapshot: snapshot,
    controlledLayoutIdentity: layoutIdentity ?? harness.layoutIdentity,
    layout: harness.paginatorLayout,
  );
}
