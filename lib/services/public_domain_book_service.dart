import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/public_domain_book.dart';
import '../utils/person_name_utils.dart';
import 'api_client.dart';

class PublicDomainBookService {
  PublicDomainBookService({http.Client? client})
    : _client = ApiClient(
        client: client,
        minIntervalByHost: const {'gutendex.com': Duration(milliseconds: 800)},
      );

  static const userAgent = ApiClient.userAgent;
  static const _baseUri = 'gutendex.com';
  static const _cachePrefix = 'gutendex_cache_v1_';
  static const _detailCachePrefix = 'gutendex_detail_cache_v1_';
  static const _defaultCacheTtl = Duration(hours: 24);
  static const _searchCacheTtl = Duration(hours: 12);
  static const _detailCacheTtl = Duration(days: 30);
  static const _minimumAutomaticPrefetchInterval = Duration(minutes: 30);
  static const _maxAutomaticExactAuthorPages = 2;

  static bool _hasPrefetchedDefaultThisSession = false;
  static DateTime? _lastAutomaticPrefetchAt;
  static final Map<String, Future<PublicDomainBookPage>> _inFlightRequests = {};

  final ApiClient _client;

  Future<PublicDomainBookPage?> readCachedBooks({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(query: query, page: page));
    if (raw == null) return null;

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PublicDomainBookPage.fromCache(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isCacheFresh({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedAt = prefs.getInt(_cacheTimestampKey(query: query, page: page));
    if (cachedAt == null) return false;

    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(cachedAt),
    );
    return age <= _ttlFor(query);
  }

  Future<PublicDomainBookPage> fetchBooks({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    final normalizedAuthor = _normalizePersonName(query.exactAuthor);
    var sourcePage = page;
    var sourcePageUrl = pageUrl;

    while (true) {
      final result = await _fetchRemoteBooks(
        query: query,
        page: sourcePage,
        pageUrl: sourcePageUrl,
      );
      final filteredBooks = normalizedAuthor == null
          ? result.books
          : result.books
                .where((book) {
                  return book.authorDetails.any(
                    (author) =>
                        _normalizePersonName(author.name) == normalizedAuthor,
                  );
                })
                .toList(growable: false);

      if (normalizedAuthor == null ||
          filteredBooks.isNotEmpty ||
          !result.hasNextPage) {
        return PublicDomainBookPage(
          books: filteredBooks,
          count: result.count,
          hasNextPage: result.hasNextPage,
          page: sourcePage,
          nextUrl: result.nextUrl,
          previousUrl: result.previousUrl,
        );
      }

      if (sourcePage - page + 1 >= _maxAutomaticExactAuthorPages) {
        return PublicDomainBookPage(
          books: filteredBooks,
          count: result.count,
          hasNextPage: result.hasNextPage,
          page: sourcePage,
          nextUrl: result.nextUrl,
          previousUrl: result.previousUrl,
        );
      }

      sourcePage += 1;
      sourcePageUrl = result.nextUrl;
    }
  }

  Future<PublicDomainBookPage> fetchBooksAndCache({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    final key = _cacheKey(query: query, page: page);
    final existing = _inFlightRequests[key];
    if (existing != null) return existing;

    final request = _fetchAndStoreBooks(
      query: query,
      page: page,
      pageUrl: pageUrl,
    );
    _inFlightRequests[key] = request;
    try {
      return await request;
    } finally {
      _inFlightRequests.remove(key);
    }
  }

  Future<PublicDomainBookPage> fetchBooksCacheFirst({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    final cached = await readCachedBooks(query: query, page: page);
    if (cached != null && await isCacheFresh(query: query, page: page)) {
      return cached;
    }

    try {
      return await fetchBooksAndCache(
        query: query,
        page: page,
        pageUrl: pageUrl,
      );
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<void> maybePrefetchDefaultList() async {
    if (_hasPrefetchedDefaultThisSession) return;

    final now = DateTime.now();
    final lastPrefetchAt = _lastAutomaticPrefetchAt;
    if (lastPrefetchAt != null &&
        now.difference(lastPrefetchAt) < _minimumAutomaticPrefetchInterval) {
      return;
    }

    if (await isCacheFresh()) return;

    _hasPrefetchedDefaultThisSession = true;
    _lastAutomaticPrefetchAt = now;

    try {
      await fetchBooksAndCache();
    } catch (_) {
      // Automatic warming should never surface errors or block the caller.
    }
  }

  Future<PublicDomainBook> fetchBookDetails(int id) async {
    final cached = await _readCachedBookDetails(id);
    if (cached != null && await _isBookDetailsCacheFresh(id)) return cached;

    try {
      final book = await _fetchRemoteBookDetails(id);
      await _storeBookDetails(id, book);
      return book;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<PublicDomainBook> _fetchRemoteBookDetails(int id) async {
    final uri = Uri.https(_baseUri, '/books/$id');
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw PublicDomainBookServiceException(
        'Book details request failed (${response.statusCode})',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PublicDomainBookServiceException('Invalid book details');
    }

    if (!_isPublicDomainEpub(decoded)) {
      throw const PublicDomainBookServiceException(
        'This book is not available as a public-domain EPUB',
      );
    }

    return PublicDomainBook.fromGutendex(decoded);
  }

  Future<PublicDomainBookPage> _fetchRemoteBooks({
    required PublicDomainBookQuery query,
    required int page,
    String? pageUrl,
  }) async {
    final params = <String, String>{
      'copyright': 'false',
      'mime_type': 'application/epub+zip',
      'page': page.toString(),
      'sort': _sortValue(query.sort),
    };

    if (query.languageCode != null && query.languageCode!.trim().isNotEmpty) {
      params['languages'] = query.languageCode!;
    }

    final seededText = _seededText(query);
    if (seededText != null) {
      final key = query.searchMode == PublicDomainSearchMode.topic
          ? 'topic'
          : 'search';
      params[key] = seededText;
    }

    final parsedPageUri = pageUrl == null ? null : Uri.tryParse(pageUrl);
    final uri = parsedPageUri ?? Uri.https(_baseUri, '/books', params);
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw PublicDomainBookServiceException(
        'Book catalog request failed (${response.statusCode})',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PublicDomainBookServiceException('Invalid catalog response');
    }

    final rawResults = decoded['results'];
    if (rawResults is! List) {
      throw const PublicDomainBookServiceException('Missing catalog results');
    }

    final books = rawResults
        .whereType<Map<String, dynamic>>()
        .where(_isPublicDomainEpub)
        .map(PublicDomainBook.fromGutendex)
        .toList(growable: false);

    return PublicDomainBookPage(
      books: books,
      count: (decoded['count'] as num?)?.toInt() ?? books.length,
      hasNextPage: decoded['next'] is String,
      page: page,
      nextUrl: decoded['next'] as String?,
      previousUrl: decoded['previous'] as String?,
    );
  }

  Future<PublicDomainBookPage> _fetchAndStoreBooks({
    required PublicDomainBookQuery query,
    required int page,
    String? pageUrl,
  }) async {
    final result = await fetchBooks(query: query, page: page, pageUrl: pageUrl);
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKey(query: query, page: page);
    await prefs.setString(key, json.encode(result.toCacheJson()));
    await prefs.setInt(
      _cacheTimestampKey(query: query, page: page),
      DateTime.now().millisecondsSinceEpoch,
    );
    return result;
  }

  String? _seededText(PublicDomainBookQuery query) {
    final trimmedText = query.trimmedText;
    final exactAuthor = query.exactAuthor?.trim();

    if (exactAuthor != null &&
        exactAuthor.isNotEmpty &&
        trimmedText.isNotEmpty) {
      return '$exactAuthor $trimmedText';
    }
    if (exactAuthor != null && exactAuthor.isNotEmpty) {
      return exactAuthor;
    }
    if (trimmedText.isNotEmpty) {
      return trimmedText;
    }
    return null;
  }

  Duration _ttlFor(PublicDomainBookQuery query) {
    return query.hasText ? _searchCacheTtl : _defaultCacheTtl;
  }

  String _cacheKey({required PublicDomainBookQuery query, required int page}) {
    return '$_cachePrefix${query.cacheKey}_page_$page';
  }

  String _cacheTimestampKey({
    required PublicDomainBookQuery query,
    required int page,
  }) {
    return '${_cacheKey(query: query, page: page)}_cached_at';
  }

  Future<PublicDomainBook?> _readCachedBookDetails(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_detailCachePrefix$id');
    if (raw == null) return null;

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PublicDomainBook.fromCache(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isBookDetailsCacheFresh(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedAt = prefs.getInt('$_detailCachePrefix${id}_cached_at');
    if (cachedAt == null) return false;

    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(cachedAt),
    );
    return age <= _detailCacheTtl;
  }

  Future<void> _storeBookDetails(int id, PublicDomainBook book) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_detailCachePrefix$id',
      json.encode(book.toCacheJson()),
    );
    await prefs.setInt(
      '$_detailCachePrefix${id}_cached_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool _isPublicDomainEpub(Map<String, dynamic> json) {
    if (json['copyright'] != false) return false;

    final formats = json['formats'];
    if (formats is! Map<String, dynamic>) return false;

    return formats.keys.any(
      (key) => key.toLowerCase().startsWith('application/epub+zip'),
    );
  }

  String _sortValue(PublicDomainSort sort) {
    switch (sort) {
      case PublicDomainSort.popular:
        return 'popular';
      case PublicDomainSort.ascending:
        return 'ascending';
      case PublicDomainSort.descending:
        return 'descending';
    }
  }

  String? _normalizePersonName(String? raw) {
    final trimmed = normalizePersonNameForDisplay(raw ?? '').toLowerCase();
    if (trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  Map<String, String> get _headers => const {
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };
}

class PublicDomainBookServiceException implements Exception {
  final String message;

  const PublicDomainBookServiceException(this.message);

  @override
  String toString() => message;
}
