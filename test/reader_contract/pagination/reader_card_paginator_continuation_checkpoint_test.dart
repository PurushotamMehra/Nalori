import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/canonical_pagination_checkpoint_index.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/utils/reader_content_parser.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  group('[TASK-P04-003] deterministic continuation codec', () {
    testWidgets('round trips byte-for-byte with identical digest and no text', (
      tester,
    ) async {
      final sources = <BookChunk>[
        _text(0, 'private sentinel source text'),
        _text(1, 'successor proof'),
      ];
      final harness = await _harness(tester, sources);
      final snapshot = _snapshot(sources, 'codec-r1');
      final first =
          await _run(
                harness,
                snapshot,
                budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
              )
              as CanonicalBudgetExhaustedWithFrontier;
      final encoding = first.continuation.canonicalEncoding;
      final decoded =
          CanonicalPaginationContinuationCodec.decode(encoding)
              as CanonicalPaginationContinuationAccepted;

      expect(decoded.continuation.canonicalEncoding, encoding);
      expect(
        decoded.continuation.integrityDigest,
        first.continuation.integrityDigest,
      );
      expect(decoded.continuation.copiedSourceTextUtf16, 0);
      expect(encoding, isNot(contains('private sentinel source text')));
      expect(encoding, isNot(contains('displayIndex')));
      expect(encoding, isNot(contains('windowIndex')));
      expect(encoding, isNot(contains('controllerIndex')));
    });

    testWidgets(
      'identical logical construction has identical bytes and digest',
      (tester) async {
        final sources = <BookChunk>[_text(0, 'alpha'), _text(1, 'beta')];
        final harness = await _harness(tester, sources);
        final snapshot = _snapshot(sources, 'same-r1');
        final first =
            await _run(
                  harness,
                  snapshot,
                  generation: 1,
                  budget: const CanonicalPaginationWorkBudget(
                    maxSourceChunks: 1,
                  ),
                )
                as CanonicalPaginationAcceptedResult;
        final second =
            await _run(
                  harness,
                  snapshot,
                  generation: 2,
                  budget: const CanonicalPaginationWorkBudget(
                    maxSourceChunks: 1,
                  ),
                )
                as CanonicalPaginationAcceptedResult;

        expect(
          second.continuation.canonicalEncoding,
          first.continuation.canonicalEncoding,
        );
        expect(
          second.continuation.integrityDigest,
          first.continuation.integrityDigest,
        );
      },
    );

    testWidgets('covered mutation, missing/unknown fields and kinds reject', (
      tester,
    ) async {
      final sources = <BookChunk>[_text(0, 'alpha'), _text(1, 'beta')];
      final harness = await _harness(tester, sources);
      final result =
          await _run(
                harness,
                _snapshot(sources, 'mutate-r1'),
                budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
              )
              as CanonicalPaginationAcceptedResult;
      final root = Map<String, Object?>.from(
        jsonDecode(result.continuation.canonicalEncoding) as Map,
      );

      for (final field in root.keys.where(
        (field) => field != 'integrityDigest',
      )) {
        final original = root[field];
        final mutated = Map<String, Object?>.from(root)
          ..[field] = switch (original) {
            final bool value => !value,
            final int value => value + 1,
            final String value => '$value-mutated',
            Map _ => <String, Object?>{},
            List _ => <Object?>[],
            null => 'present',
            _ => throw StateError('Unhandled canonical field type.'),
          };
        final rejected = CanonicalPaginationContinuationCodec.decode(
          canonicalJsonEncode(mutated),
        );
        expect(rejected, isA<CanonicalPaginationContinuationRejected>());
        if (field != 'contractKind') {
          expect(
            rejected.kind,
            CanonicalPaginationContinuationValidationKind.corruptDigest,
            reason: 'Every covered field must invalidate the digest: $field',
          );
        }
      }

      final missing = Map<String, Object?>.from(root)..remove('terminal');
      expect(
        CanonicalPaginationContinuationCodec.decode(
          canonicalJsonEncode(missing),
        ).kind,
        CanonicalPaginationContinuationValidationKind.invalidFrontier,
      );

      final unknown = Map<String, Object?>.from(root)..['displayIndex'] = 4;
      expect(
        CanonicalPaginationContinuationCodec.decode(
          canonicalJsonEncode(unknown),
        ).kind,
        CanonicalPaginationContinuationValidationKind.invalidFrontier,
      );

      final duplicate = result.continuation.canonicalEncoding.replaceFirst(
        '"terminal":false',
        '"terminal":false,"terminal":false',
      );
      expect(
        CanonicalPaginationContinuationCodec.decode(duplicate).kind,
        CanonicalPaginationContinuationValidationKind.invalidFrontier,
      );

      final kind = Map<String, Object?>.from(root)
        ..['contractKind'] = 'futureContinuationV99';
      expect(
        CanonicalPaginationContinuationCodec.decode(
          canonicalJsonEncode(kind),
        ).kind,
        CanonicalPaginationContinuationValidationKind.unsupportedContractKind,
      );
    });
  });

  group('[TASK-P04-003] compatibility and reconstruction', () {
    testWidgets(
      'publication, parser, pagination, and layout mismatches reject',
      (tester) async {
        final sources = <BookChunk>[_text(0, 'alpha'), _text(1, 'beta')];
        final harness = await _harness(tester, sources);
        final snapshot = _snapshot(sources, 'compat-r1');
        final root =
            (await _run(
                      harness,
                      snapshot,
                      budget: const CanonicalPaginationWorkBudget(
                        maxSourceChunks: 1,
                      ),
                    )
                    as CanonicalPaginationAcceptedResult)
                .continuation;

        Future<CanonicalPaginationRejectionReason> rejection(
          CanonicalPaginationContinuation continuation, {
          CanonicalPaginationSourceSnapshot? against,
        }) async =>
            (await _run(harness, against ?? snapshot, restart: continuation)
                    as CanonicalInvalidRestartSourceRejected)
                .reason;

        expect(
          await rejection(
            _copy(
              root,
              key: _copyKey(
                root.key,
                publicationFingerprint: 'another-publication',
              ),
            ),
          ),
          CanonicalPaginationRejectionReason.incompatiblePublication,
        );
        expect(
          await rejection(root, against: _snapshot(sources, 'compat-r2')),
          CanonicalPaginationRejectionReason.incompatibleParserSourceSnapshot,
        );
        expect(
          await rejection(
            _copy(
              root,
              key: _copyKey(
                root.key,
                paginationAlgorithmIdentity: 'other-pagination',
              ),
            ),
          ),
          CanonicalPaginationRejectionReason.incompatiblePaginationIdentity,
        );
        expect(
          await rejection(
            _copy(
              root,
              key: _copyKey(root.key, controlledLayoutIdentity: 'other-layout'),
            ),
          ),
          CanonicalPaginationRejectionReason.incompatibleLayout,
        );
      },
    );

    testWidgets('invalid owner/cursor and non-grapheme frontier reject', (
      tester,
    ) async {
      final sources = <BookChunk>[_text(0, '🚀alpha'), _text(1, 'beta')];
      final harness = await _harness(tester, sources);
      final snapshot = _snapshot(sources, 'cursor-r1');
      final root =
          (await _run(
                    harness,
                    snapshot,
                    budget: const CanonicalPaginationWorkBudget(
                      maxSourceChunks: 1,
                    ),
                  )
                  as CanonicalPaginationAcceptedResult)
              .continuation;

      final badCursor = CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.sourceText,
        sourceIdentity: 'missing-owner',
        sectionIdentity: root.nextSourceCursor.sectionIdentity,
        sourceOrdinalHint: root.nextSourceCursor.sourceOrdinalHint,
        textOffsetUtf16: 999,
      );
      final cursorRejected =
          await _run(
                harness,
                snapshot,
                restart: _copy(
                  root,
                  nextSourceCursor: badCursor,
                  key: _copyKey(root.key, boundaryCursor: badCursor),
                ),
              )
              as CanonicalInvalidRestartSourceRejected;
      expect(
        cursorRejected.reason,
        CanonicalPaginationRejectionReason.invalidCursorOffsetRowInterval,
      );
      _expectNoAuthority(cursorRejected);

      final slice = root.frontier.pendingTail!.sourceSlices.single;
      final wrongOwnerFrontier = CanonicalPaginationFrontier(
        pendingTail: CanonicalPaginationFrontierCandidate(
          sourceSlices: <CanonicalPaginationSourceSlice>[
            _copySlice(slice, sectionIdentity: 'another-section.xhtml'),
          ],
          reconstructedCardDigest:
              root.frontier.pendingTail!.reconstructedCardDigest,
        ),
      );
      final ownerRejected =
          await _run(
                harness,
                snapshot,
                restart: _copy(root, frontier: wrongOwnerFrontier),
              )
              as CanonicalInvalidRestartSourceRejected;
      expect(
        ownerRejected.reason,
        CanonicalPaginationRejectionReason.invalidSectionSourceOwner,
      );
      _expectNoAuthority(ownerRejected);

      final invalidSlice = _copySlice(slice, startUtf16: 1);
      final invalidFrontier = CanonicalPaginationFrontier(
        pendingTail: CanonicalPaginationFrontierCandidate(
          sourceSlices: <CanonicalPaginationSourceSlice>[invalidSlice],
          reconstructedCardDigest:
              root.frontier.pendingTail!.reconstructedCardDigest,
        ),
      );
      final boundary = CanonicalPaginationFinalizedBoundary(
        kind: CanonicalPaginationBoundaryKind.publicationStart,
        endCursor: CanonicalPaginationCursor(
          kind: CanonicalPaginationCursorKind.sourceText,
          sourceIdentity: slice.sourceIdentity,
          sectionIdentity: slice.sectionIdentity,
          sourceOrdinalHint: slice.sourceOrdinalHint,
          textOffsetUtf16: 1,
        ),
        cardIdentity: null,
      );
      final invalid = await _run(
        harness,
        snapshot,
        restart: _copy(
          root,
          frontier: invalidFrontier,
          previousBoundary: boundary,
        ),
      );
      expect(invalid, isA<CanonicalInvalidRestartSourceRejected>());
      _expectNoAuthority(invalid as CanonicalInvalidRestartSourceRejected);
    });

    testWidgets('invalid table-row boundary rejects exact reconstruction', (
      tester,
    ) async {
      final table = ReaderTableBlock(
        headers: const <String>['Column', 'Value'],
        rows: <List<String>>[
          for (var row = 0; row < 10; row++) <String>['row-$row', 'value-$row'],
        ],
      );
      final sources = <BookChunk>[
        BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: encodeReaderTableBlock(table),
          blockRole: BookBlockRole.table,
          sourceFile: 'table.xhtml',
          logicalParagraphId: 'table-owner',
        ),
      ];
      final harness = await _harness(tester, sources);
      final snapshot = _snapshot(sources, 'table-invalid-r1');
      final result =
          await _run(
                harness,
                snapshot,
                layout: _height(harness.paginatorLayout, 90),
                budget: const CanonicalPaginationWorkBudget(
                  maxAtomicFragments: 1,
                ),
              )
              as CanonicalBudgetExhaustedWithFrontier;
      final slice = result.frontier.pendingTail!.sourceSlices.single;
      final invalidFrontier = CanonicalPaginationFrontier(
        pendingTail: CanonicalPaginationFrontierCandidate(
          sourceSlices: <CanonicalPaginationSourceSlice>[
            _copySlice(slice, tableRowEndExclusive: 99),
          ],
          reconstructedCardDigest:
              result.frontier.pendingTail!.reconstructedCardDigest,
        ),
      );
      final rejected = await _run(
        harness,
        snapshot,
        layout: _height(harness.paginatorLayout, 90),
        restart: _copy(result.continuation, frontier: invalidFrontier),
      );
      expect(rejected, isA<CanonicalInvalidRestartSourceRejected>());
      _expectNoAuthority(rejected as CanonicalInvalidRestartSourceRejected);
    });

    testWidgets('frontier resumes through the production kernel exactly', (
      tester,
    ) async {
      final sources = <BookChunk>[
        _text(0, 'Merge alpha.'),
        _text(1, 'Merge beta.'),
        _text(2, 'Merge gamma.'),
      ];
      final harness = await _harness(tester, sources);
      final snapshot = _snapshot(sources, 'reconstruct-r1');
      final direct =
          await _run(harness, snapshot) as CanonicalLogicalEndReached;
      final first =
          await _run(
                harness,
                snapshot,
                budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
              )
              as CanonicalBudgetExhaustedWithFrontier;
      final resumed =
          await _run(harness, snapshot, restart: first.continuation)
              as CanonicalLogicalEndReached;

      expect(
        resumed.finalizedCards.map((card) => card.identity.signature),
        direct.finalizedCards.map((card) => card.identity.signature),
      );
      expect(
        resumed.finalizedCards.map((card) => card.card.toJson()),
        direct.finalizedCards.map((card) => card.card.toJson()),
      );
    });

    testWidgets('coalesced two-card frontier resumes exactly more than once', (
      tester,
    ) async {
      final sources = <BookChunk>[
        for (var index = 0; index < 32; index++)
          _text(
            index,
            'Synthetic bounded source ${index.toString().padLeft(3, '0')} '
            'contains deterministic test prose.',
          ),
      ];
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: sources,
      );
      final snapshot = _snapshot(sources, 'two-card-audit-r1');
      final first =
          await _run(
                harness,
                snapshot,
                budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 8),
              )
              as CanonicalBudgetExhaustedWithFrontier;
      expect(first.frontier.cardCandidateCount, 2);
      expect(first.frontier.structuralEntryCount, 5);
      expect(first.diagnostics.peakFrontierEntries, 6);
      expect(
        first.diagnostics.atomicFragmentsProcessed,
        lessThanOrEqualTo(110),
      );
      final decoded =
          CanonicalPaginationContinuationCodec.decode(
                first.continuation.canonicalEncoding,
              )
              as CanonicalPaginationContinuationAccepted;
      expect(
        decoded.continuation.canonicalEncoding,
        first.continuation.canonicalEncoding,
      );
      expect(decoded.continuation.copiedSourceTextUtf16, 0);

      final diagnostics = <Map<String, Object?>>[];
      CanonicalPaginationRestart restart = first.continuation;
      CanonicalPaginationContinuation? parent;
      var completedResumes = 0;
      for (var operation = 1; operation < 10; operation++) {
        final result = await _run(
          harness,
          snapshot,
          restart: restart,
          continuationParent: parent,
          generation: 70 + operation,
          budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 8),
          onDiagnostic: (phase, fields) {
            if (phase == 'canonical_frontier_reconstruction_mismatch') {
              diagnostics.add(fields);
            }
          },
        );
        final accepted = result as CanonicalPaginationAcceptedResult;
        expect(
          accepted.diagnostics.atomicFragmentsProcessed,
          lessThanOrEqualTo(110),
        );
        expect(accepted.continuation.copiedSourceTextUtf16, 0);
        completedResumes++;
        if (result is CanonicalLogicalEndReached) break;
        parent = restart as CanonicalPaginationContinuation;
        restart = accepted.continuation;
      }

      expect(completedResumes, greaterThanOrEqualTo(2));
      expect(diagnostics, isEmpty);
    });
  });

  group('[TASK-P04-003] chain, cadence, and bounded index', () {
    testWidgets('parent/ordinal accept; missing, gap, and stale fork reject', (
      tester,
    ) async {
      final sources = <BookChunk>[
        _text(0, 'alpha'),
        _text(1, 'beta'),
        _text(2, 'gamma'),
        _text(3, 'delta'),
      ];
      final harness = await _harness(tester, sources);
      final snapshot = _snapshot(sources, 'chain-r1');
      final first =
          await _run(
                harness,
                snapshot,
                budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
              )
              as CanonicalPaginationAcceptedResult;
      final second =
          await _run(
                harness,
                snapshot,
                restart: first.continuation,
                budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
              )
              as CanonicalPaginationAcceptedResult;
      expect(
        second.continuation.parentDigest,
        first.continuation.integrityDigest,
      );
      expect(second.continuation.chainOrdinal, 1);

      final accepted = await _run(
        harness,
        snapshot,
        restart: second.continuation,
        continuationParent: first.continuation,
        budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
      );
      expect(accepted, isA<CanonicalPaginationAcceptedResult>());

      final missingParent =
          await _run(harness, snapshot, restart: second.continuation)
              as CanonicalInvalidRestartSourceRejected;
      expect(
        missingParent.reason,
        CanonicalPaginationRejectionReason.brokenParentChain,
      );

      final alternateRoot =
          await _run(
                harness,
                snapshot,
                budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 2),
              )
              as CanonicalPaginationAcceptedResult;
      final wrongParent =
          await _run(
                harness,
                snapshot,
                restart: second.continuation,
                continuationParent: alternateRoot.continuation,
              )
              as CanonicalInvalidRestartSourceRejected;
      expect(
        wrongParent.reason,
        CanonicalPaginationRejectionReason.brokenParentChain,
      );

      final gap = _copy(second.continuation, chainOrdinal: 3);
      final ordinalRejected =
          await _run(
                harness,
                snapshot,
                restart: gap,
                continuationParent: first.continuation,
              )
              as CanonicalInvalidRestartSourceRejected;
      expect(
        ordinalRejected.reason,
        CanonicalPaginationRejectionReason.ordinalMismatch,
      );

      final index = _index(snapshot, harness);
      expect(
        index.insert(first).kind,
        CanonicalPaginationContinuationValidationKind.accepted,
      );
      expect(
        index.insert(second).kind,
        CanonicalPaginationContinuationValidationKind.accepted,
      );
      final fork = _acceptedWith(
        _copy(
          second.continuation,
          checkpointReason: CanonicalPaginationCheckpointReason.targetSatisfied,
        ),
      );
      expect(
        index.insert(fork).kind,
        CanonicalPaginationContinuationValidationKind.staleForkReplay,
      );
    });

    testWidgets(
      'publication and section roots plus boundary/terminal records',
      (tester) async {
        final sources = <BookChunk>[
          _text(0, 'first').copyWith(sourceFile: 'one.xhtml'),
          _text(1, 'second').copyWith(sourceFile: 'two.xhtml'),
        ];
        final harness = await _harness(tester, sources);
        final snapshot = _snapshot(sources, 'section-r1');
        final publication =
            await _run(harness, snapshot) as CanonicalFinalizedOutputAvailable;
        expect(publication.continuation.chainOrdinal, 0);
        expect(publication.continuation.parentDigest, isNull);
        expect(
          publication.continuation.checkpointReason,
          CanonicalPaginationCheckpointReason.sectionBoundary,
        );

        final owner = snapshot.ownerAt(1);
        final section =
            await _run(
                  harness,
                  snapshot,
                  restart: CanonicalPaginationTrustedSectionStart(
                    sectionIdentity: owner.sectionIdentity,
                    sourceIdentity: owner.sourceIdentity,
                    sourceOrdinalHint: 1,
                  ),
                )
                as CanonicalLogicalEndReached;
        expect(section.continuation.chainOrdinal, 0);
        expect(section.continuation.terminal, isTrue);
        expect(
          section.continuation.checkpointReason,
          CanonicalPaginationCheckpointReason.terminalBookEnd,
        );
      },
    );

    testWidgets(
      '48 sources, eight cards, request exhaustion, and repeat chain',
      (tester) async {
        final emptySources = <BookChunk>[
          for (var index = 0; index < 50; index++) _text(index, ''),
        ];
        final emptyHarness = await _harness(tester, emptySources);
        final emptySnapshot = _snapshot(emptySources, 'source-cadence-r1');
        final emptyEvidence = emptyHarness
            .paginatorLayout
            .fontEvidenceResolver!(emptySources.first, '');
        expect(emptyHarness.bootstrapFontEvidence.observations, isEmpty);
        expect(
          emptyHarness.bootstrapFontEvidence.isExplicitlyEmptyRepertoire,
          isTrue,
        );
        expect(emptyEvidence, hasLength(1));
        expect(emptyEvidence.single.observations, isEmpty);
        expect(emptyEvidence.single.isExplicitlyEmptyRepertoire, isTrue);
        expect(
          emptySnapshot.owners
              .take(48)
              .map((owner) => owner.sourceIdentity)
              .toSet(),
          hasLength(48),
        );
        final sourceCadence =
            await _run(
                  emptyHarness,
                  emptySnapshot,
                  budget: const CanonicalPaginationWorkBudget(
                    maxSourceChunks: 96,
                    maxFinalizedCards: 96,
                  ),
                )
                as CanonicalBudgetExhaustedWithFrontier;
        expect(sourceCadence.finalizedCards, isEmpty);
        expect(sourceCadence.diagnostics.sourceChunksEntered, 48);
        expect(sourceCadence.diagnostics.sourceChunksFullyConsumed, 48);
        expect(sourceCadence.diagnostics.atomicFragmentsProcessed, 0);
        expect(sourceCadence.diagnostics.cardsFinalized, 0);
        expect(sourceCadence.continuation.frontier.cardCandidateCount, 0);
        expect(
          sourceCadence.continuation.nextSourceCursor.sourceOrdinalHint,
          48,
        );
        expect(sourceCadence.continuation.copiedSourceTextUtf16, 0);
        expect(sourceCadence.continuation.sourcesSinceCheckpoint, 48);
        expect(
          sourceCadence.continuation.checkpointReason,
          CanonicalPaginationCheckpointReason.sourceCadence,
        );

        final longSource = <BookChunk>[
          _text(0, List<String>.filled(500, 'unbrokenword').join()),
        ];
        final longHarness = await _harness(tester, longSource);
        final cardCadence =
            await _run(
                  longHarness,
                  _snapshot(longSource, 'card-cadence-r1'),
                  layout: _height(longHarness.paginatorLayout, 35),
                )
                as CanonicalBudgetExhaustedWithFrontier;
        expect(cardCadence.continuation.cardsSinceCheckpoint, 8);
        expect(
          cardCadence.continuation.checkpointReason,
          CanonicalPaginationCheckpointReason.cardCadence,
        );

        final requestSources = <BookChunk>[_text(0, 'alpha'), _text(1, 'beta')];
        final requestHarness = await _harness(tester, requestSources);
        final requestSnapshot = _snapshot(requestSources, 'request-r1');
        final request =
            await _run(
                  requestHarness,
                  requestSnapshot,
                  budget: const CanonicalPaginationWorkBudget(
                    maxSourceChunks: 1,
                  ),
                )
                as CanonicalBudgetExhaustedWithFrontier;
        expect(request.continuation.terminal, isFalse);
        expect(
          request.continuation.checkpointReason,
          CanonicalPaginationCheckpointReason.requestExhaustedProvisional,
        );

        final firstChain = await _chainEncodings(
          requestHarness,
          requestSnapshot,
        );
        final secondChain = await _chainEncodings(
          requestHarness,
          requestSnapshot,
        );
        expect(secondChain, firstChain);

        final mixedSources = <BookChunk>[
          _text(0, ''),
          _text(1, 'alpha'),
          _text(2, ''),
          _text(3, 'beta'),
          _text(4, ''),
        ];
        final mixedHarness = await _harness(tester, mixedSources);
        final mixed =
            await _run(mixedHarness, _snapshot(mixedSources, 'mixed-empty-r1'))
                as CanonicalLogicalEndReached;
        expect(
          <int>[
            for (final card in mixed.finalizedCards)
              for (final slice in card.sourceSlices) slice.sourceOrdinalHint,
          ],
          <int>[1, 3],
        );
        expect(mixed.diagnostics.sourceChunksFullyConsumed, 5);
        expect(mixed.continuation.nextSourceCursor.isLogicalEnd, isTrue);
      },
    );

    testWidgets('index deduplicates, orders, bounds 25, and preserves guards', (
      tester,
    ) async {
      final sources = <BookChunk>[
        for (var index = 0; index < 31; index++)
          _text(
            index,
            '',
          ).copyWith(sourceFile: index < 10 ? 'one.xhtml' : 'two.xhtml'),
      ];
      final harness = await _harness(tester, sources);
      final snapshot = _snapshot(sources, 'index-r1');
      final index = _index(snapshot, harness);
      CanonicalPaginationRestart restart =
          const CanonicalPaginationPublicationStart();
      CanonicalPaginationContinuation? parent;
      String? firstDigest;
      String? sectionBoundaryDigest;
      CanonicalPaginationAcceptedResult? first;
      CanonicalPaginationAcceptedResult? last;
      for (var operation = 0; operation < sources.length; operation++) {
        final result =
            await _run(
                  harness,
                  snapshot,
                  restart: restart,
                  continuationParent: parent,
                  generation: 800 + operation,
                  budget: const CanonicalPaginationWorkBudget(
                    maxSourceChunks: 1,
                  ),
                )
                as CanonicalPaginationAcceptedResult;
        expect(
          index.insert(result).kind,
          CanonicalPaginationContinuationValidationKind.accepted,
        );
        firstDigest ??= result.continuation.integrityDigest;
        if (result.continuation.checkpointReason ==
            CanonicalPaginationCheckpointReason.sectionBoundary) {
          sectionBoundaryDigest = result.continuation.integrityDigest;
        }
        first ??= result;
        last = result;
        parent = restart is CanonicalPaginationContinuation ? restart : null;
        restart = result.continuation;
      }

      expect(index.records.length, 25);
      expect(
        index.activeFrontier!.integrityDigest,
        last!.continuation.integrityDigest,
      );
      expect(
        index.requireDigest(firstDigest!).kind,
        CanonicalPaginationContinuationValidationKind.accepted,
      );
      expect(sectionBoundaryDigest, isNotNull);
      expect(
        index.requireDigest(sectionBoundaryDigest!).kind,
        CanonicalPaginationContinuationValidationKind.accepted,
      );
      expect(
        index.insert(first!).kind,
        CanonicalPaginationContinuationValidationKind.staleForkReplay,
      );
      expect(
        index.requireDigest(parent!.integrityDigest).kind,
        CanonicalPaginationContinuationValidationKind.accepted,
      );
      final beforeDedup = index.records.length;
      expect(
        index.insert(last).kind,
        CanonicalPaginationContinuationValidationKind.accepted,
      );
      expect(index.records.length, beforeDedup);
      expect(index.records.last.nextSourceCursor.isLogicalEnd, isTrue);
      for (var position = 1; position < index.records.length - 1; position++) {
        expect(
          index.records[position - 1].key.boundaryCursor.sourceOrdinalHint,
          lessThanOrEqualTo(
            index.records[position].key.boundaryCursor.sourceOrdinalHint,
          ),
        );
      }
      expect(
        index.requireDigest('missing').kind,
        CanonicalPaginationContinuationValidationKind.requiredEarlierRestart,
      );
    });

    testWidgets(
      'cancelled and stale operations expose no continuation authority',
      (tester) async {
        final sources = <BookChunk>[_text(0, 'alpha')];
        final harness = await _harness(tester, sources);
        final snapshot = _snapshot(sources, 'stale-r1');
        final cancelled =
            await _run(harness, snapshot, isCancelled: () => true)
                as CanonicalCancelledStaleRejected;
        _expectNoAuthority(cancelled);
        final stale =
            await _run(
                  harness,
                  snapshot,
                  generation: 1,
                  currentGeneration: () => 2,
                )
                as CanonicalCancelledStaleRejected;
        _expectNoAuthority(stale);
      },
    );
  });
}

