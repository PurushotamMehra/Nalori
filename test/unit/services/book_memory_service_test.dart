import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/book_memory_entry.dart';
import 'package:nalori/models/book_metadata.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/saved_word.dart';
import 'package:nalori/services/book_character_occurrence_service.dart';
import 'package:nalori/services/book_memory_service.dart';

void main() {
  Highlight highlight({
    required String id,
    required String text,
    HighlightType type = HighlightType.highlight,
    String? note,
    int chunkIndex = 2,
    int startOffset = 0,
    DateTime? createdAt,
  }) {
    return Highlight(
      id: id,
      originalChunkIndex: chunkIndex,
      startOffset: startOffset,
      endOffset: text.length,
      text: text,
      type: type,
      note: note,
      createdAt: createdAt ?? DateTime(2026, 5),
    );
  }

  test('filters highlights, notes, and character groups', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: BookMetadata(
        id: 'book.epub',
        title: 'Test Book',
        author: 'Test Author',
      ),
      bookmarks: const [],
      highlights: [
        highlight(id: 'h1', text: 'Regular'),
        highlight(id: 'h2', text: 'With note', note: 'Remember this'),
        highlight(
          id: 'c1',
          text: 'Elizabeth Bennet',
          type: HighlightType.character,
        ),
        highlight(
          id: 'c2',
          text: ' elizabeth   bennet ',
          type: HighlightType.character,
          chunkIndex: 4,
        ),
      ],
      words: const [],
      chapters: const [],
    );

    expect(memory.highlights.map((item) => item.id), ['h1']);
    expect(memory.notes.map((item) => item.id), ['h2']);
    expect(memory.characters, hasLength(1));
    expect(memory.characters.single.name, 'Elizabeth Bennet');
    expect(memory.characters.single.count, 2);
  });

  test('orders character moments by reading location', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        highlight(
          id: 'c-late',
          text: 'Jane',
          type: HighlightType.character,
          chunkIndex: 8,
          createdAt: DateTime(2026, 5, 2),
        ),
        highlight(
          id: 'c-offset',
          text: 'Jane',
          type: HighlightType.character,
          chunkIndex: 3,
          startOffset: 12,
          createdAt: DateTime(2026, 5, 3),
        ),
        highlight(
          id: 'c-first',
          text: 'Jane',
          type: HighlightType.character,
          chunkIndex: 3,
          startOffset: 4,
          createdAt: DateTime(2026, 5),
        ),
      ],
      words: const [],
      chapters: const [],
    );

    final character = memory.characters.single;
    expect(character.highlights.map((item) => item.id), [
      'c-first',
      'c-offset',
      'c-late',
    ]);
    expect(character.firstMarked.id, 'c-first');
    expect(character.latestMarked.id, 'c-offset');
  });

  test('groups full character names with their individual name parts', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        highlight(
          id: 'c1',
          text: 'Elizabeth Bennet',
          type: HighlightType.character,
        ),
        highlight(
          id: 'c2',
          text: 'Elizabeth',
          type: HighlightType.character,
          chunkIndex: 4,
        ),
      ],
      words: const [],
      chapters: const [],
    );

    expect(memory.characters, hasLength(1));
    expect(memory.characters.single.name, 'Elizabeth Bennet');
    expect(
      memory.characters.single.aliases,
      containsAll(['Elizabeth Bennet', 'Elizabeth', 'Bennet']),
    );
    expect(memory.characters.single.count, 2);
  });

  test('links highlights and notes by selected book text only', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        highlight(
          id: 'c1',
          text: 'Elizabeth Bennet',
          type: HighlightType.character,
        ),
        highlight(id: 'h1', text: 'Elizabeth crossed the room'),
        highlight(
          id: 'n1',
          text: 'The room was quiet',
          note: 'Elizabeth is hiding something',
        ),
        highlight(id: 'n2', text: 'Bennet smiled', note: 'Suspicious'),
      ],
      words: const [],
      chapters: const [],
    );

    final character = memory.characters.single;
    expect(character.linkedHighlights.map((item) => item.id), ['h1']);
    expect(character.linkedNotes.map((item) => item.id), ['n2']);
    expect(character.linkedInputCount, 2);
  });

  test('attaches stored first and last character occurrences', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        highlight(
          id: 'c1',
          text: 'Elizabeth Bennet',
          type: HighlightType.character,
        ),
      ],
      words: const [],
      occurrenceIndex: const StoredCharacterOccurrenceIndex(
        occurrences: {
          'elizabeth bennet': StoredCharacterOccurrence(
            aliases: ['Elizabeth Bennet', 'Elizabeth', 'Bennet'],
            first: CharacterOccurrencePosition(
              chunkIndex: 1,
              startOffset: 4,
              endOffset: 13,
              text: 'Elizabeth',
            ),
            last: CharacterOccurrencePosition(
              chunkIndex: 8,
              startOffset: 12,
              endOffset: 18,
              text: 'Bennet',
            ),
            count: 6,
          ),
        },
      ),
      chapters: const [],
    );

    final character = memory.characters.single;
    expect(character.firstOccurrence?.chunkIndex, 1);
    expect(character.lastOccurrence?.chunkIndex, 8);
    expect(character.occurrenceCount, 6);
  });

  test(
    'occurrence scan ignores Project Gutenberg license boilerplate',
    () async {
      final service = BookMemoryService();
      final memory = BookMemorySnapshot.fromStorage(
        bookId: 'book.epub',
        metadata: null,
        bookmarks: const [],
        highlights: [
          highlight(
            id: 'c1',
            text: 'Jane',
            type: HighlightType.character,
            chunkIndex: 1,
          ),
        ],
        words: const [],
        chapters: const [],
      );

      final updated = service.updateOccurrenceIndexForTesting(
        StoredCharacterOccurrenceIndex.empty(),
        memory.characters,
        const [
          BookChunk(index: 0, type: BookChunkType.text, text: 'Jane arrived.'),
          BookChunk(index: 1, type: BookChunkType.text, text: 'Jane left.'),
          BookChunk(
            index: 2,
            type: BookChunkType.text,
            text: 'THE FULL PROJECT GUTENBERG™ LICENSE',
          ),
          BookChunk(
            index: 3,
            type: BookChunkType.text,
            text: 'Jane appears in the license boilerplate.',
          ),
        ],
      );

      final occurrence = updated['jane']!;
      expect(occurrence.count, 2);
      expect(occurrence.last?.chunkIndex, 1);
    },
  );

  test(
    'occurrence scan stops at alternate Project Gutenberg license marker',
    () {
      final service = BookMemoryService();
      final memory = BookMemorySnapshot.fromStorage(
        bookId: 'book.epub',
        metadata: null,
        bookmarks: const [],
        highlights: [
          highlight(
            id: 'c1',
            text: 'Jane',
            type: HighlightType.character,
            chunkIndex: 1,
          ),
        ],
        words: const [],
        chapters: const [],
      );

      final updated = service.updateOccurrenceIndexForTesting(
        StoredCharacterOccurrenceIndex.empty(),
        memory.characters,
        const [
          BookChunk(index: 0, type: BookChunkType.text, text: 'Jane arrived.'),
          BookChunk(index: 1, type: BookChunkType.text, text: 'Jane left.'),
          BookChunk(
            index: 2,
            type: BookChunkType.text,
            text: '*** START: FULL LICENSE ***',
          ),
          BookChunk(
            index: 3,
            type: BookChunkType.text,
            text: 'Jane appears in redistribution terms.',
          ),
        ],
      );

      final occurrence = updated['jane']!;
      expect(occurrence.count, 2);
      expect(occurrence.last?.chunkIndex, 1);
    },
  );

  test('occurrence scan stops before post-story table of contents', () {
    final service = BookMemoryService();
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        highlight(
          id: 'c1',
          text: 'Jane',
          type: HighlightType.character,
          chunkIndex: 1,
        ),
      ],
      words: const [],
      chapters: const [],
    );

    final updated = service.updateOccurrenceIndexForTesting(
      StoredCharacterOccurrenceIndex.empty(),
      memory.characters,
      const [
        BookChunk(index: 0, type: BookChunkType.text, text: 'Jane arrived.'),
        BookChunk(index: 1, type: BookChunkType.text, text: 'Jane left.'),
        BookChunk(
          index: 2,
          type: BookChunkType.text,
          text: 'Table of Contents',
          isHeading: true,
        ),
        BookChunk(
          index: 3,
          type: BookChunkType.text,
          text: 'Jane and the Appendix',
        ),
      ],
    );

    final occurrence = updated['jane']!;
    expect(occurrence.count, 2);
    expect(occurrence.last?.chunkIndex, 1);
  });

  test('occurrence scan does not count initials as standalone aliases', () {
    final service = BookMemoryService();
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        highlight(
          id: 'c1',
          text: 'G. A. Raymond',
          type: HighlightType.character,
          chunkIndex: 0,
        ),
      ],
      words: const [],
      chapters: const [],
    );

    final updated = service.updateOccurrenceIndexForTesting(
      StoredCharacterOccurrenceIndex.empty(),
      memory.characters,
      const [
        BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: 'G. A. Raymond entered quietly.',
        ),
        BookChunk(
          index: 1,
          type: BookChunkType.text,
          text: 'A section labelled G. should not count as the character.',
        ),
        BookChunk(
          index: 2,
          type: BookChunkType.text,
          text: 'Raymond returned before the chapter ended.',
        ),
      ],
    );

    final occurrence = updated['g. a. raymond']!;
    expect(occurrence.count, 2);
    expect(occurrence.last?.chunkIndex, 2);
    expect(occurrence.last?.text, 'Raymond');
  });

  test('groups multi-segment highlights and notes by logical id', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        highlight(id: 'h1', text: 'First'),
        highlight(id: 'h1', text: 'Second'),
        highlight(id: 'n1', text: 'Selected', note: 'Reader note'),
        highlight(id: 'n1', text: 'text', note: 'Reader note'),
      ],
      words: const [],
      chapters: const [],
    );

    expect(memory.highlights, hasLength(1));
    expect(memory.highlights.single.id, 'h1');
    expect(memory.highlights.single.text, 'First Second');
    expect(memory.notes, hasLength(1));
    expect(memory.notes.single.id, 'n1');
    expect(memory.notes.single.text, 'Selected text');
    expect(memory.notes.single.note, 'Reader note');
  });

  test('keeps saved words with and without source locations', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: const [],
      words: const [
        SavedWord(
          id: 'w1',
          word: 'lucid',
          meaning: 'Clear',
          bookId: 'book.epub',
          timestamp: 1,
          originalChunkIndex: 3,
        ),
        SavedWord(
          id: 'w2',
          word: 'opaque',
          meaning: 'Not clear',
          bookId: 'book.epub',
          timestamp: 2,
        ),
      ],
      chapters: const [],
    );

    expect(memory.words, hasLength(2));
    expect(memory.words.first.originalChunkIndex, 3);
    expect(memory.words.last.originalChunkIndex, isNull);
  });

  test('indexes entries by source and keeps orphaned writing', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: const [],
      words: const [],
      entries: const [
        BookMemoryEntry(
          id: 'entry-1',
          bookId: 'book.epub',
          sourceType: BookMemorySourceType.bookmark,
          sourceId: '2:0',
          title: 'Bookmark thought',
          body: 'Still useful after the source is gone.',
          createdAtMs: 100,
          updatedAtMs: 200,
        ),
        BookMemoryEntry(
          id: 'entry-2',
          bookId: 'book.epub',
          sourceType: BookMemorySourceType.free,
          sourceId: null,
          title: 'Free note',
          body: '',
          createdAtMs: 50,
          updatedAtMs: 300,
        ),
      ],
      chapters: const [],
    );

    expect(
      memory.entryForSource(BookMemorySourceType.bookmark, '2:0')!.id,
      'entry-1',
    );
    expect(
      memory.hasEntryForSource(BookMemorySourceType.bookmark, '2:0'),
      true,
    );
    expect(memory.recentWrittenEntries.map((entry) => entry.id), [
      'entry-2',
      'entry-1',
    ]);
  });

  test('uses the same normalized source key for character entries', () {
    final sourceId = BookMemorySnapshot.characterSourceId(
      ' Elizabeth   Bennet ',
    );
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        highlight(
          id: 'c1',
          text: 'Elizabeth Bennet',
          type: HighlightType.character,
        ),
      ],
      words: const [],
      entries: [
        BookMemoryEntry(
          id: 'entry-1',
          bookId: 'book.epub',
          sourceType: BookMemorySourceType.character,
          sourceId: sourceId,
          title: 'Character thought',
          body: '',
          createdAtMs: 100,
          updatedAtMs: 100,
        ),
      ],
      chapters: const [],
    );

    expect(sourceId, 'elizabeth bennet');
    expect(memory.characters.single.name, 'Elizabeth Bennet');
    expect(
      memory.entryForSource(BookMemorySourceType.character, sourceId)!.title,
      'Character thought',
    );
  });
}
