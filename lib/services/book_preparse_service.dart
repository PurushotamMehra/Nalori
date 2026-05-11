import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'book_cache_service.dart';
import 'epub_parser.dart';

/// Builds parsed-book caches in the background and shares in-flight parses.
///
/// This service only prepares the screen-independent parsed EPUB cache:
/// chunks, anchors, chapters, and search index. Display/page layout remains
/// owned by ReaderScreen because it depends on screen and typography settings.
class BookPreparseService {
  BookPreparseService._();

  static final BookPreparseService instance = BookPreparseService._();

  final BookCacheService _cacheService = BookCacheService();
  final Map<String, Future<CachedBook>> _inFlightParses = {};
  final Queue<File> _queue = Queue<File>();
  final Set<String> _queuedBookIds = {};

  Future<void> _parseTail = Future<void>.value();
  bool _isProcessingQueue = false;
  int _queueGeneration = 0;

  void queueBooks(List<File> books) {
    _queueGeneration++;
    _queue.clear();
    _queuedBookIds.clear();

    for (final file in books) {
      final bookId = p.basename(file.path);
      if (_inFlightParses.containsKey(bookId) || !_queuedBookIds.add(bookId)) {
        continue;
      }
      _queue.add(file);
      _log('preparse queued: $bookId');
    }

    if (_queue.isEmpty) return;
    unawaited(_processQueue(_queueGeneration));
  }

  void cancelQueue() {
    _queueGeneration++;
    _queue.clear();
    _queuedBookIds.clear();
  }

  Future<CachedBook> ensureParsed(File file) async {
    final bookId = p.basename(file.path);

    final fileStat = await file.stat();
    final bookModifiedMs = fileStat.modified.millisecondsSinceEpoch;
    final hasCached = await _cacheService.hasCachedBook(bookId, bookModifiedMs);
    if (hasCached) {
      final cached = await _cacheService.loadCachedBook(bookId);
      if (cached != null) {
        _log('preparse skipped cache hit: $bookId');
        return cached;
      }
    }

    final existing = _inFlightParses[bookId];
    if (existing != null) {
      _log('preparse joined existing parse: $bookId');
      return existing;
    }

    final future = _scheduleParseAndCache(bookId, file);
    _inFlightParses[bookId] = future;
    future.whenComplete(() {
      if (identical(_inFlightParses[bookId], future)) {
        _inFlightParses.remove(bookId);
      }
    });
    return future;
  }

  Future<void> _processQueue(int generation) async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_queue.isNotEmpty && generation == _queueGeneration) {
        final file = _queue.removeFirst();
        final bookId = p.basename(file.path);
        _queuedBookIds.remove(bookId);

        if (!await file.exists()) {
          _log('preparse skipped missing file: $bookId');
          continue;
        }

        try {
          await ensureParsed(file);
          _log('preparse completed: $bookId');
        } catch (e) {
          _log('preparse failed: $bookId $e');
        }

        if (generation == _queueGeneration && _queue.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    } finally {
      _isProcessingQueue = false;
      if (_queue.isNotEmpty) {
        unawaited(_processQueue(_queueGeneration));
      }
    }
  }

  Future<CachedBook> _scheduleParseAndCache(String bookId, File file) {
    final completer = Completer<CachedBook>();
    _parseTail = _parseTail
        .catchError((_) {
          // Keep the serial parse chain alive after a previous book fails.
        })
        .then((_) async {
          try {
            if (!await file.exists()) {
              throw FileSystemException(
                'EPUB file no longer exists',
                file.path,
              );
            }
            final parsed = await _parseAndCache(bookId, file);
            completer.complete(parsed);
          } catch (e, stackTrace) {
            completer.completeError(e, stackTrace);
          }
        });
    return completer.future;
  }

  Future<CachedBook> _parseAndCache(String bookId, File file) async {
    _log('preparse started: $bookId');
    final result = await EpubParserService.parseFileInBackground(file);
    final parsed = CachedBook(
      title: result.title,
      chunks: result.chunks,
      anchorMap: result.anchorMap,
      chapters: result.chapters,
      searchIndex: result.searchIndex,
    );

    await _cacheService.cacheBook(
      bookId: bookId,
      title: parsed.title,
      chunks: parsed.chunks,
      anchorMap: parsed.anchorMap,
      chapters: parsed.chapters,
      searchIndex: parsed.searchIndex,
    );

    return parsed;
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('BookPreparseService: $message');
    }
  }
}
