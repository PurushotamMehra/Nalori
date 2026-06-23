import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late ParsedSectionCacheService cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'nalori_parsed_section_cache_',
    );
    cache = ParsedSectionCacheService(rootDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes and loads independent parsed sections', () async {
    final first = _section(0, 'text/one.xhtml', 'First section text.');
    final second = _section(1, 'text/two.xhtml', 'Second section text.');

    await cache.writeSection(first);
    await cache.writeSection(second);

    final loadedFirst = await cache.loadSection(first.identity);
    final loadedSecond = await cache.loadSection(second.identity);
    final manifest = await cache.loadManifest(first.identity.bookId);

    expect(loadedFirst, isNotNull);
    expect(loadedSecond, isNotNull);
    expect(loadedFirst!.chunks.single.text, 'First section text.');
    expect(loadedSecond!.chunks.single.text, 'Second section text.');
    expect(manifest!.records, hasLength(2));
    expect(manifest.records.map((record) => record.spineIndex), [0, 1]);
  });

  test('source checksum change misses only the changed section', () async {
    final original = _section(0, 'text/one.xhtml', 'Original text.');
    final changedIdentity = LazySectionIdentity(
      bookId: original.identity.bookId,
      spineIndex: original.identity.spineIndex,
      href: original.identity.href,
      fullPath: original.identity.fullPath,
      sourceChecksum: 'changed',
    );

    await cache.writeSection(original);

    expect(await cache.loadSection(original.identity), isNotNull);
    expect(await cache.loadSection(changedIdentity), isNull);
  });

  test('repeated manifest loads preserve cached manifest state', () async {
    final section = _section(0, 'text/one.xhtml', 'Cached text.');
    await cache.writeSection(section);

    final first = await cache.loadManifest(section.identity.bookId);
    final second = await cache.loadManifest(section.identity.bookId);

    expect(first?.records, hasLength(1));
    expect(second?.records, hasLength(1));
  });

  test('external manifest changes invalidate cached parsed manifest', () async {
    final section = _section(0, 'text/one.xhtml', 'Cached text.');
    await cache.writeSection(section);
    expect(await cache.loadManifest(section.identity.bookId), isNotNull);

    final manifestFile = File(
      p.join(tempDir.path, section.identity.bookId, 'manifest.json'),
    );
    final json =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    json['version'] = -1;
    await manifestFile.writeAsString(jsonEncode(json), flush: true);

    expect(await cache.loadManifest(section.identity.bookId), isNull);
  });

  test('missing payload is removed from the lightweight manifest', () async {
    final section = _section(0, 'text/one.xhtml', 'Cached text.');
    await cache.writeSection(section);

    final manifest = await cache.loadManifest(section.identity.bookId);
    final record = manifest!.records.single;
    await File(
      p.join(tempDir.path, section.identity.bookId, record.fileName),
    ).delete();

    expect(await cache.loadSection(section.identity), isNull);
    final repaired = await cache.loadManifest(section.identity.bookId);
    expect(repaired!.records, isEmpty);
  });

  test('hydration manifest resumes from completed section records', () async {
    final first = _section(0, 'text/one.xhtml', 'First section text.');
    await cache.writeSection(first);

    final hydration = await cache.ensureHydrationManifest(
      bookId: first.identity.bookId,
      sourceChecksum: 'book-checksum',
      parserVersion: lazyParsedSectionParserVersion,
      readableSpineIndexes: [0, 1, 2],
      skippedSpineIndexes: [3],
    );

    expect(hydration.completedSpineIndexes, [0]);
    expect(hydration.pendingSpineIndexes, [1, 2]);
    expect(hydration.skippedSpineIndexes, [3]);
    expect(hydration.status, 'inProgress');
  });

  test(
    'hydration manifest is completed when pending sections are written',
    () async {
      final first = _section(0, 'text/one.xhtml', 'First section text.');
      final second = _section(1, 'text/two.xhtml', 'Second section text.');

      await cache.ensureHydrationManifest(
        bookId: first.identity.bookId,
        sourceChecksum: 'book-checksum',
        parserVersion: lazyParsedSectionParserVersion,
        readableSpineIndexes: [0, 1],
        skippedSpineIndexes: const [],
      );
      await cache.writeSection(first);
      await cache.writeSection(second);

      final manifest = await cache.loadManifest(first.identity.bookId);
      expect(manifest!.hydration?.completedSpineIndexes, [0, 1]);
      expect(manifest.hydration?.pendingSpineIndexes, isEmpty);
      expect(manifest.hydration?.status, 'complete');
    },
  );
}

ParsedSection _section(int spineIndex, String href, String text) {
  final identity = LazySectionIdentity(
    bookId: 'book.epub',
    spineIndex: spineIndex,
    href: href,
    fullPath: 'OEBPS/$href',
    sourceChecksum: fnv1aHex(Uint8List.fromList(text.codeUnits)),
  );
  return ParsedSection(
    identity: identity,
    chunks: [
      BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: text,
        sourceFile: href,
      ),
    ],
    anchorMap: {'ch$spineIndex': 0},
    chapters: [],
    wordCount: text.split(RegExp(r'\s+')).length,
    textCharCount: text.length,
    resourceHrefs: const [],
    parserVersion: lazyParsedSectionParserVersion,
  );
}
