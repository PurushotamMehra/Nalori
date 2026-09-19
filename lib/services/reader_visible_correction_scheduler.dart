import 'package:flutter/scheduler.dart';

import 'display_generation_coordinator.dart';

class ReaderVisibleCorrectionScheduler<T> {
  ReaderVisibleCorrectionScheduler({
    required ReaderVisiblePositionCoordinator<T> coordinator,
    required void Function(ReaderVisibleCorrectionIntent<T> correction) apply,
  }) : _coordinator = coordinator,
       _apply = apply;

  final ReaderVisiblePositionCoordinator<T> _coordinator;
  final void Function(ReaderVisibleCorrectionIntent<T> correction) _apply;
  bool _scheduled = false;
  bool _disposed = false;

  bool get isScheduled => _scheduled;

  void schedule() {
    if (_disposed || _scheduled || _coordinator.pendingCorrection == null) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      final correction = _coordinator.pendingCorrection;
      if (correction != null) _apply(correction);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void dispose() {
    _disposed = true;
    _scheduled = false;
  }
}
