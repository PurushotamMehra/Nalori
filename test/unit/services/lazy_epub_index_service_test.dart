import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/lazy_epub_index_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_lazy_epub_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'opens a lightweight index without reading every spine section',
    () async {
      final file = File(p.join(tempDir.path, 'lazy.epub'));
      await file.writeAsBytes(_buildLazyFixture(), flush: true);

      final handle = await const LazyEpubIndexService().openBookIndex(file);
      addTearDown(handle.close);

      expect(handle.index.bookId, 'lazy.epub');
      expect(handle.index.title, 'Lazy Fixture');
      expect(handle.index.author, 'Test Author');
      expect(handle.index.contentDirectoryPath, 'OEBPS');
      expect(
        handle.index.manifest.keys,
        containsAll(['text/ch1.xhtml', 'text/ch2.xhtml']),
      );
      expect(handle.index.spine.map((item) => item.href), [
        'text/ch1.xhtml',
        'text/ch2.xhtml',
      ]);
      expect(handle.index.spine.first.index, 0);
      expect(handle.index.spine.first.sizeBytes, isPositive);
      expect(handle.index.chapters.map((chapter) => chapter.title), [
        'Chapter One',
        'Chapter Two',
      ]);

      final section = await handle.readSection(1);

      expect(section.spineIndex, 1);
      expect(section.href, 'text/ch2.xhtml');
      expect(section.html, contains('Second section unique text.'));
      expect(section.html, isNot(contains('First section unique text.')));
    },
  );

  test('reads cover and arbitrary resources on demand', () async {
    final file = File(p.join(tempDir.path, 'resources.epub'));
    await file.writeAsBytes(_buildLazyFixture(), flush: true);

    final handle = await const LazyEpubIndexService().openBookIndex(file);
    addTearDown(handle.close);

    expect(handle.index.coverHref, 'images/cover.png');

    final cover = await handle.readCoverResource();
    final css = await handle.readResource('styles/book.css');

    expect(cover, isNotNull);
    expect(cover!.mediaType, 'image/png');
    expect(cover.bytes, _coverBytes);
    expect(css.mediaType, 'text/css');
    expect(String.fromCharCodes(css.bytes), contains('line-height'));
  });
}

const _coverBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];

List<int> _buildLazyFixture() {
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
    <dc:title>Lazy Fixture</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">lazy-fixture</dc:identifier>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="style" href="styles/book.css" media-type="text/css"/>
    <item id="cover-image" href="images/cover.png" media-type="image/png"/>
    <item id="ch1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head><meta name="dtb:uid" content="lazy-fixture"/></head>
  <docTitle><text>Lazy Fixture</text></docTitle>
  <navMap>
    <navPoint id="nav1" playOrder="1">
      <navLabel><text>Chapter One</text></navLabel>
      <content src="text/ch1.xhtml#ch1"/>
    </navPoint>
    <navPoint id="nav2" playOrder="2">
      <navLabel><text>Chapter Two</text></navLabel>
      <content src="text/ch2.xhtml#ch2"/>
    </navPoint>
  </navMap>
</ncx>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/ch1.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>One</title><link rel="stylesheet" href="../styles/book.css"/></head>
  <body><h1 id="ch1">Chapter One</h1><p>First section unique text.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/ch2.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Two</title><link rel="stylesheet" href="../styles/book.css"/></head>
  <body><h1 id="ch2">Chapter Two</h1><p>Second section unique text.</p></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string('OEBPS/styles/book.css', 'body { line-height: 1.4; }'),
    )
    ..addFile(
      ArchiveFile('OEBPS/images/cover.png', _coverBytes.length, _coverBytes),
    );

  return ZipEncoder().encode(archive)!;
}
