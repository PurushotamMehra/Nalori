import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/book_chunk.dart';
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

Future<void> _pumpReadingCard(WidgetTester tester, String text) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 720,
          child: ReadingCard(
            chunk: BookChunk(index: 0, type: BookChunkType.text, text: text),
            settings: const ReadingSettings(),
          ),
        ),
      ),
    ),
  );
}
