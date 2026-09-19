import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import '../support/reader_contract_sandbox.dart';
import 'reader_core_cache_order_harness.dart';
import 'reader_core_pagination_harness.dart';

const _fixedSeeds = <int>[
  40400801,
  40400802,
  40400803,
  40400804,
  40400805,
  40400806,
  40400807,
  40400808,
  40400809,
  40400810,
  40400811,
  40400812,
];

const _reviewedStandardMembership = <List<(int, int, int)>>[
  [(0, 0, 20), (1, 0, 22)],
  [(2, 0, 20), (3, 0, 23)],
  [(4, 0, 10), (5, 0, 10), (6, 0, 12), (7, 0, 198)],
  [(8, 0, 33)],
  [(9, 0, 19), (10, 0, 18)],
  // Canonical table ownership is the authored body-row interval, not encoded
  // table-text UTF-16. The source oracle still independently owns 136 UTF-16.
  [(11, 0, 1)],
  [(12, 0, 56), (13, 0, 50), (14, 0, 37), (15, 0, 63)],
  [(16, 0, 22)],
  [(17, 0, 52), (18, 0, 33), (19, 0, 55)],
];

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('nalori_p04_008_');
  });

  tearDownAll(() => fixture.close());

  group('[TASK-P04-008] fixed-seed canonical construction gate', () {
    testWidgets(
      'ten legal fixture plans repeat exact canonical cards, chains, work, and retained state',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
          bookId: 'p04-008-fixture',
          publicationFingerprint: 'p04-008-fixture-publication',
        );
        final oraclePlan = _planFor(_fixedSeeds.first, 0);
        final oracle = await _executeFixturePlan(harness, oraclePlan);
        _expectReviewedMembership(oracle.cards, reason: oracle.diagnostics);
        _expectCompleteFixtureCoverage(oracle.cards, fixture.sourceChunks);

        final failures = <String>[];
        final failureSeeds = <int>[];
        final completedRuns = <_GateRun>[oracle];
        for (var index = 0; index < 10; index++) {
          final plan = _planFor(_fixedSeeds[index], index);
          final regenerated = _planFor(_fixedSeeds[index], index);
          expect(
            regenerated.canonicalJson,
            plan.canonicalJson,
            reason: 'seed=${plan.seed}',
          );

          try {
            final first = await _executeFixturePlan(harness, plan);
            final second = await _executeFixturePlan(harness, regenerated);
            final failure = _failureEvidence(
              plan: plan,
              expected: oracle,
              actual: first,
            );
            expect(
              first.canonicalCardsJson,
              oracle.canonicalCardsJson,
              reason: failure,
            );
            expect(
              second.canonicalCardsJson,
              first.canonicalCardsJson,
              reason: failure,
            );
            expect(
              second.continuationChainJson,
              first.continuationChainJson,
              reason: failure,
            );
            expect(second.workJson, first.workJson, reason: failure);
            expect(second.retainedJson, first.retainedJson, reason: failure);
            expect(
              first.maxAtomicWork,
              lessThanOrEqualTo(110),
              reason: failure,
            );
            expect(
              first.maxPrivatePredecessors,
              lessThanOrEqualTo(7),
              reason: failure,
            );
            expect(
              first.maxFrontierCandidates,
              lessThanOrEqualTo(2),
              reason: failure,
            );
            expect(
              first.maxFrontierEntries,
              lessThanOrEqualTo(61),
              reason: failure,
            );
            expect(
              first.maxContinuationRecords,
              lessThanOrEqualTo(25),
              reason: failure,
            );
            expect(
              first.maxResidentCards,
              lessThanOrEqualTo(96),
              reason: failure,
            );
            expect(first.continuationsCopiedText, 0, reason: failure);
            _expectCompleteFixtureCoverage(first.cards, fixture.sourceChunks);
            completedRuns.add(first);
          } on Object catch (error) {
            failureSeeds.add(plan.seed);
            failures.add(
              'seed=${plan.seed}; plan=${plan.canonicalJson}; '
              'error=$error',
            );
          }
        }
        // ignore: avoid_print
        print(
          'P04-008 fixture summary: failureSeeds=$failureSeeds; '
          'completedPlans=${completedRuns.length}/10; '
          'maxAtomic=${completedRuns.map((run) => run.maxAtomicWork).reduce(math.max)}; '
          'maxPrivatePredecessors=${completedRuns.map((run) => run.maxPrivatePredecessors).reduce(math.max)}; '
          'maxFrontierCandidates=${completedRuns.map((run) => run.maxFrontierCandidates).reduce(math.max)}; '
          'maxFrontierEntries=${completedRuns.map((run) => run.maxFrontierEntries).reduce(math.max)}; '
          'maxContinuationRecords=${completedRuns.map((run) => run.maxContinuationRecords).reduce(math.max)}; '
          'maxResidentCards=${completedRuns.map((run) => run.maxResidentCards).reduce(math.max)}; '
          'copiedText=${completedRuns.map((run) => run.continuationsCopiedText).reduce(math.max)}',
        );
        expect(failures, isEmpty, reason: failures.join('\n---\n'));
      },
    );

    testWidgets(
      'real memory and fresh-service cache hits fail closed then regenerate identically',
      (tester) async {
        for (var index = 10; index < _fixedSeeds.length; index++) {
          final plan = _planFor(_fixedSeeds[index], index);
          final first = await _executeCachePlan(tester, fixture, plan);
          final second = await _executeCachePlan(tester, fixture, plan);
          expect(second.planJson, first.planJson, reason: first.diagnostics);
          expect(
            second.canonicalCardsJson,
            first.canonicalCardsJson,
            reason: first.diagnostics,
          );
          expect(
            second.evidenceJson,
            first.evidenceJson,
            reason: first.diagnostics,
          );
          expect(first.diagnostics, contains('direct-publication-rejected'));
          expect(first.diagnostics, contains('bounded-canonical-regeneration'));
        }
      },
    );
  });

  testWidgets(
    '[REQ-010, REQ-044, REQ-045, REQ-048] distant target advances cumulatively, evicts checkpoints, and replaces display state within bounds',
    (tester) async {
      final sources = _syntheticSources(320);
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: sources,
        bookId: 'p04-008-synthetic',
        publicationFingerprint: 'p04-008-synthetic-publication',
      );
      final session = harness.canonicalSessionForP04(
        deferPublicationCommit: true,
      );
      final state = _state(harness);
      final recordsSeen = <String>[];
      final sectionBoundaryDigests = <String>[];
      final operations = <Map<String, Object?>>[];
      CanonicalPaginationRestart restart =
          const CanonicalPaginationPublicationStart();
      CanonicalPaginationContinuation? predecessor;
      var firstPublication = true;
      var maximumCards = 0;
      var maximumRecords = 0;
      var maximumAtomic = 0;
      var maximumFrontierEntries = 0;
      var maximumFrontierCandidates = 0;

      for (var operationIndex = 0; operationIndex < 64; operationIndex++) {
        final controls = harness.canonicalOperationForP04();
        final outcome = await session.generateInitial(
          restart: restart,
          operation: controls,
          budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 8),
        );
        expect(
          outcome,
          isA<CanonicalReaderPaginationPathAccepted>(),
          reason: outcome is CanonicalReaderPaginationPathRejected
              ? 'operation=$operationIndex; restart='
                    '${restart is CanonicalPaginationContinuation ? restart.canonicalEncoding : restart}; '
                    'operations=${canonicalJsonEncode(operations)}; '
                    '${outcome.rejection.reason}: ${outcome.rejection.message}'
              : '$outcome',
        );
        final accepted = outcome as CanonicalReaderPaginationPathAccepted;
        expect(accepted.boundedWorkEntriesConsumed, lessThanOrEqualTo(110));
        expect(accepted.diagnostics.sourceChunksEntered, lessThanOrEqualTo(8));
        expect(accepted.continuation.copiedSourceTextUtf16, 0);
        maximumAtomic = math.max(
          maximumAtomic,
          accepted.boundedWorkEntriesConsumed,
        );
        maximumFrontierEntries = math.max(
          maximumFrontierEntries,
          accepted.diagnostics.peakFrontierEntries,
        );
        maximumFrontierCandidates = math.max(
          maximumFrontierCandidates,
          accepted.continuation.frontier.cardCandidateCount,
        );
        recordsSeen.add(accepted.continuation.integrityDigest);
        if (accepted.continuation.checkpointReason ==
            CanonicalPaginationCheckpointReason.sectionBoundary) {
          sectionBoundaryDigests.add(accepted.continuation.integrityDigest);
        }
        operations.add(<String, Object?>{
          'operation': operationIndex,
          'start': accepted.continuation.startSourceCursor.toCanonicalJson(),
          'next': accepted.continuation.nextSourceCursor.toCanonicalJson(),
          'work': accepted.boundedWorkEntriesConsumed,
          'cards': accepted.publishableCards.length,
          'frontierCandidates':
              accepted.continuation.frontier.cardCandidateCount,
          'frontierEntries': accepted.diagnostics.peakFrontierEntries,
          'reason': accepted.continuation.checkpointReason.name,
        });
        // ignore: avoid_print
        print(
          'P04-008 synthetic accepted ${canonicalJsonEncode(operations.last)}',
        );

        if (accepted.publishableCards.isNotEmpty) {
          final published = state.publishCanonical(
            _publicationRequest(
              harness: harness,
              session: session,
              controls: controls,
              accepted: accepted,
              operation: firstPublication
                  ? CanonicalDisplayPublicationOperation.initial
                  : CanonicalDisplayPublicationOperation.append,
              predecessor: predecessor,
              committedCard: firstPublication
                  ? null
                  : state.canonicalCards.first,
            ),
          );
          expect(
            published.accepted,
            isTrue,
            reason: canonicalJsonEncode(operations),
          );
          expect(session.commitPublication(accepted), isTrue);
          firstPublication = false;
          predecessor = accepted.continuation;
          maximumCards = math.max(maximumCards, state.canonicalCards.length);
          maximumRecords = math.max(
            maximumRecords,
            session.checkpointIndex.records.length,
          );
        }
        restart = accepted.continuation;
        if (!accepted.continuation.nextSourceCursor.isLogicalEnd &&
            accepted.continuation.nextSourceCursor.sourceOrdinalHint >= 264) {
          break;
        }
      }

      expect(operations.length, greaterThan(25));
      expect(session.checkpointIndex.records.length, 25);
      expect(maximumRecords, 25);
      expect(maximumCards, lessThanOrEqualTo(96));
      expect(maximumAtomic, lessThanOrEqualTo(110));
      expect(maximumFrontierEntries, lessThanOrEqualTo(61));
      expect(maximumFrontierCandidates, lessThanOrEqualTo(2));
      expect(sectionBoundaryDigests, hasLength(2));
      for (final digest in sectionBoundaryDigests) {
        expect(
          session.checkpointIndex.requireDigest(digest).kind,
          CanonicalPaginationContinuationValidationKind.accepted,
        );
      }
      final evicted = recordsSeen.firstWhere(
        (digest) =>
            session.checkpointIndex.requireDigest(digest).kind ==
            CanonicalPaginationContinuationValidationKind
                .requiredEarlierRestart,
      );
      expect(
        session.checkpointIndex.requireDigest(evicted).kind,
        CanonicalPaginationContinuationValidationKind.requiredEarlierRestart,
      );
      final active = session.checkpointIndex.activeFrontier!;
      expect(
        session.checkpointIndex.requireDigest(active.integrityDigest).kind,
        CanonicalPaginationContinuationValidationKind.accepted,
      );
      expect(
        session.checkpointIndex.requireDigest(active.parentDigest!).kind,
        CanonicalPaginationContinuationValidationKind.accepted,
      );

      final beforeTargetCards = state.canonicalCards.length;
      final targetControls = harness.canonicalOperationForP04(
        priority: DisplayRangeTaskPriority.directTarget,
      );
      final targetOutcome = await session.generateTarget(
        target: harness.canonicalTargetForP04(session, 280),
        operation: targetControls,
      );
      expect(
        targetOutcome,
        isA<CanonicalReaderPaginationPathAccepted>(),
        reason: canonicalJsonEncode(operations),
      );
      final target = targetOutcome as CanonicalReaderPaginationPathAccepted;
      expect(target.targetContainment, isNotNull);
      expect(target.boundedWorkEntriesConsumed, lessThanOrEqualTo(110));
      expect(target.publishableCards, isNotEmpty);
      expect(
        target.publishableCards.any(
          (card) =>
              card.identity.signature ==
              target.targetContainment!.cardIdentity.signature,
        ),
        isTrue,
      );
      final replacement = state.publishCanonical(
        _publicationRequest(
          harness: harness,
          session: session,
          controls: targetControls,
          accepted: target,
          operation: CanonicalDisplayPublicationOperation.replacement,
          targetContainment: target.targetContainment,
        ),
      );
      expect(
        replacement.kind,
        CanonicalDisplayPublicationOutcomeKind.acceptedReplacement,
      );
      expect(session.commitPublication(target), isTrue);
      expect(state.canonicalCards.length, lessThanOrEqualTo(96));
      expect(state.canonicalCards.length, lessThan(beforeTargetCards));

      final stateBeforeCancellation = _stateJson(state);
      var checks = 0;
      final cancelled = await session.generateTarget(
        target: harness.canonicalTargetForP04(session, 300),
        operation: harness.canonicalOperationForP04(
          priority: DisplayRangeTaskPriority.directTarget,
          isCancelled: () => ++checks > 4,
        ),
      );
      expect(cancelled, isNot(isA<CanonicalReaderPaginationPathAccepted>()));
      expect(_stateJson(state), stateBeforeCancellation);

      final regeneratedControls = harness.canonicalOperationForP04(
        priority: DisplayRangeTaskPriority.directTarget,
      );
      final regeneratedOutcome = await session.generateTarget(
        target: harness.canonicalTargetForP04(session, 20),
        operation: regeneratedControls,
      );
      expect(regeneratedOutcome, isA<CanonicalReaderPaginationPathAccepted>());
      final regenerated =
          regeneratedOutcome as CanonicalReaderPaginationPathAccepted;
      expect(regenerated.boundedWorkEntriesConsumed, lessThanOrEqualTo(110));
      expect(regenerated.targetContainment, isNotNull);
      expect(
        state
            .publishCanonical(
              _publicationRequest(
                harness: harness,
                session: session,
                controls: regeneratedControls,
                accepted: regenerated,
                operation: CanonicalDisplayPublicationOperation.replacement,
                targetContainment: regenerated.targetContainment,
              ),
            )
            .accepted,
        isTrue,
      );
      expect(session.commitPublication(regenerated), isTrue);
      expect(state.canonicalCards.length, lessThanOrEqualTo(96));
    },
  );
}

