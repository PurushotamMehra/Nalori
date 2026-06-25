import 'package:path/path.dart' as p;

import '../models/bookmark.dart';
import '../models/stable_book_location.dart';

enum ChapterNavigationTargetType {
  chapter,
  part,
  section,
  frontMatter,
  appendix,
  unknown,
}

class ChapterNavigationTarget {
  const ChapterNavigationTarget({
    required this.chapter,
    required this.title,
    required this.normalizedTitle,
    required this.type,
    required this.depth,
    required this.href,
    required this.anchorId,
    required this.spineIndex,
    required this.resolvedSourceIndex,
    required this.resolvedLocalChunkIndex,
    required this.textOffset,
    required this.stableLocation,
    required this.isSelectable,
    required this.isStructuralParent,
    required this.duplicateGroupId,
    required this.tocOrder,
  });

  final ChapterInfo chapter;
  final String title;
  final String normalizedTitle;
  final ChapterNavigationTargetType type;
  final int depth;
  final String? href;
  final String? anchorId;
  final int spineIndex;
  final int? resolvedSourceIndex;
  final int? resolvedLocalChunkIndex;
  final int textOffset;
  final StableBookLocation stableLocation;
  final bool isSelectable;
  final bool isStructuralParent;
  final String duplicateGroupId;
  final int tocOrder;
}

class ChapterNavigationService {
  const ChapterNavigationService._();

  static List<ChapterNavigationTarget> buildTargets({
    required List<ChapterInfo> chapters,
    Map<String, int> anchorMap = const {},
    Map<int, StableBookLocation> locationsByChunkIndex = const {},
  }) {
    final entries = <_ChapterEntry>[];
    var order = 0;

    void walk(List<ChapterInfo> nodes) {
      for (final chapter in nodes) {
        entries.add(_ChapterEntry(chapter: chapter, tocOrder: order++));
        if (chapter.children.isNotEmpty) walk(chapter.children);
      }
    }

    walk(chapters);

    final targets = <ChapterNavigationTarget>[];
    for (final entry in entries) {
      final location = entry.chapter.stableLocation;
      if (location == null) continue;
      final normalizedTitle = normalizeTitle(entry.chapter.title);
      final type = classifyTitle(entry.chapter.title);
      final anchorIndex = _sourceIndexForAnchor(
        location: location,
        anchorMap: anchorMap,
      );
      final anchorLocation = anchorIndex == null
          ? null
          : locationsByChunkIndex[anchorIndex];
      final resolvedSourceIndex =
          anchorIndex ??
          _sourceIndexForLocation(
            location: location,
            locationsByChunkIndex: locationsByChunkIndex,
          );
      final resolvedLocalChunkIndex =
          anchorLocation?.localChunkIndex ?? location.localChunkIndex;
      final isStructuralParent = entry.chapter.children.isNotEmpty;
      final isSelectable = _isSelectable(type);
      final duplicateGroupId = _duplicateGroupId(location);
      targets.add(
        ChapterNavigationTarget(
          chapter: entry.chapter,
          title: entry.chapter.title,
          normalizedTitle: normalizedTitle,
          type: type,
          depth: entry.chapter.depth,
          href: location.href,
          anchorId: location.anchorId,
          spineIndex: location.spineIndex,
          resolvedSourceIndex: resolvedSourceIndex,
          resolvedLocalChunkIndex: resolvedLocalChunkIndex,
          textOffset: location.textOffset,
          stableLocation: resolvedLocalChunkIndex == null
              ? location
              : location.copyWith(localChunkIndex: resolvedLocalChunkIndex),
          isSelectable: isSelectable,
          isStructuralParent: isStructuralParent,
          duplicateGroupId: duplicateGroupId,
          tocOrder: entry.tocOrder,
        ),
      );
    }

    targets.sort(compareTargets);
    return _dedupeStructuralTargets(_dedupeExactTargets(targets));
  }

  static ChapterNavigationTarget? nextTarget(
    List<ChapterNavigationTarget> targets,
    StableBookLocation current,
  ) {
    for (final target in targets.where((target) => target.isSelectable)) {
      if (compareTargetToLocation(target, current) > 0) return target;
    }
    return null;
  }

  static ChapterNavigationTarget? previousTarget(
    List<ChapterNavigationTarget> targets,
    StableBookLocation current,
  ) {
    ChapterNavigationTarget? previous;
    for (final target in targets.where((target) => target.isSelectable)) {
      if (compareTargetToLocation(target, current) < 0) {
        previous = target;
        continue;
      }
      break;
    }
    return previous;
  }

