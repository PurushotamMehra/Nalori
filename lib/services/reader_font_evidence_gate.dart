import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reader_font_evidence.dart';
import '../models/reading_settings.dart';

typedef ReaderFontBundleReader = Future<ByteData> Function(String assetPath);
typedef ReaderFontFamilyLoader =
    Future<void> Function(String localFamily, List<ByteData> fontBytes);
typedef ReaderFontEvidenceStabilityComparator =
    bool Function(
      ReaderSourceFontMetricEvidence first,
      ReaderSourceFontMetricEvidence second,
    );

final class ReaderFontEvidenceGate {
  ReaderFontEvidenceGate({
    ReaderFontBundleReader? bundleReader,
    ReaderFontFamilyLoader? familyLoader,
    ReaderFontEvidenceStabilityComparator? stabilityComparator,
  }) : _bundleReader = bundleReader ?? rootBundle.load,
       _familyLoader = familyLoader ?? _loadFamily,
       _stabilityComparator = stabilityComparator ?? _sameEvidence;

  static const String manifestAssetPath = 'assets/fonts/reader/manifest.json';
  static const int expectedAssetCount = 74;
  static const int expectedTotalAssetBytes = 19348768;

  final ReaderFontBundleReader _bundleReader;
  final ReaderFontFamilyLoader _familyLoader;
  final ReaderFontEvidenceStabilityComparator _stabilityComparator;
  final LinkedHashMap<String, ReaderSourceFontMetricEvidence> _sourceCache =
      LinkedHashMap<String, ReaderSourceFontMetricEvidence>();

  ReaderFontEvidenceOutcome _currentOutcome =
      const ReaderFontPendingAssetReadiness(reason: 'notPrepared');
  Future<_PreparedDelivery>? _preparing;
  _PreparedDelivery? _prepared;

  ReaderFontEvidenceOutcome get currentOutcome => _currentOutcome;
  int get retainedSourceEvidenceCount => _sourceCache.length;
  int get retainedSourceEvidenceBytes => _sourceCache.values.fold<int>(
    0,
    (total, evidence) => total + evidence.canonicalBytes.length,
  );

  void releaseRetainedSourceEvidence() {
    _sourceCache.clear();
  }

  Future<ReaderFontEvidenceOutcome> capture({
    required ReadingSettings settings,
    required String stableSourceIdentity,
    required int sourceStartUtf16,
    required String sourceText,
    String? locale,
    TextScaler textScaler = TextScaler.noScaling,
    bool Function()? isCancelled,
    bool Function()? isStale,
  }) async {
    if (isCancelled?.call() ?? false) return _cancelled();
    if (isStale?.call() ?? false) return _stale();
    _currentOutcome = const ReaderFontPendingAssetReadiness(
      reason: 'assetAndMetricCaptureInProgress',
    );

    final preparedResult = await _prepareDelivery();
    if (preparedResult case _PreparationFailure(:final outcome)) {
      return _currentOutcome = outcome;
    }
    final prepared = (preparedResult as _PreparationSuccess).prepared;
    if (isCancelled?.call() ?? false) return _cancelled();
    if (isStale?.call() ?? false) return _stale();

    ReaderSourceFontProbePlan plan;
    try {
      plan = buildProbePlan(
        catalog: prepared.catalog,
        settings: settings,
        stableSourceIdentity: stableSourceIdentity,
        sourceStartUtf16: sourceStartUtf16,
        sourceText: sourceText,
        locale: locale,
        textScaler: textScaler,
      );
    } on Object catch (error) {
      return _currentOutcome = ReaderFontEvidenceRejected(
        ReaderFontGateOutcomeType.rejectedIncompleteVariantCoverage,
        reason: '$error',
      );
    }

    final cacheKey = _cacheKey(prepared.evidence.digest, plan);
    final cached = _sourceCache.remove(cacheKey);
    if (cached != null) {
      _sourceCache[cacheKey] = cached;
      return _currentOutcome = ReaderFontReadyTerminalBundled(
        deliveryEvidence: prepared.evidence,
        sourceEvidence: cached,
        requests: plan.requests,
      );
    }

    try {
      final first = _measureSource(prepared.evidence, plan);
      if (isCancelled?.call() ?? false) return _cancelled();
      if (isStale?.call() ?? false) return _stale();
      final second = _measureSource(prepared.evidence, plan);
      if (!_stabilityComparator(first, second)) {
        return _currentOutcome = const ReaderFontEvidenceRejected(
          ReaderFontGateOutcomeType.rejectedContradictoryEvidence,
          reason: 'Repeated text-engine observations were not stable.',
        );
      }
      if (first.canonicalBytes.length >
          ReaderSourceFontProbePlan.maximumEvidenceBytesPerSourceUnit) {
        return _currentOutcome = ReaderFontEvidenceRejected(
          ReaderFontGateOutcomeType.rejectedUnavailableMetricEvidence,
          reason:
              'Evidence bytes ${first.canonicalBytes.length} exceed '
              '${ReaderSourceFontProbePlan.maximumEvidenceBytesPerSourceUnit}.',
        );
      }
      if (isCancelled?.call() ?? false) return _cancelled();
      if (isStale?.call() ?? false) return _stale();
      _sourceCache[cacheKey] = first;
      while (_sourceCache.length >
          ReaderSourceFontProbePlan.maximumRetainedSourceEvidenceRecords) {
        _sourceCache.remove(_sourceCache.keys.first);
      }
      return _currentOutcome = ReaderFontReadyTerminalBundled(
        deliveryEvidence: prepared.evidence,
        sourceEvidence: first,
        requests: plan.requests,
      );
    } on Object catch (error) {
      return _currentOutcome = ReaderFontEvidenceRejected(
        ReaderFontGateOutcomeType.rejectedUnavailableMetricEvidence,
        reason: '$error',
      );
    }
  }

