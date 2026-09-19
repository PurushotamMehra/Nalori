import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('p04-005-backward-');
  });

  tearDownAll(() => fixture.close());

  group('[TASK-P04-005] bounded canonical backward preparation', () {
    testWidgets(
      'nearest earlier checkpoint regenerates forward and keeps exact order',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);
        final session = harness.canonicalSessionForP04();
        await _seed(session, harness, sourceCount: 4);
        final prepared = await _target(session, harness, 12);
        final beforeIndex = _indexBytes(session);

        final result = await _backward(
          session,
          harness,
          prepared,
          desiredOrdinal: 8,
        );

        expect(result, isA<CanonicalReaderBackwardPreparationAccepted>());
        final accepted = result as CanonicalReaderBackwardPreparationAccepted;
        expect(accepted.restartDescription, startsWith('checkpoint:'));
        expect(accepted.usedEarlierCheckpointRecovery, isFalse);
        expect(accepted.publishableCards, isNotEmpty);
        expect(
          accepted.boundedWorkEntriesConsumed,
          lessThanOrEqualTo(CanonicalPaginationBounds.normalWorkEnvelope),
        );
        expect(
          accepted.predecessorEndCursor.samePositionAs(
            accepted.currentStartCursor,
          ),
          isTrue,
        );
        expect(
          accepted.currentEndCursor.samePositionAs(
            accepted.successorStartCursor,
          ),
          isTrue,
        );
        expect(_indexBytes(session), beforeIndex);
      },
    );

    testWidgets('publication start is used only when it is within bounds', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      final session = harness.canonicalSessionForP04();
      final prepared = await _target(session, harness, 8);

      final result = await _backward(
        session,
        harness,
        prepared,
        desiredOrdinal: 0,
      );

      expect(result, isA<CanonicalReaderBackwardPreparationAccepted>());
      final accepted = result as CanonicalReaderBackwardPreparationAccepted;
      expect(accepted.restartDescription, 'publication');
      expect(
        accepted.publishableCards.first.sourceSlices.first.sourceOrdinalHint,
        0,
      );
    });

    testWidgets('trusted section start prepares a same-section predecessor', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      final session = harness.canonicalSessionForP04();
      final prepared = await _target(session, harness, 18);

      final result = await _backward(
        session,
        harness,
        prepared,
        desiredOrdinal: 16,
      );

      expect(result, isA<CanonicalReaderBackwardPreparationAccepted>());
      expect(
        (result as CanonicalReaderBackwardPreparationAccepted)
            .restartDescription,
        startsWith('trusted-section:'),
      );
    });

    testWidgets('one invalid nearest checkpoint falls back exactly once', (
      tester,
    ) async {
      final sources = _checkpointSources(34);
      final harness = await _harness(tester, sources);
      final session = harness.canonicalSessionForP04();
      CanonicalReaderPaginationPathResult outcome = await session
          .generateInitial(
            restart: const CanonicalPaginationPublicationStart(),
            operation: harness.canonicalOperationForP04(),
            budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
          );
      while (outcome is! CanonicalReaderLogicalEnd) {
        if (outcome is CanonicalReaderPaginationPathRejected) {
          throw StateError(
            '${outcome.rejection.reason}: ${outcome.rejection.message}',
          );
        }
        final accepted = outcome as CanonicalReaderPaginationPathAccepted;
        outcome = await session.generateInitial(
          restart: accepted.continuation,
          operation: harness.canonicalOperationForP04(),
          budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
        );
      }

      int? desired;
      for (var ordinal = 1; ordinal < sources.length - 2; ordinal++) {
        final target = harness.canonicalTargetForP04(session, ordinal);
        final candidates = session.checkpointIndex.predecessorsBefore(target);
        if (candidates.length == 2 &&
            !session.checkpointIndex.forkAt(candidates.first).accepted &&
            session.checkpointIndex.forkAt(candidates.last).accepted) {
          desired = ordinal;
          break;
        }
      }
      expect(desired, isNotNull);
      final prefixIndex = session.acceptedPublishedCards.indexWhere(
        (card) => card.sourceSlices.first.sourceOrdinalHint > desired!,
      );
      expect(prefixIndex, isNonNegative);
      final prefix = session.acceptedPublishedCards[prefixIndex];
      final successor = session.acceptedSuccessorStartCursorFor(prefix)!;
      final beforeIndex = _indexBytes(session);
      final result = await session.generateBackward(
        desiredPredecessor: harness.canonicalTargetForP04(session, desired!),
        acceptedPublishedPrefix: prefix,
        committedCurrentCard: prefix,
        acceptedSuccessorStartCursor: successor,
        operation: harness.canonicalOperationForP04(),
      );

      expect(result, isA<CanonicalReaderBackwardPreparationAccepted>());
      expect(
        (result as CanonicalReaderBackwardPreparationAccepted)
            .usedEarlierCheckpointRecovery,
        isTrue,
      );
      expect(result.publishableCards.length, lessThanOrEqualTo(15));
      expect(_indexBytes(session), beforeIndex);
    });

    testWidgets('missing bounded earlier restart is rejected', (tester) async {
      final sources = _isolatedSources(180);
      final harness = await _harness(tester, sources);
      final session = harness.canonicalSessionForP04();
      final prepared = await _target(session, harness, 179);
      final before = _indexBytes(session);

      final result = await _backward(
        session,
        harness,
        prepared,
        desiredOrdinal: 0,
      );

      expect(result, isA<CanonicalReaderRequiredEarlierRestart>());
      expect(result.publishableCards, isEmpty);
      expect(result.hasAcceptedRestartAuthority, isFalse);
      expect(result.hasCacheWriteAuthority, isFalse);
      expect(_indexBytes(session), before);
    });

    testWidgets(
      'identity, source range, and section-spine mismatches reject atomically',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);

        final identitySession = harness.canonicalSessionForP04();
        final identityPrepared = await _target(identitySession, harness, 8);
        final wrongIdentity = CanonicalFinalizedReaderCard(
          card: identityPrepared.current.card,
          identity: ReaderCardIdentity(
            publicationFingerprint: harness.publicationFingerprint,
            layoutFingerprint: 'wrong-layout',
            ranges: identityPrepared.current.identity.ranges,
          ),
          sourceSlices: identityPrepared.current.sourceSlices,
        );
        final identityBefore = _indexBytes(identitySession);
        final identityResult = await identitySession.generateBackward(
          desiredPredecessor: harness.canonicalTargetForP04(identitySession, 0),
          acceptedPublishedPrefix: identityPrepared.prefix,
          committedCurrentCard: wrongIdentity,
          acceptedSuccessorStartCursor: identityPrepared.successorStart,
          operation: harness.canonicalOperationForP04(),
        );
        expect(
          (identityResult as CanonicalReaderBackwardPreparationRejected).reason,
          CanonicalReaderBackwardRejectionReason.committedIdentityMismatch,
        );
        expect(identityResult.publishableCards, isEmpty);
        expect(_indexBytes(identitySession), identityBefore);

        final sliceSession = harness.canonicalSessionForP04();
        final slicePrepared = await _target(sliceSession, harness, 8);
        final alteredSlice = _copySlice(
          slicePrepared.current.sourceSlices.first,
          endUtf16: slicePrepared.current.sourceSlices.first.endUtf16! - 1,
        );
        final wrongSlice = CanonicalFinalizedReaderCard(
          card: slicePrepared.current.card,
          identity: slicePrepared.current.identity,
          sourceSlices: [
            alteredSlice,
            ...slicePrepared.current.sourceSlices.skip(1),
          ],
        );
        final sliceResult = await sliceSession.generateBackward(
          desiredPredecessor: harness.canonicalTargetForP04(sliceSession, 0),
          acceptedPublishedPrefix: slicePrepared.prefix,
          committedCurrentCard: wrongSlice,
          acceptedSuccessorStartCursor: slicePrepared.successorStart,
          operation: harness.canonicalOperationForP04(),
        );
        expect(
          (sliceResult as CanonicalReaderBackwardPreparationRejected).reason,
          CanonicalReaderBackwardRejectionReason.committedSourceSliceMismatch,
        );

        final sectionSession = harness.canonicalSessionForP04();
        final sectionPrepared = await _target(sectionSession, harness, 8);
        final wrongOwner = _copySlice(
          sectionPrepared.current.sourceSlices.first,
          sectionIdentity: 'wrong-section',
          spineIdentity: 'wrong-spine',
        );
        final wrongSection = CanonicalFinalizedReaderCard(
          card: sectionPrepared.current.card,
          identity: sectionPrepared.current.identity,
          sourceSlices: [
            wrongOwner,
            ...sectionPrepared.current.sourceSlices.skip(1),
          ],
        );
        final sectionResult = await sectionSession.generateBackward(
          desiredPredecessor: harness.canonicalTargetForP04(sectionSession, 0),
          acceptedPublishedPrefix: sectionPrepared.prefix,
          committedCurrentCard: wrongSection,
          acceptedSuccessorStartCursor: sectionPrepared.successorStart,
          operation: harness.canonicalOperationForP04(),
        );
        expect(
          (sectionResult as CanonicalReaderBackwardPreparationRejected).reason,
          CanonicalReaderBackwardRejectionReason.committedSectionSpineMismatch,
        );
      },
    );

    testWidgets('predecessor/current/successor cursor mismatch rejects', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      final session = harness.canonicalSessionForP04();
      final prepared = await _target(session, harness, 8);
      final wrongCursor = CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.sourceText,
        sourceIdentity: prepared.successorStart.sourceIdentity,
        sectionIdentity: prepared.successorStart.sectionIdentity,
        sourceOrdinalHint: prepared.successorStart.sourceOrdinalHint,
        textOffsetUtf16: prepared.successorStart.textOffsetUtf16 + 1,
      );

      final result = await session.generateBackward(
        desiredPredecessor: harness.canonicalTargetForP04(session, 0),
        acceptedPublishedPrefix: prepared.prefix,
        committedCurrentCard: prepared.current,
        acceptedSuccessorStartCursor: wrongCursor,
        operation: harness.canonicalOperationForP04(),
      );

      expect(
        (result as CanonicalReaderBackwardPreparationRejected).reason,
        CanonicalReaderBackwardRejectionReason.cursorDiscontinuity,
      );
      expect(result.publishableCards, isEmpty);
    });

    testWidgets(
      'budget exhaustion, cancellation, and staleness expose no predecessor',
      (tester) async {
        final boundedHarness = await _harness(tester, _longHeadingSources(30));
        final boundedSession = boundedHarness.canonicalSessionForP04();
        await _seedUntil(boundedSession, boundedHarness, sourceOrdinal: 19);
        final boundedPrepared = await _target(
          boundedSession,
          boundedHarness,
          20,
        );
        final pending = await boundedSession.generateBackward(
          desiredPredecessor: boundedHarness.canonicalTargetForP04(
            boundedSession,
            0,
          ),
          acceptedPublishedPrefix: boundedPrepared.prefix,
          committedCurrentCard: boundedPrepared.current,
          acceptedSuccessorStartCursor: boundedPrepared.successorStart,
          operation: boundedHarness.canonicalOperationForP04(),
        );
        expect(pending, isA<CanonicalReaderBackwardPreparationPending>());
        expect(pending.publishableCards, isEmpty);
        expect(pending.hasCacheWriteAuthority, isFalse);

        final cancelHarness = await _harness(tester, fixture.sourceChunks);
        final cancelSession = cancelHarness.canonicalSessionForP04();
        final cancelPrepared = await _target(cancelSession, cancelHarness, 8);
        for (final operation in [
          cancelHarness.canonicalOperationForP04(isCancelled: () => true),
          cancelHarness.canonicalOperationForP04(
            currentGenerationToken: () => -1,
          ),
        ]) {
          final result = await cancelSession.generateBackward(
            desiredPredecessor: cancelHarness.canonicalTargetForP04(
              cancelSession,
              0,
            ),
            acceptedPublishedPrefix: cancelPrepared.prefix,
            committedCurrentCard: cancelPrepared.current,
            acceptedSuccessorStartCursor: cancelPrepared.successorStart,
            operation: operation,
          );
          expect(result, isA<CanonicalReaderBackwardPreparationRejected>());
          expect(result.publishableCards, isEmpty);
        }

        var checks = 0;
        final duringSession = cancelHarness.canonicalSessionForP04();
        final duringPrepared = await _target(duringSession, cancelHarness, 8);
        final during = await duringSession.generateBackward(
          desiredPredecessor: cancelHarness.canonicalTargetForP04(
            duringSession,
            0,
          ),
          acceptedPublishedPrefix: duringPrepared.prefix,
          committedCurrentCard: duringPrepared.current,
          acceptedSuccessorStartCursor: duringPrepared.successorStart,
          operation: cancelHarness.canonicalOperationForP04(
            isCancelled: () => ++checks > 12,
          ),
        );
        expect(during, isA<CanonicalReaderBackwardPreparationRejected>());
        expect(during.publishableCards, isEmpty);
      },
    );

    testWidgets(
      'repeated prose, split paragraphs, headings, and section seams retain owners',
      (tester) async {
        final standard = await _harness(tester, fixture.sourceChunks);
        for (final scenario in <({int target, int desired})>[
          (target: 8, desired: 0),
          (target: 3, desired: 0),
          (target: 17, desired: 12),
          (target: 18, desired: 16),
        ]) {
          final session = standard.canonicalSessionForP04();
          final prepared = await _target(session, standard, scenario.target);
          final result = await _backward(
            session,
            standard,
            prepared,
            desiredOrdinal: scenario.desired,
          );
          expect(result, isA<CanonicalReaderBackwardPreparationAccepted>());
          final accepted = result as CanonicalReaderBackwardPreparationAccepted;
          expect(accepted.regeneratedCommittedCard.sourceSlices, isNotEmpty);
          expect(
            accepted.regeneratedCommittedCard.identity.signature,
            prepared.current.identity.signature,
          );
        }

        final split = await _harness(
          tester,
          fixture.sourceChunks,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        final splitSession = split.canonicalSessionForP04();
        final splitPrepared = await _target(splitSession, split, 7);
        final splitResult = await _backward(
          splitSession,
          split,
          splitPrepared,
          desiredOrdinal: 0,
        );
        expect(splitResult, isA<CanonicalReaderBackwardPreparationAccepted>());
        expect(splitPrepared.current.sourceSlices.single.startUtf16, 0);
        expect(splitPrepared.current.sourceSlices.single.endUtf16, 58);
      },
    );

    testWidgets(
      'accepted prepend preserves committed card/anchor; rejection mutates nothing',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);
        final session = harness.canonicalSessionForP04();
        final prepared = await _target(session, harness, 8);
        final target = prepared.accepted;
        const request = DisplayRangeRequest(
          direction: DisplayRangeDirection.target,
          sourceRange: SourceChunkRange(7, 20),
          generationId: 9001,
          reason: 'p04_backward_anchor_initial',
          targetOriginalIndex: 8,
        );
        final state =
            ProgressiveDisplayState(
              signature: const DisplayGenerationSignature(
                bookId: 'reader-core-book',
                parsedContentVersion: 1,
                layoutSignature: 'p03-controlled-lexend-layout',
                settingsSignature: 'settings',
                viewportSignature: 'viewport',
                cacheKey: 'p04-backward',
              ),
              sourceChunkCount: fixture.sourceChunks.length,
            )..publishInitial(
              canonicalPathDisplayResult(
                accepted: target,
                request: request,
                publicationStart: 7,
              ),
            );
        final committedBefore = canonicalJsonEncode(
          prepared.current.card.toJson(),
        );
        final anchorBefore = state.displayChunks.indexWhere(
          (card) => canonicalJsonEncode(card.toJson()) == committedBefore,
        );
        final accepted =
            await _backward(session, harness, prepared, desiredOrdinal: 0)
                as CanonicalReaderBackwardPreparationAccepted;
        final backwardResult = canonicalPathDisplayResult(
          accepted: accepted,
          request: DisplayRangeRequest(
            direction: DisplayRangeDirection.backward,
            sourceRange: SourceChunkRange(
              0,
              state.ranges.first.sourceRange.start,
            ),
            generationId: 9002,
            reason: 'p04_backward_anchor_prepend',
          ),
          publicationStart: 0,
        );
        final inserted = state.prepend(backwardResult);
        final anchorAfter = state.displayChunks.indexWhere(
          (card) => canonicalJsonEncode(card.toJson()) == committedBefore,
        );
        expect(anchorAfter, anchorBefore + inserted);
        expect(
          canonicalJsonEncode(state.displayChunks[anchorAfter].toJson()),
          committedBefore,
        );

        final displayBeforeRejection = canonicalJsonEncode(
          state.displayChunks.map((card) => card.toJson()).toList(),
        );
        final indexBeforeRejection = _indexBytes(session);
        final rejected = await session.generateBackward(
          desiredPredecessor: harness.canonicalTargetForP04(session, 0),
          acceptedPublishedPrefix: prepared.prefix,
          committedCurrentCard: CanonicalFinalizedReaderCard(
            card: prepared.current.card,
            identity: ReaderCardIdentity(
              publicationFingerprint: harness.publicationFingerprint,
              layoutFingerprint: 'stale-layout',
              ranges: prepared.current.identity.ranges,
            ),
            sourceSlices: prepared.current.sourceSlices,
          ),
          acceptedSuccessorStartCursor: prepared.successorStart,
          operation: harness.canonicalOperationForP04(),
        );
        expect(rejected.publishableCards, isEmpty);
        expect(
          canonicalJsonEncode(
            state.displayChunks.map((card) => card.toJson()).toList(),
          ),
          displayBeforeRejection,
        );
        expect(_indexBytes(session), indexBeforeRejection);
      },
    );
  });
}

