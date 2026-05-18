import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ReaderFontFamily {
  literata,
  merriweather,
  lora,
  ebGaramond,
  inter,
  robotoMono,
  atkinsonHyperlegible,
  lexend,
}

enum ReaderFontWeight { light, regular, medium, semiBold, bold }

enum ReaderFontSize { xs, s, m, l, xl }

enum ReaderTextAlign { left, center, right, justify }

enum ReaderPagingAxis { vertical, horizontal }

enum ContentDensity { low, medium, high, fullPage }

enum AppTheme {
  system,
  softLight,
  sepia,
  newspaper,
  dark,
  amoled,
  bookLight,
  bookDark,
}

enum AppFontFamily { inter, lexend, manrope, roboto, poppins, robotoMono }

enum SpeedReadDisplayMode { lyrics, window }

enum SpeedReadPageAdvanceMode { auto, manual }

const kAppThemeChoices = <AppTheme>[
  AppTheme.system,
  AppTheme.softLight,
  AppTheme.sepia,
  AppTheme.newspaper,
  AppTheme.dark,
  AppTheme.amoled,
];

const kReaderThemeChoices = <AppTheme>[
  AppTheme.softLight,
  AppTheme.sepia,
  AppTheme.newspaper,
  AppTheme.dark,
  AppTheme.amoled,
  AppTheme.bookLight,
  AppTheme.bookDark,
];

const kAppFontChoices = <AppFontFamily>[
  AppFontFamily.inter,
  AppFontFamily.lexend,
  AppFontFamily.manrope,
  AppFontFamily.roboto,
  AppFontFamily.poppins,
  AppFontFamily.robotoMono,
];

extension AppFontFamilyX on AppFontFamily {
  String get label {
    return switch (this) {
      AppFontFamily.inter => 'Inter',
      AppFontFamily.lexend => 'Lexend',
      AppFontFamily.manrope => 'Manrope',
      AppFontFamily.roboto => 'Roboto',
      AppFontFamily.poppins => 'Poppins',
      AppFontFamily.robotoMono => 'Roboto Mono',
    };
  }

  String get googleFontName => label;
}

@immutable
class ReaderThemeColors {
  final Color background;
  final Color menu;
  final Color text;
  final Color muted;
  final Color accent;

  const ReaderThemeColors({
    required this.background,
    required this.menu,
    required this.text,
    required this.muted,
    required this.accent,
  });
}

String colorToHex(Color color, {bool includeAlpha = false}) {
  final value = color.toARGB32();
  final hex = value.toRadixString(16).padLeft(8, '0').toUpperCase();
  return '#${includeAlpha ? hex : hex.substring(2)}';
}

bool validateHexColor(String value, {bool allowAlpha = true}) {
  return hexToColor(value, allowAlpha: allowAlpha) != null;
}

Color? hexToColor(String value, {bool allowAlpha = true}) {
  final normalized = value.trim().replaceFirst('#', '');
  final isValidLength =
      normalized.length == 6 || (allowAlpha && normalized.length == 8);
  if (!isValidLength || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized)) {
    return null;
  }

  final argb = normalized.length == 6 ? 'FF$normalized' : normalized;
  final parsed = int.tryParse(argb, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}

int _colorValue(Color color) => color.toARGB32();

int _safeColorValue(Object? raw, Color fallback) {
  if (raw is int) return Color(raw).toARGB32();
  if (raw is String) {
    final parsed = hexToColor(raw);
    if (parsed != null) return parsed.toARGB32();
    final intValue = int.tryParse(raw);
    if (intValue != null) return Color(intValue).toARGB32();
  }
  return fallback.toARGB32();
}

int? _safeOptionalColorValue(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return Color(raw).toARGB32();
  if (raw is String) {
    final parsed = hexToColor(raw);
    if (parsed != null) return parsed.toARGB32();
    final intValue = int.tryParse(raw);
    if (intValue != null) return Color(intValue).toARGB32();
  }
  return null;
}

@immutable
class CustomReaderTheme {
  final String name;
  final int readerBackgroundColor;
  final int cardBackgroundColor;
  final int textColor;
  final int secondaryTextColor;
  final int borderColor;
  final int accentColor;
  final int iconColor;
  final int inactiveControlColor;
  final int cardShadowColor;
  final int selectionColor;
  final int highlightDefaultColor;
  final int bookmarkColor;
  final int? bottomDockBackgroundColor;
  final int? topBarBackgroundColor;
  final int? overlayBackgroundColor;
  final int? speedReadActiveWordColor;
  final int? speedReadInactiveWordColor;