enum _PlanKind {
  publication,
  targetForwardBackward,
  targetBackwardForward,
  singletonForwardBackward,
  singletonBackwardForward,
  sectionRestart,
  cacheMemory,
  cacheReload,
}

final class _Plan {
  const _Plan({
    required this.seed,
    required this.kind,
    required this.target,
    required this.firstSourceBudget,
    required this.partitions,
  });

  final int seed;
  final _PlanKind kind;
  final int? target;
  final int firstSourceBudget;
  final List<SourceChunkRange> partitions;

  String get canonicalJson => canonicalJsonEncode(<String, Object?>{
    'seed': seed,
    'kind': kind.name,
    'target': target,
    'firstSourceBudget': firstSourceBudget,
    'partitions': partitions.map((range) => range.toString()).toList(),
  });
}

_Plan _planFor(int seed, int index) {
  final random = math.Random(seed);
  const kinds = <_PlanKind>[
    _PlanKind.publication,
    _PlanKind.targetForwardBackward,
    _PlanKind.targetBackwardForward,
    _PlanKind.singletonForwardBackward,
    _PlanKind.singletonBackwardForward,
    _PlanKind.targetForwardBackward,
    _PlanKind.targetBackwardForward,
    _PlanKind.sectionRestart,
    _PlanKind.targetForwardBackward,
    _PlanKind.targetBackwardForward,
    _PlanKind.cacheMemory,
    _PlanKind.cacheReload,
  ];
  const targets = <int?>[null, 2, 7, 8, 9, 11, 12, 16, 18, 15, 8, 18];
  final partitions = <SourceChunkRange>[];
  var start = 0;
  while (start < 20) {
    final end = math.min(20, start + 2 + random.nextInt(6));
    partitions.add(SourceChunkRange(start, end));
    start = end;
  }
  return _Plan(
    seed: seed,
    kind: kinds[index],
    target: targets[index],
    firstSourceBudget: 12 + random.nextInt(9),
    partitions: List.unmodifiable(partitions),
  );
}

