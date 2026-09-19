import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'reading_settings.dart';

const String readerFontCatalogRevision = 'nalori.reader_font_assets.v1';
const String readerFontProbeRevision = 'nalori.reader_font_probe.v1';

enum ReaderFontRole {
  body,
  heading,
  inlineBold,
  inlineItalic,
  inlineBoldItalic,
  footnote,
  listMarker,
  tableBody,
  tableHeader,
  preformatted,
  headingDivider,
}

enum ReaderFontFallbackEvidenceKind {
  bundledAssetMetrics,
  opaqueFallbackMetricProbe,
}

enum ReaderFontGateOutcomeType {
  readyTerminalBundled,
  pendingAssetReadiness,
  rejectedMissingAsset,
  rejectedDigestMismatch,
  rejectedIncompleteVariantCoverage,
  rejectedUnavailableMetricEvidence,
  rejectedContradictoryEvidence,
  rejectedStaleCapture,
  rejectedCancelled,
}

@immutable
final class ReaderFontAssetRecord {
  const ReaderFontAssetRecord({
    required this.family,
    required this.localFamily,
    required this.weight,
    required this.style,
    required this.assetPath,
    required this.sourceUrl,
    required this.byteLength,
    required this.sha256,
    required this.licensePath,
  });

  final String family;
  final String localFamily;
  final int weight;
  final FontStyle style;
  final String assetPath;
  final String sourceUrl;
  final int byteLength;
  final String sha256;
  final String licensePath;
}

@immutable
final class ReaderFontVariantMapping {
  const ReaderFontVariantMapping({
    required this.family,
    required this.requestedWeight,
    required this.requestedStyle,
    required this.deliveredWeight,
    required this.deliveredStyle,
    required this.assetSha256,
  });

  final String family;
  final int requestedWeight;
  final FontStyle requestedStyle;
  final int deliveredWeight;
  final FontStyle deliveredStyle;
  final String assetSha256;

  String get key =>
      '$family|$requestedWeight|${requestedStyle == FontStyle.italic ? 'italic' : 'normal'}';
}

@immutable
final class ReaderFontRequestIdentity {
  ReaderFontRequestIdentity({
    required this.role,
    required this.family,
    required this.localFamily,
    required this.requestedWeight,
    required this.requestedStyle,
    required this.deliveredWeight,
    required this.deliveredStyle,
    required this.assetSha256,
    required this.logicalSize,
    required this.scaledSize,
    required this.height,
    required this.letterSpacing,
    this.package,
    this.locale,
    List<FontFeature> fontFeatures = const <FontFeature>[],
  }) : fontFeatures = List<FontFeature>.unmodifiable(fontFeatures) {
    _requireFinite(logicalSize, 'logicalSize');
    _requireFinite(scaledSize, 'scaledSize');
    _requireFinite(height, 'height');
    _requireFinite(letterSpacing, 'letterSpacing');
  }

  final ReaderFontRole role;
  final String family;
  final String localFamily;
  final int requestedWeight;
  final FontStyle requestedStyle;
  final int deliveredWeight;
  final FontStyle deliveredStyle;
  final String assetSha256;
  final double logicalSize;
  final double scaledSize;
  final double height;
  final double letterSpacing;
  final String? package;
  final String? locale;
  final List<FontFeature> fontFeatures;

  String get canonicalKey => <Object?>[
    role.name,
    family,
    localFamily,
    requestedWeight,
    requestedStyle.name,
    deliveredWeight,
    deliveredStyle.name,
    assetSha256,
    logicalSize,
    scaledSize,
    height,
    letterSpacing,
    package,
    locale,
    ...fontFeatures.map((feature) => feature.toString()),
  ].join('|');

  TextStyle toTextStyle() => TextStyle(
    fontFamily: localFamily,
    package: package,
    fontSize: scaledSize,
    fontWeight: FontWeight.values[(requestedWeight ~/ 100) - 1],
    fontStyle: requestedStyle,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
    locale: locale == null ? null : _readerLocaleFromTag(locale!),
  );
}

@immutable
final class ReaderBundledFontCatalog {
  ReaderBundledFontCatalog({
    required this.revision,
    required this.descriptorSource,
    required this.license,
    required List<ReaderFontAssetRecord> assets,
    required List<ReaderFontVariantMapping> mappings,
    required Map<ReaderFontFamily, String> localFamilies,
  }) : assets = List<ReaderFontAssetRecord>.unmodifiable(assets),
       mappings = List<ReaderFontVariantMapping>.unmodifiable(mappings),
       localFamilies = Map<ReaderFontFamily, String>.unmodifiable(
         localFamilies,
       );

