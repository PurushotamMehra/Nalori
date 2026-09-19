import 'package:flutter/foundation.dart';

import 'reader_font_evidence.dart';
import 'reader_layout_contract.dart';

enum ReaderCompatibilityClassificationKind {
  exactCompatible,
  layoutMetricsChanged,
  sourceCompatibilityChanged,
  paginationAlgorithmChanged,
  rendererLayoutChanged,
  multipleAuthoritativeChanges,
  incompleteEvidence,
  corruptEvidence,
  unsupportedRevision,
}

extension ReaderCompatibilityClassificationKindWire
    on ReaderCompatibilityClassificationKind {
  String get wireName => switch (this) {
    ReaderCompatibilityClassificationKind.exactCompatible => 'exact_compatible',
    ReaderCompatibilityClassificationKind.layoutMetricsChanged =>
      'layout_metrics_changed',
    ReaderCompatibilityClassificationKind.sourceCompatibilityChanged =>
      'source_compatibility_changed',
    ReaderCompatibilityClassificationKind.paginationAlgorithmChanged =>
      'pagination_algorithm_changed',
    ReaderCompatibilityClassificationKind.rendererLayoutChanged =>
      'renderer_layout_changed',
    ReaderCompatibilityClassificationKind.multipleAuthoritativeChanges =>
      'multiple_authoritative_changes',
    ReaderCompatibilityClassificationKind.incompleteEvidence =>
      'incomplete_evidence',
    ReaderCompatibilityClassificationKind.corruptEvidence => 'corrupt_evidence',
    ReaderCompatibilityClassificationKind.unsupportedRevision =>
      'unsupported_revision',
  };
}

enum ReaderCompatibilityIdentityDimension {
  layoutMetrics,
  sourceCompatibility,
  paginationAlgorithm,
  rendererLayout,
}

extension ReaderCompatibilityIdentityDimensionWire
    on ReaderCompatibilityIdentityDimension {
  String get wireName => switch (this) {
    ReaderCompatibilityIdentityDimension.layoutMetrics => 'layout_metrics',
    ReaderCompatibilityIdentityDimension.sourceCompatibility =>
      'source_compatibility',
    ReaderCompatibilityIdentityDimension.paginationAlgorithm =>
      'pagination_algorithm',
    ReaderCompatibilityIdentityDimension.rendererLayout => 'renderer_layout',
  };
}

@immutable
final class ReaderCompatibilityMigrationReason {
  ReaderCompatibilityMigrationReason({
    required this.kind,
    required List<ReaderCompatibilityIdentityDimension> changedDimensions,
  }) : changedDimensions =
           List<ReaderCompatibilityIdentityDimension>.unmodifiable(
             changedDimensions,
           ),
       _canonicalBytes = _encode(kind, changedDimensions) {
    if (!_hasFixedDimensionOrder(this.changedDimensions)) {
      throw ArgumentError('Changed identity dimensions must use fixed order.');
    }
  }

  final ReaderCompatibilityClassificationKind kind;
  final List<ReaderCompatibilityIdentityDimension> changedDimensions;
  final Uint8List _canonicalBytes;

  String get wireName => kind.wireName;
  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);
  String get fingerprint => ReaderFontCanonicalEncoder.digest(_canonicalBytes);

  static Uint8List _encode(
    ReaderCompatibilityClassificationKind kind,
    List<ReaderCompatibilityIdentityDimension> dimensions,
  ) {
    final writer = ReaderFontCanonicalWriter('reader-compatibility-reason', 1);
    writer.stringField(1, kind.wireName);
    writer.stringListField(
      2,
      dimensions.map((dimension) => dimension.wireName).toList(),
    );
    return writer.takeBytes();
  }
}

@immutable
final class ReaderCompatibilityDiagnosticFingerprints {
  const ReaderCompatibilityDiagnosticFingerprints({
    required this.layoutMetricsFingerprint,
    required this.sourceCompatibilityFingerprint,
    required this.paginationAlgorithmFingerprint,
    required this.rendererLayoutFingerprint,
    required this.readerCompatibilityFingerprint,
  });

  factory ReaderCompatibilityDiagnosticFingerprints.fromEvidence(
    ReaderCompatibilityEvidence evidence,
  ) => ReaderCompatibilityDiagnosticFingerprints(
    layoutMetricsFingerprint: evidence.layoutMetricsIdentity?.fingerprint,
    sourceCompatibilityFingerprint:
        evidence.sourceCompatibilityIdentity?.fingerprint,
    paginationAlgorithmFingerprint:
        evidence.paginationAlgorithmIdentity?.fingerprint,
    rendererLayoutFingerprint: evidence.rendererLayoutIdentity?.fingerprint,
    readerCompatibilityFingerprint:
        evidence.readerCompatibilityIdentity?.fingerprint,
  );

