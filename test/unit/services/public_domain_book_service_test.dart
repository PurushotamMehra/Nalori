import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nalori/models/public_domain_book.dart';
import 'package:nalori/services/public_domain_book_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PublicDomainBookService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'requests public-domain English EPUBs and parses rich results',
      () async {
        final service = PublicDomainBookService(
          client: MockClient((request) async {
            expect(request.url.host, 'gutendex.com');
            expect(request.url.path, '/books/');
            expect(
              request.url.queryParameters.containsKey('copyright'),
              isFalse,
            );
            expect(
              request.url.queryParameters.containsKey('languages'),
              isFalse,
            );
            expect(
              request.url.queryParameters.containsKey('mime_type'),
              isFalse,
            );
            expect(request.url.queryParameters['search'], 'austen');
            expect(request.url.queryParameters.containsKey('page'), isFalse);
            expect(request.url.queryParameters.containsKey('sort'), isFalse);
            expect(
              request.headers['User-Agent'],
              contains('naloriapp@gmail.com'),
            );

            return http.Response(
              jsonEncode({
                'count': 1,
                'next': null,
                'previous': null,
                'results': [
                  {
                    'id': 1342,
                    'title': 'Pride and Prejudice',
                    'authors': [
                      {
                        'name': 'Austen, Jane',
                        'birth_year': 1775,
                        'death_year': 1817,
                      },
                    ],
                    'summaries': ['A novel of manners.'],
                    'subjects': ['Courtship -- Fiction'],
                    'bookshelves': ['Best Books Ever Listings'],
                    'languages': ['en'],
                    'translators': [
                      {'name': 'Translator, Test'},
                    ],
                    'editors': [
                      {'name': 'Editor, Test'},
                    ],
                    'copyright': false,
                    'media_type': 'Text',
                    'formats': {
                      'application/epub+zip':
                          'https://www.gutenberg.org/ebooks/1342.epub.images',
                      'image/jpeg':
                          'https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg',
                    },
                    'download_count': 123,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final page = await service.fetchBooks(
          query: const PublicDomainBookQuery(text: 'austen'),
        );

        expect(page.count, 1);
        expect(page.page, 1);
        expect(page.hasNextPage, isFalse);
        expect(page.books, hasLength(1));
        expect(page.books.single.id, 1342);
        expect(page.books.single.title, 'Pride and Prejudice');
        expect(page.books.single.authorLabel, 'Jane Austen');
        expect(
          page.books.single.authorDetails.single.displayLabel,
          contains('1775-1817'),
        );
        expect(page.books.single.bookshelves, ['Best Books Ever Listings']);
        expect(page.books.single.translators.single.name, 'Test Translator');
        expect(page.books.single.editors.single.name, 'Test Editor');
        expect(page.books.single.epubUrl, contains('1342.epub'));
      },
    );

    test('default popular catalog uses unfiltered books endpoint', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          expect(request.url.host, 'gutendex.com');
          expect(request.url.path, '/books/');
          expect(request.url.queryParameters, isEmpty);
          expect(request.url.queryParameters.containsKey('page'), isFalse);
          expect(request.url.queryParameters.containsKey('sort'), isFalse);
          expect(request.url.queryParameters.containsKey('copyright'), isFalse);
          expect(request.url.queryParameters.containsKey('languages'), isFalse);
          expect(request.url.queryParameters.containsKey('mime_type'), isFalse);

          return http.Response(
            _catalogResponse(id: 1, title: 'Default Book'),
            200,
          );
        }),
      );

      final page = await service.fetchBooks();

      expect(page.books.single.title, 'Default Book');
    });

    test('uses topic queries and custom filters', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          expect(request.url.queryParameters['topic'], 'children');
          expect(request.url.queryParameters['sort'], 'descending');
          expect(request.url.queryParameters.containsKey('copyright'), isFalse);
          expect(request.url.queryParameters.containsKey('languages'), isFalse);
          expect(request.url.queryParameters.containsKey('mime_type'), isFalse);
          expect(request.url.queryParameters.containsKey('page'), isFalse);
          expect(request.url.queryParameters.containsKey('search'), isFalse);

          return http.Response(
            jsonEncode({
              'count': 0,
              'next': null,
              'previous': null,
              'results': [],
            }),
            200,
          );
        }),
      );

      final page = await service.fetchBooks(
        query: const PublicDomainBookQuery(
          text: 'children',
          languageCode: 'fr',
          searchMode: PublicDomainSearchMode.topic,
          sort: PublicDomainSort.descending,
        ),
      );

      expect(page.books, isEmpty);
      expect(page.hasNextPage, isFalse);
    });

    test('local filtering excludes ineligible unfiltered results', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          expect(request.url.queryParameters, isEmpty);
          return http.Response(
            jsonEncode({
              'count': 4,
              'next': null,
              'previous': null,
              'results': [
                _bookJson(id: 10, title: 'Eligible'),
                _bookJson(id: 11, title: 'French', languages: ['fr']),
                _bookJson(id: 12, title: 'Copyrighted', copyright: true),
                _bookJson(
                  id: 13,
                  title: 'No EPUB',
                  formats: {'text/plain': 'https://example.com/13.txt'},
                ),
              ],
            }),
            200,
          );
        }),
      );

      final page = await service.fetchBooks();

      expect(page.books.map((book) => book.title), ['Eligible']);
    });

    test('bundled catalog loads and maps entries to existing model', () async {
      final service = PublicDomainBookService(
        assetBundle: _StringAssetBundle(
          jsonEncode({
            'books': [_assetBook(id: 1342, title: 'Pride and Prejudice')],
          }),
        ),
      );

      final page = await service.readBundledBooks();

      expect(page, isNotNull);
      expect(page!.books, hasLength(1));
      expect(page.books.single.id, 1342);
      expect(page.books.single.title, 'Pride and Prejudice');
      expect(
        page.books.single.epubUrl,
        'https://www.gutenberg.org/ebooks/1342.epub3.images',
      );
    });

    test('bundled catalog skips malformed and ineligible entries', () async {
      final service = PublicDomainBookService(
        assetBundle: _StringAssetBundle(
          jsonEncode({
            'books': [
              _assetBook(id: 1, title: 'Eligible'),
              _assetBook(id: 2, title: 'French', languages: ['fr']),
              _assetBook(id: 3, title: 'No URL', epubUrl: ''),
              {'id': 'bad'},
            ],
          }),
        ),
      );

      final page = await service.readBundledBooks();

      expect(page!.books.map((book) => book.title), ['Eligible']);
    });

    test('bundled catalog supports local search and topic filtering', () async {
      final service = PublicDomainBookService(
        assetBundle: _StringAssetBundle(
          jsonEncode({
            'books': [
              _assetBook(
                id: 1,
                title: 'Pride and Prejudice',
                subjects: ['Courtship -- Fiction'],
              ),
              _assetBook(
                id: 2,
                title: 'Moby Dick',
                subjects: ['Whaling -- Fiction'],
              ),
            ],
          }),
        ),
      );

      final titlePage = await service.readBundledBooks(
        query: const PublicDomainBookQuery(text: 'pride'),
      );
      final topicPage = await service.readBundledBooks(
        query: const PublicDomainBookQuery(
          text: 'whaling',
          searchMode: PublicDomainSearchMode.topic,
        ),
      );

      expect(titlePage!.books.map((book) => book.id), [1]);
      expect(topicPage!.books.map((book) => book.id), [2]);
    });

    test(
      'slow catalog response succeeds within catalog-specific timeout',
      () async {
        final service = PublicDomainBookService(
          catalogTimeout: const Duration(milliseconds: 100),
          client: MockClient((request) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return http.Response(
              _catalogResponse(id: 1, title: 'Slow Book'),
              200,
            );
          }),
        );

        final page = await service.fetchBooks();

        expect(page.books.single.title, 'Slow Book');
      },
    );

    test('timeout is retried before succeeding', () async {
      var requests = 0;
      final service = PublicDomainBookService(
        catalogTimeout: const Duration(milliseconds: 20),
        client: MockClient((request) async {
          requests += 1;
          if (requests == 1) throw TimeoutException('slow');
          return http.Response(
            _catalogResponse(id: 2, title: 'Retry Book'),
            200,
          );
        }),
      );

      final page = await service.fetchBooks();

      expect(requests, 2);
      expect(page.books.single.title, 'Retry Book');
    });

    test('repeated timeout reaches retry limit', () async {
      var requests = 0;
      final service = PublicDomainBookService(
        catalogTimeout: const Duration(milliseconds: 10),
        client: MockClient((request) async {
          requests += 1;
          throw TimeoutException('slow');
        }),
      );

      await expectLater(
        service.fetchBooks(),
        throwsA(
          isA<PublicDomainBookServiceException>().having(
            (error) => error.category,
            'category',
            PublicDomainCatalogFailureCategory.timeout,
          ),
        ),
      );
      expect(requests, 2);
    });

    test('socket failure is retried before succeeding', () async {
      var requests = 0;
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          requests += 1;
          if (requests == 1) throw const SocketException('offline');
          return http.Response(
            _catalogResponse(id: 3, title: 'Network Retry'),
            200,
          );
        }),
      );

      final page = await service.fetchBooks();

      expect(requests, 2);
      expect(page.books.single.title, 'Network Retry');
    });

    test('temporary server error is retried before succeeding', () async {
      var requests = 0;
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          requests += 1;
          if (requests == 1) return http.Response('busy', 503);
          return http.Response(
            _catalogResponse(id: 4, title: 'Server Retry'),
            200,
          );
        }),
      );

      final page = await service.fetchBooks();

      expect(requests, 2);
      expect(page.books.single.title, 'Server Retry');
    });

    test('permanent client error is not retried', () async {
      var requests = 0;
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          requests += 1;
          return http.Response('missing', 404);
        }),
      );

      await expectLater(
        service.fetchBooks(),
        throwsA(
          isA<PublicDomainBookServiceException>().having(
            (error) => error.category,
            'category',
            PublicDomainCatalogFailureCategory.invalidResponse,
          ),
        ),
      );
      expect(requests, 1);
    });

    test('malformed JSON is reported as a parsing failure', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async => http.Response('{', 200)),
      );

      await expectLater(
        service.fetchBooks(),
        throwsA(
          isA<PublicDomainBookServiceException>().having(
            (error) => error.category,
            'category',
            PublicDomainCatalogFailureCategory.parsing,
          ),
        ),
      );
    });

    test('invalid catalog structure is reported as invalid response', () async {
      final service = PublicDomainBookService(
        client: MockClient(
          (request) async => http.Response(jsonEncode({'results': 'bad'}), 200),
        ),
      );

      await expectLater(
        service.fetchBooks(),
        throwsA(
          isA<PublicDomainBookServiceException>().having(
            (error) => error.category,
            'category',
            PublicDomainCatalogFailureCategory.invalidResponse,
          ),
        ),
      );
    });

    test('empty but valid catalog response is safe', () async {
      final service = PublicDomainBookService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'count': 0,
              'next': null,
              'previous': null,
              'results': [],
            }),
            200,
          ),
        ),
      );

      final page = await service.fetchBooks();

      expect(page.books, isEmpty);
      expect(page.hasNextPage, isFalse);
    });

    test('filters exact-author searches locally and advances pages', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          final page = request.url.queryParameters['page'];
          if (page == null) {
            return http.Response(
              jsonEncode({
                'count': 2,
                'next':
                    'https://gutendex.com/books?page=2&search=Austen%2C+Jane',
                'previous': null,
                'results': [
                  {
                    'id': 10,
                    'title': 'Not Quite Right',
                    'authors': [
                      {'name': 'Someone Else'},
                    ],
                    'languages': ['en'],
                    'copyright': false,
                    'formats': {
                      'application/epub+zip': 'https://example.com/10.epub',
                    },
                  },
                ],
              }),
              200,
            );
          }

          expect(request.url.queryParameters['search'], 'Austen, Jane');
          return http.Response(
            jsonEncode({
              'count': 2,
              'next': null,
              'previous': 'https://gutendex.com/books?page=1',
              'results': [
                {
                  'id': 11,
                  'title': 'Sense and Sensibility',
                  'authors': [
                    {'name': 'Austen, Jane'},
                  ],
                  'languages': ['en'],
                  'copyright': false,
                  'formats': {
                    'application/epub+zip': 'https://example.com/11.epub',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final page = await service.fetchBooks(
        query: const PublicDomainBookQuery(exactAuthor: 'Austen, Jane'),
      );

      expect(page.page, 2);
      expect(page.hasNextPage, isFalse);
      expect(page.books.map((book) => book.id), [11]);
    });

    test('supports relative pagination URLs returned by Gutendex', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          expect(request.url.host, 'gutendex.com');
          expect(request.url.path, '/books');
          expect(request.url.queryParameters['page'], '2');
          return http.Response(
            _catalogResponse(id: 22, title: 'Relative Page'),
            200,
          );
        }),
      );

      final page = await service.fetchBooks(page: 2, pageUrl: '/books?page=2');

      expect(page.books.single.title, 'Relative Page');
    });

    test('caps exact-author automatic page scanning', () async {
      var requests = 0;
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          requests += 1;
          return http.Response(
            jsonEncode({
              'count': 50,
              'next': 'https://gutendex.com/books?page=${requests + 1}',
              'previous': requests == 1
                  ? null
                  : 'https://gutendex.com/books?page=${requests - 1}',
              'results': [
                {
                  'id': requests,
                  'title': 'Different Author $requests',
                  'authors': [
                    {'name': 'Someone Else'},
                  ],
                  'languages': ['en'],
                  'copyright': false,
                  'formats': {
                    'application/epub+zip':
                        'https://example.com/$requests.epub',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final page = await service.fetchBooks(
        query: const PublicDomainBookQuery(exactAuthor: 'Austen, Jane'),
      );

      expect(requests, 2);
      expect(page.books, isEmpty);
      expect(page.hasNextPage, isTrue);
    });

    test('fetches individual book details', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          expect(request.url.path, '/books/1342');
          return http.Response(
            jsonEncode({
              'id': 1342,
              'title': 'Pride and Prejudice',
              'authors': [
                {'name': 'Austen, Jane'},
              ],
              'summaries': ['A novel of manners.'],
              'subjects': ['Courtship -- Fiction'],
              'bookshelves': ['Best Books Ever Listings'],
              'languages': ['en'],
              'copyright': false,
              'media_type': 'Text',
              'formats': {
                'application/epub+zip': 'https://example.com/1342.epub',
              },
              'download_count': 123,
            }),
            200,
          );
        }),
      );

      final book = await service.fetchBookDetails(1342);

      expect(book.id, 1342);
      expect(book.title, 'Pride and Prejudice');
      expect(book.bookshelves, ['Best Books Ever Listings']);
    });

    test('filters out non-public-domain and non-EPUB results', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'count': 3,
              'next': 'https://gutendex.com/books?page=2',
              'previous': null,
              'results': [
                {
                  'id': 1,
                  'title': 'Valid Book',
                  'authors': [],
                  'languages': ['en'],
                  'copyright': false,
                  'formats': {
                    'application/epub+zip': 'https://example.com/book.epub',
                  },
                },
                {
                  'id': 2,
                  'title': 'Copyrighted Book',
                  'authors': [],
                  'languages': ['en'],
                  'copyright': true,
                  'formats': {
                    'application/epub+zip': 'https://example.com/book.epub',
                  },
                },
                {
                  'id': 3,
                  'title': 'Text Only Book',
                  'authors': [],
                  'languages': ['en'],
                  'copyright': false,
                  'formats': {'text/plain': 'https://example.com/book.txt'},
                },
              ],
            }),
            200,
          );
        }),
      );

      final page = await service.fetchBooks();

      expect(page.hasNextPage, isTrue);
      expect(page.books.map((book) => book.id), [1]);
    });

    test('cache-first returns fresh cached results without network', () async {
      var requests = 0;
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          requests += 1;
          return http.Response(
            jsonEncode({
              'count': 1,
              'next': null,
              'previous': null,
              'results': [
                {
                  'id': 1342,
                  'title': 'Pride and Prejudice',
                  'authors': [
                    {'name': 'Austen, Jane'},
                  ],
                  'languages': ['en'],
                  'copyright': false,
                  'formats': {
                    'application/epub+zip': 'https://example.com/1342.epub',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      await service.fetchBooksAndCache(
        query: const PublicDomainBookQuery(text: 'austen'),
      );

      final cached = await service.fetchBooksCacheFirst(
        query: const PublicDomainBookQuery(text: 'austen'),
      );

      expect(cached.books.single.title, 'Pride and Prejudice');
      expect(requests, 1);
    });

    test(
      'stale cache falls back to saved results when refresh fails',
      () async {
        final staleTimestamp = DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch;
        const cachedPage = PublicDomainBookPage(
          books: [
            PublicDomainBook(
              id: 84,
              title: 'Frankenstein',
              authors: ['Mary Shelley'],
              epubUrl: 'https://example.com/84.epub',
              downloadCount: 10,
            ),
          ],
          count: 1,
          hasNextPage: false,
          page: 1,
        );
        const query = PublicDomainBookQuery(text: 'shelley');
        SharedPreferences.setMockInitialValues({
          'gutendex_cache_v1_${query.cacheKey}_page_1': jsonEncode(
            cachedPage.toCacheJson(),
          ),
          'gutendex_cache_v1_${query.cacheKey}_page_1_cached_at':
              staleTimestamp,
        });

        final service = PublicDomainBookService(
          client: MockClient((request) async => http.Response('offline', 503)),
        );

        final page = await service.fetchBooksCacheFirst(query: query);

        expect(await service.isCacheFresh(query: query), isFalse);
        expect(page.books.single.title, 'Frankenstein');
      },
    );

    test('failed refresh preserves cached catalog and timestamp', () async {
      const cachedPage = PublicDomainBookPage(
        books: [
          PublicDomainBook(
            id: 84,
            title: 'Frankenstein',
            authors: ['Mary Shelley'],
            epubUrl: 'https://example.com/84.epub',
            downloadCount: 10,
          ),
        ],
        count: 1,
        hasNextPage: false,
        page: 1,
      );
      const query = PublicDomainBookQuery(text: 'shelley');
      final timestamp = DateTime.now()
          .subtract(const Duration(days: 2))
          .millisecondsSinceEpoch;
      final cacheKey = 'gutendex_cache_v1_${query.cacheKey}_page_1';
      final timestampKey = '${cacheKey}_cached_at';
      SharedPreferences.setMockInitialValues({
        cacheKey: jsonEncode(cachedPage.toCacheJson()),
        timestampKey: timestamp,
      });

      final service = PublicDomainBookService(
        client: MockClient((request) async => http.Response('offline', 503)),
      );

      final page = await service.fetchBooksCacheFirst(query: query);
      final prefs = await SharedPreferences.getInstance();

      expect(page.books.single.title, 'Frankenstein');
      expect(prefs.getString(cacheKey), jsonEncode(cachedPage.toCacheJson()));
      expect(prefs.getInt(timestampKey), timestamp);
    });

    test('no-cache failure produces a hard catalog error', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async => http.Response('offline', 503)),
      );

      await expectLater(
        service.fetchBooksCacheFirst(),
        throwsA(isA<PublicDomainBookServiceException>()),
      );
    });
  });
}

