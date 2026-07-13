import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lazy_parsed_book.dart';
import 'parsed_section_retention_policy.dart';

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
    required this.publicationFingerprint,
    required this.href,
    required this.normalizedHref,
    required this.fullPath,
    required this.sourceChecksum,
    required this.parserVersion,
    required this.cacheSchemaVersion,
    required this.dependencySignature,
    required this.dependencySchemaVersion,
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
    required this.lastAccessedAtMs,
    required this.status,
  });

  final int spineIndex;
  final String publicationFingerprint;
  final String href;
  final String normalizedHref;
  final String fullPath;
  final String sourceChecksum;
  final String parserVersion;
  final int cacheSchemaVersion;
  final String dependencySignature;
  final int dependencySchemaVersion;
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
  final int lastAccessedAtMs;
  final String status;

  bool matches(LazySectionIdentity identity, String parserVersion) {
    return spineIndex == identity.spineIndex &&
        publicationFingerprint == identity.publicationFingerprint &&
        href == identity.href &&
        normalizedHref == identity.normalizedHref &&
        fullPath == identity.fullPath &&
        sourceChecksum == identity.sourceChecksum &&
        this.parserVersion == parserVersion &&
        parserVersion == identity.parserVersion &&
        cacheSchemaVersion == lazyParsedSectionCacheFormatVersion &&
        dependencySignature == identity.dependencySignature &&
        dependencySchemaVersion == identity.dependencySchemaVersion &&
        status == 'ready';
  }

  Map<String, dynamic> toJson() => {
    'spineIndex': spineIndex,
    'publicationFingerprint': publicationFingerprint,
    'href': href,
    'normalizedHref': normalizedHref,
    'fullPath': fullPath,
    'sourceChecksum': sourceChecksum,
    'parserVersion': parserVersion,
    'cacheSchemaVersion': cacheSchemaVersion,
    'dependencySignature': dependencySignature,
    'dependencySchemaVersion': dependencySchemaVersion,
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
    'lastAccessedAtMs': lastAccessedAtMs,
    'status': status,
  };

  factory ParsedSectionCacheRecord.fromJson(Map<String, dynamic> json) {
    return ParsedSectionCacheRecord(
      spineIndex: json['spineIndex'] as int,
      publicationFingerprint: json['publicationFingerprint'] as String,
      href: json['href'] as String,
      normalizedHref: json['normalizedHref'] as String,
      fullPath: json['fullPath'] as String,
      sourceChecksum: json['sourceChecksum'] as String,
      parserVersion: json['parserVersion'] as String,
      cacheSchemaVersion: json['cacheSchemaVersion'] as int,
      dependencySignature: json['dependencySignature'] as String,
      dependencySchemaVersion: json['dependencySchemaVersion'] as int,
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
      lastAccessedAtMs:
          (json['lastAccessedAtMs'] as num?)?.toInt() ??
          (json['updatedAtMs'] as int),
      status: json['status'] as String,
    );
  }

  ParsedSectionCacheRecord copyWith({int? lastAccessedAtMs}) {
    return ParsedSectionCacheRecord(
      spineIndex: spineIndex,
      publicationFingerprint: publicationFingerprint,
      href: href,
      normalizedHref: normalizedHref,
      fullPath: fullPath,
      sourceChecksum: sourceChecksum,
      parserVersion: parserVersion,
      cacheSchemaVersion: cacheSchemaVersion,
      dependencySignature: dependencySignature,
      dependencySchemaVersion: dependencySchemaVersion,
      fileName: fileName,
      chunkCount: chunkCount,
      anchorCount: anchorCount,
      wordCount: wordCount,
      textCharCount: textCharCount,
      resourceHrefs: resourceHrefs,
      checksum: checksum,
      fileSizeBytes: fileSizeBytes,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs,
      lastAccessedAtMs: lastAccessedAtMs ?? this.lastAccessedAtMs,
      status: status,
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
    required this.publicationFingerprint,
    required this.sourceChecksum,
    required this.parserVersion,
    required this.dependencySignature,
    required this.totalReadableSpineSections,
    required this.completedSpineIndexes,
    required this.pendingSpineIndexes,
    required this.failedSpineIndexes,
    required this.skippedSpineIndexes,
    required this.status,
    required this.updatedAtMs,
  });

  final String bookId;
  final String publicationFingerprint;
  final String sourceChecksum;
  final String parserVersion;
  final String dependencySignature;
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
    required String publicationFingerprint,
    required String sourceChecksum,
    required String parserVersion,
    required String dependencySignature,
  }) {
    return this.bookId == bookId &&
        this.publicationFingerprint == publicationFingerprint &&
        this.sourceChecksum == sourceChecksum &&
        this.parserVersion == parserVersion &&
        this.dependencySignature == dependencySignature &&
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
      publicationFingerprint: publicationFingerprint,
      sourceChecksum: sourceChecksum,
      parserVersion: parserVersion,
      dependencySignature: dependencySignature,
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
    'publicationFingerprint': publicationFingerprint,
    'sourceChecksum': sourceChecksum,
    'parserVersion': parserVersion,
    'dependencySignature': dependencySignature,
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
      publicationFingerprint: json['publicationFingerprint'] as String,
      sourceChecksum: json['sourceChecksum'] as String,
      parserVersion: json['parserVersion'] as String,
      dependencySignature: json['dependencySignature'] as String,
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

final class ParsedSectionCacheWriteInvalidated implements Exception {
  const ParsedSectionCacheWriteInvalidated(this.bookId);
  final String bookId;

  @override
  String toString() => 'Parsed-section write invalidated for $bookId';
}

final class ParsedSectionCacheBudgetResult {
  const ParsedSectionCacheBudgetResult({
    required this.usageBytes,
    required this.budgetBytes,
    required this.evictedBytes,
    required this.evictedRecords,
  });

  final int usageBytes;
  final int budgetBytes;
  final int evictedBytes;
  final int evictedRecords;
}

final class _ParsedCacheFileCoordinator {
  Future<void> tail = Future<void>.value();
  final Map<String, int> generations = {};
  final Set<String> deletingBooks = {};
  int temporarySequence = 0;
  int globalGeneration = 0;
  bool resetting = false;

  int generation(String bookId) =>
      globalGeneration * 0x100000000 + (generations[bookId] ?? 0);

  int invalidate(String bookId) {
    final next = (generations[bookId] ?? 0) + 1;
    generations[bookId] = next;
    deletingBooks.add(bookId);
    return next;
  }

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

final class ParsedSectionCacheService {
  ParsedSectionCacheService({
    Directory? rootDirectory,
    ParsedSectionCachePolicy policy = const ParsedSectionCachePolicy(),
    ParsedCacheStoragePressureProvider? storagePressureProvider,
    ParsedSectionRetentionRegistry? retentionRegistry,
    ParsedCacheClock? clock,
    Duration accessUpdateInterval = const Duration(minutes: 5),
  }) : _rootDirectory = rootDirectory,
       _policy = policy,
       _storagePressureProvider =
           storagePressureProvider ?? _defaultStoragePressure,
       _retentionRegistry =
           retentionRegistry ?? ParsedSectionRetentionRegistry.instance,
       _clock = clock ?? DateTime.now,
       _accessUpdateInterval = accessUpdateInterval;

  static const String directoryName = 'parsed_sections';
  static final Map<String, _ParsedCacheFileCoordinator> _coordinators = {};

  final Directory? _rootDirectory;
  final ParsedSectionCachePolicy _policy;
  final ParsedCacheStoragePressureProvider _storagePressureProvider;
  final ParsedSectionRetentionRegistry _retentionRegistry;
  final ParsedCacheClock _clock;
  final Duration _accessUpdateInterval;
  final Map<String, _CachedParsedSectionManifest> _manifestCache = {};

  static ParsedCacheStoragePressure _defaultStoragePressure() =>
      ParsedCacheStoragePressure.normal;

  String get _scopeKey =>
      _rootDirectory?.absolute.path ?? '__default_parsed_section_cache__';

  _ParsedCacheFileCoordinator get _coordinator =>
      _coordinators.putIfAbsent(_scopeKey, _ParsedCacheFileCoordinator.new);

  int generationForBook(String bookId) => _coordinator.generation(bookId);

  bool get speculativeWorkAllowed =>
      _policy.allowsSpeculativeWork(4, _storagePressureProvider());

  bool allowsPriority(int priorityRank) =>
      _policy.allowsSpeculativeWork(priorityRank, _storagePressureProvider());

  void setActiveProtection({
    required Object owner,
    required String bookId,
    required String publicationFingerprint,
    required Iterable<LazySectionIdentity> nearbySections,
  }) {
    _retentionRegistry.setActive(
      owner: owner,
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      nearbySections: nearbySections,
    );
  }

  void clearActiveProtection(Object owner) {
    _retentionRegistry.clearActive(owner);
  }

  void recordMeaningfulReadProtection({
    required String bookId,
    required int readAtMs,
    LazySectionIdentity? lastVisible,
    Iterable<LazySectionIdentity> adjacent = const [],
  }) {
    _retentionRegistry.recordMeaningfulRead(
      bookId: bookId,
      readAtMs: readAtMs,
      lastVisible: lastVisible,
      adjacent: adjacent,
    );
  }

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
    await _coordinator.exclusive(() async {
      final root = await _root();
      if (!await root.exists()) return;
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File ||
            !(entity.path.contains('.tmp.') || entity.path.endsWith('.tmp'))) {
          continue;
        }
        _parsedSectionDiagLog('lazy_section_cache_temp_cleanup', {
          'path': entity.path,
        });
        await entity.delete();
        _manifestCache.clear();
      }
    });
  }

  Future<void> deleteForBook(String bookId) async {
    final coordinator = _coordinator;
    coordinator.invalidate(bookId);
    _retentionRegistry.removeBook(bookId);
    await coordinator.exclusive(() async {
      final dir = await _bookDir(bookId, create: false);
      if (await dir.exists()) {
        _parsedSectionDiagLog('lazy_section_cache_delete_for_book', {
          'book': bookId,
          'path': dir.path,
        });
        await dir.delete(recursive: true);
      }
      _manifestCache.remove(bookId);
      coordinator.deletingBooks.remove(bookId);
    });
  }

  Future<void> clearAll() async {
    final coordinator = _coordinator;
    coordinator.globalGeneration++;
    coordinator.resetting = true;
    final root = await _root();
    await coordinator.exclusive(() async {
      try {
        if (await root.exists()) await root.delete(recursive: true);
        await root.create(recursive: true);
        _manifestCache.clear();
      } finally {
        coordinator.resetting = false;
      }
    });
  }

  Future<void> registerPublication({
    required String bookId,
    required String publicationFingerprint,
  }) async {
    await _coordinator.exclusive(() async {
      final manifest = await _loadManifestUnlocked(bookId);
      if (manifest == null) return;
      final stale = manifest.records
          .where(
            (record) => record.publicationFingerprint != publicationFingerprint,
          )
          .toList(growable: false);
      if (stale.isEmpty) return;
      for (final record in stale) {
        final file = await _sectionFile(bookId, record.fileName, create: false);
        if (await file.exists()) await file.delete();
      }
      await _saveManifestUnlocked(
        ParsedSectionCacheManifest(
          version: manifest.version,
          bookId: manifest.bookId,
          createdAtMs: manifest.createdAtMs,
          updatedAtMs: _nowMs,
          records: manifest.records
              .where(
                (record) =>
                    record.publicationFingerprint == publicationFingerprint,
              )
              .toList(growable: false),
          hydration:
              manifest.hydration?.publicationFingerprint ==
                  publicationFingerprint
              ? manifest.hydration
              : null,
        ),
      );
    });
  }

  Future<ParsedSectionCacheManifest?> loadManifest(String bookId) =>
      _coordinator.exclusive(() => _loadManifestUnlocked(bookId));

  Future<ParsedSectionCacheManifest?> _loadManifestUnlocked(
    String bookId,
  ) async {
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
        final dir = await _bookDir(bookId, create: false);
        if (await dir.exists()) await dir.delete(recursive: true);
        _manifestCache.remove(bookId);
        return null;
      }
      final validated = await _validatedManifestUnlocked(bookId, manifest);
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
    int? expectedGeneration,
  }) async {
    final generation = expectedGeneration ?? generationForBook(identity.bookId);
    if (_coordinator.resetting ||
        _coordinator.deletingBooks.contains(identity.bookId)) {
      return null;
    }
    final recordAndBytes = await _coordinator.exclusive(() async {
      if (generation != generationForBook(identity.bookId) ||
          _coordinator.resetting ||
          _coordinator.deletingBooks.contains(identity.bookId)) {
        return null;
      }
      final manifest = await _loadManifestUnlocked(identity.bookId);
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
        return (record: record, bytes: bytes);
      } catch (error) {
        _parsedSectionDiagLog('lazy_section_cache_corrupt', {
          'book': identity.bookId,
          'spineIndex': identity.spineIndex,
          'href': identity.href,
          'path': file.path,
          'reason': error.runtimeType,
        });
        await _removeRecordUnlocked(identity.bookId, record);
        return null;
      }
    });
    if (recordAndBytes == null ||
        generation != generationForBook(identity.bookId)) {
      return null;
    }
    try {
      final section = await Isolate.run(
        () => _deserializeSection(recordAndBytes.bytes),
      );
      if (section.identity.stableKey != identity.stableKey ||
          section.parserVersion != parserVersion) {
        throw const FormatException('Parsed section identity mismatch');
      }
      await _touchRecordIfDue(identity.bookId, recordAndBytes.record);
      _parsedSectionDiagLog('lazy_section_cache_hit', {
        'book': identity.bookId,
        'spineIndex': identity.spineIndex,
        'href': identity.href,
        'chunks': section.chunks.length,
        'bytes': recordAndBytes.bytes.length,
      });
      return section;
    } catch (error) {
      _parsedSectionDiagLog('lazy_section_cache_corrupt', {
        'book': identity.bookId,
        'spineIndex': identity.spineIndex,
        'href': identity.href,
        'reason': error.runtimeType,
      });
      await _coordinator.exclusive(
        () => _removeRecordUnlocked(identity.bookId, recordAndBytes.record),
      );
      return null;
    }
  }

  Future<void> writeSection(
    ParsedSection section, {
    int? expectedGeneration,
  }) async {
    if (section.parserVersion != section.identity.parserVersion) {
      throw const FormatException('Parsed section parser identity mismatch');
    }
    final generation =
        expectedGeneration ?? generationForBook(section.identity.bookId);
    final bytes = await Isolate.run(() => _serializeSection(section));
    await _coordinator.exclusive(
      () => _writeSectionUnlocked(section, bytes, generation),
    );
    await enforceBudget();
  }

  Future<void> _writeSectionUnlocked(
    ParsedSection section,
    Uint8List bytes,
    int generation,
  ) async {
    final bookId = section.identity.bookId;
    if (generation != generationForBook(bookId) ||
        _coordinator.resetting ||
        _coordinator.deletingBooks.contains(bookId)) {
      throw ParsedSectionCacheWriteInvalidated(bookId);
    }
    final dir = await _bookDir(bookId);
    final fileName = 'section_${section.identity.cacheKey}.json.gz';
    final temporaryId = _coordinator.temporarySequence++;
    final tmpFile = File(p.join(dir.path, '$fileName.tmp.${pid}_$temporaryId'));
    final finalFile = File(p.join(dir.path, fileName));

    _parsedSectionDiagLog('lazy_section_cache_write_begin', {
      'book': section.identity.bookId,
      'spineIndex': section.identity.spineIndex,
      'href': section.identity.href,
      'chunks': section.chunks.length,
      'path': finalFile.path,
    });

    try {
      await tmpFile.writeAsBytes(bytes, flush: true);
      final validated = await Isolate.run(
        () => _deserializeSection(tmpFile.readAsBytesSync()),
      );
      if (validated.identity.stableKey != section.identity.stableKey) {
        throw const FormatException('Parsed section validation mismatch');
      }
      if (generation != generationForBook(bookId) ||
          _coordinator.resetting ||
          _coordinator.deletingBooks.contains(bookId)) {
        throw ParsedSectionCacheWriteInvalidated(bookId);
      }
      await tmpFile.rename(finalFile.path);

      final now = _nowMs;
      final record = ParsedSectionCacheRecord(
        spineIndex: section.identity.spineIndex,
        publicationFingerprint: section.identity.publicationFingerprint,
        href: section.identity.href,
        normalizedHref: section.identity.normalizedHref,
        fullPath: section.identity.fullPath,
        sourceChecksum: section.identity.sourceChecksum,
        parserVersion: section.parserVersion,
        cacheSchemaVersion: lazyParsedSectionCacheFormatVersion,
        dependencySignature: section.identity.dependencySignature,
        dependencySchemaVersion: section.identity.dependencySchemaVersion,
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
        lastAccessedAtMs: now,
        status: 'ready',
      );
      await _upsertRecordUnlocked(section.identity.bookId, record);
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

  Future<ParsedSectionCacheManifest> _validatedManifestUnlocked(
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
    await _saveManifestUnlocked(normalized);
    return normalized;
  }

  Future<void> _upsertRecordUnlocked(
    String bookId,
    ParsedSectionCacheRecord record,
  ) async {
    final current = await _loadManifestUnlocked(bookId);
    final now = _nowMs;
    final records = [
      ...?current?.records.where(
        (candidate) =>
            candidate.spineIndex != record.spineIndex ||
            candidate.publicationFingerprint != record.publicationFingerprint ||
            candidate.normalizedHref != record.normalizedHref ||
            candidate.sourceChecksum != record.sourceChecksum ||
            candidate.parserVersion != record.parserVersion ||
            candidate.dependencySignature != record.dependencySignature,
      ),
      record,
    ]..sort((a, b) => a.spineIndex.compareTo(b.spineIndex));
    await _saveManifestUnlocked(
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

  Future<void> _removeRecordUnlocked(
    String bookId,
    ParsedSectionCacheRecord record,
  ) async {
    final manifest = await _loadManifestUnlocked(bookId);
    if (manifest == null) return;
    final current = manifest.records
        .where((candidate) => candidate.fileName == record.fileName)
        .firstOrNull;
    if (current == null || current.checksum != record.checksum) return;
    final records = manifest.records
        .where((candidate) => candidate.fileName != record.fileName)
        .toList();
    final file = await _sectionFile(bookId, record.fileName);
    if (await file.exists()) await file.delete();
    await _saveManifestUnlocked(
      ParsedSectionCacheManifest(
        version: manifest.version,
        bookId: bookId,
        createdAtMs: manifest.createdAtMs,
        updatedAtMs: _nowMs,
        records: records,
        hydration: manifest.hydration,
      ),
    );
  }

  Future<ParsedSectionHydrationManifest> ensureHydrationManifest({
    required String bookId,
    required String publicationFingerprint,
    required String sourceChecksum,
    required String parserVersion,
    required String dependencySignature,
    required List<int> readableSpineIndexes,
    required List<int> skippedSpineIndexes,
  }) => _coordinator.exclusive(() async {
    final current = await _loadManifestUnlocked(bookId);
    final existing = current?.hydration;
    final completed =
        current?.records
            .where((record) => record.parserVersion == parserVersion)
            .map((record) => record.spineIndex)
            .where(readableSpineIndexes.contains)
            .toSet() ??
        <int>{};
    final now = _nowMs;
    final hydration =
        existing != null &&
            existing.matches(
              bookId: bookId,
              publicationFingerprint: publicationFingerprint,
              sourceChecksum: sourceChecksum,
              parserVersion: parserVersion,
              dependencySignature: dependencySignature,
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
            publicationFingerprint: publicationFingerprint,
            sourceChecksum: sourceChecksum,
            parserVersion: parserVersion,
            dependencySignature: dependencySignature,
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

    await _saveManifestUnlocked(
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
  });

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

  Future<void> _touchRecordIfDue(
    String bookId,
    ParsedSectionCacheRecord loadedRecord,
  ) async {
    final now = _nowMs;
    if (now - loadedRecord.lastAccessedAtMs <
        _accessUpdateInterval.inMilliseconds) {
      return;
    }
    await _coordinator.exclusive(() async {
      final manifest = await _loadManifestUnlocked(bookId);
      if (manifest == null) return;
      final index = manifest.records.indexWhere(
        (record) => record.fileName == loadedRecord.fileName,
      );
      if (index < 0 ||
          now - manifest.records[index].lastAccessedAtMs <
              _accessUpdateInterval.inMilliseconds) {
        return;
      }
      final records = List<ParsedSectionCacheRecord>.from(manifest.records);
      records[index] = records[index].copyWith(lastAccessedAtMs: now);
      await _saveManifestUnlocked(
        ParsedSectionCacheManifest(
          version: manifest.version,
          bookId: manifest.bookId,
          createdAtMs: manifest.createdAtMs,
          updatedAtMs: now,
          records: records,
          hydration: manifest.hydration,
        ),
      );
    });
  }

  Future<ParsedSectionCacheBudgetResult> enforceBudget() {
    return _coordinator.exclusive(_enforceBudgetUnlocked);
  }

  Future<ParsedSectionCacheBudgetResult> _enforceBudgetUnlocked() async {
    final pressure = _storagePressureProvider();
    final budget = _policy.effectiveBudget(pressure);
    final protection = _retentionRegistry.snapshot(pressure: pressure);
    final root = await _root();
    final candidates = <_ParsedDiskCandidate>[];
    final manifests = <String, ParsedSectionCacheManifest>{};
    var usage = 0;

    if (await root.exists()) {
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final manifestFile = File(p.join(entity.path, 'manifest.json'));
        if (!await manifestFile.exists()) {
          await _deleteCacheDerivativeDirectory(entity);
          continue;
        }
        ParsedSectionCacheManifest manifest;
        try {
          manifest = ParsedSectionCacheManifest.fromJson(
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>,
          );
          if (manifest.version != lazyParsedSectionCacheFormatVersion) {
            throw const FormatException('Unsupported manifest version');
          }
        } catch (_) {
          await _deleteCacheDerivativeDirectory(entity);
          continue;
        }
        final referenced = manifest.records
            .map((record) => record.fileName)
            .toSet();
        await for (final child in entity.list()) {
          if (child is! File) continue;
          final name = p.basename(child.path);
          if (name == 'manifest.json') continue;
          if (name.contains('.tmp.') || !referenced.contains(name)) {
            await child.delete();
          }
        }
        final validRecords = <ParsedSectionCacheRecord>[];
        for (final record in manifest.records) {
          final payload = File(p.join(entity.path, record.fileName));
          final stat = await payload.stat();
          if (stat.type != FileSystemEntityType.file) continue;
          if (stat.size != record.fileSizeBytes) {
            await payload.delete();
            continue;
          }
          validRecords.add(record);
          usage += stat.size;
          final identity = _identityForRecord(manifest.bookId, record);
          candidates.add(
            _ParsedDiskCandidate(
              bookId: manifest.bookId,
              record: record,
              file: payload,
              actualBytes: stat.size,
              protection: protection.protectionFor(identity),
            ),
          );
        }
        if (validRecords.length != manifest.records.length) {
          manifest = ParsedSectionCacheManifest(
            version: manifest.version,
            bookId: manifest.bookId,
            createdAtMs: manifest.createdAtMs,
            updatedAtMs: _nowMs,
            records: validRecords,
            hydration: manifest.hydration,
          );
          await _saveManifestUnlocked(manifest);
        }
        manifests[manifest.bookId] = manifest;
      }
    }

    candidates.sort((a, b) {
      final tier = a.protection.index.compareTo(b.protection.index);
      if (tier != 0) return tier;
      return a.record.lastAccessedAtMs.compareTo(b.record.lastAccessedAtMs);
    });
    final removedByBook = <String, Set<String>>{};
    var evictedBytes = 0;
    var evictedRecords = 0;
    for (final candidate in candidates) {
      if (usage <= budget) break;
      if (candidate.protection == ParsedSectionProtection.activeNearby) {
        continue;
      }
      if (await candidate.file.exists()) await candidate.file.delete();
      usage -= candidate.actualBytes;
      evictedBytes += candidate.actualBytes;
      evictedRecords++;
      removedByBook
          .putIfAbsent(candidate.bookId, () => <String>{})
          .add(candidate.record.fileName);
    }

    for (final entry in removedByBook.entries) {
      final manifest = manifests[entry.key];
      if (manifest == null) continue;
      await _saveManifestUnlocked(
        ParsedSectionCacheManifest(
          version: manifest.version,
          bookId: manifest.bookId,
          createdAtMs: manifest.createdAtMs,
          updatedAtMs: _nowMs,
          records: manifest.records
              .where((record) => !entry.value.contains(record.fileName))
              .toList(growable: false),
          hydration: manifest.hydration,
        ),
      );
    }
    return ParsedSectionCacheBudgetResult(
      usageBytes: usage,
      budgetBytes: budget,
      evictedBytes: evictedBytes,
      evictedRecords: evictedRecords,
    );
  }

  Future<void> _deleteCacheDerivativeDirectory(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
    _manifestCache.clear();
  }

  LazySectionIdentity _identityForRecord(
    String bookId,
    ParsedSectionCacheRecord record,
  ) {
    return LazySectionIdentity(
      bookId: bookId,
      publicationFingerprint: record.publicationFingerprint,
      spineIndex: record.spineIndex,
      href: record.href,
      normalizedHref: record.normalizedHref,
      fullPath: record.fullPath,
      sourceChecksum: record.sourceChecksum,
      parserVersion: record.parserVersion,
      dependencySignature: record.dependencySignature,
      dependencySchemaVersion: record.dependencySchemaVersion,
    );
  }

  Future<void> _saveManifestUnlocked(
    ParsedSectionCacheManifest manifest,
  ) async {
    final dir = await _bookDir(manifest.bookId);
    final temporaryId = _coordinator.temporarySequence++;
    final tmp = File(p.join(dir.path, 'manifest.json.tmp.${pid}_$temporaryId'));
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
    final dir = await _bookDir(bookId, create: false);
    return File(p.join(dir.path, 'manifest.json'));
  }

  Future<File> _sectionFile(
    String bookId,
    String fileName, {
    bool create = true,
  }) async {
    final dir = await _bookDir(bookId, create: create);
    return File(p.join(dir.path, fileName));
  }

  Future<Directory> _bookDir(String bookId, {bool create = true}) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, _safeKey(bookId)));
    if (create && !await dir.exists()) {
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

  int get _nowMs => _clock().millisecondsSinceEpoch;
}

final class _ParsedDiskCandidate {
  const _ParsedDiskCandidate({
    required this.bookId,
    required this.record,
    required this.file,
    required this.actualBytes,
    required this.protection,
  });

  final String bookId;
  final ParsedSectionCacheRecord record;
  final File file;
  final int actualBytes;
  final ParsedSectionProtection protection;
}

List<int> _sortedInts(Set<int> values) {
  return values.toList()..sort();
}
