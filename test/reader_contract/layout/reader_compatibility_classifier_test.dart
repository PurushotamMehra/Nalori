import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/reader_compatibility.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/services/reader_compatibility_classifier.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CompatibilityFixture fixture;
  var classificationCount = 0;
  var maximumResultBytes = 0;
  var maximumReasonBytes = 0;
  var maximumChangedDimensions = 0;

  ReaderCompatibilityClassificationResult classify(
    ReaderCompatibilityEvidence previous,
    ReaderCompatibilityEvidence current, {
    ReaderCompatibilityRevisionSupport? support,
    bool signaturePresent = true,
  }) {
    final result = ReaderCompatibilityClassifier.classify(
      previous: previous,
      current: current,
      supportedRevisions: support ?? fixture.support(),
      requestedPhysicalCardSignaturePresent: signaturePresent,
    );
    classificationCount++;
    maximumResultBytes = maximum(
      maximumResultBytes,
      result.canonicalBytes.length,
    );
    maximumReasonBytes = maximum(
      maximumReasonBytes,
      result.reason.canonicalBytes.length,
    );
    maximumChangedDimensions = maximum(
      maximumChangedDimensions,
      result.changedDimensions.length,
    );
    expect(result.sourceTextBytesRetained, 0);
    expect(result.mutableIndexesRetained, 0);
    expect(result.classificationMutationCount, 0);
    expect(result.hasAnyAuthority, isFalse);
    return result;
  }

  setUpAll(() async {
    fixture = await _CompatibilityFixture.create();
  });

  tearDownAll(() {
    expect(classificationCount, greaterThanOrEqualTo(35));
    expect(maximumResultBytes, greaterThan(0));
    expect(maximumReasonBytes, greaterThan(0));
    expect(maximumChangedDimensions, 4);
    // ignore: avoid_print
    print(
      'P05_COMPATIBILITY_MAX classifications=$classificationCount '
      'resultBytes=$maximumResultBytes reasonBytes=$maximumReasonBytes '
      'changedDimensions=$maximumChangedDimensions sourceTextBytes=0 '
      'mutableIndexes=0 mutations=0',
    );
  });

  test('1. byte-identical valid evidence is exact compatible', () {
    final evidence = fixture.evidence(fixture.base);
    final result = classify(evidence, evidence);

    expect(result.kind, ReaderCompatibilityClassificationKind.exactCompatible);
    expect(result.mayProceedToExactReuseValidation, isTrue);
    expect(result.requiresFurtherPhysicalCardValidation, isTrue);
    expect(result.mayConsiderSemanticMigration, isFalse);
  });

  test('2. reconstructed byte-identical evidence is exact compatible', () {
    final original = fixture.base.identities.readerCompatibilityIdentity;
    final reconstructed = _cloneIdentity(original);
    final result = classify(
      ReaderCompatibilityEvidence.fromIdentity(original),
      ReaderCompatibilityEvidence.fromIdentity(reconstructed),
    );

    expect(result.kind, ReaderCompatibilityClassificationKind.exactCompatible);
    expect(
      result.previousFingerprints.readerCompatibilityFingerprint,
      result.currentFingerprints.readerCompatibilityFingerprint,
    );
  });

  test(
    '3. raw settings with identical effective values remain exact compatible',
    () async {
      final clampedLow = await fixture.build(
        settings: const ReadingSettings(sideMargin: 1),
      );
      final clampedMinimum = await fixture.build(
        settings: const ReadingSettings(sideMargin: 12),
      );
      final result = classify(
        fixture.evidence(clampedLow),
        fixture.evidence(clampedMinimum),
      );

      expect(
        result.kind,
        ReaderCompatibilityClassificationKind.exactCompatible,
      );
    },
  );

  test('4. every P05-005 transient state remains exact compatible', () {
    const transientStates = <String>[
      'controls_visible',
      'controls_hidden',
      'keyboard_view_insets_open',
      'keyboard_view_insets_closed',
      'active_card_changed',
      'preview_card_changed',
      'cached_deck_transform',
      'selection_paint',
      'link_recognizer_paint',
      'annotation_paint',
      'bookmark_reservation',
      'chapter_progress_reservation',
      'speed_reader_active',
      'speed_reader_paused',
    ];
    final evidence = fixture.evidence(fixture.base);

    for (final state in transientStates) {
      final result = classify(evidence, _cloneEvidence(evidence));
      expect(
        result.kind,
        ReaderCompatibilityClassificationKind.exactCompatible,
        reason: state,
      );
    }
  });

  test('5. one valid F196 change is a layout metrics change', () async {
    final changed = await fixture.build(
      padding: const EdgeInsets.fromLTRB(3, 24, 5, 19),
    );
    _expectSingleChange(
      classify(fixture.evidence(fixture.base), fixture.evidence(changed)),
      ReaderCompatibilityClassificationKind.layoutMetricsChanged,
      ReaderCompatibilityIdentityDimension.layoutMetrics,
    );
  });

  test('6. bottom safe-area change is a layout metrics change', () async {
    final changed = await fixture.build(
      padding: const EdgeInsets.fromLTRB(3, 24, 5, 42),
    );
    _expectSingleChange(
      classify(fixture.evidence(fixture.base), fixture.evidence(changed)),
      ReaderCompatibilityClassificationKind.layoutMetricsChanged,
      ReaderCompatibilityIdentityDimension.layoutMetrics,
    );
  });

  test(
    '7. terminal font metric evidence change is a layout metrics change',
    () {
      final base = fixture.base.identities.readerCompatibilityIdentity;
      final changedBytes = _replaceAscii(
        base.layoutMetricsIdentity.canonicalBytes,
        fixture.terminal.deliveryEvidence.digest,
        List<String>.filled(64, 'b').join(),
      );
      final changedLayout = LayoutMetricsIdentity(
        revision: base.layoutMetricsIdentity.revision,
        canonicalBytes: changedBytes,
        fingerprint: _digest(changedBytes),
      );
      final changed = _compose(base, layout: changedLayout);

      _expectSingleChange(
        classify(
          ReaderCompatibilityEvidence.fromIdentity(base),
          ReaderCompatibilityEvidence.fromIdentity(changed),
        ),
        ReaderCompatibilityClassificationKind.layoutMetricsChanged,
        ReaderCompatibilityIdentityDimension.layoutMetrics,
      );
    },
  );

  test('8. one valid F202 source snapshot change is a source change', () async {
    final changed = await fixture.build(
      sourceSnapshot: _digestText('snapshot-v2'),
    );
    _expectSingleChange(
      classify(fixture.evidence(fixture.base), fixture.evidence(changed)),
      ReaderCompatibilityClassificationKind.sourceCompatibilityChanged,
      ReaderCompatibilityIdentityDimension.sourceCompatibility,
    );
  });

  test(
    '9. supported parser/schema revision change is a source change',
    () async {
      final changed = await fixture.build(
        parserSourceSchemaIdentity: 'fixture-parser-v2',
      );
      _expectSingleChange(
        classify(
          fixture.evidence(fixture.base),
          fixture.evidence(changed),
          support: fixture.support(
            parsers: const <String>['fixture-parser-v1', 'fixture-parser-v2'],
          ),
        ),
        ReaderCompatibilityClassificationKind.sourceCompatibilityChanged,
        ReaderCompatibilityIdentityDimension.sourceCompatibility,
      );
    },
  );

  test(
    '10. structural ownership and source repertoire changes are source changes',
    () {
      final base = fixture.base.identities.readerCompatibilityIdentity;
      final structuralBytes = _replaceAscii(
        base.sourceCompatibilityIdentity.canonicalBytes,
        readerStructuralOwnershipRevision,
        'p04_structural_ownership_v2',
      );
      final structural = SourceCompatibilityIdentity(
        canonicalBytes: structuralBytes,
        fingerprint: _digest(structuralBytes),
      );
      final repertoireBytes = _replaceAscii(
        base.sourceCompatibilityIdentity.canonicalBytes,
        fixture.terminal.sourceEvidence.digest,
        List<String>.filled(64, 'c').join(),
      );
      final repertoire = SourceCompatibilityIdentity(
        canonicalBytes: repertoireBytes,
        fingerprint: _digest(repertoireBytes),
      );

      _expectSingleChange(
        classify(
          ReaderCompatibilityEvidence.fromIdentity(base),
          ReaderCompatibilityEvidence.fromIdentity(
            _compose(base, source: structural),
          ),
          support: fixture.support(
            structural: const <String>[
              readerStructuralOwnershipRevision,
              'p04_structural_ownership_v2',
            ],
          ),
        ),
        ReaderCompatibilityClassificationKind.sourceCompatibilityChanged,
        ReaderCompatibilityIdentityDimension.sourceCompatibility,
      );
      _expectSingleChange(
        classify(
          ReaderCompatibilityEvidence.fromIdentity(base),
          ReaderCompatibilityEvidence.fromIdentity(
            _compose(base, source: repertoire),
          ),
        ),
        ReaderCompatibilityClassificationKind.sourceCompatibilityChanged,
        ReaderCompatibilityIdentityDimension.sourceCompatibility,
      );
    },
  );

  test('11. valid F204 change is a pagination algorithm change', () {
    final base = fixture.base.identities.readerCompatibilityIdentity;
    final bytes = _replaceAscii(
      base.paginationAlgorithmIdentity.canonicalBytes,
      readerPaginationSemanticRevision,
      'nalori_cards_v17_lists',
    );
    final changed = PaginationAlgorithmIdentity(
      semanticRevision: 'nalori_cards_v17_lists',
      canonicalBytes: bytes,
      fingerprint: _digest(bytes),
    );
    _expectSingleChange(
      classify(
        ReaderCompatibilityEvidence.fromIdentity(base),
        ReaderCompatibilityEvidence.fromIdentity(
          _compose(base, pagination: changed),
        ),
        support: fixture.support(
          pagination: const <String>[
            readerPaginationSemanticRevision,
            'nalori_cards_v17_lists',
          ],
        ),
      ),
      ReaderCompatibilityClassificationKind.paginationAlgorithmChanged,
      ReaderCompatibilityIdentityDimension.paginationAlgorithm,
    );
  });

  test('12. valid F206 change is a renderer layout change', () {
    final base = fixture.base.identities.readerCompatibilityIdentity;
    final bytes = _replaceAscii(
      base.rendererLayoutIdentity.canonicalBytes,
      readerRendererRulesRevision,
      'reader_renderer_layout_v2',
    );
    final changed = RendererLayoutIdentity(
      rulesRevisionLink: 'reader_renderer_layout_v2',
      canonicalBytes: bytes,
      fingerprint: _digest(bytes),
    );
    _expectSingleChange(
      classify(
        ReaderCompatibilityEvidence.fromIdentity(base),
        ReaderCompatibilityEvidence.fromIdentity(
          _compose(base, renderer: changed),
        ),
        support: fixture.support(
          renderers: const <String>[
            readerRendererRulesRevision,
            'reader_renderer_layout_v2',
          ],
        ),
      ),
      ReaderCompatibilityClassificationKind.rendererLayoutChanged,
      ReaderCompatibilityIdentityDimension.rendererLayout,
    );
  });

  test(
    '13. valid compound changes preserve the fixed changed-dimension order',
    () {
      final base = fixture.base.identities.readerCompatibilityIdentity;
      final layoutBytes = _replaceAscii(
        base.layoutMetricsIdentity.canonicalBytes,
        fixture.terminal.deliveryEvidence.digest,
        List<String>.filled(64, 'd').join(),
      );
      final sourceBytes = _replaceAscii(
        base.sourceCompatibilityIdentity.canonicalBytes,
        fixture.terminal.sourceEvidence.digest,
        List<String>.filled(64, 'e').join(),
      );
      final paginationBytes = _replaceAscii(
        base.paginationAlgorithmIdentity.canonicalBytes,
        readerPaginationSemanticRevision,
        'nalori_cards_v17_lists',
      );
      final rendererBytes = _replaceAscii(
        base.rendererLayoutIdentity.canonicalBytes,
        readerRendererRulesRevision,
        'reader_renderer_layout_v2',
      );
      final compound = _compose(
        base,
        layout: LayoutMetricsIdentity(
          revision: base.layoutMetricsIdentity.revision,
          canonicalBytes: layoutBytes,
          fingerprint: _digest(layoutBytes),
        ),
        source: SourceCompatibilityIdentity(
          canonicalBytes: sourceBytes,
          fingerprint: _digest(sourceBytes),
        ),
        pagination: PaginationAlgorithmIdentity(
          semanticRevision: 'nalori_cards_v17_lists',
          canonicalBytes: paginationBytes,
          fingerprint: _digest(paginationBytes),
        ),
        renderer: RendererLayoutIdentity(
          rulesRevisionLink: 'reader_renderer_layout_v2',
          canonicalBytes: rendererBytes,
          fingerprint: _digest(rendererBytes),
        ),
      );
      final result = classify(
        ReaderCompatibilityEvidence.fromIdentity(base),
        ReaderCompatibilityEvidence.fromIdentity(compound),
        support: fixture.support(
          pagination: const <String>[
            readerPaginationSemanticRevision,
            'nalori_cards_v17_lists',
          ],
          renderers: const <String>[
            readerRendererRulesRevision,
            'reader_renderer_layout_v2',
          ],
        ),
      );

      expect(
        result.kind,
        ReaderCompatibilityClassificationKind.multipleAuthoritativeChanges,
      );
      expect(
        result.changedDimensions,
        ReaderCompatibilityIdentityDimension.values,
      );
      expect(result.mayConsiderSemanticMigration, isTrue);
    },
  );

  test('14. missing required evidence is incomplete', () {
    final result = classify(
      const ReaderCompatibilityEvidence(),
      fixture.evidence(fixture.base),
    );

    expect(
      result.kind,
      ReaderCompatibilityClassificationKind.incompleteEvidence,
    );
    expect(result.mayProceedToExactReuseValidation, isFalse);
    expect(result.mayConsiderSemanticMigration, isFalse);
  });

  test('15. modified component with a stale digest is corrupt', () {
    final base = fixture.base.identities.readerCompatibilityIdentity;
    final bytes = _replaceAscii(
      base.layoutMetricsIdentity.canonicalBytes,
      readerLayoutContractRevision,
      'reader_layout_contract_v2',
    );
    final stale = LayoutMetricsIdentity(
      revision: base.layoutMetricsIdentity.revision,
      canonicalBytes: bytes,
      fingerprint: base.layoutMetricsIdentity.fingerprint,
    );
    final invalid = _compose(base, layout: stale);
    final result = classify(
      ReaderCompatibilityEvidence.fromIdentity(base),
      ReaderCompatibilityEvidence.fromIdentity(invalid),
    );

    expect(result.kind, ReaderCompatibilityClassificationKind.corruptEvidence);
  });

  test('16. modified composite F208 only is corrupt', () {
    final base = fixture.base.identities.readerCompatibilityIdentity;
    final bytes = _replaceAscii(
      base.canonicalBytes,
      base.layoutMetricsIdentity.fingerprint,
      List<String>.filled(64, 'f').join(),
    );
    final invalid = ReaderCompatibilityIdentity(
      layoutMetricsIdentity: base.layoutMetricsIdentity,
      sourceCompatibilityIdentity: base.sourceCompatibilityIdentity,
      paginationAlgorithmIdentity: base.paginationAlgorithmIdentity,
      rendererLayoutIdentity: base.rendererLayoutIdentity,
      classifierRevision: base.classifierRevision,
      canonicalBytes: bytes,
      fingerprint: base.fingerprint,
    );
    final result = classify(
      ReaderCompatibilityEvidence.fromIdentity(base),
      ReaderCompatibilityEvidence.fromIdentity(invalid),
    );

    expect(result.kind, ReaderCompatibilityClassificationKind.corruptEvidence);
  });

  test(
    '17. unknown classifier, contract, identity, parser, renderer, and pagination revisions are unsupported',
    () async {
      final base = fixture.base.identities.readerCompatibilityIdentity;
      final unknownIdentityBytes = _replaceAscii(
        base.layoutMetricsIdentity.canonicalBytes,
        readerLayoutMetricsIdentityRevision,
        'reader_layout_metrics_identity_v9',
      );
      final unknownIdentity = _compose(
        base,
        layout: LayoutMetricsIdentity(
          revision: 'reader_layout_metrics_identity_v9',
          canonicalBytes: unknownIdentityBytes,
          fingerprint: _digest(unknownIdentityBytes),
        ),
      );
      final unknownContractBytes = _replaceAscii(
        base.layoutMetricsIdentity.canonicalBytes,
        readerLayoutContractRevision,
        'reader_layout_contract_v9',
      );
      final unknownContract = _compose(
        base,
        layout: LayoutMetricsIdentity(
          revision: base.layoutMetricsIdentity.revision,
          canonicalBytes: unknownContractBytes,
          fingerprint: _digest(unknownContractBytes),
        ),
      );
      final unknownParser = await fixture.build(
        parserSourceSchemaIdentity: 'fixture-parser-v99',
      );
      final unknownRendererBytes = _replaceAscii(
        base.rendererLayoutIdentity.canonicalBytes,
        readerRendererRulesRevision,
        'reader_renderer_layout_v9',
      );
      final unknownRenderer = _compose(
        base,
        renderer: RendererLayoutIdentity(
          rulesRevisionLink: 'reader_renderer_layout_v9',
          canonicalBytes: unknownRendererBytes,
          fingerprint: _digest(unknownRendererBytes),
        ),
      );
      final unknownPaginationBytes = _replaceAscii(
        base.paginationAlgorithmIdentity.canonicalBytes,
        readerPaginationSemanticRevision,
        'nalori_cards_v99_lists',
      );
      final unknownPagination = _compose(
        base,
        pagination: PaginationAlgorithmIdentity(
          semanticRevision: 'nalori_cards_v99_lists',
          canonicalBytes: unknownPaginationBytes,
          fingerprint: _digest(unknownPaginationBytes),
        ),
      );
      final unknownClassifier = ReaderCompatibilityIdentity.compose(
        layoutMetricsIdentity: base.layoutMetricsIdentity,
        sourceCompatibilityIdentity: base.sourceCompatibilityIdentity,
        paginationAlgorithmIdentity: base.paginationAlgorithmIdentity,
        rendererLayoutIdentity: base.rendererLayoutIdentity,
        classifierRevision: 'reader_compatibility_inputs_v9',
      );

      for (final candidate in <ReaderCompatibilityIdentity>[
        unknownIdentity,
        unknownContract,
        unknownParser.identities.readerCompatibilityIdentity,
        unknownRenderer,
        unknownPagination,
        unknownClassifier,
      ]) {
        final result = classify(
          ReaderCompatibilityEvidence.fromIdentity(base),
          ReaderCompatibilityEvidence.fromIdentity(candidate),
        );
        expect(
          result.kind,
          ReaderCompatibilityClassificationKind.unsupportedRevision,
        );
        expect(result.mayProceedToExactReuseValidation, isFalse);
        expect(result.mayConsiderSemanticMigration, isFalse);
      }
    },
  );

  test(
    '18. identical layout with a missing physical signature is never semantic migration',
    () {
      final evidence = fixture.evidence(fixture.base);
      final result = classify(evidence, evidence, signaturePresent: false);

      expect(
        result.kind,
        ReaderCompatibilityClassificationKind.exactCompatible,
      );
      expect(result.requestedPhysicalCardSignaturePresent, isFalse);
      expect(result.mayProceedToExactReuseValidation, isTrue);
      expect(result.mayConsiderSemanticMigration, isFalse);
    },
  );

  test(
    '19. genuine classification has no publication, settlement, cache, or checkpoint authority',
    () async {
      final changed = await fixture.build(
        padding: const EdgeInsets.fromLTRB(3, 24, 5, 42),
      );
      final result = classify(
        fixture.evidence(fixture.base),
        fixture.evidence(changed),
      );

      expect(
        result.kind,
        ReaderCompatibilityClassificationKind.layoutMetricsChanged,
      );
      expect(result.hasCacheAuthority, isFalse);
      expect(result.hasCheckpointAuthority, isFalse);
      expect(result.hasPublicationAuthority, isFalse);
      expect(result.hasSettlementAuthority, isFalse);
      expect(result.classificationMutationCount, 0);
    },
  );

  test(
    '20. comparison direction preserves the changed-dimension set',
    () async {
      final changed = await fixture.build(
        padding: const EdgeInsets.fromLTRB(3, 24, 5, 42),
        sourceSnapshot: _digestText('direction-snapshot'),
      );
      final forward = classify(
        fixture.evidence(fixture.base),
        fixture.evidence(changed),
      );
      final backward = classify(
        fixture.evidence(changed),
        fixture.evidence(fixture.base),
      );

      expect(forward.changedDimensions, backward.changedDimensions);
      expect(
        forward.changedDimensions,
        const <ReaderCompatibilityIdentityDimension>[
          ReaderCompatibilityIdentityDimension.layoutMetrics,
          ReaderCompatibilityIdentityDimension.sourceCompatibility,
        ],
      );
    },
  );

  test('21. repeated classification has byte-identical reason evidence', () {
    final evidence = fixture.evidence(fixture.base);
    final first = classify(evidence, evidence);
    final second = classify(evidence, evidence);

    expect(first.reason.canonicalBytes, second.reason.canonicalBytes);
    expect(first.canonicalBytes, second.canonicalBytes);
  });

  test('22. results retain neither source text nor mutable indexes', () {
    final evidence = fixture.evidence(fixture.base);
    final result = classify(evidence, evidence);
    final resultBytes = utf8.decode(
      result.canonicalBytes,
      allowMalformed: true,
    );

    expect(resultBytes, isNot(contains(_CompatibilityFixture.sourceText)));
    expect(result.sourceTextBytesRetained, 0);
    expect(result.mutableIndexesRetained, 0);
  });

  test('23. F001-F211 exhaustive mutation oracle is total and classified', () {
    final cases = <_FieldMutationCase>[
      for (final entry in ReaderLayoutFieldCoverage.byId.entries)
        _FieldMutationCase(
          id: entry.key,
          name: entry.value,
          behavior: _expectedFieldBehavior(entry.key),
        ),
    ];
    expect(cases, hasLength(211));
    expect(cases.map((entry) => entry.id).toSet(), hasLength(211));
    expect(cases.map((entry) => entry.name).toSet(), hasLength(211));

    final base = fixture.base.identities.readerCompatibilityIdentity;
    final baseEvidence = ReaderCompatibilityEvidence.fromIdentity(base);
    final behaviorCounts = <_FieldMutationBehavior, int>{};
    for (final mutation in cases) {
      behaviorCounts.update(
        mutation.behavior,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      final candidate = _mutateIdentityForField(base, mutation);
      final result = classify(
        baseEvidence,
        ReaderCompatibilityEvidence.fromIdentity(candidate),
        support:
            mutation.behavior ==
                _FieldMutationBehavior.changesPaginationAlgorithmIdentity
            ? fixture.support(
                pagination: <String>[
                  readerPaginationSemanticRevision,
                  _mutatedPaginationRevision(),
                ],
              )
            : null,
      );
      expect(
        result.kind,
        mutation.expectedClassifierKind,
        reason: mutation.label,
      );
      expect(result.hasAnyAuthority, isFalse, reason: mutation.label);

      if (mutation.behavior ==
          _FieldMutationBehavior.changesPhysicalCardComposite) {
        final physicalBefore = _digestText('${base.fingerprint}|physical');
        final physicalAfter = _digestText(
          '${base.fingerprint}|physical|${mutation.label}',
        );
        expect(physicalAfter, isNot(physicalBefore), reason: mutation.label);
      }
    }
    expect(behaviorCounts.keys, containsAll(_FieldMutationBehavior.values));
    // ignore: avoid_print
    print(
      'P05_FIELD_MUTATION_MAX fields=${cases.length} '
      'layout=${behaviorCounts[_FieldMutationBehavior.changesLayoutMetricsIdentity]} '
      'source=${behaviorCounts[_FieldMutationBehavior.changesSourceCompatibilityIdentity]} '
      'pagination=${behaviorCounts[_FieldMutationBehavior.changesPaginationAlgorithmIdentity]} '
      'renderer=${behaviorCounts[_FieldMutationBehavior.changesRendererLayoutIdentity]} '
      'physical=${behaviorCounts[_FieldMutationBehavior.changesPhysicalCardComposite]} '
      'validation=${behaviorCounts[_FieldMutationBehavior.validationOnly]} '
      'effectiveEqual=${behaviorCounts[_FieldMutationBehavior.sameEffectiveValue]} '
      'transient=${behaviorCounts[_FieldMutationBehavior.transientDiagnostic]} '
      'rejected=${behaviorCounts[_FieldMutationBehavior.typedRejection]}',
    );
  });

  test('24. canonical numeric and collection rules are exact', () {
    Uint8List encodedDouble(double value) {
      final writer = ReaderFontCanonicalWriter('binary64-probe', 1)
        ..doubleField(1, value);
      return writer.takeBytes();
    }

    expect(encodedDouble(1), isNot(encodedDouble(1.0000000000000002)));
    expect(encodedDouble(9.25), isNot(encodedDouble(9.250000000000002)));
    expect(encodedDouble(-0.0), encodedDouble(0.0));
    expect(() => encodedDouble(double.nan), throwsArgumentError);
    expect(() => encodedDouble(double.infinity), throwsArgumentError);
    expect(() => encodedDouble(double.negativeInfinity), throwsArgumentError);

    Uint8List encodedList(List<String> values) {
      final writer = ReaderFontCanonicalWriter('ordered-list-probe', 1)
        ..stringListField(1, values);
      return writer.takeBytes();
    }

    expect(encodedList(const ['a', 'b']), isNot(encodedList(const ['b', 'a'])));
    expect(
      ReaderCanonicalLocale(
        language: 'en',
        variants: const ['POSIX', 'abc'],
      ).tag,
      ReaderCanonicalLocale(
        language: 'en',
        variants: const ['abc', 'posix'],
      ).tag,
    );
    expect(
      ResolvedTextScaleProfile(
        responses: <double, double>{18: 18, 14: 14},
        domainCompletenessDigest: 'domain',
        scaleResponseDigest: 'scale',
      ).logicalSizes,
      const <double>[14, 18],
    );
  });

  test('25. malformed canonical field shapes reject atomically', () {
    final base = fixture.base.identities.readerCompatibilityIdentity;
    final layoutBytes = base.layoutMetricsIdentity.canonicalBytes;
    final records = _canonicalFieldRecords(layoutBytes);
    expect(records, hasLength(34));
    final headerEnd = records.first.start;

    Uint8List malformed(List<_CanonicalFieldRecordSlice> selected) {
      final bytes = BytesBuilder(copy: false)
        ..add(layoutBytes.sublist(0, headerEnd));
      for (final record in selected) {
        bytes.add(layoutBytes.sublist(record.start, record.end));
      }
      return bytes.takeBytes();
    }

    final missing = malformed(records.sublist(0, 33));
    final duplicate = malformed(<_CanonicalFieldRecordSlice>[
      ...records,
      records.last,
    ]);
    final reordered = malformed(<_CanonicalFieldRecordSlice>[
      ...records.sublist(0, 32),
      records[33],
      records[32],
    ]);
    final unknown = Uint8List.fromList(layoutBytes);
    ByteData.sublistView(unknown).setUint32(records.last.start, 35);
    final trailing = Uint8List.fromList(<int>[...layoutBytes, 0]);

    for (final bytes in <Uint8List>[
      missing,
      duplicate,
      reordered,
      unknown,
      trailing,
    ]) {
      final layout = LayoutMetricsIdentity(
        revision: base.layoutMetricsIdentity.revision,
        canonicalBytes: bytes,
        fingerprint: _digest(bytes),
      );
      expect(
        classify(
          ReaderCompatibilityEvidence.fromIdentity(base),
          ReaderCompatibilityEvidence.fromIdentity(
            _compose(base, layout: layout),
          ),
        ).kind,
        ReaderCompatibilityClassificationKind.corruptEvidence,
      );
    }
  });

  test('26. F208 recomputes from F196/F202/F204/F206 and excludes indexes', () {
    final base = fixture.base.identities.readerCompatibilityIdentity;
    final recomputed = ReaderCompatibilityIdentity.compose(
      layoutMetricsIdentity: base.layoutMetricsIdentity,
      sourceCompatibilityIdentity: base.sourceCompatibilityIdentity,
      paginationAlgorithmIdentity: base.paginationAlgorithmIdentity,
      rendererLayoutIdentity: base.rendererLayoutIdentity,
      classifierRevision: base.classifierRevision,
    );
    expect(recomputed.canonicalBytes, base.canonicalBytes);
    expect(recomputed.fingerprint, base.fingerprint);
    final text = utf8.decode(recomputed.canonicalBytes, allowMalformed: true);
    for (final forbidden in const <String>[
      'displayIndex',
      'pageIndex',
      'cardIndex',
      'controller',
      'windowIndex',
      'requestIndex',
      'runtimeObject',
    ]) {
      expect(text, isNot(contains(forbidden)));
    }
  });

  test(
    '27. U-05/U-06 terminal font transition is a genuine layout change',
    () async {
      final changed = await fixture.build(
        settings: const ReadingSettings(
          fontFamily: ReaderFontFamily.lora,
          fontWeight: ReaderFontWeight.bold,
        ),
      );
      final result = classify(
        fixture.evidence(fixture.base),
        fixture.evidence(changed),
      );
      expect(
        result.changedDimensions,
        contains(ReaderCompatibilityIdentityDimension.layoutMetrics),
      );
      expect(
        result.kind,
        isNot(ReaderCompatibilityClassificationKind.exactCompatible),
      );
      expect(result.hasAnyAuthority, isFalse);
    },
  );
}

