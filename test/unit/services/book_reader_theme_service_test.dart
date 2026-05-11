import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/book_reader_theme_service.dart';
import 'package:nalori/services/cover_palette_service.dart';

void main() {
  group('BookReaderThemeService', () {
    test(
      'derives readable light and dark reader palettes from cover colors',
      () {
        final service = BookReaderThemeService();

        final palette = service.fromCoverPalette(
          const CoverPalette(
            primary: Color(0xFF7A2734),
            secondary: Color(0xFF1C7F74),
          ),
        );

        expect(
          _contrastRatio(palette.light.text, palette.light.background),
          greaterThanOrEqualTo(4.8),
        );
        expect(
          _contrastRatio(palette.dark.text, palette.dark.background),
          greaterThanOrEqualTo(4.8),
        );
        expect(palette.light.background.computeLuminance(), greaterThan(0.65));
        expect(palette.dark.background.computeLuminance(), lessThan(0.12));
      },
    );
  });
}

double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}
