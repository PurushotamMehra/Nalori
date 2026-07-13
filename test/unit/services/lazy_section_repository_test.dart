import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/parsed_section_retention_policy.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'nalori_lazy_section_repo_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loads requested sections and evicts beyond retention limit', () async {
    final file = File(p.join(tempDir.path, 'repo.epub'));
    await file.writeAsBytes(_buildRepositoryFixture(), flush: true);
    final cacheRoot = Directory(p.join(tempDir.path, 'cache'));
    final repository = LazySectionRepository(
      cache: ParsedSectionCacheService(rootDirectory: cacheRoot),
      retainedSectionLimit: 2,
    );
    addTearDown(repository.close);

    await repository.open(file);
    final first = await repository.loadSection(0);
    final second = await repository.loadSection(1);
    final third = await repository.loadSection(2);

    expect(_sectionText(first.chunks), contains('Section one text.'));
    expect(_sectionText(second.chunks), contains('Section two text.'));
    expect(_sectionText(third.chunks), contains('Section three text.'));
    expect(repository.retainedSectionCount, 2);
    expect(repository.retainedSpineIndices, [1, 2]);
  });

  test('duplicate section requests join one in-flight load', () async {
    final file = File(p.join(tempDir.path, 'repo.epub'));
    await file.writeAsBytes(_buildRepositoryFixture(), flush: true);
    final repository = LazySectionRepository(
      cache: ParsedSectionCacheService(
        rootDirectory: Directory(p.join(tempDir.path, 'join_cache')),
      ),
    );
    addTearDown(repository.close);

    await repository.open(file);
    final results = await Future.wait([
      repository.loadSectionWithPriority(
        1,
        priority: LazySectionWorkPriority.parsedHydration,
      ),
      repository.loadSectionWithPriority(
        1,
        priority: LazySectionWorkPriority.explicitNavigation,
      ),
    ]);

    expect(identical(results[0], results[1]), isTrue);
    expect(repository.retainedSpineIndices, [1]);
  });

  test(
    'two sessions join one parser invocation for the same section',
    () async {
      final file = File(p.join(tempDir.path, 'repo.epub'));
      await file.writeAsBytes(_buildRepositoryFixture(), flush: true);
      final cacheRoot = Directory(p.join(tempDir.path, 'shared_cache'));
      final coordinator = SharedLazySectionWorkCoordinator();
      final parserStarted = Completer<void>();
      final parserGate = Completer<void>();
      var parserInvocations = 0;

      Future<ParsedSection> parser(LazySectionParseRequest request) async {
        parserInvocations++;
        if (!parserStarted.isCompleted) parserStarted.complete();
        await parserGate.future;
        return ParsedSection(
          identity: request.identity,
          chunks: const [
            BookChunk(index: 0, type: BookChunkType.text, text: 'shared'),
          ],
          anchorMap: const {},
          chapters: const [],
          wordCount: 1,
          textCharCount: 6,
          resourceHrefs: const [],
          parserVersion: request.identity.parserVersion,
        );
      }

      final first = LazySectionRepository(
        cache: ParsedSectionCacheService(rootDirectory: cacheRoot),
        workCoordinator: coordinator,
        parser: parser,
      );
      final second = LazySectionRepository(
        cache: ParsedSectionCacheService(rootDirectory: cacheRoot),
        workCoordinator: coordinator,
        parser: parser,
      );
      addTearDown(first.close);
      addTearDown(second.close);
      await Future.wait([first.open(file), second.open(file)]);

      final firstLoad = first.loadSection(1);
      await parserStarted.future;
      final secondLoad = second.loadSection(1);
      parserGate.complete();
      final results = await Future.wait([firstLoad, secondLoad]);

      expect(parserInvocations, 1);
      expect(results[0], same(results[1]));
    },
  );

  test('pinned sections are not evicted by retention pressure', () async {
    final file = File(p.join(tempDir.path, 'repo.epub'));
    await file.writeAsBytes(_buildRepositoryFixture(), flush: true);
    final repository = LazySectionRepository(
      cache: ParsedSectionCacheService(
        rootDirectory: Directory(p.join(tempDir.path, 'pin_cache')),
      ),
      retainedSectionLimit: 1,
    );
    addTearDown(repository.close);

    await repository.open(file);
    repository.pinSections([0]);
    await repository.loadSection(0);
    await repository.loadSection(1);
    await repository.loadSection(2);

    expect(repository.retainedSpineIndices, [0]);
  });

  test('reopens from parsed-section cache without reparsing payload', () async {
    final file = File(p.join(tempDir.path, 'repo.epub'));
    await file.writeAsBytes(_buildRepositoryFixture(), flush: true);
    final cacheRoot = Directory(p.join(tempDir.path, 'cache'));

    final firstRepository = LazySectionRepository(
      cache: ParsedSectionCacheService(rootDirectory: cacheRoot),
    );
    await firstRepository.open(file);
    final parsed = await firstRepository.loadSection(1);
    await firstRepository.close();

    final secondRepository = LazySectionRepository(
      cache: ParsedSectionCacheService(rootDirectory: cacheRoot),
    );
    addTearDown(secondRepository.close);
    await secondRepository.open(file);
    final cached = await secondRepository.loadSection(1);

    expect(
      cached.chunks.map((chunk) => chunk.text),
      parsed.chunks.map((chunk) => chunk.text),
    );
  });

  test('loads only section-local image resources into parsed chunks', () async {
    final file = File(p.join(tempDir.path, 'repo.epub'));
    await file.writeAsBytes(_buildRepositoryFixture(), flush: true);
    final repository = LazySectionRepository(
      cache: ParsedSectionCacheService(
        rootDirectory: Directory(p.join(tempDir.path, 'cache')),
      ),
    );
    addTearDown(repository.close);

    await repository.open(file);
    final parsed = await repository.loadSection(1);

    final images = parsed.chunks
        .where((chunk) => chunk.type == BookChunkType.image)
        .toList();
    expect(images, hasLength(1));
    expect(images.single.imageBytes, [137, 80, 78, 71]);
    expect(parsed.resourceHrefs, contains('../images/pic.png'));
  });

  test('close stops hydration before another section is scheduled', () async {
    final file = File(p.join(tempDir.path, 'repo.epub'));
    await file.writeAsBytes(_buildRepositoryFixture(), flush: true);
    final parserStarted = Completer<void>();
    final parserGate = Completer<void>();
    var parserInvocations = 0;
    final repository = LazySectionRepository(
      cache: ParsedSectionCacheService(
        rootDirectory: Directory(p.join(tempDir.path, 'hydration_close')),
      ),
      workCoordinator: SharedLazySectionWorkCoordinator(),
      parser: (request) async {
        parserInvocations++;
        if (!parserStarted.isCompleted) parserStarted.complete();
        await parserGate.future;
        return ParsedSection(
          identity: request.identity,
          chunks: const [
            BookChunk(index: 0, type: BookChunkType.text, text: 'hydrated'),
          ],
          anchorMap: const {},
          chapters: const [],
          wordCount: 1,
          textCharCount: 8,
          resourceHrefs: const [],
          parserVersion: request.identity.parserVersion,
        );
      },
    );
    await repository.open(file);

    final hydration = repository.hydrateParsedSectionsAround(
      centerSpineIndex: 0,
    );
    await parserStarted.future;
    final closing = repository.close();
    parserGate.complete();
    await Future.wait([hydration, closing]);

    expect(parserInvocations, 1);
  });

  test('low storage suspends parsed hydration before parsing', () async {
    final file = File(p.join(tempDir.path, 'repo.epub'));
    await file.writeAsBytes(_buildRepositoryFixture(), flush: true);
    var parserInvocations = 0;
    final repository = LazySectionRepository(
      cache: ParsedSectionCacheService(
        rootDirectory: Directory(p.join(tempDir.path, 'low_storage')),
        storagePressureProvider: () => ParsedCacheStoragePressure.low,
      ),
      workCoordinator: SharedLazySectionWorkCoordinator(),
      parser: (request) async {
        parserInvocations++;
        throw StateError('hydration must be suspended');
      },
    );
    addTearDown(repository.close);
    await repository.open(file);

    await repository.hydrateParsedSectionsAround(centerSpineIndex: 0);

    expect(parserInvocations, 0);
  });
}

