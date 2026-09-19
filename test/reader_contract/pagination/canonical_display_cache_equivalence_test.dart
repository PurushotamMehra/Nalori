import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/canonical_display_segment.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reader_compatibility.dart';
import 'package:nalori/services/canonical_display_segment_admission.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/display_section_memory_cache.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/segmented_display_cache_service.dart';

import '../support/reader_contract_sandbox.dart';
import 'reader_card_pagination_evidence.dart';
import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('nalori_reader_p06_cache_');
  });

  tearDownAll(() => fixture.close());

  group('[REQ-009, REQ-010, REQ-013, REQ-044, REQ-045, REQ-046, '
      'REQ-048, REQ-051] TASK-P06-003 canonical cache equivalence', () {
    testWidgets(
      'cold, memory, disk, eviction, regeneration, and mixed states are exact twice',
      (tester) async {
        final normalizedRuns = <String>[];
        for (var run = 0; run < 2; run++) {
          final sandbox = (await tester.runAsync(
            ReaderContractSandbox.create,
          ))!;
          addTearDown(sandbox.close);
          final harness = await ReaderCorePaginationHarness.install(
            tester: tester,
            sourceChunks: fixture.sourceChunks,
            bookId: 'p06-003-book',
            publicationFingerprint: 'p06-003-publication',
            stateCacheKey: 'p06-003-state',
          );
          final scope = readerSha256('p06-003-storage-scope');
          // ignore: avoid_print
          print('P06_CACHE_PHASE run=$run cold-start');
          final cold = await harness.canonicalColdSegments(
            bookStorageScopeDigest: scope,
            label: 'p06-cold-$run',
          );
          expectReaderCoreStructuralInvariants(cold.construction);
          expect(cold.records.length, greaterThan(1));
          // ignore: avoid_print
          print(
            'P06_CACHE_PHASE run=$run cold-done records=${cold.records.length}',
          );

          final memory = CanonicalDisplaySegmentMemoryTransport();
          final diskRoot = Directory(
            '${sandbox.root.path}/canonical-logical-records',
          );
          final disk = CanonicalDisplaySegmentControlledDiskStore(
            rootDirectory: diskRoot,
          );
          for (final record in cold.records) {
            memory.put(record);
          }
          await tester.runAsync(() async {
            for (final record in cold.records) {
              await disk.write(record);
            }
          });
          final storedMemoryBytes = memory.canonicalBytes;
          final storedDiskBytes = (await tester.runAsync(
            () => disk.byteCount,
          ))!;

          final warmMemory = await _publishRecords(
            harness: harness,
            reference: cold,
            records: <CanonicalDisplaySegmentRecord>[
              for (final record in cold.records) memory.get(record.keyDigest)!,
            ],
            source: _CandidateSource.memory,
            scope: scope,
          );
          final reopenedDisk = CanonicalDisplaySegmentControlledDiskStore(
            rootDirectory: diskRoot,
          );
          final warmDisk = (await tester.runAsync(
            () => _publishDiskRecords(
              harness: harness,
              reference: cold,
              records: cold.records,
              disk: reopenedDisk,
              scope: scope,
            ),
          ))!;

          final acceptedDisplayBeforeEviction = _stateBytes(warmMemory.state);
          memory.clear();
          expect(memory.recordCount, 0);
          expect(_stateBytes(warmMemory.state), acceptedDisplayBeforeEviction);
          final memoryEvictedDisk = (await tester.runAsync(
            () => _publishDiskRecords(
              harness: harness,
              reference: cold,
              records: cold.records,
              disk: reopenedDisk,
              scope: scope,
            ),
          ))!;

          await tester.runAsync(() async {
            for (final record in cold.records) {
              await reopenedDisk.remove(record.keyDigest);
            }
          });
          expect(_stateBytes(warmMemory.state), acceptedDisplayBeforeEviction);
          final beforeAbsent = _emptyState(harness);
          final absentBytes = _stateBytes(beforeAbsent);
          expect(
            CanonicalDisplaySegmentAdmission.absent().outcome,
            CanonicalDisplaySegmentValidationOutcome.safeMissAbsent,
          );
          expect(_stateBytes(beforeAbsent), absentBytes);
          final regenerated = await harness.canonicalColdSegments(
            bookStorageScopeDigest: scope,
            label: 'p06-regenerated-after-eviction-$run',
          );
          expect(_recordBytes(regenerated.records), _recordBytes(cold.records));
          final fullEvictionRegenerated = regenerated.construction;

          final rejectedState = _emptyState(harness);
          final rejectedBefore = _stateBytes(rejectedState);
          final stale = CanonicalDisplaySegmentAdmission.admitMemoryRecord(
            record: cold.records.first,
            limits: _limits,
            context: _context(
              harness: harness,
              reference: cold,
              scope: scope,
              acceptedRestart: null,
              expectedGeneration: 'current',
            ),
            claimedGeneration: 'stale',
          );
          expect(
            stale.outcome,
            CanonicalDisplaySegmentValidationOutcome.rejectedStaleGeneration,
          );
          expect(_stateBytes(rejectedState), rejectedBefore);
          final rejectedRegenerated = await harness.canonicalColdSegments(
            bookStorageScopeDigest: scope,
            label: 'p06-regenerated-after-rejection-$run',
          );
          expect(
            _recordBytes(rejectedRegenerated.records),
            _recordBytes(cold.records),
          );
          final rejectedThenRegenerated = rejectedRegenerated.construction;
          // ignore: avoid_print
          print('P06_CACHE_PHASE run=$run regeneration-done');

          final prefixRegeneratedSuffixCached = await _publishRecords(
            harness: harness,
            reference: cold,
            records: <CanonicalDisplaySegmentRecord>[
              regenerated.records.first,
              ...cold.records.skip(1),
            ],
            source: _CandidateSource.mixed,
            scope: scope,
          );
          final prefixCachedSuffixRegenerated = await _publishRecords(
            harness: harness,
            reference: cold,
            records: <CanonicalDisplaySegmentRecord>[
              cold.records.first,
              ...regenerated.records.skip(1),
            ],
            source: _CandidateSource.mixed,
            scope: scope,
          );
          final cachedMiddle = await _publishRecords(
            harness: harness,
            reference: cold,
            records: <CanonicalDisplaySegmentRecord>[
              regenerated.records.first,
              for (var index = 1; index < cold.records.length - 1; index++)
                cold.records[index],
              regenerated.records.last,
            ],
            source: _CandidateSource.mixed,
            scope: scope,
          );

          final constructions = <ReaderPaginationConstruction>[
            cold.construction,
            warmMemory,
            warmDisk,
            memoryEvictedDisk,
            fullEvictionRegenerated,
            rejectedThenRegenerated,
            prefixRegeneratedSuffixCached,
            prefixCachedSuffixRegenerated,
            cachedMiddle,
          ];
          for (final construction in constructions.skip(1)) {
            expectReaderCoreStructuralInvariants(construction);
            expect(
              compareConstructionToFull(
                scenario: construction.label,
                full: cold.construction,
                actual: construction,
              ),
              isNull,
            );
          }

          final maxRecordBytes = cold.records
              .map(
                (record) => CanonicalDisplaySegmentCodec.encode(record).length,
              )
              .reduce(_max);
          final maxCardBytes = cold.records
              .expand((record) => record.orderedFinalizedCards)
              .map((card) => card.canonicalBytes.length)
              .reduce(_max);
          final maxBoundaryBytes = cold.records
              .map(
                (record) =>
                    record.leftBoundaryProof.canonicalBytes.length +
                    record.rightBoundaryProof.canonicalBytes.length,
              )
              .reduce(_max);
          final maxContinuationBytes = cold.records
              .map(
                (record) => utf8
                    .encode(record.continuationEvidence.canonicalEncoding)
                    .length,
              )
              .reduce(_max);
          final normalized = _normalizedEvidence(constructions, cold.records);
          normalizedRuns.add(normalized);
          // ignore: avoid_print
          print(
            'P06_CACHE_MAX coldSourceWork=${cold.maxSourceWork} '
            'safeMissSourceWork=${regenerated.maxSourceWork} '
            'validationFields=${13 + 32 + (11 * cold.records.map((r) => r.declaredCardCount).reduce(_max))} '
            'keyBytes=${cold.records.map((r) => r.canonicalKeyBytes.length).reduce(_max)} '
            'recordBytes=$maxRecordBytes cardBytes=$maxCardBytes '
            'boundaryBytes=$maxBoundaryBytes continuationBytes=$maxContinuationBytes '
            'memoryBytes=$storedMemoryBytes diskBytes=$storedDiskBytes '
            'segments=${cold.records.length} cards=${cold.construction.state.canonicalCards.length} '
            'sourceSlices=${cold.records.fold<int>(0, (sum, r) => sum + r.declaredSourceSliceCount)} '
            'continuationDepth=${cold.records.map((r) => _continuation(r).chainOrdinal).reduce(_max)} '
            'cardsPerTransaction=${cold.maxCardsPublished} copiedSourceTextBytes=0 '
            'mutableIndexIdentityBytes=0 rejectedAuthorityMutations=0',
          );
          // ignore: avoid_print
          print('P06_CACHE_NORMALIZED $normalized');
        }
        expect(normalizedRuns[1], normalizedRuns[0]);
      },
    );

    testWidgets(
      'forward, target-first, and bounded-backward orders retain the P03 oracle',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final full = await harness.fullRange();
        final forward = await harness.forwardFirst(const <SourceChunkRange>[
          SourceChunkRange(0, 5),
          SourceChunkRange(5, 8),
          SourceChunkRange(8, 20),
        ]);
        final target = await harness.targetFirst(7);
        final backward = await harness.backwardFirst(const <SourceChunkRange>[
          SourceChunkRange(0, 5),
          SourceChunkRange(5, 8),
          SourceChunkRange(8, 20),
        ]);
        for (final construction in <ReaderPaginationConstruction>[
          forward,
          target,
          backward,
        ]) {
          expect(
            compareConstructionToFull(
              scenario: construction.label,
              full: full,
              actual: construction,
            ),
            isNull,
          );
        }
      },
    );

    testWidgets(
      'split-stress cache records preserve the four source-7 intervals',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        final cold = await harness.canonicalColdSegments(
          bookStorageScopeDigest: readerSha256('p06-split-storage-scope'),
        );
        final ranges = cold.construction.evidence.cards
            .expand((card) => card.sourceRanges)
            .where((range) => range.sourceIndex == 7)
            .map(
              (range) => '[${range.sourceStartUtf16},${range.sourceEndUtf16})',
            )
            .toList(growable: false);
        expect(ranges, <String>[
          '[0,58)',
          '[58,125)',
          '[125,191)',
          '[191,198)',
        ]);
        final warm = await _publishRecords(
          harness: harness,
          reference: cold,
          records: cold.records,
          source: _CandidateSource.memory,
          scope: readerSha256('p06-split-storage-scope'),
        );
        expect(
          compareConstructionToFull(
            scenario: 'split-stress-warm',
            full: cold.construction,
            actual: warm,
          ),
          isNull,
        );
      },
    );

    testWidgets(
      'admitted candidates remain atomic across unproved joins and commit failures',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final scope = readerSha256('p06-atomic-storage-scope');
        final cold = await harness.canonicalColdSegments(
          bookStorageScopeDigest: scope,
        );
        final state = _emptyState(harness);
        final before = _stateBytes(state);
        final context = _context(
          harness: harness,
          reference: cold,
          scope: scope,
          acceptedRestart: null,
        );
        final admission = CanonicalDisplaySegmentAdmission.admitMemoryRecord(
          record: cold.records.first,
          limits: _limits,
          context: context,
        );
        expect(admission.isExact, isTrue);
        expect(admission.hasPublicationAuthority, isFalse);
        expect(admission.exactCandidate!.hasPublicationAuthority, isFalse);
        expect(_stateBytes(state), before);

        final join = CanonicalDisplaySegmentAdmission.join(
          admission,
          CanonicalDisplaySegmentAdmission.admitMemoryRecord(
            record: cold.records[1],
            limits: _limits,
            context: _context(
              harness: harness,
              reference: cold,
              scope: scope,
              acceptedRestart: _continuation(cold.records.first),
            ),
          ),
        );
        expect(join.isExact, isFalse);
        expect(join.hasJoinAuthority, isFalse);
        expect(_stateBytes(state), before);

        var cancelled = false;
        final cancelledPublication = state.publishCanonical(
          _request(
            harness: harness,
            state: state,
            candidate: admission.exactCandidate!,
            generation: 9300,
            isCancelled: () => cancelled,
            beforeCommit: () => cancelled = true,
          ),
        );
        expect(
          cancelledPublication.kind,
          CanonicalDisplayPublicationOutcomeKind.cancellationBeforeCommit,
        );
        expect(_stateBytes(state), before);

        final failedPublication = state.publishCanonical(
          _request(
            harness: harness,
            state: state,
            candidate: admission.exactCandidate!,
            generation: 9301,
            beforeCommit: () => throw StateError('injected-p06-failure'),
          ),
        );
        expect(
          failedPublication.kind,
          CanonicalDisplayPublicationOutcomeKind.validationError,
        );
        expect(_stateBytes(state), before);

        final accepted = state.publishCanonical(
          _request(
            harness: harness,
            state: state,
            candidate: admission.exactCandidate!,
            generation: 9302,
          ),
        );
        expect(accepted, isA<CanonicalDisplayPublicationAccepted>());
        expect(state.canonicalCards, isNotEmpty);
      },
    );
  });
}

