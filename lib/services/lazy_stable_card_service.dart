import 'lazy_validation_work.dart';
import 'dart:convert';

import '../models/canonical_pagination.dart';
import '../models/lazy_stable_card.dart';
import '../models/reader_checkpoint.dart';
import '../models/reader_layout_contract.dart';
import 'lazy_epub_index_service.dart';
import 'lazy_parsed_book.dart';
import 'reader_card_paginator.dart';
import 'reader_layout_contract_service.dart';

/// Captured only from a complete parsed section and pinned publication index.
/// No historical flat ordinal discovery or preceding-section parsing occurs.
final class LazyStableSectionAuthority {
  LazyStableSectionAuthority._(
    this.publication,
    this.sectionJson,
    this.sectionKey,
    this.owners,
    this.recordsDigest,
  );

  factory LazyStableSectionAuthority.capture(
    LazyEpubIndex index,
    ParsedSection section,
  ) {
    final position = section.identity.spineIndex;
    if (position < 0 ||
        position >= index.spine.length ||
        section.chunks.length > CanonicalPaginationBounds.activeSourceCeiling ||
        utf8.encode(canonicalJsonEncode(section.toJson())).length >
            LazyStableCardBody.maxEncodedBytes) {
      throw StateError(
        'Complete section evidence exceeds bounds or is unavailable',
      );
    }
    final expected = LazySectionIdentity.fromIndexItem(
      bookId: index.bookId,
      publicationFingerprint: index.publicationFingerprint,
      item: index.spine[position],
      sourceChecksum: index.spine[position].sourceChecksum,
      dependencySignature: lazySectionDependencySignature(index),
    );
    if (canonicalJsonEncode(expected.toJson()) !=
            canonicalJsonEncode(section.identity.toJson()) ||
        section.parserVersion != expected.parserVersion) {
      throw StateError(
        'Section does not belong to pinned publication authority',
      );
    }
    for (var local = 0; local < section.chunks.length; local++) {
      if (section.chunks[local].index != local) {
        throw StateError('Section-local source order is invalid');
      }
    }
    return LazyStableSectionAuthority._(
      readerSha256([
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
      ]),
      canonicalJsonEncode(expected.toJson()),
      expected.stableKey,
      List.unmodifiable(section.chunks.map(canonicalBookChunkOwnershipDigest)),
      readerSha256(section.toJson()),
    );
  }

  static Future<LazyStableSectionAuthority> captureYielding(
    LazyEpubIndex index,
    ParsedSection section,
    LazyValidationWork work,
  ) async {
    final position = section.identity.spineIndex;
    if (position < 0 ||
        position >= index.spine.length ||
        section.chunks.length > CanonicalPaginationBounds.activeSourceCeiling ||
        await work.utf8Length(await work.encode(section.toJson())) >
            LazyStableCardBody.maxEncodedBytes) {
      throw StateError(
        'Complete section evidence exceeds bounds or is unavailable',
      );
    }
    final expected = LazySectionIdentity.fromIndexItem(
      bookId: index.bookId,
      publicationFingerprint: index.publicationFingerprint,
      item: index.spine[position],
      sourceChecksum: index.spine[position].sourceChecksum,
      dependencySignature: lazySectionDependencySignature(index),
    );
    if (!await work.equalCanonical(
          expected.toJson(),
          section.identity.toJson(),
        ) ||
        section.parserVersion != expected.parserVersion) {
      throw StateError(
        'Section does not belong to pinned publication authority',
      );
    }
    for (var local = 0; local < section.chunks.length; local++) {
      if (section.chunks[local].index != local) {
        throw StateError('Section-local source order is invalid');
      }
    }
    return LazyStableSectionAuthority._(
      (await work.digest([
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
      ])),
      (await work.encode(expected.toJson())),
      expected.stableKey,
      List.unmodifiable([
        for (final chunk in section.chunks)
          await canonicalOwnershipYielding(chunk, work),
      ]),
      (await work.digest(section.toJson())),
    );
  }