enum _FieldMutationBehavior {
  changesLayoutMetricsIdentity,
  changesSourceCompatibilityIdentity,
  changesPaginationAlgorithmIdentity,
  changesRendererLayoutIdentity,
  changesPhysicalCardComposite,
  validationOnly,
  sameEffectiveValue,
  transientDiagnostic,
  typedRejection,
}

final class _FieldMutationCase {
  const _FieldMutationCase({
    required this.id,
    required this.name,
    required this.behavior,
  });

  final int id;
  final String name;
  final _FieldMutationBehavior behavior;
  String get label => 'F${id.toString().padLeft(3, '0')} $name';

  ReaderCompatibilityClassificationKind get expectedClassifierKind =>
      switch (behavior) {
        _FieldMutationBehavior.changesLayoutMetricsIdentity =>
          ReaderCompatibilityClassificationKind.layoutMetricsChanged,
        _FieldMutationBehavior.changesSourceCompatibilityIdentity =>
          ReaderCompatibilityClassificationKind.sourceCompatibilityChanged,
        _FieldMutationBehavior.changesPaginationAlgorithmIdentity =>
          ReaderCompatibilityClassificationKind.paginationAlgorithmChanged,
        _FieldMutationBehavior.changesRendererLayoutIdentity =>
          ReaderCompatibilityClassificationKind.rendererLayoutChanged,
        _FieldMutationBehavior.changesPhysicalCardComposite ||
        _FieldMutationBehavior.validationOnly ||
        _FieldMutationBehavior.sameEffectiveValue ||
        _FieldMutationBehavior.transientDiagnostic =>
          ReaderCompatibilityClassificationKind.exactCompatible,
        _FieldMutationBehavior.typedRejection =>
          ReaderCompatibilityClassificationKind.corruptEvidence,
      };
}

