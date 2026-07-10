import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import 'book_cache_service.dart';
import 'epub_parser.dart';

const bool _preparseDiagEnabled = bool.fromEnvironment('NALORI_EPUB_DIAG');
const String _preparseDiagPrefix = 'NALORI_EPUB_DIAG';

void _preparseDiagLog(String phase, Map<String, Object?> fields) {
  if (!_preparseDiagEnabled) return;
  final parts = <String>[
    _preparseDiagPrefix,
    'phase=$phase',
    'ts=${DateTime.now().toIso8601String()}',
    for (final entry in fields.entries)
      if (entry.value != null) '${entry.key}=${entry.value}',
  ];
  // ignore: avoid_print
  print(parts.join(' '));
}

enum BookPreparsePriority { foreground, background }

enum BookPreparationStatus { alreadyCached, stored, tooLarge, failed }

class BookPreparationResult {
  final BookPreparationStatus status;
  final String bookId;
  final BookCacheFileIdentity? fileIdentity;
  final CachedBook? cachedBook;
  final int? serializedSizeBytes;
  final int cacheLimitBytes;
  final String? failureMessage;

  const BookPreparationResult({
    required this.status,
    required this.bookId,
    required this.cacheLimitBytes,
    this.fileIdentity,
    this.cachedBook,
    this.serializedSizeBytes,
    this.failureMessage,
  });

  bool get hasCachedBook => cachedBook != null;
}

typedef EpubParseFile =
    Future<
      ({
        String title,
        List<BookChunk> chunks,
        Map<String, int> anchorMap,
        List<ChapterInfo> chapters,
        Map<String, List<int>> searchIndex,
      })
    >
    Function(File file);
typedef ProbeCachedBook =
    Future<BookCacheProbe> Function(
      String bookId,
      BookCacheFileIdentity identity,
    );
typedef LoadCachedBook = Future<CachedBook?> Function(String bookId);
typedef CacheParsedBook =
    Future<BookCacheWriteResult> Function({
      required String bookId,
      required String title,
      required List<BookChunk> chunks,
      required Map<String, int> anchorMap,
      required List<ChapterInfo> chapters,
      required Map<String, List<int>> searchIndex,
      BookCacheFileIdentity? fileIdentity,
    });

/// Builds parsed-book caches in the background and shares in-flight parses.
///
/// This service only prepares the screen-independent parsed EPUB cache:
/// chunks, anchors, chapters, and search index. Display/page layout remains
/// owned by ReaderScreen because it depends on screen and typography settings.
class BookPreparseService {
  BookPreparseService._({
    EpubParseFile? parseFile,
    ProbeCachedBook? probeCachedBook,
    LoadCachedBook? loadCachedBook,
    CacheParsedBook? cacheParsedBook,
  }) : _cacheService = BookCacheService(),
       _parseFile = parseFile ?? EpubParserService.parseFileInBackground,
       _probeCachedBook = probeCachedBook,
       _loadCachedBook = loadCachedBook,
       _cacheParsedBook = cacheParsedBook;

  @visibleForTesting
  BookPreparseService.testing({
    EpubParseFile? parseFile,
    ProbeCachedBook? probeCachedBook,
    LoadCachedBook? loadCachedBook,
    CacheParsedBook? cacheParsedBook,
  }) : this._(
         parseFile: parseFile,
         probeCachedBook: probeCachedBook,
         loadCachedBook: loadCachedBook,
         cacheParsedBook: cacheParsedBook,
       );

  static final BookPreparseService instance = BookPreparseService._();

  final BookCacheService _cacheService;
  final EpubParseFile _parseFile;
  final ProbeCachedBook? _probeCachedBook;
  final LoadCachedBook? _loadCachedBook;
  final CacheParsedBook? _cacheParsedBook;
  final Map<String, Future<BookPreparationResult>> _inFlightParses = {};
  final Queue<File> _queue = Queue<File>();
  final Set<String> _queuedBookIds = {};
  final Set<String> _foregroundBookIds = {};

  Future<void> _parseTail = Future<void>.value();
  bool _isProcessingQueue = false;
  int _queueGeneration = 0;
  int _foregroundPressure = 0;
  Completer<void>? _foregroundIdleCompleter;

  bool get hasForegroundPressure => _foregroundPressure > 0;

  void suppressBackgroundBook(String bookId) {
    _foregroundBookIds.add(bookId);
    _queuedBookIds.remove(bookId);
    _queue.removeWhere((queued) => p.basename(queued.path) == bookId);
    _preparseDiagLog('preparse_background_suppressed_book', {
      'book': bookId,
      'foregroundBooks': _foregroundBookIds.length,
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
    });
  }

