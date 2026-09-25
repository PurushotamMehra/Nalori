import 'dart:convert';
import 'dart:typed_data';

import '../models/reader_font_evidence.dart';

import '../models/book_chunk.dart';
import '../models/canonical_pagination.dart';
import '../models/lazy_section_input.dart';
import '../models/lazy_stable_card.dart';
import '../models/reader_checkpoint.dart';
import '../models/reader_layout_contract.dart';
import '../utils/reader_content_parser.dart';
import 'lazy_stable_card_service.dart';
import 'reader_card_paginator.dart';
import 'reader_layout_contract_service.dart';

/// Runtime authorization is separate from all stable receipt/lineage digests.
typedef LazyPublicationOwner = ({
  int bookOpenEpoch,
  int displayOwner,
  int attempt,
});

final class LazyHandoffOperation {
  const LazyHandoffOperation({
    required this.owner,
    required this.currentOwner,
    required this.pagination,
  });
  final LazyPublicationOwner owner;
  final LazyPublicationOwner Function() currentOwner;
  final CanonicalPaginationOperationControls pagination;
  bool get isCurrent =>
      currentOwner() == owner &&
      !pagination.isCancelled() &&
      (pagination.currentGenerationToken == null ||
          pagination.currentGenerationToken!() == pagination.generationToken);
}

/// Tagged section end: never encoded as a logical-end pagination cursor.
final class SectionEndReceiptV1 {
  SectionEndReceiptV1._(Map<String, Object?> fields)
    : canonicalEncoding = canonicalJsonEncode(fields),
      receiptDigest = readerSha256(fields);
  final String canonicalEncoding;
  final String receiptDigest;
}

/// In-memory proposal. A digest alone is not an accepted transfer capability.
final class LazySnapshotHandoffV1 {
  LazySnapshotHandoffV1(Map<String, Object?> fields)
    : canonicalEncoding = canonicalJsonEncode(fields),
      handoffDigest = readerSha256(fields);
  final String canonicalEncoding;
  final String handoffDigest;
  Map<String, Object?> get fields =>
      Map<String, Object?>.from(jsonDecode(canonicalEncoding) as Map);
}

String lazyCanonicalCardGuard(CanonicalFinalizedReaderCard card) =>
    readerSha256([
      card.card.toJson(),
      card.identity.toJson(),
      card.sourceSlices.map((s) => s.toCanonicalJson()).toList(),
      card.resolvedLayout?.contractIdentity,
      card.resolvedLayout?.physicalLayoutCompositeFingerprint,
      card.resolvedLayout?.physicalCardIdentityComponents,
    ]);

/// Live authority for accepted section cards. Retained authority deliberately
/// has no paginator session, old snapshot, layout callbacks or preparation link.
abstract class LazySectionAuthority {
  LazySectionInput get input;
  CanonicalReaderPaginationSession? get session;
  List<CanonicalFinalizedReaderCard> get cards;
  List<LazyStableCardBody> get bodies;
  List<String> get cardGuards;
  SectionEndReceiptV1? get receipt;
  String get sessionDigest;
  LazyPublicationOwner get owner;
  ReaderLayoutContract get rendererContract;
  String get packingIdentity;
  CanonicalPaginationContinuation? get continuation;
  String? get retentionDigest => null;
  void validate();
}

