import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/quote_card_palette_service.dart';

void main() {
  group('QuoteCardPaletteService', () {
    test('returns fallback themes when cover path is missing', () async {
      final service = QuoteCardPaletteService();

      final themes = await service.loadThemes(null);

      expect(themes, isNotEmpty);
      expect(themes.map((theme) => theme.name), contains('Deep'));
      expect(themes.map((theme) => theme.name), contains('AMOLED'));
      expect(themes.every((theme) => theme.backgroundColors.length >= 2), true);
    });

    test('fallback themes include readable foreground colors', () {
      final themes = QuoteCardPaletteService.fallbackThemes();

      expect(themes, hasLength(greaterThanOrEqualTo(3)));
      for (final theme in themes) {
        expect(theme.quoteColor, isNotNull);
        expect(theme.metadataColor, isNotNull);
        expect(theme.logoColor, isNotNull);
      }
    });
  });
}
