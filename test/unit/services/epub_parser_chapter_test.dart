// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/epub_parser.dart';

void main() {
  group('EpubParserService chapter navigation', () {
    test(
      'uses TOC anchors when multiple chapters share one HTML file',
      () async {
        final dir = await Directory.systemTemp.createTemp('epub_parser_test_');
        addTearDown(() => dir.delete(recursive: true));

        final file = File('${dir.path}/same_file_anchors.epub');
        await file.writeAsBytes(_buildSameFileAnchorEpub());

        final result = await EpubParserService().loadAndParseFromFile(file);
        final chapters = result.chapters;

        expect(chapters.map((chapter) => chapter.title), [
          'Chapter One',
          'Chapter Two',
          'Chapter Three',
        ]);
        expect(chapters[0].chunkIndex, lessThan(chapters[1].chunkIndex));
        expect(chapters[1].chunkIndex, lessThan(chapters[2].chunkIndex));
        expect(result.anchorMap['text/body.xhtml#ch2'], chapters[1].chunkIndex);
        expect(result.anchorMap['body.xhtml#ch3'], chapters[2].chunkIndex);
      },
    );
  });

  group('EpubParserService dialogue detection', () {
    test('splits and marks a long quoted paragraph as dialogue', () async {
      final dir = await Directory.systemTemp.createTemp('epub_dialogue_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/dialogue_split.epub');
      await file.writeAsBytes(_buildDialogueSplitEpub());

      final result = await EpubParserService().loadAndParseFromFile(file);
      final dialogueChunks = result.chunks
          .where(
            (chunk) =>
                chunk.type == BookChunkType.text &&
                !chunk.isHeading &&
                chunk.section == ChunkSection.content,
          )
          .toList();

      expect(dialogueChunks, isNotEmpty);
      expect(dialogueChunks.length, greaterThan(1));
      expect(dialogueChunks.every((chunk) => chunk.isDialogue), isTrue);
    });

    test('treats long spoken paragraphs as dialogue even with low quote ratio', () {
      const longDialogue =
          '"Well, it was this way," returned Mr. Enfield. "I was coming home from '
          'some place at the end of the world, about three o\'clock of a black '
          'winter morning, and my way lay through a part of town where there was '
          'literally nothing to be seen but lamps and sleeping streets."';
      const quotedProse =
          'He remembered the phrase "black winter morning" later, but the rest '
          'of the paragraph was ordinary narration without spoken dialogue.';

      expect(isLikelyDialogueText(longDialogue), isTrue);
      expect(isLikelyDialogueText(quotedProse), isFalse);
    });
  });

  group('EpubParserService publisher block styling', () {
    test('preserves poem and quote layout metadata', () async {
      final dir = await Directory.systemTemp.createTemp('epub_special_blocks_');
      addTearDown(() => dir.delete(recursive: true));

      final file = File('${dir.path}/special_blocks.epub');
      await file.writeAsBytes(_buildSpecialBlockEpub());

      final result = await EpubParserService().loadAndParseFromFile(file);
      final poem = result.chunks.firstWhere(
        (chunk) => chunk.blockRole == BookBlockRole.poem,
      );
      final quote = result.chunks.firstWhere(
        (chunk) => chunk.blockRole == BookBlockRole.quote,
      );
      final normal = result.chunks.firstWhere(
        (chunk) => chunk.text?.contains('ordinary paragraph') == true,
      );

      expect(poem.text, contains('First line\nSecond line'));
      expect(poem.publisherTextAlign, BookTextAlign.center);
      expect(poem.preserveLineBreaks, isTrue);
      expect(poem.usesPublisherLayout, isTrue);

      expect(quote.publisherTextAlign, BookTextAlign.right);
      expect(quote.publisherLeftIndent, greaterThan(0));
      expect(quote.usesPublisherLayout, isTrue);

      expect(normal.blockRole, BookBlockRole.paragraph);
      expect(normal.usesPublisherLayout, isFalse);
    });
  });
}

