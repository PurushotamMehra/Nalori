/// Machine-readable P03 characterization ledger.
///
/// These entries record observed red equality evidence. They do not approve
/// the current full-range physical membership as the eventual P04 oracle.
final class P03FailureLedgerEntry {
  const P03FailureLedgerEntry({
    required this.id,
    required this.testFile,
    required this.testName,
    required this.scenario,
    required this.layout,
    required this.requests,
    required this.requirements,
    required this.approvedInvariant,
    required this.referenceAuthority,
    required this.firstDivergence,
    required this.referenceEvidence,
    required this.actualEvidence,
    required this.coverageResult,
    required this.failureClassification,
    required this.repeatability,
    required this.repairOwner,
    required this.prohibitedShortcut,
    required this.observedResult,
    required this.sourceSupportedMechanism,
    required this.inference,
    required this.laterRepairResponsibility,
  });

  final String id;
  final String testFile;
  final String testName;
  final String scenario;
  final String layout;
  final String requests;
  final List<String> requirements;
  final String approvedInvariant;
  final String referenceAuthority;
  final String firstDivergence;
  final String referenceEvidence;
  final String actualEvidence;
  final String coverageResult;
  final String failureClassification;
  final String repeatability;
  final String repairOwner;
  final String prohibitedShortcut;
  final String observedResult;
  final String sourceSupportedMechanism;
  final String inference;
  final String laterRepairResponsibility;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'testFile': testFile,
    'testName': testName,
    'scenario': scenario,
    'layout': layout,
    'requests': requests,
    'requirements': requirements,
    'approvedInvariant': approvedInvariant,
    'referenceAuthority': referenceAuthority,
    'firstDivergence': firstDivergence,
    'referenceEvidence': referenceEvidence,
    'actualEvidence': actualEvidence,
    'coverageResult': coverageResult,
    'failureClassification': failureClassification,
    'repeatability': repeatability,
    'repairOwner': repairOwner,
    'prohibitedShortcut': prohibitedShortcut,
    'observedResult': observedResult,
    'sourceSupportedMechanism': sourceSupportedMechanism,
    'inference': inference,
    'laterRepairResponsibility': laterRepairResponsibility,
  };
}

const p03StandardLayout = 'p03-controlled-lexend-layout';
const p03ReferenceAuthority =
    'A fresh ReaderCardPaginator.paginate full [0,20) construction under the '
    'same layout, checked alongside the independently authored fixture source '
    'oracle. This is a relational reference, not approved canonical membership.';
const p03EqualityInvariant =
    'Equivalent source and layout inputs must yield the same complete ordered '
    'physical-card source/display/logical ranges, ReaderCardIdentity values, '
    'structural order and visible text regardless of construction/cache order.';
const p03CompleteCoverage =
    'All authored sources 0..19 covered in order; gaps=[]; overlaps=[]; '
    'duplicates=[]; outOfRange=[]; no source reorder.';
const p03BoundaryClassification =
    'Observed: changed physical boundary, separately flushed tail/cut '
    'membership, changed structural-range owner, changed visible grouping and '
    'changed ReaderCardIdentity. No missing, duplicate, overlap or reorder.';
const p03BoundaryMechanism =
    'Source-supported mechanism: ReaderCardPaginator.paginate starts '
    'request-local pending/output state and flushes each request tail; '
    'ProgressiveDisplayState appends/prepends completed range results without '
    'repacking their seam.';
const p03BoundaryInference =
    'Inference limited to returned evidence: request boundaries preserve '
    'independently finalized islands. No deeper canonical packing rule is '
    'claimed by P03.';
const p03ProhibitedShortcut =
    'Do not update the dynamic full-range reference per order, freeze current '
    'membership as canonical, alter fixture prose/layout, weaken equality, '
    'clear caches, or change identity/version values merely to make this green.';

const _targetFile =
    'test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart';
const _partitionFile =
    'test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart';
const _singletonFile =
    'test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart';
const _cacheFile =
    'test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart';

const _headingReference =
    'card[1] text/heading; source/display/logical: '
    '2:[0,20)@[0,20)|text/chapter-one.xhtml#paragraph-0|heading|[0,20), '
    '3:[0,23)@[22,45)|text/chapter-one.xhtml#paragraph-1|heading|[0,23); '
    'identity=9e9aa12b00f7fe863647bb51d4f2a07c3dd4f8747bc1cf0bc8afd80ebe19951b; '
    'text="Micro Reader Chapter\\n\\nMicro Reader Subsection"';
