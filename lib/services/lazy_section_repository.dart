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
  adjacentReadiness(1),
  boundaryPrefetch(2),
  recentRetention(3),
  parsedHydration(4),
  layoutPagination(5);

  const LazySectionWorkPriority(this.rank);

  final int rank;

  bool outranks(LazySectionWorkPriority other) => rank < other.rank;
}

final class LazySectionRepository {
  LazySectionRepository({
    LazyEpubIndexService? indexService,
    ParsedSectionCacheService? cache,
    int retainedSectionLimit = 3,
    int retainedSectionByteBudget = 6 * 1024 * 1024,
  }) : _indexService = indexService ?? LazyEpubIndexService(),
       _cache = cache ?? ParsedSectionCacheService(),
       _retainedSectionLimit = retainedSectionLimit,
       _retainedSectionByteBudget = retainedSectionByteBudget;

  final LazyEpubIndexService _indexService;
  final ParsedSectionCacheService _cache;
  final int _retainedSectionLimit;
  final int _retainedSectionByteBudget;
  final _retained = <int, ParsedSection>{};
  final _retainedCosts = <int, int>{};
  final _pinnedSpineIndices = <int>{};
  final _inFlight = <int, _LazySectionLoadTask>{};
  LazyEpubBookHandle? _handle;
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
  }

  Future<LazyEpubIndex> open(File file) async {
    await close();
    _sessionEpoch++;
    await _cache.cleanupTemporaryFiles();
    _handle = await _indexService.openBookIndex(file);
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
    if (pinDuringLoad) _pinnedSpineIndices.add(spineIndex);

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

    final active = _inFlight[spineIndex];
    if (active != null) {
      if (priority.outranks(active.priority)) {
        _lazySectionRepoDiagLog('hydration_task_preempted', {
          'book': handle.index.bookId,
          'spineIndex': spineIndex,
          'href': handle.index.spine[spineIndex].href,
          'fromPriority': active.priority.name,
          'toPriority': priority.name,
        });
        active.priority = priority;
      }
      _lazySectionRepoDiagLog('duplicate_section_request_joined', {
        'book': handle.index.bookId,
        'spineIndex': spineIndex,
        'href': handle.index.spine[spineIndex].href,
        'priority': priority.name,
      });
      return active.future;
    }

    _lazySectionRepoDiagLog('lazy_section_request', {
      'book': handle.index.bookId,
      'spineIndex': spineIndex,
      'href': handle.index.spine[spineIndex].href,
      'priority': priority.name,
    });

    final completer = Completer<ParsedSection>();
    final epoch = _sessionEpoch;
    final task = _LazySectionLoadTask(
      priority: priority,
      future: completer.future,
    );
    _inFlight[spineIndex] = task;
    unawaited(
      _loadSectionUnshared(handle, spineIndex, priority: priority, epoch: epoch)
          .then(completer.complete)
          .catchError(completer.completeError)
          .whenComplete(() {
            if (identical(_inFlight[spineIndex], task)) {
              _inFlight.remove(spineIndex);
            }
            if (pinDuringLoad && epoch == _sessionEpoch) {
              _pinnedSpineIndices.remove(spineIndex);
            }
          }),
    );
    return completer.future;
  }

  Future<ParsedSection> _loadSectionUnshared(
    LazyEpubBookHandle handle,
    int spineIndex, {
    required LazySectionWorkPriority priority,
    required int epoch,
  }) async {
    final spineItem = handle.index.spine[spineIndex];
    final identity = LazySectionIdentity.fromIndexItem(
      bookId: handle.index.bookId,
      item: spineItem,
      sourceChecksum: spineItem.sourceChecksum,
    );

    final cached = await _cache.loadSection(identity);
    if (cached != null) {
      if (_canRetainResult(handle, epoch)) _retain(cached);
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
    final parsed = await compute(_parseSectionPayload, (
      identity: identity,
      html: sectionResource.html,
      section: section,
      resourceBytes: resources.bytes,
      resourceMediaTypes: resources.mediaTypes,
      footnoteContentById: footnotes,
    ));
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
    await _cache.writeSection(parsed);
    if (_canRetainResult(handle, epoch)) _retain(parsed);
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
      sourceChecksum: _bookSourceChecksum(handle.index),
      parserVersion: lazyParsedSectionParserVersion,
      readableSpineIndexes: readable,
      skippedSpineIndexes: skipped,
    );

    for (final spineIndex in _hydrationOrder(readable, centerSpineIndex)) {
      if (epoch != _sessionEpoch || !identical(_handle, handle)) return;
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
    _inFlight.clear();
    final handle = _handle;
    _handle = null;
    if (handle != null) {
      await handle.close();
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
}

final class _LazySectionLoadTask {
  _LazySectionLoadTask({required this.priority, required this.future});

  LazySectionWorkPriority priority;
  final Future<ParsedSection> future;
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
