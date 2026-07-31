import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_lazy_session_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('opens index and loads only requested section window', () async {
    final file = File(p.join(tempDir.path, 'session.epub'));
    await file.writeAsBytes(_buildSessionFixture(), flush: true);
    final session = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(p.join(tempDir.path, 'cache')),
        ),
      ),
    );
    addTearDown(session.close);

    final index = await session.open(file);
    final initial = session.initialLocation();
    final window = await session.loadAround(initial, after: 1);

    expect(index.spine, hasLength(3));
    expect(initial.spineIndex, 0);
    expect(window.sections.map((section) => section.identity.spineIndex), [
      0,
      1,
    ]);
    expect(window.hasContentBefore, isFalse);
    expect(window.hasContentAfter, isTrue);
    expect(session.loadedSpineIndices, [0, 1]);
  });

  test(
    'resolves chapter and anchor targets without loading target section',
    () async {
      final file = File(p.join(tempDir.path, 'session.epub'));
      await file.writeAsBytes(_buildSessionFixture(), flush: true);
      final session = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(tempDir.path, 'cache')),
          ),
        ),
      );
      addTearDown(session.close);

      final index = await session.open(file);
      final chapter = index.chapters[2];
      final target = session.resolveChapterTarget(chapter);
      final anchor = session.resolveAnchor('text/s2.xhtml', 's2');

      expect(session.loadedSpineIndices, isEmpty);
      expect(target?.spineIndex, 2);
      expect(target?.anchorId, 's3');
      expect(anchor?.spineIndex, 1);
      expect(anchor?.anchorId, 's2');
    },
  );

  test('new lazy book starts at first meaningful reading chapter', () async {
    final file = File(p.join(tempDir.path, 'front_matter.epub'));
    await file.writeAsBytes(_buildFrontMatterFixture(), flush: true);
    final session = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(p.join(tempDir.path, 'front_cache')),
        ),
      ),
    );
    addTearDown(session.close);

    await session.open(file);
    final initial = session.initialLocation();

    expect(initial.spineIndex, 4);
    expect(initial.href, 'text/chapter1.xhtml');
    expect(initial.anchorId, 'chapter1');
  });

  test('unloaded chapter targets retain distinct stable order', () async {
    final file = File(p.join(tempDir.path, 'session.epub'));
    await file.writeAsBytes(_buildSessionFixture(), flush: true);
    final session = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(p.join(tempDir.path, 'order_cache')),
        ),
      ),
    );
    addTearDown(session.close);

    final index = await session.open(file);
    final window = await session.loadAround(
      session.resolveChapterTarget(index.chapters.first)!,
    );

    final chapterIndexes = window.chapters.map((chapter) => chapter.chunkIndex);
    expect(chapterIndexes.toSet(), hasLength(window.chapters.length));
    expect(window.chapters[2].stableLocation?.spineIndex, 2);
  });

  test('valid saved stable location is used as initial lazy target', () async {
    final file = File(p.join(tempDir.path, 'session.epub'));
    await file.writeAsBytes(_buildSessionFixture(), flush: true);
    final session = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(p.join(tempDir.path, 'saved_cache')),
        ),
      ),
    );
    addTearDown(session.close);

    final index = await session.open(file);
    final saved = session.resolveChapterTarget(index.chapters[2]);
    expect(saved, isNotNull);

    final initial = session.initialLocation(requested: saved);
    final window = await session.loadAround(initial, after: 0);

    expect(initial, saved);
    expect(initial.spineIndex, 2);
    expect(window.sections.map((section) => section.identity.spineIndex), [2]);
    expect(session.loadedSpineIndices, [2]);
  });

  test(
    'cold restore window can rebuild previous current and next around saved target',
    () async {
      final file = File(p.join(tempDir.path, 'session.epub'));
      await file.writeAsBytes(_buildSessionFixture(), flush: true);
      final session = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(tempDir.path, 'cold_cache')),
          ),
        ),
      );
      addTearDown(session.close);

      final index = await session.open(file);
      final saved = session
          .resolveChapterTarget(index.chapters[1])!
          .copyWith(
            localChunkIndex: 0,
            localDisplayIndex: 3,
            readerLayoutFingerprint: 'layout-v1',
            previousSpineIndex: 0,
            nextSpineIndex: 2,
          );
      final window = await session.loadAround(saved, before: 1, after: 1);

      expect(window.sections.map((section) => section.identity.spineIndex), [
        0,
        1,
        2,
      ]);
      expect(window.hasContentBefore, isFalse);
      expect(window.hasContentAfter, isFalse);
      expect(session.loadedSpineIndices, [1, 0, 2]);
      expect(
        window.locationsByChunkIndex.values.map((entry) => entry.spineIndex),
        containsAll(<int>[0, 1, 2]),
      );
    },
  );

  test(
    'incompatible saved stable location falls back to meaningful start',
    () async {
      final file = File(p.join(tempDir.path, 'front_matter.epub'));
      await file.writeAsBytes(_buildFrontMatterFixture(), flush: true);
      final session = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(tempDir.path, 'fallback_cache')),
          ),
        ),
      );
      addTearDown(session.close);

      await session.open(file);
      final initial = session.initialLocation(
        requested: const StableBookLocation(
          bookId: 'other-book',
          spineIndex: 0,
          href: 'text/cover.xhtml',
          sourceChecksum: 'old',
        ),
      );

      expect(initial.spineIndex, 4);
      expect(initial.href, 'text/chapter1.xhtml');
      expect(initial.anchorId, 'chapter1');
    },
  );

  test(
    'next and previous section loading updates current lazy focus',
    () async {
      final file = File(p.join(tempDir.path, 'session.epub'));
      await file.writeAsBytes(_buildSessionFixture(), flush: true);
      final session = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(tempDir.path, 'move_cache')),
          ),
        ),
      );
      addTearDown(session.close);

      await session.open(file);
      final middle = session.resolveAnchor('text/s2.xhtml', 's2');
      expect(middle, isNotNull);
      await session.loadAround(middle!, after: 0);

      final previous = await session.loadPreviousSection();
      expect(previous?.identity.spineIndex, 0);
      expect(session.currentLocation?.spineIndex, 0);

      final next = await session.loadNextSection();
      expect(next?.identity.spineIndex, 1);
      expect(session.currentLocation?.spineIndex, 1);

      final secondNext = await session.loadNextSection();
      expect(secondNext?.identity.spineIndex, 2);
      expect(session.currentLocation?.spineIndex, 2);
    },
  );

  test('readable adjacent resolution skips non-linear spine items', () async {
    final file = File(p.join(tempDir.path, 'non_linear.epub'));
    await file.writeAsBytes(_buildNonLinearFixture(), flush: true);
    final session = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(p.join(tempDir.path, 'non_linear_cache')),
        ),
      ),
    );
    addTearDown(session.close);

    await session.open(file);

    expect(session.nextReadableSpineIndex(0), 2);
    expect(session.previousReadableSpineIndex(2), 0);
    expect(session.previousReadableSpineIndex(0), isNull);
    expect(session.nextReadableSpineIndex(2), isNull);
  });

  test(
    'resolved empty trailing sections do not block readable completion',
    () async {
      final file = File(p.join(tempDir.path, 'trailing_empty.epub'));
      await file.writeAsBytes(
        _buildSessionFixture(emptySections: const {3}),
        flush: true,
      );
      final session = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(tempDir.path, 'empty_cache')),
          ),
        ),
      );
      addTearDown(session.close);

      await session.open(file);
      final second = session.resolveAnchor('text/s2.xhtml', 's2')!;
      await session.loadAround(second, after: 0);

      expect(session.nextReadableSpineIndex(1), 2);
      expect(await session.loadNextReadableSectionAfter(1), isNull);
      expect(session.nextReadableSpineIndex(1), isNull);
    },
  );

  test('adjacent readable loading skips unusable spine items', () async {
    final file = File(p.join(tempDir.path, 'non_linear.epub'));
    await file.writeAsBytes(_buildNonLinearFixture(), flush: true);
    final session = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(p.join(tempDir.path, 'skip_cache')),
        ),
      ),
    );
    addTearDown(session.close);

    await session.open(file);
    final first = session.resolveAnchor('text/s1.xhtml', 's1')!;
    await session.loadAround(first, after: 0);

    final next = await session.loadNextReadableSectionAfter(0);
    expect(next?.identity.spineIndex, 2);
    expect(
      next?.chunks.map((chunk) => chunk.text).join('\n'),
      contains('Final'),
    );

    final previous = await session.loadPreviousReadableSectionBefore(2);
    expect(previous?.identity.spineIndex, 0);
    expect(
      previous?.chunks.map((chunk) => chunk.text).join('\n'),
      contains('First'),
    );
  });

  test('loaded window reports real readable book boundaries', () async {
    final file = File(p.join(tempDir.path, 'non_linear.epub'));
    await file.writeAsBytes(_buildNonLinearFixture(), flush: true);
    final session = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(p.join(tempDir.path, 'bounds_cache')),
        ),
      ),
    );
    addTearDown(session.close);

    await session.open(file);
    final finalSection = session.resolveAnchor('text/s3.xhtml', 's3')!;
    final window = await session.loadAround(finalSection, after: 0);

    expect(window.sections.map((section) => section.identity.spineIndex), [2]);
    expect(window.hasContentBefore, isTrue);
    expect(window.hasContentAfter, isFalse);
  });

  test(
    'new lazy book without TOC starts at first non-front-matter spine',
    () async {
      final file = File(p.join(tempDir.path, 'no_toc.epub'));
      await file.writeAsBytes(_buildNoTocFixture(), flush: true);
      final session = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(tempDir.path, 'no_toc_cache')),
          ),
        ),
      );
      addTearDown(session.close);

      await session.open(file);
      final initial = session.initialLocation();

      expect(initial.spineIndex, 2);
      expect(initial.href, 'text/body.xhtml');
    },
  );

  test('publication mismatch is rejected without loading a section', () async {
    final session = await _openFixtureSession(
      tempDir,
      cacheName: 'mismatch_cache',
    );
    addTearDown(session.close);
    final item = session.index.spine[2];

    final resolution = await session.resolveStableLocation(
      StableBookLocation(
        bookId: session.index.bookId,
        spineIndex: item.index,
        href: item.href,
        sourceChecksum: item.sourceChecksum,
        publicationFingerprint: 'replaced-publication',
        normalizedHref: item.normalizedHref,
        sectionProgression: 0,
      ),
    );

    expect(resolution.location, isNull);
    expect(resolution.reason, 'publication_mismatch');
    expect(session.loadedSpineIndices, isEmpty);
  });

  test('ranked resolver prefers anchor then source offset', () async {
    final session = await _openFixtureSession(
      tempDir,
      cacheName: 'ranked_cache',
    );
    addTearDown(session.close);
    final anchorTarget = session.resolveAnchor('text/s3.xhtml', 's3')!;

    final anchor = await session.resolveStableLocation(anchorTarget);
    expect(anchor.confidence, StableLocationConfidence.anchor);
    expect(anchor.location?.spineIndex, 2);
    expect(session.loadedSpineIndices, [2]);

    final offset = await session.resolveStableLocation(
      anchor.location!.copyWith(
        anchorId: 'missing',
        localChunkIndex: 1,
        textOffset: 3,
      ),
    );
    expect(offset.confidence, StableLocationConfidence.exact);
    expect(offset.reason, 'source_offset');
    expect(offset.location?.localChunkIndex, 1);
    final laterOffset = await session.resolveStableLocation(
      anchor.location!.copyWith(
        anchorId: 'missing',
        localChunkIndex: 1,
        textOffset: 8,
      ),
    );
    expect(laterOffset.location?.localChunkIndex, 1);
    expect(laterOffset.location?.textOffset, 8);
    expect(
      laterOffset.location!.publicationProgression!,
      greaterThan(offset.location!.publicationProgression!),
    );

    final parserChanged = await session.resolveStableLocation(
      StableBookLocation(
        bookId: session.index.bookId,
        spineIndex: 2,
        href: 'text/s3.xhtml',
        sourceChecksum: session.index.spine[2].sourceChecksum,
        publicationFingerprint: session.index.publicationFingerprint,
        normalizedHref: 'text/s3.xhtml',
        localChunkIndex: 0,
        sourceParserVersion: 'older-parser',
        contextText: 'Section 3 text.',
      ),
    );
    expect(parserChanged.confidence, StableLocationConfidence.quote);
    expect(parserChanged.location?.localChunkIndex, 1);
  });

  test(
    'ambiguous quote remains unresolved and preserves legacy evidence',
    () async {
      final session = await _openFixtureSession(
        tempDir,
        cacheName: 'ambiguous_cache',
      );
      addTearDown(session.close);
      final item = session.index.spine[1];
      final legacy = StableBookLocation(
        bookId: session.index.bookId,
        spineIndex: item.index,
        href: item.href,
        sourceChecksum: 'old-parser-checksum',
        publicationFingerprint: session.index.publicationFingerprint,
        normalizedHref: item.normalizedHref,
        contextText: 'Section 2',
        legacyGlobalChunkIndex: 41,
      );

      final resolution = await session.resolveStableLocation(legacy);
      expect(resolution.location, isNull);
      expect(resolution.confidence, StableLocationConfidence.unresolved);
      expect(legacy.legacyGlobalChunkIndex, 41);
      expect(legacy.contextText, 'Section 2');
    },
  );

  test(
    'section and weighted progression resolve unloaded distant targets',
    () async {
      final session = await _openFixtureSession(
        tempDir,
        cacheName: 'progression_cache',
      );
      addTearDown(session.close);
      await session.loadAround(
        session.resolveAnchor('text/s1.xhtml', 's1')!,
        after: 0,
      );

      final weighted = session.locationForWeightedProgression(
        0.95,
        legacyGlobalChunkIndex: 95,
      );
      final window = await session.loadAround(weighted, after: 0);

      expect(session.currentLocation?.spineIndex, 2);
      expect(session.currentLocation?.legacyGlobalChunkIndex, 95);
      expect(session.currentLocation?.publicationProgression, closeTo(1, 0.2));
      expect(window.sections.map((section) => section.identity.spineIndex), [
        2,
      ]);

      final backward = await session.loadAround(
        session.resolveAnchor('text/s1.xhtml', 's1')!,
        after: 0,
      );
      expect(backward.sections.map((section) => section.identity.spineIndex), [
        0,
      ]);

      final relative = session.resolveAnchor('../text/s2.xhtml', 's2');
      expect(relative?.spineIndex, 1);
    },
  );

  test(
    'section chunk locations retain weighted progression when integrated',
    () async {
      final session = await _openFixtureSession(
        tempDir,
        cacheName: 'integrated_progress_cache',
      );
      addTearDown(session.close);
      final window = await session.loadAround(
        session.resolveAnchor('text/s2.xhtml', 's2')!,
        after: 0,
      );
      final section = window.sections.single;
      final locations = [
        for (var i = 0; i < section.chunks.length; i++)
          session.locationForSectionChunk(section, i),
      ];

      expect(
        locations.every((location) => location.publicationProgression != null),
        isTrue,
      );
      expect(
        locations.map((location) => location.publicationProgression!),
        orderedEquals(
          locations.map((location) => location.publicationProgression!).toList()
            ..sort(),
        ),
      );
    },
  );

  test(
    'superseded navigation preparation cannot replace current location',
    () async {
      final session = await _openFixtureSession(
        tempDir,
        cacheName: 'superseded_navigation_cache',
      );
      addTearDown(session.close);
      final initial = session.resolveAnchor('text/s1.xhtml', 's1')!;
      await session.loadAround(initial, after: 0);

      final preparation = await session.prepareNavigation(
        session.resolveAnchor('text/s3.xhtml', 's3')!,
        canCommit: () => false,
      );

      expect(preparation.superseded, isTrue);
      expect(preparation.window, isNull);
      expect(session.currentLocation?.spineIndex, 0);
      expect(session.loadedSpineIndices.length, lessThanOrEqualTo(3));
    },
  );

  test(
    'sequential reading keeps section ownership bounded and stable',
    () async {
      final file = File(p.join(tempDir.path, 'long_session.epub'));
      await file.writeAsBytes(
        _buildSessionFixture(sectionCount: 9),
        flush: true,
      );
      final session = LazyBookSession(
        nearbySectionCount: 1,
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(tempDir.path, 'long_cache')),
          ),
        ),
      );
      addTearDown(session.close);
      await session.open(file);

      for (var spineIndex = 0; spineIndex < 9; spineIndex++) {
        final target = session.resolveAnchor(
          'text/s${spineIndex + 1}.xhtml',
          's${spineIndex + 1}',
        )!;
        final window = await session.loadAround(target, before: 1, after: 1);
        expect(session.loadedSpineIndices.length, lessThanOrEqualTo(3));
        expect(window.sections.length, lessThanOrEqualTo(3));
        expect(
          window.sourceIdentitiesByChunkIndex.values.every(
            (identity) =>
                identity.section.publicationFingerprint ==
                    session.index.publicationFingerprint &&
                identity.section.normalizedHref.isNotEmpty &&
                identity.section.fullPath.isNotEmpty &&
                identity.section.sourceChecksum.isNotEmpty,
          ),
          isTrue,
        );
        for (final entry in window.sourceIdentitiesByChunkIndex.entries) {
          expect(window.chunkIndexBySourceIdentity[entry.value], entry.key);
        }
        expect(session.currentLocation?.spineIndex, spineIndex);
      }

      expect(session.loadedSpineIndices, isNot(contains(0)));
      final reloaded = await session.loadAround(
        session.resolveAnchor('text/s1.xhtml', 's1')!,
        after: 0,
      );
      expect(reloaded.sections.single.identity.spineIndex, 0);
      expect(
        reloaded.chunks.map((chunk) => chunk.text).join(),
        contains('Section 1'),
      );
    },
  );
}

