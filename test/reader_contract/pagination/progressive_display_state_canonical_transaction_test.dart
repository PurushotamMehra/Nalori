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
    fixture = await ReaderCoreParsedFixture.load('p04-007-transaction-');
  });

  tearDownAll(() => fixture.close());

  group('[TASK-P04-007] canonical display publication transaction', () {
    testWidgets('accepts initial and exact target publication atomically', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      final initial = await _initial(harness);
      final state = _state(harness);

      final result = state.publishCanonical(_request(initial));

      expect(
        result.kind,
        CanonicalDisplayPublicationOutcomeKind.acceptedInitialPublication,
      );
      expect(result.accepted, isTrue);
      expect(state.canonicalCards, initial.accepted.publishableCards);
      expect(state.displayChunks.length, state.displayToOriginal.length);
      expect(
        state.originalToDisplay.keys,
        containsAll(state.displayToOriginal.expand((owners) => owners).toSet()),
      );
      expect(state.hasCanonicalCacheWriteAuthority, isTrue);

      final targetSession = harness.canonicalSessionForP04();
      final controls = harness.canonicalOperationForP04(
        priority: DisplayRangeTaskPriority.directTarget,
      );
      final targetOutcome = await targetSession.generateTarget(
        target: harness.canonicalTargetForP04(targetSession, 12),
        operation: controls,
      );
      expect(targetOutcome, isA<CanonicalReaderPaginationPathAccepted>());
      final accepted = targetOutcome as CanonicalReaderPaginationPathAccepted;
      final targetState = _state(harness);
      final targetResult = targetState.publishCanonical(
        _request(_AcceptedRun(targetSession, controls, accepted)),
      );
      expect(targetResult.accepted, isTrue);
      expect(accepted.targetContainment, isNotNull);
      expect(
        (targetResult as CanonicalDisplayPublicationAccepted)
            .targetDisplayIndex,
        isNotNull,
      );
    });

    testWidgets('append is immutable and exact replay is idempotent', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      final session = harness.canonicalSessionForP04();
      final state = _state(harness);
      final first = await _initial(harness, session: session);
      expect(state.publishCanonical(_request(first)).accepted, isTrue);
      final prefixBytes = _cardsBytes(state.canonicalCards);
      final predecessor = state.acceptedCanonicalContinuation!;
      final boundary = session.publishedSuffixBoundary(
        card: state.displayChunks.last,
        sourceOrdinals: state.displayToOriginal.last,
      )!;
      final controls = harness.canonicalOperationForP04();
      final outcome = await session.generateForward(
        acceptedPublishedSuffix: boundary,
        operation: controls,
      );
      expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
      final accepted = outcome as CanonicalReaderPaginationPathAccepted;
      final run = _AcceptedRun(session, controls, accepted);

      final appended = state.publishCanonical(
        _request(
          run,
          operation: CanonicalDisplayPublicationOperation.append,
          predecessor: predecessor,
          committedCard: state.canonicalCards.first,
        ),
      );
      expect(
        appended.kind,
        CanonicalDisplayPublicationOutcomeKind.acceptedAppend,
      );
      expect(
        _cardsBytes(
          state.canonicalCards.take(first.accepted.publishableCards.length),
        ),
        prefixBytes,
      );
      final acceptedBytes = _stateBytes(state);

      final replay = state.publishCanonical(
        _request(
          run,
          operation: CanonicalDisplayPublicationOperation.append,
          predecessor: predecessor,
          committedCard: state.canonicalCards.first,
        ),
      );
      expect(
        replay.kind,
        CanonicalDisplayPublicationOutcomeKind.idempotentAlreadyApplied,
      );
      expect(_stateBytes(state), acceptedBytes);
    });

    testWidgets(
      'append uses the published frontier seam before the next input cursor',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);
        final session = harness.canonicalSessionForP04(
          deferPublicationCommit: true,
        );
        final state = _state(harness);
        final targetControls = harness.canonicalOperationForP04(
          priority: DisplayRangeTaskPriority.directTarget,
        );
        final target =
            await session.generateTarget(
                  target: harness.canonicalTargetForP04(session, 2),
                  operation: targetControls,
                )
                as CanonicalReaderPaginationPathAccepted;

        expect(
          target.publishableCards.first.sourceSlices.first.sourceOrdinalHint,
          2,
        );
        expect(
          target.publishableCards.first.sourceSlices.last.sourceOrdinalHint,
          3,
        );
        final predecessor = target.continuation;
        expect(
          predecessor.previousFinalizedBoundary.endCursor.sourceOrdinalHint,
          4,
        );
        expect(predecessor.nextSourceCursor.sourceOrdinalHint, 5);
        final frontierStart =
            predecessor.frontier.deferredPredecessor?.sourceSlices.first ??
            predecessor.frontier.pendingTail!.sourceSlices.first;
        expect(frontierStart.sourceOrdinalHint, 4);

        expect(
          state
              .publishCanonical(
                _request(_AcceptedRun(session, targetControls, target)),
              )
              .accepted,
          isTrue,
        );
        expect(session.commitPublication(target), isTrue);
        final suffix = session.publishedSuffixBoundary(
          card: state.canonicalCards.last.card,
          sourceOrdinals: state.canonicalCards.last.sourceSlices
              .map((slice) => slice.sourceOrdinalHint)
              .toSet()
              .toList(),
        )!;
        final forwardControls = harness.canonicalOperationForP04();
        final forward =
            await session.generateForward(
                  acceptedPublishedSuffix: suffix,
                  operation: forwardControls,
                )
                as CanonicalReaderPaginationPathAccepted;
        expect(
          forward.publishableCards.first.sourceSlices.first.sourceOrdinalHint,
          4,
        );
        expect(
          forward.publishableCards.first.sourceSlices.last.sourceOrdinalHint,
          7,
        );

        final result = state.publishCanonical(
          _request(
            _AcceptedRun(session, forwardControls, forward),
            operation: CanonicalDisplayPublicationOperation.append,
            predecessor: predecessor,
            committedCard: state.canonicalCards.first,
          ),
        );
        expect(
          result.kind,
          CanonicalDisplayPublicationOutcomeKind.acceptedAppend,
        );
        expect(session.commitPublication(forward), isTrue);
      },
    );

    testWidgets('replacement preserves a stable committed target or rejects', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      final state = _state(harness);
      final initial = await _initial(harness);
      expect(state.publishCanonical(_request(initial)).accepted, isTrue);

      final targetSession = harness.canonicalSessionForP04();
      final controls = harness.canonicalOperationForP04(
        priority: DisplayRangeTaskPriority.directTarget,
      );
      final outcome = await targetSession.generateTarget(
        target: harness.canonicalTargetForP04(targetSession, 7),
        operation: controls,
      );
      final accepted = outcome as CanonicalReaderPaginationPathAccepted;
      final replacement = state.publishCanonical(
        _request(
          _AcceptedRun(targetSession, controls, accepted),
          operation: CanonicalDisplayPublicationOperation.replacement,
        ),
      );
      expect(
        replacement.kind,
        CanonicalDisplayPublicationOutcomeKind.acceptedReplacement,
      );
      expect(
        (replacement as CanonicalDisplayPublicationAccepted).targetDisplayIndex,
        isNotNull,
      );

      final before = _stateBytes(state);
      final missing = _mutatedCard(accepted.publishableCards.first);
      final rejected = state.publishCanonical(
        _request(
          _AcceptedRun(targetSession, controls, accepted),
          operation: CanonicalDisplayPublicationOperation.replacement,
          committedCard: missing,
        ),
      );
      expect(
        rejected.kind,
        CanonicalDisplayPublicationOutcomeKind.committedCardMismatch,
      );
      expect(_stateBytes(state), before);
    });

    testWidgets(
      'prepend proves overlap and rebases the stable committed card',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);
        final session = harness.canonicalSessionForP04(
          deferPublicationCommit: true,
        );
        final controls = harness.canonicalOperationForP04(
          priority: DisplayRangeTaskPriority.directTarget,
        );
        final target =
            await session.generateTarget(
                  target: harness.canonicalTargetForP04(session, 12),
                  operation: controls,
                )
                as CanonicalReaderPaginationPathAccepted;
        final state = _state(harness);
        final targetRun = _AcceptedRun(session, controls, target);
        expect(state.publishCanonical(_request(targetRun)).accepted, isTrue);
        expect(session.commitPublication(target), isTrue);
        final prefix = state.canonicalCards.first;
        final current = state.canonicalCards.singleWhere(
          (card) =>
              card.identity.signature ==
              target.targetContainment!.cardIdentity.signature,
        );
        final successor = session.acceptedSuccessorStartCursorFor(current)!;
        final backwardControls = harness.canonicalOperationForP04();
        final backward = await session.generateBackward(
          desiredPredecessor: harness.canonicalTargetForP04(session, 8),
          acceptedPublishedPrefix: prefix,
          committedCurrentCard: current,
          acceptedSuccessorStartCursor: successor,
          operation: backwardControls,
        );
        expect(backward, isA<CanonicalReaderBackwardPreparationAccepted>());
        final accepted = backward as CanonicalReaderBackwardPreparationAccepted;
        final suffixBytes = _cardsBytes(state.canonicalCards);
        final result = state.publishCanonical(
          _request(
            _AcceptedRun(session, backwardControls, accepted),
            operation: CanonicalDisplayPublicationOperation.prepend,
            predecessor: state.acceptedCanonicalContinuation,
            committedCard: current,
            prependEvidence: CanonicalDisplayPrependEvidence(
              acceptedPublishedPrefix: prefix,
              regeneratedPublishedPrefix: accepted.regeneratedPublishedPrefix,
              acceptedCommittedCard: current,
              regeneratedCommittedCard: accepted.regeneratedCommittedCard,
              predecessorEndCursor: accepted.predecessorEndCursor,
              currentStartCursor: accepted.currentStartCursor,
              currentEndCursor: accepted.currentEndCursor,
              successorStartCursor: accepted.successorStartCursor,
            ),
          ),
        );

        expect(
          result.kind,
          CanonicalDisplayPublicationOutcomeKind.acceptedPrepend,
        );
        final publication = result as CanonicalDisplayPublicationAccepted;
        expect(publication.insertedBefore, accepted.publishableCards.length);
        expect(publication.committedDisplayIndex, isNotNull);
        expect(
          _cardsBytes(state.canonicalCards.skip(publication.insertedBefore)),
          suffixBytes,
        );
      },
    );

    testWidgets('seeds 40400802-40400810 accept strict regenerated prepends', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      final oracle = await _fullCanonical(harness);
      const cases =
          <({int seed, int target, bool backwardFirst, bool sectionRestart})>[
            (
              seed: 40400802,
              target: 2,
              backwardFirst: false,
              sectionRestart: false,
            ),
            (
              seed: 40400803,
              target: 7,
              backwardFirst: true,
              sectionRestart: false,
            ),
            (
              seed: 40400804,
              target: 8,
              backwardFirst: false,
              sectionRestart: false,
            ),
            (
              seed: 40400805,
              target: 9,
              backwardFirst: true,
              sectionRestart: false,
            ),
            (
              seed: 40400806,
              target: 11,
              backwardFirst: false,
              sectionRestart: false,
            ),
            (
              seed: 40400807,
              target: 12,
              backwardFirst: true,
              sectionRestart: false,
            ),
            (
              seed: 40400808,
              target: 16,
              backwardFirst: false,
              sectionRestart: true,
            ),
            (
              seed: 40400809,
              target: 18,
              backwardFirst: false,
              sectionRestart: false,
            ),
            (
              seed: 40400810,
              target: 15,
              backwardFirst: true,
              sectionRestart: false,
            ),
          ];

      for (final value in cases) {
        await _expectLegalPrependSeed(
          harness,
          seed: value.seed,
          targetOrdinal: value.target,
          backwardFirst: value.backwardFirst,
          sectionRestart: value.sectionRestart,
          expectedCards: oracle.cards,
        );
      }
    });

    testWidgets(
      'rejects gap overlap duplicate reorder and cross-section ownership',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);
        final full = await _fullCanonical(harness);
        expect(full.cards.length, greaterThan(4));

        CanonicalDisplayPublicationOutcomeKind reject(
          List<CanonicalFinalizedReaderCard> cards,
        ) {
          final state = _state(harness);
          return state
              .publishCanonical(
                _request(
                  full.run,
                  finalizedCards: cards,
                  continuation: _continuationWithBoundary(
                    full.run.accepted.continuation,
                    cards.last,
                  ),
                ),
              )
              .kind;
        }

        final splitIndex = full.cards.indexWhere(
          (card) =>
              card.sourceSlices.length == 1 &&
              card.sourceSlices.single.startUtf16 != null &&
              card.sourceSlices.single.endUtf16! -
                      card.sourceSlices.single.startUtf16! >=
                  4,
        );
        expect(splitIndex, isNonNegative);
        final splitCard = full.cards[splitIndex];
        final splitSlice = splitCard.sourceSlices.single;
        final midpoint =
            splitSlice.startUtf16! +
            ((splitSlice.endUtf16! - splitSlice.startUtf16!) ~/ 2);
        final left = _cardWithFirstSlice(
          splitCard,
          _copySlice(splitSlice, endUtf16: midpoint),
          harness,
        );
        final gapRight = _cardWithFirstSlice(
          splitCard,
          _copySlice(splitSlice, startUtf16: midpoint + 1),
          harness,
        );
        final gapCards = List<CanonicalFinalizedReaderCard>.of(full.cards)
          ..replaceRange(splitIndex, splitIndex + 1, [left, gapRight]);
        expect(
          reject(gapCards),
          CanonicalDisplayPublicationOutcomeKind.seamGap,
        );

        final overlapRight = _cardWithFirstSlice(
          splitCard,
          _copySlice(splitSlice, startUtf16: midpoint - 1),
          harness,
        );
        final overlapCards = List<CanonicalFinalizedReaderCard>.of(full.cards)
          ..replaceRange(splitIndex, splitIndex + 1, [left, overlapRight]);
        expect(
          reject(overlapCards),
          CanonicalDisplayPublicationOutcomeKind.seamOverlap,
        );

        final duplicated = List<CanonicalFinalizedReaderCard>.of(full.cards)
          ..insert(1, full.cards.first);
        expect(
          reject(duplicated),
          CanonicalDisplayPublicationOutcomeKind.duplicatedOwnership,
        );

        final reorderIndex = full.cards.indexWhere(
          (card) =>
              card.sourceSlices.first.sourceOrdinalHint >
              full.cards.first.sourceSlices.first.sourceOrdinalHint,
        );
        expect(reorderIndex, isNonNegative);
        final reordered = List<CanonicalFinalizedReaderCard>.of(full.cards);
        final swap = reordered.first;
        reordered[0] = reordered[reorderIndex];
        reordered[reorderIndex] = swap;
        expect(
          reject(reordered),
          CanonicalDisplayPublicationOutcomeKind.reorderedOwnership,
        );

        final differentSection = full.cards.firstWhere(
          (card) =>
              card.sourceSlices.first.sectionIdentity !=
              full.cards.first.sourceSlices.first.sectionIdentity,
        );
        final cross = CanonicalFinalizedReaderCard(
          card: full.cards.first.card,
          identity: full.cards.first.identity,
          sourceSlices: [
            full.cards.first.sourceSlices.first,
            differentSection.sourceSlices.first,
          ],
        );
        final crossed = List<CanonicalFinalizedReaderCard>.of(full.cards)
          ..insert(1, cross);
        expect(
          reject(crossed),
          CanonicalDisplayPublicationOutcomeKind.crossSectionOwnership,
        );
      },
    );

    testWidgets(
      'fails closed for incompatible legacy provisional stale and cancelled input',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);
        final run = await _initial(harness);

        CanonicalDisplayPublicationResult reject(
          CanonicalDisplayPublicationRequest request,
        ) {
          final state = _state(harness);
          final before = _stateBytes(state);
          final result = state.publishCanonical(request);
          expect(result.accepted, isFalse);
          expect(result.publishableCards, isEmpty);
          expect(result.acceptedContinuation, isNull);
          expect(result.hasCacheWriteAuthority, isFalse);
          expect(result.hasCheckpointOrSettlementAuthority, isFalse);
          expect(_stateBytes(state), before);
          return result;
        }

        expect(
          reject(
            _request(
              run,
              continuation: _continuationWithKey(
                run.accepted.continuation,
                publicationFingerprint: 'wrong-publication',
              ),
            ),
          ).kind,
          CanonicalDisplayPublicationOutcomeKind.incompatiblePublication,
        );
        expect(
          reject(_request(run, controlledLayoutIdentity: 'wrong-layout')).kind,
          CanonicalDisplayPublicationOutcomeKind.incompatibleLayout,
        );
        expect(
          reject(
            _request(run, paginationAlgorithmIdentity: 'wrong-pagination'),
          ).kind,
          CanonicalDisplayPublicationOutcomeKind.incompatiblePagination,
        );
        final wrongSourceContinuation = _continuationWithKey(
          run.accepted.continuation,
          parserSourceIdentity: 'wrong-parser-snapshot',
        );
        expect(
          reject(_request(run, continuation: wrongSourceContinuation)).kind,
          CanonicalDisplayPublicationOutcomeKind.incompatibleSourceSnapshot,
        );

        final first = run.accepted.publishableCards.first;
        final legacy = CanonicalFinalizedReaderCard(
          card: first.card,
          identity: ReaderCardIdentity.fromCard(
            publicationFingerprint: harness.publicationFingerprint,
            layoutFingerprint: harness.layoutIdentity,
            card: first.card,
            sourceChunks: harness.sourceChunks,
            sourceIndices: first.sourceSlices
                .map((slice) => slice.sourceOrdinalHint)
                .toList(),
            locationsBySourceIndex: const {},
          ),
          sourceSlices: first.sourceSlices,
        );
        final legacyCards = List<CanonicalFinalizedReaderCard>.of(
          run.accepted.publishableCards,
        )..[0] = legacy;
        expect(
          reject(_request(run, finalizedCards: legacyCards)).kind,
          CanonicalDisplayPublicationOutcomeKind.publishedCardIdentityMismatch,
        );
        expect(
          reject(_request(run, finalizedCards: const [])).kind,
          CanonicalDisplayPublicationOutcomeKind.provisionalResultRejected,
        );
        expect(
          reject(_request(run, currentGenerationIdentity: () => -1)).kind,
          CanonicalDisplayPublicationOutcomeKind.staleGenerationOrSession,
        );
        expect(
          reject(_request(run, isCancelled: () => true)).kind,
          CanonicalDisplayPublicationOutcomeKind.cancellationBeforeCommit,
        );
        var cancelledAtCommit = false;
        expect(
          reject(
            _request(
              run,
              isCancelled: () => cancelledAtCommit,
              beforeCommit: () => cancelledAtCommit = true,
            ),
          ).kind,
          CanonicalDisplayPublicationOutcomeKind.cancellationBeforeCommit,
        );

        final invalidContinuation = CanonicalPaginationContinuation.create(
          key: run.accepted.continuation.key,
          startSourceCursor: run.accepted.continuation.startSourceCursor,
          nextSourceCursor: run.accepted.continuation.nextSourceCursor,
          frontier: run.accepted.continuation.frontier,
          previousFinalizedBoundary: const CanonicalPaginationFinalizedBoundary(
            kind: CanonicalPaginationBoundaryKind.publicationStart,
            endCursor: CanonicalPaginationCursor.logicalEnd(),
            cardIdentity: null,
          ),
          chainOrdinal: run.accepted.continuation.chainOrdinal,
          parentDigest: run.accepted.continuation.parentDigest,
          checkpointReason: run.accepted.continuation.checkpointReason,
          sourcesSinceCheckpoint:
              run.accepted.continuation.sourcesSinceCheckpoint,
          cardsSinceCheckpoint: run.accepted.continuation.cardsSinceCheckpoint,
          terminal: run.accepted.continuation.terminal,
        );
        expect(
          reject(_request(run, continuation: invalidContinuation)).kind,
          CanonicalDisplayPublicationOutcomeKind.missingOrInvalidContinuation,
        );
      },
    );

    testWidgets(
      'validation exception and committed mismatch leave every map unchanged',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);
        final session = harness.canonicalSessionForP04(
          deferPublicationCommit: true,
        );
        final state = _state(harness);
        final initial = await _initial(harness, session: session);
        final checkpointsBefore = session.checkpointIndex.records.length;
        final thrown = state.publishCanonical(
          _request(initial, beforeCommit: () => throw StateError('injected')),
        );
        expect(
          thrown.kind,
          CanonicalDisplayPublicationOutcomeKind.validationError,
        );
        expect(_stateBytes(state), _emptyStateBytes(harness));
        expect(session.checkpointIndex.records.length, checkpointsBefore);
        expect(thrown.hasCacheWriteAuthority, isFalse);
        expect(thrown.hasCheckpointOrSettlementAuthority, isFalse);
        session.rejectPublication(initial.accepted);

        final acceptedInitial = await _initial(harness, session: session);
        expect(
          state.publishCanonical(_request(acceptedInitial)).accepted,
          isTrue,
        );
        expect(session.commitPublication(acceptedInitial.accepted), isTrue);
        final before = _stateBytes(state);
        final predecessor = state.acceptedCanonicalContinuation!;
        final boundary = session.publishedSuffixBoundary(
          card: state.displayChunks.last,
          sourceOrdinals: state.displayToOriginal.last,
        )!;
        final controls = harness.canonicalOperationForP04();
        final next =
            await session.generateForward(
                  acceptedPublishedSuffix: boundary,
                  operation: controls,
                )
                as CanonicalReaderPaginationPathAccepted;
        final mismatch = state.publishCanonical(
          _request(
            _AcceptedRun(session, controls, next),
            operation: CanonicalDisplayPublicationOperation.append,
            predecessor: predecessor,
            committedCard: _mutatedCard(state.canonicalCards.first),
          ),
        );
        expect(
          mismatch.kind,
          CanonicalDisplayPublicationOutcomeKind.committedCardMismatch,
        );
        expect(_stateBytes(state), before);
      },
    );
  });
}

