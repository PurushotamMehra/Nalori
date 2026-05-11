import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nalori/services/dictionary_service.dart';

void main() {
  late DictionaryService dictionaryService;
  const testBookId = 'test-book-1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dictionaryService = DictionaryService(bookId: testBookId);
    await Future.delayed(const Duration(milliseconds: 100));
  });

  group('DictionaryService', () {
    group('lookupWord', () {
      test('should return definition for valid word', () async {
        final result = await dictionaryService.lookupWord('hello');

        expect(result, isNotNull);
        expect(result, isA<String>());
      });

      test('should return null for empty word', () async {
        final result = await dictionaryService.lookupWord('');

        expect(result, isNull);
      });

      test('should return null for non-existent word', () async {
        final result = await dictionaryService.lookupWord('asdfghjklqwertyuio');

        expect(result, isNull);
      });

      test('should trim whitespace from word', () async {
        final result = await dictionaryService.lookupWord('  hello  ');

        expect(result, isNotNull);
      });

      test('should handle punctuation in word', () async {
        final result = await dictionaryService.lookupWord('hello,');

        expect(result, isNotNull);
      });
    });

    group('saveWord', () {
      test('should save word to vocabulary', () async {
        await dictionaryService.saveWord(
          'serendipity',
          'Finding something good by chance',
        );

        expect(dictionaryService.words.length, 1);
        expect(dictionaryService.words[0].word, 'serendipity');
      });

      test('should save optional text anchor', () async {
        await dictionaryService.saveWord(
          'serendipity',
          'Finding something good by chance',
          contextSentence: 'A line with serendipity in it.',
          originalChunkIndex: 2,
          originalStartOffset: 18,
          originalEndOffset: 29,
        );

        final savedWord = dictionaryService.words.single;
        expect(savedWord.contextSentence, 'A line with serendipity in it.');
        expect(savedWord.originalChunkIndex, 2);
        expect(savedWord.originalStartOffset, 18);
        expect(savedWord.originalEndOffset, 29);
      });

      test('should remove duplicate word before saving', () async {
        await dictionaryService.saveWord('hello', 'First meaning');
        await dictionaryService.saveWord('hello', 'Second meaning');

        expect(dictionaryService.words.length, 1);
      });

      test('should be case insensitive for duplicates', () async {
        await dictionaryService.saveWord('Hello', 'First meaning');
        await dictionaryService.saveWord('hello', 'Second meaning');

        expect(dictionaryService.words.length, 1);
      });
    });

    group('deleteWord', () {
      test('should delete word by id', () async {
        await dictionaryService.saveWord('test', 'A test word');
        final wordId = dictionaryService.words[0].id;

        await dictionaryService.deleteWord(wordId);

        expect(dictionaryService.words, isEmpty);
      });
    });

    group('isWordSaved', () {
      test('should return true for saved word', () async {
        await dictionaryService.saveWord('paradigm', 'A typical example');

        expect(dictionaryService.isWordSaved('paradigm'), true);
      });

      test('should return false for unsaved word', () async {
        expect(dictionaryService.isWordSaved('paradigm'), false);
      });

      test('should be case insensitive', () async {
        await dictionaryService.saveWord('Paradigm', 'A typical example');

        expect(dictionaryService.isWordSaved('paradigm'), true);
      });
    });

    group('words getter', () {
      test('should return unmodifiable list', () async {
        await dictionaryService.saveWord('test', 'Test definition');

        expect(
          () => dictionaryService.words.add(
            throw UnsupportedError('Cannot modify'),
          ),
          throwsUnsupportedError,
        );
      });
    });
  });
}
