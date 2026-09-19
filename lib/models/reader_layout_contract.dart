import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'reader_font_evidence.dart';

const String readerLayoutContractRevision = 'reader_layout_contract_v1';
const String readerLayoutCaptureRevision = 'reader_layout_capture_v1';
const String readerLayoutMetricsIdentityRevision =
    'reader_layout_metrics_identity_v1';
const String readerRendererRulesRevision = 'reader_renderer_layout_v1';
const String readerTypographyRevision = 'reader_typography_contract_v1';
const String readerPaginationSemanticRevision = 'nalori_cards_v16_lists';
const String readerCompatibilityClassifierRevision =
    'reader_compatibility_inputs_v1';
const String readerStructuralOwnershipRevision = 'p04_structural_ownership_v1';

enum ReaderLayoutDirection { ltr, rtl }

enum ReaderLayoutDirectionSource { sourceBlock, readerCapture, ltrFallback }

enum ReaderLayoutAlignment { left, center, right, justify, start, end }

extension ReaderLayoutAlignmentFlutter on ReaderLayoutAlignment {
  TextAlign get textAlign => switch (this) {
    ReaderLayoutAlignment.left => TextAlign.left,
    ReaderLayoutAlignment.center => TextAlign.center,
    ReaderLayoutAlignment.right => TextAlign.right,
    ReaderLayoutAlignment.justify => TextAlign.justify,
    ReaderLayoutAlignment.start => TextAlign.start,
    ReaderLayoutAlignment.end => TextAlign.end,
  };
}

enum ReaderLayoutDensity { low, medium, high, fullPage }

enum ReaderLayoutBuildOutcomeType {
  ready,
  pendingFontEvidence,
  pendingImageMetrics,
  incompatibleEnvironment,
  unsupportedStructuralInput,
  contradictoryDerivedGeometry,
  invalidNumericValue,
  staleCapture,
}

enum ReaderLayoutTextRole {
  body,
  heading,
  inlineBold,
  inlineItalic,
  inlineBoldItalic,
  footnoteMarker,
  listMarker,
  tableCell,
  tableHeader,
  preformatted,
  headingDivider,
  publisherProse,
  publisherPoem,
  publisherQuote,
  publisherLetter,
}

enum ReaderResolvedBlockKind {
  paragraph,
  heading,
  list,
  table,
  preformatted,
  image,
  milestone,
}

enum ReaderSpanSemantic { text, link, footnoteMarker }

@immutable
final class ReaderCanonicalLocale {
  ReaderCanonicalLocale({
    required String language,
    String? script,
    String? region,
    List<String> variants = const <String>[],
  }) : language = language.trim().isEmpty ? 'und' : language.toLowerCase(),
       script = script == null || script.isEmpty
           ? null
           : '${script[0].toUpperCase()}${script.substring(1).toLowerCase()}',
       region = region == null || region.isEmpty ? null : region.toUpperCase(),
       variants = List<String>.unmodifiable(
         variants.map((value) => value.toLowerCase()).toList()..sort(),
       );

  factory ReaderCanonicalLocale.fromLocale(Locale locale) =>
      ReaderCanonicalLocale(
        language: locale.languageCode,
        script: locale.scriptCode,
        region: locale.countryCode,
      );

  final String language;
  final String? script;
  final String? region;
  final List<String> variants;

  String get tag => <String>[
    language,
    if (script != null) script!,
    if (region != null) region!,
    ...variants,
  ].join('-');

  Locale get flutterLocale => Locale.fromSubtags(
    languageCode: language,
    scriptCode: script,
    countryCode: region,
  );
}

@immutable
final class ResolvedTextScaleProfile {
  ResolvedTextScaleProfile({
    required Map<double, double> responses,
    required this.domainCompletenessDigest,
    required this.scaleResponseDigest,
  }) : responses = Map<double, double>.unmodifiable(
         SplayTreeMap<double, double>.from(responses),
       ) {
    if (this.responses.isEmpty ||
        this.responses.entries.any(
          (entry) =>
              !entry.key.isFinite ||
              entry.key <= 0 ||
              !entry.value.isFinite ||
              entry.value <= 0,
        )) {
      throw ArgumentError('Text scale responses must be finite and positive.');
    }
  }

  final Map<double, double> responses;
  final String domainCompletenessDigest;
  final String scaleResponseDigest;

  List<double> get logicalSizes => List<double>.unmodifiable(responses.keys);
  List<double> get scaledSizes => List<double>.unmodifiable(responses.values);

  double scale(double logicalSize) {
    final value = responses[logicalSize];
    if (value == null) {
      throw StateError('Uncaptured reader text size $logicalSize.');
    }
    return value;
  }
}