Future<ReaderCorePaginationHarness> _harness(
  WidgetTester tester,
  List<BookChunk> chunks,
) => ReaderCorePaginationHarness.install(
  tester: tester,
  sourceChunks: chunks,
  bookId: 'p04-007-book',
  publicationFingerprint: 'p04-007-publication',
);

ProgressiveDisplayState _state(ReaderCorePaginationHarness harness) =>
    ProgressiveDisplayState(
      signature: DisplayGenerationSignature(
        bookId: harness.bookId,
        parsedContentVersion: 1,
        layoutSignature: harness.layoutIdentity,
        settingsSignature: 'p04-007',
        viewportSignature: 'p04-007',
        cacheKey: 'p04-007',
      ),
      sourceChunkCount: harness.sourceChunks.length,
    );

Future<_AcceptedRun> _initial(
  ReaderCorePaginationHarness harness, {
  CanonicalReaderPaginationSession? session,
}) async {
  final active = session ?? harness.canonicalSessionForP04();
  final controls = harness.canonicalOperationForP04(
    priority: DisplayRangeTaskPriority.initialVisible,
  );
  final outcome = await active.generateInitial(
    restart: const CanonicalPaginationPublicationStart(),
    operation: controls,
  );
  expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
  return _AcceptedRun(
    active,
    controls,
    outcome as CanonicalReaderPaginationPathAccepted,
  );
}

