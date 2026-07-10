import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/book_metadata.dart';
import '../models/public_domain_book.dart';
import '../models/reading_settings.dart';
import '../services/book_metadata_service.dart';
import '../services/library_service.dart';
import '../services/public_domain_book_service.dart';
import '../services/public_domain_download_service.dart';
import '../ui/app_visuals.dart';
import 'public_domain_book_detail_screen.dart';

class PublicDomainBooksScreen extends StatefulWidget {
  final ReadingSettings settings;
  final String title;
  final String subtitle;
  final PublicDomainBookQuery initialQuery;
  final PublicDomainBookService? catalogService;
  final PublicDomainDownloadService? downloadService;
  final LibraryService? libraryService;
  final BookMetadataService? metadataService;
  final bool skipLocalBookLoad;

  const PublicDomainBooksScreen({
    super.key,
    required this.settings,
    this.title = 'Project Gutenberg',
    this.subtitle =
        'Search public-domain EPUBs from Project Gutenberg via Gutendex.',
    this.initialQuery = const PublicDomainBookQuery(),
    this.catalogService,
    this.downloadService,
    this.libraryService,
    this.metadataService,
    this.skipLocalBookLoad = false,
  });

  factory PublicDomainBooksScreen.forAuthor({
    required ReadingSettings settings,
    required PublicDomainPerson author,
    String? languageCode,
    PublicDomainSort sort = PublicDomainSort.popular,
  }) {
    return PublicDomainBooksScreen(
      settings: settings,
      subtitle: '${author.displayLabel} • free public-domain books',
      initialQuery: PublicDomainBookQuery(
        languageCode: languageCode,
        sort: sort,
        exactAuthor: author.name,
      ),
    );
  }

  factory PublicDomainBooksScreen.forTopic({
    required ReadingSettings settings,
    required String topic,
    String? languageCode,
    PublicDomainSort sort = PublicDomainSort.popular,
  }) {
    return PublicDomainBooksScreen(
      settings: settings,
      subtitle: '$topic • free public-domain books',
      initialQuery: PublicDomainBookQuery(
        text: topic,
        languageCode: languageCode,
        sort: sort,
        searchMode: PublicDomainSearchMode.topic,
      ),
    );
  }

  @override
  State<PublicDomainBooksScreen> createState() =>
      _PublicDomainBooksScreenState();
}

enum _DownloadTaskPhase { queued, downloading, preparing }

class _PublicDomainDownloadTask {
  final PublicDomainBook book;
  final PublicDomainDownloadCancelToken cancelToken;
  _DownloadTaskPhase phase;
  double? progress;

  _PublicDomainDownloadTask({required this.book})
    : cancelToken = PublicDomainDownloadCancelToken(),
      phase = _DownloadTaskPhase.queued;
}

class _PublicDomainBooksScreenState extends State<PublicDomainBooksScreen> {
  late final PublicDomainBookService _catalogService;
  late final PublicDomainDownloadService _downloadService;
  late final LibraryService _libraryService;
  late final BookMetadataService _metadataService;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  static const _languageChoices = <String?>[null, 'en', 'fr', 'de', 'es'];

  late PublicDomainBookQuery _activeQuery;

  List<PublicDomainBook> _books = [];
  Map<String, File> _localBooksByName = {};
  Map<int, File> _localGutenbergBooksById = {};
  Map<String, File> _localBooksByTitleAuthor = {};
  Set<int> _downloadingIds = {};
  final Map<int, _PublicDomainDownloadTask> _downloadTasks = {};
  final List<int> _downloadQueue = [];
  int? _activeDownloadId;
  String? _error;
  String? _statusMessage;
  bool _loading = true;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _hasNextPage = false;
  bool _showingSavedResults = false;
  int _page = 1;
  String? _nextPageUrl;
  int _requestGeneration = 0;
  String? _activeInitialLoadKey;
  Timer? _searchDebounce;
  bool _prefetchingMore = false;
  PublicDomainBookPage? _prefetchedPage;
  String? _prefetchedPageKey;

  ReadingSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? PublicDomainBookService();
    _downloadService = widget.downloadService ?? PublicDomainDownloadService();
    _libraryService = widget.libraryService ?? LibraryService();
    _metadataService = widget.metadataService ?? BookMetadataService();
    _activeQuery = widget.initialQuery;
    _searchController.text = widget.initialQuery.text;
    _scrollController.addListener(_maybePrefetchNextPage);
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!widget.skipLocalBookLoad) await _loadLocalBooks();
    await _loadBooks(reset: true);
  }

  Future<void> _loadLocalBooks() async {
    await _metadataService.init();
    final localBooks = await _libraryService.getLocalBooks();
    final metadata = {
      for (final item in _metadataService.getAllSortedByLastRead())
        item.id: item,
    };
    if (!mounted) return;
    setState(() {
      _localBooksByName = {
        for (final file in localBooks) p.basename(file.path): file,
      };
      _localGutenbergBooksById = {
        for (final file in localBooks)
          if (_gutenbergIdFor(file, metadata[p.basename(file.path)]) != null)
            _gutenbergIdFor(file, metadata[p.basename(file.path)])!: file,
      };
      _localBooksByTitleAuthor = {
        for (final file in localBooks)
          if (_titleAuthorKeyForMetadata(metadata[p.basename(file.path)]) !=
              null)
            _titleAuthorKeyForMetadata(metadata[p.basename(file.path)])!: file,
      };
    });
  }

  File? _existingFileFor(PublicDomainBook book) {
    return _localGutenbergBooksById[book.id] ??
        _localBooksByName[_downloadService.fileNameFor(book)] ??
        _localBooksByTitleAuthor[_titleAuthorKey(book.title, book.authorLabel)];
  }

  bool _isInLibrary(PublicDomainBook book) => _existingFileFor(book) != null;

  int? _gutenbergIdFor(File file, BookMetadata? metadata) {
    final metadataId = metadata?.gutenbergId;
    if (metadataId != null) return metadataId;

    final match = RegExp(
      r'^gutenberg_(\d+)_',
      caseSensitive: false,
    ).firstMatch(p.basename(file.path));
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String? _titleAuthorKeyForMetadata(BookMetadata? metadata) {
    if (metadata == null) return null;
    if (metadata.source == 'gutenberg' || metadata.gutenbergId != null) {
      return _titleAuthorKey(metadata.title, metadata.author);
    }
    return null;
  }

  String _titleAuthorKey(String title, String author) {
    return '${_normalizeMatchText(title)}|${_normalizeMatchText(author)}';
  }

  String _normalizeMatchText(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _loadBooks({required bool reset}) async {
    final loadKey = _pageCacheKey(
      query: _activeQuery,
      page: reset ? 1 : _page + 1,
    );
    if (reset &&
        _activeInitialLoadKey == loadKey &&
        (_loading || _refreshing)) {
      return;
    }
    if (!reset && _loadingMore) return;
    if (reset) _activeInitialLoadKey = loadKey;

    final generation = ++_requestGeneration;
    final query = _activeQuery;
    if (reset) {
      _clearPrefetchedPage();
      setState(() {
        _loading = _books.isEmpty;
        _loadingMore = false;
        _refreshing = _books.isNotEmpty;
        _error = null;
        _statusMessage = _books.isNotEmpty
            ? 'Showing saved results while refreshing.'
            : null;
        _showingSavedResults = _books.isNotEmpty;
        _page = 1;
        _nextPageUrl = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final requestedPage = reset ? 1 : _page + 1;
      final prefetchedPage = reset
          ? null
          : _takePrefetchedPage(query: query, page: requestedPage);
      final page =
          prefetchedPage ??
          await _catalogService.fetchBooksCacheFirst(
            query: query,
            page: requestedPage,
            pageUrl: reset ? null : _nextPageUrl,
          );

      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _books = reset ? page.books : _appendUniqueBooks(_books, page.books);
        _page = page.page;
        _hasNextPage = page.hasNextPage;
        _nextPageUrl = page.nextUrl;
        _loading = false;
        _loadingMore = false;
        _refreshing = false;
        _statusMessage = page.catalogStatusMessage;
        _showingSavedResults = page.isFallbackOnly;
      });
      if (!reset) _maybePrefetchNextPage();
    } catch (e) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = _books.isEmpty ? _catalogUnavailableMessage(e) : null;
        _statusMessage = _books.isNotEmpty
            ? reset
                  ? 'You appear to be offline. Showing saved results.'
                  : 'Could not load more books. Try again when the catalog responds.'
            : null;
        _showingSavedResults = _books.isNotEmpty;
        _loading = false;
        _loadingMore = false;
        _refreshing = false;
      });
    } finally {
      if (reset && _activeInitialLoadKey == loadKey) {
        _activeInitialLoadKey = null;
      }
    }
  }

  List<PublicDomainBook> _appendUniqueBooks(
    List<PublicDomainBook> existing,
    List<PublicDomainBook> incoming,
  ) {
    final seen = existing.map((book) => book.id).toSet();
    return [
      ...existing,
      for (final book in incoming)
        if (seen.add(book.id)) book,
    ];
  }

  String _catalogUnavailableMessage(Object error) {
    if (error is PublicDomainBookServiceException) return error.message;
    return 'Check your connection and try again.';
  }

  void _clearPrefetchedPage() {
    _prefetchedPage = null;
    _prefetchedPageKey = null;
    _prefetchingMore = false;
  }

  String _pageCacheKey({
    required PublicDomainBookQuery query,
    required int page,
  }) {
    return '${query.cacheKey}|$page';
  }

  PublicDomainBookPage? _takePrefetchedPage({
    required PublicDomainBookQuery query,
    required int page,
  }) {
    final key = _pageCacheKey(query: query, page: page);
    if (_prefetchedPageKey != key) return null;
    final pageResult = _prefetchedPage;
    _prefetchedPage = null;
    _prefetchedPageKey = null;
    return pageResult;
  }

  void _maybePrefetchNextPage() {
    if (!_hasNextPage ||
        _loading ||
        _loadingMore ||
        _refreshing ||
        _prefetchingMore ||
        !_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.extentAfter > 700) return;

    final query = _activeQuery;
    final nextPage = _page + 1;
    final nextPageUrl = _nextPageUrl;
    final key = _pageCacheKey(query: query, page: nextPage);
    if (_prefetchedPageKey == key && _prefetchedPage != null) return;

    _prefetchingMore = true;
    _prefetchedPageKey = key;
    unawaited(
      _catalogService
          .fetchBooksCacheFirst(
            query: query,
            page: nextPage,
            pageUrl: nextPageUrl,
          )
          .then((page) {
            if (!mounted || _prefetchedPageKey != key) return;
            _prefetchedPage = page;
          })
          .catchError((_) {
            if (mounted && _prefetchedPageKey == key) {
              _prefetchedPage = null;
            }
          })
          .whenComplete(() {
            if (mounted && _prefetchedPageKey == key) {
              _prefetchingMore = false;
            }
          }),
    );
  }

  void _submitSearch() {
    final nextText = _searchController.text.trim();
    _reloadQuery(_activeQuery.copyWith(text: nextText));
  }

  void _clearSearch() {
    _searchController.clear();
    _reloadQuery(_activeQuery.copyWith(text: ''));
  }

  void _reloadQuery(PublicDomainBookQuery nextQuery) {
    _searchDebounce?.cancel();
    if (nextQuery.cacheKey == _activeQuery.cacheKey && !_loading) return;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() => _activeQuery = nextQuery);
    _loadBooks(reset: true);
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), _submitSearch);
    setState(() {});
  }

  Future<void> _refreshCurrentQuery() => _loadBooks(reset: true);

  Future<void> _openFilters() async {
    var nextMode = _activeQuery.searchMode;
    var nextLanguage = _activeQuery.languageCode;
    var nextSort = _activeQuery.sort;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: _s.menuColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: _s.mutedColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (_activeQuery.exactAuthor == null) ...[
                        _buildSheetSectionTitle('Search Mode'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final mode in PublicDomainSearchMode.values)
                              ChoiceChip(
                                label: Text(_labelForMode(mode)),
                                selected: nextMode == mode,
                                onSelected: (_) {
                                  setModalState(() => nextMode = mode);
                                },
                                selectedColor: _s.accentColor.withValues(
                                  alpha: 0.18,
                                ),
                                labelStyle: _s.uiText(
                                  color: nextMode == mode
                                      ? _s.accentColor
                                      : _s.textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      _buildSheetSectionTitle('Language'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final code in _languageChoices)
                            ChoiceChip(
                              label: Text(
                                code == null
                                    ? 'Any language'
                                    : labelForLanguageCode(code),
                              ),
                              selected: nextLanguage == code,
                              onSelected: (_) {
                                setModalState(() => nextLanguage = code);
                              },
                              selectedColor: _s.accentColor.withValues(
                                alpha: 0.18,
                              ),
                              labelStyle: _s.uiText(
                                color: nextLanguage == code
                                    ? _s.accentColor
                                    : _s.textColor,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildSheetSectionTitle('Sort'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final sort in PublicDomainSort.values)
                            ChoiceChip(
                              label: Text(_labelForSort(sort)),
                              selected: nextSort == sort,
                              onSelected: (_) {
                                setModalState(() => nextSort = sort);
                              },
                              selectedColor: _s.accentColor.withValues(
                                alpha: 0.18,
                              ),
                              labelStyle: _s.uiText(
                                color: nextSort == sort
                                    ? _s.accentColor
                                    : _s.textColor,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _reloadQuery(
                              _activeQuery.copyWith(
                                languageCode: nextLanguage,
                                clearLanguageCode: nextLanguage == null,
                                searchMode: nextMode,
                                sort: nextSort,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _s.accentColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: _s.uiText(fontWeight: FontWeight.w700),
                          ),
                          child: const Text('Apply Filters'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _performPrimaryBookAction(
    PublicDomainBook book, {
    ValueChanged<double?>? onProgress,
  }) async {
    if (_downloadingIds.contains(book.id)) return null;

    final existingFile = _existingFileFor(book);
    if (existingFile != null) {
      return existingFile.path;
    }

    if (!_hasReadableEpubUrl(book)) {
      _showDownloadError(
        const PublicDomainDownloadException(
          'This book does not have a readable EPUB download available.',
        ),
      );
      return null;
    }

    if (onProgress != null) {
      return _downloadBookForDetail(book, onProgress);
    }

    setState(() {
      _downloadingIds = {..._downloadingIds, book.id};
      _downloadTasks[book.id] = _PublicDomainDownloadTask(book: book);
      _downloadQueue.add(book.id);
    });

    unawaited(_startNextQueuedDownload());
    return null;
  }

  Future<String?> _downloadBookForDetail(
    PublicDomainBook book,
    ValueChanged<double?> onProgress,
  ) async {
    setState(() => _downloadingIds = {..._downloadingIds, book.id});
    onProgress(null);

    File? downloadedFile;
    var lastReportedProgress = 0.0;
    try {
      downloadedFile = await _downloadService.downloadBook(
        book,
        onProgress: (receivedBytes, totalBytes) {
          if (!mounted || totalBytes == null || totalBytes <= 0) return;
          final progress = (receivedBytes / totalBytes)
              .clamp(0.0, 1.0)
              .toDouble();
          if (progress - lastReportedProgress < 0.01 && progress < 1.0) {
            return;
          }
          lastReportedProgress = progress;
          onProgress(progress);
        },
      );
      onProgress(1);
      final preparedFile = await _prepareDownloadedBook(book, downloadedFile);
      await _loadLocalBooks();
      return mounted ? preparedFile.path : null;
    } catch (e) {
      if (downloadedFile != null) {
        try {
          await downloadedFile.delete();
        } catch (_) {}
      }
      if (!mounted) return null;
      if (e is! PublicDomainDownloadCancelledException) {
        _showDownloadError(e);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _downloadingIds = {..._downloadingIds}..remove(book.id));
      }
    }
  }

  Future<void> _startNextQueuedDownload() async {
    if (_activeDownloadId != null || _downloadQueue.isEmpty) return;

    final bookId = _downloadQueue.removeAt(0);
    final task = _downloadTasks[bookId];
    if (task == null) {
      unawaited(_startNextQueuedDownload());
      return;
    }

    setState(() {
      _activeDownloadId = bookId;
      task.phase = _DownloadTaskPhase.downloading;
      task.progress = null;
    });

    await _runDownloadTask(task);

    if (!mounted) return;
    setState(() => _activeDownloadId = null);
    unawaited(_startNextQueuedDownload());
  }

  Future<void> _runDownloadTask(_PublicDomainDownloadTask task) async {
    final book = task.book;
    File? downloadedFile;
    var lastReportedProgress = 0.0;
    try {
      downloadedFile = await _downloadService.downloadBook(
        book,
        cancelToken: task.cancelToken,
        onProgress: (receivedBytes, totalBytes) {
          if (!mounted || totalBytes == null || totalBytes <= 0) return;
          final progress = (receivedBytes / totalBytes)
              .clamp(0.0, 1.0)
              .toDouble();
          if (progress - lastReportedProgress < 0.01 && progress < 1.0) {
            return;
          }
          lastReportedProgress = progress;
          setState(() {
            task.progress = progress;
          });
        },
      );
      if (mounted) {
        setState(() {
          task.phase = _DownloadTaskPhase.preparing;
          task.progress = null;
        });
      }
      final preparedFile = await _prepareDownloadedBook(book, downloadedFile);
      await _loadLocalBooks();
      if (!mounted) return;
      _showDownloadComplete(book, preparedFile);
    } catch (e) {
      if (downloadedFile != null) {
        try {
          await downloadedFile.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      if (e is! PublicDomainDownloadCancelledException) {
        _showDownloadError(e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingIds = {..._downloadingIds}..remove(book.id);
          _downloadTasks.remove(book.id);
        });
      }
    }
  }

  void _cancelDownload(_PublicDomainDownloadTask task) {
    if (_activeDownloadId == task.book.id) {
      task.cancelToken.cancel();
      return;
    }

    setState(() {
      _downloadQueue.remove(task.book.id);
      _downloadTasks.remove(task.book.id);
      _downloadingIds = {..._downloadingIds}..remove(task.book.id);
    });
  }

  void _showDownloadComplete(PublicDomainBook book, File file) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Downloaded "${book.title}"',
          style: _s.uiText(color: _s.textColor, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _s.menuColor,
        action: SnackBarAction(
          label: 'Read',
          textColor: _s.accentColor,
          onPressed: () {
            if (mounted) Navigator.pop(context, file.path);
          },
        ),
      ),
    );
  }

  void _showDownloadError(Object error) {
    if (error is PublicDomainDownloadCancelledException) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _friendlyDownloadErrorMessage(error),
          style: _s.uiText(color: _s.textColor, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _s.menuColor,
      ),
    );
  }

  String _friendlyDownloadErrorMessage(Object error) {
    if (error is PublicDomainDownloadException) return error.message;
    return "Couldn't import this book. Please try again.";
  }

  bool _hasReadableEpubUrl(PublicDomainBook book) {
    final uri = Uri.tryParse(book.epubUrl.trim());
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Future<File> _prepareDownloadedBook(
    PublicDomainBook book,
    File downloadedFile,
  ) async {
    await _metadataService.init();
    final bookId = p.basename(downloadedFile.path);
    var metadata = _metadataService.getMetadata(bookId);
    if (metadata == null) {
      try {
        metadata = await _metadataService.extractAndCacheMetadata(
          downloadedFile,
        );
      } catch (_) {
        metadata = null;
      }
    }

    if (metadata == null) {
      metadata = BookMetadata(
        id: bookId,
        managedFilePath: downloadedFile.path,
        title: book.title,
        author: book.authorLabel,
        embeddedTitle: book.title,
        embeddedAuthor: book.authorLabel,
        titleSource: 'gutendex',
        authorSource: 'gutendex',
        metadataSource: 'gutendex',
        source: 'gutenberg',
        gutenbergId: book.id,
        sourceUrl: 'https://www.gutenberg.org/ebooks/${book.id}',
        downloadUrl: book.epubUrl,
        importedAt: DateTime.now().millisecondsSinceEpoch,
        originalSourceTitle: book.title,
        originalSourceAuthor: book.authorLabel,
        metadataConfidence: 0.78,
      );
      await _metadataService.updateMetadata(metadata);
    }

    var coverPath = metadata.coverImagePath;
    final coverUrl = book.coverUrl;
    if (coverPath == null && coverUrl != null) {
      try {
        final updated = await _metadataService.saveRemoteCover(
          bookId: bookId,
          coverUrl: coverUrl,
          source: 'gutendex',
        );
        coverPath = updated?.coverImagePath;
      } catch (_) {
        coverPath = null;
      }
    }

    final updated = await _metadataService.applyRemoteMetadata(
      bookId: bookId,
      title: book.title,
      author: book.authorLabel,
      source: 'gutendex',
      coverImagePath: coverPath,
      coverSource: coverPath == null ? null : 'gutendex',
      metadataConfidence: 0.78,
    );
    if (updated != null) {
      await _metadataService.updateMetadata(
        updated.copyWith(
          managedFilePath: downloadedFile.path,
          source: 'gutenberg',
          gutenbergId: book.id,
          sourceUrl: 'https://www.gutenberg.org/ebooks/${book.id}',
          downloadUrl: book.epubUrl,
          importedAt: DateTime.now().millisecondsSinceEpoch,
          originalSourceTitle: book.title,
          originalSourceAuthor: book.authorLabel,
        ),
      );
    }
    return downloadedFile;
  }

  Future<void> _openBookDetails(PublicDomainBook book) async {
    final isDownloaded = _isInLibrary(book);

    final pathToOpen = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => PublicDomainBookDetailScreen(
          book: book,
          settings: _s,
          isDownloaded: isDownloaded,
          onPrimaryAction: ({onProgress}) =>
              _performPrimaryBookAction(book, onProgress: onProgress),
          onAuthorSelected: _openAuthorBooks,
          onTopicSelected: _openTopicBooks,
        ),
      ),
    );

    if (pathToOpen != null && mounted) {
      Navigator.pop(context, pathToOpen);
      return;
    }

    await _loadLocalBooks();
  }

  Future<void> _openAuthorBooks(PublicDomainPerson author) async {
    final pathToOpen = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => PublicDomainBooksScreen.forAuthor(
          settings: _s,
          author: author,
          languageCode: _activeQuery.languageCode,
          sort: _activeQuery.sort,
        ),
      ),
    );

    if (pathToOpen != null && mounted) {
      Navigator.pop(context, pathToOpen);
      return;
    }

    await _loadLocalBooks();
  }

  Future<void> _openTopicBooks(String topic) async {
    final pathToOpen = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => PublicDomainBooksScreen.forTopic(
          settings: _s,
          topic: topic,
          languageCode: _activeQuery.languageCode,
          sort: _activeQuery.sort,
        ),
      ),
    );

    if (pathToOpen != null && mounted) {
      Navigator.pop(context, pathToOpen);
      return;
    }

    await _loadLocalBooks();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = _s.isDark ? ThemeData.dark() : ThemeData.light();

    return Theme(
      data: baseTheme.copyWith(
        scaffoldBackgroundColor: _s.backgroundColor,
        colorScheme: baseTheme.colorScheme.copyWith(
          surface: _s.backgroundColor,
          onSurface: _s.textColor,
          surfaceContainerHighest: _s.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Scaffold(
        backgroundColor: _s.backgroundColor,
        appBar: AppBar(
          title: Text(
            widget.title,
            style: _s.uiText(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: -0.3,
            ),
          ),
          centerTitle: true,
          backgroundColor: _s.backgroundColor,
          foregroundColor: _s.textColor,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildSearchHeader(),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
            if (_downloadTasks.isNotEmpty) _buildDownloadStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    final summaryParts = <String>[
      _labelForMode(_activeQuery.searchMode),
      _activeQuery.languageCode == null
          ? 'Any language'
          : labelForLanguageCode(_activeQuery.languageCode!),
      _labelForSort(_activeQuery.sort),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.subtitle,
            style: _s.uiText(fontSize: 13, color: _s.mutedColor, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            'For deeper catalogue browsing, visit Project Gutenberg.',
            style: _s.uiText(
              fontSize: 12,
              color: _s.mutedColor.withValues(alpha: 0.82),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            onSubmitted: (_) => _submitSearch(),
            textInputAction: TextInputAction.search,
            onChanged: (_) => _scheduleSearch(),
            style: _s.uiText(color: _s.textColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: _activeQuery.searchMode == PublicDomainSearchMode.topic
                  ? 'Search subjects or bookshelves'
                  : _activeQuery.exactAuthor != null
                  ? 'Search within this author'
                  : 'Search title or author',
              hintStyle: _s.uiText(color: _s.mutedColor),
              prefixIcon: Icon(Icons.search_rounded, color: _s.mutedColor),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Filters',
                    onPressed: _openFilters,
                    icon: Icon(Icons.tune_rounded, color: _s.mutedColor),
                  ),
                  if (_searchController.text.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                      icon: Icon(Icons.close_rounded, color: _s.mutedColor),
                    ),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: _submitSearch,
                    icon: Icon(
                      Icons.arrow_forward_rounded,
                      color: _s.mutedColor,
                    ),
                  ),
                ],
              ),
              filled: true,
              fillColor: _s.menuColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _s.mutedColor.withValues(alpha: 0.08),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _s.mutedColor.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _s.accentColor),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            summaryParts.join('  •  '),
            style: _s.uiText(
              fontSize: 12,
              color: _s.mutedColor.withValues(alpha: 0.9),
            ),
          ),
          if (_activeQuery.exactAuthor != null) ...[
            const SizedBox(height: 10),
            InputChip(
              label: Text('Author: ${_activeQuery.exactAuthor!}'),
              onDeleted: () {
                _reloadQuery(_activeQuery.copyWith(clearExactAuthor: true));
              },
              backgroundColor: _s.menuColor,
              side: BorderSide(color: _s.mutedColor.withValues(alpha: 0.12)),
              labelStyle: _s.uiText(
                color: _s.textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadStatusBar() {
    final activeTask = _activeDownloadId == null
        ? null
        : _downloadTasks[_activeDownloadId];
    final task = activeTask ?? _downloadTasks.values.first;
    final queuedCount = activeTask == null
        ? (_downloadTasks.length > 1 ? _downloadTasks.length - 1 : 0)
        : _downloadTasks.length - 1;
    final progress = task.progress;
    final isQueued = task.phase == _DownloadTaskPhase.queued;
    final isPreparing = task.phase == _DownloadTaskPhase.preparing;
    final statusText = isQueued
        ? 'Queued'
        : isPreparing
        ? 'Adding to library'
        : progress == null
        ? 'Downloading EPUB'
        : 'Downloading ${(progress * 100).floor()}%';
    final queueText = queuedCount > 0 ? ' • $queuedCount waiting' : '';
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      left: 20,
      right: 20,
      bottom: safeBottom + 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: _s.menuColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _s.mutedColor.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _s.isDark ? 0.34 : 0.14),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: isQueued
                    ? Icon(
                        Icons.schedule_rounded,
                        color: _s.accentColor,
                        size: 22,
                      )
                    : CircularProgressIndicator(
                        value: isPreparing ? null : progress,
                        strokeWidth: 2.6,
                        color: _s.accentColor,
                        backgroundColor: _s.accentColor.withValues(alpha: 0.16),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$statusText$queueText',
                      style: _s.uiText(
                        color: _s.textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.book.title,
                      style: _s.uiText(
                        color: _s.mutedColor,
                        fontSize: 12,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isQueued && progress != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          color: _s.accentColor,
                          backgroundColor: _s.accentColor.withValues(
                            alpha: 0.16,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Cancel download',
                onPressed: () => _cancelDownload(task),
                icon: Icon(Icons.close_rounded, color: _s.mutedColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _buildSkeletonList();
    }

    if (_error != null) {
      return _buildMessageState(
        icon: Icons.wifi_off_rounded,
        title: 'Catalog unavailable',
        message: _error ?? 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: () => _loadBooks(reset: true),
      );
    }

    if (_books.isEmpty) {
      return _buildMessageState(
        icon: Icons.search_off_rounded,
        title: 'No books found',
        message: 'Try a shorter search or adjust the filters.',
        actionLabel: 'Clear search',
        onAction: () {
          _clearSearch();
        },
      );
    }

    return RefreshIndicator(
      color: _s.accentColor,
      backgroundColor: _s.menuColor,
      onRefresh: _refreshCurrentQuery,
      child: ListView.separated(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          _downloadTasks.isEmpty ? 28 : 112,
        ),
        itemCount:
            _books.length +
            (_hasNextPage ? 1 : 0) +
            (_refreshing || _statusMessage != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (_refreshing || _statusMessage != null) {
            if (index == 0) return _buildStatusBanner();
            index -= 1;
          }
          if (index >= _books.length) {
            return _buildLoadMoreButton();
          }
          return _buildBookCard(_books[index]);
        },
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        _downloadTasks.isEmpty ? 28 : 112,
      ),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => _buildSkeletonListItem(),
    );
  }

  Widget _buildSkeletonListItem() {
    return Container(
      height: 124,
      padding: const EdgeInsets.all(14),
      decoration: AppUi.surfaceCard(_s, prominent: true),
      child: Row(
        children: [
          _buildSkeletonBox(width: 58, height: 84),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonBox(width: double.infinity, height: 16),
                const SizedBox(height: 10),
                _buildSkeletonBox(width: 160, height: 12),
                const Spacer(),
                Row(
                  children: [
                    _buildSkeletonBox(width: 96, height: 11),
                    const Spacer(),
                    _buildSkeletonBox(width: 92, height: 34),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonBox({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _s.mutedColor.withValues(alpha: _s.isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _s.menuColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _s.mutedColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          if (_refreshing) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _s.accentColor,
              ),
            ),
            const SizedBox(width: 10),
          ] else
            Icon(
              _showingSavedResults
                  ? Icons.cloud_off_rounded
                  : Icons.info_outline_rounded,
              size: 16,
              color: _s.mutedColor,
            ),
          if (!_refreshing) const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage ?? 'Refreshing Project Gutenberg',
              style: _s.uiText(fontSize: 12, color: _s.mutedColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _s.mutedColor.withValues(alpha: 0.5), size: 48),
            const SizedBox(height: 18),
            Text(
              title,
              style: _s.uiText(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _s.textColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: _s.uiText(
                fontSize: 14,
                color: _s.mutedColor,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: _s.accentColor),
              child: Text(
                actionLabel,
                style: _s.uiText(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCard(PublicDomainBook book) {
    final isDownloaded = _isInLibrary(book);
    final isDownloading = _downloadingIds.contains(book.id);
    final downloadTask = _downloadTasks[book.id];
    final summary = book.summary;
    final topicChips = book.topicLabels.take(2).toList(growable: false);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openBookDetails(book),
        borderRadius: AppUi.cardRadius(),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: AppUi.surfaceCard(_s, prominent: true),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(book),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            style: _s.uiText(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _s.textColor,
                              height: 1.28,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDownloaded) ...[
                          const SizedBox(width: 8),
                          _buildInLibraryBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.authorLabel,
                      style: _s.uiText(fontSize: 13, color: _s.mutedColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (summary != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        summary,
                        style: _s.uiText(
                          fontSize: 12,
                          color: _s.mutedColor.withValues(alpha: 0.86),
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (topicChips.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final topic in topicChips)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: AppUi.accentPill(_s),
                              child: Text(
                                topic,
                                style: _s.uiText(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _s.accentColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${book.downloadCount} downloads',
                            style: _s.uiText(
                              fontSize: 11,
                              color: _s.mutedColor.withValues(alpha: 0.65),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 34,
                          child: ElevatedButton.icon(
                            onPressed: isDownloading
                                ? null
                                : () async {
                                    final path =
                                        await _performPrimaryBookAction(book);
                                    if (path != null && mounted) {
                                      Navigator.pop(context, path);
                                    }
                                  },
                            icon: isDownloading
                                ? downloadTask?.phase ==
                                          _DownloadTaskPhase.queued
                                      ? const Icon(
                                          Icons.schedule_rounded,
                                          size: 16,
                                        )
                                      : SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _s.textColor,
                                          ),
                                        )
                                : Icon(
                                    isDownloaded
                                        ? Icons.menu_book_rounded
                                        : Icons.download_rounded,
                                    size: 16,
                                  ),
                            label: Text(
                              isDownloading
                                  ? downloadTask?.phase ==
                                            _DownloadTaskPhase.queued
                                        ? 'Queued'
                                        : 'Saving'
                                  : isDownloaded
                                  ? 'Open'
                                  : 'Download',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _s.accentColor,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: _s.mutedColor.withValues(
                                alpha: 0.12,
                              ),
                              disabledForegroundColor: _s.mutedColor,
                              elevation: 0,
                              textStyle: _s.uiText(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInLibraryBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: _s.accentColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _s.accentColor.withValues(alpha: 0.22)),
      ),
      child: Text(
        'In library',
        style: _s.uiText(
          color: _s.accentColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCover(PublicDomainBook book) {
    final coverUrl = book.coverUrl;
    if (coverUrl == null) {
      return _buildGeneratedCover(book);
    }

    return ClipRRect(
      borderRadius: AppUi.cardRadius(AppUi.radiusSm),
      child: Stack(
        children: [
          _buildGeneratedCover(book),
          Image.network(
            coverUrl,
            width: 58,
            height: 84,
            fit: BoxFit.cover,
            cacheWidth: 116,
            headers: const {'User-Agent': PublicDomainBookService.userAgent},
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: child,
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedCover(PublicDomainBook book) {
    final initials = book.title
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Container(
      width: 58,
      height: 84,
      decoration: BoxDecoration(
        color: _s.accentColor.withValues(alpha: 0.16),
        borderRadius: AppUi.cardRadius(AppUi.radiusSm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _s.isDark ? 0.2 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? 'B' : initials,
        style: _s.uiText(
          color: _s.accentColor,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    if (_loadingMore) {
      return Column(
        children: [
          _buildSkeletonListItem(),
          const SizedBox(height: 10),
          _buildSkeletonListItem(),
        ],
      );
    }

    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: _loadingMore ? null : () => _loadBooks(reset: false),
        style: OutlinedButton.styleFrom(
          foregroundColor: _s.accentColor,
          side: BorderSide(color: _s.accentColor.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text('Load more', style: _s.uiText(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildSheetSectionTitle(String title) {
    return Text(
      title,
      style: _s.uiText(
        color: _s.textColor,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  String _labelForMode(PublicDomainSearchMode mode) {
    switch (mode) {
      case PublicDomainSearchMode.titleAuthor:
        return 'Title & Author';
      case PublicDomainSearchMode.topic:
        return 'Topics';
    }
  }

  String _labelForSort(PublicDomainSort sort) {
    switch (sort) {
      case PublicDomainSort.popular:
        return 'Popular';
      case PublicDomainSort.ascending:
        return 'Oldest IDs';
      case PublicDomainSort.descending:
        return 'Newest IDs';
    }
  }
}