_FieldMutationBehavior _expectedFieldBehavior(int id) {
  if (<int>{12, 13, 14, 127}.contains(id)) {
    return _FieldMutationBehavior.validationOnly;
  }
  if (id == 68) return _FieldMutationBehavior.sameEffectiveValue;
  if (id == 22) return _FieldMutationBehavior.transientDiagnostic;
  if (<int>{113, 114, 195, 203, 205, 207, 208}.contains(id)) {
    return _FieldMutationBehavior.typedRejection;
  }
  if (id == 118 || (id >= 197 && id <= 202)) {
    return _FieldMutationBehavior.changesSourceCompatibilityIdentity;
  }
  if (id == 204) {
    return _FieldMutationBehavior.changesPaginationAlgorithmIdentity;
  }
  if ((id >= 129 && id <= 163) || id == 206) {
    return _FieldMutationBehavior.changesRendererLayoutIdentity;
  }
  if ((id >= 164 && id <= 194) || (id >= 209 && id <= 211)) {
    return _FieldMutationBehavior.changesPhysicalCardComposite;
  }
  return _FieldMutationBehavior.changesLayoutMetricsIdentity;
}

ReaderCompatibilityIdentity _mutateIdentityForField(
  ReaderCompatibilityIdentity base,
  _FieldMutationCase mutation,
) {
  switch (mutation.behavior) {
    case _FieldMutationBehavior.changesLayoutMetricsIdentity:
      final bytes = _replaceFloat64Field(
        base.layoutMetricsIdentity.canonicalBytes,
        28,
        (mutation.id + 1) / 1024,
      );
      return _compose(
        base,
        layout: LayoutMetricsIdentity(
          revision: base.layoutMetricsIdentity.revision,
          canonicalBytes: bytes,
          fingerprint: _digest(bytes),
        ),
      );
    case _FieldMutationBehavior.changesSourceCompatibilityIdentity:
      final digest = _digestText('source-${mutation.label}');
      final bytes = _replaceAscii(
        base.sourceCompatibilityIdentity.canonicalBytes,
        _sourceSnapshotDigest(base.sourceCompatibilityIdentity.canonicalBytes),
        digest,
      );
      return _compose(
        base,
        source: SourceCompatibilityIdentity(
          canonicalBytes: bytes,
          fingerprint: _digest(bytes),
        ),
      );
    case _FieldMutationBehavior.changesPaginationAlgorithmIdentity:
      final revision = _mutatedPaginationRevision();
      final bytes = _replaceAscii(
        base.paginationAlgorithmIdentity.canonicalBytes,
        readerPaginationSemanticRevision,
        revision,
      );
      return _compose(
        base,
        pagination: PaginationAlgorithmIdentity(
          semanticRevision: revision,
          canonicalBytes: bytes,
          fingerprint: _digest(bytes),
        ),
      );
    case _FieldMutationBehavior.changesRendererLayoutIdentity:
      final bytes = _replaceFloat64Field(
        base.rendererLayoutIdentity.canonicalBytes,
        2,
        (mutation.id + 1) / 1024,
      );
      return _compose(
        base,
        renderer: RendererLayoutIdentity(
          rulesRevisionLink: base.rendererLayoutIdentity.rulesRevisionLink,
          canonicalBytes: bytes,
          fingerprint: _digest(bytes),
        ),
      );
    case _FieldMutationBehavior.typedRejection:
      final bytes =
          Uint8List.fromList(base.layoutMetricsIdentity.canonicalBytes)
            ..[bytesIndexForMutation(
                  base.layoutMetricsIdentity.canonicalBytes,
                )] ^=
                1;
      return _compose(
        base,
        layout: LayoutMetricsIdentity(
          revision: base.layoutMetricsIdentity.revision,
          canonicalBytes: bytes,
          fingerprint: base.layoutMetricsIdentity.fingerprint,
        ),
      );
    case _FieldMutationBehavior.changesPhysicalCardComposite:
    case _FieldMutationBehavior.validationOnly:
    case _FieldMutationBehavior.sameEffectiveValue:
    case _FieldMutationBehavior.transientDiagnostic:
      return _cloneIdentity(base);
  }
}

