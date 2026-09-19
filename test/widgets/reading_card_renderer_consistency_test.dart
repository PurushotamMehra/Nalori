import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/controllers/speed_read_controller.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/widgets/reading_card.dart';
import 'package:nalori/widgets/reading_card_deck.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'Card Mode keeps the same paragraph layout and source identity through forward and backward commits',
    (tester) async {
      final deckController = ReadingCardDeckController();
      final speedReadController = SpeedReadController();
      final chunks = _testChunks();
      var currentIndex = 0;

      await tester.pumpWidget(
        _buildDeckHarness(
          chunks: chunks,
          deckController: deckController,
          speedReadController: speedReadController,
          onIndexChanged: (index) => currentIndex = index,
        ),
      );

      final originalActive = _paragraphSnapshot(tester, chunks[0]);
      final incomingAtRest = _paragraphSnapshot(tester, chunks[1]);
      _expectCardIdentity(tester, chunks[1], isActive: false);
      _expectPreviewIsNonInteractive(tester, chunks[1]);
      expect(_cardWidget(tester, chunks[1]).speedReadController, isNull);

      expect(
        deckController.animateToIndex(
          1,
          const Duration(milliseconds: 400),
          Curves.linear,
        ),
        isTrue,
      );

      for (var progress = 25; progress <= 75; progress += 25) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(currentIndex, 0, reason: 'transition committed at $progress%');
        _expectSameParagraphLayout(
          incomingAtRest,
          _paragraphSnapshot(tester, chunks[1]),
          reason: 'forward transition at $progress%',
        );
        _expectCardIdentity(tester, chunks[1], isActive: false);
      }

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(currentIndex, 1);
      final incomingCommitted = _paragraphSnapshot(tester, chunks[1]);
      _expectSameParagraphLayout(
        incomingAtRest,
        incomingCommitted,
        reason: 'forward transition commit',
      );
      _expectCardIdentity(tester, chunks[1], isActive: true);
      expect(
        _cardWidget(tester, chunks[1]).speedReadController,
        same(speedReadController),
      );

      expect(
        deckController.animateToIndex(
          0,
          const Duration(milliseconds: 400),
          Curves.linear,
        ),
        isTrue,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      _expectSameParagraphLayout(
        originalActive,
        _paragraphSnapshot(tester, chunks[0]),
        reason: 'backward transition preview at 25%',
      );
      _expectCardIdentity(tester, chunks[0], isActive: false);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(currentIndex, 0);
      _expectSameParagraphLayout(
        originalActive,
        _paragraphSnapshot(tester, chunks[0]),
        reason: 'backward transition commit',
      );
      _expectCardIdentity(tester, chunks[0], isActive: true);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ReadingCardDeck)),
      );
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      _expectSameParagraphLayout(
        incomingAtRest,
        _paragraphSnapshot(tester, chunks[1]),
        reason: 'interrupted forward transition',
      );
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(currentIndex, 0);
      _expectSameParagraphLayout(
        originalActive,
        _paragraphSnapshot(tester, chunks[0]),
        reason: 'cancelled transition settles on the original card',
      );

      speedReadController.dispose();
    },
  );

  testWidgets(
    'only the committed card adds selection while preserving the paragraph renderer',
    (tester) async {
      final deckController = ReadingCardDeckController();
      final speedReadController = SpeedReadController();
      final chunks = _testChunks();

      await tester.pumpWidget(
        _buildDeckHarness(
          chunks: chunks,
          deckController: deckController,
          speedReadController: speedReadController,
        ),
      );

      final previewParagraph = _paragraphTextFinder(chunks[1]);
      expect(
        find.ancestor(
          of: previewParagraph,
          matching: find.byType(SelectionArea),
        ),
        findsNothing,
      );
      _expectPreviewIsNonInteractive(tester, chunks[1]);

      expect(
        deckController.animateToIndex(
          1,
          const Duration(milliseconds: 200),
          Curves.linear,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();

      final activeParagraph = _paragraphTextFinder(chunks[1]);
      expect(
        find.ancestor(
          of: activeParagraph,
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsNothing);
      expect(
        _cardWidget(tester, chunks[1]).speedReadController,
        same(speedReadController),
      );

      speedReadController.dispose();
    },
  );

  testWidgets(
    'canonical paragraph keeps inline styles links and footnotes across activation',
    (tester) async {
      const text = 'Alice opened the archive [1] before dawn.';
      const linkStart = 17;
      const linkEnd = 24;
      const footnoteStart = 25;
      const chunk = BookChunk(
        index: 31,
        type: BookChunkType.text,
        text: text,
        inlineStyles: <InlineStyle>[
          InlineStyle(start: 0, end: 5, type: InlineStyleType.bold),
        ],
        links: <LinkMetadata>[
          LinkMetadata(
            start: linkStart,
            end: linkEnd,
            url: 'https://example.invalid/archive',
          ),
        ],
        footnotes: <FootnoteRef>[
          FootnoteRef(
            position: footnoteStart,
            label: '1',
            content: 'The archive footnote remains interactive.',
          ),
        ],
      );
      var openedLink = '';

      Future<void> pumpCard({required bool active}) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 720,
                child: ReadingCard(
                  chunk: chunk,
                  settings: const ReadingSettings(),
                  isActivePage: active,
                  enableTextSelection: active,
                  onLinkTap: (url) => openedLink = url,
                ),
              ),
            ),
          ),
        );
      }

      await pumpCard(active: false);
      final previewLayout = _paragraphSnapshot(tester, chunk);
      final previewSpans = _flattenTextSpans(
        tester.widget<Text>(_paragraphTextFinder(chunk)).textSpan!,
      ).toList();
      expect(_spanContaining(previewSpans, 'archive').recognizer, isNull);
      expect(_spanContaining(previewSpans, '[1]').recognizer, isNull);

      await pumpCard(active: true);
      await tester.pump();
      _expectSameParagraphLayout(
        previewLayout,
        _paragraphSnapshot(tester, chunk),
        reason: 'annotated paragraph activation',
      );

      final activeSpans = _flattenTextSpans(
        tester.widget<Text>(_paragraphTextFinder(chunk)).textSpan!,
      ).toList();
      final alice = _spanContaining(activeSpans, 'Alice');
      expect(alice.style?.fontWeight, FontWeight.w700);
      final linkRecognizer =
          _spanContaining(activeSpans, 'archive').recognizer
              as TapGestureRecognizer?;
      final footnoteRecognizer =
          _spanContaining(activeSpans, '[1]').recognizer
              as TapGestureRecognizer?;
      expect(linkRecognizer, isNotNull);
      expect(footnoteRecognizer, isNotNull);

      linkRecognizer!.onTap!();
      await tester.pump();
      expect(openedLink, 'https://example.invalid/archive');

      footnoteRecognizer!.onTap!();
      await tester.pumpAndSettle();
      expect(
        find.text('The archive footnote remains interactive.'),
        findsOneWidget,
      );
    },
  );
}

