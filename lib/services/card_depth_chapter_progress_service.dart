import '../models/stable_book_location.dart';
import 'chapter_navigation_service.dart';

class CardDepthChapterPageMeta {
  const CardDepthChapterPageMeta({
    required this.title,
    required this.pageLabel,
    required this.progress,
    required this.isExact,
  });

  final String title;
  final String pageLabel;
  final double progress;
  final bool isExact;
}

class CardDepthChapterProgressService {
  const CardDepthChapterProgressService._();

  static CardDepthChapterPageMeta calculate({
    required int displayIndex,
    required int displayChunkCount,
    required List<List<int>> displayToOriginal,
    required Map<int, StableBookLocation> locationsByChunkIndex,
    required List<ChapterNavigationTarget> chapterNavigationTargets,
    required bool displayChunksComplete,
    List<({int chunkIndex, String title})> fallbackFlatChapters = const [],
  }) {
    if (displayChunkCount <= 0) {
      return const CardDepthChapterPageMeta(
        title: 'Current chapter',
        pageLabel: '1 / 1',
        progress: 1,
        isExact: true,
      );
    }

    if (displayIndex < 0 || displayIndex >= displayToOriginal.length) {
      return _wholeWindowFallback(displayIndex, displayChunkCount);
    }

    final currentLocation = _firstLocationForDisplayIndex(
      displayIndex,
      displayToOriginal,
      locationsByChunkIndex,
    );
    final selectableTargets = chapterNavigationTargets
        .where((target) => target.isSelectable)
        .toList(growable: false);

    if (currentLocation == null || selectableTargets.isEmpty) {
      return _fallbackFromChunkIndexes(
        displayIndex: displayIndex,
        displayChunkCount: displayChunkCount,
        displayToOriginal: displayToOriginal,
        fallbackFlatChapters: fallbackFlatChapters,
      );
    }

    final currentTargetIndex = ChapterNavigationService.currentTargetIndex(
      selectableTargets,
      currentLocation,
    );
    if (currentTargetIndex < 0) {
      return _fallbackFromChunkIndexes(
        displayIndex: displayIndex,
        displayChunkCount: displayChunkCount,
        displayToOriginal: displayToOriginal,
        fallbackFlatChapters: fallbackFlatChapters,
      );
    }

    final currentTarget = selectableTargets[currentTargetIndex];
    final nextTarget = currentTargetIndex + 1 < selectableTargets.length
        ? selectableTargets[currentTargetIndex + 1]
        : null;

    if (!_hasUsableStartBoundary(currentTarget, currentLocation)) {
      return _inexactFromChapterStart(
        title: currentTarget.title,
        displayIndex: displayIndex,
        displayToOriginal: displayToOriginal,
        locationsByChunkIndex: locationsByChunkIndex,
        currentTarget: currentTarget,
        nextTarget: nextTarget,
      );
    }

    final chapterDisplayIndexes = _displayIndexesInTargetRange(
      displayToOriginal: displayToOriginal,
      locationsByChunkIndex: locationsByChunkIndex,
      currentTarget: currentTarget,
      nextTarget: nextTarget,
    );
    final zeroBasedPage = chapterDisplayIndexes.indexOf(displayIndex);

    final hasExactEnd = nextTarget == null
        ? displayChunksComplete
        : _isBoundaryUsable(currentTarget, nextTarget) &&
              _isTargetRendered(
                nextTarget,
                displayToOriginal,
                locationsByChunkIndex,
              );

    if (hasExactEnd && zeroBasedPage >= 0 && chapterDisplayIndexes.isNotEmpty) {
      final current = zeroBasedPage + 1;
      final total = chapterDisplayIndexes.length;
      return CardDepthChapterPageMeta(
        title: _safeTitle(currentTarget.title),
        pageLabel: '$current / $total',
        progress: _progressForKnownTotal(current, total),
        isExact: true,
      );
    }

    // Lazy mode often knows the current chapter start before the next chapter
    // boundary has been parsed/rendered. In that state, do not use the loaded
    // window length as a fake chapter denominator; show local page position and
    // keep the progress rail at the chapter-start baseline until exact bounds
    // are available.
    final current = zeroBasedPage >= 0 ? zeroBasedPage + 1 : 1;
    return CardDepthChapterPageMeta(
      title: _safeTitle(currentTarget.title),
      pageLabel: '$current / ?',
      progress: 0,
      isExact: false,
    );
  }

  static StableBookLocation? _firstLocationForDisplayIndex(
    int displayIndex,
    List<List<int>> displayToOriginal,
    Map<int, StableBookLocation> locationsByChunkIndex,
  ) {
    if (displayIndex < 0 || displayIndex >= displayToOriginal.length) {
      return null;
    }
    for (final original in displayToOriginal[displayIndex]) {
      final location = locationsByChunkIndex[original];
      if (location != null) return location;
    }
    return null;
  }

  static List<int> _displayIndexesInTargetRange({
    required List<List<int>> displayToOriginal,
    required Map<int, StableBookLocation> locationsByChunkIndex,
    required ChapterNavigationTarget currentTarget,
    required ChapterNavigationTarget? nextTarget,
  }) {
    final indexes = <int>[];
    for (var i = 0; i < displayToOriginal.length; i++) {
      final location = _firstLocationForDisplayIndex(
        i,
        displayToOriginal,
        locationsByChunkIndex,
      );
      if (location == null) continue;
      if (!_locationIsAtOrAfterTarget(currentTarget, location)) continue;
      if (nextTarget != null &&
          !_locationIsBeforeTarget(nextTarget, location)) {
        continue;
      }
      indexes.add(i);
    }
    return indexes;
  }