Future<LazyBookSession> _openFixtureSession(
  Directory tempDir, {
  required String cacheName,
}) async {
  final file = File(p.join(tempDir.path, '$cacheName.epub'));
  await file.writeAsBytes(_buildSessionFixture(), flush: true);
  final session = LazyBookSession(
    repository: LazySectionRepository(
      cache: ParsedSectionCacheService(
        rootDirectory: Directory(p.join(tempDir.path, cacheName)),
      ),
    ),
  );
  await session.open(file);
  return session;
}

List<int> _buildSessionFixture({
  int sectionCount = 3,
  Set<int> emptySections = const {},
}) {
  final manifestItems = List.generate(
    sectionCount,
    (index) =>
        '<item id="s${index + 1}" href="text/s${index + 1}.xhtml" media-type="application/xhtml+xml"/>',
  ).join('\n    ');
  final spineItems = List.generate(
    sectionCount,
    (index) => '<itemref idref="s${index + 1}"/>',
  ).join('\n    ');
  final navPoints = List.generate(
    sectionCount,
    (index) =>
        '<navPoint id="nav${index + 1}" playOrder="${index + 1}"><navLabel><text>${index + 1}</text></navLabel><content src="text/s${index + 1}.xhtml#s${index + 1}"/></navPoint>',
  ).join('\n    ');
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
    <dc:title>Session Fixture</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">session-fixture</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    $manifestItems
  </manifest>
  <spine toc="ncx">
    $spineItems
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head><meta name="dtb:uid" content="session-fixture"/></head>
  <docTitle><text>Session Fixture</text></docTitle>
  <navMap>
    $navPoints
  </navMap>
</ncx>''',
      ),
    );

  for (var i = 1; i <= sectionCount; i++) {
    final body = emptySections.contains(i)
        ? ''
        : '<h1 id="s$i">Section $i</h1><p>Section $i text.</p>';
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/text/s$i.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>$i</title></head>
  <body>$body</body>
</html>''',
      ),
    );
  }

  return ZipEncoder().encode(archive)!;
}

