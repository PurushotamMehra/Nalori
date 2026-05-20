import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/services/cover_palette_service.dart';
import 'package:nalori/ui/continue_reading_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContinueReadingColors', () {
    test('fallback preserves the existing continue reading accent', () {
      final colors = ContinueReadingColors.fallback(const ReadingSettings());

      expect(colors.accentColor.toARGB32(), 0xFFE85D04);
      expect(colors.onAccentColor, Colors.white);
    });

    test('derives readable dark launch colors from a cover palette', () {
      final fallback = ContinueReadingColors.fallback(const ReadingSettings());
      final colors = ContinueReadingColors.fromCover(
        settings: const ReadingSettings(),
        palette: const CoverPalette(
          primary: Color(0xFF6E2433),
          secondary: Color(0xFF167B72),
        ),
      );

      expect(colors.baseColor, fallback.baseColor);
      expect(colors.surfaceColor, fallback.surfaceColor);
      expect(
        _contrastRatio(colors.titleColor, colors.baseColor),
        greaterThanOrEqualTo(4.8),
      );
      expect(
        _contrastRatio(
          colors.statusTextColor,
          _compositeOver(colors.statusBackgroundColor, colors.baseColor),
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(colors.onAccentColor, colors.accentColor),
        greaterThanOrEqualTo(4.5),
      );
      expect(colors.accentColor.toARGB32(), isNot(0xFFE85D04));
    });

    test('derives readable light launch colors from a cover palette', () {
      const settings = ReadingSettings(appTheme: AppTheme.softLight);
      final fallback = ContinueReadingColors.fallback(settings);
      final colors = ContinueReadingColors.fromCover(
        settings: settings,
        palette: const CoverPalette(
          primary: Color(0xFF2A5C8F),
          secondary: Color(0xFFE0B84C),
        ),
      );

      expect(colors.baseColor, fallback.baseColor);
      expect(colors.surfaceColor, fallback.surfaceColor);
      expect(
        _contrastRatio(colors.titleColor, colors.baseColor),
        greaterThanOrEqualTo(4.8),
      );
      expect(
        _contrastRatio(
          colors.statusTextColor,
          _compositeOver(colors.statusBackgroundColor, colors.baseColor),
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(colors.onAccentColor, colors.accentColor),
        greaterThanOrEqualTo(4.5),
      );
      expect(colors.accentColor.toARGB32(), isNot(0xFFE85D04));
    });

    test('uses the dominant cover color hue for the accent', () {
      final colors = ContinueReadingColors.fromCover(
        settings: const ReadingSettings(),
        palette: const CoverPalette(
          primary: Color(0xFF244C8A),
          secondary: Color(0xFF2F5791),
        ),
      );

      final primaryHue = HSVColor.fromColor(const Color(0xFF244C8A)).hue;
      final accentHue = HSVColor.fromColor(colors.accentColor).hue;

      expect(_hueDistance(primaryHue, accentHue), lessThan(6));
    });
  });
}

double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

double _hueDistance(double a, double b) {
  final diff = (a - b).abs();
  return diff < 180 ? diff : 360 - diff;
}

Color _compositeOver(Color foreground, Color background) {
  final alpha = foreground.a;
  return Color.from(
    alpha: 1,
    red: foreground.r * alpha + background.r * (1 - alpha),
    green: foreground.g * alpha + background.g * (1 - alpha),
    blue: foreground.b * alpha + background.b * (1 - alpha),
  );
}
