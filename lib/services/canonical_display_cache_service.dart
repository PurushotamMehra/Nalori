import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/canonical_display_cache_invalidation.dart';
import '../models/canonical_display_segment.dart';
import '../models/canonical_pagination.dart';
import '../models/reader_checkpoint.dart';
import 'canonical_display_segment_admission.dart';
import 'progressive_display_state.dart';

const int canonicalDisplayCachePhysicalFormatVersion = 4;
const String canonicalDisplayCacheNamespace = 'canonical_display_v4';
const String canonicalDisplayCacheManifestRevision =
    'canonical_display_manifest_v4';
const String canonicalDisplayCacheContainerRevision =
    'canonical_display_container_v4';

/// Release limits derived from the P04 window/continuation bounds and the
/// P06-002/P06-003 observed maxima. See CHANGE-20260913-037.
@immutable
final class CanonicalDisplayCacheBudgets {
  const CanonicalDisplayCacheBudgets({
    this.maxCardsPerRecord = 12,
    this.maxSourceSlicesPerRecord = 96,
    this.maxBlockLayoutsPerRecord = 192,
    this.maxCompressedBytesPerRecord = 512 * 1024,
    this.maxDecodedBytesPerRecord = 1024 * 1024,
    this.maxDecompressionRatio = 64,
    this.maxManifestRecords = 48,
    this.maxManifestBytes = 128 * 1024,
    this.maxMemoryRecords = 12,
    this.maxMemoryBytes = 12 * 1024 * 1024,
    this.maxDiskRecords = 48,
    this.maxDiskBytes = 24 * 1024 * 1024,
    this.maxContinuationChainDepth = 25,
    this.maxRestartDepth = 2,
    this.maxPinnedRecords = 3,
    this.maxValidationCards = 12,
    this.maxValidationSourceSlices = 96,
    this.maxTemporaryBytes = (512 * 1024) + (128 * 1024) + 256,
  }) : assert(maxCardsPerRecord > 0),
       assert(maxSourceSlicesPerRecord > 0),
       assert(maxBlockLayoutsPerRecord > 0),
       assert(maxCompressedBytesPerRecord > 0),
       assert(maxDecodedBytesPerRecord > 0),
       assert(maxDecompressionRatio > 0),
       assert(maxManifestRecords > 0),
       assert(maxManifestBytes > 0),
       assert(maxMemoryRecords > 0),
       assert(maxMemoryBytes > 0),
       assert(maxDiskRecords > 0),
       assert(maxDiskBytes > 0),
       assert(maxContinuationChainDepth >= 0),
       assert(maxRestartDepth >= 0),
       assert(maxPinnedRecords > 0),
       assert(maxValidationCards > 0),
       assert(maxValidationSourceSlices > 0),
       assert(maxTemporaryBytes > 0);

  final int maxCardsPerRecord;
  final int maxSourceSlicesPerRecord;
  final int maxBlockLayoutsPerRecord;
  final int maxCompressedBytesPerRecord;
  final int maxDecodedBytesPerRecord;
  final int maxDecompressionRatio;
  final int maxManifestRecords;
  final int maxManifestBytes;
  final int maxMemoryRecords;
  final int maxMemoryBytes;
  final int maxDiskRecords;
  final int maxDiskBytes;
  final int maxContinuationChainDepth;
  final int maxRestartDepth;
  final int maxPinnedRecords;
  final int maxValidationCards;
  final int maxValidationSourceSlices;
  final int maxTemporaryBytes;

  CanonicalDisplaySegmentCodecLimits get codecLimits =>
      CanonicalDisplaySegmentCodecLimits(
        maxEncodedBytes: maxDecodedBytesPerRecord,
        maxDecodedBytes: maxDecodedBytesPerRecord,
        maxFieldBytes: maxDecodedBytesPerRecord,
        maxCards: maxCardsPerRecord,
        maxSourceSlices: maxSourceSlicesPerRecord,
        maxBlockLayouts: maxBlockLayoutsPerRecord,
        maxContinuationBytes: 64 * 1024,
        maxManifestSegments: maxManifestRecords,
        maxContinuationChainOrdinal: maxContinuationChainDepth,
      );

  CanonicalDisplayCacheBudgets copyWith({
    int? maxCardsPerRecord,
    int? maxSourceSlicesPerRecord,
    int? maxBlockLayoutsPerRecord,
    int? maxCompressedBytesPerRecord,
    int? maxDecodedBytesPerRecord,
    int? maxDecompressionRatio,
    int? maxManifestRecords,
    int? maxManifestBytes,
    int? maxMemoryRecords,
    int? maxMemoryBytes,
    int? maxDiskRecords,
    int? maxDiskBytes,
    int? maxContinuationChainDepth,
    int? maxRestartDepth,
    int? maxPinnedRecords,
    int? maxValidationCards,
    int? maxValidationSourceSlices,
    int? maxTemporaryBytes,
  }) => CanonicalDisplayCacheBudgets(
    maxCardsPerRecord: maxCardsPerRecord ?? this.maxCardsPerRecord,
    maxSourceSlicesPerRecord:
        maxSourceSlicesPerRecord ?? this.maxSourceSlicesPerRecord,
    maxBlockLayoutsPerRecord:
        maxBlockLayoutsPerRecord ?? this.maxBlockLayoutsPerRecord,
    maxCompressedBytesPerRecord:
        maxCompressedBytesPerRecord ?? this.maxCompressedBytesPerRecord,
    maxDecodedBytesPerRecord:
        maxDecodedBytesPerRecord ?? this.maxDecodedBytesPerRecord,
    maxDecompressionRatio: maxDecompressionRatio ?? this.maxDecompressionRatio,
    maxManifestRecords: maxManifestRecords ?? this.maxManifestRecords,
    maxManifestBytes: maxManifestBytes ?? this.maxManifestBytes,
    maxMemoryRecords: maxMemoryRecords ?? this.maxMemoryRecords,
    maxMemoryBytes: maxMemoryBytes ?? this.maxMemoryBytes,
    maxDiskRecords: maxDiskRecords ?? this.maxDiskRecords,
    maxDiskBytes: maxDiskBytes ?? this.maxDiskBytes,
    maxContinuationChainDepth:
        maxContinuationChainDepth ?? this.maxContinuationChainDepth,
    maxRestartDepth: maxRestartDepth ?? this.maxRestartDepth,
    maxPinnedRecords: maxPinnedRecords ?? this.maxPinnedRecords,
    maxValidationCards: maxValidationCards ?? this.maxValidationCards,
    maxValidationSourceSlices:
        maxValidationSourceSlices ?? this.maxValidationSourceSlices,
    maxTemporaryBytes: maxTemporaryBytes ?? this.maxTemporaryBytes,
  );
}

enum CanonicalDisplayCacheWriteOutcome {
  stored,
  rejectedAuthorization,
  rejectedAdmission,
  rejectedBudget,
  pressurePinned,
  stale,
  cancelled,
  ioFailure,
}

enum CanonicalDisplayCacheReadSource { memory, disk, absent, rejected }

enum CanonicalDisplayCacheWriteBoundary {
  beforePayloadTemporaryWrite,
  afterPayloadTemporaryFlush,
  beforePayloadRename,
  afterPayloadRename,
  beforeManifestTemporaryWrite,
  afterManifestTemporaryFlush,
  beforeManifestRename,
  afterManifestRename,
  beforeMemoryCommit,
}

typedef CanonicalDisplayCacheWriteInterceptor =
    FutureOr<void> Function(CanonicalDisplayCacheWriteBoundary boundary);

