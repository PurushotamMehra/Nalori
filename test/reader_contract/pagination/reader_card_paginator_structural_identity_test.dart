import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/book_list_semantics.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/utils/reader_content_parser.dart';

import 'reader_core_pagination_harness.dart';

void main() {
  late ReaderCoreParsedFixture fixture;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load(
      'nalori_reader_p04_006_structure_',
    );
  });

  tearDownAll(() => fixture.close());

  group('[TASK-P04-006] finalized canonical structural ownership', () {
    testWidgets(
      'source headings, navigation, lists, repeated prose, rich text, and seams own stable ordered ranges',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final cards = await _runForwardToEnd(
          harness.canonicalSessionForP04(),
          harness,
        );
        final slices = cards.expand((card) => card.sourceSlices).toList();

        expect(_rolesFor(slices, 0), {'source:navigation'});
        expect(_rolesFor(slices, 1), {'source:navigation'});
        expect(_rolesFor(slices, 2), {'source:heading'});
        expect(_rolesFor(slices, 3), {'source:heading'});
        expect(_rolesFor(slices, 9), {'source:list'});
        expect(_rolesFor(slices, 10), {'source:list'});

        final repeatedOne = _slicesFor(slices, 8).single;
        final repeatedTwo = _slicesFor(slices, 18).single;
        expect(fixture.sourceChunks[8].text, fixture.sourceChunks[18].text);
        expect(repeatedOne.sourceIdentity, isNot(repeatedTwo.sourceIdentity));
        expect(
          repeatedOne.logicalOwnerIdentity,
          isNot(repeatedTwo.logicalOwnerIdentity),
        );

        for (final sourceOrdinal in const [0, 12, 13]) {
          final source = fixture.sourceChunks[sourceOrdinal];
          final owned = _slicesFor(slices, sourceOrdinal).single;
          final fragment = buildCanonicalTextFragment(
            source,
            0,
            source.text!.length,
          );
          expect(owned.richMetadataDigest, isNotEmpty);
          expect(
            fragment.inlineStyles?.map((value) => value.toJson()).toList(),
            source.inlineStyles?.map((value) => value.toJson()).toList(),
          );
          expect(
            fragment.links?.map((value) => value.toJson()).toList(),
            source.links?.map((value) => value.toJson()).toList(),
          );
          expect(
            fragment.footnotes?.map((value) => value.toJson()).toList(),
            source.footnotes?.map((value) => value.toJson()).toList(),
          );
        }

        final seamTail = _slicesFor(slices, 15).single;
        final seamHead = _slicesFor(slices, 16).single;
        expect(seamTail.sectionIdentity, isNot(seamHead.sectionIdentity));
        expect(seamTail.spineIdentity, isNot(seamHead.spineIdentity));
        expect(
          cards.any(
            (card) =>
                card.sourceSlices.any(
                  (slice) => slice.sourceOrdinalHint == 15,
                ) &&
                card.sourceSlices.any((slice) => slice.sourceOrdinalHint == 16),
          ),
          isFalse,
        );

        for (final card in cards) {
          expect(card.identity.ranges, hasLength(card.sourceSlices.length));
          for (var index = 0; index < card.sourceSlices.length; index++) {
            final slice = card.sourceSlices[index];
            final range = card.identity.ranges[index];
            expect(range.hasCanonicalStructuralOwnership, isTrue);
            expect(range.sourceIdentity, slice.sourceIdentity);
            expect(range.spineIdentity, slice.spineIdentity);
            expect(range.structuralOwnerRole, slice.structuralOwnerRole);
            expect(range.fragmentDigest, slice.fragmentDigest);
          }
        }
      },
    );

    testWidgets(
      'split paragraph start/middle/end ownership is UTF-16 adjacent and preserves explicit full-span split provenance',
      (tester) async {
        final splitHarness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
          layout: ReaderCorePaginationLayout.splitStress,
        );
        final cards = await _runForwardToEnd(
          splitHarness.canonicalSessionForP04(),
          splitHarness,
        );
        final fragments = _slicesFor(
          cards.expand((card) => card.sourceSlices).toList(),
          7,
        );
        expect(
          fragments.map((slice) => (slice.startUtf16, slice.endUtf16)).toList(),
          const [(0, 58), (58, 125), (125, 191), (191, 198)],
        );
        expect(fragments.first.isLogicalParagraphStart, isTrue);
        expect(fragments.first.isLogicalParagraphEnd, isFalse);
        expect(fragments[1].isLogicalParagraphStart, isFalse);
        expect(fragments[1].isLogicalParagraphEnd, isFalse);
        expect(fragments.last.isLogicalParagraphStart, isFalse);
        expect(fragments.last.isLogicalParagraphEnd, isTrue);
        expect(
          fragments.map((slice) => slice.fragmentDigest).toSet(),
          hasLength(fragments.length),
        );
        final sourceText = fixture.sourceChunks[7].text!;
        for (final fragment in fragments) {
          expect(
            _splitsSurrogatePair(sourceText, fragment.startUtf16!),
            isFalse,
          );
          expect(_splitsSurrogatePair(sourceText, fragment.endUtf16!), isFalse);
        }

        final fullSpanSource = _text(
          0,
          'First deliberately short sentence. Second short sentence.',
          owner: 'full-span-split-owner',
        );
        final fullSpanHarness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: <BookChunk>[fullSpanSource],
        );
        final fullSpanCards = await _runForwardToEnd(
          fullSpanHarness.canonicalSessionForP04(),
          fullSpanHarness,
        );
        final fullSpan = fullSpanCards.single.sourceSlices.single;
        expect(
          (fullSpan.startUtf16, fullSpan.endUtf16),
          (0, fullSpanSource.text!.length),
        );
        expect(fullSpan.usesExplicitTextFragment, isTrue);
        expect(
          fullSpanCards.single.identity.ranges.single.usesExplicitTextFragment,
          isTrue,
        );
      },
    );

    testWidgets(
      'compatible headings retain complete ordered membership in one finalized identity',
      (tester) async {
        final sources = <BookChunk>[
          _heading(0, 'Generated chapter title', owner: 'heading-owner-0'),
          _heading(1, 'Generated subsection title', owner: 'heading-owner-1'),
        ];
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final cards = await _runForwardToEnd(
          harness.canonicalSessionForP04(),
          harness,
        );
        expect(cards, hasLength(1));
        expect(
          cards.single.sourceSlices
              .map((slice) => slice.logicalOwnerIdentity)
              .toList(),
          const ['heading-owner-0', 'heading-owner-1'],
        );
        expect(
          cards.single.identity.ranges
              .map((range) => range.logicalBlockId)
              .toList(),
          const ['heading-owner-0', 'heading-owner-1'],
        );
      },
    );

    testWidgets(
      'table fragments own exact ordered row intervals and decoded visible content',
      (tester) async {
        final table = ReaderTableBlock(
          headers: const ['Column', 'Value'],
          rows: <List<String>>[
            for (var row = 0; row < 10; row++) ['row-$row', 'value-$row'],
          ],
        );
        final source = BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: encodeReaderTableBlock(table),
          blockRole: BookBlockRole.table,
          preserveLineBreaks: true,
          sourceFile: 'table.xhtml',
          logicalParagraphId: 'table.xhtml#table-owner',
        );
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: <BookChunk>[source],
        );
        final session = CanonicalReaderPaginationSession(
          sourceSnapshot: _snapshot(<BookChunk>[source]),
          controlledLayoutIdentity: 'p04-006-table-layout',
          layout: _layoutWithHeight(harness.paginatorLayout, 90),
        );
        final cards = await _runForwardToEnd(session, harness);
        final slices = cards.expand((card) => card.sourceSlices).toList();
        expect(slices.length, greaterThan(1));
        expect(slices.first.tableRowStart, 0);
        expect(slices.last.tableRowEndExclusive, table.rows.length);
        for (var index = 1; index < slices.length; index++) {
          expect(
            slices[index - 1].tableRowEndExclusive,
            slices[index].tableRowStart,
          );
        }
        final decodedRows = <List<String>>[];
        for (var index = 0; index < cards.length; index++) {
          final slice = cards[index].sourceSlices.single;
          final block = parseReaderContentBlocks(
            cards[index].card.text!,
          ).single;
          expect(block.table, isNotNull);
          expect(block.table!.headers, table.headers);
          decodedRows.addAll(block.table!.rows);
          final range = cards[index].identity.ranges.single;
          expect(range.structuralOwnerRole, 'source:table');
          expect(range.tableRowStart, slice.tableRowStart);
          expect(range.tableRowEndExclusive, slice.tableRowEndExclusive);
        }
        expect(decodedRows, table.rows);
      },
    );

    testWidgets(
      'generated title/navigation, image, and milestone use intrinsic stable owners',
      (tester) async {
        final sources = <BookChunk>[
          _heading(
            0,
            'Generated title',
            owner: 'generated:title:publication:section',
            sourceFile: 'generated:title',
          ),
          const BookChunk(
            index: 1,
            type: BookChunkType.text,
            text: 'Generated navigation entry',
            sourceFile: 'generated:navigation',
            logicalParagraphId: 'generated:navigation:section:item-1',
            logicalParagraphEndOffset: 'Generated navigation entry'.length,
            listSemantics: BookListSemantics(
              listId: 'generated-navigation',
              itemId: 'generated-navigation-item-1',
              ordered: false,
              depth: 0,
              markerType: BookListMarkerType.unordered,
              blockIndex: 0,
              beginsItem: true,
              endsItem: true,
            ),
          ),
          BookChunk(
            index: 2,
            type: BookChunkType.image,
            imageBytes: Uint8List.fromList(const [0, 1, 2, 3]),
            sourceFile: 'images.xhtml',
            logicalParagraphId: 'images.xhtml#image-hero:hero.png',
          ),
          const BookChunk(
            index: 3,
            type: BookChunkType.milestone,
            text: 'Halfway there',
            sourceFile: 'generated:milestone',
            logicalParagraphId: 'generated:milestone:publication:50-percent',
          ),
        ];
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: sources,
        );
        final cards = await _runForwardToEnd(
          harness.canonicalSessionForP04(),
          harness,
        );
        final slices = cards.expand((card) => card.sourceSlices).toList();
        expect(_rolesFor(slices, 0), {'generated:title'});
        expect(_rolesFor(slices, 1), {'generated:navigation'});
        expect(_rolesFor(slices, 2), {'source:image'});
        expect(_rolesFor(slices, 3), {'generated:milestone'});
        for (final ordinal in const [2, 3]) {
          final slice = _slicesFor(slices, ordinal).single;
          expect(slice.startUtf16, isNull);
          expect(slice.tableRowStart, isNull);
          final card = cards.singleWhere(
            (value) => value.sourceSlices.contains(slice),
          );
          expect(card.identity.ranges.single.contentChecksum, isNotEmpty);
        }
      },
    );

    testWidgets(
      'full, target, forward, backward, and singleton construction preserve canonical signatures',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final full = await _runForwardToEnd(
          harness.canonicalSessionForP04(),
          harness,
        );
        final fullSignatures = full
            .map((card) => card.identity.signature)
            .toSet();

        final targetSession = harness.canonicalSessionForP04();
        final target = await targetSession.generateTarget(
          target: harness.canonicalTargetForP04(targetSession, 13),
          operation: harness.canonicalOperationForP04(
            priority: DisplayRangeTaskPriority.directTarget,
          ),
        );
        expect(target, isA<CanonicalReaderPaginationPathAccepted>());
        final acceptedTarget = target as CanonicalReaderPaginationPathAccepted;
        expect(acceptedTarget.publishableCards, isNotEmpty);
        for (final card in acceptedTarget.publishableCards) {
          expect(fullSignatures, contains(card.identity.signature));
        }

        if (target is! CanonicalReaderLogicalEnd) {
          final forward = await targetSession.generateForward(
            acceptedPublishedSuffix:
                target.acceptedContinuation.previousFinalizedBoundary,
            operation: harness.canonicalOperationForP04(),
          );
          expect(forward, isA<CanonicalReaderPaginationPathAccepted>());
          for (final card
              in (forward as CanonicalReaderPaginationPathAccepted)
                  .publishableCards) {
            expect(fullSignatures, contains(card.identity.signature));
          }
        }

        final committed = acceptedTarget.publishableCards.first;
        final successor = targetSession.acceptedSuccessorStartCursorFor(
          committed,
        );
        expect(successor, isNotNull);
        final backward = await targetSession.generateBackward(
          desiredPredecessor: harness.canonicalTargetForP04(targetSession, 8),
          acceptedPublishedPrefix: acceptedTarget.publishableCards.first,
          committedCurrentCard: committed,
          acceptedSuccessorStartCursor: successor!,
          operation: harness.canonicalOperationForP04(),
        );
        expect(backward, isA<CanonicalReaderBackwardPreparationAccepted>());
        final acceptedBackward =
            backward as CanonicalReaderBackwardPreparationAccepted;
        for (final card in acceptedBackward.publishableCards) {
          expect(fullSignatures, contains(card.identity.signature));
        }
        expect(
          acceptedBackward.regeneratedCommittedCard.identity.signature,
          committed.identity.signature,
        );

        final singletonIdentity =
            acceptedTarget.targetContainment!.cardIdentity;
        expect(singletonIdentity.signature, committed.identity.signature);

        final repeatedSession = harness.canonicalSessionForP04();
        final repeated = await _runForwardToEnd(repeatedSession, harness);
        expect(
          repeated.map((card) => card.identity.signature).toList(),
          full.map((card) => card.identity.signature).toList(),
        );

        final slice = full.first.sourceSlices.first;
        expect(
          canonicalBookChunkOwnershipDigest(fixture.sourceChunks.first),
          canonicalBookChunkOwnershipDigest(
            fixture.sourceChunks.first.copyWith(index: 9999),
          ),
        );
        final ordinalChanged = _copySlice(
          slice,
          sourceOrdinalHint: slice.sourceOrdinalHint + 1000,
        );
        final originalIdentity = CanonicalReaderCardIdentityBuilder.build(
          publicationFingerprint: readerCoreFixtureId,
          controlledLayoutIdentity: harness.layoutIdentity,
          paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
          orderedSourceSlices: <CanonicalPaginationSourceSlice>[slice],
        );
        final hintedIdentity = CanonicalReaderCardIdentityBuilder.build(
          publicationFingerprint: readerCoreFixtureId,
          controlledLayoutIdentity: harness.layoutIdentity,
          paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
          orderedSourceSlices: <CanonicalPaginationSourceSlice>[ordinalChanged],
        );
        expect(hintedIdentity.signature, originalIdentity.signature);
      },
    );

    testWidgets(
      'malformed, contradictory, seam-crossing, and display-index evidence is rejected',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: fixture.sourceChunks,
        );
        final session = harness.canonicalSessionForP04();
        final cards = await _runForwardToEnd(session, harness);
        final first = cards.first.sourceSlices.first;
        final oppositeSection = cards
            .expand((card) => card.sourceSlices)
            .firstWhere(
              (slice) => slice.sectionIdentity != first.sectionIdentity,
            );

        expect(
          () => CanonicalReaderCardIdentityBuilder.build(
            publicationFingerprint: readerCoreFixtureId,
            controlledLayoutIdentity: harness.layoutIdentity,
            paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
            orderedSourceSlices: <CanonicalPaginationSourceSlice>[
              first,
              oppositeSection,
            ],
          ),
          throwsFormatException,
        );
        expect(
          () => CanonicalReaderCardIdentityBuilder.build(
            publicationFingerprint: readerCoreFixtureId,
            controlledLayoutIdentity: harness.layoutIdentity,
            paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
            orderedSourceSlices: <CanonicalPaginationSourceSlice>[
              _copySlice(first, structuralOwnerRole: ''),
            ],
          ),
          throwsFormatException,
        );
        expect(
          () => CanonicalReaderCardIdentityBuilder.build(
            publicationFingerprint: readerCoreFixtureId,
            controlledLayoutIdentity: harness.layoutIdentity,
            paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
            orderedSourceSlices: <CanonicalPaginationSourceSlice>[
              _copySlice(first, tableRowStart: 0, tableRowEndExclusive: 1),
            ],
          ),
          throwsFormatException,
        );

        final root = Map<String, Object?>.from(
          jsonDecode(session.acceptedSuffix!.canonicalEncoding) as Map,
        );
        final boundary = Map<String, Object?>.from(
          root['previousFinalizedBoundary']! as Map,
        );
        final identity = Map<String, Object?>.from(
          boundary['cardIdentity']! as Map,
        );
        final ranges = (identity['ranges']! as List)
            .map((value) => Map<String, Object?>.from(value as Map))
            .toList();
        ranges.first
          ..['windowIndex'] = 4
          ..['displayIndex'] = 2
          ..['controllerIndex'] = 2;
        identity['ranges'] = ranges;
        boundary['cardIdentity'] = identity;
        root['previousFinalizedBoundary'] = boundary;
        root.remove('integrityDigest');
        root['integrityDigest'] = readerSha256(root);
        final decoded = CanonicalPaginationContinuationCodec.decode(
          canonicalJsonEncode(root),
        );
        expect(decoded, isA<CanonicalPaginationContinuationRejected>());
        expect(
          (decoded as CanonicalPaginationContinuationRejected).kind,
          CanonicalPaginationContinuationValidationKind.invalidFrontier,
        );
      },
    );
  });
}

