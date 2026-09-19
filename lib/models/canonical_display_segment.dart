import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'canonical_pagination.dart';
import 'reader_checkpoint.dart';
import 'reader_compatibility.dart';
import 'reader_layout_contract.dart';
import '../utils/reader_content_parser.dart';

/// Logical-only P06 segment evidence. This model is deliberately not wired to
/// the legacy display-cache payloads or a deployed cache-file version.
const String canonicalDisplaySegmentRecordKind = 'canonical_display_segment';
const String canonicalDisplaySegmentSemanticRevision =
    'canonical_display_segment_contract_v1';
const String canonicalDisplaySegmentEncodingMarker =
    'canonical_display_segment_tlv_v1';
const String canonicalDisplaySegmentChecksumCoverageRevision =
    'canonical_display_segment_checksum_v1';

enum CanonicalDisplaySegmentBoundaryRole {
  bookStartAnchored,
  continuationAnchored,
  interior,
  logicalEndAnchored,
}

enum CanonicalDisplaySegmentLeftBoundaryKind { bookStart, predecessor, restart }

enum CanonicalDisplaySegmentRightBoundaryKind {
  logicalEnd,
  successor,
  frontier,
}

/// Explicit caller-owned ceilings for decode/allocation. P06-006 owns release
/// budgets; this logical codec has no default limits.
@immutable
final class CanonicalDisplaySegmentCodecLimits {
  const CanonicalDisplaySegmentCodecLimits({
    required this.maxEncodedBytes,
    required this.maxDecodedBytes,
    required this.maxFieldBytes,
    required this.maxCards,
    required this.maxSourceSlices,
    required this.maxBlockLayouts,
    required this.maxContinuationBytes,
    required this.maxManifestSegments,
    required this.maxContinuationChainOrdinal,
  }) : assert(maxEncodedBytes > 0),
       assert(maxDecodedBytes > 0),
       assert(maxFieldBytes > 0),
       assert(maxCards > 0),
       assert(maxSourceSlices > 0),
       assert(maxBlockLayouts > 0),
       assert(maxContinuationBytes > 0),
       assert(maxManifestSegments > 0),
       assert(maxContinuationChainOrdinal >= 0);

  final int maxEncodedBytes;
  final int maxDecodedBytes;
  final int maxFieldBytes;
  final int maxCards;
  final int maxSourceSlices;
  final int maxBlockLayouts;
  final int maxContinuationBytes;
  final int maxManifestSegments;
  final int maxContinuationChainOrdinal;
}

@immutable
final class CanonicalDisplaySegmentKey {
  CanonicalDisplaySegmentKey({
    required this.bookStorageScopeDigest,
    required this.publicationFingerprint,
    required this.sourceCompatibilityFingerprint,
    required this.layoutMetricsFingerprint,
    required this.rendererLayoutFingerprint,
    required this.paginationAlgorithmFingerprint,
    required this.compatibilityClassifierRevision,
    required this.readerCompatibilityFingerprint,
    required this.stableStartCursor,
    required this.stableEndCursor,
    required this.boundaryRole,
    this.recordKind = canonicalDisplaySegmentRecordKind,
    this.semanticRevision = canonicalDisplaySegmentSemanticRevision,
  }) : _canonicalBytes = _encode(
         recordKind: recordKind,
         semanticRevision: semanticRevision,
         bookStorageScopeDigest: bookStorageScopeDigest,
         publicationFingerprint: publicationFingerprint,
         sourceCompatibilityFingerprint: sourceCompatibilityFingerprint,
         layoutMetricsFingerprint: layoutMetricsFingerprint,
         rendererLayoutFingerprint: rendererLayoutFingerprint,
         paginationAlgorithmFingerprint: paginationAlgorithmFingerprint,
         compatibilityClassifierRevision: compatibilityClassifierRevision,
         readerCompatibilityFingerprint: readerCompatibilityFingerprint,
         stableStartCursor: stableStartCursor,
         stableEndCursor: stableEndCursor,
         boundaryRole: boundaryRole,
       ) {
    _validateFingerprint(bookStorageScopeDigest, 'book storage scope');
    _validateFingerprint(sourceCompatibilityFingerprint, 'F202');
    _validateFingerprint(layoutMetricsFingerprint, 'F196');
    _validateFingerprint(rendererLayoutFingerprint, 'F206');
    _validateFingerprint(paginationAlgorithmFingerprint, 'F204');
    _validateFingerprint(readerCompatibilityFingerprint, 'F208');
    if (recordKind != canonicalDisplaySegmentRecordKind ||
        semanticRevision != canonicalDisplaySegmentSemanticRevision ||
        publicationFingerprint.isEmpty ||
        compatibilityClassifierRevision.isEmpty) {
      throw ArgumentError('Canonical display key identity is incomplete.');
    }
  }

  final String recordKind;
  final String semanticRevision;
  final String bookStorageScopeDigest;
  final String publicationFingerprint;
  final String sourceCompatibilityFingerprint;
  final String layoutMetricsFingerprint;
  final String rendererLayoutFingerprint;
  final String paginationAlgorithmFingerprint;
  final String compatibilityClassifierRevision;
  final String readerCompatibilityFingerprint;
  final CanonicalPaginationCursor stableStartCursor;
  final CanonicalPaginationCursor stableEndCursor;
  final CanonicalDisplaySegmentBoundaryRole boundaryRole;
  final Uint8List _canonicalBytes;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);
  String get digest => readerSha256(_canonicalBytes);

  static Uint8List _encode({
    required String recordKind,
    required String semanticRevision,
    required String bookStorageScopeDigest,
    required String publicationFingerprint,
    required String sourceCompatibilityFingerprint,
    required String layoutMetricsFingerprint,
    required String rendererLayoutFingerprint,
    required String paginationAlgorithmFingerprint,
    required String compatibilityClassifierRevision,
    required String readerCompatibilityFingerprint,
    required CanonicalPaginationCursor stableStartCursor,
    required CanonicalPaginationCursor stableEndCursor,
    required CanonicalDisplaySegmentBoundaryRole boundaryRole,
  }) {
    final writer = _CanonicalSegmentWriter();
    writer.stringField(1, recordKind);
    writer.stringField(2, semanticRevision);
    writer.stringField(3, bookStorageScopeDigest);
    writer.stringField(4, publicationFingerprint);
    writer.stringField(5, sourceCompatibilityFingerprint);
    writer.stringField(6, layoutMetricsFingerprint);
    writer.stringField(7, rendererLayoutFingerprint);
    writer.stringField(8, paginationAlgorithmFingerprint);
    writer.stringField(9, compatibilityClassifierRevision);
    writer.stringField(10, readerCompatibilityFingerprint);
    writer.recordField(11, _encodeCursor(stableStartCursor));
    writer.recordField(12, _encodeCursor(stableEndCursor));
    writer.stringField(13, boundaryRole.name);
    return writer.takeBytes();
  }

  static CanonicalDisplaySegmentKey decode(
    Uint8List bytes, {
    required CanonicalDisplaySegmentCodecLimits limits,
  }) {
    final fields = _CanonicalSegmentReader(
      bytes,
      limits,
    ).readFields(const <int>{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13});
    final key = CanonicalDisplaySegmentKey(
      recordKind: fields.stringAt(1),
      semanticRevision: fields.stringAt(2),
      bookStorageScopeDigest: fields.stringAt(3),
      publicationFingerprint: fields.stringAt(4),
      sourceCompatibilityFingerprint: fields.stringAt(5),
      layoutMetricsFingerprint: fields.stringAt(6),
      rendererLayoutFingerprint: fields.stringAt(7),
      paginationAlgorithmFingerprint: fields.stringAt(8),
      compatibilityClassifierRevision: fields.stringAt(9),
      readerCompatibilityFingerprint: fields.stringAt(10),
      stableStartCursor: _decodeCursor(fields.recordAt(11), limits),
      stableEndCursor: _decodeCursor(fields.recordAt(12), limits),
      boundaryRole: _enumByName(
        CanonicalDisplaySegmentBoundaryRole.values,
        fields.stringAt(13),
        'boundary role',
      ),
    );
    if (!_sameBytes(key.canonicalBytes, bytes)) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical key encoding is nonminimal or noncanonical.',
      );
    }
    return key;
  }
}

@immutable
final class CanonicalDisplaySegmentFingerprintEvidence {
  CanonicalDisplaySegmentFingerprintEvidence({
    required this.fingerprint,
    required List<int> canonicalBytes,
    required this.revision,
  }) : _canonicalBytes = Uint8List.fromList(canonicalBytes) {
    _validateFingerprint(fingerprint, 'compatibility fingerprint');
    if (revision.isEmpty || _canonicalBytes.isEmpty) {
      throw ArgumentError('Canonical compatibility evidence is incomplete.');
    }
  }

  final String fingerprint;
  final String revision;
  final Uint8List _canonicalBytes;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);
}

/// Retains the typed P05 evidence required to invoke ReaderCompatibilityClassifier
/// rather than treating F208 equality as authority.
@immutable
final class CanonicalDisplaySegmentCompatibilityEvidence {
  CanonicalDisplaySegmentCompatibilityEvidence({
    required this.layoutMetrics,
    required this.sourceCompatibility,
    required this.paginationAlgorithm,
    required this.rendererLayout,
    required this.readerCompatibility,
    required this.classifierRevision,
  }) {
    if (classifierRevision.isEmpty ||
        readerCompatibility.revision != classifierRevision) {
      throw ArgumentError('Classifier revision evidence is contradictory.');
    }
  }