@immutable
final class CanonicalDisplayCacheWriteResult {
  const CanonicalDisplayCacheWriteResult({
    required this.outcome,
    required this.recordCount,
    required this.diskBytes,
    required this.memoryRecordCount,
    required this.memoryBytes,
    required this.evictedKeyDigests,
    this.diagnostic,
  });

  final CanonicalDisplayCacheWriteOutcome outcome;
  final int recordCount;
  final int diskBytes;
  final int memoryRecordCount;
  final int memoryBytes;
  final List<String> evictedKeyDigests;
  final String? diagnostic;

  bool get stored => outcome == CanonicalDisplayCacheWriteOutcome.stored;
}

@immutable
final class CanonicalDisplayCacheReadResult {
  const CanonicalDisplayCacheReadResult({
    required this.source,
    required this.admission,
    this.bytesRead = 0,
    this.diagnostic,
  });

  final CanonicalDisplayCacheReadSource source;
  final CanonicalDisplaySegmentAdmissionResult admission;
  final int bytesRead;
  final String? diagnostic;
}

@immutable
final class CanonicalDisplayCachePressureResult {
  const CanonicalDisplayCachePressureResult({
    required this.withinBudget,
    required this.pinnedPressure,
    required this.recordCount,
    required this.bytes,
    required this.evictedKeyDigests,
  });

  final bool withinBudget;
  final bool pinnedPressure;
  final int recordCount;
  final int bytes;
  final List<String> evictedKeyDigests;
}

@immutable
final class CanonicalDisplayCacheRecordMeasurement {
  const CanonicalDisplayCacheRecordMeasurement({
    required this.cards,
    required this.sourceSlices,
    required this.blockLayouts,
    required this.decodedBytes,
    required this.compressedBytes,
    required this.containerBytes,
    required this.decompressionRatioCeiling,
    required this.continuationChainDepth,
  });

  final int cards;
  final int sourceSlices;
  final int blockLayouts;
  final int decodedBytes;
  final int compressedBytes;
  final int containerBytes;
  final int decompressionRatioCeiling;
  final int continuationChainDepth;
}

final class _CanonicalCacheCoordinator {
  Future<void> _tail = Future<void>.value();

  Future<T> exclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _tail = _tail.catchError((_) {});
    return completer.future;
  }
}

final class _MemoryEntry {
  const _MemoryEntry(this.record, this.bytes);
  final CanonicalDisplaySegmentRecord record;
  final int bytes;
}

final class _ManifestEntry {
  const _ManifestEntry({
    required this.keyDigest,
    required this.bookScopeDigest,
    required this.fileName,
    required this.recordDigest,
    required this.containerDigest,
    required this.encodedBytes,
    required this.decodedBytes,
  });

  factory _ManifestEntry.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const <String>{
      'bookScopeDigest',
      'containerDigest',
      'decodedBytes',
      'encodedBytes',
      'fileName',
      'keyDigest',
      'recordDigest',
    });
    return _ManifestEntry(
      keyDigest: _requiredDigest(json['keyDigest'], 'keyDigest'),
      bookScopeDigest: _requiredDigest(
        json['bookScopeDigest'],
        'bookScopeDigest',
      ),
      fileName: _requiredString(json['fileName'], 'fileName'),
      recordDigest: _requiredDigest(json['recordDigest'], 'recordDigest'),
      containerDigest: _requiredDigest(
        json['containerDigest'],
        'containerDigest',
      ),
      encodedBytes: _requiredNonnegativeInt(
        json['encodedBytes'],
        'encodedBytes',
      ),
      decodedBytes: _requiredNonnegativeInt(
        json['decodedBytes'],
        'decodedBytes',
      ),
    );
  }

  final String keyDigest;
  final String bookScopeDigest;
  final String fileName;
  final String recordDigest;
  final String containerDigest;
  final int encodedBytes;
  final int decodedBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'bookScopeDigest': bookScopeDigest,
    'containerDigest': containerDigest,
    'decodedBytes': decodedBytes,
    'encodedBytes': encodedBytes,
    'fileName': fileName,
    'keyDigest': keyDigest,
    'recordDigest': recordDigest,
  };
}

final class _Manifest {
  _Manifest(Iterable<_ManifestEntry> entries)
    : entries = List<_ManifestEntry>.unmodifiable(
        entries.toList(growable: false)
          ..sort((left, right) => left.keyDigest.compareTo(right.keyDigest)),
      );

  final List<_ManifestEntry> entries;

  int get totalBytes => entries.fold<int>(
    0,
    (total, entry) => _checkedAdd(total, entry.encodedBytes),
  );

  Uint8List encode() {
    final body = <String, Object?>{
      'containerRevision': canonicalDisplayCacheContainerRevision,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'formatVersion': canonicalDisplayCachePhysicalFormatVersion,
      'namespace': canonicalDisplayCacheNamespace,
      'recordCount': entries.length,
      'revision': canonicalDisplayCacheManifestRevision,
      'totalBytes': totalBytes,
    };
    final digest = readerSha256(utf8.encode(canonicalJsonEncode(body)));
    return Uint8List.fromList(
      utf8.encode(
        canonicalJsonEncode(<String, Object?>{
          ...body,
          'manifestDigest': digest,
        }),
      ),
    );
  }

  static _Manifest decode(
    Uint8List bytes,
    CanonicalDisplayCacheBudgets limits,
  ) {
    if (bytes.isEmpty || bytes.length > limits.maxManifestBytes) {
      throw const FormatException('Canonical manifest length is invalid.');
    }
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Canonical manifest must be an object.');
    }
    final json = Map<String, Object?>.from(decoded);
    _expectKeys(json, const <String>{
      'entries',
      'containerRevision',
      'formatVersion',
      'manifestDigest',
      'namespace',
      'recordCount',
      'revision',
      'totalBytes',
    });
    if (json['formatVersion'] != canonicalDisplayCachePhysicalFormatVersion ||
        json['namespace'] != canonicalDisplayCacheNamespace ||
        json['revision'] != canonicalDisplayCacheManifestRevision ||
        json['containerRevision'] != canonicalDisplayCacheContainerRevision) {
      throw const FormatException('Unsupported canonical manifest revision.');
    }
    final rawEntries = json['entries'];
    if (rawEntries is! List || rawEntries.length > limits.maxManifestRecords) {
      throw const FormatException('Canonical manifest count is excessive.');
    }
    final entries = <_ManifestEntry>[];
    final seen = <String>{};
    var total = 0;
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Canonical manifest entry is invalid.');
      }
      final entry = _ManifestEntry.fromJson(Map<String, Object?>.from(raw));
      if (!seen.add(entry.keyDigest) || !_safePayloadName(entry)) {
        throw const FormatException('Canonical manifest entry collides.');
      }
      total = _checkedAdd(total, entry.encodedBytes, limits.maxDiskBytes);
      entries.add(entry);
    }
    if (json['recordCount'] != entries.length || json['totalBytes'] != total) {
      throw const FormatException('Canonical manifest totals contradict.');
    }
    final digest = json.remove('manifestDigest');
    if (digest is! String ||
        digest != readerSha256(utf8.encode(canonicalJsonEncode(json)))) {
      throw const FormatException('Canonical manifest checksum is invalid.');
    }
    return _Manifest(entries);
  }
}

/// Production v4 canonical display-cache boundary. It owns derivative bytes
/// only. Parsed source, checkpoints and user data are neither accepted nor
/// addressable by this service.
final class CanonicalDisplayCacheService {
  CanonicalDisplayCacheService({
    required Directory rootDirectory,
    this.budgets = const CanonicalDisplayCacheBudgets(),
    this.writeInterceptor,
  }) : _storageRoot = Directory(
         p.join(rootDirectory.absolute.path, canonicalDisplayCacheNamespace),
       );