Future<_FullCanonicalRun> _fullCanonical(
  ReaderCorePaginationHarness harness,
) async {
  final session = harness.canonicalSessionForP04();
  var run = await _initial(harness, session: session);
  final cards = <CanonicalFinalizedReaderCard>[
    ...run.accepted.publishableCards,
  ];
  for (var count = 0; count < 32; count++) {
    if (run.accepted is CanonicalReaderLogicalEnd) {
      return _FullCanonicalRun(run, cards);
    }
    final last = cards.last;
    final boundary = session.publishedSuffixBoundary(
      card: last.card,
      sourceOrdinals: last.sourceSlices
          .map((slice) => slice.sourceOrdinalHint)
          .toSet()
          .toList(),
    )!;
    final controls = harness.canonicalOperationForP04();
    final outcome = await session.generateForward(
      acceptedPublishedSuffix: boundary,
      operation: controls,
    );
    expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
    run = _AcceptedRun(
      session,
      controls,
      outcome as CanonicalReaderPaginationPathAccepted,
    );
    cards.addAll(run.accepted.publishableCards);
  }
  throw StateError('Canonical fixture did not reach logical end.');
}

CanonicalDisplayPublicationRequest _request(
  _AcceptedRun run, {
  CanonicalDisplayPublicationOperation operation =
      CanonicalDisplayPublicationOperation.initial,
  List<CanonicalFinalizedReaderCard>? finalizedCards,
  CanonicalPaginationContinuation? continuation,
  CanonicalPaginationContinuation? predecessor,
  CanonicalDisplayPrependEvidence? prependEvidence,
  CanonicalFinalizedReaderCard? committedCard,
  String? sessionIdentity,
  String? controlledLayoutIdentity,
  String? paginationAlgorithmIdentity,
  int Function()? currentGenerationIdentity,
  bool Function()? isCancelled,
  void Function()? beforeCommit,
}) => CanonicalDisplayPublicationRequest(
  operation: operation,
  sessionIdentity:
      sessionIdentity ?? '${run.session.sourceSnapshot.snapshotDigest}|test',
  generationIdentity: run.controls.generationToken,
  currentGenerationIdentity:
      currentGenerationIdentity ?? () => run.controls.generationToken,
  sourceSnapshot: run.session.sourceSnapshot,
  controlledLayoutIdentity:
      controlledLayoutIdentity ?? run.session.controlledLayoutIdentity,
  paginationAlgorithmIdentity:
      paginationAlgorithmIdentity ?? readerPaginationAlgorithmVersion,
  finalizedCards: finalizedCards ?? run.accepted.publishableCards,
  continuation: continuation ?? run.accepted.continuation,
  predecessorContinuation: predecessor,
  targetContainment: run.accepted.targetContainment,
  prependEvidence: prependEvidence,
  committedCard: committedCard,
  isCancelled: isCancelled ?? () => false,
  beforeCommit: beforeCommit,
);

