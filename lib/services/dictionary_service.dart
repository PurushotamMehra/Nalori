import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/saved_word.dart';

class DictionaryService {
  final String bookId;
  static const _uuid = Uuid();
  List<SavedWord> _words = [];

  DictionaryService({required this.bookId}) {
    _loadWords();
  }

  String get _prefsKey => 'saved_words_$bookId';

  Future<void> _loadWords() async {
    final prefs = await SharedPreferences.getInstance();
    final wordsJson = prefs.getStringList(_prefsKey) ?? [];
    _words = wordsJson.map((jsonStr) => SavedWord.fromJson(jsonStr)).toList();
    // Sort newest first
    _words.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<List<SavedWord>> loadWords() async {
    await _loadWords();
    return words;
  }

  Future<void> _saveWords() async {
    final prefs = await SharedPreferences.getInstance();
    final wordsJson = _words.map((w) => w.toJson()).toList();
    await prefs.setStringList(_prefsKey, wordsJson);
  }

  List<SavedWord> get words => List.unmodifiable(_words);

  /// Look up a word using Free Dictionary API
  Future<String?> lookupWord(String word) async {
    // Strip leading and trailing non-word characters (like punctuation)
    final cleanWord = word
        .trim()
        .replaceAll(RegExp(r'^\W+|\W+$'), '')
        .toLowerCase();
    if (cleanWord.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$cleanWord'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          final entry = data.first;
          if (entry is! Map<String, dynamic>) return null;

          final meanings = entry['meanings'] as List<dynamic>?;
          if (meanings != null && meanings.isNotEmpty) {
            final firstMeaning = meanings.first;
            if (firstMeaning is! Map<String, dynamic>) return null;

            final definitions = firstMeaning['definitions'] as List<dynamic>?;
            if (definitions != null && definitions.isNotEmpty) {
              final firstDefinition = definitions.first;
              if (firstDefinition is! Map<String, dynamic>) return null;

              return firstDefinition['definition'] as String?;
            }
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Dictionary lookup failed: $e');
      return null;
    }
  }

  Future<void> saveWord(
    String word,
    String meaning, {
    String? contextSentence,
    int? originalChunkIndex,
    int? originalStartOffset,
    int? originalEndOffset,
  }) async {
    final newWord = SavedWord(
      id: _uuid.v4(),
      word: word.trim(),
      meaning: meaning,
      bookId: bookId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      contextSentence: contextSentence,
      originalChunkIndex: originalChunkIndex,
      originalStartOffset: originalStartOffset,
      originalEndOffset: originalEndOffset,
    );

    // Avoid exact duplicates
    _words.removeWhere(
      (w) => w.word.toLowerCase() == newWord.word.toLowerCase(),
    );

    _words.insert(0, newWord);
    await _saveWords();
  }

  Future<void> deleteWord(String id) async {
    _words.removeWhere((w) => w.id == id);
    await _saveWords();
  }

  bool isWordSaved(String word) {
    return _words.any((w) => w.word.toLowerCase() == word.trim().toLowerCase());
  }
}
