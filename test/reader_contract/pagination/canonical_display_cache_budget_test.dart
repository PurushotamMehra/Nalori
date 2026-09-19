import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_display_segment.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reader_compatibility.dart';
import 'package:nalori/services/canonical_display_cache_service.dart';
import 'package:nalori/services/canonical_display_segment_admission.dart';
import 'package:nalori/services/display_generation_coordinator.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:path/path.dart' as p;

import '../support/reader_contract_sandbox.dart';
import 'reader_core_pagination_harness.dart';

late ReaderCoreParsedFixture _fixture;

void main() {
  setUpAll(() async {
    _fixture = await ReaderCoreParsedFixture.load('nalori_reader_p06_budget_');
  });

  tearDownAll(() => _fixture.close());

  group('[REQ-009, REQ-010, REQ-013, REQ-044, REQ-045, REQ-046, '
      'REQ-048, REQ-051] TASK-P06-006 bounded canonical retention', () {
    testWidgets(
      'release record budgets accept below/exact and reject above before retain',
      (tester) async {
        final setup = await _setup(tester, 'record-bounds');
        final record = setup.cold.records.reduce((left, right) {
          final leftSize = CanonicalDisplaySegmentCodec.encode(left).length;
          final rightSize = CanonicalDisplaySegmentCodec.encode(right).length;
          return leftSize >= rightSize ? left : right;
        });
        final previous = _previousContinuation(setup.cold.records, record);
        const measurement = CanonicalDisplayCacheBudgets();
        final probe = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/measure'),
        ).measureRecord(record);

        final cases =
            <
              String,
              ({int value, CanonicalDisplayCacheBudgets Function(int) limits})
            >{
              'cards': (
                value: probe.cards,
                limits: (value) => measurement.copyWith(
                  maxCardsPerRecord: value,
                  maxValidationCards: value,
                ),
              ),
              'sourceSlices': (
                value: probe.sourceSlices,
                limits: (value) => measurement.copyWith(
                  maxSourceSlicesPerRecord: value,
                  maxValidationSourceSlices: value,
                ),
              ),
              'blockLayouts': (
                value: probe.blockLayouts,
                limits: (value) =>
                    measurement.copyWith(maxBlockLayoutsPerRecord: value),
              ),
              'decodedBytes': (
                value: probe.decodedBytes,
                limits: (value) =>
                    measurement.copyWith(maxDecodedBytesPerRecord: value),
              ),
              'compressedBytes': (
                value: probe.compressedBytes,
                limits: (value) =>
                    measurement.copyWith(maxCompressedBytesPerRecord: value),
              ),
              'decompressionRatio': (
                value: probe.decompressionRatioCeiling,
                limits: (value) =>
                    measurement.copyWith(maxDecompressionRatio: value),
              ),
              'continuationDepth': (
                value: probe.continuationChainDepth,
                limits: (value) =>
                    measurement.copyWith(maxContinuationChainDepth: value),
              ),
            };

        for (final entry in cases.entries) {
          if (entry.value.value <= 0) continue;
          for (final delta in const <int>[1, 0, -1]) {
            final ceiling = entry.value.value + delta;
            if (ceiling <= 0) continue;
            final service = CanonicalDisplayCacheService(
              rootDirectory: Directory(
                '${setup.sandbox.root.path}/${entry.key}-$delta',
              ),
              budgets: entry.value.limits(ceiling),
            );
            if (delta < 0) {
              expect(
                service.validateMeasurement(probe),
                isNotNull,
                reason: '${entry.key} accepted just-above-limit input',
              );
            } else {
              expect(
                service.validateMeasurement(probe),
                isNull,
                reason: '${entry.key} rejected below/exact-limit input',
              );
            }
          }
        }

        final exactPhysical = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/exact-physical'),
        );
        expect(
          (await tester.runAsync(
            () => exactPhysical.writeAuthorized(
              record: record,
              authorization: _authorization(setup, record),
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                previous,
              ),
            ),
          ))!.stored,
          isTrue,
        );

        final restartExact = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/restart-exact'),
          budgets: measurement.copyWith(maxRestartDepth: 2),
        );
        expect(
          (await tester.runAsync(
            () => restartExact.writeAuthorized(
              record: record,
              authorization: _authorization(setup, record),
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                previous,
              ),
              restartDepth: 2,
            ),
          ))!.stored,
          isTrue,
        );
        final restartAbove = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/restart-above'),
          budgets: measurement.copyWith(maxRestartDepth: 2),
        );
        expect(
          (await tester.runAsync(
            () => restartAbove.writeAuthorized(
              record: record,
              authorization: _authorization(setup, record),
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                previous,
              ),
              restartDepth: 3,
            ),
          ))!.outcome,
          CanonicalDisplayCacheWriteOutcome.rejectedBudget,
        );

        // ignore: avoid_print
        print(
          'P06_BUDGET_OBSERVED cards=${probe.cards} '
          'sourceSlices=${probe.sourceSlices} blocks=${probe.blockLayouts} '
          'decodedBytes=${probe.decodedBytes} compressedBytes=${probe.compressedBytes} '
          'containerBytes=${probe.containerBytes} ratio=${probe.decompressionRatioCeiling} '
          'continuationDepth=${probe.continuationChainDepth}',
        );
      },
    );

    testWidgets(
      'manifest, memory, disk and temporary aggregates enforce exact budgets',
      (tester) async {
        final setup = await _setup(tester, 'aggregate-bounds');
        final measurements = setup.cold.records
            .map(
              CanonicalDisplayCacheService(
                rootDirectory: Directory('${setup.sandbox.root.path}/probe'),
              ).measureRecord,
            )
            .toList(growable: false);
        final twoDiskBytes = measurements
            .take(2)
            .fold<int>(0, (sum, value) => sum + value.containerBytes);
        final service = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/aggregate'),
          budgets: const CanonicalDisplayCacheBudgets().copyWith(
            maxManifestRecords: 2,
            maxDiskRecords: 2,
            maxDiskBytes: twoDiskBytes,
            maxMemoryRecords: 2,
            maxMemoryBytes: measurements
                .take(2)
                .fold<int>(0, (sum, value) => sum + value.decodedBytes),
          ),
        );
        CanonicalPaginationContinuation? previous;
        for (final record in setup.cold.records) {
          final result = await tester.runAsync(
            () => service.writeAuthorized(
              record: record,
              authorization: _authorization(setup, record),
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                previous,
              ),
            ),
          );
          expect(result!.stored, isTrue);
          previous = _continuation(record);
          expect(service.memoryRecordCount, lessThanOrEqualTo(2));
          expect(
            service.memoryBytes,
            lessThanOrEqualTo(service.budgets.maxMemoryBytes),
          );
          expect(
            await tester.runAsync(() => service.diskRecordCount),
            lessThanOrEqualTo(2),
          );
          expect(
            await tester.runAsync(() => service.diskBytes),
            lessThanOrEqualTo(twoDiskBytes),
          );
        }
        expect(await tester.runAsync(() => service.diskRecordCount), 2);
        expect(service.memoryRecordCount, 2);

        final observationService = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/observed'),
        );
        previous = null;
        for (final record in setup.cold.records) {
          final result = await tester.runAsync(
            () => observationService.writeAuthorized(
              record: record,
              authorization: _authorization(setup, record),
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                previous,
              ),
            ),
          );
          expect(result!.stored, isTrue);
          previous = _continuation(record);
        }
        final observedManifestBytes = await tester.runAsync(
          () => File(
            p.join(observationService.storageRoot.path, 'manifest.v4.json'),
          ).length(),
        );
        final observedDiskBytes = await tester.runAsync(
          () => observationService.diskBytes,
        );
        expect(observationService.memoryRecordCount, 3);
        expect(
          await tester.runAsync(() => observationService.diskRecordCount),
          3,
        );
        expect(
          observedManifestBytes,
          lessThanOrEqualTo(observationService.budgets.maxManifestBytes),
        );
        // ignore: avoid_print
        print(
          'P06_AGGREGATE_OBSERVED records=3 '
          'manifestBytes=$observedManifestBytes '
          'memoryBytes=${observationService.memoryBytes} '
          'diskBytes=$observedDiskBytes',
        );

        final tooSmallTemporary = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/temporary'),
          budgets: const CanonicalDisplayCacheBudgets().copyWith(
            maxTemporaryBytes: measurements.first.containerBytes + 1,
          ),
        );
        final tempResult = await tester.runAsync(
          () => tooSmallTemporary.writeAuthorized(
            record: setup.cold.records.first,
            authorization: _authorization(setup, setup.cold.records.first),
            admissionContext: _context(
              setup,
              setup.cold.records.first.bookStorageScopeDigest,
              null,
            ),
          ),
        );
        expect(
          tempResult!.outcome,
          CanonicalDisplayCacheWriteOutcome.rejectedBudget,
        );
        expect(
          await tester.runAsync(() => tooSmallTemporary.diskRecordCount),
          0,
        );
      },
    );

    testWidgets(
      'accepted current and stable adjacent records pin; preview and rejected do not',
      (tester) async {
        final setup = await _setup(tester, 'pins');
        expect(setup.cold.records.length, 3);
        final currentSignature = setup
            .cold
            .records[1]
            .orderedFinalizedCards
            .first
            .physicalCardSignature;
        final authorization = setup.cold.construction.state
            .authorizeCanonicalCacheRetention(
              currentCardSignature: currentSignature,
              residentRecords: setup.cold.records,
            );
        expect(authorization, isNotNull);
        expect(authorization!.pinnedKeyDigests.length, 3);
        expect(
          authorization.pinnedKeyDigests,
          containsAll(setup.cold.records.map((record) => record.keyDigest)),
        );
        expect(
          setup.cold.construction.state.authorizeCanonicalCacheRetention(
            currentCardSignature: readerSha256('preview-only'),
            residentRecords: setup.cold.records,
          ),
          isNull,
        );
        final empty = ProgressiveDisplayState(
          signature: setup.cold.construction.state.signature,
          sourceChunkCount: _fixture.sourceChunks.length,
        );
        expect(
          empty.authorizeCanonicalCacheRetention(
            currentCardSignature: currentSignature,
            residentRecords: setup.cold.records,
          ),
          isNull,
        );

        final service = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/pinned'),
          budgets: const CanonicalDisplayCacheBudgets().copyWith(
            maxPinnedRecords: 3,
            maxDiskRecords: 2,
            maxMemoryRecords: 2,
          ),
        );
        final pressure = await tester.runAsync(
          () => service.applyRetentionAuthorization(authorization),
        );
        expect(pressure!.withinBudget, isTrue);
        expect(service.pinnedKeyDigests.length, 3);
      },
    );

    testWidgets(
      'deterministic eviction and long traversal stay inside both bounds',
      (tester) async {
        final setup = await _setup(tester, 'traversal');
        final service = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/traversal'),
          budgets: const CanonicalDisplayCacheBudgets().copyWith(
            maxManifestRecords: 4,
            maxDiskRecords: 4,
            maxMemoryRecords: 3,
          ),
        );
        final evicted = <String>[];
        final expectedResident = <String>{};
        for (var index = 0; index < 18; index++) {
          final scope = readerSha256('traversal-scope-$index');
          final record = _recordForScope(
            setup,
            setup.cold.records.first,
            scope,
          );
          final result = await tester.runAsync(
            () => service.writeAuthorized(
              record: record,
              authorization: _authorization(setup, record),
              admissionContext: _context(setup, scope, null),
            ),
          );
          final before = Set<String>.of(expectedResident);
          final proposed = Set<String>.of(expectedResident)
            ..add(record.keyDigest);
          final expectedEvicted = <String>[];
          while (proposed.length > 4) {
            final first = (proposed.toList()..sort()).first;
            proposed.remove(first);
            expectedEvicted.add(first);
          }
          if (expectedEvicted.contains(record.keyDigest)) {
            expect(
              result!.outcome,
              CanonicalDisplayCacheWriteOutcome.rejectedBudget,
            );
            expect(result.evictedKeyDigests, isEmpty);
            expectedResident
              ..clear()
              ..addAll(before);
          } else {
            expect(result!.stored, isTrue);
            expect(result.evictedKeyDigests, expectedEvicted);
            expectedResident
              ..clear()
              ..addAll(proposed);
            evicted.addAll(result.evictedKeyDigests);
          }
          expect(service.memoryRecordCount, lessThanOrEqualTo(3));
          expect(
            await tester.runAsync(() => service.diskRecordCount),
            lessThanOrEqualTo(4),
          );
          expect(
            await tester.runAsync(() => service.diskBytes),
            lessThanOrEqualTo(service.budgets.maxDiskBytes),
          );
        }
        expect(evicted, isNotEmpty);
      },
    );

    testWidgets(
      'replacement pressure preserves prior bytes and failures grant no authority',
      (tester) async {
        final setup = await _setup(tester, 'replacement');
        final record = setup.cold.records.first;
        final root = Directory('${setup.sandbox.root.path}/replacement');
        final initial = CanonicalDisplayCacheService(rootDirectory: root);
        expect(
          (await tester.runAsync(
            () => initial.writeAuthorized(
              record: record,
              authorization: _authorization(setup, record),
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                null,
              ),
            ),
          ))!.stored,
          isTrue,
        );
        final before = await tester.runAsync(
          () => _treeBytes(initial.storageRoot),
        );
        final stateBefore = _stateBytes(setup.cold.construction.state);
        final pressure = CanonicalDisplayCacheService(
          rootDirectory: root,
          budgets: const CanonicalDisplayCacheBudgets().copyWith(
            maxDiskBytes: 1,
            maxMemoryBytes: 1,
          ),
        );
        final result = await tester.runAsync(
          () => pressure.writeAuthorized(
            record: record,
            authorization: _authorization(setup, record),
            admissionContext: _context(
              setup,
              record.bookStorageScopeDigest,
              null,
            ),
          ),
        );
        expect(result!.stored, isFalse);
        expect(
          await tester.runAsync(() => _treeBytes(initial.storageRoot)),
          before,
        );
        expect(_stateBytes(setup.cold.construction.state), stateBefore);
        expect(result.outcome, isNot(CanonicalDisplayCacheWriteOutcome.stored));
      },
    );

    testWidgets(
      'eviction reload regeneration order and protected source bytes are stable',
      (tester) async {
        final setup = await _setup(tester, 'reload');
        final protected = File(
          '${setup.sandbox.root.path}/checkpoint-source.bin',
        );
        final protectedBytes = utf8.encode('source-checkpoint-user-authority');
        await tester.runAsync(
          () => protected.writeAsBytes(protectedBytes, flush: true),
        );
        final service = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/reload-root'),
        );
        CanonicalPaginationContinuation? previous;
        for (final record in setup.cold.records) {
          expect(
            (await tester.runAsync(
              () => service.writeAuthorized(
                record: record,
                authorization: _authorization(setup, record),
                admissionContext: _context(
                  setup,
                  record.bookStorageScopeDigest,
                  previous,
                ),
              ),
            ))!.stored,
            isTrue,
          );
          previous = _continuation(record);
        }
        service.clearMemory();
        final fresh = CanonicalDisplayCacheService(
          rootDirectory: Directory('${setup.sandbox.root.path}/reload-root'),
        );
        previous = null;
        final identities = <String>[];
        for (final record in setup.cold.records) {
          final read = await tester.runAsync(
            () => fresh.readAndAdmit(
              bookScopeDigest: record.bookStorageScopeDigest,
              keyDigest: record.keyDigest,
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                previous,
              ),
            ),
          );
          expect(
            read!.source,
            CanonicalDisplayCacheReadSource.disk,
            reason: '${read.diagnostic} ${read.admission.diagnostics}',
          );
          expect(read.admission.isExact, isTrue);
          identities.addAll(
            read.admission.exactCandidate!.finalizedCards.map(
              (card) => card.identity.signature,
            ),
          );
          previous = read.admission.exactCandidate!.continuation;
        }
        expect(
          identities,
          setup.cold.construction.state.canonicalCards
              .map((card) => card.identity.signature)
              .toList(growable: false),
        );
        expect(await tester.runAsync(protected.readAsBytes), protectedBytes);
        expect(
          setup.cold.records.any(
            (record) => utf8.decode(record.canonicalKeyBytes).contains('index'),
          ),
          isFalse,
        );
      },
    );
  });

  group('[REQ-009, REQ-010, REQ-013, REQ-044, REQ-045, REQ-046, '
      'REQ-048, REQ-051] TASK-P06-007 physical rollout', () {
    testWidgets(
      'cold publication authorized write fresh reopen disk admission and publication are identical',
      (tester) async {
        final setup = await _setup(tester, 'production-round-trip');
        final root = Directory('${setup.sandbox.root.path}/production');
        final writer = CanonicalDisplayCacheService(rootDirectory: root);
        await _writeRecords(tester, setup, writer, setup.cold.records);
        writer.clearMemory();

        final reader = CanonicalDisplayCacheService(rootDirectory: root);
        final reopenedState = _emptyState(setup);
        CanonicalPaginationContinuation? previous;
        final rebuilt = <CanonicalDisplaySegmentRecord>[];
        for (var index = 0; index < setup.cold.records.length; index++) {
          final expected = setup.cold.records[index];
          final read = await tester.runAsync(
            () => reader.readAndAdmit(
              bookScopeDigest: expected.bookStorageScopeDigest,
              keyDigest: expected.keyDigest,
              admissionContext: _context(
                setup,
                expected.bookStorageScopeDigest,
                previous,
              ),
            ),
          );
          expect(read!.source, CanonicalDisplayCacheReadSource.disk);
          expect(read.admission.isExact, isTrue);
          final candidate = read.admission.exactCandidate!;
          final publication = reopenedState.publishCanonical(
            _publicationRequest(
              setup: setup,
              state: reopenedState,
              candidate: candidate,
              generation: 7000 + index,
            ),
          );
          expect(publication, isA<CanonicalDisplayPublicationAccepted>());
          rebuilt.add(
            CanonicalDisplaySegmentRecordBuilder.build(
              bookStorageScopeDigest: expected.bookStorageScopeDigest,
              compatibilityEvidence: expected.compatibilityEvidence,
              sourceSnapshot: setup.harness
                  .canonicalSessionForP04()
                  .sourceSnapshot,
              finalizedCards: candidate.finalizedCards,
              continuation: candidate.continuation,
              acceptedRestart: previous,
            ),
          );
          previous = candidate.continuation;
        }
        expect(
          _stateBytes(reopenedState),
          _stateBytes(setup.cold.construction.state),
        );
        expect(
          rebuilt.map(CanonicalDisplaySegmentCodec.encode).map(base64Encode),
          setup.cold.records
              .map(CanonicalDisplaySegmentCodec.encode)
              .map(base64Encode),
        );
        expect(reader.memoryRecordCount, setup.cold.records.length);
      },
    );

    testWidgets(
      'truncated malformed contradictory corrupt legacy current and future inputs fail closed',
      (tester) async {
        final setup = await _setup(tester, 'corruption');
        final mutations = <String, void Function(Uint8List)>{
          'truncated': (bytes) =>
              bytes.setRange(0, bytes.length - 1, bytes.sublist(1)),
          'magic': (bytes) => bytes[0] ^= 0xff,
          'future-version': (bytes) =>
              ByteData.sublistView(bytes).setUint32(8, 999),
          'legacy-version': (bytes) =>
              ByteData.sublistView(bytes).setUint32(8, 3),
          'decoded-overflow': (bytes) =>
              ByteData.sublistView(bytes).setUint64(12, 0x7fffffffffffffff),
          'compressed-contradiction': (bytes) =>
              ByteData.sublistView(bytes).setUint64(20, 1),
          'checksum': (bytes) => bytes[bytes.length - 1] ^= 0xff,
        };
        for (final entry in mutations.entries) {
          final root = Directory('${setup.sandbox.root.path}/${entry.key}');
          final service = CanonicalDisplayCacheService(rootDirectory: root);
          await _writeRecords(
            tester,
            setup,
            service,
            <CanonicalDisplaySegmentRecord>[setup.cold.records.first],
          );
          service.clearMemory();
          final payload = await tester.runAsync(() => _onlyPayload(service));
          var bytes = Uint8List.fromList(
            await tester.runAsync(payload!.readAsBytes) ?? const <int>[],
          );
          if (entry.key == 'truncated') {
            bytes = Uint8List.fromList(bytes.sublist(0, bytes.length - 1));
          } else {
            entry.value(bytes);
          }
          await tester.runAsync(() => payload.writeAsBytes(bytes, flush: true));
          final fresh = CanonicalDisplayCacheService(rootDirectory: root);
          final read = await tester.runAsync(
            () => fresh.readAndAdmit(
              bookScopeDigest: setup.cold.records.first.bookStorageScopeDigest,
              keyDigest: setup.cold.records.first.keyDigest,
              admissionContext: _context(
                setup,
                setup.cold.records.first.bookStorageScopeDigest,
                null,
              ),
            ),
          );
          expect(
            read!.source,
            CanonicalDisplayCacheReadSource.rejected,
            reason: entry.key,
          );
          expect(fresh.memoryRecordCount, 0);
          if (entry.key == 'checksum') {
            final corruptBytes = await tester.runAsync(payload.readAsBytes);
            final regenerated = await setup.harness.canonicalColdSegments(
              bookStorageScopeDigest:
                  setup.cold.records.first.bookStorageScopeDigest,
              label: 'regenerated-with-corrupt-derivative-present',
            );
            expect(
              regenerated.records
                  .map(CanonicalDisplaySegmentCodec.encode)
                  .map(base64Encode),
              setup.cold.records
                  .map(CanonicalDisplaySegmentCodec.encode)
                  .map(base64Encode),
            );
            expect(await tester.runAsync(payload.readAsBytes), corruptBytes);
          }
        }

        final legacyRoot = Directory(
          '${setup.sandbox.root.path}/legacy-safe-miss',
        );
        await tester.runAsync(() async {
          await legacyRoot.create(recursive: true);
          await File(
            p.join(legacyRoot.path, 'display_cache_v3.json'),
          ).writeAsString('{"formatVersion":3}', flush: true);
        });
        final current = CanonicalDisplayCacheService(rootDirectory: legacyRoot);
        final legacyRead = await tester.runAsync(
          () => current.readAndAdmit(
            bookScopeDigest: setup.cold.records.first.bookStorageScopeDigest,
            keyDigest: setup.cold.records.first.keyDigest,
            admissionContext: _context(
              setup,
              setup.cold.records.first.bookStorageScopeDigest,
              null,
            ),
          ),
        );
        expect(legacyRead!.source, CanonicalDisplayCacheReadSource.absent);
        await _writeRecords(
          tester,
          setup,
          current,
          <CanonicalDisplaySegmentRecord>[setup.cold.records.first],
        );
        current.clearMemory();
        final currentRead = await tester.runAsync(
          () => CanonicalDisplayCacheService(rootDirectory: legacyRoot)
              .readAndAdmit(
                bookScopeDigest:
                    setup.cold.records.first.bookStorageScopeDigest,
                keyDigest: setup.cold.records.first.keyDigest,
                admissionContext: _context(
                  setup,
                  setup.cold.records.first.bookStorageScopeDigest,
                  null,
                ),
              ),
        );
        expect(currentRead!.admission.isExact, isTrue);
        expect(
          await tester.runAsync(
            () => File(
              p.join(legacyRoot.path, 'display_cache_v3.json'),
            ).readAsString(),
          ),
          '{"formatVersion":3}',
        );
      },
    );

    testWidgets(
      'malformed manifest binding counts lengths overflow and missing payload reject without allocation',
      (tester) async {
        final setup = await _setup(tester, 'manifest-corruption');
        final variants =
            <String, Map<String, Object?> Function(Map<String, Object?>)>{
              'binding': (json) => <String, Object?>{
                ...json,
                'manifestDigest': readerSha256('wrong'),
              },
              'count': (json) => <String, Object?>{...json, 'recordCount': 999},
              'total': (json) => <String, Object?>{
                ...json,
                'totalBytes': 0x7fffffffffffffff,
              },
              'tag': (json) => <String, Object?>{...json, 'unexpected': true},
              'future': (json) => <String, Object?>{
                ...json,
                'formatVersion': 999,
              },
            };
        for (final entry in variants.entries) {
          final root = Directory(
            '${setup.sandbox.root.path}/manifest-${entry.key}',
          );
          final service = CanonicalDisplayCacheService(rootDirectory: root);
          await _writeRecords(
            tester,
            setup,
            service,
            <CanonicalDisplaySegmentRecord>[setup.cold.records.first],
          );
          service.clearMemory();
          final manifest = File(
            p.join(service.storageRoot.path, 'manifest.v4.json'),
          );
          final manifestText = await tester.runAsync(manifest.readAsString);
          final json = Map<String, Object?>.from(
            jsonDecode(manifestText!) as Map,
          );
          await tester.runAsync(
            () => manifest.writeAsString(
              canonicalJsonEncode(entry.value(json)),
              flush: true,
            ),
          );
          final fresh = CanonicalDisplayCacheService(rootDirectory: root);
          final read = await tester.runAsync(
            () => fresh.readAndAdmit(
              bookScopeDigest: setup.cold.records.first.bookStorageScopeDigest,
              keyDigest: setup.cold.records.first.keyDigest,
              admissionContext: _context(
                setup,
                setup.cold.records.first.bookStorageScopeDigest,
                null,
              ),
            ),
          );
          expect(
            read!.source,
            CanonicalDisplayCacheReadSource.rejected,
            reason: entry.key,
          );
        }

        final missingRoot = Directory(
          '${setup.sandbox.root.path}/missing-payload',
        );
        final missing = CanonicalDisplayCacheService(
          rootDirectory: missingRoot,
        );
        await _writeRecords(
          tester,
          setup,
          missing,
          <CanonicalDisplaySegmentRecord>[setup.cold.records.first],
        );
        missing.clearMemory();
        await tester.runAsync(
          () async => (await _onlyPayload(missing)).delete(),
        );
        final read = await tester.runAsync(
          () => CanonicalDisplayCacheService(rootDirectory: missingRoot)
              .readAndAdmit(
                bookScopeDigest:
                    setup.cold.records.first.bookStorageScopeDigest,
                keyDigest: setup.cold.records.first.keyDigest,
                admissionContext: _context(
                  setup,
                  setup.cold.records.first.bookStorageScopeDigest,
                  null,
                ),
              ),
        );
        expect(read!.source, CanonicalDisplayCacheReadSource.rejected);
      },
    );

    testWidgets(
      'partial writes and interruption before commit recover while post-commit interruption reopens',
      (tester) async {
        final setup = await _setup(tester, 'interruptions');
        final record = setup.cold.records.first;
        for (final boundary in CanonicalDisplayCacheWriteBoundary.values) {
          final root = Directory(
            '${setup.sandbox.root.path}/interrupt-${boundary.name}',
          );
          final service = CanonicalDisplayCacheService(
            rootDirectory: root,
            writeInterceptor: (seen) {
              if (seen == boundary) throw StateError('interrupt-${seen.name}');
            },
          );
          final result = await tester.runAsync(
            () => service.writeAuthorized(
              record: record,
              authorization: _authorization(setup, record),
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                null,
              ),
            ),
          );
          expect(result!.outcome, CanonicalDisplayCacheWriteOutcome.ioFailure);
          final fresh = CanonicalDisplayCacheService(rootDirectory: root);
          final read = await tester.runAsync(
            () => fresh.readAndAdmit(
              bookScopeDigest: record.bookStorageScopeDigest,
              keyDigest: record.keyDigest,
              admissionContext: _context(
                setup,
                record.bookStorageScopeDigest,
                null,
              ),
            ),
          );
          final committed =
              boundary.index >=
              CanonicalDisplayCacheWriteBoundary.afterManifestRename.index;
          expect(read!.admission.isExact, committed, reason: boundary.name);
          expect(
            await tester.runAsync(() => _temporaryFiles(fresh)),
            isEmpty,
            reason: boundary.name,
          );
        }

        final orphanRoot = Directory(
          '${setup.sandbox.root.path}/partial-orphan',
        );
        final orphanService = CanonicalDisplayCacheService(
          rootDirectory: orphanRoot,
        );
        await tester.runAsync(() async {
          await orphanService.storageRoot.create(recursive: true);
          await File(
            p.join(orphanService.storageRoot.path, 'payload.tmp-partial'),
          ).writeAsBytes(const <int>[1, 2, 3], flush: true);
        });
        await tester.runAsync(orphanService.ensureInitialized);
        expect(
          await tester.runAsync(() => _temporaryFiles(orphanService)),
          isEmpty,
        );
      },
    );

    testWidgets(
      'payload success followed by manifest failure retains the previous valid manifest and bytes',
      (tester) async {
        final setup = await _setup(tester, 'manifest-rollback');
        final root = Directory('${setup.sandbox.root.path}/manifest-rollback');
        final initial = CanonicalDisplayCacheService(rootDirectory: root);
        await _writeRecords(
          tester,
          setup,
          initial,
          <CanonicalDisplaySegmentRecord>[setup.cold.records.first],
        );
        initial.clearMemory();
        final manifest = File(
          p.join(initial.storageRoot.path, 'manifest.v4.json'),
        );
        final previousManifest = await tester.runAsync(manifest.readAsBytes);
        final previousPayload = await tester.runAsync(
          () => _onlyPayload(initial),
        );
        final previousPayloadBytes = await tester.runAsync(
          previousPayload!.readAsBytes,
        );

        final failing = CanonicalDisplayCacheService(
          rootDirectory: root,
          writeInterceptor: (boundary) {
            if (boundary ==
                CanonicalDisplayCacheWriteBoundary.beforeManifestRename) {
              throw StateError('manifest-install-failure');
            }
          },
        );
        final second = setup.cold.records[1];
        final result = await tester.runAsync(
          () => failing.writeAuthorized(
            record: second,
            authorization: _authorization(setup, second),
            admissionContext: _context(
              setup,
              second.bookStorageScopeDigest,
              _continuation(setup.cold.records.first),
            ),
          ),
        );
        expect(result!.outcome, CanonicalDisplayCacheWriteOutcome.ioFailure);
        expect(await tester.runAsync(manifest.readAsBytes), previousManifest);
        expect(
          await tester.runAsync(previousPayload.readAsBytes),
          previousPayloadBytes,
        );

        final reopened = CanonicalDisplayCacheService(rootDirectory: root);
        final retained = await tester.runAsync(
          () => reopened.readAndAdmit(
            bookScopeDigest: setup.cold.records.first.bookStorageScopeDigest,
            keyDigest: setup.cold.records.first.keyDigest,
            admissionContext: _context(
              setup,
              setup.cold.records.first.bookStorageScopeDigest,
              null,
            ),
          ),
        );
        expect(retained!.admission.isExact, isTrue);
        final uncommitted = await tester.runAsync(
          () => reopened.readAndAdmit(
            bookScopeDigest: second.bookStorageScopeDigest,
            keyDigest: second.keyDigest,
            admissionContext: _context(
              setup,
              second.bookStorageScopeDigest,
              _continuation(setup.cold.records.first),
            ),
          ),
        );
        expect(uncommitted!.source, CanonicalDisplayCacheReadSource.absent);
      },
    );

    testWidgets(
      'cancellation and stale generation fail before commit and cannot revoke a complete commit',
      (tester) async {
        final setup = await _setup(tester, 'freshness');
        final record = setup.cold.records.first;
        for (final cancelledCase in <bool>[true, false]) {
          for (final boundary in CanonicalDisplayCacheWriteBoundary.values) {
            var cancelled = false;
            var current = true;
            final root = Directory(
              '${setup.sandbox.root.path}/${cancelledCase ? 'cancel' : 'stale'}-${boundary.name}',
            );
            final service = CanonicalDisplayCacheService(
              rootDirectory: root,
              writeInterceptor: (seen) {
                if (seen == boundary) {
                  if (cancelledCase) {
                    cancelled = true;
                  } else {
                    current = false;
                  }
                }
              },
            );
            final result = await tester.runAsync(
              () => service.writeAuthorized(
                record: record,
                authorization: _authorization(setup, record),
                admissionContext: _context(
                  setup,
                  record.bookStorageScopeDigest,
                  null,
                ),
                isCancelled: () => cancelled,
                isCurrent: () => current,
              ),
            );
            final afterCommit =
                boundary.index >=
                CanonicalDisplayCacheWriteBoundary.afterManifestRename.index;
            expect(result!.stored, afterCommit, reason: boundary.name);
            expect(service.memoryRecordCount, afterCommit ? 1 : 0);
          }
        }
      },
    );

    testWidgets(
      'concurrent same-key and cross-book writers serialize without prefix collision',
      (tester) async {
        final setup = await _setup(tester, 'concurrency');
        final root = Directory('${setup.sandbox.root.path}/concurrent');
        final services = List<CanonicalDisplayCacheService>.generate(
          4,
          (_) => CanonicalDisplayCacheService(rootDirectory: root),
        );
        final same = await tester.runAsync(
          () => Future.wait(
            services.map(
              (service) => service.writeAuthorized(
                record: setup.cold.records.first,
                authorization: _authorization(setup, setup.cold.records.first),
                admissionContext: _context(
                  setup,
                  setup.cold.records.first.bookStorageScopeDigest,
                  null,
                ),
              ),
            ),
          ),
        );
        expect(same!.every((result) => result.stored), isTrue);

        final records = <CanonicalDisplaySegmentRecord>[
          _recordForScope(
            setup,
            setup.cold.records.first,
            readerSha256('book-a'),
          ),
          _recordForScope(
            setup,
            setup.cold.records.first,
            readerSha256('book-a-sibling'),
          ),
          _recordForScope(
            setup,
            setup.cold.records.first,
            readerSha256('book-b'),
          ),
        ];
        final different = await tester.runAsync(
          () => Future.wait(<Future<CanonicalDisplayCacheWriteResult>>[
            for (var index = 0; index < records.length; index++)
              services[index].writeAuthorized(
                record: records[index],
                authorization: _authorization(setup, records[index]),
                admissionContext: _context(
                  setup,
                  records[index].bookStorageScopeDigest,
                  null,
                ),
              ),
          ]),
        );
        expect(different!.every((result) => result.stored), isTrue);
        expect(await tester.runAsync(() => services.first.diskRecordCount), 4);
        for (final record in records) {
          final read = await tester.runAsync(
            () =>
                CanonicalDisplayCacheService(rootDirectory: root).readAndAdmit(
                  bookScopeDigest: record.bookStorageScopeDigest,
                  keyDigest: record.keyDigest,
                  admissionContext: _context(
                    setup,
                    record.bookStorageScopeDigest,
                    null,
                  ),
                ),
          );
          expect(read!.admission.isExact, isTrue);
        }
      },
    );

    testWidgets(
      'symlink swap path traversal and sibling scope attacks retain outside bytes',
      (tester) async {
        final setup = await _setup(tester, 'symlink');
        final outside = File(
          '${setup.sandbox.root.path}/outside-authority.bin',
        );
        const outsideBytes = <int>[9, 8, 7, 6];
        await tester.runAsync(
          () => outside.writeAsBytes(outsideBytes, flush: true),
        );
        final root = Directory('${setup.sandbox.root.path}/symlink-root');
        late CanonicalDisplaySegmentRecord record;
        record = setup.cold.records.first;
        late final CanonicalDisplayCacheService service;
        service = CanonicalDisplayCacheService(
          rootDirectory: root,
          writeInterceptor: (boundary) async {
            if (boundary ==
                CanonicalDisplayCacheWriteBoundary.beforePayloadRename) {
              final payloads = await _temporaryFiles(service);
              final temporary = payloads.single;
              final finalPath = temporary.path.substring(
                0,
                temporary.path.indexOf('.tmp-'),
              );
              await Link(finalPath).create(outside.path);
            }
          },
        );
        final result = await tester.runAsync(
          () => service.writeAuthorized(
            record: record,
            authorization: _authorization(setup, record),
            admissionContext: _context(
              setup,
              record.bookStorageScopeDigest,
              null,
            ),
          ),
        );
        expect(result!.outcome, CanonicalDisplayCacheWriteOutcome.ioFailure);
        expect(await tester.runAsync(outside.readAsBytes), outsideBytes);
        final invalid = await tester.runAsync(
          () => service.readAndAdmit(
            bookScopeDigest: '../${record.bookStorageScopeDigest}',
            keyDigest: record.keyDigest,
            admissionContext: _context(
              setup,
              record.bookStorageScopeDigest,
              null,
            ),
          ),
        );
        expect(invalid!.source, CanonicalDisplayCacheReadSource.rejected);
      },
    );

    testWidgets(
      'pinned pressure full eviction reload and corrupt warm regeneration preserve accepted state',
      (tester) async {
        final setup = await _setup(tester, 'pressure-regeneration');
        final root = Directory('${setup.sandbox.root.path}/pressure');
        final service = CanonicalDisplayCacheService(rootDirectory: root);
        await _writeRecords(tester, setup, service, setup.cold.records);
        final current = setup
            .cold
            .records[1]
            .orderedFinalizedCards
            .first
            .physicalCardSignature;
        final pins = setup.cold.construction.state
            .authorizeCanonicalCacheRetention(
              currentCardSignature: current,
              residentRecords: service.memoryRecords,
            )!;
        final tight = CanonicalDisplayCacheService(
          rootDirectory: root,
          budgets: const CanonicalDisplayCacheBudgets().copyWith(
            maxDiskRecords: 2,
            maxMemoryRecords: 2,
          ),
        );
        final pressure = await tester.runAsync(
          () => tight.applyRetentionAuthorization(pins),
        );
        expect(pressure!.withinBudget, isFalse);
        expect(pressure.pinnedPressure, isTrue);
        expect(await tester.runAsync(() => tight.diskRecordCount), 3);

        final acceptedBefore = _stateBytes(setup.cold.construction.state);
        final evictor = CanonicalDisplayCacheService(rootDirectory: root);
        final eviction = await tester.runAsync(evictor.evictAllUnpinned);
        expect(eviction!.withinBudget, isTrue);
        expect(await tester.runAsync(() => evictor.diskRecordCount), 0);
        final regenerated = await setup.harness.canonicalColdSegments(
          bookStorageScopeDigest:
              setup.cold.records.first.bookStorageScopeDigest,
          label: 'regenerated-after-complete-eviction',
        );
        expect(
          regenerated.records
              .map(CanonicalDisplaySegmentCodec.encode)
              .map(base64Encode),
          setup.cold.records
              .map(CanonicalDisplaySegmentCodec.encode)
              .map(base64Encode),
        );
        expect(_stateBytes(setup.cold.construction.state), acceptedBefore);
      },
    );

    testWidgets(
      'CHANGE-20260914-039 derivative queue detaches and coalesces writes',
      (tester) async {
        final setup = await _setupTiny(tester, 'detached-queue');
        final record = setup.cold.records.first;

        final evidence = await tester.runAsync(() async {
          final entered = Completer<void>();
          final release = Completer<void>();
          final service = CanonicalDisplayCacheService(
            rootDirectory: Directory('${setup.sandbox.root.path}/queue'),
            writeInterceptor: (boundary) async {
              if (boundary ==
                  CanonicalDisplayCacheWriteBoundary
                      .beforePayloadTemporaryWrite) {
                if (!entered.isCompleted) entered.complete();
                await release.future;
              }
            },
          );
          final first = service.enqueueAuthorizedWrite(
            record: record,
            authorization: _authorization(setup, record),
            admissionContext: _context(
              setup,
              record.bookStorageScopeDigest,
              null,
            ),
          );
          final joined = service.enqueueAuthorizedWrite(
            record: record,
            authorization: _authorization(setup, record),
            admissionContext: _context(
              setup,
              record.bookStorageScopeDigest,
              null,
            ),
          );
          final queuedBeforeWrite = service.queuedWriteCount;
          final reachedWriteBoundary = await Future.any<bool>([
            entered.future.then((_) => true),
            first.then((_) => false),
          ]);
          var completedWhileBlocked = false;
          first.then((_) => completedWhileBlocked = true);
          await Future<void>.delayed(Duration.zero);
          final wasCompletedWhileBlocked = completedWhileBlocked;
          release.complete();
          final result = await first;
          return (
            joinedSameFuture: identical(joined, first),
            queuedBeforeWrite: queuedBeforeWrite,
            reachedWriteBoundary: reachedWriteBoundary,
            completedWhileBlocked: wasCompletedWhileBlocked,
            result: result,
            queuedAfterWrite: service.queuedWriteCount,
          );
        });

        expect(evidence!.joinedSameFuture, isTrue);
        expect(evidence.queuedBeforeWrite, 1);
        expect(
          evidence.reachedWriteBoundary,
          isTrue,
          reason:
              '${evidence.result.outcome.name}: ${evidence.result.diagnostic}',
        );
        expect(evidence.completedWhileBlocked, isFalse);
        expect(evidence.result.stored, isTrue);
        expect(evidence.queuedAfterWrite, 0);
      },
    );
  });
}

