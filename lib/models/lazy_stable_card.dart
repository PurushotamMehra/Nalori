import '../services/lazy_validation_work.dart';
import 'dart:convert';

import 'canonical_pagination.dart';
import 'reader_checkpoint.dart';

/// A tagged source interval in the lazy domain. Serialization contains a local
/// position and address; the checked resident hint is supplied only to project.
final class LazyStableSourceSlice {
  LazyStableSourceSlice._(this._encoding);
  final String _encoding;
  Map<String, Object?> toJson() =>
      Map<String, Object?>.from(jsonDecode(_encoding) as Map);
  int get localSourcePosition => toJson()['localSourcePosition']! as int;
  String get address => toJson()['address']! as String;

  factory LazyStableSourceSlice.fromJson(Map<String, Object?> json) {
    const strings = {
      'sourceIdentity',
      'sectionIdentity',
      'spineIdentity',
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
      'address',
    };
    const booleans = {
      'isLogicalParagraphStart',
      'isLogicalParagraphEnd',
      'usesExplicitTextFragment',
    };
    const offsets = {
      'startUtf16',
      'endUtf16',
      'tableRowStart',
      'tableRowEndExclusive',
    };
    final keys = {...strings, ...booleans, ...offsets, 'localSourcePosition'};
    if (json.length != keys.length ||
        json.keys.any((key) => !keys.contains(key)) ||
        strings.any(
          (key) => json[key] is! String || (json[key]! as String).isEmpty,
        ) ||
        booleans.any((key) => json[key] is! bool) ||
        offsets.any((key) => json[key] != null && json[key] is! int) ||
        (json['startUtf16'] == null) != (json['endUtf16'] == null) ||
        (json['tableRowStart'] == null) !=
            (json['tableRowEndExclusive'] == null) ||
        json['localSourcePosition'] is! int ||
        (json['localSourcePosition']! as int) < 0) {
      throw const FormatException('Invalid lazy source slice');
    }
    return LazyStableSourceSlice._(canonicalJsonEncode(json));
  }

  CanonicalPaginationSourceSlice project(int checkedResidentHint) {
    final j = toJson();
    return CanonicalPaginationSourceSlice(
      sourceIdentity: j['sourceIdentity']! as String,
      sectionIdentity: j['sectionIdentity']! as String,
      spineIdentity: j['spineIdentity']! as String,
      sourceOrdinalHint: checkedResidentHint,
      sourceDigest: j['sourceDigest']! as String,
      structuralType: j['structuralType']! as String,
      structuralOwnerRole: j['structuralOwnerRole']! as String,
      logicalOwnerIdentity: j['logicalOwnerIdentity']! as String,
      structuralDigest: j['structuralDigest']! as String,
      fragmentDigest: j['fragmentDigest']! as String,
      publisherLayoutDigest: j['publisherLayoutDigest']! as String,
      richMetadataDigest: j['richMetadataDigest']! as String,
      listFragmentDigest: j['listFragmentDigest']! as String,
      splitBoundaryKind: j['splitBoundaryKind']! as String,
      isLogicalParagraphStart: j['isLogicalParagraphStart']! as bool,
      isLogicalParagraphEnd: j['isLogicalParagraphEnd']! as bool,
      usesExplicitTextFragment: j['usesExplicitTextFragment']! as bool,
      startUtf16: j['startUtf16'] as int?,
      endUtf16: j['endUtf16'] as int?,
      tableRowStart: j['tableRowStart'] as int?,
      tableRowEndExclusive: j['tableRowEndExclusive'] as int?,
    );
  }
}

/// Durable lazy emission domain. This is never a BookChunk JSON record and
/// must never be decoded by giving an old payload.i a new meaning.
final class LazyStableCardBody {
  LazyStableCardBody._(
    this.canonicalEncoding,
    this.signature,
    this.identity,
    List<LazyStableSourceSlice> slices,
  ) : sourceSlices = List.unmodifiable(slices);

  static const domain = 'nalori.lazy.stable-card';
  static const version = 1;
  static const maxEncodedBytes = 4 * 1024 * 1024;