@immutable
final class ReaderLayoutEnvironment {
  const ReaderLayoutEnvironment({
    required this.outerDeckSize,
    required this.mediaQuerySizeEvidence,
    required this.deckMediaQueryEquivalent,
    required this.viewPadding,
    required this.locale,
    required this.defaultDirection,
    required this.textScaleProfile,
    required this.captureFreshnessEvidence,
  });

  final Size outerDeckSize;
  final Size? mediaQuerySizeEvidence;
  final bool deckMediaQueryEquivalent;
  final EdgeInsets viewPadding;
  final ReaderCanonicalLocale locale;
  final ReaderLayoutDirection? defaultDirection;
  final ResolvedTextScaleProfile textScaleProfile;
  final String captureFreshnessEvidence;
}

@immutable
final class ReaderResolvedSettingsPolicy {
  const ReaderResolvedSettingsPolicy({
    required this.effectiveSidePadding,
    required this.cardDepthEnabled,
    required this.density,
    required this.densityPageRatio,
    required this.densityTinyWordCount,
    required this.densityTinyHeightRatio,
    required this.paragraphSpacingMultiplier,
    required this.defaultAlignment,
  });

  final double effectiveSidePadding;
  final bool cardDepthEnabled;
  final ReaderLayoutDensity density;
  final double densityPageRatio;
  final int densityTinyWordCount;
  final double densityTinyHeightRatio;
  final double paragraphSpacingMultiplier;
  final ReaderLayoutAlignment defaultAlignment;
}

@immutable
final class ReaderCardGeometry {
  const ReaderCardGeometry({
    required this.cardMargin,
    required this.contentPadding,
    required this.cardSize,
    required this.bodySize,
    required this.borderStrokeWidth,
    required this.measurementSafetyReserve,
    required this.physicalPaginationCapacity,
    required this.ordinaryPaginationHeightBudget,
    required this.publisherPaginationHeightBudget,
    required this.minUsefulHeight,
  });

  final EdgeInsets cardMargin;
  final EdgeInsets contentPadding;
  final Size cardSize;
  final Size bodySize;
  final double borderStrokeWidth;
  final double measurementSafetyReserve;
  final double physicalPaginationCapacity;
  final double ordinaryPaginationHeightBudget;
  final double publisherPaginationHeightBudget;
  final double minUsefulHeight;

  static const EdgeInsets borderLayoutInset = EdgeInsets.zero;
  static const double minimumCapacityLineCount = 2.4;
  static const double safetyReserveLineFactor = 0.65;
  static const double safetyReserveMinimum = 14;
  static const double safetyReserveMaximum = 36;
}

@immutable
final class ReaderResolvedTextStyleSpec {
  const ReaderResolvedTextStyleSpec({
    required this.role,
    required this.fontRequest,
    required this.logicalFontSize,
    required this.scaledFontSize,
    required this.lineHeightMultiplier,
    required this.effectiveLineBoxHeight,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.locale,
    required this.direction,
    required this.alignment,
    required this.softWrap,
    required this.widthBasis,
    required this.maxLines,
    required this.overflow,
  });

  final ReaderLayoutTextRole role;
  final ReaderFontRequestIdentity fontRequest;
  final double logicalFontSize;
  final double scaledFontSize;
  final double lineHeightMultiplier;
  final double effectiveLineBoxHeight;
  final double letterSpacing;
  final double wordSpacing;
  final ReaderCanonicalLocale locale;
  final ReaderLayoutDirection direction;
  final ReaderLayoutAlignment alignment;
  final bool softWrap;
  final String widthBasis;
  final int? maxLines;
  final TextOverflow overflow;

  TextDirection get textDirection => direction == ReaderLayoutDirection.rtl
      ? TextDirection.rtl
      : TextDirection.ltr;

  TextAlign get textAlign => switch (alignment) {
    ReaderLayoutAlignment.left => TextAlign.left,
    ReaderLayoutAlignment.center => TextAlign.center,
    ReaderLayoutAlignment.right => TextAlign.right,
    ReaderLayoutAlignment.justify => TextAlign.justify,
    ReaderLayoutAlignment.start => TextAlign.start,
    ReaderLayoutAlignment.end => TextAlign.end,
  };

  TextStyle toTextStyle({Color? color}) => TextStyle(
    color: color,
    fontFamily: fontRequest.localFamily,
    package: fontRequest.package,
    fontSize: scaledFontSize,
    fontWeight: FontWeight.values[(fontRequest.requestedWeight ~/ 100) - 1],
    fontStyle: fontRequest.requestedStyle,
    height: lineHeightMultiplier,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    locale: locale.flutterLocale,
    fontFeatures: fontRequest.fontFeatures,
  );