  final String publication;
  final String sectionJson;
  final String sectionKey;
  final List<String> owners;
  final String recordsDigest;

  String sourceIdentity(int local) {
    RangeError.checkValidIndex(local, owners);
    return '$sectionKey|$local';
  }

  String address(int local) => readerSha256([
    'LazySourceAddressV1',
    publication,
    readerSha256(sectionJson),
    local,
  ]);

  void validate(LazyEpubIndex index, ParsedSection section) {
    final current = LazyStableSectionAuthority.capture(index, section);
    if (publication != current.publication ||
        sectionJson != current.sectionJson ||
        recordsDigest != current.recordsDigest) {
      throw StateError('Exact section membership changed');
    }
  }

  Map<String, Object?> membershipJson() => {
    'count': owners.length,
    'owners': owners,
    'recordsDigest': recordsDigest,
  };
}

/// Resident mapping is deliberately not part of the serialized body/equality.
/// Build after the complete owning section has loaded and been authenticated.
final class LazyStableResidentProjection {
  LazyStableResidentProjection({
    required this.authority,
    required this.snapshot,
  }) {
    if (snapshot.owners
            .where((owner) => owner.sectionIdentity == authority.sectionKey)
            .length !=
        authority.owners.length) {
      throw StateError('Resident section membership is incomplete or extended');
    }
    for (var local = 0; local < authority.owners.length; local++) {
      final matches = snapshot.owners
          .where(
            (owner) =>
                owner.sourceIdentity == authority.sourceIdentity(local) &&
                owner.sectionIdentity == authority.sectionKey &&
                owner.spineIdentity == authority.sectionKey &&
                owner.sourceDigest == authority.owners[local],
          )
          .toList();
      if (matches.length != 1) throw StateError('Stable owner is not resident');
      _slots.add(matches.single.sourceOrdinalHint);
    }
    for (var i = 1; i < _slots.length; i++) {
      if (_slots[i] != _slots[i - 1] + 1) {
        throw StateError('Resident section order changed');
      }
    }
  }

  final LazyStableSectionAuthority authority;
  final CanonicalPaginationSourceSnapshot snapshot;
  final List<int> _slots = [];

  int resolve(int local, {int? runtimeHint}) {
    RangeError.checkValidIndex(local, _slots);
    final slot = _slots[local];
    if ((runtimeHint != null && runtimeHint != slot) ||
        snapshot.resolveOrdinal(
              sourceIdentity: authority.sourceIdentity(local),
              ordinalHint: slot,
            ) !=
            slot) {
      throw StateError('Runtime hint does not identify the stable owner');
    }
    return slot;
  }

  int localForHint(int hint) {
    final local = _slots.indexOf(hint);
    if (local < 0) {
      throw StateError('Runtime hint belongs to a different section');
    }
    resolve(local, runtimeHint: hint);
    return local;
  }

  CanonicalPaginationSourceSlice projectSlice(
    LazyStableSourceSlice slice, {
    int? runtimeHint,
  }) {
    final local = slice.localSourcePosition;
    final slot = resolve(local, runtimeHint: runtimeHint);
    final json = slice.toJson();
    if (slice.address != authority.address(local) ||
        json['sourceIdentity'] != authority.sourceIdentity(local) ||
        json['sectionIdentity'] != authority.sectionKey ||
        json['sourceDigest'] != authority.owners[local]) {
      throw StateError('Stable slice belongs to a different source');
    }
    return slice.project(slot);
  }
}

abstract final class LazyStableCardEmitter {
  static String packingIdentity(
    LazyStableSectionAuthority authority,
    ReaderLayoutContract contract,
  ) => readerSha256([
    'LazyPackingIdentityV1',
    authority.publication,
    readerStructuralOwnershipRevision,
    contract.identities.layoutMetricsFingerprint,
    contract.identities.rendererLayoutFingerprint,
    contract.identities.paginationAlgorithmFingerprint,
    readerCompatibilityClassifierRevision,
    contract.fontDeliveryEvidence.digest,
  ]);

