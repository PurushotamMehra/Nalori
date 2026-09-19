import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/reader_text_boundary.dart';
import 'package:nalori/services/book_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('text-boundary cache identities reject pre-migration artifacts', () {
    expect(BookCacheService.parsedBookCacheFormatVersion, 6);
    expect(BookCacheService.displayCacheFormatVersion, 3);
    expect(BookCacheService.displayLayoutVersion, 'v14');
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_book_cache_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<BookCacheWriteResult> store(
    BookCacheService service,
    BookCacheFileIdentity identity,
  ) => service.cacheBook(
    bookId: identity.bookId,
    title: 'Book',
    chunks: const [
      BookChunk(index: 0, type: BookChunkType.text, text: 'hello'),
    ],
    anchorMap: const {},
    chapters: const [],
    searchIndex: const {},
    fileIdentity: identity,
  );

  test('whole-cache probe validates payload without loading it', () async {
    final service = BookCacheService.testing(cacheDirectory: tempDir);
    const identity = BookCacheFileIdentity(
      bookId: 'book.epub',
      fileSizeBytes: 50,
      modifiedMs: 100,
    );

    expect(
      (await store(service, identity)).status,
      BookCacheWriteStatus.stored,
    );
    final probe = await service.probeBook('book.epub', identity);

    expect(probe.status, BookCacheProbeStatus.validPayload);
    final cached = await service.loadCachedBook('book.epub');
    expect(cached?.title, 'Book');
  });

  test('whole display cache round-trips paragraph and seam metadata', () async {
    final service = BookCacheService.testing(cacheDirectory: tempDir);
    const chunk = BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'First. Second.',
      logicalParagraphId: 'chapter.xhtml#paragraph-0',
      logicalParagraphEndOffset: 14,
      textBoundaries: [
        DisplayTextBoundary(offset: 7, kind: ReaderTextBoundaryKind.sentence),
      ],
    );

    await service.cacheDisplayChunks(
      key: 'display-v14-roundtrip',
      displayChunks: const [chunk],
      displayToOriginal: const [
        [0],
      ],
      originalToDisplay: const {0: 0},
    );
    final cached = await service.loadDisplayChunks('display-v14-roundtrip');

    expect(cached, isNotNull);
    expect(
      cached!.displayChunks.single.logicalParagraphId,
      chunk.logicalParagraphId,
    );
    expect(
      cached.displayChunks.single.textBoundaries!.single.kind,
      ReaderTextBoundaryKind.sentence,
    );
  });

  test(
    'missing payload is not considered valid and clears preparation metadata',
    () async {
      final service = BookCacheService.testing(cacheDirectory: tempDir);
      const identity = BookCacheFileIdentity(
        bookId: 'book.epub',
        fileSizeBytes: 50,
        modifiedMs: 100,
      );
      await store(service, identity);
      await File(p.join(tempDir.path, 'book.epub.json.gz')).delete();

      expect(
        (await service.probeBook('book.epub', identity)).status,
        BookCacheProbeStatus.missingPayload,
      );
      expect(
        (await service.probeBook('book.epub', identity)).status,
        BookCacheProbeStatus.noCache,
      );
    },
  );

  test(
    'oversized outcome is durable and file identity invalidates it',
    () async {
      final service = BookCacheService.testing(
        cacheDirectory: tempDir,
        maxCacheSizeBytes: 1,
      );
      const first = BookCacheFileIdentity(
        bookId: 'book.epub',
        fileSizeBytes: 50,
        modifiedMs: 100,
      );
      const changed = BookCacheFileIdentity(
        bookId: 'book.epub',
        fileSizeBytes: 51,
        modifiedMs: 101,
      );

      expect(
        (await store(service, first)).status,
        BookCacheWriteStatus.tooLarge,
      );
      expect(
        (await service.probeBook('book.epub', first)).status,
        BookCacheProbeStatus.knownTooLarge,
      );
      expect(
        (await service.probeBook('book.epub', changed)).status,
        BookCacheProbeStatus.stale,
      );
    },
  );

  test(
    'cache-limit and version changes invalidate preparation metadata',
    () async {
      final limited = BookCacheService.testing(
        cacheDirectory: tempDir,
        maxCacheSizeBytes: 1,
      );
      const identity = BookCacheFileIdentity(
        bookId: 'book.epub',
        fileSizeBytes: 50,
        modifiedMs: 100,
      );
      await store(limited, identity);

      final changedLimit = BookCacheService.testing(
        cacheDirectory: tempDir,
        maxCacheSizeBytes: 2,
      );
      expect(
        (await changedLimit.probeBook('book.epub', identity)).status,
        BookCacheProbeStatus.stale,
      );

      await store(limited, identity);
      final manifest = File(p.join(tempDir.path, 'preparation_manifest.json'));
      final data =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      (data['book.epub'] as Map<String, dynamic>)['formatVersion'] = 4;
      await manifest.writeAsString(jsonEncode(data));
      final incompatible = BookCacheService.testing(
        cacheDirectory: tempDir,
        maxCacheSizeBytes: 1,
      );
      expect(
        (await incompatible.probeBook('book.epub', identity)).status,
        BookCacheProbeStatus.unsupportedVersion,
      );
    },
  );

  test(
    'deleting or clearing cache also clears oversized preparation metadata',
    () async {
      final service = BookCacheService.testing(
        cacheDirectory: tempDir,
        maxCacheSizeBytes: 1,
      );
      const identity = BookCacheFileIdentity(
        bookId: 'book.epub',
        fileSizeBytes: 50,
        modifiedMs: 100,
      );
      await store(service, identity);
      await service.deleteCachedBook('book.epub');
      expect(
        (await service.probeBook('book.epub', identity)).status,
        BookCacheProbeStatus.noCache,
      );

      await store(service, identity);
      await service.clearAll();
      expect(
        (await service.probeBook('book.epub', identity)).status,
        BookCacheProbeStatus.noCache,
      );
    },
  );

  test('corrupt preparation metadata is handled as an invalid cache', () async {
    await File(
      p.join(tempDir.path, 'preparation_manifest.json'),
    ).writeAsString('{not json');
    final service = BookCacheService.testing(cacheDirectory: tempDir);
    const identity = BookCacheFileIdentity(
      bookId: 'book.epub',
      fileSizeBytes: 50,
      modifiedMs: 100,
    );

    expect(
      (await service.probeBook('book.epub', identity)).status,
      BookCacheProbeStatus.corruptMetadata,
    );
  });

  group('BookCacheService.displayChunkKey', () {
    test('differs when the resolved font metric identity differs', () {
      String key(String metric) => BookCacheService.displayChunkKey(
        bookId: 'book.epub',
        fontSize: 18,
        fontFamily: 'lexend',
        fontWeight: 'regular',
        fontMetricIdentity: metric,
        density: 1,
        lineHeight: 1.3,
        paragraphSpacing: 1,
        sideMargin: 24,
        screenW: 412,
        screenH: 915,
        enableCardDepth: false,
        textScaleFactor: 1,
        safeAreaTop: 44,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      );

      expect(key('reader_typography_v1'), isNot(key('reader_typography_v0')));
      expect(BookCacheService.displayLayoutVersion, 'v14');
    });

    test('differs when only paragraphSpacing differs', () {
      final base = BookCacheService.displayChunkKey(
        bookId: 'book.epub',
        fontSize: 18,
        fontFamily: 'serif',
        fontWeight: 'regular',
        density: 1,
        lineHeight: 1.4,
        paragraphSpacing: 1,
        sideMargin: 24,
        screenW: 412,
        screenH: 915,
        enableCardDepth: false,
        textScaleFactor: 1,
        safeAreaTop: 44,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      );
      final changed = BookCacheService.displayChunkKey(
        bookId: 'book.epub',
        fontSize: 18,
        fontFamily: 'serif',
        fontWeight: 'regular',
        density: 1,
        lineHeight: 1.4,
        paragraphSpacing: 2,
        sideMargin: 24,
        screenW: 412,
        screenH: 915,
        enableCardDepth: false,
        textScaleFactor: 1,
        safeAreaTop: 44,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      );

      expect(changed, isNot(base));
    });

    test('differs when only sideMargin differs', () {
      final base = BookCacheService.displayChunkKey(
        bookId: 'book.epub',
        fontSize: 18,
        fontFamily: 'serif',
        fontWeight: 'regular',
        density: 1,
        lineHeight: 1.4,
        paragraphSpacing: 1,
        sideMargin: 24,
        screenW: 412,
        screenH: 915,
        enableCardDepth: false,
        textScaleFactor: 1,
        safeAreaTop: 44,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      );
      final changed = BookCacheService.displayChunkKey(
        bookId: 'book.epub',
        fontSize: 18,
        fontFamily: 'serif',
        fontWeight: 'regular',
        density: 1,
        lineHeight: 1.4,
        paragraphSpacing: 1,
        sideMargin: 56,
        screenW: 412,
        screenH: 915,
        enableCardDepth: false,
        textScaleFactor: 1,
        safeAreaTop: 44,
        safeAreaBottom: 34,
        safeAreaLeft: 0,
        safeAreaRight: 0,
      );

      expect(changed, isNot(base));
    });
  });
}
