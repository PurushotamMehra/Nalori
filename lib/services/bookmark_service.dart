import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';
import '../models/stable_book_location.dart';

/// Persistent storage for user-created bookmarks.
///
/// Each book has its own list keyed by `bookmarks_<bookId>`.
/// Bookmarks are auto-named sequentially ("Bookmark 1", "Bookmark 2", …).
class BookmarkService {
  final String bookId;
  SharedPreferences? _prefs;

  BookmarkService({required this.bookId});

  String get _key => 'bookmarks_$bookId';
  static const String _defaultColorKey = 'default_bookmark_color';
  static const String _defaultColorValueKey = 'default_bookmark_color_value';

  Future<SharedPreferences> get _cachedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Read ──────────────────────────────────────────────────────────────

  Future<List<Bookmark>> load() async {
    final prefs = await _cachedPrefs;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    return Bookmark.decodeList(raw);
  }

  // ── Default Color ────────────────────────────────────────────────────

  /// Load the user's preferred default bookmark palette index.
  Future<int> loadDefaultColorIndex() async {
    final prefs = await _cachedPrefs;
    return prefs.getInt(_defaultColorKey) ?? 0;
  }

  /// Load the user's preferred default bookmark color.
  ///
  /// Falls back to the legacy fixed palette index key for older installs.
  Future<Color> loadDefaultColor() async {
    final prefs = await _cachedPrefs;
    final rawColorValue = prefs.getInt(_defaultColorValueKey);
    if (rawColorValue != null) {
      return Color(bookmarkColorValue(Color(rawColorValue)));
    }

    final colorIndex = prefs.getInt(_defaultColorKey) ?? 0;
    return kBookmarkColors[colorIndex % kBookmarkColors.length];
  }

  /// Save the user's preferred default bookmark color index.
  Future<void> saveDefaultColorIndex(int colorIndex) async {
    final prefs = await _cachedPrefs;
    await prefs.setInt(_defaultColorKey, colorIndex);
    await prefs.remove(_defaultColorValueKey);
  }

  /// Save the user's preferred default bookmark color.
  Future<void> saveDefaultColor(Color color) async {
    final prefs = await _cachedPrefs;
    final normalized = Color(bookmarkColorValue(color));
    await prefs.setInt(_defaultColorValueKey, bookmarkColorValue(normalized));

    final fixedIndex = defaultBookmarkColorIndex(normalized);
    if (fixedIndex != null) {
      await prefs.setInt(_defaultColorKey, fixedIndex);
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────

  Future<List<Bookmark>> add(
    int chunkIndex, {
    int originalStartOffset = 0,
    String? previewText,
    int colorIndex = 0,
    int? colorValue,
    StableBookLocation? stableLocation,
  }) async {
    final list = await load();

    // Don't double-bookmark the same source location.
    if (list.any((b) => b.isSameLocation(chunkIndex, originalStartOffset))) {
      return list;
    }

    // Sequential name: highest existing number + 1
    int maxNum = 0;
    final pattern = RegExp(r'^Bookmark (\d+)$');
    for (final b in list) {
      final match = pattern.firstMatch(b.name);
      if (match != null) {
        final n = int.parse(match.group(1)!);
        if (n > maxNum) maxNum = n;
      }
    }

    list.insert(
      0,
      Bookmark(
        chunkIndex: chunkIndex,
        originalStartOffset: originalStartOffset,
        name: 'Bookmark ${maxNum + 1}',
        previewText: previewText,
        colorIndex: colorIndex,
        colorValue: colorValue,
        stableLocation: stableLocation,
      ),
    );

    await _save(list);
    return list;
  }

  Future<List<Bookmark>> remove(
    int chunkIndex, {
    int? originalStartOffset,
  }) async {
    final list = await load();
    list.removeWhere((b) {
      if (b.chunkIndex != chunkIndex) return false;
      return originalStartOffset == null ||
          b.originalStartOffset == originalStartOffset;
    });
    await _save(list);
    return list;
  }

  Future<List<Bookmark>> rename(
    int chunkIndex,
    String newName, {
    int? originalStartOffset,
  }) async {
    final list = await load();
    final updated = <Bookmark>[];
    for (final b in list) {
      if (b.chunkIndex == chunkIndex &&
          (originalStartOffset == null ||
              b.originalStartOffset == originalStartOffset)) {
        updated.add(b.copyWith(name: newName));
      } else {
        updated.add(b);
      }
    }
    await _save(updated);
    return updated;
  }

  /// Update both name and color of a bookmark.
  Future<List<Bookmark>> update(
    int chunkIndex, {
    int? originalStartOffset,
    String? newName,
    int? colorIndex,
    int? colorValue,
    bool clearColorValue = false,
  }) async {
    final list = await load();
    final updated = <Bookmark>[];
    for (final b in list) {
      if (b.chunkIndex == chunkIndex &&
          (originalStartOffset == null ||
              b.originalStartOffset == originalStartOffset)) {
        updated.add(
          b.copyWith(
            name: newName ?? b.name,
            colorIndex: colorIndex ?? b.colorIndex,
            colorValue: colorValue,
            clearColorValue: clearColorValue,
          ),
        );
      } else {
        updated.add(b);
      }
    }
    await _save(updated);
    return updated;
  }

  /// Remove all bookmarks for this book.
  Future<List<Bookmark>> clearAll() async {
    await _save([]);
    return [];
  }

  /// Replace the entire bookmark list (used for undo/restore).
  Future<List<Bookmark>> restoreAll(List<Bookmark> bookmarks) async {
    final restored = List<Bookmark>.from(bookmarks);
    await _save(restored);
    return restored;
  }

  /// Check if a specific chunk is bookmarked.
  bool isBookmarked(
    List<Bookmark> bookmarks,
    int chunkIndex, {
    int? originalStartOffset,
  }) {
    return bookmarks.any((b) {
      if (b.chunkIndex != chunkIndex) return false;
      return originalStartOffset == null ||
          b.originalStartOffset == originalStartOffset;
    });
  }

  // ── Internal ──────────────────────────────────────────────────────────

  Future<void> _save(List<Bookmark> list) async {
    final prefs = await _cachedPrefs;
    await prefs.setString(_key, Bookmark.encodeList(list));
  }
}
