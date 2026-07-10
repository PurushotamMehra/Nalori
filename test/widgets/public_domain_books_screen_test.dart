import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nalori/models/public_domain_book.dart';
import 'package:nalori/models/public_domain_catalog.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/public_domain_books_screen.dart';
import 'package:nalori/services/public_domain_book_service.dart';
import 'package:nalori/services/public_domain_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('initial loading state appears and only starts one request', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      initialCompleter: Completer<PublicDomainBookPage>(),
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Load more'), findsNothing);
    expect(service.initialRequests, 1);
    expect(service.localCatalogRequests, 0);
    expect(service.manifestRequests, 0);
  });

  testWidgets('successful initial load uses Gutendex cache-first path', (
    tester,
  ) async {
    final service = _FakeCatalogService(initialPage: _page([_book(1, 'Emma')]));

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Emma'), findsOneWidget);
    expect(
      find.text(
        'Search public-domain EPUBs from Project Gutenberg via Gutendex.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('For deeper catalogue browsing, visit Project Gutenberg.'),
      findsOneWidget,
    );
    expect(find.textContaining('Full Gutenberg catalogue'), findsNothing);
    expect(find.textContaining('Full catalogue'), findsNothing);
    expect(find.textContaining('starter offline catalogue'), findsNothing);
    expect(service.initialRequests, 1);
    expect(service.requestedPages, [1]);
    expect(service.requestedPageUrls, [null]);
    expect(service.localCatalogRequests, 0);
    expect(service.manifestRequests, 0);
  });

  testWidgets('bundled starter catalogue is not used for initial browsing', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      bundledPage: _page([
        _book(10, 'Pride and Prejudice'),
      ], statusMessage: 'Showing starter offline catalogue'),
      initialPage: _page([_book(1, 'Emma')]),
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pump();
    await tester.pump();

    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('Pride and Prejudice'), findsNothing);
    expect(find.text('Showing starter offline catalogue'), findsNothing);
    expect(service.initialRequests, 1);
    expect(service.localCatalogRequests, 0);
  });

  testWidgets(
    'no-cache failure shows unavailable state and manual retry works',
    (tester) async {
      final service = _FakeCatalogService(
        initialErrors: [
          const PublicDomainBookServiceException(
            'The catalog could not be reached.',
          ),
        ],
        initialPage: _page([_book(2, 'Persuasion')]),
      );

      await tester.pumpWidget(_wrap(service));
      await tester.pumpAndSettle();

      expect(find.text('Catalog unavailable'), findsOneWidget);
      expect(find.text('The catalog could not be reached.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(service.initialRequests, 2);
      await tester.pumpAndSettle();

      expect(find.text('Persuasion'), findsOneWidget);
    },
  );

  testWidgets('cached Gutendex data keeps book cards visible', (tester) async {
    final service = _FakeCatalogService(
      cachedPage: _page([
        _book(3, 'Frankenstein'),
      ], statusMessage: 'Showing saved results while refreshing.'),
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Frankenstein'), findsOneWidget);
    expect(
      find.text('Showing saved results while refreshing.'),
      findsOneWidget,
    );
    expect(service.localCatalogRequests, 0);
  });

  testWidgets('stale fallback data shows friendly saved-results copy', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      initialPage: _page(
        [_book(14, 'Wuthering Heights')],
        statusMessage: 'You appear to be offline. Showing saved results.',
        isFallbackOnly: true,
      ),
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Wuthering Heights'), findsOneWidget);
    expect(
      find.text('You appear to be offline. Showing saved results.'),
      findsOneWidget,
    );
    expect(find.textContaining('Full catalogue'), findsNothing);
    expect(find.textContaining('starter offline catalogue'), findsNothing);
    expect(find.textContaining('offline Gutenberg catalogue'), findsNothing);
  });

  testWidgets('bundled starter catalogue is not fallback for API failure', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      bundledPage: _page([
        _book(12, 'Dracula'),
      ], statusMessage: 'Showing starter offline catalogue'),
      initialErrors: [
        const PublicDomainBookServiceException(
          'The catalog could not be reached.',
        ),
      ],
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Dracula'), findsNothing);
    expect(find.text('Catalog unavailable'), findsOneWidget);
    expect(find.text('Showing starter offline catalogue'), findsNothing);
    expect(service.localCatalogRequests, 0);
  });

  testWidgets('pagination failure preserves loaded books', (tester) async {
    final service = _FakeCatalogService(
      initialPage: _page([_book(4, 'Jane Eyre')], hasNextPage: true),
      pageErrors: [
        const PublicDomainBookServiceException(
          'More books could not be loaded.',
        ),
      ],
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(find.text('Jane Eyre'), findsOneWidget);
    expect(
      find.text(
        'Could not load more books. Try again when the catalog responds.',
      ),
      findsOneWidget,
    );
    expect(find.text('Load more'), findsOneWidget);
    expect(service.requestedPageUrls.last, 'https://gutendex.com/books?page=2');
  });

  testWidgets('pagination retry adds new books once without duplicates', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      initialPage: _page([_book(5, 'The Time Machine')], hasNextPage: true),
      pageErrors: [
        const PublicDomainBookServiceException(
          'More books could not be loaded.',
        ),
      ],
      nextPages: [
        _page([_book(5, 'The Time Machine'), _book(6, 'The Invisible Man')]),
      ],
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(find.text('The Time Machine'), findsOneWidget);
    expect(find.text('The Invisible Man'), findsOneWidget);
    expect(service.requestedPageUrls.sublist(1), [
      'https://gutendex.com/books?page=2',
      'https://gutendex.com/books?page=2',
    ]);
  });

  testWidgets('keyboard search submits query and replaces results', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      firstPageResults: [
        _page([_book(1, 'Emma')]),
        _page([_book(2, 'Persuasion')]),
      ],
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'persuasion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Emma'), findsNothing);
    expect(find.text('Persuasion'), findsOneWidget);
    expect(service.requestedQueries.last.trimmedText, 'persuasion');
    expect(service.requestedPages.last, 1);
  });

  testWidgets('arrow search submits through the same query reload path', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      firstPageResults: [
        _page([_book(1, 'Emma')]),
        _page([_book(3, 'Mansfield Park')]),
      ],
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'mansfield');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Emma'), findsNothing);
    expect(find.text('Mansfield Park'), findsOneWidget);
    expect(service.requestedQueries.last.trimmedText, 'mansfield');
    expect(service.requestedPages.last, 1);
  });

  testWidgets('clear search immediately restores active-filter results', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      firstPageResults: [
        _page([_book(1, 'Emma')]),
        _page([_book(2, 'Persuasion')]),
        _page([_book(4, 'Jane Eyre')]),
      ],
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'persuasion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('Persuasion'), findsNothing);
    expect(find.text('Jane Eyre'), findsOneWidget);
    expect(service.requestedQueries.last.trimmedText, '');
    expect(service.requestedQueries.last.languageCode, 'en');
    expect(service.requestedPages.last, 1);
  });

  testWidgets('apply filters immediately executes selected query', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      firstPageResults: [
        _page([_book(1, 'Emma')]),
        _page([_book(5, 'Les Miserables')]),
      ],
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any language'));
    await tester.tap(find.text('Oldest IDs'));
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Emma'), findsNothing);
    expect(find.text('Les Miserables'), findsOneWidget);
    expect(service.requestedQueries.last.languageCode, isNull);
    expect(service.requestedQueries.last.sort, PublicDomainSort.ascending);
    expect(service.requestedPages.last, 1);
  });

  testWidgets('new query resets pagination and ignores stale responses', (
    tester,
  ) async {
    final olderSearch = Completer<PublicDomainBookPage>();
    final newerSearch = Completer<PublicDomainBookPage>();
    final service = _FakeCatalogService(
      firstPageResults: [
        _page([_book(1, 'Emma')], hasNextPage: true),
        olderSearch.future,
        newerSearch.future,
      ],
      nextPages: [
        _page([_book(2, 'Northanger Abbey')], page: 2),
      ],
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Northanger Abbey'), findsOneWidget);
    expect(service.requestedPages.last, 2);

    await tester.enterText(find.byType(TextField), 'old');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'new');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    newerSearch.complete(_page([_book(3, 'New Result')]));
    await tester.pumpAndSettle();
    olderSearch.complete(_page([_book(4, 'Old Result')]));
    await tester.pumpAndSettle();

    expect(find.text('New Result'), findsOneWidget);
    expect(find.text('Old Result'), findsNothing);
    expect(find.text('Emma'), findsNothing);
    expect(find.text('Northanger Abbey'), findsNothing);
    expect(service.requestedPages.sublist(service.requestedPages.length - 2), [
      1,
      1,
    ]);
  });

  testWidgets('missing EPUB URL is rejected before download starts', (
    tester,
  ) async {
    final catalogService = _FakeCatalogService(
      initialPage: _page([_book(21, 'No EPUB', epubUrl: '')]),
    );
    final downloadService = _FakeDownloadService();

    await tester.pumpWidget(
      _wrap(catalogService, downloadService: downloadService),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(downloadService.downloadCalls, 0);
    expect(
      find.text('This book does not have a readable EPUB download available.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Cancel download'), findsNothing);
  });

  testWidgets('cancelled download clears active state without failure copy', (
    tester,
  ) async {
    final catalogService = _FakeCatalogService(
      initialPage: _page([_book(22, 'Slow EPUB')]),
    );
    final downloadService = _FakeDownloadService(waitForCancellation: true);

    await tester.pumpWidget(
      _wrap(catalogService, downloadService: downloadService),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(find.byTooltip('Cancel download'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel download'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(downloadService.downloadCalls, 1);
    expect(find.byTooltip('Cancel download'), findsNothing);
    expect(find.textContaining("Couldn't"), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
  });
}

Widget _wrap(
  PublicDomainBookService service, {
  PublicDomainDownloadService? downloadService,
}) {
  return MaterialApp(
    home: PublicDomainBooksScreen(
      settings: const ReadingSettings(),
      catalogService: service,
      downloadService: downloadService,
      skipLocalBookLoad: true,
    ),
  );
}

PublicDomainBook _book(int id, String title, {String? epubUrl}) {
  return PublicDomainBook(
    id: id,
    title: title,
    authors: const ['Test Author'],
    epubUrl: epubUrl ?? 'https://example.com/$id.epub',
    downloadCount: 10,
  );
}

PublicDomainBookPage _page(
  List<PublicDomainBook> books, {
  bool hasNextPage = false,
  int page = 1,
  String? statusMessage,
  bool isFallbackOnly = false,
}) {
  return PublicDomainBookPage(
    books: books,
    count: books.length,
    hasNextPage: hasNextPage,
    page: page,
    nextUrl: hasNextPage ? 'https://gutendex.com/books?page=2' : null,
    catalogStatusMessage: statusMessage,
    isFallbackOnly: isFallbackOnly,
  );
}

class _FakeCatalogService extends PublicDomainBookService {
  _FakeCatalogService({
    this.bundledPage,
    this.cachedPage,
    this.initialPage,
    this.firstPageResults = const [],
    this.initialCompleter,
    this.initialErrors = const [],
    this.pageErrors = const [],
    this.nextPages = const [],
  });

  final PublicDomainBookPage? bundledPage;
  final PublicDomainBookPage? cachedPage;
  final PublicDomainBookPage? initialPage;
  final List<FutureOr<PublicDomainBookPage>> firstPageResults;
  final Completer<PublicDomainBookPage>? initialCompleter;
  final List<Object> initialErrors;
  final List<Object> pageErrors;
  final List<PublicDomainBookPage> nextPages;
  int initialRequests = 0;
  int pageRequests = 0;
  int localCatalogRequests = 0;
  int manifestRequests = 0;
  final List<PublicDomainBookQuery> requestedQueries = [];
  final List<int> requestedPages = [];
  final List<String?> requestedPageUrls = [];

  @override
  Future<PublicDomainBookPage?> readBundledBooks({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
  }) async {
    return bundledPage;
  }

  @override
  Future<PublicDomainBookPage?> readCachedBooks({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    return page == 1 ? cachedPage : null;
  }

  @override
  Future<bool> isCacheFresh({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    return false;
  }

  @override
  Future<PublicDomainBookPage> fetchBooksAndCache({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    return fetchBooksCacheFirst(query: query, page: page, pageUrl: pageUrl);
  }

  @override
  Future<PublicDomainBookPage> fetchLocalCatalogPage({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
  }) async {
    localCatalogRequests += 1;
    fail('PublicDomainBooksScreen should use Gutendex cache-first browsing');
  }

  @override
  Future<PublicDomainCatalogManifest?> fetchCatalogManifest() async {
    manifestRequests += 1;
    return null;
  }

  @override
  Future<PublicDomainBookPage> fetchBooksCacheFirst({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    requestedQueries.add(query);
    requestedPages.add(page);
    requestedPageUrls.add(pageUrl);
    if (page == 1) {
      initialRequests += 1;
      if (cachedPage != null) return cachedPage!;
      if (initialRequests <= initialErrors.length) {
        throw initialErrors[initialRequests - 1];
      }
      final responseIndex = initialRequests - initialErrors.length - 1;
      if (responseIndex < firstPageResults.length) {
        return Future.value(firstPageResults[responseIndex]);
      }
      if (initialCompleter != null) return initialCompleter!.future;
      return initialPage ?? _page(const []);
    }
    pageRequests += 1;
    if (pageRequests <= pageErrors.length) {
      throw pageErrors[pageRequests - 1];
    }
    final index = pageRequests - pageErrors.length - 1;
    return nextPages[index];
  }
}

class _FakeDownloadService extends PublicDomainDownloadService {
  _FakeDownloadService({this.waitForCancellation = false})
    : super(
        client: MockClient((_) async => http.Response('', 500)),
        saveBookBytes: ({required fileName, required bytes}) async {
          return File('/tmp/$fileName');
        },
      );

  final bool waitForCancellation;
  int downloadCalls = 0;

  @override
  Future<File> downloadBook(
    PublicDomainBook book, {
    PublicDomainDownloadProgress? onProgress,
    PublicDomainDownloadCancelToken? cancelToken,
  }) async {
    downloadCalls += 1;
    if (waitForCancellation) {
      while (cancelToken?.isCancelled != true) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      throw const PublicDomainDownloadCancelledException();
    }
    throw StateError('Unexpected download');
  }
}
