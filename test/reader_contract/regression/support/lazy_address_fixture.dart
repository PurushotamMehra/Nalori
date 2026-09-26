import 'package:archive/archive.dart';

// Isolated proof fixture; does not modify any frozen fixture or oracle.
List<int> buildAddressFixture({
  int sectionCount = 7,
  Set<int> emptySections = const {},
  Map<int, String> sectionBodies = const {},
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
    final body =
        sectionBodies[i] ??
        (emptySections.contains(i)
            ? ''
            : '<h1 id="s$i">Section $i</h1><p>Section $i text.</p>');
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