  /// New emission from production-accepted pagination. Old card bytes and P05
  /// objects are left intact. Their source-bound F202/F208 remain runtime P05
  /// validation authority, not lazy persistence authority.
  static LazyStableCardBody emit({
    required LazyStableSectionAuthority authority,
    required CanonicalReaderPaginationSession session,
    required CanonicalFinalizedReaderCard card,
  }) {
    final contract = session.layout.contract;
    final resolved = card.resolvedLayout;
    if (contract == null ||
        resolved == null ||
        session.sourceSnapshot.sourceCount >
            CanonicalPaginationBounds.activeSourceCeiling ||
        resolved.contractIdentity != contract.identity ||
        session.controlledLayoutIdentity !=
            packingIdentity(authority, contract) ||
        !session.acceptedPublishedCards.any(
          (accepted) =>
              canonicalJsonEncode(accepted.card.toJson()) ==
                  canonicalJsonEncode(card.card.toJson()) &&
              canonicalJsonEncode(accepted.identity.toJson()) ==
                  canonicalJsonEncode(card.identity.toJson()) &&
              canonicalJsonEncode(
                    accepted.sourceSlices
                        .map((s) => s.toCanonicalJson())
                        .toList(),
                  ) ==
                  canonicalJsonEncode(
                    card.sourceSlices.map((s) => s.toCanonicalJson()).toList(),
                  ) &&
              accepted.resolvedLayout == resolved,
        )) {
      throw StateError(
        'Lazy emission requires accepted production P05 evidence',
      );
    }
    final projection = LazyStableResidentProjection(
      authority: authority,
      snapshot: session.sourceSnapshot,
    );
    // Recheck current per-source font/image evidence with the unchanged P05
    // resolver. A previously accepted object cannot smuggle stale evidence.
    final fontResolver = session.layout.fontEvidenceResolver;
    if (fontResolver == null) {
      throw StateError('Source font evidence unavailable');
    }
    final owner = canonicalBookChunkOwnershipDigest(card.card);
    final block = ReaderBlockLayoutResolver.resolve(
      contract: contract,
      chunk: card.card,
      stableBlockOwner: owner,
      sourceStructureDigestLink: owner,
      fontEvidence: fontResolver(card.card, card.card.text ?? ''),
      imageEvidence: session.layout.imageEvidenceResolver?.call(card.card),
    );
    if (resolved !=
        ReaderCardLayoutResolver.resolve(
          contract: contract,
          block: block,
          physicalSourceIdentity: owner,
        )) {
      throw StateError('P05 layout evidence no longer resolves');
    }
    ReaderLayoutRenderingAdapter.block(contract: contract, card: resolved);
    final rebuiltIdentity = CanonicalReaderCardIdentityBuilder.build(
      publicationFingerprint: session.sourceSnapshot.publicationFingerprint,
      controlledLayoutIdentity: session.controlledLayoutIdentity,
      paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
      orderedSourceSlices: card.sourceSlices,
    );
    if (canonicalJsonEncode(rebuiltIdentity.toJson()) !=
        canonicalJsonEncode(card.identity.toJson())) {
      throw StateError('Card identity does not bind its slices');
    }
    final slices = <Map<String, Object?>>[];
    for (final slice in card.sourceSlices) {
      final local = projection.localForHint(slice.sourceOrdinalHint);
      if (slice.sourceIdentity != authority.sourceIdentity(local) ||
          slice.sectionIdentity != authority.sectionKey ||
          slice.spineIdentity != authority.sectionKey ||
          slice.sourceDigest != authority.owners[local]) {
        throw StateError('Slice ownership mismatch');
      }
      slices.add({
        for (final entry in slice.toCanonicalJson().entries)
          if (entry.key != 'sourceOrdinalHint') entry.key: entry.value,
        'localSourcePosition': local,
        'address': authority.address(local),
      });
    }
    final payload = <String, Object?>{
      for (final entry in card.card.toJson().entries)
        if (entry.key != 'i' && entry.key != 'sr') entry.key: entry.value,
      if (card.card.sourceRanges?.isNotEmpty == true)
        'sr': [
          for (final range in card.card.sourceRanges!)
            {
              for (final entry in range.toJson().entries)
                if (entry.key != 'ci') entry.key: entry.value,
              'localSourcePosition': projection.localForHint(
                range.originalChunkIndex,
              ),
              'address': authority.address(
                projection.localForHint(range.originalChunkIndex),
              ),
            },
        ],
    };
    final unsigned = <String, Object?>{
      'domain': LazyStableCardBody.domain,
      'version': LazyStableCardBody.version,
      'publication': authority.publication,
      'section': jsonDecode(authority.sectionJson),
      'membership': authority.membershipJson(),
      'payload': payload,
      'slices': slices,
      'identity': rebuiltIdentity.toJson(),
      'layout': {
        'packing': session.controlledLayoutIdentity,
        'metrics': contract.identities.layoutMetricsFingerprint,
        'renderer': contract.identities.rendererLayoutFingerprint,
        'pagination': contract.identities.paginationAlgorithmFingerprint,
        'classifier': readerCompatibilityClassifierRevision,
        'structureRevision': readerStructuralOwnershipRevision,
        'fontDelivery': contract.fontDeliveryEvidence.digest,
        'blocks': [
          for (final block in resolved.blocks)
            {
              'owner': block.stableBlockOwner,
              'layout': block.blockLayoutFingerprint,
              'font': block.fontEvidenceDigest,
              'structure': block.sourceStructureDigestLink,
            },
        ],
      },
    };
    return LazyStableCardBody.fromJson({
      ...unsigned,
      'digest': readerSha256(unsigned),
    });
  }

