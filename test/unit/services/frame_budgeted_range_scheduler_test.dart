import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';

void main() {
  test('splits work across scheduler-controlled slices', () async {
    var now = Duration.zero;
    var yields = 0;
    final scheduler = FrameBudgetedRangeScheduler(
      frameBudget: const Duration(milliseconds: 5),
      clock: () => now,
      yieldToFrame: () async {
        yields++;
        now += const Duration(milliseconds: 2);
      },
    );

    final task = scheduler.startTask(
      id: 1,
      priority: DisplayRangeTaskPriority.boundaryWait,
      isExternallyCancelled: () => false,
    );

    for (var i = 0; i < 12; i++) {
      now += const Duration(milliseconds: 1);
      expect(
        await task.checkpoint(
          sourceChunksProcessed: 1,
          displayChunksProduced: i.isEven ? 1 : 0,
        ),
        isTrue,
      );
    }

    final metrics = task.finish();
    expect(yields, greaterThan(0));
    expect(metrics.yieldCount, yields);
    expect(metrics.sliceCount, greaterThan(1));
    expect(metrics.maxSliceDuration.inMilliseconds, lessThanOrEqualTo(5));
    expect(metrics.sourceChunksProcessed, 12);
    expect(metrics.displayChunksProduced, 6);
    expect(metrics.maxSourceChunksPerSlice, greaterThan(0));
  });

  test('continuation resumes without altering deterministic output', () async {
    var now = Duration.zero;
    final yieldedAt = <int>[];
    final scheduler = FrameBudgetedRangeScheduler(
      frameBudget: const Duration(milliseconds: 3),
      clock: () => now,
      yieldToFrame: () async => yieldedAt.add(now.inMilliseconds),
    );
    final sliced = <int>[];
    final synchronous = <int>[];
    final task = scheduler.startTask(
      id: 2,
      priority: DisplayRangeTaskPriority.initialVisible,
      isExternallyCancelled: () => false,
    );

    for (var i = 0; i < 10; i++) {
      synchronous.add(i * i);
      sliced.add(i * i);
      now += const Duration(milliseconds: 1);
      expect(await task.checkpoint(sourceChunksProcessed: 1), isTrue);
    }

    task.finish();
    expect(yieldedAt, isNotEmpty);
    expect(sliced, synchronous);
  });

  test('yields when source or display unit budget is reached', () async {
    var now = Duration.zero;
    var yields = 0;
    final scheduler = FrameBudgetedRangeScheduler(
      frameBudget: const Duration(seconds: 1),
      sourceChunksPerSliceBudget: 3,
      displayChunksPerSliceBudget: 5,
      clock: () => now,
      yieldToFrame: () async {
        yields++;
      },
    );
    final task = scheduler.startTask(
      id: 20,
      priority: DisplayRangeTaskPriority.boundaryWait,
      isExternallyCancelled: () => false,
    );

    expect(await task.checkpoint(sourceChunksProcessed: 1), isTrue);
    expect(await task.checkpoint(sourceChunksProcessed: 1), isTrue);
    expect(await task.checkpoint(sourceChunksProcessed: 1), isTrue);
    expect(yields, 1);

    expect(await task.checkpoint(displayChunksProduced: 4), isTrue);
    expect(yields, 1);
    expect(await task.checkpoint(displayChunksProduced: 1), isTrue);
    expect(yields, 2);

    final metrics = task.finish();
    expect(metrics.maxSourceChunksPerSlice, 3);
    expect(metrics.maxDisplayChunksPerSlice, 5);
  });

  test('cancels promptly between slices', () async {
    var now = Duration.zero;
    final scheduler = FrameBudgetedRangeScheduler(
      frameBudget: const Duration(milliseconds: 5),
      clock: () => now,
    );
    final task = scheduler.startTask(
      id: 3,
      priority: DisplayRangeTaskPriority.boundaryWait,
      isExternallyCancelled: () => false,
    );

    expect(await task.checkpoint(sourceChunksProcessed: 1), isTrue);
    task.cancel('settings_changed');
    now += const Duration(milliseconds: 2);
    expect(await task.checkpoint(sourceChunksProcessed: 1), isFalse);

    final metrics = task.finish();
    expect(task.cancellationReason, 'settings_changed');
    expect(metrics.cancellationLatency?.inMilliseconds, 2);
  });

  test('higher priority task preempts lower priority active work', () async {
    var now = Duration.zero;
    final scheduler = FrameBudgetedRangeScheduler(
      frameBudget: const Duration(milliseconds: 5),
      clock: () => now,
    );
    final speculative = scheduler.startTask(
      id: 4,
      priority: DisplayRangeTaskPriority.speculativeLookahead,
      isExternallyCancelled: () => false,
    );

    final target = scheduler.startTask(
      id: 5,
      priority: DisplayRangeTaskPriority.directTarget,
      isExternallyCancelled: () => false,
    );

    expect(await speculative.checkpoint(), isFalse);
    expect(speculative.cancellationReason, 'preempted_by_higher_priority');
    expect(await target.checkpoint(), isTrue);
  });

  test('duplicate task id joins the active scheduler task', () {
    final scheduler = FrameBudgetedRangeScheduler();
    final first = scheduler.startTask(
      id: 6,
      priority: DisplayRangeTaskPriority.boundaryWait,
      isExternallyCancelled: () => false,
    );
    final second = scheduler.startTask(
      id: 6,
      priority: DisplayRangeTaskPriority.boundaryWait,
      isExternallyCancelled: () => false,
    );

    expect(identical(first, second), isTrue);
  });

  test('dispose cancels pending active work', () async {
    final scheduler = FrameBudgetedRangeScheduler();
    final task = scheduler.startTask(
      id: 7,
      priority: DisplayRangeTaskPriority.boundaryWait,
      isExternallyCancelled: () => false,
    );

    scheduler.dispose();

    expect(await task.checkpoint(), isFalse);
    expect(task.cancellationReason, 'scheduler_disposed');
  });
}
