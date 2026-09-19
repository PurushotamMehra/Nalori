import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/reader_visible_correction_scheduler.dart';

void main() {
  testWidgets('real swipes remain committed after initial restoration', (
    tester,
  ) async {
    final key = GlobalKey<_CorrectionHarnessState>();
    await tester.pumpWidget(_CorrectionHarness(key: key));

    await tester.drag(find.byType(PageView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(key.currentState!.controller.page, 1);
    expect(key.currentState!.coordinator.committedLocation, 'page-1');
    expect(key.currentState!.coordinator.activeIntent, isNull);

    await tester.drag(find.byType(PageView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(key.currentState!.controller.page, 2);
    expect(key.currentState!.coordinator.committedLocation, 'page-2');
    expect(key.currentState!.coordinator.activeIntent, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll-end correction runs after layout once without looping', (
    tester,
  ) async {
    final key = GlobalKey<_CorrectionHarnessState>();
    await tester.pumpWidget(
      _CorrectionHarness(key: key, rejectFirstSwipe: true),
    );

    await tester.drag(find.byType(PageView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(key.currentState!.controller.page, 0);
    expect(key.currentState!.correctionsApplied, 1);
    expect(key.currentState!.coordinator.pendingCorrection, isNull);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(PageView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(key.currentState!.controller.page, 1);
    expect(key.currentState!.coordinator.committedLocation, 'page-1');
    expect(key.currentState!.correctionsApplied, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending correction is inert after reader replacement', (
    tester,
  ) async {
    final oldKey = GlobalKey<_CorrectionHarnessState>();
    await tester.pumpWidget(_CorrectionHarness(key: oldKey));
    oldKey.currentState!.requestCorrection();

    final newKey = GlobalKey<_CorrectionHarnessState>();
    await tester.pumpWidget(_CorrectionHarness(key: newKey));
    await tester.pump();

    expect(oldKey.currentState, isNull);
    expect(newKey.currentState!.controller.page, 0);
    expect(newKey.currentState!.correctionsApplied, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple correction requests coalesce to the latest owner', (
    tester,
  ) async {
    final key = GlobalKey<_CorrectionHarnessState>();
    await tester.pumpWidget(_CorrectionHarness(key: key));

    key.currentState!.requestCorrection();
    key.currentState!.requestCorrection();
    await tester.pump();

    expect(key.currentState!.correctionsApplied, 1);
    expect(key.currentState!.coordinator.pendingCorrection, isNull);
    expect(tester.takeException(), isNull);
  });
}

class _CorrectionHarness extends StatefulWidget {
  const _CorrectionHarness({super.key, this.rejectFirstSwipe = false});

  final bool rejectFirstSwipe;

  @override
  State<_CorrectionHarness> createState() => _CorrectionHarnessState();
}

class _CorrectionHarnessState extends State<_CorrectionHarness> {
  late final PageController controller;
  late final ReaderVisiblePositionCoordinator<String> coordinator;
  late final ReaderVisibleCorrectionScheduler<String> correctionScheduler;
  late bool rejectNextSwipe;
  int correctionsApplied = 0;

  @override
  void initState() {
    super.initState();
    controller = PageController();
    coordinator = ReaderVisiblePositionCoordinator<String>(
      sessionId: 'correction-harness',
      readerGeneration: 1,
    );
    final restore = coordinator.beginInitialRestore(
      target: 'page-0',
      reason: 'initial_restore',
      expectedWindowGeneration: 1,
      expectedPublicationGeneration: 1,
    )!;
    coordinator.markControllerMoved(restore);
    coordinator.completeIntent(
      intent: restore,
      resolvedLocation: 'page-0',
      windowGeneration: 1,
      publicationGeneration: 1,
    );
    correctionScheduler = ReaderVisibleCorrectionScheduler<String>(
      coordinator: coordinator,
      apply: _applyCorrection,
    );
    rejectNextSwipe = widget.rejectFirstSwipe;
  }

  void requestCorrection() {
    coordinator.requestCorrection(
      target: coordinator.authoritativeTarget!,
      reason: 'rejected_visible_settlement',
      expectedWindowGeneration: 1,
      expectedPublicationGeneration: 1,
      controllerIdentity: controller,
    );
    correctionScheduler.schedule();
  }

  void _applyCorrection(ReaderVisibleCorrectionIntent<String> correction) {
    if (!mounted ||
        !coordinator.isCurrentCorrection(
          correction,
          windowGeneration: 1,
          publicationGeneration: 1,
          controllerIdentity: controller,
        )) {
      coordinator.cancelPendingCorrection();
      return;
    }
    controller.jumpToPage(0);
    correctionsApplied++;
    coordinator.completeCorrection(correction);
  }

  @override
  void dispose() {
    correctionScheduler.dispose();
    coordinator.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          final page = controller.page?.round();
          if (page == 1 && rejectNextSwipe) {
            rejectNextSwipe = false;
            requestCorrection();
          } else if (page != null) {
            coordinator.settleUser('page-$page');
          }
          return false;
        },
        child: PageView.builder(
          scrollDirection: Axis.vertical,
          controller: controller,
          itemCount: 3,
          itemBuilder: (_, index) => Center(child: Text('Page $index')),
        ),
      ),
    );
  }
}