final class LazyRetainedSection extends LazySectionAuthority {
  LazyRetainedSection._(
    this.input,
    this.cards,
    this.bodies,
    this.cardGuards,
    this.receipt,
    this.owner,
    this.rendererContract,
    this.packingIdentity,
    this.retentionDigest,
    this.sessionDigest,
  );
  factory LazyRetainedSection.capture(LazySectionAuthority old) {
    old.validate();
    final input = old.input.retainLastSection();
    final receipt = old.receipt;
    final retention = readerSha256([
      'LazySuffixRetentionV1',
      old.input.snapshot.snapshotDigest,
      input.snapshot.snapshotDigest,
      input.prefixDigest(input.snapshot.sourceCount),
      old.cardGuards,
      receipt?.receiptDigest,
      old.continuation?.integrityDigest,
      old.packingIdentity,
    ]);
    return LazyRetainedSection._(
      input,
      old.cards,
      old.bodies,
      old.cardGuards,
      receipt,
      old.owner,
      old.rendererContract,
      old.packingIdentity,
      retention,
      readerSha256(['LazyRetainedSessionRootV1', retention]),
    );
  }
  @override
  final LazySectionInput input;
  @override
  final List<CanonicalFinalizedReaderCard> cards;
  @override
  final List<LazyStableCardBody> bodies;
  @override
  final List<String> cardGuards;
  @override
  final SectionEndReceiptV1? receipt;
  @override
  final LazyPublicationOwner owner;
  @override
  final ReaderLayoutContract rendererContract;
  @override
  final String packingIdentity;
  @override
  final String retentionDigest;
  @override
  final String sessionDigest;
  @override
  CanonicalReaderPaginationSession? get session => null;
  @override
  CanonicalPaginationContinuation? get continuation => null;
  @override
  void validate() {
    final authority = input.sectionAuthorities.single;
    final projection = LazyStableResidentProjection(
      authority: authority,
      snapshot: input.snapshot,
    );
    if (packingIdentity !=
        LazyStableCardEmitter.packingIdentity(authority, rendererContract)) {
      throw StateError('Retained packing authority changed');
    }
    for (var i = 0; i < cards.length; i++) {
      if (lazyCanonicalCardGuard(cards[i]) != cardGuards[i] ||
          cards[i].identity.signature != bodies[i].identity.signature) {
        throw StateError('Retained card guard changed');
      }
      for (final slice in bodies[i].sourceSlices) {
        projection.projectSlice(slice);
      }
      ReaderLayoutRenderingAdapter.block(
        contract: rendererContract,
        card: cards[i].resolvedLayout!,
      );
    }
  }
}

/// Private section preparation consumes the sole production canonical session.
/// No split, packing, finalization or successful acceptance is synthesized here.
final class LazyPreparedSection extends LazySectionAuthority {
  LazyPreparedSection._(
    this.input,
    this.session,
    this.cards,
    this.bodies,
    this.cardGuards,
    this.receipt,
    this.sessionDigest,
    this.owner,
    this.workEntries,
  );
  @override
  final LazySectionInput input;
  @override
  final CanonicalReaderPaginationSession session;
  @override
  final List<CanonicalFinalizedReaderCard> cards;
  @override
  final List<LazyStableCardBody> bodies;
  @override
  final List<String> cardGuards;
  @override
  final SectionEndReceiptV1? receipt;
  @override
  final String sessionDigest;
  @override
  final LazyPublicationOwner owner;
  final int workEntries;
  @override
  CanonicalPaginationContinuation? get continuation => session.acceptedSuffix;
  @override
  ReaderLayoutContract get rendererContract => session.layout.contract!;
  @override
  String get packingIdentity => session.controlledLayoutIdentity;

