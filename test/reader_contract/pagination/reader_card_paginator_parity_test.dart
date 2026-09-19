import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/utils/reader_content_parser.dart';

import '../support/reader_contract_fixture.dart';
import '../support/reader_contract_layout_environment.dart';

void main() {
  late Directory temporaryDirectory;
  late List<BookChunk> sourceChunks;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'nalori_reader_paginator_parity_',
    );
    final fixture = (await loadReaderContractFixtureManifest()).fixture(
      'reader-core-micro-v1',
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

  group('[REQ-032, REQ-033, REQ-034] production paginator extraction parity', () {
    testWidgets(
      'full trusted fixture exposes ordered ranges identities text and structure',
      (tester) async {
        final result = await _paginate(
          tester: tester,
          sourceChunks: sourceChunks,
          range: SourceChunkRange(0, sourceChunks.length),
          generationId: 1,
        );

        expect(result.succeeded, isTrue);
        expect(result.request.sourceRange.start, 0);
        expect(result.request.sourceRange.endExclusive, sourceChunks.length);
        expect(result.inspectedSourceChunks, sourceChunks.length);
        expect(_snapshot(result, sourceChunks), _fullParityBaseline);
      },
    );

    testWidgets('anchor finalization preserves the current early result', (
      tester,
    ) async {
      final anchorIndex = sourceChunks.indexWhere(
        (chunk) => (chunk.text ?? '').contains('The repeated marker'),
      );
      expect(anchorIndex, greaterThanOrEqualTo(0));

      final result = await _paginate(
        tester: tester,
        sourceChunks: sourceChunks,
        range: SourceChunkRange(anchorIndex, sourceChunks.length),
        generationId: 2,
        finalizeAnchor: ReaderCardPaginatorAnchor(
          sourceIndex: anchorIndex,
          textOffset: 4,
        ),
      );

      expect(result.succeeded, isTrue);
      expect(
        result.request.sourceRange.endExclusive,
        lessThan(sourceChunks.length),
      );
      expect(_snapshot(result, sourceChunks), _anchorParityBaseline);
    });

    testWidgets('a partial request still flushes its range-local tail', (
      tester,
    ) async {
      final start = sourceChunks.indexWhere(
        (chunk) => (chunk.text ?? '').contains('Merge one.'),
      );
      expect(start, greaterThanOrEqualTo(0));
      final endExclusive = math.min(sourceChunks.length, start + 4);

      final result = await _paginate(
        tester: tester,
        sourceChunks: sourceChunks,
        range: SourceChunkRange(start, endExclusive),
        generationId: 3,
      );

      expect(result.succeeded, isTrue);
      expect(result.displayChunks, isNotEmpty);
      expect(
        result.displayToOriginal.last,
        contains(sourceChunks[endExclusive - 1].index),
      );
      expect(_snapshot(result, sourceChunks), _tailParityBaseline);
    });

    testWidgets('explicit cancellation returns the existing classification', (
      tester,
    ) async {
      final result = await _paginate(
        tester: tester,
        sourceChunks: sourceChunks,
        range: SourceChunkRange(0, sourceChunks.length),
        generationId: 4,
        cancelled: true,
      );

      expect(result.cancelled, isTrue);
      expect(result.succeeded, isFalse);
      expect(result.error, isNull);
      expect(result.displayChunks, isEmpty);
      expect(result.displayToOriginal, isEmpty);
      expect(result.originalToDisplay, isEmpty);
      expect(
        result.request.sourceRange.toString(),
        '[0,${sourceChunks.length})',
      );
    });
  });
}

Future<DisplayRangeResult> _paginate({
  required WidgetTester tester,
  required List<BookChunk> sourceChunks,
  required SourceChunkRange range,
  required int generationId,
  ReaderCardPaginatorAnchor? finalizeAnchor,
  bool cancelled = false,
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
        sourceRange: range,
        generationId: generationId,
        reason: 'p02_extraction_parity',
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
      isCancelled: () => cancelled,
      diagnosticBookId: 'reader-core-micro-v1',
      parentGeneration: generationId,
      finalizeAnchor: finalizeAnchor,
    ),
  );
}

