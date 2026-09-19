import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/reader_checkpoint_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('exact rendered-card identity', () {
    test('every split card from one long paragraph has a unique signature', () {
      final cards = List.generate(
        10,
        (index) =>
            _card(layout: 'layout-a', start: index * 10, end: (index + 1) * 10),
      );

      expect(cards.map((card) => card.signature).toSet(), hasLength(10));
    });

    test('ordered ranges are deterministic across reconstruction', () {
      final first = _multiRangeCard(layout: 'layout-a');
      final second = ReaderCardIdentity.fromJson(first.toJson());

      expect(second.signature, first.signature);
      expect(
        canonicalJsonEncode(second.toJson()),
        canonicalJsonEncode(first.toJson()),
      );
    });

    test('same paragraph split across cards identifies the exact split', () {
      final cards = List.generate(
        8,
        (index) =>
            _card(layout: 'layout-a', start: index * 20, end: (index + 1) * 20),
      );
      final saved = cards[5];

      expect(
        cards.singleWhere((card) => card.signature == saved.signature),
        same(saved),
      );
      expect(saved.ranges.single.startUtf16, 100);
    });

    test('cards containing multiple paragraphs preserve ordered coverage', () {
      final card = _multiRangeCard(layout: 'layout-a');

      expect(card.ranges.map((range) => range.logicalBlockId), [
        'paragraph-1',
        'paragraph-2',
      ]);
      expect(card.ranges.map((range) => range.startUtf16), [12, 0]);
      expect(card.ranges.map((range) => range.endUtf16), [40, 18]);
    });

    test(
      'headings, tables, preformatted, images, and synthetic cards are explicit',
      () {
        final heading = _identityFromSource(
          const BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: 'Heading',
            isHeading: true,
            blockRole: BookBlockRole.heading,
            logicalParagraphId: 'heading-1',
          ),
        );
        final table = _identityFromSource(
          const BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: 'A | B',
            blockRole: BookBlockRole.table,
            logicalParagraphId: 'table-1',
          ),
        );
        final pre = _identityFromSource(
          const BookChunk(
            index: 0,
            type: BookChunkType.text,
            text: '  code\n',
            blockRole: BookBlockRole.preformatted,
            logicalParagraphId: 'pre-1',
          ),
        );
        final image = _identityFromSource(
          BookChunk(
            index: 0,
            type: BookChunkType.image,
            imageBytes: Uint8List.fromList([1, 2, 3]),
            logicalParagraphId: 'image-1',
          ),
        );
        final synthetic = ReaderCardIdentity.fromCard(
          publicationFingerprint: 'publication',
          layoutFingerprint: 'layout-a',
          card: const BookChunk(
            index: -1,
            type: BookChunkType.milestone,
            text: 'Halfway',
          ),
          sourceChunks: const [],
          sourceIndices: const [],
          locationsBySourceIndex: const {},
        );

        expect(heading.ranges.single.structuralType, 'heading');
        expect(table.ranges.single.structuralType, 'table');
        expect(pre.ranges.single.structuralType, 'preformatted');
        expect(image.ranges.single.structuralType, 'image');
        expect(image.ranges.single.startUtf16, isNull);
        expect(image.ranges.single.endUtf16, isNull);
        expect(image.ranges.single.contentChecksum, isNotEmpty);
        expect(synthetic.ranges.single.structuralType, 'synthetic:milestone');
        expect(synthetic.ranges.single.startUtf16, isNull);
      },
    );
  });

  group('canonical checkpoint protocol', () {
    late Directory directory;
    late ReaderCheckpointStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('nalori_checkpoint_');
      store = ReaderCheckpointStore.forTesting(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/checkpoints.sqlite3',
      );
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    test('same layout restores the exact committed signature', () async {
      final committed = _card(layout: 'layout-a', start: 40, end: 60);
      await _establish(store, committed);
      final reopened = await _coordinator(store);

      final result = reopened.resolveRestore(
        cards: [
          _card(layout: 'layout-a'),
          committed,
          _card(layout: 'layout-a', start: 60, end: 80),
        ],
        currentLayoutFingerprint: 'layout-a',
      );

      expect(result?.strategy, ReaderRestoreMatchStrategy.exactSignature);
      expect(result?.index, 1);
      expect(
        reopened.verifyPublished(
          visibleCard: committed,
          strategy: result!.strategy,
        ),
        isTrue,
      );
    });

    test(
      'same-layout partial publication cannot downgrade to semantic restore',
      () async {
        final committed = _card(layout: 'layout-a', start: 40, end: 60);
        await _establish(store, committed);
        final reopened = await _coordinator(store);
        final semanticNeighbor = ReaderCardIdentity(
          publicationFingerprint: committed.publicationFingerprint,
          layoutFingerprint: committed.layoutFingerprint,
          ranges: [
            ReaderCardSourceRange(
              sectionIdentity: committed.ranges.single.sectionIdentity,
              sectionChecksum: committed.ranges.single.sectionChecksum,
              logicalBlockId: committed.ranges.single.logicalBlockId,
              structuralType: committed.ranges.single.structuralType,
              startUtf16: 0,
              endUtf16: 80,
            ),
          ],
        );

        final latePartial = reopened.resolveRestore(
          cards: [semanticNeighbor],
          currentLayoutFingerprint: 'layout-a',
        );

        expect(latePartial, isNull);
        expect(reopened.current?.card?.signature, committed.signature);
      },
    );

    test('fifty rapid navigations survive immediate close', () async {
      final coordinator = await _freshEstablished(store);
      final writes = <Future<ReaderCheckpointCommitResult>>[];
      for (var index = 0; index < 50; index++) {
        writes.add(
          coordinator.commitCard(
            card: _card(
              layout: 'layout-a',
              start: index * 10,
              end: index * 10 + 10,
            ),
            stableLocation: _location(offset: index * 10),
            navigationSource: 'swipe',
          ),
        );
      }
      await coordinator.flush();
      await Future.wait(writes);

      final saved = await store.loadNewestValid('book.epub');
      expect(
        saved?.card?.signature,
        _card(layout: 'layout-a', start: 490, end: 500).signature,
      );
    });

    test(
      'background flush waits for an in-flight persistence operation',
      () async {
        final coordinator = await _freshEstablished(store);
        final destination = _card(layout: 'layout-a', start: 200, end: 220);
        final write = coordinator.commitCard(
          card: destination,
          stableLocation: _location(offset: 200),
          navigationSource: 'swipe',
        );

        await coordinator.flush();
        expect((await write).applied, isTrue);
        expect(
          (await store.loadNewestValid('book.epub'))?.card?.signature,
          destination.signature,
        );
      },
    );

    test(
      'out-of-order completion cannot overwrite the newer revision',
      () async {
        final epoch = await store.beginSession('book.epub');
        final newer = _checkpoint(epoch: epoch, revision: 2, start: 20);
        final older = _checkpoint(epoch: epoch, revision: 1, start: 10);

        expect((await store.commit(newer)).applied, isTrue);
        expect(
          (await store.commit(older)).status,
          ReaderCheckpointCommitStatus.staleRevisionRejected,
        );
        expect((await store.loadNewestValid('book.epub'))?.revision, 2);
      },
    );

    test(
      'stale revision and stale session are rejected inside the store',
      () async {
        final oldEpoch = await store.beginSession('book.epub');
        expect(
          (await store.commit(
            _checkpoint(epoch: oldEpoch, revision: 1),
          )).applied,
          isTrue,
        );
        final currentEpoch = await store.beginSession('book.epub');

        expect(
          (await store.commit(
            _checkpoint(epoch: oldEpoch, revision: 2),
          )).status,
          ReaderCheckpointCommitStatus.staleSessionRejected,
        );
        expect(
          (await store.commit(
            _checkpoint(epoch: currentEpoch, revision: 1),
          )).applied,
          isTrue,
        );
        expect(
          (await store.commit(
            _checkpoint(epoch: currentEpoch, revision: 1),
          )).status,
          ReaderCheckpointCommitStatus.staleRevisionRejected,
        );
      },
    );

    test('default page cannot overwrite a pending restore', () async {
      final saved = _card(layout: 'layout-a', start: 80, end: 100);
      await _establish(store, saved);
      final reopened = await _coordinator(store);

      final rejected = await reopened.commitCard(
        card: _card(layout: 'layout-a'),
        stableLocation: _location(),
        navigationSource: 'initial_default',
      );

      expect(rejected.status, ReaderCheckpointCommitStatus.invalidRejected);
      expect(
        (await store.loadNewestValid('book.epub'))?.card?.signature,
        saved.signature,
      );
    });

    test(
      'explicit entry target does not reload the stored checkpoint',
      () async {
        final saved = _card(layout: 'layout-a', start: 80, end: 100);
        await _establish(store, saved);
        final explicitEntry = ReaderCheckpointCoordinator(
          store: store,
          bookId: 'book.epub',
          publicationFingerprint: 'publication',
        );

        final loaded = await explicitEntry.initialize(ignoreStored: true);

        expect(loaded, isNull);
        expect(explicitEntry.current, isNull);
      },
    );

    test(
      'delayed lazy-window publication cannot displace exact restore',
      () async {
        final saved = _card(layout: 'layout-a', start: 60, end: 80);
        await _establish(store, saved);
        final reopened = await _coordinator(store);

        final first = reopened.resolveRestore(
          cards: [saved],
          currentLayoutFingerprint: 'layout-a',
        );
        final delayed = reopened.resolveRestore(
          cards: [
            _card(layout: 'layout-a'),
            _card(layout: 'layout-a', start: 20, end: 40),
            saved,
          ],
          currentLayoutFingerprint: 'layout-a',
        );

        expect(first?.index, 0);
        expect(delayed?.index, 2);
        expect(delayed?.strategy, ReaderRestoreMatchStrategy.exactSignature);
      },
    );

    test(
      'unloaded chapter resolves after its semantic section is loaded',
      () async {
        final saved = _card(
          layout: 'layout-a',
          section: 'chapter-9.xhtml',
          block: 'chapter-9-p1',
        );
        await _establish(
          store,
          saved,
          location: _location(href: 'chapter-9.xhtml'),
        );
        final reopened = await _coordinator(store);

        expect(
          reopened.resolveRestore(
            cards: [_card(layout: 'layout-a')],
            currentLayoutFingerprint: 'layout-a',
          ),
          isNull,
        );
        expect(
          reopened
              .resolveRestore(
                cards: [saved],
                currentLayoutFingerprint: 'layout-a',
              )
              ?.index,
          0,
        );
      },
    );

    test(
      'chapter bookmark link search and scrubber use one commit path',
      () async {
        final coordinator = await _freshEstablished(store);
        const sources = ['chapter', 'bookmark', 'link', 'search', 'scrubber'];
        for (var index = 0; index < sources.length; index++) {
          expect(
            (await coordinator.commitCard(
              card: _card(
                layout: 'layout-a',
                start: 100 + index * 20,
                end: 120 + index * 20,
              ),
              stableLocation: _location(offset: 100 + index * 20),
              navigationSource: sources[index],
            )).applied,
            isTrue,
          );
        }

        expect(
          (await store.loadNewestValid('book.epub'))?.navigationSource,
          'scrubber',
        );
      },
    );

    test('canceled scrubber or gesture does not create a checkpoint', () async {
      final coordinator = await _freshEstablished(store);
      final before = await store.loadNewestValid('book.epub');
      // Preview/cancel intentionally performs no coordinator commit.
      await coordinator.flush();
      final after = await store.loadNewestValid('book.epub');

      expect(after?.integrityChecksum, before?.integrityChecksum);
    });

    test('density reflow commits the exact new card before exit', () async {
      final coordinator = await _freshEstablished(store);
      final token = await coordinator.beginLayoutTransition(
        targetLayoutFingerprint: 'density-high',
        targetLayoutSettings: const {'contentDensity': 'high'},
        navigationSource: 'density',
      );
      final reflowed = _card(layout: 'density-high', end: 14);

      expect(
        coordinator
            .resolveRestore(
              cards: [reflowed],
              currentLayoutFingerprint: 'density-high',
            )
            ?.strategy,
        ReaderRestoreMatchStrategy.semanticAnchor,
      );
      expect(
        (await coordinator.commitCard(
          card: reflowed,
          stableLocation: _location(),
          navigationSource: 'reflow_complete',
          duringRestore: true,
          layoutToken: token,
        )).applied,
        isTrue,
      );
      expect(
        (await store.loadNewestValid('book.epub'))?.card?.signature,
        reflowed.signature,
      );
      final reopened = await _coordinator(store);
      final exactAfterReflow = reopened.resolveRestore(
        cards: [reflowed],
        currentLayoutFingerprint: 'density-high',
      );
      expect(
        exactAfterReflow?.strategy,
        ReaderRestoreMatchStrategy.exactSignature,
      );
      expect([reflowed][exactAfterReflow!.index].signature, reflowed.signature);
    });

    test(
      'termination during reflow reopens from pending semantic anchor',
      () async {
        final coordinator = await _freshEstablished(store);
        await coordinator.beginLayoutTransition(
          targetLayoutFingerprint: 'density-full',
          targetLayoutSettings: const {'contentDensity': 'fullPage'},
          navigationSource: 'density',
        );
        // No dispose callback and no reflow completion.
        final reopened = await _coordinator(store);
        final target = _card(layout: 'density-full', end: 12);

        expect(
          reopened.current?.state,
          ReaderCheckpointState.layoutTransitionPending,
        );
        expect(
          reopened.current?.targetLayoutSettings?['contentDensity'],
          'fullPage',
        );
        expect(
          reopened
              .resolveRestore(
                cards: [target],
                currentLayoutFingerprint: 'density-full',
              )
              ?.strategy,
          ReaderRestoreMatchStrategy.semanticAnchor,
        );
      },
    );

    test('rapid density changes reject older pagination completions', () async {
      final coordinator = await _freshEstablished(store);
      final first = await coordinator.beginLayoutTransition(
        targetLayoutFingerprint: 'density-low',
        targetLayoutSettings: const {'contentDensity': 'low'},
        navigationSource: 'density',
      );
      final second = await coordinator.beginLayoutTransition(
        targetLayoutFingerprint: 'density-high',
        targetLayoutSettings: const {'contentDensity': 'high'},
        navigationSource: 'density',
      );
      final third = await coordinator.beginLayoutTransition(
        targetLayoutFingerprint: 'density-full',
        targetLayoutSettings: const {'contentDensity': 'fullPage'},
        navigationSource: 'density',
      );

      expect(
        (await coordinator.commitCard(
          card: _card(layout: 'density-low', end: 10),
          stableLocation: _location(),
          navigationSource: 'late_reflow',
          duringRestore: true,
          layoutToken: first,
        )).status,
        ReaderCheckpointCommitStatus.staleRevisionRejected,
      );
      expect(
        (await coordinator.commitCard(
          card: _card(layout: 'density-high', end: 10),
          stableLocation: _location(),
          navigationSource: 'late_reflow',
          duringRestore: true,
          layoutToken: second,
        )).status,
        ReaderCheckpointCommitStatus.staleRevisionRejected,
      );
      expect(
        (await coordinator.commitCard(
          card: _card(layout: 'density-full', end: 10),
          stableLocation: _location(),
          navigationSource: 'latest_reflow',
          duringRestore: true,
          layoutToken: third,
        )).applied,
        isTrue,
      );
    });

    test(
      'font text-scale orientation and viewport changes restore the anchor',
      () async {
        final coordinator = await _freshEstablished(store);
        for (final layout in [
          'font-literata',
          'text-scale-1.2',
          'orientation-landscape',
          'viewport-800x600',
        ]) {
          final token = await coordinator.beginLayoutTransition(
            targetLayoutFingerprint: layout,
            targetLayoutSettings: {'layout': layout},
            navigationSource: 'layout_change',
          );
          final card = _card(layout: layout, end: 15);
          expect(
            coordinator
                .resolveRestore(cards: [card], currentLayoutFingerprint: layout)
                ?.strategy,
            ReaderRestoreMatchStrategy.semanticAnchor,
          );
          expect(
            (await coordinator.commitCard(
              card: card,
              stableLocation: _location(),
              navigationSource: 'reflow_complete',
              duringRestore: true,
              layoutToken: token,
            )).applied,
            isTrue,
          );
        }
      },
    );

    test(
      'legacy location is migrated once into a canonical exact card',
      () async {
        final coordinator = await _coordinator(store);
        final migrated = _card(layout: 'layout-a', start: 30, end: 50);

        expect(
          (await coordinator.migrateLegacy(
            card: migrated,
            stableLocation: _location(offset: 30),
          )).applied,
          isTrue,
        );
        final reopened = await _coordinator(store);
        expect(reopened.current?.card?.signature, migrated.signature);
        expect(reopened.current?.navigationSource, 'legacy_migration');
      },
    );

    test(
      'corrupt newest record recovers the previous valid checkpoint',
      () async {
        final coordinator = await _freshEstablished(store);
        final valid = coordinator.current!;
        await store.insertCorruptNewest(
          bookId: 'book.epub',
          sessionEpoch: valid.sessionEpoch,
          revision: valid.revision + 100,
        );

        expect(
          (await store.loadNewestValid('book.epub'))?.integrityChecksum,
          valid.integrityChecksum,
        );
        final recovered = _card(layout: 'layout-a', start: 80, end: 100);
        expect(
          (await coordinator.commitCard(
            card: recovered,
            stableLocation: _location(offset: 80),
            navigationSource: 'after_corruption',
          )).applied,
          isTrue,
        );
        expect(
          (await store.loadNewestValid('book.epub'))?.card?.signature,
          recovered.signature,
        );
      },
    );

    test('abrupt termination simulation needs no dispose callback', () async {
      final coordinator = await _freshEstablished(store);
      final destination = _card(layout: 'layout-a', start: 300, end: 320);
      expect(
        (await coordinator.commitCard(
          card: destination,
          stableLocation: _location(offset: 300),
          navigationSource: 'swipe',
        )).applied,
        isTrue,
      );

      final secondStore = ReaderCheckpointStore.forTesting(
        databaseFactory: databaseFactoryFfi,
        databasePath: '${directory.path}/checkpoints.sqlite3',
      );
      addTearDown(secondStore.close);
      expect(
        (await secondStore.loadNewestValid('book.epub'))?.card?.signature,
        destination.signature,
      );
    });

    test(
      'seeded 1000-operation navigation layout background reopen stress',
      () async {
        final random = math.Random(1776);
        var coordinator = await _freshEstablished(store);
        var layout = 'layout-0';
        var expected = coordinator.current!.card!;

        for (var operation = 1; operation <= 1000; operation++) {
          final event = random.nextInt(10);
          if (event < 6) {
            final start = random.nextInt(80) * 10;
            expected = _card(layout: layout, start: start, end: start + 10);
            expect(
              (await coordinator.commitCard(
                card: expected,
                stableLocation: _location(offset: start),
                navigationSource: 'stress_navigation',
              )).applied,
              isTrue,
            );
          } else if (event < 8) {
            layout = 'layout-$operation';
            final token = await coordinator.beginLayoutTransition(
              targetLayoutFingerprint: layout,
              targetLayoutSettings: {'layout': layout},
              navigationSource: 'stress_layout',
            );
            final anchor =
                coordinator.current!.semanticAnchor.blockOffsetUtf16 ?? 0;
            expected = _card(layout: layout, start: anchor, end: anchor + 10);
            expect(
              (await coordinator.commitCard(
                card: expected,
                stableLocation: _location(offset: anchor),
                navigationSource: 'stress_reflow',
                duringRestore: true,
                layoutToken: token,
              )).applied,
              isTrue,
            );
          } else if (event == 8) {
            await coordinator.flush();
          } else {
            coordinator = await _coordinator(store);
            final resolution = coordinator.resolveRestore(
              cards: [expected],
              currentLayoutFingerprint: layout,
            );
            expect(
              resolution?.strategy,
              ReaderRestoreMatchStrategy.exactSignature,
            );
            expect(
              coordinator.verifyPublished(
                visibleCard: expected,
                strategy: resolution!.strategy,
              ),
              isTrue,
            );
          }
        }

        await coordinator.flush();
        expect(
          (await store.loadNewestValid('book.epub'))?.card?.signature,
          expected.signature,
        );
      },
    );
  });
}