  final String? layoutMetricsFingerprint;
  final String? sourceCompatibilityFingerprint;
  final String? paginationAlgorithmFingerprint;
  final String? rendererLayoutFingerprint;
  final String? readerCompatibilityFingerprint;
}

/// The classifier accepts canonical identity evidence only. Book identity is
/// deliberately absent: P06/P08 retain independent lookup/isolation checks.
@immutable
final class ReaderCompatibilityEvidence {
  const ReaderCompatibilityEvidence({
    this.layoutMetricsIdentity,
    this.sourceCompatibilityIdentity,
    this.paginationAlgorithmIdentity,
    this.rendererLayoutIdentity,
    this.readerCompatibilityIdentity,
  });

  factory ReaderCompatibilityEvidence.fromIdentity(
    ReaderCompatibilityIdentity identity,
  ) => ReaderCompatibilityEvidence(
    layoutMetricsIdentity: identity.layoutMetricsIdentity,
    sourceCompatibilityIdentity: identity.sourceCompatibilityIdentity,
    paginationAlgorithmIdentity: identity.paginationAlgorithmIdentity,
    rendererLayoutIdentity: identity.rendererLayoutIdentity,
    readerCompatibilityIdentity: identity,
  );

  final LayoutMetricsIdentity? layoutMetricsIdentity;
  final SourceCompatibilityIdentity? sourceCompatibilityIdentity;
  final PaginationAlgorithmIdentity? paginationAlgorithmIdentity;
  final RendererLayoutIdentity? rendererLayoutIdentity;
  final ReaderCompatibilityIdentity? readerCompatibilityIdentity;

  bool get isComplete =>
      layoutMetricsIdentity != null &&
      sourceCompatibilityIdentity != null &&
      paginationAlgorithmIdentity != null &&
      rendererLayoutIdentity != null &&
      readerCompatibilityIdentity != null;
}

@immutable
final class ReaderCompatibilityRevisionSupport {
  ReaderCompatibilityRevisionSupport({
    required Iterable<String> layoutContractRevisions,
    required Iterable<String> layoutMetricsIdentityRevisions,
    required Iterable<String> parserSourceSchemaIdentities,
    required Iterable<String> structuralOwnershipRevisions,
    required Iterable<String> paginationSemanticRevisions,
    required Iterable<String> rendererRulesRevisions,
    required Iterable<String> classifierRevisions,
  }) : layoutContractRevisions = _sortedSet(layoutContractRevisions),
       layoutMetricsIdentityRevisions = _sortedSet(
         layoutMetricsIdentityRevisions,
       ),
       parserSourceSchemaIdentities = _sortedSet(parserSourceSchemaIdentities),
       structuralOwnershipRevisions = _sortedSet(structuralOwnershipRevisions),
       paginationSemanticRevisions = _sortedSet(paginationSemanticRevisions),
       rendererRulesRevisions = _sortedSet(rendererRulesRevisions),
       classifierRevisions = _sortedSet(classifierRevisions) {
    if (<Iterable<String>>[
      this.layoutContractRevisions,
      this.layoutMetricsIdentityRevisions,
      this.parserSourceSchemaIdentities,
      this.structuralOwnershipRevisions,
      this.paginationSemanticRevisions,
      this.rendererRulesRevisions,
      this.classifierRevisions,
    ].any((values) => values.isEmpty)) {
      throw ArgumentError('Revision support must be explicit and nonempty.');
    }
  }

  factory ReaderCompatibilityRevisionSupport.current({
    required Iterable<String> parserSourceSchemaIdentities,
  }) => ReaderCompatibilityRevisionSupport(
    layoutContractRevisions: const <String>[readerLayoutContractRevision],
    layoutMetricsIdentityRevisions: const <String>[
      readerLayoutMetricsIdentityRevision,
    ],
    parserSourceSchemaIdentities: parserSourceSchemaIdentities,
    structuralOwnershipRevisions: const <String>[
      readerStructuralOwnershipRevision,
    ],
    paginationSemanticRevisions: const <String>[
      readerPaginationSemanticRevision,
    ],
    rendererRulesRevisions: const <String>[readerRendererRulesRevision],
    classifierRevisions: const <String>[readerCompatibilityClassifierRevision],
  );

  final List<String> layoutContractRevisions;
  final List<String> layoutMetricsIdentityRevisions;
  final List<String> parserSourceSchemaIdentities;
  final List<String> structuralOwnershipRevisions;
  final List<String> paginationSemanticRevisions;
  final List<String> rendererRulesRevisions;
  final List<String> classifierRevisions;
}