  static int currentTargetIndex(
    List<ChapterNavigationTarget> targets,
    StableBookLocation current,
  ) {
    var currentIndex = -1;
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      if (!target.isSelectable) continue;
      if (compareTargetToLocation(target, current) <= 0) {
        currentIndex = i;
      } else {
        break;
      }
    }
    return currentIndex;
  }

  static ChapterNavigationTarget? currentTarget(
    List<ChapterNavigationTarget> targets,
    StableBookLocation current,
  ) {
    final index = currentTargetIndex(targets, current);
    return index < 0 ? null : targets[index];
  }

  static bool sameTarget(ChapterNavigationTarget target, ChapterInfo chapter) {
    return identical(target.chapter, chapter) ||
        (target.title == chapter.title &&
            target.depth == chapter.depth &&
            target.chapter.chunkIndex == chapter.chunkIndex &&
            target.chapter.stableLocation == chapter.stableLocation);
  }

  static int compareTargets(
    ChapterNavigationTarget a,
    ChapterNavigationTarget b,
  ) {
    final spine = a.spineIndex.compareTo(b.spineIndex);
    if (spine != 0) return spine;
    final local = _compareNullableInts(
      a.resolvedLocalChunkIndex,
      b.resolvedLocalChunkIndex,
    );
    if (local != 0) return local;
    final source = _compareNullableInts(
      a.resolvedSourceIndex,
      b.resolvedSourceIndex,
    );
    if (source != 0) return source;
    final offset = a.textOffset.compareTo(b.textOffset);
    if (offset != 0) return offset;
    final order = a.tocOrder.compareTo(b.tocOrder);
    if (order != 0) return order;
    final anchor = (a.anchorId ?? '').compareTo(b.anchorId ?? '');
    if (anchor != 0) return anchor;
    return 0;
  }

  static int compareTargetToLocation(
    ChapterNavigationTarget target,
    StableBookLocation location,
  ) {
    final spine = target.spineIndex.compareTo(location.spineIndex);
    if (spine != 0) return spine;
    final targetLocal = target.resolvedLocalChunkIndex;
    final currentLocal = location.localChunkIndex;
    if (targetLocal != null && currentLocal != null) {
      final local = targetLocal.compareTo(currentLocal);
      if (local != 0) return local;
    } else if (target.resolvedSourceIndex != null &&
        location.legacyGlobalChunkIndex != null) {
      final source = target.resolvedSourceIndex!.compareTo(
        location.legacyGlobalChunkIndex!,
      );
      if (source != 0) return source;
    } else if (targetLocal != null || currentLocal != null) {
      return targetLocal == null ? -1 : 1;
    }
    final offset = target.textOffset.compareTo(location.textOffset);
    if (offset != 0) return offset;
    if (location.anchorId != null && location.anchorId!.isNotEmpty) {
      final anchor = (target.anchorId ?? '').compareTo(location.anchorId!);
      if (anchor != 0) return anchor;
    }
    return 0;
  }

  static String normalizeTitle(String title) {
    return title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool isChapterOneLikeTitle(String title) {
    final normalized = normalizeTitle(title);
    if (normalized.isEmpty) return false;
    return RegExp(
      r'^(chapter\s+)?(1|one|i)(\s*[:.\-].*)?$',
    ).hasMatch(normalized);
  }

  static bool isFrontMatterTitle(String title) {
    return classifyTitle(title) == ChapterNavigationTargetType.frontMatter;
  }

  static ChapterNavigationTargetType classifyTitle(String title) {
    final normalized = normalizeTitle(title);
    if (normalized.isEmpty) return ChapterNavigationTargetType.unknown;
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
    if (frontMatterTitles.contains(normalized) ||
        normalized.startsWith('about ') ||
        normalized.startsWith('copyright ') ||
        normalized.startsWith('contents ')) {
      return ChapterNavigationTargetType.frontMatter;
    }
    if (normalized.startsWith('appendix') ||
        normalized == 'notes' ||
        normalized == 'endnotes' ||
        normalized == 'glossary' ||
        normalized == 'index') {
      return ChapterNavigationTargetType.appendix;
    }
    if (normalized.startsWith('chapter ') ||
        RegExp(
          r'^(chapter\s+)?([0-9]+|[ivxlcdm]+|one|two|three|four|five|six|seven|eight|nine|ten)(\s*[:.\-].*)?$',
        ).hasMatch(normalized)) {
      return ChapterNavigationTargetType.chapter;
    }
    if (normalized.startsWith('part ')) {
      return ChapterNavigationTargetType.part;
    }
    if (normalized.startsWith('section ') || normalized.startsWith('book ')) {
      return ChapterNavigationTargetType.section;
    }
    return ChapterNavigationTargetType.unknown;
  }

  static bool isFrontMatterHref(String href) {
    final lower = href.toLowerCase();
    const markers = [
      'cover',
      'title',
      'copyright',
      'contents',
      'toc',
      'dedication',
      'imprint',
      'preface',
      'introduction',
      'foreword',
      'acknowledgement',
      'acknowledgment',
    ];
    return markers.any(lower.contains);
  }

  static List<T> flatten<T>(
    List<T> roots,
    List<T> Function(T entry) childrenOf,
  ) {
    final result = <T>[];
    void walk(List<T> nodes) {
      for (final node in nodes) {
        result.add(node);
        walk(childrenOf(node));
      }
    }

    walk(roots);
    return result;
  }

  static T? firstReadingEntry<T>({
    required List<T> roots,
    required String Function(T entry) titleOf,
    required List<T> Function(T entry) childrenOf,
  }) {
    T? firstBodyLeaf;
    T? firstBodyEntry;

    T? walk(List<T> entries) {
      for (final entry in entries) {
        final title = titleOf(entry);
        if (isChapterOneLikeTitle(title)) return entry;
        final children = childrenOf(entry);
        final childMatch = walk(children);
        if (childMatch != null) return childMatch;
        if (!isFrontMatterTitle(title)) {
          firstBodyEntry ??= entry;
          if (children.isEmpty) firstBodyLeaf ??= entry;
        }
      }
      return null;
    }

    return walk(roots) ?? firstBodyLeaf ?? firstBodyEntry;
  }

  static int? _sourceIndexForAnchor({
    required StableBookLocation location,
    required Map<String, int> anchorMap,
  }) {
    final anchorId = location.anchorId;
    if (anchorId == null || anchorId.isEmpty) return null;
    final decoded = Uri.decodeComponent(anchorId);
    final candidates = <String>[
      anchorId,
      decoded,
      '${location.href}#$anchorId',
      '${location.href}#$decoded',
      '${p.basename(location.href)}#$anchorId',
      '${p.basename(location.href)}#$decoded',
    ];
    for (final candidate in candidates) {
      final index = anchorMap[candidate];
      if (index != null) return index;
    }
    return null;
  }

  static int? _sourceIndexForLocation({
    required StableBookLocation location,
    required Map<int, StableBookLocation> locationsByChunkIndex,
  }) {
    for (final entry in locationsByChunkIndex.entries) {
      final other = entry.value;
      if (other.spineIndex == location.spineIndex &&
          (location.localChunkIndex == null ||
              other.localChunkIndex == location.localChunkIndex)) {
        return entry.key;
      }
    }
    return null;
  }

  static bool _isSelectable(ChapterNavigationTargetType type) {
    if (type == ChapterNavigationTargetType.frontMatter ||
        type == ChapterNavigationTargetType.appendix) {
      return false;
    }
    return true;
  }

  static String _duplicateGroupId(StableBookLocation location) {
    final anchor = location.anchorId ?? '';
    final local = location.localChunkIndex?.toString() ?? '';
    return '${location.spineIndex}|${location.href}|$anchor|$local|${location.textOffset}';
  }

  static List<ChapterNavigationTarget> _dedupeExactTargets(
    List<ChapterNavigationTarget> targets,
  ) {
    final byGroup = <String, ChapterNavigationTarget>{};
    final result = <ChapterNavigationTarget>[];
    for (final target in targets) {
      final existing = byGroup[target.duplicateGroupId];
      if (existing == null) {
        byGroup[target.duplicateGroupId] = target;
        result.add(target);
        continue;
      }
      if (existing.isStructuralParent && !target.isStructuralParent) {
        final index = result.indexOf(existing);
        if (index >= 0) result[index] = target;
        byGroup[target.duplicateGroupId] = target;
      }
    }
    return result;
  }

  static List<ChapterNavigationTarget> _dedupeStructuralTargets(
    List<ChapterNavigationTarget> targets,
  ) {
    final result = <ChapterNavigationTarget>[];
    for (final target in targets) {
      if (!target.isSelectable) {
        result.add(target);
        continue;
      }
      if (target.isStructuralParent) {
        final child = _firstSelectableDescendant(target.chapter, targets);
        if (child != null && _isSameSemanticTarget(target, child)) continue;
      }
      result.add(target);
    }
    return result;
  }

  static ChapterNavigationTarget? _firstSelectableDescendant(
    ChapterInfo parent,
    List<ChapterNavigationTarget> targets,
  ) {
    for (final child in parent.children) {
      final direct = targets.cast<ChapterNavigationTarget?>().firstWhere(
        (target) => target != null && sameTarget(target, child),
        orElse: () => null,
      );
      if (direct?.isSelectable == true) return direct;
      final nested = _firstSelectableDescendant(child, targets);
      if (nested != null) return nested;
    }
    return null;
  }

  static bool _isSameSemanticTarget(
    ChapterNavigationTarget a,
    ChapterNavigationTarget b,
  ) {
    final sameHrefFragment =
        a.spineIndex == b.spineIndex &&
        a.href == b.href &&
        (a.anchorId ?? '') == (b.anchorId ?? '');
    if (sameHrefFragment) return true;

    final aLocal = a.resolvedLocalChunkIndex;
    final bLocal = b.resolvedLocalChunkIndex;
    if (a.spineIndex == b.spineIndex &&
        aLocal != null &&
        bLocal != null &&
        aLocal == bLocal &&
        a.textOffset == b.textOffset) {
      return true;
    }

    final aSource = a.resolvedSourceIndex;
    final bSource = b.resolvedSourceIndex;
    if (aSource != null &&
        bSource != null &&
        aSource == bSource &&
        a.textOffset == b.textOffset) {
      return true;
    }
    return false;
  }

  static int _compareNullableInts(int? a, int? b) {
    if (a != null && b != null) return a.compareTo(b);
    if (a == null && b == null) return 0;
    return a == null ? -1 : 1;
  }
}

class _ChapterEntry {
  const _ChapterEntry({required this.chapter, required this.tocOrder});

  final ChapterInfo chapter;
  final int tocOrder;
}