final class _GateRun {
  const _GateRun({
    required this.cards,
    required this.canonicalCardsJson,
    required this.continuationChainJson,
    required this.workJson,
    required this.retainedJson,
    required this.diagnostics,
    required this.maxAtomicWork,
    required this.maxPrivatePredecessors,
    required this.maxFrontierCandidates,
    required this.maxFrontierEntries,
    required this.maxContinuationRecords,
    required this.maxResidentCards,
    required this.continuationsCopiedText,
  });

  final List<CanonicalFinalizedReaderCard> cards;
  final String canonicalCardsJson;
  final String continuationChainJson;
  final String workJson;
  final String retainedJson;
  final String diagnostics;
  final int maxAtomicWork;
  final int maxPrivatePredecessors;
  final int maxFrontierCandidates;
  final int maxFrontierEntries;
  final int maxContinuationRecords;
  final int maxResidentCards;
  final int continuationsCopiedText;
}

Future<_GateRun> _executeFixturePlan(
  ReaderCorePaginationHarness harness,
  _Plan plan,
) async {
  final session = harness.canonicalSessionForP04(deferPublicationCommit: true);
  final state = _state(harness);
  final outcomes = <CanonicalReaderPaginationPathAccepted>[];
  final controls = <CanonicalPaginationOperationControls>[];

  Future<void> publish(
    CanonicalReaderPaginationPathAccepted accepted,
    CanonicalPaginationOperationControls operation,
    CanonicalDisplayPublicationOperation publication, {
    CanonicalDisplayPrependEvidence? prependEvidence,
    CanonicalFinalizedReaderCard? committedCard,
  }) async {
    final result = state.publishCanonical(
      _publicationRequest(
        harness: harness,
        session: session,
        controls: operation,
        accepted: accepted,
        operation: publication,
        predecessor:
            publication == CanonicalDisplayPublicationOperation.append ||
                publication == CanonicalDisplayPublicationOperation.prepend
            ? state.acceptedCanonicalContinuation
            : null,
        targetContainment: accepted.targetContainment,
        prependEvidence: prependEvidence,
        committedCard: committedCard,
      ),
    );
    if (!result.accepted || !session.commitPublication(accepted)) {
      final predecessorCursor = state
          .acceptedCanonicalContinuation
          ?.nextSourceCursor
          .toCanonicalJson();
      final incomingStart = accepted.publishableCards.isEmpty
          ? null
          : accepted.publishableCards.first.sourceSlices.first
                .toCanonicalJson();
      throw StateError(
        'seed=${plan.seed}; plan=${plan.canonicalJson}; '
        'publication=${result.kind}; '
        'message=${result is CanonicalDisplayPublicationRejected ? result.message : 'commit rejected'}; '
        'preStateDigest=${readerSha256(_stateJson(state))}; '
        'preStateCards=${_cardSummary(state.canonicalCards)}; '
        'preStateContinuation=${state.acceptedCanonicalContinuation?.integrityDigest}; '
        'predecessorNext=$predecessorCursor; '
        'incomingStart=$incomingStart; '
        'incomingCards=${_cardSummary(accepted.publishableCards)}; '
        'continuationDigest=${accepted.continuation.integrityDigest}; '
        'continuationStart=${accepted.continuation.startSourceCursor.toCanonicalJson()}; '
        'continuationNext=${accepted.continuation.nextSourceCursor.toCanonicalJson()}; '
        'work=${accepted.boundedWorkEntriesConsumed}; '
        'diagnostics=${_diagnosticsJson(accepted.diagnostics)}',
      );
    }
    outcomes.add(accepted);
    controls.add(operation);
  }

  Future<CanonicalReaderPaginationPathAccepted> forwardToEnd() async {
    late CanonicalReaderPaginationPathAccepted accepted;
    for (var count = 0; count < 16; count++) {
      final boundary = session.publishedSuffixBoundary(
        card: state.canonicalCards.last.card,
        sourceOrdinals: state.canonicalCards.last.sourceSlices
            .map((slice) => slice.sourceOrdinalHint)
            .toSet()
            .toList(),
      );
      if (boundary == null) throw StateError('missing suffix boundary');
      final operation = harness.canonicalOperationForP04();
      final outcome = await session.generateForward(
        acceptedPublishedSuffix: boundary,
        operation: operation,
      );
      if (outcome is! CanonicalReaderPaginationPathAccepted) {
        throw StateError('forward rejected: $outcome');
      }
      accepted = outcome;
      if (accepted.publishableCards.isNotEmpty) {
        await publish(
          accepted,
          operation,
          CanonicalDisplayPublicationOperation.append,
          committedCard: state.canonicalCards.first,
        );
      }
      if (accepted is CanonicalReaderLogicalEnd) return accepted;
    }
    throw StateError('forward traversal did not terminate');
  }

  Future<void> prependToStart(CanonicalFinalizedReaderCard committed) async {
    if (state.canonicalCards.first.sourceSlices.first.sourceOrdinalHint == 0) {
      return;
    }
    final prefix = state.canonicalCards.first;
    final successor = session.acceptedSuccessorStartCursorFor(committed);
    if (successor == null) throw StateError('missing committed successor');
    final operation = harness.canonicalOperationForP04();
    final outcome = await session.generateBackward(
      desiredPredecessor: harness.canonicalTargetForP04(session, 0),
      acceptedPublishedPrefix: prefix,
      committedCurrentCard: committed,
      acceptedSuccessorStartCursor: successor,
      operation: operation,
    );
    if (outcome is! CanonicalReaderBackwardPreparationAccepted) {
      throw StateError('backward rejected: $outcome');
    }
    await publish(
      outcome,
      operation,
      CanonicalDisplayPublicationOperation.prepend,
      committedCard: committed,
      prependEvidence: CanonicalDisplayPrependEvidence(
        acceptedPublishedPrefix: prefix,
        regeneratedPublishedPrefix: outcome.regeneratedPublishedPrefix,
        acceptedCommittedCard: committed,
        regeneratedCommittedCard: outcome.regeneratedCommittedCard,
        predecessorEndCursor: outcome.predecessorEndCursor,
        currentStartCursor: outcome.currentStartCursor,
        currentEndCursor: outcome.currentEndCursor,
        successorStartCursor: outcome.successorStartCursor,
      ),
    );
  }

  if (plan.kind == _PlanKind.publication) {
    final operation = harness.canonicalOperationForP04(
      priority: DisplayRangeTaskPriority.initialVisible,
    );
    final outcome = await session.generateInitial(
      restart: const CanonicalPaginationPublicationStart(),
      operation: operation,
      budget: CanonicalPaginationWorkBudget(
        maxSourceChunks: plan.firstSourceBudget,
      ),
    );
    if (outcome is! CanonicalReaderPaginationPathAccepted ||
        outcome.publishableCards.isEmpty) {
      throw StateError('publication start rejected: $outcome');
    }
    await publish(
      outcome,
      operation,
      CanonicalDisplayPublicationOperation.initial,
    );
    if (outcome is! CanonicalReaderLogicalEnd) await forwardToEnd();
  } else if (plan.kind == _PlanKind.sectionRestart) {
    final owner = session.sourceSnapshot.ownerAt(plan.target!);
    final operation = harness.canonicalOperationForP04(
      priority: DisplayRangeTaskPriority.directTarget,
    );
    final outcome = await session.generateInitial(
      restart: CanonicalPaginationTrustedSectionStart(
        sectionIdentity: owner.sectionIdentity,
        sourceIdentity: owner.sourceIdentity,
        sourceOrdinalHint: owner.sourceOrdinalHint,
      ),
      operation: operation,
    );
    if (outcome is! CanonicalReaderPaginationPathAccepted) {
      throw StateError('section restart rejected: $outcome');
    }
    await publish(
      outcome,
      operation,
      CanonicalDisplayPublicationOperation.initial,
    );
    await prependToStart(state.canonicalCards.first);
  } else {
    final operation = harness.canonicalOperationForP04(
      priority: DisplayRangeTaskPriority.directTarget,
    );
    final outcome = await session.generateTarget(
      target: harness.canonicalTargetForP04(session, plan.target!),
      operation: operation,
    );
    if (outcome is! CanonicalReaderPaginationPathAccepted) {
      throw StateError('target rejected: $outcome');
    }
    await publish(
      outcome,
      operation,
      CanonicalDisplayPublicationOperation.initial,
    );
    final committed = state.canonicalCards.singleWhere(
      (card) =>
          card.identity.signature ==
          outcome.targetContainment!.cardIdentity.signature,
    );
    final backwardFirst =
        plan.kind == _PlanKind.targetBackwardForward ||
        plan.kind == _PlanKind.singletonBackwardForward;
    if (backwardFirst) {
      await prependToStart(committed);
      if (!outcome.continuation.terminal) await forwardToEnd();
    } else {
      if (!outcome.continuation.terminal) await forwardToEnd();
      await prependToStart(committed);
    }
  }

  final maxAtomic = outcomes.fold<int>(
    0,
    (value, outcome) => math.max(value, outcome.boundedWorkEntriesConsumed),
  );
  final maxPrivate = outcomes.fold<int>(
    0,
    (value, outcome) =>
        math.max(value, outcome.privatePredecessorCardsDiscarded),
  );
  final maxEntries = outcomes.fold<int>(
    0,
    (value, outcome) =>
        math.max(value, outcome.diagnostics.peakFrontierEntries),
  );
  final maxCandidates = outcomes.fold<int>(
    0,
    (value, outcome) =>
        math.max(value, outcome.continuation.frontier.cardCandidateCount),
  );
  final work = <Map<String, Object?>>[
    for (final outcome in outcomes)
      <String, Object?>{
        'atomic': outcome.boundedWorkEntriesConsumed,
        'entered': outcome.diagnostics.sourceChunksEntered,
        'fullyConsumed': outcome.diagnostics.sourceChunksFullyConsumed,
        'cards': outcome.diagnostics.cardsFinalized,
        'discarded': outcome.privatePredecessorCardsDiscarded,
        'frontier': outcome.diagnostics.peakFrontierEntries,
        'reason': outcome.continuation.checkpointReason.name,
      },
  ];
  final cards = List<CanonicalFinalizedReaderCard>.unmodifiable(
    state.canonicalCards,
  );
  final diagnostics =
      'seed=${plan.seed}; plan=${plan.canonicalJson}; '
      'layout=${harness.layoutIdentity}; owners='
      '${plan.target == null ? 'none' : session.sourceSnapshot.ownerAt(plan.target!).toDigestJson()}; '
      'checkpoints=${session.checkpointIndex.records.map((r) => '${r.checkpointReason.name}:${r.integrityDigest}').join(',')}; '
      'work=${canonicalJsonEncode(work)}; expected=${_reviewedMembershipJson()}; '
      'actual=${_membershipJson(cards)}; canonical=${_cardsJson(cards)}; '
      'residentRecords=${session.checkpointIndex.records.length}; residentCards=${cards.length}';
  return _GateRun(
    cards: cards,
    canonicalCardsJson: _cardsJson(cards),
    continuationChainJson: canonicalJsonEncode(
      outcomes
          .map((outcome) => outcome.continuation.canonicalEncoding)
          .toList(),
    ),
    workJson: canonicalJsonEncode(work),
    retainedJson: canonicalJsonEncode(<String, Object?>{
      'records': session.checkpointIndex.records
          .map((record) => record.canonicalEncoding)
          .toList(),
      'cards': cards.length,
    }),
    diagnostics: diagnostics,
    maxAtomicWork: maxAtomic,
    maxPrivatePredecessors: maxPrivate,
    maxFrontierCandidates: maxCandidates,
    maxFrontierEntries: maxEntries,
    maxContinuationRecords: session.checkpointIndex.records.length,
    maxResidentCards: cards.length,
    continuationsCopiedText: outcomes.fold<int>(
      0,
      (sum, outcome) => sum + outcome.continuation.copiedSourceTextUtf16,
    ),
  );
}

