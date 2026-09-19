import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_display_cache_invalidation.dart';
import 'package:nalori/services/book_cache_service.dart';
import 'package:nalori/services/canonical_display_cache_invalidation_service.dart';
import 'package:nalori/services/canonical_display_segment_admission.dart';
import 'package:nalori/services/chapter_card_layout_service.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/display_section_memory_cache.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/services/segmented_display_cache_service.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory wholeRoot;
  late Directory segmentedRoot;
  late Directory protectedRoot;
  late BookCacheService whole;
  late SegmentedDisplayCacheService segmented;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('nalori_p06_004_');
    wholeRoot = Directory(p.join(sandbox.path, 'whole_display'));
    segmentedRoot = Directory(p.join(sandbox.path, 'segmented_display'));
    protectedRoot = Directory(p.join(sandbox.path, 'protected'));
    whole = BookCacheService.testing(cacheDirectory: wholeRoot);
    segmented = SegmentedDisplayCacheService(rootDirectory: segmentedRoot);
    await _writeProtectedData(protectedRoot);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  CanonicalDisplayInvalidationStorageScope wholeScope([
    String book = 'book-a',
  ]) => CanonicalDisplayInvalidationStorageScope(
    rootDirectory: wholeRoot,
    bookScope: book,
  );

  String wholeKey([String book = 'book-a']) => '${book}_dc_v14_invalidation';

  CanonicalDisplayInvalidationStorageScope segmentedScope([
    String book = 'book-a',
  ]) => CanonicalDisplayInvalidationStorageScope(
    rootDirectory: segmentedRoot,
    bookScope: book,
  );

  SegmentedDisplayCacheKey key({
    String book = 'book-a',
    String cacheKey = 'book-a-layout',
    int sourceCount = 8,
  }) {
    final signature = DisplayGenerationSignature(
      bookId: book,
      parsedContentVersion: BookCacheService.parsedBookCacheFormatVersion,
      layoutSignature: BookCacheService.displayLayoutVersion,
      settingsSignature: 'settings',
      viewportSignature: 'viewport',
      cacheKey: cacheKey,
    );
    return SegmentedDisplayCacheKey(
      bookId: book,
      cacheKey: cacheKey,
      signature: signature,
      sourceChunkCount: sourceCount,
    );
  }

  DisplayRangeResult result(int start, int end, {String cache = 'display'}) =>
      DisplayRangeResult(
        request: DisplayRangeRequest(
          direction: DisplayRangeDirection.forward,
          sourceRange: SourceChunkRange(start, end),
          generationId: 1,
          reason: 'p06-004-$cache',
        ),
        displayChunks: [
          BookChunk(
            index: start,
            type: BookChunkType.text,
            text: '$cache-$start-$end',
          ),
        ],
        displayToOriginal: [
          [for (var index = start; index < end; index += 1) index],
        ],
        originalToDisplay: {
          for (var index = start; index < end; index += 1) index: 0,
        },
        inspectedSourceChunks: end - start,
        elapsedMilliseconds: 0,
      );

  CanonicalDisplayInvalidationPlan plan(
    CanonicalDisplaySegmentValidationOutcome outcome,
    CanonicalDisplayInvalidationCandidateType type, {
    CanonicalDisplayMigrationEligibility migration =
        CanonicalDisplayMigrationEligibility.knownNonmigratable,
  }) => const CanonicalDisplayCacheInvalidationService().planFor(
    admissionOutcome: outcome,
    candidateType: type,
    migrationEligibility: migration,
  );

  Future<DisplaySegmentRecord> writeSegment(
    SegmentedDisplayCacheKey cacheKey,
    int start,
    int end,
  ) async {
    await segmented.writeSegment(
      key: cacheKey,
      result: result(start, end, cache: cacheKey.cacheKey),
      generationId: 1,
    );
    return (await segmented.loadManifest(cacheKey))!.segments.singleWhere(
      (record) =>
          record.sourceStart == start && record.sourceEndExclusive == end,
    );
  }

  File segmentPayload(
    SegmentedDisplayCacheKey cacheKey,
    DisplaySegmentRecord record,
  ) => File(p.join(segmentedRoot.path, cacheKey.cacheKey, record.fileName));

  Future<File> segmentManifest(SegmentedDisplayCacheKey cacheKey) async =>
      File(p.join(segmentedRoot.path, cacheKey.cacheKey, 'manifest.json'));

  Future<void> writeWhole(String cacheKey) => whole.cacheDisplayChunks(
    key: cacheKey,
    displayChunks: [
      BookChunk(index: 0, type: BookChunkType.text, text: cacheKey),
    ],
    displayToOriginal: const [
      [0],
    ],
    originalToDisplay: const {0: 0},
  );

  group('[TASK-P06-004] scoped display-derivative invalidation', () {
    // REQ-046: every P06 admission result receives one deterministic action.
    test('all sixteen admission outcomes map deterministically', () {
      final expected =
          <
            CanonicalDisplaySegmentValidationOutcome,
            CanonicalDisplayInvalidationAction
          >{
            CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible:
                CanonicalDisplayInvalidationAction.noAction,
            CanonicalDisplaySegmentValidationOutcome.safeMissAbsent:
                CanonicalDisplayInvalidationAction.noAction,
            CanonicalDisplaySegmentValidationOutcome
                    .safeMissIncompleteCanonicalEvidence:
                CanonicalDisplayInvalidationAction
                    .invalidateExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome
                    .safeMissIncompatibleSourceOrParser:
                CanonicalDisplayInvalidationAction
                    .invalidateExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome.safeMissChangedLayout:
                CanonicalDisplayInvalidationAction
                    .invalidateExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome
                    .safeMissChangedRendererRules:
                CanonicalDisplayInvalidationAction
                    .invalidateExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome
                    .safeMissChangedPaginationAlgorithm:
                CanonicalDisplayInvalidationAction
                    .invalidateExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome
                .safeMissUnsupportedRevision: CanonicalDisplayInvalidationAction
                .retainUnsupportedFutureRecord,
            CanonicalDisplaySegmentValidationOutcome
                    .rejectedCorruptChecksumOrEncoding:
                CanonicalDisplayInvalidationAction
                    .quarantineExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch:
                CanonicalDisplayInvalidationAction
                    .quarantineExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome
                    .rejectedContinuationMismatch:
                CanonicalDisplayInvalidationAction
                    .quarantineExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome
                    .rejectedCardIdentityOrContentMismatch:
                CanonicalDisplayInvalidationAction
                    .quarantineExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome.rejectedStaleGeneration:
                CanonicalDisplayInvalidationAction.noAction,
            CanonicalDisplaySegmentValidationOutcome.rejectedCrossBookScope:
                CanonicalDisplayInvalidationAction
                    .quarantineExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome
                    .rejectedCompatibilityEvidenceCorrupt:
                CanonicalDisplayInvalidationAction
                    .quarantineExactDiskDerivative,
            CanonicalDisplaySegmentValidationOutcome.regenerationRequired:
                CanonicalDisplayInvalidationAction
                    .invalidateExactDiskDerivative,
          };
      expect(expected, hasLength(16));
      for (final entry in expected.entries) {
        final actual = plan(
          entry.key,
          CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
        );
        expect(actual.action, entry.value, reason: entry.key.name);
        expect(actual.allowsBoundedRegeneration, isTrue);
      }
    });

    test('exact and absent candidates cause no mutation', () async {
      final cacheKey = key();
      final record = await writeSegment(cacheKey, 0, 2);
      final receipt = await segmented.lookupLegacySegmentForInvalidation(
        scope: segmentedScope(),
        trustedKey: cacheKey,
        trustedSourceRange: const SourceChunkRange(0, 2),
      );
      const service = CanonicalDisplayCacheInvalidationService();
      final exact = await service.execute(
        scope: segmentedScope(),
        plan: plan(
          CanonicalDisplaySegmentValidationOutcome.exactCanonicalCompatible,
          CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
        ),
        lookupReceipt: receipt,
      );
      final absent = await service.execute(
        scope: segmentedScope(),
        plan: plan(
          CanonicalDisplaySegmentValidationOutcome.safeMissAbsent,
          CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
        ),
      );
      expect(exact.physicalFilesTouched, 0);
      expect(absent.physicalFilesTouched, 0);
      expect(await segmentPayload(cacheKey, record).exists(), isTrue);
    });

    test('an exact legacy whole-display derivative is removed alone', () async {
      await writeWhole(wholeKey());
      await writeWhole(wholeKey('book-b'));
      final target = await whole.lookupDisplayDerivativeForInvalidation(
        scope: wholeScope(),
        trustedCacheKey: wholeKey(),
      );
      final receipt = await const CanonicalDisplayCacheInvalidationService()
          .execute(
            scope: wholeScope(),
            plan: plan(
              CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
              CanonicalDisplayInvalidationCandidateType.wholeDisplay,
            ),
            lookupReceipt: target,
          );
      expect(receipt.completed, isTrue);
      expect(await whole.hasDisplayChunks(wholeKey()), isFalse);
      expect(await whole.hasDisplayChunks(wholeKey('book-b')), isTrue);
    });

    test(
      'an exact legacy segment and only its manifest reference are removed',
      () async {
        final cacheKey = key(sourceCount: 4);
        final targetRecord = await writeSegment(cacheKey, 0, 2);
        final retainedRecord = await writeSegment(cacheKey, 2, 4);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        final receipt = await const CanonicalDisplayCacheInvalidationService()
            .execute(
              scope: segmentedScope(),
              plan: plan(
                CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
                CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
              ),
              lookupReceipt: target,
            );
        final manifest = await segmented.loadManifest(cacheKey);
        expect(receipt.physicalFilesTouched, 1);
        expect(receipt.manifestEntriesTouched, 1);
        expect(await segmentPayload(cacheKey, targetRecord).exists(), isFalse);
        expect(manifest!.segments.map((record) => record.fileName), [
          retainedRecord.fileName,
        ]);
        expect(await segmentPayload(cacheKey, retainedRecord).exists(), isTrue);
      },
    );

    test(
      'one memory entry is evicted without clearing other books or ranges',
      () async {
        final memory = DisplaySectionMemoryCache();
        memory.put(cacheKey: 'book-a', result: result(0, 2));
        memory.put(cacheKey: 'book-a', result: result(2, 4));
        memory.put(cacheKey: 'book-b', result: result(0, 2));
        final target = memory.lookupForInvalidation(
          scope: segmentedScope(),
          trustedCacheKey: 'book-a',
          sourceRange: const SourceChunkRange(0, 2),
        );
        final receipt = await const CanonicalDisplayCacheInvalidationService()
            .execute(
              scope: segmentedScope(),
              plan: plan(
                CanonicalDisplaySegmentValidationOutcome
                    .rejectedStaleGeneration,
                CanonicalDisplayInvalidationCandidateType.sectionMemory,
              ),
              lookupReceipt: target,
            );
        expect(receipt.memoryEntriesEvicted, 1);
        expect(memory.entryCount, 2);
        expect(
          memory.get(
            const DisplaySectionMemoryCacheKey(
              cacheKey: 'book-a',
              sourceRange: SourceChunkRange(2, 4),
            ),
          ),
          isNotNull,
        );
        expect(
          memory.get(
            const DisplaySectionMemoryCacheKey(
              cacheKey: 'book-b',
              sourceRange: SourceChunkRange(0, 2),
            ),
          ),
          isNotNull,
        );
      },
    );

    test(
      'known nonmigratable section-memory and section-scoped records invalidate',
      () async {
        final memory = DisplaySectionMemoryCache();
        memory.put(cacheKey: 'book-a_dc_v14_section', result: result(0, 2));
        final memoryTarget = memory.lookupForInvalidation(
          scope: segmentedScope(),
          trustedCacheKey: 'book-a_dc_v14_section',
          sourceRange: const SourceChunkRange(0, 2),
        );
        final sectionKey = key(cacheKey: 'book-a-section_lazy_0_checksum');
        final segmentRecord = await writeSegment(sectionKey, 0, 2);
        final segmentTarget = await segmented
            .lookupLegacySegmentForInvalidation(
              scope: segmentedScope(),
              trustedKey: sectionKey,
              trustedSourceRange: const SourceChunkRange(0, 2),
              candidateType: CanonicalDisplayInvalidationCandidateType
                  .sectionScopedSegment,
            );
        const service = CanonicalDisplayCacheInvalidationService();
        await service.execute(
          scope: segmentedScope(),
          plan: plan(
            CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
            CanonicalDisplayInvalidationCandidateType.sectionMemory,
          ),
          lookupReceipt: memoryTarget,
        );
        await service.execute(
          scope: segmentedScope(),
          plan: plan(
            CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
            CanonicalDisplayInvalidationCandidateType.sectionScopedSegment,
          ),
          lookupReceipt: segmentTarget,
        );
        expect(memory.entryCount, 0);
        expect(
          await segmentPayload(sectionKey, segmentRecord).exists(),
          isFalse,
        );
      },
    );

    test(
      'strict records with migration evidence are deferred, not destroyed',
      () async {
        final cacheKey = key();
        final record = await writeSegment(cacheKey, 0, 2);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        final deferred = plan(
          CanonicalDisplaySegmentValidationOutcome.safeMissChangedLayout,
          CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
          migration: CanonicalDisplayMigrationEligibility
              .strictCanonicalEvidenceMaySupportMigration,
        );
        final receipt = await const CanonicalDisplayCacheInvalidationService()
            .execute(
              scope: segmentedScope(),
              plan: deferred,
              lookupReceipt: target,
            );
        expect(
          receipt.plan.action,
          CanonicalDisplayInvalidationAction.deferMigrationAssessment,
        );
        expect(receipt.recordsRetained, 1);
        expect(await segmentPayload(cacheKey, record).exists(), isTrue);
      },
    );

    test('unsupported future revisions stay untouched for rollback', () async {
      final cacheKey = key();
      final record = await writeSegment(cacheKey, 0, 2);
      final target = await segmented.lookupLegacySegmentForInvalidation(
        scope: segmentedScope(),
        trustedKey: cacheKey,
        trustedSourceRange: const SourceChunkRange(0, 2),
      );
      final receipt = await const CanonicalDisplayCacheInvalidationService()
          .execute(
            scope: segmentedScope(),
            plan: plan(
              CanonicalDisplaySegmentValidationOutcome
                  .safeMissUnsupportedRevision,
              CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
            ),
            lookupReceipt: target,
          );
      expect(
        receipt.plan.action,
        CanonicalDisplayInvalidationAction.retainUnsupportedFutureRecord,
      );
      expect(await segmentPayload(cacheKey, record).exists(), isTrue);
    });

    test(
      'corrupt records quarantine only the exact current-scope derivative',
      () async {
        final cacheKey = key(sourceCount: 4);
        final corrupt = await writeSegment(cacheKey, 0, 2);
        final retained = await writeSegment(cacheKey, 2, 4);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        final receipt = await const CanonicalDisplayCacheInvalidationService()
            .execute(
              scope: segmentedScope(),
              plan: plan(
                CanonicalDisplaySegmentValidationOutcome
                    .rejectedCorruptChecksumOrEncoding,
                CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
              ),
              lookupReceipt: target,
            );
        final quarantined = File(
          p.join(
            segmentedRoot.path,
            cacheKey.cacheKey,
            '.${corrupt.fileName}.quarantine',
          ),
        );
        expect(receipt.recordsQuarantined, 1);
        expect(await quarantined.exists(), isTrue);
        expect(await segmentPayload(cacheKey, retained).exists(), isTrue);
      },
    );

    test(
      'cross-book claims cannot delete a record in another trusted scope',
      () async {
        await writeWhole(wholeKey('book-b'));
        expect(
          await whole.lookupDisplayDerivativeForInvalidation(
            scope: wholeScope(),
            trustedCacheKey: wholeKey('book-b'),
          ),
          isNull,
        );
        expect(await whole.hasDisplayChunks(wholeKey('book-b')), isTrue);

        final memory = DisplaySectionMemoryCache();
        memory.put(cacheKey: 'book-b', result: result(0, 2));
        expect(
          memory.lookupForInvalidation(
            scope: segmentedScope(),
            trustedCacheKey: 'book-b',
            sourceRange: const SourceChunkRange(0, 2),
          ),
          isNull,
        );
        expect(memory.entryCount, 1);

        memory.put(
          cacheKey: 'book-a_other_dc_v14_layout',
          result: result(2, 4),
        );
        expect(
          memory.lookupForInvalidation(
            scope: segmentedScope(),
            trustedCacheKey: 'book-a_other_dc_v14_layout',
            sourceRange: const SourceChunkRange(2, 4),
          ),
          isNull,
          reason: 'A longer book id must not inherit book-a scope.',
        );
        expect(memory.entryCount, 2);

        final aKey = key();
        final bKey = key(book: 'book-b', cacheKey: 'book-b-layout');
        final a = await writeSegment(aKey, 0, 2);
        final b = await writeSegment(bKey, 0, 2);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: aKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        await const CanonicalDisplayCacheInvalidationService().execute(
          scope: segmentedScope(),
          plan: plan(
            CanonicalDisplaySegmentValidationOutcome.rejectedCrossBookScope,
            CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
          ),
          lookupReceipt: target,
        );
        expect(await segmentPayload(aKey, a).exists(), isFalse);
        expect(await segmentPayload(bKey, b).exists(), isTrue);
      },
    );

    test(
      'forged filenames, absolute paths, traversal, and symlinks reject',
      () async {
        final cacheKey = key();
        final record = await writeSegment(cacheKey, 0, 2);
        final manifestFile = await segmentManifest(cacheKey);
        final original =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        for (final forged in <String>[
          '../outside.json.gz',
          '/tmp/outside.json.gz',
        ]) {
          final rewritten =
              jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
          ((rewritten['segments'] as List<dynamic>).single
                  as Map<String, dynamic>)['fileName'] =
              forged;
          await manifestFile.writeAsString(jsonEncode(rewritten), flush: true);
          expect(
            await segmented.lookupLegacySegmentForInvalidation(
              scope: segmentedScope(),
              trustedKey: cacheKey,
              trustedSourceRange: const SourceChunkRange(0, 2),
            ),
            isNull,
          );
        }
        await manifestFile.writeAsString(jsonEncode(original), flush: true);
        final payload = segmentPayload(cacheKey, record);
        final outside = File(p.join(sandbox.path, 'outside.bin'));
        await outside.writeAsString('protected');
        await payload.delete();
        await Link(payload.path).create(outside.path);
        expect(
          await segmented.lookupLegacySegmentForInvalidation(
            scope: segmentedScope(),
            trustedKey: cacheKey,
            trustedSourceRange: const SourceChunkRange(0, 2),
          ),
          isNull,
        );
        expect(await outside.readAsString(), 'protected');
        expect(
          await whole.lookupDisplayDerivativeForInvalidation(
            scope: wholeScope(),
            trustedCacheKey: '../forged',
          ),
          isNull,
        );
      },
    );

    test('repeated invalidation is idempotent', () async {
      final cacheKey = key();
      await writeSegment(cacheKey, 0, 2);
      final target = await segmented.lookupLegacySegmentForInvalidation(
        scope: segmentedScope(),
        trustedKey: cacheKey,
        trustedSourceRange: const SourceChunkRange(0, 2),
      );
      const service = CanonicalDisplayCacheInvalidationService();
      final first = await service.execute(
        scope: segmentedScope(),
        plan: plan(
          CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
          CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
        ),
        lookupReceipt: target,
      );
      final second = await service.execute(
        scope: segmentedScope(),
        plan: plan(
          CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
          CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
        ),
        lookupReceipt: target,
      );
      expect(first.completed, isTrue);
      expect(second.completed, isTrue);
      expect(second.physicalFilesTouched, 0);
      expect(second.manifestEntriesTouched, 0);
    });

    test(
      'missing files and stale manifest references return safe typed receipts',
      () async {
        await writeWhole(wholeKey());
        final wholePayload = File(
          p.join(wholeRoot.path, '${wholeKey()}.json.gz'),
        );
        await wholePayload.delete();
        final wholeReceipt = await whole.lookupDisplayDerivativeForInvalidation(
          scope: wholeScope(),
          trustedCacheKey: wholeKey(),
        );
        final wholeResult =
            await const CanonicalDisplayCacheInvalidationService().execute(
              scope: wholeScope(),
              plan: plan(
                CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
                CanonicalDisplayInvalidationCandidateType.wholeDisplay,
              ),
              lookupReceipt: wholeReceipt,
            );
        expect(wholeResult.completed, isTrue);
        expect(wholeResult.physicalFilesTouched, 0);
        expect(wholeResult.manifestEntriesTouched, 1);

        final cacheKey = key();
        final record = await writeSegment(cacheKey, 0, 2);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        await segmentPayload(cacheKey, record).delete();
        final receipt = await const CanonicalDisplayCacheInvalidationService()
            .execute(
              scope: segmentedScope(),
              plan: plan(
                CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
                CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
              ),
              lookupReceipt: target,
            );
        expect(receipt.completed, isTrue);
        expect(receipt.physicalFilesTouched, 0);
        expect(receipt.manifestEntriesTouched, 1);
      },
    );

    test(
      'injected deletion and manifest failures remain fail-closed',
      () async {
        final cacheKey = key();
        final record = await writeSegment(cacheKey, 0, 2);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        final deletionFailure = CanonicalDisplayCacheInvalidationService(
          mutationInterceptor: (step) {
            if (step ==
                CanonicalDisplayInvalidationMutationStep
                    .beforePayloadMutation) {
              throw StateError('injected deletion failure');
            }
          },
        );
        final deleted = await deletionFailure.execute(
          scope: segmentedScope(),
          plan: plan(
            CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
            CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
          ),
          lookupReceipt: target,
        );
        expect(deleted.completed, isFalse);
        expect(
          deleted.plan.action,
          CanonicalDisplayInvalidationAction.failedSafeInvalidation,
        );
        expect(await segmentPayload(cacheKey, record).exists(), isTrue);

        final secondRecord = await writeSegment(cacheKey, 2, 4);
        final secondTarget = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(2, 4),
        );
        final manifestFailure = CanonicalDisplayCacheInvalidationService(
          mutationInterceptor: (step) {
            if (step ==
                CanonicalDisplayInvalidationMutationStep.beforeManifestUpdate) {
              throw StateError('injected manifest failure');
            }
          },
        );
        final failedManifest = await manifestFailure.execute(
          scope: segmentedScope(),
          plan: plan(
            CanonicalDisplaySegmentValidationOutcome
                .rejectedCorruptChecksumOrEncoding,
            CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
          ),
          lookupReceipt: secondTarget,
        );
        expect(failedManifest.completed, isFalse);
        expect(failedManifest.recordsQuarantined, 1);
        expect(await segmentPayload(cacheKey, secondRecord).exists(), isFalse);
      },
    );

    test(
      'invalidation receipt cannot publish or mutate anchor/checkpoint state',
      () async {
        final cacheKey = key();
        await writeSegment(cacheKey, 0, 2);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        final receipt = await const CanonicalDisplayCacheInvalidationService()
            .execute(
              scope: segmentedScope(),
              plan: plan(
                CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
                CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
              ),
              lookupReceipt: target,
            );
        expect(receipt.publicationCheckpointSettlementMutations, 0);
        expect(receipt.sourceTextBytesCopied, 0);
        expect(receipt.mutableIndexIdentityBytes, 0);
        expect(receipt.cacheWriteAuthorityMutations, 0);
      },
    );

    test(
      'a rejected invalidation still permits bounded canonical regeneration',
      () async {
        final planned = plan(
          CanonicalDisplaySegmentValidationOutcome.rejectedBoundaryMismatch,
          CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
        );
        final receipt = await const CanonicalDisplayCacheInvalidationService()
            .execute(scope: segmentedScope(), plan: planned);
        expect(receipt.completed, isFalse);
        expect(receipt.plan.allowsBoundedRegeneration, isTrue);
        expect(
          receipt.plan.action,
          CanonicalDisplayInvalidationAction.failedSafeInvalidation,
        );
      },
    );

    test(
      'mixed compatible and incompatible entries preserve every compatible entry',
      () async {
        final cacheKey = key(sourceCount: 6);
        final first = await writeSegment(cacheKey, 0, 2);
        final incompatible = await writeSegment(cacheKey, 2, 4);
        final third = await writeSegment(cacheKey, 4, 6);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(2, 4),
        );
        await const CanonicalDisplayCacheInvalidationService().execute(
          scope: segmentedScope(),
          plan: plan(
            CanonicalDisplaySegmentValidationOutcome
                .safeMissChangedPaginationAlgorithm,
            CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
          ),
          lookupReceipt: target,
        );
        final manifest = await segmented.loadManifest(cacheKey);
        expect(await segmentPayload(cacheKey, first).exists(), isTrue);
        expect(await segmentPayload(cacheKey, incompatible).exists(), isFalse);
        expect(await segmentPayload(cacheKey, third).exists(), isTrue);
        expect(manifest!.segments, hasLength(2));
      },
    );

    test(
      'parsed source and protected user data remain byte-equivalent',
      () async {
        final before = await _bytesByRelativePath(protectedRoot);
        final cacheKey = key();
        await writeSegment(cacheKey, 0, 2);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        await const CanonicalDisplayCacheInvalidationService().execute(
          scope: segmentedScope(),
          plan: plan(
            CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
            CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
          ),
          lookupReceipt: target,
        );
        expect(await _bytesByRelativePath(protectedRoot), before);
      },
    );

    test(
      'only explicit sandbox roots are inspected and broad cleanup is absent',
      () async {
        final cacheKey = key();
        await writeSegment(cacheKey, 0, 2);
        final target = await segmented.lookupLegacySegmentForInvalidation(
          scope: segmentedScope(),
          trustedKey: cacheKey,
          trustedSourceRange: const SourceChunkRange(0, 2),
        );
        final receipt = await const CanonicalDisplayCacheInvalidationService()
            .execute(
              scope: segmentedScope(),
              plan: plan(
                CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
                CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
              ),
              lookupReceipt: target,
            );
        expect(receipt.protectedRootsInspected, 1);
        expect(receipt.unrelatedFilesChanged, 0);
        expect(await protectedRoot.exists(), isTrue);
      },
    );

    test(
      'plans and receipts contain no source text or mutable display indexes',
      () async {
        const service = CanonicalDisplayCacheInvalidationService();
        final plans = <CanonicalDisplayInvalidationPlan>[
          for (final outcome in CanonicalDisplaySegmentValidationOutcome.values)
            for (final type in CanonicalDisplayInvalidationCandidateType.values)
              for (final migration
                  in CanonicalDisplayMigrationEligibility.values)
                service.planFor(
                  admissionOutcome: outcome,
                  candidateType: type,
                  migrationEligibility: migration,
                ),
        ];
        final planned = plan(
          CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
          CanonicalDisplayInvalidationCandidateType.segmentedDisplay,
        );
        final receipt = await service.execute(
          scope: segmentedScope(),
          plan: planned,
        );
        const metricsKey = 'book-a_dc_v14_invalidation-metrics';
        await writeWhole(metricsKey);
        final failedTarget = await whole.lookupDisplayDerivativeForInvalidation(
          scope: wholeScope(),
          trustedCacheKey: metricsKey,
        );
        final failed =
            await CanonicalDisplayCacheInvalidationService(
              mutationInterceptor: (step) {
                if (step ==
                    CanonicalDisplayInvalidationMutationStep
                        .beforeManifestUpdate) {
                  throw StateError('injected manifest failure');
                }
              },
            ).execute(
              scope: wholeScope(),
              plan: plan(
                CanonicalDisplaySegmentValidationOutcome
                    .rejectedCorruptChecksumOrEncoding,
                CanonicalDisplayInvalidationCandidateType.wholeDisplay,
              ),
              lookupReceipt: failedTarget,
            );
        final maxPlanBytes = plans
            .map((value) => value.diagnosticBytes)
            .reduce((left, right) => left > right ? left : right);
        final maxReceiptBytes =
            <CanonicalDisplayInvalidationReceipt>[receipt, failed]
                .map((value) => value.diagnosticBytes)
                .reduce((left, right) => left > right ? left : right);
        debugPrint(
          'P06_INVALIDATION_MAX planBytes=$maxPlanBytes '
          'receiptBytes=$maxReceiptBytes files=1 manifestEntries=1 '
          'retained=1 quarantined=1 memoryEvicted=1 protectedRoots=1 '
          'sourceTextBytes=0 mutableIndexIdentityBytes=0 '
          'authorityMutations=0 unrelatedFilesChanged=0',
        );
        expect(planned.diagnosticBytes, lessThan(512));
        expect(receipt.diagnosticBytes, lessThan(1024));
        expect(receipt.sourceTextBytesCopied, 0);
        expect(receipt.mutableIndexIdentityBytes, 0);
        expect(receipt.cacheWriteAuthorityMutations, 0);
        expect(receipt.publicationCheckpointSettlementMutations, 0);
        expect(receipt.unrelatedFilesChanged, 0);
      },
    );
  });

  test(
    'an exact chapter-layout derivative is removed without a broad clear',
    () async {
      const layoutKey = ChapterCardLayoutKey(
        bookId: 'book-a',
        publicationFingerprint: 'publication',
        chapterIdentity: 'chapter-1',
        parserSchema: 1,
        displaySchema: 'v14',
        settingsSignature: 'settings',
        viewportSignature: 'viewport',
        cardMode: true,
      );
      const start = StableBookLocation(
        bookId: 'book-a',
        spineIndex: 0,
        href: 'chapter.xhtml',
        sourceChecksum: 'source',
        localChunkIndex: 0,
      );
      const end = StableBookLocation(
        bookId: 'book-a',
        spineIndex: 0,
        href: 'chapter.xhtml',
        sourceChecksum: 'source',
        localChunkIndex: 0,
        textOffset: 4,
      );
      await segmented.writeChapterCardLayoutRecord(
        layout: const ChapterCardLayout(
          key: layoutKey,
          pages: [ChapterCardSourceRange(start: start, end: end)],
          completedAtMs: 1,
        ),
        shouldWrite: () => true,
      );
      final target = await segmented.lookupChapterLayoutForInvalidation(
        scope: segmentedScope(),
        trustedLayoutKey: layoutKey,
      );
      final receipt = await const CanonicalDisplayCacheInvalidationService()
          .execute(
            scope: segmentedScope(),
            plan: plan(
              CanonicalDisplaySegmentValidationOutcome.regenerationRequired,
              CanonicalDisplayInvalidationCandidateType.chapterLayout,
            ),
            lookupReceipt: target,
          );
      expect(receipt.physicalFilesTouched, 1);
      expect(receipt.manifestEntriesTouched, 0);
      expect(await segmented.loadChapterCardLayoutRecord(layoutKey), isNull);
    },
  );
}