List<BookChunk> _testChunks() {
  const thresholdParagraph =
      'The dogs and sledges continued steadily across the frozen channel while the incoming card moved toward the reader.';
  return <BookChunk>[
    const BookChunk(
      index: 20,
      type: BookChunkType.text,
      text:
          'The expedition waited beside the pressure ridge until the weather cleared enough to continue.',
      sourceRanges: <ChunkSourceRange>[
        ChunkSourceRange(
          originalChunkIndex: 8,
          originalStartOffset: 120,
          originalEndOffset: 218,
          displayStartOffset: 0,
          displayEndOffset: 98,
          logicalParagraphId: 'chapter-2.xhtml#p8',
        ),
      ],
    ),
    const BookChunk(
      index: 21,
      type: BookChunkType.text,
      text: thresholdParagraph,
      sourceRanges: <ChunkSourceRange>[
        ChunkSourceRange(
          originalChunkIndex: 9,
          originalStartOffset: 42,
          originalEndOffset: 159,
          displayStartOffset: 0,
          displayEndOffset: 117,
          logicalParagraphId: 'chapter-2.xhtml#p9',
        ),
      ],
    ),
    const BookChunk(
      index: 22,
      type: BookChunkType.text,
      text: 'A third card keeps the normal depth stack populated.',
    ),
  ];
}

