import 'dart:convert';

import 'package:flutter/material.dart';

import 'stable_book_location.dart';

enum HighlightType { highlight, character, note }

/// Available highlight colors.
const List<Color> kHighlightColors = [
  Color(0xFFFFD54F), // Yellow (default)
  Color(0xFF81C784), // Green
  Color(0xFFFF8A65), // Orange
  Color(0xFFCE93D8), // Purple
  Color(0xFFEF5350), // Red
];

/// Legacy color constant for character highlight UI indicators (icon tinting, etc.).
/// Character highlights now use the standard [kHighlightColors] palette via [colorIndex].
const Color kCharacterHighlightColor = Color(0xFF64B5F6); // Blue

int highlightColorValue(Color color) => Color(color.toARGB32()).toARGB32();

bool isSameHighlightColor(Color a, Color b) =>
    highlightColorValue(a) == highlightColorValue(b);

bool isDefaultHighlightColor(Color color) =>
    defaultHighlightColorIndex(color) != null;

int? defaultHighlightColorIndex(Color color) {
  final normalized = highlightColorValue(color);
  for (int i = 0; i < kHighlightColors.length; i++) {
    if (highlightColorValue(kHighlightColors[i]) == normalized) return i;
  }
  return null;
}

/// A single text highlight stored against an original chunk.
@immutable
class Highlight {
  static const Object _unsetNote = Object();
  static const Object _unsetColorValue = Object();

  /// Unique ID for this highlight.
  final String id;

  /// The original chunk index this highlight belongs to.
  final int originalChunkIndex;

  /// Character offset within the chunk's text where highlight starts.
  final int startOffset;

  /// Character offset within the chunk's text where highlight ends.
  final int endOffset;

  /// The actual highlighted text (stored for display in the panel).
  final String text;

  /// Highlight color index into [kHighlightColors].
  final int colorIndex;

  /// Stable ARGB color value used for custom palettes and migrations.
  final int? colorValue;

  /// Semantic annotation type.
  final HighlightType type;

  /// Creation timestamp.
  final DateTime createdAt;

  /// User-authored note text for note annotations.
  final String? note;
  final StableBookLocation? stableLocation;

  const Highlight({
    required this.id,
    required this.originalChunkIndex,
    required this.startOffset,
    required this.endOffset,
    required this.text,
    this.colorIndex = 0,
    this.colorValue,
    this.type = HighlightType.highlight,
    required this.createdAt,
    this.note,
    this.stableLocation,
  });

  bool get isCharacter => type == HighlightType.character;
  bool get isNote => type == HighlightType.note;
  bool get isRegularHighlight => type == HighlightType.highlight;
  bool get hasNote => note != null && note!.isNotEmpty;

  int get resolvedColorValue =>
      colorValue ??
      highlightColorValue(
        kHighlightColors[colorIndex % kHighlightColors.length],
      );

  Color get color => Color(resolvedColorValue);

  Highlight copyWith({
    int? originalChunkIndex,
    int? startOffset,
    int? endOffset,
    String? text,
    int? colorIndex,
    Object? colorValue = _unsetColorValue,
    HighlightType? type,
    Object? note = _unsetNote,
    StableBookLocation? stableLocation,
  }) {
    return Highlight(
      id: id,
      originalChunkIndex: originalChunkIndex ?? this.originalChunkIndex,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset,
      text: text ?? this.text,
      colorIndex: colorIndex ?? this.colorIndex,
      colorValue: identical(colorValue, _unsetColorValue)
          ? this.colorValue
          : colorValue as int?,
      type: type ?? this.type,
      createdAt: createdAt,
      note: identical(note, _unsetNote) ? this.note : note as String?,
      stableLocation: stableLocation ?? this.stableLocation,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ci': originalChunkIndex,
    'so': startOffset,
    'eo': endOffset,
    'tx': text,
    'co': colorIndex,
    if (colorValue != null) 'cv': colorValue,
    'tp': type.index,
    'ca': createdAt.toIso8601String(),
    if (note != null) 'nt': note,
    if (stableLocation != null) 'loc': stableLocation!.toJson(),
  };

  factory Highlight.fromJson(Map<String, dynamic> json) => Highlight(
    id: json['id'] as String,
    originalChunkIndex: json['ci'] as int,
    startOffset: json['so'] as int,
    endOffset: json['eo'] as int,
    text: json['tx'] as String,
    colorIndex: (json['co'] as int?) ?? 0,
    colorValue: json['cv'] as int?,
    type: _typeFromJson(json),
    createdAt: DateTime.parse(json['ca'] as String),
    note: json['nt'] as String?,
    stableLocation: StableBookLocation.maybeFromJson(json['loc']),
  );

  static String encodeList(List<Highlight> list) =>
      jsonEncode(list.map((h) => h.toJson()).toList());

  static List<Highlight> decodeList(String json) {
    final decoded = jsonDecode(json) as List;
    final result = <Highlight>[];

    for (final entry in decoded) {
      final map = entry as Map<String, dynamic>;
      final hasLegacyType = map.containsKey('ic') && !map.containsKey('tp');
      final legacyNote = map['nt'] as String?;

      final base = Highlight.fromJson({
        ...map,
        if (hasLegacyType)
          'tp': ((map['ic'] as bool?) ?? false)
              ? HighlightType.character.index
              : HighlightType.highlight.index,
        'nt': map.containsKey('tp') ? legacyNote : null,
      });
      result.add(base);

      if (hasLegacyType && legacyNote != null && legacyNote.trim().isNotEmpty) {
        result.add(
          Highlight(
            id: '${base.id}__note',
            originalChunkIndex: base.originalChunkIndex,
            startOffset: base.startOffset,
            endOffset: base.endOffset,
            text: base.text,
            colorIndex: base.colorIndex,
            colorValue: base.colorValue,
            type: HighlightType.note,
            createdAt: base.createdAt,
            note: legacyNote,
            stableLocation: base.stableLocation,
          ),
        );
      }
    }

    return result;
  }

  static HighlightType _typeFromJson(Map<String, dynamic> json) {
    final rawType = json['tp'];
    if (rawType is int &&
        rawType >= 0 &&
        rawType < HighlightType.values.length) {
      return HighlightType.values[rawType];
    }
    if ((json['ic'] as bool?) ?? false) {
      return HighlightType.character;
    }
    return HighlightType.highlight;
  }
}
