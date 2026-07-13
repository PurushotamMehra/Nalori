import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/book_chunk.dart';
import 'epub_parser.dart';
import 'lazy_epub_index_service.dart';
import 'lazy_parsed_book.dart';
import 'parsed_section_cache_service.dart';

const bool _lazySectionRepoDiagEnabled = bool.fromEnvironment(
  'NALORI_EPUB_DIAG',
);
const String _lazySectionRepoDiagPrefix = 'NALORI_EPUB_DIAG';

void _lazySectionRepoDiagLog(String phase, Map<String, Object?> fields) {
  if (!_lazySectionRepoDiagEnabled) return;
  final parts = <String>[
    _lazySectionRepoDiagPrefix,
    'phase=$phase',
    'ts=${DateTime.now().toIso8601String()}',
    for (final entry in fields.entries)
      if (entry.value != null) '${entry.key}=${entry.value}',
  ];
  // ignore: avoid_print
  print(parts.join(' '));
}

enum LazySectionWorkPriority {
  explicitNavigation(0),
  visibleSection(1),
  adjacentReadiness(2),
  boundaryPrefetch(2),
  targetPreview(3),
  parsedHydration(4),
  recentRetention(5),
  layoutPagination(6),
  derivedIndexing(6);

  const LazySectionWorkPriority(this.rank);

  final int rank;

  bool outranks(LazySectionWorkPriority other) => rank < other.rank;
}

enum SharedSectionJobState { queued, launched, committing }

final class SharedSectionWorkCancelled implements Exception {
  const SharedSectionWorkCancelled(this.identity);
  final LazySectionIdentity identity;

  @override
  String toString() =>
      'Queued shared section work cancelled: ${identity.stableKey}';
}

final class SharedSectionWorkRequest {
  const SharedSectionWorkRequest({
    required this.future,
    required this.createdJob,
  });

  final Future<ParsedSection> future;
  final bool createdJob;
}

final class SharedLazySectionWorkCoordinator {
  SharedLazySectionWorkCoordinator({this.maxConcurrentJobs = 2})
    : assert(maxConcurrentJobs > 0);

  static final SharedLazySectionWorkCoordinator instance =
      SharedLazySectionWorkCoordinator();

  final int maxConcurrentJobs;
  final Map<String, _SharedSectionJob> _jobs = {};
  final Map<String, int> _bookGenerations = {};
  var _globalGeneration = 0;
  var _runningJobs = 0;
  var _drainScheduled = false;

  int get activeJobCount => _jobs.length;

  SharedSectionWorkRequest request({
    required LazySectionIdentity identity,
    required Object owner,
    required LazySectionWorkPriority priority,
    required Future<ParsedSection> Function() operation,
  }) {
    final generation = _generation(identity.bookId);
    final key = _jobKey(identity, generation);
    final existing = _jobs[key];
    if (existing != null) {
      existing.owners.add(owner);
      if (priority.outranks(existing.priority)) {
        existing.priority = priority;
      }
      _scheduleDrain();
      return SharedSectionWorkRequest(
        future: existing.completer.future,
        createdJob: false,
      );
    }
    final job = _SharedSectionJob(
      key: key,
      identity: identity,
      generation: generation,
      priority: priority,
      operation: operation,
      owners: {owner},
    );
    _jobs[key] = job;
    _scheduleDrain();
    return SharedSectionWorkRequest(
      future: job.completer.future,
      createdJob: true,
    );
  }

  void releaseOwner(Object owner) {
    final cancelled = <_SharedSectionJob>[];
    for (final job in _jobs.values) {
      job.owners.remove(owner);
      if (job.owners.isEmpty && job.state == SharedSectionJobState.queued) {
        cancelled.add(job);
      }
    }
    for (final job in cancelled) {
      if (!identical(_jobs[job.key], job)) continue;
      _jobs.remove(job.key);
      job.completer.completeError(SharedSectionWorkCancelled(job.identity));
    }
  }

