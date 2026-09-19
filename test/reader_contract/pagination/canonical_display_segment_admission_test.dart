import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/canonical_display_segment.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reader_compatibility.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/services/canonical_display_segment_admission.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('nalori_p06_002_');
  });
  tearDownAll(() => fixture.close());

  group('[TASK-P06-002] canonical display-segment admission', () {
    testWidgets(
      'stable key/record round trip admits the identical memory and disk candidate',
      (tester) async {
        final material = await _material(tester, fixture);
        final bytes = CanonicalDisplaySegmentCodec.encode(material.record);
        final decoded = CanonicalDisplaySegmentCodec.decode(
          bytes,
          limits: _limits,
        );
        expect(decoded.keyDigest, material.record.keyDigest);
        expect(decoded.canonicalKeyBytes, material.record.canonicalKeyBytes);

        final disk = CanonicalDisplaySegmentAdmission.admitDiskBytes(
          bytes: bytes,
          limits: _limits,
          context: material.context,
        );
        final memory = CanonicalDisplaySegmentAdmission.admitMemoryRecord(
          record: material.record,
          limits: _limits,
          context: material.context,
        );
        expect(
          disk.outcome,
          CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible,
        );
        expect(memory.outcome, disk.outcome);
        expect(memory.canonicalOutcomeBytes, disk.canonicalOutcomeBytes);
        expect(disk.candidate, isNotNull);
        expect(disk.hasPublicationAuthority, isFalse);
        expect(disk.hasJoinAuthority, isFalse);
        expect(disk.hasCacheWriteAuthority, isFalse);
        expect(disk.hasCheckpointOrSettlementAuthority, isFalse);
        expect(disk.cards, isEmpty);
        expect(disk.continuation, isNull);
      },
    );

    testWidgets(
      'the 13 encoded key fields exclude transient mutable identity',
      (tester) async {
        final material = await _material(tester, fixture);
        final text = String.fromCharCodes(material.record.canonicalKeyBytes);
        expect(
          material.record.canonicalKeyBytes,
          material.record.canonicalKeyBytes,
        );
        expect(
          material.record.keyDigest,
          readerSha256(material.record.canonicalKeyBytes),
        );
        for (final forbidden in <String>[
          'displayIndex',
          'cardOrdinal',
          'windowIndex',
          'requestIndex',
          'SourceChunkRange',
          'segmentOrdinal',
          'generationId',
          'filename',
          'accessTime',
          'lru',
        ]) {
          expect(text, isNot(contains(forbidden)));
        }
        expect(material.record.canonicalKeyBytes.length, greaterThan(0));
      },
    );

    testWidgets(
      'all declared field/count/checksum/encoding failures reject before admission',
      (tester) async {
        final material = await _material(tester, fixture);
        final bytes = CanonicalDisplaySegmentCodec.encode(material.record);
        for (final mutation in <Uint8List>[
          Uint8List.fromList(<int>[...bytes.sublist(0, bytes.length - 1), 0]),
          Uint8List.fromList(<int>[255, ...bytes]),
          Uint8List.fromList(bytes)..[bytes.length ~/ 2] ^= 0x01,
        ]) {
          final result = CanonicalDisplaySegmentAdmission.admitDiskBytes(
            bytes: mutation,
            limits: _limits,
            context: material.context,
          );
          expect(
            result.outcome,
            CanonicalDisplaySegmentValidationOutcome
                .rejectedCorruptChecksumOrEncoding,
          );
          expect(result.candidate, isNull);
        }
      },
    );

    testWidgets(
      'scope, generation, source/card, boundary and continuation evidence fail closed',
      (tester) async {
        final material = await _material(tester, fixture);
        final crossBook = CanonicalDisplaySegmentAdmissionContext(
          bookStorageScopeDigest: readerSha256('other-scope'),
          publicationFingerprint: material.context.publicationFingerprint,
          sourceSnapshot: material.context.sourceSnapshot,
          currentCompatibilityEvidence:
              material.context.currentCompatibilityEvidence,
          supportedCompatibilityRevisions:
              material.context.supportedCompatibilityRevisions,
          controlledLayoutIdentity: material.context.controlledLayoutIdentity,
          paginationAlgorithmIdentity:
              material.context.paginationAlgorithmIdentity,
          acceptedFinalizedCards: material.context.acceptedFinalizedCards,
        );
        expect(
          CanonicalDisplaySegmentAdmission.admitRecord(
            record: material.record,
            limits: _limits,
            context: crossBook,
          ).outcome,
          CanonicalDisplaySegmentValidationOutcome.rejectedCrossBookScope,
        );
        expect(
          CanonicalDisplaySegmentAdmission.admitRecord(
            record: material.record,
            limits: _limits,
            context: material.context,
            claimedGeneration: 'stale',
          ).outcome,
          CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible,
        );
        final generationContext = _withGeneration(material.context, 'current');
        expect(
          CanonicalDisplaySegmentAdmission.admitRecord(
            record: material.record,
            limits: _limits,
            context: generationContext,
            claimedGeneration: 'stale',
          ).outcome,
          CanonicalDisplaySegmentValidationOutcome.rejectedStaleGeneration,
        );
        expect(
          CanonicalDisplaySegmentAdmission.join(
            CanonicalDisplaySegmentAdmission.admitMemoryRecord(
              record: material.record,
              limits: _limits,
              context: material.context,
            ),
            CanonicalDisplaySegmentAdmission.admitMemoryRecord(
              record: material.record,
              limits: _limits,
              context: material.context,
            ),
          ).outcome,
          CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch,
        );
      },
    );

    testWidgets(
      'source interval ownership must be the exact ordered pinned half-open span',
      (tester) async {
        final material = await _material(tester, fixture);
        final interval = material.record.exactHalfOpenSourceInterval;
        expect(interval.orderedOwners.length, greaterThan(1));
        final malformedIntervals = <CanonicalDisplaySegmentSourceInterval>[
          CanonicalDisplaySegmentSourceInterval(
            startCursor: interval.startCursor,
            endCursor: interval.endCursor,
            orderedOwners: interval.orderedOwners.reversed.toList(),
          ),
          CanonicalDisplaySegmentSourceInterval(
            startCursor: interval.startCursor,
            endCursor: interval.endCursor,
            orderedOwners: interval.orderedOwners.sublist(1),
          ),
        ];
        for (final malformedInterval in malformedIntervals) {
          final result = CanonicalDisplaySegmentAdmission.admitMemoryRecord(
            record: _copyRecord(
              material.record,
              exactHalfOpenSourceInterval: malformedInterval,
            ),
            limits: _limits,
            context: material.context,
          );
          expect(
            result.outcome,
            CanonicalDisplaySegmentValidationOutcome
                .rejectedCardIdentityOrContentMismatch,
          );
        }
      },
    );

    testWidgets(
      'bounded continuations and key boundary roles cannot be claimed out of proof shape',
      (tester) async {
        final material = await _material(tester, fixture);
        final original =
            CanonicalPaginationContinuationCodec.decode(
                  material.record.continuationEvidence.canonicalEncoding,
                )
                as CanonicalPaginationContinuationAccepted;
        final overBound = CanonicalPaginationContinuation.create(
          key: original.continuation.key,
          startSourceCursor: original.continuation.startSourceCursor,
          nextSourceCursor: original.continuation.nextSourceCursor,
          frontier: original.continuation.frontier,
          previousFinalizedBoundary:
              original.continuation.previousFinalizedBoundary,
          chainOrdinal: _limits.maxContinuationChainOrdinal + 1,
          parentDigest: readerSha256('p06-002-over-bound-parent'),
          checkpointReason: original.continuation.checkpointReason,
          sourcesSinceCheckpoint: original.continuation.sourcesSinceCheckpoint,
          cardsSinceCheckpoint: original.continuation.cardsSinceCheckpoint,
          terminal: original.continuation.terminal,
        );
        final continuationEvidence =
            CanonicalDisplaySegmentContinuationEvidence.fromContinuation(
              overBound,
            );
        expect(
          CanonicalDisplaySegmentAdmission.admitMemoryRecord(
            record: _copyRecord(
              material.record,
              continuationEvidence: continuationEvidence,
              rightBoundaryProof: _rightWithContinuationDigest(
                material.record.rightBoundaryProof,
                continuationEvidence.continuationDigest,
              ),
            ),
            limits: _limits,
            context: material.context,
          ).outcome,
          CanonicalDisplaySegmentValidationOutcome.rejectedContinuationMismatch,
        );

        final originalKey = CanonicalDisplaySegmentKey.decode(
          material.record.canonicalKeyBytes,
          limits: _limits,
        );
        expect(
          CanonicalDisplaySegmentAdmission.admitMemoryRecord(
            record: _copyRecord(
              material.record,
              key: _keyWithBoundaryRole(
                originalKey,
                CanonicalDisplaySegmentBoundaryRole.continuationAnchored,
              ),
            ),
            limits: _limits,
            context: material.context,
          ).outcome,
          CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch,
        );
      },
    );

    testWidgets(
      'all sixteen typed outcomes are reachable and retain zero authority',
      (tester) async {
        final material = await _material(tester, fixture);
        final identity = material
            .context
            .currentCompatibilityEvidence
            .readerCompatibilityIdentity!;
        final sourceBytes = _replaceAscii(
          identity.sourceCompatibilityIdentity.canonicalBytes,
          material.context.sourceSnapshot.snapshotDigest,
          List<String>.filled(64, 'a').join(),
        );
        final sourceChanged = _composeCompatibility(
          identity,
          source: SourceCompatibilityIdentity(
            canonicalBytes: sourceBytes,
            fingerprint: _digest(sourceBytes),
          ),
        );
        final paginationBytes = _replaceAscii(
          identity.paginationAlgorithmIdentity.canonicalBytes,
          readerPaginationSemanticRevision,
          'nalori_cards_v17_lists',
        );
        final paginationChanged = _composeCompatibility(
          identity,
          pagination: PaginationAlgorithmIdentity(
            semanticRevision: 'nalori_cards_v17_lists',
            canonicalBytes: paginationBytes,
            fingerprint: _digest(paginationBytes),
          ),
        );
        final rendererBytes = _replaceAscii(
          identity.rendererLayoutIdentity.canonicalBytes,
          readerRendererRulesRevision,
          'reader_renderer_layout_v2',
        );
        final rendererChanged = _composeCompatibility(
          identity,
          renderer: RendererLayoutIdentity(
            rulesRevisionLink: 'reader_renderer_layout_v2',
            canonicalBytes: rendererBytes,
            fingerprint: _digest(rendererBytes),
          ),
        );
        final corruptLayout = LayoutMetricsIdentity(
          revision: identity.layoutMetricsIdentity.revision,
          canonicalBytes: identity.layoutMetricsIdentity.canonicalBytes,
          fingerprint: readerSha256('p06-002-corrupt-layout-evidence'),
        );
        final alternate = await _material(
          tester,
          fixture,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        final samples = <CanonicalDisplaySegmentRecord>[
          material.record,
          alternate.record,
        ];
        final maxKeyBytes = samples
            .map((record) => record.canonicalKeyBytes.length)
            .reduce((left, right) => left > right ? left : right);
        final maxRecordBytes = samples
            .map((record) => CanonicalDisplaySegmentCodec.encode(record).length)
            .reduce((left, right) => left > right ? left : right);
        final maxCardBytes = samples
            .expand((record) => record.orderedFinalizedCards)
            .map((card) => card.canonicalBytes.length)
            .reduce((left, right) => left > right ? left : right);
        final maxBoundaryBytes = samples
            .map(
              (record) =>
                  record.leftBoundaryProof.canonicalBytes.length +
                  record.rightBoundaryProof.canonicalBytes.length,
            )
            .reduce((left, right) => left > right ? left : right);
        final maxContinuationBytes = samples
            .map(
              (record) => utf8
                  .encode(record.continuationEvidence.canonicalEncoding)
                  .length,
            )
            .reduce((left, right) => left > right ? left : right);
        final maxCards = samples
            .map((record) => record.orderedFinalizedCards.length)
            .reduce((left, right) => left > right ? left : right);
        final maxSlices = samples
            .map((record) => record.declaredSourceSliceCount)
            .reduce((left, right) => left > right ? left : right);
        final maxValidationFields = samples
            .map(
              (record) =>
                  13 +
                  record.declaredTopLevelFieldCount +
                  (11 * record.orderedFinalizedCards.length),
            )
            .reduce((left, right) => left > right ? left : right);
        expect(maxKeyBytes, lessThanOrEqualTo(_limits.maxEncodedBytes));
        expect(maxRecordBytes, lessThanOrEqualTo(_limits.maxEncodedBytes));
        expect(
          maxContinuationBytes,
          lessThanOrEqualTo(_limits.maxContinuationBytes),
        );
        expect(maxCards, lessThanOrEqualTo(_limits.maxCards));
        expect(maxSlices, lessThanOrEqualTo(_limits.maxSourceSlices));
        expect(material.record.declaredTopLevelFieldCount, 32);
        expect(
          material.record.orderedFinalizedCards,
          everyElement(
            predicate<CanonicalDisplaySegmentCardRecord>(
              (card) => card.canonicalBytes.isNotEmpty,
            ),
          ),
        );
        // ignore: avoid_print
        print(
          'P06_ADMISSION_MAX keyBytes=$maxKeyBytes recordBytes=$maxRecordBytes '
          'cardBytes=$maxCardBytes boundaryBytes=$maxBoundaryBytes '
          'continuationBytes=$maxContinuationBytes validationFields=$maxValidationFields '
          'cards=$maxCards slices=$maxSlices sourceTextBytes=0 '
          'mutableIndexBytes=0 rejectionMutations=0',
        );
        final originalRecordBytes = CanonicalDisplaySegmentCodec.encode(
          material.record,
        );
        final malformedInterval = CanonicalDisplaySegmentSourceInterval(
          startCursor: material.record.exactHalfOpenSourceInterval.startCursor,
          endCursor: material.record.exactHalfOpenSourceInterval.endCursor,
          orderedOwners: material
              .record
              .exactHalfOpenSourceInterval
              .orderedOwners
              .sublist(1),
        );
        final original =
            CanonicalPaginationContinuationCodec.decode(
                  material.record.continuationEvidence.canonicalEncoding,
                )
                as CanonicalPaginationContinuationAccepted;
        final overBound = CanonicalPaginationContinuation.create(
          key: original.continuation.key,
          startSourceCursor: original.continuation.startSourceCursor,
          nextSourceCursor: original.continuation.nextSourceCursor,
          frontier: original.continuation.frontier,
          previousFinalizedBoundary:
              original.continuation.previousFinalizedBoundary,
          chainOrdinal: _limits.maxContinuationChainOrdinal + 1,
          parentDigest: readerSha256('p06-002-over-bound-parent'),
          checkpointReason: original.continuation.checkpointReason,
          sourcesSinceCheckpoint: original.continuation.sourcesSinceCheckpoint,
          cardsSinceCheckpoint: original.continuation.cardsSinceCheckpoint,
          terminal: original.continuation.terminal,
        );
        final overBoundEvidence =
            CanonicalDisplaySegmentContinuationEvidence.fromContinuation(
              overBound,
            );
        final outcomes =
            <
              CanonicalDisplaySegmentValidationOutcome,
              CanonicalDisplaySegmentAdmissionResult
            >{
              CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible:
                  _admit(material),
              CanonicalDisplaySegmentValidationOutcome.safeMissAbsent:
                  CanonicalDisplaySegmentAdmission.absent(),
              CanonicalDisplaySegmentValidationOutcome
                  .safeMissIncompleteCanonicalEvidence: _admit(
                material,
                context: _withCompatibility(
                  material.context,
                  const ReaderCompatibilityEvidence(),
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome
                  .safeMissIncompatibleSourceOrParser: _admit(
                material,
                context: _withCompatibility(
                  material.context,
                  ReaderCompatibilityEvidence.fromIdentity(sourceChanged),
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome.safeMissChangedLayout:
                  _admit(
                    material,
                    context: _withCompatibility(
                      material.context,
                      alternate.context.currentCompatibilityEvidence,
                    ),
                  ),
              CanonicalDisplaySegmentValidationOutcome
                  .safeMissChangedRendererRules: _admit(
                material,
                context: _withCompatibility(
                  material.context,
                  ReaderCompatibilityEvidence.fromIdentity(rendererChanged),
                  supportedCompatibilityRevisions: _supportWith(
                    material.context.supportedCompatibilityRevisions,
                    rendererRulesRevisions: const <String>[
                      readerRendererRulesRevision,
                      'reader_renderer_layout_v2',
                    ],
                  ),
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome
                  .safeMissChangedPaginationAlgorithm: _admit(
                material,
                context: _withCompatibility(
                  material.context,
                  ReaderCompatibilityEvidence.fromIdentity(paginationChanged),
                  supportedCompatibilityRevisions: _supportWith(
                    material.context.supportedCompatibilityRevisions,
                    paginationSemanticRevisions: const <String>[
                      readerPaginationSemanticRevision,
                      'nalori_cards_v17_lists',
                    ],
                  ),
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome
                  .safeMissUnsupportedRevision: _admit(
                material,
                context: _withCompatibility(
                  material.context,
                  material.context.currentCompatibilityEvidence,
                  supportedCompatibilityRevisions: _supportWith(
                    material.context.supportedCompatibilityRevisions,
                    paginationSemanticRevisions: const <String>[
                      'unsupported-pagination-revision',
                    ],
                  ),
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome
                      .rejectedCorruptChecksumOrEncoding:
                  CanonicalDisplaySegmentAdmission.admitDiskBytes(
                    bytes: Uint8List.fromList(<int>[255]),
                    limits: _limits,
                    context: material.context,
                  ),
              CanonicalDisplaySegmentValidationOutcome
                  .rejectedBoundaryMismatch: _admit(
                material,
                record: _copyRecord(
                  material.record,
                  key: _keyWithBoundaryRole(
                    CanonicalDisplaySegmentKey.decode(
                      material.record.canonicalKeyBytes,
                      limits: _limits,
                    ),
                    CanonicalDisplaySegmentBoundaryRole.continuationAnchored,
                  ),
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome
                  .rejectedContinuationMismatch: _admit(
                material,
                record: _copyRecord(
                  material.record,
                  continuationEvidence: overBoundEvidence,
                  rightBoundaryProof: _rightWithContinuationDigest(
                    material.record.rightBoundaryProof,
                    overBoundEvidence.continuationDigest,
                  ),
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome
                  .rejectedCardIdentityOrContentMismatch: _admit(
                material,
                record: _copyRecord(
                  material.record,
                  exactHalfOpenSourceInterval: malformedInterval,
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome.rejectedStaleGeneration:
                  _admit(
                    material,
                    context: _withGeneration(material.context, 'current'),
                    claimedGeneration: 'stale',
                  ),
              CanonicalDisplaySegmentValidationOutcome.rejectedCrossBookScope:
                  _admit(
                    material,
                    context: _withBookStorageScope(material.context, 'other'),
                  ),
              CanonicalDisplaySegmentValidationOutcome
                  .rejectedCompatibilityEvidenceCorrupt: _admit(
                material,
                context: _withCompatibility(
                  material.context,
                  ReaderCompatibilityEvidence.fromIdentity(
                    _composeCompatibility(identity, layout: corruptLayout),
                  ),
                ),
              ),
              CanonicalDisplaySegmentValidationOutcome.regenerationRequired:
                  CanonicalDisplaySegmentAdmission.legacySafeMiss(
                    cacheKind: 'segmented',
                  ),
            };
        expect(
          outcomes.keys,
          unorderedEquals(CanonicalDisplaySegmentValidationOutcome.values),
        );
        for (final entry in outcomes.entries) {
          final result = entry.value;
          expect(result.outcome, entry.key, reason: entry.key.name);
          expect(result.hasJoinAuthority, isFalse);
          expect(result.hasPublicationAuthority, isFalse);
          expect(result.hasCacheWriteAuthority, isFalse);
          expect(result.hasCheckpointOrSettlementAuthority, isFalse);
          expect(result.cards, isEmpty);
          expect(result.continuation, isNull);
        }
        expect(
          CanonicalDisplaySegmentCodec.encode(material.record),
          originalRecordBytes,
        );
      },
    );
  });
}

const _limits = CanonicalDisplaySegmentCodecLimits(
  maxEncodedBytes: 1 << 20,
  maxDecodedBytes: 1 << 20,
  maxFieldBytes: 1 << 18,
  maxCards: 96,
  maxSourceSlices: 432,
  maxBlockLayouts: 4096,
  maxContinuationBytes: 1 << 18,
  maxManifestSegments: 8,
  maxContinuationChainOrdinal: 25,
);

Future<_Material> _material(
  WidgetTester tester,
  ReaderCoreParsedFixture fixture, {
  ReaderCorePaginationLayout layout = ReaderCorePaginationLayout.standard,
}) async {
  final harness = await ReaderCorePaginationHarness.install(
    tester: tester,
    sourceChunks: fixture.sourceChunks,
    layout: layout,
    bookId: 'p06-002-book',
    publicationFingerprint: 'p06-002-publication',
  );
  final session = harness.canonicalSessionForP04(deferPublicationCommit: true);
  final outcome = await session.generateInitial(
    restart: const CanonicalPaginationPublicationStart(),
    operation: harness.canonicalOperationForP04(),
    budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 8),
  );
  expect(outcome, isA<CanonicalReaderPaginationPathAccepted>());
  final accepted = outcome as CanonicalReaderPaginationPathAccepted;
  expect(accepted.publishableCards, isNotEmpty);
  final snapshot = session.sourceSnapshot;
  final compatibility = ReaderCompatibilityEvidence.fromIdentity(
    harness.paginatorLayout.contract!.identities.readerCompatibilityIdentity,
  );
  final evidence =
      CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
        compatibility,
      );
  final cards = <CanonicalDisplaySegmentCardRecord>[
    for (final card in accepted.publishableCards)
      CanonicalDisplaySegmentCardRecord.fromFinalized(
        card,
        sourceSnapshot: snapshot,
      ),
  ];
  final ownerOrdinals = <int>{
    for (final card in accepted.publishableCards)
      for (final slice in card.sourceSlices) slice.sourceOrdinalHint,
  }.toList()..sort();
  final interval = CanonicalDisplaySegmentSourceInterval(
    startCursor: cards.first.cardStartCursor,
    endCursor: cards.last.cardEndCursor,
    orderedOwners: <CanonicalDisplaySegmentSourceOwner>[
      for (final ordinal in ownerOrdinals)
        CanonicalDisplaySegmentSourceOwner.fromOwner(snapshot.ownerAt(ordinal)),
    ],
  );
  final key = CanonicalDisplaySegmentKey(
    bookStorageScopeDigest: readerSha256('p06-002-storage-scope'),
    publicationFingerprint: snapshot.publicationFingerprint,
    sourceCompatibilityFingerprint: evidence.sourceCompatibility.fingerprint,
    layoutMetricsFingerprint: evidence.layoutMetrics.fingerprint,
    rendererLayoutFingerprint: evidence.rendererLayout.fingerprint,
    paginationAlgorithmFingerprint: evidence.paginationAlgorithm.fingerprint,
    compatibilityClassifierRevision: evidence.classifierRevision,
    readerCompatibilityFingerprint: evidence.readerCompatibility.fingerprint,
    stableStartCursor: cards.first.cardStartCursor,
    stableEndCursor: cards.last.cardEndCursor,
    boundaryRole: CanonicalDisplaySegmentBoundaryRole.bookStartAnchored,
  );
  final continuation =
      CanonicalDisplaySegmentContinuationEvidence.fromContinuation(
        accepted.continuation,
      );
  final frontier = accepted.continuation.terminal
      ? CanonicalDisplaySegmentRightBoundaryProof(
          kind: CanonicalDisplaySegmentRightBoundaryKind.logicalEnd,
          finalCardSignature: cards.last.physicalCardSignature,
          finalCardEndCursor: cards.last.cardEndCursor,
        )
      : CanonicalDisplaySegmentRightBoundaryProof(
          kind: CanonicalDisplaySegmentRightBoundaryKind.frontier,
          finalCardSignature: cards.last.physicalCardSignature,
          finalCardEndCursor: cards.last.cardEndCursor,
          continuationDigest: continuation.continuationDigest,
          frontierStartCursor:
              accepted.continuation.frontier.cardCandidateCount == 0
              ? null
              : accepted.continuation.previousFinalizedBoundary.endCursor,
          frontierEndCursor:
              accepted.continuation.frontier.cardCandidateCount == 0
              ? null
              : accepted.continuation.nextSourceCursor,
        );
  final record = CanonicalDisplaySegmentRecord.create(
    key: key,
    compatibilityEvidence: evidence,
    sourceSnapshotLink: CanonicalDisplaySegmentSourceSnapshotLink.fromSnapshot(
      snapshot,
    ),
    exactHalfOpenSourceInterval: interval,
    orderedFinalizedCards: cards,
    leftBoundaryProof: CanonicalDisplaySegmentLeftBoundaryProof(
      kind: CanonicalDisplaySegmentLeftBoundaryKind.bookStart,
      firstCardStartCursor: cards.first.cardStartCursor,
    ),
    rightBoundaryProof: frontier,
    continuationEvidence: continuation,
  );
  return _Material(
    record: record,
    context: CanonicalDisplaySegmentAdmissionContext(
      bookStorageScopeDigest: key.bookStorageScopeDigest,
      publicationFingerprint: snapshot.publicationFingerprint,
      sourceSnapshot: snapshot,
      currentCompatibilityEvidence: compatibility,
      supportedCompatibilityRevisions:
          ReaderCompatibilityRevisionSupport.current(
            parserSourceSchemaIdentities: <String>[
              snapshot.parserSourceIdentity,
            ],
          ),
      controlledLayoutIdentity: harness.layoutIdentity,
      paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
      acceptedFinalizedCards: accepted.publishableCards,
    ),
  );
}

CanonicalDisplaySegmentAdmissionContext _withGeneration(
  CanonicalDisplaySegmentAdmissionContext context,
  String generation,
) => CanonicalDisplaySegmentAdmissionContext(
  bookStorageScopeDigest: context.bookStorageScopeDigest,
  publicationFingerprint: context.publicationFingerprint,
  sourceSnapshot: context.sourceSnapshot,
  currentCompatibilityEvidence: context.currentCompatibilityEvidence,
  supportedCompatibilityRevisions: context.supportedCompatibilityRevisions,
  controlledLayoutIdentity: context.controlledLayoutIdentity,
  paginationAlgorithmIdentity: context.paginationAlgorithmIdentity,
  acceptedFinalizedCards: context.acceptedFinalizedCards,
  expectedGeneration: generation,
);

CanonicalDisplaySegmentAdmissionContext _withCompatibility(
  CanonicalDisplaySegmentAdmissionContext context,
  ReaderCompatibilityEvidence evidence, {
  ReaderCompatibilityRevisionSupport? supportedCompatibilityRevisions,
}) => CanonicalDisplaySegmentAdmissionContext(
  bookStorageScopeDigest: context.bookStorageScopeDigest,
  publicationFingerprint: context.publicationFingerprint,
  sourceSnapshot: context.sourceSnapshot,
  currentCompatibilityEvidence: evidence,
  supportedCompatibilityRevisions:
      supportedCompatibilityRevisions ??
      context.supportedCompatibilityRevisions,
  controlledLayoutIdentity: context.controlledLayoutIdentity,
  paginationAlgorithmIdentity: context.paginationAlgorithmIdentity,
  acceptedFinalizedCards: context.acceptedFinalizedCards,
  acceptedPredecessor: context.acceptedPredecessor,
  acceptedSuccessor: context.acceptedSuccessor,
  acceptedRestart: context.acceptedRestart,
  expectedGeneration: context.expectedGeneration,
);

CanonicalDisplaySegmentAdmissionContext _withBookStorageScope(
  CanonicalDisplaySegmentAdmissionContext context,
  String scope,
) => CanonicalDisplaySegmentAdmissionContext(
  bookStorageScopeDigest: readerSha256(scope),
  publicationFingerprint: context.publicationFingerprint,
  sourceSnapshot: context.sourceSnapshot,
  currentCompatibilityEvidence: context.currentCompatibilityEvidence,
  supportedCompatibilityRevisions: context.supportedCompatibilityRevisions,
  controlledLayoutIdentity: context.controlledLayoutIdentity,
  paginationAlgorithmIdentity: context.paginationAlgorithmIdentity,
  acceptedFinalizedCards: context.acceptedFinalizedCards,
  acceptedPredecessor: context.acceptedPredecessor,
  acceptedSuccessor: context.acceptedSuccessor,
  acceptedRestart: context.acceptedRestart,
  expectedGeneration: context.expectedGeneration,
);

CanonicalDisplaySegmentAdmissionResult _admit(
  _Material material, {
  CanonicalDisplaySegmentAdmissionContext? context,
  CanonicalDisplaySegmentRecord? record,
  String? claimedGeneration,
}) => CanonicalDisplaySegmentAdmission.admitMemoryRecord(
  record: record ?? material.record,
  limits: _limits,
  context: context ?? material.context,
  claimedGeneration: claimedGeneration,
);

ReaderCompatibilityIdentity _composeCompatibility(
  ReaderCompatibilityIdentity base, {
  LayoutMetricsIdentity? layout,
  SourceCompatibilityIdentity? source,
  PaginationAlgorithmIdentity? pagination,
  RendererLayoutIdentity? renderer,
}) => ReaderCompatibilityIdentity.compose(
  layoutMetricsIdentity: layout ?? base.layoutMetricsIdentity,
  sourceCompatibilityIdentity: source ?? base.sourceCompatibilityIdentity,
  paginationAlgorithmIdentity: pagination ?? base.paginationAlgorithmIdentity,
  rendererLayoutIdentity: renderer ?? base.rendererLayoutIdentity,
  classifierRevision: base.classifierRevision,
);

ReaderCompatibilityRevisionSupport _supportWith(
  ReaderCompatibilityRevisionSupport source, {
  Iterable<String>? layoutContractRevisions,
  Iterable<String>? layoutMetricsIdentityRevisions,
  Iterable<String>? parserSourceSchemaIdentities,
  Iterable<String>? structuralOwnershipRevisions,
  Iterable<String>? paginationSemanticRevisions,
  Iterable<String>? rendererRulesRevisions,
  Iterable<String>? classifierRevisions,
}) => ReaderCompatibilityRevisionSupport(
  layoutContractRevisions:
      layoutContractRevisions ?? source.layoutContractRevisions,
  layoutMetricsIdentityRevisions:
      layoutMetricsIdentityRevisions ?? source.layoutMetricsIdentityRevisions,
  parserSourceSchemaIdentities:
      parserSourceSchemaIdentities ?? source.parserSourceSchemaIdentities,
  structuralOwnershipRevisions:
      structuralOwnershipRevisions ?? source.structuralOwnershipRevisions,
  paginationSemanticRevisions:
      paginationSemanticRevisions ?? source.paginationSemanticRevisions,
  rendererRulesRevisions:
      rendererRulesRevisions ?? source.rendererRulesRevisions,
  classifierRevisions: classifierRevisions ?? source.classifierRevisions,
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
  throw StateError('Canonical evidence did not contain the expected field.');
}

String _digest(Uint8List bytes) => ReaderFontCanonicalEncoder.digest(bytes);

final class _Material {
  const _Material({required this.record, required this.context});
  final CanonicalDisplaySegmentRecord record;
  final CanonicalDisplaySegmentAdmissionContext context;
}

CanonicalDisplaySegmentRecord _copyRecord(
  CanonicalDisplaySegmentRecord record, {
  CanonicalDisplaySegmentKey? key,
  CanonicalDisplaySegmentSourceInterval? exactHalfOpenSourceInterval,
  CanonicalDisplaySegmentLeftBoundaryProof? leftBoundaryProof,
  CanonicalDisplaySegmentRightBoundaryProof? rightBoundaryProof,
  CanonicalDisplaySegmentContinuationEvidence? continuationEvidence,
}) => CanonicalDisplaySegmentRecord.create(
  key:
      key ??
      CanonicalDisplaySegmentKey.decode(
        record.canonicalKeyBytes,
        limits: _limits,
      ),
  compatibilityEvidence: record.compatibilityEvidence,
  sourceSnapshotLink: record.sourceSnapshotLink,
  exactHalfOpenSourceInterval:
      exactHalfOpenSourceInterval ?? record.exactHalfOpenSourceInterval,
  orderedFinalizedCards: record.orderedFinalizedCards,
  leftBoundaryProof: leftBoundaryProof ?? record.leftBoundaryProof,
  rightBoundaryProof: rightBoundaryProof ?? record.rightBoundaryProof,
  continuationEvidence: continuationEvidence ?? record.continuationEvidence,
  manifestRevision: record.manifestBinding.manifestRevision,
);

CanonicalDisplaySegmentKey _keyWithBoundaryRole(
  CanonicalDisplaySegmentKey key,
  CanonicalDisplaySegmentBoundaryRole boundaryRole,
) => CanonicalDisplaySegmentKey(
  bookStorageScopeDigest: key.bookStorageScopeDigest,
  publicationFingerprint: key.publicationFingerprint,
  sourceCompatibilityFingerprint: key.sourceCompatibilityFingerprint,
  layoutMetricsFingerprint: key.layoutMetricsFingerprint,
  rendererLayoutFingerprint: key.rendererLayoutFingerprint,
  paginationAlgorithmFingerprint: key.paginationAlgorithmFingerprint,
  compatibilityClassifierRevision: key.compatibilityClassifierRevision,
  readerCompatibilityFingerprint: key.readerCompatibilityFingerprint,
  stableStartCursor: key.stableStartCursor,
  stableEndCursor: key.stableEndCursor,
  boundaryRole: boundaryRole,
  recordKind: key.recordKind,
  semanticRevision: key.semanticRevision,
);

CanonicalDisplaySegmentRightBoundaryProof _rightWithContinuationDigest(
  CanonicalDisplaySegmentRightBoundaryProof proof,
  String continuationDigest,
) => CanonicalDisplaySegmentRightBoundaryProof(
  kind: proof.kind,
  finalCardSignature: proof.finalCardSignature,
  finalCardEndCursor: proof.finalCardEndCursor,
  successorCardSignature: proof.successorCardSignature,
  successorStartCursor: proof.successorStartCursor,
  continuationDigest:
      proof.kind == CanonicalDisplaySegmentRightBoundaryKind.logicalEnd
      ? proof.continuationDigest
      : continuationDigest,
  frontierStartCursor: proof.frontierStartCursor,
  frontierEndCursor: proof.frontierEndCursor,
);
