import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book_metadata.dart';
import '../utils/person_name_utils.dart';
import 'lazy_epub_index_service.dart';
import 'open_library_metadata_service.dart';

/// Service managing persistent metadata for all imported books.
/// Creates a cached JSON registry and extracts cover images.
class BookMetadataService {
  // Singleton pattern
  static final BookMetadataService _instance = BookMetadataService._internal();

  factory BookMetadataService() {
    return _instance;
  }

  BookMetadataService._internal();

  static const String _metadataFileName = 'books_metadata.json';
  static const String _coversDirName = 'covers';

  final OpenLibraryMetadataService _openLibrary = OpenLibraryMetadataService();
  Map<String, BookMetadata> _cache = {};
  bool _initialized = false;

  /// Ensure metadata registry is loaded into memory
  Future<void> init() async {
    if (_initialized) return;

    final file = await _getMetadataFile();
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final Map<String, dynamic> data = json.decode(content);
        _cache = data.map(
          (key, value) => MapEntry(key, BookMetadata.fromMap(value)),
        );
      } catch (e) {
        debugPrint('BookMetadataService: Failed to load metadata: $e');
        _cache = {};
      }
    }
    _initialized = true;
  }

  /// Get metadata for a specific book ID (filename)
  BookMetadata? getMetadata(String bookId) {
    return _cache[bookId];
  }

  /// Update metadata for a book inside the cache (e.g. updating progress)
  Future<void> updateMetadata(BookMetadata metadata) async {
    _cache[metadata.id] = _withEmbeddedFallbacks(metadata);
    await _save();
  }

  Future<void> updateReadingSummary({
    required String bookId,
    required BookReadingSummary summary,
    int? totalChunks,
  }) async {
    await init();
    final current = _cache[bookId];
    if (current == null) return;

    await updateMetadata(
      current.copyWith(
        readingSummary: summary,
        totalChunks: totalChunks ?? current.totalChunks,
      ),
    );
  }

  /// Get all metadata sorted by lastReadTime descending
  List<BookMetadata> getAllSortedByLastRead() {
    final list = _cache.values.toList();
    list.sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
    return list;
  }

  /// Delete metadata for a book, including its cover image.
  Future<void> deleteMetadata(String bookId) async {
    final meta = _cache[bookId];
    if (meta != null) {
      // Delete cover image if it exists
      if (meta.coverImagePath != null) {
        final coverFile = File(meta.coverImagePath!);
        if (await coverFile.exists()) {
          await coverFile.delete();
        }
      }
      _cache.remove(bookId);
      await _save();
    }
  }

  /// Extract metadata and cover image natively from an EPUB File
  /// Fallbacks to generating a clean filename if real title is not present.
  /// Returns null if the file is corrupted.
  Future<BookMetadata?> extractAndCacheMetadata(File epubFile) async {
    final bookId = p.basename(epubFile.path);
    LazyEpubBookHandle? handle;
    try {
      handle = await const LazyEpubIndexService().openBookIndex(epubFile);
    } catch (e) {
      debugPrint('BookMetadataService: Failed to index EPUB ($bookId): $e');
      return null; // File is completely unreadable
    }

    try {
      final index = handle.index;
      var title = index.title.trim();
      if (title.isEmpty) {
        title = _cleanFileName(bookId);
      }
      var author = index.author.trim().isEmpty
          ? 'Unknown Author'
          : index.author;
      author = normalizePersonNameForDisplay(author);

      String? coverPath;
      try {
        final coverResource = await handle.readCoverResource();
        if (coverResource != null && coverResource.bytes.isNotEmpty) {
          coverPath = await _saveCoverBytes(
            bookId: bookId,
            source: 'embedded',
            bytes: coverResource.bytes,
            extension: _extensionForCoverResource(
              mediaType: coverResource.mediaType,
              path: coverResource.path,
            ),
          );
        }
      } catch (e) {
        debugPrint('Failed to extract raw cover for $bookId: $e');
      }

      final newMeta = BookMetadata(
        id: bookId,
        managedFilePath: epubFile.path,
        title: title,
        author: author,
        embeddedTitle: title,
        embeddedAuthor: author,
        coverImagePath: coverPath,
        coverSource: coverPath == null ? null : 'embedded',
        lastReadTime: DateTime.now().millisecondsSinceEpoch,
      );

      await updateMetadata(newMeta);
      return newMeta;
    } finally {
      await handle.close();
    }
  }

  /// Improve title, author, and cover by matching the current metadata against
  /// Open Library. Returns null when no confident match is found.
  Future<BookMetadata?> enhanceMetadataFromOpenLibrary(String bookId) async {
    await init();

    final current = _cache[bookId];
    if (current == null) return null;

    OpenLibraryBookMatch? match;
    try {
      match = await _openLibrary.findBestMatch(
        title: current.title,
        author: current.author,
      );
    } catch (e) {
      debugPrint('BookMetadataService: Open Library lookup failed: $e');
      return null;
    }
    if (match == null) {
      final candidates = await findCoverCandidates(bookId);
      if (candidates.isEmpty) return null;
      return applyCoverCandidate(bookId, candidates.first);
    }

    var coverPath = current.coverImagePath;
    final coverId = match.coverId;
    var coverSource = current.coverSource;
    final canAutoApplyRemoteCover = _openLibrary.isHighConfidence(match);
    if (coverId != null && canAutoApplyRemoteCover) {
      try {
        final bytes = await _openLibrary.fetchCoverBytes(coverId);
        if (bytes != null) {
          coverPath = await _saveCoverBytes(
            bookId: bookId,
            source: 'openlibrary',
            bytes: bytes,
          );
          coverSource = 'open_library';
        }
      } catch (e) {
        debugPrint('BookMetadataService: Open Library cover failed: $e');
      }
    }

    if (coverPath == null && canAutoApplyRemoteCover) {
      try {
        final candidates = await findCoverCandidates(bookId);
        if (candidates.isNotEmpty) {
          final updated = await applyCoverCandidate(bookId, candidates.first);
          coverPath = updated?.coverImagePath;
          coverSource = updated?.coverSource;
        }
      } catch (e) {
        debugPrint('BookMetadataService: cover candidate lookup failed: $e');
      }
    }

    final updated = _applyVerifiedRemoteMetadata(
      current,
      remoteTitle: match.title,
      remoteAuthor: match.author,
      source: 'open_library',
      coverImagePath: coverPath,
      coverSource: coverSource,
      openLibraryWorkKey: match.workKey,
      openLibraryCoverId: match.coverId,
      metadataConfidence: match.confidence,
    );
    await updateMetadata(updated);
    return updated;
  }

  Future<BookMetadata?> applyRemoteMetadata({
    required String bookId,
    required String title,
    required String author,
    required String source,
    String? coverImagePath,
    String? coverSource,
    double? metadataConfidence,
    String? openLibraryWorkKey,
    int? openLibraryCoverId,
  }) async {
    await init();

    final current = _cache[bookId];
    if (current == null) return null;

    final updated = _applyVerifiedRemoteMetadata(
      current,
      remoteTitle: title,
      remoteAuthor: author,
      source: source,
      coverImagePath: coverImagePath,
      coverSource: coverSource,
      metadataConfidence: metadataConfidence,
      openLibraryWorkKey: openLibraryWorkKey,
      openLibraryCoverId: openLibraryCoverId,
    );
    await updateMetadata(updated);
    return updated;
  }

  Future<BookMetadata?> revertToBookMetadata(String bookId) async {
    await init();

    final current = _cache[bookId];
    if (current == null) return null;

    final updated = current.copyWith(
      title: current.embeddedTitle,
      author: current.embeddedAuthor,
      titleSource: 'embedded',
      authorSource: 'embedded',
      metadataSource: 'embedded',
    );
    await updateMetadata(updated);
    return updated;
  }

  Future<List<BookCoverCandidate>> findCoverCandidates(String bookId) async {
    await init();

    final current = _cache[bookId];
    if (current == null) return const [];

    try {
      return _openLibrary.findCoverCandidates(
        title: current.title,
        author: current.author,
      );
    } catch (e) {
      debugPrint('BookMetadataService: cover lookup failed: $e');
      return const [];
    }
  }

  Future<BookMetadata?> applyCoverCandidate(
    String bookId,
    BookCoverCandidate candidate,
  ) async {
    await init();

    final current = _cache[bookId];
    if (current == null) return null;

    final bytes = await _openLibrary.fetchCoverCandidateBytes(candidate);
    if (bytes == null) return null;

    final coverPath = await _saveCoverBytes(
      bookId: bookId,
      source: candidate.source,
      bytes: bytes,
    );
    final updated = current.copyWith(
      coverImagePath: coverPath,
      coverSource: candidate.source,
    );
    await updateMetadata(updated);
    return updated;
  }

  Future<BookMetadata?> saveRemoteCover({
    required String bookId,
    required String coverUrl,
    required String source,
  }) async {
    return applyCoverCandidate(
      bookId,
      BookCoverCandidate(
        source: source,
        label: source,
        imageUrl: coverUrl,
        confidence: 1.0,
      ),
    );
  }

  Future<BookMetadata?> saveLocalCover({
    required String bookId,
    required File sourceFile,
  }) async {
    await init();

    final current = _cache[bookId];
    if (current == null) return null;

    final bytes = await sourceFile.readAsBytes();
    if (bytes.length < 256) return null;

    final coverPath = await _saveCoverBytes(
      bookId: bookId,
      source: 'local',
      bytes: bytes,
      extension: _extensionForCoverFile(sourceFile.path),
    );
    final updated = current.copyWith(coverImagePath: coverPath);
    await updateMetadata(updated);
    return updated;
  }

  Future<BookMetadata?> updateManagedFilePath({
    required String bookId,
    required String managedFilePath,
  }) async {
    await init();
    final current = _cache[bookId];
    if (current == null) return null;
    final updated = current.copyWith(managedFilePath: managedFilePath);
    await updateMetadata(updated);
    return updated;
  }

  BookMetadata _withEmbeddedFallbacks(BookMetadata metadata) {
    final embeddedTitle = metadata.embeddedTitle.trim().isEmpty
        ? metadata.title
        : metadata.embeddedTitle;
    final embeddedAuthor = normalizePersonNameForDisplay(
      metadata.embeddedAuthor.trim().isEmpty
          ? metadata.author
          : metadata.embeddedAuthor,
    );

    return metadata.copyWith(
      embeddedTitle: embeddedTitle,
      embeddedAuthor: embeddedAuthor,
      author: normalizePersonNameForDisplay(metadata.author),
    );
  }

  BookMetadata _applyVerifiedRemoteMetadata(
    BookMetadata current, {
    required String remoteTitle,
    required String remoteAuthor,
    required String source,
    String? coverImagePath,
    String? coverSource,
    double? metadataConfidence,
    String? openLibraryWorkKey,
    int? openLibraryCoverId,
  }) {
    final normalizedRemoteTitle = _compactValue(remoteTitle);
    final normalizedRemoteAuthor = normalizePersonNameForDisplay(
      _compactValue(remoteAuthor),
    );
    final embeddedTitle = _compactValue(current.embeddedTitle);
    final embeddedAuthor = normalizePersonNameForDisplay(
      _compactValue(current.embeddedAuthor),
    );

    final shouldUseRemoteTitle = _shouldReplaceWithRemoteValue(
      embeddedValue: embeddedTitle,
      remoteValue: normalizedRemoteTitle,
      confidence: metadataConfidence,
      isAuthor: false,
    );
    final shouldUseRemoteAuthor = _shouldReplaceWithRemoteValue(
      embeddedValue: embeddedAuthor,
      remoteValue: normalizedRemoteAuthor,
      confidence: metadataConfidence,
      isAuthor: true,
    );

    return current.copyWith(
      title: shouldUseRemoteTitle ? normalizedRemoteTitle : embeddedTitle,
      author: shouldUseRemoteAuthor ? normalizedRemoteAuthor : embeddedAuthor,
      titleSource: shouldUseRemoteTitle ? source : 'embedded',
      authorSource: shouldUseRemoteAuthor ? source : 'embedded',
      coverImagePath: coverImagePath ?? current.coverImagePath,
      coverSource: coverSource ?? current.coverSource,
      metadataSource: source,
      metadataConfidence: metadataConfidence ?? current.metadataConfidence,
      openLibraryWorkKey: openLibraryWorkKey ?? current.openLibraryWorkKey,
      openLibraryCoverId: openLibraryCoverId ?? current.openLibraryCoverId,
    );
  }

  bool _shouldReplaceWithRemoteValue({
    required String embeddedValue,
    required String remoteValue,
    required bool isAuthor,
    double? confidence,
  }) {
    if (remoteValue.isEmpty) return false;
    if (embeddedValue.isEmpty) return true;
    if (_isUnknownValue(embeddedValue, isAuthor: isAuthor)) return true;

    final similarity = _tokenSimilarity(
      isAuthor
          ? _normalizeAuthorForComparison(embeddedValue)
          : _stripTitleNoise(embeddedValue),
      isAuthor
          ? _normalizeAuthorForComparison(remoteValue)
          : _stripTitleNoise(remoteValue),
      useFuzzyTokenMatch: isAuthor,
    );
    final minimumSimilarity = isAuthor ? 0.70 : 0.74;
    if (similarity >= minimumSimilarity) return true;

    final normalizedConfidence = confidence ?? 0.72;
    return similarity >= 0.62 && normalizedConfidence >= 0.92;
  }

  String _stripTitleNoise(String value) {
    return value
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _tokenSimilarity(
    String left,
    String right, {
    bool useFuzzyTokenMatch = false,
  }) {
    final leftTokens = _tokens(left);
    final rightTokens = _tokens(right);
    if (leftTokens.isEmpty || rightTokens.isEmpty) return 0.0;

    final intersection = useFuzzyTokenMatch
        ? _fuzzyIntersectionCount(leftTokens, rightTokens)
        : leftTokens.intersection(rightTokens).length;
    final union = useFuzzyTokenMatch
        ? leftTokens.length + rightTokens.length - intersection
        : leftTokens.union(rightTokens).length;
    final jaccard = union == 0 ? 0.0 : intersection / union;
    final normalizedLeft = _normalize(left);
    final normalizedRight = _normalize(right);
    final containsBonus =
        normalizedLeft.contains(normalizedRight) ||
            normalizedRight.contains(normalizedLeft)
        ? 0.18
        : 0.0;
    return (jaccard + containsBonus).clamp(0.0, 1.0);
  }

  String _normalizeAuthorForComparison(String value) {
    return normalizePersonNameForDisplay(value);
  }

  int _fuzzyIntersectionCount(Set<String> leftTokens, Set<String> rightTokens) {
    final remainingRight = rightTokens.toList(growable: true);
    var matches = 0;

    for (final left in leftTokens) {
      final index = remainingRight.indexWhere(
        (right) => _tokensAreEquivalent(left, right),
      );
      if (index == -1) continue;
      matches += 1;
      remainingRight.removeAt(index);
    }

    return matches;
  }

  bool _tokensAreEquivalent(String left, String right) {
    if (left == right) return true;
    if (left.length < 4 || right.length < 4) return false;
    return _levenshteinDistance(left, right) <= 1;
  }

  int _levenshteinDistance(String left, String right) {
    if (left == right) return 0;
    if (left.isEmpty) return right.length;
    if (right.isEmpty) return left.length;

    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 0; i < left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < right.length; j++) {
        final substitutionCost = left[i] == right[j] ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + substitutionCost,
        ].reduce((a, b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous.last;
  }

  Set<String> _tokens(String value) {
    return _normalize(value)
        .split(' ')
        .where((token) => token.length > 1 && !_stopWords.contains(token))
        .toSet();
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _compactValue(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isUnknownValue(String value, {required bool isAuthor}) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) return true;
    if (isAuthor) {
      return normalized == 'unknown author' || normalized == 'unknown';
    }
    return normalized == 'unknown title' || normalized == 'untitled';
  }

  // --- Helpers ---

  Future<File> _getMetadataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _metadataFileName));
  }

  Future<Directory> _getCoversDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory(p.join(dir.path, _coversDirName));
  }

  Future<String> _saveCoverBytes({
    required String bookId,
    required String source,
    required List<int> bytes,
    String extension = '.jpg',
  }) async {
    final coversDir = await _getCoversDirectory();
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final safeSource = source.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final safeExtension = extension.startsWith('.') ? extension : '.$extension';
    final outPath = p.join(
      coversDir.path,
      '${bookId}_${safeSource}_${DateTime.now().millisecondsSinceEpoch}$safeExtension',
    );
    await File(outPath).writeAsBytes(bytes, flush: true);
    return outPath;
  }

  String _extensionForCoverFile(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    const allowed = {'.jpg', '.jpeg', '.png', '.webp'};
    return allowed.contains(extension) ? extension : '.jpg';
  }

  String _extensionForCoverResource({
    required String mediaType,
    required String path,
  }) {
    switch (mediaType.toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/svg+xml':
        return '.svg';
    }
    return _extensionForCoverFile(path);
  }

  Future<void> _save() async {
    final file = await _getMetadataFile();
    final data = _cache.map((key, value) => MapEntry(key, value.toMap()));
    await file.writeAsString(json.encode(data));
  }

  /// Cleans obscure filenames into presentable titles
  /// Example: "the_great_gatsby_v2.epub" -> "The Great Gatsby V2"
  String _cleanFileName(String filename) {
    var name = filename.replaceAll('.epub', '');
    // remove stuff in brackets
    name = name.replaceAll(RegExp(r'\[.*?\]'), '');
    name = name.replaceAll(RegExp(r'\(.*?\)'), '');
    name = name.replaceAll('_', ' ');
    name = name.replaceAll('-', ' ');
    name = name.trim();

    // Capitalize words
    if (name.isEmpty) return 'Unknown Title';
    return name
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');
  }

  static const _stopWords = {
    'a',
    'an',
    'and',
    'book',
    'by',
    'of',
    'the',
    'volume',
  };
}
