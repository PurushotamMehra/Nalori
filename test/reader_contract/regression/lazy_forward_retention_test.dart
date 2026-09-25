import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/lazy_forward_handoff_core.dart';
import 'package:nalori/services/lazy_snapshot_handoff_service.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import 'lazy_single_handoff_test.dart' show LazySingleHandoffTestRun;

void main() {
  Future<void> advance(
    LazySingleHandoffTestRun run,
    LazyForwardHandoffCore core,
    int section,
  ) async {
    final begun = core.beginNext(run.sections[section], run.operation);
    expect(begun.transfer, isNotNull, reason: begun.result.message);
    final token = begun.transfer!;
    final prepared = await core.prepare(
      token,
      await run.layout(core.inputFor(token)),
      run.operation,
    );
    expect(
      prepared.outcome,
      LazySnapshotPublicationOutcome.prepared,
      reason: prepared.message,
    );
    final published = core.publish(token, run.operation);
    expect(published.accepted, isTrue, reason: published.message);
  }

  void retire(LazySingleHandoffTestRun run, LazyForwardHandoffCore core) {
    expect(
      run.state.advanceLazyVisibleCard(
        run.state.lazyPublication!.current.cards.first.identity.signature,
        run.operation,
      ),
      isTrue,
    );
    final retired = core.retainSnapshotSuffix(run.operation);
    expect(retired.accepted, isTrue, reason: retired.message);
  }

  testWidgets(
    'F01 A to B to C retires old authorities while retaining visible B bytes and renderer',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await advance(run, core, 1);
      final b = run.state.lazyPublication!.current;
      final guards = b.cardGuards;
      final bodies = b.bodies.map((b) => b.canonicalEncoding).toList();
      final bRecords = b.input.sourceRecords.sublist(b.input.lastSectionStart);
      final lease = core.leaseRenderer(b.cards.first.identity.signature);
      final block = lease.block();
      expect(core.liveState.sessions, 2);
      retire(run, core);
      expect(core.liveState.sessions, 0);
      expect(core.liveState.snapshotViews, 1);
      expect(core.liveState.rendererAuthorities, 1);
      expect(core.liveState.preparationReferences, 0);
      expect(core.liveState.sections, 1);
      expect(run.state.lazyPublication!.predecessor, isNull);
      expect(run.state.lazyPublication!.current.session, isNull);
      expect(run.state.lazyPublication!.current.cardGuards, guards);
      expect(
        run.state.lazyPublication!.bodies
            .map((b) => b.canonicalEncoding)
            .toList(),
        bodies,
      );
      expect(run.state.displayToOriginal.expand((s) => s).toSet(), {0, 1});
      for (var i = 0; i < bRecords.length; i++) {
        expect(
          identical(
            run.state.lazyPublication!.current.input.sourceRecords[i],
            bRecords[i],
          ),
          isTrue,
        );
      }
      expect(lease.block(), same(block));
      final before = run.state.lazyPublication!.current;
      await advance(run, core, 2);
      expect(run.state.lazyPublication!.handoffOrdinal, 2);
      expect(run.state.lazyPublication!.predecessor, same(before));
      expect(
        run.state.lazyPublication!.cards
            .take(guards.length)
            .map(lazyCanonicalCardGuard)
            .toList(),
        guards,
      );
      expect(lease.block(), same(block));
      expect(run.state.generationComplete, isTrue);
      expect(core.liveState.pendingTransfers, 0);
      lease.release();
      retire(run, core);
      expect(core.liveState.sessions, 0);
      expect(core.liveState.sections, 1);
      // ignore: avoid_print
      print('FORWARD_TWO peak=${core.peak} retired=${core.liveState.toJson()}');
    },
  );

  testWidgets('F02 visible card and renderer lease independently pin A', (
    tester,
  ) async {
    final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
    final core = LazyForwardHandoffCore(run.state);
    final aLease = core.leaseRenderer(run.a.cards.first.identity.signature);
    await advance(run, core, 1);
    final accepted = run.state.lazyPublication!;
    final digest = accepted.digest;
    expect(
      core.retainSnapshotSuffix(run.operation).outcome,
      LazySnapshotPublicationOutcome.retentionRequired,
    );
    expect(
      core.beginNext(run.sections[2], run.operation).result.outcome,
      LazySnapshotPublicationOutcome.retentionRequired,
    );
    expect(core.liveState.pendingTransfers, 0);
    run.state.advanceLazyVisibleCard(
      accepted.current.cards.first.identity.signature,
      run.operation,
    );
    expect(
      core.retainSnapshotSuffix(run.operation).outcome,
      LazySnapshotPublicationOutcome.retentionRequired,
    );
    expect(run.state.lazyPublication!.digest, digest);
    expect(aLease.block(), isNotNull);
    aLease.release();
    expect(core.retainSnapshotSuffix(run.operation).accepted, isTrue);
    expect(core.liveState.rendererLeases, 0);
    expect(core.liveState.sections, 1);
    expect(() => aLease.block(), throwsStateError);
  });

  testWidgets(
    'F03 pending input is counted, serialized, and released on cancellation',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await advance(run, core, 1);
      retire(run, core);
      final baseline = core.liveState.toJson();
      final token = core.beginNext(run.sections[2], run.operation).transfer!;
      expect(core.liveState.pendingTransfers, 1);
      expect(core.liveState.backingRecords, 4);
      expect(core.liveState.snapshotViews, 2);
      expect(core.liveState.sources, 6);
      expect(core.liveState.accountedBytes, greaterThan(baseline['bytes']!));
      expect(
        core.beginNext(run.sections[2], run.operation).result.outcome,
        LazySnapshotPublicationOutcome.busy,
      );
      core.cancelPending();
      expect(core.liveState.toJson(), baseline);
      expect(() => core.inputFor(token), throwsStateError);
    },
  );

  for (final mode in ['cancelled', 'stale', 'invalid']) {
    testWidgets(
      'F04 $mode second transfer releases preparation and preserves accepted B',
      (tester) async {
        final run = await LazySingleHandoffTestRun.open(
          tester,
          sectionCount: 3,
        );
        final core = LazyForwardHandoffCore(run.state);
        await advance(run, core, 1);
        retire(run, core);
        final accepted = run.state.lazyPublication!;
        final baseline = core.liveState.toJson();
        final token = core.beginNext(run.sections[2], run.operation).transfer!;
        final prepared = await core.prepare(
          token,
          await run.layout(core.inputFor(token)),
          run.operation,
        );
        expect(
          prepared.outcome,
          LazySnapshotPublicationOutcome.prepared,
          reason: prepared.message,
        );
        expect(core.liveState.sessions, 1);
        if (mode == 'cancelled') run.cancelled = true;
        if (mode == 'stale') {
          run.currentOwner = (bookOpenEpoch: 2, displayOwner: 1, attempt: 0);
        }
        final result = core.publish(
          token,
          run.operation,
          proposal: mode == 'invalid'
              ? LazySnapshotHandoffV1({'kind': 'invalid'})
              : null,
        );
        expect(result.accepted, isFalse);
        expect(run.state.lazyPublication, same(accepted));
        expect(core.liveState.toJson(), baseline);
        expect(
          core.publish(token, run.operation).outcome,
          LazySnapshotPublicationOutcome.replayed,
        );
      },
    );
  }

  testWidgets(
    'F05 active production pagination cancellation stays counted until settlement',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await advance(run, core, 1);
      retire(run, core);
      final baseline = core.liveState.toJson();
      final token = core.beginNext(run.sections[2], run.operation).transfer!;
      final controls = run.operation.pagination;
      var sawActive = false;
      final operation = LazyHandoffOperation(
        owner: run.owner,
        currentOwner: () => run.currentOwner,
        pagination: CanonicalPaginationOperationControls(
          generationToken: controls.generationToken,
          scheduler: controls.scheduler,
          priority: controls.priority,
          isCancelled: () {
            if (core.liveState.sessions > 0 &&
                core.liveState.frontierCardReservation == 2) {
              sawActive = true;
            }
            return sawActive;
          },
        ),
      );
      final outcome = await core.prepare(
        token,
        await run.layout(core.inputFor(token)),
        operation,
      );
      expect(sawActive, isTrue);
      expect(outcome.outcome, LazySnapshotPublicationOutcome.cancelled);
      expect(core.liveState.toJson(), baseline);
    },
  );

  testWidgets(
    'F06 source and pending card budgets reject without evicting visible authority',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final digest = run.state.lazyPublication!.digest;
      final sources = LazyForwardHandoffCore(
        run.state,
        limits: const LazyForwardRetentionLimits(sources: 3),
      );
      expect(
        sources.beginNext(run.sections[1], run.operation).result.outcome,
        LazySnapshotPublicationOutcome.boundExceeded,
      );
      expect(sources.liveState.pendingTransfers, 0);
      final cards = LazyForwardHandoffCore(
        run.state,
        limits: const LazyForwardRetentionLimits(cards: 2),
      );
      final token = cards.beginNext(run.sections[1], run.operation).transfer!;
      final result = await cards.prepare(
        token,
        await run.layout(cards.inputFor(token)),
        run.operation,
      );
      expect(result.accepted, isFalse);
      expect(cards.liveState.pendingTransfers, 0);
      expect(run.state.lazyPublication!.digest, digest);
      expect(
        run.state.lazyVisibleCardSignature,
        run.a.cards.first.identity.signature,
      );
    },
  );

  testWidgets(
    'F07 eighteen small sections do not accumulate snapshots, sessions or renderer roots',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 18);
      final core = LazyForwardHandoffCore(run.state);
      for (var section = 1; section < 18; section++) {
        await advance(run, core, section);
        expect(run.state.lazyPublication!.handoffOrdinal, section);
        expect(run.state.generationComplete, section == 17);
        retire(run, core);
        final live = core.liveState;
        expect(live.backingRecords, 2);
        expect(live.snapshotViews, 1);
        expect(live.sessions, 0);
        expect(live.rendererAuthorities, 1);
        expect(live.preparationReferences, 0);
        expect(live.resolverReferences, 0);
        expect(live.pendingTransfers, 0);
        expect(live.sections, 1);
        expect(live.guards, lessThanOrEqualTo(5));
        expect(live.accountedBytes, lessThanOrEqualTo(6 * 1024 * 1024));
        expect(live.metadataBytes, lessThanOrEqualTo(64 * 1024));
      }
      expect(core.peak['backingRecords'], 4);
      expect(core.peak['sessions'], 2);
      expect(core.peak['snapshots'], 3);
      expect(core.peak['renderers'], 2);
      expect(core.peak['pending'], 1);
      expect(core.peak['sources'], lessThanOrEqualTo(11));
      // ignore: avoid_print
      print('FORWARD_18 peak=${core.peak} retired=${core.liveState.toJson()}');
    },
  );

  testWidgets('F08 cancellation at second commit releases all private roots', (
    tester,
  ) async {
    final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
    final core = LazyForwardHandoffCore(run.state);
    await advance(run, core, 1);
    retire(run, core);
    final old = run.state.lazyPublication!;
    final baseline = core.liveState.toJson();
    final token = core.beginNext(run.sections[2], run.operation).transfer!;
    expect(
      (await core.prepare(
        token,
        await run.layout(core.inputFor(token)),
        run.operation,
      )).outcome,
      LazySnapshotPublicationOutcome.prepared,
    );
    final rejected = core.publish(
      token,
      run.operation,
      beforeCommit: () {
        run.cancelled = true;
      },
    );
    expect(rejected.outcome, LazySnapshotPublicationOutcome.cancelled);
    expect(run.state.lazyPublication, same(old));
    expect(core.liveState.toJson(), baseline);
  });

  testWidgets(
    'F09 replayed second token cannot clear a later pending third transfer',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 4);
      final core = LazyForwardHandoffCore(run.state);
      await advance(run, core, 1);
      retire(run, core);
      final second = core.beginNext(run.sections[2], run.operation).transfer!;
      expect(
        (await core.prepare(
          second,
          await run.layout(core.inputFor(second)),
          run.operation,
        )).outcome,
        LazySnapshotPublicationOutcome.prepared,
      );
      expect(core.publish(second, run.operation).accepted, isTrue);
      retire(run, core);
      final third = core.beginNext(run.sections[3], run.operation).transfer!;
      final live = core.liveState.toJson();
      expect(
        core.publish(second, run.operation).outcome,
        LazySnapshotPublicationOutcome.replayed,
      );
      expect(core.liveState.toJson(), live);
      expect(core.inputFor(third).nextCandidate, isNull);
      core.cancelPending();
    },
  );

  testWidgets(
    'F10 byte and metadata reservations reject without keeping candidate references',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final original = run.state.lazyPublication!;
      final observer = LazyForwardHandoffCore(run.state);
      final bytes = LazyForwardHandoffCore(
        run.state,
        limits: LazyForwardRetentionLimits(
          bytes: observer.liveState.accountedBytes + 1,
        ),
      );
      expect(
        bytes.beginNext(run.sections[1], run.operation).result.outcome,
        LazySnapshotPublicationOutcome.boundExceeded,
      );
      expect(bytes.liveState.pendingTransfers, 0);
      final meta = LazyForwardHandoffCore(
        run.state,
        limits: LazyForwardRetentionLimits(
          metadataBytes: observer.liveState.metadataBytes + 1,
        ),
      );
      final token = meta.beginNext(run.sections[1], run.operation).transfer!;
      final outcome = await meta.prepare(
        token,
        await run.layout(meta.inputFor(token)),
        run.operation,
      );
      expect(outcome.outcome, LazySnapshotPublicationOutcome.boundExceeded);
      expect(meta.liveState.pendingTransfers, 0);
      expect(run.state.lazyPublication, same(original));
    },
  );

  testWidgets(
    'F11 visible B body card is preserved and bound in the second handoff',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await advance(run, core, 1);
      final bodyCard = run.state.lazyPublication!.current.cards.last;
      final guard = lazyCanonicalCardGuard(bodyCard);
      expect(
        run.state.advanceLazyVisibleCard(
          bodyCard.identity.signature,
          run.operation,
        ),
        isTrue,
      );
      expect(core.retainSnapshotSuffix(run.operation).accepted, isTrue);
      await advance(run, core, 2);
      expect(run.state.lazyVisibleCardSignature, bodyCard.identity.signature);
      expect(
        run.state.lazyPublication!.handoff!.fields['committedCardSignature'],
        bodyCard.identity.signature,
      );
      expect(
        run.state.canonicalCards.any(
          (c) => identical(c, bodyCard) && lazyCanonicalCardGuard(c) == guard,
        ),
        isTrue,
      );
    },
  );

  for (final mode in ['visible race', 'oversized proposal']) {
    testWidgets(
      'F12 $mode rejects the second transfer and releases its roots',
      (tester) async {
        final run = await LazySingleHandoffTestRun.open(
          tester,
          sectionCount: 3,
        );
        final core = LazyForwardHandoffCore(run.state);
        await advance(run, core, 1);
        retire(run, core);
        final accepted = run.state.lazyPublication!;
        final baseline = core.liveState.toJson();
        final token = core.beginNext(run.sections[2], run.operation).transfer!;
        expect(
          (await core.prepare(
            token,
            await run.layout(core.inputFor(token)),
            run.operation,
          )).outcome,
          LazySnapshotPublicationOutcome.prepared,
        );
        final result = core.publish(
          token,
          run.operation,
          proposal: mode == 'oversized proposal'
              ? LazySnapshotHandoffV1({'padding': 'x' * (64 * 1024)})
              : null,
          beforeCommit: mode == 'visible race'
              ? () {
                  expect(
                    run.state.advanceLazyVisibleCard(
                      accepted.cards.last.identity.signature,
                      run.operation,
                    ),
                    isTrue,
                  );
                }
              : null,
        );
        expect(
          result.outcome,
          mode == 'visible race'
              ? LazySnapshotPublicationOutcome.stale
              : LazySnapshotPublicationOutcome.boundExceeded,
        );
        expect(run.state.lazyPublication, same(accepted));
        expect(core.liveState.toJson(), baseline);
      },
    );
  }

  testWidgets(
    'F13 cancelling active core pagination retains accounting until settlement',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await advance(run, core, 1);
      retire(run, core);
      final baseline = core.liveState.toJson();
      final token = core.beginNext(run.sections[2], run.operation).transfer!;
      final controls = run.operation.pagination;
      var cancelled = false;
      final operation = LazyHandoffOperation(
        owner: run.owner,
        currentOwner: () => run.currentOwner,
        pagination: CanonicalPaginationOperationControls(
          generationToken: controls.generationToken,
          scheduler: controls.scheduler,
          priority: controls.priority,
          isCancelled: () {
            if (!cancelled &&
                core.liveState.sessions > 0 &&
                core.liveState.frontierCardReservation == 2) {
              cancelled = true;
              core.cancelPending();
              expect(core.liveState.pendingTransfers, 1);
              expect(core.liveState.sessions, 1);
            }
            return false;
          },
        ),
      );
      final result = await core.prepare(
        token,
        await run.layout(core.inputFor(token)),
        operation,
      );
      expect(cancelled, isTrue);
      expect(result.outcome, LazySnapshotPublicationOutcome.cancelled);
      expect(core.liveState.toJson(), baseline);
    },
  );
}