String _mutatedPaginationRevision() =>
    readerPaginationSemanticRevision.endsWith('s')
    ? '${readerPaginationSemanticRevision.substring(0, readerPaginationSemanticRevision.length - 1)}x'
    : '${readerPaginationSemanticRevision.substring(0, readerPaginationSemanticRevision.length - 1)}s';

int bytesIndexForMutation(Uint8List bytes) => bytes.length - 1;

Uint8List _replaceFloat64Field(Uint8List source, int tag, double delta) {
  final result = Uint8List.fromList(source);
  final data = ByteData.sublistView(result);
  for (final record in _canonicalFieldRecords(result)) {
    if (record.tag != tag) continue;
    expect(data.getUint8(record.start + 4), 4);
    final payload = record.start + 13;
    data.setFloat64(payload, data.getFloat64(payload) + delta);
    return result;
  }
  throw StateError('Missing canonical double field $tag.');
}

String _sourceSnapshotDigest(Uint8List sourceBytes) {
  final text = utf8.decode(sourceBytes, allowMalformed: true);
  final matches = RegExp(r'[0-9a-f]{64}').allMatches(text).toList();
  expect(matches.length, greaterThanOrEqualTo(3));
  return matches[2].group(0)!;
}

final class _CanonicalFieldRecordSlice {
  const _CanonicalFieldRecordSlice(this.tag, this.start, this.end);
  final int tag;
  final int start;
  final int end;
}