  factory CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
    ReaderCompatibilityEvidence evidence,
  ) {
    if (!evidence.isComplete) {
      throw ArgumentError('Complete P05 compatibility evidence is required.');
    }
    final layout = evidence.layoutMetricsIdentity!;
    final source = evidence.sourceCompatibilityIdentity!;
    final pagination = evidence.paginationAlgorithmIdentity!;
    final renderer = evidence.rendererLayoutIdentity!;
    final reader = evidence.readerCompatibilityIdentity!;
    return CanonicalDisplaySegmentCompatibilityEvidence(
      layoutMetrics: CanonicalDisplaySegmentFingerprintEvidence(
        fingerprint: layout.fingerprint,
        canonicalBytes: layout.canonicalBytes,
        revision: layout.revision,
      ),
      sourceCompatibility: CanonicalDisplaySegmentFingerprintEvidence(
        fingerprint: source.fingerprint,
        canonicalBytes: source.canonicalBytes,
        revision: 'reader-source-compatibility',
      ),
      paginationAlgorithm: CanonicalDisplaySegmentFingerprintEvidence(
        fingerprint: pagination.fingerprint,
        canonicalBytes: pagination.canonicalBytes,
        revision: pagination.semanticRevision,
      ),
      rendererLayout: CanonicalDisplaySegmentFingerprintEvidence(
        fingerprint: renderer.fingerprint,
        canonicalBytes: renderer.canonicalBytes,
        revision: renderer.rulesRevisionLink,
      ),
      readerCompatibility: CanonicalDisplaySegmentFingerprintEvidence(
        fingerprint: reader.fingerprint,
        canonicalBytes: reader.canonicalBytes,
        revision: reader.classifierRevision,
      ),
      classifierRevision: reader.classifierRevision,
    );
  }

  final CanonicalDisplaySegmentFingerprintEvidence layoutMetrics;
  final CanonicalDisplaySegmentFingerprintEvidence sourceCompatibility;
  final CanonicalDisplaySegmentFingerprintEvidence paginationAlgorithm;
  final CanonicalDisplaySegmentFingerprintEvidence rendererLayout;
  final CanonicalDisplaySegmentFingerprintEvidence readerCompatibility;
  final String classifierRevision;

  ReaderCompatibilityEvidence toReaderEvidence() {
    final layout = LayoutMetricsIdentity(
      revision: layoutMetrics.revision,
      canonicalBytes: layoutMetrics.canonicalBytes,
      fingerprint: layoutMetrics.fingerprint,
    );
    final source = SourceCompatibilityIdentity(
      canonicalBytes: sourceCompatibility.canonicalBytes,
      fingerprint: sourceCompatibility.fingerprint,
    );
    final pagination = PaginationAlgorithmIdentity(
      semanticRevision: paginationAlgorithm.revision,
      canonicalBytes: paginationAlgorithm.canonicalBytes,
      fingerprint: paginationAlgorithm.fingerprint,
    );
    final renderer = RendererLayoutIdentity(
      rulesRevisionLink: rendererLayout.revision,
      canonicalBytes: rendererLayout.canonicalBytes,
      fingerprint: rendererLayout.fingerprint,
    );
    final reader = ReaderCompatibilityIdentity(
      layoutMetricsIdentity: layout,
      sourceCompatibilityIdentity: source,
      paginationAlgorithmIdentity: pagination,
      rendererLayoutIdentity: renderer,
      classifierRevision: classifierRevision,
      canonicalBytes: readerCompatibility.canonicalBytes,
      fingerprint: readerCompatibility.fingerprint,
    );
    return ReaderCompatibilityEvidence(
      layoutMetricsIdentity: layout,
      sourceCompatibilityIdentity: source,
      paginationAlgorithmIdentity: pagination,
      rendererLayoutIdentity: renderer,
      readerCompatibilityIdentity: reader,
    );
  }
}

@immutable
final class CanonicalDisplaySegmentSourceSnapshotLink {
  const CanonicalDisplaySegmentSourceSnapshotLink({
    required this.snapshotDigest,
    required this.sourceRevision,
    required this.parserSourceIdentity,
    required this.publicationFingerprint,
    required this.sourceCount,
  });

  factory CanonicalDisplaySegmentSourceSnapshotLink.fromSnapshot(
    CanonicalPaginationSourceSnapshot snapshot,
  ) => CanonicalDisplaySegmentSourceSnapshotLink(
    snapshotDigest: snapshot.snapshotDigest,
    sourceRevision: snapshot.sourceRevision,
    parserSourceIdentity: snapshot.parserSourceIdentity,
    publicationFingerprint: snapshot.publicationFingerprint,
    sourceCount: snapshot.sourceCount,
  );

  final String snapshotDigest;
  final String sourceRevision;
  final String parserSourceIdentity;
  final String publicationFingerprint;
  final int sourceCount;
}

@immutable
final class CanonicalDisplaySegmentSourceOwner {
  const CanonicalDisplaySegmentSourceOwner({
    required this.sourceIdentity,
    required this.sectionIdentity,
    required this.spineIdentity,
    required this.sourceOrdinalHint,
    required this.sourceDigest,
  });

  factory CanonicalDisplaySegmentSourceOwner.fromOwner(
    CanonicalPaginationSourceOwner owner,
  ) => CanonicalDisplaySegmentSourceOwner(
    sourceIdentity: owner.sourceIdentity,
    sectionIdentity: owner.sectionIdentity,
    spineIdentity: owner.spineIdentity,
    sourceOrdinalHint: owner.sourceOrdinalHint,
    sourceDigest: owner.sourceDigest,
  );

  final String sourceIdentity;
  final String sectionIdentity;
  final String spineIdentity;
  final int sourceOrdinalHint;
  final String sourceDigest;
}

@immutable
final class CanonicalDisplaySegmentSourceInterval {
  CanonicalDisplaySegmentSourceInterval({
    required this.startCursor,
    required this.endCursor,
    required List<CanonicalDisplaySegmentSourceOwner> orderedOwners,
  }) : orderedOwners = List<CanonicalDisplaySegmentSourceOwner>.unmodifiable(
         orderedOwners,
       ) {
    if (orderedOwners.isEmpty) {
      throw ArgumentError('A canonical segment interval needs source owners.');
    }
  }

  final CanonicalPaginationCursor startCursor;
  final CanonicalPaginationCursor endCursor;
  final List<CanonicalDisplaySegmentSourceOwner> orderedOwners;
}

@immutable
final class CanonicalDisplaySegmentCardRecord {
  CanonicalDisplaySegmentCardRecord({
    required this.physicalCardSignature,
    required this.physicalLayoutCompositeFingerprint,
    required this.physicalCardIdentityComponents,
    required this.cardStartCursor,
    required this.cardEndCursor,
    required List<CanonicalPaginationSourceSlice> orderedStableSourceSlices,
    required List<String> orderedBlockLayoutFingerprints,
    required List<int> structuralCardPayload,
    required this.structuralCardPayloadDigest,
    required this.declaredSourceSliceCount,
    required this.declaredBlockLayoutCount,
  }) : orderedStableSourceSlices =
           List<CanonicalPaginationSourceSlice>.unmodifiable(
             orderedStableSourceSlices,
           ),
       orderedBlockLayoutFingerprints = List<String>.unmodifiable(
         orderedBlockLayoutFingerprints,
       ),
       _structuralCardPayload = Uint8List.fromList(structuralCardPayload) {
    _validateFingerprint(physicalCardSignature, 'physical card signature');
    _validateFingerprint(physicalLayoutCompositeFingerprint, 'F210');
    _validateFingerprint(physicalCardIdentityComponents, 'F211');
    _validateFingerprint(structuralCardPayloadDigest, 'card payload digest');
    if (this.orderedStableSourceSlices.isEmpty ||
        declaredSourceSliceCount != this.orderedStableSourceSlices.length ||
        declaredBlockLayoutCount !=
            this.orderedBlockLayoutFingerprints.length ||
        _structuralCardPayload.isEmpty) {
      throw ArgumentError('Canonical card fields/counts are contradictory.');
    }
  }

  factory CanonicalDisplaySegmentCardRecord.fromFinalized(
    CanonicalFinalizedReaderCard finalized, {
    required CanonicalPaginationSourceSnapshot sourceSnapshot,
  }) {
    final layout = finalized.resolvedLayout;
    if (layout == null) {
      throw ArgumentError(
        'A canonical display segment requires final P05 resolved layout.',
      );
    }
    final payload = Uint8List.fromList(
      utf8.encode(canonicalJsonEncode(finalized.card.toJson())),
    );
    return CanonicalDisplaySegmentCardRecord(
      physicalCardSignature: finalized.identity.signature,
      physicalLayoutCompositeFingerprint:
          layout.physicalLayoutCompositeFingerprint,
      physicalCardIdentityComponents: layout.physicalCardIdentityComponents,
      cardStartCursor: _sliceStartCursor(finalized.sourceSlices.first),
      cardEndCursor: _sliceEndCursor(
        finalized.sourceSlices.last,
        sourceSnapshot,
      ),
      orderedStableSourceSlices: finalized.sourceSlices,
      orderedBlockLayoutFingerprints: layout.blocks
          .map((block) => block.blockLayoutFingerprint)
          .toList(growable: false),
      structuralCardPayload: payload,
      structuralCardPayloadDigest: readerSha256(payload),
      declaredSourceSliceCount: finalized.sourceSlices.length,
      declaredBlockLayoutCount: layout.blocks.length,
    );
  }

  final String physicalCardSignature;
  final String physicalLayoutCompositeFingerprint;
  final String physicalCardIdentityComponents;
  final CanonicalPaginationCursor cardStartCursor;
  final CanonicalPaginationCursor cardEndCursor;
  final List<CanonicalPaginationSourceSlice> orderedStableSourceSlices;
  final List<String> orderedBlockLayoutFingerprints;
  final Uint8List _structuralCardPayload;
  final String structuralCardPayloadDigest;
  final int declaredSourceSliceCount;
  final int declaredBlockLayoutCount;

  /// Read-only inspection bytes for the shared record codec. They grant no
  /// cache or publication authority and avoid a parallel size serializer.
  Uint8List get canonicalBytes => Uint8List.fromList(_encodeCard(this));

  Uint8List get structuralCardPayload =>
      Uint8List.fromList(_structuralCardPayload);
}

@immutable
final class CanonicalDisplaySegmentLeftBoundaryProof {
  const CanonicalDisplaySegmentLeftBoundaryProof({
    required this.kind,
    required this.firstCardStartCursor,
    this.predecessorCardSignature,
    this.predecessorEndCursor,
    this.predecessorContinuationDigest,
    this.restartContinuationEncoding,
    this.restartContinuationDigest,
  });

  final CanonicalDisplaySegmentLeftBoundaryKind kind;
  final CanonicalPaginationCursor firstCardStartCursor;
  final String? predecessorCardSignature;
  final CanonicalPaginationCursor? predecessorEndCursor;
  final String? predecessorContinuationDigest;
  final String? restartContinuationEncoding;
  final String? restartContinuationDigest;

  Uint8List get canonicalBytes => Uint8List.fromList(_encodeLeftProof(this));
}

@immutable
final class CanonicalDisplaySegmentRightBoundaryProof {
  const CanonicalDisplaySegmentRightBoundaryProof({
    required this.kind,
    required this.finalCardSignature,
    required this.finalCardEndCursor,
    this.successorCardSignature,
    this.successorStartCursor,
    this.continuationDigest,
    this.frontierStartCursor,
    this.frontierEndCursor,
  });

