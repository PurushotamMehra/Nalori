import 'dart:io';

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
    );
  }

  Future<LazyLoadedContentWindow> loadAround(
    StableBookLocation location, {
    int before = 0,
    int after = 1,
  }) async {
    _currentLocation = location;
    _updatePinnedSections(targetSpineIndex: location.spineIndex);
    await loadSection(location.spineIndex);
    final previousIndexes = <int>[];
    var previous = location.spineIndex;
    for (var i = 0; i < before; i++) {
      final resolved = previousReadableSpineIndex(previous);
      if (resolved == null) break;
      previousIndexes.add(resolved);
      previous = resolved;
    }
    final nextIndexes = <int>[];
    var next = location.spineIndex;
    for (var i = 0; i < after; i++) {
      final resolved = nextReadableSpineIndex(next);
      if (resolved == null) break;
      nextIndexes.add(resolved);
      next = resolved;
    }

    final currentSection = _loadedSections[location.spineIndex];
    final localChunkIndex = location.localChunkIndex ?? 0;
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
    return loadedWindow(centerSpineIndex: location.spineIndex);
  }

  Future<ParsedSection> loadSection(
    int spineIndex, {
    LazySectionWorkPriority priority =
        LazySectionWorkPriority.explicitNavigation,
  }) async {
    final existing = _loadedSections[spineIndex];
    if (existing != null) return existing;
    final section = await _repository.loadSectionWithPriority(
      spineIndex,
      priority: priority,
      pinDuringLoad: priority == LazySectionWorkPriority.explicitNavigation,
    );
    _loadedSections[spineIndex] = section;
    _releaseDistantSections();
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
          localChunkIndex: chunk.index,
          legacyGlobalChunkIndex: nextChunkIndex,
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
      anchorId: chapter.anchor,
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
      anchorId: fragment,
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
    if (location.spineIndex < 0 || location.spineIndex >= index.spine.length) {
      return false;
    }
    final spineItem = index.spine[location.spineIndex];
    return spineItem.href == location.href;
  }

  LazyEpubSpineItem? _spineItemForHref(String href) {
    final mappedIndex = index.spineIndexForHref(href);
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
