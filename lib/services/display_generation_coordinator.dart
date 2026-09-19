import 'dart:async';

enum DisplayGenerationState {
  idle,
  loadingCache,
  buildingInitialWindow,
  readyPartial,
  expandingForeground,
  expandingBackground,
  complete,
  cancelled,
  failed,
}

enum DisplayGenerationRequestKind { start, join, replace, blockedFailure }

enum DisplayGenerationTerminalKind { ready, failed, cancelled, stale }

final class DisplayGenerationTerminalResult {
  const DisplayGenerationTerminalResult(this.kind, {this.error});

  final DisplayGenerationTerminalKind kind;
  final Object? error;
}

class DisplayGenerationSignature {
  final String bookId;
  final int parsedContentVersion;
  final String layoutSignature;
  final String settingsSignature;
  final String viewportSignature;
  final String cacheKey;
  final String sourceSnapshotIdentity;
  final String targetIdentity;

  const DisplayGenerationSignature({
    required this.bookId,
    required this.parsedContentVersion,
    required this.layoutSignature,
    required this.settingsSignature,
    required this.viewportSignature,
    required this.cacheKey,
    this.sourceSnapshotIdentity = '',
    this.targetIdentity = '',
  });

  @override
  bool operator ==(Object other) {
    return other is DisplayGenerationSignature &&
        other.bookId == bookId &&
        other.parsedContentVersion == parsedContentVersion &&
        other.layoutSignature == layoutSignature &&
        other.settingsSignature == settingsSignature &&
        other.viewportSignature == viewportSignature &&
        other.cacheKey == cacheKey &&
        other.sourceSnapshotIdentity == sourceSnapshotIdentity &&
        other.targetIdentity == targetIdentity;
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    parsedContentVersion,
    layoutSignature,
    settingsSignature,
    viewportSignature,
    cacheKey,
    sourceSnapshotIdentity,
    targetIdentity,
  );

  @override
  String toString() {
    return 'DisplayGenerationSignature('
        'bookId: $bookId, '
        'parsedContentVersion: $parsedContentVersion, '
        'layoutSignature: $layoutSignature, '
        'settingsSignature: $settingsSignature, '
        'viewportSignature: $viewportSignature, '
        'cacheKey: $cacheKey, '
        'sourceSnapshotIdentity: $sourceSnapshotIdentity, '
        'targetIdentity: $targetIdentity'
        ')';
  }
}

class DisplayGenerationToken {
  final int id;
  final DisplayGenerationSignature signature;
  DisplayGenerationState state;
  bool _cancelled = false;
  String? _cancellationReason;
  final Completer<DisplayGenerationTerminalResult> _terminal =
      Completer<DisplayGenerationTerminalResult>();

  DisplayGenerationToken._({
    required this.id,
    required this.signature,
    required this.state,
  });

  bool get isCancelled => _cancelled;
  String? get cancellationReason => _cancellationReason;
  Future<DisplayGenerationTerminalResult> get done => _terminal.future;

  void cancel(String reason) {
    if (_cancelled) return;
    _cancelled = true;
    _cancellationReason = reason;
    state = DisplayGenerationState.cancelled;
    if (!_terminal.isCompleted) {
      _terminal.complete(
        DisplayGenerationTerminalResult(
          reason == 'signature_changed'
              ? DisplayGenerationTerminalKind.stale
              : DisplayGenerationTerminalKind.cancelled,
        ),
      );
    }
  }

  void _finish(DisplayGenerationTerminalResult result) {
    if (!_terminal.isCompleted) _terminal.complete(result);
  }
}

class DisplayGenerationRequest {
  final DisplayGenerationRequestKind kind;
  final DisplayGenerationToken token;
  final DisplayGenerationToken? cancelledToken;

  const DisplayGenerationRequest._({
    required this.kind,
    required this.token,
    this.cancelledToken,
  });
}

class DisplayGenerationCoordinator {
  int _nextId = 0;
  DisplayGenerationToken? _active;
  DisplayGenerationToken? _failed;

  DisplayGenerationToken? get activeToken => _active;

