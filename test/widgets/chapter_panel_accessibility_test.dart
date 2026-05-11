import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/widgets/chapter_panel.dart';

void main() {
  testWidgets('chapter panel exposes chapter and bookmark navigation labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterPanel(
            chapters: const [
              ChapterInfo(title: 'Opening', chunkIndex: 0),
              ChapterInfo(title: 'Second Chapter', chunkIndex: 4),
            ],
            currentPage: 0,
            originalToDisplay: const {0: 0, 4: 4},
            onNavigate: (_) {},
            settings: const ReadingSettings(),
            bookmarks: [
              Bookmark(
                chunkIndex: 4,
                name: 'Important passage',
                createdAt: DateTime.fromMillisecondsSinceEpoch(1),
                previewText: 'Important bookmarked passage.',
              ),
            ],
            totalDisplayPages: 10,
            chunkTexts: const {4: 'Important bookmarked passage.'},
            onRemoveBookmark: (_) {},
            onClearAllBookmarks: () {},
            onRestoreBookmarks: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.bySemanticsLabel('Opening'), findsOneWidget);

    await tester.tap(find.text('Bookmarks'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Important passage'), findsOneWidget);
    semantics.dispose();
  });
}
