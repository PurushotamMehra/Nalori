import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reading_settings.dart';

class ReadingSettingsService {
  static const _presetsKey = 'setting_readerPresets';
  static const _hiddenBuiltInPresetsKey = 'setting_hiddenBuiltInReaderPresets';
  static final settingsNotifier = ValueNotifier<ReadingSettings>(
    const ReadingSettings(),
  );

  Future<ReadingSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final appThemeString = prefs.getString('setting_appTheme');
    final appFontFamilyName = prefs.getString('setting_appFontFamily');
    final fontFamilyName = prefs.getString('setting_fontFamilyName');
    final fontIndex = prefs.getInt('setting_fontFamily');
    final weightIndex = prefs.getInt('setting_fontWeight');
    final sizeIndex = prefs.getInt('setting_fontSize');
    final alignIndex = prefs.getInt('setting_textAlign');
    final pagingAxisName = prefs.getString('setting_pagingAxis');
    final contentDensityString = prefs.getString('contentDensity');
    final enableCardDepth = prefs.getBool('setting_enableCardDepth');
    final blueLightFilter = prefs.getBool('setting_blueLightFilter');
    final blueLightIntensity = prefs.getDouble('setting_blueLightIntensity');
    final dimText = prefs.getBool('setting_dimText');
    final dimTextIntensity = prefs.getDouble('setting_dimTextIntensity');
    final useVolumeButtonsForPaging = prefs.getBool(
      'setting_useVolumeButtonsForPaging',
    );
    final readingInsightsEnabled = prefs.getBool(
      'setting_readingInsightsEnabled',
    );
    final speedReadWPM = prefs.getInt('setting_speedReadWPM');
    final speedReadDisplayModeName = prefs.getString(
      'setting_speedReadDisplayMode',
    );
    final speedReadPageAdvanceModeName = prefs.getString(
      'setting_speedReadPageAdvanceMode',
    );
    final speedReadAdaptivePacing = prefs.getBool(
      'setting_speedReadAdaptivePacing',
    );
    final lineHeightVal = prefs.getDouble('setting_lineHeight_val');
    final paragraphSpacingVal = prefs.getDouble('setting_paragraphSpacing_val');
    final useCustomReaderTheme = prefs.getBool('setting_useCustomReaderTheme');
    final customReaderThemeJson = prefs.getString('setting_customReaderTheme');
    final hasLegacySpeedReadSettings =
        prefs.containsKey('setting_speedReadWPM') ||
        prefs.containsKey('setting_appTheme') ||
        prefs.containsKey('setting_fontFamilyName') ||
        prefs.containsKey('setting_fontFamily');

    // Resolve font family: prefer name-based lookup, fall back to index (legacy),
    // default to Lexend if neither exists or value is invalid.
    ReaderFontFamily resolvedFont = ReaderFontFamily.lexend;
    if (fontFamilyName != null) {
      resolvedFont = ReaderFontFamily.values.firstWhere(
        (e) => e.name == fontFamilyName,
        orElse: () => ReaderFontFamily.lexend,
      );
    } else if (fontIndex != null) {
      // Legacy migration: old enum was {literata=0, inter=1, robotoMono=2, comicNeue=3}
      // Map old indices to new enum values
      const oldIndexMap = <int, ReaderFontFamily>{
        0: ReaderFontFamily.literata,
        1: ReaderFontFamily.inter,
        2: ReaderFontFamily.robotoMono,
        // 3 was comicNeue (removed) — fall back to literata
      };
      resolvedFont = oldIndexMap[fontIndex] ?? ReaderFontFamily.lexend;
    }