  final CanonicalDisplaySegmentRightBoundaryKind kind;
  final String finalCardSignature;
  final CanonicalPaginationCursor finalCardEndCursor;
  final String? successorCardSignature;
  final CanonicalPaginationCursor? successorStartCursor;
  final String? continuationDigest;
  final CanonicalPaginationCursor? frontierStartCursor;
  final CanonicalPaginationCursor? frontierEndCursor;

  Uint8List get canonicalBytes => Uint8List.fromList(_encodeRightProof(this));
}

@immutable
final class CanonicalDisplaySegmentContinuationEvidence {
  CanonicalDisplaySegmentContinuationEvidence({
    required this.canonicalEncoding,
    required this.continuationDigest,
  }) {
    _validateFingerprint(continuationDigest, 'continuation digest');
    if (canonicalEncoding.isEmpty) {
      throw ArgumentError('Continuation encoding is required.');
    }
  }

  factory CanonicalDisplaySegmentContinuationEvidence.fromContinuation(
    CanonicalPaginationContinuation continuation,
  ) => CanonicalDisplaySegmentContinuationEvidence(
    canonicalEncoding: continuation.canonicalEncoding,
    continuationDigest: continuation.integrityDigest,
  );

  final String canonicalEncoding;
  final String continuationDigest;
}

@immutable
final class CanonicalDisplaySegmentManifestBinding {
  const CanonicalDisplaySegmentManifestBinding({
    required this.manifestRevision,
    required this.keyDigest,
    required this.recordDigest,
    required this.declaredSegmentCount,
    required this.declaredTotalCardCount,
    required this.declaredTotalSourceSliceCount,
    required this.declaredTotalEncodedBytes,
    required this.declaredTotalDecodedBytes,
  });

  final String manifestRevision;
  final String keyDigest;
  final String recordDigest;
  final int declaredSegmentCount;
  final int declaredTotalCardCount;
  final int declaredTotalSourceSliceCount;
  final int declaredTotalEncodedBytes;
  final int declaredTotalDecodedBytes;

  CanonicalDisplaySegmentManifestBinding copyWith({
    String? keyDigest,
    String? recordDigest,
    int? declaredTotalEncodedBytes,
    int? declaredTotalDecodedBytes,
  }) => CanonicalDisplaySegmentManifestBinding(
    manifestRevision: manifestRevision,
    keyDigest: keyDigest ?? this.keyDigest,
    recordDigest: recordDigest ?? this.recordDigest,
    declaredSegmentCount: declaredSegmentCount,
    declaredTotalCardCount: declaredTotalCardCount,
    declaredTotalSourceSliceCount: declaredTotalSourceSliceCount,
    declaredTotalEncodedBytes:
        declaredTotalEncodedBytes ?? this.declaredTotalEncodedBytes,
    declaredTotalDecodedBytes:
        declaredTotalDecodedBytes ?? this.declaredTotalDecodedBytes,
  );
}

@immutable
final class CanonicalDisplaySegmentRecord {
  CanonicalDisplaySegmentRecord._({
    required this.recordKind,
    required this.semanticRevision,
    required List<int> canonicalKeyBytes,
    required this.keyDigest,
    required this.bookStorageScopeDigest,
    required this.publicationFingerprint,
    required this.compatibilityEvidence,
    required this.sourceSnapshotLink,
    required this.encodingMarker,
    required this.compressionMarker,
    required this.declaredTopLevelFieldCount,
    required this.declaredCardCount,
    required this.declaredSourceSliceCount,
    required this.declaredBlockLayoutCount,
    required this.declaredEncodedByteCount,
    required this.declaredDecodedByteCount,
    required this.stableStartCursor,
    required this.stableEndCursor,
    required this.exactHalfOpenSourceInterval,
    required List<CanonicalDisplaySegmentCardRecord> orderedFinalizedCards,
    required this.leftBoundaryProof,
    required this.rightBoundaryProof,
    required this.continuationEvidence,
    required this.manifestBinding,
    required this.checksumAlgorithm,
    required this.checksumDigest,
    required this.checksumCoverageRevision,
  }) : _canonicalKeyBytes = Uint8List.fromList(canonicalKeyBytes),
       orderedFinalizedCards =
           List<CanonicalDisplaySegmentCardRecord>.unmodifiable(
             orderedFinalizedCards,
           );

  /// Creates a sealed logical record. It does not write to disk or grant cache
  /// reuse/publication authority.
  factory CanonicalDisplaySegmentRecord.create({
    required CanonicalDisplaySegmentKey key,
    required CanonicalDisplaySegmentCompatibilityEvidence compatibilityEvidence,
    required CanonicalDisplaySegmentSourceSnapshotLink sourceSnapshotLink,
    required CanonicalDisplaySegmentSourceInterval exactHalfOpenSourceInterval,
    required List<CanonicalDisplaySegmentCardRecord> orderedFinalizedCards,
    required CanonicalDisplaySegmentLeftBoundaryProof leftBoundaryProof,
    required CanonicalDisplaySegmentRightBoundaryProof rightBoundaryProof,
    required CanonicalDisplaySegmentContinuationEvidence continuationEvidence,
    String manifestRevision = 'canonical_display_segment_manifest_v1',
  }) {
    if (orderedFinalizedCards.isEmpty) {
      throw ArgumentError('A canonical display segment needs finalized cards.');
    }
    final sourceSliceCount = orderedFinalizedCards.fold<int>(
      0,
      (sum, card) => sum + card.declaredSourceSliceCount,
    );
    final blockCount = orderedFinalizedCards.fold<int>(
      0,
      (sum, card) => sum + card.declaredBlockLayoutCount,
    );
    final binding = CanonicalDisplaySegmentManifestBinding(
      manifestRevision: manifestRevision,
      keyDigest: key.digest,
      recordDigest: _zeroDigest,
      declaredSegmentCount: 1,
      declaredTotalCardCount: orderedFinalizedCards.length,
      declaredTotalSourceSliceCount: sourceSliceCount,
      declaredTotalEncodedBytes: 0,
      declaredTotalDecodedBytes: 0,
    );
    var record = CanonicalDisplaySegmentRecord._(
      recordKind: key.recordKind,
      semanticRevision: key.semanticRevision,
      canonicalKeyBytes: key.canonicalBytes,
      keyDigest: key.digest,
      bookStorageScopeDigest: key.bookStorageScopeDigest,
      publicationFingerprint: key.publicationFingerprint,
      compatibilityEvidence: compatibilityEvidence,
      sourceSnapshotLink: sourceSnapshotLink,
      encodingMarker: canonicalDisplaySegmentEncodingMarker,
      compressionMarker: 'none',
      declaredTopLevelFieldCount: 32,
      declaredCardCount: orderedFinalizedCards.length,
      declaredSourceSliceCount: sourceSliceCount,
      declaredBlockLayoutCount: blockCount,
      declaredEncodedByteCount: 0,
      declaredDecodedByteCount: 0,
      stableStartCursor: key.stableStartCursor,
      stableEndCursor: key.stableEndCursor,
      exactHalfOpenSourceInterval: exactHalfOpenSourceInterval,
      orderedFinalizedCards: orderedFinalizedCards,
      leftBoundaryProof: leftBoundaryProof,
      rightBoundaryProof: rightBoundaryProof,
      continuationEvidence: continuationEvidence,
      manifestBinding: binding,
      checksumAlgorithm: 'sha256',
      checksumDigest: _zeroDigest,
      checksumCoverageRevision: canonicalDisplaySegmentChecksumCoverageRevision,
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      final contentDigest = readerSha256(
        CanonicalDisplaySegmentCodec._encodeRecord(
          record,
          includeManifestBinding: false,
          includeChecksum: false,
        ),
      );
      record = record._copyWith(
        manifestBinding: record.manifestBinding.copyWith(
          recordDigest: contentDigest,
        ),
      );
      final bytes = CanonicalDisplaySegmentCodec._encodeRecord(
        record,
        includeChecksum: true,
      );
      if (record.declaredEncodedByteCount == bytes.length &&
          record.declaredDecodedByteCount == bytes.length &&
          record.manifestBinding.declaredTotalEncodedBytes == bytes.length &&
          record.manifestBinding.declaredTotalDecodedBytes == bytes.length) {
        final checksum = readerSha256(
          CanonicalDisplaySegmentCodec._bytesWithoutChecksum(bytes),
        );
        return record._copyWith(checksumDigest: checksum);
      }
      record = record._copyWith(
        declaredEncodedByteCount: bytes.length,
        declaredDecodedByteCount: bytes.length,
        manifestBinding: record.manifestBinding.copyWith(
          declaredTotalEncodedBytes: bytes.length,
          declaredTotalDecodedBytes: bytes.length,
        ),
      );
    }
    throw StateError('Canonical display record byte counts did not stabilize.');
  }

  static const String _zeroDigest =
      '0000000000000000000000000000000000000000000000000000000000000000';

  final String recordKind;
  final String semanticRevision;
  final Uint8List _canonicalKeyBytes;
  final String keyDigest;
  final String bookStorageScopeDigest;
  final String publicationFingerprint;
  final CanonicalDisplaySegmentCompatibilityEvidence compatibilityEvidence;
  final CanonicalDisplaySegmentSourceSnapshotLink sourceSnapshotLink;
  final String encodingMarker;
  final String compressionMarker;
  final int declaredTopLevelFieldCount;
  final int declaredCardCount;
  final int declaredSourceSliceCount;
  final int declaredBlockLayoutCount;
  final int declaredEncodedByteCount;
  final int declaredDecodedByteCount;
  final CanonicalPaginationCursor stableStartCursor;
  final CanonicalPaginationCursor stableEndCursor;
  final CanonicalDisplaySegmentSourceInterval exactHalfOpenSourceInterval;
  final List<CanonicalDisplaySegmentCardRecord> orderedFinalizedCards;
  final CanonicalDisplaySegmentLeftBoundaryProof leftBoundaryProof;
  final CanonicalDisplaySegmentRightBoundaryProof rightBoundaryProof;
  final CanonicalDisplaySegmentContinuationEvidence continuationEvidence;
  final CanonicalDisplaySegmentManifestBinding manifestBinding;
  final String checksumAlgorithm;
  final String checksumDigest;
  final String checksumCoverageRevision;