Map<String, Object?> _snapshot(
  DisplayRangeResult result,
  List<BookChunk> sourceChunks,
) {
  final cards = <Map<String, Object?>>[];
  final visibleText = <String>[];
  for (var index = 0; index < result.displayChunks.length; index++) {
    final card = result.displayChunks[index];
    ReaderTableBlock? table;
    if (card.blockRole == BookBlockRole.table) {
      for (final block in parseReaderContentBlocks(card.text ?? '')) {
        if (block.table != null) {
          table = block.table;
          break;
        }
      }
    }
    visibleText.add(
      table == null
          ? card.text ?? ''
          : table.logicalText.replaceAll(RegExp(r'\s+'), ' ').trim(),
    );
    final identity = ReaderCardIdentity.fromCard(
      publicationFingerprint: 'reader-core-micro-v1',
      layoutFingerprint: 'p02-controlled-lexend-layout',
      card: card,
      sourceChunks: sourceChunks,
      sourceIndices: result.displayToOriginal[index],
      locationsBySourceIndex: const {},
    );
    cards.add(<String, Object?>{
      'text': card.text,
      'structure':
          '${card.type.name}/'
          '${card.isHeading ? 'heading' : card.blockRole.name}',
      'sourceIndices': result.displayToOriginal[index],
      'ranges': card.effectiveSourceRanges
          .map(
            (range) =>
                '${range.originalChunkIndex}:'
                '${range.originalStartOffset}-${range.originalEndOffset}@'
                '${range.displayStartOffset}-${range.displayEndOffset}',
          )
          .toList(),
      'identityHeader':
          '${identity.publicationFingerprint}|'
          '${identity.layoutFingerprint}|${identity.paginationVersion}',
      'identityRanges': identity.ranges
          .map(
            (range) =>
                '${range.sectionIdentity}|${range.sectionChecksum}|'
                '${range.logicalBlockId}|${range.structuralType}|'
                '${range.startUtf16}-${range.endUtf16}',
          )
          .toList(),
      'identitySignature': identity.signature,
    });
  }
  return <String, Object?>{
    'requested': result.request.sourceRange.toString(),
    'inspected': result.inspectedSourceChunks,
    'cancelled': result.cancelled,
    'visibleText': visibleText,
    'cards': cards,
  };
}

// This is a frozen P02 extraction baseline for one controlled layout. It is
// deliberately not a canonical card oracle and makes no construction-order
// equivalence claim.
const _identityHeader =
    'reader-core-micro-v1|p02-controlled-lexend-layout|'
    'nalori_cards_v16_lists';

const _mergeLongCard = <String, Object?>{
  'text':
      'Merge one.\n\nMerge two.\n\nMerge three.\n\n'
      'The deliberate long paragraph begins with a 🚀 marker and continues '
      'through forty calm, artificial words so later controlled layouts must '
      'split source coverage without changing this authored oracle.',
  'structure': 'text/paragraph',
  'sourceIndices': <int>[4, 5, 6, 7],
  'ranges': <String>[
    '4:0-10@0-10',
    '5:0-10@12-22',
    '6:0-12@24-36',
    '7:0-198@38-236',
  ],
  'identityHeader': _identityHeader,
  'identityRanges': <String>[
    'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-2|paragraph|0-10',
    'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-3|paragraph|0-10',
    'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-4|paragraph|0-12',
    'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-5|paragraph|0-198',
  ],
  'identitySignature':
      'a5359dd65eed855dabd8a5463b0a04d73c7a5380cedca86a9ce670949cf64906',
};

