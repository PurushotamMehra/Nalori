import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/controllers/speed_read_controller.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/widgets/reading_card.dart';
import 'package:nalori/widgets/speed_read_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Speed Read dims inactive words and highlights active word', (
    tester,
  ) async {
    const text = 'Alpha beta.';
    const settings = ReadingSettings();
    final controller = SpeedReadController()..start(text, 0);

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
                text: text,
              ),
              settings: settings,
              speedReadController: controller,
            ),
          ),
        ),
      ),
    );

    final speedReadSpans = _flattenSelectableTextSpans(tester);
    expect(
      _spanForText(speedReadSpans, 'Alpha').style?.color,
      settings.readerTextColor,
    );
    expect(
      _spanForText(speedReadSpans, 'beta.').style?.color,
      settings.speedReadInactiveWordColor,
    );

    controller.jumpToWord(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final transitioningSpans = _flattenSelectableTextSpans(tester);
    expect(
      _spanForText(transitioningSpans, 'Alpha').style?.color,
      isNot(settings.readerTextColor),
    );
    expect(
      _spanForText(transitioningSpans, 'Alpha').style?.color,
      isNot(settings.speedReadInactiveWordColor),
    );
    expect(
      _spanForText(transitioningSpans, 'beta.').style?.color,
      isNot(settings.readerTextColor),
    );
    expect(
      _spanForText(transitioningSpans, 'beta.').style?.color,
      isNot(settings.speedReadInactiveWordColor),
    );

    await tester.pump(const Duration(milliseconds: 140));

    final advancedSpans = _flattenSelectableTextSpans(tester);
    expect(
      _spanForText(advancedSpans, 'Alpha').style?.color,
      settings.speedReadInactiveWordColor,
    );
    expect(
      _spanForText(advancedSpans, 'beta.').style?.color,
      settings.readerTextColor,
    );

    controller.stop();
    await tester.pump();

    final normalSpans = _flattenSelectableTextSpans(tester);
    expect(
      _spanForText(normalSpans, text).style?.color,
      settings.readerTextColor,
    );

    controller.dispose();
  });

  testWidgets('Speed Read window mode renders the moving guide overlay', (
    tester,
  ) async {
    const text = 'Alpha beta.';
    final controller = SpeedReadController()..start(text, 0);

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
                text: text,
              ),
              settings: const ReadingSettings(
                speedReadDisplayMode: SpeedReadDisplayMode.window,
              ),
              speedReadController: controller,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SpeedReadOverlay), findsOneWidget);
    final spans = _flattenSelectableTextSpans(tester);
    expect(_spanForText(spans, 'Alpha').style?.color, isNotNull);
    expect(_spanForText(spans, 'beta.').style?.color, isNotNull);

    controller.dispose();
  });

  testWidgets('Speed Read lyrics mode keeps character colors only', (
    tester,
  ) async {
    const text = 'Alice met Bob.';
    const characterColor = Color(0xFF81C784);
    const regularHighlightColor = Color(0xFFFFD54F);
    const settings = ReadingSettings();
    final controller = SpeedReadController()..start(text, 0);
    controller.pause();

    await _pumpSpeedReadCard(
      tester,
      text,
      controller,
      highlights: [
        _highlight(
          id: 'alice-character',
          startOffset: 0,
          endOffset: 5,
          text: 'Alice',
          color: characterColor,
          type: HighlightType.character,
        ),
        _highlight(
          id: 'bob-highlight',
          startOffset: 10,
          endOffset: 13,
          text: 'Bob',
          color: regularHighlightColor,
        ),
      ],
    );

    final spans = _flattenSelectableTextSpans(tester);
    expect(
      _spanForText(spans, 'Alice').style?.color,
      Color.lerp(characterColor, settings.readerTextColor, 0.4),
    );
    expect(_spanForText(spans, 'Alice').style?.backgroundColor, isNull);
    expect(_spanForText(spans, 'Bob.').style?.backgroundColor, isNull);

    controller.dispose();
  });

  testWidgets(
    'Speed Read window mode keeps character colors without highlights',
    (tester) async {
      const text = 'Alice met Bob.';
      const characterColor = Color(0xFF81C784);
      const noteColor = Color(0xFFCE93D8);
      const settings = ReadingSettings(
        speedReadDisplayMode: SpeedReadDisplayMode.window,
      );
      final controller = SpeedReadController()..start(text, 0);
      controller.pause();

      await _pumpSpeedReadCard(
        tester,
        text,
        controller,
        settings: settings,
        highlights: [
          _highlight(
            id: 'alice-character',
            startOffset: 0,
            endOffset: 5,
            text: 'Alice',
            color: characterColor,
            type: HighlightType.character,
          ),
          _highlight(
            id: 'bob-note',
            startOffset: 10,
            endOffset: 13,
            text: 'Bob',
            color: noteColor,
            type: HighlightType.note,
            note: 'Important',
          ),
        ],
      );

      expect(find.byType(SpeedReadOverlay), findsOneWidget);
      final spans = _flattenSelectableTextSpans(tester);
      expect(
        _spanForText(spans, 'Alice').style?.color,
        Color.lerp(characterColor, settings.readerTextColor, 0.4),
      );
      expect(_spanForText(spans, 'Alice').style?.backgroundColor, isNull);
      expect(_spanForText(spans, 'Bob.').style?.backgroundColor, isNull);

      controller.dispose();
    },
  );

  testWidgets(
    'tapping text while Speed Read is paused jumps and stays paused',
    (tester) async {
      const text = 'Alpha beta gamma.';
      final controller = SpeedReadController()..start(text, 0);
      controller.pause();
      controller.jumpToWord(2);

      await _pumpSpeedReadCard(tester, text, controller);

      await _tapToken(tester, startOffset: 6, endOffset: 10);
      await tester.pump();

      expect(controller.currentWordIndex, 1);
      expect(controller.isPaused, isTrue);

      controller.dispose();
    },
  );

  testWidgets('tapping text while Speed Read window mode jumps to the word', (
    tester,
  ) async {
    const text = 'Alpha beta gamma.';
    final controller = SpeedReadController()..start(text, 0);
    controller.pause();

    await _pumpSpeedReadCard(
      tester,
      text,
      controller,
      settings: const ReadingSettings(
        speedReadDisplayMode: SpeedReadDisplayMode.window,
      ),
    );

    await _tapToken(tester, startOffset: 11, endOffset: 17);
    await tester.pump();

    expect(controller.currentWordIndex, 2);
    expect(controller.isPaused, isTrue);

    controller.dispose();
  });

  testWidgets('tapping text blank space does not jump to the final word', (
    tester,
  ) async {
    const text = 'Alpha beta.\n\n\n';
    final controller = SpeedReadController()..start(text, 0);
    controller.pause();

    await _pumpSpeedReadCard(tester, text, controller);

    final box = _selectableTextBox(tester);
    await tester.tapAt(box.localToGlobal(Offset(box.size.width - 2, 2)));
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.currentWordIndex, 0);

    controller.dispose();
  });
}