CanonicalPaginationContinuation _continuationWithBoundary(
  CanonicalPaginationContinuation source,
  CanonicalFinalizedReaderCard last,
) => CanonicalPaginationContinuation.create(
  key: source.key,
  startSourceCursor: source.startSourceCursor,
  nextSourceCursor: source.nextSourceCursor,
  frontier: source.frontier,
  previousFinalizedBoundary: CanonicalPaginationFinalizedBoundary(
    kind: CanonicalPaginationBoundaryKind.finalizedCard,
    endCursor: source.previousFinalizedBoundary.endCursor,
    cardIdentity: last.identity,
  ),
  chainOrdinal: source.chainOrdinal,
  parentDigest: source.parentDigest,
  checkpointReason: source.checkpointReason,
  sourcesSinceCheckpoint: source.sourcesSinceCheckpoint,
  cardsSinceCheckpoint: source.cardsSinceCheckpoint,
  terminal: source.terminal,
);

CanonicalPaginationContinuation _continuationWithKey(
  CanonicalPaginationContinuation source, {
  String? parserSourceIdentity,
  String? publicationFingerprint,
}) => CanonicalPaginationContinuation.create(
  key: CanonicalPaginationContinuationKey(
    bookId: source.key.bookId,
    publicationFingerprint:
        publicationFingerprint ?? source.key.publicationFingerprint,
    parserSourceIdentity:
        parserSourceIdentity ?? source.key.parserSourceIdentity,
    sourceRevision: source.key.sourceRevision,
    sourceSnapshotDigest: source.key.sourceSnapshotDigest,
    paginationAlgorithmIdentity: source.key.paginationAlgorithmIdentity,
    controlledLayoutIdentity: source.key.controlledLayoutIdentity,
    sectionIdentity: source.key.sectionIdentity,
    boundaryCursor: source.key.boundaryCursor,
  ),
  startSourceCursor: source.startSourceCursor,
  nextSourceCursor: source.nextSourceCursor,
  frontier: source.frontier,
  previousFinalizedBoundary: source.previousFinalizedBoundary,
  chainOrdinal: source.chainOrdinal,
  parentDigest: source.parentDigest,
  checkpointReason: source.checkpointReason,
  sourcesSinceCheckpoint: source.sourcesSinceCheckpoint,
  cardsSinceCheckpoint: source.cardsSinceCheckpoint,
  terminal: source.terminal,
);