  StrutStyle toStrutStyle() => StrutStyle(
    fontFamily: fontRequest.localFamily,
    package: fontRequest.package,
    fontSize: scaledFontSize,
    fontWeight: FontWeight.values[(fontRequest.requestedWeight ~/ 100) - 1],
    fontStyle: fontRequest.requestedStyle,
    height: lineHeightMultiplier,
    leading: 0,
    forceStrutHeight: true,
    leadingDistribution: TextLeadingDistribution.proportional,
  );
}

@immutable
final class ReaderTypographyContract {
  ReaderTypographyContract({
    required Map<ReaderLayoutTextRole, ReaderResolvedTextStyleSpec> styles,
    required this.defaultLocale,
    required this.defaultDirection,
    required this.defaultBodyAlignment,
  }) : styles =
           Map<ReaderLayoutTextRole, ReaderResolvedTextStyleSpec>.unmodifiable(
             SplayTreeMap<
               ReaderLayoutTextRole,
               ReaderResolvedTextStyleSpec
             >.from(styles, (left, right) => left.index.compareTo(right.index)),
           ) {
    if (this.styles.length != ReaderLayoutTextRole.values.length ||
        !ReaderLayoutTextRole.values.every(this.styles.containsKey)) {
      throw ArgumentError('The reader typography catalog is not closed.');
    }
  }

  final Map<ReaderLayoutTextRole, ReaderResolvedTextStyleSpec> styles;
  final ReaderCanonicalLocale defaultLocale;
  final ReaderLayoutDirection defaultDirection;
  final ReaderLayoutAlignment defaultBodyAlignment;

  ReaderResolvedTextStyleSpec operator [](ReaderLayoutTextRole role) =>
      styles[role]!;
}

@immutable
final class ReaderStructuralLayoutContract {
  const ReaderStructuralLayoutContract({
    this.headingGap = 20,
    this.headingDividerText = '─────── ◆ ───────',
    this.publisherIndentClampMaximum = 72,
    this.dialogueInset = 0,
    this.listDepthStep = 12,
    this.listMaxIndent = 36,
    this.listMarkerWidthMinimum = 18,
    this.listMarkerWidthMaximum = 52,
    this.listMarkerGap = 8,
    this.listSameBlockGapFactor = 0,
    this.listSameItemGapFactor = 0.42,
    this.listNewItemGapFactor = 0.28,
    this.tableColumnMinimum = 156,
    this.tableOuterVerticalPadding = 10,
    this.tableCellHorizontalPadding = 10,
    this.tableCellVerticalPadding = 9,
    this.preformattedOuterVerticalPadding = 10,
    this.preformattedInnerPadding = 10,
    this.imageBottomPadding = 16,
  });

  final double headingGap;
  final String headingDividerText;
  final double publisherIndentClampMaximum;
  final double dialogueInset;
  final double listDepthStep;
  final double listMaxIndent;
  final double listMarkerWidthMinimum;
  final double listMarkerWidthMaximum;
  final double listMarkerGap;
  final double listSameBlockGapFactor;
  final double listSameItemGapFactor;
  final double listNewItemGapFactor;
  final double tableColumnMinimum;
  final double tableOuterVerticalPadding;
  final double tableCellHorizontalPadding;
  final double tableCellVerticalPadding;
  final double preformattedOuterVerticalPadding;
  final double preformattedInnerPadding;
  final double imageBottomPadding;
}

@immutable
final class LayoutMetricsIdentity {
  LayoutMetricsIdentity({
    required this.revision,
    required List<int> canonicalBytes,
    required this.fingerprint,
  }) : _canonicalBytes = Uint8List.fromList(canonicalBytes);

  final String revision;
  final Uint8List _canonicalBytes;
  final String fingerprint;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);
}

@immutable
final class SourceCompatibilityIdentity {
  SourceCompatibilityIdentity({
    required List<int> canonicalBytes,
    required this.fingerprint,
  }) : _canonicalBytes = Uint8List.fromList(canonicalBytes);

  final Uint8List _canonicalBytes;
  final String fingerprint;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);
}

@immutable
final class PaginationAlgorithmIdentity {
  PaginationAlgorithmIdentity({
    required this.semanticRevision,
    required List<int> canonicalBytes,
    required this.fingerprint,
  }) : _canonicalBytes = Uint8List.fromList(canonicalBytes);

  final String semanticRevision;
  final Uint8List _canonicalBytes;
  final String fingerprint;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);
}

@immutable
final class RendererLayoutIdentity {
  RendererLayoutIdentity({
    required this.rulesRevisionLink,
    required List<int> canonicalBytes,
    required this.fingerprint,
  }) : _canonicalBytes = Uint8List.fromList(canonicalBytes);

