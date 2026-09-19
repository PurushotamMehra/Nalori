import 'dart:convert';
import 'dart:typed_data';

import '../models/reader_compatibility.dart';
import '../models/reader_font_evidence.dart';

/// Pure P05 identity boundary. It validates revisioned canonical evidence
/// before it compares it and deliberately grants no persistence or publication
/// authority.
abstract final class ReaderCompatibilityClassifier {
  static ReaderCompatibilityClassificationResult classify({
    required ReaderCompatibilityEvidence previous,
    required ReaderCompatibilityEvidence current,
    required ReaderCompatibilityRevisionSupport supportedRevisions,
    bool requestedPhysicalCardSignaturePresent = true,
  }) {
    final previousFingerprints =
        ReaderCompatibilityDiagnosticFingerprints.fromEvidence(previous);
    final currentFingerprints =
        ReaderCompatibilityDiagnosticFingerprints.fromEvidence(current);
    if (!previous.isComplete || !current.isComplete) {
      return _result(
        ReaderCompatibilityClassificationKind.incompleteEvidence,
        const <ReaderCompatibilityIdentityDimension>[],
        previousFingerprints,
        currentFingerprints,
        requestedPhysicalCardSignaturePresent,
      );
    }

    final previousValidation = _validate(previous, supportedRevisions);
    final currentValidation = _validate(current, supportedRevisions);
    if (previousValidation.state == _EvidenceState.corrupt ||
        currentValidation.state == _EvidenceState.corrupt) {
      return _result(
        ReaderCompatibilityClassificationKind.corruptEvidence,
        const <ReaderCompatibilityIdentityDimension>[],
        previousFingerprints,
        currentFingerprints,
        requestedPhysicalCardSignaturePresent,
      );
    }
    if (previousValidation.state == _EvidenceState.unsupported ||
        currentValidation.state == _EvidenceState.unsupported ||
        previousValidation.classifierRevision !=
            currentValidation.classifierRevision) {
      return _result(
        ReaderCompatibilityClassificationKind.unsupportedRevision,
        const <ReaderCompatibilityIdentityDimension>[],
        previousFingerprints,
        currentFingerprints,
        requestedPhysicalCardSignaturePresent,
      );
    }

    final changed = <ReaderCompatibilityIdentityDimension>[
      if (previous.layoutMetricsIdentity!.fingerprint !=
          current.layoutMetricsIdentity!.fingerprint)
        ReaderCompatibilityIdentityDimension.layoutMetrics,
      if (previous.sourceCompatibilityIdentity!.fingerprint !=
          current.sourceCompatibilityIdentity!.fingerprint)
        ReaderCompatibilityIdentityDimension.sourceCompatibility,
      if (previous.paginationAlgorithmIdentity!.fingerprint !=
          current.paginationAlgorithmIdentity!.fingerprint)
        ReaderCompatibilityIdentityDimension.paginationAlgorithm,
      if (previous.rendererLayoutIdentity!.fingerprint !=
          current.rendererLayoutIdentity!.fingerprint)
        ReaderCompatibilityIdentityDimension.rendererLayout,
    ];
    final kind = switch (changed.length) {
      0 => ReaderCompatibilityClassificationKind.exactCompatible,
      1 => switch (changed.single) {
        ReaderCompatibilityIdentityDimension.layoutMetrics =>
          ReaderCompatibilityClassificationKind.layoutMetricsChanged,
        ReaderCompatibilityIdentityDimension.sourceCompatibility =>
          ReaderCompatibilityClassificationKind.sourceCompatibilityChanged,
        ReaderCompatibilityIdentityDimension.paginationAlgorithm =>
          ReaderCompatibilityClassificationKind.paginationAlgorithmChanged,
        ReaderCompatibilityIdentityDimension.rendererLayout =>
          ReaderCompatibilityClassificationKind.rendererLayoutChanged,
      },
      _ => ReaderCompatibilityClassificationKind.multipleAuthoritativeChanges,
    };
    return _result(
      kind,
      changed,
      previousFingerprints,
      currentFingerprints,
      requestedPhysicalCardSignaturePresent,
    );
  }

