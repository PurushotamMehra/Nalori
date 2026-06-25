import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/widgets/reading_card_deck.dart';

void main() {
  Widget buildHarness({
    required int itemCount,
    bool canSwipe = true,
    int initialIndex = 0,
    Axis axis = Axis.vertical,
    bool selectableText = false,
    ReadingCardDeckController? controller,
    ValueChanged<int>? onChanged,
  }) {
    var currentIndex = initialIndex;
    return MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          return SizedBox(
            width: 320,
            height: 560,
            child: ReadingCardDeck(
              currentIndex: currentIndex,
              itemCount: itemCount,
              canSwipe: canSwipe,
              axis: axis,
              controller: controller,
              onIndexChanged: (index) {
                setState(() => currentIndex = index);
                onChanged?.call(index);
              },
              cardBuilder: (context, index, progress, isCurrent) {
                return Center(
                  child: Container(
                    key: ValueKey('card-$index'),
                    width: 260,
                    height: 420,
                    alignment: Alignment.center,
                    color: isCurrent ? Colors.white : Colors.grey.shade300,
                    child: selectableText
                        ? SelectableText('Selectable card $index')
                        : Text('Card $index'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  testWidgets('swipe up changes to the next card', (tester) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(itemCount: 3, onChanged: (index) => latest = index),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(latest, 1);
    expect(find.text('Card 1'), findsWidgets);
  });

  testWidgets('swipe down changes to the previous card', (tester) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(itemCount: 3, onChanged: (index) => latest = index),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, 220));
    await tester.pumpAndSettle();

    expect(latest, 0);
    expect(find.text('Card 0'), findsWidgets);
  });

  testWidgets('controller animates vertical next card before committing', (
    tester,
  ) async {
    var latest = 0;
    final controller = ReadingCardDeckController();
    await tester.pumpWidget(
      buildHarness(
        itemCount: 3,
        controller: controller,
        onChanged: (index) => latest = index,
      ),
    );

    final started = controller.animateToIndex(
      1,
      const Duration(milliseconds: 220),
      Curves.easeOutCubic,
    );
    await tester.pump(const Duration(milliseconds: 110));

    expect(started, isTrue);
    expect(latest, 0);

    await tester.pumpAndSettle();

    expect(latest, 1);
    expect(find.text('Card 1'), findsWidgets);
  });

  testWidgets('incomplete swipe snaps back', (tester) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(itemCount: 3, onChanged: (index) => latest = index),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, -50));
    await tester.pumpAndSettle();

    expect(latest, 0);
  });

  testWidgets('upward swipe keeps previous card out of the stack', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(itemCount: 4, initialIndex: 1));
    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, -90));
    await tester.pump();

    expect(find.text('Card 0'), findsNothing);
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(ClipRect), findsOneWidget);
  });

  testWidgets('first and last card resist unavailable directions', (
    tester,
  ) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(itemCount: 2, onChanged: (index) => latest = index),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, 240));
    await tester.pumpAndSettle();
    expect(latest, 0);

    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(latest, 1);

    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(latest, 1);
  });

  testWidgets('disabled deck ignores swipe gestures', (tester) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(
        itemCount: 3,
        canSwipe: false,
        onChanged: (index) => latest = index,
      ),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(latest, 0);
  });

  testWidgets('drag beginning on selectable text can still change page', (
    tester,
  ) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(
        itemCount: 3,
        selectableText: true,
        onChanged: (index) => latest = index,
      ),
    );

    await tester.drag(find.text('Selectable card 0'), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(latest, 1);
  });

  testWidgets('stationary long press on selectable text does not navigate', (
    tester,
  ) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(
        itemCount: 3,
        selectableText: true,
        onChanged: (index) => latest = index,
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Selectable card 0')),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(latest, 0);
  });

  testWidgets('current card is not remounted when deck swipe is disabled', (
    tester,
  ) async {
    var canSwipe = true;
    var disposeCount = 0;
    late StateSetter updateHarness;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateHarness = setState;
              return SizedBox(
                width: 320,
                height: 560,
                child: ReadingCardDeck(
                  currentIndex: 0,
                  itemCount: 3,
                  canSwipe: canSwipe,
                  onIndexChanged: (_) {},
                  cardBuilder: (context, index, progress, isCurrent) {
                    return Center(
                      child: _DisposeProbe(
                        onDispose: () => disposeCount++,
                        child: SelectableText('Selectable card $index'),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    updateHarness(() => canSwipe = false);
    await tester.pumpAndSettle();

    expect(disposeCount, 0);
  });

  testWidgets('ignores late pointer events after disposal', (tester) async {
    await tester.pumpWidget(buildHarness(itemCount: 3));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReadingCardDeck)),
    );
    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.moveBy(const Offset(0, -90));
    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('drag transforms reuse existing card widgets', (tester) async {
    var buildCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 560,
            child: ReadingCardDeck(
              currentIndex: 0,
              itemCount: 4,
              cacheCardWidgetsDuringDrag: true,
              onIndexChanged: (_) {},
              cardBuilder: (context, index, progress, isCurrent) {
                buildCount++;
                return Center(
                  child: Container(
                    key: ValueKey('card-$index'),
                    width: 260,
                    height: 420,
                    alignment: Alignment.center,
                    color: isCurrent ? Colors.white : Colors.grey.shade300,
                    child: Text('Card $index'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    final initialBuildCount = buildCount;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ReadingCardDeck)),
    );
    await gesture.moveBy(const Offset(0, -90));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();

    expect(buildCount, initialBuildCount);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('horizontal swipe left changes to the next card', (tester) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(
        itemCount: 3,
        axis: Axis.horizontal,
        onChanged: (index) => latest = index,
      ),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(-260, 0));
    await tester.pumpAndSettle();

    expect(latest, 1);
    expect(find.text('Card 1'), findsWidgets);
  });

  testWidgets('horizontal swipe right changes to the previous card', (
    tester,
  ) async {
    var latest = 1;
    await tester.pumpWidget(
      buildHarness(
        itemCount: 3,
        initialIndex: 1,
        axis: Axis.horizontal,
        onChanged: (index) => latest = index,
      ),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(260, 0));
    await tester.pumpAndSettle();

    expect(latest, 0);
    expect(find.text('Card 0'), findsWidgets);
  });

  testWidgets('controller animates horizontal next card before committing', (
    tester,
  ) async {
    var latest = 0;
    final controller = ReadingCardDeckController();
    await tester.pumpWidget(
      buildHarness(
        itemCount: 3,
        axis: Axis.horizontal,
        controller: controller,
        onChanged: (index) => latest = index,
      ),
    );

    final started = controller.animateToIndex(
      1,
      const Duration(milliseconds: 220),
      Curves.easeOutCubic,
    );
    await tester.pump(const Duration(milliseconds: 110));

    expect(started, isTrue);
    expect(latest, 0);

    await tester.pumpAndSettle();

    expect(latest, 1);
    expect(find.text('Card 1'), findsWidgets);
  });

  testWidgets('incomplete horizontal swipe snaps back', (tester) async {
    var latest = 0;
    await tester.pumpWidget(
      buildHarness(
        itemCount: 3,
        axis: Axis.horizontal,
        onChanged: (index) => latest = index,
      ),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(latest, 0);
  });

  testWidgets('horizontal forward swipe keeps previous card out of the stack', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(itemCount: 4, initialIndex: 1, axis: Axis.horizontal),
    );

    await tester.drag(find.byType(ReadingCardDeck), const Offset(-90, 0));
    await tester.pump();

    expect(find.text('Card 0'), findsNothing);
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(ClipRect), findsOneWidget);
  });
}

class _DisposeProbe extends StatefulWidget {
  final Widget child;
  final VoidCallback onDispose;

  const _DisposeProbe({required this.child, required this.onDispose});

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
