import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/models/saved_word.dart';
import 'package:nalori/screens/book_memory_screen.dart';
import 'package:nalori/services/book_memory_service.dart';

void main() {
  Widget screen(BookMemorySnapshot memory) {
    return MaterialApp(
      home: BookMemoryScreen(
        bookFile: File('test.epub'),
        bookId: memory.bookId,
        settings: const ReadingSettings(),
        memoryFuture: Future.value(memory),
      ),
    );
  }

  testWidgets('empty state renders without crashing', (tester) async {
    await tester.pumpWidget(
      screen(BookMemorySnapshot.empty(bookId: 'empty.epub')),
    );
    await tester.pump();

    expect(find.text('Unknown Book'), findsOneWidget);
    expect(find.text('No memory saved for this book yet.'), findsOneWidget);
  });

  testWidgets('summary counts match fixture data', (tester) async {
    await tester.pumpWidget(screen(_fixtureMemory()));
    await tester.pump();

    expect(find.byTooltip('Bookmarks'), findsOneWidget);
    expect(find.byTooltip('Highlights'), findsOneWidget);
    expect(find.byTooltip('Notes'), findsOneWidget);
    expect(find.byTooltip('Words'), findsOneWidget);
    expect(find.byTooltip('Characters'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(5));
    expect(find.text('Bookmarks 1'), findsNothing);
  });

  testWidgets('category selector renders expected memory cards', (
    tester,
  ) async {
    await tester.pumpWidget(screen(_fixtureMemory()));
    await tester.pump();

    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmark 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Highlights'));
    await tester.pumpAndSettle();
    expect(find.text('Highlighted line'), findsOneWidget);

    await tester.tap(find.byTooltip('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Remember this'), findsOneWidget);

    await tester.tap(find.byTooltip('Words'));
    await tester.pumpAndSettle();
    expect(find.text('lucid'), findsOneWidget);

    await tester.tap(find.byTooltip('Characters'));
    await tester.pumpAndSettle();
    expect(find.text('Characters'), findsOneWidget);
    expect(find.text('Jane'), findsOneWidget);

    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Book Memory'), findsOneWidget);
    expect(find.byTooltip('New Book Note'), findsOneWidget);
    expect(find.text('New Book Note'), findsNothing);
  });
}

BookMemorySnapshot _fixtureMemory() {
  return BookMemorySnapshot.fromStorage(
    bookId: 'fixture.epub',
    metadata: null,
    bookmarks: [
      Bookmark(
        chunkIndex: 1,
        name: 'Bookmark 1',
        previewText: 'Bookmarked line',
        createdAt: DateTime(2026, 5, 1),
      ),
    ],
    highlights: [
      Highlight(
        id: 'h1',
        originalChunkIndex: 2,
        startOffset: 0,
        endOffset: 16,
        text: 'Highlighted line',
        createdAt: DateTime(2026, 5, 1),
      ),
      Highlight(
        id: 'n1',
        originalChunkIndex: 3,
        startOffset: 0,
        endOffset: 10,
        text: 'Noted line',
        note: 'Remember this',
        createdAt: DateTime(2026, 5, 1),
      ),
      Highlight(
        id: 'c1',
        originalChunkIndex: 4,
        startOffset: 0,
        endOffset: 4,
        text: 'Jane',
        type: HighlightType.character,
        createdAt: DateTime(2026, 5, 1),
      ),
    ],
    words: const [
      SavedWord(
        id: 'w1',
        word: 'lucid',
        meaning: 'Clear',
        bookId: 'fixture.epub',
        timestamp: 1777593600000,
        originalChunkIndex: 5,
      ),
    ],
    chapters: const [],
  );
}
