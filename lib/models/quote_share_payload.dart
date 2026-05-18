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
    final compact = _normalizeQuoteSpacing(input);
    if (compact.length <= maxLength) return compact;

    final cutoff = compact.lastIndexOf(' ', maxLength - 3);
    final end = cutoff > maxLength * 0.6 ? cutoff : maxLength - 3;
    return '${compact.substring(0, end).trimRight()}...';
  }

  static String normalizeMetadata(String input, {String fallback = ''}) {
    final compact = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    return compact.isEmpty ? fallback : compact;
  }

  static String _normalizeQuoteSpacing(String input) {
    final compact = input
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(RegExp(r'\s+([,.;:!?])'), (match) => match[1]!);
    if (compact.isEmpty) return compact;

    final buffer = StringBuffer();
    var inSingleQuote = false;
    var inDoubleQuote = false;

    for (var i = 0; i < compact.length; i += 1) {
      final char = compact[i];
      if (char == '“' || char == '‘') {
        buffer.write(char);
        while (i + 1 < compact.length && compact[i + 1] == ' ') {
          i += 1;
        }
        continue;
      }

      if (char == '”' || char == '’') {
        _trimTrailingSpace(buffer);
        buffer.write(char);
        continue;
      }

      if (char == "'" || char == '"') {
        final previous = _nearestNonSpace(compact, i, -1);
        final next = _nearestNonSpace(compact, i, 1);
        final isApostropheInWord =
            char == "'" &&
            previous != null &&
            next != null &&
            _isAsciiLetterOrDigit(previous) &&
            _isAsciiLetterOrDigit(next);
        if (isApostropheInWord) {
          buffer.write(char);
          continue;
        }

        final isSingle = char == "'";
        final isOpening = isSingle ? !inSingleQuote : !inDoubleQuote;
        if (isOpening) {
          buffer.write(char);
          while (i + 1 < compact.length && compact[i + 1] == ' ') {
            i += 1;
          }
        } else {
          _trimTrailingSpace(buffer);
          buffer.write(char);
        }
        if (isSingle) {
          inSingleQuote = !inSingleQuote;
        } else {
          inDoubleQuote = !inDoubleQuote;
        }
        continue;
      }

      buffer.write(char);
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _nearestNonSpace(String text, int index, int direction) {
    var cursor = index + direction;
    while (cursor >= 0 && cursor < text.length) {
      final char = text[cursor];
      if (char != ' ') return char;
      cursor += direction;
    }
    return null;
  }

  static bool _isAsciiLetterOrDigit(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122);
  }

  static void _trimTrailingSpace(StringBuffer buffer) {
    final value = buffer.toString();
    if (!value.endsWith(' ')) return;
    buffer
      ..clear()
      ..write(value.trimRight());
  }
}