  DisplayGenerationRequest request(DisplayGenerationSignature signature) {
    final active = _active;
    if (active != null &&
        !active.isCancelled &&
        active.signature == signature) {
      return DisplayGenerationRequest._(
        kind: DisplayGenerationRequestKind.join,
        token: active,
      );
    }

    final failed = _failed;
    if (failed != null && failed.signature == signature) {
      return DisplayGenerationRequest._(
        kind: DisplayGenerationRequestKind.blockedFailure,
        token: failed,
      );
    }

    DisplayGenerationToken? cancelled;
    if (active != null && !active.isCancelled) {
      active.cancel('signature_changed');
      cancelled = active;
    }

    final token = DisplayGenerationToken._(
      id: ++_nextId,
      signature: signature,
      state: DisplayGenerationState.loadingCache,
    );
    _active = token;
    _failed = null;

    return DisplayGenerationRequest._(
      kind: cancelled == null
          ? DisplayGenerationRequestKind.start
          : DisplayGenerationRequestKind.replace,
      token: token,
      cancelledToken: cancelled,
    );
  }

  DisplayGenerationRequest retry(DisplayGenerationSignature signature) {
    if (_failed?.signature == signature) _failed = null;
    return request(signature);
  }

  bool canPublish(DisplayGenerationToken token) {
    return identical(_active, token) && !token.isCancelled;
  }

  bool canWriteCache(DisplayGenerationToken token, String cacheKey) {
    return canPublish(token) && token.signature.cacheKey == cacheKey;
  }

  void markState(DisplayGenerationToken token, DisplayGenerationState state) {
    if (!canPublish(token)) return;
    token.state = state;
  }

  void complete(DisplayGenerationToken token) {
    if (!canPublish(token)) return;
    token.state = DisplayGenerationState.complete;
    token._finish(
      const DisplayGenerationTerminalResult(
        DisplayGenerationTerminalKind.ready,
      ),
    );
    _active = null;
  }

  void fail(DisplayGenerationToken token, [Object? error]) {
    if (!canPublish(token)) return;
    token.state = DisplayGenerationState.failed;
    token._finish(
      DisplayGenerationTerminalResult(
        DisplayGenerationTerminalKind.failed,
        error: error,
      ),
    );
    _active = null;
    _failed = token;
  }

  void settleReadyPartial(DisplayGenerationToken token) {
    if (!canPublish(token)) return;
    token.state = DisplayGenerationState.readyPartial;
    token._finish(
      const DisplayGenerationTerminalResult(
        DisplayGenerationTerminalKind.ready,
      ),
    );
  }

  void cancelActive(String reason) {
    final active = _active;
    if (active == null) return;
    active.cancel(reason);
    _active = null;
  }

  void clearFailure() {
    _failed = null;
  }
}

class ReaderNavigationToken<T> {
  const ReaderNavigationToken._({required this.id, required this.target});

  final int id;
  final T target;
}

/// Owns pending-versus-published navigation generations independently from
/// layout/display generation. Starting or failing a newer target never clears
/// the last readable publication; only the latest target may replace it.
class ReaderNavigationPublicationCoordinator<T> {
  int _nextId = 0;
  int _latestId = 0;
  int? _publishedId;
  ReaderNavigationToken<T>? _pending;

  ReaderNavigationToken<T>? get pending => _pending;
  int? get publishedGeneration => _publishedId;
  bool get hasPublishedReadableContent => _publishedId != null;

  ReaderNavigationToken<T> begin(T target) {
    final token = ReaderNavigationToken<T>._(id: ++_nextId, target: target);
    _latestId = token.id;
    _pending = token;
    return token;
  }

  bool isLatest(ReaderNavigationToken<T> token) => token.id == _latestId;

  void markReadablePublished([ReaderNavigationToken<T>? token]) {
    if (token != null && !isLatest(token)) return;
    _publishedId = token?.id ?? _publishedId ?? 0;
    if (token != null && identical(_pending, token)) {
      _pending = null;
    }
  }

  void fail(ReaderNavigationToken<T> token) {
    if (!isLatest(token)) return;
    if (identical(_pending, token)) _pending = null;
  }

  void cancelPending() {
    _latestId = ++_nextId;
    _pending = null;
  }
}

enum ReaderVisibleMutationClassification { user, programmatic, synthetic }

enum ReaderVisibleRestorationState { preparing, committed, disposed }

enum ReaderVisibleNavigationPhase {
  requested,
  targetResolved,
  windowPublished,
  controllerMoved,
  settled,
  rejected,
  failed,
  cancelled,
}

enum ReaderVisibleCorrectionPhase { scheduled, applied, superseded, cancelled }