const _headingActual =
    'card[1] text/heading; source/display/logical: '
    '2:[0,20)@[0,20)|text/chapter-one.xhtml#paragraph-0|heading|[0,20); '
    'identity=4fcae4b0aa322e933ee437d126f1b679402dd44006c4182c7279edad6927e488; '
    'text="Micro Reader Chapter"; successor card owns source 3 alone with '
    'identity=cfaa6057d09a575946490500e8165af1e0486d4738ea0925eb968e74084147b8';
const _mergeReference =
    'card[2] text/paragraph; source/display/logical: '
    '4:[0,10)@[0,10)|paragraph-2, 5:[0,10)@[12,22)|paragraph-3, '
    '6:[0,12)@[24,36)|paragraph-4, 7:[0,198)@[38,236)|paragraph-5; '
    'section=text/chapter-one.xhtml; '
    'identity=f2262c3ecc71e1c568c6938935830134400b22c36d5a168be8f590fe2953ea22; '
    'text="Merge one.\\n\\nMerge two.\\n\\nMerge three.\\n\\nThe deliberate long paragraph begins with a 🚀 marker and continues through forty calm, artificial words so later controlled layouts must split source coverage without changing this authored oracle."';
const _mergeActualSource4 =
    'card[2] text/paragraph; source/display/logical: '
    '4:[0,10)@[0,10)|text/chapter-one.xhtml#paragraph-2|paragraph|[0,10); '
    'identity=57de0bf94a841b8a8cace219053ed0e2809f4ffe3f490cde379903c453721a98; '
    'text="Merge one."; successor owns 5,6,7 with '
    'identity=e709a95ea0d1d6b49f63eb45535a68e0fec015c318159f4faff95b608fe38811';
const _mergeActual456 =
    'card[2] text/paragraph; sources 4:[0,10)@[0,10), '
    '5:[0,10)@[12,22), 6:[0,12)@[24,36); '
    'identity=c7486bc5ed1685a1e4f40ec5cb83bff0096c33c73b04e4f0302c2d64a67f5f88; '
    'text="Merge one.\\n\\nMerge two.\\n\\nMerge three."; successor owns 7,8';
const _mergeActual45 =
    'card[2] text/paragraph; sources 4:[0,10)@[0,10), '
    '5:[0,10)@[12,22); '
    'identity=63afe18a1aae9fbbce7bb49d0cbcbe4987fb90140c0b26e000552800bbd59fc1; '
    'text="Merge one.\\n\\nMerge two."; successor owns 6,7,8';
const _inlineReference =
    'card[6] text/paragraph; sources 12:[0,56)@[0,56), '
    '13:[0,50)@[58,108), 14:[0,37)@[110,147), '
    '15:[0,63)@[149,212); section=text/chapter-one.xhtml; '
    'identity=4ed200ab0ea75831937807c82419f0f12c210d1116f60dd9a468c3ef04217e5b; '
    'text="Inline bold token and italic token stay in source order.\\n\\nA[linked note] remains an inline source structure.\\n\\nFootnote body from the first section.\\n\\nFirst-section seam tail continues into the next spine resource."';
const _inlineActual121314 =
    'card[6] owns sources 12,13,14 only; '
    'identity=0c8c24a59d616574ef1a9ac97eee2aee82aef31760b03260d9e72c3d704facca; '
    'visible text ends at "Footnote body from the first section."; '
    'successor owns source 15 alone';

P03FailureLedgerEntry _boundaryEntry({
  required String id,
  required String testFile,
  required String testName,
  required String scenario,
  required String requests,
  required List<String> requirements,
  required String firstDivergence,
  required String referenceEvidence,
  required String actualEvidence,
  required String repeatability,
  String repairOwner = 'P04',
  String failureClassification = p03BoundaryClassification,
  String sourceSupportedMechanism = p03BoundaryMechanism,
  String laterRepairResponsibility =
      'P04 must define and implement canonical bounded seam continuation.',
}) => P03FailureLedgerEntry(
  id: id,
  testFile: testFile,
  testName: testName,
  scenario: scenario,
  layout: p03StandardLayout,
  requests: requests,
  requirements: requirements,
  approvedInvariant: p03EqualityInvariant,
  referenceAuthority: p03ReferenceAuthority,
  firstDivergence: firstDivergence,
  referenceEvidence: referenceEvidence,
  actualEvidence: actualEvidence,
  coverageResult: p03CompleteCoverage,
  failureClassification: failureClassification,
  repeatability: repeatability,
  repairOwner: repairOwner,
  prohibitedShortcut: p03ProhibitedShortcut,
  observedResult:
      'The returned complete ordered physical-card sequence differs from its '
      'fresh same-layout full-range reference at the recorded card.',
  sourceSupportedMechanism: sourceSupportedMechanism,
  inference: p03BoundaryInference,
  laterRepairResponsibility: laterRepairResponsibility,
);

