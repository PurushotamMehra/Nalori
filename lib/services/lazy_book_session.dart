import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import '../models/stable_book_location.dart';
import 'chapter_navigation_service.dart';
import 'lazy_epub_index_service.dart';
import 'lazy_parsed_book.dart';
import 'lazy_section_repository.dart';

final class LazyLoadedContentWindow {
  const LazyLoadedContentWindow({
    required this.sections,
    required this.chunks,
    required this.anchorMap,
    required this.chapters,
    required this.searchIndex,
    required this.locationsByChunkIndex,
    required this.hasContentBefore,
    required this.hasContentAfter,
  });

  final List<ParsedSection> sections;
  final List<BookChunk> chunks;
  final Map<String, int> anchorMap;
  final List<ChapterInfo> chapters;
  final Map<String, List<int>> searchIndex;
  final Map<int, StableBookLocation> locationsByChunkIndex;
  final bool hasContentBefore;
  final bool hasContentAfter;
}

enum StableLocationConfidence {
  exact,
  anchor,
  quote,
  progression,
  legacy,
  unresolved,
}

final class StableLocationResolution {
  const StableLocationResolution(this.location, this.confidence, this.reason);
  final StableBookLocation? location;
  final StableLocationConfidence confidence;
  final String reason;
}

final class LazyBookSession {
  LazyBookSession({LazySectionRepository? repository})
    : _repository = repository ?? LazySectionRepository();

  final LazySectionRepository _repository;
  final Map<int, ParsedSection> _loadedSections = {};
  LazyEpubIndex? _index;
  StableBookLocation? _currentLocation;

  LazyEpubIndex get index {
    final value = _index;
    if (value == null) {
      throw StateError('LazyBookSession.open must be called first.');
    }
    return value;
  }

  StableBookLocation? get currentLocation => _currentLocation;
  Iterable<int> get loadedSpineIndices => _loadedSections.keys;
  int get retainedSectionCount => _repository.retainedSectionCount;

  Future<LazyEpubIndex> open(File file) async {
    _loadedSections.clear();
    _currentLocation = null;
    _index = await _repository.open(file);
    return _index!;
  }

  StableBookLocation initialLocation({StableBookLocation? requested}) {
    if (requested != null && _isLocationCompatible(requested)) {
      return requested;
    }
    final firstChapter = _firstReadingChapter(index.chapters);
    if (firstChapter != null) {
      final location = resolveChapterTarget(firstChapter);
      if (location != null) return location;
    }
    final firstReadable = index.spine.firstWhere(
      (item) => item.isLinear && !_isFrontMatterHref(item.href),
      orElse: () => index.spine.first,
    );
    return StableBookLocation(
      bookId: index.bookId,
      spineIndex: firstReadable.index,
      href: firstReadable.href,
      sourceChecksum: firstReadable.sourceChecksum,
      publicationFingerprint: index.publicationFingerprint,
      normalizedHref: firstReadable.normalizedHref,
      sectionProgression: 0,
      publicationProgression: _weightedProgression(firstReadable, 0),
    );
  }

  Future<LazyLoadedContentWindow> loadAround(
    StableBookLocation location, {
    int before = 0,
    int after = 1,
  }) async {
    final resolution = await resolveStableLocation(location);
    final resolvedLocation = resolution.location;
    if (resolvedLocation == null) {
      throw StateError(
        'Stable location could not be resolved: ${resolution.reason}',
      );
    }
    _currentLocation = resolvedLocation;
    _releaseDistantSections();
    _updatePinnedSections(targetSpineIndex: resolvedLocation.spineIndex);
    await loadSection(resolvedLocation.spineIndex);
    final previousIndexes = <int>[];
    var previous = resolvedLocation.spineIndex;
    for (var i = 0; i < before; i++) {
      final resolved = previousReadableSpineIndex(previous);
      if (resolved == null) break;
      previousIndexes.add(resolved);
      previous = resolved;
    }
    final nextIndexes = <int>[];
    var next = resolvedLocation.spineIndex;
    for (var i = 0; i < after; i++) {
      final resolved = nextReadableSpineIndex(next);
      if (resolved == null) break;
      nextIndexes.add(resolved);
      next = resolved;
    }

    final currentSection = _loadedSections[resolvedLocation.spineIndex];
    final localChunkIndex = resolvedLocation.localChunkIndex ?? 0;
    final currentChunkCount = currentSection?.chunks.length ?? 0;
    final sectionProgress = currentChunkCount <= 1
        ? 0.0
        : localChunkIndex / (currentChunkCount - 1);
    final adjacentIndexes = sectionProgress >= 0.65
        ? <int>[...nextIndexes, ...previousIndexes]
        : <int>[...previousIndexes, ...nextIndexes];
    for (final spineIndex in adjacentIndexes) {
      await loadSection(spineIndex);
    }
    return loadedWindow(centerSpineIndex: resolvedLocation.spineIndex);
  }

