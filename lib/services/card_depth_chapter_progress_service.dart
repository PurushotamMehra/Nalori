import '../models/stable_book_location.dart';
import 'chapter_card_layout_service.dart';
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
    StableBookLocation? currentCardStartLocation,
    StableBookLocation? currentCardEndLocation,
    ChapterCardLayout? completeChapterLayout,
    bool currentCardReachesChapterBoundary = false,
    bool allowWindowExactFallback = true,
    List<({int chunkIndex, String title})> fallbackFlatChapters = const [],
  }) {
    if (displayChunkCount <= 0) {
      return _wholeWindowFallback(
        displayIndex,
        displayChunkCount,
        allowWindowExactFallback: allowWindowExactFallback,
      );
    }

    if (displayIndex < 0 || displayIndex >= displayToOriginal.length) {
      return _wholeWindowFallback(
        displayIndex,
        displayChunkCount,
        allowWindowExactFallback: allowWindowExactFallback,
      );
    }

    final currentLocation =
        currentCardStartLocation ??
        _firstLocationForDisplayIndex(
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
        allowWindowExactFallback: allowWindowExactFallback,
        currentLocation: currentCardEndLocation ?? currentLocation,
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
        allowWindowExactFallback: allowWindowExactFallback,
        currentLocation: currentCardEndLocation ?? currentLocation,
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
        currentCardEndLocation: currentCardEndLocation,
      );
    }

    final chapterDisplayIndexes = _displayIndexesInTargetRange(
      displayToOriginal: displayToOriginal,
      locationsByChunkIndex: locationsByChunkIndex,
      currentTarget: currentTarget,
      nextTarget: nextTarget,
    );
    final zeroBasedPage = chapterDisplayIndexes.indexOf(displayIndex);

    final completePage = completeChapterLayout?.pageNumberFor(currentLocation);
    if (completePage != null && completeChapterLayout!.totalCards > 0) {
      return CardDepthChapterPageMeta(
        title: _safeTitle(currentTarget.title),
        pageLabel: '$completePage / ${completeChapterLayout.totalCards}',
        progress: currentCardReachesChapterBoundary
            ? 1.0
            : _structuralChapterProgress(
                currentLocation: currentCardEndLocation ?? currentLocation,
                currentTarget: currentTarget,
                nextTarget: nextTarget,
                fallback: _safeApproximateProgress(
                  (currentCardEndLocation ?? currentLocation)
                      .sectionProgression,
                ),
              ),
        isExact: true,
      );
    }

    final hasExactEnd = nextTarget == null
        ? displayChunksComplete && allowWindowExactFallback
        : _isBoundaryUsable(currentTarget, nextTarget) &&
              _isTargetStartRendered(
                currentTarget,
                displayToOriginal,
                locationsByChunkIndex,
              ) &&
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
        progress: currentCardEndLocation == null
            ? _progressForKnownTotal(current, total)
            : (currentCardReachesChapterBoundary
                  ? 1.0
                  : _structuralChapterProgress(
                      currentLocation: currentCardEndLocation,
                      currentTarget: currentTarget,
                      nextTarget: nextTarget,
                      fallback: _safeApproximateProgress(
                        currentCardEndLocation.sectionProgression,
                      ),
                    )),
        isExact: true,
      );
    }

    // Lazy mode often knows the current chapter start before the next chapter
    // boundary has been parsed/rendered. In that state, do not use the loaded
    // window length as a fake chapter denominator. Keep the label inexact and
    // let the rail move provisionally across already-rendered chapter pages
    // while the reader prioritizes loading/rendering the canonical next chapter
    // boundary. The provisional rail is capped below 100% so it cannot imply
    // that the current loaded window is the full chapter.
    final current = zeroBasedPage >= 0 ? zeroBasedPage + 1 : 1;
    return CardDepthChapterPageMeta(
      title: _safeTitle(currentTarget.title),
      pageLabel: 'Page $current',
      progress: currentCardReachesChapterBoundary
          ? 1.0
          : _structuralChapterProgress(
              currentLocation: currentCardEndLocation ?? currentLocation,
              currentTarget: currentTarget,
              nextTarget: nextTarget,
              fallback: _safeApproximateProgress(
                (currentCardEndLocation ?? currentLocation).sectionProgression,
              ),
            ),
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

  static bool _isTargetStartRendered(
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
      if (location != null &&
          ChapterNavigationService.compareTargetToLocation(target, location) ==
              0) {
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
    StableBookLocation? currentCardEndLocation,
  }) {
    final indexes = _displayIndexesInTargetRange(
      displayToOriginal: displayToOriginal,
      locationsByChunkIndex: locationsByChunkIndex,
      currentTarget: currentTarget,
      nextTarget: nextTarget,
    );
    final page = indexes.indexOf(displayIndex);
    final currentLocation = _firstLocationForDisplayIndex(
      displayIndex,
      displayToOriginal,
      locationsByChunkIndex,
    );
    final progressLocation = currentCardEndLocation ?? currentLocation;
    return CardDepthChapterPageMeta(
      title: _safeTitle(title),
      pageLabel: 'Page ${page >= 0 ? page + 1 : 1}',
      progress: progressLocation == null
          ? 0
          : _structuralChapterProgress(
              currentLocation: progressLocation,
              currentTarget: currentTarget,
              nextTarget: nextTarget,
              fallback: _safeApproximateProgress(
                progressLocation.sectionProgression,
              ),
            ),
      isExact: false,
    );
  }

  static CardDepthChapterPageMeta _fallbackFromChunkIndexes({
    required int displayIndex,
    required int displayChunkCount,
    required List<List<int>> displayToOriginal,
    required List<({int chunkIndex, String title})> fallbackFlatChapters,
    required bool allowWindowExactFallback,
    StableBookLocation? currentLocation,
  }) {
    if (fallbackFlatChapters.isEmpty ||
        displayIndex < 0 ||
        displayIndex >= displayToOriginal.length) {
      return _wholeWindowFallback(
        displayIndex,
        displayChunkCount,
        allowWindowExactFallback: allowWindowExactFallback,
      );
    }

    final mappedOriginals = displayToOriginal[displayIndex];
    if (mappedOriginals.isEmpty) {
      return _wholeWindowFallback(
        displayIndex,
        displayChunkCount,
        allowWindowExactFallback: allowWindowExactFallback,
      );
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
      return _wholeWindowFallback(
        displayIndex,
        displayChunkCount,
        allowWindowExactFallback: allowWindowExactFallback,
      );
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
    if (allowWindowExactFallback) {
      return CardDepthChapterPageMeta(
        title: _safeTitle(chapter.title),
        pageLabel: '$current / $total',
        progress: _progressForKnownTotal(current, total),
        isExact: true,
      );
    }
    return CardDepthChapterPageMeta(
      title: _safeTitle(chapter.title),
      pageLabel: 'Page $current',
      progress: _safeApproximateProgress(currentLocation?.sectionProgression),
      isExact: false,
    );
  }

  static CardDepthChapterPageMeta _wholeWindowFallback(
    int displayIndex,
    int displayChunkCount, {
    required bool allowWindowExactFallback,
  }) {
    final total = displayChunkCount <= 0 ? 1 : displayChunkCount;
    final current = (displayIndex + 1).clamp(1, total);
    if (!allowWindowExactFallback) {
      return CardDepthChapterPageMeta(
        title: 'Current chapter',
        pageLabel: 'Page $current',
        progress: 0,
        isExact: false,
      );
    }
    return CardDepthChapterPageMeta(
      title: 'Current chapter',
      pageLabel: '$current / $total',
      progress: _progressForKnownTotal(current, total),
      isExact: true,
    );
  }

  static double _structuralChapterProgress({
    required StableBookLocation currentLocation,
    required ChapterNavigationTarget currentTarget,
    required ChapterNavigationTarget? nextTarget,
    required double fallback,
  }) {
    if (nextTarget == null) return fallback;
    final current = currentLocation.publicationProgression;
    final start = currentTarget.stableLocation.publicationProgression;
    final end = nextTarget.stableLocation.publicationProgression;
    if (current != null && start != null && end != null && end > start) {
      return ((current - start) / (end - start)).clamp(0.0, 0.98).toDouble();
    }

    if (currentLocation.spineIndex == currentTarget.spineIndex &&
        currentLocation.spineIndex == nextTarget.spineIndex) {
      final sectionCurrent = currentLocation.sectionProgression;
      final sectionStart = currentTarget.stableLocation.sectionProgression;
      final sectionEnd = nextTarget.stableLocation.sectionProgression;
      if (sectionCurrent != null &&
          sectionStart != null &&
          sectionEnd != null &&
          sectionEnd > sectionStart) {
        return ((sectionCurrent - sectionStart) / (sectionEnd - sectionStart))
            .clamp(0.0, 0.98)
            .toDouble();
      }
    }
    return fallback;
  }

  static double _progressForKnownTotal(int current, int total) {
    if (total <= 1) return 1;
    return ((current - 1) / (total - 1)).clamp(0.0, 1.0).toDouble();
  }

  static double _safeApproximateProgress(double? progress) {
    if (progress == null || !progress.isFinite) return 0;
    return progress.clamp(0.0, 0.98).toDouble();
  }

  static String _safeTitle(String title) {
    return title.trim().isEmpty ? 'Current chapter' : title;
  }
}
