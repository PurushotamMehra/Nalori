import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book_chunk.dart';
import '../models/bookmark.dart';

/// Cached result of parsing an EPUB book.
class CachedBook {
  final String title;
  final List<BookChunk> chunks;
  final Map<String, int> anchorMap;
  final List<ChapterInfo> chapters;
  final Map<String, List<int>> searchIndex;

  const CachedBook({
    required this.title,
    required this.chunks,
    required this.anchorMap,
    required this.chapters,
    required this.searchIndex,
  });
}

/// Cached result of display chunk layout computation.
class CachedDisplayChunks {
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;

  const CachedDisplayChunks({
    required this.displayChunks,
    required this.displayToOriginal,
    required this.originalToDisplay,
  });
}

/// Service managing disk cache for parsed EPUB books.
///
/// Saves/loads parsed chunks, anchors, and chapters to/from compressed
/// JSON files so re-opening a previously read book is near-instant.
///
/// Cache budget: max [_maxCacheSizeBytes] total (default 10 MB).
/// Uses LRU eviction when the budget would be exceeded.
class BookCacheService {
  // Singleton
  static final BookCacheService _instance = BookCacheService._internal();
  factory BookCacheService() => _instance;
  BookCacheService._internal();

  static const String _cacheDirName = 'book_cache';
  static const String _manifestFileName = 'manifest.json';
  static const String _displayManifestFileName = 'display_manifest.json';

  /// Maximum total cache size in bytes (10 MB).
  static const int _maxCacheSizeBytes = 10 * 1024 * 1024;

  /// Maximum total display-layout cache size in bytes (20 MB).
  static const int _maxDisplayCacheSizeBytes = 20 * 1024 * 1024;

  /// Maximum size of a single display-layout cache file (5 MB).
  static const int _maxDisplayCacheFileSizeBytes = 5 * 1024 * 1024;

  /// Maximum filename length to avoid OS errors (e.g., errno 36).
  static const int _maxFileNameLength = 200;

  Directory? _cacheDir;

  /// Manifest: bookId → { fileSizeBytes, lastAccessedMs }
  Map<String, _CacheEntry> _manifest = {};
  Map<String, _CacheEntry> _displayManifest = {};
  bool _initialized = false;

  // ─── Initialization ─────────────────────────────────────────────────

  Future<void> _ensureInit() async {
    if (_initialized) return;

    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory(p.join(appDir.path, _cacheDirName));
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }

    await _loadManifests();
    _initialized = true;
  }

  // ─── Public API ─────────────────────────────────────────────────────

  /// Check if a cached version exists for the given book.
  ///
  /// [bookId] is typically the EPUB filename.
  /// [bookModifiedMs] is the file's last-modified timestamp (epoch ms).
  /// If the book file is newer than the cache, the cache is invalid.
  Future<bool> hasCachedBook(String bookId, int bookModifiedMs) async {
    await _ensureInit();
    final entry = _manifest[bookId];
    if (entry == null) return false;

    // Invalidate if book file was modified after caching
    if (bookModifiedMs > entry.cachedAtMs) {
      await _evict(bookId);
      return false;
    }

    // Verify the cache file actually exists
    final file = _fileFor(bookId);
    if (!await file.exists()) {
      _manifest.remove(bookId);
      await _saveManifest();
      return false;
    }

    return true;
  }

  /// Load a cached book. Returns null if not found.
  Future<CachedBook?> loadCachedBook(String bookId) async {
    await _ensureInit();
    final entry = _manifest[bookId];
    if (entry == null) return null;

    final file = _fileFor(bookId);
    if (!await file.exists()) {
      _manifest.remove(bookId);
      await _saveManifest();
      return null;
    }

    try {
      // Read + decompress + deserialize in an isolate to keep UI smooth
      final compressedBytes = await file.readAsBytes();
      final result = await Isolate.run(() => _deserializeBook(compressedBytes));

      // Update last-accessed time
      _manifest[bookId] = entry.copyWith(
        lastAccessedMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveManifest();

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BookCacheService: Failed to load cache for $bookId: $e');
      }
      await _evict(bookId);
      return null;
    }
  }

  /// Save a parsed book to the cache.
  Future<void> cacheBook({
    required String bookId,
    required String title,
    required List<BookChunk> chunks,
    required Map<String, int> anchorMap,
    required List<ChapterInfo> chapters,
    required Map<String, List<int>> searchIndex,
  }) async {
    await _ensureInit();

    try {
      // Serialize + compress in an isolate
      final compressedBytes = await Isolate.run(
        () => _serializeBook(title, chunks, anchorMap, chapters, searchIndex),
      );

      // Check if this single file exceeds budget
      if (compressedBytes.length > _maxCacheSizeBytes) {
        if (kDebugMode) {
          debugPrint(
            'BookCacheService: Skipping cache for $bookId '
            '(${compressedBytes.length} bytes > $_maxCacheSizeBytes limit)',
          );
        }
        return;
      }

      // Evict oldest entries until there's room
      await _evictUntilFits(compressedBytes.length, exclude: bookId);

      // Write the file
      final file = _fileFor(bookId);
      await file.writeAsBytes(compressedBytes);

      // Update manifest
      _manifest[bookId] = _CacheEntry(
        fileSizeBytes: compressedBytes.length,
        cachedAtMs: DateTime.now().millisecondsSinceEpoch,
        lastAccessedMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveManifest();

      if (kDebugMode) {
        debugPrint(
          'BookCacheService: Cached $bookId '
          '(${(compressedBytes.length / 1024).toStringAsFixed(1)} KB)',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BookCacheService: Failed to cache $bookId: $e');
      }
    }
  }

  /// Clear all cached books.
  Future<void> clearAll() async {
    await _ensureInit();
    if (await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create(recursive: true);
    }
    _manifest.clear();
    _displayManifest.clear();
    await _saveManifest();
    await _saveDisplayManifest();
  }

  Future<int> getTotalCacheSize() async {
    await _ensureInit();
    int total = 0;
    for (final entry in _manifest.values) {
      total += entry.fileSizeBytes;
    }
    for (final entry in _displayManifest.values) {
      total += entry.fileSizeBytes;
    }
    return total;
  }

  /// Delete cached data for a specific book.
  Future<void> deleteCachedBook(String bookId) async {
    await _ensureInit();
    await _evict(bookId);
  }

  // ─── Display Chunk Cache ─────────────────────────────────────────────

  /// Build a cache key for display chunks based on settings that affect layout.
  static String displayChunkKey({
    required String bookId,
    required double fontSize,
    required String fontFamily,
    required String fontWeight,
    required double density,
    required double lineHeight,
    required double paragraphSpacing,
    required double sideMargin,
    required double screenW,
    required double screenH,
    required bool enableCardDepth,
    required double textScaleFactor,
    required double safeAreaTop,
    required double safeAreaBottom,
    required double safeAreaLeft,
    required double safeAreaRight,
  }) {
    const layoutVersion = 'v11';
    final String cardModeStr = enableCardDepth ? '1' : '0';
    final String textScalerStr = textScaleFactor.toStringAsFixed(2);
    final String safeAreaStr =
        '${safeAreaTop.round()}_${safeAreaBottom.round()}_'
        '${safeAreaLeft.round()}_${safeAreaRight.round()}';

    return '${bookId}_dc_${layoutVersion}_${fontSize}_${fontFamily}_${fontWeight}_'
        '${density}_lineHeight_${lineHeight}_paragraphSpacing_${paragraphSpacing}_'
        'sideMargin_${sideMargin}_'
        '${screenW.toInt()}x${screenH.toInt()}_${cardModeStr}_${textScalerStr}_$safeAreaStr';
  }

  /// Check if cached display chunks exist for the given key.
  Future<bool> hasDisplayChunks(String key) async {
    await _ensureInit();
    final file = _fileFor(key);
    return file.exists();
  }

  /// Load cached display chunks. Returns null if not found.
  Future<CachedDisplayChunks?> loadDisplayChunks(String key) async {
    await _ensureInit();
    final file = _fileFor(key);
    if (!await file.exists()) return null;

    try {
      final compressedBytes = await file.readAsBytes();
      final result = await Isolate.run(
        () => _deserializeDisplayChunks(compressedBytes),
      );
      final entry = _displayManifest[key];
      if (entry != null) {
        _displayManifest[key] = entry.copyWith(
          lastAccessedMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _saveDisplayManifest();
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'BookCacheService: Failed to load display chunks for $key: $e',
        );
      }
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Save display chunks to disk cache.
  Future<void> cacheDisplayChunks({
    required String key,
    required List<BookChunk> displayChunks,
    required List<List<int>> displayToOriginal,
    required Map<int, int> originalToDisplay,
  }) async {
    await _ensureInit();
    try {
      final compressedBytes = await Isolate.run(
        () => _serializeDisplayChunks(
          displayChunks,
          displayToOriginal,
          originalToDisplay,
        ),
      );

      // Don't cache unusually large individual layouts.
      if (compressedBytes.length > _maxDisplayCacheFileSizeBytes) return;
      await _evictDisplayUntilFits(compressedBytes.length, exclude: key);

      final file = _fileFor(key);
      await file.writeAsBytes(compressedBytes);
      _displayManifest[key] = _CacheEntry(
        fileSizeBytes: compressedBytes.length,
        cachedAtMs: DateTime.now().millisecondsSinceEpoch,
        lastAccessedMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveDisplayManifest();

      if (kDebugMode) {
        debugPrint(
          'BookCacheService: Cached display chunks $key '
          '(${(compressedBytes.length / 1024).toStringAsFixed(1)} KB)',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BookCacheService: Failed to cache display chunks: $e');
      }
    }
  }

  /// Delete all display chunk caches for a given book.
  Future<void> deleteDisplayChunks(String bookId) async {
    await _ensureInit();
    final dir = _cacheDir!;
    final prefix = _sanitizeKey(bookId);
    await for (final entity in dir.list()) {
      if (entity is File && p.basename(entity.path).startsWith(prefix)) {
        await entity.delete();
      }
    }
    _displayManifest.removeWhere(
      (key, _) => _sanitizeKey(key).startsWith(prefix),
    );
    await _saveDisplayManifest();
  }

  // ─── Serialization (runs in isolate) ────────────────────────────────

  static Uint8List _serializeDisplayChunks(
    List<BookChunk> displayChunks,
    List<List<int>> displayToOriginal,
    Map<int, int> originalToDisplay,
  ) {
    final data = {
      'v': 2,
      'dc': displayChunks.map((c) => c.toJson()).toList(),
      'dto': displayToOriginal,
      'otd': originalToDisplay.map((k, v) => MapEntry(k.toString(), v)),
    };
    final jsonStr = jsonEncode(data);
    final jsonBytes = utf8.encode(jsonStr);
    return Uint8List.fromList(gzip.encode(jsonBytes));
  }

  static CachedDisplayChunks _deserializeDisplayChunks(
    Uint8List compressedBytes,
  ) {
    final jsonBytes = gzip.decode(compressedBytes);
    final jsonStr = utf8.decode(jsonBytes);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final displayChunks = (data['dc'] as List)
        .map((e) => BookChunk.fromJson(e as Map<String, dynamic>))
        .toList();

    final displayToOriginal = (data['dto'] as List)
        .map((e) => (e as List).map((i) => i as int).toList())
        .toList();

    final originalToDisplay = (data['otd'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(int.parse(k), v as int),
    );

    return CachedDisplayChunks(
      displayChunks: displayChunks,
      displayToOriginal: displayToOriginal,
      originalToDisplay: originalToDisplay,
    );
  }

  static Uint8List _serializeBook(
    String title,
    List<BookChunk> chunks,
    Map<String, int> anchorMap,
    List<ChapterInfo> chapters,
    Map<String, List<int>> searchIndex,
  ) {
    final data = {
      'v': 4, // cache format version
      'title': title,
      'chunks': chunks.map((c) => c.toJson()).toList(),
      'anchors': anchorMap,
      'chapters': chapters.map((c) => c.toJson()).toList(),
      'searchIndex': searchIndex,
    };

    final jsonStr = jsonEncode(data);
    final jsonBytes = utf8.encode(jsonStr);
    return Uint8List.fromList(gzip.encode(jsonBytes));
  }

  static CachedBook _deserializeBook(Uint8List compressedBytes) {
    final jsonBytes = gzip.decode(compressedBytes);
    final jsonStr = utf8.decode(jsonBytes);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (data['v'] != 4) {
      throw const FormatException('Unsupported parsed book cache version');
    }

    final chunks = (data['chunks'] as List)
        .map((e) => BookChunk.fromJson(e as Map<String, dynamic>))
        .toList();

    final anchorMap = (data['anchors'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as int),
    );

    final chapters = (data['chapters'] as List)
        .map((e) => ChapterInfo.fromJson(e as Map<String, dynamic>))
        .toList();

    final searchIndex =
        (data['searchIndex'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as List).cast<int>()),
        ) ??
        {};

    return CachedBook(
      title: data['title'] as String,
      chunks: chunks,
      anchorMap: anchorMap,
      chapters: chapters,
      searchIndex: searchIndex,
    );
  }

  // ─── LRU Eviction ──────────────────────────────────────────────────

  Future<void> _evictUntilFits(int newFileSize, {String? exclude}) async {
    int currentSize = _manifest.entries
        .where((e) => e.key != exclude)
        .fold(0, (sum, e) => sum + e.value.fileSizeBytes);

    if (currentSize + newFileSize <= _maxCacheSizeBytes) return;

    // Sort by last accessed (oldest first)
    final sortedEntries =
        _manifest.entries.where((e) => e.key != exclude).toList()..sort(
          (a, b) => a.value.lastAccessedMs.compareTo(b.value.lastAccessedMs),
        );

    for (final entry in sortedEntries) {
      if (currentSize + newFileSize <= _maxCacheSizeBytes) break;
      currentSize -= entry.value.fileSizeBytes;
      await _evict(entry.key);
    }
  }

  Future<void> _evict(String bookId) async {
    final file = _fileFor(bookId);
    if (await file.exists()) {
      await file.delete();
    }
    _manifest.remove(bookId);
    await _saveManifest();
    if (kDebugMode) {
      debugPrint('BookCacheService: Evicted $bookId');
    }
  }

  Future<void> _evictDisplayUntilFits(
    int newFileSize, {
    String? exclude,
  }) async {
    var currentSize = _displayManifest.entries
        .where((e) => e.key != exclude)
        .fold(0, (sum, e) => sum + e.value.fileSizeBytes);

    if (currentSize + newFileSize <= _maxDisplayCacheSizeBytes) return;

    final sortedEntries =
        _displayManifest.entries.where((e) => e.key != exclude).toList()..sort(
          (a, b) => a.value.lastAccessedMs.compareTo(b.value.lastAccessedMs),
        );

    for (final entry in sortedEntries) {
      if (currentSize + newFileSize <= _maxDisplayCacheSizeBytes) break;
      currentSize -= entry.value.fileSizeBytes;
      await _evictDisplay(entry.key);
    }
  }

  Future<void> _evictDisplay(String key) async {
    final file = _fileFor(key);
    if (await file.exists()) {
      await file.delete();
    }
    _displayManifest.remove(key);
    await _saveDisplayManifest();
  }

  // ─── Manifest persistence ──────────────────────────────────────────

  Future<void> _loadManifests() async {
    await _loadManifest();
    await _loadDisplayManifest();
  }

  Future<void> _loadManifest() async {
    final file = File(p.join(_cacheDir!.path, _manifestFileName));
    if (!await file.exists()) {
      _manifest = {};
      return;
    }

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _manifest = data.map(
        (k, v) => MapEntry(k, _CacheEntry.fromJson(v as Map<String, dynamic>)),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BookCacheService: Failed to load manifest: $e');
      }
      _manifest = {};
    }
  }

  Future<void> _saveManifest() async {
    final file = File(p.join(_cacheDir!.path, _manifestFileName));
    final data = _manifest.map((k, v) => MapEntry(k, v.toJson()));
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> _loadDisplayManifest() async {
    final file = File(p.join(_cacheDir!.path, _displayManifestFileName));
    if (!await file.exists()) {
      _displayManifest = {};
      return;
    }

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _displayManifest = data.map(
        (k, v) => MapEntry(k, _CacheEntry.fromJson(v as Map<String, dynamic>)),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BookCacheService: Failed to load display manifest: $e');
      }
      _displayManifest = {};
    }
  }

  Future<void> _saveDisplayManifest() async {
    final file = File(p.join(_cacheDir!.path, _displayManifestFileName));
    final data = _displayManifest.map((k, v) => MapEntry(k, v.toJson()));
    await file.writeAsString(jsonEncode(data));
  }

  // ─── Path Helpers ──────────────────────────────────────────────────

  File _fileFor(String key) {
    final sanitized = _sanitizeKey(key);
    return File(p.join(_cacheDir!.path, '$sanitized.json.gz'));
  }

  String _sanitizeKey(String key) {
    if (key.length <= _maxFileNameLength) return key;

    // Deterministic truncation + hash to keep it unique but short.
    // We use hashCode for simplicity as a local non-cryptographic hash.
    final hash = key.hashCode.toRadixString(36);
    final prefix = key.substring(0, _maxFileNameLength - hash.length - 1);
    return '${prefix}_$hash';
  }
}

/// Internal manifest entry tracking a single cached book.
class _CacheEntry {
  final int fileSizeBytes;
  final int cachedAtMs;
  final int lastAccessedMs;

  const _CacheEntry({
    required this.fileSizeBytes,
    required this.cachedAtMs,
    required this.lastAccessedMs,
  });

  _CacheEntry copyWith({int? lastAccessedMs}) => _CacheEntry(
    fileSizeBytes: fileSizeBytes,
    cachedAtMs: cachedAtMs,
    lastAccessedMs: lastAccessedMs ?? this.lastAccessedMs,
  );

  Map<String, dynamic> toJson() => {
    'size': fileSizeBytes,
    'cached': cachedAtMs,
    'accessed': lastAccessedMs,
  };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
    fileSizeBytes: json['size'] as int,
    cachedAtMs: json['cached'] as int,
    lastAccessedMs: json['accessed'] as int,
  );
}