  final String rulesRevisionLink;
  final Uint8List _canonicalBytes;
  final String fingerprint;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);
}

@immutable
final class ReaderCompatibilityIdentity {
  ReaderCompatibilityIdentity({
    required this.layoutMetricsIdentity,
    required this.sourceCompatibilityIdentity,
    required this.paginationAlgorithmIdentity,
    required this.rendererLayoutIdentity,
    required this.classifierRevision,
    required List<int> canonicalBytes,
    required this.fingerprint,
  }) : _canonicalBytes = Uint8List.fromList(canonicalBytes);

  factory ReaderCompatibilityIdentity.compose({
    required LayoutMetricsIdentity layoutMetricsIdentity,
    required SourceCompatibilityIdentity sourceCompatibilityIdentity,
    required PaginationAlgorithmIdentity paginationAlgorithmIdentity,
    required RendererLayoutIdentity rendererLayoutIdentity,
    required String classifierRevision,
  }) {
    final bytes = ReaderCompatibilityCanonicalEncoder.encodeComposite(
      layoutMetricsFingerprint: layoutMetricsIdentity.fingerprint,
      sourceCompatibilityFingerprint: sourceCompatibilityIdentity.fingerprint,
      paginationAlgorithmFingerprint: paginationAlgorithmIdentity.fingerprint,
      rendererLayoutFingerprint: rendererLayoutIdentity.fingerprint,
      classifierRevision: classifierRevision,
    );
    return ReaderCompatibilityIdentity(
      layoutMetricsIdentity: layoutMetricsIdentity,
      sourceCompatibilityIdentity: sourceCompatibilityIdentity,
      paginationAlgorithmIdentity: paginationAlgorithmIdentity,
      rendererLayoutIdentity: rendererLayoutIdentity,
      classifierRevision: classifierRevision,
      canonicalBytes: bytes,
      fingerprint: ReaderFontCanonicalEncoder.digest(bytes),
    );
  }

  final LayoutMetricsIdentity layoutMetricsIdentity;
  final SourceCompatibilityIdentity sourceCompatibilityIdentity;
  final PaginationAlgorithmIdentity paginationAlgorithmIdentity;
  final RendererLayoutIdentity rendererLayoutIdentity;
  final String classifierRevision;
  final Uint8List _canonicalBytes;
  final String fingerprint;

  Uint8List get canonicalBytes => Uint8List.fromList(_canonicalBytes);
}

abstract final class ReaderCompatibilityCanonicalEncoder {
  static Uint8List encodeComposite({
    required String layoutMetricsFingerprint,
    required String sourceCompatibilityFingerprint,
    required String paginationAlgorithmFingerprint,
    required String rendererLayoutFingerprint,
    required String classifierRevision,
  }) {
    final writer = ReaderFontCanonicalWriter('reader-compatibility', 1);
    writer.stringField(1, classifierRevision);
    writer.stringField(2, layoutMetricsFingerprint);
    writer.stringField(3, sourceCompatibilityFingerprint);
    writer.stringField(4, paginationAlgorithmFingerprint);
    writer.stringField(5, rendererLayoutFingerprint);
    return writer.takeBytes();
  }
}

@immutable
final class ReaderLayoutIdentityBundle {
  const ReaderLayoutIdentityBundle({
    required this.layoutMetricsFingerprint,
    required this.rendererLayoutFingerprint,
    required this.sourceCompatibilityFingerprint,
    required this.paginationAlgorithmFingerprint,
    required this.readerCompatibilityFingerprint,
    required this.layoutMetricsIdentity,
    required this.sourceCompatibilityIdentity,
    required this.paginationAlgorithmIdentity,
    required this.rendererLayoutIdentity,
    required this.readerCompatibilityIdentity,
  });

  /// Existing measure/render/card consumers retain these P05-003 strings.
  /// F195–F208 typed evidence is classified separately by P05-006 and is not
  /// wired into persistent/cache/checkpoint behavior in this task.
  final String layoutMetricsFingerprint;
  final String rendererLayoutFingerprint;
  final String sourceCompatibilityFingerprint;
  final String paginationAlgorithmFingerprint;
  final String readerCompatibilityFingerprint;
  final LayoutMetricsIdentity layoutMetricsIdentity;
  final SourceCompatibilityIdentity sourceCompatibilityIdentity;
  final PaginationAlgorithmIdentity paginationAlgorithmIdentity;
  final RendererLayoutIdentity rendererLayoutIdentity;
  final ReaderCompatibilityIdentity readerCompatibilityIdentity;
}

@immutable
final class ReaderLayoutContract {
  const ReaderLayoutContract({
    required this.environment,
    required this.settingsPolicy,
    required this.geometry,
    required this.typography,
    required this.fontDeliveryEvidence,
    required this.structure,
    required this.identities,
  });

