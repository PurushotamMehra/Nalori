import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_memory_entry.dart';

void main() {
  group('BookMemoryEntry', () {
    test('serializes and deserializes source entries', () {
      const entry = BookMemoryEntry(
        id: 'entry-1',
        bookId: 'book.epub',
        sourceType: BookMemorySourceType.highlight,
        sourceId: 'highlight-1',
        title: 'A thought',
        body: 'This matters later.',
        createdAtMs: 100,
        updatedAtMs: 200,
      );

      final decoded = BookMemoryEntry.decodeList(
        BookMemoryEntry.encodeList([entry]),
      );

      expect(decoded, hasLength(1));
      expect(decoded.single.id, 'entry-1');
      expect(decoded.single.bookId, 'book.epub');
      expect(decoded.single.sourceType, BookMemorySourceType.highlight);
      expect(decoded.single.sourceId, 'highlight-1');
      expect(decoded.single.title, 'A thought');
      expect(decoded.single.body, 'This matters later.');
      expect(decoded.single.createdAtMs, 100);
      expect(decoded.single.updatedAtMs, 200);
    });

    test('supports free book notes without a source id', () {
      const entry = BookMemoryEntry(
        id: 'entry-1',
        bookId: 'book.epub',
        sourceType: BookMemorySourceType.free,
        sourceId: null,
        title: 'Book note',
        body: '',
        createdAtMs: 100,
        updatedAtMs: 100,
      );

      final decoded = BookMemoryEntry.fromJson(entry.toJson());

      expect(decoded.sourceType, BookMemorySourceType.free);
      expect(decoded.sourceId, isNull);
      expect(decoded.isFree, isTrue);
      expect(decoded.isEmpty, isFalse);
    });
  });
}