Future<ReaderCorePaginationHarness> _harness(
  WidgetTester tester,
  List<BookChunk> sources, {
  ReaderCorePaginationLayout layout = ReaderCorePaginationLayout.standard,
}) => ReaderCorePaginationHarness.install(
  tester: tester,
  sourceChunks: sources,
  layout: layout,
  bookId: 'reader-core-book',
  publicationFingerprint: 'reader-core-publication',
);

Future<void> _seed(
  CanonicalReaderPaginationSession session,
  ReaderCorePaginationHarness harness, {
  required int sourceCount,
}) async {
  final result = await session.generateInitial(
    restart: const CanonicalPaginationPublicationStart(),
    operation: harness.canonicalOperationForP04(),
    budget: CanonicalPaginationWorkBudget(maxSourceChunks: sourceCount),
  );
  expect(result, isA<CanonicalReaderPaginationPathAccepted>());
}

Future<void> _seedUntil(
  CanonicalReaderPaginationSession session,
  ReaderCorePaginationHarness harness, {
  required int sourceOrdinal,
}) async {
  CanonicalPaginationRestart restart =
      const CanonicalPaginationPublicationStart();
  for (var attempt = 0; attempt < 32; attempt++) {
    final cursorOrdinal = restart is CanonicalPaginationContinuation
        ? restart.nextSourceCursor.sourceOrdinalHint
        : 0;
    if (cursorOrdinal >= sourceOrdinal) return;
    final result = await session.generateInitial(
      restart: restart,
      operation: harness.canonicalOperationForP04(),
      budget: CanonicalPaginationWorkBudget(
        maxSourceChunks: sourceOrdinal - cursorOrdinal,
      ),
    );
    expect(result, isA<CanonicalReaderPaginationPathAccepted>());
    restart = (result as CanonicalReaderPaginationPathAccepted).continuation;
  }
  throw StateError('Checkpoint seeding did not reach the requested source.');
}