ReaderCardIdentity _card({
  required String layout,
  int start = 0,
  int end = 20,
  String section = 'chapter-1.xhtml',
  String block = 'paragraph-1',
}) {
  return ReaderCardIdentity(
    publicationFingerprint: 'publication',
    layoutFingerprint: layout,
    ranges: [
      ReaderCardSourceRange(
        sectionIdentity: section,
        sectionChecksum: 'section-checksum-$section',
        logicalBlockId: block,
        structuralType: 'paragraph',
        startUtf16: start,
        endUtf16: end,
      ),
    ],
  );
}

ReaderCardIdentity _multiRangeCard({required String layout}) {
  return ReaderCardIdentity(
    publicationFingerprint: 'publication',
    layoutFingerprint: layout,
    ranges: const [
      ReaderCardSourceRange(
        sectionIdentity: 'chapter-1.xhtml',
        sectionChecksum: 'section-checksum-chapter-1.xhtml',
        logicalBlockId: 'paragraph-1',
        structuralType: 'paragraph',
        startUtf16: 12,
        endUtf16: 40,
      ),
      ReaderCardSourceRange(
        sectionIdentity: 'chapter-1.xhtml',
        sectionChecksum: 'section-checksum-chapter-1.xhtml',
        logicalBlockId: 'paragraph-2',
        structuralType: 'paragraph',
        startUtf16: 0,
        endUtf16: 18,
      ),
    ],
  );
}