  const CustomReaderTheme({
    this.name = 'My Theme',
    required this.readerBackgroundColor,
    required this.cardBackgroundColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.borderColor,
    required this.accentColor,
    required this.iconColor,
    required this.inactiveControlColor,
    required this.cardShadowColor,
    required this.selectionColor,
    required this.highlightDefaultColor,
    required this.bookmarkColor,
    this.bottomDockBackgroundColor,
    this.topBarBackgroundColor,
    this.overlayBackgroundColor,
    this.speedReadActiveWordColor,
    this.speedReadInactiveWordColor,
  });

  factory CustomReaderTheme.fromSettings(
    ReadingSettings settings, {
    String name = 'My Theme',
  }) {
    final background = settings.backgroundColor;
    final card = settings.cardBackgroundColor;
    final text = settings.textColor;
    final secondary = settings.mutedColor;
    final accent = settings.accentColor;

    return CustomReaderTheme(
      name: name,
      readerBackgroundColor: _colorValue(background),
      cardBackgroundColor: _colorValue(card),
      textColor: _colorValue(text),
      secondaryTextColor: _colorValue(secondary),
      borderColor: _colorValue(secondary.withValues(alpha: 0.24)),
      accentColor: _colorValue(accent),
      iconColor: _colorValue(text),
      inactiveControlColor: _colorValue(secondary.withValues(alpha: 0.62)),
      cardShadowColor: _colorValue(Colors.black.withValues(alpha: 0.28)),
      selectionColor: _colorValue(accent.withValues(alpha: 0.26)),
      highlightDefaultColor: _colorValue(kCustomReaderDefaultHighlightColor),
      bookmarkColor: _colorValue(kCustomReaderDefaultBookmarkColor),
      bottomDockBackgroundColor: _colorValue(settings.menuColor),
      topBarBackgroundColor: _colorValue(settings.menuColor),
      overlayBackgroundColor: _colorValue(settings.menuColor),
      speedReadActiveWordColor: _colorValue(text),
      speedReadInactiveWordColor: _colorValue(
        text.withValues(alpha: settings.isDark ? 0.34 : 0.38),
      ),
    );
  }

