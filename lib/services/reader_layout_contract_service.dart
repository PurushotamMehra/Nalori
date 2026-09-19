import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/book_chunk.dart';
import '../models/book_list_semantics.dart';
import '../models/reader_font_evidence.dart';
import '../models/reader_layout_contract.dart';
import '../models/reading_settings.dart';
import '../utils/final_layout_paragraphs.dart';
import '../utils/reader_content_parser.dart';

@immutable
final class ReaderLayoutContractBuildInput {
  const ReaderLayoutContractBuildInput({
    required this.deckSize,
    required this.mediaQuerySize,
    required this.viewPadding,
    required this.locale,
    required this.defaultDirection,
    required this.textScaler,
    required this.settings,
    required this.fontOutcome,
    required this.captureFreshnessEvidence,
    required this.publicationFingerprint,
    required this.parserSourceSchemaIdentity,
    required this.sourceRevision,
    required this.sourceSnapshotDigest,
  });

  final Size deckSize;
  final Size? mediaQuerySize;
  final EdgeInsets viewPadding;
  final Locale locale;
  final TextDirection? defaultDirection;
  final TextScaler textScaler;
  final ReadingSettings settings;
  final ReaderFontEvidenceOutcome fontOutcome;
  final String captureFreshnessEvidence;
  final String publicationFingerprint;
  final String parserSourceSchemaIdentity;
  final String sourceRevision;
  final String sourceSnapshotDigest;
}

abstract final class ReaderLayoutContractBuilder {
  static ReaderLayoutContractBuildOutcome build(
    ReaderLayoutContractBuildInput input,
  ) {
    ReaderLayoutFieldCoverage.validate();
    if (!_validSize(input.deckSize) || !_validInsets(input.viewPadding)) {
      return const ReaderLayoutContractNoAuthority(
        ReaderLayoutBuildOutcomeType.invalidNumericValue,
        reason: 'Deck size and viewPadding must be finite and valid.',
      );
    }
    final mediaSize = input.mediaQuerySize;
    final mediaEquivalent = mediaSize == null || mediaSize == input.deckSize;
    if (!mediaEquivalent) {
      return const ReaderLayoutContractNoAuthority(
        ReaderLayoutBuildOutcomeType.incompatibleEnvironment,
        reason: 'The bounded deck and MediaQuery size are not equivalent.',
      );
    }
    final fontOutcome = input.fontOutcome;
    if (fontOutcome is! ReaderFontReadyTerminalBundled ||
        !fontOutcome.canAuthorizeLayout) {
      return ReaderLayoutContractNoAuthority(
        fontOutcome.type == ReaderFontGateOutcomeType.pendingAssetReadiness
            ? ReaderLayoutBuildOutcomeType.pendingFontEvidence
            : ReaderLayoutBuildOutcomeType.unsupportedStructuralInput,
        reason: fontOutcome.reason ?? fontOutcome.type.name,
      );
    }

    try {
      final locale = ReaderCanonicalLocale.fromLocale(input.locale);
      final direction = input.defaultDirection == null
          ? ReaderLayoutDirection.ltr
          : readerContractDirection(input.defaultDirection!);
      final settingsPolicy = _settingsPolicy(input.settings);
      final requests = _requestsByRole(fontOutcome);
      final scaleResponses = <double, double>{
        for (final request in requests.values)
          request.logicalSize: request.scaledSize,
      };
      final domainDigest = _digestStringList(
        requests.entries
            .map((entry) => '${entry.key.name}:${entry.value.logicalSize}')
            .toList()
          ..sort(),
        'reader-scale-domain',
      );
      final scaleWriter = ReaderFontCanonicalWriter('reader-scale-profile', 1);
      var scaleTag = 1;
      for (final entry in scaleResponses.entries) {
        scaleWriter.doubleField(scaleTag++, entry.key);
        scaleWriter.doubleField(scaleTag++, entry.value);
      }
      scaleWriter.stringField(scaleTag, domainDigest);
      final scaleProfile = ResolvedTextScaleProfile(
        responses: scaleResponses,
        domainCompletenessDigest: domainDigest,
        scaleResponseDigest: ReaderFontCanonicalEncoder.digest(
          scaleWriter.takeBytes(),
        ),
      );
      final environment = ReaderLayoutEnvironment(
        outerDeckSize: input.deckSize,
        mediaQuerySizeEvidence: mediaSize,
        deckMediaQueryEquivalent: true,
        viewPadding: input.viewPadding,
        locale: locale,
        defaultDirection: input.defaultDirection == null ? null : direction,
        textScaleProfile: scaleProfile,
        captureFreshnessEvidence: input.captureFreshnessEvidence,
      );
      final typography = _typography(
        requests: requests,
        profile: scaleProfile,
        locale: locale,
        direction: direction,
        alignment: settingsPolicy.defaultAlignment,
      );
      final geometry = _geometry(
        environment: environment,
        policy: settingsPolicy,
        bodyLineBox:
            typography[ReaderLayoutTextRole.body].effectiveLineBoxHeight,
      );
      if (geometry.physicalPaginationCapacity <
          ReaderCardGeometry.minimumCapacityLineCount *
              typography[ReaderLayoutTextRole.body].effectiveLineBoxHeight) {
        return const ReaderLayoutContractNoAuthority(
          ReaderLayoutBuildOutcomeType.incompatibleEnvironment,
          reason: 'The resolved card cannot hold the minimum line capacity.',
        );
      }
      const structure = ReaderStructuralLayoutContract();
      final layoutMetrics = _layoutMetricsIdentity(
        environment,
        settingsPolicy,
        geometry,
        typography,
        fontOutcome.deliveryEvidence.digest,
      );
      final renderer = _rendererLayoutIdentity(structure);
      final source = _sourceCompatibilityIdentity(
        input,
        fontOutcome.sourceEvidence.digest,
      );
      final pagination = _paginationAlgorithmIdentity();
      final composite = ReaderCompatibilityIdentity.compose(
        layoutMetricsIdentity: layoutMetrics,
        sourceCompatibilityIdentity: source,
        paginationAlgorithmIdentity: pagination,
        rendererLayoutIdentity: renderer,
        classifierRevision: readerCompatibilityClassifierRevision,
      );
      final legacyLayoutMetrics = _legacyLayoutMetricsFingerprint(
        environment,
        settingsPolicy,
        geometry,
        typography,
        fontOutcome.deliveryEvidence.digest,
      );
      final legacyPagination = _singleStringFingerprint(
        'reader-pagination-algorithm',
        readerPaginationSemanticRevision,
      );
      final legacyComposite = _digestStringList(<String>[
        legacyLayoutMetrics,
        source.fingerprint,
        legacyPagination,
        renderer.fingerprint,
      ], 'reader-compatibility');
      return ReaderLayoutContractReady(
        ReaderLayoutContract(
          environment: environment,
          settingsPolicy: settingsPolicy,
          geometry: geometry,
          typography: typography,
          fontDeliveryEvidence: fontOutcome.deliveryEvidence,
          structure: structure,
          identities: ReaderLayoutIdentityBundle(
            layoutMetricsFingerprint: legacyLayoutMetrics,
            rendererLayoutFingerprint: renderer.fingerprint,
            sourceCompatibilityFingerprint: source.fingerprint,
            paginationAlgorithmFingerprint: legacyPagination,
            readerCompatibilityFingerprint: legacyComposite,
            layoutMetricsIdentity: layoutMetrics,
            rendererLayoutIdentity: renderer,
            sourceCompatibilityIdentity: source,
            paginationAlgorithmIdentity: pagination,
            readerCompatibilityIdentity: composite,
          ),
        ),
      );
    } on Object catch (error) {
      return ReaderLayoutContractNoAuthority(
        ReaderLayoutBuildOutcomeType.contradictoryDerivedGeometry,
        reason: '$error',
      );
    }
  }