  static Future<LazyStableCardBody> emitYielding({
    required LazyValidationWork work,
    required LazyStableSectionAuthority authority,
    required CanonicalReaderPaginationSession session,
    required CanonicalFinalizedReaderCard card,
  }) async {
    final contract = session.layout.contract;
    final resolved = card.resolvedLayout;
    var acceptedMatch = false;
    for (final accepted in session.acceptedPublishedCards) {
      if (await work.equalCanonical(
            accepted.card.toJson(),
            card.card.toJson(),
          ) &&
          await work.equalCanonical(
            accepted.identity.toJson(),
            card.identity.toJson(),
          ) &&
          await work.equalCanonical(
            accepted.sourceSlices.map((s) => s.toCanonicalJson()).toList(),
            card.sourceSlices.map((s) => s.toCanonicalJson()).toList(),
          ) &&
          accepted.resolvedLayout == resolved) {
        acceptedMatch = true;
        break;
      }
      await work.step('accepted-membership');
    }
    if (contract == null ||
        resolved == null ||
        session.sourceSnapshot.sourceCount >
            CanonicalPaginationBounds.activeSourceCeiling ||
        resolved.contractIdentity != contract.identity ||
        session.controlledLayoutIdentity !=
            packingIdentity(authority, contract) ||
        !acceptedMatch) {
      throw StateError(
        'Lazy emission requires accepted production P05 evidence',
      );
    }
    final projection = LazyStableResidentProjection(
      authority: authority,
      snapshot: session.sourceSnapshot,
    );
    // Recheck current per-source font/image evidence with the unchanged P05
    // resolver. A previously accepted object cannot smuggle stale evidence.
    final fontResolver = session.layout.fontEvidenceResolver;
    if (fontResolver == null) {
      throw StateError('Source font evidence unavailable');
    }
    final owner = (await canonicalOwnershipYielding(card.card, work));
    final block = ReaderBlockLayoutResolver.resolve(
      contract: contract,
      chunk: card.card,
      stableBlockOwner: owner,
      sourceStructureDigestLink: owner,
      fontEvidence: fontResolver(card.card, card.card.text ?? ''),
      imageEvidence: session.layout.imageEvidenceResolver?.call(card.card),
    );
    if (resolved !=
        ReaderCardLayoutResolver.resolve(
          contract: contract,
          block: block,
          physicalSourceIdentity: owner,
        )) {
      throw StateError('P05 layout evidence no longer resolves');
    }
    ReaderLayoutRenderingAdapter.block(contract: contract, card: resolved);
    final rebuiltIdentity = CanonicalReaderCardIdentityBuilder.build(
      publicationFingerprint: session.sourceSnapshot.publicationFingerprint,
      controlledLayoutIdentity: session.controlledLayoutIdentity,
      paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
      orderedSourceSlices: card.sourceSlices,
    );
    if (!await work.equalCanonical(
      rebuiltIdentity.toJson(),
      card.identity.toJson(),
    )) {
      throw StateError('Card identity does not bind its slices');
    }
    final slices = <Map<String, Object?>>[];
    for (final slice in card.sourceSlices) {
      final local = projection.localForHint(slice.sourceOrdinalHint);
      if (slice.sourceIdentity != authority.sourceIdentity(local) ||
          slice.sectionIdentity != authority.sectionKey ||
          slice.spineIdentity != authority.sectionKey ||
          slice.sourceDigest != authority.owners[local]) {
        throw StateError('Slice ownership mismatch');
      }
      slices.add({
        for (final entry in slice.toCanonicalJson().entries)
          if (entry.key != 'sourceOrdinalHint') entry.key: entry.value,
        'localSourcePosition': local,
        'address': authority.address(local),
      });
    }
    final payload = <String, Object?>{
      for (final entry in card.card.toJson().entries)
        if (entry.key != 'i' && entry.key != 'sr') entry.key: entry.value,
      if (card.card.sourceRanges?.isNotEmpty == true)
        'sr': [
          for (final range in card.card.sourceRanges!)
            {
              for (final entry in range.toJson().entries)
                if (entry.key != 'ci') entry.key: entry.value,
              'localSourcePosition': projection.localForHint(
                range.originalChunkIndex,
              ),
              'address': authority.address(
                projection.localForHint(range.originalChunkIndex),
              ),
            },
        ],
    };
    final unsigned = <String, Object?>{
      'domain': LazyStableCardBody.domain,
      'version': LazyStableCardBody.version,
      'publication': authority.publication,
      'section': jsonDecode(authority.sectionJson),
      'membership': authority.membershipJson(),
      'payload': payload,
      'slices': slices,
      'identity': rebuiltIdentity.toJson(),
      'layout': {
        'packing': session.controlledLayoutIdentity,
        'metrics': contract.identities.layoutMetricsFingerprint,
        'renderer': contract.identities.rendererLayoutFingerprint,
        'pagination': contract.identities.paginationAlgorithmFingerprint,
        'classifier': readerCompatibilityClassifierRevision,
        'structureRevision': readerStructuralOwnershipRevision,
        'fontDelivery': contract.fontDeliveryEvidence.digest,
        'blocks': [
          for (final block in resolved.blocks)
            {
              'owner': block.stableBlockOwner,
              'layout': block.blockLayoutFingerprint,
              'font': block.fontEvidenceDigest,
              'structure': block.sourceStructureDigestLink,
            },
        ],
      },
    };
    return LazyStableCardBody.fromJsonYielding({
      ...unsigned,
      'digest': (await work.digest(unsigned)),
    }, work);
  }

  static void admit({
    required LazyStableCardBody persisted,
    required LazyStableSectionAuthority authority,
    required CanonicalReaderPaginationSession session,
    required CanonicalFinalizedReaderCard regenerated,
  }) {
    if (persisted !=
        emit(authority: authority, session: session, card: regenerated)) {
      throw StateError('Lazy source, body, or layout evidence changed');
    }
  }
}
