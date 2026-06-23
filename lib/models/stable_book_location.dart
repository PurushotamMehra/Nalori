import 'package:flutter/foundation.dart';

@immutable
class StableBookLocation {
  static const int currentVersion = 1;

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
        other.nextSpineIndex == nextSpineIndex;
  }

  @override
  int get hashCode => Object.hash(
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
  );
}
