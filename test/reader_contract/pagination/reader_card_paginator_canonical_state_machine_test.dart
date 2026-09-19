import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/book_list_semantics.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/utils/reader_content_parser.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load(
      'nalori_p04_canonical_paginator_',
    );
  });

  tearDownAll(() => fixture.close());

  group('[TASK-P04-002] immutable request and typed outcomes', () {
    testWidgets(
      'pinned source records survive caller list replacement and nested mutation',
      (tester) async {
        final links = <LinkMetadata>[
          const LinkMetadata(start: 0, end: 4, url: 'https://pinned.example'),
        ];
        final callerSources = <BookChunk>[
          _text(0, 'same pinned text', links: links),
          _text(1, 'successor proof'),
        ];
        final snapshot = _snapshot(callerSources, revision: 'immutable-r1');

        callerSources[0] = _text(0, 'replacement text');
        links[0] = const LinkMetadata(
          start: 0,
          end: 4,
          url: 'https://mutated.example',
        );

        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: callerSources,
        );
        final result = await _run(harness, snapshot: snapshot);

        expect(result, isA<CanonicalLogicalEndReached>());
        final cards = (result as CanonicalLogicalEndReached).finalizedCards;
        expect(
          cards.map((card) => card.card.text).join('\n'),
          contains('same pinned text'),
        );
        expect(
          cards.map((card) => card.card.text).join('\n'),
          isNot(contains('replacement text')),
        );
        expect(cards.first.card.links!.single.url, 'https://pinned.example');
        expect(
          snapshot.resolveOrdinalSource(0).links!.single.url,
          'https://pinned.example',
        );
      },
    );

    testWidgets(
      'restart source revision/digest mismatch is rejected without authority',
      (tester) async {
        final sources = <BookChunk>[
          _text(0, 'first source'),
          _text(1, 'second source'),
        ];
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final firstSnapshot = _snapshot(sources, revision: 'digest-r1');
        final exhausted = await _run(
          harness,
          snapshot: firstSnapshot,
          budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
        );
        expect(exhausted, isA<CanonicalBudgetExhaustedWithFrontier>());

        final secondSnapshot = _snapshot(sources, revision: 'digest-r2');
        final rejected = await _run(
          harness,
          snapshot: secondSnapshot,
          restart: (exhausted as CanonicalBudgetExhaustedWithFrontier).restart,
        );

        expect(rejected, isA<CanonicalInvalidRestartSourceRejected>());
        final typed = rejected as CanonicalInvalidRestartSourceRejected;
        expect(
          typed.reason,
          CanonicalPaginationRejectionReason.incompatibleParserSourceSnapshot,
        );
        _expectNoAuthority(typed);
      },
    );

    testWidgets(
      'repeated visible text retains two stable owners and no display authority',
      (tester) async {
        final sources = <BookChunk>[
          _text(0, 'repeated owner text'),
          _text(1, 'repeated owner text'),
        ];
        final snapshot = _snapshot(sources, revision: 'repeat-r1');
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final result = await _run(harness, snapshot: snapshot);

        final slices = (result as CanonicalLogicalEndReached).finalizedCards
            .expand((card) => card.sourceSlices)
            .toList();
        expect(
          slices.map((slice) => slice.sourceIdentity).toSet(),
          hasLength(2),
        );
        expect(slices.map((slice) => slice.sourceOrdinalHint), <int>[0, 1]);
        expect(
          snapshot.resolveOrdinalSource(0).text,
          snapshot.resolveOrdinalSource(1).text,
        );
      },
    );

    testWidgets(
      'request budget is not logical end and carries identity-free frontier',
      (tester) async {
        final sources = <BookChunk>[
          _text(0, 'first pending source'),
          _text(1, 'second source supplies proof'),
        ];
        final snapshot = _snapshot(sources, revision: 'request-end-r1');
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final first = await _run(
          harness,
          snapshot: snapshot,
          budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 1),
        );

        expect(first, isA<CanonicalBudgetExhaustedWithFrontier>());
        final exhausted = first as CanonicalBudgetExhaustedWithFrontier;
        expect(exhausted.finalizedCards, isEmpty);
        expect(exhausted.frontier.cardCandidateCount, 1);
        expect(exhausted.frontier.pendingTail!.sourceSlices, isNotEmpty);
        expect(exhausted.nextSourceCursor.isLogicalEnd, isFalse);

        final resumed = await _run(
          harness,
          snapshot: snapshot,
          restart: exhausted.restart,
        );
        expect(resumed, isA<CanonicalLogicalEndReached>());
        expect(
          (resumed as CanonicalLogicalEndReached).finalizedCards.every(
            (card) => card.identity.signature.isNotEmpty,
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'finalized prefix and provisional frontier are typed separately',
      (tester) async {
        final sources = <BookChunk>[
          _heading(0, 'Hard heading'),
          _text(1, 'pending body'),
          _text(2, 'later body'),
        ];
        final snapshot = _snapshot(sources, revision: 'prefix-r1');
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final result = await _run(
          harness,
          snapshot: snapshot,
          budget: const CanonicalPaginationWorkBudget(maxSourceChunks: 2),
        );

        final exhausted = result as CanonicalBudgetExhaustedWithFrontier;
        expect(exhausted.finalizedCards, hasLength(1));
        expect(exhausted.finalizedCards.single.card.isHeading, isTrue);
        expect(exhausted.finalizedCards.single.identity.signature, isNotEmpty);
        expect(exhausted.frontier.pendingTail, isNotNull);
        expect(exhausted.frontier.cardCandidateCount, lessThanOrEqualTo(2));
      },
    );

    testWidgets('stable target returns the target-finalized outcome', (
      tester,
    ) async {
      final sources = <BookChunk>[
        _heading(0, 'Heading proof'),
        _text(1, 'target source'),
        _heading(2, 'Following boundary'),
      ];
      final snapshot = _snapshot(sources, revision: 'target-r1');
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: sources,
      );
      final owner = snapshot.ownerAt(1);
      final result = await _run(
        harness,
        snapshot: snapshot,
        target: CanonicalPaginationTargetCursor(
          sourceIdentity: owner.sourceIdentity,
          sectionIdentity: owner.sectionIdentity,
          sourceOrdinalHint: 1,
          textOffsetUtf16: 2,
        ),
      );

      expect(result, isA<CanonicalTargetFinalized>());
      expect(
        (result as CanonicalTargetFinalized)
            .targetCard
            .sourceSlices
            .single
            .sourceIdentity,
        owner.sourceIdentity,
      );
    });

    testWidgets('trusted section start is stable restart authority', (
      tester,
    ) async {
      final sources = <BookChunk>[
        _heading(0, 'First section'),
        _text(1, 'first section body'),
        _heading(2, 'Second section').copyWith(sourceFile: 'second.xhtml'),
        _text(3, 'second section body').copyWith(sourceFile: 'second.xhtml'),
      ];
      final snapshot = _snapshot(sources, revision: 'section-start-r1');
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: sources,
      );
      final owner = snapshot.ownerAt(2);
      final result = await _run(
        harness,
        snapshot: snapshot,
        restart: CanonicalPaginationTrustedSectionStart(
          sectionIdentity: owner.sectionIdentity,
          sourceIdentity: owner.sourceIdentity,
          sourceOrdinalHint: 2,
        ),
      );

      final logicalEnd = result as CanonicalLogicalEndReached;
      expect(
        logicalEnd.finalizedCards
            .expand((card) => card.sourceSlices)
            .map((slice) => slice.sourceOrdinalHint),
        everyElement(greaterThanOrEqualTo(2)),
      );
    });
  });

  group('[TASK-P04-002] two-card frontier transitions', () {
    testWidgets(
      'direct compatible merge and hard boundary finalize deterministically',
      (tester) async {
        final sources = <BookChunk>[
          _text(0, 'Merge alpha.'),
          _text(1, 'Merge beta.'),
          _heading(2, 'Hard boundary'),
        ];
        final transitions = <String>[];
        final snapshot = _snapshot(sources, revision: 'merge-hard-r1');
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final result = await _run(
          harness,
          snapshot: snapshot,
          onDiagnostic: (phase, fields) {
            if (phase == 'canonical_frontier_transition') {
              transitions.add(fields['transition']! as String);
            }
          },
        );

        final cards = (result as CanonicalLogicalEndReached).finalizedCards;
        expect(cards.first.card.text, 'Merge alpha.\n\nMerge beta.');
        expect(cards.last.card.isHeading, isTrue);
        expect(transitions, contains('direct_compatible_merge'));
        expect(transitions, contains('hard_structural_boundary'));
      },
    );

    testWidgets('measured merge failure retains at most two candidates', (
      tester,
    ) async {
      final sources = <BookChunk>[
        _text(
          0,
          'First measured card has enough words to occupy its own line.',
        ),
        _text(1, 'Second measured card also occupies a separate bounded line.'),
      ];
      final transitions = <String>[];
      final snapshot = _snapshot(sources, revision: 'measured-r1');
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: sources,
        layout: ReaderCorePaginationLayout.splitStress,
      );
      final result = await _run(
        harness,
        snapshot: snapshot,
        budget: const CanonicalPaginationWorkBudget(
          maxSourceChunks: 2,
          maxAtomicFragments: 2,
        ),
        onDiagnostic: (phase, fields) {
          if (phase == 'canonical_frontier_transition') {
            transitions.add(fields['transition']! as String);
          }
        },
      );

      expect(result.diagnostics.peakFrontierEntries, lessThanOrEqualTo(7));
      expect(transitions, contains('measured_merge_failure'));
      if (result is CanonicalBudgetExhaustedWithFrontier) {
        expect(result.frontier.cardCandidateCount, lessThanOrEqualTo(2));
      }
    });

    testWidgets('tiny publisher tail attaches backward at trusted end', (
      tester,
    ) async {
      final sources = <BookChunk>[
        _publisher(0, 'A stable publisher predecessor with several words.'),
        _publisher(1, 'Tiny', dialogue: true),
      ];
      final transitions = <String>[];
      final snapshot = _snapshot(sources, revision: 'tiny-attach-r1');
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: sources,
      );
      final result = await _run(
        harness,
        snapshot: snapshot,
        onDiagnostic: (phase, fields) {
          if (phase == 'canonical_frontier_transition') {
            transitions.add(fields['transition']! as String);
          }
        },
      );

      final cards = (result as CanonicalLogicalEndReached).finalizedCards;
      expect(cards, hasLength(1));
      expect(cards.single.sourceSlices, hasLength(2));
      expect(transitions, contains('measured_merge_failure'));
      expect(transitions, contains('tiny_tail_backward_attachment'));
    });

    testWidgets(
      'tiny tail growth releases predecessor when attachment becomes impossible',
      (tester) async {
        final sources = <BookChunk>[
          _publisher(0, 'Publisher predecessor words.'),
          _publisher(1, 'Tiny', dialogue: true),
          _publisher(2, 'Y', dialogue: true),
        ];
        final transitions = <String>[];
        final snapshot = _snapshot(sources, revision: 'tiny-grow-r1');
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        final result = await _run(
          harness,
          snapshot: snapshot,
          layout: _layoutWithBudgets(harness.paginatorLayout, 72),
          onDiagnostic: (phase, fields) {
            if (phase == 'canonical_frontier_transition') {
              transitions.add(fields['transition']! as String);
            }
          },
        );

        expect(result, isA<CanonicalLogicalEndReached>());
        expect(transitions, contains('measured_merge_failure'));
        expect(
          transitions,
          anyOf(
            contains('tiny_tail_attachment_became_impossible'),
            contains('tiny_tail_backward_attachment'),
          ),
        );
        expect(result.diagnostics.peakFrontierEntries, lessThanOrEqualTo(7));
      },
    );

    testWidgets(
      'sentence rebalance runs while publisher and list candidates are excluded',
      (tester) async {
        final prose = <BookChunk>[
          _text(0, 'Alpha sentence.'),
          _text(1, 'Beta sentence.'),
          _text(2, 'x'),
        ];
        final proseTransitions = <String>[];
        final proseHarness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: prose,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        final proseResult = await _run(
          proseHarness,
          snapshot: _snapshot(prose, revision: 'rebalance-r1'),
          layout: _layoutWithBudgets(proseHarness.paginatorLayout, 70),
          onDiagnostic: (phase, fields) {
            if (phase == 'canonical_frontier_transition') {
              proseTransitions.add(fields['transition']! as String);
            }
          },
        );
        expect(proseResult, isA<CanonicalLogicalEndReached>());

        final excluded = <BookChunk>[
          _list(0, 'List sentence one. List sentence two.'),
          _list(1, 'x'),
          _publisher(2, 'Publisher sentence one. Publisher sentence two.'),
          _publisher(3, 'x'),
        ];
        final excludedTransitions = <String>[];
        final excludedHarness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: excluded,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        final excludedResult = await _run(
          excludedHarness,
          snapshot: _snapshot(excluded, revision: 'rebalance-excluded-r1'),
          onDiagnostic: (phase, fields) {
            if (phase == 'canonical_frontier_transition') {
              excludedTransitions.add(fields['transition']! as String);
            }
          },
        );

        expect(proseTransitions, contains('sentence_rebalance'));
        expect(excludedTransitions, isNot(contains('sentence_rebalance')));
        final excludedCards =
            (excludedResult as CanonicalLogicalEndReached).finalizedCards;
        expect(
          excludedCards.expand(
            (card) => card.card.effectiveListDisplaySegments,
          ),
          isNotEmpty,
        );
        expect(
          excludedCards.any((card) => card.card.usesPublisherLayout),
          isTrue,
        );
      },
    );
  });

  group('[TASK-P04-002] bounds, cancellation, and structural preservation', () {
    testWidgets(
      'frontier cap breach rejects every private output and authority',
      (tester) async {
        final sources = <BookChunk>[
          _text(0, 'first frontier entry'),
          _text(1, 'second proof entry'),
        ];
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final result = await _run(
          harness,
          snapshot: _snapshot(sources, revision: 'bound-r1'),
          budget: const CanonicalPaginationWorkBudget(maxFrontierEntries: 1),
        );

        expect(result, isA<CanonicalFrontierBoundViolation>());
        final rejected = result as CanonicalFrontierBoundViolation;
        expect(rejected.diagnostics.peakFrontierEntries, greaterThan(1));
        _expectNoAuthority(rejected);
      },
    );

    testWidgets(
      'cancellation checkpoints reject before work, splitting, finalization, and assembly',
      (tester) async {
        final scenarios =
            <
              ({
                String label,
                List<BookChunk> sources,
                String phase,
                String? stage,
              })
            >[
              (
                label: 'before-source-work',
                sources: <BookChunk>[_text(0, 'source')],
                phase: 'canonical_cancellation_checkpoint',
                stage: 'before_source_work',
              ),
              (
                label: 'during-splitting',
                sources: <BookChunk>[
                  _text(0, List<String>.filled(220, 'unbroken').join()),
                ],
                phase: 'canonical_split_begin',
                stage: null,
              ),
              (
                label: 'before-finalization',
                sources: <BookChunk>[_heading(0, 'Heading'), _text(1, 'body')],
                phase: 'canonical_cancellation_checkpoint',
                stage: 'before_finalization',
              ),
              (
                label: 'before-result-assembly',
                sources: <BookChunk>[_text(0, 'terminal body')],
                phase: 'canonical_cancellation_checkpoint',
                stage: 'before_result_assembly',
              ),
            ];

        for (final scenario in scenarios) {
          var cancel = false;
          final harness = await ReaderCorePaginationHarness.install(
            tester: tester,
            sourceChunks: scenario.sources,
            layout: ReaderCorePaginationLayout.splitStress,
          );
          final result = await _run(
            harness,
            snapshot: _snapshot(
              scenario.sources,
              revision: 'cancel-${scenario.label}',
            ),
            isCancelled: () => cancel,
            onDiagnostic: (phase, fields) {
              if (phase == scenario.phase &&
                  (scenario.stage == null ||
                      fields['stage'] == scenario.stage)) {
                cancel = true;
              }
            },
          );
          expect(
            result,
            isA<CanonicalCancelledStaleRejected>(),
            reason: scenario.label,
          );
          _expectNoAuthority(result as CanonicalCancelledStaleRejected);
          expect(result.diagnostics.cancellationCheckpoints, greaterThan(0));
        }
      },
    );

    testWidgets(
      'cancellation during rebalance and stale generation reject private cards',
      (tester) async {
        final sources = <BookChunk>[
          _text(0, 'Alpha sentence.'),
          _text(1, 'Beta sentence.'),
          _text(2, 'x'),
        ];
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        var cancel = false;
        final cancelled = await _run(
          harness,
          snapshot: _snapshot(sources, revision: 'cancel-rebalance-r1'),
          layout: _layoutWithBudgets(harness.paginatorLayout, 70),
          isCancelled: () => cancel,
          onDiagnostic: (phase, fields) {
            if (phase == 'canonical_cancellation_checkpoint' &&
                fields['stage'] == 'during_rebalance') {
              cancel = true;
            }
          },
        );
        expect(cancel, isTrue);
        expect(cancelled, isA<CanonicalCancelledStaleRejected>());
        _expectNoAuthority(cancelled as CanonicalCancelledStaleRejected);

        final stale = await _run(
          harness,
          snapshot: _snapshot(sources, revision: 'stale-r1'),
          generation: 80,
          currentGeneration: () => 81,
        );
        expect(stale, isA<CanonicalCancelledStaleRejected>());
        final rejected = stale as CanonicalCancelledStaleRejected;
        expect(
          rejected.reason,
          CanonicalPaginationRejectionReason.staleGeneration,
        );
        _expectNoAuthority(rejected);
      },
    );

    testWidgets(
      'trusted fixture preserves headings, lists, tables, rich text, seams, and source 7',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        final run = await _runToLogicalEnd(
          harness,
          snapshot: _snapshot(fixture.sourceChunks, revision: 'fixture-r1'),
        );

        final logicalEnd = run.terminal;
        final cards = run.cards;
        expect(cards.any((card) => card.card.isHeading), isTrue);
        expect(
          cards.expand((card) => card.card.effectiveListDisplaySegments),
          isNotEmpty,
        );
        expect(
          cards.any(
            (card) =>
                card.card.blockRole == BookBlockRole.table &&
                parseReaderContentBlocks(card.card.text ?? '').single.table !=
                    null,
          ),
          isTrue,
        );
        expect(
          cards.any((card) => card.card.inlineStyles?.isNotEmpty ?? false),
          isTrue,
        );
        expect(
          cards.any((card) => card.card.links?.isNotEmpty ?? false),
          isTrue,
        );
        expect(
          cards.any((card) => card.card.footnotes?.isNotEmpty ?? false),
          isTrue,
        );
        final sourceSevenRanges = cards
            .expand((card) => card.sourceSlices)
            .where((slice) => slice.sourceOrdinalHint == 7)
            .toList();
        expect(sourceSevenRanges, hasLength(greaterThan(1)));
        expect(sourceSevenRanges.first.startUtf16, 0);
        expect(
          sourceSevenRanges.last.endUtf16,
          fixture.sourceChunks[7].text!.length,
        );
        expect(
          cards
              .expand((card) => card.sourceSlices)
              .map((slice) => slice.sectionIdentity)
              .toSet(),
          containsAll(<String>{
            'nav.xhtml',
            'text/chapter-one.xhtml',
            'text/chapter-two.xhtml',
          }),
        );
        expect(run.peakFrontierEntries, lessThanOrEqualTo(7));
        expect(run.sourceChunksFullyConsumed, fixture.sourceChunks.length);
        expect(
          run.atomicFragmentsProcessed,
          greaterThan(fixture.sourceChunks.length),
        );
        expect(run.referencedUtf16Extent, greaterThan(0));
        expect(run.tableRows, greaterThan(0));
        expect(run.cardsFinalized, cards.length);
        expect(run.peakPrivateFrontierBytes, greaterThan(0));
        expect(logicalEnd.continuation.terminal, isTrue);
      },
    );

    testWidgets(
      'split table frontier carries stable row intervals across in-memory resumes',
      (tester) async {
        final table = ReaderTableBlock(
          headers: const <String>['Column', 'Value'],
          rows: <List<String>>[
            for (var row = 0; row < 10; row++)
              <String>['row-$row', 'value-$row'],
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
        final snapshot = _snapshot(sources, revision: 'table-rows-r1');
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final layout = _layoutWithBudgets(harness.paginatorLayout, 90);
        CanonicalPaginationRestart restart =
            const CanonicalPaginationPublicationStart();
        CanonicalPaginationContinuation? continuationParent;
        final finalized = <CanonicalFinalizedReaderCard>[];
        var sawRowCursor = false;

        for (var request = 0; request < 16; request++) {
          final result = await _run(
            harness,
            snapshot: snapshot,
            restart: restart,
            continuationParent: continuationParent,
            layout: layout,
            generation: 200 + request,
            budget: const CanonicalPaginationWorkBudget(
              maxAtomicFragments: 1,
              maxFinalizedCards: 96,
            ),
          );
          if (result is CanonicalLogicalEndReached) {
            finalized.addAll(result.finalizedCards);
            break;
          }
          final exhausted = result as CanonicalBudgetExhaustedWithFrontier;
          finalized.addAll(exhausted.finalizedCards);
          expect(exhausted.frontier.cardCandidateCount, lessThanOrEqualTo(2));
          expect(
            exhausted.frontier.pendingTail!.sourceSlices.single.tableRowStart,
            isNotNull,
          );
          sawRowCursor |=
              exhausted.nextSourceCursor.kind ==
              CanonicalPaginationCursorKind.tableRow;
          continuationParent = restart is CanonicalPaginationContinuation
              ? restart
              : null;
          restart = exhausted.restart;
        }

        expect(sawRowCursor, isTrue);
        expect(finalized, isNotEmpty);
        final intervals = finalized
            .expand((card) => card.sourceSlices)
            .where((slice) => slice.tableRowStart != null)
            .toList();
        expect(intervals.first.tableRowStart, 0);
        expect(intervals.last.tableRowEndExclusive, table.rows.length);
        for (var index = 1; index < intervals.length; index++) {
          expect(
            intervals[index - 1].tableRowEndExclusive,
            intervals[index].tableRowStart,
          );
        }
        expect(
          finalized.map((card) => card.identity.signature).toSet(),
          hasLength(finalized.length),
        );
      },
    );

    testWidgets('identical canonical invocation is deterministic', (
      tester,
    ) async {
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: fixture.sourceChunks,
      );
      final snapshot = _snapshot(
        fixture.sourceChunks,
        revision: 'determinism-r1',
      );
      final first = await _runToLogicalEnd(
        harness,
        snapshot: snapshot,
        firstGeneration: 90,
      );
      final second = await _runToLogicalEnd(
        harness,
        snapshot: snapshot,
        firstGeneration: 190,
      );

      List<Map<String, Object?>> evidence(_CompletedCanonicalRun result) =>
          result.cards
              .map(
                (card) => <String, Object?>{
                  'text': card.card.text,
                  'chunk': card.card.toJson(),
                  'identity': card.identity.signature,
                  'owners': card.sourceSlices
                      .map((slice) => slice.sourceIdentity)
                      .toList(),
                },
              )
              .toList();

      expect(evidence(second), evidence(first));
      expect(second.continuationEncodings, first.continuationEncodings);
    });
  });
}

