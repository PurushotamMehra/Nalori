import 'package:flutter/foundation.dart';

import 'book_chunk.dart';
import 'stable_book_location.dart';

@immutable
final class DerivedParagraphSourceSegment {
  const DerivedParagraphSourceSegment({
    required this.localChunkIndex,
    required this.paragraphStart,
    required this.paragraphEnd,
    required this.chunkStart,
  });

  final int localChunkIndex;
  final int paragraphStart;
  final int paragraphEnd;
  final int chunkStart;

  Map<String, dynamic> toJson() => {
    'chunk': localChunkIndex,
    'paragraphStart': paragraphStart,
    'paragraphEnd': paragraphEnd,
    'chunkStart': chunkStart,
  };

  factory DerivedParagraphSourceSegment.fromJson(Map<String, dynamic> json) {
    return DerivedParagraphSourceSegment(
      localChunkIndex: (json['chunk'] as num).toInt(),
      paragraphStart: (json['paragraphStart'] as num).toInt(),
      paragraphEnd: (json['paragraphEnd'] as num).toInt(),
      chunkStart: (json['chunkStart'] as num).toInt(),
    );
  }
}

@immutable
final class DerivedIndexedParagraph {
  const DerivedIndexedParagraph({
    required this.logicalParagraphId,
    required this.text,
    required this.normalizedText,
    required this.normalizedSourceStarts,
    required this.normalizedSourceEnds,
    required this.checksum,
    required this.contextBefore,
    required this.contextAfter,
    required this.sourceSegments,
    required this.section,
    required this.isHeading,
  });

  final String logicalParagraphId;
  final String text;
  final String normalizedText;
  final List<int> normalizedSourceStarts;
  final List<int> normalizedSourceEnds;
  final String checksum;
  final String contextBefore;
  final String contextAfter;
  final List<DerivedParagraphSourceSegment> sourceSegments;
  final ChunkSection section;
  final bool isHeading;

  Map<String, dynamic> toJson() => {
    'id': logicalParagraphId,
    'text': text,
    'normalized': normalizedText,
    'starts': normalizedSourceStarts,
    'ends': normalizedSourceEnds,
    'checksum': checksum,
    'before': contextBefore,
    'after': contextAfter,
    'segments': sourceSegments.map((item) => item.toJson()).toList(),
    'section': section.name,
    'heading': isHeading,
  };

  factory DerivedIndexedParagraph.fromJson(Map<String, dynamic> json) {
    return DerivedIndexedParagraph(
      logicalParagraphId: json['id'] as String,
      text: json['text'] as String,
      normalizedText: json['normalized'] as String,
      normalizedSourceStarts: (json['starts'] as List).cast<int>(),
      normalizedSourceEnds: (json['ends'] as List).cast<int>(),
      checksum: json['checksum'] as String,
      contextBefore: json['before'] as String? ?? '',
      contextAfter: json['after'] as String? ?? '',
      sourceSegments: (json['segments'] as List)
          .map(
            (item) => DerivedParagraphSourceSegment.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      section: ChunkSection.values.firstWhere(
        (value) => value.name == (json['section'] as String? ?? 'content'),
        orElse: () => ChunkSection.content,
      ),
      isHeading: json['heading'] as bool? ?? false,
    );
  }
}

@immutable
final class DerivedIndexSegment {
  const DerivedIndexSegment({
    required this.schemaVersion,
    required this.normalizationVersion,
    required this.bookId,
    required this.publicationFingerprint,
    required this.spineIndex,
    required this.href,
    required this.normalizedHref,
    required this.sourceChecksum,
    required this.parserVersion,
    required this.paragraphs,
  });

  final int schemaVersion;
  final int normalizationVersion;
  final String bookId;
  final String publicationFingerprint;
  final int spineIndex;
  final String href;
  final String normalizedHref;
  final String sourceChecksum;
  final String parserVersion;
  final List<DerivedIndexedParagraph> paragraphs;

