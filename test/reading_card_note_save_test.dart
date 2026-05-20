import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/widgets/note_sheets.dart';
import 'package:nalori/widgets/reading_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('unsaved note dismiss asks before discarding text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showNoteEditorSheet(
                    context,
                    title: 'Add note',
                    highlightedText: 'Selected text',
                    accentColor: Colors.amber,
                  );
                },
                child: const Text('Open note'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft note');
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Discard note?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(find.text('Draft note'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard note'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('view note popup closes outside but not inside', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showNotePreviewPopup(
                    context,
                    highlight: Highlight(
                      id: 'note-1',
                      originalChunkIndex: 0,
                      startOffset: 0,
                      endOffset: 13,
                      text: 'Selected text',
                      colorIndex: 0,
                      type: HighlightType.note,
                      note: 'Saved note',
                      createdAt: DateTime(2026),
                    ),
                  );
                },
                child: const Text('View note'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('View note'));
    await tester.pumpAndSettle();

    expect(find.text('Saved note'), findsOneWidget);

    await tester.tap(find.text('Saved note'));
    await tester.pumpAndSettle();

    expect(find.text('Saved note'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Saved note'), findsNothing);
  });

  testWidgets('reader note preview closes from outside tap', (tester) async {
    const text = 'Annotated note text.';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              height: 820,
              child: ReadingCard(
                chunk: const BookChunk(
                  index: 0,
                  type: BookChunkType.text,
                  text: text,
                ),
                settings: const ReadingSettings(),
                highlights: [
                  Highlight(
                    id: 'reader-note',
                    originalChunkIndex: 0,
                    startOffset: 0,
                    endOffset: text.length,
                    text: text,
                    colorIndex: 0,
                    type: HighlightType.note,
                    note: 'Reader saved note',
                    createdAt: DateTime(2026),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(find.byType(SelectableText).first));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Reader saved note'), findsOneWidget);

    await tester.tap(find.text('Reader saved note'));
    await tester.pumpAndSettle();

    expect(find.text('Reader saved note'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Reader saved note'), findsNothing);
  });

  testWidgets('long selected note text starts collapsed and can expand', (
    tester,
  ) async {
    final longSelection = List.filled(
      36,
      'A long selected sentence.',
    ).join(' ');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showNoteEditorSheet(
                    context,
                    title: 'Add note',
                    highlightedText: longSelection,
                    accentColor: Colors.amber,
                  );
                },
                child: const Text('Open long note'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open long note'));
    await tester.pumpAndSettle();

    expect(find.text('Show more'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();

    expect(find.text('Show more'), findsOneWidget);
  });

  testWidgets('Card Mode bookmark icon keeps assigned bookmark color', (
    tester,
  ) async {
    const bookmarkColorIndex = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: ReadingCard(
              chunk: const BookChunk(
                index: 0,
                type: BookChunkType.text,
                text: 'A bookmarked page should keep its chosen color.',
              ),
              settings: const ReadingSettings(enableCardDepth: true),
              bookmark: Bookmark(
                chunkIndex: 0,
                name: 'Bookmark',
                colorIndex: bookmarkColorIndex,
              ),
            ),
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.bookmark_rounded).first);
    expect(icon.color, kBookmarkColors[bookmarkColorIndex]);
  });

  testWidgets(
    'Save Note commits a highlight-backed note without tapping the checkmark',
    (tester) async {
      int? capturedStart;
      int? capturedEnd;
      String? capturedText;
      Color? capturedColor;
      HighlightType? capturedType;
      String? capturedNote;
      List<MappedTextRange>? capturedMappedRanges;
      bool legacyCallbackCalled = false;
      bool saveCompletedBeforeRouteFinished = false;
      bool saveCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 520,
                height: 820,
                child: ReadingCard(
                  chunk: const BookChunk(
                    index: 0,
                    type: BookChunkType.text,
                    text:
                        'This sentence exists so the test can select a word and save a note.',
                  ),
                  settings: const ReadingSettings(),
                  onMappedNoteCreated: (mappedRanges, text, color, note) async {
                    capturedMappedRanges = mappedRanges;
                    capturedText = text;
                    capturedColor = color;
                    capturedNote = note;
                    await Future<void>.delayed(Duration.zero);
                    saveCompleted = true;
                  },
                  onHighlightCreated: (start, end, text, color, type, note) {
                    legacyCallbackCalled = true;
                    capturedStart = start;
                    capturedEnd = end;
                    capturedText = text;
                    capturedColor = color;
                    capturedType = type;
                    capturedNote = note;
                  },
                  onNoteEditorRoute: <T>(action) async {
                    final result = await action();
                    saveCompletedBeforeRouteFinished = saveCompleted;
                    return result;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selectableText = find.byType(SelectableText).first;
      final selectionPoint =
          tester.getTopLeft(selectableText) + const Offset(80, 18);

      await tester.longPressAt(selectionPoint);
      await tester.pumpAndSettle();

      final addNoteButton = find.byIcon(Icons.edit_rounded);
      expect(addNoteButton, findsNothing);

      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(addNoteButton, findsOneWidget);
      expect(capturedType, isNull);

      await tester.tap(addNoteButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Remember this line');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Note'));
      await tester.pumpAndSettle();

      expect(capturedMappedRanges, isNotNull);
      expect(capturedMappedRanges, hasLength(1));
      expect(capturedMappedRanges!.single.originalChunkIndex, 0);
      expect(
        capturedMappedRanges!.single.originalEndOffset >
            capturedMappedRanges!.single.originalStartOffset,
        isTrue,
      );
      expect(capturedText, isNotEmpty);
      expect(capturedColor, isNotNull);
      expect(capturedNote, 'Remember this line');
      expect(saveCompletedBeforeRouteFinished, isTrue);
      expect(legacyCallbackCalled, isFalse);
      expect(capturedType, isNull);
      expect(capturedStart, isNull);
      expect(capturedEnd, isNull);
    },
  );

  testWidgets('selected text can be sent to the quote share callback', (
    tester,
  ) async {
    int? capturedStart;
    int? capturedEnd;
    String? capturedText;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              height: 820,
              child: ReadingCard(
                chunk: const BookChunk(
                  index: 0,
                  type: BookChunkType.text,
                  text: 'Share this sentence from Nalori.',
                ),
                settings: const ReadingSettings(),
                onQuoteShareRequested: (start, end, text) {
                  capturedStart = start;
                  capturedEnd = end;
                  capturedText = text;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectableText = find.byType(SelectableText).first;
    final selectionPoint =
        tester.getTopLeft(selectableText) + const Offset(80, 18);

    await tester.longPressAt(selectionPoint);
    await tester.pumpAndSettle();

    final shareButton = find.byIcon(Icons.ios_share_rounded);
    final moreButton = find.byIcon(Icons.more_horiz_rounded);
    expect(shareButton, findsNothing);
    expect(moreButton, findsNothing);

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(shareButton, findsNothing);
    expect(moreButton, findsOneWidget);

    await tester.tap(moreButton);
    await tester.pumpAndSettle();

    expect(find.text('Share'), findsOneWidget);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(capturedStart, isNotNull);
    expect(capturedEnd, isNotNull);
    expect(capturedEnd! > capturedStart!, isTrue);
    expect(capturedText, isNotEmpty);
  });
}