List<int> _buildFrontMatterFixture() {
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
    <dc:title>Front Matter Fixture</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">front-fixture</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="preface" href="text/preface.xhtml" media-type="application/xhtml+xml"/>
    <item id="intro" href="text/introduction.xhtml" media-type="application/xhtml+xml"/>
    <item id="foreword" href="text/foreword.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="cover"/>
    <itemref idref="preface"/>
    <itemref idref="intro"/>
    <itemref idref="foreword"/>
    <itemref idref="chapter1"/>
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head><meta name="dtb:uid" content="front-fixture"/></head>
  <docTitle><text>Front Matter Fixture</text></docTitle>
  <navMap>
    <navPoint id="nav1" playOrder="1"><navLabel><text>Cover</text></navLabel><content src="text/cover.xhtml#cover"/></navPoint>
    <navPoint id="nav2" playOrder="2"><navLabel><text>Preface</text></navLabel><content src="text/preface.xhtml#preface"/></navPoint>
    <navPoint id="nav3" playOrder="3"><navLabel><text>Introduction</text></navLabel><content src="text/introduction.xhtml#introduction"/></navPoint>
    <navPoint id="nav4" playOrder="4"><navLabel><text>Foreword</text></navLabel><content src="text/foreword.xhtml#foreword"/></navPoint>
    <navPoint id="nav5" playOrder="5"><navLabel><text>Chapter 1</text></navLabel><content src="text/chapter1.xhtml#chapter1"/></navPoint>
  </navMap>
</ncx>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/cover.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Cover</title></head>
  <body><h1 id="cover">Cover</h1><p>Title page.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/preface.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Preface</title></head>
  <body><h1 id="preface">Preface</h1><p>Preface text.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/introduction.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Introduction</title></head>
  <body><h1 id="introduction">Introduction</h1><p>Introduction text.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/foreword.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Foreword</title></head>
  <body><h1 id="foreword">Foreword</h1><p>Foreword text.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/chapter1.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Chapter 1</title></head>
  <body><h1 id="chapter1">Chapter 1</h1><p>Real opening text.</p></body>
</html>''',
      ),
    );

  return ZipEncoder().encode(archive)!;
}

List<int> _buildNoTocFixture() {
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
<package version="3.0" unique-identifier="bookid" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>No TOC Fixture</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">no-toc-fixture</dc:identifier>
  </metadata>
  <manifest>
    <item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml"/>
    <item id="copyright" href="text/copyright.xhtml" media-type="application/xhtml+xml"/>
    <item id="body" href="text/body.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="cover"/>
    <itemref idref="copyright"/>
    <itemref idref="body"/>
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/cover.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Cover</title></head>
  <body><h1>Cover</h1></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/copyright.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Copyright</title></head>
  <body><p>Copyright page.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/body.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Body</title></head>
  <body><h1>Opening</h1><p>First real reading text.</p></body>
</html>''',
      ),
    );

  return ZipEncoder().encode(archive)!;
}