  void invalidateBook(String bookId) {
    _bookGenerations[bookId] = (_bookGenerations[bookId] ?? 0) + 1;
    final cancelled = _jobs.values
        .where(
          (job) =>
              job.identity.bookId == bookId &&
              job.state == SharedSectionJobState.queued,
        )
        .toList(growable: false);
    for (final job in cancelled) {
      _jobs.remove(job.key);
      job.completer.completeError(SharedSectionWorkCancelled(job.identity));
    }
  }

  void invalidateAll() {
    _globalGeneration++;
    final queued = _jobs.values
        .where((job) => job.state == SharedSectionJobState.queued)
        .toList(growable: false);
    for (final job in queued) {
      _jobs.remove(job.key);
      job.completer.completeError(SharedSectionWorkCancelled(job.identity));
    }
  }

  LazySectionWorkPriority? priorityFor(LazySectionIdentity identity) {
    final generation = _generation(identity.bookId);
    return _jobs[_jobKey(identity, generation)]?.priority;
  }

  SharedSectionJobState? stateFor(LazySectionIdentity identity) {
    final generation = _generation(identity.bookId);
    return _jobs[_jobKey(identity, generation)]?.state;
  }

  void markCommitting(LazySectionIdentity identity) {
    final generation = _generation(identity.bookId);
    final job = _jobs[_jobKey(identity, generation)];
    if (job != null && job.state == SharedSectionJobState.launched) {
      job.state = SharedSectionJobState.committing;
    }
  }

  String _jobKey(LazySectionIdentity identity, int generation) =>
      '$generation|${identity.stableKey}';

  int _generation(String bookId) =>
      _globalGeneration * 0x100000000 + (_bookGenerations[bookId] ?? 0);

  void _scheduleDrain() {
    if (_drainScheduled) return;
    _drainScheduled = true;
    scheduleMicrotask(() {
      _drainScheduled = false;
      _drain();
    });
  }

  void _drain() {
    while (_runningJobs < maxConcurrentJobs) {
      final queued =
          _jobs.values
              .where((job) => job.state == SharedSectionJobState.queued)
              .toList(growable: false)
            ..sort((a, b) => a.priority.rank.compareTo(b.priority.rank));
      if (queued.isEmpty) return;
      final job = queued.first;
      if (job.owners.isEmpty) {
        _jobs.remove(job.key);
        job.completer.completeError(SharedSectionWorkCancelled(job.identity));
        continue;
      }
      _launch(job);
    }
  }

  void _launch(_SharedSectionJob job) {
    job.state = SharedSectionJobState.launched;
    _runningJobs++;
    unawaited(
      job
          .operation()
          .then(job.completer.complete)
          .catchError((Object error, StackTrace stackTrace) {
            job.completer.completeError(error, stackTrace);
          })
          .whenComplete(() {
            _runningJobs--;
            if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
            _scheduleDrain();
          }),
    );
  }
}

final class _SharedSectionJob {
  _SharedSectionJob({
    required this.key,
    required this.identity,
    required this.generation,
    required this.priority,
    required this.operation,
    required this.owners,
  });

  final String key;
  final LazySectionIdentity identity;
  final int generation;
  LazySectionWorkPriority priority;
  final Future<ParsedSection> Function() operation;
  final Set<Object> owners;
  final Completer<ParsedSection> completer = Completer<ParsedSection>();
  SharedSectionJobState state = SharedSectionJobState.queued;
}

final class LazySectionParseRequest {
  const LazySectionParseRequest({
    required this.identity,
    required this.html,
    required this.section,
    required this.resourceBytes,
    required this.resourceMediaTypes,
    required this.footnoteContentById,
  });

  final LazySectionIdentity identity;
  final String html;
  final ChunkSection section;
  final Map<String, Uint8List> resourceBytes;
  final Map<String, String> resourceMediaTypes;
  final Map<String, String> footnoteContentById;
}

typedef LazySectionParser =
    Future<ParsedSection> Function(LazySectionParseRequest request);

