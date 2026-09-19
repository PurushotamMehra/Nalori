import 'package:flutter/foundation.dart';

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import '../models/stable_book_location.dart';
import 'lazy_parsed_book.dart';

@immutable
class ReaderMappedSourceSegment {
  const ReaderMappedSourceSegment({required this.range, required this.text});

  final MappedTextRange range;
  final String text;
}

bool readerHasDurableSourceIdentity(StableBookLocation location) {
  return location.publicationFingerprint?.isNotEmpty == true &&
      location.normalizedHref?.isNotEmpty == true &&
      location.sourceChecksum != 'unknown' &&
      location.sourceParserVersion?.isNotEmpty == true &&
      location.localChunkIndex != null;
}

bool readerStableLocationMatchesSource({
  required StableBookLocation target,
  required StableBookLocation current,
  LazySourceChunkIdentity? sourceIdentity,
}) {
  if (target.bookId != current.bookId ||
      target.spineIndex != current.spineIndex ||
      target.localChunkIndex == null ||
      target.localChunkIndex != current.localChunkIndex) {
    return false;
  }

  final targetHref = target.normalizedHref ?? target.href;
  final currentHref = current.normalizedHref ?? current.href;
  if (targetHref.isNotEmpty && targetHref != currentHref) return false;
  if (target.publicationFingerprint != null &&
      target.publicationFingerprint != current.publicationFingerprint) {
    return false;
  }
  if (target.sourceChecksum != 'unknown' &&
      target.sourceChecksum != current.sourceChecksum) {
    return false;
  }
  if (target.sourceParserVersion != null &&
      target.sourceParserVersion != current.sourceParserVersion) {
    return false;
  }

  if (sourceIdentity == null) return true;
  final section = sourceIdentity.section;
  return sourceIdentity.localChunkIndex == target.localChunkIndex &&
      section.bookId == target.bookId &&
      section.spineIndex == target.spineIndex &&
      section.normalizedHref == targetHref &&
      (target.publicationFingerprint == null ||
          section.publicationFingerprint == target.publicationFingerprint) &&
      (target.sourceChecksum == 'unknown' ||
          section.sourceChecksum == target.sourceChecksum) &&
      (target.sourceParserVersion == null ||
          section.parserVersion == target.sourceParserVersion);
}

int? readerSourceIndexForStableLocation({
  required StableBookLocation location,
  required Map<int, StableBookLocation> locationsByChunkIndex,
  Map<int, LazySourceChunkIdentity> sourceIdentitiesByChunkIndex =
      const <int, LazySourceChunkIdentity>{},
}) {
  final matches = <int>[];
  for (final entry in locationsByChunkIndex.entries) {
    if (readerStableLocationMatchesSource(
      target: location,
      current: entry.value,
      sourceIdentity: sourceIdentitiesByChunkIndex[entry.key],
    )) {
      matches.add(entry.key);
    }
  }
  return matches.length == 1 ? matches.single : null;
}

int? readerDisplayIndexForStableLocation({
  required StableBookLocation location,
  required List<BookChunk> displayChunks,
  required Map<int, StableBookLocation> locationsByChunkIndex,
  Map<int, LazySourceChunkIdentity> sourceIdentitiesByChunkIndex =
      const <int, LazySourceChunkIdentity>{},
}) {
  final sourceIndex = readerSourceIndexForStableLocation(
    location: location,
    locationsByChunkIndex: locationsByChunkIndex,
    sourceIdentitiesByChunkIndex: sourceIdentitiesByChunkIndex,
  );
  if (sourceIndex == null) return null;

  for (
    var displayIndex = 0;
    displayIndex < displayChunks.length;
    displayIndex++
  ) {
    for (final range in displayChunks[displayIndex].effectiveSourceRanges) {
      if (range.originalChunkIndex == sourceIndex &&
          location.textOffset >= range.originalStartOffset &&
          location.textOffset < range.originalEndOffset) {
        return displayIndex;
      }
    }
  }
  return null;
}

StableBookLocation? readerStableLocationForDisplayIndex({
  required int displayIndex,
  required List<BookChunk> displayChunks,
  required List<List<int>> displayToOriginal,
  required Map<int, StableBookLocation> locationsByChunkIndex,
}) {
  if (displayIndex < 0 ||
      displayIndex >= displayChunks.length ||
      displayIndex >= displayToOriginal.length) {
    return null;
  }
  final ranges = displayChunks[displayIndex].effectiveSourceRanges;
  for (final sourceIndex in displayToOriginal[displayIndex]) {
    final base = locationsByChunkIndex[sourceIndex];
    if (base == null) continue;
    final range = ranges
        .where((candidate) => candidate.originalChunkIndex == sourceIndex)
        .firstOrNull;
    if (range == null) continue;
    return base.copyWith(textOffset: range.originalStartOffset);
  }
  return null;
}

