import 'dart:convert';

import 'package:flutter/material.dart';

/// Predefined bookmark colors.
/// Index 0 is the default (Instagram pink).
const List<Color> kBookmarkColors = [
  Color(0xFFE1306C), // Pink (default — matches the original kBookmarkPink)
  Color(0xFF4FC3F7), // Sky Blue
  Color(0xFFFFB74D), // Amber / Orange
  Color(0xFF81C784), // Green
  Color(0xFFCE93D8), // Lavender / Purple
  Color(0xFFFF6B6B), // Coral
  Color(0xFFFFD166), // Warm Yellow
  Color(0xFF06D6A0), // Mint
  Color(0xFF2EC4B6), // Teal
  Color(0xFF118AB2), // Ocean Blue
  Color(0xFF5E60CE), // Indigo
  Color(0xFF9D4EDD), // Violet
  Color(0xFFF72585), // Magenta
  Color(0xFF8D6E63), // Cocoa
  Color(0xFF607D8B), // Blue Grey
];

int bookmarkColorValue(Color color) => Color(color.toARGB32()).toARGB32();

bool isSameBookmarkColor(Color a, Color b) =>
    bookmarkColorValue(a) == bookmarkColorValue(b);

int? defaultBookmarkColorIndex(Color color) {
  final normalized = bookmarkColorValue(color);
  for (int i = 0; i < kBookmarkColors.length; i++) {
    if (bookmarkColorValue(kBookmarkColors[i]) == normalized) return i;
  }
  return null;
}

String bookmarkColorHex(Color color) {
  final rgb = bookmarkColorValue(color) & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? parseBookmarkHexColor(String input) {
  final normalized = input.trim().replaceAll('#', '');
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)) return null;
  return Color(int.parse('FF$normalized', radix: 16));
}

/// A user-created bookmark pointing to a specific card in the book.
@immutable
class Bookmark {
  final int chunkIndex;
  final int originalStartOffset;
  final String name;
  final DateTime createdAt;
  final String? previewText;

  /// Index into [kBookmarkColors]. Defaults to 0 (pink).
  final int colorIndex;

  /// Stable ARGB color value for arbitrary custom bookmark colors.
  final int? colorValue;

  Bookmark({
    required this.chunkIndex,
    required this.name,
    this.originalStartOffset = 0,
    DateTime? createdAt,
    this.previewText,
    this.colorIndex = 0,
    this.colorValue,
  }) : createdAt = createdAt ?? DateTime.now();

  int get resolvedColorValue =>
      colorValue ??
      bookmarkColorValue(kBookmarkColors[colorIndex % kBookmarkColors.length]);

  /// Resolved color from the custom value or palette.
  Color get color => Color(resolvedColorValue);

  String get locationKey => '$chunkIndex:$originalStartOffset';

  bool isSameLocation(int chunkIndex, int originalStartOffset) {
    return this.chunkIndex == chunkIndex &&
        this.originalStartOffset == originalStartOffset;
  }

  Bookmark copyWith({
    int? chunkIndex,
    int? originalStartOffset,
    String? name,
    DateTime? createdAt,
    String? previewText,
    int? colorIndex,
    int? colorValue,
    bool clearColorValue = false,
  }) {
    return Bookmark(
      chunkIndex: chunkIndex ?? this.chunkIndex,
      originalStartOffset: originalStartOffset ?? this.originalStartOffset,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      previewText: previewText ?? this.previewText,
      colorIndex: colorIndex ?? this.colorIndex,
      colorValue: clearColorValue ? null : colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
    'chunkIndex': chunkIndex,
    'originalStartOffset': originalStartOffset,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    if (previewText != null && previewText!.isNotEmpty)
      'previewText': previewText,
    'colorIndex': colorIndex,
    if (colorValue != null) 'colorValue': colorValue,
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    chunkIndex: json['chunkIndex'] as int,
    originalStartOffset: (json['originalStartOffset'] as int?) ?? 0,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    previewText: json['previewText'] as String?,
    colorIndex: (json['colorIndex'] as int?) ?? 0,
    colorValue: _parseColorValue(json['colorValue'] ?? json['color']),
  );

  static String encodeList(List<Bookmark> list) =>
      jsonEncode(list.map((b) => b.toJson()).toList());

  static List<Bookmark> decodeList(String json) => (jsonDecode(json) as List)
      .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
      .toList();
}

int? _parseColorValue(Object? raw) {
  if (raw is int) return bookmarkColorValue(Color(raw));
  if (raw is String) {
    final parsed = parseBookmarkHexColor(raw);
    if (parsed != null) return bookmarkColorValue(parsed);
    final numeric = int.tryParse(raw);
    if (numeric != null) return bookmarkColorValue(Color(numeric));
  }
  return null;
}

/// Chapter/section metadata from the EPUB Table of Contents.
///
/// Supports arbitrary nesting: Part → Chapter → Section → …
@immutable
class ChapterInfo {
  final String title;
  final int chunkIndex;

  /// 0 = top-level (e.g. "Part I"), 1 = chapter, 2 = sub-section, etc.
  final int depth;

  /// Optional children for UI hierarchy rendering.
  final List<ChapterInfo> children;

  const ChapterInfo({
    required this.title,
    required this.chunkIndex,
    this.depth = 0,
    this.children = const [],
  });

  Map<String, dynamic> toJson() => {
    't': title,
    'ci': chunkIndex,
    'd': depth,
    if (children.isNotEmpty) 'ch': children.map((c) => c.toJson()).toList(),
  };

  factory ChapterInfo.fromJson(Map<String, dynamic> json) => ChapterInfo(
    title: json['t'] as String,
    chunkIndex: json['ci'] as int,
    depth: json['d'] as int? ?? 0,
    children: json['ch'] != null
        ? (json['ch'] as List)
              .map((e) => ChapterInfo.fromJson(e as Map<String, dynamic>))
              .toList()
        : const [],
  );
}
