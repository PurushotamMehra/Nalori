import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/reading_settings.dart';
import '../services/cover_palette_service.dart';

@immutable
class ContinueReadingColors {
  static const _fallbackAccent = Color(0xFFE85D04);

  final Color baseColor;
  final Color surfaceColor;
  final Color titleColor;
  final Color authorColor;
  final Color statusBackgroundColor;
  final Color statusBorderColor;
  final Color statusTextColor;
  final Color browseColor;
  final Color progressTrackColor;
  final Color accentColor;
  final Color onAccentColor;

  const ContinueReadingColors({
    required this.baseColor,
    required this.surfaceColor,
    required this.titleColor,
    required this.authorColor,
    required this.statusBackgroundColor,
    required this.statusBorderColor,
    required this.statusTextColor,
    required this.browseColor,
    required this.progressTrackColor,
    required this.accentColor,
    required this.onAccentColor,
  });

  factory ContinueReadingColors.fallback(ReadingSettings settings) {
    final baseColor = settings.backgroundColor;
    final surfaceColor = settings.menuColor;
    final titleColor = settings.isDark ? Colors.white : settings.textColor;
    final authorColor = settings.isDark
        ? Colors.white.withValues(alpha: 0.74)
        : settings.mutedColor;

    return ContinueReadingColors(
      baseColor: baseColor,
      surfaceColor: surfaceColor,
      titleColor: titleColor,
      authorColor: authorColor,
      statusBackgroundColor: settings.isDark
          ? Colors.white.withValues(alpha: 0.1)
          : baseColor.withValues(alpha: 0.92),
      statusBorderColor: settings.isDark
          ? Colors.white.withValues(alpha: 0.12)
          : surfaceColor.withValues(alpha: 0.9),
      statusTextColor: settings.isDark
          ? Colors.white.withValues(alpha: 0.78)
          : settings.textColor.withValues(alpha: 0.82),
      browseColor: settings.isDark
          ? Colors.white.withValues(alpha: 0.64)
          : settings.mutedColor,
      progressTrackColor: settings.isDark
          ? Colors.white.withValues(alpha: 0.16)
          : surfaceColor,
      accentColor: _fallbackAccent,
      onAccentColor: Colors.white,
    );
  }

  factory ContinueReadingColors.fromCover({
    required ReadingSettings settings,
    required CoverPalette palette,
  }) {
    final isDark = settings.isDark;
    final themeColors = ContinueReadingColors.fallback(settings);
    final baseColor = themeColors.baseColor;
    final surfaceColor = themeColors.surfaceColor;
    final accentColor = _accentFor(palette, isDark: isDark);

    if (isDark) {
      return ContinueReadingColors(
        baseColor: baseColor,
        surfaceColor: surfaceColor,
        titleColor: themeColors.titleColor,
        authorColor: themeColors.authorColor,
        statusBackgroundColor: themeColors.statusBackgroundColor,
        statusBorderColor: themeColors.statusBorderColor,
        statusTextColor: themeColors.statusTextColor,
        browseColor: themeColors.browseColor,
        progressTrackColor: themeColors.progressTrackColor,
        accentColor: accentColor,
        onAccentColor: _foregroundFor(accentColor),
      );
    }

    return ContinueReadingColors(
      baseColor: baseColor,
      surfaceColor: surfaceColor,
      titleColor: themeColors.titleColor,
      authorColor: themeColors.authorColor,
      statusBackgroundColor: themeColors.statusBackgroundColor,
      statusBorderColor: themeColors.statusBorderColor,
      statusTextColor: themeColors.statusTextColor,
      browseColor: themeColors.browseColor,
      progressTrackColor: themeColors.progressTrackColor,
      accentColor: accentColor,
      onAccentColor: _foregroundFor(accentColor),
    );
  }

  static Color _accentFor(CoverPalette palette, {required bool isDark}) {
    final seed = HSVColor.fromColor(palette.primary);

    final saturation = seed.saturation.clamp(0.42, 0.82);
    final value = isDark
        ? seed.value.clamp(0.58, 0.88)
        : seed.value.clamp(0.34, 0.62);

    final tuned = seed.withSaturation(saturation).withValue(value).toColor();
    return isDark
        ? _mix(tuned, Colors.white, 0.10)
        : _mix(tuned, Colors.black, 0.08);
  }

  static Color _foregroundFor(Color background) {
    final whiteRatio = _contrastRatio(Colors.white, background);
    final blackRatio = _contrastRatio(Colors.black, background);
    return whiteRatio >= blackRatio ? Colors.white : Colors.black;
  }

  static double _contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static Color _mix(Color a, Color b, double amount) {
    return Color.lerp(a, b, amount.clamp(0.0, 1.0))!;
  }
}
