// ignore_for_file: avoid_redundant_argument_values, prefer_const_constructors, prefer_const_declarations

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_font_evidence.dart';
import 'package:nalori/models/reader_layout_contract.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/reader_font_evidence_gate.dart';
import 'package:nalori/services/reader_layout_contract_service.dart';

// Entry proof only: never installs a different production layout identity.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gate = ReaderFontEvidenceGate();
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

    return value;
  }

  test(
    'K01 CONTROL real P05 split preserves metrics and block evidence across windows/reload',
    () async {
      final a = await buildContract(sourceSnapshot: 'A');
      final ab = await buildContract(
        sourceSnapshot: 'A+B',
        source: 'Different representative probe',
      );
      final reload = await buildContract(sourceSnapshot: 'A');
      expect(
        a.identities.layoutMetricsFingerprint,
        ab.identities.layoutMetricsFingerprint,
      );
      expect(
        a.identities.rendererLayoutFingerprint,
        ab.identities.rendererLayoutFingerprint,
      );
      expect(
        a.identities.paginationAlgorithmFingerprint,
        ab.identities.paginationAlgorithmFingerprint,
      );
      expect(a.fontDeliveryEvidence.digest, ab.fontDeliveryEvidence.digest);
      expect(
        a.identities.sourceCompatibilityFingerprint,
        isNot(ab.identities.sourceCompatibilityFingerprint),
      );
      expect(a.identity, isNot(ab.identity));
      // Candidate tuple only, never substituted for F202/F208 in production.
      String candidate(ReaderLayoutContract contract) => readerSha256([
        'LazyPackingIdentityV1',
        'publication-v1',
        'pinned-spine',
        'parser-v1',
        'pinned-dependency',
        'pinned-structural-ownership',
        contract.identities.layoutMetricsFingerprint,
        contract.identities.rendererLayoutFingerprint,
        contract.identities.paginationAlgorithmFingerprint,
        readerCompatibilityClassifierRevision,
        contract.fontDeliveryEvidence.digest,
      ]);
      expect(candidate(a), candidate(ab));
      expect(candidate(a), candidate(reload));
      const chunk = BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: 'Retained source.',
      );
      final oldBlock = resolve(a, chunk);
      expect(
        resolve(ab, chunk).blockLayoutFingerprint,
        oldBlock.blockLayoutFingerprint,
      );
      expect(card(reload, resolve(reload, chunk)), card(a, oldBlock));
      expect(
        card(ab, resolve(ab, chunk)).physicalCardIdentityComponents,
        isNot(card(a, oldBlock).physicalCardIdentityComponents),
      );
      expect(
        () => ReaderBlockLayoutResolver.resolve(
          contract: ab,
          chunk: chunk,
          stableBlockOwner: canonicalBookChunkOwnershipDigest(chunk),
          sourceStructureDigestLink: canonicalBookChunkOwnershipDigest(chunk),
          fontEvidence: const [],
        ),
        throwsStateError,
      );
    },
  );

  test(
    'K02 RED unchanged retained card must render under successor without rewriting or bypass',
    () async {
      final a = await buildContract(sourceSnapshot: 'A');
      final ab = await buildContract(sourceSnapshot: 'A+B');
      const chunk = BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: 'Retained source.',
      );
      final retained = card(a, resolve(a, chunk));
      expect(
        () => ReaderLayoutRenderingAdapter.block(contract: ab, card: retained),
        returnsNormally,
        reason:
            'LazyPackingIdentityV1 alone cannot authorize an old P05 resolved card under the successor contract.',
      );
    },
  );
}
