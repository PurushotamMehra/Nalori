import 'package:flutter_test/flutter_test.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load(
      'nalori_reader_p03_target_first_',
    );
  });

  tearDownAll(() => fixture.close());

  const anchors = <({String label, int sourceIndex, String? failureId})>[
    (label: 'first-readable', sourceIndex: 0, failureId: 'P03-TARGET-001'),
    (
      label: 'generated-toc-structure',
      sourceIndex: 1,
      failureId: 'P03-TARGET-002',
    ),
    (label: 'chapter-heading', sourceIndex: 2, failureId: 'P03-TARGET-003'),
    (label: 'subsection-heading', sourceIndex: 3, failureId: 'P03-TARGET-004'),
    (
      label: 'mergeable-short-prose',
      sourceIndex: 5,
      failureId: 'P03-TARGET-005',
    ),
    (label: 'long-paragraph', sourceIndex: 7, failureId: 'P03-TARGET-006'),
    (
      label: 'first-repeated-prose',
      sourceIndex: 8,
      failureId: 'P03-TARGET-007',
    ),
    (label: 'ordered-list-start', sourceIndex: 9, failureId: null),
    (label: 'table', sourceIndex: 11, failureId: 'P03-TARGET-008'),
    (
      label: 'inline-link-footnote-group',
      sourceIndex: 13,
      failureId: 'P03-TARGET-009',
    ),
    (label: 'before-spine-seam', sourceIndex: 15, failureId: 'P03-TARGET-010'),
    (
      label: 'second-section-heading',
      sourceIndex: 16,
      failureId: 'P03-TARGET-011',
    ),
    (label: 'after-spine-seam', sourceIndex: 17, failureId: 'P03-TARGET-012'),
    (label: 'second-repeated-prose', sourceIndex: 18, failureId: null),
    (label: 'final-readable', sourceIndex: 19, failureId: null),
  ];

  group('[REQ-007, REQ-008, REQ-011, REQ-012, REQ-013, REQ-027, '
      'REQ-028, REQ-032, REQ-033, REQ-034, REQ-048, REQ-051] '
      'TASK-P03-002 target-first matrix', () {
    for (final anchor in anchors) {
      testWidgets('${anchor.failureId == null ? '' : '${anchor.failureId} '}'
          '${anchor.label} preserves the full physical sequence', (
        tester,
      ) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final full = await harness.fullRange();
        final targetFirst = await harness.targetFirst(anchor.sourceIndex);

        expectReaderCoreStructuralInvariants(targetFirst);
        final mismatch = compareConstructionToFull(
          scenario: 'target-first:${anchor.label}',
          full: full,
          actual: targetFirst,
        );
        if (anchor.failureId != null) {
          // ignore: avoid_print
          print(
            compactConstructionMismatchEvidence(
              failureId: anchor.failureId!,
              full: full,
              actual: targetFirst,
            ),
          );
        }
        expect(
          mismatch,
          isNull,
          reason: '$mismatch\ncontrolledLayout=${harness.layoutDiagnostics}',
        );
      });
    }
  });
}