enum _CandidateSource { memory, disk, mixed }

const _limits = CanonicalDisplaySegmentCodecLimits(
  maxEncodedBytes: 1 << 20,
  maxDecodedBytes: 1 << 20,
  maxFieldBytes: 1 << 18,
  maxCards: 96,
  maxSourceSlices: 432,
  maxBlockLayouts: 4096,
  maxContinuationBytes: 1 << 18,
  maxManifestSegments: 64,
  maxContinuationChainOrdinal: 25,
);

Future<ReaderPaginationConstruction> _publishDiskRecords({
  required ReaderCorePaginationHarness harness,
  required ReaderCanonicalSegmentConstruction reference,
  required List<CanonicalDisplaySegmentRecord> records,
  required CanonicalDisplaySegmentControlledDiskStore disk,
  required String scope,
}) async {
  final decoded = <CanonicalDisplaySegmentRecord>[];
  for (final record in records) {
    final bytes = await disk.read(record.keyDigest);
    if (bytes == null) throw StateError('Controlled disk record is absent.');
    decoded.add(CanonicalDisplaySegmentCodec.decode(bytes, limits: _limits));
  }
  return _publishRecords(
    harness: harness,
    reference: reference,
    records: decoded,
    source: _CandidateSource.disk,
    scope: scope,
  );
}

