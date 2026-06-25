import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lazy_parsed_book.dart';

const bool _parsedSectionDiagEnabled = bool.fromEnvironment('NALORI_EPUB_DIAG');
const String _parsedSectionDiagPrefix = 'NALORI_EPUB_DIAG';

void _parsedSectionDiagLog(String phase, Map<String, Object?> fields) {
  if (!_parsedSectionDiagEnabled) return;
  final parts = <String>[
    _parsedSectionDiagPrefix,
    'phase=$phase',
    'ts=${DateTime.now().toIso8601String()}',
    for (final entry in fields.entries)
      if (entry.value != null) '${entry.key}=${entry.value}',
  ];
  // ignore: avoid_print
  print(parts.join(' '));
}

final class ParsedSectionCacheRecord {
  const ParsedSectionCacheRecord({
    required this.spineIndex,
    required this.href,
    required this.fullPath,
    required this.sourceChecksum,
    required this.parserVersion,
    required this.fileName,
    required this.chunkCount,
    required this.anchorCount,
    required this.wordCount,
    required this.textCharCount,
    required this.resourceHrefs,
    required this.checksum,
    required this.fileSizeBytes,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.status,
  });

  final int spineIndex;
  final String href;
  final String fullPath;
  final String sourceChecksum;
  final String parserVersion;
  final String fileName;
  final int chunkCount;
  final int anchorCount;
  final int wordCount;
  final int textCharCount;
  final List<String> resourceHrefs;
  final String checksum;
  final int fileSizeBytes;
  final int createdAtMs;
  final int updatedAtMs;
  final String status;

  bool matches(LazySectionIdentity identity, String parserVersion) {
    return spineIndex == identity.spineIndex &&
        href == identity.href &&
        fullPath == identity.fullPath &&
        sourceChecksum == identity.sourceChecksum &&
        this.parserVersion == parserVersion &&
        status == 'ready';
  }

  Map<String, dynamic> toJson() => {
    'spineIndex': spineIndex,
    'href': href,
    'fullPath': fullPath,
    'sourceChecksum': sourceChecksum,
    'parserVersion': parserVersion,
    'fileName': fileName,
    'chunkCount': chunkCount,
    'anchorCount': anchorCount,
    'wordCount': wordCount,
    'textCharCount': textCharCount,
    'resourceHrefs': resourceHrefs,
    'checksum': checksum,
    'fileSizeBytes': fileSizeBytes,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
    'status': status,
  };

  factory ParsedSectionCacheRecord.fromJson(Map<String, dynamic> json) {
    return ParsedSectionCacheRecord(
      spineIndex: json['spineIndex'] as int,
      href: json['href'] as String,
      fullPath: json['fullPath'] as String,
      sourceChecksum: json['sourceChecksum'] as String,
      parserVersion: json['parserVersion'] as String,
      fileName: json['fileName'] as String,
      chunkCount: json['chunkCount'] as int,
      anchorCount: json['anchorCount'] as int,
      wordCount: json['wordCount'] as int,
      textCharCount: json['textCharCount'] as int,
      resourceHrefs:
          (json['resourceHrefs'] as List<dynamic>?)?.cast<String>() ?? const [],
      checksum: json['checksum'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int,
      createdAtMs: json['createdAtMs'] as int,
      updatedAtMs: json['updatedAtMs'] as int,
      status: json['status'] as String,
    );
  }
}

final class ParsedSectionCacheManifest {
  const ParsedSectionCacheManifest({
    required this.version,
    required this.bookId,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.records,
    this.hydration,
  });

  final int version;
  final String bookId;
  final int createdAtMs;
  final int updatedAtMs;
  final List<ParsedSectionCacheRecord> records;
  final ParsedSectionHydrationManifest? hydration;

  Map<String, dynamic> toJson() => {
    'version': version,
    'bookId': bookId,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
    'records': records.map((record) => record.toJson()).toList(),
    if (hydration != null) 'hydration': hydration!.toJson(),
  };