CanonicalPaginationSourceSlice _copySlice(
  CanonicalPaginationSourceSlice source, {
  int? startUtf16,
  int? endUtf16,
}) => CanonicalPaginationSourceSlice(
  sourceIdentity: source.sourceIdentity,
  sectionIdentity: source.sectionIdentity,
  spineIdentity: source.spineIdentity,
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
  startUtf16: startUtf16 ?? source.startUtf16,
  endUtf16: endUtf16 ?? source.endUtf16,
  tableRowStart: source.tableRowStart,
  tableRowEndExclusive: source.tableRowEndExclusive,
);

CanonicalFinalizedReaderCard _cardWithFirstSlice(
  CanonicalFinalizedReaderCard source,
  CanonicalPaginationSourceSlice first,
  ReaderCorePaginationHarness harness,
) {
  final slices = <CanonicalPaginationSourceSlice>[
    first,
    ...source.sourceSlices.skip(1),
  ];
  return CanonicalFinalizedReaderCard(
    card: source.card,
    identity: CanonicalReaderCardIdentityBuilder.build(
      publicationFingerprint: harness.publicationFingerprint,
      controlledLayoutIdentity: harness.layoutIdentity,
      paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
      orderedSourceSlices: slices,
    ),
    sourceSlices: slices,
  );
}

