import 'dart:io';
import 'dart:convert' as convert;

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:image/image.dart' as image;

void main() async {
  final output = File('test/fixtures/books/feature_rich_lazy_reader.epub');
  await output.parent.create(recursive: true);
  final archive = Archive()
    ..addFile(
      ArchiveFile.noCompress(
        'mimetype',
        'application/epub+zip'.length,
        convert.utf8.encode('application/epub+zip'),
      ),
    )
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
    ..addFile(ArchiveFile.string('OEBPS/content.opf', _opf))
    ..addFile(ArchiveFile.string('OEBPS/nav.xhtml', _nav))
    ..addFile(
      ArchiveFile.string(
        'OEBPS/titlepage.xhtml',
        _xhtml('Title Page', _titleBody),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/chapter-1.xhtml',
        _xhtml('Chapter 1', _chapter1Body),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/chapter-2.xhtml',
        _xhtml('Chapter 2', _chapter2Body),
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/chapter-3.xhtml',
        _xhtml('Chapter 3', _chapter3Body),
      ),
    )
    ..addFile(
      ArchiveFile.string('OEBPS/notes.xhtml', _xhtml('Notes', _notesBody)),
    )
    ..addFile(
      ArchiveFile(
        'OEBPS/images/generated-square.png',
        _pngBytes.length,
        _pngBytes,
      ),
    );

  final bytes = ZipEncoder().encode(archive)!;
  await output.writeAsBytes(bytes, flush: true);
  stdout.writeln('Wrote ${output.path} (${bytes.length} bytes)');
}

const _opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" unique-identifier="bookid" xmlns="http://www.idpf.org/2007/opf">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Feature Rich Lazy Reader Fixture</dc:title>
    <dc:creator>Nalori Test Generator</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">feature-rich-lazy-reader-fixture</dc:identifier>
    <meta property="dcterms:modified">2026-06-13T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="titlepage" href="titlepage.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter1" href="chapter-1.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter2" href="chapter-2.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter3" href="chapter-3.xhtml" media-type="application/xhtml+xml"/>
    <item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/>
    <item id="generatedSquare" href="images/generated-square.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="titlepage"/>
    <itemref idref="chapter1"/>
    <itemref idref="chapter2"/>
    <itemref idref="chapter3"/>
    <itemref idref="notes" linear="no"/>
  </spine>
</package>''';

const _nav = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head><title>Navigation</title></head>
  <body>
    <nav epub:type="toc" id="toc">
      <h1>Contents</h1>
      <ol>
        <li><a href="titlepage.xhtml#titlepage">Title Page</a></li>
        <li>
          <a href="chapter-1.xhtml#part-i">Part I</a>
          <ol>
            <li><a href="chapter-1.xhtml#chapter-1">Chapter 1</a></li>
            <li><a href="chapter-2.xhtml#chapter-2">Chapter 2</a></li>
          </ol>
        </li>
        <li>
          <a href="chapter-3.xhtml#part-ii">Part II</a>
          <ol>
            <li><a href="chapter-3.xhtml#chapter-3">Chapter 3</a></li>
          </ol>
        </li>
        <li><a href="notes.xhtml#note-1">Notes</a></li>
      </ol>
    </nav>
  </body>
</html>''';

String _xhtml(String title, String body) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <head>
    <title>$title</title>
  </head>
  <body>
$body
  </body>
</html>''';

const _titleBody = '''
    <section id="titlepage">
      <h1>Feature Rich Lazy Reader Fixture</h1>
      <p>This title page is synthetic front matter for reader routing tests.</p>
    </section>''';

final _chapter1Body =
    '''
    <section id="chapter-1">
      <h1 id="part-i">Part I</h1>
      <h1>Chapter 1</h1>
      <p id="origin-paragraph">Synthetic paragraph with a unique source context for lazy footnote testing. Mira studies the repeated phrase luminous pebble before following the cross section note. <a href="notes.xhtml#note-1" epub:type="noteref">1</a></p>
      <p id="same-section-target">Same section anchor target with a clean synthetic context for local anchor navigation.</p>
      <p><a href="#same-section-target">Jump to the same section target</a>.</p>
      <p><a href="chapter-2.xhtml#chapter-2-target">Jump to the Chapter 2 target paragraph</a>.</p>
      <figure id="chapter-1-image">
        <img src="images/generated-square.png" alt="Synthetic generated square image"/>
        <figcaption>Generated square image for lazy resource tests.</figcaption>
      </figure>
      <table id="chapter-1-table">
        <tr><th>Speaker</th><th>Line</th></tr>
        <tr><td>Mira</td><td>The luminous pebble appears in more than one section.</td></tr>
        <tr><td>Sol</td><td>The table stays in reading order.</td></tr>
      </table>
${_paragraphs('chapter one filler', 16)}
    </section>''';

final _chapter2Body =
    '''
    <section id="chapter-2">
      <h1>Chapter 2</h1>
      <p id="chapter-2-target">Chapter 2 target paragraph for a cross section internal link. Mira returns to the luminous pebble phrase in a different section.</p>
      <p id="chapter-2-bookmark-target">Chapter 2 bookmark and highlight target with deterministic repeated words and exact offsets.</p>
${_paragraphs('chapter two filler', 28)}
    </section>''';

final _chapter3Body =
    '''
    <section id="chapter-3">
      <h1 id="part-ii">Part II</h1>
      <h1>Chapter 3</h1>
      <p id="chapter-3-start">Part II begins here. Mira and Sol verify previous chapter and next chapter navigation across parts.</p>
${_paragraphs('chapter three filler', 24)}
    </section>''';

const _notesBody = '''
    <section id="notes">
      <h1>Notes</h1>
      <aside id="note-1" epub:type="footnote">
        <p>Synthetic footnote content for lazy cross section navigation. <a href="chapter-1.xhtml#origin-paragraph" epub:type="backlink">Return</a></p>
      </aside>
    </section>''';

String _paragraphs(String label, int count) {
  return List.generate(count, (index) {
    final n = index + 1;
    return '      <p id="$label-$n">$label paragraph $n keeps the synthetic reader busy with deterministic prose. Mira watches Sol repeat the luminous pebble phrase while Nalori tests lazy section boundaries.</p>';
  }).join('\n');
}

final _pngBytes = image.encodePng(image.Image.rgb(4, 4)..fill(0xff2277cc));