final class _CacheRun {
  const _CacheRun({
    required this.planJson,
    required this.canonicalCardsJson,
    required this.evidenceJson,
    required this.diagnostics,
  });

  final String planJson;
  final String canonicalCardsJson;
  final String evidenceJson;
  final String diagnostics;
}

Future<_CacheRun> _executeCachePlan(
  WidgetTester tester,
  ReaderCoreParsedFixture fixture,
  _Plan plan,
) async {
  final sandbox = (await tester.runAsync(ReaderContractSandbox.create))!;
  try {
    final pagination = await ReaderCorePaginationHarness.install(
      tester: tester,
      sourceChunks: fixture.sourceChunks,
      bookId: 'p04-008-cache-${plan.seed}',
      publicationFingerprint: 'p04-008-cache-publication-${plan.seed}',
      stateCacheKey: 'p04-008-${plan.seed}',
    );
    final cache = ReaderCoreCacheOrderHarness.create(
      sandbox: sandbox,
      pagination: pagination,
    );
    final rangePlan = ReaderCacheRangePlan(
      label: 'seed-${plan.seed}',
      ranges: plan.partitions,
      expectedToMatchFull: true,
    );
    final outcome = (await tester.runAsync(
      () => cache.exercise(
        plan: rangePlan,
        state: plan.kind == _PlanKind.cacheMemory
            ? ReaderCacheOrderState.warmMemory
            : ReaderCacheOrderState.reopenReload,
      ),
    ))!;
    _expectReviewedMembership(
      outcome.construction.state.canonicalCards,
      reason: outcome.diagnostics,
    );
    return _CacheRun(
      planJson: plan.canonicalJson,
      canonicalCardsJson: _cardsJson(outcome.construction.state.canonicalCards),
      evidenceJson: canonicalJsonEncode(outcome.construction.evidence.toJson()),
      diagnostics: outcome.diagnostics,
    );
  } finally {
    await tester.runAsync(sandbox.close);
  }
}