final class _Setup {
  const _Setup(this.sandbox, this.harness, this.cold);
  final ReaderContractSandbox sandbox;
  final ReaderCorePaginationHarness harness;
  final ReaderCanonicalSegmentConstruction cold;
}

Future<_Setup> _setup(WidgetTester tester, String label) async {
  final sandbox = (await tester.runAsync(ReaderContractSandbox.create))!;
  addTearDown(sandbox.close);
  final harness = await ReaderCorePaginationHarness.install(
    tester: tester,
    sourceChunks: _fixture.sourceChunks,
    bookId: 'p06-006-$label',
    publicationFingerprint: 'p06-006-publication-$label',
    stateCacheKey: 'p06-006-state-$label',
  );
  final cold = await harness.canonicalColdSegments(
    bookStorageScopeDigest: readerSha256('p06-006-scope-$label'),
    label: label,
  );
  return _Setup(sandbox, harness, cold);
}

Future<_Setup> _setupTiny(WidgetTester tester, String label) async {
  final sandbox = (await tester.runAsync(ReaderContractSandbox.create))!;
  addTearDown(sandbox.close);
  final harness = await ReaderCorePaginationHarness.install(
    tester: tester,
    sourceChunks: const <BookChunk>[
      BookChunk(
        index: 0,
        type: BookChunkType.text,
        sourceFile: 'chapter.xhtml',
        text: 'A bounded canonical card for detached cache queue evidence.',
        logicalParagraphId: 'queue-paragraph',
      ),
    ],
    bookId: 'p06-006-$label',
    publicationFingerprint: 'p06-006-publication-$label',
    stateCacheKey: 'p06-006-state-$label',
  );
  final cold = await harness.canonicalInitialSegment(
    bookStorageScopeDigest: readerSha256('p06-006-scope-$label'),
    label: label,
  );
  return _Setup(sandbox, harness, cold);
}

