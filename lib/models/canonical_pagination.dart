import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'book_chunk.dart';
import 'reader_checkpoint.dart';
import 'reader_layout_contract.dart';

/// Digest input for stable source/fragment ownership. Runtime source ordinals
/// remain available on the pinned record for lookup, but never contribute to
/// a physical-card signature.
String canonicalBookChunkOwnershipDigest(BookChunk chunk) {
  final json = Map<String, Object?>.from(chunk.toJson())..remove('i');
  final ranges = json['sr'];
  if (ranges is List) {
    json['sr'] = <Map<String, Object?>>[
      for (final value in ranges)
        Map<String, Object?>.from(value as Map)..remove('ci'),
    ];
  }
  return readerSha256(json);
}

/// Bounds derived by the approved P04 canonical-pagination design.
abstract final class CanonicalPaginationBounds {
  static const int checkpointSourceStride = 48;
  static const int checkpointCardStride = 8;
  static const int activeSourceCeiling = 432;
  static const int activeCardCeiling = 96;
  static const int standardFrontierEntryCap = 61;
  static const int splitStressFrontierEntryCap = 7;
  static const int normalWorkEnvelope = 110;
  static const int recoveryWorkEnvelope = 158;
  static const int residentContinuationRecordBasis = 25;
}

/// Stable source ownership supplied by the parser/publication layer.
///
/// [sourceOrdinalHint] is validated against [sourceIdentity] whenever it is
/// used. It is never sufficient authority on its own.
@immutable
final class CanonicalPaginationSourceKey {
  const CanonicalPaginationSourceKey({
    required this.sourceIdentity,
    required this.sectionIdentity,
    required this.spineIdentity,
    required this.sourceOrdinalHint,
  });

  final String sourceIdentity;
  final String sectionIdentity;
  final String spineIdentity;
  final int sourceOrdinalHint;
}

@immutable
final class CanonicalPaginationSourceOwner {
  const CanonicalPaginationSourceOwner({
    required this.sourceIdentity,
    required this.sectionIdentity,
    required this.spineIdentity,
    required this.sourceOrdinalHint,
    required this.sourceDigest,
  });

  final String sourceIdentity;
  final String sectionIdentity;
  final String spineIdentity;
  final int sourceOrdinalHint;
  final String sourceDigest;

  Map<String, Object?> toDigestJson() => <String, Object?>{
    'sourceIdentity': sourceIdentity,
    'sectionIdentity': sectionIdentity,
    'spineIdentity': spineIdentity,
    'sourceOrdinalHint': sourceOrdinalHint,
    'sourceDigest': sourceDigest,
  };
}

/// A revision-pinned source snapshot.
///
/// Source chunks are stored as canonical serialized records and decoded on
/// resolution. Consequently neither replacement of the caller's list nor
/// mutation of a caller-owned chunk/list/byte buffer can alter this snapshot.
@immutable
final class CanonicalPaginationSourceSnapshot {
  CanonicalPaginationSourceSnapshot._({
    required this.bookId,
    required this.publicationFingerprint,
    required this.parserSourceIdentity,
    required this.sourceRevision,
    required this.snapshotDigest,
    required List<CanonicalPaginationSourceOwner> owners,
    required List<String> encodedSources,
  }) : owners = List<CanonicalPaginationSourceOwner>.unmodifiable(owners),
       _encodedSources = List<String>.unmodifiable(encodedSources),
       _ordinalByIdentity = Map<String, int>.unmodifiable(<String, int>{
         for (var index = 0; index < owners.length; index++)
           owners[index].sourceIdentity: index,
       });

  factory CanonicalPaginationSourceSnapshot.pin({
    required String bookId,
    required String publicationFingerprint,
    required String parserSourceIdentity,
    required String sourceRevision,
    required List<BookChunk> sourceChunks,
    required List<CanonicalPaginationSourceKey> sourceKeys,
  }) {
    if (bookId.isEmpty ||
        publicationFingerprint.isEmpty ||
        parserSourceIdentity.isEmpty ||
        sourceRevision.isEmpty) {
      throw ArgumentError('Canonical source identities must be nonempty.');
    }
    if (sourceChunks.length != sourceKeys.length) {
      throw ArgumentError('Every source chunk requires one stable owner.');
    }

    final identities = <String>{};
    final encodedSources = <String>[];
    final owners = <CanonicalPaginationSourceOwner>[];
    for (var ordinal = 0; ordinal < sourceChunks.length; ordinal++) {
      final key = sourceKeys[ordinal];
      if (key.sourceIdentity.isEmpty ||
          key.sectionIdentity.isEmpty ||
          key.spineIdentity.isEmpty ||
          key.sourceOrdinalHint != ordinal ||
          sourceChunks[ordinal].index != ordinal ||
          !identities.add(key.sourceIdentity)) {
        throw ArgumentError(
          'Source owner $ordinal is missing, duplicated, or has an invalid '
          'paired source ordinal hint.',
        );
      }
      final encoded = canonicalJsonEncode(sourceChunks[ordinal].toJson());
      encodedSources.add(encoded);
      owners.add(
        CanonicalPaginationSourceOwner(
          sourceIdentity: key.sourceIdentity,
          sectionIdentity: key.sectionIdentity,
          spineIdentity: key.spineIdentity,
          sourceOrdinalHint: ordinal,
          sourceDigest: canonicalBookChunkOwnershipDigest(
            sourceChunks[ordinal],
          ),
        ),
      );
    }

    final snapshotDigest = readerSha256(<String, Object?>{
      'bookId': bookId,
      'publicationFingerprint': publicationFingerprint,
      'parserSourceIdentity': parserSourceIdentity,
      'sourceRevision': sourceRevision,
      'sourceCount': sourceChunks.length,
      'orderedOwners': owners.map((owner) => owner.toDigestJson()).toList(),
      'orderedSourceRecords': encodedSources,
    });
    return CanonicalPaginationSourceSnapshot._(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      parserSourceIdentity: parserSourceIdentity,
      sourceRevision: sourceRevision,
      snapshotDigest: snapshotDigest,
      owners: owners,
      encodedSources: encodedSources,
    );
  }

  final String bookId;
  final String publicationFingerprint;
  final String parserSourceIdentity;
  final String sourceRevision;
  final String snapshotDigest;
  final List<CanonicalPaginationSourceOwner> owners;
  final List<String> _encodedSources;
  final Map<String, int> _ordinalByIdentity;

  int get sourceCount => owners.length;

  CanonicalPaginationSourceOwner ownerAt(int ordinal) => owners[ordinal];

  int? resolveOrdinal({
    required String sourceIdentity,
    required int ordinalHint,
  }) {
    if (ordinalHint < 0 || ordinalHint >= owners.length) return null;
    final owner = owners[ordinalHint];
    if (owner.sourceIdentity != sourceIdentity ||
        _ordinalByIdentity[sourceIdentity] != ordinalHint) {
      return null;
    }
    return ordinalHint;
  }

  BookChunk resolveSource({
    required String sourceIdentity,
    required int ordinalHint,
  }) {
    final ordinal = resolveOrdinal(
      sourceIdentity: sourceIdentity,
      ordinalHint: ordinalHint,
    );
    if (ordinal == null) {
      throw StateError('Stable source owner did not resolve exactly.');
    }
    final decoded = jsonDecode(_encodedSources[ordinal]);
    return BookChunk.fromJson(Map<String, dynamic>.from(decoded as Map));
  }