final List<P03FailureLedgerEntry> p03FailureLedger = <P03FailureLedgerEntry>[
  _boundaryEntry(
    id: 'P03-TARGET-001',
    testFile: _targetFile,
    testName:
        'P03-TARGET-001 first-readable preserves the full physical sequence',
    scenario: 'target-first:first-readable',
    requests: 'target=0; [0,3) target -> [3,20) forward',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[1]; reference predecessor=nav sources 0,1; reference heading owns 2,3; actual heading owns 2 and successor owns 3',
    referenceEvidence: _headingReference,
    actualEvidence: _headingActual,
    repeatability:
        'Three complete-file observations; identical card[1] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-002',
    testFile: _targetFile,
    testName:
        'P03-TARGET-002 generated-toc-structure preserves the full physical sequence',
    scenario: 'target-first:generated-toc-structure',
    requests: 'target=1; [0,3) target -> [3,20) forward',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence: 'card[1]; same heading seam as P03-TARGET-001',
    referenceEvidence: _headingReference,
    actualEvidence: _headingActual,
    repeatability:
        'Three complete-file observations; identical card[1] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-003',
    testFile: _targetFile,
    testName:
        'P03-TARGET-003 chapter-heading preserves the full physical sequence',
    scenario: 'target-first:chapter-heading',
    requests: 'target=2; [1,4) target -> [4,20) forward -> [0,1) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[0]; reference nav card owns sources 0,1; actual card[0] owns source 0 and successor owns source 1',
    referenceEvidence:
        'card[0] sources 0:[0,20)@[0,20), 1:[0,22)@[22,44); nav logical owners; identity=bbcef0bfea79d045d2f660416a6e2510b4d7b147aaf59de8e8e8059d10245654; text="Micro Reader Chapter\\n\\nSecond Section Heading"',
    actualEvidence:
        'card[0] source 0 only; identity=8efb2dede7b9f61738ed4d4c0d6d87e112d16da2f85f92e0746c2e5bac748514; text="Micro Reader Chapter"; successor source 1 identity=1aa6b80de36fd06fe0f984e2d045748161ed0374c6d9706b75812e5a21add866',
    repeatability:
        'Three complete-file observations; identical card[0] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-004',
    testFile: _targetFile,
    testName:
        'P03-TARGET-004 subsection-heading preserves the full physical sequence',
    scenario: 'target-first:subsection-heading',
    requests: 'target=3; [2,5) target -> [5,20) forward -> [0,2) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
      'REQ-012',
      'REQ-013',
      'REQ-027',
      'REQ-032',
      'REQ-033',
      'REQ-034',
      'REQ-048',
      'REQ-051',
    ],
    firstDivergence:
        'card[2]; heading predecessor unchanged; reference sources 4,5,6,7; actual source 4 then successor 5,6,7',
    referenceEvidence: _mergeReference,
    actualEvidence: _mergeActualSource4,
    repeatability:
        'Three complete-file observations; identical card[2] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-005',
    testFile: _targetFile,
    testName:
        'P03-TARGET-005 mergeable-short-prose preserves the full physical sequence',
    scenario: 'target-first:mergeable-short-prose',
    requests: 'target=5; [4,7) target -> [7,20) forward -> [0,4) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
      'REQ-012',
      'REQ-013',
      'REQ-027',
      'REQ-032',
      'REQ-033',
      'REQ-034',
      'REQ-048',
      'REQ-051',
    ],
    firstDivergence:
        'card[2]; reference sources 4,5,6,7; actual 4,5,6 then successor 7,8',
    referenceEvidence: _mergeReference,
    actualEvidence: _mergeActual456,
    repeatability:
        'Three complete-file observations; identical card[2] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-006',
    testFile: _targetFile,
    testName:
        'P03-TARGET-006 long-paragraph preserves the full physical sequence',
    scenario: 'target-first:long-paragraph',
    requests: 'target=7; [6,9) target -> [9,20) forward -> [0,6) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
      'REQ-012',
      'REQ-013',
      'REQ-027',
      'REQ-032',
      'REQ-033',
      'REQ-034',
      'REQ-048',
      'REQ-051',
    ],
    firstDivergence:
        'card[2]; reference sources 4,5,6,7; actual 4,5 then successor 6,7,8',
    referenceEvidence: _mergeReference,
    actualEvidence: _mergeActual45,
    repeatability:
        'Three complete-file observations; identical card[2] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-007',
    testFile: _targetFile,
    testName:
        'P03-TARGET-007 first-repeated-prose preserves the full physical sequence',
    scenario: 'target-first:first-repeated-prose',
    requests: 'target=8; [7,10) target -> [10,20) forward -> [0,7) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
      'REQ-012',
      'REQ-013',
      'REQ-027',
      'REQ-032',
      'REQ-033',
      'REQ-034',
      'REQ-048',
      'REQ-051',
    ],
    firstDivergence:
        'card[2]; reference sources 4,5,6,7; actual 4,5,6 then successor 7,8',
    referenceEvidence: _mergeReference,
    actualEvidence: _mergeActual456,
    repeatability:
        'Three complete-file observations; identical card[2] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-008',
    testFile: _targetFile,
    testName: 'P03-TARGET-008 table preserves the full physical sequence',
    scenario: 'target-first:table',
    requests: 'target=11; [10,13) target -> [13,20) forward -> [0,10) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[4]; repeated-prose predecessor unchanged; reference list card owns 9,10; actual owns 9 and successor owns 10; table follows',
    referenceEvidence:
        'card[4] sources 9:[0,19)@[0,19)|list item 0, 10:[0,18)@[21,39)|list item 1; identity=a550125c97da99487e0a79d9eea691e36284446fbae6232b06ff11ea9d25d90f; text="Ordered item alpha.\\n\\nOrdered item beta."',
    actualEvidence:
        'card[4] source 9 only; identity=556fb0bf80979f34c4516e60bcdf7059433568acf3e05932d0c450926d19ac7a; text="Ordered item alpha."; successor source 10 identity=fd8614e184ec3d399597b37b6ddc39ba9b13c4ac3370608159aa726718462105',
    repeatability:
        'Three complete-file observations; identical card[4] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-009',
    testFile: _targetFile,
    testName:
        'P03-TARGET-009 inline-link-footnote-group preserves the full physical sequence',
    scenario: 'target-first:inline-link-footnote-group',
    requests: 'target=13; [12,15) target -> [15,20) forward -> [0,12) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[6]; table predecessor unchanged; reference owns 12,13,14,15; actual owns 12,13,14 and successor owns 15',
    referenceEvidence: _inlineReference,
    actualEvidence: _inlineActual121314,
    repeatability:
        'Three complete-file observations; identical card[6] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-010',
    testFile: _targetFile,
    testName:
        'P03-TARGET-010 before-spine-seam preserves the full physical sequence',
    scenario: 'target-first:before-spine-seam',
    requests: 'target=15; [14,17) target -> [17,20) forward -> [0,14) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[6]; reference owns 12,13,14,15; actual owns 12,13 and successor owns 14,15',
    referenceEvidence: _inlineReference,
    actualEvidence:
        'card[6] sources 12,13; identity=771334cb6f18ed091bf140cab31b88bd37768462184dcd2809284083cd99af7f; text ends at linked-note content; successor sources 14,15 identity=bb986bc6067239b2e5b0b5df9f59661ad867f796d17b8889e2cbecc502dfce59',
    repeatability:
        'Three complete-file observations; identical card[6] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-011',
    testFile: _targetFile,
    testName:
        'P03-TARGET-011 second-section-heading preserves the full physical sequence',
    scenario: 'target-first:second-section-heading',
    requests: 'target=16; [15,18) target -> [18,20) forward -> [0,15) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[6]; reference owns 12,13,14,15 before section heading; actual owns 12,13,14 and successor owns 15',
    referenceEvidence: _inlineReference,
    actualEvidence: _inlineActual121314,
    repeatability:
        'Three complete-file observations; identical card[6] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-TARGET-012',
    testFile: _targetFile,
    testName:
        'P03-TARGET-012 after-spine-seam preserves the full physical sequence',
    scenario: 'target-first:after-spine-seam',
    requests: 'target=17; [16,19) target -> [19,20) forward -> [0,16) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[8]; section-heading predecessor unchanged; reference owns 17,18,19; actual owns 17,18 and successor owns 19',
    referenceEvidence:
        'card[8] sources 17:[0,52)@[0,52), 18:[0,33)@[54,87), 19:[0,55)@[89,144); chapter-two logical owners; identity=0de27fc7632caaec424955e2e2aae5092654c9713c016cbc26ede79b8d640f53; complete second-section text',
    actualEvidence:
        'card[8] sources 17,18; identity=b44a97d1993c82a983a62dac0e978328a24ec766e600da60849e86adc143cf4d; text ends at repeated marker; successor source 19 identity=8edcb78cd1ffe64241326cd9184e7b6892736497591714df607e570aca529618',
    repeatability:
        'Three complete-file observations; identical card[8] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-FORWARD-001',
    testFile: _partitionFile,
    testName:
        'P03-FORWARD-001 merge-long-repeat-boundaries forward-first equals full range',
    scenario: 'partition:merge-long-repeat-boundaries:forward-first',
    requests: '[0,5) initial -> [5,8) forward -> [8,20) forward',
    requirements: const [
      'REQ-007',
      'REQ-008',
      'REQ-012',
      'REQ-013',
      'REQ-027',
      'REQ-032',
      'REQ-033',
      'REQ-034',
      'REQ-048',
      'REQ-051',
    ],
    firstDivergence:
        'card[2]; reference sources 4,5,6,7; actual source 4; successor owns 5,6,7',
    referenceEvidence: _mergeReference,
    actualEvidence: _mergeActualSource4,
    repeatability:
        'Three complete-file observations; identical card[2] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-PREPEND-001',
    testFile: _partitionFile,
    testName:
        'P03-PREPEND-001 merge-long-repeat-boundaries backward/prepend-first equals full range',
    scenario: 'partition:merge-long-repeat-boundaries:backward-prepend-first',
    requests: '[8,20) target -> [5,8) prepend -> [0,5) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
      'REQ-012',
      'REQ-013',
      'REQ-027',
      'REQ-032',
      'REQ-033',
      'REQ-034',
      'REQ-048',
      'REQ-051',
    ],
    firstDivergence:
        'card[2]; reference sources 4,5,6,7; actual source 4; successor owns 5,6,7',
    referenceEvidence: _mergeReference,
    actualEvidence: _mergeActualSource4,
    repeatability:
        'Three complete-file observations; identical card[2] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-SINGLETON-001',
    testFile: _singletonFile,
    testName:
        'P03-SINGLETON-001 mergeable-prose singleton forward-then-backward equals full range',
    scenario: 'singleton:mergeable-prose:forward-then-backward',
    requests: 'target=5; [5,6) singleton -> [6,20) forward -> [0,5) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
      'REQ-012',
      'REQ-013',
      'REQ-027',
      'REQ-032',
      'REQ-033',
      'REQ-034',
      'REQ-048',
      'REQ-051',
    ],
    firstDivergence:
        'card[2]; reference sources 4,5,6,7; actual source 4; successor is independently flushed singleton source 5 identity=1f1d6286fee84b79c4e69ef2fa6b286b90d9c462bfbc6e13dd0b96d5e41dc79c',
    referenceEvidence: _mergeReference,
    actualEvidence: _mergeActualSource4,
    repeatability:
        'At least three complete-file observations; identical card[2] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-SINGLETON-002',
    testFile: _singletonFile,
    testName:
        'P03-SINGLETON-002 mergeable-prose singleton backward-then-forward equals full range',
    scenario: 'singleton:mergeable-prose:backward-then-forward',
    requests: 'target=5; [5,6) singleton -> [0,5) prepend -> [6,20) forward',
    requirements: const [
      'REQ-007',
      'REQ-008',
      'REQ-012',
      'REQ-013',
      'REQ-027',
      'REQ-032',
      'REQ-033',
      'REQ-034',
      'REQ-048',
      'REQ-051',
    ],
    firstDivergence:
        'card[2]; reference sources 4,5,6,7; actual source 4; successor is independently flushed singleton source 5 identity=1f1d6286fee84b79c4e69ef2fa6b286b90d9c462bfbc6e13dd0b96d5e41dc79c',
    referenceEvidence: _mergeReference,
    actualEvidence: _mergeActualSource4,
    repeatability:
        'At least three complete-file observations; identical card[2] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-SINGLETON-003',
    testFile: _singletonFile,
    testName:
        'P03-SINGLETON-003 heading-boundary singleton forward-then-backward equals full range',
    scenario: 'singleton:heading-boundary:forward-then-backward',
    requests: 'target=3; [3,4) singleton -> [4,20) forward -> [0,3) prepend',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[1]; reference heading owns sources 2,3; actual owns source 2 and successor is singleton source 3',
    referenceEvidence: _headingReference,
    actualEvidence: _headingActual,
    repeatability:
        'At least three complete-file observations; identical card[1] classification; exit 1.',
  ),
  _boundaryEntry(
    id: 'P03-SINGLETON-004',
    testFile: _singletonFile,
    testName:
        'P03-SINGLETON-004 heading-boundary singleton backward-then-forward equals full range',
    scenario: 'singleton:heading-boundary:backward-then-forward',
    requests: 'target=3; [3,4) singleton -> [0,3) prepend -> [4,20) forward',
    requirements: const [
      'REQ-007',
      'REQ-008',
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
    ],
    firstDivergence:
        'card[1]; reference heading owns sources 2,3; actual owns source 2 and successor is singleton source 3',
    referenceEvidence: _headingReference,
    actualEvidence: _headingActual,
    repeatability:
        'At least three complete-file observations; identical card[1] classification; exit 1.',
  ),
  for (final cache in _cacheFailures)
    _boundaryEntry(
      id: cache.id,
      testFile: _cacheFile,
      testName: cache.testName,
      scenario: cache.scenario,
      requests:
          '[0,5) initial -> [5,8) forward -> [8,20) forward; cacheState=${cache.state}',
      requirements: const [
        'REQ-007',
        'REQ-008',
        'REQ-009',
        'REQ-012',
        'REQ-013',
        'REQ-027',
        'REQ-032',
        'REQ-033',
        'REQ-034',
        'REQ-048',
        'REQ-051',
      ],
      firstDivergence:
          'card[2]; heading predecessor unchanged; reference owns sources 4,5,6,7; cache reconstruction owns source 4 then 5,6,7',
      referenceEvidence: '${cache.referenceIdentity}; $_mergeReference',
      actualEvidence:
          '${cache.actualIdentity}; cache-replayed $_mergeActualSource4',
      repeatability:
          'Three complete-file observations; identical card[2] range/text classification; exit 1.',
      repairOwner: cache.state == 'cold-segmented'
          ? 'P04'
          : 'P04 primary; P06 cache compatibility/replay',
      failureClassification:
          '$p03BoundaryClassification Cache state=${cache.state}; storage/reload reproduced the generated island and did not introduce another range/text mismatch.',
      sourceSupportedMechanism: '$p03BoundaryMechanism ${cache.mechanism}',
      laterRepairResponsibility: cache.state == 'cold-segmented'
          ? 'P04 must canonicalize segmented construction.'
          : 'P04 must canonicalize segment boundaries; P06 must then prove compatible cache replay/migration under the canonical contract.',
    ),
];