  static ReaderResolvedSettingsPolicy _settingsPolicy(
    ReadingSettings settings,
  ) {
    final density = switch (settings.contentDensity) {
      ContentDensity.low => ReaderLayoutDensity.low,
      ContentDensity.medium => ReaderLayoutDensity.medium,
      ContentDensity.high => ReaderLayoutDensity.high,
      ContentDensity.fullPage => ReaderLayoutDensity.fullPage,
    };
    final tuple = switch (density) {
      ReaderLayoutDensity.low => (0.25, 10, 0.35),
      ReaderLayoutDensity.medium => (0.50, 12, 0.25),
      ReaderLayoutDensity.high => (0.75, 14, 0.18),
      ReaderLayoutDensity.fullPage => (1.0, 16, 0.12),
    };
    final alignment = switch (settings.resolvedTextAlign) {
      TextAlign.left => ReaderLayoutAlignment.left,
      TextAlign.center => ReaderLayoutAlignment.center,
      TextAlign.right => ReaderLayoutAlignment.right,
      TextAlign.justify => ReaderLayoutAlignment.justify,
      TextAlign.start => ReaderLayoutAlignment.start,
      TextAlign.end => ReaderLayoutAlignment.end,
    };
    return ReaderResolvedSettingsPolicy(
      effectiveSidePadding: settings.sideMargin.clamp(12, 56).toDouble(),
      cardDepthEnabled: settings.enableCardDepth,
      density: density,
      densityPageRatio: tuple.$1,
      densityTinyWordCount: tuple.$2,
      densityTinyHeightRatio: tuple.$3,
      paragraphSpacingMultiplier: settings.paragraphSpacing,
      defaultAlignment: alignment,
    );
  }

  static Map<ReaderFontRole, ReaderFontRequestIdentity> _requestsByRole(
    ReaderFontReadyTerminalBundled outcome,
  ) {
    final result = <ReaderFontRole, ReaderFontRequestIdentity>{};
    for (final request in outcome.requests) {
      final previous = result.putIfAbsent(request.role, () => request);
      if (previous.canonicalKey != request.canonicalKey) {
        throw StateError('Terminal font catalog is contradictory.');
      }
    }
    if (result.length != ReaderFontRole.values.length) {
      throw StateError('Terminal evidence does not cover every font role.');
    }
    for (final observation in outcome.sourceEvidence.observations) {
      if (result[observation.request.role]?.canonicalKey !=
          observation.request.canonicalKey) {
        throw StateError('Source observations contradict the font catalog.');
      }
    }
    return result;
  }

