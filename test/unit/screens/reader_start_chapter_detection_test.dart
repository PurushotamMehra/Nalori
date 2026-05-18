import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/screens/reader_screen.dart';

void main() {
  group('first reading chapter detection', () {
    test('finds explicit chapter one after front matter', () {
      final chapter = detectFirstReadingChapter(const [
        ChapterInfo(title: 'Cover', chunkIndex: 0),
        ChapterInfo(title: 'Copyright', chunkIndex: 1),
        ChapterInfo(title: 'Table of Contents', chunkIndex: 2),
        ChapterInfo(title: 'Chapter One', chunkIndex: 8),
        ChapterInfo(title: 'Chapter Two', chunkIndex: 24),
      ]);

      expect(chapter?.title, 'Chapter One');
      expect(chapter?.chunkIndex, 8);
    });

    test('detects numeric and roman chapter one titles', () {
      expect(isChapterOneLikeTitle('1'), isTrue);
      expect(isChapterOneLikeTitle('I'), isTrue);
      expect(isChapterOneLikeTitle('Chapter 1'), isTrue);
      expect(isChapterOneLikeTitle('Chapter I'), isTrue);
      expect(isChapterOneLikeTitle('Chapter 10'), isFalse);
    });

    test('detects nested part one chapter one title path', () {
      final chapter = detectFirstReadingChapter(const [
        ChapterInfo(title: 'Preface', chunkIndex: 0),
        ChapterInfo(
          title: 'Part 1',
          chunkIndex: 4,
          children: [ChapterInfo(title: 'Chapter 1', chunkIndex: 6, depth: 1)],
        ),
      ]);

      expect(chapter?.title, 'Chapter 1');
      expect(chapter?.chunkIndex, 6);
    });

    test('falls back to first non-front-matter chapter', () {
      final chapter = detectFirstReadingChapter(const [
        ChapterInfo(title: 'Dedication', chunkIndex: 0),
        ChapterInfo(title: 'Acknowledgements', chunkIndex: 1),
        ChapterInfo(title: 'The Old Road', chunkIndex: 5),
      ]);

      expect(chapter?.title, 'The Old Road');
      expect(chapter?.chunkIndex, 5);
    });

    test('identifies common front matter titles', () {
      expect(isFrontMatterTitle('About the Author'), isTrue);
      expect(isFrontMatterTitle('Foreword'), isTrue);
      expect(isFrontMatterTitle('The Old Road'), isFalse);
    });
  });
}
