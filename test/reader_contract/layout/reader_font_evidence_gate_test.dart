import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool originalRuntimeFetching;
  late ReaderBundledFontCatalog catalog;
  late ReaderFontEvidenceGate gate;
  late ReaderFontReadyTerminalBundled baseline;

  setUpAll(() async {
    originalRuntimeFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    catalog = await _loadCatalog();
    gate = ReaderFontEvidenceGate();
    final outcome = await gate.capture(
      settings: const ReadingSettings(),
      stableSourceIdentity: 'fixture/source/alpha',
      sourceStartUtf16: 0,
      sourceText: 'Office affinity — عربي — हिन्दी — 😀',
    );
    expect(
      outcome,
      isA<ReaderFontReadyTerminalBundled>(),
      reason: outcome.reason,
    );
    baseline = outcome as ReaderFontReadyTerminalBundled;
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  tearDown(() {
    GoogleFonts.config.allowRuntimeFetching = originalRuntimeFetching;
  });

  group('U-05/U-06 bundled transition and complete variant delivery', () {
    test('1. all eight selectable families are present', () {
      expect(
        catalog.localFamilies.keys.toSet(),
        ReaderFontFamily.values.toSet(),
      );
      expect(catalog.localFamilies, readerBundledFontFamilies);
    });

    test('2. every reachable reader role resolves to bundled delivery', () {
      for (final family in ReaderFontFamily.values) {
        for (final weight in ReaderFontWeight.values) {
          final plan = buildProbePlan(
            catalog: catalog,
            settings: ReadingSettings(fontFamily: family, fontWeight: weight),
            stableSourceIdentity: 'catalog/${family.name}/${weight.name}',
            sourceStartUtf16: 0,
            sourceText: 'probe',
          );
          expect(
            plan.requests.map((request) => request.role).toSet(),
            ReaderFontRole.values.toSet(),
          );
          expect(
            plan.requests,
            hasLength(ReaderSourceFontProbePlan.maximumRequestsPerCapture),
          );
          for (final request in plan.requests) {
            expect(catalog.assetForSha256(request.assetSha256), isNotNull);
          }
        }
      }
    });

    test(
      '3–5. manifest paths, hashes, byte lengths and licences are valid',
      () async {
        expect(
          catalog.assets,
          hasLength(ReaderFontEvidenceGate.expectedAssetCount),
        );
        var total = 0;
        for (final asset in catalog.assets) {
          final data = await rootBundle.load(asset.assetPath);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          expect(bytes, hasLength(asset.byteLength), reason: asset.assetPath);
          expect(
            sha256.convert(bytes).toString(),
            asset.sha256,
            reason: asset.assetPath,
          );
          final licence = await rootBundle.loadString(asset.licensePath);
          expect(licence, contains('SIL OPEN FONT LICENSE'));
          total += bytes.length;
        }
        expect(total, ReaderFontEvidenceGate.expectedTotalAssetBytes);
        final provenance = await rootBundle.loadString(
          'assets/fonts/reader/PROVENANCE.md',
        );
        expect(provenance, contains('google_fonts'));
        expect(provenance, contains('8.0.2'));
      },
    );

    test(
      '6–7. preformatted and divider roles have explicit bundled owners',
      () {
        final plan = buildProbePlan(
          catalog: catalog,
          settings: const ReadingSettings(fontFamily: ReaderFontFamily.lora),
          stableSourceIdentity: 'roles',
          sourceStartUtf16: 0,
          sourceText: 'roles',
        );
        final pre = plan.requests.singleWhere(
          (request) => request.role == ReaderFontRole.preformatted,
        );
        final divider = plan.requests.singleWhere(
          (request) => request.role == ReaderFontRole.headingDivider,
        );
        expect(pre.family, 'Roboto Mono');
        expect(pre.localFamily, 'NaloriReaderRobotoMono');
        expect(pre.localFamily, isNot('monospace'));
        expect(divider.family, 'Lora');
        expect(divider.localFamily, 'NaloriReaderLora');
      },
    );

    test('8. reader requests cannot initiate HTTP', () async {
      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
      for (final family in ReaderFontFamily.values) {
        final style = ReadingSettings(fontFamily: family).getTextStyle();
        expect(style.fontFamily, readerBundledFontFamilies[family]);
        expect(style.fontFamily, startsWith('NaloriReader'));
      }
      await GoogleFonts.pendingFonts();
    });

    test('9. effective mappings preserve google_fonts 8.0.2 choices', () {
      _expectMapping(
        catalog,
        'Roboto Mono',
        900,
        FontStyle.normal,
        700,
        FontStyle.normal,
      );
      _expectMapping(
        catalog,
        'Lora',
        300,
        FontStyle.italic,
        400,
        FontStyle.italic,
      );
      _expectMapping(
        catalog,
        'EB Garamond',
        900,
        FontStyle.normal,
        800,
        FontStyle.normal,
      );
      _expectMapping(
        catalog,
        'Atkinson Hyperlegible',
        600,
        FontStyle.italic,
        700,
        FontStyle.italic,
      );
      _expectMapping(
        catalog,
        'Lexend',
        700,
        FontStyle.italic,
        700,
        FontStyle.normal,
      );
    });

    test('10. missing one required variant rejects', () {
      final incomplete = ReaderBundledFontCatalog(
        revision: catalog.revision,
        descriptorSource: catalog.descriptorSource,
        license: catalog.license,
        assets: catalog.assets,
        mappings: catalog.mappings.sublist(1),
        localFamilies: catalog.localFamilies,
      );
      expect(
        () => ReaderBundledFontCatalogParser.validate(incomplete),
        throwsStateError,
      );
    });

    test('11. altered asset bytes reject', () async {
      final alteredPath = catalog.assets.first.assetPath;
      final alteredGate = ReaderFontEvidenceGate(
        bundleReader: (path) async {
          final data = await rootBundle.load(path);
          if (path != alteredPath) return data;
          final bytes = Uint8List.fromList(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          bytes[0] ^= 0xff;
          return ByteData.sublistView(bytes);
        },
        familyLoader: (_, __) async {},
      );
      final result = await alteredGate.capture(
        settings: const ReadingSettings(),
        stableSourceIdentity: 'altered',
        sourceStartUtf16: 0,
        sourceText: 'altered',
      );
      expect(result.type, ReaderFontGateOutcomeType.rejectedDigestMismatch);
      expect(result.canAuthorizeLayout, isFalse);
    });

    test('U-05 missing bundled asset rejects without authority', () async {
      final missing = ReaderFontEvidenceGate(
        bundleReader: (_) async => throw FlutterError('missing asset'),
        familyLoader: (_, __) async {},
      );
      final result = await missing.capture(
        settings: const ReadingSettings(),
        stableSourceIdentity: 'missing',
        sourceStartUtf16: 0,
        sourceText: 'missing',
      );
      expect(result.type, ReaderFontGateOutcomeType.rejectedMissingAsset);
      expect(result.canAuthorizeLayout, isFalse);
    });

    test(
      'U-06 incomplete source probe coverage rejects without authority',
      () async {
        final tooLarge = List.filled(
          ReaderSourceFontProbePlan.maximumSourceSliceUtf16 + 1,
          'x',
        ).join();
        final result = await gate.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'incomplete',
          sourceStartUtf16: 0,
          sourceText: tooLarge,
        );
        expect(
          result.type,
          ReaderFontGateOutcomeType.rejectedIncompleteVariantCoverage,
        );
        expect(result.canAuthorizeLayout, isFalse);
      },
    );
  });

  group('U-05/U-06 source metrics, fallback, rejection and freshness', () {
    test(
      '12–14. terminal evidence is deterministic and window/order independent',
      () async {
        final second = await gate.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'fixture/source/alpha',
          sourceStartUtf16: 0,
          sourceText: 'Office affinity — عربي — हिन्दी — 😀',
        );
        expect(second, isA<ReaderFontReadyTerminalBundled>());
        final ready = second as ReaderFontReadyTerminalBundled;
        expect(
          ready.deliveryEvidence.canonicalBytes,
          baseline.deliveryEvidence.canonicalBytes,
        );
        expect(ready.deliveryEvidence.digest, baseline.deliveryEvidence.digest);
        expect(
          ready.sourceEvidence.canonicalBytes,
          baseline.sourceEvidence.canonicalBytes,
        );
        expect(ready.sourceEvidence.digest, baseline.sourceEvidence.digest);
        final reversedPlan = ReaderSourceFontProbePlan(
          stableSourceIdentity: baseline.sourceEvidence.stableSourceIdentity,
          sourceStartUtf16: baseline.sourceEvidence.sourceStartUtf16,
          sourceEndUtf16: baseline.sourceEvidence.sourceEndUtf16,
          sourceText: 'Office affinity — عربي — हिन्दी — 😀',
          requests: baseline.sourceEvidence.observations
              .map((observation) => observation.request)
              .toSet()
              .toList()
              .reversed
              .toList(),
        );
        final reordered = ReaderFontCanonicalEncoder.encodeSource(
          deliveryEvidenceDigest: baseline.deliveryEvidence.digest,
          plan: reversedPlan,
          repertoireDigest: baseline.sourceEvidence.sourceRepertoireDigest,
          observations: baseline.sourceEvidence.observations.reversed.toList(),
        );
        expect(reordered, baseline.sourceEvidence.canonicalBytes);
      },
    );

    test(
      '15–16. source units do not inherit evidence and each new unit gates',
      () async {
        final fresh = ReaderFontEvidenceGate(familyLoader: (_, __) async {});
        expect(
          fresh.currentOutcome.type,
          ReaderFontGateOutcomeType.pendingAssetReadiness,
        );
        final result = await fresh.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'fixture/source/beta',
          sourceStartUtf16: 0,
          sourceText: 'A separate stable source.',
        );
        expect(result, isA<ReaderFontReadyTerminalBundled>());
        final evidence =
            (result as ReaderFontReadyTerminalBundled).sourceEvidence;
        expect(evidence.stableSourceIdentity, 'fixture/source/beta');
        expect(evidence.digest, isNot(baseline.sourceEvidence.digest));
        expect(fresh.retainedSourceEvidenceCount, 1);
      },
    );

    test('17. metric, wrap and shaping changes alter the digest', () {
      final plan = buildProbePlan(
        catalog: catalog,
        settings: const ReadingSettings(),
        stableSourceIdentity: baseline.sourceEvidence.stableSourceIdentity,
        sourceStartUtf16: baseline.sourceEvidence.sourceStartUtf16,
        sourceText: 'Office affinity — عربي — हिन्दी — 😀',
      );
      final observations = baseline.sourceEvidence.observations;
      final widthChanged = [...observations]
        ..[0] = _copyObservation(
          observations[0],
          width: observations[0].width + 0.25,
        );
      final shapeChanged = [...observations]
        ..[0] = _copyObservation(
          observations[0],
          completeObservationDigest: List.filled(64, '0').join(),
        );
      final first = ReaderFontCanonicalEncoder.encodeSource(
        deliveryEvidenceDigest: baseline.deliveryEvidence.digest,
        plan: plan,
        repertoireDigest: baseline.sourceEvidence.sourceRepertoireDigest,
        observations: widthChanged,
      );
      final second = ReaderFontCanonicalEncoder.encodeSource(
        deliveryEvidenceDigest: baseline.deliveryEvidence.digest,
        plan: plan,
        repertoireDigest: baseline.sourceEvidence.sourceRepertoireDigest,
        observations: shapeChanged,
      );
      expect(
        ReaderFontCanonicalEncoder.digest(first),
        isNot(baseline.sourceEvidence.digest),
      );
      expect(
        ReaderFontCanonicalEncoder.digest(second),
        isNot(baseline.sourceEvidence.digest),
      );
      expect(
        ReaderFontCanonicalEncoder.digest(first),
        isNot(ReaderFontCanonicalEncoder.digest(second)),
      );
    });

    test(
      '18. unsupported glyph probes remain opaque and invent no face',
      () async {
        final result = await gate.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'fixture/source/fallback',
          sourceStartUtf16: 0,
          sourceText: '\u{10ffff} unsupported probe',
        );
        final evidence =
            (result as ReaderFontReadyTerminalBundled).sourceEvidence;
        expect(evidence.observations, isNotEmpty);
        for (final observation in evidence.observations) {
          expect(
            observation.fallbackEvidenceKind,
            ReaderFontFallbackEvidenceKind.opaqueFallbackMetricProbe,
          );
          expect(observation.fallbackFaceIdentity, isNull);
        }
      },
    );

    test('19. unstable fallback observations reject', () async {
      final unstable = ReaderFontEvidenceGate(
        familyLoader: (_, __) async {},
        stabilityComparator: (_, __) => false,
      );
      final result = await unstable.capture(
        settings: const ReadingSettings(),
        stableSourceIdentity: 'fixture/source/unstable',
        sourceStartUtf16: 0,
        sourceText: '\u{10ffff}',
      );
      expect(
        result.type,
        ReaderFontGateOutcomeType.rejectedContradictoryEvidence,
      );
      expect(result.canAuthorizeLayout, isFalse);
    });

    test('20. serialized evidence contains no source text', () {
      final needle = utf8.encode('Office affinity — عربي — हिन्दी — 😀');
      expect(
        _containsBytes(baseline.sourceEvidence.canonicalBytes, needle),
        isFalse,
      );
    });

    test(
      '21. exact fragments enforce incremental source and evidence bounds',
      () async {
        final large = List.filled(
          ReaderSourceFontProbePlan.maximumSourceSliceUtf16,
          'a',
        ).join();
        final result = await gate.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'fixture/source/large#0',
          sourceStartUtf16: 0,
          sourceText: large,
        );
        final evidence =
            (result as ReaderFontReadyTerminalBundled).sourceEvidence;
        expect(
          evidence.canonicalBytes.length,
          lessThanOrEqualTo(
            ReaderSourceFontProbePlan.maximumEvidenceBytesPerSourceUnit,
          ),
        );
        expect(
          evidence.observations.length,
          ReaderSourceFontProbePlan.maximumProbeRunsPerStableSourceUnit,
        );
        expect(
          () => buildProbePlan(
            catalog: catalog,
            settings: const ReadingSettings(),
            stableSourceIdentity: 'too-large',
            sourceStartUtf16: 0,
            sourceText: '$large!',
          ),
          throwsArgumentError,
        );
        expect(
          gate.retainedSourceEvidenceCount,
          lessThanOrEqualTo(
            ReaderSourceFontProbePlan.maximumRetainedSourceEvidenceRecords,
          ),
        );
        expect(
          gate.retainedSourceEvidenceBytes,
          lessThanOrEqualTo(
            ReaderSourceFontProbePlan.maximumRetainedEvidenceBytes,
          ),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('22. cancellation and staleness never return ready', () async {
      final cancelled = await gate.capture(
        settings: const ReadingSettings(),
        stableSourceIdentity: 'cancelled',
        sourceStartUtf16: 0,
        sourceText: 'cancelled',
        isCancelled: () => true,
      );
      final stale = await gate.capture(
        settings: const ReadingSettings(),
        stableSourceIdentity: 'stale',
        sourceStartUtf16: 0,
        sourceText: 'stale',
        isStale: () => true,
      );
      expect(cancelled.type, ReaderFontGateOutcomeType.rejectedCancelled);
      expect(stale.type, ReaderFontGateOutcomeType.rejectedStaleCapture);
      expect(cancelled.canAuthorizeLayout, isFalse);
      expect(stale.canAuthorizeLayout, isFalse);
    });

    test('23. mutable Google Fonts state is restored by test cleanup', () {
      expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    });

    test('24. reader-contract Lexend files remain test-only evidence', () {
      for (final asset in catalog.assets) {
        expect(asset.assetPath, isNot(contains('/reader_contract/')));
      }
      expect(
        catalog.assets
            .where((asset) => asset.family == 'Lexend')
            .map((asset) => asset.assetPath),
        everyElement(startsWith('assets/fonts/reader/Lexend-')),
      );
    });

    test(
      '25. exact empty repertoire is terminal, explicit, and performs no metric runs',
      () async {
        final first = await gate.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'snapshot-a/source-0|0:0',
          sourceStartUtf16: 0,
          sourceText: '',
        );
        final repeat = await gate.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'snapshot-a/source-0|0:0',
          sourceStartUtf16: 0,
          sourceText: '',
        );
        expect(first, isA<ReaderFontReadyTerminalBundled>());
        expect(repeat, isA<ReaderFontReadyTerminalBundled>());
        final ready = first as ReaderFontReadyTerminalBundled;
        final repeated = repeat as ReaderFontReadyTerminalBundled;
        expect(ready.sourceEvidence.isExplicitlyEmptyRepertoire, isTrue);
        expect(ready.sourceEvidence.observations, isEmpty);
        expect(ready.sourceEvidence.sourceStartUtf16, 0);
        expect(ready.sourceEvidence.sourceEndUtf16, 0);
        expect(repeated.sourceEvidence.digest, ready.sourceEvidence.digest);
        expect(
          ready.requests.map((request) => request.role).toSet(),
          ReaderFontRole.values.toSet(),
        );
        expect(ready.requests, hasLength(11));
        expect(
          ready.requests
              .map(
                (request) =>
                    '${request.family}|${request.deliveredWeight}|${request.deliveredStyle.name}',
              )
              .toSet(),
          hasLength(lessThanOrEqualTo(10)),
        );
      },
    );

    test(
      '26. empty-to-glyph transition re-gates and keeps rejection states distinct',
      () async {
        final empty = await gate.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'snapshot-transition/source-0|0:0',
          sourceStartUtf16: 0,
          sourceText: '',
        );
        final glyph = await gate.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'snapshot-transition/source-0|0:1',
          sourceStartUtf16: 0,
          sourceText: 'A',
        );
        final emptyReady = empty as ReaderFontReadyTerminalBundled;
        final glyphReady = glyph as ReaderFontReadyTerminalBundled;
        expect(glyphReady.sourceEvidence.observations, hasLength(33));
        expect(
          glyphReady.sourceEvidence.digest,
          isNot(emptyReady.sourceEvidence.digest),
        );

        final absent = ReaderFontEvidenceGate(familyLoader: (_, __) async {});
        expect(
          absent.currentOutcome.type,
          ReaderFontGateOutcomeType.pendingAssetReadiness,
        );
        final cancelled = await absent.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'cancelled-empty|0:0',
          sourceStartUtf16: 0,
          sourceText: '',
          isCancelled: () => true,
        );
        final stale = await absent.capture(
          settings: const ReadingSettings(),
          stableSourceIdentity: 'stale-empty|0:0',
          sourceStartUtf16: 0,
          sourceText: '',
          isStale: () => true,
        );
        final contradictory =
            await ReaderFontEvidenceGate(
              familyLoader: (_, __) async {},
              stabilityComparator: (_, __) => false,
            ).capture(
              settings: const ReadingSettings(),
              stableSourceIdentity: 'contradictory-empty|0:0',
              sourceStartUtf16: 0,
              sourceText: '',
            );
        expect(cancelled.type, ReaderFontGateOutcomeType.rejectedCancelled);
        expect(stale.type, ReaderFontGateOutcomeType.rejectedStaleCapture);
        expect(
          contradictory.type,
          ReaderFontGateOutcomeType.rejectedContradictoryEvidence,
        );
        expect(cancelled.canAuthorizeLayout, isFalse);
        expect(stale.canAuthorizeLayout, isFalse);
        expect(contradictory.canAuthorizeLayout, isFalse);
      },
    );
  });
}