  factory ParsedSectionCacheManifest.fromJson(Map<String, dynamic> json) {
    return ParsedSectionCacheManifest(
      version: json['version'] as int,
      bookId: json['bookId'] as String,
      createdAtMs: json['createdAtMs'] as int,
      updatedAtMs: json['updatedAtMs'] as int,
      records: (json['records'] as List<dynamic>)
          .map(
            (entry) => ParsedSectionCacheRecord.fromJson(
              entry as Map<String, dynamic>,
            ),
          )
          .toList(),
      hydration: json['hydration'] == null
          ? null
          : ParsedSectionHydrationManifest.fromJson(
              json['hydration'] as Map<String, dynamic>,
            ),
    );
  }
}

final class ParsedSectionHydrationManifest {
  const ParsedSectionHydrationManifest({
    required this.bookId,
    required this.sourceChecksum,
    required this.parserVersion,
    required this.totalReadableSpineSections,
    required this.completedSpineIndexes,
    required this.pendingSpineIndexes,
    required this.failedSpineIndexes,
    required this.skippedSpineIndexes,
    required this.status,
    required this.updatedAtMs,
  });

  final String bookId;
  final String sourceChecksum;
  final String parserVersion;
  final int totalReadableSpineSections;
  final List<int> completedSpineIndexes;
  final List<int> pendingSpineIndexes;
  final List<int> failedSpineIndexes;
  final List<int> skippedSpineIndexes;
  final String status;
  final int updatedAtMs;

  double get completionFraction {
    if (totalReadableSpineSections <= 0) return 1;
    return completedSpineIndexes.length / totalReadableSpineSections;
  }

  bool matches({
    required String bookId,
    required String sourceChecksum,
    required String parserVersion,
  }) {
    return this.bookId == bookId &&
        this.sourceChecksum == sourceChecksum &&
        this.parserVersion == parserVersion &&
        status != 'invalidated';
  }

  ParsedSectionHydrationManifest copyWith({
    List<int>? completedSpineIndexes,
    List<int>? pendingSpineIndexes,
    List<int>? failedSpineIndexes,
    List<int>? skippedSpineIndexes,
    String? status,
    int? updatedAtMs,
  }) {
    return ParsedSectionHydrationManifest(
      bookId: bookId,
      sourceChecksum: sourceChecksum,
      parserVersion: parserVersion,
      totalReadableSpineSections: totalReadableSpineSections,
      completedSpineIndexes:
          completedSpineIndexes ?? this.completedSpineIndexes,
      pendingSpineIndexes: pendingSpineIndexes ?? this.pendingSpineIndexes,
      failedSpineIndexes: failedSpineIndexes ?? this.failedSpineIndexes,
      skippedSpineIndexes: skippedSpineIndexes ?? this.skippedSpineIndexes,
      status: status ?? this.status,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'sourceChecksum': sourceChecksum,
    'parserVersion': parserVersion,
    'totalReadableSpineSections': totalReadableSpineSections,
    'completedSpineIndexes': completedSpineIndexes,
    'pendingSpineIndexes': pendingSpineIndexes,
    'failedSpineIndexes': failedSpineIndexes,
    'skippedSpineIndexes': skippedSpineIndexes,
    'status': status,
    'updatedAtMs': updatedAtMs,
  };

  factory ParsedSectionHydrationManifest.fromJson(Map<String, dynamic> json) {
    return ParsedSectionHydrationManifest(
      bookId: json['bookId'] as String,
      sourceChecksum: json['sourceChecksum'] as String,
      parserVersion: json['parserVersion'] as String,
      totalReadableSpineSections: json['totalReadableSpineSections'] as int,
      completedSpineIndexes: (json['completedSpineIndexes'] as List<dynamic>)
          .cast<int>(),
      pendingSpineIndexes: (json['pendingSpineIndexes'] as List<dynamic>)
          .cast<int>(),
      failedSpineIndexes: (json['failedSpineIndexes'] as List<dynamic>)
          .cast<int>(),
      skippedSpineIndexes: (json['skippedSpineIndexes'] as List<dynamic>)
          .cast<int>(),
      status: json['status'] as String,
      updatedAtMs: json['updatedAtMs'] as int,
    );
  }
}

final class _CachedParsedSectionManifest {
  const _CachedParsedSectionManifest({
    required this.manifest,
    required this.modifiedMs,
    required this.length,
  });

  final ParsedSectionCacheManifest manifest;
  final int modifiedMs;
  final int length;

  bool matches(FileStat stat) =>
      length == stat.size && modifiedMs == stat.modified.millisecondsSinceEpoch;
}

final class ParsedSectionCacheService {
  ParsedSectionCacheService({Directory? rootDirectory})
    : _rootDirectory = rootDirectory;

  static const String directoryName = 'parsed_sections';

  final Directory? _rootDirectory;
  Future<void> _writeQueue = Future<void>.value();
  final Map<String, _CachedParsedSectionManifest> _manifestCache = {};