final class LazySectionRepository {
  LazySectionRepository({
    LazyEpubIndexService? indexService,
    ParsedSectionCacheService? cache,
    SharedLazySectionWorkCoordinator? workCoordinator,
    LazySectionParser? parser,
    int retainedSectionLimit = 3,
    int retainedSectionByteBudget = 6 * 1024 * 1024,
  }) : _indexService = indexService ?? LazyEpubIndexService(),
       _cache = cache ?? ParsedSectionCacheService(),
       _workCoordinator =
           workCoordinator ?? SharedLazySectionWorkCoordinator.instance,
       _parser = parser ?? _defaultLazySectionParser,
       _retainedSectionLimit = retainedSectionLimit,
       _retainedSectionByteBudget = retainedSectionByteBudget;

  final LazyEpubIndexService _indexService;
  final ParsedSectionCacheService _cache;
  final SharedLazySectionWorkCoordinator _workCoordinator;
  final LazySectionParser _parser;
  final int _retainedSectionLimit;
  final int _retainedSectionByteBudget;
  final _retained = <int, ParsedSection>{};
  final _retainedCosts = <int, int>{};
  final _pinnedSpineIndices = <int>{};
  final Object _workOwner = Object();
  final Set<Future<ParsedSection>> _ownedSharedWork = {};
  LazyEpubBookHandle? _handle;
  String? _dependencySignature;
  int _sessionEpoch = 0;

  LazyEpubIndex? get index => _handle?.index;
  int get retainedSectionCount => _retained.length;
  int get retainedEstimatedBytes =>
      _retainedCosts.values.fold(0, (sum, cost) => sum + cost);
  Iterable<int> get retainedSpineIndices => _retained.keys;

  void pinSections(Iterable<int> spineIndices) {
    _pinnedSpineIndices
      ..clear()
      ..addAll(spineIndices);
    _evictUntilWithinBudget();
    _updateDiskProtection();
  }

  void recordMeaningfulRead(int spineIndex, int readAtMs) {
    final handle = _handle;
    if (handle == null ||
        spineIndex < 0 ||
        spineIndex >= handle.index.spine.length) {
      return;
    }
    final adjacent = <LazySectionIdentity>[];
    for (final candidate in [spineIndex - 1, spineIndex + 1]) {
      if (candidate >= 0 && candidate < handle.index.spine.length) {
        adjacent.add(_identityFor(handle.index, candidate));
      }
    }
    _cache.recordMeaningfulReadProtection(
      bookId: handle.index.bookId,
      readAtMs: readAtMs,
      lastVisible: _identityFor(handle.index, spineIndex),
      adjacent: adjacent,
    );
  }

  Future<LazyEpubIndex> open(File file) async {
    await close();
    _sessionEpoch++;
    await _cache.cleanupTemporaryFiles();
    _handle = await _indexService.openBookIndex(file);
    _dependencySignature = lazySectionDependencySignature(_handle!.index);
    await _cache.registerPublication(
      bookId: _handle!.index.bookId,
      publicationFingerprint: _handle!.index.publicationFingerprint,
    );
    _updateDiskProtection();
    await _cache.enforceBudget();
    return _handle!.index;
  }

  Future<ParsedSection> loadSection(int spineIndex) async {
    return loadSectionWithPriority(
      spineIndex,
      priority: LazySectionWorkPriority.explicitNavigation,
    );
  }