String _catalogResponse({required int id, required String title}) {
  return jsonEncode({
    'count': 1,
    'next': null,
    'previous': null,
    'results': [_bookJson(id: id, title: title)],
  });
}

Map<String, dynamic> _bookJson({
  required int id,
  required String title,
  List<String> languages = const ['en'],
  Object? copyright = false,
  Map<String, dynamic>? formats,
}) {
  return {
    'id': id,
    'title': title,
    'authors': [
      {'name': 'Author, Test'},
    ],
    'languages': languages,
    'copyright': copyright,
    'formats':
        formats ?? {'application/epub+zip': 'https://example.com/$id.epub'},
  };
}

Map<String, dynamic> _assetBook({
  required int id,
  required String title,
  List<String> languages = const ['en'],
  List<String> subjects = const [],
  String? epubUrl,
}) {
  return {
    'id': id,
    'title': title,
    'authors': ['Test Author'],
    'authorDetails': [
      {'name': 'Test Author'},
    ],
    'subjects': subjects,
    'bookshelves': const [],
    'languages': languages,
    'copyright': false,
    'coverUrl':
        'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg',
    'epubUrl': epubUrl ?? 'https://www.gutenberg.org/ebooks/$id.epub3.images',
    'downloadCount': 1000 - id,
    'mediaType': 'Text',
  };
}

class _StringAssetBundle extends CachingAssetBundle {
  _StringAssetBundle(this.value);

  final String value;

  @override
  Future<ByteData> load(String key) async {
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}