  Future<Directory> _root() async {
    final configured = _rootDirectory;
    if (configured != null) {
      if (!await configured.exists()) {
        await configured.create(recursive: true);
      }
      return configured;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(appDir.path, 'book_cache', directoryName));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  Future<void> cleanupTemporaryFiles() async {
    final root = await _root();
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.tmp')) continue;
      _parsedSectionDiagLog('lazy_section_cache_temp_cleanup', {
        'path': entity.path,
      });
      await entity.delete();
      _manifestCache.clear();
    }
  }

  Future<void> deleteForBook(String bookId) async {
    final dir = await _bookDir(bookId);
    if (await dir.exists()) {
      _parsedSectionDiagLog('lazy_section_cache_delete_for_book', {
        'book': bookId,
        'path': dir.path,
      });
      await dir.delete(recursive: true);
      _manifestCache.remove(bookId);
    }
  }

  Future<ParsedSectionCacheManifest?> loadManifest(String bookId) async {
    final file = await _manifestFile(bookId);
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.file) {
      final cached = _manifestCache[bookId];
      if (cached != null && cached.matches(stat)) {
        _parsedSectionDiagLog('lazy_section_manifest_memory_hit', {
          'book': bookId,
          'records': cached.manifest.records.length,
          'hydrationStatus': cached.manifest.hydration?.status,
        });
        return cached.manifest;
      }
    } else {
      _manifestCache.remove(bookId);
    }
    _parsedSectionDiagLog('lazy_section_manifest_load', {
      'book': bookId,
      'path': file.path,
    });
    if (stat.type != FileSystemEntityType.file) return null;
    try {
      final manifest = ParsedSectionCacheManifest.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      if (manifest.version != lazyParsedSectionCacheFormatVersion ||
          manifest.bookId != bookId) {
        return null;
      }
      final validated = await _validatedManifest(bookId, manifest);
      if (validated.records.length != manifest.records.length) {
        return validated;
      }
      _manifestCache[bookId] = _CachedParsedSectionManifest(
        manifest: validated,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
        length: stat.size,
      );
      return validated;
    } catch (error) {
      _manifestCache.remove(bookId);
      _parsedSectionDiagLog('lazy_section_cache_corrupt', {
        'book': bookId,
        'path': file.path,
        'reason': 'manifest_${error.runtimeType}',
      });
      await file.delete();
      return null;
    }
  }

  Future<ParsedSection?> loadSection(
    LazySectionIdentity identity, {
    String parserVersion = lazyParsedSectionParserVersion,
  }) async {
    final manifest = await loadManifest(identity.bookId);
    if (manifest == null) {
      _parsedSectionDiagLog('lazy_section_cache_miss', {
        'book': identity.bookId,
        'spineIndex': identity.spineIndex,
        'href': identity.href,
        'reason': 'no_manifest',
      });
      return null;
    }
    final record = manifest.records
        .where((candidate) => candidate.matches(identity, parserVersion))
        .firstOrNull;
    if (record == null) {
      _parsedSectionDiagLog('lazy_section_cache_miss', {
        'book': identity.bookId,
        'spineIndex': identity.spineIndex,
        'href': identity.href,
        'reason': 'range_not_cached',
      });
      return null;
    }
    final file = await _sectionFile(identity.bookId, record.fileName);
    try {
      final bytes = await file.readAsBytes();
      if (fnv1aHex(bytes) != record.checksum) {
        throw const FormatException('Parsed section checksum mismatch');
      }
      final section = await Isolate.run(() => _deserializeSection(bytes));
      _parsedSectionDiagLog('lazy_section_cache_hit', {
        'book': identity.bookId,
        'spineIndex': identity.spineIndex,
        'href': identity.href,
        'chunks': section.chunks.length,
        'bytes': bytes.length,
      });
      return section;
    } catch (error) {
      _parsedSectionDiagLog('lazy_section_cache_corrupt', {
        'book': identity.bookId,
        'spineIndex': identity.spineIndex,
        'href': identity.href,
        'path': file.path,
        'reason': error.runtimeType,
      });
      await _removeRecord(identity.bookId, record);
      return null;
    }
  }

  Future<void> writeSection(ParsedSection section) {
    final operation = _writeQueue.then((_) => _writeSection(section));
    _writeQueue = operation.catchError((_) {});
    return operation;
  }