  Future<ParsedSection> loadSectionWithPriority(
    int spineIndex, {
    required LazySectionWorkPriority priority,
    bool pinDuringLoad = false,
  }) async {
    final handle = _requireHandle();
    if (spineIndex < 0 || spineIndex >= handle.index.spine.length) {
      throw RangeError.index(spineIndex, handle.index.spine, 'spineIndex');
    }
    final retained = _retained.remove(spineIndex);
    if (retained != null) {
      _retained[spineIndex] = retained;
      _lazySectionRepoDiagLog('adjacent_section_memory_hit', {
        'book': handle.index.bookId,
        'spineIndex': spineIndex,
        'href': handle.index.spine[spineIndex].href,
        'priority': priority.name,
        'retainedBytes': retainedEstimatedBytes,
      });
      return retained;
    }

    final protectDuringWork = pinDuringLoad || priority.rank <= 2;
    final addedWorkPin =
        protectDuringWork && _pinnedSpineIndices.add(spineIndex);
    if (addedWorkPin) _updateDiskProtection();

    _lazySectionRepoDiagLog('lazy_section_request', {
      'book': handle.index.bookId,
      'spineIndex': spineIndex,
      'href': handle.index.spine[spineIndex].href,
      'priority': priority.name,
    });

    final epoch = _sessionEpoch;
    final identity = _identityFor(handle.index, spineIndex);
    final cacheGeneration = _cache.generationForBook(identity.bookId);
    final request = _workCoordinator.request(
      identity: identity,
      owner: _workOwner,
      priority: priority,
      operation: () => _loadSectionUnshared(
        handle,
        identity,
        priority: priority,
        cacheGeneration: cacheGeneration,
      ),
    );
    if (!request.createdJob) {
      _lazySectionRepoDiagLog('duplicate_section_request_joined', {
        'book': handle.index.bookId,
        'spineIndex': spineIndex,
        'href': handle.index.spine[spineIndex].href,
        'priority': priority.name,
      });
    } else {
      _ownedSharedWork.add(request.future);
      unawaited(
        request.future.then<void>(
          (_) {
            _ownedSharedWork.remove(request.future);
          },
          onError: (_, __) {
            _ownedSharedWork.remove(request.future);
          },
        ),
      );
    }
    try {
      final result = await request.future;
      if (_canRetainResult(handle, epoch)) _retain(result);
      return result;
    } finally {
      if (addedWorkPin && epoch == _sessionEpoch) {
        _pinnedSpineIndices.remove(spineIndex);
        _evictUntilWithinBudget();
        _updateDiskProtection();
      }
    }
  }

  Future<ParsedSection> _loadSectionUnshared(
    LazyEpubBookHandle handle,
    LazySectionIdentity identity, {
    required LazySectionWorkPriority priority,
    required int cacheGeneration,
  }) async {
    final spineIndex = identity.spineIndex;

    final cached = await _cache.loadSection(
      identity,
      expectedGeneration: cacheGeneration,
    );
    if (cached != null) {
      _lazySectionRepoDiagLog('adjacent_section_parsed_cache_hit', {
        'book': identity.bookId,
        'spineIndex': identity.spineIndex,
        'href': identity.href,
        'priority': priority.name,
        'chunks': cached.chunks.length,
      });
      return cached;
    }

    _lazySectionRepoDiagLog('adjacent_section_parse_started', {
      'book': identity.bookId,
      'spineIndex': identity.spineIndex,
      'href': identity.href,
      'priority': priority.name,
    });
    final sectionResource = await handle.readSection(spineIndex);
    final section = _sectionKindFor(handle.index, spineIndex);
    final resources = await _readSectionImageResources(
      handle,
      sectionResource.href,
      sectionResource.html,
    );
    final footnotes = await _readLinkedFootnotes(
      handle,
      sectionResource.href,
      sectionResource.html,
    );
    final stopwatch = Stopwatch()..start();
    final parsed = await _parser(
      LazySectionParseRequest(
        identity: identity,
        html: sectionResource.html,
        section: section,
        resourceBytes: resources.bytes,
        resourceMediaTypes: resources.mediaTypes,
        footnoteContentById: footnotes,
      ),
    );
    stopwatch.stop();
    _lazySectionRepoDiagLog('lazy_section_parse_complete', {
      'book': identity.bookId,
      'spineIndex': identity.spineIndex,
      'href': identity.href,
      'chunks': parsed.chunks.length,
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'priority': priority.name,
    });
    _lazySectionRepoDiagLog('adjacent_section_parse_completed', {
      'book': identity.bookId,
      'spineIndex': identity.spineIndex,
      'href': identity.href,
      'chunks': parsed.chunks.length,
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'priority': priority.name,
    });
    _workCoordinator.markCommitting(identity);
    await _cache.writeSection(parsed, expectedGeneration: cacheGeneration);
    return parsed;
  }

