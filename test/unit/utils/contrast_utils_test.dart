import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/utils/contrast_utils.dart';

void main() {
  group('readableForegroundForBackground', () {
    test('uses a calm light foreground for dark highlight colors', () {
      for (final color in const [
        Color(0xFF0D47A1), // dark blue
        Color(0xFF4A148C), // dark purple
        Color(0xFF7F1D1D), // dark red
        Color(0xFF1B5E20), // dark green
      ]) {
        final foreground = readableForegroundForBackground(color);

        expect(foreground, kCalmLightForeground);
        expect(contrastRatio(foreground, color), greaterThanOrEqualTo(4.5));
      }
    });

    test('uses a calm dark foreground for light highlight colors', () {
      for (final color in const [
        Color(0xFFFFD54F), // yellow
        Color(0xFFCE93D8), // light purple
        Color(0xFF81C784), // light green
        Color(0xFFFFE0B2), // light orange
      ]) {
        final foreground = readableForegroundForBackground(color);

        expect(foreground, kCalmDarkForeground);
        expect(contrastRatio(foreground, color), greaterThanOrEqualTo(4.5));
      }
    });

    test('composites translucent colors before choosing foreground', () {
      final effectiveBackground = compositeColorOver(
        const Color(0x990D47A1),
        Colors.white,
      );

      final foreground = readableForegroundForBackground(effectiveBackground);

      expect(contrastRatio(foreground, effectiveBackground), greaterThan(4.5));
    });
  });
}