  final String revision;
  final String descriptorSource;
  final String license;
  final List<ReaderFontAssetRecord> assets;
  final List<ReaderFontVariantMapping> mappings;
  final Map<ReaderFontFamily, String> localFamilies;

  static const int selectableFamilyCount = 8;
  static const int legacyReachableNominalRequestCount = 102;
  static const int effectiveVariantMappingCount = 96;
  static const int maximumUniqueVariantsPerCapture = 10;
  static const int maximumScaledSizesPerCapture = 6;

  ReaderFontVariantMapping? mappingFor({
    required String family,
    required int weight,
    required FontStyle style,
  }) {
    final key =
        '$family|$weight|${style == FontStyle.italic ? 'italic' : 'normal'}';
    for (final mapping in mappings) {
      if (mapping.key == key) return mapping;
    }
    return null;
  }

  ReaderFontAssetRecord? assetForSha256(String value) {
    for (final asset in assets) {
      if (asset.sha256 == value) return asset;
    }
    return null;
  }

  String localFamilyFor(ReaderFontFamily family) => localFamilies[family]!;
}

@immutable
final class ReaderFontDeliveryEvidence {
  const ReaderFontDeliveryEvidence({
    required this.catalogRevision,
    required this.descriptorSource,
    required this.assetCount,
    required this.totalAssetBytes,
    required this.canonicalBytes,
    required this.digest,
  });

  final String catalogRevision;
  final String descriptorSource;
  final int assetCount;
  final int totalAssetBytes;
  final Uint8List canonicalBytes;
  final String digest;
}

@immutable
final class ReaderSourceFontProbePlan {
  ReaderSourceFontProbePlan({
    required this.stableSourceIdentity,
    required this.sourceStartUtf16,
    required this.sourceEndUtf16,
    required this.sourceText,
    required List<ReaderFontRequestIdentity> requests,
    List<double> probeWidths = approvedProbeWidths,
  }) : requests = List<ReaderFontRequestIdentity>.unmodifiable(requests),
       probeWidths = List<double>.unmodifiable(probeWidths) {
    if (stableSourceIdentity.isEmpty) {
      throw ArgumentError.value(stableSourceIdentity, 'stableSourceIdentity');
    }
    if (sourceStartUtf16 < 0 ||
        sourceEndUtf16 < sourceStartUtf16 ||
        sourceEndUtf16 - sourceStartUtf16 != sourceText.length) {
      throw ArgumentError('Source slice identity/range is inconsistent.');
    }
    if (sourceText.length > maximumSourceSliceUtf16) {
      throw ArgumentError(
        'Source slice exceeds $maximumSourceSliceUtf16 UTF-16 code units; '
        'partition it into exact stable slices.',
      );
    }
    if (requests.isEmpty || requests.length > maximumRequestsPerCapture) {
      throw ArgumentError('Invalid request count ${requests.length}.');
    }
    if (probeWidths.isEmpty ||
        probeWidths.length > maximumProbeWidths ||
        probeWidths.any((width) => !width.isFinite || width <= 0)) {
      throw ArgumentError('Invalid probe widths.');
    }
  }

  static const int maximumSourceSliceUtf16 = 2048;
  static const int maximumRequestsPerCapture = 11;
  static const int maximumProbeWidths = 2;
  static const int maximumProbeRunsPerStableSourceUnit =
      maximumRequestsPerCapture * (maximumProbeWidths + 1);

  /// Next binary allocation boundary above the 24,722-byte worst reachable
  /// 11-role/3-width canonical record measured by the P05 gate tests.
  static const int maximumEvidenceBytesPerSourceUnit = 32768;
  static const int maximumRetainedSourceEvidenceRecords = 25;
  static const int maximumRetainedEvidenceBytes =
      maximumEvidenceBytesPerSourceUnit * maximumRetainedSourceEvidenceRecords;
  static const List<double> approvedProbeWidths = <double>[156.0, 342.0];

  final String stableSourceIdentity;
  final int sourceStartUtf16;
  final int sourceEndUtf16;

  /// Ephemeral input only. It is never copied into canonical evidence.
  final String sourceText;
  final List<ReaderFontRequestIdentity> requests;
  final List<double> probeWidths;
}

