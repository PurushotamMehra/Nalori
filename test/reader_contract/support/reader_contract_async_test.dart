import 'package:flutter_test/flutter_test.dart';

import 'reader_contract_async.dart';

void main() {
  group('[REQ-035, REQ-042] reader-contract asynchronous controls', () {
    test(
      'entered and released events have deterministic causal order',
      () async {
        final probe = ReaderContractEventProbe();
        final gate = ReaderContractGate<int>(
          label: 'cache-write',
          probe: probe,
        );
        final operation = gate.wait(
          evidence: const ReaderContractEventEvidence(
            bookId: 'book-a',
            sessionId: 'session-a',
            generationId: 3,
          ),
        );

        final entered = await gate.entered;
        expect(entered.generationId, 3);
        gate.release(
          7,
          evidence: const ReaderContractEventEvidence(
            bookId: 'book-a',
            sessionId: 'session-a',
            generationId: 3,
            publicationId: 'publication-4',
            cardIdentity: 'card-5',
          ),
        );

        expect(await operation, 7);
        probe.requireKinds(const <ReaderContractEventKind>[
          ReaderContractEventKind.boundaryEntered,
          ReaderContractEventKind.boundaryReleased,
        ]);
        expect(probe.events.last.evidence.cardIdentity, 'card-5');
      },
    );

    test('success and error completions are distinct', () async {
      final success = ReaderContractGate<String>(label: 'success');
      final successOperation = success.wait();
      await success.entered;
      success.release('complete');
      expect(await successOperation, 'complete');

      final failure = ReaderContractGate<String>(label: 'failure');
      final failureOperation = failure.wait();
      await failure.entered;
      failure.fail(ArgumentError('expected failure'));
      await expectLater(failureOperation, throwsA(isA<ArgumentError>()));
      expect(
        failure.probe.events.last.kind,
        ReaderContractEventKind.boundaryFailed,
      );
    });

    test('double release and double close are deterministic errors', () async {
      final gate = ReaderContractGate<int>(label: 'one-shot');
      final operation = gate.wait();
      await gate.entered;
      gate.release(1);
      expect(await operation, 1);
      expect(() => gate.release(2), throwsStateError);

      final closing = ReaderContractGate<int>(label: 'cleanup');
      final closingOperation = closing.wait();
      await closing.entered;
      closing.close();
      await expectLater(closingOperation, throwsStateError);
      expect(closing.close, throwsStateError);
    });

    test('separate gates and probes have no shared events', () async {
      final first = ReaderContractGate<int>(label: 'first');
      final second = ReaderContractGate<int>(label: 'second');
      final firstOperation = first.wait();
      await first.entered;
      first.release(1);
      expect(await firstOperation, 1);

      expect(first.probe.events, hasLength(2));
      expect(second.probe.events, isEmpty);
      second.requireEntered;
      expect(() => second.requireEntered(), throwsStateError);
      first.probe.requireAbsent(
        ReaderContractEventKind.operationObserved,
        label: 'stale-mutation',
      );
    });

    test('awaited close leaves no pending completer', () async {
      final gate = ReaderContractGate<void>(label: 'pending-cleanup');
      final operation = gate.wait();
      await gate.entered;
      expect(gate.isPending, isTrue);

      gate.close();
      await expectLater(operation, throwsStateError);
      expect(gate.isPending, isFalse);
      expect(gate.isClosed, isTrue);
      gate.probe.require(ReaderContractEventKind.boundaryClosed);
    });

    test(
      'closing before entry completes both diagnostic futures safely',
      () async {
        final gate = ReaderContractGate<int>(label: 'never-entered');

        gate.close();

        await expectLater(gate.entered, throwsStateError);
        expect(gate.isClosed, isTrue);
        expect(gate.isPending, isFalse);
        expect(() => gate.close(), throwsStateError);
      },
    );
  });
}
