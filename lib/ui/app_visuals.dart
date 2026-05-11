import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/reading_settings.dart';

abstract final class AppBrand {
  static const String name = 'Nalori';
  static const String logoAsset = 'assets/images/nalori_mark.svg';
  static const String appIconAsset = 'assets/images/nalori_app_icon.png';
}

class BrandMark extends StatelessWidget {
  final double size;
  final Color? color;
  final BoxFit fit;

  const BrandMark({
    super.key,
    required this.size,
    this.color,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      AppBrand.logoAsset,
      width: size,
      height: size,
      fit: fit,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}

abstract final class AppUi {
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 24;

  static BorderRadius cardRadius([double radius = radiusLg]) =>
      BorderRadius.circular(radius);

  static RoundedRectangleBorder shape([double radius = radiusLg]) =>
      RoundedRectangleBorder(borderRadius: cardRadius(radius));

  static Color foregroundFor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }

  static ThemeData appTheme(ReadingSettings settings) {
    final appSettings = settings.copyWith(useCustomReaderTheme: false);
    final base = appSettings.isDark ? ThemeData.dark() : ThemeData.light();
    final textTheme = appSettings
        .getAppTextTheme(base.textTheme)
        .apply(
          bodyColor: appSettings.textColor,
          displayColor: appSettings.textColor,
        );
    final onAccent = foregroundFor(appSettings.accentColor);

    return base.copyWith(
      scaffoldBackgroundColor: appSettings.backgroundColor,
      canvasColor: appSettings.backgroundColor,
      cardColor: appSettings.menuColor,
      textTheme: textTheme,
      colorScheme: base.colorScheme.copyWith(
        primary: appSettings.accentColor,
        onPrimary: onAccent,
        secondary: appSettings.accentColor,
        onSecondary: onAccent,
        surface: appSettings.menuColor,
        onSurface: appSettings.textColor,
        onSurfaceVariant: appSettings.mutedColor,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: appSettings.backgroundColor,
        foregroundColor: appSettings.textColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: appSettings.menuColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: appSettings.menuColor,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: appSettings.menuColor,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: appSettings.textColor,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: appSettings.backgroundColor,
        ),
        actionTextColor: appSettings.accentColor,
        behavior: SnackBarBehavior.floating,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: appSettings.accentColor),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: appSettings.textColor,
          side: BorderSide(
            color: appSettings.mutedColor.withValues(alpha: 0.22),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: appSettings.accentColor,
          foregroundColor: onAccent,
        ),
      ),
      switchTheme: base.switchTheme.copyWith(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return appSettings.accentColor;
          }
          return appSettings.mutedColor;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return appSettings.accentColor.withValues(alpha: 0.32);
          }
          return appSettings.mutedColor.withValues(alpha: 0.22);
        }),
      ),
    );
  }

  static ThemeData readerTheme(ReadingSettings settings) {
    final base = settings.isDark ? ThemeData.dark() : ThemeData.light();
    final textTheme = settings
        .getAppTextTheme(base.textTheme)
        .apply(bodyColor: settings.textColor, displayColor: settings.textColor);
    final mutedSurface = settings.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final dividerColor = settings.mutedColor.withValues(
      alpha: settings.isDark ? 0.22 : 0.18,
    );
    final onAccent = foregroundFor(settings.accentColor);

    return base.copyWith(
      scaffoldBackgroundColor: settings.backgroundColor,
      canvasColor: settings.backgroundColor,
      cardColor: settings.menuColor,
      dividerColor: dividerColor,
      textTheme: textTheme,
      iconTheme: base.iconTheme.copyWith(color: settings.textColor),
      colorScheme: base.colorScheme.copyWith(
        primary: settings.accentColor,
        onPrimary: onAccent,
        secondary: settings.accentColor,
        onSecondary: onAccent,
        surface: settings.menuColor,
        onSurface: settings.textColor,
        surfaceContainerHighest: mutedSurface,
        onSurfaceVariant: settings.mutedColor,
        inverseSurface: settings.textColor,
        onInverseSurface: settings.backgroundColor,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: settings.menuColor,
        foregroundColor: settings.textColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: settings.menuColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: settings.menuColor,
        modalBarrierColor: Colors.black54,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: settings.menuColor,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: base.dividerTheme.copyWith(color: dividerColor),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: mutedSurface,
        selectedColor: settings.accentColor.withValues(alpha: 0.18),
        secondarySelectedColor: settings.accentColor.withValues(alpha: 0.18),
        labelStyle: textTheme.labelLarge?.copyWith(color: settings.textColor),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: settings.textColor,
        ),
        brightness: settings.isDark ? Brightness.dark : Brightness.light,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: mutedSurface,
        labelStyle: TextStyle(color: settings.mutedColor),
        hintStyle: TextStyle(color: settings.mutedColor),
        prefixIconColor: settings.mutedColor,
        suffixIconColor: settings.mutedColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: cardRadius(radiusMd),
          borderSide: BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: cardRadius(radiusMd),
          borderSide: BorderSide(color: settings.accentColor, width: 1.4),
        ),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: settings.textColor,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: settings.backgroundColor,
        ),
        actionTextColor: settings.accentColor,
        behavior: SnackBarBehavior.floating,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: settings.accentColor,
        thumbColor: settings.accentColor,
        overlayColor: settings.accentColor.withValues(alpha: 0.12),
        inactiveTrackColor: settings.mutedColor.withValues(alpha: 0.24),
      ),
      switchTheme: base.switchTheme.copyWith(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return settings.accentColor;
          }
          return settings.mutedColor;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return settings.accentColor.withValues(alpha: 0.32);
          }
          return settings.mutedColor.withValues(alpha: 0.22);
        }),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: settings.accentColor),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: settings.textColor,
          side: BorderSide(color: dividerColor),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: settings.accentColor,
          foregroundColor: onAccent,
          disabledBackgroundColor: settings.mutedColor.withValues(alpha: 0.18),
          disabledForegroundColor: settings.mutedColor,
        ),
      ),
    );
  }

  static BoxDecoration surfaceCard(
    ReadingSettings settings, {
    bool prominent = false,
    double radius = radiusLg,
  }) {
    final isDark = settings.isDark;
    final topTint = isDark
        ? Colors.white.withValues(alpha: prominent ? 0.05 : 0.035)
        : Colors.white.withValues(alpha: prominent ? 0.88 : 0.78);
    final baseColor = settings.menuColor;
    final borderColor = settings.mutedColor.withValues(
      alpha: isDark ? 0.16 : 0.09,
    );
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: prominent ? 0.32 : 0.22)
        : const Color(0xFF2C1906).withValues(alpha: prominent ? 0.14 : 0.08);

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.alphaBlend(topTint, baseColor), baseColor],
      ),
      borderRadius: cardRadius(radius),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: shadowColor,
          blurRadius: prominent ? 24 : 18,
          offset: Offset(0, prominent ? 12 : 8),
        ),
      ],
    );
  }

  static BoxDecoration accentPill(ReadingSettings settings) {
    return BoxDecoration(
      color: settings.accentColor.withValues(alpha: 0.1),
      borderRadius: cardRadius(radiusSm),
      border: Border.all(color: settings.accentColor.withValues(alpha: 0.16)),
    );
  }

  static BoxDecoration neutralPill(ReadingSettings settings) {
    return BoxDecoration(
      color: settings.menuColor.withValues(alpha: settings.isDark ? 0.94 : 0.9),
      borderRadius: cardRadius(radiusSm),
      border: Border.all(color: settings.mutedColor.withValues(alpha: 0.14)),
    );
  }

  static List<BoxShadow> readerCardShadows(
    ReadingSettings settings, {
    bool sideShadow = false,
  }) {
    final isDark = settings.isDark;
    final mainOffset = sideShadow ? const Offset(18, 4) : const Offset(0, 18);
    return [
      BoxShadow(
        color: settings.cardShadowColor,
        blurRadius: 30,
        offset: mainOffset,
      ),
      BoxShadow(
        color: isDark
            ? Colors.white.withValues(alpha: 0.028)
            : Colors.white.withValues(alpha: 0.44),
        blurRadius: 1,
        spreadRadius: 1,
        offset: sideShadow ? const Offset(-1, 0) : const Offset(0, -1),
      ),
    ];
  }
}