Future<_PreparedBackward> _target(
  CanonicalReaderPaginationSession session,
  ReaderCorePaginationHarness harness,
  int target,
) async {
  final outcome = await session.generateTarget(
    target: harness.canonicalTargetForP04(session, target),
    operation: harness.canonicalOperationForP04(
      priority: DisplayRangeTaskPriority.directTarget,
    ),
  );
  expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
  final accepted = outcome as CanonicalReaderPaginationPathAccepted;
  expect(accepted.targetContainment, isNotNull);
  final current = accepted.publishableCards.singleWhere(
    (card) =>
        card.identity.signature ==
        accepted.targetContainment!.cardIdentity.signature,
  );
  final prefix = accepted.publishableCards.first;
  final successorStart = session.acceptedSuccessorStartCursorFor(current);
  expect(successorStart, isNotNull);
  return _PreparedBackward(
    accepted: accepted,
    prefix: prefix,
    current: current,
    successorStart: successorStart!,
  );
}

Future<CanonicalReaderPaginationPathResult> _backward(
  CanonicalReaderPaginationSession session,
  ReaderCorePaginationHarness harness,
  _PreparedBackward prepared, {
  required int desiredOrdinal,
}) => session.generateBackward(
  desiredPredecessor: harness.canonicalTargetForP04(session, desiredOrdinal),
  acceptedPublishedPrefix: prepared.prefix,
  committedCurrentCard: prepared.current,
  acceptedSuccessorStartCursor: prepared.successorStart,
  operation: harness.canonicalOperationForP04(),
);

