import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/services/book_preparse_service.dart';
import 'package:nalori/services/book_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_preparse_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> bookFile(String name) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsString('epub bytes', flush: true);
    return file;
  }

  test('foreground parse starts before paused background queue work', () async {
    final parseOrder = <String>[];
    final parseCompleters = <String, Completer<void>>{};

    final service = BookPreparseService.testing(
      probeCachedBook: (bookId, identity) async => BookCacheProbe(
        status: BookCacheProbeStatus.noCache,
        bookId: bookId,
        identity: identity,
        cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
      ),
      loadCachedBook: (_) async => null,
      cacheParsedBook:
          ({
            required bookId,
            required title,
            required chunks,
            required anchorMap,
            required chapters,
            required searchIndex,
            fileIdentity,
          }) async => BookCacheWriteResult(
            status: BookCacheWriteStatus.stored,
            bookId: bookId,
            cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
          ),
      parseFile: (file) async {
        final bookId = p.basename(file.path);
        parseOrder.add(bookId);
        final completer = Completer<void>();
        parseCompleters[bookId] = completer;
        await completer.future;
        return (
          title: bookId,
          chunks: [BookChunk(index: 0, type: BookChunkType.text, text: bookId)],
          anchorMap: <String, int>{},
          chapters: <ChapterInfo>[],
          searchIndex: <String, List<int>>{},
        );
      },
    );

    final background = await bookFile('background.epub');
    final foreground = await bookFile('foreground.epub');

    service.beginForegroundWork('test_gate');
    service.queueBooks([background]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(parseOrder, isEmpty);

    final foregroundFuture = service.ensureParsed(foreground);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(parseOrder, ['foreground.epub']);
    expect(parseCompleters, contains('foreground.epub'));
    parseCompleters['foreground.epub']!.complete();
    await foregroundFuture;

    expect(parseOrder, ['foreground.epub']);
    service.endForegroundWork('test_gate');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(parseOrder, ['foreground.epub', 'background.epub']);
    parseCompleters['background.epub']!.complete();
  });

  test(
    'suppressed foreground book is not parsed by background queue',
    () async {
      final parseOrder = <String>[];

      final service = BookPreparseService.testing(
        probeCachedBook: (bookId, identity) async => BookCacheProbe(
          status: BookCacheProbeStatus.noCache,
          bookId: bookId,
          identity: identity,
          cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
        ),
        loadCachedBook: (_) async => null,
        cacheParsedBook:
            ({
              required bookId,
              required title,
              required chunks,
              required anchorMap,
              required chapters,
              required searchIndex,
              fileIdentity,
            }) async => BookCacheWriteResult(
              status: BookCacheWriteStatus.stored,
              bookId: bookId,
              cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
            ),
        parseFile: (file) async {
          final bookId = p.basename(file.path);
          parseOrder.add(bookId);
          return (
            title: bookId,
            chunks: [
              BookChunk(index: 0, type: BookChunkType.text, text: bookId),
            ],
            anchorMap: <String, int>{},
            chapters: <ChapterInfo>[],
            searchIndex: <String, List<int>>{},
          );
        },
      );

      final active = await bookFile('active.epub');
      final background = await bookFile('background.epub');

      service.suppressBackgroundBook('active.epub');
      service.queueBooks([active, background]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(parseOrder, ['background.epub']);
      service.resumeBackgroundBook('active.epub');
    },
  );

  test(
    'known oversized preparation is reused until the EPUB changes',
    () async {
      var parseCount = 0;
      var knownTooLarge = false;
      BookCacheFileIdentity? storedIdentity;
      final file = await bookFile('oversized.epub');

      final service = BookPreparseService.testing(
        probeCachedBook: (bookId, identity) async => BookCacheProbe(
          status:
              knownTooLarge &&
                  storedIdentity!.fileSizeBytes == identity.fileSizeBytes
              ? BookCacheProbeStatus.knownTooLarge
              : BookCacheProbeStatus.noCache,
          bookId: bookId,
          identity: identity,
          serializedSizeBytes: knownTooLarge ? 1024 : null,
          cacheLimitBytes: 100,
        ),
        cacheParsedBook:
            ({
              required bookId,
              required title,
              required chunks,
              required anchorMap,
              required chapters,
              required searchIndex,
              fileIdentity,
            }) async {
              knownTooLarge = true;
              storedIdentity = fileIdentity;
              return BookCacheWriteResult(
                status: BookCacheWriteStatus.tooLarge,
                bookId: bookId,
                identity: fileIdentity,
                serializedSizeBytes: 1024,
                cacheLimitBytes: 100,
              );
            },
        parseFile: (file) async {
          parseCount++;
          return (
            title: 'Oversized',
            chunks: [
              const BookChunk(index: 0, type: BookChunkType.text, text: 'text'),
            ],
            anchorMap: <String, int>{},
            chapters: <ChapterInfo>[],
            searchIndex: <String, List<int>>{},
          );
        },
      );

      expect(
        (await service.ensureParsed(file)).status,
        BookPreparationStatus.tooLarge,
      );
      expect(
        (await service.ensureParsed(file)).status,
        BookPreparationStatus.tooLarge,
      );
      expect(parseCount, 1);

      await file.writeAsString('changed epub bytes', flush: true);
      expect(
        (await service.ensureParsed(file)).status,
        BookPreparationStatus.tooLarge,
      );
      expect(parseCount, 2);
    },
  );

  test(
    'valid background payload probe does not deserialize the book',
    () async {
      var parseCount = 0;
      var deserializeCount = 0;
      final file = await bookFile('cached.epub');

      final service = BookPreparseService.testing(
        probeCachedBook: (bookId, identity) async => BookCacheProbe(
          status: BookCacheProbeStatus.validPayload,
          bookId: bookId,
          identity: identity,
          cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
        ),
        loadCachedBook: (_) async {
          deserializeCount++;
          return null;
        },
        parseFile: (_) async {
          parseCount++;
          throw StateError('should not parse');
        },
      );

      final result = await service.ensureParsed(
        file,
        priority: BookPreparsePriority.background,
        loadCachedBook: false,
      );

      expect(result.status, BookPreparationStatus.alreadyCached);
      expect(deserializeCount, 0);
      expect(parseCount, 0);
    },
  );

  test('an explicit request parses only its requested book', () async {
    final parsedBooks = <String>[];
    final service = BookPreparseService.testing(
      probeCachedBook: (bookId, identity) async => BookCacheProbe(
        status: BookCacheProbeStatus.noCache,
        bookId: bookId,
        identity: identity,
        cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
      ),
      cacheParsedBook:
          ({
            required bookId,
            required title,
            required chunks,
            required anchorMap,
            required chapters,
            required searchIndex,
            fileIdentity,
          }) async => BookCacheWriteResult(
            status: BookCacheWriteStatus.stored,
            bookId: bookId,
            cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
          ),
      parseFile: (file) async {
        parsedBooks.add(p.basename(file.path));
        return (
          title: 'One',
          chunks: const <BookChunk>[],
          anchorMap: <String, int>{},
          chapters: <ChapterInfo>[],
          searchIndex: <String, List<int>>{},
        );
      },
    );
    final requested = await bookFile('requested.epub');
    await bookFile('unrelated.epub');

    await service.ensureParsed(requested);

    expect(parsedBooks, ['requested.epub']);
  });

  test('queueBooks deduplicates duplicate explicit submissions', () async {
    var parseCount = 0;
    final service = BookPreparseService.testing(
      probeCachedBook: (bookId, identity) async => BookCacheProbe(
        status: BookCacheProbeStatus.noCache,
        bookId: bookId,
        identity: identity,
        cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
      ),
      cacheParsedBook:
          ({
            required bookId,
            required title,
            required chunks,
            required anchorMap,
            required chapters,
            required searchIndex,
            fileIdentity,
          }) async => BookCacheWriteResult(
            status: BookCacheWriteStatus.stored,
            bookId: bookId,
            cacheLimitBytes: BookCacheService.parsedBookCacheLimitBytes,
          ),
      parseFile: (_) async {
        parseCount++;
        return (
          title: 'One',
          chunks: const <BookChunk>[],
          anchorMap: <String, int>{},
          chapters: <ChapterInfo>[],
          searchIndex: <String, List<int>>{},
        );
      },
    );
    final file = await bookFile('dedupe.epub');

    service.queueBooks([file, file]);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(parseCount, 1);
  });
}
