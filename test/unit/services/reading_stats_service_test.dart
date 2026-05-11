import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nalori/services/reading_stats_service.dart';

void main() {
  late ReadingStatsService statsService;
  final now = DateTime.now();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    statsService = ReadingStatsService();
    statsService.clearForTest(); // Ensure tests start clean
    await statsService.init();
  });

  group('ReadingStatsService', () {
    group('recordPageRead', () {
      test('should increment pages read today', () async {
        await statsService.recordPageRead();
        await statsService.recordPageRead();

        expect(statsService.pagesReadToday, 2);
      });
    });

    group('recordBookCompleted', () {
      test('should increment total books completed', () async {
        await statsService.recordBookCompleted();
        await statsService.recordBookCompleted();

        expect(statsService.totalBooksCompleted, 2);
      });
    });

    group('currentStreak', () {
      test('should return 0 when no reading done', () async {
        expect(statsService.currentStreak, 0);
      });

      test('should not start a streak from page turns alone', () async {
        await statsService.recordPageRead();

        expect(statsService.currentStreak, 0);
      });

      test('should return 1 when reading goal is met today', () async {
        await statsService.recordReadingSession(
          startedAt: now.subtract(const Duration(minutes: 6)),
          endedAt: now,
        );

        expect(statsService.currentStreak, 1);
      });

      test('should keep yesterday streak alive until today ends', () async {
        final yesterday = now.subtract(const Duration(days: 1));
        await statsService.recordReadingSession(
          startedAt: DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            20,
            0,
          ),
          endedAt: DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            20,
            6,
          ),
        );

        expect(statsService.currentStreak, 1);
      });

      test('should reset after a missed day', () async {
        final twoDaysAgo = now.subtract(const Duration(days: 2));
        await statsService.recordReadingSession(
          startedAt: DateTime(
            twoDaysAgo.year,
            twoDaysAgo.month,
            twoDaysAgo.day,
            20,
            0,
          ),
          endedAt: DateTime(
            twoDaysAgo.year,
            twoDaysAgo.month,
            twoDaysAgo.day,
            20,
            6,
          ),
        );

        expect(statsService.currentStreak, 0);
      });
    });

    group('longestStreak', () {
      test('should update when current streak exceeds longest', () async {
        await statsService.recordReadingSession(
          startedAt: now.subtract(const Duration(minutes: 6)),
          endedAt: now,
        );

        expect(statsService.longestStreak, 1);
      });
    });

    group('recordReadingSession', () {
      test('should accumulate reading seconds for today', () async {
        await statsService.recordReadingSession(
          startedAt: now.subtract(const Duration(minutes: 2)),
          endedAt: now,
        );

        expect(statsService.secondsReadToday, greaterThanOrEqualTo(120));
      });

      test('should split a session across midnight boundaries', () async {
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(minutes: 6));
        final end = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(minutes: 6));

        await statsService.recordReadingSession(startedAt: start, endedAt: end);

        expect(statsService.currentStreak, 2);
        expect(statsService.secondsReadToday, greaterThanOrEqualTo(360));
      });
    });

    group('totalPagesRead', () {
      test('should return sum of all daily pages', () async {
        await statsService.recordPageRead();
        await statsService.recordPageRead();
        await statsService.recordPageRead();

        expect(statsService.totalPagesRead, greaterThanOrEqualTo(3));
      });
    });

    group('pagesReadThisWeek', () {
      test('should return pages read in last 7 days', () async {
        await statsService.recordPageRead();
        await statsService.recordPageRead();

        expect(statsService.pagesReadThisWeek, greaterThanOrEqualTo(2));
      });
    });

    group('pagesReadThisMonth', () {
      test('should return pages read in last 30 days', () async {
        await statsService.recordPageRead();

        expect(statsService.pagesReadThisMonth, greaterThanOrEqualTo(1));
      });
    });

    group('getHeatmapData', () {
      test('should return heatmap data for specified days', () async {
        await statsService.recordPageRead();

        final data = statsService.getHeatmapData(days: 7);

        expect(data, isA<Map<String, int>>());
        expect(data.length, 7);
      });

      test('should include today in heatmap data', () async {
        await statsService.recordPageRead();

        final data = statsService.getHeatmapData(days: 1);
        final today = DateTime.now();
        final todayKey =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        expect(data.containsKey(todayKey), true);
      });
    });

    group('maxDailyPages', () {
      test('should return 0 when no pages read', () {
        expect(statsService.maxDailyPages, 0);
      });

      test('should return max pages in a single day', () async {
        await statsService.recordPageRead();
        await statsService.recordPageRead();
        await statsService.recordPageRead();

        expect(statsService.maxDailyPages, greaterThanOrEqualTo(3));
      });
    });

    group('reading insights', () {
      test('should expose default global WPM', () {
        expect(statsService.globalEstimatedWpm, 220);
        expect(
          statsService.globalConfidence,
          ReadingPaceConfidence.uncalibrated,
        );
      });

      test('should record pace samples and book active time', () async {
        await statsService.recordReadingInsightSample(
          bookId: 'book.epub',
          activeSeconds: 60,
          measuredWords: 240,
          highestMeasuredOriginalIndex: 3,
        );

        final insights = statsService.getBookInsights('book.epub');
        expect(insights.activeSeconds, 60);
        expect(insights.measuredWords, 240);
        expect(insights.highestMeasuredOriginalIndex, 3);
        expect(statsService.globalEstimatedWpm, greaterThanOrEqualTo(80));
      });

      test('should register and update chapter stats', () async {
        await statsService.registerBookInsightChapters(
          bookId: 'book.epub',
          chapters: const {
            '0_0': ReadingChapterStats(
              id: '0_0',
              title: 'Chapter One',
              wordCount: 1000,
            ),
          },
        );

        await statsService.recordReadingInsightSample(
          bookId: 'book.epub',
          activeSeconds: 30,
          measuredWords: 120,
          chapterId: '0_0',
        );

        final chapter = statsService
            .getBookInsights('book.epub')
            .chapters['0_0'];
        expect(chapter, isNotNull);
        expect(chapter!.measuredWords, 120);
        expect(chapter.wpm, 240);
      });

      test(
        'should reset reading pace calibration without clearing active time',
        () async {
          await statsService.recordReadingInsightSample(
            bookId: 'book.epub',
            activeSeconds: 60,
            measuredWords: 240,
          );

          await statsService.resetReadingPaceCalibration();

          final insights = statsService.getBookInsights('book.epub');
          expect(statsService.globalEstimatedWpm, 220);
          expect(insights.activeSeconds, 60);
          expect(insights.measuredWords, 0);
        },
      );
    });
  });
}
