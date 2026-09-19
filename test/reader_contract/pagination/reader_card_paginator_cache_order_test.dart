import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/progressive_display_state.dart';

import '../support/reader_contract_sandbox.dart';
import 'reader_core_cache_order_harness.dart';
import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('nalori_reader_p03_cache_');
  });

  tearDownAll(() => fixture.close());

  const plans = <ReaderCacheRangePlan>[
    ReaderCacheRangePlan(
      label: 'inline-section-seam-known-pass',
      expectedToMatchFull: true,
      ranges: [
        SourceChunkRange(0, 12),
        SourceChunkRange(12, 16),
        SourceChunkRange(16, 17),
        SourceChunkRange(17, 20),
      ],
    ),
    ReaderCacheRangePlan(
      label: 'merge-long-repeat-known-red',
      expectedToMatchFull: false,
      ranges: [
        SourceChunkRange(0, 5),
        SourceChunkRange(5, 8),
        SourceChunkRange(8, 20),
      ],
      failureIds: {
        ReaderCacheOrderState.coldSegmented: 'P03-CACHE-001',
        ReaderCacheOrderState.warmMemory: 'P03-CACHE-002',
        ReaderCacheOrderState.warmDisk: 'P03-CACHE-003',
        ReaderCacheOrderState.memoryEviction: 'P03-CACHE-004',
        ReaderCacheOrderState.reopenReload: 'P03-CACHE-005',
      },
    ),
  ];

  group('[REQ-007, REQ-008, REQ-009, REQ-012, REQ-013, REQ-027, '
      'REQ-032, REQ-033, REQ-034, REQ-048, REQ-051] '
      'TASK-P03-005 cache-order matrix', () {
    for (final plan in plans) {
      for (final state in ReaderCacheOrderState.values) {
        final failureId = plan.failureIdFor(state);
        testWidgets(
          '${failureId == null ? '' : '$failureId '}cache:${plan.label} '
          '${state.label} equals fresh full range',
          (tester) async {
            final sandbox = (await tester.runAsync(
              ReaderContractSandbox.create,
            ))!;
            addTearDown(sandbox.close);
            // ignore: avoid_print
            print('P03 cache setup sandbox-ready ${sandbox.root.path}');
            final pagination = await ReaderCorePaginationHarness.install(
              tester: tester,
              sourceChunks: fixture.sourceChunks,
              bookId: sandbox.identity.bookId,
              publicationFingerprint: sandbox.identity.publicationFingerprint,
              stateCacheKey: 'p03-cache-state-${sandbox.identity.sessionId}',
            );
            // ignore: avoid_print
            print('P03 cache setup layout-ready ${pagination.layoutIdentity}');
            final cache = ReaderCoreCacheOrderHarness.create(
              sandbox: sandbox,
              pagination: pagination,
            );

            final full = await pagination.fullRange();
            // ignore: avoid_print
            print(
              'P03 cache setup reference-ready ${full.evidence.cards.length}',
            );
            final outcome = (await tester.runAsync(
              () => cache.exercise(plan: plan, state: state),
            ))!;
            final mismatch = compareConstructionToFull(
              scenario:
                  '${failureId ?? 'P03-CACHE-PASS'}:'
                  '${plan.label}:${state.label}',
              full: full,
              actual: outcome.construction,
            );
            if (failureId != null) {
              // ignore: avoid_print
              print(
                compactConstructionMismatchEvidence(
                  failureId: failureId,
                  full: full,
                  actual: outcome.construction,
                ),
              );
            }
            // ignore: avoid_print
            print('P03 cache evidence ${outcome.diagnostics}');
            if (state != ReaderCacheOrderState.coldFull) {
              expect(outcome.diagnostics, contains('whole-cache-hit:'));
              expect(
                outcome.diagnostics,
                contains(
                  'direct-publication-rejected: canonicalRegenerationRequired',
                ),
              );
              expect(
                outcome.diagnostics,
                contains('bounded-canonical-regeneration:'),
              );
              expect(outcome.construction.state.canonicalCards, isNotEmpty);
              expect(
                outcome.construction.state.hasCanonicalCacheWriteAuthority,
                isTrue,
              );
            }
            expect(
              mismatch,
              isNull,
              reason: '$mismatch\n${outcome.diagnostics}',
            );
          },
        );
      }
    }
  });
}
