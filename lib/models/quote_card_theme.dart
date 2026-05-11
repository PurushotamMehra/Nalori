import 'package:flutter/material.dart';

@immutable
class QuoteCardTheme {
  final String name;
  final List<Color> backgroundColors;
  final Color quoteColor;
  final Color metadataColor;
  final Color logoColor;
  final Color accentColor;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  const QuoteCardTheme({
    required this.name,
    required this.backgroundColors,
    required this.quoteColor,
    required this.metadataColor,
    required this.logoColor,
    required this.accentColor,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  /// True when every background color is the same (e.g. pure AMOLED black).
  bool get isSolidColor {
    if (backgroundColors.isEmpty) return false;
    final first = backgroundColors.first;
    return backgroundColors.every((c) => c.toARGB32() == first.toARGB32());
  }

  LinearGradient get gradient {
    return LinearGradient(
      begin: begin,
      end: end,
      colors: backgroundColors.length >= 2
          ? backgroundColors
          : const [Color(0xFF111111), Color(0xFF000000)],
    );
  }
}