Future<List<CanonicalFinalizedReaderCard>> _runForwardToEnd(
  CanonicalReaderPaginationSession session,
  ReaderCorePaginationHarness harness,
) async {
  final cards = <CanonicalFinalizedReaderCard>[];
  CanonicalReaderPaginationPathResult outcome = await session.generateInitial(
    restart: const CanonicalPaginationPublicationStart(),
    operation: harness.canonicalOperationForP04(
      priority: DisplayRangeTaskPriority.initialVisible,
    ),
  );
  for (var operation = 0; operation < 64; operation++) {
    if (outcome is! CanonicalReaderPaginationPathAccepted) {
      throw StateError('Canonical production path rejected: $outcome');
    }
    cards.addAll(outcome.publishableCards);
    if (outcome is CanonicalReaderLogicalEnd) return cards;
    final boundary = outcome.acceptedContinuation.previousFinalizedBoundary;
    outcome = await session.generateForward(
      acceptedPublishedSuffix: boundary,
      operation: harness.canonicalOperationForP04(),
    );
  }
  throw StateError('Canonical production path did not reach logical end.');
}

Set<String> _rolesFor(
  List<CanonicalPaginationSourceSlice> slices,
  int sourceOrdinal,
) => _slicesFor(
  slices,
  sourceOrdinal,
).map((slice) => slice.structuralOwnerRole).toSet();