List<Bookmark> resolveReaderBookmarksForSourceWindow({
  required List<Bookmark> bookmarks,
  required List<BookChunk> sourceChunks,
  required Map<int, StableBookLocation> locationsByChunkIndex,
  Map<int, LazySourceChunkIdentity> sourceIdentitiesByChunkIndex =
      const <int, LazySourceChunkIdentity>{},
}) {
  final resolved = <Bookmark>[];
  for (final bookmark in bookmarks) {
    final stable = bookmark.stableLocation;
    if (stable != null && readerHasDurableSourceIdentity(stable)) {
      final currentIndex = readerSourceIndexForStableLocation(
        location: stable,
        locationsByChunkIndex: locationsByChunkIndex,
        sourceIdentitiesByChunkIndex: sourceIdentitiesByChunkIndex,
      );
      if (currentIndex == null ||
          !_isValidSourceOffset(
            sourceChunks,
            currentIndex,
            stable.textOffset,
          )) {
        continue;
      }
      resolved.add(
        bookmark.copyWith(
          chunkIndex: currentIndex,
          originalStartOffset: stable.textOffset,
        ),
      );
      continue;
    }

    final legacyIndex = _uniquelyVerifiedLegacyBookmarkIndex(
      bookmark: bookmark,
      sourceChunks: sourceChunks,
    );
    if (legacyIndex != null) {
      resolved.add(
        bookmark.copyWith(
          chunkIndex: legacyIndex,
          originalStartOffset: bookmark.originalStartOffset,
        ),
      );
    }
  }
  return resolved;
}

String readerBookmarkProjectionKey(Bookmark bookmark) {
  final stable = bookmark.stableLocation;
  if (stable != null && readerHasDurableSourceIdentity(stable)) {
    return <Object?>[
      stable.bookId,
      stable.publicationFingerprint,
      stable.spineIndex,
      stable.normalizedHref ?? stable.href,
      stable.sourceChecksum,
      stable.sourceParserVersion,
      stable.localChunkIndex,
      stable.textOffset,
    ].join('|');
  }
  return 'legacy|${bookmark.locationKey}|${bookmark.createdAt.microsecondsSinceEpoch}';
}

List<ReaderMappedSourceSegment> readerMappedSourceSegments({
  required List<MappedTextRange> ranges,
  required List<BookChunk> sourceChunks,
}) {
  final segments = <ReaderMappedSourceSegment>[];
  for (final range in ranges) {
    final text = readerSourceSubstring(
      sourceChunks: sourceChunks,
      sourceIndex: range.originalChunkIndex,
      startOffset: range.originalStartOffset,
      endOffset: range.originalEndOffset,
    );
    if (text == null) return const <ReaderMappedSourceSegment>[];
    segments.add(ReaderMappedSourceSegment(range: range, text: text));
  }
  return segments;
}

String? readerSourceSubstring({
  required List<BookChunk> sourceChunks,
  required int sourceIndex,
  required int startOffset,
  required int endOffset,
}) {
  if (sourceIndex < 0 || sourceIndex >= sourceChunks.length) return null;
  final text = sourceChunks[sourceIndex].text;
  if (text == null ||
      startOffset < 0 ||
      endOffset > text.length ||
      startOffset >= endOffset) {
    return null;
  }
  return text.substring(startOffset, endOffset);
}

int? _uniquelyVerifiedLegacyBookmarkIndex({
  required Bookmark bookmark,
  required List<BookChunk> sourceChunks,
}) {
  final preview = _normalizedBookmarkPreview(bookmark.previewText);
  if (preview.isEmpty) return null;

  final matches = <int>[];
  for (var index = 0; index < sourceChunks.length; index++) {
    if (!_isValidSourceOffset(
      sourceChunks,
      index,
      bookmark.originalStartOffset,
    )) {
      continue;
    }
    final source = sourceChunks[index].text!;
    final tail = _normalizeText(source.substring(bookmark.originalStartOffset));
    if (tail.startsWith(preview)) {
      matches.add(index);
    }
  }
  return matches.length == 1 ? matches.single : null;
}

bool _isValidSourceOffset(
  List<BookChunk> sourceChunks,
  int sourceIndex,
  int offset,
) {
  if (sourceIndex < 0 || sourceIndex >= sourceChunks.length) return false;
  final text = sourceChunks[sourceIndex].text;
  return text != null && text.isNotEmpty && offset >= 0 && offset < text.length;
}

String _normalizedBookmarkPreview(String? text) {
  var normalized = _normalizeText(text ?? '');
  while (normalized.endsWith('.') || normalized.endsWith('\u2026')) {
    normalized = normalized.substring(0, normalized.length - 1).trimRight();
  }
  return normalized;
}

String _normalizeText(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