  static const int _containerHeaderBytes = 96;
  static const List<int> _magic = <int>[78, 76, 67, 83, 69, 71, 52, 10];
  static final Map<String, _CanonicalCacheCoordinator> _coordinators =
      <String, _CanonicalCacheCoordinator>{};
  static var _temporaryOrdinal = 0;

  final Directory _storageRoot;
  final CanonicalDisplayCacheBudgets budgets;
  final CanonicalDisplayCacheWriteInterceptor? writeInterceptor;
  final Map<String, _MemoryEntry> _memory = <String, _MemoryEntry>{};
  final Map<String, Future<CanonicalDisplayCacheWriteResult>> _queuedWrites =
      <String, Future<CanonicalDisplayCacheWriteResult>>{};
  Future<void> _writeTail = Future<void>.value();
  var _writeQueueEpoch = 0;
  Set<String> _pins = const <String>{};
  var _memoryBytes = 0;
  var _initialized = false;

  Directory get storageRoot => _storageRoot;
  int get memoryRecordCount => _memory.length;
  int get memoryBytes => _memoryBytes;
  Iterable<CanonicalDisplaySegmentRecord> get memoryRecords =>
      _memory.values.map((entry) => entry.record);
  int get queuedWriteCount => _queuedWrites.length;
  Set<String> get pinnedKeyDigests => Set<String>.unmodifiable(_pins);

  void cancelQueuedWrites() {
    _writeQueueEpoch++;
  }

  _CanonicalCacheCoordinator get _coordinator => _coordinators.putIfAbsent(
    p.normalize(_storageRoot.absolute.path),
    _CanonicalCacheCoordinator.new,
  );