List<CanonicalPaginationSourceSlice> _slicesFor(
  List<CanonicalPaginationSourceSlice> slices,
  int sourceOrdinal,
) => slices
    .where((slice) => slice.sourceOrdinalHint == sourceOrdinal)
    .toList(growable: false);

bool _splitsSurrogatePair(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return false;
  final prior = text.codeUnitAt(offset - 1);
  final current = text.codeUnitAt(offset);
  return prior >= 0xD800 &&
      prior <= 0xDBFF &&
      current >= 0xDC00 &&
      current <= 0xDFFF;
}

BookChunk _text(int index, String text, {required String owner}) => BookChunk(
  index: index,
  type: BookChunkType.text,
  text: text,
  sourceFile: 'chapter.xhtml',
  logicalParagraphId: owner,
  logicalParagraphEndOffset: text.length,
);

BookChunk _heading(
  int index,
  String text, {
  required String owner,
  String sourceFile = 'chapter.xhtml',
}) => BookChunk(
  index: index,
  type: BookChunkType.text,
  text: text,
  isHeading: true,
  blockRole: BookBlockRole.heading,
  sourceFile: sourceFile,
  logicalParagraphId: owner,
  logicalParagraphEndOffset: text.length,
);

CanonicalPaginationSourceSnapshot _snapshot(List<BookChunk> sources) {
  final keys = <CanonicalPaginationSourceKey>[
    for (final source in sources)
      CanonicalPaginationSourceKey(
        sourceIdentity:
            '${source.sourceFile}|${source.logicalParagraphId}|${source.type.name}|${source.blockRole.name}',
        sectionIdentity: source.sourceFile ?? 'section',
        spineIdentity: source.sourceFile ?? 'section',
        sourceOrdinalHint: source.index,
      ),
  ];
  return CanonicalPaginationSourceSnapshot.pin(
    bookId: 'p04-006-structural-book',
    publicationFingerprint: 'p04-006-structural-publication',
    parserSourceIdentity: 'p04-006-parser',
    sourceRevision: readerSha256(
      sources.map(canonicalBookChunkOwnershipDigest).toList(),
    ),
    sourceChunks: sources,
    sourceKeys: keys,
  );
}

