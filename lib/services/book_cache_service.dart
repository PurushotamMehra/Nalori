import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import 'lazy_epub_index_service.dart';
import 'parsed_section_cache_service.dart';

const bool _bookCacheDiagEnabled = bool.fromEnvironment('NALORI_EPUB_DIAG');
const String _bookCacheDiagPrefix = 'NALORI_EPUB_DIAG';

int _bookCacheDiagRssBytes() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return -1;
  }
}

void _bookCacheDiagLog(String phase, Map<String, Object?> fields) {
  if (!_bookCacheDiagEnabled) return;
  final isolateName = Isolate.current.debugName;
  final parts = <String>[
    _bookCacheDiagPrefix,
    'phase=$phase',
    'ts=${DateTime.now().toIso8601String()}',
    'rss=${_bookCacheDiagRssBytes()}',
    'isolate=${isolateName == null || isolateName.isEmpty ? Isolate.current.hashCode : isolateName}',
    for (final entry in fields.entries)
      if (entry.value != null) '${entry.key}=${entry.value}',
  ];
  // ignore: avoid_print
  print(parts.join(' '));
}

Future<T> _bookCacheDiagAsync<T>(
  String phase,
  Map<String, Object?> fields,
  Future<T> Function() body,
) async {
  if (!_bookCacheDiagEnabled) return body();
  final sw = Stopwatch()..start();
  _bookCacheDiagLog('${phase}_start', fields);
  try {
    final result = await body();
    sw.stop();
    _bookCacheDiagLog('${phase}_end', {
      ...fields,
      'elapsedMs': sw.elapsedMilliseconds,
    });
    return result;
  } catch (error) {
    sw.stop();
    _bookCacheDiagLog('${phase}_error', {
      ...fields,
      'elapsedMs': sw.elapsedMilliseconds,
      'error': error.runtimeType,
    });
    rethrow;
  }
}

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

/// Filesystem evidence used to validate a whole-book preparation result.
class BookCacheFileIdentity {
  final String bookId;
  final int fileSizeBytes;
  final int modifiedMs;

  const BookCacheFileIdentity({
    required this.bookId,
    required this.fileSizeBytes,
    required this.modifiedMs,
  });
}

enum BookCacheProbeStatus {
  validPayload,
  noCache,
  stale,
  knownTooLarge,
  missingPayload,
  corruptMetadata,
  unsupportedVersion,
}

class BookCacheProbe {
  final BookCacheProbeStatus status;
  final String bookId;
  final BookCacheFileIdentity identity;
  final int? serializedSizeBytes;
  final int cacheLimitBytes;

  const BookCacheProbe({
    required this.status,
    required this.bookId,
    required this.identity,
    required this.cacheLimitBytes,
    this.serializedSizeBytes,
  });

  bool get hasValidPayload => status == BookCacheProbeStatus.validPayload;
}

enum BookCacheWriteStatus { stored, tooLarge, failed }

class BookCacheWriteResult {
  final BookCacheWriteStatus status;
  final String bookId;
  final BookCacheFileIdentity? identity;
  final int? serializedSizeBytes;
  final int cacheLimitBytes;
  final String? failureMessage;