  Uint8List get canonicalKeyBytes => Uint8List.fromList(_canonicalKeyBytes);
  String get sourceCompatibilityFingerprint =>
      compatibilityEvidence.sourceCompatibility.fingerprint;
  String get layoutMetricsFingerprint =>
      compatibilityEvidence.layoutMetrics.fingerprint;
  String get rendererLayoutFingerprint =>
      compatibilityEvidence.rendererLayout.fingerprint;
  String get paginationAlgorithmFingerprint =>
      compatibilityEvidence.paginationAlgorithm.fingerprint;
  String get compatibilityClassifierRevision =>
      compatibilityEvidence.classifierRevision;
  String get readerCompatibilityFingerprint =>
      compatibilityEvidence.readerCompatibility.fingerprint;

  CanonicalDisplaySegmentRecord _copyWith({
    int? declaredEncodedByteCount,
    int? declaredDecodedByteCount,
    CanonicalDisplaySegmentManifestBinding? manifestBinding,
    String? checksumDigest,
  }) => CanonicalDisplaySegmentRecord._(
    recordKind: recordKind,
    semanticRevision: semanticRevision,
    canonicalKeyBytes: _canonicalKeyBytes,
    keyDigest: keyDigest,
    bookStorageScopeDigest: bookStorageScopeDigest,
    publicationFingerprint: publicationFingerprint,
    compatibilityEvidence: compatibilityEvidence,
    sourceSnapshotLink: sourceSnapshotLink,
    encodingMarker: encodingMarker,
    compressionMarker: compressionMarker,
    declaredTopLevelFieldCount: declaredTopLevelFieldCount,
    declaredCardCount: declaredCardCount,
    declaredSourceSliceCount: declaredSourceSliceCount,
    declaredBlockLayoutCount: declaredBlockLayoutCount,
    declaredEncodedByteCount:
        declaredEncodedByteCount ?? this.declaredEncodedByteCount,
    declaredDecodedByteCount:
        declaredDecodedByteCount ?? this.declaredDecodedByteCount,
    stableStartCursor: stableStartCursor,
    stableEndCursor: stableEndCursor,
    exactHalfOpenSourceInterval: exactHalfOpenSourceInterval,
    orderedFinalizedCards: orderedFinalizedCards,
    leftBoundaryProof: leftBoundaryProof,
    rightBoundaryProof: rightBoundaryProof,
    continuationEvidence: continuationEvidence,
    manifestBinding: manifestBinding ?? this.manifestBinding,
    checksumAlgorithm: checksumAlgorithm,
    checksumDigest: checksumDigest ?? this.checksumDigest,
    checksumCoverageRevision: checksumCoverageRevision,
  );
}

/// Builds one bounded logical cache record exclusively from finalized P04
/// cards, their accepted continuation, the pinned source snapshot, and final
/// P05 compatibility evidence. It has no storage or publication side effect.
abstract final class CanonicalDisplaySegmentRecordBuilder {
  static CanonicalDisplaySegmentRecordBuildResult buildForPublication({
    required String bookStorageScopeDigest,
    required CanonicalDisplaySegmentCompatibilityEvidence compatibilityEvidence,
    required CanonicalPaginationSourceSnapshot sourceSnapshot,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required CanonicalPaginationContinuation continuation,
    CanonicalPaginationContinuation? acceptedRestart,
  }) {
    if (finalizedCards.isEmpty) {
      return const CanonicalDisplaySegmentRecordNoWrite(
        CanonicalDisplaySegmentNoWriteReason.emptyPublication,
      );
    }
    final start = finalizedCards.first.sourceSlices.first;
    final beginsAtSourceStart = start.startUtf16 != null
        ? start.startUtf16 == 0
        : start.tableRowStart != null
        ? start.tableRowStart == 0
        : true;
    if (acceptedRestart == null &&
        (start.sourceOrdinalHint != 0 || !beginsAtSourceStart)) {
      return const CanonicalDisplaySegmentRecordNoWrite(
        CanonicalDisplaySegmentNoWriteReason.unprovenMidBookRestart,
      );
    }
    try {
      return CanonicalDisplaySegmentRecordBuilt(
        build(
          bookStorageScopeDigest: bookStorageScopeDigest,
          compatibilityEvidence: compatibilityEvidence,
          sourceSnapshot: sourceSnapshot,
          finalizedCards: finalizedCards,
          continuation: continuation,
          acceptedRestart: acceptedRestart,
        ),
      );
    } on Object catch (error) {
      return CanonicalDisplaySegmentRecordNoWrite(
        CanonicalDisplaySegmentNoWriteReason.rejectedStrictConstruction,
        diagnostic: '$error',
      );
    }
  }

  static CanonicalDisplaySegmentRecord build({
    required String bookStorageScopeDigest,
    required CanonicalDisplaySegmentCompatibilityEvidence compatibilityEvidence,
    required CanonicalPaginationSourceSnapshot sourceSnapshot,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required CanonicalPaginationContinuation continuation,
    CanonicalPaginationContinuation? acceptedRestart,
  }) {
    if (finalizedCards.isEmpty) {
      throw ArgumentError('A canonical record requires finalized P04 cards.');
    }
    final cards = <CanonicalDisplaySegmentCardRecord>[
      for (final card in finalizedCards)
        CanonicalDisplaySegmentCardRecord.fromFinalized(
          card,
          sourceSnapshot: sourceSnapshot,
        ),
    ];
    final startCursor = cards.first.cardStartCursor;
    final endCursor = cards.last.cardEndCursor;
    final startOrdinal = startCursor.sourceOrdinalHint;
    final endOrdinalExclusive = endCursor.isLogicalEnd
        ? sourceSnapshot.sourceCount
        : endCursor.sourceOrdinalHint +
              (endCursor.kind == CanonicalPaginationCursorKind.wholeSource
                  ? 0
                  : 1);
    if (startOrdinal < 0 ||
        startOrdinal >= endOrdinalExclusive ||
        endOrdinalExclusive > sourceSnapshot.sourceCount) {
      throw ArgumentError('Finalized cards do not form a bounded interval.');
    }
    final isBookStart = acceptedRestart == null;
    if (isBookStart && startOrdinal != 0) {
      throw ArgumentError(
        'A record without an accepted restart must begin at book start.',
      );
    }
    final leftProof = isBookStart
        ? CanonicalDisplaySegmentLeftBoundaryProof(
            kind: CanonicalDisplaySegmentLeftBoundaryKind.bookStart,
            firstCardStartCursor: startCursor,
          )
        : CanonicalDisplaySegmentLeftBoundaryProof(
            kind: CanonicalDisplaySegmentLeftBoundaryKind.restart,
            firstCardStartCursor: startCursor,
            restartContinuationEncoding: acceptedRestart.canonicalEncoding,
            restartContinuationDigest: acceptedRestart.integrityDigest,
          );
    final continuationEvidence =
        CanonicalDisplaySegmentContinuationEvidence.fromContinuation(
          continuation,
        );
    final rightProof = continuation.terminal
        ? CanonicalDisplaySegmentRightBoundaryProof(
            kind: CanonicalDisplaySegmentRightBoundaryKind.logicalEnd,
            finalCardSignature: cards.last.physicalCardSignature,
            finalCardEndCursor: endCursor,
          )
        : CanonicalDisplaySegmentRightBoundaryProof(
            kind: CanonicalDisplaySegmentRightBoundaryKind.frontier,
            finalCardSignature: cards.last.physicalCardSignature,
            finalCardEndCursor: endCursor,
            continuationDigest: continuation.integrityDigest,
            frontierStartCursor: continuation.frontier.cardCandidateCount == 0
                ? null
                : continuation.previousFinalizedBoundary.endCursor,
            frontierEndCursor: continuation.frontier.cardCandidateCount == 0
                ? null
                : continuation.nextSourceCursor,
          );
    final key = CanonicalDisplaySegmentKey(
      bookStorageScopeDigest: bookStorageScopeDigest,
      publicationFingerprint: sourceSnapshot.publicationFingerprint,
      sourceCompatibilityFingerprint:
          compatibilityEvidence.sourceCompatibility.fingerprint,
      layoutMetricsFingerprint: compatibilityEvidence.layoutMetrics.fingerprint,
      rendererLayoutFingerprint:
          compatibilityEvidence.rendererLayout.fingerprint,
      paginationAlgorithmFingerprint:
          compatibilityEvidence.paginationAlgorithm.fingerprint,
      compatibilityClassifierRevision: compatibilityEvidence.classifierRevision,
      readerCompatibilityFingerprint:
          compatibilityEvidence.readerCompatibility.fingerprint,
      stableStartCursor: startCursor,
      stableEndCursor: endCursor,
      boundaryRole: isBookStart
          ? CanonicalDisplaySegmentBoundaryRole.bookStartAnchored
          : CanonicalDisplaySegmentBoundaryRole.continuationAnchored,
    );
    return CanonicalDisplaySegmentRecord.create(
      key: key,
      compatibilityEvidence: compatibilityEvidence,
      sourceSnapshotLink:
          CanonicalDisplaySegmentSourceSnapshotLink.fromSnapshot(
            sourceSnapshot,
          ),
      exactHalfOpenSourceInterval: CanonicalDisplaySegmentSourceInterval(
        startCursor: startCursor,
        endCursor: endCursor,
        orderedOwners: <CanonicalDisplaySegmentSourceOwner>[
          for (
            var ordinal = startOrdinal;
            ordinal < endOrdinalExclusive;
            ordinal += 1
          )
            CanonicalDisplaySegmentSourceOwner.fromOwner(
              sourceSnapshot.ownerAt(ordinal),
            ),
        ],
      ),
      orderedFinalizedCards: cards,
      leftBoundaryProof: leftProof,
      rightBoundaryProof: rightProof,
      continuationEvidence: continuationEvidence,
    );
  }
}

enum CanonicalDisplaySegmentNoWriteReason {
  emptyPublication,
  unprovenMidBookRestart,
  rejectedStrictConstruction,
}

sealed class CanonicalDisplaySegmentRecordBuildResult {
  const CanonicalDisplaySegmentRecordBuildResult();
}

final class CanonicalDisplaySegmentRecordBuilt
    extends CanonicalDisplaySegmentRecordBuildResult {
  const CanonicalDisplaySegmentRecordBuilt(this.record);

  final CanonicalDisplaySegmentRecord record;
}

final class CanonicalDisplaySegmentRecordNoWrite
    extends CanonicalDisplaySegmentRecordBuildResult {
  const CanonicalDisplaySegmentRecordNoWrite(this.reason, {this.diagnostic});

  final CanonicalDisplaySegmentNoWriteReason reason;
  final String? diagnostic;
}

