import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/book_share_payload.dart';
import 'package:nalori/models/quote_card_style.dart';
import 'package:nalori/models/quote_share_payload.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/quote_card_preview_screen.dart';
import 'package:nalori/widgets/quote_card_canvas.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('quote share editor opens with preview-first shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: QuoteCardPreviewScreen(payload: _quotePayload())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Share'), findsNWidgets(2));
    expect(find.text('Quote'), findsOneWidget);
    expect(find.byType(QuoteCardCanvas), findsWidgets);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Layout'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Deep'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Left'), findsNothing);
  });

  testWidgets('theme and layout controls update quote canvas options', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: QuoteCardPreviewScreen(payload: _quotePayload())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paper'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is QuoteCardCanvas && widget.theme.name == 'Paper',
      ),
      findsWidgets,
    );

    await tester.tap(find.text('Layout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Center'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is QuoteCardCanvas && widget.textAlign == TextAlign.center,
      ),
      findsWidgets,
    );
  });

  testWidgets('swiping the preview changes the selected quote style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: QuoteCardPreviewScreen(payload: _quotePayload())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Classic'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('share-style-page-view')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Polaroid'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is QuoteCardCanvas &&
            widget.cardStyle == QuoteCardStyle.polaroid,
      ),
      findsWidgets,
    );
  });

  testWidgets('full-screen preview opens and returns selected style', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: QuoteCardPreviewScreen(payload: _quotePayload())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fullscreen-style-page-view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fullscreen-selected-style-label')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('fullscreen-style-page-view')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Polaroid'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fullscreen-style-page-view')),
      findsNothing,
    );
    expect(find.text('Polaroid'), findsOneWidget);
  });

  testWidgets('book share editor uses the same shell and book canvas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: QuoteCardPreviewScreen.book(payload: _bookPayload())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Share'), findsNWidgets(2));
    expect(find.text('Book'), findsOneWidget);
    expect(find.byType(BookCardCanvas), findsWidgets);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Layout'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('share-style-page-view')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Polaroid'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is BookCardCanvas &&
            widget.cardStyle == QuoteCardStyle.polaroid,
      ),
      findsWidgets,
    );
  });
}

QuoteSharePayload _quotePayload() {
  return QuoteSharePayload.fromSelection(
    quote: 'A sentence worth carrying forward.',
    bookTitle: 'The Test Novel',
    author: 'A. Writer',
    bookId: 'book-id',
    displayIndex: 2,
    fontFamily: ReaderFontFamily.lora,
  );
}

BookSharePayload _bookPayload() {
  return BookSharePayload.fromBook(
    bookTitle: 'The Test Novel',
    author: 'A. Writer',
    bookId: 'book-id',
    fontFamily: ReaderFontFamily.lora,
  );
}
