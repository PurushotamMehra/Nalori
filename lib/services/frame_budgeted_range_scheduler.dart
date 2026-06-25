import 'dart:async';

enum DisplayRangeTaskPriority {
  speculativeLookahead(10),
  initialVisible(20),
  boundaryWait(30),
  directTarget(40);

  const DisplayRangeTaskPriority(this.rank);

  final int rank;

  bool outranks(DisplayRangeTaskPriority other) => rank > other.rank;
}

typedef RangeSchedulerClock = Duration Function();
typedef RangeSchedulerYield = Future<void> Function();

final class FrameBudgetedRangeMetrics {
  const FrameBudgetedRangeMetrics({
    required this.totalElapsed,
    required this.longestWorkInterval,
    required this.maxSliceDuration,
    required this.sliceCount,
    required this.yieldCount,
    required this.totalYieldDuration,
    required this.maxSourceChunksPerSlice,
    required this.maxDisplayChunksPerSlice,
    required this.sourceChunksProcessed,
    required this.displayChunksProduced,
    this.cancellationLatency,
  });

  final Duration totalElapsed;
  final Duration longestWorkInterval;
  final Duration maxSliceDuration;
  final int sliceCount;
  final int yieldCount;
  final Duration totalYieldDuration;
  final int maxSourceChunksPerSlice;
  final int maxDisplayChunksPerSlice;
  final int sourceChunksProcessed;
  final int displayChunksProduced;
  final Duration? cancellationLatency;
}

final class FrameBudgetedRangeScheduler {
  FrameBudgetedRangeScheduler({
    this.frameBudget = const Duration(milliseconds: 8),
    this.sourceChunksPerSliceBudget = 4,
    this.displayChunksPerSliceBudget = 12,
    RangeSchedulerYield? yieldToFrame,
    RangeSchedulerClock? clock,
  }) : _yieldToFrame =
           yieldToFrame ?? (() => Future<void>.delayed(Duration.zero)),
       _clock = clock ?? (() => _monotonicElapsed);

  final Duration frameBudget;
  final int sourceChunksPerSliceBudget;
  final int displayChunksPerSliceBudget;
  final RangeSchedulerYield _yieldToFrame;
  final RangeSchedulerClock _clock;
  FrameBudgetedRangeTask? _activeTask;

  static final Stopwatch _monotonicClock = Stopwatch()..start();
  static Duration get _monotonicElapsed => _monotonicClock.elapsed;

  FrameBudgetedRangeTask startTask({
    required int id,
    required DisplayRangeTaskPriority priority,
    required bool Function() isExternallyCancelled,
  }) {
    final active = _activeTask;
    if (active != null && !active.isFinished) {
      if (active.id == id) return active;
      if (priority.outranks(active.priority)) {
        active.cancel('preempted_by_higher_priority');
      }
    }

    final task = FrameBudgetedRangeTask._(
      scheduler: this,
      id: id,
      priority: priority,
      isExternallyCancelled: isExternallyCancelled,
      startedAt: _clock(),
    );
    _activeTask = task;
    return task;
  }

  void dispose() {
    _activeTask?.cancel('scheduler_disposed');
    _activeTask = null;
  }

  void _clearIfActive(FrameBudgetedRangeTask task) {
    if (identical(_activeTask, task)) {
      _activeTask = null;
    }
  }
}

final class FrameBudgetedRangeTask {
  FrameBudgetedRangeTask._({
    required FrameBudgetedRangeScheduler scheduler,
    required this.id,
    required this.priority,
    required bool Function() isExternallyCancelled,
    required Duration startedAt,
  }) : _scheduler = scheduler,
       _isExternallyCancelled = isExternallyCancelled,
       _startedAt = startedAt,
       _sliceStartedAt = startedAt,
       _lastCheckpointAt = startedAt;

  final FrameBudgetedRangeScheduler _scheduler;
  final int id;
  final DisplayRangeTaskPriority priority;
  final bool Function() _isExternallyCancelled;
  final Duration _startedAt;
  Duration _sliceStartedAt;
  Duration _lastCheckpointAt;
  bool _cancelled = false;
  bool _finished = false;
  String? _cancellationReason;
  Duration? _cancelledAt;
  int _sliceCount = 0;
  int _yieldCount = 0;
  Duration _totalYieldDuration = Duration.zero;
  Duration _longestWorkInterval = Duration.zero;
  Duration _maxSliceDuration = Duration.zero;
  int _sliceSourceChunks = 0;
  int _sliceDisplayChunks = 0;
  int _maxSourceChunksPerSlice = 0;
  int _maxDisplayChunksPerSlice = 0;
  int _sourceChunksProcessed = 0;
  int _displayChunksProduced = 0;

