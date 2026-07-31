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

enum DisplayGenerationRequestKind { start, join, replace }

class DisplayGenerationSignature {
  final String bookId;
  final int parsedContentVersion;
  final String layoutSignature;
  final String settingsSignature;
  final String viewportSignature;
  final String cacheKey;

  const DisplayGenerationSignature({
    required this.bookId,
    required this.parsedContentVersion,
    required this.layoutSignature,
    required this.settingsSignature,
    required this.viewportSignature,
    required this.cacheKey,
  });

  @override
  bool operator ==(Object other) {
    return other is DisplayGenerationSignature &&
        other.bookId == bookId &&
        other.parsedContentVersion == parsedContentVersion &&
        other.layoutSignature == layoutSignature &&
        other.settingsSignature == settingsSignature &&
        other.viewportSignature == viewportSignature &&
        other.cacheKey == cacheKey;
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    parsedContentVersion,
    layoutSignature,
    settingsSignature,
    viewportSignature,
    cacheKey,
  );

  @override
  String toString() {
    return 'DisplayGenerationSignature('
        'bookId: $bookId, '
        'parsedContentVersion: $parsedContentVersion, '
        'layoutSignature: $layoutSignature, '
        'settingsSignature: $settingsSignature, '
        'viewportSignature: $viewportSignature, '
        'cacheKey: $cacheKey'
        ')';
  }
}

class DisplayGenerationToken {
  final int id;
  final DisplayGenerationSignature signature;
  DisplayGenerationState state;
  bool _cancelled = false;
  String? _cancellationReason;

  DisplayGenerationToken._({
    required this.id,
    required this.signature,
    required this.state,
  });

  bool get isCancelled => _cancelled;
  String? get cancellationReason => _cancellationReason;

  void cancel(String reason) {
    _cancelled = true;
    _cancellationReason = reason;
    state = DisplayGenerationState.cancelled;
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

    return DisplayGenerationRequest._(
      kind: cancelled == null
          ? DisplayGenerationRequestKind.start
          : DisplayGenerationRequestKind.replace,
      token: token,
      cancelledToken: cancelled,
    );
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
    _active = null;
  }

  void fail(DisplayGenerationToken token) {
    if (!canPublish(token)) return;
    token.state = DisplayGenerationState.failed;
    _active = null;
  }

  void cancelActive(String reason) {
    final active = _active;
    if (active == null) return;
    active.cancel(reason);
    _active = null;
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
