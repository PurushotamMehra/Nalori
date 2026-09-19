import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/book_cache_service.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/segmented_display_cache_service.dart';

import 'reader_contract_sandbox.dart';

void main() {
  group('[REQ-033, REQ-034, REQ-039] reader-contract storage sandbox', () {
    test(
      'each sandbox has isolated roots, identities and preference values',
      () async {
        final first = await ReaderContractSandbox.create(
          initialPreferences: const <String, Object>{
            'reader-position': 'first',
          },
        );
        final firstRoot = first.root.path;
        addTearDown(first.close);
        final second = await ReaderContractSandbox.create();
        final secondRoot = second.root.path;
        addTearDown(second.close);

        expect(first.root.path, isNot(second.root.path));
        expect(first.identity.bookId, isNot(second.identity.bookId));
        expect(first.identity.sessionId, isNot(second.identity.sessionId));
        expect(first.preferences.getString('reader-position'), 'first');
        expect(second.preferences.getString('reader-position'), isNull);
        await first.wholeCache.cacheDisplayChunks(
          key: 'isolation-key',
          displayChunks: const <BookChunk>[
            BookChunk(index: 0, type: BookChunkType.text, text: 'first only'),
          ],
          displayToOriginal: const <List<int>>[
            <int>[0],
          ],
          originalToDisplay: const <int, int>{0: 0},
        );
        expect(
          await second.wholeCache.loadDisplayChunks('isolation-key'),
          isNull,
        );
        expect(first.diagnostics, contains('root=$firstRoot'));
        expect(second.diagnostics, contains('root=$secondRoot'));
      },
    );

    test(
      'real temporary SQLite checkpoint survives close and reopen only there',
      () async {
        final sandbox = await ReaderContractSandbox.create();
        final rootPath = sandbox.root.path;
        addTearDown(sandbox.close);
        final store = sandbox.checkpointStore;
        final epoch = await store.beginSession(sandbox.identity.bookId);
        final card = ReaderCardIdentity(
          publicationFingerprint: sandbox.identity.publicationFingerprint,
          layoutFingerprint: 'sandbox-layout',
          ranges: const <ReaderCardSourceRange>[
            ReaderCardSourceRange(
              sectionIdentity: 'chapter-1.xhtml',
              sectionChecksum: 'section-checksum',
              logicalBlockId: 'paragraph-1',
              structuralType: 'paragraph',
              startUtf16: 0,
              endUtf16: 12,
            ),
          ],
        );
        final checkpoint = ReaderCheckpoint.create(
          bookId: sandbox.identity.bookId,
          publicationFingerprint: sandbox.identity.publicationFingerprint,
          card: card,
          semanticAnchor: card.firstMeaningfulAnchor(),
          layoutFingerprint: 'sandbox-layout',
          state: ReaderCheckpointState.exactCommitted,
          sessionEpoch: epoch,
          revision: 1,
          navigationSource: 'reader-contract-sandbox-test',
          committedAtMillis: 1,
        );

        expect((await store.commit(checkpoint)).applied, isTrue);
        await store.close();
        final reopened = sandbox.createCheckpointStore();
        final loaded = await reopened.loadNewestValid(sandbox.identity.bookId);
        expect(loaded?.card?.signature, card.signature);

        final other = await ReaderContractSandbox.create();
        addTearDown(other.close);
        expect(
          await other.checkpointStore.loadNewestValid(sandbox.identity.bookId),
          isNull,
        );
        await other.close();
        expect(await Directory(rootPath).exists(), isTrue);
      },
    );

    test(
      'whole and segmented production caches serialize beneath sandbox roots',
      () async {
        final sandbox = await ReaderContractSandbox.create();
        addTearDown(sandbox.close);
        const key = 'reader-contract-cache-key';
        const chunk = BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: 'sandbox cache content',
        );
        await sandbox.wholeCache.cacheDisplayChunks(
          key: key,
          displayChunks: const <BookChunk>[chunk],
          displayToOriginal: const <List<int>>[
            <int>[0],
          ],
          originalToDisplay: const <int, int>{0: 0},
        );
        expect(
          (await sandbox.wholeCache.loadDisplayChunks(
            key,
          ))?.displayChunks.single.text,
          'sandbox cache content',
        );

        final signature = DisplayGenerationSignature(
          bookId: sandbox.identity.bookId,
          parsedContentVersion: BookCacheService.parsedBookCacheFormatVersion,
          layoutSignature: BookCacheService.displayLayoutVersion,
          settingsSignature: 'sandbox-settings',
          viewportSignature: '390x844',
          cacheKey: key,
        );
        final segmentedKey = SegmentedDisplayCacheKey(
          bookId: sandbox.identity.bookId,
          cacheKey: key,
          signature: signature,
          sourceChunkCount: 1,
        );
        const range = SourceChunkRange(0, 1);
        await sandbox.segmentedDisplayCache.writeSegment(
          key: segmentedKey,
          generationId: 1,
          result: const DisplayRangeResult(
            request: DisplayRangeRequest(
              direction: DisplayRangeDirection.forward,
              sourceRange: range,
              generationId: 1,
              reason: 'reader-contract-sandbox-test',
            ),
            displayChunks: <BookChunk>[chunk],
            displayToOriginal: <List<int>>[
              <int>[0],
            ],
            originalToDisplay: <int, int>{0: 0},
            inspectedSourceChunks: 1,
            elapsedMilliseconds: 0,
          ),
        );
        expect(
          (await sandbox.segmentedDisplayCache.loadRange(
            key: segmentedKey,
            sourceRange: range,
          ))?.displayChunks.single.text,
          'sandbox cache content',
        );
        expect(
          await sandbox.segmentedDisplayCache.payloadBytesOnDisk(),
          greaterThan(0),
        );
        expect(await _hasFiles(sandbox.wholeCacheDirectory), isTrue);
        expect(await _hasFiles(sandbox.segmentedDisplayCacheDirectory), isTrue);
      },
    );

    test(
      'awaited teardown closes stores before removing the unique root',
      () async {
        final sandbox = await ReaderContractSandbox.create();
        final rootPath = sandbox.root.path;
        await sandbox.checkpointStore.beginSession(sandbox.identity.bookId);

        await sandbox.close();

        expect(await Directory(rootPath).exists(), isFalse);
        expect(() => sandbox.createCheckpointStore(), throwsStateError);
      },
    );
  });
}

Future<bool> _hasFiles(Directory directory) async {
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) return true;
  }
  return false;
}
