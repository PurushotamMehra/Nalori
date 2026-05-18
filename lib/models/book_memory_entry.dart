import 'dart:convert';

enum BookMemorySourceType { bookmark, highlight, note, word, character, free }

class BookMemoryEntry {
  final String id;
  final String bookId;
  final BookMemorySourceType sourceType;
  final String? sourceId;
  final String title;
  final String body;
  final int createdAtMs;
  final int updatedAtMs;

  const BookMemoryEntry({
    required this.id,
    required this.bookId,
    required this.sourceType,
    required this.sourceId,
    required this.title,
    required this.body,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  bool get isFree => sourceType == BookMemorySourceType.free;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  BookMemoryEntry copyWith({
    String? id,
    String? bookId,
    BookMemorySourceType? sourceType,
    Object? sourceId = _unset,
    String? title,
    String? body,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return BookMemoryEntry(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      sourceType: sourceType ?? this.sourceType,
      sourceId: identical(sourceId, _unset)
          ? this.sourceId
          : sourceId as String?,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'sourceType': sourceType.name,
    if (sourceId != null) 'sourceId': sourceId,
    'title': title,
    'body': body,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
  };

  factory BookMemoryEntry.fromJson(Map<String, dynamic> json) {
    return BookMemoryEntry(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      sourceType: _sourceTypeFromJson(json['sourceType']),
      sourceId: json['sourceId'] as String?,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      createdAtMs: json['createdAtMs'] as int,
      updatedAtMs: json['updatedAtMs'] as int,
    );
  }

  static String encodeList(List<BookMemoryEntry> entries) {
    return jsonEncode(entries.map((entry) => entry.toJson()).toList());
  }

  static List<BookMemoryEntry> decodeList(String source) {
    final decoded = jsonDecode(source) as List;
    return decoded
        .map((entry) => BookMemoryEntry.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  static BookMemorySourceType _sourceTypeFromJson(Object? value) {
    if (value is String) {
      return BookMemorySourceType.values.firstWhere(
        (type) => type.name == value,
      );
    }
    if (value is int &&
        value >= 0 &&
        value < BookMemorySourceType.values.length) {
      return BookMemorySourceType.values[value];
    }
    throw FormatException('Unknown book memory source type: $value');
  }

  static const Object _unset = Object();
}
