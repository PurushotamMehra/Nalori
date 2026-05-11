import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/book_share_payload.dart';
import 'package:nalori/models/quote_share_payload.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/services/quote_card_palette_service.dart';
import 'package:nalori/widgets/quote_card_canvas.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('renders a story-sized quote card', (tester) async {
    final payload = QuoteSharePayload.fromSelection(
      quote: 'A sentence worth carrying forward.',
      bookTitle: 'The Test Novel',
      author: 'A. Writer',
      bookId: 'book-id',
      displayIndex: 2,
      coverImagePath: '/path/to/missing-cover.png',
      fontFamily: ReaderFontFamily.lora,
    );
    final theme = QuoteCardPaletteService.fallbackThemes().first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 270,
              height: 480,
              child: QuoteCardCanvas(payload: payload, theme: theme),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is AspectRatio && widget.aspectRatio == 9 / 16,
      ),
      findsOneWidget,
    );
    expect(find.text('A sentence worth carrying forward.'), findsOneWidget);
    expect(find.text('The Test Novel'), findsOneWidget);
    expect(find.text('A. Writer'), findsOneWidget);
    expect(find.text('Nalori'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quote-card-decorative-quote-mark')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('quote-card-book-cover')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quote-card-nalori-icon')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('quote-card-book-cover')))
          .height,
      lessThan(80),
    );
    expect(
      tester.getTopLeft(find.text('Nalori')).dy,
      lessThan(tester.getTopLeft(find.text('The Test Novel')).dy),
    );

    final watermarkText = tester.widget<Text>(find.text('Nalori'));
    expect(watermarkText.style?.color, Colors.white);
    expect(watermarkText.style?.fontWeight, FontWeight.w300);

    final quoteText = tester.widget<Text>(
      find.text('A sentence worth carrying forward.'),
    );
    expect(quoteText.style?.fontFamily, contains('Lora'));
  });

  testWidgets('applies centered quote text alignment', (tester) async {
    final payload = QuoteSharePayload.fromSelection(
      quote: 'A sentence worth carrying forward.',
      bookTitle: 'The Test Novel',
      author: 'A. Writer',
      bookId: 'book-id',
      displayIndex: 2,
      fontFamily: ReaderFontFamily.lora,
    );
    final theme = QuoteCardPaletteService.fallbackThemes().first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 270,
              height: 480,
              child: QuoteCardCanvas(
                payload: payload,
                theme: theme,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );

    final quoteText = tester.widget<Text>(
      find.text('A sentence worth carrying forward.'),
    );
    expect(quoteText.textAlign, TextAlign.center);
  });

  testWidgets('uses a dark watermark on light quote card themes', (
    tester,
  ) async {
    final payload = QuoteSharePayload.fromSelection(
      quote: 'A sentence worth carrying forward.',
      bookTitle: 'The Test Novel',
      author: 'A. Writer',
      bookId: 'book-id',
      displayIndex: 2,
      fontFamily: ReaderFontFamily.lora,
    );
    final theme = QuoteCardPaletteService.fallbackThemes().firstWhere(
      (theme) => theme.name == 'Minimal',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 270,
              height: 480,
              child: QuoteCardCanvas(payload: payload, theme: theme),
            ),
          ),
        ),
      ),
    );

    final watermarkText = tester.widget<Text>(find.text('Nalori'));
    expect(watermarkText.style?.color, const Color(0xFF111111));
  });

  testWidgets('renders a story-sized book card', (tester) async {
    final payload = BookSharePayload.fromBook(
      bookTitle: 'The Test Novel',
      author: 'A. Writer',
      bookId: 'book-id',
      fontFamily: ReaderFontFamily.lora,
    );
    final theme = QuoteCardPaletteService.fallbackThemes().first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 270,
              height: 480,
              child: BookCardCanvas(payload: payload, theme: theme),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is AspectRatio && widget.aspectRatio == 9 / 16,
      ),
      findsOneWidget,
    );
    expect(find.text('The Test Novel'), findsWidgets);
    expect(find.text('A. Writer'), findsWidgets);
    expect(find.text('Nalori'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('book-card-generated-cover')),
      findsOneWidget,
    );

    final titleText = tester.widget<Text>(find.text('The Test Novel').last);
    expect(titleText.style?.fontFamily, contains('Lora'));
  });

  testWidgets('renders a compact reading recap card without overflow', (
    tester,
  ) async {
    final payload = ReadingRecapPayload.fromBook(
      bookTitle: 'Nineteen Eighty-Four',
      author: 'George Orwell',
      bookId: 'book-id',
      totalReadingTime: '0m',
      averageWpm: '450 WPM',
      fastestChapter: 'Chapter 4 • 450 WPM',
      longestChapter: 'Chapter 5 • 42m',
      fontFamily: ReaderFontFamily.lora,
    );
    final theme = QuoteCardPaletteService.fallbackThemes().first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 270,
              height: 480,
              child: ReadingRecapCardCanvas(payload: payload, theme: theme),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Reading Recap'), findsOneWidget);
    expect(find.text('Nineteen Eighty-Four'), findsOneWidget);
    expect(find.text('George Orwell'), findsOneWidget);
    expect(find.text('Chapter 4 • 450 WPM'), findsOneWidget);
  });
}
