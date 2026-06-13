import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/public_domain_catalog.dart';
import 'api_client.dart';
import 'public_domain_catalog_database.dart';

typedef PublicDomainCatalogDownloadProgress =
    void Function(int receivedBytes, int? totalBytes);

class PublicDomainCatalogInstaller {
  PublicDomainCatalogInstaller({
    required PublicDomainCatalogDatabase database,
    http.Client? client,
    Uri? manifestUri,
  }) : _database = database,
       _manifestUri = manifestUri ?? _defaultManifestUri(),
       _client = ApiClient(
         client: client,
         timeout: const Duration(seconds: 30),
       );

  final PublicDomainCatalogDatabase _database;
  final ApiClient _client;
  final Uri? _manifestUri;

  static Uri? _defaultManifestUri() {
    const raw = String.fromEnvironment('GUTENBERG_CATALOG_MANIFEST_URL');
    if (raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw);
    return uri != null && uri.hasScheme ? uri : null;
  }

  Future<PublicDomainCatalogManifest?> fetchManifest() async {
    final uri = _manifestUri;
    if (uri == null) return null;
    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': ApiClient.userAgent,
      },
      timeout: const Duration(seconds: 15),
      maxRetries: 1,
    );
    if (response.statusCode != 200) {
      throw PublicDomainCatalogInstallException(
        'Catalogue manifest request failed (${response.statusCode})',
      );
    }
    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PublicDomainCatalogInstallException(
        'Catalogue manifest is invalid',
      );
    }
    return PublicDomainCatalogManifest.fromJson(decoded);
  }

  Future<void> installFromManifest(
    PublicDomainCatalogManifest manifest, {
    PublicDomainCatalogDownloadProgress? onProgress,
  }) async {
    if (manifest.schemaVersion != PublicDomainCatalogDatabase.schemaVersion) {
      throw const PublicDomainCatalogInstallException(
        'Catalogue schema is not supported',
      );
    }

    final targetPath = await _database.databasePath();
    final targetFile = File(targetPath);
    final dir = targetFile.parent;
    await dir.create(recursive: true);
    await cleanupTemporaryFiles();

    final downloadFile = File(
      p.join(dir.path, 'catalog_${manifest.catalogVersion}.download'),
    );
    final sqliteTempFile = File(
      p.join(dir.path, 'catalog_${manifest.catalogVersion}.sqlite.tmp'),
    );
    final backupFile = File(p.join(dir.path, 'catalog.sqlite.previous'));

    try {
      await _download(manifest, downloadFile, onProgress: onProgress);
      await _verifyChecksum(downloadFile, manifest.sha256);
      await _decodeArtifact(downloadFile, sqliteTempFile, manifest.downloadUrl);
      await _validateCandidate(sqliteTempFile, manifest);
      await _replaceAtomically(
        candidate: sqliteTempFile,
        target: targetFile,
        backup: backupFile,
      );
    } catch (_) {
      if (await sqliteTempFile.exists()) {
        await sqliteTempFile.delete();
      }
      rethrow;
    } finally {
      if (await downloadFile.exists()) {
        await downloadFile.delete();
      }
    }
  }

  Future<void> cleanupTemporaryFiles() async {
    final targetPath = await _database.databasePath();
    final dir = File(targetPath).parent;
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('.download') || name.endsWith('.sqlite.tmp')) {
        await entity.delete();
      }
    }
  }

  Future<void> _download(
    PublicDomainCatalogManifest manifest,
    File output, {
    PublicDomainCatalogDownloadProgress? onProgress,
  }) async {
    final request = http.Request('GET', manifest.downloadUrl);
    final response = await _client.send(
      request,
      headers: const {'User-Agent': ApiClient.userAgent},
    );
    if (response.statusCode != 200) {
      throw PublicDomainCatalogInstallException(
        'Catalogue download failed (${response.statusCode})',
      );
    }
    final sink = output.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, response.contentLength);
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> _verifyChecksum(File file, String expected) async {
    final digest = sha256.convert(await file.readAsBytes()).toString();
    if (digest.toLowerCase() != expected.toLowerCase()) {
      throw const PublicDomainCatalogInstallException(
        'Catalogue checksum did not match',
      );
    }
  }

  Future<void> _decodeArtifact(File input, File output, Uri downloadUrl) async {
    final bytes = await input.readAsBytes();
    final decoded = downloadUrl.path.toLowerCase().endsWith('.gz')
        ? gzip.decode(bytes)
        : bytes;
    await output.writeAsBytes(decoded, flush: true);
  }

  Future<void> _validateCandidate(
    File sqliteFile,
    PublicDomainCatalogManifest manifest,
  ) async {
    final candidate = PublicDomainCatalogDatabase(
      databaseFactory: _database.databaseFactoryForTesting,
      databasePath: sqliteFile.path,
      pageSize: _database.pageSize,
    );
    try {
      await candidate.open();
      final meta = await candidate.meta();
      final count = int.tryParse(meta['record_count'] ?? '');
      if (count != manifest.recordCount) {
        throw const PublicDomainCatalogInstallException(
          'Catalogue record count did not match manifest',
        );
      }
    } finally {
      await candidate.close();
    }
  }

  Future<void> _replaceAtomically({
    required File candidate,
    required File target,
    required File backup,
  }) async {
    await _database.close();
    if (await backup.exists()) {
      await backup.delete();
    }
    var movedTarget = false;
    if (await target.exists()) {
      await target.rename(backup.path);
      movedTarget = true;
    }
    try {
      await candidate.rename(target.path);
      if (await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (await target.exists()) {
        await target.delete();
      }
      if (movedTarget && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }
}

class PublicDomainCatalogInstallException implements Exception {
  final String message;

  const PublicDomainCatalogInstallException(this.message);

  @override
  String toString() => message;
}
