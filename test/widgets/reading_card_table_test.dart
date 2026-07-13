import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/utils/contrast_utils.dart';
import 'package:nalori/widgets/reader_table_block.dart';
import 'package:nalori/widgets/reading_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('ReadingCard renders detected table as table UI', (tester) async {
    const text = '''
Field | Description | Type
--- | --- | ---
latitude | Latitude of a given location | decimal
longitude | Longitude of a given location | decimal''';

    await _pumpReadingCard(tester, text);

    expect(find.byType(ReaderTableBlockWidget), findsOneWidget);
    expect(find.text('Field'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('latitude'), findsOneWidget);
    expect(find.text('---'), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(
      find.byKey(const ValueKey('reader-table-horizontal-scroll')),
      findsOneWidget,
    );
  });

  testWidgets('ReadingCard does not render wrapped raw header above table', (
    tester,
  ) async {
    const text = '''
API | Detail
--- | ---
GET /v1/businesses/{:id} | Return detailed information about a business''';

    await _pumpReadingCard(tester, text);

    expect(find.byType(ReaderTableBlockWidget), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('|'), findsNothing);
  });

  testWidgets('ReadingCard does not render box drawing delimiter column', (
    tester,
  ) async {
    const text = '''
API │ Detail
──── │ ───
GET /v1/businesses/{:id} │ Return detailed information about a business''';

    await _pumpReadingCard(tester, text);

    expect(find.byType(ReaderTableBlockWidget), findsOneWidget);
    expect(find.text('API'), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('│'), findsNothing);
  });

  testWidgets('ReadingCard consumes separated raw header preamble', (
    tester,
  ) async {
    const text = '''
API | Detail
---
---

GET /v1/businesses/{:id} | Return detailed information about a business
POST /v1/businesses | Add a business
PUT /v1/businesses/{:id} | Update details of a business''';

    await _pumpReadingCard(tester, text);

    expect(find.byType(ReaderTableBlockWidget), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('API'), findsOneWidget);
    expect(find.text('GET /v1/businesses/{:id}'), findsOneWidget);
  });

  testWidgets('ReadingCard consumes header paragraph before table body', (
    tester,
  ) async {
    const text = '''
API | Detail
__________________________ | ______________
--------------------------

GET /v1/businesses/{:id} | Return detailed information about a business
POST /v1/businesses | Add a business
PUT /v1/businesses/{:id} | Update details of a business''';

    await _pumpReadingCard(tester, text);

    expect(find.byType(ReaderTableBlockWidget), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('API'), findsOneWidget);
    expect(find.text('GET /v1/businesses/{:id}'), findsOneWidget);
  });

  testWidgets('ReadingCard keeps normal prose on selectable text path', (
    tester,
  ) async {
    const text = 'Normal prose should remain selectable and untabled.';

    await _pumpReadingCard(tester, text);

    expect(find.byType(ReaderTableBlockWidget), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text(text), findsOneWidget);
  });

  testWidgets('ReadingCard scales merged prose paragraph separators', (
    tester,
  ) async {
    const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';

    await _pumpReadingCard(
      tester,
      text,
      settings: const ReadingSettings(lineHeight: 1, paragraphSpacing: 0),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectionListener), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(_paragraphTopGapPaddings(tester, 0), hasLength(3));

    await _pumpReadingCard(
      tester,
      text,
      settings: const ReadingSettings(lineHeight: 1),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectionListener), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(_paragraphTopGapPaddings(tester, 0), hasLength(1));
    expect(_paragraphTopGapPaddings(tester, 18), hasLength(2));

    await _pumpReadingCard(
      tester,
      text,
      settings: const ReadingSettings(lineHeight: 1, paragraphSpacing: 2),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectionListener), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(_paragraphTopGapPaddings(tester, 0), hasLength(1));
    expect(_paragraphTopGapPaddings(tester, 36), hasLength(2));
  });

  testWidgets('ReadingCard does not add paragraph padding inside wrapped prose', (
    tester,
  ) async {
    final text = List.filled(
      80,
      'A long paragraph wraps across several visual lines without becoming multiple paragraph widgets.',
    ).join(' ');

    await _pumpReadingCard(tester, text);

    expect(find.byType(SelectableText), findsOneWidget);
    expect(_paragraphPaddings(tester, 4), isEmpty);
    expect(_paragraphTopGapPaddings(tester, 0), isEmpty);
  });

  testWidgets('ReadingCard keeps highlight offsets inside split paragraphs', (
    tester,
  ) async {
    const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';
    final start = text.indexOf('Second paragraph.');
    final end = start + 'Second paragraph.'.length;

    await _pumpReadingCard(
      tester,
      text,
      highlights: [
        Highlight(
          id: 'second',
          originalChunkIndex: 0,
          startOffset: start,
          endOffset: end,
          text: text.substring(start, end),
          createdAt: DateTime(2026, 5, 19),
        ),
      ],
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SelectionListener), findsOneWidget);
    expect(_hasHighlightedText(tester, 'Second paragraph.'), isTrue);
    expect(_hasHighlightedText(tester, 'First paragraph.'), isFalse);
  });

  testWidgets('ReadingCard redecorates existing text when highlights change', (
    tester,
  ) async {
    const text = 'Existing display text receives a highlight.';
    final start = text.indexOf('display text');
    final end = start + 'display text'.length;

    await _pumpReadingCard(tester, text);
    expect(_hasHighlightedText(tester, 'display text'), isFalse);

    await _pumpReadingCard(
      tester,
      text,
      highlights: [
        Highlight(
          id: 'new-highlight',
          originalChunkIndex: 0,
          startOffset: start,
          endOffset: end,
          text: text.substring(start, end),
          createdAt: DateTime(2026, 7, 12),
        ),
      ],
    );
    await tester.pump();

    expect(_hasHighlightedText(tester, 'display text'), isTrue);
  });

  testWidgets('ReadingCard does not color an unrelated same-length range', (
    tester,
  ) async {
    const text = 'McNeish watches, and waits.';
    const color = Color(0xFF00897B);

    await _pumpReadingCard(
      tester,
      text,
      highlights: [
        Highlight(
          id: 'mcneish',
          originalChunkIndex: 0,
          startOffset: 0,
          endOffset: 7,
          text: 'McNeish',
          colorValue: color.toARGB32(),
          type: HighlightType.character,
          createdAt: DateTime(2026, 7, 12),
        ),
      ],
      characterNames: const {'McNeish': color},
    );

    expect(_spanForText(tester, 'McNeish').style?.color, color);
    final unrelated = _allTextSpans(
      tester,
    ).firstWhere((span) => span.text?.contains('es, and') == true);
    expect(unrelated.style?.color, isNot(color));
  });

  testWidgets('ReadingCard paints note blocks inside split paragraphs', (
    tester,
  ) async {
    const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';
    const settings = ReadingSettings();
    final start = text.indexOf('Second paragraph.');
    final end = start + 'Second paragraph.'.length;

    await _pumpReadingCard(
      tester,
      text,
      highlights: [
        Highlight(
          id: 'second-note',
          originalChunkIndex: 0,
          startOffset: start,
          endOffset: end,
          text: text.substring(start, end),
          type: HighlightType.note,
          note: 'Important',
          createdAt: DateTime(2026, 5, 19),
        ),
      ],
    );

    final span = _spanForText(tester, 'Second paragraph.');

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(span.style?.backgroundColor, isNull);
    expect(
      span.style?.color,
      _expectedNoteForeground(settings, kHighlightColors.first),
    );
    expect(_hasNoteHighlightPainter(tester), isTrue);
  });

  testWidgets('ReadingCard gives dark notes a readable foreground', (
    tester,
  ) async {
    const text = 'Blue note highlight uses contrast text color.';
    const noteColor = Color(0xFF0D47A1);
    const settings = ReadingSettings();

    await _pumpReadingCard(
      tester,
      text,
      highlights: [
        Highlight(
          id: 'blue-note',
          originalChunkIndex: 0,
          startOffset: 0,
          endOffset: text.length,
          text: text,
          colorValue: noteColor.toARGB32(),
          type: HighlightType.note,
          note: 'Important',
          createdAt: DateTime(2026, 5, 19),
        ),
      ],
    );

    final span = _spanForText(tester, text);

    expect(span.style?.backgroundColor, isNull);
    expect(span.style?.color, _expectedNoteForeground(settings, noteColor));
    expect(_hasNoteHighlightPainter(tester), isTrue);
  });

  testWidgets('ReadingCard gives yellow notes dark foreground in dark mode', (
    tester,
  ) async {
    const text = 'Yellow note highlight uses dark contrast text.';
    const noteColor = Color(0xFFFFD54F);
    const settings = ReadingSettings(appTheme: AppTheme.dark);

    await _pumpReadingCard(
      tester,
      text,
      settings: settings,
      highlights: [
        Highlight(
          id: 'yellow-note',
          originalChunkIndex: 0,
          startOffset: 0,
          endOffset: text.length,
          text: text,
          colorValue: noteColor.toARGB32(),
          type: HighlightType.note,
          note: 'Important',
          createdAt: DateTime(2026, 5, 19),
        ),
      ],
    );

    final span = _spanForText(tester, text);

    expect(span.style?.backgroundColor, isNull);
    expect(span.style?.color, _expectedNoteForeground(settings, noteColor));
    expect(span.style!.color!.computeLuminance(), lessThan(0.5));
    expect(_hasNoteHighlightPainter(tester), isTrue);
  });

  testWidgets(
    'ReadingCard treats regular highlights with notes as note blocks',
    (tester) async {
      const text = 'Attached note highlight keeps reader text color.';
      const noteColor = Color(0xFF4A148C);
      const settings = ReadingSettings();

      await _pumpReadingCard(
        tester,
        text,
        highlights: [
          Highlight(
            id: 'attached-note',
            originalChunkIndex: 0,
            startOffset: 0,
            endOffset: text.length,
            text: text,
            colorValue: noteColor.toARGB32(),
            note: 'Attached note',
            createdAt: DateTime(2026, 5, 19),
          ),
        ],
      );

      final span = _spanForText(tester, text);

      expect(span.style?.backgroundColor, isNull);
      expect(span.style?.color, _expectedNoteForeground(settings, noteColor));
      expect(_hasNoteHighlightPainter(tester), isTrue);
    },
  );

  testWidgets('ReadingCard keeps regular highlight foreground unchanged', (
    tester,
  ) async {
    const text = 'Regular highlight stays lightweight.';
    const highlightColor = Color(0xFF0D47A1);
    const settings = ReadingSettings();

    await _pumpReadingCard(
      tester,
      text,
      highlights: [
        Highlight(
          id: 'regular-blue',
          originalChunkIndex: 0,
          startOffset: 0,
          endOffset: text.length,
          text: text,
          colorValue: highlightColor.toARGB32(),
          createdAt: DateTime(2026, 5, 19),
        ),
      ],
    );

    final span = _spanForText(tester, text);

    expect(span.style?.backgroundColor, highlightColor.withValues(alpha: 0.3));
    expect(span.style?.color, settings.readerTextColor);
  });

  testWidgets('ReadingCard toggles reader controls when split text is tapped', (
    tester,
  ) async {
    const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';
    var tapCount = 0;

    await _pumpReadingCard(
      tester,
      text,
      onTapOutside: (_) {
        tapCount++;
      },
    );

    await tester.tap(_richTextWithPlainText('Second paragraph.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tapCount, 1);
  });

  testWidgets(
    'ReadingCard does not toggle reader controls on split text long press',
    (tester) async {
      const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';
      var tapCount = 0;

      await _pumpReadingCard(
        tester,
        text,
        onTapOutside: (_) {
          tapCount++;
        },
      );

      await tester.longPress(_richTextWithPlainText('Second paragraph.'));
      await tester.pumpAndSettle();

      expect(tapCount, 0);
    },
  );

  testWidgets(
    'ReadingCard does not wrap inactive split paragraphs in selection area',
    (tester) async {
      const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';

      await _pumpReadingCard(tester, text, isActivePage: false);

      expect(find.byType(SelectionArea), findsNothing);
      expect(find.byType(SelectionListener), findsNothing);
      expect(find.byType(RichText), findsWidgets);
    },
  );

  testWidgets('ReadingCard keeps default paragraph block spacing unchanged', (
    tester,
  ) async {
    await _pumpReadingCard(tester, _paragraphTableParagraphText);

    expect(find.byType(ReaderTableBlockWidget), findsOneWidget);
    expect(_paragraphPaddings(tester, 4), hasLength(2));
  });

  testWidgets('ReadingCard scales only final paragraph block spacing', (
    tester,
  ) async {
    await _pumpReadingCard(
      tester,
      _paragraphTableParagraphText,
      settings: const ReadingSettings(paragraphSpacing: 0),
    );

    expect(_paragraphPaddings(tester, 0), hasLength(2));
    expect(_paragraphPaddings(tester, 4), isEmpty);

    await _pumpReadingCard(
      tester,
      _paragraphTableParagraphText,
      settings: const ReadingSettings(paragraphSpacing: 2),
    );

    expect(_paragraphPaddings(tester, 8), hasLength(2));
    expect(_paragraphPaddings(tester, 4), isEmpty);
  });

  testWidgets('ReadingCard uses preformatted fallback for broken table text', (
    tester,
  ) async {
    const text = '''
Field | Description
--- --- ---
latitude only''';

    await _pumpReadingCard(tester, text);

    expect(find.byType(ReaderPreformattedBlockWidget), findsOneWidget);
    expect(find.byType(ReaderTableBlockWidget), findsNothing);
  });
}

const _paragraphTableParagraphText = '''
First paragraph before the table.

Field | Description
--- | ---
latitude | Latitude of a given location

Second paragraph after the table.''';

Future<void> _pumpReadingCard(
  WidgetTester tester,
  String text, {
  ReadingSettings settings = const ReadingSettings(),
  List<Highlight> highlights = const [],
  Map<String, Color> characterNames = const {},
  bool isActivePage = true,
  void Function(Offset? globalPosition)? onTapOutside,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 720,
          child: ReadingCard(
            chunk: BookChunk(index: 0, type: BookChunkType.text, text: text),
            settings: settings,
            highlights: highlights,
            characterNames: characterNames,
            isActivePage: isActivePage,
            onTapOutside: onTapOutside,
          ),
        ),
      ),
    ),
  );
}

