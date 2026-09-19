import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import '../support/reader_contract_fixture.dart';
import '../support/reader_contract_layout_environment.dart';
import 'reader_card_pagination_evidence.dart';

const _fixtureId = 'reader-core-micro-v1';
const _layoutId = 'p03-controlled-lexend-layout';

void main() {
  late Directory temporaryDirectory;
  late List<BookChunk> sourceChunks;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'nalori_reader_p03_full_range_',
    );
    final fixture = (await loadReaderContractFixtureManifest()).fixture(
      _fixtureId,
    );
    final epub = await buildReaderContractFixtureEpub(
      fixture: fixture,
      outputDirectory: temporaryDirectory,
    );
    sourceChunks = (await EpubParserService().loadAndParseFromFile(
      epub,
    )).chunks;
  });

  tearDownAll(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group(
    '[REQ-007, REQ-011, REQ-032, REQ-033, REQ-034, REQ-051] TASK-P03-001',
    () {
      testWidgets(
        'records independently reviewed full-range evidence without canonizing physical-card membership',
        (tester) async {
          const sourceReview = _ReviewedReaderCoreSourceOracle.units;
          final sourceErrors = _sourceOracleErrors(sourceChunks, sourceReview);
          expect(sourceErrors, isEmpty, reason: sourceErrors.join('\n'));

          final diagnosticPhases = <String>[];
          final result = await _paginateFullRange(
            tester: tester,
            sourceChunks: sourceChunks,
            onDiagnostic: (phase, _) => diagnosticPhases.add(phase),
          );
          expect(result.succeeded, isTrue);

          final actual = ReaderCardPaginationEvidence.project(
            result: result,
            sourceChunks: sourceChunks,
            readableSourceExtents: {
              for (final unit in sourceReview)
                unit.index: unit.sourceExtentUtf16,
            },
            publicationFingerprint: _fixtureId,
            layoutFingerprint: _layoutId,
            diagnosticPhases: diagnosticPhases,
          );
          final reviewedFullRange = _reviewedFullRangeEvidence(sourceReview);
          final mismatch = readerCardPaginationEvidenceMismatch(
            constructionLabel: 'TASK-P03-001 full-range',
            expected: reviewedFullRange,
            actual: actual,
          );

          // The card range membership below is a manually reviewed observation
          // of this one full request. It is deliberately not a P03 canonical
          // construction-order expectation; later tasks must compare new
          // construction results through the evidence comparator above.
          expect(mismatch, isNull, reason: mismatch);
          expect(actual.coverage.complete, isTrue, reason: actual.describe());
          expect(
            actual.diagnosticPhases,
            containsAll(<String>[
              'range_generation_begin',
              'range_generation_end',
            ]),
          );
          _expectStructuralOrder(actual);
          _expectDistinctRepeatedProse(actual);

          // This is intentionally emitted for the evidence ledger. It includes
          // every physical card, all source/display/logical ranges, identities,
          // coverage, and only origin classifications observable at this seam.
          // Pending/rebalancing internals have no production diagnostic signal.
          // ignore: avoid_print
          print('TASK-P03-001 full-range evidence:\n${actual.describe()}');
        },
      );
    },
  );
}

