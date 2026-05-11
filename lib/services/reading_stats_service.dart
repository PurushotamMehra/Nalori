import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingPaceConfidence { uncalibrated, low, medium, high }

@immutable
class ReadingChapterStats {
  final String id;
  final String title;
  final int wordCount;
  final int measuredWords;
  final int activeSeconds;
  final int calibrationSeconds;

  const ReadingChapterStats({
    required this.id,
    required this.title,
    this.wordCount = 0,
    this.measuredWords = 0,
    this.activeSeconds = 0,
    this.calibrationSeconds = 0,
  });

  double get progress =>
      wordCount <= 0 ? 0 : (measuredWords / wordCount).clamp(0.0, 1.0);

  int? get wpm {
    if (calibrationSeconds <= 0 || measuredWords <= 0) {
      return null;
    }
    final rawWpm = ((measuredWords * 60) / calibrationSeconds).round();
    return rawWpm
        .clamp(
          ReadingStatsService.minPassiveWpm,
          ReadingStatsService.maxPassiveWpm,
        )
        .toInt();
  }

  ReadingChapterStats copyWith({
    String? id,
    String? title,
    int? wordCount,
    int? measuredWords,
    int? activeSeconds,
    int? calibrationSeconds,
  }) {
    return ReadingChapterStats(
      id: id ?? this.id,
      title: title ?? this.title,
      wordCount: wordCount ?? this.wordCount,
      measuredWords: measuredWords ?? this.measuredWords,
      activeSeconds: activeSeconds ?? this.activeSeconds,
      calibrationSeconds: calibrationSeconds ?? this.calibrationSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'word_count': wordCount,
    'measured_words': measuredWords,
    'active_seconds': activeSeconds,
    'calibration_seconds': calibrationSeconds,
  };

  factory ReadingChapterStats.fromJson(Map<String, dynamic> json) =>
      ReadingChapterStats(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Chapter',
        wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
        measuredWords: (json['measured_words'] as num?)?.toInt() ?? 0,
        activeSeconds: (json['active_seconds'] as num?)?.toInt() ?? 0,
        calibrationSeconds: (json['calibration_seconds'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class ReadingBookInsights {
  final String bookId;
  final int estimatedWpm;
  final int measuredWords;
  final int calibrationSeconds;
  final int sampleCount;
  final int activeSeconds;
  final int? completedReadingSeconds;
  final int highestMeasuredOriginalIndex;
  final Map<String, ReadingChapterStats> chapters;

  const ReadingBookInsights({
    required this.bookId,
    this.estimatedWpm = ReadingStatsService.defaultEstimatedWpm,
    this.measuredWords = 0,
    this.calibrationSeconds = 0,
    this.sampleCount = 0,
    this.activeSeconds = 0,
    this.completedReadingSeconds,
    this.highestMeasuredOriginalIndex = -1,
    this.chapters = const {},
  });

  ReadingPaceConfidence get confidence =>
      ReadingStatsService.confidenceForSeconds(calibrationSeconds);

  ReadingChapterStats? get fastestChapter {
    ReadingChapterStats? fastest;
    for (final chapter in chapters.values) {
      final wpm = chapter.wpm;
      if (wpm == null) continue;
      if (fastest == null || wpm > (fastest.wpm ?? 0)) {
        fastest = chapter;
      }
    }
    return fastest;
  }

  ReadingChapterStats? get slowestChapter {
    ReadingChapterStats? slowest;
    for (final chapter in chapters.values) {
      final wpm = chapter.wpm;
      if (wpm == null) continue;
      if (slowest == null || wpm < (slowest.wpm ?? 9999)) {
        slowest = chapter;
      }
    }
    return slowest;
  }

  ReadingChapterStats? get longestChapter {
    ReadingChapterStats? longest;
    for (final chapter in chapters.values) {
      if (chapter.activeSeconds <= 0) continue;
      if (longest == null || chapter.activeSeconds > longest.activeSeconds) {
        longest = chapter;
      }
    }
    return longest;
  }

  ReadingBookInsights copyWith({
    String? bookId,
    int? estimatedWpm,
    int? measuredWords,
    int? calibrationSeconds,
    int? sampleCount,
    int? activeSeconds,
    int? completedReadingSeconds,
    bool clearCompletedReadingSeconds = false,
    int? highestMeasuredOriginalIndex,
    Map<String, ReadingChapterStats>? chapters,
  }) {
    return ReadingBookInsights(
      bookId: bookId ?? this.bookId,
      estimatedWpm: estimatedWpm ?? this.estimatedWpm,
      measuredWords: measuredWords ?? this.measuredWords,
      calibrationSeconds: calibrationSeconds ?? this.calibrationSeconds,
      sampleCount: sampleCount ?? this.sampleCount,
      activeSeconds: activeSeconds ?? this.activeSeconds,
      completedReadingSeconds: clearCompletedReadingSeconds
          ? null
          : (completedReadingSeconds ?? this.completedReadingSeconds),
      highestMeasuredOriginalIndex:
          highestMeasuredOriginalIndex ?? this.highestMeasuredOriginalIndex,
      chapters: chapters ?? this.chapters,
    );
  }

  Map<String, dynamic> toJson() => {
    'estimated_wpm': estimatedWpm,
    'measured_words': measuredWords,
    'calibration_seconds': calibrationSeconds,
    'sample_count': sampleCount,
    'active_seconds': activeSeconds,
    'completed_reading_seconds': completedReadingSeconds,
    'highest_measured_original_index': highestMeasuredOriginalIndex,
    'chapters': chapters.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory ReadingBookInsights.fromJson(
    String bookId,
    Map<String, dynamic> json,
  ) {
    return ReadingBookInsights(
      bookId: bookId,
      estimatedWpm:
          (json['estimated_wpm'] as num?)?.toInt() ??
          ReadingStatsService.defaultEstimatedWpm,
      measuredWords: (json['measured_words'] as num?)?.toInt() ?? 0,
      calibrationSeconds: (json['calibration_seconds'] as num?)?.toInt() ?? 0,
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
      activeSeconds: (json['active_seconds'] as num?)?.toInt() ?? 0,
      completedReadingSeconds: (json['completed_reading_seconds'] as num?)
          ?.toInt(),
      highestMeasuredOriginalIndex:
          (json['highest_measured_original_index'] as num?)?.toInt() ?? -1,
      chapters: (json['chapters'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(
          key,
          ReadingChapterStats.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }
}

/// Service to track and persist reading statistics:
/// - Daily page counts (heatmap data)
/// - Streaks (current & longest)
/// - Total books completed
/// - Session tracking
class ReadingStatsService {
  // Singleton
  static final ReadingStatsService _instance = ReadingStatsService._internal();
  factory ReadingStatsService() => _instance;
  ReadingStatsService._internal();

  static const String _statsKey = 'reading_stats_v1';
  static const int defaultEstimatedWpm = 220;
  static const int minPassiveWpm = 80;
  static const int maxPassiveWpm = 450;
  static const int minInsightSampleSeconds = 2;
  static const int maxInsightCalibrationSeconds = 120;
  static const int minDailyReadSeconds = 5 * 60;
  static const Duration _saveDebounceDuration = Duration(milliseconds: 1500);

  Map<String, int> _dailyPages = {}; // "2026-03-08" → pages read
  Map<String, int> _dailyReadSeconds = {}; // "2026-03-08" → seconds read
  Map<String, ReadingBookInsights> _bookInsights = {};
  int _totalBooksCompleted = 0;
  int _globalEstimatedWpm = defaultEstimatedWpm;
  int _globalMeasuredWords = 0;
  int _globalCalibrationSeconds = 0;
  int _globalSampleCount = 0;
  int _currentStreak = 0;
  int _longestStreak = 0;
  bool _initialized = false;
  Timer? _saveDebounceTimer;
  bool _hasPendingSave = false;

  /// Initialize by loading persisted data.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_statsKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _dailyPages = (data['daily'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
        _dailyReadSeconds =
            (data['daily_read_seconds'] as Map<String, dynamic>? ?? {}).map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            );
        _totalBooksCompleted = (data['books_completed'] as num?)?.toInt() ?? 0;
        _currentStreak = (data['current_streak'] as num?)?.toInt() ?? 0;
        _longestStreak = (data['longest_streak'] as num?)?.toInt() ?? 0;
        _globalEstimatedWpm =
            (data['global_estimated_wpm'] as num?)?.toInt() ??
            defaultEstimatedWpm;
        _globalMeasuredWords =
            (data['global_measured_words'] as num?)?.toInt() ?? 0;
        _globalCalibrationSeconds =
            (data['global_calibration_seconds'] as num?)?.toInt() ?? 0;
        _globalSampleCount =
            (data['global_sample_count'] as num?)?.toInt() ?? 0;
        _bookInsights = (data['book_insights'] as Map<String, dynamic>? ?? {})
            .map(
              (bookId, value) => MapEntry(
                bookId,
                ReadingBookInsights.fromJson(
                  bookId,
                  value as Map<String, dynamic>,
                ),
              ),
            );
      }
    } catch (e) {
      debugPrint('ReadingStatsService: Failed to load stats: $e');
    }
    // Recalculate streak on load to handle missed days
    _recalculateStreak();
    _initialized = true;
  }

  /// For testing purposes: clear in-memory state
  @visibleForTesting
  void clearForTest() {
    _dailyPages = {};
    _dailyReadSeconds = {};
    _bookInsights = {};
    _totalBooksCompleted = 0;
    _globalEstimatedWpm = defaultEstimatedWpm;
    _globalMeasuredWords = 0;
    _globalCalibrationSeconds = 0;
    _globalSampleCount = 0;
    _currentStreak = 0;
    _longestStreak = 0;
    _initialized = false;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _hasPendingSave = false;
  }

  /// Record a single page read (call from _onPageChanged in reader).
  Future<void> recordPageRead({bool deferSave = false}) async {
    await init();
    final today = _todayKey();
    _dailyPages[today] = (_dailyPages[today] ?? 0) + 1;
    await _persistStats(deferSave: deferSave);
  }

  /// Record an active reading interval. The duration is split across local
  /// calendar days so streak qualification respects midnight boundaries.
  Future<void> recordReadingSession({
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    await init();
    if (!endedAt.isAfter(startedAt)) return;

    var cursor = startedAt;
    while (cursor.isBefore(endedAt)) {
      final nextMidnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final segmentEnd = endedAt.isBefore(nextMidnight)
          ? endedAt
          : nextMidnight;
      final seconds = segmentEnd.difference(cursor).inSeconds;
      if (seconds > 0) {
        final key = _dateKey(cursor);
        _dailyReadSeconds[key] = (_dailyReadSeconds[key] ?? 0) + seconds;
      }
      cursor = segmentEnd;
    }

    _recalculateStreak();
    await _save();
  }

  /// Record a completed book.
  Future<void> recordBookCompleted() async {
    await init();
    _totalBooksCompleted++;
    await _save();
  }

  Future<void> recordBookCompletedWithInsights(String bookId) async {
    await init();
    final current = getBookInsights(bookId);
    _bookInsights[bookId] = current.copyWith(
      completedReadingSeconds: current.activeSeconds,
    );
    await recordBookCompleted();
  }

  Future<void> registerBookInsightChapters({
    required String bookId,
    required Map<String, ReadingChapterStats> chapters,
  }) async {
    await init();
    final current = getBookInsights(bookId);
    final merged = <String, ReadingChapterStats>{};
    for (final entry in chapters.entries) {
      final previous = current.chapters[entry.key];
      final next = entry.value;
      merged[entry.key] = next.copyWith(
        measuredWords: previous?.measuredWords,
        activeSeconds: previous?.activeSeconds,
        calibrationSeconds: previous?.calibrationSeconds,
      );
    }
    _bookInsights[bookId] = current.copyWith(chapters: merged);
    await _save();
  }

  Future<void> recordReadingInsightSample({
    required String bookId,
    required int activeSeconds,
    int measuredWords = 0,
    int? highestMeasuredOriginalIndex,
    String? chapterId,
    bool calibratesPace = true,
    bool deferSave = false,
  }) async {
    await init();
    if (activeSeconds <= 0) return;

    final current = getBookInsights(bookId);
    final cappedActiveSeconds = activeSeconds.clamp(0, 180).toInt();
    final validCalibration =
        calibratesPace &&
        measuredWords > 0 &&
        activeSeconds >= minInsightSampleSeconds &&
        activeSeconds <= maxInsightCalibrationSeconds;

    final calibrationSeconds = validCalibration ? activeSeconds : 0;
    final nextBookMeasuredWords = current.measuredWords + measuredWords;
    final nextBookCalibrationSeconds =
        current.calibrationSeconds + calibrationSeconds;
    final nextBookSampleCount =
        current.sampleCount + (validCalibration ? 1 : 0);

    var nextBookWpm = current.estimatedWpm;
    if (validCalibration) {
      nextBookWpm = _weightedWpm(
        oldWpm: current.estimatedWpm,
        oldSeconds: current.calibrationSeconds,
        newWords: measuredWords,
        newSeconds: calibrationSeconds,
      );
      _globalEstimatedWpm = _weightedWpm(
        oldWpm: _globalEstimatedWpm,
        oldSeconds: _globalCalibrationSeconds,
        newWords: measuredWords,
        newSeconds: calibrationSeconds,
      );
      _globalMeasuredWords += measuredWords;
      _globalCalibrationSeconds += calibrationSeconds;
      _globalSampleCount++;
    }

    final chapters = Map<String, ReadingChapterStats>.from(current.chapters);
    if (chapterId != null && chapters.containsKey(chapterId)) {
      final chapter = chapters[chapterId]!;
      chapters[chapterId] = chapter.copyWith(
        measuredWords: chapter.measuredWords + measuredWords,
        activeSeconds: chapter.activeSeconds + cappedActiveSeconds,
        calibrationSeconds: chapter.calibrationSeconds + calibrationSeconds,
      );
    }

    _bookInsights[bookId] = current.copyWith(
      estimatedWpm: nextBookWpm,
      measuredWords: nextBookMeasuredWords,
      calibrationSeconds: nextBookCalibrationSeconds,
      sampleCount: nextBookSampleCount,
      activeSeconds: current.activeSeconds + cappedActiveSeconds,
      highestMeasuredOriginalIndex:
          highestMeasuredOriginalIndex ?? current.highestMeasuredOriginalIndex,
      chapters: chapters,
    );
    await _persistStats(deferSave: deferSave);
  }

  Future<void> flushPendingWrites() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (!_hasPendingSave) return;

    _hasPendingSave = false;
    await _save();
  }

  Future<void> resetReadingPaceCalibration({String? bookId}) async {
    await init();
    if (bookId != null) {
      final current = getBookInsights(bookId);
      _bookInsights[bookId] = current.copyWith(
        estimatedWpm: defaultEstimatedWpm,
        measuredWords: 0,
        calibrationSeconds: 0,
        sampleCount: 0,
        chapters: current.chapters.map(
          (key, chapter) => MapEntry(
            key,
            chapter.copyWith(measuredWords: 0, calibrationSeconds: 0),
          ),
        ),
      );
    } else {
      _globalEstimatedWpm = defaultEstimatedWpm;
      _globalMeasuredWords = 0;
      _globalCalibrationSeconds = 0;
      _globalSampleCount = 0;
      _bookInsights = _bookInsights.map(
        (bookId, book) => MapEntry(
          bookId,
          book.copyWith(
            estimatedWpm: defaultEstimatedWpm,
            measuredWords: 0,
            calibrationSeconds: 0,
            sampleCount: 0,
            chapters: book.chapters.map(
              (key, chapter) => MapEntry(
                key,
                chapter.copyWith(measuredWords: 0, calibrationSeconds: 0),
              ),
            ),
          ),
        ),
      );
    }
    await _save();
  }

  /// Get the current reading streak (consecutive days meeting the daily
  /// reading-time threshold).
  int get currentStreak {
    _recalculateStreak();
    return _currentStreak;
  }

  /// Get the longest-ever streak.
  int get longestStreak => _longestStreak;

  /// Get total books completed.
  int get totalBooksCompleted => _totalBooksCompleted;

  int get globalEstimatedWpm => _globalEstimatedWpm;

  int get globalCalibrationSeconds => _globalCalibrationSeconds;

  ReadingPaceConfidence get globalConfidence =>
      confidenceForSeconds(_globalCalibrationSeconds);

  ReadingBookInsights getBookInsights(String bookId) =>
      _bookInsights[bookId] ?? ReadingBookInsights(bookId: bookId);

  int estimatedWpmForBook(String bookId) {
    final book = getBookInsights(bookId);
    final bookWeight = (book.calibrationSeconds / (20 * 60)).clamp(0.0, 0.85);
    final blended =
        (_globalEstimatedWpm * (1 - bookWeight)) +
        (book.estimatedWpm * bookWeight);
    return blended.round().clamp(minPassiveWpm, maxPassiveWpm).toInt();
  }

  Duration estimateTimeLeft({
    required String bookId,
    required int remainingWords,
  }) {
    if (remainingWords <= 0) return Duration.zero;
    final wpm = estimatedWpmForBook(bookId);
    return Duration(seconds: ((remainingWords / wpm) * 60).round());
  }

  static ReadingPaceConfidence confidenceForSeconds(int seconds) {
    if (seconds <= 0) return ReadingPaceConfidence.uncalibrated;
    if (seconds < 5 * 60) return ReadingPaceConfidence.low;
    if (seconds < 30 * 60) return ReadingPaceConfidence.medium;
    return ReadingPaceConfidence.high;
  }

  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes <= 0) return '0m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours <= 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  /// Get total pages read all-time.
  int get totalPagesRead {
    int total = 0;
    for (final v in _dailyPages.values) {
      total += v;
    }
    return total;
  }

  /// Get pages read today.
  int get pagesReadToday => _dailyPages[_todayKey()] ?? 0;

  /// Get qualified reading seconds today.
  int get secondsReadToday => _dailyReadSeconds[_todayKey()] ?? 0;

  bool get didQualifyToday => secondsReadToday >= minDailyReadSeconds;

  int get remainingSecondsToQualifyToday {
    final remaining = minDailyReadSeconds - secondsReadToday;
    return remaining > 0 ? remaining : 0;
  }

  /// Get pages read this week (last 7 days including today).
  int get pagesReadThisWeek {
    final now = DateTime.now();
    int total = 0;
    for (int i = 0; i < 7; i++) {
      final day = now.subtract(Duration(days: i));
      final key = _dateKey(day);
      total += _dailyPages[key] ?? 0;
    }
    return total;
  }

  /// Get pages read this month (last 30 days including today).
  int get pagesReadThisMonth {
    final now = DateTime.now();
    int total = 0;
    for (int i = 0; i < 30; i++) {
      final day = now.subtract(Duration(days: i));
      final key = _dateKey(day);
      total += _dailyPages[key] ?? 0;
    }
    return total;
  }

  /// Get heatmap data: maps date strings to page counts.
  /// Returns up to [days] days of data (default 365).
  Map<String, int> getHeatmapData({int days = 365}) {
    final now = DateTime.now();
    final result = <String, int>{};
    for (int i = 0; i < days; i++) {
      final day = now.subtract(Duration(days: i));
      final key = _dateKey(day);
      result[key] = _dailyPages[key] ?? 0;
    }
    return result;
  }

  /// Get the maximum pages read in a single day (for heatmap intensity scaling).
  int get maxDailyPages {
    if (_dailyPages.isEmpty) return 0;
    int max = 0;
    for (final v in _dailyPages.values) {
      if (v > max) max = v;
    }
    return max;
  }

  // ─── Private helpers ─────────────────────────────────────────────────

  void _recalculateStreak() {
    final now = DateTime.now();
    int streak = 0;

    // Start from today and work backwards
    for (int i = 0; i < 3650; i++) {
      // up to 10 years
      final day = now.subtract(Duration(days: i));
      final key = _dateKey(day);
      final qualifiedSeconds = _dailyReadSeconds[key] ?? 0;

      if (qualifiedSeconds >= minDailyReadSeconds) {
        streak++;
      } else {
        // Allow today to be zero (we might not have read yet today)
        if (i == 0) continue;
        break;
      }
    }

    _currentStreak = streak;
    if (streak > _longestStreak) {
      _longestStreak = streak;
    }
  }

  int _weightedWpm({
    required int oldWpm,
    required int oldSeconds,
    required int newWords,
    required int newSeconds,
  }) {
    if (newWords <= 0 || newSeconds <= 0) return oldWpm;
    final sampleWpm = ((newWords * 60) / newSeconds).round();
    final sampleWeight = oldSeconds <= 0 ? 1.0 : 0.15;
    final next = (oldWpm * (1 - sampleWeight)) + (sampleWpm * sampleWeight);
    return next.round().clamp(minPassiveWpm, maxPassiveWpm).toInt();
  }

  String _todayKey() => _dateKey(DateTime.now());

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _persistStats({required bool deferSave}) async {
    if (deferSave) {
      _scheduleSave();
      return;
    }
    await _saveImmediately();
  }

  Future<void> _saveImmediately() async {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _hasPendingSave = false;
    await _save();
  }

  void _scheduleSave() {
    _hasPendingSave = true;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(_saveDebounceDuration, () {
      unawaited(flushPendingWrites());
    });
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'daily': _dailyPages,
        'daily_read_seconds': _dailyReadSeconds,
        'books_completed': _totalBooksCompleted,
        'current_streak': _currentStreak,
        'longest_streak': _longestStreak,
        'global_estimated_wpm': _globalEstimatedWpm,
        'global_measured_words': _globalMeasuredWords,
        'global_calibration_seconds': _globalCalibrationSeconds,
        'global_sample_count': _globalSampleCount,
        'book_insights': _bookInsights.map(
          (bookId, insights) => MapEntry(bookId, insights.toJson()),
        ),
      };
      await prefs.setString(_statsKey, jsonEncode(data));
    } catch (e) {
      debugPrint('ReadingStatsService: Failed to save stats: $e');
    }
  }
}
