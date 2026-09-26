import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/lazy_forward_handoff_core.dart';
import 'package:nalori/services/lazy_snapshot_handoff_service.dart';
import 'package:nalori/services/lazy_validation_work.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import '../pagination/reader_core_pagination_harness.dart';
import 'lazy_single_handoff_test.dart' show LazySingleHandoffTestRun;

class YieldProbe {
  int ticks = 0;
  int yields = 0;
  Future<void> Function()? onYield;
  late final scheduler = FrameBudgetedRangeScheduler(
    clock: () => Duration(microseconds: ticks++),
    // Pin this quota explicitly: the test asserts its exact yield relationship.
    // ignore: avoid_redundant_argument_values
    sourceChunksPerSliceBudget: 4,
    yieldToFrame: () async {
      yields++;
      await onYield?.call();
    },
  );
  LazyHandoffOperation operation(LazySingleHandoffTestRun run) =>
      LazyHandoffOperation(
        owner: run.owner,
        currentOwner: () => run.currentOwner,
        pagination: CanonicalPaginationOperationControls(
          generationToken: 1,
          scheduler: scheduler,
          priority: DisplayRangeTaskPriority.directTarget,
          isCancelled: () => run.cancelled,
        ),
      );
}

Future<LazyForwardTransfer> prepare(
  LazySingleHandoffTestRun run,
  LazyForwardHandoffCore core,
  LazyHandoffOperation operation,
  int section, {
  bool backward = false,
}) async {
  final begun = backward
      ? await core.beginPreviousYielding(run.sections[section], operation)
      : await core.beginNextYielding(run.sections[section], operation);
  expect(begun.transfer, isNotNull, reason: begun.result.message);
  final token = begun.transfer!;
  final result = await core.prepare(
    token,
    await run.layout(core.inputFor(token)),
    operation,
    committedLayout: backward
        ? await run.layout(run.state.lazyPublication!.current.input)
        : null,
  );
  expect(
    result.outcome,
    LazySnapshotPublicationOutcome.prepared,
    reason: result.message,
  );
  return token;
}