CanonicalDisplayCacheWriteAuthorization _authorization(
  _Setup setup,
  CanonicalDisplaySegmentRecord record,
) {
  final result = setup.cold.construction.state.authorizeCanonicalCacheWrite(
    record,
  );
  if (result == null) {
    throw StateError('Accepted publication did not authorize record.');
  }
  return result;
}

CanonicalDisplaySegmentAdmissionContext _context(
  _Setup setup,
  String scope,
  CanonicalPaginationContinuation? acceptedRestart,
) {
  final session = setup.harness.canonicalSessionForP04();
  return CanonicalDisplaySegmentAdmissionContext(
    bookStorageScopeDigest: scope,
    publicationFingerprint: session.sourceSnapshot.publicationFingerprint,
    sourceSnapshot: session.sourceSnapshot,
    currentCompatibilityEvidence: ReaderCompatibilityEvidence.fromIdentity(
      setup
          .harness
          .paginatorLayout
          .contract!
          .identities
          .readerCompatibilityIdentity,
    ),
    supportedCompatibilityRevisions: ReaderCompatibilityRevisionSupport.current(
      parserSourceSchemaIdentities: <String>[
        session.sourceSnapshot.parserSourceIdentity,
      ],
    ),
    controlledLayoutIdentity: setup.harness.layoutIdentity,
    paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
    acceptedFinalizedCards: setup.cold.construction.state.canonicalCards,
    acceptedRestart: acceptedRestart,
  );
}