  /// Captures exact-slice evidence after bundled delivery has already reached
  /// terminal readiness. Pagination uses this synchronous boundary so it
  /// never scans or probes an entire publication in advance.
  ReaderFontEvidenceOutcome capturePrepared({
    required ReadingSettings settings,
    required String stableSourceIdentity,
    required int sourceStartUtf16,
    required String sourceText,
    String? locale,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final prepared = _prepared;
    if (prepared == null) {
      return _currentOutcome = const ReaderFontPendingAssetReadiness(
        reason: 'bundledDeliveryNotPrepared',
      );
    }
    try {
      final plan = buildProbePlan(
        catalog: prepared.catalog,
        settings: settings,
        stableSourceIdentity: stableSourceIdentity,
        sourceStartUtf16: sourceStartUtf16,
        sourceText: sourceText,
        locale: locale,
        textScaler: textScaler,
      );
      final cacheKey = _cacheKey(prepared.evidence.digest, plan);
      final cached = _sourceCache.remove(cacheKey);
      if (cached != null) {
        _sourceCache[cacheKey] = cached;
        return _currentOutcome = ReaderFontReadyTerminalBundled(
          deliveryEvidence: prepared.evidence,
          sourceEvidence: cached,
          requests: plan.requests,
        );
      }
      final first = _measureSource(prepared.evidence, plan);
      final second = _measureSource(prepared.evidence, plan);
      if (!_stabilityComparator(first, second)) {
        return _currentOutcome = const ReaderFontEvidenceRejected(
          ReaderFontGateOutcomeType.rejectedContradictoryEvidence,
          reason: 'Repeated text-engine observations were not stable.',
        );
      }
      if (first.canonicalBytes.length >
          ReaderSourceFontProbePlan.maximumEvidenceBytesPerSourceUnit) {
        return _currentOutcome = const ReaderFontEvidenceRejected(
          ReaderFontGateOutcomeType.rejectedUnavailableMetricEvidence,
          reason: 'Exact-slice evidence exceeds the retained byte bound.',
        );
      }
      _sourceCache[cacheKey] = first;
      while (_sourceCache.length >
          ReaderSourceFontProbePlan.maximumRetainedSourceEvidenceRecords) {
        _sourceCache.remove(_sourceCache.keys.first);
      }
      return _currentOutcome = ReaderFontReadyTerminalBundled(
        deliveryEvidence: prepared.evidence,
        sourceEvidence: first,
        requests: plan.requests,
      );
    } on Object catch (error) {
      return _currentOutcome = ReaderFontEvidenceRejected(
        ReaderFontGateOutcomeType.rejectedUnavailableMetricEvidence,
        reason: '$error',
      );
    }
  }

  Future<_PreparationResult> _prepareDelivery() async {
    if (_prepared case final prepared?) return _PreparationSuccess(prepared);
    final active = _preparing;
    if (active != null) {
      try {
        return _PreparationSuccess(await active);
      } on _PreparationException catch (error) {
        return _PreparationFailure(error.outcome);
      }
    }
    final future = _loadAndValidateDelivery();
    _preparing = future;
    try {
      final result = await future;
      _prepared = result;
      return _PreparationSuccess(result);
    } on _PreparationException catch (error) {
      return _PreparationFailure(error.outcome);
    } finally {
      _preparing = null;
    }
  }

  Future<_PreparedDelivery> _loadAndValidateDelivery() async {
    late ByteData manifestBytes;
    try {
      manifestBytes = await _bundleReader(manifestAssetPath);
    } on Object catch (error) {
      throw _PreparationException(
        ReaderFontEvidenceRejected(
          ReaderFontGateOutcomeType.rejectedMissingAsset,
          reason: 'Missing font manifest: $error',
        ),
      );
    }

    ReaderBundledFontCatalog catalog;
    try {
      final json = jsonDecode(utf8.decode(manifestBytes.buffer.asUint8List()));
      catalog = ReaderBundledFontCatalogParser.parse(json);
      ReaderBundledFontCatalogParser.validate(catalog);
    } on Object catch (error) {
      throw _PreparationException(
        ReaderFontEvidenceRejected(
          ReaderFontGateOutcomeType.rejectedIncompleteVariantCoverage,
          reason: '$error',
        ),
      );
    }

    final familyBytes = <String, List<ByteData>>{};
    var totalBytes = 0;
    for (final licensePath
        in catalog.assets.map((asset) => asset.licensePath).toSet()) {
      try {
        final license = await _bundleReader(licensePath);
        final text = utf8.decode(license.buffer.asUint8List());
        if (!text.contains('SIL OPEN FONT LICENSE') || text.trim().isEmpty) {
          throw StateError('Not an OFL notice.');
        }
      } on Object catch (error) {
        throw _PreparationException(
          ReaderFontEvidenceRejected(
            ReaderFontGateOutcomeType.rejectedMissingAsset,
            reason: 'Missing or invalid licence $licensePath: $error',
          ),
        );
      }
    }
    for (final asset in catalog.assets) {
      late ByteData data;
      try {
        data = await _bundleReader(asset.assetPath);
      } on Object catch (error) {
        throw _PreparationException(
          ReaderFontEvidenceRejected(
            ReaderFontGateOutcomeType.rejectedMissingAsset,
            reason: 'Missing ${asset.assetPath}: $error',
          ),
        );
      }
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (bytes.length != asset.byteLength ||
          sha256.convert(bytes).toString() != asset.sha256) {
        throw _PreparationException(
          ReaderFontEvidenceRejected(
            ReaderFontGateOutcomeType.rejectedDigestMismatch,
            reason: 'Asset integrity mismatch: ${asset.assetPath}',
          ),
        );
      }
      familyBytes.putIfAbsent(asset.localFamily, () => <ByteData>[]).add(data);
      totalBytes += bytes.length;
    }
    if (catalog.assets.length != expectedAssetCount ||
        totalBytes != expectedTotalAssetBytes) {
      throw _PreparationException(
        ReaderFontEvidenceRejected(
          ReaderFontGateOutcomeType.rejectedIncompleteVariantCoverage,
          reason:
              'Expected $expectedAssetCount/$expectedTotalAssetBytes assets/bytes; '
              'found ${catalog.assets.length}/$totalBytes.',
        ),
      );
    }
    for (final entry in familyBytes.entries) {
      try {
        await _familyLoader(entry.key, entry.value);
      } on Object catch (error) {
        throw _PreparationException(
          ReaderFontEvidenceRejected(
            ReaderFontGateOutcomeType.rejectedUnavailableMetricEvidence,
            reason:
                'Text-engine font registration failed for ${entry.key}: $error',
          ),
        );
      }
    }
    final canonical = ReaderFontCanonicalEncoder.encodeDelivery(
      catalog: catalog,
    );
    final evidence = ReaderFontDeliveryEvidence(
      catalogRevision: catalog.revision,
      descriptorSource: catalog.descriptorSource,
      assetCount: catalog.assets.length,
      totalAssetBytes: totalBytes,
      canonicalBytes: canonical,
      digest: ReaderFontCanonicalEncoder.digest(canonical),
    );
    return _PreparedDelivery(catalog, evidence);
  }

  ReaderFontEvidenceOutcome _cancelled() =>
      _currentOutcome = const ReaderFontEvidenceRejected(
        ReaderFontGateOutcomeType.rejectedCancelled,
        reason: 'Capture was cancelled.',
      );

  ReaderFontEvidenceOutcome _stale() =>
      _currentOutcome = const ReaderFontEvidenceRejected(
        ReaderFontGateOutcomeType.rejectedStaleCapture,
        reason: 'Capture generation is stale.',
      );

  static Future<void> _loadFamily(
    String localFamily,
    List<ByteData> bytes,
  ) async {
    final loader = FontLoader(localFamily);
    for (final data in bytes) {
      loader.addFont(Future<ByteData>.value(data));
    }
    await loader.load();
  }

  static bool _sameEvidence(
    ReaderSourceFontMetricEvidence first,
    ReaderSourceFontMetricEvidence second,
  ) =>
      listEquals(first.canonicalBytes, second.canonicalBytes) &&
      first.digest == second.digest;

  static String _cacheKey(
    String deliveryDigest,
    ReaderSourceFontProbePlan plan,
  ) {
    final writer = ReaderFontCanonicalWriter('reader-source-cache-key', 1);
    writer.stringField(1, deliveryDigest);
    writer.stringField(2, plan.stableSourceIdentity);
    writer.intField(3, plan.sourceStartUtf16);
    writer.intField(4, plan.sourceEndUtf16);
    writer.stringField(5, readerFontSourceRepertoireDigest(plan.sourceText));
    writer.stringListField(
      6,
      plan.requests.map((request) => request.canonicalKey).toList()..sort(),
    );
    return ReaderFontCanonicalEncoder.digest(writer.takeBytes());
  }
}

abstract final class ReaderBundledFontCatalogParser {
  static ReaderBundledFontCatalog parse(Object? value) {
    final root = _map(value, 'manifest');
    if (root['schema'] != readerFontCatalogRevision) {
      throw FormatException('Unexpected reader font schema ${root['schema']}.');
    }
    final assets = <ReaderFontAssetRecord>[];
    final mappings = <ReaderFontVariantMapping>[];
    final localFamilies = <ReaderFontFamily, String>{};
    for (final item in _list(root['families'], 'families')) {
      final family = _map(item, 'family');
      final familyName = _string(family['family'], 'family');
      final localFamily = _string(family['localFamily'], 'localFamily');
      final licensePath = _string(family['licensePath'], 'licensePath');
      final enumFamily = _readerFamily(familyName);
      if (localFamilies.putIfAbsent(enumFamily, () => localFamily) !=
          localFamily) {
        throw FormatException('Duplicate family $familyName.');
      }
      for (final assetItem in _list(family['assets'], '$familyName.assets')) {
        final asset = _map(assetItem, 'asset');
        assets.add(
          ReaderFontAssetRecord(
            family: familyName,
            localFamily: localFamily,
            weight: _integer(asset['weight'], 'weight'),
            style: _style(asset['style']),
            assetPath: _string(asset['path'], 'path'),
            sourceUrl: _string(asset['url'], 'url'),
            byteLength: _integer(asset['byteLength'], 'byteLength'),
            sha256: _string(asset['sha256'], 'sha256'),
            licensePath: licensePath,
          ),
        );
      }
      for (final mappingItem in _list(
        family['mappings'],
        '$familyName.mappings',
      )) {
        final mapping = _map(mappingItem, 'mapping');
        mappings.add(
          ReaderFontVariantMapping(
            family: familyName,
            requestedWeight: _integer(
              mapping['requestedWeight'],
              'requestedWeight',
            ),
            requestedStyle: _style(mapping['requestedStyle']),
            deliveredWeight: _integer(
              mapping['deliveredWeight'],
              'deliveredWeight',
            ),
            deliveredStyle: _style(mapping['deliveredStyle']),
            assetSha256: _string(mapping['assetSha256'], 'assetSha256'),
          ),
        );
      }
    }
    return ReaderBundledFontCatalog(
      revision: _string(root['schema'], 'schema'),
      descriptorSource: _string(root['descriptorSource'], 'descriptorSource'),
      license: _string(root['license'], 'license'),
      assets: assets,
      mappings: mappings,
      localFamilies: localFamilies,
    );
  }