/// Strict logical codec only. No method creates a legacy or deployed cache
/// payload; callers must pass finite [CanonicalDisplaySegmentCodecLimits].
abstract final class CanonicalDisplaySegmentCodec {
  static Uint8List encode(CanonicalDisplaySegmentRecord record) {
    final bytes = _encodeRecord(record, includeChecksum: true);
    if (record.declaredTopLevelFieldCount != 32 ||
        record.declaredEncodedByteCount != bytes.length ||
        record.declaredDecodedByteCount != bytes.length) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical record declared counts or lengths are contradictory.',
      );
    }
    return bytes;
  }

  static CanonicalDisplaySegmentRecord decode(
    Uint8List bytes, {
    required CanonicalDisplaySegmentCodecLimits limits,
  }) {
    if (bytes.isEmpty ||
        bytes.length > limits.maxEncodedBytes ||
        bytes.length > limits.maxDecodedBytes) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical record length exceeds supplied limits.',
      );
    }
    final fields = _CanonicalSegmentReader(
      bytes,
      limits,
    ).readFields(_recordTags);
    final record = CanonicalDisplaySegmentRecord._(
      recordKind: fields.stringAt(1),
      semanticRevision: fields.stringAt(2),
      canonicalKeyBytes: fields.bytesAt(3),
      keyDigest: fields.stringAt(4),
      bookStorageScopeDigest: fields.stringAt(5),
      publicationFingerprint: fields.stringAt(6),
      compatibilityEvidence: CanonicalDisplaySegmentCompatibilityEvidence(
        sourceCompatibility: _decodeFingerprintEvidence(
          fields.recordAt(7),
          limits,
        ),
        layoutMetrics: _decodeFingerprintEvidence(fields.recordAt(8), limits),
        rendererLayout: _decodeFingerprintEvidence(fields.recordAt(9), limits),
        paginationAlgorithm: _decodeFingerprintEvidence(
          fields.recordAt(10),
          limits,
        ),
        classifierRevision: fields.stringAt(11),
        readerCompatibility: _decodeFingerprintEvidence(
          fields.recordAt(12),
          limits,
        ),
      ),
      sourceSnapshotLink: _decodeSnapshotLink(fields.recordAt(13), limits),
      encodingMarker: fields.stringAt(14),
      compressionMarker: fields.stringAt(15),
      declaredTopLevelFieldCount: fields.uintAt(16),
      declaredCardCount: fields.uintAt(17),
      declaredSourceSliceCount: fields.uintAt(18),
      declaredBlockLayoutCount: fields.uintAt(19),
      declaredEncodedByteCount: fields.uintAt(20),
      declaredDecodedByteCount: fields.uintAt(21),
      stableStartCursor: _decodeCursor(fields.recordAt(22), limits),
      stableEndCursor: _decodeCursor(fields.recordAt(23), limits),
      exactHalfOpenSourceInterval: _decodeInterval(fields.recordAt(24), limits),
      orderedFinalizedCards: _decodeCards(
        fields.listAt(25, limits: limits, maxCount: limits.maxCards),
        limits,
      ),
      leftBoundaryProof: _decodeLeftProof(fields.recordAt(26), limits),
      rightBoundaryProof: _decodeRightProof(fields.recordAt(27), limits),
      continuationEvidence: _decodeContinuation(fields.recordAt(28), limits),
      manifestBinding: _decodeManifestBinding(fields.recordAt(29), limits),
      checksumAlgorithm: fields.stringAt(30),
      checksumDigest: fields.stringAt(31),
      checksumCoverageRevision: fields.stringAt(32),
    );
    _validateDecodedRecordShape(record, bytes, limits);
    return record;
  }

  static const Set<int> _recordTags = <int>{
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
  };

  static Uint8List _encodeRecord(
    CanonicalDisplaySegmentRecord record, {
    required bool includeChecksum,
    bool includeManifestBinding = true,
  }) {
    final writer = _CanonicalSegmentWriter();
    writer.stringField(1, record.recordKind);
    writer.stringField(2, record.semanticRevision);
    writer.bytesField(3, record.canonicalKeyBytes);
    writer.stringField(4, record.keyDigest);
    writer.stringField(5, record.bookStorageScopeDigest);
    writer.stringField(6, record.publicationFingerprint);
    writer.recordField(
      7,
      _encodeFingerprintEvidence(
        record.compatibilityEvidence.sourceCompatibility,
      ),
    );
    writer.recordField(
      8,
      _encodeFingerprintEvidence(record.compatibilityEvidence.layoutMetrics),
    );
    writer.recordField(
      9,
      _encodeFingerprintEvidence(record.compatibilityEvidence.rendererLayout),
    );
    writer.recordField(
      10,
      _encodeFingerprintEvidence(
        record.compatibilityEvidence.paginationAlgorithm,
      ),
    );
    writer.stringField(11, record.compatibilityEvidence.classifierRevision);
    writer.recordField(
      12,
      _encodeFingerprintEvidence(
        record.compatibilityEvidence.readerCompatibility,
      ),
    );
    writer.recordField(13, _encodeSnapshotLink(record.sourceSnapshotLink));
    writer.stringField(14, record.encodingMarker);
    writer.stringField(15, record.compressionMarker);
    writer.uintField(16, record.declaredTopLevelFieldCount);
    writer.uintField(17, record.declaredCardCount);
    writer.uintField(18, record.declaredSourceSliceCount);
    writer.uintField(19, record.declaredBlockLayoutCount);
    writer.uintField(20, record.declaredEncodedByteCount);
    writer.uintField(21, record.declaredDecodedByteCount);
    writer.recordField(22, _encodeCursor(record.stableStartCursor));
    writer.recordField(23, _encodeCursor(record.stableEndCursor));
    writer.recordField(24, _encodeInterval(record.exactHalfOpenSourceInterval));
    writer.recordListField(
      25,
      record.orderedFinalizedCards.map(_encodeCard).toList(growable: false),
    );
    writer.recordField(26, _encodeLeftProof(record.leftBoundaryProof));
    writer.recordField(27, _encodeRightProof(record.rightBoundaryProof));
    writer.recordField(28, _encodeContinuation(record.continuationEvidence));
    if (includeManifestBinding) {
      writer.recordField(29, _encodeManifestBinding(record.manifestBinding));
    }
    writer.stringField(30, record.checksumAlgorithm);
    if (includeChecksum) {
      writer.stringField(31, record.checksumDigest);
    }
    writer.stringField(32, record.checksumCoverageRevision);
    return writer.takeBytes();
  }

  static Uint8List _bytesWithoutChecksum(Uint8List bytes) {
    final reader = _CanonicalSegmentReader(
      bytes,
      const CanonicalDisplaySegmentCodecLimits(
        maxEncodedBytes: 1 << 30,
        maxDecodedBytes: 1 << 30,
        maxFieldBytes: 1 << 30,
        maxCards: 1 << 20,
        maxSourceSlices: 1 << 24,
        maxBlockLayouts: 1 << 24,
        maxContinuationBytes: 1 << 30,
        maxManifestSegments: 1 << 20,
        maxContinuationChainOrdinal: 1 << 30,
      ),
    );
    return reader.copyWithoutTag(31, _recordTags);
  }

  static void _validateDecodedRecordShape(
    CanonicalDisplaySegmentRecord record,
    Uint8List bytes,
    CanonicalDisplaySegmentCodecLimits limits,
  ) {
    if (record.recordKind != canonicalDisplaySegmentRecordKind ||
        record.semanticRevision != canonicalDisplaySegmentSemanticRevision ||
        record.encodingMarker != canonicalDisplaySegmentEncodingMarker ||
        record.compressionMarker != 'none' ||
        record.checksumAlgorithm != 'sha256' ||
        record.checksumCoverageRevision !=
            canonicalDisplaySegmentChecksumCoverageRevision ||
        record.declaredTopLevelFieldCount != 32 ||
        record.declaredEncodedByteCount != bytes.length ||
        record.declaredDecodedByteCount != bytes.length ||
        record.declaredCardCount != record.orderedFinalizedCards.length ||
        record.declaredCardCount > limits.maxCards) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical record header/count/encoding is invalid.',
      );
    }
    final key = CanonicalDisplaySegmentKey.decode(
      record.canonicalKeyBytes,
      limits: limits,
    );
    if (key.digest != record.keyDigest ||
        key.bookStorageScopeDigest != record.bookStorageScopeDigest ||
        key.publicationFingerprint != record.publicationFingerprint ||
        key.sourceCompatibilityFingerprint !=
            record.sourceCompatibilityFingerprint ||
        key.layoutMetricsFingerprint != record.layoutMetricsFingerprint ||
        key.rendererLayoutFingerprint != record.rendererLayoutFingerprint ||
        key.paginationAlgorithmFingerprint !=
            record.paginationAlgorithmFingerprint ||
        key.compatibilityClassifierRevision !=
            record.compatibilityClassifierRevision ||
        key.readerCompatibilityFingerprint !=
            record.readerCompatibilityFingerprint ||
        !key.stableStartCursor.samePositionAs(record.stableStartCursor) ||
        !key.stableEndCursor.samePositionAs(record.stableEndCursor)) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical key components do not match record fields.',
      );
    }
    final sourceSlices = record.orderedFinalizedCards.fold<int>(
      0,
      (sum, card) => sum + card.declaredSourceSliceCount,
    );
    final blocks = record.orderedFinalizedCards.fold<int>(
      0,
      (sum, card) => sum + card.declaredBlockLayoutCount,
    );
    if (sourceSlices != record.declaredSourceSliceCount ||
        blocks != record.declaredBlockLayoutCount ||
        sourceSlices > limits.maxSourceSlices ||
        blocks > limits.maxBlockLayouts ||
        record.manifestBinding.keyDigest != record.keyDigest ||
        record.manifestBinding.declaredSegmentCount <= 0 ||
        record.manifestBinding.declaredSegmentCount >
            limits.maxManifestSegments ||
        record.manifestBinding.declaredTotalCardCount !=
            record.declaredCardCount ||
        record.manifestBinding.declaredTotalSourceSliceCount != sourceSlices ||
        record.manifestBinding.declaredTotalEncodedBytes != bytes.length ||
        record.manifestBinding.declaredTotalDecodedBytes != bytes.length) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical record counts or manifest binding are invalid.',
      );
    }
    _validateFingerprint(record.checksumDigest, 'record checksum');
    if (readerSha256(_bytesWithoutChecksum(bytes)) != record.checksumDigest ||
        readerSha256(
              _encodeRecord(
                record,
                includeManifestBinding: false,
                includeChecksum: false,
              ),
            ) !=
            record.manifestBinding.recordDigest) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical record checksum or manifest digest is invalid.',
      );
    }
  }
}

