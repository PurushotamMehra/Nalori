import 'package:flutter/material.dart';

import '../models/reading_settings.dart';
import '../services/reading_stats_service.dart';

/// Beautiful stats dashboard with reading heatmap, streaks, and summary stats.
class StatsScreen extends StatefulWidget {
  final ReadingSettings settings;

  const StatsScreen({super.key, required this.settings});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  final _statsService = ReadingStatsService();
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _loaded = false;
  bool _isYearlyView = false; // Default to monthly view

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _loadStats();
  }

  Future<void> _loadStats() async {
    await _statsService.init();
    if (mounted) {
      setState(() => _loaded = true);
      _animController.forward();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  ReadingSettings get _s => widget.settings;

  @override
  Widget build(BuildContext context) {
    final baseTheme = _s.isDark ? ThemeData.dark() : ThemeData.light();
    return Theme(
      data: baseTheme.copyWith(
        scaffoldBackgroundColor: _s.backgroundColor,
        colorScheme: baseTheme.colorScheme.copyWith(
          surface: _s.backgroundColor,
          onSurface: _s.textColor,
          surfaceContainerHighest: _s.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
        chipTheme: baseTheme.chipTheme.copyWith(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          secondarySelectedColor: _s.accentColor,
        ),
      ),
      child: Scaffold(
        backgroundColor: _s.backgroundColor,
        appBar: AppBar(
          title: Text(
            'Reading Stats',
            style: _s.uiText(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: -0.3,
            ),
          ),
          centerTitle: true,
          backgroundColor: _s.backgroundColor,
          foregroundColor: _s.textColor,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: !_loaded
            ? Center(
                child: CircularProgressIndicator(
                  color: _s.accentColor,
                  strokeWidth: 2.5,
                ),
              )
            : FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      _buildStreakCard(),
                      const SizedBox(height: 20),
                      _buildSummaryRow(),
                      if (_s.readingInsightsEnabled) ...[
                        const SizedBox(height: 28),
                        _buildReadingPaceSection(),
                      ],
                      const SizedBox(height: 28),
                      _buildHeatmapSection(),
                      const SizedBox(height: 28),
                      _buildWeeklyBreakdown(),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildReadingPaceSection() {
    final confidence = _statsService.globalConfidence;
    final confidenceLabel = switch (confidence) {
      ReadingPaceConfidence.uncalibrated => 'Calibrating',
      ReadingPaceConfidence.low => 'Low confidence',
      ReadingPaceConfidence.medium => 'Medium confidence',
      ReadingPaceConfidence.high => 'High confidence',
    };
    final calibration = ReadingStatsService.formatDuration(
      Duration(seconds: _statsService.globalCalibrationSeconds),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reading Pace',
          style: _s.uiText(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _s.textColor,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _s.menuColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _s.mutedColor.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildPaceMetric(
                      icon: Icons.speed_rounded,
                      label: 'Average pace',
                      value: '${_statsService.globalEstimatedWpm} WPM',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPaceMetric(
                      icon: Icons.insights_rounded,
                      label: confidenceLabel,
                      value: calibration == '0m' ? 'New' : '$calibration read',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaceMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _s.accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: _s.accentColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: _s.uiText(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _s.textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: _s.uiText(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _s.mutedColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Streak Card ───────────────────────────────────────────────────

  Widget _buildStreakCard() {
    final streak = _statsService.currentStreak;
    final longest = _statsService.longestStreak;
    final hasStreak = streak > 0;
    final didQualifyToday = _statsService.didQualifyToday;
    final remainingMinutes = (_statsService.remainingSecondsToQualifyToday / 60)
        .ceil();
    final goalMinutes = (ReadingStatsService.minDailyReadSeconds / 60).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: hasStreak ? null : _s.menuColor,
        gradient: hasStreak
            ? LinearGradient(
                colors: [_s.accentColor, _s.accentColor.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(20),
        border: hasStreak
            ? null
            : Border.all(color: _s.mutedColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Icon instead of emoji
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: hasStreak
                  ? Colors.white.withValues(alpha: 0.2)
                  : _s.mutedColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              hasStreak
                  ? Icons.local_fire_department_rounded
                  : Icons.auto_stories_rounded,
              size: 28,
              color: hasStreak ? Colors.white : _s.mutedColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasStreak ? '$streak-day streak!' : 'Start your streak!',
            style: _s.uiText(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: hasStreak ? Colors.white : _s.textColor,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            didQualifyToday
                ? 'Daily reading goal completed.'
                : hasStreak
                ? 'Read $remainingMinutes more min today to keep it.'
                : 'Read $goalMinutes min today to start.',
            textAlign: TextAlign.center,
            style: _s.uiText(
              fontSize: 14,
              color: hasStreak
                  ? Colors.white.withValues(alpha: 0.86)
                  : _s.mutedColor,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          if (hasStreak && longest > streak) ...[
            const SizedBox(height: 6),
            Text(
              'Longest: $longest days',
              style: _s.uiText(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (!hasStreak && longest > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Best streak: $longest days',
              style: _s.uiText(
                fontSize: 13,
                color: _s.mutedColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Summary Stats Row ─────────────────────────────────────────────

  Widget _buildSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.description_outlined,
            value: _formatNumber(_statsService.totalPagesRead),
            label: 'Pages Read',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            icon: Icons.check_circle_outline_rounded,
            value: '${_statsService.totalBooksCompleted}',
            label: 'Books Done',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            icon: Icons.calendar_today_rounded,
            value: _formatNumber(_statsService.pagesReadThisWeek),
            label: 'This Week',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: _s.menuColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _s.mutedColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _s.mutedColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _s.mutedColor),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: _s.uiText(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _s.textColor,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: _s.uiText(
              fontSize: 11,
              color: _s.mutedColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Heatmap Section ───────────────────────────────────────────────

  Widget _buildHeatmapSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Reading Activity',
              style: _s.uiText(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _s.textColor,
                letterSpacing: -0.3,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _isYearlyView = !_isYearlyView),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _s.mutedColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isYearlyView
                        ? _s.accentColor.withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isYearlyView
                          ? Icons.calendar_month
                          : Icons.calendar_today,
                      size: 14,
                      color: _isYearlyView ? _s.accentColor : _s.mutedColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isYearlyView ? 'Full Year' : 'This Month',
                      style: _s.uiText(
                        fontSize: 11,
                        color: _isYearlyView ? _s.textColor : _s.mutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _s.menuColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _s.mutedColor.withValues(alpha: 0.08)),
          ),
          child: GestureDetector(
            onTap: () => setState(() => _isYearlyView = !_isYearlyView),
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                _ReadingHeatmap(
                  settings: _s,
                  heatmapData: _statsService.getHeatmapData(
                    days: _isYearlyView ? 3650 : 60,
                  ),
                  maxPages: _statsService.maxDailyPages,
                  isDark: _s.isDark,
                  textColor: _s.textColor,
                  mutedColor: _s.mutedColor,
                  isYearlyView: _isYearlyView,
                  accentColor: _s.accentColor,
                  onToggle: () =>
                      setState(() => _isYearlyView = !_isYearlyView),
                ),
                const SizedBox(height: 12),
                _buildHeatmapLegend(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeatmapLegend() {
    const baseColor = Color(0xFF4CAF50);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less', style: _s.uiText(fontSize: 10, color: _s.mutedColor)),
        const SizedBox(width: 4),
        for (int i = 0; i < 5; i++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: i == 0
                  ? (_s.isDark ? const Color(0xFF1A1A1A) : Colors.grey[200])
                  : baseColor.withValues(alpha: 0.2 + (i * 0.2)),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 4),
        Text('More', style: _s.uiText(fontSize: 10, color: _s.mutedColor)),
      ],
    );
  }

  // ─── Weekly Breakdown ──────────────────────────────────────────────

  Widget _buildWeeklyBreakdown() {
    final now = DateTime.now();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final heatmap = _statsService.getHeatmapData(days: 7);

    // Build bars for each day
    final dailyCounts = <int>[];
    final labels = <String>[];
    int maxDay = 1;

    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final count = heatmap[key] ?? 0;
      dailyCounts.add(count);
      labels.add(dayNames[day.weekday - 1]);
      if (count > maxDay) maxDay = count;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This Week',
          style: _s.uiText(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _s.textColor,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          decoration: BoxDecoration(
            color: _s.menuColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _s.mutedColor.withValues(alpha: 0.08)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final count = dailyCounts[i];
              final ratio = maxDay > 0 ? count / maxDay : 0.0;
              final isToday = i == 6;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Count label
                      Text(
                        count > 0 ? '$count' : '',
                        style: _s.uiText(
                          fontSize: 10,
                          color: _s.mutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Bar
                      Container(
                        height: 80 * ratio + 4,
                        decoration: BoxDecoration(
                          color: count > 0
                              ? (isToday
                                    ? _s.accentColor
                                    : const Color(0xFF4CAF50))
                              : _s.mutedColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Day label
                      Text(
                        labels[i],
                        style: _s.uiText(
                          fontSize: 10,
                          color: isToday ? _s.textColor : _s.mutedColor,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  String _formatNumber(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return '$n';
  }
}

class _ReadingHeatmap extends StatelessWidget {
  final ReadingSettings settings;
  final Map<String, int> heatmapData;
  final int maxPages;
  final bool isYearlyView;
  final bool isDark;
  final Color textColor;
  final Color mutedColor;
  final Color accentColor;
  final VoidCallback onToggle;

  const _ReadingHeatmap({
    required this.settings,
    required this.heatmapData,
    required this.maxPages,
    required this.isDark,
    required this.textColor,
    required this.mutedColor,
    required this.accentColor,
    required this.isYearlyView,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return isYearlyView
        ? _buildYearlyView(context)
        : _buildMonthlyView(context);
  }

  Widget _buildMonthlyView(BuildContext context) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;

    // Day of week for padding (0=Sun, 1=Mon... 6=Sat)
    final startPadding = firstDayOfMonth.weekday % 7;
    final weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      children: [
        // Weekday headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekDays
              .map(
                (day) => Expanded(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: settings.uiText(
                      fontSize: 10,
                      color: mutedColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        // Days Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: startPadding + daysInMonth,
          itemBuilder: (context, index) {
            if (index < startPadding) return const SizedBox.shrink();

            final dayNumber = index - startPadding + 1;
            final date = DateTime(now.year, now.month, dayNumber);
            final key =
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final pages = heatmapData[key] ?? 0;
            final isToday = dayNumber == now.day;

            final intensity = maxPages > 0
                ? (pages / maxPages).clamp(0.0, 1.0)
                : 0.0;

            return Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _cellColor(intensity),
                borderRadius: BorderRadius.circular(4),
                border: isToday
                    ? Border.all(color: accentColor, width: 1.5)
                    : null,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildYearlyView(BuildContext context) {
    final now = DateTime.now();
    final currentYear = now.year;
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 32.0;
        final availableWidth = constraints.maxWidth - labelWidth - 8;
        // Keep cells small to fit 31 columns
        final cellSize = (availableWidth / 31) - 2.0;
        final clampedSize = cellSize.clamp(6.0, 10.0);

        return Column(
          children: [
            for (int mIdx = 0; mIdx < 12; mIdx++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Text(
                        months[mIdx],
                        style: settings.uiText(
                          fontSize: 9,
                          color: mutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(31, (dIdx) {
                          final day = dIdx + 1;
                          final date = DateTime(currentYear, mIdx + 1, day);
                          final isValidDay = date.month == (mIdx + 1);
                          if (!isValidDay) {
                            return SizedBox(
                              width: clampedSize,
                              height: clampedSize,
                            );
                          }
                          if (date.isAfter(now)) {
                            return Container(
                              width: clampedSize,
                              height: clampedSize,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.03)
                                    : Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            );
                          }
                          final key =
                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                          final pages = heatmapData[key] ?? 0;
                          final intensity = maxPages > 0
                              ? (pages / maxPages).clamp(0.0, 1.0)
                              : 0.0;
                          return Container(
                            width: clampedSize,
                            height: clampedSize,
                            decoration: BoxDecoration(
                              color: _cellColor(intensity),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Color _cellColor(double intensity) {
    if (intensity <= 0) {
      return isDark ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE);
    }
    const baseGreen = Color(0xFF4CAF50);
    if (intensity < 0.25) return baseGreen.withValues(alpha: 0.25);
    if (intensity < 0.50) return baseGreen.withValues(alpha: 0.45);
    if (intensity < 0.75) return baseGreen.withValues(alpha: 0.65);
    return baseGreen.withValues(alpha: 0.90);
  }
}