  static Future<LazyPreparedSection> prepare({
    required LazySectionInput input,
    required ReaderCardPaginatorLayout layout,
    required LazyHandoffOperation operation,
    int maximumWork = CanonicalPaginationBounds.normalWorkEnvelope,
    int maximumCards = CanonicalPaginationBounds.activeCardCeiling,
    int maximumGuards =
        CanonicalPaginationBounds.residentContinuationRecordBasis,
    void Function(CanonicalReaderPaginationSession)? onProgress,
  }) async {
    if (!operation.isCurrent) {
      throw StateError('Cancelled or stale section preparation');
    }
    final contract = layout.contract;
    if (contract == null) throw StateError('Exact P05 contract required');
    final snapshot = input.snapshot;
    _validateSourceContract(contract, snapshot);
    final authority = input.sectionAuthorities.last;
    final packing = LazyStableCardEmitter.packingIdentity(authority, contract);
    final session = CanonicalReaderPaginationSession(
      sourceSnapshot: snapshot,
      controlledLayoutIdentity: packing,
      layout: layout,
      sectionInput: input,
    );
    if (maximumCards < 1 ||
        maximumGuards < 1 ||
        maximumWork < 1 ||
        maximumWork > CanonicalPaginationBounds.normalWorkEnvelope) {
      throw const LazyHandoffBoundExceeded('No aggregate preparation budget');
    }
    onProgress?.call(session);
    final root = snapshot.ownerAt(input.lastSectionStart);
    var result = await session.generateInitial(
      restart: CanonicalPaginationTrustedSectionStart(
        sectionIdentity: root.sectionIdentity,
        sourceIdentity: root.sourceIdentity,
        sourceOrdinalHint: root.sourceOrdinalHint,
      ),
      operation: operation.pagination,
      budget: CanonicalPaginationWorkBudget(
        maxFinalizedCards: maximumCards < 8 ? maximumCards : 8,
        maxAtomicFragments: maximumWork,
      ),
    );
    var work = 0;
    var steps = 0;
    while (true) {
      onProgress?.call(session);
      if (session.acceptedPublishedCards.length > maximumCards ||
          session.checkpointIndex.records.length > maximumGuards) {
        throw const LazyHandoffBoundExceeded(
          'Aggregate preparation budget exceeded',
        );
      }
      if (++steps > CanonicalPaginationBounds.residentContinuationRecordBasis) {
        throw const LazyHandoffBoundExceeded(
          'Section preparation exhausted checkpoint bound',
        );
      }
      if (!operation.isCurrent) {
        throw StateError('Cancelled or stale section preparation');
      }
      if (result is CanonicalReaderInputExhausted) {
        work += result.diagnostics.atomicFragmentsProcessed;
        break;
      }
      if (result is! CanonicalReaderPaginationPathAccepted) {
        throw StateError('Section pagination rejected: $result');
      }
      work += result.boundedWorkEntriesConsumed;
      if (result.continuation.terminal) break;
      if (work >= maximumWork) {
        throw const LazyHandoffBoundExceeded(
          'Section preparation needs more bounded evidence',
        );
      }
      final remainingCards =
          maximumCards - session.acceptedPublishedCards.length;
      if (remainingCards < 1 ||
          session.checkpointIndex.records.length >= maximumGuards) {
        throw const LazyHandoffBoundExceeded(
          'Aggregate preparation budget exhausted',
        );
      }
      result = await session.generateForward(
        acceptedPublishedSuffix: result.continuation.previousFinalizedBoundary,
        operation: operation.pagination,
        budget: CanonicalPaginationWorkBudget(
          maxFinalizedCards: remainingCards < 8 ? remainingCards : 8,
          maxAtomicFragments: maximumWork - work,
        ),
      );
    }
    if (work > maximumWork ||
        session.acceptedPublishedCards.length >
            CanonicalPaginationBounds.activeCardCeiling) {
      throw const LazyHandoffBoundExceeded(
        'Section preparation exceeded its bound',
      );
    }
    final cards = session.acceptedPublishedCards;
    validateCompleteSectionCoverage(input, cards);
    final bodies = List<LazyStableCardBody>.unmodifiable([
      for (final card in cards)
        LazyStableCardEmitter.emit(
          authority: authority,
          session: session,
          card: card,
        ),
    ]);
    final guards = List<String>.unmodifiable(cards.map(lazyCanonicalCardGuard));
    final last = cards.last;
    final position = sectionEndPosition(input, last.sourceSlices.last);
    final receipt = input.verifiedBookEnd
        ? null
        : SectionEndReceiptV1._({
            'kind': 'SectionEndReceiptV1',
            'bookId': snapshot.bookId,
            'publicationFingerprint': snapshot.publicationFingerprint,
            'spineAuthorityDigest': authority.publication,
            'snapshotDigest': snapshot.snapshotDigest,
            'sourceRevision': snapshot.sourceRevision,
            'parserSourceIdentity': snapshot.parserSourceIdentity,
            'sectionIdentity': jsonDecode(authority.sectionJson),
            'sectionSourceCount': authority.owners.length,
            'sectionSourceRecordsDigest': authority.recordsDigest,
            'completeSectionProofDigest': readerSha256(
              authority.membershipJson(),
            ),
            'lastConsumedOwner': snapshot.owners.last.toDigestJson(),
            'sectionEndPosition': position,
            'emptyFrontierDigest': readerSha256(
              const CanonicalPaginationFrontier().toCanonicalJson(),
            ),
            'lastAcceptedContinuationDigest':
                session.acceptedSuffix?.integrityDigest,
            'lastFinalizedCardSignature': last.identity.signature,
            'lastFinalizedCardBytesDigest': guards.last,
            'lastFinalizedSlicesDigest': readerSha256(
              last.sourceSlices.map((s) => s.toCanonicalJson()).toList(),
            ),
            'nextCandidateSpineIdentity': input.nextCandidate!.toJson(),
            'packingIdentity': packing,
            'sourceCompatibilityEvidenceDigest':
                contract.identities.sourceCompatibilityFingerprint,
          });
    if (input.verifiedBookEnd && session.acceptedSuffix?.terminal != true) {
      throw StateError('Final section lacks verified terminal authority');
    }
    final digest = readerSha256([
      'LazyCanonicalSessionV1',
      snapshot.snapshotDigest,
      packing,
      receipt?.receiptDigest,
      session.acceptedSuffix?.integrityDigest,
    ]);
    return LazyPreparedSection._(
      input,
      session,
      cards,
      bodies,
      guards,
      receipt,
      digest,
      operation.owner,
      work,
    );
  }

