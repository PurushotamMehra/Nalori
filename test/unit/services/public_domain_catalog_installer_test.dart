import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nalori/models/public_domain_book.dart';
import 'package:nalori/models/public_domain_catalog.dart';
import 'package:nalori/services/public_domain_catalog_database.dart';
import 'package:nalori/services/public_domain_catalog_installer.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  var sqliteAvailable = true;

  setUpAll(() async {
    sqfliteFfiInit();
    try {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.close();
    } catch (_) {
      sqliteAvailable = false;
    }
  });

  setUp(() async {
    if (!sqliteAvailable) return;
    tempDir = await Directory.systemTemp.createTemp('nalori_catalog_install_');
  });

  tearDown(() async {
    if (!sqliteAvailable) return;
    await tempDir.delete(recursive: true);
  });

  test('manifest parsing validates the immutable download URL', () {
    final manifest = PublicDomainCatalogManifest.fromJson({
      'schema_version': 1,
      'catalog_version': '2026-06-14',
      'generated_at': '2026-06-14T00:00:00Z',
      'record_count': 2,
      'compressed_size_bytes': 100,
      'installed_size_bytes': 500,
      'sha256': 'abc',
      'download_url': 'https://example.com/catalogs/gutenberg.sqlite.gz',
    });

    expect(manifest.schemaVersion, 1);
    expect(manifest.downloadUrl.host, 'example.com');
  });

  test('installs a verified gzip SQLite catalogue', () async {
    if (!sqliteAvailable) return;
    final artifact = await _artifact(tempDir, [_book(1, 'Installed Book')]);
    final manifest = artifact.manifest;
    final database = _targetDatabase(tempDir);
    final installer = PublicDomainCatalogInstaller(
      database: database,
      client: MockClient((request) async {
        expect(request.url, manifest.downloadUrl);
        return http.Response.bytes(
          artifact.compressedBytes,
          200,
          headers: {
            'content-length': artifact.compressedBytes.length.toString(),
          },
        );
      }),
    );

    await installer.installFromManifest(manifest);

    final page = await database.query(query: const PublicDomainBookQuery());
    expect(page.books.single.title, 'Installed Book');
  });

  test('checksum failure rejects a corrupted catalogue', () async {
    if (!sqliteAvailable) return;
    final artifact = await _artifact(tempDir, [_book(2, 'Corrupt Book')]);
    final database = _targetDatabase(tempDir);
    final installer = PublicDomainCatalogInstaller(
      database: database,
      client: MockClient(
        (_) async => http.Response.bytes(artifact.compressedBytes, 200),
      ),
    );
    final badManifest = PublicDomainCatalogManifest(
      schemaVersion: artifact.manifest.schemaVersion,
      catalogVersion: artifact.manifest.catalogVersion,
      generatedAt: artifact.manifest.generatedAt,
      recordCount: artifact.manifest.recordCount,
      compressedSizeBytes: artifact.manifest.compressedSizeBytes,
      installedSizeBytes: artifact.manifest.installedSizeBytes,
      sha256: '0' * 64,
      downloadUrl: artifact.manifest.downloadUrl,
    );

    await expectLater(
      installer.installFromManifest(badManifest),
      throwsA(isA<PublicDomainCatalogInstallException>()),
    );
    expect(await database.exists(), isFalse);
  });

  test('failed update preserves previous valid catalogue', () async {
    if (!sqliteAvailable) return;
    final database = _targetDatabase(tempDir);
    await database.open();
    await database.seedForTests(books: [_book(10, 'Previous Book')]);
    await database.close();
    final artifact = await _artifact(tempDir, [_book(11, 'New Book')]);
    final installer = PublicDomainCatalogInstaller(
      database: database,
      client: MockClient(
        (_) async => http.Response.bytes(artifact.compressedBytes, 200),
      ),
    );
    final badManifest = PublicDomainCatalogManifest(
      schemaVersion: artifact.manifest.schemaVersion,
      catalogVersion: artifact.manifest.catalogVersion,
      generatedAt: artifact.manifest.generatedAt,
      recordCount: 999,
      compressedSizeBytes: artifact.manifest.compressedSizeBytes,
      installedSizeBytes: artifact.manifest.installedSizeBytes,
      sha256: artifact.manifest.sha256,
      downloadUrl: artifact.manifest.downloadUrl,
    );

    await expectLater(
      installer.installFromManifest(badManifest),
      throwsA(isA<PublicDomainCatalogInstallException>()),
    );

    final page = await database.query(query: const PublicDomainBookQuery());
    expect(page.books.single.title, 'Previous Book');
  });

  test('old temporary catalogue files are removed', () async {
    if (!sqliteAvailable) return;
    final database = _targetDatabase(tempDir);
    final installer = PublicDomainCatalogInstaller(database: database);
    final dir = File(await database.databasePath()).parent;
    await dir.create(recursive: true);
    final staleDownload = File(p.join(dir.path, 'old.download'));
    final staleSqlite = File(p.join(dir.path, 'old.sqlite.tmp'));
    await staleDownload.writeAsString('stale');
    await staleSqlite.writeAsString('stale');

    await installer.cleanupTemporaryFiles();

    expect(await staleDownload.exists(), isFalse);
    expect(await staleSqlite.exists(), isFalse);
  });
}

PublicDomainCatalogDatabase _targetDatabase(Directory tempDir) {
  return PublicDomainCatalogDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: p.join(tempDir.path, 'target', 'catalog.sqlite'),
  );
}

Future<_Artifact> _artifact(
  Directory tempDir,
  List<PublicDomainBook> books,
) async {
  final sourcePath = p.join(
    tempDir.path,
    'source_${DateTime.now().microsecondsSinceEpoch}.sqlite',
  );
  final source = PublicDomainCatalogDatabase(
    databaseFactory: databaseFactoryFfi,
    databasePath: sourcePath,
  );
  await source.open();
  await source.seedForTests(books: books, catalogVersion: 'fixture-v1');
  await source.close();

  final rawBytes = await File(sourcePath).readAsBytes();
  final compressed = gzip.encode(rawBytes);
  final digest = sha256.convert(compressed).toString();
  return _Artifact(
    compressedBytes: compressed,
    manifest: PublicDomainCatalogManifest(
      schemaVersion: PublicDomainCatalogDatabase.schemaVersion,
      catalogVersion: 'fixture-v1',
      generatedAt: DateTime.utc(2026, 6, 14),
      recordCount: books.length,
      compressedSizeBytes: compressed.length,
      installedSizeBytes: rawBytes.length,
      sha256: digest,
      downloadUrl: Uri.parse('https://example.com/catalog.sqlite.gz'),
    ),
  );
}

PublicDomainBook _book(int id, String title) {
  return PublicDomainBook(
    id: id,
    title: title,
    authors: const ['Test Author'],
    authorDetails: const [PublicDomainPerson(name: 'Test Author')],
    languages: const ['en'],
    epubUrl: 'https://www.gutenberg.org/ebooks/$id.epub3.images',
    downloadCount: id,
  );
}

class _Artifact {
  final List<int> compressedBytes;
  final PublicDomainCatalogManifest manifest;

  const _Artifact({required this.compressedBytes, required this.manifest});
}
