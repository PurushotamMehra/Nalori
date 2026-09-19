import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_list_semantics.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/services/book_authoritative_text_service.dart';
import 'package:nalori/services/book_character_occurrence_service.dart';
import 'package:nalori/services/book_memory_service.dart';
import 'package:nalori/services/derived_book_index_service.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/reader_character_match_service.dart';
import 'package:nalori/utils/reader_content_parser.dart';

const _identity = LazySectionIdentity(
  bookId: 'list-test',
  publicationFingerprint: 'publication',
  spineIndex: 0,
  href: 'chapter.xhtml',
  normalizedHref: 'chapter.xhtml',
  fullPath: 'chapter.xhtml',
  sourceChecksum: 'checksum',
  parserVersion: lazyParsedSectionParserVersion,
  dependencySignature: 'dependencies',
  dependencySchemaVersion: lazyParsedSectionDependencySchemaVersion,
);

void main() {
  ParsedSection parse(String body) => EpubParserService().parseLazySection(
    identity: _identity,
    html: '<html><body>$body</body></html>',
  );

  test('simple unordered direct-text items exclude generated bullets', () {
    final section = parse('<ul><li>First item</li><li>Second item</li></ul>');

    expect(section.chunks.map((chunk) => chunk.text), [
      'First item',
      'Second item',
    ]);
    expect(section.chunks.every((chunk) => !chunk.text!.contains('•')), isTrue);
    final first = section.chunks.first.listSemantics!;
    final second = section.chunks.last.listSemantics!;
    expect(first.listId, second.listId);
    expect(first.itemId, isNot(second.itemId));
    expect(first.ordered, isFalse);
    expect(first.depth, 0);
    expect(first.beginsItem, isTrue);
    expect(first.endsItem, isTrue);
    expect(
      section.chunks.first.effectiveSourceRanges.single.originalEndOffset,
      'First item'.length,
    );
  });

  test('paragraph child never produces a marker-only source chunk', () {
    final section = parse('<ul><li><p>Paragraph item</p></li></ul>');

    expect(section.chunks, hasLength(1));
    expect(section.chunks.single.text, 'Paragraph item');
    expect(section.chunks.single.listSemantics?.beginsItem, isTrue);
    expect(section.chunks.single.listSemantics?.endsItem, isTrue);
  });

  test('multi-paragraph item retains one stable item relationship', () {
    final section = parse(
      '<ul><li><p>First paragraph.</p><p>Second paragraph.</p></li></ul>',
    );

    expect(section.chunks.map((chunk) => chunk.text), [
      'First paragraph.',
      'Second paragraph.',
    ]);
    final first = section.chunks.first.listSemantics!;
    final second = section.chunks.last.listSemantics!;
    expect(first.itemId, second.itemId);
    expect(first.blockIndex, 0);
    expect(second.blockIndex, 1);
    expect(first.beginsItem, isTrue);
    expect(first.endsItem, isFalse);
    expect(second.beginsItem, isFalse);
    expect(second.endsItem, isTrue);
    expect(section.chunks.first.logicalParagraphId, '${first.itemId}#block-0');
    expect(section.chunks.last.logicalParagraphId, '${first.itemId}#block-1');
  });

  test('nested UL inside OL retains type depth and parent item', () {
    final section = parse('''
      <ol><li><p>Outer ordered</p><ul><li>Inner bullet</li></ul></li></ol>
    ''');
    final outer = section.chunks
        .firstWhere((chunk) => chunk.text == 'Outer ordered')
        .listSemantics!;
    final inner = section.chunks
        .firstWhere((chunk) => chunk.text == 'Inner bullet')
        .listSemantics!;

    expect(outer.ordered, isTrue);
    expect(inner.ordered, isFalse);
    expect(inner.depth, 1);
    expect(inner.parentListId, outer.listId);
    expect(inner.parentItemId, outer.itemId);
  });

  test('nested OL inside UL retains ordered child relationship', () {
    final section = parse('''
      <ul><li><p>Outer bullet</p><ol><li>Inner ordered</li></ol></li></ul>
    ''');
    final outer = section.chunks
        .firstWhere((chunk) => chunk.text == 'Outer bullet')
        .listSemantics!;
    final inner = section.chunks
        .firstWhere((chunk) => chunk.text == 'Inner ordered')
        .listSemantics!;

    expect(outer.ordered, isFalse);
    expect(inner.ordered, isTrue);
    expect(inner.resolvedOrdinal, 1);
    expect(inner.parentListId, outer.listId);
    expect(inner.parentItemId, outer.itemId);
  });

  test('ordered start value and marker type are deterministic', () {
    final section = parse('''
      <ol start="3" type="A">
        <li>Third</li><li value="7">Seventh</li><li>Eighth</li>
      </ol>
    ''');
    final semantics = section.chunks
        .map((chunk) => chunk.listSemantics!)
        .toList();

    expect(semantics.map((item) => item.resolvedOrdinal), [3, 7, 8]);
    expect(semantics.map((item) => item.orderedStart), [3, 3, 3]);
    expect(semantics[1].itemValue, 7);
    expect(
      semantics.every(
        (item) => item.markerType == BookListMarkerType.upperAlpha,
      ),
      isTrue,
    );
    expect(semantics.map(bookListMarkerText), ['C.', 'G.', 'H.']);
  });

  test('alphabetic and Roman marker functions cover HTML marker types', () {
    BookListSemantics semantics(BookListMarkerType type, int ordinal) =>
        BookListSemantics(
          listId: 'list',
          itemId: 'item',
          ordered: true,
          depth: 0,
          markerType: type,
          resolvedOrdinal: ordinal,
          orderedStart: 1,
          blockIndex: 0,
          beginsItem: true,
          endsItem: true,
        );

    expect(
      bookListMarkerText(semantics(BookListMarkerType.lowerAlpha, 27)),
      'aa.',
    );
    expect(
      bookListMarkerText(semantics(BookListMarkerType.upperAlpha, 27)),
      'AA.',
    );
    expect(
      bookListMarkerText(semantics(BookListMarkerType.lowerRoman, 14)),
      'xiv.',
    );
    expect(
      bookListMarkerText(semantics(BookListMarkerType.upperRoman, 14)),
      'XIV.',
    );
  });

  test('orphan malformed item falls back to normalized prose', () {
    final section = parse('<li><p>Readable fallback</p></li>');

    expect(section.chunks, hasLength(1));
    expect(section.chunks.single.text, 'Readable fallback');
    expect(section.chunks.single.listSemantics, isNull);
  });

  test('authoritative projection and derived index exclude markers', () {
    final section = parse('<ol start="9"><li>Ada arrived.</li></ol>');
    final chunk = section.chunks.single;
    final segment = buildDerivedIndexSegment(section);

    expect(authoritativeBookChunkText(chunk), 'Ada arrived.');
    expect(segment.paragraphs.single.text, 'Ada arrived.');
    expect(segment.paragraphs.single.text, isNot(contains('9.')));
    expect(
      readerSpeedReadText(authoritativeBookChunkTextOrEmpty(chunk)),
      'Ada arrived.',
    );
  });

  test('Book Memory and character matching use item-body offsets', () {
    final section = parse('<ol start="9"><li>Ada arrived.</li></ol>');
    final declaration = Highlight(
      id: 'ada-character',
      originalChunkIndex: section.chunks.single.index,
      startOffset: 0,
      endOffset: 3,
      text: 'Ada',
      type: HighlightType.character,
      createdAt: DateTime(2026, 8, 8),
    );
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'list-test',
      metadata: null,
      bookmarks: const [],
      highlights: [declaration],
      words: const [],
      chapters: const [],
    );
    final occurrences = BookMemoryService().updateOccurrenceIndexForTesting(
      StoredCharacterOccurrenceIndex.empty(),
      memory.characters,
      section.chunks,
    );
    final occurrence = occurrences['ada']!;

    expect(occurrence.count, 1);
    expect(occurrence.first?.startOffset, 0);
    expect(occurrence.first?.text, 'Ada');

    final plan = buildReaderCharacterMatchPlan(highlights: [declaration]);
    final matches = matchReaderCharacterSourceRanges(
      plan: plan,
      sourceChunks: section.chunks,
    );
    expect(matches.single.startOffset, 0);
    expect(matches.single.endOffset, 3);
  });

  test('ordinary prose identity and text remain unchanged without lists', () {
    final section = parse('<p>First prose.</p><p>Second prose.</p>');

    expect(section.chunks.map((chunk) => chunk.text), [
      'First prose.',
      'Second prose.',
    ]);
    expect(section.chunks.map((chunk) => chunk.logicalParagraphId), [
      'chapter.xhtml#paragraph-0',
      'chapter.xhtml#paragraph-1',
    ]);
    expect(
      section.chunks.every((chunk) => chunk.listSemantics == null),
      isTrue,
    );
  });

  test(
    'ordinary prose identity after a block-first list item stays stable',
    () {
      final section = parse(
        '<p>Before.</p><ul><li><p>Item.</p></li></ul><p>After.</p>',
      );
      final after = section.chunks.singleWhere(
        (chunk) => chunk.text == 'After.',
      );

      expect(after.logicalParagraphId, 'chapter.xhtml#paragraph-3');
    },
  );
}