Future<ReaderCorePaginationHarness> _harness(
  WidgetTester tester,
  List<BookChunk> sources,
) => ReaderCorePaginationHarness.install(
  tester: tester,
  sourceChunks: sources,
  layout: ReaderCorePaginationLayout.splitStress,
);

CanonicalPaginationSourceSnapshot _snapshot(
  List<BookChunk> sources,
  String revision,
) => CanonicalPaginationSourceSnapshot.pin(
  bookId: readerCoreFixtureId,
  publicationFingerprint: readerCoreFixtureId,
  parserSourceIdentity: 'reader-core-parser-v1',
  sourceRevision: revision,
  sourceChunks: sources,
  sourceKeys: <CanonicalPaginationSourceKey>[
    for (var index = 0; index < sources.length; index++)
      CanonicalPaginationSourceKey(
        sourceIdentity: '${sources[index].sourceFile}#stable-$index',
        sectionIdentity: sources[index].sourceFile!,
        spineIdentity: sources[index].sourceFile!,
        sourceOrdinalHint: index,
      ),
  ],
);

Future<CanonicalPaginationResult> _run(
  ReaderCorePaginationHarness harness,
  CanonicalPaginationSourceSnapshot snapshot, {
  CanonicalPaginationRestart restart =
      const CanonicalPaginationPublicationStart(),
  CanonicalPaginationContinuation? continuationParent,
  CanonicalPaginationWorkBudget budget = const CanonicalPaginationWorkBudget(
    maxFinalizedCards: 96,
  ),
  ReaderCardPaginatorLayout? layout,
  int generation = 70,
  int Function()? currentGeneration,
  bool Function()? isCancelled,
  ReaderCardPaginatorDiagnostic? onDiagnostic,
}) {
  final actualLayout = layout ?? harness.paginatorLayout;
  return const ReaderCardPaginator().paginateCanonical(
    CanonicalPaginationRequest(
      bookId: readerCoreFixtureId,
      publicationFingerprint: readerCoreFixtureId,
      sourceSnapshot: snapshot,
      controlledLayoutIdentity: _layoutIdentity,
      layout: actualLayout,
      restart: restart,
      continuationParent: continuationParent,
      workBudget: budget,
      operation: CanonicalPaginationOperationControls(
        generationToken: generation,
        currentGenerationToken: currentGeneration,
        scheduler: harness.scheduler,
        priority: DisplayRangeTaskPriority.directTarget,
        isCancelled: isCancelled ?? _neverCancelled,
        onDiagnostic: onDiagnostic,
      ),
    ),
  );
}