  BookChunk resolveOrdinalSource(int ordinal) => resolveSource(
    sourceIdentity: owners[ordinal].sourceIdentity,
    ordinalHint: ordinal,
  );

  bool isTrustedSectionStart(int ordinal, String sectionIdentity) {
    if (ordinal < 0 || ordinal >= owners.length) return false;
    if (owners[ordinal].sectionIdentity != sectionIdentity) return false;
    return ordinal == 0 ||
        owners[ordinal - 1].sectionIdentity != sectionIdentity;
  }
}

enum CanonicalPaginationCursorKind { sourceText, tableRow, wholeSource, end }

@immutable
final class CanonicalPaginationCursor {
  const CanonicalPaginationCursor({
    required this.kind,
    required this.sourceIdentity,
    required this.sectionIdentity,
    required this.sourceOrdinalHint,
    this.textOffsetUtf16 = 0,
    this.tableRowIndex = 0,
  });

  const CanonicalPaginationCursor.logicalEnd()
    : kind = CanonicalPaginationCursorKind.end,
      sourceIdentity = '',
      sectionIdentity = '',
      sourceOrdinalHint = -1,
      textOffsetUtf16 = 0,
      tableRowIndex = 0;

  final CanonicalPaginationCursorKind kind;
  final String sourceIdentity;
  final String sectionIdentity;
  final int sourceOrdinalHint;
  final int textOffsetUtf16;
  final int tableRowIndex;

  bool get isLogicalEnd => kind == CanonicalPaginationCursorKind.end;

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'kind': kind.name,
    'sourceIdentity': sourceIdentity,
    'sectionIdentity': sectionIdentity,
    'sourceOrdinalHint': sourceOrdinalHint,
    'textOffsetUtf16': textOffsetUtf16,
    'tableRowIndex': tableRowIndex,
  };

  bool samePositionAs(CanonicalPaginationCursor other) =>
      kind == other.kind &&
      sourceIdentity == other.sourceIdentity &&
      sectionIdentity == other.sectionIdentity &&
      sourceOrdinalHint == other.sourceOrdinalHint &&
      textOffsetUtf16 == other.textOffsetUtf16 &&
      tableRowIndex == other.tableRowIndex;
}

@immutable
final class CanonicalPaginationSourceSlice {
  const CanonicalPaginationSourceSlice({
    required this.sourceIdentity,
    required this.sectionIdentity,
    required this.spineIdentity,
    required this.sourceOrdinalHint,
    required this.sourceDigest,
    required this.structuralType,
    required this.structuralOwnerRole,
    required this.logicalOwnerIdentity,
    required this.structuralDigest,
    required this.fragmentDigest,
    required this.publisherLayoutDigest,
    required this.richMetadataDigest,
    required this.listFragmentDigest,
    required this.splitBoundaryKind,
    required this.isLogicalParagraphStart,
    required this.isLogicalParagraphEnd,
    required this.usesExplicitTextFragment,
    this.startUtf16,
    this.endUtf16,
    this.tableRowStart,
    this.tableRowEndExclusive,
  }) : assert((startUtf16 == null) == (endUtf16 == null)),
       assert((tableRowStart == null) == (tableRowEndExclusive == null));

  final String sourceIdentity;
  final String sectionIdentity;
  final String spineIdentity;
  final int sourceOrdinalHint;
  final String sourceDigest;
  final String structuralType;
  final String structuralOwnerRole;
  final String logicalOwnerIdentity;
  final String structuralDigest;
  final String fragmentDigest;
  final String publisherLayoutDigest;
  final String richMetadataDigest;
  final String listFragmentDigest;
  final String splitBoundaryKind;
  final bool isLogicalParagraphStart;
  final bool isLogicalParagraphEnd;
  final bool usesExplicitTextFragment;
  final int? startUtf16;
  final int? endUtf16;
  final int? tableRowStart;
  final int? tableRowEndExclusive;

  int get referencedUtf16Extent =>
      startUtf16 == null ? 0 : endUtf16! - startUtf16!;

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'sourceIdentity': sourceIdentity,
    'sectionIdentity': sectionIdentity,
    'spineIdentity': spineIdentity,
    'sourceOrdinalHint': sourceOrdinalHint,
    'sourceDigest': sourceDigest,
    'structuralType': structuralType,
    'structuralOwnerRole': structuralOwnerRole,
    'logicalOwnerIdentity': logicalOwnerIdentity,
    'structuralDigest': structuralDigest,
    'fragmentDigest': fragmentDigest,
    'publisherLayoutDigest': publisherLayoutDigest,
    'richMetadataDigest': richMetadataDigest,
    'listFragmentDigest': listFragmentDigest,
    'splitBoundaryKind': splitBoundaryKind,
    'isLogicalParagraphStart': isLogicalParagraphStart,
    'isLogicalParagraphEnd': isLogicalParagraphEnd,
    'usesExplicitTextFragment': usesExplicitTextFragment,
    'startUtf16': startUtf16,
    'endUtf16': endUtf16,
    'tableRowStart': tableRowStart,
    'tableRowEndExclusive': tableRowEndExclusive,
  };
}

/// The only production conversion from finalized canonical slice ownership to
/// a physical-card identity. Source ordinals deliberately remain lookup hints
/// on [CanonicalPaginationSourceSlice] and never enter the signature.
abstract final class CanonicalReaderCardIdentityBuilder {
  static ReaderCardIdentity build({
    required String publicationFingerprint,
    required String controlledLayoutIdentity,
    required String paginationAlgorithmIdentity,
    required List<CanonicalPaginationSourceSlice> orderedSourceSlices,
  }) {
    if (orderedSourceSlices.isEmpty) {
      throw const FormatException(
        'A finalized canonical card requires stable structural ownership.',
      );
    }
    final first = orderedSourceSlices.first;
    var previousOrdinal = -1;
    CanonicalPaginationSourceSlice? previous;
    for (final slice in orderedSourceSlices) {
      _validateSlice(slice);
      if (slice.sectionIdentity != first.sectionIdentity ||
          slice.spineIdentity != first.spineIdentity) {
        throw const FormatException(
          'A physical card cannot own content across a section/spine seam.',
        );
      }
      if (slice.sourceOrdinalHint < previousOrdinal) {
        throw const FormatException(
          'Canonical structural owners are not in source order.',
        );
      }
      final prior = previous;
      if (prior != null &&
          prior.sourceIdentity == slice.sourceIdentity &&
          prior.logicalOwnerIdentity == slice.logicalOwnerIdentity) {
        final textAdjacent =
            prior.endUtf16 != null &&
            slice.startUtf16 != null &&
            prior.endUtf16 == slice.startUtf16;
        final rowAdjacent =
            prior.tableRowEndExclusive != null &&
            slice.tableRowStart != null &&
            prior.tableRowEndExclusive == slice.tableRowStart;
        if (!textAdjacent && !rowAdjacent) {
          throw const FormatException(
            'Adjacent fragments of one owner must meet without a gap or overlap.',
          );
        }
      }
      previousOrdinal = slice.sourceOrdinalHint;
      previous = slice;
    }

    return ReaderCardIdentity(
      publicationFingerprint: publicationFingerprint,
      layoutFingerprint: controlledLayoutIdentity,
      paginationVersion: paginationAlgorithmIdentity,
      ranges: <ReaderCardSourceRange>[
        for (final slice in orderedSourceSlices)
          ReaderCardSourceRange(
            sectionIdentity: slice.sectionIdentity,
            sectionChecksum: slice.sourceDigest,
            logicalBlockId: slice.logicalOwnerIdentity,
            structuralType: slice.structuralType,
            startUtf16: slice.startUtf16,
            endUtf16: slice.endUtf16,
            contentChecksum: slice.startUtf16 == null
                ? slice.sourceDigest
                : null,
            sourceIdentity: slice.sourceIdentity,
            spineIdentity: slice.spineIdentity,
            structuralDigest: slice.structuralDigest,
            fragmentDigest: slice.fragmentDigest,
            publisherLayoutDigest: slice.publisherLayoutDigest,
            richMetadataDigest: slice.richMetadataDigest,
            listFragmentDigest: slice.listFragmentDigest,
            splitBoundaryKind: slice.splitBoundaryKind,
            isLogicalParagraphStart: slice.isLogicalParagraphStart,
            isLogicalParagraphEnd: slice.isLogicalParagraphEnd,
            usesExplicitTextFragment: slice.usesExplicitTextFragment,
            tableRowStart: slice.tableRowStart,
            tableRowEndExclusive: slice.tableRowEndExclusive,
            structuralOwnerRole: slice.structuralOwnerRole,
          ),
      ],
    );
  }