  static Future<CanonicalDisplayCacheService> createDefault({
    CanonicalDisplayCacheBudgets budgets = const CanonicalDisplayCacheBudgets(),
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    return CanonicalDisplayCacheService(
      rootDirectory: Directory(p.join(documents.path, 'book_cache')),
      budgets: budgets,
    );
  }

  Future<void> ensureInitialized() =>
      _coordinator.exclusive(_ensureInitializedUnlocked);

  Future<void> _ensureInitializedUnlocked() async {
    if (_initialized) return;
    await _rejectLinksAndCreate(_storageRoot);
    await _recoverTemporaryAndOrphanFiles();
    _initialized = true;
  }

  Future<CanonicalDisplayCachePressureResult> applyRetentionAuthorization(
    CanonicalDisplayCacheRetentionAuthorization authorization,
  ) async {
    if (authorization.pinnedKeyDigests.length > budgets.maxPinnedRecords ||
        authorization.pinnedKeyDigests.any(
          (digest) => !_digestPattern.hasMatch(digest),
        )) {
      return CanonicalDisplayCachePressureResult(
        withinBudget: false,
        pinnedPressure: true,
        recordCount: _memory.length,
        bytes: _memoryBytes,
        evictedKeyDigests: const <String>[],
      );
    }
    _pins = Set<String>.unmodifiable(authorization.pinnedKeyDigests);
    final memory = _enforceMemoryBudget();
    final disk = await _coordinator.exclusive(() async {
      await _ensureInitializedUnlocked();
      final manifest = await _loadManifestOrEmpty();
      return _evictManifestToBudget(manifest, _pins);
    });
    return CanonicalDisplayCachePressureResult(
      withinBudget: memory.withinBudget && disk.withinBudget,
      pinnedPressure: memory.pinnedPressure || disk.pinnedPressure,
      recordCount: memory.recordCount,
      bytes: memory.bytes,
      evictedKeyDigests: <String>[
        ...memory.evictedKeyDigests,
        ...disk.evictedKeyDigests,
      ],
    );
  }

  Future<CanonicalDisplayCacheReadResult> readAndAdmit({
    required String bookScopeDigest,
    required String keyDigest,
    required CanonicalDisplaySegmentAdmissionContext admissionContext,
    String? claimedGeneration,
    int restartDepth = 0,
  }) async {
    if (restartDepth < 0 || restartDepth > budgets.maxRestartDepth) {
      return CanonicalDisplayCacheReadResult(
        source: CanonicalDisplayCacheReadSource.rejected,
        admission: CanonicalDisplaySegmentAdmissionResult.rejected(
          CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch,
          'Canonical cache restart depth exceeded.',
        ),
        diagnostic: 'restart_depth_budget',
      );
    }
    if (!_digestPattern.hasMatch(bookScopeDigest) ||
        !_digestPattern.hasMatch(keyDigest)) {
      return CanonicalDisplayCacheReadResult(
        source: CanonicalDisplayCacheReadSource.rejected,
        admission: CanonicalDisplaySegmentAdmission.absent(),
        diagnostic: 'invalid_scope_or_key',
      );
    }
    final resident = _memory[keyDigest];
    if (resident != null &&
        resident.record.bookStorageScopeDigest == bookScopeDigest) {
      final admission = CanonicalDisplaySegmentAdmission.admitMemoryRecord(
        record: resident.record,
        limits: budgets.codecLimits,
        context: admissionContext,
        claimedGeneration: claimedGeneration,
      );
      return CanonicalDisplayCacheReadResult(
        source: admission.isExact
            ? CanonicalDisplayCacheReadSource.memory
            : CanonicalDisplayCacheReadSource.rejected,
        admission: admission,
        bytesRead: resident.bytes,
      );
    }
    return _coordinator.exclusive(() async {
      try {
        await _ensureInitializedUnlocked();
        final manifest = await _loadManifestOrEmpty();
        final entry = manifest.entries
            .where(
              (candidate) =>
                  candidate.keyDigest == keyDigest &&
                  candidate.bookScopeDigest == bookScopeDigest,
            )
            .firstOrNull;
        if (entry == null) {
          return CanonicalDisplayCacheReadResult(
            source: CanonicalDisplayCacheReadSource.absent,
            admission: CanonicalDisplaySegmentAdmission.absent(),
          );
        }
        final file = _payloadFile(entry);
        final logical = await _readContainer(file, entry);
        final admission = CanonicalDisplaySegmentAdmission.admitDiskBytes(
          bytes: logical,
          limits: budgets.codecLimits,
          context: admissionContext,
          claimedGeneration: claimedGeneration,
        );
        if (admission.isExact && admission.candidate != null) {
          _retainMemory(admission.candidate!);
        }
        return CanonicalDisplayCacheReadResult(
          source: admission.isExact
              ? CanonicalDisplayCacheReadSource.disk
              : CanonicalDisplayCacheReadSource.rejected,
          admission: admission,
          bytesRead: entry.encodedBytes,
        );
      } on Object catch (error) {
        return CanonicalDisplayCacheReadResult(
          source: CanonicalDisplayCacheReadSource.rejected,
          admission: CanonicalDisplaySegmentAdmissionResult.rejected(
            CanonicalDisplaySegmentValidationOutcome
                .rejectedCorruptChecksumOrEncoding,
            '$error',
          ),
          diagnostic: 'physical_read_rejected',
        );
      }
    });
  }

  Future<CanonicalDisplayCacheWriteResult> writeAuthorized({
    required CanonicalDisplaySegmentRecord record,
    required CanonicalDisplayCacheWriteAuthorization authorization,
    required CanonicalDisplaySegmentAdmissionContext admissionContext,
    bool Function()? isCancelled,
    bool Function()? isCurrent,
    int restartDepth = 0,
  }) async {
    final cancelled = isCancelled ?? () => false;
    final current = isCurrent ?? () => true;
    if (authorization.keyDigest != record.keyDigest ||
        authorization.recordDigest != record.checksumDigest ||
        authorization.sourceSnapshotDigest !=
            record.sourceSnapshotLink.snapshotDigest) {
      return _writeResult(
        CanonicalDisplayCacheWriteOutcome.rejectedAuthorization,
        diagnostic: 'publication_authorization_mismatch',
      );
    }
    if (restartDepth < 0 || restartDepth > budgets.maxRestartDepth) {
      return _writeResult(
        CanonicalDisplayCacheWriteOutcome.rejectedBudget,
        diagnostic: 'restart_depth_budget',
      );
    }
    if (record.declaredCardCount > budgets.maxCardsPerRecord ||
        record.declaredCardCount > budgets.maxValidationCards ||
        record.declaredSourceSliceCount > budgets.maxSourceSlicesPerRecord ||
        record.declaredSourceSliceCount > budgets.maxValidationSourceSlices ||
        record.declaredBlockLayoutCount > budgets.maxBlockLayoutsPerRecord ||
        record.declaredEncodedByteCount > budgets.maxDecodedBytesPerRecord ||
        record.declaredDecodedByteCount > budgets.maxDecodedBytesPerRecord) {
      return _writeResult(
        CanonicalDisplayCacheWriteOutcome.rejectedBudget,
        diagnostic: 'declared_record_budget',
      );
    }
    Uint8List logical;
    Uint8List container;
    CanonicalDisplaySegmentAdmissionResult strict;
    try {
      final maximumCompressedBytes = budgets.maxCompressedBytesPerRecord;
      final prepared = await _prepareCanonicalCacheBytesOffIsolate(
        record,
        maximumCompressedBytes,
      );
      logical = prepared.logical;
      container = prepared.container;
      if (logical.length > budgets.maxDecodedBytesPerRecord ||
          record.declaredCardCount > budgets.maxValidationCards ||
          record.declaredSourceSliceCount > budgets.maxValidationSourceSlices) {
        return _writeResult(
          CanonicalDisplayCacheWriteOutcome.rejectedBudget,
          diagnostic: 'record_validation_budget',
        );
      }
      strict = CanonicalDisplaySegmentAdmission.admitDiskBytes(
        bytes: logical,
        limits: budgets.codecLimits,
        context: admissionContext,
      );
    } on Object catch (error) {
      return _writeResult(
        CanonicalDisplayCacheWriteOutcome.rejectedBudget,
        diagnostic: '$error',
      );
    }
    if (!strict.isExact || !strict.hasStrictAdmissionAttestation) {
      return _writeResult(
        CanonicalDisplayCacheWriteOutcome.rejectedAdmission,
        diagnostic: strict.outcome.name,
      );
    }
    if (cancelled()) {
      return _writeResult(CanonicalDisplayCacheWriteOutcome.cancelled);
    }
    if (!current()) {
      return _writeResult(CanonicalDisplayCacheWriteOutcome.stale);
    }
    final compressedBytes = container.length - _containerHeaderBytes;
    if (compressedBytes <= 0 ||
        compressedBytes > budgets.maxCompressedBytesPerRecord ||
        !_ratioWithin(
          decodedBytes: logical.length,
          compressedBytes: compressedBytes,
          maximumRatio: budgets.maxDecompressionRatio,
        )) {
      return _writeResult(
        CanonicalDisplayCacheWriteOutcome.rejectedBudget,
        diagnostic: 'compressed_or_ratio_budget',
      );
    }
    if (_checkedAdd(container.length, budgets.maxManifestBytes) >
        budgets.maxTemporaryBytes) {
      return _writeResult(
        CanonicalDisplayCacheWriteOutcome.rejectedBudget,
        diagnostic: 'temporary_byte_budget',
      );
    }
    return _coordinator.exclusive(() async {
      var installedPayload = false;
      File? temporaryPayload;
      try {
        await _ensureInitializedUnlocked();
        final oldManifest = await _loadManifestOrEmpty();
        final fileName = _payloadName(record);
        final entry = _ManifestEntry(
          keyDigest: record.keyDigest,
          bookScopeDigest: record.bookStorageScopeDigest,
          fileName: fileName,
          recordDigest: record.checksumDigest,
          containerDigest: readerSha256(container),
          encodedBytes: container.length,
          decodedBytes: logical.length,
        );
        final retained = <_ManifestEntry>[
          for (final candidate in oldManifest.entries)
            if (candidate.keyDigest != record.keyDigest) candidate,
          entry,
        ];
        final planned = _planManifest(retained, _pins);
        if (!planned.withinBudget) {
          return _writeResult(
            CanonicalDisplayCacheWriteOutcome.pressurePinned,
            manifest: oldManifest,
            diagnostic: 'pinned_disk_pressure',
          );
        }
        if (planned.evictedKeyDigests.contains(record.keyDigest)) {
          return _writeResult(
            CanonicalDisplayCacheWriteOutcome.rejectedBudget,
            manifest: oldManifest,
            diagnostic: 'new_record_evicted_by_pressure',
          );
        }
        final nextManifest = _Manifest(
          retained.where(
            (candidate) =>
                !planned.evictedKeyDigests.contains(candidate.keyDigest),
          ),
        );
        final scopeDirectory = _scopeDirectory(record.bookStorageScopeDigest);
        await _rejectLinksAndCreate(scopeDirectory);
        final finalPayload = File(p.join(scopeDirectory.path, fileName));
        temporaryPayload = File(
          '${finalPayload.path}.tmp-${_nextTemporaryOrdinal()}',
        );
        await _boundary(
          CanonicalDisplayCacheWriteBoundary.beforePayloadTemporaryWrite,
        );
        final prePayloadWrite = _freshnessOutcome(cancelled, current);
        if (prePayloadWrite != null) {
          return _writeResult(prePayloadWrite, manifest: oldManifest);
        }
        await temporaryPayload.writeAsBytes(container, flush: true);
        await _boundary(
          CanonicalDisplayCacheWriteBoundary.afterPayloadTemporaryFlush,
        );
        final freshness = _freshnessOutcome(cancelled, current);
        if (freshness != null) {
          return _writeResult(freshness, manifest: oldManifest);
        }
        await _boundary(CanonicalDisplayCacheWriteBoundary.beforePayloadRename);
        final prePayloadRename = _freshnessOutcome(cancelled, current);
        if (prePayloadRename != null) {
          return _writeResult(prePayloadRename, manifest: oldManifest);
        }
        await _assertSafeTarget(finalPayload);
        if (await finalPayload.exists()) {
          await temporaryPayload.delete();
        } else {
          await temporaryPayload.rename(finalPayload.path);
        }
        installedPayload = true;
        await _boundary(CanonicalDisplayCacheWriteBoundary.afterPayloadRename);
        final postPayload = _freshnessOutcome(cancelled, current);
        if (postPayload != null) {
          return _writeResult(postPayload, manifest: oldManifest);
        }
        final manifestBytes = nextManifest.encode();
        if (manifestBytes.length > budgets.maxManifestBytes) {
          return _writeResult(
            CanonicalDisplayCacheWriteOutcome.rejectedBudget,
            manifest: oldManifest,
            diagnostic: 'manifest_byte_budget',
          );
        }
        final manifestFile = _manifestFile;
        final temporaryManifest = File(
          '${manifestFile.path}.tmp-${_nextTemporaryOrdinal()}',
        );
        await _boundary(
          CanonicalDisplayCacheWriteBoundary.beforeManifestTemporaryWrite,
        );
        final preManifestWrite = _freshnessOutcome(cancelled, current);
        if (preManifestWrite != null) {
          return _writeResult(preManifestWrite, manifest: oldManifest);
        }
        await temporaryManifest.writeAsBytes(manifestBytes, flush: true);
        await _boundary(
          CanonicalDisplayCacheWriteBoundary.afterManifestTemporaryFlush,
        );
        final preManifest = _freshnessOutcome(cancelled, current);
        if (preManifest != null) {
          return _writeResult(preManifest, manifest: oldManifest);
        }
        await _boundary(
          CanonicalDisplayCacheWriteBoundary.beforeManifestRename,
        );
        final preManifestRename = _freshnessOutcome(cancelled, current);
        if (preManifestRename != null) {
          return _writeResult(preManifestRename, manifest: oldManifest);
        }
        await _assertSafeTarget(manifestFile);
        await temporaryManifest.rename(manifestFile.path);
        await _boundary(CanonicalDisplayCacheWriteBoundary.afterManifestRename);
        await _deleteUnreferencedPayloads(nextManifest);
        await _boundary(CanonicalDisplayCacheWriteBoundary.beforeMemoryCommit);
        // The manifest rename is the commit point. Cancellation or generation
        // change observed after it cannot revoke an already complete atomic
        // record; a later request may evict it through the normal policy.
        _retainMemory(record);
        return _writeResult(
          CanonicalDisplayCacheWriteOutcome.stored,
          manifest: nextManifest,
          evicted: planned.evictedKeyDigests,
        );
      } on Object catch (error) {
        if (!installedPayload && temporaryPayload != null) {
          try {
            if (await temporaryPayload.exists()) {
              await temporaryPayload.delete();
            }
          } on Object {
            // Recovery removes a bounded orphan on the next open.
          }
        }
        return _writeResult(
          CanonicalDisplayCacheWriteOutcome.ioFailure,
          diagnostic: '$error',
        );
      }
    });
  }

  Future<CanonicalDisplayCacheWriteResult> enqueueAuthorizedWrite({
    required CanonicalDisplaySegmentRecord record,
    required CanonicalDisplayCacheWriteAuthorization authorization,
    required CanonicalDisplaySegmentAdmissionContext admissionContext,
    bool Function()? isCancelled,
    bool Function()? isCurrent,
    int restartDepth = 0,
  }) {
    final existing = _queuedWrites[record.keyDigest];
    if (existing != null) return existing;
    final completer = Completer<CanonicalDisplayCacheWriteResult>();
    final operation = completer.future;
    final queueEpoch = _writeQueueEpoch;
    _queuedWrites[record.keyDigest] = operation;
    _writeTail = _writeTail.then((_) async {
      try {
        final cancelled =
            queueEpoch != _writeQueueEpoch || (isCancelled?.call() ?? false);
        if (cancelled) {
          completer.complete(
            _writeResult(CanonicalDisplayCacheWriteOutcome.cancelled),
          );
          return;
        }
        final current =
            queueEpoch == _writeQueueEpoch && (isCurrent?.call() ?? true);
        if (!current) {
          completer.complete(
            _writeResult(CanonicalDisplayCacheWriteOutcome.stale),
          );
          return;
        }
        await Future<void>.delayed(Duration.zero);
        completer.complete(
          await writeAuthorized(
            record: record,
            authorization: authorization,
            admissionContext: admissionContext,
            isCancelled: () =>
                queueEpoch != _writeQueueEpoch ||
                (isCancelled?.call() ?? false),
            isCurrent: () =>
                queueEpoch == _writeQueueEpoch && (isCurrent?.call() ?? true),
            restartDepth: restartDepth,
          ),
        );
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_queuedWrites[record.keyDigest], operation)) {
          _queuedWrites.remove(record.keyDigest);
        }
      }
    });
    return operation;
  }

  Future<CanonicalDisplayCachePressureResult> enforceBudgets() =>
      _coordinator.exclusive(() async {
        await _ensureInitializedUnlocked();
        final memory = _enforceMemoryBudget();
        final disk = await _evictManifestToBudget(
          await _loadManifestOrEmpty(),
          _pins,
        );
        return CanonicalDisplayCachePressureResult(
          withinBudget: memory.withinBudget && disk.withinBudget,
          pinnedPressure: memory.pinnedPressure || disk.pinnedPressure,
          recordCount: disk.recordCount,
          bytes: disk.bytes,
          evictedKeyDigests: <String>[
            ...memory.evictedKeyDigests,
            ...disk.evictedKeyDigests,
          ],
        );
      });

  /// Removes every unpinned display derivative through the same
  /// manifest-first protocol. Pinned accepted display state is retained.
  Future<CanonicalDisplayCachePressureResult> evictAllUnpinned() =>
      _coordinator.exclusive(() async {
        await _ensureInitializedUnlocked();
        final manifest = await _loadManifestOrEmpty();
        final evicted =
            manifest.entries
                .where((entry) => !_pins.contains(entry.keyDigest))
                .map((entry) => entry.keyDigest)
                .toList(growable: false)
              ..sort();
        final retained = _Manifest(
          manifest.entries.where((entry) => _pins.contains(entry.keyDigest)),
        );
        await _installManifest(retained);
        await _deleteUnreferencedPayloads(retained);
        for (final key in evicted) {
          _removeMemory(key);
        }
        return CanonicalDisplayCachePressureResult(
          withinBudget: true,
          pinnedPressure: false,
          recordCount: retained.entries.length,
          bytes: retained.totalBytes,
          evictedKeyDigests: List<String>.unmodifiable(evicted),
        );
      });

  CanonicalDisplayCacheRecordMeasurement measureRecord(
    CanonicalDisplaySegmentRecord record,
  ) {
    final logical = CanonicalDisplaySegmentCodec.encode(record);
    final compressed = _compressBounded(
      logical,
      budgets.maxCompressedBytesPerRecord,
    );
    final continuation = record.continuationEvidence.canonicalEncoding;
    final decodedContinuation = CanonicalPaginationContinuationCodec.decode(
      continuation,
    );
    final chainDepth =
        decodedContinuation is CanonicalPaginationContinuationAccepted
        ? decodedContinuation.continuation.chainOrdinal
        : -1;
    return CanonicalDisplayCacheRecordMeasurement(
      cards: record.declaredCardCount,
      sourceSlices: record.declaredSourceSliceCount,
      blockLayouts: record.declaredBlockLayoutCount,
      decodedBytes: logical.length,
      compressedBytes: compressed.length,
      containerBytes: _checkedAdd(compressed.length, _containerHeaderBytes),
      decompressionRatioCeiling:
          (logical.length + compressed.length - 1) ~/ compressed.length,
      continuationChainDepth: chainDepth,
    );
  }

  String? validateMeasurement(
    CanonicalDisplayCacheRecordMeasurement measurement, {
    int restartDepth = 0,
  }) {
    if (measurement.cards > budgets.maxCardsPerRecord ||
        measurement.cards > budgets.maxValidationCards) {
      return 'card_budget';
    }
    if (measurement.sourceSlices > budgets.maxSourceSlicesPerRecord ||
        measurement.sourceSlices > budgets.maxValidationSourceSlices) {
      return 'source_slice_budget';
    }
    if (measurement.blockLayouts > budgets.maxBlockLayoutsPerRecord) {
      return 'block_layout_budget';
    }
    if (measurement.decodedBytes > budgets.maxDecodedBytesPerRecord) {
      return 'decoded_byte_budget';
    }
    if (measurement.compressedBytes > budgets.maxCompressedBytesPerRecord) {
      return 'compressed_byte_budget';
    }
    if (measurement.decompressionRatioCeiling > budgets.maxDecompressionRatio) {
      return 'decompression_ratio_budget';
    }
    if (measurement.continuationChainDepth >
        budgets.maxContinuationChainDepth) {
      return 'continuation_chain_budget';
    }
    if (restartDepth < 0 || restartDepth > budgets.maxRestartDepth) {
      return 'restart_depth_budget';
    }
    if (_checkedAdd(measurement.containerBytes, budgets.maxManifestBytes) >
        budgets.maxTemporaryBytes) {
      return 'temporary_byte_budget';
    }
    return null;
  }

  Future<int> get diskRecordCount async => _coordinator.exclusive(() async {
    await _ensureInitializedUnlocked();
    return (await _loadManifestOrEmpty()).entries.length;
  });

  Future<int> get diskBytes async => _coordinator.exclusive(() async {
    await _ensureInitializedUnlocked();
    return (await _loadManifestOrEmpty()).totalBytes;
  });

  Future<CanonicalDisplayInvalidationLookupReceipt?> lookupForInvalidation({
    required CanonicalDisplayInvalidationStorageScope scope,
    required String bookScopeDigest,
    required String keyDigest,
  }) => _coordinator.exclusive(() async {
    await _ensureInitializedUnlocked();
    if (p.normalize(_storageRoot.absolute.path) != scope.rootPath ||
        scope.bookScope != bookScopeDigest ||
        !_digestPattern.hasMatch(bookScopeDigest) ||
        !_digestPattern.hasMatch(keyDigest)) {
      return null;
    }
    final manifest = await _loadManifestOrEmpty();
    final entry = manifest.entries
        .where(
          (candidate) =>
              candidate.keyDigest == keyDigest &&
              candidate.bookScopeDigest == bookScopeDigest,
        )
        .firstOrNull;
    if (entry == null) return null;
    return _CanonicalPhysicalInvalidationReceipt(
      service: this,
      scope: scope,
      entry: entry,
    );
  });

  Future<CanonicalDisplayInvalidationPhysicalMutation> _invalidateEntry(
    _ManifestEntry entry,
    CanonicalDisplayInvalidationAction action,
    CanonicalDisplayInvalidationMutationInterceptor? interceptor,
  ) => _coordinator.exclusive(() async {
    if (action !=
            CanonicalDisplayInvalidationAction.invalidateExactDiskDerivative &&
        action !=
            CanonicalDisplayInvalidationAction.quarantineExactDiskDerivative) {
      return const CanonicalDisplayInvalidationPhysicalMutation(
        status: CanonicalDisplayInvalidationMutationStatus.failed,
        physicalFilesTouched: 0,
        manifestEntriesTouched: 0,
        recordsQuarantined: 0,
        memoryEntriesEvicted: 0,
        diagnosticCode: 'unsafe_canonical_physical_action',
      );
    }
    try {
      await _ensureInitializedUnlocked();
      final manifest = await _loadManifestOrEmpty();
      final present = manifest.entries.any(
        (candidate) =>
            candidate.keyDigest == entry.keyDigest &&
            candidate.fileName == entry.fileName,
      );
      if (!present) {
        return const CanonicalDisplayInvalidationPhysicalMutation.noOp();
      }
      await interceptor?.call(
        CanonicalDisplayInvalidationMutationStep.beforeManifestUpdate,
      );
      final next = _Manifest(
        manifest.entries.where(
          (candidate) => candidate.keyDigest != entry.keyDigest,
        ),
      );
      await _installManifest(next);
      _removeMemory(entry.keyDigest);
      await interceptor?.call(
        CanonicalDisplayInvalidationMutationStep.beforePayloadMutation,
      );
      final payload = _payloadFile(entry);
      var files = 0;
      var quarantined = 0;
      if (await payload.exists()) {
        if (action ==
            CanonicalDisplayInvalidationAction.quarantineExactDiskDerivative) {
          await payload.rename('${payload.path}.quarantine');
          quarantined = 1;
        } else {
          await payload.delete();
        }
        files = 1;
      }
      return CanonicalDisplayInvalidationPhysicalMutation(
        status: CanonicalDisplayInvalidationMutationStatus.applied,
        physicalFilesTouched: files,
        manifestEntriesTouched: 1,
        recordsQuarantined: quarantined,
        memoryEntriesEvicted: 0,
      );
    } on Object {
      return const CanonicalDisplayInvalidationPhysicalMutation(
        status: CanonicalDisplayInvalidationMutationStatus.failed,
        physicalFilesTouched: 0,
        manifestEntriesTouched: 0,
        recordsQuarantined: 0,
        memoryEntriesEvicted: 0,
        diagnosticCode: 'canonical_physical_invalidation_failed',
      );
    }
  });

  void clearMemory() {
    _memory.clear();
    _memoryBytes = 0;
    _pins = const <String>{};
  }

  void _retainMemory(CanonicalDisplaySegmentRecord record) {
    final bytes = CanonicalDisplaySegmentCodec.encode(record).length;
    if (bytes > budgets.maxMemoryBytes) return;
    final old = _memory.remove(record.keyDigest);
    if (old != null) _memoryBytes -= old.bytes;
    _memory[record.keyDigest] = _MemoryEntry(record, bytes);
    _memoryBytes = _checkedAdd(_memoryBytes, bytes);
    final pressure = _enforceMemoryBudget();
    if (!pressure.withinBudget) {
      _memory.remove(record.keyDigest);
      _memoryBytes -= bytes;
      if (old != null) {
        _memory[record.keyDigest] = old;
        _memoryBytes = _checkedAdd(_memoryBytes, old.bytes);
      }
    }
  }

  CanonicalDisplayCachePressureResult _enforceMemoryBudget() {
    final evicted = <String>[];
    while (_memory.length > budgets.maxMemoryRecords ||
        _memoryBytes > budgets.maxMemoryBytes) {
      final key = _memory.keys.where((key) => !_pins.contains(key)).sortedFirst;
      if (key == null) {
        return CanonicalDisplayCachePressureResult(
          withinBudget: false,
          pinnedPressure: true,
          recordCount: _memory.length,
          bytes: _memoryBytes,
          evictedKeyDigests: List<String>.unmodifiable(evicted),
        );
      }
      _removeMemory(key);
      evicted.add(key);
    }
    return CanonicalDisplayCachePressureResult(
      withinBudget: true,
      pinnedPressure: false,
      recordCount: _memory.length,
      bytes: _memoryBytes,
      evictedKeyDigests: List<String>.unmodifiable(evicted),
    );
  }

  void _removeMemory(String key) {
    final removed = _memory.remove(key);
    if (removed != null) _memoryBytes -= removed.bytes;
  }

  _ManifestPlan _planManifest(
    Iterable<_ManifestEntry> source,
    Set<String> pins,
  ) {
    final entries = source.toList(growable: false);
    var bytes = 0;
    for (final entry in entries) {
      bytes = _checkedAdd(bytes, entry.encodedBytes);
    }
    final retained = <String>{for (final entry in entries) entry.keyDigest};
    final evicted = <String>[];
    final candidates =
        entries
            .where((entry) => !pins.contains(entry.keyDigest))
            .map((entry) => entry.keyDigest)
            .toList(growable: false)
          ..sort();
    var cursor = 0;
    while (retained.length > budgets.maxDiskRecords ||
        bytes > budgets.maxDiskBytes) {
      if (cursor >= candidates.length) {
        return _ManifestPlan(false, evicted);
      }
      final key = candidates[cursor++];
      final entry = entries.firstWhere((item) => item.keyDigest == key);
      retained.remove(key);
      bytes -= entry.encodedBytes;
      evicted.add(key);
    }
    return _ManifestPlan(true, evicted);
  }

  Future<CanonicalDisplayCachePressureResult> _evictManifestToBudget(
    _Manifest manifest,
    Set<String> pins,
  ) async {
    final plan = _planManifest(manifest.entries, pins);
    if (!plan.withinBudget) {
      return CanonicalDisplayCachePressureResult(
        withinBudget: false,
        pinnedPressure: true,
        recordCount: manifest.entries.length,
        bytes: manifest.totalBytes,
        evictedKeyDigests: const <String>[],
      );
    }
    if (plan.evictedKeyDigests.isEmpty) {
      return CanonicalDisplayCachePressureResult(
        withinBudget: true,
        pinnedPressure: false,
        recordCount: manifest.entries.length,
        bytes: manifest.totalBytes,
        evictedKeyDigests: const <String>[],
      );
    }
    final next = _Manifest(
      manifest.entries.where(
        (entry) => !plan.evictedKeyDigests.contains(entry.keyDigest),
      ),
    );
    await _installManifest(next);
    await _deleteUnreferencedPayloads(next);
    return CanonicalDisplayCachePressureResult(
      withinBudget: true,
      pinnedPressure: false,
      recordCount: next.entries.length,
      bytes: next.totalBytes,
      evictedKeyDigests: List<String>.unmodifiable(plan.evictedKeyDigests),
    );
  }

  Future<_Manifest> _loadManifestOrEmpty() async {
    final file = _manifestFile;
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) return _Manifest(const []);
    if (stat.type != FileSystemEntityType.file ||
        stat.size <= 0 ||
        stat.size > budgets.maxManifestBytes) {
      throw const FormatException('Canonical manifest physical size rejected.');
    }
    await _assertSafeTarget(file, requireExistingFile: true);
    return _Manifest.decode(
      Uint8List.fromList(await file.readAsBytes()),
      budgets,
    );
  }

  Future<void> _installManifest(_Manifest manifest) async {
    final bytes = manifest.encode();
    if (bytes.length > budgets.maxManifestBytes) {
      throw const FormatException('Canonical manifest byte budget exceeded.');
    }
    final temporary = File(
      '${_manifestFile.path}.tmp-${_nextTemporaryOrdinal()}',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    await _assertSafeTarget(_manifestFile);
    await temporary.rename(_manifestFile.path);
  }

  Future<Uint8List> _readContainer(File file, _ManifestEntry entry) async {
    await _assertSafeTarget(file, requireExistingFile: true);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size != entry.encodedBytes ||
        stat.size < _containerHeaderBytes ||
        stat.size >
            _checkedAdd(
              budgets.maxCompressedBytesPerRecord,
              _containerHeaderBytes,
            )) {
      throw const FormatException('Canonical payload size is invalid.');
    }
    final handle = await file.open();
    try {
      final header = Uint8List.fromList(
        await handle.read(_containerHeaderBytes),
      );
      final declared = _decodeContainerHeader(header);
      if (declared.compressedBytes > budgets.maxCompressedBytesPerRecord ||
          declared.decodedBytes > budgets.maxDecodedBytesPerRecord ||
          declared.compressedBytes != stat.size - _containerHeaderBytes ||
          declared.decodedBytes != entry.decodedBytes ||
          !_ratioWithin(
            decodedBytes: declared.decodedBytes,
            compressedBytes: declared.compressedBytes,
            maximumRatio: budgets.maxDecompressionRatio,
          )) {
        throw const FormatException('Canonical declared sizes are rejected.');
      }
      final compressed = Uint8List.fromList(
        await handle.read(declared.compressedBytes),
      );
      if (compressed.length != declared.compressedBytes ||
          readerSha256(compressed) != declared.compressedDigest ||
          readerSha256(Uint8List.fromList(<int>[...header, ...compressed])) !=
              entry.containerDigest) {
        throw const FormatException('Canonical container checksum is invalid.');
      }
      final sink = _BoundedByteSink(declared.decodedBytes);
      final decoder = gzip.decoder.startChunkedConversion(sink);
      decoder.add(compressed);
      decoder.close();
      final logical = sink.takeBytes();
      if (logical.length != declared.decodedBytes) {
        throw const FormatException('Canonical decoded size is contradictory.');
      }
      return logical;
    } finally {
      await handle.close();
    }
  }

  ({int decodedBytes, int compressedBytes, String compressedDigest})
  _decodeContainerHeader(Uint8List header) {
    if (header.length != _containerHeaderBytes ||
        !_sameBytes(header.sublist(0, 8), _magic) ||
        header.sublist(92).any((value) => value != 0)) {
      throw const FormatException('Canonical container header is malformed.');
    }
    final data = ByteData.sublistView(header);
    if (data.getUint32(8) != canonicalDisplayCachePhysicalFormatVersion) {
      throw const FormatException('Unsupported canonical container version.');
    }
    final decoded = data.getUint64(12);
    final compressed = data.getUint64(20);
    final digest = ascii.decode(header.sublist(28, 92), allowInvalid: false);
    if (!_digestPattern.hasMatch(digest) || decoded <= 0 || compressed <= 0) {
      throw const FormatException(
        'Canonical container declaration is invalid.',
      );
    }
    return (
      decodedBytes: decoded,
      compressedBytes: compressed,
      compressedDigest: digest,
    );
  }

  Future<void> _recoverTemporaryAndOrphanFiles() async {
    _Manifest? manifest;
    try {
      manifest = await _loadManifestOrEmpty();
    } on Object {
      manifest = null;
    }
    final referenced = manifest == null
        ? const <String>{}
        : manifest.entries.map((entry) => entry.fileName).toSet();
    await for (final entity in _storageRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.contains('.tmp-') ||
          (manifest != null &&
              name.endsWith('.cseg4.gz') &&
              !referenced.contains(name))) {
        try {
          await entity.delete();
        } on Object {
          // A remaining temporary/orphan is never manifest-addressable.
        }
      }
    }
  }

  Future<void> _deleteUnreferencedPayloads(_Manifest manifest) async {
    final referenced = manifest.entries.map((entry) => entry.fileName).toSet();
    await for (final entity in _storageRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File &&
          entity.path.endsWith('.cseg4.gz') &&
          !referenced.contains(p.basename(entity.path))) {
        try {
          await entity.delete();
        } on Object {
          // Unreferenced bytes are safe and retried during recovery.
        }
      }
    }
  }

  Future<void> _rejectLinksAndCreate(Directory directory) async {
    final root = p.normalize(_storageRoot.absolute.path);
    final target = p.normalize(directory.absolute.path);
    if (target != root && !p.isWithin(root, target)) {
      throw const FileSystemException('Canonical cache path escaped root.');
    }
    final relative = p.relative(target, from: root);
    var cursor = _storageRoot;
    if (await FileSystemEntity.type(root, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Canonical cache root is a link.');
    }
    if (!await _storageRoot.exists()) {
      await _storageRoot.create(recursive: true);
    }
    if (relative != '.') {
      for (final component in p.split(relative)) {
        if (component.isEmpty || component == '..' || component.contains('/')) {
          throw const FileSystemException('Unsafe canonical path component.');
        }
        cursor = Directory(p.join(cursor.path, component));
        final type = await FileSystemEntity.type(
          cursor.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link ||
            (type != FileSystemEntityType.notFound &&
                type != FileSystemEntityType.directory)) {
          throw const FileSystemException(
            'Canonical cache component is unsafe.',
          );
        }
        if (type == FileSystemEntityType.notFound) await cursor.create();
      }
    }
  }

  Future<void> _assertSafeTarget(
    File file, {
    bool requireExistingFile = false,
  }) async {
    final root = p.normalize(_storageRoot.absolute.path);
    final target = p.normalize(file.absolute.path);
    if (!p.isWithin(root, target) ||
        p.basename(target).contains('/') ||
        p.basename(target).contains('\\') ||
        p.basename(target).contains('\u0000')) {
      throw const FileSystemException('Canonical cache target escaped root.');
    }
    final parentType = await FileSystemEntity.type(
      file.parent.path,
      followLinks: false,
    );
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (parentType != FileSystemEntityType.directory ||
        targetType == FileSystemEntityType.link ||
        (requireExistingFile && targetType != FileSystemEntityType.file) ||
        (!requireExistingFile &&
            targetType != FileSystemEntityType.notFound &&
            targetType != FileSystemEntityType.file)) {
      throw const FileSystemException('Canonical cache target is unsafe.');
    }
  }

  Directory _scopeDirectory(String digest) {
    if (!_digestPattern.hasMatch(digest)) {
      throw ArgumentError.value(digest, 'digest');
    }
    return Directory(p.join(_storageRoot.path, digest));
  }

  File _payloadFile(_ManifestEntry entry) =>
      File(p.join(_scopeDirectory(entry.bookScopeDigest).path, entry.fileName));

  File get _manifestFile => File(p.join(_storageRoot.path, 'manifest.v4.json'));

  String _payloadName(CanonicalDisplaySegmentRecord record) =>
      'seg-sha256-${record.keyDigest}-${record.checksumDigest}.cseg4.gz';

  Future<void> _boundary(CanonicalDisplayCacheWriteBoundary boundary) async {
    await writeInterceptor?.call(boundary);
  }

  CanonicalDisplayCacheWriteOutcome? _freshnessOutcome(
    bool Function() cancelled,
    bool Function() current,
  ) {
    if (cancelled()) return CanonicalDisplayCacheWriteOutcome.cancelled;
    if (!current()) return CanonicalDisplayCacheWriteOutcome.stale;
    return null;
  }

  CanonicalDisplayCacheWriteResult _writeResult(
    CanonicalDisplayCacheWriteOutcome outcome, {
    _Manifest? manifest,
    Iterable<String> evicted = const <String>[],
    String? diagnostic,
  }) => CanonicalDisplayCacheWriteResult(
    outcome: outcome,
    recordCount: manifest?.entries.length ?? 0,
    diskBytes: manifest?.totalBytes ?? 0,
    memoryRecordCount: _memory.length,
    memoryBytes: _memoryBytes,
    evictedKeyDigests: List<String>.unmodifiable(evicted),
    diagnostic: diagnostic,
  );

  static int _nextTemporaryOrdinal() => _temporaryOrdinal++;
}