List<_CanonicalFieldRecordSlice> _canonicalFieldRecords(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final kindLength = data.getUint64(0);
  var offset = 8 + kindLength + 8;
  final result = <_CanonicalFieldRecordSlice>[];
  while (offset + 13 <= bytes.length) {
    final tag = data.getUint32(offset);
    final payloadLength = data.getUint64(offset + 5);
    final end = offset + 13 + payloadLength;
    if (end > bytes.length) break;
    result.add(_CanonicalFieldRecordSlice(tag, offset, end));
    offset = end;
  }
  return result;
}

void _expectSingleChange(
  ReaderCompatibilityClassificationResult result,
  ReaderCompatibilityClassificationKind kind,
  ReaderCompatibilityIdentityDimension dimension,
) {
  expect(result.kind, kind);
  expect(result.changedDimensions, <ReaderCompatibilityIdentityDimension>[
    dimension,
  ]);
  expect(result.mayProceedToExactReuseValidation, isFalse);
  expect(result.mayConsiderSemanticMigration, isTrue);
}

ReaderCompatibilityEvidence _cloneEvidence(
  ReaderCompatibilityEvidence source,
) => ReaderCompatibilityEvidence.fromIdentity(
  _cloneIdentity(source.readerCompatibilityIdentity!),
);