  Future<StableLocationResolution> resolveStableLocation(
    StableBookLocation location,
  ) async {
    if (location.bookId != index.bookId) {
      return const StableLocationResolution(
        null,
        StableLocationConfidence.unresolved,
        'book_mismatch',
      );
    }
    if (location.publicationFingerprint != null &&
        location.publicationFingerprint != index.publicationFingerprint) {
      return const StableLocationResolution(
        null,
        StableLocationConfidence.unresolved,
        'publication_mismatch',
      );
    }
    var spineIndex = index.spineIndexForHref(
      location.normalizedHref ?? location.href,
    );
    if (spineIndex == null && location.sourceChecksum != 'unknown') {
      final checksumMatches = index.spine
          .where((item) => item.sourceChecksum == location.sourceChecksum)
          .toList(growable: false);
      if (checksumMatches.length == 1) {
        spineIndex = checksumMatches.single.index;
      }
    }
    if (spineIndex == null && location.publicationProgression != null) {
      spineIndex = _spineIndexForWeightedProgression(
        location.publicationProgression!,
      );
    }
    if (spineIndex == null &&
        location.publicationFingerprint == null &&
        location.spineIndex >= 0 &&
        location.spineIndex < index.spine.length) {
      spineIndex = location.spineIndex;
    }
    if (spineIndex == null) {
      return const StableLocationResolution(
        null,
        StableLocationConfidence.unresolved,
        'missing_spine',
      );
    }
    final item = index.spine[spineIndex];
    final section = await loadSection(spineIndex, preserveDistantTarget: true);
    int? local;
    var confidence = StableLocationConfidence.unresolved;
    var reason = 'unresolved';
    final stableSourceId = location.anchorId ?? location.internalSegmentId;
    final anchor = stableSourceId == null
        ? null
        : _anchorChunkIndex(section, stableSourceId);
    if (anchor != null) {
      local = anchor;
      confidence = StableLocationConfidence.anchor;
      reason = location.anchorId != null ? 'anchor' : 'stable_source_identity';
    } else if (_validLocalChunk(section, location.localChunkIndex) &&
        item.sourceChecksum == location.sourceChecksum &&
        location.sourceParserVersion == section.parserVersion) {
      local = location.localChunkIndex;
      confidence = StableLocationConfidence.exact;
      reason = location.textOffset > 0 ? 'source_offset' : 'exact_section';
    } else {
      final quote = _uniqueQuoteMatch(section, location);
      if (quote != null) {
        local = quote;
        confidence = StableLocationConfidence.quote;
        reason = 'unique_quote_context';
      } else if (location.sectionProgression != null &&
          section.chunks.isNotEmpty) {
        local = _localChunkForProgression(
          section,
          location.sectionProgression!,
        );
        confidence = StableLocationConfidence.progression;
        reason = 'section_progression';
      } else if (location.publicationProgression != null &&
          section.chunks.isNotEmpty) {
        local = _localChunkForProgression(
          section,
          _sectionProgressionForWeightedProgression(
            item,
            location.publicationProgression!,
          ),
        );
        confidence = StableLocationConfidence.progression;
        reason = 'weighted_publication_progression';
      } else if (_validLocalChunk(section, location.localChunkIndex) &&
          location.publicationFingerprint == null) {
        local = location.localChunkIndex;
        confidence = StableLocationConfidence.legacy;
        reason = 'legacy_local_index_hint';
      }
    }
    if (local == null) {
      return const StableLocationResolution(
        null,
        StableLocationConfidence.unresolved,
        'ambiguous_or_missing_local_target',
      );
    }
    final sectionProgression = section.chunks.length <= 1
        ? 0.0
        : local / (section.chunks.length - 1);
    return StableLocationResolution(
      StableBookLocation(
        bookId: index.bookId,
        spineIndex: item.index,
        href: item.href,
        sourceChecksum: item.sourceChecksum,
        publicationFingerprint: index.publicationFingerprint,
        normalizedHref: item.normalizedHref,
        internalSegmentId: location.internalSegmentId,
        anchorId: location.anchorId,
        localChunkIndex: local,
        textOffset: location.textOffset,
        contextBefore: location.contextBefore,
        contextText: location.contextText,
        contextAfter: location.contextAfter,
        legacyGlobalChunkIndex: location.legacyGlobalChunkIndex,
        localDisplayIndex: location.localDisplayIndex,
        readerLayoutFingerprint: location.readerLayoutFingerprint,
        previousSpineIndex: location.previousSpineIndex,
        nextSpineIndex: location.nextSpineIndex,
        sectionProgression: sectionProgression,
        publicationProgression: _weightedProgression(item, sectionProgression),
        sourceParserVersion: section.parserVersion,
      ),
      confidence,
      reason,
    );
  }