Widget _buildDeckHarness({
  required List<BookChunk> chunks,
  required ReadingCardDeckController deckController,
  required SpeedReadController speedReadController,
  ValueChanged<int>? onIndexChanged,
  ValueChanged<bool>? onInteractionBlockedChanged,
}) {
  var currentIndex = 0;
  return MaterialApp(
    home: StatefulBuilder(
      builder: (context, setState) {
        return Scaffold(
          body: SizedBox(
            width: 420,
            height: 720,
            child: ReadingCardDeck(
              controller: deckController,
              currentIndex: currentIndex,
              itemCount: chunks.length,
              cacheCardWidgetsDuringDrag: true,
              onIndexChanged: (index) {
                setState(() => currentIndex = index);
                onIndexChanged?.call(index);
              },
              cardBuilder: (context, index, progress, isCurrent) {
                return ReadingCard(
                  chunk: chunks[index],
                  settings: const ReadingSettings(),
                  isActivePage: isCurrent,
                  enableTextSelection: isCurrent,
                  speedReadController: isCurrent ? speedReadController : null,
                  depthLiftProgress: progress,
                  showStackLayers: false,
                  onInteractionBlockedChanged: isCurrent
                      ? onInteractionBlockedChanged
                      : null,
                );
              },
            ),
          ),
        );
      },
    ),
  );
}

ReadingCard _cardWidget(WidgetTester tester, BookChunk chunk) {
  return tester.widget<ReadingCard>(_cardFinder(chunk));
}

void _expectCardIdentity(
  WidgetTester tester,
  BookChunk chunk, {
  required bool isActive,
}) {
  final card = _cardWidget(tester, chunk);
  expect(card.chunk, same(chunk));
  expect(card.chunk.sourceRanges, same(chunk.sourceRanges));
  expect(card.isActivePage, isActive);
}

void _expectPreviewIsNonInteractive(WidgetTester tester, BookChunk chunk) {
  final ignorePointer = tester.widget<IgnorePointer>(
    find
        .ancestor(of: _cardFinder(chunk), matching: find.byType(IgnorePointer))
        .first,
  );
  expect(ignorePointer.ignoring, isTrue);
  expect(_cardWidget(tester, chunk).enableTextSelection, isFalse);
}

Finder _cardFinder(BookChunk chunk) {
  return find.byWidgetPredicate(
    (widget) => widget is ReadingCard && identical(widget.chunk, chunk),
  );
}

Finder _paragraphTextFinder(BookChunk chunk) {
  return find.descendant(
    of: _cardFinder(chunk),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Text && widget.textSpan?.toPlainText() == chunk.text,
    ),
  );
}