ReaderCardPaginatorLayout _layoutWithHeight(
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

CanonicalPaginationSourceSlice _copySlice(
  CanonicalPaginationSourceSlice source, {
  int? sourceOrdinalHint,
  String? structuralOwnerRole,
  int? tableRowStart,
  int? tableRowEndExclusive,
}) => CanonicalPaginationSourceSlice(
  sourceIdentity: source.sourceIdentity,
  sectionIdentity: source.sectionIdentity,
  spineIdentity: source.spineIdentity,
  sourceOrdinalHint: sourceOrdinalHint ?? source.sourceOrdinalHint,
  sourceDigest: source.sourceDigest,
  structuralType: source.structuralType,
  structuralOwnerRole: structuralOwnerRole ?? source.structuralOwnerRole,
  logicalOwnerIdentity: source.logicalOwnerIdentity,
  structuralDigest: source.structuralDigest,
  fragmentDigest: source.fragmentDigest,
  publisherLayoutDigest: source.publisherLayoutDigest,
  richMetadataDigest: source.richMetadataDigest,
  listFragmentDigest: source.listFragmentDigest,
  splitBoundaryKind: source.splitBoundaryKind,
  isLogicalParagraphStart: source.isLogicalParagraphStart,
  isLogicalParagraphEnd: source.isLogicalParagraphEnd,
  usesExplicitTextFragment: source.usesExplicitTextFragment,
  startUtf16: source.startUtf16,
  endUtf16: source.endUtf16,
  tableRowStart: tableRowStart ?? source.tableRowStart,
  tableRowEndExclusive: tableRowEndExclusive ?? source.tableRowEndExclusive,
);
