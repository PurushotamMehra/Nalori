import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

@immutable
class CoverPalette {
  final Color primary;
  final Color secondary;

  const CoverPalette({required this.primary, required this.secondary});
}

class CoverPaletteService {
  Future<CoverPalette?> loadPalette(String? coverImagePath) async {
    if (coverImagePath == null || coverImagePath.trim().isEmpty) return null;

    final file = File(coverImagePath);
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final byteData = await image.toByteData();
        if (byteData == null) return null;

        return paletteFromPixels(
          byteData.buffer.asUint8List(),
          image.width,
          image.height,
        );
      } finally {
        image.dispose();
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  CoverPalette? paletteFromPixels(Uint8List bytes, int width, int height) {
    final colors = sampleColors(bytes, width, height);
    if (colors.isEmpty) return null;

    final primary = pickPrimary(colors);
    final secondary = pickSecondary(colors, primary);
    return CoverPalette(primary: primary, secondary: secondary);
  }

  @visibleForTesting
  List<Color> sampleColors(Uint8List bytes, int width, int height) {
    final colors = <Color>[];
    final stepX = math.max(1, width ~/ 10);
    final stepY = math.max(1, height ~/ 10);

    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final index = (y * width + x) * 4;
        if (index + 3 >= bytes.length) continue;
        final r = bytes[index];
        final g = bytes[index + 1];
        final b = bytes[index + 2];
        final a = bytes[index + 3];
        if (a < 200) continue;
        final color = Color.fromARGB(a, r, g, b);
        final hsv = HSVColor.fromColor(color);
        if (hsv.value < 0.08 || hsv.value > 0.96) continue;
        colors.add(color);
      }
    }

    return colors;
  }

  @visibleForTesting
  Color pickPrimary(List<Color> colors) {
    return rankedColorClusters(colors).first.color;
  }

  @visibleForTesting
  Color pickSecondary(List<Color> colors, Color primary) {
    final primaryHue = HSVColor.fromColor(primary).hue;

    for (final cluster in rankedColorClusters(colors)) {
      final color = cluster.color;
      final hueDistance = this.hueDistance(
        primaryHue,
        HSVColor.fromColor(color).hue,
      );
      if (hueDistance >= 28) return color;
    }

    final primaryHsv = HSVColor.fromColor(primary);
    return primaryHsv
        .withHue((primaryHsv.hue + 42) % 360)
        .withSaturation((primaryHsv.saturation + 0.18).clamp(0.0, 1.0))
        .toColor();
  }

  @visibleForTesting
  double colorScore(Color color) {
    final hsv = HSVColor.fromColor(color);
    final balancedValue = 1 - (hsv.value - 0.55).abs();
    return hsv.saturation * 2.4 + balancedValue;
  }

  @visibleForTesting
  List<ColorCluster> rankedColorClusters(List<Color> colors) {
    final clusters = <String, ColorCluster>{};

    for (final color in colors) {
      final hsv = HSVColor.fromColor(color);
      final key =
          '${(hsv.hue / 18).floor()}-'
          '${(hsv.saturation / 0.16).floor()}-'
          '${(hsv.value / 0.16).floor()}';
      final existing = clusters[key];
      if (existing == null) {
        clusters[key] = ColorCluster(color: color, count: 1, score: 0);
        continue;
      }

      final existingColorScore = colorScore(existing.color);
      final nextColorScore = colorScore(color);
      clusters[key] = ColorCluster(
        color: nextColorScore > existingColorScore ? color : existing.color,
        count: existing.count + 1,
        score: 0,
      );
    }

    final ranked = clusters.values.map((cluster) {
      final hsv = HSVColor.fromColor(cluster.color);
      final dominance = math.sqrt(cluster.count);
      final vibrance = 0.72 + hsv.saturation;
      return ColorCluster(
        color: cluster.color,
        count: cluster.count,
        score: dominance * vibrance + colorScore(cluster.color),
      );
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    return ranked;
  }

  @visibleForTesting
  double hueDistance(double a, double b) {
    final diff = (a - b).abs();
    return math.min(diff, 360 - diff);
  }
}

@visibleForTesting
@immutable
class ColorCluster {
  final Color color;
  final int count;
  final double score;

  const ColorCluster({
    required this.color,
    required this.count,
    required this.score,
  });
}
