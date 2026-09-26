import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/lazy_forward_handoff_core.dart';
import 'package:nalori/services/lazy_snapshot_handoff_service.dart';

import 'lazy_single_handoff_test.dart' show LazySingleHandoffTestRun;
import 'lazy_yielding_handoff_test.dart' show YieldProbe;
import 'support/lazy_address_fixture.dart';

Future<LazySingleHandoffTestRun> open(
  WidgetTester tester, {
  bool finalB = true,
  bool longParagraphs = false,
  int pairs = 12,
}) async {
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('first-batch-'),
  ))!;
  addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
  final body = longParagraphs
      ? '<h1>Successor B</h1>${List.generate(24, (i) => '<p>Paragraph $i ${List.generate(70, (w) => 'word$w').join(' ')}.</p>').join()}'
      : List.generate(
          pairs,
          (i) => '<h1>Part $i</h1><p>Small readable paragraph $i.</p>',
        ).join();
  final file = (await tester.runAsync(
    () => File('${root.path}/book.epub').writeAsBytes(
      buildAddressFixture(
        sectionCount: finalB ? 2 : 3,
        sectionBodies: {2: body},
      ),
    ),
  ))!;
  return LazySingleHandoffTestRun.open(tester, fixture: file);
}

Future<LazyForwardTransfer> first(
  LazySingleHandoffTestRun run,
  LazyForwardHandoffCore core,
  LazyHandoffOperation op,
) async {
  final begin = await core.beginNextYielding(run.sections[1], op);
  expect(begin.transfer, isNotNull, reason: begin.result.message);
  final result = await core.prepare(
    begin.transfer!,
    await run.layout(core.inputFor(begin.transfer!)),
    op,
    firstBatchOnly: true,
  );
  expect(
    result.outcome,
    LazySnapshotPublicationOutcome.prepared,
    reason: result.message,
  );
  return begin.transfer!;
}