const _layoutIdentity = 'p04-continuation-controlled-layout';

CanonicalPaginationCheckpointIndex _index(
  CanonicalPaginationSourceSnapshot snapshot,
  ReaderCorePaginationHarness harness,
) => CanonicalPaginationCheckpointIndex(
  bookId: readerCoreFixtureId,
  publicationFingerprint: readerCoreFixtureId,
  parserSourceIdentity: snapshot.parserSourceIdentity,
  sourceRevision: snapshot.sourceRevision,
  sourceSnapshotDigest: snapshot.snapshotDigest,
  paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
  controlledLayoutIdentity: _layoutIdentity,
);

Future<List<String>> _chainEncodings(
  ReaderCorePaginationHarness harness,
  CanonicalPaginationSourceSnapshot snapshot,
) async {
  final encodings = <String>[];
  CanonicalPaginationRestart restart =
      const CanonicalPaginationPublicationStart();
  CanonicalPaginationContinuation? parent;
  for (var operation = 0; operation < 8; operation++) {
    final result = await _run(
      harness,
      snapshot,
      restart: restart,
      continuationParent: parent,
      generation: 900 + operation,
      budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
    );
    final accepted = result as CanonicalPaginationAcceptedResult;
    encodings.add(accepted.continuation.canonicalEncoding);
    if (result is CanonicalLogicalEndReached) break;
    parent = restart is CanonicalPaginationContinuation ? restart : null;
    restart = accepted.continuation;
  }
  return encodings;
}

