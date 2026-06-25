import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/book_cache_service.dart';
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
    String cacheKey = 'book_dc_v11_settings_viewport',
    int parsedVersion = BookCacheService.parsedBookCacheFormatVersion,
    String layout = BookCacheService.displayLayoutVersion,
    String settings = 'settings',
    String viewport = 'viewport',
  }) {
    return DisplayGenerationSignature(
      bookId: 'book.epub',
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
}
