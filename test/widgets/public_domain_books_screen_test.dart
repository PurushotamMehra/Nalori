import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/public_domain_book.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/public_domain_books_screen.dart';
import 'package:nalori/services/public_domain_book_service.dart';
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
  });

  testWidgets('successful initial load shows books', (tester) async {
    final service = _FakeCatalogService(initialPage: _page([_book(1, 'Emma')]));

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Emma'), findsOneWidget);
  });

  testWidgets('starter books display as the immediate local catalogue', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      bundledPage: _page([
        _book(10, 'Pride and Prejudice'),
      ], statusMessage: 'Showing starter offline catalogue'),
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pump();
    await tester.pump();

    expect(find.text('Pride and Prejudice'), findsOneWidget);
    expect(find.text('Showing starter offline catalogue'), findsOneWidget);
    expect(service.initialRequests, 1);
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

  testWidgets('cached local data keeps book cards visible', (tester) async {
    final service = _FakeCatalogService(
      cachedPage: _page([
        _book(3, 'Frankenstein'),
      ], statusMessage: 'Full catalogue available offline'),
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Frankenstein'), findsOneWidget);
    expect(find.text('Full catalogue available offline'), findsOneWidget);
  });

  testWidgets('bundled data keeps book cards visible without network', (
    tester,
  ) async {
    final service = _FakeCatalogService(
      bundledPage: _page([
        _book(12, 'Dracula'),
      ], statusMessage: 'Showing starter offline catalogue'),
    );

    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Dracula'), findsOneWidget);
    expect(find.text('Catalog unavailable'), findsNothing);
    expect(find.text('Showing starter offline catalogue'), findsOneWidget);
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
  });
}

Widget _wrap(PublicDomainBookService service) {
  return MaterialApp(
    home: PublicDomainBooksScreen(
      settings: const ReadingSettings(),
      catalogService: service,
      skipLocalBookLoad: true,
    ),
  );
}

PublicDomainBook _book(int id, String title) {
  return PublicDomainBook(
    id: id,
    title: title,
    authors: const ['Test Author'],
    epubUrl: 'https://example.com/$id.epub',
    downloadCount: 10,
  );
}

PublicDomainBookPage _page(
  List<PublicDomainBook> books, {
  bool hasNextPage = false,
  String? statusMessage,
}) {
  return PublicDomainBookPage(
    books: books,
    count: books.length,
    hasNextPage: hasNextPage,
    page: 1,
    nextUrl: hasNextPage ? 'https://gutendex.com/books?page=2' : null,
    catalogStatusMessage: statusMessage,
  );
}

class _FakeCatalogService extends PublicDomainBookService {
  _FakeCatalogService({
    this.bundledPage,
    this.cachedPage,
    this.initialPage,
    this.initialCompleter,
    this.initialErrors = const [],
    this.pageErrors = const [],
    this.nextPages = const [],
  });

  final PublicDomainBookPage? bundledPage;
  final PublicDomainBookPage? cachedPage;
  final PublicDomainBookPage? initialPage;
  final Completer<PublicDomainBookPage>? initialCompleter;
  final List<Object> initialErrors;
  final List<Object> pageErrors;
  final List<PublicDomainBookPage> nextPages;
  int initialRequests = 0;
  int pageRequests = 0;

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
  }) async {
    return page == 1 ? cachedPage : null;
  }

  @override
  Future<bool> isCacheFresh({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
  }) async {
    return false;
  }

  @override
  Future<PublicDomainBookPage> fetchBooksAndCache({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    initialRequests += 1;
    if (initialRequests <= initialErrors.length) {
      throw initialErrors[initialRequests - 1];
    }
    if (initialCompleter != null) return initialCompleter!.future;
    return initialPage ?? cachedPage ?? _page(const []);
  }

  @override
  Future<PublicDomainBookPage> fetchLocalCatalogPage({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
  }) async {
    if (page == 1) {
      initialRequests += 1;
      if (bundledPage != null) return bundledPage!;
      if (cachedPage != null) return cachedPage!;
      if (initialRequests <= initialErrors.length) {
        throw initialErrors[initialRequests - 1];
      }
      if (initialCompleter != null) return initialCompleter!.future;
      return initialPage ?? _page(const []);
    }
    return fetchBooksCacheFirst(query: query, page: page);
  }

  @override
  Future<PublicDomainBookPage> fetchBooksCacheFirst({
    PublicDomainBookQuery query = const PublicDomainBookQuery(),
    int page = 1,
    String? pageUrl,
  }) async {
    pageRequests += 1;
    if (pageRequests <= pageErrors.length) {
      throw pageErrors[pageRequests - 1];
    }
    final index = pageRequests - pageErrors.length - 1;
    return nextPages[index];
  }
}
