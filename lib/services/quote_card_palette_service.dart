import 'package:flutter/material.dart';

import '../models/quote_card_theme.dart';
import 'cover_palette_service.dart';

class QuoteCardPaletteService {
  final CoverPaletteService _coverPaletteService;

  QuoteCardPaletteService({CoverPaletteService? coverPaletteService})
    : _coverPaletteService = coverPaletteService ?? CoverPaletteService();

  Future<List<QuoteCardTheme>> loadThemes(String? coverImagePath) async {
    final palette = await _coverPaletteService.loadPalette(coverImagePath);
    if (palette == null) return fallbackThemes();
    return _themesFromPalette(palette);
  }

  static List<QuoteCardTheme> fallbackThemes() {
    const green = Color(0xFF0D332E);
    const black = Color(0xFF0A0A0A);
    const coral = Color(0xFFB64B5F);
    const mint = Color(0xFFDFF5F0);
    const graphite = Color(0xFF171717);
    const ink = Color(0xFF161817);

    return [
      const QuoteCardTheme(
        name: 'Deep',
        backgroundColors: [green, black, coral],
        quoteColor: Colors.white,
        metadataColor: Colors.white70,
        logoColor: Colors.white,
        accentColor: coral,
      ),
      const QuoteCardTheme(
        name: 'Ink',
        backgroundColors: [graphite, Color(0xFF273D38), black],
        quoteColor: Colors.white,
        metadataColor: Colors.white70,
        logoColor: Colors.white,
        accentColor: Color(0xFF8DE0D0),
      ),
      const QuoteCardTheme(
        name: 'AMOLED',
        backgroundColors: [Colors.black, Colors.black],
        quoteColor: Colors.white,
        metadataColor: Colors.white70,
        logoColor: Colors.white,
        accentColor: Color(0xFF00D7BE),
      ),
      const QuoteCardTheme(
        name: 'Paper',
        backgroundColors: [Color(0xFFF5FAF8), mint, Color(0xFFF1D9DF)],
        quoteColor: ink,
        metadataColor: Color(0xB3161817),
        logoColor: ink,
        accentColor: green,
      ),
      const QuoteCardTheme(
        name: 'Minimal',
        backgroundColors: [Colors.white, Color(0xFFE9EEEE)],
        quoteColor: Colors.black,
        metadataColor: Color(0x99000000),
        logoColor: Colors.black,
        accentColor: Color(0xFF008577),
      ),
    ];
  }

  List<QuoteCardTheme> _themesFromPalette(CoverPalette palette) {
    final primary = palette.primary;
    final secondary = palette.secondary;
    final accent = _mix(secondary, Colors.white, 0.18);
    final darkPrimary = _mix(primary, Colors.black, 0.52);
    final darkSecondary = _mix(secondary, Colors.black, 0.48);
    final lightPrimary = _mix(primary, Colors.white, 0.88);
    final lightSecondary = _mix(secondary, Colors.white, 0.82);
    final lightText = _readableTextFor([lightPrimary, lightSecondary]);

    return [
      QuoteCardTheme(
        name: 'Cover',
        backgroundColors: [
          darkPrimary,
          darkSecondary,
          _mix(accent, Colors.black, 0.28),
        ],
        quoteColor: Colors.white,
        metadataColor: Colors.white70,
        logoColor: Colors.white,
        accentColor: accent,
      ),
      QuoteCardTheme(
        name: 'Ink',
        backgroundColors: [
          const Color(0xFF090909),
          _mix(primary, Colors.black, 0.68),
          _mix(secondary, Colors.black, 0.58),
        ],
        quoteColor: Colors.white,
        metadataColor: Colors.white70,
        logoColor: Colors.white,
        accentColor: accent,
      ),
      QuoteCardTheme(
        name: 'AMOLED',
        backgroundColors: const [Colors.black, Colors.black],
        quoteColor: Colors.white,
        metadataColor: Colors.white70,
        logoColor: Colors.white,
        accentColor: _mix(secondary, Colors.white, 0.28),
      ),
      QuoteCardTheme(
        name: 'Paper',
        backgroundColors: [lightPrimary, lightSecondary, Colors.white],
        quoteColor: lightText,
        metadataColor: lightText.withValues(alpha: 0.66),
        logoColor: lightText,
        accentColor: _mix(primary, Colors.black, 0.24),
      ),
      fallbackThemes().last,
    ];
  }

  Color _readableTextFor(List<Color> colors) {
    final averageLuminance =
        colors.fold<double>(
          0,
          (total, color) => total + color.computeLuminance(),
        ) /
        colors.length;
    return averageLuminance > 0.46 ? const Color(0xFF101010) : Colors.white;
  }

  Color _mix(Color a, Color b, double amount) {
    return Color.lerp(a, b, amount.clamp(0.0, 1.0))!;
  }
}
