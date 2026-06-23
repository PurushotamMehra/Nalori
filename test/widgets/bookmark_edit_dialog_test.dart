import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/widgets/bookmark_edit_dialog.dart';

void main() {
  Future<BookmarkEditResult?> openDialog(
    WidgetTester tester, {
    required List<Color> palette,
    Color initialColor = const Color(0xFFE1306C),
    Size surfaceSize = const Size(320, 640),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = surfaceSize;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    BookmarkEditResult? result;
    var currentPalette = List<Color>.from(palette);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showDialog<BookmarkEditResult>(
                      context: context,
                      builder: (_) => BookmarkEditDialog(
                        initialName: 'Bookmark 1',
                        initialColor: initialColor,
                        sharedPalette: currentPalette,
                        settings: const ReadingSettings(),
                        onAddCustomColor: (color) async {
                          currentPalette = [
                            Color(bookmarkColorValue(color)),
                            ...currentPalette,
                          ];
                          return currentPalette;
                        },
                        onRemoveCustomColor: (color) async {
                          currentPalette = currentPalette
                              .where(
                                (entry) =>
                                    bookmarkColorValue(entry) !=
                                    bookmarkColorValue(color),
                              )
                              .toList();
                          return currentPalette;
                        },
                        onResetPalette: () async {
                          currentPalette = const [
                            Color(0xFFFFD54F),
                            Color(0xFF81C784),
                          ];
                          return currentPalette;
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('does not overflow with many saved colors on a narrow screen', (
    tester,
  ) async {
    final palette = List<Color>.generate(
      25,
      (index) => Color(0xFF000000 + index * 9973),
    );

    await openDialog(tester, palette: palette);

    expect(tester.takeException(), isNull);
    expect(find.byType(BookmarkEditDialog), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsWidgets);
  });

  testWidgets('shows default pink plus de-duped shared palette colors', (
    tester,
  ) async {
    const customColor = Color(0xFF123456);

    await openDialog(tester, palette: const [Color(0xFFE1306C), customColor]);

    expect(
      find.byKey(const ValueKey('bookmark_color_#E1306C')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bookmark_color_#123456')),
      findsOneWidget,
    );
  });

  testWidgets('selects a shared palette color and returns it on save', (
    tester,
  ) async {
    const customColor = Color(0xFF123456);
    BookmarkEditResult? captured;

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              captured = await showDialog<BookmarkEditResult>(
                context: context,
                builder: (_) => BookmarkEditDialog(
                  initialName: 'Bookmark 1',
                  initialColor: kBookmarkColors.first,
                  sharedPalette: const [customColor],
                  settings: const ReadingSettings(),
                  onAddCustomColor: (color) async => [color, customColor],
                  onRemoveCustomColor: (_) async => const [customColor],
                  onResetPalette: () async => const [customColor],
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bookmark_color_#123456')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured?.color, customColor);
  });

  testWidgets('add action opens shared palette sheet and applies selection', (
    tester,
  ) async {
    const sheetColor = Color(0xFF123456);
    BookmarkEditResult? captured;
    var palette = const [sheetColor];

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              captured = await showDialog<BookmarkEditResult>(
                context: context,
                builder: (_) => BookmarkEditDialog(
                  initialName: 'Bookmark 1',
                  initialColor: kBookmarkColors.first,
                  sharedPalette: palette,
                  settings: const ReadingSettings(),
                  onAddCustomColor: (color) async {
                    palette = [Color(bookmarkColorValue(color)), ...palette];
                    return palette;
                  },
                  onRemoveCustomColor: (_) async => palette,
                  onResetPalette: () async => palette,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add bookmark color'));
    await tester.pumpAndSettle();

    expect(find.text('Choose bookmark color'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('highlight_palette_#123456')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured?.color, sheetColor);
  });
}