Future<DisplayRangeResult> _paginateFullRange({
  required WidgetTester tester,
  required List<BookChunk> sourceChunks,
  required ReaderCardPaginatorDiagnostic onDiagnostic,
}) async {
  final environment = await ReaderContractLayoutEnvironment.install(tester);
  addTearDown(() => environment.close(tester));
  const settings = ReadingSettings();
  final inputs = environment.inputs;
  final metrics = resolveReaderLayoutMetrics(
    inputs.viewportSize,
    inputs.safeArea,
    settings,
  );
  final density = readerDensityPolicy(settings.contentDensity);
  final fontFamily = inputs.font.fontFamily;
  final bodyStyle = TextStyle(
    fontFamily: fontFamily,
    fontSize: settings.fontSizeValue,
    fontWeight: settings.fontWeightValue,
    height: settings.effectiveLineHeight,
    color: settings.readerTextColor,
    locale: inputs.locale,
  );
  final headingStyle = TextStyle(
    fontFamily: fontFamily,
    fontSize: settings.fontSizeValue + (14 * settings.fontSizeMultiplier),
    fontWeight: FontWeight.w900,
    height: ReadingSettings.headingLineHeight,
    color: settings.readerTextColor,
    letterSpacing: 2,
    locale: inputs.locale,
  );
  final scheduler = FrameBudgetedRangeScheduler(yieldToFrame: () async {});
  addTearDown(scheduler.dispose);

  return const ReaderCardPaginator().paginateLegacyForP02(
    ReaderCardPaginatorRequest(
      range: DisplayRangeRequest(
        direction: DisplayRangeDirection.initial,
        sourceRange: SourceChunkRange(0, sourceChunks.length),
        generationId: 3001,
        reason: 'p03_full_range_characterization',
      ),
      sourceChunks: sourceChunks,
      layout: ReaderCardPaginatorLayout(
        availableWidth: metrics.availableWidth,
        pageHeightBudget: metrics.maxTextHeight,
        physicalTextBudget: math.max(
          metrics.maxTextHeight,
          metrics.availableHeight - metrics.safetyBuffer,
        ),
        minUsefulHeight: metrics.minUsefulTextHeight,
        tinyWordCount: density.tinyWordCount,
        tinyHeightRatio: density.tinyHeightRatio,
        settings: settings,
        bodyStyle: bodyStyle,
        headingStyle: headingStyle,
        bodyStrut: StrutStyle(
          fontFamily: fontFamily,
          fontSize: settings.fontSizeValue,
          fontWeight: settings.fontWeightValue,
          height: settings.effectiveLineHeight,
          forceStrutHeight: true,
          leading: 0,
        ),
        headingStrut: StrutStyle(
          fontFamily: fontFamily,
          fontSize: headingStyle.fontSize,
          fontWeight: headingStyle.fontWeight,
          height: ReadingSettings.headingLineHeight,
          forceStrutHeight: true,
          leading: 0,
        ),
        textScaler: TextScaler.linear(inputs.textScaleFactor),
      ),
      scheduler: scheduler,
      priority: DisplayRangeTaskPriority.initialVisible,
      isCancelled: () => false,
      diagnosticBookId: _fixtureId,
      parentGeneration: 3001,
      onDiagnostic: onDiagnostic,
    ),
  );
}

ReaderCardPaginationEvidence _reviewedFullRangeEvidence(
  List<_ReviewedSourceUnit> source,
) {
  final cards = <ReaderCardEvidence>[];
  for (final card in _ReviewedFullRange.cards) {
    final ranges = card.ranges
        .map((range) {
          final unit = source[range.sourceIndex];
          return ReaderCardSourceRangeEvidence(
            sourceIndex: unit.index,
            sourceStartUtf16: range.sourceStartUtf16,
            sourceEndUtf16: range.sourceEndUtf16,
            displayStartUtf16: range.displayStartUtf16,
            displayEndUtf16: range.displayEndUtf16,
            sectionIdentity: unit.sectionIdentity,
            sectionChecksum: 'unknown',
            logicalBlockId: unit.logicalBlockId,
            structuralType: unit.structuralType,
            logicalBlockStartUtf16: 0,
            logicalBlockEndUtf16: unit.sourceExtentUtf16,
          );
        })
        .toList(growable: false);
    cards.add(
      ReaderCardEvidence(
        structuralType: card.structuralType,
        rawText: null,
        visibleText: card.visibleText,
        sourceRanges: ranges,
        identity: const ReaderCardIdentityEvidence(
          publicationFingerprint: _fixtureId,
          layoutFingerprint: _layoutId,
          paginationVersion: 'nalori_cards_v16_lists',
          signature: null,
        ),
        observableOrigins: const [],
      ),
    );
  }
  return ReaderCardPaginationEvidence(
    requestedSourceRange: '[0,${source.length})',
    cards: cards,
    coverage: ReaderSourceCoverageEvidence.fromCards(
      cards: cards,
      readableSourceExtents: {
        for (final unit in source) unit.index: unit.sourceExtentUtf16,
      },
    ),
    diagnosticPhases: const [],
  );
}

