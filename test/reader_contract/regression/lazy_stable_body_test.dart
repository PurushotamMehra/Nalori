import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as image;
// Existing sqflite_common_ffi transitive dependency, used for read-only audit.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/lazy_stable_card.dart';
import 'package:nalori/services/lazy_stable_card_service.dart';
import 'package:nalori/services/lazy_checkpoint_recovery.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_epub_index_service.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/reader_card_paginator.dart';
import 'package:nalori/services/reader_checkpoint_store.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';

import '../pagination/reader_core_pagination_harness.dart';
import '../support/reader_contract_sandbox.dart';

// New-format proofs. Historical R02/L02 remain in their unchanged file.
void main() {
  late ReaderCoreParsedFixture fixture;
  late File imageFixture;
  var sequence = 0;
  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('lazy-stable-body-');
    // Separate generated EPUB; frozen source fixture bytes stay untouched.
    final original = ZipDecoder().decodeBytes(
      await fixture.epubFile.readAsBytes(),
    );
    final withImage = Archive();
    for (final entry in original.files) {
      if (entry.name.endsWith('chapter-two.xhtml')) {
        final text = utf8
            .decode(entry.content as List<int>)
            .replaceFirst(
              '</body>',
              '<img src="../images/stable.png" alt="Stable atomic image"/></body>',
            );
        withImage.addFile(ArchiveFile.string(entry.name, text));
      } else if (entry.name.endsWith('.opf')) {
        final text = utf8
            .decode(entry.content as List<int>)
            .replaceFirst(
              '</manifest>',
              '<item id="stableImage" href="images/stable.png" media-type="image/png"/></manifest>',
            );
        withImage.addFile(ArchiveFile.string(entry.name, text));
      } else {
        withImage.addFile(entry);
      }
    }
    final png = image.encodePng(image.Image.rgb(4, 4)..fill(0xff2277cc));
    withImage.addFile(ArchiveFile('OEBPS/images/stable.png', png.length, png));
    imageFixture = File('${fixture.temporaryDirectory.path}/stable-image.epub');
    await imageFixture.writeAsBytes(ZipEncoder().encode(withImage)!);
  });
  tearDownAll(() => fixture.close());

  Future<_Run> generate(
    WidgetTester tester, {
    required bool precedingA,
    bool legacy = false,
    bool evict = false,
    bool owningA = false,
    bool withImage = false,
    ReaderCorePaginationLayout layoutKind = ReaderCorePaginationLayout.standard,
  }) async {
    final lazy = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(
            '${fixture.temporaryDirectory.path}/reopen-${sequence++}',
          ),
        ),
        workCoordinator: SharedLazySectionWorkCoordinator(),
      ),
    );
    late LazyEpubIndex index;
    late LazyLoadedContentWindow window;
    // Close each repository before the next run: the later run really reloads
    // the index and owning section without the earlier repository or cache.
    await tester.runAsync(() async {
      try {
        index = await lazy.open(withImage ? imageFixture : fixture.epubFile);
        final item = owningA
            ? index.spine.firstWhere((item) => item.isLinear)
            : index.spine.lastWhere((item) => item.isLinear);
        window = await lazy.loadAround(
          StableBookLocation(
            bookId: index.bookId,
            publicationFingerprint: index.publicationFingerprint,
            spineIndex: item.index,
            href: item.href,
            normalizedHref: item.normalizedHref,
            sourceChecksum: item.sourceChecksum,
            sourceParserVersion: lazyParsedSectionParserVersion,
            localChunkIndex: 0,
          ),
          before: precedingA ? 1 : 0,
          after: 0,
        );
        if (evict) {
          final b = window.sections.last;
          final target = lazy.locationForSectionChunk(b, 0);
          await lazy.prepareNavigation(
            lazy.initialLocation(),
            canCommit: () => true,
          );
          lazy.handleMemoryPressure();
          expect(
            lazy.loadedSpineIndices,
            isNot(contains(b.identity.spineIndex)),
          );
          final reloaded = await lazy.prepareNavigation(
            target,
            canCommit: () => true,
          );
          expect(reloaded.window, isNotNull);
          lazy.handleMemoryPressure();
          window = lazy.loadedWindow();
        }
      } finally {
        await lazy.close();
      }
    });
    expect(window.sections.length, precedingA ? 2 : 1);
    final harness = await ReaderCorePaginationHarness.install(
      tester: tester,
      sourceChunks: window.chunks,
      layout: layoutKind,
      bookId: index.bookId,
      publicationFingerprint: index.publicationFingerprint,
    );
    final snapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: index.bookId,
      publicationFingerprint: index.publicationFingerprint,
      parserSourceIdentity: lazyParsedSectionParserVersion,
      sourceRevision: readerSha256(
        window.chunks.map((c) => c.toJson()).toList(),
      ),
      sourceChunks: window.chunks,
      sourceKeys: [
        for (var i = 0; i < window.chunks.length; i++)
          CanonicalPaginationSourceKey(
            sourceIdentity: window.sourceIdentitiesByChunkIndex[i]!.stableKey,
            sectionIdentity:
                window.sourceIdentitiesByChunkIndex[i]!.section.stableKey,
            spineIdentity:
                window.sourceIdentitiesByChunkIndex[i]!.section.stableKey,
            sourceOrdinalHint: i,
          ),
      ],
    );
    // Bind P05 to this exact lazy snapshot, not the harness's generic fixture
    // source keys. Keep its production font resolver and controlled environment.
    final inputs = harness.environment.inputs;
    final baseLayout = harness.paginatorLayout;
    final font = await ReaderFontEvidenceGate().capture(
      settings: baseLayout.settings,
      stableSourceIdentity: window.sourceIdentitiesByChunkIndex[0]!.stableKey,
      sourceStartUtf16: 0,
      sourceText: window.chunks.first.text ?? '',
      locale: inputs.locale.toLanguageTag(),
      textScaler: TextScaler.linear(inputs.textScaleFactor),
    );
    final built = ReaderLayoutContractBuilder.build(
      ReaderLayoutContractBuildInput(
        deckSize: inputs.viewportSize,
        mediaQuerySize: inputs.viewportSize,
        viewPadding: inputs.safeArea,
        locale: inputs.locale,
        defaultDirection: inputs.textDirection,
        textScaler: TextScaler.linear(inputs.textScaleFactor),
        settings: baseLayout.settings,
        fontOutcome: font,
        captureFreshnessEvidence: 'reopen-payload-proof',
        publicationFingerprint: snapshot.publicationFingerprint,
        parserSourceSchemaIdentity: snapshot.parserSourceIdentity,
        sourceRevision: snapshot.sourceRevision,
        sourceSnapshotDigest: snapshot.snapshotDigest,
      ),
    );
    expect(built, isA<ReaderLayoutContractReady>());
    final contract = (built as ReaderLayoutContractReady).contract;
    final body = contract.typography[ReaderLayoutTextRole.body];
    final heading = contract.typography[ReaderLayoutTextRole.heading];
    var invalidateFont = false;
    final imageEvidence = <String, ReaderImageMetricEvidence>{};
    for (final chunk in window.chunks) {
      final bytes = chunk.imageBytes;
      if (bytes != null) {
        imageEvidence[readerSha256(bytes)] = (await tester.runAsync(
          () => resolveReaderImageMetricEvidence(bytes),
        ))!;
      }
    }
    final layout = ReaderCardPaginatorLayout(
      availableWidth: contract.geometry.bodySize.width,
      pageHeightBudget: contract.geometry.ordinaryPaginationHeightBudget,
      physicalTextBudget: contract.geometry.publisherPaginationHeightBudget,
      minUsefulHeight: contract.geometry.minUsefulHeight,
      tinyWordCount: contract.settingsPolicy.densityTinyWordCount,
      tinyHeightRatio: contract.settingsPolicy.densityTinyHeightRatio,
      settings: baseLayout.settings,
      bodyStyle: body.toTextStyle(),
      headingStyle: heading.toTextStyle(),
      bodyStrut: body.toStrutStyle(),
      headingStrut: heading.toStrutStyle(),
      textScaler: TextScaler.noScaling,
      contract: contract,
      fontEvidenceResolver: (chunk, text) =>
          invalidateFont ? [] : baseLayout.fontEvidenceResolver!(chunk, text),
      imageEvidenceResolver: (chunk) => chunk.imageBytes == null
          ? null
          : imageEvidence[readerSha256(chunk.imageBytes!)],
    );
    final authority = LazyStableSectionAuthority.capture(
      index,
      window.sections.last,
    );
    final packing = LazyStableCardEmitter.packingIdentity(authority, contract);
    final root = snapshot.owners.firstWhere(
      (owner) =>
          owner.sectionIdentity == window.sections.last.identity.stableKey,
    );
    final controlledIdentity = legacy ? contract.identity : packing;
    final session = CanonicalReaderPaginationSession(
      sourceSnapshot: snapshot,
      controlledLayoutIdentity: controlledIdentity,
      layout: layout,
    );
    final result = await session.generateInitial(
      restart: CanonicalPaginationTrustedSectionStart(
        sectionIdentity: root.sectionIdentity,
        sourceIdentity: root.sourceIdentity,
        sourceOrdinalHint: root.sourceOrdinalHint,
      ),
      operation: harness.canonicalOperationForP04(),
    );
    expect(result, isA<CanonicalReaderPaginationPathAccepted>());
    final accepted = result as CanonicalReaderPaginationPathAccepted;
    expect(accepted.continuation.terminal, isTrue);
    expect(accepted.publishableCards, isNotEmpty);
    expect(
      accepted.boundedWorkEntriesConsumed,
      lessThanOrEqualTo(CanonicalPaginationBounds.normalWorkEnvelope),
    );
    final card = accepted.publishableCards.first;
    expect(
      snapshot.sourceCount,
      lessThanOrEqualTo(CanonicalPaginationBounds.activeSourceCeiling),
    );
    expect(
      session.acceptedPublishedCards.length,
      lessThanOrEqualTo(CanonicalPaginationBounds.activeCardCeiling),
    );
    expect(
      session.checkpointIndex.records.length,
      lessThanOrEqualTo(
        CanonicalPaginationBounds.residentContinuationRecordBasis,
      ),
    );
    // ignore: avoid_print
    print(
      'LAZY_STABLE sources=${snapshot.sourceCount} cards=${session.acceptedPublishedCards.length} guards=${session.checkpointIndex.records.length} work=${accepted.boundedWorkEntriesConsumed} entered=${accepted.diagnostics.sourceChunksEntered}',
    );
    final checkpoint = ReaderCheckpoint.create(
      bookId: index.bookId,
      publicationFingerprint: index.publicationFingerprint,
      semanticAnchor: card.identity.firstMeaningfulAnchor(),
      layoutFingerprint: controlledIdentity,
      state: ReaderCheckpointState.exactCommitted,
      sessionEpoch: 1,
      revision: 1,
      navigationSource: 'entry-reopen-proof',
      committedAtMillis: 1,
      card: card.identity,
      stableLocation: window.locationsByChunkIndex[root.sourceOrdinalHint],
    );
    // This is the real format/checksum codec, not a restoration/UI simulation.
    final decoded = ReaderCheckpoint.fromPayload(
      checkpoint.payloadJson(),
      integrityChecksum: checkpoint.integrityChecksum,
    );
    expect(decoded.card!.signature, card.identity.signature);
    return _Run(
      card,
      decoded,
      authority,
      contract,
      session,
      harness,
      index,
      window,
      () => invalidateFont = true,
    );
  }

  testWidgets(
    'R03 stable emission is byte-identical A+B, B-only and eviction/reload',
    (tester) async {
      final expanded = await generate(tester, precedingA: true);
      final alone = await generate(tester, precedingA: false);
      final reloaded = await generate(tester, precedingA: false, evict: true);
      expect(expanded.card.card.index, 14);
      expect(alone.card.card.index, 0);
      expect(expanded.card.card.toJson(), isNot(alone.card.card.toJson()));
      expect(expanded.body.canonicalEncoding, alone.body.canonicalEncoding);
      expect(alone.body.canonicalEncoding, reloaded.body.canonicalEncoding);
      expect(expanded.body.signature, alone.body.signature);
      final projection = LazyStableResidentProjection(
        authority: expanded.authority,
        snapshot: expanded.session.sourceSnapshot,
      );
      expect(projection.resolve(0, runtimeHint: 14), 14);
      expect(() => projection.resolve(0, runtimeHint: 0), throwsStateError);
      expect(
        projection
            .projectSlice(alone.body.sourceSlices.first, runtimeHint: 14)
            .sourceOrdinalHint,
        14,
      );
      expect(
        () => projection.projectSlice(
          alone.body.sourceSlices.first,
          runtimeHint: 0,
        ),
        throwsStateError,
      );
      final a = LazyStableSectionAuthority.capture(
        expanded.index,
        expanded.window.sections.first,
      );
      expect(a.address(0), isNot(expanded.authority.address(0)));
      expect(expanded.body.toJson()['payload'] as Map, isNot(contains('i')));
      expect(
        (expanded.body.toJson()['slices'] as List).first as Map,
        isNot(contains('sourceOrdinalHint')),
      );
    },
  );

  testWidgets(
    'R04 new checkpoint real SQLite close/reopen restores exact body',
    (tester) async {
      final expanded = await generate(tester, precedingA: true);
      final sandbox = (await tester.runAsync(ReaderContractSandbox.create))!;
      try {
        final checkpoint = ReaderCheckpoint.createLazy(
          bookId: expanded.index.bookId,
          body: expanded.body,
          sessionEpoch: 1,
          revision: 1,
          committedAtMillis: 1,
        );
        await tester.runAsync(() async {
          final writer = sandbox.createCheckpointStore();
          await writer.beginSession(checkpoint.bookId);
          expect((await writer.commit(checkpoint)).applied, isTrue);
          await writer.close();
        });
        final store = (await tester.runAsync(
          () async => sandbox.createCheckpointStore(),
        ))!;
        final coordinator = LazyCheckpointRecoveryCoordinator(
          store: store,
          bookId: checkpoint.bookId,
          publicationFingerprint: checkpoint.publicationFingerprint,
        );
        await tester.runAsync(coordinator.initialize);
        final reopened = await generate(tester, precedingA: false);
        final result = coordinator.prepare(
          authority: reopened.authority,
          session: reopened.session,
        );
        expect(result.kind, LazyRestoreKind.exactStableBody);
        expect(result.body!.canonicalEncoding, expanded.body.canonicalEncoding);
        expect(coordinator.current!.payloadJson(), checkpoint.payloadJson());
        LazyStableCardEmitter.admit(
          persisted: coordinator.current!.lazyStableBody!,
          authority: reopened.authority,
          session: reopened.session,
          regenerated: reopened.card,
        );
        final oldCoordinator = ReaderCheckpointCoordinator(
          store: store,
          bookId: checkpoint.bookId,
          publicationFingerprint: checkpoint.publicationFingerprint,
        );
        await tester.runAsync(oldCoordinator.initialize);
        expect(
          oldCoordinator.resolveRestore(
            cards: [reopened.card.identity],
            currentLayoutFingerprint: reopened.card.identity.layoutFingerprint,
          ),
          isNull,
        );
        final downgrade = await tester.runAsync(
          () => oldCoordinator.commitCard(
            card: reopened.card.identity,
            stableLocation: null,
            navigationSource: 'incorrect_old_path',
            duringRestore: true,
          ),
        );
        expect(downgrade!.applied, isFalse);
        expect(
          (await tester.runAsync(
            () => store.loadNewestValid(checkpoint.bookId),
          ))!.formatVersion,
          2,
        );
      } finally {
        await tester.runAsync(sandbox.close);
      }
    },
  );

  testWidgets(
    'R05 backward regeneration retains new stable body and signature',
    (tester) async {
      final run = await generate(tester, precedingA: false);
      final cards = run.session.acceptedPublishedCards;
      expect(cards.length, greaterThan(1));
      final current = cards.last;
      final before = LazyStableCardEmitter.emit(
        authority: run.authority,
        session: run.session,
        card: current,
      );
      final owner = run.session.sourceSnapshot.owners.first;
      final result = await run.session.generateBackward(
        desiredPredecessor: run.session.targetForStableOwner(
          sourceIdentity: owner.sourceIdentity,
          sectionIdentity: owner.sectionIdentity,
          sourceOrdinalHint: owner.sourceOrdinalHint,
          textOffsetUtf16: 0,
        ),
        acceptedPublishedPrefix: current,
        committedCurrentCard: current,
        acceptedSuccessorStartCursor: run.session
            .acceptedSuccessorStartCursorFor(current)!,
        operation: run.harness.canonicalOperationForP04(),
      );
      expect(result, isA<CanonicalReaderBackwardPreparationAccepted>());
      final regenerated = (result as CanonicalReaderBackwardPreparationAccepted)
          .regeneratedCommittedCard;
      expect(regenerated.card.toJson(), current.card.toJson());
      expect(regenerated.identity.signature, current.identity.signature);
      LazyStableCardEmitter.admit(
        persisted: before,
        authority: run.authority,
        session: run.session,
        regenerated: regenerated,
      );
    },
  );

  for (final change in [
    'insert',
    'remove',
    'reorder',
    'text',
    'parser',
    'dependency',
    'image',
    'structure',
  ]) {
    testWidgets('R06 production membership rejects $change', (tester) async {
      final run = await generate(tester, precedingA: true);
      final source = run.window.sections.first;
      final authority = LazyStableSectionAuthority.capture(run.index, source);
      final json =
          jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>;
      final chunks = json['chunks'] as List;
      switch (change) {
        case 'insert':
          chunks.add(chunks.last);
          break;
        case 'remove':
          chunks.removeLast();
          break;
        case 'reorder':
          final first = chunks[0];
          chunks[0] = chunks[1];
          chunks[1] = first;
          break;
        case 'text':
          (chunks[0] as Map)['tx'] = 'changed';
          break;
        case 'parser':
          (json['identity'] as Map)['parserVersion'] = 'changed';
          break;
        case 'dependency':
          (json['identity'] as Map)['dependencySignature'] = 'changed';
          break;
        case 'image':
          (chunks[0] as Map)['img'] = base64Encode([1, 2, 3]);
          break;
        case 'structure':
          (chunks[0] as Map)['br'] = BookBlockRole.paragraph.index;
          break;
      }
      expect(
        () => authority.validate(run.index, ParsedSection.fromJson(json)),
        throwsStateError,
      );
    });
  }

  for (final change in [
    'metrics',
    'renderer',
    'pagination',
    'fontDelivery',
    'structureRevision',
    'blocks',
    'slices',
    'payload',
  ]) {
    testWidgets('R07 lazy admission rejects re-signed $change mutation', (
      tester,
    ) async {
      final run = await generate(tester, precedingA: false);
      final json = run.body.toJson();
      if (change == 'slices') {
        ((json['slices'] as List).first as Map)['endUtf16'] = 999999;
      } else if (change == 'payload') {
        (json['payload'] as Map)['tx'] = 'changed';
      } else {
        (json['layout'] as Map)[change] = 'changed';
      }
      json.remove('digest');
      json['digest'] = readerSha256(json);
      expect(
        () => LazyStableCardEmitter.admit(
          persisted: LazyStableCardBody.fromJson(json),
          authority: run.authority,
          session: run.session,
          regenerated: run.card,
        ),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
    });
  }

  testWidgets('R08 strict old/new format discrimination and immutable bytes', (
    tester,
  ) async {
    final run = await generate(tester, precedingA: false);
    final json = run.card.card.toJson();
    expect(
      () => LazyStableCardBody.fromJson(Map<String, Object?>.from(json)),
      throwsFormatException,
    );
    final old = run.checkpoint.payloadJson();
    final relabeled = {...old, 'formatVersion': 2};
    expect(
      () => ReaderCheckpoint.fromPayload(
        relabeled,
        integrityChecksum: readerSha256(relabeled),
      ),
      throwsFormatException,
    );
    final newCheckpoint = ReaderCheckpoint.createLazy(
      bookId: run.index.bookId,
      body: run.body,
      sessionEpoch: 1,
      revision: 1,
      committedAtMillis: 1,
    );
    final wrongDomain = {...newCheckpoint.payloadJson(), 'formatVersion': 1};
    expect(
      () => ReaderCheckpoint.fromPayload(
        wrongDomain,
        integrityChecksum: readerSha256(wrongDomain),
      ),
      throwsFormatException,
    );
    final badBody = run.body.toJson()..['digest'] = 'bad';
    expect(() => LazyStableCardBody.fromJson(badBody), throwsFormatException);
    final copy = run.body.toJson();
    (copy['payload'] as Map)['i'] = 999;
    expect(run.body.toJson()['payload'] as Map, isNot(contains('i')));
    expect(run.card.card.toJson(), json);
  });

  testWidgets('R09 changed production layout rejects exact lazy admission', (
    tester,
  ) async {
    final standard = await generate(tester, precedingA: false);
    final changed = await generate(
      tester,
      precedingA: false,
      layoutKind: ReaderCorePaginationLayout.splitStress,
    );
    expect(
      changed.contract.identities.layoutMetricsFingerprint,
      isNot(standard.contract.identities.layoutMetricsFingerprint),
    );
    expect(
      () => LazyStableCardEmitter.admit(
        persisted: standard.body,
        authority: changed.authority,
        session: changed.session,
        regenerated: changed.card,
      ),
      throwsStateError,
    );
  });

  testWidgets(
    'R10 complete parsed A text, list and table slices survive codec and regeneration',
    (tester) async {
      final first = await generate(tester, precedingA: false, owningA: true);
      final second = await generate(tester, precedingA: false, owningA: true);
      final bodies = [
        for (final card in first.session.acceptedPublishedCards)
          LazyStableCardEmitter.emit(
            authority: first.authority,
            session: first.session,
            card: card,
          ),
      ];
      final reopened = [
        for (final card in second.session.acceptedPublishedCards)
          LazyStableCardEmitter.emit(
            authority: second.authority,
            session: second.session,
            card: card,
          ),
      ];
      expect(
        bodies.map((b) => b.canonicalEncoding),
        reopened.map((b) => b.canonicalEncoding),
      );
      final types = bodies
          .expand((b) => b.sourceSlices)
          .map((s) => s.toJson()['structuralType'])
          .toSet();
      expect(types, contains('table'));
      expect(
        first.window.chunks.any((chunk) => chunk.listSemantics != null),
        isTrue,
      );
      expect(
        bodies.any((body) {
          final payload = body.toJson()['payload'] as Map;
          return payload.containsKey('ls') || payload.containsKey('lf');
        }),
        isTrue,
      );
      for (final body in bodies) {
        expect(LazyStableCardBody.fromJson(body.toJson()), body);
      }
    },
  );

  testWidgets(
    'R11 missing current per-source font evidence rejects accepted lazy emission',
    (tester) async {
      final run = await generate(tester, precedingA: false);
      final before = run.body;
      run.invalidateFont();
      expect(
        () => LazyStableCardEmitter.admit(
          persisted: before,
          authority: run.authority,
          session: run.session,
          regenerated: run.card,
        ),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'R12 real parsed image atomic body and decoded metrics are window independent',
    (tester) async {
      final expanded = await generate(
        tester,
        precedingA: true,
        withImage: true,
      );
      final alone = await generate(tester, precedingA: false, withImage: true);
      LazyStableCardBody imageBody(_Run run) => LazyStableCardEmitter.emit(
        authority: run.authority,
        session: run.session,
        card: run.session.acceptedPublishedCards.singleWhere(
          (card) => card.card.type == BookChunkType.image,
        ),
      );
      final body = imageBody(expanded);
      expect(body.canonicalEncoding, imageBody(alone).canonicalEncoding);
      final slice = body.sourceSlices.single.toJson();
      expect(slice['structuralType'], 'image');
      expect(slice['startUtf16'], isNull);
      expect(slice['tableRowStart'], isNull);
      expect((body.toJson()['payload'] as Map)['img'], isNotEmpty);
      expect(LazyStableCardBody.fromJson(body.toJson()), body);
    },
  );

  for (final mode in [
    'exact',
    'migration',
    'stable_anchor',
    'missing_anchor',
    'unavailable',
    'cancel',
    'stale',
    'failed',
    'rollback',
  ]) {
    testWidgets(
      'L03 versioned legacy recovery $mode preserves journal until publication',
      (tester) async {
        final original = await generate(tester, precedingA: true, legacy: true);
        var saved = original.checkpoint;
        if (mode == 'stable_anchor' || mode == 'missing_anchor') {
          final payload = saved.payloadJson();
          (payload['semanticAnchor'] as Map)['logicalBlockId'] =
              'missing-semantic-owner';
          if (mode == 'missing_anchor') payload.remove('stableLocation');
          saved = ReaderCheckpoint.fromPayload(
            payload,
            integrityChecksum: readerSha256(payload),
          );
        }
        final migrates = mode == 'migration' || mode == 'stable_anchor';
        final sandbox = (await tester.runAsync(ReaderContractSandbox.create))!;
        try {
          await tester.runAsync(() async {
            final writer = sandbox.createCheckpointStore();
            await writer.beginSession(original.index.bookId);
            expect((await writer.commit(saved)).applied, isTrue);
            await writer.close();
          });
          final store = (await tester.runAsync(
            () async => sandbox.createCheckpointStore(),
          ))!;
          final coordinator = LazyCheckpointRecoveryCoordinator(
            store: store,
            bookId: original.index.bookId,
            publicationFingerprint: original.index.publicationFingerprint,
          );
          await tester.runAsync(coordinator.initialize);
          final reconstructed = await generate(
            tester,
            precedingA: mode == 'exact',
            legacy: mode == 'exact' || mode == 'unavailable',
          );
          final prepared = coordinator.prepare(
            authority: reconstructed.authority,
            session: reconstructed.session,
            authoritativeLegacyWindowDigest: mode == 'exact'
                ? original.session.sourceSnapshot.snapshotDigest
                : null,
          );
          expect(coordinator.current!.payloadJson(), saved.payloadJson());
          expect(coordinator.ordinaryWritesEnabled, isFalse);
          if (mode == 'exact') {
            expect(prepared.kind, LazyRestoreKind.legacyExactSignature);
            expect(
              prepared.legacyCard!.card.toJson(),
              original.card.card.toJson(),
            );
          } else if (mode == 'unavailable' || mode == 'missing_anchor') {
            expect(prepared.kind, LazyRestoreKind.exactUnavailable);
            expect(prepared.actions, [
              LazyRecoveryAction.retry,
              LazyRecoveryAction.back,
            ]);
            coordinator.abandon(LazyRecoveryAction.retry);
            coordinator.abandon(LazyRecoveryAction.back);
          } else {
            expect(prepared.kind, LazyRestoreKind.semanticMigrationV1);
            expect(prepared.reason, 'lazy_semantic_migration_v1');
            expect(prepared.presentation, 'Reader layout was rebuilt');
            if (mode == 'cancel') coordinator.abandon(LazyRecoveryAction.back);
            if (mode == 'stale') {
              await tester.runAsync(
                () => store.beginSession(original.index.bookId),
              );
            }
            var guardChecks = 0;
            if (mode == 'failed') {
              await tester.runAsync(() async {
                await expectLater(
                  coordinator.commitPublished(
                    preparation: prepared,
                    publishedBody: prepared.body!,
                    isCurrent: () {
                      if (++guardChecks == 4) {
                        throw StateError('publication failed');
                      }
                      return true;
                    },
                  ),
                  throwsStateError,
                );
              });
            } else {
              final committed = await tester.runAsync(
                () => coordinator.commitPublished(
                  preparation: prepared,
                  publishedBody: prepared.body!,
                  isCurrent: () => mode != 'rollback' || ++guardChecks < 4,
                ),
              );
              expect(committed, migrates);
            }
          }
          await tester.runAsync(() async {
            await store.close();
            final fresh = sandbox.createCheckpointStore();
            final durable = (await fresh.loadNewestValid(
              original.index.bookId,
            ))!;
            if (migrates) {
              expect(durable.formatVersion, 2);
              expect(durable.lazyMigration, 'lazy_semantic_migration_v1');
              expect(durable.lazyStableBody, prepared.body);
            } else {
              expect(durable.payloadJson(), saved.payloadJson());
            }
            await fresh.close();
            final audit = sqlite.sqlite3.open(
              sandbox.checkpointDatabaseFile.path,
              mode: sqlite.OpenMode.readOnly,
            );
            try {
              final rows = audit.select(
                'SELECT checkpoint_json FROM reader_checkpoint_journal ORDER BY record_id',
              );
              expect(rows.length, migrates ? 2 : 1);
              expect(
                rows.first['checkpoint_json'],
                canonicalJsonEncode(saved.payloadJson()),
              );
            } finally {
              audit.dispose();
            }
          });
        } finally {
          await tester.runAsync(sandbox.close);
        }
      },
    );
  }
}

final class _Run {
  const _Run(
    this.card,
    this.checkpoint,
    this.authority,
    this.contract,
    this.session,
    this.harness,
    this.index,
    this.window,
    this.invalidateFont,
  );
  final CanonicalFinalizedReaderCard card;
  final ReaderCheckpoint checkpoint;
  final LazyStableSectionAuthority authority;
  final ReaderLayoutContract contract;
  final CanonicalReaderPaginationSession session;
  final ReaderCorePaginationHarness harness;
  final LazyEpubIndex index;
  final LazyLoadedContentWindow window;
  final void Function() invalidateFont;
  LazyStableCardBody get body => LazyStableCardEmitter.emit(
    authority: authority,
    session: session,
    card: card,
  );
}
