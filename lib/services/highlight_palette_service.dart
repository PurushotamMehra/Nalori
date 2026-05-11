import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/highlight.dart';

class HighlightPaletteService {
  static const String _activePaletteKey = 'active_highlight_palette';
  static const String _customColorsKey = 'custom_highlight_colors';
  static const String _defaultColorKey = 'default_highlight_color';
  static const int maxHighlightColors = 25;

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _cachedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<List<Color>> loadPalette() async {
    final prefs = await _cachedPrefs;
    final rawPalette = prefs.getStringList(_activePaletteKey);
    final savedPalette = _parsePalette(rawPalette ?? const []);
    if (savedPalette.isNotEmpty) return savedPalette;

    final migratedPalette = _buildLegacyPalette(prefs);
    await _savePalette(migratedPalette);
    return migratedPalette;
  }

  List<Color> _buildLegacyPalette(SharedPreferences prefs) {
    final rawColors = prefs.getStringList(_customColorsKey) ?? const [];
    final customColors = _parsePalette(rawColors);
    final seen = <int>{...customColors.map(highlightColorValue)};
    final palette = <Color>[...customColors];

    for (final color in kHighlightColors) {
      final normalized = highlightColorValue(color);
      if (!seen.add(normalized)) continue;
      palette.add(Color(normalized));
      if (palette.length >= maxHighlightColors) break;
    }

    return palette.isEmpty
        ? kHighlightColors
              .map((color) => Color(highlightColorValue(color)))
              .toList()
        : palette;
  }

  List<Color> _parsePalette(List<String> rawColors) {
    final colors = <Color>[];
    final seen = <int>{};

    for (final raw in rawColors) {
      final parsed = parseHighlightHexColor(raw);
      if (parsed == null) continue;
      final normalized = highlightColorValue(parsed);
      if (!seen.add(normalized)) continue;
      colors.add(Color(normalized));
      if (colors.length >= maxHighlightColors) break;
    }

    return colors;
  }

  Future<Color> loadDefaultColor() async {
    final prefs = await _cachedPrefs;
    final raw = prefs.getInt(_defaultColorKey);
    if (raw != null) return Color(raw);
    return kHighlightColors.last;
  }

  Future<void> saveDefaultColor(Color color) async {
    final prefs = await _cachedPrefs;
    await prefs.setInt(_defaultColorKey, highlightColorValue(color));
  }

  Future<List<Color>> addColor(Color color) async {
    final normalized = Color(highlightColorValue(color));
    final palette = await loadPalette();

    if (palette.any((entry) => isSameHighlightColor(entry, normalized)) ||
        palette.length >= maxHighlightColors) {
      return palette;
    }

    final updatedPalette = <Color>[normalized, ...palette];
    await _savePalette(updatedPalette);
    return updatedPalette;
  }

  Future<List<Color>> removeColor(Color color) async {
    final palette = await loadPalette();
    if (palette.length <= 1) return palette;

    final updatedPalette = palette
        .where((entry) => !isSameHighlightColor(entry, color))
        .map((entry) => Color(highlightColorValue(entry)))
        .toList();

    if (updatedPalette.length == palette.length || updatedPalette.isEmpty) {
      return palette;
    }

    await _savePalette(updatedPalette);
    return updatedPalette;
  }

  Future<List<Color>> resetPalette() async {
    final systemPalette = kHighlightColors
        .map((color) => Color(highlightColorValue(color)))
        .toList();
    await _savePalette(systemPalette);
    return systemPalette;
  }

  Future<List<Color>> addCustomColor(Color color) => addColor(color);

  Future<List<Color>> removeCustomColor(Color color) => removeColor(color);

  Future<void> _savePalette(List<Color> palette) async {
    final prefs = await _cachedPrefs;
    final limited = <Color>[];
    final seen = <int>{};

    for (final color in palette) {
      final normalized = Color(highlightColorValue(color));
      if (!seen.add(highlightColorValue(normalized))) continue;
      limited.add(normalized);
      if (limited.length >= maxHighlightColors) break;
    }

    if (limited.isEmpty) {
      limited.addAll(
        kHighlightColors.map((color) => Color(highlightColorValue(color))),
      );
    }

    await prefs.setStringList(
      _activePaletteKey,
      limited.map(highlightColorHex).toList(),
    );
  }
}

String highlightColorHex(Color color) {
  final rgb = highlightColorValue(color) & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? parseHighlightHexColor(String input) {
  final normalized = input.trim().replaceAll('#', '');
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)) return null;
  return Color(int.parse('FF$normalized', radix: 16));
}