  static const fallback = CustomReaderTheme(
    readerBackgroundColor: 0xFF0E1116,
    cardBackgroundColor: 0xFF171B22,
    textColor: 0xFFEDE7DC,
    secondaryTextColor: 0xFFB6AA98,
    borderColor: 0x334A5565,
    accentColor: 0xFFFFB86B,
    iconColor: 0xFFEDE7DC,
    inactiveControlColor: 0xFF7C8794,
    cardShadowColor: 0xAA000000,
    selectionColor: 0x55FFB86B,
    highlightDefaultColor: 0xFFFFD54F,
    bookmarkColor: 0xFFE1306C,
    bottomDockBackgroundColor: 0xFF171B22,
    topBarBackgroundColor: 0xFF171B22,
    overlayBackgroundColor: 0xEE171B22,
    speedReadActiveWordColor: 0xFFEDE7DC,
    speedReadInactiveWordColor: 0x88EDE7DC,
  );

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'readerBackgroundColor': readerBackgroundColor,
      'cardBackgroundColor': cardBackgroundColor,
      'textColor': textColor,
      'secondaryTextColor': secondaryTextColor,
      'borderColor': borderColor,
      'accentColor': accentColor,
      'iconColor': iconColor,
      'inactiveControlColor': inactiveControlColor,
      'cardShadowColor': cardShadowColor,
      'selectionColor': selectionColor,
      'highlightDefaultColor': highlightDefaultColor,
      'bookmarkColor': bookmarkColor,
      if (bottomDockBackgroundColor != null)
        'bottomDockBackgroundColor': bottomDockBackgroundColor,
      if (topBarBackgroundColor != null)
        'topBarBackgroundColor': topBarBackgroundColor,
      if (overlayBackgroundColor != null)
        'overlayBackgroundColor': overlayBackgroundColor,
      if (speedReadActiveWordColor != null)
        'speedReadActiveWordColor': speedReadActiveWordColor,
      if (speedReadInactiveWordColor != null)
        'speedReadInactiveWordColor': speedReadInactiveWordColor,
    };
  }

  static CustomReaderTheme? fromJson(Map<String, Object?> json) {
    try {
      const fallback = CustomReaderTheme.fallback;
      final rawName = json['name'];
      return CustomReaderTheme(
        name: rawName is String && rawName.trim().isNotEmpty
            ? rawName.trim()
            : fallback.name,
        readerBackgroundColor: _safeColorValue(
          json['readerBackgroundColor'],
          fallback.readerBackground,
        ),
        cardBackgroundColor: _safeColorValue(
          json['cardBackgroundColor'],
          fallback.cardBackground,
        ),
        textColor: _safeColorValue(json['textColor'], fallback.text),
        secondaryTextColor: _safeColorValue(
          json['secondaryTextColor'],
          fallback.secondaryText,
        ),
        borderColor: _safeColorValue(json['borderColor'], fallback.border),
        accentColor: _safeColorValue(json['accentColor'], fallback.accent),
        iconColor: _safeColorValue(json['iconColor'], fallback.icon),
        inactiveControlColor: _safeColorValue(
          json['inactiveControlColor'],
          fallback.inactiveControl,
        ),
        cardShadowColor: _safeColorValue(
          json['cardShadowColor'],
          fallback.cardShadow,
        ),
        selectionColor: _safeColorValue(
          json['selectionColor'],
          fallback.selection,
        ),
        highlightDefaultColor: _safeColorValue(
          json['highlightDefaultColor'],
          fallback.highlightDefault,
        ),
        bookmarkColor: _safeColorValue(
          json['bookmarkColor'],
          fallback.bookmark,
        ),
        bottomDockBackgroundColor: _safeOptionalColorValue(
          json['bottomDockBackgroundColor'],
        ),
        topBarBackgroundColor: _safeOptionalColorValue(
          json['topBarBackgroundColor'],
        ),
        overlayBackgroundColor: _safeOptionalColorValue(
          json['overlayBackgroundColor'],
        ),
        speedReadActiveWordColor: _safeOptionalColorValue(
          json['speedReadActiveWordColor'],
        ),
        speedReadInactiveWordColor: _safeOptionalColorValue(
          json['speedReadInactiveWordColor'],
        ),
      );
    } on TypeError {
      return null;
    }
  }

  Color get readerBackground => Color(readerBackgroundColor);
  Color get cardBackground => Color(cardBackgroundColor);
  Color get text => Color(textColor);
  Color get secondaryText => Color(secondaryTextColor);
  Color get border => Color(borderColor);
  Color get accent => Color(accentColor);
  Color get icon => Color(iconColor);
  Color get inactiveControl => Color(inactiveControlColor);
  Color get cardShadow => Color(cardShadowColor);
  Color get selection => Color(selectionColor);
  Color get highlightDefault => Color(highlightDefaultColor);
  Color get bookmark => Color(bookmarkColor);
  Color? get bottomDockBackground => bottomDockBackgroundColor == null
      ? null
      : Color(bottomDockBackgroundColor!);
  Color? get topBarBackground =>
      topBarBackgroundColor == null ? null : Color(topBarBackgroundColor!);
  Color? get overlayBackground =>
      overlayBackgroundColor == null ? null : Color(overlayBackgroundColor!);
  Color? get speedReadActiveWord => speedReadActiveWordColor == null
      ? null
      : Color(speedReadActiveWordColor!);
  Color? get speedReadInactiveWord => speedReadInactiveWordColor == null
      ? null
      : Color(speedReadInactiveWordColor!);

  CustomReaderTheme copyWith({
    String? name,
    int? readerBackgroundColor,
    int? cardBackgroundColor,
    int? textColor,
    int? secondaryTextColor,
    int? borderColor,
    int? accentColor,
    int? iconColor,
    int? inactiveControlColor,
    int? cardShadowColor,
    int? selectionColor,
    int? highlightDefaultColor,
    int? bookmarkColor,
    int? bottomDockBackgroundColor,
    int? topBarBackgroundColor,
    int? overlayBackgroundColor,
    int? speedReadActiveWordColor,
    int? speedReadInactiveWordColor,
  }) {
    return CustomReaderTheme(
      name: name ?? this.name,
      readerBackgroundColor:
          readerBackgroundColor ?? this.readerBackgroundColor,
      cardBackgroundColor: cardBackgroundColor ?? this.cardBackgroundColor,
      textColor: textColor ?? this.textColor,
      secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
      borderColor: borderColor ?? this.borderColor,
      accentColor: accentColor ?? this.accentColor,
      iconColor: iconColor ?? this.iconColor,
      inactiveControlColor: inactiveControlColor ?? this.inactiveControlColor,
      cardShadowColor: cardShadowColor ?? this.cardShadowColor,
      selectionColor: selectionColor ?? this.selectionColor,
      highlightDefaultColor:
          highlightDefaultColor ?? this.highlightDefaultColor,
      bookmarkColor: bookmarkColor ?? this.bookmarkColor,
      bottomDockBackgroundColor:
          bottomDockBackgroundColor ?? this.bottomDockBackgroundColor,
      topBarBackgroundColor:
          topBarBackgroundColor ?? this.topBarBackgroundColor,
      overlayBackgroundColor:
          overlayBackgroundColor ?? this.overlayBackgroundColor,
      speedReadActiveWordColor:
          speedReadActiveWordColor ?? this.speedReadActiveWordColor,
      speedReadInactiveWordColor:
          speedReadInactiveWordColor ?? this.speedReadInactiveWordColor,
    );
  }
}

const kCustomReaderDefaultHighlightColor = Color(0xFFFFD54F);
const kCustomReaderDefaultBookmarkColor = Color(0xFFE1306C);

@immutable
class BookReaderThemePalette {
  final ReaderThemeColors light;
  final ReaderThemeColors dark;