const _cacheFailures =
    <
      ({
        String id,
        String testName,
        String scenario,
        String state,
        String referenceIdentity,
        String actualIdentity,
        String mechanism,
      })
    >[
      (
        id: 'P03-CACHE-001',
        testName:
            'P03-CACHE-001 cache:merge-long-repeat-known-red cold-segmented equals fresh full range',
        scenario: 'cache:merge-long-repeat-known-red:cold-segmented',
        state: 'cold-segmented',
        referenceIdentity:
            'publication=reader-contract-publication-8; reference identity=268775e73be24b6f8f3e0b9bd3b78fcb2fdacf743ec94c6f628dce57c3d06265',
        actualIdentity:
            'publication=reader-contract-publication-8; actual identity=50a419365d1d926d9a56220c87141d3e3726134f0999d182c636bf43fc90d30c',
        mechanism:
            'Fresh generated results were stored in production memory and segmented stores after assembly.',
      ),
      (
        id: 'P03-CACHE-002',
        testName:
            'P03-CACHE-002 cache:merge-long-repeat-known-red warm-memory equals fresh full range',
        scenario: 'cache:merge-long-repeat-known-red:warm-memory',
        state: 'warm-memory',
        referenceIdentity:
            'publication=reader-contract-publication-9; reference identity=382be7ba1a9768c7357c30291da7d4619eb05e5ed27b8afb3f267739ea3ab38d',
        actualIdentity:
            'publication=reader-contract-publication-9; actual identity=634e758aebe89469de3c8c9798af627da398d12d5dfa8bc0b935783e39c4a308',
        mechanism:
            'DisplaySectionMemoryCache.get hit every exact range and toResult replayed the stored cards.',
      ),
      (
        id: 'P03-CACHE-003',
        testName:
            'P03-CACHE-003 cache:merge-long-repeat-known-red warm-disk equals fresh full range',
        scenario: 'cache:merge-long-repeat-known-red:warm-disk',
        state: 'warm-disk',
        referenceIdentity:
            'publication=reader-contract-publication-10; reference identity=79051c1caed52d4f66d7de6104f5d9547388f8300bf7013140567b37d590d58c',
        actualIdentity:
            'publication=reader-contract-publication-10; actual identity=215822518c97ef6b68ab437a66120a774cc096fa5a868cd8e6c37998c1e7c130',
        mechanism:
            'Memory misses were proved; a fresh SegmentedDisplayCacheService loaded compatible manifest v3 records and deserialized bytes.',
      ),
      (
        id: 'P03-CACHE-004',
        testName:
            'P03-CACHE-004 cache:merge-long-repeat-known-red memory-eviction equals fresh full range',
        scenario: 'cache:merge-long-repeat-known-red:memory-eviction',
        state: 'memory-eviction',
        referenceIdentity:
            'publication=reader-contract-publication-11; reference identity=222c4783c6adcbc75b74e16d8cf6af7d881e57d3dbf901a06d5a1ea58c5df9dd',
        actualIdentity:
            'publication=reader-contract-publication-11; actual identity=fedf04a0f86c46054b62343772b632c0b7dd22fca048ee9c2a55ed9472b02146',
        mechanism:
            'The bounded production memory policy evicted [0,5); reconstruction proved a disk fallback for it and memory hits for retained ranges.',
      ),
      (
        id: 'P03-CACHE-005',
        testName:
            'P03-CACHE-005 cache:merge-long-repeat-known-red close-reopen-reload equals fresh full range',
        scenario: 'cache:merge-long-repeat-known-red:close-reopen-reload',
        state: 'close-reopen-reload',
        referenceIdentity:
            'publication=reader-contract-publication-12; reference identity=36e40a58b517fb261c5f92a6d0bda6992f5021cd3f1fb759258814f1803b21ea',
        actualIdentity:
            'publication=reader-contract-publication-12; actual identity=f97b0ed0f79098e5aeb31657599768b88de124e287119de8abb1afb235b8bcb9',
        mechanism:
            'All writes were awaited; the service exposes no close API, so two fresh service instances independently loaded the persisted records/bytes.',
      ),
    ];