  static void validate(ReaderBundledFontCatalog catalog) {
    if (catalog.localFamilies.length !=
            ReaderBundledFontCatalog.selectableFamilyCount ||
        catalog.localFamilies.keys.toSet().length !=
            ReaderFontFamily.values.length) {
      throw StateError(
        'The catalog must contain exactly eight reader families.',
      );
    }
    if (catalog.mappings.length !=
        ReaderBundledFontCatalog.effectiveVariantMappingCount) {
      throw StateError(
        'Expected ${ReaderBundledFontCatalog.effectiveVariantMappingCount} effective variants, '
        'found ${catalog.mappings.length}.',
      );
    }
    final assetPaths = <String>{};
    final assetDigests = <String>{};
    for (final asset in catalog.assets) {
      if (!assetPaths.add(asset.assetPath) ||
          !assetDigests.add(asset.sha256) ||
          !asset.assetPath.startsWith('assets/fonts/reader/') ||
          asset.assetPath.contains('/reader_contract/') ||
          !asset.sourceUrl.startsWith('https://fonts.gstatic.com/s/a/') ||
          !asset.licensePath.startsWith('assets/fonts/reader/licenses/')) {
        throw StateError(
          'Invalid/duplicate production asset ${asset.assetPath}.',
        );
      }
    }
    final mappingKeys = <String>{};
    for (final mapping in catalog.mappings) {
      if (!mappingKeys.add(mapping.key)) {
        throw StateError('Duplicate mapping ${mapping.key}.');
      }
      final asset = catalog.assetForSha256(mapping.assetSha256);
      if (asset == null ||
          asset.family != mapping.family ||
          asset.weight != mapping.deliveredWeight ||
          asset.style != mapping.deliveredStyle) {
        throw StateError('Mapping does not resolve to its delivered asset.');
      }
    }
    for (final family in catalog.localFamilies.keys) {
      final familyName = readerFontProviderFamilyName(family);
      for (final weight in <int>[300, 400, 500, 600, 700, 800, 900]) {
        if (catalog.mappingFor(
              family: familyName,
              weight: weight,
              style: FontStyle.normal,
            ) ==
            null) {
          throw StateError('Missing $familyName $weight normal.');
        }
      }
      for (final weight in <int>[300, 400, 500, 600, 700]) {
        if (catalog.mappingFor(
              family: familyName,
              weight: weight,
              style: FontStyle.italic,
            ) ==
            null) {
          throw StateError('Missing $familyName $weight italic.');
        }
      }
    }
  }