@immutable
final class ReaderFontMetricObservation {
  ReaderFontMetricObservation({
    required this.request,
    required this.probeWidth,
    required this.width,
    required this.height,
    required this.minIntrinsicWidth,
    required this.maxIntrinsicWidth,
    required this.alphabeticBaseline,
    required this.ideographicBaseline,
    required this.lineCount,
    required this.didExceedMaxLines,
    required this.fallbackEvidenceKind,
    required this.fallbackFaceIdentity,
    required this.completeObservationDigest,
  }) {
    for (final value in <double?>[
      probeWidth,
      width,
      height,
      minIntrinsicWidth,
      maxIntrinsicWidth,
      alphabeticBaseline,
      ideographicBaseline,
    ]) {
      if (value != null) _requireFinite(value, 'metric');
    }
    if (fallbackEvidenceKind ==
            ReaderFontFallbackEvidenceKind.opaqueFallbackMetricProbe &&
        fallbackFaceIdentity != null) {
      throw ArgumentError('Opaque fallback evidence cannot name a face.');
    }
  }

  final ReaderFontRequestIdentity request;
  final double? probeWidth;
  final double width;
  final double height;
  final double minIntrinsicWidth;
  final double maxIntrinsicWidth;
  final double? alphabeticBaseline;
  final double? ideographicBaseline;
  final int lineCount;
  final bool didExceedMaxLines;
  final ReaderFontFallbackEvidenceKind fallbackEvidenceKind;
  final String? fallbackFaceIdentity;

  /// SHA-256 of complete line metrics, UTF-16 line boundaries, carets,
  /// selection boxes and available GlyphInfo ranges/boxes/directions.
  final String completeObservationDigest;
}

@immutable
final class ReaderSourceFontMetricEvidence {
  ReaderSourceFontMetricEvidence({
    required this.probeRevision,
    required this.deliveryEvidenceDigest,
    required this.stableSourceIdentity,
    required this.sourceStartUtf16,
    required this.sourceEndUtf16,
    required this.sourceRepertoireDigest,
    required List<ReaderFontMetricObservation> observations,
    required this.canonicalBytes,
    required this.digest,
  }) : observations = List<ReaderFontMetricObservation>.unmodifiable(
         observations,
       );

  final String probeRevision;
  final String deliveryEvidenceDigest;
  final String stableSourceIdentity;
  final int sourceStartUtf16;
  final int sourceEndUtf16;
  final String sourceRepertoireDigest;
  final List<ReaderFontMetricObservation> observations;
  final Uint8List canonicalBytes;
  final String digest;

  bool get isExplicitlyEmptyRepertoire =>
      sourceStartUtf16 == sourceEndUtf16 &&
      sourceRepertoireDigest == readerFontSourceRepertoireDigest('') &&
      observations.isEmpty;
}

sealed class ReaderFontEvidenceOutcome {
  const ReaderFontEvidenceOutcome(this.type, {this.reason});

  final ReaderFontGateOutcomeType type;
  final String? reason;
  bool get canAuthorizeLayout => false;
}

final class ReaderFontReadyTerminalBundled extends ReaderFontEvidenceOutcome {
  ReaderFontReadyTerminalBundled({
    required this.deliveryEvidence,
    required this.sourceEvidence,
    required List<ReaderFontRequestIdentity> requests,
  }) : requests = List<ReaderFontRequestIdentity>.unmodifiable(requests),
       super(ReaderFontGateOutcomeType.readyTerminalBundled);

  final ReaderFontDeliveryEvidence deliveryEvidence;
  final ReaderSourceFontMetricEvidence sourceEvidence;

  /// Complete delivery-backed session typography. An empty source repertoire
  /// can carry this catalog without claiming any source metric observation.
  final List<ReaderFontRequestIdentity> requests;

  @override
  bool get canAuthorizeLayout => true;
}

final class ReaderFontPendingAssetReadiness extends ReaderFontEvidenceOutcome {
  const ReaderFontPendingAssetReadiness({super.reason})
    : super(ReaderFontGateOutcomeType.pendingAssetReadiness);
}

final class ReaderFontEvidenceRejected extends ReaderFontEvidenceOutcome {
  const ReaderFontEvidenceRejected(super.type, {super.reason})
    : assert(
        type != ReaderFontGateOutcomeType.readyTerminalBundled &&
            type != ReaderFontGateOutcomeType.pendingAssetReadiness,
      );
}