  const BookReaderThemePalette({required this.light, required this.dark});

  ReaderThemeColors colorsFor(AppTheme theme) {
    return switch (theme) {
      AppTheme.bookDark => dark,
      _ => light,
    };
  }
}

@immutable
class ReadingSettingsPreset {
  final String id;
  final String name;
  final String? description;
  final ReadingSettings settings;

  const ReadingSettingsPreset({
    required this.id,
    required this.name,
    this.description,
    required this.settings,
  });

  ReadingSettingsPreset copyWith({
    String? name,
    String? description,
    ReadingSettings? settings,
  }) {
    return ReadingSettingsPreset(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      settings: settings ?? this.settings,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'settings': settings.toPresetJson(),
    };
  }

  static ReadingSettingsPreset? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final rawSettings = json['settings'];
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        rawSettings is! Map) {
      return null;
    }

    return ReadingSettingsPreset(
      id: id,
      name: name,
      description: json['description'] as String?,
      settings: ReadingSettings.fromPresetJson(
        Map<String, Object?>.from(rawSettings),
      ),
    );
  }
}

@immutable
class ReadingSettings {
  static const double headingLineHeight = 1.3;

  final AppTheme appTheme;
  final AppTheme? readerTheme;
  final AppFontFamily appFontFamily;
  final ReaderFontFamily fontFamily;
  final ReaderFontWeight fontWeight;
  final ReaderFontSize fontSize;
  final ReaderTextAlign textAlign;
  final ReaderPagingAxis pagingAxis;
  final ContentDensity contentDensity;
  final bool enableCardDepth;
  final bool blueLightFilter;
  final double blueLightIntensity; // 0.0 - 1.0
  final bool dimText;
  final double dimTextIntensity; // 0.0 - 1.0
  final bool useVolumeButtonsForPaging;
  final bool readingInsightsEnabled;
  final int speedReadWPM;
  final SpeedReadDisplayMode speedReadDisplayMode;
  final SpeedReadPageAdvanceMode speedReadPageAdvanceMode;
  final bool speedReadAdaptivePacing;
  final double lineHeight;
  final double paragraphSpacing;
  final BookReaderThemePalette? bookThemePalette;
  final bool useCustomReaderTheme;
  final CustomReaderTheme? customReaderTheme;

  const ReadingSettings({
    this.appTheme = AppTheme.system,
    this.readerTheme,
    this.appFontFamily = AppFontFamily.inter,
    this.fontFamily = ReaderFontFamily.lexend,
    this.fontWeight = ReaderFontWeight.regular,
    this.fontSize = ReaderFontSize.m,
    this.textAlign = ReaderTextAlign.left,
    this.pagingAxis = ReaderPagingAxis.vertical,
    this.contentDensity = ContentDensity.medium,
    this.enableCardDepth = true,
    this.blueLightFilter = false,
    this.blueLightIntensity = 0.3,
    this.dimText = false,
    this.dimTextIntensity = 0.22,
    this.useVolumeButtonsForPaging = false,
    this.readingInsightsEnabled = true,
    this.speedReadWPM = 200,
    this.speedReadDisplayMode = SpeedReadDisplayMode.lyrics,
    this.speedReadPageAdvanceMode = SpeedReadPageAdvanceMode.manual,
    this.speedReadAdaptivePacing = true,
    this.lineHeight = 1.3,
    this.paragraphSpacing = 1.0,
    this.bookThemePalette,
    this.useCustomReaderTheme = false,
    this.customReaderTheme,
  });

  AppTheme get effectiveTheme {
    final theme = readerTheme ?? appTheme;
    if (theme != AppTheme.system) return theme;
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? AppTheme.dark : AppTheme.softLight;
  }

  bool get isCustomReaderThemeActive =>
      useCustomReaderTheme && customReaderTheme != null;

  bool get isDark => isCustomReaderThemeActive
      ? customReaderTheme!.readerBackground.computeLuminance() < 0.36
      : effectiveTheme == AppTheme.dark ||
            effectiveTheme == AppTheme.amoled ||
            effectiveTheme == AppTheme.bookDark;

  Map<String, Object?> toPresetJson() {
    return {
      'appTheme': appTheme.name,
      'readerTheme': readerTheme?.name,
      'appFontFamily': appFontFamily.name,
      'fontFamily': fontFamily.name,
      'fontWeight': fontWeight.name,
      'fontSize': fontSize.name,
      'textAlign': textAlign.name,
      'pagingAxis': pagingAxis.name,
      'contentDensity': contentDensity.name,
      'enableCardDepth': enableCardDepth,
      'blueLightFilter': blueLightFilter,
      'blueLightIntensity': blueLightIntensity,
      'dimText': dimText,
      'dimTextIntensity': dimTextIntensity,
      'useVolumeButtonsForPaging': useVolumeButtonsForPaging,
      'readingInsightsEnabled': readingInsightsEnabled,
      'speedReadWPM': speedReadWPM,
      'speedReadDisplayMode': speedReadDisplayMode.name,
      'speedReadPageAdvanceMode': speedReadPageAdvanceMode.name,
      'speedReadAdaptivePacing': speedReadAdaptivePacing,
      'lineHeight': lineHeight,
      'paragraphSpacing': paragraphSpacing,
      'useCustomReaderTheme': useCustomReaderTheme,
      'customReaderTheme': customReaderTheme?.toJson(),
    };
  }