CanonicalPaginationSourceSnapshot _snapshot(
  List<BookChunk> sources, {
  required String revision,
}) {
  return CanonicalPaginationSourceSnapshot.pin(
    bookId: readerCoreFixtureId,
    publicationFingerprint: readerCoreFixtureId,
    parserSourceIdentity: 'reader-core-parser-v1',
    sourceRevision: revision,
    sourceChunks: sources,
    sourceKeys: <CanonicalPaginationSourceKey>[
      for (var index = 0; index < sources.length; index++)
        CanonicalPaginationSourceKey(
          sourceIdentity:
              '${sources[index].sourceFile ?? 'source'}#stable-$index',
          sectionIdentity:
              sources[index].sourceFile ??
              'section-${sources[index].section.name}',
          spineIdentity:
              sources[index].sourceFile ??
              'spine-${sources[index].section.name}',
          sourceOrdinalHint: index,
        ),
    ],
  );
}

Future<CanonicalPaginationResult> _run(
  ReaderCorePaginationHarness harness, {
  required CanonicalPaginationSourceSnapshot snapshot,
  CanonicalPaginationRestart restart =
      const CanonicalPaginationPublicationStart(),
  CanonicalPaginationContinuation? continuationParent,
  CanonicalPaginationWorkBudget budget = const CanonicalPaginationWorkBudget(
    maxFinalizedCards: 96,
  ),
  CanonicalPaginationTargetCursor? target,
  ReaderCardPaginatorLayout? layout,
  int generation = 70,
  int Function()? currentGeneration,
  bool Function()? isCancelled,
  ReaderCardPaginatorDiagnostic? onDiagnostic,
}) {
  final requestLayout = layout ?? harness.paginatorLayout;
  return const ReaderCardPaginator().paginateCanonical(
    CanonicalPaginationRequest(
      bookId: readerCoreFixtureId,
      publicationFingerprint: readerCoreFixtureId,
      sourceSnapshot: snapshot,
      controlledLayoutIdentity:
          '${harness.layoutIdentity}:${requestLayout.pageHeightBudget}:'
          '${requestLayout.physicalTextBudget}:${requestLayout.minUsefulHeight}:'
          '${requestLayout.tinyWordCount}:${requestLayout.tinyHeightRatio}',
      layout: requestLayout,
      restart: restart,
      continuationParent: continuationParent,
      target: target,
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

Future<_CompletedCanonicalRun> _runToLogicalEnd(
  ReaderCorePaginationHarness harness, {
  required CanonicalPaginationSourceSnapshot snapshot,
  int firstGeneration = 70,
}) async {
  final cards = <CanonicalFinalizedReaderCard>[];
  final encodings = <String>[];
  CanonicalPaginationRestart restart =
      const CanonicalPaginationPublicationStart();
  CanonicalPaginationContinuation? continuationParent;
  var sourceChunksFullyConsumed = 0;
  var atomicFragmentsProcessed = 0;
  var referencedUtf16Extent = 0;
  var tableRows = 0;
  var cardsFinalized = 0;
  var peakFrontierEntries = 0;
  var peakPrivateFrontierBytes = 0;
  for (var operation = 0; operation < 64; operation++) {
    final result = await _run(
      harness,
      snapshot: snapshot,
      restart: restart,
      continuationParent: continuationParent,
      generation: firstGeneration + operation,
    );
    if (result is CanonicalPaginationRejectedResult) {
      throw StateError(
        'Canonical chain rejected at operation $operation: '
        '${result.reason.name}: ${result.message}; '
        'restart=${restart is CanonicalPaginationContinuation ? '${restart.chainOrdinal}/${restart.integrityDigest}' : restart.runtimeType}',
      );
    }
    final accepted = result as CanonicalPaginationAcceptedResult;
    cards.addAll(accepted.finalizedCards);
    encodings.add(accepted.continuation.canonicalEncoding);
    final diagnostics = accepted.diagnostics;
    sourceChunksFullyConsumed += diagnostics.sourceChunksFullyConsumed;
    atomicFragmentsProcessed += diagnostics.atomicFragmentsProcessed;
    referencedUtf16Extent += diagnostics.referencedUtf16Extent;
    tableRows += diagnostics.tableRows;
    cardsFinalized += diagnostics.cardsFinalized;
    peakFrontierEntries = math.max(
      peakFrontierEntries,
      diagnostics.peakFrontierEntries,
    );
    peakPrivateFrontierBytes = math.max(
      peakPrivateFrontierBytes,
      diagnostics.peakPrivateFrontierBytes,
    );
    if (result is CanonicalLogicalEndReached) {
      return _CompletedCanonicalRun(
        terminal: result,
        cards: cards,
        continuationEncodings: encodings,
        sourceChunksFullyConsumed: sourceChunksFullyConsumed,
        atomicFragmentsProcessed: atomicFragmentsProcessed,
        referencedUtf16Extent: referencedUtf16Extent,
        tableRows: tableRows,
        cardsFinalized: cardsFinalized,
        peakFrontierEntries: peakFrontierEntries,
        peakPrivateFrontierBytes: peakPrivateFrontierBytes,
      );
    }
    continuationParent = restart is CanonicalPaginationContinuation
        ? restart
        : null;
    restart = accepted.continuation;
  }
  throw StateError(
    'Canonical chain did not reach logical end within 64 steps.',
  );
}

final class _CompletedCanonicalRun {
  const _CompletedCanonicalRun({
    required this.terminal,
    required this.cards,
    required this.continuationEncodings,
    required this.sourceChunksFullyConsumed,
    required this.atomicFragmentsProcessed,
    required this.referencedUtf16Extent,
    required this.tableRows,
    required this.cardsFinalized,
    required this.peakFrontierEntries,
    required this.peakPrivateFrontierBytes,
  });

  final CanonicalLogicalEndReached terminal;
  final List<CanonicalFinalizedReaderCard> cards;
  final List<String> continuationEncodings;
  final int sourceChunksFullyConsumed;
  final int atomicFragmentsProcessed;
  final int referencedUtf16Extent;
  final int tableRows;
  final int cardsFinalized;
  final int peakFrontierEntries;
  final int peakPrivateFrontierBytes;
}

bool _neverCancelled() => false;

ReaderCardPaginatorLayout _layoutWithBudgets(
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

BookChunk _text(int index, String text, {List<LinkMetadata>? links}) =>
    BookChunk(
      index: index,
      type: BookChunkType.text,
      text: text,
      links: links,
      sourceFile: 'chapter.xhtml',
      logicalParagraphId: 'paragraph-$index',
      logicalParagraphEndOffset: text.length,
    );

BookChunk _heading(int index, String text) => BookChunk(
  index: index,
  type: BookChunkType.text,
  text: text,
  isHeading: true,
  blockRole: BookBlockRole.heading,
  sourceFile: 'chapter.xhtml',
  logicalParagraphId: 'heading-$index',
  logicalParagraphEndOffset: text.length,
);

BookChunk _publisher(int index, String text, {bool dialogue = false}) =>
    BookChunk(
      index: index,
      type: BookChunkType.text,
      text: text,
      isDialogue: dialogue,
      blockRole: BookBlockRole.poem,
      preserveLineBreaks: true,
      sourceFile: 'chapter.xhtml',
      logicalParagraphId: 'publisher-$index',
      logicalParagraphEndOffset: text.length,
    );

BookChunk _list(int index, String text) => BookChunk(
  index: index,
  type: BookChunkType.text,
  text: text,
  sourceFile: 'chapter.xhtml',
  logicalParagraphId: 'list-$index',
  logicalParagraphEndOffset: text.length,
  listSemantics: BookListSemantics(
    listId: 'ordered-list',
    itemId: 'item-$index',
    ordered: true,
    depth: 0,
    markerType: BookListMarkerType.decimal,
    resolvedOrdinal: index + 1,
    blockIndex: 0,
    beginsItem: true,
    endsItem: true,
  ),
);
