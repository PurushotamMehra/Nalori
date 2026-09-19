import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/progressive_display_state.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load(
      'nalori_reader_p03_structure_',
    );
  });

  tearDownAll(() => fixture.close());

  group('[REQ-007, REQ-011, REQ-013, REQ-028, REQ-032, REQ-033, '
      'REQ-034, REQ-051] TASK-P03-006 structural ownership and coverage', () {
    testWidgets('full-range construction preserves authored structure', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      expectReaderCoreStructuralInvariants(await harness.fullRange());
    });

    testWidgets('target-first construction preserves authored structure', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      expectReaderCoreStructuralInvariants(await harness.targetFirst(13));
    });

    testWidgets('forward-first construction preserves authored structure', (
      tester,
    ) async {
      final harness = await _harness(tester, fixture.sourceChunks);
      expectReaderCoreStructuralInvariants(
        await harness.forwardFirst(_structuralPartitions),
      );
    });

    testWidgets(
      'backward/prepend-first construction preserves authored structure',
      (tester) async {
        final harness = await _harness(tester, fixture.sourceChunks);
        expectReaderCoreStructuralInvariants(
          await harness.backwardFirst(_structuralPartitions),
        );
      },
    );

    for (final forwardFirst in const [true, false]) {
      final order = forwardFirst
          ? 'forward-then-backward'
          : 'backward-then-forward';
      testWidgets(
        'section-heading singleton $order preserves authored structure',
        (tester) async {
          final harness = await _harness(tester, fixture.sourceChunks);
          expectReaderCoreStructuralInvariants(
            await harness.singletonThenExpand(
              target: 16,
              forwardFirst: forwardFirst,
            ),
          );
        },
      );
    }
  });
}

const _structuralPartitions = <SourceChunkRange>[
  SourceChunkRange(0, 8),
  SourceChunkRange(8, 12),
  SourceChunkRange(12, 16),
  SourceChunkRange(16, 20),
];

Future<ReaderCorePaginationHarness> _harness(
  WidgetTester tester,
  List<BookChunk> sourceChunks,
) {
  return ReaderCorePaginationHarness.install(
    tester: tester,
    sourceChunks: sourceChunks,
  );
}