  Future<void> prefetchAround(int spineIndex, {int before = 1, int after = 1}) {
    final handle = _requireHandle();
    final futures = <Future<void>>[];
    for (var i = spineIndex - before; i <= spineIndex + after; i++) {
      if (i == spineIndex || i < 0 || i >= handle.index.spine.length) continue;
      futures.add(
        loadSectionWithPriority(
          i,
          priority: LazySectionWorkPriority.adjacentReadiness,
        ).then((_) {}),
      );
    }
    return Future.wait(futures).then((_) {});
  }

  Future<void> hydrateParsedSectionsAround({
    required int centerSpineIndex,
    bool Function()? shouldPause,
  }) async {
    final handle = _requireHandle();
    final epoch = _sessionEpoch;
    final readable = handle.index.spine
        .where((item) => item.isLinear)
        .map((item) => item.index)
        .toList(growable: false);
    final skipped = handle.index.spine
        .where((item) => !item.isLinear)
        .map((item) => item.index)
        .toList(growable: false);
    await _cache.ensureHydrationManifest(
      bookId: handle.index.bookId,
      publicationFingerprint: handle.index.publicationFingerprint,
      sourceChecksum: _bookSourceChecksum(handle.index),
      parserVersion: lazyParsedSectionParserVersion,
      dependencySignature: lazySectionDependencySignature(handle.index),
      readableSpineIndexes: readable,
      skippedSpineIndexes: skipped,
    );

    for (final spineIndex in _hydrationOrder(readable, centerSpineIndex)) {
      if (epoch != _sessionEpoch || !identical(_handle, handle)) return;
      if (!_cache.allowsPriority(
        LazySectionWorkPriority.parsedHydration.rank,
      )) {
        _lazySectionRepoDiagLog('prefetch_paused', {
          'book': handle.index.bookId,
          'spineIndex': spineIndex,
          'queuePriority': LazySectionWorkPriority.parsedHydration.name,
          'reason': 'storage_pressure',
        });
        return;
      }
      if (shouldPause?.call() ?? false) {
        _lazySectionRepoDiagLog('prefetch_paused', {
          'book': handle.index.bookId,
          'spineIndex': spineIndex,
          'queuePriority': LazySectionWorkPriority.parsedHydration.name,
          'reason': 'foreground_reader_work',
        });
        return;
      }
      final manifest = await _cache.loadManifest(handle.index.bookId);
      final hydration = manifest?.hydration;
      if (hydration != null &&
          hydration.completedSpineIndexes.contains(spineIndex)) {
        continue;
      }
      try {
        await loadSectionWithPriority(
          spineIndex,
          priority: LazySectionWorkPriority.parsedHydration,
        );
      } catch (error) {
        _lazySectionRepoDiagLog('hydration_section_failed', {
          'book': handle.index.bookId,
          'spineIndex': spineIndex,
          'reason': error.runtimeType,
        });
      }
    }
  }

  Future<void> close() async {
    _sessionEpoch++;
    _retained.clear();
    _retainedCosts.clear();
    _pinnedSpineIndices.clear();
    _workCoordinator.releaseOwner(_workOwner);
    _cache.clearActiveProtection(_workOwner);
    final handle = _handle;
    _handle = null;
    _dependencySignature = null;
    if (handle != null) {
      final work = _ownedSharedWork.toList(growable: false);
      if (work.isNotEmpty) {
        await Future.wait(
          work.map((future) => future.then<void>((_) {}, onError: (_, __) {})),
        );
      }
      await handle.close();
      await _cache.enforceBudget();
    }
  }

  bool _canRetainResult(LazyEpubBookHandle handle, int epoch) {
    return epoch == _sessionEpoch && identical(_handle, handle);
  }

  void _retain(ParsedSection section) {
    final spineIndex = section.identity.spineIndex;
    _retained.remove(spineIndex);
    _retainedCosts.remove(spineIndex);
    _retained[spineIndex] = section;
    _retainedCosts[spineIndex] = _estimateSectionBytes(section);
    _evictUntilWithinBudget();
  }

