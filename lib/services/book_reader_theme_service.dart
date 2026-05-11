import 'package:flutter/material.dart';

import '../models/reading_settings.dart';
import 'cover_palette_service.dart';

class BookReaderThemeService {
  final CoverPaletteService _coverPaletteService;

  BookReaderThemeService({CoverPaletteService? coverPaletteService})
    : _coverPaletteService = coverPaletteService ?? CoverPaletteService();

  Future<BookReaderThemePalette?> loadPalette(String? coverImagePath) async {
    final palette = await _coverPaletteService.loadPalette(coverImagePath);
    if (palette == null) return null;
    return fromCoverPalette(palette);
  }

  @visibleForTesting
  BookReaderThemePalette fromCoverPalette(CoverPalette palette) {
    final primary = palette.primary;
    final secondary = palette.secondary;
    final darkAccent = _mix(secondary, Colors.white, 0.22);
    final lightAccent = _mix(primary, Colors.black, 0.26);

    return BookReaderThemePalette(
      light: ReaderThemeColors(
        background: _mix(primary, Colors.white, 0.90),
        menu: _mix(primary, Colors.white, 0.84),
        text: _ensureContrast(
          foreground: _mix(primary, Colors.black, 0.66),
          background: _mix(primary, Colors.white, 0.90),
          darkenForeground: true,
        ),
        muted: _mix(secondary, Colors.black, 0.42),
        accent: lightAccent,
      ),
      dark: ReaderThemeColors(
        background: _mix(primary, Colors.black, 0.78),
        menu: _mix(secondary, Colors.black, 0.70),
        text: _ensureContrast(
          foreground: _mix(secondary, Colors.white, 0.76),
          background: _mix(primary, Colors.black, 0.78),
          darkenForeground: false,
        ),
        muted: _mix(secondary, Colors.white, 0.54),
        accent: darkAccent,
      ),
    );
  }

  Color _ensureContrast({
    required Color foreground,
    required Color background,
    required bool darkenForeground,
  }) {
    var result = foreground;
    var amount = 0.0;
    final target = darkenForeground ? Colors.black : Colors.white;

    while (_contrastRatio(result, background) < 4.8 && amount < 1.0) {
      amount = (amount + 0.08).clamp(0.0, 1.0);
      result = _mix(foreground, target, amount);
    }

    return result;
  }

  double _contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  Color _mix(Color a, Color b, double amount) {
    return Color.lerp(a, b, amount.clamp(0.0, 1.0))!;
  }
}