  static void _validateSlice(CanonicalPaginationSourceSlice slice) {
    if (slice.sourceIdentity.isEmpty ||
        slice.sectionIdentity.isEmpty ||
        slice.spineIdentity.isEmpty ||
        slice.sourceDigest.isEmpty ||
        slice.structuralType.isEmpty ||
        slice.structuralOwnerRole.isEmpty ||
        slice.logicalOwnerIdentity.isEmpty ||
        slice.structuralDigest.isEmpty ||
        slice.fragmentDigest.isEmpty ||
        slice.publisherLayoutDigest.isEmpty ||
        slice.richMetadataDigest.isEmpty ||
        slice.listFragmentDigest.isEmpty ||
        slice.splitBoundaryKind.isEmpty ||
        slice.sourceOrdinalHint < 0) {
      throw const FormatException(
        'Canonical structural ownership is incomplete.',
      );
    }
    final hasText = slice.startUtf16 != null || slice.endUtf16 != null;
    final hasRows =
        slice.tableRowStart != null || slice.tableRowEndExclusive != null;
    if (hasText == hasRows &&
        !(slice.startUtf16 == null &&
            slice.endUtf16 == null &&
            slice.tableRowStart == null &&
            slice.tableRowEndExclusive == null)) {
      throw const FormatException('Canonical interval kind is ambiguous.');
    }
    if (hasText &&
        (slice.startUtf16 == null ||
            slice.endUtf16 == null ||
            slice.startUtf16! < 0 ||
            slice.endUtf16! <= slice.startUtf16!)) {
      throw const FormatException('Canonical UTF-16 interval is invalid.');
    }
    if (hasRows &&
        (slice.tableRowStart == null ||
            slice.tableRowEndExclusive == null ||
            slice.tableRowStart! < 0 ||
            slice.tableRowEndExclusive! <= slice.tableRowStart! ||
            slice.structuralType != 'table')) {
      throw const FormatException('Canonical table-row interval is invalid.');
    }
    if (!hasText &&
        !hasRows &&
        slice.structuralType != 'image' &&
        slice.structuralType != 'synthetic:milestone') {
      throw const FormatException(
        'Only intrinsic nontext/generated owners may omit an interval.',
      );
    }
    if (slice.structuralType == 'synthetic:milestone' &&
        slice.structuralOwnerRole != 'generated:milestone') {
      throw const FormatException(
        'Generated structural ownership contradicts its type.',
      );
    }
  }
}

/// Reconstructable unpublished card candidate. It contains no card identity
/// and no copied source text.
@immutable
final class CanonicalPaginationFrontierCandidate {
  CanonicalPaginationFrontierCandidate({
    required List<CanonicalPaginationSourceSlice> sourceSlices,
    required this.reconstructedCardDigest,
  }) : sourceSlices = List<CanonicalPaginationSourceSlice>.unmodifiable(
         sourceSlices,
       );

  final List<CanonicalPaginationSourceSlice> sourceSlices;
  final String reconstructedCardDigest;

  int get referencedUtf16Extent => sourceSlices.fold<int>(
    0,
    (total, slice) => total + slice.referencedUtf16Extent,
  );

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'sourceSlices': sourceSlices
        .map((slice) => slice.toCanonicalJson())
        .toList(growable: false),
    'reconstructedCardDigest': reconstructedCardDigest,
  };
}

@immutable
final class CanonicalPaginationFrontier {
  const CanonicalPaginationFrontier({
    this.deferredPredecessor,
    this.pendingTail,
  });

  final CanonicalPaginationFrontierCandidate? deferredPredecessor;
  final CanonicalPaginationFrontierCandidate? pendingTail;

  int get cardCandidateCount =>
      (deferredPredecessor == null ? 0 : 1) + (pendingTail == null ? 0 : 1);

  int get structuralEntryCount => <CanonicalPaginationSourceSlice>[
    ...?deferredPredecessor?.sourceSlices,
    ...?pendingTail?.sourceSlices,
  ].length;

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'deferredPredecessor': deferredPredecessor?.toCanonicalJson(),
    'pendingTail': pendingTail?.toCanonicalJson(),
  };
}

@immutable
final class CanonicalPaginationWorkBudget {
  const CanonicalPaginationWorkBudget({
    this.maxSourceChunks = CanonicalPaginationBounds.checkpointSourceStride,
    this.maxAtomicFragments = CanonicalPaginationBounds.normalWorkEnvelope,
    this.maxFinalizedCards = CanonicalPaginationBounds.checkpointCardStride,
    this.maxFrontierEntries,
    this.envelope = CanonicalPaginationWorkEnvelope.normal,
  });

  final int maxSourceChunks;
  final int maxAtomicFragments;
  final int maxFinalizedCards;
  final CanonicalPaginationWorkEnvelope envelope;

  /// A caller may request a stricter cap, but never a weaker one.
  final int? maxFrontierEntries;
}

enum CanonicalPaginationWorkEnvelope {
  normal(CanonicalPaginationBounds.normalWorkEnvelope),
  recovery(CanonicalPaginationBounds.recoveryWorkEnvelope);

  const CanonicalPaginationWorkEnvelope(this.maxEntries);

  final int maxEntries;
}

@immutable
final class CanonicalPaginationWorkDiagnostics {
  const CanonicalPaginationWorkDiagnostics({
    this.sourceChunksEntered = 0,
    this.sourceChunksFullyConsumed = 0,
    this.atomicFragmentsProcessed = 0,
    this.referencedUtf16Extent = 0,
    this.tableRows = 0,
    this.graphemeCandidates = 0,
    this.rebalanceCandidates = 0,
    this.cardsFinalized = 0,
    this.privatePredecessorCardsDiscarded = 0,
    this.frontierEntries = 0,
    this.peakFrontierEntries = 0,
    this.peakPrivateFrontierBytes = 0,
    this.cancellationCheckpoints = 0,
    this.schedulerSlices = 0,
    this.schedulerYields = 0,
  });

  final int sourceChunksEntered;
  final int sourceChunksFullyConsumed;
  final int atomicFragmentsProcessed;
  final int referencedUtf16Extent;
  final int tableRows;
  final int graphemeCandidates;
  final int rebalanceCandidates;
  final int cardsFinalized;
  final int privatePredecessorCardsDiscarded;
  final int frontierEntries;
  final int peakFrontierEntries;
  final int peakPrivateFrontierBytes;
  final int cancellationCheckpoints;
  final int schedulerSlices;
  final int schedulerYields;
}