  @override
  void validate() {
    input.validateSnapshot(session.sourceSnapshot);
    _validateSourceContract(session.layout.contract!, input.snapshot);
    if (receipt != null && !session.inputExhaustedAwaitingSuccessor) {
      throw StateError('Section receipt lacks production exhaustion evidence');
    }
    validateCompleteSectionCoverage(input, cards);
    if (cards.length != bodies.length || cards.length != cardGuards.length) {
      throw StateError('Accepted card guard count changed');
    }
    for (var i = 0; i < cards.length; i++) {
      if (lazyCanonicalCardGuard(cards[i]) != cardGuards[i]) {
        throw StateError('Accepted card bytes or renderer evidence changed');
      }
      LazyStableCardEmitter.admit(
        persisted: bodies[i],
        authority: input.sectionAuthorities.last,
        session: session,
        regenerated: cards[i],
      );
    }
  }
}

Map<String, Object?> sectionEndPosition(
  LazySectionInput input,
  CanonicalPaginationSourceSlice last,
) => {
  'kind': 'sectionEnd',
  'owner': input.snapshot.owners.last.toDigestJson(),
  'coordinate': last.tableRowEndExclusive != null
      ? 'tableRow'
      : last.endUtf16 != null
      ? 'utf16'
      : 'atomic',
  'exclusiveEnd': last.tableRowEndExclusive ?? last.endUtf16 ?? 1,
};

/// Exact ordered coverage of the complete owning section, including intervals.
/// Missing, repeated or reordered sources cannot be certified as a sealed tail.
void validateCompleteSectionCoverage(
  LazySectionInput input,
  List<CanonicalFinalizedReaderCard> cards,
) {
  if (cards.isEmpty) throw StateError('No finalized section cards');
  final slices = cards.expand((c) => c.sourceSlices).toList();
  var index = 0;
  for (
    var ordinal = input.lastSectionStart;
    ordinal < input.snapshot.sourceCount;
    ordinal++
  ) {
    final source = input.snapshot.resolveOrdinalSource(ordinal);
    final owner = input.snapshot.ownerAt(ordinal);
    var offset = 0;
    var count = 0;
    final table = source.type == BookChunkType.text
        ? normalizedReaderTableFromText(source.text ?? '')
        : null;
    final extent =
        table?.rows.length ??
        (source.type == BookChunkType.text ? (source.text?.length ?? 0) : 1);
    while (index < slices.length &&
        slices[index].sourceOrdinalHint == ordinal) {
      final slice = slices[index++];
      if (slice.sourceIdentity != owner.sourceIdentity ||
          slice.sectionIdentity != owner.sectionIdentity ||
          slice.spineIdentity != owner.spineIdentity ||
          slice.sourceDigest != owner.sourceDigest) {
        throw StateError('Slice source ownership changed');
      }
      final start = slice.tableRowStart ?? slice.startUtf16 ?? 0;
      final end = slice.tableRowEndExclusive ?? slice.endUtf16 ?? 1;
      if (start != offset || end < start || end > extent) {
        throw StateError('Section interval gap or overlap');
      }
      offset = end;
      count++;
    }
    if (offset != extent || count == 0) {
      throw StateError('Incomplete section source coverage');
    }
  }
  if (index != slices.length) {
    throw StateError('Duplicated or reordered section coverage');
  }
}