CanonicalFinalizedReaderCard _mutatedCard(
  CanonicalFinalizedReaderCard source,
) => CanonicalFinalizedReaderCard(
  card: source.card.copyWith(text: '${source.card.text ?? ''}!'),
  identity: source.identity,
  sourceSlices: source.sourceSlices,
);

String _cardsBytes(Iterable<CanonicalFinalizedReaderCard> cards) =>
    canonicalJsonEncode([
      for (final card in cards)
        {
          'card': card.card.toJson(),
          'identity': card.identity.toJson(),
          'slices': card.sourceSlices
              .map((slice) => slice.toCanonicalJson())
              .toList(),
        },
    ]);

String _stateBytes(ProgressiveDisplayState state) => canonicalJsonEncode({
  'ranges': state.ranges.map((range) => range.sourceRange.toString()).toList(),
  'cards': state.displayChunks.map((card) => card.toJson()).toList(),
  'displayToOriginal': state.displayToOriginal,
  'originalToDisplay': state.originalToDisplay,
  'canonical': _cardsBytes(state.canonicalCards),
  'continuation': state.acceptedCanonicalContinuation?.canonicalEncoding,
  'cache': state.hasCanonicalCacheWriteAuthority,
  'complete': state.generationComplete,
});

String _emptyStateBytes(ReaderCorePaginationHarness harness) =>
    _stateBytes(_state(harness));