sealed class CanonicalPaginationRestart {
  const CanonicalPaginationRestart();
}

final class CanonicalPaginationPublicationStart
    extends CanonicalPaginationRestart {
  const CanonicalPaginationPublicationStart();
}

@immutable
final class CanonicalPaginationTrustedSectionStart
    extends CanonicalPaginationRestart {
  const CanonicalPaginationTrustedSectionStart({
    required this.sectionIdentity,
    required this.sourceIdentity,
    required this.sourceOrdinalHint,
  });

  final String sectionIdentity;
  final String sourceIdentity;
  final int sourceOrdinalHint;
}

enum CanonicalPaginationContinuationContractKind {
  canonicalPaginationContinuationV1,
}

enum CanonicalPaginationCheckpointReason {
  requestExhaustedProvisional,
  sourceCadence,
  cardCadence,
  sectionBoundary,
  targetSatisfied,
  terminalBookEnd,
}

enum CanonicalPaginationBoundaryKind {
  publicationStart,
  sectionStart,
  finalizedCard,
}

/// Stable lookup key. Every field is authoritative and must exactly match the
/// pinned publication/parser snapshot, pagination algorithm, layout, section,
/// and checkpoint boundary. No display, window, controller, or cache index is
/// present or accepted as a substitute.
@immutable
final class CanonicalPaginationContinuationKey {
  const CanonicalPaginationContinuationKey({
    required this.bookId,
    required this.publicationFingerprint,
    required this.parserSourceIdentity,
    required this.sourceRevision,
    required this.sourceSnapshotDigest,
    required this.paginationAlgorithmIdentity,
    required this.controlledLayoutIdentity,
    required this.sectionIdentity,
    required this.boundaryCursor,
  });

  final String bookId;
  final String publicationFingerprint;
  final String parserSourceIdentity;
  final String sourceRevision;
  final String sourceSnapshotDigest;
  final String paginationAlgorithmIdentity;
  final String controlledLayoutIdentity;
  final String sectionIdentity;
  final CanonicalPaginationCursor boundaryCursor;

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'bookId': bookId,
    'publicationFingerprint': publicationFingerprint,
    'parserSourceIdentity': parserSourceIdentity,
    'sourceRevision': sourceRevision,
    'sourceSnapshotDigest': sourceSnapshotDigest,
    'paginationAlgorithmIdentity': paginationAlgorithmIdentity,
    'controlledLayoutIdentity': controlledLayoutIdentity,
    'sectionIdentity': sectionIdentity,
    'boundaryCursor': boundaryCursor.toCanonicalJson(),
  };

  String get stableDigest => readerSha256(toCanonicalJson());
}

@immutable
final class CanonicalPaginationFinalizedBoundary {
  const CanonicalPaginationFinalizedBoundary({
    required this.kind,
    required this.endCursor,
    required this.cardIdentity,
  });

  final CanonicalPaginationBoundaryKind kind;
  final CanonicalPaginationCursor endCursor;
  final ReaderCardIdentity? cardIdentity;

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    'kind': kind.name,
    'endCursor': endCursor.toCanonicalJson(),
    'cardIdentity': cardIdentity?.toJson(),
  };
}

/// The sole canonical pagination continuation representation.
///
/// It contains stable descriptors only. In particular it copies no source
/// text and contains no display/window/controller indexes, rendered cards,
/// cache paths, or generation/scheduler counters.
@immutable
final class CanonicalPaginationContinuation extends CanonicalPaginationRestart {
  const CanonicalPaginationContinuation._({
    required this.contractKind,
    required this.key,
    required this.startSourceCursor,
    required this.nextSourceCursor,
    required this.frontier,
    required this.previousFinalizedBoundary,
    required this.chainOrdinal,
    required this.parentDigest,
    required this.checkpointReason,
    required this.sourcesSinceCheckpoint,
    required this.cardsSinceCheckpoint,
    required this.terminal,
    required this.integrityDigest,
  });

  factory CanonicalPaginationContinuation.create({
    required CanonicalPaginationContinuationKey key,
    required CanonicalPaginationCursor startSourceCursor,
    required CanonicalPaginationCursor nextSourceCursor,
    required CanonicalPaginationFrontier frontier,
    required CanonicalPaginationFinalizedBoundary previousFinalizedBoundary,
    required int chainOrdinal,
    required String? parentDigest,
    required CanonicalPaginationCheckpointReason checkpointReason,
    required int sourcesSinceCheckpoint,
    required int cardsSinceCheckpoint,
    required bool terminal,
  }) {
    final payload = _continuationPayload(
      contractKind: CanonicalPaginationContinuationContractKind
          .canonicalPaginationContinuationV1,
      key: key,
      startSourceCursor: startSourceCursor,
      nextSourceCursor: nextSourceCursor,
      frontier: frontier,
      previousFinalizedBoundary: previousFinalizedBoundary,
      chainOrdinal: chainOrdinal,
      parentDigest: parentDigest,
      checkpointReason: checkpointReason,
      sourcesSinceCheckpoint: sourcesSinceCheckpoint,
      cardsSinceCheckpoint: cardsSinceCheckpoint,
      terminal: terminal,
    );
    return CanonicalPaginationContinuation._(
      contractKind: CanonicalPaginationContinuationContractKind
          .canonicalPaginationContinuationV1,
      key: key,
      startSourceCursor: startSourceCursor,
      nextSourceCursor: nextSourceCursor,
      frontier: frontier,
      previousFinalizedBoundary: previousFinalizedBoundary,
      chainOrdinal: chainOrdinal,
      parentDigest: parentDigest,
      checkpointReason: checkpointReason,
      sourcesSinceCheckpoint: sourcesSinceCheckpoint,
      cardsSinceCheckpoint: cardsSinceCheckpoint,
      terminal: terminal,
      integrityDigest: readerSha256(payload),
    );
  }

  final CanonicalPaginationContinuationContractKind contractKind;
  final CanonicalPaginationContinuationKey key;
  final CanonicalPaginationCursor startSourceCursor;
  final CanonicalPaginationCursor nextSourceCursor;
  final CanonicalPaginationFrontier frontier;
  final CanonicalPaginationFinalizedBoundary previousFinalizedBoundary;
  final int chainOrdinal;
  final String? parentDigest;
  final CanonicalPaginationCheckpointReason checkpointReason;
  final int sourcesSinceCheckpoint;
  final int cardsSinceCheckpoint;
  final bool terminal;
  final String integrityDigest;

  int get copiedSourceTextUtf16 => 0;

  Map<String, Object?> payloadJson() => _continuationPayload(
    contractKind: contractKind,
    key: key,
    startSourceCursor: startSourceCursor,
    nextSourceCursor: nextSourceCursor,
    frontier: frontier,
    previousFinalizedBoundary: previousFinalizedBoundary,
    chainOrdinal: chainOrdinal,
    parentDigest: parentDigest,
    checkpointReason: checkpointReason,
    sourcesSinceCheckpoint: sourcesSinceCheckpoint,
    cardsSinceCheckpoint: cardsSinceCheckpoint,
    terminal: terminal,
  );

  Map<String, Object?> toCanonicalJson() => <String, Object?>{
    ...payloadJson(),
    'integrityDigest': integrityDigest,
  };

  String get canonicalEncoding => canonicalJsonEncode(toCanonicalJson());
}