/// Retained cards keep their original strict renderer contract. The successor
/// supplies separate exact prefix/source membership and stable packing proof.
abstract final class LazyHandoffRenderingAdapter {
  static ResolvedReaderBlockLayout block({
    required LazySectionAuthority retained,
    required int cardIndex,
    required LazyPreparedSection successor,
  }) {
    successor.input.validateExtensionOf(retained.input);
    if (retained.packingIdentity !=
        successor.session.controlledLayoutIdentity) {
      throw StateError(
        'Lazy metric/renderer/font/pagination authority changed',
      );
    }
    retained.validate();
    final projection = LazyStableResidentProjection(
      authority: retained.input.sectionAuthorities.single,
      snapshot: successor.input.snapshot,
    );
    for (final slice in retained.bodies[cardIndex].sourceSlices) {
      projection.projectSlice(slice);
    }
    return ReaderLayoutRenderingAdapter.block(
      contract: retained.rendererContract,
      card: retained.cards[cardIndex].resolvedLayout!,
    );
  }
}

final class LazyAcceptedPublication {
  LazyAcceptedPublication.initial(this.current, this.owner)
    : sourceInput = current.input,
      predecessor = null,
      lineageRootDigest = current.sessionDigest,
      previousHandoffDigest = null,
      handoffOrdinal = 0,
      revision = 0,
      handoff = null,
      cards = current.cards,
      bodies = current.bodies,
      sessionDigest = current.sessionDigest;
  LazyAcceptedPublication.transferred(
    LazyAcceptedPublication old,
    this.current,
    this.handoff,
    this.sessionDigest,
  ) : sourceInput = current.input,
      predecessor = old.current,
      lineageRootDigest = old.lineageRootDigest,
      previousHandoffDigest = handoff!.handoffDigest,
      handoffOrdinal = old.handoffOrdinal + 1,
      owner = old.owner,
      revision = old.revision + 1,
      cards = List.unmodifiable([...old.cards, ...current.cards]),
      bodies = List.unmodifiable([...old.bodies, ...current.bodies]);
  LazyAcceptedPublication.retained(
    LazyAcceptedPublication old,
    LazyRetainedSection retained,
  ) : sourceInput = retained.input,
      predecessor = null,
      current = retained,
      owner = old.owner,
      revision = old.revision + 1,
      handoff = null,
      lineageRootDigest = old.lineageRootDigest,
      previousHandoffDigest = old.previousHandoffDigest,
      handoffOrdinal = old.handoffOrdinal,
      cards = retained.cards,
      bodies = retained.bodies,
      sessionDigest = retained.sessionDigest;
  LazyAcceptedPublication.prepended(
    LazyAcceptedPublication old,
    LazyPreparedSection reconstructed,
    this.sourceInput,
    this.handoff,
  ) : predecessor = reconstructed,
      current = old.current,
      owner = old.owner,
      revision = old.revision + 1,
      lineageRootDigest = old.lineageRootDigest,
      previousHandoffDigest = handoff!.handoffDigest,
      handoffOrdinal = old.handoffOrdinal + 1,
      cards = List.unmodifiable([...reconstructed.cards, ...old.cards]),
      bodies = List.unmodifiable([...reconstructed.bodies, ...old.bodies]),
      sessionDigest = readerSha256([
        'LazyPrependSessionV1',
        old.sessionDigest,
        handoff.handoffDigest,
      ]);
  final LazySectionInput sourceInput;
  final String lineageRootDigest;
  final String? previousHandoffDigest;
  final int handoffOrdinal;
  final LazySectionAuthority? predecessor;
  final LazySectionAuthority current;
  final LazyPublicationOwner owner;
  final int revision;
  final LazySnapshotHandoffV1? handoff;
  final List<CanonicalFinalizedReaderCard> cards;
  final List<LazyStableCardBody> bodies;
  final String sessionDigest;
  String get digest => readerSha256([
    'LazyAcceptedPublicationV1',
    revision,
    sessionDigest,
    cards.map(lazyCanonicalCardGuard).toList(),
    bodies.map((b) => b.canonicalEncoding).toList(),
  ]);
}