Future<ReaderBundledFontCatalog> _loadCatalog() async {
  final data = await rootBundle.load(ReaderFontEvidenceGate.manifestAssetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final catalog = ReaderBundledFontCatalogParser.parse(
    jsonDecode(utf8.decode(bytes)),
  );
  ReaderBundledFontCatalogParser.validate(catalog);
  return catalog;
}

void _expectMapping(
  ReaderBundledFontCatalog catalog,
  String family,
  int requestedWeight,
  FontStyle requestedStyle,
  int deliveredWeight,
  FontStyle deliveredStyle,
) {
  final mapping = catalog.mappingFor(
    family: family,
    weight: requestedWeight,
    style: requestedStyle,
  );
  expect(mapping, isNotNull);
  expect(mapping!.deliveredWeight, deliveredWeight);
  expect(mapping.deliveredStyle, deliveredStyle);
}

ReaderFontMetricObservation _copyObservation(
  ReaderFontMetricObservation source, {
  double? width,
  String? completeObservationDigest,
}) => ReaderFontMetricObservation(
  request: source.request,
  probeWidth: source.probeWidth,
  width: width ?? source.width,
  height: source.height,
  minIntrinsicWidth: source.minIntrinsicWidth,
  maxIntrinsicWidth: source.maxIntrinsicWidth,
  alphabeticBaseline: source.alphabeticBaseline,
  ideographicBaseline: source.ideographicBaseline,
  lineCount: source.lineCount,
  didExceedMaxLines: source.didExceedMaxLines,
  fallbackEvidenceKind: source.fallbackEvidenceKind,
  fallbackFaceIdentity: source.fallbackFaceIdentity,
  completeObservationDigest:
      completeObservationDigest ?? source.completeObservationDigest,
);

bool _containsBytes(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var index = 0; index <= haystack.length - needle.length; index++) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (haystack[index + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