  static ReaderTypographyContract _typography({
    required Map<ReaderFontRole, ReaderFontRequestIdentity> requests,
    required ResolvedTextScaleProfile profile,
    required ReaderCanonicalLocale locale,
    required ReaderLayoutDirection direction,
    required ReaderLayoutAlignment alignment,
  }) {
    ReaderResolvedTextStyleSpec style(
      ReaderLayoutTextRole role,
      ReaderFontRole requestRole, {
      ReaderLayoutAlignment? roleAlignment,
      bool softWrap = true,
      String widthBasis = 'block',
      int? maxLines,
      TextOverflow overflow = TextOverflow.clip,
    }) {
      final request = requests[requestRole]!;
      final scaledSize = profile.scale(request.logicalSize);
      return ReaderResolvedTextStyleSpec(
        role: role,
        fontRequest: request,
        logicalFontSize: request.logicalSize,
        scaledFontSize: scaledSize,
        lineHeightMultiplier: request.height,
        effectiveLineBoxHeight: scaledSize * request.height,
        letterSpacing: request.letterSpacing,
        wordSpacing: 0,
        locale: locale,
        direction: direction,
        alignment: roleAlignment ?? alignment,
        softWrap: softWrap,
        widthBasis: widthBasis,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final body = style(ReaderLayoutTextRole.body, ReaderFontRole.body);
    return ReaderTypographyContract(
      styles: <ReaderLayoutTextRole, ReaderResolvedTextStyleSpec>{
        ReaderLayoutTextRole.body: body,
        ReaderLayoutTextRole.heading: style(
          ReaderLayoutTextRole.heading,
          ReaderFontRole.heading,
          roleAlignment: ReaderLayoutAlignment.center,
        ),
        ReaderLayoutTextRole.inlineBold: style(
          ReaderLayoutTextRole.inlineBold,
          ReaderFontRole.inlineBold,
        ),
        ReaderLayoutTextRole.inlineItalic: style(
          ReaderLayoutTextRole.inlineItalic,
          ReaderFontRole.inlineItalic,
        ),
        ReaderLayoutTextRole.inlineBoldItalic: style(
          ReaderLayoutTextRole.inlineBoldItalic,
          ReaderFontRole.inlineBoldItalic,
        ),
        ReaderLayoutTextRole.footnoteMarker: style(
          ReaderLayoutTextRole.footnoteMarker,
          ReaderFontRole.footnote,
        ),
        ReaderLayoutTextRole.listMarker: style(
          ReaderLayoutTextRole.listMarker,
          ReaderFontRole.listMarker,
          roleAlignment: ReaderLayoutAlignment.right,
          softWrap: false,
          widthBasis: 'list_marker',
          maxLines: 1,
        ),
        ReaderLayoutTextRole.tableCell: style(
          ReaderLayoutTextRole.tableCell,
          ReaderFontRole.tableBody,
          roleAlignment: ReaderLayoutAlignment.left,
          widthBasis: 'table_cell',
        ),
        ReaderLayoutTextRole.tableHeader: style(
          ReaderLayoutTextRole.tableHeader,
          ReaderFontRole.tableHeader,
          roleAlignment: ReaderLayoutAlignment.left,
          widthBasis: 'table_cell',
        ),
        ReaderLayoutTextRole.preformatted: style(
          ReaderLayoutTextRole.preformatted,
          ReaderFontRole.preformatted,
          roleAlignment: ReaderLayoutAlignment.left,
          softWrap: false,
          widthBasis: 'intrinsic_line',
        ),
        ReaderLayoutTextRole.headingDivider: style(
          ReaderLayoutTextRole.headingDivider,
          ReaderFontRole.headingDivider,
          roleAlignment: ReaderLayoutAlignment.center,
          softWrap: false,
          maxLines: 1,
        ),
        ReaderLayoutTextRole.publisherProse: _copyRole(
          body,
          ReaderLayoutTextRole.publisherProse,
        ),
        ReaderLayoutTextRole.publisherPoem: _copyRole(
          body,
          ReaderLayoutTextRole.publisherPoem,
          alignment: ReaderLayoutAlignment.left,
        ),
        ReaderLayoutTextRole.publisherQuote: _copyRole(
          body,
          ReaderLayoutTextRole.publisherQuote,
        ),
        ReaderLayoutTextRole.publisherLetter: _copyRole(
          body,
          ReaderLayoutTextRole.publisherLetter,
        ),
      },
      defaultLocale: locale,
      defaultDirection: direction,
      defaultBodyAlignment: alignment,
    );
  }

  static ReaderResolvedTextStyleSpec _copyRole(
    ReaderResolvedTextStyleSpec source,
    ReaderLayoutTextRole role, {
    ReaderLayoutAlignment? alignment,
  }) => ReaderResolvedTextStyleSpec(
    role: role,
    fontRequest: source.fontRequest,
    logicalFontSize: source.logicalFontSize,
    scaledFontSize: source.scaledFontSize,
    lineHeightMultiplier: source.lineHeightMultiplier,
    effectiveLineBoxHeight: source.effectiveLineBoxHeight,
    letterSpacing: source.letterSpacing,
    wordSpacing: source.wordSpacing,
    locale: source.locale,
    direction: source.direction,
    alignment: alignment ?? source.alignment,
    softWrap: source.softWrap,
    widthBasis: source.widthBasis,
    maxLines: source.maxLines,
    overflow: source.overflow,
  );

  static ReaderCardGeometry _geometry({
    required ReaderLayoutEnvironment environment,
    required ReaderResolvedSettingsPolicy policy,
    required double bodyLineBox,
  }) {
    final full = policy.density == ReaderLayoutDensity.fullPage;
    final margin = !policy.cardDepthEnabled
        ? EdgeInsets.zero
        : EdgeInsets.fromLTRB(
            full ? 14 : 18,
            full ? 22 : 28,
            full ? 14 : 18,
            full ? 34 : 42,
          );
    final boundaryTop = full ? 4.0 : 14.0;
    final boundaryBottom = full ? 6.0 : 16.0;
    final header = policy.cardDepthEnabled ? 40.0 : 0.0;
    final footer = policy.cardDepthEnabled ? 42.0 : 0.0;
    final padding = EdgeInsets.fromLTRB(
      environment.viewPadding.left + policy.effectiveSidePadding,
      environment.viewPadding.top + boundaryTop + header,
      environment.viewPadding.right + policy.effectiveSidePadding,
      environment.viewPadding.bottom + boundaryBottom + footer,
    );
    final card = Size(
      environment.outerDeckSize.width - margin.horizontal,
      environment.outerDeckSize.height - margin.vertical,
    );
    final body = Size(
      card.width - padding.horizontal,
      card.height - padding.vertical,
    );
    if (!_validSize(card) || !_validSize(body)) {
      throw StateError('Resolved card/body geometry is nonpositive.');
    }
    final depthBias = policy.cardDepthEnabled ? 4.0 : 0.0;
    final safety =
        ((bodyLineBox * ReaderCardGeometry.safetyReserveLineFactor) + depthBias)
            .clamp(
              ReaderCardGeometry.safetyReserveMinimum,
              ReaderCardGeometry.safetyReserveMaximum,
            );
    final capacity = body.height - safety;
    final ordinary = capacity * policy.densityPageRatio;
    return ReaderCardGeometry(
      cardMargin: margin,
      contentPadding: padding,
      cardSize: card,
      bodySize: body,
      borderStrokeWidth: policy.cardDepthEnabled ? 1.8 : 0,
      measurementSafetyReserve: safety,
      physicalPaginationCapacity: capacity,
      ordinaryPaginationHeightBudget: ordinary,
      publisherPaginationHeightBudget: capacity,
      minUsefulHeight: math.min(
        ordinary * policy.densityTinyHeightRatio,
        ReaderCardGeometry.minimumCapacityLineCount * bodyLineBox,
      ),
    );
  }

  static LayoutMetricsIdentity _layoutMetricsIdentity(
    ReaderLayoutEnvironment environment,
    ReaderResolvedSettingsPolicy policy,
    ReaderCardGeometry geometry,
    ReaderTypographyContract typography,
    String deliveryDigest,
  ) {
    final writer = ReaderFontCanonicalWriter('reader-layout-metrics', 1);
    writer.stringField(1, readerLayoutMetricsIdentityRevision);
    writer.stringField(2, readerLayoutContractRevision);
    writer.doubleField(3, environment.outerDeckSize.width);
    writer.doubleField(4, environment.outerDeckSize.height);
    writer.doubleField(5, environment.viewPadding.top);
    writer.doubleField(6, environment.viewPadding.bottom);
    writer.doubleField(7, environment.viewPadding.left);
    writer.doubleField(8, environment.viewPadding.right);
    writer.stringField(9, environment.locale.tag);
    writer.enumField(
      10,
      (environment.defaultDirection ?? ReaderLayoutDirection.ltr).name,
    );
    writer.stringField(11, environment.textScaleProfile.scaleResponseDigest);
    writer.doubleField(12, policy.effectiveSidePadding);
    writer.boolField(13, policy.cardDepthEnabled);
    writer.enumField(14, policy.density.name);
    writer.doubleField(15, policy.densityPageRatio);
    writer.intField(16, policy.densityTinyWordCount);
    writer.doubleField(17, policy.densityTinyHeightRatio);
    writer.doubleField(18, policy.paragraphSpacingMultiplier);
    writer.enumField(19, policy.defaultAlignment.name);
    writer.doubleField(20, geometry.cardMargin.top);
    writer.doubleField(21, geometry.cardMargin.bottom);
    writer.doubleField(22, geometry.cardMargin.left);
    writer.doubleField(23, geometry.cardMargin.right);
    writer.doubleField(24, geometry.contentPadding.top);
    writer.doubleField(25, geometry.contentPadding.bottom);
    writer.doubleField(26, geometry.contentPadding.left);
    writer.doubleField(27, geometry.contentPadding.right);
    writer.doubleField(28, geometry.bodySize.width);
    writer.doubleField(29, geometry.bodySize.height);
    writer.doubleField(30, geometry.measurementSafetyReserve);
    writer.doubleField(31, geometry.ordinaryPaginationHeightBudget);
    writer.doubleField(32, geometry.publisherPaginationHeightBudget);
    writer.stringField(33, deliveryDigest);
    writer.stringListField(
      34,
      typography.styles.entries.map((entry) {
        final style = entry.value;
        return '${entry.key.name}|${style.fontRequest.canonicalKey}|'
            '${style.scaledFontSize}|${style.lineHeightMultiplier}|'
            '${style.letterSpacing}|${style.wordSpacing}|'
            '${style.alignment.name}|${style.direction.name}|${style.softWrap}|'
            '${style.widthBasis}|${style.maxLines}|${style.overflow.name}';
      }).toList(),
    );
    final bytes = writer.takeBytes();
    return LayoutMetricsIdentity(
      revision: readerLayoutMetricsIdentityRevision,
      canonicalBytes: bytes,
      fingerprint: ReaderFontCanonicalEncoder.digest(bytes),
    );
  }

  static String _legacyLayoutMetricsFingerprint(
    ReaderLayoutEnvironment environment,
    ReaderResolvedSettingsPolicy policy,
    ReaderCardGeometry geometry,
    ReaderTypographyContract typography,
    String deliveryDigest,
  ) {
    final writer = ReaderFontCanonicalWriter('reader-layout-metrics', 1);
    writer.stringField(1, readerLayoutContractRevision);
    writer.doubleField(2, environment.outerDeckSize.width);
    writer.doubleField(3, environment.outerDeckSize.height);
    writer.doubleField(4, environment.viewPadding.top);
    writer.doubleField(5, environment.viewPadding.bottom);
    writer.doubleField(6, environment.viewPadding.left);
    writer.doubleField(7, environment.viewPadding.right);
    writer.stringField(8, environment.locale.tag);
    writer.enumField(
      9,
      (environment.defaultDirection ?? ReaderLayoutDirection.ltr).name,
    );
    writer.stringField(10, environment.textScaleProfile.scaleResponseDigest);
    writer.doubleField(11, policy.effectiveSidePadding);
    writer.boolField(12, policy.cardDepthEnabled);
    writer.enumField(13, policy.density.name);
    writer.doubleField(14, policy.densityPageRatio);
    writer.intField(15, policy.densityTinyWordCount);
    writer.doubleField(16, policy.densityTinyHeightRatio);
    writer.doubleField(17, policy.paragraphSpacingMultiplier);
    writer.enumField(18, policy.defaultAlignment.name);
    writer.doubleField(19, geometry.cardMargin.top);
    writer.doubleField(20, geometry.cardMargin.bottom);
    writer.doubleField(21, geometry.cardMargin.left);
    writer.doubleField(22, geometry.cardMargin.right);
    writer.doubleField(23, geometry.contentPadding.top);
    writer.doubleField(24, geometry.contentPadding.bottom);
    writer.doubleField(25, geometry.contentPadding.left);
    writer.doubleField(26, geometry.contentPadding.right);
    writer.doubleField(27, geometry.bodySize.width);
    writer.doubleField(28, geometry.bodySize.height);
    writer.doubleField(29, geometry.measurementSafetyReserve);
    writer.doubleField(30, geometry.ordinaryPaginationHeightBudget);
    writer.doubleField(31, geometry.publisherPaginationHeightBudget);
    writer.stringField(32, deliveryDigest);
    writer.stringListField(
      33,
      typography.styles.entries.map((entry) {
        final style = entry.value;
        return '${entry.key.name}|${style.fontRequest.canonicalKey}|'
            '${style.scaledFontSize}|${style.lineHeightMultiplier}|'
            '${style.letterSpacing}|${style.wordSpacing}|'
            '${style.alignment.name}|${style.direction.name}|${style.softWrap}|'
            '${style.widthBasis}|${style.maxLines}|${style.overflow.name}';
      }).toList(),
    );
    return ReaderFontCanonicalEncoder.digest(writer.takeBytes());
  }

  static RendererLayoutIdentity _rendererLayoutIdentity(
    ReaderStructuralLayoutContract value,
  ) {
    final writer = ReaderFontCanonicalWriter('reader-renderer-layout', 1);
    writer.stringField(1, readerRendererRulesRevision);
    writer.doubleField(2, value.headingGap);
    writer.stringField(3, value.headingDividerText);
    writer.doubleField(4, value.publisherIndentClampMaximum);
    writer.doubleField(5, value.dialogueInset);
    writer.doubleField(6, value.listDepthStep);
    writer.doubleField(7, value.listMaxIndent);
    writer.doubleField(8, value.listMarkerWidthMinimum);
    writer.doubleField(9, value.listMarkerWidthMaximum);
    writer.doubleField(10, value.listMarkerGap);
    writer.doubleField(11, value.listSameBlockGapFactor);
    writer.doubleField(12, value.listSameItemGapFactor);
    writer.doubleField(13, value.listNewItemGapFactor);
    writer.doubleField(14, value.tableColumnMinimum);
    writer.doubleField(15, value.tableOuterVerticalPadding);
    writer.doubleField(16, value.tableCellHorizontalPadding);
    writer.doubleField(17, value.tableCellVerticalPadding);
    writer.doubleField(18, value.preformattedOuterVerticalPadding);
    writer.doubleField(19, value.preformattedInnerPadding);
    writer.doubleField(20, value.imageBottomPadding);
    final bytes = writer.takeBytes();
    return RendererLayoutIdentity(
      rulesRevisionLink: readerRendererRulesRevision,
      canonicalBytes: bytes,
      fingerprint: ReaderFontCanonicalEncoder.digest(bytes),
    );
  }

  static SourceCompatibilityIdentity _sourceCompatibilityIdentity(
    ReaderLayoutContractBuildInput input,
    String sourceEvidenceDigest,
  ) {
    final writer = ReaderFontCanonicalWriter('reader-source-compatibility', 1);
    writer.stringListField(1, <String>[
      input.publicationFingerprint,
      input.parserSourceSchemaIdentity,
      input.sourceRevision,
      input.sourceSnapshotDigest,
      readerStructuralOwnershipRevision,
      sourceEvidenceDigest,
    ]);
    final bytes = writer.takeBytes();
    return SourceCompatibilityIdentity(
      canonicalBytes: bytes,
      fingerprint: ReaderFontCanonicalEncoder.digest(bytes),
    );
  }

  static PaginationAlgorithmIdentity _paginationAlgorithmIdentity() {
    final writer = ReaderFontCanonicalWriter('reader-pagination-algorithm', 1);
    writer.stringField(1, readerPaginationSemanticRevision);
    final bytes = writer.takeBytes();
    return PaginationAlgorithmIdentity(
      semanticRevision: readerPaginationSemanticRevision,
      canonicalBytes: bytes,
      fingerprint: ReaderFontCanonicalEncoder.digest(bytes),
    );
  }
}

abstract final class ReaderBlockLayoutResolver {
  static ResolvedReaderBlockLayout resolve({
    required ReaderLayoutContract contract,
    required BookChunk chunk,
    required String stableBlockOwner,
    required String sourceStructureDigestLink,
    required List<ReaderSourceFontMetricEvidence> fontEvidence,
    ReaderImageMetricEvidence? imageEvidence,
  }) {
    final text = chunk.text ?? '';
    final kind = _kind(chunk);
    final spans = _spanPlan(chunk, 0, text.length, _baseRole(chunk));
    final hasRenderableText = _hasRenderableTextRepertoire(chunk, kind, text);
    final orderedEvidence = [...fontEvidence]
      ..sort(
        (left, right) =>
            left.sourceStartUtf16.compareTo(right.sourceStartUtf16),
      );
    _validateFontEvidence(
      contract: contract,
      text: text,
      stableBlockOwner: stableBlockOwner,
      evidence: orderedEvidence,
      hasRenderableText: hasRenderableText,
    );
    final evidenceDigest = _digestStringList(
      orderedEvidence.map((evidence) => evidence.digest).toList(),
      'reader-block-font-evidence',
    );
    final direction = contract.typography.defaultDirection;
    final alignment = _alignment(
      chunk,
      contract.settingsPolicy.defaultAlignment,
    );
    final publisherPadding = EdgeInsets.only(
      left: chunk.usesPublisherLayout
          ? chunk.publisherLeftIndent
                .clamp(0, contract.structure.publisherIndentClampMaximum)
                .toDouble()
          : 0,
      right: chunk.usesPublisherLayout
          ? chunk.publisherRightIndent
                .clamp(0, contract.structure.publisherIndentClampMaximum)
                .toDouble()
          : 0,
    );
    final blockWidth =
        contract.geometry.bodySize.width -
        publisherPadding.horizontal -
        (chunk.isDialogue ? contract.structure.dialogueInset : 0);
    if (!blockWidth.isFinite || blockWidth <= 0) {
      throw StateError('Resolved block width is nonpositive.');
    }
    var paragraphs = <ResolvedReaderParagraphSegment>[];
    var lists = <ResolvedReaderListSegment>[];
    ResolvedReaderTableLayout? table;
    var preLines = <ResolvedReaderPreformattedLine>[];
    ResolvedReaderImageLayout? image;
    late double height;

    switch (kind) {
      case ReaderResolvedBlockKind.heading:
        final heading = _measureRuns(
          contract,
          text,
          spans,
          0,
          text.length,
          blockWidth,
          ReaderLayoutAlignment.center,
          direction,
          fallbackRole: ReaderLayoutTextRole.heading,
        );
        final dividerStyle =
            contract.typography[ReaderLayoutTextRole.headingDivider];
        final divider = TextPainter(
          text: TextSpan(
            text: contract.structure.headingDividerText,
            style: dividerStyle.toTextStyle(),
          ),
          textDirection: dividerStyle.textDirection,
          textAlign: TextAlign.center,
          textScaler: TextScaler.noScaling,
          strutStyle: dividerStyle.toStrutStyle(),
          textHeightBehavior: readerTextHeightBehavior,
          maxLines: 1,
        )..layout(maxWidth: blockWidth);
        height = heading + contract.structure.headingGap + divider.height;
        divider.dispose();
        paragraphs = <ResolvedReaderParagraphSegment>[
          ResolvedReaderParagraphSegment(
            startUtf16: 0,
            endUtf16: text.length,
            gapBefore: 0,
          ),
        ];
      case ReaderResolvedBlockKind.list:
        lists = _resolveLists(
          contract,
          chunk,
          text,
          blockWidth,
          alignment,
          direction,
        );
        height = lists.fold<double>(0, (sum, segment) {
          final bodyHeight = _measureRuns(
            contract,
            text,
            segment.spans,
            segment.startUtf16,
            segment.endUtf16,
            blockWidth -
                segment.leadingIndent -
                segment.markerWidth -
                segment.markerGap,
            alignment,
            direction,
          );
          final markerStyle =
              contract.typography[ReaderLayoutTextRole.listMarker];
          final marker = TextPainter(
            text: TextSpan(
              text: segment.marker,
              style: markerStyle.toTextStyle(),
            ),
            textDirection: readerFlutterDirection(direction),
            textAlign: TextAlign.right,
            textScaler: TextScaler.noScaling,
            strutStyle: markerStyle.toStrutStyle(),
            maxLines: 1,
          )..layout(maxWidth: segment.markerWidth);
          final row = math.max(bodyHeight, marker.height);
          marker.dispose();
          return sum + segment.gapBefore + row;
        });
      case ReaderResolvedBlockKind.table:
        table = _resolveTable(contract, chunk, text, blockWidth, direction);
        height = table.totalHeight;
      case ReaderResolvedBlockKind.preformatted:
        preLines = _resolvePreformatted(contract, text);
        height =
            preLines.fold<double>(0, (sum, line) => sum + line.height) +
            (2 * contract.structure.preformattedInnerPadding) +
            (2 * contract.structure.preformattedOuterVerticalPadding);
      case ReaderResolvedBlockKind.image:
        if (imageEvidence == null) {
          throw StateError('Terminal image metrics are required.');
        }
        _validateImageEvidence(chunk, imageEvidence);
        image = _resolveImage(contract, blockWidth, imageEvidence);
        height = image.height + image.bottomPadding;
      case ReaderResolvedBlockKind.paragraph:
        if (!hasRenderableText) {
          height = 0;
        } else {
          paragraphs = _paragraphPlan(contract, chunk, text);
          height = 0;
          for (final segment in paragraphs) {
            height +=
                segment.gapBefore +
                _measureRuns(
                  contract,
                  text,
                  spans,
                  segment.startUtf16,
                  segment.endUtf16,
                  blockWidth,
                  alignment,
                  direction,
                );
          }
        }
      case ReaderResolvedBlockKind.milestone:
        height = 0;
    }
    final budget = chunk.usesPublisherLayout
        ? contract.geometry.publisherPaginationHeightBudget
        : contract.geometry.ordinaryPaginationHeightBudget;
    final overflowFits = height <= budget;
    final fingerprint = _blockFingerprint(
      contract: contract,
      owner: stableBlockOwner,
      kind: kind,
      locale: contract.environment.locale,
      direction: direction,
      alignment: alignment,
      width: blockWidth,
      publisherPadding: publisherPadding,
      paragraphs: paragraphs,
      spans: spans,
      lists: lists,
      table: table,
      preLines: preLines,
      image: image,
      height: height,
      overflowFits: overflowFits,
      evidenceDigest: evidenceDigest,
      sourceStructureDigestLink: sourceStructureDigestLink,
    );
    return ResolvedReaderBlockLayout(
      stableBlockOwner: stableBlockOwner,
      blockKind: kind,
      resolvedLocale: contract.environment.locale,
      directionSource: contract.environment.defaultDirection == null
          ? ReaderLayoutDirectionSource.ltrFallback
          : ReaderLayoutDirectionSource.readerCapture,
      resolvedDirection: direction,
      resolvedAlignment: alignment,
      resolvedBlockWidth: blockWidth,
      publisherPadding: publisherPadding,
      paragraphSegments: paragraphs,
      spanRuns: spans,
      listSegments: lists,
      table: table,
      preformattedLines: preLines,
      image: image,
      totalHeight: height,
      overflowFits: overflowFits,
      fontEvidenceDigest: evidenceDigest,
      sourceStructureDigestLink: sourceStructureDigestLink,
      blockLayoutFingerprint: fingerprint,
    );
  }

  static ReaderResolvedBlockKind _kind(BookChunk chunk) {
    if (chunk.type == BookChunkType.image) return ReaderResolvedBlockKind.image;
    if (chunk.type == BookChunkType.milestone) {
      return ReaderResolvedBlockKind.milestone;
    }
    if (chunk.isHeading) return ReaderResolvedBlockKind.heading;
    if (chunk.effectiveListDisplaySegments.isNotEmpty) {
      return ReaderResolvedBlockKind.list;
    }
    if (chunk.blockRole == BookBlockRole.table) {
      return ReaderResolvedBlockKind.table;
    }
    if (chunk.blockRole == BookBlockRole.preformatted) {
      return ReaderResolvedBlockKind.preformatted;
    }
    return ReaderResolvedBlockKind.paragraph;
  }

  static void _validateFontEvidence({
    required ReaderLayoutContract contract,
    required String text,
    required String stableBlockOwner,
    required List<ReaderSourceFontMetricEvidence> evidence,
    required bool hasRenderableText,
  }) {
    if (evidence.isEmpty) {
      throw StateError('Stable-source font evidence is required.');
    }
    final requests = <ReaderFontRole, ReaderFontRequestIdentity>{};
    for (final style in contract.typography.styles.values) {
      final request = style.fontRequest;
      final previous = requests.putIfAbsent(request.role, () => request);
      if (previous.canonicalKey != request.canonicalKey) {
        throw StateError('The layout font catalog is contradictory.');
      }
    }
    if (requests.length != ReaderFontRole.values.length) {
      throw StateError('The layout font catalog is incomplete.');
    }
    final orderedRequests = <ReaderFontRequestIdentity>[
      for (final role in ReaderFontRole.values) requests[role]!,
    ];
    var coveredUtf16 = 0;
    for (final item in evidence) {
      final start = item.sourceStartUtf16;
      final end = item.sourceEndUtf16;
      if (start != coveredUtf16 ||
          end < start ||
          end > text.length ||
          item.stableSourceIdentity != '$stableBlockOwner|$start:$end') {
        throw StateError(
          'Font evidence does not exactly cover its stable source.',
        );
      }
      if (item.probeRevision != readerFontProbeRevision ||
          item.deliveryEvidenceDigest != contract.fontDeliveryEvidence.digest ||
          item.canonicalBytes.length >
              ReaderSourceFontProbePlan.maximumEvidenceBytesPerSourceUnit) {
        throw StateError('Font evidence has stale or invalid authority.');
      }
      final slice = text.substring(start, end);
      final repertoireDigest = readerFontSourceRepertoireDigest(slice);
      if (item.sourceRepertoireDigest != repertoireDigest) {
        throw StateError('Font evidence claims a different repertoire.');
      }
      final plan = ReaderSourceFontProbePlan(
        stableSourceIdentity: item.stableSourceIdentity,
        sourceStartUtf16: start,
        sourceEndUtf16: end,
        sourceText: slice,
        requests: orderedRequests,
      );
      final canonical = ReaderFontCanonicalEncoder.encodeSource(
        deliveryEvidenceDigest: contract.fontDeliveryEvidence.digest,
        plan: plan,
        repertoireDigest: repertoireDigest,
        observations: item.observations,
      );
      if (!listEquals(canonical, item.canonicalBytes) ||
          ReaderFontCanonicalEncoder.digest(canonical) != item.digest) {
        throw StateError('Font evidence encoding is corrupt or contradictory.');
      }
      if (hasRenderableText) {
        _validateCompleteMetricMatrix(item.observations, requests);
      } else if (!item.isExplicitlyEmptyRepertoire) {
        throw StateError(
          'A no-text layout requires explicit empty-repertoire evidence.',
        );
      }
      coveredUtf16 = end;
    }
    if (coveredUtf16 != text.length) {
      throw StateError(
        'Font evidence has a gap or overlap in source coverage.',
      );
    }
  }

  static bool _hasRenderableTextRepertoire(
    BookChunk chunk,
    ReaderResolvedBlockKind kind,
    String text,
  ) => switch (kind) {
    ReaderResolvedBlockKind.heading || ReaderResolvedBlockKind.list => true,
    ReaderResolvedBlockKind.table ||
    ReaderResolvedBlockKind.preformatted => true,
    ReaderResolvedBlockKind.paragraph =>
      text.isNotEmpty ||
          chunk.isDialogue ||
          chunk.listSemantics != null ||
          (chunk.listDisplaySegments?.isNotEmpty ?? false),
    ReaderResolvedBlockKind.image || ReaderResolvedBlockKind.milestone => false,
  };

  static void _validateCompleteMetricMatrix(
    List<ReaderFontMetricObservation> observations,
    Map<ReaderFontRole, ReaderFontRequestIdentity> requests,
  ) {
    if (observations.length !=
        ReaderSourceFontProbePlan.maximumProbeRunsPerStableSourceUnit) {
      throw StateError('Renderable text requires complete font metrics.');
    }
    final expectedWidths = <double?>{
      null,
      ...ReaderSourceFontProbePlan.approvedProbeWidths,
    };
    final observed = <String>{};
    for (final observation in observations) {
      final expected = requests[observation.request.role];
      if (expected == null ||
          expected.canonicalKey != observation.request.canonicalKey ||
          !expectedWidths.contains(observation.probeWidth) ||
          !observed.add(
            '${observation.request.role.name}|${observation.probeWidth}',
          )) {
        throw StateError(
          'Font metric evidence is incomplete or contradictory.',
        );
      }
    }
    if (observed.length !=
        ReaderSourceFontProbePlan.maximumProbeRunsPerStableSourceUnit) {
      throw StateError('Font metric evidence is incomplete.');
    }
  }

  static ReaderLayoutTextRole _baseRole(BookChunk chunk) =>
      switch (chunk.blockRole) {
        BookBlockRole.heading => ReaderLayoutTextRole.heading,
        BookBlockRole.poem ||
        BookBlockRole.stanza => ReaderLayoutTextRole.publisherPoem,
        BookBlockRole.quote ||
        BookBlockRole.epigraph => ReaderLayoutTextRole.publisherQuote,
        BookBlockRole.letter => ReaderLayoutTextRole.publisherLetter,
        _ =>
          chunk.usesPublisherLayout
              ? ReaderLayoutTextRole.publisherProse
              : ReaderLayoutTextRole.body,
      };

  static ReaderLayoutAlignment _alignment(
    BookChunk chunk,
    ReaderLayoutAlignment fallback,
  ) {
    if (chunk.isHeading) return ReaderLayoutAlignment.center;
    final value = chunk.publisherTextAlign;
    if (chunk.usesPublisherLayout && value != null) {
      return switch (value) {
        BookTextAlign.left => ReaderLayoutAlignment.left,
        BookTextAlign.center => ReaderLayoutAlignment.center,
        BookTextAlign.right => ReaderLayoutAlignment.right,
        BookTextAlign.justify => ReaderLayoutAlignment.justify,
      };
    }
    if (chunk.blockRole == BookBlockRole.poem ||
        chunk.blockRole == BookBlockRole.stanza ||
        chunk.blockRole == BookBlockRole.preformatted ||
        chunk.blockRole == BookBlockRole.table) {
      return ReaderLayoutAlignment.left;
    }
    return fallback;
  }

  static List<ResolvedReaderSpanRun> _spanPlan(
    BookChunk chunk,
    int start,
    int end,
    ReaderLayoutTextRole baseRole,
  ) {
    if (start >= end) return const <ResolvedReaderSpanRun>[];
    final boundaries = <int>{start, end};
    for (final style in chunk.inlineStyles ?? const <InlineStyle>[]) {
      if (style.start > start && style.start < end) boundaries.add(style.start);
      if (style.end > start && style.end < end) boundaries.add(style.end);
    }
    for (final link in chunk.links ?? const <LinkMetadata>[]) {
      if (link.start > start && link.start < end) boundaries.add(link.start);
      if (link.end > start && link.end < end) boundaries.add(link.end);
    }
    final text = chunk.text ?? '';
    for (final footnote in chunk.footnotes ?? const <FootnoteRef>[]) {
      final markerEnd = footnote.position + '[${footnote.label}]'.length;
      if (footnote.position >= start &&
          markerEnd <= end &&
          markerEnd <= text.length) {
        boundaries
          ..add(footnote.position)
          ..add(markerEnd);
      }
    }
    final ordered = boundaries.toList()..sort();
    return List<ResolvedReaderSpanRun>.unmodifiable(<ResolvedReaderSpanRun>[
      for (var index = 0; index < ordered.length - 1; index++)
        if (ordered[index] < ordered[index + 1])
          _runFor(chunk, ordered[index], ordered[index + 1], baseRole),
    ]);
  }

  static ResolvedReaderSpanRun _runFor(
    BookChunk chunk,
    int start,
    int end,
    ReaderLayoutTextRole baseRole,
  ) {
    var bold = false;
    var italic = false;
    for (final style in chunk.inlineStyles ?? const <InlineStyle>[]) {
      if (style.start >= end || style.end <= start) continue;
      bold |=
          style.type == InlineStyleType.bold ||
          style.type == InlineStyleType.boldItalic;
      italic |=
          style.type == InlineStyleType.italic ||
          style.type == InlineStyleType.boldItalic;
    }
    FootnoteRef? footnote;
    for (final value in chunk.footnotes ?? const <FootnoteRef>[]) {
      if (value.position == start && end == start + '[${value.label}]'.length) {
        footnote = value;
        break;
      }
    }
    LinkMetadata? link;
    for (final value in chunk.links ?? const <LinkMetadata>[]) {
      if (value.start <= start && value.end >= end) {
        link = value;
        break;
      }
    }
    final role = footnote != null
        ? ReaderLayoutTextRole.footnoteMarker
        : bold && italic
        ? ReaderLayoutTextRole.inlineBoldItalic
        : bold
        ? ReaderLayoutTextRole.inlineBold
        : italic
        ? ReaderLayoutTextRole.inlineItalic
        : baseRole;
    return ResolvedReaderSpanRun(
      startUtf16: start,
      endUtf16: end,
      role: role,
      semantic: footnote != null
          ? ReaderSpanSemantic.footnoteMarker
          : link != null
          ? ReaderSpanSemantic.link
          : ReaderSpanSemantic.text,
      linkUrl: link?.url,
      footnoteLabel: footnote?.label,
    );
  }

  static List<ResolvedReaderParagraphSegment> _paragraphPlan(
    ReaderLayoutContract contract,
    BookChunk chunk,
    String text,
  ) {
    final segments = splitFinalLayoutParagraphSegments(
      text,
      boundaries: chunk.textBoundaries,
    );
    final gap =
        contract.typography[ReaderLayoutTextRole.body].effectiveLineBoxHeight *
        contract.settingsPolicy.paragraphSpacingMultiplier;
    return <ResolvedReaderParagraphSegment>[
      for (var index = 0; index < segments.length; index++)
        ResolvedReaderParagraphSegment(
          startUtf16: segments[index].startOffset,
          endUtf16: segments[index].startOffset + segments[index].text.length,
          gapBefore: index == 0 ? 0 : gap,
        ),
    ];
  }

  static List<ResolvedReaderListSegment> _resolveLists(
    ReaderLayoutContract contract,
    BookChunk chunk,
    String text,
    double width,
    ReaderLayoutAlignment alignment,
    ReaderLayoutDirection direction,
  ) {
    final result = <ResolvedReaderListSegment>[];
    BookListDisplaySegment? previous;
    for (final segment in chunk.effectiveListDisplaySegments) {
      final start = segment.displayStartOffset.clamp(0, text.length);
      final end = segment.displayEndOffset.clamp(start, text.length);
      if (start >= end) continue;
      final marker = segment.showsMarker
          ? bookListMarkerText(segment.semantics)
          : '';
      final markerStyle = contract.typography[ReaderLayoutTextRole.listMarker];
      final painter = TextPainter(
        text: TextSpan(text: marker, style: markerStyle.toTextStyle()),
        textDirection: readerFlutterDirection(direction),
        textAlign: TextAlign.right,
        textScaler: TextScaler.noScaling,
        strutStyle: markerStyle.toStrutStyle(),
        maxLines: 1,
      )..layout();
      final markerWidth = painter.width.clamp(
        contract.structure.listMarkerWidthMinimum,
        contract.structure.listMarkerWidthMaximum,
      );
      painter.dispose();
      final leading = math.min(
        contract.structure.listMaxIndent,
        segment.semantics.depth * contract.structure.listDepthStep,
      );
      final gap = previous == null
          ? 0.0
          : _listGap(contract, previous, segment);
      result.add(
        ResolvedReaderListSegment(
          startUtf16: start,
          endUtf16: end,
          marker: marker,
          leadingIndent: leading,
          markerWidth: markerWidth,
          markerGap: contract.structure.listMarkerGap,
          gapBefore: gap,
          spans: _spanPlan(chunk, start, end, _baseRole(chunk)),
        ),
      );
      previous = segment;
    }
    return List<ResolvedReaderListSegment>.unmodifiable(result);
  }

  static double _listGap(
    ReaderLayoutContract contract,
    BookListDisplaySegment previous,
    BookListDisplaySegment current,
  ) {
    final sameBlock =
        previous.semantics.itemId == current.semantics.itemId &&
        previous.semantics.blockIndex == current.semantics.blockIndex;
    final factor = sameBlock
        ? contract.structure.listSameBlockGapFactor
        : previous.semantics.itemId == current.semantics.itemId
        ? contract.structure.listSameItemGapFactor
        : contract.structure.listNewItemGapFactor;
    return contract
            .typography[ReaderLayoutTextRole.body]
            .effectiveLineBoxHeight *
        factor *
        contract.settingsPolicy.paragraphSpacingMultiplier;
  }

  static ResolvedReaderTableLayout _resolveTable(
    ReaderLayoutContract contract,
    BookChunk chunk,
    String text,
    double width,
    ReaderLayoutDirection direction,
  ) {
    final table = requireNormalizedReaderTable(text);
    final columnCount = table.columnCount;
    final scrollWidth = math.max(
      width,
      contract.structure.tableColumnMinimum * columnCount,
    );
    final columnWidth = scrollWidth / columnCount;
    final sourceRows = table.cellRows.isNotEmpty
        ? table.cellRows
        : <List<ReaderTableCell>>[
            if (table.headers.isNotEmpty)
              <ReaderTableCell>[
                for (final value in table.headers)
                  ReaderTableCell(text: value, isHeader: true),
              ],
            for (final row in table.rows)
              <ReaderTableCell>[
                for (final value in row) ReaderTableCell(text: value),
              ],
          ];
    final occupied = <String>{};
    final placements = <({ReaderTableCell cell, int row, int column})>[];
    var rowCount = sourceRows.length;
    for (var row = 0; row < sourceRows.length; row++) {
      var column = 0;
      for (final cell in sourceRows[row]) {
        while (occupied.contains('$row:$column')) {
          column++;
        }
        if (column >= columnCount) break;
        final columnSpan = math.min(cell.columnSpan, columnCount - column);
        final rowSpan = math.max(1, cell.rowSpan);
        placements.add((cell: cell, row: row, column: column));
        rowCount = math.max(rowCount, row + rowSpan);
        for (var y = row; y < row + rowSpan; y++) {
          for (var x = column; x < column + columnSpan; x++) {
            occupied.add('$y:$x');
          }
        }
        column += columnSpan;
      }
    }
    final rowHeights = List<double>.filled(rowCount, 0);
    final measured = <ResolvedReaderTableCell>[];
    for (final placement in placements) {
      final source = placement.cell;
      final isHeader = source.isHeader;
      final role = isHeader
          ? ReaderLayoutTextRole.tableHeader
          : ReaderLayoutTextRole.tableCell;
      final style = contract.typography[role];
      final columnSpan = math.min(
        source.columnSpan,
        columnCount - placement.column,
      );
      final rowSpan = math.max(1, source.rowSpan);
      final cellWidth = columnWidth * columnSpan;
      final painter =
          TextPainter(
            text: TextSpan(text: source.text, style: style.toTextStyle()),
            textDirection: readerFlutterDirection(direction),
            textAlign: TextAlign.left,
            textScaler: TextScaler.noScaling,
            strutStyle: style.toStrutStyle(),
            textHeightBehavior: readerTextHeightBehavior,
          )..layout(
            maxWidth:
                cellWidth - (2 * contract.structure.tableCellHorizontalPadding),
          );
      final cellHeight =
          painter.height + (2 * contract.structure.tableCellVerticalPadding);
      painter.dispose();
      if (rowSpan == 1) {
        rowHeights[placement.row] = math.max(
          rowHeights[placement.row],
          cellHeight,
        );
      }
      measured.add(
        ResolvedReaderTableCell(
          text: source.text,
          isHeader: isHeader,
          row: placement.row,
          column: placement.column,
          rowSpan: rowSpan,
          columnSpan: columnSpan,
          width: cellWidth,
          height: cellHeight,
          spans: source.text.isEmpty
              ? const <ResolvedReaderSpanRun>[]
              : <ResolvedReaderSpanRun>[
                  ResolvedReaderSpanRun(
                    startUtf16: 0,
                    endUtf16: source.text.length,
                    role: role,
                    semantic: ReaderSpanSemantic.text,
                  ),
                ],
        ),
      );
    }
    final minimumRowHeight =
        contract
            .typography[ReaderLayoutTextRole.tableCell]
            .effectiveLineBoxHeight +
        (2 * contract.structure.tableCellVerticalPadding);
    for (var row = 0; row < rowHeights.length; row++) {
      rowHeights[row] = math.max(rowHeights[row], minimumRowHeight);
    }
    for (final cell in measured.where((value) => value.rowSpan > 1)) {
      final occupiedHeight = rowHeights
          .skip(cell.row)
          .take(cell.rowSpan)
          .fold<double>(0, (sum, value) => sum + value);
      if (occupiedHeight < cell.height) {
        rowHeights[cell.row + cell.rowSpan - 1] += cell.height - occupiedHeight;
      }
    }
    final cells = <ResolvedReaderTableCell>[
      for (final cell in measured)
        ResolvedReaderTableCell(
          text: cell.text,
          isHeader: cell.isHeader,
          row: cell.row,
          column: cell.column,
          rowSpan: cell.rowSpan,
          columnSpan: cell.columnSpan,
          width: cell.width,
          height: rowHeights
              .skip(cell.row)
              .take(cell.rowSpan)
              .fold<double>(0, (sum, value) => sum + value),
          spans: cell.spans,
        ),
    ];
    return ResolvedReaderTableLayout(
      columnWidths: List<double>.filled(columnCount, columnWidth),
      rowHeights: rowHeights,
      cells: cells,
      horizontalScrollWidth: scrollWidth,
      totalHeight:
          rowHeights.fold<double>(0, (sum, value) => sum + value) +
          (2 * contract.structure.tableOuterVerticalPadding),
    );
  }

  static List<ResolvedReaderPreformattedLine> _resolvePreformatted(
    ReaderLayoutContract contract,
    String text,
  ) {
    final style = contract.typography[ReaderLayoutTextRole.preformatted];
    final result = <ResolvedReaderPreformattedLine>[];
    var start = 0;
    for (var index = 0; index <= text.length; index++) {
      if (index != text.length && text.codeUnitAt(index) != 10) continue;
      final end = index == text.length ? index : index + 1;
      final lineText = text.substring(start, end);
      final painter = TextPainter(
        text: TextSpan(text: lineText, style: style.toTextStyle()),
        textDirection: style.textDirection,
        textAlign: TextAlign.left,
        textScaler: TextScaler.noScaling,
        strutStyle: style.toStrutStyle(),
        textHeightBehavior: readerTextHeightBehavior,
        maxLines: 1,
      )..layout();
      result.add(
        ResolvedReaderPreformattedLine(
          startUtf16: start,
          endUtf16: end,
          width: painter.width,
          height: painter.height,
        ),
      );
      painter.dispose();
      start = end;
    }
    return List<ResolvedReaderPreformattedLine>.unmodifiable(result);
  }

  static ResolvedReaderImageLayout _resolveImage(
    ReaderLayoutContract contract,
    double blockWidth,
    ReaderImageMetricEvidence evidence,
  ) {
    final maximumHeight =
        contract.geometry.publisherPaginationHeightBudget -
        contract.structure.imageBottomPadding;
    final widthScale = blockWidth / evidence.intrinsicWidth;
    final heightScale = maximumHeight / evidence.intrinsicHeight;
    final scale = math.min(1.0, math.min(widthScale, heightScale));
    return ResolvedReaderImageLayout(
      evidence: evidence,
      width: evidence.intrinsicWidth * scale,
      height: evidence.intrinsicHeight * scale,
      bottomPadding: contract.structure.imageBottomPadding,
    );
  }

  static void _validateImageEvidence(
    BookChunk chunk,
    ReaderImageMetricEvidence evidence,
  ) {
    final bytes = chunk.imageBytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Image source bytes are unavailable.');
    }
    if (evidence.intrinsicWidth <= 0 || evidence.intrinsicHeight <= 0) {
      throw StateError('Image intrinsic metrics are invalid.');
    }
    final bytesDigest = sha256.convert(bytes).toString();
    if (evidence.bytesDigest != bytesDigest) {
      throw StateError('Image metric evidence belongs to different bytes.');
    }
    final writer = ReaderFontCanonicalWriter('reader-image-metrics', 1)
      ..stringField(1, bytesDigest)
      ..intField(2, evidence.intrinsicWidth)
      ..intField(3, evidence.intrinsicHeight);
    if (evidence.evidenceDigest !=
        ReaderFontCanonicalEncoder.digest(writer.takeBytes())) {
      throw StateError('Image metric evidence digest is contradictory.');
    }
  }

  static double _measureRuns(
    ReaderLayoutContract contract,
    String text,
    List<ResolvedReaderSpanRun> runs,
    int start,
    int end,
    double width,
    ReaderLayoutAlignment alignment,
    ReaderLayoutDirection direction, {
    ReaderLayoutTextRole? fallbackRole,
  }) {
    final children = <InlineSpan>[];
    for (final run in runs) {
      final overlapStart = math.max(start, run.startUtf16);
      final overlapEnd = math.min(end, run.endUtf16);
      if (overlapStart >= overlapEnd) continue;
      children.add(
        TextSpan(
          text: text.substring(overlapStart, overlapEnd),
          style: contract.typography[run.role].toTextStyle(),
        ),
      );
    }
    if (children.isEmpty && start < end) {
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: contract.typography[fallbackRole ?? ReaderLayoutTextRole.body]
              .toTextStyle(),
        ),
      );
    }
    final base = contract.typography[fallbackRole ?? ReaderLayoutTextRole.body];
    final painter = TextPainter(
      text: TextSpan(children: children),
      textDirection: readerFlutterDirection(direction),
      textAlign: switch (alignment) {
        ReaderLayoutAlignment.left => TextAlign.left,
        ReaderLayoutAlignment.center => TextAlign.center,
        ReaderLayoutAlignment.right => TextAlign.right,
        ReaderLayoutAlignment.justify => TextAlign.justify,
        ReaderLayoutAlignment.start => TextAlign.start,
        ReaderLayoutAlignment.end => TextAlign.end,
      },
      locale: contract.environment.locale.flutterLocale,
      textScaler: TextScaler.noScaling,
      strutStyle: base.toStrutStyle(),
      textHeightBehavior: readerTextHeightBehavior,
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  static String _blockFingerprint({
    required ReaderLayoutContract contract,
    required String owner,
    required ReaderResolvedBlockKind kind,
    required ReaderCanonicalLocale locale,
    required ReaderLayoutDirection direction,
    required ReaderLayoutAlignment alignment,
    required double width,
    required EdgeInsets publisherPadding,
    required List<ResolvedReaderParagraphSegment> paragraphs,
    required List<ResolvedReaderSpanRun> spans,
    required List<ResolvedReaderListSegment> lists,
    required ResolvedReaderTableLayout? table,
    required List<ResolvedReaderPreformattedLine> preLines,
    required ResolvedReaderImageLayout? image,
    required double height,
    required bool overflowFits,
    required String evidenceDigest,
    required String sourceStructureDigestLink,
  }) {
    final writer = ReaderFontCanonicalWriter('reader-block-layout', 1);
    writer.stringField(1, owner);
    writer.enumField(2, kind.name);
    writer.stringField(3, locale.tag);
    writer.enumField(4, direction.name);
    writer.enumField(5, alignment.name);
    writer.doubleField(6, width);
    writer.doubleField(7, publisherPadding.left);
    writer.doubleField(8, publisherPadding.right);
    writer.stringListField(
      9,
      paragraphs
          .map(
            (value) =>
                '${value.startUtf16}:${value.endUtf16}:${value.gapBefore}',
          )
          .toList(),
    );
    writer.stringListField(
      10,
      spans
          .map(
            (value) =>
                '${value.startUtf16}:${value.endUtf16}:${value.role.name}:${value.semantic.name}:${value.linkUrl ?? ''}:${value.footnoteLabel ?? ''}',
          )
          .toList(),
    );
    writer.stringListField(
      11,
      lists
          .map(
            (value) =>
                '${value.startUtf16}:${value.endUtf16}:${value.marker}:${value.leadingIndent}:${value.markerWidth}:${value.markerGap}:${value.gapBefore}',
          )
          .toList(),
    );
    writer.stringListField(
      12,
      table == null
          ? const <String>[]
          : <String>[
              ...table.columnWidths.map((value) => 'c:$value'),
              ...table.rowHeights.map((value) => 'r:$value'),
              'w:${table.horizontalScrollWidth}',
              'h:${table.totalHeight}',
            ],
    );
    writer.stringListField(
      13,
      preLines
          .map(
            (value) =>
                '${value.startUtf16}:${value.endUtf16}:${value.width}:${value.height}',
          )
          .toList(),
    );
    writer.optionalStringField(14, image?.evidence.evidenceDigest);
    writer.optionalDoubleField(16, image?.width);
    writer.optionalDoubleField(18, image?.height);
    writer.doubleField(20, height);
    writer.boolField(21, overflowFits);
    writer.stringField(22, evidenceDigest);
    writer.stringField(23, sourceStructureDigestLink);
    writer.stringField(24, contract.identities.layoutMetricsFingerprint);
    writer.stringField(25, contract.identities.rendererLayoutFingerprint);
    return ReaderFontCanonicalEncoder.digest(writer.takeBytes());
  }
}

abstract final class ReaderCardLayoutResolver {
  static ResolvedReaderCardLayout resolve({
    required ReaderLayoutContract contract,
    required ResolvedReaderBlockLayout block,
    required String physicalSourceIdentity,
  }) {
    final composite = _digestStringList(<String>[
      contract.identities.layoutMetricsFingerprint,
      contract.identities.rendererLayoutFingerprint,
      block.blockLayoutFingerprint,
    ], 'reader-physical-layout');
    final components = _digestStringList(<String>[
      contract.identities.sourceCompatibilityFingerprint,
      contract.identities.paginationAlgorithmFingerprint,
      composite,
      physicalSourceIdentity,
    ], 'reader-physical-card-components');
    return ResolvedReaderCardLayout(
      contractIdentity: contract.identity,
      blocks: <ResolvedReaderBlockLayout>[block],
      physicalLayoutCompositeFingerprint: composite,
      physicalCardIdentityComponents: components,
    );
  }
}

abstract final class ReaderLayoutMeasurementAdapter {
  static double blockHeight(ResolvedReaderBlockLayout block) {
    if (!block.totalHeight.isFinite || block.totalHeight < 0) {
      throw StateError('Resolved block has no measurement authority.');
    }
    return block.totalHeight;
  }
}

abstract final class ReaderLayoutRenderingAdapter {
  static ResolvedReaderBlockLayout block({
    required ReaderLayoutContract contract,
    required ResolvedReaderCardLayout card,
  }) {
    if (card.contractIdentity != contract.identity || card.blocks.length != 1) {
      throw StateError(
        'Resolved card does not belong to this layout contract.',
      );
    }
    final block = card.blocks.single;
    ReaderLayoutMeasurementAdapter.blockHeight(block);
    if (!block.overflowFits) {
      throw StateError('Resolved card contains an overflowing block.');
    }
    return block;
  }
}

Future<ReaderImageMetricEvidence> resolveReaderImageMetricEvidence(
  Uint8List bytes,
) async {
  if (bytes.isEmpty) throw const FormatException('Image bytes are empty.');
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      if (frame.image.width <= 0 || frame.image.height <= 0) {
        throw const FormatException('Decoded image dimensions are invalid.');
      }
      final bytesDigest = sha256.convert(bytes).toString();
      final writer = ReaderFontCanonicalWriter('reader-image-metrics', 1);
      writer.stringField(1, bytesDigest);
      writer.intField(2, frame.image.width);
      writer.intField(3, frame.image.height);
      return ReaderImageMetricEvidence(
        bytesDigest: bytesDigest,
        intrinsicWidth: frame.image.width,
        intrinsicHeight: frame.image.height,
        evidenceDigest: ReaderFontCanonicalEncoder.digest(writer.takeBytes()),
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

bool _validSize(Size value) =>
    value.width.isFinite &&
    value.height.isFinite &&
    value.width > 0 &&
    value.height > 0;

bool _validInsets(EdgeInsets value) => <double>[
  value.top,
  value.bottom,
  value.left,
  value.right,
].every((item) => item.isFinite && item >= 0);

String _singleStringFingerprint(String kind, String value) =>
    _digestStringList(<String>[value], kind);

String _digestStringList(List<String> values, String kind) {
  final writer = ReaderFontCanonicalWriter(kind, 1);
  writer.stringListField(1, values);
  return ReaderFontCanonicalEncoder.digest(writer.takeBytes());
}