Map<String, Object?> _continuationPayload({
  required CanonicalPaginationContinuationContractKind contractKind,
  required CanonicalPaginationContinuationKey key,
  required CanonicalPaginationCursor startSourceCursor,
  required CanonicalPaginationCursor nextSourceCursor,
  required CanonicalPaginationFrontier frontier,
  required CanonicalPaginationFinalizedBoundary previousFinalizedBoundary,
  required int chainOrdinal,
  required String? parentDigest,
  required CanonicalPaginationCheckpointReason checkpointReason,
  required int sourcesSinceCheckpoint,
  required int cardsSinceCheckpoint,
  required bool terminal,
}) => <String, Object?>{
  'contractKind': contractKind.name,
  'key': key.toCanonicalJson(),
  'startSourceCursor': startSourceCursor.toCanonicalJson(),
  'nextSourceCursor': nextSourceCursor.toCanonicalJson(),
  'frontier': frontier.toCanonicalJson(),
  'previousFinalizedBoundary': previousFinalizedBoundary.toCanonicalJson(),
  'chainOrdinal': chainOrdinal,
  'parentDigest': parentDigest,
  'checkpointReason': checkpointReason.name,
  'sourcesSinceCheckpoint': sourcesSinceCheckpoint,
  'cardsSinceCheckpoint': cardsSinceCheckpoint,
  'terminal': terminal,
};

enum CanonicalPaginationContinuationValidationKind {
  accepted,
  unsupportedContractKind,
  corruptDigest,
  incompatiblePublication,
  incompatibleParserSourceSnapshot,
  incompatiblePaginationIdentity,
  incompatibleLayout,
  invalidSectionSourceOwner,
  invalidCursorOffsetRowInterval,
  invalidFrontier,
  brokenParentChain,
  ordinalMismatch,
  staleForkReplay,
  terminalStateContradiction,
  boundViolation,
  requiredEarlierRestart,
}

sealed class CanonicalPaginationContinuationValidationResult {
  const CanonicalPaginationContinuationValidationResult();

  CanonicalPaginationContinuationValidationKind get kind;
}

final class CanonicalPaginationContinuationAccepted
    extends CanonicalPaginationContinuationValidationResult {
  const CanonicalPaginationContinuationAccepted(this.continuation);

  final CanonicalPaginationContinuation continuation;

  @override
  CanonicalPaginationContinuationValidationKind get kind =>
      CanonicalPaginationContinuationValidationKind.accepted;
}

final class CanonicalPaginationContinuationRejected
    extends CanonicalPaginationContinuationValidationResult {
  const CanonicalPaginationContinuationRejected({
    required this.kind,
    required this.message,
  });

  @override
  final CanonicalPaginationContinuationValidationKind kind;
  final String message;

  List<CanonicalFinalizedReaderCard> get publishableCards => const [];
  bool get hasAcceptedRestartAuthority => false;
  bool get hasCacheWriteAuthority => false;
  bool get hasPartiallyInsertedCheckpoint => false;
}

/// Strict, deterministic in-memory codec. Decoding accepts only the exact
/// canonical byte representation, so duplicate keys, reordered/unknown keys,
/// permissive numeric coercions, and silent defaults cannot survive.
abstract final class CanonicalPaginationContinuationCodec {
  static String encode(CanonicalPaginationContinuation continuation) =>
      continuation.canonicalEncoding;

