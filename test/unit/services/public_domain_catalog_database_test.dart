import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/public_domain_book.dart';
import 'package:nalori/services/public_domain_catalog_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late PublicDomainCatalogDatabase catalog;
  var sqliteAvailable = true;

  setUpAll(() async {
    sqfliteFfiInit();
    try {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.close();
    } catch (_) {
      sqliteAvailable = false;
    }
  });

  setUp(() async {
    if (!sqliteAvailable) return;
    tempDir = await Directory.systemTemp.createTemp('nalori_catalog_db_');
    catalog = PublicDomainCatalogDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(tempDir.path, 'catalog.sqlite'),
      pageSize: 2,
    );
    await catalog.open();
    await catalog.seedForTests(books: _fixtureBooks());
  });

  tearDown(() async {
    if (!sqliteAvailable) return;
    await catalog.close();
    await tempDir.delete(recursive: true);
  });

  test('title search runs across records beyond the first page', () async {
    if (!sqliteAvailable) return;
    final page = await catalog.query(
      query: const PublicDomainBookQuery(text: 'hidden island'),
    );

    expect(page.books.map((book) => book.id), [700]);
    expect(page.totalCount, 1);
  });

  test(
    'author search and case punctuation normalization are correct',
    () async {
      if (!sqliteAvailable) return;
      final page = await catalog.query(
        query: const PublicDomainBookQuery(text: 'JULES, VERNE'),
      );

      expect(page.books.map((book) => book.id), [300, 700]);
    },
  );

  test('exact-author matching uses normalized identity', () async {
    if (!sqliteAvailable) return;
    final page = await catalog.query(
      query: const PublicDomainBookQuery(exactAuthor: 'Verne, Jules'),
    );

    expect(page.books.map((book) => book.id), [300, 700]);
  });

  test('exact-author plus text search narrows within that author', () async {
    if (!sqliteAvailable) return;
    final page = await catalog.query(
      query: const PublicDomainBookQuery(
        exactAuthor: 'Verne, Jules',
        text: 'island',
      ),
    );

    expect(page.books.map((book) => book.id), [700]);
  });

  test('topic search includes subjects and bookshelves', () async {
    if (!sqliteAvailable) return;
    final subjectPage = await catalog.query(
      query: const PublicDomainBookQuery(
        text: 'sea adventure',
        searchMode: PublicDomainSearchMode.topic,
      ),
    );
    final shelfPage = await catalog.query(
      query: const PublicDomainBookQuery(
        text: 'science fiction',
        searchMode: PublicDomainSearchMode.topic,
      ),
    );

    expect(subjectPage.books.map((book) => book.id), [300]);
    expect(shelfPage.books.map((book) => book.id), [700]);
  });

  test('language filtering is applied before sorting and pagination', () async {
    if (!sqliteAvailable) return;
    final page = await catalog.query(
      query: const PublicDomainBookQuery(languageCode: 'fr'),
    );

    expect(page.books.map((book) => book.id), [900]);
    expect(page.totalCount, 1);
  });

  test(
    'popular sorting happens before pagination with deterministic ties',
    () async {
      if (!sqliteAvailable) return;
      const query = PublicDomainBookQuery(languageCode: null);
      final first = await catalog.query(query: query);
      final second = await catalog.query(query: query, cursor: first.cursor);

      expect(first.books.map((book) => book.id), [200, 300]);
      expect(first.hasMoreLocal, isTrue);
      expect(second.books.map((book) => book.id), [700, 900]);
    },
  );

  test(
    'oldest and newest ID sorting use the complete fixture catalogue',
    () async {
      if (!sqliteAvailable) return;
      final oldest = await catalog.query(
        query: const PublicDomainBookQuery(
          languageCode: null,
          sort: PublicDomainSort.ascending,
        ),
      );
      final newest = await catalog.query(
        query: const PublicDomainBookQuery(
          languageCode: null,
          sort: PublicDomainSort.descending,
        ),
      );

      expect(oldest.books.map((book) => book.id), [200, 300]);
      expect(newest.books.map((book) => book.id), [900, 700]);
    },
  );

  test('no-result queries return empty deterministic pages', () async {
    if (!sqliteAvailable) return;
    final page = await catalog.query(
      query: const PublicDomainBookQuery(text: 'no such title'),
    );

    expect(page.books, isEmpty);
    expect(page.totalCount, 0);
    expect(page.hasMoreLocal, isFalse);
  });
}

List<PublicDomainBook> _fixtureBooks() {
  return const [
    PublicDomainBook(
      id: 200,
      title: 'Early Popular Work',
      authors: ['Jane Austen'],
      authorDetails: [PublicDomainPerson(name: 'Jane Austen')],
      subjects: ['Courtship -- Fiction'],
      bookshelves: ['Best Books Ever Listings'],
      languages: ['en'],
      epubUrl: 'https://www.gutenberg.org/ebooks/200.epub3.images',
      downloadCount: 50,
      mediaType: 'Text',
    ),
    PublicDomainBook(
      id: 300,
      title: 'Twenty Thousand Leagues Under the Seas',
      authors: ['Jules Verne'],
      authorDetails: [PublicDomainPerson(name: 'Jules Verne')],
      subjects: ['Sea stories', 'Adventure stories'],
      bookshelves: ['Adventure'],
      languages: ['en'],
      epubUrl: 'https://www.gutenberg.org/ebooks/300.epub.images',
      downloadCount: 40,
      mediaType: 'Text',
    ),
    PublicDomainBook(
      id: 700,
      title: 'The Hidden Island',
      authors: ['Jules Verne'],
      authorDetails: [PublicDomainPerson(name: 'Jules Verne')],
      subjects: ['Islands -- Fiction'],
      bookshelves: ['Science Fiction'],
      languages: ['en'],
      epubUrl: 'https://www.gutenberg.org/ebooks/700.epub.images',
      downloadCount: 40,
      mediaType: 'Text',
    ),
    PublicDomainBook(
      id: 900,
      title: 'Voyage Extraordinaire',
      authors: ['Auteur Test'],
      authorDetails: [PublicDomainPerson(name: 'Auteur Test')],
      subjects: ['Voyages imaginaires'],
      bookshelves: ['French Fiction'],
      languages: ['fr'],
      epubUrl: 'https://www.gutenberg.org/ebooks/900.epub.images',
      downloadCount: 30,
      mediaType: 'Text',
    ),
  ];
}
