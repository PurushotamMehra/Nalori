import 'package:shared_preferences/shared_preferences.dart';

import '../models/highlight.dart';

/// Persistent storage for user-created highlights.
///
/// Each book has its own list keyed by `highlights_<bookId>`.
class HighlightService {
  final String bookId;
  SharedPreferences? _prefs;

  HighlightService({required this.bookId});

  String get _key => 'highlights_$bookId';

  Future<SharedPreferences> get _cachedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Read ──────────────────────────────────────────────────────────────

  Future<List<Highlight>> load() async {
    final prefs = await _cachedPrefs;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return Highlight.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────

  /// Add a new highlight. Returns the updated list.
  Future<List<Highlight>> add(Highlight highlight) async {
    final list = await load();

    // Overlap is only resolved within the same semantic annotation type.
    final merged = _mergeOverlapping(list, highlight);
    await _save(merged);
    return merged;
  }

  /// Remove a highlight by ID. Returns the updated list.
  Future<List<Highlight>> remove(String highlightId) async {
    final list = await load();
    list.removeWhere((h) => h.id == highlightId);
    await _save(list);
    return list;
  }

  /// Update a highlight (e.g. change color or range). Returns the updated list.
  Future<List<Highlight>> update(Highlight updated) async {
    final list = await load();
    for (int i = 0; i < list.length; i++) {
      if (list[i].id != updated.id) continue;
      list[i] = list[i].copyWith(
        colorIndex: updated.colorIndex,
        colorValue: updated.colorValue,
      );
    }
    await _save(list);
    return list;
  }

  /// Update just the note on an existing highlight. Returns the updated list.
  Future<List<Highlight>> updateNote(String highlightId, String? note) async {
    final list = await load();
    for (int i = 0; i < list.length; i++) {
      if (list[i].id != highlightId) continue;
      list[i] = list[i].copyWith(note: note);
    }
    await _save(list);
    return list;
  }

  /// Clear all highlights. Returns empty list.
  Future<List<Highlight>> clearAll() async {
    await _save([]);
    return [];
  }

  /// Get highlights for a specific original chunk index.
  List<Highlight> getForChunk(List<Highlight> all, int originalChunkIndex) {
    return all
        .where((h) => h.originalChunkIndex == originalChunkIndex)
        .toList();
  }

  // ── Internal ──────────────────────────────────────────────────────────

  Future<void> _save(List<Highlight> list) async {
    final prefs = await _cachedPrefs;
    await prefs.setString(_key, Highlight.encodeList(list));
  }

  /// Merge a new highlight with existing overlapping ones on the same chunk.
  List<Highlight> _mergeOverlapping(
    List<Highlight> existing,
    Highlight incoming,
  ) {
    final result = <Highlight>[];
    final merged = incoming;

    for (final h in existing) {
      if (h.originalChunkIndex == merged.originalChunkIndex &&
          h.type == merged.type &&
          _overlaps(h, merged)) {
        // Same-type overlaps are replaced by the most recent version.
      } else {
        result.add(h);
      }
    }

    result.insert(0, merged);
    return result;
  }

  bool _overlaps(Highlight a, Highlight b) {
    return a.startOffset < b.endOffset && b.startOffset < a.endOffset;
  }
}
