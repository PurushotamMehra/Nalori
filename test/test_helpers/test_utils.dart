import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestUtils {
  static Future<void> setUpMockSharedPreferences(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
  }

  static Future<SharedPreferences> getMockPreferences(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  static Map<String, dynamic> createMockBookMetadata() {
    return {
      'id': 'test-book-1',
      'title': 'Test Book',
      'author': 'Test Author',
      'filePath': '/test/path/book.epub',
      'coverImagePath': null,
      'dateAdded': DateTime.now().toIso8601String(),
      'lastRead': DateTime.now().toIso8601String(),
      'currentPosition': 0,
      'totalChunks': 100,
    };
  }

  static Map<String, dynamic> createMockBookmark() {
    return {
      'id': 'bookmark-1',
      'bookId': 'test-book-1',
      'position': 50,
      'chapterIndex': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'note': 'Test bookmark',
    };
  }

  static Map<String, dynamic> createMockHighlight() {
    return {
      'id': 'highlight-1',
      'bookId': 'test-book-1',
      'chapterIndex': 1,
      'startPosition': 10,
      'endPosition': 50,
      'text': 'Test highlighted text',
      'color': '#FFFF00',
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  static Map<String, dynamic> createMockReadingStats() {
    return {
      'bookId': 'test-book-1',
      'totalReadingTimeMs': 3600000,
      'sessionsCount': 5,
      'pagesRead': 50,
      'lastSessionDate': DateTime.now().toIso8601String(),
      'readingStreak': 3,
    };
  }

  static Map<String, dynamic> createMockSavedWord() {
    return {
      'id': 'word-1',
      'word': 'serendipity',
      'definition': 'The occurrence of events by chance in a happy way',
      'context': 'She found serendipity in the old bookstore.',
      'bookId': 'test-book-1',
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}