  static ReadingSettings fromPresetJson(Map<String, Object?> json) {
    const fallback = ReadingSettings();

    T enumByName<T extends Enum>(List<T> values, Object? raw, T fallbackValue) {
      if (raw is! String) return fallbackValue;
      return values.firstWhere(
        (value) => value.name == raw,
        orElse: () => fallbackValue,
      );
    }

    double doubleValue(Object? raw, double fallbackValue) {
      return switch (raw) {
        final double value => value,
        final int value => value.toDouble(),
        _ => fallbackValue,
      };
    }

    return ReadingSettings(
      appTheme: enumByName(
        AppTheme.values,
        json['appTheme'],
        fallback.appTheme,
      ),
      readerTheme: json['readerTheme'] == null
          ? null
          : enumByName(AppTheme.values, json['readerTheme'], fallback.appTheme),
      appFontFamily: enumByName(
        AppFontFamily.values,
        json['appFontFamily'],
        fallback.appFontFamily,
      ),
      fontFamily: enumByName(
        ReaderFontFamily.values,
        json['fontFamily'],
        fallback.fontFamily,
      ),
      fontWeight: enumByName(
        ReaderFontWeight.values,
        json['fontWeight'],
        fallback.fontWeight,
      ),
      fontSize: enumByName(
        ReaderFontSize.values,
        json['fontSize'],
        fallback.fontSize,
      ),
      textAlign: enumByName(
        ReaderTextAlign.values,
        json['textAlign'],
        fallback.textAlign,
      ),
      pagingAxis: enumByName(
        ReaderPagingAxis.values,
        json['pagingAxis'],
        fallback.pagingAxis,
      ),
      contentDensity: enumByName(
        ContentDensity.values,
        json['contentDensity'],
        fallback.contentDensity,
      ),
      enableCardDepth:
          json['enableCardDepth'] as bool? ?? fallback.enableCardDepth,
      blueLightFilter:
          json['blueLightFilter'] as bool? ?? fallback.blueLightFilter,
      blueLightIntensity: doubleValue(
        json['blueLightIntensity'],
        fallback.blueLightIntensity,
      ),
      dimText: json['dimText'] as bool? ?? fallback.dimText,
      dimTextIntensity: doubleValue(
        json['dimTextIntensity'],
        fallback.dimTextIntensity,
      ),
      useVolumeButtonsForPaging:
          json['useVolumeButtonsForPaging'] as bool? ??
          fallback.useVolumeButtonsForPaging,
      readingInsightsEnabled:
          json['readingInsightsEnabled'] as bool? ??
          fallback.readingInsightsEnabled,
      speedReadWPM: json['speedReadWPM'] as int? ?? fallback.speedReadWPM,
      speedReadDisplayMode: enumByName(
        SpeedReadDisplayMode.values,
        json['speedReadDisplayMode'],
        fallback.speedReadDisplayMode,
      ),
      speedReadPageAdvanceMode: enumByName(
        SpeedReadPageAdvanceMode.values,
        json['speedReadPageAdvanceMode'],
        fallback.speedReadPageAdvanceMode,
      ),
      speedReadAdaptivePacing:
          json['speedReadAdaptivePacing'] as bool? ??
          fallback.speedReadAdaptivePacing,
      lineHeight: doubleValue(json['lineHeight'], fallback.lineHeight),
      paragraphSpacing: doubleValue(
        json['paragraphSpacing'],
        fallback.paragraphSpacing,
      ),
      useCustomReaderTheme:
          json['useCustomReaderTheme'] as bool? ??
          fallback.useCustomReaderTheme,
      customReaderTheme: json['customReaderTheme'] is Map
          ? CustomReaderTheme.fromJson(
              Map<String, Object?>.from(json['customReaderTheme'] as Map),
            )
          : null,
    );
  }

  Axis get resolvedPagingAxis {
    switch (pagingAxis) {
      case ReaderPagingAxis.horizontal:
        return Axis.horizontal;
      case ReaderPagingAxis.vertical:
        return Axis.vertical;
    }
  }