class ReaderVisibleCorrectionIntent<T> {
  ReaderVisibleCorrectionIntent._({
    required this.id,
    required this.readerGeneration,
    required this.reason,
    required this.target,
    required this.expectedWindowGeneration,
    required this.expectedPublicationGeneration,
    required this.controllerIdentity,
  });

  final int id;
  final int readerGeneration;
  final String reason;
  final T target;
  final int expectedWindowGeneration;
  final int expectedPublicationGeneration;
  final Object controllerIdentity;
  ReaderVisibleCorrectionPhase _phase = ReaderVisibleCorrectionPhase.scheduled;

  ReaderVisibleCorrectionPhase get phase => _phase;
  bool get isConsumed => _phase != ReaderVisibleCorrectionPhase.scheduled;
}

class ReaderVisibleNavigationIntent<T> {
  ReaderVisibleNavigationIntent._({
    required this.id,
    required this.readerGeneration,
    required this.reason,
    required T target,
    required int expectedWindowGeneration,
    required int expectedPublicationGeneration,
    required this.isInitialRestore,
  }) : _target = target,
       _expectedWindowGeneration = expectedWindowGeneration,
       _expectedPublicationGeneration = expectedPublicationGeneration;

  final int id;
  final int readerGeneration;
  final String reason;
  T _target;
  int _expectedWindowGeneration;
  int _expectedPublicationGeneration;
  final bool isInitialRestore;
  ReaderVisibleNavigationPhase _phase = ReaderVisibleNavigationPhase.requested;
  bool _consumed = false;

  bool get isConsumed => _consumed;
  T get target => _target;
  int get expectedWindowGeneration => _expectedWindowGeneration;
  int get expectedPublicationGeneration => _expectedPublicationGeneration;
  ReaderVisibleNavigationPhase get phase => _phase;
}

class ReaderVisibleMutationDecision<T> {
  const ReaderVisibleMutationDecision._({
    required this.accepted,
    required this.reason,
    required this.oldLocation,
    required this.newLocation,
    this.intentId,
  });

  final bool accepted;
  final String reason;
  final T? oldLocation;
  final T? newLocation;
  final int? intentId;
}

/// Single owner for the stable source position shown by one reader instance.
///
/// Display, window, controller, and pagination indexes intentionally do not
/// appear in this state. They are publication-local hints resolved by the UI.
/// A content publication may preserve the authoritative target, but it cannot
/// change or commit it.
class ReaderVisiblePositionCoordinator<T> {
  ReaderVisiblePositionCoordinator({
    required this.sessionId,
    required int readerGeneration,
  }) : _readerGeneration = readerGeneration;

  final String sessionId;
  int _readerGeneration;
  int _nextIntentId = 0;
  int _nextCorrectionId = 0;
  ReaderVisibleRestorationState _restorationState =
      ReaderVisibleRestorationState.preparing;
  ReaderVisibleNavigationIntent<T>? _activeIntent;
  ReaderVisibleCorrectionIntent<T>? _pendingCorrection;
  T? _committedLocation;

  int get readerGeneration => _readerGeneration;
  ReaderVisibleRestorationState get restorationState => _restorationState;
  bool get restorationComplete =>
      _restorationState == ReaderVisibleRestorationState.committed;
  ReaderVisibleNavigationIntent<T>? get activeIntent => _activeIntent;
  ReaderVisibleCorrectionIntent<T>? get pendingCorrection => _pendingCorrection;
  T? get committedLocation => _committedLocation;
  T? get authoritativeTarget {
    final active = _activeIntent;
    if (active == null) return _committedLocation;
    if (!active.isInitialRestore &&
        active.phase == ReaderVisibleNavigationPhase.requested) {
      return _committedLocation;
    }
    return active.target;
  }

  bool get isGestureSuppressed =>
      _activeIntent != null && !_activeIntent!.isInitialRestore;

  ReaderVisibleNavigationIntent<T>? beginInitialRestore({
    required T target,
    required String reason,
    required int expectedWindowGeneration,
    required int expectedPublicationGeneration,
  }) {
    if (_restorationState != ReaderVisibleRestorationState.preparing) {
      return null;
    }
    cancelPendingCorrection();
    final active = _activeIntent;
    if (active != null) return active;
    return _activeIntent = _newIntent(
      target: target,
      reason: reason,
      expectedWindowGeneration: expectedWindowGeneration,
      expectedPublicationGeneration: expectedPublicationGeneration,
      isInitialRestore: true,
    );
  }