CanonicalPaginationContinuation _copy(
  CanonicalPaginationContinuation source, {
  CanonicalPaginationContinuationKey? key,
  CanonicalPaginationCursor? nextSourceCursor,
  CanonicalPaginationFrontier? frontier,
  CanonicalPaginationFinalizedBoundary? previousBoundary,
  int? chainOrdinal,
  CanonicalPaginationCheckpointReason? checkpointReason,
}) => CanonicalPaginationContinuation.create(
  key: key ?? source.key,
  startSourceCursor: source.startSourceCursor,
  nextSourceCursor: nextSourceCursor ?? source.nextSourceCursor,
  frontier: frontier ?? source.frontier,
  previousFinalizedBoundary:
      previousBoundary ?? source.previousFinalizedBoundary,
  chainOrdinal: chainOrdinal ?? source.chainOrdinal,
  parentDigest: source.parentDigest,
  checkpointReason: checkpointReason ?? source.checkpointReason,
  sourcesSinceCheckpoint: source.sourcesSinceCheckpoint,
  cardsSinceCheckpoint: source.cardsSinceCheckpoint,
  terminal: source.terminal,
);

CanonicalPaginationContinuationKey _copyKey(
  CanonicalPaginationContinuationKey source, {
  String? publicationFingerprint,
  String? paginationAlgorithmIdentity,
  String? controlledLayoutIdentity,
  CanonicalPaginationCursor? boundaryCursor,
}) => CanonicalPaginationContinuationKey(
  bookId: source.bookId,
  publicationFingerprint:
      publicationFingerprint ?? source.publicationFingerprint,
  parserSourceIdentity: source.parserSourceIdentity,
  sourceRevision: source.sourceRevision,
  sourceSnapshotDigest: source.sourceSnapshotDigest,
  paginationAlgorithmIdentity:
      paginationAlgorithmIdentity ?? source.paginationAlgorithmIdentity,
  controlledLayoutIdentity:
      controlledLayoutIdentity ?? source.controlledLayoutIdentity,
  sectionIdentity: source.sectionIdentity,
  boundaryCursor: boundaryCursor ?? source.boundaryCursor,
);

