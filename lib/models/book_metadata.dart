import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'book_chunk.dart';
import 'bookmark.dart';
import 'reading_settings.dart';
import 'stable_book_location.dart';

@immutable
class BookReadingSummary {
  final List<int> chapterStartIndices;
  final List<int> contentWordPrefixSums;

  const BookReadingSummary({
    this.chapterStartIndices = const [],
    this.contentWordPrefixSums = const [],
  });

  bool get isUsable => contentWordPrefixSums.isNotEmpty;

  int get totalContentWords =>
      contentWordPrefixSums.isEmpty ? 0 : contentWordPrefixSums.last;

  int remainingWordsAfter(int chunkIndex) {
    if (contentWordPrefixSums.isEmpty) return 0;
    final prefixIndex = (chunkIndex + 1)
        .clamp(0, contentWordPrefixSums.length - 1)
        .toInt();
    return (totalContentWords - contentWordPrefixSums[prefixIndex])
        .clamp(0, totalContentWords)
        .toInt();
  }

  int? chapterNumberFor(int currentChunkIndex) {
    if (chapterStartIndices.isEmpty) return null;

    var chapterIndex = -1;
    for (var i = 0; i < chapterStartIndices.length; i++) {
      if (chapterStartIndices[i] <= currentChunkIndex) {
        chapterIndex = i;
      } else {
        break;
      }
    }

    if (chapterIndex == -1 && currentChunkIndex >= 0) {
      return 1;
    }
    return chapterIndex >= 0 ? chapterIndex + 1 : null;
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'chapters': chapterStartIndices,
    'words': contentWordPrefixSums,
  };

  factory BookReadingSummary.fromJson(Map<String, dynamic> json) {
    return BookReadingSummary(
      chapterStartIndices:
          (json['chapters'] as List?)
              ?.whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false) ??
          const [],
      contentWordPrefixSums:
          (json['words'] as List?)
              ?.whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false) ??
          const [],
    );
  }

  factory BookReadingSummary.fromParsedBook({
    required List<BookChunk> chunks,
    required List<ChapterInfo> chapters,
  }) {
    final prefixSums = <int>[0];
    var totalWords = 0;
    for (final chunk in chunks) {
      if (chunk.type == BookChunkType.text &&
          chunk.section == ChunkSection.content) {
        totalWords += _wordCount(chunk.text ?? '');
      }
      prefixSums.add(totalWords);
    }

    return BookReadingSummary(
      chapterStartIndices: _chapterStartIndices(chapters),
      contentWordPrefixSums: prefixSums,
    );
  }

  static List<int> _chapterStartIndices(List<ChapterInfo> chapters) {
    if (chapters.isEmpty) return const [];

    final flat = <ChapterInfo>[];
    void walk(List<ChapterInfo> nodes) {
      for (final chapter in nodes) {
        flat.add(chapter);
        if (chapter.children.isNotEmpty) {
          walk(chapter.children);
        }
      }
    }

    walk(chapters);
    flat.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

    final chapterTitled = flat
        .where(
          (chapter) => RegExp(
            r'\bchapter\b',
            caseSensitive: false,
          ).hasMatch(chapter.title),
        )
        .toList();
    final shallowChapters = flat
        .where((chapter) => chapter.depth <= 1)
        .toList();
    final candidates = chapterTitled.length >= 2
        ? chapterTitled
        : (shallowChapters.length >= 2 ? shallowChapters : flat);

    return candidates
        .map((chapter) => chapter.chunkIndex)
        .toList(growable: false);
  }

  static int _wordCount(String text) {
    if (text.isEmpty) return 0;
    var count = 0;
    var inWord = false;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      final isSpace = c == 32 || c == 9 || c == 10 || c == 13;
      if (!isSpace) {
        if (!inWord) {
          count++;
          inWord = true;
        }
      } else {
        inWord = false;
      }
    }
    return count;
  }
}