  Future<void> _writeSection(ParsedSection section) async {
    final dir = await _bookDir(section.identity.bookId);
    final fileName = 'section_${section.identity.cacheKey}.json.gz';
    final tmpFile = File(p.join(dir.path, '$fileName.tmp'));
    final finalFile = File(p.join(dir.path, fileName));

    _parsedSectionDiagLog('lazy_section_cache_write_begin', {
      'book': section.identity.bookId,
      'spineIndex': section.identity.spineIndex,
      'href': section.identity.href,
      'chunks': section.chunks.length,
      'path': finalFile.path,
    });

    try {
      final bytes = await Isolate.run(() => _serializeSection(section));
      await tmpFile.writeAsBytes(bytes, flush: true);
      final validated = await Isolate.run(
        () => _deserializeSection(tmpFile.readAsBytesSync()),
      );
      if (validated.identity.sourceChecksum !=
          section.identity.sourceChecksum) {
        throw const FormatException('Parsed section validation mismatch');
      }
      await tmpFile.rename(finalFile.path);

      final now = DateTime.now().millisecondsSinceEpoch;
      final record = ParsedSectionCacheRecord(
        spineIndex: section.identity.spineIndex,
        href: section.identity.href,
        fullPath: section.identity.fullPath,
        sourceChecksum: section.identity.sourceChecksum,
        parserVersion: section.parserVersion,
        fileName: fileName,
        chunkCount: section.chunks.length,
        anchorCount: section.anchorMap.length,
        wordCount: section.wordCount,
        textCharCount: section.textCharCount,
        resourceHrefs: section.resourceHrefs,
        checksum: fnv1aHex(bytes),
        fileSizeBytes: bytes.length,
        createdAtMs: now,
        updatedAtMs: now,
        status: 'ready',
      );
      await _upsertRecord(section.identity.bookId, record);
      _parsedSectionDiagLog('lazy_section_cache_write_end', {
        'book': section.identity.bookId,
        'spineIndex': section.identity.spineIndex,
        'href': section.identity.href,
        'chunks': section.chunks.length,
        'bytes': bytes.length,
        'path': finalFile.path,
      });
    } finally {
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
    }
  }

  Future<ParsedSectionCacheManifest> _validatedManifest(
    String bookId,
    ParsedSectionCacheManifest manifest,
  ) async {
    final valid = <ParsedSectionCacheRecord>[];
    for (final record in manifest.records) {
      final file = await _sectionFile(bookId, record.fileName);
      if (await file.exists()) {
        valid.add(record);
      } else {
        _parsedSectionDiagLog('lazy_section_cache_corrupt', {
          'book': bookId,
          'spineIndex': record.spineIndex,
          'href': record.href,
          'reason': 'missing_payload',
        });
      }
    }
    if (valid.length == manifest.records.length) return manifest;
    final normalized = ParsedSectionCacheManifest(
      version: manifest.version,
      bookId: manifest.bookId,
      createdAtMs: manifest.createdAtMs,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      records: valid,
      hydration: manifest.hydration,
    );
    await _saveManifest(normalized);
    return normalized;
  }