  void resumeBackgroundBook(String bookId) {
    _foregroundBookIds.remove(bookId);
    _preparseDiagLog('preparse_background_resumed_book', {
      'book': bookId,
      'foregroundBooks': _foregroundBookIds.length,
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
    });
  }

  void beginForegroundWork(String reason) {
    _foregroundPressure++;
    _foregroundIdleCompleter ??= Completer<void>();
    _preparseDiagLog('preparse_foreground_begin', {
      'reason': reason,
      'foregroundPressure': _foregroundPressure,
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
    });
  }

  void endForegroundWork(String reason) {
    if (_foregroundPressure > 0) {
      _foregroundPressure--;
    }
    _preparseDiagLog('preparse_foreground_end', {
      'reason': reason,
      'foregroundPressure': _foregroundPressure,
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
    });
    if (_foregroundPressure == 0) {
      final completer = _foregroundIdleCompleter;
      _foregroundIdleCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      if (_queue.isNotEmpty) {
        unawaited(_processQueue(_queueGeneration));
      }
    }
  }

  void queueBooks(List<File> books) {
    _queueGeneration++;
    _queue.clear();
    _queuedBookIds.clear();

    for (final file in books) {
      final bookId = p.basename(file.path);
      if (_foregroundBookIds.contains(bookId) ||
          _inFlightParses.containsKey(bookId) ||
          !_queuedBookIds.add(bookId)) {
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

  Future<BookPreparationResult> ensureParsed(
    File file, {
    BookPreparsePriority priority = BookPreparsePriority.foreground,
    bool loadCachedBook = true,
  }) async {
    final bookId = p.basename(file.path);
    final isForeground = priority == BookPreparsePriority.foreground;

    if (isForeground) {
      beginForegroundWork('ensureParsed:$bookId');
      _queuedBookIds.remove(bookId);
      _queue.removeWhere((queued) => p.basename(queued.path) == bookId);
    } else {
      await _waitForForegroundIdle('background_ensureParsed:$bookId');
      _throwIfBackgroundSuppressed(bookId);
    }

    try {
      final fileStat = await file.stat();
      final identity = BookCacheFileIdentity(
        bookId: bookId,
        fileSizeBytes: fileStat.size,
        modifiedMs: fileStat.modified.millisecondsSinceEpoch,
      );
      final probe = await (_probeCachedBook ?? _cacheService.probeBook)(
        bookId,
        identity,
      );
      if (probe.status == BookCacheProbeStatus.knownTooLarge) {
        _log('preparse skipped known too large: $bookId');
        return BookPreparationResult(
          status: BookPreparationStatus.tooLarge,
          bookId: bookId,
          fileIdentity: identity,
          serializedSizeBytes: probe.serializedSizeBytes,
          cacheLimitBytes: probe.cacheLimitBytes,
        );
      }
      if (probe.hasValidPayload) {
        if (!loadCachedBook) {
          _log('preparse skipped valid cached payload: $bookId');
          return BookPreparationResult(
            status: BookPreparationStatus.alreadyCached,
            bookId: bookId,
            fileIdentity: identity,
            serializedSizeBytes: probe.serializedSizeBytes,
            cacheLimitBytes: probe.cacheLimitBytes,
          );
        }
        final cached = await (_loadCachedBook ?? _cacheService.loadCachedBook)(
          bookId,
        );
        if (cached != null) {
          _preparseDiagLog('preparse_cache_hit', {
            'book': bookId,
            'priority': priority.name,
            'parsedCacheVersion': BookCacheService.parsedBookCacheFormatVersion,
            'sourceChunks': cached.chunks.length,
            'anchors': cached.anchorMap.length,
            'chapters': cached.chapters.length,
          });
          _log('preparse skipped cache hit: $bookId');
          return BookPreparationResult(
            status: BookPreparationStatus.alreadyCached,
            bookId: bookId,
            fileIdentity: identity,
            cachedBook: cached,
            serializedSizeBytes: probe.serializedSizeBytes,
            cacheLimitBytes: probe.cacheLimitBytes,
          );
        }
      }

      final existing = _inFlightParses[bookId];
      if (existing != null) {
        _preparseDiagLog('preparse_join_inflight', {
          'book': bookId,
          'priority': priority.name,
        });
        _log('preparse joined existing parse: $bookId');
        return existing;
      }

      if (!isForeground) {
        _throwIfBackgroundSuppressed(bookId);
      }
      final future = _scheduleParseAndCache(bookId, file, identity, priority);
      _inFlightParses[bookId] = future;
      future.whenComplete(() {
        if (identical(_inFlightParses[bookId], future)) {
          _inFlightParses.remove(bookId);
        }
      });
      return await future;
    } catch (_) {
      return BookPreparationResult(
        status: BookPreparationStatus.failed,
        bookId: bookId,
        cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
        failureMessage: 'Unable to prepare this book right now.',
      );
    } finally {
      if (isForeground) {
        endForegroundWork('ensureParsed:$bookId');
      }
    }
  }

  Future<void> _processQueue(int generation) async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      while (_queue.isNotEmpty && generation == _queueGeneration) {
        final file = _queue.removeFirst();
        final bookId = p.basename(file.path);
        _queuedBookIds.remove(bookId);

        await _waitForForegroundIdle('background_queue:$bookId');
        if (generation != _queueGeneration) break;
        if (_foregroundBookIds.contains(bookId)) {
          _preparseDiagLog('preparse_background_suppressed', {
            'book': bookId,
            'reason': 'foreground_book_active',
            'queuedBooks': _queue.length,
            'inFlight': _inFlightParses.length,
          });
          continue;
        }

        if (!await file.exists()) {
          _log('preparse skipped missing file: $bookId');
          continue;
        }

        try {
          final result = await ensureParsed(
            file,
            priority: BookPreparsePriority.background,
            loadCachedBook: false,
          );
          _log('preparse ${result.status.name}: $bookId');
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

  Future<void> _waitForForegroundIdle(String reason) async {
    if (!hasForegroundPressure) return;
    _preparseDiagLog('preparse_background_paused', {
      'reason': reason,
      'foregroundPressure': _foregroundPressure,
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
    });
    final completer = _foregroundIdleCompleter;
    if (completer != null) {
      await completer.future;
    }
    _preparseDiagLog('preparse_background_resumed', {
      'reason': reason,
      'foregroundPressure': _foregroundPressure,
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
    });
  }

  void _throwIfBackgroundSuppressed(String bookId) {
    if (!_foregroundBookIds.contains(bookId)) return;
    _preparseDiagLog('preparse_background_suppressed', {
      'book': bookId,
      'reason': 'foreground_book_active',
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
    });
    throw StateError('Background preparse suppressed for active book $bookId');
  }

  Future<BookPreparationResult> _scheduleParseAndCache(
    String bookId,
    File file,
    BookCacheFileIdentity identity,
    BookPreparsePriority priority,
  ) {
    final completer = Completer<BookPreparationResult>();
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
            if (priority == BookPreparsePriority.background) {
              _throwIfBackgroundSuppressed(bookId);
            }
            final parsed = await _parseAndCache(bookId, file, identity);
            completer.complete(parsed);
          } catch (_) {
            completer.complete(
              BookPreparationResult(
                status: BookPreparationStatus.failed,
                bookId: bookId,
                fileIdentity: identity,
                cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
                failureMessage: 'Unable to prepare this book right now.',
              ),
            );
          }
        });
    return completer.future;
  }

  Future<BookPreparationResult> _parseAndCache(
    String bookId,
    File file,
    BookCacheFileIdentity identity,
  ) async {
    _log('preparse started: $bookId');
    _preparseDiagLog('preparse_parse_begin', {
      'book': bookId,
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
      'foregroundPressure': _foregroundPressure,
    });
    final result = await _parseFile(file);
    final parsed = CachedBook(
      title: result.title,
      chunks: result.chunks,
      anchorMap: result.anchorMap,
      chapters: result.chapters,
      searchIndex: result.searchIndex,
    );

    final cacheResult = await (_cacheParsedBook ?? _cacheService.cacheBook)(
      bookId: bookId,
      title: parsed.title,
      chunks: parsed.chunks,
      anchorMap: parsed.anchorMap,
      chapters: parsed.chapters,
      searchIndex: parsed.searchIndex,
      fileIdentity: identity,
    );

    _preparseDiagLog('preparse_parse_end', {
      'book': bookId,
      'sourceChunks': parsed.chunks.length,
      'anchors': parsed.anchorMap.length,
      'chapters': parsed.chapters.length,
      'queuedBooks': _queue.length,
      'inFlight': _inFlightParses.length,
      'foregroundPressure': _foregroundPressure,
    });
    return BookPreparationResult(
      status: switch (cacheResult.status) {
        BookCacheWriteStatus.stored => BookPreparationStatus.stored,
        BookCacheWriteStatus.tooLarge => BookPreparationStatus.tooLarge,
        BookCacheWriteStatus.failed => BookPreparationStatus.failed,
      },
      bookId: bookId,
      fileIdentity: identity,
      cachedBook: cacheResult.status == BookCacheWriteStatus.tooLarge
          ? null
          : parsed,
      serializedSizeBytes: cacheResult.serializedSizeBytes,
      cacheLimitBytes: cacheResult.cacheLimitBytes,
      failureMessage: cacheResult.failureMessage,
    );
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('BookPreparseService: $message');
    }
  }
}