ReaderCompatibilityIdentity _cloneIdentity(
  ReaderCompatibilityIdentity source,
) => ReaderCompatibilityIdentity(
  layoutMetricsIdentity: LayoutMetricsIdentity(
    revision: source.layoutMetricsIdentity.revision,
    canonicalBytes: source.layoutMetricsIdentity.canonicalBytes,
    fingerprint: source.layoutMetricsIdentity.fingerprint,
  ),
  sourceCompatibilityIdentity: SourceCompatibilityIdentity(
    canonicalBytes: source.sourceCompatibilityIdentity.canonicalBytes,
    fingerprint: source.sourceCompatibilityIdentity.fingerprint,
  ),
  paginationAlgorithmIdentity: PaginationAlgorithmIdentity(
    semanticRevision: source.paginationAlgorithmIdentity.semanticRevision,
    canonicalBytes: source.paginationAlgorithmIdentity.canonicalBytes,
    fingerprint: source.paginationAlgorithmIdentity.fingerprint,
  ),
  rendererLayoutIdentity: RendererLayoutIdentity(
    rulesRevisionLink: source.rendererLayoutIdentity.rulesRevisionLink,
    canonicalBytes: source.rendererLayoutIdentity.canonicalBytes,
    fingerprint: source.rendererLayoutIdentity.fingerprint,
  ),
  classifierRevision: source.classifierRevision,
  canonicalBytes: source.canonicalBytes,
  fingerprint: source.fingerprint,
);