LazySnapshotHandoffV1 buildLazySnapshotHandoff({
  required LazyAcceptedPublication old,
  required LazyPreparedSection successor,
  String? committedCardSignature,
}) {
  if (old.current.input.sectionCount != 1 ||
      old.current.receipt == null ||
      old.predecessor != null) {
    throw StateError('Retained single-section receipt required');
  }
  successor.input.validateExtensionOf(old.current.input);
  old.current.validate();
  successor.validate();
  final committed =
      committedCardSignature ?? old.cards.first.identity.signature;
  if (!old.cards.any((c) => c.identity.signature == committed)) {
    throw StateError('Visible card absent from retained publication');
  }
  final a = old.current;
  final b = successor;
  final oldSnapshot = a.input.snapshot;
  final snapshot = b.input.snapshot;
  final contract = b.session.layout.contract!;
  if (a.packingIdentity != b.session.controlledLayoutIdentity) {
    throw StateError('Packing compatibility changed');
  }
  final nextOwner = snapshot.ownerAt(oldSnapshot.sourceCount);
  final nextCursor = CanonicalPaginationCursor(
    kind: CanonicalPaginationCursorKind.wholeSource,
    sourceIdentity: nextOwner.sourceIdentity,
    sectionIdentity: nextOwner.sectionIdentity,
    sourceOrdinalHint: nextOwner.sourceOrdinalHint,
  );
  final rootDigest = old.lineageRootDigest;
  final successorDigest = readerSha256([
    'LazySuccessorSessionV1',
    rootDigest,
    old.sessionDigest,
    old.previousHandoffDigest,
    old.handoffOrdinal + 1,
    snapshot.snapshotDigest,
    b.session.controlledLayoutIdentity,
    a.receipt!.receiptDigest,
    nextOwner.toDigestJson(),
  ]);
  final last = a.cards.last;
  return LazySnapshotHandoffV1({
    'kind': 'LazySnapshotHandoffV1',
    'bookId': snapshot.bookId,
    'publicationFingerprint': snapshot.publicationFingerprint,
    'spineAuthorityDigest': b.input.sectionAuthorities.last.publication,
    'parserSourceIdentity': snapshot.parserSourceIdentity,
    'dependencyIdentity': b.input.publication.dependencyIdentity,
    'lineageRootDigest': rootDigest,
    'parentSessionDigest': old.sessionDigest,
    'successorSessionDigest': successorDigest,
    'previousHandoffDigest': old.previousHandoffDigest,
    'handoffOrdinal': old.handoffOrdinal + 1,
    'retentionProofDigest': a.retentionDigest,
    'oldSnapshotDigest': oldSnapshot.snapshotDigest,
    'oldSourceRevision': oldSnapshot.sourceRevision,
    'newSnapshotDigest': snapshot.snapshotDigest,
    'newSourceRevision': snapshot.sourceRevision,
    'prefixSourceCount': oldSnapshot.sourceCount,
    'prefixOwnersAndRecordsDigest': b.input.prefixDigest(
      oldSnapshot.sourceCount,
    ),
    'addedSectionIdentity': jsonDecode(
      b.input.sectionAuthorities.last.sectionJson,
    ),
    'addedSectionRecordsDigest': b.input.sectionAuthorities.last.recordsDigest,
    'sectionEndReceiptDigest': a.receipt!.receiptDigest,
    'acceptedPublicationDigest': old.digest,
    'acceptedCardCount': old.cards.length,
    'committedCardSignature': committed,
    'lastAcceptedCardSignature': last.identity.signature,
    'lastAcceptedCardBytesDigest': a.cardGuards.last,
    'lastAcceptedSlicesDigest': readerSha256(
      last.sourceSlices.map((s) => s.toCanonicalJson()).toList(),
    ),
    'oldSectionEndPosition': sectionEndPosition(
      a.input,
      last.sourceSlices.last,
    ),
    'nextExpectedSourceOwner': nextOwner.toDigestJson(),
    'nextExpectedCursor': nextCursor.toCanonicalJson(),
    'trustedSectionStartProofDigest': readerSha256([
      snapshot.snapshotDigest,
      nextCursor.toCanonicalJson(),
    ]),
    'emptySectionChainDigest': null,
    'firstNewCardSignature': b.cards.first.identity.signature,
    'firstNewCardStartCursor': nextCursor.toCanonicalJson(),
    'packingIdentity': b.session.controlledLayoutIdentity,
    'layoutMetricsFingerprint': contract.identities.layoutMetricsFingerprint,
    'rendererLayoutFingerprint': contract.identities.rendererLayoutFingerprint,
    'paginationAlgorithmFingerprint':
        contract.identities.paginationAlgorithmFingerprint,
    'paginationAlgorithmIdentity': readerPaginationAlgorithmVersion,
    'compatibilityClassifierRevision': readerCompatibilityClassifierRevision,
    'fontDeliveryDigest': contract.fontDeliveryEvidence.digest,
    'oldSourceCompatibilityFingerprint':
        a.rendererContract.identities.sourceCompatibilityFingerprint,
    'newSourceCompatibilityFingerprint':
        contract.identities.sourceCompatibilityFingerprint,
    'sourceExtensionProofDigest': readerSha256([
      b.input.prefixDigest(oldSnapshot.sourceCount),
      b.input.sectionAuthorities.last.membershipJson(),
    ]),
  });
}

