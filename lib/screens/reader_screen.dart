import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent,
        kLongPressTimeout,
        kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_chunk.dart';
import '../models/book_list_semantics.dart';
import '../models/canonical_display_segment.dart';
import '../models/canonical_pagination.dart';
import '../models/derived_book_index.dart';
import '../models/book_metadata.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/quote_share_payload.dart';
import '../models/reader_checkpoint.dart';
import '../models/reader_font_evidence.dart';
import '../models/reader_layout_contract.dart';
import '../models/reader_compatibility.dart';
import '../models/reading_settings.dart';
import '../models/reader_position_session.dart';
import '../services/bookmark_service.dart';
import '../services/book_authoritative_text_service.dart';
import '../services/dictionary_service.dart';
import '../services/derived_book_index_service.dart';
import '../services/display_generation_coordinator.dart';
import '../services/reader_visible_correction_scheduler.dart';
import '../services/display_section_memory_cache.dart';
import '../services/frame_budgeted_range_scheduler.dart';
import '../services/progressive_display_state.dart';
import '../services/reader_card_paginator.dart' as paginator;
import '../services/segmented_display_cache_service.dart';
import '../services/highlight_palette_service.dart';
import '../services/highlight_service.dart';
import '../services/book_cache_service.dart';
import '../services/canonical_display_segment_admission.dart';
import '../services/canonical_display_cache_service.dart';
import '../services/card_depth_chapter_progress_service.dart';
import '../services/chapter_card_layout_service.dart';
import '../services/chapter_navigation_service.dart';
import '../services/lazy_book_session.dart';
import '../services/lazy_parsed_book.dart';
import '../services/lazy_section_repository.dart';
import '../services/reader_open_service.dart';
import '../services/reader_checkpoint_store.dart';
import '../services/reader_font_evidence_gate.dart';
import '../services/reader_layout_contract_service.dart';
import '../services/reader_source_projection_service.dart';
import '../services/reader_character_match_service.dart';
import '../services/reader_structural_progress_service.dart';
import '../services/reading_settings_service.dart';
import '../services/reading_stats_service.dart';
import '../services/book_metadata_service.dart';
import '../services/book_reader_theme_service.dart';
import '../services/user_education_service.dart';
import '../controllers/speed_read_controller.dart'; // Added this import
import '../widgets/navigation_panel.dart'; // AnnotationsPanel
import '../widgets/chapter_panel.dart';
import '../widgets/reading_card.dart';
import '../widgets/reading_card_deck.dart';
import '../widgets/book_completion_overlay.dart';
import '../widgets/bookmark_edit_dialog.dart';
import '../ui/app_visuals.dart';
import '../utils/reader_content_parser.dart';
import 'quote_card_preview_screen.dart';
import 'search_screen.dart';
import 'book_image_viewer_screen.dart';
import '../models/stable_book_location.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import '../models/position_history.dart';
import 'book_list_screen.dart';

const bool _readerDiagEnabled = bool.fromEnvironment('NALORI_EPUB_DIAG');
const String _readerDiagPrefix = 'NALORI_EPUB_DIAG';
const String _readerDiagScenario = String.fromEnvironment(
  'NALORI_READER_DIAG_SCENARIO',
);

int _readerDiagRssBytes() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return -1;
  }
}

void _readerDiagLog(String phase, Map<String, Object?> fields) {
  if (!_readerDiagEnabled) return;
  final parts = <String>[
    _readerDiagPrefix,
    'phase=$phase',
    'ts=${DateTime.now().toIso8601String()}',
    'rss=${_readerDiagRssBytes()}',
    'isolate=${Isolate.current.debugName ?? Isolate.current.hashCode}',
    for (final entry in fields.entries)
      if (entry.value != null) '${entry.key}=${entry.value}',
  ];
  // ignore: avoid_print
  print(parts.join(' '));
}

@visibleForTesting
QuoteSharePayload buildReaderQuoteSharePayload({
  required String selectedText,
  required String bookTitle,
  required String author,
  required String bookId,
  required int displayIndex,
  required ReaderFontFamily fontFamily,
  String? coverImagePath,
  int? startOffset,
  int? endOffset,
}) {
  return QuoteSharePayload.fromSelection(
    quote: selectedText,
    bookTitle: bookTitle,
    author: author,
    bookId: bookId,
    displayIndex: displayIndex,
    coverImagePath: coverImagePath,
    fontFamily: fontFamily,
    startOffset: startOffset,
    endOffset: endOffset,
  );
}

@visibleForTesting
Route<void> buildReaderQuoteShareRoute(QuoteSharePayload payload) {
  return PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => QuoteCardPreviewScreen(payload: payload),
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

@visibleForTesting
LazySectionWorkPriority lazySectionPriorityForReaderReason(String reason) {
  if (reason.startsWith('next_page_') ||
      reason.startsWith('previous_page_') ||
      reason.contains('source_anchor_navigation')) {
    return LazySectionWorkPriority.explicitNavigation;
  }
  if (reason.contains('warmup') || reason.contains('cold_restore')) {
    return LazySectionWorkPriority.adjacentReadiness;
  }
  if (reason.contains('boundary')) {
    return LazySectionWorkPriority.boundaryPrefetch;
  }
  return LazySectionWorkPriority.explicitNavigation;
}

@visibleForTesting
List<Highlight> resolveReaderHighlightsForSourceWindow({
  required List<Highlight> highlights,
  required Map<int, StableBookLocation> locationsByChunkIndex,
  List<BookChunk> sourceChunks = const <BookChunk>[],
  Map<int, LazySourceChunkIdentity> sourceIdentitiesByChunkIndex =
      const <int, LazySourceChunkIdentity>{},
}) {
  if (locationsByChunkIndex.isEmpty) return List<Highlight>.from(highlights);
  final resolved = <Highlight>[];
  for (final highlight in highlights) {
    final stable = highlight.stableLocation;
    if (stable == null || !readerHasDurableSourceIdentity(stable)) {
      final sourceIndex = highlight.originalChunkIndex;
      final source = sourceIndex >= 0 && sourceIndex < sourceChunks.length
          ? sourceChunks[sourceIndex]
          : null;
      final sourceText = source == null
          ? null
          : authoritativeBookChunkText(source);
      final rangeIsValid =
          sourceText != null &&
          highlight.startOffset >= 0 &&
          highlight.endOffset <= sourceText.length &&
          highlight.startOffset < highlight.endOffset;
      if (rangeIsValid &&
          sourceText.substring(highlight.startOffset, highlight.endOffset) ==
              highlight.text) {
        resolved.add(highlight);
        continue;
      }
      final listAlias = _resolveLegacyListHighlightByText(
        highlight: highlight,
        sourceChunks: sourceChunks,
      );
      if (listAlias != null) resolved.add(listAlias);
      continue;
    }

    final currentIndex = readerSourceIndexForStableLocation(
      location: stable,
      locationsByChunkIndex: locationsByChunkIndex,
      sourceIdentitiesByChunkIndex: sourceIdentitiesByChunkIndex,
    );
    if (currentIndex == null) continue;
    final rangeLength = highlight.endOffset - highlight.startOffset;
    final resolvedStart = stable.textOffset;
    final resolvedEnd = resolvedStart + rangeLength;
    final resolvedText = sourceChunks.isEmpty
        ? highlight.text
        : readerSourceSubstring(
            sourceChunks: sourceChunks,
            sourceIndex: currentIndex,
            startOffset: resolvedStart,
            endOffset: resolvedEnd,
          );
    if (resolvedText == null) continue;
    resolved.add(
      highlight.copyWith(
        originalChunkIndex: currentIndex,
        startOffset: resolvedStart,
        endOffset: resolvedEnd,
        text: resolvedText,
      ),
    );
  }
  return resolved;
}

Highlight? _resolveLegacyListHighlightByText({
  required Highlight highlight,
  required List<BookChunk> sourceChunks,
}) {
  if (highlight.text.isEmpty) return null;
  (BookChunk, int)? match;
  for (final chunk in sourceChunks) {
    if (chunk.listSemantics == null) continue;
    final text = authoritativeBookChunkTextOrEmpty(chunk);
    var offset = text.indexOf(highlight.text);
    while (offset >= 0) {
      if (match != null) return null;
      match = (chunk, offset);
      offset = text.indexOf(highlight.text, offset + 1);
    }
  }
  final resolved = match;
  if (resolved == null) return null;
  return highlight.copyWith(
    originalChunkIndex: resolved.$1.index,
    startOffset: resolved.$2,
    endOffset: resolved.$2 + highlight.text.length,
  );
}

@visibleForTesting
List<Highlight> buildTransientSearchHighlights({
  required DerivedSourceRange range,
  required List<BookChunk> sourceChunks,
}) {
  final highlights = <Highlight>[];
  for (var index = 0; index < sourceChunks.length; index++) {
    final chunk = sourceChunks[index];
    if (chunk.logicalParagraphId != range.logicalParagraphId) continue;
    final chunkStart = chunk.logicalParagraphStartOffset;
    final chunkEnd =
        chunk.logicalParagraphEndOffset ??
        chunkStart + (chunk.text?.length ?? 0);
    final overlapStart = math.max(range.paragraphStart, chunkStart);
    final overlapEnd = math.min(range.paragraphEnd, chunkEnd);
    if (overlapStart >= overlapEnd || chunk.text == null) continue;
    final localStart = overlapStart - chunkStart;
    final localEnd = overlapEnd - chunkStart;
    if (localStart < 0 || localEnd > chunk.text!.length) continue;
    highlights.add(
      Highlight(
        id: '__transient_search__${range.stableKey}__$index',
        originalChunkIndex: index,
        startOffset: localStart,
        endOffset: localEnd,
        text: chunk.text!.substring(localStart, localEnd),
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }
  return highlights;
}

@visibleForTesting
SourceChunkRange readerFirstVisibleSourceRange({
  required int targetOriginalIndex,
  required int sourceChunkCount,
  required bool lazy,
  required SourceChunkRange nearbyRange,
  int? lazyEndExclusive,
}) {
  if (!lazy) return nearbyRange;
  if (sourceChunkCount <= 0) return const SourceChunkRange(0, 0);
  final target = targetOriginalIndex.clamp(0, sourceChunkCount - 1);
  final endExclusive = (lazyEndExclusive ?? target + 1).clamp(
    target + 1,
    sourceChunkCount,
  );
  return SourceChunkRange(target, endExclusive);
}

@visibleForTesting
bool readerChunksShareHardMergeBoundary(BookChunk first, BookChunk second) {
  return paginator.readerChunksShareHardMergeBoundary(first, second);
}

@visibleForTesting
List<BookListDisplaySegment> readerListDisplaySegmentsForSlice({
  required BookChunk chunk,
  required int startOffset,
  required int endOffset,
}) {
  return paginator.readerListDisplaySegmentsForSlice(
    chunk: chunk,
    startOffset: startOffset,
    endOffset: endOffset,
  );
}

@visibleForTesting
bool readerCanAttemptDisplayMerge(BookChunk first, BookChunk second) {
  return paginator.readerCanAttemptDisplayMerge(first, second);
}

@visibleForTesting
int readerMeasuredAnchoredLookaheadEndExclusive({
  required List<BookChunk> sourceChunks,
  required int sourceIndex,
  required double heightBudget,
  required double effectiveLineBoxHeight,
}) {
  return paginator.readerMeasuredAnchoredLookaheadEndExclusive(
    sourceChunks: sourceChunks,
    sourceIndex: sourceIndex,
    heightBudget: heightBudget,
    effectiveLineBoxHeight: effectiveLineBoxHeight,
  );
}

@visibleForTesting
bool readerDisplayChunkContainsSourceOffset({
  required BookChunk chunk,
  required int sourceIndex,
  required int textOffset,
}) {
  return paginator.readerDisplayChunkContainsSourceOffset(
    chunk: chunk,
    sourceIndex: sourceIndex,
    textOffset: textOffset,
  );
}

@visibleForTesting
bool readerAnchoredCardBoundaryIsFinalized({
  required List<BookChunk> emittedCards,
  required BookChunk? pendingCard,
  required int sourceIndex,
  required int textOffset,
}) {
  return paginator.readerAnchoredCardBoundaryIsFinalized(
    emittedCards: emittedCards,
    pendingCard: pendingCard,
    sourceIndex: sourceIndex,
    textOffset: textOffset,
  );
}

@visibleForTesting
int? readerDisplayIndexContainingSourceOffset({
  required List<BookChunk> displayChunks,
  required int originalChunkIndex,
  required int textOffset,
}) {
  for (
    var displayIndex = 0;
    displayIndex < displayChunks.length;
    displayIndex++
  ) {
    for (final range in displayChunks[displayIndex].effectiveSourceRanges) {
      if (range.originalChunkIndex != originalChunkIndex) continue;
      if (textOffset >= range.originalStartOffset &&
          textOffset < range.originalEndOffset) {
        return displayIndex;
      }
    }
  }
  return null;
}

@visibleForTesting
bool readerShouldBackgroundPaginateChapter({
  required bool hasStructuralChapterBoundary,
  required bool startsAtPublicationStart,
  required bool spansAllReadableSections,
}) {
  if (!hasStructuralChapterBoundary &&
      startsAtPublicationStart &&
      spansAllReadableSections) {
    return false;
  }
  return true;
}

typedef ProgressiveDisplayRangeGenerator =
    Future<paginator.CanonicalReaderPaginationPathResult> Function(
      DisplayRangeRequest request,
    );
typedef ProgressiveCanonicalPublisher =
    CanonicalDisplayPublicationResult Function(
      ProgressiveDisplayState state,
      paginator.CanonicalReaderPaginationPathAccepted accepted,
      DisplayRangeRequest request,
      CanonicalFinalizedReaderCard? committedCard,
    );
typedef ChapterDisplayRangeGenerator =
    Future<DisplayRangeResult> Function(
      DisplayRangeRequest request,
      List<BookChunk> sourceChunks,
    );

final class _PreparedChapterLayoutSource {
  const _PreparedChapterLayoutSource({
    required this.key,
    required this.cacheKey,
    required this.signature,
    required this.chunks,
    required this.locations,
    required this.sectionChunkCounts,
    required this.chapterStart,
    required this.chapterEnd,
  });

  final ChapterCardLayoutKey key;
  final SegmentedDisplayCacheKey cacheKey;
  final DisplayGenerationSignature signature;
  final List<BookChunk> chunks;
  final Map<int, StableBookLocation> locations;
  final Map<int, int> sectionChunkCounts;
  final StableBookLocation chapterStart;
  final StableBookLocation chapterEnd;
}

/// Screen 2 — fullscreen vertical-swipe reader with progress tracking,
/// overlay menu (scrubber + navigation), and bookmark management.
class ReaderScreen extends StatefulWidget {
  final String title;
  final String bookId;
  final List<BookChunk> chunks;
  final Map<String, int> anchorMap;
  final List<ChapterInfo> chapters;
  final Map<String, List<int>> searchIndex;
  final int? initialOriginalChunkIndex;
  final int? initialOriginalStartOffset;
  final String? initialSourceText;
  final LazyBookSession? lazySession;
  final StableBookLocation? initialStableLocation;
  final Map<int, StableBookLocation> initialStableLocationsByChunkIndex;
  final bool initialHasContentBefore;
  final bool initialHasContentAfter;
  final File? directContinueFile;
  final BookMetadata? directContinueMetadata;
  final ReadingSettings? initialSettings;
  final ReaderCheckpoint? initialCheckpoint;
  final DerivedSourceRange? initialDerivedSourceRange;
  final bool initialLocationIsNavigationTarget;

  const ReaderScreen({
    super.key,
    required this.title,
    required this.bookId,
    required this.chunks,
    required this.anchorMap,
    required this.chapters,
    required this.searchIndex,
    this.initialOriginalChunkIndex,
    this.initialOriginalStartOffset,
    this.initialSourceText,
    this.lazySession,
    this.initialStableLocation,
    this.initialStableLocationsByChunkIndex = const {},
    this.initialHasContentBefore = false,
    this.initialHasContentAfter = false,
    this.directContinueFile,
    this.directContinueMetadata,
    this.initialSettings,
    this.initialCheckpoint,
    this.initialDerivedSourceRange,
    this.initialLocationIsNavigationTarget = false,
  });

  ReaderScreen.directContinue({
    super.key,
    required File bookFile,
    required BookMetadata metadata,
    required ReadingSettings settings,
  }) : title = metadata.title,
       bookId = metadata.id,
       chunks = const [],
       anchorMap = const {},
       chapters = const [],
       searchIndex = const {},
       initialOriginalChunkIndex = null,
       initialOriginalStartOffset = null,
       initialSourceText = null,
       lazySession = null,
       initialStableLocation = null,
       initialStableLocationsByChunkIndex = const {},
       initialHasContentBefore = false,
       initialHasContentAfter = false,
       directContinueFile = bookFile,
       directContinueMetadata = metadata,
       initialSettings = settings,
       initialCheckpoint = null,
       initialDerivedSourceRange = null,
       initialLocationIsNavigationTarget = false;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

/// Shared layout constants so boundary lines, ReadingCard padding,
/// and chunk-splitting all agree on the exact same measurements.
const double kBoundaryTop = 14.0;
const double kBoundaryBottom = 16.0;
const double kContentPaddingH = 24.0;
const double kReaderSideMarginMin = 12.0;
const double kReaderSideMarginMax = 56.0;
const double kReaderCardDepthInsetH = 18.0;
const double kReaderCardDepthInsetTop = 28.0;
const double kReaderCardDepthInsetBottom = 42.0;
const double kReaderCardDepthHeaderReserve = 40.0;
const double kReaderCardDepthFooterReserve = 42.0;
const double kReaderCardDepthBorderWidth = 1.8;
const double kReaderDialogueTextInset = paginator.kReaderDialogueTextInset;
const double kBoundaryTopFullPage = 4.0;
const double kBoundaryBottomFullPage = 6.0;
const MethodChannel _readerControlsChannel = MethodChannel('reader_controls');
const Duration _hardwarePageRepeatInitialDelay = Duration(milliseconds: 420);
const Duration _hardwarePageRepeatInterval = Duration(milliseconds: 360);

double readerBoundaryTopInset(ReadingSettings settings) {
  return settings.contentDensity == ContentDensity.fullPage
      ? kBoundaryTopFullPage
      : kBoundaryTop;
}

double readerBoundaryBottomInset(ReadingSettings settings) {
  return settings.contentDensity == ContentDensity.fullPage
      ? kBoundaryBottomFullPage
      : kBoundaryBottom;
}

EdgeInsets readerCardMargin(ReadingSettings settings) {
  if (!settings.enableCardDepth) return EdgeInsets.zero;

  final isFullPage = settings.contentDensity == ContentDensity.fullPage;
  return EdgeInsets.fromLTRB(
    isFullPage ? 14.0 : kReaderCardDepthInsetH,
    isFullPage ? 22.0 : kReaderCardDepthInsetTop,
    isFullPage ? 14.0 : kReaderCardDepthInsetH,
    isFullPage ? 34.0 : kReaderCardDepthInsetBottom,
  );
}

bool isChapterOneLikeTitle(String title) {
  return ChapterNavigationService.isChapterOneLikeTitle(title);
}

bool isFrontMatterTitle(String title) {
  return ChapterNavigationService.isFrontMatterTitle(title);
}

ChapterInfo? detectFirstReadingChapter(List<ChapterInfo> chapters) {
  return ChapterNavigationService.firstReadingEntry<ChapterInfo>(
    roots: chapters,
    titleOf: (chapter) => chapter.title,
    childrenOf: (chapter) => chapter.children,
  );
}

double readerHorizontalContentPadding(ReadingSettings settings) {
  return settings.sideMargin
      .clamp(kReaderSideMarginMin, kReaderSideMarginMax)
      .toDouble();
}

@immutable
class ReaderLayoutMetrics {
  final EdgeInsets contentPadding;
  final EdgeInsets cardMargin;
  final double availableWidth;
  final double availableHeight;
  final double safetyBuffer;
  final double targetTextHeight;
  final double preferredMaxTextHeight;
  final double minUsefulTextHeight;
  final double maxTextHeight;

  const ReaderLayoutMetrics({
    required this.contentPadding,
    required this.cardMargin,
    required this.availableWidth,
    required this.availableHeight,
    required this.safetyBuffer,
    required this.targetTextHeight,
    required this.preferredMaxTextHeight,
    required this.minUsefulTextHeight,
    required this.maxTextHeight,
  });
}

@immutable
class ReaderDensityPolicy {
  final ContentDensity density;
  final double pageHeightRatio;
  final int tinyWordCount;
  final double tinyHeightRatio;

  const ReaderDensityPolicy({
    required this.density,
    required this.pageHeightRatio,
    required this.tinyWordCount,
    required this.tinyHeightRatio,
  });
}

ReaderDensityPolicy readerDensityPolicy(ContentDensity density) {
  return switch (density) {
    ContentDensity.low => const ReaderDensityPolicy(
      density: ContentDensity.low,
      pageHeightRatio: 0.25,
      tinyWordCount: 10,
      tinyHeightRatio: 0.35,
    ),
    ContentDensity.medium => const ReaderDensityPolicy(
      density: ContentDensity.medium,
      pageHeightRatio: 0.50,
      tinyWordCount: 12,
      tinyHeightRatio: 0.25,
    ),
    ContentDensity.high => const ReaderDensityPolicy(
      density: ContentDensity.high,
      pageHeightRatio: 0.75,
      tinyWordCount: 14,
      tinyHeightRatio: 0.18,
    ),
    ContentDensity.fullPage => const ReaderDensityPolicy(
      density: ContentDensity.fullPage,
      pageHeightRatio: 1.0,
      tinyWordCount: 16,
      tinyHeightRatio: 0.12,
    ),
  };
}

ReaderLayoutMetrics resolveReaderLayoutMetrics(
  Size screenSize,
  EdgeInsets safeArea,
  ReadingSettings settings,
) {
  final policy = readerDensityPolicy(settings.contentDensity);
  final depthHeaderReserve = settings.enableCardDepth
      ? kReaderCardDepthHeaderReserve
      : 0.0;
  final depthFooterReserve = settings.enableCardDepth
      ? kReaderCardDepthFooterReserve
      : 0.0;
  final horizontalContentPadding = readerHorizontalContentPadding(settings);
  final contentPadding = EdgeInsets.fromLTRB(
    safeArea.left + horizontalContentPadding,
    safeArea.top + readerBoundaryTopInset(settings) + depthHeaderReserve,
    safeArea.right + horizontalContentPadding,
    safeArea.bottom + readerBoundaryBottomInset(settings) + depthFooterReserve,
  );
  final cardMargin = readerCardMargin(settings);

  final availableWidth = math.max(
    1.0,
    screenSize.width - contentPadding.horizontal - cardMargin.horizontal,
  );
  final availableHeight = math.max(
    1.0,
    screenSize.height - contentPadding.vertical - cardMargin.vertical,
  );

  final lineHeightPx = settings.effectiveLineBoxHeight;
  final depthBias = settings.enableCardDepth ? 4.0 : 0.0;
  final safetyBuffer = ((lineHeightPx * 0.65) + depthBias).clamp(14.0, 36.0);
  final usableTextHeight = math.max(
    availableHeight - safetyBuffer,
    lineHeightPx * 2.4,
  );
  final densityTextHeight = usableTextHeight * policy.pageHeightRatio;
  final minUsefulTextHeight = math.min(
    densityTextHeight * policy.tinyHeightRatio,
    lineHeightPx * 2.4,
  );

  return ReaderLayoutMetrics(
    contentPadding: contentPadding,
    cardMargin: cardMargin,
    availableWidth: availableWidth,
    availableHeight: availableHeight,
    safetyBuffer: safetyBuffer,
    targetTextHeight: densityTextHeight,
    preferredMaxTextHeight: densityTextHeight,
    minUsefulTextHeight: minUsefulTextHeight,
    maxTextHeight: densityTextHeight,
  );
}

int readerSoftWordCap(ContentDensity density) {
  return switch (density) {
    ContentDensity.low => 48,
    ContentDensity.medium => 96,
    ContentDensity.high => 144,
    ContentDensity.fullPage => 192,
  };
}

int readerLayoutWordCount(String text) {
  return paginator.readerLayoutWordCount(text);
}

TextAlign resolveReaderChunkTextAlign(
  BookChunk chunk,
  ReadingSettings settings,
) {
  return paginator.resolveReaderChunkTextAlign(chunk, settings);
}

EdgeInsets resolveReaderPublisherPadding(BookChunk chunk) {
  return paginator.resolveReaderPublisherPadding(chunk);
}

bool readerSettingsRequireDisplayChunkRebuild(
  ReadingSettings old,
  ReadingSettings updated,
) {
  return old.fontSize != updated.fontSize ||
      old.fontFamily != updated.fontFamily ||
      old.fontWeight != updated.fontWeight ||
      old.contentDensity != updated.contentDensity ||
      old.lineHeight != updated.lineHeight ||
      old.paragraphSpacing != updated.paragraphSpacing ||
      old.sideMargin != updated.sideMargin ||
      old.enableCardDepth != updated.enableCardDepth;
}

bool readerShouldShowFullPreparingPages({
  required bool hasPublishedReadableContent,
  required bool hasDisplayChunks,
  required bool hasSourceChunks,
  required bool isPreparing,
}) {
  return !hasPublishedReadableContent &&
      !hasDisplayChunks &&
      hasSourceChunks &&
      isPreparing;
}

enum ReaderPreparationFailureKind {
  malformedTable,
  layoutRejected,
  paginationRejected,
  unknown,
}

final class ReaderPreparationException implements Exception {
  const ReaderPreparationException(this.kind, this.message, [this.cause]);

  final ReaderPreparationFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ReaderPreparationException(${kind.name}): $message';
}

@visibleForTesting
bool readerShouldShowPreparationStatus({required Object? failure}) {
  return failure != null;
}

@visibleForTesting
bool readerShouldSurfacePreparationFailure(String reason) {
  return reason.startsWith('next_page_') ||
      reason.startsWith('previous_page_') ||
      reason.contains('source_anchor_navigation') ||
      reason == 'retry_failed_range';
}

bool readerTextEndsAtSentenceBoundary(String text) {
  return paginator.readerTextEndsAtSentenceBoundary(text);
}

List<({int start, int end})> readerSentenceRanges(String text) {
  return paginator.readerSentenceRanges(text);
}

/// Safe fallbacks used only when one complete sentence cannot fit on an empty
/// physical card. Whitespace remains attached to the preceding clause so the
/// returned ranges reconstruct [text] byte-for-byte.
List<({int start, int end})> readerSafeClauseRanges(String text) {
  return paginator.readerSafeClauseRanges(text);
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static int _nextReaderSessionSequence = 0;

  PageController? _pageController;
  final ReadingCardDeckController _cardDeckController =
      ReadingCardDeckController();
  late final BookmarkService _bookmarkService;
  late final AnimationController _overlayAnimController;
  late final Animation<double> _overlayAnim;
  late final SpeedReadController _speedReadController;
  late List<BookChunk> _sourceChunks;
  late Map<String, int> _sourceAnchorMap;
  late List<ChapterInfo> _sourceChapters;
  late Map<String, List<int>> _sourceSearchIndex;
  late Map<int, StableBookLocation> _sourceLocationsByChunkIndex;
  late Map<int, LazySourceChunkIdentity> _sourceIdentitiesByChunkIndex;
  late List<BookChunk> _publishedSourceChunks;
  late Map<int, StableBookLocation> _publishedSourceLocationsByChunkIndex;
  late Map<int, LazySourceChunkIdentity> _publishedSourceIdentitiesByChunkIndex;
  LazyBookSession? _lazySession;
  DerivedBookIndexSession? _derivedIndexSession;
  bool _lazyHasContentAfter = false;
  bool _isLoadingLazyBackwardSection = false;
  int? _lazyMaxLoadedSpineIndex;
  bool _isLoadingLazyForwardSection = false;
  final Map<DisplayRangeDirection, Future<bool>> _activeLazyAdjacentLoads = {};
  int _lazyAdjacentOperationSequence = 0;
  static const Duration _lazyHydrationQuietPeriod = Duration(milliseconds: 900);
  int _lastForegroundReaderWorkMs = 0;
  final ReaderOpenService _readerOpenService = ReaderOpenService();
  ReaderOpenOperation? _directOpenOperation;
  bool _directOpenInProgress = false;
  ReaderOpenException? _directOpenFailure;

  bool _ready = false;
  int _currentPage = 0;
  int _targetOriginalIndex = 0;
  double _targetProgressRatio = 0.0; // 0.0–1.0 position through the book
  bool _isFirstLayout = true;
  Size? _lastScreenSize;
  EdgeInsets? _lastSafeArea;
  TextScaler? _lastTextScaler;
  bool _isReaderLifecycleActive = true;
  bool _routePopReady = false;
  bool _routePopInProgress = false;
  bool _hasDeferredRestoreWhileInactive = false;
  int? _deferredRestoreNavigationGeneration;
  int _readerSurfaceBlockCount = 0;
  bool _cardInteractionBlocked = false;
  bool _isOpeningQuoteShare = false;

  // Overlay
  bool _overlayVisible = false;
  int _activeDisplayIndex = 0;

  // Tracks whether speed-read was auto-paused by menu opening (vs user pause)
  bool _speedReadAutoPaused = false;
  bool _speedReadLifecycleAutoPaused = false;
  bool _speedReadReaderBlockAutoPaused = false;
  bool _speedReadCardInteractionAutoPaused = false;
  bool _speedReadPageAdvanceScheduled = false;
  ({bool active, bool paused, bool pageComplete, int pageIndex})?
  _lastSpeedReadShellState;

  // Bookmarks
  List<Bookmark> _bookmarks = [];
  final Map<String, int> _bookmarkDisplayHints = {};
  int _defaultBookmarkColorIndex = 0;
  Color _defaultBookmarkColor = kBookmarkColors.first;

  // Highlights
  late final HighlightService _highlightService;
  late final HighlightPaletteService _highlightPaletteService;
  List<Highlight> _highlights = [];
  DerivedSourceRange? _transientSearchRange;
  Timer? _transientSearchTimer;
  int _transientSearchGeneration = 0;
  List<Color> _highlightPalette = kHighlightColors;
  Color _defaultHighlightColor = kHighlightColors.last;
  List<Highlight>? _characterMatchHighlights;
  List<BookChunk>? _characterMatchSourceChunks;
  List<ReaderCharacterSourceRange> _characterSourceRanges = const [];

  // Dictionary
  late final DictionaryService _dictionaryService;

  // Rendered Chunks
  final List<BookChunk> _displayChunks = [];
  final List<List<int>> _displayToOriginal = [];
  final Map<int, int> _originalToDisplay = {};
  bool _displayChunksComplete = false;
  ProgressiveDisplayState? _progressiveDisplayState;
  CanonicalDisplayCacheService? _canonicalDisplayCacheService;
  Future<void>? _activeProgressiveRangeTask;
  DisplayRangeRequest? _activeProgressiveRangeRequest;
  final Set<int> _cancelledProgressiveRangeGenerations = <int>{};
  late final FrameBudgetedRangeScheduler _displayRangeScheduler;
  final paginator.ReaderCardPaginator _readerCardPaginator =
      const paginator.ReaderCardPaginator();
  ProgressiveDisplayRangeGenerator? _progressiveRangeGenerator;
  ProgressiveCanonicalPublisher? _progressiveCanonicalPublisher;
  ChapterDisplayRangeGenerator? _chapterDisplayRangeGenerator;
  final ChapterCardLayoutCoordinator _chapterCardLayoutCoordinator =
      ChapterCardLayoutCoordinator();
  ChapterCardLayout? _currentChapterCardLayout;
  Future<void>? _activeChapterLayoutTask;
  int? _activeChapterLayoutRangeGeneration;
  int _progressiveRangeGeneration = 0;
  bool _isPreparingForwardRange = false;
  bool _isPreparingBackwardRange = false;
  bool _isPreparingTargetRange = false;
  Object? _progressiveRangeFailure;
  VoidCallback? _progressiveFailureRetry;
  // Settings
  final _settingsService = ReadingSettingsService();
  Future<void>? _settingsUpdateTail;
  Future<void> _settingsSaveTail = Future<void>.value();
  int _settingsUpdateGeneration = 0;
  final _bookReaderThemeService = BookReaderThemeService();
  final _educationService = UserEducationService();
  ReadingSettings _settings = const ReadingSettings();

  // Metadata
  final _metadataService = BookMetadataService();
  final ReaderCheckpointStore _checkpointStore = ReaderCheckpointStore();
  ReaderCheckpointCoordinator? _checkpointCoordinator;
  ReaderCheckpoint? _preloadedCheckpoint;
  ReaderRestoreResolution? _pendingCheckpointRestoreResolution;
  ReaderLayoutTransitionToken? _activeCheckpointLayoutToken;
  String? _publicationFingerprint;
  String _nextCheckpointNavigationSource = 'page_settled';
  bool _checkpointVerificationScheduled = false;
  int _lastSettledNavigationGeneration = -1;

  // Cached preferences to avoid repeated async lookups
  SharedPreferences? _prefs;
  AnnotationPanelTab _lastAnnotationsTab = AnnotationPanelTab.highlights;

  // Display chunk caching
  SegmentedDisplayCacheService? _segmentedDisplayCacheService;
  final DisplaySectionMemoryCache _displaySectionMemoryCache =
      DisplaySectionMemoryCache();
  final _displayGenerationCoordinator = DisplayGenerationCoordinator();
  final ReaderNavigationPublicationCoordinator<StableBookLocation>
  _navigationPublicationCoordinator =
      ReaderNavigationPublicationCoordinator<StableBookLocation>();
  late final ReaderVisiblePositionCoordinator<StableBookLocation>
  _visiblePositionCoordinator;
  late final ReaderVisibleCorrectionScheduler<StableBookLocation>
  _visibleCorrectionScheduler;
  ReaderVisibleNavigationIntent<StableBookLocation>? _controllerIntent;
  int? _syntheticControllerTargetIndex;
  ReaderNavigationToken<StableBookLocation>? _pendingDisplayNavigationToken;
  bool _isRebuildingChunks = false; // true while async batch measurement runs
  bool _hasCompletedDisplayChunkBuild = false;
  int _rebuildGeneration = 0; // cancellation token for async rebuilds
  int _lastCompletedDisplayRebuildGeneration = -1;
  String? _lastCompletedDisplayRebuildCacheKey;
  DisplayGenerationSignature? _lastCompletedDisplayRebuildSignature;
  int _lastCompletedDisplayRebuildAtMs = 0;

  // Cached flat chapter list — avoids recomputing tree walk + sort on every access
  List<({int chunkIndex, String title})>? _cachedFlatChapters;

  // Reading stats
  final _statsService = ReadingStatsService();
  int? _lastInsightDisplayIndex;
  DateTime? _lastInsightStartedAt;
  int _highestMeasuredOriginalIndex = -1;
  List<_AnalyticsChapter> _analyticsChapters = const [];
  bool _hasRegisteredInsightChapters = false;

  // Text-anchor for position restoration (opening text on current page)
  _PageAnchor? _positionAnchor;
  List<int> _targetOriginalCandidates = const [];
  bool _hasPendingSettingsRestore = false;
  bool _hasResolvedInitialLocation = false;
  bool _preferSourceIndexOnNextRestore = false;
  StableBookLocation? _pendingExactStableRestore;
  bool _lazyColdRestoreAdjacentStarted = false;
  bool _lazyColdRestoreAdjacentComplete = false;
  bool _lazyInitialAdjacentWarmupStarted = false;
  bool _lazyParsedHydrationStarted = false;
  int _backgroundWorkGeneration = 0;
  bool _readerDiagScenarioStarted = false;
  String? _activeReaderLayoutFingerprint;
  final ReaderFontEvidenceGate _readerFontEvidenceGate =
      ReaderFontEvidenceGate();
  ReaderFontReadyTerminalBundled? _terminalReaderFontOutcome;
  ReaderLayoutContract? _activeReaderLayoutContract;
  ReaderLayoutContract? _pendingReaderLayoutContract;
  int? _pendingReaderLayoutGeneration;
  List<ResolvedReaderCardLayout?> _resolvedDisplayLayouts = const [];

  static const int _positionAnchorLength = 120;
  static const int _initialRangeLookBehind = 16;
  static const int _initialRangeLookAhead = 79;
  static const int _minimumInitialRangeSourceChunks = 96;
  static const int _lazyInitialRangeLookBehind = 8;
  static const int _lazyInitialRangeLookAhead = 39;
  static const int _lazyMinimumInitialRangeSourceChunks = 48;
  static const int _adjacentRangeSourceChunks = 192;
  static const String _readerDrawerLastTabKeySuffix = '.readerDrawer.lastTab';

  // Live scale for Transform.scale visual feedback during slider drag
  double _liveScale = 1.0;

  // Book completion tracking
  bool _hasShownCompletion = false;
  bool _isCelebrationVisible = false;
  bool _showReaderGestureHint = false;
  bool _readerGestureHintCheckStarted = false;
  Timer? _readerGestureHintTimer;
  Timer? _readerViewportLongPressTimer;
  Timer? _readerViewportDeferredTapTimer;
  Offset? _readerViewportPointerDownPosition;
  int? _readerViewportPointer;
  int _readerViewportTapGeneration = 0;
  int? _readerViewportTapHandledGeneration;
  int? _readerViewportTapSuppressedGeneration;
  DateTime? _readerViewportTapSuppressedUntil;
  bool _readerViewportPointerMoved = false;
  bool _readerViewportPointerHeld = false;
  Timer? _hardwarePageRepeatStartTimer;
  Timer? _hardwarePageRepeatTimer;
  int? _hardwarePageRepeatDelta;

  // Position History
  final List<PositionHistory> _positionStack = [];
  Timer? _dwellTimer;
  Timer? _positionSaveTimer;
  Timer? _previewPromotionTimer;
  final ReaderPositionPersistenceQueue _positionPersistenceQueue =
      ReaderPositionPersistenceQueue();
  final ReaderPositionRevisionClock _positionRevisionClock =
      ReaderPositionRevisionClock();
  int? _pendingPreviewJumpDisplayIndex;
  bool _isScrubbing = false;
  int? _scrubStartDisplayIndex;
  int? _scrubPreviewDisplayIndex;
  int? _lazyScrubPreviewSpineIndex;
  final ReaderStructuralScrubCommitPolicy _lazyStructuralScrubPolicy =
      ReaderStructuralScrubCommitPolicy();
  int? _lastDwellPage;
  DateTime? _readingSessionStartedAt;
  final ReaderPositionSession _positionSession = ReaderPositionSession();
  final ValueNotifier<PositionHistory?> _positionHistoryNotifier =
      ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    final readerSequence = ++_nextReaderSessionSequence;
    _visiblePositionCoordinator =
        ReaderVisiblePositionCoordinator<StableBookLocation>(
          sessionId: '${widget.bookId}:$readerSequence',
          readerGeneration: readerSequence,
        );
    _visibleCorrectionScheduler =
        ReaderVisibleCorrectionScheduler<StableBookLocation>(
          coordinator: _visiblePositionCoordinator,
          apply: _applyPendingVisibleCorrection,
        );
    _settings = widget.initialSettings ?? const ReadingSettings();
    _preloadedCheckpoint = widget.initialCheckpoint;
    _lazySession = widget.lazySession;
    if (_lazySession case final session?) {
      _derivedIndexSession = DerivedBookIndexSession(source: session);
    }
    _sourceChunks = List<BookChunk>.from(widget.chunks);
    _sourceAnchorMap = Map<String, int>.from(widget.anchorMap);
    _sourceChapters = List<ChapterInfo>.from(widget.chapters);
    _sourceSearchIndex = Map<String, List<int>>.from(widget.searchIndex);
    _sourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
      widget.initialStableLocationsByChunkIndex,
    );
    _sourceIdentitiesByChunkIndex = <int, LazySourceChunkIdentity>{};
    final initialLazyWindow = _lazySession?.loadedWindow();
    if (initialLazyWindow != null) {
      _sourceIdentitiesByChunkIndex = Map<int, LazySourceChunkIdentity>.from(
        initialLazyWindow.sourceIdentitiesByChunkIndex,
      );
    }
    _publishedSourceChunks = List<BookChunk>.from(_sourceChunks);
    _publishedSourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
      _sourceLocationsByChunkIndex,
    );
    _publishedSourceIdentitiesByChunkIndex =
        Map<int, LazySourceChunkIdentity>.from(_sourceIdentitiesByChunkIndex);
    _lazyHasContentAfter = widget.initialHasContentAfter;
    final loadedSpines = _sourceLocationsByChunkIndex.values
        .map((location) => location.spineIndex)
        .toSet();
    if (loadedSpines.isNotEmpty) {
      _lazyMaxLoadedSpineIndex = loadedSpines.reduce(math.max);
    }
    if (widget.initialStableLocation != null) {
      _pendingExactStableRestore = widget.initialStableLocation;
      _preferSourceIndexOnNextRestore = true;
    }
    _transientSearchRange = widget.initialDerivedSourceRange;
    if (_transientSearchRange != null) {
      final generation = ++_transientSearchGeneration;
      _transientSearchTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || generation != _transientSearchGeneration) return;
        setState(() => _transientSearchRange = null);
      });
    }
    _displayRangeScheduler = FrameBudgetedRangeScheduler();
    WidgetsBinding.instance.addObserver(this);
    _bookmarkService = BookmarkService(bookId: widget.bookId);
    _highlightService = HighlightService(bookId: widget.bookId);
    _highlightPaletteService = HighlightPaletteService();
    _dictionaryService = DictionaryService(bookId: widget.bookId);

    // Hide system UI for immersive full-screen reading.
    // User can temporarily reveal status/nav bars by swiping from edges.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // The system UI change is async — MediaQuery won't reflect the new
    // safe area until a later frame. Schedule a rebuild so display chunks
    // are re-measured with the final (immersive) dimensions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleLazyColdRestoreAdjacentWindow();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() {});
        });
      }
    });

    _overlayAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _overlayAnim = CurvedAnimation(
      parent: _overlayAnimController,
      curve: Curves.easeInOut,
    );

    _speedReadController = SpeedReadController();
    _lastSpeedReadShellState = _speedReadShellState();
    _speedReadController.addListener(_onSpeedReadChanged);
    _speedReadController.setWPM(_settings.speedReadWPM);
    _speedReadController.setAdaptivePacing(_settings.speedReadAdaptivePacing);
    _readerControlsChannel.setMethodCallHandler(_handleReaderControlMethodCall);

    _startReadingSession();
    _initReadingPosition();
    if (widget.directContinueFile != null) {
      _startDirectContinueOpen();
    }
  }

  void _onSpeedReadChanged() {
    if (!mounted) return;
    final nextShellState = _speedReadShellState();
    if (_lastSpeedReadShellState != nextShellState) {
      _lastSpeedReadShellState = nextShellState;
      setState(() {});
    }
    _scheduleSpeedReadPageAdvanceIfNeeded();
  }

  ({bool active, bool paused, bool pageComplete, int pageIndex})
  _speedReadShellState() => (
    active: _speedReadController.isActive,
    paused: _speedReadController.isPaused,
    pageComplete: _speedReadController.isPageComplete,
    pageIndex: _speedReadController.currentPageIndex,
  );

  void _scheduleSpeedReadPageAdvanceIfNeeded() {
    if (!_speedReadController.isActive ||
        !_speedReadController.isPageComplete ||
        _settings.speedReadPageAdvanceMode != SpeedReadPageAdvanceMode.auto ||
        _speedReadPageAdvanceScheduled) {
      return;
    }

    _speedReadPageAdvanceScheduled = true;
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      _speedReadPageAdvanceScheduled = false;

      if (!_speedReadController.isActive ||
          !_speedReadController.isPageComplete ||
          _displayChunks.isEmpty) {
        return;
      }

      if (_currentPage >= _displayChunks.length - 1) {
        final state = _progressiveDisplayState;
        if (state != null && state.hasUnavailableAfter) {
          _nextReaderPage(
            duration: const Duration(milliseconds: 340),
            curve: Curves.easeOutCubic,
          );
        }
        return;
      }

      _nextReaderPage(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _stageCommittedLifecycleSnapshot('reader_disposed');
    WidgetsBinding.instance.removeObserver(this);
    _directOpenOperation?.cancel();
    _displayGenerationCoordinator.cancelActive('reader_disposed');
    _navigationPublicationCoordinator.cancelPending();
    _rebuildGeneration++;
    _progressiveRangeGeneration++;
    _progressiveRangeGenerator = null;
    _progressiveCanonicalPublisher = null;
    _chapterDisplayRangeGenerator = null;
    _cancelChapterCardLayoutWork(clearPublished: true);
    _cancelledProgressiveRangeGenerations.add(_progressiveRangeGeneration);
    _displayRangeScheduler.dispose();
    _displaySectionMemoryCache.clear();
    _progressiveDisplayState?.cancelActiveRequests();
    _progressiveDisplayState = null;
    _readerControlsChannel.setMethodCallHandler(null);
    unawaited(_setNativeReaderControls(readerVisible: false));
    _dwellTimer?.cancel();
    _previewPromotionTimer?.cancel();
    _readerGestureHintTimer?.cancel();
    _readerViewportLongPressTimer?.cancel();
    _readerViewportDeferredTapTimer?.cancel();
    _stopHardwarePagePress();
    _positionSaveTimer?.cancel();
    _transientSearchTimer?.cancel();
    unawaited(_derivedIndexSession?.dispose());
    unawaited(_flushReaderPersistence());
    _visibleCorrectionScheduler.dispose();
    _visiblePositionCoordinator.dispose();
    _positionStack.clear();
    _savePositionHistory(); // Clear history on explicit book close

    // Restore system UI when leaving the reader
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _overlayAnimController.dispose();
    _settingsDebounceTimer?.cancel();
    _speedReadController.removeListener(_onSpeedReadChanged);
    _speedReadController.dispose();
    _pageController?.dispose();
    _positionHistoryNotifier.dispose();
    final lazySession = _lazySession;
    if (lazySession != null) {
      unawaited(lazySession.close());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isReaderLifecycleActive = false;
        _pauseNonessentialReaderWork('lifecycle_${state.name}');
        _stageCommittedLifecycleSnapshot('lifecycle_${state.name}');
        _dwellTimer?.cancel();
        _previewPromotionTimer?.cancel();
        _stopHardwarePagePress();
        if (_speedReadController.isActive && !_speedReadController.isPaused) {
          _speedReadController.pause();
          _speedReadLifecycleAutoPaused = true;
        }
        unawaited(_syncNativeReaderControlsState());
        unawaited(_flushReaderPersistence());
        break;
      case AppLifecycleState.resumed:
        _isReaderLifecycleActive = true;
        _applyDeferredRestoreAfterResume();
        unawaited(_syncNativeReaderControlsState());
        _startReadingSession();
        if (_speedReadLifecycleAutoPaused) {
          _speedReadLifecycleAutoPaused = false;
          _resumeAutoPausedSpeedReadIfReady();
        }
        if (_displayChunks.isNotEmpty) {
          _scheduleLazyParsedHydration();
          _scheduleDerivedIndexWhenQuiet();
        }
        break;
    }
  }

  @override
  void didHaveMemoryPressure() {
    final beforeSourceSections = _lazySession?.retainedSectionCount ?? 0;
    final beforeSourceBytes = _lazySession?.retainedEstimatedBytes ?? 0;
    final beforeDisplayBytes = _displaySectionMemoryCache.estimatedBytes;
    final beforeFontBytes = _readerFontEvidenceGate.retainedSourceEvidenceBytes;
    _pauseNonessentialReaderWork('android_memory_pressure');
    _lazySession?.handleMemoryPressure();
    _displaySectionMemoryCache.clear();
    _readerFontEvidenceGate.releaseRetainedSourceEvidence();
    _canonicalDisplayCacheService?.cancelQueuedWrites();
    final cache = _canonicalDisplayCacheService;
    if (cache != null) unawaited(cache.evictAllUnpinned());
    _characterMatchHighlights = null;
    _characterMatchSourceChunks = null;
    _characterSourceRanges = const [];
    if (_resolvedDisplayLayouts.isNotEmpty) {
      final current = _currentPage.clamp(0, _resolvedDisplayLayouts.length - 1);
      _resolvedDisplayLayouts = List<ResolvedReaderCardLayout?>.generate(
        _resolvedDisplayLayouts.length,
        (index) => (index - current).abs() <= 1
            ? _resolvedDisplayLayouts[index]
            : null,
        growable: false,
      );
    }
    _readerDiagLog('reader_memory_pressure_release', {
      'book': widget.bookId,
      'sourceSectionsBefore': beforeSourceSections,
      'sourceSectionsAfter': _lazySession?.retainedSectionCount ?? 0,
      'sourceBytesBefore': beforeSourceBytes,
      'sourceBytesAfter': _lazySession?.retainedEstimatedBytes ?? 0,
      'displayBytesBefore': beforeDisplayBytes,
      'displayBytesAfter': _displaySectionMemoryCache.estimatedBytes,
      'fontBytesBefore': beforeFontBytes,
      'fontBytesAfter': _readerFontEvidenceGate.retainedSourceEvidenceBytes,
      'visibleCardPreserved': _displayChunks.isNotEmpty,
    });
  }

  void _stageCommittedLifecycleSnapshot(String reason) {
    final anchor = _visiblePositionCoordinator.committedLocation;
    if (anchor == null || _displayChunks.isEmpty) return;
    final displayIndex = _displayIndexForStableAnchor(anchor);
    if (displayIndex == null) {
      _logVisiblePositionMutation(
        reason: reason,
        classification: ReaderVisibleMutationClassification.synthetic,
        accepted: false,
        decisionReason: 'committed_anchor_unresolved_for_lifecycle_snapshot',
        oldLocation: anchor,
        newLocation: anchor,
        oldLocalIndex: _currentPage,
      );
      return;
    }
    final snapshot = _captureCommittedPosition(displayIndex);
    if (snapshot == null) return;
    _positionPersistenceQueue.stage(snapshot);
    _readerDiagLog('lifecycle_checkpoint_snapshot_captured', {
      'book': widget.bookId,
      'readerSessionId': _visiblePositionCoordinator.sessionId,
      'reason': reason,
      'displayIndex': displayIndex,
      ..._stableLocationDiagFields(anchor),
      'checkpointRevision': _checkpointCoordinator?.current?.revision,
    });
  }

  void _startReadingSession() {
    _readingSessionStartedAt ??= DateTime.now();
    _lastInsightDisplayIndex ??= _currentPage;
    _lastInsightStartedAt ??= DateTime.now();
  }

  Future<void> _flushReadingSession() async {
    _lastInsightDisplayIndex = null;
    _lastInsightStartedAt = null;
    final startedAt = _readingSessionStartedAt;
    if (startedAt == null) return;

    _readingSessionStartedAt = null;
    await _statsService.recordReadingSession(
      startedAt: startedAt,
      endedAt: DateTime.now(),
    );
  }

  Future<void> _flushReaderPersistence() async {
    while (true) {
      final pendingSettings = _settingsUpdateTail;
      if (pendingSettings == null) break;
      await pendingSettings;
      if (identical(pendingSettings, _settingsUpdateTail)) break;
    }
    await _flushPendingReadingPosition();
    await _checkpointCoordinator?.flush();
    await _flushReadingSession();
    await _statsService.flushPendingWrites();
  }

  Future<void> _flushAndPopReaderRoute() async {
    if (_routePopInProgress) return;
    _routePopInProgress = true;
    await _flushReaderPersistence();
    if (!mounted) return;
    setState(() => _routePopReady = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  bool get _isReaderInteractable =>
      _ready &&
      _isReaderLifecycleActive &&
      _readerSurfaceBlockCount == 0 &&
      !_overlayVisible &&
      !_isCelebrationVisible;

  bool get _canAutoResumeSpeedRead =>
      _isReaderLifecycleActive &&
      _readerSurfaceBlockCount == 0 &&
      !_overlayVisible &&
      !_cardInteractionBlocked &&
      !_isCelebrationVisible;

  void _resumeAutoPausedSpeedReadIfReady() {
    if (!_canAutoResumeSpeedRead ||
        !_speedReadController.isActive ||
        !_speedReadController.isPaused) {
      return;
    }
    _speedReadController.resume();
  }

  void _clearSpeedReadAutoPauseFlags() {
    _speedReadAutoPaused = false;
    _speedReadLifecycleAutoPaused = false;
    _speedReadReaderBlockAutoPaused = false;
    _speedReadCardInteractionAutoPaused = false;
  }

  bool get _usesInteractiveCardDeck => _settings.enableCardDepth;

  void _cancelPreviewPromotionTimer() {
    _previewPromotionTimer?.cancel();
    _previewPromotionTimer = null;
  }

  void _schedulePreviewPromotion(int displayIndex) {
    _cancelPreviewPromotionTimer();
    _previewPromotionTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted ||
          !_isReaderLifecycleActive ||
          _positionSession.isScrubbing ||
          _positionSession.previewPosition != displayIndex ||
          _positionSession.activeVisiblePosition != displayIndex) {
        return;
      }
      _promotePreviewToCommitted();
    });
  }

  void _promotePreviewToCommitted() {
    final promoted = _positionSession.previewPosition;
    if (promoted == null) return;
    _positionSession.clearPreview(visibleDisplayIndex: promoted);
    _isScrubbing = false;
    _scrubPreviewDisplayIndex = null;
    _scrubStartDisplayIndex = null;
    _pendingPreviewJumpDisplayIndex = null;
    _cancelPreviewPromotionTimer();
    _onPageSettled(promoted);
  }

  void _clearPreviewState({int? visibleDisplayIndex}) {
    _positionSession.clearPreview(visibleDisplayIndex: visibleDisplayIndex);
    _isScrubbing = false;
    _scrubPreviewDisplayIndex = null;
    _lazyScrubPreviewSpineIndex = null;
    _lazyStructuralScrubPolicy.cancel();
    _scrubStartDisplayIndex = null;
    _pendingPreviewJumpDisplayIndex = null;
    _cancelPreviewPromotionTimer();
  }

  void _jumpReaderToPage(
    int targetIndex, {
    bool asPreview = false,
    String reason = 'programmatic_page_jump',
    StableBookLocation? targetLocation,
    ReaderVisibleNavigationIntent<StableBookLocation>? navigationIntent,
  }) {
    if (_displayChunks.isEmpty) return;
    final clamped = targetIndex.clamp(0, _displayChunks.length - 1);
    if (asPreview) {
      _pendingPreviewJumpDisplayIndex = clamped;
      _positionSession.updatePreview(clamped);
    }
    if (!asPreview) {
      final stableTarget =
          targetLocation ?? _committedStableLocationForDisplay(clamped);
      if (stableTarget != null) {
        final intent = navigationIntent;
        _controllerIntent =
            intent != null &&
                _visiblePositionCoordinator.isCurrent(intent) &&
                intent.target == stableTarget
            ? intent
            : _beginExplicitVisibleNavigation(stableTarget, reason);
        final controllerIntent = _controllerIntent;
        if (controllerIntent != null) {
          _visiblePositionCoordinator.markControllerMoved(controllerIntent);
          _syntheticControllerTargetIndex = null;
        }
      }
    }
    if (_usesInteractiveCardDeck || _pageController?.hasClients != true) {
      if (_currentPage != clamped ||
          _activeDisplayIndex != clamped ||
          _isScrubbing ||
          asPreview) {
        _onPageChanged(clamped);
      }
      return;
    }
    _logVisiblePositionMutation(
      reason: reason,
      classification: ReaderVisibleMutationClassification.programmatic,
      accepted: _controllerIntent != null,
      decisionReason: _controllerIntent == null
          ? 'explicit_intent_unavailable'
          : 'controller_jump_requested',
      oldLocation: _visiblePositionCoordinator.committedLocation,
      newLocation:
          targetLocation ?? _committedStableLocationForDisplay(clamped),
      oldLocalIndex: _currentPage,
      newLocalIndex: clamped,
      intent: _controllerIntent,
    );
    _pageController!.jumpToPage(clamped);
  }

  void _animateReaderToPage(
    int targetIndex, {
    required Duration duration,
    required Curve curve,
    String reason = 'programmatic_page_animation',
    StableBookLocation? targetLocation,
    ReaderVisibleNavigationIntent<StableBookLocation>? navigationIntent,
  }) {
    if (_displayChunks.isEmpty) return;
    final clamped = targetIndex.clamp(0, _displayChunks.length - 1);
    final stableTarget =
        targetLocation ?? _committedStableLocationForDisplay(clamped);
    if (stableTarget != null) {
      final intent = navigationIntent;
      _controllerIntent =
          intent != null &&
              _visiblePositionCoordinator.isCurrent(intent) &&
              intent.target == stableTarget
          ? intent
          : _beginExplicitVisibleNavigation(stableTarget, reason);
      final controllerIntent = _controllerIntent;
      if (controllerIntent != null) {
        _visiblePositionCoordinator.markControllerMoved(controllerIntent);
        _syntheticControllerTargetIndex = null;
      }
    }
    if (_usesInteractiveCardDeck || _pageController?.hasClients != true) {
      if (_usesInteractiveCardDeck) {
        final intent = _controllerIntent;
        final operation = _cardDeckController.startNavigation(
          clamped,
          duration,
          curve,
        );
        if (operation.started) {
          unawaited(
            operation.completed.then((completed) {
              if (!completed && intent != null) {
                _failControllerNavigationIntent(
                  intent,
                  'card_deck_animation_cancelled',
                );
              }
            }),
          );
          return;
        }
      }
      if (_currentPage != clamped || _activeDisplayIndex != clamped) {
        _onPageChanged(clamped);
      }
      return;
    }
    _logVisiblePositionMutation(
      reason: reason,
      classification: ReaderVisibleMutationClassification.programmatic,
      accepted: _controllerIntent != null,
      decisionReason: _controllerIntent == null
          ? 'explicit_intent_unavailable'
          : 'controller_animation_requested',
      oldLocation: _visiblePositionCoordinator.committedLocation,
      newLocation: stableTarget,
      oldLocalIndex: _currentPage,
      newLocalIndex: clamped,
      intent: _controllerIntent,
    );
    final controller = _pageController!;
    final intent = _controllerIntent;
    unawaited(
      controller
          .animateToPage(clamped, duration: duration, curve: curve)
          .then((_) {
            if (intent == null) return;
            if (!mounted ||
                !identical(_pageController, controller) ||
                !controller.hasClients) {
              _failControllerNavigationIntent(
                intent,
                'page_controller_detached_or_replaced',
              );
              return;
            }
            _scheduleProgrammaticPageSettlement(clamped);
          })
          .catchError((Object error) {
            if (intent != null) {
              _failControllerNavigationIntent(
                intent,
                'page_controller_animation_failed',
              );
            }
          }),
    );
  }

  void _failControllerNavigationIntent(
    ReaderVisibleNavigationIntent<StableBookLocation> intent,
    String reason,
  ) {
    if (!_visiblePositionCoordinator.isCurrent(intent)) return;
    final committed = _visiblePositionCoordinator.committedLocation;
    _visiblePositionCoordinator.cancelActiveIntent(failed: true);
    if (identical(_controllerIntent, intent)) {
      _controllerIntent = null;
    }
    _logVisiblePositionMutation(
      reason: intent.reason,
      classification: ReaderVisibleMutationClassification.programmatic,
      accepted: false,
      decisionReason: reason,
      oldLocation: committed,
      newLocation: intent.target,
      oldLocalIndex: _positionSession.committedReadingPosition,
      newLocalIndex: _currentPage,
      intent: intent,
    );
    if (mounted) setState(() {});
    _restoreAuthoritativeVisibleIndex(reason);
  }

  ReaderVisibleNavigationIntent<StableBookLocation>?
  _beginAdjacentBoundaryIntent({
    required DisplayRangeDirection direction,
    required StableBookLocation sourceAnchor,
    required SourceChunkRange? range,
  }) {
    StableBookLocation? candidate;
    if (range != null && !range.isEmpty) {
      final sourceIndex = direction == DisplayRangeDirection.forward
          ? range.start
          : range.endExclusive - 1;
      candidate = _sourceLocationsByChunkIndex[sourceIndex];
    }
    final session = _lazySession;
    if (candidate == null && session != null) {
      final targetSpine = direction == DisplayRangeDirection.forward
          ? session.nextReadableSpineIndex(sourceAnchor.spineIndex)
          : session.previousReadableSpineIndex(sourceAnchor.spineIndex);
      if (targetSpine != null) {
        final spine = session.index.spine[targetSpine];
        candidate = StableBookLocation(
          bookId: session.index.bookId,
          spineIndex: spine.index,
          href: spine.href,
          sourceChecksum: spine.sourceChecksum,
          publicationFingerprint: session.index.publicationFingerprint,
          normalizedHref: spine.normalizedHref,
          sectionProgression: direction == DisplayRangeDirection.forward
              ? 0
              : 1,
        );
      }
    }
    if (candidate == null) return null;
    final intent = _beginExplicitVisibleNavigation(
      candidate,
      direction == DisplayRangeDirection.forward
          ? 'next_page_boundary'
          : 'previous_page_boundary',
    );
    if (intent != null) _controllerIntent = intent;
    return intent;
  }

  Future<void> _completeAdjacentBoundaryNavigation({
    required DisplayRangeDirection direction,
    required int generation,
    required StableBookLocation sourceAnchor,
    required ReaderVisibleNavigationIntent<StableBookLocation> intent,
    required Duration duration,
    required Curve curve,
  }) async {
    const maxFrames = 40;
    for (var frame = 0; frame < maxFrames; frame++) {
      if (!mounted || !_visiblePositionCoordinator.isCurrent(intent)) return;
      if (generation != _rebuildGeneration) {
        _failControllerNavigationIntent(intent, 'stale_boundary_generation');
        return;
      }
      if (_displayChunks.isNotEmpty && _hasCompletedDisplayChunkBuild) {
        final sourceDisplayIndex = _displayIndexForStableAnchor(sourceAnchor);
        final targetDisplayIndex = sourceDisplayIndex == null
            ? null
            : direction == DisplayRangeDirection.forward
            ? sourceDisplayIndex + 1
            : sourceDisplayIndex - 1;
        if (targetDisplayIndex != null &&
            targetDisplayIndex >= 0 &&
            targetDisplayIndex < _displayChunks.length) {
          final targetLocation = _committedStableLocationForDisplay(
            targetDisplayIndex,
          );
          if (targetLocation != null &&
              _visiblePositionCoordinator.resolveIntentTarget(
                intent: intent,
                target: targetLocation,
                expectedWindowGeneration: _rebuildGeneration,
                expectedPublicationGeneration: _progressiveRangeGeneration,
              )) {
            _visiblePositionCoordinator.markWindowPublished(
              intent: intent,
              resolvedLocation: targetLocation,
              windowGeneration: _rebuildGeneration,
              publicationGeneration: _progressiveRangeGeneration,
            );
            _pendingExactStableRestore = null;
            _preferSourceIndexOnNextRestore = false;
            _animateReaderToPage(
              targetDisplayIndex,
              duration: duration,
              curve: curve,
              targetLocation: targetLocation,
              navigationIntent: intent,
            );
            return;
          }
        }
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    _failControllerNavigationIntent(intent, 'adjacent_target_unresolved');
    if (!mounted) return;
    setState(() {
      _progressiveRangeFailure = StateError(
        'The adjacent page could not be prepared. Retry to continue.',
      );
      _progressiveFailureRetry = () {
        _progressiveRangeFailure = null;
        _progressiveFailureRetry = null;
        if (direction == DisplayRangeDirection.forward) {
          _nextReaderPage(duration: duration, curve: curve);
        } else {
          _previousReaderPage(duration: duration, curve: curve);
        }
      };
    });
  }

  void _nextReaderPage({required Duration duration, required Curve curve}) {
    final sourceAnchor = _visiblePositionCoordinator.committedLocation;
    final sourceDisplayIndex = sourceAnchor == null
        ? null
        : _displayIndexForStableAnchor(sourceAnchor);
    if (sourceAnchor == null || sourceDisplayIndex == null) {
      _readerDiagLog('adjacent_navigation_failed', {
        'book': widget.bookId,
        'direction': DisplayRangeDirection.forward.name,
        'reason': 'committed_source_anchor_unresolved',
      });
      return;
    }
    if (sourceDisplayIndex >= _displayChunks.length - 1) {
      final state = _progressiveDisplayState;
      if (state != null &&
          (state.hasUnavailableAfter || _hasLazyContentAfter())) {
        _readerDiagLog('boundary_wait_begin', {
          'book': widget.bookId,
          'generation': _rebuildGeneration,
          'direction': DisplayRangeDirection.forward.name,
          'currentPage': _currentPage,
        });
        final range = state.nextForwardRange(_adjacentRangeSourceChunks);
        if (range != null || _hasLazyContentAfter()) {
          final intent = _beginAdjacentBoundaryIntent(
            direction: DisplayRangeDirection.forward,
            sourceAnchor: sourceAnchor,
            range: range,
          );
          if (intent == null) return;
          final rangeFuture =
              range == null || _isLazyForwardSentinelRange(range)
              ? _ensureAdjacentSectionAvailable(
                  DisplayRangeDirection.forward,
                  reason: 'next_page_at_loaded_window_boundary',
                )
              : _prepareProgressiveDisplayRange(
                  direction: DisplayRangeDirection.forward,
                  sourceRange: range,
                  reason: 'next_page_at_unprepared_boundary',
                ).then((_) => true);
          unawaited(
            rangeFuture.then((loaded) {
              _readerDiagLog('boundary_wait_end', {
                'book': widget.bookId,
                'generation': _rebuildGeneration,
                'direction': DisplayRangeDirection.forward.name,
              });
              if (!loaded) {
                _failControllerNavigationIntent(
                  intent,
                  'adjacent_window_unavailable',
                );
                return;
              }
              unawaited(
                _completeAdjacentBoundaryNavigation(
                  direction: DisplayRangeDirection.forward,
                  generation: _rebuildGeneration,
                  sourceAnchor: sourceAnchor,
                  intent: intent,
                  duration: duration,
                  curve: curve,
                ),
              );
            }),
          );
        }
      }
      return;
    }
    final targetIndex = sourceDisplayIndex + 1;
    _animateReaderToPage(
      targetIndex,
      duration: duration,
      curve: curve,
      targetLocation: _committedStableLocationForDisplay(targetIndex),
    );
  }

  void _previousReaderPage({required Duration duration, required Curve curve}) {
    final sourceAnchor = _visiblePositionCoordinator.committedLocation;
    final sourceDisplayIndex = sourceAnchor == null
        ? null
        : _displayIndexForStableAnchor(sourceAnchor);
    if (sourceAnchor == null || sourceDisplayIndex == null) {
      _readerDiagLog('adjacent_navigation_failed', {
        'book': widget.bookId,
        'direction': DisplayRangeDirection.backward.name,
        'reason': 'committed_source_anchor_unresolved',
      });
      return;
    }
    if (sourceDisplayIndex <= 0) {
      final state = _progressiveDisplayState;
      if (state != null &&
          (state.hasUnavailableBefore ||
              _lazyHasContentBeforeOutsideLoadedWindow())) {
        _readerDiagLog('boundary_wait_begin', {
          'book': widget.bookId,
          'generation': _rebuildGeneration,
          'direction': DisplayRangeDirection.backward.name,
          'currentPage': _currentPage,
        });
        final range = state.nextBackwardRange(_adjacentRangeSourceChunks);
        if (range != null || _lazyHasContentBeforeOutsideLoadedWindow()) {
          final intent = _beginAdjacentBoundaryIntent(
            direction: DisplayRangeDirection.backward,
            sourceAnchor: sourceAnchor,
            range: range,
          );
          if (intent == null) return;
          final rangeFuture =
              range == null ||
                  (_lazySession != null &&
                      _lazyHasContentBeforeOutsideLoadedWindow() &&
                      sourceDisplayIndex <= 0)
              ? _ensureAdjacentSectionAvailable(
                  DisplayRangeDirection.backward,
                  reason: 'previous_page_at_loaded_window_boundary',
                )
              : _prepareProgressiveDisplayRange(
                  direction: DisplayRangeDirection.backward,
                  sourceRange: range,
                  reason: 'previous_page_at_unprepared_boundary',
                ).then((_) => true);
          unawaited(
            rangeFuture.then((loaded) {
              _readerDiagLog('boundary_wait_end', {
                'book': widget.bookId,
                'generation': _rebuildGeneration,
                'direction': DisplayRangeDirection.backward.name,
              });
              if (!mounted) return;
              if (!loaded) {
                _failControllerNavigationIntent(
                  intent,
                  'adjacent_window_unavailable',
                );
                return;
              }
              unawaited(
                _completeAdjacentBoundaryNavigation(
                  direction: DisplayRangeDirection.backward,
                  generation: _rebuildGeneration,
                  sourceAnchor: sourceAnchor,
                  intent: intent,
                  duration: duration,
                  curve: curve,
                ),
              );
            }),
          );
        }
      }
      return;
    }
    final targetIndex = sourceDisplayIndex - 1;
    _animateReaderToPage(
      targetIndex,
      duration: duration,
      curve: curve,
      targetLocation: _committedStableLocationForDisplay(targetIndex),
    );
  }

  Future<void> _setNativeReaderControls({
    required bool readerVisible,
    bool? volumePagingEnabled,
  }) async {
    try {
      await _readerControlsChannel
          .invokeMethod<void>('setReaderControlsState', {
            'readerVisible': readerVisible,
            'volumePagingEnabled':
                volumePagingEnabled ?? _settings.useVolumeButtonsForPaging,
          });
    } catch (_) {
      // Native support is optional outside Android.
    }
  }

  Future<void> _syncNativeReaderControlsState() async {
    await _setNativeReaderControls(readerVisible: _isReaderInteractable);
  }

  Future<void> _handleReaderControlMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'volumePagePressStart':
        _startHardwarePagePress((call.arguments as num?)?.toInt() ?? 0);
        break;
      case 'volumePagePressEnd':
        _stopHardwarePagePress();
        break;
      case 'volumeNextPage':
        _turnPageFromHardware(1);
        break;
      case 'volumePreviousPage':
        _turnPageFromHardware(-1);
        break;
    }
  }

  void _blockReaderControls() {
    _stopHardwarePagePress();
    _lastInsightDisplayIndex = null;
    _lastInsightStartedAt = null;
    if (_readerSurfaceBlockCount == 0 &&
        _speedReadController.isActive &&
        !_speedReadController.isPaused) {
      _speedReadController.pause();
      _speedReadReaderBlockAutoPaused = true;
    }
    if (mounted) {
      setState(() => _readerSurfaceBlockCount++);
    } else {
      _readerSurfaceBlockCount++;
    }
    unawaited(_syncNativeReaderControlsState());
  }

  void _unblockReaderControls() {
    if (_readerSurfaceBlockCount > 0) {
      if (mounted) {
        setState(() => _readerSurfaceBlockCount--);
      } else {
        _readerSurfaceBlockCount--;
      }
    }
    _lastInsightDisplayIndex = _currentPage;
    _lastInsightStartedAt = DateTime.now();
    unawaited(_syncNativeReaderControlsState());
    if (_readerSurfaceBlockCount == 0 && _speedReadReaderBlockAutoPaused) {
      _speedReadReaderBlockAutoPaused = false;
      _resumeAutoPausedSpeedReadIfReady();
    }
  }

  Future<T> _runWithReaderControlsSuspended<T>(
    Future<T> Function() action,
  ) async {
    _blockReaderControls();
    try {
      return await action();
    } finally {
      _unblockReaderControls();
    }
  }

  _ReaderVisiblePositionSnapshot _captureVisibleReaderPosition({
    int? preferredDisplayIndex,
  }) {
    if (_displayChunks.isEmpty) {
      return const _ReaderVisiblePositionSnapshot(displayIndex: 0);
    }

    final displayIndex = (preferredDisplayIndex ?? _activeDisplayIndex).clamp(
      0,
      _displayChunks.length - 1,
    );
    final chunk = _displayChunks[displayIndex];
    final originals = displayIndex < _displayToOriginal.length
        ? List<int>.from(_displayToOriginal[displayIndex])
        : const <int>[];

    double? controllerPage;
    final controller = _pageController;
    if (!_usesInteractiveCardDeck && controller?.hasClients == true) {
      controllerPage = controller!.page;
    }

    return _ReaderVisiblePositionSnapshot(
      displayIndex: displayIndex,
      pageControllerPage: controllerPage,
      pageControllerIndex: controllerPage?.round(),
      sourceAnchor: _buildPageAnchor(chunk),
      sourceOriginalCandidates: originals,
      displayChunkCount: _displayChunks.length,
      cardMode: _settings.enableCardDepth,
      densityMultiplier: _settings.densityMultiplier,
      hasPreferredDisplayIndex: preferredDisplayIndex != null,
    );
  }

  Future<T> _runWithReaderPositionPreserved<T>(
    Future<T> Function() action, {
    int? visibleDisplayIndex,
  }) async {
    final capturedPosition = _captureVisibleReaderPosition(
      preferredDisplayIndex: visibleDisplayIndex,
    );
    final capturedIndex = capturedPosition.displayIndex;
    await _flushPendingReadingPosition();
    _cancelPreviewPromotionTimer();
    _positionSaveTimer?.cancel();
    _positionPersistenceQueue.clear();
    _pendingPreviewJumpDisplayIndex = null;
    _positionSession.beginModalState(capturedIndex);
    if (_isScrubbing || _scrubPreviewDisplayIndex != null) {
      setState(() {
        _isScrubbing = false;
        _scrubPreviewDisplayIndex = null;
        _scrubStartDisplayIndex = null;
      });
    }

    try {
      return await _runWithReaderControlsSuspended(action);
    } finally {
      _positionSession.endModalState();
      final restoreIndex = _resolveVisibleReaderPosition(capturedPosition);
      if (mounted) {
        _restoreVisibleReaderPosition(restoreIndex, scheduleFollowUp: true);
      }
    }
  }

  int _resolveVisibleReaderPosition(_ReaderVisiblePositionSnapshot snapshot) {
    if (_displayChunks.isEmpty) return 0;

    final index = snapshot.displayIndex.clamp(0, _displayChunks.length - 1);
    final layoutUnchanged =
        snapshot.displayChunkCount == _displayChunks.length &&
        snapshot.cardMode == _settings.enableCardDepth &&
        snapshot.densityMultiplier == _settings.densityMultiplier;
    final controllerIndex = snapshot.pageControllerIndex;
    final controllerPage = snapshot.pageControllerPage;
    final controllerIsSettled =
        controllerIndex != null &&
        controllerPage != null &&
        (controllerPage - controllerIndex).abs() < 0.01;
    if (layoutUnchanged) {
      if (!snapshot.hasPreferredDisplayIndex &&
          snapshot.cardMode == false &&
          controllerIsSettled) {
        return controllerIndex.clamp(0, _displayChunks.length - 1);
      }
      return index;
    }

    final anchor = snapshot.sourceAnchor;
    final candidates = snapshot.sourceOriginalCandidates;
    if (anchor != null && candidates.isNotEmpty) {
      return _findDisplayIndexForAnchor(
        anchor: anchor,
        preferredOriginalIndex: candidates.first,
        expectedDisplayIndex: index,
        preferredOriginalCandidates: candidates,
      ).clamp(0, _displayChunks.length - 1);
    }

    return _findNearestByOriginalOverlap(
      expectedDisplayIndex: index,
      preferredOriginalCandidates: candidates,
    ).clamp(0, _displayChunks.length - 1);
  }

  void _restoreVisibleReaderPosition(
    int index, {
    bool scheduleFollowUp = false,
  }) {
    if (_displayChunks.isEmpty) return;
    final clamped = index.clamp(0, _displayChunks.length - 1);
    _logVisiblePositionMutation(
      reason: 'modal_route_visible_index_restore',
      classification: ReaderVisibleMutationClassification.synthetic,
      accepted: true,
      decisionReason: 'derived_index_hint_updated_from_preserved_anchor',
      oldLocation: _currentStableLocation(),
      newLocation: _committedStableLocationForDisplay(clamped),
      oldLocalIndex: _currentPage,
      newLocalIndex: clamped,
    );
    _currentPage = clamped;
    _activeDisplayIndex = clamped;
    _positionSession.markVisible(clamped);
    _syntheticControllerTargetIndex = clamped;
    _syncRestoreTargetFromDisplayIndex(clamped);

    if (scheduleFollowUp) {
      final restoreGeneration = _positionSession.navigationGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _positionSession.navigationGeneration != restoreGeneration) {
          return;
        }
        _restoreVisibleReaderPosition(clamped);
      });
    }

    if (_usesInteractiveCardDeck || _pageController?.hasClients != true) {
      setState(() {});
      return;
    }

    _logVisiblePositionMutation(
      reason: 'modal_route_position_restore',
      classification: ReaderVisibleMutationClassification.synthetic,
      accepted: true,
      decisionReason: 'modal_anchor_preserved',
      oldLocation: _visiblePositionCoordinator.committedLocation,
      newLocation: _committedStableLocationForDisplay(clamped),
      oldLocalIndex: _positionSession.committedReadingPosition,
      newLocalIndex: clamped,
    );
    _pageController!.jumpToPage(clamped);
    setState(() {});
  }

  void _startHardwarePagePress(int delta) {
    if (delta == 0) return;
    _stopHardwarePagePress();
    if (!_turnPageFromHardware(delta)) return;

    _hardwarePageRepeatDelta = delta;
    _hardwarePageRepeatStartTimer = Timer(_hardwarePageRepeatInitialDelay, () {
      final repeatDelta = _hardwarePageRepeatDelta;
      if (repeatDelta == null || !_turnPageFromHardware(repeatDelta)) {
        _stopHardwarePagePress();
        return;
      }
      _hardwarePageRepeatTimer = Timer.periodic(_hardwarePageRepeatInterval, (
        _,
      ) {
        final periodicDelta = _hardwarePageRepeatDelta;
        if (periodicDelta == null || !_turnPageFromHardware(periodicDelta)) {
          _stopHardwarePagePress();
        }
      });
    });
  }

  void _stopHardwarePagePress() {
    _hardwarePageRepeatStartTimer?.cancel();
    _hardwarePageRepeatStartTimer = null;
    _hardwarePageRepeatTimer?.cancel();
    _hardwarePageRepeatTimer = null;
    _hardwarePageRepeatDelta = null;
  }

  bool _turnPageFromHardware(int delta) {
    if (!_isReaderInteractable || !_settings.useVolumeButtonsForPaging) {
      return false;
    }

    final lastPage = _displayChunks.length - 1;
    if (delta > 0) {
      if (_currentPage >= lastPage) return false;
      _nextReaderPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return true;
    }

    if (_currentPage <= 0) return false;
    _previousReaderPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  String _normalizeForAnchor(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _extractOpeningSentence(String normalized) {
    final match = RegExp(r'^.{20,220}?[.!?](?:\s|$)').firstMatch(normalized);
    if (match != null) {
      final sentence = (match.group(0) ?? '').trim();
      if (sentence.length >= 20) return sentence;
    }
    if (normalized.length <= _positionAnchorLength) return normalized;
    return normalized.substring(0, _positionAnchorLength);
  }

  _PageAnchor? _buildPageAnchor(BookChunk chunk) {
    final raw = chunk.text;
    if (raw == null || raw.trim().isEmpty) return null;

    final normalized = _normalizeForAnchor(raw);
    if (normalized.isEmpty) return null;

    final opening = _extractOpeningSentence(normalized);
    final middleStart = (normalized.length * 0.35).floor().clamp(
      0,
      normalized.length,
    );
    final middle = middleStart >= normalized.length
        ? normalized
        : normalized.substring(
            middleStart,
            (middleStart + _positionAnchorLength).clamp(0, normalized.length),
          );

    return _PageAnchor(opening: opening, middle: middle);
  }

  int _findDisplayIndexForAnchor({
    required _PageAnchor anchor,
    required int preferredOriginalIndex,
    required int expectedDisplayIndex,
    required List<int> preferredOriginalCandidates,
  }) {
    int bestIdx = expectedDisplayIndex.clamp(0, _displayChunks.length - 1);
    double bestScore = double.negativeInfinity;
    bool foundAnchorMatch = false;

    for (int i = 0; i < _displayChunks.length; i++) {
      final normalized = _normalizeForAnchor(_displayChunks[i].text ?? '');
      if (normalized.isEmpty) continue;

      final hasOpening = normalized.contains(anchor.opening);
      final hasMiddle =
          anchor.middle.isNotEmpty && normalized.contains(anchor.middle);
      if (!hasOpening && !hasMiddle) continue;
      foundAnchorMatch = true;

      final originals = i < _displayToOriginal.length
          ? _displayToOriginal[i]
          : const <int>[];

      double score = 0.0;
      if (hasOpening) score += 1000.0;
      if (hasMiddle) score += 1000.0;
      final overlapCount = originals
          .where((o) => preferredOriginalCandidates.contains(o))
          .length;
      if (overlapCount > 0) {
        // Strongest signal: this rebuilt card still maps to the same source chunks.
        score += 500.0 + (overlapCount * 40.0);
      }

      if (originals.contains(preferredOriginalIndex)) {
        score += 250.0;
      } else if (originals.isNotEmpty) {
        final nearestDistance = originals
            .map((o) => (o - preferredOriginalIndex).abs())
            .reduce((a, b) => a < b ? a : b);
        score += (120 - nearestDistance.toDouble()).clamp(0, 120);
      }

      score -= (i - expectedDisplayIndex).abs() * 3.0;

      if (score > bestScore) {
        bestScore = score;
        bestIdx = i;
      }
    }

    if (foundAnchorMatch) return bestIdx;
    if (preferredOriginalCandidates.isNotEmpty) {
      int nearestByOriginalSet = expectedDisplayIndex.clamp(
        0,
        _displayChunks.length - 1,
      );
      int nearestDist = 1 << 30;
      for (int i = 0; i < _displayToOriginal.length; i++) {
        final originals = _displayToOriginal[i];
        final hasOverlap = originals.any(
          (o) => preferredOriginalCandidates.contains(o),
        );
        if (!hasOverlap) continue;
        final d = (i - expectedDisplayIndex).abs();
        if (d < nearestDist) {
          nearestDist = d;
          nearestByOriginalSet = i;
        }
      }
      return nearestByOriginalSet;
    }
    return expectedDisplayIndex.clamp(0, _displayChunks.length - 1);
  }

  int _findNearestByOriginalOverlap({
    required int expectedDisplayIndex,
    required List<int> preferredOriginalCandidates,
  }) {
    if (_displayChunks.isEmpty) return 0;
    final expected = expectedDisplayIndex.clamp(0, _displayChunks.length - 1);
    if (preferredOriginalCandidates.isEmpty) return expected;

    int bestIdx = expected;
    int bestDist = 1 << 30;
    int bestOverlap = -1;

    for (int i = 0; i < _displayToOriginal.length; i++) {
      final originals = _displayToOriginal[i];
      if (originals.isEmpty) continue;
      final overlap = originals
          .where((o) => preferredOriginalCandidates.contains(o))
          .length;
      if (overlap == 0) continue;

      final dist = (i - expected).abs();
      if (overlap > bestOverlap ||
          (overlap == bestOverlap && dist < bestDist)) {
        bestOverlap = overlap;
        bestDist = dist;
        bestIdx = i;
      }
    }

    return bestIdx;
  }

  // ─── Initialization ──────────────────────────────────────────────────

  bool _paletteContainsColor(List<Color> palette, Color color) {
    return palette.any((entry) => isSameHighlightColor(entry, color));
  }

  Color _fallbackHighlightColor(List<Color> palette) {
    if (palette.isEmpty) return kHighlightColors.last;
    return palette.last;
  }

  void _ensureCanonicalSourceIdentity() {
    final session = _lazySession;
    if (session != null) {
      _publicationFingerprint = session.index.publicationFingerprint;
      return;
    }
    if (_publicationFingerprint != null &&
        _sourceLocationsByChunkIndex.length == _sourceChunks.length) {
      return;
    }

    final sectionPayloads = <String, List<Object?>>{};
    for (final chunk in _sourceChunks) {
      final section = chunk.sourceFile ?? 'eager:${chunk.section.name}';
      sectionPayloads.putIfAbsent(section, () => <Object?>[]).add({
        'logicalBlockId': chunk.logicalParagraphId,
        'type': chunk.type.name,
        'role': chunk.blockRole.name,
        'textChecksum': readerSha256(chunk.text ?? ''),
        'imageChecksum': chunk.imageBytes == null
            ? null
            : readerSha256(chunk.imageBytes!),
      });
    }
    final sectionChecksums = <String, String>{
      for (final entry in sectionPayloads.entries)
        entry.key: readerSha256(entry.value),
    };
    _publicationFingerprint = readerSha256({
      'bookId': widget.bookId,
      'sections': sectionChecksums,
      'parserVersion': BookCacheService.parsedBookCacheFormatVersion,
    });

    _sourceLocationsByChunkIndex = <int, StableBookLocation>{};
    final localOrdinals = <String, int>{};
    for (var index = 0; index < _sourceChunks.length; index++) {
      final chunk = _sourceChunks[index];
      final href = chunk.sourceFile ?? 'eager:${chunk.section.name}';
      final local = localOrdinals[href] ?? 0;
      localOrdinals[href] = local + 1;
      _sourceLocationsByChunkIndex[index] = StableBookLocation(
        bookId: widget.bookId,
        spineIndex: sectionPayloads.keys.toList().indexOf(href),
        href: href,
        normalizedHref: href,
        sourceChecksum: sectionChecksums[href]!,
        publicationFingerprint: _publicationFingerprint,
        localChunkIndex: local,
        legacyGlobalChunkIndex: index,
        sourceParserVersion:
            'eager_${BookCacheService.parsedBookCacheFormatVersion}',
        contextText: chunk.text,
      );
    }
    _publishedSourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
      _sourceLocationsByChunkIndex,
    );
  }

  List<CanonicalPaginationSourceKey> _canonicalPaginationSourceKeys(
    List<BookChunk> chunks, {
    Map<int, StableBookLocation> locations = const {},
    Map<int, LazySourceChunkIdentity> identities = const {},
  }) {
    final publication = _publicationFingerprint ?? widget.bookId;
    return <CanonicalPaginationSourceKey>[
      for (var ordinal = 0; ordinal < chunks.length; ordinal++)
        (() {
          final chunk = chunks[ordinal];
          final location = locations[ordinal];
          final lazyIdentity = identities[ordinal];
          final href =
              location?.normalizedHref ??
              location?.href ??
              chunk.sourceFile ??
              'section:${chunk.section.name}';
          final sectionIdentity =
              lazyIdentity?.section.stableKey ??
              readerSha256(<String, Object?>{
                'publication': publication,
                'spine': location?.spineIndex,
                'href': href,
                'sourceChecksum': location?.sourceChecksum,
              });
          final logicalOwner = chunk.logicalParagraphId;
          if (lazyIdentity == null &&
              (logicalOwner == null || logicalOwner.isEmpty)) {
            throw StateError(
              'Canonical source ownership requires a parser-stable logical '
              'owner for ${chunk.type.name} content in $href.',
            );
          }
          final sourceIdentity =
              lazyIdentity?.stableKey ??
              readerSha256(<String, Object?>{
                'section': sectionIdentity,
                'logicalOwner': logicalOwner,
                'sourceType': chunk.type.name,
                'structuralRole': chunk.type == BookChunkType.text
                    ? chunk.blockRole.name
                    : chunk.type.name,
              });
          return CanonicalPaginationSourceKey(
            sourceIdentity: sourceIdentity,
            sectionIdentity: sectionIdentity,
            spineIdentity: sectionIdentity,
            sourceOrdinalHint: ordinal,
          );
        })(),
    ];
  }

  String _canonicalPaginationSourceRevision(List<BookChunk> chunks) =>
      readerSha256(<String, Object?>{
        'publication': _publicationFingerprint ?? widget.bookId,
        'sources': chunks
            .map((chunk) => chunk.toJson())
            .toList(growable: false),
      });

  String _canonicalParserSourceIdentity(
    Map<int, StableBookLocation> locations,
  ) {
    final versions =
        locations.values
            .map((location) => location.sourceParserVersion)
            .whereType<String>()
            .toSet()
            .toList(growable: false)
          ..sort();
    return versions.isEmpty
        ? 'parsed:${BookCacheService.parsedBookCacheFormatVersion}'
        : readerSha256(versions);
  }

  ReaderCheckpointCoordinator _createCheckpointCoordinator() {
    _checkpointStore.trace ??= _readerDiagLog;
    return ReaderCheckpointCoordinator(
      store: _checkpointStore,
      bookId: widget.bookId,
      publicationFingerprint: _publicationFingerprint!,
      trace: (event, fields) {
        _readerDiagLog(event, {'book': widget.bookId, ...fields});
      },
    );
  }

  Future<void> _initReadingPosition() async {
    if (_sourceChunks.isEmpty) {
      setState(() => _ready = true);
      return;
    }

    _ensureCanonicalSourceIdentity();
    await _metadataService.init();
    await _statsService.init();
    _highestMeasuredOriginalIndex = _statsService
        .getBookInsights(widget.bookId)
        .highestMeasuredOriginalIndex;
    final metadata = _metadataService.getMetadata(widget.bookId);

    _prefs = await SharedPreferences.getInstance();
    final key = 'last_read_${widget.bookId}';
    int lastIndex = _prefs!.getInt(key) ?? 0;
    final savedAnnotationsTab = _annotationPanelTabFromName(
      _prefs!.getString(_readerDrawerLastTabKey),
    );

    if (metadata != null && metadata.lastReadIndex > 0) {
      lastIndex = metadata.lastReadIndex;
    }

    final initialOriginalChunkIndex = widget.initialOriginalChunkIndex;
    final initialStableIndex = widget.initialStableLocation == null
        ? null
        : _sourceIndexForStableLocation(widget.initialStableLocation!);
    _targetOriginalIndex =
        (initialOriginalChunkIndex ?? initialStableIndex ?? lastIndex)
            .clamp(0, _sourceChunks.length - 1)
            .toInt();
    if (widget.initialStableLocation != null) {
      _readerDiagLog('stable_location_initial_restore', {
        ..._stableLocationDiagFields(widget.initialStableLocation!),
        'resolvedOriginalIndex': initialStableIndex,
        'targetOriginalIndex': _targetOriginalIndex,
        'usedStableLocation': initialStableIndex != null,
      });
    }

    final bookmarks = await _bookmarkService.load();
    final defaultBookmarkColor = await _bookmarkService.loadDefaultColor();
    final loadedDefaultBookmarkColorIndex =
        defaultBookmarkColorIndex(defaultBookmarkColor) ?? 0;
    final highlights = await _highlightService.load();
    final highlightPalette = await _highlightPaletteService.loadPalette();
    var defaultHighlightColor = await _highlightPaletteService
        .loadDefaultColor();
    if (!_paletteContainsColor(highlightPalette, defaultHighlightColor)) {
      defaultHighlightColor = _fallbackHighlightColor(highlightPalette);
      await _highlightPaletteService.saveDefaultColor(defaultHighlightColor);
    }
    var settings = await _settingsService.loadSettings();
    final coordinator = _checkpointCoordinator ??=
        _createCheckpointCoordinator();
    final checkpoint = coordinator.isInitialized
        ? coordinator.current
        : await coordinator.initialize(
            preloaded: _preloadedCheckpoint,
            ignoreStored: widget.initialLocationIsNavigationTarget,
          );
    final pendingLayoutSettings =
        checkpoint?.state == ReaderCheckpointState.layoutTransitionPending
        ? checkpoint?.targetLayoutSettings
        : null;
    if (pendingLayoutSettings != null) {
      settings = ReadingSettings.fromPresetJson(pendingLayoutSettings);
      await _settingsService.saveSettings(settings);
      _readerDiagLog('restore_pending_layout_settings_applied', {
        'book': widget.bookId,
        'savedLayoutFingerprint': checkpoint?.layoutFingerprint,
      });
    }
    final canonicalStableLocation = checkpoint?.stableLocation;
    if (canonicalStableLocation != null) {
      _pendingExactStableRestore = canonicalStableLocation;
      _preferSourceIndexOnNextRestore = true;
      final canonicalSourceIndex = _sourceIndexForStableLocation(
        canonicalStableLocation,
      );
      if (canonicalSourceIndex != null) {
        _targetOriginalIndex = canonicalSourceIndex;
      }
    } else if (checkpoint != null) {
      final canonicalSourceIndex = _sourceChunks.indexWhere(
        (chunk) =>
            chunk.logicalParagraphId ==
            checkpoint.semanticAnchor.logicalBlockId,
      );
      if (canonicalSourceIndex >= 0) {
        _targetOriginalIndex = canonicalSourceIndex;
      }
    }
    await _loadPositionHistory();

    // Inject the book's custom theme overrides specifically into the reader settings
    final metadataRaw = _metadataService.getMetadata(widget.bookId);
    final bookThemePalette = await _bookReaderThemeService.loadPalette(
      metadataRaw?.coverImagePath,
    );

    setState(() {
      _bookmarks = bookmarks;
      _defaultBookmarkColorIndex = loadedDefaultBookmarkColorIndex;
      _defaultBookmarkColor = Color(bookmarkColorValue(defaultBookmarkColor));
      _highlights = highlights;
      _highlightPalette = highlightPalette;
      _defaultHighlightColor = Color(
        highlightColorValue(defaultHighlightColor),
      );
      _lastAnnotationsTab =
          savedAnnotationsTab ?? AnnotationPanelTab.highlights;
      _settings = settings.copyWith(
        readerTheme: metadataRaw?.theme,
        clearReaderTheme: metadataRaw?.theme == null,
        bookThemePalette: bookThemePalette,
        clearBookThemePalette: bookThemePalette == null,
      );
      _ready = true;
    });
    _speedReadController.setWPM(_settings.speedReadWPM);
    _speedReadController.setAdaptivePacing(_settings.speedReadAdaptivePacing);
    unawaited(_syncNativeReaderControlsState());
  }

  Future<void> _startDirectContinueOpen() async {
    final file = widget.directContinueFile;
    if (file == null || _directOpenInProgress) return;

    final operation = ReaderOpenOperation();
    _directOpenOperation?.cancel();
    _directOpenOperation = operation;
    setState(() {
      _directOpenInProgress = true;
      _directOpenFailure = null;
    });
    _readerDiagLog('continue_tapped', {
      'book': widget.bookId,
      'path': file.path,
      'readerInstanceId': identityHashCode(this),
      'readerRouteId': identityHashCode(context),
      'readerOpenOperationId': identityHashCode(operation),
      'lastReadIndex': widget.directContinueMetadata?.lastReadIndex,
      'hasStableLastReadLocation':
          widget.directContinueMetadata?.lastReadLocation != null,
    });

    try {
      final result = await _readerOpenService.openLazy(
        bookFile: file,
        metadata: widget.directContinueMetadata,
        requestedLocation: widget.directContinueMetadata?.lastReadLocation,
        legacyLastReadIndex: widget.directContinueMetadata?.lastReadIndex,
        operation: operation,
        caller: 'direct_continue',
      );
      if (!mounted || operation.isCancelled) {
        await result.session.close();
        return;
      }
      _applyReaderOpenResult(result);
      await _initReadingPosition();
    } on ReaderOpenException catch (e) {
      if (!mounted || operation.isCancelled) return;
      _readerDiagLog('direct_continue_open_failed', {
        'book': widget.bookId,
        'kind': e.kind.name,
        'message': e.message,
        'cause': e.cause?.runtimeType,
      });
      setState(() {
        _directOpenInProgress = false;
        _directOpenFailure = e;
      });
    } catch (e) {
      if (!mounted || operation.isCancelled) return;
      _readerDiagLog('direct_continue_open_failed', {
        'book': widget.bookId,
        'kind': ReaderOpenFailureKind.unknown.name,
        'message': 'Failed to open book',
        'cause': e.runtimeType,
      });
      setState(() {
        _directOpenInProgress = false;
        _directOpenFailure = ReaderOpenException(
          ReaderOpenFailureKind.unknown,
          'Failed to open book',
          e,
        );
      });
    } finally {
      if (identical(_directOpenOperation, operation)) {
        _directOpenOperation = null;
      }
    }
  }

  void _applyReaderOpenResult(ReaderOpenResult result) {
    final previousSession = _lazySession;
    final previousDerivedIndexSession = _derivedIndexSession;
    _derivedIndexSession = DerivedBookIndexSession(source: result.session);
    if (previousDerivedIndexSession != null) {
      unawaited(previousDerivedIndexSession.dispose());
    }
    if (previousSession != null &&
        !identical(previousSession, result.session)) {
      unawaited(previousSession.close());
    }

    final loadedSpines = result.window.locationsByChunkIndex.values
        .map((location) => location.spineIndex)
        .toSet();
    _preloadedCheckpoint = result.checkpoint;
    _publicationFingerprint = result.session.index.publicationFingerprint;
    setState(() {
      _lazySession = result.session;
      _sourceChunks = List<BookChunk>.from(result.window.chunks);
      _sourceAnchorMap = Map<String, int>.from(result.window.anchorMap);
      _sourceChapters = List<ChapterInfo>.from(result.window.chapters);
      _sourceSearchIndex = Map<String, List<int>>.from(
        result.window.searchIndex,
      );
      _sourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
        result.window.locationsByChunkIndex,
      );
      _sourceIdentitiesByChunkIndex = Map<int, LazySourceChunkIdentity>.from(
        result.window.sourceIdentitiesByChunkIndex,
      );
      _publishedSourceChunks = List<BookChunk>.from(_sourceChunks);
      _publishedSourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
        _sourceLocationsByChunkIndex,
      );
      _publishedSourceIdentitiesByChunkIndex =
          Map<int, LazySourceChunkIdentity>.from(_sourceIdentitiesByChunkIndex);
      _cachedFlatChapters = null;
      _lazyHasContentAfter = result.window.hasContentAfter;
      _lazyMaxLoadedSpineIndex = loadedSpines.isEmpty
          ? null
          : loadedSpines.reduce(math.max);
      _pendingExactStableRestore = result.targetLocation;
      _preferSourceIndexOnNextRestore = true;
      _isFirstLayout = true;
      _hasResolvedInitialLocation = false;
      _lastScreenSize = null;
      _lastSafeArea = null;
      _lastTextScaler = null;
      _displayChunks.clear();
      _displayToOriginal.clear();
      _originalToDisplay.clear();
      _displaySectionMemoryCache.clear();
      _displayChunksComplete = false;
      _hasCompletedDisplayChunkBuild = false;
      _lazyInitialAdjacentWarmupStarted = false;
      _lazyParsedHydrationStarted = false;
      _isRebuildingChunks = false;
      _ready = false;
      _directOpenInProgress = false;
      _directOpenFailure = null;
    });
    _readerDiagLog('lazy_reader_open_end', {
      'book': result.bookId,
      'caller': 'direct_continue',
      'lazySessionId': identityHashCode(result.session),
      'elapsedMs': result.elapsedMs,
    });
  }

  Widget _buildDirectContinuePreparing() {
    return Scaffold(
      backgroundColor: _settings.backgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _settings.mutedColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Preparing page...',
              style: TextStyle(color: _settings.mutedColor, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectContinueError(ReaderOpenException failure) {
    return Scaffold(
      backgroundColor: _settings.backgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: _settings.mutedColor,
                  size: 38,
                ),
                const SizedBox(height: 18),
                Text(
                  failure.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _settings.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The saved book file could not be opened from its last known location.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _settings.mutedColor, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: _startDirectContinueOpen,
                      child: const Text('Retry'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BookListScreen(),
                          ),
                        );
                      },
                      child: const Text('Browse Library'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _checkpointStore.deleteBook(widget.bookId);
                        await _metadataService.deleteMetadata(widget.bookId);
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text('Remove unavailable entry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReaderPreparationError(Object failure) {
    final message = failure is ReaderPreparationException
        ? failure.message
        : 'This page could not be prepared.';
    return Scaffold(
      backgroundColor: _settings.backgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: _settings.mutedColor,
                  size: 38,
                ),
                const SizedBox(height: 18),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _settings.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: () {
                        _displayGenerationCoordinator.clearFailure();
                        setState(() {
                          _progressiveRangeFailure = null;
                          _progressiveFailureRetry = null;
                          _lastScreenSize = null;
                          _lastSafeArea = null;
                          _lastTextScaler = null;
                          _hasCompletedDisplayChunkBuild = false;
                        });
                      },
                      child: const Text('Retry'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: const Text('Back to library'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _maybeShowReaderGestureHint() async {
    if (_readerGestureHintCheckStarted) return;
    _readerGestureHintCheckStarted = true;

    final hasSeen = await _educationService.hasSeenReaderGestureHint();
    if (hasSeen) return;

    await _educationService.markReaderGestureHintSeen();
    if (!mounted) return;
    setState(() {
      _showReaderGestureHint = true;
    });
    _readerGestureHintTimer?.cancel();
    _readerGestureHintTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _showReaderGestureHint = false;
      });
    });
  }

  void _dismissReaderGestureHint() {
    _readerGestureHintTimer?.cancel();
    unawaited(_educationService.markReaderGestureHintSeen());
    if (!_showReaderGestureHint) return;
    setState(() {
      _showReaderGestureHint = false;
    });
  }

  void _ensureDisplayChunksBuilt(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
  ) {
    final displaySafeArea = _canonicalDisplaySafeArea(safeArea);
    if (_lastScreenSize == screenSize &&
        _lastSafeArea == displaySafeArea &&
        _lastTextScaler == textScaler &&
        _displayChunks.isNotEmpty) {
      return;
    }

    final layoutRestoreTarget = _captureLayoutRestoreTarget();

    _lastScreenSize = screenSize;
    _lastSafeArea = displaySafeArea;
    _lastTextScaler = textScaler;
    _hasCompletedDisplayChunkBuild = false;
    _displayChunksComplete = false;
    final layoutLocale =
        Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'und';

    final cacheKey = BookCacheService.displayChunkKey(
      bookId: widget.bookId,
      fontSize: _settings.fontSizeValue,
      fontFamily: _settings.fontFamily.name,
      fontWeight: _settings.fontWeight.name,
      fontMetricIdentity: _settings.fontMetricIdentity,
      locale: layoutLocale,
      density: _settings.densityMultiplier,
      lineHeight: _settings.lineHeight,
      paragraphSpacing: _settings.paragraphSpacing,
      sideMargin: _settings.sideMargin,
      screenW: screenSize.width,
      screenH: screenSize.height,
      enableCardDepth: _settings.enableCardDepth,
      textScaleFactor: textScaler.scale(1.0),
      safeAreaTop: displaySafeArea.top,
      safeAreaBottom: displaySafeArea.bottom,
      safeAreaLeft: displaySafeArea.left,
      safeAreaRight: displaySafeArea.right,
    );
    final displaySignature = {
      'book': widget.bookId,
      'parsedCacheVersion': BookCacheService.parsedBookCacheFormatVersion,
      'displayCacheVersion': BookCacheService.displayCacheFormatVersion,
      'layoutVersion': BookCacheService.displayLayoutVersion,
      'fontSize': _settings.fontSizeValue,
      'fontFamily': _settings.fontFamily.name,
      'fontWeight': _settings.fontWeight.name,
      'typographyVersion': readerTypographyNormalizationVersion,
      'fontMetricIdentity': _settings.fontMetricIdentity,
      'locale': layoutLocale,
      'density': _settings.densityMultiplier,
      'lineHeight': _settings.lineHeight,
      'paragraphSpacing': _settings.paragraphSpacing,
      'sideMargin': _settings.sideMargin,
      'screenW': screenSize.width,
      'screenH': screenSize.height,
      'enableCardDepth': _settings.enableCardDepth,
      'textScaleFactor': textScaler.scale(1.0),
      'safeAreaTop': displaySafeArea.top,
      'safeAreaBottom': displaySafeArea.bottom,
      'safeAreaLeft': displaySafeArea.left,
      'safeAreaRight': displaySafeArea.right,
      'rawSafeAreaTop': safeArea.top,
      'rawSafeAreaBottom': safeArea.bottom,
      'rawSafeAreaLeft': safeArea.left,
      'rawSafeAreaRight': safeArea.right,
      'cacheKey': cacheKey,
    };
    _readerDiagLog('reader_display_signature', displaySignature);
    final generationSignature = DisplayGenerationSignature(
      bookId: widget.bookId,
      parsedContentVersion: BookCacheService.parsedBookCacheFormatVersion,
      layoutSignature: BookCacheService.displayLayoutVersion,
      settingsSignature:
          '${_settings.fontSizeValue}|${_settings.fontFamily.name}|'
          '${_settings.fontWeight.name}|${_settings.densityMultiplier}|'
          '${_settings.fontMetricIdentity}|'
          '$layoutLocale|'
          '${_settings.lineHeight}|${_settings.paragraphSpacing}|'
          '${_settings.sideMargin}|${_settings.enableCardDepth}|'
          '${textScaler.scale(1.0)}',
      viewportSignature:
          '${screenSize.width}x${screenSize.height}|'
          '${displaySafeArea.top},${displaySafeArea.bottom},'
          '${displaySafeArea.left},${displaySafeArea.right}',
      cacheKey: cacheKey,
      sourceSnapshotIdentity: _sourceIdentitiesByChunkIndex.values
          .map((identity) => identity.stableKey)
          .join('|'),
      targetIdentity: (() {
        final target =
            _pendingExactStableRestore ?? layoutRestoreTarget?.location;
        return target == null
            ? 'source:$_targetOriginalIndex'
            : '${target.spineIndex}|${target.normalizedHref ?? target.href}|'
                  '${target.localChunkIndex}|${target.textOffset}';
      })(),
    );
    final readerLayoutFingerprint =
        '${generationSignature.parsedContentVersion}|'
        '${generationSignature.layoutSignature}|'
        '${generationSignature.settingsSignature}|'
        '${generationSignature.viewportSignature}|'
        '${generationSignature.cacheKey}';
    if (_activeReaderLayoutFingerprint != null &&
        _activeReaderLayoutFingerprint != readerLayoutFingerprint) {
      _cancelChapterCardLayoutWork(clearPublished: true);
    }
    final generationRequest = _displayGenerationCoordinator.request(
      generationSignature,
    );
    final token = generationRequest.token;

    if (generationRequest.kind == DisplayGenerationRequestKind.blockedFailure) {
      _isRebuildingChunks = false;
      _progressiveRangeFailure = const ReaderPreparationException(
        ReaderPreparationFailureKind.paginationRejected,
        'This page could not be prepared. Retry when you are ready.',
      );
      return;
    }

    if (generationRequest.kind == DisplayGenerationRequestKind.join) {
      _readerDiagLog('reader_display_request_skipped_rebuilding', {
        ...displaySignature,
        'activeGeneration': token.id,
        'reason': 'identical_signature_joined',
      });
      if (kDebugMode) {
        debugPrint(
          '[_ensureDisplayChunksBuilt] identical generation in flight, joining',
        );
      }
      return;
    }

    final cancelled = generationRequest.cancelledToken;
    if (cancelled != null) {
      _readerDiagLog('reader_display_generation_cancelled', {
        'book': cancelled.signature.bookId,
        'generation': cancelled.id,
        'reason': cancelled.cancellationReason,
        'cacheKey': cancelled.signature.cacheKey,
        'replacementGeneration': token.id,
        'replacementCacheKey': cacheKey,
      });
    }

    if (kDebugMode) {
      debugPrint(
        '[_ensureDisplayChunksBuilt] launching loadOrRebuild cacheKey=$cacheKey',
      );
    }
    _rebuildGeneration = token.id;
    _progressiveRangeGeneration++;
    _cancelledProgressiveRangeGenerations.clear();
    _progressiveRangeGenerator = null;
    _progressiveCanonicalPublisher = null;
    _progressiveDisplayState?.cancelActiveRequests();
    _progressiveRangeFailure = null;
    _progressiveFailureRetry = null;
    _isRebuildingChunks = true;
    unawaited(
      _runAuthoritativeDisplayGeneration(
        screenSize,
        displaySafeArea,
        textScaler,
        cacheKey,
        token,
        layoutRestoreTarget,
      ),
    );
  }

  Future<void> _runAuthoritativeDisplayGeneration(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
    String cacheKey,
    DisplayGenerationToken token,
    ({StableBookLocation location, int navigationGeneration})?
    layoutRestoreTarget,
  ) async {
    Object? failure;
    StackTrace? failureStack;
    try {
      await _loadOrRebuildDisplayChunks(
        screenSize,
        safeArea,
        textScaler,
        cacheKey,
        token,
        layoutRestoreTarget,
      );
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
      if (_displayGenerationCoordinator.canPublish(token)) {
        _displayGenerationCoordinator.fail(token, error);
      }
      if (mounted && token.id == _rebuildGeneration) {
        _progressiveRangeFailure = error is ReaderPreparationException
            ? error
            : ReaderPreparationException(
                ReaderPreparationFailureKind.unknown,
                'This page could not be prepared.',
                error,
              );
      }
    } finally {
      if (_displayGenerationCoordinator.canPublish(token)) {
        if (_displayChunks.isNotEmpty) {
          _displayGenerationCoordinator.settleReadyPartial(token);
        } else {
          final terminalFailure =
              failure ??
              const ReaderPreparationException(
                ReaderPreparationFailureKind.paginationRejected,
                'No readable card was produced.',
              );
          _displayGenerationCoordinator.fail(token, terminalFailure);
          _progressiveRangeFailure ??= terminalFailure;
        }
      }
      if (mounted && token.id == _rebuildGeneration) {
        _isRebuildingChunks = false;
        _isPreparingTargetRange = false;
        setState(() {});
      }
      if (failure != null) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: failure,
            stack: failureStack,
            library: 'reader display generation',
            context: ErrorDescription('while preparing the first reader card'),
          ),
        );
      }
    }
  }

  String _layoutFingerprintForCurrentViewport(ReadingSettings settings) {
    final screenSize = _lastScreenSize ?? MediaQuery.sizeOf(context);
    final safeArea = _canonicalDisplaySafeArea(
      _lastSafeArea ?? MediaQuery.viewPaddingOf(context),
    );
    final textScaler = _lastTextScaler ?? MediaQuery.textScalerOf(context);
    final locale =
        Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'und';
    final cacheKey = BookCacheService.displayChunkKey(
      bookId: widget.bookId,
      fontSize: settings.fontSizeValue,
      fontFamily: settings.fontFamily.name,
      fontWeight: settings.fontWeight.name,
      fontMetricIdentity: settings.fontMetricIdentity,
      locale: locale,
      density: settings.densityMultiplier,
      lineHeight: settings.lineHeight,
      paragraphSpacing: settings.paragraphSpacing,
      sideMargin: settings.sideMargin,
      screenW: screenSize.width,
      screenH: screenSize.height,
      enableCardDepth: settings.enableCardDepth,
      textScaleFactor: textScaler.scale(1.0),
      safeAreaTop: safeArea.top,
      safeAreaBottom: safeArea.bottom,
      safeAreaLeft: safeArea.left,
      safeAreaRight: safeArea.right,
    );
    final settingsSignature =
        '${settings.fontSizeValue}|${settings.fontFamily.name}|'
        '${settings.fontWeight.name}|${settings.densityMultiplier}|'
        '${settings.fontMetricIdentity}|$locale|'
        '${settings.lineHeight}|${settings.paragraphSpacing}|'
        '${settings.sideMargin}|${settings.enableCardDepth}|'
        '${textScaler.scale(1.0)}';
    final viewportSignature =
        '${screenSize.width}x${screenSize.height}|'
        '${safeArea.top},${safeArea.bottom},${safeArea.left},${safeArea.right}';
    return '${BookCacheService.parsedBookCacheFormatVersion}|'
        '${BookCacheService.displayLayoutVersion}|'
        '$settingsSignature|$viewportSignature|$cacheKey';
  }

  ({StableBookLocation location, int navigationGeneration})?
  _captureLayoutRestoreTarget() {
    if (_isFirstLayout ||
        _displayChunks.isEmpty ||
        _pendingExactStableRestore != null ||
        _pendingDisplayNavigationToken != null ||
        _isPreparingTargetRange ||
        _positionSession.hasActivePreviewPosition) {
      return null;
    }
    // A display index belongs to the current publication only. A delayed
    // reflow must capture the stable source owner, never reuse the numeric
    // index that happened to be committed in an older window.
    final location = _authoritativeVisibleAnchor();
    if (location == null) return null;
    return (
      location: location,
      navigationGeneration: _positionSession.navigationGeneration,
    );
  }

  EdgeInsets _canonicalDisplaySafeArea(EdgeInsets safeArea) {
    return EdgeInsets.fromLTRB(
      safeArea.left,
      safeArea.top,
      safeArea.right,
      safeArea.bottom,
    );
  }

  Future<void> _loadOrRebuildDisplayChunks(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
    String cacheKey,
    DisplayGenerationToken token,
    ({StableBookLocation location, int navigationGeneration})?
    layoutRestoreTarget,
  ) async {
    final thisGen = token.id;
    _pendingReaderLayoutContract = null;
    _pendingReaderLayoutGeneration = null;
    final restoreNavigationGeneration =
        layoutRestoreTarget?.navigationGeneration ??
        _positionSession.navigationGeneration;
    if (kDebugMode) {
      debugPrint('[_loadOrRebuildDisplayChunks] start gen=$thisGen');
    }
    _readerDiagLog('reader_display_load_begin', {
      'book': widget.bookId,
      'generation': thisGen,
      'parsedCacheVersion': BookCacheService.parsedBookCacheFormatVersion,
      'displayCacheVersion': BookCacheService.displayCacheFormatVersion,
      'layoutVersion': BookCacheService.displayLayoutVersion,
      'sourceChunks': _sourceChunks.length,
      'fontSize': _settings.fontSizeValue,
      'fontFamily': _settings.fontFamily.name,
      'fontWeight': _settings.fontWeight.name,
      'density': _settings.densityMultiplier,
      'lineHeight': _settings.lineHeight,
      'paragraphSpacing': _settings.paragraphSpacing,
      'sideMargin': _settings.sideMargin,
      'screenW': screenSize.width,
      'screenH': screenSize.height,
      'enableCardDepth': _settings.enableCardDepth,
      'textScaleFactor': textScaler.scale(1.0),
      'safeAreaTop': safeArea.top,
      'safeAreaBottom': safeArea.bottom,
      'safeAreaLeft': safeArea.left,
      'safeAreaRight': safeArea.right,
      'cacheKey': cacheKey,
    });

    final representative = _sourceChunks.cast<BookChunk?>().firstWhere(
      (chunk) => (chunk?.text ?? '').isNotEmpty,
      orElse: () => null,
    );
    final representativeText = representative?.text ?? '';
    final probeText =
        representativeText.length <=
            ReaderSourceFontProbePlan.maximumSourceSliceUtf16
        ? representativeText
        : representativeText.substring(
            0,
            ReaderSourceFontProbePlan.maximumSourceSliceUtf16,
          );
    final fontOutcome = await _readerFontEvidenceGate.capture(
      settings: _settings,
      stableSourceIdentity: representative == null
          ? '${widget.bookId}|empty-publication'
          : canonicalBookChunkOwnershipDigest(representative),
      sourceStartUtf16: 0,
      sourceText: probeText,
      locale: Localizations.maybeLocaleOf(context)?.toLanguageTag(),
      textScaler: textScaler,
      isCancelled: () =>
          !mounted || !_displayGenerationCoordinator.canPublish(token),
      isStale: () => token.id != _rebuildGeneration,
    );
    if (fontOutcome is! ReaderFontReadyTerminalBundled ||
        !fontOutcome.canAuthorizeLayout) {
      _readerDiagLog('reader_layout_font_authority_rejected', {
        'book': widget.bookId,
        'generation': thisGen,
        'outcome': fontOutcome.type.name,
        'reason': fontOutcome.reason,
      });
      throw ReaderPreparationException(
        ReaderPreparationFailureKind.layoutRejected,
        'Reader font evidence was rejected: ${fontOutcome.reason}',
      );
    }
    _terminalReaderFontOutcome = fontOutcome;
    if (!mounted || !_displayGenerationCoordinator.canPublish(token)) return;

    // The legacy whole-display derivative can never satisfy P04/P06 admission.
    // Do not put its disk read on the first-readable-card critical path.
    if (kDebugMode) {
      debugPrint(
        '[_loadOrRebuildDisplayChunks] gen=$thisGen CACHE MISS -> triggering rebuild',
      );
    }
    _readerDiagLog('reader_display_cache_miss', {
      'book': widget.bookId,
      'generation': thisGen,
      'cacheKey': cacheKey,
    });
    await _rebuildDisplayChunksAsync(
      screenSize,
      safeArea,
      textScaler,
      cacheKey,
      token,
      restoreNavigationGeneration,
      layoutRestoreTarget,
    );
    _readerDiagLog('reader_display_load_end', {
      'book': widget.bookId,
      'generation': thisGen,
      'displayChunks': _displayChunks.length,
    });
  }

  Future<StableBookLocation?> _resolveLayoutRestoreTarget(
    ({StableBookLocation location, int navigationGeneration})? target,
    DisplayGenerationToken token,
  ) async {
    if (target == null ||
        target.navigationGeneration != _positionSession.navigationGeneration ||
        !_displayGenerationCoordinator.canPublish(token)) {
      return null;
    }
    final session = _lazySession;
    final resolved = session == null
        ? target.location
        : (await session.resolveStableLocation(target.location)).location;
    if (!mounted ||
        target.navigationGeneration != _positionSession.navigationGeneration ||
        !_displayGenerationCoordinator.canPublish(token)) {
      return null;
    }
    return resolved;
  }

  int? _displayIndexForSourceLocation({
    required int originalChunkIndex,
    int? originalStartOffset,
    String? sourceText,
  }) {
    final offsetMatch = originalStartOffset == null
        ? null
        : _displayIndexContainingOriginalOffset(
            originalChunkIndex,
            originalStartOffset,
          );
    if (offsetMatch != null) return offsetMatch;

    final normalizedSource = _normalizeLocatorText(sourceText);
    if (normalizedSource.isNotEmpty) {
      final snippetOffset = _offsetForSourceText(
        originalChunkIndex,
        normalizedSource,
      );
      if (snippetOffset != null) {
        final snippetMatch = _displayIndexContainingOriginalOffset(
          originalChunkIndex,
          snippetOffset,
        );
        if (snippetMatch != null) return snippetMatch;
      }

      final textMatch = _displayIndexContainingSourceText(
        originalChunkIndex,
        normalizedSource,
      );
      if (textMatch != null) return textMatch;
    }

    final nearestOffset = originalStartOffset == null
        ? null
        : _displayIndexNearestOriginalOffset(
            originalChunkIndex,
            originalStartOffset,
          );
    return nearestOffset ?? _originalToDisplay[originalChunkIndex];
  }

  int? _displayIndexContainingOriginalOffset(
    int originalChunkIndex,
    int originalStartOffset,
  ) {
    return readerDisplayIndexContainingSourceOffset(
      displayChunks: _displayChunks,
      originalChunkIndex: originalChunkIndex,
      textOffset: originalStartOffset,
    );
  }

  int? _displayIndexNearestOriginalOffset(
    int originalChunkIndex,
    int originalStartOffset,
  ) {
    int? bestDisplayIndex;
    var bestDistance = 1 << 30;

    for (
      var displayIndex = 0;
      displayIndex < _displayChunks.length;
      displayIndex++
    ) {
      for (final range in _displayChunks[displayIndex].effectiveSourceRanges) {
        if (range.originalChunkIndex != originalChunkIndex) continue;
        final distance = originalStartOffset < range.originalStartOffset
            ? range.originalStartOffset - originalStartOffset
            : originalStartOffset - range.originalEndOffset;
        final normalizedDistance = distance < 0 ? 0 : distance;
        if (normalizedDistance < bestDistance) {
          bestDistance = normalizedDistance;
          bestDisplayIndex = displayIndex;
        }
      }
    }

    return bestDisplayIndex;
  }

  int? _displayIndexContainingSourceText(
    int originalChunkIndex,
    String normalizedSource,
  ) {
    for (
      var displayIndex = 0;
      displayIndex < _displayChunks.length;
      displayIndex++
    ) {
      final chunk = _displayChunks[displayIndex];
      final ranges = chunk.effectiveSourceRanges;
      if (!ranges.any(
        (range) => range.originalChunkIndex == originalChunkIndex,
      )) {
        continue;
      }
      final displayText = _normalizeLocatorText(chunk.text);
      if (displayText.isEmpty) continue;
      if (displayText.contains(normalizedSource) ||
          (displayText.length >= 20 &&
              normalizedSource.contains(displayText))) {
        return displayIndex;
      }
    }
    return null;
  }

  int? _offsetForSourceText(int originalChunkIndex, String normalizedSource) {
    final source = _chunkByOriginalIndex(originalChunkIndex);
    final text = source?.text;
    if (text == null || text.isEmpty) return null;
    final normalizedText = _normalizeLocatorText(text);
    final normalizedOffset = normalizedText.indexOf(normalizedSource);
    if (normalizedOffset < 0) return null;
    return _approximateOriginalOffsetForNormalizedOffset(
      text,
      normalizedOffset,
    );
  }

  int _approximateOriginalOffsetForNormalizedOffset(
    String text,
    int normalizedOffset,
  ) {
    if (normalizedOffset <= 0) return 0;
    var normalizedCount = 0;
    var previousWasWhitespace = true;
    for (var i = 0; i < text.length; i++) {
      final isWhitespace = text[i].trim().isEmpty;
      if (isWhitespace) {
        if (!previousWasWhitespace) {
          if (normalizedCount == normalizedOffset) return i;
          normalizedCount++;
        }
        previousWasWhitespace = true;
        continue;
      }

      if (normalizedCount == normalizedOffset) return i;
      normalizedCount++;
      previousWasWhitespace = false;
    }
    return text.length;
  }

  String _normalizeLocatorText(String? text) {
    return (text ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Restore the reading position after display chunks change.
  /// Uses text-anchor matching first, then falls back to index/ratio-based positioning.
  void _restorePosition(
    int restoreNavigationGeneration, {
    StableBookLocation? layoutStableRestore,
  }) {
    if (_displayChunks.isEmpty) {
      _logVisiblePositionMutation(
        reason: 'empty_display_publication',
        classification: ReaderVisibleMutationClassification.synthetic,
        accepted: false,
        decisionReason: 'no_visible_source_location',
        oldLocation: _visiblePositionCoordinator.committedLocation,
        oldLocalIndex: _currentPage,
        newLocalIndex: 0,
      );
      _currentPage = 0;
      _hasCompletedDisplayChunkBuild = true;
      if (_pageController == null) {
        _pageController = PageController(keepPage: false);
      } else if (_pageController!.hasClients) {
        if (SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
          _pageController!.jumpToPage(0);
        }
      } else {
        _pageController?.dispose();
        _pageController = PageController(keepPage: false);
      }

      if (_isRebuildingChunks) {
        setState(() => _isRebuildingChunks = false);
      } else {
        setState(() {});
      }
      return;
    }

    if (_shouldDeferVisibleRestore(restoreNavigationGeneration)) {
      _deferRestoreUntilResume(restoreNavigationGeneration);
      return;
    }

    final pendingStableRestore =
        layoutStableRestore ?? _pendingExactStableRestore;
    if (_readerDiagEnabled) {
      _readerDiagLog('stable_location_restore_check', {
        'book': widget.bookId,
        'hasPendingStableRestore': pendingStableRestore != null,
        'isFirstLayout': _isFirstLayout,
        'restoreNavigationGeneration': restoreNavigationGeneration,
        'activeNavigationGeneration': _positionSession.navigationGeneration,
        'targetOriginalIndex': _targetOriginalIndex,
        'displayChunks': _displayChunks.length,
      });
    }
    if (_visiblePositionCoordinator.restorationComplete) {
      final activeIntent = _visiblePositionCoordinator.activeIntent;
      final anchor = _visiblePositionCoordinator.authoritativeTarget;
      final preservedIndex = anchor == null
          ? null
          : _displayIndexForStableAnchor(anchor);
      if (anchor == null || preservedIndex == null) {
        _logVisiblePositionMutation(
          reason: 'late_restore_or_publication',
          classification: ReaderVisibleMutationClassification.synthetic,
          accepted: false,
          decisionReason: 'authoritative_anchor_unresolved',
          oldLocation: anchor,
          newLocation: pendingStableRestore,
          oldLocalIndex: _currentPage,
        );
        _hasCompletedDisplayChunkBuild = true;
        _isRebuildingChunks = false;
        if (mounted) setState(() {});
        return;
      }
      _jumpToDisplayIndex(
        preservedIndex,
        reason: 'late_publication_preserve_committed_anchor',
        restoreIntent: activeIntent,
      );
      return;
    }
    final checkpointResolution = _resolveCanonicalCheckpointRestore();
    if (checkpointResolution != null) {
      final restoreLocation =
          _checkpointCoordinator?.current?.stableLocation ??
          _committedStableLocationForDisplay(checkpointResolution.index);
      final restoreIntent = restoreLocation == null
          ? null
          : _beginInitialVisibleRestore(
              restoreLocation,
              'authoritative_checkpoint_restore',
            );
      _pendingCheckpointRestoreResolution = checkpointResolution;
      _pendingExactStableRestore = null;
      _preferSourceIndexOnNextRestore = false;
      _isFirstLayout = false;
      _hasPendingSettingsRestore = false;
      _positionAnchor = null;
      _readerDiagLog('checkpoint_restore_publication', {
        'book': widget.bookId,
        'strategy': checkpointResolution.strategy.name,
        'displayIndex': checkpointResolution.index,
        'fallbackReason': checkpointResolution.fallbackReason,
      });
      _jumpToDisplayIndex(
        checkpointResolution.index,
        reason: 'authoritative_checkpoint_restore',
        restoreIntent: restoreIntent,
      );
      return;
    }
    if (pendingStableRestore != null) {
      final sourceIndex = readerSourceIndexForStableLocation(
        location: pendingStableRestore,
        locationsByChunkIndex: _publishedSourceLocationsByChunkIndex,
        sourceIdentitiesByChunkIndex: _publishedSourceIdentitiesByChunkIndex,
      );
      final exactDisplayIndex = readerDisplayIndexForStableLocation(
        location: pendingStableRestore,
        displayChunks: _displayChunks,
        locationsByChunkIndex: _publishedSourceLocationsByChunkIndex,
        sourceIdentitiesByChunkIndex: _publishedSourceIdentitiesByChunkIndex,
      );
      if (exactDisplayIndex != null) {
        final restoreIntent = _beginInitialVisibleRestore(
          pendingStableRestore,
          'stable_location_initial_restore',
        );
        if (layoutStableRestore == null) {
          _pendingExactStableRestore = null;
        }
        _preferSourceIndexOnNextRestore = false;
        _isFirstLayout = false;
        _hasPendingSettingsRestore = false;
        _positionAnchor = null;
        _targetProgressRatio = _displayChunks.isEmpty
            ? 0
            : exactDisplayIndex / _displayChunks.length;
        _readerDiagLog('stable_location_exact_restore', {
          ..._stableLocationDiagFields(pendingStableRestore),
          'sourceIndex': sourceIndex,
          'displayIndex': exactDisplayIndex,
        });
        _jumpToDisplayIndex(
          exactDisplayIndex,
          reason: 'stable_location_initial_restore',
          restoreIntent: restoreIntent,
        );
        return;
      }
      _readerDiagLog('stable_location_exact_restore_miss', {
        ..._stableLocationDiagFields(pendingStableRestore),
        'sourceIndex': sourceIndex,
      });
      _logVisiblePositionMutation(
        reason: 'stable_location_restore',
        classification: ReaderVisibleMutationClassification.programmatic,
        accepted: false,
        decisionReason: 'stable_anchor_unresolved_no_fallback',
        oldLocation: _currentStableLocation(),
        newLocation: pendingStableRestore,
        oldLocalIndex: _currentPage,
      );
      _hasCompletedDisplayChunkBuild = true;
      _isRebuildingChunks = false;
      if (mounted) setState(() {});
      return;
    }

    if (!_isFirstLayout &&
        restoreNavigationGeneration != _positionSession.navigationGeneration) {
      _jumpToDisplayIndex(
        _positionSession.activeVisiblePosition.clamp(
          0,
          _displayChunks.length - 1,
        ),
      );
      return;
    }

    final initialOriginalChunkIndex = widget.initialOriginalChunkIndex;
    if (!_hasResolvedInitialLocation && initialOriginalChunkIndex != null) {
      _hasResolvedInitialLocation = true;
      _isFirstLayout = false;
      final targetIndex =
          _displayIndexForSourceLocation(
            originalChunkIndex: initialOriginalChunkIndex,
            originalStartOffset: widget.initialOriginalStartOffset,
            sourceText: widget.initialSourceText,
          ) ??
          _originalToDisplay[initialOriginalChunkIndex] ??
          0;
      _jumpToDisplayIndex(targetIndex.clamp(0, _displayChunks.length - 1));
      return;
    }

    // Try text-anchor matching first (most accurate)
    if (_positionAnchor != null && !_isFirstLayout) {
      final anchor = _positionAnchor!;
      _positionAnchor = null; // Clear after use

      final estimatedNewIndex = (_targetProgressRatio * _displayChunks.length)
          .round()
          .clamp(0, _displayChunks.length - 1);

      final anchorIndex = _findDisplayIndexForAnchor(
        anchor: anchor,
        preferredOriginalIndex: _targetOriginalIndex,
        expectedDisplayIndex: estimatedNewIndex,
        preferredOriginalCandidates: _targetOriginalCandidates,
      );
      _jumpToDisplayIndex(anchorIndex.clamp(0, _displayChunks.length - 1));
      _hasPendingSettingsRestore = false;
      return;
    }

    // During settings-driven rebuilds, avoid ratio-based jumps.
    // Keep the user near the previous display index and source chunk set.
    if (_hasPendingSettingsRestore && !_isFirstLayout) {
      final estimatedNewIndex = (_targetProgressRatio * _displayChunks.length)
          .round()
          .clamp(0, _displayChunks.length - 1);

      final localIdx = _findNearestByOriginalOverlap(
        expectedDisplayIndex: estimatedNewIndex,
        preferredOriginalCandidates: _targetOriginalCandidates,
      );
      _hasPendingSettingsRestore = false;
      _jumpToDisplayIndex(localIdx.clamp(0, _displayChunks.length - 1));
      return;
    }

    // Fallback to index/ratio-based positioning
    int newDisplayIndex;
    final indexBased = _originalToDisplay[_targetOriginalIndex] ?? 0;

    if (_preferSourceIndexOnNextRestore) {
      _preferSourceIndexOnNextRestore = false;
      _isFirstLayout = false;
      _targetProgressRatio = indexBased / _displayChunks.length;
      _jumpToDisplayIndex(indexBased.clamp(0, _displayChunks.length - 1));
      return;
    }

    final ratioBased = (_targetProgressRatio * _displayChunks.length)
        .round()
        .clamp(0, _displayChunks.length - 1);

    final indexFraction = indexBased / _displayChunks.length;

    if (_isFirstLayout) {
      newDisplayIndex = indexBased;
      _isFirstLayout = false;
      _targetProgressRatio = indexFraction;
    } else {
      final drift = (indexFraction - _targetProgressRatio).abs();
      newDisplayIndex = drift < 0.05 ? indexBased : ratioBased;
    }

    _jumpToDisplayIndex(newDisplayIndex);
  }

  bool _shouldDeferVisibleRestore(int restoreNavigationGeneration) {
    return !_isReaderLifecycleActive && !_isFirstLayout;
  }

  void _deferRestoreUntilResume(int restoreNavigationGeneration) {
    _hasDeferredRestoreWhileInactive = true;
    _deferredRestoreNavigationGeneration = restoreNavigationGeneration;
    _hasCompletedDisplayChunkBuild = true;
    _isRebuildingChunks = false;
  }

  void _applyDeferredRestoreAfterResume() {
    if (!_hasDeferredRestoreWhileInactive) return;
    final restoreNavigationGeneration = _deferredRestoreNavigationGeneration;
    _hasDeferredRestoreWhileInactive = false;
    _deferredRestoreNavigationGeneration = null;
    if (restoreNavigationGeneration == null ||
        restoreNavigationGeneration != _positionSession.navigationGeneration ||
        _displayChunks.isEmpty) {
      return;
    }

    _jumpToDisplayIndex(
      _positionSession.activeVisiblePosition.clamp(
        0,
        _displayChunks.length - 1,
      ),
    );
  }

  /// Jump to a display index without animation, then clear rebuilding state.
  void _jumpToDisplayIndex(
    int index, {
    String reason = 'publication_anchor_mapping',
    ReaderVisibleNavigationIntent<StableBookLocation>? restoreIntent,
  }) {
    final pendingStableRestore = _pendingExactStableRestore;
    var targetIndex = index;
    if (pendingStableRestore != null) {
      final sourceIndex = _sourceIndexForStableLocation(pendingStableRestore);
      final exactDisplayIndex = _displayIndexForStableAnchor(
        pendingStableRestore,
      );
      if (exactDisplayIndex != null) {
        _pendingExactStableRestore = null;
        targetIndex = exactDisplayIndex;
        _readerDiagLog('stable_location_exact_restore', {
          ..._stableLocationDiagFields(pendingStableRestore),
          'sourceIndex': sourceIndex,
          'displayIndex': exactDisplayIndex,
          'fallbackDisplayIndex': index,
        });
      } else {
        _readerDiagLog('stable_location_exact_restore_miss', {
          ..._stableLocationDiagFields(pendingStableRestore),
          'sourceIndex': sourceIndex,
          'fallbackDisplayIndex': index,
        });
        _logVisiblePositionMutation(
          reason: reason,
          classification: ReaderVisibleMutationClassification.programmatic,
          accepted: false,
          decisionReason: 'pending_stable_anchor_unresolved_no_fallback',
          oldLocation: _currentStableLocation(),
          newLocation: pendingStableRestore,
          oldLocalIndex: _currentPage,
          newLocalIndex: index,
          intent: restoreIntent,
        );
        return;
      }
    }
    _hasCompletedDisplayChunkBuild = true;
    final oldLocation = _currentStableLocation();
    final oldIndex = _currentPage;
    _logVisiblePositionMutation(
      reason: reason,
      classification: restoreIntent == null
          ? ReaderVisibleMutationClassification.synthetic
          : ReaderVisibleMutationClassification.programmatic,
      accepted: true,
      decisionReason: 'derived_index_hint_assignment',
      oldLocation: oldLocation,
      newLocation: _committedStableLocationForDisplay(targetIndex),
      oldLocalIndex: oldIndex,
      newLocalIndex: targetIndex,
      intent: restoreIntent,
    );
    _currentPage = targetIndex;
    _activeDisplayIndex = targetIndex;
    _positionSession.markVisible(targetIndex);
    _syncRestoreTargetFromDisplayIndex(targetIndex);
    final newLocation = _committedStableLocationForDisplay(targetIndex);
    final effectiveRestoreIntent =
        restoreIntent ??
        (newLocation == null ||
                _visiblePositionCoordinator.restorationState !=
                    ReaderVisibleRestorationState.preparing
            ? null
            : _beginInitialVisibleRestore(newLocation, reason));
    final appliesControllerIntent =
        effectiveRestoreIntent != null &&
        _visiblePositionCoordinator.isCurrent(effectiveRestoreIntent);
    if (appliesControllerIntent) {
      _controllerIntent = effectiveRestoreIntent;
      _syntheticControllerTargetIndex = null;
      _visiblePositionCoordinator.markWindowPublished(
        intent: effectiveRestoreIntent,
        resolvedLocation: effectiveRestoreIntent.target,
        windowGeneration: _rebuildGeneration,
        publicationGeneration: _progressiveRangeGeneration,
      );
      _visiblePositionCoordinator.markControllerMoved(effectiveRestoreIntent);
    } else {
      _syntheticControllerTargetIndex = targetIndex;
    }
    _logVisiblePositionMutation(
      reason: reason,
      classification: effectiveRestoreIntent == null
          ? ReaderVisibleMutationClassification.synthetic
          : ReaderVisibleMutationClassification.programmatic,
      accepted: effectiveRestoreIntent == null
          ? _visiblePositionCoordinator.authoritativeTarget != null
          : _visiblePositionCoordinator.isCurrent(effectiveRestoreIntent),
      decisionReason: effectiveRestoreIntent == null
          ? 'stable_anchor_reindexed'
          : 'initial_restore_controller_requested',
      oldLocation: oldLocation,
      newLocation: newLocation,
      oldLocalIndex: oldIndex,
      newLocalIndex: targetIndex,
      intent: effectiveRestoreIntent,
    );
    if (_pageController == null) {
      _pageController = PageController(
        initialPage: targetIndex,
        keepPage: false,
      );
    } else if (_pageController!.hasClients) {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        _restoreAuthoritativeVisibleIndex('layout_deferred_$reason');
      } else {
        _pageController!.jumpToPage(targetIndex);
      }
    } else {
      _pageController?.dispose();
      _pageController = PageController(
        initialPage: targetIndex,
        keepPage: false,
      );
    }

    if (_isRebuildingChunks) {
      setState(() => _isRebuildingChunks = false);
    } else {
      setState(() {});
    }
    _scheduleCheckpointPublicationVerification(targetIndex);
  }

  void _syncRestoreTargetFromDisplayIndex(int index) {
    if (_displayChunks.isEmpty || _displayToOriginal.isEmpty) return;
    if (index < 0 || index >= _displayToOriginal.length) return;

    final originals = _displayToOriginal[index];
    if (originals.isEmpty) return;

    _targetOriginalCandidates = List<int>.from(originals);
    _targetOriginalIndex = originals.first.clamp(0, _sourceChunks.length - 1);
    _targetProgressRatio = _displayChunks.isNotEmpty
        ? index / _displayChunks.length
        : 0.0;
  }

  /// Async batched rebuild — shows loading indicator, runs the rebuild
  /// with periodic yields to prevent UI freezes, then caches results to disk.
  Future<void> _rebuildDisplayChunksAsync(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
    String cacheKey,
    DisplayGenerationToken token,
    int restoreNavigationGeneration,
    ({StableBookLocation location, int navigationGeneration})?
    layoutRestoreTarget,
  ) async {
    final generation = token.id;
    if (kDebugMode) {
      debugPrint(
        '[_rebuildDisplayChunksAsync] gen=$generation currentGen=$_rebuildGeneration',
      );
    }
    if (!_displayGenerationCoordinator.canPublish(token)) {
      if (kDebugMode) {
        debugPrint(
          '[_rebuildDisplayChunksAsync] gen=$generation STALE -> returning immediately',
        );
      }
      return;
    }
    final rebuildStopwatch = Stopwatch()..start();
    _readerDiagLog('reader_display_rebuild_async_begin', {
      'book': widget.bookId,
      'generation': generation,
      'cacheKey': cacheKey,
      'parsedCacheVersion': BookCacheService.parsedBookCacheFormatVersion,
      'displayCacheVersion': BookCacheService.displayCacheFormatVersion,
      'layoutVersion': BookCacheService.displayLayoutVersion,
      'sourceChunks': _sourceChunks.length,
    });
    setState(() => _isRebuildingChunks = true);
    if (kDebugMode) {
      debugPrint(
        '[_rebuildDisplayChunksAsync] gen=$generation marked rebuilding=true',
      );
    }

    await Future.delayed(Duration.zero);
    if (!mounted || !_displayGenerationCoordinator.canPublish(token)) {
      if (kDebugMode) {
        debugPrint(
          '[_rebuildDisplayChunksAsync] gen=$generation cancelled after yield',
        );
      }
      return;
    }

    await _rebuildDisplayChunks(
      screenSize,
      safeArea,
      textScaler,
      token,
      layoutRestoreLocation: layoutRestoreTarget?.location,
    );

    if (!mounted || !_displayGenerationCoordinator.canPublish(token)) {
      if (kDebugMode) {
        debugPrint(
          '[_rebuildDisplayChunksAsync] gen=$generation cancelled after rebuild',
        );
      }
      return;
    }

    final resolvedLayoutRestore = await _resolveLayoutRestoreTarget(
      layoutRestoreTarget,
      token,
    );
    if (!mounted || !_displayGenerationCoordinator.canPublish(token)) return;
    _restorePosition(
      restoreNavigationGeneration,
      layoutStableRestore: resolvedLayoutRestore,
    );
    rebuildStopwatch.stop();
    _markDisplayRebuildCompleted(generation, token.signature);
    _readerDiagLog('reader_display_rebuild_async_end', {
      'book': widget.bookId,
      'generation': generation,
      'cacheKey': cacheKey,
      'elapsedMs': rebuildStopwatch.elapsedMilliseconds,
      'displayChunks': _displayChunks.length,
      'displayToOriginal': _displayToOriginal.length,
      'originalToDisplay': _originalToDisplay.length,
    });

    if (!_displayChunksComplete) {
      _readerDiagLog('reader_display_cache_write_skipped_partial', {
        'book': widget.bookId,
        'generation': generation,
        'cacheKey': cacheKey,
        'displayChunks': _displayChunks.length,
        'reason': 'progressive_display_incomplete',
      });
    } else {
      _readerDiagLog('reader_legacy_display_cache_write_skipped', {
        'book': widget.bookId,
        'generation': generation,
        'cacheKey': cacheKey,
        'reason': 'noncanonical_whole_display_derivative',
      });
    }
    if (_displayChunksComplete) {
      _displayGenerationCoordinator.complete(token);
    } else {
      _displayGenerationCoordinator.settleReadyPartial(token);
    }
  }

  Future<void> _rebuildDisplayChunks(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
    DisplayGenerationToken token, {
    StableBookLocation? layoutRestoreLocation,
  }) async {
    final generation = token.id;
    final fullRebuildStopwatch = Stopwatch()..start();
    _readerDiagLog('reader_display_rebuild_begin', {
      'book': widget.bookId,
      'generation': generation,
      'sourceChunks': _sourceChunks.length,
      'screenW': screenSize.width.round(),
      'screenH': screenSize.height.round(),
    });
    if (_sourceChunks.isEmpty) {
      _displayChunks.clear();
      _displayToOriginal.clear();
      _originalToDisplay.clear();
      _displayChunksComplete = true;
      return;
    }

    final layoutMetrics = resolveReaderLayoutMetrics(
      screenSize,
      safeArea,
      _settings,
    );
    final pageHeightBudget = layoutMetrics.maxTextHeight;
    final physicalTextBudget = math.max(
      pageHeightBudget,
      layoutMetrics.availableHeight - layoutMetrics.safetyBuffer,
    );
    late final paginator.ReaderCardPaginatorLayout paginatorLayout;

    int anchoredInitialRangeEndExclusive(int sourceIndex) {
      return readerMeasuredAnchoredLookaheadEndExclusive(
        sourceChunks: _sourceChunks,
        sourceIndex: sourceIndex,
        heightBudget: _sourceChunks[sourceIndex].usesPublisherLayout
            ? physicalTextBudget
            : pageHeightBudget,
        effectiveLineBoxHeight: _settings.effectiveLineBoxHeight,
      );
    }

    final canonicalSourceRevision = _canonicalPaginationSourceRevision(
      _sourceChunks,
    );
    final canonicalSourceKeys = _canonicalPaginationSourceKeys(
      _sourceChunks,
      locations: _sourceLocationsByChunkIndex,
      identities: _sourceIdentitiesByChunkIndex,
    );
    final canonicalSnapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: widget.bookId,
      publicationFingerprint: _publicationFingerprint!,
      parserSourceIdentity: _canonicalParserSourceIdentity(
        _sourceLocationsByChunkIndex,
      ),
      sourceRevision: canonicalSourceRevision,
      sourceChunks: _sourceChunks,
      sourceKeys: canonicalSourceKeys,
    );
    final terminalFontOutcome = _terminalReaderFontOutcome;
    if (terminalFontOutcome == null) return;
    final contractOutcome = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: screenSize,
        mediaQuerySize: screenSize,
        viewPadding: safeArea,
        locale: Localizations.maybeLocaleOf(context) ?? const Locale('und'),
        defaultDirection: Directionality.maybeOf(context),
        textScaler: textScaler,
        settings: _settings,
        fontOutcome: terminalFontOutcome,
        captureFreshnessEvidence:
            '$generation|${canonicalSnapshot.snapshotDigest}',
        publicationFingerprint: _publicationFingerprint!,
        parserSourceSchemaIdentity: canonicalSnapshot.parserSourceIdentity,
        sourceRevision: canonicalSourceRevision,
        sourceSnapshotDigest: canonicalSnapshot.snapshotDigest,
      ),
    );
    if (contractOutcome is! ReaderLayoutContractReady) {
      _readerDiagLog('reader_layout_contract_rejected', {
        'book': widget.bookId,
        'generation': generation,
        'outcome': contractOutcome.type.name,
        'reason': contractOutcome.reason,
      });
      throw ReaderPreparationException(
        ReaderPreparationFailureKind.layoutRejected,
        'Reader layout contract was rejected: ${contractOutcome.reason}',
      );
    }
    final contract = contractOutcome.contract;
    if (!mounted || generation != _rebuildGeneration) return;

    final imageEvidence = <String, ReaderImageMetricEvidence>{};
    for (final source in _sourceChunks) {
      final bytes = source.imageBytes;
      if (source.type != BookChunkType.image || bytes == null) continue;
      try {
        imageEvidence[canonicalBookChunkOwnershipDigest(source)] =
            await resolveReaderImageMetricEvidence(bytes);
      } on Object catch (error) {
        _readerDiagLog('reader_layout_image_authority_rejected', {
          'book': widget.bookId,
          'generation': generation,
          'source': canonicalBookChunkOwnershipDigest(source),
          'error': '$error',
        });
        throw ReaderPreparationException(
          ReaderPreparationFailureKind.layoutRejected,
          'Image layout evidence could not be resolved.',
          error,
        );
      }
      if (!mounted || generation != _rebuildGeneration) return;
    }
    final resolvedImageEvidence =
        Map<String, ReaderImageMetricEvidence>.unmodifiable(imageEvidence);

    List<ReaderSourceFontMetricEvidence> resolveFontEvidence(
      BookChunk chunk,
      String text,
    ) {
      final evidence = <ReaderSourceFontMetricEvidence>[];
      final owner = canonicalBookChunkOwnershipDigest(chunk);
      if (text.isEmpty) {
        final outcome = _readerFontEvidenceGate.capturePrepared(
          settings: _settings,
          stableSourceIdentity: '$owner|0:0',
          sourceStartUtf16: 0,
          sourceText: '',
          locale: contract.environment.locale.tag,
          textScaler: textScaler,
        );
        if (outcome is! ReaderFontReadyTerminalBundled) {
          throw StateError('Font evidence unavailable: ${outcome.type.name}');
        }
        return <ReaderSourceFontMetricEvidence>[outcome.sourceEvidence];
      }
      var start = 0;
      while (start < text.length) {
        var end = math.min(
          text.length,
          start + ReaderSourceFontProbePlan.maximumSourceSliceUtf16,
        );
        if (end < text.length &&
            text.codeUnitAt(end - 1) >= 0xD800 &&
            text.codeUnitAt(end - 1) <= 0xDBFF) {
          end--;
        }
        final outcome = _readerFontEvidenceGate.capturePrepared(
          settings: _settings,
          stableSourceIdentity: '$owner|$start:$end',
          sourceStartUtf16: start,
          sourceText: text.substring(start, end),
          locale: contract.environment.locale.tag,
          textScaler: textScaler,
        );
        if (outcome is! ReaderFontReadyTerminalBundled) {
          throw StateError('Font evidence unavailable: ${outcome.type.name}');
        }
        evidence.add(outcome.sourceEvidence);
        start = end;
      }
      return List<ReaderSourceFontMetricEvidence>.unmodifiable(evidence);
    }

    paginatorLayout = paginator.ReaderCardPaginatorLayout(
      availableWidth: contract.geometry.bodySize.width,
      pageHeightBudget: contract.geometry.ordinaryPaginationHeightBudget,
      physicalTextBudget: contract.geometry.publisherPaginationHeightBudget,
      minUsefulHeight: contract.geometry.minUsefulHeight,
      tinyWordCount: contract.settingsPolicy.densityTinyWordCount,
      tinyHeightRatio: contract.settingsPolicy.densityTinyHeightRatio,
      settings: _settings,
      bodyStyle: contract.typography[ReaderLayoutTextRole.body].toTextStyle(),
      headingStyle: contract.typography[ReaderLayoutTextRole.heading]
          .toTextStyle(),
      bodyStrut: contract.typography[ReaderLayoutTextRole.body].toStrutStyle(),
      headingStrut: contract.typography[ReaderLayoutTextRole.heading]
          .toStrutStyle(),
      textScaler: TextScaler.noScaling,
      contract: contract,
      fontEvidenceResolver: resolveFontEvidence,
      imageEvidenceResolver: (chunk) =>
          resolvedImageEvidence[canonicalBookChunkOwnershipDigest(chunk)],
    );
    _pendingReaderLayoutContract = contract;
    _pendingReaderLayoutGeneration = generation;
    final controlledLayoutIdentity = contract.identity;
    final canonicalSession = paginator.CanonicalReaderPaginationSession(
      sourceSnapshot: canonicalSnapshot,
      controlledLayoutIdentity: controlledLayoutIdentity,
      layout: paginatorLayout,
      paginator: _readerCardPaginator,
      deferPublicationCommit: true,
    );
    final canonicalBookScopeDigest = readerSha256(<String, Object?>{
      'namespace': canonicalDisplayCacheNamespace,
      'bookId': widget.bookId,
    });
    final canonicalCompatibility = ReaderCompatibilityEvidence.fromIdentity(
      contract.identities.readerCompatibilityIdentity,
    );

    CanonicalDisplaySegmentAdmissionContext canonicalCacheContext({
      required List<CanonicalFinalizedReaderCard> acceptedCards,
      required CanonicalPaginationContinuation? acceptedRestart,
      String? expectedGeneration,
    }) => CanonicalDisplaySegmentAdmissionContext(
      bookStorageScopeDigest: canonicalBookScopeDigest,
      publicationFingerprint: canonicalSnapshot.publicationFingerprint,
      sourceSnapshot: canonicalSnapshot,
      currentCompatibilityEvidence: canonicalCompatibility,
      supportedCompatibilityRevisions:
          ReaderCompatibilityRevisionSupport.current(
            parserSourceSchemaIdentities: <String>[
              canonicalSnapshot.parserSourceIdentity,
            ],
          ),
      controlledLayoutIdentity: controlledLayoutIdentity,
      paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
      acceptedFinalizedCards: acceptedCards,
      acceptedRestart: acceptedRestart,
      expectedGeneration: expectedGeneration,
    );

    Future<void> refreshCanonicalCachePins(
      ProgressiveDisplayState state,
    ) async {
      final service = _canonicalDisplayCacheService;
      if (service == null ||
          !mounted ||
          generation != _rebuildGeneration ||
          state.canonicalCards.isEmpty) {
        return;
      }
      final current =
          state.canonicalCards[_currentPage.clamp(
            0,
            state.canonicalCards.length - 1,
          )];
      final authorization = state.authorizeCanonicalCacheRetention(
        currentCardSignature: current.identity.signature,
        residentRecords: service.memoryRecords,
      );
      if (authorization == null) return;
      final pressure = await service.applyRetentionAuthorization(authorization);
      if (!pressure.withinBudget) {
        _readerDiagLog('canonical_display_cache_pressure', {
          'book': widget.bookId,
          'generation': generation,
          'pinned': pressure.pinnedPressure,
          'records': pressure.recordCount,
          'bytes': pressure.bytes,
        });
      }
    }

    paginator.CanonicalPaginationOperationControls canonicalOperation(
      DisplayRangeRequest request,
    ) => paginator.CanonicalPaginationOperationControls(
      generationToken: request.generationId,
      scheduler: _displayRangeScheduler,
      priority: _displayRangePriority(request.direction, request.reason),
      isCancelled: () =>
          !mounted ||
          _rebuildGeneration != generation ||
          _canonicalPaginationSourceRevision(_sourceChunks) !=
              canonicalSourceRevision ||
          _cancelledProgressiveRangeGenerations.contains(request.generationId),
      currentGenerationToken: () => _progressiveRangeGeneration,
      diagnosticBookId: widget.bookId,
      // The compile-time diagnostic flag is deliberately allowed to collapse
      // this callback to the default null value in non-diagnostic builds.
      // ignore: avoid_redundant_argument_values
      onDiagnostic: _readerDiagEnabled ? _readerDiagLog : null,
    );

    CanonicalPaginationTargetCursor canonicalTarget(
      int sourceOrdinal,
      int textOffset,
    ) {
      final owner = canonicalSnapshot.ownerAt(sourceOrdinal);
      return canonicalSession.targetForStableOwner(
        sourceIdentity: owner.sourceIdentity,
        sectionIdentity: owner.sectionIdentity,
        sourceOrdinalHint: owner.sourceOrdinalHint,
        textOffsetUtf16: textOffset,
      );
    }

    CanonicalDisplayPublicationResult publishCanonicalRange(
      ProgressiveDisplayState state,
      paginator.CanonicalReaderPaginationPathAccepted accepted,
      DisplayRangeRequest request,
      CanonicalFinalizedReaderCard? committedCard, {
      CanonicalDisplaySegmentExactCandidate? cacheCandidate,
    }) {
      if (!canonicalSession.hasPendingPublication(accepted)) {
        return const CanonicalDisplayPublicationRejected(
          kind: CanonicalDisplayPublicationOutcomeKind.staleGenerationOrSession,
          message: 'Canonical session has no pending publication authority.',
        );
      }
      final operation = switch (request.direction) {
        DisplayRangeDirection.initial =>
          state.canonicalCards.isEmpty
              ? CanonicalDisplayPublicationOperation.initial
              : CanonicalDisplayPublicationOperation.replacement,
        DisplayRangeDirection.target =>
          CanonicalDisplayPublicationOperation.replacement,
        DisplayRangeDirection.forward =>
          CanonicalDisplayPublicationOperation.append,
        DisplayRangeDirection.backward =>
          CanonicalDisplayPublicationOperation.prepend,
      };
      final backward =
          accepted is paginator.CanonicalReaderBackwardPreparationAccepted
          ? accepted
          : null;
      final predecessorContinuation = state.acceptedCanonicalContinuation;
      final publishedCards =
          cacheCandidate?.finalizedCards ?? accepted.publishableCards;
      final publishedContinuation =
          cacheCandidate?.continuation ?? accepted.continuation;
      final result = state.publishCanonical(
        CanonicalDisplayPublicationRequest(
          operation: operation,
          sessionIdentity: '${canonicalSnapshot.snapshotDigest}|$generation',
          generationIdentity: request.generationId,
          currentGenerationIdentity: () => _progressiveRangeGeneration,
          sourceSnapshot: canonicalSnapshot,
          controlledLayoutIdentity: controlledLayoutIdentity,
          paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
          finalizedCards: publishedCards,
          continuation: publishedContinuation,
          predecessorContinuation: predecessorContinuation,
          targetContainment: accepted.targetContainment,
          prependEvidence: backward == null || committedCard == null
              ? null
              : CanonicalDisplayPrependEvidence(
                  acceptedPublishedPrefix: state.canonicalCards.first,
                  regeneratedPublishedPrefix:
                      backward.regeneratedPublishedPrefix,
                  acceptedCommittedCard: committedCard,
                  regeneratedCommittedCard: backward.regeneratedCommittedCard,
                  predecessorEndCursor: backward.predecessorEndCursor,
                  currentStartCursor: backward.currentStartCursor,
                  currentEndCursor: backward.currentEndCursor,
                  successorStartCursor: backward.successorStartCursor,
                ),
          committedCard:
              operation == CanonicalDisplayPublicationOperation.append ||
                  operation == CanonicalDisplayPublicationOperation.prepend
              ? committedCard
              : null,
          isCancelled: () =>
              !mounted ||
              _rebuildGeneration != generation ||
              _cancelledProgressiveRangeGenerations.contains(
                request.generationId,
              ),
        ),
      );
      if (result is CanonicalDisplayPublicationAccepted) {
        if (!canonicalSession.commitPublication(accepted)) {
          throw StateError(
            'Canonical session commit authority disappeared after validation.',
          );
        }
        final mayWrite =
            operation == CanonicalDisplayPublicationOperation.initial ||
            operation == CanonicalDisplayPublicationOperation.append ||
            (operation == CanonicalDisplayPublicationOperation.replacement &&
                predecessorContinuation == null);
        if (mayWrite) {
          final build = CanonicalDisplaySegmentRecordBuilder.buildForPublication(
            bookStorageScopeDigest: canonicalBookScopeDigest,
            compatibilityEvidence:
                CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
                  canonicalCompatibility,
                ),
            sourceSnapshot: canonicalSnapshot,
            finalizedCards: accepted.publishableCards,
            continuation: accepted.continuation,
            acceptedRestart: predecessorContinuation,
          );
          if (build is CanonicalDisplaySegmentRecordNoWrite) {
            _readerDiagLog('canonical_display_cache_write_not_admitted', {
              'book': widget.bookId,
              'generation': generation,
              'rangeGeneration': request.generationId,
              'reason': build.reason.name,
            });
          } else {
            final record = (build as CanonicalDisplaySegmentRecordBuilt).record;
            final authorization = state.authorizeCanonicalCacheWrite(record);
            final admissionContext = canonicalCacheContext(
              acceptedCards: List<CanonicalFinalizedReaderCard>.unmodifiable(
                state.canonicalCards,
              ),
              acceptedRestart: predecessorContinuation,
            );
            if (authorization != null) {
              unawaited(
                Future<void>.delayed(Duration.zero, () async {
                  try {
                    if (!mounted || generation != _rebuildGeneration) return;
                    final service = _canonicalDisplayCacheService ??=
                        await CanonicalDisplayCacheService.createDefault();
                    await service.ensureInitialized();
                    if (!mounted ||
                        token.isCancelled ||
                        generation != _rebuildGeneration) {
                      return;
                    }
                    final reuse = await service.readAndAdmit(
                      bookScopeDigest: record.bookStorageScopeDigest,
                      keyDigest: record.keyDigest,
                      admissionContext: admissionContext,
                    );
                    if (!mounted ||
                        token.isCancelled ||
                        generation != _rebuildGeneration) {
                      return;
                    }
                    if (reuse.admission.isExact) {
                      _readerDiagLog('canonical_display_cache_warm_reuse', {
                        'book': widget.bookId,
                        'generation': generation,
                        'rangeGeneration': request.generationId,
                        'source': reuse.source.name,
                        'bytesRead': reuse.bytesRead,
                      });
                      await refreshCanonicalCachePins(state);
                      return;
                    }
                    final write = await service.enqueueAuthorizedWrite(
                      record: record,
                      authorization: authorization,
                      admissionContext: admissionContext,
                      isCancelled: () =>
                          !mounted ||
                          token.isCancelled ||
                          _cancelledProgressiveRangeGenerations.contains(
                            request.generationId,
                          ),
                      isCurrent: () =>
                          mounted &&
                          !token.isCancelled &&
                          generation == _rebuildGeneration,
                    );
                    _readerDiagLog('canonical_display_cache_write', {
                      'book': widget.bookId,
                      'generation': generation,
                      'rangeGeneration': request.generationId,
                      'outcome': write.outcome.name,
                    });
                    if (write.stored) await refreshCanonicalCachePins(state);
                  } on Object catch (error) {
                    _readerDiagLog('canonical_display_cache_write_failed', {
                      'book': widget.bookId,
                      'generation': generation,
                      'error': '$error',
                    });
                  }
                }),
              );
            }
          }
        }
      } else {
        canonicalSession.rejectPublication(accepted);
      }
      return result;
    }

    Future<paginator.CanonicalReaderPaginationPathResult>
    generateCanonicalDisplayRange(DisplayRangeRequest request) {
      final operation = canonicalOperation(request);
      switch (request.direction) {
        case DisplayRangeDirection.initial:
          final target = request.targetOriginalIndex;
          if (target != null &&
              (target != 0 || (request.targetTextOffset ?? 0) != 0)) {
            return canonicalSession.generateTarget(
              target: canonicalTarget(target, request.targetTextOffset ?? 0),
              operation: operation,
            );
          }
          if (request.sourceRange.start == 0) {
            return canonicalSession.generateInitial(
              restart: const CanonicalPaginationPublicationStart(),
              operation: operation,
            );
          }
          final owner = canonicalSnapshot.ownerAt(request.sourceRange.start);
          return canonicalSession.generateInitial(
            restart: CanonicalPaginationTrustedSectionStart(
              sectionIdentity: owner.sectionIdentity,
              sourceIdentity: owner.sourceIdentity,
              sourceOrdinalHint: owner.sourceOrdinalHint,
            ),
            operation: operation,
          );
        case DisplayRangeDirection.target:
          final target = request.targetOriginalIndex;
          if (target == null) {
            return Future.value(
              const paginator.CanonicalReaderRequiredEarlierRestart(
                'Stable target evidence is required for target generation.',
              ),
            );
          }
          return canonicalSession.generateTarget(
            target: canonicalTarget(target, request.targetTextOffset ?? 0),
            operation: operation,
          );
        case DisplayRangeDirection.forward:
          final state = _progressiveDisplayState;
          if (state == null ||
              state.displayChunks.isEmpty ||
              state.displayToOriginal.isEmpty) {
            return Future.value(
              const paginator.CanonicalReaderRequiredEarlierRestart(
                'Forward generation requires an accepted published suffix.',
              ),
            );
          }
          final boundary = canonicalSession.publishedSuffixBoundary(
            card: state.displayChunks.last,
            sourceOrdinals: state.displayToOriginal.last,
          );
          if (boundary == null) {
            return Future.value(
              const paginator.CanonicalReaderPaginationPathRejected(
                CanonicalInvalidRestartSourceRejected(
                  diagnostics: CanonicalPaginationWorkDiagnostics(),
                  reason: CanonicalPaginationRejectionReason.invalidRestart,
                  message: 'Published suffix boundary no longer matches.',
                ),
              ),
            );
          }
          return canonicalSession.generateForward(
            acceptedPublishedSuffix: boundary,
            operation: operation,
          );
        case DisplayRangeDirection.backward:
          final state = _progressiveDisplayState;
          if (state == null ||
              state.displayChunks.isEmpty ||
              state.displayToOriginal.isEmpty ||
              request.sourceRange.start >=
                  state.ranges.first.sourceRange.start) {
            return Future.value(
              const paginator.CanonicalReaderRequiredEarlierRestart(
                'Backward generation requires a stable earlier source window.',
              ),
            );
          }
          final prefix = canonicalSession.acceptedPublishedCard(
            card: state.displayChunks.first,
            sourceOrdinals: state.displayToOriginal.first,
          );
          final committedDisplayIndex = _currentPage.clamp(
            0,
            state.displayChunks.length - 1,
          );
          final committed = canonicalSession.acceptedPublishedCard(
            card: state.displayChunks[committedDisplayIndex],
            sourceOrdinals: state.displayToOriginal[committedDisplayIndex],
          );
          if (prefix == null || committed == null) {
            return Future.value(
              const paginator.CanonicalReaderBackwardPreparationRejected(
                reason: paginator
                    .CanonicalReaderBackwardRejectionReason
                    .invalidPublishedPrefix,
                message:
                    'Published prefix/current card is not canonical session evidence.',
              ),
            );
          }
          final acceptedSuccessorStart = canonicalSession
              .acceptedSuccessorStartCursorFor(committed);
          if (acceptedSuccessorStart == null) {
            return Future.value(
              const paginator.CanonicalReaderBackwardPreparationRejected(
                reason: paginator
                    .CanonicalReaderBackwardRejectionReason
                    .cursorDiscontinuity,
                message:
                    'Committed successor-continuation cursor is unavailable.',
              ),
            );
          }
          return canonicalSession.generateBackward(
            desiredPredecessor: canonicalTarget(
              request.sourceRange.start,
              request.targetTextOffset ?? 0,
            ),
            acceptedPublishedPrefix: prefix,
            committedCurrentCard: committed,
            acceptedSuccessorStartCursor: acceptedSuccessorStart,
            operation: operation,
          );
      }
    }

    Future<DisplayRangeResult> generateCanonicalChapterRange(
      DisplayRangeRequest request,
      List<BookChunk> sourceChunks,
    ) async {
      final sourceRevision = _canonicalPaginationSourceRevision(sourceChunks);
      final snapshot = CanonicalPaginationSourceSnapshot.pin(
        bookId: widget.bookId,
        publicationFingerprint: _publicationFingerprint!,
        parserSourceIdentity: _canonicalParserSourceIdentity(const {}),
        sourceRevision: sourceRevision,
        sourceChunks: sourceChunks,
        sourceKeys: _canonicalPaginationSourceKeys(sourceChunks),
      );
      final session = paginator.CanonicalReaderPaginationSession(
        sourceSnapshot: snapshot,
        controlledLayoutIdentity: controlledLayoutIdentity,
        layout: paginatorLayout,
        paginator: _readerCardPaginator,
        deferPublicationCommit: true,
      );
      final temporary = ProgressiveDisplayState(
        signature: DisplayGenerationSignature(
          bookId: widget.bookId,
          parsedContentVersion: BookCacheService.parsedBookCacheFormatVersion,
          layoutSignature: controlledLayoutIdentity,
          settingsSignature: 'chapter-canonical-background',
          viewportSignature: 'chapter-canonical-background',
          cacheKey: 'chapter-canonical-background',
        ),
        sourceChunkCount: sourceChunks.length,
      );
      paginator.CanonicalReaderPaginationPathResult outcome = await session
          .generateInitial(
            restart: const CanonicalPaginationPublicationStart(),
            operation: canonicalOperation(request),
          );
      for (var step = 0; step < 64; step++) {
        if (outcome is! paginator.CanonicalReaderPaginationPathAccepted) {
          return DisplayRangeResult(
            request: request,
            displayChunks: const [],
            displayToOriginal: const [],
            originalToDisplay: const {},
            inspectedSourceChunks: 0,
            elapsedMilliseconds: 0,
            cancelled:
                outcome is paginator.CanonicalReaderPaginationPathRejected &&
                outcome.rejection is CanonicalCancelledStaleRejected,
            error: StateError('Canonical chapter generation was rejected.'),
          );
        }
        if (outcome.publishableCards.isNotEmpty) {
          final publication = temporary.publishCanonical(
            CanonicalDisplayPublicationRequest(
              operation: temporary.canonicalCards.isEmpty
                  ? CanonicalDisplayPublicationOperation.initial
                  : CanonicalDisplayPublicationOperation.append,
              sessionIdentity: '${snapshot.snapshotDigest}|chapter',
              generationIdentity: request.generationId,
              currentGenerationIdentity: () => request.generationId,
              sourceSnapshot: snapshot,
              controlledLayoutIdentity: controlledLayoutIdentity,
              paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
              finalizedCards: outcome.publishableCards,
              continuation: outcome.continuation,
              predecessorContinuation: temporary.acceptedCanonicalContinuation,
              isCancelled: canonicalOperation(request).isCancelled,
            ),
          );
          if (publication is! CanonicalDisplayPublicationAccepted ||
              !session.commitPublication(outcome)) {
            return DisplayRangeResult(
              request: request,
              displayChunks: const [],
              displayToOriginal: const [],
              originalToDisplay: const {},
              inspectedSourceChunks: 0,
              elapsedMilliseconds: 0,
              error: StateError('Canonical chapter publication was rejected.'),
            );
          }
        }
        if (outcome is paginator.CanonicalReaderLogicalEnd) {
          return DisplayRangeResult(
            request: DisplayRangeRequest(
              direction: request.direction,
              sourceRange: SourceChunkRange(0, sourceChunks.length),
              generationId: request.generationId,
              reason: request.reason,
            ),
            displayChunks: List<BookChunk>.unmodifiable(
              temporary.displayChunks,
            ),
            displayToOriginal: List<List<int>>.unmodifiable(
              temporary.displayToOriginal,
            ),
            originalToDisplay: Map<int, int>.unmodifiable(
              temporary.originalToDisplay,
            ),
            inspectedSourceChunks: sourceChunks.length,
            elapsedMilliseconds: 0,
          );
        }
        if (temporary.displayChunks.isEmpty) continue;
        final boundary = session.publishedSuffixBoundary(
          card: temporary.displayChunks.last,
          sourceOrdinals: temporary.displayToOriginal.last,
        );
        if (boundary == null) break;
        outcome = await session.generateForward(
          acceptedPublishedSuffix: boundary,
          operation: canonicalOperation(request),
        );
      }
      return DisplayRangeResult(
        request: request,
        displayChunks: const [],
        displayToOriginal: const [],
        originalToDisplay: const {},
        inspectedSourceChunks: 0,
        elapsedMilliseconds: 0,
        error: StateError('Canonical chapter generation bound was exhausted.'),
      );
    }

    _progressiveRangeGenerator = generateCanonicalDisplayRange;
    _progressiveCanonicalPublisher = publishCanonicalRange;
    _chapterDisplayRangeGenerator = generateCanonicalChapterRange;

    final signature = _displayGenerationCoordinator.activeToken?.signature;
    if (signature == null) return;
    final progressiveState = ProgressiveDisplayState(
      signature: signature,
      sourceChunkCount: _sourceChunks.length,
    );
    _applyLazyExternalAvailability(progressiveState);
    _progressiveDisplayState = progressiveState;
    final startIndex = _targetOriginalIndex.clamp(0, _sourceChunks.length - 1);
    final isLazySession = _lazySession != null;
    final nearbyInitialRange = progressiveState.initialSourceRange(
      targetOriginalIndex: startIndex,
      lookBehind: isLazySession
          ? _lazyInitialRangeLookBehind
          : _initialRangeLookBehind,
      lookAhead: isLazySession
          ? _lazyInitialRangeLookAhead
          : _initialRangeLookAhead,
      minimumWindow: isLazySession
          ? _lazyMinimumInitialRangeSourceChunks
          : _minimumInitialRangeSourceChunks,
    );
    final initialRange = readerFirstVisibleSourceRange(
      targetOriginalIndex: startIndex,
      sourceChunkCount: _sourceChunks.length,
      lazy: isLazySession,
      nearbyRange: nearbyInitialRange,
      lazyEndExclusive: isLazySession
          ? anchoredInitialRangeEndExclusive(startIndex)
          : null,
    );
    final anchorTextOffset =
        (layoutRestoreLocation ?? _pendingExactStableRestore)?.textOffset ?? 0;
    // Legacy segmented entries cannot carry P04 continuation authority. Do
    // not perform a guaranteed-rejection disk read on the first-card path.
    final rangeGeneration = ++_progressiveRangeGeneration;
    final initialRequest = DisplayRangeRequest(
      direction: DisplayRangeDirection.initial,
      sourceRange: initialRange,
      generationId: rangeGeneration,
      reason: 'initial_open',
      targetOriginalIndex: startIndex,
      targetTextOffset: anchorTextOffset,
    );

    _readerDiagLog('progressive_generation_begin', {
      'book': widget.bookId,
      'generation': generation,
      'rangeGeneration': rangeGeneration,
      'sourceChunks': _sourceChunks.length,
    });
    _readerDiagLog('initial_range_begin', {
      'book': widget.bookId,
      'generation': generation,
      'rangeGeneration': rangeGeneration,
      'sourceStart': initialRange.start,
      'sourceEndExclusive': initialRange.endExclusive,
      'targetOriginalIndex': startIndex,
    });

    final initialOutcome = await generateCanonicalDisplayRange(initialRequest);
    if (!mounted || _rebuildGeneration != generation) {
      _readerDiagLog('range_cancel', {
        'book': widget.bookId,
        'generation': generation,
        'rangeGeneration': rangeGeneration,
        'direction': DisplayRangeDirection.initial.name,
        'reason': 'stale_initial_generation',
      });
      return;
    }
    if (initialOutcome is paginator.CanonicalReaderPaginationPathRejected) {
      final rejection = initialOutcome.rejection;
      if (rejection is CanonicalCancelledStaleRejected) {
        _readerDiagLog('range_cancel', {
          'book': widget.bookId,
          'generation': generation,
          'rangeGeneration': rangeGeneration,
          'direction': DisplayRangeDirection.initial.name,
          'reason': rejection.reason.name,
        });
        return;
      }
      throw ReaderPreparationException(
        rejection.message.contains('table')
            ? ReaderPreparationFailureKind.malformedTable
            : ReaderPreparationFailureKind.paginationRejected,
        rejection.message,
      );
    }
    if (initialOutcome is paginator.CanonicalReaderRequiredEarlierRestart) {
      throw ReaderPreparationException(
        ReaderPreparationFailureKind.paginationRejected,
        initialOutcome.message,
      );
    }
    if (initialOutcome
            is paginator.CanonicalReaderProvisionalBudgetExhaustion &&
        initialOutcome.publishableCards.isEmpty) {
      _readerDiagLog('canonical_provisional_no_publication', {
        'book': widget.bookId,
        'generation': generation,
        'rangeGeneration': rangeGeneration,
        'direction': DisplayRangeDirection.initial.name,
        'checkpoint': initialOutcome.continuation.integrityDigest,
      });
      throw const ReaderPreparationException(
        ReaderPreparationFailureKind.paginationRejected,
        'Pagination exhausted its bounded budget before producing a card.',
      );
    }
    final acceptedInitial =
        initialOutcome as paginator.CanonicalReaderPaginationPathAccepted;
    if (acceptedInitial.publishableCards.isEmpty) {
      _readerDiagLog('canonical_provisional_no_publication', {
        'book': widget.bookId,
        'generation': generation,
        'rangeGeneration': rangeGeneration,
        'direction': DisplayRangeDirection.initial.name,
      });
      throw const ReaderPreparationException(
        ReaderPreparationFailureKind.paginationRejected,
        'Pagination completed without producing a readable card.',
      );
    }
    final initialResult = paginator.canonicalPathDisplayResult(
      accepted: acceptedInitial,
      request: initialRequest,
      publicationStart: initialRange.start,
    );
    final initialPublication = publishCanonicalRange(
      progressiveState,
      acceptedInitial,
      initialRequest,
      null,
    );
    if (initialPublication is! CanonicalDisplayPublicationAccepted) {
      _readerDiagLog('canonical_publication_rejected', {
        'book': widget.bookId,
        'generation': generation,
        'rangeGeneration': rangeGeneration,
        'direction': DisplayRangeDirection.initial.name,
        'reason': initialPublication.kind.name,
      });
      return;
    }
    progressiveState.sourceChunkCount =
        _progressiveSourceCountForLoadedWindow();
    _applyLazyExternalAvailability(progressiveState);
    progressiveState.generationComplete =
        !progressiveState.externalUnavailableBefore &&
        !progressiveState.externalUnavailableAfter &&
        initialResult.request.sourceRange.start == 0 &&
        initialResult.request.sourceRange.endExclusive >=
            progressiveState.sourceChunkCount;
    if (!_applyProgressiveDisplayState(progressiveState)) return;
    _displayChunksComplete = progressiveState.generationComplete;
    _hasCompletedDisplayChunkBuild = true;

    _readerDiagLog('reader_display_initial_window_candidate', {
      'book': widget.bookId,
      'generation': generation,
      'elapsedMs': fullRebuildStopwatch.elapsedMilliseconds,
      'sourceStartIndex': initialRange.start,
      'candidateDisplayChunks': initialResult.displayChunks.length,
      'existingDisplayChunks': _displayChunks.length,
      'sourceChunksCovered': initialResult.originalToDisplay.length,
    });
    _readerDiagLog('initial_range_ready', {
      'book': widget.bookId,
      'generation': generation,
      'rangeGeneration': rangeGeneration,
      'elapsedMs': initialResult.elapsedMilliseconds,
      'sourceStart': initialResult.request.sourceRange.start,
      'sourceEndExclusive': initialResult.request.sourceRange.endExclusive,
      'sourceCeilingEndExclusive': initialRange.endExclusive,
      'inspectedSourceChunks': initialResult.inspectedSourceChunks,
      'displayChunks': initialResult.displayChunks.length,
      'sliceCount': initialResult.sliceCount,
      'yieldCount': initialResult.yieldCount,
      'longestWorkIntervalMs': initialResult.longestWorkIntervalMilliseconds,
      'maxSliceDurationMs': initialResult.maxSliceDurationMilliseconds,
      'totalYieldMs': initialResult.totalYieldMilliseconds,
      'maxSourceChunksPerSlice': initialResult.maxSourceChunksPerSlice,
      'maxDisplayChunksPerSlice': initialResult.maxDisplayChunksPerSlice,
      'hasEarlierContent': progressiveState.hasUnavailableBefore,
      'hasLaterContent': progressiveState.hasUnavailableAfter,
    });
    _readerDiagLog('reader_display_initial_window_ready', {
      'book': widget.bookId,
      'generation': generation,
      'elapsedMs': fullRebuildStopwatch.elapsedMilliseconds,
      'sourceStartIndex': initialRange.start,
      'sourceChunksCovered': initialResult.originalToDisplay.length,
      'displayChunks': initialResult.displayChunks.length,
      'hasEarlierContent': progressiveState.hasUnavailableBefore,
      'hasLaterContent': progressiveState.hasUnavailableAfter,
    });
    if (mounted) setState(() {});
    _scheduleLazyInitialAdjacentWarmup();

    if (isLazySession) {
      unawaited(
        _prepareRequiredLazyDisplayRanges(
          progressiveState: progressiveState,
          targetOriginalIndex: startIndex,
          generation: generation,
          generator: generateCanonicalDisplayRange,
        ),
      );
    }

    final forwardRange = progressiveState.nextForwardRange(
      _adjacentRangeSourceChunks,
    );
    if (forwardRange != null) {
      _readerDiagLog('range_request', {
        'book': widget.bookId,
        'generation': generation,
        'direction': DisplayRangeDirection.forward.name,
        'sourceStart': forwardRange.start,
        'sourceEndExclusive': forwardRange.endExclusive,
        'reason': 'initial_bounded_lookahead',
      });
      if (_lazySession != null) {
        _readerDiagLog('range_request_skipped_lazy_initial_lookahead', {
          'book': widget.bookId,
          'generation': generation,
          'sourceStart': forwardRange.start,
          'sourceEndExclusive': forwardRange.endExclusive,
          'reason': 'lazy_initial_window_ready',
        });
      } else if (_isLazyForwardSentinelRange(forwardRange)) {
        unawaited(_loadLazyForwardSectionAndPrepareRange());
      } else {
        unawaited(
          _prepareProgressiveDisplayRange(
            direction: DisplayRangeDirection.forward,
            sourceRange: forwardRange,
            reason: 'initial_bounded_lookahead',
            generator: generateCanonicalDisplayRange,
            parentGeneration: generation,
          ),
        );
      }
    }

    fullRebuildStopwatch.stop();
    _markDisplayRebuildCompleted(generation, signature);
    _readerDiagLog('reader_display_rebuild_end', {
      'book': widget.bookId,
      'generation': generation,
      'elapsedMs': fullRebuildStopwatch.elapsedMilliseconds,
      'displayChunks': _displayChunks.length,
      'displayToOriginal': _displayToOriginal.length,
      'originalToDisplay': _originalToDisplay.length,
      'complete': _displayChunksComplete,
      'mode': 'progressive_initial_range',
    });
  }

  Future<void> _prepareRequiredLazyDisplayRanges({
    required ProgressiveDisplayState progressiveState,
    required int targetOriginalIndex,
    required int generation,
    required ProgressiveDisplayRangeGenerator generator,
  }) async {
    if (!mounted || generation != _rebuildGeneration) return;
    final preparedRange = progressiveState.preparedSourceRange;
    if (preparedRange == null) return;
    final forward = SourceChunkRange(
      preparedRange.endExclusive,
      math.min(
        _sourceChunks.length,
        preparedRange.endExclusive + _lazyInitialRangeLookAhead,
      ),
    );
    if (!forward.isEmpty) {
      await _prepareProgressiveDisplayRange(
        direction: DisplayRangeDirection.forward,
        sourceRange: forward,
        reason: 'lazy_required_forward_cards',
        generator: generator,
        parentGeneration: generation,
      );
    }
    if (!mounted || generation != _rebuildGeneration) return;
    final backward = SourceChunkRange(
      math.max(0, targetOriginalIndex - _lazyInitialRangeLookBehind),
      preparedRange.start,
    );
    if (!backward.isEmpty) {
      await _prepareProgressiveDisplayRange(
        direction: DisplayRangeDirection.backward,
        sourceRange: backward,
        reason: 'lazy_required_backward_card',
        generator: generator,
        parentGeneration: generation,
      );
    }
  }

  bool _applyProgressiveDisplayState(ProgressiveDisplayState state) {
    final pendingContract = _pendingReaderLayoutGeneration == _rebuildGeneration
        ? _pendingReaderLayoutContract
        : null;
    final publicationContract = pendingContract ?? _activeReaderLayoutContract;
    if (publicationContract != null) {
      final geometryCurrent =
          publicationContract.environment.outerDeckSize == _lastScreenSize &&
          publicationContract.environment.viewPadding == _lastSafeArea;
      final layoutsComplete =
          state.canonicalCards.length == state.displayChunks.length &&
          state.canonicalCards.every((card) {
            final layout = card.resolvedLayout;
            if (layout == null ||
                layout.contractIdentity != publicationContract.identity ||
                layout.blocks.length != 1) {
              return false;
            }
            final block = layout.blocks.single;
            return block.stableBlockOwner ==
                    canonicalBookChunkOwnershipDigest(card.card) &&
                block.fontEvidenceDigest.isNotEmpty &&
                block.overflowFits &&
                (block.blockKind != ReaderResolvedBlockKind.image ||
                    block.image != null);
          });
      if (!geometryCurrent || !layoutsComplete) {
        _readerDiagLog('reader_layout_atomic_publication_rejected', {
          'book': widget.bookId,
          'geometryCurrent': geometryCurrent,
          'layoutsComplete': layoutsComplete,
          'candidateCards': state.canonicalCards.length,
        });
        return false;
      }
    }
    final committedCheckpoint = _checkpointCoordinator?.current;
    final visibleBefore = _cardIdentityForDisplay(_currentPage);
    final anchor =
        _visiblePositionCoordinator.authoritativeTarget ??
        _pendingDisplayNavigationToken?.target;
    final layoutFingerprint = publicationContract?.identity;
    final protectExactSignature =
        anchor == _visiblePositionCoordinator.committedLocation &&
            committedCheckpoint?.state ==
                ReaderCheckpointState.exactCommitted &&
            committedCheckpoint?.layoutFingerprint == layoutFingerprint &&
            committedCheckpoint?.card?.signature == visibleBefore?.signature &&
            _activeCheckpointLayoutToken == null &&
            !_positionSession.hasActivePreviewPosition
        ? visibleBefore?.signature
        : null;
    final oldDisplayIndex = _currentPage;
    final activeVisibleIntent = _visiblePositionCoordinator.activeIntent;

    // Resolve every stable coordinate against the private accepted candidate
    // before any live screen/controller/publication state is changed.
    final candidateIdentities = <ReaderCardIdentity>[];
    final publicationFingerprint = _publicationFingerprint;
    if (layoutFingerprint != null && publicationFingerprint != null) {
      for (var index = 0; index < state.displayChunks.length; index++) {
        candidateIdentities.add(
          ReaderCardIdentity.fromCard(
            publicationFingerprint: publicationFingerprint,
            layoutFingerprint: layoutFingerprint,
            card: state.displayChunks[index],
            sourceChunks: _sourceChunks,
            sourceIndices: state.displayToOriginal[index],
            locationsBySourceIndex: _sourceLocationsByChunkIndex,
            stableSourceKeys: {
              for (final entry in _sourceIdentitiesByChunkIndex.entries)
                entry.key: entry.value.stableKey,
            },
          ),
        );
      }
    }
    int? anchorIndex;
    if (protectExactSignature != null) {
      final exactIndex = candidateIdentities.indexWhere(
        (card) => card.signature == protectExactSignature,
      );
      if (exactIndex >= 0) anchorIndex = exactIndex;
    }
    anchorIndex ??= anchor == null
        ? null
        : readerDisplayIndexForStableLocation(
            location: anchor,
            displayChunks: state.displayChunks,
            locationsByChunkIndex: _sourceLocationsByChunkIndex,
            sourceIdentitiesByChunkIndex: _sourceIdentitiesByChunkIndex,
          );
    final exactMissing =
        protectExactSignature != null &&
        candidateIdentities.every(
          (card) => card.signature != protectExactSignature,
        );
    if (anchor != null && (anchorIndex == null || exactMissing)) {
      _readerDiagLog('lazy_window_publication_rejected', {
        'book': widget.bookId,
        'reason': exactMissing
            ? 'committed_exact_card_missing'
            : 'authoritative_anchor_unresolved',
        'committedCardSignature': protectExactSignature,
        'candidateDisplayCards': state.displayChunks.length,
      });
      _logVisiblePositionMutation(
        reason: 'progressive_window_publication',
        classification: ReaderVisibleMutationClassification.synthetic,
        accepted: false,
        decisionReason: exactMissing
            ? 'committed_exact_card_missing'
            : 'authoritative_anchor_unresolved',
        oldLocation: anchor,
        newLocation: anchor,
        oldLocalIndex: oldDisplayIndex,
        newLocalIndex: oldDisplayIndex,
      );
      return false;
    }

    if (pendingContract != null) {
      _activeReaderLayoutContract = pendingContract;
      _activeReaderLayoutFingerprint = pendingContract.identity;
      _pendingReaderLayoutContract = null;
      _pendingReaderLayoutGeneration = null;
    }

    _displayChunks
      ..clear()
      ..addAll(state.displayChunks);
    _resolvedDisplayLayouts = publicationContract == null
        ? List<ResolvedReaderCardLayout?>.filled(
            state.displayChunks.length,
            null,
          )
        : List<ResolvedReaderCardLayout?>.unmodifiable(
            state.canonicalCards.map((card) => card.resolvedLayout),
          );
    _displayToOriginal
      ..clear()
      ..addAll(state.displayToOriginal);
    _originalToDisplay
      ..clear()
      ..addAll(state.originalToDisplay);
    _publishCurrentSourceOwnership(completeNavigationPublication: false);
    _displayChunksComplete = state.generationComplete;
    _isPreparingTargetRange = false;

    final publicationIntent =
        activeVisibleIntent != null &&
            anchor == activeVisibleIntent.target &&
            _visiblePositionCoordinator.markWindowPublished(
              intent: activeVisibleIntent,
              resolvedLocation: anchor!,
              windowGeneration: _rebuildGeneration,
              publicationGeneration: _progressiveRangeGeneration,
            )
        ? activeVisibleIntent
        : null;

    _completeCurrentSourcePublication();
    if (anchorIndex == null || anchorIndex == oldDisplayIndex) return true;
    final resolvedAnchorIndex = anchorIndex;
    _logVisiblePositionMutation(
      reason: 'progressive_window_anchor_index_assignment',
      classification: publicationIntent == null
          ? ReaderVisibleMutationClassification.synthetic
          : ReaderVisibleMutationClassification.programmatic,
      accepted: true,
      decisionReason: 'authoritative_anchor_resolved_in_candidate',
      oldLocation: anchor,
      newLocation: anchor,
      oldLocalIndex: oldDisplayIndex,
      newLocalIndex: resolvedAnchorIndex,
      intent: publicationIntent,
    );
    _currentPage = resolvedAnchorIndex;
    _activeDisplayIndex = resolvedAnchorIndex;
    _syncRestoreTargetFromDisplayIndex(resolvedAnchorIndex);
    if (publicationIntent == null) {
      _syntheticControllerTargetIndex = resolvedAnchorIndex;
    } else if (_syntheticControllerTargetIndex == resolvedAnchorIndex) {
      _syntheticControllerTargetIndex = null;
    }
    _logVisiblePositionMutation(
      reason: 'progressive_window_anchor_rebase',
      classification: publicationIntent == null
          ? ReaderVisibleMutationClassification.synthetic
          : ReaderVisibleMutationClassification.programmatic,
      accepted: true,
      decisionReason: 'authoritative_anchor_preserved',
      oldLocation: anchor,
      newLocation: anchor,
      oldLocalIndex: oldDisplayIndex,
      newLocalIndex: resolvedAnchorIndex,
      intent: publicationIntent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _authoritativeVisibleAnchor() != anchor ||
          _currentPage != resolvedAnchorIndex ||
          _usesInteractiveCardDeck ||
          _pageController?.hasClients != true) {
        return;
      }
      _logVisiblePositionMutation(
        reason: 'progressive_window_controller_rebase',
        classification: ReaderVisibleMutationClassification.synthetic,
        accepted: true,
        decisionReason: 'controller_reindexed_to_preserved_anchor',
        oldLocation: anchor,
        newLocation: anchor,
        oldLocalIndex: oldDisplayIndex,
        newLocalIndex: resolvedAnchorIndex,
      );
      _pageController!.jumpToPage(resolvedAnchorIndex);
    });
    return true;
  }

  void _publishCurrentSourceOwnership({
    bool completeNavigationPublication = true,
  }) {
    _publishedSourceChunks = List<BookChunk>.from(_sourceChunks);
    _publishedSourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
      _sourceLocationsByChunkIndex,
    );
    _publishedSourceIdentitiesByChunkIndex =
        Map<int, LazySourceChunkIdentity>.from(_sourceIdentitiesByChunkIndex);
    if (completeNavigationPublication) _completeCurrentSourcePublication();
  }

  void _completeCurrentSourcePublication() {
    final navigationToken = _pendingDisplayNavigationToken;
    _navigationPublicationCoordinator.markReadablePublished(navigationToken);
    _pendingDisplayNavigationToken = null;
  }

  void _markDisplayRebuildCompleted(
    int generation,
    DisplayGenerationSignature signature,
  ) {
    _lastCompletedDisplayRebuildGeneration = generation;
    _lastCompletedDisplayRebuildCacheKey = signature.cacheKey;
    _lastCompletedDisplayRebuildSignature = signature;
    _lastCompletedDisplayRebuildAtMs = DateTime.now().millisecondsSinceEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _rebuildGeneration ||
          _displayChunks.isEmpty) {
        return;
      }
      _scheduleDerivedIndexWhenQuiet();
    });
  }

  Future<SegmentedDisplayCacheService> _segmentedDisplayCache() async {
    final existing = _segmentedDisplayCacheService;
    if (existing != null) return existing;
    final created = await SegmentedDisplayCacheService.createDefault();
    _segmentedDisplayCacheService = created;
    return created;
  }

  SegmentedDisplayCacheKey _segmentedDisplayCacheKey({
    required String cacheKey,
    required DisplayGenerationSignature signature,
    SourceChunkRange? sourceRange,
    int? sourceIndex,
  }) {
    final scope = _segmentedDisplayCacheScope(
      cacheKey,
      sourceRange: sourceRange,
      sourceIndex: sourceIndex,
    );
    return SegmentedDisplayCacheKey(
      bookId: widget.bookId,
      cacheKey: scope.cacheKey,
      signature: signature,
      sourceChunkCount: scope.sourceChunkCount,
    );
  }

  ({String cacheKey, int sourceChunkCount}) _segmentedDisplayCacheScope(
    String cacheKey, {
    SourceChunkRange? sourceRange,
    int? sourceIndex,
  }) {
    final sectionScoped = _sectionScopedSegmentedCacheKey(
      cacheKey,
      sourceRange: sourceRange,
      sourceIndex: sourceIndex,
    );
    if (sectionScoped != null) return sectionScoped;
    if (_lazySession == null || _sourceLocationsByChunkIndex.isEmpty) {
      return (cacheKey: cacheKey, sourceChunkCount: _sourceChunks.length);
    }
    final sectionIds =
        _sourceLocationsByChunkIndex.values
            .map(
              (location) =>
                  '${location.spineIndex}_${_shortCacheId(location.sourceChecksum)}',
            )
            .toSet()
            .toList()
          ..sort();
    return (
      cacheKey: '${cacheKey}_lazy_${sectionIds.join('_')}',
      sourceChunkCount: _sourceChunks.length,
    );
  }

  ({String cacheKey, int sourceChunkCount})? _sectionScopedSegmentedCacheKey(
    String cacheKey, {
    SourceChunkRange? sourceRange,
    int? sourceIndex,
  }) {
    if (_lazySession == null || _sourceLocationsByChunkIndex.isEmpty) {
      return null;
    }
    int? spineIndex;
    if (sourceRange != null) {
      final spines = <int>{};
      for (var i = sourceRange.start; i < sourceRange.endExclusive; i++) {
        final location = _sourceLocationsByChunkIndex[i];
        if (location == null) return null;
        spines.add(location.spineIndex);
      }
      if (spines.length != 1) return null;
      spineIndex = spines.single;
    } else if (sourceIndex != null) {
      spineIndex = _sourceLocationsByChunkIndex[sourceIndex]?.spineIndex;
    }
    if (spineIndex == null) return null;

    int? firstSourceIndex;
    int? lastSourceIndex;
    String? checksum;
    for (final entry in _sourceLocationsByChunkIndex.entries) {
      final location = entry.value;
      if (location.spineIndex != spineIndex) continue;
      firstSourceIndex = firstSourceIndex == null
          ? entry.key
          : math.min(firstSourceIndex, entry.key);
      lastSourceIndex = lastSourceIndex == null
          ? entry.key
          : math.max(lastSourceIndex, entry.key);
      checksum ??= location.sourceChecksum;
    }
    if (firstSourceIndex == null ||
        lastSourceIndex == null ||
        checksum == null ||
        firstSourceIndex != 0) {
      return null;
    }
    final sourceChunkCount = lastSourceIndex + 1;
    return (
      cacheKey: '${cacheKey}_lazy_${spineIndex}_${_shortCacheId(checksum)}',
      sourceChunkCount: sourceChunkCount,
    );
  }

  String _shortCacheId(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (sanitized.isEmpty) return 'unknown';
    return sanitized.length <= 12 ? sanitized : sanitized.substring(0, 12);
  }

  String _stableReaderCacheId(String value) {
    var hash = 0xcbf29ce484222325;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  // Retained only for migration diagnostics; canonical startup never awaits
  // this guaranteed-rejection legacy path.
  // ignore: unused_element
  Future<bool> _loadProgressiveSegmentsAroundSource({
    required String cacheKey,
    required DisplayGenerationSignature signature,
    required ProgressiveDisplayState progressiveState,
    required int targetOriginalIndex,
    required int generation,
  }) async {
    final service = await _segmentedDisplayCache();
    final key = _segmentedDisplayCacheKey(
      cacheKey: cacheKey,
      signature: signature,
      sourceIndex: targetOriginalIndex,
    );
    final protectedRange = progressiveState.targetRange(
      targetOriginalIndex: targetOriginalIndex,
      lookBehind: _lazyInitialRangeLookBehind,
      lookAhead: _lazyInitialRangeLookAhead,
      minimumWindow: _lazyMinimumInitialRangeSourceChunks,
    );
    service.protectActiveRanges(
      bookId: widget.bookId,
      cacheKey: key.cacheKey,
      layoutIdentity: service.layoutIdentityForKey(key),
      ranges: [protectedRange],
    );
    final loaded = await service.loadAroundSource(
      key: key,
      sourceIndex: targetOriginalIndex,
    );
    final center = loaded.center;
    if (center == null) return false;
    if (!mounted || _rebuildGeneration != generation) return false;
    final admission = CanonicalDisplaySegmentAdmission.legacySafeMiss(
      cacheKind: 'segmented',
    );
    final rejection = progressiveState.rejectNonCanonicalCachePublication(
      cacheKind: 'segmented',
    );
    _readerDiagLog('segment_cache_record_found', {
      'book': widget.bookId,
      'generation': generation,
      'targetOriginalIndex': targetOriginalIndex,
      'sourceStart': center.record.sourceStart,
      'sourceEndExclusive': center.record.sourceEndExclusive,
      'displayChunks': center.displayChunks.length,
    });
    _readerDiagLog('segment_cache_publication_rejected', {
      'book': widget.bookId,
      'generation': generation,
      'reason': rejection.kind.name,
      'admission': admission.outcome.name,
    });
    return false;
  }

  // Retained for P06 canonical cache integration.
  // ignore: unused_element
  Future<void> _cacheProgressiveDisplayRange({
    required String cacheKey,
    required DisplayGenerationSignature signature,
    required DisplayRangeResult result,
    required int generationId,
  }) async {
    final token = _displayGenerationCoordinator.activeToken;
    if (token == null || !identical(token.signature, signature)) return;
    _displaySectionMemoryCache.put(cacheKey: cacheKey, result: result);
    _pinDisplayMemoryToPreparedRanges(cacheKey);
    final service = await _segmentedDisplayCache();
    await _cacheCompleteSectionScopedDisplayRanges(
      service: service,
      cacheKey: cacheKey,
      signature: signature,
      result: result,
      generationId: generationId,
      shouldWrite: () =>
          _displayGenerationCoordinator.canWriteCache(token, cacheKey) &&
          !_cancelledProgressiveRangeGenerations.contains(generationId),
    );
    final segmentedKey = _segmentedDisplayCacheKey(
      cacheKey: cacheKey,
      signature: signature,
      sourceRange: result.request.sourceRange,
    );
    service.protectActiveRanges(
      bookId: widget.bookId,
      cacheKey: segmentedKey.cacheKey,
      layoutIdentity: service.layoutIdentityForKey(segmentedKey),
      ranges: [result.request.sourceRange],
    );
    await service.writeSegment(
      key: segmentedKey,
      result: result,
      generationId: generationId,
      shouldWrite: () =>
          _displayGenerationCoordinator.canWriteCache(token, cacheKey) &&
          !_cancelledProgressiveRangeGenerations.contains(generationId),
    );
    _readerDiagLog('section_scoped_segment_write_after_primary', {
      'book': widget.bookId,
      'generationId': generationId,
      'resultStart': result.request.sourceRange.start,
      'resultEndExclusive': result.request.sourceRange.endExclusive,
      'displayChunks': result.displayChunks.length,
      'displayToOriginal': result.displayToOriginal.length,
      'sourceLocations': _sourceLocationsByChunkIndex.length,
      'canWrite':
          _displayGenerationCoordinator.canWriteCache(token, cacheKey) &&
          !_cancelledProgressiveRangeGenerations.contains(generationId),
    });
  }

  Future<void> _cacheCompleteSectionScopedDisplayRanges({
    required SegmentedDisplayCacheService service,
    required String cacheKey,
    required DisplayGenerationSignature signature,
    required DisplayRangeResult result,
    required int generationId,
    required bool Function() shouldWrite,
  }) async {
    _readerDiagLog('section_scoped_segment_write_scan', {
      'book': widget.bookId,
      'generationId': generationId,
      'hasLazySession': _lazySession != null,
      'sourceLocations': _sourceLocationsByChunkIndex.length,
      'resultStart': result.request.sourceRange.start,
      'resultEndExclusive': result.request.sourceRange.endExclusive,
      'displayChunks': result.displayChunks.length,
      'displayToOriginal': result.displayToOriginal.length,
      'canWrite': shouldWrite(),
    });
    if (_lazySession == null || _sourceLocationsByChunkIndex.isEmpty) {
      _readerDiagLog('section_scoped_segment_write_skipped', {
        'book': widget.bookId,
        'generationId': generationId,
        'reason': _lazySession == null
            ? 'no_lazy_session'
            : 'no_source_locations',
        'resultStart': result.request.sourceRange.start,
        'resultEndExclusive': result.request.sourceRange.endExclusive,
      });
      return;
    }
    final boundsBySpine = <int, ({int first, int last, String checksum})>{};
    for (final entry in _sourceLocationsByChunkIndex.entries) {
      final location = entry.value;
      final existing = boundsBySpine[location.spineIndex];
      boundsBySpine[location.spineIndex] = existing == null
          ? (
              first: entry.key,
              last: entry.key,
              checksum: location.sourceChecksum,
            )
          : (
              first: math.min(existing.first, entry.key),
              last: math.max(existing.last, entry.key),
              checksum: existing.checksum,
            );
    }

    _readerDiagLog('section_scoped_segment_write_bounds', {
      'book': widget.bookId,
      'generationId': generationId,
      'spines': boundsBySpine.keys.toList(growable: false).join(','),
      'bounds': boundsBySpine.entries
          .map(
            (entry) =>
                '${entry.key}:${entry.value.first}-${entry.value.last + 1}',
          )
          .join(','),
      'resultStart': result.request.sourceRange.start,
      'resultEndExclusive': result.request.sourceRange.endExclusive,
      'canWrite': shouldWrite(),
    });

    for (final entry in boundsBySpine.entries) {
      final spineIndex = entry.key;
      final bounds = entry.value;
      final sectionRange = SourceChunkRange(bounds.first, bounds.last + 1);
      if (result.request.sourceRange.start > sectionRange.start ||
          result.request.sourceRange.endExclusive < sectionRange.endExclusive) {
        _readerDiagLog('section_scoped_segment_write_skipped', {
          'book': widget.bookId,
          'spineIndex': spineIndex,
          'reason': 'section_not_fully_covered',
          'resultStart': result.request.sourceRange.start,
          'resultEndExclusive': result.request.sourceRange.endExclusive,
          'sectionStart': sectionRange.start,
          'sectionEndExclusive': sectionRange.endExclusive,
        });
        continue;
      }

      final selectedDisplayIndexes = <int>[];
      for (var i = 0; i < result.displayToOriginal.length; i++) {
        final originals = result.displayToOriginal[i];
        if (originals.isEmpty ||
            originals.any((index) => !sectionRange.contains(index))) {
          continue;
        }
        selectedDisplayIndexes.add(i);
      }
      if (selectedDisplayIndexes.isEmpty) {
        _readerDiagLog('section_scoped_segment_write_skipped', {
          'book': widget.bookId,
          'spineIndex': spineIndex,
          'reason': 'no_display_chunks_for_section',
          'resultStart': result.request.sourceRange.start,
          'resultEndExclusive': result.request.sourceRange.endExclusive,
          'sectionStart': sectionRange.start,
          'sectionEndExclusive': sectionRange.endExclusive,
          'displayChunks': result.displayChunks.length,
          'displayToOriginal': result.displayToOriginal.length,
        });
        continue;
      }

      final selected = <BookChunk>[];
      final displayToOriginal = <List<int>>[];
      final originalToDisplay = <int, int>{};
      for (
        var localDisplay = 0;
        localDisplay < selectedDisplayIndexes.length;
        localDisplay++
      ) {
        final displayIndex = selectedDisplayIndexes[localDisplay];
        selected.add(
          _shiftDisplayChunkSourceIndexes(
            result.displayChunks[displayIndex],
            delta: -sectionRange.start,
            displayIndex: localDisplay,
          ),
        );
        final localOriginals = result.displayToOriginal[displayIndex]
            .map((index) => index - sectionRange.start)
            .toList();
        displayToOriginal.add(localOriginals);
        for (final original in localOriginals) {
          originalToDisplay.putIfAbsent(original, () => localDisplay);
        }
      }

      _readerDiagLog('section_scoped_segment_write_started', {
        'book': widget.bookId,
        'spineIndex': spineIndex,
        'sectionStart': sectionRange.start,
        'sectionEndExclusive': sectionRange.endExclusive,
        'displayChunks': selected.length,
        'sourceChunkCount': sectionRange.length,
      });
      final sectionResult = DisplayRangeResult(
        request: DisplayRangeRequest(
          direction: result.request.direction,
          sourceRange: SourceChunkRange(0, sectionRange.length),
          generationId: generationId,
          reason: '${result.request.reason}_section_scoped',
          targetOriginalIndex:
              result.request.targetOriginalIndex != null &&
                  sectionRange.contains(result.request.targetOriginalIndex!)
              ? result.request.targetOriginalIndex! - sectionRange.start
              : null,
        ),
        displayChunks: selected,
        displayToOriginal: displayToOriginal,
        originalToDisplay: originalToDisplay,
        inspectedSourceChunks: sectionRange.length,
        elapsedMilliseconds: result.elapsedMilliseconds,
        sliceCount: result.sliceCount,
        yieldCount: result.yieldCount,
        longestWorkIntervalMilliseconds: result.longestWorkIntervalMilliseconds,
        maxSliceDurationMilliseconds: result.maxSliceDurationMilliseconds,
        totalYieldMilliseconds: result.totalYieldMilliseconds,
        maxSourceChunksPerSlice: result.maxSourceChunksPerSlice,
        maxDisplayChunksPerSlice: result.maxDisplayChunksPerSlice,
      );
      await service.writeSegment(
        key: SegmentedDisplayCacheKey(
          bookId: widget.bookId,
          cacheKey:
              '${cacheKey}_lazy_${spineIndex}_${_shortCacheId(bounds.checksum)}',
          signature: signature,
          sourceChunkCount: sectionRange.length,
        ),
        result: sectionResult,
        generationId: generationId,
        shouldWrite: shouldWrite,
      );
    }
  }

  BookChunk _shiftDisplayChunkSourceIndexes(
    BookChunk chunk, {
    required int delta,
    required int displayIndex,
  }) {
    return chunk.copyWith(
      index: displayIndex,
      sourceRanges: chunk.sourceRanges
          ?.map(
            (range) => ChunkSourceRange(
              originalChunkIndex: range.originalChunkIndex + delta,
              originalStartOffset: range.originalStartOffset,
              originalEndOffset: range.originalEndOffset,
              displayStartOffset: range.displayStartOffset,
              displayEndOffset: range.displayEndOffset,
              logicalParagraphId: range.logicalParagraphId,
              paragraphStartOffset: range.paragraphStartOffset,
              paragraphEndOffset: range.paragraphEndOffset,
              isParagraphStart: range.isParagraphStart,
              isParagraphEnd: range.isParagraphEnd,
            ),
          )
          .toList(),
    );
  }

  void _pinDisplayMemoryToPreparedRanges(String cacheKey) {
    final state = _progressiveDisplayState;
    if (state == null) return;
    _displaySectionMemoryCache.pinPreparedRanges(
      cacheKey,
      state.ranges.map((range) => range.sourceRange),
    );
  }

  DisplayRangeTaskPriority _displayRangePriority(
    DisplayRangeDirection direction,
    String reason,
  ) {
    if (direction == DisplayRangeDirection.target) {
      return DisplayRangeTaskPriority.directTarget;
    }
    if (reason.contains('boundary') || reason.contains('waiting')) {
      return DisplayRangeTaskPriority.boundaryWait;
    }
    if (direction == DisplayRangeDirection.initial) {
      return DisplayRangeTaskPriority.initialVisible;
    }
    return DisplayRangeTaskPriority.speculativeLookahead;
  }

  bool _shouldPreemptActiveRange(
    DisplayRangeDirection direction,
    String reason,
  ) {
    final active = _activeProgressiveRangeRequest;
    if (active == null) return false;
    final requestedPriority = _displayRangePriority(direction, reason);
    final activePriority = _displayRangePriority(
      active.direction,
      active.reason,
    );
    return requestedPriority.outranks(activePriority);
  }

  Future<void> _prepareProgressiveDisplayRange({
    required DisplayRangeDirection direction,
    required SourceChunkRange sourceRange,
    required String reason,
    ProgressiveDisplayRangeGenerator? generator,
    int? parentGeneration,
    int? targetOriginalIndex,
    int? targetTextOffset,
  }) {
    sourceRange = _clampToLoadedSourceRange(sourceRange);
    if (sourceRange.isEmpty) return Future.value();
    final chapterTask = _activeChapterLayoutTask;
    if (chapterTask != null) {
      _cancelChapterCardLayoutWork();
      return chapterTask.then((_) async {
        if (!mounted) return;
        await _prepareProgressiveDisplayRange(
          direction: direction,
          sourceRange: sourceRange,
          reason: reason,
          generator: generator,
          parentGeneration: parentGeneration,
          targetOriginalIndex: targetOriginalIndex,
          targetTextOffset: targetTextOffset,
        );
      });
    }
    _markForegroundReaderWork('display_range_$reason');

    final existing = _activeProgressiveRangeTask;
    if (existing != null) {
      final activeRequest = _activeProgressiveRangeRequest;
      if (activeRequest != null &&
          activeRequest.direction == direction &&
          activeRequest.sourceRange.start == sourceRange.start &&
          activeRequest.sourceRange.endExclusive == sourceRange.endExclusive &&
          activeRequest.reason == reason) {
        return existing;
      }
      if (_shouldPreemptActiveRange(direction, reason) &&
          activeRequest != null) {
        _cancelledProgressiveRangeGenerations.add(activeRequest.generationId);
        _readerDiagLog('range_cancel', {
          'book': widget.bookId,
          'generation': parentGeneration ?? _rebuildGeneration,
          'rangeGeneration': activeRequest.generationId,
          'direction': activeRequest.direction.name,
          'reason': 'preempted_by_${direction.name}',
          'replacementDirection': direction.name,
        });
        _setProgressiveRangePreparing(activeRequest.direction, false);
      } else {
        return existing;
      }
    }

    final state = _progressiveDisplayState;
    final activeToken = _displayGenerationCoordinator.activeToken;
    final rangeGenerator = generator ?? _progressiveRangeGenerator;
    if (state == null || activeToken == null || rangeGenerator == null) {
      return Future.value();
    }

    final generation = parentGeneration ?? _rebuildGeneration;
    final rangeGeneration = ++_progressiveRangeGeneration;
    final request = DisplayRangeRequest(
      direction: direction,
      sourceRange: sourceRange,
      generationId: rangeGeneration,
      reason: reason,
      targetOriginalIndex: targetOriginalIndex,
      targetTextOffset: targetTextOffset,
    );
    state.markRequest(request);
    _activeProgressiveRangeRequest = request;
    _setProgressiveRangePreparing(direction, true);
    _readerDiagLog('range_request', {
      'book': widget.bookId,
      'generation': generation,
      'rangeGeneration': rangeGeneration,
      'direction': direction.name,
      'sourceStart': sourceRange.start,
      'sourceEndExclusive': sourceRange.endExclusive,
      'reason': reason,
      'targetOriginalIndex': targetOriginalIndex,
    });

    final task = () async {
      try {
        late final DisplayRangeResult result;
        paginator.CanonicalReaderPaginationPathAccepted? canonicalAccepted;
        final outcome = await rangeGenerator(request);
        if (outcome is paginator.CanonicalReaderRequiredEarlierRestart) {
          throw StateError(outcome.message);
        }
        if (outcome is paginator.CanonicalReaderBackwardPreparationPending) {
          _readerDiagLog('canonical_backward_provisional_no_publication', {
            'book': widget.bookId,
            'generation': generation,
            'rangeGeneration': rangeGeneration,
            'direction': direction.name,
            'checkpoint': outcome.continuation.integrityDigest,
            'boundedWork': outcome.boundedWorkEntriesConsumed,
          });
          return;
        }
        if (outcome is paginator.CanonicalReaderBackwardPreparationRejected) {
          if (outcome.reason ==
                  paginator.CanonicalReaderBackwardRejectionReason.cancelled ||
              outcome.reason ==
                  paginator
                      .CanonicalReaderBackwardRejectionReason
                      .staleGeneration) {
            _readerDiagLog('range_cancel', {
              'book': widget.bookId,
              'generation': generation,
              'rangeGeneration': rangeGeneration,
              'direction': direction.name,
              'reason': outcome.reason.name,
            });
            return;
          }
          throw StateError(outcome.message);
        }
        if (outcome is paginator.CanonicalReaderPaginationPathRejected) {
          final rejection = outcome.rejection;
          if (rejection is CanonicalCancelledStaleRejected) {
            _readerDiagLog('range_cancel', {
              'book': widget.bookId,
              'generation': generation,
              'rangeGeneration': rangeGeneration,
              'direction': direction.name,
              'reason': rejection.reason.name,
            });
            return;
          }
          throw StateError(rejection.message);
        }
        if (outcome is paginator.CanonicalReaderProvisionalBudgetExhaustion &&
            outcome.publishableCards.isEmpty) {
          _readerDiagLog('canonical_provisional_no_publication', {
            'book': widget.bookId,
            'generation': generation,
            'rangeGeneration': rangeGeneration,
            'direction': direction.name,
            'checkpoint': outcome.continuation.integrityDigest,
          });
          return;
        }
        canonicalAccepted =
            outcome as paginator.CanonicalReaderPaginationPathAccepted;
        if (canonicalAccepted.publishableCards.isEmpty) {
          _readerDiagLog('canonical_provisional_no_publication', {
            'book': widget.bookId,
            'generation': generation,
            'rangeGeneration': rangeGeneration,
            'direction': direction.name,
            'checkpoint': canonicalAccepted.continuation.integrityDigest,
          });
          return;
        }
        final publicationStart = direction == DisplayRangeDirection.forward
            ? state.ranges.last.sourceRange.endExclusive
            : sourceRange.start;
        result = paginator.canonicalPathDisplayResult(
          accepted: canonicalAccepted,
          request: request,
          publicationStart: publicationStart,
        );
        if (!mounted ||
            _rebuildGeneration != generation ||
            !_displayGenerationCoordinator.canPublish(activeToken) ||
            _cancelledProgressiveRangeGenerations.contains(rangeGeneration) ||
            result.cancelled) {
          _readerDiagLog('range_cancel', {
            'book': widget.bookId,
            'generation': generation,
            'rangeGeneration': rangeGeneration,
            'direction': direction.name,
            'reason': result.cancelled
                ? 'range_generator_cancelled'
                : 'stale_progressive_range',
            'cancellationLatencyMs': result.cancellationLatencyMilliseconds,
          });
          return;
        }

        final canonicalPublisher = _progressiveCanonicalPublisher;
        if (canonicalPublisher == null) {
          throw StateError('Canonical publication boundary is unavailable.');
        }
        final committedCanonical = state.canonicalCards.isEmpty
            ? null
            : state.canonicalCards[_currentPage.clamp(
                0,
                state.canonicalCards.length - 1,
              )];
        final publication = canonicalPublisher(
          state,
          canonicalAccepted,
          request,
          committedCanonical,
        );
        if (publication is! CanonicalDisplayPublicationAccepted) {
          _readerDiagLog('canonical_publication_rejected', {
            'book': widget.bookId,
            'generation': generation,
            'rangeGeneration': rangeGeneration,
            'direction': direction.name,
            'reason': publication.kind.name,
          });
          return;
        }
        final insertedBefore = publication.insertedBefore;
        if (!_applyProgressiveDisplayState(state)) return;
        if (direction == DisplayRangeDirection.backward) {
          _readerDiagLog('range_prepend', {
            'book': widget.bookId,
            'generation': generation,
            'rangeGeneration': rangeGeneration,
            'displayChunksInserted': insertedBefore,
            'sourceStart': sourceRange.start,
            'sourceEndExclusive': sourceRange.endExclusive,
          });
        } else if (direction == DisplayRangeDirection.forward) {
          _readerDiagLog('range_append', {
            'book': widget.bookId,
            'generation': generation,
            'rangeGeneration': rangeGeneration,
            'displayChunksAdded': result.displayChunks.length,
            'sourceStart': sourceRange.start,
            'sourceEndExclusive': sourceRange.endExclusive,
          });
        }

        _readerDiagLog('range_publish', {
          'book': widget.bookId,
          'generation': generation,
          'rangeGeneration': rangeGeneration,
          'direction': direction.name,
          'displayChunks': _displayChunks.length,
          'sourceStart': sourceRange.start,
          'sourceEndExclusive': sourceRange.endExclusive,
          'complete': _displayChunksComplete,
          'rangeElapsedMs': result.elapsedMilliseconds,
          'sliceCount': result.sliceCount,
          'yieldCount': result.yieldCount,
          'longestWorkIntervalMs': result.longestWorkIntervalMilliseconds,
          'maxSliceDurationMs': result.maxSliceDurationMilliseconds,
        });
        if (mounted) setState(() {});
      } catch (error, stackTrace) {
        state.markFailure(request, error);
        if (readerShouldSurfacePreparationFailure(reason)) {
          _progressiveRangeFailure = error;
          _progressiveFailureRetry = () {
            _progressiveRangeFailure = null;
            _progressiveFailureRetry = null;
            unawaited(
              _prepareProgressiveDisplayRange(
                direction: direction,
                sourceRange: sourceRange,
                reason: 'retry_failed_range',
                targetOriginalIndex: targetOriginalIndex,
                targetTextOffset: targetTextOffset,
              ),
            );
          };
        }
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'reader progressive display',
            context: ErrorDescription('while preparing display range'),
          ),
        );
      } finally {
        final hasDifferentActiveRange =
            _activeProgressiveRangeRequest != null &&
            _activeProgressiveRangeRequest?.generationId != rangeGeneration;
        if (!hasDifferentActiveRange) {
          _setProgressiveRangePreparing(direction, false);
        }
        if (_activeProgressiveRangeRequest?.generationId == rangeGeneration) {
          _activeProgressiveRangeTask = null;
          _activeProgressiveRangeRequest = null;
        }
        _cancelledProgressiveRangeGenerations.remove(rangeGeneration);
      }
    }();
    _activeProgressiveRangeTask = task;
    return task;
  }

  SourceChunkRange _clampToLoadedSourceRange(SourceChunkRange range) {
    final sourceCount = _sourceChunks.length;
    if (sourceCount == 0) return const SourceChunkRange(0, 0);
    final start = range.start.clamp(0, sourceCount);
    final end = range.endExclusive.clamp(start, sourceCount);
    return SourceChunkRange(start, end);
  }

  // Retained for P06 canonical cache integration.
  // ignore: unused_element
  Future<DisplayRangeResult?> _loadCachedProgressiveDisplayRange({
    required String cacheKey,
    required DisplayGenerationSignature signature,
    required DisplayRangeRequest request,
  }) async {
    final memoryKey = DisplaySectionMemoryCacheKey(
      cacheKey: cacheKey,
      sourceRange: request.sourceRange,
    );
    final memory = _displaySectionMemoryCache.get(memoryKey);
    if (memory != null) {
      final admission = CanonicalDisplaySegmentAdmission.legacySafeMiss(
        cacheKind: 'section-memory',
      );
      _readerDiagLog('adjacent_section_display_memory_hit', {
        'book': widget.bookId,
        'cacheKey': cacheKey,
        'sourceStart': request.sourceRange.start,
        'sourceEndExclusive': request.sourceRange.endExclusive,
        'displayChunks': memory.displayChunks.length,
        'estimatedBytes': memory.estimatedBytes,
        'retainedBytes': _displaySectionMemoryCache.estimatedBytes,
        'admission': admission.outcome.name,
      });
      return null;
    }
    final service = await _segmentedDisplayCache();
    final segment = await service.loadRange(
      key: _segmentedDisplayCacheKey(
        cacheKey: cacheKey,
        signature: signature,
        sourceRange: request.sourceRange,
      ),
      sourceRange: request.sourceRange,
    );
    if (segment != null) {
      final admission = CanonicalDisplaySegmentAdmission.legacySafeMiss(
        cacheKind: 'section-segmented',
      );
      _readerDiagLog('adjacent_section_display_segment_rejected', {
        'book': widget.bookId,
        'cacheKey': cacheKey,
        'sourceStart': request.sourceRange.start,
        'sourceEndExclusive': request.sourceRange.endExclusive,
        'admission': admission.outcome.name,
      });
    }
    return null;
  }

  void _setProgressiveRangePreparing(
    DisplayRangeDirection direction,
    bool preparing,
  ) {
    if (!mounted) return;
    setState(() {
      switch (direction) {
        case DisplayRangeDirection.backward:
          _isPreparingBackwardRange = preparing;
          break;
        case DisplayRangeDirection.target:
          _isPreparingTargetRange = preparing;
          break;
        case DisplayRangeDirection.forward:
          _isPreparingForwardRange = preparing;
          break;
        case DisplayRangeDirection.initial:
          _isPreparingTargetRange = preparing;
          break;
      }
      if (preparing) {
        _progressiveRangeFailure = null;
        _progressiveFailureRetry = null;
      }
    });
  }

  void _maybeRequestProgressiveBoundaryRange(int displayIndex) {
    final state = _progressiveDisplayState;
    if (state == null) return;
    if (_shouldLoadLazyForwardSection(displayIndex)) {
      unawaited(_loadLazyForwardSectionAndPrepareRange());
      return;
    }
    if (_displayChunksComplete) {
      if (state.shouldRequestBackward(currentDisplayIndex: displayIndex) &&
          _lazyHasContentBeforeOutsideLoadedWindow()) {
        unawaited(_loadLazyBackwardSectionAndPrepareRange());
      }
      return;
    }
    if (state.shouldRequestForward(currentDisplayIndex: displayIndex)) {
      final range = state.nextForwardRange(_adjacentRangeSourceChunks);
      if (range != null) {
        if (_isLazyForwardSentinelRange(range)) {
          unawaited(_loadLazyForwardSectionAndPrepareRange());
        } else {
          unawaited(
            _prepareProgressiveDisplayRange(
              direction: DisplayRangeDirection.forward,
              sourceRange: range,
              reason: 'forward_boundary',
            ),
          );
        }
      }
    }
    if (state.shouldRequestBackward(currentDisplayIndex: displayIndex)) {
      final range = state.nextBackwardRange(_adjacentRangeSourceChunks);
      if (range == null && _lazyHasContentBeforeOutsideLoadedWindow()) {
        unawaited(_loadLazyBackwardSectionAndPrepareRange());
      } else if (range != null) {
        unawaited(
          _prepareProgressiveDisplayRange(
            direction: DisplayRangeDirection.backward,
            sourceRange: range,
            reason: 'backward_boundary',
          ),
        );
      }
    }
  }

  bool _shouldLoadLazyForwardSection(int displayIndex) {
    if (_lazySession == null ||
        !_hasLazyContentAfter() ||
        _isLoadingLazyForwardSection ||
        _activeProgressiveRangeTask != null ||
        _displayChunks.isEmpty) {
      return false;
    }
    return displayIndex >= _displayChunks.length - 1 - 6;
  }

  bool _lazyHasContentBeforeOutsideLoadedWindow() {
    final session = _lazySession;
    if (session == null) return false;
    final loadedSpines = _loadedLazySpineIndexes();
    if (loadedSpines.isEmpty) return widget.initialHasContentBefore;
    return session.previousReadableSpineIndex(loadedSpines.reduce(math.min)) !=
        null;
  }

  void _scheduleLazyColdRestoreAdjacentWindow() {
    final session = _lazySession;
    final location = widget.initialStableLocation;
    if (session == null ||
        location == null ||
        _lazyColdRestoreAdjacentStarted ||
        _lazyColdRestoreAdjacentComplete) {
      return;
    }
    _lazyColdRestoreAdjacentStarted = true;
    unawaited(_restoreLazyColdAdjacentWindow(location));
  }

  void _scheduleLazyInitialAdjacentWarmup() {
    if (_lazySession == null || _lazyInitialAdjacentWarmupStarted) return;
    final location = _currentStableLocation() ?? widget.initialStableLocation;
    if (location == null) return;
    _lazyInitialAdjacentWarmupStarted = true;
    _readerDiagLog('prefetch_scheduled', {
      'book': widget.bookId,
      'direction': 'both',
      'sourceSpineIndex': location.spineIndex,
      'sourceHref': location.href,
      'queuePriority': LazySectionWorkPriority.adjacentReadiness.name,
      'reason': 'initial_visible_adjacent_warmup',
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lazySession == null) return;
      _scheduleLazyAdjacentWarmup(location);
      _maybeStartReaderDiagScenario();
    });
  }

  Future<void> _restoreLazyColdAdjacentWindow(
    StableBookLocation location,
  ) async {
    const maxAttempts = 40;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted) return;
      if (_hasCompletedDisplayChunkBuild && _displayChunks.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted) return;

    final currentChunkCount = _sourceLocationsByChunkIndex.values
        .where((entry) => entry.spineIndex == location.spineIndex)
        .length;
    final localChunk = location.localChunkIndex ?? 0;
    final sectionProgress = currentChunkCount <= 1
        ? 0.0
        : (localChunk / (currentChunkCount - 1)).clamp(0.0, 1.0);
    final preferPrevious = sectionProgress <= 0.35;
    final preferNext = sectionProgress >= 0.65;
    _readerDiagLog('cold_restore_adjacent_begin', {
      'book': widget.bookId,
      'spineIndex': location.spineIndex,
      'sectionProgress': sectionProgress,
      'preferPrevious': preferPrevious,
      'preferNext': preferNext,
    });

    final tasks = <Future<void> Function()>[
      if (preferNext)
        () => _loadLazyForwardSectionAndPrepareRange()
      else
        () => _loadLazyBackwardSectionAndPrepareRange(),
      if (preferNext)
        () => _loadLazyBackwardSectionAndPrepareRange()
      else
        () => _loadLazyForwardSectionAndPrepareRange(),
    ];

    for (final task in tasks) {
      if (!mounted) return;
      await task();
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (!mounted) return;
        if (_hasCompletedDisplayChunkBuild &&
            _progressiveDisplayState != null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    _lazyColdRestoreAdjacentComplete = true;
    final loadedSpines =
        _sourceLocationsByChunkIndex.values
            .map((entry) => entry.spineIndex)
            .toSet()
            .toList()
          ..sort();
    _readerDiagLog('cold_restore_adjacent_ready', {
      'book': widget.bookId,
      'targetSpineIndex': location.spineIndex,
      'loadedSpines': loadedSpines.join(','),
      'hasPrevious': loadedSpines.contains(location.spineIndex - 1),
      'hasCurrent': loadedSpines.contains(location.spineIndex),
      'hasNext': loadedSpines.contains(location.spineIndex + 1),
    });
  }

  bool _hasLazyContentAfter() {
    final session = _lazySession;
    final maxLoaded = _lazyMaxLoadedSpineIndex;
    if (session == null || maxLoaded == null) return _lazyHasContentAfter;
    return session.nextReadableSpineIndex(maxLoaded) != null;
  }

  bool _isLazyForwardSentinelRange(SourceChunkRange range) {
    return _lazySession != null &&
        _hasLazyContentAfter() &&
        range.start >= _sourceChunks.length;
  }

  Future<void> _loadLazyForwardSectionAndPrepareRange() async {
    await _ensureAdjacentSectionAvailable(
      DisplayRangeDirection.forward,
      reason: 'lazy_forward_boundary',
    );
  }

  Future<void> _loadLazyBackwardSectionAndPrepareRange() async {
    await _ensureAdjacentSectionAvailable(
      DisplayRangeDirection.backward,
      reason: 'lazy_backward_boundary',
    );
  }

  Future<bool> _ensureAdjacentSectionAvailable(
    DisplayRangeDirection direction, {
    required String reason,
  }) {
    _markForegroundReaderWork('adjacent_$reason');
    final existing = _activeLazyAdjacentLoads[direction];
    if (existing != null) {
      _readerDiagLog('existing_request_joined', {
        'book': widget.bookId,
        'direction': direction.name,
        'generation': _rebuildGeneration,
        'reason': reason,
      });
      return existing;
    }

    final operationId = ++_lazyAdjacentOperationSequence;
    final generation = _rebuildGeneration;
    final task = _ensureAdjacentSectionAvailableInner(
      direction,
      reason: reason,
      operationId: operationId,
      generation: generation,
    );
    _activeLazyAdjacentLoads[direction] = task;
    task.whenComplete(() {
      if (identical(_activeLazyAdjacentLoads[direction], task)) {
        _activeLazyAdjacentLoads.remove(direction);
      }
    });
    return task;
  }

  Future<bool> _ensureAdjacentSectionAvailableInner(
    DisplayRangeDirection direction, {
    required String reason,
    required int operationId,
    required int generation,
  }) async {
    final stopwatch = Stopwatch()..start();
    final session = _lazySession;
    final loadedSpines = _loadedLazySpineIndexes();
    if (session == null || loadedSpines.isEmpty) return false;

    final sourceSpine = direction == DisplayRangeDirection.forward
        ? loadedSpines.reduce(math.max)
        : loadedSpines.reduce(math.min);
    final targetSpine = direction == DisplayRangeDirection.forward
        ? session.nextReadableSpineIndex(sourceSpine)
        : session.previousReadableSpineIndex(sourceSpine);
    final actualBookBoundary = targetSpine == null;
    _readerDiagLog('boundary_navigation_requested', {
      'book': widget.bookId,
      'operationId': operationId,
      'direction': direction.name,
      'boundary_direction': direction.name,
      'actual_book_boundary': actualBookBoundary,
      'loaded_window_boundary': true,
      'sourceSpineIndex': sourceSpine,
      'targetSpineIndex': targetSpine,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
      'displayGeneration': generation,
      'reason': reason,
    });
    if (targetSpine == null) {
      if (direction == DisplayRangeDirection.forward) {
        _lazyHasContentAfter = false;
      }
      return false;
    }

    _readerDiagLog('adjacent_section_resolved', {
      'book': widget.bookId,
      'operationId': operationId,
      'direction': direction.name,
      'sourceSpineIndex': sourceSpine,
      'targetSpineIndex': targetSpine,
      'sourceHref': session.index.spine[sourceSpine].href,
      'targetHref': session.index.spine[targetSpine].href,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });

    if (loadedSpines.contains(targetSpine)) return true;
    if (direction == DisplayRangeDirection.forward &&
        _progressiveDisplayState == null) {
      return false;
    }
    if (direction == DisplayRangeDirection.forward) {
      if (_isLoadingLazyForwardSection) return false;
      _isLoadingLazyForwardSection = true;
    } else {
      if (_isLoadingLazyBackwardSection) return false;
      _isLoadingLazyBackwardSection = true;
    }

    final visibleBefore = _currentStableLocation();
    _readerDiagLog('visible_location_before_integration', {
      'book': widget.bookId,
      'operationId': operationId,
      ...?_stableLocationDiagFieldsOrNull(visibleBefore),
      'currentPage': _currentPage,
    });
    _readerDiagLog('adjacent_section_load_started', {
      'book': widget.bookId,
      'operationId': operationId,
      'direction': direction.name,
      'spineIndex': targetSpine,
      'href': session.index.spine[targetSpine].href,
      'layoutFingerprint':
          _displayGenerationCoordinator.activeToken?.signature.cacheKey,
    });

    try {
      final priority = _lazySectionPriorityForReason(reason);
      _readerDiagLog('prefetch_started', {
        'book': widget.bookId,
        'operationId': operationId,
        'direction': direction.name,
        'sourceSpineIndex': sourceSpine,
        'targetSpineIndex': targetSpine,
        'queuePriority': priority.name,
        'reason': reason,
      });
      final section = direction == DisplayRangeDirection.forward
          ? await session.loadNextReadableSectionAfter(
              sourceSpine,
              priority: priority,
            )
          : await session.loadPreviousReadableSectionBefore(
              sourceSpine,
              priority: priority,
            );
      if (!mounted || generation != _rebuildGeneration) return false;
      if (section == null) {
        if (direction == DisplayRangeDirection.forward) {
          _lazyHasContentAfter = false;
        }
        return false;
      }

      _readerDiagLog('adjacent_cache_hit_or_miss', {
        'book': widget.bookId,
        'operationId': operationId,
        'direction': direction.name,
        'targetSpineIndex': section.identity.spineIndex,
        'cacheSourceUsed': 'lazy_section_repository',
        'chunks': section.chunks.length,
      });

      if (direction == DisplayRangeDirection.forward) {
        await _integrateLazyForwardSection(
          section,
          operationId,
          generation,
          visibleBefore,
        );
      } else {
        await _integrateLazyBackwardSection(
          section,
          operationId,
          generation,
          visibleBefore,
        );
      }
      stopwatch.stop();
      _readerDiagLog('boundary_navigation_completed', {
        'book': widget.bookId,
        'operationId': operationId,
        'direction': direction.name,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'activeWindowBounds': _activeLazyWindowBoundsLabel(),
      });
      _readerDiagLog('prefetch_completed', {
        'book': widget.bookId,
        'operationId': operationId,
        'direction': direction.name,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'queuePriority': priority.name,
        'reason': reason,
      });
      return true;
    } catch (error) {
      stopwatch.stop();
      _readerDiagLog('boundary_navigation_failed', {
        'book': widget.bookId,
        'operationId': operationId,
        'direction': direction.name,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'error': error.runtimeType,
      });
      if (readerShouldSurfacePreparationFailure(reason)) {
        _progressiveRangeFailure = error;
        _progressiveFailureRetry = () {
          _progressiveRangeFailure = null;
          _progressiveFailureRetry = null;
          unawaited(_ensureAdjacentSectionAvailable(direction, reason: reason));
        };
        if (mounted) setState(() {});
      }
      return false;
    } finally {
      if (direction == DisplayRangeDirection.forward) {
        _isLoadingLazyForwardSection = false;
      } else {
        _isLoadingLazyBackwardSection = false;
      }
    }
  }

  LazySectionWorkPriority _lazySectionPriorityForReason(String reason) {
    return lazySectionPriorityForReaderReason(reason);
  }

  Future<void> _integrateLazyForwardSection(
    ParsedSection section,
    int operationId,
    int generation,
    StableBookLocation? visibleBefore,
  ) async {
    final authoritativeWindow = _lazySession?.loadedWindow(
      centerSpineIndex: visibleBefore?.spineIndex,
    );
    if (authoritativeWindow != null &&
        _sourceWindowContainsEvictedSections(authoritativeWindow)) {
      if (_tryReconcileLazySourceWindowForEviction(
        authoritativeWindow,
        visibleBefore: visibleBefore,
        reason: 'lazy_forward_source_eviction',
      )) {
        final reconciledState = _progressiveDisplayState;
        final range = reconciledState?.nextForwardRange(
          _adjacentRangeSourceChunks,
        );
        if (range != null) {
          await _prepareProgressiveDisplayRange(
            direction: DisplayRangeDirection.forward,
            sourceRange: range,
            reason: 'lazy_forward_boundary_after_eviction',
            parentGeneration: generation,
          );
        }
        return;
      }
      _replaceLazySourceWindowForEviction(
        authoritativeWindow,
        visibleBefore: visibleBefore,
        reason: 'lazy_forward_source_eviction',
      );
      return;
    }
    final state = _progressiveDisplayState;
    if (state == null) {
      _readerDiagLog('boundary_navigation_failed', {
        'book': widget.bookId,
        'operationId': operationId,
        'direction': DisplayRangeDirection.forward.name,
        'reason': 'missing_progressive_state',
      });
      return;
    }
    final sourceStart = _sourceChunks.length;
    _readerDiagLog('section_append_started', {
      'book': widget.bookId,
      'operationId': operationId,
      'targetSpineIndex': section.identity.spineIndex,
      'sourceStart': sourceStart,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
    _appendLazySectionToSourceWindow(section);
    _lazyMaxLoadedSpineIndex = math.max(
      _lazyMaxLoadedSpineIndex ?? section.identity.spineIndex,
      section.identity.spineIndex,
    );
    _lazyHasContentAfter =
        _lazySession?.nextReadableSpineIndex(section.identity.spineIndex) !=
        null;
    state.sourceChunkCount = _progressiveSourceCountForLoadedWindow();
    _applyLazyExternalAvailability(state);

    final prepared = state.preparedSourceRange;
    if (prepared != null) {
      final range = SourceChunkRange(
        prepared.endExclusive,
        math.min(
          _sourceChunks.length,
          prepared.endExclusive + _adjacentRangeSourceChunks,
        ),
      );
      if (!range.isEmpty) {
        await _prepareProgressiveDisplayRange(
          direction: DisplayRangeDirection.forward,
          sourceRange: range,
          reason: 'lazy_forward_boundary',
          parentGeneration: generation,
        );
      }
    }
    _readerDiagLog('section_append_completed', {
      'book': widget.bookId,
      'operationId': operationId,
      'targetSpineIndex': section.identity.spineIndex,
      'sourceEndExclusive': _sourceChunks.length,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
      'hasLaterContent': _lazyHasContentAfter,
    });
  }

  Future<void> _integrateLazyBackwardSection(
    ParsedSection section,
    int operationId,
    int generation,
    StableBookLocation? visibleBefore,
  ) async {
    _readerDiagLog('section_prepend_started', {
      'book': widget.bookId,
      'operationId': operationId,
      'targetSpineIndex': section.identity.spineIndex,
      'prependSourceChunks': section.chunks.length,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
    final authoritativeWindow = _lazySession?.loadedWindow(
      centerSpineIndex: visibleBefore?.spineIndex,
    );
    if (authoritativeWindow != null &&
        _sourceWindowContainsEvictedSections(authoritativeWindow)) {
      if (_tryReconcileLazySourceWindowForEviction(
        authoritativeWindow,
        visibleBefore: visibleBefore,
        reason: 'lazy_backward_source_eviction',
      )) {
        final reconciledState = _progressiveDisplayState;
        final range = reconciledState?.nextBackwardRange(
          _adjacentRangeSourceChunks,
        );
        if (range != null) {
          await _prepareProgressiveDisplayRange(
            direction: DisplayRangeDirection.backward,
            sourceRange: range,
            reason: 'lazy_backward_boundary_after_eviction',
            parentGeneration: generation,
          );
        }
        return;
      }
      _replaceLazySourceWindowForEviction(
        authoritativeWindow,
        visibleBefore: visibleBefore,
        reason: 'lazy_backward_source_eviction',
      );
      return;
    }
    final activeRange = _activeProgressiveRangeTask;
    if (activeRange != null) {
      await activeRange;
      if (!mounted || generation != _rebuildGeneration) return;
    }
    final state = _progressiveDisplayState;
    final canIncrementallyPrepend =
        state != null &&
        state.ranges.isNotEmpty &&
        _activeProgressiveRangeTask == null &&
        !state.hasCanonicalCacheWriteAuthority;
    if (canIncrementallyPrepend) {
      final insertedCount = section.chunks.length;
      _prependLazySectionToSourceWindow(section);
      state.shiftSourceIndexes(insertedCount);
      state.sourceChunkCount = _progressiveSourceCountForLoadedWindow();
      _applyLazyExternalAvailability(state);
      if (!_applyProgressiveDisplayState(state)) return;
      final range = state.nextBackwardRange(_adjacentRangeSourceChunks);
      if (range != null) {
        await _prepareProgressiveDisplayRange(
          direction: DisplayRangeDirection.backward,
          sourceRange: range,
          reason: 'lazy_backward_boundary_incremental',
          parentGeneration: generation,
        );
      }
      _readerDiagLog('section_prepend_completed', {
        'book': widget.bookId,
        'operationId': operationId,
        'targetSpineIndex': section.identity.spineIndex,
        'displayGenerationBefore': generation,
        'displayGenerationAfter': _rebuildGeneration,
        'mode': 'incremental',
        'insertedSourceChunks': insertedCount,
        'activeWindowBounds': _activeLazyWindowBoundsLabel(),
      });
      if (mounted) setState(() {});
      return;
    }

    _readerDiagLog('section_prepend_incremental_unavailable', {
      'book': widget.bookId,
      'operationId': operationId,
      'targetSpineIndex': section.identity.spineIndex,
      'hasProgressiveState': state != null,
      'rangeStart': state?.ranges.isEmpty == false
          ? state!.ranges.first.sourceRange.start
          : null,
      'hasActiveProgressiveRange': _activeProgressiveRangeTask != null,
    });
    _prependLazySectionToSourceWindow(section);
    final preservedIndex = visibleBefore == null
        ? section.chunks.length
        : _sourceIndexForStableLocation(visibleBefore);

    _displayGenerationCoordinator.cancelActive(
      'lazy_backward_window_prepended',
    );
    _rebuildGeneration++;
    _progressiveRangeGeneration++;
    _progressiveDisplayState?.cancelActiveRequests();
    _progressiveDisplayState = null;
    _lastScreenSize = null;
    _lastSafeArea = null;
    _lastTextScaler = null;
    _hasCompletedDisplayChunkBuild = false;
    _displayChunksComplete = false;
    if (preservedIndex != null) {
      _targetOriginalIndex = preservedIndex.clamp(
        0,
        math.max(0, _sourceChunks.length - 1),
      );
    }
    _preferSourceIndexOnNextRestore = true;
    _pendingExactStableRestore = visibleBefore;
    _readerDiagLog('section_prepend_completed', {
      'book': widget.bookId,
      'operationId': operationId,
      'targetSpineIndex': section.identity.spineIndex,
      'displayGenerationBefore': generation,
      'displayGenerationAfter': _rebuildGeneration,
      'preservedSourceIndex': preservedIndex,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
    _readerDiagLog('visible_location_after_integration', {
      'book': widget.bookId,
      'operationId': operationId,
      ...?_stableLocationDiagFieldsOrNull(visibleBefore),
      'targetOriginalIndex': _targetOriginalIndex,
    });
    if (mounted) setState(() {});
  }

  int? _lastDisplayIndexForSpine(int spineIndex) {
    int? target;
    for (var i = 0; i < _displayToOriginal.length; i++) {
      final originals = _displayToOriginal[i];
      if (originals.any(
        (original) =>
            _sourceLocationsByChunkIndex[original]?.spineIndex == spineIndex,
      )) {
        target = i;
      }
    }
    return target;
  }

  int? _firstDisplayIndexForSpine(int spineIndex) {
    for (var i = 0; i < _displayToOriginal.length; i++) {
      final originals = _displayToOriginal[i];
      if (originals.any(
        (original) =>
            _sourceLocationsByChunkIndex[original]?.spineIndex == spineIndex,
      )) {
        return i;
      }
    }
    return null;
  }

  Set<int> _loadedLazySpineIndexes() {
    return _sourceLocationsByChunkIndex.values
        .map((location) => location.spineIndex)
        .toSet();
  }

  bool _sourceWindowContainsEvictedSections(
    LazyLoadedContentWindow authoritativeWindow,
  ) {
    final currentSections = _sourceIdentitiesByChunkIndex.values
        .map((identity) => identity.section.stableKey)
        .toSet();
    final authoritativeSections = authoritativeWindow
        .sourceIdentitiesByChunkIndex
        .values
        .map((identity) => identity.section.stableKey)
        .toSet();
    return currentSections.difference(authoritativeSections).isNotEmpty;
  }

  bool _tryReconcileLazySourceWindowForEviction(
    LazyLoadedContentWindow window, {
    required StableBookLocation? visibleBefore,
    required String reason,
  }) {
    final state = _progressiveDisplayState;
    if (visibleBefore == null ||
        state == null ||
        state.ranges.isEmpty ||
        _activeProgressiveRangeTask != null ||
        _progressiveRangeGenerator == null ||
        _displayChunks.isEmpty) {
      return false;
    }
    final rejection = state.rejectNonCanonicalCachePublication(
      cacheKind: 'eviction-remapped display',
    );
    _readerDiagLog('lazy_window_reconciliation_rejected', {
      'book': widget.bookId,
      'requestedReason': reason,
      'candidateSourceCount': window.sourceIdentitiesByChunkIndex.length,
      'reason': rejection.kind.name,
      'fallback': 'canonical_source_regeneration',
    });
    return false;
  }

  void _replaceLazySourceWindowForEviction(
    LazyLoadedContentWindow window, {
    required StableBookLocation? visibleBefore,
    required String reason,
  }) {
    _replaceLazySourceWindow(window);
    final preservedIndex = visibleBefore == null
        ? null
        : _sourceIndexForStableLocation(visibleBefore);
    _displayGenerationCoordinator.cancelActive(reason);
    _rebuildGeneration++;
    _progressiveRangeGeneration++;
    _progressiveDisplayState?.cancelActiveRequests();
    _progressiveDisplayState = null;
    _isPreparingTargetRange = true;
    _lastScreenSize = null;
    _lastSafeArea = null;
    _lastTextScaler = null;
    _hasCompletedDisplayChunkBuild = false;
    _displayChunksComplete = false;
    if (preservedIndex != null) {
      _targetOriginalIndex = preservedIndex.clamp(
        0,
        math.max(0, _sourceChunks.length - 1),
      );
    }
    _preferSourceIndexOnNextRestore = true;
    _pendingExactStableRestore = visibleBefore;
    if (mounted) setState(() {});
  }

  String _activeLazyWindowBoundsLabel() {
    final loaded = _loadedLazySpineIndexes();
    if (loaded.isEmpty) return 'empty';
    return '${loaded.reduce(math.min)}..${loaded.reduce(math.max)}';
  }

  Map<String, Object?>? _stableLocationDiagFieldsOrNull(
    StableBookLocation? location,
  ) {
    if (location == null) return null;
    return _stableLocationDiagFields(location);
  }

  Map<String, Object?> _stableLocationDiagFieldsWithPrefix(
    String prefix,
    StableBookLocation location,
  ) {
    return {
      '${prefix}SpineIndex': location.spineIndex,
      '${prefix}Href': location.href,
      '${prefix}AnchorId': location.anchorId,
      '${prefix}LocalChunkIndex': location.localChunkIndex,
      '${prefix}TextOffset': location.textOffset,
    };
  }

  StableBookLocation? _authoritativeVisibleAnchor() {
    return _visiblePositionCoordinator.authoritativeTarget ??
        _checkpointCoordinator?.current?.stableLocation ??
        _currentStableLocation();
  }

  int? _displayIndexForStableAnchor(StableBookLocation location) {
    return readerDisplayIndexForStableLocation(
      location: location,
      displayChunks: _displayChunks,
      locationsByChunkIndex: _publishedSourceLocationsByChunkIndex,
      sourceIdentitiesByChunkIndex: _publishedSourceIdentitiesByChunkIndex,
    );
  }

  void _logVisiblePositionMutation({
    required String reason,
    required ReaderVisibleMutationClassification classification,
    required bool accepted,
    required String decisionReason,
    StableBookLocation? oldLocation,
    StableBookLocation? newLocation,
    int? oldLocalIndex,
    int? newLocalIndex,
    ReaderVisibleNavigationIntent<StableBookLocation>? intent,
  }) {
    final checkpoint = _checkpointCoordinator?.current;
    _readerDiagLog('visible_position_mutation', {
      'book': widget.bookId,
      'readerSessionId': _visiblePositionCoordinator.sessionId,
      'readerGeneration': _visiblePositionCoordinator.readerGeneration,
      'navigationIntentId': intent?.id,
      'navigationIntentPhase': intent?.phase.name,
      'intentExpectedWindowGeneration': intent?.expectedWindowGeneration,
      'intentExpectedPublicationGeneration':
          intent?.expectedPublicationGeneration,
      'gestureSuppressed': _visiblePositionCoordinator.isGestureSuppressed,
      'reason': reason,
      'classification': classification.name,
      ...?_stableLocationDiagFieldsOrNull(
        oldLocation,
      )?.map((key, value) => MapEntry('old_$key', value)),
      ...?_stableLocationDiagFieldsOrNull(
        newLocation,
      )?.map((key, value) => MapEntry('new_$key', value)),
      'oldSourceOffset': oldLocation?.textOffset,
      'newSourceOffset': newLocation?.textOffset,
      'oldLocalDisplayIndex': oldLocalIndex,
      'newLocalDisplayIndex': newLocalIndex,
      'oldGlobalDisplayIndex': oldLocation?.localDisplayIndex,
      'newGlobalDisplayIndex': newLocation?.localDisplayIndex,
      'windowGeneration': _rebuildGeneration,
      'windowBounds': _activeLazyWindowBoundsLabel(),
      'paginationGeneration': _progressiveRangeGeneration,
      'checkpointRevision': checkpoint?.revision,
      'layoutSignatureMatch':
          checkpoint?.layoutFingerprint == _activeReaderLayoutFingerprint,
      'controllerAttached': _pageController?.hasClients == true,
      'restorationState': _visiblePositionCoordinator.restorationState.name,
      'accepted': accepted,
      'decisionReason': decisionReason,
    });
  }

  ReaderVisibleNavigationIntent<StableBookLocation>?
  _beginInitialVisibleRestore(StableBookLocation target, String reason) {
    return _visiblePositionCoordinator.beginInitialRestore(
      target: target,
      reason: reason,
      expectedWindowGeneration: _rebuildGeneration,
      expectedPublicationGeneration: _progressiveRangeGeneration,
    );
  }

  ReaderVisibleNavigationIntent<StableBookLocation>?
  _beginExplicitVisibleNavigation(StableBookLocation target, String reason) {
    return _visiblePositionCoordinator.beginExplicit(
      target: target,
      reason: reason,
      expectedWindowGeneration: _rebuildGeneration,
      expectedPublicationGeneration: _progressiveRangeGeneration,
    );
  }

  void _appendLazySectionToSourceWindow(ParsedSection section) {
    _cachedFlatChapters = null;
    final sourceStart = _sourceChunks.length;
    for (final entry in section.anchorMap.entries) {
      _sourceAnchorMap[entry.key] = sourceStart + entry.value;
    }
    var nextIndex = sourceStart;
    for (final chunk in section.chunks) {
      _sourceChunks.add(chunk.copyWith(index: nextIndex));
      _sourceIdentitiesByChunkIndex[nextIndex] = LazySourceChunkIdentity(
        section: section.identity,
        localChunkIndex: chunk.index,
      );
      _sourceLocationsByChunkIndex[nextIndex] =
          _lazySession?.locationForSectionChunk(section, chunk.index) ??
          StableBookLocation(
            bookId: section.identity.bookId,
            spineIndex: section.identity.spineIndex,
            href: section.identity.href,
            sourceChecksum: section.identity.sourceChecksum,
            publicationFingerprint: section.identity.publicationFingerprint,
            normalizedHref: section.identity.normalizedHref,
            localChunkIndex: chunk.index,
            sourceParserVersion: section.parserVersion,
            contextText: chunk.text,
          );
      final text = authoritativeBookChunkText(chunk);
      if (text != null) {
        for (final word
            in text
                .toLowerCase()
                .split(RegExp(r'[^a-z0-9]+'))
                .where((entry) => entry.isNotEmpty)) {
          _sourceSearchIndex.putIfAbsent(word, () => <int>[]).add(nextIndex);
        }
      }
      nextIndex++;
    }
  }

  void _prependLazySectionToSourceWindow(ParsedSection section) {
    _cachedFlatChapters = null;
    final insertedCount = section.chunks.length;
    final oldChunks = List<BookChunk>.from(_sourceChunks);
    final oldAnchors = Map<String, int>.from(_sourceAnchorMap);
    final oldLocations = Map<int, StableBookLocation>.from(
      _sourceLocationsByChunkIndex,
    );
    final oldSourceIdentities = Map<int, LazySourceChunkIdentity>.from(
      _sourceIdentitiesByChunkIndex,
    );
    final oldSearch = Map<String, List<int>>.from(_sourceSearchIndex);

    _sourceChunks = <BookChunk>[];
    _sourceAnchorMap = <String, int>{};
    _sourceLocationsByChunkIndex = <int, StableBookLocation>{};
    _sourceIdentitiesByChunkIndex = <int, LazySourceChunkIdentity>{};
    _sourceSearchIndex = <String, List<int>>{};

    for (final entry in section.anchorMap.entries) {
      _sourceAnchorMap[entry.key] = entry.value;
    }
    for (final chunk in section.chunks) {
      final nextIndex = _sourceChunks.length;
      _sourceChunks.add(chunk.copyWith(index: nextIndex));
      _sourceIdentitiesByChunkIndex[nextIndex] = LazySourceChunkIdentity(
        section: section.identity,
        localChunkIndex: chunk.index,
      );
      _sourceLocationsByChunkIndex[nextIndex] =
          _lazySession?.locationForSectionChunk(section, chunk.index) ??
          StableBookLocation(
            bookId: section.identity.bookId,
            spineIndex: section.identity.spineIndex,
            href: section.identity.href,
            sourceChecksum: section.identity.sourceChecksum,
            publicationFingerprint: section.identity.publicationFingerprint,
            normalizedHref: section.identity.normalizedHref,
            localChunkIndex: chunk.index,
            sourceParserVersion: section.parserVersion,
            contextText: chunk.text,
          );
      _indexChunkTextForSearch(authoritativeBookChunkText(chunk), nextIndex);
    }

    for (final entry in _sourceAnchorMap.entries.toList()) {
      _sourceAnchorMap[entry.key] = entry.value;
    }
    for (final entry in oldAnchors.entries) {
      _sourceAnchorMap[entry.key] = entry.value + insertedCount;
    }
    for (final entry in oldLocations.entries) {
      _sourceLocationsByChunkIndex[entry.key + insertedCount] = entry.value;
    }
    for (final entry in oldSourceIdentities.entries) {
      _sourceIdentitiesByChunkIndex[entry.key + insertedCount] = entry.value;
    }
    for (final chunk in oldChunks) {
      _sourceChunks.add(chunk.copyWith(index: chunk.index + insertedCount));
    }
    for (final entry in oldSearch.entries) {
      _sourceSearchIndex
          .putIfAbsent(entry.key, () => <int>[])
          .addAll(entry.value.map((index) => index + insertedCount));
    }
    final loadedSpines = _sourceLocationsByChunkIndex.values
        .map((location) => location.spineIndex)
        .toSet();
    if (loadedSpines.isNotEmpty) {
      _lazyMaxLoadedSpineIndex = loadedSpines.reduce(math.max);
    }
  }

  void _indexChunkTextForSearch(String? text, int chunkIndex) {
    if (text == null) return;
    for (final word
        in text
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'))
            .where((entry) => entry.isNotEmpty)) {
      _sourceSearchIndex.putIfAbsent(word, () => <int>[]).add(chunkIndex);
    }
  }

  int _progressiveSourceCountForLoadedWindow() {
    final session = _lazySession;
    final maxLoaded = _lazyMaxLoadedSpineIndex;
    if (session != null && maxLoaded != null) {
      return _sourceChunks.length +
          (session.nextReadableSpineIndex(maxLoaded) != null ? 1 : 0);
    }
    return _sourceChunks.length + (_lazyHasContentAfter ? 1 : 0);
  }

  void _applyLazyExternalAvailability(ProgressiveDisplayState state) {
    final session = _lazySession;
    final loadedSpines = _sourceLocationsByChunkIndex.values
        .map((location) => location.spineIndex)
        .toSet();
    if (session == null || loadedSpines.isEmpty) {
      state.externalUnavailableBefore = widget.initialHasContentBefore;
      state.externalUnavailableAfter = _lazyHasContentAfter;
      return;
    }
    final minLoaded = loadedSpines.reduce(math.min);
    final maxLoaded = loadedSpines.reduce(math.max);
    state.externalUnavailableBefore =
        session.previousReadableSpineIndex(minLoaded) != null;
    state.externalUnavailableAfter =
        session.nextReadableSpineIndex(maxLoaded) != null;
  }

  bool _isCurrentDerivedRange(DerivedSourceRange range) {
    if (range.location.bookId != widget.bookId) return false;
    final publication = _lazySession?.index.publicationFingerprint;
    if (range.location.publicationFingerprint != null &&
        publication != null &&
        range.location.publicationFingerprint != publication) {
      return false;
    }
    if (range.indexGeneration <= 0) return true;
    final manifest = _derivedIndexSession?.snapshot?.manifest;
    return manifest != null &&
        manifest.generation == range.indexGeneration &&
        manifest.publicationFingerprint ==
            range.location.publicationFingerprint;
  }

  void _clearTransientSearchEmphasis() {
    _transientSearchGeneration++;
    _transientSearchTimer?.cancel();
    _transientSearchTimer = null;
    if (_transientSearchRange == null) return;
    if (mounted) {
      setState(() => _transientSearchRange = null);
    } else {
      _transientSearchRange = null;
    }
  }

  void _showTransientSearchEmphasis(DerivedSourceRange range) {
    if (!_isCurrentDerivedRange(range)) return;
    final generation = ++_transientSearchGeneration;
    _transientSearchTimer?.cancel();
    if (mounted) setState(() => _transientSearchRange = range);
    _transientSearchTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || generation != _transientSearchGeneration) return;
      setState(() => _transientSearchRange = null);
    });
  }

  Future<StableBookLocation?> _navigateToStableLocation(
    StableBookLocation location, {
    String navigationSource = 'stable_location',
    DerivedSourceRange? transientSearchRange,
  }) async {
    _clearTransientSearchEmphasis();
    if (transientSearchRange != null &&
        !_isCurrentDerivedRange(transientSearchRange)) {
      return null;
    }
    _cancelChapterCardLayoutWork();
    final visibleIntent = _beginExplicitVisibleNavigation(
      location,
      navigationSource,
    );
    if (visibleIntent == null) {
      _logVisiblePositionMutation(
        reason: navigationSource,
        classification: ReaderVisibleMutationClassification.programmatic,
        accepted: false,
        decisionReason: 'explicit_intent_unavailable',
        oldLocation: _visiblePositionCoordinator.committedLocation,
        newLocation: location,
        oldLocalIndex: _currentPage,
      );
      return null;
    }
    _controllerIntent = visibleIntent;
    final navigationToken = _navigationPublicationCoordinator.begin(location);
    final session = _lazySession;
    var resolvedLocation = location;
    LazyNavigationPreparation? preparedNavigation;
    var navigationSettled = false;
    try {
      if (session != null) {
        preparedNavigation = await session.prepareNavigation(
          location,
          canCommit: () =>
              mounted &&
              _navigationPublicationCoordinator.isLatest(navigationToken),
        );
        if (preparedNavigation.superseded ||
            !_navigationPublicationCoordinator.isLatest(navigationToken) ||
            !_visiblePositionCoordinator.isCurrent(visibleIntent)) {
          return null;
        }
        final resolution = preparedNavigation.resolution;
        final resolved = resolution.location;
        if (resolved == null) {
          _navigationPublicationCoordinator.fail(navigationToken);
          _readerDiagLog('stable_location_unresolved', {
            ..._stableLocationDiagFields(location),
            'reason': resolution.reason,
          });
          return null;
        }
        resolvedLocation = resolved;
      }
      if (!_visiblePositionCoordinator.resolveIntentTarget(
        intent: visibleIntent,
        target: resolvedLocation,
        expectedWindowGeneration: _rebuildGeneration,
        expectedPublicationGeneration: _progressiveRangeGeneration,
      )) {
        return null;
      }

      final existingIndex = _sourceIndexForStableLocation(resolvedLocation);
      if (existingIndex != null) {
        await _navigateToSourceLocation(
          originalChunkIndex: existingIndex,
          originalStartOffset: resolvedLocation.textOffset,
          sourceText: resolvedLocation.contextText,
          navigationSource: navigationSource,
          targetLocation: resolvedLocation,
          navigationIntent: visibleIntent,
        );
        if (_navigationPublicationCoordinator.isLatest(navigationToken) &&
            (_visiblePositionCoordinator.isCurrent(visibleIntent) ||
                visibleIntent.phase == ReaderVisibleNavigationPhase.settled)) {
          final displayIndex = _displayIndexForSourceLocation(
            originalChunkIndex: existingIndex,
            originalStartOffset: resolvedLocation.textOffset,
            sourceText: resolvedLocation.contextText,
          );
          if (displayIndex != null) {
            if (_visiblePositionCoordinator.isCurrent(visibleIntent)) {
              _visiblePositionCoordinator.markWindowPublished(
                intent: visibleIntent,
                resolvedLocation: resolvedLocation,
                windowGeneration: _rebuildGeneration,
                publicationGeneration: _progressiveRangeGeneration,
              );
              _onPageSettled(displayIndex);
            }
            if (await _waitForSettledPageAttachment(displayIndex)) {
              _onPageSettled(displayIndex);
              await _flushPendingReadingPosition();
            }
            navigationSettled =
                visibleIntent.phase == ReaderVisibleNavigationPhase.settled &&
                _visiblePositionCoordinator.committedLocation ==
                    resolvedLocation;
            if (transientSearchRange != null) {
              _showTransientSearchEmphasis(transientSearchRange);
            }
          }
          _navigationPublicationCoordinator.markReadablePublished(
            navigationToken,
          );
        }
        return navigationSettled ? resolvedLocation : null;
      }

      if (session == null) {
        final fallback = resolvedLocation.legacyGlobalChunkIndex;
        if (fallback != null) {
          await _navigateToSourceLocation(
            originalChunkIndex: fallback,
            originalStartOffset: resolvedLocation.textOffset,
            sourceText: resolvedLocation.contextText,
            navigationSource: navigationSource,
            targetLocation: resolvedLocation,
            navigationIntent: visibleIntent,
          );
          final displayIndex = _displayIndexForSourceLocation(
            originalChunkIndex: fallback,
            originalStartOffset: resolvedLocation.textOffset,
            sourceText: resolvedLocation.contextText,
          );
          if (displayIndex != null &&
              await _waitForSettledPageAttachment(displayIndex)) {
            _onPageSettled(displayIndex);
            navigationSettled =
                visibleIntent.phase == ReaderVisibleNavigationPhase.settled;
          }
        }
        _navigationPublicationCoordinator.fail(navigationToken);
        return navigationSettled ? resolvedLocation : null;
      }

      _readerDiagLog('lazy_reader_section_requested', {
        'book': widget.bookId,
        'direction': 'target',
        'spineIndex': location.spineIndex,
        'href': location.href,
        'navigationGeneration': navigationToken.id,
      });
      if (transientSearchRange == null) {
        _commitCurrentPosition();
      }
      setState(() {
        _isPreparingTargetRange = true;
        _progressiveRangeFailure = null;
        _progressiveFailureRetry = null;
      });
      final window = preparedNavigation?.window;
      if (!mounted ||
          window == null ||
          !_navigationPublicationCoordinator.isLatest(navigationToken)) {
        return null;
      }
      _replaceLazySourceWindow(window);
      _pendingDisplayNavigationToken = navigationToken;
      final targetIndex = _sourceIndexForStableLocation(resolvedLocation);
      _targetOriginalIndex = (targetIndex ?? 0).clamp(
        0,
        math.max(0, _sourceChunks.length - 1),
      );
      _preferSourceIndexOnNextRestore = true;
      _pendingExactStableRestore = resolvedLocation;
      _readerDiagLog('stable_location_pending_restore_set', {
        ..._stableLocationDiagFields(resolvedLocation),
        'targetOriginalIndex': _targetOriginalIndex,
        'loadedChunks': _sourceChunks.length,
        'navigationGeneration': navigationToken.id,
      });
      _targetProgressRatio = _sourceChunks.isEmpty
          ? 0
          : _targetOriginalIndex / _sourceChunks.length;
      _displayGenerationCoordinator.cancelActive('lazy_target_window_replaced');
      _rebuildGeneration++;
      _progressiveRangeGeneration++;
      if (!_visiblePositionCoordinator.resolveIntentTarget(
        intent: visibleIntent,
        target: resolvedLocation,
        expectedWindowGeneration: _rebuildGeneration,
        expectedPublicationGeneration: _progressiveRangeGeneration,
      )) {
        return null;
      }
      _progressiveDisplayState?.cancelActiveRequests();
      _progressiveDisplayState = null;
      _lastScreenSize = null;
      _lastSafeArea = null;
      _lastTextScaler = null;
      _hasCompletedDisplayChunkBuild = false;
      _displayChunksComplete = false;
      _readerDiagLog('lazy_reader_target_resolved', {
        'book': widget.bookId,
        'spineIndex': resolvedLocation.spineIndex,
        'href': resolvedLocation.href,
        'targetOriginalIndex': _targetOriginalIndex,
        'loadedChunks': _sourceChunks.length,
        'navigationGeneration': navigationToken.id,
      });
      setState(() {});
      navigationSettled = await _completeStableLocationNavigation(
        location: resolvedLocation,
        generation: _rebuildGeneration,
        navigationToken: navigationToken,
        visibleIntent: visibleIntent,
        navigationSource: navigationSource,
        transientSearchRange: transientSearchRange,
      );
      return navigationSettled ? resolvedLocation : null;
    } catch (error) {
      if (mounted &&
          _navigationPublicationCoordinator.isLatest(navigationToken)) {
        _navigationPublicationCoordinator.fail(navigationToken);
        if (identical(_pendingDisplayNavigationToken, navigationToken)) {
          _pendingDisplayNavigationToken = null;
        }
        setState(() {
          _isPreparingTargetRange = false;
          _progressiveRangeFailure = error;
          _progressiveFailureRetry = () {
            _progressiveRangeFailure = null;
            _progressiveFailureRetry = null;
            unawaited(
              _navigateToStableLocation(
                location,
                navigationSource: navigationSource,
              ),
            );
          };
        });
      }
      return null;
    } finally {
      if (!navigationSettled &&
          _visiblePositionCoordinator.isCurrent(visibleIntent)) {
        _visiblePositionCoordinator.cancelActiveIntent(failed: true);
      }
      if (identical(_controllerIntent, visibleIntent) &&
          visibleIntent.phase != ReaderVisibleNavigationPhase.controllerMoved) {
        _controllerIntent = null;
      }
      if (_navigationPublicationCoordinator.isLatest(navigationToken)) {
        if (!navigationSettled) {
          _navigationPublicationCoordinator.fail(navigationToken);
        }
        if (identical(_pendingDisplayNavigationToken, navigationToken)) {
          _pendingDisplayNavigationToken = null;
        }
        if (mounted && _isPreparingTargetRange) {
          setState(() => _isPreparingTargetRange = false);
        }
      }
    }
  }

  Future<bool> _completeStableLocationNavigation({
    required StableBookLocation location,
    required int generation,
    required ReaderNavigationToken<StableBookLocation> navigationToken,
    required ReaderVisibleNavigationIntent<StableBookLocation> visibleIntent,
    required String navigationSource,
    DerivedSourceRange? transientSearchRange,
  }) async {
    const maxAttempts = 30;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (visibleIntent.phase == ReaderVisibleNavigationPhase.settled &&
          _visiblePositionCoordinator.committedLocation == location) {
        return true;
      }
      if (!mounted ||
          generation != _rebuildGeneration ||
          !_navigationPublicationCoordinator.isLatest(navigationToken) ||
          !_visiblePositionCoordinator.isCurrent(visibleIntent)) {
        return false;
      }
      if (_displayChunks.isNotEmpty && _hasCompletedDisplayChunkBuild) {
        final sourceIndex = _sourceIndexForStableLocation(location);
        final displayIndex = sourceIndex == null
            ? null
            : _displayIndexForSourceLocation(
                originalChunkIndex: sourceIndex,
                originalStartOffset: location.textOffset,
                sourceText: location.contextText,
              );
        if (displayIndex != null) {
          _pendingExactStableRestore = null;
          _preferSourceIndexOnNextRestore = false;
          _readerDiagLog('stable_location_navigation_complete', {
            ..._stableLocationDiagFields(location),
            'sourceIndex': sourceIndex,
            'displayIndex': displayIndex,
            'attempt': attempt,
          });
          _clearPreviewState(visibleDisplayIndex: displayIndex);
          _visiblePositionCoordinator.markWindowPublished(
            intent: visibleIntent,
            resolvedLocation: location,
            windowGeneration: _rebuildGeneration,
            publicationGeneration: _progressiveRangeGeneration,
          );
          final alreadyVisible = _currentPage == displayIndex;
          _nextCheckpointNavigationSource = navigationSource;
          _jumpReaderToPage(
            displayIndex,
            reason: navigationSource,
            targetLocation: location,
            navigationIntent: visibleIntent,
          );
          if (alreadyVisible) {
            _onPageSettled(displayIndex);
          }
          if (await _waitForSettledPageAttachment(displayIndex)) {
            _onPageSettled(displayIndex);
            await _flushPendingReadingPosition();
          }
          if (transientSearchRange != null) {
            _showTransientSearchEmphasis(transientSearchRange);
          }
          _scheduleLazyAdjacentWarmup(location);
          return visibleIntent.phase == ReaderVisibleNavigationPhase.settled &&
              _visiblePositionCoordinator.committedLocation == location;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _readerDiagLog('stable_location_navigation_timeout', {
      ..._stableLocationDiagFields(location),
      'generation': generation,
      'displayChunks': _displayChunks.length,
      'hasCompletedDisplayChunkBuild': _hasCompletedDisplayChunkBuild,
      'navigationGeneration': navigationToken.id,
    });
    return false;
  }

  Future<void> _navigateAndMigrateLegacyBookmark(Bookmark bookmark) async {
    final session = _lazySession;
    final metadata = _metadataService.getMetadata(widget.bookId);
    final total = metadata?.totalChunks ?? 0;
    if (session == null || total <= 1) {
      await _navigateToSourceLocation(
        originalChunkIndex: bookmark.chunkIndex,
        originalStartOffset: bookmark.originalStartOffset,
        sourceText: bookmark.previewText,
        navigationSource: 'bookmark',
      );
      return;
    }
    final progression = (bookmark.chunkIndex / (total - 1)).clamp(0.0, 1.0);
    final candidate = session
        .locationForWeightedProgression(
          progression,
          legacyGlobalChunkIndex: bookmark.chunkIndex,
        )
        .copyWith(
          textOffset: bookmark.originalStartOffset,
          contextText: bookmark.previewText,
        );
    final resolution = await session.resolveStableLocation(candidate);
    final resolved = resolution.location;
    if (resolved == null) return;
    await _navigateToStableLocation(resolved, navigationSource: 'bookmark');
    final hadQuote = bookmark.previewText?.trim().isNotEmpty == true;
    if (hadQuote &&
        resolution.confidence == StableLocationConfidence.progression) {
      return;
    }
    final updated = await _bookmarkService.migrateStableLocation(
      bookmark,
      resolved,
    );
    if (mounted) setState(() => _bookmarks = updated);
  }

  Future<void> _navigateAndMigrateLegacyAnnotation({
    required int originalChunkIndex,
    int? originalStartOffset,
    String? sourceText,
  }) async {
    final session = _lazySession;
    final total = _metadataService.getMetadata(widget.bookId)?.totalChunks ?? 0;
    if (session == null || total <= 1) {
      await _navigateToSourceLocation(
        originalChunkIndex: originalChunkIndex,
        originalStartOffset: originalStartOffset,
        sourceText: sourceText,
        navigationSource: 'annotation',
      );
      return;
    }
    final candidate = session
        .locationForWeightedProgression(
          (originalChunkIndex / (total - 1)).clamp(0.0, 1.0),
          legacyGlobalChunkIndex: originalChunkIndex,
        )
        .copyWith(
          textOffset: originalStartOffset ?? 0,
          contextText: sourceText,
        );
    final resolution = await session.resolveStableLocation(candidate);
    final resolved = resolution.location;
    if (resolved == null) return;
    await _navigateToStableLocation(resolved, navigationSource: 'annotation');
    if (sourceText?.trim().isNotEmpty == true &&
        resolution.confidence == StableLocationConfidence.progression) {
      return;
    }
    for (final highlight in List<Highlight>.from(_highlights)) {
      if (highlight.stableLocation == null &&
          highlight.originalChunkIndex == originalChunkIndex &&
          (originalStartOffset == null ||
              highlight.startOffset == originalStartOffset)) {
        _highlights = await _highlightService.migrateStableLocation(
          highlight,
          resolved,
        );
      }
    }
    for (final word in _dictionaryService.words) {
      if (word.stableLocation == null &&
          word.originalChunkIndex == originalChunkIndex &&
          (originalStartOffset == null ||
              word.originalStartOffset == originalStartOffset)) {
        await _dictionaryService.migrateStableLocation(word.id, resolved);
      }
    }
    if (mounted) setState(() {});
  }

  void _scheduleLazyAdjacentWarmup(StableBookLocation location) {
    if (_lazySession == null) return;
    unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted || _lazySession == null) return;
      final currentSpines = _loadedLazySpineIndexes();
      if (!currentSpines.contains(location.spineIndex)) return;
      await _ensureAdjacentSectionAvailable(
        DisplayRangeDirection.backward,
        reason: 'stable_location_adjacent_warmup',
      );
      await _waitForDisplayWindowReady();
      if (!mounted || _lazySession == null) return;
      await _ensureAdjacentSectionAvailable(
        DisplayRangeDirection.forward,
        reason: 'stable_location_adjacent_warmup',
      );
      _scheduleLazyParsedHydration();
    }());
  }

  void _scheduleLazyParsedHydration() {
    final session = _lazySession;
    if (session == null || _lazyParsedHydrationStarted) return;
    _lazyParsedHydrationStarted = true;
    unawaited(_runLazyParsedHydrationWhenQuiet(session));
  }

  Future<void> _runLazyParsedHydrationWhenQuiet(LazyBookSession session) async {
    while (mounted && identical(_lazySession, session)) {
      final remaining = _remainingHydrationQuietPeriod();
      if (remaining <= Duration.zero && !_hasForegroundReaderWork()) break;
      await Future<void>.delayed(
        remaining > Duration.zero
            ? remaining
            : const Duration(milliseconds: 120),
      );
    }
    if (!mounted || !identical(_lazySession, session)) return;
    await session.hydrateParsedSectionsFromCurrent(
      shouldPause: () {
        return !mounted ||
            !identical(_lazySession, session) ||
            _remainingHydrationQuietPeriod() > Duration.zero ||
            _hasForegroundReaderWork();
      },
    );
  }

  void _markForegroundReaderWork(String reason) {
    _lastForegroundReaderWorkMs = DateTime.now().millisecondsSinceEpoch;
    _readerDiagLog('hydration_task_preempted', {
      'book': widget.bookId,
      'reason': reason,
      'quietPeriodMs': _lazyHydrationQuietPeriod.inMilliseconds,
    });
  }

  void _pauseNonessentialReaderWork(String reason) {
    _backgroundWorkGeneration++;
    _derivedIndexSession?.cancel();
    _lazySession?.cancelBackgroundWork();
    _lazyParsedHydrationStarted = false;
    _markForegroundReaderWork(reason);
  }

  void _scheduleDerivedIndexWhenQuiet() {
    final session = _derivedIndexSession;
    if (session == null) return;
    final owner = ++_backgroundWorkGeneration;
    unawaited(() async {
      await Future<void>.delayed(_lazyHydrationQuietPeriod);
      if (!mounted ||
          owner != _backgroundWorkGeneration ||
          !_isReaderLifecycleActive ||
          _displayChunks.isEmpty ||
          _hasForegroundReaderWork()) {
        return;
      }
      session.start();
    }());
  }

  void _cancelChapterCardLayoutWork({bool clearPublished = false}) {
    final rangeGeneration = _activeChapterLayoutRangeGeneration;
    if (rangeGeneration != null) {
      _cancelledProgressiveRangeGenerations.add(rangeGeneration);
    }
    if (clearPublished) {
      _chapterCardLayoutCoordinator.clearPublished();
      _currentChapterCardLayout = null;
    } else {
      _chapterCardLayoutCoordinator.cancel();
    }
  }

  bool _hasForegroundReaderWork() {
    return _activeProgressiveRangeTask != null ||
        _isLoadingLazyForwardSection ||
        _isLoadingLazyBackwardSection ||
        _isPreparingForwardRange ||
        _isPreparingBackwardRange ||
        _isPreparingTargetRange;
  }

  Duration _remainingHydrationQuietPeriod() {
    final last = _lastForegroundReaderWorkMs;
    if (last <= 0) return Duration.zero;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    final remainingMs = _lazyHydrationQuietPeriod.inMilliseconds - elapsed;
    return remainingMs <= 0
        ? Duration.zero
        : Duration(milliseconds: remainingMs);
  }

  void _maybeStartReaderDiagScenario() {
    if (_readerDiagScenario.isEmpty || _readerDiagScenarioStarted) return;
    _readerDiagScenarioStarted = true;
    unawaited(_runReaderDiagScenario(_readerDiagScenario));
  }

  Future<void> _runReaderDiagScenario(String scenario) async {
    await _waitForReaderDiagIdle('scenario_start');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _readerDiagLog('reader_diag_sequence_begin', {
      'book': widget.bookId,
      'scenario': scenario,
      'currentPage': _currentPage,
      'currentSpineIndex': _currentStableLocation()?.spineIndex,
      'displayChunks': _displayChunks.length,
      'sourceChunks': _sourceChunks.length,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
    switch (scenario.toUpperCase()) {
      case 'A':
        await _runReaderDiagSequenceA();
        break;
      case 'B':
        await _runReaderDiagSequenceB();
        break;
      case 'C':
        await _runReaderDiagSequenceC();
        break;
      case 'D':
        await _runReaderDiagSequenceD();
        break;
      case 'E':
        await _runReaderDiagSequenceE();
        break;
      case 'CACHE_CORRUPT':
        await _runReaderDiagCacheCorruptScenario();
        break;
      case 'ALL':
        await _runReaderDiagSequenceA();
        await _runReaderDiagSequenceB();
        await _runReaderDiagSequenceC();
        await _runReaderDiagSequenceD();
        await _runReaderDiagSequenceE();
        break;
      default:
        _readerDiagLog('reader_diag_sequence_skipped', {
          'book': widget.bookId,
          'scenario': scenario,
          'reason': 'unknown_scenario',
        });
    }
    _readerDiagLog('reader_diag_sequence_end', {
      'book': widget.bookId,
      'scenario': scenario,
      'currentPage': _currentPage,
      'currentSpineIndex': _currentStableLocation()?.spineIndex,
      'displayChunks': _displayChunks.length,
      'sourceChunks': _sourceChunks.length,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
  }

  Future<void> _runReaderDiagSequenceA() async {
    await _readerDiagBoundary(direction: DisplayRangeDirection.forward);
    await _readerDiagBoundary(direction: DisplayRangeDirection.backward);
  }

  Future<void> _runReaderDiagSequenceB() async {
    await _readerDiagChapterJump('chapter_1_to_2', forward: true);
    await _readerDiagChapterJump('chapter_2_to_3', forward: true);
    await _readerDiagChapterJump('chapter_3_to_2', forward: false);
    await _readerDiagBoundary(direction: DisplayRangeDirection.backward);
  }

  Future<void> _runReaderDiagSequenceC() async {
    final session = _lazySession;
    final current = _currentStableLocation();
    if (session == null || current == null) return;
    final targetSpine = current.spineIndex + 10;
    if (targetSpine >= session.index.spine.length) {
      _readerDiagLog('reader_diag_operation_skipped', {
        'book': widget.bookId,
        'scenario': 'C',
        'reason': 'not_enough_spine_sections',
        'currentSpineIndex': current.spineIndex,
        'spineCount': session.index.spine.length,
      });
      return;
    }
    final spine = session.index.spine[targetSpine];
    final target = StableBookLocation(
      bookId: session.index.bookId,
      spineIndex: spine.index,
      href: spine.href,
      sourceChecksum: spine.sourceChecksum,
    );
    await _readerDiagTimedOperation(
      name: 'distant_jump_plus_10',
      targetSpineIndex: target.spineIndex,
      action: () async => _navigateToStableLocation(target),
      isComplete: () =>
          _currentStableLocation()?.spineIndex == target.spineIndex,
    );
    await _readerDiagBoundary(direction: DisplayRangeDirection.backward);
    await _readerDiagBoundary(direction: DisplayRangeDirection.forward);
  }

  Future<void> _runReaderDiagSequenceD() async {
    final session = _lazySession;
    final current = _currentStableLocation();
    if (session == null || current == null) return;
    final prefs = await SharedPreferences.getInstance();
    final restoreMarkerKey = 'nalori_diag_cold_restore_ready_${widget.bookId}';
    final restoreReady = prefs.getBool(restoreMarkerKey) ?? false;
    if (restoreReady) {
      await prefs.remove(restoreMarkerKey);
      _readerDiagLog('cold_restore_detected', {
        'book': widget.bookId,
        'scenario': 'D',
        'currentSpineIndex': current.spineIndex,
        'currentHref': current.href,
        'activeWindowBounds': _activeLazyWindowBoundsLabel(),
      });
      await _readerDiagBoundary(direction: DisplayRangeDirection.backward);
      return;
    }
    final targetSpineIndex = session.nextReadableSpineIndex(current.spineIndex);
    if (targetSpineIndex == null) {
      _readerDiagLog('reader_diag_operation_skipped', {
        'book': widget.bookId,
        'scenario': 'D',
        'reason': 'no_next_readable_spine_for_setup',
        'currentSpineIndex': current.spineIndex,
      });
      return;
    }
    final spine = session.index.spine[targetSpineIndex];
    final target = StableBookLocation(
      bookId: session.index.bookId,
      spineIndex: spine.index,
      href: spine.href,
      sourceChecksum: spine.sourceChecksum,
    );
    await _readerDiagTimedOperation(
      name: 'cold_restore_setup_jump',
      targetSpineIndex: target.spineIndex,
      action: () async => _navigateToStableLocation(target),
      isComplete: () =>
          _currentStableLocation()?.spineIndex == target.spineIndex,
    );
    await _persistReadingPosition(_currentPage);
    await prefs.setBool(restoreMarkerKey, true);
    _readerDiagLog('cold_restore_setup_ready', {
      'book': widget.bookId,
      'scenario': 'D',
      'targetSpineIndex': target.spineIndex,
      'targetHref': target.href,
      'currentPage': _currentPage,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
  }

  Future<void> _runReaderDiagCacheCorruptScenario() async {
    final current = _currentStableLocation();
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    final markerKey = 'nalori_diag_segment_corrupt_ready_${widget.bookId}';
    final restoreReady = prefs.getBool(markerKey) ?? false;
    if (restoreReady) {
      await prefs.remove(markerKey);
      _readerDiagLog('segment_corrupt_restore_detected', {
        'book': widget.bookId,
        'scenario': 'CACHE_CORRUPT',
        'currentSpineIndex': current.spineIndex,
        'currentHref': current.href,
        'currentPage': _currentPage,
        'activeWindowBounds': _activeLazyWindowBoundsLabel(),
        'lastCompletedCacheKey': _lastCompletedDisplayRebuildCacheKey,
      });
      await _readerDiagBoundary(direction: DisplayRangeDirection.backward);
      await _readerDiagBoundary(direction: DisplayRangeDirection.forward);
      return;
    }

    final signature = _lastCompletedDisplayRebuildSignature;
    final targetOriginalIndex =
        _currentPage >= 0 &&
            _currentPage < _displayToOriginal.length &&
            _displayToOriginal[_currentPage].isNotEmpty
        ? _displayToOriginal[_currentPage].first
        : null;
    if (signature == null || targetOriginalIndex == null) {
      _readerDiagLog('reader_diag_operation_skipped', {
        'book': widget.bookId,
        'scenario': 'CACHE_CORRUPT',
        'reason': signature == null
            ? 'missing_completed_display_signature'
            : 'missing_current_source_index',
        'currentPage': _currentPage,
        'displayToOriginal': _displayToOriginal.length,
      });
      return;
    }

    final key = _segmentedDisplayCacheKey(
      cacheKey: signature.cacheKey,
      signature: signature,
      sourceIndex: targetOriginalIndex,
    );
    final service = await _segmentedDisplayCache();
    final corrupted = await service.corruptSegmentAroundSourceForDiagnostics(
      key: key,
      sourceIndex: targetOriginalIndex,
    );
    await _persistReadingPosition(_currentPage);
    if (corrupted) {
      await prefs.setBool(markerKey, true);
    }
    _readerDiagLog('segment_corrupt_setup_ready', {
      'book': widget.bookId,
      'scenario': 'CACHE_CORRUPT',
      'corrupted': corrupted,
      'currentPage': _currentPage,
      'currentSpineIndex': current.spineIndex,
      'targetOriginalIndex': targetOriginalIndex,
      'cacheKey': key.cacheKey,
      'sourceChunkCount': key.sourceChunkCount,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
  }

  Future<void> _runReaderDiagSequenceE() async {
    await _readerDiagSettingsChange(
      'font_size',
      _settings.copyWith(
        fontSize:
            ReaderFontSize.values[(_settings.fontSize.index + 1) %
                ReaderFontSize.values.length],
      ),
    );
    await _readerDiagSettingsChange(
      'density',
      _settings.copyWith(
        contentDensity:
            ContentDensity.values[(_settings.contentDensity.index + 1) %
                ContentDensity.values.length],
      ),
    );
    await _readerDiagSettingsChange(
      'margin',
      _settings.copyWith(
        sideMargin: (_settings.sideMargin + 4).clamp(8.0, 48.0),
      ),
    );
    await _readerDiagSettingsChange(
      'line_height',
      _settings.copyWith(
        lineHeight: (_settings.lineHeight + 0.1).clamp(1.0, 2.0),
      ),
    );
    await _readerDiagOrientationChange();
  }

  Future<void> _readerDiagSettingsChange(
    String name,
    ReadingSettings updated,
  ) async {
    final beforeGeneration = _rebuildGeneration;
    final beforeCacheKey =
        _displayGenerationCoordinator.activeToken?.signature.cacheKey;
    final beforeCompletedAtMs = _lastCompletedDisplayRebuildAtMs;
    await _readerDiagTimedOperation(
      name: 'settings_$name',
      targetSpineIndex: _currentStableLocation()?.spineIndex,
      action: () async => _handleSettingsUpdate(updated),
      isComplete: () {
        final completedNewLayout =
            _lastCompletedDisplayRebuildAtMs > beforeCompletedAtMs &&
            _lastCompletedDisplayRebuildGeneration > beforeGeneration &&
            _lastCompletedDisplayRebuildCacheKey != null &&
            _lastCompletedDisplayRebuildCacheKey != beforeCacheKey;
        return completedNewLayout &&
            _hasCompletedDisplayChunkBuild &&
            !_isRebuildingChunks &&
            !_hasForegroundReaderWork();
      },
    );
    await _readerDiagBoundary(direction: DisplayRangeDirection.backward);
    await _readerDiagBoundary(direction: DisplayRangeDirection.forward);
  }

  Future<void> _readerDiagOrientationChange() async {
    final beforeGeneration = _rebuildGeneration;
    final beforeCacheKey =
        _displayGenerationCoordinator.activeToken?.signature.cacheKey;
    final beforeCompletedAtMs = _lastCompletedDisplayRebuildAtMs;
    await _readerDiagTimedOperation(
      name: 'settings_orientation_landscape',
      targetSpineIndex: _currentStableLocation()?.spineIndex,
      action: () async {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
        ]);
      },
      isComplete: () {
        final completedNewLayout =
            _lastCompletedDisplayRebuildAtMs > beforeCompletedAtMs &&
            _lastCompletedDisplayRebuildGeneration > beforeGeneration &&
            _lastCompletedDisplayRebuildCacheKey != null &&
            _lastCompletedDisplayRebuildCacheKey != beforeCacheKey;
        return completedNewLayout &&
            _hasCompletedDisplayChunkBuild &&
            !_isRebuildingChunks &&
            !_hasForegroundReaderWork();
      },
    );
    await _readerDiagBoundary(direction: DisplayRangeDirection.backward);
    await _readerDiagBoundary(direction: DisplayRangeDirection.forward);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _readerDiagChapterJump(
    String name, {
    required bool forward,
  }) async {
    final beforeLocation = _currentStableLocation();
    final session = _lazySession;
    if (session != null && beforeLocation != null) {
      final targetSpineIndex = forward
          ? session.nextReadableSpineIndex(beforeLocation.spineIndex)
          : session.previousReadableSpineIndex(beforeLocation.spineIndex);
      if (targetSpineIndex == null) {
        _readerDiagLog('reader_diag_operation_skipped', {
          'book': widget.bookId,
          'name': name,
          'reason': 'no_adjacent_readable_spine',
          'direction': forward ? 'next' : 'previous',
          'sourceSpineIndex': beforeLocation.spineIndex,
        });
        return;
      }
      final spine = session.index.spine[targetSpineIndex];
      final target = StableBookLocation(
        bookId: session.index.bookId,
        spineIndex: spine.index,
        href: spine.href,
        sourceChecksum: spine.sourceChecksum,
      );
      await _readerDiagTimedOperation(
        name: name,
        targetSpineIndex: target.spineIndex,
        action: () async {
          _readerDiagLog('reader_diag_chapter_jump_action', {
            'book': widget.bookId,
            'name': name,
            'direction': forward ? 'next' : 'previous',
            'mode': 'lazy_adjacent_spine',
            'sourceSpineIndex': beforeLocation.spineIndex,
            'targetSpineIndex': target.spineIndex,
            'targetHref': target.href,
            'currentPage': _currentPage,
            'activeWindowBounds': _activeLazyWindowBoundsLabel(),
          });
          await _navigateToStableLocation(target);
        },
        isComplete: () =>
            _currentStableLocation()?.spineIndex == target.spineIndex,
      );
      return;
    }

    final before = beforeLocation?.spineIndex;
    await _readerDiagTimedOperation(
      name: name,
      targetSpineIndex: null,
      action: () async {
        _readerDiagLog('reader_diag_chapter_jump_action', {
          'book': widget.bookId,
          'name': name,
          'direction': forward ? 'next' : 'previous',
          'hasLazySession': _lazySession != null,
          'currentPage': _currentPage,
          'currentSpineIndex': _currentStableLocation()?.spineIndex,
          'activeWindowBounds': _activeLazyWindowBoundsLabel(),
        });
        if (forward) {
          _jumpToNextChapter();
        } else {
          _jumpToPrevChapter();
        }
      },
      isComplete: () {
        final after = _currentStableLocation()?.spineIndex;
        if (after == null || before == null) return false;
        return forward ? after > before : after < before;
      },
    );
  }

  Future<void> _readerDiagBoundary({
    required DisplayRangeDirection direction,
  }) async {
    final current = _currentStableLocation();
    if (current == null) return;
    final edge = direction == DisplayRangeDirection.forward
        ? _lastDisplayIndexForSpine(current.spineIndex)
        : _firstDisplayIndexForSpine(current.spineIndex);
    if (edge == null) {
      _readerDiagLog('reader_diag_operation_skipped', {
        'book': widget.bookId,
        'name': 'boundary_${direction.name}',
        'reason': 'edge_not_found',
        'sourceSpineIndex': current.spineIndex,
      });
      return;
    }
    _jumpReaderToPage(edge);
    await _waitForReaderDiagIdle('boundary_edge_${direction.name}');
    final sourceSpine = _currentStableLocation()?.spineIndex;
    final expectedTargetSpine = sourceSpine == null
        ? null
        : direction == DisplayRangeDirection.forward
        ? _lazySession?.nextReadableSpineIndex(sourceSpine)
        : _lazySession?.previousReadableSpineIndex(sourceSpine);
    await _readerDiagTimedOperation(
      name: 'boundary_${direction.name}',
      targetSpineIndex: expectedTargetSpine,
      action: () async {
        if (direction == DisplayRangeDirection.forward) {
          _nextReaderPage(
            duration: const Duration(milliseconds: 1),
            curve: Curves.linear,
          );
        } else {
          _previousReaderPage(
            duration: const Duration(milliseconds: 1),
            curve: Curves.linear,
          );
        }
      },
      isComplete: () {
        final after = _currentStableLocation()?.spineIndex;
        if (after == null || sourceSpine == null) return false;
        if (expectedTargetSpine == null) return after == sourceSpine;
        return after == expectedTargetSpine;
      },
    );
  }

  Future<void> _readerDiagTimedOperation({
    required String name,
    required int? targetSpineIndex,
    required Future<void> Function() action,
    required bool Function() isComplete,
  }) async {
    final before = _currentStableLocation();
    final operationId = DateTime.now().microsecondsSinceEpoch;
    final stopwatch = Stopwatch()..start();
    _readerDiagLog('navigation_intent_received', {
      'book': widget.bookId,
      'operationId': operationId,
      'name': name,
      'sourceSpineIndex': before?.spineIndex,
      'sourceHref': before?.href,
      'targetSpineIndex': targetSpineIndex,
      'currentPage': _currentPage,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
    await action();
    var completed = false;
    for (var attempt = 0; attempt < 120; attempt++) {
      if (!mounted) return;
      if (isComplete() &&
          _hasCompletedDisplayChunkBuild &&
          !_isRebuildingChunks) {
        completed = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await _waitForReaderDiagIdle('${name}_complete');
    stopwatch.stop();
    final after = _currentStableLocation();
    _readerDiagLog('navigation_completed', {
      'book': widget.bookId,
      'operationId': operationId,
      'name': name,
      'completed': completed,
      'sourceSpineIndex': before?.spineIndex,
      'targetSpineIndex': after?.spineIndex,
      'targetHref': after?.href,
      'currentPage': _currentPage,
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'displayChunks': _displayChunks.length,
      'sourceChunks': _sourceChunks.length,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
    _readerDiagLog('first_frame_after_navigation', {
      'book': widget.bookId,
      'operationId': operationId,
      'name': name,
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'targetSpineIndex': after?.spineIndex,
    });
  }

  Future<void> _waitForReaderDiagIdle(String reason) async {
    for (var attempt = 0; attempt < 120; attempt++) {
      if (!mounted) return;
      if (_hasCompletedDisplayChunkBuild &&
          !_isRebuildingChunks &&
          _activeProgressiveRangeTask == null &&
          !_isLoadingLazyForwardSection &&
          !_isLoadingLazyBackwardSection &&
          !_isPreparingForwardRange &&
          !_isPreparingBackwardRange &&
          !_isPreparingTargetRange) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _readerDiagLog('reader_diag_wait_timeout', {
      'book': widget.bookId,
      'reason': reason,
      'hasCompletedDisplayChunkBuild': _hasCompletedDisplayChunkBuild,
      'isRebuildingChunks': _isRebuildingChunks,
      'hasActiveProgressiveRange': _activeProgressiveRangeTask != null,
      'loadingForward': _isLoadingLazyForwardSection,
      'loadingBackward': _isLoadingLazyBackwardSection,
    });
  }

  Future<void> _waitForDisplayWindowReady() async {
    const maxAttempts = 40;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted) return;
      if (_hasCompletedDisplayChunkBuild && _progressiveDisplayState != null) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  int? _sourceIndexForStableLocation(StableBookLocation location) {
    final exact = readerSourceIndexForStableLocation(
      location: location,
      locationsByChunkIndex: _sourceLocationsByChunkIndex,
      sourceIdentitiesByChunkIndex: _sourceIdentitiesByChunkIndex,
    );
    if (exact != null) return exact;
    if (readerHasDurableSourceIdentity(location)) return null;

    final anchorId = location.anchorId;
    if (anchorId != null && anchorId.isNotEmpty) {
      final anchorIndex =
          _sourceAnchorMap[anchorId] ??
          _sourceAnchorMap[Uri.decodeComponent(anchorId)];
      if (anchorIndex != null) {
        final anchorLocation = _sourceLocationsByChunkIndex[anchorIndex];
        if (anchorLocation == null ||
            anchorLocation.spineIndex == location.spineIndex) {
          return anchorIndex;
        }
      }
    }

    return _sourceLocationsByChunkIndex.entries
        .cast<MapEntry<int, StableBookLocation>?>()
        .firstWhere(
          (entry) =>
              entry != null &&
              entry.value.spineIndex == location.spineIndex &&
              (location.localChunkIndex == null ||
                  entry.value.localChunkIndex == location.localChunkIndex),
          orElse: () => null,
        )
        ?.key;
  }

  StableBookLocation? _currentStableLocation() {
    if (_displayChunks.isEmpty || _displayToOriginal.isEmpty) return null;
    final displayIndex = _currentPage.clamp(0, _displayToOriginal.length - 1);
    return _firstLocationForDisplayIndex(displayIndex);
  }

  ReaderCardIdentity? _cardIdentityForDisplay(int displayIndex) {
    final layoutFingerprint = _activeReaderLayoutFingerprint;
    final publicationFingerprint = _publicationFingerprint;
    if (layoutFingerprint == null ||
        publicationFingerprint == null ||
        displayIndex < 0 ||
        displayIndex >= _displayChunks.length ||
        displayIndex >= _displayToOriginal.length) {
      return null;
    }
    return ReaderCardIdentity.fromCard(
      publicationFingerprint: publicationFingerprint,
      layoutFingerprint: layoutFingerprint,
      card: _displayChunks[displayIndex],
      sourceChunks: _publishedSourceChunks,
      sourceIndices: _displayToOriginal[displayIndex],
      locationsBySourceIndex: _publishedSourceLocationsByChunkIndex,
      stableSourceKeys: {
        for (final entry in _publishedSourceIdentitiesByChunkIndex.entries)
          entry.key: entry.value.stableKey,
      },
    );
  }

  List<ReaderCardIdentity> _currentCardIdentities() {
    final identities = <ReaderCardIdentity>[];
    for (var index = 0; index < _displayChunks.length; index++) {
      final identity = _cardIdentityForDisplay(index);
      if (identity == null) return const [];
      identities.add(identity);
    }
    return identities;
  }

  ReaderRestoreResolution? _resolveCanonicalCheckpointRestore() {
    final coordinator = _checkpointCoordinator;
    final layoutFingerprint = _activeReaderLayoutFingerprint;
    if (coordinator == null ||
        coordinator.current == null ||
        layoutFingerprint == null) {
      return null;
    }
    return coordinator.resolveRestore(
      cards: _currentCardIdentities(),
      currentLayoutFingerprint: layoutFingerprint,
    );
  }

  void _scheduleCheckpointPublicationVerification(int displayIndex) {
    final coordinator = _checkpointCoordinator;
    if (coordinator == null ||
        !coordinator.isInitialized ||
        coordinator.ordinaryWritesEnabled ||
        _checkpointVerificationScheduled) {
      return;
    }
    _checkpointVerificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _checkpointVerificationScheduled = false;
      if (!mounted ||
          displayIndex != _currentPage ||
          displayIndex != _activeDisplayIndex) {
        return;
      }
      if (!_usesInteractiveCardDeck) {
        final controller = _pageController;
        final attachedPage = controller?.hasClients == true
            ? controller!.page
            : null;
        if (attachedPage == null ||
            (attachedPage - displayIndex).abs() > 0.01) {
          _readerDiagLog('restore_publication_waiting_for_controller', {
            'book': widget.bookId,
            'displayIndex': displayIndex,
            'controllerPage': attachedPage,
          });
          _scheduleCheckpointPublicationVerification(displayIndex);
          return;
        }
      }
      final visible = _cardIdentityForDisplay(displayIndex);
      if (visible == null) return;
      final saved = coordinator.current;
      final resolution = _pendingCheckpointRestoreResolution;
      if (saved != null) {
        final strategy =
            resolution?.strategy ??
            (saved.card?.signature == visible.signature
                ? ReaderRestoreMatchStrategy.exactSignature
                : ReaderRestoreMatchStrategy.semanticAnchor);
        if (!coordinator.verifyPublished(
          visibleCard: visible,
          strategy: strategy,
        )) {
          _readerDiagLog('restore_publication_rejected', {
            'book': widget.bookId,
            'visibleCardSignature': visible.signature,
            'expectedCardSignature': saved.card?.signature,
            'reason': 'visible_identity_does_not_match_checkpoint',
          });
          return;
        }
        if (strategy == ReaderRestoreMatchStrategy.semanticAnchor) {
          final result = await coordinator.commitCard(
            card: visible,
            stableLocation: _committedStableLocationForDisplay(displayIndex),
            navigationSource: 'restore_reflow_complete',
            duringRestore: true,
            layoutToken: _activeCheckpointLayoutToken,
          );
          if (!result.applied) return;
          _activeCheckpointLayoutToken = null;
        }
      } else {
        final result = await coordinator.migrateLegacy(
          card: visible,
          stableLocation: _committedStableLocationForDisplay(displayIndex),
        );
        if (!result.applied) return;
      }
      if (!mounted || displayIndex != _currentPage) return;
      final visibleLocation = _committedStableLocationForDisplay(displayIndex);
      final visibleIntent = _visiblePositionCoordinator.activeIntent;
      if (visibleLocation == null ||
          visibleIntent == null ||
          !visibleIntent.isInitialRestore) {
        _logVisiblePositionMutation(
          reason: 'restore_verification',
          classification: ReaderVisibleMutationClassification.programmatic,
          accepted: false,
          decisionReason: visibleLocation == null
              ? 'stable_location_unavailable'
              : 'initial_restore_intent_unavailable',
          oldLocation: _visiblePositionCoordinator.committedLocation,
          newLocation: visibleLocation,
          newLocalIndex: displayIndex,
          intent: visibleIntent,
        );
        return;
      }
      final visibleDecision = _visiblePositionCoordinator.completeIntent(
        intent: visibleIntent,
        resolvedLocation: visibleIntent.target,
        windowGeneration: _rebuildGeneration,
        publicationGeneration: _progressiveRangeGeneration,
      );
      _logVisiblePositionMutation(
        reason: 'restore_verification',
        classification: ReaderVisibleMutationClassification.programmatic,
        accepted: visibleDecision.accepted,
        decisionReason: visibleDecision.reason,
        oldLocation: visibleDecision.oldLocation,
        newLocation: visibleDecision.newLocation,
        oldLocalIndex: _positionSession.committedReadingPosition,
        newLocalIndex: displayIndex,
        intent: visibleIntent,
      );
      if (visibleIntent.isConsumed &&
          identical(_controllerIntent, visibleIntent)) {
        _controllerIntent = null;
      }
      if (!visibleDecision.accepted) return;
      _pendingCheckpointRestoreResolution = null;
      _positionSession.markCommitted(displayIndex);
      _readerDiagLog('restore_complete', {
        'book': widget.bookId,
        'displayIndex': displayIndex,
        'cardSignature': visible.signature,
        'layoutFingerprint': visible.layoutFingerprint,
      });
    });
  }

  ReaderPublishedCardBoundaryEvidence? _publishedBoundaryEvidenceForDisplay(
    int displayIndex,
  ) {
    if (displayIndex < 0 ||
        displayIndex >= _displayChunks.length ||
        displayIndex >= _displayToOriginal.length) {
      return null;
    }
    final startLocation = _firstLocationForDisplayIndex(displayIndex);
    if (startLocation == null) return null;

    final originals = _displayToOriginal[displayIndex];
    if (originals.isEmpty) return null;
    final ranges = _displayChunks[displayIndex].effectiveSourceRanges;
    final lastRange = ranges.isEmpty
        ? null
        : ranges.reduce(
            (current, candidate) =>
                candidate.displayEndOffset > current.displayEndOffset
                ? candidate
                : current,
          );
    final endOriginal = lastRange?.originalChunkIndex ?? originals.last;
    final endBase = _publishedSourceLocationsByChunkIndex[endOriginal];
    if (endBase == null) return null;
    final endSource =
        endOriginal >= 0 && endOriginal < _publishedSourceChunks.length
        ? _publishedSourceChunks[endOriginal]
        : null;
    final sourceLength = endSource?.type == BookChunkType.text
        ? (endSource?.text?.length ?? 0)
        : 1;
    final endOffset = lastRange?.originalEndOffset ?? sourceLength;
    final reachesEndOfSourceChunk =
        endSource == null ||
        endSource.type != BookChunkType.text ||
        endOffset >= sourceLength;

    final readableIndexes = <int>[];
    for (final entry in _publishedSourceLocationsByChunkIndex.entries) {
      if (entry.value.spineIndex != endBase.spineIndex) continue;
      if (entry.key < 0 || entry.key >= _publishedSourceChunks.length) {
        continue;
      }
      final source = _publishedSourceChunks[entry.key];
      if (source.type != BookChunkType.text ||
          (source.text?.trim().isNotEmpty ?? false)) {
        readableIndexes.add(entry.key);
      }
    }
    if (readableIndexes.isEmpty) return null;
    final finalReadableSourceIndex = readableIndexes.reduce(math.max);
    final reachesEndOfResolvedSection =
        endOriginal == finalReadableSourceIndex && reachesEndOfSourceChunk;
    final session = _lazySession;
    final nextReadableSpineIndex = session?.nextReadableSpineIndex(
      endBase.spineIndex,
    );
    final sectionChunkCount = _publishedSourceLocationsByChunkIndex.values
        .where((location) => location.spineIndex == endBase.spineIndex)
        .length;
    final refinedEnd = session?.refineSourceLocation(
      endBase,
      sourceChunkCount: sectionChunkCount,
      sourceTextLength: sourceLength,
      textOffset: endOffset,
    );
    return ReaderPublishedCardBoundaryEvidence(
      startLocation: startLocation,
      endLocation: refinedEnd ?? endBase.copyWith(textOffset: endOffset),
      reachesEndOfSourceChunk: reachesEndOfSourceChunk,
      reachesEndOfResolvedSection: reachesEndOfResolvedSection,
      resolvedSectionComplete: session != null,
      nextReadableSpineIndex: nextReadableSpineIndex,
    );
  }

  StableBookLocation? _committedStableLocationForDisplay(int displayIndex) {
    final evidence = _publishedBoundaryEvidenceForDisplay(displayIndex);
    return evidence?.locationForCommittedProgress() ??
        _firstLocationForDisplayIndex(displayIndex);
  }

  Set<int> _displayIndexesReachingChapterBoundary() {
    if (_lazySession == null || _chapterNavigationTargets.isEmpty) {
      return const <int>{};
    }
    final completed = <int>{};
    final selectable = _chapterNavigationTargets
        .where((target) => target.isSelectable)
        .toList(growable: false);
    for (
      var displayIndex = 0;
      displayIndex < _displayChunks.length;
      displayIndex++
    ) {
      final evidence = _publishedBoundaryEvidenceForDisplay(displayIndex);
      if (evidence == null) continue;
      final currentTargetIndex = ChapterNavigationService.currentTargetIndex(
        selectable,
        evidence.startLocation,
      );
      if (currentTargetIndex < 0) continue;
      final nextTarget = currentTargetIndex + 1 < selectable.length
          ? selectable[currentTargetIndex + 1]
          : null;
      if (evidence.reachesChapterBoundary(nextTarget?.stableLocation)) {
        completed.add(displayIndex);
      }
    }
    return completed;
  }

  void _scheduleChapterCardLayoutCompletion(int displayIndex) {
    if (!_settings.enableCardDepth || _lazySession == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentPage != displayIndex) return;
      unawaited(_ensureChapterCardLayout(displayIndex));
    });
  }

  ({
    ChapterCardLayoutKey key,
    ChapterNavigationTarget target,
    ChapterNavigationTarget? next,
    DisplayGenerationSignature signature,
  })?
  _chapterLayoutDescriptor(int displayIndex) {
    final evidence = _publishedBoundaryEvidenceForDisplay(displayIndex);
    final signature = _displayGenerationCoordinator.activeToken?.signature;
    final session = _lazySession;
    if (evidence == null || signature == null || session == null) return null;
    final targets = _chapterNavigationTargets
        .where((target) => target.isSelectable)
        .toList(growable: false);
    final targetIndex = ChapterNavigationService.currentTargetIndex(
      targets,
      evidence.startLocation,
    );
    if (targetIndex < 0) return null;
    final target = targets[targetIndex];
    final next = targetIndex + 1 < targets.length
        ? targets[targetIndex + 1]
        : null;
    final chapterIdentity = [
      target.spineIndex,
      target.resolvedLocalChunkIndex ?? -1,
      target.textOffset,
      target.anchorId ?? '',
      next?.spineIndex ?? -1,
      next?.resolvedLocalChunkIndex ?? -1,
      next?.textOffset ?? -1,
      next?.anchorId ?? '',
    ].join(':');
    return (
      key: ChapterCardLayoutKey(
        bookId: widget.bookId,
        publicationFingerprint: session.index.publicationFingerprint,
        chapterIdentity: chapterIdentity,
        parserSchema: BookCacheService.parsedBookCacheFormatVersion,
        displaySchema:
            '${BookCacheService.displayCacheFormatVersion}|'
            '${BookCacheService.displayLayoutVersion}',
        settingsSignature: signature.settingsSignature,
        viewportSignature: signature.viewportSignature,
        cardMode: true,
      ),
      target: target,
      next: next,
      signature: signature,
    );
  }

  Future<void> _ensureChapterCardLayout(int displayIndex) async {
    final descriptor = _chapterLayoutDescriptor(displayIndex);
    if (descriptor == null) return;
    final priorTask = _activeChapterLayoutTask;
    if (priorTask != null &&
        !_chapterCardLayoutCoordinator.isActiveFor(descriptor.key)) {
      _cancelChapterCardLayoutWork();
      await priorTask;
      if (!mounted) return;
    }
    final service = await _segmentedDisplayCache();
    if (!mounted) return;
    late final Future<ChapterCardLayout?> coordinated;
    coordinated = _chapterCardLayoutCoordinator.ensure(
      key: descriptor.key,
      load: () => service.loadChapterCardLayoutRecord(descriptor.key),
      generate: (isCurrent) async {
        final prepared = await _prepareChapterLayoutSource(
          key: descriptor.key,
          signature: descriptor.signature,
          target: descriptor.target,
          next: descriptor.next,
          isCurrent: isCurrent,
        );
        if (prepared == null || !isCurrent()) return null;
        return _generateAndCacheChapterLayout(prepared, isCurrent: isCurrent);
      },
    );
    final task = () async {
      ChapterCardLayout? layout;
      try {
        layout = await coordinated;
      } catch (error) {
        _readerDiagLog('chapter_layout_background_failed', {
          'book': widget.bookId,
          'error': error.runtimeType,
        });
        return;
      }
      if (!mounted || layout == null) return;
      final currentDescriptor = _chapterLayoutDescriptor(_currentPage);
      if (currentDescriptor?.key != layout.key) return;
      setState(() => _currentChapterCardLayout = layout);
    }();
    _activeChapterLayoutTask = task;
    try {
      await task;
    } finally {
      if (identical(_activeChapterLayoutTask, task)) {
        _activeChapterLayoutTask = null;
      }
    }
  }

  Future<_PreparedChapterLayoutSource?> _prepareChapterLayoutSource({
    required ChapterCardLayoutKey key,
    required DisplayGenerationSignature signature,
    required ChapterNavigationTarget target,
    required ChapterNavigationTarget? next,
    required bool Function() isCurrent,
  }) async {
    final session = _lazySession;
    final stableCurrent = _currentStableLocation();
    if (session == null || stableCurrent == null || !isCurrent()) return null;
    final readable = session.index.spine
        .where((item) => item.isLinear)
        .map((item) => item.index)
        .toList(growable: false);
    if (readable.isEmpty) return null;
    final endSpine = next?.spineIndex ?? readable.last;
    final spines = readable
        .where((spine) => spine >= target.spineIndex && spine <= endSpine)
        .toList(growable: false);
    if (spines.isEmpty) return null;

    // A missing chapter boundary that covers the entire publication is not a
    // chapter-scoped request. Counting it would silently reintroduce whole-book
    // pagination, which Phase 5 explicitly forbids.
    if (!readerShouldBackgroundPaginateChapter(
      hasStructuralChapterBoundary: next != null,
      startsAtPublicationStart: target.spineIndex == readable.first,
      spansAllReadableSections: spines.length == readable.length,
    )) {
      return null;
    }

    final chunks = <BookChunk>[];
    final locations = <int, StableBookLocation>{};
    final sectionChunkCounts = <int, int>{};
    StableBookLocation? chapterEnd;
    try {
      for (final spine in spines) {
        if (!isCurrent()) return null;
        final section = await session.loadSection(
          spine,
          priority: LazySectionWorkPriority.layoutPagination,
          preserveDistantTarget: true,
        );
        if (!isCurrent()) return null;
        if (section.chunks.isEmpty) continue;
        sectionChunkCounts[spine] = section.chunks.length;
        final startLocal = spine == target.spineIndex
            ? (target.resolvedLocalChunkIndex ??
                      target.stableLocation.localChunkIndex ??
                      0)
                  .clamp(0, section.chunks.length - 1)
            : 0;
        final endLocal = spine == next?.spineIndex
            ? (next?.resolvedLocalChunkIndex ??
                      next?.stableLocation.localChunkIndex ??
                      0)
                  .clamp(startLocal, section.chunks.length - 1)
            : section.chunks.length - 1;
        for (var local = startLocal; local <= endLocal; local++) {
          final detachedIndex = chunks.length;
          final chunk = section.chunks[local];
          chunks.add(chunk.copyWith(index: detachedIndex));
          locations[detachedIndex] = session.locationForSectionChunk(
            section,
            local,
          );
        }
        if (next == null && spine == spines.last && chunks.isNotEmpty) {
          final lastIndex = chunks.length - 1;
          final source = chunks[lastIndex];
          final sourceLength = source.type == BookChunkType.text
              ? (source.text?.length ?? 0)
              : 1;
          chapterEnd = session.refineSourceLocation(
            locations[lastIndex]!,
            sourceChunkCount: section.chunks.length,
            sourceTextLength: sourceLength,
            textOffset: sourceLength,
          );
        }
      }
    } finally {
      // Detached chapter counting may temporarily touch distant sections. The
      // live session must always return ownership to the published anchor,
      // including cancellation and parse/generation failures.
      session.updateCurrentLocation(stableCurrent);
    }
    if (chunks.isEmpty || !isCurrent()) return null;
    chapterEnd ??= next?.stableLocation;
    if (chapterEnd == null) return null;
    final cacheKey = SegmentedDisplayCacheKey(
      bookId: widget.bookId,
      cacheKey:
          '${signature.cacheKey}_chapter_layout_${_stableReaderCacheId(key.cacheKey)}',
      signature: signature,
      sourceChunkCount: chunks.length,
    );
    return _PreparedChapterLayoutSource(
      key: key,
      cacheKey: cacheKey,
      signature: signature,
      chunks: chunks,
      locations: locations,
      sectionChunkCounts: sectionChunkCounts,
      chapterStart: target.stableLocation,
      chapterEnd: chapterEnd,
    );
  }

  Future<ChapterCardLayout?> _generateAndCacheChapterLayout(
    _PreparedChapterLayoutSource prepared, {
    required bool Function() isCurrent,
  }) async {
    final generator = _chapterDisplayRangeGenerator;
    if (generator == null || !isCurrent()) return null;
    final foreground = _activeProgressiveRangeTask;
    if (foreground != null) await foreground;
    if (!mounted || !isCurrent()) return null;

    final rangeGeneration = ++_progressiveRangeGeneration;
    _activeChapterLayoutRangeGeneration = rangeGeneration;
    final request = DisplayRangeRequest(
      direction: DisplayRangeDirection.forward,
      sourceRange: SourceChunkRange(0, prepared.chunks.length),
      generationId: rangeGeneration,
      reason: 'chapter_total_background',
    );
    try {
      final result = await generator(request, prepared.chunks);
      if (!mounted || !isCurrent() || result.cancelled) return null;
      final layout = _chapterCardLayoutFromResult(prepared, result);
      if (layout == null) return null;
      final service = await _segmentedDisplayCache();
      if (!isCurrent()) return null;
      await service.writeChapterCardLayout(
        key: prepared.cacheKey,
        result: result,
        generationId: rangeGeneration,
        layout: layout,
        shouldWrite: isCurrent,
      );
      await service.writeChapterCardLayoutRecord(
        layout: layout,
        shouldWrite: isCurrent,
      );
      return isCurrent() ? layout : null;
    } finally {
      _cancelledProgressiveRangeGenerations.remove(rangeGeneration);
      if (_activeChapterLayoutRangeGeneration == rangeGeneration) {
        _activeChapterLayoutRangeGeneration = null;
      }
    }
  }

  ChapterCardLayout? _chapterCardLayoutFromResult(
    _PreparedChapterLayoutSource prepared,
    DisplayRangeResult result,
  ) {
    final session = _lazySession;
    if (session == null) return null;
    final pages = <ChapterCardSourceRange>[];
    for (var i = 0; i < result.displayChunks.length; i++) {
      if (i >= result.displayToOriginal.length) break;
      final ranges = result.displayChunks[i].effectiveSourceRanges;
      final originals = result.displayToOriginal[i];
      if (originals.isEmpty) continue;
      final firstRange = ranges.isEmpty ? null : ranges.first;
      final lastRange = ranges.isEmpty ? null : ranges.last;
      final firstOriginal = firstRange?.originalChunkIndex ?? originals.first;
      final lastOriginal = lastRange?.originalChunkIndex ?? originals.last;
      final firstBase = prepared.locations[firstOriginal];
      final lastBase = prepared.locations[lastOriginal];
      if (firstBase == null || lastBase == null) continue;
      final firstSource = prepared.chunks[firstOriginal];
      final lastSource = prepared.chunks[lastOriginal];
      final firstSourceLength = firstSource.type == BookChunkType.text
          ? (firstSource.text?.length ?? 0)
          : 1;
      final lastSourceLength = lastSource.type == BookChunkType.text
          ? (lastSource.text?.length ?? 0)
          : 1;
      var start = session.refineSourceLocation(
        firstBase,
        sourceChunkCount:
            prepared.sectionChunkCounts[firstBase.spineIndex] ?? 1,
        sourceTextLength: firstSourceLength,
        textOffset: firstRange?.originalStartOffset ?? 0,
      );
      var end = session.refineSourceLocation(
        lastBase,
        sourceChunkCount: prepared.sectionChunkCounts[lastBase.spineIndex] ?? 1,
        sourceTextLength: lastSourceLength,
        textOffset: lastRange?.originalEndOffset ?? lastSourceLength,
      );
      if (compareStableSourceLocations(end, prepared.chapterStart) <= 0 ||
          compareStableSourceLocations(start, prepared.chapterEnd) >= 0) {
        continue;
      }
      if (compareStableSourceLocations(start, prepared.chapterStart) < 0) {
        start = prepared.chapterStart;
      }
      if (compareStableSourceLocations(end, prepared.chapterEnd) > 0) {
        end = prepared.chapterEnd;
      }
      if (compareStableSourceLocations(start, end) >= 0) continue;
      pages.add(ChapterCardSourceRange(start: start, end: end));
    }
    if (pages.isEmpty) return null;
    return ChapterCardLayout(
      key: prepared.key,
      pages: pages,
      completedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _replaceLazySourceWindow(LazyLoadedContentWindow window) {
    _sourceChunks = List<BookChunk>.from(window.chunks);
    _sourceAnchorMap = Map<String, int>.from(window.anchorMap);
    _sourceChapters = List<ChapterInfo>.from(window.chapters);
    _sourceSearchIndex = Map<String, List<int>>.from(window.searchIndex);
    _sourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
      window.locationsByChunkIndex,
    );
    _sourceIdentitiesByChunkIndex = Map<int, LazySourceChunkIdentity>.from(
      window.sourceIdentitiesByChunkIndex,
    );
    _lazyHasContentAfter = window.hasContentAfter;
    final loadedSpines = _sourceLocationsByChunkIndex.values
        .map((location) => location.spineIndex)
        .toSet();
    if (loadedSpines.isEmpty) {
      _lazyMaxLoadedSpineIndex = null;
    } else {
      _lazyMaxLoadedSpineIndex = loadedSpines.reduce(math.max);
    }
    _cachedFlatChapters = null;
  }

  Future<void> _navigateToSourceLocation({
    required int originalChunkIndex,
    int? originalStartOffset,
    String? sourceText,
    bool exploratory = false,
    String navigationSource = 'programmatic',
    StableBookLocation? targetLocation,
    ReaderVisibleNavigationIntent<StableBookLocation>? navigationIntent,
  }) async {
    final existing = _displayIndexForSourceLocation(
      originalChunkIndex: originalChunkIndex,
      originalStartOffset: originalStartOffset,
      sourceText: sourceText,
    );
    if (existing != null) {
      _navigateTo(
        existing,
        exploratory: exploratory,
        navigationSource: navigationSource,
        targetLocation: targetLocation,
        navigationIntent: navigationIntent,
      );
      return;
    }

    var state = _progressiveDisplayState;
    if (state == null || _isRebuildingChunks) {
      _readerDiagLog('source_navigation_wait_for_display_state', {
        'book': widget.bookId,
        'targetOriginalIndex': originalChunkIndex,
        'isRebuildingChunks': _isRebuildingChunks,
        'hasProgressiveState': state != null,
      });
      for (var attempt = 0; attempt < 40; attempt++) {
        if (!mounted) return;
        if (!_isRebuildingChunks && _progressiveDisplayState != null) {
          state = _progressiveDisplayState;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final retryDisplayIndex = _displayIndexForSourceLocation(
        originalChunkIndex: originalChunkIndex,
        originalStartOffset: originalStartOffset,
        sourceText: sourceText,
      );
      if (retryDisplayIndex != null) {
        _navigateTo(
          retryDisplayIndex,
          exploratory: exploratory,
          navigationSource: navigationSource,
          targetLocation: targetLocation,
          navigationIntent: navigationIntent,
        );
        return;
      }
    }
    if (state == null) return;
    final isLazySession = _lazySession != null;
    final range = state.targetRange(
      targetOriginalIndex: originalChunkIndex,
      lookBehind: isLazySession
          ? _lazyInitialRangeLookBehind
          : _initialRangeLookBehind,
      lookAhead: isLazySession
          ? _lazyInitialRangeLookAhead
          : _initialRangeLookAhead,
      minimumWindow: isLazySession
          ? _lazyMinimumInitialRangeSourceChunks
          : _minimumInitialRangeSourceChunks,
    );
    _readerDiagLog('boundary_wait_begin', {
      'book': widget.bookId,
      'generation': _rebuildGeneration,
      'targetOriginalIndex': originalChunkIndex,
      'sourceStart': range.start,
      'sourceEndExclusive': range.endExclusive,
    });
    await _prepareProgressiveDisplayRange(
      direction: DisplayRangeDirection.target,
      sourceRange: range,
      reason: 'source_anchor_navigation',
      targetOriginalIndex: originalChunkIndex,
      targetTextOffset: originalStartOffset ?? targetLocation?.textOffset ?? 0,
    );
    if (!mounted) return;
    _readerDiagLog('boundary_wait_end', {
      'book': widget.bookId,
      'generation': _rebuildGeneration,
      'targetOriginalIndex': originalChunkIndex,
    });
    final displayIndex = _displayIndexForSourceLocation(
      originalChunkIndex: originalChunkIndex,
      originalStartOffset: originalStartOffset,
      sourceText: sourceText,
    );
    if (displayIndex != null) {
      _navigateTo(
        displayIndex,
        exploratory: exploratory,
        navigationSource: navigationSource,
        targetLocation: targetLocation,
        navigationIntent: navigationIntent,
      );
    }
  }

  // Milestone insertion requires a known final display count. Progressive
  // Phase 2 defers it until complete generation/caching returns in later phases.
  // ignore: unused_element
  void _insertMilestoneCards(
    List<BookChunk> displayChunks,
    List<List<int>> displayToOriginal,
    Map<int, int> originalToDisplay,
  ) {
    if (displayChunks.length < 20) return; // Too short for milestones

    final totalChunks = displayChunks.length;
    final milestonePositions = [
      (ratio: 0.25, text: 'You\'re 25% through!'),
      (ratio: 0.50, text: 'Halfway there — 50%!'),
      (ratio: 0.75, text: '75% done — almost there!'),
    ];

    int inserted = 0;
    for (final ms in milestonePositions) {
      final pos = (totalChunks * ms.ratio).round() + inserted;
      if (pos >= displayChunks.length) continue;
      final percentage = (ms.ratio * 100).round();

      final milestoneChunk = BookChunk(
        index: -1, // synthetic — doesn't map to any original chunk
        type: BookChunkType.milestone,
        text: ms.text,
        sourceFile: 'generated:milestone',
        logicalParagraphId:
            'generated:milestone:${_publicationFingerprint ?? widget.bookId}:$percentage',
      );

      displayChunks.insert(pos, milestoneChunk);
      displayToOriginal.insert(pos, []);

      // Shift all originalToDisplay entries after the insertion point
      final updatedMap = <int, int>{};
      for (final entry in originalToDisplay.entries) {
        if (entry.value >= pos) {
          updatedMap[entry.key] = entry.value + 1;
        } else {
          updatedMap[entry.key] = entry.value;
        }
      }
      originalToDisplay
        ..clear()
        ..addAll(updatedMap);

      inserted++;
    }
  }

  // ─── Interaction & UI ────────────────────────────────────────────────

  void _scheduleDwellTracking(int index) {
    _dwellTimer?.cancel();
    if (!_speedReadController.isActive) {
      _dwellTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _currentPage == index && !_isCelebrationVisible) {
          if (_lastDwellPage != null && _lastDwellPage != index) {
            _commitDisplayIndexToHistory(_lastDwellPage!);
          }
          _lastDwellPage = index;
        }
      });
    }

    if (_lastDwellPage == null && _displayChunks.isNotEmpty) {
      _lastDwellPage = index;
    }
  }

  void _runCommittedPageEffects(int index) {
    final committedLocation = _firstLocationForDisplayIndex(index);
    if (committedLocation != null) {
      _lazySession?.updateCurrentLocation(committedLocation);
    }
    _cancelPreviewPromotionTimer();
    _recordReadingInsightForPageChange(index);
    if (_speedReadController.isActive) {
      final text = index < _displayChunks.length
          ? (_displayChunks[index].text ?? '')
          : '';
      _speedReadController.onPageChanged(readerSpeedReadText(text), index);

      if (_speedReadController.tokens.isEmpty) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted &&
              _speedReadController.isActive &&
              _currentPage == index) {
            if (_settings.speedReadPageAdvanceMode ==
                    SpeedReadPageAdvanceMode.auto &&
                index < _displayChunks.length - 1) {
              _nextReaderPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            } else {
              _speedReadController.pause();
            }
          }
        });
      }
    }

    // Record page read for stats
    unawaited(_statsService.recordPageRead(deferSave: true));
    _scheduleDwellTracking(index);
    _updatePositionHistoryNotifier();

    // Persist the canonical source position for both PageView and the custom
    // card deck. The deck changes visual indexes itself, so this must run from
    // the committed reader index rather than from PageController callbacks.
    final provesPublicationEnd = _isAtPublicationEndForCompletion(index);
    if (_displayToOriginal.length > index) {
      final position = _captureCommittedPosition(index);
      if (position != null) {
        _scheduleReadingPositionSave(position);
        if (provesPublicationEnd) {
          unawaited(_flushPendingReadingPosition());
        }
      }
    }
    _maybeRequestProgressiveBoundaryRange(index);
    _scheduleChapterCardLayoutCompletion(index);

    // Publication completion is proved by the published card's source end,
    // never by the end of a bounded display window.
    if (!_hasShownCompletion &&
        provesPublicationEnd &&
        _displayChunks.isNotEmpty) {
      _hasShownCompletion = true;
      _isCelebrationVisible = true;
      if (_settings.readingInsightsEnabled) {
        unawaited(_statsService.recordBookCompletedWithInsights(widget.bookId));
      } else {
        unawaited(_statsService.recordBookCompleted());
      }
      unawaited(_syncNativeReaderControlsState());
    }
  }

  bool _isAtPublicationEndForCompletion([int? displayIndex]) {
    final index = displayIndex ?? _currentPage;
    if (_lazySession == null) {
      return _displayChunksComplete && index == _displayChunks.length - 1;
    }
    return _publishedBoundaryEvidenceForDisplay(index)?.provesPublicationEnd ==
        true;
  }

  StableBookLocation? _firstLocationForDisplayIndex(int displayIndex) {
    if (displayIndex < 0 ||
        displayIndex >= _displayToOriginal.length ||
        displayIndex >= _displayChunks.length) {
      return null;
    }
    final displayRanges = _displayChunks[displayIndex].effectiveSourceRanges;
    for (final original in _displayToOriginal[displayIndex]) {
      final base = _publishedSourceLocationsByChunkIndex[original];
      if (base == null) continue;
      final range = displayRanges
          .where((candidate) => candidate.originalChunkIndex == original)
          .firstOrNull;
      final textOffset = range?.originalStartOffset ?? base.textOffset;

      var sectionProgression = base.sectionProgression;
      var publicationProgression = base.publicationProgression;
      final session = _lazySession;
      final localChunkIndex = base.localChunkIndex;
      final sourceChunk = original < _publishedSourceChunks.length
          ? _publishedSourceChunks[original]
          : null;
      final sourceTextLength = sourceChunk?.type == BookChunkType.text
          ? (sourceChunk?.text?.length ?? 0)
          : 1;
      if (session != null && localChunkIndex != null && sourceChunk != null) {
        final sectionChunkCount = _publishedSourceLocationsByChunkIndex.values
            .where((location) => location.spineIndex == base.spineIndex)
            .length;
        final refined = session.refineSourceLocation(
          base,
          sourceChunkCount: sectionChunkCount,
          sourceTextLength: sourceTextLength,
          textOffset: textOffset,
        );
        sectionProgression = refined.sectionProgression;
        publicationProgression = refined.publicationProgression;
      }
      return base.copyWith(
        textOffset: textOffset,
        sectionProgression: sectionProgression,
        publicationProgression: publicationProgression,
      );
    }
    return null;
  }

  void _recordReadingInsightForPageChange(int newIndex) {
    if (!_settings.readingInsightsEnabled || _speedReadController.isActive) {
      _lastInsightDisplayIndex = newIndex;
      _lastInsightStartedAt = DateTime.now();
      return;
    }

    final previousIndex = _lastInsightDisplayIndex;
    final startedAt = _lastInsightStartedAt;
    _lastInsightDisplayIndex = newIndex;
    _lastInsightStartedAt = DateTime.now();
    if (previousIndex == null || startedAt == null) return;
    if (previousIndex < 0 || previousIndex >= _displayChunks.length) return;

    final seconds = DateTime.now().difference(startedAt).inSeconds;
    if (seconds <= 0 || seconds > 300) return;

    final isSequentialForward = newIndex == previousIndex + 1;
    final previousOriginals = previousIndex < _displayToOriginal.length
        ? _displayToOriginal[previousIndex]
        : const <int>[];
    if (previousOriginals.isEmpty) return;

    final originalIndex = previousOriginals.reduce(math.max);
    final wasAlreadyMeasured = originalIndex <= _highestMeasuredOriginalIndex;
    final measuredWords = isSequentialForward && !wasAlreadyMeasured
        ? _sourceWordCountForDisplayIndex(previousIndex)
        : 0;
    if (measuredWords > 0) {
      _highestMeasuredOriginalIndex = originalIndex;
    }

    final chapterId = _chapterIdForOriginalIndex(originalIndex);
    unawaited(
      _statsService.recordReadingInsightSample(
        bookId: widget.bookId,
        activeSeconds: seconds,
        measuredWords: measuredWords,
        highestMeasuredOriginalIndex: _highestMeasuredOriginalIndex,
        chapterId: chapterId,
        calibratesPace: isSequentialForward && measuredWords > 0,
        deferSave: true,
      ),
    );
  }

  void _onPageChanged(int index) {
    if (_positionSession.isNavigationSuspended) {
      return;
    }

    final isPreviewChange =
        _isScrubbing || _pendingPreviewJumpDisplayIndex == index;
    if (_pendingPreviewJumpDisplayIndex == index) {
      _pendingPreviewJumpDisplayIndex = null;
    }

    if (!isPreviewChange && _positionSession.hasActivePreviewPosition) {
      _promotePreviewToCommitted();
    }

    final callbackClassification = isPreviewChange
        ? ReaderVisibleMutationClassification.user
        : _syntheticControllerTargetIndex == index
        ? ReaderVisibleMutationClassification.synthetic
        : _controllerIntent != null
        ? ReaderVisibleMutationClassification.programmatic
        : ReaderVisibleMutationClassification.user;
    _logVisiblePositionMutation(
      reason: 'controller_index_callback',
      classification: callbackClassification,
      accepted: true,
      decisionReason: isPreviewChange
          ? 'preview_only_not_committed'
          : 'visual_index_only_pending_settlement',
      oldLocation: _currentStableLocation(),
      newLocation: _committedStableLocationForDisplay(index),
      oldLocalIndex: _currentPage,
      newLocalIndex: index,
      intent: _controllerIntent,
    );
    setState(() {
      _currentPage = index;
      _activeDisplayIndex = index;
      if (isPreviewChange) {
        _scrubPreviewDisplayIndex = index;
      }
    });
    _positionSession.markVisible(index);
    _syncRestoreTargetFromDisplayIndex(index);

    if (isPreviewChange) {
      _positionSession.updatePreview(index);
      return;
    }

    // ReadingCardDeck emits onIndexChanged only after its drag/animation has
    // settled. PageView's onPageChanged can fire mid-drag, so its durable
    // commit is deferred to ScrollEndNotification below.
    if (_usesInteractiveCardDeck) {
      _onPageSettled(index);
    }
  }

  void _onPageSettled(int index) {
    if (!mounted ||
        _positionSession.isNavigationSuspended ||
        _positionSession.isScrubbing ||
        _positionSession.hasActivePreviewPosition ||
        index != _currentPage ||
        index != _activeDisplayIndex) {
      return;
    }
    final navigationGeneration = _positionSession.navigationGeneration;
    if (_lastSettledNavigationGeneration == navigationGeneration) return;
    _lastSettledNavigationGeneration = navigationGeneration;

    final stableLocation = _committedStableLocationForDisplay(index);
    if (stableLocation == null) {
      _logVisiblePositionMutation(
        reason: 'page_settlement',
        classification: ReaderVisibleMutationClassification.synthetic,
        accepted: false,
        decisionReason: 'stable_location_unavailable',
        oldLocation: _visiblePositionCoordinator.committedLocation,
        oldLocalIndex: _positionSession.committedReadingPosition,
        newLocalIndex: index,
      );
      _restoreAuthoritativeVisibleIndex(
        'rejected_synthetic_controller_settlement',
      );
      return;
    }

    if (_syntheticControllerTargetIndex == index) {
      _syntheticControllerTargetIndex = null;
      final decision = _visiblePositionCoordinator.rejectSynthetic(
        reason: 'synthetic_controller_settlement',
      );
      _logVisiblePositionMutation(
        reason: 'controller_correction',
        classification: ReaderVisibleMutationClassification.synthetic,
        accepted: decision.accepted,
        decisionReason: decision.reason,
        oldLocation: decision.oldLocation,
        newLocation: stableLocation,
        oldLocalIndex: _positionSession.committedReadingPosition,
        newLocalIndex: index,
      );
      _restoreAuthoritativeVisibleIndex(
        'rejected_synthetic_controller_settlement',
      );
      return;
    }

    final controllerIntent = _controllerIntent;
    final ReaderVisibleMutationDecision<StableBookLocation> decision;
    final ReaderVisibleMutationClassification classification;
    if (controllerIntent != null) {
      final expectedIndex = _displayIndexForStableAnchor(
        controllerIntent.target,
      );
      if (expectedIndex != index) {
        decision = _visiblePositionCoordinator.rejectSynthetic(
          reason: 'stale_callback_does_not_match_current_explicit_intent',
        );
      } else {
        decision = _visiblePositionCoordinator.completeIntent(
          intent: controllerIntent,
          resolvedLocation: controllerIntent.target,
          windowGeneration: _rebuildGeneration,
          publicationGeneration: _progressiveRangeGeneration,
        );
      }
      if (controllerIntent.isConsumed &&
          identical(_controllerIntent, controllerIntent)) {
        _controllerIntent = null;
      }
      classification = ReaderVisibleMutationClassification.programmatic;
    } else {
      decision = _visiblePositionCoordinator.settleUser(stableLocation);
      classification = ReaderVisibleMutationClassification.user;
    }
    _logVisiblePositionMutation(
      reason: controllerIntent?.reason ?? 'user_swipe_settled',
      classification: classification,
      accepted: decision.accepted,
      decisionReason: decision.reason,
      oldLocation: decision.oldLocation,
      newLocation: decision.newLocation,
      oldLocalIndex: _positionSession.committedReadingPosition,
      newLocalIndex: index,
      intent: controllerIntent,
    );
    assert(
      decision.accepted ||
          _visiblePositionCoordinator.committedLocation == decision.oldLocation,
      'Rejected visible work must not change the authoritative stable anchor.',
    );
    if (!decision.accepted) {
      _restoreAuthoritativeVisibleIndex('rejected_visible_settlement');
      return;
    }
    if (controllerIntent != null && mounted) {
      // A target-window publication may already have rebuilt the card deck
      // with explicit-navigation gesture suppression enabled. Settlement is
      // the owner transition that must publish the enabled interaction state.
      setState(() {});
    }
    _runCommittedPageEffects(index);
  }

  void _restoreAuthoritativeVisibleIndex(String reason) {
    final anchor = _authoritativeVisibleAnchor();
    if (anchor == null) return;
    final authoritativeIndex = _displayIndexForStableAnchor(anchor);
    if (authoritativeIndex == null) return;
    final controllerIdentity = _visibleControllerIdentity;
    if (controllerIdentity == null) return;
    if (_isControllerVisiblyAtIndex(authoritativeIndex, controllerIdentity)) {
      _visiblePositionCoordinator.cancelPendingCorrection();
      return;
    }
    _visiblePositionCoordinator.requestCorrection(
      target: anchor,
      reason: reason,
      expectedWindowGeneration: _rebuildGeneration,
      expectedPublicationGeneration: _progressiveRangeGeneration,
      controllerIdentity: controllerIdentity,
    );
    _visibleCorrectionScheduler.schedule();
  }

  Object? get _visibleControllerIdentity =>
      _usesInteractiveCardDeck ? _cardDeckController : _pageController;

  bool _isControllerVisiblyAtIndex(int index, Object controllerIdentity) {
    if (_currentPage != index || _activeDisplayIndex != index) return false;
    if (_usesInteractiveCardDeck) {
      return identical(controllerIdentity, _cardDeckController);
    }
    final controller = _pageController;
    if (controller == null ||
        !identical(controller, controllerIdentity) ||
        !controller.hasClients) {
      return false;
    }
    final page = controller.page;
    return page != null && (page - index).abs() <= 0.01;
  }

  void _applyPendingVisibleCorrection(
    ReaderVisibleCorrectionIntent<StableBookLocation> correction,
  ) {
    final controllerIdentity = _visibleControllerIdentity;
    if (!mounted ||
        controllerIdentity == null ||
        !_visiblePositionCoordinator.isCurrentCorrection(
          correction,
          windowGeneration: _rebuildGeneration,
          publicationGeneration: _progressiveRangeGeneration,
          controllerIdentity: controllerIdentity,
        )) {
      if (identical(
        _visiblePositionCoordinator.pendingCorrection,
        correction,
      )) {
        _visiblePositionCoordinator.cancelPendingCorrection();
      }
      return;
    }
    final authoritativeIndex = _displayIndexForStableAnchor(correction.target);
    if (authoritativeIndex == null) {
      _visiblePositionCoordinator.cancelPendingCorrection();
      return;
    }
    if (!_isControllerVisiblyAtIndex(authoritativeIndex, controllerIdentity)) {
      _jumpToDisplayIndex(authoritativeIndex, reason: correction.reason);
    }
    _visiblePositionCoordinator.completeCorrection(correction);
  }

  void _scheduleProgrammaticPageSettlement(
    int displayIndex, [
    int attemptsRemaining = 4,
  ]) {
    if (_usesInteractiveCardDeck) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          displayIndex != _currentPage ||
          displayIndex != _activeDisplayIndex) {
        return;
      }
      final controller = _pageController;
      final page = controller?.hasClients == true ? controller!.page : null;
      if (page == null || (page - displayIndex).abs() > 0.01) {
        if (attemptsRemaining > 0) {
          _scheduleProgrammaticPageSettlement(
            displayIndex,
            attemptsRemaining - 1,
          );
        }
        return;
      }
      _onPageSettled(displayIndex);
    });
  }

  Future<bool> _waitForSettledPageAttachment(int displayIndex) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          displayIndex != _currentPage ||
          displayIndex != _activeDisplayIndex) {
        return false;
      }
      if (_usesInteractiveCardDeck) return true;
      final controller = _pageController;
      final page = controller?.hasClients == true ? controller!.page : null;
      if (page != null && (page - displayIndex).abs() <= 0.01) return true;
    }
    _readerDiagLog('navigation_settlement_timeout', {
      'book': widget.bookId,
      'displayIndex': displayIndex,
      'controllerPage': _pageController?.hasClients == true
          ? _pageController!.page
          : null,
    });
    return false;
  }

  void _scheduleReadingPositionSave(ReaderCommittedPosition position) {
    // The exact card and source ranges are captured at settlement. Canonical
    // persistence starts immediately; no correctness-critical debounce exists.
    _positionPersistenceQueue.stage(position);
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    unawaited(
      _flushPendingReadingPosition().catchError((Object error) {
        _readerDiagLog('checkpoint_commit_failure', {
          'book': widget.bookId,
          'error': error.runtimeType,
        });
      }),
    );
  }

  Future<void> _flushPendingReadingPosition() async {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    await _positionPersistenceQueue.flush(_persistCommittedPosition);
  }

  Future<void> _persistReadingPosition(int index) async {
    final position = _captureCommittedPosition(index);
    if (position == null) return;
    _positionPersistenceQueue.stage(position);
    await _flushPendingReadingPosition();
  }

  ReaderCommittedPosition? _captureCommittedPosition(int index) {
    if (index < 0 || index >= _displayToOriginal.length) return null;
    final originals = _displayToOriginal[index];
    if (originals.isEmpty) return null;
    if (!_positionSession.canCommitActiveVisiblePosition &&
        _positionSession.previewPosition == index) {
      return null;
    }

    // Only the legacy eager route may interpret its final display page as the
    // publication end. A lazy window's final card is merely a local boundary.
    final bool isLastPage =
        _lazySession == null &&
        _displayChunksComplete &&
        index == _displayToOriginal.length - 1;
    final originalIndex = isLastPage
        ? _sourceChunks.length - 1
        : originals.first;
    final stableLocation =
        (_lazySession == null
                ? _stableLocationForOriginalIndex(originalIndex)
                : _committedStableLocationForDisplay(index))
            ?.copyWith(
              localDisplayIndex: index,
              readerLayoutFingerprint: _activeReaderLayoutFingerprint,
              previousSpineIndex: _previousSpineIndexForOriginalIndex(
                originalIndex,
              ),
              nextSpineIndex: _nextSpineIndexForOriginalIndex(originalIndex),
            );
    final cardIdentity = _cardIdentityForDisplay(index);
    if (cardIdentity == null) return null;
    final navigationSource = _nextCheckpointNavigationSource;
    _nextCheckpointNavigationSource = 'page_settled';
    return ReaderCommittedPosition(
      revision: _positionRevisionClock.next(),
      displayIndex: index,
      originalIndex: originalIndex,
      location: stableLocation,
      cardIdentity: cardIdentity,
      navigationSource: navigationSource,
    );
  }

  Future<void> _persistCommittedPosition(
    ReaderCommittedPosition position,
  ) async {
    final index = position.displayIndex;
    final originalIndex = position.originalIndex;
    final stableLocation = position.location;
    final cardIdentity = position.cardIdentity;
    final coordinator = _checkpointCoordinator;
    if (coordinator == null || cardIdentity == null) return;

    final commit = await coordinator.commitCard(
      card: cardIdentity,
      stableLocation: stableLocation,
      navigationSource: position.navigationSource,
    );
    if (!commit.applied) {
      _readerDiagLog('checkpoint_commit_not_applied', {
        'book': widget.bookId,
        'status': commit.status.name,
        'candidateCardSignature': cardIdentity.signature,
        'navigationSource': position.navigationSource,
      });
      return;
    }

    final visibleIdentity = _cardIdentityForDisplay(_currentPage);
    if (visibleIdentity?.signature == cardIdentity.signature) {
      _positionSession.markCommitted(index);
    }

    // Compatibility mirrors happen only after the authoritative SQLite commit.
    if (_lazySession == null) {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setInt('last_read_${widget.bookId}', originalIndex);
    }
    final metadata = _metadataService.getMetadata(widget.bookId);
    if (metadata != null) {
      final meaningfulReadAt = DateTime.now().millisecondsSinceEpoch;
      final updated = stableLocation == null
          ? metadata.copyWith(
              lastReadIndex: _lazySession == null
                  ? originalIndex
                  : metadata.lastReadIndex,
              totalChunks: _lazySession == null
                  ? _sourceChunks.length
                  : metadata.totalChunks,
              lastReadTime: meaningfulReadAt,
              lastReadRevision: position.revision,
              lastMeaningfulReadAt: meaningfulReadAt,
            )
          : ReaderStructuralProgressService.metadataForCommittedLocation(
              metadata: metadata,
              currentStableLocation: stableLocation,
              meaningfulReadAt: meaningfulReadAt,
              revision: position.revision,
              legacyLastReadIndex: _lazySession == null ? originalIndex : null,
              legacyTotalChunks: _lazySession == null
                  ? _sourceChunks.length
                  : null,
            );
      await _metadataService.updateMetadata(updated);
      if (stableLocation != null) {
        _lazySession?.recordMeaningfulRead(stableLocation, meaningfulReadAt);
        _readerDiagLog('stable_location_saved', {
          ..._stableLocationDiagFields(stableLocation),
          'displayIndex': index,
          'originalIndex': originalIndex,
          'publicationProgression': stableLocation.publicationProgression,
        });
      } else {
        _readerDiagLog('stable_location_save_skipped', {
          'book': widget.bookId,
          'displayIndex': index,
          'originalIndex': originalIndex,
          'reason': 'missing_source_location_mapping',
        });
      }
    }
  }

  StableBookLocation? _stableLocationForOriginalIndex(
    int originalIndex, {
    int textOffset = 0,
  }) {
    final location = _sourceLocationsByChunkIndex[originalIndex];
    if (location == null) return null;
    return location.copyWith(textOffset: textOffset);
  }

  int? _previousSpineIndexForOriginalIndex(int originalIndex) {
    final current = _sourceLocationsByChunkIndex[originalIndex]?.spineIndex;
    if (current == null || current <= 0) return null;
    return current - 1;
  }

  int? _nextSpineIndexForOriginalIndex(int originalIndex) {
    final current = _sourceLocationsByChunkIndex[originalIndex]?.spineIndex;
    final session = _lazySession;
    if (current == null || session == null) return null;
    final next = current + 1;
    return next < session.index.spine.length ? next : null;
  }

  Map<String, Object?> _stableLocationDiagFields(StableBookLocation location) {
    return {
      'book': widget.bookId,
      'locationBookId': location.bookId,
      'spineIndex': location.spineIndex,
      'href': location.href,
      'sourceChecksum': location.sourceChecksum,
      'localChunkIndex': location.localChunkIndex,
      'textOffset': location.textOffset,
      'anchorId': location.anchorId,
      'legacyGlobalChunkIndex': location.legacyGlobalChunkIndex,
      'localDisplayIndex': location.localDisplayIndex,
      'hasReaderLayoutFingerprint': location.readerLayoutFingerprint != null,
      'previousSpineIndex': location.previousSpineIndex,
      'nextSpineIndex': location.nextSpineIndex,
      'context': _normalizeForAnchor(location.contextText ?? ''),
    };
  }

  // ─── Position History ──────────────────────────────────────────────────

  Future<void> _loadPositionHistory() async {
    _prefs ??= await SharedPreferences.getInstance();
    final chunk = _prefs!.getInt('pos_hist_${widget.bookId}_chunk');
    final display = _prefs!.getInt('pos_hist_${widget.bookId}_display');
    final label = _prefs!.getString('pos_hist_${widget.bookId}_label');
    final stableJson = _prefs!.getString('pos_hist_${widget.bookId}_stable');
    StableBookLocation? stableLocation;
    if (stableJson != null) {
      try {
        stableLocation = StableBookLocation.maybeFromJson(
          jsonDecode(stableJson),
        );
      } catch (_) {
        // A corrupt optional stable history record must not drop legacy fields.
      }
    }

    if (chunk != null && display != null && label != null) {
      _positionStack.clear();
      _positionStack.add(
        PositionHistory(
          chunkIndex: chunk,
          displayIndex: display,
          label: label,
          stableLocation:
              stableLocation ?? _stableLocationForOriginalIndex(chunk),
        ),
      );
    }
  }

  Future<void> _savePositionHistory() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (_positionStack.isEmpty) {
      await _prefs!.remove('pos_hist_${widget.bookId}_chunk');
      await _prefs!.remove('pos_hist_${widget.bookId}_display');
      await _prefs!.remove('pos_hist_${widget.bookId}_label');
      await _prefs!.remove('pos_hist_${widget.bookId}_stable');
    } else {
      final top = _positionStack.last;
      await _prefs!.setInt('pos_hist_${widget.bookId}_chunk', top.chunkIndex);
      await _prefs!.setInt(
        'pos_hist_${widget.bookId}_display',
        top.displayIndex,
      );
      await _prefs!.setString('pos_hist_${widget.bookId}_label', top.label);
      final stableLocation = top.stableLocation;
      if (stableLocation == null) {
        await _prefs!.remove('pos_hist_${widget.bookId}_stable');
      } else {
        await _prefs!.setString(
          'pos_hist_${widget.bookId}_stable',
          jsonEncode(stableLocation.toJson()),
        );
      }
    }
  }

  void _commitCurrentPosition() {
    _commitDisplayIndexToHistory(_currentPage);
  }

  String _buildPositionHistoryLabel(int displayIndex) {
    return 'Page ${displayIndex + 1}';
  }

  void _commitDisplayIndexToHistory(int displayIndex) {
    if (_displayChunks.isEmpty || displayIndex >= _displayChunks.length) return;

    final origIndices = _displayToOriginal[displayIndex];
    if (origIndices.isEmpty) return;
    final originalIndex = origIndices.first;
    final label = _buildPositionHistoryLabel(displayIndex);

    if (_positionStack.isNotEmpty) {
      final top = _positionStack.last;
      // Don't commit adjacent positions dynamically or exact same ones
      if (top.chunkIndex == originalIndex || top.displayIndex == displayIndex) {
        return;
      }
    }

    _positionStack.add(
      PositionHistory(
        chunkIndex: originalIndex,
        displayIndex: displayIndex,
        label: label,
        stableLocation: _stableLocationForOriginalIndex(originalIndex),
      ),
    );
    if (_positionStack.length > 5) {
      _positionStack.removeAt(0);
    }
    _savePositionHistory();
    _updatePositionHistoryNotifier();
  }

  void _updatePositionHistoryNotifier() {
    if (_positionStack.isEmpty) {
      _positionHistoryNotifier.value = null;
    } else {
      final top = _positionStack.last;
      // Only show stack top if distance is more than 2 cards
      if ((_currentPage - top.displayIndex).abs() > 2) {
        _positionHistoryNotifier.value = top;
      } else {
        _positionHistoryNotifier.value = null;
      }
    }
  }

  void _popAndGoBackToPosition() {
    if (_positionStack.isEmpty) return;
    final top = _positionStack.removeLast();
    _savePositionHistory();

    if (_lazySession != null && top.stableLocation != null) {
      unawaited(
        _navigateToStableLocation(
          top.stableLocation!,
          navigationSource: 'link_back',
        ),
      );
      _updatePositionHistoryNotifier();
      return;
    }

    // Jump to the saved position. Recalculate display index using original just in case font changed.
    final rebuiltDisplayTarget = _originalToDisplay[top.chunkIndex];
    if (rebuiltDisplayTarget == null) {
      unawaited(
        _navigateToSourceLocation(
          originalChunkIndex: top.chunkIndex,
          navigationSource: 'link_back',
        ),
      );
      _updatePositionHistoryNotifier();
      return;
    }
    final targetDIndex = rebuiltDisplayTarget;

    _clearPreviewState(visibleDisplayIndex: targetDIndex);
    _jumpReaderToPage(targetDIndex);
    _lastDwellPage = targetDIndex; // Reset anchor baseline to destination
    // Explicitly update notifier immediately so the chip disappears or updates
    _updatePositionHistoryNotifier();
  }

  // ─── Internal link navigation ────────────────────────────────────────

  void _onLinkTap(String url) {
    final parsed = _parseInternalLinkTarget(url);
    final anchor = parsed.fragment;
    final originalIndex = anchor == null ? null : _sourceAnchorMap[anchor];
    if (originalIndex != null) {
      _commitCurrentPosition();
      unawaited(
        _navigateToSourceLocation(
          originalChunkIndex: originalIndex,
          navigationSource: 'link',
        ),
      );
      return;
    }

    final session = _lazySession;
    if (session != null) {
      final targetHref = parsed.href ?? _currentStableLocation()?.href;
      if (targetHref != null) {
        final target = session.resolveAnchor(targetHref, anchor);
        if (target != null) {
          _commitCurrentPosition();
          _readerDiagLog('lazy_internal_link_target', {
            'book': widget.bookId,
            'url': url,
            'href': target.href,
            'fragment': target.anchorId,
            'spineIndex': target.spineIndex,
          });
          unawaited(
            _navigateToStableLocation(target, navigationSource: 'link'),
          );
          return;
        }
      }
    }

    _readerDiagLog('internal_link_target_missing', {
      'book': widget.bookId,
      'url': url,
      'anchor': anchor,
      'href': parsed.href,
    });
    if (kDebugMode) {
      debugPrint('Anchor not found: $url');
    }
  }

  ({String? href, String? fragment}) _parseInternalLinkTarget(String url) {
    final uri = Uri.tryParse(url);
    final path = uri?.path.isNotEmpty == true ? uri!.path : null;
    final fragment = uri?.fragment.isNotEmpty == true
        ? Uri.decodeComponent(uri!.fragment)
        : null;
    if (path != null || fragment != null) {
      return (href: path, fragment: fragment);
    }

    final hashIndex = url.indexOf('#');
    if (hashIndex == -1) {
      return (href: url.isEmpty ? null : url, fragment: null);
    }
    final href = url.substring(0, hashIndex);
    final rawFragment = url.substring(hashIndex + 1);
    return (
      href: href.isEmpty ? null : href,
      fragment: rawFragment.isEmpty ? null : Uri.decodeComponent(rawFragment),
    );
  }

  // ─── Overlay toggle ──────────────────────────────────────────────────

  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) {
      _lastInsightDisplayIndex = null;
      _lastInsightStartedAt = null;
      // Auto-pause speed read when opening the menu (only if currently playing)
      if (_speedReadController.isActive && !_speedReadController.isPaused) {
        _speedReadController.pause();
        _speedReadAutoPaused = true;
      }
      _overlayAnimController.forward();
    } else {
      // Resume speed read if it was auto-paused by the menu opening
      if (_speedReadAutoPaused &&
          _speedReadController.isActive &&
          _speedReadController.isPaused) {
        _speedReadAutoPaused = false;
        _resumeAutoPausedSpeedReadIfReady();
      }
      _lastInsightDisplayIndex = _currentPage;
      _lastInsightStartedAt = DateTime.now();
      _overlayAnimController.reverse();
    }
    unawaited(_syncNativeReaderControlsState());
  }

  void _handleReaderContentTap(Offset? globalPosition) {
    if (_positionSession.hasActivePreviewPosition &&
        !_positionSession.isScrubbing) {
      _promotePreviewToCommitted();
    }
    _toggleOverlay();
  }

  bool _isReaderViewportTapSuppressed(int generation) {
    if (_readerViewportTapSuppressedGeneration != generation) return false;
    final suppressedUntil = _readerViewportTapSuppressedUntil;
    return suppressedUntil != null && DateTime.now().isBefore(suppressedUntil);
  }

  void _suppressReaderMenuTapThisFrame() {
    _readerViewportTapSuppressedGeneration = _readerViewportTapGeneration;
    _readerViewportTapSuppressedUntil = DateTime.now().add(
      const Duration(milliseconds: 200),
    );
  }

  void _handleReaderViewportPointerDown(PointerDownEvent event) {
    _pauseNonessentialReaderWork('viewport_pointer_down');
    _readerViewportTapGeneration++;
    _readerViewportPointer = event.pointer;
    _readerViewportPointerDownPosition = event.position;
    _readerViewportPointerMoved = false;
    _readerViewportPointerHeld = false;
    _readerViewportDeferredTapTimer?.cancel();
    _readerViewportDeferredTapTimer = null;
    _readerViewportLongPressTimer?.cancel();
    _readerViewportLongPressTimer = Timer(kLongPressTimeout, () {
      _readerViewportPointerHeld = true;
    });
  }

  void _handleReaderViewportPointerMove(PointerMoveEvent event) {
    if (_readerViewportPointer != event.pointer) return;
    final downPosition = _readerViewportPointerDownPosition;
    if (downPosition != null &&
        (event.position - downPosition).distance > kTouchSlop) {
      _readerViewportPointerMoved = true;
    }
  }

  void _finishReaderViewportPointerTracking() {
    _readerViewportLongPressTimer?.cancel();
    _readerViewportLongPressTimer = null;
    _scheduleLazyParsedHydration();
    _scheduleDerivedIndexWhenQuiet();
  }

  void _handleReaderViewportPointerUp(PointerUpEvent event) {
    if (_readerViewportPointer != event.pointer) return;
    final downPosition = _readerViewportPointerDownPosition;
    _finishReaderViewportPointerTracking();
    if (downPosition == null) return;
    if (_readerViewportPointerMoved) return;
    if (_readerViewportPointerHeld) return;
    if ((event.position - downPosition).distance > kTouchSlop) return;
    if (_cardInteractionBlocked) return;

    _scheduleReaderViewportTap(
      generation: _readerViewportTapGeneration,
      pointer: event.pointer,
      globalPosition: event.position,
    );
  }

  void _scheduleReaderViewportTap({
    required int generation,
    required int pointer,
    required Offset globalPosition,
  }) {
    _readerViewportDeferredTapTimer?.cancel();
    _readerViewportDeferredTapTimer = Timer(
      const Duration(milliseconds: 60),
      () {
        if (!mounted) return;
        if (_readerViewportTapGeneration != generation) return;
        if (_readerViewportPointer != pointer) return;
        if (_readerViewportTapHandledGeneration == generation) return;
        if (_isReaderViewportTapSuppressed(generation)) return;
        if (_readerViewportPointerMoved) return;
        if (_readerViewportPointerHeld) return;
        if (_cardInteractionBlocked) return;

        _readerViewportTapHandledGeneration = generation;
        _handleReaderContentTap(globalPosition);
      },
    );
  }

  void _handleReadingCardTapOutside(Offset? globalPosition) {
    final generation = _readerViewportTapGeneration;
    if (_readerViewportTapHandledGeneration == generation) return;
    if (_isReaderViewportTapSuppressed(generation)) return;
    _readerViewportTapHandledGeneration = generation;
    _handleReaderContentTap(globalPosition);
  }

  // ─── Bookmark actions ────────────────────────────────────────────────

  ({int chunkIndex, int originalStartOffset, String? previewText})?
  _bookmarkAnchorForDisplayPage(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= _displayChunks.length) {
      return null;
    }

    final chunk = _displayChunks[displayIndex];
    final ranges =
        chunk.effectiveSourceRanges
            .where(
              (range) => range.originalStartOffset < range.originalEndOffset,
            )
            .toList()
          ..sort(
            (a, b) => a.displayStartOffset.compareTo(b.displayStartOffset),
          );

    if (ranges.isNotEmpty) {
      final topRange = ranges.first;
      return (
        chunkIndex: topRange.originalChunkIndex,
        originalStartOffset: topRange.originalStartOffset,
        previewText: _bookmarkPreviewText(chunk.text),
      );
    }

    if (displayIndex >= _displayToOriginal.length) return null;
    final originals = _displayToOriginal[displayIndex];
    if (originals.isEmpty) return null;
    return (
      chunkIndex: originals.first,
      originalStartOffset: 0,
      previewText: _bookmarkPreviewText(chunk.text),
    );
  }

  String? _bookmarkPreviewText(String? text) {
    final collapsed = text?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed == null || collapsed.isEmpty) return null;
    if (collapsed.length <= 180) return collapsed;
    return '${collapsed.substring(0, 180).trimRight()}...';
  }

  Bookmark? _bookmarkForPublishedSourceAnchor(
    int chunkIndex,
    int originalStartOffset, {
    List<Bookmark>? bookmarks,
  }) {
    for (final bookmark in bookmarks ?? _bookmarks) {
      final projected = resolveReaderBookmarksForSourceWindow(
        bookmarks: <Bookmark>[bookmark],
        sourceChunks: _publishedSourceChunks,
        locationsByChunkIndex: _publishedSourceLocationsByChunkIndex,
        sourceIdentitiesByChunkIndex: _publishedSourceIdentitiesByChunkIndex,
      );
      if (projected.length == 1 &&
          projected.single.isSameLocation(chunkIndex, originalStartOffset)) {
        return bookmark;
      }
    }
    return null;
  }

  int? _displayIndexForBookmark(Bookmark bookmark) {
    final projected = resolveReaderBookmarksForSourceWindow(
      bookmarks: <Bookmark>[bookmark],
      sourceChunks: _publishedSourceChunks,
      locationsByChunkIndex: _publishedSourceLocationsByChunkIndex,
      sourceIdentitiesByChunkIndex: _publishedSourceIdentitiesByChunkIndex,
    );
    if (projected.length != 1) return null;
    final resolved = projected.single;
    return _displayIndexForSourceLocation(
      originalChunkIndex: resolved.chunkIndex,
      originalStartOffset: resolved.originalStartOffset,
      sourceText: resolved.previewText,
    );
  }

  int get _defaultBookmarkFixedIndex =>
      defaultBookmarkColorIndex(_defaultBookmarkColor) ?? 0;

  int? get _defaultBookmarkCustomColorValue =>
      defaultBookmarkColorIndex(_defaultBookmarkColor) == null
      ? bookmarkColorValue(_defaultBookmarkColor)
      : null;

  Future<void> _onBookmarkTap(int displayIndex) async {
    final anchor = _bookmarkAnchorForDisplayPage(displayIndex);
    if (anchor == null) return;

    final bookmarked = _bookmarkForPublishedSourceAnchor(
      anchor.chunkIndex,
      anchor.originalStartOffset,
    );

    if (bookmarked != null) {
      // Unbookmark
      final updated = await _bookmarkService.removeBookmark(bookmarked);
      setState(() {
        _bookmarks = updated;
        _bookmarkDisplayHints.remove(readerBookmarkProjectionKey(bookmarked));
      });
    } else {
      final stableLocation =
          _publishedSourceLocationsByChunkIndex[anchor.chunkIndex]?.copyWith(
            textOffset: anchor.originalStartOffset,
          );
      final updated = await _bookmarkService.add(
        anchor.chunkIndex,
        originalStartOffset: anchor.originalStartOffset,
        previewText: anchor.previewText,
        colorIndex: _defaultBookmarkFixedIndex,
        colorValue: _defaultBookmarkCustomColorValue,
        stableLocation: stableLocation,
      );
      final added = _bookmarkForPublishedSourceAnchor(
        anchor.chunkIndex,
        anchor.originalStartOffset,
        bookmarks: updated,
      );
      setState(() {
        _bookmarks = updated;
        if (added != null) {
          _bookmarkDisplayHints[readerBookmarkProjectionKey(added)] =
              displayIndex;
        }
      });
    }
  }

  Future<void> _onBookmarkLongPress(int displayIndex) async {
    final anchor = _bookmarkAnchorForDisplayPage(displayIndex);
    if (anchor == null) return;

    final bookmark = _bookmarkForPublishedSourceAnchor(
      anchor.chunkIndex,
      anchor.originalStartOffset,
    );
    if (bookmark == null) return;

    _showRenameDialog(bookmark);
  }

  Future<void> _onTripleTap(int displayIndex) async {
    final anchor = _bookmarkAnchorForDisplayPage(displayIndex);
    if (anchor == null) return;

    // Ensure bookmark exists
    var bookmark = _bookmarkForPublishedSourceAnchor(
      anchor.chunkIndex,
      anchor.originalStartOffset,
    );
    if (bookmark == null) {
      final stableLocation =
          _publishedSourceLocationsByChunkIndex[anchor.chunkIndex]?.copyWith(
            textOffset: anchor.originalStartOffset,
          );
      final updated = await _bookmarkService.add(
        anchor.chunkIndex,
        originalStartOffset: anchor.originalStartOffset,
        previewText: anchor.previewText,
        colorIndex: _defaultBookmarkFixedIndex,
        colorValue: _defaultBookmarkCustomColorValue,
        stableLocation: stableLocation,
      );
      final added = _bookmarkForPublishedSourceAnchor(
        anchor.chunkIndex,
        anchor.originalStartOffset,
        bookmarks: updated,
      );
      setState(() {
        _bookmarks = updated;
        if (added != null) {
          _bookmarkDisplayHints[readerBookmarkProjectionKey(added)] =
              displayIndex;
        }
      });
      bookmark = added;
    }

    if (bookmark == null) return;
    await _showRenameDialog(bookmark);
  }

  Future<void> _showRenameDialog(Bookmark bookmark) async {
    final result = await _runWithReaderControlsSuspended(() {
      return showDialog<BookmarkEditResult>(
        context: context,
        builder: (_) => BookmarkEditDialog(
          initialName: bookmark.name,
          initialColor: bookmark.color,
          sharedPalette: _highlightPalette,
          settings: _settings,
          onAddCustomColor: _onAddCustomHighlightColor,
          onRemoveCustomColor: _onRemoveCustomHighlightColor,
          onResetPalette: _onResetHighlightPalette,
        ),
      );
    });

    if (result == null) return;

    final selectedColor = Color(bookmarkColorValue(result.color));
    final fixedIndex = defaultBookmarkColorIndex(selectedColor);
    await _bookmarkService.saveDefaultColor(selectedColor);

    final updated = await _bookmarkService.updateBookmark(
      bookmark,
      newName: result.name,
      colorIndex: fixedIndex ?? bookmark.colorIndex,
      colorValue: fixedIndex == null ? bookmarkColorValue(selectedColor) : null,
      clearColorValue: fixedIndex != null,
    );
    setState(() {
      _bookmarks = updated;
      _defaultBookmarkColor = selectedColor;
      _defaultBookmarkColorIndex = fixedIndex ?? 0;
    });
  }

  // ─── Highlights ────────────────────────────────────────────────────────

  Future<void> _onQuoteShareRequested(
    int displayIndex,
    int startOffset,
    int endOffset,
    String text,
  ) async {
    if (_isOpeningQuoteShare ||
        !mounted ||
        displayIndex < 0 ||
        displayIndex >= _displayChunks.length ||
        text.isEmpty) {
      return;
    }

    final frozenText = text;

    final metadata = _metadataService.getMetadata(widget.bookId);
    final title = metadata?.title.trim().isNotEmpty == true
        ? metadata!.title
        : widget.title;

    late final QuoteSharePayload payload;
    try {
      payload = buildReaderQuoteSharePayload(
        selectedText: frozenText,
        bookTitle: title,
        author: metadata?.author ?? '',
        bookId: widget.bookId,
        displayIndex: displayIndex,
        coverImagePath: metadata?.coverImagePath,
        fontFamily: _settings.fontFamily,
        startOffset: startOffset,
        endOffset: endOffset,
      );
    } on ArgumentError {
      return;
    }

    if (_speedReadController.isActive) {
      _speedReadController.pause();
    }

    final navigator = Navigator.of(context);
    _isOpeningQuoteShare = true;
    try {
      await _runWithReaderControlsSuspended(() {
        return navigator.push(buildReaderQuoteShareRoute(payload));
      });
    } finally {
      _isOpeningQuoteShare = false;
    }
  }

  Future<void> _openBookImageViewer(int displayIndex) async {
    if (displayIndex < 0 || displayIndex >= _displayChunks.length) return;

    final chunk = _displayChunks[displayIndex];
    final imageBytes = chunk.imageBytes;
    if (chunk.type != BookChunkType.image ||
        imageBytes == null ||
        imageBytes.isEmpty) {
      return;
    }

    final shouldResumeSpeedRead =
        _speedReadController.isActive && !_speedReadController.isPaused;
    if (shouldResumeSpeedRead) {
      _speedReadController.pause();
    }

    final metadata = _metadataService.getMetadata(widget.bookId);
    final bookTitle = metadata?.title.trim().isNotEmpty == true
        ? metadata!.title
        : widget.title;
    final author = metadata?.author ?? '';
    final imageLabel = 'Image ${displayIndex + 1}';

    try {
      await _runWithReaderControlsSuspended(() {
        return Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => BookImageViewerScreen(
              imageBytes: imageBytes,
              bookTitle: bookTitle,
              author: author,
              bookId: widget.bookId,
              imageLabel: imageLabel,
              fontFamily: _settings.fontFamily,
            ),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      });
    } finally {
      if (mounted &&
          shouldResumeSpeedRead &&
          _speedReadController.isActive &&
          _speedReadController.isPaused &&
          !_overlayVisible) {
        _speedReadController.resume();
      }
    }
  }

  Future<void> _onHighlightCreated(
    int displayIndex,
    int startOffset,
    int endOffset,
    String _,
    Color color,
    HighlightType type, [
    String? note,
  ]) async {
    if (displayIndex < 0 || displayIndex >= _displayChunks.length) return;

    final displayChunk = _displayChunks[displayIndex];
    final translatedRanges = displayChunk.mapDisplayRangeToOriginal(
      startOffset,
      endOffset,
    );
    await _saveMappedHighlight(
      translatedRanges: translatedRanges,
      color: color,
      type: type,
      note: note,
    );
  }

  Future<void> _onMappedNoteCreated(
    List<MappedTextRange> mappedRanges,
    String _,
    Color color,
    String note,
  ) async {
    await _saveMappedHighlight(
      translatedRanges: mappedRanges,
      color: color,
      type: HighlightType.highlight,
      note: note,
    );
  }

  Future<void> _saveMappedHighlight({
    required List<MappedTextRange> translatedRanges,
    required Color color,
    required HighlightType type,
    String? note,
  }) async {
    if (translatedRanges.isEmpty) return;
    final sourceSegments = readerMappedSourceSegments(
      ranges: translatedRanges,
      sourceChunks: _publishedSourceChunks,
    );
    if (sourceSegments.length != translatedRanges.length) return;

    final trimmedNote = note?.trim();
    final isNoteBackedHighlight =
        type == HighlightType.highlight &&
        trimmedNote != null &&
        trimmedNote.isNotEmpty;

    if (isNoteBackedHighlight) {
      Set<String>? exactMatchingIds;
      for (final segment in sourceSegments) {
        final range = segment.range;
        final matchingIds = <String>{};
        for (final highlight in _highlights) {
          final isExactMatch =
              highlight.type == HighlightType.highlight &&
              highlight.originalChunkIndex == range.originalChunkIndex &&
              highlight.startOffset == range.originalStartOffset &&
              highlight.endOffset == range.originalEndOffset;
          if (isExactMatch) {
            matchingIds.add(highlight.id);
          }
        }
        exactMatchingIds = exactMatchingIds == null
            ? matchingIds
            : exactMatchingIds.intersection(matchingIds);
        if (exactMatchingIds.isEmpty) break;
      }

      final existingHighlightId =
          exactMatchingIds != null && exactMatchingIds.length == 1
          ? exactMatchingIds.single
          : null;

      if (existingHighlightId != null) {
        final updatedList = await _highlightService.updateNote(
          existingHighlightId,
          trimmedNote,
        );
        setState(() => _highlights = updatedList);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Note saved'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    final annotationLabel = switch (type) {
      HighlightType.highlight => 'highlight',
      HighlightType.character => 'character mark',
      HighlightType.note => 'note',
    };
    final hasOverlap = sourceSegments.any(
      (segment) => _highlights.any(
        (hl) =>
            hl.originalChunkIndex == segment.range.originalChunkIndex &&
            hl.type == type &&
            (segment.range.originalStartOffset < hl.endOffset &&
                segment.range.originalEndOffset > hl.startOffset),
      ),
    );

    if (hasOverlap) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('This text already has a $annotationLabel.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red[700],
          ),
        );
      }
      return;
    }

    final createdAt = DateTime.now();
    final normalizedColor = Color(highlightColorValue(color));
    final highlightId = '${createdAt.microsecondsSinceEpoch}';
    List<Highlight> updated = _highlights;
    for (final segment in sourceSegments) {
      final range = segment.range;
      final newHighlight = Highlight(
        id: highlightId,
        originalChunkIndex: range.originalChunkIndex,
        startOffset: range.originalStartOffset,
        endOffset: range.originalEndOffset,
        text: segment.text,
        colorIndex: defaultHighlightColorIndex(normalizedColor) ?? 0,
        colorValue: highlightColorValue(normalizedColor),
        type: type,
        note: trimmedNote,
        createdAt: createdAt,
        stableLocation:
            _publishedSourceLocationsByChunkIndex[range.originalChunkIndex]
                ?.copyWith(textOffset: range.originalStartOffset),
      );
      updated = await _highlightService.add(newHighlight);
    }
    setState(() => _highlights = updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (type) {
            HighlightType.highlight => 'Highlight saved',
            HighlightType.character => 'Character mark saved',
            HighlightType.note => 'Note saved',
          }),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _onNoteUpdated(String id, String note) async {
    final updatedList = await _highlightService.updateNote(id, note);
    setState(() => _highlights = updatedList);
  }

  Future<void> _onNoteRemoved(String id) async {
    Highlight? target;
    for (final highlight in _highlights) {
      if (highlight.id == id) {
        target = highlight;
        break;
      }
    }
    if (target == null) return;

    final updatedList = await _highlightService.remove(id);
    setState(() => _highlights = updatedList);
  }

  Future<void> _onHighlightColorChange(Highlight highlight, Color color) async {
    final normalizedColor = Color(highlightColorValue(color));
    final updatedhl = highlight.copyWith(
      colorIndex:
          defaultHighlightColorIndex(normalizedColor) ?? highlight.colorIndex,
      colorValue: highlightColorValue(normalizedColor),
    );
    final updatedList = await _highlightService.update(updatedhl);
    setState(() => _highlights = updatedList);
  }

  Future<void> _onHighlightDeleted(String id) async {
    final updatedList = await _highlightService.remove(id);
    setState(() => _highlights = updatedList);
  }

  void _onDefaultHighlightColorChanged(Color color) {
    final normalized = Color(highlightColorValue(color));
    unawaited(_highlightPaletteService.saveDefaultColor(normalized));
    setState(() => _defaultHighlightColor = normalized);
  }

  Future<List<Color>> _onAddCustomHighlightColor(Color color) async {
    final normalized = Color(highlightColorValue(color));
    final updatedPalette = await _highlightPaletteService.addCustomColor(
      normalized,
    );
    if (mounted) {
      setState(() {
        _highlightPalette = updatedPalette;
      });
    }
    return updatedPalette;
  }

  Future<List<Color>> _onRemoveCustomHighlightColor(Color color) async {
    final updatedPalette = await _highlightPaletteService.removeColor(color);
    var nextDefaultColor = _defaultHighlightColor;
    if (!_paletteContainsColor(updatedPalette, nextDefaultColor)) {
      nextDefaultColor = _fallbackHighlightColor(updatedPalette);
      await _highlightPaletteService.saveDefaultColor(nextDefaultColor);
    }

    if (mounted) {
      setState(() {
        _highlightPalette = updatedPalette;
        _defaultHighlightColor = Color(highlightColorValue(nextDefaultColor));
      });
    }

    return updatedPalette;
  }

  Future<List<Color>> _onResetHighlightPalette() async {
    final updatedPalette = await _highlightPaletteService.resetPalette();
    var nextDefaultColor = _defaultHighlightColor;
    if (!_paletteContainsColor(updatedPalette, nextDefaultColor)) {
      nextDefaultColor = _fallbackHighlightColor(updatedPalette);
      await _highlightPaletteService.saveDefaultColor(nextDefaultColor);
    }

    if (mounted) {
      setState(() {
        _highlightPalette = updatedPalette;
        _defaultHighlightColor = Color(highlightColorValue(nextDefaultColor));
      });
    }

    return updatedPalette;
  }

  List<ReaderCharacterSourceRange> _readerCharacterSourceRanges() {
    if (identical(_characterMatchHighlights, _highlights) &&
        identical(_characterMatchSourceChunks, _publishedSourceChunks)) {
      return _characterSourceRanges;
    }
    final plan = buildReaderCharacterMatchPlan(
      highlights: _highlights,
      sourceChunks: _publishedSourceChunks,
    );
    _characterMatchHighlights = _highlights;
    _characterMatchSourceChunks = _publishedSourceChunks;
    _characterSourceRanges = matchReaderCharacterSourceRanges(
      plan: plan,
      sourceChunks: _publishedSourceChunks,
    );
    return _characterSourceRanges;
  }

  String _buildStorageLocationLabel(int originalChunkIndex) {
    final displayIdx = _originalToDisplay[originalChunkIndex];
    final pageNumber = (displayIdx ?? originalChunkIndex) + 1;

    String? chapterTitle;
    for (final chapter in _flatChapters) {
      if (chapter.chunkIndex <= originalChunkIndex) {
        chapterTitle = chapter.title.trim();
      } else {
        break;
      }
    }

    if (chapterTitle != null && chapterTitle.isNotEmpty) {
      return 'Page $pageNumber from $chapterTitle';
    }

    return 'Page $pageNumber';
  }

  String _displayPageTotalLabel() {
    return _displayChunksComplete
        ? '${_displayChunks.length}'
        : '${_displayChunks.length}+';
  }

  String _positionSummaryLabel(int displayIndex) {
    if (_lazySession != null) {
      final location = _currentStableLocation();
      if (location != null) {
        return _titleForSpineIndex(location.spineIndex);
      }
      return 'Preparing pages';
    }
    return 'Page ${displayIndex + 1} of ${_displayPageTotalLabel()}';
  }

  // ─── Navigation ──────────────────────────────────────────────────────

  void _navigateTo(
    int targetIndex, {
    bool exploratory = false,
    String navigationSource = 'programmatic',
    StableBookLocation? targetLocation,
    ReaderVisibleNavigationIntent<StableBookLocation>? navigationIntent,
  }) {
    _markForegroundReaderWork('navigate_to_page');
    if (exploratory) {
      if (_currentPage != targetIndex) {
        if (!_positionSession.hasActivePreviewPosition) {
          _commitCurrentPosition();
        }
        _positionSession.startPreview(_currentPage);
        _jumpReaderToPage(targetIndex, asPreview: true);
        _positionSession.finishScrub();
        _schedulePreviewPromotion(targetIndex);
      }
      return;
    }
    _clearPreviewState(visibleDisplayIndex: _currentPage);
    _nextCheckpointNavigationSource = navigationSource;
    _jumpReaderToPage(
      targetIndex,
      reason: navigationSource,
      targetLocation: targetLocation,
      navigationIntent: navigationIntent,
    );
    _scheduleProgrammaticPageSettlement(targetIndex);
  }

  Future<void> _openSearchScreen() async {
    await _flushReadingSession();
    if (!mounted) return;
    final target = await _runWithReaderControlsSuspended(() {
      return Navigator.push<DerivedSourceRange>(
        context,
        MaterialPageRoute(
          builder: (_) => SearchScreen(
            chunks: _sourceChunks,
            searchIndex: _sourceSearchIndex,
            stableLocationsByChunkIndex: _sourceLocationsByChunkIndex,
            derivedIndexSession: _derivedIndexSession,
            initialSettings: _settings,
          ),
        ),
      );
    });
    if (mounted) {
      _startReadingSession();
    }

    if (target != null) {
      unawaited(
        _navigateToStableLocation(
          target.location,
          navigationSource: 'search',
          transientSearchRange: target,
        ),
      );
    }
  }

  Future<void> _openAnnotationsPanel() async {
    // Build a lookup map from original chunk index → text for previews
    final chunkTexts = <int, String>{};
    for (final chunk in _sourceChunks) {
      if (chunk.text != null && chunk.text!.isNotEmpty) {
        chunkTexts[chunk.index] = chunk.text!;
      }
    }

    await _runWithReaderControlsSuspended(() {
      return AnnotationsPanel.show(
        context,
        currentPage: _currentPage,
        originalToDisplay: _originalToDisplay,
        totalDisplayPages: _displayChunks.length,
        chunkTexts: chunkTexts,
        buildLocationLabel: _buildStorageLocationLabel,
        onNavigate:
            (
              originalIndex, {
              int? originalStartOffset,
              String? sourceText,
              StableBookLocation? stableLocation,
            }) {
              if (stableLocation != null) {
                _readerDiagLog('annotation_stable_navigation', {
                  ..._stableLocationDiagFields(stableLocation),
                  'legacyOriginalIndex': originalIndex,
                  'originalStartOffset': originalStartOffset,
                  'sourceText': sourceText,
                });
                unawaited(
                  _navigateToStableLocation(
                    stableLocation.copyWith(
                      textOffset:
                          originalStartOffset ?? stableLocation.textOffset,
                      contextText: sourceText ?? stableLocation.contextText,
                    ),
                    navigationSource: 'annotation',
                  ),
                );
                return;
              }
              unawaited(
                _navigateAndMigrateLegacyAnnotation(
                  originalChunkIndex: originalIndex,
                  originalStartOffset: originalStartOffset,
                  sourceText: sourceText,
                ),
              );
            },
        highlights: _highlights,
        onRemoveHighlight: (id) async {
          final updated = await _highlightService.remove(id);
          setState(() => _highlights = updated);
        },
        onChangeHighlightColor: _onHighlightColorChange,
        highlightPalette: _highlightPalette,
        onAddCustomColor: _onAddCustomHighlightColor,
        onRemoveCustomColor: _onRemoveCustomHighlightColor,
        onResetHighlightPalette: _onResetHighlightPalette,
        onNoteUpdated: _onNoteUpdated,
        onNoteRemoved: _onNoteRemoved,
        dictionaryService: _dictionaryService,
        settings: _settings,
        initialTab: _lastAnnotationsTab,
        onTabChanged: _rememberAnnotationsTab,
      );
    });
  }

  String get _readerDrawerLastTabKey =>
      'nalori.book.${widget.bookId}$_readerDrawerLastTabKeySuffix';

  AnnotationPanelTab? _annotationPanelTabFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final tab in AnnotationPanelTab.values) {
      if (tab.name == name) return tab;
    }
    return null;
  }

  void _rememberAnnotationsTab(AnnotationPanelTab tab) {
    if (_lastAnnotationsTab == tab) return;
    _lastAnnotationsTab = tab;
    final prefs = _prefs;
    if (prefs != null) {
      unawaited(prefs.setString(_readerDrawerLastTabKey, tab.name));
      return;
    }
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString(_readerDrawerLastTabKey, tab.name),
      ),
    );
  }

  Future<void> _showPageJumpDialog() async {
    if (_displayChunks.isEmpty) return;

    if (_lazySession != null) {
      final session = _lazySession;
      final title = session == null
          ? 'Book sections'
          : _titleForSpineIndex(_currentStableLocation()?.spineIndex ?? 0);
      await _runWithReaderControlsSuspended(() {
        return showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _settings.backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: _settings.textColor.withValues(alpha: 0.2),
              ),
            ),
            title: Text(
              'Jump by Chapter',
              style: TextStyle(color: _settings.textColor),
            ),
            content: Text(
              'Exact page numbers are available after full pagination. Use the book scrubber or chapter list to jump across the whole book. Current section: $title.',
              style: TextStyle(
                color: _settings.mutedColor,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: TextStyle(color: _settings.textColor),
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_showChapterPanel());
                },
                style: FilledButton.styleFrom(
                  backgroundColor: _settings.accentColor,
                  foregroundColor: AppUi.foregroundFor(_settings.accentColor),
                ),
                child: const Text('Open Chapters'),
              ),
            ],
          ),
        );
      });
      return;
    }

    final controller = TextEditingController(text: '${_currentPage + 1}');
    String? errorText;
    final pageTotalLabel = _displayPageTotalLabel();

    await _runWithReaderControlsSuspended(() {
      return showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: _settings.backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _settings.textColor.withValues(alpha: 0.2),
                ),
              ),
              title: Text(
                'Jump to Page',
                style: TextStyle(color: _settings.textColor),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter an available page between 1 and $pageTotalLabel.',
                    style: TextStyle(
                      color: _settings.mutedColor,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: _settings.textColor),
                    decoration: InputDecoration(
                      labelText: 'Page number',
                      labelStyle: TextStyle(color: _settings.mutedColor),
                      errorText: errorText,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _settings.mutedColor.withValues(alpha: 0.5),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _settings.textColor),
                      ),
                      errorBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.redAccent),
                      ),
                      focusedErrorBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    onSubmitted: (_) {
                      final requestedPage = int.tryParse(
                        controller.text.trim(),
                      );
                      if (requestedPage == null ||
                          requestedPage < 1 ||
                          requestedPage > _displayChunks.length) {
                        setLocalState(() {
                          errorText =
                              'Choose an available page from 1 to $pageTotalLabel.';
                        });
                        return;
                      }

                      Navigator.pop(ctx);
                      _navigateTo(requestedPage - 1);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: _settings.textColor),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final requestedPage = int.tryParse(controller.text.trim());
                    if (requestedPage == null ||
                        requestedPage < 1 ||
                        requestedPage > _displayChunks.length) {
                      setLocalState(() {
                        errorText =
                            'Choose an available page from 1 to $pageTotalLabel.';
                      });
                      return;
                    }

                    Navigator.pop(ctx);
                    _navigateTo(requestedPage - 1);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _settings.accentColor,
                    foregroundColor: AppUi.foregroundFor(_settings.accentColor),
                  ),
                  child: const Text('Go'),
                ),
              ],
            );
          },
        ),
      );
    });
  }

  void _commitScrubSelection(int targetIndex) {
    final previousIndex = _scrubStartDisplayIndex;
    final previewAlreadyVisible = _currentPage == targetIndex;

    setState(() {
      _isScrubbing = false;
      _scrubPreviewDisplayIndex = null;
      _scrubStartDisplayIndex = null;
    });

    if (previousIndex == null) return;

    if (previousIndex == targetIndex) {
      _clearPreviewState(visibleDisplayIndex: targetIndex);
      _lastDwellPage = targetIndex;
      _scheduleDwellTracking(targetIndex);
      _updatePositionHistoryNotifier();
      return;
    }

    _commitDisplayIndexToHistory(previousIndex);
    _lastDwellPage = targetIndex;
    _nextCheckpointNavigationSource = 'scrubber';
    _clearPreviewState(visibleDisplayIndex: targetIndex);

    if (previewAlreadyVisible) {
      _onPageSettled(targetIndex);
      return;
    }

    _jumpReaderToPage(targetIndex);
    _scheduleProgrammaticPageSettlement(targetIndex);
  }

  void _commitLazyStructuralScrub(double progression) {
    final committedProgression = _lazyStructuralScrubPolicy.commit(progression);
    if (committedProgression == null) return;
    final session = _lazySession;
    if (session == null) return;
    setState(() {
      _isScrubbing = false;
      _lazyScrubPreviewSpineIndex = null;
    });
    _commitCurrentPosition();
    _nextCheckpointNavigationSource = 'scrubber';
    unawaited(
      _navigateToStableLocation(
        session.locationForWeightedProgression(committedProgression),
        navigationSource: 'scrubber',
      ),
    );
  }

  Widget _buildLazyStructuralScrubber() {
    final session = _lazySession;
    if (session == null) return _buildPageScrubber(const []);
    final spineCount = math.max(1, session.index.spine.length);
    final currentSpine =
        _lazyScrubPreviewSpineIndex ??
        _currentStableLocation()?.spineIndex ??
        0;
    final currentItem =
        session.index.spine[currentSpine.clamp(0, spineCount - 1).toInt()];
    final totalWeight = session.index.totalReadableWeight;
    final stableProgression = _lazyScrubPreviewSpineIndex == null
        ? _currentStableLocation()?.publicationProgression
        : null;
    final value = stableProgression != null
        ? stableProgression.clamp(0.0, 1.0)
        : totalWeight <= 0
        ? (spineCount <= 1 ? 0.0 : currentSpine / (spineCount - 1))
        : (currentItem.prefixWeight / totalWeight).clamp(0.0, 1.0);
    final markRatios =
        _flatChapterInfos
            .map((chapter) => chapter.stableLocation?.spineIndex)
            .whereType<int>()
            .map((spine) {
              if (totalWeight <= 0) {
                return spineCount <= 1 ? 0.0 : spine / (spineCount - 1);
              }
              return (session.index.spine[spine].prefixWeight / totalWeight)
                  .clamp(0.0, 1.0);
            })
            .toSet()
            .toList()
          ..sort();
    final previewSpine = _lazyScrubPreviewSpineIndex ?? currentSpine;
    final currentTitle = _titleForSpineIndex(previewSpine);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          currentTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _settings.textColor,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Book scrubber',
          value: currentTitle,
          hint: 'Adjust to jump to another chapter or section',
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              trackShape: _ChapterMarksTrackShape(markRatios: markRatios),
              thumbShape: const _PillSliderThumbShape(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: _settings.accentColor,
              inactiveTrackColor: _settings.mutedColor.withValues(alpha: 0.24),
              thumbColor: _settings.accentColor,
              overlayColor: _settings.accentColor.withValues(alpha: 0.15),
            ),
            child: Slider(
              divisions: 100,
              value: value,
              onChangeStart: (start) {
                _dwellTimer?.cancel();
                _cancelPreviewPromotionTimer();
                _lazyStructuralScrubPolicy.begin(start);
                setState(() {
                  _isScrubbing = true;
                  _lazyScrubPreviewSpineIndex = currentSpine;
                });
              },
              onChanged: (next) {
                _lazyStructuralScrubPolicy.update(next);
                final target = session
                    .locationForWeightedProgression(next)
                    .spineIndex;
                if (_lazyScrubPreviewSpineIndex == target) return;
                setState(() => _lazyScrubPreviewSpineIndex = target);
              },
              onChangeEnd: _commitLazyStructuralScrub,
            ),
          ),
        ),
      ],
    );
  }

  String _titleForSpineIndex(int spineIndex) {
    ChapterInfo? best;
    for (final chapter in _flatChapterInfos) {
      final location = chapter.stableLocation;
      if (location == null) continue;
      if (location.spineIndex <= spineIndex) {
        best = chapter;
      } else {
        break;
      }
    }
    final title = best?.title.trim();
    if (title != null && title.isNotEmpty) return title;
    final session = _lazySession;
    if (session != null &&
        spineIndex >= 0 &&
        spineIndex < session.index.spine.length) {
      return session.index.spine[spineIndex].href;
    }
    return 'Book position';
  }

  Widget _buildPageScrubber(List<double> markRatios) {
    final maxPage = (_displayChunks.length - 1).clamp(0, 1 << 30);
    final displayedPage = _scrubPreviewDisplayIndex ?? _currentPage;
    final sliderValue = displayedPage
        .toDouble()
        .clamp(0, maxPage.toDouble())
        .toDouble();
    final ratio = maxPage > 0 ? sliderValue / maxPage : 0.0;
    const bubbleWidth = 76.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleLeft = ((constraints.maxWidth - bubbleWidth) * ratio).clamp(
          0.0,
          (constraints.maxWidth - bubbleWidth).clamp(0.0, double.infinity),
        );

        return SizedBox(
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (_scrubPreviewDisplayIndex != null)
                Positioned(
                  top: -32,
                  left: bubbleLeft,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _settings.isDark
                            ? Colors.black.withValues(alpha: 0.92)
                            : Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _settings.textColor.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: bubbleWidth,
                        height: 28,
                        child: Center(
                          child: Text(
                            'Page ${displayedPage + 1}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _settings.textColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Semantics(
                label: 'Page scrubber',
                value:
                    'Page ${displayedPage + 1} of ${_displayPageTotalLabel()}',
                hint: 'Adjust to jump to another page',
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    trackShape: _ChapterMarksTrackShape(markRatios: markRatios),
                    thumbShape: const _PillSliderThumbShape(),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    activeTrackColor: _settings.accentColor,
                    inactiveTrackColor: _settings.mutedColor.withValues(
                      alpha: 0.24,
                    ),
                    thumbColor: _settings.accentColor,
                    overlayColor: _settings.accentColor.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    max: maxPage.toDouble(),
                    divisions: maxPage > 0 ? maxPage : null,
                    value: sliderValue,
                    onChangeStart: (_) {
                      _dwellTimer?.cancel();
                      _cancelPreviewPromotionTimer();
                      _positionSession.startPreview(
                        _currentPage,
                        scrubbing: true,
                      );
                      setState(() {
                        _isScrubbing = true;
                        _scrubStartDisplayIndex = _currentPage;
                        _scrubPreviewDisplayIndex = _currentPage;
                      });
                    },
                    onChanged: (val) {
                      final targetIndex = val.round();
                      if (_scrubPreviewDisplayIndex == targetIndex) return;

                      setState(() {
                        _scrubPreviewDisplayIndex = targetIndex;
                      });
                      _positionSession.updatePreview(targetIndex);

                      if (_currentPage != targetIndex) {
                        _jumpReaderToPage(targetIndex, asPreview: true);
                      }
                    },
                    onChangeEnd: (val) {
                      _commitScrubSelection(val.round());
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────

  int _sourceWordCountForDisplayIndex(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= _displayChunks.length) return 0;
    final displayChunk = _displayChunks[displayIndex];
    final ranges = displayChunk.effectiveSourceRanges;
    if (ranges.isEmpty) {
      return readerLayoutWordCount(displayChunk.text ?? '');
    }

    var total = 0;
    for (final range in ranges) {
      final source = _chunkByOriginalIndex(range.originalChunkIndex);
      final text = source?.text;
      if (text == null || text.isEmpty) continue;
      final start = range.originalStartOffset.clamp(0, text.length).toInt();
      final end = range.originalEndOffset.clamp(0, text.length).toInt();
      if (start >= end) continue;
      total += readerLayoutWordCount(text.substring(start, end));
    }
    return total;
  }

  BookChunk? _chunkByOriginalIndex(int originalIndex) {
    if (originalIndex >= 0 &&
        originalIndex < _sourceChunks.length &&
        _sourceChunks[originalIndex].index == originalIndex) {
      return _sourceChunks[originalIndex];
    }
    for (final chunk in _sourceChunks) {
      if (chunk.index == originalIndex) return chunk;
    }
    return null;
  }

  int _sourceWordCountForOriginalRange(int startIndex, int endExclusive) {
    var total = 0;
    for (final chunk in _sourceChunks) {
      if (chunk.index < startIndex || chunk.index >= endExclusive) continue;
      if (chunk.type != BookChunkType.text) continue;
      if (chunk.section != ChunkSection.content) continue;
      total += readerLayoutWordCount(chunk.text ?? '');
    }
    return total;
  }

  List<_AnalyticsChapter> _buildAnalyticsChapters() {
    final flat = _flatChapters
        .where((chapter) => chapter.chunkIndex >= 0)
        .toList();
    if (flat.isEmpty || _sourceChunks.isEmpty) {
      return const [];
    }

    final byStart = <int, String>{};
    for (final chapter in flat) {
      byStart.putIfAbsent(chapter.chunkIndex, () => chapter.title.trim());
    }
    final starts = byStart.keys.toList()..sort();
    final chapters = <_AnalyticsChapter>[];
    for (int i = 0; i < starts.length; i++) {
      final start = starts[i].clamp(0, _sourceChunks.length - 1).toInt();
      final end = i + 1 < starts.length
          ? starts[i + 1].clamp(0, _sourceChunks.length).toInt()
          : _sourceChunks.length;
      if (end <= start) continue;
      final title = byStart[starts[i]]?.isNotEmpty == true
          ? byStart[starts[i]]!
          : 'Chapter ${chapters.length + 1}';
      final id = '${chapters.length}_$start';
      chapters.add(
        _AnalyticsChapter(
          id: id,
          title: title,
          startChunkIndex: start,
          endChunkIndex: end,
          wordCount: _sourceWordCountForOriginalRange(start, end),
        ),
      );
    }
    return chapters;
  }

  Future<void> _ensureInsightChaptersRegistered() async {
    if (_hasRegisteredInsightChapters || !_settings.readingInsightsEnabled) {
      return;
    }
    _analyticsChapters = _buildAnalyticsChapters();
    if (_analyticsChapters.isEmpty) return;
    _hasRegisteredInsightChapters = true;
    await _statsService.registerBookInsightChapters(
      bookId: widget.bookId,
      chapters: {
        for (final chapter in _analyticsChapters)
          chapter.id: ReadingChapterStats(
            id: chapter.id,
            title: chapter.title,
            wordCount: chapter.wordCount,
          ),
      },
    );
  }

  String? _chapterIdForOriginalIndex(int originalIndex) {
    if (_analyticsChapters.isEmpty) {
      _analyticsChapters = _buildAnalyticsChapters();
    }
    for (final chapter in _analyticsChapters) {
      if (originalIndex >= chapter.startChunkIndex &&
          originalIndex < chapter.endChunkIndex) {
        return chapter.id;
      }
    }
    return null;
  }

  int get _remainingInsightSourceWords {
    if (_displayToOriginal.isEmpty ||
        _currentPage >= _displayToOriginal.length) {
      return 0;
    }
    final originals = _displayToOriginal[_currentPage];
    if (originals.isEmpty) return 0;
    final currentOriginal = originals.reduce(math.max);
    return _sourceWordCountForOriginalRange(
      currentOriginal + 1,
      _sourceChunks.length,
    );
  }

  ({String title, String timeLeft})? _readingInsightParts() {
    if (!_settings.readingInsightsEnabled) return null;
    if (_analyticsChapters.isEmpty) {
      _analyticsChapters = _buildAnalyticsChapters();
    }
    final currentOriginals =
        _currentPage >= 0 && _currentPage < _displayToOriginal.length
        ? _displayToOriginal[_currentPage]
        : const <int>[];
    final currentOriginal = currentOriginals.isEmpty
        ? 0
        : currentOriginals.reduce(math.max);
    final chapterId = _chapterIdForOriginalIndex(currentOriginal);
    final chapter = _analyticsChapters.cast<_AnalyticsChapter?>().firstWhere(
      (entry) => entry?.id == chapterId,
      orElse: () => null,
    );
    final remainingWords = chapter == null
        ? _remainingInsightSourceWords
        : _sourceWordCountForOriginalRange(
            currentOriginal + 1,
            chapter.endChunkIndex,
          );
    if (remainingWords <= 0) return null;
    final duration = _statsService.estimateTimeLeft(
      bookId: widget.bookId,
      remainingWords: remainingWords,
    );
    final confidence = _statsService.getBookInsights(widget.bookId).confidence;
    final prefix = confidence == ReadingPaceConfidence.high ? '' : '~';
    return (
      title: chapter?.title ?? 'Current chapter',
      timeLeft: '$prefix${ReadingStatsService.formatDuration(duration)} left',
    );
  }

  String? _completionReadingTimeLabel() {
    final insights = _statsService.getBookInsights(widget.bookId);
    final seconds = insights.completedReadingSeconds ?? insights.activeSeconds;
    if (seconds <= 0) return null;
    return 'Finished in ${ReadingStatsService.formatDuration(Duration(seconds: seconds))}';
  }

  /// Flatten the hierarchical chapter list into a sorted list of
  /// (originalChunkIndex, title) pairs for sequential navigation.
  /// Cached to avoid recomputing on every access (called 5+ times per page change).
  List<({int chunkIndex, String title})> get _flatChapters {
    if (_cachedFlatChapters != null) return _cachedFlatChapters!;
    final flat = <({int chunkIndex, String title})>[];
    void walk(List<ChapterInfo> chapters) {
      for (final ch in chapters) {
        flat.add((chunkIndex: ch.chunkIndex, title: ch.title));
        if (ch.children.isNotEmpty) walk(ch.children);
      }
    }

    walk(_sourceChapters);
    flat.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    _cachedFlatChapters = flat;
    return flat;
  }

  List<ChapterInfo> get _flatChapterInfos {
    final flat = <ChapterInfo>[];
    void walk(List<ChapterInfo> chapters) {
      for (final ch in chapters) {
        flat.add(ch);
        if (ch.children.isNotEmpty) walk(ch.children);
      }
    }

    walk(_sourceChapters);
    if (_lazySession != null) {
      flat.sort((a, b) {
        final aLoc = a.stableLocation;
        final bLoc = b.stableLocation;
        if (aLoc != null && bLoc != null) {
          final stable = _compareStableLocations(aLoc, bLoc);
          if (stable != 0) return stable;
        }
        return a.chunkIndex.compareTo(b.chunkIndex);
      });
    } else {
      flat.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    }
    return flat;
  }

  List<ChapterNavigationTarget> get _chapterNavigationTargets {
    return ChapterNavigationService.buildTargets(
      chapters: _sourceChapters,
      anchorMap: _sourceAnchorMap,
      locationsByChunkIndex: _sourceLocationsByChunkIndex,
    );
  }

  int _compareStableLocations(StableBookLocation a, StableBookLocation b) {
    final spine = a.spineIndex.compareTo(b.spineIndex);
    if (spine != 0) return spine;
    final chunk = (a.localChunkIndex ?? 0).compareTo(b.localChunkIndex ?? 0);
    if (chunk != 0) return chunk;
    return a.textOffset.compareTo(b.textOffset);
  }

  /// Find the index in _flatChapters that the current display page belongs to.
  /// Returns -1 if the current position is before the first chapter.
  int _currentChapterFlatIndex() {
    if (_displayChunks.isEmpty || _sourceChapters.isEmpty) return -1;

    // Guard: during rebuilds _currentPage may exceed the new list length
    if (_currentPage >= _displayToOriginal.length) return -1;

    // Get the original chunk index for the current display page
    final origIndices = _displayToOriginal[_currentPage];
    if (origIndices.isEmpty) return -1;
    final currentOriginal = origIndices.first;

    final flat = _flatChapters;
    int chapterIdx = -1;
    for (int i = 0; i < flat.length; i++) {
      if (flat[i].chunkIndex <= currentOriginal) {
        chapterIdx = i;
      } else {
        break;
      }
    }
    return chapterIdx;
  }

  /// Jump to the previous chapter. Returns the chapter title, or null if
  /// already at/before the first chapter.
  String? _jumpToPrevChapter() {
    _readerDiagLog('chapter_jump_invoked', {
      'book': widget.bookId,
      'direction': 'previous',
      'hasLazySession': _lazySession != null,
      'currentPage': _currentPage,
      'currentSpineIndex': _currentStableLocation()?.spineIndex,
      'activeWindowBounds': _activeLazyWindowBoundsLabel(),
    });
    if (_lazySession != null) {
      final current = _currentStableLocation();
      if (current == null) {
        _readerDiagLog('chapter_jump_resolved', {
          'book': widget.bookId,
          'direction': 'previous',
          'resolved': false,
          'reason': 'missing_current_location',
          'currentPage': _currentPage,
          'currentChapterIndex': -1,
        });
        return null;
      }
      final targets = _chapterNavigationTargets;
      final currentChIdx = ChapterNavigationService.currentTargetIndex(
        targets,
        current,
      );
      _readerDiagLog('chapter_jump_resolve_started', {
        'book': widget.bookId,
        'direction': 'previous',
        'currentPage': _currentPage,
        'currentChapterIndex': currentChIdx,
        'flatChapterCount': targets.length,
        ..._stableLocationDiagFieldsWithPrefix('current', current),
      });
      final target = ChapterNavigationService.previousTarget(targets, current);
      if (target == null) {
        _readerDiagLog('chapter_jump_resolved', {
          'book': widget.bookId,
          'direction': 'previous',
          'resolved': false,
          'currentPage': _currentPage,
          'currentChapterIndex': currentChIdx,
          ..._stableLocationDiagFieldsWithPrefix('current', current),
        });
        return null;
      }
      final targetLocation = target.stableLocation;
      _readerDiagLog('chapter_jump_resolved', {
        'book': widget.bookId,
        'direction': 'previous',
        'resolved': true,
        'currentPage': _currentPage,
        'currentChapterIndex': currentChIdx,
        'targetChapterIndex': targets.indexOf(target),
        'targetTitle': target.title,
        ..._stableLocationDiagFieldsWithPrefix('current', current),
        ..._stableLocationDiagFieldsWithPrefix('target', targetLocation),
      });
      unawaited(
        _navigateToStableLocation(targetLocation, navigationSource: 'chapter'),
      );
      return target.title;
    }

    final flat = _flatChapters;
    if (flat.isEmpty) return null;

    final currentChIdx = _currentChapterFlatIndex();
    final targetIdx = (currentChIdx <= 0) ? -1 : currentChIdx - 1;

    if (targetIdx < 0) {
      _readerDiagLog('chapter_jump_resolved', {
        'book': widget.bookId,
        'direction': 'previous',
        'resolved': false,
        'branch': 'legacy',
        'currentPage': _currentPage,
        'currentChapterIndex': currentChIdx,
      });
      return null;
    }

    final target = flat[targetIdx];
    _readerDiagLog('chapter_jump_resolved', {
      'book': widget.bookId,
      'direction': 'previous',
      'resolved': true,
      'branch': 'legacy',
      'currentPage': _currentPage,
      'currentChapterIndex': currentChIdx,
      'targetChapterIndex': targetIdx,
      'targetTitle': target.title,
      'targetChunkIndex': target.chunkIndex,
    });
    final displayIdx = _originalToDisplay[target.chunkIndex];
    if (displayIdx != null) {
      _navigateTo(displayIdx, navigationSource: 'chapter');
      return target.title;
    }
    unawaited(
      _navigateToSourceLocation(
        originalChunkIndex: target.chunkIndex,
        navigationSource: 'chapter',
      ),
    );
    return target.title;
  }

  /// Jump to the next chapter. Returns the chapter title, or null if
  /// already at/past the last chapter.
  String? _jumpToNextChapter() {
    if (_lazySession != null) {
      final current = _currentStableLocation();
      if (current == null) return null;
      final target = ChapterNavigationService.nextTarget(
        _chapterNavigationTargets,
        current,
      );
      if (target == null) return null;
      unawaited(
        _navigateToStableLocation(
          target.stableLocation,
          navigationSource: 'chapter',
        ),
      );
      return target.title;
    }

    final flat = _flatChapters;
    if (flat.isEmpty) return null;

    final currentChIdx = _currentChapterFlatIndex();
    final targetIdx = currentChIdx + 1;

    if (targetIdx >= flat.length) return null;

    final target = flat[targetIdx];
    final displayIdx = _originalToDisplay[target.chunkIndex];
    if (displayIdx != null) {
      _navigateTo(displayIdx, navigationSource: 'chapter');
      return target.title;
    }
    unawaited(
      _navigateToSourceLocation(
        originalChunkIndex: target.chunkIndex,
        navigationSource: 'chapter',
      ),
    );
    return target.title;
  }

  /// Get info about adjacent chapters for displaying on the arrows.
  ({String? prevTitle, String? nextTitle}) _getAdjacentChapterTitles() {
    if (_lazySession != null) {
      final current = _currentStableLocation();
      if (current == null) return (prevTitle: null, nextTitle: null);
      final targets = _chapterNavigationTargets;
      final prevTitle = ChapterNavigationService.previousTarget(
        targets,
        current,
      )?.title;
      final nextTitle = ChapterNavigationService.nextTarget(
        targets,
        current,
      )?.title;
      return (prevTitle: prevTitle, nextTitle: nextTitle);
    }

    final flat = _flatChapters;
    if (flat.isEmpty) return (prevTitle: null, nextTitle: null);

    final currentChIdx = _currentChapterFlatIndex();

    final prevTitle = (currentChIdx > 0) ? flat[currentChIdx - 1].title : null;
    final nextTitle = (currentChIdx + 1 < flat.length)
        ? flat[currentChIdx + 1].title
        : null;

    return (prevTitle: prevTitle, nextTitle: nextTitle);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      if (widget.directContinueFile != null) {
        return _buildDirectContinuePreparing();
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final directFailure = _directOpenFailure;
    if (directFailure != null && _sourceChunks.isEmpty) {
      return _buildDirectContinueError(directFailure);
    }

    if (_directOpenInProgress && _sourceChunks.isEmpty) {
      return _buildDirectContinuePreparing();
    }

    if (_sourceChunks.isNotEmpty) {
      final screenSize = MediaQuery.sizeOf(context);
      final safeArea = MediaQuery.viewPaddingOf(context);
      final textScaler = MediaQuery.textScalerOf(context);
      _ensureDisplayChunksBuilt(screenSize, safeArea, textScaler);
      if (_hasCompletedDisplayChunkBuild && _displayChunks.isNotEmpty) {
        unawaited(_ensureInsightChaptersRegistered());
      }
    }

    final initialPreparationFailure = _progressiveRangeFailure;
    if (_displayChunks.isEmpty && initialPreparationFailure != null) {
      return _buildReaderPreparationError(initialPreparationFailure);
    }

    // Show loading indicator while display chunks are being built/loaded.
    // Avoid showing the empty-book state before the first async layout pass
    // has finished; that caused a split-second false empty screen on launch.
    if (readerShouldShowFullPreparingPages(
      hasPublishedReadableContent:
          _navigationPublicationCoordinator.hasPublishedReadableContent,
      hasDisplayChunks: _displayChunks.isNotEmpty,
      hasSourceChunks: _sourceChunks.isNotEmpty,
      isPreparing: _isRebuildingChunks || !_hasCompletedDisplayChunkBuild,
    )) {
      return Scaffold(
        backgroundColor: _settings.backgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _settings.mutedColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Preparing pages…',
                style: TextStyle(color: _settings.mutedColor, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_displayChunks.isEmpty) {
      return Scaffold(
        backgroundColor: _settings.backgroundColor,
        body: Center(
          child: Text(
            'No readable content found in this book.',
            style: TextStyle(color: _settings.textColor),
          ),
        ),
      );
    }

    unawaited(_maybeShowReaderGestureHint());

    final bgColor = _settings.backgroundColor;

    // Guard: during rebuilds _pageController may not yet be initialised
    if (_pageController == null) {
      return Scaffold(
        backgroundColor: _settings.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final speedReadAllowsManualNavigation =
        !_speedReadController.isActive ||
        _settings.speedReadPageAdvanceMode == SpeedReadPageAdvanceMode.manual;
    final renderHighlights = resolveReaderHighlightsForSourceWindow(
      highlights: _highlights,
      locationsByChunkIndex: _publishedSourceLocationsByChunkIndex,
      sourceChunks: _publishedSourceChunks,
      sourceIdentitiesByChunkIndex: _publishedSourceIdentitiesByChunkIndex,
    );
    final transientRange = _transientSearchRange;
    if (transientRange != null) {
      renderHighlights.addAll(
        buildTransientSearchHighlights(
          range: transientRange,
          sourceChunks: _publishedSourceChunks,
        ),
      );
    }
    final renderBookmarks = resolveReaderBookmarksForSourceWindow(
      bookmarks: _bookmarks,
      sourceChunks: _publishedSourceChunks,
      locationsByChunkIndex: _publishedSourceLocationsByChunkIndex,
      sourceIdentitiesByChunkIndex: _publishedSourceIdentitiesByChunkIndex,
    );
    final characterSourceRanges = _readerCharacterSourceRanges();
    final cardBoundaryEvidence = <int, ReaderPublishedCardBoundaryEvidence>{
      for (var i = 0; i < _displayChunks.length; i++)
        if (_publishedBoundaryEvidenceForDisplay(i) case final evidence?)
          i: evidence,
    };

    final body = Stack(
      children: [
        // ── PageView (always present) ──
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handleReaderViewportPointerDown,
            onPointerMove: _handleReaderViewportPointerMove,
            onPointerUp: _handleReaderViewportPointerUp,
            onPointerCancel: (_) => _finishReaderViewportPointerTracking(),
            child: _ReaderPageView(
              speedReadController: _speedReadController,
              cardDeckController: _cardDeckController,
              activeDisplayIndex: _activeDisplayIndex,
              pageController: _pageController!,
              displayChunks: _displayChunks,
              layoutContract: _activeReaderLayoutContract,
              resolvedLayouts: _resolvedDisplayLayouts,
              displayToOriginal: _displayToOriginal,
              originalToDisplay: _originalToDisplay,
              flatChapters: _flatChapters,
              chapterNavigationTargets: _chapterNavigationTargets,
              chapterBoundaryCompletedDisplayIndexes:
                  _displayIndexesReachingChapterBoundary(),
              cardBoundaryEvidence: cardBoundaryEvidence,
              completeChapterCardLayout: _currentChapterCardLayout,
              sourceLocationsByChunkIndex:
                  _publishedSourceLocationsByChunkIndex,
              displayChunksComplete: _displayChunksComplete,
              allowWindowExactFallback: _lazySession == null,
              canSwipe:
                  !_overlayVisible &&
                  speedReadAllowsManualNavigation &&
                  _readerSurfaceBlockCount == 0 &&
                  !_cardInteractionBlocked &&
                  !_isPreparingTargetRange &&
                  !_visiblePositionCoordinator.isGestureSuppressed &&
                  !_isCelebrationVisible,
              canRequestPreviousBoundary:
                  _progressiveDisplayState?.hasUnavailableBefore == true ||
                  _lazyHasContentBeforeOutsideLoadedWindow(),
              onPreviousBoundaryRequested: () => _previousReaderPage(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              ),
              settings: _settings,
              bookmarkService: _bookmarkService,
              bookmarks: renderBookmarks,
              bookmarkDisplayHints: _bookmarkDisplayHints,
              onPageChanged: _onPageChanged,
              onPageSettled: _onPageSettled,
              onLinkTap: _onLinkTap,
              onDoubleTap: _onBookmarkTap,
              onTripleTap: _onTripleTap,
              onBookmarkLongPress: _onBookmarkLongPress,
              onImageTap: _openBookImageViewer,
              highlights: renderHighlights,
              characterSourceRanges: characterSourceRanges,
              onHighlightCreated: _onHighlightCreated,
              onQuoteShareRequested: _onQuoteShareRequested,
              onMappedNoteCreated: _onMappedNoteCreated,
              onHighlightColorChange: _onHighlightColorChange,
              onHighlightDeleted: _onHighlightDeleted,
              onNoteUpdated: _onNoteUpdated,
              onNoteRemoved: _onNoteRemoved,
              onNoteEditorRoute: _runWithReaderPositionPreserved,
              highlightPalette: _highlightPalette,
              defaultHighlightColor: _defaultHighlightColor,
              onDefaultHighlightColorChanged: _onDefaultHighlightColorChanged,
              onAddCustomHighlightColor: _onAddCustomHighlightColor,
              onRemoveCustomHighlightColor: _onRemoveCustomHighlightColor,
              onResetHighlightPalette: _onResetHighlightPalette,
              defaultBookmarkColorIndex: _defaultBookmarkColorIndex,
              onDefaultBookmarkColorChanged: (idx) {
                setState(() => _defaultBookmarkColorIndex = idx);
              },
              onDictionaryLookup: _lookupWord,
              onCardInteractionBlockedChanged: (blocked) {
                if (_cardInteractionBlocked == blocked) return;
                setState(() => _cardInteractionBlocked = blocked);
                if (blocked &&
                    _speedReadController.isActive &&
                    !_speedReadController.isPaused) {
                  _speedReadController.pause();
                  _speedReadCardInteractionAutoPaused = true;
                } else if (!blocked && _speedReadCardInteractionAutoPaused) {
                  _speedReadCardInteractionAutoPaused = false;
                  _resumeAutoPausedSpeedReadIfReady();
                }
              },
              onTapOutside: _handleReadingCardTapOutside,
              onSuppressParentReaderTap: _suppressReaderMenuTapThisFrame,
            ),
          ),
        ),

        // ── Top menu placeholder ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_overlayVisible,
            child: _buildTopMenu(),
          ),
        ),

        // ── Bottom menu (scrubber + navigation) ──
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_overlayVisible,
            child: _buildBottomMenu(),
          ),
        ),

        // ── Floating speed-read pause/play button ──
        if (_speedReadController.isActive && !_overlayVisible)
          Positioned(
            right: 20,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            child: _SpeedReadFAB(
              controller: _speedReadController,
              onTap: () {
                if (_speedReadController.isPageComplete &&
                    _currentPage < _displayChunks.length - 1) {
                  _nextReaderPage(
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOutCubic,
                  );
                  return;
                }
                if (_speedReadController.isPaused) {
                  _clearSpeedReadAutoPauseFlags();
                  _speedReadController.resume();
                } else {
                  _clearSpeedReadAutoPauseFlags();
                  _speedReadController.pause();
                }
              },
            ),
          ),

        if (_showReaderGestureHint) _buildReaderGestureHint(),

        if (readerShouldShowPreparationStatus(
          failure: _progressiveRangeFailure,
        ))
          _buildProgressiveBoundaryStatus(),

        // ── Book completion celebration overlay ──
        if (_isAtPublicationEndForCompletion() &&
            _isCelebrationVisible &&
            _displayChunks.isNotEmpty)
          Positioned.fill(
            child: BookCompletionOverlay(
              bookTitle: widget.title,
              readingTimeLabel: _settings.readingInsightsEnabled
                  ? _completionReadingTimeLabel()
                  : null,
              paceLabel: _settings.readingInsightsEnabled
                  ? '${_statsService.estimatedWpmForBook(widget.bookId)} WPM'
                  : null,
              onDismiss: () {
                setState(() {
                  _isCelebrationVisible = false;
                });
                unawaited(_syncNativeReaderControlsState());
              },
              onGoToLibrary: () {
                setState(() {
                  _isCelebrationVisible = false;
                });
                unawaited(_setNativeReaderControls(readerVisible: false));
                Navigator.pop(context); // Exit reader back to list
              },
            ),
          ),
      ],
    );

    return PopScope(
      canPop: _routePopReady,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_flushAndPopReaderRoute());
      },
      child: Theme(
        data: AppUi.readerTheme(_settings),
        child: Transform.scale(
          scale: _liveScale,
          child: Scaffold(
            backgroundColor: bgColor,
            resizeToAvoidBottomInset: false,
            body: body,
          ),
        ),
      ),
    );
  }

  // ─── Top Menu ──────────────────────────────────────────

  Timer? _settingsDebounceTimer;

  Widget _buildReaderGestureHint() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _settings.menuColor.withValues(alpha: 0.96),
          borderRadius: AppUi.cardRadius(AppUi.radiusMd),
          border: Border.all(
            color: _settings.mutedColor.withValues(alpha: 0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: _settings.isDark ? 0.28 : 0.12,
              ),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.swipe_vertical_rounded,
                size: 22,
                color: _settings.accentColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reading gestures',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _settings.textColor,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Swipe up or down for pages. Tap once for controls. Select text for dictionary, notes, highlights, and quote cards.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _settings.mutedColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: _dismissReaderGestureHint,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: _settings.mutedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressiveBoundaryStatus() {
    final failure = _progressiveRangeFailure;
    const label = 'Could not prepare that range';
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 18,
      child: IgnorePointer(
        ignoring: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _settings.menuColor.withValues(alpha: 0.96),
            borderRadius: AppUi.cardRadius(AppUi.radiusMd),
            border: Border.all(
              color: _settings.mutedColor.withValues(alpha: 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: _settings.isDark ? 0.28 : 0.12,
                ),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: _settings.mutedColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _settings.textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: failure == null
                      ? null
                      : () {
                          final retry = _progressiveFailureRetry;
                          _progressiveRangeFailure = null;
                          _progressiveFailureRetry = null;
                          if (retry != null) {
                            retry();
                            return;
                          }
                          final failed =
                              _progressiveDisplayState?.failedRequest;
                          if (failed == null) return;
                          unawaited(
                            _prepareProgressiveDisplayRange(
                              direction: failed.direction,
                              sourceRange: failed.sourceRange,
                              reason: 'retry_failed_range',
                              targetOriginalIndex: failed.targetOriginalIndex,
                              targetTextOffset: failed.targetTextOffset,
                            ),
                          );
                        },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSettingsUpdate(ReadingSettings updated) {
    final generation = ++_settingsUpdateGeneration;
    // Every request starts its pending-checkpoint write immediately. SQLite
    // serializes those writes, while the generation checks below prevent an
    // older callback from applying or publishing after a newer request.
    final operation = _applySettingsUpdate(updated, generation);
    _settingsUpdateTail = operation;
    return operation;
  }

  Future<void> _saveSettingsOrdered(ReadingSettings settings) {
    final operation = _settingsSaveTail
        .catchError((_) {})
        .then((_) => _settingsService.saveSettings(settings));
    _settingsSaveTail = operation;
    return operation;
  }

  Future<void> _applySettingsUpdate(
    ReadingSettings updated,
    int settingsGeneration,
  ) async {
    final old = _settings;
    final pagingAxisChanged = old.pagingAxis != updated.pagingAxis;
    if (old.speedReadWPM != updated.speedReadWPM) {
      _speedReadController.setWPM(updated.speedReadWPM);
    }
    if (old.speedReadAdaptivePacing != updated.speedReadAdaptivePacing) {
      _speedReadController.setAdaptivePacing(updated.speedReadAdaptivePacing);
    }

    // Persist preset reader themes directly back into BookMetadata. Custom
    // reader themes live in ReadingSettings so app-wide UI theming stays clean.
    final metadata = _metadataService.getMetadata(widget.bookId);
    final metadataTheme = updated.useCustomReaderTheme
        ? null
        : updated.readerTheme;
    if (metadata != null && metadata.theme != metadataTheme) {
      _metadataService.updateMetadata(
        metadata.copyWith(
          theme: metadataTheme,
          clearTheme: metadataTheme == null,
        ),
      );
    }

    // ── Smooth transition: check if we need a full chunk rebuild ──
    final needsRebuild = readerSettingsRequireDisplayChunkRebuild(old, updated);
    if (needsRebuild) {
      final coordinator = _checkpointCoordinator;
      if (coordinator != null && coordinator.current != null) {
        final targetLayoutFingerprint = _layoutFingerprintForCurrentViewport(
          updated,
        );
        final token = await coordinator.beginLayoutTransition(
          targetLayoutFingerprint: targetLayoutFingerprint,
          targetLayoutSettings: updated.toPresetJson(),
          navigationSource: 'layout_settings_changed',
        );
        if (token == null) {
          _readerDiagLog('layout_transition_persist_failed', {
            'book': widget.bookId,
            'targetLayoutFingerprint': targetLayoutFingerprint,
          });
          return;
        }
        if (settingsGeneration != _settingsUpdateGeneration) return;
        _activeCheckpointLayoutToken = token;
      }
      // The target settings are durable before pagination begins. A pending
      // checkpoint can therefore resume this exact target after termination.
      await _saveSettingsOrdered(updated);
      if (settingsGeneration != _settingsUpdateGeneration) return;
      _cancelChapterCardLayoutWork(clearPublished: true);
      // The visible card may preview the new style during the debounce, but
      // work measured for the old style must become unpublishable immediately.
      _displayGenerationCoordinator.cancelActive(
        'layout_settings_changed_before_debounce',
      );
      _rebuildGeneration = -1;
      _progressiveRangeGeneration++;
      _progressiveDisplayState?.cancelActiveRequests();
    }

    if (!needsRebuild) {
      // Alignment, theme, paging controls, and blue light do not need
      // chunk regeneration.
      final oldController = pagingAxisChanged ? _pageController : null;
      if (pagingAxisChanged) {
        _syntheticControllerTargetIndex = _currentPage;
        _logVisiblePositionMutation(
          reason: 'paging_axis_controller_reattach',
          classification: ReaderVisibleMutationClassification.synthetic,
          accepted: true,
          decisionReason: 'controller_reattached_at_committed_anchor',
          oldLocation: _visiblePositionCoordinator.committedLocation,
          newLocation: _visiblePositionCoordinator.committedLocation,
          oldLocalIndex: _currentPage,
          newLocalIndex: _currentPage,
        );
      }
      setState(() {
        _settings = updated;
        if (pagingAxisChanged) {
          _pageController = PageController(
            initialPage: _currentPage,
            keepPage: false,
          );
        }
      });
      if (oldController != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      }
      await _saveSettingsOrdered(updated);
      if (settingsGeneration != _settingsUpdateGeneration) return;
      unawaited(_syncNativeReaderControlsState());
      return;
    }

    // Full rebuild needed — save position first (including text anchor)
    if (_displayChunks.isNotEmpty && _currentPage < _displayChunks.length) {
      final currentChunk = _displayChunks[_currentPage];
      _positionAnchor = _buildPageAnchor(currentChunk);
      _hasPendingSettingsRestore = true;

      if (_displayToOriginal.isNotEmpty &&
          _currentPage < _displayToOriginal.length &&
          _displayToOriginal[_currentPage].isNotEmpty) {
        _targetOriginalCandidates = List<int>.from(
          _displayToOriginal[_currentPage],
        );
        _targetOriginalIndex = _targetOriginalCandidates.first;
      } else {
        _targetOriginalCandidates = const [];
      }
      _targetProgressRatio = _currentPage / _displayChunks.length;
    }

    // Instantly update settings so ReadingCard previews the new style
    // Also reset liveScale to 1.0 if it was set (slider released)
    final oldController = pagingAxisChanged ? _pageController : null;
    if (pagingAxisChanged) {
      _syntheticControllerTargetIndex = _currentPage;
      _logVisiblePositionMutation(
        reason: 'layout_reflow_controller_reattach',
        classification: ReaderVisibleMutationClassification.synthetic,
        accepted: true,
        decisionReason: 'controller_reattached_pending_anchor_reflow',
        oldLocation: _authoritativeVisibleAnchor(),
        newLocation: _authoritativeVisibleAnchor(),
        oldLocalIndex: _currentPage,
        newLocalIndex: _currentPage,
      );
    }
    setState(() {
      _settings = updated;
      _liveScale = 1.0;
      if (pagingAxisChanged) {
        _pageController = PageController(
          initialPage: _currentPage,
          keepPage: false,
        );
      }
    });
    if (oldController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
    }
    unawaited(_syncNativeReaderControlsState());

    // Debounce the heavy layout recalculation
    _settingsDebounceTimer?.cancel();
    _settingsDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _lastScreenSize = null;
        _lastSafeArea = null;
      });
      // Layout settings were persisted before the transition was published.
    });
  }

  /// Called during slider drag to provide instant visual feedback.
  /// Does NOT trigger a rebuild — only applies Transform.scale.
  void _onSliderLiveScaleUpdate(double scale) {
    setState(() {
      _liveScale = scale;
    });
  }

  Future<void> _showSettingsModal() async {
    await _runWithReaderControlsSuspended(() {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // Keep these explicit so reader settings preserves scrim and drag dismiss.
        // ignore: avoid_redundant_argument_values
        isDismissible: true,
        // ignore: avoid_redundant_argument_values
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          var isTypefacePickerVisible = false;

          return StatefulBuilder(
            builder: (context, setSheetState) {
              final sheetSize = _readerSettingsSheetSize(
                context,
                isTypefacePickerVisible: isTypefacePickerVisible,
              );

              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: sheetSize.max,
                minChildSize: sheetSize.min,
                maxChildSize: sheetSize.max,
                snap: true,
                snapSizes: [sheetSize.min, sheetSize.max],
                builder: (context, scrollController) {
                  return _SettingsModalContent(
                    settings: _settings,
                    onSettingsChanged: (updated) {
                      unawaited(_handleSettingsUpdate(updated));
                    },
                    onResetReadingPace: () {
                      unawaited(_statsService.resetReadingPaceCalibration());
                    },
                    onLiveScaleUpdate: _onSliderLiveScaleUpdate,
                    onTypefacePickerVisibilityChanged: (isVisible) {
                      if (isTypefacePickerVisible == isVisible) return;
                      setSheetState(() {
                        isTypefacePickerVisible = isVisible;
                      });
                    },
                    scrollController: scrollController,
                  );
                },
              );
            },
          );
        },
      );
    });
  }

  Widget _buildTopMenu() {
    return AnimatedBuilder(
      animation: _overlayAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -80 * (1 - _overlayAnim.value)),
          child: Opacity(
            opacity: _overlayAnim.value,
            child: Container(
              height: MediaQuery.paddingOf(context).top + 56,
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              decoration: BoxDecoration(
                color: _settings.menuColor.withValues(alpha: 0.97),
                border: Border(
                  bottom: BorderSide(
                    color: _settings.mutedColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to library',
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: _settings.textColor,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, right: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.title,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _settings.textColor,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Search book',
                    icon: Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: _settings.textColor,
                    ),
                    onPressed: _openSearchScreen,
                  ),
                  IconButton(
                    tooltip: 'Reading settings',
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 22,
                      color: _settings.textColor,
                    ),
                    onPressed: _showSettingsModal,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Bottom Menu (scrubber + navigation icon) ────────────────────────

  Future<void> _showChapterPanel() async {
    // Build a lookup map from original chunk index → text for bookmark previews
    final chunkTexts = <int, String>{};
    for (final chunk in _sourceChunks) {
      if (chunk.text != null && chunk.text!.isNotEmpty) {
        chunkTexts[chunk.index] = chunk.text!;
      }
    }

    await _runWithReaderControlsSuspended(() {
      return ChapterPanel.show(
        context,
        chapters: _sourceChapters,
        currentPage: _currentPage,
        currentStableLocation: _currentStableLocation(),
        chapterNavigationTargets: _chapterNavigationTargets,
        originalToDisplay: _originalToDisplay,
        positionHistoryNotifier: _positionHistoryNotifier,
        settings: _settings,
        onGoBack: _popAndGoBackToPosition,
        onNavigate: (originalIndex) {
          unawaited(
            _navigateToSourceLocation(
              originalChunkIndex: originalIndex,
              navigationSource: 'chapter',
            ),
          );
        },
        onNavigateChapter: (chapter) {
          final location = chapter.stableLocation;
          if (location != null) {
            unawaited(
              _navigateToStableLocation(location, navigationSource: 'chapter'),
            );
          } else {
            unawaited(
              _navigateToSourceLocation(
                originalChunkIndex: chapter.chunkIndex,
                navigationSource: 'chapter',
              ),
            );
          }
        },
        onNavigateBookmark: (bookmark) {
          final location = bookmark.stableLocation;
          if (location != null) {
            unawaited(
              _navigateToStableLocation(location, navigationSource: 'bookmark'),
            );
          } else {
            unawaited(_navigateAndMigrateLegacyBookmark(bookmark));
          }
        },
        bookmarks: _bookmarks,
        totalDisplayPages: _displayChunks.length,
        chunkTexts: chunkTexts,
        buildLocationLabel: _buildStorageLocationLabel,
        buildBookmarkLocationLabel: (bookmark) {
          final displayIndex = _displayIndexForBookmark(bookmark);
          if (displayIndex != null) {
            return 'Page ${displayIndex + 1} of ${_displayChunks.length}';
          }
          return _buildStorageLocationLabel(bookmark.chunkIndex);
        },
        onRemoveBookmark: (bookmark) async {
          final updated = await _bookmarkService.removeBookmark(bookmark);
          setState(() {
            _bookmarks = updated;
            _bookmarkDisplayHints.remove(readerBookmarkProjectionKey(bookmark));
          });
        },
        onClearAllBookmarks: () async {
          final updated = await _bookmarkService.clearAll();
          setState(() {
            _bookmarks = updated;
            _bookmarkDisplayHints.clear();
          });
        },
        onRestoreBookmarks: (bookmarks) async {
          final updated = await _bookmarkService.restoreAll(bookmarks);
          setState(() {
            _bookmarks = updated;
            _bookmarkDisplayHints.clear();
          });
        },
      );
    });
  }

  Widget _buildBottomMenu() {
    // Collect the progress ratios for all chapters to display ticks
    final flat = _flatChapters;
    final totalChunks = _displayChunks.isNotEmpty ? _displayChunks.length : 1;
    final markRatios = <double>[];

    for (final ch in flat) {
      final dispIdx = _originalToDisplay[ch.chunkIndex];
      if (dispIdx != null) {
        markRatios.add(dispIdx / totalChunks);
      }
    }

    final displayedPage = _scrubPreviewDisplayIndex ?? _currentPage;
    final progressLabel = ReaderStructuralProgressService.global(
      location: _lazySession == null
          ? _currentStableLocation()
          : _committedStableLocationForDisplay(displayedPage),
      isLazyWindow: _lazySession != null,
      displayIndex: displayedPage,
      displayChunkCount: _displayChunks.length,
      displayWindowComplete: _displayChunksComplete,
    ).label;

    return AnimatedBuilder(
      animation: _overlayAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 100 * (1 - _overlayAnim.value)),
          child: Opacity(
            opacity: _overlayAnim.value,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildBottomChapterRail(),
                Padding(
                  padding: const EdgeInsets.only(top: 46),
                  child: Container(
                    padding: EdgeInsets.only(
                      left: 8,
                      right: 8,
                      top: 14,
                      bottom: MediaQuery.paddingOf(context).bottom + 28,
                    ),
                    decoration: BoxDecoration(
                      color: _settings.menuColor.withValues(alpha: 0.97),
                      border: Border(
                        top: BorderSide(
                          color: _settings.mutedColor.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            // Chapter list navigation button
                            IconButton(
                              onPressed: _showChapterPanel,
                              icon: const Icon(
                                Icons.format_list_bulleted_rounded,
                              ),
                              color: _settings.textColor,
                              iconSize: 24,
                              tooltip: 'Chapters',
                            ),
                            // Scrubber
                            Expanded(
                              child: _lazySession == null
                                  ? _buildPageScrubber(markRatios)
                                  : _buildLazyStructuralScrubber(),
                            ),
                            // Annotations (Highlights, Notes, Dictionary)
                            IconButton(
                              onPressed: _openAnnotationsPanel,
                              icon: const Icon(
                                Icons.collections_bookmark_rounded,
                              ),
                              color: _settings.textColor,
                              iconSize: 22,
                              tooltip: 'Annotations',
                            ),
                          ],
                        ),
                        // ── Progress label row ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: _showPageJumpDialog,
                                style: TextButton.styleFrom(
                                  foregroundColor: _settings.mutedColor,
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 24),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: Icon(
                                  Icons.dialpad_rounded,
                                  size: 12,
                                  color: _settings.mutedColor,
                                ),
                                label: Text(
                                  _positionSummaryLabel(displayedPage),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _settings.mutedColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                progressLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: _settings.mutedColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (_settings.readingInsightsEnabled) ...[
                          const SizedBox(height: 6),
                          _buildReaderInsightRow(),
                        ],

                        // ── Speed Read Controls ──
                        _buildSpeedReadRow(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReaderInsightRow() {
    final insight = _readingInsightParts();
    if (insight == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 14, color: _settings.accentColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              insight.title,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: _settings.mutedColor,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            insight.timeLeft,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: _settings.mutedColor,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  void _setSpeedReadWPM(int wpm, {bool persist = false}) {
    final next = wpm.clamp(100, 700).toInt();
    setState(() {
      _settings = _settings.copyWith(speedReadWPM: next);
    });
    _speedReadController.setWPM(next);
    if (persist) {
      unawaited(_settingsService.saveSettings(_settings));
    }
  }

  void _setSpeedReadDisplayMode(SpeedReadDisplayMode mode) {
    if (_settings.speedReadDisplayMode == mode) return;
    setState(() {
      _settings = _settings.copyWith(speedReadDisplayMode: mode);
    });
    unawaited(_settingsService.saveSettings(_settings));
  }

  void _setSpeedReadPageAdvanceMode(SpeedReadPageAdvanceMode mode) {
    if (_settings.speedReadPageAdvanceMode == mode) return;
    setState(() {
      _settings = _settings.copyWith(speedReadPageAdvanceMode: mode);
    });
    unawaited(_settingsService.saveSettings(_settings));
    _scheduleSpeedReadPageAdvanceIfNeeded();
  }

  void _setSpeedReadAdaptivePacing(bool enabled) {
    if (_settings.speedReadAdaptivePacing == enabled) return;
    setState(() {
      _settings = _settings.copyWith(speedReadAdaptivePacing: enabled);
    });
    _speedReadController.setAdaptivePacing(enabled);
    unawaited(_settingsService.saveSettings(_settings));
  }

  String get _speedReadStyleLabel =>
      _settings.speedReadDisplayMode == SpeedReadDisplayMode.lyrics
      ? 'Highlight word'
      : 'Reading window';

  IconData get _speedReadStyleIcon =>
      _settings.speedReadDisplayMode == SpeedReadDisplayMode.lyrics
      ? Icons.format_color_text_rounded
      : Icons.center_focus_strong_rounded;

  String get _speedReadPageAdvanceLabel =>
      _settings.speedReadPageAdvanceMode == SpeedReadPageAdvanceMode.auto
      ? 'Auto-continue'
      : 'Wait for me';

  IconData get _speedReadPageAdvanceIcon =>
      _settings.speedReadPageAdvanceMode == SpeedReadPageAdvanceMode.auto
      ? Icons.keyboard_double_arrow_down_rounded
      : Icons.pan_tool_alt_rounded;

  Future<void> _openSpeedReadSettingsPanel() async {
    var localDisplayMode = _settings.speedReadDisplayMode;
    var localPageAdvanceMode = _settings.speedReadPageAdvanceMode;
    var localAdaptivePacing = _settings.speedReadAdaptivePacing;
    var localWpm = _settings.speedReadWPM;

    await _runWithReaderControlsSuspended(() {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _settings.backgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              void updateWpm(int next) {
                final clamped = next.clamp(100, 700).toInt();
                setSheetState(() => localWpm = clamped);
                _setSpeedReadWPM(clamped, persist: true);
              }

              return SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    14,
                    16,
                    MediaQuery.paddingOf(sheetContext).bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Speed Read settings',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _settings.textColor,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            color: _settings.mutedColor,
                            tooltip: 'Close',
                            onPressed: () =>
                                Navigator.of(sheetContext).maybePop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _SpeedReadChoiceRow(
                        label: 'Style',
                        firstLabel: 'Highlight word',
                        firstIcon: Icons.format_color_text_rounded,
                        firstSelected:
                            localDisplayMode == SpeedReadDisplayMode.lyrics,
                        secondLabel: 'Reading window',
                        secondIcon: Icons.center_focus_strong_rounded,
                        secondSelected:
                            localDisplayMode == SpeedReadDisplayMode.window,
                        settings: _settings,
                        onFirstTap: () {
                          setSheetState(
                            () =>
                                localDisplayMode = SpeedReadDisplayMode.lyrics,
                          );
                          _setSpeedReadDisplayMode(SpeedReadDisplayMode.lyrics);
                        },
                        onSecondTap: () {
                          setSheetState(
                            () =>
                                localDisplayMode = SpeedReadDisplayMode.window,
                          );
                          _setSpeedReadDisplayMode(SpeedReadDisplayMode.window);
                        },
                      ),
                      const SizedBox(height: 10),
                      _SpeedReadChoiceRow(
                        label: 'Page advance',
                        firstLabel: 'Wait for me',
                        firstIcon: Icons.pan_tool_alt_rounded,
                        firstSelected:
                            localPageAdvanceMode ==
                            SpeedReadPageAdvanceMode.manual,
                        secondLabel: 'Auto-continue',
                        secondIcon: Icons.keyboard_double_arrow_down_rounded,
                        secondSelected:
                            localPageAdvanceMode ==
                            SpeedReadPageAdvanceMode.auto,
                        settings: _settings,
                        onFirstTap: () {
                          setSheetState(
                            () => localPageAdvanceMode =
                                SpeedReadPageAdvanceMode.manual,
                          );
                          _setSpeedReadPageAdvanceMode(
                            SpeedReadPageAdvanceMode.manual,
                          );
                        },
                        onSecondTap: () {
                          setSheetState(
                            () => localPageAdvanceMode =
                                SpeedReadPageAdvanceMode.auto,
                          );
                          _setSpeedReadPageAdvanceMode(
                            SpeedReadPageAdvanceMode.auto,
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'WPM',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _settings.mutedColor,
                              ),
                            ),
                          ),
                          _SpeedReadWpmStepper(
                            wpm: localWpm,
                            settings: _settings,
                            onDecrease: () => updateWpm(localWpm - 25),
                            onIncrease: () => updateWpm(localWpm + 25),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Adaptive pacing',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: _settings.textColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Slows slightly for longer words and punctuation.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _settings.mutedColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: localAdaptivePacing,
                            activeThumbColor: _settings.accentColor,
                            onChanged: (enabled) {
                              setSheetState(
                                () => localAdaptivePacing = enabled,
                              );
                              _setSpeedReadAdaptivePacing(enabled);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(
                            'Done',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              color: _settings.accentColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    });
  }

  Widget _buildSpeedReadRow() {
    final isActive = _speedReadController.isActive;
    void updateSpeedReadEnabled(bool val) {
      if (val) {
        if (_displayChunks.isNotEmpty) {
          final chunkText = _displayChunks[_currentPage].text;
          _speedReadController.start(
            readerSpeedReadText(chunkText ?? ''),
            _currentPage,
          );
          _clearSpeedReadAutoPauseFlags();
          if (_overlayVisible) {
            // Close the menu — don't auto-pause since we're starting fresh
            setState(() => _overlayVisible = false);
            _overlayAnimController.reverse();
          }
        }
      } else {
        _speedReadController.stop();
        _clearSpeedReadAutoPauseFlags();
      }
    }

    if (!isActive) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.speed_rounded,
                  size: 18,
                  color: _settings.mutedColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Speed Read',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _settings.textColor,
                  ),
                ),
              ],
            ),
            Semantics(
              label: 'Speed Read',
              toggled: false,
              child: Switch(
                value: false,
                onChanged: updateSpeedReadEnabled,
                activeThumbColor: _settings.accentColor,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SpeedReadIconPill(
                      icon: _speedReadStyleIcon,
                      tooltip: _speedReadStyleLabel,
                      color: _settings.textColor,
                      background: _settings.menuColor.withValues(alpha: 0.72),
                    ),
                    const SizedBox(width: 8),
                    _SpeedReadIconPill(
                      icon: _speedReadPageAdvanceIcon,
                      tooltip: _speedReadPageAdvanceLabel,
                      color: _settings.accentColor,
                      background: _settings.accentColor.withValues(alpha: 0.12),
                    ),
                    const SizedBox(width: 8),
                    _SpeedReadWpmStepper(
                      wpm: _settings.speedReadWPM,
                      settings: _settings,
                      onDecrease: () => _setSpeedReadWPM(
                        _settings.speedReadWPM - 25,
                        persist: true,
                      ),
                      onIncrease: () => _setSpeedReadWPM(
                        _settings.speedReadWPM + 25,
                        persist: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SpeedReadIconPill(
                      icon: Icons.settings_suggest_rounded,
                      tooltip: 'Speed Read settings',
                      color: _settings.accentColor,
                      background: _settings.menuColor.withValues(alpha: 0.72),
                      onTap: () {
                        unawaited(_openSpeedReadSettingsPanel());
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Speed Read',
            toggled: true,
            child: SizedBox(
              width: 44,
              height: 34,
              child: Transform.scale(
                scale: 0.86,
                child: Switch(
                  value: true,
                  onChanged: updateSpeedReadEnabled,
                  activeThumbColor: _settings.accentColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Looks up a word using DictionaryService and presents a bottom sheet
  /// with the definition and a save button.
  Future<void> _lookupWord(
    String word, {
    int? originalChunkIndex,
    int? originalStartOffset,
    int? originalEndOffset,
    String? contextSentence,
  }) async {
    final cleanWord = word.trim();
    if (cleanWord.isEmpty) return;

    // Optional: could show a loading snackbar or rely on fast lookup
    final meaning = await _dictionaryService.lookupWord(cleanWord);

    if (!mounted) return;

    if (meaning == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No definition found for "$cleanWord"')),
      );
      return;
    }

    // StatefulBuilder allows the bottom sheet to update its own 'Like' button state
    await _runWithReaderControlsSuspended(() {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _settings.backgroundColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (bctx) {
          return StatefulBuilder(
            builder: (stCtx, setModalState) {
              final isSaved = _dictionaryService.isWordSaved(cleanWord);

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  MediaQuery.paddingOf(bctx).bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            cleanWord,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _settings.textColor,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isSaved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isSaved
                                ? Colors.red
                                : _settings.textColor.withValues(alpha: 0.5),
                          ),
                          onPressed: () async {
                            if (isSaved) {
                              final savedWord = _dictionaryService.words
                                  .firstWhere(
                                    (w) =>
                                        w.word.toLowerCase() ==
                                        cleanWord.toLowerCase(),
                                  );
                              await _dictionaryService.deleteWord(savedWord.id);
                            } else {
                              await _dictionaryService.saveWord(
                                cleanWord,
                                meaning,
                                contextSentence: contextSentence,
                                originalChunkIndex: originalChunkIndex,
                                originalStartOffset: originalStartOffset,
                                originalEndOffset: originalEndOffset,
                                stableLocation: originalChunkIndex == null
                                    ? null
                                    : _stableLocationForOriginalIndex(
                                        originalChunkIndex,
                                        textOffset: originalStartOffset ?? 0,
                                      ),
                              );
                            }
                            setModalState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      meaning,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: _settings.textColor.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    });
  }
  // ─── Chapter Navigation Rail ────────────────────────────────────────

  Widget _buildBottomChapterRail() {
    if (_sourceChapters.isEmpty) return const SizedBox.shrink();

    final adjacent = _getAdjacentChapterTitles();

    void handleChapterJump(String? Function() jumpFn) {
      if (jumpFn() != null && mounted) {
        _toggleOverlay();
      }
    }

    return Positioned(
      top: 0,
      left: 14,
      right: 14,
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            if (adjacent.prevTitle != null)
              Positioned(
                left: 0,
                top: 0,
                child: _ChapterArrowButton(
                  direction: _ArrowDirection.left,
                  chapterTitle: adjacent.prevTitle!,
                  color: _settings.textColor,
                  backgroundColor: _settings.menuColor,
                  onTap: () => handleChapterJump(_jumpToPrevChapter),
                ),
              ),
            if (adjacent.nextTitle != null)
              Positioned(
                right: 0,
                top: 0,
                child: _ChapterArrowButton(
                  direction: _ArrowDirection.right,
                  chapterTitle: adjacent.nextTitle!,
                  color: _settings.textColor,
                  backgroundColor: _settings.menuColor,
                  onTap: () => handleChapterJump(_jumpToNextChapter),
                ),
              ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ValueListenableBuilder<PositionHistory?>(
                    valueListenable: _positionHistoryNotifier,
                    builder: (context, posHistory, _) {
                      if (posHistory == null) {
                        return const SizedBox.shrink();
                      }
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: ActionChip(
                          onPressed: _popAndGoBackToPosition,
                          backgroundColor: Colors.black.withValues(alpha: 0.85),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          labelStyle: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.undo_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'To: ${posHistory.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ArrowDirection { left, right }

class _SpeedReadChoiceRow extends StatelessWidget {
  final String label;
  final String firstLabel;
  final IconData firstIcon;
  final bool firstSelected;
  final String secondLabel;
  final IconData secondIcon;
  final bool secondSelected;
  final ReadingSettings settings;
  final VoidCallback onFirstTap;
  final VoidCallback onSecondTap;

  const _SpeedReadChoiceRow({
    required this.label,
    required this.firstLabel,
    required this.firstIcon,
    required this.firstSelected,
    required this.secondLabel,
    required this.secondIcon,
    required this.secondSelected,
    required this.settings,
    required this.onFirstTap,
    required this.onSecondTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: settings.mutedColor,
            ),
          ),
        ),
        Expanded(
          child: _SpeedReadOptionButton(
            label: firstLabel,
            icon: firstIcon,
            selected: firstSelected,
            settings: settings,
            onTap: onFirstTap,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _SpeedReadOptionButton(
            label: secondLabel,
            icon: secondIcon,
            selected: secondSelected,
            settings: settings,
            onTap: onSecondTap,
          ),
        ),
      ],
    );
  }
}

class _SpeedReadOptionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final ReadingSettings settings;
  final VoidCallback onTap;

  const _SpeedReadOptionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.settings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? settings.accentColor : settings.textColor;
    final background = selected
        ? settings.accentColor.withValues(alpha: 0.14)
        : settings.menuColor.withValues(alpha: 0.72);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? settings.accentColor.withValues(alpha: 0.42)
                  : settings.mutedColor.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color.withValues(alpha: 0.9)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedReadIconPill extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  const _SpeedReadIconPill({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Ink(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: color.withValues(alpha: onTap == null ? 0.10 : 0.18),
              ),
            ),
            child: Icon(icon, size: 17, color: color.withValues(alpha: 0.9)),
          ),
        ),
      ),
    );
  }
}

class _SpeedReadWpmStepper extends StatelessWidget {
  static const int minWpm = 100;
  static const int maxWpm = 700;

  final int wpm;
  final ReadingSettings settings;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _SpeedReadWpmStepper({
    required this.wpm,
    required this.settings,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final canDecrease = wpm > minWpm;
    final canIncrease = wpm < maxWpm;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: settings.menuColor.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: settings.mutedColor.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SpeedReadStepperButton(
            icon: Icons.remove_rounded,
            tooltip: 'Decrease WPM',
            enabled: canDecrease,
            settings: settings,
            onTap: onDecrease,
          ),
          SizedBox(
            width: 74,
            child: Text(
              '$wpm WPM',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: settings.textColor,
              ),
            ),
          ),
          _SpeedReadStepperButton(
            icon: Icons.add_rounded,
            tooltip: 'Increase WPM',
            enabled: canIncrease,
            settings: settings,
            onTap: onIncrease,
          ),
        ],
      ),
    );
  }
}

class _SpeedReadStepperButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final ReadingSettings settings;
  final VoidCallback onTap;

  const _SpeedReadStepperButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.settings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? settings.accentColor
        : settings.mutedColor.withValues(alpha: 0.38);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 30,
            height: 32,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// A compact corner-docked chapter jump button.
class _ChapterArrowButton extends StatelessWidget {
  final _ArrowDirection direction;
  final String chapterTitle;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _ChapterArrowButton({
    required this.direction,
    required this.chapterTitle,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLeft = direction == _ArrowDirection.left;
    final icon = isLeft
        ? Icons.chevron_left_rounded
        : Icons.chevron_right_rounded;

    return Semantics(
      button: true,
      label: '${isLeft ? 'Previous' : 'Next'} chapter: $chapterTitle',
      child: Tooltip(
        message: chapterTitle,
        preferBelow: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: backgroundColor.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.08)),
              ),
              child: Icon(icon, color: color.withValues(alpha: 0.78), size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

/// A semi-transparent floating pause/play button for speed reading control.
/// Appears bottom-right when speed read is active and the overlay menu is hidden.
class _SpeedReadFAB extends StatefulWidget {
  final SpeedReadController controller;
  final VoidCallback onTap;

  const _SpeedReadFAB({required this.controller, required this.onTap});

  @override
  State<_SpeedReadFAB> createState() => _SpeedReadFABState();
}

class _SpeedReadFABState extends State<_SpeedReadFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late bool _lastPaused;

  @override
  void initState() {
    super.initState();
    _lastPaused = widget.controller.isPaused;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: _lastPaused ? 0.0 : 1.0,
    );
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _SpeedReadFAB oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _lastPaused = widget.controller.isPaused;
      widget.controller.addListener(_onControllerChanged);
      _syncPauseAnimation();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _animController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncPauseAnimation();
    setState(() {});
  }

  void _syncPauseAnimation() {
    final paused = widget.controller.isPaused;
    if (_lastPaused == paused) return;
    _lastPaused = paused;
    if (paused) {
      _animController.reverse();
    } else {
      _animController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = colorScheme.primary;
    return Semantics(
      button: true,
      label: widget.controller.isPaused
          ? 'Resume Speed Read'
          : 'Pause Speed Read',
      value: '${(widget.controller.progressInPage * 100).round()} percent',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            // Subtle glow when playing (animController value → 1.0)
            final glowOpacity = _animController.value * 0.4;
            return SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      value: widget.controller.progressInPage.clamp(0.0, 1.0),
                      strokeWidth: 2.6,
                      backgroundColor: colorScheme.onSurface.withValues(
                        alpha: 0.12,
                      ),
                      valueColor: AlwaysStoppedAnimation(accentColor),
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withValues(
                        alpha: 0.32 + _animController.value * 0.14,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: glowOpacity),
                          blurRadius: 14,
                          spreadRadius: 1.5,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        widget.controller.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        key: ValueKey(widget.controller.isPaused),
                        color: Colors.white.withValues(alpha: 0.95),
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Extracted Widgets — Separation of Concerns & Rebuild Minimization
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

typedef _ReaderNoteEditorRoute =
    Future<T> Function<T>(
      Future<T> Function() action, {
      int? visibleDisplayIndex,
    });

/// Extracted PageView to isolate its rebuilds from overlay changes.
class _ReaderPageView extends StatelessWidget {
  final int activeDisplayIndex;
  final PageController pageController;
  final ReadingCardDeckController cardDeckController;
  final List<BookChunk> displayChunks;
  final ReaderLayoutContract? layoutContract;
  final List<ResolvedReaderCardLayout?> resolvedLayouts;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;
  final List<({int chunkIndex, String title})> flatChapters;
  final List<ChapterNavigationTarget> chapterNavigationTargets;
  final Set<int> chapterBoundaryCompletedDisplayIndexes;
  final Map<int, ReaderPublishedCardBoundaryEvidence> cardBoundaryEvidence;
  final ChapterCardLayout? completeChapterCardLayout;
  final Map<int, StableBookLocation> sourceLocationsByChunkIndex;
  final bool displayChunksComplete;
  final bool allowWindowExactFallback;
  final bool canSwipe;
  final bool canRequestPreviousBoundary;
  final VoidCallback onPreviousBoundaryRequested;
  final ReadingSettings settings;
  final BookmarkService bookmarkService;
  final List<Bookmark> bookmarks;
  final Map<String, int> bookmarkDisplayHints;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSettled;
  final Function(String url) onLinkTap;
  final Function(int displayIndex) onDoubleTap;
  final Function(int displayIndex) onTripleTap;
  final Function(int displayIndex) onBookmarkLongPress;
  final Future<void> Function(int displayIndex)? onImageTap;
  final SpeedReadController speedReadController;

  // ── Highlights ──
  final List<Highlight> highlights;
  final List<ReaderCharacterSourceRange> characterSourceRanges;
  final void Function(
    int displayIndex,
    int startOffset,
    int endOffset,
    String text,
    Color color,
    HighlightType type, [
    String? note,
  ])?
  onHighlightCreated;
  final FutureOr<void> Function(
    int displayIndex,
    int startOffset,
    int endOffset,
    String text,
  )?
  onQuoteShareRequested;
  final Future<void> Function(
    List<MappedTextRange> mappedRanges,
    String text,
    Color color,
    String note,
  )?
  onMappedNoteCreated;
  final void Function(Highlight highlight, Color newColor)?
  onHighlightColorChange;
  final void Function(String id)? onHighlightDeleted;
  final FutureOr<void> Function(String id, String note)? onNoteUpdated;
  final FutureOr<void> Function(String id)? onNoteRemoved;
  final _ReaderNoteEditorRoute? onNoteEditorRoute;
  final List<Color> highlightPalette;
  final Color defaultHighlightColor;
  final ValueChanged<Color>? onDefaultHighlightColorChanged;
  final Future<List<Color>> Function(Color color)? onAddCustomHighlightColor;
  final Future<List<Color>> Function(Color color)? onRemoveCustomHighlightColor;
  final Future<List<Color>> Function()? onResetHighlightPalette;
  final int defaultBookmarkColorIndex;
  final ValueChanged<int>? onDefaultBookmarkColorChanged;
  final void Function(Offset? globalPosition)? onTapOutside;
  final VoidCallback? onSuppressParentReaderTap;
  final void Function(
    String word, {
    int? originalChunkIndex,
    int? originalStartOffset,
    int? originalEndOffset,
    String? contextSentence,
  })?
  onDictionaryLookup;
  final ValueChanged<bool>? onCardInteractionBlockedChanged;

  const _ReaderPageView({
    required this.speedReadController,
    required this.cardDeckController,
    required this.activeDisplayIndex,
    required this.pageController,
    required this.displayChunks,
    required this.layoutContract,
    required this.resolvedLayouts,
    required this.displayToOriginal,
    required this.originalToDisplay,
    required this.flatChapters,
    required this.chapterNavigationTargets,
    required this.chapterBoundaryCompletedDisplayIndexes,
    required this.cardBoundaryEvidence,
    required this.completeChapterCardLayout,
    required this.sourceLocationsByChunkIndex,
    required this.displayChunksComplete,
    required this.allowWindowExactFallback,
    required this.canSwipe,
    required this.canRequestPreviousBoundary,
    required this.onPreviousBoundaryRequested,
    required this.settings,
    required this.bookmarkService,
    required this.bookmarks,
    required this.bookmarkDisplayHints,
    required this.onPageChanged,
    required this.onPageSettled,
    required this.onLinkTap,
    required this.onDoubleTap,
    required this.onTripleTap,
    required this.onBookmarkLongPress,
    this.onImageTap,
    this.highlights = const [],
    this.characterSourceRanges = const [],
    this.onHighlightCreated,
    this.onQuoteShareRequested,
    this.onMappedNoteCreated,
    this.onHighlightColorChange,
    this.onHighlightDeleted,
    this.onNoteUpdated,
    this.onNoteRemoved,
    this.onNoteEditorRoute,
    this.highlightPalette = kHighlightColors,
    this.defaultHighlightColor = const Color(0xFFEF5350),
    this.onDefaultHighlightColorChanged,
    this.onAddCustomHighlightColor,
    this.onRemoveCustomHighlightColor,
    this.onResetHighlightPalette,
    this.defaultBookmarkColorIndex = 0,
    this.onDefaultBookmarkColorChanged,
    this.onTapOutside,
    this.onSuppressParentReaderTap,
    this.onDictionaryLookup,
    this.onCardInteractionBlockedChanged,
  });

  int? _displayIndexForBookmark(Bookmark bookmark) {
    for (
      var displayIndex = 0;
      displayIndex < displayChunks.length;
      displayIndex++
    ) {
      for (final range in displayChunks[displayIndex].effectiveSourceRanges) {
        if (range.originalChunkIndex != bookmark.chunkIndex) continue;
        final containsOffset =
            bookmark.originalStartOffset >= range.originalStartOffset &&
            bookmark.originalStartOffset < range.originalEndOffset;
        if (containsOffset) return displayIndex;
      }
    }

    return originalToDisplay[bookmark.chunkIndex];
  }

  CardDepthChapterPageMeta _chapterPageMetaFor(int displayIndex) {
    final boundary = cardBoundaryEvidence[displayIndex];
    return CardDepthChapterProgressService.calculate(
      displayIndex: displayIndex,
      displayChunkCount: displayChunks.length,
      displayToOriginal: displayToOriginal,
      locationsByChunkIndex: sourceLocationsByChunkIndex,
      chapterNavigationTargets: chapterNavigationTargets,
      displayChunksComplete: displayChunksComplete,
      currentCardStartLocation: boundary?.startLocation,
      currentCardEndLocation: boundary?.endLocation,
      completeChapterLayout: completeChapterCardLayout,
      currentCardReachesChapterBoundary: chapterBoundaryCompletedDisplayIndexes
          .contains(displayIndex),
      allowWindowExactFallback: allowWindowExactFallback,
      fallbackFlatChapters: flatChapters,
    );
  }

  Widget _buildReadingCard(
    BuildContext context,
    int index,
    double stackProgress,
    bool isCurrent, {
    bool useRealStack = false,
  }) {
    final mappedOriginals = displayToOriginal[index];
    final chapterMeta = _chapterPageMetaFor(index);

    // Render each bookmark on one display page only. Prefer the in-session
    // tap target when it still maps to the same original chunk; otherwise
    // fall back to the rebuilt canonical page.
    final bookmark = bookmarks
        .where((candidate) => mappedOriginals.contains(candidate.chunkIndex))
        .map((candidate) {
          final hintedIndex =
              bookmarkDisplayHints[readerBookmarkProjectionKey(candidate)];
          final hasValidHint =
              hintedIndex != null &&
              hintedIndex >= 0 &&
              hintedIndex < displayToOriginal.length &&
              displayChunks[hintedIndex].effectiveSourceRanges.any(
                (range) =>
                    range.originalChunkIndex == candidate.chunkIndex &&
                    candidate.originalStartOffset >=
                        range.originalStartOffset &&
                    candidate.originalStartOffset < range.originalEndOffset,
              );
          if (hasValidHint) return hintedIndex == index ? candidate : null;

          final canonicalIndex = _displayIndexForBookmark(candidate);
          if (canonicalIndex == index) return candidate;

          return null;
        })
        .firstWhere((b) => b != null, orElse: () => null);

    final pageHighlights = <Highlight>[];
    for (final origIdx in mappedOriginals) {
      for (final hl in highlights) {
        if (hl.originalChunkIndex == origIdx) pageHighlights.add(hl);
      }
    }

    return ReadingCard(
      isActivePage: isCurrent && index == activeDisplayIndex,
      chunk: displayChunks[index],
      settings: settings,
      layoutContract: layoutContract,
      resolvedLayout: index < resolvedLayouts.length
          ? resolvedLayouts[index]
          : null,
      speedReadController: isCurrent ? speedReadController : null,
      onLinkTap: onLinkTap,
      bookmark: bookmark,
      onDoubleTap: isCurrent ? () => onDoubleTap(index) : null,
      onTripleTap: isCurrent ? () => onTripleTap(index) : null,
      onBookmarkLongPress: isCurrent ? () => onBookmarkLongPress(index) : null,
      onImageTap: isCurrent && chunkHasImage(displayChunks[index])
          ? () {
              final handler = onImageTap;
              if (handler != null) unawaited(handler(index));
            }
          : null,
      chapterTitle: chapterMeta.title,
      chapterPageLabel: chapterMeta.pageLabel,
      chapterProgress: chapterMeta.progress,
      depthLiftProgress: stackProgress,
      showStackLayers: !useRealStack,
      enableTextSelection: isCurrent && index == activeDisplayIndex,
      highlights: pageHighlights,
      generatedCharacterRanges: projectReaderCharacterRangesToDisplay(
        displayChunk: displayChunks[index],
        sourceRanges: characterSourceRanges,
      ),
      onHighlightCreated: isCurrent
          ? (start, end, text, colorIndex, type, [note]) {
              onHighlightCreated?.call(
                index,
                start,
                end,
                text,
                colorIndex,
                type,
                note,
              );
            }
          : null,
      onQuoteShareRequested: isCurrent
          ? (start, end, text) async {
              await onQuoteShareRequested?.call(index, start, end, text);
            }
          : null,
      onMappedNoteCreated: isCurrent ? onMappedNoteCreated : null,
      onHighlightColorChange: isCurrent ? onHighlightColorChange : null,
      onHighlightDeleted: isCurrent ? onHighlightDeleted : null,
      onNoteUpdated: isCurrent ? onNoteUpdated : null,
      onNoteRemoved: isCurrent ? onNoteRemoved : null,
      onNoteEditorRoute: isCurrent && onNoteEditorRoute != null
          ? <T>(action) =>
                onNoteEditorRoute!<T>(action, visibleDisplayIndex: index)
          : null,
      highlightPalette: highlightPalette,
      defaultHighlightColor: defaultHighlightColor,
      onDefaultHighlightColorChanged: isCurrent
          ? onDefaultHighlightColorChanged
          : null,
      onAddCustomColor: isCurrent ? onAddCustomHighlightColor : null,
      onRemoveCustomColor: isCurrent ? onRemoveCustomHighlightColor : null,
      onResetHighlightPalette: isCurrent ? onResetHighlightPalette : null,
      onTapOutside: isCurrent ? onTapOutside : null,
      onSuppressParentReaderTap: isCurrent ? onSuppressParentReaderTap : null,
      onDictionaryLookup: isCurrent ? onDictionaryLookup : null,
      onInteractionBlockedChanged: isCurrent
          ? onCardInteractionBlockedChanged
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final useCardDeck = settings.enableCardDepth;

    if (useCardDeck) {
      return ReadingCardDeck(
        controller: cardDeckController,
        currentIndex: activeDisplayIndex,
        itemCount: displayChunks.length,
        canSwipe: canSwipe,
        canRequestPrevious: canRequestPreviousBoundary,
        onPreviousBoundaryRequested: onPreviousBoundaryRequested,
        cacheCardWidgetsDuringDrag: true,
        axis: settings.resolvedPagingAxis,
        onIndexChanged: onPageChanged,
        cardBuilder: (context, index, stackProgress, isCurrent) =>
            _buildReadingCard(
              context,
              index,
              stackProgress,
              isCurrent,
              useRealStack: true,
            ),
      );
    }

    return NotificationListener<OverscrollNotification>(
      onNotification: (notification) {
        if (activeDisplayIndex == 0 &&
            canRequestPreviousBoundary &&
            notification.overscroll < 0) {
          onPreviousBoundaryRequested();
        }
        return false;
      },
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          final settledPage = pageController.hasClients
              ? pageController.page?.round()
              : null;
          if (settledPage != null) onPageSettled(settledPage);
          return false;
        },
        child: PageView.builder(
          scrollDirection: settings.resolvedPagingAxis,
          controller: pageController,
          itemCount: displayChunks.length,
          physics: const _SnappyPagePhysics(parent: ClampingScrollPhysics()),
          onPageChanged: onPageChanged,
          itemBuilder: (context, index) {
            return _buildReadingCard(
              context,
              index,
              0,
              index == activeDisplayIndex,
            );
          },
        ),
      ),
    );
  }

  bool chunkHasImage(BookChunk chunk) {
    final imageBytes = chunk.imageBytes;
    return chunk.type == BookChunkType.image &&
        imageBytes != null &&
        imageBytes.isNotEmpty;
  }
}

/// TikTok-style snappy page scroll physics.
/// Overdamped spring snaps to the target page fast, with zero bounce.
/// ClampingScrollPhysics parent prevents iOS-style edge bounce.
// class _SnappyPagePhysics extends PageScrollPhysics {
//   const _SnappyPagePhysics({super.parent});

//   @override
//   _SnappyPagePhysics applyTo(ScrollPhysics? ancestor) {
//     return _SnappyPagePhysics(parent: buildParent(ancestor));
//   }

//   @override
//   SpringDescription get spring => const SpringDescription(
//     mass: 0.5,
//     stiffness: 500, // increased stiffness = much faster snap
//     damping: 35, // overdamped (critical is ~31.6) = snaps instantly into place without any bounce
//   );
// }
class _SnappyPagePhysics extends PageScrollPhysics {
  const _SnappyPagePhysics({super.parent});

  @override
  _SnappyPagePhysics applyTo(ScrollPhysics? ancestor) {
    return _SnappyPagePhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
    mass: 0.3, // Lighter mass = faster response
    stiffness: 300, // High enough to snap quick
    damping: 19, // 2*sqrt(0.3*300) ≈ 18.97 — critically damped, zero bounce
  );

  @override
  double get minFlingVelocity => 200.0; // Intentional flick required

  @override
  double get maxFlingVelocity => 3000.0; // Let fast flings carry through fully

  // This is the key missing piece — controls drag friction during the swipe
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return offset * 0.92; // ~0.88–0.95 sweet spot, lower = heavier drag
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Modal — Extracted from the 400-line build method
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

const double _settingsSheetMainTargetHeight = 560;
const double _settingsSheetTypefaceTargetHeight = 520;

({double min, double max}) _readerSettingsSheetSize(
  BuildContext context, {
  required bool isTypefacePickerVisible,
}) {
  final media = MediaQuery.of(context);
  final usableHeight =
      media.size.height - media.padding.top - media.viewInsets.bottom;
  final targetHeight = isTypefacePickerVisible
      ? _settingsSheetTypefaceTargetHeight
      : _settingsSheetMainTargetHeight;
  final maxSize = (targetHeight / usableHeight).clamp(0.42, 0.84);
  final minSize = (maxSize - 0.12).clamp(0.36, maxSize);

  return (min: minSize, max: maxSize);
}

class _SettingsModalContent extends StatefulWidget {
  final ReadingSettings settings;
  final ValueChanged<ReadingSettings> onSettingsChanged;
  final VoidCallback? onResetReadingPace;
  final ValueChanged<double>? onLiveScaleUpdate;
  final ValueChanged<bool>? onTypefacePickerVisibilityChanged;
  final ScrollController? scrollController;

  const _SettingsModalContent({
    required this.settings,
    required this.onSettingsChanged,
    this.onResetReadingPace,
    this.onLiveScaleUpdate,
    this.onTypefacePickerVisibilityChanged,
    this.scrollController,
  });

  @override
  State<_SettingsModalContent> createState() => _SettingsModalContentState();
}

enum _ReaderSettingsCategory {
  appearance,
  layout,
  navigation,
  effects,
  reading,
}

enum _PresetAction { update, rename, delete }

class _SettingsModalContentState extends State<_SettingsModalContent> {
  final _settingsService = ReadingSettingsService();
  late ReadingSettings _localSettings;
  List<ReadingSettingsPreset> _presets = const [];
  Set<String> _hiddenBuiltInPresetIds = const {};
  String? _activePresetId;
  ReadingSettings? _activePresetSettings;
  _ReaderSettingsCategory _selectedCategory =
      _ReaderSettingsCategory.appearance;
  bool _hasSelectedCategoryThisSession = false;
  bool _showTypefacePicker = false;

  @override
  void initState() {
    super.initState();
    _localSettings = widget.settings;
    unawaited(_loadLastSelectedCategory());
    unawaited(_loadPresets());
  }

  Future<void> _loadLastSelectedCategory() async {
    final savedCategoryName = await _settingsService
        .loadReaderSettingsLastSection();
    final savedCategory = _readerSettingsCategoryFromName(savedCategoryName);
    if (!mounted || savedCategory == null || _hasSelectedCategoryThisSession) {
      return;
    }
    setState(() => _selectedCategory = savedCategory);
  }

  _ReaderSettingsCategory? _readerSettingsCategoryFromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final category in _ReaderSettingsCategory.values) {
      if (category.name == name) return category;
    }
    return null;
  }

  void _selectCategory(_ReaderSettingsCategory category) {
    if (_selectedCategory == category) return;
    _hasSelectedCategoryThisSession = true;
    setState(() => _selectedCategory = category);
    unawaited(_settingsService.saveReaderSettingsLastSection(category.name));
  }

  void _update(ReadingSettings updated, {String? activePresetId}) {
    final activeSettings = activePresetId == null
        ? null
        : updated.copyWith(clearBookThemePalette: true);
    setState(() {
      _localSettings = updated;
      _activePresetId = activePresetId;
      _activePresetSettings = activeSettings;
    });
    widget.onSettingsChanged(updated);
  }

  Future<void> _loadPresets() async {
    final presets = await _settingsService.loadPresets();
    final hiddenBuiltInPresetIds = await _settingsService
        .loadHiddenBuiltInPresetIds();
    if (!mounted) return;
    setState(() {
      _presets = presets;
      _hiddenBuiltInPresetIds = hiddenBuiltInPresetIds;
      _activePresetId = _presetIdForSettings(_localSettings);
    });
  }

  void _setTypefacePickerVisible(bool isVisible) {
    if (_showTypefacePicker == isVisible) return;
    setState(() => _showTypefacePicker = isVisible);
    widget.onTypefacePickerVisibilityChanged?.call(isVisible);
  }

  Color get _accent => _localSettings.accentColor;

  Color get _controlColor => Color.alphaBlend(
    _localSettings.textColor.withValues(
      alpha: _localSettings.isDark ? 0.12 : 0.08,
    ),
    _localSettings.backgroundColor,
  );

  Color get _selectedControlColor => Color.alphaBlend(
    _accent.withValues(alpha: _localSettings.isDark ? 0.22 : 0.14),
    _localSettings.backgroundColor,
  );

  Color get _hairlineColor => _localSettings.mutedColor.withValues(alpha: 0.28);

  Color get _groupSurfaceColor => Color.alphaBlend(
    _localSettings.textColor.withValues(
      alpha: _localSettings.isDark ? 0.06 : 0.04,
    ),
    _localSettings.menuColor,
  );

  List<BoxShadow> get _softShadow => [
    BoxShadow(
      color: Colors.black.withValues(
        alpha: _localSettings.isDark ? 0.12 : 0.05,
      ),
      blurRadius: 8,
      offset: const Offset(0, 3),
    ),
  ];

  TextStyle get _labelStyle => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: _localSettings.mutedColor,
  );

  TextStyle get _bodyLabelStyle => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: _localSettings.textColor,
  );

  Widget _buildSection(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _groupSurfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _hairlineColor, width: 0.8),
          boxShadow: _softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title.toUpperCase(), style: _labelStyle),
            ),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSubLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _localSettings.mutedColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom + 14;
    final horizontalPadding = MediaQuery.sizeOf(context).width < 380
        ? 14.0
        : 18.0;

    return Container(
      decoration: BoxDecoration(
        color: _localSettings.menuColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: _localSettings.isDark ? 0.45 : 0.16,
            ),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: _showTypefacePicker
              ? Padding(
                  key: const ValueKey('settings-typeface-shell'),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    4,
                    horizontalPadding,
                    bottomInset,
                  ),
                  child: SingleChildScrollView(
                    controller: widget.scrollController,
                    child: _buildTypefacePicker(),
                  ),
                )
              : _buildMainSettings(
                  horizontalPadding: horizontalPadding,
                  bottomInset: bottomInset,
                ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: SizedBox(
        height: 12,
        width: 96,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: _localSettings.mutedColor.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainSettings({
    required double horizontalPadding,
    required double bottomInset,
  }) {
    return Column(
      key: const ValueKey('settings-main'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDragHandle(),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: _buildQuickPresets(),
        ),
        const SizedBox(height: 6),
        _buildCategoryTabs(horizontalPadding: horizontalPadding),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              bottomInset,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: _buildSelectedCategorySection(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickPresets() {
    final visiblePresets = [
      for (final preset in _builtInPresets())
        if (!_hiddenBuiltInPresetIds.contains(preset.id)) preset,
      ..._presets,
    ];
    final addIndex = visiblePresets.length;

    return _buildSection(
      'Presets',
      SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: visiblePresets.length + (_presets.length < 4 ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            if (index == addIndex) return _buildAddPresetChip();
            final preset = visiblePresets[index];
            return _buildPresetChip(
              preset,
              isBuiltIn: preset.id.startsWith('builtin-'),
            );
          },
        ),
      ),
    );
  }

  List<ReadingSettingsPreset> _builtInPresets() {
    const naloriDefault = ReadingSettings(readerTheme: AppTheme.system);

    return [
      const ReadingSettingsPreset(
        id: 'builtin-amoled-cards',
        name: 'AMOLED Cards',
        description: 'Roboto Mono · AMOLED black · Card Mode on',
        settings: ReadingSettings(
          appTheme: AppTheme.amoled,
          readerTheme: AppTheme.amoled,
          fontFamily: ReaderFontFamily.robotoMono,
          fontWeight: ReaderFontWeight.medium,
        ),
      ),
      ReadingSettingsPreset(
        id: 'builtin-comfort',
        name: 'Comfort',
        description: 'Atkinson · Larger text · 1.4x line height',
        settings: naloriDefault.copyWith(
          fontFamily: ReaderFontFamily.atkinsonHyperlegible,
          fontSize: ReaderFontSize.l,
          lineHeight: 1.4,
          contentDensity: ContentDensity.medium,
          enableCardDepth: true,
        ),
      ),
      ReadingSettingsPreset(
        id: 'builtin-dense-scroll',
        name: 'Dense Scroll',
        description: 'Lexend · High density · Card Mode off',
        settings: naloriDefault.copyWith(
          fontSize: ReaderFontSize.s,
          contentDensity: ContentDensity.high,
          enableCardDepth: false,
        ),
      ),
      ReadingSettingsPreset(
        id: 'builtin-classic-reader',
        name: 'Classic Reader',
        description: 'Literata · Full density · Card Mode off',
        settings: _localSettings.copyWith(
          fontFamily: ReaderFontFamily.literata,
          fontSize: ReaderFontSize.xs,
          fontWeight: ReaderFontWeight.regular,
          lineHeight: 1.2,
          contentDensity: ContentDensity.fullPage,
          textAlign: ReaderTextAlign.left,
          enableCardDepth: false,
          pagingAxis: ReaderPagingAxis.vertical,
        ),
      ),
      const ReadingSettingsPreset(
        id: 'builtin-nalori-default',
        name: 'Nalori Default',
        description: 'Lexend · Medium density · Card Mode on',
        settings: naloriDefault,
      ),
    ];
  }

  Widget _buildAddPresetChip() {
    return ActionChip(
      avatar: Icon(Icons.add_rounded, color: _accent, size: 18),
      label: Text(_presets.isEmpty ? 'Save current' : 'Add preset'),
      visualDensity: VisualDensity.compact,
      backgroundColor: _controlColor,
      side: BorderSide(color: _hairlineColor, width: 0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: _localSettings.textColor,
      ),
      onPressed: _addPreset,
    );
  }

  Widget _buildPresetChip(
    ReadingSettingsPreset preset, {
    required bool isBuiltIn,
  }) {
    final isSelected = _isPresetActive(preset);
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _applyPreset(preset),
        child: Container(
          constraints: const BoxConstraints(minWidth: 84),
          padding: const EdgeInsets.only(left: 12, right: 2),
          decoration: BoxDecoration(
            color: isSelected ? _selectedControlColor : _controlColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? _accent : _hairlineColor,
              width: isSelected ? 1.3 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Icon(Icons.check_rounded, color: _accent, size: 16),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: Text(
                  preset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                    color: isSelected ? _accent : _localSettings.textColor,
                  ),
                ),
              ),
              SizedBox.square(
                dimension: 30,
                child: PopupMenuButton<_PresetAction>(
                  tooltip: 'Preset actions',
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: _localSettings.mutedColor,
                    size: 18,
                  ),
                  color: _localSettings.menuColor,
                  onSelected: (action) =>
                      _handlePresetAction(action, preset, isBuiltIn: isBuiltIn),
                  itemBuilder: (context) => [
                    if (!isBuiltIn) ...[
                      const PopupMenuItem(
                        value: _PresetAction.update,
                        child: Text('Update'),
                      ),
                      const PopupMenuItem(
                        value: _PresetAction.rename,
                        child: Text('Rename'),
                      ),
                    ],
                    const PopupMenuItem(
                      value: _PresetAction.delete,
                      child: Text('Remove'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final description = preset.description;
    if (description == null || description.isEmpty) return chip;
    return Tooltip(message: description, child: chip);
  }

  Future<void> _addPreset() async {
    if (_presets.length >= 4) return;
    final name = await _promptPresetName(
      title: 'Save preset',
      initialValue: 'Preset ${_presets.length + 1}',
    );
    if (!mounted) return;
    if (name == null) return;

    final preset = ReadingSettingsPreset(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      settings: _localSettings.copyWith(clearBookThemePalette: true),
    );
    await _savePresetList([..._presets, preset]);
  }

  Future<void> _savePresetList(List<ReadingSettingsPreset> presets) async {
    final next = presets.take(4).toList(growable: false);
    if (!mounted) return;
    setState(() => _presets = next);
    await _settingsService.savePresets(next);
  }

  Future<String?> _promptPresetName({
    required String title,
    required String initialValue,
  }) async {
    var currentValue = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _localSettings.menuColor,
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _localSettings.textColor,
            ),
          ),
          content: TextFormField(
            key: ValueKey('preset-name-$initialValue'),
            initialValue: initialValue,
            autofocus: true,
            maxLength: 24,
            style: GoogleFonts.inter(color: _localSettings.textColor),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Preset name',
              hintStyle: GoogleFonts.inter(color: _localSettings.mutedColor),
            ),
            onChanged: (value) => currentValue = value,
            onFieldSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(currentValue),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  bool _isPresetActive(ReadingSettingsPreset preset) {
    if (_activePresetId == preset.id) {
      final appliedSettings = _activePresetSettings;
      return appliedSettings == null ||
          _settingsMatchPreset(_localSettings, appliedSettings);
    }
    return _activePresetId == null &&
        _settingsMatchPreset(_localSettings, preset.settings);
  }

  String? _presetIdForSettings(ReadingSettings settings) {
    for (final preset in [..._builtInPresets(), ..._presets]) {
      if (_hiddenBuiltInPresetIds.contains(preset.id)) continue;
      if (_settingsMatchPreset(settings, preset.settings)) return preset.id;
    }
    return null;
  }

  bool _settingsMatchPreset(ReadingSettings current, ReadingSettings preset) {
    return current.appTheme == preset.appTheme &&
        current.readerTheme == preset.readerTheme &&
        current.appFontFamily == preset.appFontFamily &&
        current.fontFamily == preset.fontFamily &&
        current.fontWeight == preset.fontWeight &&
        current.fontSize == preset.fontSize &&
        current.textAlign == preset.textAlign &&
        current.pagingAxis == preset.pagingAxis &&
        current.contentDensity == preset.contentDensity &&
        current.enableCardDepth == preset.enableCardDepth &&
        current.blueLightFilter == preset.blueLightFilter &&
        current.blueLightIntensity == preset.blueLightIntensity &&
        current.dimText == preset.dimText &&
        current.dimTextIntensity == preset.dimTextIntensity &&
        current.useVolumeButtonsForPaging == preset.useVolumeButtonsForPaging &&
        current.readingInsightsEnabled == preset.readingInsightsEnabled &&
        current.speedReadWPM == preset.speedReadWPM &&
        current.speedReadDisplayMode == preset.speedReadDisplayMode &&
        current.speedReadPageAdvanceMode == preset.speedReadPageAdvanceMode &&
        current.speedReadAdaptivePacing == preset.speedReadAdaptivePacing &&
        current.lineHeight == preset.lineHeight &&
        current.sideMargin == preset.sideMargin &&
        current.useCustomReaderTheme == preset.useCustomReaderTheme &&
        mapEquals(
          current.customReaderTheme?.toJson(),
          preset.customReaderTheme?.toJson(),
        );
  }

  void _handlePresetAction(
    _PresetAction action,
    ReadingSettingsPreset preset, {
    required bool isBuiltIn,
  }) {
    switch (action) {
      case _PresetAction.update:
        if (!isBuiltIn) _updatePreset(preset);
        break;
      case _PresetAction.rename:
        if (!isBuiltIn) unawaited(_renamePreset(preset));
        break;
      case _PresetAction.delete:
        unawaited(
          isBuiltIn ? _hideBuiltInPreset(preset) : _deletePreset(preset),
        );
        break;
    }
  }

  Future<void> _renamePreset(ReadingSettingsPreset preset) async {
    final name = await _promptPresetName(
      title: 'Rename preset',
      initialValue: preset.name,
    );
    if (!mounted) return;
    if (name == null) return;
    await _savePresetList([
      for (final item in _presets)
        if (item.id == preset.id) item.copyWith(name: name) else item,
    ]);
  }

  Future<void> _deletePreset(ReadingSettingsPreset preset) async {
    final confirmed = await _confirmRemovePreset();
    if (!confirmed || !mounted) return;
    await _savePresetList([
      for (final item in _presets)
        if (item.id != preset.id) item,
    ]);
    if (!mounted) return;
    if (_activePresetId == preset.id) {
      setState(() {
        _activePresetId = null;
        _activePresetSettings = null;
      });
    }
  }

  Future<void> _hideBuiltInPreset(ReadingSettingsPreset preset) async {
    final confirmed = await _confirmRemovePreset();
    if (!confirmed || !mounted) return;
    final next = {..._hiddenBuiltInPresetIds, preset.id};
    setState(() {
      _hiddenBuiltInPresetIds = next;
      if (_activePresetId == preset.id) {
        _activePresetId = null;
        _activePresetSettings = null;
      }
    });
    await _settingsService.saveHiddenBuiltInPresetIds(next);
  }

  Future<bool> _confirmRemovePreset() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _localSettings.menuColor,
        title: Text(
          'Remove preset?',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _localSettings.textColor,
          ),
        ),
        content: Text(
          'This will remove this preset from your presets list.',
          style: GoogleFonts.inter(color: _localSettings.textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _updatePreset(ReadingSettingsPreset preset) {
    unawaited(
      _savePresetList([
        for (final item in _presets)
          if (item.id == preset.id)
            item.copyWith(
              settings: _localSettings.copyWith(clearBookThemePalette: true),
            )
          else
            item,
      ]),
    );
  }

  void _applyPreset(ReadingSettingsPreset preset) {
    final updated = preset.settings.copyWith(
      bookThemePalette: _localSettings.bookThemePalette,
    );
    _update(updated, activePresetId: preset.id);
  }

  CustomReaderTheme _customThemeSeed() {
    final current = _localSettings.copyWith(useCustomReaderTheme: false);
    return _localSettings.customReaderTheme ??
        CustomReaderTheme.fromSettings(current);
  }

  Future<void> _applyCustomTheme() async {
    final existing = _localSettings.customReaderTheme;
    if (existing == null) {
      await _editCustomTheme();
      return;
    }

    _update(
      _localSettings.copyWith(
        useCustomReaderTheme: true,
        customReaderTheme: existing,
      ),
    );
  }

  Future<void> _editCustomTheme() async {
    final seed = _customThemeSeed();
    final result = await showModalBottomSheet<CustomReaderTheme>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CustomReaderThemeEditor(
          initialTheme: seed,
          resetTheme: CustomReaderTheme.fromSettings(
            _localSettings.copyWith(useCustomReaderTheme: false),
          ),
          settings: _localSettings,
        );
      },
    );
    if (!mounted || result == null) return;
    _update(
      _localSettings.copyWith(
        useCustomReaderTheme: true,
        customReaderTheme: result,
      ),
    );
  }

  Widget _buildCategoryTabs({required double horizontalPadding}) {
    return Container(
      decoration: BoxDecoration(
        color: _localSettings.menuColor,
        border: Border(
          top: BorderSide(color: _hairlineColor, width: 0.8),
          bottom: BorderSide(color: _hairlineColor, width: 0.8),
        ),
      ),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          itemCount: _ReaderSettingsCategory.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final category = _ReaderSettingsCategory.values[index];
            final selected = category == _selectedCategory;
            return ChoiceChip(
              label: Text(_categoryLabel(category)),
              selected: selected,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              avatar: Icon(
                _categoryIcon(category),
                size: 15,
                color: selected ? _accent : _localSettings.mutedColor,
              ),
              labelStyle: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0,
                color: selected ? _accent : _localSettings.textColor,
              ),
              selectedColor: _selectedControlColor,
              backgroundColor: _controlColor,
              side: BorderSide(
                color: selected ? _accent : _hairlineColor,
                width: selected ? 1.2 : 0.8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onSelected: (_) {
                _selectCategory(category);
              },
            );
          },
        ),
      ),
    );
  }

  String _categoryLabel(_ReaderSettingsCategory category) {
    return switch (category) {
      _ReaderSettingsCategory.appearance => 'Appearance',
      _ReaderSettingsCategory.layout => 'Layout',
      _ReaderSettingsCategory.navigation => 'Navigation',
      _ReaderSettingsCategory.effects => 'Effects',
      _ReaderSettingsCategory.reading => 'Reading',
    };
  }

  IconData _categoryIcon(_ReaderSettingsCategory category) {
    return switch (category) {
      _ReaderSettingsCategory.appearance => Icons.palette_outlined,
      _ReaderSettingsCategory.layout => Icons.view_agenda_outlined,
      _ReaderSettingsCategory.navigation => Icons.swipe_outlined,
      _ReaderSettingsCategory.effects => Icons.dark_mode_outlined,
      _ReaderSettingsCategory.reading => Icons.insights_outlined,
    };
  }

  Widget _buildSelectedCategorySection() {
    return KeyedSubtree(
      key: ValueKey(_selectedCategory),
      child: switch (_selectedCategory) {
        _ReaderSettingsCategory.appearance => _buildAppearanceSettings(),
        _ReaderSettingsCategory.layout => _buildLayoutSettings(),
        _ReaderSettingsCategory.navigation => _buildNavigationSettings(),
        _ReaderSettingsCategory.effects => _buildEffectsSettings(),
        _ReaderSettingsCategory.reading => _buildReadingSettings(),
      },
    );
  }

  Widget _buildAppearanceSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection('Theme', _buildThemeChips()),
        _buildSection(
          'Typography',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSubLabel('Typeface'),
              _buildTypefaceRow(),
              const SizedBox(height: 8),
              _buildSubLabel('Size'),
              _buildFontSizeChips(),
              const SizedBox(height: 8),
              _buildSubLabel('Weight'),
              _buildFontWeightChips(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSection(
          'Layout',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSubLabel('Density'),
              _buildContentDensityChips(),
              const SizedBox(height: 8),
              _buildSubLabel('Alignment'),
              _buildTextAlignButtons(),
              const SizedBox(height: 8),
              _buildSubLabel('Line height'),
              _buildLineHeightSlider(),
              const SizedBox(height: 8),
              _buildSubLabel('Paragraph spacing'),
              _buildParagraphSpacingSlider(),
              const SizedBox(height: 8),
              _buildSubLabel('Side margins'),
              _buildSideMarginSlider(),
            ],
          ),
        ),
        _buildSection('Card Mode', _buildCardDepthToggle()),
      ],
    );
  }

  Widget _buildNavigationSettings() {
    return _buildSection(
      'Navigation',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubLabel('Swipe direction'),
          _buildPagingAxisButtons(),
          const SizedBox(height: 8),
          _buildReaderNavigationToggles(),
        ],
      ),
    );
  }

  Widget _buildReadingSettings() {
    return _buildSection(
      'Reading assistance',
      _buildReadingAssistanceToggles(),
    );
  }

  Widget _buildEffectsSettings() {
    return _buildSection('Effects', _buildVisualEffectsToggles());
  }

  Widget _buildTypefacePicker() {
    return Column(
      key: const ValueKey('settings-typeface'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDragHandle(),
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _setTypefacePickerVisible(false),
              icon: Icon(Icons.chevron_left_rounded, color: _accent),
              tooltip: 'Back',
            ),
            Expanded(
              child: Text(
                'Typeface',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _localSettings.textColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildTypefaceList(),
      ],
    );
  }

  String _themeLabel(AppTheme theme) {
    return switch (theme) {
      AppTheme.system => 'System-aware',
      AppTheme.softLight => 'Soft light',
      AppTheme.sepia => 'Sepia',
      AppTheme.newspaper => 'Newspaper',
      AppTheme.dark => 'Dark',
      AppTheme.amoled => 'AMOLED',
      AppTheme.bookLight => 'Book light',
      AppTheme.bookDark => 'Book dark',
    };
  }

  String _fontFamilyLabel(ReaderFontFamily family) {
    return switch (family) {
      ReaderFontFamily.literata => 'Literata',
      ReaderFontFamily.merriweather => 'Merriweather',
      ReaderFontFamily.lora => 'Lora',
      ReaderFontFamily.ebGaramond => 'EB Garamond',
      ReaderFontFamily.inter => 'Inter',
      ReaderFontFamily.robotoMono => 'Roboto Mono',
      ReaderFontFamily.atkinsonHyperlegible => 'Atkinson',
      ReaderFontFamily.lexend => 'Lexend',
    };
  }

  String _fontWeightLabel(ReaderFontWeight weight) {
    return switch (weight) {
      ReaderFontWeight.light => 'Light',
      ReaderFontWeight.regular => 'Reg',
      ReaderFontWeight.medium => 'Med',
      ReaderFontWeight.semiBold => 'Semi',
      ReaderFontWeight.bold => 'Bold',
    };
  }

  String _densityLabel(ContentDensity density) {
    return switch (density) {
      ContentDensity.low => 'Low',
      ContentDensity.medium => 'Medium',
      ContentDensity.high => 'High',
      ContentDensity.fullPage => 'Full',
    };
  }

  String _pagingAxisLabel(ReaderPagingAxis axis) {
    return switch (axis) {
      ReaderPagingAxis.vertical => 'Up/down',
      ReaderPagingAxis.horizontal => 'Left/right',
    };
  }

  IconData _alignIcon(ReaderTextAlign align) {
    return switch (align) {
      ReaderTextAlign.left => Icons.format_align_left,
      ReaderTextAlign.center => Icons.format_align_center,
      ReaderTextAlign.right => Icons.format_align_right,
      ReaderTextAlign.justify => Icons.format_align_justify,
    };
  }

  IconData _pagingAxisIcon(ReaderPagingAxis axis) {
    return switch (axis) {
      ReaderPagingAxis.vertical => Icons.swap_vert_rounded,
      ReaderPagingAxis.horizontal => Icons.swap_horiz_rounded,
    };
  }

  TextStyle _fontSampleStyle(
    ReaderFontFamily family,
    Color color, {
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: 0,
      color: color,
    );

    return switch (family) {
      ReaderFontFamily.inter => GoogleFonts.inter(textStyle: baseStyle),
      ReaderFontFamily.robotoMono => GoogleFonts.robotoMono(
        textStyle: baseStyle,
      ),
      ReaderFontFamily.merriweather => GoogleFonts.merriweather(
        textStyle: baseStyle,
      ),
      ReaderFontFamily.lora => GoogleFonts.lora(textStyle: baseStyle),
      ReaderFontFamily.ebGaramond => GoogleFonts.ebGaramond(
        textStyle: baseStyle,
      ),
      ReaderFontFamily.literata => GoogleFonts.literata(textStyle: baseStyle),
      ReaderFontFamily.atkinsonHyperlegible => GoogleFonts.atkinsonHyperlegible(
        textStyle: baseStyle,
      ),
      ReaderFontFamily.lexend => GoogleFonts.lexend(textStyle: baseStyle),
    };
  }

  Widget _buildOptionSurface({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
    Color? backgroundColor,
    double? height,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 7,
      vertical: 5,
    ),
  }) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color:
                  backgroundColor ??
                  (selected ? _selectedControlColor : _controlColor),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? _accent : _hairlineColor,
                width: selected ? 1.2 : 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: selected
                        ? (_localSettings.isDark ? 0.24 : 0.12)
                        : (_localSettings.isDark ? 0.10 : 0.05),
                  ),
                  blurRadius: selected ? 8 : 5,
                  offset: Offset(0, selected ? 3 : 2),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedControl<T>({
    required List<T> values,
    required T selectedValue,
    required String Function(T value) labelBuilder,
    required ValueChanged<T> onSelected,
    Widget Function(T value, bool selected)? iconBuilder,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _controlColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor, width: 0.8),
        boxShadow: _softShadow,
      ),
      child: Row(
        children: values.map((value) {
          final selected = value == selectedValue;
          final foreground = selected ? _accent : _localSettings.textColor;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: true,
                selected: selected,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => onSelected(value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? _localSettings.backgroundColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: selected
                            ? Border.all(color: _accent, width: 1.2)
                            : null,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: _localSettings.isDark ? 0.22 : 0.12,
                                  ),
                                  blurRadius: 7,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child:
                          iconBuilder?.call(value, selected) ??
                          Text(
                            labelBuilder(value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              letterSpacing: 0,
                              color: foreground,
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildThemeChips() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBookPalette = _localSettings.bookThemePalette != null;
        final themes = kReaderThemeChoices.where((theme) {
          if (theme != AppTheme.bookLight && theme != AppTheme.bookDark) {
            return true;
          }
          return hasBookPalette;
        }).toList();
        const spacing = 6.0;
        final itemCount = themes.length + 1;
        final columns = ((constraints.maxWidth + spacing) / (44 + spacing))
            .floor()
            .clamp(3, itemCount);
        final tileSize =
            ((constraints.maxWidth - (spacing * (columns - 1))) / columns)
                .clamp(42.0, 50.0)
                .toDouble();

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            ...themes.map((theme) {
              final isSelected =
                  !_localSettings.useCustomReaderTheme &&
                  _localSettings.effectiveTheme == theme;
              final previewSettings = ReadingSettings(
                appTheme: theme,
                bookThemePalette: _localSettings.bookThemePalette,
              );

              return Tooltip(
                message: _themeLabel(theme),
                child: SizedBox.square(
                  dimension: tileSize,
                  child: _buildOptionSurface(
                    selected: isSelected,
                    onTap: () => _update(
                      _localSettings.copyWith(
                        readerTheme: theme,
                        useCustomReaderTheme: false,
                      ),
                    ),
                    backgroundColor: previewSettings.backgroundColor,
                    padding: EdgeInsets.zero,
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            'Aa',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                              color: previewSettings.textColor,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 13,
                              color: previewSettings.accentColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            Tooltip(
              message: 'Custom',
              child: SizedBox.square(
                dimension: tileSize,
                child: _buildOptionSurface(
                  selected: _localSettings.isCustomReaderThemeActive,
                  onTap: _applyCustomTheme,
                  backgroundColor:
                      (_localSettings.customReaderTheme ?? _customThemeSeed())
                          .readerBackground,
                  padding: EdgeInsets.zero,
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color:
                              (_localSettings.customReaderTheme ??
                                      _customThemeSeed())
                                  .accent,
                        ),
                      ),
                      Positioned(
                        left: 5,
                        bottom: 5,
                        child: Text(
                          'My',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color:
                                (_localSettings.customReaderTheme ??
                                        _customThemeSeed())
                                    .text,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: IconButton(
                          tooltip: 'Edit custom reader theme',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 24,
                            height: 24,
                          ),
                          onPressed: _editCustomTheme,
                          icon: Icon(
                            Icons.edit_rounded,
                            size: 12,
                            color:
                                (_localSettings.customReaderTheme ??
                                        _customThemeSeed())
                                    .icon,
                          ),
                        ),
                      ),
                      if (_localSettings.isCustomReaderThemeActive)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 13,
                            color:
                                (_localSettings.customReaderTheme ??
                                        _customThemeSeed())
                                    .accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFontSizeChips() {
    return _buildSegmentedControl<ReaderFontSize>(
      values: ReaderFontSize.values,
      selectedValue: _localSettings.fontSize,
      labelBuilder: (size) => size.name.toUpperCase(),
      onSelected: (size) => _update(_localSettings.copyWith(fontSize: size)),
    );
  }

  Widget _buildFontWeightChips() {
    return _buildSegmentedControl<ReaderFontWeight>(
      values: ReaderFontWeight.values,
      selectedValue: _localSettings.fontWeight,
      labelBuilder: _fontWeightLabel,
      onSelected: (weight) =>
          _update(_localSettings.copyWith(fontWeight: weight)),
    );
  }

  Widget _buildTypefaceRow() {
    final selectedFamily = _localSettings.fontFamily;

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: _controlColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _hairlineColor, width: 0.8),
          boxShadow: _softShadow,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _setTypefacePickerVisible(true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Text(
                  'Aa',
                  style: _fontSampleStyle(
                    selectedFamily,
                    _accent,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _fontFamilyLabel(selectedFamily),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: _localSettings.textColor,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: _accent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypefaceList() {
    return Container(
      decoration: BoxDecoration(
        color: _groupSurfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor, width: 0.8),
        boxShadow: _softShadow,
      ),
      child: Column(
        children: ReaderFontFamily.values.map((family) {
          final isSelected = _localSettings.fontFamily == family;
          final foreground = isSelected ? _accent : _localSettings.textColor;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                _update(_localSettings.copyWith(fontFamily: family));
                _setTypefacePickerVisible(false);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                constraints: BoxConstraints(minHeight: isSelected ? 54 : 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _selectedControlColor
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: _accent, width: 1.2)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _localSettings.isDark ? 0.22 : 0.12,
                            ),
                            blurRadius: 7,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Text(
                      'Aa',
                      style: _fontSampleStyle(family, foreground, fontSize: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fontFamilyLabel(family),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          letterSpacing: 0,
                          color: foreground,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_rounded, color: _accent, size: 18),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextAlignButtons() {
    return _buildSegmentedControl<ReaderTextAlign>(
      values: ReaderTextAlign.values,
      selectedValue: _localSettings.textAlign,
      labelBuilder: (align) => align.name,
      onSelected: (align) => _update(_localSettings.copyWith(textAlign: align)),
      iconBuilder: (align, isSelected) {
        return Icon(
          _alignIcon(align),
          size: 20,
          color: isSelected ? _accent : _localSettings.textColor,
        );
      },
    );
  }

  Widget _buildContentDensityChips() {
    return _buildSegmentedControl<ContentDensity>(
      values: ContentDensity.values,
      selectedValue: _localSettings.contentDensity,
      labelBuilder: _densityLabel,
      onSelected: (density) =>
          _update(_localSettings.copyWith(contentDensity: density)),
    );
  }

  Widget _buildPagingAxisButtons() {
    return _buildSegmentedControl<ReaderPagingAxis>(
      values: ReaderPagingAxis.values,
      selectedValue: _localSettings.pagingAxis,
      labelBuilder: _pagingAxisLabel,
      onSelected: (axis) => _update(_localSettings.copyWith(pagingAxis: axis)),
      iconBuilder: (axis, isSelected) {
        final color = isSelected ? _accent : _localSettings.textColor;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_pagingAxisIcon(axis), size: 18, color: color),
            Text(
              _pagingAxisLabel(axis),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLineHeightSlider() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: _controlColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _selectedControlColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.45)),
            ),
            child: Text(
              '${_localSettings.lineHeight.toStringAsFixed(1)}x',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.5,
                activeTrackColor: _accent,
                inactiveTrackColor: _localSettings.mutedColor.withValues(
                  alpha: 0.18,
                ),
                thumbColor: _accent,
                overlayColor: _accent.withValues(alpha: 0.12),
              ),
              child: Slider(
                min: 1.0,
                max: 2.2,
                divisions: 12,
                value: _localSettings.lineHeight.clamp(1.0, 2.2),
                onChanged: (val) {
                  setState(() {
                    _localSettings = _localSettings.copyWith(lineHeight: val);
                  });
                  // Calculate a slight scale change based on the slider range
                  final scaleOffset = ((val - 1.0) / 1.2) * 0.05;
                  widget.onLiveScaleUpdate?.call(1.0 - scaleOffset);
                },
                onChangeEnd: (val) {
                  widget.onLiveScaleUpdate?.call(1.0);
                  _update(_localSettings);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParagraphSpacingSlider() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: _controlColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _selectedControlColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.45)),
            ),
            child: Text(
              '${_localSettings.paragraphSpacing.toStringAsFixed(1)}x',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.5,
                activeTrackColor: _accent,
                inactiveTrackColor: _localSettings.mutedColor.withValues(
                  alpha: 0.18,
                ),
                thumbColor: _accent,
                overlayColor: _accent.withValues(alpha: 0.12),
              ),
              child: Slider(
                max: 2.0,
                divisions: 20,
                value: _localSettings.paragraphSpacing.clamp(0.0, 2.0),
                onChanged: (val) {
                  setState(() {
                    _localSettings = _localSettings.copyWith(
                      paragraphSpacing: val,
                    );
                  });
                },
                onChangeEnd: (_) => _update(_localSettings),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideMarginSlider() {
    final sideMargin = readerHorizontalContentPadding(_localSettings);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: _controlColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _selectedControlColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.45)),
            ),
            child: Text(
              '${sideMargin.round()}px',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.5,
                activeTrackColor: _accent,
                inactiveTrackColor: _localSettings.mutedColor.withValues(
                  alpha: 0.18,
                ),
                thumbColor: _accent,
                overlayColor: _accent.withValues(alpha: 0.12),
              ),
              child: Slider(
                min: kReaderSideMarginMin,
                max: kReaderSideMarginMax,
                divisions: (kReaderSideMarginMax - kReaderSideMarginMin)
                    .round(),
                value: sideMargin,
                onChanged: (val) {
                  setState(() {
                    _localSettings = _localSettings.copyWith(sideMargin: val);
                  });
                },
                onChangeEnd: (_) => _update(_localSettings),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualEffectsToggles() {
    return Container(
      decoration: BoxDecoration(
        color: _controlColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor),
      ),
      child: Column(
        children: [
          _buildSwitchRow(
            title: 'Blue light filter',
            subtitle: 'Warms text and bright details without washing the page',
            value: _localSettings.blueLightFilter,
            onChanged: (val) {
              _update(_localSettings.copyWith(blueLightFilter: val));
            },
          ),
          if (_localSettings.blueLightFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.brightness_low_rounded,
                    color: _localSettings.mutedColor,
                    size: 18,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2.5,
                        activeTrackColor: _accent,
                        inactiveTrackColor: _localSettings.mutedColor
                            .withValues(alpha: 0.15),
                        thumbColor: _accent,
                        overlayColor: _accent.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: _localSettings.blueLightIntensity,
                        min: 0.1,
                        max: 0.5,
                        divisions: 8,
                        onChanged: (val) {
                          _update(
                            _localSettings.copyWith(blueLightIntensity: val),
                          );
                        },
                      ),
                    ),
                  ),
                  Icon(Icons.brightness_high_rounded, color: _accent, size: 18),
                ],
              ),
            ),
          Divider(height: 1, color: _hairlineColor),
          _buildSwitchRow(
            title: 'Dim text',
            subtitle: 'Soften text brightness for dark reading',
            value: _localSettings.dimText,
            onChanged: (val) {
              _update(_localSettings.copyWith(dimText: val));
            },
          ),
          if (_localSettings.dimText)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.dark_mode_outlined,
                    color: _localSettings.mutedColor,
                    size: 18,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2.5,
                        activeTrackColor: _accent,
                        inactiveTrackColor: _localSettings.mutedColor
                            .withValues(alpha: 0.15),
                        thumbColor: _accent,
                        overlayColor: _accent.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: _localSettings.dimTextIntensity,
                        min: 0.05,
                        max: 0.4,
                        divisions: 7,
                        onChanged: (val) {
                          _update(
                            _localSettings.copyWith(dimTextIntensity: val),
                          );
                        },
                      ),
                    ),
                  ),
                  Icon(Icons.dark_mode_rounded, color: _accent, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardDepthToggle() {
    return Container(
      decoration: BoxDecoration(
        color: _controlColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor),
      ),
      child: _buildSwitchRow(
        title: 'Card Mode',
        subtitle: 'Shadow on reading cards',
        value: _localSettings.enableCardDepth,
        onChanged: (val) {
          _update(_localSettings.copyWith(enableCardDepth: val));
        },
      ),
    );
  }

  Widget _buildReaderNavigationToggles() {
    return Container(
      decoration: BoxDecoration(
        color: _controlColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor),
      ),
      child: _buildSwitchRow(
        title: 'Volume buttons',
        subtitle: 'Use volume down/up for next and previous page',
        value: _localSettings.useVolumeButtonsForPaging,
        onChanged: (val) {
          _update(_localSettings.copyWith(useVolumeButtonsForPaging: val));
        },
      ),
    );
  }

  Widget _buildReadingAssistanceToggles() {
    return Container(
      decoration: BoxDecoration(
        color: _controlColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hairlineColor),
      ),
      child: Column(
        children: [
          _buildSwitchRow(
            title: 'Reading insights',
            subtitle: 'Estimate pace, time left, and completion stats',
            value: _localSettings.readingInsightsEnabled,
            onChanged: (val) {
              _update(_localSettings.copyWith(readingInsightsEnabled: val));
            },
          ),
          if (_localSettings.readingInsightsEnabled) ...[
            Divider(height: 1, color: _hairlineColor),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onResetReadingPace,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Reset reading pace',
                          style: _bodyLabelStyle,
                        ),
                      ),
                      Icon(Icons.restart_alt_rounded, color: _accent, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _bodyLabelStyle),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _localSettings.mutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: _accent,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// A custom slider track shape that draws vertical ticks based on given ratios (0.0 - 1.0)
class _ChapterMarksTrackShape extends RoundedRectSliderTrackShape {
  final List<double> markRatios;

  const _ChapterMarksTrackShape({required this.markRatios});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    double additionalActiveTrackHeight = 2,
  }) {
    // Pain the normal track first
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
      textDirection: textDirection,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );

    // Then draw the tick marks over the track
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final paint = Paint()
      ..color =
          sliderTheme.inactiveTrackColor?.withValues(alpha: 0.8) ?? Colors.grey
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final double trackTop = trackRect.top;
    final double trackBottom = trackRect.bottom;
    final double trackWidth = trackRect.width;
    final double trackLeft = trackRect.left;

    for (final ratio in markRatios) {
      if (ratio < 0.0 || ratio > 1.0) continue;
      final x = trackLeft + (trackWidth * ratio);
      context.canvas.drawLine(
        Offset(x, trackTop - 2), // Slightly taller than track
        Offset(x, trackBottom + 2),
        paint,
      );
    }
  }
}

/// A pill-shaped slider thumb for a more premium scrubber look.
class _PillSliderThumbShape extends SliderComponentShape {
  final double enabledThumbRadius;

  const _PillSliderThumbShape() : enabledThumbRadius = 10.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(enabledThumbRadius * 1.5, enabledThumbRadius * 2.5);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? const Color(0xFFE85D04)
      ..style = PaintingStyle.fill;

    // Draw pill shape
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: enabledThumbRadius * 1.2,
        height: enabledThumbRadius * 2.2,
      ),
      Radius.circular(enabledThumbRadius * 0.6),
    );
    canvas.drawRRect(rect, paint);

    // Inner highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center.translate(-1, -1),
        width: enabledThumbRadius * 0.6,
        height: enabledThumbRadius * 1.4,
      ),
      Radius.circular(enabledThumbRadius * 0.3),
    );
    canvas.drawRRect(innerRect, highlightPaint);
  }
}

enum _ReaderThemeColorToken {
  readerBackground,
  cardBackground,
  text,
  secondaryText,
  border,
  accent,
  icon,
  inactiveControl,
  selection,
  highlight,
  bookmark,
  cardShadow,
  speedReadActive,
  speedReadInactive,
}

class _CustomReaderThemeEditor extends StatefulWidget {
  final CustomReaderTheme initialTheme;
  final CustomReaderTheme resetTheme;
  final ReadingSettings settings;

  const _CustomReaderThemeEditor({
    required this.initialTheme,
    required this.resetTheme,
    required this.settings,
  });

  @override
  State<_CustomReaderThemeEditor> createState() =>
      _CustomReaderThemeEditorState();
}

class _CustomReaderThemeEditorState extends State<_CustomReaderThemeEditor> {
  late CustomReaderTheme _draft = widget.initialTheme;

  double _contrast(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  List<String> get _warnings {
    final warnings = <String>[];
    if (_contrast(_draft.text, _draft.cardBackground) < 4.5) {
      warnings.add('Low contrast may make book text hard to read.');
    }
    if (_contrast(_draft.secondaryText, _draft.cardBackground) < 3.0) {
      warnings.add('Low contrast may make secondary text hard to read.');
    }
    return warnings;
  }

  void _setToken(_ReaderThemeColorToken token, Color color) {
    final value = color.toARGB32();
    setState(() {
      _draft = switch (token) {
        _ReaderThemeColorToken.readerBackground => _draft.copyWith(
          readerBackgroundColor: value,
        ),
        _ReaderThemeColorToken.cardBackground => _draft.copyWith(
          cardBackgroundColor: value,
        ),
        _ReaderThemeColorToken.text => _draft.copyWith(textColor: value),
        _ReaderThemeColorToken.secondaryText => _draft.copyWith(
          secondaryTextColor: value,
        ),
        _ReaderThemeColorToken.border => _draft.copyWith(borderColor: value),
        _ReaderThemeColorToken.accent => _draft.copyWith(accentColor: value),
        _ReaderThemeColorToken.icon => _draft.copyWith(iconColor: value),
        _ReaderThemeColorToken.inactiveControl => _draft.copyWith(
          inactiveControlColor: value,
        ),
        _ReaderThemeColorToken.selection => _draft.copyWith(
          selectionColor: value,
        ),
        _ReaderThemeColorToken.highlight => _draft.copyWith(
          highlightDefaultColor: value,
        ),
        _ReaderThemeColorToken.bookmark => _draft.copyWith(
          bookmarkColor: value,
        ),
        _ReaderThemeColorToken.cardShadow => _draft.copyWith(
          cardShadowColor: value,
        ),
        _ReaderThemeColorToken.speedReadActive => _draft.copyWith(
          speedReadActiveWordColor: value,
        ),
        _ReaderThemeColorToken.speedReadInactive => _draft.copyWith(
          speedReadInactiveWordColor: value,
        ),
      };
    });
  }

  Future<void> _pickColor(
    _ReaderThemeColorToken token,
    String label,
    Color color,
  ) async {
    final picked = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReaderThemeColorPickerSheet(
        title: label,
        initialColor: color,
        theme: _draft,
      ),
    );
    if (picked != null) _setToken(token, picked);
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: _draft.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _field(_ReaderThemeColorToken token, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _ReaderThemeColorField(
        label: label,
        color: color,
        theme: _draft,
        onChanged: (color) => _setToken(token, color),
        onTapPicker: () => _pickColor(token, label, color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 16;
    final warnings = _warnings;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.58,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: _draft.overlayBackground ?? _draft.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: _draft.border)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _draft.secondaryText.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Custom reader theme',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _draft.text,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _draft = widget.resetTheme),
                        child: const Text('Reset'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(_draft),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: EdgeInsets.fromLTRB(18, 0, 18, bottom),
                    children: [
                      _ReaderThemePreview(theme: _draft),
                      if (warnings.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        for (final warning in warnings)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _draft.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _draft.accent.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 17,
                                  color: _draft.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    warning,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _draft.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 16),
                      _section('Base', [
                        _field(
                          _ReaderThemeColorToken.readerBackground,
                          'Background',
                          _draft.readerBackground,
                        ),
                        _field(
                          _ReaderThemeColorToken.cardBackground,
                          'Card',
                          _draft.cardBackground,
                        ),
                        _field(
                          _ReaderThemeColorToken.text,
                          'Text',
                          _draft.text,
                        ),
                        _field(
                          _ReaderThemeColorToken.secondaryText,
                          'Secondary text',
                          _draft.secondaryText,
                        ),
                        _field(
                          _ReaderThemeColorToken.border,
                          'Border',
                          _draft.border,
                        ),
                      ]),
                      _section('Accent', [
                        _field(
                          _ReaderThemeColorToken.accent,
                          'Accent',
                          _draft.accent,
                        ),
                        _field(
                          _ReaderThemeColorToken.icon,
                          'Icons',
                          _draft.icon,
                        ),
                        _field(
                          _ReaderThemeColorToken.inactiveControl,
                          'Inactive controls',
                          _draft.inactiveControl,
                        ),
                      ]),
                      _section('Reader Extras', [
                        _field(
                          _ReaderThemeColorToken.selection,
                          'Selection',
                          _draft.selection,
                        ),
                        _field(
                          _ReaderThemeColorToken.highlight,
                          'Highlight',
                          _draft.highlightDefault,
                        ),
                        _field(
                          _ReaderThemeColorToken.bookmark,
                          'Bookmark',
                          _draft.bookmark,
                        ),
                        _field(
                          _ReaderThemeColorToken.cardShadow,
                          'Card shadow',
                          _draft.cardShadow,
                        ),
                      ]),
                      _section('Speed Read', [
                        _field(
                          _ReaderThemeColorToken.speedReadActive,
                          'Active word',
                          _draft.speedReadActiveWord ?? _draft.text,
                        ),
                        _field(
                          _ReaderThemeColorToken.speedReadInactive,
                          'Dimmed words',
                          _draft.speedReadInactiveWord ??
                              _draft.text.withValues(alpha: 0.38),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReaderThemePreview extends StatelessWidget {
  final CustomReaderTheme theme;

  const _ReaderThemePreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.readerBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.border),
          boxShadow: [
            BoxShadow(
              color: theme.cardShadow,
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chapter preview',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.secondaryText,
                    ),
                  ),
                ),
                Icon(Icons.bookmark_rounded, color: theme.bookmark, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A quiet page should feel readable before it feels decorated.',
              style: GoogleFonts.literata(
                fontSize: 18,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: theme.text,
              ),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Selected text',
                    style: TextStyle(backgroundColor: theme.selection),
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'highlighted text',
                    style: TextStyle(backgroundColor: theme.highlightDefault),
                  ),
                  const TextSpan(text: ' stay visible.'),
                ],
              ),
              style: GoogleFonts.inter(
                fontSize: 12,
                height: 1.4,
                color: theme.text,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: 0.42,
                backgroundColor: theme.inactiveControl,
                valueColor: AlwaysStoppedAnimation(theme.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderThemeColorField extends StatefulWidget {
  final String label;
  final Color color;
  final CustomReaderTheme theme;
  final ValueChanged<Color> onChanged;
  final VoidCallback onTapPicker;

  const _ReaderThemeColorField({
    required this.label,
    required this.color,
    required this.theme,
    required this.onChanged,
    required this.onTapPicker,
  });

  @override
  State<_ReaderThemeColorField> createState() => _ReaderThemeColorFieldState();
}

class _ReaderThemeColorFieldState extends State<_ReaderThemeColorField> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: colorToHex(widget.color));
  }

  @override
  void didUpdateWidget(_ReaderThemeColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color.toARGB32() != widget.color.toARGB32()) {
      _controller.text = colorToHex(widget.color);
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleHexChanged(String value) {
    final parsed = hexToColor(value);
    setState(() => _error = parsed == null ? 'Invalid HEX' : null);
    if (parsed != null) widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.theme.readerBackground.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.theme.border),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: widget.onTapPicker,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: widget.theme.border),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: widget.theme.text,
              ),
            ),
          ),
          SizedBox(
            width: 116,
            child: TextField(
              controller: _controller,
              onChanged: _handleHexChanged,
              textCapitalization: TextCapitalization.characters,
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.theme.text,
              ),
              decoration: InputDecoration(
                isDense: true,
                errorText: _error,
                errorMaxLines: 1,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 8,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Pick ${widget.label}',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onTapPicker,
            icon: Icon(Icons.colorize_rounded, color: widget.theme.icon),
          ),
        ],
      ),
    );
  }
}

class _ReaderThemeColorPickerSheet extends StatefulWidget {
  final String title;
  final Color initialColor;
  final CustomReaderTheme theme;

  const _ReaderThemeColorPickerSheet({
    required this.title,
    required this.initialColor,
    required this.theme,
  });

  @override
  State<_ReaderThemeColorPickerSheet> createState() =>
      _ReaderThemeColorPickerSheetState();
}

class _ReaderThemeColorPickerSheetState
    extends State<_ReaderThemeColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initialColor);
  late final TextEditingController _hexController = TextEditingController(
    text: colorToHex(widget.initialColor),
  );
  String? _error;

  Color get _color => _hsv.toColor();

  void _setColor(Color color, {bool updateText = true}) {
    setState(() {
      _hsv = HSVColor.fromColor(color);
      _error = null;
      if (updateText) _hexController.text = colorToHex(color);
    });
  }

  void _handleHex(String value) {
    final parsed = hexToColor(value);
    setState(() => _error = parsed == null ? 'Enter #RRGGBB' : null);
    if (parsed != null) _setColor(parsed, updateText: false);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final bottom = MediaQuery.paddingOf(context).bottom + 16;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, bottom),
      decoration: BoxDecoration(
        color: theme.overlayBackground ?? theme.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: theme.text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_color),
                  child: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: _ReaderThemeColorWheel(
                color: _hsv,
                onChanged: (color) => _setColor(color.toColor()),
              ),
            ),
            Slider(
              value: _hsv.value,
              activeColor: theme.accent,
              inactiveColor: theme.inactiveControl,
              onChanged: (value) => _setColor(_hsv.withValue(value).toColor()),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.border),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    onChanged: _handleHex,
                    textCapitalization: TextCapitalization.characters,
                    style: GoogleFonts.robotoMono(color: theme.text),
                    decoration: InputDecoration(
                      labelText: 'HEX',
                      errorText: _error,
                      helperText: '#RRGGBB or #AARRGGBB',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderThemeColorWheel extends StatelessWidget {
  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  const _ReaderThemeColorWheel({required this.color, required this.onChanged});

  void _updateColor(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final vector = localPosition - center;
    final radius = math.min(size.width, size.height) / 2;
    final distance = vector.distance.clamp(0.0, radius);
    final saturation = (distance / radius).clamp(0.0, 1.0);
    final hue =
        ((math.atan2(vector.dy, vector.dx) * 180 / math.pi) + 360) % 360;
    onChanged(HSVColor.fromAHSV(1, hue, saturation, color.value));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size.square(
          math.min(constraints.maxWidth, constraints.maxHeight),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => _updateColor(details.localPosition, size),
          onPanUpdate: (details) => _updateColor(details.localPosition, size),
          child: CustomPaint(
            size: size,
            painter: _ReaderThemeColorWheelPainter(color: color),
          ),
        );
      },
    );
  }
}

class _ReaderThemeColorWheelPainter extends CustomPainter {
  final HSVColor color;

  const _ReaderThemeColorWheelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    if (color.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - color.value),
      );
    }
    canvas.restore();

    canvas.drawCircle(
      center,
      radius - 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    final selectorAngle = color.hue * math.pi / 180;
    final selectorOffset = Offset(
      center.dx + math.cos(selectorAngle) * color.saturation * radius,
      center.dy + math.sin(selectorAngle) * color.saturation * radius,
    );
    canvas.drawCircle(
      selectorOffset,
      13,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(selectorOffset, 10, Paint()..color = color.toColor());
    canvas.drawCircle(
      selectorOffset,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ReaderThemeColorWheelPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _PageAnchor {
  final String opening;
  final String middle;

  const _PageAnchor({required this.opening, required this.middle});
}

class _ReaderVisiblePositionSnapshot {
  final int displayIndex;
  final double? pageControllerPage;
  final int? pageControllerIndex;
  final _PageAnchor? sourceAnchor;
  final List<int> sourceOriginalCandidates;
  final int? displayChunkCount;
  final bool? cardMode;
  final double? densityMultiplier;
  final bool hasPreferredDisplayIndex;

  const _ReaderVisiblePositionSnapshot({
    required this.displayIndex,
    this.pageControllerPage,
    this.pageControllerIndex,
    this.sourceAnchor,
    this.sourceOriginalCandidates = const [],
    this.displayChunkCount,
    this.cardMode,
    this.densityMultiplier,
    this.hasPreferredDisplayIndex = false,
  });
}

class _AnalyticsChapter {
  final String id;
  final String title;
  final int startChunkIndex;
  final int endChunkIndex;
  final int wordCount;

  const _AnalyticsChapter({
    required this.id,
    required this.title,
    required this.startChunkIndex,
    required this.endChunkIndex,
    required this.wordCount,
  });
}