Iterable<TextSpan> _allTextSpans(WidgetTester tester) {
  return tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .expand((widget) sync* {
        final span = widget.textSpan;
        if (span != null) yield* _flattenTextSpans(span);
      })
      .followedBy(
        tester.widgetList<Text>(find.byType(Text)).expand((widget) sync* {
          final span = widget.textSpan;
          if (span != null) yield* _flattenTextSpans(span);
        }),
      );
}

List<Padding> _paragraphPaddings(WidgetTester tester, double verticalPadding) {
  return tester
      .widgetList<Padding>(
        find.ancestor(
          of: _readerSelectableTextContent(),
          matching: find.byType(Padding),
        ),
      )
      .where((padding) {
        final insets = padding.padding;
        return insets is EdgeInsets &&
            padding.child is Listener &&
            insets.top == verticalPadding &&
            insets.bottom == verticalPadding &&
            insets.left == 0 &&
            insets.right == 0;
      })
      .toList();
}

List<Padding> _paragraphTopGapPaddings(WidgetTester tester, double topPadding) {
  return tester
      .widgetList<Padding>(
        find.ancestor(
          of: _readerSelectableTextContent(),
          matching: find.byType(Padding),
        ),
      )
      .where((padding) {
        final insets = padding.padding;
        return insets is EdgeInsets &&
            padding.child is Listener &&
            insets.top == topPadding &&
            insets.bottom == 0 &&
            insets.left == 0 &&
            insets.right == 0;
      })
      .toList();
}