  void _evictUntilWithinBudget() {
    while (_shouldEvictRetained()) {
      final evictableKey = _retained.keys.cast<int?>().firstWhere(
        (spineIndex) =>
            spineIndex != null && !_pinnedSpineIndices.contains(spineIndex),
        orElse: () => null,
      );
      if (evictableKey == null) break;
      final evicted = _retained.remove(evictableKey);
      final evictedBytes = _retainedCosts.remove(evictableKey) ?? 0;
      _lazySectionRepoDiagLog('section_evicted_from_memory', {
        'book': evicted?.identity.bookId,
        'spineIndex': evicted?.identity.spineIndex,
        'href': evicted?.identity.href,
        'retained': _retained.length,
        'estimatedBytes': evictedBytes,
        'retainedBytes': retainedEstimatedBytes,
        'budgetBytes': _retainedSectionByteBudget,
        'reason': retainedEstimatedBytes > _retainedSectionByteBudget
            ? 'byte_budget'
            : 'section_limit',
      });
    }
  }

  bool _shouldEvictRetained() {
    return _retained.length > _retainedSectionLimit ||
        retainedEstimatedBytes > _retainedSectionByteBudget;
  }

  int _estimateSectionBytes(ParsedSection section) {
    var bytes = 1024;
    bytes += section.textCharCount * 2;
    bytes += section.anchorMap.length * 96;
    bytes += section.chapters.length * 192;
    for (final chunk in section.chunks) {
      bytes += 96;
      bytes += (chunk.text?.length ?? 0) * 2;
      bytes += chunk.imageBytes?.length ?? 0;
      bytes += (chunk.links?.length ?? 0) * 48;
      bytes += (chunk.inlineStyles?.length ?? 0) * 24;
      bytes += (chunk.footnotes?.length ?? 0) * 96;
    }
    return bytes;
  }

  LazyEpubBookHandle _requireHandle() {
    final handle = _handle;
    if (handle == null) {
      throw StateError('LazySectionRepository.open must be called first.');
    }
    return handle;
  }

  LazySectionIdentity _identityFor(LazyEpubIndex index, int spineIndex) {
    final item = index.spine[spineIndex];
    return LazySectionIdentity.fromIndexItem(
      bookId: index.bookId,
      publicationFingerprint: index.publicationFingerprint,
      item: item,
      sourceChecksum: item.sourceChecksum,
      dependencySignature:
          _dependencySignature ?? lazySectionDependencySignature(index),
    );
  }

  void _updateDiskProtection() {
    final handle = _handle;
    if (handle == null) return;
    _cache.setActiveProtection(
      owner: _workOwner,
      bookId: handle.index.bookId,
      publicationFingerprint: handle.index.publicationFingerprint,
      nearbySections: _pinnedSpineIndices
          .where((index) => index >= 0 && index < handle.index.spine.length)
          .map((index) => _identityFor(handle.index, index)),
    );
  }
}

String _bookSourceChecksum(LazyEpubIndex index) {
  final signature = index.spine
      .map((item) => '${item.index}:${item.href}:${item.sourceChecksum}')
      .join('|');
  return fnv1aHex(Uint8List.fromList(utf8.encode(signature)));
}

List<int> _hydrationOrder(List<int> readable, int centerSpineIndex) {
  final remaining = readable.toSet();
  final ordered = <int>[];
  var radius = 0;
  while (remaining.isNotEmpty) {
    final candidates = radius == 0
        ? <int>[centerSpineIndex]
        : <int>[centerSpineIndex - radius, centerSpineIndex + radius];
    for (final candidate in candidates) {
      if (remaining.remove(candidate)) ordered.add(candidate);
    }
    radius++;
    if (radius > readable.length + centerSpineIndex + 1) {
      ordered.addAll(remaining.toList()..sort());
      break;
    }
  }
  return ordered;
}

Future<ParsedSection> _defaultLazySectionParser(
  LazySectionParseRequest request,
) {
  return compute(_parseSectionPayload, (
    identity: request.identity,
    html: request.html,
    section: request.section,
    resourceBytes: request.resourceBytes,
    resourceMediaTypes: request.resourceMediaTypes,
    footnoteContentById: request.footnoteContentById,
  ));
}