const _fullParityBaseline = <String, Object?>{
  'requested': '[0,20)',
  'inspected': 20,
  'cancelled': false,
  'visibleText': <String>[
    'Micro Reader Chapter\n\nSecond Section Heading',
    'Micro Reader Chapter\n\nMicro Reader Subsection',
    'Merge one.\n\nMerge two.\n\nMerge three.\n\n'
        'The deliberate long paragraph begins with a 🚀 marker and continues '
        'through forty calm, artificial words so later controlled layouts '
        'must split source coverage without changing this authored oracle.',
    'The repeated marker appears here.',
    'Ordered item alpha.\n\nOrdered item beta.',
    'Column Value North Seven',
    'Inline bold token and italic token stay in source order.\n\n'
        'A[linked note] remains an inline source structure.\n\n'
        'Footnote body from the first section.\n\n'
        'First-section seam tail continues into the next spine resource.',
    'Second Section Heading',
    'Second-section seam head follows the first resource.\n\n'
        'The repeated marker appears here.\n\n'
        'Second section closes the deterministic source fixture.',
  ],
  'cards': <Map<String, Object?>>[
    <String, Object?>{
      'text': 'Micro Reader Chapter\n\nSecond Section Heading',
      'structure': 'text/paragraph',
      'sourceIndices': <int>[0, 1],
      'ranges': <String>['0:0-20@0-20', '1:0-22@22-44'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'nav.xhtml|unknown|nav.xhtml#list-0#item-0#block-0|paragraph|0-20',
        'nav.xhtml|unknown|nav.xhtml#list-0#item-1#block-0|paragraph|0-22',
      ],
      'identitySignature':
          '900dcb5cd6f865b023e2993eddc2af0717708ed7e97eacc90bd428169b801ad2',
    },
    <String, Object?>{
      'text': 'Micro Reader Chapter\n\nMicro Reader Subsection',
      'structure': 'text/heading',
      'sourceIndices': <int>[2, 3],
      'ranges': <String>['2:0-20@0-20', '3:0-23@22-45'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-0|heading|0-20',
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-1|heading|0-23',
      ],
      'identitySignature':
          'c65ab813c185dcb053f18212e692cb32185eb9bdcf0dd3727b9e91dcbc0d027e',
    },
    _mergeLongCard,
    <String, Object?>{
      'text': 'The repeated marker appears here.',
      'structure': 'text/paragraph',
      'sourceIndices': <int>[8],
      'ranges': <String>['8:0-33@0-33'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-6|paragraph|0-33',
      ],
      'identitySignature':
          '80da94b0e869efae9a7bc7997053d8327d404fd3f3897bad890aac1e074fbfb3',
    },
    <String, Object?>{
      'text': 'Ordered item alpha.\n\nOrdered item beta.',
      'structure': 'text/paragraph',
      'sourceIndices': <int>[9, 10],
      'ranges': <String>['9:0-19@0-19', '10:0-18@21-39'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#list-0#item-0#block-0|paragraph|0-19',
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#list-0#item-1#block-0|paragraph|0-18',
      ],
      'identitySignature':
          '0f99c5663483c1a5e281e37368ca4b7ba9e51afba5e14336f2c8051211b55f63',
    },
    <String, Object?>{
      'text':
          'NALORI_TABLE_V1:eyJyb3dzIjpbW3sidCI6IkNvbHVtbiIsImgiOnRydWV9LHsidCI6IlZhbHVlIiwiaCI6dHJ1ZX1dLFt7InQiOiJOb3J0aCJ9LHsidCI6IlNldmVuIn1dXX0=',
      'structure': 'text/table',
      'sourceIndices': <int>[11],
      'ranges': <String>['11:0-136@0-136'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-9|table|0-136',
      ],
      'identitySignature':
          '6390952d896803c796cbf9d53e385fd176472a30f1e6be2ef99e55650342f8eb',
    },
    <String, Object?>{
      'text':
          'Inline bold token and italic token stay in source order.\n\n'
          'A[linked note] remains an inline source structure.\n\n'
          'Footnote body from the first section.\n\n'
          'First-section seam tail continues into the next spine resource.',
      'structure': 'text/paragraph',
      'sourceIndices': <int>[12, 13, 14, 15],
      'ranges': <String>[
        '12:0-56@0-56',
        '13:0-50@58-108',
        '14:0-37@110-147',
        '15:0-63@149-212',
      ],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-10|paragraph|0-56',
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-11|paragraph|0-50',
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-12|paragraph|0-37',
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-13|paragraph|0-63',
      ],
      'identitySignature':
          'd6390d57d281d9c783feb6ce8e5b292395ed2bdbd47dd5c43f134d87c2a68316',
    },
    <String, Object?>{
      'text': 'Second Section Heading',
      'structure': 'text/heading',
      'sourceIndices': <int>[16],
      'ranges': <String>['16:0-22@0-22'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-two.xhtml|unknown|text/chapter-two.xhtml#paragraph-0|heading|0-22',
      ],
      'identitySignature':
          '8202c7593986184e7bd43ce6e2dd5c43922af33bc6f902f79adee6ff2215eee5',
    },
    <String, Object?>{
      'text':
          'Second-section seam head follows the first resource.\n\n'
          'The repeated marker appears here.\n\n'
          'Second section closes the deterministic source fixture.',
      'structure': 'text/paragraph',
      'sourceIndices': <int>[17, 18, 19],
      'ranges': <String>['17:0-52@0-52', '18:0-33@54-87', '19:0-55@89-144'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-two.xhtml|unknown|text/chapter-two.xhtml#paragraph-1|paragraph|0-52',
        'text/chapter-two.xhtml|unknown|text/chapter-two.xhtml#paragraph-2|paragraph|0-33',
        'text/chapter-two.xhtml|unknown|text/chapter-two.xhtml#paragraph-3|paragraph|0-55',
      ],
      'identitySignature':
          '5f823ecc03e20c9bf069c1ac4b831bbc2b2d5dbd20b4fa755afda489af72bb4e',
    },
  ],
};

