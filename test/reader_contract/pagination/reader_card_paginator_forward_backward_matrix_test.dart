import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/progressive_display_state.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load(
      'nalori_reader_p03_forward_backward_',
    );
  });

  tearDownAll(() => fixture.close());

  const plans = <_PartitionPlan>[
    _PartitionPlan(
      label: 'generated-heading-boundaries',
      ranges: [
        SourceChunkRange(0, 2),
        SourceChunkRange(2, 4),
        SourceChunkRange(4, 20),
      ],
    ),
    _PartitionPlan(
      label: 'merge-long-repeat-boundaries',
      forwardFailureId: 'P03-FORWARD-001',
      backwardFailureId: 'P03-PREPEND-001',
      ranges: [
        SourceChunkRange(0, 5),
        SourceChunkRange(5, 8),
        SourceChunkRange(8, 20),
      ],
    ),
    _PartitionPlan(
      label: 'repeat-list-table-boundaries',
      ranges: [
        SourceChunkRange(0, 8),
        SourceChunkRange(8, 11),
        SourceChunkRange(11, 12),
        SourceChunkRange(12, 20),
      ],
    ),
    _PartitionPlan(
      label: 'inline-and-section-seam-boundaries',
      ranges: [
        SourceChunkRange(0, 12),
        SourceChunkRange(12, 16),
        SourceChunkRange(16, 17),
        SourceChunkRange(17, 20),
      ],
    ),
    _PartitionPlan(
      label: 'split-stress-long-paragraph-island',
      layout: ReaderCorePaginationLayout.splitStress,
      ranges: [
        SourceChunkRange(0, 7),
        SourceChunkRange(7, 8),
        SourceChunkRange(8, 20),
      ],
    ),
  ];

  group('[REQ-007, REQ-008, REQ-011, REQ-012, REQ-013, REQ-027, '
      'REQ-028, REQ-032, REQ-033, REQ-034, REQ-048, REQ-051] '
      'TASK-P03-003 forward/backward matrix', () {
    for (final plan in plans) {
      testWidgets(
        '${plan.forwardFailureId == null ? '' : '${plan.forwardFailureId} '}'
        '${plan.label} forward-first equals full range',
        (tester) async {
          final harness = await ReaderCorePaginationHarness.install(
            tester: tester,
            sourceChunks: fixture.sourceChunks,
            layout: plan.layout,
          );
          final full = await harness.fullRange();
          _expectSplitWhenRequired(plan, full);
          final actual = await harness.forwardFirst(plan.ranges);
          _expectSplitWhenRequired(plan, actual);
          final mismatch = compareConstructionToFull(
            scenario: 'partition:${plan.label}',
            full: full,
            actual: actual,
          );
          if (plan.forwardFailureId != null) {
            // ignore: avoid_print
            print(
              compactConstructionMismatchEvidence(
                failureId: plan.forwardFailureId!,
                full: full,
                actual: actual,
              ),
            );
          }
          expect(
            mismatch,
            isNull,
            reason: '$mismatch\ncontrolledLayout=${harness.layoutDiagnostics}',
          );
        },
      );

      testWidgets(
        '${plan.backwardFailureId == null ? '' : '${plan.backwardFailureId} '}'
        '${plan.label} backward/prepend-first equals full range',
        (tester) async {
          final harness = await ReaderCorePaginationHarness.install(
            tester: tester,
            sourceChunks: fixture.sourceChunks,
            layout: plan.layout,
          );
          final full = await harness.fullRange();
          _expectSplitWhenRequired(plan, full);
          final actual = await harness.backwardFirst(plan.ranges);
          _expectSplitWhenRequired(plan, actual);
          final mismatch = compareConstructionToFull(
            scenario: 'partition:${plan.label}',
            full: full,
            actual: actual,
          );
          if (plan.backwardFailureId != null) {
            // ignore: avoid_print
            print(
              compactConstructionMismatchEvidence(
                failureId: plan.backwardFailureId!,
                full: full,
                actual: actual,
              ),
            );
          }
          expect(
            mismatch,
            isNull,
            reason: '$mismatch\ncontrolledLayout=${harness.layoutDiagnostics}',
          );
        },
      );
    }
  });
}

void _expectSplitWhenRequired(
  _PartitionPlan plan,
  ReaderPaginationConstruction construction,
) {
  if (plan.layout != ReaderCorePaginationLayout.splitStress) return;
  final ranges = construction.evidence.cards
      .expand((card) => card.sourceRanges)
      .where((range) => range.sourceIndex == 7)
      .toList(growable: false);
  expect(
    ranges.length,
    greaterThan(1),
    reason:
        'The explicit split-stress layout did not split source 7.\n'
        '${construction.evidence.describe()}',
  );
  expect(ranges.first.sourceStartUtf16, 0);
  expect(ranges.last.sourceEndUtf16, 198);
  for (var index = 1; index < ranges.length; index++) {
    expect(ranges[index].sourceStartUtf16, ranges[index - 1].sourceEndUtf16);
  }
  // ignore: avoid_print
  print(
    'P03 split evidence ${construction.label} '
    'layout=${construction.layoutIdentity} source7=${ranges.map((range) => '[${range.sourceStartUtf16},${range.sourceEndUtf16})').join(',')}',
  );
}

final class _PartitionPlan {
  const _PartitionPlan({
    required this.label,
    required this.ranges,
    this.layout = ReaderCorePaginationLayout.standard,
    this.forwardFailureId,
    this.backwardFailureId,
  });

  final String label;
  final List<SourceChunkRange> ranges;
  final ReaderCorePaginationLayout layout;
  final String? forwardFailureId;
  final String? backwardFailureId;
}