Future<ReaderPaginationConstruction> _publishRecords({
  required ReaderCorePaginationHarness harness,
  required ReaderCanonicalSegmentConstruction reference,
  required List<CanonicalDisplaySegmentRecord> records,
  required _CandidateSource source,
  required String scope,
}) async {
  final state = _emptyState(harness);
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    final admission = source == _CandidateSource.disk
        ? CanonicalDisplaySegmentAdmission.admitDiskBytes(
            bytes: CanonicalDisplaySegmentCodec.encode(record),
            limits: _limits,
            context: _context(
              harness: harness,
              reference: reference,
              scope: scope,
              acceptedRestart: state.acceptedCanonicalContinuation,
            ),
          )
        : CanonicalDisplaySegmentAdmission.admitMemoryRecord(
            record: record,
            limits: _limits,
            context: _context(
              harness: harness,
              reference: reference,
              scope: scope,
              acceptedRestart: state.acceptedCanonicalContinuation,
            ),
          );
    if (!admission.isExact || admission.exactCandidate == null) {
      throw StateError(
        'Canonical ${source.name} admission failed: '
        '${admission.outcome.name} ${admission.diagnostics}',
      );
    }
    final before = _stateBytes(state);
    final publication = state.publishCanonical(
      _request(
        harness: harness,
        state: state,
        candidate: admission.exactCandidate!,
        generation: 9100 + index,
      ),
    );
    if (publication is! CanonicalDisplayPublicationAccepted) {
      throw StateError(
        'P04 publication rejected exact candidate: '
        '${publication.kind}; before=$before',
      );
    }
  }
  return ReaderPaginationConstruction(
    label: 'p06-${source.name}-reuse',
    layoutIdentity: harness.layoutIdentity,
    requestedRanges: records
        .map(
          (record) =>
              '${record.stableStartCursor.sourceOrdinalHint}:'
              '${record.stableEndCursor.sourceOrdinalHint}',
        )
        .toList(growable: false),
    state: state,
    evidence: _evidence(harness, state),
    results: const <DisplayRangeResult>[],
  );
}