  Future<void> _upsertRecord(
    String bookId,
    ParsedSectionCacheRecord record,
  ) async {
    final current = await loadManifest(bookId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = [
      ...?current?.records.where(
        (candidate) =>
            candidate.spineIndex != record.spineIndex ||
            candidate.href != record.href ||
            candidate.sourceChecksum != record.sourceChecksum ||
            candidate.parserVersion != record.parserVersion,
      ),
      record,
    ]..sort((a, b) => a.spineIndex.compareTo(b.spineIndex));
    await _saveManifest(
      ParsedSectionCacheManifest(
        version: lazyParsedSectionCacheFormatVersion,
        bookId: bookId,
        createdAtMs: current?.createdAtMs ?? now,
        updatedAtMs: now,
        records: records,
        hydration: _recordHydrationCompletion(current?.hydration, record, now),
      ),
    );
  }

  Future<void> _removeRecord(
    String bookId,
    ParsedSectionCacheRecord record,
  ) async {
    final manifest = await loadManifest(bookId);
    if (manifest == null) return;
    final records = manifest.records
        .where((candidate) => candidate.fileName != record.fileName)
        .toList();
    final file = await _sectionFile(bookId, record.fileName);
    if (await file.exists()) await file.delete();
    await _saveManifest(
      ParsedSectionCacheManifest(
        version: manifest.version,
        bookId: bookId,
        createdAtMs: manifest.createdAtMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        records: records,
        hydration: manifest.hydration,
      ),
    );
  }

  Future<ParsedSectionHydrationManifest> ensureHydrationManifest({
    required String bookId,
    required String sourceChecksum,
    required String parserVersion,
    required List<int> readableSpineIndexes,
    required List<int> skippedSpineIndexes,
  }) async {
    final current = await loadManifest(bookId);
    final existing = current?.hydration;
    final completed =
        current?.records
            .where((record) => record.parserVersion == parserVersion)
            .map((record) => record.spineIndex)
            .where(readableSpineIndexes.contains)
            .toSet() ??
        <int>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    final hydration =
        existing != null &&
            existing.matches(
              bookId: bookId,
              sourceChecksum: sourceChecksum,
              parserVersion: parserVersion,
            )
        ? existing.copyWith(
            completedSpineIndexes: _sortedInts({
              ...existing.completedSpineIndexes,
              ...completed,
            }),
            pendingSpineIndexes: _sortedInts(
              readableSpineIndexes
                  .where(
                    (index) =>
                        !completed.contains(index) &&
                        !existing.completedSpineIndexes.contains(index),
                  )
                  .toSet(),
            ),
            status: completed.length >= readableSpineIndexes.length
                ? 'complete'
                : 'inProgress',
            updatedAtMs: now,
          )
        : ParsedSectionHydrationManifest(
            bookId: bookId,
            sourceChecksum: sourceChecksum,
            parserVersion: parserVersion,
            totalReadableSpineSections: readableSpineIndexes.length,
            completedSpineIndexes: _sortedInts(completed),
            pendingSpineIndexes: _sortedInts(
              readableSpineIndexes
                  .where((index) => !completed.contains(index))
                  .toSet(),
            ),
            failedSpineIndexes: const [],
            skippedSpineIndexes: _sortedInts(skippedSpineIndexes.toSet()),
            status: completed.length >= readableSpineIndexes.length
                ? 'complete'
                : 'inProgress',
            updatedAtMs: now,
          );

    await _saveManifest(
      ParsedSectionCacheManifest(
        version: lazyParsedSectionCacheFormatVersion,
        bookId: bookId,
        createdAtMs: current?.createdAtMs ?? now,
        updatedAtMs: now,
        records: current?.records ?? const [],
        hydration: hydration,
      ),
    );
    return hydration;
  }

  ParsedSectionHydrationManifest? _recordHydrationCompletion(
    ParsedSectionHydrationManifest? hydration,
    ParsedSectionCacheRecord record,
    int now,
  ) {
    if (hydration == null ||
        hydration.parserVersion != record.parserVersion ||
        !hydration.pendingSpineIndexes.contains(record.spineIndex)) {
      return hydration;
    }
    final completed = _sortedInts({
      ...hydration.completedSpineIndexes,
      record.spineIndex,
    });
    final pending = _sortedInts(
      hydration.pendingSpineIndexes
          .where((index) => index != record.spineIndex)
          .toSet(),
    );
    return hydration.copyWith(
      completedSpineIndexes: completed,
      pendingSpineIndexes: pending,
      status: pending.isEmpty ? 'complete' : 'inProgress',
      updatedAtMs: now,
    );
  }

  Future<void> _saveManifest(ParsedSectionCacheManifest manifest) async {
    final dir = await _bookDir(manifest.bookId);
    final tmp = File(p.join(dir.path, 'manifest.json.tmp'));
    final file = File(p.join(dir.path, 'manifest.json'));
    await tmp.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    await tmp.rename(file.path);
    final stat = await file.stat();
    _manifestCache[manifest.bookId] = _CachedParsedSectionManifest(
      manifest: manifest,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      length: stat.size,
    );
  }

  Future<File> _manifestFile(String bookId) async {
    final dir = await _bookDir(bookId);
    return File(p.join(dir.path, 'manifest.json'));
  }

  Future<File> _sectionFile(String bookId, String fileName) async {
    final dir = await _bookDir(bookId);
    return File(p.join(dir.path, fileName));
  }

  Future<Directory> _bookDir(String bookId) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, _safeKey(bookId)));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Uint8List _serializeSection(ParsedSection section) {
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(section))));
  }

  static ParsedSection _deserializeSection(Uint8List bytes) {
    return ParsedSection.fromJson(
      jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>,
    );
  }

  static String _safeKey(String input) {
    final safe = input.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (safe.length <= 120) return safe;
    return '${safe.substring(0, 96)}_${fnv1aHex(Uint8List.fromList(input.codeUnits))}';
  }
}

List<int> _sortedInts(Set<int> values) {
  return values.toList()..sort();
}