final class LazyHandoffBoundExceeded implements Exception {
  const LazyHandoffBoundExceeded(this.message);
  final String message;
  @override
  String toString() => message;
}

/// This failure never authorizes a semantic substitute for an exact card.
final class LazyExactReconstructionUnavailable implements Exception {
  const LazyExactReconstructionUnavailable(this.message);
  final String message;
  @override
  String toString() => 'Exact reconstruction unavailable: $message';
}

LazySnapshotHandoffV1 buildLazySnapshotPrepend({
  required LazyAcceptedPublication old,
  required LazyPreparedSection predecessor,
  required LazyPreparedSection reconstructedCurrent,
  required LazySectionInput window,
  required String committedCardSignature,
}) {
  if (old.predecessor != null ||
      old.current.input.sectionCount != 1 ||
      predecessor.input.sectionCount != 1 ||
      predecessor.receipt == null ||
      predecessor.input.nextCandidate?.stableKey !=
          old.current.input.sectionAuthorities.single.sectionKey ||
      predecessor.packingIdentity != old.current.packingIdentity ||
      reconstructedCurrent.packingIdentity != old.current.packingIdentity) {
    throw const LazyExactReconstructionUnavailable(
      'Predecessor, seam or packing authority differs',
    );
  }
  old.current.validate();
  predecessor.validate();
  reconstructedCurrent.validate();
  window.validateExtensionOf(predecessor.input);
  final suffix = old.current.input;
  if (window.sourceRecords.length !=
          predecessor.input.snapshot.sourceCount +
              suffix.sourceRecords.length ||
      window.encodedSections.last != suffix.encodedSections.single ||
      !List.generate(
        suffix.sourceRecords.length,
        (i) => identical(
          window.sourceRecords[predecessor.input.snapshot.sourceCount + i],
          suffix.sourceRecords[i],
        ),
      ).every((same) => same)) {
    throw const LazyExactReconstructionUnavailable(
      'Retained suffix authority differs',
    );
  }
  if (reconstructedCurrent.input.snapshot.snapshotDigest !=
          old.current.input.snapshot.snapshotDigest ||
      canonicalJsonEncode(
            old.bodies.map((b) => b.canonicalEncoding).toList(),
          ) !=
          canonicalJsonEncode(
            reconstructedCurrent.bodies
                .map((b) => b.canonicalEncoding)
                .toList(),
          ) ||
      !old.cards.any((c) => c.identity.signature == committedCardSignature)) {
    throw const LazyExactReconstructionUnavailable(
      'Exact current card or source reconstruction differs',
    );
  }
  // Stable-body equality includes all payload, stable slices and resolved block
  // metrics. Runtime ordinals and snapshot-specific P05 identities are separate.
  final first = old.current.bodies.first.sourceSlices.first;
  final projection = LazyStableResidentProjection(
    authority: old.current.input.sectionAuthorities.single,
    snapshot: window.snapshot,
  );
  final next = projection.projectSlice(first);
  if (next.sourceOrdinalHint != predecessor.input.snapshot.sourceCount ||
      (next.startUtf16 ?? next.tableRowStart ?? 0) != 0) {
    throw const LazyExactReconstructionUnavailable(
      'Successor cursor does not meet the hard seam',
    );
  }
  return LazySnapshotHandoffV1({
    'kind': 'LazySnapshotPrependV1',
    'acceptedPublicationDigest': old.digest,
    'parentSessionDigest': old.sessionDigest,
    'previousHandoffDigest': old.previousHandoffDigest,
    'handoffOrdinal': old.handoffOrdinal + 1,
    'committedCardSignature': committedCardSignature,
    'predecessorRoot': predecessor.sessionDigest,
    'predecessorReceipt': predecessor.receipt!.receiptDigest,
    'predecessorBodies': readerSha256(
      predecessor.bodies.map((b) => b.canonicalEncoding).toList(),
    ),
    'currentBodies': readerSha256(
      reconstructedCurrent.bodies.map((b) => b.canonicalEncoding).toList(),
    ),
    'window': window.snapshot.snapshotDigest,
    'packing': predecessor.packingIdentity,
    'predecessorEnd': sectionEndPosition(
      predecessor.input,
      predecessor.cards.last.sourceSlices.last,
    ),
    'successorCursor': next.toCanonicalJson(),
  });
}