void main() {
  test(
    'Y01 sliced codec preserves canonical bytes including fragment boundaries',
    () async {
      final probe = YieldProbe();
      final work = LazyValidationWork(
        task: probe.scheduler.startTask(
          id: 1,
          priority: DisplayRangeTaskPriority.directTarget,
          isExternallyCancelled: () => false,
        ),
        isCurrent: () => true,
      );
      final long = '${'x' * 1023}😀\n\\"${'é' * 256000}';
      final value = {
        'z': [long, null, true, 42],
        'a': 'first',
      };
      expect(await work.encode(value), canonicalJsonEncode(value));
      expect(await work.digest(value), readerSha256(value));
      expect(await work.digest(long), readerSha256(long));
      final bytes = Uint8List.fromList(List.generate(70000, (i) => i % 256));
      expect(await work.digest(bytes), readerSha256(bytes));
      expect(
        await work.equal(long, String.fromCharCodes(long.codeUnits)),
        isTrue,
      );
      expect(await work.equalCanonical(value, value), isTrue);
      expect(await work.equalCanonical(value, {'a': 'different'}), isFalse);
      expect(await work.equal(long, '${long.substring(1)}!'), isFalse);
      expect(probe.yields, work.units ~/ 4);
      expect(work.units, greaterThan(100));
      work.finish();
      expect(work.accountedBytes, 0);
      expect(
        probe.scheduler.completedMetrics.single.maxSourceChunksPerSlice,
        4,
      );
    },
  );

  testWidgets(
    'Y02 capture yields incomplete; cancelled work stays counted until settlement',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester);
      final core = LazyForwardHandoffCore(run.state);
      final before = run.state.lazyPublication;
      final probe = YieldProbe();
      final reached = Completer<void>(), release = Completer<void>();
      probe.onYield = () async {
        if (!reached.isCompleted && core.validationPhase == 'encoding') {
          reached.complete();
          await release.future;
        }
      };
      var complete = false;
      final future = core
          .beginNextYielding(run.sections[1], probe.operation(run))
          .then((value) {
            complete = true;
            return value;
          });
      await reached.future;
      expect(complete, isFalse);
      expect(core.validationTemporaryBytes, greaterThan(0));
      expect(core.liveState.pendingTransfers, 1);
      core.cancelPending();
      expect(core.liveState.pendingTransfers, 1);
      expect(run.state.lazyPublication, same(before));
      release.complete();
      expect((await future).transfer, isNull);
      expect(core.liveState.pendingTransfers, 0);
      expect(core.validationTemporaryBytes, 0);
      expect(run.state.lazyPublication, same(before));
    },
  );

  for (final race in ['owner', 'visible', 'cancel']) {
    testWidgets(
      'Y03 $race changes during projection reject atomic publication',
      (tester) async {
        final run = await LazySingleHandoffTestRun.open(tester);
        final core = LazyForwardHandoffCore(run.state);
        final probe = YieldProbe();
        final op = probe.operation(run);
        final token = await prepare(run, core, op, 1);
        final before = run.state.lazyPublication!;
        final guards = before.cards.map(lazyCanonicalCardGuard).toList();
        var interrupted = false;
        probe.onYield = () async {
          if (interrupted || core.validationPhase != 'projection-slice') return;
          interrupted = true;
          expect(run.state.lazyPublication, same(before));
          if (race == 'owner') {
            run.currentOwner = (bookOpenEpoch: 2, displayOwner: 1, attempt: 0);
          } else if (race == 'visible') {
            final next = before.cards.firstWhere(
              (c) => c.identity.signature != run.state.lazyVisibleCardSignature,
            );
            run.state.advanceLazyVisibleCard(next.identity.signature, op);
          } else {
            core.cancelPending();
            expect(core.liveState.pendingTransfers, 1);
          }
        };
        final result = await core.publishYielding(token, op);
        expect(interrupted, isTrue);
        expect(result.accepted, isFalse, reason: result.message);
        expect(run.state.lazyPublication, same(before));
        expect(before.cards.map(lazyCanonicalCardGuard), guards);
        expect(core.liveState.pendingTransfers, 0);
        expect(core.validationTemporaryBytes, 0);
      },
    );
  }

  for (final rich in [false, true]) {
    testWidgets('Y04 forward/backward bytes and yielding retirement rich=$rich', (
      tester,
    ) async {
      final fixture = rich
          ? await tester.runAsync(
              () => ReaderCoreParsedFixture.load('yield-rich-'),
            )
          : null;
      if (fixture != null) addTearDown(() => tester.runAsync(fixture.close));
      final run = await LazySingleHandoffTestRun.open(
        tester,
        fixture: fixture?.epubFile,
      );
      final core = LazyForwardHandoffCore(run.state);
      final probe = YieldProbe();
      final phases = <String>{};
      probe.onYield = () async {
        if (core.validationPhase != null) phases.add(core.validationPhase!);
      };
      final op = probe.operation(run);
      final original = run.a.bodies.map((b) => b.canonicalEncoding).toList();
      final legacyB = await run.prepareB(tester);
      final b = await prepare(run, core, op, 1);
      final result = await core.publishYielding(b, op);
      expect(result.accepted, isTrue, reason: result.message);
      expect(
        run.state.lazyPublication!.current.bodies.map(
          (b) => b.canonicalEncoding,
        ),
        legacyB.bodies.map((b) => b.canonicalEncoding),
      );
      run.state.advanceLazyVisibleCard(
        run.state.lazyPublication!.current.cards.last.identity.signature,
        op,
      );
      expect((await core.retainYielding(op)).accepted, isTrue);
      final a = await prepare(run, core, op, 0, backward: true);
      final back = await core.publishYielding(a, op);
      expect(back.accepted, isTrue, reason: back.message);
      expect(
        run.state.lazyPublication!.predecessor!.bodies.map(
          (b) => b.canonicalEncoding,
        ),
        original,
      );
      final signature =
          run.state.lazyPublication!.predecessor!.cards.last.identity.signature;
      run.state.advanceLazyVisibleCard(signature, op);
      final lease = core.leaseRenderer(signature);
      final block = lease.block();
      expect(
        (await core.retainYielding(op, predecessor: true)).accepted,
        isTrue,
      );
      expect(lease.block(), same(block));
      lease.release();
      expect(core.liveState.sessions, 0);
      expect(core.liveState.snapshotViews, 1);
      expect(core.liveState.pendingTransfers, 0);
      expect(core.peak['bytes'], lessThanOrEqualTo(6 * 1024 * 1024));
      expect(
        phases,
        containsAll(['encoding', 'hashing', 'comparison', 'projection-slice']),
      );
      // ignore: avoid_print
      print(
        'YIELD_PROOF rich=$rich phases=$phases yields=${probe.yields} peak=${core.peak}',
      );
    });
  }
  testWidgets(
    'Y05 near source cap yields then rejects aggregate duplication without publication',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester);
      final section = run.sections[1];
      final core = LazyForwardHandoffCore(run.state);
      final old = run.state.lazyPublication;
      final probe = YieldProbe();
      final chunks = List.generate(
        428,
        (i) => section.chunks.last.copyWith(index: i),
      );
      final large = ParsedSection(
        identity: section.identity,
        chunks: chunks,
        anchorMap: const {},
        chapters: const [],
        wordCount: 428,
        textCharCount: 428 * (chunks.first.text?.length ?? 0),
        resourceHrefs: const [],
        parserVersion: section.parserVersion,
      );
      final result = await core.beginNextYielding(large, probe.operation(run));
      expect(probe.yields, greaterThan(1));
      expect(
        result.result.outcome,
        LazySnapshotPublicationOutcome.boundExceeded,
        reason: result.result.message,
      );
      expect(result.transfer, isNull);
      expect(run.state.lazyPublication, same(old));
      expect(core.liveState.pendingTransfers, 0);
      expect(core.validationTemporaryBytes, 0);
      expect(core.peak['bytes'], lessThanOrEqualTo(6 * 1024 * 1024));
      expect(core.peak['sources'], 432);
    },
  );

  testWidgets(
    'Y06 renderer lease acquired during yielding retirement blocks commit',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester);
      final core = LazyForwardHandoffCore(run.state);
      final probe = YieldProbe();
      final op = probe.operation(run);
      final token = await prepare(run, core, op, 1);
      expect((await core.publishYielding(token, op)).accepted, isTrue);
      final old = run.state.lazyPublication!;
      run.state.advanceLazyVisibleCard(
        old.current.cards.last.identity.signature,
        op,
      );
      LazyRendererLease? lease;
      probe.onYield = () async {
        lease ??= core.leaseRenderer(
          old.predecessor!.cards.first.identity.signature,
        );
      };
      final result = await core.retainYielding(op);
      expect(lease, isNotNull);
      expect(result.accepted, isFalse);
      expect(run.state.lazyPublication, same(old));
      expect(core.liveState.pendingTransfers, 0);
      lease!.release();
      probe.onYield = null;
      expect((await core.retainYielding(op)).accepted, isTrue);
    },
  );
  testWidgets(
    'Y07 cancellation during stable validation settles and releases every pending root',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester);
      final core = LazyForwardHandoffCore(run.state);
      final probe = YieldProbe();
      final op = probe.operation(run);
      final token = (await core.beginNextYielding(
        run.sections[1],
        op,
      )).transfer!;
      final layout = await run.layout(core.inputFor(token));
      final before = run.state.lazyPublication;
      final reached = Completer<void>(), release = Completer<void>();
      probe.onYield = () async {
        if (!reached.isCompleted && core.validationPhase == 'hashing') {
          reached.complete();
          await release.future;
        }
      };
      final future = core.prepare(token, layout, op);
      await reached.future;
      expect(core.liveState.sessions, greaterThan(0));
      core.cancelPending();
      expect(core.liveState.pendingTransfers, 1);
      release.complete();
      final result = await future;
      expect(result.outcome, LazySnapshotPublicationOutcome.cancelled);
      expect(run.state.lazyPublication, same(before));
      expect(core.liveState.pendingTransfers, 0);
      expect(
        core.liveState.sessions,
        1,
      ); // The original accepted A session only.
      expect(core.validationTemporaryBytes, 0);
    },
  );

  testWidgets(
    'Y08 a caller proof cannot authorize publication and accepted payloads are pinned',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester);
      final core = LazyForwardHandoffCore(run.state);
      final probe = YieldProbe();
      final op = probe.operation(run);
      final token = await prepare(run, core, op, 1);
      final before = run.state.lazyPublication;
      final result = await core.publishYielding(
        token,
        op,
        proposal: LazySnapshotHandoffV1({'kind': 'forged'}),
      );
      expect(result.accepted, isFalse);
      expect(run.state.lazyPublication, same(before));
      expect(core.liveState.pendingTransfers, 0);
      final card = before!.cards.first;
      expect(() => card.sourceSlices.clear(), throwsUnsupportedError);
      if (card.card.sourceRanges != null) {
        expect(() => card.card.sourceRanges!.clear(), throwsUnsupportedError);
      }
    },
  );
  testWidgets(
    'Y09 cancelled retirement remains owned and accounted until its slice settles',
    (tester) async {
      final run = await LazySingleHandoffTestRun.open(tester);
      final core = LazyForwardHandoffCore(run.state);
      final probe = YieldProbe();
      final op = probe.operation(run);
      final token = await prepare(run, core, op, 1);
      expect((await core.publishYielding(token, op)).accepted, isTrue);
      final old = run.state.lazyPublication!;
      run.state.advanceLazyVisibleCard(
        old.current.cards.last.identity.signature,
        op,
      );
      final reached = Completer<void>(), release = Completer<void>();
      probe.onYield = () async {
        if (!reached.isCompleted) {
          reached.complete();
          await release.future;
        }
      };
      final future = core.retainYielding(op);
      await reached.future;
      core.cancelPending();
      expect(core.liveState.pendingTransfers, 1);
      expect(
        (await core.beginPreviousYielding(run.sections[0], op)).result.outcome,
        LazySnapshotPublicationOutcome.busy,
      );
      release.complete();
      expect((await future).accepted, isFalse);
      expect(run.state.lazyPublication, same(old));
      expect(core.liveState.pendingTransfers, 0);
      expect(core.validationTemporaryBytes, 0);
      probe.onYield = null;
      expect((await core.retainYielding(op)).accepted, isTrue);
    },
  );
}
