import 'dart:convert';

import 'stable_book_location.dart';

class SavedWord {
  final String id;
  final String word;
  final String meaning;
  final String bookId;
  final int timestamp;

  // Storing the sentence context helps users remember where they saw the word
  final String? contextSentence;
  final int? originalChunkIndex;
  final int? originalStartOffset;
  final int? originalEndOffset;
  final StableBookLocation? stableLocation;

  const SavedWord({
    required this.id,
    required this.word,
    required this.meaning,
    required this.bookId,
    required this.timestamp,
    this.contextSentence,
    this.originalChunkIndex,
    this.originalStartOffset,
    this.originalEndOffset,
    this.stableLocation,
  });

  SavedWord copyWith({
    String? id,
    String? word,
    String? meaning,
    String? bookId,
    int? timestamp,
    String? contextSentence,
    int? originalChunkIndex,
    int? originalStartOffset,
    int? originalEndOffset,
    StableBookLocation? stableLocation,
  }) {
    return SavedWord(
      id: id ?? this.id,
      word: word ?? this.word,
      meaning: meaning ?? this.meaning,
      bookId: bookId ?? this.bookId,
      timestamp: timestamp ?? this.timestamp,
      contextSentence: contextSentence ?? this.contextSentence,
      originalChunkIndex: originalChunkIndex ?? this.originalChunkIndex,
      originalStartOffset: originalStartOffset ?? this.originalStartOffset,
      originalEndOffset: originalEndOffset ?? this.originalEndOffset,
      stableLocation: stableLocation ?? this.stableLocation,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'word': word,
      'meaning': meaning,
      'bookId': bookId,
      'timestamp': timestamp,
      'contextSentence': contextSentence,
      'originalChunkIndex': originalChunkIndex,
      'originalStartOffset': originalStartOffset,
      'originalEndOffset': originalEndOffset,
      if (stableLocation != null) 'stableLocation': stableLocation!.toJson(),
    };
  }

  factory SavedWord.fromMap(Map<String, dynamic> map) {
    return SavedWord(
      id: map['id'] ?? '',
      word: map['word'] ?? '',
      meaning: map['meaning'] ?? '',
      bookId: map['bookId'] ?? '',
      timestamp: map['timestamp'] ?? 0,
      contextSentence: map['contextSentence'],
      originalChunkIndex: map['originalChunkIndex'] as int?,
      originalStartOffset: map['originalStartOffset'] as int?,
      originalEndOffset: map['originalEndOffset'] as int?,
      stableLocation: StableBookLocation.maybeFromJson(map['stableLocation']),
    );
  }

  String toJson() => json.encode(toMap());

  factory SavedWord.fromJson(String source) =>
      SavedWord.fromMap(json.decode(source));
}