CanonicalPaginationSourceSlice _copySlice(
  CanonicalPaginationSourceSlice source, {
  String? sectionIdentity,
  int? startUtf16,
  int? tableRowEndExclusive,
}) => CanonicalPaginationSourceSlice(
  sourceIdentity: source.sourceIdentity,
  sectionIdentity: sectionIdentity ?? source.sectionIdentity,
  spineIdentity: source.spineIdentity,
  sourceOrdinalHint: source.sourceOrdinalHint,
  sourceDigest: source.sourceDigest,
  structuralType: source.structuralType,
  structuralOwnerRole: source.structuralOwnerRole,
  logicalOwnerIdentity: source.logicalOwnerIdentity,
  structuralDigest: source.structuralDigest,
  fragmentDigest: source.fragmentDigest,
  publisherLayoutDigest: source.publisherLayoutDigest,
  richMetadataDigest: source.richMetadataDigest,
  listFragmentDigest: source.listFragmentDigest,
  splitBoundaryKind: source.splitBoundaryKind,
  isLogicalParagraphStart: source.isLogicalParagraphStart,
  isLogicalParagraphEnd: source.isLogicalParagraphEnd,
  usesExplicitTextFragment: source.usesExplicitTextFragment,
  startUtf16: startUtf16 ?? source.startUtf16,
  endUtf16: source.endUtf16,
  tableRowStart: source.tableRowStart,
  tableRowEndExclusive: tableRowEndExclusive ?? source.tableRowEndExclusive,
);

