import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/services/highlight_palette_service.dart';

void main() {
  late HighlightPaletteService paletteService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    paletteService = HighlightPaletteService();
  });

  group('HighlightPaletteService', () {
    test('loads the default palette when no custom colors exist', () async {
      final palette = await paletteService.loadPalette();

      expect(palette, kHighlightColors);
    });

    test('adds custom colors before the defaults', () async {
      await paletteService.addCustomColor(const Color(0xFF009688));

      final palette = await paletteService.loadPalette();

      expect(palette.first, const Color(0xFF009688));
      expect(palette, hasLength(kHighlightColors.length + 1));
    });

    test('does not duplicate default or custom colors', () async {
      await paletteService.addCustomColor(const Color(0xFFFFD54F));
      await paletteService.addCustomColor(const Color(0xFF009688));
      await paletteService.addCustomColor(const Color(0xFF009688));

      final palette = await paletteService.loadPalette();

      expect(
        palette.where(
          (color) => isSameHighlightColor(color, const Color(0xFFFFD54F)),
        ),
        hasLength(1),
      );
      expect(
        palette.where(
          (color) => isSameHighlightColor(color, const Color(0xFF009688)),
        ),
        hasLength(1),
      );
    });

    test('removes only saved custom colors', () async {
      await paletteService.addCustomColor(const Color(0xFF8E24AA));

      final palette = await paletteService.removeCustomColor(
        const Color(0xFF8E24AA),
      );

      expect(
        palette.where(
          (color) => isSameHighlightColor(color, const Color(0xFF8E24AA)),
        ),
        isEmpty,
      );
      expect(palette, hasLength(kHighlightColors.length));
    });

    test('persists the default color selection', () async {
      await paletteService.saveDefaultColor(const Color(0xFF8E24AA));

      expect(await paletteService.loadDefaultColor(), const Color(0xFF8E24AA));
    });

    test('parses and formats hex colors', () {
      expect(highlightColorHex(const Color(0xFF12ABEF)), '#12ABEF');
      expect(parseHighlightHexColor('#12ABEF'), const Color(0xFF12ABEF));
      expect(parseHighlightHexColor('12ABEF'), const Color(0xFF12ABEF));
      expect(parseHighlightHexColor('#XYZ123'), isNull);
    });
  });
}