  static ReaderCompatibilityClassificationResult _result(
    ReaderCompatibilityClassificationKind kind,
    List<ReaderCompatibilityIdentityDimension> changed,
    ReaderCompatibilityDiagnosticFingerprints previous,
    ReaderCompatibilityDiagnosticFingerprints current,
    bool requestedPhysicalCardSignaturePresent,
  ) => ReaderCompatibilityClassificationResult(
    kind: kind,
    reason: ReaderCompatibilityMigrationReason(
      kind: kind,
      changedDimensions: changed,
    ),
    changedDimensions: changed,
    previousFingerprints: previous,
    currentFingerprints: current,
    requestedPhysicalCardSignaturePresent:
        requestedPhysicalCardSignaturePresent,
  );

  static _EvidenceValidation _validate(
    ReaderCompatibilityEvidence evidence,
    ReaderCompatibilityRevisionSupport support,
  ) {
    try {
      final layout = evidence.layoutMetricsIdentity!;
      final source = evidence.sourceCompatibilityIdentity!;
      final pagination = evidence.paginationAlgorithmIdentity!;
      final renderer = evidence.rendererLayoutIdentity!;
      final composite = evidence.readerCompatibilityIdentity!;
      if (!_validFingerprint(layout.fingerprint) ||
          !_validFingerprint(source.fingerprint) ||
          !_validFingerprint(pagination.fingerprint) ||
          !_validFingerprint(renderer.fingerprint) ||
          !_validFingerprint(composite.fingerprint) ||
          ReaderFontCanonicalEncoder.digest(layout.canonicalBytes) !=
              layout.fingerprint ||
          ReaderFontCanonicalEncoder.digest(source.canonicalBytes) !=
              source.fingerprint ||
          ReaderFontCanonicalEncoder.digest(pagination.canonicalBytes) !=
              pagination.fingerprint ||
          ReaderFontCanonicalEncoder.digest(renderer.canonicalBytes) !=
              renderer.fingerprint ||
          ReaderFontCanonicalEncoder.digest(composite.canonicalBytes) !=
              composite.fingerprint) {
        return const _EvidenceValidation.corrupt();
      }

      final layoutRecord = _CanonicalRecord.parse(layout.canonicalBytes);
      final sourceRecord = _CanonicalRecord.parse(source.canonicalBytes);
      final paginationRecord = _CanonicalRecord.parse(
        pagination.canonicalBytes,
      );
      final rendererRecord = _CanonicalRecord.parse(renderer.canonicalBytes);
      final compositeRecord = _CanonicalRecord.parse(composite.canonicalBytes);
      _expectRecord(
        layoutRecord,
        kind: 'reader-layout-metrics',
        types: _layoutMetricTypes,
      );
      _expectRecord(
        sourceRecord,
        kind: 'reader-source-compatibility',
        types: const <int, int>{1: _CanonicalFieldType.stringList},
      );
      _expectRecord(
        paginationRecord,
        kind: 'reader-pagination-algorithm',
        types: const <int, int>{1: _CanonicalFieldType.string},
      );
      _expectRecord(
        rendererRecord,
        kind: 'reader-renderer-layout',
        types: _rendererTypes,
      );
      _expectRecord(
        compositeRecord,
        kind: 'reader-compatibility',
        types: const <int, int>{
          1: _CanonicalFieldType.string,
          2: _CanonicalFieldType.string,
          3: _CanonicalFieldType.string,
          4: _CanonicalFieldType.string,
          5: _CanonicalFieldType.string,
        },
      );

      final layoutIdentityRevision = layoutRecord.stringAt(1);
      final layoutContractRevision = layoutRecord.stringAt(2);
      final sourceFields = sourceRecord.stringListAt(1);
      final paginationRevision = paginationRecord.stringAt(1);
      final rendererRevision = rendererRecord.stringAt(1);
      final classifierRevision = compositeRecord.stringAt(1);
      if (layout.revision != layoutIdentityRevision ||
          pagination.semanticRevision != paginationRevision ||
          renderer.rulesRevisionLink != rendererRevision ||
          composite.classifierRevision != classifierRevision ||
          composite.layoutMetricsIdentity.fingerprint != layout.fingerprint ||
          composite.sourceCompatibilityIdentity.fingerprint !=
              source.fingerprint ||
          composite.paginationAlgorithmIdentity.fingerprint !=
              pagination.fingerprint ||
          composite.rendererLayoutIdentity.fingerprint !=
              renderer.fingerprint ||
          compositeRecord.stringAt(2) != layout.fingerprint ||
          compositeRecord.stringAt(3) != source.fingerprint ||
          compositeRecord.stringAt(4) != pagination.fingerprint ||
          compositeRecord.stringAt(5) != renderer.fingerprint) {
        return const _EvidenceValidation.corrupt();
      }
      _validateLayoutValues(layoutRecord);
      _validateSourceValues(sourceFields);
      _validateRendererValues(rendererRecord);
      if (paginationRevision.isEmpty ||
          classifierRevision.isEmpty ||
          !<String>[
            compositeRecord.stringAt(2),
            compositeRecord.stringAt(3),
            compositeRecord.stringAt(4),
            compositeRecord.stringAt(5),
          ].every(_validFingerprint)) {
        return const _EvidenceValidation.corrupt();
      }
      final supported =
          support.layoutMetricsIdentityRevisions.contains(
            layoutIdentityRevision,
          ) &&
          support.layoutContractRevisions.contains(layoutContractRevision) &&
          support.parserSourceSchemaIdentities.contains(sourceFields[1]) &&
          support.structuralOwnershipRevisions.contains(sourceFields[4]) &&
          support.paginationSemanticRevisions.contains(paginationRevision) &&
          support.rendererRulesRevisions.contains(rendererRevision) &&
          support.classifierRevisions.contains(classifierRevision);
      return supported
          ? _EvidenceValidation.valid(classifierRevision)
          : _EvidenceValidation.unsupported(classifierRevision);
    } on _UnsupportedCanonicalEvidenceException {
      return const _EvidenceValidation.unsupported(null);
    } on _CanonicalEvidenceFormatException {
      return const _EvidenceValidation.corrupt();
    }
  }

