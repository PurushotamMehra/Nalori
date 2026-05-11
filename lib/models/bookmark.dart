import 'dart:convert';

import 'package:flutter/material.dart';

/// 5 predefined bookmark colors.
/// Index 0 is the default (Instagram pink).
const List<Color> kBookmarkColors = [
  Color(0xFFE1306C), // Pink (default — matches the original kBookmarkPink)
  Color(0xFF4FC3F7), // Sky Blue
  Color(0xFFFFB74D), // Amber / Orange
  Color(0xFF81C784), // Green
  Color(0xFFCE93D8), // Lavender / Purple
];

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

  Bookmark({
    required this.chunkIndex,
    required this.name,
    this.originalStartOffset = 0,
    DateTime? createdAt,
    this.previewText,
    this.colorIndex = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Resolved color from the palette.
  Color get color => kBookmarkColors[colorIndex % kBookmarkColors.length];

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
  }) {
    return Bookmark(
      chunkIndex: chunkIndex ?? this.chunkIndex,
      originalStartOffset: originalStartOffset ?? this.originalStartOffset,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      previewText: previewText ?? this.previewText,
      colorIndex: colorIndex ?? this.colorIndex,
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
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    chunkIndex: json['chunkIndex'] as int,
    originalStartOffset: (json['originalStartOffset'] as int?) ?? 0,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    previewText: json['previewText'] as String?,
    colorIndex: (json['colorIndex'] as int?) ?? 0,
  );

  static String encodeList(List<Bookmark> list) =>
      jsonEncode(list.map((b) => b.toJson()).toList());

  static List<Bookmark> decodeList(String json) => (jsonDecode(json) as List)
      .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
      .toList();
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
