import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/book_metadata.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/reading_settings.dart';

void main() {
  group('BookMetadata', () {
    test('persists online metadata fields', () {
      final metadata = BookMetadata(
        id: 'book.epub',
        managedFilePath: '/app/books/book.epub',
        title: 'The Book of Five Rings',
        author: 'Miyamoto Musashi',
        embeddedTitle: 'Go Rin No Sho',
        embeddedAuthor: 'Musashi Miyamoto',
        titleSource: 'open_library',
        authorSource: 'open_library',
        coverImagePath: '/covers/book.jpg',
        metadataSource: 'open_library',
        openLibraryWorkKey: '/works/OL123W',
        openLibraryCoverId: 123,
        metadataConfidence: 0.92,
      );

      final restored = BookMetadata.fromMap(metadata.toMap());

      expect(restored.metadataSource, 'open_library');
      expect(restored.managedFilePath, '/app/books/book.epub');
      expect(restored.embeddedTitle, 'Go Rin No Sho');
      expect(restored.embeddedAuthor, 'Musashi Miyamoto');
      expect(restored.titleSource, 'open_library');
      expect(restored.authorSource, 'open_library');
      expect(restored.openLibraryWorkKey, '/works/OL123W');
      expect(restored.openLibraryCoverId, 123);
      expect(restored.metadataConfidence, 0.92);
    });

    test('persists opened and meaningful-read timestamps', () {
      final metadata = BookMetadata(
        id: 'book.epub',
        title: 'Book',
        author: 'Author',
        lastOpenedAt: 100,
        lastMeaningfulReadAt: 200,
      );

      final restored = BookMetadata.fromMap(metadata.toMap());

      expect(restored.lastOpenedAt, 100);
      expect(restored.lastMeaningfulReadAt, 200);
    });

    test('legacy progress migrates to meaningful recency only when proven', () {
      final meaningfullyRead = BookMetadata.fromMap({
        'id': 'read.epub',
        'title': 'Read',
        'author': 'Author',
        'lastReadIndex': 4,
        'lastReadTime': 500,
      });
      final importedOnly = BookMetadata.fromMap({
        'id': 'imported.epub',
        'title': 'Imported',
        'author': 'Author',
        'lastReadIndex': 0,
        'lastReadTime': 600,
      });

      expect(meaningfullyRead.lastMeaningfulReadAt, 500);
      expect(meaningfullyRead.lastOpenedAt, 500);
      expect(importedOnly.lastMeaningfulReadAt, isNull);
      expect(importedOnly.lastOpenedAt, isNull);
    });

    test('copyWith can update online metadata fields', () {
      final metadata = BookMetadata(
        id: 'book.epub',
        title: 'Old Title',
        author: 'Unknown Author',
      );

      final updated = metadata.copyWith(
        title: 'Clean Title',
        managedFilePath: '/app/books/old-title.epub',
        author: 'Known Author',
        embeddedTitle: 'Original Title',
        embeddedAuthor: 'Original Author',
        titleSource: 'open_library',
        authorSource: 'open_library',
        metadataSource: 'open_library',
        openLibraryCoverId: 456,
        metadataConfidence: 0.81,
      );

      expect(updated.title, 'Clean Title');
      expect(updated.managedFilePath, '/app/books/old-title.epub');
      expect(updated.author, 'Known Author');
      expect(updated.embeddedTitle, 'Original Title');
      expect(updated.embeddedAuthor, 'Original Author');
      expect(updated.titleSource, 'open_library');
      expect(updated.authorSource, 'open_library');
      expect(updated.metadataSource, 'open_library');
      expect(updated.openLibraryCoverId, 456);
      expect(updated.metadataConfidence, 0.81);
      expect(updated.lastReadTime, metadata.lastReadTime);
    });

    test(
      'can detect when current metadata can be reverted to EPUB metadata',
      () {
        final metadata = BookMetadata(
          id: 'book.epub',
          title: 'Updated Title',
          author: 'Updated Author',
          embeddedTitle: 'Original Title',
          embeddedAuthor: 'Original Author',
          titleSource: 'open_library',
          authorSource: 'open_library',
        );

        expect(metadata.canRevertToBookMetadata, isTrue);
      },
    );

    test('persists book-derived reader themes', () {
      final metadata = BookMetadata(
        id: 'book.epub',
        title: 'Cover Book',
        author: 'Known Author',
        theme: AppTheme.bookDark,
      );

      final restored = BookMetadata.fromMap(metadata.toMap());

      expect(restored.theme, AppTheme.bookDark);
    });

    test('persists Gutenberg source metadata', () {
      final metadata = BookMetadata(
        id: 'gutenberg_1342_pride-and-prejudice.epub',
        title: 'Pride and Prejudice',
        author: 'Jane Austen',
        source: 'gutenberg',
        gutenbergId: 1342,
        sourceUrl: 'https://www.gutenberg.org/ebooks/1342',
        downloadUrl: 'https://www.gutenberg.org/ebooks/1342.epub.images',
        importedAt: 123456,
        originalSourceTitle: 'Pride and Prejudice',
        originalSourceAuthor: 'Jane Austen',
      );

      final restored = BookMetadata.fromMap(metadata.toMap());

      expect(restored.source, 'gutenberg');
      expect(restored.gutenbergId, 1342);
      expect(restored.sourceUrl, 'https://www.gutenberg.org/ebooks/1342');
      expect(restored.downloadUrl, contains('1342.epub'));
      expect(restored.importedAt, 123456);
      expect(restored.originalSourceTitle, 'Pride and Prejudice');
      expect(restored.originalSourceAuthor, 'Jane Austen');
    });

    test('persists compact reading summary fields', () {
      final metadata = BookMetadata(
        id: 'book.epub',
        title: 'Summary Book',
        author: 'Known Author',
        readingSummary: const BookReadingSummary(
          chapterStartIndices: [0, 4],
          contentWordPrefixSums: [0, 10, 25],
        ),
      );

      final restored = BookMetadata.fromMap(metadata.toMap());

      expect(restored.readingSummary, isNotNull);
      expect(restored.readingSummary!.chapterNumberFor(4), 2);
      expect(restored.readingSummary!.remainingWordsAfter(0), 15);
    });

    test('builds reading summary from parsed chunks and chapters', () {
      final summary = BookReadingSummary.fromParsedBook(
        chunks: const [
          BookChunk(
            index: 0,
            type: BookChunkType.text,
            section: ChunkSection.frontMatter,
            text: 'ignored words',
          ),
          BookChunk(index: 1, type: BookChunkType.text, text: 'one two three'),
          BookChunk(index: 2, type: BookChunkType.image),
          BookChunk(index: 3, type: BookChunkType.text, text: 'four five'),
        ],
        chapters: const [
          ChapterInfo(title: 'Chapter One', chunkIndex: 1),
          ChapterInfo(title: 'Chapter Two', chunkIndex: 3),
        ],
      );

      expect(summary.chapterStartIndices, [1, 3]);
      expect(summary.totalContentWords, 5);
      expect(summary.remainingWordsAfter(1), 2);
      expect(summary.chapterNumberFor(3), 2);
    });
  });
}