abstract final class ReaderFontCanonicalEncoder {
  static Uint8List encodeDelivery({required ReaderBundledFontCatalog catalog}) {
    final writer = ReaderFontCanonicalWriter('reader-font-delivery', 1);
    writer.stringField(1, catalog.revision);
    writer.stringField(2, catalog.descriptorSource);
    writer.stringField(3, catalog.license);
    final assets = catalog.assets.toList()
      ..sort((a, b) => a.assetPath.compareTo(b.assetPath));
    writer.recordListField(4, assets, (nested, asset) {
      nested.stringField(1, asset.family);
      nested.stringField(2, asset.localFamily);
      nested.intField(3, asset.weight);
      nested.enumField(4, asset.style.name);
      nested.stringField(5, asset.assetPath);
      nested.stringField(6, asset.sourceUrl);
      nested.intField(7, asset.byteLength);
      nested.stringField(8, asset.sha256);
      nested.stringField(9, asset.licensePath);
    });
    final mappings = catalog.mappings.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    writer.recordListField(5, mappings, (nested, mapping) {
      nested.stringField(1, mapping.family);
      nested.intField(2, mapping.requestedWeight);
      nested.enumField(3, mapping.requestedStyle.name);
      nested.intField(4, mapping.deliveredWeight);
      nested.enumField(5, mapping.deliveredStyle.name);
      nested.stringField(6, mapping.assetSha256);
    });
    return writer.takeBytes();
  }

  static Uint8List encodeSource({
    required String deliveryEvidenceDigest,
    required ReaderSourceFontProbePlan plan,
    required String repertoireDigest,
    required List<ReaderFontMetricObservation> observations,
  }) {
    final writer = ReaderFontCanonicalWriter('reader-source-font-metrics', 1);
    writer.stringField(1, readerFontProbeRevision);
    writer.stringField(2, deliveryEvidenceDigest);
    writer.stringField(3, plan.stableSourceIdentity);
    writer.intField(4, plan.sourceStartUtf16);
    writer.intField(5, plan.sourceEndUtf16);
    writer.stringField(6, repertoireDigest);
    final ordered = observations.toList()
      ..sort((a, b) {
        final request = a.request.canonicalKey.compareTo(
          b.request.canonicalKey,
        );
        if (request != 0) return request;
        return _nullableDoubleOrder(a.probeWidth, b.probeWidth);
      });
    writer.recordListField(7, ordered, (nested, observation) {
      _writeRequest(nested, observation.request);
      nested.optionalDoubleField(20, observation.probeWidth);
      nested.doubleField(22, observation.width);
      nested.doubleField(23, observation.height);
      nested.doubleField(24, observation.minIntrinsicWidth);
      nested.doubleField(25, observation.maxIntrinsicWidth);
      nested.optionalDoubleField(26, observation.alphabeticBaseline);
      nested.optionalDoubleField(28, observation.ideographicBaseline);
      nested.intField(30, observation.lineCount);
      nested.boolField(31, observation.didExceedMaxLines);
      nested.enumField(32, observation.fallbackEvidenceKind.name);
      nested.optionalStringField(33, observation.fallbackFaceIdentity);
      nested.stringField(35, observation.completeObservationDigest);
    });
    return writer.takeBytes();
  }

  static void _writeRequest(
    ReaderFontCanonicalWriter writer,
    ReaderFontRequestIdentity request,
  ) {
    writer.enumField(1, request.role.name);
    writer.stringField(2, request.family);
    writer.stringField(3, request.localFamily);
    writer.intField(4, request.requestedWeight);
    writer.enumField(5, request.requestedStyle.name);
    writer.intField(6, request.deliveredWeight);
    writer.enumField(7, request.deliveredStyle.name);
    writer.stringField(8, request.assetSha256);
    writer.doubleField(9, request.logicalSize);
    writer.doubleField(10, request.scaledSize);
    writer.doubleField(11, request.height);
    writer.doubleField(12, request.letterSpacing);
    writer.optionalStringField(13, request.package);
    writer.optionalStringField(15, request.locale);
    writer.stringListField(
      17,
      request.fontFeatures.map((feature) => feature.toString()).toList()
        ..sort(),
    );
  }

  static String digest(Uint8List bytes) => sha256.convert(bytes).toString();
}