CanonicalDisplaySegmentRecord _recordForScope(
  _Setup setup,
  CanonicalDisplaySegmentRecord template,
  String scope,
) {
  final bySignature = <String, CanonicalFinalizedReaderCard>{
    for (final card in setup.cold.construction.state.canonicalCards)
      card.identity.signature: card,
  };
  return CanonicalDisplaySegmentRecordBuilder.build(
    bookStorageScopeDigest: scope,
    compatibilityEvidence:
        CanonicalDisplaySegmentCompatibilityEvidence.fromReaderEvidence(
          ReaderCompatibilityEvidence.fromIdentity(
            setup
                .harness
                .paginatorLayout
                .contract!
                .identities
                .readerCompatibilityIdentity,
          ),
        ),
    sourceSnapshot: setup.harness.canonicalSessionForP04().sourceSnapshot,
    finalizedCards: template.orderedFinalizedCards
        .map((card) => bySignature[card.physicalCardSignature]!)
        .toList(growable: false),
    continuation: _continuation(template),
  );
}

CanonicalPaginationContinuation? _previousContinuation(
  List<CanonicalDisplaySegmentRecord> records,
  CanonicalDisplaySegmentRecord record,
) {
  final index = records.indexOf(record);
  return index <= 0 ? null : _continuation(records[index - 1]);
}

