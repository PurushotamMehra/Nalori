import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_metadata.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/book_metadata_service.dart';
import 'package:nalori/services/reader_open_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File fixture;
  late BookMetadataService metadataService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_reader_open_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    fixture = File(
      p.join('test', 'fixtures', 'books', 'feature_rich_lazy_reader.epub'),
    );
    expect(await fixture.exists(), isTrue);
    metadataService = BookMetadataService();
    await metadataService.init();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'legacy last-read position migrates through structural weights',
    () async {
      final metadata = BookMetadata(
        id: p.basename(fixture.path),
        title: 'Fixture',
        author: 'Author',
        lastReadIndex: 75,
        totalChunks: 101,
      );
      await metadataService.updateMetadata(metadata);

      final result = await ReaderOpenService(
        metadataService: metadataService,
      ).openLazy(bookFile: fixture, metadata: metadata);
      addTearDown(result.session.close);

      final stored = metadataService.getMetadata(metadata.id)!;
      expect(result.targetLocation.publicationFingerprint, isNotEmpty);
      expect(result.targetLocation.publicationProgression, closeTo(0.75, 0.02));
      expect(result.targetLocation.legacyGlobalChunkIndex, 75);
      expect(stored.lastReadIndex, 75);
      expect(stored.lastReadLocation, result.targetLocation);
    },
  );

  test(
    'replacement mismatch does not reuse the old legacy percentage',
    () async {
      final metadata = BookMetadata(
        id: p.basename(fixture.path),
        title: 'Fixture',
        author: 'Author',
        lastReadIndex: 99,
        totalChunks: 101,
        lastReadLocation: StableBookLocation(
          bookId: p.basename(fixture.path),
          spineIndex: 4,
          href: 'notes.xhtml',
          sourceChecksum: 'old-checksum',
          publicationFingerprint: 'old-publication',
          sectionProgression: 0.9,
          legacyGlobalChunkIndex: 99,
        ),
      );
      await metadataService.updateMetadata(metadata);

      final result = await ReaderOpenService(
        metadataService: metadataService,
      ).openLazy(bookFile: fixture, metadata: metadata);
      addTearDown(result.session.close);

      expect(result.targetLocation.spineIndex, 1);
      expect(result.targetLocation.anchorId, 'chapter-1');
      expect(
        metadataService.getMetadata(metadata.id)!.lastReadLocation,
        metadata.lastReadLocation,
      );
    },
  );
}

final class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