    final settings = ReadingSettings(
      appTheme: appThemeString != null
          ? AppTheme.values.firstWhere(
              (e) => e.name == appThemeString,
              orElse: () => AppTheme.system,
            )
          : AppTheme.system,
      appFontFamily: appFontFamilyName != null
          ? AppFontFamily.values.firstWhere(
              (e) => e.name == appFontFamilyName,
              orElse: () => AppFontFamily.inter,
            )
          : AppFontFamily.inter,
      fontFamily: resolvedFont,
      fontWeight:
          weightIndex != null && weightIndex < ReaderFontWeight.values.length
          ? ReaderFontWeight.values[weightIndex]
          : ReaderFontWeight.regular,
      fontSize: sizeIndex != null && sizeIndex < ReaderFontSize.values.length
          ? ReaderFontSize.values[sizeIndex]
          : ReaderFontSize.m,
      textAlign:
          alignIndex != null && alignIndex < ReaderTextAlign.values.length
          ? ReaderTextAlign.values[alignIndex]
          : ReaderTextAlign.left,
      pagingAxis: pagingAxisName != null
          ? ReaderPagingAxis.values.firstWhere(
              (e) => e.name == pagingAxisName,
              orElse: () => ReaderPagingAxis.vertical,
            )
          : ReaderPagingAxis.vertical,
      contentDensity: contentDensityString != null
          ? ContentDensity.values.firstWhere(
              (e) => e.toString() == contentDensityString,
              orElse: () => ContentDensity.medium,
            )
          : ContentDensity.medium,
      enableCardDepth: enableCardDepth ?? true,
      blueLightFilter: blueLightFilter ?? false,
      blueLightIntensity: blueLightIntensity ?? 0.3,
      dimText: dimText ?? false,
      dimTextIntensity: dimTextIntensity ?? 0.22,
      useVolumeButtonsForPaging: useVolumeButtonsForPaging ?? false,
      readingInsightsEnabled: readingInsightsEnabled ?? true,
      speedReadWPM: speedReadWPM ?? 200,
      speedReadDisplayMode: speedReadDisplayModeName != null
          ? SpeedReadDisplayMode.values.firstWhere(
              (e) => e.name == speedReadDisplayModeName,
              orElse: () => SpeedReadDisplayMode.lyrics,
            )
          : SpeedReadDisplayMode.lyrics,
      speedReadPageAdvanceMode: speedReadPageAdvanceModeName != null
          ? SpeedReadPageAdvanceMode.values.firstWhere(
              (e) => e.name == speedReadPageAdvanceModeName,
              orElse: () => SpeedReadPageAdvanceMode.manual,
            )
          : hasLegacySpeedReadSettings
          ? SpeedReadPageAdvanceMode.auto
          : SpeedReadPageAdvanceMode.manual,
      speedReadAdaptivePacing: speedReadAdaptivePacing ?? true,
      lineHeight: lineHeightVal ?? 1.3,
      paragraphSpacing: paragraphSpacingVal ?? 1.0,
      useCustomReaderTheme: useCustomReaderTheme ?? false,
      customReaderTheme: _decodeCustomReaderTheme(customReaderThemeJson),
    );
    settingsNotifier.value = settings;
    return settings;
  }

  Future<void> saveSettings(ReadingSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('setting_appTheme', settings.appTheme.name);
    await prefs.setString('setting_appFontFamily', settings.appFontFamily.name);
    await prefs.setString('setting_fontFamilyName', settings.fontFamily.name);
    // Keep legacy index for backward compat (will be ignored on next load)
    await prefs.setInt('setting_fontFamily', settings.fontFamily.index);
    await prefs.setInt('setting_fontWeight', settings.fontWeight.index);
    await prefs.setInt('setting_fontSize', settings.fontSize.index);
    await prefs.setInt('setting_textAlign', settings.textAlign.index);
    await prefs.setString('setting_pagingAxis', settings.pagingAxis.name);
    await prefs.setString('contentDensity', settings.contentDensity.toString());
    await prefs.setBool('setting_enableCardDepth', settings.enableCardDepth);
    await prefs.setBool('setting_blueLightFilter', settings.blueLightFilter);
    await prefs.setDouble(
      'setting_blueLightIntensity',
      settings.blueLightIntensity,
    );
    await prefs.setBool('setting_dimText', settings.dimText);
    await prefs.setDouble(
      'setting_dimTextIntensity',
      settings.dimTextIntensity,
    );
    await prefs.setBool(
      'setting_useVolumeButtonsForPaging',
      settings.useVolumeButtonsForPaging,
    );
    await prefs.setBool(
      'setting_readingInsightsEnabled',
      settings.readingInsightsEnabled,
    );
    await prefs.setInt('setting_speedReadWPM', settings.speedReadWPM);
    await prefs.setString(
      'setting_speedReadDisplayMode',
      settings.speedReadDisplayMode.name,
    );
    await prefs.setString(
      'setting_speedReadPageAdvanceMode',
      settings.speedReadPageAdvanceMode.name,
    );
    await prefs.setBool(
      'setting_speedReadAdaptivePacing',
      settings.speedReadAdaptivePacing,
    );
    await prefs.setDouble('setting_lineHeight_val', settings.lineHeight);
    await prefs.setDouble(
      'setting_paragraphSpacing_val',
      settings.paragraphSpacing,
    );
    await prefs.setBool(
      'setting_useCustomReaderTheme',
      settings.useCustomReaderTheme,
    );
    final customTheme = settings.customReaderTheme;
    if (customTheme == null) {
      await prefs.remove('setting_customReaderTheme');
    } else {
      await prefs.setString(
        'setting_customReaderTheme',
        jsonEncode(customTheme.toJson()),
      );
    }
    settingsNotifier.value = settings;
  }

  CustomReaderTheme? _decodeCustomReaderTheme(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return CustomReaderTheme.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<List<ReadingSettingsPreset>> loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_presetsKey);
    if (encoded == null || encoded.isEmpty) return const [];

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                ReadingSettingsPreset.fromJson(Map<String, Object?>.from(item)),
          )
          .whereType<ReadingSettingsPreset>()
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> savePresets(List<ReadingSettingsPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = presets.take(4).map((preset) => preset.toJson()).toList();
    await prefs.setString(_presetsKey, jsonEncode(capped));
  }

  Future<Set<String>> loadHiddenBuiltInPresetIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_hiddenBuiltInPresetsKey) ?? const <String>[])
        .toSet();
  }

  Future<void> saveHiddenBuiltInPresetIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenBuiltInPresetsKey, ids.toList()..sort());
  }
}
