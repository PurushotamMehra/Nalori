import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_display_segment.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_compatibility.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/utils/reader_content_parser.dart';

import '../pagination/reader_core_pagination_harness.dart';

const _tableIdentity = LazySectionIdentity(
  bookId: 'device-regression-table',
  publicationFingerprint: 'device-regression-publication',
  spineIndex: 0,
  href: 'table.xhtml',
  normalizedHref: 'table.xhtml',
  fullPath: 'table.xhtml',
  sourceChecksum: 'table-source',
  parserVersion: lazyParsedSectionParserVersion,
  dependencySignature: 'table-dependencies',
  dependencySchemaVersion: lazyParsedSectionDependencySchemaVersion,
);

void main() {
  group('CHANGE-20260914-039 production table compatibility', () {
    test('single-row production table remains structured and lossless', () {
      final section = EpubParserService().parseLazySection(
        identity: _tableIdentity,
        html: '''
          <html><body>
            <table><tbody><tr>
              <td><em>Port</em> Stanley</td><td colspan="2">South Georgia</td>
            </tr></tbody></table>
          </body></html>
        ''',
      );

      final chunk = section.chunks.singleWhere(
        (candidate) => candidate.blockRole == BookBlockRole.table,
      );
      final blocks = parseReaderContentBlocks(chunk.text!);

      expect(blocks, hasLength(1));
      expect(blocks.single.type, ReaderContentBlockType.table);
      final table = blocks.single.table!;
      expect(table.headers, isEmpty);
      expect(table.rows, [
        ['Port Stanley', 'South Georgia', ''],
      ]);
      expect(table.cellRows.single.map((cell) => cell.text), [
        'Port Stanley',
        'South Georgia',
      ]);
      expect(table.cellRows.single.last.columnSpan, 2);
      expect(chunk.text, startsWith('NALORI_TABLE_V1:'));
    });

    test('production spans and header/body roles survive normalization', () {
      final section = EpubParserService().parseLazySection(
        identity: _tableIdentity,
        html: '''
          <html><body><table>
            <tr><th>Stage</th><th colspan="2"><strong>Position</strong></th></tr>
            <tr><td rowspan="2">One</td><td>Lat</td><td>54 S</td></tr>
            <tr><td>Lon</td><td>36 W</td></tr>
          </table></body></html>
        ''',
      );
      final chunk = section.chunks.singleWhere(
        (candidate) => candidate.blockRole == BookBlockRole.table,
      );

      final table = requireNormalizedReaderTable(chunk.text!);

      expect(table.headers, ['Stage', 'Position', '']);
      expect(table.rows, [
        ['One', 'Lat', '54 S'],
        ['One', 'Lon', '36 W'],
      ]);
      expect(table.cellRows.first[1].isHeader, isTrue);
      expect(table.cellRows.first[1].columnSpan, 2);
      expect(table.cellRows[1].first.rowSpan, 2);
      expect(encodeReaderTableBlock(table), chunk.text);
    });

    test('canonical table-row fragments retain cell structure and spans', () {
      const table = ReaderTableBlock(
        headers: ['Stage', 'Position', ''],
        rows: [
          ['One', 'Lat', '54 S'],
          ['One', 'Lon', '36 W'],
        ],
        cellRows: [
          [
            ReaderTableCell(text: 'Stage', isHeader: true),
            ReaderTableCell(text: 'Position', isHeader: true, columnSpan: 2),
          ],
          [
            ReaderTableCell(text: 'One', rowSpan: 2),
            ReaderTableCell(text: 'Lat'),
            ReaderTableCell(text: '54 S'),
          ],
          [ReaderTableCell(text: 'Lon'), ReaderTableCell(text: '36 W')],
        ],
      );
      final source = BookChunk(
        index: 7,
        type: BookChunkType.text,
        sourceFile: 'table.xhtml',
        text: encodeReaderTableBlock(table),
        blockRole: BookBlockRole.table,
        logicalParagraphId: 'table-owner',
      );

      final fragment = buildCanonicalTableRowFragment(source, table, 0, 2);
      final normalized = requireNormalizedReaderTable(fragment.text!);

      expect(normalized.cellRows.first[1].isHeader, isTrue);
      expect(normalized.cellRows.first[1].columnSpan, 2);
      expect(normalized.cellRows[1].first.rowSpan, 2);
      expect(normalized.rows, table.rows);
      expect(fragment.logicalParagraphId, source.logicalParagraphId);
    });

    test('malformed table has a typed recoverable normalization error', () {
      expect(
        () => requireNormalizedReaderTable('not a table'),
        throwsA(isA<ReaderTableNormalizationException>()),
      );
    });
  });

  group('CHANGE-20260914-039 authoritative generation lifecycle', () {
    const signature = DisplayGenerationSignature(
      bookId: 'single-flight.epub',
      parsedContentVersion: 6,
      layoutSignature: 'layout',
      settingsSignature: 'settings',
      viewportSignature: 'viewport',
      cacheKey: 'cache',
    );

    test('deterministic failure cannot auto-start the same request', () {
      final coordinator = DisplayGenerationCoordinator();
      final first = coordinator.request(signature);
      coordinator.fail(first.token);

      final repeated = coordinator.request(signature);

      expect(repeated.kind, isNot(DisplayGenerationRequestKind.start));
      expect(repeated.token.id, first.token.id);
      expect(repeated.token.state, DisplayGenerationState.failed);
    });

    test(
      'join, replacement, failure, cancellation, and retry are terminal',
      () async {
        final coordinator = DisplayGenerationCoordinator();
        final first = coordinator.request(signature);
        final joined = coordinator.request(signature);
        expect(joined.token.done, same(first.token.done));

        final replacement = coordinator.request(
          const DisplayGenerationSignature(
            bookId: 'single-flight.epub',
            parsedContentVersion: 6,
            layoutSignature: 'layout',
            settingsSignature: 'settings',
            viewportSignature: 'viewport',
            cacheKey: 'cache',
            sourceSnapshotIdentity: 'source',
            targetIdentity: 'chapter-2',
          ),
        );
        expect(
          (await first.token.done).kind,
          DisplayGenerationTerminalKind.stale,
        );

        coordinator.fail(replacement.token, const FormatException('table'));
        final failed = await replacement.token.done;
        expect(failed.kind, DisplayGenerationTerminalKind.failed);
        expect(failed.error, isA<FormatException>());

        final blocked = coordinator.request(replacement.token.signature);
        expect(blocked.kind, DisplayGenerationRequestKind.blockedFailure);
        final retry = coordinator.retry(replacement.token.signature);
        expect(retry.kind, DisplayGenerationRequestKind.start);
        coordinator.cancelActive('reader_disposed');
        expect(
          (await retry.token.done).kind,
          DisplayGenerationTerminalKind.cancelled,
        );
      },
    );
  });

  group('CHANGE-20260914-039 cooperative pagination', () {
    test('default bounded section work uses one concurrent job', () {
      expect(SharedLazySectionWorkCoordinator().maxConcurrentJobs, 1);
    });

    testWidgets('long paragraph yields through the production paginator', (
      tester,
    ) async {
      final evidence = await _paginateWithSyntheticClock(
        tester,
        BookChunk(
          index: 0,
          type: BookChunkType.text,
          sourceFile: 'long.xhtml',
          text: List<String>.filled(
            220,
            'A bounded scheduler keeps navigation responsive.',
          ).join(' '),
          logicalParagraphId: 'long-paragraph',
        ),
      );

      expect(evidence.yields, greaterThan(0));
      expect(
        evidence.maxSlice,
        lessThanOrEqualTo(const Duration(milliseconds: 8)),
      );
    });

    testWidgets('large table yields through the production paginator', (
      tester,
    ) async {
      final table = ReaderTableBlock(
        headers: const ['Step', 'Position'],
        rows: [
          for (var index = 0; index < 24; index++)
            ['$index', 'A structurally owned cell value $index'],
        ],
      );
      final evidence = await _paginateWithSyntheticClock(
        tester,
        BookChunk(
          index: 0,
          type: BookChunkType.text,
          sourceFile: 'table.xhtml',
          text: encodeReaderTableBlock(table),
          blockRole: BookBlockRole.table,
          logicalParagraphId: 'large-table',
        ),
      );

      expect(evidence.yields, greaterThan(0));
      expect(
        evidence.maxSlice,
        lessThanOrEqualTo(const Duration(milliseconds: 8)),
      );
    });
  });

  group('CHANGE-20260914-039 retained-memory bounds', () {
    test(
      'memory pressure preserves current section and evicts adjacent work',
      () async {
        final fixture = await ReaderCoreParsedFixture.load(
          'device_regression_memory_',
        );
        addTearDown(fixture.close);
        final repository = LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(
              '${fixture.temporaryDirectory.path}/cache',
            ),
          ),
        );
        final session = LazyBookSession(repository: repository);
        addTearDown(session.close);
        await session.open(fixture.epubFile);
        final current = session.initialLocation();
        await session.loadAround(current);
        final beforeSections = repository.retainedSectionCount;
        final beforeBytes = repository.retainedEstimatedBytes;

        session.handleMemoryPressure();

        expect(session.loadedSpineIndices, [current.spineIndex]);
        expect(repository.retainedSpineIndices, [current.spineIndex]);
        expect(
          repository.retainedEstimatedBytes,
          lessThanOrEqualTo(beforeBytes),
        );
        // ignore: avoid_print
        print(
          'P06_MEMORY_PRESSURE beforeSections=$beforeSections '
          'beforeBytes=$beforeBytes afterSections='
          '${repository.retainedSectionCount} afterBytes='
          '${repository.retainedEstimatedBytes}',
        );
      },
    );

    test(
      'switching three books does not accumulate retained sections',
      () async {
        final fixture = await ReaderCoreParsedFixture.load(
          'device_regression_switching_',
        );
        addTearDown(fixture.close);
        final copies = <File>[];
        for (var index = 0; index < 3; index++) {
          copies.add(
            await fixture.epubFile.copy(
              '${fixture.temporaryDirectory.path}/switch-$index.epub',
            ),
          );
        }
        final repository = LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(
              '${fixture.temporaryDirectory.path}/switch-cache',
            ),
          ),
        );
        final session = LazyBookSession(repository: repository);
        addTearDown(session.close);
        final counts = <int>[];
        final bytes = <int>[];

        for (final file in copies) {
          await session.open(file);
          await session.loadAround(session.initialLocation());
          counts.add(session.retainedSectionCount);
          bytes.add(session.retainedEstimatedBytes);
        }

        expect(counts.every((count) => count <= 2), isTrue);
        expect(counts.toSet(), hasLength(1));
        expect(bytes.toSet(), hasLength(1));
        // ignore: avoid_print
        print('P06_BOOK_SWITCH retainedSections=$counts retainedBytes=$bytes');
      },
    );
  });

  group('CHANGE-20260914-039 canonical restart writes', () {
    testWidgets(
      'title pagination advances across the following chapter boundary',
      (tester) async {
        final harness = await ReaderCorePaginationHarness.install(
          tester: tester,
          sourceChunks: const <BookChunk>[
            BookChunk(
              index: 0,
              type: BookChunkType.text,
              section: ChunkSection.frontMatter,
              sourceFile: 'title.xhtml',
              text: 'A Bounded Voyage',
              isHeading: true,
              blockRole: BookBlockRole.heading,
              logicalParagraphId: 'title',
            ),
            BookChunk(
              index: 1,
              type: BookChunkType.text,
              sourceFile: 'chapter-one.xhtml',
              text: 'Chapter one opens with a short readable paragraph.',
              logicalParagraphId: 'chapter-one',
            ),
            BookChunk(
              index: 2,
              type: BookChunkType.text,
              sourceFile: 'chapter-two.xhtml',
              text: 'Chapter two follows without whole-book preparation.',
              logicalParagraphId: 'chapter-two',
            ),
          ],
          bookId: 'device-regression-boundary',
          publicationFingerprint: 'device-regression-boundary',
        );
        final session = harness.canonicalSessionForP04();
        final initial = await session.generateInitial(
          restart: const CanonicalPaginationPublicationStart(),
          operation: harness.canonicalOperationForP04(
            priority: DisplayRangeTaskPriority.initialVisible,
          ),
          budget: const CanonicalPaginationWorkBudget(
            maxSourceChunks: 1,
            maxAtomicFragments: 16,
            maxFinalizedCards: 1,
          ),
        );
        expect(initial, isA<CanonicalReaderPaginationPathAccepted>());
        final acceptedInitial =
            initial as CanonicalReaderPaginationPathAccepted;
        expect(
          acceptedInitial.publishableCards
              .expand((card) => card.sourceSlices)
              .map((slice) => slice.sourceOrdinalHint)
              .toSet(),
          {0},
        );
        final titleCard = acceptedInitial.publishableCards.last;
        final boundary = session.publishedSuffixBoundary(
          card: titleCard.card,
          sourceOrdinals: titleCard.sourceSlices
              .map((slice) => slice.sourceOrdinalHint)
              .toSet()
              .toList(growable: false),
        );
        expect(boundary, isNotNull);

        final forward = await session.generateForward(
          acceptedPublishedSuffix: boundary!,
          operation: harness.canonicalOperationForP04(
            priority: DisplayRangeTaskPriority.boundaryWait,
          ),
        );

        expect(forward, isA<CanonicalReaderPaginationPathAccepted>());
        final acceptedForward =
            forward as CanonicalReaderPaginationPathAccepted;
        final forwardOrdinals = acceptedForward.publishableCards
            .expand((card) => card.sourceSlices)
            .map((slice) => slice.sourceOrdinalHint)
            .toSet();
        expect(forwardOrdinals, contains(1));
        final chapterOneCard = acceptedForward.publishableCards.last;
        final chapterBoundary = session.publishedSuffixBoundary(
          card: chapterOneCard.card,
          sourceOrdinals: chapterOneCard.sourceSlices
              .map((slice) => slice.sourceOrdinalHint)
              .toSet()
              .toList(growable: false),
        );
        expect(chapterBoundary, isNotNull);
        final nextChapter = await session.generateForward(
          acceptedPublishedSuffix: chapterBoundary!,
          operation: harness.canonicalOperationForP04(
            priority: DisplayRangeTaskPriority.boundaryWait,
          ),
        );
        expect(nextChapter, isA<CanonicalReaderPaginationPathAccepted>());
        expect(
          (nextChapter as CanonicalReaderPaginationPathAccepted)
              .publishableCards
              .expand((card) => card.sourceSlices)
              .map((slice) => slice.sourceOrdinalHint),
          contains(2),
        );
      },
    );

    testWidgets('mid-book cache record requires the accepted predecessor', (
      tester,
    ) async {
      final sourceChunks = <BookChunk>[
        for (var index = 0; index < 3; index++)
          BookChunk(
            index: index,
            type: BookChunkType.text,
            sourceFile: 'chapter-${index + 1}.xhtml',
            text: List<String>.filled(
              80,
              'Bounded chapter ${index + 1} content.',
            ).join(' '),
            logicalParagraphId: 'chapter-$index',
          ),
      ];
      final harness = await ReaderCorePaginationHarness.install(
        tester: tester,
        sourceChunks: sourceChunks,
        bookId: 'device-regression-restart',
        publicationFingerprint: 'device-regression-restart',
      );
      final session = harness.canonicalSessionForP04();
      final initial = await session.generateInitial(
        restart: const CanonicalPaginationPublicationStart(),
        operation: harness.canonicalOperationForP04(
          priority: DisplayRangeTaskPriority.initialVisible,
        ),
        budget: const CanonicalPaginationWorkBudget(
          maxSourceChunks: 3,
          maxAtomicFragments: 64,
          maxFinalizedCards: 1,
        ),
      );
      expect(initial, isA<CanonicalReaderPaginationPathAccepted>());
      final acceptedInitial = initial as CanonicalReaderPaginationPathAccepted;
      final suffix = acceptedInitial.publishableCards.last;
      final boundary = session.publishedSuffixBoundary(
        card: suffix.card,
        sourceOrdinals: suffix.sourceSlices
            .map((slice) => slice.sourceOrdinalHint)
            .toSet()
            .toList(growable: false),
      );
      expect(boundary, isNotNull);
      final forward = await session.generateForward(
        acceptedPublishedSuffix: boundary!,
        operation: harness.canonicalOperationForP04(),
      );
      expect(forward, isA<CanonicalReaderPaginationPathAccepted>());
      final acceptedForward = forward as CanonicalReaderPaginationPathAccepted;
      final compatibility =
          CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
            ReaderCompatibilityEvidence.fromIdentity(
              harness
                  .paginatorLayout
                  .contract!
                  .identities
                  .readerCompatibilityIdentity,
            ),
          );
      final arguments = (
        bookStorageScopeDigest: readerSha256('device-regression-restart'),
        compatibilityEvidence: compatibility,
        sourceSnapshot: session.sourceSnapshot,
        finalizedCards: acceptedForward.publishableCards,
        continuation: acceptedForward.continuation,
      );

      final unproven = CanonicalDisplaySegmentRecordBuilder.buildForPublication(
        bookStorageScopeDigest: arguments.bookStorageScopeDigest,
        compatibilityEvidence: arguments.compatibilityEvidence,
        sourceSnapshot: arguments.sourceSnapshot,
        finalizedCards: arguments.finalizedCards,
        continuation: arguments.continuation,
      );
      final proven = CanonicalDisplaySegmentRecordBuilder.buildForPublication(
        bookStorageScopeDigest: arguments.bookStorageScopeDigest,
        compatibilityEvidence: arguments.compatibilityEvidence,
        sourceSnapshot: arguments.sourceSnapshot,
        finalizedCards: arguments.finalizedCards,
        continuation: arguments.continuation,
        acceptedRestart: acceptedInitial.continuation,
      );

      expect(
        (unproven as CanonicalDisplaySegmentRecordNoWrite).reason,
        CanonicalDisplaySegmentNoWriteReason.unprovenMidBookRestart,
      );
      expect(proven, isA<CanonicalDisplaySegmentRecordBuilt>());
    });
  });
}

Future<({int yields, Duration maxSlice})> _paginateWithSyntheticClock(
  WidgetTester tester,
  BookChunk source,
) async {
  var micros = 0;
  var yields = 0;
  final scheduler = FrameBudgetedRangeScheduler(
    clock: () => Duration(microseconds: micros += 1000),
    yieldToFrame: () async => yields++,
  );
  final harness = await ReaderCorePaginationHarness.install(
    tester: tester,
    sourceChunks: [source],
    bookId: 'device-regression-scheduler',
    publicationFingerprint: 'device-regression-scheduler',
    scheduler: scheduler,
  );
  final session = harness.canonicalSessionForP04();
  final result = await session.generateInitial(
    restart: const CanonicalPaginationPublicationStart(),
    operation: harness.canonicalOperationForP04(
      priority: DisplayRangeTaskPriority.initialVisible,
    ),
  );
  expect(result, isA<CanonicalReaderPaginationPathAccepted>());
  final metrics = scheduler.completedMetrics.single;
  return (yields: yields, maxSlice: metrics.maxSliceDuration);
}
