class ReaderPositionSession {
  ReaderPositionSession({int initialDisplayIndex = 0})
    : committedReadingPosition = initialDisplayIndex,
      activeVisiblePosition = initialDisplayIndex;

  int committedReadingPosition;
  int activeVisiblePosition;
  int? previewPosition;
  bool isScrubbing = false;
  DateTime? lastUserNavigationAt;
  int navigationGeneration = 0;
  int _modalDepth = 0;
  int? _modalVisiblePosition;

  bool get hasActivePreviewPosition => previewPosition != null;

  bool get canCommitActiveVisiblePosition =>
      !isNavigationSuspended && !isScrubbing && !hasActivePreviewPosition;

  bool get isNavigationSuspended => _modalDepth > 0;

  int? get modalVisiblePosition => _modalVisiblePosition;

  void beginModalState(int displayIndex) {
    if (_modalDepth == 0) {
      _modalVisiblePosition = displayIndex;
      activeVisiblePosition = displayIndex;
      previewPosition = null;
      isScrubbing = false;
      navigationGeneration++;
    }
    _modalDepth++;
  }

  int? endModalState() {
    if (_modalDepth == 0) return null;
    _modalDepth--;
    final captured = _modalVisiblePosition;
    if (_modalDepth == 0) {
      _modalVisiblePosition = null;
      if (captured != null) {
        activeVisiblePosition = captured;
      }
      previewPosition = null;
      isScrubbing = false;
      navigationGeneration++;
    }
    return captured;
  }

  void markVisible(int displayIndex) {
    if (isNavigationSuspended) return;
    activeVisiblePosition = displayIndex;
    navigationGeneration++;
  }

  void commit(int displayIndex) {
    if (isNavigationSuspended) return;
    committedReadingPosition = displayIndex;
    activeVisiblePosition = displayIndex;
    previewPosition = null;
    isScrubbing = false;
    lastUserNavigationAt = DateTime.now();
    navigationGeneration++;
  }

  void markCommitted(int displayIndex) {
    committedReadingPosition = displayIndex;
  }

  void startPreview(int displayIndex, {bool scrubbing = false}) {
    if (isNavigationSuspended) return;
    activeVisiblePosition = displayIndex;
    previewPosition = displayIndex;
    isScrubbing = scrubbing;
    navigationGeneration++;
  }

  void updatePreview(int displayIndex) {
    if (isNavigationSuspended) return;
    activeVisiblePosition = displayIndex;
    previewPosition = displayIndex;
    navigationGeneration++;
  }

  void finishScrub() {
    isScrubbing = false;
  }

  int? promotePreview() {
    if (isNavigationSuspended) return null;
    final preview = previewPosition;
    if (preview == null) return null;
    commit(preview);
    return preview;
  }

  void clearPreview({int? visibleDisplayIndex}) {
    previewPosition = null;
    isScrubbing = false;
    if (!isNavigationSuspended && visibleDisplayIndex != null) {
      activeVisiblePosition = visibleDisplayIndex;
    }
    navigationGeneration++;
  }
}