  static CanonicalPaginationContinuationValidationResult decode(
    String encoded,
  ) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.invalidFrontier,
          'Continuation root must be a map.',
        );
      }
      final root = Map<String, Object?>.from(decoded);
      final rawKind = root['contractKind'];
      if (rawKind !=
          CanonicalPaginationContinuationContractKind
              .canonicalPaginationContinuationV1
              .name) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.unsupportedContractKind,
          'Unsupported canonical continuation contract kind.',
        );
      }
      _expectKeys(root, const <String>{
        'contractKind',
        'key',
        'startSourceCursor',
        'nextSourceCursor',
        'frontier',
        'previousFinalizedBoundary',
        'chainOrdinal',
        'parentDigest',
        'checkpointReason',
        'sourcesSinceCheckpoint',
        'cardsSinceCheckpoint',
        'terminal',
        'integrityDigest',
      });
      if (canonicalJsonEncode(root) != encoded) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.invalidFrontier,
          'Continuation bytes are not the canonical encoding.',
        );
      }
      final digest = _requiredString(root, 'integrityDigest');
      final payload = Map<String, Object?>.from(root)
        ..remove('integrityDigest');
      if (readerSha256(payload) != digest) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.corruptDigest,
          'Continuation integrity digest does not cover the supplied payload.',
        );
      }

      final key = _decodeKey(_requiredMap(root, 'key'));
      final startCursor = _decodeCursor(
        _requiredMap(root, 'startSourceCursor'),
      );
      final nextCursor = _decodeCursor(_requiredMap(root, 'nextSourceCursor'));
      final frontier = _decodeFrontier(_requiredMap(root, 'frontier'));
      final boundary = _decodeBoundary(
        _requiredMap(root, 'previousFinalizedBoundary'),
      );
      final ordinal = _requiredInt(root, 'chainOrdinal');
      final parentValue = root['parentDigest'];
      if (parentValue != null && parentValue is! String) {
        throw const FormatException('parentDigest must be null or a string.');
      }
      final reason = _enumByName(
        CanonicalPaginationCheckpointReason.values,
        _requiredString(root, 'checkpointReason'),
        'checkpointReason',
      );
      final sources = _requiredInt(root, 'sourcesSinceCheckpoint');
      final cards = _requiredInt(root, 'cardsSinceCheckpoint');
      final terminal = _requiredBool(root, 'terminal');
      if (ordinal < 0 ||
          sources < 0 ||
          sources > CanonicalPaginationBounds.checkpointSourceStride ||
          cards < 0 ||
          cards > CanonicalPaginationBounds.checkpointCardStride ||
          frontier.cardCandidateCount > 2 ||
          frontier.structuralEntryCount >
              CanonicalPaginationBounds.standardFrontierEntryCap) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.boundViolation,
          'Continuation ordinal, cadence, or frontier bound is invalid.',
        );
      }
      if ((ordinal == 0) != (parentValue == null)) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.brokenParentChain,
          'Only a root ordinal may omit its parent digest.',
        );
      }
      final cadenceContradiction = switch (reason) {
        CanonicalPaginationCheckpointReason.requestExhaustedProvisional =>
          sources >= CanonicalPaginationBounds.checkpointSourceStride ||
              cards >= CanonicalPaginationBounds.checkpointCardStride,
        CanonicalPaginationCheckpointReason.sourceCadence =>
          sources != CanonicalPaginationBounds.checkpointSourceStride,
        CanonicalPaginationCheckpointReason.cardCadence =>
          cards != CanonicalPaginationBounds.checkpointCardStride,
        _ => false,
      };
      if (cadenceContradiction) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind.boundViolation,
          'Checkpoint reason contradicts its cadence counters.',
        );
      }
      if (terminal !=
              (reason == CanonicalPaginationCheckpointReason.terminalBookEnd) ||
          terminal != nextCursor.isLogicalEnd ||
          (terminal && frontier.cardCandidateCount != 0)) {
        return _rejected(
          CanonicalPaginationContinuationValidationKind
              .terminalStateContradiction,
          'Terminal evidence contradicts the cursor, frontier, or reason.',
        );
      }
      final continuation = CanonicalPaginationContinuation._(
        contractKind: CanonicalPaginationContinuationContractKind
            .canonicalPaginationContinuationV1,
        key: key,
        startSourceCursor: startCursor,
        nextSourceCursor: nextCursor,
        frontier: frontier,
        previousFinalizedBoundary: boundary,
        chainOrdinal: ordinal,
        parentDigest: parentValue as String?,
        checkpointReason: reason,
        sourcesSinceCheckpoint: sources,
        cardsSinceCheckpoint: cards,
        terminal: terminal,
        integrityDigest: digest,
      );
      return CanonicalPaginationContinuationAccepted(continuation);
    } on FormatException catch (error) {
      return _rejected(
        CanonicalPaginationContinuationValidationKind.invalidFrontier,
        error.message,
      );
    } on Object catch (error) {
      return _rejected(
        CanonicalPaginationContinuationValidationKind.invalidFrontier,
        'Malformed canonical continuation: $error',
      );
    }
  }

  static CanonicalPaginationContinuationRejected _rejected(
    CanonicalPaginationContinuationValidationKind kind,
    String message,
  ) => CanonicalPaginationContinuationRejected(kind: kind, message: message);

  static CanonicalPaginationContinuationKey _decodeKey(
    Map<String, Object?> json,
  ) {
    _expectKeys(json, const <String>{
      'bookId',
      'publicationFingerprint',
      'parserSourceIdentity',
      'sourceRevision',
      'sourceSnapshotDigest',
      'paginationAlgorithmIdentity',
      'controlledLayoutIdentity',
      'sectionIdentity',
      'boundaryCursor',
    });
    return CanonicalPaginationContinuationKey(
      bookId: _requiredString(json, 'bookId'),
      publicationFingerprint: _requiredString(json, 'publicationFingerprint'),
      parserSourceIdentity: _requiredString(json, 'parserSourceIdentity'),
      sourceRevision: _requiredString(json, 'sourceRevision'),
      sourceSnapshotDigest: _requiredString(json, 'sourceSnapshotDigest'),
      paginationAlgorithmIdentity: _requiredString(
        json,
        'paginationAlgorithmIdentity',
      ),
      controlledLayoutIdentity: _requiredString(
        json,
        'controlledLayoutIdentity',
      ),
      sectionIdentity: _requiredString(json, 'sectionIdentity'),
      boundaryCursor: _decodeCursor(_requiredMap(json, 'boundaryCursor')),
    );
  }

  static CanonicalPaginationCursor _decodeCursor(Map<String, Object?> json) {
    _expectKeys(json, const <String>{
      'kind',
      'sourceIdentity',
      'sectionIdentity',
      'sourceOrdinalHint',
      'textOffsetUtf16',
      'tableRowIndex',
    });
    final kind = _enumByName(
      CanonicalPaginationCursorKind.values,
      _requiredString(json, 'kind'),
      'cursor kind',
    );
    final cursor = CanonicalPaginationCursor(
      kind: kind,
      sourceIdentity: _requiredString(json, 'sourceIdentity', allowEmpty: true),
      sectionIdentity: _requiredString(
        json,
        'sectionIdentity',
        allowEmpty: true,
      ),
      sourceOrdinalHint: _requiredInt(json, 'sourceOrdinalHint'),
      textOffsetUtf16: _requiredInt(json, 'textOffsetUtf16'),
      tableRowIndex: _requiredInt(json, 'tableRowIndex'),
    );
    if (kind == CanonicalPaginationCursorKind.end) {
      if (!cursor.samePositionAs(
        const CanonicalPaginationCursor.logicalEnd(),
      )) {
        throw const FormatException('Logical-end cursor has extra authority.');
      }
    } else if (cursor.sourceIdentity.isEmpty ||
        cursor.sectionIdentity.isEmpty ||
        cursor.sourceOrdinalHint < 0 ||
        cursor.textOffsetUtf16 < 0 ||
        cursor.tableRowIndex < 0) {
      throw const FormatException('Cursor identity or offset is invalid.');
    }
    return cursor;
  }

  static CanonicalPaginationFrontier _decodeFrontier(
    Map<String, Object?> json,
  ) {
    _expectKeys(json, const <String>{'deferredPredecessor', 'pendingTail'});
    CanonicalPaginationFrontierCandidate? candidate(String name) {
      final value = json[name];
      if (value == null) return null;
      if (value is! Map) throw FormatException('$name must be a map or null.');
      final map = Map<String, Object?>.from(value);
      _expectKeys(map, const <String>{
        'sourceSlices',
        'reconstructedCardDigest',
      });
      final slices = _requiredList(map, 'sourceSlices')
          .map((value) {
            if (value is! Map) {
              throw const FormatException('Source slice must be a map.');
            }
            return _decodeSlice(Map<String, Object?>.from(value));
          })
          .toList(growable: false);
      if (slices.isEmpty) {
        throw const FormatException('Frontier candidate cannot be empty.');
      }
      return CanonicalPaginationFrontierCandidate(
        sourceSlices: slices,
        reconstructedCardDigest: _requiredString(
          map,
          'reconstructedCardDigest',
        ),
      );
    }

    return CanonicalPaginationFrontier(
      deferredPredecessor: candidate('deferredPredecessor'),
      pendingTail: candidate('pendingTail'),
    );
  }

  static CanonicalPaginationSourceSlice _decodeSlice(
    Map<String, Object?> json,
  ) {
    _expectKeys(json, const <String>{
      'sourceIdentity',
      'sectionIdentity',
      'spineIdentity',
      'sourceOrdinalHint',
      'sourceDigest',
      'structuralType',
      'structuralOwnerRole',
      'logicalOwnerIdentity',
      'structuralDigest',
      'fragmentDigest',
      'publisherLayoutDigest',
      'richMetadataDigest',
      'listFragmentDigest',
      'splitBoundaryKind',
      'isLogicalParagraphStart',
      'isLogicalParagraphEnd',
      'usesExplicitTextFragment',
      'startUtf16',
      'endUtf16',
      'tableRowStart',
      'tableRowEndExclusive',
    });
    final start = _optionalInt(json, 'startUtf16');
    final end = _optionalInt(json, 'endUtf16');
    final rowStart = _optionalInt(json, 'tableRowStart');
    final rowEnd = _optionalInt(json, 'tableRowEndExclusive');
    if ((start == null) != (end == null) ||
        (rowStart == null) != (rowEnd == null) ||
        (start != null && rowStart != null)) {
      throw const FormatException('Slice interval kind is ambiguous.');
    }
    return CanonicalPaginationSourceSlice(
      sourceIdentity: _requiredString(json, 'sourceIdentity'),
      sectionIdentity: _requiredString(json, 'sectionIdentity'),
      spineIdentity: _requiredString(json, 'spineIdentity'),
      sourceOrdinalHint: _requiredInt(json, 'sourceOrdinalHint'),
      sourceDigest: _requiredString(json, 'sourceDigest'),
      structuralType: _requiredString(json, 'structuralType'),
      structuralOwnerRole: _requiredString(json, 'structuralOwnerRole'),
      logicalOwnerIdentity: _requiredString(json, 'logicalOwnerIdentity'),
      structuralDigest: _requiredString(json, 'structuralDigest'),
      fragmentDigest: _requiredString(json, 'fragmentDigest'),
      publisherLayoutDigest: _requiredString(json, 'publisherLayoutDigest'),
      richMetadataDigest: _requiredString(json, 'richMetadataDigest'),
      listFragmentDigest: _requiredString(json, 'listFragmentDigest'),
      splitBoundaryKind: _requiredString(json, 'splitBoundaryKind'),
      isLogicalParagraphStart: _requiredBool(json, 'isLogicalParagraphStart'),
      isLogicalParagraphEnd: _requiredBool(json, 'isLogicalParagraphEnd'),
      usesExplicitTextFragment: _requiredBool(json, 'usesExplicitTextFragment'),
      startUtf16: start,
      endUtf16: end,
      tableRowStart: rowStart,
      tableRowEndExclusive: rowEnd,
    );
  }

  static CanonicalPaginationFinalizedBoundary _decodeBoundary(
    Map<String, Object?> json,
  ) {
    _expectKeys(json, const <String>{'kind', 'endCursor', 'cardIdentity'});
    final kind = _enumByName(
      CanonicalPaginationBoundaryKind.values,
      _requiredString(json, 'kind'),
      'boundary kind',
    );
    final rawCard = json['cardIdentity'];
    if (rawCard != null && rawCard is! Map) {
      throw const FormatException('cardIdentity must be a map or null.');
    }
    final card = rawCard == null
        ? null
        : _decodeCardIdentity(Map<String, Object?>.from(rawCard as Map));
    if ((kind == CanonicalPaginationBoundaryKind.finalizedCard) !=
        (card != null)) {
      throw const FormatException('Boundary/card identity is contradictory.');
    }
    return CanonicalPaginationFinalizedBoundary(
      kind: kind,
      endCursor: _decodeCursor(_requiredMap(json, 'endCursor')),
      cardIdentity: card,
    );
  }

  static ReaderCardIdentity _decodeCardIdentity(Map<String, Object?> json) {
    _expectKeys(json, const <String>{
      'publicationFingerprint',
      'layoutFingerprint',
      'paginationVersion',
      'ranges',
      'signature',
    });
    _requiredString(json, 'publicationFingerprint');
    _requiredString(json, 'layoutFingerprint');
    _requiredString(json, 'paginationVersion');
    _requiredString(json, 'signature');
    final ranges = _requiredList(json, 'ranges');
    if (ranges.isEmpty) {
      throw const FormatException('Finalized card identity needs a range.');
    }
    for (final value in ranges) {
      if (value is! Map) {
        throw const FormatException('Card source range must be a map.');
      }
      final range = Map<String, Object?>.from(value);
      final expected = <String>{
        'sectionIdentity',
        'sectionChecksum',
        'logicalBlockId',
        'structuralType',
        'startUtf16',
        'endUtf16',
        if (range.containsKey('contentChecksum')) 'contentChecksum',
      };
      const canonicalOwnershipKeys = <String>{
        'sourceIdentity',
        'spineIdentity',
        'structuralDigest',
        'fragmentDigest',
        'publisherLayoutDigest',
        'richMetadataDigest',
        'listFragmentDigest',
        'splitBoundaryKind',
        'isLogicalParagraphStart',
        'isLogicalParagraphEnd',
        'usesExplicitTextFragment',
        'structuralOwnerRole',
      };
      const canonicalRelatedKeys = <String>{
        ...canonicalOwnershipKeys,
        'tableRowStart',
        'tableRowEndExclusive',
      };
      final hasCanonicalOwnership = range.containsKey('sourceIdentity');
      if (range.keys.any(canonicalRelatedKeys.contains) !=
          hasCanonicalOwnership) {
        throw const FormatException(
          'Card structural ownership is partial or contradictory.',
        );
      }
      if (hasCanonicalOwnership) expected.addAll(canonicalOwnershipKeys);
      final hasRowStart = range.containsKey('tableRowStart');
      final hasRowEnd = range.containsKey('tableRowEndExclusive');
      if (hasRowStart != hasRowEnd) {
        throw const FormatException(
          'Card table-row ownership is partial or contradictory.',
        );
      }
      if (hasRowStart) {
        expected.addAll(const <String>{
          'tableRowStart',
          'tableRowEndExclusive',
        });
      }
      _expectKeys(range, expected);
      _requiredString(range, 'sectionIdentity');
      _requiredString(range, 'sectionChecksum');
      _requiredString(range, 'logicalBlockId');
      _requiredString(range, 'structuralType');
      final start = _optionalInt(range, 'startUtf16');
      final end = _optionalInt(range, 'endUtf16');
      if ((start == null) != (end == null) ||
          (start != null && (start < 0 || end! <= start))) {
        throw const FormatException('Card source range is invalid.');
      }
      if (range.containsKey('contentChecksum')) {
        _requiredString(range, 'contentChecksum');
      }
      if (hasCanonicalOwnership) {
        for (final field in const <String>[
          'sourceIdentity',
          'spineIdentity',
          'structuralDigest',
          'fragmentDigest',
          'publisherLayoutDigest',
          'richMetadataDigest',
          'listFragmentDigest',
          'splitBoundaryKind',
          'structuralOwnerRole',
        ]) {
          _requiredString(range, field);
        }
        _requiredBool(range, 'isLogicalParagraphStart');
        _requiredBool(range, 'isLogicalParagraphEnd');
        _requiredBool(range, 'usesExplicitTextFragment');
        final rowStart = _optionalInt(range, 'tableRowStart');
        final rowEnd = _optionalInt(range, 'tableRowEndExclusive');
        if ((rowStart == null) != (rowEnd == null) ||
            (rowStart != null && (rowStart < 0 || rowEnd! <= rowStart)) ||
            (rowStart != null && start != null) ||
            ((rowStart != null) != (range['structuralType'] == 'table')) ||
            ((start == null && rowStart == null) !=
                (range['structuralType'] == 'image' ||
                    range['structuralType'] == 'synthetic:milestone')) ||
            (range['structuralType'] == 'synthetic:milestone' &&
                range['structuralOwnerRole'] != 'generated:milestone')) {
          throw const FormatException(
            'Card structural interval is contradictory.',
          );
        }
      }
    }
    final identity = ReaderCardIdentity.fromJson(json);
    if (canonicalJsonEncode(identity.toJson()) != canonicalJsonEncode(json)) {
      throw const FormatException(
        'Card identity contains noncanonical or permissive values.',
      );
    }
    return identity;
  }

  static void _expectKeys(Map<String, Object?> json, Set<String> expected) {
    if (json.keys.toSet().length != json.length ||
        json.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException('Missing, unknown, or duplicate map key.');
    }
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map) throw FormatException('$key must be a map.');
    return Map<String, Object?>.from(value);
  }

  static List<Object?> _requiredList(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! List) throw FormatException('$key must be a list.');
    return List<Object?>.from(value);
  }

  static String _requiredString(
    Map<String, Object?> json,
    String key, {
    bool allowEmpty = false,
  }) {
    final value = json[key];
    if (value is! String || (!allowEmpty && value.isEmpty)) {
      throw FormatException('$key must be a nonempty string.');
    }
    return value;
  }

  static int _requiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) throw FormatException('$key must be an integer.');
    return value;
  }

  static int? _optionalInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! int) throw FormatException('$key must be null or integer.');
    return value;
  }

  static bool _requiredBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! bool) throw FormatException('$key must be a boolean.');
    return value;
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String name,
    String field,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('Unknown $field.');
  }
}

