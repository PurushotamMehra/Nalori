import 'public_domain_book.dart';

enum PublicDomainCatalogSourceKind { starter, installed, cache, remote }

enum PublicDomainCatalogAvailability {
  starterOnly,
  fullInstalled,
  updating,
  downloadAvailable,
  updateFailed,
}

class PublicDomainCatalogCursor {
  final int offset;
  final String? remoteToken;

  const PublicDomainCatalogCursor({this.offset = 0, this.remoteToken});

  PublicDomainCatalogCursor next(int returnedCount) {
    return PublicDomainCatalogCursor(
      offset: offset + returnedCount,
      remoteToken: remoteToken,
    );
  }
}

class PublicDomainCatalogStatus {
  final PublicDomainCatalogAvailability availability;
  final String message;
  final bool isFallbackOnly;
  final bool isUpdateInProgress;
  final double? updateProgress;
  final Object? recoverableError;

  const PublicDomainCatalogStatus({
    required this.availability,
    required this.message,
    this.isFallbackOnly = false,
    this.isUpdateInProgress = false,
    this.updateProgress,
    this.recoverableError,
  });

  static const starterOnly = PublicDomainCatalogStatus(
    availability: PublicDomainCatalogAvailability.starterOnly,
    message: 'Showing limited saved book list',
    isFallbackOnly: true,
  );

  static const fullInstalled = PublicDomainCatalogStatus(
    availability: PublicDomainCatalogAvailability.fullInstalled,
    message: 'Local book list available',
  );
}

class PublicDomainCatalogPage {
  final List<PublicDomainBook> books;
  final int totalCount;
  final PublicDomainCatalogCursor cursor;
  final bool hasMoreLocal;
  final bool hasMoreCached;
  final bool hasMoreRemote;
  final PublicDomainCatalogSourceKind sourceKind;
  final PublicDomainCatalogStatus status;

  const PublicDomainCatalogPage({
    required this.books,
    required this.totalCount,
    required this.cursor,
    required this.sourceKind,
    required this.status,
    this.hasMoreLocal = false,
    this.hasMoreCached = false,
    this.hasMoreRemote = false,
  });

  bool get hasMore => hasMoreLocal || hasMoreCached || hasMoreRemote;

  PublicDomainBookPage toBookPage({required int page}) {
    return PublicDomainBookPage(
      books: books,
      count: totalCount,
      hasNextPage: hasMore,
      page: page,
      catalogStatusMessage: status.message,
      isFallbackOnly: status.isFallbackOnly,
    );
  }
}

class PublicDomainCatalogManifest {
  final int schemaVersion;
  final String catalogVersion;
  final DateTime generatedAt;
  final int recordCount;
  final int compressedSizeBytes;
  final int installedSizeBytes;
  final String sha256;
  final Uri downloadUrl;
  final int minimumAppCatalogVersion;

  const PublicDomainCatalogManifest({
    required this.schemaVersion,
    required this.catalogVersion,
    required this.generatedAt,
    required this.recordCount,
    required this.compressedSizeBytes,
    required this.installedSizeBytes,
    required this.sha256,
    required this.downloadUrl,
    this.minimumAppCatalogVersion = 1,
  });

  factory PublicDomainCatalogManifest.fromJson(Map<String, dynamic> json) {
    final downloadUrl = Uri.parse((json['download_url'] as String?) ?? '');
    if (!downloadUrl.hasScheme) {
      throw const FormatException('Manifest download_url must be absolute');
    }
    return PublicDomainCatalogManifest(
      schemaVersion: (json['schema_version'] as num).toInt(),
      catalogVersion: (json['catalog_version'] as String).trim(),
      generatedAt: DateTime.parse((json['generated_at'] as String).trim()),
      recordCount: (json['record_count'] as num).toInt(),
      compressedSizeBytes: (json['compressed_size_bytes'] as num).toInt(),
      installedSizeBytes: (json['installed_size_bytes'] as num).toInt(),
      sha256: (json['sha256'] as String).trim().toLowerCase(),
      downloadUrl: downloadUrl,
      minimumAppCatalogVersion:
          (json['minimum_app_catalog_version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'catalog_version': catalogVersion,
    'generated_at': generatedAt.toUtc().toIso8601String(),
    'record_count': recordCount,
    'compressed_size_bytes': compressedSizeBytes,
    'installed_size_bytes': installedSizeBytes,
    'sha256': sha256,
    'download_url': downloadUrl.toString(),
    'minimum_app_catalog_version': minimumAppCatalogVersion,
  };
}
