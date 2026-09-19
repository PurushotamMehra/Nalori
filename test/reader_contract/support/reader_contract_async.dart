import 'dart:async';

/// Later production connection points for event evidence.
///
/// These names record evidence only. They do not implement any coordinator,
/// acceptance rule or navigation state machine.
enum ReaderContractEventKind {
  boundaryEntered,
  boundaryReleased,
  boundaryFailed,
  boundaryClosed,
  operationObserved,
}

/// Stable evidence carried by a probe event. All fields are optional because a
/// particular production boundary may not expose all identities yet.
final class ReaderContractEventEvidence {
  const ReaderContractEventEvidence({
    this.bookId,
    this.sessionId,
    this.intentId,
    this.generationId,
    this.publicationId,
    this.cardIdentity,
  });

  final String? bookId;
  final String? sessionId;
  final String? intentId;
  final int? generationId;
  final String? publicationId;
  final String? cardIdentity;

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'bookId': bookId,
    'sessionId': sessionId,
    'intentId': intentId,
    'generationId': generationId,
    'publicationId': publicationId,
    'cardIdentity': cardIdentity,
  };
}

final class ReaderContractEvent {
  const ReaderContractEvent({
    required this.sequence,
    required this.kind,
    required this.label,
    required this.evidence,
  });

  final int sequence;
  final ReaderContractEventKind kind;
  final String label;
  final ReaderContractEventEvidence evidence;

  @override
  String toString() =>
      '#$sequence ${kind.name}($label) ${evidence.toDiagnosticMap()}';
}

/// Per-test chronological probe. It is deliberately not global.
final class ReaderContractEventProbe {
  final List<ReaderContractEvent> _events = <ReaderContractEvent>[];

  List<ReaderContractEvent> get events => List.unmodifiable(_events);

  ReaderContractEvent record({
    required ReaderContractEventKind kind,
    required String label,
    ReaderContractEventEvidence evidence = const ReaderContractEventEvidence(),
  }) {
    final event = ReaderContractEvent(
      sequence: _events.length + 1,
      kind: kind,
      label: label,
      evidence: evidence,
    );
    _events.add(event);
    return event;
  }

  /// Fails immediately with useful causal context after a test has driven the
  /// expected boundary. It intentionally does not use a wall-clock timeout.
  ReaderContractEvent require(ReaderContractEventKind kind, {String? label}) {
    for (final event in _events) {
      if (event.kind == kind && (label == null || event.label == label)) {
        return event;
      }
    }
    throw StateError(
      'Expected reader-contract event ${kind.name}'
      '${label == null ? '' : ' for "$label"'} never occurred. '
      'Observed: ${_events.join(', ')}',
    );
  }

  /// Proves that a named observation did not occur after a test has driven all
  /// relevant work. This does not infer production stale-work acceptance; the
  /// later production-connected test supplies that state evidence.
  void requireAbsent(ReaderContractEventKind kind, {String? label}) {
    for (final event in _events) {
      if (event.kind == kind && (label == null || event.label == label)) {
        throw StateError(
          'Unexpected reader-contract event ${kind.name}'
          '${label == null ? '' : ' for "$label"'} occurred: $event. '
          'Observed: ${_events.join(', ')}',
        );
      }
    }
  }

  void requireKinds(List<ReaderContractEventKind> expected) {
    final actual = _events.map((event) => event.kind).toList();
    if (!_sameKinds(actual, expected)) {
      throw StateError(
        'Reader-contract causal order mismatch. Expected '
        '${expected.map((kind) => kind.name).toList()}, observed '
        '${_events.join(', ')}.',
      );
    }
  }
}

/// A typed, one-shot controlled completion at an already injectable boundary.
///
/// Current connections: none. TASK-P02-005 may connect paginator scheduling;
/// P07 may connect checkpoint/path-platform operations; P09 may connect
/// publication/controller settlement once production exposes those events.
/// This gate cannot prove that production accepts or rejects stale work; later
/// contract tests must assert that against production state.
final class ReaderContractGate<T> {
  ReaderContractGate({required this.label, ReaderContractEventProbe? probe})
    : probe = probe ?? ReaderContractEventProbe() {
    // A teardown can close a gate that was never awaited. Suppress the
    // otherwise unhandled internal error without changing what a caller sees
    // when it explicitly awaits either public future.
    _entered.future.ignore();
    _completion.future.ignore();
  }

  final String label;
  final ReaderContractEventProbe probe;
  final Completer<ReaderContractEventEvidence> _entered =
      Completer<ReaderContractEventEvidence>();
  final Completer<T> _completion = Completer<T>();
  bool _enteredOnce = false;
  bool _closed = false;

  bool get hasEntered => _enteredOnce;
  bool get isPending => _enteredOnce && !_completion.isCompleted;
  bool get isClosed => _closed;
  Future<ReaderContractEventEvidence> get entered => _entered.future;

  Future<T> wait({
    ReaderContractEventEvidence evidence = const ReaderContractEventEvidence(),
  }) {
    if (_closed) {
      throw StateError('Reader-contract gate "$label" is closed.');
    }
    if (_enteredOnce) {
      throw StateError(
        'Reader-contract gate "$label" is one-shot and was entered twice.',
      );
    }
    _enteredOnce = true;
    probe.record(
      kind: ReaderContractEventKind.boundaryEntered,
      label: label,
      evidence: evidence,
    );
    _entered.complete(evidence);
    return _completion.future;
  }

  void release(
    T value, {
    ReaderContractEventEvidence evidence = const ReaderContractEventEvidence(),
  }) {
    _ensurePending('release');
    _completion.complete(value);
    probe.record(
      kind: ReaderContractEventKind.boundaryReleased,
      label: label,
      evidence: evidence,
    );
  }

  void fail(
    Object error, [
    StackTrace? stackTrace,
    ReaderContractEventEvidence evidence = const ReaderContractEventEvidence(),
  ]) {
    _ensurePending('fail');
    _completion.completeError(error, stackTrace);
    probe.record(
      kind: ReaderContractEventKind.boundaryFailed,
      label: label,
      evidence: evidence,
    );
  }

  /// Closes a held operation with a deterministic error so test teardown never
  /// leaves a pending completer. Callers should await the returned operation.
  void close({
    ReaderContractEventEvidence evidence = const ReaderContractEventEvidence(),
  }) {
    if (_closed) {
      throw StateError('Reader-contract gate "$label" was closed twice.');
    }
    _closed = true;
    if (!_entered.isCompleted) {
      _entered.completeError(
        StateError('Reader-contract gate "$label" closed before entry.'),
      );
    }
    if (!_completion.isCompleted) {
      _completion.completeError(
        StateError('Reader-contract gate "$label" closed before release.'),
      );
    }
    probe.record(
      kind: ReaderContractEventKind.boundaryClosed,
      label: label,
      evidence: evidence,
    );
  }

  void requireEntered() {
    if (!hasEntered) {
      throw StateError(
        'Reader-contract gate "$label" was never entered. '
        'Observed: ${probe.events.join(', ')}',
      );
    }
  }

  void _ensurePending(String action) {
    if (!_enteredOnce || _completion.isCompleted || _closed) {
      throw StateError(
        'Reader-contract gate "$label" cannot $action; '
        'entered=$_enteredOnce pending=$isPending closed=$_closed.',
      );
    }
  }
}

bool _sameKinds(
  List<ReaderContractEventKind> first,
  List<ReaderContractEventKind> second,
) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