  static void _validateLayoutValues(_CanonicalRecord record) {
    if (record.stringAt(1).isEmpty ||
        record.stringAt(2).isEmpty ||
        record.stringAt(9).isEmpty ||
        record.stringAt(10).isEmpty ||
        !_validFingerprint(record.stringAt(11)) ||
        record.stringAt(14).isEmpty ||
        record.stringAt(19).isEmpty ||
        !_validFingerprint(record.stringAt(33)) ||
        record.stringListAt(34).isEmpty ||
        record.doubleAt(3) <= 0 ||
        record.doubleAt(4) <= 0 ||
        <double>[
          record.doubleAt(5),
          record.doubleAt(6),
          record.doubleAt(7),
          record.doubleAt(8),
        ].any((value) => value < 0) ||
        record.doubleAt(28) <= 0 ||
        record.doubleAt(29) <= 0 ||
        record.doubleAt(30) <= 0 ||
        record.doubleAt(31) <= 0 ||
        record.doubleAt(32) <= 0) {
      throw const _CanonicalEvidenceFormatException();
    }
  }

  static void _validateSourceValues(List<String> fields) {
    if (fields.length != 6 ||
        fields.any((field) => field.isEmpty) ||
        !_validFingerprint(fields[3]) ||
        !_validFingerprint(fields[5])) {
      throw const _CanonicalEvidenceFormatException();
    }
  }

  static void _validateRendererValues(_CanonicalRecord record) {
    if (record.stringAt(1).isEmpty || record.stringAt(3).isEmpty) {
      throw const _CanonicalEvidenceFormatException();
    }
    for (var tag = 2; tag <= 20; tag++) {
      if (tag == 3) continue;
      if (record.doubleAt(tag) < 0) {
        throw const _CanonicalEvidenceFormatException();
      }
    }
  }
}

const Map<int, int> _layoutMetricTypes = <int, int>{
  1: _CanonicalFieldType.string,
  2: _CanonicalFieldType.string,
  3: _CanonicalFieldType.doubleValue,
  4: _CanonicalFieldType.doubleValue,
  5: _CanonicalFieldType.doubleValue,
  6: _CanonicalFieldType.doubleValue,
  7: _CanonicalFieldType.doubleValue,
  8: _CanonicalFieldType.doubleValue,
  9: _CanonicalFieldType.string,
  10: _CanonicalFieldType.string,
  11: _CanonicalFieldType.string,
  12: _CanonicalFieldType.doubleValue,
  13: _CanonicalFieldType.boolean,
  14: _CanonicalFieldType.string,
  15: _CanonicalFieldType.doubleValue,
  16: _CanonicalFieldType.integer,
  17: _CanonicalFieldType.doubleValue,
  18: _CanonicalFieldType.doubleValue,
  19: _CanonicalFieldType.string,
  20: _CanonicalFieldType.doubleValue,
  21: _CanonicalFieldType.doubleValue,
  22: _CanonicalFieldType.doubleValue,
  23: _CanonicalFieldType.doubleValue,
  24: _CanonicalFieldType.doubleValue,
  25: _CanonicalFieldType.doubleValue,
  26: _CanonicalFieldType.doubleValue,
  27: _CanonicalFieldType.doubleValue,
  28: _CanonicalFieldType.doubleValue,
  29: _CanonicalFieldType.doubleValue,
  30: _CanonicalFieldType.doubleValue,
  31: _CanonicalFieldType.doubleValue,
  32: _CanonicalFieldType.doubleValue,
  33: _CanonicalFieldType.string,
  34: _CanonicalFieldType.stringList,
};

