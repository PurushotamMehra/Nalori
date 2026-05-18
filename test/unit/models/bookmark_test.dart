import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/bookmark.dart';

void main() {
  group('Bookmark', () {
    group('constructor', () {
      test('should create bookmark with required parameters', () {
        final bookmark = Bookmark(chunkIndex: 5, name: 'Test Bookmark');

        expect(bookmark.chunkIndex, 5);
        expect(bookmark.originalStartOffset, 0);
        expect(bookmark.name, 'Test Bookmark');
        expect(bookmark.createdAt, isNotNull);
        expect(bookmark.color, kBookmarkColors.first);
      });

      test('should create bookmark with source offset and preview', () {
        final bookmark = Bookmark(
          chunkIndex: 5,
          originalStartOffset: 42,
          name: 'Test Bookmark',
          previewText: 'Visible page text',
        );

        expect(bookmark.chunkIndex, 5);
        expect(bookmark.originalStartOffset, 42);
        expect(bookmark.previewText, 'Visible page text');
        expect(bookmark.locationKey, '5:42');
      });

      test('should accept custom createdAt', () {
        final customDate = DateTime(2026, 3, 11);
        final bookmark = Bookmark(
          chunkIndex: 5,
          name: 'Test',
          createdAt: customDate,
        );

        expect(bookmark.createdAt, customDate);
      });
    });

    group('copyWith', () {
      test('should copy with new chunkIndex', () {
        final original = Bookmark(chunkIndex: 5, name: 'Original');
        final copy = original.copyWith(chunkIndex: 10);

        expect(copy.chunkIndex, 10);
        expect(copy.originalStartOffset, 0);
        expect(copy.name, 'Original');
      });

      test('should copy with new name', () {
        final original = Bookmark(chunkIndex: 5, name: 'Original');
        final copy = original.copyWith(name: 'New Name');

        expect(copy.chunkIndex, 5);
        expect(copy.name, 'New Name');
      });

      test('should copy with custom color and clear it', () {
        final original = Bookmark(chunkIndex: 5, name: 'Original');
        final custom = original.copyWith(
          colorValue: bookmarkColorValue(const Color(0xFF123456)),
        );
        final preset = custom.copyWith(colorIndex: 2, clearColorValue: true);

        expect(custom.color, const Color(0xFF123456));
        expect(preset.color, kBookmarkColors[2]);
      });
    });

    group('serialization', () {
      test('should convert to JSON', () {
        final bookmark = Bookmark(
          chunkIndex: 5,
          name: 'Test',
          createdAt: DateTime(2026, 3, 11, 10, 30),
        );

        final json = bookmark.toJson();

        expect(json['chunkIndex'], 5);
        expect(json['originalStartOffset'], 0);
        expect(json['name'], 'Test');
        expect(json['createdAt'], contains('2026-03-11'));
        expect(json['colorIndex'], 0);
      });

      test('should convert source offset and preview to JSON', () {
        final bookmark = Bookmark(
          chunkIndex: 5,
          originalStartOffset: 42,
          name: 'Test',
          previewText: 'Visible page text',
          createdAt: DateTime(2026, 3, 11, 10, 30),
        );

        final json = bookmark.toJson();

        expect(json['chunkIndex'], 5);
        expect(json['originalStartOffset'], 42);
        expect(json['previewText'], 'Visible page text');
      });

      test('should create from JSON', () {
        final json = {
          'chunkIndex': 5,
          'name': 'Test',
          'createdAt': '2026-03-11T10:30:00.000',
        };

        final bookmark = Bookmark.fromJson(json);

        expect(bookmark.chunkIndex, 5);
        expect(bookmark.originalStartOffset, 0);
        expect(bookmark.name, 'Test');
        expect(bookmark.color, kBookmarkColors.first);
      });

      test('should create from JSON with source offset and preview', () {
        final json = {
          'chunkIndex': 5,
          'originalStartOffset': 42,
          'name': 'Test',
          'previewText': 'Visible page text',
          'createdAt': '2026-03-11T10:30:00.000',
        };

        final bookmark = Bookmark.fromJson(json);

        expect(bookmark.chunkIndex, 5);
        expect(bookmark.originalStartOffset, 42);
        expect(bookmark.previewText, 'Visible page text');
      });

      test('should preserve existing fixed color indices', () {
        final json = {
          'chunkIndex': 5,
          'name': 'Fixed color',
          'createdAt': '2026-03-11T10:30:00.000',
          'colorIndex': 4,
        };

        final bookmark = Bookmark.fromJson(json);

        expect(bookmark.colorIndex, 4);
        expect(bookmark.color, kBookmarkColors[4]);
        expect(bookmark.colorValue, isNull);
      });

      test('should serialize and deserialize arbitrary custom colors', () {
        final bookmark = Bookmark(
          chunkIndex: 5,
          name: 'Custom color',
          createdAt: DateTime(2026, 3, 11, 10, 30),
          colorIndex: 1,
          colorValue: bookmarkColorValue(const Color(0xFF123456)),
        );

        final decoded = Bookmark.fromJson(bookmark.toJson());

        expect(decoded.colorIndex, 1);
        expect(decoded.colorValue, bookmarkColorValue(const Color(0xFF123456)));
        expect(decoded.color, const Color(0xFF123456));
      });

      test('should encode and decode list', () {
        final bookmarks = [
          Bookmark(chunkIndex: 1, name: 'Bookmark 1'),
          Bookmark(chunkIndex: 2, name: 'Bookmark 2'),
        ];

        final encoded = Bookmark.encodeList(bookmarks);
        final decoded = Bookmark.decodeList(encoded);

        expect(decoded.length, 2);
        expect(decoded[0].chunkIndex, 1);
        expect(decoded[1].chunkIndex, 2);
      });
    });
  });

  group('ChapterInfo', () {
    group('constructor', () {
      test('should create chapter info with required parameters', () {
        const chapter = ChapterInfo(title: 'Chapter 1', chunkIndex: 10);

        expect(chapter.title, 'Chapter 1');
        expect(chapter.chunkIndex, 10);
        expect(chapter.depth, 0);
        expect(chapter.children, isEmpty);
      });

      test('should accept depth and children', () {
        const child = ChapterInfo(title: 'Section 1', chunkIndex: 20, depth: 1);
        const chapter = ChapterInfo(
          title: 'Chapter 1',
          chunkIndex: 10,
          depth: 0,
          children: [child],
        );

        expect(chapter.depth, 0);
        expect(chapter.children.length, 1);
        expect(chapter.children[0].title, 'Section 1');
      });
    });

    group('serialization', () {
      test('should convert to JSON with minimal data', () {
        const chapter = ChapterInfo(title: 'Test', chunkIndex: 5);

        final json = chapter.toJson();

        expect(json['t'], 'Test');
        expect(json['ci'], 5);
        expect(json['d'], 0);
      });

      test('should convert to JSON with children', () {
        const child = ChapterInfo(title: 'Child', chunkIndex: 10, depth: 1);
        const parent = ChapterInfo(
          title: 'Parent',
          chunkIndex: 5,
          depth: 0,
          children: [child],
        );

        final json = parent.toJson();

        expect(json['ch'], isNotNull);
        expect((json['ch'] as List).length, 1);
      });

      test('should create from JSON', () {
        final json = {'t': 'Test Chapter', 'ci': 15, 'd': 1};

        final chapter = ChapterInfo.fromJson(json);

        expect(chapter.title, 'Test Chapter');
        expect(chapter.chunkIndex, 15);
        expect(chapter.depth, 1);
      });

      test('should handle children in JSON', () {
        final json = {
          't': 'Parent',
          'ci': 5,
          'd': 0,
          'ch': [
            {'t': 'Child', 'ci': 10, 'd': 1},
          ],
        };

        final chapter = ChapterInfo.fromJson(json);

        expect(chapter.children.length, 1);
        expect(chapter.children[0].title, 'Child');
      });
    });
  });
}
