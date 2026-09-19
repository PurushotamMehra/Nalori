import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/controllers/speed_read_controller.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/book_list_semantics.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/widgets/reading_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('list marker and body share a hanging-indent row', (
    tester,
  ) async {
    final chunk = _listChunk(text: 'List body text');
    await _pumpCard(tester, chunk);

    final marker = find.text('4.');
    final body = find.text('List body text');
    expect(marker, findsOneWidget);
    expect(body, findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.getTopLeft(marker).dy, tester.getTopLeft(body).dy);
    expect(
      tester.getTopLeft(body).dx,
      greaterThan(tester.getTopLeft(marker).dx),
    );
  });

  testWidgets('continuation preserves indent without repeating marker', (
    tester,
  ) async {
    final opening = _listChunk(
      text: 'Opening fragment',
      fragmentState: BookListFragmentState.opening,
    );
    await _pumpCard(tester, opening);
    final openingBodyX = tester.getTopLeft(find.text('Opening fragment')).dx;
    expect(find.text('4.'), findsOneWidget);

    final continuation = _listChunk(
      text: 'Continuation fragment',
      fragmentState: BookListFragmentState.continuation,
    );
    await _pumpCard(tester, continuation);
    final continuationBodyX = tester
        .getTopLeft(find.text('Continuation fragment'))
        .dx;

    expect(find.text('4.'), findsNothing);
    expect(continuationBodyX, openingBodyX);
  });

  testWidgets('nested list uses restrained additional indentation', (
    tester,
  ) async {
    const text = 'Outer\n\nInner';
    final outer = _semantics(itemId: 'outer', ordered: false);
    final inner = _semantics(
      listId: 'list-child',
      itemId: 'inner',
      parentListId: 'list',
      parentItemId: 'outer',
      depth: 1,
      ordered: false,
    );
    final chunk = BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: text,
      listDisplaySegments: [
        BookListDisplaySegment(
          displayStartOffset: 0,
          displayEndOffset: 5,
          semantics: outer,
          fragmentState: BookListFragmentState.complete,
        ),
        BookListDisplaySegment(
          displayStartOffset: 7,
          displayEndOffset: text.length,
          semantics: inner,
          fragmentState: BookListFragmentState.complete,
        ),
      ],
    );

    await _pumpCard(tester, chunk);

    expect(
      tester.getTopLeft(find.text('Inner')).dx -
          tester.getTopLeft(find.text('Outer')).dx,
      inInclusiveRange(10, 14),
    );
  });

  testWidgets('only list cards are top aligned', (tester) async {
    final list = _listChunk(text: 'Top aligned list');
    await _pumpCard(tester, list, active: false);
    final listTop = tester.getTopLeft(find.text('Top aligned list')).dy;

    const prose = BookChunk(
      index: 1,
      type: BookChunkType.text,
      text: 'Centered narrative prose',
    );
    await _pumpCard(tester, prose, active: false);
    final proseTop = tester
        .getTopLeft(find.text('Centered narrative prose'))
        .dy;

    expect(listTop, lessThan(160));
    expect(proseTop, greaterThan(listTop + 150));
  });

  testWidgets('active and preview list geometry is identical', (tester) async {
    final chunk = _listChunk(text: 'Stable geometry');
    await _pumpCard(tester, chunk);
    final activeMarker = tester.getRect(find.text('4.'));
    final activeBody = tester.getRect(find.text('Stable geometry'));

    await _pumpCard(tester, chunk, active: false);
    final previewMarker = tester.getRect(find.text('4.'));
    final previewBody = tester.getRect(find.text('Stable geometry'));

    expect(previewMarker, activeMarker);
    expect(previewBody, activeBody);
    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('highlights and notes address only item body offsets', (
    tester,
  ) async {
    final chunk = _listChunk(text: 'Ada reads');
    await _pumpCard(
      tester,
      chunk,
      highlights: [
        Highlight(
          id: 'body-highlight',
          originalChunkIndex: 0,
          startOffset: 0,
          endOffset: 3,
          text: 'Ada',
          createdAt: DateTime(2026, 8, 8),
        ),
        Highlight(
          id: 'body-note',
          originalChunkIndex: 0,
          startOffset: 4,
          endOffset: 9,
          text: 'reads',
          type: HighlightType.note,
          note: 'Body note',
          createdAt: DateTime(2026, 8, 8),
        ),
      ],
    );

    expect(_spanForText(tester, 'Ada').style?.backgroundColor, isNotNull);
    expect(_spanForText(tester, 'reads').style?.color, isNotNull);
    expect(find.text('4.'), findsOneWidget);
  });

  testWidgets('Speed Reader animates item body without consuming marker', (
    tester,
  ) async {
    const settings = ReadingSettings();
    final chunk = _listChunk(text: 'Ada reads');
    final controller = SpeedReadController()..start(chunk.text!, 0);
    controller.pause();

    await _pumpCard(tester, chunk, speedReadController: controller);

    expect(controller.tokens.map((token) => token.word), ['Ada', 'reads']);
    expect(find.text('4.'), findsOneWidget);
    expect(_spanForText(tester, 'Ada').style?.color, settings.readerTextColor);
    expect(
      _spanForText(tester, 'reads').style?.color,
      settings.speedReadInactiveWordColor,
    );

    controller.dispose();
  });
}

BookListSemantics _semantics({
  String listId = 'list',
  String itemId = 'item',
  String? parentListId,
  String? parentItemId,
  int depth = 0,
  bool ordered = true,
}) {
  return BookListSemantics(
    listId: listId,
    itemId: itemId,
    parentListId: parentListId,
    parentItemId: parentItemId,
    ordered: ordered,
    depth: depth,
    markerType: ordered
        ? BookListMarkerType.decimal
        : BookListMarkerType.unordered,
    resolvedOrdinal: ordered ? 4 : null,
    orderedStart: ordered ? 4 : null,
    blockIndex: 0,
    beginsItem: true,
    endsItem: true,
  );
}

BookChunk _listChunk({
  required String text,
  BookListFragmentState fragmentState = BookListFragmentState.complete,
}) {
  final semantics = _semantics();
  return BookChunk(
    index: 0,
    type: BookChunkType.text,
    text: text,
    logicalParagraphId: '${semantics.itemId}#block-0',
    logicalParagraphEndOffset: text.length,
    listSemantics: semantics,
    listDisplaySegments: [
      BookListDisplaySegment(
        displayStartOffset: 0,
        displayEndOffset: text.length,
        semantics: semantics,
        fragmentState: fragmentState,
      ),
    ],
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  BookChunk chunk, {
  bool active = true,
  List<Highlight> highlights = const [],
  SpeedReadController? speedReadController,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 720,
          child: ReadingCard(
            chunk: chunk,
            settings: const ReadingSettings(),
            highlights: highlights,
            isActivePage: active,
            speedReadController: speedReadController,
          ),
        ),
      ),
    ),
  );
}

TextSpan _spanForText(WidgetTester tester, String target) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final match = _flatten(richText.text).where((span) => span.text == target);
    if (match.isNotEmpty) return match.first;
  }
  throw TestFailure('No TextSpan found for "$target".');
}

Iterable<TextSpan> _flatten(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _flatten(child);
  }
}