  static Map<String, Object?> _map(Object? value, String name) =>
      (value as Map<Object?, Object?>).map(
        (key, value) => MapEntry(key as String, value),
      );
  static List<Object?> _list(Object? value, String name) =>
      List<Object?>.from(value as List<Object?>);
  static String _string(Object? value, String name) => value as String;
  static int _integer(Object? value, String name) => value as int;
  static FontStyle _style(Object? value) => switch (value) {
    'normal' => FontStyle.normal,
    'italic' => FontStyle.italic,
    _ => throw FormatException('Unknown font style $value.'),
  };
  static ReaderFontFamily _readerFamily(String family) => ReaderFontFamily
      .values
      .singleWhere((value) => readerFontProviderFamilyName(value) == family);
}

ReaderSourceFontProbePlan buildProbePlan({
  required ReaderBundledFontCatalog catalog,
  required ReadingSettings settings,
  required String stableSourceIdentity,
  required int sourceStartUtf16,
  required String sourceText,
  String? locale,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final family = readerFontProviderFamilyName(settings.fontFamily);
  final bodyWeight = settings.fontWeightValue.value;
  final bodySize = settings.fontSizeValue;
  final tableSize = (bodySize * 0.85).clamp(13.0, 18.0);
  final preSize = (bodySize * 0.80).clamp(12.0, 16.0);
  final specs =
      <(ReaderFontRole, String, int, FontStyle, double, double, double)>[
        (
          ReaderFontRole.body,
          family,
          bodyWeight,
          FontStyle.normal,
          settings.semanticFontSize,
          bodySize,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.heading,
          family,
          900,
          FontStyle.normal,
          settings.semanticFontSize + 14,
          bodySize + (14 * settings.fontSizeMultiplier),
          ReadingSettings.headingLineHeight,
        ),
        (
          ReaderFontRole.inlineBold,
          family,
          700,
          FontStyle.normal,
          settings.semanticFontSize,
          bodySize,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.inlineItalic,
          family,
          bodyWeight,
          FontStyle.italic,
          settings.semanticFontSize,
          bodySize,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.inlineBoldItalic,
          family,
          700,
          FontStyle.italic,
          settings.semanticFontSize,
          bodySize,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.footnote,
          family,
          600,
          FontStyle.normal,
          settings.semanticFontSize * 0.75,
          bodySize * 0.75,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.listMarker,
          family,
          600,
          FontStyle.normal,
          settings.semanticFontSize,
          bodySize,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.tableBody,
          family,
          500,
          FontStyle.normal,
          tableSize,
          tableSize,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.tableHeader,
          family,
          800,
          FontStyle.normal,
          tableSize,
          tableSize,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.preformatted,
          'Roboto Mono',
          bodyWeight,
          FontStyle.normal,
          preSize,
          preSize,
          settings.effectiveLineHeight,
        ),
        (
          ReaderFontRole.headingDivider,
          family,
          400,
          FontStyle.normal,
          14,
          14,
          1.0,
        ),
      ];
  final requests = <ReaderFontRequestIdentity>[];
  for (final spec in specs) {
    final mapping = catalog.mappingFor(
      family: spec.$2,
      weight: spec.$3,
      style: spec.$4,
    );
    if (mapping == null) {
      throw StateError(
        'No bundled mapping for ${spec.$2} ${spec.$3} ${spec.$4.name}.',
      );
    }
    final selectedFamily = _readerFamilyByProviderName(spec.$2);
    requests.add(
      ReaderFontRequestIdentity(
        role: spec.$1,
        family: spec.$2,
        localFamily: catalog.localFamilyFor(selectedFamily),
        requestedWeight: spec.$3,
        requestedStyle: spec.$4,
        deliveredWeight: mapping.deliveredWeight,
        deliveredStyle: mapping.deliveredStyle,
        assetSha256: mapping.assetSha256,
        logicalSize: spec.$6,
        scaledSize: textScaler.scale(spec.$6),
        height: spec.$7,
        letterSpacing: spec.$1 == ReaderFontRole.heading ? 2 : 0,
        locale: locale,
      ),
    );
  }
  final uniqueVariants = requests
      .map(
        (request) =>
            '${request.family}|${request.deliveredWeight}|${request.deliveredStyle.name}',
      )
      .toSet();
  final sizes = requests.map((request) => request.scaledSize).toSet();
  if (uniqueVariants.length >
          ReaderBundledFontCatalog.maximumUniqueVariantsPerCapture ||
      sizes.length > ReaderBundledFontCatalog.maximumScaledSizesPerCapture) {
    throw StateError('Reachable request bounds were exceeded.');
  }
  return ReaderSourceFontProbePlan(
    stableSourceIdentity: stableSourceIdentity,
    sourceStartUtf16: sourceStartUtf16,
    sourceEndUtf16: sourceStartUtf16 + sourceText.length,
    sourceText: sourceText,
    requests: requests,
  );
}

ReaderSourceFontMetricEvidence _measureSource(
  ReaderFontDeliveryEvidence delivery,
  ReaderSourceFontProbePlan plan,
) {
  final repertoireDigest = readerFontSourceRepertoireDigest(plan.sourceText);
  final observations = <ReaderFontMetricObservation>[];
  if (plan.sourceText.isNotEmpty) {
    for (final request in plan.requests) {
      observations.add(
        _measure(request, plan.sourceText, repertoireDigest, null),
      );
      for (final width in plan.probeWidths) {
        observations.add(
          _measure(request, plan.sourceText, repertoireDigest, width),
        );
      }
    }
  }
  if (observations.length >
      ReaderSourceFontProbePlan.maximumProbeRunsPerStableSourceUnit) {
    throw StateError('Probe run bound exceeded.');
  }
  final canonical = ReaderFontCanonicalEncoder.encodeSource(
    deliveryEvidenceDigest: delivery.digest,
    plan: plan,
    repertoireDigest: repertoireDigest,
    observations: observations,
  );
  return ReaderSourceFontMetricEvidence(
    probeRevision: readerFontProbeRevision,
    deliveryEvidenceDigest: delivery.digest,
    stableSourceIdentity: plan.stableSourceIdentity,
    sourceStartUtf16: plan.sourceStartUtf16,
    sourceEndUtf16: plan.sourceEndUtf16,
    sourceRepertoireDigest: repertoireDigest,
    observations: observations,
    canonicalBytes: canonical,
    digest: ReaderFontCanonicalEncoder.digest(canonical),
  );
}

ReaderFontMetricObservation _measure(
  ReaderFontRequestIdentity request,
  String text,
  String repertoireDigest,
  double? maxWidth,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: request.toTextStyle()),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    textHeightBehavior: readerTextHeightBehavior,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  final details = ReaderFontCanonicalWriter(
    'reader-font-observation-detail',
    1,
  );
  details.stringField(1, repertoireDigest);
  details.recordListField(2, painter.computeLineMetrics(), (writer, line) {
    writer.boolField(1, line.hardBreak);
    writer.intField(2, line.lineNumber);
    writer.doubleField(3, line.left);
    writer.doubleField(4, line.baseline);
    writer.doubleField(5, line.ascent);
    writer.doubleField(6, line.descent);
    writer.doubleField(7, line.unscaledAscent);
    writer.doubleField(8, line.height);
    writer.doubleField(9, line.width);
  });
  final boundaries = <TextRange>[];
  TextRange? prior;
  for (var offset = 0; offset <= text.length; offset++) {
    final boundary = painter.getLineBoundary(TextPosition(offset: offset));
    if (prior?.start != boundary.start || prior?.end != boundary.end) {
      boundaries.add(boundary);
      prior = boundary;
    }
  }
  details.recordListField(3, boundaries, (writer, boundary) {
    writer.intField(1, boundary.start);
    writer.intField(2, boundary.end);
  });
  final boxes = text.isEmpty
      ? const <TextBox>[]
      : painter.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
          boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
        );
  details.recordListField(4, boxes, (writer, box) {
    writer.doubleField(1, box.left);
    writer.doubleField(2, box.top);
    writer.doubleField(3, box.right);
    writer.doubleField(4, box.bottom);
    writer.enumField(5, box.direction.name);
  });
  final carets = <_CaretEvidence>[];
  final glyphs = <String, ui.GlyphInfo>{};
  for (var offset = 0; offset <= text.length; offset++) {
    final position = TextPosition(offset: offset);
    final caret = painter.getOffsetForCaret(position, Rect.zero);
    final height = painter.getFullHeightForCaret(position, Rect.zero);
    final resolved = painter.getPositionForOffset(caret);
    carets.add(
      _CaretEvidence(offset, caret, height, resolved.offset, resolved.affinity),
    );
    final glyph = painter.getClosestGlyphForOffset(
      Offset(caret.dx, caret.dy + (height / 2)),
    );
    if (glyph != null) {
      final range = glyph.graphemeClusterCodeUnitRange;
      glyphs['${range.start}:${range.end}'] = glyph;
    }
  }
  details.recordListField(5, carets, (writer, caret) {
    writer.intField(1, caret.requestedOffset);
    writer.doubleField(2, caret.offset.dx);
    writer.doubleField(3, caret.offset.dy);
    writer.doubleField(4, caret.height);
    writer.intField(5, caret.resolvedOffset);
    writer.enumField(6, caret.affinity.name);
  });
  final glyphList = glyphs.values.toList()
    ..sort(
      (a, b) => a.graphemeClusterCodeUnitRange.start.compareTo(
        b.graphemeClusterCodeUnitRange.start,
      ),
    );
  details.recordListField(6, glyphList, (writer, glyph) {
    final range = glyph.graphemeClusterCodeUnitRange;
    final bounds = glyph.graphemeClusterLayoutBounds;
    writer.intField(1, range.start);
    writer.intField(2, range.end);
    writer.doubleField(3, bounds.left);
    writer.doubleField(4, bounds.top);
    writer.doubleField(5, bounds.right);
    writer.doubleField(6, bounds.bottom);
    writer.enumField(7, glyph.writingDirection.name);
  });
  final detailDigest = ReaderFontCanonicalEncoder.digest(details.takeBytes());
  return ReaderFontMetricObservation(
    request: request,
    probeWidth: maxWidth,
    width: painter.width,
    height: painter.height,
    minIntrinsicWidth: painter.minIntrinsicWidth,
    maxIntrinsicWidth: painter.maxIntrinsicWidth,
    alphabeticBaseline: painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    ),
    ideographicBaseline: painter.computeDistanceToActualBaseline(
      TextBaseline.ideographic,
    ),
    lineCount: painter.computeLineMetrics().length,
    didExceedMaxLines: painter.didExceedMaxLines,
    fallbackEvidenceKind:
        ReaderFontFallbackEvidenceKind.opaqueFallbackMetricProbe,
    fallbackFaceIdentity: null,
    completeObservationDigest: detailDigest,
  );
}

