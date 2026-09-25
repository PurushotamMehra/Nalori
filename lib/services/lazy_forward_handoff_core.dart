import 'dart:collection';
import 'dart:convert';

import '../models/canonical_pagination.dart';
import '../models/lazy_section_input.dart';
import '../models/lazy_stable_card.dart';
import '../models/reader_checkpoint.dart';
import '../models/reader_layout_contract.dart';
import 'lazy_parsed_book.dart';
import 'lazy_snapshot_handoff_service.dart';
import 'progressive_display_state.dart';
import 'reader_card_paginator.dart';
import 'reader_layout_contract_service.dart';

final class LazyForwardRetentionLimits {
  const LazyForwardRetentionLimits({
    this.sources = 432,
    this.cards = 96,
    this.guards = 25,
    this.sections = 3,
    this.bytes = 6 * 1024 * 1024,
    this.metadataBytes = 64 * 1024,
  });
  final int sources, cards, guards, sections, bytes, metadataBytes;
  void validate() {
    if (sources < 1 ||
        sources > 432 ||
        cards < 1 ||
        cards > 96 ||
        guards < 1 ||
        guards > 25 ||
        sections < 1 ||
        sections > 3 ||
        bytes < 1 ||
        bytes > 6 * 1024 * 1024 ||
        metadataBytes < 1 ||
        metadataBytes > 64 * 1024) {
      throw ArgumentError(
        'Retention limits may only tighten the approved ceilings',
      );
    }
  }
}

/// Deterministic owned-state census, not VM heap/RSS or whole-app memory.
/// Payload bytes use UTF-16 string storage and existing renderer retained-state
/// estimates. During pagination decoded-source/frontier scratch is reserved too.
final class LazyForwardLiveState {
  const LazyForwardLiveState({
    required this.sources,
    required this.backingRecords,
    required this.snapshotViews,
    required this.sessions,
    required this.rendererAuthorities,
    required this.cards,
    required this.guards,
    required this.sections,
    required this.accountedBytes,
    required this.metadataBytes,
    required this.pendingTransfers,
    required this.preparationReferences,
    required this.rendererLeases,
    required this.frontierCardReservation,
    required this.resolverReferences,
    required this.indexMetadataBytes,
  });
  final int sources,
      backingRecords,
      snapshotViews,
      sessions,
      rendererAuthorities;
  final int cards, guards, sections, accountedBytes, metadataBytes;
  final int resolverReferences, indexMetadataBytes;
  final int pendingTransfers,
      preparationReferences,
      rendererLeases,
      frontierCardReservation;
  Map<String, int> toJson() => {
    'sources': sources,
    'backingRecords': backingRecords,
    'snapshots': snapshotViews,
    'sessions': sessions,
    'renderers': rendererAuthorities,
    'cards': cards,
    'guards': guards,
    'sections': sections,
    'bytes': accountedBytes,
    'metadataBytes': metadataBytes,
    'pending': pendingTransfers,
    'preparations': preparationReferences,
    'leases': rendererLeases,
    'frontierReservation': frontierCardReservation,
    'resolverReferences': resolverReferences,
    'indexMetadataBytes': indexMetadataBytes,
  };
}

/// An inert token: it never captures source/session/preparation references.
final class LazyForwardTransfer {
  const LazyForwardTransfer._(this.id);
  final int id;
}

final class LazyForwardBeginResult {
  const LazyForwardBeginResult(this.result, [this.transfer]);
  final LazySnapshotPublicationResult result;
  final LazyForwardTransfer? transfer;
}

final class LazyRendererLease {
  LazyRendererLease._(this._core, this._id, this.signature);
  LazyForwardHandoffCore? _core;
  final int _id;
  final String signature;
  ResolvedReaderBlockLayout block() {
    final core = _core;
    if (core == null) throw StateError('Renderer lease released');
    return core._render(signature);
  }

  void release() {
    _core?._leases.remove(_id);
    _core = null;
  }
}

/// Owns one pending transfer. Accepted state remains in the production display
/// publication; handles and renderer leases cannot capture historical chains.
final class LazyForwardHandoffCore {
  LazyForwardHandoffCore(
    this.state, {
    this.limits = const LazyForwardRetentionLimits(),
  }) {
    limits.validate();
    _check();
  }
  final ProgressiveDisplayState state;
  final LazyForwardRetentionLimits limits;
  _PendingForward? _pending;
  LazyRetainedSection? _retentionCandidate;
  final Map<int, String> _leases = {};
  int _sequence = 0;
  final Map<String, int> peak = {};