const Map<int, int> _rendererTypes = <int, int>{
  1: _CanonicalFieldType.string,
  2: _CanonicalFieldType.doubleValue,
  3: _CanonicalFieldType.string,
  4: _CanonicalFieldType.doubleValue,
  5: _CanonicalFieldType.doubleValue,
  6: _CanonicalFieldType.doubleValue,
  7: _CanonicalFieldType.doubleValue,
  8: _CanonicalFieldType.doubleValue,
  9: _CanonicalFieldType.doubleValue,
  10: _CanonicalFieldType.doubleValue,
  11: _CanonicalFieldType.doubleValue,
  12: _CanonicalFieldType.doubleValue,
  13: _CanonicalFieldType.doubleValue,
  14: _CanonicalFieldType.doubleValue,
  15: _CanonicalFieldType.doubleValue,
  16: _CanonicalFieldType.doubleValue,
  17: _CanonicalFieldType.doubleValue,
  18: _CanonicalFieldType.doubleValue,
  19: _CanonicalFieldType.doubleValue,
  20: _CanonicalFieldType.doubleValue,
};

enum _EvidenceState { valid, corrupt, unsupported }

final class _EvidenceValidation {
  const _EvidenceValidation.valid(this.classifierRevision)
    : state = _EvidenceState.valid;
  const _EvidenceValidation.corrupt()
    : state = _EvidenceState.corrupt,
      classifierRevision = null;
  const _EvidenceValidation.unsupported(this.classifierRevision)
    : state = _EvidenceState.unsupported;

  final _EvidenceState state;
  final String? classifierRevision;
}

bool _validFingerprint(String value) =>
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

void _expectRecord(
  _CanonicalRecord record, {
  required String kind,
  required Map<int, int> types,
}) {
  if (record.kind != kind) {
    throw const _CanonicalEvidenceFormatException();
  }
  if (record.revision != 1) {
    throw const _UnsupportedCanonicalEvidenceException();
  }
  if (record.fields.length != types.length) {
    throw const _CanonicalEvidenceFormatException();
  }
  for (final entry in types.entries) {
    final field = record.fields[entry.key];
    if (field == null || field.type != entry.value) {
      throw const _CanonicalEvidenceFormatException();
    }
  }
}

abstract final class _CanonicalFieldType {
  static const int string = 1;
  static const int integer = 2;
  static const int boolean = 3;
  static const int doubleValue = 4;
  static const int stringList = 5;
  static const int recordList = 6;
  static const int presence = 7;
}

final class _CanonicalRecord {
  const _CanonicalRecord(this.kind, this.revision, this.fields);

  factory _CanonicalRecord.parse(Uint8List bytes) {
    final reader = _CanonicalByteReader(bytes);
    final kindBytes = reader.bytes(reader.uint64());
    final kind = _decodeAscii(kindBytes);
    final revision = reader.uint64();
    final fields = <int, _CanonicalField>{};
    var previousTag = 0;
    while (!reader.isAtEnd) {
      final tag = reader.uint32();
      final type = reader.uint8();
      final payload = reader.bytes(reader.uint64());
      if (tag <= previousTag || tag == 0) {
        throw const _CanonicalEvidenceFormatException();
      }
      previousTag = tag;
      fields[tag] = _CanonicalField.parse(type, payload);
    }
    if (kind.isEmpty) {
      throw const _CanonicalEvidenceFormatException();
    }
    return _CanonicalRecord(
      kind,
      revision,
      Map<int, _CanonicalField>.unmodifiable(fields),
    );
  }

  final String kind;
  final int revision;
  final Map<int, _CanonicalField> fields;

  String stringAt(int tag) {
    final field = fields[tag];
    if (field?.stringValue == null) {
      throw const _CanonicalEvidenceFormatException();
    }
    return field!.stringValue!;
  }

  List<String> stringListAt(int tag) {
    final field = fields[tag];
    if (field?.stringListValue == null) {
      throw const _CanonicalEvidenceFormatException();
    }
    return field!.stringListValue!;
  }