List<int> _buildNonLinearFixture() {
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
    <dc:title>Non Linear Fixture</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">non-linear-fixture</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="s1" href="text/s1.xhtml" media-type="application/xhtml+xml"/>
    <item id="skip" href="text/skip.xhtml" media-type="application/xhtml+xml"/>
    <item id="s3" href="text/s3.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="s1"/>
    <itemref idref="skip" linear="no"/>
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
  <head><meta name="dtb:uid" content="non-linear-fixture"/></head>
  <docTitle><text>Non Linear Fixture</text></docTitle>
  <navMap>
    <navPoint id="nav1" playOrder="1"><navLabel><text>First</text></navLabel><content src="text/s1.xhtml#s1"/></navPoint>
    <navPoint id="nav2" playOrder="2"><navLabel><text>Final</text></navLabel><content src="text/s3.xhtml#s3"/></navPoint>
  </navMap>
</ncx>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/s1.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>First</title></head>
  <body><h1 id="s1">First</h1><p>First readable text.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/skip.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Skip</title></head>
  <body><h1 id="skip">Skip</h1><p>Non linear text.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/s3.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Final</title></head>
  <body><h1 id="s3">Final</h1><p>Final readable text.</p></body>
</html>''',
      ),
    );

  return ZipEncoder().encode(archive)!;
}