final class ReaderFontCanonicalWriter {
  ReaderFontCanonicalWriter(String kind, int revision) {
    final kindBytes = Uint8List.fromList(utf8.encode(kind));
    _bytes
      ..add(_uint64(kindBytes.length))
      ..add(kindBytes)
      ..add(_uint64(revision));
  }

  final BytesBuilder _bytes = BytesBuilder(copy: false);
  int _lastTag = 0;

  void stringField(int tag, String value) =>
      _field(tag, 1, Uint8List.fromList(utf8.encode(value)));

  void optionalStringField(int tag, String? value) {
    _presence(tag, value != null);
    if (value != null) stringField(tag + 1, value);
  }

  void enumField(int tag, String value) => stringField(tag, value);

  void intField(int tag, int value) {
    final data = ByteData(8)..setInt64(0, value);
    _field(tag, 2, data.buffer.asUint8List());
  }

  void boolField(int tag, bool value) =>
      _field(tag, 3, Uint8List.fromList(<int>[value ? 1 : 0]));

  void doubleField(int tag, double value) {
    _requireFinite(value, 'field $tag');
    final normalized = value == 0 ? 0.0 : value;
    final data = ByteData(8)..setFloat64(0, normalized);
    _field(tag, 4, data.buffer.asUint8List());
  }

  void optionalDoubleField(int tag, double? value) {
    _presence(tag, value != null);
    if (value != null) doubleField(tag + 1, value);
  }

  void stringListField(int tag, List<String> values) {
    final nested = BytesBuilder(copy: false);
    nested.add(_uint64(values.length));
    for (final value in values) {
      final bytes = Uint8List.fromList(utf8.encode(value));
      nested.add(_uint64(bytes.length));
      nested.add(bytes);
    }
    _field(tag, 5, nested.takeBytes());
  }

  void recordListField<T>(
    int tag,
    List<T> values,
    void Function(ReaderFontCanonicalWriter writer, T value) encode,
  ) {
    final nested = BytesBuilder(copy: false)..add(_uint64(values.length));
    for (final value in values) {
      final writer = ReaderFontCanonicalWriter('entry', 1);
      encode(writer, value);
      final bytes = writer.takeBytes();
      nested
        ..add(_uint64(bytes.length))
        ..add(bytes);
    }
    _field(tag, 6, nested.takeBytes());
  }

  Uint8List takeBytes() => _bytes.takeBytes();

  void _presence(int tag, bool present) =>
      _field(tag, 7, Uint8List.fromList(<int>[present ? 1 : 0]));

  void _field(int tag, int type, Uint8List payload) {
    if (tag <= _lastTag) {
      throw StateError('Canonical field tags must increase: $tag.');
    }
    _lastTag = tag;
    final header = ByteData(13)
      ..setUint32(0, tag)
      ..setUint8(4, type)
      ..setUint64(5, payload.length);
    _bytes
      ..add(header.buffer.asUint8List())
      ..add(payload);
  }

  static Uint8List _uint64(int value) {
    final data = ByteData(8)..setUint64(0, value);
    return data.buffer.asUint8List();
  }
}

int _nullableDoubleOrder(double? left, double? right) {
  if (left == null) return right == null ? 0 : -1;
  if (right == null) return 1;
  return left.compareTo(right);
}

String readerFontSourceRepertoireDigest(String text) {
  final digests = <Digest>[];
  final sink = ChunkedConversionSink<Digest>.withCallback(digests.addAll);
  final input = sha256.startChunkedConversion(sink);
  final buffer = ByteData(512);
  var used = 0;
  for (final codeUnit in text.codeUnits) {
    if (used == buffer.lengthInBytes) {
      input.add(buffer.buffer.asUint8List());
      used = 0;
    }
    buffer.setUint16(used, codeUnit);
    used += 2;
  }
  if (used > 0) input.add(buffer.buffer.asUint8List().sublist(0, used));
  input.close();
  return digests.single.toString();
}

void _requireFinite(double value, String name) {
  if (!value.isFinite) throw ArgumentError.value(value, name, 'must be finite');
}

Locale _readerLocaleFromTag(String tag) {
  final parts = tag.replaceAll('_', '-').split('-');
  return Locale.fromSubtags(
    languageCode: parts.first,
    scriptCode: parts.length > 1 && parts[1].length == 4 ? parts[1] : null,
    countryCode: parts.length > 1 && parts[1].length != 4
        ? parts[1]
        : parts.length > 2
        ? parts[2]
        : null,
  );
}