ParsedSection _parseSectionPayload(
  ({
    LazySectionIdentity identity,
    String html,
    ChunkSection section,
    Map<String, Uint8List> resourceBytes,
    Map<String, String> resourceMediaTypes,
    Map<String, String> footnoteContentById,
  })
  payload,
) {
  return EpubParserService().parseLazySection(
    identity: payload.identity,
    html: payload.html,
    section: payload.section,
    resourceBytes: payload.resourceBytes,
    resourceMediaTypes: payload.resourceMediaTypes,
    footnoteContentById: payload.footnoteContentById,
  );
}

({Map<String, Uint8List> bytes, Map<String, String> mediaTypes})
_emptyResourcePayload() =>
    (bytes: <String, Uint8List>{}, mediaTypes: <String, String>{});

Future<({Map<String, Uint8List> bytes, Map<String, String> mediaTypes})>
_readSectionImageResources(
  LazyEpubBookHandle handle,
  String sectionHref,
  String html,
) async {
  final refs = EpubParserService.extractSectionResourceHrefs(html);
  if (refs.isEmpty) return _emptyResourcePayload();

  final bytes = <String, Uint8List>{};
  final mediaTypes = <String, String>{};
  for (final ref in refs) {
    final manifestItem = _resolveManifestResource(
      handle.index,
      ref,
      relativeToHref: sectionHref,
    );
    if (manifestItem == null ||
        !manifestItem.mediaType.toLowerCase().startsWith('image/')) {
      continue;
    }
    if (bytes.containsKey(manifestItem.href)) continue;
    try {
      final resource = await handle.readResource(manifestItem.href);
      bytes[manifestItem.href] = resource.bytes;
      mediaTypes[manifestItem.href] = resource.mediaType;
    } catch (error) {
      _lazySectionRepoDiagLog('lazy_resource_load_failed', {
        'book': handle.index.bookId,
        'section': sectionHref,
        'resource': manifestItem.href,
        'reason': error.runtimeType,
      });
    }
  }
  return (bytes: bytes, mediaTypes: mediaTypes);
}

Future<Map<String, String>> _readLinkedFootnotes(
  LazyEpubBookHandle handle,
  String sectionHref,
  String html,
) async {
  final refs = EpubParserService.extractSectionResourceHrefs(html);
  if (refs.isEmpty) return const {};

  final content = <String, String>{};
  final loadedTargets = <String>{};
  for (final ref in refs) {
    final fragment = _fragmentFromHref(ref);
    if (fragment == null || !_isFootnoteAnchor(fragment)) continue;

    final manifestItem = _resolveManifestResource(
      handle.index,
      ref,
      relativeToHref: sectionHref,
    );
    if (manifestItem == null ||
        manifestItem.href == sectionHref ||
        !manifestItem.mediaType.toLowerCase().contains('xhtml')) {
      continue;
    }
    final currentOrder = _manifestOrder(handle.index, sectionHref);
    final targetOrder = _manifestOrder(handle.index, manifestItem.href);
    if (currentOrder != null &&
        targetOrder != null &&
        targetOrder > currentOrder) {
      continue;
    }
    if (!loadedTargets.add(manifestItem.href)) continue;

    try {
      final resource = await handle.readResource(manifestItem.href);
      final targetHtml = utf8.decode(resource.bytes, allowMalformed: true);
      content.addAll(EpubParserService.extractFootnoteContentById(targetHtml));
    } catch (error) {
      _lazySectionRepoDiagLog('lazy_footnote_load_failed', {
        'book': handle.index.bookId,
        'section': sectionHref,
        'resource': manifestItem.href,
        'reason': error.runtimeType,
      });
    }
  }
  return content;
}

int? _manifestOrder(LazyEpubIndex index, String href) {
  var order = 0;
  for (final item in index.manifest.values) {
    if (item.href == href || item.fullPath == href) return order;
    order++;
  }
  return null;
}

LazyEpubManifestItem? _resolveManifestResource(
  LazyEpubIndex index,
  String href, {
  required String relativeToHref,
}) {
  final cleaned = _cleanResourceHref(href);
  if (cleaned == null) return null;
  final candidates = <String>[
    cleaned,
    p.posix.normalize(cleaned),
    p.posix.normalize(p.posix.join(p.posix.dirname(relativeToHref), cleaned)),
  ];
  for (final candidate in candidates) {
    final item =
        index.manifest[candidate] ??
        index.manifest.values
            .where((entry) => entry.fullPath == candidate)
            .firstOrNull;
    if (item != null) return item;
  }
  return null;
}

