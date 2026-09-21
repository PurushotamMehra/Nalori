import 'dart:convert';

import '../models/canonical_pagination.dart';
import '../models/lazy_stable_card.dart';
import '../models/reader_checkpoint.dart';
import 'lazy_stable_card_service.dart';
import 'reader_card_paginator.dart';
import 'reader_checkpoint_store.dart';

enum LazyRestoreKind {
  exactStableBody,
  legacyExactSignature,
  semanticMigrationV1,
  exactUnavailable,
}

enum LazyRecoveryAction { retry, back }

final class LazyRestorePreparation {
  const LazyRestorePreparation._(
    this.kind,
    this.body,
    this.legacyCard,
    this.reason,
  );
  final LazyRestoreKind kind;
  final LazyStableCardBody? body;
  final CanonicalFinalizedReaderCard? legacyCard;
  final String reason;
  List<LazyRecoveryAction> get actions =>
      kind == LazyRestoreKind.exactUnavailable
      ? const [LazyRecoveryAction.retry, LazyRecoveryAction.back]
      : const [];
  String? get presentation => kind == LazyRestoreKind.semanticMigrationV1
      ? 'Reader layout was rebuilt'
      : null;
}

/// Persistence prerequisite only: consumes already bounded, accepted production
/// pagination. It neither searches historical windows nor schedules the screen.
/// An exact legacy attempt needs externally retained authoritative provenance;
/// the old checkpoint itself never supplies a historical window recipe.
final class LazyCheckpointRecoveryCoordinator {
  LazyCheckpointRecoveryCoordinator({
    required this.store,
    required this.bookId,
    required this.publicationFingerprint,
  });

  final ReaderCheckpointStore store;
  final String bookId;
  final String publicationFingerprint;
  ReaderCheckpoint? _current;
  ReaderCheckpoint? get current => _current;
  int _epoch = 0;
  int _revision = 0;
  LazyRestorePreparation? _pending;
  bool _committing = false;
  bool get ordinaryWritesEnabled => false;

  Future<void> initialize() async {
    _current = await store.loadNewestValid(bookId);
    _epoch = await store.beginSession(bookId);
    _pending = null;
  }

  LazyRestorePreparation _unavailable(String reason) =>
      _pending = LazyRestorePreparation._(
        LazyRestoreKind.exactUnavailable,
        null,
        null,
        reason,
      );