  ReaderVisibleNavigationIntent<T>? beginExplicit({
    required T target,
    required String reason,
    required int expectedWindowGeneration,
    required int expectedPublicationGeneration,
  }) {
    if (_restorationState != ReaderVisibleRestorationState.committed) {
      return null;
    }
    cancelPendingCorrection();
    final previous = _activeIntent;
    if (previous != null) {
      previous._phase = ReaderVisibleNavigationPhase.cancelled;
      previous._consumed = true;
    }
    return _activeIntent = _newIntent(
      target: target,
      reason: reason,
      expectedWindowGeneration: expectedWindowGeneration,
      expectedPublicationGeneration: expectedPublicationGeneration,
      isInitialRestore: false,
    );
  }

  ReaderVisibleNavigationIntent<T> _newIntent({
    required T target,
    required String reason,
    required int expectedWindowGeneration,
    required int expectedPublicationGeneration,
    required bool isInitialRestore,
  }) {
    return ReaderVisibleNavigationIntent<T>._(
      id: ++_nextIntentId,
      readerGeneration: _readerGeneration,
      reason: reason,
      target: target,
      expectedWindowGeneration: expectedWindowGeneration,
      expectedPublicationGeneration: expectedPublicationGeneration,
      isInitialRestore: isInitialRestore,
    );
  }

  bool isCurrent(ReaderVisibleNavigationIntent<T> intent) {
    return _restorationState != ReaderVisibleRestorationState.disposed &&
        identical(_activeIntent, intent) &&
        !intent.isConsumed &&
        intent.readerGeneration == _readerGeneration;
  }

  bool resolveIntentTarget({
    required ReaderVisibleNavigationIntent<T> intent,
    required T target,
    required int expectedWindowGeneration,
    required int expectedPublicationGeneration,
  }) {
    if (!isCurrent(intent) ||
        intent.phase == ReaderVisibleNavigationPhase.controllerMoved) {
      return false;
    }
    intent._target = target;
    intent._expectedWindowGeneration = expectedWindowGeneration;
    intent._expectedPublicationGeneration = expectedPublicationGeneration;
    intent._phase = ReaderVisibleNavigationPhase.targetResolved;
    return true;
  }

  bool markWindowPublished({
    required ReaderVisibleNavigationIntent<T> intent,
    required T resolvedLocation,
    required int windowGeneration,
    required int publicationGeneration,
  }) {
    if (!isCurrent(intent) ||
        intent.target != resolvedLocation ||
        intent.phase == ReaderVisibleNavigationPhase.controllerMoved) {
      return false;
    }
    intent._expectedWindowGeneration = windowGeneration;
    intent._expectedPublicationGeneration = publicationGeneration;
    intent._phase = ReaderVisibleNavigationPhase.windowPublished;
    return true;
  }

  bool markControllerMoved(ReaderVisibleNavigationIntent<T> intent) {
    if (!isCurrent(intent)) return false;
    intent._phase = ReaderVisibleNavigationPhase.controllerMoved;
    return true;
  }

  ReaderVisibleMutationDecision<T> completeIntent({
    required ReaderVisibleNavigationIntent<T> intent,
    required T resolvedLocation,
    required int windowGeneration,
    required int publicationGeneration,
  }) {
    final old = _committedLocation;
    String? rejection;
    if (!isCurrent(intent)) {
      rejection = intent.isConsumed ? 'intent_consumed' : 'stale_intent';
    } else if (intent.target != resolvedLocation) {
      rejection = 'target_location_mismatch';
    } else if (intent.expectedWindowGeneration != windowGeneration) {
      rejection = 'window_generation_mismatch';
    } else if (intent.expectedPublicationGeneration != publicationGeneration) {
      rejection = 'publication_generation_mismatch';
    }
    if (rejection != null) {
      if (isCurrent(intent)) {
        intent._consumed = true;
        intent._phase = ReaderVisibleNavigationPhase.rejected;
        _activeIntent = null;
      }
      return ReaderVisibleMutationDecision<T>._(
        accepted: false,
        reason: rejection,
        oldLocation: old,
        newLocation: old,
        intentId: intent.id,
      );
    }

    intent._consumed = true;
    intent._phase = ReaderVisibleNavigationPhase.settled;
    _activeIntent = null;
    cancelPendingCorrection();
    _committedLocation = resolvedLocation;
    _restorationState = ReaderVisibleRestorationState.committed;
    return ReaderVisibleMutationDecision<T>._(
      accepted: true,
      reason: intent.isInitialRestore
          ? 'initial_restore_committed'
          : 'explicit_intent_committed',
      oldLocation: old,
      newLocation: resolvedLocation,
      intentId: intent.id,
    );
  }