List<String> _sourceOracleErrors(
  List<BookChunk> actual,
  List<_ReviewedSourceUnit> expected,
) {
  final errors = <String>[];
  if (actual.length != expected.length) {
    errors.add(
      'independent source oracle expects ${expected.length} units; got ${actual.length}',
    );
  }
  for (
    var index = 0;
    index < actual.length && index < expected.length;
    index++
  ) {
    final source = actual[index];
    final review = expected[index];
    if (source.index != review.index) {
      errors.add(
        'source[$index] index expected ${review.index}; got ${source.index}',
      );
    }
    if (source.sourceFile != review.sectionIdentity) {
      errors.add(
        'source[$index] section expected ${review.sectionIdentity}; got ${source.sourceFile}',
      );
    }
    final structuralType = source.isHeading ? 'heading' : source.blockRole.name;
    if (structuralType != review.structuralType) {
      errors.add(
        'source[$index] structure expected ${review.structuralType}; got $structuralType',
      );
    }
    final visible = source.text ?? '';
    if (visible.length != review.sourceExtentUtf16) {
      errors.add(
        'source[$index] UTF-16 extent expected ${review.sourceExtentUtf16}; got ${visible.length}',
      );
    }
  }
  return errors;
}

void _expectStructuralOrder(ReaderCardPaginationEvidence evidence) {
  final flattened = evidence.cards
      .expand((card) => card.sourceRanges.map((range) => range.sourceIndex))
      .toList(growable: false);
  expect(
    flattened,
    containsAllInOrder(<int>[2, 3, 9, 10, 11, 14, 15, 16, 17]),
    reason: evidence.describe(),
  );
}

void _expectDistinctRepeatedProse(ReaderCardPaginationEvidence evidence) {
  final occurrences = <ReaderCardSourceRangeEvidence>[];
  for (final card in evidence.cards) {
    if (card.visibleText.contains('The repeated marker appears here.')) {
      occurrences.addAll(
        card.sourceRanges.where(
          (range) => range.sourceIndex == 8 || range.sourceIndex == 18,
        ),
      );
    }
  }
  expect(occurrences.map((range) => range.sourceIndex), <int>[8, 18]);
  expect(
    occurrences.map((range) => range.logicalBlockId).toSet().length,
    2,
    reason: evidence.describe(),
  );
}

final class _ReviewedSourceUnit {
  const _ReviewedSourceUnit({
    required this.index,
    required this.sectionIdentity,
    required this.logicalBlockId,
    required this.structuralType,
    required this.sourceExtentUtf16,
  });

  final int index;
  final String sectionIdentity;
  final String logicalBlockId;
  final String structuralType;
  final int sourceExtentUtf16;
}

