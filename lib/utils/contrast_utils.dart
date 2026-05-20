import 'package:flutter/material.dart';

const Color kCalmLightForeground = Color(0xFFFAF7F0);
const Color kCalmDarkForeground = Color(0xFF171512);

double contrastRatio(Color foreground, Color background) {
  final fg = foreground.computeLuminance();
  final bg = background.computeLuminance();
  final lighter = fg > bg ? fg : bg;
  final darker = fg > bg ? bg : fg;
  return (lighter + 0.05) / (darker + 0.05);
}

Color readableForegroundForBackground(
  Color background, {
  Color lightForeground = kCalmLightForeground,
  Color darkForeground = kCalmDarkForeground,
  double minContrast = 4.5,
}) {
  final lightRatio = contrastRatio(lightForeground, background);
  final darkRatio = contrastRatio(darkForeground, background);

  if (lightRatio >= minContrast || darkRatio >= minContrast) {
    return lightRatio > darkRatio ? lightForeground : darkForeground;
  }

  final whiteRatio = contrastRatio(Colors.white, background);
  final blackRatio = contrastRatio(Colors.black, background);
  return whiteRatio > blackRatio ? Colors.white : Colors.black;
}

Color compositeColorOver(Color foreground, Color background) {
  final alpha = foreground.a;
  if (alpha >= 1) return foreground;
  if (alpha <= 0) return background;

  return Color.from(
    alpha: 1,
    red: foreground.r * alpha + background.r * (1 - alpha),
    green: foreground.g * alpha + background.g * (1 - alpha),
    blue: foreground.b * alpha + background.b * (1 - alpha),
  );
}
