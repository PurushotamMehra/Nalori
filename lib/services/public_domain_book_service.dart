import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/public_domain_book.dart';
import '../utils/person_name_utils.dart';
import 'api_client.dart';

class PublicDomainBookService {
  PublicDomainBookService({
    http.Client? client,
    AssetBundle? assetBundle,
    Duration catalogTimeout = _catalogTimeout,
    int catalogMaxRetries = _catalogMaxRetries,
  }) : _catalogTimeoutForRequest = catalogTimeout,
       _catalogMaxRetriesForRequest = catalogMaxRetries,
       _assetBundle = assetBundle ?? rootBundle,
       _client = ApiClient(
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
  static const _catalogTimeout = Duration(seconds: 20);
  static const _catalogMaxRetries = 1;
  static const _bundledCatalogAsset =
      'assets/catalog/gutenberg_starter_catalog.json';

  static bool _hasPrefetchedDefaultThisSession = false;
  static DateTime? _lastAutomaticPrefetchAt;
  static final Map<String, Future<PublicDomainBookPage>> _inFlightRequests = {};

  final ApiClient _client;
  final AssetBundle _assetBundle;
  final Duration _catalogTimeoutForRequest;
  final int _catalogMaxRetriesForRequest;

  Future<PublicDomainBookPage?> readBundledBooks({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
  }) async {
    try {
      final raw = await _assetBundle.loadString(_bundledCatalogAsset);
      final decoded = json.decode(raw);
      final rawBooks = decoded is Map<String, dynamic>
          ? decoded['books']
          : decoded;
      if (rawBooks is! List) return null;

      final books = <PublicDomainBook>[];
      for (final rawBook in rawBooks) {
        if (rawBook is! Map) continue;
        try {
          final book = PublicDomainBook.fromCache(
            Map<String, dynamic>.from(rawBook),
          );
          if (!_isEligibleBundledBook(book, query: query)) continue;
          books.add(book);
        } catch (_) {
          continue;
        }
      }

      final sorted = _sortLocalBooks(books, query.sort);
      return PublicDomainBookPage(
        books: sorted,
        count: sorted.length,
        hasNextPage: false,
        page: 1,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Bundled Gutenberg catalog load failed: $error');
      }
      return null;
    }
  }

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
    final params = <String, String>{};

    if (pageUrl == null) {
      final seededText = _seededText(query);
      if (seededText != null) {
        final key = query.searchMode == PublicDomainSearchMode.topic
            ? 'topic'
            : 'search';
        params[key] = seededText;
      }
      if (query.sort != PublicDomainSort.popular) {
        params['sort'] = _sortValue(query.sort);
      }
      if (page > 1) {
        params['page'] = page.toString();
      }
    }

    final uri = _catalogUri(page: page, pageUrl: pageUrl, params: params);
    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: _headers,
        timeout: _catalogTimeoutForRequest,
        maxRetries: _catalogMaxRetriesForRequest,
      );
    } on Object catch (error) {
      final category = _categoryForTransportError(error);
      _debugCatalogLog(uri: uri, page: page, category: category, error: error);
      throw PublicDomainBookServiceException(
        _messageForCategory(category),
        category: category,
      );
    }
    if (response.statusCode != 200) {
      final category = _categoryForStatusCode(response.statusCode);
      _debugCatalogLog(
        uri: uri,
        page: page,
        category: category,
        statusCode: response.statusCode,
      );
      throw PublicDomainBookServiceException(
        _messageForCategory(category),
        category: category,
      );
    }

    Object? decoded;
    try {
      decoded = json.decode(response.body);
    } on FormatException catch (error) {
      _debugCatalogLog(
        uri: uri,
        page: page,
        category: PublicDomainCatalogFailureCategory.parsing,
        error: error,
      );
      throw const PublicDomainBookServiceException(
        'The catalog response could not be read.',
        category: PublicDomainCatalogFailureCategory.parsing,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PublicDomainBookServiceException(
        'The catalog returned an invalid response.',
        category: PublicDomainCatalogFailureCategory.invalidResponse,
      );
    }

    final rawResults = decoded['results'];
    if (rawResults is! List) {
      throw const PublicDomainBookServiceException(
        'The catalog returned an invalid response.',
        category: PublicDomainCatalogFailureCategory.invalidResponse,
      );
    }

    final books = <PublicDomainBook>[];
    try {
      for (final result in rawResults) {
        if (result is! Map<String, dynamic>) {
          throw const FormatException('Catalog result is not an object');
        }
        if (!_isEligibleBookResult(result, query: query)) continue;
        books.add(PublicDomainBook.fromGutendex(result));
      }
    } on Object catch (error) {
      _debugCatalogLog(
        uri: uri,
        page: page,
        category: PublicDomainCatalogFailureCategory.parsing,
        error: error,
      );
      throw const PublicDomainBookServiceException(
        'The catalog response could not be read.',
        category: PublicDomainCatalogFailureCategory.parsing,
      );
    }

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

  Uri _catalogUri({
    required int page,
    required String? pageUrl,
    required Map<String, String> params,
  }) {
    if (pageUrl == null) {
      return params.isEmpty
          ? _baseBooksUri()
          : Uri.https(_baseUri, '/books/', params);
    }

    final parsed = Uri.tryParse(pageUrl);
    if (parsed == null) {
      return params.isEmpty
          ? _baseBooksUri()
          : Uri.https(_baseUri, '/books/', params);
    }
    if (parsed.hasScheme) return parsed;

    final path = parsed.path.isEmpty ? '/books/' : parsed.path;
    return Uri.https(_baseUri, path, parsed.queryParametersAll);
  }

  Uri _baseBooksUri() {
    return Uri(scheme: 'https', host: _baseUri, path: '/books/');
  }

  PublicDomainCatalogFailureCategory _categoryForTransportError(Object error) {
    if (error is TimeoutException) {
      return PublicDomainCatalogFailureCategory.timeout;
    }
    if (error is SocketException || error is http.ClientException) {
      return PublicDomainCatalogFailureCategory.network;
    }
    return PublicDomainCatalogFailureCategory.unknown;
  }

  PublicDomainCatalogFailureCategory _categoryForStatusCode(int statusCode) {
    if (statusCode >= 500 || statusCode == 429) {
      return PublicDomainCatalogFailureCategory.temporaryServer;
    }
    return PublicDomainCatalogFailureCategory.invalidResponse;
  }

  String _messageForCategory(PublicDomainCatalogFailureCategory category) {
    switch (category) {
      case PublicDomainCatalogFailureCategory.timeout:
        return 'The catalog is taking too long to respond.';
      case PublicDomainCatalogFailureCategory.network:
        return 'The catalog could not be reached.';
      case PublicDomainCatalogFailureCategory.temporaryServer:
        return 'The catalog is temporarily unavailable.';
      case PublicDomainCatalogFailureCategory.invalidResponse:
        return 'The catalog returned an invalid response.';
      case PublicDomainCatalogFailureCategory.parsing:
        return 'The catalog response could not be read.';
      case PublicDomainCatalogFailureCategory.empty:
        return 'The catalog did not return any books.';
      case PublicDomainCatalogFailureCategory.cacheFallback:
        return 'Showing saved Project Gutenberg results.';
      case PublicDomainCatalogFailureCategory.pagination:
        return 'More books could not be loaded.';
      case PublicDomainCatalogFailureCategory.unknown:
        return 'The catalog could not be loaded.';
    }
  }

  void _debugCatalogLog({
    required Uri uri,
    required int page,
    required PublicDomainCatalogFailureCategory category,
    Object? error,
    int? statusCode,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      'Gutendex catalog request failed: url=$uri page=$page '
      'category=${category.name} status=$statusCode error=$error',
    );
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

  bool _isEligibleBookResult(
    Map<String, dynamic> json, {
    required PublicDomainBookQuery query,
  }) {
    if (!_isPublicDomainEpub(json)) return false;

    final languageCode = query.languageCode?.trim().toLowerCase();
    if (languageCode == null || languageCode.isEmpty) return true;

    final languages = json['languages'];
    if (languages is! List) return false;
    return languages
        .whereType<String>()
        .map((value) => value.trim().toLowerCase())
        .contains(languageCode);
  }

  bool _isEligibleBundledBook(
    PublicDomainBook book, {
    required PublicDomainBookQuery query,
  }) {
    if (book.epubUrl.trim().isEmpty) return false;
    final parsedUrl = Uri.tryParse(book.epubUrl);
    if (parsedUrl == null || !parsedUrl.hasScheme) return false;

    final languageCode = query.languageCode?.trim().toLowerCase();
    if (languageCode != null && languageCode.isNotEmpty) {
      final languages = book.languages
          .map((value) => value.trim().toLowerCase())
          .toSet();
      if (!languages.contains(languageCode)) return false;
    }

    final normalizedAuthor = _normalizePersonName(query.exactAuthor);
    if (normalizedAuthor != null) {
      final hasAuthor = book.authorDetails.any(
        (author) => _normalizePersonName(author.name) == normalizedAuthor,
      );
      if (!hasAuthor) return false;
    }

    final searchText = query.trimmedText.toLowerCase();
    if (searchText.isEmpty) return true;

    final searchable = query.searchMode == PublicDomainSearchMode.topic
        ? [...book.subjects, ...book.bookshelves].join(' ')
        : [
            book.title,
            ...book.authors,
            ...book.authorDetails.map((author) => author.name),
          ].join(' ');
    return searchable.toLowerCase().contains(searchText);
  }

  List<PublicDomainBook> _sortLocalBooks(
    List<PublicDomainBook> books,
    PublicDomainSort sort,
  ) {
    final sorted = books.toList(growable: false);
    switch (sort) {
      case PublicDomainSort.popular:
        sorted.sort((a, b) => b.downloadCount.compareTo(a.downloadCount));
        break;
      case PublicDomainSort.ascending:
        sorted.sort((a, b) => a.id.compareTo(b.id));
        break;
      case PublicDomainSort.descending:
        sorted.sort((a, b) => b.id.compareTo(a.id));
        break;
    }
    return sorted;
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

enum PublicDomainCatalogFailureCategory {
  timeout,
  network,
  temporaryServer,
  invalidResponse,
  parsing,
  empty,
  cacheFallback,
  pagination,
  unknown,
}

class PublicDomainBookServiceException implements Exception {
  final String message;
  final PublicDomainCatalogFailureCategory category;

  const PublicDomainBookServiceException(
    this.message, {
    this.category = PublicDomainCatalogFailureCategory.unknown,
  });

  @override
  String toString() => message;
}
