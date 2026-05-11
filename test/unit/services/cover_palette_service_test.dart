import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/cover_palette_service.dart';

void main() {
  group('CoverPaletteService', () {
    test('picks a repeated vibrant color cluster as primary', () {
      final service = CoverPaletteService();
      final colors = <Color>[
        for (var i = 0; i < 24; i++) const Color(0xFFC21F3A),
        for (var i = 0; i < 4; i++) const Color(0xFF244CFF),
      ];

      final primary = service.pickPrimary(colors);

      expect(primary, const Color(0xFFC21F3A));
    });

    test('ranks dominant color clusters ahead of isolated vivid pixels', () {
      final service = CoverPaletteService();
      final colors = <Color>[
        for (var i = 0; i < 18; i++) const Color(0xFF1FA56E),
        const Color(0xFFFF00F0),
      ];

      final ranked = service.rankedColorClusters(colors);

      expect(ranked.first.color, const Color(0xFF1FA56E));
      expect(ranked.first.count, 18);
    });
  });
}
