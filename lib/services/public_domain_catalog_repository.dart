import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/public_domain_book.dart';
import '../models/public_domain_catalog.dart';
import 'public_domain_catalog_database.dart';
import 'public_domain_catalog_normalizer.dart';

class PublicDomainCatalogRepository {
  PublicDomainCatalogRepository({
    PublicDomainCatalogDatabase? database,
    AssetBundle? assetBundle,
    this.pageSize = 25,
  }) : _database = database,
       _assetBundle = assetBundle ?? rootBundle;

  static const bundledCatalogAsset =
      'assets/catalog/gutenberg_starter_catalog.json';

  final PublicDomainCatalogDatabase? _database;
  final AssetBundle _assetBundle;
  final int pageSize;

  List<PublicDomainBook>? _starterBooks;

  Future<PublicDomainCatalogPage> query({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    PublicDomainCatalogCursor cursor = const PublicDomainCatalogCursor(),
  }) async {
    final database = _database;
    if (database != null && await database.exists()) {
      await database.open();
      return database.query(query: query, cursor: cursor);
    }
    return queryStarter(query: query, cursor: cursor);
  }

  Future<PublicDomainBook?> bookById(int id) async {
    final database = _database;
    if (database != null && await database.exists()) {
      await database.open();
      final book = await database.bookById(id);
      if (book != null) return book;
    }
    final starter = await _loadStarterBooks();
    for (final book in starter) {
      if (book.id == id) return book;
    }
    return null;
  }

  Future<PublicDomainCatalogPage> queryStarter({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    PublicDomainCatalogCursor cursor = const PublicDomainCatalogCursor(),
  }) async {
    final filtered = _applyLocalQuery(await _loadStarterBooks(), query);
    final start = cursor.offset.clamp(0, filtered.length);
    final end = (start + pageSize).clamp(0, filtered.length);
    final books = filtered.sublist(start, end);
    final nextCursor = cursor.next(books.length);
    return PublicDomainCatalogPage(
      books: books,
      totalCount: filtered.length,
      cursor: nextCursor,
      hasMoreLocal: nextCursor.offset < filtered.length,
      sourceKind: PublicDomainCatalogSourceKind.starter,
      status: PublicDomainCatalogStatus.starterOnly,
    );
  }

  Future<List<PublicDomainBook>> _loadStarterBooks() async {
    final cached = _starterBooks;
    if (cached != null) return cached;
    try {
      final raw = await _assetBundle.loadString(bundledCatalogAsset);
      final decoded = json.decode(raw);
      final rawBooks = decoded is Map<String, dynamic>
          ? decoded['books']
          : decoded;
      if (rawBooks is! List) return _starterBooks = const [];
      final books = <PublicDomainBook>[];
      final seen = <int>{};
      for (final rawBook in rawBooks) {
        if (rawBook is! Map) continue;
        try {
          final book = PublicDomainBook.fromCache(
            Map<String, dynamic>.from(rawBook),
          );
          final url = Uri.tryParse(book.epubUrl);
          if (url == null || !url.hasScheme || book.epubUrl.trim().isEmpty) {
            continue;
          }
          if (!seen.add(book.id)) continue;
          books.add(book);
        } catch (_) {
          continue;
        }
      }
      return _starterBooks = books;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Bundled Gutenberg catalog load failed: $error');
      }
      return _starterBooks = const [];
    }
  }

  List<PublicDomainBook> _applyLocalQuery(
    List<PublicDomainBook> books,
    PublicDomainBookQuery query,
  ) {
    Iterable<PublicDomainBook> candidates = books;
    final language = query.languageCode?.trim().toLowerCase();
    if (language != null && language.isNotEmpty) {
      candidates = candidates.where(
        (book) => book.languages
            .map((value) => value.trim().toLowerCase())
            .contains(language),
      );
    }

    final exactAuthor = query.exactAuthor;
    if (exactAuthor != null && exactAuthor.trim().isNotEmpty) {
      final normalizedAuthor = normalizeCatalogPersonName(exactAuthor);
      candidates = candidates.where(
        (book) => book.authorDetails.any(
          (author) =>
              normalizeCatalogPersonName(author.name) == normalizedAuthor,
        ),
      );
    }

    final tokens = catalogSearchTokens(query.trimmedText);
    if (tokens.isNotEmpty) {
      candidates = candidates.where((book) {
        final searchable = query.searchMode == PublicDomainSearchMode.topic
            ? normalizeCatalogText(
                [...book.subjects, ...book.bookshelves].join(' '),
              )
            : normalizeCatalogText(
                [
                  book.title,
                  ...book.authors,
                  ...book.authorDetails.map((author) => author.name),
                ].join(' '),
              );
        return tokens.every(searchable.contains);
      });
    }

    final sorted = candidates.toList(growable: false);
    switch (query.sort) {
      case PublicDomainSort.popular:
        sorted.sort((a, b) {
          final popularity = b.downloadCount.compareTo(a.downloadCount);
          if (popularity != 0) return popularity;
          return a.id.compareTo(b.id);
        });
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
}
