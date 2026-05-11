import 'dart:convert';

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
            expect(request.url.path, '/books');
            expect(request.url.queryParameters['copyright'], 'false');
            expect(request.url.queryParameters['languages'], 'en');
            expect(
              request.url.queryParameters['mime_type'],
              'application/epub+zip',
            );
            expect(request.url.queryParameters['search'], 'austen');
            expect(request.url.queryParameters['sort'], 'popular');
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

    test('uses topic queries and custom filters', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          expect(request.url.queryParameters['topic'], 'children');
          expect(request.url.queryParameters['languages'], 'fr');
          expect(request.url.queryParameters['sort'], 'descending');
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

    test('filters exact-author searches locally and advances pages', () async {
      final service = PublicDomainBookService(
        client: MockClient((request) async {
          final page = request.url.queryParameters['page'];
          if (page == '1') {
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
                  'copyright': false,
                  'formats': {
                    'application/epub+zip': 'https://example.com/book.epub',
                  },
                },
                {
                  'id': 2,
                  'title': 'Copyrighted Book',
                  'authors': [],
                  'copyright': true,
                  'formats': {
                    'application/epub+zip': 'https://example.com/book.epub',
                  },
                },
                {
                  'id': 3,
                  'title': 'Text Only Book',
                  'authors': [],
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
        final cachedPage = const PublicDomainBookPage(
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
        final query = const PublicDomainBookQuery(text: 'shelley');
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
  });
}