Future<void> _pumpSpeedReadCard(
  WidgetTester tester,
  String text,
  SpeedReadController controller, {
  ReadingSettings settings = const ReadingSettings(),
  List<Highlight> highlights = const [],
  Map<String, Color> characterNames = const {},
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 720,
          child: ReadingCard(
            chunk: BookChunk(index: 0, type: BookChunkType.text, text: text),
            settings: settings,
            speedReadController: controller,
            highlights: highlights,
            characterNames: characterNames,
          ),
        ),
      ),
    ),
  );
}

Highlight _highlight({
  required String id,
  required int startOffset,
  required int endOffset,
  required String text,
  required Color color,
  HighlightType type = HighlightType.highlight,
  String? note,
}) {
  return Highlight(
    id: id,
    originalChunkIndex: 0,
    startOffset: startOffset,
    endOffset: endOffset,
    text: text,
    colorValue: color.toARGB32(),
    type: type,
    createdAt: DateTime(2026),
    note: note,
  );
}

Future<void> _tapToken(
  WidgetTester tester, {
  required int startOffset,
  required int endOffset,
}) async {
  final selectableText = tester.widget<SelectableText>(
    find.byType(SelectableText).first,
  );
  final textPainter = TextPainter(
    text: selectableText.textSpan,
    textDirection: TextDirection.ltr,
    textAlign: selectableText.textAlign ?? TextAlign.start,
    strutStyle: selectableText.strutStyle,
  );
  final box = _selectableTextBox(tester);
  textPainter.layout(maxWidth: box.size.width);
  final boxes = textPainter.getBoxesForSelection(
    TextSelection(baseOffset: startOffset, extentOffset: endOffset),
  );
  expect(boxes, isNotEmpty);

  await tester.tapAt(box.localToGlobal(boxes.first.toRect().center));
  await tester.pump(const Duration(milliseconds: 50));
}

RenderBox _selectableTextBox(WidgetTester tester) {
  final element = tester.element(find.byType(SelectableText).first);
  final renderObject = element.findRenderObject();
  expect(renderObject, isA<RenderBox>());
  return renderObject! as RenderBox;
}

List<TextSpan> _flattenSelectableTextSpans(WidgetTester tester) {
  final selectableText = tester.widget<SelectableText>(
    find.byType(SelectableText).first,
  );
  final root = selectableText.textSpan;
  expect(root, isNotNull);
  return _flattenTextSpan(root!).toList();
}

Iterable<TextSpan> _flattenTextSpan(InlineSpan span) sync* {
  if (span is TextSpan) {
    if (span.text != null && span.text!.isNotEmpty) {
      yield span;
    }
    final children = span.children;
    if (children != null) {
      for (final child in children) {
        yield* _flattenTextSpan(child);
      }
    }
  }
}

TextSpan _spanForText(List<TextSpan> spans, String text) {
  return spans.firstWhere((span) => span.text == text);
}
