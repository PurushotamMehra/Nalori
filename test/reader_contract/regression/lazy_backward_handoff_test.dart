import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/lazy_forward_handoff_core.dart';
import 'package:nalori/services/lazy_snapshot_handoff_service.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import '../pagination/reader_core_pagination_harness.dart';

import 'lazy_single_handoff_test.dart' show LazySingleHandoffTestRun;

List<String> bodies(LazySectionAuthority section) =>
    section.bodies.map((b) => b.canonicalEncoding).toList();

Future<void> forward(
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
  expect(core.publish(token, run.operation).accepted, isTrue);
  run.state.advanceLazyVisibleCard(
    run.state.lazyPublication!.current.cards.last.identity.signature,
    run.operation,
  );
  expect(core.retainSnapshotSuffix(run.operation).accepted, isTrue);
}

Future<LazyForwardTransfer> prepareBackward(
  LazySingleHandoffTestRun run,
  LazyForwardHandoffCore core,
  int section,
) async {
  final begun = core.beginPrevious(
    run.reloadSection == null
        ? run.sections[section]
        : await run.reloadSection!(section),
    run.operation,
  );
  expect(begun.transfer, isNotNull, reason: begun.result.message);
  final token = begun.transfer!;
  final prepared = await core.prepare(
    token,
    await run.layout(core.inputFor(token)),
    run.operation,
    committedLayout: await run.layout(run.state.lazyPublication!.current.input),
  );
  expect(
    prepared.outcome,
    LazySnapshotPublicationOutcome.prepared,
    reason: prepared.message,
  );
  return token;
}

Future<void> backward(
  LazySingleHandoffTestRun run,
  LazyForwardHandoffCore core,
  int section,
  List<String> expected,
) async {
  final before = run.state.lazyPublication!;
  final guards = before.cards.map(lazyCanonicalCardGuard).toList();
  final visible = run.state.lazyVisibleCardSignature!;
  final lease = core.leaseRenderer(visible);
  final block = lease.block();
  final token = await prepareBackward(run, core, section);
  expect(run.state.lazyPublication, same(before));
  final result = core.publish(
    token,
    run.operation,
    beforeCommit: () {
      expect(run.state.lazyPublication, same(before));
      expect(run.state.lazyVisibleCardSignature, visible);
      expect(lease.block(), same(block));
    },
  );
  expect(result.accepted, isTrue, reason: result.message);
  final accepted = run.state.lazyPublication!;
  expect(bodies(accepted.predecessor!), expected);
  expect(
    accepted.cards
        .skip(accepted.predecessor!.cards.length)
        .map(lazyCanonicalCardGuard),
    guards,
  );
  expect(accepted.current, same(before.current));
  expect(lease.block(), same(block));
  expect(run.state.lazyVisibleCardSignature, visible);
  expect(run.state.displayToOriginal.expand((s) => s).toList(), [0, 1, 2, 3]);
  run.state.advanceLazyVisibleCard(
    accepted.predecessor!.cards.last.identity.signature,
    run.operation,
  );
  // A tracked renderer still pins the old current section.
  expect(
    core.retainSnapshotPrefix(run.operation).outcome,
    LazySnapshotPublicationOutcome.retentionRequired,
  );
  lease.release();
  expect(core.retainSnapshotPrefix(run.operation).accepted, isTrue);
  expect(bodies(run.state.lazyPublication!.current), expected);
  expect(core.liveState.sessions, 0);
  expect(core.liveState.snapshotViews, 1);
  expect(core.liveState.preparationReferences, 0);
  expect(core.liveState.rendererLeases, 0);
}

