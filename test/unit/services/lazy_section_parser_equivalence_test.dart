import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/lazy_epub_index_service.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_lazy_equivalence_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('joined lazy section output matches full parser visible text', () async {
    final file = File(p.join(tempDir.path, 'equivalence.epub'));
    await file.writeAsBytes(_buildEquivalenceFixture(), flush: true);

    final parser = EpubParserService();
    final full = await parser.loadAndParseFromFile(file);
    final handle = await const LazyEpubIndexService().openBookIndex(file);
    addTearDown(handle.close);

    final lazyChunks = <BookChunk>[];
    for (final spineItem in handle.index.spine) {
      final section = await handle.readSection(spineItem.index);
      final parsed = parser.parseLazySection(
        identity: LazySectionIdentity.fromIndexItem(
          bookId: handle.index.bookId,
          item: spineItem,
          sourceChecksum: fnv1aHex(Uint8List.fromList(section.html.codeUnits)),
        ),
        html: section.html,
      );
      lazyChunks.addAll(parsed.chunks);
    }

    expect(_visibleText(lazyChunks), _visibleText(full.chunks));
    expect(
      lazyChunks.map((chunk) => chunk.sourceFile).toSet(),
      containsAll(['text/ch1.xhtml', 'text/ch2.xhtml']),
    );
  });
}

String _visibleText(List<BookChunk> chunks) {
  return chunks
      .where((chunk) => chunk.type == BookChunkType.text)
      .map((chunk) => chunk.text?.trim() ?? '')
      .where((text) => text.isNotEmpty)
      .join('\n\n')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<int> _buildEquivalenceFixture() {
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
    <dc:title>Equivalence Fixture</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">equivalence-fixture</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
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
  <head><meta name="dtb:uid" content="equivalence-fixture"/></head>
  <docTitle><text>Equivalence Fixture</text></docTitle>
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
  <head><title>One</title></head>
  <body>
    <h1 id="ch1">Chapter One</h1>
    <p>First paragraph with <strong>bold words</strong> and <a href="#note1">a local link</a>.</p>
    <aside id="note1"><p>Footnote body for chapter one.</p></aside>
  </body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/ch2.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Two</title></head>
  <body>
    <h1 id="ch2">Chapter Two</h1>
    <p>Second paragraph before the table.</p>
    <table>
      <tr><th>Speaker</th><th>Line</th></tr>
      <tr><td>Socrates</td><td>A table line.</td></tr>
    </table>
    <p>Second paragraph after the table.</p>
  </body>
</html>''',
      ),
    );

  return ZipEncoder().encode(archive)!;
}