abstract final class _ReviewedReaderCoreSourceOracle {
  // These source units were transcribed from the manifest's two ordered spine
  // texts and the visible chapter-one/chapter-two XHTML. They intentionally
  // contain no physical-card signatures or count oracle.
  static const units = <_ReviewedSourceUnit>[
    _ReviewedSourceUnit(
      index: 0,
      sectionIdentity: 'nav.xhtml',
      logicalBlockId: 'nav.xhtml#list-0#item-0#block-0',
      structuralType: 'paragraph',
      sourceExtentUtf16: 20,
    ),
    _ReviewedSourceUnit(
      index: 1,
      sectionIdentity: 'nav.xhtml',
      logicalBlockId: 'nav.xhtml#list-0#item-1#block-0',
      structuralType: 'paragraph',
      sourceExtentUtf16: 22,
    ),
    _ReviewedSourceUnit(
      index: 2,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-0',
      structuralType: 'heading',
      sourceExtentUtf16: 20,
    ),
    _ReviewedSourceUnit(
      index: 3,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-1',
      structuralType: 'heading',
      sourceExtentUtf16: 23,
    ),
    _ReviewedSourceUnit(
      index: 4,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-2',
      structuralType: 'paragraph',
      sourceExtentUtf16: 10,
    ),
    _ReviewedSourceUnit(
      index: 5,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-3',
      structuralType: 'paragraph',
      sourceExtentUtf16: 10,
    ),
    _ReviewedSourceUnit(
      index: 6,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-4',
      structuralType: 'paragraph',
      sourceExtentUtf16: 12,
    ),
    _ReviewedSourceUnit(
      index: 7,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-5',
      structuralType: 'paragraph',
      sourceExtentUtf16: 198,
    ),
    _ReviewedSourceUnit(
      index: 8,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-6',
      structuralType: 'paragraph',
      sourceExtentUtf16: 33,
    ),
    _ReviewedSourceUnit(
      index: 9,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#list-0#item-0#block-0',
      structuralType: 'paragraph',
      sourceExtentUtf16: 19,
    ),
    _ReviewedSourceUnit(
      index: 10,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#list-0#item-1#block-0',
      structuralType: 'paragraph',
      sourceExtentUtf16: 18,
    ),
    _ReviewedSourceUnit(
      index: 11,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-9',
      structuralType: 'table',
      sourceExtentUtf16: 136,
    ),
    _ReviewedSourceUnit(
      index: 12,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-10',
      structuralType: 'paragraph',
      sourceExtentUtf16: 56,
    ),
    _ReviewedSourceUnit(
      index: 13,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-11',
      structuralType: 'paragraph',
      sourceExtentUtf16: 50,
    ),
    _ReviewedSourceUnit(
      index: 14,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-12',
      structuralType: 'paragraph',
      sourceExtentUtf16: 37,
    ),
    _ReviewedSourceUnit(
      index: 15,
      sectionIdentity: 'text/chapter-one.xhtml',
      logicalBlockId: 'text/chapter-one.xhtml#paragraph-13',
      structuralType: 'paragraph',
      sourceExtentUtf16: 63,
    ),
    _ReviewedSourceUnit(
      index: 16,
      sectionIdentity: 'text/chapter-two.xhtml',
      logicalBlockId: 'text/chapter-two.xhtml#paragraph-0',
      structuralType: 'heading',
      sourceExtentUtf16: 22,
    ),
    _ReviewedSourceUnit(
      index: 17,
      sectionIdentity: 'text/chapter-two.xhtml',
      logicalBlockId: 'text/chapter-two.xhtml#paragraph-1',
      structuralType: 'paragraph',
      sourceExtentUtf16: 52,
    ),
    _ReviewedSourceUnit(
      index: 18,
      sectionIdentity: 'text/chapter-two.xhtml',
      logicalBlockId: 'text/chapter-two.xhtml#paragraph-2',
      structuralType: 'paragraph',
      sourceExtentUtf16: 33,
    ),
    _ReviewedSourceUnit(
      index: 19,
      sectionIdentity: 'text/chapter-two.xhtml',
      logicalBlockId: 'text/chapter-two.xhtml#paragraph-3',
      structuralType: 'paragraph',
      sourceExtentUtf16: 55,
    ),
  ];
}

final class _ReviewedCardRange {
  const _ReviewedCardRange(
    this.sourceIndex,
    this.sourceStartUtf16,
    this.sourceEndUtf16,
    this.displayStartUtf16,
    this.displayEndUtf16,
  );

