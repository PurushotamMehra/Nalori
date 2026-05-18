import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_memory_entry.dart';
import 'package:nalori/services/book_memory_entry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const bookId = 'book.epub';
  late BookMemoryEntryService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = BookMemoryEntryService(bookId: bookId);
  });

  group('BookMemoryEntryService', () {
    test('returns an empty list when no entries exist', () async {
      expect(await service.loadForBook(), isEmpty);
      expect(await service.countForBook(), 0);
    });

    test('fails closed to an empty list for malformed entry JSON', () async {
      SharedPreferences.setMockInitialValues({
        'book_memory_entries_$bookId': 'not json',
      });
      service = BookMemoryEntryService(bookId: bookId);

      expect(await service.loadForBook(), isEmpty);
    });

    test('does not create source entries for empty drafts', () async {
      final entry = await service.upsertSourceEntry(
        sourceType: BookMemorySourceType.bookmark,
        sourceId: '2:10',
        title: ' ',
        body: '\n',
      );

      expect(entry, isNull);
      expect(await service.loadForBook(), isEmpty);
    });

    test('keeps one entry per non-free source', () async {
      final first = await service.upsertSourceEntry(
        sourceType: BookMemorySourceType.highlight,
        sourceId: 'highlight-1',
        title: 'First',
        body: 'Body',
      );

      final second = await service.upsertSourceEntry(
        sourceType: BookMemorySourceType.highlight,
        sourceId: 'highlight-1',
        title: 'Second',
        body: 'Updated body',
      );

      final entries = await service.loadForBook();
      expect(entries, hasLength(1));
      expect(second!.id, first!.id);
      expect(entries.single.title, 'Second');
      expect(entries.single.body, 'Updated body');
      expect(entries.single.createdAtMs, first.createdAtMs);
      expect(
        entries.single.updatedAtMs,
        greaterThanOrEqualTo(first.updatedAtMs),
      );
    });

    test(
      'does not overwrite an existing source entry with empty fields',
      () async {
        final existing = await service.upsertSourceEntry(
          sourceType: BookMemorySourceType.note,
          sourceId: 'note-1',
          title: 'Keep',
          body: 'Keep this body',
        );

        final result = await service.upsertSourceEntry(
          sourceType: BookMemorySourceType.note,
          sourceId: 'note-1',
          title: '',
          body: '',
        );

        final loaded = await service.loadById(existing!.id);
        expect(result!.id, existing.id);
        expect(loaded!.title, 'Keep');
        expect(loaded.body, 'Keep this body');
      },
    );

    test('creates multiple free notes and ignores empty free notes', () async {
      final empty = await service.createFreeEntry(title: '', body: ' ');
      final first = await service.createFreeEntry(
        title: 'First free note',
        body: '',
      );
      final second = await service.createFreeEntry(
        title: '',
        body: 'Second free note body',
      );

      final entries = await service.loadForBook();
      expect(empty, isNull);
      expect(entries, hasLength(2));
      expect(first!.id, isNot(second!.id));
      expect(
        entries.map((entry) => entry.sourceType),
        everyElement(BookMemorySourceType.free),
      );
      expect(entries.map((entry) => entry.sourceId), everyElement(isNull));
    });

    test('updates existing free notes without creating a new entry', () async {
      final original = await service.createFreeEntry(
        title: 'Original',
        body: 'Draft',
      );

      final updated = await service.updateEntry(
        id: original!.id,
        title: 'Updated',
        body: 'Edited body',
      );

      final entries = await service.loadForBook();
      expect(updated!.id, original.id);
      expect(entries, hasLength(1));
      expect(entries.single.title, 'Updated');
      expect(entries.single.body, 'Edited body');
      expect(entries.single.createdAtMs, original.createdAtMs);
    });

    test('does not overwrite an existing entry with an empty update', () async {
      final original = await service.createFreeEntry(
        title: 'Original',
        body: 'Draft',
      );

      final result = await service.updateEntry(
        id: original!.id,
        title: '',
        body: '',
      );

      final loaded = await service.loadById(original.id);
      expect(result!.id, original.id);
      expect(loaded!.title, 'Original');
      expect(loaded.body, 'Draft');
    });

    test('loads entries by id and source', () async {
      final entry = await service.upsertSourceEntry(
        sourceType: BookMemorySourceType.word,
        sourceId: 'word-1',
        title: 'Word memory',
        body: 'Use this word.',
      );

      expect((await service.loadById(entry!.id))!.title, 'Word memory');
      expect(
        (await service.loadForSource(BookMemorySourceType.word, 'word-1'))!.id,
        entry.id,
      );
      expect(
        await service.hasEntryForSource(BookMemorySourceType.word, 'word-1'),
        isTrue,
      );
    });

    test('deletes entries by id and clears a book', () async {
      final first = await service.createFreeEntry(title: 'One', body: '');
      await service.createFreeEntry(title: 'Two', body: '');

      await service.deleteEntry(first!.id);
      expect(await service.countForBook(), 1);

      await service.clearForBook();
      expect(await service.loadForBook(), isEmpty);
    });
  });
}