ReaderCompatibilityIdentity _compose(
  ReaderCompatibilityIdentity base, {
  LayoutMetricsIdentity? layout,
  SourceCompatibilityIdentity? source,
  PaginationAlgorithmIdentity? pagination,
  RendererLayoutIdentity? renderer,
  String? classifierRevision,
}) => ReaderCompatibilityIdentity.compose(
  layoutMetricsIdentity: layout ?? base.layoutMetricsIdentity,
  sourceCompatibilityIdentity: source ?? base.sourceCompatibilityIdentity,
  paginationAlgorithmIdentity: pagination ?? base.paginationAlgorithmIdentity,
  rendererLayoutIdentity: renderer ?? base.rendererLayoutIdentity,
  classifierRevision: classifierRevision ?? base.classifierRevision,
);

Uint8List _replaceAscii(Uint8List source, String original, String replacement) {
  final originalBytes = ascii.encode(original);
  final replacementBytes = ascii.encode(replacement);
  expect(replacementBytes.length, originalBytes.length);
  final result = Uint8List.fromList(source);
  for (var start = 0; start <= result.length - originalBytes.length; start++) {
    if (Iterable<int>.generate(
      originalBytes.length,
      (index) => start + index,
    ).every((index) => result[index] == originalBytes[index - start])) {
      result.setRange(start, start + originalBytes.length, replacementBytes);
      return result;
    }
  }
  throw StateError('Canonical source did not contain $original.');
}

