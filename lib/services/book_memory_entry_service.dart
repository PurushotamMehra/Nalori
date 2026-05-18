import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/book_memory_entry.dart';

class BookMemoryEntryService {
  static const _uuid = Uuid();

  final String bookId;
  SharedPreferences? _prefs;

  BookMemoryEntryService({required this.bookId});

  String get _key => 'book_memory_entries_$bookId';

  Future<SharedPreferences> get _cachedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<List<BookMemoryEntry>> loadForBook() async {
    final prefs = await _cachedPrefs;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final entries = BookMemoryEntry.decodeList(
        raw,
      ).where((entry) => entry.bookId == bookId && !entry.isEmpty).toList();
      entries.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<BookMemoryEntry?> loadById(String id) async {
    final entries = await loadForBook();
    return entries.cast<BookMemoryEntry?>().firstWhere(
      (entry) => entry?.id == id,
      orElse: () => null,
    );
  }

  Future<BookMemoryEntry?> loadForSource(
    BookMemorySourceType type,
    String sourceId,
  ) async {
    final normalizedSourceId = sourceId.trim();
    if (type == BookMemorySourceType.free || normalizedSourceId.isEmpty) {
      return null;
    }
    final entries = await loadForBook();
    return entries.cast<BookMemoryEntry?>().firstWhere(
      (entry) =>
          entry?.sourceType == type && entry?.sourceId == normalizedSourceId,
      orElse: () => null,
    );
  }

  Future<BookMemoryEntry?> upsertSourceEntry({
    required BookMemorySourceType sourceType,
    required String sourceId,
    required String title,
    required String body,
  }) async {
    if (sourceType == BookMemorySourceType.free) {
      throw ArgumentError('Use createFreeEntry for free book notes.');
    }

    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) return null;

    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    final entries = await loadForBook();
    final existingIndex = entries.indexWhere(
      (entry) =>
          entry.sourceType == sourceType &&
          entry.sourceId == normalizedSourceId,
    );

    if (trimmedTitle.isEmpty && trimmedBody.isEmpty) {
      return existingIndex == -1 ? null : entries[existingIndex];
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = existingIndex == -1
        ? BookMemoryEntry(
            id: _uuid.v4(),
            bookId: bookId,
            sourceType: sourceType,
            sourceId: normalizedSourceId,
            title: trimmedTitle,
            body: trimmedBody,
            createdAtMs: now,
            updatedAtMs: now,
          )
        : entries[existingIndex].copyWith(
            title: trimmedTitle,
            body: trimmedBody,
            updatedAtMs: now,
          );

    entries.removeWhere(
      (candidate) =>
          candidate.sourceType == sourceType &&
          candidate.sourceId == normalizedSourceId,
    );
    entries.insert(0, entry);
    await _save(entries);
    return entry;
  }

  Future<BookMemoryEntry?> createFreeEntry({
    required String title,
    required String body,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty && trimmedBody.isEmpty) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = await loadForBook();
    final entry = BookMemoryEntry(
      id: _uuid.v4(),
      bookId: bookId,
      sourceType: BookMemorySourceType.free,
      sourceId: null,
      title: trimmedTitle,
      body: trimmedBody,
      createdAtMs: now,
      updatedAtMs: now,
    );
    entries.insert(0, entry);
    await _save(entries);
    return entry;
  }

  Future<BookMemoryEntry?> updateEntry({
    required String id,
    required String title,
    required String body,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty && trimmedBody.isEmpty) return loadById(id);

    final entries = await loadForBook();
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index == -1) return null;

    final updated = entries[index].copyWith(
      title: trimmedTitle,
      body: trimmedBody,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    entries
      ..removeAt(index)
      ..insert(0, updated);
    await _save(entries);
    return updated;
  }

  Future<void> deleteEntry(String id) async {
    final entries = await loadForBook();
    entries.removeWhere((entry) => entry.id == id);
    await _save(entries);
  }

  Future<bool> hasEntryForSource(
    BookMemorySourceType type,
    String sourceId,
  ) async {
    return await loadForSource(type, sourceId) != null;
  }

  Future<int> countForBook() async {
    final entries = await loadForBook();
    return entries.length;
  }

  Future<void> clearForBook() async {
    final prefs = await _cachedPrefs;
    await prefs.remove(_key);
  }

  Future<void> _save(List<BookMemoryEntry> entries) async {
    final prefs = await _cachedPrefs;
    final nonEmptyEntries = entries.where((entry) => !entry.isEmpty).toList();
    await prefs.setString(_key, BookMemoryEntry.encodeList(nonEmptyEntries));
  }
}
