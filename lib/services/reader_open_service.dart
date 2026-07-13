import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/book_metadata.dart';
import '../models/stable_book_location.dart';
import 'book_metadata_service.dart';
import 'book_preparse_service.dart';
import 'lazy_book_session.dart';

const bool _readerOpenDiagEnabled = bool.fromEnvironment('NALORI_EPUB_DIAG');
const String _readerOpenDiagPrefix = 'NALORI_EPUB_DIAG';

void _readerOpenDiagLog(String phase, Map<String, Object?> fields) {
  if (!_readerOpenDiagEnabled) return;
  final parts = <String>[
    _readerOpenDiagPrefix,
    'phase=$phase',
    'ts=${DateTime.now().toIso8601String()}',
    for (final entry in fields.entries)
      if (entry.value != null) '${entry.key}=${entry.value}',
  ];
  // ignore: avoid_print
  print(parts.join(' '));
}

enum ReaderOpenFailureKind { unavailable, unreadable, cancelled, unknown }

final class ReaderOpenException implements Exception {
  const ReaderOpenException(this.kind, this.message, [this.cause]);

  final ReaderOpenFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class ReaderOpenResult {
  const ReaderOpenResult({
    required this.bookId,
    required this.title,
    required this.session,
    required this.targetLocation,
    required this.window,
    required this.metadata,
    required this.elapsedMs,
  });

  final String bookId;
  final String title;
  final LazyBookSession session;
  final StableBookLocation targetLocation;
  final LazyLoadedContentWindow window;
  final BookMetadata? metadata;
  final int elapsedMs;
}

final class ReaderOpenOperation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

final class ReaderOpenService {
  ReaderOpenService({BookMetadataService? metadataService})
    : _metadataService = metadataService ?? BookMetadataService();

  final BookMetadataService _metadataService;