  ReaderVisibleMutationDecision<T> settleUser(T location) {
    final old = _committedLocation;
    if (_restorationState != ReaderVisibleRestorationState.committed) {
      return ReaderVisibleMutationDecision<T>._(
        accepted: false,
        reason: 'restore_not_complete',
        oldLocation: old,
        newLocation: old,
      );
    }
    final active = _activeIntent;
    if (active != null) {
      active._phase = ReaderVisibleNavigationPhase.cancelled;
      active._consumed = true;
      _activeIntent = null;
    }
    cancelPendingCorrection();
    _committedLocation = location;
    return ReaderVisibleMutationDecision<T>._(
      accepted: true,
      reason: 'user_settlement_committed',
      oldLocation: old,
      newLocation: location,
    );
  }

  ReaderVisibleMutationDecision<T> rejectSynthetic({String? reason}) {
    return ReaderVisibleMutationDecision<T>._(
      accepted: false,
      reason: reason ?? 'synthetic_mutation_cannot_commit',
      oldLocation: _committedLocation,
      newLocation: _committedLocation,
      intentId: _activeIntent?.id,
    );
  }

  bool canPublishPreserving(T location) {
    final target = authoritativeTarget;
    return _restorationState != ReaderVisibleRestorationState.disposed &&
        target != null &&
        target == location;
  }

  ReaderVisibleCorrectionIntent<T>? requestCorrection({
    required T target,
    required String reason,
    required int expectedWindowGeneration,
    required int expectedPublicationGeneration,
    required Object controllerIdentity,
  }) {
    if (_restorationState == ReaderVisibleRestorationState.disposed) {
      return null;
    }
    final previous = _pendingCorrection;
    if (previous != null) {
      previous._phase = ReaderVisibleCorrectionPhase.superseded;
    }
    return _pendingCorrection = ReaderVisibleCorrectionIntent<T>._(
      id: ++_nextCorrectionId,
      readerGeneration: _readerGeneration,
      reason: reason,
      target: target,
      expectedWindowGeneration: expectedWindowGeneration,
      expectedPublicationGeneration: expectedPublicationGeneration,
      controllerIdentity: controllerIdentity,
    );
  }

  bool isCurrentCorrection(
    ReaderVisibleCorrectionIntent<T> correction, {
    required int windowGeneration,
    required int publicationGeneration,
    required Object controllerIdentity,
  }) {
    return _restorationState != ReaderVisibleRestorationState.disposed &&
        identical(_pendingCorrection, correction) &&
        !correction.isConsumed &&
        correction.readerGeneration == _readerGeneration &&
        correction.expectedWindowGeneration == windowGeneration &&
        correction.expectedPublicationGeneration == publicationGeneration &&
        identical(correction.controllerIdentity, controllerIdentity) &&
        authoritativeTarget == correction.target;
  }

  void completeCorrection(ReaderVisibleCorrectionIntent<T> correction) {
    if (!identical(_pendingCorrection, correction) || correction.isConsumed) {
      return;
    }
    correction._phase = ReaderVisibleCorrectionPhase.applied;
    _pendingCorrection = null;
  }

  void cancelPendingCorrection() {
    final pending = _pendingCorrection;
    if (pending != null && !pending.isConsumed) {
      pending._phase = ReaderVisibleCorrectionPhase.cancelled;
    }
    _pendingCorrection = null;
  }

  void cancelActiveIntent({bool failed = false}) {
    final active = _activeIntent;
    if (active != null) {
      active._phase = failed
          ? ReaderVisibleNavigationPhase.failed
          : ReaderVisibleNavigationPhase.cancelled;
      active._consumed = true;
    }
    _activeIntent = null;
  }

  void dispose() {
    cancelPendingCorrection();
    cancelActiveIntent();
    _readerGeneration++;
    _restorationState = ReaderVisibleRestorationState.disposed;
  }
}