  final int sourceIndex;
  final int sourceStartUtf16;
  final int sourceEndUtf16;
  final int displayStartUtf16;
  final int displayEndUtf16;
}

final class _ReviewedCard {
  const _ReviewedCard({
    required this.structuralType,
    required this.visibleText,
    required this.ranges,
  });

  final String structuralType;
  final String visibleText;
  final List<_ReviewedCardRange> ranges;
}

abstract final class _ReviewedFullRange {
  // Each boundary was reviewed against the named XHTML anchors. This is the
  // observed membership of one complete request, not an approved canonical
  // membership across target/append/prepend/cache construction orders.
  static const cards = <_ReviewedCard>[
    _ReviewedCard(
      structuralType: 'text/paragraph',
      visibleText: 'Micro Reader Chapter\n\nSecond Section Heading',
      ranges: [
        _ReviewedCardRange(0, 0, 20, 0, 20),
        _ReviewedCardRange(1, 0, 22, 22, 44),
      ],
    ),
    _ReviewedCard(
      structuralType: 'text/heading',
      visibleText: 'Micro Reader Chapter\n\nMicro Reader Subsection',
      ranges: [
        _ReviewedCardRange(2, 0, 20, 0, 20),
        _ReviewedCardRange(3, 0, 23, 22, 45),
      ],
    ),
    _ReviewedCard(
      structuralType: 'text/paragraph',
      visibleText:
          'Merge one.\n\nMerge two.\n\nMerge three.\n\nThe deliberate long paragraph begins with a 🚀 marker and continues through forty calm, artificial words so later controlled layouts must split source coverage without changing this authored oracle.',
      ranges: [
        _ReviewedCardRange(4, 0, 10, 0, 10),
        _ReviewedCardRange(5, 0, 10, 12, 22),
        _ReviewedCardRange(6, 0, 12, 24, 36),
        _ReviewedCardRange(7, 0, 198, 38, 236),
      ],
    ),
    _ReviewedCard(
      structuralType: 'text/paragraph',
      visibleText: 'The repeated marker appears here.',
      ranges: [_ReviewedCardRange(8, 0, 33, 0, 33)],
    ),
    _ReviewedCard(
      structuralType: 'text/paragraph',
      visibleText: 'Ordered item alpha.\n\nOrdered item beta.',
      ranges: [
        _ReviewedCardRange(9, 0, 19, 0, 19),
        _ReviewedCardRange(10, 0, 18, 21, 39),
      ],
    ),
    _ReviewedCard(
      structuralType: 'text/table',
      visibleText: 'Column Value North Seven',
      ranges: [_ReviewedCardRange(11, 0, 136, 0, 136)],
    ),
    _ReviewedCard(
      structuralType: 'text/paragraph',
      visibleText:
          'Inline bold token and italic token stay in source order.\n\nA[linked note] remains an inline source structure.\n\nFootnote body from the first section.\n\nFirst-section seam tail continues into the next spine resource.',
      ranges: [
        _ReviewedCardRange(12, 0, 56, 0, 56),
        _ReviewedCardRange(13, 0, 50, 58, 108),
        _ReviewedCardRange(14, 0, 37, 110, 147),
        _ReviewedCardRange(15, 0, 63, 149, 212),
      ],
    ),
    _ReviewedCard(
      structuralType: 'text/heading',
      visibleText: 'Second Section Heading',
      ranges: [_ReviewedCardRange(16, 0, 22, 0, 22)],
    ),
    _ReviewedCard(
      structuralType: 'text/paragraph',
      visibleText:
          'Second-section seam head follows the first resource.\n\nThe repeated marker appears here.\n\nSecond section closes the deterministic source fixture.',
      ranges: [
        _ReviewedCardRange(17, 0, 52, 0, 52),
        _ReviewedCardRange(18, 0, 33, 54, 87),
        _ReviewedCardRange(19, 0, 55, 89, 144),
      ],
    ),
  ];
}