String? _cleanResourceHref(String href) {
  final trimmed = href.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('#') ||
      trimmed.startsWith('data:') ||
      trimmed.startsWith('http://') ||
      trimmed.startsWith('https://') ||
      trimmed.startsWith('mailto:')) {
    return null;
  }
  final withoutFragment = trimmed.split('#').first.split('?').first;
  if (withoutFragment.isEmpty) return null;
  try {
    return Uri.decodeFull(withoutFragment);
  } catch (_) {
    return withoutFragment;
  }
}

String? _fragmentFromHref(String href) {
  final index = href.indexOf('#');
  if (index < 0 || index == href.length - 1) return null;
  final fragment = href.substring(index + 1).trim();
  if (fragment.isEmpty) return null;
  try {
    return Uri.decodeFull(fragment);
  } catch (_) {
    return fragment;
  }
}

bool _isFootnoteAnchor(String anchor) {
  return anchor.startsWith('fn') ||
      anchor.startsWith('note') ||
      anchor.startsWith('footnote') ||
      anchor.startsWith('endnote');
}

ChunkSection _sectionKindFor(LazyEpubIndex index, int spineIndex) {
  final firstContent = _firstContentSpineIndex(index);
  final href = index.spine[spineIndex].href;
  if (firstContent != null && spineIndex < firstContent) {
    return ChunkSection.frontMatter;
  }
  return _isFrontMatterHref(href)
      ? ChunkSection.frontMatter
      : ChunkSection.content;
}

int? _firstContentSpineIndex(LazyEpubIndex index) {
  for (final chapter in _flattenChapters(index.chapters)) {
    if (_isFrontMatterTitle(chapter.title)) continue;
    final target = _spineIndexForHref(index, chapter.contentFileName);
    if (target != null) return target;
  }
  for (final item in index.spine) {
    if (item.isLinear && !_isFrontMatterHref(item.href)) {
      return item.index;
    }
  }
  return index.spine.isEmpty ? null : index.spine.first.index;
}

Iterable<LazyEpubChapter> _flattenChapters(
  List<LazyEpubChapter> chapters,
) sync* {
  for (final chapter in chapters) {
    yield chapter;
    yield* _flattenChapters(chapter.children);
  }
}

int? _spineIndexForHref(LazyEpubIndex index, String href) {
  final normalized = _cleanResourceHref(href);
  if (normalized == null) return null;
  final basename = p.posix.basename(normalized);
  for (final item in index.spine) {
    if (item.href == normalized ||
        item.fullPath == normalized ||
        p.posix.basename(item.href) == basename) {
      return item.index;
    }
  }
  return null;
}

bool _isFrontMatterTitle(String title) {
  final normalized = title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return false;
  const frontMatterTitles = {
    'about the author',
    'acknowledgements',
    'acknowledgments',
    'also by',
    'author note',
    'authors note',
    'bibliography',
    'contents',
    'copyright',
    'cover',
    'dedication',
    'epigraph',
    'foreword',
    'front matter',
    'imprint',
    'introduction',
    'preface',
    'prologue',
    'table of contents',
    'title page',
  };
  return frontMatterTitles.contains(normalized) ||
      normalized.startsWith('about ') ||
      normalized.startsWith('copyright ') ||
      normalized.startsWith('contents ');
}

bool _isFrontMatterHref(String href) {
  final lower = href.toLowerCase();
  const markers = [
    'cover',
    'title',
    'titlepage',
    'copyright',
    'rights',
    'dedication',
    'epigraph',
    'foreword',
    'preface',
    'prologue',
    'acknowledgment',
    'acknowledgement',
    'toc',
    'contents',
    'nav',
    'half-title',
    'halftitle',
    'frontispiece',
    'colophon',
    'imprint',
  ];
  return markers.any(lower.contains);
}
