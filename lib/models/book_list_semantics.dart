import 'package:flutter/foundation.dart';

enum BookListMarkerType {
  unordered,
  decimal,
  lowerAlpha,
  upperAlpha,
  lowerRoman,
  upperRoman,
}

enum BookListFragmentState { complete, opening, continuation, finalFragment }

@immutable
class BookListSemantics {
  const BookListSemantics({
    required this.listId,
    required this.itemId,
    required this.ordered,
    required this.depth,
    required this.markerType,
    required this.blockIndex,
    required this.beginsItem,
    required this.endsItem,
    this.parentListId,
    this.parentItemId,
    this.resolvedOrdinal,
    this.orderedStart,
    this.itemValue,
  });

  final String listId;
  final String itemId;
  final String? parentListId;
  final String? parentItemId;
  final bool ordered;
  final int depth;
  final BookListMarkerType markerType;
  final int? resolvedOrdinal;
  final int? orderedStart;
  final int? itemValue;
  final int blockIndex;
  final bool beginsItem;
  final bool endsItem;

  BookListSemantics copyWith({
    int? blockIndex,
    bool? beginsItem,
    bool? endsItem,
  }) {
    return BookListSemantics(
      listId: listId,
      itemId: itemId,
      parentListId: parentListId,
      parentItemId: parentItemId,
      ordered: ordered,
      depth: depth,
      markerType: markerType,
      resolvedOrdinal: resolvedOrdinal,
      orderedStart: orderedStart,
      itemValue: itemValue,
      blockIndex: blockIndex ?? this.blockIndex,
      beginsItem: beginsItem ?? this.beginsItem,
      endsItem: endsItem ?? this.endsItem,
    );
  }

  Map<String, dynamic> toJson() => {
    'l': listId,
    'i': itemId,
    if (parentListId != null) 'pl': parentListId,
    if (parentItemId != null) 'pi': parentItemId,
    if (ordered) 'o': true,
    'd': depth,
    'm': markerType.index,
    if (resolvedOrdinal != null) 'r': resolvedOrdinal,
    if (orderedStart != null) 's': orderedStart,
    if (itemValue != null) 'v': itemValue,
    'b': blockIndex,
    if (beginsItem) 'bi': true,
    if (endsItem) 'ei': true,
  };

  factory BookListSemantics.fromJson(Map<String, dynamic> json) {
    return BookListSemantics(
      listId: json['l'] as String,
      itemId: json['i'] as String,
      parentListId: json['pl'] as String?,
      parentItemId: json['pi'] as String?,
      ordered: json['o'] == true,
      depth: json['d'] as int,
      markerType: BookListMarkerType.values[json['m'] as int],
      resolvedOrdinal: json['r'] as int?,
      orderedStart: json['s'] as int?,
      itemValue: json['v'] as int?,
      blockIndex: json['b'] as int,
      beginsItem: json['bi'] == true,
      endsItem: json['ei'] == true,
    );
  }
}

@immutable
class BookListDisplaySegment {
  const BookListDisplaySegment({
    required this.displayStartOffset,
    required this.displayEndOffset,
    required this.semantics,
    required this.fragmentState,
  });

  final int displayStartOffset;
  final int displayEndOffset;
  final BookListSemantics semantics;
  final BookListFragmentState fragmentState;

  bool get showsMarker =>
      semantics.beginsItem &&
      (fragmentState == BookListFragmentState.complete ||
          fragmentState == BookListFragmentState.opening);

  BookListDisplaySegment shift(int delta) => BookListDisplaySegment(
    displayStartOffset: displayStartOffset + delta,
    displayEndOffset: displayEndOffset + delta,
    semantics: semantics,
    fragmentState: fragmentState,
  );

  Map<String, dynamic> toJson() => {
    's': displayStartOffset,
    'e': displayEndOffset,
    'l': semantics.toJson(),
    'f': fragmentState.index,
  };

  factory BookListDisplaySegment.fromJson(Map<String, dynamic> json) {
    return BookListDisplaySegment(
      displayStartOffset: json['s'] as int,
      displayEndOffset: json['e'] as int,
      semantics: BookListSemantics.fromJson(json['l'] as Map<String, dynamic>),
      fragmentState: BookListFragmentState.values[json['f'] as int],
    );
  }
}

BookListFragmentState bookListFragmentState({
  required bool beginsItem,
  required bool endsItem,
}) {
  if (beginsItem && endsItem) return BookListFragmentState.complete;
  if (beginsItem) return BookListFragmentState.opening;
  if (endsItem) return BookListFragmentState.finalFragment;
  return BookListFragmentState.continuation;
}

String bookListMarkerText(BookListSemantics semantics) {
  if (!semantics.ordered) {
    return switch (semantics.depth % 3) {
      0 => '•',
      1 => '◦',
      _ => '▪',
    };
  }

  final ordinal = semantics.resolvedOrdinal ?? semantics.orderedStart ?? 1;
  final value = switch (semantics.markerType) {
    BookListMarkerType.lowerAlpha => _alphabeticOrdinal(ordinal, false),
    BookListMarkerType.upperAlpha => _alphabeticOrdinal(ordinal, true),
    BookListMarkerType.lowerRoman => _romanOrdinal(ordinal).toLowerCase(),
    BookListMarkerType.upperRoman => _romanOrdinal(ordinal),
    BookListMarkerType.unordered || BookListMarkerType.decimal => '$ordinal',
  };
  return '$value.';
}

String _alphabeticOrdinal(int ordinal, bool uppercase) {
  if (ordinal <= 0) return '$ordinal';
  var remaining = ordinal;
  final units = <int>[];
  while (remaining > 0) {
    remaining--;
    units.add((uppercase ? 65 : 97) + remaining % 26);
    remaining ~/= 26;
  }
  return String.fromCharCodes(units.reversed);
}

String _romanOrdinal(int ordinal) {
  if (ordinal <= 0 || ordinal > 3999) return '$ordinal';
  const values = <(int, String)>[
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  var remaining = ordinal;
  final result = StringBuffer();
  for (final entry in values) {
    while (remaining >= entry.$1) {
      result.write(entry.$2);
      remaining -= entry.$1;
    }
  }
  return result.toString();
}