final class _ManifestPlan {
  const _ManifestPlan(this.withinBudget, this.evictedKeyDigests);
  final bool withinBudget;
  final List<String> evictedKeyDigests;
}

final class _CanonicalPhysicalInvalidationReceipt
    implements CanonicalDisplayInvalidationLookupReceipt {
  const _CanonicalPhysicalInvalidationReceipt({
    required this.service,
    required this.scope,
    required this.entry,
  });

  final CanonicalDisplayCacheService service;
  @override
  final CanonicalDisplayInvalidationStorageScope scope;
  final _ManifestEntry entry;

  @override
  CanonicalDisplayInvalidationCandidateType get candidateType =>
      CanonicalDisplayInvalidationCandidateType.strictCanonicalDisplay;

  @override
  Future<CanonicalDisplayInvalidationPhysicalMutation> mutate(
    CanonicalDisplayInvalidationAction action, {
    CanonicalDisplayInvalidationMutationInterceptor? interceptor,
  }) => service._invalidateEntry(entry, action, interceptor);
}

final class _BoundedByteSink implements Sink<List<int>> {
  _BoundedByteSink(this.maximumBytes);
  final int maximumBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  var _length = 0;
  var _closed = false;

  @override
  void add(List<int> data) {
    if (_closed || data.length > maximumBytes - _length) {
      throw const FormatException('Canonical decompression output exceeded.');
    }
    _length += data.length;
    _builder.add(data);
  }

