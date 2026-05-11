import 'package:shared_preferences/shared_preferences.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/saved_word.dart';
import 'package:nalori/models/reading_settings.dart';

class MockSharedPreferences {
  static Future<SharedPreferences> getMock({
    Map<String, Object>? values,
  }) async {
    SharedPreferences.setMockInitialValues(values ?? {});
    return SharedPreferences.getInstance();
  }
}

class TestData {
  static Bookmark createBookmark({
    int chunkIndex = 0,
    String name = 'Test Bookmark',
  }) {
    return Bookmark(
      chunkIndex: chunkIndex,
      name: name,
      createdAt: DateTime(2026, 3, 11),
    );
  }

  static Highlight createHighlight({
    String id = 'test-highlight-1',
    int originalChunkIndex = 0,
    int startOffset = 0,
    int endOffset = 10,
    String text = 'Test highlight',
    int colorIndex = 0,
  }) {
    return Highlight(
      id: id,
      originalChunkIndex: originalChunkIndex,
      startOffset: startOffset,
      endOffset: endOffset,
      text: text,
      colorIndex: colorIndex,
      createdAt: DateTime(2026, 3, 11),
    );
  }

  static SavedWord createSavedWord({
    String id = 'test-word-1',
    String word = 'serendipity',
    String meaning = 'The occurrence of events by chance in a happy way',
    String? contextSentence,
    String bookId = 'test-book-1',
  }) {
    return SavedWord(
      id: id,
      word: word,
      meaning: meaning,
      bookId: bookId,
      timestamp: DateTime(2026, 3, 11).millisecondsSinceEpoch,
      contextSentence: contextSentence,
    );
  }

  static ReadingSettings createDefaultSettings() {
    return const ReadingSettings(
      appTheme: AppTheme.amoled,
      fontFamily: ReaderFontFamily.literata,
      fontWeight: ReaderFontWeight.regular,
      fontSize: ReaderFontSize.m,
      textAlign: ReaderTextAlign.left,
      contentDensity: ContentDensity.medium,
      enableCardDepth: false,
      blueLightFilter: false,
      blueLightIntensity: 0.3,
    );
  }
}