  StableBookLocation locationForWeightedProgression(
    double progression, {
    int? legacyGlobalChunkIndex,
  }) {
    final spineIndex = _spineIndexForWeightedProgression(progression);
    final item = index.spine[spineIndex];
    final sectionProgression = _sectionProgressionForWeightedProgression(
      item,
      progression,
    );
    return StableBookLocation(
      bookId: index.bookId,
      spineIndex: item.index,
      href: item.href,
      sourceChecksum: item.sourceChecksum,
      publicationFingerprint: index.publicationFingerprint,
      normalizedHref: item.normalizedHref,
      sectionProgression: sectionProgression,
      publicationProgression: progression.clamp(0.0, 1.0),
      legacyGlobalChunkIndex: legacyGlobalChunkIndex,
    );
  }

  Future<ParsedSection> loadSection(
    int spineIndex, {
    LazySectionWorkPriority priority =
        LazySectionWorkPriority.explicitNavigation,
    bool preserveDistantTarget = false,
  }) async {
    final existing = _loadedSections[spineIndex];
    if (existing != null) return existing;
    final section = await _repository.loadSectionWithPriority(
      spineIndex,
      priority: priority,
      pinDuringLoad: priority == LazySectionWorkPriority.explicitNavigation,
    );
    _loadedSections[spineIndex] = section;
    if (!preserveDistantTarget) _releaseDistantSections();
    _updatePinnedSections();
    return section;
  }

  Future<ParsedSection?> loadNextSection() async {
    final current = _currentLocation?.spineIndex;
    if (current == null) return null;
    final section = await loadNextReadableSectionAfter(current);
    if (section == null) return null;
    _currentLocation = StableBookLocation(
      bookId: section.identity.bookId,
      spineIndex: section.identity.spineIndex,
      href: section.identity.href,
      sourceChecksum: section.identity.sourceChecksum,
      publicationFingerprint: index.publicationFingerprint,
      normalizedHref: index.spine[section.identity.spineIndex].normalizedHref,
      sectionProgression: 0,
      publicationProgression: _weightedProgression(
        index.spine[section.identity.spineIndex],
        0,
      ),
    );
    _releaseDistantSections();
    _updatePinnedSections();
    return section;
  }

  Future<ParsedSection?> loadPreviousSection() async {
    final current = _currentLocation?.spineIndex;
    if (current == null) return null;
    final section = await loadPreviousReadableSectionBefore(current);
    if (section == null) return null;
    _currentLocation = StableBookLocation(
      bookId: section.identity.bookId,
      spineIndex: section.identity.spineIndex,
      href: section.identity.href,
      sourceChecksum: section.identity.sourceChecksum,
      publicationFingerprint: index.publicationFingerprint,
      normalizedHref: index.spine[section.identity.spineIndex].normalizedHref,
      sectionProgression: 0,
      publicationProgression: _weightedProgression(
        index.spine[section.identity.spineIndex],
        0,
      ),
    );
    _releaseDistantSections();
    _updatePinnedSections();
    return section;
  }

  int? previousReadableSpineIndex(int beforeSpineIndex) {
    for (var i = beforeSpineIndex - 1; i >= 0; i--) {
      if (index.spine[i].isLinear) return i;
    }
    return null;
  }

