import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book_chunk.dart';
import 'book_cache_service.dart';
import 'display_generation_coordinator.dart';
import 'progressive_display_state.dart';

const bool _segmentCacheDiagEnabled = bool.fromEnvironment('NALORI_EPUB_DIAG');
const String _segmentCacheDiagPrefix = 'NALORI_EPUB_DIAG';

int _segmentCacheDiagRssBytes() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return -1;
  }
}

void _segmentCacheDiagLog(String phase, Map<String, Object?> fields) {
  if (!_segmentCacheDiagEnabled) return;
  final parts = <String>[
    _segmentCacheDiagPrefix,
    'phase=$phase',
    'ts=${DateTime.now().toIso8601String()}',
    'rss=${_segmentCacheDiagRssBytes()}',
    'isolate=${Isolate.current.debugName ?? Isolate.current.hashCode}',
    for (final entry in fields.entries)
      if (entry.value != null) '${entry.key}=${entry.value}',
  ];
  // ignore: avoid_print
  print(parts.join(' '));
}

final class SegmentedDisplayCacheKey {
  const SegmentedDisplayCacheKey({
    required this.bookId,
    required this.cacheKey,
    required this.signature,
    required this.sourceChunkCount,
    this.displayCacheVersion =
        SegmentedDisplayCacheService.segmentedDisplayCacheFormatVersion,
    this.parserVersion = BookCacheService.parsedBookCacheFormatVersion,
  });

  final String bookId;
  final String cacheKey;
  final DisplayGenerationSignature signature;
  final int sourceChunkCount;
  final int displayCacheVersion;
  final int parserVersion;
}

final class DisplaySegmentRecord {
  const DisplaySegmentRecord({
    required this.sourceStart,
    required this.sourceEndExclusive,
    required this.actualSourceStart,
    required this.actualSourceEndExclusive,
    required this.fileName,
    required this.displayChunkCount,
    required this.displayToOriginalCount,
    required this.originalToDisplayCount,
    required this.checksum,
    required this.generationId,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.status,
    required this.fileSizeBytes,
  });

  final int sourceStart;
  final int sourceEndExclusive;
  final int actualSourceStart;
  final int actualSourceEndExclusive;
  final String fileName;
  final int displayChunkCount;
  final int displayToOriginalCount;
  final int originalToDisplayCount;
  final String checksum;
  final int generationId;
  final int createdAtMs;
  final int updatedAtMs;
  final String status;
  final int fileSizeBytes;

  SourceChunkRange get sourceRange =>
      SourceChunkRange(sourceStart, sourceEndExclusive);

  bool containsSource(int sourceIndex) =>
      sourceIndex >= sourceStart && sourceIndex < sourceEndExclusive;

  Map<String, dynamic> toJson() => {
    'sourceStart': sourceStart,
    'sourceEndExclusive': sourceEndExclusive,
    'actualSourceStart': actualSourceStart,
    'actualSourceEndExclusive': actualSourceEndExclusive,
    'fileName': fileName,
    'displayChunkCount': displayChunkCount,
    'displayToOriginalCount': displayToOriginalCount,
    'originalToDisplayCount': originalToDisplayCount,
    'checksum': checksum,
    'generationId': generationId,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
    'status': status,
    'fileSizeBytes': fileSizeBytes,
  };

  factory DisplaySegmentRecord.fromJson(Map<String, dynamic> json) {
    return DisplaySegmentRecord(
      sourceStart: json['sourceStart'] as int,
      sourceEndExclusive: json['sourceEndExclusive'] as int,
      actualSourceStart: json['actualSourceStart'] as int,
      actualSourceEndExclusive: json['actualSourceEndExclusive'] as int,
      fileName: json['fileName'] as String,
      displayChunkCount: json['displayChunkCount'] as int,
      displayToOriginalCount: json['displayToOriginalCount'] as int,
      originalToDisplayCount: json['originalToDisplayCount'] as int,
      checksum: json['checksum'] as String,
      generationId: json['generationId'] as int,
      createdAtMs: json['createdAtMs'] as int,
      updatedAtMs: json['updatedAtMs'] as int,
      status: json['status'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int,
    );
  }
}

final class SegmentedDisplayCacheManifest {
  const SegmentedDisplayCacheManifest({
    required this.version,
    required this.bookId,
    required this.cacheKey,
    required this.parsedContentVersion,
    required this.parserVersion,
    required this.displayLayoutVersion,
    required this.settingsSignature,
    required this.viewportSignature,
    required this.sourceChunkCount,
    required this.complete,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.segments,
  });

  final int version;
  final String bookId;
  final String cacheKey;
  final int parsedContentVersion;
  final int parserVersion;
  final String displayLayoutVersion;
  final String settingsSignature;
  final String viewportSignature;
  final int sourceChunkCount;
  final bool complete;
  final int createdAtMs;
  final int updatedAtMs;
  final List<DisplaySegmentRecord> segments;