  @override
  void close() => _closed = true;

  Uint8List takeBytes() {
    if (!_closed) throw StateError('Canonical decompression is incomplete.');
    return _builder.takeBytes();
  }
}

extension on Iterable<String> {
  String? get sortedFirst {
    final values = toList(growable: false)..sort();
    return values.isEmpty ? null : values.first;
  }
}

final RegExp _digestPattern = RegExp(r'^[0-9a-f]{64}$');

bool _ratioWithin({
  required int decodedBytes,
  required int compressedBytes,
  required int maximumRatio,
}) {
  if (decodedBytes <= 0 || compressedBytes <= 0 || maximumRatio <= 0) {
    return false;
  }
  final quotient = decodedBytes ~/ compressedBytes;
  final remainder = decodedBytes % compressedBytes;
  return quotient < maximumRatio ||
      (quotient == maximumRatio && remainder == 0);
}

Uint8List _compressBounded(Uint8List logical, int maximumBytes) {
  final sink = _BoundedByteSink(maximumBytes);
  final encoder = gzip.encoder.startChunkedConversion(sink);
  encoder.add(logical);
  encoder.close();
  return sink.takeBytes();
}

({Uint8List logical, Uint8List container}) _prepareCanonicalCacheBytes(
  CanonicalDisplaySegmentRecord record,
  int maximumCompressedBytes,
) {
  final logical = CanonicalDisplaySegmentCodec.encode(record);
  final compressed = _compressBounded(logical, maximumCompressedBytes);
  final header = Uint8List(96);
  const magic = <int>[78, 76, 67, 83, 69, 71, 52, 10];
  header.setRange(0, magic.length, magic);
  final data = ByteData.sublistView(header);
  data.setUint32(8, canonicalDisplayCachePhysicalFormatVersion);
  data.setUint64(12, logical.length);
  data.setUint64(20, compressed.length);
  header.setRange(28, 92, ascii.encode(readerSha256(compressed)));
  final container =
      (BytesBuilder(copy: false)
            ..add(header)
            ..add(compressed))
          .takeBytes();
  return (logical: logical, container: container);
}

