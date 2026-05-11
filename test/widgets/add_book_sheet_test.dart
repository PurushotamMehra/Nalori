import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/l10n/app_localizations.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/widgets/add_book_sheet.dart';

void main() {
  Widget buildHarness({
    required VoidCallback onImport,
    required VoidCallback onBrowse,
    ReadingSettings settings = const ReadingSettings(),
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => AddBookSheet(
                    settings: settings,
                    onImportEpub: onImport,
                    onBrowseProjectGutenberg: onBrowse,
                  ),
                );
              },
              child: const Text('Open sheet'),
            );
          },
        ),
      ),
    );
  }

  testWidgets('opens with polished add book copy and dark surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(onImport: () {}, onBrowse: () {}));

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Add a book'), findsOneWidget);
    expect(
      find.text('Import your own EPUB or browse free classics.'),
      findsOneWidget,
    );
    expect(find.text('Import EPUB'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Browse Project Gutenberg'), findsOneWidget);
    expect(
      find.text('Supported format: EPUB. Imported books stay on this device.'),
      findsOneWidget,
    );
  });

  testWidgets('import card dismisses the sheet and triggers callback', (
    tester,
  ) async {
    var imports = 0;
    await tester.pumpWidget(
      buildHarness(onImport: () => imports++, onBrowse: () {}),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import EPUB'));
    await tester.pumpAndSettle();

    expect(imports, 1);
    expect(find.text('Add a book'), findsNothing);
  });

  testWidgets(
    'Project Gutenberg card dismisses the sheet and triggers callback',
    (tester) async {
      var browse = 0;
      await tester.pumpWidget(
        buildHarness(onImport: () {}, onBrowse: () => browse++),
      );

      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse Project Gutenberg'));
      await tester.pumpAndSettle();

      expect(browse, 1);
      expect(find.text('Add a book'), findsNothing);
    },
  );

  testWidgets('sheet text remains visible on a small screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildHarness(onImport: () {}, onBrowse: () {}));
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Import EPUB'), findsOneWidget);
    expect(find.text('Choose a book file from this device'), findsOneWidget);
    expect(find.text('Browse Project Gutenberg'), findsOneWidget);
    expect(find.text('Explore free public-domain EPUBs'), findsOneWidget);
  });
}
