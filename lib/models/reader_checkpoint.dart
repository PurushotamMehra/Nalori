import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'book_chunk.dart';
import 'stable_book_location.dart';

/// Bump this whenever card boundaries or source-range interpretation changes.
const String readerPaginationAlgorithmVersion = 'nalori_cards_v16_lists';

String readerSha256(Object value) {
  final bytes = value is Uint8List
      ? value
      : utf8.encode(value is String ? value : canonicalJsonEncode(value));
  return sha256.convert(bytes).toString();
}

String canonicalJsonEncode(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

@immutable
class ReaderCardSourceRange {
  const ReaderCardSourceRange({
    required this.sectionIdentity,
    required this.sectionChecksum,
    required this.logicalBlockId,
    required this.structuralType,
    required this.startUtf16,
    required this.endUtf16,
    this.contentChecksum,
    this.sourceIdentity,
    this.spineIdentity,
    this.structuralDigest,
    this.fragmentDigest,
    this.publisherLayoutDigest,
    this.richMetadataDigest,
    this.listFragmentDigest,
    this.splitBoundaryKind,
    this.isLogicalParagraphStart,
    this.isLogicalParagraphEnd,
    this.usesExplicitTextFragment,
    this.tableRowStart,
    this.tableRowEndExclusive,
    this.structuralOwnerRole,
  });

  final String sectionIdentity;
  final String sectionChecksum;
  final String logicalBlockId;
  final String structuralType;

  /// Half-open offsets relative to [logicalBlockId]. Structural content such
  /// as images and synthetic cards deliberately has no fabricated text range.
  final int? startUtf16;
  final int? endUtf16;
  final String? contentChecksum;

  /// Canonical physical-card ownership. These fields are absent only on
  /// historical/legacy identities. Canonical finalization supplies the whole
  /// set so a signature cannot collapse structurally different fragments that
  /// happen to expose the same visible text range.
  final String? sourceIdentity;
  final String? spineIdentity;
  final String? structuralDigest;
  final String? fragmentDigest;
  final String? publisherLayoutDigest;
  final String? richMetadataDigest;
  final String? listFragmentDigest;
  final String? splitBoundaryKind;
  final bool? isLogicalParagraphStart;
  final bool? isLogicalParagraphEnd;
  final bool? usesExplicitTextFragment;
  final int? tableRowStart;
  final int? tableRowEndExclusive;
  final String? structuralOwnerRole;

  bool get hasCanonicalStructuralOwnership => sourceIdentity != null;

  bool contains(ReaderSemanticAnchor anchor) {
    if (sectionIdentity != anchor.sectionIdentity ||
        sectionChecksum != anchor.sectionChecksum ||
        logicalBlockId != anchor.logicalBlockId ||
        structuralType != anchor.structuralType) {
      return false;
    }
    final start = startUtf16;
    final end = endUtf16;
    final offset = anchor.blockOffsetUtf16;
    if (start == null || end == null || offset == null) {
      return start == null && end == null && offset == null;
    }
    return offset >= start && offset < end;
  }

  Map<String, Object?> toJson() => {
    'sectionIdentity': sectionIdentity,
    'sectionChecksum': sectionChecksum,
    'logicalBlockId': logicalBlockId,
    'structuralType': structuralType,
    'startUtf16': startUtf16,
    'endUtf16': endUtf16,
    if (contentChecksum != null) 'contentChecksum': contentChecksum,
    if (sourceIdentity != null) 'sourceIdentity': sourceIdentity,
    if (spineIdentity != null) 'spineIdentity': spineIdentity,
    if (structuralDigest != null) 'structuralDigest': structuralDigest,
    if (fragmentDigest != null) 'fragmentDigest': fragmentDigest,
    if (publisherLayoutDigest != null)
      'publisherLayoutDigest': publisherLayoutDigest,
    if (richMetadataDigest != null) 'richMetadataDigest': richMetadataDigest,
    if (listFragmentDigest != null) 'listFragmentDigest': listFragmentDigest,
    if (splitBoundaryKind != null) 'splitBoundaryKind': splitBoundaryKind,
    if (isLogicalParagraphStart != null)
      'isLogicalParagraphStart': isLogicalParagraphStart,
    if (isLogicalParagraphEnd != null)
      'isLogicalParagraphEnd': isLogicalParagraphEnd,
    if (usesExplicitTextFragment != null)
      'usesExplicitTextFragment': usesExplicitTextFragment,
    if (tableRowStart != null) 'tableRowStart': tableRowStart,
    if (tableRowEndExclusive != null)
      'tableRowEndExclusive': tableRowEndExclusive,
    if (structuralOwnerRole != null) 'structuralOwnerRole': structuralOwnerRole,
  };

  factory ReaderCardSourceRange.fromJson(Map<String, Object?> json) {
    return ReaderCardSourceRange(
      sectionIdentity: json['sectionIdentity']! as String,
      sectionChecksum: json['sectionChecksum']! as String,
      logicalBlockId: json['logicalBlockId']! as String,
      structuralType: json['structuralType']! as String,
      startUtf16: (json['startUtf16'] as num?)?.toInt(),
      endUtf16: (json['endUtf16'] as num?)?.toInt(),
      contentChecksum: json['contentChecksum'] as String?,
      sourceIdentity: json['sourceIdentity'] as String?,
      spineIdentity: json['spineIdentity'] as String?,
      structuralDigest: json['structuralDigest'] as String?,
      fragmentDigest: json['fragmentDigest'] as String?,
      publisherLayoutDigest: json['publisherLayoutDigest'] as String?,
      richMetadataDigest: json['richMetadataDigest'] as String?,
      listFragmentDigest: json['listFragmentDigest'] as String?,
      splitBoundaryKind: json['splitBoundaryKind'] as String?,
      isLogicalParagraphStart: json['isLogicalParagraphStart'] as bool?,
      isLogicalParagraphEnd: json['isLogicalParagraphEnd'] as bool?,
      usesExplicitTextFragment: json['usesExplicitTextFragment'] as bool?,
      tableRowStart: (json['tableRowStart'] as num?)?.toInt(),
      tableRowEndExclusive: (json['tableRowEndExclusive'] as num?)?.toInt(),
      structuralOwnerRole: json['structuralOwnerRole'] as String?,
    );
  }
}

@immutable
class ReaderSemanticAnchor {
  const ReaderSemanticAnchor({
    required this.sectionIdentity,
    required this.sectionChecksum,
    required this.logicalBlockId,
    required this.structuralType,
    required this.blockOffsetUtf16,
    this.contextChecksum,
  });

  final String sectionIdentity;
  final String sectionChecksum;
  final String logicalBlockId;
  final String structuralType;
  final int? blockOffsetUtf16;
  final String? contextChecksum;

  Map<String, Object?> toJson() => {
    'sectionIdentity': sectionIdentity,
    'sectionChecksum': sectionChecksum,
    'logicalBlockId': logicalBlockId,
    'structuralType': structuralType,
    'blockOffsetUtf16': blockOffsetUtf16,
    if (contextChecksum != null) 'contextChecksum': contextChecksum,
  };

  factory ReaderSemanticAnchor.fromJson(Map<String, Object?> json) {
    return ReaderSemanticAnchor(
      sectionIdentity: json['sectionIdentity']! as String,
      sectionChecksum: json['sectionChecksum']! as String,
      logicalBlockId: json['logicalBlockId']! as String,
      structuralType: json['structuralType']! as String,
      blockOffsetUtf16: (json['blockOffsetUtf16'] as num?)?.toInt(),
      contextChecksum: json['contextChecksum'] as String?,
    );
  }
}

@immutable
class ReaderCardIdentity {
  const ReaderCardIdentity._({
    required this.publicationFingerprint,
    required this.layoutFingerprint,
    required this.paginationVersion,
    required this.ranges,
    required this.signature,
  });

  final String publicationFingerprint;
  final String layoutFingerprint;
  final String paginationVersion;
  final List<ReaderCardSourceRange> ranges;
  final String signature;

  factory ReaderCardIdentity({
    required String publicationFingerprint,
    required String layoutFingerprint,
    required List<ReaderCardSourceRange> ranges,
    String paginationVersion = readerPaginationAlgorithmVersion,
  }) {
    final immutableRanges = List<ReaderCardSourceRange>.unmodifiable(ranges);
    final signature = readerSha256({
      'publicationFingerprint': publicationFingerprint,
      'layoutFingerprint': layoutFingerprint,
      'paginationVersion': paginationVersion,
      'ranges': immutableRanges.map((range) => range.toJson()).toList(),
    });
    return ReaderCardIdentity._(
      publicationFingerprint: publicationFingerprint,
      layoutFingerprint: layoutFingerprint,
      paginationVersion: paginationVersion,
      ranges: immutableRanges,
      signature: signature,
    );
  }

  factory ReaderCardIdentity.fromCard({
    required String publicationFingerprint,
    required String layoutFingerprint,
    required BookChunk card,
    required List<BookChunk> sourceChunks,
    required List<int> sourceIndices,
    required Map<int, StableBookLocation> locationsBySourceIndex,
    Map<int, String> stableSourceKeys = const {},
    String paginationVersion = readerPaginationAlgorithmVersion,
  }) {
    final ranges = <ReaderCardSourceRange>[];
    // Pagination emits ranges in display order. Preserve that exact order;
    // re-sorting equal-offset structural ranges would make identity depend on
    // the sort implementation rather than on rendered source coverage.
    final ordered = card.effectiveSourceRanges.toList();
    for (final range in ordered) {
      if (range.originalChunkIndex < 0 ||
          range.originalChunkIndex >= sourceChunks.length) {
        continue;
      }
      final source = sourceChunks[range.originalChunkIndex];
      final location = locationsBySourceIndex[range.originalChunkIndex];
      final section = _sectionIdentity(location, source);
      final blockId =
          range.logicalParagraphId ??
          source.logicalParagraphId ??
          stableSourceKeys[range.originalChunkIndex] ??
          '$section#block:${location?.localChunkIndex ?? source.index}';
      final hasTextOffsets = source.type == BookChunkType.text;
      final start = hasTextOffsets
          ? range.paragraphStartOffset ??
                source.logicalParagraphStartOffset + range.originalStartOffset
          : null;
      final end = hasTextOffsets
          ? range.paragraphEndOffset ??
                source.logicalParagraphStartOffset + range.originalEndOffset
          : null;
      ranges.add(
        ReaderCardSourceRange(
          sectionIdentity: section,
          sectionChecksum: location?.sourceChecksum ?? 'unknown',
          logicalBlockId: blockId,
          structuralType: _structuralType(source),
          startUtf16: start,
          endUtf16: end,
          contentChecksum: source.type == BookChunkType.image
              ? readerSha256(source.imageBytes ?? Uint8List(0))
              : source.type == BookChunkType.milestone
              ? readerSha256(source.text ?? '')
              : null,
        ),
      );
    }

    if (ranges.isEmpty) {
      for (final sourceIndex in sourceIndices) {
        if (sourceIndex < 0 || sourceIndex >= sourceChunks.length) continue;
        final source = sourceChunks[sourceIndex];
        final location = locationsBySourceIndex[sourceIndex];
        final section = _sectionIdentity(location, source);
        ranges.add(
          ReaderCardSourceRange(
            sectionIdentity: section,
            sectionChecksum: location?.sourceChecksum ?? 'unknown',
            logicalBlockId:
                source.logicalParagraphId ??
                stableSourceKeys[sourceIndex] ??
                '$section#block:${location?.localChunkIndex ?? source.index}',
            structuralType: _structuralType(source),
            startUtf16: source.type == BookChunkType.text
                ? source.logicalParagraphStartOffset
                : null,
            endUtf16: source.type == BookChunkType.text
                ? source.logicalParagraphEndOffset ??
                      source.logicalParagraphStartOffset +
                          (source.text?.length ?? 0)
                : null,
            contentChecksum: source.type == BookChunkType.image
                ? readerSha256(source.imageBytes ?? Uint8List(0))
                : null,
          ),
        );
      }
    }

    if (ranges.isEmpty) {
      final text = card.text ?? '';
      ranges.add(
        ReaderCardSourceRange(
          sectionIdentity: 'synthetic',
          sectionChecksum: readerSha256(card.type.name),
          logicalBlockId: 'synthetic:${card.type.name}:${readerSha256(text)}',
          structuralType: 'synthetic:${card.type.name}',
          startUtf16: null,
          endUtf16: null,
          contentChecksum: readerSha256(text),
        ),
      );
    }

    return ReaderCardIdentity(
      publicationFingerprint: publicationFingerprint,
      layoutFingerprint: layoutFingerprint,
      paginationVersion: paginationVersion,
      ranges: ranges,
    );
  }

  ReaderSemanticAnchor firstMeaningfulAnchor({String? contextChecksum}) {
    final first = ranges.first;
    return ReaderSemanticAnchor(
      sectionIdentity: first.sectionIdentity,
      sectionChecksum: first.sectionChecksum,
      logicalBlockId: first.logicalBlockId,
      structuralType: first.structuralType,
      blockOffsetUtf16: first.startUtf16,
      contextChecksum: contextChecksum,
    );
  }

  bool containsAnchor(ReaderSemanticAnchor anchor) {
    return ranges.any((range) => range.contains(anchor));
  }

  Map<String, Object?> toJson() => {
    'publicationFingerprint': publicationFingerprint,
    'layoutFingerprint': layoutFingerprint,
    'paginationVersion': paginationVersion,
    'ranges': ranges.map((range) => range.toJson()).toList(),
    'signature': signature,
  };

  factory ReaderCardIdentity.fromJson(Map<String, Object?> json) {
    final identity = ReaderCardIdentity(
      publicationFingerprint: json['publicationFingerprint']! as String,
      layoutFingerprint: json['layoutFingerprint']! as String,
      paginationVersion: json['paginationVersion']! as String,
      ranges: (json['ranges']! as List)
          .map(
            (value) => ReaderCardSourceRange.fromJson(
              Map<String, Object?>.from(value as Map),
            ),
          )
          .toList(growable: false),
    );
    if (identity.signature != json['signature']) {
      throw const FormatException('Invalid reader card signature');
    }
    return identity;
  }

  static String _sectionIdentity(
    StableBookLocation? location,
    BookChunk source,
  ) {
    return location?.normalizedHref ??
        location?.href ??
        source.sourceFile ??
        'section:${source.section.name}';
  }

  static String _structuralType(BookChunk chunk) {
    return switch (chunk.type) {
      BookChunkType.image => 'image',
      BookChunkType.milestone => 'synthetic:milestone',
      BookChunkType.text when chunk.isHeading => 'heading',
      BookChunkType.text => chunk.blockRole.name,
    };
  }
}

enum ReaderCheckpointState {
  exactCommitted,
  layoutTransitionPending,
  semanticOnlyMigrated,
}

@immutable
class ReaderCheckpoint {
  static const int currentFormatVersion = 1;

  const ReaderCheckpoint({
    required this.bookId,
    required this.publicationFingerprint,
    required this.layoutFingerprint,
    required this.paginationVersion,
    required this.state,
    required this.sessionEpoch,
    required this.revision,
    required this.committedAtMillis,
    required this.navigationSource,
    required this.semanticAnchor,
    required this.integrityChecksum,
    this.formatVersion = currentFormatVersion,
    this.card,
    this.stableLocation,
    this.targetLayoutSettings,
  });

  final int formatVersion;
  final String bookId;
  final String publicationFingerprint;
  final ReaderCardIdentity? card;
  final ReaderSemanticAnchor semanticAnchor;
  final StableBookLocation? stableLocation;
  final String layoutFingerprint;
  final String paginationVersion;
  final ReaderCheckpointState state;
  final int sessionEpoch;
  final int revision;
  final int committedAtMillis;
  final String navigationSource;
  final Map<String, Object?>? targetLayoutSettings;
  final String integrityChecksum;

  factory ReaderCheckpoint.create({
    required String bookId,
    required String publicationFingerprint,
    required ReaderSemanticAnchor semanticAnchor,
    required String layoutFingerprint,
    required ReaderCheckpointState state,
    required int sessionEpoch,
    required int revision,
    required String navigationSource,
    ReaderCardIdentity? card,
    StableBookLocation? stableLocation,
    Map<String, Object?>? targetLayoutSettings,
    int? committedAtMillis,
    String paginationVersion = readerPaginationAlgorithmVersion,
  }) {
    final payload = <String, Object?>{
      'formatVersion': currentFormatVersion,
      'bookId': bookId,
      'publicationFingerprint': publicationFingerprint,
      if (card != null) 'card': card.toJson(),
      'semanticAnchor': semanticAnchor.toJson(),
      if (stableLocation != null)
        'stableLocation': sanitizeStableLocation(stableLocation).toJson(),
      'layoutFingerprint': layoutFingerprint,
      'paginationVersion': paginationVersion,
      'state': state.name,
      'sessionEpoch': sessionEpoch,
      'revision': revision,
      'committedAtMillis':
          committedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
      'navigationSource': navigationSource,
      if (targetLayoutSettings != null)
        'targetLayoutSettings': targetLayoutSettings,
    };
    return ReaderCheckpoint.fromPayload(
      payload,
      integrityChecksum: readerSha256(payload),
    );
  }

  factory ReaderCheckpoint.fromPayload(
    Map<String, Object?> payload, {
    required String integrityChecksum,
  }) {
    if (readerSha256(payload) != integrityChecksum) {
      throw const FormatException('Invalid checkpoint integrity checksum');
    }
    final version = (payload['formatVersion'] as num?)?.toInt();
    if (version != currentFormatVersion) {
      throw const FormatException('Unsupported reader checkpoint version');
    }
    final state = ReaderCheckpointState.values.firstWhere(
      (value) => value.name == payload['state'],
      orElse: () => throw const FormatException('Invalid checkpoint state'),
    );
    final rawCard = payload['card'];
    final checkpoint = ReaderCheckpoint(
      formatVersion: version!,
      bookId: payload['bookId']! as String,
      publicationFingerprint: payload['publicationFingerprint']! as String,
      card: rawCard is Map
          ? ReaderCardIdentity.fromJson(Map<String, Object?>.from(rawCard))
          : null,
      semanticAnchor: ReaderSemanticAnchor.fromJson(
        Map<String, Object?>.from(payload['semanticAnchor']! as Map),
      ),
      stableLocation: StableBookLocation.maybeFromJson(
        payload['stableLocation'],
      ),
      layoutFingerprint: payload['layoutFingerprint']! as String,
      paginationVersion: payload['paginationVersion']! as String,
      state: state,
      sessionEpoch: (payload['sessionEpoch']! as num).toInt(),
      revision: (payload['revision']! as num).toInt(),
      committedAtMillis: (payload['committedAtMillis']! as num).toInt(),
      navigationSource: payload['navigationSource']! as String,
      targetLayoutSettings: payload['targetLayoutSettings'] is Map
          ? Map<String, Object?>.from(payload['targetLayoutSettings']! as Map)
          : null,
      integrityChecksum: integrityChecksum,
    );
    if (!checkpoint.isValid) {
      throw const FormatException('Incomplete reader checkpoint');
    }
    return checkpoint;
  }

  bool get isValid {
    if (bookId.isEmpty ||
        publicationFingerprint.isEmpty ||
        layoutFingerprint.isEmpty ||
        paginationVersion.isEmpty ||
        semanticAnchor.sectionIdentity.isEmpty ||
        semanticAnchor.sectionChecksum.isEmpty ||
        semanticAnchor.logicalBlockId.isEmpty ||
        semanticAnchor.structuralType.isEmpty ||
        sessionEpoch <= 0 ||
        revision <= 0) {
      return false;
    }
    if (state == ReaderCheckpointState.exactCommitted) {
      return card != null &&
          card!.signature.isNotEmpty &&
          card!.layoutFingerprint == layoutFingerprint &&
          card!.publicationFingerprint == publicationFingerprint;
    }
    if (state == ReaderCheckpointState.layoutTransitionPending) {
      return targetLayoutSettings?.isNotEmpty == true;
    }
    return true;
  }

  Map<String, Object?> payloadJson() => {
    'formatVersion': formatVersion,
    'bookId': bookId,
    'publicationFingerprint': publicationFingerprint,
    if (card != null) 'card': card!.toJson(),
    'semanticAnchor': semanticAnchor.toJson(),
    if (stableLocation != null) 'stableLocation': stableLocation!.toJson(),
    'layoutFingerprint': layoutFingerprint,
    'paginationVersion': paginationVersion,
    'state': state.name,
    'sessionEpoch': sessionEpoch,
    'revision': revision,
    'committedAtMillis': committedAtMillis,
    'navigationSource': navigationSource,
    if (targetLayoutSettings != null)
      'targetLayoutSettings': targetLayoutSettings,
  };

  static StableBookLocation sanitizeStableLocation(
    StableBookLocation location,
  ) {
    return StableBookLocation(
      version: location.version,
      bookId: location.bookId,
      spineIndex: location.spineIndex,
      href: location.href,
      sourceChecksum: location.sourceChecksum,
      internalSegmentId: location.internalSegmentId,
      localChunkIndex: location.localChunkIndex,
      textOffset: location.textOffset,
      anchorId: location.anchorId,
      legacyGlobalChunkIndex: location.legacyGlobalChunkIndex,
      readerLayoutFingerprint: location.readerLayoutFingerprint,
      previousSpineIndex: location.previousSpineIndex,
      nextSpineIndex: location.nextSpineIndex,
      publicationFingerprint: location.publicationFingerprint,
      normalizedHref: location.normalizedHref,
      sectionProgression: location.sectionProgression,
      publicationProgression: location.publicationProgression,
      sourceParserVersion: location.sourceParserVersion,
    );
  }
}