  final String canonicalEncoding;
  final String signature;
  int get retainedMetadataBytes =>
      512 + sourceSlices.fold<int>(0, (n, s) => n + 2 * s._encoding.length);

  Map<String, Object?> toJson() =>
      Map<String, Object?>.from(jsonDecode(canonicalEncoding) as Map);

  final ReaderCardIdentity identity;
  final List<LazyStableSourceSlice> sourceSlices;

  /// Checks envelope integrity/shape only. Source/layout admission additionally
  /// requires exact regeneration through LazyStableCardEmitter.admit.
  factory LazyStableCardBody.fromJson(Map<String, Object?> json) {
    final encoded = canonicalJsonEncode(json);
    if (utf8.encode(encoded).length > maxEncodedBytes ||
        json['domain'] != domain ||
        json['version'] != version ||
        json.keys.toSet().difference(const {
          'domain',
          'version',
          'publication',
          'section',
          'membership',
          'payload',
          'slices',
          'layout',
          'identity',
          'digest',
        }).isNotEmpty ||
        json.length != 10) {
      throw const FormatException('Unsupported lazy stable body');
    }
    final unsigned = Map<String, Object?>.of(json)..remove('digest');
    if (readerSha256(unsigned) != json['digest']) {
      throw const FormatException('Invalid lazy body digest');
    }
    final payload = json['payload'];
    final slices = json['slices'];
    final membership = json['membership'];
    if (payload is! Map ||
        payload.containsKey('i') ||
        slices is! List ||
        slices.isEmpty ||
        slices.length > CanonicalPaginationBounds.activeSourceCeiling ||
        membership is! Map ||
        membership['count'] is! int ||
        membership['owners'] is! List ||
        (membership['owners'] as List).length != membership['count'] ||
        (membership['count'] as int) >
            CanonicalPaginationBounds.activeSourceCeiling ||
        json['publication'] is! String ||
        json['section'] is! Map ||
        json['layout'] is! Map ||
        json['identity'] is! Map) {
      throw const FormatException('Incomplete lazy stable body');
    }
    final stableSlices = <LazyStableSourceSlice>[];
    for (final slice in slices) {
      if (slice is! Map ||
          slice.containsKey('sourceOrdinalHint') ||
          slice['localSourcePosition'] is! int ||
          (slice['localSourcePosition'] as int) < 0 ||
          (slice['localSourcePosition'] as int) >=
              (membership['count'] as int)) {
        throw const FormatException('Invalid stable source slice');
      }
      final stable = LazyStableSourceSlice.fromJson(
        Map<String, Object?>.from(slice),
      );
      if (slice['sourceDigest'] !=
              (membership['owners'] as List)[stable.localSourcePosition] ||
          stable.address !=
              readerSha256([
                'LazySourceAddressV1',
                json['publication'],
                readerSha256(json['section']!),
                stable.localSourcePosition,
              ])) {
        throw const FormatException('Invalid lazy slice membership');
      }
      stableSlices.add(stable);
    }
    final ranges = payload['sr'];
    if (ranges != null &&
        (ranges is! List ||
            ranges.any(
              (range) =>
                  range is! Map ||
                  range.containsKey('ci') ||
                  range['localSourcePosition'] is! int,
            ))) {
      throw const FormatException('Runtime range in stable payload');
    }
    final identity = ReaderCardIdentity.fromJson(
      Map<String, Object?>.from(json['identity']! as Map),
    );
    final rebuilt = CanonicalReaderCardIdentityBuilder.build(
      publicationFingerprint: identity.publicationFingerprint,
      controlledLayoutIdentity: identity.layoutFingerprint,
      paginationAlgorithmIdentity: identity.paginationVersion,
      orderedSourceSlices: [
        for (final slice in stableSlices)
          slice.project(slice.localSourcePosition),
      ],
    );
    if (canonicalJsonEncode(rebuilt.toJson()) !=
            canonicalJsonEncode(identity.toJson()) ||
        identity.layoutFingerprint != (json['layout'] as Map)['packing']) {
      throw const FormatException(
        'Stable identity does not bind ordered slices',
      );
    }
    return LazyStableCardBody._(
      encoded,
      json['digest']! as String,
      identity,
      stableSlices,
    );
  }