String _sectionText(Iterable<BookChunk> chunks) {
  return chunks.map((chunk) => chunk.text ?? '').join('\n');
}

List<int> _buildRepositoryFixture() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '''<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" unique-identifier="bookid" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Repository Fixture</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">repository-fixture</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="s1" href="text/s1.xhtml" media-type="application/xhtml+xml"/>
    <item id="s2" href="text/s2.xhtml" media-type="application/xhtml+xml"/>
    <item id="s3" href="text/s3.xhtml" media-type="application/xhtml+xml"/>
    <item id="pic" href="images/pic.png" media-type="image/png"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="s1"/>
    <itemref idref="s2"/>
    <itemref idref="s3"/>
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head><meta name="dtb:uid" content="repository-fixture"/></head>
  <docTitle><text>Repository Fixture</text></docTitle>
  <navMap>
    <navPoint id="nav1" playOrder="1"><navLabel><text>One</text></navLabel><content src="text/s1.xhtml#s1"/></navPoint>
    <navPoint id="nav2" playOrder="2"><navLabel><text>Two</text></navLabel><content src="text/s2.xhtml#s2"/></navPoint>
    <navPoint id="nav3" playOrder="3"><navLabel><text>Three</text></navLabel><content src="text/s3.xhtml#s3"/></navPoint>
  </navMap>
</ncx>''',
      ),
    );

  for (var i = 1; i <= 3; i++) {
    final image = i == 2 ? '<img src="../images/pic.png" alt="pic"/>' : '';
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/text/s$i.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>$i</title></head>
  <body><h1 id="s$i">Section $i</h1><p>Section ${_word(i)} text.</p>$image</body>
</html>''',
      ),
    );
  }
  archive.addFile(ArchiveFile('OEBPS/images/pic.png', 4, [137, 80, 78, 71]));

  return ZipEncoder().encode(archive)!;
}

String _word(int value) {
  return switch (value) {
    1 => 'one',
    2 => 'two',
    3 => 'three',
    _ => '$value',
  };
}