  double doubleAt(int tag) {
    final field = fields[tag];
    if (field?.doubleValue == null) {
      throw const _CanonicalEvidenceFormatException();
    }
    return field!.doubleValue!;
  }
}

final class _CanonicalField {
  const _CanonicalField._({
    required this.type,
    this.stringValue,
    this.stringListValue,
    this.doubleValue,
  });

  factory _CanonicalField.parse(int type, Uint8List payload) {
    switch (type) {
      case _CanonicalFieldType.string:
        return _CanonicalField._(type: type, stringValue: _decodeUtf8(payload));
      case _CanonicalFieldType.integer:
        if (payload.length != 8) {
          throw const _CanonicalEvidenceFormatException();
        }
        return _CanonicalField._(type: type);
      case _CanonicalFieldType.boolean:
        if (payload.length != 1 ||
            (payload.single != 0 && payload.single != 1)) {
          throw const _CanonicalEvidenceFormatException();
        }
        return _CanonicalField._(type: type);
      case _CanonicalFieldType.doubleValue:
        if (payload.length != 8) {
          throw const _CanonicalEvidenceFormatException();
        }
        final data = ByteData.sublistView(payload);
        final value = data.getFloat64(0);
        if (!value.isFinite || (value == 0 && data.getUint64(0) != 0)) {
          throw const _CanonicalEvidenceFormatException();
        }
        return _CanonicalField._(type: type, doubleValue: value);
      case _CanonicalFieldType.stringList:
        final reader = _CanonicalByteReader(payload);
        final values = <String>[];
        final count = reader.uint64();
        for (var index = 0; index < count; index++) {
          values.add(_decodeUtf8(reader.bytes(reader.uint64())));
        }
        if (!reader.isAtEnd) {
          throw const _CanonicalEvidenceFormatException();
        }
        return _CanonicalField._(
          type: type,
          stringListValue: List<String>.unmodifiable(values),
        );
      case _CanonicalFieldType.recordList:
        final reader = _CanonicalByteReader(payload);
        final count = reader.uint64();
        for (var index = 0; index < count; index++) {
          final record = _CanonicalRecord.parse(reader.bytes(reader.uint64()));
          if (record.kind != 'entry' || record.revision != 1) {
            throw const _CanonicalEvidenceFormatException();
          }
        }
        if (!reader.isAtEnd) {
          throw const _CanonicalEvidenceFormatException();
        }
        return _CanonicalField._(type: type);
      case _CanonicalFieldType.presence:
        if (payload.length != 1 ||
            (payload.single != 0 && payload.single != 1)) {
          throw const _CanonicalEvidenceFormatException();
        }
        return _CanonicalField._(type: type);
      default:
        throw const _CanonicalEvidenceFormatException();
    }
  }

  final int type;
  final String? stringValue;
  final List<String>? stringListValue;
  final double? doubleValue;
}

final class _CanonicalByteReader {
  _CanonicalByteReader(this._bytes);

  final Uint8List _bytes;
  var _offset = 0;

  bool get isAtEnd => _offset == _bytes.length;

  int uint8() {
    if (_offset >= _bytes.length) {
      throw const _CanonicalEvidenceFormatException();
    }
    return _bytes[_offset++];
  }

  int uint32() {
    _require(4);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 4,
    ).getUint32(0);
    _offset += 4;
    return value;
  }

  int uint64() {
    _require(8);
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 8,
    ).getUint64(0);
    _offset += 8;
    return value;
  }

  Uint8List bytes(int length) {
    if (length < 0 || length > _bytes.length - _offset) {
      throw const _CanonicalEvidenceFormatException();
    }
    final result = Uint8List.fromList(
      _bytes.sublist(_offset, _offset + length),
    );
    _offset += length;
    return result;
  }

  void _require(int length) {
    if (length > _bytes.length - _offset) {
      throw const _CanonicalEvidenceFormatException();
    }
  }
}

String _decodeAscii(Uint8List bytes) {
  if (bytes.any((byte) => byte < 0x20 || byte > 0x7e)) {
    throw const _CanonicalEvidenceFormatException();
  }
  return _decodeUtf8(bytes);
}

String _decodeUtf8(Uint8List bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const _CanonicalEvidenceFormatException();
  }
}

final class _CanonicalEvidenceFormatException implements Exception {
  const _CanonicalEvidenceFormatException();
}

final class _UnsupportedCanonicalEvidenceException implements Exception {
  const _UnsupportedCanonicalEvidenceException();
}