ProgressiveDisplayState _state(ReaderCorePaginationHarness harness) =>
    ProgressiveDisplayState(
      signature: DisplayGenerationSignature(
        bookId: harness.bookId,
        parsedContentVersion: 1,
        layoutSignature: harness.layoutIdentity,
        settingsSignature: 'p04-008-controlled',
        viewportSignature: harness.environment.inputs.diagnosticJson,
        cacheKey: harness.stateCacheKey,
      ),
      sourceChunkCount: harness.sourceChunks.length,
    );

CanonicalDisplayPublicationRequest _publicationRequest({
  required ReaderCorePaginationHarness harness,
  required CanonicalReaderPaginationSession session,
  required CanonicalPaginationOperationControls controls,
  required CanonicalReaderPaginationPathAccepted accepted,
  required CanonicalDisplayPublicationOperation operation,
  CanonicalPaginationContinuation? predecessor,
  CanonicalPaginationTargetContainmentEvidence? targetContainment,
  CanonicalDisplayPrependEvidence? prependEvidence,
  CanonicalFinalizedReaderCard? committedCard,
}) => CanonicalDisplayPublicationRequest(
  operation: operation,
  sessionIdentity: '${session.sourceSnapshot.snapshotDigest}|p04-008',
  generationIdentity: controls.generationToken,
  currentGenerationIdentity: () => controls.generationToken,
  sourceSnapshot: session.sourceSnapshot,
  controlledLayoutIdentity: harness.layoutIdentity,
  paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
  finalizedCards: accepted.publishableCards,
  continuation: accepted.continuation,
  predecessorContinuation: predecessor,
  targetContainment: targetContainment,
  prependEvidence: prependEvidence,
  committedCard: committedCard,
  isCancelled: () => false,
);

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