CanonicalDisplaySegmentAdmissionContext _context({
  required ReaderCorePaginationHarness harness,
  required ReaderCanonicalSegmentConstruction reference,
  required String scope,
  required CanonicalPaginationContinuation? acceptedRestart,
  String? expectedGeneration,
}) {
  final session = harness.canonicalSessionForP04();
  final compatibility = ReaderCompatibilityEvidence.fromIdentity(
    harness.paginatorLayout.contract!.identities.readerCompatibilityIdentity,
  );
  return CanonicalDisplaySegmentAdmissionContext(
    bookStorageScopeDigest: scope,
    publicationFingerprint: session.sourceSnapshot.publicationFingerprint,
    sourceSnapshot: session.sourceSnapshot,
    currentCompatibilityEvidence: compatibility,
    supportedCompatibilityRevisions: ReaderCompatibilityRevisionSupport.current(
      parserSourceSchemaIdentities: <String>[
        session.sourceSnapshot.parserSourceIdentity,
      ],
    ),
    controlledLayoutIdentity: harness.layoutIdentity,
    paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
    acceptedFinalizedCards: reference.construction.state.canonicalCards,
    acceptedRestart: acceptedRestart,
    expectedGeneration: expectedGeneration,
  );
}

CanonicalDisplayPublicationRequest _request({
  required ReaderCorePaginationHarness harness,
  required ProgressiveDisplayState state,
  required CanonicalDisplaySegmentExactCandidate candidate,
  required int generation,
  bool Function()? isCancelled,
  void Function()? beforeCommit,
}) => CanonicalDisplayPublicationRequest(
  operation: state.canonicalCards.isEmpty
      ? CanonicalDisplayPublicationOperation.initial
      : CanonicalDisplayPublicationOperation.append,
  sessionIdentity: 'p06-cache-publication',
  generationIdentity: generation,
  currentGenerationIdentity: () => generation,
  sourceSnapshot: harness.canonicalSessionForP04().sourceSnapshot,
  controlledLayoutIdentity: harness.layoutIdentity,
  paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
  finalizedCards: candidate.finalizedCards,
  continuation: candidate.continuation,
  predecessorContinuation: state.acceptedCanonicalContinuation,
  committedCard: state.canonicalCards.isEmpty
      ? null
      : state.canonicalCards.first,
  isCancelled: isCancelled ?? () => false,
  beforeCommit: beforeCommit,
);

