import 'dart:io';

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

// Entry precondition, not a handoff implementation. Use the selected stable
// packing tuple as the existing paginator's controlled identity, with each
// window's unmodified P05 contract. No card/slice/layout field is normalized.
void main() {
  late ReaderCoreParsedFixture fixture;
  var sequence = 0;
  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('lazy-reopen-payload-');
  });
  tearDownAll(() => fixture.close());

  Future<_Run> generate(
    WidgetTester tester, {
    required bool precedingA,
    bool legacy = false,
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
        index = await lazy.open(fixture.epubFile);
        final item = index.spine.lastWhere((item) => item.isLinear);
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
      } finally {
        await lazy.close();
      }
    });
    expect(window.sections.length, precedingA ? 2 : 1);
    final harness = await ReaderCorePaginationHarness.install(
      tester: tester,
      sourceChunks: window.chunks,
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
      fontEvidenceResolver: baseLayout.fontEvidenceResolver,
      imageEvidenceResolver: baseLayout.imageEvidenceResolver,
    );
    final spineDigest = readerSha256([
      'PublicationSpineAuthorityV1',
      index.bookId,
      index.publicationFingerprint,
      index.schemaVersion,
      lazyParsedSectionParserVersion,
      lazySectionDependencySignature(index),
      for (final item in index.spine)
        [
          item.index,
          item.idRef,
          item.normalizedHref,
          item.fullPath,
          item.isLinear,
          item.sourceChecksum,
        ],
    ]);
    final packing = readerSha256([
      'LazyPackingIdentityV1',
      index.publicationFingerprint,
      spineDigest,
      lazyParsedSectionParserVersion,
      lazySectionDependencySignature(index),
      readerStructuralOwnershipRevision,
      contract.identities.layoutMetricsFingerprint,
      contract.identities.rendererLayoutFingerprint,
      contract.identities.paginationAlgorithmFingerprint,
      readerCompatibilityClassifierRevision,
      contract.fontDeliveryEvidence.digest,
    ]);
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
    // ignore: avoid_print
    print(
      'REOPEN precedingA=$precedingA sources=${snapshot.sourceCount} '
      'cards=${session.acceptedPublishedCards.length} '
      'guards=${session.checkpointIndex.records.length} '
      'work=${accepted.boundedWorkEntriesConsumed} '
      'entered=${accepted.diagnostics.sourceChunksEntered} '
      'hint=${card.sourceSlices.first.sourceOrdinalHint} '
      'signature=${card.identity.signature} '
      'payload=${readerSha256(card.card.toJson())} '
      'checkpoint=${checkpoint.integrityChecksum}',
    );
    return _Run(card, decoded, packing, contract);
  }

  testWidgets(
    'R01 CONTROL stable packing and checkpoint do not encode window-dependent payload',
    (tester) async {
      final expanded = await generate(tester, precedingA: true);
      final owning = await generate(tester, precedingA: false);
      final reopened = await generate(tester, precedingA: false);
      expect(expanded.packing, owning.packing);
      expect(owning.packing, reopened.packing);
      expect(expanded.card.identity.signature, owning.card.identity.signature);
      expect(
        expanded.checkpoint.payloadJson(),
        owning.checkpoint.payloadJson(),
      );
      expect(
        expanded.checkpoint.integrityChecksum,
        owning.checkpoint.integrityChecksum,
      );
      expect(
        expanded.card.sourceSlices.first.sourceIdentity,
        owning.card.sourceSlices.first.sourceIdentity,
      );
      expect(
        expanded.card.sourceSlices.first.sourceDigest,
        owning.card.sourceSlices.first.sourceDigest,
      );
      expect(
        expanded.card.resolvedLayout!.blocks.single.blockLayoutFingerprint,
        owning.card.resolvedLayout!.blocks.single.blockLayoutFingerprint,
      );
      expect(
        expanded.card.sourceSlices.first.sourceOrdinalHint,
        isNot(owning.card.sourceSlices.first.sourceOrdinalHint),
      );
      expect(expanded.card.card.toJson(), isNot(owning.card.card.toJson()));
      expect(expanded.card.resolvedLayout, isNot(owning.card.resolvedLayout));
      // Fresh owning-section reconstruction is deterministic for its own history.
      expect(owning.card.identity.toJson(), reopened.card.identity.toJson());
      expect(owning.card.card.toJson(), reopened.card.card.toJson());
      expect(_slices(owning.card), _slices(reopened.card));
      expect(owning.card.resolvedLayout, reopened.card.resolvedLayout);
      // Ordinary P05 evidence still distinguishes these source-bound contracts.
      expect(
        expanded.contract.identities.sourceCompatibilityFingerprint,
        isNot(owning.contract.identities.sourceCompatibilityFingerprint),
      );
    },
  );

  testWidgets(
    'R02 RED bounded owning-section reopen must reproduce historical exact payload and slices',
    (tester) async {
      final expanded = await generate(tester, precedingA: true);
      final reopened = await generate(tester, precedingA: false);
      expect(
        reopened.card.identity.signature,
        expanded.card.identity.signature,
      );
      expect(
        reopened.checkpoint.integrityChecksum,
        expanded.checkpoint.integrityChecksum,
      );
      expect(
        {
          'payload': reopened.card.card.toJson(),
          'slices': _slices(reopened.card),
          'layoutContract': reopened.card.resolvedLayout!.contractIdentity,
          'physicalComponents':
              reopened.card.resolvedLayout!.physicalCardIdentityComponents,
        },
        {
          'payload': expanded.card.card.toJson(),
          'slices': _slices(expanded.card),
          'layoutContract': expanded.card.resolvedLayout!.contractIdentity,
          'physicalComponents':
              expanded.card.resolvedLayout!.physicalCardIdentityComponents,
        },
        reason:
            'Equal stable packing/signature/checkpoint cannot choose between '
            'different historical card bytes, slice hints and P05 layout payloads. '
            'No normalization, re-signing or checkpoint mutation is permitted.',
      );
    },
  );
  for (final exactWindow in [true, false]) {
    testWidgets(
      exactWindow
          ? 'L01 CONTROL legacy checkpoint persists and exact bounded original window reconstructs'
          : 'L02 RED changed window alone must not authorize legacy semantic restoration',
      (tester) async {
        final original = await generate(tester, precedingA: true, legacy: true);
        final sandbox = (await tester.runAsync(ReaderContractSandbox.create))!;
        try {
          final writer = (await tester.runAsync(
            () async => sandbox.createCheckpointStore(),
          ))!;
          await tester.runAsync(() async {
            expect(await writer.beginSession(original.checkpoint.bookId), 1);
            expect((await writer.commit(original.checkpoint)).applied, isTrue);
            await writer.close();
          });
          final reopenedStore = (await tester.runAsync(
            () async => sandbox.createCheckpointStore(),
          ))!;
          final coordinator = ReaderCheckpointCoordinator(
            store: reopenedStore,
            bookId: original.checkpoint.bookId,
            publicationFingerprint: original.checkpoint.publicationFingerprint,
          );
          await tester.runAsync(() => coordinator.initialize());
          expect(
            coordinator.current!.payloadJson(),
            original.checkpoint.payloadJson(),
          );
          // Regenerate only after the durable store was closed and reopened.
          final reconstructed = await generate(
            tester,
            precedingA: exactWindow,
            legacy: true,
          );
          expect(
            original.contract.identities.layoutMetricsFingerprint,
            reconstructed.contract.identities.layoutMetricsFingerprint,
          );
          final resolution = coordinator.resolveRestore(
            cards: [reconstructed.card.identity],
            currentLayoutFingerprint: reconstructed.contract.identity,
          );
          expect(
            coordinator.current!.payloadJson(),
            original.checkpoint.payloadJson(),
          );
          expect(coordinator.ordinaryWritesEnabled, isFalse);
          if (exactWindow) {
            expect(
              resolution!.strategy,
              ReaderRestoreMatchStrategy.exactSignature,
            );
            expect(
              reconstructed.card.card.toJson(),
              original.card.card.toJson(),
            );
            expect(_slices(reconstructed.card), _slices(original.card));
            expect(
              reconstructed.card.resolvedLayout,
              original.card.resolvedLayout,
            );
          } else {
            expect(
              reconstructed.card.identity.signature,
              isNot(original.card.identity.signature),
            );
            // The existing exact-missing branch itself fails closed.
            expect(
              coordinator.resolveRestore(
                cards: [reconstructed.card.identity],
                currentLayoutFingerprint: original.contract.identity,
              ),
              isNull,
            );
            // ignore: avoid_print
            print(
              'LEGACY changedWindow strategy=${resolution?.strategy.name} reason=${resolution?.fallbackReason} checkpointPreserved=true',
            );
            expect(
              resolution,
              isNull,
              reason:
                  'Window-only F202/F208 change is not genuine reflow; preserve legacy checkpoint and require explicit exact-unavailable.',
            );
          }
        } finally {
          await tester.runAsync(sandbox.close);
        }
      },
    );
  }
}

List<Map<String, Object?>> _slices(CanonicalFinalizedReaderCard card) => [
  for (final slice in card.sourceSlices) slice.toCanonicalJson(),
];

final class _Run {
  const _Run(this.card, this.checkpoint, this.packing, this.contract);
  final CanonicalFinalizedReaderCard card;
  final ReaderCheckpoint checkpoint;
  final String packing;
  final ReaderLayoutContract contract;
}
