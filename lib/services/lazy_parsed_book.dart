import 'package:flutter/foundation.dart';

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import '../models/stable_book_location.dart';
import 'lazy_epub_index_service.dart';

const int lazyParsedSectionCacheFormatVersion = 2;
const String lazyParsedSectionParserVersion = 'section_v2';
const int lazyParsedSectionDependencySchemaVersion = 1;

typedef StableContentAnchor = StableBookLocation;

@immutable
class LazySectionIdentity {
  const LazySectionIdentity({
    required this.bookId,
    required this.publicationFingerprint,
    required this.spineIndex,
    required this.href,
    required this.normalizedHref,
    required this.fullPath,
    required this.sourceChecksum,
    required this.parserVersion,
    required this.dependencySignature,
    required this.dependencySchemaVersion,
  });

  factory LazySectionIdentity.fromIndexItem({
    required String bookId,
    required String publicationFingerprint,
    required LazyEpubSpineItem item,
    required String sourceChecksum,
    required String dependencySignature,
    String parserVersion = lazyParsedSectionParserVersion,
    int dependencySchemaVersion = lazyParsedSectionDependencySchemaVersion,
  }) {
    return LazySectionIdentity(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      spineIndex: item.index,
      href: item.href,
      normalizedHref: item.normalizedHref,
      fullPath: item.fullPath,
      sourceChecksum: sourceChecksum,
      parserVersion: parserVersion,
      dependencySignature: dependencySignature,
      dependencySchemaVersion: dependencySchemaVersion,
    );
  }

  final String bookId;
  final String publicationFingerprint;
  final int spineIndex;
  final String href;
  final String normalizedHref;
  final String fullPath;
  final String sourceChecksum;
  final String parserVersion;
  final String dependencySignature;
  final int dependencySchemaVersion;

  String get stableKey => [
    bookId,
    publicationFingerprint,
    spineIndex,
    normalizedHref,
    fullPath,
    sourceChecksum,
    parserVersion,
    dependencySchemaVersion,
    dependencySignature,
  ].join('|');

  String get cacheKey => [
    spineIndex,
    _safePart(normalizedHref),
    _checksumPrefix(sourceChecksum),
    _checksumPrefix(publicationFingerprint),
    _checksumPrefix(dependencySignature),
  ].join('_');

  Map<String, dynamic> toJson() => {
    'bookId': bookId,
    'publicationFingerprint': publicationFingerprint,
    'spineIndex': spineIndex,
    'href': href,
    'normalizedHref': normalizedHref,
    'fullPath': fullPath,
    'sourceChecksum': sourceChecksum,
    'parserVersion': parserVersion,
    'dependencySignature': dependencySignature,
    'dependencySchemaVersion': dependencySchemaVersion,
  };

  factory LazySectionIdentity.fromJson(Map<String, dynamic> json) {
    return LazySectionIdentity(
      bookId: json['bookId'] as String,
      publicationFingerprint: json['publicationFingerprint'] as String,
      spineIndex: json['spineIndex'] as int,
      href: json['href'] as String,
      normalizedHref: json['normalizedHref'] as String,
      fullPath: json['fullPath'] as String,
      sourceChecksum: json['sourceChecksum'] as String,
      parserVersion: json['parserVersion'] as String,
      dependencySignature: json['dependencySignature'] as String,
      dependencySchemaVersion: json['dependencySchemaVersion'] as int,
    );
  }
}

enum SectionParseStatus { notLoaded, queued, parsing, ready, failed, stale }

@immutable
class LazyBookSectionDescriptor {
  const LazyBookSectionDescriptor({
    required this.identity,
    required this.mediaType,
    required this.sizeBytes,
    this.status = SectionParseStatus.notLoaded,
    this.cachePath,
    this.lastAccessedMs,
    this.error,
  });

  final LazySectionIdentity identity;
  final String mediaType;
  final int? sizeBytes;
  final SectionParseStatus status;
  final String? cachePath;
  final int? lastAccessedMs;
  final String? error;

  LazyBookSectionDescriptor copyWith({
    SectionParseStatus? status,
    String? cachePath,
    int? lastAccessedMs,
    String? error,
  }) {
    return LazyBookSectionDescriptor(
      identity: identity,
      mediaType: mediaType,
      sizeBytes: sizeBytes,
      status: status ?? this.status,
      cachePath: cachePath ?? this.cachePath,
      lastAccessedMs: lastAccessedMs ?? this.lastAccessedMs,
      error: error,
    );
  }
}