@immutable
class BookMetadata {
  final String id; // filename, e.g., 'book.epub'
  final String? managedFilePath; // exact app-managed EPUB path
  final String title;
  final String author;
  final String embeddedTitle;
  final String embeddedAuthor;
  final String titleSource;
  final String authorSource;
  final String? coverImagePath; // local path to extracted cover
  final String? coverSource;
  final String? metadataSource;
  final String? openLibraryWorkKey;
  final int? openLibraryCoverId;
  final String? source;
  final int? gutenbergId;
  final String? sourceUrl;
  final String? downloadUrl;
  final int? importedAt;
  final String? originalSourceTitle;
  final String? originalSourceAuthor;
  final double? metadataConfidence;
  final int lastReadIndex;
  final StableBookLocation? lastReadLocation;
  final int totalChunks;
  final int lastReadTime; // Epoch milliseconds
  final int? lastOpenedAt;
  final int? lastMeaningfulReadAt;
  final AppTheme? theme; // book-specific theme
  final BookReadingSummary? readingSummary;

  BookMetadata({
    required this.id,
    this.managedFilePath,
    required this.title,
    required this.author,
    String? embeddedTitle,
    String? embeddedAuthor,
    this.titleSource = 'embedded',
    this.authorSource = 'embedded',
    this.coverImagePath,
    this.coverSource,
    this.metadataSource,
    this.openLibraryWorkKey,
    this.openLibraryCoverId,
    this.source,
    this.gutenbergId,
    this.sourceUrl,
    this.downloadUrl,
    this.importedAt,
    this.originalSourceTitle,
    this.originalSourceAuthor,
    this.metadataConfidence,
    this.lastReadIndex = 0,
    this.lastReadLocation,
    this.totalChunks = 0,
    int? lastReadTime,
    this.lastOpenedAt,
    this.lastMeaningfulReadAt,
    this.theme,
    this.readingSummary,
  }) : embeddedTitle = _normalizeMetadataValue(
         embeddedTitle ?? title,
         fallback: title,
       ),
       embeddedAuthor = _normalizeMetadataValue(
         embeddedAuthor ?? author,
         fallback: author,
       ),
       lastReadTime = lastReadTime ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'managedFilePath': managedFilePath,
      'title': title,
      'author': author,
      'embeddedTitle': embeddedTitle,
      'embeddedAuthor': embeddedAuthor,
      'titleSource': titleSource,
      'authorSource': authorSource,
      'coverImagePath': coverImagePath,
      'coverSource': coverSource,
      'metadataSource': metadataSource,
      'openLibraryWorkKey': openLibraryWorkKey,
      'openLibraryCoverId': openLibraryCoverId,
      'source': source,
      'gutenbergId': gutenbergId,
      'sourceUrl': sourceUrl,
      'downloadUrl': downloadUrl,
      'importedAt': importedAt,
      'originalSourceTitle': originalSourceTitle,
      'originalSourceAuthor': originalSourceAuthor,
      'metadataConfidence': metadataConfidence,
      'lastReadIndex': lastReadIndex,
      if (lastReadLocation != null)
        'lastReadLocation': lastReadLocation!.toJson(),
      'totalChunks': totalChunks,
      'lastReadTime': lastReadTime,
      if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt,
      if (lastMeaningfulReadAt != null)
        'lastMeaningfulReadAt': lastMeaningfulReadAt,
      'theme': theme?.name,
      'readingSummary': readingSummary?.toJson(),
    };
  }

  factory BookMetadata.fromMap(Map<String, dynamic> map) {
    final rawReadingSummary = map['readingSummary'];
    final lastReadIndex = (map['lastReadIndex'] as num?)?.toInt() ?? 0;
    final lastReadLocation = StableBookLocation.maybeFromJson(
      map['lastReadLocation'],
    );
    final legacyLastReadTime = (map['lastReadTime'] as num?)?.toInt();
    final migratedMeaningfulRead =
        (map['lastMeaningfulReadAt'] as num?)?.toInt() ??
        ((lastReadIndex > 0 || lastReadLocation != null)
            ? legacyLastReadTime
            : null);
    return BookMetadata(
      id: map['id'] ?? '',
      managedFilePath: map['managedFilePath'],
      title: map['title'] ?? '',
      author: map['author'] ?? '',
      embeddedTitle: map['embeddedTitle'] ?? map['title'] ?? '',
      embeddedAuthor: map['embeddedAuthor'] ?? map['author'] ?? '',
      titleSource: map['titleSource'] ?? 'embedded',
      authorSource: map['authorSource'] ?? 'embedded',
      coverImagePath: map['coverImagePath'],
      coverSource: map['coverSource'],
      metadataSource: map['metadataSource'],
      openLibraryWorkKey: map['openLibraryWorkKey'],
      openLibraryCoverId: (map['openLibraryCoverId'] as num?)?.toInt(),
      source: map['source'],
      gutenbergId: (map['gutenbergId'] as num?)?.toInt(),
      sourceUrl: map['sourceUrl'],
      downloadUrl: map['downloadUrl'],
      importedAt: (map['importedAt'] as num?)?.toInt(),
      originalSourceTitle: map['originalSourceTitle'],
      originalSourceAuthor: map['originalSourceAuthor'],
      metadataConfidence: (map['metadataConfidence'] as num?)?.toDouble(),
      lastReadIndex: lastReadIndex,
      lastReadLocation: lastReadLocation,
      totalChunks: (map['totalChunks'] as num?)?.toInt() ?? 0,
      lastReadTime: legacyLastReadTime,
      lastOpenedAt:
          (map['lastOpenedAt'] as num?)?.toInt() ?? migratedMeaningfulRead,
      lastMeaningfulReadAt: migratedMeaningfulRead,
      theme: map['theme'] != null
          ? AppTheme.values.firstWhere(
              (e) => e.name == map['theme'],
              orElse: () => AppTheme.amoled,
            )
          : null,
      readingSummary: rawReadingSummary is Map
          ? BookReadingSummary.fromJson(
              Map<String, dynamic>.from(rawReadingSummary),
            )
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory BookMetadata.fromJson(String source) =>
      BookMetadata.fromMap(json.decode(source));

  BookMetadata copyWith({
    String? id,
    String? managedFilePath,
    String? title,
    String? author,
    String? embeddedTitle,
    String? embeddedAuthor,
    String? titleSource,
    String? authorSource,
    String? coverImagePath,
    String? coverSource,
    String? metadataSource,
    String? openLibraryWorkKey,
    int? openLibraryCoverId,
    String? source,
    int? gutenbergId,
    String? sourceUrl,
    String? downloadUrl,
    int? importedAt,
    String? originalSourceTitle,
    String? originalSourceAuthor,
    double? metadataConfidence,
    int? lastReadIndex,
    StableBookLocation? lastReadLocation,
    int? totalChunks,
    int? lastReadTime,
    int? lastOpenedAt,
    int? lastMeaningfulReadAt,
    AppTheme? theme,
    BookReadingSummary? readingSummary,
    bool clearTheme = false,
    bool clearReadingSummary = false,
    bool clearManagedFilePath = false,
  }) {
    return BookMetadata(
      id: id ?? this.id,
      managedFilePath: clearManagedFilePath
          ? null
          : (managedFilePath ?? this.managedFilePath),
      title: title ?? this.title,
      author: author ?? this.author,
      embeddedTitle: embeddedTitle ?? this.embeddedTitle,
      embeddedAuthor: embeddedAuthor ?? this.embeddedAuthor,
      titleSource: titleSource ?? this.titleSource,
      authorSource: authorSource ?? this.authorSource,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      coverSource: coverSource ?? this.coverSource,
      metadataSource: metadataSource ?? this.metadataSource,
      openLibraryWorkKey: openLibraryWorkKey ?? this.openLibraryWorkKey,
      openLibraryCoverId: openLibraryCoverId ?? this.openLibraryCoverId,
      source: source ?? this.source,
      gutenbergId: gutenbergId ?? this.gutenbergId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      importedAt: importedAt ?? this.importedAt,
      originalSourceTitle: originalSourceTitle ?? this.originalSourceTitle,
      originalSourceAuthor: originalSourceAuthor ?? this.originalSourceAuthor,
      metadataConfidence: metadataConfidence ?? this.metadataConfidence,
      lastReadIndex: lastReadIndex ?? this.lastReadIndex,
      lastReadLocation: lastReadLocation ?? this.lastReadLocation,
      totalChunks: totalChunks ?? this.totalChunks,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      lastMeaningfulReadAt: lastMeaningfulReadAt ?? this.lastMeaningfulReadAt,
      theme: clearTheme ? null : (theme ?? this.theme),
      readingSummary: clearReadingSummary
          ? null
          : (readingSummary ?? this.readingSummary),
    );
  }

  bool get canRevertToBookMetadata =>
      _normalizeMetadataValue(title) !=
          _normalizeMetadataValue(embeddedTitle) ||
      _normalizeMetadataValue(author) !=
          _normalizeMetadataValue(embeddedAuthor);

  static String _normalizeMetadataValue(String? value, {String fallback = ''}) {
    final compact = value?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    return compact.isEmpty ? fallback : compact;
  }
}