  static bool _isTargetRendered(
    ChapterNavigationTarget target,
    List<List<int>> displayToOriginal,
    Map<int, StableBookLocation> locationsByChunkIndex,
  ) {
    for (var i = 0; i < displayToOriginal.length; i++) {
      final location = _firstLocationForDisplayIndex(
        i,
        displayToOriginal,
        locationsByChunkIndex,
      );
      if (location != null && _locationIsAtOrAfterTarget(target, location)) {
        return true;
      }
    }
    return false;
  }

  static bool _hasUsableStartBoundary(
    ChapterNavigationTarget target,
    StableBookLocation currentLocation,
  ) {
    if (target.spineIndex != currentLocation.spineIndex) return true;
    return target.resolvedLocalChunkIndex != null ||
        target.resolvedSourceIndex != null ||
        target.stableLocation.localChunkIndex != null;
  }

  static bool _isBoundaryUsable(
    ChapterNavigationTarget currentTarget,
    ChapterNavigationTarget nextTarget,
  ) {
    if (currentTarget.spineIndex != nextTarget.spineIndex) return true;
    return nextTarget.resolvedLocalChunkIndex != null ||
        nextTarget.resolvedSourceIndex != null ||
        nextTarget.stableLocation.localChunkIndex != null;
  }

  static bool _locationIsAtOrAfterTarget(
    ChapterNavigationTarget target,
    StableBookLocation location,
  ) {
    return ChapterNavigationService.compareTargetToLocation(target, location) <=
        0;
  }

  static bool _locationIsBeforeTarget(
    ChapterNavigationTarget target,
    StableBookLocation location,
  ) {
    return ChapterNavigationService.compareTargetToLocation(target, location) >
        0;
  }

  static CardDepthChapterPageMeta _inexactFromChapterStart({
    required String title,
    required int displayIndex,
    required List<List<int>> displayToOriginal,
    required Map<int, StableBookLocation> locationsByChunkIndex,
    required ChapterNavigationTarget currentTarget,
    required ChapterNavigationTarget? nextTarget,
  }) {
    final indexes = _displayIndexesInTargetRange(
      displayToOriginal: displayToOriginal,
      locationsByChunkIndex: locationsByChunkIndex,
      currentTarget: currentTarget,
      nextTarget: nextTarget,
    );
    final page = indexes.indexOf(displayIndex);
    return CardDepthChapterPageMeta(
      title: _safeTitle(title),
      pageLabel: '${page >= 0 ? page + 1 : 1} / ?',
      progress: 0,
      isExact: false,
    );
  }

  static CardDepthChapterPageMeta _fallbackFromChunkIndexes({
    required int displayIndex,
    required int displayChunkCount,
    required List<List<int>> displayToOriginal,
    required List<({int chunkIndex, String title})> fallbackFlatChapters,
  }) {
    if (fallbackFlatChapters.isEmpty ||
        displayIndex < 0 ||
        displayIndex >= displayToOriginal.length) {
      return _wholeWindowFallback(displayIndex, displayChunkCount);
    }

    final mappedOriginals = displayToOriginal[displayIndex];
    if (mappedOriginals.isEmpty) {
      return _wholeWindowFallback(displayIndex, displayChunkCount);
    }
    final currentOriginal = mappedOriginals.first;

    var chapterIndex = -1;
    for (var i = 0; i < fallbackFlatChapters.length; i++) {
      if (fallbackFlatChapters[i].chunkIndex <= currentOriginal) {
        chapterIndex = i;
      } else {
        break;
      }
    }
    if (chapterIndex < 0) {
      return _wholeWindowFallback(displayIndex, displayChunkCount);
    }

    final chapter = fallbackFlatChapters[chapterIndex];
    final startOriginal = chapter.chunkIndex;
    final endOriginal = chapterIndex + 1 < fallbackFlatChapters.length
        ? fallbackFlatChapters[chapterIndex + 1].chunkIndex
        : 1 << 30;
    final chapterDisplayIndexes = <int>[];
    for (var i = 0; i < displayToOriginal.length; i++) {
      final inChapter = displayToOriginal[i].any(
        (original) => original >= startOriginal && original < endOriginal,
      );
      if (inChapter) chapterDisplayIndexes.add(i);
    }
    final zeroBasedPage = chapterDisplayIndexes.indexOf(displayIndex);
    final total = chapterDisplayIndexes.isEmpty
        ? 1
        : chapterDisplayIndexes.length;
    final current = zeroBasedPage >= 0 ? zeroBasedPage + 1 : 1;
    return CardDepthChapterPageMeta(
      title: _safeTitle(chapter.title),
      pageLabel: '$current / $total',
      progress: _progressForKnownTotal(current, total),
      isExact: true,
    );
  }

  static CardDepthChapterPageMeta _wholeWindowFallback(
    int displayIndex,
    int displayChunkCount,
  ) {
    final total = displayChunkCount <= 0 ? 1 : displayChunkCount;
    final current = (displayIndex + 1).clamp(1, total);
    return CardDepthChapterPageMeta(
      title: 'Current chapter',
      pageLabel: '$current / $total',
      progress: _progressForKnownTotal(current, total),
      isExact: true,
    );
  }

  static double _progressForKnownTotal(int current, int total) {
    if (total <= 1) return 1;
    return ((current - 1) / (total - 1)).clamp(0.0, 1.0).toDouble();
  }

  static String _safeTitle(String title) {
    return title.trim().isEmpty ? 'Current chapter' : title;
  }
}