@immutable
final class ReaderCompatibilityClassificationResult {
  ReaderCompatibilityClassificationResult({
    required this.kind,
    required this.reason,
    required List<ReaderCompatibilityIdentityDimension> changedDimensions,
    required this.previousFingerprints,
    required this.currentFingerprints,
    required this.requestedPhysicalCardSignaturePresent,
  }) : changedDimensions =
           List<ReaderCompatibilityIdentityDimension>.unmodifiable(
             changedDimensions,
           ),
       _canonicalBytes = _encode(
         kind,
         reason,
         changedDimensions,
         previousFingerprints,
         currentFingerprints,
         requestedPhysicalCardSignaturePresent,
       );

  final ReaderCompatibilityClassificationKind kind;
  final ReaderCompatibilityMigrationReason reason;
  final List<ReaderCompatibilityIdentityDimension> changedDimensions;
  final ReaderCompatibilityDiagnosticFingerprints previousFingerprints;
  final ReaderCompatibilityDiagnosticFingerprints currentFingerprints;

  /// This is diagnostic input only; the classifier never receives a card or
  /// chooses a replacement. An exact identity still requires later validation.
  final bool requestedPhysicalCardSignaturePresent;
  final Uint8List _canonicalBytes;

  bool get mayProceedToExactReuseValidation =>
      kind == ReaderCompatibilityClassificationKind.exactCompatible;
  bool get mayConsiderSemanticMigration => switch (kind) {
    ReaderCompatibilityClassificationKind.layoutMetricsChanged ||
    ReaderCompatibilityClassificationKind.sourceCompatibilityChanged ||
    ReaderCompatibilityClassificationKind.paginationAlgorithmChanged ||
    ReaderCompatibilityClassificationKind.rendererLayoutChanged ||
    ReaderCompatibilityClassificationKind.multipleAuthoritativeChanges => true,
    _ => false,
  };
  bool get requiresFurtherPhysicalCardValidation =>
      kind == ReaderCompatibilityClassificationKind.exactCompatible;

  bool get hasCacheAuthority => false;
  bool get hasCheckpointAuthority => false;
  bool get hasPublicationAuthority => false;
  bool get hasSettlementAuthority => false;
  bool get hasAnyAuthority => false;
  int get sourceTextBytesRetained => 0;
  int get mutableIndexesRetained => 0;
  int get classificationMutationCount => 0;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);

  static Uint8List _encode(
    ReaderCompatibilityClassificationKind kind,
    ReaderCompatibilityMigrationReason reason,
    List<ReaderCompatibilityIdentityDimension> dimensions,
    ReaderCompatibilityDiagnosticFingerprints previous,
    ReaderCompatibilityDiagnosticFingerprints current,
    bool signaturePresent,
  ) {
    final writer = ReaderFontCanonicalWriter('reader-compatibility-result', 1);
    writer.stringField(1, kind.wireName);
    writer.stringField(2, reason.fingerprint);
    writer.stringListField(
      3,
      dimensions.map((dimension) => dimension.wireName).toList(),
    );
    writer.stringListField(4, _fingerprints(previous));
    writer.stringListField(5, _fingerprints(current));
    writer.boolField(6, signaturePresent);
    writer.boolField(
      7,
      kind == ReaderCompatibilityClassificationKind.exactCompatible,
    );
    writer.boolField(8, switch (kind) {
      ReaderCompatibilityClassificationKind.layoutMetricsChanged ||
      ReaderCompatibilityClassificationKind.sourceCompatibilityChanged ||
      ReaderCompatibilityClassificationKind.paginationAlgorithmChanged ||
      ReaderCompatibilityClassificationKind.rendererLayoutChanged ||
      ReaderCompatibilityClassificationKind.multipleAuthoritativeChanges =>
        true,
      _ => false,
    });
    return writer.takeBytes();
  }

  static List<String> _fingerprints(
    ReaderCompatibilityDiagnosticFingerprints fingerprints,
  ) => <String>[
    fingerprints.layoutMetricsFingerprint ?? '',
    fingerprints.sourceCompatibilityFingerprint ?? '',
    fingerprints.paginationAlgorithmFingerprint ?? '',
    fingerprints.rendererLayoutFingerprint ?? '',
    fingerprints.readerCompatibilityFingerprint ?? '',
  ];
}

List<String> _sortedSet(Iterable<String> values) {
  final result = values.toSet().toList()..sort();
  if (result.any((value) => value.isEmpty)) {
    throw ArgumentError('Supported revisions must be nonempty.');
  }
  return List<String>.unmodifiable(result);
}

bool _hasFixedDimensionOrder(
  List<ReaderCompatibilityIdentityDimension> dimensions,
) {
  const fixed = ReaderCompatibilityIdentityDimension.values;
  var previous = -1;
  for (final dimension in dimensions) {
    final index = fixed.indexOf(dimension);
    if (index <= previous) return false;
    previous = index;
  }
  return true;
}
