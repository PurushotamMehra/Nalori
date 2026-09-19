import 'package:flutter_test/flutter_test.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load(
      'nalori_reader_p03_singleton_',
    );
  });

  tearDownAll(() => fixture.close());

  const anchors = <_SingletonAnchor>[
    _SingletonAnchor(
      label: 'mergeable-prose',
      sourceIndex: 5,
      forwardFailureId: 'P03-SINGLETON-001',
      backwardFailureId: 'P03-SINGLETON-002',
    ),
    _SingletonAnchor(
      label: 'split-long-paragraph',
      sourceIndex: 7,
      layout: ReaderCorePaginationLayout.splitStress,
    ),
    _SingletonAnchor(label: 'repeated-prose', sourceIndex: 8),
    _SingletonAnchor(
      label: 'heading-boundary',
      sourceIndex: 3,
      forwardFailureId: 'P03-SINGLETON-003',
      backwardFailureId: 'P03-SINGLETON-004',
    ),
    _SingletonAnchor(label: 'section-seam-heading', sourceIndex: 16),
  ];

  group('[REQ-007, REQ-008, REQ-011, REQ-012, REQ-013, REQ-027, '
      'REQ-028, REQ-032, REQ-033, REQ-034, REQ-048, REQ-051] '
      'TASK-P03-004 singleton expansion matrix', () {
    for (final anchor in anchors) {
      for (final forwardFirst in const [true, false]) {
        final order = forwardFirst
            ? 'forward-then-backward'
            : 'backward-then-forward';
        final declaredFailureId = forwardFirst
            ? anchor.forwardFailureId
            : anchor.backwardFailureId;
        testWidgets('${declaredFailureId == null ? '' : '$declaredFailureId '}'
            '${anchor.label} singleton $order equals full range', (
          tester,
        ) async {
          final harness = await ReaderCorePaginationHarness.install(
            tester: tester,
            sourceChunks: fixture.sourceChunks,
            layout: anchor.layout,
          );
          final full = await harness.fullRange();
          final actual = await harness.singletonThenExpand(
            target: anchor.sourceIndex,
            forwardFirst: forwardFirst,
          );
          if (anchor.layout == ReaderCorePaginationLayout.splitStress) {
            _expectLongParagraphSplit(full);
            _expectLongParagraphSplit(actual);
          }
          final singletonOutcome = describeSingletonOutcome(
            full: full,
            actual: actual,
          );
          // ignore: avoid_print
          print(
            'P03 singleton outcome ${anchor.label} $order: $singletonOutcome',
          );
          final mismatch = compareConstructionToFull(
            scenario: 'singleton:${anchor.label}',
            full: full,
            actual: actual,
          );
          final failureId = forwardFirst
              ? anchor.forwardFailureId
              : anchor.backwardFailureId;
          if (failureId != null) {
            // ignore: avoid_print
            print(
              compactConstructionMismatchEvidence(
                failureId: failureId,
                full: full,
                actual: actual,
              ),
            );
          }
          expect(
            mismatch,
            isNull,
            reason:
                '$mismatch\n$singletonOutcome\n'
                'controlledLayout=${harness.layoutDiagnostics}',
          );
        });
      }
    }
  });
}

void _expectLongParagraphSplit(ReaderPaginationConstruction construction) {
  final ranges = construction.evidence.cards
      .expand((card) => card.sourceRanges)
      .where((range) => range.sourceIndex == 7)
      .toList(growable: false);
  expect(
    ranges.length,
    greaterThan(1),
    reason: construction.evidence.describe(),
  );
}

final class _SingletonAnchor {
  const _SingletonAnchor({
    required this.label,
    required this.sourceIndex,
    this.layout = ReaderCorePaginationLayout.standard,
    this.forwardFailureId,
    this.backwardFailureId,
  });

  final String label;
  final int sourceIndex;
  final ReaderCorePaginationLayout layout;
  final String? forwardFailureId;
  final String? backwardFailureId;
}