List<int> _buildSameFileAnchorEpub() {
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
    <dc:title>Anchor Test Book</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">anchor-test</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="body" href="text/body.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="body"/>
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head>
    <meta name="dtb:uid" content="anchor-test"/>
  </head>
  <docTitle><text>Anchor Test Book</text></docTitle>
  <navMap>
    <navPoint id="nav1" playOrder="1">
      <navLabel><text>Chapter One</text></navLabel>
      <content src="text/body.xhtml#ch1"/>
    </navPoint>
    <navPoint id="nav2" playOrder="2">
      <navLabel><text>Chapter Two</text></navLabel>
      <content src="text/body.xhtml#ch2"/>
    </navPoint>
    <navPoint id="nav3" playOrder="3">
      <navLabel><text>Chapter Three</text></navLabel>
      <content src="text/body.xhtml#ch3"/>
    </navPoint>
  </navMap>
</ncx>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/body.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Anchor Test Book</title></head>
  <body>
    <h1 id="ch1">Chapter One</h1>
    <p>First chapter text has enough words to remain separate from the next heading after parsing and chunking.</p>
    <h1 id="ch2">Chapter Two</h1>
    <p>Second chapter text has enough words to prove the table of contents points beyond the first heading.</p>
    <h1 id="ch3">Chapter Three</h1>
    <p>Third chapter text has enough words to prove every anchor resolves to its own later card.</p>
  </body>
</html>''',
      ),
    );

  return ZipEncoder().encode(archive)!;
}

List<int> _buildDialogueSplitEpub() {
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
    <dc:title>Dialogue Test Book</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">dialogue-test</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="body" href="text/body.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="body"/>
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head>
    <meta name="dtb:uid" content="dialogue-test"/>
  </head>
  <docTitle><text>Dialogue Test Book</text></docTitle>
  <navMap>
    <navPoint id="nav1" playOrder="1">
      <navLabel><text>Chapter One</text></navLabel>
      <content src="text/body.xhtml#ch1"/>
    </navPoint>
  </navMap>
</ncx>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/body.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Dialogue Test Book</title></head>
  <body>
    <h1 id="ch1">Chapter One</h1>
    <p>"I was coming home from some place at the end of the world, about three o'clock of a black winter morning." "My way lay through a part of town where there was literally nothing to be seen but lamps and sleeping streets." "Street after street was lit up, and I kept moving until I saw two figures approaching the corner at speed." "One was a little man walking eastward, and the other was a girl running as hard as she was able down a cross street." "They ran into one another at the corner, and then came the horrible part of the thing for the man trampled calmly over the child's body." "I gave a few halloa, took to my heels, collared my gentleman, and brought him back to where there was already quite a group about the screaming child." "He was perfectly cool and made no resistance, but gave me one look so ugly that it brought out the sweat on me like running." "The people who had turned out were the girl's own family, and pretty soon the doctor arrived to hear the whole tale."</p>
  </body>
</html>''',
      ),
    );

  return ZipEncoder().encode(archive)!;
}

List<int> _buildSpecialBlockEpub() {
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
    <dc:title>Special Block Test Book</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">special-block-test</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="body" href="text/body.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="body"/>
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/toc.ncx',
        '''<?xml version="1.0" encoding="UTF-8"?>
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head>
    <meta name="dtb:uid" content="special-block-test"/>
  </head>
  <docTitle><text>Special Block Test Book</text></docTitle>
  <navMap>
    <navPoint id="nav1" playOrder="1">
      <navLabel><text>Chapter One</text></navLabel>
      <content src="text/body.xhtml#ch1"/>
    </navPoint>
  </navMap>
</ncx>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/text/body.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>Special Block Test Book</title></head>
  <body>
    <h1 id="ch1">Chapter One</h1>
    <div class="poem" style="text-align: center">
      <p>First line<br/>Second line</p>
      <p>Third line</p>
    </div>
    <blockquote style="margin-left: 2em; text-align: right">
      <p>A quoted passage that keeps its book declared alignment and indentation.</p>
    </blockquote>
    <p>This ordinary paragraph should continue to follow reader density and alignment settings.</p>
  </body>
</html>''',
      ),
    );

  return ZipEncoder().encode(archive)!;
}