  int? nextReadableSpineIndex(int afterSpineIndex) {
    for (var i = afterSpineIndex + 1; i < index.spine.length; i++) {
      if (index.spine[i].isLinear) return i;
    }
    return null;
  }

  Future<ParsedSection?> loadPreviousReadableSectionBefore(
    int beforeSpineIndex, {
    LazySectionWorkPriority priority =
        LazySectionWorkPriority.explicitNavigation,
  }) async {
    var candidate = previousReadableSpineIndex(beforeSpineIndex);
    while (candidate != null) {
      final section = await loadSection(candidate, priority: priority);
      if (section.chunks.isNotEmpty) return section;
      candidate = previousReadableSpineIndex(candidate);
    }
    return null;
  }

  Future<ParsedSection?> loadNextReadableSectionAfter(
    int afterSpineIndex, {
    LazySectionWorkPriority priority =
        LazySectionWorkPriority.explicitNavigation,
  }) async {
    var candidate = nextReadableSpineIndex(afterSpineIndex);
    while (candidate != null) {
      final section = await loadSection(candidate, priority: priority);
      if (section.chunks.isNotEmpty) return section;
      candidate = nextReadableSpineIndex(candidate);
    }
    return null;
  }

  Future<void> prefetchAround(StableBookLocation location) async {
    await _repository.prefetchAround(location.spineIndex);
  }

  Future<void> hydrateParsedSectionsFromCurrent({
    bool Function()? shouldPause,
  }) async {
    final current = _currentLocation?.spineIndex;
    if (current == null) return;
    await _repository.hydrateParsedSectionsAround(
      centerSpineIndex: current,
      shouldPause: shouldPause,
    );
  }

  void recordMeaningfulRead(StableBookLocation location, int readAtMs) {
    if (location.bookId != index.bookId ||
        location.publicationFingerprint != index.publicationFingerprint) {
      return;
    }
    _repository.recordMeaningfulRead(location.spineIndex, readAtMs);
  }

  LazyLoadedContentWindow loadedWindow({int? centerSpineIndex}) {
    final center = centerSpineIndex ?? _currentLocation?.spineIndex ?? 0;
    final sections = _loadedSections.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final parsedSections = sections.map((entry) => entry.value).toList();
    final chunks = <BookChunk>[];
    final anchors = <String, int>{};
    final searchIndex = <String, List<int>>{};
    final locations = <int, StableBookLocation>{};
    var nextChunkIndex = 0;
    for (final section in parsedSections) {
      final sectionStart = nextChunkIndex;
      for (final entry in section.anchorMap.entries) {
        anchors[entry.key] = sectionStart + entry.value;
      }
      for (final chunk in section.chunks) {
        final reindexed = chunk.copyWith(index: nextChunkIndex);
        chunks.add(reindexed);
        locations[nextChunkIndex] = StableBookLocation(
          bookId: section.identity.bookId,
          spineIndex: section.identity.spineIndex,
          href: section.identity.href,
          sourceChecksum: section.identity.sourceChecksum,
          publicationFingerprint: index.publicationFingerprint,
          normalizedHref:
              index.spine[section.identity.spineIndex].normalizedHref,
          localChunkIndex: chunk.index,
          sectionProgression: section.chunks.length <= 1
              ? 0
              : chunk.index / (section.chunks.length - 1),
          publicationProgression: _weightedProgression(
            index.spine[section.identity.spineIndex],
            section.chunks.length <= 1
                ? 0
                : chunk.index / (section.chunks.length - 1),
          ),
          sourceParserVersion: section.parserVersion,
          contextText: chunk.text,
        );
        final text = chunk.text;
        if (text != null) {
          for (final word
              in text
                  .toLowerCase()
                  .split(RegExp(r'[^a-z0-9]+'))
                  .where((entry) => entry.isNotEmpty)) {
            searchIndex.putIfAbsent(word, () => <int>[]).add(nextChunkIndex);
          }
        }
        nextChunkIndex++;
      }
    }
    final minLoaded = sections.isEmpty ? center : sections.first.key;
    final maxLoaded = sections.isEmpty ? center : sections.last.key;
    return LazyLoadedContentWindow(
      sections: parsedSections,
      chunks: chunks,
      anchorMap: anchors,
      chapters: _chaptersForLoadedWindow(),
      searchIndex: searchIndex,
      locationsByChunkIndex: locations,
      hasContentBefore: previousReadableSpineIndex(minLoaded) != null,
      hasContentAfter: nextReadableSpineIndex(maxLoaded) != null,
    );
  }