  LazyRestorePreparation prepare({
    required LazyStableSectionAuthority authority,
    required CanonicalReaderPaginationSession session,
    String? authoritativeLegacyWindowDigest,
  }) {
    _pending = null;
    final checkpoint = _current;
    if (checkpoint == null ||
        checkpoint.publicationFingerprint != publicationFingerprint ||
        session.sourceSnapshot.bookId != bookId ||
        session.sourceSnapshot.publicationFingerprint !=
            publicationFingerprint) {
      return _unavailable('checkpoint_or_publication_unavailable');
    }
    if (session.sourceSnapshot.sourceCount >
            CanonicalPaginationBounds.activeSourceCeiling ||
        session.acceptedPublishedCards.length >
            CanonicalPaginationBounds.activeCardCeiling ||
        session.checkpointIndex.records.length >
            CanonicalPaginationBounds.residentContinuationRecordBasis) {
      return _unavailable('bounded_evidence_unavailable');
    }
    if (checkpoint.formatVersion == 1 &&
        authoritativeLegacyWindowDigest != null &&
        authoritativeLegacyWindowDigest ==
            session.sourceSnapshot.snapshotDigest &&
        checkpoint.layoutFingerprint == session.controlledLayoutIdentity &&
        checkpoint.layoutFingerprint == session.layout.contract?.identity) {
      final exact = session.acceptedPublishedCards
          .where(
            (card) => card.identity.signature == checkpoint.card?.signature,
          )
          .toList();
      if (exact.length == 1) {
        return _pending = LazyRestorePreparation._(
          LazyRestoreKind.legacyExactSignature,
          null,
          exact.single,
          'known_original_window',
        );
      }
    }
    final candidates = <LazyStableCardBody>[];
    try {
      for (final card in session.acceptedPublishedCards) {
        candidates.add(
          LazyStableCardEmitter.emit(
            authority: authority,
            session: session,
            card: card,
          ),
        );
      }
    } on StateError {
      return _unavailable('verified_lazy_target_unavailable');
    } on FormatException {
      return _unavailable('invalid_lazy_target_evidence');
    }
    if (checkpoint.formatVersion == 2) {
      final matches = candidates
          .where((body) => body == checkpoint.lazyStableBody)
          .toList();
      if (matches.length != 1) {
        return _unavailable('exact_source_or_layout_evidence_changed');
      }
      return _pending = LazyRestorePreparation._(
        LazyRestoreKind.exactStableBody,
        matches.single,
        null,
        'exact_stable_body',
      );
    }

    // Exact semantic ownership, not text similarity, authorizes conversion.
    // Resolve the persisted anchor to one source, then choose its nearest card.
    final anchor = checkpoint.semanticAnchor;
    final sourceIds = <String>{};
    final distances = <LazyStableCardBody, int>{};
    final projection = LazyStableResidentProjection(
      authority: authority,
      snapshot: session.sourceSnapshot,
    );
    for (final body in candidates) {
      for (final range in body.identity.ranges) {
        if (range.sectionIdentity != anchor.sectionIdentity ||
            range.sectionChecksum != anchor.sectionChecksum ||
            range.logicalBlockId != anchor.logicalBlockId ||
            range.structuralType != anchor.structuralType ||
            range.sourceIdentity == null) {
          continue;
        }
        final offset = anchor.blockOffsetUtf16;
        final local = authority.owners
            .asMap()
            .keys
            .where(
              (local) =>
                  authority.sourceIdentity(local) == range.sourceIdentity,
            )
            .single;
        final source = session.sourceSnapshot.resolveOrdinalSource(
          projection.resolve(local),
        );
        if (offset != null &&
            (offset < 0 || offset > (source.text?.length ?? 0))) {
          continue;
        }
        sourceIds.add(range.sourceIdentity!);
        final start = range.startUtf16;
        final end = range.endUtf16;
        final distance = offset == null || start == null || end == null
            ? 0
            : offset < start
            ? start - offset
            : offset >= end
            ? offset - end + 1
            : 0;
        final prior = distances[body];
        if (prior == null || distance < prior) distances[body] = distance;
      }
    }
    if (sourceIds.length != 1 || distances.isEmpty) {
      // Some legacy semantic anchors used href/logical IDs while their durable
      // location retained the exact section-local source. Use that independent
      // anchor only when every publication/section/parser field agrees.
      final location = checkpoint.stableLocation;
      final section = jsonDecode(authority.sectionJson) as Map;
      final local = location?.localChunkIndex;
      if (location != null &&
          local != null &&
          local >= 0 &&
          local < authority.owners.length &&
          location.bookId == bookId &&
          location.publicationFingerprint == publicationFingerprint &&
          location.spineIndex == section['spineIndex'] &&
          location.normalizedHref == section['normalizedHref'] &&
          location.sourceChecksum == section['sourceChecksum'] &&
          location.sourceParserVersion == section['parserVersion']) {
        sourceIds.clear();
        distances.clear();
        final source = session.sourceSnapshot.resolveOrdinalSource(
          projection.resolve(local),
        );
        final extent = source.text?.length ?? 0;
        if (location.textOffset >= 0 && location.textOffset <= extent) {
          for (final body in candidates) {
            for (final slice in body.sourceSlices) {
              if (slice.localSourcePosition != local) continue;
              final value = slice.toJson();
              final start = value['startUtf16'] as int?;
              final end = value['endUtf16'] as int?;
              final offset = location.textOffset;
              final distance = start == null || end == null
                  ? 0
                  : offset < start
                  ? start - offset
                  : offset >= end
                  ? offset - end + 1
                  : 0;
              sourceIds.add(authority.sourceIdentity(local));
              final prior = distances[body];
              if (prior == null || distance < prior) distances[body] = distance;
            }
          }
        }
      }
    }
    if (sourceIds.length != 1 || distances.isEmpty) {
      return _unavailable('unique_semantic_owner_unavailable');
    }
    final minimum = distances.values.reduce((a, b) => a < b ? a : b);
    final nearest = distances.entries
        .where((entry) => entry.value == minimum)
        .toList();
    if (nearest.length != 1) return _unavailable('semantic_card_ambiguous');
    return _pending = LazyRestorePreparation._(
      LazyRestoreKind.semanticMigrationV1,
      nearest.single.key,
      null,
      'lazy_semantic_migration_v1',
    );
  }

  /// Retry and Back both abandon the private target and preserve the journal.
  /// Retry permits another bounded prepare; Back leaves navigation to the caller.
  void abandon(LazyRecoveryAction action) {
    _pending = null;
  }

  Future<bool> commitPublished({
    required LazyRestorePreparation preparation,
    required LazyStableCardBody publishedBody,
    required bool Function() isCurrent,
  }) async {
    if (_committing ||
        !identical(_pending, preparation) ||
        preparation.body != publishedBody ||
        !isCurrent() ||
        preparation.kind == LazyRestoreKind.exactUnavailable ||
        preparation.kind == LazyRestoreKind.legacyExactSignature) {
      return false;
    }
    final previous = _current;
    if (previous == null) return false;
    final checkpoint = ReaderCheckpoint.createLazy(
      bookId: bookId,
      body: publishedBody,
      sessionEpoch: _epoch,
      revision: ++_revision,
      committedAtMillis: DateTime.now().millisecondsSinceEpoch,
      migration: preparation.kind == LazyRestoreKind.semanticMigrationV1
          ? 'lazy_semantic_migration_v1'
          : null,
    );
    _committing = true;
    try {
      final result = await store.commit(
        checkpoint,
        expectedPreviousChecksum: previous.integrityChecksum,
        canCommit: () => identical(_pending, preparation) && isCurrent(),
      );
      if (result.applied) {
        _current = checkpoint;
        _pending = null;
      }
      return result.applied;
    } finally {
      _committing = false;
    }
  }
}