  Map<String, dynamic> toJson() => {
    'version': version,
    'bookId': bookId,
    'cacheKey': cacheKey,
    'parsedContentVersion': parsedContentVersion,
    'parserVersion': parserVersion,
    'displayLayoutVersion': displayLayoutVersion,
    'settingsSignature': settingsSignature,
    'viewportSignature': viewportSignature,
    'sourceChunkCount': sourceChunkCount,
    'complete': complete,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
    'segments': segments.map((segment) => segment.toJson()).toList(),
  };

  factory SegmentedDisplayCacheManifest.fromJson(Map<String, dynamic> json) {
    return SegmentedDisplayCacheManifest(
      version: json['version'] as int,
      bookId: json['bookId'] as String,
      cacheKey: json['cacheKey'] as String,
      parsedContentVersion: json['parsedContentVersion'] as int,
      parserVersion: json['parserVersion'] as int,
      displayLayoutVersion: json['displayLayoutVersion'] as String,
      settingsSignature: json['settingsSignature'] as String,
      viewportSignature: json['viewportSignature'] as String,
      sourceChunkCount: json['sourceChunkCount'] as int,
      complete: json['complete'] as bool,
      createdAtMs: json['createdAtMs'] as int,
      updatedAtMs: json['updatedAtMs'] as int,
      segments: (json['segments'] as List<dynamic>)
          .map(
            (value) =>
                DisplaySegmentRecord.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

final class CachedDisplaySegment {
  const CachedDisplaySegment({
    required this.record,
    required this.displayChunks,
    required this.displayToOriginal,
    required this.originalToDisplay,
  });

  final DisplaySegmentRecord record;
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;

  DisplayRangeResult toResult({
    required DisplayRangeDirection direction,
    required int generationId,
    required String reason,
    int? targetOriginalIndex,
  }) {
    return DisplayRangeResult(
      request: DisplayRangeRequest(
        direction: direction,
        sourceRange: record.sourceRange,
        generationId: generationId,
        reason: reason,
        targetOriginalIndex: targetOriginalIndex,
      ),
      displayChunks: displayChunks,
      displayToOriginal: displayToOriginal,
      originalToDisplay: originalToDisplay,
      inspectedSourceChunks: record.sourceRange.length,
      elapsedMilliseconds: 0,
    );
  }
}

final class SegmentedDisplayCacheLoadResult {
  const SegmentedDisplayCacheLoadResult({
    required this.center,
    required this.before,
    required this.after,
    required this.manifest,
  });

  final CachedDisplaySegment? center;
  final CachedDisplaySegment? before;
  final CachedDisplaySegment? after;
  final SegmentedDisplayCacheManifest? manifest;

  bool get hasCenter => center != null;
}

final class _CachedSegmentManifest {
  const _CachedSegmentManifest({
    required this.manifest,
    required this.modifiedMs,
    required this.length,
  });

  final SegmentedDisplayCacheManifest manifest;
  final int modifiedMs;
  final int length;

  bool matches(FileStat stat) =>
      length == stat.size && modifiedMs == stat.modified.millisecondsSinceEpoch;
}

final class _SegmentCacheFileCoordinator {
  Future<void> tail = Future<void>.value();

  Future<T> exclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    tail = tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    tail = tail.catchError((_) {});
    return completer.future;
  }
}

final class SegmentedDisplayCacheService {
  SegmentedDisplayCacheService({required Directory rootDirectory})
    : _rootDirectory = rootDirectory;

  static const int segmentedDisplayCacheFormatVersion = 1;
  static const String segmentStatusReady = 'ready';
  static const int _maxSegmentedDisplayCacheBytes = 40 * 1024 * 1024;
  static const int _maxSegmentFileBytes = 3 * 1024 * 1024;
  static const int _maxSegmentKeyLength = 96;
  static final Map<String, Map<String, int>> _bookGenerationsByRoot = {};
  static final Map<String, Set<String>> _deletingBooksByRoot = {};
  static final Map<String, int> _globalGenerationsByRoot = {};
  static final Set<String> _resettingRoots = {};
  static final Map<String, _SegmentCacheFileCoordinator> _fileCoordinators = {};

  final Directory _rootDirectory;
  bool _initialized = false;
  Future<void> _writeQueue = Future<void>.value();
  final Map<String, _CachedSegmentManifest> _manifestCache = {};

  Map<String, int> get _bookGenerations => _bookGenerationsByRoot.putIfAbsent(
    _rootDirectory.absolute.path,
    () => <String, int>{},
  );

  Set<String> get _deletingBooks => _deletingBooksByRoot.putIfAbsent(
    _rootDirectory.absolute.path,
    () => <String>{},
  );

  int _cacheGeneration(String bookId) =>
      (_globalGenerationsByRoot[_rootDirectory.absolute.path] ?? 0) *
          0x100000000 +
      (_bookGenerations[bookId] ?? 0);

  bool get _resetting => _resettingRoots.contains(_rootDirectory.absolute.path);

  _SegmentCacheFileCoordinator get _fileCoordinator =>
      _fileCoordinators.putIfAbsent(
        _rootDirectory.absolute.path,
        _SegmentCacheFileCoordinator.new,
      );

  bool _writeInvalidated(String bookId, int cacheGeneration) =>
      _resetting ||
      _deletingBooks.contains(bookId) ||
      _cacheGeneration(bookId) != cacheGeneration;

  static Future<SegmentedDisplayCacheService> createDefault() async {
    final appDir = await getApplicationDocumentsDirectory();
    return SegmentedDisplayCacheService(
      rootDirectory: Directory(
        p.join(appDir.path, 'book_cache', 'display_segments'),
      ),
    );
  }

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    if (!await _rootDirectory.exists()) {
      await _rootDirectory.create(recursive: true);
    }
    await cleanupTemporaryFiles();
    _initialized = true;
  }

  Future<void> cleanupTemporaryFiles() async {
    if (!await _rootDirectory.exists()) return;
    final deleted = <String>[];
    await for (final entity in _rootDirectory.list(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.tmp')) continue;
      try {
        await entity.delete();
        deleted.add(path);
      } catch (_) {}
    }
    if (deleted.isNotEmpty) {
      _manifestCache.clear();
      _segmentCacheDiagLog('segment_cache_temp_cleanup', {
        'deleted': deleted.length,
      });
    }
  }

  Future<SegmentedDisplayCacheManifest?> loadManifest(
    SegmentedDisplayCacheKey key,
  ) async {
    await ensureInitialized();
    final file = _manifestFile(key.cacheKey);
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.file) {
      final cached = _manifestCache[key.cacheKey];
      if (cached != null &&
          cached.matches(stat) &&
          _isManifestCompatible(cached.manifest, key)) {
        _segmentCacheDiagLog('segment_cache_manifest_memory_hit', {
          'book': key.bookId,
          'cacheKey': key.cacheKey,
          'segments': cached.manifest.segments.length,
        });
        return cached.manifest;
      }
    } else {
      _manifestCache.remove(key.cacheKey);
    }
    _segmentCacheDiagLog('segment_cache_manifest_load', {
      'book': key.bookId,
      'cacheKey': key.cacheKey,
      'path': file.path,
    });
    if (stat.type != FileSystemEntityType.file) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final manifest = SegmentedDisplayCacheManifest.fromJson(json);
      if (!_isManifestCompatible(manifest, key)) {
        _segmentCacheDiagLog('segment_cache_signature_rejected', {
          'book': key.bookId,
          'cacheKey': key.cacheKey,
          'path': file.path,
          'manifestCacheKey': manifest.cacheKey,
          'manifestLayout': manifest.displayLayoutVersion,
          'manifestSettings': manifest.settingsSignature,
          'manifestViewport': manifest.viewportSignature,
          'requestedLayout': key.signature.layoutSignature,
          'requestedSettings': key.signature.settingsSignature,
          'requestedViewport': key.signature.viewportSignature,
        });
        _segmentCacheDiagLog('segment_cache_rejected', {
          'book': key.bookId,
          'cacheKey': key.cacheKey,
          'reason': 'incompatible_manifest',
        });
        return null;
      }
      final normalized = await _validatedManifest(key, manifest);
      if (normalized.segments.length != manifest.segments.length) {
        await _saveManifest(key.cacheKey, normalized);
        return normalized;
      }
      _manifestCache[key.cacheKey] = _CachedSegmentManifest(
        manifest: normalized,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
        length: stat.size,
      );
      return normalized;
    } catch (error) {
      _manifestCache.remove(key.cacheKey);
      _segmentCacheDiagLog('segment_cache_corrupt', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'reason': 'manifest_${error.runtimeType}',
      });
      return null;
    }
  }