  bool get isCancelled => _cancelled || _isExternallyCancelled();
  bool get isFinished => _finished;
  String? get cancellationReason =>
      _cancellationReason ??
      (_isExternallyCancelled() ? 'external_cancellation' : null);

  void cancel(String reason) {
    if (_cancelled) return;
    _cancelled = true;
    _cancellationReason = reason;
    _cancelledAt = _scheduler._clock();
  }

  Future<bool> checkpoint({
    int sourceChunksProcessed = 0,
    int displayChunksProduced = 0,
  }) async {
    _sourceChunksProcessed += sourceChunksProcessed;
    _displayChunksProduced += displayChunksProduced;
    _sliceSourceChunks += sourceChunksProcessed;
    _sliceDisplayChunks += displayChunksProduced;

    if (isCancelled) return false;

    final now = _scheduler._clock();
    final uninterrupted = now - _lastCheckpointAt;
    if (uninterrupted > _longestWorkInterval) {
      _longestWorkInterval = uninterrupted;
    }
    _lastCheckpointAt = now;

    final sliceDuration = now - _sliceStartedAt;
    final sourceBudgetExceeded =
        _scheduler.sourceChunksPerSliceBudget > 0 &&
        _sliceSourceChunks >= _scheduler.sourceChunksPerSliceBudget;
    final displayBudgetExceeded =
        _scheduler.displayChunksPerSliceBudget > 0 &&
        _sliceDisplayChunks >= _scheduler.displayChunksPerSliceBudget;
    if (sliceDuration < _scheduler.frameBudget &&
        !sourceBudgetExceeded &&
        !displayBudgetExceeded) {
      return true;
    }

    _finishCurrentSlice(sliceDuration);
    final yieldStartedAt = _scheduler._clock();
    await _scheduler._yieldToFrame();
    final yieldDuration = _scheduler._clock() - yieldStartedAt;
    _yieldCount++;
    _totalYieldDuration += yieldDuration;
    _sliceStartedAt = _scheduler._clock();
    _lastCheckpointAt = _sliceStartedAt;
    return !isCancelled;
  }

  FrameBudgetedRangeMetrics finish() {
    if (_finished) return _metrics(_scheduler._clock());
    final now = _scheduler._clock();
    final sliceDuration = now - _sliceStartedAt;
    if (sliceDuration > Duration.zero ||
        _sliceSourceChunks > 0 ||
        _sliceDisplayChunks > 0) {
      _finishCurrentSlice(sliceDuration);
    }
    _finished = true;
    _scheduler._clearIfActive(this);
    return _metrics(now);
  }

  void _finishCurrentSlice(Duration duration) {
    _sliceCount++;
    if (duration > _maxSliceDuration) {
      _maxSliceDuration = duration;
    }
    if (duration > _longestWorkInterval) {
      _longestWorkInterval = duration;
    }
    if (_sliceSourceChunks > _maxSourceChunksPerSlice) {
      _maxSourceChunksPerSlice = _sliceSourceChunks;
    }
    if (_sliceDisplayChunks > _maxDisplayChunksPerSlice) {
      _maxDisplayChunksPerSlice = _sliceDisplayChunks;
    }
    _sliceSourceChunks = 0;
    _sliceDisplayChunks = 0;
  }

  FrameBudgetedRangeMetrics _metrics(Duration now) {
    return FrameBudgetedRangeMetrics(
      totalElapsed: now - _startedAt,
      longestWorkInterval: _longestWorkInterval,
      maxSliceDuration: _maxSliceDuration,
      sliceCount: _sliceCount,
      yieldCount: _yieldCount,
      totalYieldDuration: _totalYieldDuration,
      maxSourceChunksPerSlice: _maxSourceChunksPerSlice,
      maxDisplayChunksPerSlice: _maxDisplayChunksPerSlice,
      sourceChunksProcessed: _sourceChunksProcessed,
      displayChunksProduced: _displayChunksProduced,
      cancellationLatency: _cancelledAt == null ? null : now - _cancelledAt!,
    );
  }
}