enum LazySnapshotPublicationOutcome {
  accepted,
  prepared,
  stale,
  cancelled,
  replayed,
  invalid,
  failedAttempt,
  retentionRequired,
  boundExceeded,
  exactUnavailable,
  busy,
}

final class LazySnapshotPublicationResult {
  const LazySnapshotPublicationResult(this.outcome, [this.message]);
  final LazySnapshotPublicationOutcome outcome;
  final String? message;
  bool get accepted => outcome == LazySnapshotPublicationOutcome.accepted;
}

// Read only the existing F202 source tuple. This neither changes its encoding
// nor claims equality across windows; each renderer contract must bind its own
// snapshot. Per-source fonts/images/structure are rechecked by stable admission.
void _validateSourceContract(
  ReaderLayoutContract contract,
  CanonicalPaginationSourceSnapshot snapshot,
) {
  final identity = contract.identities.sourceCompatibilityIdentity;
  final bytes = identity.canonicalBytes;
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  int number() {
    final n = data.getUint64(offset);
    offset += 8;
    return n;
  }

  String string() {
    final length = number();
    final value = utf8.decode(bytes.sublist(offset, offset + length));
    offset += length;
    return value;
  }

  if (string() != 'reader-source-compatibility' ||
      number() != 1 ||
      data.getUint32(offset) != 1 ||
      data.getUint8(offset + 4) != 5) {
    throw StateError('Invalid source compatibility encoding');
  }
  offset += 5;
  final payloadLength = number();
  final payloadStart = offset;
  if (number() != 6) throw StateError('Invalid source compatibility tuple');
  final values = [for (var i = 0; i < 6; i++) string()];
  if (offset != bytes.length ||
      offset - payloadStart != payloadLength ||
      identity.fingerprint != ReaderFontCanonicalEncoder.digest(bytes) ||
      contract.identities.sourceCompatibilityFingerprint !=
          identity.fingerprint ||
      canonicalJsonEncode(values.take(5).toList()) !=
          canonicalJsonEncode([
            snapshot.publicationFingerprint,
            snapshot.parserSourceIdentity,
            snapshot.sourceRevision,
            snapshot.snapshotDigest,
            readerStructuralOwnershipRevision,
          ]) ||
      values.last.isEmpty) {
    throw StateError(
      'Renderer source contract does not bind the exact snapshot',
    );
  }
}
