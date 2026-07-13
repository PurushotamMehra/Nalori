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
import '../models/book_metadata.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/quote_share_payload.dart';
import '../models/reading_settings.dart';
import '../models/reader_position_session.dart';
import '../services/bookmark_service.dart';
import '../services/dictionary_service.dart';
import '../services/display_generation_coordinator.dart';
import '../services/display_section_memory_cache.dart';
import '../services/frame_budgeted_range_scheduler.dart';
import '../services/progressive_display_state.dart';
import '../services/segmented_display_cache_service.dart';
import '../services/highlight_palette_service.dart';
import '../services/highlight_service.dart';
import '../services/book_cache_service.dart';
import '../services/card_depth_chapter_progress_service.dart';
import '../services/chapter_navigation_service.dart';
import '../services/lazy_book_session.dart';
import '../services/lazy_parsed_book.dart';
import '../services/lazy_section_repository.dart';
import '../services/reader_open_service.dart';
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
import '../utils/final_layout_paragraphs.dart';
import '../utils/reader_content_parser.dart';
import 'quote_card_preview_screen.dart';
import 'search_screen.dart';
import 'book_image_viewer_screen.dart';
import '../utils/text_span_utils.dart';
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
LazySectionWorkPriority lazySectionPriorityForReaderReason(String reason) {
  if (reason.startsWith('next_page_') ||
      reason.startsWith('previous_page_') ||
      reason.contains('source_anchor_navigation') ||
      reason.contains('card_depth_current_chapter')) {
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
}) {
  if (locationsByChunkIndex.isEmpty) return List<Highlight>.from(highlights);
  final resolved = <Highlight>[];
  for (final highlight in highlights) {
    final stable = highlight.stableLocation;
    if (stable == null) {
      resolved.add(highlight);
      continue;
    }

    int? currentIndex;
    for (final entry in locationsByChunkIndex.entries) {
      final current = entry.value;
      final publicationMatches =
          stable.publicationFingerprint == null ||
          current.publicationFingerprint == null ||
          stable.publicationFingerprint == current.publicationFingerprint;
      if (publicationMatches &&
          stable.bookId == current.bookId &&
          stable.spineIndex == current.spineIndex &&
          stable.localChunkIndex != null &&
          stable.localChunkIndex == current.localChunkIndex) {
        currentIndex = entry.key;
        break;
      }
    }
    if (currentIndex == null) continue;
    resolved.add(
      currentIndex == highlight.originalChunkIndex
          ? highlight
          : highlight.copyWith(originalChunkIndex: currentIndex),
    );
  }
  return resolved;
}

typedef ProgressiveDisplayRangeGenerator =
    Future<DisplayRangeResult> Function(DisplayRangeRequest request);

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
       initialSettings = settings;

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
const double kReaderDialogueTextInset = 0.0;
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

  final lineHeightPx = settings.fontSizeValue * settings.lineHeight;
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
  final len = text.length;
  if (len == 0) return 0;
  int count = 0;
  bool inWord = false;
  for (int i = 0; i < len; i++) {
    final c = text.codeUnitAt(i);
    final isSpace = c == 32 || c == 9 || c == 10 || c == 13;
    if (!isSpace) {
      if (!inWord) {
        count++;
        inWord = true;
      }
    } else {
      inWord = false;
    }
  }
  return count;
}

TextAlign resolveReaderChunkTextAlign(
  BookChunk chunk,
  ReadingSettings settings,
) {
  if (chunk.isHeading) return TextAlign.center;

  final publisherAlign = chunk.publisherTextAlign;
  if (chunk.usesPublisherLayout && publisherAlign != null) {
    return switch (publisherAlign) {
      BookTextAlign.left => TextAlign.left,
      BookTextAlign.center => TextAlign.center,
      BookTextAlign.right => TextAlign.right,
      BookTextAlign.justify => TextAlign.justify,
    };
  }

  if (chunk.blockRole == BookBlockRole.poem ||
      chunk.blockRole == BookBlockRole.stanza ||
      chunk.blockRole == BookBlockRole.preformatted ||
      chunk.blockRole == BookBlockRole.table) {
    return TextAlign.left;
  }

  return settings.resolvedTextAlign;
}