String _cardsJson(Iterable<CanonicalFinalizedReaderCard> cards) =>
    canonicalJsonEncode(<Object?>[
      for (final card in cards)
        <String, Object?>{
          'visibleText': card.card.text,
          'card': card.card.toJson(),
          'slices': card.sourceSlices
              .map((slice) => slice.toCanonicalJson())
              .toList(),
          'identity': card.identity.toJson(),
        },
    ]);

String _membershipJson(Iterable<CanonicalFinalizedReaderCard> cards) =>
    canonicalJsonEncode(<Object?>[
      for (final card in cards)
        <Object?>[
          for (final slice in card.sourceSlices)
            <Object?>[
              slice.sourceOrdinalHint,
              slice.startUtf16 ?? slice.tableRowStart,
              slice.endUtf16 ?? slice.tableRowEndExclusive,
            ],
        ],
    ]);

String _cardSummary(Iterable<CanonicalFinalizedReaderCard> cards) =>
    canonicalJsonEncode(<Object?>[
      for (final card in cards)
        <String, Object?>{
          'visibleText': card.card.text,
          'slices': card.sourceSlices
              .map((slice) => slice.toCanonicalJson())
              .toList(),
          'identitySignature': card.identity.signature,
        },
    ]);

void _expectReviewedMembership(
  Iterable<CanonicalFinalizedReaderCard> cards, {
  required String reason,
}) {
  expect(_membershipJson(cards), _reviewedMembershipJson(), reason: reason);
}