  Future<SegmentedDisplayCacheLoadResult> loadAroundSource({
    required SegmentedDisplayCacheKey key,
    required int sourceIndex,
    bool includeAdjacent = true,
  }) async {
    final manifest = await loadManifest(key);
    if (manifest == null || manifest.segments.isEmpty) {
      _segmentCacheDiagLog('segment_cache_miss', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'sourceIndex': sourceIndex,
        'reason': 'no_manifest_or_segments',
      });
      return SegmentedDisplayCacheLoadResult(
        center: null,
        before: null,
        after: null,
        manifest: manifest,
      );
    }

    final sorted = [...manifest.segments]
      ..sort((a, b) => a.sourceStart.compareTo(b.sourceStart));
    final centerRecord = sorted
        .where((segment) => segment.containsSource(sourceIndex))
        .firstOrNull;
    if (centerRecord == null) {
      _segmentCacheDiagLog('segment_cache_miss', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'sourceIndex': sourceIndex,
        'reason': 'source_gap',
      });
      return SegmentedDisplayCacheLoadResult(
        center: null,
        before: null,
        after: null,
        manifest: manifest,
      );
    }

    final center = await loadSegment(key: key, record: centerRecord);
    if (center == null) {
      return SegmentedDisplayCacheLoadResult(
        center: null,
        before: null,
        after: null,
        manifest: await loadManifest(key),
      );
    }

