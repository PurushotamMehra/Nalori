import 'package:flutter/foundation.dart';

enum ReaderTextBoundaryKind {
  structural,
  sentence,
  clause,
  word,
  emergencyGrapheme,
}

@immutable
class DisplayTextBoundary {
  const DisplayTextBoundary({
    required this.offset,
    required this.kind,
    this.synthesizedTextLength = 0,
  });

  final int offset;
  final ReaderTextBoundaryKind kind;
  final int synthesizedTextLength;

  DisplayTextBoundary shift(int delta) => DisplayTextBoundary(
    offset: offset + delta,
    kind: kind,
    synthesizedTextLength: synthesizedTextLength,
  );

  Map<String, dynamic> toJson() => {
    'o': offset,
    'k': kind.index,
    if (synthesizedTextLength != 0) 's': synthesizedTextLength,
  };

  factory DisplayTextBoundary.fromJson(Map<String, dynamic> json) =>
      DisplayTextBoundary(
        offset: json['o'] as int,
        kind: ReaderTextBoundaryKind.values[json['k'] as int],
        synthesizedTextLength: json['s'] as int? ?? 0,
      );
}