CanonicalPaginationContinuation _continuation(
  CanonicalDisplaySegmentRecord record,
) {
  final decoded = CanonicalPaginationContinuationCodec.decode(
    record.continuationEvidence.canonicalEncoding,
  );
  if (decoded is! CanonicalPaginationContinuationAccepted) {
    throw StateError('Canonical continuation did not decode.');
  }
  return decoded.continuation;
}

String _stateBytes(ProgressiveDisplayState state) =>
    canonicalJsonEncode(<String, Object?>{
      'cards': state.canonicalCards
          .map((card) => card.identity.signature)
          .toList(growable: false),
      'continuation': state.acceptedCanonicalContinuation?.canonicalEncoding,
      'cacheWrite': state.hasCanonicalCacheWriteAuthority,
    });

Future<String> _treeBytes(Directory root) async {
  if (!await root.exists()) return '';
  final entries = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      entries.add(
        '${p.relative(entity.path, from: root.path)}:'
        '${base64Encode(await entity.readAsBytes())}',
      );
    }
  }
  entries.sort();
  return entries.join('|');
}

Future<void> _writeRecords(
  WidgetTester tester,
  _Setup setup,
  CanonicalDisplayCacheService service,
  Iterable<CanonicalDisplaySegmentRecord> records,
) async {
  CanonicalPaginationContinuation? previous;
  for (final record in records) {
    final result = await tester.runAsync(
      () => service.writeAuthorized(
        record: record,
        authorization: _authorization(setup, record),
        admissionContext: _context(
          setup,
          record.bookStorageScopeDigest,
          previous,
        ),
      ),
    );
    if (result == null || !result.stored) {
      throw StateError(
        'Physical write failed: ${result?.outcome} ${result?.diagnostic}',
      );
    }
    previous = _continuation(record);
  }
}