final class CanonicalDisplaySegmentFormatException implements FormatException {
  const CanonicalDisplaySegmentFormatException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'CanonicalDisplaySegmentFormatException: $message';
}

enum _CanonicalSegmentWireType {
  bytes,
  string,
  uint,
  sint,
  boolean,
  record,
  list,
}

final class _CanonicalSegmentWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  var _lastTag = 0;

  void stringField(int tag, String value, {bool allowEmpty = false}) {
    if (!allowEmpty && value.isEmpty) {
      throw ArgumentError('Canonical string field $tag must be nonempty.');
    }
    _field(tag, _CanonicalSegmentWireType.string, utf8.encode(value));
  }

  void bytesField(int tag, List<int> value) =>
      _field(tag, _CanonicalSegmentWireType.bytes, value);

  void uintField(int tag, int value) {
    if (value < 0) throw ArgumentError('Unsigned canonical field is negative.');
    _field(tag, _CanonicalSegmentWireType.uint, _encodeUnsigned(value));
  }

  void sintField(int tag, int value) =>
      _field(tag, _CanonicalSegmentWireType.sint, _encodeSigned(value));

  void boolField(int tag, bool value) =>
      _field(tag, _CanonicalSegmentWireType.boolean, <int>[value ? 1 : 0]);

  void recordField(int tag, List<int> value) =>
      _field(tag, _CanonicalSegmentWireType.record, value);

  void recordListField(int tag, List<Uint8List> values) {
    final nested = BytesBuilder(copy: false)
      ..add(_encodeUnsigned(values.length));
    for (final value in values) {
      nested
        ..add(_encodeUnsigned(value.length))
        ..add(value);
    }
    _field(tag, _CanonicalSegmentWireType.list, nested.takeBytes());
  }

  Uint8List takeBytes() => _bytes.takeBytes();

  void _field(int tag, _CanonicalSegmentWireType type, List<int> payload) {
    if (tag <= _lastTag || tag <= 0 || payload.length > 0x7fffffff) {
      throw ArgumentError('Canonical field tags or length are invalid.');
    }
    _lastTag = tag;
    _bytes
      ..add(_encodeUnsigned(tag))
      ..add(<int>[type.index])
      ..add(_encodeUnsigned(payload.length))
      ..add(payload);
  }
}

final class _CanonicalSegmentReader {
  _CanonicalSegmentReader(this.bytes, this.limits);

  final Uint8List bytes;
  final CanonicalDisplaySegmentCodecLimits limits;

  _CanonicalSegmentFields readFields(Set<int> expected) {
    if (bytes.length > limits.maxFieldBytes) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical nested record exceeds supplied field limit.',
      );
    }
    var offset = 0;
    var prior = 0;
    final entries = <int, _CanonicalSegmentField>{};
    while (offset < bytes.length) {
      final tag = _readUnsigned(offset);
      offset = tag.next;
      if (tag.value <= prior || !expected.contains(tag.value)) {
        throw const CanonicalDisplaySegmentFormatException(
          'Canonical fields are unknown, duplicated, or unordered.',
        );
      }
      prior = tag.value;
      if (offset >= bytes.length ||
          bytes[offset] >= _CanonicalSegmentWireType.values.length) {
        throw const CanonicalDisplaySegmentFormatException(
          'Canonical field type is invalid.',
        );
      }
      final type = _CanonicalSegmentWireType.values[bytes[offset++]];
      final length = _readUnsigned(offset);
      offset = length.next;
      if (length.value > limits.maxFieldBytes ||
          length.value > bytes.length - offset) {
        throw const CanonicalDisplaySegmentFormatException(
          'Canonical field length is invalid.',
        );
      }
      entries[tag.value] = _CanonicalSegmentField(
        type,
        Uint8List.sublistView(bytes, offset, offset + length.value),
      );
      offset += length.value;
    }
    if (offset != bytes.length || entries.length != expected.length) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical fields are missing or trailing.',
      );
    }
    return _CanonicalSegmentFields(entries);
  }

  Uint8List copyWithoutTag(int omitted, Set<int> expected) {
    var offset = 0;
    final result = BytesBuilder(copy: false);
    var prior = 0;
    var count = 0;
    while (offset < bytes.length) {
      final start = offset;
      final tag = _readUnsigned(offset);
      offset = tag.next;
      if (tag.value <= prior || !expected.contains(tag.value)) {
        throw const CanonicalDisplaySegmentFormatException(
          'Canonical fields are unknown, duplicated, or unordered.',
        );
      }
      prior = tag.value;
      if (offset >= bytes.length ||
          bytes[offset] >= _CanonicalSegmentWireType.values.length) {
        throw const CanonicalDisplaySegmentFormatException(
          'Canonical field type is invalid.',
        );
      }
      offset++;
      final length = _readUnsigned(offset);
      offset = length.next + length.value;
      if (offset > bytes.length) {
        throw const CanonicalDisplaySegmentFormatException(
          'Canonical field length is invalid.',
        );
      }
      count++;
      if (tag.value != omitted) result.add(bytes.sublist(start, offset));
    }
    if (count != expected.length || offset != bytes.length) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical checksum field set is invalid.',
      );
    }
    return result.takeBytes();
  }

  ({int value, int next}) _readUnsigned(int offset) {
    var value = 0;
    var shift = 0;
    var cursor = offset;
    while (true) {
      if (cursor >= bytes.length || shift > 63) {
        throw const CanonicalDisplaySegmentFormatException(
          'Canonical integer is truncated or overflows.',
        );
      }
      final byte = bytes[cursor++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        final encoded = _encodeUnsigned(value);
        if (encoded.length != cursor - offset ||
            !_sameBytes(encoded, bytes.sublist(offset, cursor))) {
          throw const CanonicalDisplaySegmentFormatException(
            'Canonical integer is nonminimal.',
          );
        }
        return (value: value, next: cursor);
      }
      shift += 7;
    }
  }
}

final class _CanonicalSegmentField {
  const _CanonicalSegmentField(this.type, this.bytes);
  final _CanonicalSegmentWireType type;
  final Uint8List bytes;
}

final class _CanonicalSegmentFields {
  const _CanonicalSegmentFields(this._entries);
  final Map<int, _CanonicalSegmentField> _entries;

  bool contains(int tag) => _entries.containsKey(tag);

  String stringAt(int tag, {bool allowEmpty = false}) {
    final bytes = _at(tag, _CanonicalSegmentWireType.string);
    final value = utf8.decode(bytes, allowMalformed: false);
    if ((!allowEmpty && value.isEmpty) ||
        !_sameBytes(utf8.encode(value), bytes)) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical string is invalid.',
      );
    }
    return value;
  }

  Uint8List bytesAt(int tag) =>
      Uint8List.fromList(_at(tag, _CanonicalSegmentWireType.bytes));

  int uintAt(int tag) =>
      _decodeUnsigned(_at(tag, _CanonicalSegmentWireType.uint));

  int sintAt(int tag) =>
      _decodeSigned(_at(tag, _CanonicalSegmentWireType.sint));

  bool boolAt(int tag) {
    final value = _at(tag, _CanonicalSegmentWireType.boolean);
    if (value.length != 1 || (value.single != 0 && value.single != 1)) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical boolean is invalid.',
      );
    }
    return value.single == 1;
  }

  Uint8List recordAt(int tag) =>
      Uint8List.fromList(_at(tag, _CanonicalSegmentWireType.record));

  List<Uint8List> listAt(
    int tag, {
    required CanonicalDisplaySegmentCodecLimits limits,
    required int maxCount,
  }) {
    final bytes = _at(tag, _CanonicalSegmentWireType.list);
    final reader = _CanonicalSegmentReader(bytes, limits);
    var offset = 0;
    final count = reader._readUnsigned(offset);
    offset = count.next;
    if (count.value > maxCount) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical list count is excessive.',
      );
    }
    final values = <Uint8List>[];
    for (var index = 0; index < count.value; index++) {
      final length = reader._readUnsigned(offset);
      offset = length.next;
      if (length.value > bytes.length - offset) {
        throw const CanonicalDisplaySegmentFormatException(
          'Canonical list entry is truncated.',
        );
      }
      values.add(
        Uint8List.fromList(bytes.sublist(offset, offset + length.value)),
      );
      offset += length.value;
    }
    if (offset != bytes.length) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical list has trailing bytes.',
      );
    }
    return values;
  }

  Uint8List _at(int tag, _CanonicalSegmentWireType expected) {
    final field = _entries[tag];
    if (field == null) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical required field is missing.',
      );
    }
    if (field.type != expected) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical field type is contradictory.',
      );
    }
    return field.bytes;
  }
}

Uint8List _encodeUnsigned(int value) {
  if (value < 0) throw ArgumentError.value(value, 'value');
  final bytes = <int>[];
  do {
    var byte = value & 0x7f;
    value >>= 7;
    if (value != 0) byte |= 0x80;
    bytes.add(byte);
  } while (value != 0);
  return Uint8List.fromList(bytes);
}

Uint8List _encodeSigned(int value) {
  final zigZag = (value << 1) ^ (value >> 63);
  return _encodeUnsigned(zigZag);
}

int _decodeUnsigned(Uint8List bytes) {
  final reader = _CanonicalSegmentReader(
    bytes,
    const CanonicalDisplaySegmentCodecLimits(
      maxEncodedBytes: 1024,
      maxDecodedBytes: 1024,
      maxFieldBytes: 1024,
      maxCards: 1,
      maxSourceSlices: 1,
      maxBlockLayouts: 1,
      maxContinuationBytes: 1,
      maxManifestSegments: 1,
      maxContinuationChainOrdinal: 1,
    ),
  );
  final decoded = reader._readUnsigned(0);
  if (decoded.next != bytes.length) {
    throw const CanonicalDisplaySegmentFormatException(
      'Canonical integer has trailing bytes.',
    );
  }
  return decoded.value;
}

int _decodeSigned(Uint8List bytes) {
  final value = _decodeUnsigned(bytes);
  return (value >> 1) ^ -(value & 1);
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

void _validateFingerprint(String value, String name) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError('$name must be a lowercase SHA-256 fingerprint.');
  }
}

T _enumByName<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw CanonicalDisplaySegmentFormatException('Unknown $field.');
}

Uint8List _encodeCursor(CanonicalPaginationCursor cursor) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, cursor.kind.name);
  writer.stringField(2, cursor.sourceIdentity, allowEmpty: true);
  writer.stringField(3, cursor.sectionIdentity, allowEmpty: true);
  writer.sintField(4, cursor.sourceOrdinalHint);
  writer.uintField(5, cursor.textOffsetUtf16);
  writer.uintField(6, cursor.tableRowIndex);
  return writer.takeBytes();
}