  static Future<LazyStableCardBody> fromJsonYielding(
    Map<String, Object?> json,
    LazyValidationWork work,
  ) async {
    final encoded = (await work.encode(json));
    work.hold(2 * encoded.length);
    try {
      if (await work.utf8Length(encoded) > maxEncodedBytes ||
          json['domain'] != domain ||
          json['version'] != version ||
          json.keys.toSet().difference(const {
            'domain',
            'version',
            'publication',
            'section',
            'membership',
            'payload',
            'slices',
            'layout',
            'identity',
            'digest',
          }).isNotEmpty ||
          json.length != 10) {
        throw const FormatException('Unsupported lazy stable body');
      }
      final unsigned = Map<String, Object?>.of(json)..remove('digest');
      if ((await work.digest(unsigned)) != json['digest']) {
        throw const FormatException('Invalid lazy body digest');
      }
      final payload = json['payload'];
      final slices = json['slices'];
      final membership = json['membership'];
      if (payload is! Map ||
          payload.containsKey('i') ||
          slices is! List ||
          slices.isEmpty ||
          slices.length > CanonicalPaginationBounds.activeSourceCeiling ||
          membership is! Map ||
          membership['count'] is! int ||
          membership['owners'] is! List ||
          (membership['owners'] as List).length != membership['count'] ||
          (membership['count'] as int) >
              CanonicalPaginationBounds.activeSourceCeiling ||
          json['publication'] is! String ||
          json['section'] is! Map ||
          json['layout'] is! Map ||
          json['identity'] is! Map) {
        throw const FormatException('Incomplete lazy stable body');
      }
      final stableSlices = <LazyStableSourceSlice>[];
      for (final slice in slices) {
        await work.step('stable-envelope');
        if (slice is! Map ||
            slice.containsKey('sourceOrdinalHint') ||
            slice['localSourcePosition'] is! int ||
            (slice['localSourcePosition'] as int) < 0 ||
            (slice['localSourcePosition'] as int) >=
                (membership['count'] as int)) {
          throw const FormatException('Invalid stable source slice');
        }
        final stable = LazyStableSourceSlice.fromJson(
          Map<String, Object?>.from(slice),
        );
        if (slice['sourceDigest'] !=
                (membership['owners'] as List)[stable.localSourcePosition] ||
            stable.address !=
                (await work.digest([
                  'LazySourceAddressV1',
                  json['publication'],
                  (await work.digest(json['section']!)),
                  stable.localSourcePosition,
                ]))) {
          throw const FormatException('Invalid lazy slice membership');
        }
        stableSlices.add(stable);
      }
      final ranges = payload['sr'];
      if (ranges != null &&
          (ranges is! List ||
              ranges.any(
                (range) =>
                    range is! Map ||
                    range.containsKey('ci') ||
                    range['localSourcePosition'] is! int,
              ))) {
        throw const FormatException('Runtime range in stable payload');
      }
      final identity = ReaderCardIdentity.fromJson(
        Map<String, Object?>.from(json['identity']! as Map),
      );
      final rebuilt = CanonicalReaderCardIdentityBuilder.build(
        publicationFingerprint: identity.publicationFingerprint,
        controlledLayoutIdentity: identity.layoutFingerprint,
        paginationAlgorithmIdentity: identity.paginationVersion,
        orderedSourceSlices: [
          for (final slice in stableSlices)
            slice.project(slice.localSourcePosition),
        ],
      );
      if (!await work.equalCanonical(rebuilt.toJson(), identity.toJson()) ||
          identity.layoutFingerprint != (json['layout'] as Map)['packing']) {
        throw const FormatException(
          'Stable identity does not bind ordered slices',
        );
      }
      return LazyStableCardBody._(
        encoded,
        json['digest']! as String,
        identity,
        stableSlices,
      );
    } finally {
      work.releaseHeld(2 * encoded.length);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LazyStableCardBody &&
      canonicalEncoding == other.canonicalEncoding;

  @override
  int get hashCode => canonicalEncoding.hashCode;
}