  Future<ReaderOpenResult> openLazy({
    required File bookFile,
    BookMetadata? metadata,
    StableBookLocation? requestedLocation,
    int? legacyLastReadIndex,
    ReaderOpenOperation? operation,
    String caller = 'unknown',
  }) async {
    final bookId = p.basename(bookFile.path);
    final stopwatch = Stopwatch()..start();
    LazyBookSession? session;
    var transferred = false;

    try {
      await _validateReadableEpub(bookFile);
      _throwIfCancelled(operation);

      await _metadataService.init();
      final meta = metadata ?? _metadataService.getMetadata(bookId);

      BookPreparseService.instance.cancelQueue();
      BookPreparseService.instance.suppressBackgroundBook(bookId);
      BookPreparseService.instance.beginForegroundWork(
        'lazyReaderOpen:$bookId',
      );

      session = LazyBookSession();
      _readerOpenDiagLog('lazy_reader_open_begin', {
        'book': bookId,
        'caller': caller,
        'path': bookFile.path,
      });
      final index = await session.open(bookFile);
      _throwIfCancelled(operation);

      _readerOpenDiagLog('lazy_reader_index_ready', {
        'book': bookId,
        'caller': caller,
        'lazySessionId': identityHashCode(session),
        'sectionsIndexed': index.spine.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });

      final persistedLocation = requestedLocation ?? meta?.lastReadLocation;
      StableLocationResolution? persistedResolution;
      if (persistedLocation != null) {
        persistedResolution = await session.resolveStableLocation(
          persistedLocation,
        );
      }
      final canMigratePersisted = persistedResolution?.location != null;
      final targetLocation =
          persistedResolution?.location ??
          (persistedLocation == null
              ? _resolveInitialLocation(
                  session: session,
                  legacyLastReadIndex:
                      legacyLastReadIndex ?? meta?.lastReadIndex,
                  totalChunks: meta?.totalChunks,
                )
              : session.initialLocation());
      _readerOpenDiagLog('lazy_reader_target_resolved', {
        'book': bookId,
        'caller': caller,
        'lazySessionId': identityHashCode(session),
        'spineIndex': targetLocation.spineIndex,
        'href': targetLocation.href,
        'localChunkIndex': targetLocation.localChunkIndex,
        'textOffset': targetLocation.textOffset,
        'localDisplayIndex': targetLocation.localDisplayIndex,
        'hasLayoutFingerprint': targetLocation.readerLayoutFingerprint != null,
      });

      final window = await session.loadAround(targetLocation, after: 0);
      _throwIfCancelled(operation);
      final resolvedTarget = session.currentLocation ?? targetLocation;

      final legacyIndex = legacyLastReadIndex ?? meta?.lastReadIndex ?? 0;
      final canMigrateLegacyPosition =
          persistedLocation == null &&
          legacyIndex > 0 &&
          (meta?.totalChunks ?? 0) > 1;
      if (meta != null) {
        await _metadataService.updateMetadata(
          meta.copyWith(
            lastOpenedAt: DateTime.now().millisecondsSinceEpoch,
            lastReadLocation: canMigratePersisted || canMigrateLegacyPosition
                ? resolvedTarget
                : meta.lastReadLocation,
          ),
        );
      }

      _readerOpenDiagLog('lazy_reader_section_ready', {
        'book': bookId,
        'caller': caller,
        'lazySessionId': identityHashCode(session),
        'sectionsParsedBeforeReady': window.sections.length,
        'chunks': window.chunks.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });

      final knownTotalChunks = meta?.totalChunks ?? window.chunks.length;
      if (meta != null && meta.totalChunks == 0) {
        final readingSummary = BookReadingSummary.fromParsedBook(
          chunks: window.chunks,
          chapters: window.chapters,
        );
        unawaited(
          _metadataService.updateReadingSummary(
            bookId: bookId,
            summary: readingSummary,
            totalChunks: knownTotalChunks,
          ),
        );
      }

      transferred = true;
      return ReaderOpenResult(
        bookId: bookId,
        title: index.title,
        session: session,
        targetLocation: resolvedTarget,
        window: window,
        metadata: meta,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } on ReaderOpenException {
      rethrow;
    } catch (e) {
      throw ReaderOpenException(
        ReaderOpenFailureKind.unknown,
        'Failed to open book',
        e,
      );
    } finally {
      if (!transferred && session != null) {
        unawaited(session.close());
      }
      BookPreparseService.instance.endForegroundWork('lazyReaderOpen:$bookId');
      BookPreparseService.instance.resumeBackgroundBook(bookId);
    }
  }

  Future<void> _validateReadableEpub(File bookFile) async {
    if (p.extension(bookFile.path).toLowerCase() != '.epub') {
      throw const ReaderOpenException(
        ReaderOpenFailureKind.unreadable,
        'This file is not an EPUB book.',
      );
    }
    try {
      final stat = await bookFile.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
        throw const ReaderOpenException(
          ReaderOpenFailureKind.unavailable,
          'This book file is unavailable.',
        );
      }
    } on ReaderOpenException {
      rethrow;
    } catch (e) {
      throw ReaderOpenException(
        ReaderOpenFailureKind.unavailable,
        'This book file is unavailable.',
        e,
      );
    }
  }

  StableBookLocation _resolveInitialLocation({
    required LazyBookSession session,
    int? legacyLastReadIndex,
    int? totalChunks,
  }) {
    final legacyIndex = legacyLastReadIndex ?? 0;
    final chunkCount = totalChunks ?? 0;
    if (legacyIndex > 0 && chunkCount > 1 && session.index.spine.isNotEmpty) {
      final progress = (legacyIndex / (chunkCount - 1)).clamp(0.0, 1.0);
      return session.locationForWeightedProgression(
        progress,
        legacyGlobalChunkIndex: legacyIndex,
      );
    }

    return session.initialLocation();
  }

  void _throwIfCancelled(ReaderOpenOperation? operation) {
    if (operation?.isCancelled != true) return;
    throw const ReaderOpenException(
      ReaderOpenFailureKind.cancelled,
      'Opening was cancelled.',
    );
  }
}