  // ─── Static color lookup tables (no allocations per call) ───────────
  static const _bgColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFFFAF8F5),
    AppTheme.sepia: Color(0xFFF4ECD8),
    AppTheme.newspaper: Color(0xFFEAE8E3),
    AppTheme.dark: Color(0xFF1E1E1E),
    AppTheme.amoled: Color(0xFF000000),
    AppTheme.bookLight: Color(0xFFFAF8F5),
    AppTheme.bookDark: Color(0xFF1E1E1E),
  };

  static const _menuColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFFF0EBE1),
    AppTheme.sepia: Color(0xFFE8DECA),
    AppTheme.newspaper: Color(0xFFDCDAD4),
    AppTheme.dark: Color(0xFF2C2C2C),
    AppTheme.amoled: Color(0xFF121212),
    AppTheme.bookLight: Color(0xFFF0EBE1),
    AppTheme.bookDark: Color(0xFF2C2C2C),
  };

  static const _textColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFF2C2C2C),
    AppTheme.sepia: Color(0xFF433422),
    AppTheme.newspaper: Color(0xFF1A1A1A),
    AppTheme.dark: Color(0xFFE0E0E0),
    AppTheme.amoled: Color(0xFFFFFFFF),
    AppTheme.bookLight: Color(0xFF2C2C2C),
    AppTheme.bookDark: Color(0xFFE0E0E0),
  };

  static const _mutedColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFF757575),
    AppTheme.sepia: Color(0xFF8A7967),
    AppTheme.newspaper: Color(0xFF5A5A5A),
    AppTheme.dark: Color(0xFFA0A0A0),
    AppTheme.amoled: Color(0xFF888888),
    AppTheme.bookLight: Color(0xFF757575),
    AppTheme.bookDark: Color(0xFFA0A0A0),
  };

  static const _accentColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFFE85D04), // Bright Orange
    AppTheme.sepia: Color(0xFFD84315), // Rust / Deep Orange
    AppTheme.newspaper: Color(0xFF3D3D3D), // Ink grey
    AppTheme.dark: Color(0xFFFF9100), // Amber
    AppTheme.amoled: Color(0xFFFFAB40), // Light Amber
    AppTheme.bookLight: Color(0xFFE85D04),
    AppTheme.bookDark: Color(0xFFFF9100),
  };

  ReaderThemeColors? get _bookColors {
    final theme = effectiveTheme;
    if (theme != AppTheme.bookLight && theme != AppTheme.bookDark) {
      return null;
    }
    return bookThemePalette?.colorsFor(theme);
  }

  CustomReaderTheme? get _customColors =>
      isCustomReaderThemeActive ? customReaderTheme : null;

  Color get backgroundColor =>
      _customColors?.readerBackground ??
      _bookColors?.background ??
      _bgColors[effectiveTheme]!;
  Color get cardBackgroundColor =>
      _customColors?.cardBackground ?? backgroundColor;
  Color get menuColor =>
      _customColors?.overlayBackground ??
      _customColors?.bottomDockBackground ??
      _customColors?.cardBackground ??
      _bookColors?.menu ??
      _menuColors[effectiveTheme]!;
  Color get textColor =>
      _customColors?.text ?? _bookColors?.text ?? _textColors[effectiveTheme]!;
  Color get mutedColor =>
      _customColors?.secondaryText ??
      _bookColors?.muted ??
      _mutedColors[effectiveTheme]!;
  Color get accentColor =>
      _customColors?.accent ??
      _bookColors?.accent ??
      _accentColors[effectiveTheme]!;
  Color get borderColor =>
      _customColors?.border ??
      mutedColor.withValues(alpha: isDark ? 0.22 : 0.18);
  Color get iconColor => _customColors?.icon ?? textColor;
  Color get inactiveControlColor =>
      _customColors?.inactiveControl ?? mutedColor.withValues(alpha: 0.62);
  Color get cardShadowColor =>
      _customColors?.cardShadow ??
      Colors.black.withValues(alpha: isDark ? 0.42 : 0.16);
  Color get selectionColor =>
      _customColors?.selection ?? accentColor.withValues(alpha: 0.26);
  Color get highlightDefaultColor =>
      _customColors?.highlightDefault ?? kCustomReaderDefaultHighlightColor;
  Color get bookmarkColor =>
      _customColors?.bookmark ?? kCustomReaderDefaultBookmarkColor;
  Color get topBarBackgroundColor =>
      _customColors?.topBarBackground ?? menuColor;
  Color get bottomDockBackgroundColor =>
      _customColors?.bottomDockBackground ?? menuColor;
  Color get overlayBackgroundColor =>
      _customColors?.overlayBackground ?? menuColor;
  Color get speedReadActiveWordColor =>
      _customColors?.speedReadActiveWord ?? readerTextColor;
  Color get speedReadInactiveWordColor =>
      _customColors?.speedReadInactiveWord ??
      readerTextColor.withValues(alpha: isDark ? 0.34 : 0.38);

  Color get readerTextColor => _applyReaderComfort(textColor, isMuted: false);
  Color get readerMutedColor => _applyReaderComfort(mutedColor, isMuted: true);
  Color get readerAccentColor =>
      _applyReaderComfort(accentColor, isMuted: false);

  /// Density multiplier for layout calculations.
  double get densityMultiplier {
    switch (contentDensity) {
      case ContentDensity.low:
        return 0.35;
      case ContentDensity.medium:
        return 0.55;
      case ContentDensity.high:
        return 0.75;
      case ContentDensity.fullPage:
        return 1.0;
    }
  }

  /// Resolved Flutter TextAlign value.
  TextAlign get resolvedTextAlign {
    switch (textAlign) {
      case ReaderTextAlign.center:
        return TextAlign.center;
      case ReaderTextAlign.right:
        return TextAlign.right;
      case ReaderTextAlign.justify:
        return TextAlign.justify;
      case ReaderTextAlign.left:
        return TextAlign.left;
    }
  }

  ReadingSettings copyWith({
    AppTheme? appTheme,
    AppTheme? readerTheme,
    bool clearReaderTheme = false,
    AppFontFamily? appFontFamily,
    ReaderFontFamily? fontFamily,
    ReaderFontWeight? fontWeight,
    ReaderFontSize? fontSize,
    ReaderTextAlign? textAlign,
    ReaderPagingAxis? pagingAxis,
    ContentDensity? contentDensity,
    bool? enableCardDepth,
    bool? blueLightFilter,
    double? blueLightIntensity,
    bool? dimText,
    double? dimTextIntensity,
    bool? useVolumeButtonsForPaging,
    bool? readingInsightsEnabled,
    int? speedReadWPM,
    SpeedReadDisplayMode? speedReadDisplayMode,
    SpeedReadPageAdvanceMode? speedReadPageAdvanceMode,
    bool? speedReadAdaptivePacing,
    double? lineHeight,
    double? paragraphSpacing,
    BookReaderThemePalette? bookThemePalette,
    bool clearBookThemePalette = false,
    bool? useCustomReaderTheme,
    CustomReaderTheme? customReaderTheme,
    bool clearCustomReaderTheme = false,
  }) {
    return ReadingSettings(
      appTheme: appTheme ?? this.appTheme,
      readerTheme: clearReaderTheme ? null : (readerTheme ?? this.readerTheme),
      appFontFamily: appFontFamily ?? this.appFontFamily,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontSize: fontSize ?? this.fontSize,
      textAlign: textAlign ?? this.textAlign,
      pagingAxis: pagingAxis ?? this.pagingAxis,
      contentDensity: contentDensity ?? this.contentDensity,
      enableCardDepth: enableCardDepth ?? this.enableCardDepth,
      blueLightFilter: blueLightFilter ?? this.blueLightFilter,
      blueLightIntensity: blueLightIntensity ?? this.blueLightIntensity,
      dimText: dimText ?? this.dimText,
      dimTextIntensity: dimTextIntensity ?? this.dimTextIntensity,
      useVolumeButtonsForPaging:
          useVolumeButtonsForPaging ?? this.useVolumeButtonsForPaging,
      readingInsightsEnabled:
          readingInsightsEnabled ?? this.readingInsightsEnabled,
      speedReadWPM: speedReadWPM ?? this.speedReadWPM,
      speedReadDisplayMode: speedReadDisplayMode ?? this.speedReadDisplayMode,
      speedReadPageAdvanceMode:
          speedReadPageAdvanceMode ?? this.speedReadPageAdvanceMode,
      speedReadAdaptivePacing:
          speedReadAdaptivePacing ?? this.speedReadAdaptivePacing,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      bookThemePalette: clearBookThemePalette
          ? null
          : (bookThemePalette ?? this.bookThemePalette),
      useCustomReaderTheme: useCustomReaderTheme ?? this.useCustomReaderTheme,
      customReaderTheme: clearCustomReaderTheme
          ? null
          : (customReaderTheme ?? this.customReaderTheme),
    );
  }

  TextStyle getTextStyle({bool isHeading = false}) {
    final fSize = fontSizeValue;
    final fWeight = fontWeightValue;
    final color = readerTextColor;

    final baseStyle = TextStyle(
      fontSize: isHeading ? fSize + (14 * fontSizeMultiplier) : fSize,
      fontWeight: isHeading ? FontWeight.w900 : fWeight,
      height: isHeading ? headingLineHeight : lineHeight,
      color: color,
      letterSpacing: isHeading ? 2.0 : 0,
    );

    switch (fontFamily) {
      case ReaderFontFamily.inter:
        return GoogleFonts.inter(textStyle: baseStyle);
      case ReaderFontFamily.robotoMono:
        return GoogleFonts.robotoMono(textStyle: baseStyle);
      case ReaderFontFamily.merriweather:
        return GoogleFonts.merriweather(textStyle: baseStyle);
      case ReaderFontFamily.lora:
        return GoogleFonts.lora(textStyle: baseStyle);
      case ReaderFontFamily.ebGaramond:
        return GoogleFonts.ebGaramond(textStyle: baseStyle);
      case ReaderFontFamily.literata:
        return GoogleFonts.literata(textStyle: baseStyle);
      case ReaderFontFamily.atkinsonHyperlegible:
        return GoogleFonts.atkinsonHyperlegible(textStyle: baseStyle);
      case ReaderFontFamily.lexend:
        return GoogleFonts.lexend(textStyle: baseStyle);
    }
  }

  TextStyle getAppTextStyle(TextStyle baseStyle) {
    return GoogleFonts.getFont(
      appFontFamily.googleFontName,
      textStyle: baseStyle,
    );
  }

  TextStyle uiText({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    TextBaseline? textBaseline,
    double? height,
    Locale? locale,
    Paint? foreground,
    Paint? background,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
  }) {
    return GoogleFonts.getFont(
      appFontFamily.googleFontName,
      textStyle: textStyle,
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      textBaseline: textBaseline,
      height: height,
      locale: locale,
      foreground: foreground,
      background: background,
      shadows: shadows,
      fontFeatures: fontFeatures,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
    );
  }

  TextTheme getAppTextTheme(TextTheme baseTheme) {
    return GoogleFonts.getTextTheme(appFontFamily.googleFontName, baseTheme);
  }

  double get fontSizeMultiplier {
    switch (fontFamily) {
      case ReaderFontFamily.inter:
        return 0.95; // Large x-height
      case ReaderFontFamily.robotoMono:
        return 0.95; // Large x-height monospaced
      case ReaderFontFamily.merriweather:
        return 1.0; // Sturdy baseline
      case ReaderFontFamily.lora:
        return 1.05; // Slightly condensed
      case ReaderFontFamily.ebGaramond:
        return 1.25; // Small x-height, needs significant scaling
      case ReaderFontFamily.literata:
        return 1.0; // Baseline
      case ReaderFontFamily.atkinsonHyperlegible:
        return 0.95; // Designed for high legibility, slightly larger visual glyphs
      case ReaderFontFamily.lexend:
        return 1.0; // Pretty accurately sized standard
    }
  }

  double get fontSizeValue {
    double baseSize;
    switch (fontSize) {
      case ReaderFontSize.xs:
        baseSize = 14.0;
        break;
      case ReaderFontSize.s:
        baseSize = 16.0;
        break;
      case ReaderFontSize.m:
        baseSize = 18.0;
        break;
      case ReaderFontSize.l:
        baseSize = 22.0;
        break;
      case ReaderFontSize.xl:
        baseSize = 26.0;
        break;
    }
    return baseSize * fontSizeMultiplier;
  }

  FontWeight get fontWeightValue {
    switch (fontWeight) {
      case ReaderFontWeight.light:
        return FontWeight.w300;
      case ReaderFontWeight.regular:
        return FontWeight.w400;
      case ReaderFontWeight.medium:
        return FontWeight.w500;
      case ReaderFontWeight.semiBold:
        return FontWeight.w600;
      case ReaderFontWeight.bold:
        return FontWeight.w700;
    }
  }

  StrutStyle getBodyStrutStyle() {
    return StrutStyle(
      fontFamily: getTextStyle().fontFamily,
      fontSize: fontSizeValue,
      height: lineHeight,
      forceStrutHeight: true,
      leading: 0,
    );
  }

  StrutStyle getHeadingStrutStyle() {
    final headingStyle = getTextStyle(isHeading: true);
    return StrutStyle(
      fontFamily: headingStyle.fontFamily,
      fontSize: headingStyle.fontSize,
      fontWeight: headingStyle.fontWeight,
      height: headingLineHeight,
      forceStrutHeight: true,
      leading: 0,
    );
  }

  Color _applyReaderComfort(Color color, {required bool isMuted}) {
    var result = color;

    if (dimText) {
      final intensity = dimTextIntensity.clamp(0.0, 0.5);
      final dimTarget = isDark
          ? Color(isMuted ? 0xFF7F858D : 0xFFADB4BD)
          : Color(isMuted ? 0xFF737373 : 0xFF5C5C5C);
      final dimBlend = (0.216 + (intensity * 1.15)).clamp(0.216, 0.64);
      result = Color.lerp(result, dimTarget, dimBlend) ?? result;
    }

    if (blueLightFilter) {
      final warmTarget = isDark
          ? const Color(0xFFFFC07A)
          : const Color(0xFF8B4B12);
      final warmth = (0.18 + (blueLightIntensity.clamp(0.0, 0.5) * 0.72)).clamp(
        0.18,
        0.54,
      );
      result = Color.lerp(result, warmTarget, warmth) ?? result;
    }

    return result;
  }
}
