import 'book_cache_service.dart';
import 'lazy_epub_index_service.dart';
import 'lazy_section_repository.dart';
import 'parsed_section_cache_service.dart';
import 'segmented_display_cache_service.dart';

typedef SegmentedDisplayCacheFactory =
    Future<SegmentedDisplayCacheService> Function();

/// Coordinates deletion of reader-owned cache derivatives only.
///
/// User annotations, saved words, metadata, and stable locations are outside
/// this service and are deliberately untouched.
final class LazyReaderCacheCleanupService {
  LazyReaderCacheCleanupService({
    BookCacheService? bookCache,
    ParsedSectionCacheService? parsedSectionCache,
    LazyEpubIndexStore? indexStore,
    SharedLazySectionWorkCoordinator? workCoordinator,
    SegmentedDisplayCacheFactory? segmentedDisplayCacheFactory,
  }) : _bookCache = bookCache ?? BookCacheService(),
       _parsedSectionCache = parsedSectionCache ?? ParsedSectionCacheService(),
       _indexStore = indexStore ?? LazyEpubIndexStore(),
       _workCoordinator =
           workCoordinator ?? SharedLazySectionWorkCoordinator.instance,
       _segmentedDisplayCacheFactory =
           segmentedDisplayCacheFactory ??
           SegmentedDisplayCacheService.createDefault;

  final BookCacheService _bookCache;
  final ParsedSectionCacheService _parsedSectionCache;
  final LazyEpubIndexStore _indexStore;
  final SharedLazySectionWorkCoordinator _workCoordinator;
  final SegmentedDisplayCacheFactory _segmentedDisplayCacheFactory;

  Future<void> deleteDerivativesForBook(String bookId) async {
    _workCoordinator.invalidateBook(bookId);

    // Calling this before the first await publishes the parsed-cache tombstone
    // synchronously, so stale parse commits cannot recreate deleted records.
    final parsedDeletion = _parsedSectionCache.deleteForBook(bookId);
    final segmented = await _segmentedDisplayCacheFactory();
    await Future.wait([
      parsedDeletion,
      segmented.deleteForBook(bookId),
      _indexStore.deleteForBook(bookId),
    ]);
    await _bookCache.deleteDisplayChunks(bookId);
    await _bookCache.deleteCachedBook(bookId);
  }

  Future<void> clearAllDerivatives() async {
    _workCoordinator.invalidateAll();
    final parsedReset = _parsedSectionCache.clearAll();
    final segmented = await _segmentedDisplayCacheFactory();
    await Future.wait([
      parsedReset,
      segmented.clearAll(),
      _indexStore.clearAll(),
    ]);
    await _bookCache.clearAll();
  }
}