  Map<String, dynamic> toJson() => {
    'schema': schemaVersion,
    'normalization': normalizationVersion,
    'bookId': bookId,
    'fingerprint': publicationFingerprint,
    'spine': spineIndex,
    'href': href,
    'normalizedHref': normalizedHref,
    'sourceChecksum': sourceChecksum,
    'parserVersion': parserVersion,
    'paragraphs': paragraphs.map((item) => item.toJson()).toList(),
  };

  factory DerivedIndexSegment.fromJson(Map<String, dynamic> json) {
    return DerivedIndexSegment(
      schemaVersion: (json['schema'] as num).toInt(),
      normalizationVersion: (json['normalization'] as num).toInt(),
      bookId: json['bookId'] as String,
      publicationFingerprint: json['fingerprint'] as String,
      spineIndex: (json['spine'] as num).toInt(),
      href: json['href'] as String,
      normalizedHref: json['normalizedHref'] as String,
      sourceChecksum: json['sourceChecksum'] as String,
      parserVersion: json['parserVersion'] as String,
      paragraphs: (json['paragraphs'] as List)
          .map(
            (item) => DerivedIndexedParagraph.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

@immutable
final class DerivedIndexSegmentRecord {
  const DerivedIndexSegmentRecord({
    required this.spineIndex,
    required this.href,
    required this.sourceChecksum,
    required this.fileName,
    required this.fileChecksum,
    required this.fileSizeBytes,
    required this.paragraphCount,
    required this.generation,
  });

  final int spineIndex;
  final String href;
  final String sourceChecksum;
  final String fileName;
  final String fileChecksum;
  final int fileSizeBytes;
  final int paragraphCount;
  final int generation;

  Map<String, dynamic> toJson() => {
    'spine': spineIndex,
    'href': href,
    'sourceChecksum': sourceChecksum,
    'file': fileName,
    'checksum': fileChecksum,
    'bytes': fileSizeBytes,
    'paragraphs': paragraphCount,
    'generation': generation,
  };

  factory DerivedIndexSegmentRecord.fromJson(Map<String, dynamic> json) {
    return DerivedIndexSegmentRecord(
      spineIndex: (json['spine'] as num).toInt(),
      href: json['href'] as String,
      sourceChecksum: json['sourceChecksum'] as String,
      fileName: json['file'] as String,
      fileChecksum: json['checksum'] as String,
      fileSizeBytes: (json['bytes'] as num).toInt(),
      paragraphCount: (json['paragraphs'] as num).toInt(),
      generation: (json['generation'] as num).toInt(),
    );
  }
}

@immutable
final class DerivedIndexManifest {
  const DerivedIndexManifest({
    required this.schemaVersion,
    required this.normalizationVersion,
    required this.bookId,
    required this.publicationFingerprint,
    required this.parserVersion,
    required this.generation,
    required this.totalSections,
    required this.records,
    required this.complete,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.lastAccessedAtMs,
  });

  final int schemaVersion;
  final int normalizationVersion;
  final String bookId;
  final String publicationFingerprint;
  final String parserVersion;
  final int generation;
  final int totalSections;
  final List<DerivedIndexSegmentRecord> records;
  final bool complete;
  final int createdAtMs;
  final int updatedAtMs;
  final int lastAccessedAtMs;

  Set<int> get indexedSpineIndexes =>
      records.map((record) => record.spineIndex).toSet();

  double get coverage =>
      totalSections <= 0 ? 1 : (records.length / totalSections).clamp(0.0, 1.0);

  DerivedIndexManifest copyWith({
    List<DerivedIndexSegmentRecord>? records,
    bool? complete,
    int? updatedAtMs,
    int? lastAccessedAtMs,
  }) {
    return DerivedIndexManifest(
      schemaVersion: schemaVersion,
      normalizationVersion: normalizationVersion,
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      parserVersion: parserVersion,
      generation: generation,
      totalSections: totalSections,
      records: records ?? this.records,
      complete: complete ?? this.complete,
      createdAtMs: createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      lastAccessedAtMs: lastAccessedAtMs ?? this.lastAccessedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema': schemaVersion,
    'normalization': normalizationVersion,
    'bookId': bookId,
    'fingerprint': publicationFingerprint,
    'parserVersion': parserVersion,
    'generation': generation,
    'totalSections': totalSections,
    'records': records.map((record) => record.toJson()).toList(),
    'complete': complete,
    'createdAtMs': createdAtMs,
    'updatedAtMs': updatedAtMs,
    'lastAccessedAtMs': lastAccessedAtMs,
  };

  factory DerivedIndexManifest.fromJson(Map<String, dynamic> json) {
    return DerivedIndexManifest(
      schemaVersion: (json['schema'] as num).toInt(),
      normalizationVersion: (json['normalization'] as num).toInt(),
      bookId: json['bookId'] as String,
      publicationFingerprint: json['fingerprint'] as String,
      parserVersion: json['parserVersion'] as String,
      generation: (json['generation'] as num).toInt(),
      totalSections: (json['totalSections'] as num).toInt(),
      records: (json['records'] as List)
          .map(
            (item) => DerivedIndexSegmentRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      complete: json['complete'] as bool? ?? false,
      createdAtMs: (json['createdAtMs'] as num).toInt(),
      updatedAtMs: (json['updatedAtMs'] as num).toInt(),
      lastAccessedAtMs:
          (json['lastAccessedAtMs'] as num?)?.toInt() ??
          (json['updatedAtMs'] as num).toInt(),
    );
  }
}

@immutable
final class DerivedIndexSnapshot {
  const DerivedIndexSnapshot({required this.manifest, required this.segments});

  final DerivedIndexManifest manifest;
  final Map<int, DerivedIndexSegment> segments;

  double get coverage => manifest.coverage;
  bool get isComplete => manifest.complete;
}

@immutable
final class DerivedSourceRange {
  const DerivedSourceRange({
    required this.indexGeneration,
    required this.location,
    required this.logicalParagraphId,
    required this.paragraphChecksum,
    required this.paragraphStart,
    required this.paragraphEnd,
    required this.matchText,
  });

  final int indexGeneration;
  final StableBookLocation location;
  final String logicalParagraphId;
  final String paragraphChecksum;
  final int paragraphStart;
  final int paragraphEnd;
  final String matchText;

  String get stableKey => [
    location.bookId,
    location.publicationFingerprint,
    location.normalizedHref ?? location.href,
    logicalParagraphId,
    paragraphStart,
    paragraphEnd,
  ].join('|');

  Map<String, dynamic> toJson() => {
    'generation': indexGeneration,
    'location': location.toJson(),
    'paragraphId': logicalParagraphId,
    'paragraphChecksum': paragraphChecksum,
    'start': paragraphStart,
    'end': paragraphEnd,
    'text': matchText,
  };

  factory DerivedSourceRange.fromJson(Map<String, dynamic> json) {
    return DerivedSourceRange(
      indexGeneration: (json['generation'] as num).toInt(),
      location: StableBookLocation.fromJson(
        Map<String, dynamic>.from(json['location'] as Map),
      ),
      logicalParagraphId: json['paragraphId'] as String,
      paragraphChecksum: json['paragraphChecksum'] as String,
      paragraphStart: (json['start'] as num).toInt(),
      paragraphEnd: (json['end'] as num).toInt(),
      matchText: json['text'] as String? ?? '',
    );
  }
}

@immutable
final class DerivedSearchResult {
  const DerivedSearchResult({
    required this.range,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
    required this.rank,
  });

  final DerivedSourceRange range;
  final String snippet;
  final int matchStart;
  final int matchEnd;
  final int rank;
}