  List<ChapterInfo> _chaptersForLoadedWindow() {
    var syntheticChunkIndex = 0;
    ChapterInfo convert(LazyEpubChapter chapter, int depth) {
      final location = resolveChapterTarget(chapter);
      final loadedChunkIndex = location == null
          ? 0
          : _loadedChunkIndexFor(location);
      final fallbackChunkIndex =
          loadedChunkIndex ??
          _syntheticChapterIndex(location, syntheticChunkIndex);
      syntheticChunkIndex++;
      return ChapterInfo(
        title: chapter.title,
        chunkIndex: fallbackChunkIndex,
        stableLocation: location,
        depth: depth,
        children: chapter.children
            .map((child) => convert(child, depth + 1))
            .toList(),
      );
    }

    return index.chapters.map((chapter) => convert(chapter, 0)).toList();
  }

  int? _loadedChunkIndexFor(StableBookLocation location) {
    final sections = _loadedSections.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    var offset = 0;
    for (final entry in sections) {
      final section = entry.value;
      if (entry.key == location.spineIndex) {
        return offset + (location.localChunkIndex ?? 0);
      }
      offset += section.chunks.length;
    }
    return null;
  }

  StableBookLocation? resolveChapterTarget(LazyEpubChapter chapter) {
    final href = chapter.contentFileName;
    if (href.isEmpty) return null;
    final chapterSpineIndex = chapter.spineIndex;
    final spineItem =
        chapterSpineIndex != null &&
            chapterSpineIndex >= 0 &&
            chapterSpineIndex < index.spine.length
        ? index.spine[chapterSpineIndex]
        : _spineItemForHref(href);
    if (spineItem == null) return null;
    return StableBookLocation(
      bookId: index.bookId,
      spineIndex: spineItem.index,
      href: spineItem.href,
      sourceChecksum: spineItem.sourceChecksum,
      publicationFingerprint: index.publicationFingerprint,
      normalizedHref: spineItem.normalizedHref,
      anchorId: chapter.anchor,
      sectionProgression: 0,
      publicationProgression: _weightedProgression(spineItem, 0),
    );
  }

  StableBookLocation? resolveAnchor(String href, String? fragment) {
    final spineItem = _spineItemForHref(href);
    if (spineItem == null) return null;
    return StableBookLocation(
      bookId: index.bookId,
      spineIndex: spineItem.index,
      href: spineItem.href,
      sourceChecksum: spineItem.sourceChecksum,
      publicationFingerprint: index.publicationFingerprint,
      normalizedHref: spineItem.normalizedHref,
      anchorId: fragment,
      sectionProgression: 0,
      publicationProgression: _weightedProgression(spineItem, 0),
    );
  }

  Future<void> close() async {
    _loadedSections.clear();
    _currentLocation = null;
    _index = null;
    _repository.pinSections(const []);
    await _repository.close();
  }

  bool _isLocationCompatible(StableBookLocation location) {
    if (location.bookId != index.bookId) return false;
    if (location.publicationFingerprint != null &&
        location.publicationFingerprint != index.publicationFingerprint) {
      return false;
    }
    if (location.spineIndex < 0 || location.spineIndex >= index.spine.length) {
      return false;
    }
    final spineItem = index.spine[location.spineIndex];
    return index.spineIndexForHref(location.normalizedHref ?? location.href) ==
            spineItem.index ||
        (location.sourceChecksum != 'unknown' &&
            spineItem.sourceChecksum == location.sourceChecksum);
  }

  bool _validLocalChunk(ParsedSection section, int? index) =>
      index != null && index >= 0 && index < section.chunks.length;

  int? _anchorChunkIndex(ParsedSection section, String anchor) {
    final decoded = Uri.decodeComponent(anchor);
    return section.anchorMap[anchor] ??
        section.anchorMap[decoded] ??
        section.anchorMap['#$anchor'] ??
        section.anchorMap['#$decoded'];
  }

