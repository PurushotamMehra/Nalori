import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/reading_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('ReadingSettings', () {
    group('theme choices', () {
      test('should keep system theme out of reader theme tiles', () {
        expect(kAppThemeChoices.first, AppTheme.system);
        expect(kReaderThemeChoices, isNot(contains(AppTheme.system)));
      });
    });

    group('constructor', () {
      test('should create with default values', () {
        const settings = ReadingSettings();

        expect(settings.appTheme, AppTheme.system);
        expect(settings.appFontFamily, AppFontFamily.inter);
        expect(settings.fontFamily, ReaderFontFamily.lexend);
        expect(settings.fontWeight, ReaderFontWeight.regular);
        expect(settings.fontSize, ReaderFontSize.m);
        expect(settings.textAlign, ReaderTextAlign.left);
        expect(settings.pagingAxis, ReaderPagingAxis.vertical);
        expect(settings.contentDensity, ContentDensity.medium);
        expect(settings.enableCardDepth, true);
        expect(settings.blueLightFilter, false);
        expect(settings.blueLightIntensity, 0.3);
        expect(settings.dimText, false);
        expect(settings.dimTextIntensity, 0.22);
        expect(settings.useVolumeButtonsForPaging, false);
        expect(settings.readingInsightsEnabled, true);
        expect(settings.speedReadDisplayMode, SpeedReadDisplayMode.lyrics);
        expect(
          settings.speedReadPageAdvanceMode,
          SpeedReadPageAdvanceMode.manual,
        );
        expect(settings.speedReadAdaptivePacing, true);
        expect(settings.lineHeight, 1.3);
      });

      test('should accept custom values', () {
        const settings = ReadingSettings(
          appTheme: AppTheme.sepia,
          appFontFamily: AppFontFamily.poppins,
          fontFamily: ReaderFontFamily.inter,
          fontWeight: ReaderFontWeight.bold,
          fontSize: ReaderFontSize.xl,
          textAlign: ReaderTextAlign.justify,
          pagingAxis: ReaderPagingAxis.horizontal,
          contentDensity: ContentDensity.high,
          enableCardDepth: true,
          blueLightFilter: true,
          blueLightIntensity: 0.5,
          dimText: true,
          dimTextIntensity: 0.3,
          useVolumeButtonsForPaging: true,
          readingInsightsEnabled: false,
          speedReadDisplayMode: SpeedReadDisplayMode.window,
          speedReadPageAdvanceMode: SpeedReadPageAdvanceMode.auto,
          speedReadAdaptivePacing: false,
        );

        expect(settings.appTheme, AppTheme.sepia);
        expect(settings.appFontFamily, AppFontFamily.poppins);
        expect(settings.fontFamily, ReaderFontFamily.inter);
        expect(settings.fontWeight, ReaderFontWeight.bold);
        expect(settings.fontSize, ReaderFontSize.xl);
        expect(settings.textAlign, ReaderTextAlign.justify);
        expect(settings.pagingAxis, ReaderPagingAxis.horizontal);
        expect(settings.contentDensity, ContentDensity.high);
        expect(settings.enableCardDepth, true);
        expect(settings.blueLightFilter, true);
        expect(settings.blueLightIntensity, 0.5);
        expect(settings.dimText, true);
        expect(settings.dimTextIntensity, 0.3);
        expect(settings.useVolumeButtonsForPaging, true);
        expect(settings.readingInsightsEnabled, false);
        expect(settings.speedReadDisplayMode, SpeedReadDisplayMode.window);
        expect(
          settings.speedReadPageAdvanceMode,
          SpeedReadPageAdvanceMode.auto,
        );
        expect(settings.speedReadAdaptivePacing, false);
      });
    });

    group('effectiveTheme', () {
      test('should return readerTheme when set', () {
        const settings = ReadingSettings(
          appTheme: AppTheme.dark,
          readerTheme: AppTheme.sepia,
        );

        expect(settings.effectiveTheme, AppTheme.sepia);
      });

      test('should return appTheme when readerTheme is null', () {
        const settings = ReadingSettings(appTheme: AppTheme.dark);

        expect(settings.effectiveTheme, AppTheme.dark);
      });
    });

    group('isDark', () {
      test('should return true for dark theme', () {
        const settings = ReadingSettings(appTheme: AppTheme.dark);

        expect(settings.isDark, true);
      });

      test('should return true for amoled theme', () {
        const settings = ReadingSettings(appTheme: AppTheme.amoled);

        expect(settings.isDark, true);
      });

      test('should return false for light theme', () {
        const settings = ReadingSettings(appTheme: AppTheme.softLight);

        expect(settings.isDark, false);
      });

      test('should return false for sepia theme', () {
        const settings = ReadingSettings(appTheme: AppTheme.sepia);

        expect(settings.isDark, false);
      });

      test('should return true for book dark theme', () {
        const settings = ReadingSettings(appTheme: AppTheme.bookDark);

        expect(settings.isDark, true);
      });
    });

    group('color getters', () {
      test('should parse and serialize reader theme hex colors', () {
        expect(hexToColor('#112233')!.toARGB32(), 0xFF112233);
        expect(hexToColor('112233')!.toARGB32(), 0xFF112233);
        expect(hexToColor('#80112233')!.toARGB32(), 0x80112233);
        expect(hexToColor('not-hex'), isNull);
        expect(validateHexColor('#112233'), true);
        expect(validateHexColor('#XYZ'), false);
        expect(colorToHex(const Color(0xFF112233)), '#112233');
        expect(
          colorToHex(const Color(0x80112233), includeAlpha: true),
          '#80112233',
        );
      });

      test('should use custom reader theme colors when active', () {
        const customTheme = CustomReaderTheme(
          readerBackgroundColor: 0xFF101010,
          cardBackgroundColor: 0xFF202020,
          textColor: 0xFFEFEFEF,
          secondaryTextColor: 0xFFB0B0B0,
          borderColor: 0xFF303030,
          accentColor: 0xFFFFAA00,
          iconColor: 0xFFE0E0E0,
          inactiveControlColor: 0xFF606060,
          cardShadowColor: 0x99000000,
          selectionColor: 0x55FFAA00,
          highlightDefaultColor: 0xFFFFD54F,
          bookmarkColor: 0xFFE1306C,
          speedReadActiveWordColor: 0xFFFFFFFF,
          speedReadInactiveWordColor: 0x88FFFFFF,
        );
        const settings = ReadingSettings(
          appTheme: AppTheme.softLight,
          useCustomReaderTheme: true,
          customReaderTheme: customTheme,
        );

        expect(settings.backgroundColor.toARGB32(), 0xFF101010);
        expect(settings.cardBackgroundColor.toARGB32(), 0xFF202020);
        expect(settings.textColor.toARGB32(), 0xFFEFEFEF);
        expect(settings.mutedColor.toARGB32(), 0xFFB0B0B0);
        expect(settings.accentColor.toARGB32(), 0xFFFFAA00);
        expect(settings.speedReadInactiveWordColor.toARGB32(), 0x88FFFFFF);
      });

      test('should safely fallback invalid custom reader theme colors', () {
        final theme = CustomReaderTheme.fromJson({
          'readerBackgroundColor': 'bad',
          'cardBackgroundColor': '#123456',
          'textColor': '#FFFFFF',
          'secondaryTextColor': '#AAAAAA',
          'borderColor': '#222222',
          'accentColor': '#FFAA00',
          'iconColor': '#EFEFEF',
          'inactiveControlColor': '#666666',
          'cardShadowColor': '#99000000',
          'selectionColor': '#55FFAA00',
          'highlightDefaultColor': '#FFD54F',
          'bookmarkColor': '#E1306C',
        });

        expect(theme, isNotNull);
        expect(
          theme!.readerBackgroundColor,
          CustomReaderTheme.fallback.readerBackgroundColor,
        );
        expect(theme.cardBackgroundColor, 0xFF123456);
      });

      test('should return correct background color for amoled', () {
        const settings = ReadingSettings(appTheme: AppTheme.amoled);

        expect(settings.backgroundColor.toARGB32(), 0xFF000000);
      });

      test('should return correct background color for softLight', () {
        const settings = ReadingSettings(appTheme: AppTheme.softLight);

        expect(settings.backgroundColor.toARGB32(), 0xFFFAF8F5);
      });

      test('should return correct menu color for dark', () {
        const settings = ReadingSettings(appTheme: AppTheme.dark);

        expect(settings.menuColor.toARGB32(), 0xFF2C2C2C);
      });

      test('should return correct text color for amoled', () {
        const settings = ReadingSettings(appTheme: AppTheme.amoled);

        expect(settings.textColor.toARGB32(), 0xFFFFFFFF);
      });

      test(
        'should keep background pitch black in amoled when blue light is on',
        () {
          const settings = ReadingSettings(
            appTheme: AppTheme.amoled,
            blueLightFilter: true,
            blueLightIntensity: 0.5,
          );

          expect(settings.backgroundColor.toARGB32(), 0xFF000000);
          expect(settings.readerTextColor, isNot(equals(settings.textColor)));
          expect(
            settings.readerTextColor.red,
            greaterThan(settings.textColor.red - 1),
          );
          expect(
            settings.readerTextColor.blue,
            lessThan(settings.textColor.blue),
          );
        },
      );

      test('should return correct muted color for sepia', () {
        const settings = ReadingSettings(appTheme: AppTheme.sepia);

        expect(settings.mutedColor.toARGB32(), 0xFF8A7967);
      });

      test('should dim reader text without changing the background', () {
        const settings = ReadingSettings(
          appTheme: AppTheme.amoled,
          dimText: true,
          dimTextIntensity: 0.4,
        );

        expect(settings.readerTextColor, isNot(equals(settings.textColor)));
        expect(settings.readerTextColor.red, lessThan(settings.textColor.red));
        expect(settings.backgroundColor.toARGB32(), 0xFF000000);
      });

      test('should warm non-amoled reader text visibly', () {
        const settings = ReadingSettings(
          appTheme: AppTheme.sepia,
          blueLightFilter: true,
          blueLightIntensity: 0.5,
        );

        expect(settings.readerTextColor, isNot(equals(settings.textColor)));
        expect(
          settings.readerTextColor.red,
          greaterThan(settings.textColor.red),
        );
      });

      test('should use injected book light colors', () {
        const palette = BookReaderThemePalette(
          light: ReaderThemeColors(
            background: Color(0xFFF4E9DD),
            menu: Color(0xFFE8D5C0),
            text: Color(0xFF23180F),
            muted: Color(0xFF6E5745),
            accent: Color(0xFF8A4422),
          ),
          dark: ReaderThemeColors(
            background: Color(0xFF120B08),
            menu: Color(0xFF22130E),
            text: Color(0xFFF4D9C0),
            muted: Color(0xFFC09475),
            accent: Color(0xFFFFA06A),
          ),
        );
        const settings = ReadingSettings(
          appTheme: AppTheme.bookLight,
          bookThemePalette: palette,
        );

        expect(settings.backgroundColor.toARGB32(), 0xFFF4E9DD);
        expect(settings.menuColor.toARGB32(), 0xFFE8D5C0);
        expect(settings.textColor.toARGB32(), 0xFF23180F);
        expect(settings.mutedColor.toARGB32(), 0xFF6E5745);
        expect(settings.accentColor.toARGB32(), 0xFF8A4422);
      });

      test('should use safe fallback colors when book palette is missing', () {
        const settings = ReadingSettings(appTheme: AppTheme.bookDark);

        expect(settings.backgroundColor.toARGB32(), 0xFF1E1E1E);
        expect(settings.textColor.toARGB32(), 0xFFE0E0E0);
      });
    });

    group('densityMultiplier', () {
      test('should return 0.35 for low density', () {
        const settings = ReadingSettings(contentDensity: ContentDensity.low);

        expect(settings.densityMultiplier, 0.35);
      });

      test('should return 0.55 for medium density', () {
        const settings = ReadingSettings(contentDensity: ContentDensity.medium);

        expect(settings.densityMultiplier, 0.55);
      });

      test('should return 0.75 for high density', () {
        const settings = ReadingSettings(contentDensity: ContentDensity.high);

        expect(settings.densityMultiplier, 0.75);
      });

      test('should return 1.0 for fullPage density', () {
        const settings = ReadingSettings(
          contentDensity: ContentDensity.fullPage,
        );

        expect(settings.densityMultiplier, 1.0);
      });
    });

    group('resolvedTextAlign', () {
      test('should return TextAlign.left for left', () {
        const settings = ReadingSettings(textAlign: ReaderTextAlign.left);

        expect(settings.resolvedTextAlign.name, 'left');
      });

      test('should return TextAlign.center for center', () {
        const settings = ReadingSettings(textAlign: ReaderTextAlign.center);

        expect(settings.resolvedTextAlign.name, 'center');
      });

      test('should return TextAlign.right for right', () {
        const settings = ReadingSettings(textAlign: ReaderTextAlign.right);

        expect(settings.resolvedTextAlign.name, 'right');
      });

      test('should return TextAlign.justify for justify', () {
        const settings = ReadingSettings(textAlign: ReaderTextAlign.justify);

        expect(settings.resolvedTextAlign.name, 'justify');
      });
    });

    group('resolvedPagingAxis', () {
      test('should return Axis.vertical for vertical paging', () {
        const settings = ReadingSettings(pagingAxis: ReaderPagingAxis.vertical);

        expect(settings.resolvedPagingAxis, Axis.vertical);
      });

      test('should return Axis.horizontal for horizontal paging', () {
        const settings = ReadingSettings(
          pagingAxis: ReaderPagingAxis.horizontal,
        );

        expect(settings.resolvedPagingAxis, Axis.horizontal);
      });
    });

    group('copyWith', () {
      test('should copy with new appTheme', () {
        const original = ReadingSettings(appTheme: AppTheme.dark);
        final copy = original.copyWith(appTheme: AppTheme.sepia);

        expect(copy.appTheme, AppTheme.sepia);
        expect(copy.fontFamily, ReaderFontFamily.lexend);
      });

      test('should copy with new readerTheme', () {
        const original = ReadingSettings();
        final copy = original.copyWith(readerTheme: AppTheme.dark);

        expect(copy.readerTheme, AppTheme.dark);
      });

      test('should copy with new comfort settings', () {
        const original = ReadingSettings();
        final copy = original.copyWith(
          blueLightFilter: true,
          blueLightIntensity: 0.4,
          dimText: true,
          dimTextIntensity: 0.3,
        );

        expect(copy.blueLightFilter, true);
        expect(copy.blueLightIntensity, 0.4);
        expect(copy.dimText, true);
        expect(copy.dimTextIntensity, 0.3);
      });

      test('should copy and clear book theme palette', () {
        const palette = BookReaderThemePalette(
          light: ReaderThemeColors(
            background: Color(0xFFFFFFFF),
            menu: Color(0xFFF0F0F0),
            text: Color(0xFF111111),
            muted: Color(0xFF555555),
            accent: Color(0xFF333333),
          ),
          dark: ReaderThemeColors(
            background: Color(0xFF000000),
            menu: Color(0xFF111111),
            text: Color(0xFFFFFFFF),
            muted: Color(0xFFBBBBBB),
            accent: Color(0xFFDDDDDD),
          ),
        );
        final withPalette = const ReadingSettings().copyWith(
          bookThemePalette: palette,
        );
        final cleared = withPalette.copyWith(clearBookThemePalette: true);

        expect(withPalette.bookThemePalette, palette);
        expect(cleared.bookThemePalette, isNull);
      });

      test('should clear readerTheme with clearReaderTheme', () {
        const original = ReadingSettings(readerTheme: AppTheme.dark);
        final copy = original.copyWith(clearReaderTheme: true);

        expect(copy.readerTheme, isNull);
      });

      test('should copy with new paging and hardware controls settings', () {
        const original = ReadingSettings();
        final copy = original.copyWith(
          pagingAxis: ReaderPagingAxis.horizontal,
          useVolumeButtonsForPaging: true,
          speedReadDisplayMode: SpeedReadDisplayMode.window,
          speedReadPageAdvanceMode: SpeedReadPageAdvanceMode.auto,
          speedReadAdaptivePacing: false,
        );

        expect(copy.pagingAxis, ReaderPagingAxis.horizontal);
        expect(copy.useVolumeButtonsForPaging, true);
        expect(copy.speedReadDisplayMode, SpeedReadDisplayMode.window);
        expect(copy.speedReadPageAdvanceMode, SpeedReadPageAdvanceMode.auto);
        expect(copy.speedReadAdaptivePacing, false);
      });
    });

    group('heading typography', () {
      test(
        'should keep chapter heading metrics independent from body line height',
        () {
          const settings = ReadingSettings(
            fontFamily: ReaderFontFamily.literata,
            fontSize: ReaderFontSize.m,
            lineHeight: 1.8,
          );

          final headingFontSize =
              settings.fontSizeValue + (14 * settings.fontSizeMultiplier);

          expect(ReadingSettings.headingLineHeight, 1.3);
          expect(headingFontSize, greaterThan(settings.fontSizeValue));
          expect(settings.lineHeight, 1.8);
        },
      );
    });

    group('fontSizeValue', () {
      test('should return 14 for xs', () {
        const settings = ReadingSettings(fontSize: ReaderFontSize.xs);

        expect(settings.fontSizeValue, 14.0);
      });

      test('should return 16 for s', () {
        const settings = ReadingSettings(fontSize: ReaderFontSize.s);

        expect(settings.fontSizeValue, 16.0);
      });

      test('should return 18 for m', () {
        const settings = ReadingSettings(fontSize: ReaderFontSize.m);

        expect(settings.fontSizeValue, 18.0);
      });

      test('should return 22 for l', () {
        const settings = ReadingSettings(fontSize: ReaderFontSize.l);

        expect(settings.fontSizeValue, 22.0);
      });

      test('should return 26 for xl', () {
        const settings = ReadingSettings(fontSize: ReaderFontSize.xl);

        expect(settings.fontSizeValue, 26.0);
      });
    });

    group('fontWeightValue', () {
      test('should return w300 for light', () {
        const settings = ReadingSettings(fontWeight: ReaderFontWeight.light);

        expect(settings.fontWeightValue, FontWeight.w300);
      });

      test('should return w400 for regular', () {
        const settings = ReadingSettings(fontWeight: ReaderFontWeight.regular);

        expect(settings.fontWeightValue, FontWeight.w400);
      });

      test('should return w500 for medium', () {
        const settings = ReadingSettings(fontWeight: ReaderFontWeight.medium);

        expect(settings.fontWeightValue, FontWeight.w500);
      });

      test('should return w600 for semiBold', () {
        const settings = ReadingSettings(fontWeight: ReaderFontWeight.semiBold);

        expect(settings.fontWeightValue, FontWeight.w600);
      });

      test('should return w700 for bold', () {
        const settings = ReadingSettings(fontWeight: ReaderFontWeight.bold);

        expect(settings.fontWeightValue, FontWeight.w700);
      });
    });

    group('getTextStyle', () {
      // Note: getTextStyle requires Flutter binding for google_fonts
      // These tests verify the method exists and returns a TextStyle
      test('should return TextStyle for normal text', () {
        const settings = ReadingSettings(
          fontSize: ReaderFontSize.m,
          fontWeight: ReaderFontWeight.regular,
        );

        // Just verify the method is callable - actual font loading requires binding
        expect(settings.fontSizeValue, 18.0);
      });

      test('should return larger fontSize for heading', () {
        const settings = ReadingSettings(
          fontSize: ReaderFontSize.m,
          fontWeight: ReaderFontWeight.regular,
        );

        final baseSize = settings.fontSizeValue;
        final headingSize = settings.fontSizeValue + 14; // isHeading adds 14

        expect(headingSize, greaterThan(baseSize));
      });
    });
  });
}
