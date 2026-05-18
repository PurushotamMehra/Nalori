import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_memory_entry.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/book_memory_source_detail_screen.dart';
import 'package:nalori/screens/book_memory_writing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('highlight detail shows passage once with bottom actions', (
    tester,
  ) async {
    const passage = 'A single highlighted passage';

    await tester.pumpWidget(
      MaterialApp(
        home: BookMemorySourceDetailScreen(
          bookFile: File('test.epub'),
          bookId: 'book.epub',
          settings: const ReadingSettings(),
          preview: const BookMemorySourcePreview(
            sourceType: BookMemorySourceType.highlight,
            sourceId: 'h1',
            title: passage,
            subtitle: 'Chapter 1 • Page/Chunk 2',
            body: passage,
            date: '2026-05-01',
            color: Color(0xFFFFD54F),
            originalChunkIndex: 1,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Highlight'), findsOneWidget);
    expect(find.byTooltip('Write about this'), findsNothing);
    expect(find.text(passage), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.text('Go to Text'), findsOneWidget);
    expect(find.text('Write'), findsOneWidget);
  });

  testWidgets('reader note separates source text from user note', (
    tester,
  ) async {
    const sourceText = 'Go into your room and wait there.';
    const noteText = 'This changes the scene.';

    await tester.pumpWidget(
      MaterialApp(
        home: BookMemorySourceDetailScreen(
          bookFile: File('test.epub'),
          bookId: 'book.epub',
          settings: const ReadingSettings(),
          preview: const BookMemorySourcePreview(
            sourceType: BookMemorySourceType.note,
            sourceId: 'n1',
            title: noteText,
            subtitle: 'Chapter 1 • Page/Chunk 28',
            body: sourceText,
            date: '2026-05-12',
            color: Color(0xFFFF8A65),
            originalChunkIndex: 27,
            details: ['Selected text: $sourceText'],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Reader Note'), findsOneWidget);
    expect(find.byTooltip('Write about this'), findsNothing);
    expect(find.text(sourceText), findsOneWidget);
    expect(find.text('Your note'), findsOneWidget);
    expect(find.text(noteText), findsOneWidget);
    expect(find.text('Selected text: $sourceText'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('character detail shows first mark and marked moments', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookMemorySourceDetailScreen(
          bookFile: File('test.epub'),
          bookId: 'book.epub',
          settings: const ReadingSettings(),
          preview: const BookMemorySourcePreview(
            sourceType: BookMemorySourceType.character,
            sourceId: 'jane',
            title: 'Jane',
            subtitle: '2 marked moments',
            body: 'First marked: Chapter 1 • Page/Chunk 2',
            date: '2026-05-03',
            color: Color(0xFFFFD54F),
            originalChunkIndex: 1,
            details: [
              'Occurrences',
              'First occurrence: Found earlier',
              'Marked occurrences',
              'Chapter 1 • Page/Chunk 2: Jane',
              'Last occurrence: Found later in the book',
              'Linked highlights and notes',
              'Chapter 1 • Page/Chunk 2: Jane',
              'Chapter 3 • Page/Chunk 8: Jane',
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Character'), findsOneWidget);
    expect(find.text('Jane'), findsWidgets);
    expect(find.text('2 marked moments • 2026-05-03'), findsOneWidget);
    expect(find.text('Occurrences'), findsOneWidget);
    expect(find.text('First occurrence'), findsOneWidget);
    expect(find.text('Found earlier'), findsOneWidget);
    expect(find.text('Marked occurrences'), findsOneWidget);
    expect(find.text('Linked highlights and notes'), findsOneWidget);
    expect(find.text('Chapter 3 • Page/Chunk 8'), findsOneWidget);
    expect(find.text('Jane'), findsWidgets);
  });

  testWidgets('character detail limits long snippets and can expand them', (
    tester,
  ) async {
    final longSnippet = List.filled(30, 'Elizabeth').join(' ');

    await tester.pumpWidget(
      MaterialApp(
        home: BookMemorySourceDetailScreen(
          bookFile: File('test.epub'),
          bookId: 'book.epub',
          settings: const ReadingSettings(),
          preview: BookMemorySourcePreview(
            sourceType: BookMemorySourceType.character,
            sourceId: 'elizabeth-bennet',
            title: 'Elizabeth Bennet',
            subtitle: '1 marked moment',
            body: 'First marked: Chapter 2 • Page/Chunk 6',
            date: '2026-05-03',
            color: const Color(0xFFEF5350),
            originalChunkIndex: 5,
            details: [
              'Linked highlights and notes',
              'Highlight - Chapter 4 • Page/Chunk 12: $longSnippet',
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(longSnippet), findsNothing);
    expect(find.text('Show more'), findsOneWidget);

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    expect(find.text(longSnippet), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();

    expect(find.text(longSnippet), findsNothing);
    expect(find.text('Show more'), findsOneWidget);
  });

  testWidgets('character detail hides and reveals spoiler occurrence rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookMemorySourceDetailScreen(
          bookFile: File('test.epub'),
          bookId: 'book.epub',
          settings: const ReadingSettings(),
          preview: const BookMemorySourcePreview(
            sourceType: BookMemorySourceType.character,
            sourceId: 'jane',
            title: 'Jane',
            subtitle: '1 marked moment',
            body: 'First marked: Chapter 1 • Page/Chunk 2',
            date: '2026-05-03',
            color: Color(0xFFFFD54F),
            originalChunkIndex: 1,
            detailItems: [
              BookMemoryDetailItem(
                section: 'Occurrences',
                label: 'Last occurrence',
                text: 'Chapter 20 • Page/Chunk 240',
                originalChunkIndex: 239,
                originalStartOffset: 12,
                spoilerProtected: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Hidden to avoid spoilers'), findsOneWidget);
    expect(find.text('Chapter 20 • Page/Chunk 240'), findsNothing);
    expect(find.text('Go to Text'), findsOneWidget); // bottom action only
    expect(find.text('Go to text'), findsNothing);
    expect(find.byTooltip('Unhide'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byTooltip('Unhide'));
    await tester.pumpAndSettle();

    expect(find.text('Chapter 20 • Page/Chunk 240'), findsOneWidget);
    expect(find.byTooltip('Hide'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byTooltip('Go to text'), findsOneWidget);
    expect(find.text('Go to text'), findsNothing);

    await tester.tap(find.byTooltip('Hide'));
    await tester.pumpAndSettle();

    expect(find.text('Hidden to avoid spoilers'), findsOneWidget);
    expect(find.text('Chapter 20 • Page/Chunk 240'), findsNothing);
  });

  testWidgets('linked highlight row can open its memory detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookMemorySourceDetailScreen(
          bookFile: File('test.epub'),
          bookId: 'book.epub',
          settings: const ReadingSettings(),
          preview: const BookMemorySourcePreview(
            sourceType: BookMemorySourceType.character,
            sourceId: 'jane',
            title: 'Jane',
            subtitle: '1 marked moment',
            color: Color(0xFFFFD54F),
            originalChunkIndex: 1,
            detailItems: [
              BookMemoryDetailItem(
                section: 'Linked highlights',
                label: 'Chapter 3 • Page/Chunk 8',
                text: 'Jane crossed the garden.',
                originalChunkIndex: 7,
                originalStartOffset: 4,
                sourcePreview: BookMemorySourcePreview(
                  sourceType: BookMemorySourceType.highlight,
                  sourceId: 'h1',
                  title: 'Jane crossed the garden.',
                  subtitle: 'Chapter 3 • Page/Chunk 8',
                  body: 'Jane crossed the garden.',
                  date: '2026-05-03',
                  color: Color(0xFFFFD54F),
                  originalChunkIndex: 7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Open memory'), findsOneWidget);
    await tester.tap(find.text('Open memory'));
    await tester.pumpAndSettle();

    expect(find.text('Highlight'), findsOneWidget);
    expect(find.text('Jane crossed the garden.'), findsOneWidget);
    expect(find.text('Chapter 3 • Page/Chunk 8 • 2026-05-03'), findsOneWidget);
  });
}
