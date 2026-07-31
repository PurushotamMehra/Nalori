import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/book_cache_service.dart';
import 'package:nalori/services/chapter_card_layout_service.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/segmented_display_cache_service.dart';

void main() {
  late Directory tempDir;
  late SegmentedDisplayCacheService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_segments_test_');
    service = SegmentedDisplayCacheService(rootDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DisplayGenerationSignature signature({
    String bookId = 'book.epub',
    String cacheKey = 'book_dc_v11_settings_viewport',
    int parsedVersion = BookCacheService.parsedBookCacheFormatVersion,
    String layout = BookCacheService.displayLayoutVersion,
    String settings = 'settings',
    String viewport = 'viewport',
  }) {
    return DisplayGenerationSignature(
      bookId: bookId,
      parsedContentVersion: parsedVersion,
      layoutSignature: layout,
      settingsSignature: settings,
      viewportSignature: viewport,
      cacheKey: cacheKey,
    );
  }

  SegmentedDisplayCacheKey cacheKey({
    DisplayGenerationSignature? sig,
    int sourceChunkCount = 1000,
  }) {
    final actualSignature = sig ?? signature();
    return SegmentedDisplayCacheKey(
      bookId: actualSignature.bookId,
      cacheKey: actualSignature.cacheKey,
      signature: actualSignature,
      sourceChunkCount: sourceChunkCount,
    );
  }

  BookChunk chunk(int index, String text) {
    return BookChunk(index: index, type: BookChunkType.text, text: text);
  }

  DisplayRangeResult result({
    required int start,
    required int end,
    required int generationId,
    List<BookChunk>? displayChunks,
    List<List<int>>? displayToOriginal,
    Map<int, int>? originalToDisplay,
  }) {
    final chunks =
        displayChunks ??
        [for (var i = start; i < end; i += 2) chunk(i, 'chunk $i')];
    return DisplayRangeResult(
      request: DisplayRangeRequest(
        direction: DisplayRangeDirection.forward,
        sourceRange: SourceChunkRange(start, end),
        generationId: generationId,
        reason: 'test',
      ),
      displayChunks: chunks,
      displayToOriginal:
          displayToOriginal ??
          [
            for (var i = start; i < end; i += 2) [i, if (i + 1 < end) i + 1],
          ],
      originalToDisplay:
          originalToDisplay ??
          {for (var i = start; i < end; i++) i: (i - start) ~/ 2},
      inspectedSourceChunks: end - start,
      elapsedMilliseconds: 1,
    );
  }

  Future<File> segmentFile(DisplaySegmentRecord record) async {
    await for (final entity in tempDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith(record.fileName)) {
        return entity;
      }
    }
    fail('segment file not found: ${record.fileName}');
  }

  Future<File> manifestFile() async {
    await for (final entity in tempDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('manifest.json')) {
        return entity;
      }
    }
    fail('manifest file not found');
  }

  Future<void> rewriteManifest(
    Map<String, dynamic> Function(Map<String, dynamic> manifest) update,
  ) async {
    final file = await manifestFile();
    final manifest =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    await file.writeAsString(jsonEncode(update(manifest)), flush: true);
  }

  test(
    'chapter totals persist and invalidate by exact layout identity',
    () async {
      ChapterCardLayoutKey layoutKey(String settings) => ChapterCardLayoutKey(
        bookId: 'book.epub',
        publicationFingerprint: 'publication',
        chapterIdentity: 'chapter-1',
        parserSchema: 2,
        displaySchema: 'display',
        settingsSignature: settings,
        viewportSignature: '400x800',
        cardMode: true,
      );
      StableBookLocation location(int offset) => StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 1,
        href: 'chapter.xhtml',
        sourceChecksum: 'checksum',
        localChunkIndex: 0,
        textOffset: offset,
      );
      final firstKey = layoutKey('font-16');
      final layout = ChapterCardLayout(
        key: firstKey,
        pages: [
          ChapterCardSourceRange(start: location(0), end: location(100)),
          ChapterCardSourceRange(start: location(100), end: location(200)),
        ],
        completedAtMs: 1,
      );

      await service.writeChapterCardLayoutRecord(
        layout: layout,
        shouldWrite: () => true,
      );

      expect(await service.loadChapterCardLayoutRecord(firstKey), isNotNull);
      expect(
        await service.loadChapterCardLayoutRecord(layoutKey('font-18')),
        isNull,
      );
      await service.deleteForBook('book.epub');
      expect(await service.loadChapterCardLayoutRecord(firstKey), isNull);
    },
  );

  test('writes first segment with lightweight manifest only', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 96, end: 192, generationId: 1),
      generationId: 1,
    );

    final manifest = await service.loadManifest(key);
    expect(manifest, isNotNull);
    expect(manifest!.segments, hasLength(1));
    expect(manifest.complete, isFalse);

    final manifestFile = File(
      tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('manifest.json'))
          .path,
    );
    final manifestText = await manifestFile.readAsString();
    expect(manifestText, isNot(contains('displayChunks')));
    expect(manifestText.length, lessThan(2000));
  });

  test('loads center segment and adjacent cached segments lazily', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    await service.writeSegment(
      key: key,
      result: result(start: 96, end: 192, generationId: 2),
      generationId: 2,
    );
    await service.writeSegment(
      key: key,
      result: result(start: 192, end: 288, generationId: 3),
      generationId: 3,
    );

    final loaded = await service.loadAroundSource(key: key, sourceIndex: 120);

    expect(loaded.center?.record.sourceRange.toString(), '[96,192)');
    expect(loaded.before?.record.sourceRange.toString(), '[0,96)');
    expect(loaded.after?.record.sourceRange.toString(), '[192,288)');
    expect(loaded.center?.displayChunks, isNotEmpty);
  });

  test(
    'loads an exact cached source range without adjacent decoding',
    () async {
      final key = cacheKey();
      await service.writeSegment(
        key: key,
        result: result(start: 96, end: 192, generationId: 1),
        generationId: 1,
      );

      final loaded = await service.loadRange(
        key: key,
        sourceRange: const SourceChunkRange(96, 192),
      );

      expect(loaded?.record.sourceRange.toString(), '[96,192)');
      expect(
        loaded
            ?.toResult(
              direction: DisplayRangeDirection.forward,
              generationId: 2,
              reason: 'cache',
            )
            .displayChunks,
        isNotEmpty,
      );
    },
  );

  test(
    'preserves separated islands and reports a source gap as miss',
    () async {
      final key = cacheKey(sourceChunkCount: 6000);
      await service.writeSegment(
        key: key,
        result: result(start: 0, end: 96, generationId: 1),
        generationId: 1,
      );
      await service.writeSegment(
        key: key,
        result: result(start: 4800, end: 4896, generationId: 2),
        generationId: 2,
      );

      final gap = await service.loadAroundSource(key: key, sourceIndex: 1000);
      final island = await service.loadAroundSource(
        key: key,
        sourceIndex: 4820,
      );

      expect(gap.center, isNull);
      expect(island.center?.record.sourceRange.toString(), '[4800,4896)');
      expect(island.before, isNull);
      expect(island.after, isNull);
    },
  );

  test('stale generation is denied before manifest publication', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
      shouldWrite: () => false,
    );

    expect(await service.loadManifest(key), isNull);
    final files = tempDir.listSync(recursive: true).whereType<File>().toList();
    expect(files.where((file) => file.path.endsWith('.json.gz')), isEmpty);
  });

  test('incompatible layout signature is skipped', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );

    final changed = cacheKey(
      sig: signature(cacheKey: key.cacheKey, settings: 'different_settings'),
    );

    expect(await service.loadManifest(changed), isNull);
  });

  test('repeated compatible loads preserve validated manifest state', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );

    final first = await service.loadManifest(key);
    expect(first?.segments, hasLength(1));

    final second = await service.loadManifest(key);
    expect(second?.segments, hasLength(1));
  });

  test('cached manifest is not reused for incompatible layout keys', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    expect(await service.loadManifest(key), isNotNull);

    final changed = cacheKey(
      sig: signature(cacheKey: key.cacheKey, viewport: 'different_viewport'),
    );

    expect(await service.loadManifest(changed), isNull);
  });

  test('corrupt segment is removed without deleting valid neighbors', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    await service.writeSegment(
      key: key,
      result: result(start: 96, end: 192, generationId: 2),
      generationId: 2,
    );
    final manifest = await service.loadManifest(key);
    final corruptRecord = manifest!.segments.first;
    final corruptFile = await segmentFile(corruptRecord);
    await corruptFile.writeAsBytes(utf8.encode('not gzip'), flush: true);

    final loaded = await service.loadAroundSource(key: key, sourceIndex: 10);
    final repairedManifest = await service.loadManifest(key);

    expect(loaded.center, isNull);
    expect(repairedManifest?.segments, hasLength(1));
    expect(
      repairedManifest?.segments.single.sourceRange.toString(),
      '[96,192)',
    );
  });

  test('checksum mismatch invalidates only the affected segment', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    await service.writeSegment(
      key: key,
      result: result(start: 96, end: 192, generationId: 2),
      generationId: 2,
    );
    final manifest = await service.loadManifest(key);
    final changedRecord = manifest!.segments.first;
    final changedFile = await segmentFile(changedRecord);
    final bytes = await changedFile.readAsBytes();
    await changedFile.writeAsBytes([...bytes, 0], flush: true);

    final loaded = await service.loadAroundSource(key: key, sourceIndex: 10);
    final repairedManifest = await service.loadManifest(key);

    expect(loaded.center, isNull);
    expect(repairedManifest?.segments, hasLength(1));
    expect(
      repairedManifest?.segments.single.sourceRange.toString(),
      '[96,192)',
    );
  });

  test('corrupt manifest is rejected without decoding segments', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    final file = await manifestFile();
    await file.writeAsString('{not valid json', flush: true);

    expect(await service.loadManifest(key), isNull);
    final files = tempDir.listSync(recursive: true).whereType<File>().toList();
    expect(files.where((file) => file.path.endsWith('.json.gz')), hasLength(1));
  });

  test('old segmented cache version is rejected', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    await rewriteManifest((manifest) {
      manifest['version'] = 0;
      return manifest;
    });

    expect(await service.loadManifest(key), isNull);
  });

  test('duplicate and overlapping manifest records are normalized', () async {
    final key = cacheKey();
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    await service.writeSegment(
      key: key,
      result: result(start: 96, end: 192, generationId: 2),
      generationId: 2,
    );
    final original = await service.loadManifest(key);
    final duplicate = original!.segments.first.toJson();
    final overlapping = original.segments.last.toJson()
      ..['sourceStart'] = 48
      ..['sourceEndExclusive'] = 144;
    await rewriteManifest((manifest) {
      manifest['segments'] = [
        ...manifest['segments'] as List<dynamic>,
        duplicate,
        overlapping,
      ];
      return manifest;
    });

    final normalized = await service.loadManifest(key);

    expect(normalized?.segments, hasLength(2));
    expect(
      normalized?.segments.map((segment) => segment.sourceRange.toString()),
      ['[0,96)', '[96,192)'],
    );
  });

  test('stale temporary files are removed during initialization', () async {
    final tmp = File('${tempDir.path}/orphan.tmp');
    await tmp.writeAsString('partial', flush: true);

    await service.ensureInitialized();

    expect(await tmp.exists(), isFalse);
  });

  test('complete contiguous source coverage is detected', () async {
    final key = cacheKey(sourceChunkCount: 192);
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    await service.writeSegment(
      key: key,
      result: result(start: 96, end: 192, generationId: 2),
      generationId: 2,
    );

    final manifest = await service.loadManifest(key);

    expect(manifest?.complete, isTrue);
  });

  test('default policy is configurable and defaults to 48 MiB', () {
    expect(service.configuredByteBudget, 48 * 1024 * 1024);
    final configured = SegmentedDisplayCacheService(
      rootDirectory: tempDir,
      policy: const SegmentedDisplayCachePolicy(byteBudget: 1234),
    );
    expect(configured.configuredByteBudget, 1234);
  });

  test('actual-byte LRU evicts the coldest display range', () async {
    var now = 10;
    service = SegmentedDisplayCacheService(
      rootDirectory: tempDir,
      clock: () => now,
    );
    final key = cacheKey(sourceChunkCount: 288);
    for (final start in [0, 96, 192]) {
      now += 10;
      await service.writeSegment(
        key: key,
        result: result(start: start, end: start + 96, generationId: now),
        generationId: now,
      );
    }
    now = 100;
    expect(
      await service.loadRange(
        key: key,
        sourceRange: const SourceChunkRange(0, 96),
      ),
      isNotNull,
    );
    final before = await service.payloadBytesOnDisk();
    final constrained = SegmentedDisplayCacheService(
      rootDirectory: tempDir,
      policy: SegmentedDisplayCachePolicy(byteBudget: before - 1),
      clock: () => now,
    );

    await constrained.enforceBudget();

    final retained = await constrained.loadManifest(key);
    expect(
      retained?.segments.map((segment) => segment.sourceRange.toString()),
      containsAll(<String>['[0,96)', '[192,288)']),
    );
    expect(
      retained?.segments.map((segment) => segment.sourceRange.toString()),
      isNot(contains('[96,192)')),
    );
    expect(
      await constrained.payloadBytesOnDisk(),
      lessThanOrEqualTo(before - 1),
    );
  });

  test('active visible range is protected under byte pressure', () async {
    final key = cacheKey(sourceChunkCount: 192);
    await service.writeSegment(
      key: key,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    await service.writeSegment(
      key: key,
      result: result(start: 96, end: 192, generationId: 2),
      generationId: 2,
    );
    final before = await service.payloadBytesOnDisk();
    final constrained = SegmentedDisplayCacheService(
      rootDirectory: tempDir,
      policy: SegmentedDisplayCachePolicy(byteBudget: before - 1),
    );
    constrained.protectActiveRanges(
      bookId: key.bookId,
      cacheKey: key.cacheKey,
      layoutIdentity: constrained.layoutIdentityForKey(key),
      ranges: const [SourceChunkRange(0, 96)],
    );

    await constrained.enforceBudget();

    final retained = await constrained.loadManifest(key);
    expect(
      retained?.segments.map((segment) => segment.sourceRange.toString()),
      contains('[0,96)'),
    );
    expect(
      retained?.segments.map((segment) => segment.sourceRange.toString()),
      isNot(contains('[96,192)')),
    );
  });

  test('obsolete layouts evict before current valid layout ranges', () async {
    final obsolete = cacheKey(
      sig: signature(cacheKey: 'obsolete-key', settings: 'old-settings'),
      sourceChunkCount: 96,
    );
    final current = cacheKey(
      sig: signature(cacheKey: 'current-key', settings: 'current-settings'),
      sourceChunkCount: 96,
    );
    await service.writeSegment(
      key: obsolete,
      result: result(start: 0, end: 96, generationId: 10),
      generationId: 10,
    );
    await service.writeSegment(
      key: current,
      result: result(start: 0, end: 96, generationId: 1),
      generationId: 1,
    );
    final before = await service.payloadBytesOnDisk();
    final constrained = SegmentedDisplayCacheService(
      rootDirectory: tempDir,
      policy: SegmentedDisplayCachePolicy(byteBudget: before - 1),
    );
    constrained.protectActiveRanges(
      bookId: current.bookId,
      cacheKey: current.cacheKey,
      layoutIdentity: constrained.layoutIdentityForKey(current),
      ranges: const [SourceChunkRange(0, 96)],
    );

    await constrained.enforceBudget();

    expect(await constrained.loadManifest(obsolete), isNull);
    expect(await constrained.loadManifest(current), isNotNull);
  });

  test(
    'low storage reduces retention without touching external data',
    () async {
      final displayRoot = Directory('${tempDir.path}/display');
      final sentinel = File('${tempDir.path}/parsed-source-and-user-data');
      await sentinel.writeAsString('preserve', flush: true);
      var pressure = DisplayCacheStoragePressure.normal;
      final roomy = SegmentedDisplayCacheService(rootDirectory: displayRoot);
      final key = cacheKey(sourceChunkCount: 288);
      for (final start in [0, 96, 192]) {
        await roomy.writeSegment(
          key: key,
          result: result(
            start: start,
            end: start + 96,
            generationId: start + 1,
          ),
          generationId: start + 1,
        );
      }
      final normalBytes = await roomy.payloadBytesOnDisk();
      final adaptive = SegmentedDisplayCacheService(
        rootDirectory: displayRoot,
        policy: SegmentedDisplayCachePolicy(byteBudget: normalBytes),
        storagePressureProvider: () => pressure,
      );
      expect(adaptive.effectiveByteBudget, normalBytes);

      pressure = DisplayCacheStoragePressure.low;
      await adaptive.enforceBudget();

      expect(adaptive.effectiveByteBudget, normalBytes ~/ 2);
      expect(
        await adaptive.payloadBytesOnDisk(),
        lessThanOrEqualTo(adaptive.effectiveByteBudget),
      );
      expect(await sentinel.readAsString(), 'preserve');
    },
  );
}