@immutable
final class CanonicalPaginationTargetCursor {
  const CanonicalPaginationTargetCursor({
    required this.sourceIdentity,
    required this.sectionIdentity,
    required this.sourceOrdinalHint,
    required this.textOffsetUtf16,
  });

  final String sourceIdentity;
  final String sectionIdentity;
  final int sourceOrdinalHint;
  final int textOffsetUtf16;
}

@immutable
final class CanonicalPaginationTargetContainmentEvidence {
  const CanonicalPaginationTargetContainmentEvidence({
    required this.target,
    required this.cardIdentity,
    required this.containingSlice,
    required this.offsetWithinSliceUtf16,
  });

  final CanonicalPaginationTargetCursor target;
  final ReaderCardIdentity cardIdentity;
  final CanonicalPaginationSourceSlice containingSlice;
  final int offsetWithinSliceUtf16;
}

@immutable
final class CanonicalFinalizedReaderCard {
  CanonicalFinalizedReaderCard({
    required BookChunk card,
    required this.identity,
    required List<CanonicalPaginationSourceSlice> sourceSlices,
    this.resolvedLayout,
  }) : card = BookChunk.fromJson(
         Map<String, dynamic>.from(
           jsonDecode(canonicalJsonEncode(card.toJson())) as Map,
         ),
       ),
       sourceSlices = List<CanonicalPaginationSourceSlice>.unmodifiable(
         sourceSlices,
       );