String _indexBytes(CanonicalReaderPaginationSession session) =>
    canonicalJsonEncode(
      session.checkpointIndex.records
          .map((record) => record.canonicalEncoding)
          .toList(growable: false),
    );

List<BookChunk> _isolatedSources(int count) => <BookChunk>[
  for (var index = 0; index < count; index++)
    BookChunk(
      index: index,
      type: BookChunkType.text,
      text: 'isolated source $index',
      sourceFile: 'section-$index.xhtml',
      logicalParagraphId: 'paragraph-$index',
      logicalParagraphEndOffset: 'isolated source $index'.length,
    ),
];

List<BookChunk> _checkpointSources(int count) => <BookChunk>[
  for (var index = 0; index < count; index++)
    BookChunk(
      index: index,
      type: BookChunkType.text,
      text: 'checkpoint source $index',
      sourceFile: 'chapter.xhtml',
      logicalParagraphId: 'paragraph-$index',
      logicalParagraphEndOffset: 'checkpoint source $index'.length,
    ),
];

List<BookChunk> _longHeadingSources(int count) => <BookChunk>[
  for (var index = 0; index < count; index++)
    BookChunk(
      index: index,
      type: BookChunkType.text,
      text: 'Heading $index ${'wide '.padRight(500, 'x')}',
      sourceFile: 'chapter.xhtml',
      logicalParagraphId: 'heading-$index',
      logicalParagraphEndOffset: 512,
      isHeading: true,
      blockRole: BookBlockRole.heading,
    ),
];

