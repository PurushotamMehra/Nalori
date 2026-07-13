import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nalori/services/bookmark_service.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/models/stable_book_location.dart';

void main() {
  late BookmarkService bookmarkService;
  const testBookId = 'test-book-1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bookmarkService = BookmarkService(bookId: testBookId);
  });

  group('BookmarkService', () {
    group('load', () {
      test('should return empty list when no bookmarks exist', () async {
        final result = await bookmarkService.load();
        expect(result, isEmpty);
      });

      test('should return bookmarks when they exist', () async {
        final bookmarks = [
          Bookmark(chunkIndex: 0, name: 'Bookmark 1'),
          Bookmark(chunkIndex: 5, name: 'Bookmark 2'),
        ];
        await bookmarkService.restoreAll(bookmarks);

        final result = await bookmarkService.load();

        expect(result.length, 2);
        expect(result[0].chunkIndex, 0);
        expect(result[1].chunkIndex, 5);
      });
    });

    group('add', () {
      test('should add a new bookmark', () async {
        final result = await bookmarkService.add(10);

        expect(result.length, 1);
        expect(result[0].chunkIndex, 10);
        expect(result[0].originalStartOffset, 0);
        expect(result[0].name, 'Bookmark 1');
      });

      test('should add a bookmark at a source offset', () async {
        final result = await bookmarkService.add(
          10,
          originalStartOffset: 42,
          previewText: 'Visible page text',
        );

        expect(result.length, 1);
        expect(result[0].chunkIndex, 10);
        expect(result[0].originalStartOffset, 42);
        expect(result[0].previewText, 'Visible page text');
      });

      test('should generate sequential bookmark names', () async {
        await bookmarkService.add(0);
        await bookmarkService.add(5);
        await bookmarkService.add(10);

        final result = await bookmarkService.load();

        expect(result.length, 3);
        expect(result[0].name, 'Bookmark 3');
        expect(result[1].name, 'Bookmark 2');
        expect(result[2].name, 'Bookmark 1');
      });

      test('should not add duplicate bookmark at same position', () async {
        await bookmarkService.add(5);
        final result = await bookmarkService.add(5);

        expect(result.length, 1);
      });

      test('should allow same chunk at different source offsets', () async {
        await bookmarkService.add(5);
        final result = await bookmarkService.add(5, originalStartOffset: 42);

        expect(result.length, 2);
        expect(result.map((b) => b.originalStartOffset), containsAll([0, 42]));
      });
    });

    group('remove', () {
      test('should remove a bookmark at specified position', () async {
        await bookmarkService.add(0);
        await bookmarkService.add(5);
        await bookmarkService.add(10);

        final result = await bookmarkService.remove(5);

        expect(result.length, 2);
        expect(result.any((b) => b.chunkIndex == 5), false);
      });

      test('should remove only the matching source offset', () async {
        await bookmarkService.add(5);
        await bookmarkService.add(5, originalStartOffset: 42);

        final result = await bookmarkService.remove(5, originalStartOffset: 42);

        expect(result.length, 1);
        expect(result[0].chunkIndex, 5);
        expect(result[0].originalStartOffset, 0);
      });

      test('should return current list if bookmark not found', () async {
        await bookmarkService.add(0);
        final result = await bookmarkService.remove(999);

        expect(result.length, 1);
      });
    });

    group('rename', () {
      test('should rename a bookmark', () async {
        await bookmarkService.add(5);

        final result = await bookmarkService.rename(5, 'My Important Place');

        expect(result[0].name, 'My Important Place');
      });
    });

    group('update', () {
      test('should save arbitrary bookmark color values', () async {
        await bookmarkService.add(5);

        final updated = await bookmarkService.update(
          5,
          colorIndex: 2,
          colorValue: bookmarkColorValue(const Color(0xFF123456)),
        );

        expect(updated.single.colorIndex, 2);
        expect(
          updated.single.colorValue,
          bookmarkColorValue(const Color(0xFF123456)),
        );
        expect(updated.single.color, const Color(0xFF123456));
      });

      test(
        'should clear custom color values when saving fixed colors',
        () async {
          await bookmarkService.add(
            5,
            colorValue: bookmarkColorValue(const Color(0xFF123456)),
          );

          final updated = await bookmarkService.update(
            5,
            colorIndex: 2,
            clearColorValue: true,
          );

          expect(updated.single.colorValue, isNull);
          expect(updated.single.color, kBookmarkColors[2]);
        },
      );
    });

    group('default color', () {
      test('should load legacy default bookmark color index', () async {
        SharedPreferences.setMockInitialValues({'default_bookmark_color': 2});
        bookmarkService = BookmarkService(bookId: testBookId);

        expect(await bookmarkService.loadDefaultColor(), kBookmarkColors[2]);
      });

      test('should persist custom default bookmark color values', () async {
        await bookmarkService.saveDefaultColor(const Color(0xFF123456));

        expect(
          await bookmarkService.loadDefaultColor(),
          const Color(0xFF123456),
        );
      });

      test(
        'saving a fixed default index clears custom default color value',
        () async {
          await bookmarkService.saveDefaultColor(const Color(0xFF123456));
          await bookmarkService.saveDefaultColorIndex(3);

          expect(await bookmarkService.loadDefaultColor(), kBookmarkColors[3]);
        },
      );
    });

    group('clearAll', () {
      test('should remove all bookmarks', () async {
        await bookmarkService.add(0);
        await bookmarkService.add(5);
        await bookmarkService.add(10);

        final result = await bookmarkService.clearAll();

        expect(result, isEmpty);
      });
    });

    group('restoreAll', () {
      test('should restore bookmarks from list', () async {
        final bookmarks = [
          Bookmark(chunkIndex: 1, name: 'Restored 1'),
          Bookmark(chunkIndex: 2, name: 'Restored 2'),
        ];

        final result = await bookmarkService.restoreAll(bookmarks);

        expect(result.length, 2);
        expect(result[0].name, 'Restored 1');
      });
    });

    group('isBookmarked', () {
      test('should return true when chunk is bookmarked', () async {
        await bookmarkService.add(5);
        final bookmarks = await bookmarkService.load();

        final result = bookmarkService.isBookmarked(bookmarks, 5);

        expect(result, true);
      });

      test('should match exact source offset when provided', () async {
        await bookmarkService.add(5, originalStartOffset: 42);
        final bookmarks = await bookmarkService.load();

        final exact = bookmarkService.isBookmarked(
          bookmarks,
          5,
          originalStartOffset: 42,
        );
        final differentOffset = bookmarkService.isBookmarked(
          bookmarks,
          5,
          originalStartOffset: 7,
        );

        expect(exact, true);
        expect(differentOffset, false);
      });

      test('should return false when chunk is not bookmarked', () async {
        await bookmarkService.add(5);
        final bookmarks = await bookmarkService.load();

        final result = bookmarkService.isBookmarked(bookmarks, 10);

        expect(result, false);
      });
    });

    test(
      'successful migration adds stable target without dropping legacy fields',
      () async {
        final createdAt = DateTime(2026, 7, 12);
        final legacy = Bookmark(
          chunkIndex: 42,
          originalStartOffset: 7,
          name: 'Legacy',
          createdAt: createdAt,
        );
        await bookmarkService.restoreAll([legacy]);
        const location = StableBookLocation(
          bookId: testBookId,
          spineIndex: 2,
          href: 'chapter.xhtml',
          sourceChecksum: 'checksum',
          publicationFingerprint: 'publication',
          sectionProgression: 0.5,
        );

        final migrated = await bookmarkService.migrateStableLocation(
          legacy,
          location,
        );

        expect(migrated.single.chunkIndex, 42);
        expect(migrated.single.originalStartOffset, 7);
        expect(migrated.single.stableLocation, location);
      },
    );
  });
}
