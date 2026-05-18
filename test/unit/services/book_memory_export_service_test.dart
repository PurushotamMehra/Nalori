import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_memory_entry.dart';
import 'package:nalori/models/book_metadata.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/saved_word.dart';
import 'package:nalori/services/book_character_occurrence_service.dart';
import 'package:nalori/services/book_memory_export_service.dart';
import 'package:nalori/services/book_memory_service.dart';

void main() {
  final exportService = BookMemoryExportService();

  test('builds Markdown with all memory sections', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: BookMetadata(
        id: 'book.epub',
        title: 'Test Book',
        author: 'Test Author',
        lastReadIndex: 4,
        totalChunks: 10,
        lastReadTime: DateTime(2026, 5, 2).millisecondsSinceEpoch,
      ),
      bookmarks: [
        Bookmark(
          chunkIndex: 1,
          name: 'Bookmark 1',
          createdAt: DateTime(2026, 5),
          previewText: 'Opening line',
        ),
      ],
      highlights: [
        Highlight(
          id: 'h1',
          originalChunkIndex: 2,
          startOffset: 0,
          endOffset: 9,
          text: 'A thought',
          createdAt: DateTime(2026, 5),
        ),
        Highlight(
          id: 'n1',
          originalChunkIndex: 3,
          startOffset: 0,
          endOffset: 7,
          text: 'A quote',
          note: 'My note',
          createdAt: DateTime(2026, 5),
        ),
        Highlight(
          id: 'c1',
          originalChunkIndex: 4,
          startOffset: 0,
          endOffset: 4,
          text: 'Jane',
          type: HighlightType.character,
          createdAt: DateTime(2026, 5),
        ),
      ],
      words: const [
        SavedWord(
          id: 'w1',
          word: 'lucid',
          meaning: 'Clear',
          bookId: 'book.epub',
          timestamp: 1777593600000,
          contextSentence: 'A lucid sentence.',
          originalChunkIndex: 5,
        ),
      ],
      entries: const [
        BookMemoryEntry(
          id: 'e1',
          bookId: 'book.epub',
          sourceType: BookMemorySourceType.free,
          sourceId: null,
          title: 'Free thought',
          body: 'A book-level reflection.',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        BookMemoryEntry(
          id: 'e2',
          bookId: 'book.epub',
          sourceType: BookMemorySourceType.highlight,
          sourceId: 'h1',
          title: 'Linked highlight thought',
          body: 'This is linked.',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
        BookMemoryEntry(
          id: 'e3',
          bookId: 'book.epub',
          sourceType: BookMemorySourceType.word,
          sourceId: 'missing-word',
          title: 'Orphaned thought',
          body: 'The source was deleted.',
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      ],
      occurrenceIndex: const StoredCharacterOccurrenceIndex(
        occurrences: {
          'jane': StoredCharacterOccurrence(
            aliases: ['Jane'],
            first: CharacterOccurrencePosition(
              chunkIndex: 1,
              startOffset: 2,
              endOffset: 6,
              text: 'Jane',
            ),
            last: CharacterOccurrencePosition(
              chunkIndex: 4,
              startOffset: 0,
              endOffset: 4,
              text: 'Jane',
            ),
            count: 3,
          ),
        },
      ),
      chapters: const [],
    );

    final markdown = exportService.buildMarkdown(memory);

    expect(markdown, contains('# Test Book'));
    expect(markdown, contains('Author: Test Author'));
    expect(markdown, contains('Progress: 44%'));
    expect(markdown, contains('## Book Notes'));
    expect(markdown, contains('Free thought'));
    expect(markdown, contains('## Bookmarks'));
    expect(markdown, contains('Bookmark 1'));
    expect(markdown, contains('## Highlights'));
    expect(markdown, contains('A thought'));
    expect(markdown, contains('Linked highlight thought'));
    expect(markdown, contains('## Notes'));
    expect(markdown, contains('My note'));
    expect(markdown, contains('## Saved Words'));
    expect(markdown, contains('lucid: Clear'));
    expect(markdown, contains('## Character Tags'));
    expect(markdown, contains('Jane (1 marked, 3 mentions)'));
    expect(markdown, contains('First occurrence: Page/Chunk 2'));
    expect(markdown, contains('Last occurrence: Page/Chunk 5'));
    expect(markdown, contains('## Unlinked Thoughts'));
    expect(markdown, contains('Orphaned thought'));
  });

  test('renders empty Markdown sections', () {
    final markdown = exportService.buildMarkdown(
      BookMemorySnapshot.empty(bookId: 'empty.epub'),
    );

    expect(RegExp(r'None\.').allMatches(markdown), hasLength(6));
    expect(markdown, contains('Last read: Never'));
  });
}