bool _hasHighlightedText(WidgetTester tester, String text) {
  return tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .expand((widget) sync* {
        final span = widget.textSpan;
        if (span != null) yield* _flattenTextSpans(span);
      })
      .followedBy(
        tester.widgetList<Text>(find.byType(Text)).expand((widget) sync* {
          final span = widget.textSpan;
          if (span != null) yield* _flattenTextSpans(span);
        }),
      )
      .any((span) => span.text == text && span.style?.backgroundColor != null);
}

TextSpan _spanForText(WidgetTester tester, String text) {
  return tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .expand((widget) sync* {
        final span = widget.textSpan;
        if (span != null) yield* _flattenTextSpans(span);
      })
      .followedBy(
        tester.widgetList<Text>(find.byType(Text)).expand((widget) sync* {
          final span = widget.textSpan;
          if (span != null) yield* _flattenTextSpans(span);
        }),
      )
      .firstWhere((span) => span.text == text);
}

bool _hasNoteHighlightPainter(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .any(
        (widget) =>
            widget.painter?.runtimeType.toString() == '_NoteHighlightPainter',
      );
}

Color _expectedNoteForeground(ReadingSettings settings, Color noteColor) {
  final paintedColor = noteColor.withValues(
    alpha: settings.isDark ? 0.80 : 0.56,
  );
  return readableForegroundForBackground(
    compositeColorOver(paintedColor, settings.backgroundColor),
  );
}

Finder _readerSelectableTextContent() {
  return find.byWidgetPredicate(
    (widget) => widget is SelectableText || widget is Text,
  );
}

Finder _richTextWithPlainText(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && widget.textSpan?.toPlainText() == text,
  );
}

Iterable<TextSpan> _flattenTextSpans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    final children = span.children;
    if (children == null) return;
    for (final child in children) {
      yield* _flattenTextSpans(child);
    }
  }
}
