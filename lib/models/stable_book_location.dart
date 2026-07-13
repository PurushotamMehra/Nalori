import 'package:flutter/foundation.dart';

@immutable
class StableBookLocation {
  static const int currentVersion = 2;

  const StableBookLocation({
    required this.bookId,
    required this.spineIndex,
    required this.href,
    required this.sourceChecksum,
    this.version = currentVersion,
    this.internalSegmentId,
    this.localChunkIndex,
    this.textOffset = 0,
    this.anchorId,
    this.contextBefore,
    this.contextText,
    this.contextAfter,
    this.legacyGlobalChunkIndex,
    this.localDisplayIndex,
    this.readerLayoutFingerprint,
    this.previousSpineIndex,
    this.nextSpineIndex,
    this.publicationFingerprint,
    this.normalizedHref,
    this.sectionProgression,
    this.publicationProgression,
    this.sourceParserVersion,
  });

  final int version;
  final String bookId;
  final int spineIndex;
  final String href;
  final String sourceChecksum;
  final String? internalSegmentId;
  final int? localChunkIndex;
  final int textOffset;
  final String? anchorId;
  final String? contextBefore;
  final String? contextText;
  final String? contextAfter;
  final int? legacyGlobalChunkIndex;
  final int? localDisplayIndex;
  final String? readerLayoutFingerprint;
  final int? previousSpineIndex;
  final int? nextSpineIndex;
  final String? publicationFingerprint;
  final String? normalizedHref;
  final double? sectionProgression;
  final double? publicationProgression;
  final String? sourceParserVersion;

  bool get hasExactLocalTarget => localChunkIndex != null || anchorId != null;