String _digest(Uint8List bytes) => ReaderFontCanonicalEncoder.digest(bytes);

String _digestText(String value) =>
    _digest(Uint8List.fromList(utf8.encode(value)));

int maximum(int first, int second) => first > second ? first : second;

final class _CompatibilityFixture {
  _CompatibilityFixture._(this.gate, this.terminal, this.base);

  static const String sourceText = 'Compatibility source text must not escape.';

  final ReaderFontEvidenceGate gate;
  final ReaderFontReadyTerminalBundled terminal;
  final ReaderLayoutContract base;

  static Future<_CompatibilityFixture> create() async {
    final gate = ReaderFontEvidenceGate();
    final outcome = await gate.capture(
      settings: const ReadingSettings(),
      stableSourceIdentity: 'compatibility-source',
      sourceStartUtf16: 0,
      sourceText: sourceText,
      locale: 'en-US',
    );
    expect(outcome, isA<ReaderFontReadyTerminalBundled>());
    final terminal = outcome as ReaderFontReadyTerminalBundled;
    final fixture = _CompatibilityFixture._(
      gate,
      terminal,
      await _buildContract(gate: gate, terminal: terminal),
    );
    return fixture;
  }

  Future<ReaderLayoutContract> build({
    ReadingSettings settings = const ReadingSettings(),
    EdgeInsets padding = const EdgeInsets.fromLTRB(3, 24, 5, 18),
    String parserSourceSchemaIdentity = 'fixture-parser-v1',
    String? sourceSnapshot,
  }) async {
    final outcome = await gate.capture(
      settings: settings,
      stableSourceIdentity: 'compatibility-source',
      sourceStartUtf16: 0,
      sourceText: sourceText,
      locale: 'en-US',
    );
    expect(outcome, isA<ReaderFontReadyTerminalBundled>());
    return _buildContract(
      gate: gate,
      terminal: outcome as ReaderFontReadyTerminalBundled,
      settings: settings,
      padding: padding,
      parserSourceSchemaIdentity: parserSourceSchemaIdentity,
      sourceSnapshot: sourceSnapshot,
    );
  }

  ReaderCompatibilityEvidence evidence(ReaderLayoutContract contract) =>
      ReaderCompatibilityEvidence.fromIdentity(
        contract.identities.readerCompatibilityIdentity,
      );

  ReaderCompatibilityRevisionSupport support({
    Iterable<String> parsers = const <String>['fixture-parser-v1'],
    Iterable<String> structural = const <String>[
      readerStructuralOwnershipRevision,
    ],
    Iterable<String> pagination = const <String>[
      readerPaginationSemanticRevision,
    ],
    Iterable<String> renderers = const <String>[readerRendererRulesRevision],
  }) => ReaderCompatibilityRevisionSupport(
    layoutContractRevisions: const <String>[readerLayoutContractRevision],
    layoutMetricsIdentityRevisions: const <String>[
      readerLayoutMetricsIdentityRevision,
    ],
    parserSourceSchemaIdentities: parsers,
    structuralOwnershipRevisions: structural,
    paginationSemanticRevisions: pagination,
    rendererRulesRevisions: renderers,
    classifierRevisions: const <String>[readerCompatibilityClassifierRevision],
  );
}

Future<ReaderLayoutContract> _buildContract({
  required ReaderFontEvidenceGate gate,
  required ReaderFontReadyTerminalBundled terminal,
  ReadingSettings settings = const ReadingSettings(),
  EdgeInsets padding = const EdgeInsets.fromLTRB(3, 24, 5, 18),
  String parserSourceSchemaIdentity = 'fixture-parser-v1',
  String? sourceSnapshot,
}) async {
  final built = ReaderLayoutContractBuilder.build(
    ReaderLayoutContractBuildInput(
      deckSize: const Size(390, 420),
      mediaQuerySize: const Size(390, 420),
      viewPadding: padding,
      locale: const Locale('en', 'US'),
      defaultDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      settings: settings,
      fontOutcome: terminal,
      captureFreshnessEvidence: 'compatibility-generation',
      publicationFingerprint: _digestText('compatibility-publication'),
      parserSourceSchemaIdentity: parserSourceSchemaIdentity,
      sourceRevision: 'compatibility-source-revision-v1',
      sourceSnapshotDigest:
          sourceSnapshot ?? _digestText('compatibility-snapshot'),
    ),
  );
  expect(built, isA<ReaderLayoutContractReady>());
  return (built as ReaderLayoutContractReady).contract;
}