_ParagraphSnapshot _paragraphSnapshot(WidgetTester tester, BookChunk chunk) {
  final textFinder = _paragraphTextFinder(chunk);
  expect(textFinder, findsOneWidget);
  final text = tester.widget<Text>(textFinder);
  final richTextFinder = find.descendant(
    of: textFinder,
    matching: find.byType(RichText),
  );
  expect(richTextFinder, findsOneWidget);
  final richText = tester.widget<RichText>(richTextFinder);
  final paragraph = tester.renderObject<RenderParagraph>(richTextFinder);
  final plainText = richText.text.toPlainText();
  final textPainter = TextPainter(
    text: richText.text,
    textAlign: richText.textAlign,
    textDirection: richText.textDirection ?? TextDirection.ltr,
    textScaler: richText.textScaler,
    maxLines: richText.maxLines,
    ellipsis: richText.overflow == TextOverflow.ellipsis ? '\u2026' : null,
    locale: richText.locale,
    strutStyle: richText.strutStyle,
    textWidthBasis: richText.textWidthBasis,
    textHeightBehavior: richText.textHeightBehavior,
  )..layout(maxWidth: paragraph.constraints.maxWidth);
  final lineEnds = <int>[];
  var offset = 0;
  while (offset < plainText.length) {
    final boundary = textPainter.getLineBoundary(TextPosition(offset: offset));
    expect(boundary.end, greaterThan(offset));
    lineEnds.add(boundary.end);
    offset = boundary.end;
  }

  return _ParagraphSnapshot(
    maxWidth: paragraph.constraints.maxWidth,
    laidOutWidth: paragraph.size.width,
    laidOutHeight: paragraph.size.height,
    textAlign: text.textAlign,
    textScaler: text.textScaler,
    strutStyle: text.strutStyle,
    textHeightBehavior: text.textHeightBehavior,
    locale: richText.locale,
    lineEnds: lineEnds,
    metricStyles: _metricStyleSignatures(richText.text).toList(),
  );
}

Iterable<TextSpan> _flattenTextSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  if (span.text?.isNotEmpty == true) yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _flattenTextSpans(child);
  }
}

TextSpan _spanContaining(List<TextSpan> spans, String text) {
  return spans.firstWhere((span) => span.text?.contains(text) == true);
}

Iterable<String> _metricStyleSignatures(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  final style = span.style;
  yield <Object?>[
    span.text,
    style?.fontFamily,
    style?.fontFamilyFallback,
    style?.fontSize,
    style?.fontWeight,
    style?.fontStyle,
    style?.letterSpacing,
    style?.wordSpacing,
    style?.height,
    style?.locale,
    style?.fontFeatures,
    style?.fontVariations,
  ].join('|');
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _metricStyleSignatures(child);
  }
}

void _expectSameParagraphLayout(
  _ParagraphSnapshot expected,
  _ParagraphSnapshot actual, {
  required String reason,
}) {
  expect(actual.maxWidth, expected.maxWidth, reason: '$reason max width');
  expect(actual.laidOutWidth, expected.laidOutWidth, reason: '$reason width');
  expect(
    actual.laidOutHeight,
    expected.laidOutHeight,
    reason: '$reason height',
  );
  expect(actual.textAlign, expected.textAlign, reason: '$reason alignment');
  expect(actual.textScaler, expected.textScaler, reason: '$reason text scale');
  expect(actual.strutStyle, expected.strutStyle, reason: '$reason strut');
  expect(
    actual.textHeightBehavior,
    expected.textHeightBehavior,
    reason: '$reason height behavior',
  );
  expect(actual.locale, expected.locale, reason: '$reason locale');
  expect(actual.metricStyles, expected.metricStyles, reason: '$reason styles');
  expect(actual.lineEnds, expected.lineEnds, reason: '$reason line boundaries');
  expect(actual.lineEnds.length, greaterThan(1));
}

class _ParagraphSnapshot {
  const _ParagraphSnapshot({
    required this.maxWidth,
    required this.laidOutWidth,
    required this.laidOutHeight,
    required this.textAlign,
    required this.textScaler,
    required this.strutStyle,
    required this.textHeightBehavior,
    required this.locale,
    required this.lineEnds,
    required this.metricStyles,
  });

  final double maxWidth;
  final double laidOutWidth;
  final double laidOutHeight;
  final TextAlign? textAlign;
  final TextScaler? textScaler;
  final StrutStyle? strutStyle;
  final TextHeightBehavior? textHeightBehavior;
  final Locale? locale;
  final List<int> lineEnds;
  final List<String> metricStyles;
}
