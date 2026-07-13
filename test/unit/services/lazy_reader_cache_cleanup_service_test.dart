import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/book_cache_service.dart';
import 'package:nalori/services/lazy_epub_index_service.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_reader_cache_cleanup_service.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/segmented_display_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('coordinated deletion removes derivatives but not user data', () async {
    final temp = await Directory.systemTemp.createTemp(
      'nalori_reader_cleanup_',
    );
    addTearDown(() => temp.delete(recursive: true));
    const bookId = 'book.epub';
    final parsedRoot = Directory(p.join(temp.path, 'parsed'));
    final parsed = ParsedSectionCacheService(rootDirectory: parsedRoot);
    final section = _section(bookId);
    await parsed.writeSection(section);

    final indexRoot = Directory(p.join(temp.path, 'indexes'));
    await indexRoot.create(recursive: true);
    final indexFile = File(
      p.join(indexRoot.path, '${sha256.convert(utf8.encode(bookId))}.json'),
    );
    await indexFile.writeAsString('{}');

    final segmentedRoot = Directory(p.join(temp.path, 'segments'));
    final segmentDir = Directory(p.join(segmentedRoot.path, 'layout'));
    await segmentDir.create(recursive: true);
    await File(
      p.join(segmentDir.path, 'manifest.json'),
    ).writeAsString(jsonEncode(_segmentedManifest(bookId)));

    final userData = Directory(p.join(temp.path, 'user_data'));
    await userData.create();
    final annotations = File(p.join(userData.path, 'annotations.json'));
    final stableLocations = File(p.join(userData.path, 'stable.json'));
    await annotations.writeAsString('keep');
    await stableLocations.writeAsString('keep');

    final cleanup = LazyReaderCacheCleanupService(
      bookCache: BookCacheService.testing(
        cacheDirectory: Directory(p.join(temp.path, 'whole_cache')),
      ),
      parsedSectionCache: parsed,
      indexStore: LazyEpubIndexStore(directory: indexRoot),
      workCoordinator: SharedLazySectionWorkCoordinator(),
      segmentedDisplayCacheFactory: () async =>
          SegmentedDisplayCacheService(rootDirectory: segmentedRoot),
    );

    await cleanup.deleteDerivativesForBook(bookId);

    expect(await parsed.loadManifest(bookId), isNull);
    expect(await indexFile.exists(), isFalse);
    expect(await segmentDir.exists(), isFalse);
    expect(await annotations.readAsString(), 'keep');
    expect(await stableLocations.readAsString(), 'keep');
  });

  test(
    'structural-index delete prevents stale write and permits reopen',
    () async {
      final temp = await Directory.systemTemp.createTemp('nalori_index_race_');
      addTearDown(() => temp.delete(recursive: true));
      final store = LazyEpubIndexStore(directory: temp);
      final index = _index('book.epub');

      final staleWrite = store.write(index);
      final deletion = store.deleteForBook(index.bookId);
      await Future.wait([staleWrite, deletion]);

      expect(await store.load(index.bookId), isNull);
      await store.write(index);
      expect(await store.load(index.bookId), isNotNull);
    },
  );

  test('whole derivative reset invalidates stale parsed writes', () async {
    final temp = await Directory.systemTemp.createTemp('nalori_cache_reset_');
    addTearDown(() => temp.delete(recursive: true));
    final parsed = ParsedSectionCacheService(
      rootDirectory: Directory(p.join(temp.path, 'parsed')),
    );
    final section = _section('book.epub');
    await parsed.writeSection(section);
    final staleGeneration = parsed.generationForBook(section.identity.bookId);
    final userData = File(p.join(temp.path, 'annotations.json'));
    await userData.writeAsString('keep');
    final cleanup = LazyReaderCacheCleanupService(
      bookCache: BookCacheService.testing(
        cacheDirectory: Directory(p.join(temp.path, 'whole')),
      ),
      parsedSectionCache: parsed,
      indexStore: LazyEpubIndexStore(
        directory: Directory(p.join(temp.path, 'indexes')),
      ),
      workCoordinator: SharedLazySectionWorkCoordinator(),
      segmentedDisplayCacheFactory: () async => SegmentedDisplayCacheService(
        rootDirectory: Directory(p.join(temp.path, 'segments')),
      ),
    );

    await cleanup.clearAllDerivatives();

    await expectLater(
      parsed.writeSection(section, expectedGeneration: staleGeneration),
      throwsA(isA<ParsedSectionCacheWriteInvalidated>()),
    );
    expect(await parsed.loadManifest(section.identity.bookId), isNull);
    expect(await userData.readAsString(), 'keep');
  });
}

ParsedSection _section(String bookId) {
  final identity = LazySectionIdentity(
    bookId: bookId,
    publicationFingerprint: 'publication',
    spineIndex: 0,
    href: 'text/one.xhtml',
    normalizedHref: 'text/one.xhtml',
    fullPath: 'OEBPS/text/one.xhtml',
    sourceChecksum: fnv1aHex(Uint8List.fromList('text'.codeUnits)),
    parserVersion: lazyParsedSectionParserVersion,
    dependencySignature: 'dependencies',
    dependencySchemaVersion: lazyParsedSectionDependencySchemaVersion,
  );
  return ParsedSection(
    identity: identity,
    chunks: const [BookChunk(index: 0, type: BookChunkType.text, text: 'text')],
    anchorMap: const {},
    chapters: const [],
    wordCount: 1,
    textCharCount: 4,
    resourceHrefs: const [],
    parserVersion: lazyParsedSectionParserVersion,
  );
}

Map<String, Object?> _segmentedManifest(String bookId) => {
  'version': SegmentedDisplayCacheService.segmentedDisplayCacheFormatVersion,
  'bookId': bookId,
  'cacheKey': 'layout',
  'parsedContentVersion': 1,
  'parserVersion': 1,
  'displayLayoutVersion': 'test',
  'settingsSignature': 'settings',
  'viewportSignature': 'viewport',
  'sourceChunkCount': 1,
  'complete': false,
  'createdAtMs': 1,
  'updatedAtMs': 1,
  'segments': <Object>[],
};

LazyEpubIndex _index(String bookId) {
  return LazyEpubIndex(
    filePath: '/tmp/$bookId',
    bookId: bookId,
    title: 'Book',
    author: 'Author',
    authorList: const ['Author'],
    contentDirectoryPath: 'OEBPS',
    manifest: const {},
    spine: const [],
    chapters: const [],
    coverHref: null,
    schemaVersion: LazyEpubIndexService.schemaVersion,
    publicationFingerprint: 'publication',
    fileSizeBytes: 1,
    fileModifiedMs: 1,
    normalizedHrefToManifestHref: const {},
    normalizedHrefToSpineIndex: const {},
    totalReadableWeight: 0,
    warnings: const [],
  );
}