String _reviewedMembershipJson() => canonicalJsonEncode(<Object?>[
  for (final card in _reviewedStandardMembership)
    <Object?>[
      for (final range in card) <int>[range.$1, range.$2, range.$3],
    ],
]);

void _expectCompleteFixtureCoverage(
  List<CanonicalFinalizedReaderCard> cards,
  List<BookChunk> sources,
) {
  final slices = cards.expand((card) => card.sourceSlices).toList();
  for (var source = 0; source < sources.length; source++) {
    final owned = slices
        .where((slice) => slice.sourceOrdinalHint == source)
        .toList();
    expect(owned, isNotEmpty, reason: 'source=$source');
    if (owned.first.startUtf16 != null) {
      expect(owned.first.startUtf16, 0, reason: 'source=$source');
      expect(
        owned.last.endUtf16,
        sources[source].text!.length,
        reason: 'source=$source',
      );
      for (var index = 1; index < owned.length; index++) {
        expect(
          owned[index].startUtf16,
          owned[index - 1].endUtf16,
          reason: 'source=$source',
        );
      }
    }
  }
}

String _failureEvidence({
  required _Plan plan,
  required _GateRun expected,
  required _GateRun actual,
}) {
  final expectedCards = expected.cards;
  final actualCards = actual.cards;
  var divergence = -1;
  final common = math.min(expectedCards.length, actualCards.length);
  for (var index = 0; index < common; index++) {
    if (_cardsJson([expectedCards[index]]) !=
        _cardsJson([actualCards[index]])) {
      divergence = index;
      break;
    }
  }
  if (divergence < 0 && expectedCards.length != actualCards.length) {
    divergence = common;
  }
  return 'seed=${plan.seed}; plan=${plan.canonicalJson}; '
      'layout=$readerCoreStandardLayoutId; target=${plan.target}; '
      'checkpoint/restart=${plan.kind.name}; work=${actual.workJson}; '
      'expectedSlices=${_membershipJson(expectedCards)}; '
      'actualSlices=${_membershipJson(actualCards)}; '
      'expectedCanonical=${expected.canonicalCardsJson}; '
      'actualCanonical=${actual.canonicalCardsJson}; firstDivergence=$divergence; '
      'coverage=complete-source-0-through-19; retained=${actual.retainedJson}; '
      '${actual.diagnostics}';
}

