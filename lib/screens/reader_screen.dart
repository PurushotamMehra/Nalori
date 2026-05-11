import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/quote_share_payload.dart';
import '../models/reading_settings.dart';
import '../services/bookmark_service.dart';
import '../services/dictionary_service.dart';
import '../services/highlight_palette_service.dart';
import '../services/highlight_service.dart';
import '../services/book_cache_service.dart';
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
import '../ui/app_visuals.dart';
import '../utils/reader_content_parser.dart';
import 'quote_card_preview_screen.dart';
import 'search_screen.dart';
import 'book_image_viewer_screen.dart';
import '../utils/text_span_utils.dart';
import 'dart:async';
import 'dart:math' as math;
import '../models/position_history.dart';

/// Screen 2 — fullscreen vertical-swipe reader with progress tracking,
/// overlay menu (scrubber + navigation), and bookmark management.
class ReaderScreen extends StatefulWidget {
  final String title;
  final String bookId;
  final List<BookChunk> chunks;
  final Map<String, int> anchorMap;
  final List<ChapterInfo> chapters;
  final Map<String, List<int>> searchIndex;

  const ReaderScreen({
    super.key,
    required this.title,
    required this.bookId,
    required this.chunks,
    required this.anchorMap,
    required this.chapters,
    required this.searchIndex,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

/// Shared layout constants so boundary lines, ReadingCard padding,
/// and chunk-splitting all agree on the exact same measurements.
const double kBoundaryTop = 14.0;
const double kBoundaryBottom = 16.0;
const double kContentPaddingH = 24.0;
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
  final contentPadding = EdgeInsets.fromLTRB(
    safeArea.left + kContentPaddingH,
    safeArea.top + readerBoundaryTopInset(settings) + depthHeaderReserve,
    safeArea.right + kContentPaddingH,
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

  bool _ready = false;
  int _currentPage = 0;
  int _targetOriginalIndex = 0;
  double _targetProgressRatio = 0.0; // 0.0–1.0 position through the book
  bool _isFirstLayout = true;
  Size? _lastScreenSize;
  EdgeInsets? _lastSafeArea;
  TextScaler? _lastTextScaler;
  bool _isReaderLifecycleActive = true;
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

  // Settings
  final _settingsService = ReadingSettingsService();
  final _bookReaderThemeService = BookReaderThemeService();
  final _educationService = UserEducationService();
  ReadingSettings _settings = const ReadingSettings();

  // Metadata
  final _metadataService = BookMetadataService();

  // Cached preferences to avoid repeated async lookups
  SharedPreferences? _prefs;

  // Display chunk caching
  final _bookCacheService = BookCacheService();
  bool _isRebuildingChunks = false; // true while async batch measurement runs
  bool _hasCompletedDisplayChunkBuild = false;
  int _rebuildGeneration = 0; // cancellation token for async rebuilds

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

  static const int _positionAnchorLength = 120;

  // Live scale for Transform.scale visual feedback during slider drag
  double _liveScale = 1.0;

  // Book completion tracking
  bool _hasShownCompletion = false;
  bool _isCelebrationVisible = false;
  bool _showReaderGestureHint = false;
  bool _readerGestureHintCheckStarted = false;
  Timer? _readerGestureHintTimer;
  Timer? _hardwarePageRepeatStartTimer;
  Timer? _hardwarePageRepeatTimer;
  int? _hardwarePageRepeatDelta;

  // Position History
  final List<PositionHistory> _positionStack = [];
  Timer? _dwellTimer;
  Timer? _positionSaveTimer;
  int? _pendingPositionSaveIndex;
  bool _isScrubbing = false;
  int? _scrubStartDisplayIndex;
  int? _scrubPreviewDisplayIndex;
  int? _lastDwellPage;
  DateTime? _readingSessionStartedAt;
  final ValueNotifier<PositionHistory?> _positionHistoryNotifier =
      ValueNotifier(null);

  @override
  void initState() {
    super.initState();
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
          _currentPage >= _displayChunks.length - 1) {
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
    _readerControlsChannel.setMethodCallHandler(null);
    unawaited(_setNativeReaderControls(readerVisible: false));
    _dwellTimer?.cancel();
    _readerGestureHintTimer?.cancel();
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
        _stopHardwarePagePress();
        if (_speedReadController.isActive && !_speedReadController.isPaused) {
          _speedReadController.pause();
          _speedReadLifecycleAutoPaused = true;
        }
        unawaited(_syncNativeReaderControlsState());
        _syncRestoreTargetFromDisplayIndex(_currentPage);
        unawaited(_flushReaderPersistence(includeCurrentPosition: true));
        break;
      case AppLifecycleState.resumed:
        _isReaderLifecycleActive = true;
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
        _displayChunks.isNotEmpty &&
        _displayToOriginal.isNotEmpty) {
      _pendingPositionSaveIndex = _currentPage.clamp(
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

  void _jumpReaderToPage(int targetIndex) {
    if (_displayChunks.isEmpty) return;
    final clamped = targetIndex.clamp(0, _displayChunks.length - 1);
    if (_usesInteractiveCardDeck || _pageController?.hasClients != true) {
      if (_currentPage != clamped ||
          _activeDisplayIndex != clamped ||
          _isScrubbing) {
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
    if (_currentPage >= _displayChunks.length - 1) return;
    _animateReaderToPage(_currentPage + 1, duration: duration, curve: curve);
  }

  void _previousReaderPage({required Duration duration, required Curve curve}) {
    if (_currentPage <= 0) return;
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
    if (widget.chunks.isEmpty) {
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

    if (metadata != null && metadata.lastReadIndex > 0) {
      lastIndex = metadata.lastReadIndex;
    }

    _targetOriginalIndex = lastIndex.clamp(0, widget.chunks.length - 1);

    final bookmarks = await _bookmarkService.load();
    final defaultBookmarkColor = await _bookmarkService.loadDefaultColorIndex();
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
      _defaultBookmarkColorIndex = defaultBookmarkColor;
      _highlights = highlights;
      _highlightPalette = highlightPalette;
      _defaultHighlightColor = Color(
        highlightColorValue(defaultHighlightColor),
      );
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
    if (_lastScreenSize == screenSize &&
        _lastSafeArea == safeArea &&
        _lastTextScaler == textScaler &&
        _displayChunks.isNotEmpty) {
      return;
    }

    _lastScreenSize = screenSize;
    _lastSafeArea = safeArea;
    _lastTextScaler = textScaler;
    _hasCompletedDisplayChunkBuild = false;

    final cacheKey = BookCacheService.displayChunkKey(
      bookId: widget.bookId,
      fontSize: _settings.fontSizeValue,
      fontFamily: _settings.fontFamily.name,
      fontWeight: _settings.fontWeight.name,
      density: _settings.densityMultiplier,
      lineHeight: _settings.lineHeight,
      screenW: screenSize.width,
      screenH: screenSize.height,
      enableCardDepth: _settings.enableCardDepth,
      textScaleFactor: textScaler.scale(1.0),
      safeAreaTop: safeArea.top,
      safeAreaBottom: safeArea.bottom,
      safeAreaLeft: safeArea.left,
      safeAreaRight: safeArea.right,
    );

    // Prevent concurrent rebuilds — if one is already in flight, let it finish.
    if (_isRebuildingChunks) {
      if (kDebugMode) {
        debugPrint('[_ensureDisplayChunksBuilt] already rebuilding, skipping');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[_ensureDisplayChunksBuilt] launching loadOrRebuild cacheKey=$cacheKey',
      );
    }
    _isRebuildingChunks = true;
    _loadOrRebuildDisplayChunks(screenSize, safeArea, textScaler, cacheKey);
  }

  Future<void> _loadOrRebuildDisplayChunks(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
    String cacheKey,
  ) async {
    _rebuildGeneration++;
    final thisGen = _rebuildGeneration;
    if (kDebugMode) {
      debugPrint('[_loadOrRebuildDisplayChunks] start gen=$thisGen');
    }

    final cached = await _bookCacheService.loadDisplayChunks(cacheKey);
    if (kDebugMode) {
      debugPrint('[_loadOrRebuildDisplayChunks] gen=$thisGen cacheLoaded');
    }

    if (!mounted || _rebuildGeneration != thisGen) {
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
      _restorePosition();
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[_loadOrRebuildDisplayChunks] gen=$thisGen CACHE MISS -> triggering rebuild',
      );
    }
    await _rebuildDisplayChunksAsync(
      screenSize,
      safeArea,
      textScaler,
      cacheKey,
      thisGen,
    );
  }

  /// Restore the reading position after display chunks change.
  /// Uses text-anchor matching first, then falls back to index/ratio-based positioning.
  void _restorePosition() {
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

  /// Jump to a display index without animation, then clear rebuilding state.
  void _jumpToDisplayIndex(int index) {
    _hasCompletedDisplayChunkBuild = true;
    _currentPage = index;
    _activeDisplayIndex = index;
    _syncRestoreTargetFromDisplayIndex(index);
    if (_pageController == null) {
      _pageController = PageController(initialPage: index, keepPage: false);
    } else if (_pageController!.hasClients) {
      _pageController!.jumpToPage(index);
    } else {
      _pageController?.dispose();
      _pageController = PageController(initialPage: index, keepPage: false);
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
    _targetOriginalIndex = originals.first.clamp(0, widget.chunks.length - 1);
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
    int generation,
  ) async {
    if (kDebugMode) {
      debugPrint(
        '[_rebuildDisplayChunksAsync] gen=$generation currentGen=$_rebuildGeneration',
      );
    }
    if (_rebuildGeneration != generation) {
      if (kDebugMode) {
        debugPrint(
          '[_rebuildDisplayChunksAsync] gen=$generation STALE -> returning immediately',
        );
      }
      return;
    }
    setState(() => _isRebuildingChunks = true);
    if (kDebugMode) {
      debugPrint(
        '[_rebuildDisplayChunksAsync] gen=$generation marked rebuilding=true',
      );
    }

    await Future.delayed(Duration.zero);
    if (!mounted || _rebuildGeneration != generation) {
      if (kDebugMode) {
        debugPrint(
          '[_rebuildDisplayChunksAsync] gen=$generation cancelled after yield',
        );
      }
      return;
    }

    await _rebuildDisplayChunks(screenSize, safeArea, textScaler, generation);

    if (!mounted || _rebuildGeneration != generation) {
      if (kDebugMode) {
        debugPrint(
          '[_rebuildDisplayChunksAsync] gen=$generation cancelled after rebuild',
        );
      }
      return;
    }

    _restorePosition();

    _bookCacheService.cacheDisplayChunks(
      key: cacheKey,
      displayChunks: List.of(_displayChunks),
      displayToOriginal: List.of(_displayToOriginal),
      originalToDisplay: Map.of(_originalToDisplay),
    );
  }

  Future<void> _rebuildDisplayChunks(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
    int generation,
  ) async {
    final List<BookChunk> newDisplayChunks = [];
    final List<List<int>> newDisplayToOriginal = [];
    final Map<int, int> newOriginalToDisplay = {};

    if (widget.chunks.isEmpty) {
      _displayChunks.clear();
      _displayToOriginal.clear();
      _originalToDisplay.clear();
      return;
    }

    final layoutMetrics = resolveReaderLayoutMetrics(
      screenSize,
      safeArea,
      _settings,
    );
    final availableWidth = layoutMetrics.availableWidth;
    final fullBoundsHeight = layoutMetrics.availableHeight;
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

    // Helper: measures exact painted height, using the same textScaler
    // as the Text widget so measurements are pixel-accurate.
    double measureTextHeight(
      String text,
      BookChunk chunk, {
      bool? dialogueOverride,
    }) {
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

      final span = chunk.isHeading
          ? TextSpan(text: text, style: headingStyle)
          : TextSpanUtils.buildSpacedTextSpan(
              text: text,
              baseStyle: bodyStyle,
              paragraphSpacingMultiplier: 1.0,
            );
      final textAlign = resolveReaderChunkTextAlign(chunk, _settings);

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

    List<({int start, int end})> splitOversizedRange(
      String text,
      int startOffset,
      int endOffset,
      BookChunk original,
    ) {
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

      for (final token in tokenMatches) {
        final tokenStart = startOffset + token.start;
        final tokenEnd = startOffset + token.end;
        final tokenText = text.substring(tokenStart, tokenEnd);
        final tokenHeight = measureTextHeight(tokenText, original);

        if (tokenHeight > physicalTextBudget) {
          flushPiece(pieceStart, pieceEnd);

          int charPieceStart = tokenStart;
          for (int cursor = tokenStart + 1; cursor <= tokenEnd; cursor++) {
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
    List<BookChunk> splitChunkByHeight(BookChunk original) {
      if (original.type != BookChunkType.text || original.isHeading) {
        return [original];
      }
      final text = original.text ?? '';
      if (text.isEmpty) return [original];
      final chunkBudget = heightBudgetFor(original);
      final totalH = measureTextHeight(text, original);
      if (totalH <= chunkBudget) {
        return [original];
      }

      final sourceRanges = original.preserveLineBreaks
          ? preservedLineRanges(text)
          : readerSentenceRanges(text);
      final splitRanges = <({int start, int end})>[];
      for (final range in sourceRanges) {
        if (range.start >= range.end) continue;

        final rangeText = text.substring(range.start, range.end);
        final rangeHeight = measureTextHeight(rangeText, original);

        if (rangeHeight <= physicalTextBudget) {
          splitRanges.add(range);
        } else {
          splitRanges.addAll(
            splitOversizedRange(text, range.start, range.end, original),
          );
        }
      }

      if (splitRanges.isEmpty) return [original];

      final subChunks = <BookChunk>[];
      int currentStart = splitRanges.first.start;
      int currentEnd = splitRanges.first.end;

      for (final range in splitRanges.skip(1)) {
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

    bool tryRebalancePendingWithTinyNext(
      BookChunk nextChunk,
      double nextHeight,
    ) {
      final pendingChunk = pending;
      if (pendingChunk == null) return false;
      if (pendingChunk.usesPublisherLayout || nextChunk.usesPublisherLayout) {
        return false;
      }

      final nextText = nextChunk.text ?? '';
      if (!isTinyChunk(nextChunk, nextHeight) ||
          !sharesHardMergeBoundary(pendingChunk, nextChunk)) {
        return false;
      }

      final pendingText = pendingChunk.text ?? '';
      if (pendingText.isEmpty ||
          isTinyChunk(pendingChunk, chunkHeight(pendingChunk))) {
        return false;
      }

      for (final splitOffset in rebalanceSplitOffsets(pendingText)) {
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
        pending = mergeChunks(tail, nextChunk);
        pendingOriginals = [...pendingOriginals];
        if (!pendingOriginals.contains(nextChunk.index)) {
          pendingOriginals.add(nextChunk.index);
        }
        return true;
      }

      return false;
    }

    void flush() {
      if (pending != null) {
        final pendingChunk = pending!;
        final pendingText = pendingChunk.text ?? '';
        final pendingHeight = chunkHeight(pendingChunk);
        final canAttachToPrevious =
            newDisplayChunks.isNotEmpty &&
            isTinyChunk(pendingChunk, pendingHeight) &&
            sharesHardMergeBoundary(newDisplayChunks.last, pendingChunk);

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
            return;
          }
        }

        addDisplayChunk(pendingChunk, pendingOriginals);
        pending = null;
        pendingOriginals = [];
      }
    }

    final stopwatch = Stopwatch()..start();

    // ── Phase 1: Prioritized Center-Out Layout ──
    // Build chunks starting from the user's current reading position to fill the screen instantly.
    final startIndex = _targetOriginalIndex.clamp(0, widget.chunks.length - 1);

    // We only need to lay out ~2 screens worth of content to start
    double accumulatedHeight = 0;

    for (int i = startIndex; i < widget.chunks.length; i++) {
      if (accumulatedHeight > fullBoundsHeight * 2) break;

      final originalChunk = widget.chunks[i];
      final subChunks = splitChunkByHeight(originalChunk);

      for (final chunk in subChunks) {
        if (chunk.type != BookChunkType.text) {
          flush();
          pending = chunk;
          pendingOriginals = [chunk.index];
          flush();
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
          accumulatedHeight += chunkHeight(chunk);
          continue;
        }

        final pendingText = pending!.text ?? '';
        final separator = mergeSeparator(pending!, chunk);
        final testMergeText = '$pendingText$separator$text';
        final pendingHeight = chunkHeight(pending!);
        final nextHeight = chunkHeight(chunk);

        final mergeHeight = measureTextHeight(
          testMergeText,
          pending!,
          dialogueOverride: pending!.isDialogue && chunk.isDialogue,
        );

        if (shouldMergeChunks(
          pending!,
          chunk,
          pendingHeight: pendingHeight,
          nextHeight: nextHeight,
          mergedHeight: mergeHeight,
        )) {
          // Merge perfectly fits layout bounds!
          pending = mergeChunks(pending!, chunk);
          if (!pendingOriginals.contains(chunk.index)) {
            pendingOriginals.add(chunk.index);
          }
          accumulatedHeight += mergeHeight - pendingHeight;
        } else {
          if (tryRebalancePendingWithTinyNext(chunk, nextHeight)) {
            accumulatedHeight += nextHeight;
            continue;
          }
          flush();
          pending = chunk;
          pendingOriginals = [chunk.index];
          accumulatedHeight += nextHeight;
        }
      }
    }
    flush();

    // Quick display for instantaneous feedback before computing everything else.
    // We only swap this in if the screen is currently empty (e.g., initial open).
    // If we're updating settings, we keep the old display intact so the PageController
    // isn't broken by a suddenly truncated chunks array, avoiding visual jumping.
    if (newDisplayChunks.isNotEmpty && _displayChunks.isEmpty) {
      _displayChunks.clear();
      _displayChunks.addAll(newDisplayChunks);

      _displayToOriginal.clear();
      _displayToOriginal.addAll(newDisplayToOriginal);

      _originalToDisplay.clear();
      _originalToDisplay.addAll(newOriginalToDisplay);

      if (mounted) {
        setState(() {}); // Show immediately
      }
    }

    // ── Phase 2: Complete Layout Background Loop ──
    // Now compute the rest of the book, yielding to avoid UI freezes.

    // Clear and restart from 0
    newDisplayChunks.clear();
    newDisplayToOriginal.clear();
    newOriginalToDisplay.clear();
    pending = null;
    pendingOriginals = [];

    stopwatch.reset();

    for (int i = 0; i < widget.chunks.length; i++) {
      if (stopwatch.elapsedMilliseconds > 16) {
        // Yield to the event loop so the UI doesn't drop frames while calculating layout
        await Future.delayed(Duration.zero);
        if (!mounted || _rebuildGeneration != generation) return;
        stopwatch.reset();
      }

      final originalChunk = widget.chunks[i];
      final subChunks = splitChunkByHeight(originalChunk);

      for (final chunk in subChunks) {
        if (chunk.type != BookChunkType.text) {
          flush();
          pending = chunk;
          pendingOriginals = [chunk.index];
          flush();
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
          // Merge perfectly fits layout bounds!
          pending = mergeChunks(pending!, chunk);
          if (!pendingOriginals.contains(chunk.index)) {
            pendingOriginals.add(chunk.index);
          }
        } else {
          if (tryRebalancePendingWithTinyNext(chunk, nextHeight)) {
            continue;
          }
          flush();
          pending = chunk;
          pendingOriginals = [chunk.index];
        }
      }
    }
    flush();

    // ── Insert milestone celebration cards at 25%, 50%, 75% ──
    _insertMilestoneCards(
      newDisplayChunks,
      newDisplayToOriginal,
      newOriginalToDisplay,
    );

    // Swap the newly built lists into place
    _displayChunks.clear();
    _displayChunks.addAll(newDisplayChunks);

    _displayToOriginal.clear();
    _displayToOriginal.addAll(newDisplayToOriginal);

    _originalToDisplay.clear();
    _originalToDisplay.addAll(newOriginalToDisplay);
  }

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

    // Detect book completion — show overlay when reaching the last page
    if (!_hasShownCompletion &&
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
    setState(() {
      _currentPage = index;
      _activeDisplayIndex = index;
      if (_isScrubbing) {
        _scrubPreviewDisplayIndex = index;
      }
    });
    _syncRestoreTargetFromDisplayIndex(index);

    if (_isScrubbing) {
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

    // If we're on the very last display page, force originalIndex to the very end
    // so progress calculates out to precisely 100%.
    final bool isLastPage = index == _displayToOriginal.length - 1;
    final originalIndex = isLastPage
        ? widget.chunks.length - 1
        : originals.first;

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt('last_read_${widget.bookId}', originalIndex);

    final metadata = _metadataService.getMetadata(widget.bookId);
    if (metadata != null) {
      final updated = metadata.copyWith(
        lastReadIndex: originalIndex,
        totalChunks: widget.chunks.length,
        lastReadTime: DateTime.now().millisecondsSinceEpoch,
      );
      await _metadataService.updateMetadata(updated);
    }
  }

  // ─── Position History ──────────────────────────────────────────────────

  Future<void> _loadPositionHistory() async {
    _prefs ??= await SharedPreferences.getInstance();
    final chunk = _prefs!.getInt('pos_hist_${widget.bookId}_chunk');
    final display = _prefs!.getInt('pos_hist_${widget.bookId}_display');
    final label = _prefs!.getString('pos_hist_${widget.bookId}_label');

    if (chunk != null && display != null && label != null) {
      _positionStack.clear();
      _positionStack.add(
        PositionHistory(
          chunkIndex: chunk,
          displayIndex: display,
          label: _buildPositionHistoryLabel(display),
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
    } else {
      final top = _positionStack.last;
      await _prefs!.setInt('pos_hist_${widget.bookId}_chunk', top.chunkIndex);
      await _prefs!.setInt(
        'pos_hist_${widget.bookId}_display',
        top.displayIndex,
      );
      await _prefs!.setString('pos_hist_${widget.bookId}_label', top.label);
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

    // Jump to the saved position. Recalculate display index using original just in case font changed.
    final rebuiltDisplayTarget = _originalToDisplay[top.chunkIndex];
    final targetDIndex = rebuiltDisplayTarget ?? top.displayIndex;

    _jumpReaderToPage(targetDIndex);
    _lastDwellPage = targetDIndex; // Reset anchor baseline to destination
    // Explicitly update notifier immediately so the chip disappears or updates
    _updatePositionHistoryNotifier();
  }

  // ─── Internal link navigation ────────────────────────────────────────

  void _onLinkTap(String url) {
    String anchor = url;
    final hashIndex = url.indexOf('#');
    if (hashIndex != -1) {
      anchor = url.substring(hashIndex + 1);
    }

    final originalIndex = widget.anchorMap[anchor];
    if (originalIndex != null) {
      final targetIndex = _originalToDisplay[originalIndex];
      if (targetIndex != null) {
        _jumpReaderToPage(targetIndex);
      }
    } else if (kDebugMode) {
      debugPrint('Anchor not found: $anchor');
    }
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
    for (
      var displayIndex = 0;
      displayIndex < _displayChunks.length;
      displayIndex++
    ) {
      for (final range in _displayChunks[displayIndex].effectiveSourceRanges) {
        if (range.originalChunkIndex != bookmark.chunkIndex) continue;
        final containsOffset =
            bookmark.originalStartOffset >= range.originalStartOffset &&
            bookmark.originalStartOffset < range.originalEndOffset;
        if (containsOffset) return displayIndex;
      }
    }

    return _originalToDisplay[bookmark.chunkIndex];
  }

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
        colorIndex: _defaultBookmarkColorIndex,
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
        colorIndex: _defaultBookmarkColorIndex,
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
    final controller = TextEditingController(text: bookmark.name);
    int selectedColor = bookmark.colorIndex;

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
                'Edit Bookmark',
                style: TextStyle(color: _settings.textColor),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(color: _settings.textColor),
                    decoration: InputDecoration(
                      hintText: 'Bookmark name',
                      hintStyle: TextStyle(color: _settings.mutedColor),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _settings.mutedColor.withValues(alpha: 0.5),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _settings.textColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 12,
                    children: List.generate(kBookmarkColors.length, (i) {
                      final color = kBookmarkColors[i];
                      final isSelected = selectedColor == i;
                      return GestureDetector(
                        onTap: () {
                          setLocalState(() => selectedColor = i);
                          _bookmarkService.saveDefaultColorIndex(i);
                          setState(() => _defaultBookmarkColorIndex = i);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: isSelected
                              ? BoxDecoration(
                                  border: Border.all(
                                    color: _settings.textColor,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                )
                              : BoxDecoration(
                                  border: Border.all(
                                    color: Colors.transparent,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                          child: Icon(
                            Icons.bookmark_rounded,
                            color: color,
                            size: 32,
                          ),
                        ),
                      );
                    }),
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
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      final updated = await _bookmarkService.update(
                        bookmark.chunkIndex,
                        originalStartOffset: bookmark.originalStartOffset,
                        newName: name,
                        colorIndex: selectedColor,
                      );
                      setState(() => _bookmarks = updated);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _settings.accentColor,
                    foregroundColor: AppUi.foregroundFor(_settings.accentColor),
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
      );
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

  // ─── Navigation ──────────────────────────────────────────────────────

  void _navigateTo(int targetIndex) {
    if (_currentPage != targetIndex) {
      _commitCurrentPosition(); // Pre-jump commit exception
      _jumpReaderToPage(targetIndex);
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
            chunks: widget.chunks,
            searchIndex: widget.searchIndex,
            initialSettings: _settings,
          ),
        ),
      );
    });
    if (mounted) {
      _startReadingSession();
    }

    if (targetIndex != null) {
      final displayIndex = _originalToDisplay[targetIndex];
      if (displayIndex != null) {
        _navigateTo(displayIndex);
      }
    }
  }

  Future<void> _openAnnotationsPanel() async {
    // Build a lookup map from original chunk index → text for previews
    final chunkTexts = <int, String>{};
    for (final chunk in widget.chunks) {
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
        onNavigate: (originalIndex) {
          final targetDIndex = _originalToDisplay[originalIndex];
          if (targetDIndex != null) {
            _navigateTo(targetDIndex);
          }
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
      );
    });
  }

  Future<void> _showPageJumpDialog() async {
    if (_displayChunks.isEmpty) return;

    final controller = TextEditingController(text: '${_currentPage + 1}');
    String? errorText;

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
                    'Enter a page between 1 and ${_displayChunks.length}.',
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
                              'Choose a page from 1 to ${_displayChunks.length}.';
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
                            'Choose a page from 1 to ${_displayChunks.length}.';
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
      _lastDwellPage = targetIndex;
      _scheduleDwellTracking(targetIndex);
      _updatePositionHistoryNotifier();
      return;
    }

    _commitDisplayIndexToHistory(previousIndex);
    _lastDwellPage = targetIndex;

    if (previewAlreadyVisible) {
      _runCommittedPageEffects(targetIndex);
      return;
    }

    _jumpReaderToPage(targetIndex);
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
                value: 'Page ${displayedPage + 1} of ${_displayChunks.length}',
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

                      if (_currentPage != targetIndex) {
                        _jumpReaderToPage(targetIndex);
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
        originalIndex < widget.chunks.length &&
        widget.chunks[originalIndex].index == originalIndex) {
      return widget.chunks[originalIndex];
    }
    for (final chunk in widget.chunks) {
      if (chunk.index == originalIndex) return chunk;
    }
    return null;
  }

  int _sourceWordCountForOriginalRange(int startIndex, int endExclusive) {
    var total = 0;
    for (final chunk in widget.chunks) {
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
    if (flat.isEmpty || widget.chunks.isEmpty) {
      return const [];
    }

    final byStart = <int, String>{};
    for (final chapter in flat) {
      byStart.putIfAbsent(chapter.chunkIndex, () => chapter.title.trim());
    }
    final starts = byStart.keys.toList()..sort();
    final chapters = <_AnalyticsChapter>[];
    for (int i = 0; i < starts.length; i++) {
      final start = starts[i].clamp(0, widget.chunks.length - 1).toInt();
      final end = i + 1 < starts.length
          ? starts[i + 1].clamp(0, widget.chunks.length).toInt()
          : widget.chunks.length;
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
      widget.chunks.length,
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

    walk(widget.chapters);
    flat.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    _cachedFlatChapters = flat;
    return flat;
  }

  /// Find the index in _flatChapters that the current display page belongs to.
  /// Returns -1 if the current position is before the first chapter.
  int _currentChapterFlatIndex() {
    if (_displayChunks.isEmpty || widget.chapters.isEmpty) return -1;

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
    final flat = _flatChapters;
    if (flat.isEmpty) return null;

    final currentChIdx = _currentChapterFlatIndex();
    final targetIdx = (currentChIdx <= 0) ? -1 : currentChIdx - 1;

    if (targetIdx < 0) return null;

    final target = flat[targetIdx];
    final displayIdx = _originalToDisplay[target.chunkIndex];
    if (displayIdx != null) {
      _navigateTo(displayIdx);
      return target.title;
    }
    return null;
  }

  /// Jump to the next chapter. Returns the chapter title, or null if
  /// already at/past the last chapter.
  String? _jumpToNextChapter() {
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
    return null;
  }

  /// Get info about adjacent chapters for displaying on the arrows.
  ({String? prevTitle, String? nextTitle}) _getAdjacentChapterTitles() {
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.chunks.isNotEmpty) {
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
        widget.chunks.isNotEmpty &&
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

    final body = Stack(
      children: [
        // ── PageView (always present) ──
        _ReaderPageView(
          speedReadController: _speedReadController,
          cardDeckController: _cardDeckController,
          activeDisplayIndex: _activeDisplayIndex,
          pageController: _pageController!,
          displayChunks: _displayChunks,
          displayToOriginal: _displayToOriginal,
          originalToDisplay: _originalToDisplay,
          flatChapters: _flatChapters,
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
          highlights: _highlights,
          characterNames: _buildCharacterNamesMap(),
          onHighlightCreated: _onHighlightCreated,
          onQuoteShareRequested: _onQuoteShareRequested,
          onMappedNoteCreated: _onMappedNoteCreated,
          onHighlightColorChange: _onHighlightColorChange,
          onHighlightDeleted: _onHighlightDeleted,
          onNoteUpdated: _onNoteUpdated,
          onNoteRemoved: _onNoteRemoved,
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
          onTapOutside: (_) => _toggleOverlay(),
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

        // ── Book completion celebration overlay ──
        if (_isCelebrationVisible && _currentPage >= _displayChunks.length - 1)
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
    final needsRebuild =
        old.fontSize != updated.fontSize ||
        old.fontFamily != updated.fontFamily ||
        old.fontWeight != updated.fontWeight ||
        old.contentDensity != updated.contentDensity ||
        old.lineHeight != updated.lineHeight ||
        old.enableCardDepth != updated.enableCardDepth;

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
    for (final chunk in widget.chunks) {
      if (chunk.text != null && chunk.text!.isNotEmpty) {
        chunkTexts[chunk.index] = chunk.text!;
      }
    }

    await _runWithReaderControlsSuspended(() {
      return ChapterPanel.show(
        context,
        chapters: widget.chapters,
        currentPage: _currentPage,
        originalToDisplay: _originalToDisplay,
        positionHistoryNotifier: _positionHistoryNotifier,
        settings: _settings,
        onGoBack: _popAndGoBackToPosition,
        onNavigate: (originalIndex) {
          final targetDIndex = _originalToDisplay[originalIndex];
          if (targetDIndex != null) {
            _navigateTo(targetDIndex);
          }
        },
        onNavigateBookmark: (bookmark) {
          final targetDIndex = _displayIndexForBookmark(bookmark);
          if (targetDIndex != null) {
            _navigateTo(targetDIndex);
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
                            Expanded(child: _buildPageScrubber(markRatios)),
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
                                  'Page ${displayedPage + 1} of ${_displayChunks.length}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _settings.mutedColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '$progressPercent%',
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
    if (widget.chapters.isEmpty) return const SizedBox.shrink();

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

/// Extracted PageView to isolate its rebuilds from overlay changes.
class _ReaderPageView extends StatelessWidget {
  final int activeDisplayIndex;
  final PageController pageController;
  final ReadingCardDeckController cardDeckController;
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final Map<int, int> originalToDisplay;
  final List<({int chunkIndex, String title})> flatChapters;
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
  final void Function(String id, String note)? onNoteUpdated;
  final void Function(String id)? onNoteRemoved;
  final List<Color> highlightPalette;
  final Color defaultHighlightColor;
  final ValueChanged<Color>? onDefaultHighlightColorChanged;
  final Future<List<Color>> Function(Color color)? onAddCustomHighlightColor;
  final Future<List<Color>> Function(Color color)? onRemoveCustomHighlightColor;
  final Future<List<Color>> Function()? onResetHighlightPalette;
  final int defaultBookmarkColorIndex;
  final ValueChanged<int>? onDefaultBookmarkColorChanged;
  final void Function(Offset? globalPosition)? onTapOutside;
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
    this.highlightPalette = kHighlightColors,
    this.defaultHighlightColor = const Color(0xFFEF5350),
    this.onDefaultHighlightColorChanged,
    this.onAddCustomHighlightColor,
    this.onRemoveCustomHighlightColor,
    this.onResetHighlightPalette,
    this.defaultBookmarkColorIndex = 0,
    this.onDefaultBookmarkColorChanged,
    this.onTapOutside,
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

  _ChapterPageMeta _chapterPageMetaFor(int displayIndex) {
    if (displayChunks.isEmpty) {
      return const _ChapterPageMeta(
        title: 'Current chapter',
        pageLabel: '1 / 1',
        progress: 1,
      );
    }

    if (flatChapters.isEmpty ||
        displayIndex < 0 ||
        displayIndex >= displayToOriginal.length) {
      final current = (displayIndex + 1).clamp(1, displayChunks.length);
      return _ChapterPageMeta(
        title: 'Current chapter',
        pageLabel: '$current / ${displayChunks.length}',
        progress: current / displayChunks.length,
      );
    }

    final mappedOriginals = displayToOriginal[displayIndex];
    final currentOriginal = mappedOriginals.isNotEmpty
        ? mappedOriginals.first
        : displayChunks[displayIndex].index;

    var chapterIndex = -1;
    for (var i = 0; i < flatChapters.length; i++) {
      if (flatChapters[i].chunkIndex <= currentOriginal) {
        chapterIndex = i;
      } else {
        break;
      }
    }

    if (chapterIndex < 0) {
      final current = (displayIndex + 1).clamp(1, displayChunks.length);
      return _ChapterPageMeta(
        title: flatChapters.first.title,
        pageLabel: '$current / ${displayChunks.length}',
        progress: current / displayChunks.length,
      );
    }

    final chapter = flatChapters[chapterIndex];
    final startOriginal = chapter.chunkIndex;
    final endOriginal = chapterIndex + 1 < flatChapters.length
        ? flatChapters[chapterIndex + 1].chunkIndex
        : 1 << 30;
    final chapterDisplayIndexes = <int>[];

    for (var i = 0; i < displayToOriginal.length; i++) {
      final isInChapter = displayToOriginal[i].any(
        (original) => original >= startOriginal && original < endOriginal,
      );
      if (isInChapter) chapterDisplayIndexes.add(i);
    }

    final total = chapterDisplayIndexes.isEmpty
        ? 1
        : chapterDisplayIndexes.length;
    final zeroBasedPage = chapterDisplayIndexes.indexOf(displayIndex);
    final current = zeroBasedPage >= 0
        ? zeroBasedPage + 1
        : chapterDisplayIndexes
              .where((i) => i <= displayIndex)
              .length
              .clamp(1, total);

    return _ChapterPageMeta(
      title: chapter.title.trim().isEmpty ? 'Current chapter' : chapter.title,
      pageLabel: '$current / $total',
      progress: current / total,
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
      highlightPalette: highlightPalette,
      defaultHighlightColor: defaultHighlightColor,
      onDefaultHighlightColorChanged: isCurrent
          ? onDefaultHighlightColorChanged
          : null,
      onAddCustomColor: isCurrent ? onAddCustomHighlightColor : null,
      onRemoveCustomColor: isCurrent ? onRemoveCustomHighlightColor : null,
      onResetHighlightPalette: isCurrent ? onResetHighlightPalette : null,
      onTapOutside: isCurrent ? onTapOutside : null,
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
        return AnimatedBuilder(
          animation: pageController,
          builder: (context, _) {
            final page = pageController.hasClients
                ? pageController.page ?? activeDisplayIndex.toDouble()
                : activeDisplayIndex.toDouble();
            final pageDelta = page - index;
            final liftProgress =
                settings.pagingAxis == ReaderPagingAxis.vertical
                ? pageDelta.clamp(0.0, 1.0).toDouble()
                : pageDelta.abs().clamp(0.0, 1.0).toDouble();
            return _buildReadingCard(
              context,
              index,
              liftProgress,
              index == activeDisplayIndex,
            );
          },
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

class _ChapterPageMeta {
  final String title;
  final String pageLabel;
  final double progress;

  const _ChapterPageMeta({
    required this.title,
    required this.pageLabel,
    required this.progress,
  });
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
  bool _showTypefacePicker = false;

  @override
  void initState() {
    super.initState();
    _localSettings = widget.settings;
    unawaited(_loadPresets());
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
                setState(() => _selectedCategory = category);
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
