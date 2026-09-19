import 'package:flutter_test/flutter_test.dart';

import 'p03_failure_ledger.dart';

void main() {
  group('[REQ-007, REQ-008, REQ-009, REQ-011, REQ-012, REQ-013, '
      'REQ-027, REQ-028, REQ-032, REQ-033, REQ-034, REQ-048, REQ-051] '
      'TASK-P03-007 failure-ledger integrity', () {
    test('contains every distinct deterministic red scenario exactly once', () {
      expect(p03FailureLedger, hasLength(23));
      final ids = p03FailureLedger.map((entry) => entry.id).toSet();
      expect(ids, hasLength(p03FailureLedger.length));
      expect(ids.where((id) => id.startsWith('P03-TARGET-')), hasLength(12));
      expect(ids.where((id) => id.startsWith('P03-FORWARD-')), hasLength(1));
      expect(ids.where((id) => id.startsWith('P03-PREPEND-')), hasLength(1));
      expect(ids.where((id) => id.startsWith('P03-SINGLETON-')), hasLength(4));
      expect(ids.where((id) => id.startsWith('P03-CACHE-')), hasLength(5));
    });

    test('every row carries the required review and repair evidence', () {
      const approvedRequirements = <String>{
        'REQ-007',
        'REQ-008',
        'REQ-009',
        'REQ-011',
        'REQ-012',
        'REQ-013',
        'REQ-027',
        'REQ-028',
        'REQ-032',
        'REQ-033',
        'REQ-034',
        'REQ-048',
        'REQ-051',
      };
      for (final entry in p03FailureLedger) {
        final json = entry.toJson();
        expect(json.values, everyElement(isNotNull), reason: entry.id);
        expect(entry.id, startsWith('P03-'));
        expect(entry.testFile, startsWith('test/reader_contract/pagination/'));
        expect(entry.testName, contains(entry.id));
        expect(entry.layout, p03StandardLayout);
        expect(entry.requests, contains('['));
        expect(entry.requirements, isNotEmpty);
        expect(
          entry.requirements.every(approvedRequirements.contains),
          isTrue,
          reason: entry.id,
        );
        expect(entry.firstDivergence, contains('card['));
        expect(entry.referenceEvidence, contains('identity='));
        expect(entry.actualEvidence, contains('identity='));
        expect(entry.coverageResult, p03CompleteCoverage);
        expect(entry.repeatability, contains('exit 1'));
        expect(entry.repairOwner, anyOf(contains('P04'), contains('P06')));
        expect(entry.prohibitedShortcut, contains('Do not'));
        expect(entry.sourceSupportedMechanism, contains('mechanism'));
        expect(entry.inference, startsWith('Inference'));
      }
    });

    test(
      'cache rows are actual failures and passing evidence stays separate',
      () {
        final cacheRows = p03FailureLedger
            .where((entry) => entry.id.startsWith('P03-CACHE-'))
            .toList(growable: false);
        expect(cacheRows, hasLength(5));
        expect(
          cacheRows.map((entry) => entry.scenario),
          containsAll(<String>[
            'cache:merge-long-repeat-known-red:cold-segmented',
            'cache:merge-long-repeat-known-red:warm-memory',
            'cache:merge-long-repeat-known-red:warm-disk',
            'cache:merge-long-repeat-known-red:memory-eviction',
            'cache:merge-long-repeat-known-red:close-reopen-reload',
          ]),
        );
        expect(
          p03PassingEvidenceSummary['cachePasses'],
          contains('12/12 pass'),
        );
        expect(
          p03PassingEvidenceSummary['resolvedByP04_007'],
          contains('P03-CACHE-001 through P03-CACHE-005 are green'),
        );
        expect(
          p03FailureLedger.any(
            (entry) =>
                entry.scenario.contains('inline-section-seam-known-pass'),
          ),
          isFalse,
        );
      },
    );
  });
}