  final ReaderLayoutEnvironment environment;
  final ReaderResolvedSettingsPolicy settingsPolicy;
  final ReaderCardGeometry geometry;
  final ReaderTypographyContract typography;
  final ReaderFontDeliveryEvidence fontDeliveryEvidence;
  final ReaderStructuralLayoutContract structure;
  final ReaderLayoutIdentityBundle identities;

  String get identity => identities.readerCompatibilityFingerprint;

  int get retainedStateBytes =>
      2 *
      (identity.length +
          identities.layoutMetricsFingerprint.length +
          identities.rendererLayoutFingerprint.length +
          identities.sourceCompatibilityFingerprint.length +
          identities.paginationAlgorithmFingerprint.length +
          environment.captureFreshnessEvidence.length +
          environment.textScaleProfile.responses.length * 16 +
          typography.styles.length * 128);

  @override
  bool operator ==(Object other) =>
      other is ReaderLayoutContract && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

sealed class ReaderLayoutContractBuildOutcome {
  const ReaderLayoutContractBuildOutcome(this.type, {this.reason});

  final ReaderLayoutBuildOutcomeType type;
  final String? reason;
  bool get canAuthorizeLayout => false;
}

final class ReaderLayoutContractReady extends ReaderLayoutContractBuildOutcome {
  const ReaderLayoutContractReady(this.contract)
    : super(ReaderLayoutBuildOutcomeType.ready);

  final ReaderLayoutContract contract;

  @override
  bool get canAuthorizeLayout => true;
}

final class ReaderLayoutContractNoAuthority
    extends ReaderLayoutContractBuildOutcome {
  const ReaderLayoutContractNoAuthority(super.type, {super.reason})
    : assert(type != ReaderLayoutBuildOutcomeType.ready);
}

@immutable
final class ResolvedReaderSpanRun {
  const ResolvedReaderSpanRun({
    required this.startUtf16,
    required this.endUtf16,
    required this.role,
    required this.semantic,
    this.linkUrl,
    this.footnoteLabel,
  });

  final int startUtf16;
  final int endUtf16;
  final ReaderLayoutTextRole role;
  final ReaderSpanSemantic semantic;
  final String? linkUrl;
  final String? footnoteLabel;

  String get semanticKey =>
      '$startUtf16|$endUtf16|${role.name}|${semantic.name}|'
      '${linkUrl ?? ''}|${footnoteLabel ?? ''}';

  @override
  bool operator ==(Object other) =>
      other is ResolvedReaderSpanRun && other.semanticKey == semanticKey;

  @override
  int get hashCode => semanticKey.hashCode;
}

@immutable
final class ResolvedReaderParagraphSegment {
  const ResolvedReaderParagraphSegment({
    required this.startUtf16,
    required this.endUtf16,
    required this.gapBefore,
  });

  final int startUtf16;
  final int endUtf16;
  final double gapBefore;

  @override
  bool operator ==(Object other) =>
      other is ResolvedReaderParagraphSegment &&
      other.startUtf16 == startUtf16 &&
      other.endUtf16 == endUtf16 &&
      other.gapBefore == gapBefore;

  @override
  int get hashCode => Object.hash(startUtf16, endUtf16, gapBefore);
}

@immutable
final class ResolvedReaderListSegment {
  ResolvedReaderListSegment({
    required this.startUtf16,
    required this.endUtf16,
    required this.marker,
    required this.leadingIndent,
    required this.markerWidth,
    required this.markerGap,
    required this.gapBefore,
    required List<ResolvedReaderSpanRun> spans,
  }) : spans = List<ResolvedReaderSpanRun>.unmodifiable(spans);

  final int startUtf16;
  final int endUtf16;
  final String marker;
  final double leadingIndent;
  final double markerWidth;
  final double markerGap;
  final double gapBefore;
  final List<ResolvedReaderSpanRun> spans;
}

@immutable
final class ResolvedReaderTableCell {
  ResolvedReaderTableCell({
    required this.text,
    required this.isHeader,
    required this.row,
    required this.column,
    required this.rowSpan,
    required this.columnSpan,
    required this.width,
    required this.height,
    required List<ResolvedReaderSpanRun> spans,
  }) : spans = List<ResolvedReaderSpanRun>.unmodifiable(spans);