String _stateJson(ProgressiveDisplayState state) =>
    canonicalJsonEncode(<String, Object?>{
      'ranges': state.ranges
          .map((range) => range.sourceRange.toString())
          .toList(),
      'cards': state.displayChunks.map((card) => card.toJson()).toList(),
      'displayToOriginal': state.displayToOriginal,
      'originalToDisplay': state.originalToDisplay,
      'canonical': _cardsJson(state.canonicalCards),
      'continuation': state.acceptedCanonicalContinuation?.canonicalEncoding,
      'cacheAuthority': state.hasCanonicalCacheWriteAuthority,
      'complete': state.generationComplete,
    });

Map<String, Object?> _diagnosticsJson(
  CanonicalPaginationWorkDiagnostics diagnostics,
) => <String, Object?>{
  'sourceChunksEntered': diagnostics.sourceChunksEntered,
  'sourceChunksFullyConsumed': diagnostics.sourceChunksFullyConsumed,
  'atomicFragmentsProcessed': diagnostics.atomicFragmentsProcessed,
  'cardsFinalized': diagnostics.cardsFinalized,
  'privatePredecessorCardsDiscarded':
      diagnostics.privatePredecessorCardsDiscarded,
  'frontierEntries': diagnostics.frontierEntries,
  'peakFrontierEntries': diagnostics.peakFrontierEntries,
  'cancellationCheckpoints': diagnostics.cancellationCheckpoints,
};