  LazyForwardLiveState get liveState => _census();
  LazySectionInput inputFor(LazyForwardTransfer transfer) =>
      _require(transfer).input!;

  LazyForwardBeginResult beginNext(
    ParsedSection section,
    LazyHandoffOperation operation,
  ) => _begin(section, operation, backward: false);

  LazyForwardBeginResult beginPrevious(
    ParsedSection section,
    LazyHandoffOperation operation,
  ) => _begin(section, operation, backward: true);

  LazyForwardBeginResult _begin(
    ParsedSection section,
    LazyHandoffOperation operation, {
    required bool backward,
  }) {
    if (_pending != null || _retentionCandidate != null) {
      return const LazyForwardBeginResult(
        LazySnapshotPublicationResult(LazySnapshotPublicationOutcome.busy),
      );
    }
    if (state.lazyAttemptFailed(operation.owner)) {
      return const LazyForwardBeginResult(
        LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.failedAttempt,
        ),
      );
    }
    final old = state.lazyPublication;
    if (old == null ||
        !operation.isCurrent ||
        old.owner.bookOpenEpoch != operation.owner.bookOpenEpoch ||
        old.owner.displayOwner != operation.owner.displayOwner) {
      return const LazyForwardBeginResult(
        LazySnapshotPublicationResult(LazySnapshotPublicationOutcome.stale),
      );
    }
    if (old.predecessor != null || old.current.input.sectionCount != 1) {
      return const LazyForwardBeginResult(
        LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.retentionRequired,
        ),
      );
    }
    try {
      if (backward &&
          old.current.input.publication
                  .predecessorOf(old.current.input.sections.single)
                  ?.stableKey !=
              section.identity.stableKey) {
        return const LazyForwardBeginResult(
          LazySnapshotPublicationResult(
            LazySnapshotPublicationOutcome.exactUnavailable,
            'Verified immediate predecessor required',
          ),
        );
      }
      final input = backward
          ? LazySectionInput.capture(
              publication: old.current.input.publication,
              sections: [section],
            )
          : old.current.input.append(section);
      final token = LazyForwardTransfer._(++_sequence);
      _pending = _PendingForward(
        token.id,
        input,
        section,
        old.digest,
        operation.owner,
        state.lazyVisibleCardSignature,
        backward: backward,
        committedInput: backward ? old.current.input : null,
        window: backward ? input.joinSuccessor(old.current.input) : null,
      );
      _check();
      return LazyForwardBeginResult(
        const LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.prepared,
        ),
        token,
      );
    } on Object catch (error) {
      _release();
      return LazyForwardBeginResult(
        LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.boundExceeded,
          '$error',
        ),
      );
    }
  }

  Future<LazySnapshotPublicationResult> prepare(
    LazyForwardTransfer transfer,
    ReaderCardPaginatorLayout layout,
    LazyHandoffOperation operation, {
    ReaderCardPaginatorLayout? committedLayout,
  }) async {
    final pending = _pending;
    if (pending == null ||
        pending.id != transfer.id ||
        pending.working ||
        pending.prepared != null) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.stale,
      );
    }
    if (!_current(pending, operation)) {
      _release();
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.stale,
      );
    }
    pending.working = true;
    pending.layout = layout;
    try {
      _check();
      final active = _census(includePending: false);
      final controls = operation.pagination;
      final ownedOperation = LazyHandoffOperation(
        owner: operation.owner,
        currentOwner: operation.currentOwner,
        pagination: CanonicalPaginationOperationControls(
          generationToken: controls.generationToken,
          currentGenerationToken: controls.currentGenerationToken,
          scheduler: controls.scheduler,
          priority: controls.priority,
          isCancelled: () => pending.cancelled || !operation.isCurrent,
          diagnosticBookId: controls.diagnosticBookId,
          onDiagnostic: controls.onDiagnostic,
        ),
      );
      pending.prepared = await LazyPreparedSection.prepare(
        input: pending.input!,
        layout: layout,
        operation: ownedOperation,
        maximumCards: limits.cards - active.cards,
        maximumGuards: limits.guards - active.guards - 3,
        onProgress: (session) {
          pending.session = session;
          _check();
        },
      );
      pending.source = null;
      if (pending.backward) {
        if (committedLayout == null) {
          throw const LazyExactReconstructionUnavailable(
            'Current-section renderer evidence required',
          );
        }
        pending.workingInput = pending.committedInput;
        pending.layout = committedLayout;
        final remaining = limits.cards - _census().cards;
        final remainingGuards = limits.guards - _census().guards - 2;
        pending.verified = await LazyPreparedSection.prepare(
          input: pending.committedInput!,
          layout: committedLayout,
          operation: ownedOperation,
          maximumWork:
              CanonicalPaginationBounds.normalWorkEnvelope -
              pending.prepared!.workEntries,
          maximumCards: remaining,
          maximumGuards: remainingGuards,
          onProgress: (session) {
            pending.session = session;
            _check();
          },
        );
        final work =
            pending.prepared!.workEntries + pending.verified!.workEntries;
        if (work > (peak['reconstructionWork'] ?? 0)) {
          peak['reconstructionWork'] = work;
        }
      }
      pending.working = false;
      _check();
      if (!_current(pending, operation)) {
        final cancelled =
            pending.cancelled || operation.pagination.isCancelled();
        _release();
        return LazySnapshotPublicationResult(
          cancelled
              ? LazySnapshotPublicationOutcome.cancelled
              : LazySnapshotPublicationOutcome.stale,
        );
      }
      pending.handoff = pending.backward
          ? buildLazySnapshotPrepend(
              old: state.lazyPublication!,
              predecessor: pending.prepared!,
              reconstructedCurrent: pending.verified!,
              window: pending.window!,
              committedCardSignature: state.lazyVisibleCardSignature!,
            )
          : buildLazySnapshotHandoff(
              old: state.lazyPublication!,
              successor: pending.prepared!,
              committedCardSignature: state.lazyVisibleCardSignature,
            );
      _check();
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.prepared,
      );
    } on Object catch (error) {
      final outcome = pending.cancelled || operation.pagination.isCancelled()
          ? LazySnapshotPublicationOutcome.cancelled
          : !_current(pending, operation)
          ? LazySnapshotPublicationOutcome.stale
          : pending.backward && error is! LazyHandoffBoundExceeded
          ? LazySnapshotPublicationOutcome.exactUnavailable
          : LazySnapshotPublicationOutcome.boundExceeded;
      if (pending.backward &&
          (outcome == LazySnapshotPublicationOutcome.exactUnavailable ||
              outcome == LazySnapshotPublicationOutcome.boundExceeded)) {
        state.latchLazyAttemptFailure(operation);
      }
      _release();
      return LazySnapshotPublicationResult(outcome, '$error');
    }
  }

  LazySnapshotPublicationResult publish(
    LazyForwardTransfer transfer,
    LazyHandoffOperation operation, {
    LazySnapshotHandoffV1? proposal,
    void Function()? beforeCommit,
  }) {
    final pending = _pending;
    if (pending == null ||
        pending.id != transfer.id ||
        pending.prepared == null ||
        pending.working) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.replayed,
      );
    }
    try {
      if (!_current(pending, operation)) {
        return LazySnapshotPublicationResult(
          operation.pagination.isCancelled() || pending.cancelled
              ? LazySnapshotPublicationOutcome.cancelled
              : LazySnapshotPublicationOutcome.stale,
        );
      }
      if (proposal != null) pending.handoff = proposal;
      try {
        _check();
      } on Object catch (error) {
        return LazySnapshotPublicationResult(
          LazySnapshotPublicationOutcome.boundExceeded,
          '$error',
        );
      }
      final controls = operation.pagination;
      final publicationOperation = LazyHandoffOperation(
        owner: operation.owner,
        currentOwner: operation.currentOwner,
        pagination: CanonicalPaginationOperationControls(
          generationToken: controls.generationToken,
          currentGenerationToken: controls.currentGenerationToken,
          scheduler: controls.scheduler,
          priority: controls.priority,
          isCancelled: () =>
              pending.cancelled ||
              !identical(_pending, pending) ||
              controls.isCancelled(),
          diagnosticBookId: controls.diagnosticBookId,
          onDiagnostic: controls.onDiagnostic,
        ),
      );
      if (pending.backward) {
        return state.publishSnapshotPrepend(
          predecessor: pending.prepared!,
          reconstructedCurrent: pending.verified!,
          window: pending.window!,
          handoff: pending.handoff!,
          operation: publicationOperation,
          beforeCommit: beforeCommit,
        );
      }
      return state.publishSnapshotHandoff(
        successor: pending.prepared!,
        handoff: pending.handoff!,
        operation: publicationOperation,
        beforeCommit: beforeCommit,
      );
    } finally {
      if (identical(_pending, pending)) _release();
      _observe();
    }
  }

  void cancelPending() {
    final pending = _pending;
    if (pending == null) return;
    pending.cancelled = true;
    // Active physical pagination stays accounted until its frame settles.
    if (!pending.working) _release();
  }

  LazySnapshotPublicationResult retainSnapshotSuffix(
    LazyHandoffOperation operation,
  ) => _retain(operation, predecessor: false);

  LazySnapshotPublicationResult retainSnapshotPrefix(
    LazyHandoffOperation operation,
  ) => _retain(operation, predecessor: true);

  LazySnapshotPublicationResult _retain(
    LazyHandoffOperation operation, {
    required bool predecessor,
  }) {
    if (_pending != null || _retentionCandidate != null) {
      return const LazySnapshotPublicationResult(
        LazySnapshotPublicationOutcome.busy,
      );
    }
    var exceeded = false;
    try {
      final result = state.retainSnapshotSuffix(
        operation: operation,
        retainPredecessor: predecessor,
        pinnedRendererCards: _leases.values.toSet(),
        beforeCommit: () {
          final selected = predecessor
              ? state.lazyPublication!.predecessor!
              : state.lazyPublication!.current;
          final kept = selected.cards.map((c) => c.identity.signature).toSet();
          if (!_leases.values.every(kept.contains)) {
            throw StateError('Renderer pin changed before retention');
          }
        },
        onPrepared: (candidate) {
          _retentionCandidate = candidate;
          try {
            _check();
          } on Object {
            exceeded = true;
            rethrow;
          }
        },
      );
      return exceeded
          ? const LazySnapshotPublicationResult(
              LazySnapshotPublicationOutcome.boundExceeded,
            )
          : result;
    } finally {
      _retentionCandidate = null;
      _observe();
    }
  }

  LazyRendererLease leaseRenderer(String signature) {
    _render(signature);
    if (_leases.length >= limits.cards) {
      throw StateError('Renderer lease budget exhausted');
    }
    final id = ++_sequence;
    _leases[id] = signature;
    try {
      _check();
    } on Object {
      _leases.remove(id);
      rethrow;
    }
    return LazyRendererLease._(this, id, signature);
  }

  ResolvedReaderBlockLayout _render(String signature) {
    final publication = state.lazyPublication;
    if (publication == null) throw StateError('No accepted renderer authority');
    for (final authority in [
      if (publication.predecessor != null) publication.predecessor!,
      publication.current,
    ]) {
      final index = authority.cards.indexWhere(
        (c) => c.identity.signature == signature,
      );
      if (index >= 0) {
        authority.validate();
        return ReaderLayoutRenderingAdapter.block(
          contract: authority.rendererContract,
          card: authority.cards[index].resolvedLayout!,
        );
      }
    }
    throw StateError('Renderer authority retired');
  }

  bool _current(_PendingForward pending, LazyHandoffOperation operation) =>
      !pending.cancelled &&
      operation.isCurrent &&
      pending.owner == operation.owner &&
      state.lazyPublication?.digest == pending.publicationDigest &&
      state.lazyVisibleCardSignature == pending.visibleSignature;
  _PendingForward _require(LazyForwardTransfer transfer) {
    final pending = _pending;
    if (pending == null || pending.id != transfer.id) {
      throw StateError('Preparation token released');
    }
    return pending;
  }

  void _release() {
    _pending?.clear();
    _pending = null;
  }

  void _observe() {
    for (final entry in liveState.toJson().entries) {
      if (entry.value > (peak[entry.key] ?? 0)) peak[entry.key] = entry.value;
    }
  }

  void _check() {
    final live = liveState;
    if (live.sources > limits.sources ||
        live.cards > limits.cards ||
        live.guards > limits.guards ||
        live.sections > limits.sections ||
        live.accountedBytes > limits.bytes ||
        live.metadataBytes > limits.metadataBytes) {
      throw LazyHandoffBoundExceeded(
        'Core retention bound exceeded: ${live.toJson()}',
      );
    }
    _observe();
  }

  LazyForwardLiveState _census({bool includePending = true}) {
    final publication = state.lazyPublication;
    final pending = includePending ? _pending : null;
    final authorities = <LazySectionAuthority>[
      if (publication?.predecessor != null) publication!.predecessor!,
      if (publication != null) publication.current,
      if (_retentionCandidate != null) _retentionCandidate!,
      if (pending?.prepared != null) pending!.prepared!,
      if (pending?.verified != null) pending!.verified!,
    ];
    final inputs = HashSet<LazySectionInput>.identity();
    if (publication != null) inputs.add(publication.sourceInput);
    final sessions = HashSet<CanonicalReaderPaginationSession>.identity();
    final renderers = HashSet<ReaderLayoutContract>.identity();
    final cards = HashSet<CanonicalFinalizedReaderCard>.identity();
    final bodies = HashSet<LazyStableCardBody>.identity();
    final records = HashSet<CanonicalLazySourceRecord>.identity();
    final snapshots = HashSet<CanonicalPaginationSourceSnapshot>.identity();
    final sectionStrings = HashSet<String>.identity();
    final sections = <String>{};
    final guards = <String>{};
    final metadata = <String>{};
    var preparationReferences = 0;
    var resolverReferences = 0;
    var bytes = 0;
    final indexes = HashSet<PublicationSpineAuthority>.identity();
    for (final authority in authorities) {
      inputs.add(authority.input);
      if (authority.session != null) sessions.add(authority.session!);
      if (authority is LazyPreparedSection) preparationReferences++;
      renderers.add(authority.rendererContract);
      cards.addAll(authority.cards);
      bodies.addAll(authority.bodies);
      guards.add(authority.sessionDigest);
      if (authority.retentionDigest != null) {
        guards.add(authority.retentionDigest!);
      }
      if (authority.receipt != null) {
        guards.add(authority.receipt!.receiptDigest);
        metadata.add(authority.receipt!.canonicalEncoding);
      }
      bytes += authority.cardGuards.fold<int>(0, (n, s) => n + 2 * s.length);
    }
    if (pending != null) {
      if (pending.input != null) inputs.add(pending.input!);
      if (pending.window != null) inputs.add(pending.window!);
      if (pending.committedInput != null) inputs.add(pending.committedInput!);
      if (pending.session != null) sessions.add(pending.session!);
      if (pending.layout?.contract != null) {
        renderers.add(pending.layout!.contract!);
      }
      if (pending.prepared == null ||
          (pending.backward && pending.working && pending.verified == null)) {
        preparationReferences++;
      }
      if (pending.handoff != null) {
        guards.add(pending.handoff!.handoffDigest);
        metadata.add(pending.handoff!.canonicalEncoding);
      }
      if (pending.source != null) {
        bytes += 2 * canonicalJsonEncode(pending.source!.toJson()).length;
      }
    }
    for (final input in inputs) {
      indexes.add(input.publication);
      snapshots.add(input.snapshot);
      records.addAll(input.sourceRecords);
      sectionStrings.addAll(input.encodedSections);
      sections.addAll(input.sectionAuthorities.map((a) => a.sectionKey));
      bytes += input.sectionAuthorities.fold<int>(
        0,
        (n, a) =>
            n +
            2 * canonicalJsonEncode([a.sectionJson, a.membershipJson()]).length,
      );
    }
    for (final session in sessions) {
      resolverReferences +=
          (session.layout.fontEvidenceResolver == null ? 0 : 1) +
          (session.layout.imageEvidenceResolver == null ? 0 : 1);
      snapshots.add(session.sourceSnapshot);
      cards.addAll(session.acceptedPublishedCards);
      for (final record in session.checkpointIndex.records) {
        guards.add(record.integrityDigest);
        bytes += 2 * record.canonicalEncoding.length;
      }
    }
    if (publication != null) {
      guards.add(publication.lineageRootDigest);
      if (publication.previousHandoffDigest != null) {
        guards.add(publication.previousHandoffDigest!);
      }
      if (publication.handoff != null) {
        metadata.add(publication.handoff!.canonicalEncoding);
      }
    }
    final indexMetadataBytes = indexes.fold<int>(
      0,
      (n, index) => n + index.accountedMetadataBytes,
    );
    bytes += indexMetadataBytes;
    for (final snapshot in snapshots) {
      records.addAll(snapshot.lazyRecords ?? const []);
      bytes +=
          2 *
          canonicalJsonEncode(
            snapshot.owners.map((o) => o.toDigestJson()).toList(),
          ).length;
    }
    for (final record in records) {
      bytes +=
          2 *
          (record.encodedSource.length +
              record.sourceIdentity.length +
              record.sectionIdentity.length +
              record.spineIdentity.length +
              record.sourceDigest.length);
    }
    for (final encoded in sectionStrings) {
      bytes += 2 * encoded.length;
    }
    for (final card in cards) {
      bytes +=
          2 * canonicalJsonEncode(card.card.toJson()).length +
          2 *
              canonicalJsonEncode(
                card.sourceSlices.map((s) => s.toCanonicalJson()).toList(),
              ).length +
          (card.resolvedLayout?.retainedStateBytes ?? 0);
    }
    for (final body in bodies) {
      bytes += 2 * body.canonicalEncoding.length;
    }
    for (final renderer in renderers) {
      bytes += renderer.retainedStateBytes;
    }
    final metadataBytes = metadata.fold<int>(
      0,
      (n, s) => n + utf8.encode(s).length,
    );
    bytes +=
        metadata.fold<int>(0, (n, s) => n + 2 * s.length) +
        guards.fold<int>(0, (n, s) => n + 2 * s.length);
    bytes += _leases.values.fold<int>(0, (n, s) => n + 32 + 2 * s.length);
    bytes +=
        16 * state.displayChunks.length + 16 * state.originalToDisplay.length;
    final working = pending?.working == true;
    final workingInput = pending?.workingInput ?? pending?.input;
    final scratchSources = working ? workingInput!.snapshot.sourceCount + 1 : 0;
    final scratchBytes = working
        ? workingInput!.sourceRecords.fold<int>(
            0,
            (n, r) => n + 4 * r.encodedSource.length,
          )
        : 0;
    final rawSources = pending?.source?.chunks.length ?? 0;
    return LazyForwardLiveState(
      sources: records.length + scratchSources + rawSources,
      backingRecords: records.length,
      snapshotViews: snapshots.length,
      sessions: sessions.length,
      rendererAuthorities: renderers.length,
      cards: cards.length,
      guards:
          guards.length + (pending != null && pending.handoff == null ? 2 : 0),
      sections: sections.length,
      accountedBytes: bytes + scratchBytes,
      metadataBytes: metadataBytes,
      pendingTransfers: pending == null && _retentionCandidate == null ? 0 : 1,
      preparationReferences: preparationReferences,
      rendererLeases: _leases.length,
      frontierCardReservation: working ? 2 : 0,
      resolverReferences: resolverReferences,
      indexMetadataBytes: indexMetadataBytes,
    );
  }
}

final class _PendingForward {
  _PendingForward(
    this.id,
    this.input,
    this.source,
    this.publicationDigest,
    this.owner,
    this.visibleSignature, {
    this.backward = false,
    this.committedInput,
    this.window,
  });
  final int id;
  final bool backward;
  LazySectionInput? committedInput, window, workingInput;
  LazyPreparedSection? verified;
  LazySectionInput? input;
  ParsedSection? source;
  ReaderCardPaginatorLayout? layout;
  CanonicalReaderPaginationSession? session;
  LazyPreparedSection? prepared;
  LazySnapshotHandoffV1? handoff;
  final String publicationDigest;
  final String? visibleSignature;
  final LazyPublicationOwner owner;
  bool working = false;
  bool cancelled = false;
  void clear() {
    committedInput = null;
    window = null;
    workingInput = null;
    verified = null;
    input = null;
    source = null;
    layout = null;
    session = null;
    prepared = null;
    handoff = null;
  }
}
