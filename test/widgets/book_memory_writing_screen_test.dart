import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_memory_entry.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/book_memory_writing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('writing editor shows title first and source preview once', (
    tester,
  ) async {
    const passage = 'One highlighted passage to think about.';

    await tester.pumpWidget(
      MaterialApp(
        home: BookMemoryWritingScreen(
          bookFile: File('test.epub'),
          bookId: 'book.epub',
          settings: const ReadingSettings(),
          sourceType: BookMemorySourceType.highlight,
          sourceId: 'h1',
          sourcePreview: const BookMemorySourcePreview(
            sourceType: BookMemorySourceType.highlight,
            sourceId: 'h1',
            title: passage,
            subtitle: 'Chapter 1',
            body: passage,
            date: '2026-05-01',
            color: Color(0xFFFFD54F),
            originalChunkIndex: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Writing'), findsOneWidget);
    expect(find.text('Highlight'), findsOneWidget);
    expect(find.text(passage), findsOneWidget);
    expect(find.text('Not saved'), findsNothing);
    expect(find.byIcon(Icons.circle_outlined), findsOneWidget);

    final titleTop = tester.getTopLeft(find.byType(TextField).first).dy;
    final previewTop = tester.getTopLeft(find.text('Highlight')).dy;
    expect(titleTop, lessThan(previewTop));
  });

  testWidgets('free writing does not render an empty source card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookMemoryWritingScreen(
          bookFile: File('test.epub'),
          bookId: 'book.epub',
          settings: const ReadingSettings(),
          sourceType: BookMemorySourceType.free,
          sourcePreview: const BookMemorySourcePreview(
            sourceType: BookMemorySourceType.free,
            sourceId: null,
            title: 'Book title',
            subtitle: 'Book note',
            color: Color(0xFFFFA726),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Book title'), findsNothing);
    expect(find.text('Free Note'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