CanonicalPaginationSourceSlice _copySlice(
  CanonicalPaginationSourceSlice source, {
  String? sectionIdentity,
  String? spineIdentity,
  int? endUtf16,
}) => CanonicalPaginationSourceSlice(
  sourceIdentity: source.sourceIdentity,
  sectionIdentity: sectionIdentity ?? source.sectionIdentity,
  spineIdentity: spineIdentity ?? source.spineIdentity,
  sourceOrdinalHint: source.sourceOrdinalHint,
  sourceDigest: source.sourceDigest,
  structuralType: source.structuralType,
  structuralOwnerRole: source.structuralOwnerRole,
  logicalOwnerIdentity: source.logicalOwnerIdentity,
  structuralDigest: source.structuralDigest,
  fragmentDigest: source.fragmentDigest,
  publisherLayoutDigest: source.publisherLayoutDigest,
  richMetadataDigest: source.richMetadataDigest,
  listFragmentDigest: source.listFragmentDigest,
  splitBoundaryKind: source.splitBoundaryKind,
  isLogicalParagraphStart: source.isLogicalParagraphStart,
  isLogicalParagraphEnd: source.isLogicalParagraphEnd,
  usesExplicitTextFragment: source.usesExplicitTextFragment,
  startUtf16: source.startUtf16,
  endUtf16: endUtf16 ?? source.endUtf16,
  tableRowStart: source.tableRowStart,
  tableRowEndExclusive: source.tableRowEndExclusive,
);

final class _PreparedBackward {
  const _PreparedBackward({
    required this.accepted,
    required this.prefix,
    required this.current,
    required this.successorStart,
  });

  final CanonicalReaderPaginationPathAccepted accepted;
  final CanonicalFinalizedReaderCard prefix;
  final CanonicalFinalizedReaderCard current;
  final CanonicalPaginationCursor successorStart;
}
