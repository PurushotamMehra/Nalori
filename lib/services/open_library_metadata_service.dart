import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class OpenLibraryBookMatch {
  final String title;
  final String author;
  final String? workKey;
  final int? coverId;
  final double confidence;

  const OpenLibraryBookMatch({
    required this.title,
    required this.author,
    required this.confidence,
    this.workKey,
    this.coverId,
  });
}

class BookCoverCandidate {
  final String source;
  final String label;
  final String imageUrl;
  final double confidence;
  final List<int>? imageBytes;

  const BookCoverCandidate({
    required this.source,
    required this.label,
    required this.imageUrl,
    required this.confidence,
    this.imageBytes,
  });

  BookCoverCandidate copyWith({List<int>? imageBytes}) {
    return BookCoverCandidate(
      source: source,
      label: label,
      imageUrl: imageUrl,
      confidence: confidence,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'source': source,
    'label': label,
    'imageUrl': imageUrl,
    'confidence': confidence,
  };

  factory BookCoverCandidate.fromJson(Map<String, dynamic> json) {
    return BookCoverCandidate(
      source: (json['source'] as String?)?.trim() ?? 'open_library',
      label: (json['label'] as String?)?.trim() ?? 'Open Library',
      imageUrl: (json['imageUrl'] as String?)?.trim() ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

class OpenLibraryMetadataService {
  OpenLibraryMetadataService({http.Client? client})
    : _client = ApiClient(
        client: client,
        minIntervalByHost: const {
          'openlibrary.org': Duration(seconds: 1),
          'covers.openlibrary.org': Duration(seconds: 1),
        },
      );

  static const _baseUri = 'openlibrary.org';
  static const _coverBaseUri = 'covers.openlibrary.org';
  static const _userAgent = ApiClient.userAgent;
  static const _minimumConfidence = 0.58;
  static const _highConfidence = 0.84;
  static const _cachePrefix = 'openlibrary_cache_v1_';
  static const _searchCacheTtl = Duration(days: 30);
  static const _negativeCacheTtl = Duration(days: 7);
  static const _coverCandidateCacheTtl = Duration(days: 60);

  final ApiClient _client;
  final Map<String, List<int>> _coverBytesByUrl = {};

  Future<OpenLibraryBookMatch?> findBestMatch({
    required String title,
    required String author,
  }) async {
    final normalizedTitle = _cleanQueryTitle(title, author);
    if (normalizedTitle.isEmpty) return null;

    final docs = await _search(normalizedTitle, author);
    if (docs.isEmpty) return null;

    OpenLibraryBookMatch? best;
    for (final doc in docs) {
      final candidate = _matchFromDoc(
        doc,
        expectedTitle: normalizedTitle,
        expectedAuthor: author,
      );
      if (candidate == null) continue;
      if (best == null || candidate.confidence > best.confidence) {
        best = candidate;
      }
    }

    if (best == null || best.confidence < _minimumConfidence) return null;
    return best;
  }

  bool isHighConfidence(OpenLibraryBookMatch match) {
    return match.confidence >= _highConfidence;
  }

  Future<List<int>?> fetchCoverBytes(int coverId) async {
    final uri = Uri.https(_coverBaseUri, '/b/id/$coverId-M.jpg', {
      'default': 'false',
    });
    final response = await _client.get(uri, headers: _imageHeaders);
    return _validImageBytes(response);
  }

  Future<List<int>?> fetchCoverCandidateBytes(
    BookCoverCandidate candidate,
  ) async {
    if (candidate.imageBytes != null) return candidate.imageBytes;
    final cachedBytes = _coverBytesByUrl[candidate.imageUrl];
    if (cachedBytes != null) return cachedBytes;

    final response = await _client.get(
      Uri.parse(candidate.imageUrl),
      headers: _imageHeaders,
    );
    final bytes = _validImageBytes(response);
    if (bytes != null) _coverBytesByUrl[candidate.imageUrl] = bytes;
    return bytes;
  }

  Future<List<BookCoverCandidate>> findCoverCandidates({
    required String title,
    required String author,
    int limit = 3,
  }) async {
    final normalizedTitle = _cleanQueryTitle(title, author);
    if (normalizedTitle.isEmpty) return const [];

    final cacheKey = _coverCandidateCacheKey(normalizedTitle, author, limit);
    final cached = await _readCachedCoverCandidates(cacheKey);
    if (cached != null) return cached;

    final docs = await _search(normalizedTitle, author);
    if (docs.isEmpty) return const [];

    final candidates = <BookCoverCandidate>[];
    final seenUrls = <String>{};
    for (final doc in docs) {
      final match = _matchFromDoc(
        doc,
        expectedTitle: normalizedTitle,
        expectedAuthor: author,
      );
      if (match == null || match.confidence < 0.42) continue;

      final coverId = (doc['cover_i'] as num?)?.toInt();
      if (coverId != null) {
        final url = _coverUrl('id', coverId.toString());
        if (seenUrls.add(url)) {
          candidates.add(
            BookCoverCandidate(
              source: 'open_library',
              label: match.title,
              imageUrl: url,
              confidence: match.confidence,
            ),
          );
        }
      }

      final editionKey = (doc['cover_edition_key'] as String?)?.trim();
      if (editionKey != null && editionKey.isNotEmpty) {
        final url = _coverUrl('olid', editionKey);
        if (seenUrls.add(url)) {
          candidates.add(
            BookCoverCandidate(
              source: 'open_library',
              label: match.title,
              imageUrl: url,
              confidence: (match.confidence - 0.02).clamp(0.0, 1.0).toDouble(),
            ),
          );
        }
      }
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    final valid = await _validatedCoverCandidates(candidates, limit);
    await _storeCoverCandidates(cacheKey, valid);
    return valid;
  }

  Future<List<BookCoverCandidate>> _validatedCoverCandidates(
    List<BookCoverCandidate> candidates,
    int limit,
  ) async {
    final valid = <BookCoverCandidate>[];
    for (final candidate in candidates) {
      if (valid.length >= limit) break;
      final bytes = await fetchCoverCandidateBytes(candidate);
      if (bytes != null) valid.add(candidate.copyWith(imageBytes: bytes));
    }
    return valid;
  }

  List<int>? _validImageBytes(http.Response response) {
    if (response.statusCode != 200) return null;
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().startsWith('image/')) return null;
    if (response.bodyBytes.length < 256) return null;
    return response.bodyBytes;
  }

  String _coverUrl(String keyType, String key, {String size = 'M'}) {
    return Uri.https(_coverBaseUri, '/b/$keyType/$key-$size.jpg', {
      'default': 'false',
    }).toString();
  }

  Future<List<Map<String, dynamic>>> _search(
    String title,
    String author,
  ) async {
    final params = <String, String>{
      'title': title,
      'limit': '8',
      'fields':
          'key,title,author_name,cover_i,cover_edition_key,first_publish_year,language,isbn',
    };

    final cleanAuthor = author.trim();
    if (cleanAuthor.isNotEmpty && !_isUnknownAuthor(cleanAuthor)) {
      params['author'] = cleanAuthor;
    }

    var docs = await _requestSearch(params);
    if (docs.isNotEmpty || !params.containsKey('author')) return docs;

    final fallbackParams = Map<String, String>.from(params)..remove('author');
    docs = await _requestSearch(fallbackParams);
    return docs;
  }

  Future<List<Map<String, dynamic>>> _requestSearch(
    Map<String, String> params,
  ) async {
    final uri = Uri.https(_baseUri, '/search.json', params);
    final cacheKey = _searchCacheKey(uri);
    final cached = await _readCachedDocs(cacheKey);
    if (cached != null) return cached;

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) return const [];

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final docs = decoded['docs'];
    if (docs is! List) return const [];

    final parsed = docs.whereType<Map<String, dynamic>>().toList(
      growable: false,
    );
    await _storeDocs(cacheKey, parsed);
    return parsed;
  }

  Future<List<Map<String, dynamic>>?> _readCachedDocs(String key) async {
    final cached = await _readCacheEntry(key);
    if (cached == null) return null;

    final rawDocs = cached.value['docs'];
    if (rawDocs is! List) return null;
    final ttl = rawDocs.isEmpty ? _negativeCacheTtl : _searchCacheTtl;
    if (!_isFresh(cached.cachedAt, ttl)) return null;
    return rawDocs
        .whereType<Map>()
        .map((doc) => Map<String, dynamic>.from(doc))
        .toList(growable: false);
  }

  Future<void> _storeDocs(String key, List<Map<String, dynamic>> docs) async {
    await _storeCacheEntry(key, {'docs': docs});
  }

  Future<List<BookCoverCandidate>?> _readCachedCoverCandidates(
    String key,
  ) async {
    final cached = await _readCacheEntry(key);
    if (cached == null || !_isFresh(cached.cachedAt, _coverCandidateCacheTtl)) {
      return null;
    }

    final rawCandidates = cached.value['candidates'];
    if (rawCandidates is! List) return null;
    return rawCandidates
        .whereType<Map>()
        .map(
          (item) =>
              BookCoverCandidate.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((candidate) => candidate.imageUrl.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _storeCoverCandidates(
    String key,
    List<BookCoverCandidate> candidates,
  ) async {
    await _storeCacheEntry(key, {
      'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
    });
  }

  Future<_CachedEntry?> _readCacheEntry(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix$key');
    final cachedAt = prefs.getInt('$_cachePrefix${key}_cached_at');
    if (raw == null || cachedAt == null) return null;

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return _CachedEntry(
        value: decoded,
        cachedAt: DateTime.fromMillisecondsSinceEpoch(cachedAt),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeCacheEntry(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cachePrefix$key', json.encode(value));
    await prefs.setInt(
      '$_cachePrefix${key}_cached_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool _isFresh(DateTime cachedAt, Duration ttl) {
    return DateTime.now().difference(cachedAt) <= ttl;
  }

  String _searchCacheKey(Uri uri) => 'search_${_normalize(uri.toString())}';

  String _coverCandidateCacheKey(String title, String author, int limit) {
    return 'covers_${_normalize('$title|$author|$limit')}';
  }

  OpenLibraryBookMatch? _matchFromDoc(
    Map<String, dynamic> doc, {
    required String expectedTitle,
    required String expectedAuthor,
  }) {
    final title = (doc['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    final authors = (doc['author_name'] as List?)
        ?.whereType<String>()
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList(growable: false);
    final author = authors?.isNotEmpty == true ? authors!.first : '';

    final titleScore = _tokenSimilarity(expectedTitle, title);
    final authorScore =
        expectedAuthor.trim().isEmpty || _isUnknownAuthor(expectedAuthor)
        ? 0.55
        : authors == null || authors.isEmpty
        ? 0.0
        : authors
              .map((candidateAuthor) {
                return _tokenSimilarity(expectedAuthor, candidateAuthor);
              })
              .fold<double>(0.0, (best, score) => score > best ? score : best);
    final coverBonus = doc['cover_i'] is num ? 0.08 : 0.0;
    final confidence = (titleScore * 0.68) + (authorScore * 0.24) + coverBonus;

    return OpenLibraryBookMatch(
      title: title,
      author: author,
      workKey: doc['key'] as String?,
      coverId: (doc['cover_i'] as num?)?.toInt(),
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
    );
  }

  String _cleanQueryTitle(String title, String author) {
    var cleaned = title.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\.epub$', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    final cleanAuthor = author.trim();
    if (cleanAuthor.isNotEmpty && !_isUnknownAuthor(cleanAuthor)) {
      final authorPattern = RegExp(
        '^${RegExp.escape(cleanAuthor)}\\s*[-–—:]\\s*',
        caseSensitive: false,
      );
      cleaned = cleaned.replaceFirst(authorPattern, '').trim();
    }

    final dashParts = cleaned
        .split(RegExp(r'\s[-–—]\s'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (dashParts.length == 2 &&
        cleanAuthor.isNotEmpty &&
        !_isUnknownAuthor(cleanAuthor)) {
      final firstLooksLikeAuthor = _tokenSimilarity(
        dashParts.first,
        cleanAuthor,
      );
      final secondLooksLikeAuthor = _tokenSimilarity(
        dashParts.last,
        cleanAuthor,
      );
      if (firstLooksLikeAuthor > 0.7) return dashParts.last;
      if (secondLooksLikeAuthor > 0.7) return dashParts.first;
    }

    return cleaned;
  }

  double _tokenSimilarity(String left, String right) {
    final leftTokens = _tokens(left);
    final rightTokens = _tokens(right);
    if (leftTokens.isEmpty || rightTokens.isEmpty) return 0.0;

    final intersection = leftTokens.intersection(rightTokens).length;
    final union = leftTokens.union(rightTokens).length;
    final jaccard = union == 0 ? 0.0 : intersection / union;
    final containsBonus =
        _normalize(left).contains(_normalize(right)) ||
            _normalize(right).contains(_normalize(left))
        ? 0.18
        : 0.0;
    return (jaccard + containsBonus).clamp(0.0, 1.0);
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

  bool _isUnknownAuthor(String author) {
    final normalized = _normalize(author);
    return normalized.isEmpty ||
        normalized == 'unknown author' ||
        normalized == 'unknown';
  }

  Map<String, String> get _headers => const {
    'Accept': 'application/json',
    'User-Agent': _userAgent,
  };

  Map<String, String> get _imageHeaders => const {
    'Accept':
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'User-Agent': _userAgent,
  };

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

class _CachedEntry {
  final Map<String, dynamic> value;
  final DateTime cachedAt;

  const _CachedEntry({required this.value, required this.cachedAt});
}