ProgressiveDisplayState _emptyState(ReaderCorePaginationHarness harness) =>
    ProgressiveDisplayState(
      signature: DisplayGenerationSignature(
        bookId: harness.bookId,
        parsedContentVersion: 1,
        layoutSignature: harness.layoutIdentity,
        settingsSignature: 'p06-controlled',
        viewportSignature: harness.environment.inputs.diagnosticJson,
        cacheKey: 'p06-controlled',
      ),
      sourceChunkCount: harness.sourceChunks.length,
    );

ReaderCardPaginationEvidence _evidence(
  ReaderCorePaginationHarness harness,
  ProgressiveDisplayState state,
) => ReaderCardPaginationEvidence.projectSnapshot(
  requestedSourceRange: '[0,${harness.sourceChunks.length})',
  displayChunks: state.displayChunks,
  displayToOriginal: state.displayToOriginal,
  sourceChunks: harness.sourceChunks,
  readableSourceExtents: readerCoreReadableSourceExtents,
  publicationFingerprint: harness.publicationFingerprint,
  layoutFingerprint: harness.layoutIdentity,
  cardIdentities: state.canonicalCards.map((card) => card.identity).toList(),
);

String _stateBytes(ProgressiveDisplayState state) =>
    canonicalJsonEncode(<String, Object?>{
      'cards': state.canonicalCards
          .map((card) => card.identity.signature)
          .toList(growable: false),
      'chunks': state.displayChunks
          .map((chunk) => chunk.toJson())
          .toList(growable: false),
      'continuation': state.acceptedCanonicalContinuation?.canonicalEncoding,
      'maps': state.displayToOriginal,
      'reverse': state.originalToDisplay,
      'ranges': state.ranges
          .map(
            (range) => <int>[
              range.sourceRange.start,
              range.sourceRange.endExclusive,
              range.displayStart,
              range.displayEndExclusive,
            ],
          )
          .toList(growable: false),
      'writeAuthority': state.hasCanonicalCacheWriteAuthority,
    });

String _recordBytes(List<CanonicalDisplaySegmentRecord> records) =>
    base64Encode(
      records
          .expand(CanonicalDisplaySegmentCodec.encode)
          .toList(growable: false),
    );

CanonicalPaginationContinuation _continuation(
  CanonicalDisplaySegmentRecord record,
) {
  final decoded = CanonicalPaginationContinuationCodec.decode(
    record.continuationEvidence.canonicalEncoding,
  );
  if (decoded is! CanonicalPaginationContinuationAccepted) {
    throw StateError('Stored continuation did not decode.');
  }
  return decoded.continuation;
}

String _normalizedEvidence(
  List<ReaderPaginationConstruction> constructions,
  List<CanonicalDisplaySegmentRecord> records,
) => readerSha256(
  canonicalJsonEncode(<String, Object?>{
    'constructions': constructions
        .map((construction) => construction.evidence.describe())
        .toList(growable: false),
    'records': records
        .map((record) => record.checksumDigest)
        .toList(growable: false),
  }),
);

int _max(int left, int right) => left > right ? left : right;
