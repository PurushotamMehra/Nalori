import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/book_metadata_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'nalori_metadata_lazy_index_',
    );
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'metadata extraction uses lightweight index and cover resource',
    () async {
      final epub = File(p.join(tempDir.path, 'metadata_lazy.epub'));
      await epub.writeAsBytes(_metadataFixture(), flush: true);

      final service = BookMetadataService();
      final metadata = await service.extractAndCacheMetadata(epub);

      expect(metadata, isNotNull);
      expect(metadata!.id, 'metadata_lazy.epub');
      expect(metadata.title, 'Metadata Lazy Fixture');
      expect(metadata.author, 'Fixture Author');
      expect(metadata.coverSource, 'embedded');
      expect(metadata.coverImagePath, isNotNull);
      expect(await File(metadata.coverImagePath!).readAsBytes(), _coverBytes);
    },
  );

  test('malformed metadata input returns a recoverable null result', () async {
    final epub = File(p.join(tempDir.path, 'corrupt.epub'));
    await epub.writeAsString('not an epub', flush: true);

    final service = BookMetadataService();
    final metadata = await service.extractAndCacheMetadata(epub);

    expect(metadata, isNull);
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

const _coverBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];

List<int> _metadataFixture() {
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
    <dc:title>Metadata Lazy Fixture</dc:title>
    <dc:creator>Fixture Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">metadata-lazy-fixture</dc:identifier>
    <meta property="dcterms:modified">2026-06-13T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover-image" href="images/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="chapter1" href="chapter-1.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter2" href="chapter-2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
    <itemref idref="chapter2"/>
  </spine>
</package>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/nav.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body><nav epub:type="toc"><ol><li><a href="chapter-1.xhtml#c1">Chapter 1</a></li></ol></nav></body>
</html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/chapter-1.xhtml',
        '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body><h1 id="c1">Chapter 1</h1><p>Readable metadata fixture text.</p></body></html>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/chapter-2.xhtml',
        '<html><body><p>This intentionally incomplete section should not be parsed during metadata extraction.',
      ),
    )
    ..addFile(
      ArchiveFile('OEBPS/images/cover.png', _coverBytes.length, _coverBytes),
    );

  return ZipEncoder().encode(archive)!;
}