const _anchorParityBaseline = <String, Object?>{
  'requested': '[8,10)',
  'inspected': 2,
  'cancelled': false,
  'visibleText': <String>[
    'The repeated marker appears here.',
    'Ordered item alpha.',
  ],
  'cards': <Map<String, Object?>>[
    <String, Object?>{
      'text': 'The repeated marker appears here.',
      'structure': 'text/paragraph',
      'sourceIndices': <int>[8],
      'ranges': <String>['8:0-33@0-33'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#paragraph-6|paragraph|0-33',
      ],
      'identitySignature':
          '80da94b0e869efae9a7bc7997053d8327d404fd3f3897bad890aac1e074fbfb3',
    },
    <String, Object?>{
      'text': 'Ordered item alpha.',
      'structure': 'text/paragraph',
      'sourceIndices': <int>[9],
      'ranges': <String>['9:0-19@0-19'],
      'identityHeader': _identityHeader,
      'identityRanges': <String>[
        'text/chapter-one.xhtml|unknown|text/chapter-one.xhtml#list-0#item-0#block-0|paragraph|0-19',
      ],
      'identitySignature':
          'eacd73379a3838a08768bf5dd2147aa8bf99a8592e6134d38eee2776afd83c40',
    },
  ],
};

const _tailParityBaseline = <String, Object?>{
  'requested': '[4,8)',
  'inspected': 4,
  'cancelled': false,
  'visibleText': <String>[
    'Merge one.\n\nMerge two.\n\nMerge three.\n\n'
        'The deliberate long paragraph begins with a 🚀 marker and continues '
        'through forty calm, artificial words so later controlled layouts '
        'must split source coverage without changing this authored oracle.',
  ],
  'cards': <Map<String, Object?>>[_mergeLongCard],
};