CanonicalPaginationCursor _decodeCursor(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2, 3, 4, 5, 6});
  final cursor = CanonicalPaginationCursor(
    kind: _enumByName(
      CanonicalPaginationCursorKind.values,
      fields.stringAt(1),
      'cursor kind',
    ),
    sourceIdentity: fields.stringAt(2, allowEmpty: true),
    sectionIdentity: fields.stringAt(3, allowEmpty: true),
    sourceOrdinalHint: fields.sintAt(4),
    textOffsetUtf16: fields.uintAt(5),
    tableRowIndex: fields.uintAt(6),
  );
  if (cursor.kind == CanonicalPaginationCursorKind.end) {
    if (!cursor.samePositionAs(const CanonicalPaginationCursor.logicalEnd())) {
      throw const CanonicalDisplaySegmentFormatException(
        'Logical-end cursor has extra authority.',
      );
    }
  } else if (cursor.sourceIdentity.isEmpty ||
      cursor.sectionIdentity.isEmpty ||
      cursor.sourceOrdinalHint < 0) {
    throw const CanonicalDisplaySegmentFormatException(
      'Stable cursor identity is incomplete.',
    );
  }
  return cursor;
}

Uint8List _encodeFingerprintEvidence(
  CanonicalDisplaySegmentFingerprintEvidence evidence,
) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, evidence.fingerprint);
  writer.bytesField(2, evidence.canonicalBytes);
  writer.stringField(3, evidence.revision);
  return writer.takeBytes();
}

CanonicalDisplaySegmentFingerprintEvidence _decodeFingerprintEvidence(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2, 3});
  return CanonicalDisplaySegmentFingerprintEvidence(
    fingerprint: fields.stringAt(1),
    canonicalBytes: fields.bytesAt(2),
    revision: fields.stringAt(3),
  );
}

Uint8List _encodeSnapshotLink(CanonicalDisplaySegmentSourceSnapshotLink link) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, link.snapshotDigest);
  writer.stringField(2, link.sourceRevision);
  writer.stringField(3, link.parserSourceIdentity);
  writer.stringField(4, link.publicationFingerprint);
  writer.uintField(5, link.sourceCount);
  return writer.takeBytes();
}

CanonicalDisplaySegmentSourceSnapshotLink _decodeSnapshotLink(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2, 3, 4, 5});
  return CanonicalDisplaySegmentSourceSnapshotLink(
    snapshotDigest: fields.stringAt(1),
    sourceRevision: fields.stringAt(2),
    parserSourceIdentity: fields.stringAt(3),
    publicationFingerprint: fields.stringAt(4),
    sourceCount: fields.uintAt(5),
  );
}

Uint8List _encodeSourceOwner(CanonicalDisplaySegmentSourceOwner owner) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, owner.sourceIdentity);
  writer.stringField(2, owner.sectionIdentity);
  writer.stringField(3, owner.spineIdentity);
  writer.uintField(4, owner.sourceOrdinalHint);
  writer.stringField(5, owner.sourceDigest);
  return writer.takeBytes();
}

CanonicalDisplaySegmentSourceOwner _decodeSourceOwner(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2, 3, 4, 5});
  return CanonicalDisplaySegmentSourceOwner(
    sourceIdentity: fields.stringAt(1),
    sectionIdentity: fields.stringAt(2),
    spineIdentity: fields.stringAt(3),
    sourceOrdinalHint: fields.uintAt(4),
    sourceDigest: fields.stringAt(5),
  );
}

Uint8List _encodeInterval(CanonicalDisplaySegmentSourceInterval interval) {
  final writer = _CanonicalSegmentWriter();
  writer.recordField(1, _encodeCursor(interval.startCursor));
  writer.recordField(2, _encodeCursor(interval.endCursor));
  writer.recordListField(
    3,
    interval.orderedOwners.map(_encodeSourceOwner).toList(growable: false),
  );
  return writer.takeBytes();
}

CanonicalDisplaySegmentSourceInterval _decodeInterval(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2, 3});
  final values = fields.listAt(
    3,
    limits: limits,
    maxCount: limits.maxSourceSlices,
  );
  return CanonicalDisplaySegmentSourceInterval(
    startCursor: _decodeCursor(fields.recordAt(1), limits),
    endCursor: _decodeCursor(fields.recordAt(2), limits),
    orderedOwners: values
        .map((value) => _decodeSourceOwner(value, limits))
        .toList(growable: false),
  );
}

Uint8List _encodeSlice(CanonicalPaginationSourceSlice slice) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, slice.sourceIdentity);
  writer.stringField(2, slice.sectionIdentity);
  writer.stringField(3, slice.spineIdentity);
  writer.uintField(4, slice.sourceOrdinalHint);
  writer.stringField(5, slice.sourceDigest);
  writer.stringField(6, slice.structuralType);
  writer.stringField(7, slice.structuralOwnerRole);
  writer.stringField(8, slice.logicalOwnerIdentity);
  writer.stringField(9, slice.structuralDigest);
  writer.stringField(10, slice.fragmentDigest);
  writer.stringField(11, slice.publisherLayoutDigest);
  writer.stringField(12, slice.richMetadataDigest);
  writer.stringField(13, slice.listFragmentDigest);
  writer.stringField(14, slice.splitBoundaryKind);
  writer.boolField(15, slice.isLogicalParagraphStart);
  writer.boolField(16, slice.isLogicalParagraphEnd);
  writer.boolField(17, slice.usesExplicitTextFragment);
  writer.sintField(18, slice.startUtf16 ?? -1);
  writer.sintField(19, slice.endUtf16 ?? -1);
  writer.sintField(20, slice.tableRowStart ?? -1);
  writer.sintField(21, slice.tableRowEndExclusive ?? -1);
  return writer.takeBytes();
}

CanonicalPaginationSourceSlice _decodeSlice(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(bytes, limits).readFields(const <int>{
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
  });
  final start = fields.sintAt(18);
  final end = fields.sintAt(19);
  final rowStart = fields.sintAt(20);
  final rowEnd = fields.sintAt(21);
  final hasText = start >= 0 || end >= 0;
  final hasRows = rowStart >= 0 || rowEnd >= 0;
  if ((start < 0) != (end < 0) ||
      (rowStart < 0) != (rowEnd < 0) ||
      (hasText && hasRows) ||
      (hasText && end <= start) ||
      (hasRows && rowEnd <= rowStart)) {
    throw const CanonicalDisplaySegmentFormatException(
      'Canonical source slice interval is contradictory.',
    );
  }
  return CanonicalPaginationSourceSlice(
    sourceIdentity: fields.stringAt(1),
    sectionIdentity: fields.stringAt(2),
    spineIdentity: fields.stringAt(3),
    sourceOrdinalHint: fields.uintAt(4),
    sourceDigest: fields.stringAt(5),
    structuralType: fields.stringAt(6),
    structuralOwnerRole: fields.stringAt(7),
    logicalOwnerIdentity: fields.stringAt(8),
    structuralDigest: fields.stringAt(9),
    fragmentDigest: fields.stringAt(10),
    publisherLayoutDigest: fields.stringAt(11),
    richMetadataDigest: fields.stringAt(12),
    listFragmentDigest: fields.stringAt(13),
    splitBoundaryKind: fields.stringAt(14),
    isLogicalParagraphStart: fields.boolAt(15),
    isLogicalParagraphEnd: fields.boolAt(16),
    usesExplicitTextFragment: fields.boolAt(17),
    startUtf16: start < 0 ? null : start,
    endUtf16: end < 0 ? null : end,
    tableRowStart: rowStart < 0 ? null : rowStart,
    tableRowEndExclusive: rowEnd < 0 ? null : rowEnd,
  );
}

Uint8List _encodeCard(CanonicalDisplaySegmentCardRecord card) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, card.physicalCardSignature);
  writer.stringField(2, card.physicalLayoutCompositeFingerprint);
  writer.stringField(3, card.physicalCardIdentityComponents);
  writer.recordField(4, _encodeCursor(card.cardStartCursor));
  writer.recordField(5, _encodeCursor(card.cardEndCursor));
  writer.recordListField(
    6,
    card.orderedStableSourceSlices.map(_encodeSlice).toList(growable: false),
  );
  writer.recordListField(
    7,
    card.orderedBlockLayoutFingerprints
        .map((value) {
          final nested = _CanonicalSegmentWriter();
          nested.stringField(1, value);
          return nested.takeBytes();
        })
        .toList(growable: false),
  );
  writer.bytesField(8, card.structuralCardPayload);
  writer.stringField(9, card.structuralCardPayloadDigest);
  writer.uintField(10, card.declaredSourceSliceCount);
  writer.uintField(11, card.declaredBlockLayoutCount);
  return writer.takeBytes();
}

List<CanonicalDisplaySegmentCardRecord> _decodeCards(
  List<Uint8List> entries,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  if (entries.isEmpty || entries.length > limits.maxCards) {
    throw const CanonicalDisplaySegmentFormatException(
      'Canonical card count exceeds supplied limits.',
    );
  }
  var sliceTotal = 0;
  var blockTotal = 0;
  final cards = <CanonicalDisplaySegmentCardRecord>[];
  for (final entry in entries) {
    final fields = _CanonicalSegmentReader(
      entry,
      limits,
    ).readFields(const <int>{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11});
    final sliceEntries = fields.listAt(
      6,
      limits: limits,
      maxCount: limits.maxSourceSlices,
    );
    final blockEntries = fields.listAt(
      7,
      limits: limits,
      maxCount: limits.maxBlockLayouts,
    );
    final blocks = <String>[
      for (final block in blockEntries)
        _CanonicalSegmentReader(
          block,
          limits,
        ).readFields(const <int>{1}).stringAt(1),
    ];
    final slices = sliceEntries
        .map((slice) => _decodeSlice(slice, limits))
        .toList(growable: false);
    final card = CanonicalDisplaySegmentCardRecord(
      physicalCardSignature: fields.stringAt(1),
      physicalLayoutCompositeFingerprint: fields.stringAt(2),
      physicalCardIdentityComponents: fields.stringAt(3),
      cardStartCursor: _decodeCursor(fields.recordAt(4), limits),
      cardEndCursor: _decodeCursor(fields.recordAt(5), limits),
      orderedStableSourceSlices: slices,
      orderedBlockLayoutFingerprints: blocks,
      structuralCardPayload: fields.bytesAt(8),
      structuralCardPayloadDigest: fields.stringAt(9),
      declaredSourceSliceCount: fields.uintAt(10),
      declaredBlockLayoutCount: fields.uintAt(11),
    );
    sliceTotal += card.declaredSourceSliceCount;
    blockTotal += card.declaredBlockLayoutCount;
    if (sliceTotal > limits.maxSourceSlices ||
        blockTotal > limits.maxBlockLayouts) {
      throw const CanonicalDisplaySegmentFormatException(
        'Canonical aggregate card fields exceed supplied limits.',
      );
    }
    cards.add(card);
  }
  return List<CanonicalDisplaySegmentCardRecord>.unmodifiable(cards);
}