final Map<String, Object?> p03PassingEvidenceSummary = <String, Object?>{
  'resolvedByP04_005':
      'P03-PREPEND-001 is green through bounded canonical forward regeneration; '
      'the historical failure row above remains unchanged.',
  'resolvedByP04_007':
      'P03-CACHE-001 through P03-CACHE-005 are green: real legacy whole, '
      'segmented, memory, eviction/fallback and fresh-service records are '
      'observed, rejected for missing canonical authority, then regenerated '
      'through the canonical session. The five historical rows remain unchanged.',
  'structuralOwnership':
      '6/6 pass: full, target, forward, prepend and both section-heading singleton orders preserve authored structural ownership and complete coverage.',
  'targetFirstPasses': <String>[
    'ordered-list-start target=9 [8,11)->[11,20)->[0,8)',
    'second-repeated-prose target=18 [17,20)->[0,17)',
    'final-readable target=19 [17,20)->[0,17)',
  ],
  'partitionPasses':
      '10/10 pass: forward and bounded canonical backward construction match the full range for every partition plan.',
  'singletonPasses':
      '10/10 pass: both expansion orders match the full range for every singleton plan.',
  'cachePasses':
      '12/12 pass: cold full plus every real segmented/memory/disk/eviction/reload path matches canonical full order after fail-closed regeneration.',
  'coverageAcrossRed': p03CompleteCoverage,
};
