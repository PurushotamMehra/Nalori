import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/public_domain_book.dart';
import '../models/public_domain_catalog.dart';
import 'public_domain_catalog_normalizer.dart';

class PublicDomainCatalogDatabase {
  PublicDomainCatalogDatabase({
    DatabaseFactory? databaseFactory,
    String? databasePath,
    this.pageSize = 25,
  }) : _databaseFactory = databaseFactory,
       _databasePath = databasePath {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Must be positive');
    }
  }

  static const schemaVersion = 1;

  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;
  final int pageSize;
  Database? _db;

  Future<bool> exists() async {
    final path = await _path();
    final factory = _databaseFactory ?? databaseFactory;
    return factory.databaseExists(path);
  }

  Future<void> open() async {
    if (_db != null) return;
    final factory = _databaseFactory ?? databaseFactory;
    _db = await factory.openDatabase(
      await _path(),
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, _) async => createSchema(db),
      ),
    );
    await validateSchema();
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  Future<void> validateSchema() async {
    final db = await _database();
    final rows = await db.query(
      'catalog_meta',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['schema_version'],
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.single['value']?.toString();
    if (value != schemaVersion.toString()) {
      throw const FormatException('Unsupported Gutenberg catalogue schema');
    }
  }

  Future<Map<String, String>> meta() async {
    final db = await _database();
    final rows = await db.query('catalog_meta');
    return {
      for (final row in rows)
        row['key'].toString(): row['value']?.toString() ?? '',
    };
  }

  Future<void> seedForTests({
    required List<PublicDomainBook> books,
    String catalogVersion = 'fixture',
  }) async {
    final db = await _database();
    await db.transaction((txn) async {
      await createSchema(txn);
      await txn.delete('book_authors');
      await txn.delete('book_topics');
      await txn.delete('book_languages');
      await txn.delete('books');
      await txn.delete('catalog_meta');
      await txn.insert('catalog_meta', {
        'key': 'schema_version',
        'value': schemaVersion.toString(),
      });
      await txn.insert('catalog_meta', {
        'key': 'catalog_version',
        'value': catalogVersion,
      });
      await txn.insert('catalog_meta', {
        'key': 'record_count',
        'value': books.length.toString(),
      });
      for (final book in books) {
        await insertBook(txn, book);
      }
    });
  }

  Future<PublicDomainCatalogPage> query({
    required PublicDomainBookQuery query,
    PublicDomainCatalogCursor cursor = const PublicDomainCatalogCursor(),
  }) async {
    final db = await _database();
    final where = <String>['b.epub_url != ""'];
    final args = <Object?>[];

    final languageCode = query.languageCode?.trim().toLowerCase();
    if (languageCode != null && languageCode.isNotEmpty) {
      where.add(
        'EXISTS (SELECT 1 FROM book_languages bl '
        'WHERE bl.book_id = b.id AND bl.language = ?)',
      );
      args.add(languageCode);
    }

    final exactAuthor = query.exactAuthor;
    if (exactAuthor != null && exactAuthor.trim().isNotEmpty) {
      where.add(
        'EXISTS (SELECT 1 FROM book_authors ba '
        'WHERE ba.book_id = b.id AND ba.normalized_name = ?)',
      );
      args.add(normalizeCatalogPersonName(exactAuthor));
    }

    final tokens = catalogSearchTokens(query.trimmedText);
    for (final token in tokens) {
      where.add(
        query.searchMode == PublicDomainSearchMode.topic
            ? 'b.topics_search LIKE ?'
            : 'b.title_author_search LIKE ?',
      );
      args.add('%$token%');
    }

    final whereSql = where.join(' AND ');
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM books b WHERE $whereSql',
      args,
    );
    final total = (countRows.single['total'] as num?)?.toInt() ?? 0;
    final orderBy = switch (query.sort) {
      PublicDomainSort.popular => 'b.download_count DESC, b.id ASC',
      PublicDomainSort.ascending => 'b.id ASC',
      PublicDomainSort.descending => 'b.id DESC',
    };
    final rows = await db.rawQuery(
      'SELECT b.* FROM books b WHERE $whereSql '
      'ORDER BY $orderBy LIMIT ? OFFSET ?',
      [...args, pageSize, cursor.offset],
    );
    final books = await _booksFromRows(db, rows);
    final nextCursor = cursor.next(books.length);

    return PublicDomainCatalogPage(
      books: books,
      totalCount: total,
      cursor: nextCursor,
      hasMoreLocal: nextCursor.offset < total,
      sourceKind: PublicDomainCatalogSourceKind.installed,
      status: PublicDomainCatalogStatus.fullInstalled,
    );
  }

  Future<PublicDomainBook?> bookById(int id) async {
    final db = await _database();
    final rows = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return (await _booksFromRows(db, rows)).single;
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.insert('catalog_meta', {
      'key': 'schema_version',
      'value': schemaVersion.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS books (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        summary TEXT,
        cover_url TEXT,
        epub_url TEXT NOT NULL,
        download_count INTEGER NOT NULL DEFAULT 0,
        media_type TEXT,
        title_search TEXT NOT NULL,
        title_author_search TEXT NOT NULL,
        topics_search TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_authors (
        book_id INTEGER NOT NULL,
        ordinal INTEGER NOT NULL,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL,
        birth_year INTEGER,
        death_year INTEGER,
        PRIMARY KEY (book_id, ordinal)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_languages (
        book_id INTEGER NOT NULL,
        language TEXT NOT NULL,
        PRIMARY KEY (book_id, language)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS book_topics (
        book_id INTEGER NOT NULL,
        kind TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        value TEXT NOT NULL,
        normalized_value TEXT NOT NULL,
        PRIMARY KEY (book_id, kind, ordinal)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_books_downloads '
      'ON books(download_count DESC, id ASC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_book_authors_norm '
      'ON book_authors(normalized_name, book_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_book_languages '
      'ON book_languages(language, book_id)',
    );
  }

  static Future<void> insertBook(
    DatabaseExecutor db,
    PublicDomainBook book,
  ) async {
    final authorsSearch = book.authorDetails.isNotEmpty
        ? book.authorDetails.map((author) => author.name).join(' ')
        : book.authors.join(' ');
    final topics = [...book.subjects, ...book.bookshelves];
    await db.insert('books', {
      'id': book.id,
      'title': book.title,
      'summary': book.summary,
      'cover_url': book.coverUrl,
      'epub_url': book.epubUrl,
      'download_count': book.downloadCount,
      'media_type': book.mediaType,
      'title_search': normalizeCatalogText(book.title),
      'title_author_search': normalizeCatalogText(
        '${book.title} $authorsSearch',
      ),
      'topics_search': normalizeCatalogText(topics.join(' ')),
    });
    final authorDetails = book.authorDetails.isNotEmpty
        ? book.authorDetails
        : [for (final author in book.authors) PublicDomainPerson(name: author)];
    for (var index = 0; index < authorDetails.length; index += 1) {
      final author = authorDetails[index];
      await db.insert('book_authors', {
        'book_id': book.id,
        'ordinal': index,
        'name': author.name,
        'normalized_name': normalizeCatalogPersonName(author.name),
        'birth_year': author.birthYear,
        'death_year': author.deathYear,
      });
    }
    for (final language in book.languages) {
      final normalized = language.trim().toLowerCase();
      if (normalized.isEmpty) continue;
      await db.insert('book_languages', {
        'book_id': book.id,
        'language': normalized,
      });
    }
    await _insertTopics(db, book.id, 'subject', book.subjects);
    await _insertTopics(db, book.id, 'bookshelf', book.bookshelves);
  }

  static Future<void> _insertTopics(
    DatabaseExecutor db,
    int bookId,
    String kind,
    List<String> values,
  ) async {
    for (var index = 0; index < values.length; index += 1) {
      final value = values[index].trim();
      if (value.isEmpty) continue;
      await db.insert('book_topics', {
        'book_id': bookId,
        'kind': kind,
        'ordinal': index,
        'value': value,
        'normalized_value': normalizeCatalogText(value),
      });
    }
  }

  Future<List<PublicDomainBook>> _booksFromRows(
    Database db,
    List<Map<String, Object?>> rows,
  ) async {
    final books = <PublicDomainBook>[];
    for (final row in rows) {
      final id = (row['id'] as num).toInt();
      final authors = await db.query(
        'book_authors',
        where: 'book_id = ?',
        whereArgs: [id],
        orderBy: 'ordinal ASC',
      );
      final languages = await db.query(
        'book_languages',
        where: 'book_id = ?',
        whereArgs: [id],
        orderBy: 'language ASC',
      );
      final topics = await db.query(
        'book_topics',
        where: 'book_id = ?',
        whereArgs: [id],
        orderBy: 'kind ASC, ordinal ASC',
      );
      final authorDetails = authors
          .map(
            (author) => PublicDomainPerson(
              name: author['name'].toString(),
              birthYear: (author['birth_year'] as num?)?.toInt(),
              deathYear: (author['death_year'] as num?)?.toInt(),
            ),
          )
          .toList(growable: false);
      books.add(
        PublicDomainBook(
          id: id,
          title: row['title'].toString(),
          authors: authorDetails
              .map((author) => author.name)
              .toList(growable: false),
          authorDetails: authorDetails,
          summary: row['summary']?.toString(),
          subjects: topics
              .where((topic) => topic['kind'] == 'subject')
              .map((topic) => topic['value'].toString())
              .toList(growable: false),
          bookshelves: topics
              .where((topic) => topic['kind'] == 'bookshelf')
              .map((topic) => topic['value'].toString())
              .toList(growable: false),
          languages: languages
              .map((language) => language['language'].toString())
              .toList(growable: false),
          coverUrl: row['cover_url']?.toString(),
          epubUrl: row['epub_url'].toString(),
          downloadCount: (row['download_count'] as num?)?.toInt() ?? 0,
          mediaType: row['media_type']?.toString(),
        ),
      );
    }
    return books;
  }

  Future<Database> _database() async {
    await open();
    return _db!;
  }

  Future<String> _path() async {
    final explicit = _databasePath;
    if (explicit != null) return explicit;
    final dir = await getApplicationDocumentsDirectory();
    final catalogDir = p.join(dir.path, 'gutenberg_catalog');
    await Directory(catalogDir).create(recursive: true);
    return p.join(catalogDir, 'catalog.sqlite');
  }
}