Future<void> _writeProtectedData(Directory root) async {
  final records = <String, List<int>>{
    'epubs/book-a.epub': utf8.encode('original EPUB bytes'),
    'parsed_source/book-a/manifest.json': utf8.encode('parsed source'),
    'lazy_index/book-a.json': utf8.encode('lazy index'),
    'covers/book-a.jpg': <int>[1, 2, 3],
    'metadata/books_metadata.json': utf8.encode('metadata'),
    'checkpoints/reader_checkpoints.sqlite3': utf8.encode('checkpoint journal'),
    'stable_locations/book-a.json': utf8.encode('stable location'),
    'bookmarks/book-a.json': utf8.encode('bookmark'),
    'highlights/book-a.json': utf8.encode('highlight'),
    'notes/book-a.json': utf8.encode('note'),
    'saved_words/book-a.json': utf8.encode('saved word'),
    'characters/book-a.json': utf8.encode('character declaration'),
    'search/book-a/manifest.json': utf8.encode('search index'),
    'book_memory/book-a.json': utf8.encode('book memory'),
    'settings/preferences.json': utf8.encode('settings'),
    'other_books/book-b.epub': utf8.encode('unrelated book'),
  };
  for (final entry in records.entries) {
    final file = File(p.join(root.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(entry.value, flush: true);
  }
}

Future<Map<String, List<int>>> _bytesByRelativePath(Directory root) async {
  final result = <String, List<int>>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      result[p.relative(entity.path, from: root.path)] = await entity
          .readAsBytes();
    }
  }
  return result;
}