  final String text;
  final bool isHeader;
  final int row;
  final int column;
  final int rowSpan;
  final int columnSpan;
  final double width;
  final double height;
  final List<ResolvedReaderSpanRun> spans;
}

@immutable
final class ResolvedReaderTableLayout {
  ResolvedReaderTableLayout({
    required List<double> columnWidths,
    required List<double> rowHeights,
    required List<ResolvedReaderTableCell> cells,
    required this.horizontalScrollWidth,
    required this.totalHeight,
  }) : columnWidths = List<double>.unmodifiable(columnWidths),
       rowHeights = List<double>.unmodifiable(rowHeights),
       cells = List<ResolvedReaderTableCell>.unmodifiable(cells);

  final List<double> columnWidths;
  final List<double> rowHeights;
  final List<ResolvedReaderTableCell> cells;
  final double horizontalScrollWidth;
  final double totalHeight;
}

@immutable
final class ResolvedReaderPreformattedLine {
  const ResolvedReaderPreformattedLine({
    required this.startUtf16,
    required this.endUtf16,
    required this.width,
    required this.height,
  });

  final int startUtf16;
  final int endUtf16;
  final double width;
  final double height;
}

@immutable
final class ReaderImageMetricEvidence {
  const ReaderImageMetricEvidence({
    required this.bytesDigest,
    required this.intrinsicWidth,
    required this.intrinsicHeight,
    required this.evidenceDigest,
  });

  final String bytesDigest;
  final int intrinsicWidth;
  final int intrinsicHeight;
  final String evidenceDigest;
}

@immutable
final class ResolvedReaderImageLayout {
  const ResolvedReaderImageLayout({
    required this.evidence,
    required this.width,
    required this.height,
    required this.bottomPadding,
  });

  final ReaderImageMetricEvidence evidence;
  final double width;
  final double height;
  final double bottomPadding;
}

@immutable
final class ResolvedReaderBlockLayout {
  ResolvedReaderBlockLayout({
    required this.stableBlockOwner,
    required this.blockKind,
    required this.resolvedLocale,
    required this.directionSource,
    required this.resolvedDirection,
    required this.resolvedAlignment,
    required this.resolvedBlockWidth,
    required this.publisherPadding,
    required List<ResolvedReaderParagraphSegment> paragraphSegments,
    required List<ResolvedReaderSpanRun> spanRuns,
    required List<ResolvedReaderListSegment> listSegments,
    required this.table,
    required List<ResolvedReaderPreformattedLine> preformattedLines,
    required this.image,
    required this.totalHeight,
    required this.overflowFits,
    required this.fontEvidenceDigest,
    required this.sourceStructureDigestLink,
    required this.blockLayoutFingerprint,
  }) : paragraphSegments = List<ResolvedReaderParagraphSegment>.unmodifiable(
         paragraphSegments,
       ),
       spanRuns = List<ResolvedReaderSpanRun>.unmodifiable(spanRuns),
       listSegments = List<ResolvedReaderListSegment>.unmodifiable(
         listSegments,
       ),
       preformattedLines = List<ResolvedReaderPreformattedLine>.unmodifiable(
         preformattedLines,
       );

  final String stableBlockOwner;
  final ReaderResolvedBlockKind blockKind;
  final ReaderCanonicalLocale resolvedLocale;
  final ReaderLayoutDirectionSource directionSource;
  final ReaderLayoutDirection resolvedDirection;
  final ReaderLayoutAlignment resolvedAlignment;
  final double resolvedBlockWidth;
  final EdgeInsets publisherPadding;
  final List<ResolvedReaderParagraphSegment> paragraphSegments;
  final List<ResolvedReaderSpanRun> spanRuns;
  final List<ResolvedReaderListSegment> listSegments;
  final ResolvedReaderTableLayout? table;
  final List<ResolvedReaderPreformattedLine> preformattedLines;
  final ResolvedReaderImageLayout? image;
  final double totalHeight;
  final bool overflowFits;
  final String fontEvidenceDigest;
  final String sourceStructureDigestLink;
  final String blockLayoutFingerprint;

  int get retainedStateBytes =>
      2 *
      (stableBlockOwner.length +
          fontEvidenceDigest.length +
          sourceStructureDigestLink.length +
          blockLayoutFingerprint.length +
          spanRuns.fold<int>(0, (sum, run) => sum + run.semanticKey.length) +
          paragraphSegments.length * 24 +
          listSegments.length * 56 +
          (table?.cells.length ?? 0) * 64 +
          preformattedLines.length * 32);

  @override
  bool operator ==(Object other) =>
      other is ResolvedReaderBlockLayout &&
      other.blockLayoutFingerprint == blockLayoutFingerprint;

  @override
  int get hashCode => blockLayoutFingerprint.hashCode;
}

@immutable
final class ResolvedReaderCardLayout {
  ResolvedReaderCardLayout({
    required this.contractIdentity,
    required List<ResolvedReaderBlockLayout> blocks,
    required this.physicalLayoutCompositeFingerprint,
    required this.physicalCardIdentityComponents,
  }) : blocks = List<ResolvedReaderBlockLayout>.unmodifiable(blocks);