EdgeInsets resolveReaderPublisherPadding(BookChunk chunk) {
  if (!chunk.usesPublisherLayout) return EdgeInsets.zero;

  return EdgeInsets.only(
    left: chunk.publisherLeftIndent.clamp(0, 72).toDouble(),
    right: chunk.publisherRightIndent.clamp(0, 72).toDouble(),
  );
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

bool _isReaderWhitespace(String char) => char.trim().isEmpty;

bool _isReaderSentenceTerminator(String char) =>
    char == '.' || char == '!' || char == '?' || char == '…';

bool _isReaderSentenceCloser(String char) =>
    char == '"' ||
    char == "'" ||
    char == ')' ||
    char == ']' ||
    char == '}' ||
    char == '”' ||
    char == '’' ||
    char == '»';

bool _isReaderAsciiLetter(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

bool _isLikelyReaderAbbreviation(String text, int periodIndex) {
  var wordStart = periodIndex - 1;
  while (wordStart >= 0) {
    if (!_isReaderAsciiLetter(text[wordStart])) break;
    wordStart--;
  }

  final word = text.substring(wordStart + 1, periodIndex).toLowerCase();
  if (word.isEmpty) return false;
  const abbreviations = {
    'mr',
    'mrs',
    'ms',
    'dr',
    'prof',
    'st',
    'jr',
    'sr',
    'vs',
    'etc',
  };
  return abbreviations.contains(word) || word.length == 1;
}

String _readerNextWord(String text, int start) {
  var index = start;
  while (index < text.length && _isReaderWhitespace(text[index])) {
    index++;
  }

  final wordStart = index;
  while (index < text.length && _isReaderAsciiLetter(text[index])) {
    index++;
  }

  return text.substring(wordStart, index).toLowerCase();
}

bool _continuesWithDialogueAttribution(String text, int start) {
  const attributionWords = {
    'said',
    'asked',
    'cried',
    'replied',
    'returned',
    'remarked',
    'answered',
    'continued',
    'whispered',
    'shouted',
    'murmured',
    'exclaimed',
  };
  return attributionWords.contains(_readerNextWord(text, start));
}

bool readerTextEndsAtSentenceBoundary(String text) {
  var index = text.trimRight().length - 1;
  if (index < 0) return true;

  while (index >= 0 && _isReaderSentenceCloser(text[index])) {
    index--;
  }
  return index >= 0 && _isReaderSentenceTerminator(text[index]);
}

List<({int start, int end})> readerSentenceRanges(String text) {
  if (text.isEmpty) return const [];

  final ranges = <({int start, int end})>[];
  var start = 0;
  var index = 0;

  while (index < text.length) {
    final char = text[index];
    if (!_isReaderSentenceTerminator(char)) {
      index++;
      continue;
    }

    if (char == '.' && _isLikelyReaderAbbreviation(text, index)) {
      index++;
      continue;
    }

    var end = index + 1;
    while (end < text.length && _isReaderSentenceCloser(text[end])) {
      end++;
    }

    if (_continuesWithDialogueAttribution(text, end)) {
      index++;
      continue;
    }

    if (end < text.length && !_isReaderWhitespace(text[end])) {
      index++;
      continue;
    }

    while (end < text.length && _isReaderWhitespace(text[end])) {
      end++;
    }

    if (start < end) {
      ranges.add((start: start, end: end));
    }
    start = end;
    index = end;
  }

  if (start < text.length) {
    ranges.add((start: start, end: text.length));
  }

  return ranges;
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  LazyBookSession? _lazySession;
  bool _lazyHasContentAfter = false;
  bool _isLoadingLazyBackwardSection = false;
  int? _lazyMaxLoadedSpineIndex;
  bool _isLoadingLazyForwardSection = false;
  final Map<DisplayRangeDirection, Future<bool>> _activeLazyAdjacentLoads = {};
  String? _activeCardDepthChapterCompletionKey;
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
  bool _hasDeferredRestoreWhileInactive = false;
  int? _deferredRestoreNavigationGeneration;
  int _readerSurfaceBlockCount = 0;
  bool _cardInteractionBlocked = false;

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
  List<Color> _highlightPalette = kHighlightColors;
  Color _defaultHighlightColor = kHighlightColors.last;

  // Dictionary
  late final DictionaryService _dictionaryService;

  // Rendered Chunks
  final List<BookChunk> _displayChunks = [];
  final List<List<int>> _displayToOriginal = [];
  final Map<int, int> _originalToDisplay = {};
  bool _displayChunksComplete = false;
  ProgressiveDisplayState? _progressiveDisplayState;
  Future<void>? _activeProgressiveRangeTask;
  DisplayRangeRequest? _activeProgressiveRangeRequest;
  final Set<int> _cancelledProgressiveRangeGenerations = <int>{};
  late final FrameBudgetedRangeScheduler _displayRangeScheduler;
  ProgressiveDisplayRangeGenerator? _progressiveRangeGenerator;
  int _progressiveRangeGeneration = 0;
  bool _isPreparingForwardRange = false;
  bool _isPreparingBackwardRange = false;
  bool _isPreparingTargetRange = false;
  Object? _progressiveRangeFailure;
  // Settings
  final _settingsService = ReadingSettingsService();
  final _bookReaderThemeService = BookReaderThemeService();
  final _educationService = UserEducationService();
  ReadingSettings _settings = const ReadingSettings();

  // Metadata
  final _metadataService = BookMetadataService();

  // Cached preferences to avoid repeated async lookups
  SharedPreferences? _prefs;
  AnnotationPanelTab _lastAnnotationsTab = AnnotationPanelTab.highlights;

  // Display chunk caching
  final _bookCacheService = BookCacheService();
  SegmentedDisplayCacheService? _segmentedDisplayCacheService;
  final DisplaySectionMemoryCache _displaySectionMemoryCache =
      DisplaySectionMemoryCache();
  final _displayGenerationCoordinator = DisplayGenerationCoordinator();
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
  bool _readerDiagScenarioStarted = false;
  String? _activeReaderLayoutFingerprint;

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
  int? _pendingPositionSaveIndex;
  int? _pendingPreviewJumpDisplayIndex;
  bool _isScrubbing = false;
  int? _scrubStartDisplayIndex;
  int? _scrubPreviewDisplayIndex;
  int? _lazyScrubPreviewSpineIndex;
  int? _lastDwellPage;
  DateTime? _readingSessionStartedAt;
  final ReaderPositionSession _positionSession = ReaderPositionSession();
  final ValueNotifier<PositionHistory?> _positionHistoryNotifier =
      ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings ?? const ReadingSettings();
    _lazySession = widget.lazySession;
    _sourceChunks = List<BookChunk>.from(widget.chunks);
    _sourceAnchorMap = Map<String, int>.from(widget.anchorMap);
    _sourceChapters = List<ChapterInfo>.from(widget.chapters);
    _sourceSearchIndex = Map<String, List<int>>.from(widget.searchIndex);
    _sourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
      widget.initialStableLocationsByChunkIndex,
    );
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
    WidgetsBinding.instance.removeObserver(this);
    _directOpenOperation?.cancel();
    _displayGenerationCoordinator.cancelActive('reader_disposed');
    _rebuildGeneration++;
    _progressiveRangeGeneration++;
    _progressiveRangeGenerator = null;
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
    unawaited(_flushReaderPersistence(includeCurrentPosition: true));
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
        _dwellTimer?.cancel();
        _previewPromotionTimer?.cancel();
        _stopHardwarePagePress();
        if (_speedReadController.isActive && !_speedReadController.isPaused) {
          _speedReadController.pause();
          _speedReadLifecycleAutoPaused = true;
        }
        unawaited(_syncNativeReaderControlsState());
        unawaited(_flushReaderPersistence(includeCurrentPosition: true));
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
        break;
    }
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

  Future<void> _flushReaderPersistence({
    bool includeCurrentPosition = false,
  }) async {
    if (includeCurrentPosition &&
        _positionSession.canCommitActiveVisiblePosition &&
        _displayChunks.isNotEmpty &&
        _displayToOriginal.isNotEmpty) {
      _pendingPositionSaveIndex = _positionSession.activeVisiblePosition.clamp(
        0,
        _displayToOriginal.length - 1,
      );
    }

    await _flushPendingReadingPosition();
    await _flushReadingSession();
    await _statsService.flushPendingWrites();
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
    final promoted = _positionSession.promotePreview();
    if (promoted == null) return;
    _isScrubbing = false;
    _scrubPreviewDisplayIndex = null;
    _scrubStartDisplayIndex = null;
    _pendingPreviewJumpDisplayIndex = null;
    _cancelPreviewPromotionTimer();
    _runCommittedPageEffects(promoted);
  }

  void _clearPreviewState({int? visibleDisplayIndex}) {
    _positionSession.clearPreview(visibleDisplayIndex: visibleDisplayIndex);
    _isScrubbing = false;
    _scrubPreviewDisplayIndex = null;
    _lazyScrubPreviewSpineIndex = null;
    _scrubStartDisplayIndex = null;
    _pendingPreviewJumpDisplayIndex = null;
    _cancelPreviewPromotionTimer();
  }

  void _jumpReaderToPage(int targetIndex, {bool asPreview = false}) {
    if (_displayChunks.isEmpty) return;
    final clamped = targetIndex.clamp(0, _displayChunks.length - 1);
    if (asPreview) {
      _pendingPreviewJumpDisplayIndex = clamped;
      _positionSession.updatePreview(clamped);
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
    _pageController!.jumpToPage(clamped);
  }

  void _animateReaderToPage(
    int targetIndex, {
    required Duration duration,
    required Curve curve,
  }) {
    if (_displayChunks.isEmpty) return;
    final clamped = targetIndex.clamp(0, _displayChunks.length - 1);
    if (_usesInteractiveCardDeck || _pageController?.hasClients != true) {
      if (_usesInteractiveCardDeck &&
          _cardDeckController.animateToIndex(clamped, duration, curve)) {
        return;
      }
      if (_currentPage != clamped || _activeDisplayIndex != clamped) {
        _onPageChanged(clamped);
      }
      return;
    }
    _pageController!.animateToPage(clamped, duration: duration, curve: curve);
  }

  void _nextReaderPage({required Duration duration, required Curve curve}) {
    if (_currentPage >= _displayChunks.length - 1) {
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
            rangeFuture.then((_) {
              _readerDiagLog('boundary_wait_end', {
                'book': widget.bookId,
                'generation': _rebuildGeneration,
                'direction': DisplayRangeDirection.forward.name,
              });
              if (mounted && _currentPage < _displayChunks.length - 1) {
                _animateReaderToPage(
                  _currentPage + 1,
                  duration: duration,
                  curve: curve,
                );
              }
            }),
          );
        }
      }
      return;
    }
    _animateReaderToPage(_currentPage + 1, duration: duration, curve: curve);
  }

  void _previousReaderPage({required Duration duration, required Curve curve}) {
    if (_currentPage <= 0) {
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
          final rangeFuture =
              range == null ||
                  (_lazySession != null &&
                      _lazyHasContentBeforeOutsideLoadedWindow() &&
                      _currentPage <= 0)
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
              if (loaded &&
                  range == null &&
                  _lazySession != null &&
                  _currentPage <= 0) {
                unawaited(
                  _completeBackwardBoundaryNavigation(
                    generation: _rebuildGeneration,
                    duration: duration,
                    curve: curve,
                  ),
                );
                return;
              }
              if (_currentPage > 0) {
                _animateReaderToPage(
                  _currentPage - 1,
                  duration: duration,
                  curve: curve,
                );
              }
            }),
          );
        }
      }
      return;
    }
    _animateReaderToPage(_currentPage - 1, duration: duration, curve: curve);
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
    _cancelPreviewPromotionTimer();
    _positionSaveTimer?.cancel();
    _pendingPositionSaveIndex = null;
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
    _currentPage = clamped;
    _activeDisplayIndex = clamped;
    _positionSession.markVisible(clamped);
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

  Future<void> _initReadingPosition() async {
    if (_sourceChunks.isEmpty) {
      setState(() => _ready = true);
      return;
    }

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
    final settings = await _settingsService.loadSettings();
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
    if (previousSession != null &&
        !identical(previousSession, result.session)) {
      unawaited(previousSession.close());
    }

    final loadedSpines = result.window.locationsByChunkIndex.values
        .map((location) => location.spineIndex)
        .toSet();
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

    _lastScreenSize = screenSize;
    _lastSafeArea = displaySafeArea;
    _lastTextScaler = textScaler;
    _hasCompletedDisplayChunkBuild = false;
    _displayChunksComplete = false;

    final cacheKey = BookCacheService.displayChunkKey(
      bookId: widget.bookId,
      fontSize: _settings.fontSizeValue,
      fontFamily: _settings.fontFamily.name,
      fontWeight: _settings.fontWeight.name,
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
          '${_settings.lineHeight}|${_settings.paragraphSpacing}|'
          '${_settings.sideMargin}|${_settings.enableCardDepth}|'
          '${textScaler.scale(1.0)}',
      viewportSignature:
          '${screenSize.width}x${screenSize.height}|'
          '${displaySafeArea.top},${displaySafeArea.bottom},'
          '${displaySafeArea.left},${displaySafeArea.right}',
      cacheKey: cacheKey,
    );
    _activeReaderLayoutFingerprint =
        '${generationSignature.parsedContentVersion}|'
        '${generationSignature.layoutSignature}|'
        '${generationSignature.settingsSignature}|'
        '${generationSignature.viewportSignature}|'
        '${generationSignature.cacheKey}';
    final generationRequest = _displayGenerationCoordinator.request(
      generationSignature,
    );
    final token = generationRequest.token;

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
    _progressiveDisplayState?.cancelActiveRequests();
    _progressiveDisplayState = null;
    _progressiveRangeFailure = null;
    _isRebuildingChunks = true;
    _loadOrRebuildDisplayChunks(
      screenSize,
      displaySafeArea,
      textScaler,
      cacheKey,
      token,
    );
  }

  EdgeInsets _canonicalDisplaySafeArea(EdgeInsets safeArea) {
    return EdgeInsets.fromLTRB(safeArea.left, safeArea.top, safeArea.right, 0);
  }

  Future<void> _loadOrRebuildDisplayChunks(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
    String cacheKey,
    DisplayGenerationToken token,
  ) async {
    final thisGen = token.id;
    final restoreNavigationGeneration = _positionSession.navigationGeneration;
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

    final cached = await _bookCacheService.loadDisplayChunks(cacheKey);
    if (kDebugMode) {
      debugPrint('[_loadOrRebuildDisplayChunks] gen=$thisGen cacheLoaded');
    }

    if (!mounted || !_displayGenerationCoordinator.canPublish(token)) {
      if (kDebugMode) {
        debugPrint(
          '[_loadOrRebuildDisplayChunks] gen=$thisGen earlyReturn (stale gen=$_rebuildGeneration)',
        );
      }
      return;
    }

    if (cached != null) {
      if (kDebugMode) {
        debugPrint(
          '[_loadOrRebuildDisplayChunks] gen=$thisGen CACHE HIT -> applying ${cached.displayChunks.length} chunks',
        );
      }
      _displayChunks
        ..clear()
        ..addAll(cached.displayChunks);
      _displayToOriginal
        ..clear()
        ..addAll(cached.displayToOriginal);
      _originalToDisplay
        ..clear()
        ..addAll(cached.originalToDisplay);
      _displayChunksComplete = true;
      _progressiveDisplayState = null;
      _restorePosition(restoreNavigationGeneration);
      _markDisplayRebuildCompleted(thisGen, token.signature);
      _displayGenerationCoordinator.complete(token);
      _readerDiagLog('reader_display_cache_hit', {
        'book': widget.bookId,
        'generation': thisGen,
        'cacheKey': cacheKey,
        'displayChunks': cached.displayChunks.length,
      });
      _scheduleLazyInitialAdjacentWarmup();
      return;
    }

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
    );
    _readerDiagLog('reader_display_load_end', {
      'book': widget.bookId,
      'generation': thisGen,
      'displayChunks': _displayChunks.length,
    });
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
    for (
      var displayIndex = 0;
      displayIndex < _displayChunks.length;
      displayIndex++
    ) {
      for (final range in _displayChunks[displayIndex].effectiveSourceRanges) {
        if (range.originalChunkIndex != originalChunkIndex) continue;
        final containsOffset =
            originalStartOffset >= range.originalStartOffset &&
            originalStartOffset < range.originalEndOffset;
        if (containsOffset) return displayIndex;
      }
    }
    return null;
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
  void _restorePosition(int restoreNavigationGeneration) {
    if (_displayChunks.isEmpty) {
      _currentPage = 0;
      _hasCompletedDisplayChunkBuild = true;
      if (_pageController == null) {
        _pageController = PageController(keepPage: false);
      } else if (_pageController!.hasClients) {
        _pageController!.jumpToPage(0);
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

    final pendingStableRestore = _pendingExactStableRestore;
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
    if (pendingStableRestore != null) {
      final sourceIndex = _sourceIndexForStableLocation(pendingStableRestore);
      final exactDisplayIndex = sourceIndex == null
          ? null
          : _displayIndexForSourceLocation(
              originalChunkIndex: sourceIndex,
              originalStartOffset: pendingStableRestore.textOffset,
              sourceText: pendingStableRestore.contextText,
            );
      if (exactDisplayIndex != null) {
        _pendingExactStableRestore = null;
        _preferSourceIndexOnNextRestore = false;
        _isFirstLayout = false;
        _targetProgressRatio = _displayChunks.isEmpty
            ? 0
            : exactDisplayIndex / _displayChunks.length;
        _readerDiagLog('stable_location_exact_restore', {
          ..._stableLocationDiagFields(pendingStableRestore),
          'sourceIndex': sourceIndex,
          'displayIndex': exactDisplayIndex,
        });
        _jumpToDisplayIndex(exactDisplayIndex);
        return;
      }
      _readerDiagLog('stable_location_exact_restore_miss', {
        ..._stableLocationDiagFields(pendingStableRestore),
        'sourceIndex': sourceIndex,
      });
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
  void _jumpToDisplayIndex(int index) {
    final pendingStableRestore = _pendingExactStableRestore;
    var targetIndex = index;
    if (pendingStableRestore != null) {
      _pendingExactStableRestore = null;
      final sourceIndex = _sourceIndexForStableLocation(pendingStableRestore);
      final exactDisplayIndex = sourceIndex == null
          ? null
          : _displayIndexForSourceLocation(
              originalChunkIndex: sourceIndex,
              originalStartOffset: pendingStableRestore.textOffset,
              sourceText: pendingStableRestore.contextText,
            );
      if (exactDisplayIndex != null) {
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
      }
    }
    _hasCompletedDisplayChunkBuild = true;
    _currentPage = targetIndex;
    _activeDisplayIndex = targetIndex;
    _positionSession.markVisible(targetIndex);
    _syncRestoreTargetFromDisplayIndex(targetIndex);
    if (_pageController == null) {
      _pageController = PageController(
        initialPage: targetIndex,
        keepPage: false,
      );
    } else if (_pageController!.hasClients) {
      _pageController!.jumpToPage(targetIndex);
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

    await _rebuildDisplayChunks(screenSize, safeArea, textScaler, generation);

    if (!mounted || !_displayGenerationCoordinator.canPublish(token)) {
      if (kDebugMode) {
        debugPrint(
          '[_rebuildDisplayChunksAsync] gen=$generation cancelled after rebuild',
        );
      }
      return;
    }

    _restorePosition(restoreNavigationGeneration);
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
    } else if (_displayGenerationCoordinator.canWriteCache(token, cacheKey)) {
      await _bookCacheService.cacheDisplayChunks(
        key: cacheKey,
        displayChunks: List.of(_displayChunks),
        displayToOriginal: List.of(_displayToOriginal),
        originalToDisplay: Map.of(_originalToDisplay),
        shouldWrite: () =>
            _displayGenerationCoordinator.canWriteCache(token, cacheKey),
      );
    } else {
      _readerDiagLog('reader_display_cache_write_skipped_stale', {
        'book': widget.bookId,
        'generation': generation,
        'cacheKey': cacheKey,
        'reason': token.cancellationReason ?? 'stale_generation',
      });
    }
    if (_displayChunksComplete) {
      _displayGenerationCoordinator.complete(token);
    } else {
      _displayGenerationCoordinator.markState(
        token,
        DisplayGenerationState.readyPartial,
      );
    }
  }

  Future<void> _rebuildDisplayChunks(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
    int generation,
  ) async {
    final fullRebuildStopwatch = Stopwatch()..start();
    _readerDiagLog('reader_display_rebuild_begin', {
      'book': widget.bookId,
      'generation': generation,
      'sourceChunks': _sourceChunks.length,
      'screenW': screenSize.width.round(),
      'screenH': screenSize.height.round(),
    });
    final List<BookChunk> newDisplayChunks = [];
    final List<List<int>> newDisplayToOriginal = [];
    final Map<int, int> newOriginalToDisplay = {};

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
    final availableWidth = layoutMetrics.availableWidth;
    final densityPolicy = readerDensityPolicy(_settings.contentDensity);
    final pageHeightBudget = layoutMetrics.maxTextHeight;
    final physicalTextBudget = math.max(
      pageHeightBudget,
      layoutMetrics.availableHeight - layoutMetrics.safetyBuffer,
    );
    final minUsefulHeight = layoutMetrics.minUsefulTextHeight;

    // Cache text styles to avoid repeated GoogleFonts calls
    final bodyStyle = _settings.getTextStyle();
    final headingStyle = _settings.getTextStyle(isHeading: true);
    final headingStrut = _settings.getHeadingStrutStyle();
    final bodyStrut = _settings.getBodyStrutStyle();
    final textHeightCache =
        <({int chunkId, String text, bool dialogue, double width}), double>{};
    final tokenRangePattern = RegExp(r'\S+\s*|\s+');

    ReaderTableBlock? singleTableBlock(String text) {
      final blocks = parseReaderContentBlocks(text);
      if (blocks.length != 1 ||
          blocks.single.type != ReaderContentBlockType.table) {
        return null;
      }
      return blocks.single.table;
    }

    double tableRowHeight(
      List<String> cells,
      TextStyle style,
      double columnWidth,
    ) {
      var maxCellHeight = 0.0;
      for (final cell in cells) {
        final tp = TextPainter(
          text: TextSpan(text: cell, style: style),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          strutStyle: bodyStrut,
        )..layout(maxWidth: math.max(1.0, columnWidth - 20));
        maxCellHeight = math.max(maxCellHeight, tp.height);
        tp.dispose();
      }
      return maxCellHeight + 18;
    }

    ({TextStyle style, double columnWidth}) tableMeasurementStyle(
      ReaderTableBlock table,
      BookChunk chunk,
    ) {
      final columnCount = math.max(1, table.columnCount);
      final publisherPadding = resolveReaderPublisherPadding(chunk);
      final maxWidth = math.max(
        1.0,
        availableWidth - publisherPadding.horizontal,
      );
      final columnWidth = columnCount >= 3
          ? 156.0
          : math.max(120.0, maxWidth / columnCount);
      final style = bodyStyle.copyWith(
        fontSize: (_settings.fontSizeValue).clamp(13.0, 18.0),
        height: _settings.lineHeight.clamp(1.2, 1.45),
      );
      return (style: style, columnWidth: columnWidth);
    }

    double estimateTableHeight(ReaderTableBlock table, BookChunk chunk) {
      final rowCount = table.rows.length + (table.headers.isNotEmpty ? 1 : 0);
      if (rowCount == 0) return 0;
      final tableStyle = tableMeasurementStyle(table, chunk);

      var height = 22.0;
      if (table.headers.isNotEmpty) {
        height += tableRowHeight(
          table.headers,
          tableStyle.style,
          tableStyle.columnWidth,
        );
      }
      for (final row in table.rows) {
        height += tableRowHeight(row, tableStyle.style, tableStyle.columnWidth);
      }
      return height;
    }

    Future<double?> estimateTableHeightCooperative(
      ReaderTableBlock table,
      BookChunk chunk,
      FrameBudgetedRangeTask schedulerTask, {
      double? stopAfter,
    }) async {
      final rowCount = table.rows.length + (table.headers.isNotEmpty ? 1 : 0);
      if (rowCount == 0) return 0;
      final tableStyle = tableMeasurementStyle(table, chunk);
      var height = 22.0;

      if (table.headers.isNotEmpty) {
        height += tableRowHeight(
          table.headers,
          tableStyle.style,
          tableStyle.columnWidth,
        );
        if (!await schedulerTask.checkpoint()) return null;
        if (stopAfter != null && height > stopAfter) return height;
      }

      var rowIndex = 0;
      for (final row in table.rows) {
        height += tableRowHeight(row, tableStyle.style, tableStyle.columnWidth);
        if (rowIndex % 2 == 0 && !await schedulerTask.checkpoint()) {
          return null;
        }
        if (stopAfter != null && height > stopAfter) return height;
        rowIndex++;
      }
      return height;
    }

    void logSlowTextMeasure({
      required Stopwatch? stopwatch,
      required BookChunk chunk,
      required String text,
      required String kind,
      ReaderTableBlock? table,
    }) {
      if (stopwatch == null) return;
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      if (elapsedMs < 40) return;
      _readerDiagLog('range_slow_text_measure', {
        'book': widget.bookId,
        'generation': _rebuildGeneration,
        'sourceIndex': chunk.index,
        'kind': kind,
        'elapsedMs': elapsedMs,
        'textLength': text.length,
        'wordCount': readerLayoutWordCount(text),
        'lineBreaks': '\n'.allMatches(text).length,
        'blockRole': chunk.blockRole.name,
        'publisherLayout': chunk.usesPublisherLayout,
        'isHeading': chunk.isHeading,
        'isDialogue': chunk.isDialogue,
        'tableRows': table?.rows.length,
        'tableColumns': table?.columnCount,
      });
    }

    // Helper: measures exact painted height, using the same textScaler
    // as the Text widget so measurements are pixel-accurate.
    double measureTextHeight(
      String text,
      BookChunk chunk, {
      bool? dialogueOverride,
    }) {
      final measureStopwatch = _readerDiagEnabled
          ? (Stopwatch()..start())
          : null;
      final isDialogue = dialogueOverride ?? chunk.isDialogue;
      final dialogueExtraInset = isDialogue ? kReaderDialogueTextInset : 0.0;
      final publisherPadding = resolveReaderPublisherPadding(chunk);
      final chunkAvailableWidth =
          availableWidth - dialogueExtraInset - publisherPadding.horizontal;
      final maxWidth = math.max(1.0, chunkAvailableWidth);
      final cacheKey = (
        chunkId: identityHashCode(chunk),
        text: text,
        dialogue: isDialogue,
        width: maxWidth,
      );
      final cachedHeight = textHeightCache[cacheKey];
      if (cachedHeight != null) {
        return cachedHeight;
      }

      final textAlign = resolveReaderChunkTextAlign(chunk, _settings);
      final table = chunk.blockRole == BookBlockRole.table
          ? singleTableBlock(text)
          : null;
      if (table != null) {
        final height = estimateTableHeight(table, chunk);
        textHeightCache[cacheKey] = height;
        logSlowTextMeasure(
          stopwatch: measureStopwatch,
          chunk: chunk,
          text: text,
          kind: 'table',
          table: table,
        );
        return height;
      }

      if (!chunk.isHeading && !chunk.usesPublisherLayout) {
        final height = measureFinalLayoutParagraphTextHeight(
          text: text,
          style: bodyStyle,
          maxWidth: maxWidth,
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
          textScaler: textScaler,
          strutStyle: bodyStrut,
          fallbackFontSize: _settings.fontSizeValue,
          fallbackLineHeight: _settings.lineHeight,
          paragraphSpacing: _settings.paragraphSpacing,
        );
        textHeightCache[cacheKey] = height;
        logSlowTextMeasure(
          stopwatch: measureStopwatch,
          chunk: chunk,
          text: text,
          kind: 'paragraph',
        );
        return height;
      }

      final span = chunk.isHeading
          ? TextSpan(text: text, style: headingStyle)
          : TextSpanUtils.buildSpacedTextSpan(
              text: text,
              baseStyle: bodyStyle,
              paragraphSpacingMultiplier: 1.0,
            );

      final tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textAlign: textAlign,
        textScaler: textScaler,
        strutStyle: chunk.isHeading ? headingStrut : bodyStrut,
      );

      tp.layout(maxWidth: maxWidth);
      final h = tp.height;
      tp.dispose();
      textHeightCache[cacheKey] = h;
      logSlowTextMeasure(
        stopwatch: measureStopwatch,
        chunk: chunk,
        text: text,
        kind: chunk.isHeading ? 'heading' : 'publisher',
      );
      return h;
    }

    double heightBudgetFor(BookChunk chunk) {
      return chunk.usesPublisherLayout ? physicalTextBudget : pageHeightBudget;
    }

    List<T>? combineLists<T>(List<T>? first, List<T>? second) {
      final combined = <T>[...?first, ...?second];
      return combined.isEmpty ? null : combined;
    }

    List<LinkMetadata>? sliceLinks(
      BookChunk original,
      int startOffset,
      int endOffset,
    ) {
      final links = original.links;
      if (links == null || links.isEmpty) return null;

      final sliced = <LinkMetadata>[];
      for (final link in links) {
        final overlapStart = math.max(startOffset, link.start);
        final overlapEnd = math.min(endOffset, link.end);
        if (overlapStart >= overlapEnd) continue;
        sliced.add(
          LinkMetadata(
            start: overlapStart - startOffset,
            end: overlapEnd - startOffset,
            url: link.url,
          ),
        );
      }
      return sliced.isEmpty ? null : sliced;
    }

    List<InlineStyle>? sliceInlineStyles(
      BookChunk original,
      int startOffset,
      int endOffset,
    ) {
      final styles = original.inlineStyles;
      if (styles == null || styles.isEmpty) return null;

      final sliced = <InlineStyle>[];
      for (final style in styles) {
        final overlapStart = math.max(startOffset, style.start);
        final overlapEnd = math.min(endOffset, style.end);
        if (overlapStart >= overlapEnd) continue;
        sliced.add(
          InlineStyle(
            start: overlapStart - startOffset,
            end: overlapEnd - startOffset,
            type: style.type,
          ),
        );
      }
      return sliced.isEmpty ? null : sliced;
    }

    List<FootnoteRef>? sliceFootnotes(
      BookChunk original,
      int startOffset,
      int endOffset,
    ) {
      final footnotes = original.footnotes;
      if (footnotes == null || footnotes.isEmpty) return null;

      final sliced = <FootnoteRef>[];
      for (final footnote in footnotes) {
        if (footnote.position < startOffset || footnote.position >= endOffset) {
          continue;
        }
        sliced.add(
          FootnoteRef(
            position: footnote.position - startOffset,
            label: footnote.label,
            content: footnote.content,
          ),
        );
      }
      return sliced.isEmpty ? null : sliced;
    }

    List<ChunkSourceRange> sliceSourceRanges(
      BookChunk original,
      int startOffset,
      int endOffset,
    ) {
      final mapped = original.mapDisplayRangeToOriginal(startOffset, endOffset);
      return mapped
          .map(
            (range) => ChunkSourceRange(
              originalChunkIndex: range.originalChunkIndex,
              originalStartOffset: range.originalStartOffset,
              originalEndOffset: range.originalEndOffset,
              displayStartOffset: range.displayStartOffset - startOffset,
              displayEndOffset: range.displayEndOffset - startOffset,
            ),
          )
          .toList();
    }

    List<LinkMetadata>? shiftLinks(List<LinkMetadata>? links, int delta) {
      if (links == null || links.isEmpty) return null;
      return links
          .map(
            (link) => LinkMetadata(
              start: link.start + delta,
              end: link.end + delta,
              url: link.url,
            ),
          )
          .toList();
    }

    List<InlineStyle>? shiftInlineStyles(List<InlineStyle>? styles, int delta) {
      if (styles == null || styles.isEmpty) return null;
      return styles
          .map(
            (style) => InlineStyle(
              start: style.start + delta,
              end: style.end + delta,
              type: style.type,
            ),
          )
          .toList();
    }

    List<FootnoteRef>? shiftFootnotes(List<FootnoteRef>? footnotes, int delta) {
      if (footnotes == null || footnotes.isEmpty) return null;
      return footnotes
          .map(
            (footnote) => FootnoteRef(
              position: footnote.position + delta,
              label: footnote.label,
              content: footnote.content,
            ),
          )
          .toList();
    }

    BookChunk buildSplitChunk(
      BookChunk original,
      int startOffset,
      int endOffset,
    ) {
      final text = original.text ?? '';
      final subText = text.substring(startOffset, endOffset);
      final sourceRanges = sliceSourceRanges(original, startOffset, endOffset);

      return BookChunk(
        index: original.index,
        type: BookChunkType.text,
        section: original.section,
        sourceFile: original.sourceFile,
        text: subText,
        links: sliceLinks(original, startOffset, endOffset),
        inlineStyles: sliceInlineStyles(original, startOffset, endOffset),
        footnotes: sliceFootnotes(original, startOffset, endOffset),
        isHeading: original.isHeading,
        isDialogue: original.isDialogue,
        blockRole: original.blockRole,
        publisherTextAlign: original.publisherTextAlign,
        publisherLeftIndent: original.publisherLeftIndent,
        publisherRightIndent: original.publisherRightIndent,
        preserveLineBreaks: original.preserveLineBreaks,
        preserveWhitespace: original.preserveWhitespace,
        sourceRanges: sourceRanges.isEmpty ? null : sourceRanges,
      );
    }

    Future<List<({int start, int end})>?> splitOversizedRange(
      String text,
      int startOffset,
      int endOffset,
      BookChunk original,
      FrameBudgetedRangeTask schedulerTask,
    ) async {
      final localText = text.substring(startOffset, endOffset);
      final tokenMatches = tokenRangePattern.allMatches(localText).toList();
      if (tokenMatches.isEmpty) {
        return [(start: startOffset, end: endOffset)];
      }

      final pieces = <({int start, int end})>[];
      int pieceStart = startOffset;
      int pieceEnd = startOffset;

      void flushPiece(int start, int end) {
        if (start < end) {
          pieces.add((start: start, end: end));
        }
      }

      Future<List<({int start, int end})>?> run() async {
        for (final token in tokenMatches) {
          if (!await schedulerTask.checkpoint()) return null;
          final tokenStart = startOffset + token.start;
          final tokenEnd = startOffset + token.end;
          final tokenText = text.substring(tokenStart, tokenEnd);
          final tokenHeight = measureTextHeight(tokenText, original);

          if (tokenHeight > physicalTextBudget) {
            flushPiece(pieceStart, pieceEnd);

            int charPieceStart = tokenStart;
            for (int cursor = tokenStart + 1; cursor <= tokenEnd; cursor++) {
              if (cursor % 12 == 0 && !await schedulerTask.checkpoint()) {
                return null;
              }
              final candidate = text.substring(charPieceStart, cursor);
              final candidateHeight = measureTextHeight(candidate, original);
              if (candidateHeight > physicalTextBudget &&
                  cursor - 1 > charPieceStart) {
                flushPiece(charPieceStart, cursor - 1);
                charPieceStart = cursor - 1;
              }
            }
            flushPiece(charPieceStart, tokenEnd);
            pieceStart = tokenEnd;
            pieceEnd = tokenEnd;
            continue;
          }

          if (pieceStart == pieceEnd) {
            pieceStart = tokenStart;
          }

          final candidate = text.substring(pieceStart, tokenEnd);
          final candidateHeight = measureTextHeight(candidate, original);
          if (candidateHeight > physicalTextBudget && pieceEnd > pieceStart) {
            flushPiece(pieceStart, pieceEnd);
            pieceStart = tokenStart;
          }
          pieceEnd = tokenEnd;
        }

        flushPiece(pieceStart, pieceEnd);
        return pieces.isEmpty ? [(start: startOffset, end: endOffset)] : pieces;
      }

      return run();
    }

    List<({int start, int end})> preservedLineRanges(String text) {
      final ranges = <({int start, int end})>[];
      var start = 0;
      for (var i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) {
          ranges.add((start: start, end: i + 1));
          start = i + 1;
        }
      }
      if (start < text.length) {
        ranges.add((start: start, end: text.length));
      }
      return ranges;
    }

    // Helper: Chunk Splitting exactly as wide as bounds
    Future<List<BookChunk>?> splitChunkByHeight(
      BookChunk original,
      FrameBudgetedRangeTask schedulerTask,
    ) async {
      if (original.type != BookChunkType.text || original.isHeading) {
        return [original];
      }
      final text = original.text ?? '';
      if (text.isEmpty) return [original];
      if (original.blockRole == BookBlockRole.table) {
        final table = singleTableBlock(text);
        final tableBudget = heightBudgetFor(original);
        final tableHeight = table == null
            ? null
            : await estimateTableHeightCooperative(
                table,
                original,
                schedulerTask,
                stopAfter: tableBudget,
              );
        if (table != null && tableHeight == null) return null;
        if (table != null && tableHeight! > tableBudget) {
          final tableChunks = <BookChunk>[];
          var currentRows = <List<String>>[];
          final tableStyle = tableMeasurementStyle(table, original);
          final headerHeight = table.headers.isEmpty
              ? 0.0
              : tableRowHeight(
                  table.headers,
                  tableStyle.style,
                  tableStyle.columnWidth,
                );
          final baseHeight = 22.0 + headerHeight;
          var currentHeight = baseHeight;

          BookChunk buildTableChunk(List<List<String>> rows) {
            final splitTable = ReaderTableBlock(
              headers: table.headers,
              rows: rows,
            );
            return BookChunk(
              index: original.index,
              type: BookChunkType.text,
              section: original.section,
              sourceFile: original.sourceFile,
              text: encodeReaderTableBlock(splitTable),
              blockRole: original.blockRole,
              publisherTextAlign: original.publisherTextAlign,
              publisherLeftIndent: original.publisherLeftIndent,
              publisherRightIndent: original.publisherRightIndent,
              preserveLineBreaks: original.preserveLineBreaks,
              preserveWhitespace: original.preserveWhitespace,
            );
          }

          var tableRowIndex = 0;
          for (final row in table.rows) {
            if (tableRowIndex % 2 == 0 && !await schedulerTask.checkpoint()) {
              return null;
            }
            tableRowIndex++;
            final rowHeight = tableRowHeight(
              row,
              tableStyle.style,
              tableStyle.columnWidth,
            );
            final candidateHeight = currentHeight + rowHeight;
            if (currentRows.isNotEmpty && candidateHeight > tableBudget) {
              tableChunks.add(buildTableChunk(currentRows));
              currentRows = [row];
              currentHeight = baseHeight + rowHeight;
            } else {
              currentRows = [...currentRows, row];
              currentHeight = candidateHeight;
            }
          }

          if (currentRows.isNotEmpty) {
            tableChunks.add(buildTableChunk(currentRows));
          }
          return tableChunks.isNotEmpty ? tableChunks : [original];
        }
      }
      final chunkBudget = heightBudgetFor(original);
      final shouldSkipWholeChunkMeasurement =
          text.length > 2400 ||
          '\n'.allMatches(text).length > 8 ||
          readerLayoutWordCount(text) > 360;
      if (!shouldSkipWholeChunkMeasurement) {
        final totalH = measureTextHeight(text, original);
        if (totalH <= chunkBudget) {
          return [original];
        }
        if (!await schedulerTask.checkpoint()) return null;
      } else {
        _readerDiagLog('range_large_chunk_direct_split', {
          'book': widget.bookId,
          'generation': _rebuildGeneration,
          'sourceIndex': original.index,
          'textLength': text.length,
          'wordCount': readerLayoutWordCount(text),
          'lineBreaks': '\n'.allMatches(text).length,
          'blockRole': original.blockRole.name,
          'publisherLayout': original.usesPublisherLayout,
        });
      }

      final sourceRanges = original.preserveLineBreaks
          ? preservedLineRanges(text)
          : readerSentenceRanges(text);
      final splitRanges = <({int start, int end})>[];
      for (final range in sourceRanges) {
        if (!await schedulerTask.checkpoint()) return null;
        if (range.start >= range.end) continue;

        final rangeText = text.substring(range.start, range.end);
        final rangeHeight = measureTextHeight(rangeText, original);

        if (rangeHeight <= physicalTextBudget) {
          splitRanges.add(range);
        } else {
          final oversized = await splitOversizedRange(
            text,
            range.start,
            range.end,
            original,
            schedulerTask,
          );
          if (oversized == null) return null;
          splitRanges.addAll(oversized);
        }
      }

      if (splitRanges.isEmpty) return [original];

      final subChunks = <BookChunk>[];
      int currentStart = splitRanges.first.start;
      int currentEnd = splitRanges.first.end;

      var splitIndex = 0;
      for (final range in splitRanges.skip(1)) {
        if (splitIndex % 4 == 0 && !await schedulerTask.checkpoint()) {
          return null;
        }
        splitIndex++;
        final candidateText = text.substring(currentStart, range.end);
        final candidateHeight = measureTextHeight(candidateText, original);

        if (candidateHeight <= chunkBudget) {
          currentEnd = range.end;
          continue;
        }

        subChunks.add(buildSplitChunk(original, currentStart, currentEnd));
        currentStart = range.start;
        currentEnd = range.end;
      }

      subChunks.add(buildSplitChunk(original, currentStart, currentEnd));
      return subChunks.isNotEmpty ? subChunks : [original];
    }

    String mergeSeparator(BookChunk first, BookChunk second) {
      final firstRanges = first.effectiveSourceRanges;
      final secondRanges = second.effectiveSourceRanges;
      if (firstRanges.isEmpty || secondRanges.isEmpty) return '\n\n';

      final lastFirstRange = firstRanges.last;
      final firstSecondRange = secondRanges.first;
      final isContiguousSameSource =
          lastFirstRange.originalChunkIndex ==
              firstSecondRange.originalChunkIndex &&
          lastFirstRange.originalEndOffset ==
              firstSecondRange.originalStartOffset;

      return isContiguousSameSource ? '' : '\n\n';
    }

    BookChunk mergeChunks(BookChunk first, BookChunk second) {
      final firstText = first.text ?? '';
      final secondText = second.text ?? '';
      final separator = mergeSeparator(first, second);
      final secondOffset = firstText.length + separator.length;

      final mergedSourceRanges = <ChunkSourceRange>[
        ...first.effectiveSourceRanges,
        ...second.effectiveSourceRanges.map(
          (range) => range.shiftDisplayOffsets(secondOffset),
        ),
      ];

      return BookChunk(
        index: first.index,
        type: BookChunkType.text,
        section: first.section,
        sourceFile: first.sourceFile,
        isHeading: first.isHeading,
        isDialogue: first.isDialogue && second.isDialogue,
        blockRole: first.blockRole,
        publisherTextAlign: first.publisherTextAlign,
        publisherLeftIndent: first.publisherLeftIndent,
        publisherRightIndent: first.publisherRightIndent,
        preserveLineBreaks: first.preserveLineBreaks,
        preserveWhitespace: first.preserveWhitespace,
        text: '$firstText$separator$secondText',
        links: combineLists(
          first.links,
          shiftLinks(second.links, secondOffset),
        ),
        inlineStyles: combineLists(
          first.inlineStyles,
          shiftInlineStyles(second.inlineStyles, secondOffset),
        ),
        footnotes: combineLists(
          first.footnotes,
          shiftFootnotes(second.footnotes, secondOffset),
        ),
        sourceRanges: mergedSourceRanges,
      );
    }

    double chunkHeight(BookChunk chunk) {
      final text = chunk.text ?? '';
      if (text.isEmpty) return 0.0;
      return measureTextHeight(text, chunk);
    }

    bool isTinyChunk(BookChunk chunk, double height) {
      final text = chunk.text ?? '';
      if (text.isEmpty) return true;
      final budget = heightBudgetFor(chunk);
      final fillRatio = budget <= 0 ? 1.0 : (height / budget);
      return readerLayoutWordCount(text) <= densityPolicy.tinyWordCount ||
          height <= minUsefulHeight ||
          fillRatio <= densityPolicy.tinyHeightRatio;
    }

    bool sharesHardMergeBoundary(BookChunk first, BookChunk second) {
      if (first.type != BookChunkType.text ||
          second.type != BookChunkType.text) {
        return false;
      }
      return first.section == second.section &&
          first.sourceFile == second.sourceFile &&
          first.isHeading == second.isHeading &&
          first.blockRole == second.blockRole &&
          first.publisherTextAlign == second.publisherTextAlign &&
          first.publisherLeftIndent == second.publisherLeftIndent &&
          first.publisherRightIndent == second.publisherRightIndent &&
          first.preserveLineBreaks == second.preserveLineBreaks &&
          first.preserveWhitespace == second.preserveWhitespace;
    }

    bool canAttemptDisplayMerge(BookChunk first, BookChunk second) {
      if (!sharesHardMergeBoundary(first, second)) return false;
      if (first.blockRole == BookBlockRole.table ||
          second.blockRole == BookBlockRole.table) {
        return false;
      }
      return true;
    }

    bool canUseSoftBodyMerge(BookChunk first, BookChunk second) {
      return !first.isHeading &&
          !second.isHeading &&
          !first.usesPublisherLayout &&
          !second.usesPublisherLayout;
    }

    bool shouldMergeChunks(
      BookChunk pendingChunk,
      BookChunk nextChunk, {
      required double pendingHeight,
      required double nextHeight,
      required double mergedHeight,
    }) {
      if (!sharesHardMergeBoundary(pendingChunk, nextChunk) ||
          mergedHeight > heightBudgetFor(pendingChunk)) {
        return false;
      }

      final pendingTiny = isTinyChunk(pendingChunk, pendingHeight);
      final nextTiny = isTinyChunk(nextChunk, nextHeight);
      final mergeTiny = pendingTiny || nextTiny;

      final matchingPresentation =
          pendingChunk.isDialogue == nextChunk.isDialogue;
      if (matchingPresentation) {
        return true;
      }

      if (!canUseSoftBodyMerge(pendingChunk, nextChunk)) {
        return false;
      }

      return mergeTiny;
    }

    BookChunk? pending;
    List<int> pendingOriginals = [];

    List<int> rebalanceSplitOffsets(String text) {
      final offsets = <int>{};
      for (final range in readerSentenceRanges(text)) {
        if (range.end > 0 && range.end < text.length) {
          offsets.add(range.end);
        }
      }

      return offsets.toList()..sort((a, b) => b.compareTo(a));
    }

    void addDisplayChunk(BookChunk chunk, List<int> originals) {
      final dIdx = newDisplayChunks.length;
      newDisplayChunks.add(chunk);
      newDisplayToOriginal.add(List<int>.of(originals));
      for (final oIdx in originals) {
        newOriginalToDisplay[oIdx] = dIdx;
      }
    }

    Future<bool?> tryRebalancePendingWithTinyNext(
      BookChunk nextChunk,
      double nextHeight,
      FrameBudgetedRangeTask schedulerTask,
    ) async {
      final pendingChunk = pending;
      if (pendingChunk == null) return false;
      if (pendingChunk.usesPublisherLayout || nextChunk.usesPublisherLayout) {
        return false;
      }

      final nextText = nextChunk.text ?? '';
      if (!isTinyChunk(nextChunk, nextHeight) ||
          !canAttemptDisplayMerge(pendingChunk, nextChunk)) {
        return false;
      }

      final pendingText = pendingChunk.text ?? '';
      if (pendingText.isEmpty ||
          isTinyChunk(pendingChunk, chunkHeight(pendingChunk))) {
        return false;
      }

      var offsetIndex = 0;
      for (final splitOffset in rebalanceSplitOffsets(pendingText)) {
        if (offsetIndex % 4 == 0 && !await schedulerTask.checkpoint()) {
          return null;
        }
        offsetIndex++;
        final headText = pendingText.substring(0, splitOffset).trim();
        final tailText = pendingText.substring(splitOffset).trim();
        if (headText.isEmpty || tailText.isEmpty) continue;

        final head = buildSplitChunk(pendingChunk, 0, splitOffset);
        final tail = buildSplitChunk(
          pendingChunk,
          splitOffset,
          pendingText.length,
        );
        final headHeight = chunkHeight(head);
        if (isTinyChunk(head, headHeight)) continue;

        final separator = mergeSeparator(tail, nextChunk);
        final mergedText = '${tail.text ?? ''}$separator$nextText';
        final mergedDialogueLayout = tail.isDialogue && nextChunk.isDialogue;
        final mergedHeight = measureTextHeight(
          mergedText,
          tail,
          dialogueOverride: mergedDialogueLayout,
        );
        if (mergedHeight > heightBudgetFor(tail)) {
          continue;
        }

        addDisplayChunk(head, pendingOriginals);
        if (!await schedulerTask.checkpoint(displayChunksProduced: 1)) {
          return null;
        }
        pending = mergeChunks(tail, nextChunk);
        pendingOriginals = [...pendingOriginals];
        if (!pendingOriginals.contains(nextChunk.index)) {
          pendingOriginals.add(nextChunk.index);
        }
        return true;
      }

      return false;
    }

    Future<bool> flush(FrameBudgetedRangeTask schedulerTask) async {
      if (pending != null) {
        if (!await schedulerTask.checkpoint()) return false;
        final pendingChunk = pending!;
        final pendingText = pendingChunk.text ?? '';
        final pendingHeight = chunkHeight(pendingChunk);
        final canAttachToPrevious =
            newDisplayChunks.isNotEmpty &&
            isTinyChunk(pendingChunk, pendingHeight) &&
            canAttemptDisplayMerge(newDisplayChunks.last, pendingChunk);

        if (canAttachToPrevious) {
          final previous = newDisplayChunks.last;
          final previousText = previous.text ?? '';
          final separator = mergeSeparator(previous, pendingChunk);
          final mergedText = '$previousText$separator$pendingText';
          final mergedDialogueLayout =
              previous.isDialogue && pendingChunk.isDialogue;
          final mergedHeight = measureTextHeight(
            mergedText,
            previous,
            dialogueOverride: mergedDialogueLayout,
          );
          if (!await schedulerTask.checkpoint()) return false;
          if (mergedHeight <= heightBudgetFor(previous)) {
            final dIdx = newDisplayChunks.length - 1;
            newDisplayChunks[dIdx] = mergeChunks(previous, pendingChunk);
            for (final oIdx in pendingOriginals) {
              if (!newDisplayToOriginal[dIdx].contains(oIdx)) {
                newDisplayToOriginal[dIdx].add(oIdx);
              }
              newOriginalToDisplay[oIdx] = dIdx;
            }
            pending = null;
            pendingOriginals = [];
            return true;
          }
        }

        addDisplayChunk(pendingChunk, pendingOriginals);
        if (!await schedulerTask.checkpoint(displayChunksProduced: 1)) {
          return false;
        }
        pending = null;
        pendingOriginals = [];
      }
      return true;
    }

    Future<DisplayRangeResult> generateDisplayRange(
      DisplayRangeRequest request,
    ) async {
      final rangeStopwatch = Stopwatch()..start();
      final schedulerTask = _displayRangeScheduler.startTask(
        id: request.generationId,
        priority: _displayRangePriority(request.direction, request.reason),
        isExternallyCancelled: () =>
            !mounted ||
            _rebuildGeneration != generation ||
            _cancelledProgressiveRangeGenerations.contains(
              request.generationId,
            ),
      );
      var inspectedSourceChunks = 0;
      newDisplayChunks.clear();
      newDisplayToOriginal.clear();
      newOriginalToDisplay.clear();
      pending = null;
      pendingOriginals = [];

      _readerDiagLog('range_generation_begin', {
        'book': widget.bookId,
        'generation': generation,
        'rangeGeneration': request.generationId,
        'direction': request.direction.name,
        'sourceStart': request.sourceRange.start,
        'sourceEndExclusive': request.sourceRange.endExclusive,
        'reason': request.reason,
      });

      void logSlowSourceChunk({
        required String phase,
        required BookChunk chunk,
        required int elapsedMs,
        int? subChunkCount,
        int? displayChunksProduced,
      }) {
        if (!_readerDiagEnabled || elapsedMs < 40) return;
        final text = chunk.text ?? '';
        final table = chunk.blockRole == BookBlockRole.table
            ? singleTableBlock(text)
            : null;
        _readerDiagLog('range_slow_source_chunk', {
          'book': widget.bookId,
          'generation': generation,
          'rangeGeneration': request.generationId,
          'direction': request.direction.name,
          'phaseName': phase,
          'sourceIndex': chunk.index,
          'elapsedMs': elapsedMs,
          'textLength': text.length,
          'wordCount': readerLayoutWordCount(text),
          'lineBreaks': '\n'.allMatches(text).length,
          'blockRole': chunk.blockRole.name,
          'publisherLayout': chunk.usesPublisherLayout,
          'isHeading': chunk.isHeading,
          'isDialogue': chunk.isDialogue,
          'subChunks': subChunkCount,
          'displayChunksProduced': displayChunksProduced,
          'tableRows': table?.rows.length,
          'tableColumns': table?.columnCount,
        });
      }

      DisplayRangeResult cancelledResult() {
        rangeStopwatch.stop();
        final metrics = schedulerTask.finish();
        return DisplayRangeResult(
          request: request,
          displayChunks: const [],
          displayToOriginal: const [],
          originalToDisplay: const {},
          inspectedSourceChunks: inspectedSourceChunks,
          elapsedMilliseconds: rangeStopwatch.elapsedMilliseconds,
          sliceCount: metrics.sliceCount,
          yieldCount: metrics.yieldCount,
          longestWorkIntervalMilliseconds:
              metrics.longestWorkInterval.inMilliseconds,
          maxSliceDurationMilliseconds: metrics.maxSliceDuration.inMilliseconds,
          totalYieldMilliseconds: metrics.totalYieldDuration.inMilliseconds,
          maxSourceChunksPerSlice: metrics.maxSourceChunksPerSlice,
          maxDisplayChunksPerSlice: metrics.maxDisplayChunksPerSlice,
          cancellationLatencyMilliseconds:
              metrics.cancellationLatency?.inMilliseconds,
          cancelled: true,
        );
      }

      for (
        int i = request.sourceRange.start;
        i < request.sourceRange.endExclusive;
        i++
      ) {
        if (!await schedulerTask.checkpoint()) return cancelledResult();

        final originalChunk = _sourceChunks[i];
        final splitStopwatch = _readerDiagEnabled
            ? (Stopwatch()..start())
            : null;
        final subChunks = await splitChunkByHeight(
          originalChunk,
          schedulerTask,
        );
        if (subChunks == null) return cancelledResult();
        splitStopwatch?.stop();
        logSlowSourceChunk(
          phase: 'split',
          chunk: originalChunk,
          elapsedMs: splitStopwatch?.elapsedMilliseconds ?? 0,
          subChunkCount: subChunks.length,
        );

        final processStopwatch = _readerDiagEnabled
            ? (Stopwatch()..start())
            : null;
        final displayCountBeforeSource = newDisplayChunks.length;
        for (final chunk in subChunks) {
          if (!await schedulerTask.checkpoint()) return cancelledResult();
          if (chunk.type != BookChunkType.text) {
            if (!await flush(schedulerTask)) return cancelledResult();
            pending = chunk;
            pendingOriginals = [chunk.index];
            if (!await flush(schedulerTask)) return cancelledResult();
            continue;
          }

          final text = chunk.text ?? '';
          if (text.isEmpty) {
            newOriginalToDisplay[chunk.index] = newDisplayChunks.length;
            continue;
          }

          if (pending == null) {
            pending = chunk;
            pendingOriginals = [chunk.index];
            continue;
          }

          final pendingText = pending!.text ?? '';
          final separator = mergeSeparator(pending!, chunk);
          final testMergeText = '$pendingText$separator$text';
          if (!canAttemptDisplayMerge(pending!, chunk)) {
            if (!await flush(schedulerTask)) return cancelledResult();
            pending = chunk;
            pendingOriginals = [chunk.index];
            continue;
          }
          final pendingHeight = chunkHeight(pending!);
          final nextHeight = chunkHeight(chunk);
          final mergedDialogueLayout = pending!.isDialogue && chunk.isDialogue;
          final mergedHeight = measureTextHeight(
            testMergeText,
            pending!,
            dialogueOverride: mergedDialogueLayout,
          );

          if (shouldMergeChunks(
            pending!,
            chunk,
            pendingHeight: pendingHeight,
            nextHeight: nextHeight,
            mergedHeight: mergedHeight,
          )) {
            pending = mergeChunks(pending!, chunk);
            if (!pendingOriginals.contains(chunk.index)) {
              pendingOriginals.add(chunk.index);
            }
          } else {
            final rebalanced = await tryRebalancePendingWithTinyNext(
              chunk,
              nextHeight,
              schedulerTask,
            );
            if (rebalanced == null) return cancelledResult();
            if (rebalanced) {
              continue;
            }
            if (!await flush(schedulerTask)) return cancelledResult();
            pending = chunk;
            pendingOriginals = [chunk.index];
          }
        }
        processStopwatch?.stop();
        logSlowSourceChunk(
          phase: 'process_subchunks',
          chunk: originalChunk,
          elapsedMs: processStopwatch?.elapsedMilliseconds ?? 0,
          subChunkCount: subChunks.length,
          displayChunksProduced:
              newDisplayChunks.length - displayCountBeforeSource,
        );
        inspectedSourceChunks++;
        if (!await schedulerTask.checkpoint(sourceChunksProcessed: 1)) {
          return cancelledResult();
        }
      }
      if (!await flush(schedulerTask)) return cancelledResult();
      rangeStopwatch.stop();
      final metrics = schedulerTask.finish();

      final result = DisplayRangeResult(
        request: request,
        displayChunks: List<BookChunk>.of(newDisplayChunks),
        displayToOriginal: newDisplayToOriginal.map(List<int>.of).toList(),
        originalToDisplay: Map<int, int>.of(newOriginalToDisplay),
        inspectedSourceChunks: inspectedSourceChunks,
        elapsedMilliseconds: rangeStopwatch.elapsedMilliseconds,
        sliceCount: metrics.sliceCount,
        yieldCount: metrics.yieldCount,
        longestWorkIntervalMilliseconds:
            metrics.longestWorkInterval.inMilliseconds,
        maxSliceDurationMilliseconds: metrics.maxSliceDuration.inMilliseconds,
        totalYieldMilliseconds: metrics.totalYieldDuration.inMilliseconds,
        maxSourceChunksPerSlice: metrics.maxSourceChunksPerSlice,
        maxDisplayChunksPerSlice: metrics.maxDisplayChunksPerSlice,
        cancellationLatencyMilliseconds:
            metrics.cancellationLatency?.inMilliseconds,
      );
      _readerDiagLog('range_generation_end', {
        'book': widget.bookId,
        'generation': generation,
        'rangeGeneration': request.generationId,
        'direction': request.direction.name,
        'sourceStart': request.sourceRange.start,
        'sourceEndExclusive': request.sourceRange.endExclusive,
        'inspectedSourceChunks': result.inspectedSourceChunks,
        'displayChunks': result.displayChunks.length,
        'displayToOriginal': result.displayToOriginal.length,
        'originalToDisplay': result.originalToDisplay.length,
        'elapsedMs': result.elapsedMilliseconds,
        'sliceCount': result.sliceCount,
        'yieldCount': result.yieldCount,
        'longestWorkIntervalMs': result.longestWorkIntervalMilliseconds,
        'maxSliceDurationMs': result.maxSliceDurationMilliseconds,
        'totalYieldMs': result.totalYieldMilliseconds,
        'maxSourceChunksPerSlice': result.maxSourceChunksPerSlice,
        'maxDisplayChunksPerSlice': result.maxDisplayChunksPerSlice,
      });
      return result;
    }

    _progressiveRangeGenerator = generateDisplayRange;

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
    final initialRange = progressiveState.initialSourceRange(
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
    final cachedInitial = await _loadProgressiveSegmentsAroundSource(
      cacheKey: signature.cacheKey,
      signature: signature,
      progressiveState: progressiveState,
      targetOriginalIndex: startIndex,
      generation: generation,
    );
    if (cachedInitial) {
      progressiveState.sourceChunkCount =
          _progressiveSourceCountForLoadedWindow();
      _applyLazyExternalAvailability(progressiveState);
      progressiveState.generationComplete =
          !progressiveState.externalUnavailableBefore &&
          !progressiveState.externalUnavailableAfter &&
          progressiveState.ranges.first.sourceRange.start == 0 &&
          progressiveState.ranges.last.sourceRange.endExclusive >=
              progressiveState.sourceChunkCount;
      _displayChunksComplete = progressiveState.generationComplete;
      _hasCompletedDisplayChunkBuild = true;
      _readerDiagLog('initial_range_ready', {
        'book': widget.bookId,
        'generation': generation,
        'sourceStart': progressiveState.ranges.first.sourceRange.start,
        'sourceEndExclusive':
            progressiveState.ranges.last.sourceRange.endExclusive,
        'displayChunks': progressiveState.displayChunks.length,
        'cache': 'segmented',
        'hasEarlierContent': progressiveState.hasUnavailableBefore,
        'hasLaterContent': progressiveState.hasUnavailableAfter,
      });
      if (mounted) setState(() {});
      _scheduleLazyInitialAdjacentWarmup();
      _maybeRequestCardDepthChapterCompletion(_currentPage);
      final forwardRange = progressiveState.nextForwardRange(
        _adjacentRangeSourceChunks,
      );
      if (forwardRange != null) {
        if (_lazySession != null) {
          _readerDiagLog('range_request_skipped_lazy_initial_lookahead', {
            'book': widget.bookId,
            'generation': generation,
            'sourceStart': forwardRange.start,
            'sourceEndExclusive': forwardRange.endExclusive,
            'reason': 'segmented_cache_lazy_initial_window_ready',
          });
        } else if (_isLazyForwardSentinelRange(forwardRange)) {
          unawaited(_loadLazyForwardSectionAndPrepareRange());
        } else {
          unawaited(
            _prepareProgressiveDisplayRange(
              direction: DisplayRangeDirection.forward,
              sourceRange: forwardRange,
              reason: 'segmented_cache_bounded_lookahead',
              generator: generateDisplayRange,
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
        'mode': 'progressive_segment_cache',
      });
      return;
    }
    final rangeGeneration = ++_progressiveRangeGeneration;
    final initialRequest = DisplayRangeRequest(
      direction: DisplayRangeDirection.initial,
      sourceRange: initialRange,
      generationId: rangeGeneration,
      reason: 'initial_open',
      targetOriginalIndex: startIndex,
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

    final initialResult = await generateDisplayRange(initialRequest);
    if (!mounted ||
        _rebuildGeneration != generation ||
        initialResult.cancelled) {
      _readerDiagLog('range_cancel', {
        'book': widget.bookId,
        'generation': generation,
        'rangeGeneration': rangeGeneration,
        'direction': DisplayRangeDirection.initial.name,
        'reason': 'stale_initial_generation',
      });
      return;
    }
    progressiveState.publishInitial(initialResult);
    progressiveState.sourceChunkCount =
        _progressiveSourceCountForLoadedWindow();
    _applyLazyExternalAvailability(progressiveState);
    progressiveState.generationComplete =
        !progressiveState.externalUnavailableBefore &&
        !progressiveState.externalUnavailableAfter &&
        initialResult.request.sourceRange.start == 0 &&
        initialResult.request.sourceRange.endExclusive >=
            progressiveState.sourceChunkCount;
    _applyProgressiveDisplayState(progressiveState);
    _displayChunksComplete = progressiveState.generationComplete;
    _hasCompletedDisplayChunkBuild = true;
    unawaited(
      _cacheProgressiveDisplayRange(
        cacheKey: signature.cacheKey,
        signature: signature,
        result: initialResult,
        generationId: rangeGeneration,
      ),
    );

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
      'sourceStart': initialRange.start,
      'sourceEndExclusive': initialRange.endExclusive,
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
    _maybeRequestCardDepthChapterCompletion(_currentPage);

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
            generator: generateDisplayRange,
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

  void _applyProgressiveDisplayState(ProgressiveDisplayState state) {
    _displayChunks
      ..clear()
      ..addAll(state.displayChunks);
    _displayToOriginal
      ..clear()
      ..addAll(state.displayToOriginal);
    _originalToDisplay
      ..clear()
      ..addAll(state.originalToDisplay);
    _displayChunksComplete = state.generationComplete;
  }

  void _markDisplayRebuildCompleted(
    int generation,
    DisplayGenerationSignature signature,
  ) {
    _lastCompletedDisplayRebuildGeneration = generation;
    _lastCompletedDisplayRebuildCacheKey = signature.cacheKey;
    _lastCompletedDisplayRebuildSignature = signature;
    _lastCompletedDisplayRebuildAtMs = DateTime.now().millisecondsSinceEpoch;
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
    final loaded = await service.loadAroundSource(
      key: key,
      sourceIndex: targetOriginalIndex,
    );
    final center = loaded.center;
    if (center == null) return false;
    if (!mounted || _rebuildGeneration != generation) return false;

    final centerGeneration = ++_progressiveRangeGeneration;
    progressiveState.publishInitial(
      center.toResult(
        direction: DisplayRangeDirection.initial,
        generationId: centerGeneration,
        reason: 'segmented_cache_initial',
        targetOriginalIndex: targetOriginalIndex,
      ),
    );

    final before = loaded.before;
    if (before != null &&
        before.record.sourceEndExclusive ==
            progressiveState.ranges.first.sourceRange.start) {
      progressiveState.prepend(
        before.toResult(
          direction: DisplayRangeDirection.backward,
          generationId: ++_progressiveRangeGeneration,
          reason: 'segmented_cache_prepend',
        ),
      );
    }

    final after = loaded.after;
    if (after != null &&
        after.record.sourceStart ==
            progressiveState.ranges.last.sourceRange.endExclusive) {
      progressiveState.append(
        after.toResult(
          direction: DisplayRangeDirection.forward,
          generationId: ++_progressiveRangeGeneration,
          reason: 'segmented_cache_append',
        ),
      );
    }

    _applyProgressiveDisplayState(progressiveState);
    _readerDiagLog('segment_cache_publish_initial', {
      'book': widget.bookId,
      'generation': generation,
      'targetOriginalIndex': targetOriginalIndex,
      'displayChunks': _displayChunks.length,
      'ranges': progressiveState.ranges.length,
      'sourceStart': progressiveState.ranges.first.sourceRange.start,
      'sourceEndExclusive':
          progressiveState.ranges.last.sourceRange.endExclusive,
    });
    return true;
  }

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
    await service.writeSegment(
      key: _segmentedDisplayCacheKey(
        cacheKey: cacheKey,
        signature: signature,
        sourceRange: result.request.sourceRange,
      ),
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
  }) {
    sourceRange = _clampToLoadedSourceRange(sourceRange);
    if (sourceRange.isEmpty) return Future.value();
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
        final result =
            await _loadCachedProgressiveDisplayRange(
              cacheKey: activeToken.signature.cacheKey,
              signature: activeToken.signature,
              request: request,
            ) ??
            await rangeGenerator(request);
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

        int insertedBefore = 0;
        if (direction == DisplayRangeDirection.backward ||
            (direction == DisplayRangeDirection.target &&
                state.ranges.isNotEmpty &&
                sourceRange.isAdjacentBefore(state.ranges.first.sourceRange))) {
          final anchor = _currentSourceAnchor();
          insertedBefore = state.prepend(result);
          _applyProgressiveDisplayState(state);
          _readerDiagLog('range_prepend', {
            'book': widget.bookId,
            'generation': generation,
            'rangeGeneration': rangeGeneration,
            'displayChunksInserted': insertedBefore,
            'sourceStart': sourceRange.start,
            'sourceEndExclusive': sourceRange.endExclusive,
          });
          _restoreSourceAnchorAfterPrepend(anchor, insertedBefore);
        } else if (direction == DisplayRangeDirection.initial ||
            direction == DisplayRangeDirection.target) {
          state.publishInitial(result);
          _applyProgressiveDisplayState(state);
        } else {
          state.append(result);
          _applyProgressiveDisplayState(state);
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
        if (!result.request.reason.startsWith('segmented_cache_') &&
            !result.request.reason.startsWith('display_memory_')) {
          unawaited(
            _cacheProgressiveDisplayRange(
              cacheKey: activeToken.signature.cacheKey,
              signature: activeToken.signature,
              result: result,
              generationId: rangeGeneration,
            ),
          );
        }
        if (mounted) setState(() {});
      } catch (error, stackTrace) {
        state.markFailure(request, error);
        _progressiveRangeFailure = error;
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
      _readerDiagLog('adjacent_section_display_memory_hit', {
        'book': widget.bookId,
        'cacheKey': cacheKey,
        'sourceStart': request.sourceRange.start,
        'sourceEndExclusive': request.sourceRange.endExclusive,
        'displayChunks': memory.displayChunks.length,
        'estimatedBytes': memory.estimatedBytes,
        'retainedBytes': _displaySectionMemoryCache.estimatedBytes,
      });
      return memory.toResult(
        direction: request.direction,
        generationId: request.generationId,
        reason: 'display_memory_${request.reason}',
        targetOriginalIndex: request.targetOriginalIndex,
      );
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
    return segment?.toResult(
      direction: request.direction,
      generationId: request.generationId,
      reason: 'segmented_cache_${request.reason}',
      targetOriginalIndex: request.targetOriginalIndex,
    );
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
      }
    });
  }

  ({int originalIndex, int? offset, String? sourceText})?
  _currentSourceAnchor() {
    if (_currentPage < 0 || _currentPage >= _displayChunks.length) return null;
    final anchor = _bookmarkAnchorForDisplayPage(_currentPage);
    if (anchor == null) return null;
    return (
      originalIndex: anchor.chunkIndex,
      offset: anchor.originalStartOffset,
      sourceText: anchor.previewText,
    );
  }

  void _restoreSourceAnchorAfterPrepend(
    ({int originalIndex, int? offset, String? sourceText})? anchor,
    int fallbackInsertedDisplayChunks,
  ) {
    if (anchor == null) {
      final shifted = (_currentPage + fallbackInsertedDisplayChunks).clamp(
        0,
        _displayChunks.length - 1,
      );
      _jumpToDisplayIndex(shifted);
      return;
    }
    final targetIndex =
        _displayIndexForSourceLocation(
          originalChunkIndex: anchor.originalIndex,
          originalStartOffset: anchor.offset,
          sourceText: anchor.sourceText,
        ) ??
        (_currentPage + fallbackInsertedDisplayChunks).clamp(
          0,
          _displayChunks.length - 1,
        );
    _jumpToDisplayIndex(targetIndex);
  }

  void _maybeRequestProgressiveBoundaryRange(int displayIndex) {
    final state = _progressiveDisplayState;
    if (state == null || _displayChunksComplete) return;
    if (_shouldLoadLazyForwardSection(displayIndex)) {
      unawaited(_loadLazyForwardSectionAndPrepareRange());
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
        await _integrateLazyForwardSection(section, operationId, generation);
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
      _progressiveRangeFailure = error;
      if (mounted) setState(() {});
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
  ) async {
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
    final state = _progressiveDisplayState;
    final canIncrementallyPrepend =
        state != null &&
        state.ranges.isNotEmpty &&
        state.ranges.first.sourceRange.start == 0 &&
        _activeProgressiveRangeTask == null;
    if (canIncrementallyPrepend) {
      final insertedCount = section.chunks.length;
      _prependLazySectionToSourceWindow(section);
      state.shiftSourceIndexes(insertedCount);
      state.sourceChunkCount = _progressiveSourceCountForLoadedWindow();
      _applyLazyExternalAvailability(state);
      _applyProgressiveDisplayState(state);
      final range = SourceChunkRange(0, insertedCount);
      await _prepareProgressiveDisplayRange(
        direction: DisplayRangeDirection.backward,
        sourceRange: range,
        reason: 'lazy_backward_boundary_incremental',
        parentGeneration: generation,
      );
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
    _displayChunks.clear();
    _displayToOriginal.clear();
    _originalToDisplay.clear();
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

  Future<void> _completeBackwardBoundaryNavigation({
    required int generation,
    required Duration duration,
    required Curve curve,
  }) async {
    const maxAttempts = 40;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted || generation != _rebuildGeneration) return;
      if (_displayChunks.isNotEmpty && _hasCompletedDisplayChunkBuild) {
        final loadedSpines = _loadedLazySpineIndexes();
        if (loadedSpines.isEmpty) return;
        final targetSpine = loadedSpines.reduce(math.min);
        final targetDisplayIndex = _lastDisplayIndexForSpine(targetSpine);
        if (targetDisplayIndex != null) {
          _pendingExactStableRestore = null;
          _preferSourceIndexOnNextRestore = false;
          _animateReaderToPage(
            targetDisplayIndex,
            duration: duration,
            curve: curve,
          );
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
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

  void _appendLazySectionToSourceWindow(ParsedSection section) {
    _cachedFlatChapters = null;
    final sourceStart = _sourceChunks.length;
    for (final entry in section.anchorMap.entries) {
      _sourceAnchorMap[entry.key] = sourceStart + entry.value;
    }
    var nextIndex = sourceStart;
    for (final chunk in section.chunks) {
      _sourceChunks.add(chunk.copyWith(index: nextIndex));
      _sourceLocationsByChunkIndex[nextIndex] = StableBookLocation(
        bookId: section.identity.bookId,
        spineIndex: section.identity.spineIndex,
        href: section.identity.href,
        sourceChecksum: section.identity.sourceChecksum,
        localChunkIndex: chunk.index,
        legacyGlobalChunkIndex: nextIndex,
        contextText: chunk.text,
      );
      final text = chunk.text;
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
    final oldSearch = Map<String, List<int>>.from(_sourceSearchIndex);

    _sourceChunks = <BookChunk>[];
    _sourceAnchorMap = <String, int>{};
    _sourceLocationsByChunkIndex = <int, StableBookLocation>{};
    _sourceSearchIndex = <String, List<int>>{};

    for (final entry in section.anchorMap.entries) {
      _sourceAnchorMap[entry.key] = entry.value;
    }
    for (final chunk in section.chunks) {
      final nextIndex = _sourceChunks.length;
      _sourceChunks.add(chunk.copyWith(index: nextIndex));
      _sourceLocationsByChunkIndex[nextIndex] = StableBookLocation(
        bookId: section.identity.bookId,
        spineIndex: section.identity.spineIndex,
        href: section.identity.href,
        sourceChecksum: section.identity.sourceChecksum,
        localChunkIndex: chunk.index,
        legacyGlobalChunkIndex: nextIndex,
        contextText: chunk.text,
      );
      _indexChunkTextForSearch(chunk.text, nextIndex);
    }

    for (final entry in _sourceAnchorMap.entries.toList()) {
      _sourceAnchorMap[entry.key] = entry.value;
    }
    for (final entry in oldAnchors.entries) {
      _sourceAnchorMap[entry.key] = entry.value + insertedCount;
    }
    for (final entry in oldLocations.entries) {
      _sourceLocationsByChunkIndex[entry.key + insertedCount] = entry.value
          .copyWith(legacyGlobalChunkIndex: entry.key + insertedCount);
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

  Future<StableBookLocation?> _navigateToStableLocation(
    StableBookLocation location,
  ) async {
    final session = _lazySession;
    var resolvedLocation = location;
    if (session != null) {
      final resolution = await session.resolveStableLocation(location);
      final resolved = resolution.location;
      if (resolved == null) {
        _readerDiagLog('stable_location_unresolved', {
          ..._stableLocationDiagFields(location),
          'reason': resolution.reason,
        });
        return null;
      }
      resolvedLocation = resolved;
    }

    final existingIndex = _sourceIndexForStableLocation(resolvedLocation);
    if (existingIndex != null) {
      unawaited(
        _navigateToSourceLocation(
          originalChunkIndex: existingIndex,
          originalStartOffset: resolvedLocation.textOffset,
          sourceText: resolvedLocation.contextText,
        ),
      );
      return resolvedLocation;
    }

    if (session == null) {
      final fallback = resolvedLocation.legacyGlobalChunkIndex;
      if (fallback != null) {
        unawaited(
          _navigateToSourceLocation(
            originalChunkIndex: fallback,
            originalStartOffset: resolvedLocation.textOffset,
            sourceText: resolvedLocation.contextText,
          ),
        );
      }
      return null;
    }

    _readerDiagLog('lazy_reader_section_requested', {
      'book': widget.bookId,
      'direction': 'target',
      'spineIndex': location.spineIndex,
      'href': location.href,
    });
    _commitCurrentPosition();
    final window = await session.loadAround(resolvedLocation, after: 0);
    if (!mounted) return null;
    _replaceLazySourceWindow(window);
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
    });
    _targetProgressRatio = _sourceChunks.isEmpty
        ? 0
        : _targetOriginalIndex / _sourceChunks.length;
    _displayGenerationCoordinator.cancelActive('lazy_target_window_replaced');
    _rebuildGeneration++;
    _progressiveRangeGeneration++;
    _progressiveDisplayState?.cancelActiveRequests();
    _progressiveDisplayState = null;
    _displayChunks.clear();
    _displayToOriginal.clear();
    _originalToDisplay.clear();
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
    });
    setState(() {});
    unawaited(
      _completeStableLocationNavigation(
        location: resolvedLocation,
        generation: _rebuildGeneration,
      ),
    );
    return resolvedLocation;
  }

  Future<void> _completeStableLocationNavigation({
    required StableBookLocation location,
    required int generation,
  }) async {
    const maxAttempts = 30;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted || generation != _rebuildGeneration) return;
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
          _navigateTo(displayIndex);
          _scheduleLazyAdjacentWarmup(location);
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _readerDiagLog('stable_location_navigation_timeout', {
      ..._stableLocationDiagFields(location),
      'generation': generation,
      'displayChunks': _displayChunks.length,
      'hasCompletedDisplayChunkBuild': _hasCompletedDisplayChunkBuild,
    });
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
    await _navigateToStableLocation(resolved);
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
    await _navigateToStableLocation(resolved);
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
    final originals = _displayToOriginal[displayIndex];
    if (originals.isEmpty) return null;
    return _stableLocationForOriginalIndex(originals.first);
  }

  void _replaceLazySourceWindow(LazyLoadedContentWindow window) {
    _sourceChunks = List<BookChunk>.from(window.chunks);
    _sourceAnchorMap = Map<String, int>.from(window.anchorMap);
    _sourceChapters = List<ChapterInfo>.from(window.chapters);
    _sourceSearchIndex = Map<String, List<int>>.from(window.searchIndex);
    _sourceLocationsByChunkIndex = Map<int, StableBookLocation>.from(
      window.locationsByChunkIndex,
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
    bool exploratory = true,
  }) async {
    final existing = _displayIndexForSourceLocation(
      originalChunkIndex: originalChunkIndex,
      originalStartOffset: originalStartOffset,
      sourceText: sourceText,
    );
    if (existing != null) {
      _navigateTo(existing, exploratory: exploratory);
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
        _navigateTo(retryDisplayIndex, exploratory: exploratory);
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
      _navigateTo(displayIndex, exploratory: exploratory);
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

      final milestoneChunk = BookChunk(
        index: -1, // synthetic — doesn't map to any original chunk
        type: BookChunkType.milestone,
        text: ms.text,
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
    _positionSession.markCommitted(index);
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
    if (_displayToOriginal.length > index) {
      _deferSaveReadingPosition(index);
    }
    _maybeRequestProgressiveBoundaryRange(index);
    _maybeRequestCardDepthChapterCompletion(index);

    // Detect book completion — show overlay when reaching the last page
    if (!_hasShownCompletion &&
        _displayChunksComplete &&
        _displayChunks.isNotEmpty &&
        index >= _displayChunks.length - 1) {
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

  CardDepthChapterPageMeta _cardDepthChapterMetaForDisplayIndex(
    int displayIndex,
  ) {
    return CardDepthChapterProgressService.calculate(
      displayIndex: displayIndex,
      displayChunkCount: _displayChunks.length,
      displayToOriginal: _displayToOriginal,
      locationsByChunkIndex: _sourceLocationsByChunkIndex,
      chapterNavigationTargets: _chapterNavigationTargets,
      displayChunksComplete: _displayChunksComplete,
      fallbackFlatChapters: _flatChapters,
    );
  }

  StableBookLocation? _firstLocationForDisplayIndex(int displayIndex) {
    if (displayIndex < 0 || displayIndex >= _displayToOriginal.length) {
      return null;
    }
    for (final original in _displayToOriginal[displayIndex]) {
      final location = _sourceLocationsByChunkIndex[original];
      if (location != null) return location;
    }
    return null;
  }

  void _maybeRequestCardDepthChapterCompletion(int displayIndex) {
    if (!_settings.enableCardDepth ||
        _lazySession == null ||
        _displayChunksComplete ||
        displayIndex < 0 ||
        displayIndex >= _displayToOriginal.length) {
      return;
    }

    final meta = _cardDepthChapterMetaForDisplayIndex(displayIndex);
    if (!meta.shouldRequestChapterCompletion) return;

    final currentLocation = _firstLocationForDisplayIndex(displayIndex);
    if (currentLocation == null) return;
    final selectableTargets = _chapterNavigationTargets
        .where((target) => target.isSelectable)
        .toList(growable: false);
    final currentTargetIndex = ChapterNavigationService.currentTargetIndex(
      selectableTargets,
      currentLocation,
    );
    if (currentTargetIndex < 0) return;

    final nextTarget = currentTargetIndex + 1 < selectableTargets.length
        ? selectableTargets[currentTargetIndex + 1]
        : null;
    if (nextTarget == null) {
      // With no canonical next chapter target, avoid walking the whole book just
      // to prove the final denominator. The inexact `page / ?` footer remains
      // honest while normal lazy boundary reads continue to load content.
      return;
    }

    final key =
        '$_rebuildGeneration:${nextTarget.spineIndex}:'
        '${nextTarget.anchorId ?? ''}:'
        '${nextTarget.resolvedLocalChunkIndex ?? -1}:'
        '${nextTarget.textOffset}';
    if (_activeCardDepthChapterCompletionKey == key) return;
    _activeCardDepthChapterCompletionKey = key;
    unawaited(
      _completeCardDepthCurrentChapterBoundary(
        nextTarget: nextTarget,
        key: key,
        generation: _rebuildGeneration,
      ),
    );
  }

  Future<void> _completeCardDepthCurrentChapterBoundary({
    required ChapterNavigationTarget nextTarget,
    required String key,
    required int generation,
  }) async {
    try {
      _readerDiagLog('card_depth_chapter_completion_requested', {
        'book': widget.bookId,
        'generation': generation,
        'targetSpineIndex': nextTarget.spineIndex,
        'targetHref': nextTarget.href,
        'targetAnchorId': nextTarget.anchorId,
      });

      while (mounted &&
          generation == _rebuildGeneration &&
          _lazySession != null) {
        final loadedSpines = _loadedLazySpineIndexes();
        if (loadedSpines.contains(nextTarget.spineIndex)) break;
        if (loadedSpines.isEmpty ||
            nextTarget.spineIndex < loadedSpines.reduce(math.min)) {
          return;
        }
        if (nextTarget.spineIndex <= loadedSpines.reduce(math.max)) break;

        final loaded = await _ensureAdjacentSectionAvailable(
          DisplayRangeDirection.forward,
          reason: 'card_depth_current_chapter_boundary',
        );
        if (!loaded) return;
      }
      if (!mounted || generation != _rebuildGeneration) return;

      final targetSourceIndex = _sourceIndexForStableLocation(
        nextTarget.stableLocation,
      );
      if (targetSourceIndex == null) return;
      if (_progressiveDisplayState?.isSourcePrepared(targetSourceIndex) ==
          true) {
        if (mounted) setState(() {});
        return;
      }

      final prepared = _progressiveDisplayState?.preparedSourceRange;
      final start = prepared == null
          ? math.max(0, targetSourceIndex - _lazyInitialRangeLookBehind)
          : prepared.endExclusive;
      final end = math.min(_sourceChunks.length, targetSourceIndex + 1);
      if (end <= start) return;

      await _prepareProgressiveDisplayRange(
        direction: DisplayRangeDirection.forward,
        sourceRange: SourceChunkRange(start, end),
        reason: 'card_depth_current_chapter_boundary',
        parentGeneration: generation,
        targetOriginalIndex: targetSourceIndex,
      );
    } finally {
      if (_activeCardDepthChapterCompletionKey == key) {
        _activeCardDepthChapterCompletionKey = null;
      }
    }
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

    _runCommittedPageEffects(index);
  }

  void _deferSaveReadingPosition(int index) {
    // Use a post-frame callback to avoid jank during the swipe animation
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleReadingPositionSave(index);
    });
  }

  void _scheduleReadingPositionSave(int index) {
    if (!_positionSession.canCommitActiveVisiblePosition) return;
    _pendingPositionSaveIndex = index;
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(const Duration(milliseconds: 1200), () {
      unawaited(_flushPendingReadingPosition());
    });
  }

  Future<void> _flushPendingReadingPosition() async {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    final index = _pendingPositionSaveIndex;
    if (index == null) return;

    _pendingPositionSaveIndex = null;
    await _persistReadingPosition(index);
  }

  Future<void> _persistReadingPosition(int index) async {
    if (index >= _displayToOriginal.length) return;
    final originals = _displayToOriginal[index];
    if (originals.isEmpty) return;
    if (!_positionSession.canCommitActiveVisiblePosition &&
        _positionSession.previewPosition == index) {
      return;
    }

    // If we're on the very last display page, force originalIndex to the very end
    // so progress calculates out to precisely 100%.
    final bool isLastPage =
        _displayChunksComplete && index == _displayToOriginal.length - 1;
    final originalIndex = isLastPage
        ? _sourceChunks.length - 1
        : originals.first;
    final stableLocation = _stableLocationForOriginalIndex(originalIndex)
        ?.copyWith(
          localDisplayIndex: index,
          readerLayoutFingerprint: _activeReaderLayoutFingerprint,
          previousSpineIndex: _previousSpineIndexForOriginalIndex(
            originalIndex,
          ),
          nextSpineIndex: _nextSpineIndexForOriginalIndex(originalIndex),
        );

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt('last_read_${widget.bookId}', originalIndex);
    _positionSession.markCommitted(index);

    final metadata = _metadataService.getMetadata(widget.bookId);
    if (metadata != null) {
      final updated = metadata.copyWith(
        lastReadIndex: originalIndex,
        lastReadLocation: stableLocation,
        totalChunks: _sourceChunks.length,
        lastReadTime: DateTime.now().millisecondsSinceEpoch,
      );
      await _metadataService.updateMetadata(updated);
      if (stableLocation != null) {
        _readerDiagLog('stable_location_saved', {
          ..._stableLocationDiagFields(stableLocation),
          'displayIndex': index,
          'originalIndex': originalIndex,
          'totalChunks': _sourceChunks.length,
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
      unawaited(_navigateToStableLocation(top.stableLocation!));
      _updatePositionHistoryNotifier();
      return;
    }

    // Jump to the saved position. Recalculate display index using original just in case font changed.
    final rebuiltDisplayTarget = _originalToDisplay[top.chunkIndex];
    if (rebuiltDisplayTarget == null) {
      unawaited(_navigateToSourceLocation(originalChunkIndex: top.chunkIndex));
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
      unawaited(_navigateToSourceLocation(originalChunkIndex: originalIndex));
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
          unawaited(_navigateToStableLocation(target));
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

  int? _displayIndexForBookmark(Bookmark bookmark) {
    return _displayIndexForSourceLocation(
      originalChunkIndex: bookmark.chunkIndex,
      originalStartOffset: bookmark.originalStartOffset,
      sourceText: bookmark.previewText,
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

    final bookmarked = _bookmarks.cast<Bookmark?>().firstWhere(
      (bookmark) =>
          bookmark != null &&
          bookmark.isSameLocation(
            anchor.chunkIndex,
            anchor.originalStartOffset,
          ),
      orElse: () => null,
    );

    if (bookmarked != null) {
      // Unbookmark
      final updated = await _bookmarkService.remove(
        bookmarked.chunkIndex,
        originalStartOffset: bookmarked.originalStartOffset,
      );
      setState(() {
        _bookmarks = updated;
        _bookmarkDisplayHints.remove(bookmarked.locationKey);
      });
    } else {
      final updated = await _bookmarkService.add(
        anchor.chunkIndex,
        originalStartOffset: anchor.originalStartOffset,
        previewText: anchor.previewText,
        colorIndex: _defaultBookmarkFixedIndex,
        colorValue: _defaultBookmarkCustomColorValue,
        stableLocation: _stableLocationForOriginalIndex(
          anchor.chunkIndex,
          textOffset: anchor.originalStartOffset,
        ),
      );
      setState(() {
        _bookmarks = updated;
        _bookmarkDisplayHints['${anchor.chunkIndex}:${anchor.originalStartOffset}'] =
            displayIndex;
      });
    }
  }

  Future<void> _onBookmarkLongPress(int displayIndex) async {
    final anchor = _bookmarkAnchorForDisplayPage(displayIndex);
    if (anchor == null) return;

    final bookmark = _bookmarks.cast<Bookmark?>().firstWhere(
      (entry) =>
          entry != null &&
          entry.isSameLocation(anchor.chunkIndex, anchor.originalStartOffset),
      orElse: () => null,
    );
    if (bookmark == null) return;

    _showRenameDialog(bookmark);
  }

  Future<void> _onTripleTap(int displayIndex) async {
    final anchor = _bookmarkAnchorForDisplayPage(displayIndex);
    if (anchor == null) return;

    // Ensure bookmark exists
    var bookmark = _bookmarks.cast<Bookmark?>().firstWhere(
      (entry) =>
          entry != null &&
          entry.isSameLocation(anchor.chunkIndex, anchor.originalStartOffset),
      orElse: () => null,
    );
    if (bookmark == null) {
      final updated = await _bookmarkService.add(
        anchor.chunkIndex,
        originalStartOffset: anchor.originalStartOffset,
        previewText: anchor.previewText,
        colorIndex: _defaultBookmarkFixedIndex,
        colorValue: _defaultBookmarkCustomColorValue,
        stableLocation: _stableLocationForOriginalIndex(
          anchor.chunkIndex,
          textOffset: anchor.originalStartOffset,
        ),
      );
      setState(() {
        _bookmarks = updated;
        _bookmarkDisplayHints['${anchor.chunkIndex}:${anchor.originalStartOffset}'] =
            displayIndex;
      });
      bookmark = updated.firstWhere(
        (entry) =>
            entry.isSameLocation(anchor.chunkIndex, anchor.originalStartOffset),
      );
    }

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

    final updated = await _bookmarkService.update(
      bookmark.chunkIndex,
      originalStartOffset: bookmark.originalStartOffset,
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
    if (displayIndex < 0 || displayIndex >= _displayChunks.length) return;

    final metadata = _metadataService.getMetadata(widget.bookId);
    final title = metadata?.title.trim().isNotEmpty == true
        ? metadata!.title
        : widget.title;

    late final QuoteSharePayload payload;
    try {
      payload = QuoteSharePayload.fromSelection(
        quote: text,
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

    await _runWithReaderControlsSuspended(() {
      return Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => QuoteCardPreviewScreen(payload: payload),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
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
    String text,
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
      text: text,
      color: color,
      type: type,
      note: note,
    );
  }

  Future<void> _onMappedNoteCreated(
    List<MappedTextRange> mappedRanges,
    String text,
    Color color,
    String note,
  ) async {
    await _saveMappedHighlight(
      translatedRanges: mappedRanges,
      text: text,
      color: color,
      type: HighlightType.highlight,
      note: note,
    );
  }

  Future<void> _saveMappedHighlight({
    required List<MappedTextRange> translatedRanges,
    required String text,
    required Color color,
    required HighlightType type,
    String? note,
  }) async {
    if (translatedRanges.isEmpty) return;

    final trimmedNote = note?.trim();
    final isNoteBackedHighlight =
        type == HighlightType.highlight &&
        trimmedNote != null &&
        trimmedNote.isNotEmpty;

    if (isNoteBackedHighlight) {
      Set<String>? exactMatchingIds;
      for (final range in translatedRanges) {
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
    final hasOverlap = translatedRanges.any(
      (range) => _highlights.any(
        (hl) =>
            hl.originalChunkIndex == range.originalChunkIndex &&
            hl.type == type &&
            (range.originalStartOffset < hl.endOffset &&
                range.originalEndOffset > hl.startOffset),
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
    for (final range in translatedRanges) {
      final newHighlight = Highlight(
        id: highlightId,
        originalChunkIndex: range.originalChunkIndex,
        startOffset: range.originalStartOffset,
        endOffset: range.originalEndOffset,
        text: text,
        colorIndex: defaultHighlightColorIndex(normalizedColor) ?? 0,
        colorValue: highlightColorValue(normalizedColor),
        type: type,
        note: trimmedNote,
        createdAt: createdAt,
        stableLocation: _stableLocationForOriginalIndex(
          range.originalChunkIndex,
          textOffset: range.originalStartOffset,
        ),
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

  /// Build a map of character name → color from all character highlights.
  /// Used to style every occurrence of each character name across all pages.
  Map<String, Color> _buildCharacterNamesMap() {
    final map = <String, Color>{};
    for (final hl in _highlights) {
      if (hl.isCharacter) {
        // If the same name is marked multiple times, use the most recent color
        map[hl.text] = hl.color;
      }
    }
    return map;
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
    if (_lazySession != null && !_displayChunksComplete) {
      final location = _currentStableLocation();
      if (location != null) {
        return _titleForSpineIndex(location.spineIndex);
      }
      return 'Preparing pages';
    }
    return 'Page ${displayIndex + 1} of ${_displayPageTotalLabel()}';
  }

  // ─── Navigation ──────────────────────────────────────────────────────

  void _navigateTo(int targetIndex, {bool exploratory = true}) {
    _markForegroundReaderWork('navigate_to_page');
    if (_currentPage != targetIndex) {
      if (exploratory) {
        if (!_positionSession.hasActivePreviewPosition) {
          _commitCurrentPosition();
        }
        _positionSession.startPreview(_currentPage);
        _jumpReaderToPage(targetIndex, asPreview: true);
        _positionSession.finishScrub();
        _schedulePreviewPromotion(targetIndex);
      } else {
        _clearPreviewState(visibleDisplayIndex: _currentPage);
        _jumpReaderToPage(targetIndex);
      }
    }
  }

  Future<void> _openSearchScreen() async {
    await _flushReadingSession();
    if (!mounted) return;
    final targetIndex = await _runWithReaderControlsSuspended(() {
      return Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => SearchScreen(
            chunks: _sourceChunks,
            searchIndex: _sourceSearchIndex,
            initialSettings: _settings,
          ),
        ),
      );
    });
    if (mounted) {
      _startReadingSession();
    }

    if (targetIndex != null) {
      unawaited(_navigateToSourceLocation(originalChunkIndex: targetIndex));
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

    if (_lazySession != null && !_displayChunksComplete) {
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
    _positionSession.updatePreview(targetIndex);
    _positionSession.finishScrub();
    _schedulePreviewPromotion(targetIndex);

    if (previewAlreadyVisible) {
      return;
    }

    _jumpReaderToPage(targetIndex, asPreview: true);
  }

  void _commitLazyStructuralScrub(double progression) {
    final session = _lazySession;
    if (session == null) return;
    setState(() {
      _isScrubbing = false;
      _lazyScrubPreviewSpineIndex = null;
    });
    _commitCurrentPosition();
    unawaited(
      _navigateToStableLocation(
        session.locationForWeightedProgression(progression),
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
    final value = totalWeight <= 0
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
              onChangeStart: (_) {
                _dwellTimer?.cancel();
                _cancelPreviewPromotionTimer();
                setState(() {
                  _isScrubbing = true;
                  _lazyScrubPreviewSpineIndex = currentSpine;
                });
              },
              onChanged: (next) {
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
      unawaited(_navigateToStableLocation(targetLocation));
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
      _navigateTo(displayIdx);
      return target.title;
    }
    unawaited(_navigateToSourceLocation(originalChunkIndex: target.chunkIndex));
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
      unawaited(_navigateToStableLocation(target.stableLocation));
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
      _navigateTo(displayIdx);
      return target.title;
    }
    unawaited(_navigateToSourceLocation(originalChunkIndex: target.chunkIndex));
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
      unawaited(_ensureInsightChaptersRegistered());
    }

    // Show loading indicator while display chunks are being built/loaded.
    // Avoid showing the empty-book state before the first async layout pass
    // has finished; that caused a split-second false empty screen on launch.
    if (_displayChunks.isEmpty &&
        _sourceChunks.isNotEmpty &&
        (_isRebuildingChunks || !_hasCompletedDisplayChunkBuild)) {
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
      locationsByChunkIndex: _sourceLocationsByChunkIndex,
    );

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
              displayToOriginal: _displayToOriginal,
              originalToDisplay: _originalToDisplay,
              flatChapters: _flatChapters,
              chapterNavigationTargets: _chapterNavigationTargets,
              sourceLocationsByChunkIndex: _sourceLocationsByChunkIndex,
              displayChunksComplete: _displayChunksComplete,
              canSwipe:
                  !_overlayVisible &&
                  speedReadAllowsManualNavigation &&
                  _readerSurfaceBlockCount == 0 &&
                  !_cardInteractionBlocked &&
                  !_isCelebrationVisible,
              settings: _settings,
              bookmarkService: _bookmarkService,
              bookmarks: _bookmarks,
              bookmarkDisplayHints: _bookmarkDisplayHints,
              onPageChanged: _onPageChanged,
              onLinkTap: _onLinkTap,
              onDoubleTap: _onBookmarkTap,
              onTripleTap: _onTripleTap,
              onBookmarkLongPress: _onBookmarkLongPress,
              onImageTap: _openBookImageViewer,
              highlights: renderHighlights,
              characterNames: _buildCharacterNamesMap(),
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

        if (_isPreparingForwardRange ||
            _isPreparingBackwardRange ||
            _isPreparingTargetRange ||
            _progressiveRangeFailure != null)
          _buildProgressiveBoundaryStatus(),

        // ── Book completion celebration overlay ──
        if (_displayChunksComplete &&
            _isCelebrationVisible &&
            _currentPage >= _displayChunks.length - 1)
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

    return Theme(
      data: AppUi.readerTheme(_settings),
      child: Transform.scale(
        scale: _liveScale,
        child: Scaffold(
          backgroundColor: bgColor,
          resizeToAvoidBottomInset: false,
          body: body,
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
    final label = failure != null
        ? 'Could not prepare that range'
        : _isPreparingTargetRange
        ? 'Preparing destination...'
        : _isPreparingBackwardRange
        ? 'Preparing previous pages...'
        : 'Preparing next pages...';
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 18,
      child: IgnorePointer(
        ignoring: failure == null,
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
                if (failure == null)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _settings.mutedColor,
                    ),
                  )
                else
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
                if (failure != null)
                  TextButton(
                    onPressed: () {
                      final failed = _progressiveDisplayState?.failedRequest;
                      if (failed == null) return;
                      _progressiveRangeFailure = null;
                      unawaited(
                        _prepareProgressiveDisplayRange(
                          direction: failed.direction,
                          sourceRange: failed.sourceRange,
                          reason: 'retry_failed_range',
                          targetOriginalIndex: failed.targetOriginalIndex,
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

  void _handleSettingsUpdate(ReadingSettings updated) {
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

    if (!needsRebuild) {
      // Alignment, theme, paging controls, and blue light do not need
      // chunk regeneration.
      final oldController = pagingAxisChanged ? _pageController : null;
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
      _settingsService.saveSettings(updated);
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
      _settingsService.saveSettings(updated);
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
                      _handleSettingsUpdate(updated);
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
            _navigateToSourceLocation(originalChunkIndex: originalIndex),
          );
        },
        onNavigateChapter: (chapter) {
          final location = chapter.stableLocation;
          if (location != null) {
            unawaited(_navigateToStableLocation(location));
          } else {
            unawaited(
              _navigateToSourceLocation(originalChunkIndex: chapter.chunkIndex),
            );
          }
        },
        onNavigateBookmark: (bookmark) {
          final location = bookmark.stableLocation;
          if (location != null) {
            unawaited(_navigateToStableLocation(location));
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
          final updated = await _bookmarkService.remove(
            bookmark.chunkIndex,
            originalStartOffset: bookmark.originalStartOffset,
          );
          setState(() {
            _bookmarks = updated;
            _bookmarkDisplayHints.remove(bookmark.locationKey);
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
    final progressPercent = _displayChunks.isNotEmpty
        ? ((displayedPage + 1) / _displayChunks.length * 100).round()
        : 0;
    final progressLabel = _displayChunksComplete
        ? '$progressPercent%'
        : 'Preparing pages';

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
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;
  final List<({int chunkIndex, String title})> flatChapters;
  final List<ChapterNavigationTarget> chapterNavigationTargets;
  final Map<int, StableBookLocation> sourceLocationsByChunkIndex;
  final bool displayChunksComplete;
  final bool canSwipe;
  final ReadingSettings settings;
  final BookmarkService bookmarkService;
  final List<Bookmark> bookmarks;
  final Map<String, int> bookmarkDisplayHints;
  final ValueChanged<int> onPageChanged;
  final Function(String url) onLinkTap;
  final Function(int displayIndex) onDoubleTap;
  final Function(int displayIndex) onTripleTap;
  final Function(int displayIndex) onBookmarkLongPress;
  final Future<void> Function(int displayIndex)? onImageTap;
  final SpeedReadController speedReadController;

  // ── Highlights ──
  final List<Highlight> highlights;
  final Map<String, Color> characterNames;
  final FutureOr<void> Function(
    int displayIndex,
    int startOffset,
    int endOffset,
    String text,
    Color color,
    HighlightType type, [
    String? note,
  ])?
  onHighlightCreated;
  final void Function(
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
    required this.displayToOriginal,
    required this.originalToDisplay,
    required this.flatChapters,
    required this.chapterNavigationTargets,
    required this.sourceLocationsByChunkIndex,
    required this.displayChunksComplete,
    required this.canSwipe,
    required this.settings,
    required this.bookmarkService,
    required this.bookmarks,
    required this.bookmarkDisplayHints,
    required this.onPageChanged,
    required this.onLinkTap,
    required this.onDoubleTap,
    required this.onTripleTap,
    required this.onBookmarkLongPress,
    this.onImageTap,
    this.highlights = const [],
    this.characterNames = const {},
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
    return CardDepthChapterProgressService.calculate(
      displayIndex: displayIndex,
      displayChunkCount: displayChunks.length,
      displayToOriginal: displayToOriginal,
      locationsByChunkIndex: sourceLocationsByChunkIndex,
      chapterNavigationTargets: chapterNavigationTargets,
      displayChunksComplete: displayChunksComplete,
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
          final hintedIndex = bookmarkDisplayHints[candidate.locationKey];
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
      characterNames: characterNames,
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
          ? (start, end, text) {
              onQuoteShareRequested?.call(index, start, end, text);
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

    return PageView.builder(
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