    CachedDisplaySegment? before;
    CachedDisplaySegment? after;
    if (includeAdjacent) {
      final beforeRecord = sorted
          .where(
            (segment) => segment.sourceEndExclusive == centerRecord.sourceStart,
          )
          .lastOrNull;
      final afterRecord = sorted
          .where(
            (segment) => segment.sourceStart == centerRecord.sourceEndExclusive,
          )
          .firstOrNull;
      if (beforeRecord != null) {
        before = await loadSegment(key: key, record: beforeRecord);
      }
      if (afterRecord != null) {
        after = await loadSegment(key: key, record: afterRecord);
      }
    }

    _segmentCacheDiagLog('segment_cache_hit', {
      'book': key.bookId,
      'cacheKey': key.cacheKey,
      'sourceIndex': sourceIndex,
      'centerStart': center.record.sourceStart,
      'centerEnd': center.record.sourceEndExclusive,
      'loadedSegments': 1 + (before == null ? 0 : 1) + (after == null ? 0 : 1),
    });
    return SegmentedDisplayCacheLoadResult(
      center: center,
      before: before,
      after: after,
      manifest: manifest,
    );
  }

  Future<CachedDisplaySegment?> loadSegment({
    required SegmentedDisplayCacheKey key,
    required DisplaySegmentRecord record,
  }) async {
    await ensureInitialized();
    final stopwatch = Stopwatch()..start();
    try {
      final file = _segmentFile(key.cacheKey, record.fileName);
      if (!await file.exists()) {
        await _removeSegmentRecord(key, record, 'missing_file');
        return null;
      }
      final bytes = await file.readAsBytes();
      if (_checksum(bytes) != record.checksum) {
        await _removeSegmentRecord(key, record, 'checksum_mismatch');
        return null;
      }
      final decoded = await Isolate.run(() => _deserializeSegment(bytes));
      if (!_isSegmentPayloadCompatible(decoded, key, record)) {
        await _removeSegmentRecord(key, record, 'metadata_mismatch');
        return null;
      }
      stopwatch.stop();
      _segmentCacheDiagLog('segment_cache_range_loaded', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'sourceStart': record.sourceStart,
        'sourceEndExclusive': record.sourceEndExclusive,
        'displayChunks': decoded.displayChunks.length,
        'bytes': bytes.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'path': file.path,
      });
      return CachedDisplaySegment(
        record: record,
        displayChunks: decoded.displayChunks,
        displayToOriginal: decoded.displayToOriginal,
        originalToDisplay: decoded.originalToDisplay,
      );
    } catch (error) {
      await _removeSegmentRecord(key, record, 'corrupt_${error.runtimeType}');
      return null;
    }
  }

  Future<CachedDisplaySegment?> loadRange({
    required SegmentedDisplayCacheKey key,
    required SourceChunkRange sourceRange,
  }) async {
    final manifest = await loadManifest(key);
    if (manifest == null) return null;
    final record = manifest.segments
        .where(
          (segment) =>
              segment.sourceStart == sourceRange.start &&
              segment.sourceEndExclusive == sourceRange.endExclusive,
        )
        .firstOrNull;
    if (record == null) {
      _segmentCacheDiagLog('segment_cache_miss', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'sourceStart': sourceRange.start,
        'sourceEndExclusive': sourceRange.endExclusive,
        'reason': 'range_not_cached',
      });
      return null;
    }
    final segment = await loadSegment(key: key, record: record);
    if (segment != null) {
      _segmentCacheDiagLog('segment_cache_hit', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'sourceStart': sourceRange.start,
        'sourceEndExclusive': sourceRange.endExclusive,
        'loadedSegments': 1,
        'mode': 'exact_range',
      });
    }
    return segment;
  }

  Future<bool> corruptSegmentAroundSourceForDiagnostics({
    required SegmentedDisplayCacheKey key,
    required int sourceIndex,
  }) async {
    if (!_segmentCacheDiagEnabled) return false;
    await ensureInitialized();
    final manifest = await loadManifest(key);
    final record = manifest?.segments
        .where((segment) => segment.containsSource(sourceIndex))
        .firstOrNull;
    if (record == null) {
      _segmentCacheDiagLog('segment_cache_diagnostic_corrupt_skipped', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'sourceIndex': sourceIndex,
        'reason': 'no_matching_segment',
      });
      return false;
    }
    final file = _segmentFile(key.cacheKey, record.fileName);
    if (!await file.exists()) {
      _segmentCacheDiagLog('segment_cache_diagnostic_corrupt_skipped', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'sourceIndex': sourceIndex,
        'sourceStart': record.sourceStart,
        'sourceEndExclusive': record.sourceEndExclusive,
        'reason': 'missing_file',
      });
      return false;
    }
    await file.writeAsBytes(utf8.encode('nalori diagnostic corrupt segment'));
    _manifestCache.remove(key.cacheKey);
    _segmentCacheDiagLog('segment_cache_diagnostic_corrupted', {
      'book': key.bookId,
      'cacheKey': key.cacheKey,
      'sourceIndex': sourceIndex,
      'sourceStart': record.sourceStart,
      'sourceEndExclusive': record.sourceEndExclusive,
      'path': file.path,
    });
    return true;
  }

  Future<void> writeSegment({
    required SegmentedDisplayCacheKey key,
    required DisplayRangeResult result,
    required int generationId,
    bool Function()? shouldWrite,
  }) {
    final cacheGeneration = _cacheGeneration(key.bookId);
    final operation = _writeQueue.then(
      (_) => _fileCoordinator.exclusive(
        () => _writeSegment(
          key: key,
          result: result,
          generationId: generationId,
          shouldWrite: shouldWrite,
          cacheGeneration: cacheGeneration,
        ),
      ),
    );
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _writeSegment({
    required SegmentedDisplayCacheKey key,
    required DisplayRangeResult result,
    required int generationId,
    bool Function()? shouldWrite,
    required int cacheGeneration,
  }) async {
    await ensureInitialized();
    if (_writeInvalidated(key.bookId, cacheGeneration)) return;
    if (!result.succeeded || result.displayChunks.isEmpty) return;
    if (shouldWrite != null && !shouldWrite()) {
      _segmentCacheDiagLog('segment_cache_rejected', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'range': result.request.sourceRange.toString(),
        'reason': 'stale_before_serialize',
      });
      return;
    }

    final range = result.request.sourceRange;
    final fileName = _segmentFileName(range);
    final dir = await _signatureDirectory(key.cacheKey);
    final tmpFile = File(p.join(dir.path, '$fileName.tmp'));
    final finalFile = File(p.join(dir.path, fileName));

    final stopwatch = Stopwatch()..start();
    _segmentCacheDiagLog('segment_cache_write_begin', {
      'book': key.bookId,
      'cacheKey': key.cacheKey,
      'sourceStart': range.start,
      'sourceEndExclusive': range.endExclusive,
      'displayChunks': result.displayChunks.length,
      'generationId': generationId,
      'path': finalFile.path,
    });

    try {
      final bytes = await Isolate.run(
        () => _serializeSegment(
          key: key,
          result: result,
          generationId: generationId,
          status: segmentStatusReady,
        ),
      );
      if (bytes.length > _maxSegmentFileBytes) {
        _segmentCacheDiagLog('segment_cache_rejected', {
          'book': key.bookId,
          'cacheKey': key.cacheKey,
          'range': range.toString(),
          'reason': 'segment_too_large',
          'bytes': bytes.length,
        });
        return;
      }
      if (shouldWrite != null && !shouldWrite()) {
        _segmentCacheDiagLog('segment_cache_rejected', {
          'book': key.bookId,
          'cacheKey': key.cacheKey,
          'range': range.toString(),
          'reason': 'stale_after_serialize',
        });
        return;
      }
      if (_writeInvalidated(key.bookId, cacheGeneration)) return;

      await tmpFile.writeAsBytes(bytes, flush: true);
      final validated = _deserializeSegment(await tmpFile.readAsBytes());
      if (!_isRangeEqual(validated.sourceStart, validated.sourceEnd, range)) {
        await tmpFile.delete();
        throw const FormatException('Segment validation range mismatch');
      }
      if (shouldWrite != null && !shouldWrite()) {
        await tmpFile.delete();
        _segmentCacheDiagLog('segment_cache_rejected', {
          'book': key.bookId,
          'cacheKey': key.cacheKey,
          'range': range.toString(),
          'reason': 'stale_before_rename',
        });
        return;
      }
      if (_writeInvalidated(key.bookId, cacheGeneration)) {
        await tmpFile.delete();
        return;
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tmpFile.rename(finalFile.path);

      final checksum = _checksum(bytes);
      final now = DateTime.now().millisecondsSinceEpoch;
      final record = DisplaySegmentRecord(
        sourceStart: range.start,
        sourceEndExclusive: range.endExclusive,
        actualSourceStart: range.start,
        actualSourceEndExclusive: range.endExclusive,
        fileName: fileName,
        displayChunkCount: result.displayChunks.length,
        displayToOriginalCount: result.displayToOriginal.length,
        originalToDisplayCount: result.originalToDisplay.length,
        checksum: checksum,
        generationId: generationId,
        createdAtMs: now,
        updatedAtMs: now,
        status: segmentStatusReady,
        fileSizeBytes: bytes.length,
      );

      if (shouldWrite != null && !shouldWrite()) {
        if (await finalFile.exists()) await finalFile.delete();
        _segmentCacheDiagLog('segment_cache_rejected', {
          'book': key.bookId,
          'cacheKey': key.cacheKey,
          'range': range.toString(),
          'reason': 'stale_after_rename',
        });
        return;
      }
      if (_writeInvalidated(key.bookId, cacheGeneration)) {
        if (await finalFile.exists()) await finalFile.delete();
        return;
      }

      final manifestStopwatch = Stopwatch()..start();
      await _upsertSegmentRecord(key, record);
      manifestStopwatch.stop();
      await _evictUntilFits(excludeCacheKey: key.cacheKey);
      stopwatch.stop();
      _segmentCacheDiagLog('segment_cache_write_end', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'sourceStart': range.start,
        'sourceEndExclusive': range.endExclusive,
        'bytes': bytes.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'manifestUpdateMs': manifestStopwatch.elapsedMilliseconds,
        'path': finalFile.path,
      });
    } catch (error) {
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
      _segmentCacheDiagLog('segment_cache_rejected', {
        'book': key.bookId,
        'cacheKey': key.cacheKey,
        'range': range.toString(),
        'reason': 'write_${error.runtimeType}',
      });
      if (kDebugMode) {
        debugPrint('SegmentedDisplayCacheService: write failed: $error');
      }
    }
  }

  Future<void> deleteForBook(String bookId) async {
    _bookGenerations[bookId] = (_bookGenerations[bookId] ?? 0) + 1;
    _deletingBooks.add(bookId);
    try {
      await _fileCoordinator.exclusive(() async {
        await ensureInitialized();
        if (!await _rootDirectory.exists()) return;
        final deleted = <String>[];
        await for (final entity in _rootDirectory.list()) {
          if (entity is! Directory) continue;
          final manifestFile = File(p.join(entity.path, 'manifest.json'));
          if (!await manifestFile.exists()) continue;
          try {
            final manifest = SegmentedDisplayCacheManifest.fromJson(
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>,
            );
            if (manifest.bookId != bookId) continue;
            await entity.delete(recursive: true);
            deleted.add(entity.path);
          } catch (_) {}
        }
        _segmentCacheDiagLog('segment_cache_delete_for_book', {
          'book': bookId,
          'deletedPaths': deleted,
        });
      });
    } finally {
      _deletingBooks.remove(bookId);
    }
  }

  Future<void> clearAll() async {
    final rootKey = _rootDirectory.absolute.path;
    _globalGenerationsByRoot[rootKey] =
        (_globalGenerationsByRoot[rootKey] ?? 0) + 1;
    _resettingRoots.add(rootKey);
    try {
      await _fileCoordinator.exclusive(() async {
        if (await _rootDirectory.exists()) {
          await _rootDirectory.delete(recursive: true);
        }
        await _rootDirectory.create(recursive: true);
        _manifestCache.clear();
      });
    } finally {
      _resettingRoots.remove(rootKey);
    }
  }

  Future<Directory> _signatureDirectory(String cacheKey) async {
    final dir = Directory(p.join(_rootDirectory.path, _safeKey(cacheKey)));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _manifestFile(String cacheKey) {
    return File(
      p.join(_rootDirectory.path, _safeKey(cacheKey), 'manifest.json'),
    );
  }

  File _segmentFile(String cacheKey, String fileName) {
    return File(p.join(_rootDirectory.path, _safeKey(cacheKey), fileName));
  }

  Future<void> _upsertSegmentRecord(
    SegmentedDisplayCacheKey key,
    DisplaySegmentRecord record,
  ) async {
    final existing = await loadManifest(key);
    final now = DateTime.now().millisecondsSinceEpoch;
    final records =
        (existing?.segments ?? const <DisplaySegmentRecord>[])
            .where(
              (segment) =>
                  segment.sourceStart != record.sourceStart ||
                  segment.sourceEndExclusive != record.sourceEndExclusive,
            )
            .toList()
          ..add(record)
          ..sort((a, b) => a.sourceStart.compareTo(b.sourceStart));
    final manifest = SegmentedDisplayCacheManifest(
      version: segmentedDisplayCacheFormatVersion,
      bookId: key.bookId,
      cacheKey: key.cacheKey,
      parsedContentVersion: key.signature.parsedContentVersion,
      parserVersion: key.parserVersion,
      displayLayoutVersion: key.signature.layoutSignature,
      settingsSignature: key.signature.settingsSignature,
      viewportSignature: key.signature.viewportSignature,
      sourceChunkCount: key.sourceChunkCount,
      complete: _isCompleteCoverage(records, key.sourceChunkCount),
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
      segments: records,
    );
    await _saveManifest(key.cacheKey, manifest);
  }

  Future<void> _removeSegmentRecord(
    SegmentedDisplayCacheKey key,
    DisplaySegmentRecord record,
    String reason,
  ) async {
    final manifest = await loadManifest(key);
    if (manifest == null) return;
    final file = _segmentFile(key.cacheKey, record.fileName);
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    final records = manifest.segments
        .where(
          (segment) =>
              segment.sourceStart != record.sourceStart ||
              segment.sourceEndExclusive != record.sourceEndExclusive,
        )
        .toList();
    await _saveManifest(
      key.cacheKey,
      SegmentedDisplayCacheManifest(
        version: manifest.version,
        bookId: manifest.bookId,
        cacheKey: manifest.cacheKey,
        parsedContentVersion: manifest.parsedContentVersion,
        parserVersion: manifest.parserVersion,
        displayLayoutVersion: manifest.displayLayoutVersion,
        settingsSignature: manifest.settingsSignature,
        viewportSignature: manifest.viewportSignature,
        sourceChunkCount: manifest.sourceChunkCount,
        complete: false,
        createdAtMs: manifest.createdAtMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        segments: records,
      ),
    );
    _segmentCacheDiagLog('segment_cache_corrupt', {
      'book': key.bookId,
      'cacheKey': key.cacheKey,
      'sourceStart': record.sourceStart,
      'sourceEndExclusive': record.sourceEndExclusive,
      'reason': reason,
    });
  }

  Future<SegmentedDisplayCacheManifest> _validatedManifest(
    SegmentedDisplayCacheKey key,
    SegmentedDisplayCacheManifest manifest,
  ) async {
    final valid = <DisplaySegmentRecord>[];
    final seen = <String>{};
    for (final record in manifest.segments) {
      final identity = '${record.sourceStart}:${record.sourceEndExclusive}';
      if (!seen.add(identity)) continue;
      if (record.status != segmentStatusReady) continue;
      if (record.sourceStart < 0 ||
          record.sourceEndExclusive <= record.sourceStart ||
          record.sourceEndExclusive > key.sourceChunkCount) {
        continue;
      }
      final overlaps = valid.any(
        (existing) =>
            record.sourceStart < existing.sourceEndExclusive &&
            record.sourceEndExclusive > existing.sourceStart,
      );
      if (overlaps) continue;
      final file = _segmentFile(key.cacheKey, record.fileName);
      if (!await file.exists()) continue;
      valid.add(record);
    }
    valid.sort((a, b) => a.sourceStart.compareTo(b.sourceStart));
    return SegmentedDisplayCacheManifest(
      version: manifest.version,
      bookId: manifest.bookId,
      cacheKey: manifest.cacheKey,
      parsedContentVersion: manifest.parsedContentVersion,
      parserVersion: manifest.parserVersion,
      displayLayoutVersion: manifest.displayLayoutVersion,
      settingsSignature: manifest.settingsSignature,
      viewportSignature: manifest.viewportSignature,
      sourceChunkCount: manifest.sourceChunkCount,
      complete: _isCompleteCoverage(valid, manifest.sourceChunkCount),
      createdAtMs: manifest.createdAtMs,
      updatedAtMs: manifest.updatedAtMs,
      segments: valid,
    );
  }

  Future<void> _saveManifest(
    String cacheKey,
    SegmentedDisplayCacheManifest manifest,
  ) async {
    final dir = await _signatureDirectory(cacheKey);
    final temp = File(p.join(dir.path, 'manifest.json.tmp'));
    final file = File(p.join(dir.path, 'manifest.json'));
    final stopwatch = Stopwatch()..start();
    await temp.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
    final stat = await file.stat();
    _manifestCache[cacheKey] = _CachedSegmentManifest(
      manifest: manifest,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      length: stat.size,
    );
    stopwatch.stop();
    _segmentCacheDiagLog('segment_cache_manifest_update', {
      'book': manifest.bookId,
      'cacheKey': cacheKey,
      'segments': manifest.segments.length,
      'bytes': await file.length(),
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
  }

  Future<void> _evictUntilFits({required String excludeCacheKey}) async {
    var total = 0;
    final signatures = <({Directory dir, int size, int accessed})>[];
    if (!await _rootDirectory.exists()) return;
    await for (final entity in _rootDirectory.list()) {
      if (entity is! Directory) continue;
      var size = 0;
      var accessed = 0;
      await for (final child in entity.list(recursive: true)) {
        if (child is File) size += await child.length();
      }
      final manifestFile = File(p.join(entity.path, 'manifest.json'));
      if (await manifestFile.exists()) {
        try {
          final manifest = SegmentedDisplayCacheManifest.fromJson(
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>,
          );
          accessed = manifest.updatedAtMs;
        } catch (_) {}
      }
      total += size;
      signatures.add((dir: entity, size: size, accessed: accessed));
    }
    if (total <= _maxSegmentedDisplayCacheBytes) return;
    signatures.sort((a, b) => a.accessed.compareTo(b.accessed));
    for (final signature in signatures) {
      if (total <= _maxSegmentedDisplayCacheBytes) break;
      if (p.basename(signature.dir.path) == _safeKey(excludeCacheKey)) continue;
      await signature.dir.delete(recursive: true);
      total -= signature.size;
    }
  }

  bool _isManifestCompatible(
    SegmentedDisplayCacheManifest manifest,
    SegmentedDisplayCacheKey key,
  ) {
    return manifest.version == segmentedDisplayCacheFormatVersion &&
        manifest.bookId == key.bookId &&
        manifest.cacheKey == key.cacheKey &&
        manifest.parsedContentVersion == key.signature.parsedContentVersion &&
        manifest.parserVersion == key.parserVersion &&
        manifest.displayLayoutVersion == key.signature.layoutSignature &&
        manifest.settingsSignature == key.signature.settingsSignature &&
        manifest.viewportSignature == key.signature.viewportSignature &&
        manifest.sourceChunkCount == key.sourceChunkCount;
  }

  static bool _isCompleteCoverage(
    List<DisplaySegmentRecord> records,
    int sourceChunkCount,
  ) {
    if (records.isEmpty) return sourceChunkCount == 0;
    final sorted = [...records]
      ..sort((a, b) => a.sourceStart.compareTo(b.sourceStart));
    if (sorted.first.sourceStart != 0) return false;
    var cursor = 0;
    for (final record in sorted) {
      if (record.sourceStart != cursor) return false;
      cursor = record.sourceEndExclusive;
    }
    return cursor == sourceChunkCount;
  }

  static bool _isSegmentPayloadCompatible(
    _SerializedDisplaySegment decoded,
    SegmentedDisplayCacheKey key,
    DisplaySegmentRecord record,
  ) {
    return decoded.version == segmentedDisplayCacheFormatVersion &&
        decoded.bookId == key.bookId &&
        decoded.cacheKey == key.cacheKey &&
        decoded.parsedContentVersion == key.signature.parsedContentVersion &&
        decoded.displayLayoutVersion == key.signature.layoutSignature &&
        decoded.settingsSignature == key.signature.settingsSignature &&
        decoded.viewportSignature == key.signature.viewportSignature &&
        decoded.sourceStart == record.sourceStart &&
        decoded.sourceEnd == record.sourceEndExclusive;
  }

  static Uint8List _serializeSegment({
    required SegmentedDisplayCacheKey key,
    required DisplayRangeResult result,
    required int generationId,
    required String status,
  }) {
    final range = result.request.sourceRange;
    final data = {
      'version': segmentedDisplayCacheFormatVersion,
      'bookId': key.bookId,
      'cacheKey': key.cacheKey,
      'parsedContentVersion': key.signature.parsedContentVersion,
      'parserVersion': key.parserVersion,
      'displayLayoutVersion': key.signature.layoutSignature,
      'settingsSignature': key.signature.settingsSignature,
      'viewportSignature': key.signature.viewportSignature,
      'sourceChunkCount': key.sourceChunkCount,
      'sourceStart': range.start,
      'sourceEndExclusive': range.endExclusive,
      'actualSourceStart': range.start,
      'actualSourceEndExclusive': range.endExclusive,
      'generationId': generationId,
      'status': status,
      'displayChunks': result.displayChunks
          .map((chunk) => chunk.toJson())
          .toList(),
      'displayToOriginal': result.displayToOriginal,
      'originalToDisplay': result.originalToDisplay.map(
        (key, value) => MapEntry('$key', value),
      ),
    };
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(data))));
  }

  static _SerializedDisplaySegment _deserializeSegment(Uint8List bytes) {
    final data =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    final displayChunks = (data['displayChunks'] as List<dynamic>)
        .map((value) => BookChunk.fromJson(value as Map<String, dynamic>))
        .toList();
    final displayToOriginal = (data['displayToOriginal'] as List<dynamic>)
        .map((value) => (value as List<dynamic>).cast<int>())
        .toList();
    final originalToDisplay =
        (data['originalToDisplay'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(int.parse(key), value as int),
        );
    return _SerializedDisplaySegment(
      version: data['version'] as int,
      bookId: data['bookId'] as String,
      cacheKey: data['cacheKey'] as String,
      parsedContentVersion: data['parsedContentVersion'] as int,
      displayLayoutVersion: data['displayLayoutVersion'] as String,
      settingsSignature: data['settingsSignature'] as String,
      viewportSignature: data['viewportSignature'] as String,
      sourceStart: data['sourceStart'] as int,
      sourceEnd: data['sourceEndExclusive'] as int,
      displayChunks: displayChunks,
      displayToOriginal: displayToOriginal,
      originalToDisplay: originalToDisplay,
    );
  }

  static bool _isRangeEqual(int start, int end, SourceChunkRange range) {
    return start == range.start && end == range.endExclusive;
  }

  static String _segmentFileName(SourceChunkRange range) {
    return 'segment_${range.start}_${range.endExclusive}.json.gz';
  }

  static String _safeKey(String key) {
    final sanitized = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    if (sanitized.length <= _maxSegmentKeyLength) return sanitized;
    final hash = _fnv1aHex(utf8.encode(key));
    return '${sanitized.substring(0, _maxSegmentKeyLength - hash.length - 1)}_$hash';
  }

  static String _checksum(Uint8List bytes) => _fnv1aHex(bytes);

  static String _fnv1aHex(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

final class _SerializedDisplaySegment {
  const _SerializedDisplaySegment({
    required this.version,
    required this.bookId,
    required this.cacheKey,
    required this.parsedContentVersion,
    required this.displayLayoutVersion,
    required this.settingsSignature,
    required this.viewportSignature,
    required this.sourceStart,
    required this.sourceEnd,
    required this.displayChunks,
    required this.displayToOriginal,
    required this.originalToDisplay,
  });

  final int version;
  final String bookId;
  final String cacheKey;
  final int parsedContentVersion;
  final String displayLayoutVersion;
  final String settingsSignature;
  final String viewportSignature;
  final int sourceStart;
  final int sourceEnd;
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;
}