  final String contractIdentity;
  final List<ResolvedReaderBlockLayout> blocks;
  final String physicalLayoutCompositeFingerprint;
  final String physicalCardIdentityComponents;

  int get retainedStateBytes =>
      2 *
      (contractIdentity.length +
          physicalLayoutCompositeFingerprint.length +
          physicalCardIdentityComponents.length +
          blocks.fold<int>(
            0,
            (sum, block) =>
                sum +
                block.stableBlockOwner.length +
                block.blockLayoutFingerprint.length +
                block.sourceStructureDigestLink.length +
                (block.spanRuns.length * 32) +
                (block.paragraphSegments.length * 24) +
                (block.listSegments.length * 56) +
                ((block.table?.cells.length ?? 0) * 64) +
                (block.preformattedLines.length * 32),
          ));

  @override
  bool operator ==(Object other) =>
      other is ResolvedReaderCardLayout &&
      other.contractIdentity == contractIdentity &&
      other.physicalLayoutCompositeFingerprint ==
          physicalLayoutCompositeFingerprint &&
      other.physicalCardIdentityComponents == physicalCardIdentityComponents;

  @override
  int get hashCode => Object.hash(
    contractIdentity,
    physicalLayoutCompositeFingerprint,
    physicalCardIdentityComponents,
  );
}

/// Normative field registry used by validation and the focused F001–F211 test.
/// The grouped value objects above own the values; this registry prevents a
/// documented semantic from disappearing during refactors.
abstract final class ReaderLayoutFieldCoverage {
  static const List<String> names = <String>[
    'contractRevision',
    'environment',
    'settingsPolicy',
    'geometry',
    'typography',
    'fontEvidence',
    'structure',
    'identities',
    'captureRevision',
    'outerDeckWidth',
    'outerDeckHeight',
    'mediaQueryWidthEvidence',
    'mediaQueryHeightEvidence',
    'deckMediaQueryEquivalence',
    'viewPaddingTop',
    'viewPaddingBottom',
    'viewPaddingLeft',
    'viewPaddingRight',
    'readerLocale',
    'defaultTextDirection',
    'textScaleProfile',
    'captureFreshnessEvidence',
    'effectiveSidePadding',
    'cardDepthEnabled',
    'densityPolicyName',
    'densityPageRatio',
    'densityTinyWordCount',
    'densityTinyHeightRatio',
    'paragraphSpacingMultiplier',
    'cardMarginTop',
    'cardMarginBottom',
    'cardMarginLeft',
    'cardMarginRight',
    'borderStrokeWidth',
    'borderBodyPolicy',
    'borderLayoutInsetTop',
    'borderLayoutInsetBottom',
    'borderLayoutInsetLeft',
    'borderLayoutInsetRight',
    'boundaryTop',
    'boundaryBottom',
    'headerReserve',
    'footerReserve',
    'contentPaddingTop',
    'contentPaddingBottom',
    'contentPaddingLeft',
    'contentPaddingRight',
    'physicalCardWidth',
    'physicalCardHeight',
    'physicalBodyWidth',
    'physicalBodyHeight',
    'minimumCapacityLineCount',
    'safetyReserveLineFactor',
    'safetyReserveDepthBias',
    'safetyReserveMinimum',
    'safetyReserveMaximum',
    'measurementSafetyReserve',
    'physicalPaginationCapacity',
    'ordinaryPaginationHeightBudget',
    'publisherPaginationHeightBudget',
    'minUsefulHeight',
    'publisherIndentClampMaximum',
    'dialogueInset',
    'scaleProfileRevision',
    'logicalSizes',
    'scaledSizes',
    'sizeResponsePairs',
    'positiveZeroNormalized',
    'domainCompletenessDigest',
    'scaleResponseDigest',
    'strutFontRequest',
    'strutLogicalFontSize',
    'strutScaledFontSize',
    'strutHeightMultiplier',
    'strutLeading',
    'strutForceHeight',
    'strutLeadingDistribution',
    'strutTextHeightBehavior',
    'styleRole',
    'declaredFontRequest',
    'requestedWeight',
    'requestedStyle',
    'logicalFontSize',
    'scaledFontSize',
    'lineHeightMultiplier',
    'effectiveLineBoxHeight',
    'letterSpacing',
    'wordSpacing',
    'locale',
    'direction',
    'alignment',
    'softWrap',
    'widthBasis',
    'maxLines',
    'overflowPolicy',
    'textWidthBasis',
    'textLeadingDistribution',
    'fontFeatures',
    'typographyRevision',
    'stylesByRole',
    'strutsByRole',
    'styleCatalogSizeDomain',
    'defaultLocale',
    'defaultDirection',
    'defaultBodyAlignment',
    'requestFamily',
    'requestPackage',
    'requestWeight',
    'requestStyle',
    'requestAxes',
    'requestFeatures',
    'requestLocale',
    'evidenceRevision',
    'readinessState',
    'terminalRequestOutcome',
    'coveredVariantRequests',
    'probeCorpusRevision',
    'sourceRepertoireDigest',
    'probeWidths',
    'singleLineObservations',
    'lineMetricObservations',
    'baselineObservations',
    'lineBoundaryObservations',
    'shapingBoxObservations',
    'fallbackObservationKind',
    'glyphFallbackObservations',
    'stabilityObservationCount',
    'metricEvidenceDigest',
    'rendererRulesRevision',
    'paragraphSegmentPolicy',
    'continuedParagraphPolicy',
    'paragraphGapFormula',
    'headingTextBoxPolicy',
    'headingGap',
    'headingDividerText',
    'headingDividerBoxPolicy',
    'publisherRolePolicies',
    'publisherFirstLineIndentDefault',
    'publisherPreserveLineBreaksPolicy',
    'publisherPreserveWhitespacePolicy',
    'listDepthStep',
    'listMaxIndent',
    'listMarkerWidthMinimum',
    'listMarkerWidthMaximum',
    'resolvedListMarkerGap',
    'listSameBlockGapFactor',
    'listSameItemGapFactor',
    'listNewItemGapFactor',
    'richSpanResolutionPolicy',
    'footnoteMarkerPolicy',
    'tableGridPolicy',
    'tableColumnMinimum',
    'tableOuterVerticalPadding',
    'tableCellHorizontalPadding',
    'tableCellVerticalPadding',
    'tableBorderPolicy',
    'preformattedOuterVerticalPadding',
    'preformattedInnerPadding',
    'preformattedOverflowPolicy',
    'imageFitPolicy',
    'imageBottomPadding',
    'imageReadinessPolicy',
    'separatorSynthesisPolicy',
    'stableBlockOwner',
    'blockKind',
    'sourceLanguageMetadata',
    'resolvedLocale',
    'directionSource',
    'resolvedDirection',
    'resolvedAlignment',
    'resolvedBlockWidth',
    'publisherPaddingLeft',
    'publisherPaddingRight',
    'firstLineIndent',
    'listLeadingIndent',
    'listMarkerWidth',
    'listMarkerGap',
    'orderedParagraphSegments',
    'orderedSpanRuns',
    'gapBoxes',
    'lineBreakPolicy',
    'whitespacePolicy',
    'structuralBoxKind',
    'resolvedTableGrid',
    'resolvedTableColumnWidths',
    'resolvedTableRowHeights',
    'preformattedLineBoxes',
    'imageMetricEvidence',
    'resolvedImageWidth',
    'resolvedImageHeight',
    'resolvedTotalHeight',
    'overflowAuthority',
    'blockLayoutFingerprint',
    'sourceStructureDigestLink',
    'layoutMetricsIdentityRevision',
    'layoutMetricsFingerprint',
    'publicationFingerprint',
    'parserSourceSchemaIdentity',
    'sourceRevision',
    'sourceSnapshotDigest',
    'structuralOwnershipRevision',
    'sourceCompatibilityFingerprint',
    'paginationSemanticRevision',
    'paginationAlgorithmFingerprint',
    'rendererRulesRevisionLink',
    'rendererLayoutFingerprint',
    'compatibilityClassifierRevision',
    'readerCompatibilityFingerprint',
    'orderedBlockLayoutFingerprints',
    'physicalLayoutCompositeFingerprint',
    'physicalCardIdentityComponents',
  ];

  static Map<int, String> get byId =>
      Map<int, String>.unmodifiable(<int, String>{
        for (var index = 0; index < names.length; index++)
          index + 1: names[index],
      });

  static void validate() {
    if (names.length != 211 || names.toSet().length != 211) {
      final duplicates = <String>{
        for (final name in names)
          if (names.where((candidate) => candidate == name).length > 1) name,
      };
      throw StateError(
        'F001–F211 coverage has ${names.length} entries and '
        '${names.toSet().length} unique semantics; duplicates=$duplicates.',
      );
    }
  }
}

TextDirection readerFlutterDirection(ReaderLayoutDirection direction) =>
    direction == ReaderLayoutDirection.rtl
    ? TextDirection.rtl
    : TextDirection.ltr;

ReaderLayoutDirection readerContractDirection(TextDirection direction) =>
    direction == TextDirection.rtl
    ? ReaderLayoutDirection.rtl
    : ReaderLayoutDirection.ltr;
