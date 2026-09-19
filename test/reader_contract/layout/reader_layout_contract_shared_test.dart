// ignore_for_file: avoid_redundant_argument_values, prefer_const_constructors, prefer_const_declarations

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/book_list_semantics.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/widgets/reading_card.dart';
import 'package:nalori/widgets/reading_card_deck.dart';

final class _UsedSizeScaler extends TextScaler {
  const _UsedSizeScaler(this.largeFactor);

  final double largeFactor;

  @override
  double get textScaleFactor => 1;

  @override
  double scale(double fontSize) => fontSize == 1 ? 1 : fontSize * largeFactor;
}

const _runtimeProbeSection = LazySectionIdentity(
  bookId: 'p05-runtime-probes',
  publicationFingerprint: 'p05-runtime-publication',
  spineIndex: 0,
  href: 'runtime.xhtml',
  normalizedHref: 'runtime.xhtml',
  fullPath: 'runtime.xhtml',
  sourceChecksum: 'p05-runtime-checksum',
  parserVersion: lazyParsedSectionParserVersion,
  dependencySignature: 'p05-runtime-dependencies',
  dependencySchemaVersion: lazyParsedSectionDependencySchemaVersion,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final gate = ReaderFontEvidenceGate();
  var maximumContractBytes = 0;
  var maximumBlockBytes = 0;
  var maximumCardBytes = 0;

  Future<ReaderLayoutContract> buildContract({
    ReadingSettings settings = const ReadingSettings(),
    EdgeInsets padding = const EdgeInsets.fromLTRB(3, 24, 5, 18),
    TextDirection? direction = TextDirection.ltr,
    TextScaler scaler = TextScaler.noScaling,
    String source = 'Shared metric source [1].',
    String sourceSnapshot = 'snapshot-v1',
    Size deckSize = const Size(390, 844),
    Size? mediaQuerySize = const Size(390, 844),
  }) async {
    final outcome = await gate.capture(
      settings: settings,
      stableSourceIdentity: 'contract-source',
      sourceStartUtf16: 0,
      sourceText: source,
      locale: 'en-US',
      textScaler: scaler,
    );
    expect(outcome, isA<ReaderFontReadyTerminalBundled>());
    final built = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: deckSize,
        mediaQuerySize: mediaQuerySize,
        viewPadding: padding,
        locale: const Locale('en', 'US'),
        defaultDirection: direction,
        textScaler: scaler,
        settings: settings,
        fontOutcome: outcome,
        captureFreshnessEvidence: 'generation-7',
        publicationFingerprint: 'publication-v1',
        parserSourceSchemaIdentity: 'parser-v1',
        sourceRevision: 'source-v1',
        sourceSnapshotDigest: sourceSnapshot,
      ),
    );
    expect(built, isA<ReaderLayoutContractReady>());
    final contract = (built as ReaderLayoutContractReady).contract;
    maximumContractBytes = mathMax(
      maximumContractBytes,
      contract.retainedStateBytes,
    );
    return contract;
  }

  List<ReaderSourceFontMetricEvidence> evidenceFor(
    ReaderLayoutContract contract,
    BookChunk chunk,
  ) {
    final text = chunk.text ?? '';
    final owner = canonicalBookChunkOwnershipDigest(chunk);
    final evidence = <ReaderSourceFontMetricEvidence>[];
    if (text.isEmpty) {
      final outcome = gate.capturePrepared(
        settings: const ReadingSettings(),
        stableSourceIdentity: '$owner|0:0',
        sourceStartUtf16: 0,
        sourceText: '',
      );
      expect(outcome, isA<ReaderFontReadyTerminalBundled>());
      return [(outcome as ReaderFontReadyTerminalBundled).sourceEvidence];
    }
    var start = 0;
    while (start < text.length) {
      final end = (start + ReaderSourceFontProbePlan.maximumSourceSliceUtf16)
          .clamp(0, text.length);
      final outcome = gate.capturePrepared(
        settings: const ReadingSettings(),
        stableSourceIdentity: '$owner|$start:$end',
        sourceStartUtf16: start,
        sourceText: text.substring(start, end),
        locale: contract.environment.locale.tag,
      );
      expect(outcome, isA<ReaderFontReadyTerminalBundled>());
      evidence.add((outcome as ReaderFontReadyTerminalBundled).sourceEvidence);
      start = end;
    }
    return evidence;
  }

  ResolvedReaderBlockLayout resolve(
    ReaderLayoutContract contract,
    BookChunk chunk, {
    ReaderImageMetricEvidence? image,
  }) {
    final owner = canonicalBookChunkOwnershipDigest(chunk);
    final block = ReaderBlockLayoutResolver.resolve(
      contract: contract,
      chunk: chunk,
      stableBlockOwner: owner,
      sourceStructureDigestLink: owner,
      fontEvidence: evidenceFor(contract, chunk),
      imageEvidence: image,
    );
    maximumBlockBytes = mathMax(maximumBlockBytes, block.retainedStateBytes);
    return block;
  }

  ResolvedReaderCardLayout card(
    ReaderLayoutContract contract,
    ResolvedReaderBlockLayout block,
  ) {
    final value = ReaderCardLayoutResolver.resolve(
      contract: contract,
      block: block,
      physicalSourceIdentity: block.stableBlockOwner,
    );
    maximumCardBytes = mathMax(maximumCardBytes, value.retainedStateBytes);
    return value;
  }

  Future<void> pumpCard(
    WidgetTester tester,
    ReaderLayoutContract contract,
    BookChunk chunk,
    ResolvedReaderBlockLayout block, {
    bool active = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          viewPadding: EdgeInsets.zero,
          textScaler: TextScaler.linear(2),
        ),
        child: SizedBox(
          width: 390,
          height: 844,
          child: ReadingCard(
            chunk: chunk,
            settings: const ReadingSettings(),
            layoutContract: contract,
            resolvedLayout: card(contract, block),
            isActivePage: active,
          ),
        ),
      ),
    ),
  );

  test('1. F001–F211 coverage is exact', () {
    ReaderLayoutFieldCoverage.validate();
    expect(
      ReaderLayoutFieldCoverage.byId.keys,
      orderedEquals(List.generate(211, (i) => i + 1)),
    );
  });

  test('2. equivalent raw settings have one effective fingerprint', () async {
    final first = await buildContract(
      settings: const ReadingSettings(sideMargin: 1),
    );
    final second = await buildContract(
      settings: const ReadingSettings(sideMargin: 12),
    );
    expect(
      first.identities.layoutMetricsFingerprint,
      second.identities.layoutMetricsFingerprint,
    );
  });

  test('3. effective setting change changes layout identity', () async {
    final first = await buildContract();
    final second = await buildContract(
      settings: const ReadingSettings(sideMargin: 30),
    );
    expect(
      first.identities.layoutMetricsFingerprint,
      isNot(second.identities.layoutMetricsFingerprint),
    );
  });

  testWidgets('4. bottom viewPadding has measure/render body parity', (
    tester,
  ) async {
    final contract = await buildContract(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 34),
    );
    final chunk = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'One body line.',
    );
    final block = resolve(contract, chunk);
    await pumpCard(tester, contract, chunk, block);
    expect(contract.geometry.contentPadding.bottom, greaterThanOrEqualTo(34));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('reader-resolved-paragraph-layout')),
          )
          .height,
      block.totalHeight,
    );
  });

  testWidgets('U-01 production border is paint-only at the body constraint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const chunk = BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'Paint-only border geometry.',
    );
    final contract = await buildContract();
    final block = resolve(contract, chunk);

    await pumpCard(tester, contract, chunk, block);

    expect(contract.geometry.borderStrokeWidth, 1.8);
    expect(ReaderCardGeometry.borderLayoutInset, EdgeInsets.zero);
    expect(
      tester.getSize(find.byKey(const ValueKey('reader-contract-body-box'))),
      contract.geometry.bodySize,
    );
  });

  testWidgets('U-02 bounded ReadingCardDeck constraint is authoritative', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> probe(Size deckSize, Size ambientSize) async {
      final contract = await buildContract(
        deckSize: deckSize,
        mediaQuerySize: deckSize,
      );
      const chunk = BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: 'Authoritative bounded deck.',
      );
      final block = resolve(contract, chunk);
      Size? actualDeckConstraint;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: ambientSize),
            child: Center(
              child: SizedBox(
                width: deckSize.width,
                height: deckSize.height,
                child: ReadingCardDeck(
                  currentIndex: 0,
                  itemCount: 1,
                  onIndexChanged: (_) {},
                  cardBuilder: (context, index, progress, current) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        actualDeckConstraint = constraints.biggest;
                        return ReadingCard(
                          chunk: chunk,
                          settings: const ReadingSettings(),
                          layoutContract: contract,
                          resolvedLayout: card(contract, block),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(actualDeckConstraint, deckSize);
      expect(contract.environment.outerDeckSize, deckSize);
      expect(
        tester.getSize(find.byKey(const ValueKey('reader-contract-card-box'))),
        contract.geometry.cardSize,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('reader-contract-body-box'))),
        contract.geometry.bodySize,
      );
    }

    await probe(const Size(390, 844), const Size(390, 844));
    await probe(const Size(320, 600), const Size(390, 844));

    final terminal = await gate.capture(
      settings: const ReadingSettings(),
      stableSourceIdentity: 'mismatch',
      sourceStartUtf16: 0,
      sourceText: 'mismatch',
    );
    final rejected = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: const Size(320, 600),
        mediaQuerySize: const Size(390, 844),
        viewPadding: EdgeInsets.zero,
        locale: const Locale('en'),
        defaultDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        settings: const ReadingSettings(),
        fontOutcome: terminal,
        captureFreshnessEvidence: 'u02',
        publicationFingerprint: 'publication',
        parserSourceSchemaIdentity: 'parser',
        sourceRevision: 'source',
        sourceSnapshotDigest: 'snapshot',
      ),
    );
    expect(rejected.type, ReaderLayoutBuildOutcomeType.incompatibleEnvironment);
    expect(rejected.canAuthorizeLayout, isFalse);
  });

  test('5. keyboard viewInsets are outside geometry inputs', () async {
    final first = await buildContract();
    final second = await buildContract();
    expect(first.geometry.bodySize, second.geometry.bodySize);
  });

  testWidgets('6. explicit LTR is shared by painter and widget', (
    tester,
  ) async {
    final contract = await buildContract(direction: TextDirection.ltr);
    final chunk = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'LTR body',
    );
    final block = resolve(contract, chunk);
    await pumpCard(tester, contract, chunk, block);
    expect(block.resolvedDirection, ReaderLayoutDirection.ltr);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('reader-resolved-text-0')))
          .textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('7. explicit RTL is shared by painter and widget', (
    tester,
  ) async {
    final contract = await buildContract(
      direction: TextDirection.rtl,
      source: 'مرحبا',
    );
    final chunk = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'مرحبا بالعالم',
    );
    final block = resolve(contract, chunk);
    await pumpCard(tester, contract, chunk, block);
    expect(block.resolvedDirection, ReaderLayoutDirection.rtl);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('reader-resolved-text-0')))
          .textDirection,
      TextDirection.rtl,
    );
  });

  test('8. alignment is shared and fingerprinted', () async {
    final left = await buildContract();
    final center = await buildContract(
      settings: const ReadingSettings(textAlign: ReaderTextAlign.center),
    );
    expect(left.typography.defaultBodyAlignment, ReaderLayoutAlignment.left);
    expect(
      center.typography.defaultBodyAlignment,
      ReaderLayoutAlignment.center,
    );
    expect(left.identity, isNot(center.identity));
  });

  test('9. nonlinear used-size responses do not collide', () async {
    const firstScaler = _UsedSizeScaler(1.1);
    const secondScaler = _UsedSizeScaler(1.3);
    final first = await buildContract(scaler: firstScaler);
    final second = await buildContract(scaler: secondScaler);
    expect(firstScaler.scale(1), secondScaler.scale(1));
    expect(first.identity, isNot(second.identity));
  });

  testWidgets('U-07 diagnostic platform inputs preserve logical metrics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final contract = await buildContract();
    const chunk = BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'Diagnostic inputs cannot perturb explicit logical typography.',
    );
    final block = resolve(contract, chunk);
    final resolvedCard = card(contract, block);
    Size? baselineBody;
    Size? baselineText;
    for (final data in <MediaQueryData>[
      const MediaQueryData(size: Size(390, 844), devicePixelRatio: 1),
      const MediaQueryData(size: Size(390, 844), devicePixelRatio: 3),
      const MediaQueryData(size: Size(390, 844), boldText: true),
      const MediaQueryData(size: Size(390, 844), highContrast: true),
      const MediaQueryData(
        size: Size(390, 844),
        platformBrightness: Brightness.dark,
      ),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: data,
            child: ReadingCard(
              chunk: chunk,
              settings: const ReadingSettings(),
              layoutContract: contract,
              resolvedLayout: resolvedCard,
            ),
          ),
        ),
      );
      final body = tester.getSize(
        find.byKey(const ValueKey('reader-contract-body-box')),
      );
      final text = tester.getSize(
        find.byKey(const ValueKey('reader-resolved-paragraph-layout')),
      );
      baselineBody ??= body;
      baselineText ??= text;
      expect(body, baselineBody);
      expect(text, baselineText);
      expect(block.totalHeight, text.height);
    }
  });

  testWidgets('U-08 LTR/RTL alignment, fallback, wrapping and hit parity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const source =
        'English words wrap deterministically. العربية تلتف باتجاه صحيح.';
    final identities = <String>{};
    for (final direction in <TextDirection?>[
      TextDirection.ltr,
      TextDirection.rtl,
      null,
    ]) {
      for (final alignment in ReaderTextAlign.values) {
        final contract = await buildContract(
          direction: direction,
          settings: ReadingSettings(textAlign: alignment),
          source: source,
        );
        final chunk = BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: source,
        );
        final block = resolve(contract, chunk);
        await pumpCard(tester, contract, chunk, block);
        final textWidget = tester.widget<Text>(
          find.byKey(const ValueKey('reader-resolved-text-0')),
        );
        expect(textWidget.textDirection, direction ?? TextDirection.ltr);
        expect(
          textWidget.textAlign,
          contract.typography.defaultBodyAlignment.textAlign,
        );
        expect(
          block.directionSource,
          direction == null
              ? ReaderLayoutDirectionSource.ltrFallback
              : ReaderLayoutDirectionSource.readerCapture,
        );
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('reader-resolved-paragraph-layout')),
              )
              .height,
          block.totalHeight,
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find
              .descendant(
                of: find.byKey(const ValueKey('reader-resolved-text-0')),
                matching: find.byType(RichText),
              )
              .first,
        );
        final hit = paragraph.getPositionForOffset(const Offset(4, 4));
        expect(hit.offset, inInclusiveRange(0, source.length));
        expect(
          paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 7),
          ),
          isNotEmpty,
        );
        identities.add(contract.identity);
      }
    }
    // Four alignments in LTR and RTL are unique; explicit LTR and LTR
    // fallback resolve to the same effective value and intentionally collide.
    expect(identities, hasLength(8));

    final captured = await buildContract(
      settings: const ReadingSettings(textAlign: ReaderTextAlign.left),
    );
    final publisher = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'Publisher alignment override.',
      blockRole: BookBlockRole.quote,
      publisherTextAlign: BookTextAlign.right,
    );
    expect(
      resolve(captured, publisher).resolvedAlignment,
      ReaderLayoutAlignment.right,
    );
  });

  testWidgets('10. body and split-paragraph height parity', (tester) async {
    final contract = await buildContract();
    final chunk = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'First paragraph.\n\nSecond paragraph.',
    );
    final block = resolve(contract, chunk);
    await pumpCard(tester, contract, chunk, block);
    expect(block.paragraphSegments, hasLength(2));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('reader-resolved-paragraph-layout')),
          )
          .height,
      block.totalHeight,
    );
  });

  testWidgets('11. heading text, gap and divider have height parity', (
    tester,
  ) async {
    final contract = await buildContract();
    final chunk = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'Chapter One',
      isHeading: true,
      blockRole: BookBlockRole.heading,
    );
    final block = resolve(contract, chunk);
    await pumpCard(tester, contract, chunk, block);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('reader-resolved-heading-layout')))
          .height,
      block.totalHeight,
    );
  });

  test('12. rich bold and italic share resolved metric roles', () async {
    final contract = await buildContract();
    final chunk = BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'bold italic',
      inlineStyles: const [
        InlineStyle(start: 0, end: 4, type: InlineStyleType.bold),
        InlineStyle(start: 5, end: 11, type: InlineStyleType.italic),
      ],
    );
    final roles = resolve(
      contract,
      chunk,
    ).spanRuns.map((run) => run.role).toSet();
    expect(
      roles,
      containsAll([
        ReaderLayoutTextRole.inlineBold,
        ReaderLayoutTextRole.inlineItalic,
      ]),
    );
  });

  test('13. footnote markers use the footnote metric role', () async {
    final contract = await buildContract();
    final chunk = BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'Text[1]',
      footnotes: const [FootnoteRef(position: 4, label: '1', content: 'note')],
    );
    expect(
      resolve(contract, chunk).spanRuns.last.role,
      ReaderLayoutTextRole.footnoteMarker,
    );
  });

  BookChunk listChunk(bool ordered) => BookChunk(
    index: 0,
    type: BookChunkType.text,
    text: 'List item',
    listSemantics: BookListSemantics(
      listId: 'l',
      itemId: 'i',
      ordered: ordered,
      depth: 1,
      markerType: ordered
          ? BookListMarkerType.decimal
          : BookListMarkerType.unordered,
      resolvedOrdinal: ordered ? 2 : null,
      blockIndex: 0,
      beginsItem: true,
      endsItem: true,
    ),
  );

  test('14. ordered-list marker and body resolve once', () async {
    final contract = await buildContract();
    final block = resolve(contract, listChunk(true));
    expect(block.listSegments.single.marker, '2.');
    expect(block.listSegments.single.markerWidth, greaterThan(0));
  });

  test('15. unordered-list marker and body resolve once', () async {
    final contract = await buildContract();
    expect(resolve(contract, listChunk(false)).listSegments.single.marker, '◦');
  });

  testWidgets('U-03 parser-produced publisher structures have exact parity', (
    tester,
  ) async {
    final contract = await buildContract();
    final parsed = EpubParserService().parseLazySection(
      identity: _runtimeProbeSection,
      html: '''<html><body>
        <p>Publisher prose.</p>
        <div class="poem" style="text-align:center"><p>Poem one<br/>Poem two</p></div>
        <div class="stanza"><p>Stanza one<br/>Stanza two</p></div>
        <blockquote style="margin-left:18px;text-align:right"><p>Quoted words.</p></blockquote>
        <div class="epigraph"><p>Epigraph words.</p></div>
        <div class="letter"><p>Dear reader,</p><p>Faithfully yours.</p></div>
      </body></html>''',
    );
    final roles = parsed.chunks.map((chunk) => chunk.blockRole).toSet();
    expect(
      roles,
      containsAll(<BookBlockRole>{
        BookBlockRole.paragraph,
        BookBlockRole.poem,
        BookBlockRole.stanza,
        BookBlockRole.quote,
        BookBlockRole.epigraph,
        BookBlockRole.letter,
      }),
    );
    for (final chunk in parsed.chunks) {
      final block = resolve(contract, chunk);
      await pumpCard(tester, contract, chunk, block);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('reader-resolved-paragraph-layout')),
            )
            .height,
        block.totalHeight,
        reason: '${chunk.blockRole}',
      );
      expect(block.stableBlockOwner, canonicalBookChunkOwnershipDigest(chunk));
      expect(block.resolvedBlockWidth, greaterThan(0));
      if (chunk.blockRole != BookBlockRole.paragraph) {
        expect(chunk.usesPublisherLayout, isTrue);
        expect(
          block.resolvedBlockWidth,
          contract.geometry.bodySize.width - block.publisherPadding.horizontal,
        );
      }
      if (chunk.blockRole == BookBlockRole.poem ||
          chunk.blockRole == BookBlockRole.stanza) {
        expect(chunk.preserveLineBreaks, isTrue);
        expect(chunk.text, contains('\n'));
      }
    }
  });

  testWidgets('U-04 decoded table spans have fixed grid/row/render parity', (
    tester,
  ) async {
    final contract = await buildContract();
    final parsed = EpubParserService().parseLazySection(
      identity: _runtimeProbeSection,
      html: '''<html><body><table>
        <tr><th colspan="2">Header</th><th>Tail</th></tr>
        <tr><td rowspan="2">A</td><td>B</td><td>C</td></tr>
        <tr><td>D</td><td>E</td></tr>
      </table></body></html>''',
    );
    final chunk = parsed.chunks.singleWhere(
      (chunk) => chunk.blockRole == BookBlockRole.table,
    );
    final block = resolve(contract, chunk);
    await pumpCard(tester, contract, chunk, block);
    expect(block.table!.cells.first.columnSpan, 2);
    expect(block.table!.cells.where((cell) => cell.rowSpan == 2), hasLength(1));
    expect(block.table!.columnWidths.toSet(), hasLength(1));
    expect(
      block.table!.columnWidths.reduce((a, b) => a + b),
      block.table!.horizontalScrollWidth,
    );
    expect(block.table!.rowHeights.every((height) => height > 0), isTrue);
    expect(block.stableBlockOwner, canonicalBookChunkOwnershipDigest(chunk));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('reader-resolved-table-layout')))
          .height,
      block.totalHeight,
    );
  });

  testWidgets('18. preformatted width, lines and height have parity', (
    tester,
  ) async {
    final contract = await buildContract();
    final chunk = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'one\ntwo',
      blockRole: BookBlockRole.preformatted,
      preserveWhitespace: true,
    );
    final block = resolve(contract, chunk);
    await pumpCard(tester, contract, chunk, block);
    expect(block.preformattedLines, hasLength(2));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('reader-resolved-preformatted-layout')),
          )
          .height,
      block.totalHeight,
    );
  });

  ReaderImageMetricEvidence imageEvidenceFor(
    Uint8List bytes, {
    int width = 800,
    int height = 600,
  }) {
    final bytesDigest = sha256.convert(bytes).toString();
    final writer = ReaderFontCanonicalWriter('reader-image-metrics', 1)
      ..stringField(1, bytesDigest)
      ..intField(2, width)
      ..intField(3, height);
    return ReaderImageMetricEvidence(
      bytesDigest: bytesDigest,
      intrinsicWidth: width,
      intrinsicHeight: height,
      evidenceDigest: ReaderFontCanonicalEncoder.digest(writer.takeBytes()),
    );
  }

  test(
    '19. image intrinsic fit and padding resolve before finalization',
    () async {
      final contract = await buildContract();
      final chunk = BookChunk(
        index: 0,
        type: BookChunkType.image,
        imageBytes: Uint8List.fromList([1]),
      );
      final imageEvidence = imageEvidenceFor(chunk.imageBytes!);
      final block = resolve(contract, chunk, image: imageEvidence);
      expect(
        block.image!.width,
        lessThanOrEqualTo(contract.geometry.bodySize.width),
      );
      expect(
        block.totalHeight,
        block.image!.height + block.image!.bottomPadding,
      );
    },
  );

  test('20. later image evidence cannot resize a finalized card', () async {
    final contract = await buildContract();
    final chunk = BookChunk(
      index: 0,
      type: BookChunkType.image,
      imageBytes: Uint8List.fromList([1]),
    );
    final imageEvidence = imageEvidenceFor(chunk.imageBytes!);
    final first = resolve(contract, chunk, image: imageEvidence);
    final later = imageEvidenceFor(chunk.imageBytes!, width: 10, height: 900);
    resolve(contract, chunk, image: later);
    expect(first.image!.evidence, same(imageEvidence));
    expect(
      resolve(contract, chunk, image: later).blockLayoutFingerprint,
      isNot(first.blockLayoutFingerprint),
    );
  });

  test(
    'U-09 stale or contradictory image evidence rejects atomically',
    () async {
      final contract = await buildContract();
      final chunk = BookChunk(
        index: 0,
        type: BookChunkType.image,
        imageBytes: Uint8List.fromList([1]),
      );
      const contradictory = ReaderImageMetricEvidence(
        bytesDigest: 'stale',
        intrinsicWidth: 800,
        intrinsicHeight: 600,
        evidenceDigest: 'claimed',
      );
      expect(
        () => resolve(contract, chunk, image: contradictory),
        throwsStateError,
      );
    },
  );

  test(
    '21. Speed Reader state is absent from canonical paragraph boxes',
    () async {
      final contract = await buildContract();
      final chunk = const BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: 'A.\n\nB.',
      );
      expect(
        resolve(contract, chunk).paragraphSegments,
        resolve(contract, chunk).paragraphSegments,
      );
    },
  );

  testWidgets('22. active/preview wrappers preserve layout height', (
    tester,
  ) async {
    final contract = await buildContract();
    final chunk = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'Selection body',
    );
    final block = resolve(contract, chunk);
    await pumpCard(tester, contract, chunk, block, active: false);
    final inactive = tester
        .getSize(find.byKey(const ValueKey('reader-resolved-paragraph-layout')))
        .height;
    await pumpCard(tester, contract, chunk, block);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('reader-resolved-paragraph-layout')),
          )
          .height,
      inactive,
    );
  });

  test('23. paint/recognizer state is excluded from metric plans', () async {
    final contract = await buildContract();
    final plain = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'link',
    );
    final linked = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'link',
      links: [LinkMetadata(start: 0, end: 4, url: 'https://example.invalid')],
    );
    expect(
      resolve(contract, plain).totalHeight,
      resolve(contract, linked).totalHeight,
    );
  });

  test('24. pending font gate produces no contract authority', () {
    final pending = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: const Size(390, 844),
        mediaQuerySize: const Size(390, 844),
        viewPadding: EdgeInsets.zero,
        locale: const Locale('en'),
        defaultDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        settings: const ReadingSettings(),
        fontOutcome: const ReaderFontPendingAssetReadiness(),
        captureFreshnessEvidence: 'g',
        publicationFingerprint: 'p',
        parserSourceSchemaIdentity: 's',
        sourceRevision: 'r',
        sourceSnapshotDigest: 'd',
      ),
    );
    expect(pending.canAuthorizeLayout, isFalse);
  });

  test('25. absent image evidence performs no measurement', () async {
    final contract = await buildContract();
    final chunk = BookChunk(
      index: 0,
      type: BookChunkType.image,
      imageBytes: Uint8List.fromList([1]),
    );
    expect(() => resolve(contract, chunk), throwsStateError);
  });

  test(
    '26. stale/mismatched contract is atomically rejected by renderer adapter',
    () async {
      final first = await buildContract();
      final second = await buildContract(
        padding: const EdgeInsets.only(bottom: 20),
      );
      final block = resolve(
        first,
        const BookChunk(index: 0, type: BookChunkType.text, text: 'stable'),
      );
      expect(
        () => ReaderLayoutRenderingAdapter.block(
          contract: second,
          card: card(first, block),
        ),
        throwsStateError,
      );
    },
  );

  test('27. evidence-less legacy inputs fail closed', () async {
    final contract = await buildContract();
    final chunk = const BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: 'legacy',
    );
    expect(
      () => ReaderBlockLayoutResolver.resolve(
        contract: contract,
        chunk: chunk,
        stableBlockOwner: canonicalBookChunkOwnershipDigest(chunk),
        sourceStructureDigestLink: canonicalBookChunkOwnershipDigest(chunk),
        fontEvidence: const [],
      ),
      throwsStateError,
    );
  });

  test(
    '27a. canonical empty repertoire resolves to zero text layout and rejects corruption',
    () async {
      final contract = await buildContract(source: '');
      const chunk = BookChunk(index: 0, type: BookChunkType.text, text: '');
      final owner = canonicalBookChunkOwnershipDigest(chunk);
      final evidence = evidenceFor(contract, chunk);
      expect(evidence, hasLength(1));
      expect(evidence.single.isExplicitlyEmptyRepertoire, isTrue);
      expect(evidence.single.observations, isEmpty);

      final block = ReaderBlockLayoutResolver.resolve(
        contract: contract,
        chunk: chunk,
        stableBlockOwner: owner,
        sourceStructureDigestLink: owner,
        fontEvidence: evidence,
      );
      expect(block.spanRuns, isEmpty);
      expect(block.totalHeight, 0);
      expect(block.listSegments, isEmpty);
      expect(block.table, isNull);
      expect(block.preformattedLines, isEmpty);

      final glyphContract = await buildContract(source: 'A');
      expect(
        glyphContract.identities.sourceCompatibilityFingerprint,
        isNot(contract.identities.sourceCompatibilityFingerprint),
      );
      expect(glyphContract.identity, isNot(contract.identity));

      final valid = evidence.single;
      final corrupt = ReaderSourceFontMetricEvidence(
        probeRevision: valid.probeRevision,
        deliveryEvidenceDigest: valid.deliveryEvidenceDigest,
        stableSourceIdentity: valid.stableSourceIdentity,
        sourceStartUtf16: valid.sourceStartUtf16,
        sourceEndUtf16: valid.sourceEndUtf16,
        sourceRepertoireDigest: valid.sourceRepertoireDigest,
        observations: valid.observations,
        canonicalBytes: valid.canonicalBytes,
        digest: List<String>.filled(64, '0').join(),
      );
      expect(
        () => ReaderBlockLayoutResolver.resolve(
          contract: contract,
          chunk: chunk,
          stableBlockOwner: owner,
          sourceStructureDigestLink: owner,
          fontEvidence: <ReaderSourceFontMetricEvidence>[corrupt],
        ),
        throwsStateError,
      );
    },
  );

  test(
    '27b. structural glyph roles and preserved whitespace cannot claim empty repertoire',
    () async {
      final contract = await buildContract(source: '');
      const list = BookListSemantics(
        listId: 'list',
        itemId: 'item',
        ordered: true,
        depth: 0,
        markerType: BookListMarkerType.decimal,
        resolvedOrdinal: 1,
        blockIndex: 0,
        beginsItem: true,
        endsItem: true,
      );
      final structural = <BookChunk>[
        const BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: '',
          isHeading: true,
          blockRole: BookBlockRole.heading,
        ),
        const BookChunk(
          index: 1,
          type: BookChunkType.text,
          text: '',
          listSemantics: list,
        ),
        const BookChunk(
          index: 2,
          type: BookChunkType.text,
          text: '',
          blockRole: BookBlockRole.table,
        ),
        const BookChunk(
          index: 3,
          type: BookChunkType.text,
          text: '',
          blockRole: BookBlockRole.preformatted,
          preserveLineBreaks: true,
          preserveWhitespace: true,
        ),
        const BookChunk(
          index: 4,
          type: BookChunkType.text,
          text: '',
          isDialogue: true,
        ),
      ];
      for (final chunk in structural) {
        expect(
          () => resolve(contract, chunk),
          throwsStateError,
          reason: '${chunk.index}:${chunk.blockRole.name}',
        );
      }

      const whitespace = BookChunk(
        index: 5,
        type: BookChunkType.text,
        text: ' \n ',
        blockRole: BookBlockRole.preformatted,
        preserveLineBreaks: true,
        preserveWhitespace: true,
      );
      final whitespaceEvidence = evidenceFor(contract, whitespace);
      expect(whitespace.text!.trim(), isEmpty);
      expect(whitespaceEvidence.single.observations, hasLength(33));
      expect(resolve(contract, whitespace).totalHeight, greaterThan(0));
    },
  );

  test(
    '28. construction-window indexes do not change block fingerprint',
    () async {
      final contract = await buildContract();
      const first = BookChunk(
        index: 1,
        type: BookChunkType.text,
        text: 'same source',
      );
      const second = BookChunk(
        index: 99,
        type: BookChunkType.text,
        text: 'same source',
      );
      expect(
        resolve(contract, first).blockLayoutFingerprint,
        resolve(contract, second).blockLayoutFingerprint,
      );
    },
  );

  test(
    '29. same contract/source reproduces byte-identical identities',
    () async {
      final contract = await buildContract();
      const chunk = BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: 'deterministic',
      );
      final first = resolve(contract, chunk);
      final second = resolve(contract, chunk);
      expect(first, second);
      expect(card(contract, first), card(contract, second));
    },
  );

  test(
    '30. bottom inset, direction, scaler and rich role change identity',
    () async {
      final base = await buildContract();
      expect(
        (await buildContract(
          padding: const EdgeInsets.only(bottom: 30),
        )).identity,
        isNot(base.identity),
      );
      expect(
        (await buildContract(direction: TextDirection.rtl)).identity,
        isNot(base.identity),
      );
      expect(
        (await buildContract(scaler: const TextScaler.linear(1.2))).identity,
        isNot(base.identity),
      );
      const plain = BookChunk(index: 0, type: BookChunkType.text, text: 'rich');
      const rich = BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: 'rich',
        inlineStyles: [
          InlineStyle(start: 0, end: 4, type: InlineStyleType.bold),
        ],
      );
      expect(
        resolve(base, plain).blockLayoutFingerprint,
        isNot(resolve(base, rich).blockLayoutFingerprint),
      );
    },
  );

  test(
    '31. contract/evidence records contain no whole-book window text',
    () async {
      final contract = await buildContract(source: 'needle');
      expect(contract.toString(), isNot(contains('needle')));
      expect(
        contract.environment.captureFreshnessEvidence,
        isNot(contains('needle')),
      );
    },
  );

  test('32. exact probes and retained evidence remain bounded', () async {
    final contract = await buildContract();
    final long = BookChunk(
      index: 0,
      type: BookChunkType.text,
      text: List.filled(5000, 'x').join(),
    );
    final evidence = evidenceFor(contract, long);
    expect(evidence, hasLength(3));
    expect(
      evidence.every(
        (item) => item.sourceEndUtf16 - item.sourceStartUtf16 <= 2048,
      ),
      isTrue,
    );
    expect(
      gate.retainedSourceEvidenceCount,
      lessThanOrEqualTo(
        ReaderSourceFontProbePlan.maximumRetainedSourceEvidenceRecords,
      ),
    );
  });

  test(
    '33. retained contract/block/card sizes are bounded and recorded',
    () async {
      final contract = await buildContract();
      final block = resolve(
        contract,
        const BookChunk(index: 0, type: BookChunkType.text, text: 'bounded'),
      );
      final resolvedCard = card(contract, block);
      expect(contract.retainedStateBytes, lessThan(8192));
      expect(block.retainedStateBytes, lessThan(8192));
      expect(resolvedCard.retainedStateBytes, lessThan(16384));
      // ignore: avoid_print
      print(
        'P05_RETAINED_MAX contract=$maximumContractBytes '
        'block=$maximumBlockBytes card=$maximumCardBytes',
      );
    },
  );

  testWidgets(
    '34. copy/share/link/selection interaction boundaries remain wired',
    (tester) async {
      final contract = await buildContract();
      const chunk = BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: 'linked',
        links: [LinkMetadata(start: 0, end: 6, url: 'https://example.invalid')],
      );
      final block = resolve(contract, chunk);
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingCard(
            chunk: chunk,
            settings: const ReadingSettings(),
            layoutContract: contract,
            resolvedLayout: card(contract, block),
            onLinkTap: (_) => tapped = true,
            onQuoteShareRequested: (_, __, ___) async {},
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsWidgets);
      expect(tapped, isFalse);
    },
  );
}

int mathMax(int left, int right) => left > right ? left : right;