String readerFontProviderFamilyName(ReaderFontFamily family) =>
    switch (family) {
      ReaderFontFamily.inter => 'Inter',
      ReaderFontFamily.robotoMono => 'Roboto Mono',
      ReaderFontFamily.merriweather => 'Merriweather',
      ReaderFontFamily.lora => 'Lora',
      ReaderFontFamily.ebGaramond => 'EB Garamond',
      ReaderFontFamily.literata => 'Literata',
      ReaderFontFamily.atkinsonHyperlegible => 'Atkinson Hyperlegible',
      ReaderFontFamily.lexend => 'Lexend',
    };

ReaderFontFamily _readerFamilyByProviderName(String family) => ReaderFontFamily
    .values
    .singleWhere((value) => readerFontProviderFamilyName(value) == family);

@immutable
final class _CaretEvidence {
  const _CaretEvidence(
    this.requestedOffset,
    this.offset,
    this.height,
    this.resolvedOffset,
    this.affinity,
  );
  final int requestedOffset;
  final Offset offset;
  final double height;
  final int resolvedOffset;
  final TextAffinity affinity;
}

sealed class _PreparationResult {}

final class _PreparationSuccess extends _PreparationResult {
  _PreparationSuccess(this.prepared);
  final _PreparedDelivery prepared;
}

final class _PreparationFailure extends _PreparationResult {
  _PreparationFailure(this.outcome);
  final ReaderFontEvidenceRejected outcome;
}

final class _PreparedDelivery {
  const _PreparedDelivery(this.catalog, this.evidence);
  final ReaderBundledFontCatalog catalog;
  final ReaderFontDeliveryEvidence evidence;
}

final class _PreparationException implements Exception {
  const _PreparationException(this.outcome);
  final ReaderFontEvidenceRejected outcome;
}
