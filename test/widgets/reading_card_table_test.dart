import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/reading_settings.dart';
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

    expect(find.byType(SelectableText), findsNWidgets(3));
    expect(_paragraphTopGapPaddings(tester, 0), hasLength(3));

    await _pumpReadingCard(
      tester,
      text,
      settings: const ReadingSettings(lineHeight: 1, paragraphSpacing: 1),
    );

    expect(find.byType(SelectableText), findsNWidgets(3));
    expect(_paragraphTopGapPaddings(tester, 0), hasLength(1));
    expect(_paragraphTopGapPaddings(tester, 18), hasLength(2));

    await _pumpReadingCard(
      tester,
      text,
      settings: const ReadingSettings(lineHeight: 1, paragraphSpacing: 2),
    );

    expect(find.byType(SelectableText), findsNWidgets(3));
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

    expect(find.byType(SelectableText), findsNWidgets(3));
    expect(_hasHighlightedText(tester, 'Second paragraph.'), isTrue);
    expect(_hasHighlightedText(tester, 'First paragraph.'), isFalse);
  });

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
          ),
        ),
      ),
    ),
  );
}

List<Padding> _paragraphPaddings(WidgetTester tester, double verticalPadding) {
  return tester
      .widgetList<Padding>(
        find.ancestor(
          of: find.byType(SelectableText),
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
          of: find.byType(SelectableText),
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
      .any((span) => span.text == text && span.style?.backgroundColor != null);
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
