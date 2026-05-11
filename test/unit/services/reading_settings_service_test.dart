import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nalori/services/reading_settings_service.dart';
import 'package:nalori/models/reading_settings.dart';

void main() {
  late ReadingSettingsService settingsService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settingsService = ReadingSettingsService();
  });

  group('ReadingSettingsService', () {
    group('loadSettings', () {
      test('should return default settings when no saved settings', () async {
        final result = await settingsService.loadSettings();

        expect(result.appTheme, AppTheme.system);
        expect(result.appFontFamily, AppFontFamily.inter);
        expect(result.fontFamily, ReaderFontFamily.lexend);
        expect(result.fontSize, ReaderFontSize.m);
        expect(result.fontWeight, ReaderFontWeight.regular);
        expect(result.contentDensity, ContentDensity.medium);
        expect(result.textAlign, ReaderTextAlign.left);
        expect(result.pagingAxis, ReaderPagingAxis.vertical);
        expect(result.enableCardDepth, true);
        expect(result.lineHeight, 1.3);
        expect(result.useVolumeButtonsForPaging, false);
        expect(result.speedReadDisplayMode, SpeedReadDisplayMode.lyrics);
        expect(
          result.speedReadPageAdvanceMode,
          SpeedReadPageAdvanceMode.manual,
        );
        expect(result.speedReadAdaptivePacing, true);
      });

      test('should load saved theme', () async {
        SharedPreferences.setMockInitialValues({'setting_appTheme': 'dark'});

        final result = await settingsService.loadSettings();

        expect(result.appTheme, AppTheme.dark);
      });

      test('should load old settings without custom reader theme', () async {
        SharedPreferences.setMockInitialValues({'setting_appTheme': 'sepia'});

        final result = await settingsService.loadSettings();

        expect(result.appTheme, AppTheme.sepia);
        expect(result.useCustomReaderTheme, false);
        expect(result.customReaderTheme, isNull);
      });

      test('should load saved app font family', () async {
        SharedPreferences.setMockInitialValues({
          'setting_appFontFamily': 'lexend',
        });

        final result = await settingsService.loadSettings();

        expect(result.appFontFamily, AppFontFamily.lexend);
      });

      test('should load saved font family', () async {
        SharedPreferences.setMockInitialValues({
          'setting_fontFamilyName': 'inter',
        });

        final result = await settingsService.loadSettings();

        expect(result.fontFamily, ReaderFontFamily.inter);
      });

      test('should load saved font size', () async {
        SharedPreferences.setMockInitialValues({'setting_fontSize': 4});

        final result = await settingsService.loadSettings();

        expect(result.fontSize, ReaderFontSize.xl);
      });

      test('should load saved font weight', () async {
        SharedPreferences.setMockInitialValues({'setting_fontWeight': 4});

        final result = await settingsService.loadSettings();

        expect(result.fontWeight, ReaderFontWeight.bold);
      });

      test('should load saved text align', () async {
        SharedPreferences.setMockInitialValues({'setting_textAlign': 2});

        final result = await settingsService.loadSettings();

        expect(result.textAlign, ReaderTextAlign.right);
      });

      test('should load saved paging axis', () async {
        SharedPreferences.setMockInitialValues({
          'setting_pagingAxis': 'horizontal',
        });

        final result = await settingsService.loadSettings();

        expect(result.pagingAxis, ReaderPagingAxis.horizontal);
      });

      test('should load saved content density', () async {
        SharedPreferences.setMockInitialValues({
          'contentDensity': 'ContentDensity.high',
        });

        final result = await settingsService.loadSettings();

        expect(result.contentDensity, ContentDensity.high);
      });

      test('should load blue light filter settings', () async {
        SharedPreferences.setMockInitialValues({
          'setting_blueLightFilter': true,
          'setting_blueLightIntensity': 0.5,
          'setting_dimText': true,
          'setting_dimTextIntensity': 0.3,
        });

        final result = await settingsService.loadSettings();

        expect(result.blueLightFilter, true);
        expect(result.blueLightIntensity, 0.5);
        expect(result.dimText, true);
        expect(result.dimTextIntensity, 0.3);
      });

      test('should load volume button paging setting', () async {
        SharedPreferences.setMockInitialValues({
          'setting_useVolumeButtonsForPaging': true,
        });

        final result = await settingsService.loadSettings();

        expect(result.useVolumeButtonsForPaging, true);
      });

      test('should load Card Mode setting', () async {
        SharedPreferences.setMockInitialValues({
          'setting_enableCardDepth': true,
        });

        final result = await settingsService.loadSettings();

        expect(result.enableCardDepth, true);
      });

      test('should load speed read behavior settings', () async {
        SharedPreferences.setMockInitialValues({
          'setting_speedReadDisplayMode': 'window',
          'setting_speedReadPageAdvanceMode': 'auto',
          'setting_speedReadWPM': 350,
          'setting_speedReadAdaptivePacing': false,
        });

        final result = await settingsService.loadSettings();

        expect(result.speedReadDisplayMode, SpeedReadDisplayMode.window);
        expect(result.speedReadPageAdvanceMode, SpeedReadPageAdvanceMode.auto);
        expect(result.speedReadWPM, 350);
        expect(result.speedReadAdaptivePacing, false);
      });

      test(
        'should keep legacy saved settings on speed read auto advance',
        () async {
          SharedPreferences.setMockInitialValues({'setting_speedReadWPM': 250});

          final result = await settingsService.loadSettings();

          expect(result.speedReadDisplayMode, SpeedReadDisplayMode.lyrics);
          expect(
            result.speedReadPageAdvanceMode,
            SpeedReadPageAdvanceMode.auto,
          );
        },
      );

      test('should migrate legacy font index', () async {
        SharedPreferences.setMockInitialValues({'setting_fontFamily': 1});

        final result = await settingsService.loadSettings();

        expect(result.fontFamily, ReaderFontFamily.inter);
      });
    });

    group('saveSettings', () {
      test('should save all settings', () async {
        const settings = ReadingSettings(
          appTheme: AppTheme.sepia,
          appFontFamily: AppFontFamily.manrope,
          fontFamily: ReaderFontFamily.merriweather,
          fontWeight: ReaderFontWeight.bold,
          fontSize: ReaderFontSize.l,
          textAlign: ReaderTextAlign.justify,
          pagingAxis: ReaderPagingAxis.horizontal,
          contentDensity: ContentDensity.high,
          enableCardDepth: true,
          blueLightFilter: true,
          blueLightIntensity: 0.4,
          dimText: true,
          dimTextIntensity: 0.28,
          useVolumeButtonsForPaging: true,
          speedReadWPM: 350,
          speedReadDisplayMode: SpeedReadDisplayMode.window,
          speedReadPageAdvanceMode: SpeedReadPageAdvanceMode.auto,
          speedReadAdaptivePacing: false,
        );

        await settingsService.saveSettings(settings);

        final result = await settingsService.loadSettings();

        expect(result.appTheme, AppTheme.sepia);
        expect(result.appFontFamily, AppFontFamily.manrope);
        expect(result.fontFamily, ReaderFontFamily.merriweather);
        expect(result.fontWeight, ReaderFontWeight.bold);
        expect(result.fontSize, ReaderFontSize.l);
        expect(result.textAlign, ReaderTextAlign.justify);
        expect(result.pagingAxis, ReaderPagingAxis.horizontal);
        expect(result.contentDensity, ContentDensity.high);
        expect(result.enableCardDepth, true);
        expect(result.blueLightFilter, true);
        expect(result.blueLightIntensity, 0.4);
        expect(result.dimText, true);
        expect(result.dimTextIntensity, 0.28);
        expect(result.useVolumeButtonsForPaging, true);
        expect(result.speedReadWPM, 350);
        expect(result.speedReadDisplayMode, SpeedReadDisplayMode.window);
        expect(result.speedReadPageAdvanceMode, SpeedReadPageAdvanceMode.auto);
        expect(result.speedReadAdaptivePacing, false);
      });

      test('should save and restore custom reader theme', () async {
        const customTheme = CustomReaderTheme(
          readerBackgroundColor: 0xFF111111,
          cardBackgroundColor: 0xFF222222,
          textColor: 0xFFEFEFEF,
          secondaryTextColor: 0xFFBBBBBB,
          borderColor: 0xFF333333,
          accentColor: 0xFFFFAA00,
          iconColor: 0xFFEFEFEF,
          inactiveControlColor: 0xFF777777,
          cardShadowColor: 0xAA000000,
          selectionColor: 0x55FFAA00,
          highlightDefaultColor: 0xFFFFD54F,
          bookmarkColor: 0xFFE1306C,
          speedReadActiveWordColor: 0xFFFFFFFF,
          speedReadInactiveWordColor: 0x88FFFFFF,
        );

        await settingsService.saveSettings(
          const ReadingSettings(
            useCustomReaderTheme: true,
            customReaderTheme: customTheme,
          ),
        );

        final result = await settingsService.loadSettings();

        expect(result.useCustomReaderTheme, true);
        expect(result.customReaderTheme, isNotNull);
        expect(result.customReaderTheme!.cardBackgroundColor, 0xFF222222);
        expect(result.backgroundColor.toARGB32(), 0xFF111111);
        expect(result.cardBackgroundColor.toARGB32(), 0xFF222222);
      });

      test('should ignore invalid custom reader theme payload', () async {
        SharedPreferences.setMockInitialValues({
          'setting_useCustomReaderTheme': true,
          'setting_customReaderTheme': 'not json',
        });

        final result = await settingsService.loadSettings();

        expect(result.useCustomReaderTheme, true);
        expect(result.customReaderTheme, isNull);
        expect(result.isCustomReaderThemeActive, false);
      });
    });

    group('presets', () {
      test('should return empty presets when none are saved', () async {
        final result = await settingsService.loadPresets();

        expect(result, isEmpty);
      });

      test('should save and load custom reader presets', () async {
        final presets = [
          const ReadingSettingsPreset(
            id: 'preset-1',
            name: 'Night',
            settings: ReadingSettings(
              readerTheme: AppTheme.dark,
              fontFamily: ReaderFontFamily.lora,
              fontSize: ReaderFontSize.l,
              contentDensity: ContentDensity.low,
              blueLightFilter: true,
              dimText: true,
              lineHeight: 1.6,
            ),
          ),
        ];

        await settingsService.savePresets(presets);
        final result = await settingsService.loadPresets();

        expect(result, hasLength(1));
        expect(result.first.id, 'preset-1');
        expect(result.first.name, 'Night');
        expect(result.first.settings.effectiveTheme, AppTheme.dark);
        expect(result.first.settings.fontFamily, ReaderFontFamily.lora);
        expect(result.first.settings.fontSize, ReaderFontSize.l);
        expect(result.first.settings.contentDensity, ContentDensity.low);
        expect(result.first.settings.blueLightFilter, true);
        expect(result.first.settings.dimText, true);
        expect(result.first.settings.lineHeight, 1.6);
      });

      test('should ignore invalid saved preset payloads', () async {
        SharedPreferences.setMockInitialValues({
          'setting_readerPresets': '[{"id":"","name":"Broken"}]',
        });

        final result = await settingsService.loadPresets();

        expect(result, isEmpty);
      });

      test('should save and load hidden built-in preset ids', () async {
        await settingsService.saveHiddenBuiltInPresetIds({
          'builtin-comfort',
          'builtin-amoled-cards',
        });

        final result = await settingsService.loadHiddenBuiltInPresetIds();

        expect(result, {'builtin-amoled-cards', 'builtin-comfort'});
      });
    });
  });
}