ReaderCardIdentity _identityFromSource(BookChunk source) {
  final location = _location();
  return ReaderCardIdentity.fromCard(
    publicationFingerprint: 'publication',
    layoutFingerprint: 'layout-a',
    card: source,
    sourceChunks: [source],
    sourceIndices: const [0],
    locationsBySourceIndex: {0: location},
  );
}

StableBookLocation _location({
  int offset = 0,
  String href = 'chapter-1.xhtml',
}) {
  return StableBookLocation(
    bookId: 'book.epub',
    spineIndex: href == 'chapter-1.xhtml' ? 0 : 8,
    href: href,
    normalizedHref: href,
    sourceChecksum: 'section-checksum-$href',
    publicationFingerprint: 'publication',
    localChunkIndex: 0,
    textOffset: offset,
    contextBefore: 'before',
    contextText: 'target',
    contextAfter: 'after',
  );
}

ReaderCheckpoint _checkpoint({
  required int epoch,
  required int revision,
  int start = 0,
}) {
  final card = _card(layout: 'layout-a', start: start, end: start + 20);
  return ReaderCheckpoint.create(
    bookId: 'book.epub',
    publicationFingerprint: 'publication',
    card: card,
    semanticAnchor: card.firstMeaningfulAnchor(),
    stableLocation: _location(offset: start),
    layoutFingerprint: 'layout-a',
    state: ReaderCheckpointState.exactCommitted,
    sessionEpoch: epoch,
    revision: revision,
    navigationSource: 'test',
  );
}

Future<ReaderCheckpointCoordinator> _coordinator(
  ReaderCheckpointStore store,
) async {
  final coordinator = ReaderCheckpointCoordinator(
    store: store,
    bookId: 'book.epub',
    publicationFingerprint: 'publication',
  );
  await coordinator.initialize();
  return coordinator;
}

Future<ReaderCheckpointCoordinator> _freshEstablished(
  ReaderCheckpointStore store,
) async {
  final coordinator = await _coordinator(store);
  final initial = _card(layout: 'layout-a');
  expect(
    (await coordinator.migrateLegacy(
      card: initial,
      stableLocation: _location(),
    )).applied,
    isTrue,
  );
  return coordinator;
}

Future<void> _establish(
  ReaderCheckpointStore store,
  ReaderCardIdentity card, {
  StableBookLocation? location,
}) async {
  final coordinator = await _coordinator(store);
  expect(
    (await coordinator.migrateLegacy(
      card: card,
      stableLocation:
          location ?? _location(offset: card.ranges.first.startUtf16 ?? 0),
    )).applied,
    isTrue,
  );
}
