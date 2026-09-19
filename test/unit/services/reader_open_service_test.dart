import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_metadata.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/book_metadata_service.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/reader_checkpoint_store.dart';
import 'package:nalori/services/reader_open_service.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('canonical journal location wins over valid legacy metadata', () {
    const journal = StableBookLocation(
      bookId: 'book.epub',
      spineIndex: 4,
      href: 'chapter-4.xhtml',
      sourceChecksum: 'journal',
      localChunkIndex: 9,
      textOffset: 42,
    );
    const metadata = StableBookLocation(
      bookId: 'book.epub',
      spineIndex: 3,
      href: 'chapter-3.xhtml',
      sourceChecksum: 'metadata',
      localChunkIndex: 1,
    );

    expect(
      selectReaderOpenRestoreLocation(
        checkpointLocation: journal,
        requestedLocation: null,
        metadataLocation: metadata,
        requestedLocationIsNavigationTarget: false,
      ),
      same(journal),
    );
  });

  test('explicit navigation target is the only checkpoint override', () {
    const journal = StableBookLocation(
      bookId: 'book.epub',
      spineIndex: 4,
      href: 'chapter-4.xhtml',
      sourceChecksum: 'journal',
    );
    const explicit = StableBookLocation(
      bookId: 'book.epub',
      spineIndex: 8,
      href: 'chapter-8.xhtml',
      sourceChecksum: 'search',
    );

    expect(
      selectReaderOpenRestoreLocation(
        checkpointLocation: journal,
        requestedLocation: explicit,
        metadataLocation: null,
        requestedLocationIsNavigationTarget: true,
      ),
      same(explicit),
    );
  });

  late Directory tempDir;
  late File fixture;
  late BookMetadataService metadataService;
  late ReaderCheckpointStore checkpointStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_reader_open_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    fixture = File(
      p.join('test', 'fixtures', 'books', 'feature_rich_lazy_reader.epub'),
    );
    expect(await fixture.exists(), isTrue);
    metadataService = BookMetadataService();
    await metadataService.init();
    checkpointStore = ReaderCheckpointStore.forTesting(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(tempDir.path, 'reader-checkpoints.sqlite3'),
    );
  });

  tearDown(() async {
    await checkpointStore.close();
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
        checkpointStore: checkpointStore,
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
        checkpointStore: checkpointStore,
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

  test('canonical checkpoint loads an otherwise unloaded chapter', () async {
    final probe = LazyBookSession();
    await probe.open(fixture);
    final target = probe.resolveAnchor('chapter-3.xhtml', 'chapter-3')!;
    final resolved = (await probe.resolveStableLocation(target)).location!;
    final weakerRequestedLocation = probe.initialLocation();
    final publicationFingerprint = probe.index.publicationFingerprint;
    await probe.close();

    final card = ReaderCardIdentity(
      publicationFingerprint: publicationFingerprint,
      layoutFingerprint: 'test-layout',
      ranges: [
        ReaderCardSourceRange(
          sectionIdentity: resolved.normalizedHref ?? resolved.href,
          sectionChecksum: resolved.sourceChecksum,
          logicalBlockId: 'chapter-3-anchor',
          structuralType: 'paragraph',
          startUtf16: 0,
          endUtf16: 20,
        ),
      ],
    );
    final epoch = await checkpointStore.beginSession(p.basename(fixture.path));
    final checkpoint = ReaderCheckpoint.create(
      bookId: p.basename(fixture.path),
      publicationFingerprint: publicationFingerprint,
      card: card,
      semanticAnchor: card.firstMeaningfulAnchor(),
      stableLocation: resolved,
      layoutFingerprint: 'test-layout',
      state: ReaderCheckpointState.exactCommitted,
      sessionEpoch: epoch,
      revision: 1,
      navigationSource: 'test',
    );
    expect((await checkpointStore.commit(checkpoint)).applied, isTrue);

    final result =
        await ReaderOpenService(
          metadataService: metadataService,
          checkpointStore: checkpointStore,
        ).openLazy(
          bookFile: fixture,
          requestedLocation: weakerRequestedLocation,
          legacyLastReadIndex: 1,
        );
    addTearDown(result.session.close);

    expect(result.checkpoint?.card?.signature, card.signature);
    expect(result.targetLocation.spineIndex, 3);
    expect(
      result.window.sections.map((section) => section.identity.spineIndex),
      contains(3),
    );
  });
}

final class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
