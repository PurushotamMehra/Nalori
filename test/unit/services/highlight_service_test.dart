import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/services/highlight_service.dart';

void main() {
  late HighlightService highlightService;
  const testBookId = 'test-book-1';

  Highlight createHighlight({
    String id = 'h1',
    int originalChunkIndex = 0,
    int startOffset = 0,
    int endOffset = 10,
    int colorIndex = 0,
    int? colorValue,
    HighlightType type = HighlightType.highlight,
    String text = 'Test highlight',
    String? note,
  }) {
    return Highlight(
      id: id,
      originalChunkIndex: originalChunkIndex,
      startOffset: startOffset,
      endOffset: endOffset,
      text: text,
      colorIndex: colorIndex,
      colorValue: colorValue,
      type: type,
      note: note,
      createdAt: DateTime(2026, 4, 9),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    highlightService = HighlightService(bookId: testBookId);
  });

  group('HighlightService', () {
    test('returns empty list when no highlights exist', () async {
      expect(await highlightService.load(), isEmpty);
    });

    test('adds and loads persisted highlights', () async {
      await highlightService.add(createHighlight());
      await highlightService.add(
        createHighlight(id: 'h2', originalChunkIndex: 2),
      );

      final loaded = await highlightService.load();

      expect(loaded, hasLength(2));
      expect(loaded.map((item) => item.id), containsAll(['h1', 'h2']));
    });

    test('replaces overlapping highlights of the same type', () async {
      await highlightService.add(createHighlight(id: 'old', endOffset: 20));

      final updated = await highlightService.add(
        createHighlight(id: 'new', startOffset: 5, endOffset: 18),
      );

      expect(updated, hasLength(1));
      expect(updated.single.id, 'new');
    });

    test('keeps overlapping highlights when semantic types differ', () async {
      await highlightService.add(createHighlight(id: 'highlight'));

      final updated = await highlightService.add(
        createHighlight(id: 'note', type: HighlightType.note),
      );

      expect(updated, hasLength(2));
      expect(
        updated.map((item) => item.type),
        containsAll([HighlightType.highlight, HighlightType.note]),
      );
    });

    test('updates saved color values', () async {
      final original = createHighlight(id: 'color');
      await highlightService.add(original);

      final updated = await highlightService.update(
        original.copyWith(
          colorIndex: 2,
          colorValue: const Color(0xFF009688).toARGB32(),
        ),
      );

      expect(updated.single.color, const Color(0xFF009688));
      expect(updated.single.colorIndex, 2);
    });

    test('updates saved notes', () async {
      await highlightService.add(createHighlight(id: 'note-id'));

      final updated = await highlightService.updateNote('note-id', 'New note');

      expect(updated.single.note, 'New note');
    });

    test(
      'updates notes across grouped highlight segments with the same id',
      () async {
        await highlightService.add(
          createHighlight(
            id: 'grouped-note',
            originalChunkIndex: 0,
            startOffset: 0,
            endOffset: 5,
          ),
        );
        await highlightService.add(
          createHighlight(
            id: 'grouped-note',
            originalChunkIndex: 1,
            startOffset: 0,
            endOffset: 5,
          ),
        );

        final updated = await highlightService.updateNote(
          'grouped-note',
          'Linked note',
        );

        expect(updated, hasLength(2));
        expect(updated.every((item) => item.note == 'Linked note'), isTrue);
      },
    );

    test('persists highlight-backed notes when reloaded', () async {
      await highlightService.add(
        createHighlight(
          id: 'saved-note',
          text: 'Marked line',
          note: 'Remember this line',
        ),
      );

      final loaded = await highlightService.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.type, HighlightType.highlight);
      expect(loaded.single.note, 'Remember this line');
      expect(loaded.single.hasNote, isTrue);
    });

    test(
      'updates color across grouped highlight segments with the same id',
      () async {
        await highlightService.add(
          createHighlight(
            id: 'grouped-color',
            originalChunkIndex: 0,
            startOffset: 0,
            endOffset: 5,
          ),
        );
        await highlightService.add(
          createHighlight(
            id: 'grouped-color',
            originalChunkIndex: 1,
            startOffset: 0,
            endOffset: 5,
          ),
        );

        final updated = await highlightService.update(
          createHighlight(
            id: 'grouped-color',
            colorIndex: 2,
            colorValue: const Color(0xFF009688).toARGB32(),
          ),
        );

        expect(updated, hasLength(2));
        expect(
          updated.every((item) => item.color == const Color(0xFF009688)),
          isTrue,
        );
      },
    );

    test('removes highlights by id', () async {
      await highlightService.add(createHighlight(id: 'delete-me'));

      final updated = await highlightService.remove('delete-me');

      expect(updated, isEmpty);
    });

    test('filters highlights by original chunk', () async {
      await highlightService.add(createHighlight());
      await highlightService.add(
        createHighlight(id: 'h2', originalChunkIndex: 3),
      );

      final all = await highlightService.load();

      expect(highlightService.getForChunk(all, 3).single.id, 'h2');
    });
  });
}
