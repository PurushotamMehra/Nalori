import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StoredCharacterOccurrenceIndex {
  final Map<String, StoredCharacterOccurrence> occurrences;

  const StoredCharacterOccurrenceIndex({required this.occurrences});

  factory StoredCharacterOccurrenceIndex.empty() {
    return const StoredCharacterOccurrenceIndex(occurrences: {});
  }

  StoredCharacterOccurrence? operator [](String sourceId) {
    return occurrences[sourceId];
  }

  StoredCharacterOccurrenceIndex copyWith(
    Map<String, StoredCharacterOccurrence> updated,
  ) {
    return StoredCharacterOccurrenceIndex(
      occurrences: Map.unmodifiable(updated),
    );
  }

  Map<String, dynamic> toJson() => {
    'occurrences': occurrences.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  factory StoredCharacterOccurrenceIndex.fromJson(Map<String, dynamic> json) {
    final raw = json['occurrences'];
    if (raw is! Map) return StoredCharacterOccurrenceIndex.empty();
    return StoredCharacterOccurrenceIndex(
      occurrences: Map.unmodifiable(
        raw.map(
          (key, value) => MapEntry(
            key as String,
            StoredCharacterOccurrence.fromJson(value as Map<String, dynamic>),
          ),
        ),
      ),
    );
  }
}

class StoredCharacterOccurrence {
  final List<String> aliases;
  final CharacterOccurrencePosition? first;
  final CharacterOccurrencePosition? last;
  final int count;
  final String sourceSignature;

  const StoredCharacterOccurrence({
    required this.aliases,
    required this.first,
    required this.last,
    this.count = 0,
    this.sourceSignature = '',
  });

  bool isFresh({
    required List<String> expectedAliases,
    required String expectedSourceSignature,
  }) {
    final current = aliases.map(_normalize).toSet();
    final expected = expectedAliases.map(_normalize).toSet();
    return current.length == expected.length &&
        current.containsAll(expected) &&
        sourceSignature == expectedSourceSignature;
  }

  Map<String, dynamic> toJson() => {
    'aliases': aliases,
    'count': count,
    'sourceSignature': sourceSignature,
    if (first != null) 'first': first!.toJson(),
    if (last != null) 'last': last!.toJson(),
  };

  factory StoredCharacterOccurrence.fromJson(Map<String, dynamic> json) {
    return StoredCharacterOccurrence(
      aliases: (json['aliases'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      first: json['first'] is Map<String, dynamic>
          ? CharacterOccurrencePosition.fromJson(
              json['first'] as Map<String, dynamic>,
            )
          : null,
      last: json['last'] is Map<String, dynamic>
          ? CharacterOccurrencePosition.fromJson(
              json['last'] as Map<String, dynamic>,
            )
          : null,
      count: (json['count'] as num?)?.toInt() ?? 0,
      sourceSignature: (json['sourceSignature'] as String?) ?? '',
    );
  }
}

class CharacterOccurrencePosition {
  final int chunkIndex;
  final int startOffset;
  final int endOffset;
  final String text;

  const CharacterOccurrencePosition({
    required this.chunkIndex,
    required this.startOffset,
    required this.endOffset,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'chunkIndex': chunkIndex,
    'startOffset': startOffset,
    'endOffset': endOffset,
    'text': text,
  };

  factory CharacterOccurrencePosition.fromJson(Map<String, dynamic> json) {
    return CharacterOccurrencePosition(
      chunkIndex: json['chunkIndex'] as int,
      startOffset: json['startOffset'] as int,
      endOffset: json['endOffset'] as int,
      text: (json['text'] as String?) ?? '',
    );
  }
}

class BookCharacterOccurrenceService {
  final String bookId;
  SharedPreferences? _prefs;

  BookCharacterOccurrenceService({required this.bookId});

  String get _key => 'book_character_occurrences_$bookId';

  Future<SharedPreferences> get _cachedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<StoredCharacterOccurrenceIndex> load() async {
    final prefs = await _cachedPrefs;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return StoredCharacterOccurrenceIndex.empty();
    }
    try {
      return StoredCharacterOccurrenceIndex.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return StoredCharacterOccurrenceIndex.empty();
    }
  }

  Future<void> save(StoredCharacterOccurrenceIndex index) async {
    final prefs = await _cachedPrefs;
    await prefs.setString(_key, jsonEncode(index.toJson()));
  }
}

String _normalize(String text) {
  return text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