final class _AcceptedRun {
  const _AcceptedRun(this.session, this.controls, this.accepted);

  final CanonicalReaderPaginationSession session;
  final CanonicalPaginationOperationControls controls;
  final CanonicalReaderPaginationPathAccepted accepted;
}

final class _FullCanonicalRun {
  const _FullCanonicalRun(this.run, this.cards);

  final _AcceptedRun run;
  final List<CanonicalFinalizedReaderCard> cards;
}

Future<void> _expectLegalPrependSeed(
  ReaderCorePaginationHarness harness, {
  required int seed,
  required int targetOrdinal,
  required bool backwardFirst,
  required bool sectionRestart,
  required List<CanonicalFinalizedReaderCard> expectedCards,
}) async {
  final session = harness.canonicalSessionForP04(deferPublicationCommit: true);
  final state = _state(harness);
  final initialControls = harness.canonicalOperationForP04(
    priority: DisplayRangeTaskPriority.directTarget,
  );
  final CanonicalReaderPaginationPathResult initialOutcome;
  if (sectionRestart) {
    final owner = session.sourceSnapshot.ownerAt(targetOrdinal);
    initialOutcome = await session.generateInitial(
      restart: CanonicalPaginationTrustedSectionStart(
        sectionIdentity: owner.sectionIdentity,
        sourceIdentity: owner.sourceIdentity,
        sourceOrdinalHint: owner.sourceOrdinalHint,
      ),
      operation: initialControls,
    );
  } else {
    initialOutcome = await session.generateTarget(
      target: harness.canonicalTargetForP04(session, targetOrdinal),
      operation: initialControls,
    );
  }
  expect(
    initialOutcome,
    isA<CanonicalReaderPaginationPathAccepted>(),
    reason: 'seed=$seed initial',
  );
  final initial = initialOutcome as CanonicalReaderPaginationPathAccepted;
  expect(
    state
        .publishCanonical(
          _request(_AcceptedRun(session, initialControls, initial)),
        )
        .accepted,
    isTrue,
    reason: 'seed=$seed initial publication',
  );
  expect(session.commitPublication(initial), isTrue, reason: 'seed=$seed');
  final committed = sectionRestart
      ? state.canonicalCards.first
      : state.canonicalCards.singleWhere(
          (card) =>
              card.identity.signature ==
              initial.targetContainment!.cardIdentity.signature,
        );

  Future<void> appendToEnd() async {
    for (var count = 0; count < 16; count++) {
      if (state.acceptedCanonicalContinuation!.terminal) return;
      final last = state.canonicalCards.last;
      final boundary = session.publishedSuffixBoundary(
        card: last.card,
        sourceOrdinals: last.sourceSlices
            .map((slice) => slice.sourceOrdinalHint)
            .toSet()
            .toList(),
      )!;
      final controls = harness.canonicalOperationForP04();
      final outcome = await session.generateForward(
        acceptedPublishedSuffix: boundary,
        operation: controls,
      );
      expect(
        outcome,
        isA<CanonicalReaderPaginationPathAccepted>(),
        reason: 'seed=$seed forward',
      );
      final accepted = outcome as CanonicalReaderPaginationPathAccepted;
      if (accepted.publishableCards.isNotEmpty) {
        final predecessor = state.acceptedCanonicalContinuation;
        final publication = state.publishCanonical(
          _request(
            _AcceptedRun(session, controls, accepted),
            operation: CanonicalDisplayPublicationOperation.append,
            predecessor: predecessor,
            committedCard: committed,
          ),
        );
        expect(publication.accepted, isTrue, reason: 'seed=$seed append');
        expect(
          session.commitPublication(accepted),
          isTrue,
          reason: 'seed=$seed',
        );
      }
    }
    fail('seed=$seed forward traversal did not terminate');
  }

  Future<void> prependToStart() async {
    if (state.canonicalCards.first.sourceSlices.first.sourceOrdinalHint == 0) {
      return;
    }
    final prefix = state.canonicalCards.first;
    final successor = session.acceptedSuccessorStartCursorFor(committed)!;
    final controls = harness.canonicalOperationForP04();
    final outcome = await session.generateBackward(
      desiredPredecessor: harness.canonicalTargetForP04(session, 0),
      acceptedPublishedPrefix: prefix,
      committedCurrentCard: committed,
      acceptedSuccessorStartCursor: successor,
      operation: controls,
    );
    expect(
      outcome,
      isA<CanonicalReaderBackwardPreparationAccepted>(),
      reason: 'seed=$seed backward',
    );
    final accepted = outcome as CanonicalReaderBackwardPreparationAccepted;
    expect(
      accepted.regeneratedCommittedCard.identity.toJson(),
      committed.identity.toJson(),
      reason: 'seed=$seed committed identity',
    );
    expect(
      accepted.regeneratedCommittedCard.sourceSlices
          .map((slice) => slice.toCanonicalJson())
          .toList(),
      committed.sourceSlices.map((slice) => slice.toCanonicalJson()).toList(),
      reason: 'seed=$seed committed slices',
    );
    expect(
      canonicalBookChunkOwnershipDigest(accepted.regeneratedCommittedCard.card),
      canonicalBookChunkOwnershipDigest(committed.card),
      reason: 'seed=$seed visible/structural content',
    );
    final acceptedContinuation = state.acceptedCanonicalContinuation!;
    final suffixBytes = _cardsBytes(state.canonicalCards);
    final regeneratedCommitted = seed == 40400802
        ? _withTransientCardIndexes(accepted.regeneratedCommittedCard, 1000)
        : accepted.regeneratedCommittedCard;
    final publication = state.publishCanonical(
      _request(
        _AcceptedRun(session, controls, accepted),
        operation: CanonicalDisplayPublicationOperation.prepend,
        predecessor: acceptedContinuation,
        committedCard: committed,
        prependEvidence: CanonicalDisplayPrependEvidence(
          acceptedPublishedPrefix: prefix,
          regeneratedPublishedPrefix: accepted.regeneratedPublishedPrefix,
          acceptedCommittedCard: committed,
          regeneratedCommittedCard: regeneratedCommitted,
          predecessorEndCursor: accepted.predecessorEndCursor,
          currentStartCursor: accepted.currentStartCursor,
          currentEndCursor: accepted.currentEndCursor,
          successorStartCursor: accepted.successorStartCursor,
        ),
      ),
    );
    expect(publication.accepted, isTrue, reason: 'seed=$seed prepend');
    final inserted =
        (publication as CanonicalDisplayPublicationAccepted).insertedBefore;
    expect(
      _cardsBytes(state.canonicalCards.skip(inserted)),
      suffixBytes,
      reason: 'seed=$seed immutable suffix',
    );
    expect(
      state.acceptedCanonicalContinuation!.canonicalEncoding,
      acceptedContinuation.canonicalEncoding,
      reason: 'seed=$seed accepted continuation',
    );
    expect(session.commitPublication(accepted), isTrue, reason: 'seed=$seed');
  }

  if (backwardFirst) {
    await prependToStart();
    await appendToEnd();
  } else {
    await appendToEnd();
    await prependToStart();
  }
  expect(
    _cardsBytes(state.canonicalCards),
    _cardsBytes(expectedCards),
    reason: 'seed=$seed canonical result',
  );
}

CanonicalFinalizedReaderCard _withTransientCardIndexes(
  CanonicalFinalizedReaderCard source,
  int delta,
) {
  final ranges = source.card.sourceRanges;
  return CanonicalFinalizedReaderCard(
    card: source.card.copyWith(
      index: source.card.index + delta,
      sourceRanges: ranges == null
          ? null
          : [
              for (final range in ranges)
                ChunkSourceRange(
                  originalChunkIndex: range.originalChunkIndex + delta,
                  originalStartOffset: range.originalStartOffset,
                  originalEndOffset: range.originalEndOffset,
                  displayStartOffset: range.displayStartOffset,
                  displayEndOffset: range.displayEndOffset,
                  logicalParagraphId: range.logicalParagraphId,
                  paragraphStartOffset: range.paragraphStartOffset,
                  paragraphEndOffset: range.paragraphEndOffset,
                  isParagraphStart: range.isParagraphStart,
                  isParagraphEnd: range.isParagraphEnd,
                ),
            ],
    ),
    identity: source.identity,
    sourceSlices: source.sourceSlices,
  );
}