@immutable
class ParsedSection {
  const ParsedSection({
    required this.identity,
    required this.chunks,
    required this.anchorMap,
    required this.chapters,
    required this.wordCount,
    required this.textCharCount,
    required this.resourceHrefs,
    required this.parserVersion,
  });

  final LazySectionIdentity identity;
  final List<BookChunk> chunks;
  final Map<String, int> anchorMap;
  final List<ChapterInfo> chapters;
  final int wordCount;
  final int textCharCount;
  final List<String> resourceHrefs;
  final String parserVersion;

  Map<String, dynamic> toJson() => {
    'version': lazyParsedSectionCacheFormatVersion,
    'identity': identity.toJson(),
    'chunks': chunks.map((chunk) => chunk.toJson()).toList(),
    'anchors': anchorMap,
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'wordCount': wordCount,
    'textCharCount': textCharCount,
    'resourceHrefs': resourceHrefs,
    'parserVersion': parserVersion,
  };

  factory ParsedSection.fromJson(Map<String, dynamic> json) {
    if (json['version'] != lazyParsedSectionCacheFormatVersion) {
      throw const FormatException('Unsupported parsed section cache version');
    }
    return ParsedSection(
      identity: LazySectionIdentity.fromJson(
        json['identity'] as Map<String, dynamic>,
      ),
      chunks: (json['chunks'] as List<dynamic>)
          .map((entry) => BookChunk.fromJson(entry as Map<String, dynamic>))
          .toList(),
      anchorMap: (json['anchors'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as int),
      ),
      chapters: (json['chapters'] as List<dynamic>)
          .map((entry) => ChapterInfo.fromJson(entry as Map<String, dynamic>))
          .toList(),
      wordCount: json['wordCount'] as int,
      textCharCount: json['textCharCount'] as int,
      resourceHrefs:
          (json['resourceHrefs'] as List<dynamic>?)?.cast<String>() ?? const [],
      parserVersion: json['parserVersion'] as String,
    );
  }
}

@immutable
class LazyParsedBook {
  const LazyParsedBook({
    required this.bookId,
    required this.title,
    required this.author,
    required this.sections,
    required this.chapters,
  });

  factory LazyParsedBook.fromIndex(LazyEpubIndex index) {
    return LazyParsedBook(
      bookId: index.bookId,
      title: index.title,
      author: index.author,
      sections: index.spine
          .map(
            (item) => LazyBookSectionDescriptor(
              identity: LazySectionIdentity.fromIndexItem(
                bookId: index.bookId,
                publicationFingerprint: index.publicationFingerprint,
                item: item,
                sourceChecksum: item.sourceChecksum,
                dependencySignature: lazySectionDependencySignature(index),
              ),
              mediaType: item.mediaType,
              sizeBytes: item.sizeBytes,
            ),
          )
          .toList(growable: false),
      chapters: index.chapters,
    );
  }

  final String bookId;
  final String title;
  final String author;
  final List<LazyBookSectionDescriptor> sections;
  final List<LazyEpubChapter> chapters;
}

String lazySectionDependencySignature(LazyEpubIndex index) {
  final manifestSignature =
      index.manifest.values
          .map(
            (item) =>
                '${item.normalizedHref}:${item.mediaType}:${item.sizeBytes ?? -1}',
          )
          .toList(growable: false)
        ..sort();
  final value = [
    'dependency_schema_$lazyParsedSectionDependencySchemaVersion',
    index.publicationFingerprint,
    ...manifestSignature,
  ].join('|');
  return fnv1aHex(Uint8List.fromList(value.codeUnits));
}

String fnv1aHex(Uint8List bytes) {
  const int fnvOffset = 0x811c9dc5;
  const int fnvPrime = 0x01000193;
  var hash = fnvOffset;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * fnvPrime) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _safePart(String input) {
  final safe = input.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return safe.length <= 80 ? safe : safe.substring(0, 80);
}

String _checksumPrefix(String checksum) {
  if (checksum.length <= 12) return checksum;
  return checksum.substring(0, 12);
}
