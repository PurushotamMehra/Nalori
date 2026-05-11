import 'package:flutter/foundation.dart';

import 'reading_settings.dart';

@immutable
class BookSharePayload {
  final String bookTitle;
  final String author;
  final String bookId;
  final String? coverImagePath;
  final ReaderFontFamily fontFamily;

  const BookSharePayload({
    required this.bookTitle,
    required this.author,
    required this.bookId,
    this.coverImagePath,
    this.fontFamily = ReaderFontFamily.literata,
  });

  factory BookSharePayload.fromBook({
    required String bookTitle,
    required String author,
    required String bookId,
    String? coverImagePath,
    ReaderFontFamily fontFamily = ReaderFontFamily.literata,
  }) {
    return BookSharePayload(
      bookTitle: normalizeMetadata(bookTitle, fallback: 'Untitled Book'),
      author: normalizeMetadata(author),
      bookId: bookId,
      coverImagePath: coverImagePath,
      fontFamily: fontFamily,
    );
  }

  BookSharePayload copyWith({
    String? bookTitle,
    String? author,
    String? bookId,
    String? coverImagePath,
    ReaderFontFamily? fontFamily,
  }) {
    return BookSharePayload(
      bookTitle: bookTitle ?? this.bookTitle,
      author: author ?? this.author,
      bookId: bookId ?? this.bookId,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  String get attribution {
    if (author.isEmpty) return bookTitle;
    return '$bookTitle by $author';
  }

  static String normalizeMetadata(String input, {String fallback = ''}) {
    final compact = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    return compact.isEmpty ? fallback : compact;
  }
}

@immutable
class ReadingRecapPayload {
  final String bookTitle;
  final String author;
  final String bookId;
  final String? coverImagePath;
  final ReaderFontFamily fontFamily;
  final String totalReadingTime;
  final String averageWpm;
  final String? fastestChapter;
  final String? longestChapter;

  const ReadingRecapPayload({
    required this.bookTitle,
    required this.author,
    required this.bookId,
    this.coverImagePath,
    this.fontFamily = ReaderFontFamily.literata,
    required this.totalReadingTime,
    required this.averageWpm,
    this.fastestChapter,
    this.longestChapter,
  });

  factory ReadingRecapPayload.fromBook({
    required String bookTitle,
    required String author,
    required String bookId,
    String? coverImagePath,
    ReaderFontFamily fontFamily = ReaderFontFamily.literata,
    required String totalReadingTime,
    required String averageWpm,
    String? fastestChapter,
    String? longestChapter,
  }) {
    return ReadingRecapPayload(
      bookTitle: BookSharePayload.normalizeMetadata(
        bookTitle,
        fallback: 'Untitled Book',
      ),
      author: BookSharePayload.normalizeMetadata(author),
      bookId: bookId,
      coverImagePath: coverImagePath,
      fontFamily: fontFamily,
      totalReadingTime: totalReadingTime,
      averageWpm: averageWpm,
      fastestChapter: fastestChapter,
      longestChapter: longestChapter,
    );
  }

  String get attribution {
    if (author.isEmpty) return bookTitle;
    return '$bookTitle by $author';
  }
}
