import 'package:flutter/foundation.dart';

import 'reading_settings.dart';

@immutable
class QuoteSharePayload {
  static const int maxQuoteLength = 1000;

  final String quote;
  final String bookTitle;
  final String author;
  final String bookId;
  final String? coverImagePath;
  final ReaderFontFamily fontFamily;
  final int displayIndex;
  final int? startOffset;
  final int? endOffset;

  const QuoteSharePayload({
    required this.quote,
    required this.bookTitle,
    required this.author,
    required this.bookId,
    this.coverImagePath,
    this.fontFamily = ReaderFontFamily.literata,
    required this.displayIndex,
    this.startOffset,
    this.endOffset,
  });

  factory QuoteSharePayload.fromSelection({
    required String quote,
    required String bookTitle,
    required String author,
    required String bookId,
    required int displayIndex,
    String? coverImagePath,
    ReaderFontFamily fontFamily = ReaderFontFamily.literata,
    int? startOffset,
    int? endOffset,
  }) {
    final normalizedQuote = normalizeQuote(quote);
    if (normalizedQuote.isEmpty) {
      throw ArgumentError.value(quote, 'quote', 'Quote cannot be empty');
    }

    return QuoteSharePayload(
      quote: normalizedQuote,
      bookTitle: normalizeMetadata(bookTitle, fallback: 'Untitled Book'),
      author: normalizeMetadata(author),
      bookId: bookId,
      coverImagePath: coverImagePath,
      fontFamily: fontFamily,
      displayIndex: displayIndex,
      startOffset: startOffset,
      endOffset: endOffset,
    );
  }

  String get attribution {
    if (author.isEmpty) return bookTitle;
    return '$bookTitle by $author';
  }

  static String normalizeQuote(String input, {int maxLength = maxQuoteLength}) {
    final compact = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= maxLength) return compact;

    final cutoff = compact.lastIndexOf(' ', maxLength - 3);
    final end = cutoff > maxLength * 0.6 ? cutoff : maxLength - 3;
    return '${compact.substring(0, end).trimRight()}...';
  }

  static String normalizeMetadata(String input, {String fallback = ''}) {
    final compact = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    return compact.isEmpty ? fallback : compact;
  }
}