  int? _uniqueQuoteMatch(ParsedSection section, StableBookLocation location) {
    final quote = location.contextText?.trim();
    if (quote == null || quote.isEmpty) return null;
    final matches = <int>[];
    for (var i = 0; i < section.chunks.length; i++) {
      final text = section.chunks[i].text ?? '';
      if (!text.contains(quote)) continue;
      final before = location.contextBefore?.trim();
      if (before != null && before.isNotEmpty) {
        final previous = i == 0 ? '' : section.chunks[i - 1].text ?? '';
        if (!previous.endsWith(before) && !text.contains(before)) continue;
      }
      final after = location.contextAfter?.trim();
      if (after != null && after.isNotEmpty) {
        final next = i + 1 >= section.chunks.length
            ? ''
            : section.chunks[i + 1].text ?? '';
        if (!next.startsWith(after) && !text.contains(after)) continue;
      }
      matches.add(i);
    }
    return matches.length == 1 ? matches.single : null;
  }

  int _localChunkForProgression(ParsedSection section, double progression) {
    if (section.chunks.length <= 1) return 0;
    return (progression.clamp(0.0, 1.0) * (section.chunks.length - 1)).round();
  }

  int _spineIndexForWeightedProgression(double progression) {
    final readable = index.spine.where((item) => item.isLinear).toList();
    if (readable.isEmpty) return 0;
    final total = index.totalReadableWeight;
    if (total <= 0) {
      final position = (progression.clamp(0.0, 1.0) * (readable.length - 1))
          .round();
      return readable[position].index;
    }
    final target = progression.clamp(0.0, 1.0) * total;
    for (final item in readable) {
      if (target < item.prefixWeight + item.structuralWeight) {
        return item.index;
      }
    }
    return readable.last.index;
  }

  double _sectionProgressionForWeightedProgression(
    LazyEpubSpineItem item,
    double progression,
  ) {
    if (item.structuralWeight <= 0 || index.totalReadableWeight <= 0) return 0;
    final target = progression.clamp(0.0, 1.0) * index.totalReadableWeight;
    return ((target - item.prefixWeight) / item.structuralWeight).clamp(
      0.0,
      1.0,
    );
  }

  double _weightedProgression(
    LazyEpubSpineItem item,
    double sectionProgression,
  ) {
    if (index.totalReadableWeight <= 0) return 0;
    return (item.prefixWeight +
            item.structuralWeight * sectionProgression.clamp(0.0, 1.0)) /
        index.totalReadableWeight;
  }

  LazyEpubSpineItem? _spineItemForHref(String href) {
    var mappedIndex = index.spineIndexForHref(href);
    if (mappedIndex == null && _currentLocation != null) {
      final baseHref =
          _currentLocation!.normalizedHref ?? _currentLocation!.href;
      final relative = p.posix.normalize(
        p.posix.join(p.posix.dirname(baseHref), href),
      );
      mappedIndex = index.spineIndexForHref(relative);
    }
    if (mappedIndex != null &&
        mappedIndex >= 0 &&
        mappedIndex < index.spine.length) {
      return index.spine[mappedIndex];
    }
    final normalized = href.split('#').first;
    for (final item in index.spine) {
      if (item.href == normalized || item.fullPath.endsWith(normalized)) {
        return item;
      }
    }
    return null;
  }

  int _syntheticChapterIndex(StableBookLocation? location, int order) {
    final spineIndex = location?.spineIndex ?? 0;
    return (spineIndex + 1) * 1000000 + order;
  }

  LazyEpubChapter? _firstReadingChapter(List<LazyEpubChapter> chapters) {
    return ChapterNavigationService.firstReadingEntry<LazyEpubChapter>(
      roots: chapters,
      titleOf: (chapter) => chapter.title,
      childrenOf: (chapter) => chapter.children,
    );
  }

  bool _isFrontMatterHref(String href) {
    return ChapterNavigationService.isFrontMatterHref(href);
  }

  void _releaseDistantSections() {
    final current = _currentLocation?.spineIndex;
    if (current == null) return;
    _loadedSections.removeWhere((spineIndex, _) {
      return (spineIndex - current).abs() > 1;
    });
  }

  void _updatePinnedSections({int? targetSpineIndex}) {
    final current = _currentLocation?.spineIndex;
    final pins = <int>{
      if (current != null) current,
      if (targetSpineIndex != null) targetSpineIndex,
      if (current != null) ...[
        if (previousReadableSpineIndex(current) case final previous?) previous,
        if (nextReadableSpineIndex(current) case final next?) next,
      ],
    };
    _repository.pinSections(pins);
  }
}
