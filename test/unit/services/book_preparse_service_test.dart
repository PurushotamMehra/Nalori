import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/bookmark.dart';
import 'package:nalori/services/book_preparse_service.dart';
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
      hasCachedBook: (_, _) async => false,
      loadCachedBook: (_) async => null,
      cacheParsedBook:
          ({
            required bookId,
            required title,
            required chunks,
            required anchorMap,
            required chapters,
            required searchIndex,
          }) async {},
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
        hasCachedBook: (_, _) async => false,
        loadCachedBook: (_) async => null,
        cacheParsedBook:
            ({
              required bookId,
              required title,
              required chunks,
              required anchorMap,
              required chapters,
              required searchIndex,
            }) async {},
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
}
