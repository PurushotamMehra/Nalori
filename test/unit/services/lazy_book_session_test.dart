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
}

List<int> _buildSessionFixture() {
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
    <item id="s1" href="text/s1.xhtml" media-type="application/xhtml+xml"/>
    <item id="s2" href="text/s2.xhtml" media-type="application/xhtml+xml"/>
    <item id="s3" href="text/s3.xhtml" media-type="application/xhtml+xml"/>
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
  <head><meta name="dtb:uid" content="session-fixture"/></head>
  <docTitle><text>Session Fixture</text></docTitle>
  <navMap>
    <navPoint id="nav1" playOrder="1"><navLabel><text>One</text></navLabel><content src="text/s1.xhtml#s1"/></navPoint>
    <navPoint id="nav2" playOrder="2"><navLabel><text>Two</text></navLabel><content src="text/s2.xhtml#s2"/></navPoint>
    <navPoint id="nav3" playOrder="3"><navLabel><text>Three</text></navLabel><content src="text/s3.xhtml#s3"/></navPoint>
  </navMap>
</ncx>''',
      ),
    );

  for (var i = 1; i <= 3; i++) {
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/text/s$i.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>$i</title></head>
  <body><h1 id="s$i">Section $i</h1><p>Section $i text.</p></body>
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
