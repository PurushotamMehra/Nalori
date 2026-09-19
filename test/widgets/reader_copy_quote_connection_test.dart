import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/quote_share_payload.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/quote_card_preview_screen.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/widgets/reading_card.dart';

void main() {
  const selectedText = 'Café';
  const exactMultilineQuote =
      '  “Café déjà vu,” she said — don\'t change it.\n\n'
      'Second paragraph: 日本語 & emoji 📚  ';

  testWidgets('Copy freezes exact text and waits before showing success', (
    tester,
  ) async {
    final clipboardCompleted = Completer<void>();
    String? copiedText;

    await _pumpReadingCard(
      tester,
      text: selectedText,
      clipboardWriter: (data) {
        copiedText = data.text;
        return clipboardCompleted.future;
      },
    );
    await _selectAndOpenMore(tester);

    await _tapMenuAction(tester, 'Copy');
    await tester.pump();

    expect(copiedText, selectedText);
    expect(find.text('Copied to clipboard'), findsNothing);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);

    clipboardCompleted.complete();
    await tester.pumpAndSettle();

    expect(find.text('Copied to clipboard'), findsOneWidget);
    expect(copiedText, selectedText);
  });

  testWidgets('Copy failure reports failure and never reports success', (
    tester,
  ) async {
    await _pumpReadingCard(
      tester,
      text: selectedText,
      clipboardWriter: (_) async => throw StateError('clipboard unavailable'),
    );
    await _selectAndOpenMore(tester);

    await _tapMenuAction(tester, 'Copy');
    await tester.pump();

    expect(find.text('Could not copy text'), findsOneWidget);
    expect(find.text('Copied to clipboard'), findsNothing);
  });

  testWidgets('Share opens the existing quote editor with exact book context', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    QuoteSharePayload? openedPayload;
    var nativeShareCalls = 0;
    const nativeShareChannel = MethodChannel('quote_card/share');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeShareChannel, (call) async {
          nativeShareCalls += 1;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeShareChannel, null);
    });

    await _pumpReadingCard(
      tester,
      navigatorKey: navigatorKey,
      text: selectedText,
      onQuoteShareRequested: (start, end, text) async {
        openedPayload = buildReaderQuoteSharePayload(
          selectedText: text,
          bookTitle: 'The Test Book',
          author: 'Ada Author',
          bookId: 'test-book.epub',
          displayIndex: 7,
          coverImagePath: '/covers/test-book.jpg',
          fontFamily: ReaderFontFamily.lora,
          startOffset: start,
          endOffset: end,
        );
        await navigatorKey.currentState!.push(
          buildReaderQuoteShareRoute(openedPayload!),
        );
      },
    );
    await _selectAndOpenMore(tester);

    await _tapMenuAction(tester, 'Share');
    await tester.pumpAndSettle();

    expect(find.byType(QuoteCardPreviewScreen), findsOneWidget);
    expect(openedPayload?.quote, selectedText);
    expect(openedPayload?.bookTitle, 'The Test Book');
    expect(openedPayload?.author, 'Ada Author');
    expect(openedPayload?.bookId, 'test-book.epub');
    expect(openedPayload?.coverImagePath, '/covers/test-book.jpg');
    expect(openedPayload?.fontFamily, ReaderFontFamily.lora);
    expect(openedPayload?.startOffset, 0);
    expect(openedPayload?.endOffset, selectedText.length);
    expect(nativeShareCalls, 0);
  });

  testWidgets(
    'reader quote route preserves Unicode punctuation and multiline text',
    (tester) async {
      final payload = buildReaderQuoteSharePayload(
        selectedText: exactMultilineQuote,
        bookTitle: 'The Test Book',
        author: 'Ada Author',
        bookId: 'test-book.epub',
        displayIndex: 7,
        coverImagePath: '/covers/test-book.jpg',
        fontFamily: ReaderFontFamily.lora,
        startOffset: 12,
        endOffset: 12 + exactMultilineQuote.length,
      );

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (_) => buildReaderQuoteShareRoute(payload),
        ),
      );
      await tester.pumpAndSettle();

      final screen = tester.widget<QuoteCardPreviewScreen>(
        find.byType(QuoteCardPreviewScreen),
      );
      expect(screen.payload?.quote, exactMultilineQuote);
      expect(screen.payload?.bookTitle, 'The Test Book');
      expect(screen.payload?.author, 'Ada Author');
      expect(screen.payload?.coverImagePath, '/covers/test-book.jpg');
      expect(screen.payload?.startOffset, 12);
      expect(screen.payload?.endOffset, 12 + exactMultilineQuote.length);
    },
  );

  testWidgets('rapid repeated Share taps open only one async share flow', (
    tester,
  ) async {
    final shareCompleted = Completer<void>();
    var shareCalls = 0;

    await _pumpReadingCard(
      tester,
      text: selectedText,
      onQuoteShareRequested: (_, __, text) {
        shareCalls += 1;
        expect(text, selectedText);
        return shareCompleted.future;
      },
    );
    await _selectAndOpenMore(tester);
    final shareAction = find.text('Share');
    await tester.tap(shareAction);
    await tester.tap(shareAction, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(shareCalls, 1);
    shareCompleted.complete();
    await tester.pump();
  });
}

Future<void> _pumpReadingCard(
  WidgetTester tester, {
  required String text,
  GlobalKey<NavigatorState>? navigatorKey,
  Future<void> Function(ClipboardData data)? clipboardWriter,
  FutureOr<void> Function(int start, int end, String text)?
  onQuoteShareRequested,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 520,
            height: 820,
            child: ReadingCard(
              chunk: BookChunk(index: 0, type: BookChunkType.text, text: text),
              settings: const ReadingSettings(),
              clipboardWriter: clipboardWriter,
              onQuoteShareRequested: onQuoteShareRequested,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectAndOpenMore(WidgetTester tester) async {
  final paragraph = _readerRichText().first;
  final selectionPoint =
      tester.getTopLeft(paragraph) +
      Offset(8, tester.getSize(paragraph).height / 2);
  await tester.longPressAt(selectionPoint);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.more_horiz_rounded));
  await tester.pumpAndSettle();
}

Finder _readerRichText() {
  return find.descendant(
    of: find.byType(SelectionArea),
    matching: find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan != null,
    ),
  );
}

Future<void> _tapMenuAction(WidgetTester tester, String label) async {
  final action = find.text(label);
  expect(action, findsOneWidget);
  final icon = label == 'Copy'
      ? find.byIcon(Icons.copy_rounded)
      : find.byIcon(Icons.ios_share_rounded);
  expect(icon, findsOneWidget);
  await tester.tap(icon);
  await tester.pumpAndSettle();
}
