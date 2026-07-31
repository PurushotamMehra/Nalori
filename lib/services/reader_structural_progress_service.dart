import '../models/book_metadata.dart';
import '../models/stable_book_location.dart';

class ReaderGlobalProgress {
  const ReaderGlobalProgress({
    required this.label,
    required this.progress,
    required this.isExact,
  });

  final String label;
  final double? progress;
  final bool isExact;
}

class ReaderPositionRevisionClock {
  ReaderPositionRevisionClock({int Function()? clock})
    : _clock = clock ?? (() => DateTime.now().microsecondsSinceEpoch);

  final int Function() _clock;
  int _last = 0;

  int next() {
    final now = _clock();
    _last = now > _last ? now : _last + 1;
    return _last;
  }
}

class ReaderCommittedPosition {
  const ReaderCommittedPosition({
    required this.revision,
    required this.displayIndex,
    required this.originalIndex,
    required this.location,
  });

  final int revision;
  final int displayIndex;
  final int originalIndex;
  final StableBookLocation? location;
}

class ReaderPositionPersistenceQueue {
  ReaderCommittedPosition? _pending;

  ReaderCommittedPosition? get pending => _pending;

  void stage(ReaderCommittedPosition? position) {
    if (position == null) return;
    final pending = _pending;
    if (pending == null || position.revision > pending.revision) {
      _pending = position;
    }
  }

  ReaderCommittedPosition? takeLatest() {
    final latest = _pending;
    _pending = null;
    return latest;
  }

  void clear() => _pending = null;
}

/// Structural evidence carried by the currently published card's source
/// range. The start remains the ordinary reading anchor; [endLocation] and
/// the explicit completeness flags are used only to prove a real chapter or
/// publication boundary.
class ReaderPublishedCardBoundaryEvidence {
  const ReaderPublishedCardBoundaryEvidence({
    required this.startLocation,
    required this.endLocation,
    required this.reachesEndOfSourceChunk,
    required this.reachesEndOfResolvedSection,
    required this.resolvedSectionComplete,
    required this.nextReadableSpineIndex,
  });

  final StableBookLocation startLocation;
  final StableBookLocation endLocation;
  final bool reachesEndOfSourceChunk;
  final bool reachesEndOfResolvedSection;
  final bool resolvedSectionComplete;
  final int? nextReadableSpineIndex;

  bool get provesPublicationEnd =>
      resolvedSectionComplete &&
      reachesEndOfResolvedSection &&
      nextReadableSpineIndex == null;

  bool reachesChapterBoundary(StableBookLocation? nextChapterStart) {
    if (nextChapterStart == null) return provesPublicationEnd;

    final endSpine = endLocation.spineIndex;
    final boundarySpine = nextChapterStart.spineIndex;
    if (endSpine > boundarySpine) return true;
    if (endSpine < boundarySpine) {
      return resolvedSectionComplete &&
          reachesEndOfResolvedSection &&
          nextReadableSpineIndex == boundarySpine;
    }

    final endLocal = endLocation.localChunkIndex;
    final boundaryLocal = nextChapterStart.localChunkIndex;
    if (endLocal == null || boundaryLocal == null) return false;
    if (endLocal > boundaryLocal) return true;
    if (endLocal < boundaryLocal) {
      return reachesEndOfSourceChunk && endLocal + 1 == boundaryLocal;
    }
    return endLocation.textOffset >= nextChapterStart.textOffset;
  }

  StableBookLocation locationForCommittedProgress() {
    if (!provesPublicationEnd) return startLocation;
    return endLocation.copyWith(
      sectionProgression: 1.0,
      publicationProgression: 1.0,
    );
  }
}

/// Commit-on-release policy for the lazy structural scrubber. Drag updates are
/// preview-only; a drag sequence can yield at most one navigation target.
class ReaderStructuralScrubCommitPolicy {
  bool _dragging = false;
  double? _preview;

  double? get preview => _preview;

  void begin(double progression) {
    _dragging = true;
    _preview = progression.clamp(0.0, 1.0).toDouble();
  }

  void update(double progression) {
    if (!_dragging) return;
    _preview = progression.clamp(0.0, 1.0).toDouble();
  }

  double? commit(double progression) {
    if (!_dragging) return null;
    _dragging = false;
    _preview = null;
    return progression.clamp(0.0, 1.0).toDouble();
  }

  void cancel() {
    _dragging = false;
    _preview = null;
  }
}

/// Resolves publication progress without interpreting a lazy display window as
/// the complete book. Lazy progress comes from the Phase 2 weighted structural
/// index refined by the current stable source position.
class ReaderStructuralProgressService {
  const ReaderStructuralProgressService._();

  static StableBookLocation refineSourceOffset({
    required StableBookLocation base,
    required int sourceChunkCount,
    required int sourceTextLength,
    required int textOffset,
    required double publicationSectionStart,
    required double publicationSectionEnd,
  }) {
    final count = sourceChunkCount <= 0 ? 1 : sourceChunkCount;
    final local = (base.localChunkIndex ?? 0).clamp(0, count - 1);
    final offset = textOffset.clamp(0, sourceTextLength);
    final withinChunk = sourceTextLength <= 0 ? 0.0 : offset / sourceTextLength;
    final section = ((local + withinChunk) / count).clamp(0.0, 1.0).toDouble();
    final sectionSpan = publicationSectionEnd - publicationSectionStart;
    final publication = (publicationSectionStart + sectionSpan * section)
        .clamp(0.0, 1.0)
        .toDouble();
    return base.copyWith(
      textOffset: offset,
      sectionProgression: section,
      publicationProgression: publication,
    );
  }

  static ReaderGlobalProgress global({
    required StableBookLocation? location,
    required bool isLazyWindow,
    int displayIndex = 0,
    int displayChunkCount = 0,
    bool displayWindowComplete = false,
  }) {
    if (isLazyWindow) {
      final weighted = location?.publicationProgression;
      if (weighted != null && weighted.isFinite) {
        final progress = weighted.clamp(0.0, 1.0).toDouble();
        return ReaderGlobalProgress(
          label: '${(progress * 100).round()}%',
          progress: progress,
          isExact: false,
        );
      }
      return const ReaderGlobalProgress(
        label: 'Progress unknown',
        progress: null,
        isExact: false,
      );
    }

    if (!displayWindowComplete || displayChunkCount <= 0) {
      return const ReaderGlobalProgress(
        label: 'Preparing pages',
        progress: null,
        isExact: false,
      );
    }
    final current = (displayIndex + 1).clamp(1, displayChunkCount);
    final progress = current / displayChunkCount;
    return ReaderGlobalProgress(
      label: '${(progress * 100).round()}%',
      progress: progress,
      isExact: true,
    );
  }

  static BookMetadata metadataForCommittedLocation({
    required BookMetadata metadata,
    required StableBookLocation currentStableLocation,
    required int meaningfulReadAt,
    required int revision,
    int? legacyLastReadIndex,
    int? legacyTotalChunks,
  }) {
    return metadata.copyWith(
      lastReadIndex: legacyLastReadIndex ?? metadata.lastReadIndex,
      lastReadLocation: currentStableLocation,
      totalChunks: legacyTotalChunks ?? metadata.totalChunks,
      lastReadTime: meaningfulReadAt,
      lastReadRevision: revision,
      lastMeaningfulReadAt: meaningfulReadAt,
    );
  }
}