void main() {
  testWidgets(
    'B01 C to B to A reconstructs exact retired cards then moves forward again',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      final a = bodies(run.a);
      await forward(run, core, 1);
      final b = bodies(run.state.lazyPublication!.current);
      final oldRuntimeSlices = canonicalJsonEncode(
        run.state.lazyPublication!.cards
            .map((c) => c.sourceSlices.map((s) => s.toCanonicalJson()).toList())
            .toList(),
      );
      await forward(run, core, 2);
      final c = bodies(run.state.lazyPublication!.current);
      expect(core.liveState.sessions, 0);
      await backward(run, core, 1, b);
      final newRuntimeSlices = canonicalJsonEncode(
        run.state.lazyPublication!.cards
            .map((c) => c.sourceSlices.map((s) => s.toCanonicalJson()).toList())
            .toList(),
      );
      expect(newRuntimeSlices, isNot(oldRuntimeSlices));
      await backward(run, core, 0, a);
      await forward(run, core, 1);
      expect(bodies(run.state.lazyPublication!.current), b);
      await forward(run, core, 2);
      expect(bodies(run.state.lazyPublication!.current), c);
      expect(run.state.generationComplete, isTrue);
      // ignore: avoid_print
      print(
        'BACKWARD_ROUNDTRIP peak=${core.peak} retired=${core.liveState.toJson()}',
      );
    },
  );

  testWidgets('B02 repeated direction changes retire all obsolete core roots', (
    tester,
  ) async {
    final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
    final core = LazyForwardHandoffCore(run.state);
    final a = bodies(run.a);
    await forward(run, core, 1);
    final b = bodies(run.state.lazyPublication!.current);
    await forward(run, core, 2);
    for (var cycle = 0; cycle < 6; cycle++) {
      await backward(run, core, 1, b);
      await backward(run, core, 0, a);
      await forward(run, core, 1);
      await forward(run, core, 2);
      expect(core.liveState.sessions, 0);
      expect(core.liveState.snapshotViews, 1);
      expect(core.liveState.rendererAuthorities, 1);
      expect(core.liveState.sections, 1);
      expect(core.liveState.backingRecords, 2);
      expect(core.liveState.guards, lessThanOrEqualTo(5));
      expect(core.liveState.pendingTransfers, 0);
      expect(core.liveState.resolverReferences, 0);
    }
    expect(core.peak['cards'], lessThanOrEqualTo(96));
    expect(core.peak['guards'], lessThanOrEqualTo(25));
    expect(core.peak['sources'], lessThanOrEqualTo(432));
    expect(core.peak['reconstructionWork'], lessThanOrEqualTo(110));
    // ignore: avoid_print
    print(
      'BACKWARD_OSCILLATION peak=${core.peak} retired=${core.liveState.toJson()}',
    );
  });

  for (final mode in [
    'cancelled',
    'stale',
    'invalid',
    'commit cancellation',
    'visible race',
    'core cancellation',
  ]) {
    testWidgets(
      'B03 $mode backward work rejects atomically and releases preparation',
      (tester) async {
        final run = await LazySingleHandoffTestRun.open(
          tester,
          sectionCount: 3,
        );
        final core = LazyForwardHandoffCore(run.state);
        await forward(run, core, 1);
        await forward(run, core, 2);
        final before = run.state.lazyPublication!;
        final live = core.liveState.toJson();
        final token = await prepareBackward(run, core, 1);
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
          beforeCommit: () {
            if (mode == 'commit cancellation') run.cancelled = true;
            if (mode == 'core cancellation') core.cancelPending();
            if (mode == 'visible race') {
              run.state.advanceLazyVisibleCard(
                before.cards.first.identity.signature,
                run.operation,
              );
            }
          },
        );
        expect(result.accepted, isFalse);
        expect(run.state.lazyPublication, same(before));
        expect(core.liveState.toJson(), live);
        expect(
          core.publish(token, run.operation).outcome,
          LazySnapshotPublicationOutcome.replayed,
        );
      },
    );
  }

  testWidgets(
    'B04 invalid restart skips no section and stale font evidence has no semantic fallback',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await forward(run, core, 1);
      await forward(run, core, 2);
      final before = run.state.lazyPublication!;
      final live = core.liveState.toJson();
      expect(
        core.beginPrevious(run.sections[0], run.operation).result.outcome,
        LazySnapshotPublicationOutcome.exactUnavailable,
      );
      expect(core.liveState.toJson(), live);
      final token = core
          .beginPrevious(run.sections[1], run.operation)
          .transfer!;
      run.invalidFontEvidence = true;
      final result = await core.prepare(
        token,
        await run.layout(core.inputFor(token)),
        run.operation,
        committedLayout: await run.layout(before.current.input),
      );
      expect(result.outcome, LazySnapshotPublicationOutcome.exactUnavailable);
      expect(run.state.lazyPublication, same(before));
      expect(core.liveState.toJson(), live);
    },
  );

  testWidgets(
    'B05 active reconstruction cancellation stays counted until settlement',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await forward(run, core, 1);
      await forward(run, core, 2);
      final before = run.state.lazyPublication!;
      final live = core.liveState.toJson();
      final token = core
          .beginPrevious(run.sections[1], run.operation)
          .transfer!;
      var cancelled = false;
      final controls = run.operation.pagination;
      final operation = LazyHandoffOperation(
        owner: run.owner,
        currentOwner: () => run.currentOwner,
        pagination: CanonicalPaginationOperationControls(
          generationToken: controls.generationToken,
          scheduler: controls.scheduler,
          priority: controls.priority,
          isCancelled: () {
            if (!cancelled && core.liveState.sessions == 2) {
              cancelled = true;
              core.cancelPending();
              expect(core.liveState.pendingTransfers, 1);
            }
            return false;
          },
        ),
      );
      final result = await core.prepare(
        token,
        await run.layout(core.inputFor(token)),
        operation,
        committedLayout: await run.layout(before.current.input),
      );
      expect(cancelled, isTrue);
      expect(result.outcome, LazySnapshotPublicationOutcome.cancelled);
      expect(run.state.lazyPublication, same(before));
      expect(core.liveState.toJson(), live);
    },
  );

  testWidgets(
    'B06 retired predecessor is reloaded through the real repository without later chapters',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(
        tester,
        sectionCount: 3,
        fixtureSectionCount: 8,
        keepSourceForReload: true,
      );
      final core = LazyForwardHandoffCore(run.state);
      final a = bodies(run.a);
      await forward(run, core, 1);
      final b = bodies(run.state.lazyPublication!.current);
      await forward(run, core, 2);
      await backward(run, core, 1, b);
      await backward(run, core, 0, a);
      expect(run.reloadRequests, [1, 0]);
      expect(run.sections.length, 3);
      expect(run.originalIndex.spine.length, 8);
      expect(run.state.generationComplete, isFalse);
    },
  );

  testWidgets(
    'B07 reconstruction shares the aggregate card budget and latches failure',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final forwardCore = LazyForwardHandoffCore(run.state);
      await forward(run, forwardCore, 1);
      await forward(run, forwardCore, 2);
      final core = LazyForwardHandoffCore(
        run.state,
        limits: const LazyForwardRetentionLimits(cards: 4),
      );
      final before = run.state.lazyPublication!;
      final live = core.liveState.toJson();
      final token = core
          .beginPrevious(run.sections[1], run.operation)
          .transfer!;
      final result = await core.prepare(
        token,
        await run.layout(core.inputFor(token)),
        run.operation,
        committedLayout: await run.layout(before.current.input),
      );
      expect(result.outcome, LazySnapshotPublicationOutcome.boundExceeded);
      expect(run.state.lazyPublication, same(before));
      expect(core.liveState.toJson(), live);
      expect(core.peak['cards'], lessThanOrEqualTo(4));
      expect(
        core.beginPrevious(run.sections[1], run.operation).result.outcome,
        LazySnapshotPublicationOutcome.failedAttempt,
      );
    },
  );

  testWidgets(
    'B08 exact unavailable requires a new explicit attempt and never substitutes semantic evidence',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await forward(run, core, 1);
      await forward(run, core, 2);
      final before = run.state.lazyPublication!;
      final token = core
          .beginPrevious(run.sections[1], run.operation)
          .transfer!;
      final wrong = await run.layout(core.inputFor(token));
      final rejected = await core.prepare(
        token,
        wrong,
        run.operation,
        committedLayout: wrong,
      );
      expect(rejected.outcome, LazySnapshotPublicationOutcome.exactUnavailable);
      expect(core.liveState.pendingTransfers, 0);
      expect(
        core.beginPrevious(run.sections[1], run.operation).result.outcome,
        LazySnapshotPublicationOutcome.failedAttempt,
      );
      expect(run.state.lazyPublication, same(before));
      final controls = run.operation.pagination;
      run.currentOwner = (bookOpenEpoch: 1, displayOwner: 1, attempt: 1);
      final retry = LazyHandoffOperation(
        owner: run.currentOwner,
        currentOwner: () => run.currentOwner,
        pagination: controls,
      );
      final fresh = core.beginPrevious(run.sections[1], retry).transfer!;
      expect(
        core.beginPrevious(run.sections[1], retry).result.outcome,
        LazySnapshotPublicationOutcome.busy,
      );
      final ready = await core.prepare(
        fresh,
        await run.layout(core.inputFor(fresh)),
        retry,
        committedLayout: await run.layout(before.current.input),
      );
      expect(
        ready.outcome,
        LazySnapshotPublicationOutcome.prepared,
        reason: ready.message,
      );
      expect(core.publish(fresh, retry).accepted, isTrue);
      expect(core.liveState.pendingTransfers, 0);
    },
  );

  testWidgets(
    'B09 rich section reconstruction reproduces stable list table and heading bodies',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => ReaderCoreParsedFixture.load('backward-rich-'),
      ))!;
      try {
        final run = await LazySingleHandoffTestRun.open(
          tester,
          fixture: fixture.epubFile,
        );
        final core = LazyForwardHandoffCore(run.state);
        final a = bodies(run.a);
        await forward(run, core, 1);
        final before = run.state.lazyPublication!;
        final token = await prepareBackward(run, core, 0);
        final result = core.publish(token, run.operation);
        expect(result.accepted, isTrue, reason: result.message);
        expect(bodies(run.state.lazyPublication!.predecessor!), a);
        expect(run.state.lazyPublication!.current, same(before.current));
        run.state.advanceLazyVisibleCard(
          run.state.lazyPublication!.predecessor!.cards.last.identity.signature,
          run.operation,
        );
        expect(core.retainSnapshotPrefix(run.operation).accepted, isTrue);
        await forward(run, core, 1);
        expect(
          bodies(run.state.lazyPublication!.current),
          bodies(before.current),
        );
        expect(core.peak['reconstructionWork'], lessThanOrEqualTo(110));
        // ignore: avoid_print
        print('BACKWARD_RICH peak=${core.peak}');
      } finally {
        await tester.runAsync(fixture.close);
      }
    },
  );

  testWidgets(
    'B10 cancelled commit cannot clear a new pending reconstruction',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester, sectionCount: 3);
      final core = LazyForwardHandoffCore(run.state);
      await forward(run, core, 1);
      await forward(run, core, 2);
      final before = run.state.lazyPublication!;
      final token = await prepareBackward(run, core, 1);
      LazyForwardTransfer? next;
      final rejected = core.publish(
        token,
        run.operation,
        beforeCommit: () {
          core.cancelPending();
          next = core.beginPrevious(run.sections[1], run.operation).transfer;
          expect(next, isNotNull);
        },
      );
      expect(rejected.outcome, LazySnapshotPublicationOutcome.cancelled);
      expect(run.state.lazyPublication, same(before));
      expect(core.liveState.pendingTransfers, 1);
      expect(
        core.inputFor(next!).sectionAuthorities.single.sectionKey,
        run.sections[1].identity.stableKey,
      );
      core.cancelPending();
      expect(core.liveState.pendingTransfers, 0);
    },
  );
}