CanonicalFinalizedOutputAvailable _acceptedWith(
  CanonicalPaginationContinuation continuation,
) => CanonicalFinalizedOutputAvailable(
  diagnostics: const CanonicalPaginationWorkDiagnostics(),
  finalizedCards: const <CanonicalFinalizedReaderCard>[],
  continuation: continuation,
);

ReaderCardPaginatorLayout _height(
  ReaderCardPaginatorLayout source,
  double height,
) => ReaderCardPaginatorLayout(
  availableWidth: source.availableWidth,
  pageHeightBudget: height,
  physicalTextBudget: height,
  minUsefulHeight: 1,
  tinyWordCount: 1,
  tinyHeightRatio: 0.01,
  settings: source.settings,
  bodyStyle: source.bodyStyle,
  headingStyle: source.headingStyle,
  bodyStrut: source.bodyStrut,
  headingStrut: source.headingStrut,
  textScaler: source.textScaler,
);

void _expectNoAuthority(CanonicalPaginationRejectedResult result) {
  expect(result.publishableCards, isEmpty);
  expect(result.hasAcceptedRestartAuthority, isFalse);
  expect(result.hasCacheWriteAuthority, isFalse);
}

bool _neverCancelled() => false;

BookChunk _text(int index, String text) => BookChunk(
  index: index,
  type: BookChunkType.text,
  text: text,
  sourceFile: 'chapter.xhtml',
  logicalParagraphId: 'paragraph-$index',
  logicalParagraphEndOffset: text.length,
);