Future<File> _onlyPayload(CanonicalDisplayCacheService service) async {
  final payloads = <File>[];
  await for (final entity in service.storageRoot.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.cseg4.gz')) {
      payloads.add(entity);
    }
  }
  if (payloads.length != 1) {
    throw StateError('Expected one payload, got ${payloads.length}.');
  }
  return payloads.single;
}

Future<List<File>> _temporaryFiles(CanonicalDisplayCacheService service) async {
  if (!await service.storageRoot.exists()) return const <File>[];
  final files = <File>[];
  await for (final entity in service.storageRoot.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && p.basename(entity.path).contains('.tmp-')) {
      files.add(entity);
    }
  }
  return files;
}

ProgressiveDisplayState _emptyState(_Setup setup) => ProgressiveDisplayState(
  signature: DisplayGenerationSignature(
    bookId: setup.harness.bookId,
    parsedContentVersion: 1,
    layoutSignature: setup.harness.layoutIdentity,
    settingsSignature: 'p06-007-controlled',
    viewportSignature: setup.harness.environment.inputs.diagnosticJson,
    cacheKey: 'p06-007-controlled',
  ),
  sourceChunkCount: _fixture.sourceChunks.length,
);

CanonicalDisplayPublicationRequest _publicationRequest({
  required _Setup setup,
  required ProgressiveDisplayState state,
  required CanonicalDisplaySegmentExactCandidate candidate,
  required int generation,
}) => CanonicalDisplayPublicationRequest(
  operation: state.canonicalCards.isEmpty
      ? CanonicalDisplayPublicationOperation.initial
      : CanonicalDisplayPublicationOperation.append,
  sessionIdentity: 'p06-007-production-reopen',
  generationIdentity: generation,
  currentGenerationIdentity: () => generation,
  sourceSnapshot: setup.harness.canonicalSessionForP04().sourceSnapshot,
  controlledLayoutIdentity: setup.harness.layoutIdentity,
  paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
  finalizedCards: candidate.finalizedCards,
  continuation: candidate.continuation,
  predecessorContinuation: state.acceptedCanonicalContinuation,
  committedCard: state.canonicalCards.isEmpty
      ? null
      : state.canonicalCards.first,
  isCancelled: () => false,
);