void main() {
  for (final finalB in [false, true]) {
    testWidgets(
      'P01 finalized first batch and incremental exact output finalB=$finalB',
      (tester) async {
        final run = await open(tester, finalB: finalB);
        final reference = await run.prepareB(tester);
        expect(reference.cards.length, greaterThanOrEqualTo(6));
        final core = LazyForwardHandoffCore(run.state);
        final probe = YieldProbe();
        final op = probe.operation(run);
        final a = run.state.lazyPublication!;
        final token = await first(run, core, op);
        expect(run.state.lazyPublication, same(a));
        final result = await core.publishYielding(token, op);
        expect(result.accepted, isTrue, reason: result.message);
        final initial =
            run.state.lazyPublication!.current as LazyPreparedSection;
        expect(initial.sectionComplete, isFalse);
        expect(initial.cards.length, lessThan(reference.cards.length ~/ 2));
        expect(initial.workEntries, lessThan(reference.workEntries));
        expect(initial.receipt, isNull);
        expect(initial.continuation!.terminal, isFalse);
        expect(run.state.generationComplete, isFalse);
        expect(run.state.canonicalCards.take(a.cards.length), a.cards);
        expect(core.liveState.frontierCardReservation, greaterThan(0));
        final oldLease = core.leaseRenderer(a.cards.first.identity.signature);
        expect(
          oldLease.block(),
          same(a.cards.first.resolvedLayout!.blocks.single),
        );
        // Neither direction of retirement may discard B's live frontier.
        expect(
          (await core.retainYielding(op, predecessor: true)).outcome,
          LazySnapshotPublicationOutcome.retentionRequired,
        );
        run.state.advanceLazyVisibleCard(
          initial.cards.first.identity.signature,
          op,
        );
        expect((await core.retainYielding(op)).accepted, isFalse);
        var batches = 1;
        final starts = <int>[
          initial.continuation!.nextSourceCursor.sourceOrdinalHint,
        ];
        while (!run.state.lazyPublication!.current.sectionComplete) {
          final before = run.state.lazyPublication!;
          final previous = before.current as LazyPreparedSection;
          final begin = core.beginContinuation(op);
          expect(begin.transfer, isNotNull, reason: begin.result.message);
          final prepared = await core.prepare(
            begin.transfer!,
            previous.session.layout,
            op,
          );
          expect(
            prepared.outcome,
            LazySnapshotPublicationOutcome.prepared,
            reason: prepared.message,
          );
          expect(run.state.lazyPublication, same(before));
          expect(previous.matchesSession, isTrue);
          final accepted = await core.publishYielding(begin.transfer!, op);
          expect(accepted.accepted, isTrue, reason: accepted.message);
          final next =
              run.state.lazyPublication!.current as LazyPreparedSection;
          expect(next.cards.length, greaterThan(previous.cards.length));
          for (var i = 0; i < previous.cards.length; i++) {
            expect(next.cards[i], same(previous.cards[i]));
            expect(next.bodies[i], same(previous.bodies[i]));
          }
          expect(
            next.parentContinuationDigest,
            previous.continuation!.integrityDigest,
          );
          expect(next.session.isForwardForkOf(previous.session), isTrue);
          if (!next.sectionComplete) {
            starts.add(next.continuation!.nextSourceCursor.sourceOrdinalHint);
          }
          expect(run.state.lazyPublication!.handoffOrdinal, 1);
          expect(++batches, lessThan(25));
        }
        final complete =
            run.state.lazyPublication!.current as LazyPreparedSection;
        expect(
          complete.bodies.map((b) => b.canonicalEncoding),
          reference.bodies.map((b) => b.canonicalEncoding),
        );
        expect(complete.cardGuards, reference.cardGuards);
        expect(complete.receipt == null, finalB);
        expect(complete.session.inputExhaustedAwaitingSuccessor, !finalB);
        expect(run.state.generationComplete, finalB);
        expect(core.beginContinuation(op).transfer, isNull);
        oldLease.release();
        run.state.advanceLazyVisibleCard(
          complete.cards.last.identity.signature,
          op,
        );
        expect((await core.retainYielding(op)).accepted, isTrue);
        expect(core.liveState.sessions, 0);
        expect(core.liveState.pendingTransfers, 0);
        if (!finalB) {
          final backward = await core.beginPreviousYielding(
            run.sections[0],
            op,
          );
          expect(backward.transfer, isNotNull, reason: backward.result.message);
          final back = backward.transfer!;
          final ready = await core.prepare(
            back,
            await run.layout(core.inputFor(back)),
            op,
            committedLayout: await run.layout(
              run.state.lazyPublication!.current.input,
            ),
          );
          expect(
            ready.outcome,
            LazySnapshotPublicationOutcome.prepared,
            reason: ready.message,
          );
          final accepted = await core.publishYielding(back, op);
          expect(accepted.accepted, isTrue, reason: accepted.message);
          run.state.advanceLazyVisibleCard(
            run
                .state
                .lazyPublication!
                .predecessor!
                .cards
                .first
                .identity
                .signature,
            op,
          );
          expect(
            (await core.retainYielding(op, predecessor: true)).accepted,
            isTrue,
          );
          final again = await first(run, core, op);
          expect((await core.publishYielding(again, op)).accepted, isTrue);
          expect(run.state.lazyPublication!.current.sectionComplete, isFalse);
        }
        // ignore: avoid_print
        print(
          'FIRST_BATCH final=$finalB firstCards=${initial.cards.length} totalCards=${complete.cards.length} firstWork=${initial.workEntries} fullWork=${reference.workEntries} batches=$batches sources=${run.sections[1].chunks.length} starts=$starts peak=${core.peak}',
        );
      },
    );
  }

  for (final race in [
    'cancel-before-first',
    'stale-before-first',
    'cancel-later',
    'stale-later',
  ]) {
    testWidgets(
      'P02 $race preserves accepted authority and permits exact continuation',
      (tester) async {
        final run = await open(tester);
        final core = LazyForwardHandoffCore(run.state);
        final probe = YieldProbe();
        final op = probe.operation(run);
        var token = await first(run, core, op);
        if (race.endsWith('later')) {
          expect((await core.publishYielding(token, op)).accepted, isTrue);
          final previous =
              run.state.lazyPublication!.current as LazyPreparedSection;
          token = core.beginContinuation(op).transfer!;
          final reached = Completer<void>(), release = Completer<void>();
          probe.onYield = () async {
            if (!reached.isCompleted) {
              reached.complete();
              await release.future;
            }
          };
          final before = run.state.lazyPublication;
          final suffix = previous.continuation;
          final pending = core.prepare(token, previous.session.layout, op);
          await reached.future;
          expect(run.state.lazyPublication, same(before));
          expect(previous.continuation, same(suffix));
          if (race.startsWith('cancel')) {
            core.cancelPending();
          } else {
            run.currentOwner = (bookOpenEpoch: 2, displayOwner: 1, attempt: 0);
          }
          expect(core.liveState.pendingTransfers, 1);
          release.complete();
          expect(
            (await pending).outcome,
            isNot(LazySnapshotPublicationOutcome.prepared),
          );
          expect(run.state.lazyPublication, same(before));
          expect(previous.matchesSession, isTrue);
          expect(core.liveState.pendingTransfers, 0);
          probe.onYield = null;
          run.currentOwner = run.owner;
          final retry = core.beginContinuation(op).transfer!;
          expect(
            (await core.prepare(retry, previous.session.layout, op)).outcome,
            LazySnapshotPublicationOutcome.prepared,
          );
          expect((await core.publishYielding(retry, op)).accepted, isTrue);
        } else {
          final before = run.state.lazyPublication;
          if (race.startsWith('cancel')) {
            core.cancelPending();
          } else {
            run.currentOwner = (bookOpenEpoch: 2, displayOwner: 1, attempt: 0);
          }
          expect((await core.publishYielding(token, op)).accepted, isFalse);
          expect(run.state.lazyPublication, same(before));
          expect(core.liveState.pendingTransfers, 0);
        }
      },
    );
  }
  for (final race in ['visible', 'cancel']) {
    testWidgets(
      'P03 $race at extension commit preserves B and its continuation',
      (tester) async {
        final run = await open(tester);
        final core = LazyForwardHandoffCore(run.state);
        final op = run.operation;
        final initial = await first(run, core, op);
        expect((await core.publishYielding(initial, op)).accepted, isTrue);
        final old = run.state.lazyPublication!;
        final b = old.current as LazyPreparedSection;
        final token = core.beginContinuation(op).transfer!;
        expect(
          (await core.prepare(token, b.session.layout, op)).outcome,
          LazySnapshotPublicationOutcome.prepared,
        );
        final result = await core.publishYielding(
          token,
          op,
          beforeCommit: () {
            if (race == 'cancel') {
              core.cancelPending();
            } else {
              run.state.advanceLazyVisibleCard(
                b.cards.last.identity.signature,
                op,
              );
            }
          },
        );
        expect(result.accepted, isFalse);
        expect(run.state.lazyPublication, same(old));
        expect(b.matchesSession, isTrue);
        expect(core.liveState.pendingTransfers, 0);
        expect(
          (await core.publishYielding(token, op)).outcome,
          LazySnapshotPublicationOutcome.replayed,
        );
        expect(core.beginContinuation(op).transfer, isNotNull);
        core.cancelPending();
      },
    );
  }

  testWidgets(
    'P04 live frontier shares the card budget; refusal preserves accepted first batch',
    (tester) async {
      final run = await open(tester);
      final core = LazyForwardHandoffCore(
        run.state,
        limits: const LazyForwardRetentionLimits(cards: 6),
      );
      final op = run.operation;
      final initial = await first(run, core, op);
      expect((await core.publishYielding(initial, op)).accepted, isTrue);
      final old = run.state.lazyPublication!;
      final b = old.current as LazyPreparedSection;
      expect(core.liveState.frontierCardReservation, greaterThan(0));
      final token = core.beginContinuation(op).transfer!;
      final rejected = await core.prepare(token, b.session.layout, op);
      expect(rejected.outcome, LazySnapshotPublicationOutcome.boundExceeded);
      expect(run.state.lazyPublication, same(old));
      expect(b.matchesSession, isTrue);
      expect(core.liveState.pendingTransfers, 0);
      expect(core.peak['cards'], lessThanOrEqualTo(6));
    },
  );

  testWidgets(
    'P05 strict renderer overflow remains a rejection without first-card acceptance',
    (tester) async {
      final run = await open(tester, longParagraphs: true);
      final core = LazyForwardHandoffCore(run.state);
      final old = run.state.lazyPublication;
      final op = run.operation;
      final token = (await core.beginNextYielding(
        run.sections[1],
        op,
      )).transfer!;
      final rejected = await core.prepare(
        token,
        await run.layout(core.inputFor(token)),
        op,
        firstBatchOnly: true,
      );
      expect(rejected.outcome, LazySnapshotPublicationOutcome.boundExceeded);
      expect(rejected.message, contains('overflowing block'));
      expect(run.state.lazyPublication, same(old));
      expect(core.liveState.pendingTransfers, 0);
    },
  );
  testWidgets(
    'P06 many bounded batches retain only exact active checkpoint parents',
    (tester) async {
      final run = await open(tester, pairs: 24);
      final reference = await run.prepareB(tester);
      expect(reference.cards.length, 48);
      final core = LazyForwardHandoffCore(run.state);
      final op = run.operation;
      final token = await first(run, core, op);
      expect((await core.publishYielding(token, op)).accepted, isTrue);
      var batches = 1;
      while (!run.state.lazyPublication!.current.sectionComplete) {
        final old = run.state.lazyPublication!.current as LazyPreparedSection;
        final next = core.beginContinuation(op).transfer!;
        final result = await core.prepare(next, old.session.layout, op);
        expect(
          result.outcome,
          LazySnapshotPublicationOutcome.prepared,
          reason: result.message,
        );
        final accepted = await core.publishYielding(next, op);
        expect(accepted.accepted, isTrue, reason: accepted.message);
        final current =
            run.state.lazyPublication!.current as LazyPreparedSection;
        expect(
          current.session.checkpointIndex.records.length,
          lessThanOrEqualTo(3),
        );
        expect(core.liveState.guards, lessThanOrEqualTo(12));
        expect(
          core.liveState.sessions,
          2,
        ); // A and current B; no historical forks.
        expect(core.liveState.pendingTransfers, 0);
        expect(++batches, lessThanOrEqualTo(24));
      }
      expect(batches, 24);
      expect(
        run.state.lazyPublication!.current.bodies.map(
          (b) => b.canonicalEncoding,
        ),
        reference.bodies.map((b) => b.canonicalEncoding),
      );
      expect(core.peak['guards'], lessThanOrEqualTo(12));
      expect(core.peak['bytes'], lessThanOrEqualTo(6 * 1024 * 1024));
      // ignore: avoid_print
      print(
        'FIRST_BATCH_LONG batches=$batches peak=${core.peak} settled=${core.liveState.toJson()}',
      );
    },
  );
}
