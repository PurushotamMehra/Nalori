import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/saved_word.dart';

void main() {
  group('SavedWord', () {
    group('constructor', () {
      test('should create saved word with required parameters', () {
        final word = SavedWord(
          id: 'word-1',
          word: 'serendipity',
          meaning: 'Finding good things by chance',
          bookId: 'book-1',
          timestamp: 1234567890,
        );

        expect(word.id, 'word-1');
        expect(word.word, 'serendipity');
        expect(word.meaning, 'Finding good things by chance');
        expect(word.bookId, 'book-1');
        expect(word.timestamp, 1234567890);
      });

      test('should accept contextSentence', () {
        final word = SavedWord(
          id: 'word-1',
          word: 'test',
          meaning: 'Test meaning',
          bookId: 'book-1',
          timestamp: 1234567890,
          contextSentence: 'This is a test sentence.',
        );

        expect(word.contextSentence, 'This is a test sentence.');
      });

      test('should accept optional text anchor', () {
        final word = SavedWord(
          id: 'word-1',
          word: 'test',
          meaning: 'Test meaning',
          bookId: 'book-1',
          timestamp: 1234567890,
          originalChunkIndex: 4,
          originalStartOffset: 12,
          originalEndOffset: 16,
        );

        expect(word.originalChunkIndex, 4);
        expect(word.originalStartOffset, 12);
        expect(word.originalEndOffset, 16);
      });

      test('should allow null contextSentence', () {
        final word = SavedWord(
          id: 'word-1',
          word: 'test',
          meaning: 'Test meaning',
          bookId: 'book-1',
          timestamp: 1234567890,
        );

        expect(word.contextSentence, isNull);
      });
    });

    group('copyWith', () {
      test('should copy with new id', () {
        final original = SavedWord(
          id: 'original-id',
          word: 'test',
          meaning: 'Test',
          bookId: 'book-1',
          timestamp: 1234567890,
        );
        final copy = original.copyWith(id: 'new-id');

        expect(copy.id, 'new-id');
        expect(copy.word, 'test');
      });

      test('should copy with new meaning', () {
        final original = SavedWord(
          id: 'word-1',
          word: 'test',
          meaning: 'Original meaning',
          bookId: 'book-1',
          timestamp: 1234567890,
        );
        final copy = original.copyWith(meaning: 'New meaning');

        expect(copy.meaning, 'New meaning');
      });
    });

    group('serialization', () {
      test('should convert to map', () {
        final word = SavedWord(
          id: 'word-1',
          word: 'test',
          meaning: 'Test meaning',
          bookId: 'book-1',
          timestamp: 1234567890,
          contextSentence: 'Context',
        );

        final map = word.toMap();

        expect(map['id'], 'word-1');
        expect(map['word'], 'test');
        expect(map['meaning'], 'Test meaning');
        expect(map['bookId'], 'book-1');
        expect(map['timestamp'], 1234567890);
        expect(map['contextSentence'], 'Context');
      });

      test('should convert text anchor to map', () {
        final word = SavedWord(
          id: 'word-1',
          word: 'test',
          meaning: 'Test meaning',
          bookId: 'book-1',
          timestamp: 1234567890,
          originalChunkIndex: 3,
          originalStartOffset: 20,
          originalEndOffset: 24,
        );

        final map = word.toMap();

        expect(map['originalChunkIndex'], 3);
        expect(map['originalStartOffset'], 20);
        expect(map['originalEndOffset'], 24);
      });

      test('should create from map', () {
        final map = {
          'id': 'word-1',
          'word': 'serendipity',
          'meaning': 'Finding good things',
          'bookId': 'book-1',
          'timestamp': 1234567890,
          'contextSentence': 'Test context',
          'originalChunkIndex': 7,
          'originalStartOffset': 30,
          'originalEndOffset': 38,
        };

        final word = SavedWord.fromMap(map);

        expect(word.id, 'word-1');
        expect(word.word, 'serendipity');
        expect(word.meaning, 'Finding good things');
        expect(word.contextSentence, 'Test context');
        expect(word.originalChunkIndex, 7);
        expect(word.originalStartOffset, 30);
        expect(word.originalEndOffset, 38);
      });

      test('should handle null contextSentence in fromMap', () {
        final map = {
          'id': 'word-1',
          'word': 'test',
          'meaning': 'Meaning',
          'bookId': 'book-1',
          'timestamp': 1234567890,
        };

        final word = SavedWord.fromMap(map);

        expect(word.contextSentence, isNull);
      });

      test('should convert to JSON', () {
        final word = SavedWord(
          id: 'word-1',
          word: 'test',
          meaning: 'Meaning',
          bookId: 'book-1',
          timestamp: 1234567890,
        );

        final json = word.toJson();

        expect(json, contains('word-1'));
        expect(json, contains('test'));
      });

      test('should create from JSON', () {
        final json =
            '{"id":"word-1","word":"test","meaning":"Meaning","bookId":"book-1","timestamp":1234567890}';

        final word = SavedWord.fromJson(json);

        expect(word.id, 'word-1');
        expect(word.word, 'test');
        expect(word.meaning, 'Meaning');
      });

      test('should handle missing values in fromMap', () {
        final map = <String, dynamic>{};

        final word = SavedWord.fromMap(map);

        expect(word.id, '');
        expect(word.word, '');
        expect(word.meaning, '');
        expect(word.bookId, '');
        expect(word.timestamp, 0);
      });
    });
  });
}