  StableBookLocation copyWith({
    int? version,
    String? bookId,
    int? spineIndex,
    String? href,
    String? sourceChecksum,
    String? internalSegmentId,
    int? localChunkIndex,
    int? textOffset,
    String? anchorId,
    String? contextBefore,
    String? contextText,
    String? contextAfter,
    int? legacyGlobalChunkIndex,
    int? localDisplayIndex,
    String? readerLayoutFingerprint,
    int? previousSpineIndex,
    int? nextSpineIndex,
    String? publicationFingerprint,
    String? normalizedHref,
    double? sectionProgression,
    double? publicationProgression,
    String? sourceParserVersion,
  }) {
    return StableBookLocation(
      version: version ?? this.version,
      bookId: bookId ?? this.bookId,
      spineIndex: spineIndex ?? this.spineIndex,
      href: href ?? this.href,
      sourceChecksum: sourceChecksum ?? this.sourceChecksum,
      internalSegmentId: internalSegmentId ?? this.internalSegmentId,
      localChunkIndex: localChunkIndex ?? this.localChunkIndex,
      textOffset: textOffset ?? this.textOffset,
      anchorId: anchorId ?? this.anchorId,
      contextBefore: contextBefore ?? this.contextBefore,
      contextText: contextText ?? this.contextText,
      contextAfter: contextAfter ?? this.contextAfter,
      legacyGlobalChunkIndex:
          legacyGlobalChunkIndex ?? this.legacyGlobalChunkIndex,
      localDisplayIndex: localDisplayIndex ?? this.localDisplayIndex,
      readerLayoutFingerprint:
          readerLayoutFingerprint ?? this.readerLayoutFingerprint,
      previousSpineIndex: previousSpineIndex ?? this.previousSpineIndex,
      nextSpineIndex: nextSpineIndex ?? this.nextSpineIndex,
      publicationFingerprint:
          publicationFingerprint ?? this.publicationFingerprint,
      normalizedHref: normalizedHref ?? this.normalizedHref,
      sectionProgression: sectionProgression ?? this.sectionProgression,
      publicationProgression:
          publicationProgression ?? this.publicationProgression,
      sourceParserVersion: sourceParserVersion ?? this.sourceParserVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'v': version,
    'bookId': bookId,
    'spineIndex': spineIndex,
    'href': href,
    'sourceChecksum': sourceChecksum,
    if (internalSegmentId != null) 'internalSegmentId': internalSegmentId,
    if (localChunkIndex != null) 'localChunkIndex': localChunkIndex,
    'textOffset': textOffset,
    if (anchorId != null) 'anchorId': anchorId,
    if (contextBefore != null) 'contextBefore': contextBefore,
    if (contextText != null) 'contextText': contextText,
    if (contextAfter != null) 'contextAfter': contextAfter,
    if (legacyGlobalChunkIndex != null)
      'legacyGlobalChunkIndex': legacyGlobalChunkIndex,
    if (localDisplayIndex != null) 'localDisplayIndex': localDisplayIndex,
    if (readerLayoutFingerprint != null)
      'readerLayoutFingerprint': readerLayoutFingerprint,
    if (previousSpineIndex != null) 'previousSpineIndex': previousSpineIndex,
    if (nextSpineIndex != null) 'nextSpineIndex': nextSpineIndex,
    if (publicationFingerprint != null)
      'publicationFingerprint': publicationFingerprint,
    if (normalizedHref != null) 'normalizedHref': normalizedHref,
    if (sectionProgression != null) 'sectionProgression': sectionProgression,
    if (publicationProgression != null)
      'publicationProgression': publicationProgression,
    if (sourceParserVersion != null) 'sourceParserVersion': sourceParserVersion,
  };

  factory StableBookLocation.fromJson(Map<String, dynamic> json) {
    return StableBookLocation(
      version: (json['v'] as num?)?.toInt() ?? currentVersion,
      bookId: json['bookId'] as String,
      spineIndex: (json['spineIndex'] as num).toInt(),
      href: json['href'] as String,
      sourceChecksum: json['sourceChecksum'] as String? ?? 'unknown',
      internalSegmentId: json['internalSegmentId'] as String?,
      localChunkIndex: (json['localChunkIndex'] as num?)?.toInt(),
      textOffset: (json['textOffset'] as num?)?.toInt() ?? 0,
      anchorId: json['anchorId'] as String?,
      contextBefore: json['contextBefore'] as String?,
      contextText: json['contextText'] as String?,
      contextAfter: json['contextAfter'] as String?,
      legacyGlobalChunkIndex: (json['legacyGlobalChunkIndex'] as num?)?.toInt(),
      localDisplayIndex: (json['localDisplayIndex'] as num?)?.toInt(),
      readerLayoutFingerprint: json['readerLayoutFingerprint'] as String?,
      previousSpineIndex: (json['previousSpineIndex'] as num?)?.toInt(),
      nextSpineIndex: (json['nextSpineIndex'] as num?)?.toInt(),
      publicationFingerprint: json['publicationFingerprint'] as String?,
      normalizedHref: json['normalizedHref'] as String?,
      sectionProgression: (json['sectionProgression'] as num?)?.toDouble(),
      publicationProgression: (json['publicationProgression'] as num?)
          ?.toDouble(),
      sourceParserVersion: json['sourceParserVersion'] as String?,
    );
  }

  static StableBookLocation? maybeFromJson(Object? value) {
    if (value is Map<String, dynamic>) {
      return StableBookLocation.fromJson(value);
    }
    if (value is Map) {
      return StableBookLocation.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is StableBookLocation &&
        other.version == version &&
        other.bookId == bookId &&
        other.spineIndex == spineIndex &&
        other.href == href &&
        other.sourceChecksum == sourceChecksum &&
        other.internalSegmentId == internalSegmentId &&
        other.localChunkIndex == localChunkIndex &&
        other.textOffset == textOffset &&
        other.anchorId == anchorId &&
        other.contextBefore == contextBefore &&
        other.contextText == contextText &&
        other.contextAfter == contextAfter &&
        other.legacyGlobalChunkIndex == legacyGlobalChunkIndex &&
        other.localDisplayIndex == localDisplayIndex &&
        other.readerLayoutFingerprint == readerLayoutFingerprint &&
        other.previousSpineIndex == previousSpineIndex &&
        other.nextSpineIndex == nextSpineIndex &&
        other.publicationFingerprint == publicationFingerprint &&
        other.normalizedHref == normalizedHref &&
        other.sectionProgression == sectionProgression &&
        other.publicationProgression == publicationProgression &&
        other.sourceParserVersion == sourceParserVersion;
  }

  @override
  int get hashCode => Object.hashAll([
    version,
    bookId,
    spineIndex,
    href,
    sourceChecksum,
    internalSegmentId,
    localChunkIndex,
    textOffset,
    anchorId,
    contextBefore,
    contextText,
    contextAfter,
    legacyGlobalChunkIndex,
    localDisplayIndex,
    readerLayoutFingerprint,
    previousSpineIndex,
    nextSpineIndex,
    publicationFingerprint,
    normalizedHref,
    sectionProgression,
    publicationProgression,
    sourceParserVersion,
  ]);
}