  final BookChunk card;
  final ReaderCardIdentity identity;
  final List<CanonicalPaginationSourceSlice> sourceSlices;
  final ResolvedReaderCardLayout? resolvedLayout;
}

enum CanonicalPaginationOutcomeKind {
  inputExhaustedAwaitingSuccessor,
  finalizedOutputAvailable,
  logicalEndReached,
  budgetExhaustedWithProvisionalFrontier,
  targetFinalized,
  cancelledStaleRejected,
  invalidRestartSourceRejected,
  frontierBoundViolation,
}

sealed class CanonicalPaginationResult {
  const CanonicalPaginationResult({required this.diagnostics});

  final CanonicalPaginationWorkDiagnostics diagnostics;
  CanonicalPaginationOutcomeKind get kind;
}

/// A complete hard-section tail, without any v1 terminal continuation.
final class CanonicalInputExhaustedAwaitingSuccessor
    extends CanonicalPaginationResult {
  CanonicalInputExhaustedAwaitingSuccessor({
    required super.diagnostics,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
  }) : finalizedCards = List.unmodifiable(finalizedCards);
  final List<CanonicalFinalizedReaderCard> finalizedCards;
  @override
  CanonicalPaginationOutcomeKind get kind =>
      CanonicalPaginationOutcomeKind.inputExhaustedAwaitingSuccessor;
}

sealed class CanonicalPaginationAcceptedResult
    extends CanonicalPaginationResult {
  const CanonicalPaginationAcceptedResult({
    required super.diagnostics,
    required this.finalizedCards,
  });

  final List<CanonicalFinalizedReaderCard> finalizedCards;
  CanonicalPaginationContinuation get continuation;
}

final class CanonicalFinalizedOutputAvailable
    extends CanonicalPaginationAcceptedResult {
  CanonicalFinalizedOutputAvailable({
    required super.diagnostics,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required this.continuation,
  }) : super(finalizedCards: List.unmodifiable(finalizedCards));

  @override
  final CanonicalPaginationContinuation continuation;
  CanonicalPaginationContinuation get restart => continuation;

  @override
  CanonicalPaginationOutcomeKind get kind =>
      CanonicalPaginationOutcomeKind.finalizedOutputAvailable;
}

final class CanonicalLogicalEndReached
    extends CanonicalPaginationAcceptedResult {
  CanonicalLogicalEndReached({
    required super.diagnostics,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required this.continuation,
  }) : super(finalizedCards: List.unmodifiable(finalizedCards));

  @override
  final CanonicalPaginationContinuation continuation;

  @override
  CanonicalPaginationOutcomeKind get kind =>
      CanonicalPaginationOutcomeKind.logicalEndReached;
}

final class CanonicalBudgetExhaustedWithFrontier
    extends CanonicalPaginationAcceptedResult {
  CanonicalBudgetExhaustedWithFrontier({
    required super.diagnostics,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required this.frontier,
    required this.continuation,
    required this.nextSourceCursor,
  }) : super(finalizedCards: List.unmodifiable(finalizedCards));

  final CanonicalPaginationFrontier frontier;
  @override
  final CanonicalPaginationContinuation continuation;
  CanonicalPaginationContinuation get restart => continuation;
  final CanonicalPaginationCursor nextSourceCursor;

  @override
  CanonicalPaginationOutcomeKind get kind =>
      CanonicalPaginationOutcomeKind.budgetExhaustedWithProvisionalFrontier;
}

final class CanonicalTargetFinalized extends CanonicalPaginationAcceptedResult {
  CanonicalTargetFinalized({
    required super.diagnostics,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required this.targetCard,
    required this.containmentEvidence,
    required this.continuation,
  }) : super(finalizedCards: List.unmodifiable(finalizedCards));

  final CanonicalFinalizedReaderCard targetCard;
  final CanonicalPaginationTargetContainmentEvidence containmentEvidence;
  @override
  final CanonicalPaginationContinuation continuation;
  CanonicalPaginationContinuation get restart => continuation;

  @override
  CanonicalPaginationOutcomeKind get kind =>
      CanonicalPaginationOutcomeKind.targetFinalized;
}

enum CanonicalPaginationRejectionReason {
  cancelled,
  staleGeneration,
  requestIdentityMismatch,
  invalidRestart,
  invalidSourceOwner,
  sourceDigestMismatch,
  invalidTarget,
  invalidBudget,
  frontierEntryCapExceeded,
  unsupportedContractKind,
  corruptDigest,
  incompatiblePublication,
  incompatibleParserSourceSnapshot,
  incompatiblePaginationIdentity,
  incompatibleLayout,
  invalidSectionSourceOwner,
  invalidCursorOffsetRowInterval,
  invalidFrontier,
  brokenParentChain,
  ordinalMismatch,
  staleForkReplay,
  terminalStateContradiction,
  boundViolation,
  requiredEarlierRestart,
}

sealed class CanonicalPaginationRejectedResult
    extends CanonicalPaginationResult {
  const CanonicalPaginationRejectedResult({
    required super.diagnostics,
    required this.reason,
    required this.message,
  });

  final CanonicalPaginationRejectionReason reason;
  final String message;

  List<CanonicalFinalizedReaderCard> get publishableCards => const [];
  bool get hasAcceptedRestartAuthority => false;
  bool get hasCacheWriteAuthority => false;
}

final class CanonicalCancelledStaleRejected
    extends CanonicalPaginationRejectedResult {
  const CanonicalCancelledStaleRejected({
    required super.diagnostics,
    required super.reason,
    required super.message,
  });

  @override
  CanonicalPaginationOutcomeKind get kind =>
      CanonicalPaginationOutcomeKind.cancelledStaleRejected;
}

final class CanonicalInvalidRestartSourceRejected
    extends CanonicalPaginationRejectedResult {
  const CanonicalInvalidRestartSourceRejected({
    required super.diagnostics,
    required super.reason,
    required super.message,
  });

  @override
  CanonicalPaginationOutcomeKind get kind =>
      CanonicalPaginationOutcomeKind.invalidRestartSourceRejected;
}

final class CanonicalFrontierBoundViolation
    extends CanonicalPaginationRejectedResult {
  const CanonicalFrontierBoundViolation({
    required super.diagnostics,
    required super.message,
  }) : super(
         reason: CanonicalPaginationRejectionReason.frontierEntryCapExceeded,
       );

  @override
  CanonicalPaginationOutcomeKind get kind =>
      CanonicalPaginationOutcomeKind.frontierBoundViolation;
}