  const BookCacheWriteResult({
    required this.status,
    required this.bookId,
    required this.cacheLimitBytes,
    this.identity,
    this.serializedSizeBytes,
    this.failureMessage,
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

  static const String _cacheDirName = 'book_cache';
  static const String _manifestFileName = 'manifest.json';
  static const String _displayManifestFileName = 'display_manifest.json';
  static const int parsedBookCacheFormatVersion = 4;
  static const String wholeBookPreparationVersion = 'whole_book_preparation_v1';
  static const int displayCacheFormatVersion = 2;
  static const String displayLayoutVersion = 'v11';

  /// Maximum total cache size in bytes (10 MB).
  static const int parsedBookCacheLimitBytes = 10 * 1024 * 1024;
  static const int _defaultMaxCacheSizeBytes = parsedBookCacheLimitBytes;

  /// Maximum total display-layout cache size in bytes (20 MB).
  static const int _maxDisplayCacheSizeBytes = 20 * 1024 * 1024;

  /// Maximum size of a single display-layout cache file (5 MB).
  static const int _maxDisplayCacheFileSizeBytes = 5 * 1024 * 1024;

  /// Maximum filename length to avoid OS errors (e.g., errno 36).
  static const int _maxFileNameLength = 200;

  Directory? _cacheDir;
  final Directory? _testCacheDir;
  final int _maxCacheSizeBytes;

  /// Manifest: bookId → { fileSizeBytes, lastAccessedMs }
  Map<String, _CacheEntry> _manifest = {};
  Map<String, _PreparationEntry> _preparationManifest = {};
  Map<String, _CacheEntry> _displayManifest = {};
  bool _initialized = false;
  bool _preparationManifestCorrupt = false;

  BookCacheService._internal()
    : _testCacheDir = null,
      _maxCacheSizeBytes = _defaultMaxCacheSizeBytes;

  @visibleForTesting
  factory BookCacheService.testing({
    required Directory cacheDirectory,
    int maxCacheSizeBytes = _defaultMaxCacheSizeBytes,
  }) => BookCacheService._testing(cacheDirectory, maxCacheSizeBytes);

  BookCacheService._testing(this._testCacheDir, this._maxCacheSizeBytes);

  // ─── Initialization ─────────────────────────────────────────────────

  Future<void> _ensureInit() async {
    if (_initialized) return;

    final appDir = _testCacheDir ?? await getApplicationDocumentsDirectory();
    _cacheDir = _testCacheDir ?? Directory(p.join(appDir.path, _cacheDirName));
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

  /// Inspects whole-book preparation metadata without reading the payload.
  ///
  /// The payload is only decompressed by [loadCachedBook] for a consumer that
  /// actually needs its chunks. Stale records are removed so a future request
  /// can prepare the current EPUB rather than treating a filename as durable.
  Future<BookCacheProbe> probeBook(
    String bookId,
    BookCacheFileIdentity identity,
  ) async {
    await _ensureInit();
    var result = _probeResult(bookId, identity);
    if (result.status == BookCacheProbeStatus.validPayload &&
        !await _fileFor(bookId).exists()) {
      result = _probe(
        BookCacheProbeStatus.missingPayload,
        bookId,
        identity,
        serializedSizeBytes: result.serializedSizeBytes,
      );
    }
    if (result.status == BookCacheProbeStatus.stale ||
        result.status == BookCacheProbeStatus.unsupportedVersion ||
        result.status == BookCacheProbeStatus.missingPayload) {
      await _removeBookRecords(bookId, removePayload: true);
    }
    return result;
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
  Future<BookCacheWriteResult> cacheBook({
    required String bookId,
    required String title,
    required List<BookChunk> chunks,
    required Map<String, int> anchorMap,
    required List<ChapterInfo> chapters,
    required Map<String, List<int>> searchIndex,
    BookCacheFileIdentity? fileIdentity,
  }) async {
    await _ensureInit();

    try {
      // Serialize + compress in an isolate
      final compressedBytes = await _bookCacheDiagAsync(
        'cache_book_serialize',
        {
          'book': bookId,
          'chunks': chunks.length,
          'anchors': anchorMap.length,
          'chapters': chapters.length,
        },
        () => Isolate.run(
          () => _serializeBook(title, chunks, anchorMap, chapters, searchIndex),
        ),
      );
      _bookCacheDiagLog('cache_book_serialized', {
        'book': bookId,
        'compressedBytes': compressedBytes.length,
      });

      // Check if this single file exceeds budget
      if (compressedBytes.length > _maxCacheSizeBytes) {
        if (kDebugMode) {
          debugPrint(
            'BookCacheService: Skipping cache for $bookId '
            '(${compressedBytes.length} bytes > $_maxCacheSizeBytes limit)',
          );
        }
        await _removeBookRecords(bookId, removePayload: true);
        if (fileIdentity != null) {
          _preparationManifest[bookId] = _PreparationEntry.tooLarge(
            identity: fileIdentity,
            serializedSizeBytes: compressedBytes.length,
            cacheLimitBytes: _maxCacheSizeBytes,
          );
          await _savePreparationManifest();
        }
        return BookCacheWriteResult(
          status: BookCacheWriteStatus.tooLarge,
          bookId: bookId,
          identity: fileIdentity,
          serializedSizeBytes: compressedBytes.length,
          cacheLimitBytes: _maxCacheSizeBytes,
        );
      }

      // Evict oldest entries until there's room
      await _evictUntilFits(compressedBytes.length, exclude: bookId);

      // Write the file
      final file = _fileFor(bookId);
      await _bookCacheDiagAsync('cache_book_write', {
        'book': bookId,
        'bytes': compressedBytes.length,
        'path': file.path,
      }, () => file.writeAsBytes(compressedBytes));

      // Update manifest
      _manifest[bookId] = _CacheEntry(
        fileSizeBytes: compressedBytes.length,
        cachedAtMs: DateTime.now().millisecondsSinceEpoch,
        lastAccessedMs: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveManifest();
      if (fileIdentity != null) {
        _preparationManifest[bookId] = _PreparationEntry.stored(
          identity: fileIdentity,
          serializedSizeBytes: compressedBytes.length,
          cacheLimitBytes: _maxCacheSizeBytes,
        );
        await _savePreparationManifest();
      }

      if (kDebugMode) {
        debugPrint(
          'BookCacheService: Cached $bookId '
          '(${(compressedBytes.length / 1024).toStringAsFixed(1)} KB)',
        );
      }
      return BookCacheWriteResult(
        status: BookCacheWriteStatus.stored,
        bookId: bookId,
        identity: fileIdentity,
        serializedSizeBytes: compressedBytes.length,
        cacheLimitBytes: _maxCacheSizeBytes,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BookCacheService: Failed to cache $bookId: $e');
      }
      return BookCacheWriteResult(
        status: BookCacheWriteStatus.failed,
        bookId: bookId,
        identity: fileIdentity,
        cacheLimitBytes: _maxCacheSizeBytes,
        failureMessage: 'Unable to store the prepared book cache.',
      );
    }
  }

  /// Clear all cached books.
  Future<void> clearAll() async {
    await _ensureInit();
    if (_testCacheDir == null) {
      await ParsedSectionCacheService().clearAll();
    }
    if (await _cacheDir!.exists()) {
      await _cacheDir!.delete(recursive: true);
      await _cacheDir!.create(recursive: true);
    }
    _manifest.clear();
    _preparationManifest.clear();
    _displayManifest.clear();
    await _saveManifest();
    await _saveDisplayManifest();
    try {
      await LazyEpubIndexStore().clearAll();
    } catch (_) {
      // Structural-index cleanup must not make a legacy cache reset fail.
    }
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
    await _removeBookRecords(bookId, removePayload: true);
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
    String fixed(double value) => value.toStringAsFixed(3);
    final String cardModeStr = enableCardDepth ? '1' : '0';
    final String textScalerStr = textScaleFactor.toStringAsFixed(2);
    final String safeAreaStr =
        '${safeAreaTop.round()}_${safeAreaBottom.round()}_'
        '${safeAreaLeft.round()}_${safeAreaRight.round()}';

    return '${bookId}_dc_${displayLayoutVersion}_${fixed(fontSize)}_${fontFamily}_${fontWeight}_'
        '${fixed(density)}_lineHeight_${fixed(lineHeight)}_paragraphSpacing_${fixed(paragraphSpacing)}_'
        'sideMargin_${fixed(sideMargin)}_'
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
    bool Function()? shouldWrite,
  }) async {
    await _ensureInit();
    try {
      if (shouldWrite != null && !shouldWrite()) {
        _bookCacheDiagLog('display_cache_write_skipped_stale', {'key': key});
        return;
      }
      final compressedBytes = await _bookCacheDiagAsync(
        'display_cache_serialize',
        {
          'key': key,
          'displayChunks': displayChunks.length,
          'displayToOriginal': displayToOriginal.length,
          'originalToDisplay': originalToDisplay.length,
        },
        () => Isolate.run(
          () => _serializeDisplayChunks(
            displayChunks,
            displayToOriginal,
            originalToDisplay,
          ),
        ),
      );
      _bookCacheDiagLog('display_cache_serialized', {
        'key': key,
        'compressedBytes': compressedBytes.length,
      });

      if (shouldWrite != null && !shouldWrite()) {
        _bookCacheDiagLog('display_cache_write_skipped_stale', {'key': key});
        return;
      }

      // Don't cache unusually large individual layouts.
      if (compressedBytes.length > _maxDisplayCacheFileSizeBytes) return;
      await _evictDisplayUntilFits(compressedBytes.length, exclude: key);

      final file = _fileFor(key);
      await _bookCacheDiagAsync('display_cache_write', {
        'key': key,
        'bytes': compressedBytes.length,
        'path': file.path,
      }, () => file.writeAsBytes(compressedBytes));
      if (shouldWrite != null && !shouldWrite()) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        _bookCacheDiagLog('display_cache_write_discarded_stale', {
          'key': key,
          'path': file.path,
        });
        return;
      }
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
    final prefix = _sanitizeKey(bookId);
    final deletedPaths = <String>[];
    final removedKeys = _displayManifest.keys
        .where((key) => _sanitizeKey(key).startsWith(prefix))
        .toList();

    for (final key in removedKeys) {
      final file = _fileFor(key);
      if (await file.exists()) {
        await file.delete();
        deletedPaths.add(file.path);
      }
    }

    _displayManifest.removeWhere(
      (key, _) => _sanitizeKey(key).startsWith(prefix),
    );
    await _saveDisplayManifest();
    _bookCacheDiagLog('display_cache_delete_for_book', {
      'book': bookId,
      'prefix': prefix,
      'removedKeys': removedKeys,
      'deletedPaths': deletedPaths,
    });
  }

  // ─── Serialization (runs in isolate) ────────────────────────────────

  static Uint8List _serializeDisplayChunks(
    List<BookChunk> displayChunks,
    List<List<int>> displayToOriginal,
    Map<int, int> originalToDisplay,
  ) {
    final data = {
      'v': displayCacheFormatVersion,
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
      'v': parsedBookCacheFormatVersion,
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
    if (data['v'] != parsedBookCacheFormatVersion) {
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
    await _removeBookRecords(bookId, removePayload: true);
    if (kDebugMode) {
      debugPrint('BookCacheService: Evicted $bookId');
    }
  }

  BookCacheProbe _probeResult(String bookId, BookCacheFileIdentity identity) {
    if (_preparationManifestCorrupt) {
      return _probe(BookCacheProbeStatus.corruptMetadata, bookId, identity);
    }
    final preparation = _preparationManifest[bookId];
    if (preparation == null) {
      return _probe(BookCacheProbeStatus.noCache, bookId, identity);
    }
    if (preparation.formatVersion != parsedBookCacheFormatVersion ||
        preparation.preparationVersion != wholeBookPreparationVersion) {
      return _probe(
        BookCacheProbeStatus.unsupportedVersion,
        bookId,
        identity,
        serializedSizeBytes: preparation.serializedSizeBytes,
      );
    }
    if (!preparation.matches(identity, _maxCacheSizeBytes)) {
      return _probe(
        BookCacheProbeStatus.stale,
        bookId,
        identity,
        serializedSizeBytes: preparation.serializedSizeBytes,
      );
    }
    if (preparation.outcome == _PreparationOutcome.tooLarge) {
      return _probe(
        BookCacheProbeStatus.knownTooLarge,
        bookId,
        identity,
        serializedSizeBytes: preparation.serializedSizeBytes,
      );
    }
    if (!_manifest.containsKey(bookId)) {
      return _probe(
        BookCacheProbeStatus.missingPayload,
        bookId,
        identity,
        serializedSizeBytes: preparation.serializedSizeBytes,
      );
    }
    return _probe(
      BookCacheProbeStatus.validPayload,
      bookId,
      identity,
      serializedSizeBytes: preparation.serializedSizeBytes,
    );
  }

  BookCacheProbe _probe(
    BookCacheProbeStatus status,
    String bookId,
    BookCacheFileIdentity identity, {
    int? serializedSizeBytes,
  }) => BookCacheProbe(
    status: status,
    bookId: bookId,
    identity: identity,
    serializedSizeBytes: serializedSizeBytes,
    cacheLimitBytes: _maxCacheSizeBytes,
  );

  Future<void> _removeBookRecords(
    String bookId, {
    required bool removePayload,
  }) async {
    if (removePayload) {
      final file = _fileFor(bookId);
      if (await file.exists()) {
        await file.delete();
      }
      _manifest.remove(bookId);
      await _saveManifest();
    }
    if (_preparationManifest.remove(bookId) != null) {
      await _savePreparationManifest();
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
    await _loadPreparationManifest();
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

  Future<void> _loadPreparationManifest() async {
    final file = File(p.join(_cacheDir!.path, 'preparation_manifest.json'));
    if (!await file.exists()) {
      _preparationManifest = {};
      return;
    }
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _preparationManifest = data.map(
        (key, value) => MapEntry(
          key,
          _PreparationEntry.fromJson(value as Map<String, dynamic>),
        ),
      );
      _preparationManifestCorrupt = false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('BookCacheService: Failed to load preparation manifest: $e');
      }
      _preparationManifest = {};
      _preparationManifestCorrupt = true;
    }
  }

  Future<void> _savePreparationManifest() async {
    final file = File(p.join(_cacheDir!.path, 'preparation_manifest.json'));
    final data = _preparationManifest.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await file.writeAsString(jsonEncode(data));
    _preparationManifestCorrupt = false;
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

enum _PreparationOutcome { stored, tooLarge }

class _PreparationEntry {
  final _PreparationOutcome outcome;
  final String bookId;
  final int fileSizeBytes;
  final int modifiedMs;
  final int serializedSizeBytes;
  final int cacheLimitBytes;
  final int formatVersion;
  final String preparationVersion;

  const _PreparationEntry({
    required this.outcome,
    required this.bookId,
    required this.fileSizeBytes,
    required this.modifiedMs,
    required this.serializedSizeBytes,
    required this.cacheLimitBytes,
    required this.formatVersion,
    required this.preparationVersion,
  });

  factory _PreparationEntry.stored({
    required BookCacheFileIdentity identity,
    required int serializedSizeBytes,
    required int cacheLimitBytes,
  }) => _PreparationEntry(
    outcome: _PreparationOutcome.stored,
    bookId: identity.bookId,
    fileSizeBytes: identity.fileSizeBytes,
    modifiedMs: identity.modifiedMs,
    serializedSizeBytes: serializedSizeBytes,
    cacheLimitBytes: cacheLimitBytes,
    formatVersion: BookCacheService.parsedBookCacheFormatVersion,
    preparationVersion: BookCacheService.wholeBookPreparationVersion,
  );

  factory _PreparationEntry.tooLarge({
    required BookCacheFileIdentity identity,
    required int serializedSizeBytes,
    required int cacheLimitBytes,
  }) => _PreparationEntry(
    outcome: _PreparationOutcome.tooLarge,
    bookId: identity.bookId,
    fileSizeBytes: identity.fileSizeBytes,
    modifiedMs: identity.modifiedMs,
    serializedSizeBytes: serializedSizeBytes,
    cacheLimitBytes: cacheLimitBytes,
    formatVersion: BookCacheService.parsedBookCacheFormatVersion,
    preparationVersion: BookCacheService.wholeBookPreparationVersion,
  );

  bool matches(BookCacheFileIdentity identity, int cacheLimit) =>
      bookId == identity.bookId &&
      fileSizeBytes == identity.fileSizeBytes &&
      modifiedMs == identity.modifiedMs &&
      cacheLimitBytes == cacheLimit;

  Map<String, dynamic> toJson() => {
    'outcome': outcome.name,
    'bookId': bookId,
    'fileSizeBytes': fileSizeBytes,
    'modifiedMs': modifiedMs,
    'serializedSizeBytes': serializedSizeBytes,
    'cacheLimitBytes': cacheLimitBytes,
    'formatVersion': formatVersion,
    'preparationVersion': preparationVersion,
  };

  factory _PreparationEntry.fromJson(Map<String, dynamic> json) {
    final outcome = _PreparationOutcome.values.byName(
      json['outcome'] as String,
    );
    return _PreparationEntry(
      outcome: outcome,
      bookId: json['bookId'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int,
      modifiedMs: json['modifiedMs'] as int,
      serializedSizeBytes: json['serializedSizeBytes'] as int,
      cacheLimitBytes: json['cacheLimitBytes'] as int,
      formatVersion: json['formatVersion'] as int,
      preparationVersion: json['preparationVersion'] as String,
    );
  }
}