Uint8List _encodeLeftProof(CanonicalDisplaySegmentLeftBoundaryProof proof) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, proof.kind.name);
  writer.recordField(2, _encodeCursor(proof.firstCardStartCursor));
  writer.stringField(3, proof.predecessorCardSignature ?? '', allowEmpty: true);
  writer.recordField(4, _encodeOptionalCursor(proof.predecessorEndCursor));
  writer.stringField(
    5,
    proof.predecessorContinuationDigest ?? '',
    allowEmpty: true,
  );
  writer.stringField(
    6,
    proof.restartContinuationEncoding ?? '',
    allowEmpty: true,
  );
  writer.stringField(
    7,
    proof.restartContinuationDigest ?? '',
    allowEmpty: true,
  );
  return writer.takeBytes();
}

CanonicalDisplaySegmentLeftBoundaryProof _decodeLeftProof(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2, 3, 4, 5, 6, 7});
  return CanonicalDisplaySegmentLeftBoundaryProof(
    kind: _enumByName(
      CanonicalDisplaySegmentLeftBoundaryKind.values,
      fields.stringAt(1),
      'left boundary kind',
    ),
    firstCardStartCursor: _decodeCursor(fields.recordAt(2), limits),
    predecessorCardSignature: _emptyToNull(
      fields.stringAt(3, allowEmpty: true),
    ),
    predecessorEndCursor: _decodeOptionalCursor(fields.recordAt(4), limits),
    predecessorContinuationDigest: _emptyToNull(
      fields.stringAt(5, allowEmpty: true),
    ),
    restartContinuationEncoding: _emptyToNull(
      fields.stringAt(6, allowEmpty: true),
    ),
    restartContinuationDigest: _emptyToNull(
      fields.stringAt(7, allowEmpty: true),
    ),
  );
}

Uint8List _encodeRightProof(CanonicalDisplaySegmentRightBoundaryProof proof) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, proof.kind.name);
  writer.stringField(2, proof.finalCardSignature);
  writer.recordField(3, _encodeCursor(proof.finalCardEndCursor));
  writer.stringField(4, proof.successorCardSignature ?? '', allowEmpty: true);
  writer.recordField(5, _encodeOptionalCursor(proof.successorStartCursor));
  writer.stringField(6, proof.continuationDigest ?? '', allowEmpty: true);
  writer.recordField(7, _encodeOptionalCursor(proof.frontierStartCursor));
  writer.recordField(8, _encodeOptionalCursor(proof.frontierEndCursor));
  return writer.takeBytes();
}

CanonicalDisplaySegmentRightBoundaryProof _decodeRightProof(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2, 3, 4, 5, 6, 7, 8});
  return CanonicalDisplaySegmentRightBoundaryProof(
    kind: _enumByName(
      CanonicalDisplaySegmentRightBoundaryKind.values,
      fields.stringAt(1),
      'right boundary kind',
    ),
    finalCardSignature: fields.stringAt(2),
    finalCardEndCursor: _decodeCursor(fields.recordAt(3), limits),
    successorCardSignature: _emptyToNull(fields.stringAt(4, allowEmpty: true)),
    successorStartCursor: _decodeOptionalCursor(fields.recordAt(5), limits),
    continuationDigest: _emptyToNull(fields.stringAt(6, allowEmpty: true)),
    frontierStartCursor: _decodeOptionalCursor(fields.recordAt(7), limits),
    frontierEndCursor: _decodeOptionalCursor(fields.recordAt(8), limits),
  );
}

Uint8List _encodeContinuation(
  CanonicalDisplaySegmentContinuationEvidence continuation,
) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, continuation.canonicalEncoding);
  writer.stringField(2, continuation.continuationDigest);
  return writer.takeBytes();
}

CanonicalDisplaySegmentContinuationEvidence _decodeContinuation(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2});
  final encoding = fields.stringAt(1);
  if (utf8.encode(encoding).length > limits.maxContinuationBytes) {
    throw const CanonicalDisplaySegmentFormatException(
      'Continuation exceeds supplied decode limit.',
    );
  }
  return CanonicalDisplaySegmentContinuationEvidence(
    canonicalEncoding: encoding,
    continuationDigest: fields.stringAt(2),
  );
}

Uint8List _encodeManifestBinding(
  CanonicalDisplaySegmentManifestBinding binding,
) {
  final writer = _CanonicalSegmentWriter();
  writer.stringField(1, binding.manifestRevision);
  writer.stringField(2, binding.keyDigest);
  writer.stringField(3, binding.recordDigest);
  writer.uintField(4, binding.declaredSegmentCount);
  writer.uintField(5, binding.declaredTotalCardCount);
  writer.uintField(6, binding.declaredTotalSourceSliceCount);
  writer.uintField(7, binding.declaredTotalEncodedBytes);
  writer.uintField(8, binding.declaredTotalDecodedBytes);
  return writer.takeBytes();
}

CanonicalDisplaySegmentManifestBinding _decodeManifestBinding(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final fields = _CanonicalSegmentReader(
    bytes,
    limits,
  ).readFields(const <int>{1, 2, 3, 4, 5, 6, 7, 8});
  return CanonicalDisplaySegmentManifestBinding(
    manifestRevision: fields.stringAt(1),
    keyDigest: fields.stringAt(2),
    recordDigest: fields.stringAt(3),
    declaredSegmentCount: fields.uintAt(4),
    declaredTotalCardCount: fields.uintAt(5),
    declaredTotalSourceSliceCount: fields.uintAt(6),
    declaredTotalEncodedBytes: fields.uintAt(7),
    declaredTotalDecodedBytes: fields.uintAt(8),
  );
}

Uint8List _encodeOptionalCursor(CanonicalPaginationCursor? cursor) {
  final writer = _CanonicalSegmentWriter();
  writer.boolField(1, cursor != null);
  if (cursor != null) writer.recordField(2, _encodeCursor(cursor));
  return writer.takeBytes();
}

CanonicalPaginationCursor? _decodeOptionalCursor(
  Uint8List bytes,
  CanonicalDisplaySegmentCodecLimits limits,
) {
  final reader = _CanonicalSegmentReader(bytes, limits);
  final fieldSet = _tryReadOptionalCursorFields(reader);
  final present = fieldSet.boolAt(1);
  if (!present && !fieldSet.contains(2)) return null;
  if (!present || !fieldSet.contains(2)) {
    throw const CanonicalDisplaySegmentFormatException(
      'Canonical optional cursor presence is contradictory.',
    );
  }
  return _decodeCursor(fieldSet.recordAt(2), limits);
}

_CanonicalSegmentFields _tryReadOptionalCursorFields(
  _CanonicalSegmentReader reader,
) {
  try {
    return reader.readFields(const <int>{1});
  } on CanonicalDisplaySegmentFormatException {
    return reader.readFields(const <int>{1, 2});
  }
}

String? _emptyToNull(String value) => value.isEmpty ? null : value;

CanonicalPaginationCursor _sliceStartCursor(
  CanonicalPaginationSourceSlice slice,
) {
  if (slice.startUtf16 != null) {
    return CanonicalPaginationCursor(
      kind: slice.startUtf16 == 0
          ? CanonicalPaginationCursorKind.wholeSource
          : CanonicalPaginationCursorKind.sourceText,
      sourceIdentity: slice.sourceIdentity,
      sectionIdentity: slice.sectionIdentity,
      sourceOrdinalHint: slice.sourceOrdinalHint,
      textOffsetUtf16: slice.startUtf16!,
    );
  }
  if (slice.tableRowStart != null) {
    return CanonicalPaginationCursor(
      kind: slice.tableRowStart == 0
          ? CanonicalPaginationCursorKind.wholeSource
          : CanonicalPaginationCursorKind.tableRow,
      sourceIdentity: slice.sourceIdentity,
      sectionIdentity: slice.sectionIdentity,
      sourceOrdinalHint: slice.sourceOrdinalHint,
      tableRowIndex: slice.tableRowStart!,
    );
  }
  return CanonicalPaginationCursor(
    kind: CanonicalPaginationCursorKind.wholeSource,
    sourceIdentity: slice.sourceIdentity,
    sectionIdentity: slice.sectionIdentity,
    sourceOrdinalHint: slice.sourceOrdinalHint,
  );
}

CanonicalPaginationCursor _sliceEndCursor(
  CanonicalPaginationSourceSlice slice,
  CanonicalPaginationSourceSnapshot sourceSnapshot,
) {
  if (slice.endUtf16 != null) {
    final source = sourceSnapshot.resolveOrdinalSource(slice.sourceOrdinalHint);
    if (slice.endUtf16! < (source.text?.length ?? 0)) {
      return CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.sourceText,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: slice.sourceOrdinalHint,
        textOffsetUtf16: slice.endUtf16!,
      );
    }
  }
  if (slice.tableRowEndExclusive != null) {
    final source = sourceSnapshot.resolveOrdinalSource(slice.sourceOrdinalHint);
    final rows = parseReaderContentBlocks(source.text ?? '')
        .where((block) => block.type == ReaderContentBlockType.table)
        .firstOrNull
        ?.table
        ?.rows;
    if (rows != null && slice.tableRowEndExclusive! < rows.length) {
      return CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.tableRow,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: slice.sourceOrdinalHint,
        tableRowIndex: slice.tableRowEndExclusive!,
      );
    }
  }
  if (slice.sourceOrdinalHint + 1 >= sourceSnapshot.sourceCount) {
    return const CanonicalPaginationCursor.logicalEnd();
  }
  final next = sourceSnapshot.ownerAt(slice.sourceOrdinalHint + 1);
  return CanonicalPaginationCursor(
    kind: CanonicalPaginationCursorKind.wholeSource,
    sourceIdentity: next.sourceIdentity,
    sectionIdentity: next.sectionIdentity,
    sourceOrdinalHint: next.sourceOrdinalHint,
  );
}