Future<({Uint8List logical, Uint8List container})>
_prepareCanonicalCacheBytesOffIsolate(
  CanonicalDisplaySegmentRecord record,
  int maximumCompressedBytes,
) => Isolate.run(
  () => _prepareCanonicalCacheBytes(record, maximumCompressedBytes),
);

int _checkedAdd(int left, int right, [int maximum = 0x7fffffffffffffff]) {
  if (left < 0 || right < 0 || left > maximum - right) {
    throw const FormatException('Canonical cache aggregate overflow.');
  }
  return left + right;
}

bool _safePayloadName(_ManifestEntry entry) =>
    entry.fileName ==
        'seg-sha256-${entry.keyDigest}-${entry.recordDigest}.cseg4.gz' &&
    !entry.fileName.contains('/') &&
    !entry.fileName.contains('\\') &&
    !entry.fileName.contains('\u0000') &&
    !entry.fileName.contains('..');

void _expectKeys(Map<String, Object?> json, Set<String> expected) {
  if (json.length != expected.length || !expected.every(json.containsKey)) {
    throw const FormatException('Canonical cache fields are contradictory.');
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Canonical cache $field is invalid.');
  }
  return value;
}

String _requiredDigest(Object? value, String field) {
  final result = _requiredString(value, field);
  if (!_digestPattern.hasMatch(result)) {
    throw FormatException('Canonical cache $field is not a digest.');
  }
  return result;
}

int _requiredNonnegativeInt(Object? value, String field) {
  if (value is! int || value < 0) {
    throw FormatException('Canonical cache $field is invalid.');
  }
  return value;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
