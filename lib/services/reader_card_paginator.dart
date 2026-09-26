import '../models/lazy_section_input.dart';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book_chunk.dart';
import '../models/book_list_semantics.dart';
import '../models/canonical_pagination.dart';
import '../models/canonical_pagination_checkpoint_index.dart';
import '../models/reader_checkpoint.dart';
import '../models/reader_font_evidence.dart';
import '../models/reader_layout_contract.dart';
import '../models/reader_text_boundary.dart';
import '../models/reading_settings.dart';
import '../utils/final_layout_paragraphs.dart';
import '../utils/reader_content_parser.dart';
import '../utils/reader_list_layout.dart';
import '../utils/text_span_utils.dart';
import 'frame_budgeted_range_scheduler.dart';
import 'progressive_display_state.dart';
import 'reader_text_boundary_service.dart';
import 'reader_layout_contract_service.dart';

const double kReaderDialogueTextInset = 0.0;

typedef ReaderCardPaginatorDiagnostic =
    void Function(String phase, Map<String, Object?> fields);
typedef ReaderStableFontEvidenceResolver =
    List<ReaderSourceFontMetricEvidence> Function(BookChunk chunk, String text);
typedef ReaderImageEvidenceResolver =
    ReaderImageMetricEvidence? Function(BookChunk chunk);

@immutable
final class ReaderCardPaginatorAnchor {
  const ReaderCardPaginatorAnchor({
    required this.sourceIndex,
    required this.textOffset,
  });

  final int sourceIndex;
  final int textOffset;
}

/// Explicit measurement inputs captured by `ReaderScreen` before pagination.
///
/// This preserves the current measurement behavior; it is not the final P05
/// layout contract.
@immutable
final class ReaderCardPaginatorLayout {
  const ReaderCardPaginatorLayout({
    required this.availableWidth,
    required this.pageHeightBudget,
    required this.physicalTextBudget,
    required this.minUsefulHeight,
    required this.tinyWordCount,
    required this.tinyHeightRatio,
    required this.settings,
    required this.bodyStyle,
    required this.headingStyle,
    required this.bodyStrut,
    required this.headingStrut,
    required this.textScaler,
    this.contract,
    this.fontEvidenceResolver,
    this.imageEvidenceResolver,
  });

  final double availableWidth;
  final double pageHeightBudget;
  final double physicalTextBudget;
  final double minUsefulHeight;
  final int tinyWordCount;
  final double tinyHeightRatio;
  final ReadingSettings settings;
  final TextStyle bodyStyle;
  final TextStyle headingStyle;
  final StrutStyle bodyStrut;
  final StrutStyle headingStrut;
  final TextScaler textScaler;
  final ReaderLayoutContract? contract;
  final ReaderStableFontEvidenceResolver? fontEvidenceResolver;
  final ReaderImageEvidenceResolver? imageEvidenceResolver;
}

/// Temporary ReaderScreen compatibility input owned for conversion/removal by
/// TASK-P04-004.
///
/// [sourceChunks] is an unmodifiable live view only until [paginate] is
/// invoked. The compatibility adapter synchronously pins immutable canonical
/// source records before it starts asynchronous engine work.
@immutable
final class ReaderCardPaginatorRequest {
  ReaderCardPaginatorRequest({
    required this.range,
    required List<BookChunk> sourceChunks,
    required this.layout,
    required this.scheduler,
    required this.priority,
    required this.isCancelled,
    required this.diagnosticBookId,
    required this.parentGeneration,
    this.currentGenerationForDiagnostics,
    this.finalizeAnchor,
    this.onDiagnostic,
  }) : sourceChunks = UnmodifiableListView<BookChunk>(sourceChunks);

  final DisplayRangeRequest range;
  final List<BookChunk> sourceChunks;
  final ReaderCardPaginatorLayout layout;
  final FrameBudgetedRangeScheduler scheduler;
  final DisplayRangeTaskPriority priority;

  /// Evaluated at the same scheduler checkpoints as the former local closure.
  final bool Function() isCancelled;
  final String diagnosticBookId;
  final int parentGeneration;
  final int Function()? currentGenerationForDiagnostics;
  final ReaderCardPaginatorAnchor? finalizeAnchor;
  final ReaderCardPaginatorDiagnostic? onDiagnostic;
}

@immutable
final class CanonicalPaginationOperationControls {
  const CanonicalPaginationOperationControls({
    required this.generationToken,
    required this.scheduler,
    required this.priority,
    required this.isCancelled,
    this.currentGenerationToken,
    this.diagnosticBookId,
    this.onDiagnostic,
  });

  final int generationToken;
  final FrameBudgetedRangeScheduler scheduler;
  final DisplayRangeTaskPriority priority;
  final bool Function() isCancelled;
  final int Function()? currentGenerationToken;
  final String? diagnosticBookId;
  final ReaderCardPaginatorDiagnostic? onDiagnostic;
}

/// Immutable canonical pagination request.
///
/// Canonical identity is deliberately separate from scheduler, generation,
/// cancellation and diagnostic controls. No display/window/controller index
/// can be supplied as restart or target authority.
@immutable
final class CanonicalPaginationRequest {
  const CanonicalPaginationRequest({
    required this.bookId,
    required this.publicationFingerprint,
    required this.sourceSnapshot,
    required this.controlledLayoutIdentity,
    required this.layout,
    required this.restart,
    required this.workBudget,
    required this.operation,
    this.paginationAlgorithmIdentity = readerPaginationAlgorithmVersion,
    this.target,
    this.continuationParent,
    this.sectionInput,
  });

  final String bookId;
  final String publicationFingerprint;
  final CanonicalPaginationSourceSnapshot sourceSnapshot;
  final String paginationAlgorithmIdentity;
  final String controlledLayoutIdentity;
  final ReaderCardPaginatorLayout layout;
  final CanonicalPaginationRestart restart;
  final CanonicalPaginationTargetCursor? target;

  /// Required for a non-root continuation so its parent link can be proved.
  final CanonicalPaginationContinuation? continuationParent;
  final CanonicalPaginationWorkBudget workBudget;
  final LazySectionInput? sectionInput;
  final CanonicalPaginationOperationControls operation;
}

sealed class CanonicalReaderPaginationPathResult {
  const CanonicalReaderPaginationPathResult();

  List<CanonicalFinalizedReaderCard> get publishableCards => const [];
  CanonicalPaginationContinuation? get acceptedContinuation => null;
  bool get hasAcceptedRestartAuthority => false;
  bool get hasCacheWriteAuthority => false;
}

final class CanonicalReaderInputExhausted
    extends CanonicalReaderPaginationPathResult {
  CanonicalReaderInputExhausted(
    List<CanonicalFinalizedReaderCard> cards,
    this.diagnostics,
  ) : publishableCards = List.unmodifiable(cards);
  @override
  final List<CanonicalFinalizedReaderCard> publishableCards;
  final CanonicalPaginationWorkDiagnostics diagnostics;
}

sealed class CanonicalReaderPaginationPathAccepted
    extends CanonicalReaderPaginationPathResult {
  CanonicalReaderPaginationPathAccepted({
    required List<CanonicalFinalizedReaderCard> publishableCards,
    required this.continuation,
    required this.diagnostics,
    required this.boundedWorkEntriesConsumed,
    required this.privatePredecessorCardsDiscarded,
    required this.usedEarlierCheckpointRecovery,
    this.targetContainment,
  }) : _publishableCards = List.unmodifiable(publishableCards);

  final List<CanonicalFinalizedReaderCard> _publishableCards;
  final CanonicalPaginationContinuation continuation;
  final CanonicalPaginationWorkDiagnostics diagnostics;
  final int boundedWorkEntriesConsumed;
  final int privatePredecessorCardsDiscarded;
  final bool usedEarlierCheckpointRecovery;
  final CanonicalPaginationTargetContainmentEvidence? targetContainment;

  @override
  List<CanonicalFinalizedReaderCard> get publishableCards => _publishableCards;

  @override
  CanonicalPaginationContinuation get acceptedContinuation => continuation;

  @override
  bool get hasAcceptedRestartAuthority => true;

  @override
  bool get hasCacheWriteAuthority => true;
}

final class CanonicalReaderFinalizedOutput
    extends CanonicalReaderPaginationPathAccepted {
  CanonicalReaderFinalizedOutput({
    required super.publishableCards,
    required super.continuation,
    required super.diagnostics,
    required super.boundedWorkEntriesConsumed,
    required super.privatePredecessorCardsDiscarded,
    required super.usedEarlierCheckpointRecovery,
    super.targetContainment,
  });
}

final class CanonicalReaderLogicalEnd
    extends CanonicalReaderPaginationPathAccepted {
  CanonicalReaderLogicalEnd({
    required super.publishableCards,
    required super.continuation,
    required super.diagnostics,
    required super.boundedWorkEntriesConsumed,
    required super.privatePredecessorCardsDiscarded,
    required super.usedEarlierCheckpointRecovery,
    super.targetContainment,
  });
}

final class CanonicalReaderProvisionalBudgetExhaustion
    extends CanonicalReaderPaginationPathAccepted {
  CanonicalReaderProvisionalBudgetExhaustion({
    required super.publishableCards,
    required super.continuation,
    required super.diagnostics,
    required super.boundedWorkEntriesConsumed,
    required super.privatePredecessorCardsDiscarded,
    required super.usedEarlierCheckpointRecovery,
  });
}

final class CanonicalReaderRequiredEarlierRestart
    extends CanonicalReaderPaginationPathResult {
  const CanonicalReaderRequiredEarlierRestart(this.message);

  final String message;
}

final class CanonicalReaderPaginationPathRejected
    extends CanonicalReaderPaginationPathResult {
  const CanonicalReaderPaginationPathRejected(this.rejection);

  final CanonicalPaginationRejectedResult rejection;
}

enum CanonicalReaderBackwardRejectionReason {
  invalidDesiredPredecessor,
  invalidPublishedPrefix,
  committedIdentityMismatch,
  committedSourceSliceMismatch,
  committedSectionSpineMismatch,
  cursorDiscontinuity,
  incompatibleRegeneration,
  cancelled,
  staleGeneration,
}

/// A fully validated forward-regeneration result whose only publishable cards
/// are the canonical cards preceding the already published prefix.
final class CanonicalReaderBackwardPreparationAccepted
    extends CanonicalReaderPaginationPathAccepted {
  CanonicalReaderBackwardPreparationAccepted({
    required super.publishableCards,
    required super.continuation,
    required super.diagnostics,
    required super.boundedWorkEntriesConsumed,
    required super.privatePredecessorCardsDiscarded,
    required super.usedEarlierCheckpointRecovery,
    required this.regeneratedCommittedCard,
    required this.regeneratedPublishedPrefix,
    required this.previousCard,
    required this.successorCard,
    required this.predecessorEndCursor,
    required this.currentStartCursor,
    required this.currentEndCursor,
    required this.successorStartCursor,
    required this.restartDescription,
  });

  final CanonicalFinalizedReaderCard regeneratedCommittedCard;
  final CanonicalFinalizedReaderCard regeneratedPublishedPrefix;
  final CanonicalFinalizedReaderCard? previousCard;
  final CanonicalFinalizedReaderCard? successorCard;
  final CanonicalPaginationCursor predecessorEndCursor;
  final CanonicalPaginationCursor currentStartCursor;
  final CanonicalPaginationCursor currentEndCursor;
  final CanonicalPaginationCursor successorStartCursor;
  final String restartDescription;
}

/// A bounded recovery continuation. No privately regenerated predecessor is
/// publishable until a later attempt reproduces the committed boundary.
final class CanonicalReaderBackwardPreparationPending
    extends CanonicalReaderPaginationPathResult {
  const CanonicalReaderBackwardPreparationPending({
    required this.continuation,
    required this.diagnostics,
    required this.boundedWorkEntriesConsumed,
    required this.usedEarlierCheckpointRecovery,
    required this.message,
  });

  final CanonicalPaginationContinuation continuation;
  final CanonicalPaginationWorkDiagnostics diagnostics;
  final int boundedWorkEntriesConsumed;
  final bool usedEarlierCheckpointRecovery;
  final String message;
}

/// Typed all-or-nothing backward rejection. Inherited authority getters expose
/// no cards, accepted restart, or cache-write permission.
final class CanonicalReaderBackwardPreparationRejected
    extends CanonicalReaderPaginationPathResult {
  const CanonicalReaderBackwardPreparationRejected({
    required this.reason,
    required this.message,
    this.diagnostics = const CanonicalPaginationWorkDiagnostics(),
  });

  final CanonicalReaderBackwardRejectionReason reason;
  final String message;
  final CanonicalPaginationWorkDiagnostics diagnostics;
}

/// Process-local orchestration for one immutable publication/source/layout
/// generation. It selects restarts and consumes the sole production paginator;
/// it contains no split, merge, rebalance, or finalization logic.
final class CanonicalReaderPaginationSession {
  CanonicalReaderPaginationSession({
    required this.sourceSnapshot,
    required this.controlledLayoutIdentity,
    required this.layout,
    this.paginator = const ReaderCardPaginator(),
    this.deferPublicationCommit = false,
    this.sectionInput,
  }) : _checkpointIndex = CanonicalPaginationCheckpointIndex(
         bookId: sourceSnapshot.bookId,
         publicationFingerprint: sourceSnapshot.publicationFingerprint,
         parserSourceIdentity: sourceSnapshot.parserSourceIdentity,
         sourceRevision: sourceSnapshot.sourceRevision,
         sourceSnapshotDigest: sourceSnapshot.snapshotDigest,
         paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
         controlledLayoutIdentity: controlledLayoutIdentity,
       );

  final CanonicalPaginationSourceSnapshot sourceSnapshot;
  final String controlledLayoutIdentity;
  final ReaderCardPaginatorLayout layout;
  final ReaderCardPaginator paginator;
  final bool deferPublicationCommit;
  final LazySectionInput? sectionInput;
  bool _inputExhausted = false;
  bool get inputExhaustedAwaitingSuccessor => _inputExhausted;
  CanonicalPaginationCheckpointIndex _checkpointIndex;
  CanonicalPaginationContinuation? _acceptedSuffix;
  CanonicalFinalizedReaderCard? _acceptedPublishedSuffixCard;
  final List<CanonicalFinalizedReaderCard> _acceptedPublishedCards =
      <CanonicalFinalizedReaderCard>[];
  final Map<int, _CanonicalSessionState> _pendingPublicationStates =
      <int, _CanonicalSessionState>{};

  final Object _sessionBranchIdentity = Object();
  Object? _forwardForkParentIdentity;

  /// Private forward preparation shares immutable cards/source but owns its
  /// checkpoint/frontier state. It cannot mutate the accepted reader session.
  CanonicalReaderPaginationSession forkForForward() {
    if (_inputExhausted ||
        _acceptedSuffix == null ||
        _acceptedSuffix!.terminal ||
        _pendingPublicationStates.isNotEmpty) {
      throw StateError('An exact live nonterminal suffix is required');
    }
    final branch = CanonicalReaderPaginationSession(
      sourceSnapshot: sourceSnapshot,
      controlledLayoutIdentity: controlledLayoutIdentity,
      layout: layout,
      paginator: paginator,
      sectionInput: sectionInput,
    );
    // The existing validated checkpoint fork keeps the exact suffix and its
    // parent, without retaining every earlier two-card request checkpoint.
    final checkpointBranch = _checkpointIndex.forkAt(_acceptedSuffix!);
    if (!checkpointBranch.accepted) {
      throw StateError(checkpointBranch.rejection!.message);
    }
    branch._checkpointIndex = checkpointBranch.index!;
    branch._acceptedSuffix = _acceptedSuffix;
    branch._acceptedPublishedSuffixCard = _acceptedPublishedSuffixCard;
    branch._acceptedPublishedCards.addAll(_acceptedPublishedCards);
    branch._forwardForkParentIdentity = _sessionBranchIdentity;
    return branch;
  }

  bool isForwardForkOf(CanonicalReaderPaginationSession accepted) =>
      identical(_forwardForkParentIdentity, accepted._sessionBranchIdentity);

  CanonicalPaginationCheckpointIndex get checkpointIndex => _checkpointIndex;
  CanonicalPaginationContinuation? get acceptedSuffix => _acceptedSuffix;

  List<CanonicalFinalizedReaderCard> get acceptedPublishedCards =>
      List<CanonicalFinalizedReaderCard>.unmodifiable(_acceptedPublishedCards);

  /// Resolves a mutable display lookup back to immutable canonical evidence.
  /// The display card and ordinals are hints only; the returned accepted card
  /// is the authority used by backward preparation.
  CanonicalFinalizedReaderCard? acceptedPublishedCard({
    required BookChunk card,
    required List<int> sourceOrdinals,
  }) {
    final normalizedOrdinals = sourceOrdinals.toSet().toList(growable: false);
    for (final accepted in _acceptedPublishedCards) {
      final acceptedOrdinals = accepted.sourceSlices
          .map((slice) => slice.sourceOrdinalHint)
          .toSet()
          .toList(growable: false);
      if (canonicalJsonEncode(card.toJson()) ==
              canonicalJsonEncode(accepted.card.toJson()) &&
          canonicalJsonEncode(normalizedOrdinals) ==
              canonicalJsonEncode(acceptedOrdinals)) {
        return accepted;
      }
    }
    return null;
  }

  CanonicalPaginationCursor? acceptedSuccessorStartCursorFor(
    CanonicalFinalizedReaderCard card,
  ) {
    final index = _acceptedPublishedCards.indexWhere(
      (accepted) => _sameFinalizedCard(accepted, card),
    );
    if (index < 0) return null;
    if (index + 1 < _acceptedPublishedCards.length) {
      return _cardStartCursor(_acceptedPublishedCards[index + 1]);
    }
    final suffixBoundary = _acceptedSuffix?.previousFinalizedBoundary;
    if (suffixBoundary == null ||
        canonicalJsonEncode(suffixBoundary.cardIdentity?.toJson()) !=
            canonicalJsonEncode(card.identity.toJson())) {
      return null;
    }
    return suffixBoundary.endCursor;
  }

  CanonicalPaginationFinalizedBoundary? publishedSuffixBoundary({
    required BookChunk card,
    required List<int> sourceOrdinals,
  }) {
    final accepted = _acceptedSuffix?.previousFinalizedBoundary;
    final expectedCard = _acceptedPublishedSuffixCard;
    if (accepted == null || expectedCard == null) return null;
    final expectedOrdinals = expectedCard.sourceSlices
        .map((slice) => slice.sourceOrdinalHint)
        .toSet()
        .toList(growable: false);
    if (canonicalJsonEncode(card.toJson()) !=
            canonicalJsonEncode(expectedCard.card.toJson()) ||
        canonicalJsonEncode(sourceOrdinals) !=
            canonicalJsonEncode(expectedOrdinals)) {
      return null;
    }
    return CanonicalPaginationFinalizedBoundary(
      kind: accepted.kind,
      endCursor: accepted.endCursor,
      cardIdentity: expectedCard.identity,
    );
  }

  CanonicalPaginationTargetCursor targetForStableOwner({
    required String sourceIdentity,
    required String sectionIdentity,
    required int sourceOrdinalHint,
    required int textOffsetUtf16,
  }) {
    final ordinal = sourceSnapshot.resolveOrdinal(
      sourceIdentity: sourceIdentity,
      ordinalHint: sourceOrdinalHint,
    );
    if (ordinal == null ||
        sourceSnapshot.ownerAt(ordinal).sectionIdentity != sectionIdentity) {
      throw ArgumentError('Stable target owner does not resolve in snapshot.');
    }
    final source = sourceSnapshot.resolveOrdinalSource(ordinal);
    final extent = source.type == BookChunkType.text
        ? (source.text?.length ?? 0)
        : 1;
    if (textOffsetUtf16 < 0 || textOffsetUtf16 >= math.max(1, extent)) {
      throw RangeError.range(
        textOffsetUtf16,
        0,
        math.max(0, extent - 1),
        'textOffsetUtf16',
      );
    }
    return CanonicalPaginationTargetCursor(
      sourceIdentity: sourceIdentity,
      sectionIdentity: sectionIdentity,
      sourceOrdinalHint: ordinal,
      textOffsetUtf16: textOffsetUtf16,
    );
  }

  Future<CanonicalReaderPaginationPathResult> generateInitial({
    required CanonicalPaginationRestart restart,
    required CanonicalPaginationOperationControls operation,
    CanonicalPaginationWorkBudget budget =
        const CanonicalPaginationWorkBudget(),
  }) => _runWithDeferredPublication(
    () => _generateInitialInternal(
      restart: restart,
      operation: operation,
      budget: budget,
    ),
  );

  Future<CanonicalReaderPaginationPathResult> _generateInitialInternal({
    required CanonicalPaginationRestart restart,
    required CanonicalPaginationOperationControls operation,
    CanonicalPaginationWorkBudget budget =
        const CanonicalPaginationWorkBudget(),
  }) async {
    final result = await _paginateOnce(
      restart: restart,
      continuationParent:
          restart is CanonicalPaginationContinuation && restart.chainOrdinal > 0
          ? _checkpointIndex.parentOf(restart)
          : null,
      operation: operation,
      budget: budget,
    );
    return _acceptSingle(
      result,
      operation: operation,
      replacePublishedCards: restart is! CanonicalPaginationContinuation,
    );
  }

  Future<CanonicalReaderPaginationPathResult> generateTarget({
    required CanonicalPaginationTargetCursor target,
    required CanonicalPaginationOperationControls operation,
  }) => _runWithDeferredPublication(
    () => _generateTargetInternal(target: target, operation: operation),
  );

  Future<CanonicalReaderPaginationPathResult> _generateTargetInternal({
    required CanonicalPaginationTargetCursor target,
    required CanonicalPaginationOperationControls operation,
  }) async {
    if (sectionInput != null) {
      return const CanonicalReaderRequiredEarlierRestart(
        'Lazy handoff sessions start at their verified section root.',
      );
    }
    final resolved = sourceSnapshot.resolveOrdinal(
      sourceIdentity: target.sourceIdentity,
      ordinalHint: target.sourceOrdinalHint,
    );
    if (resolved == null ||
        sourceSnapshot.ownerAt(resolved).sectionIdentity !=
            target.sectionIdentity) {
      return const CanonicalReaderPaginationPathRejected(
        CanonicalInvalidRestartSourceRejected(
          diagnostics: CanonicalPaginationWorkDiagnostics(),
          reason: CanonicalPaginationRejectionReason.invalidTarget,
          message: 'Stable target owner is absent from the pinned snapshot.',
        ),
      );
    }

    final candidates = _checkpointIndex.predecessorsAtOrBefore(target);
    CanonicalPaginationRestart restart;
    CanonicalPaginationContinuation? parent;
    CanonicalPaginationCheckpointIndex branch;
    var recovery = false;
    if (candidates.isEmpty) {
      final sectionStart = _trustedSectionStartFor(target.sourceOrdinalHint);
      restart = sectionStart ?? const CanonicalPaginationPublicationStart();
      branch = _emptyIndex();
    } else {
      CanonicalPaginationCheckpointBranch? selected;
      for (var index = 0; index < candidates.length; index++) {
        final attempted = _checkpointIndex.forkAt(candidates[index]);
        if (attempted.accepted) {
          selected = attempted;
          recovery = index == 1;
          break;
        }
      }
      if (selected == null) {
        return const CanonicalReaderRequiredEarlierRestart(
          'The nearest checkpoint and its single approved predecessor are unavailable.',
        );
      }
      branch = selected.index!;
      restart = branch.activeFrontier!;
      parent = selected.parent;
    }

    var envelope = recovery
        ? CanonicalPaginationWorkEnvelope.recovery
        : CanonicalPaginationWorkEnvelope.normal;
    var atomicLimit = envelope.maxEntries;
    var privateCardLimit = recovery ? 15 : 7;
    var atomicUsed = 0;
    var privateCards = 0;
    while (atomicUsed < atomicLimit) {
      final result = await _paginateOnce(
        restart: restart,
        continuationParent: parent,
        target: target,
        operation: operation,
        budget: CanonicalPaginationWorkBudget(
          maxAtomicFragments: atomicLimit - atomicUsed,
          envelope: envelope,
        ),
      );
      if (result is CanonicalPaginationRejectedResult) {
        if (!recovery && candidates.length > 1) {
          final recovered = _checkpointIndex.forkAt(candidates[1]);
          if (recovered.accepted) {
            recovery = true;
            envelope = CanonicalPaginationWorkEnvelope.recovery;
            atomicLimit = envelope.maxEntries;
            privateCardLimit = 15;
            branch = recovered.index!;
            restart = branch.activeFrontier!;
            parent = recovered.parent;
            atomicUsed = 0;
            privateCards = 0;
            continue;
          }
        }
        return CanonicalReaderPaginationPathRejected(result);
      }
      if (!_operationIsCurrent(operation)) {
        return CanonicalReaderPaginationPathRejected(
          _staleRejection(operation),
        );
      }
      final accepted = result as CanonicalPaginationAcceptedResult;
      final insertion = branch.insert(accepted);
      if (insertion is CanonicalPaginationContinuationRejected) {
        return CanonicalReaderPaginationPathRejected(
          CanonicalInvalidRestartSourceRejected(
            diagnostics: accepted.diagnostics,
            reason: _mapContinuationRejection(insertion.kind),
            message: insertion.message,
          ),
        );
      }
      atomicUsed += accepted.diagnostics.atomicFragmentsProcessed;
      if (accepted is CanonicalTargetFinalized) {
        final targetCardIndex = accepted.finalizedCards.indexWhere(
          (card) =>
              card.identity.signature == accepted.targetCard.identity.signature,
        );
        privateCards += targetCardIndex;
        if (privateCards > privateCardLimit) {
          return const CanonicalReaderRequiredEarlierRestart(
            'Target predecessor-card discard bound was exceeded.',
          );
        }
        final targetOutput = accepted.finalizedCards
            .skip(targetCardIndex)
            .toList(growable: false);
        _checkpointIndex = branch;
        _acceptedSuffix = accepted.continuation;
        _acceptedPublishedSuffixCard = targetOutput.last;
        _acceptedPublishedCards
          ..clear()
          ..addAll(targetOutput);
        if (accepted.continuation.terminal) {
          return CanonicalReaderLogicalEnd(
            publishableCards: targetOutput,
            continuation: accepted.continuation,
            diagnostics: accepted.diagnostics,
            boundedWorkEntriesConsumed: atomicUsed,
            privatePredecessorCardsDiscarded: privateCards,
            usedEarlierCheckpointRecovery: recovery,
            targetContainment: accepted.containmentEvidence,
          );
        }
        return CanonicalReaderFinalizedOutput(
          publishableCards: targetOutput,
          continuation: accepted.continuation,
          diagnostics: accepted.diagnostics,
          boundedWorkEntriesConsumed: atomicUsed,
          privatePredecessorCardsDiscarded: privateCards,
          usedEarlierCheckpointRecovery: recovery,
          targetContainment: accepted.containmentEvidence,
        );
      }
      privateCards += accepted.finalizedCards.length;
      if (privateCards > privateCardLimit) {
        return const CanonicalReaderRequiredEarlierRestart(
          'Target predecessor-card discard bound was exceeded.',
        );
      }
      restart = accepted.continuation;
      parent = accepted.continuation.chainOrdinal == 0
          ? null
          : branch.parentOf(accepted.continuation);
      if (accepted is CanonicalLogicalEndReached) {
        return const CanonicalReaderRequiredEarlierRestart(
          'Logical end was reached without finalizing the stable target.',
        );
      }
      if (accepted is CanonicalBudgetExhaustedWithFrontier) {
        if (atomicUsed >= atomicLimit) {
          return const CanonicalReaderRequiredEarlierRestart(
            'Target work envelope ended with a provisional frontier.',
          );
        }
        continue;
      }
      if (atomicUsed >= atomicLimit) {
        return const CanonicalReaderRequiredEarlierRestart(
          'Target work envelope ended before exact containment.',
        );
      }
    }
    return const CanonicalReaderRequiredEarlierRestart(
      'Target work envelope ended before canonical finalization.',
    );
  }

  Future<CanonicalReaderPaginationPathResult> generateForward({
    required CanonicalPaginationFinalizedBoundary acceptedPublishedSuffix,
    required CanonicalPaginationOperationControls operation,
    CanonicalPaginationWorkBudget budget =
        const CanonicalPaginationWorkBudget(),
  }) => _runWithDeferredPublication(
    () => _generateForwardInternal(
      acceptedPublishedSuffix: acceptedPublishedSuffix,
      operation: operation,
      budget: budget,
    ),
  );

  Future<CanonicalReaderPaginationPathResult> _generateForwardInternal({
    required CanonicalPaginationFinalizedBoundary acceptedPublishedSuffix,
    required CanonicalPaginationOperationControls operation,
    CanonicalPaginationWorkBudget budget =
        const CanonicalPaginationWorkBudget(),
  }) async {
    if (_inputExhausted) {
      return const CanonicalReaderRequiredEarlierRestart(
        'Sealed input requires a dedicated snapshot handoff.',
      );
    }
    final restart = _acceptedSuffix;
    if (restart == null ||
        !_sameBoundary(
          restart.previousFinalizedBoundary,
          acceptedPublishedSuffix,
        )) {
      return const CanonicalReaderPaginationPathRejected(
        CanonicalInvalidRestartSourceRejected(
          diagnostics: CanonicalPaginationWorkDiagnostics(),
          reason: CanonicalPaginationRejectionReason.invalidRestart,
          message:
              'Accepted published suffix does not match the canonical continuation boundary.',
        ),
      );
    }
    final parent = restart.chainOrdinal == 0
        ? null
        : _checkpointIndex.parentOf(restart);
    if (restart.chainOrdinal > 0 && parent == null) {
      return const CanonicalReaderRequiredEarlierRestart(
        'The exact accepted suffix parent is no longer resident.',
      );
    }
    final result = await _paginateOnce(
      restart: restart,
      continuationParent: parent,
      operation: operation,
      budget: budget,
    );
    return _acceptSingle(result, operation: operation);
  }

  /// Regenerates a bounded predecessor window strictly in forward source
  /// order and exposes no card until the already published prefix and exact
  /// committed card have both been reproduced.
  Future<CanonicalReaderPaginationPathResult> generateBackward({
    required CanonicalPaginationTargetCursor desiredPredecessor,
    required CanonicalFinalizedReaderCard acceptedPublishedPrefix,
    required CanonicalFinalizedReaderCard committedCurrentCard,
    required CanonicalPaginationCursor acceptedSuccessorStartCursor,
    required CanonicalPaginationOperationControls operation,
  }) => _runWithDeferredPublication(
    () => _generateBackwardInternal(
      desiredPredecessor: desiredPredecessor,
      acceptedPublishedPrefix: acceptedPublishedPrefix,
      committedCurrentCard: committedCurrentCard,
      acceptedSuccessorStartCursor: acceptedSuccessorStartCursor,
      operation: operation,
    ),
  );

  Future<CanonicalReaderPaginationPathResult> _generateBackwardInternal({
    required CanonicalPaginationTargetCursor desiredPredecessor,
    required CanonicalFinalizedReaderCard acceptedPublishedPrefix,
    required CanonicalFinalizedReaderCard committedCurrentCard,
    required CanonicalPaginationCursor acceptedSuccessorStartCursor,
    required CanonicalPaginationOperationControls operation,
  }) async {
    if (sectionInput != null) {
      return const CanonicalReaderRequiredEarlierRestart(
        'Lazy backward transfer is not implemented',
      );
    }
    final desiredOrdinal = sourceSnapshot.resolveOrdinal(
      sourceIdentity: desiredPredecessor.sourceIdentity,
      ordinalHint: desiredPredecessor.sourceOrdinalHint,
    );
    if (desiredOrdinal == null ||
        sourceSnapshot.ownerAt(desiredOrdinal).sectionIdentity !=
            desiredPredecessor.sectionIdentity) {
      return const CanonicalReaderBackwardPreparationRejected(
        reason:
            CanonicalReaderBackwardRejectionReason.invalidDesiredPredecessor,
        message:
            'Desired predecessor owner is absent from the pinned snapshot.',
      );
    }

    final prefixValidation = _validateAcceptedPublishedEvidence(
      acceptedPublishedPrefix,
      committed: false,
    );
    if (prefixValidation.rejection != null) {
      return prefixValidation.rejection!;
    }
    final currentValidation = _validateAcceptedPublishedEvidence(
      committedCurrentCard,
      committed: true,
    );
    if (currentValidation.rejection != null) {
      return currentValidation.rejection!;
    }
    final prefixIndex = prefixValidation.index!;
    final currentIndex = currentValidation.index!;
    if (prefixIndex > currentIndex) {
      return const CanonicalReaderBackwardPreparationRejected(
        reason: CanonicalReaderBackwardRejectionReason.invalidPublishedPrefix,
        message: 'Published prefix follows the committed current card.',
      );
    }
    final expectedPrefix = _acceptedPublishedCards[prefixIndex];
    final expectedCurrent = _acceptedPublishedCards[currentIndex];
    if (!_cardEndCursor(
      expectedCurrent,
    ).samePositionAs(acceptedSuccessorStartCursor)) {
      return const CanonicalReaderBackwardPreparationRejected(
        reason: CanonicalReaderBackwardRejectionReason.cursorDiscontinuity,
        message:
            'Accepted committed end/successor-continuation cursor differs.',
      );
    }
    final expectedPrefixStart = _cardStartCursor(expectedPrefix);
    if (_compareStableCursors(
          _targetCursorAsSourceCursor(desiredPredecessor),
          expectedPrefixStart,
        ) >=
        0) {
      return const CanonicalReaderBackwardPreparationRejected(
        reason:
            CanonicalReaderBackwardRejectionReason.invalidDesiredPredecessor,
        message:
            'Desired predecessor must be strictly before the published prefix.',
      );
    }

    final attempts = _backwardRestartAttempts(desiredPredecessor);
    if (attempts.isEmpty) {
      return const CanonicalReaderRequiredEarlierRestart(
        'No earlier canonical restart exists within the backward bound.',
      );
    }
    final currentLastOrdinal =
        expectedCurrent.sourceSlices.last.sourceOrdinalHint;
    final hasCheckpointRestart = attempts.any(
      (attempt) => attempt.restart is CanonicalPaginationContinuation,
    );
    if (!hasCheckpointRestart &&
        currentLastOrdinal - desiredPredecessor.sourceOrdinalHint >
            CanonicalPaginationBounds.recoveryWorkEnvelope) {
      return const CanonicalReaderRequiredEarlierRestart(
        'Publication or trusted section start is outside the approved backward bound.',
      );
    }
    CanonicalReaderPaginationPathResult? lastFailure;
    for (var attemptIndex = 0; attemptIndex < attempts.length; attemptIndex++) {
      if (!_operationIsCurrent(operation)) {
        return CanonicalReaderBackwardPreparationRejected(
          reason: operation.isCancelled()
              ? CanonicalReaderBackwardRejectionReason.cancelled
              : CanonicalReaderBackwardRejectionReason.staleGeneration,
          message: 'Backward preparation was cancelled before regeneration.',
        );
      }
      final attempt = attempts[attemptIndex];
      if (attempt.branch == null) {
        lastFailure = CanonicalReaderRequiredEarlierRestart(attempt.message!);
        continue;
      }
      final restartOrdinal = _restartSourceOrdinal(attempt.restart!);
      final requiresRecoveryRetention =
          attempt.restart is! CanonicalPaginationContinuation &&
          expectedPrefixStart.sourceOrdinalHint - restartOrdinal > 7;
      final outcome = await _regenerateBackwardAttempt(
        desiredPredecessor: desiredPredecessor,
        expectedPrefix: expectedPrefix,
        expectedCurrent: expectedCurrent,
        acceptedSuccessorStartCursor: acceptedSuccessorStartCursor,
        expectedPublishedThroughCurrent: _acceptedPublishedCards.sublist(
          prefixIndex,
          currentIndex + 1,
        ),
        attempt: attempt,
        operation: operation,
        recovery: attemptIndex == 1 || requiresRecoveryRetention,
      );
      if (outcome is CanonicalReaderBackwardPreparationAccepted) {
        _acceptedPublishedCards.insertAll(0, outcome.publishableCards);
        if (_acceptedPublishedCards.length >
            CanonicalPaginationBounds.activeCardCeiling) {
          _acceptedPublishedCards.removeRange(
            CanonicalPaginationBounds.activeCardCeiling,
            _acceptedPublishedCards.length,
          );
        }
        return outcome;
      }
      if (outcome is CanonicalReaderBackwardPreparationRejected &&
          (outcome.reason == CanonicalReaderBackwardRejectionReason.cancelled ||
              outcome.reason ==
                  CanonicalReaderBackwardRejectionReason.staleGeneration)) {
        return outcome;
      }
      lastFailure = outcome;
    }
    return lastFailure ??
        const CanonicalReaderRequiredEarlierRestart(
          'No earlier canonical restart reproduced the committed boundary.',
        );
  }

  Future<CanonicalReaderPaginationPathResult> _runWithDeferredPublication(
    Future<CanonicalReaderPaginationPathResult> Function() operation,
  ) async {
    if (sectionInput != null && deferPublicationCommit) {
      return const CanonicalReaderRequiredEarlierRestart(
        'Lazy sections are prepared in private successor sessions.',
      );
    }
    if (!deferPublicationCommit) return operation();
    final before = _captureSessionState();
    try {
      final result = await operation();
      final after = _captureSessionState();
      _restoreSessionState(before);
      if (result is CanonicalReaderPaginationPathAccepted &&
          result.publishableCards.isNotEmpty) {
        _pendingPublicationStates[identityHashCode(result)] = after;
      }
      return result;
    } on Object {
      _restoreSessionState(before);
      rethrow;
    }
  }

  bool hasPendingPublication(CanonicalReaderPaginationPathAccepted result) =>
      _pendingPublicationStates.containsKey(identityHashCode(result));

  bool commitPublication(CanonicalReaderPaginationPathAccepted result) {
    if (!deferPublicationCommit) return true;
    final state = _pendingPublicationStates.remove(identityHashCode(result));
    if (state == null) return false;
    _pendingPublicationStates.clear();
    _restoreSessionState(state);
    return true;
  }

  void rejectPublication(CanonicalReaderPaginationPathAccepted result) {
    _pendingPublicationStates.remove(identityHashCode(result));
  }

  _CanonicalSessionState _captureSessionState() => _CanonicalSessionState(
    checkpointIndex: _checkpointIndex.copy(),
    acceptedSuffix: _acceptedSuffix,
    acceptedPublishedSuffixCard: _acceptedPublishedSuffixCard,
    acceptedPublishedCards: List<CanonicalFinalizedReaderCard>.of(
      _acceptedPublishedCards,
    ),
  );

  void _restoreSessionState(_CanonicalSessionState state) {
    _checkpointIndex = state.checkpointIndex.copy();
    _acceptedSuffix = state.acceptedSuffix;
    _acceptedPublishedSuffixCard = state.acceptedPublishedSuffixCard;
    _acceptedPublishedCards
      ..clear()
      ..addAll(state.acceptedPublishedCards);
  }

  Future<CanonicalReaderPaginationPathResult> _regenerateBackwardAttempt({
    required CanonicalPaginationTargetCursor desiredPredecessor,
    required CanonicalFinalizedReaderCard expectedPrefix,
    required CanonicalFinalizedReaderCard expectedCurrent,
    required CanonicalPaginationCursor acceptedSuccessorStartCursor,
    required List<CanonicalFinalizedReaderCard> expectedPublishedThroughCurrent,
    required _CanonicalBackwardRestartAttempt attempt,
    required CanonicalPaginationOperationControls operation,
    required bool recovery,
  }) async {
    final atomicLimit = recovery
        ? CanonicalPaginationBounds.recoveryWorkEnvelope
        : CanonicalPaginationBounds.normalWorkEnvelope;
    final retainedLimit = recovery ? 15 : 7;
    final regeneratedCardLimit = recovery ? 18 : 10;
    var atomicUsed = 0;
    var restart = attempt.restart!;
    var parent = attempt.parent;
    final branch = attempt.branch!;
    final regenerated = <CanonicalFinalizedReaderCard>[];
    CanonicalPaginationWorkDiagnostics diagnostics =
        const CanonicalPaginationWorkDiagnostics();
    CanonicalPaginationContinuation? continuation;

    for (var operationCount = 0; operationCount < 64; operationCount++) {
      final result = await _paginateOnce(
        restart: restart,
        continuationParent: parent,
        operation: operation,
        budget: CanonicalPaginationWorkBudget(
          maxAtomicFragments: math.max(1, atomicLimit - atomicUsed),
          maxFinalizedCards: math.min(
            CanonicalPaginationBounds.checkpointCardStride,
            regeneratedCardLimit - regenerated.length,
          ),
          envelope: recovery
              ? CanonicalPaginationWorkEnvelope.recovery
              : CanonicalPaginationWorkEnvelope.normal,
        ),
      );
      if (result is CanonicalPaginationRejectedResult) {
        final reason = switch (result.reason) {
          CanonicalPaginationRejectionReason.cancelled =>
            CanonicalReaderBackwardRejectionReason.cancelled,
          CanonicalPaginationRejectionReason.staleGeneration =>
            CanonicalReaderBackwardRejectionReason.staleGeneration,
          _ => CanonicalReaderBackwardRejectionReason.incompatibleRegeneration,
        };
        return CanonicalReaderBackwardPreparationRejected(
          reason: reason,
          message: result.message,
          diagnostics: result.diagnostics,
        );
      }
      if (!_operationIsCurrent(operation)) {
        return CanonicalReaderBackwardPreparationRejected(
          reason: operation.isCancelled()
              ? CanonicalReaderBackwardRejectionReason.cancelled
              : CanonicalReaderBackwardRejectionReason.staleGeneration,
          message:
              'Backward result became cancelled or stale before validation.',
          diagnostics: diagnostics,
        );
      }
      final accepted = result as CanonicalPaginationAcceptedResult;
      final insertion = branch.insert(accepted);
      if (insertion is CanonicalPaginationContinuationRejected) {
        return CanonicalReaderBackwardPreparationRejected(
          reason:
              CanonicalReaderBackwardRejectionReason.incompatibleRegeneration,
          message: insertion.message,
          diagnostics: accepted.diagnostics,
        );
      }
      diagnostics = _addDiagnostics(diagnostics, accepted.diagnostics);
      atomicUsed += accepted.diagnostics.atomicFragmentsProcessed;
      continuation = accepted.continuation;
      for (final card in accepted.finalizedCards) {
        if (regenerated.isNotEmpty &&
            !_cardEndCursor(
              regenerated.last,
            ).samePositionAs(_cardStartCursor(card))) {
          return CanonicalReaderBackwardPreparationRejected(
            reason: CanonicalReaderBackwardRejectionReason.cursorDiscontinuity,
            message:
                'Regenerated canonical cards contain a cursor gap or overlap.',
            diagnostics: diagnostics,
          );
        }
        regenerated.add(card);
      }

      final currentAt = regenerated.indexWhere(
        (card) => _sameFinalizedCard(card, expectedCurrent),
      );
      if (currentAt >= 0) {
        final prefixAt = regenerated.indexWhere(
          (card) => _sameFinalizedCard(card, expectedPrefix),
        );
        if (prefixAt < 0 || prefixAt > currentAt) {
          return CanonicalReaderBackwardPreparationRejected(
            reason:
                CanonicalReaderBackwardRejectionReason.invalidPublishedPrefix,
            message:
                'Forward regeneration did not reproduce the published prefix.',
            diagnostics: diagnostics,
          );
        }
        final reproducedPublished = regenerated.sublist(
          prefixAt,
          currentAt + 1,
        );
        if (reproducedPublished.length !=
            expectedPublishedThroughCurrent.length) {
          return CanonicalReaderBackwardPreparationRejected(
            reason: CanonicalReaderBackwardRejectionReason.cursorDiscontinuity,
            message:
                'Regenerated published-card order differs before the current card.',
            diagnostics: diagnostics,
          );
        }
        for (var index = 0; index < reproducedPublished.length; index++) {
          if (!_sameFinalizedCard(
            reproducedPublished[index],
            expectedPublishedThroughCurrent[index],
          )) {
            return CanonicalReaderBackwardPreparationRejected(
              reason: CanonicalReaderBackwardRejectionReason
                  .committedSourceSliceMismatch,
              message:
                  'Regenerated published membership differs before the current card.',
              diagnostics: diagnostics,
            );
          }
        }

        final desiredCursor = _targetCursorAsSourceCursor(desiredPredecessor);
        var retainedStart = 0;
        while (retainedStart < prefixAt &&
            _compareStableCursors(
                  _cardEndCursor(regenerated[retainedStart]),
                  desiredCursor,
                ) <=
                0) {
          retainedStart++;
        }
        final predecessors = regenerated.sublist(retainedStart, prefixAt);
        if (predecessors.isEmpty || predecessors.length > retainedLimit) {
          return const CanonicalReaderRequiredEarlierRestart(
            'Canonical predecessor retention bound was exceeded or produced no predecessor.',
          );
        }
        final currentStart = _cardStartCursor(regenerated[currentAt]);
        final currentEnd = _cardEndCursor(regenerated[currentAt]);
        final previous = currentAt == 0 ? null : regenerated[currentAt - 1];
        final predecessorEnd = previous == null
            ? currentStart
            : _cardEndCursor(previous);
        if (!predecessorEnd.samePositionAs(currentStart)) {
          return CanonicalReaderBackwardPreparationRejected(
            reason: CanonicalReaderBackwardRejectionReason.cursorDiscontinuity,
            message: 'Predecessor end does not equal current start.',
            diagnostics: diagnostics,
          );
        }
        final successor = currentAt + 1 < regenerated.length
            ? regenerated[currentAt + 1]
            : null;
        final successorStart = successor == null
            ? accepted.continuation.previousFinalizedBoundary.endCursor
            : _cardStartCursor(successor);
        if (!currentEnd.samePositionAs(successorStart) ||
            !currentEnd.samePositionAs(acceptedSuccessorStartCursor) ||
            (successor == null &&
                canonicalJsonEncode(
                      accepted
                          .continuation
                          .previousFinalizedBoundary
                          .cardIdentity
                          ?.toJson(),
                    ) !=
                    canonicalJsonEncode(
                      regenerated[currentAt].identity.toJson(),
                    ))) {
          return CanonicalReaderBackwardPreparationRejected(
            reason: CanonicalReaderBackwardRejectionReason.cursorDiscontinuity,
            message:
                'Current end does not equal accepted successor-continuation start.',
            diagnostics: diagnostics,
          );
        }
        return CanonicalReaderBackwardPreparationAccepted(
          publishableCards: predecessors,
          continuation: accepted.continuation,
          diagnostics: diagnostics,
          boundedWorkEntriesConsumed: atomicUsed,
          privatePredecessorCardsDiscarded:
              retainedStart + reproducedPublished.length,
          usedEarlierCheckpointRecovery: recovery,
          regeneratedCommittedCard: regenerated[currentAt],
          regeneratedPublishedPrefix: regenerated[prefixAt],
          previousCard: previous,
          successorCard: successor,
          predecessorEndCursor: predecessorEnd,
          currentStartCursor: currentStart,
          currentEndCursor: currentEnd,
          successorStartCursor: successorStart,
          restartDescription: attempt.description,
        );
      }

      if (regenerated.length >= regeneratedCardLimit ||
          atomicUsed >= atomicLimit) {
        return CanonicalReaderBackwardPreparationPending(
          continuation: accepted.continuation,
          diagnostics: diagnostics,
          boundedWorkEntriesConsumed: atomicUsed,
          usedEarlierCheckpointRecovery: recovery,
          message:
              'Backward work bound ended before the committed card was reproduced.',
        );
      }
      if (accepted is CanonicalLogicalEndReached) {
        return CanonicalReaderBackwardPreparationRejected(
          reason:
              CanonicalReaderBackwardRejectionReason.incompatibleRegeneration,
          message:
              'Logical end was reached without reproducing the committed card.',
          diagnostics: diagnostics,
        );
      }
      restart = accepted.continuation;
      parent = accepted.continuation.chainOrdinal == 0
          ? null
          : branch.parentOf(accepted.continuation);
    }
    return CanonicalReaderBackwardPreparationPending(
      continuation: continuation!,
      diagnostics: diagnostics,
      boundedWorkEntriesConsumed: atomicUsed,
      usedEarlierCheckpointRecovery: recovery,
      message: 'Backward operation-count bound ended before validation.',
    );
  }

  ({int? index, CanonicalReaderBackwardPreparationRejected? rejection})
  _validateAcceptedPublishedEvidence(
    CanonicalFinalizedReaderCard supplied, {
    required bool committed,
  }) {
    final index = _acceptedPublishedCards.indexWhere(
      (card) =>
          canonicalJsonEncode(card.card.toJson()) ==
              canonicalJsonEncode(supplied.card.toJson()) ||
          card.identity.signature == supplied.identity.signature,
    );
    if (index < 0) {
      return (
        index: null,
        rejection: CanonicalReaderBackwardPreparationRejected(
          reason: committed
              ? CanonicalReaderBackwardRejectionReason.committedIdentityMismatch
              : CanonicalReaderBackwardRejectionReason.invalidPublishedPrefix,
          message: committed
              ? 'Committed card is not an accepted canonical published card.'
              : 'Published prefix is not accepted by this canonical session.',
        ),
      );
    }
    final expected = _acceptedPublishedCards[index];
    if (canonicalJsonEncode(expected.identity.toJson()) !=
        canonicalJsonEncode(supplied.identity.toJson())) {
      return (
        index: null,
        rejection: CanonicalReaderBackwardPreparationRejected(
          reason: committed
              ? CanonicalReaderBackwardRejectionReason.committedIdentityMismatch
              : CanonicalReaderBackwardRejectionReason.invalidPublishedPrefix,
          message: 'Published card identity or signature differs.',
        ),
      );
    }
    final expectedSlices = canonicalJsonEncode(
      expected.sourceSlices
          .map((slice) => slice.toCanonicalJson())
          .toList(growable: false),
    );
    final suppliedSlices = canonicalJsonEncode(
      supplied.sourceSlices
          .map((slice) => slice.toCanonicalJson())
          .toList(growable: false),
    );
    if (expectedSlices != suppliedSlices) {
      final sectionOrSpineMismatch =
          expected.sourceSlices.length == supplied.sourceSlices.length &&
          Iterable<int>.generate(expected.sourceSlices.length).any(
            (sliceIndex) =>
                expected.sourceSlices[sliceIndex].sectionIdentity !=
                    supplied.sourceSlices[sliceIndex].sectionIdentity ||
                expected.sourceSlices[sliceIndex].spineIdentity !=
                    supplied.sourceSlices[sliceIndex].spineIdentity,
          );
      return (
        index: null,
        rejection: CanonicalReaderBackwardPreparationRejected(
          reason: committed
              ? sectionOrSpineMismatch
                    ? CanonicalReaderBackwardRejectionReason
                          .committedSectionSpineMismatch
                    : CanonicalReaderBackwardRejectionReason
                          .committedSourceSliceMismatch
              : CanonicalReaderBackwardRejectionReason.invalidPublishedPrefix,
          message: sectionOrSpineMismatch
              ? 'Committed section/spine evidence differs.'
              : 'Committed ordered source-slice evidence differs.',
        ),
      );
    }
    if (canonicalJsonEncode(expected.card.toJson()) !=
        canonicalJsonEncode(supplied.card.toJson())) {
      return (
        index: null,
        rejection: CanonicalReaderBackwardPreparationRejected(
          reason: committed
              ? CanonicalReaderBackwardRejectionReason
                    .committedSourceSliceMismatch
              : CanonicalReaderBackwardRejectionReason.invalidPublishedPrefix,
          message: 'Committed visible content/card evidence differs.',
        ),
      );
    }
    return (index: index, rejection: null);
  }

  List<_CanonicalBackwardRestartAttempt> _backwardRestartAttempts(
    CanonicalPaginationTargetCursor desired,
  ) {
    final attempts = <_CanonicalBackwardRestartAttempt>[];
    final checkpoints = _checkpointIndex.predecessorsBefore(desired);
    for (final checkpoint in checkpoints) {
      if (attempts.length == 2) break;
      final fork = _checkpointIndex.forkAt(checkpoint);
      attempts.add(
        fork.accepted
            ? _CanonicalBackwardRestartAttempt(
                restart: fork.index!.activeFrontier,
                parent: fork.parent,
                branch: fork.index,
                description: 'checkpoint:${checkpoint.integrityDigest}',
              )
            : _CanonicalBackwardRestartAttempt.rejected(
                fork.rejection?.message ?? 'Checkpoint fork was rejected.',
              ),
      );
    }

    void addRoot(CanonicalPaginationRestart restart, String description) {
      if (attempts.length == 2) return;
      attempts.add(
        _CanonicalBackwardRestartAttempt(
          restart: restart,
          parent: null,
          branch: _emptyIndex(),
          description: description,
        ),
      );
    }

    final sectionStart = _trustedSectionStartFor(desired.sourceOrdinalHint);
    if (sectionStart != null) {
      if (sectionStart.sourceOrdinalHint == 0) {
        addRoot(const CanonicalPaginationPublicationStart(), 'publication');
      } else {
        addRoot(
          sectionStart,
          'trusted-section:${sectionStart.sectionIdentity}',
        );
        addRoot(const CanonicalPaginationPublicationStart(), 'publication');
      }
    } else if (desired.sourceOrdinalHint == 0) {
      addRoot(const CanonicalPaginationPublicationStart(), 'publication');
    }
    return List<_CanonicalBackwardRestartAttempt>.unmodifiable(attempts);
  }

  int _restartSourceOrdinal(CanonicalPaginationRestart restart) {
    if (restart is CanonicalPaginationContinuation) {
      return restart.nextSourceCursor.sourceOrdinalHint;
    }
    if (restart is CanonicalPaginationTrustedSectionStart) {
      return restart.sourceOrdinalHint;
    }
    return 0;
  }

  bool _sameFinalizedCard(
    CanonicalFinalizedReaderCard first,
    CanonicalFinalizedReaderCard second,
  ) =>
      canonicalJsonEncode(first.identity.toJson()) ==
          canonicalJsonEncode(second.identity.toJson()) &&
      canonicalJsonEncode(first.card.toJson()) ==
          canonicalJsonEncode(second.card.toJson()) &&
      canonicalJsonEncode(
            first.sourceSlices
                .map((slice) => slice.toCanonicalJson())
                .toList(growable: false),
          ) ==
          canonicalJsonEncode(
            second.sourceSlices
                .map((slice) => slice.toCanonicalJson())
                .toList(growable: false),
          );

  CanonicalPaginationCursor _targetCursorAsSourceCursor(
    CanonicalPaginationTargetCursor target,
  ) => CanonicalPaginationCursor(
    kind: target.textOffsetUtf16 == 0
        ? CanonicalPaginationCursorKind.wholeSource
        : CanonicalPaginationCursorKind.sourceText,
    sourceIdentity: target.sourceIdentity,
    sectionIdentity: target.sectionIdentity,
    sourceOrdinalHint: target.sourceOrdinalHint,
    textOffsetUtf16: target.textOffsetUtf16,
  );

  CanonicalPaginationCursor _cardStartCursor(
    CanonicalFinalizedReaderCard card,
  ) {
    final slice = card.sourceSlices.first;
    if (slice.tableRowStart != null) {
      return CanonicalPaginationCursor(
        kind: slice.tableRowStart == 0
            ? CanonicalPaginationCursorKind.wholeSource
            : CanonicalPaginationCursorKind.tableRow,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: slice.sourceOrdinalHint,
        tableRowIndex: slice.tableRowStart!,
      );
    }
    return CanonicalPaginationCursor(
      kind: (slice.startUtf16 ?? 0) == 0
          ? CanonicalPaginationCursorKind.wholeSource
          : CanonicalPaginationCursorKind.sourceText,
      sourceIdentity: slice.sourceIdentity,
      sectionIdentity: slice.sectionIdentity,
      sourceOrdinalHint: slice.sourceOrdinalHint,
      textOffsetUtf16: slice.startUtf16 ?? 0,
    );
  }

  CanonicalPaginationCursor _cardEndCursor(CanonicalFinalizedReaderCard card) {
    final slice = card.sourceSlices.last;
    final source = sourceSnapshot.resolveOrdinalSource(slice.sourceOrdinalHint);
    if (slice.tableRowEndExclusive != null) {
      final table = normalizedReaderTableFromText(source.text ?? '');
      if (table != null && slice.tableRowEndExclusive! < table.rows.length) {
        return CanonicalPaginationCursor(
          kind: CanonicalPaginationCursorKind.tableRow,
          sourceIdentity: slice.sourceIdentity,
          sectionIdentity: slice.sectionIdentity,
          sourceOrdinalHint: slice.sourceOrdinalHint,
          tableRowIndex: slice.tableRowEndExclusive!,
        );
      }
    } else if (slice.endUtf16 != null &&
        slice.endUtf16! < (source.text?.length ?? 0)) {
      return CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.sourceText,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: slice.sourceOrdinalHint,
        textOffsetUtf16: slice.endUtf16!,
      );
    }
    return slice.sourceOrdinalHint + 1 < sourceSnapshot.sourceCount
        ? _sourceStartCursor(slice.sourceOrdinalHint + 1)
        : const CanonicalPaginationCursor.logicalEnd();
  }

  CanonicalPaginationCursor _sourceStartCursor(int ordinal) {
    final owner = sourceSnapshot.ownerAt(ordinal);
    return CanonicalPaginationCursor(
      kind: CanonicalPaginationCursorKind.wholeSource,
      sourceIdentity: owner.sourceIdentity,
      sectionIdentity: owner.sectionIdentity,
      sourceOrdinalHint: ordinal,
    );
  }

  int _compareStableCursors(
    CanonicalPaginationCursor first,
    CanonicalPaginationCursor second,
  ) {
    if (first.isLogicalEnd) return second.isLogicalEnd ? 0 : 1;
    if (second.isLogicalEnd) return -1;
    var result = first.sourceOrdinalHint.compareTo(second.sourceOrdinalHint);
    if (result != 0) return result;
    result = first.tableRowIndex.compareTo(second.tableRowIndex);
    if (result != 0) return result;
    return first.textOffsetUtf16.compareTo(second.textOffsetUtf16);
  }

  CanonicalPaginationWorkDiagnostics _addDiagnostics(
    CanonicalPaginationWorkDiagnostics first,
    CanonicalPaginationWorkDiagnostics second,
  ) => CanonicalPaginationWorkDiagnostics(
    sourceChunksEntered: first.sourceChunksEntered + second.sourceChunksEntered,
    sourceChunksFullyConsumed:
        first.sourceChunksFullyConsumed + second.sourceChunksFullyConsumed,
    atomicFragmentsProcessed:
        first.atomicFragmentsProcessed + second.atomicFragmentsProcessed,
    referencedUtf16Extent:
        first.referencedUtf16Extent + second.referencedUtf16Extent,
    tableRows: first.tableRows + second.tableRows,
    graphemeCandidates: first.graphemeCandidates + second.graphemeCandidates,
    rebalanceCandidates: first.rebalanceCandidates + second.rebalanceCandidates,
    cardsFinalized: first.cardsFinalized + second.cardsFinalized,
    privatePredecessorCardsDiscarded:
        first.privatePredecessorCardsDiscarded +
        second.privatePredecessorCardsDiscarded,
    frontierEntries: second.frontierEntries,
    peakFrontierEntries: math.max(
      first.peakFrontierEntries,
      second.peakFrontierEntries,
    ),
    peakPrivateFrontierBytes: math.max(
      first.peakPrivateFrontierBytes,
      second.peakPrivateFrontierBytes,
    ),
    cancellationCheckpoints:
        first.cancellationCheckpoints + second.cancellationCheckpoints,
    schedulerSlices: first.schedulerSlices + second.schedulerSlices,
    schedulerYields: first.schedulerYields + second.schedulerYields,
  );

  CanonicalPaginationTrustedSectionStart? _trustedSectionStartFor(
    int targetOrdinal,
  ) {
    if (targetOrdinal < 0 || targetOrdinal >= sourceSnapshot.sourceCount) {
      return null;
    }
    final section = sourceSnapshot.ownerAt(targetOrdinal).sectionIdentity;
    var ordinal = targetOrdinal;
    while (ordinal > 0 &&
        sourceSnapshot.ownerAt(ordinal - 1).sectionIdentity == section) {
      ordinal--;
    }
    final owner = sourceSnapshot.ownerAt(ordinal);
    return sourceSnapshot.isTrustedSectionStart(ordinal, section)
        ? CanonicalPaginationTrustedSectionStart(
            sectionIdentity: section,
            sourceIdentity: owner.sourceIdentity,
            sourceOrdinalHint: ordinal,
          )
        : null;
  }

  Future<CanonicalPaginationResult> _paginateOnce({
    required CanonicalPaginationRestart restart,
    required CanonicalPaginationOperationControls operation,
    required CanonicalPaginationWorkBudget budget,
    CanonicalPaginationContinuation? continuationParent,
    CanonicalPaginationTargetCursor? target,
  }) => paginator.paginateCanonical(
    CanonicalPaginationRequest(
      bookId: sourceSnapshot.bookId,
      publicationFingerprint: sourceSnapshot.publicationFingerprint,
      sourceSnapshot: sourceSnapshot,
      controlledLayoutIdentity: controlledLayoutIdentity,
      layout: layout,
      sectionInput: sectionInput,
      restart: restart,
      continuationParent: continuationParent,
      target: target,
      workBudget: budget,
      operation: operation,
    ),
  );

  CanonicalReaderPaginationPathResult _acceptSingle(
    CanonicalPaginationResult result, {
    required CanonicalPaginationOperationControls operation,
    bool replacePublishedCards = false,
  }) {
    if (result is CanonicalPaginationRejectedResult) {
      return CanonicalReaderPaginationPathRejected(result);
    }
    if (!_operationIsCurrent(operation)) {
      return CanonicalReaderPaginationPathRejected(_staleRejection(operation));
    }
    if (result is CanonicalInputExhaustedAwaitingSuccessor) {
      if (replacePublishedCards) _acceptedPublishedCards.clear();
      _acceptedPublishedCards.addAll(result.finalizedCards);
      if (result.finalizedCards.isNotEmpty) {
        _acceptedPublishedSuffixCard = result.finalizedCards.last;
      }
      _inputExhausted = true;
      return CanonicalReaderInputExhausted(
        result.finalizedCards,
        result.diagnostics,
      );
    }
    final accepted = result as CanonicalPaginationAcceptedResult;
    final insertion = _checkpointIndex.insert(accepted);
    if (insertion is CanonicalPaginationContinuationRejected) {
      return CanonicalReaderPaginationPathRejected(
        CanonicalInvalidRestartSourceRejected(
          diagnostics: accepted.diagnostics,
          reason: _mapContinuationRejection(insertion.kind),
          message: insertion.message,
        ),
      );
    }
    _acceptedSuffix = accepted.continuation;
    if (accepted.finalizedCards.isNotEmpty) {
      _acceptedPublishedSuffixCard = accepted.finalizedCards.last;
      if (replacePublishedCards) {
        _acceptedPublishedCards.clear();
      }
      _acceptedPublishedCards.addAll(accepted.finalizedCards);
      if (_acceptedPublishedCards.length >
          CanonicalPaginationBounds.activeCardCeiling) {
        _acceptedPublishedCards.removeRange(
          0,
          _acceptedPublishedCards.length -
              CanonicalPaginationBounds.activeCardCeiling,
        );
      }
    }
    if (accepted is CanonicalLogicalEndReached) {
      return CanonicalReaderLogicalEnd(
        publishableCards: accepted.finalizedCards,
        continuation: accepted.continuation,
        diagnostics: accepted.diagnostics,
        boundedWorkEntriesConsumed:
            accepted.diagnostics.atomicFragmentsProcessed,
        privatePredecessorCardsDiscarded: 0,
        usedEarlierCheckpointRecovery: false,
      );
    }
    if (accepted is CanonicalBudgetExhaustedWithFrontier) {
      return CanonicalReaderProvisionalBudgetExhaustion(
        publishableCards: accepted.finalizedCards,
        continuation: accepted.continuation,
        diagnostics: accepted.diagnostics,
        boundedWorkEntriesConsumed:
            accepted.diagnostics.atomicFragmentsProcessed,
        privatePredecessorCardsDiscarded: 0,
        usedEarlierCheckpointRecovery: false,
      );
    }
    return CanonicalReaderFinalizedOutput(
      publishableCards: accepted.finalizedCards,
      continuation: accepted.continuation,
      diagnostics: accepted.diagnostics,
      boundedWorkEntriesConsumed: accepted.diagnostics.atomicFragmentsProcessed,
      privatePredecessorCardsDiscarded: 0,
      usedEarlierCheckpointRecovery: false,
      targetContainment: accepted is CanonicalTargetFinalized
          ? accepted.containmentEvidence
          : null,
    );
  }

  CanonicalPaginationCheckpointIndex _emptyIndex() =>
      CanonicalPaginationCheckpointIndex(
        bookId: sourceSnapshot.bookId,
        publicationFingerprint: sourceSnapshot.publicationFingerprint,
        parserSourceIdentity: sourceSnapshot.parserSourceIdentity,
        sourceRevision: sourceSnapshot.sourceRevision,
        sourceSnapshotDigest: sourceSnapshot.snapshotDigest,
        paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
        controlledLayoutIdentity: controlledLayoutIdentity,
      );

  bool _operationIsCurrent(CanonicalPaginationOperationControls operation) =>
      !operation.isCancelled() &&
      (operation.currentGenerationToken == null ||
          operation.currentGenerationToken!() == operation.generationToken);

  CanonicalCancelledStaleRejected _staleRejection(
    CanonicalPaginationOperationControls operation,
  ) => CanonicalCancelledStaleRejected(
    diagnostics: const CanonicalPaginationWorkDiagnostics(),
    reason: operation.isCancelled()
        ? CanonicalPaginationRejectionReason.cancelled
        : CanonicalPaginationRejectionReason.staleGeneration,
    message: 'Canonical result became cancelled or stale before acceptance.',
  );

  bool _sameBoundary(
    CanonicalPaginationFinalizedBoundary first,
    CanonicalPaginationFinalizedBoundary second,
  ) =>
      canonicalJsonEncode(first.toCanonicalJson()) ==
      canonicalJsonEncode(second.toCanonicalJson());

  CanonicalPaginationRejectionReason _mapContinuationRejection(
    CanonicalPaginationContinuationValidationKind kind,
  ) => switch (kind) {
    CanonicalPaginationContinuationValidationKind.requiredEarlierRestart =>
      CanonicalPaginationRejectionReason.requiredEarlierRestart,
    CanonicalPaginationContinuationValidationKind.incompatiblePublication =>
      CanonicalPaginationRejectionReason.incompatiblePublication,
    CanonicalPaginationContinuationValidationKind
        .incompatibleParserSourceSnapshot =>
      CanonicalPaginationRejectionReason.incompatibleParserSourceSnapshot,
    CanonicalPaginationContinuationValidationKind
        .incompatiblePaginationIdentity =>
      CanonicalPaginationRejectionReason.incompatiblePaginationIdentity,
    CanonicalPaginationContinuationValidationKind.incompatibleLayout =>
      CanonicalPaginationRejectionReason.incompatibleLayout,
    CanonicalPaginationContinuationValidationKind.boundViolation =>
      CanonicalPaginationRejectionReason.boundViolation,
    CanonicalPaginationContinuationValidationKind.corruptDigest =>
      CanonicalPaginationRejectionReason.corruptDigest,
    CanonicalPaginationContinuationValidationKind.unsupportedContractKind =>
      CanonicalPaginationRejectionReason.unsupportedContractKind,
    CanonicalPaginationContinuationValidationKind.invalidSectionSourceOwner =>
      CanonicalPaginationRejectionReason.invalidSectionSourceOwner,
    CanonicalPaginationContinuationValidationKind
        .invalidCursorOffsetRowInterval =>
      CanonicalPaginationRejectionReason.invalidCursorOffsetRowInterval,
    CanonicalPaginationContinuationValidationKind.invalidFrontier =>
      CanonicalPaginationRejectionReason.invalidFrontier,
    CanonicalPaginationContinuationValidationKind.brokenParentChain =>
      CanonicalPaginationRejectionReason.brokenParentChain,
    CanonicalPaginationContinuationValidationKind.ordinalMismatch =>
      CanonicalPaginationRejectionReason.ordinalMismatch,
    CanonicalPaginationContinuationValidationKind.staleForkReplay =>
      CanonicalPaginationRejectionReason.staleForkReplay,
    CanonicalPaginationContinuationValidationKind.terminalStateContradiction =>
      CanonicalPaginationRejectionReason.terminalStateContradiction,
    CanonicalPaginationContinuationValidationKind.accepted =>
      CanonicalPaginationRejectionReason.invalidRestart,
  };
}

final class _CanonicalSessionState {
  const _CanonicalSessionState({
    required this.checkpointIndex,
    required this.acceptedSuffix,
    required this.acceptedPublishedSuffixCard,
    required this.acceptedPublishedCards,
  });

  final CanonicalPaginationCheckpointIndex checkpointIndex;
  final CanonicalPaginationContinuation? acceptedSuffix;
  final CanonicalFinalizedReaderCard? acceptedPublishedSuffixCard;
  final List<CanonicalFinalizedReaderCard> acceptedPublishedCards;
}

bool _canonicalSliceContainsTarget(
  CanonicalPaginationSourceSlice slice,
  CanonicalPaginationTargetCursor target,
) {
  if (slice.sourceIdentity != target.sourceIdentity) return false;
  if (slice.startUtf16 != null) {
    return target.textOffsetUtf16 >= slice.startUtf16! &&
        target.textOffsetUtf16 < slice.endUtf16!;
  }
  if (slice.tableRowStart != null) {
    return target.textOffsetUtf16 == 0 && slice.tableRowStart == 0;
  }
  return target.textOffsetUtf16 == 0;
}

final class _CanonicalBackwardRestartAttempt {
  const _CanonicalBackwardRestartAttempt({
    required this.restart,
    required this.parent,
    required this.branch,
    required this.description,
  }) : message = null;

  const _CanonicalBackwardRestartAttempt.rejected(this.message)
    : restart = null,
      parent = null,
      branch = null,
      description = 'rejected-checkpoint';

  final CanonicalPaginationRestart? restart;
  final CanonicalPaginationContinuation? parent;
  final CanonicalPaginationCheckpointIndex? branch;
  final String description;
  final String? message;
}

DisplayRangeResult canonicalPathDisplayResult({
  required CanonicalReaderPaginationPathAccepted accepted,
  required DisplayRangeRequest request,
  required int publicationStart,
}) {
  final cards = accepted.publishableCards;
  final displayChunks = <BookChunk>[for (final card in cards) card.card];
  final displayToOriginal = <List<int>>[
    for (final card in cards)
      card.sourceSlices
          .map((slice) => slice.sourceOrdinalHint)
          .toSet()
          .toList(growable: false),
  ];
  final originalToDisplay = <int, int>{};
  for (
    var displayIndex = 0;
    displayIndex < displayToOriginal.length;
    displayIndex++
  ) {
    for (final sourceOrdinal in displayToOriginal[displayIndex]) {
      originalToDisplay[sourceOrdinal] = displayIndex;
    }
  }
  final sourceOrdinals = cards
      .expand((card) => card.sourceSlices)
      .map((slice) => slice.sourceOrdinalHint)
      .toList(growable: false);
  final effectiveStart = request.direction == DisplayRangeDirection.forward
      ? publicationStart
      : sourceOrdinals.isEmpty
      ? publicationStart
      : sourceOrdinals.reduce(math.min);
  final effectiveEnd = sourceOrdinals.isEmpty
      ? effectiveStart
      : math.max(publicationStart, sourceOrdinals.reduce(math.max) + 1);
  return DisplayRangeResult(
    request: DisplayRangeRequest(
      direction: request.direction,
      sourceRange: SourceChunkRange(effectiveStart, effectiveEnd),
      generationId: request.generationId,
      reason: request.reason,
      targetOriginalIndex: request.targetOriginalIndex,
      targetTextOffset: request.targetTextOffset,
    ),
    displayChunks: List<BookChunk>.unmodifiable(displayChunks),
    displayToOriginal: List<List<int>>.unmodifiable(displayToOriginal),
    originalToDisplay: Map<int, int>.unmodifiable(originalToDisplay),
    inspectedSourceChunks: accepted.diagnostics.sourceChunksEntered,
    elapsedMilliseconds: 0,
    sliceCount: accepted.diagnostics.schedulerSlices,
    yieldCount: accepted.diagnostics.schedulerYields,
    maxSourceChunksPerSlice: accepted.diagnostics.sourceChunksEntered,
    maxDisplayChunksPerSlice: accepted.diagnostics.cardsFinalized,
  );
}

enum _EngineTerminalPolicy { canonicalLogicalEndOnly, legacyRequestEnd }

enum _EngineStopKind {
  logicalEnd,
  sectionBoundary,
  legacyRequestEnd,
  budgetExhausted,
  targetFinalized,
  cancelled,
  stale,
  invalid,
  frontierBoundViolation,
}

final class _EngineRequest {
  const _EngineRequest({
    required this.snapshot,
    required this.layout,
    required this.scheduler,
    required this.priority,
    required this.isCancelled,
    required this.generationToken,
    required this.startCursor,
    required this.endSourceOrdinalExclusive,
    required this.terminalPolicy,
    required this.workBudget,
    required this.frontierEntryCap,
    required this.controlledLayoutIdentity,
    required this.paginationAlgorithmIdentity,
    required this.diagnosticBookId,
    this.currentGenerationToken,
    this.initialFrontier = const CanonicalPaginationFrontier(),
    this.target,
    this.legacyRangeRequest,
    this.legacyAnchor,
    this.onDiagnostic,
  });

  final CanonicalPaginationSourceSnapshot snapshot;
  final ReaderCardPaginatorLayout layout;
  final FrameBudgetedRangeScheduler scheduler;
  final DisplayRangeTaskPriority priority;
  final bool Function() isCancelled;
  final int generationToken;
  final int Function()? currentGenerationToken;
  final CanonicalPaginationCursor startCursor;
  final int endSourceOrdinalExclusive;
  final _EngineTerminalPolicy terminalPolicy;
  final CanonicalPaginationWorkBudget workBudget;
  final int frontierEntryCap;
  final String controlledLayoutIdentity;
  final String paginationAlgorithmIdentity;
  final String diagnosticBookId;
  final CanonicalPaginationFrontier initialFrontier;
  final CanonicalPaginationTargetCursor? target;
  final DisplayRangeRequest? legacyRangeRequest;
  final ReaderCardPaginatorAnchor? legacyAnchor;
  final ReaderCardPaginatorDiagnostic? onDiagnostic;
}

final class _EngineCandidate {
  const _EngineCandidate({
    required this.chunk,
    required this.originals,
    required this.descriptor,
  });

  final BookChunk chunk;
  final List<int> originals;
  final CanonicalPaginationFrontierCandidate descriptor;
}

final class _EngineFinalizedCard {
  const _EngineFinalizedCard({
    required this.chunk,
    required this.originals,
    required this.descriptor,
    this.resolvedLayout,
  });

  final BookChunk chunk;
  final List<int> originals;
  final CanonicalPaginationFrontierCandidate descriptor;
  final ResolvedReaderCardLayout? resolvedLayout;
}

final class _EngineRunResult {
  const _EngineRunResult({
    required this.kind,
    required this.finalizedCards,
    required this.frontier,
    required this.nextCursor,
    required this.diagnostics,
    required this.elapsedMilliseconds,
    required this.sliceCount,
    required this.yieldCount,
    required this.longestWorkIntervalMilliseconds,
    required this.maxSliceDurationMilliseconds,
    required this.totalYieldMilliseconds,
    required this.maxSourceChunksPerSlice,
    required this.maxDisplayChunksPerSlice,
    required this.inspectedSourceChunks,
    required this.consumedEndExclusive,
    this.cancellationLatencyMilliseconds,
    this.message,
  });

  final _EngineStopKind kind;
  final List<_EngineFinalizedCard> finalizedCards;
  final CanonicalPaginationFrontier frontier;
  final CanonicalPaginationCursor nextCursor;
  final CanonicalPaginationWorkDiagnostics diagnostics;
  final int elapsedMilliseconds;
  final int sliceCount;
  final int yieldCount;
  final int longestWorkIntervalMilliseconds;
  final int maxSliceDurationMilliseconds;
  final int totalYieldMilliseconds;
  final int maxSourceChunksPerSlice;
  final int maxDisplayChunksPerSlice;
  final int? cancellationLatencyMilliseconds;
  final int inspectedSourceChunks;
  final int consumedEndExclusive;
  final String? message;
}

bool readerChunksShareHardMergeBoundary(BookChunk first, BookChunk second) {
  if (first.type != BookChunkType.text || second.type != BookChunkType.text) {
    return false;
  }
  final firstListSegments = first.effectiveListDisplaySegments;
  final secondListSegments = second.effectiveListDisplaySegments;
  if (firstListSegments.isEmpty != secondListSegments.isEmpty) return false;
  if (firstListSegments.isNotEmpty && secondListSegments.isNotEmpty) {
    final firstList = firstListSegments.last.semantics;
    final secondList = secondListSegments.first.semantics;
    final sameList = firstList.listId == secondList.listId;
    final directlyNested =
        (secondList.parentListId == firstList.listId &&
            secondList.parentItemId == firstList.itemId) ||
        (firstList.parentListId == secondList.listId &&
            firstList.parentItemId == secondList.itemId);
    if (!sameList && !directlyNested) return false;
  }
  return first.section == second.section &&
      first.sourceFile == second.sourceFile &&
      first.isHeading == second.isHeading &&
      first.blockRole == second.blockRole &&
      first.publisherTextAlign == second.publisherTextAlign &&
      first.publisherLeftIndent == second.publisherLeftIndent &&
      first.publisherRightIndent == second.publisherRightIndent &&
      first.preserveLineBreaks == second.preserveLineBreaks &&
      first.preserveWhitespace == second.preserveWhitespace;
}

List<BookListDisplaySegment> readerListDisplaySegmentsForSlice({
  required BookChunk chunk,
  required int startOffset,
  required int endOffset,
}) {
  if (startOffset >= endOffset) return const [];
  final result = <BookListDisplaySegment>[];
  for (final segment in chunk.effectiveListDisplaySegments) {
    final overlapStart = math.max(startOffset, segment.displayStartOffset);
    final overlapEnd = math.min(endOffset, segment.displayEndOffset);
    if (overlapStart >= overlapEnd) continue;
    final beginsItem =
        segment.showsMarker && overlapStart == segment.displayStartOffset;
    final segmentEndsItem =
        segment.fragmentState == BookListFragmentState.complete ||
        segment.fragmentState == BookListFragmentState.finalFragment;
    final endsItem = segmentEndsItem && overlapEnd == segment.displayEndOffset;
    result.add(
      BookListDisplaySegment(
        displayStartOffset: overlapStart - startOffset,
        displayEndOffset: overlapEnd - startOffset,
        semantics: segment.semantics,
        fragmentState: bookListFragmentState(
          beginsItem: beginsItem,
          endsItem: endsItem,
        ),
      ),
    );
  }
  return result;
}

/// Rebuilds an exact text fragment from stable source UTF-16 ownership. This
/// is shared by pagination and continuation/identity validation; it does not
/// measure or choose a pagination boundary.
BookChunk buildCanonicalTextFragment(
  BookChunk original,
  int startOffset,
  int endOffset, {
  ReaderTextBoundaryKind trailingBoundaryKind =
      ReaderTextBoundaryKind.structural,
}) {
  final text = original.text ?? '';
  final subText = text.substring(startOffset, endOffset);
  final sourceRanges = original
      .mapDisplayRangeToOriginal(startOffset, endOffset)
      .map(
        (range) => ChunkSourceRange(
          originalChunkIndex: range.originalChunkIndex,
          originalStartOffset: range.originalStartOffset,
          originalEndOffset: range.originalEndOffset,
          displayStartOffset: range.displayStartOffset - startOffset,
          displayEndOffset: range.displayEndOffset - startOffset,
          logicalParagraphId: range.logicalParagraphId,
          paragraphStartOffset: range.paragraphStartOffset,
          paragraphEndOffset: range.paragraphEndOffset,
          isParagraphStart: range.isParagraphStart,
          isParagraphEnd: range.isParagraphEnd,
        ),
      )
      .toList(growable: false);

  List<LinkMetadata>? links() {
    final sliced = <LinkMetadata>[];
    for (final link in original.links ?? const <LinkMetadata>[]) {
      final start = math.max(startOffset, link.start);
      final end = math.min(endOffset, link.end);
      if (start < end) {
        sliced.add(
          LinkMetadata(
            start: start - startOffset,
            end: end - startOffset,
            url: link.url,
          ),
        );
      }
    }
    return sliced.isEmpty ? null : sliced;
  }

  List<InlineStyle>? styles() {
    final sliced = <InlineStyle>[];
    for (final style in original.inlineStyles ?? const <InlineStyle>[]) {
      final start = math.max(startOffset, style.start);
      final end = math.min(endOffset, style.end);
      if (start < end) {
        sliced.add(
          InlineStyle(
            start: start - startOffset,
            end: end - startOffset,
            type: style.type,
          ),
        );
      }
    }
    return sliced.isEmpty ? null : sliced;
  }

  List<FootnoteRef>? footnotes() {
    final sliced = <FootnoteRef>[];
    for (final footnote in original.footnotes ?? const <FootnoteRef>[]) {
      if (footnote.position >= startOffset && footnote.position < endOffset) {
        sliced.add(
          FootnoteRef(
            position: footnote.position - startOffset,
            label: footnote.label,
            content: footnote.content,
          ),
        );
      }
    }
    return sliced.isEmpty ? null : sliced;
  }

  return BookChunk(
    index: original.index,
    type: BookChunkType.text,
    section: original.section,
    sourceFile: original.sourceFile,
    text: subText,
    links: links(),
    inlineStyles: styles(),
    footnotes: footnotes(),
    isHeading: original.isHeading,
    isDialogue: original.isDialogue,
    blockRole: original.blockRole,
    publisherTextAlign: original.publisherTextAlign,
    publisherLeftIndent: original.publisherLeftIndent,
    publisherRightIndent: original.publisherRightIndent,
    preserveLineBreaks: original.preserveLineBreaks,
    preserveWhitespace: original.preserveWhitespace,
    sourceRanges: sourceRanges.isEmpty ? null : sourceRanges,
    logicalParagraphId: original.logicalParagraphId,
    logicalParagraphStartOffset:
        original.logicalParagraphStartOffset + startOffset,
    logicalParagraphEndOffset: original.logicalParagraphStartOffset + endOffset,
    isLogicalParagraphStart:
        original.isLogicalParagraphStart && startOffset == 0,
    isLogicalParagraphEnd:
        original.isLogicalParagraphEnd && endOffset == text.length,
    listSemantics: original.listSemantics,
    listDisplaySegments: readerListDisplaySegmentsForSlice(
      chunk: original,
      startOffset: startOffset,
      endOffset: endOffset,
    ),
    textBoundaries: <DisplayTextBoundary>[
      ...?original.textBoundaries
          ?.where(
            (boundary) =>
                boundary.offset > startOffset && boundary.offset < endOffset,
          )
          .map((boundary) => boundary.shift(-startOffset)),
      if (endOffset < text.length)
        DisplayTextBoundary(offset: subText.length, kind: trailingBoundaryKind),
    ],
  );
}

/// Rebuilds a table fragment from its intrinsic table owner and exact row
/// interval. Headers are structural context; the half-open body-row interval
/// is the fragment's stable ownership.
BookChunk buildCanonicalTableRowFragment(
  BookChunk original,
  ReaderTableBlock table,
  int rowStart,
  int rowEndExclusive,
) {
  final splitTable = sliceNormalizedReaderTableBodyRows(
    table,
    rowStart,
    rowEndExclusive,
  );
  return BookChunk(
    index: original.index,
    type: BookChunkType.text,
    section: original.section,
    sourceFile: original.sourceFile,
    text: encodeReaderTableBlock(splitTable),
    blockRole: original.blockRole,
    publisherTextAlign: original.publisherTextAlign,
    publisherLeftIndent: original.publisherLeftIndent,
    publisherRightIndent: original.publisherRightIndent,
    preserveLineBreaks: original.preserveLineBreaks,
    preserveWhitespace: original.preserveWhitespace,
    logicalParagraphId: original.logicalParagraphId,
    logicalParagraphStartOffset: original.logicalParagraphStartOffset,
    logicalParagraphEndOffset: original.logicalParagraphEndOffset,
    isLogicalParagraphStart: rowStart == 0,
    isLogicalParagraphEnd: rowEndExclusive == table.rows.length,
  );
}

bool _listFragmentBeginsItem(BookListFragmentState state) =>
    state == BookListFragmentState.complete ||
    state == BookListFragmentState.opening;

bool _listFragmentEndsItem(BookListFragmentState state) =>
    state == BookListFragmentState.complete ||
    state == BookListFragmentState.finalFragment;

List<BookListDisplaySegment>? _mergeBookListDisplaySegments(
  BookChunk first,
  BookChunk second,
  int secondOffset,
  int separatorLength,
) {
  final firstSegments = first.effectiveListDisplaySegments;
  final secondSegments = second.effectiveListDisplaySegments;
  if (firstSegments.isEmpty || secondSegments.isEmpty) return null;

  final merged = <BookListDisplaySegment>[
    ...firstSegments,
    ...secondSegments.map((segment) => segment.shift(secondOffset)),
  ];
  if (separatorLength != 0 || merged.length < 2) return merged;

  final before = merged[merged.length - 2];
  final after = merged.last;
  final sameSourceBlock =
      before.semantics.itemId == after.semantics.itemId &&
      before.semantics.blockIndex == after.semantics.blockIndex &&
      before.displayEndOffset == after.displayStartOffset;
  if (!sameSourceBlock) return merged;

  merged
    ..removeLast()
    ..removeLast()
    ..add(
      BookListDisplaySegment(
        displayStartOffset: before.displayStartOffset,
        displayEndOffset: after.displayEndOffset,
        semantics: before.semantics,
        fragmentState: bookListFragmentState(
          beginsItem: _listFragmentBeginsItem(before.fragmentState),
          endsItem: _listFragmentEndsItem(after.fragmentState),
        ),
      ),
    );
  return merged;
}

bool readerCanAttemptDisplayMerge(BookChunk first, BookChunk second) {
  if (!readerChunksShareHardMergeBoundary(first, second)) return false;
  return first.blockRole != BookBlockRole.table &&
      second.blockRole != BookBlockRole.table;
}

int readerMeasuredAnchoredLookaheadEndExclusive({
  required List<BookChunk> sourceChunks,
  required int sourceIndex,
  required double heightBudget,
  required double effectiveLineBoxHeight,
}) {
  final anchorChunk = sourceChunks[sourceIndex];
  final measuredLineCapacity = math.max(
    1,
    (heightBudget / math.max(1.0, effectiveLineBoxHeight)).ceil(),
  );
  final readableUnitBudget = measuredLineCapacity + 2;
  var readableUnits = 1;
  var endExclusive = sourceIndex + 1;

  while (endExclusive < sourceChunks.length &&
      readableUnits < readableUnitBudget) {
    final candidate = sourceChunks[endExclusive];
    endExclusive++;
    if (candidate.type != BookChunkType.text ||
        (candidate.text?.trim().isNotEmpty ?? false)) {
      readableUnits++;
    }
    if (!readerCanAttemptDisplayMerge(anchorChunk, candidate)) break;
  }
  return endExclusive;
}

bool readerDisplayChunkContainsSourceOffset({
  required BookChunk chunk,
  required int sourceIndex,
  required int textOffset,
}) {
  return chunk.effectiveSourceRanges.any(
    (range) =>
        range.originalChunkIndex == sourceIndex &&
        textOffset >= range.originalStartOffset &&
        textOffset < range.originalEndOffset,
  );
}

bool readerAnchoredCardBoundaryIsFinalized({
  required List<BookChunk> emittedCards,
  required BookChunk? pendingCard,
  required int sourceIndex,
  required int textOffset,
}) {
  final anchorDisplayIndex = emittedCards.indexWhere(
    (chunk) => readerDisplayChunkContainsSourceOffset(
      chunk: chunk,
      sourceIndex: sourceIndex,
      textOffset: textOffset,
    ),
  );
  if (anchorDisplayIndex < 0) return false;
  if (anchorDisplayIndex < emittedCards.length - 1) return true;
  return pendingCard != null &&
      !readerDisplayChunkContainsSourceOffset(
        chunk: pendingCard,
        sourceIndex: sourceIndex,
        textOffset: textOffset,
      );
}

int readerLayoutWordCount(String text) {
  final len = text.length;
  if (len == 0) return 0;
  int count = 0;
  bool inWord = false;
  for (int i = 0; i < len; i++) {
    final c = text.codeUnitAt(i);
    final isSpace = c == 32 || c == 9 || c == 10 || c == 13;
    if (!isSpace) {
      if (!inWord) {
        count++;
        inWord = true;
      }
    } else {
      inWord = false;
    }
  }
  return count;
}

TextAlign resolveReaderChunkTextAlign(
  BookChunk chunk,
  ReadingSettings settings,
) {
  if (chunk.isHeading) return TextAlign.center;

  final publisherAlign = chunk.publisherTextAlign;
  if (chunk.usesPublisherLayout && publisherAlign != null) {
    return switch (publisherAlign) {
      BookTextAlign.left => TextAlign.left,
      BookTextAlign.center => TextAlign.center,
      BookTextAlign.right => TextAlign.right,
      BookTextAlign.justify => TextAlign.justify,
    };
  }

  if (chunk.blockRole == BookBlockRole.poem ||
      chunk.blockRole == BookBlockRole.stanza ||
      chunk.blockRole == BookBlockRole.preformatted ||
      chunk.blockRole == BookBlockRole.table) {
    return TextAlign.left;
  }

  return settings.resolvedTextAlign;
}

EdgeInsets resolveReaderPublisherPadding(BookChunk chunk) {
  if (!chunk.usesPublisherLayout) return EdgeInsets.zero;

  return EdgeInsets.only(
    left: chunk.publisherLeftIndent.clamp(0, 72).toDouble(),
    right: chunk.publisherRightIndent.clamp(0, 72).toDouble(),
  );
}

const ReaderTextBoundaryService _readerTextBoundaryService =
    ReaderTextBoundaryService();

bool _isReaderSentenceTerminator(String char) =>
    char == '.' ||
    char == '!' ||
    char == '?' ||
    char == '…' ||
    char == '。' ||
    char == '！' ||
    char == '？';

bool _isReaderSentenceCloser(String char) =>
    char == '"' ||
    char == "'" ||
    char == ')' ||
    char == ']' ||
    char == '}' ||
    char == '”' ||
    char == '’' ||
    char == '»';

bool readerTextEndsAtSentenceBoundary(String text) {
  var index = text.trimRight().length - 1;
  if (index < 0) return true;

  while (index >= 0 && _isReaderSentenceCloser(text[index])) {
    index--;
  }
  return index >= 0 && _isReaderSentenceTerminator(text[index]);
}

List<({int start, int end})> readerSentenceRanges(String text) {
  return _readerTextBoundaryService
      .analyze(text)
      .sentenceRanges
      .map((range) => (start: range.start, end: range.end))
      .toList();
}

List<({int start, int end})> readerSafeClauseRanges(String text) {
  return _readerTextBoundaryService
      .clauseRanges(text)
      .map((range) => (start: range.start, end: range.end))
      .toList();
}

/// The sole production split/merge/rebalance engine.
///
/// [paginateCanonical] exposes canonical P04 state.
/// [paginateLegacyForP02] remains only for frozen historical parity evidence;
/// ReaderScreen has no legacy-adapter call site.
final class ReaderCardPaginator {
  const ReaderCardPaginator();

  Future<DisplayRangeResult> paginateLegacyForP02(
    ReaderCardPaginatorRequest input,
  ) async {
    final snapshot = CanonicalPaginationSourceSnapshot.pin(
      bookId: input.diagnosticBookId,
      publicationFingerprint: 'legacy:${input.diagnosticBookId}',
      parserSourceIdentity: 'legacy-reader-screen-adapter',
      sourceRevision: 'generation:${input.parentGeneration}',
      sourceChunks: input.sourceChunks,
      sourceKeys: <CanonicalPaginationSourceKey>[
        for (var ordinal = 0; ordinal < input.sourceChunks.length; ordinal++)
          CanonicalPaginationSourceKey(
            sourceIdentity:
                'legacy:${input.sourceChunks[ordinal].sourceFile ?? 'section'}:'
                '${input.sourceChunks[ordinal].logicalParagraphId ?? 'source'}:'
                '$ordinal',
            sectionIdentity:
                input.sourceChunks[ordinal].sourceFile ??
                input.sourceChunks[ordinal].section.name,
            spineIdentity:
                input.sourceChunks[ordinal].sourceFile ??
                input.sourceChunks[ordinal].section.name,
            sourceOrdinalHint: ordinal,
          ),
      ],
    );
    final startOwner = snapshot.ownerAt(input.range.sourceRange.start);
    final engine = await _runEngine(
      _EngineRequest(
        snapshot: snapshot,
        layout: input.layout,
        scheduler: input.scheduler,
        priority: input.priority,
        isCancelled: input.isCancelled,
        generationToken: input.range.generationId,
        // This legacy callback reports ReaderScreen's parent generation; it
        // is diagnostic context, not canonical generation-token authority.
        startCursor: CanonicalPaginationCursor(
          kind: CanonicalPaginationCursorKind.wholeSource,
          sourceIdentity: startOwner.sourceIdentity,
          sectionIdentity: startOwner.sectionIdentity,
          sourceOrdinalHint: startOwner.sourceOrdinalHint,
        ),
        endSourceOrdinalExclusive: input.range.sourceRange.endExclusive,
        terminalPolicy: _EngineTerminalPolicy.legacyRequestEnd,
        workBudget: const CanonicalPaginationWorkBudget(
          maxSourceChunks: 0x3fffffff,
          maxAtomicFragments: 0x3fffffff,
          maxFinalizedCards: 0x3fffffff,
          maxFrontierEntries: 0x3fffffff,
        ),
        frontierEntryCap: 0x3fffffff,
        controlledLayoutIdentity: 'legacy-reader-screen-layout',
        paginationAlgorithmIdentity: readerPaginationAlgorithmVersion,
        diagnosticBookId: input.diagnosticBookId,
        legacyRangeRequest: input.range,
        legacyAnchor: input.finalizeAnchor,
        onDiagnostic: input.onDiagnostic,
      ),
    );

    final rangeRequest = input.range;
    final cancelled =
        engine.kind == _EngineStopKind.cancelled ||
        engine.kind == _EngineStopKind.stale;
    final effectiveRequest =
        cancelled ||
            engine.consumedEndExclusive == rangeRequest.sourceRange.endExclusive
        ? rangeRequest
        : DisplayRangeRequest(
            direction: rangeRequest.direction,
            sourceRange: SourceChunkRange(
              rangeRequest.sourceRange.start,
              engine.consumedEndExclusive,
            ),
            generationId: rangeRequest.generationId,
            reason: rangeRequest.reason,
            targetOriginalIndex: rangeRequest.targetOriginalIndex,
            targetTextOffset: rangeRequest.targetTextOffset,
          );
    final cards = cancelled
        ? const <_EngineFinalizedCard>[]
        : engine.finalizedCards;
    final displayChunks = cards.map((card) => card.chunk).toList();
    final displayToOriginal = cards
        .map((card) => List<int>.of(card.originals))
        .toList();
    final originalToDisplay = <int, int>{};
    for (var displayIndex = 0; displayIndex < cards.length; displayIndex++) {
      for (final sourceIndex in cards[displayIndex].originals) {
        originalToDisplay[sourceIndex] = displayIndex;
      }
    }
    final result = DisplayRangeResult(
      request: effectiveRequest,
      displayChunks: displayChunks,
      displayToOriginal: displayToOriginal,
      originalToDisplay: originalToDisplay,
      inspectedSourceChunks: engine.inspectedSourceChunks,
      elapsedMilliseconds: engine.elapsedMilliseconds,
      sliceCount: engine.sliceCount,
      yieldCount: engine.yieldCount,
      longestWorkIntervalMilliseconds: engine.longestWorkIntervalMilliseconds,
      maxSliceDurationMilliseconds: engine.maxSliceDurationMilliseconds,
      totalYieldMilliseconds: engine.totalYieldMilliseconds,
      maxSourceChunksPerSlice: engine.maxSourceChunksPerSlice,
      maxDisplayChunksPerSlice: engine.maxDisplayChunksPerSlice,
      cancellationLatencyMilliseconds: engine.cancellationLatencyMilliseconds,
      cancelled: cancelled,
      error:
          engine.kind == _EngineStopKind.invalid ||
              engine.kind == _EngineStopKind.frontierBoundViolation
          ? StateError(engine.message ?? 'Paginator engine rejected request.')
          : null,
    );
    input.onDiagnostic?.call('range_generation_end', <String, Object?>{
      'book': input.diagnosticBookId,
      'generation': input.parentGeneration,
      'rangeGeneration': rangeRequest.generationId,
      'direction': rangeRequest.direction.name,
      'sourceStart': rangeRequest.sourceRange.start,
      'sourceEndExclusive': effectiveRequest.sourceRange.endExclusive,
      'requestedSourceEndExclusive': rangeRequest.sourceRange.endExclusive,
      'inspectedSourceChunks': result.inspectedSourceChunks,
      'displayChunks': result.displayChunks.length,
      'displayToOriginal': result.displayToOriginal.length,
      'originalToDisplay': result.originalToDisplay.length,
      'elapsedMs': result.elapsedMilliseconds,
      'sliceCount': result.sliceCount,
      'yieldCount': result.yieldCount,
      'longestWorkIntervalMs': result.longestWorkIntervalMilliseconds,
      'maxSliceDurationMs': result.maxSliceDurationMilliseconds,
      'totalYieldMs': result.totalYieldMilliseconds,
      'maxSourceChunksPerSlice': result.maxSourceChunksPerSlice,
      'maxDisplayChunksPerSlice': result.maxDisplayChunksPerSlice,
    });
    return result;
  }

  Future<CanonicalPaginationResult> paginateCanonical(
    CanonicalPaginationRequest request,
  ) async {
    final sectionInput = request.sectionInput;
    if (sectionInput != null) {
      try {
        sectionInput.validateSnapshot(request.sourceSnapshot);
      } on Object catch (error) {
        return CanonicalInvalidRestartSourceRejected(
          diagnostics: const CanonicalPaginationWorkDiagnostics(),
          reason: CanonicalPaginationRejectionReason
              .incompatibleParserSourceSnapshot,
          message: '$error',
        );
      }
    }
    final invalid = _validateCanonicalRequest(request);
    if (invalid != null) {
      return CanonicalInvalidRestartSourceRejected(
        diagnostics: const CanonicalPaginationWorkDiagnostics(),
        reason: invalid.$1,
        message: invalid.$2,
      );
    }

    final restart = request.restart;
    late final CanonicalPaginationCursor cursor;
    late final CanonicalPaginationFrontier initialFrontier;
    if (restart is CanonicalPaginationPublicationStart) {
      initialFrontier = const CanonicalPaginationFrontier();
      cursor = request.sourceSnapshot.sourceCount == 0
          ? const CanonicalPaginationCursor.logicalEnd()
          : _sourceStartCursor(request.sourceSnapshot, 0);
    } else if (restart is CanonicalPaginationTrustedSectionStart) {
      initialFrontier = const CanonicalPaginationFrontier();
      cursor = CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.wholeSource,
        sourceIdentity: restart.sourceIdentity,
        sectionIdentity: restart.sectionIdentity,
        sourceOrdinalHint: restart.sourceOrdinalHint,
      );
    } else if (restart is CanonicalPaginationContinuation) {
      cursor = restart.nextSourceCursor;
      initialFrontier = restart.frontier;
    } else {
      return const CanonicalInvalidRestartSourceRejected(
        diagnostics: CanonicalPaginationWorkDiagnostics(),
        reason: CanonicalPaginationRejectionReason.invalidRestart,
        message: 'Unsupported canonical restart type.',
      );
    }

    final derivedCap = _derivedFrontierEntryCap(request.layout);
    final requestedCap = request.workBudget.maxFrontierEntries;
    final frontierCap = requestedCap == null
        ? derivedCap
        : math.min(derivedCap, requestedCap);
    final carriedSources =
        restart is CanonicalPaginationContinuation &&
            restart.checkpointReason ==
                CanonicalPaginationCheckpointReason.requestExhaustedProvisional
        ? restart.sourcesSinceCheckpoint
        : 0;
    final carriedCards =
        restart is CanonicalPaginationContinuation &&
            restart.checkpointReason ==
                CanonicalPaginationCheckpointReason.requestExhaustedProvisional
        ? restart.cardsSinceCheckpoint
        : 0;
    final cadenceBudget = CanonicalPaginationWorkBudget(
      maxSourceChunks: math.min(
        request.workBudget.maxSourceChunks,
        CanonicalPaginationBounds.checkpointSourceStride - carriedSources,
      ),
      maxAtomicFragments: request.workBudget.maxAtomicFragments,
      maxFinalizedCards: math.min(
        request.workBudget.maxFinalizedCards,
        CanonicalPaginationBounds.checkpointCardStride - carriedCards,
      ),
      maxFrontierEntries: request.workBudget.maxFrontierEntries,
      envelope: request.workBudget.envelope,
    );
    final engine = await _runEngine(
      _EngineRequest(
        snapshot: request.sourceSnapshot,
        layout: request.layout,
        scheduler: request.operation.scheduler,
        priority: request.operation.priority,
        isCancelled: request.operation.isCancelled,
        generationToken: request.operation.generationToken,
        currentGenerationToken: request.operation.currentGenerationToken,
        startCursor: cursor,
        endSourceOrdinalExclusive: request.sourceSnapshot.sourceCount,
        terminalPolicy: _EngineTerminalPolicy.canonicalLogicalEndOnly,
        workBudget: cadenceBudget,
        frontierEntryCap: frontierCap,
        controlledLayoutIdentity: request.controlledLayoutIdentity,
        paginationAlgorithmIdentity: request.paginationAlgorithmIdentity,
        diagnosticBookId: request.operation.diagnosticBookId ?? request.bookId,
        initialFrontier: initialFrontier,
        target: request.target,
        onDiagnostic: request.operation.onDiagnostic,
      ),
    );

    if (engine.kind == _EngineStopKind.cancelled ||
        engine.kind == _EngineStopKind.stale) {
      return CanonicalCancelledStaleRejected(
        diagnostics: engine.diagnostics,
        reason: engine.kind == _EngineStopKind.stale
            ? CanonicalPaginationRejectionReason.staleGeneration
            : CanonicalPaginationRejectionReason.cancelled,
        message: engine.message ?? 'Canonical pagination was cancelled.',
      );
    }
    if (engine.kind == _EngineStopKind.invalid) {
      return CanonicalInvalidRestartSourceRejected(
        diagnostics: engine.diagnostics,
        reason: CanonicalPaginationRejectionReason.invalidFrontier,
        message: engine.message ?? 'Canonical pagination state was invalid.',
      );
    }
    if (engine.kind == _EngineStopKind.frontierBoundViolation) {
      return CanonicalFrontierBoundViolation(
        diagnostics: engine.diagnostics,
        message: engine.message ?? 'Canonical frontier exceeded its bound.',
      );
    }

    final finalized = <CanonicalFinalizedReaderCard>[
      for (final card in engine.finalizedCards)
        _finalizedCanonicalCard(request, card),
    ];
    final totalSources =
        carriedSources + engine.diagnostics.sourceChunksFullyConsumed;
    final totalCards = carriedCards + engine.diagnostics.cardsFinalized;
    final terminal =
        engine.kind == _EngineStopKind.logicalEnd ||
        (engine.nextCursor.isLogicalEnd &&
            engine.frontier.cardCandidateCount == 0);
    if (terminal && sectionInput != null && !sectionInput.verifiedBookEnd) {
      return CanonicalInputExhaustedAwaitingSuccessor(
        diagnostics: engine.diagnostics,
        finalizedCards: finalized,
      );
    }
    final checkpointReason = switch (engine.kind) {
      _ when terminal => CanonicalPaginationCheckpointReason.terminalBookEnd,
      _EngineStopKind.sectionBoundary =>
        CanonicalPaginationCheckpointReason.sectionBoundary,
      _EngineStopKind.targetFinalized =>
        CanonicalPaginationCheckpointReason.targetSatisfied,
      _ when totalCards >= CanonicalPaginationBounds.checkpointCardStride =>
        CanonicalPaginationCheckpointReason.cardCadence,
      _ when totalSources >= CanonicalPaginationBounds.checkpointSourceStride =>
        CanonicalPaginationCheckpointReason.sourceCadence,
      _ => CanonicalPaginationCheckpointReason.requestExhaustedProvisional,
    };
    final continuation = _buildContinuation(
      request: request,
      startCursor: cursor,
      nextCursor: engine.nextCursor,
      frontier: engine.frontier,
      finalizedCards: finalized,
      checkpointReason: checkpointReason,
      sourcesSinceCheckpoint: totalSources,
      cardsSinceCheckpoint: totalCards,
      terminal: terminal,
    );
    final target = request.target;
    final targetCards = target == null
        ? const <CanonicalFinalizedReaderCard>[]
        : finalized
              .where(
                (card) => card.sourceSlices.any(
                  (slice) => _canonicalSliceContainsTarget(slice, target),
                ),
              )
              .toList(growable: false);
    if (targetCards.isNotEmpty) {
      final resolvedTarget = target!;
      final targetCard = targetCards.single;
      final containingSlice = targetCard.sourceSlices.singleWhere(
        (slice) => _canonicalSliceContainsTarget(slice, resolvedTarget),
      );
      return CanonicalTargetFinalized(
        diagnostics: engine.diagnostics,
        finalizedCards: List.unmodifiable(finalized),
        targetCard: targetCard,
        containmentEvidence: CanonicalPaginationTargetContainmentEvidence(
          target: resolvedTarget,
          cardIdentity: targetCard.identity,
          containingSlice: containingSlice,
          offsetWithinSliceUtf16: containingSlice.startUtf16 == null
              ? 0
              : resolvedTarget.textOffsetUtf16 - containingSlice.startUtf16!,
        ),
        continuation: continuation,
      );
    }
    if (engine.kind == _EngineStopKind.logicalEnd) {
      return CanonicalLogicalEndReached(
        diagnostics: engine.diagnostics,
        finalizedCards: List.unmodifiable(finalized),
        continuation: continuation,
      );
    }
    if (engine.kind == _EngineStopKind.budgetExhausted) {
      return CanonicalBudgetExhaustedWithFrontier(
        diagnostics: engine.diagnostics,
        finalizedCards: List.unmodifiable(finalized),
        frontier: engine.frontier,
        continuation: continuation,
        nextSourceCursor: engine.nextCursor,
      );
    }
    return CanonicalFinalizedOutputAvailable(
      diagnostics: engine.diagnostics,
      finalizedCards: List.unmodifiable(finalized),
      continuation: continuation,
    );
  }

  Future<_EngineRunResult> _runEngine(_EngineRequest input) async {
    final rangeRequest = input.legacyRangeRequest;
    final sourceChunks = <BookChunk>[
      for (var ordinal = 0; ordinal < input.snapshot.sourceCount; ordinal++)
        input.snapshot.resolveOrdinalSource(ordinal),
    ];
    var sourceChunksEntered = 0;
    var sourceChunksFullyConsumed = 0;
    var atomicFragmentsProcessed = 0;
    var referencedUtf16Extent = 0;
    var tableRows = 0;
    var graphemeCandidates = 0;
    var rebalanceCandidates = 0;
    var cardsFinalized = 0;
    var cancellationCheckpoints = 0;
    var peakFrontierEntries = 0;
    var peakPrivateFrontierBytes = 0;
    var inspectedSourceChunks = 0;
    final tableRowIntervals =
        HashMap<BookChunk, ({int start, int endExclusive})>.identity();

    Future<bool> cooperativeCheckpoint(
      FrameBudgetedRangeTask task, {
      int sourceChunksProcessed = 0,
      int displayChunksProduced = 0,
    }) {
      cancellationCheckpoints++;
      return task.checkpoint(
        sourceChunksProcessed: sourceChunksProcessed,
        displayChunksProduced: displayChunksProduced,
      );
    }

    final layout = input.layout;
    final settings = layout.settings;
    final textScaler = layout.textScaler;
    final textHeightCache =
        <({int chunkId, String text, bool dialogue, double width}), double>{};
    final resolvedBlockCache = <String, ResolvedReaderBlockLayout>{};

    ResolvedReaderBlockLayout? resolveContractBlock(BookChunk chunk) {
      final contract = layout.contract;
      if (contract == null) return null;
      final text = chunk.text ?? '';
      final owner = canonicalBookChunkOwnershipDigest(chunk);
      final cacheKey = '$owner|${readerSha256(text)}';
      final cached = resolvedBlockCache[cacheKey];
      if (cached != null) return cached;
      final fontResolver = layout.fontEvidenceResolver;
      if (fontResolver == null) {
        throw StateError('Authoritative layout requires source font evidence.');
      }
      final resolved = ReaderBlockLayoutResolver.resolve(
        contract: contract,
        chunk: chunk,
        stableBlockOwner: owner,
        sourceStructureDigestLink: owner,
        fontEvidence: fontResolver(chunk, text),
        imageEvidence: layout.imageEvidenceResolver?.call(chunk),
      );
      resolvedBlockCache[cacheKey] = resolved;
      return resolved;
    }

    void diagnostic(String phase, Map<String, Object?> fields) {
      input.onDiagnostic?.call(phase, fields);
    }

    ReaderTableBlock? singleTableBlock(String text) {
      return normalizedReaderTableFromText(text);
    }

    BookChunk buildTableRowFragment(
      BookChunk original,
      ReaderTableBlock table,
      int rowStart,
      int rowEndExclusive,
    ) {
      final fragment = buildCanonicalTableRowFragment(
        original,
        table,
        rowStart,
        rowEndExclusive,
      );
      tableRowIntervals[fragment] = (
        start: rowStart,
        endExclusive: rowEndExclusive,
      );
      return fragment;
    }

    double tableRowHeight(
      List<String> cells,
      TextStyle style,
      double columnWidth,
    ) {
      var maxCellHeight = 0.0;
      for (final cell in cells) {
        final tp = TextPainter(
          text: TextSpan(text: cell, style: style),
          textDirection: TextDirection.ltr,
          locale: style.locale,
          textScaler: textScaler,
          strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
          textHeightBehavior: readerTextHeightBehavior,
        )..layout(maxWidth: math.max(1.0, columnWidth - 20));
        maxCellHeight = math.max(maxCellHeight, tp.height);
        tp.dispose();
      }
      return maxCellHeight + 18;
    }

    ({TextStyle cellStyle, TextStyle headerStyle, double columnWidth})
    tableMeasurementStyle(ReaderTableBlock table, BookChunk chunk) {
      final columnCount = math.max(1, table.columnCount);
      final publisherPadding = resolveReaderPublisherPadding(chunk);
      final maxWidth = math.max(
        1.0,
        layout.availableWidth - publisherPadding.horizontal,
      );
      final columnWidth = columnCount >= 3
          ? 156.0
          : math.max(120.0, maxWidth / columnCount);
      final cellStyle = layout.bodyStyle.copyWith(
        fontSize: settings.fontSizeValue.clamp(13.0, 18.0),
        height: settings.effectiveLineHeight.clamp(1.2, 1.45),
        fontWeight: FontWeight.w500,
      );
      return (
        cellStyle: cellStyle,
        headerStyle: cellStyle.copyWith(fontWeight: FontWeight.w800),
        columnWidth: columnWidth,
      );
    }

    double estimateTableHeight(ReaderTableBlock table, BookChunk chunk) {
      final rowCount = table.rows.length + (table.headers.isNotEmpty ? 1 : 0);
      if (rowCount == 0) return 0;
      final tableStyle = tableMeasurementStyle(table, chunk);

      var height = 22.0;
      if (table.headers.isNotEmpty) {
        height += tableRowHeight(
          table.headers,
          tableStyle.headerStyle,
          tableStyle.columnWidth,
        );
      }
      for (final row in table.rows) {
        height += tableRowHeight(
          row,
          tableStyle.cellStyle,
          tableStyle.columnWidth,
        );
      }
      return height;
    }

    Future<double?> estimateTableHeightCooperative(
      ReaderTableBlock table,
      BookChunk chunk,
      FrameBudgetedRangeTask schedulerTask, {
      double? stopAfter,
    }) async {
      final rowCount = table.rows.length + (table.headers.isNotEmpty ? 1 : 0);
      if (rowCount == 0) return 0;
      final tableStyle = tableMeasurementStyle(table, chunk);
      var height = 22.0;

      if (table.headers.isNotEmpty) {
        height += tableRowHeight(
          table.headers,
          tableStyle.headerStyle,
          tableStyle.columnWidth,
        );
        if (!await cooperativeCheckpoint(schedulerTask)) return null;
        if (stopAfter != null && height > stopAfter) return height;
      }

      var rowIndex = 0;
      for (final row in table.rows) {
        tableRows++;
        height += tableRowHeight(
          row,
          tableStyle.cellStyle,
          tableStyle.columnWidth,
        );
        if (rowIndex % 2 == 0 && !await cooperativeCheckpoint(schedulerTask)) {
          return null;
        }
        if (stopAfter != null && height > stopAfter) return height;
        rowIndex++;
      }
      return height;
    }

    void logSlowTextMeasure({
      required Stopwatch? stopwatch,
      required BookChunk chunk,
      required String text,
      required String kind,
      ReaderTableBlock? table,
    }) {
      if (stopwatch == null) return;
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      if (elapsedMs < 40) return;
      diagnostic('range_slow_text_measure', {
        'book': input.diagnosticBookId,
        'generation':
            input.currentGenerationToken?.call() ?? input.generationToken,
        'sourceIndex': chunk.index,
        'kind': kind,
        'elapsedMs': elapsedMs,
        'textLength': text.length,
        'wordCount': readerLayoutWordCount(text),
        'lineBreaks': '\n'.allMatches(text).length,
        'blockRole': chunk.blockRole.name,
        'publisherLayout': chunk.usesPublisherLayout,
        'isHeading': chunk.isHeading,
        'isDialogue': chunk.isDialogue,
        'tableRows': table?.rows.length,
        'tableColumns': table?.columnCount,
      });
    }

    double measureTextHeight(
      String text,
      BookChunk chunk, {
      bool? dialogueOverride,
    }) {
      final contractBlock = resolveContractBlock(
        text == (chunk.text ?? '') ? chunk : chunk.copyWith(text: text),
      );
      if (contractBlock != null) {
        return ReaderLayoutMeasurementAdapter.blockHeight(contractBlock);
      }
      final measureStopwatch = input.onDiagnostic == null
          ? null
          : (Stopwatch()..start());
      final isDialogue = dialogueOverride ?? chunk.isDialogue;
      final dialogueExtraInset = isDialogue ? kReaderDialogueTextInset : 0.0;
      final publisherPadding = resolveReaderPublisherPadding(chunk);
      final chunkAvailableWidth =
          layout.availableWidth -
          dialogueExtraInset -
          publisherPadding.horizontal;
      final maxWidth = math.max(1.0, chunkAvailableWidth);
      final cacheKey = (
        chunkId: identityHashCode(chunk),
        text: text,
        dialogue: isDialogue,
        width: maxWidth,
      );
      final cachedHeight = textHeightCache[cacheKey];
      if (cachedHeight != null) return cachedHeight;

      final textAlign = resolveReaderChunkTextAlign(chunk, settings);
      final table = chunk.blockRole == BookBlockRole.table
          ? singleTableBlock(text)
          : null;
      if (table != null) {
        final height = estimateTableHeight(table, chunk);
        textHeightCache[cacheKey] = height;
        logSlowTextMeasure(
          stopwatch: measureStopwatch,
          chunk: chunk,
          text: text,
          kind: 'table',
          table: table,
        );
        return height;
      }

      final listSegments = chunk.effectiveListDisplaySegments;
      if (listSegments.isNotEmpty) {
        double measureListBody(
          String segmentText,
          BookListSemantics semantics,
        ) {
          final metrics = resolveReaderListLayoutMetrics(
            semantics: semantics,
            style: layout.bodyStyle,
            textScaler: textScaler,
          );
          return measureFinalLayoutParagraphTextHeight(
            text: segmentText,
            style: layout.bodyStyle,
            maxWidth: math.max(1.0, maxWidth - metrics.bodyInset),
            textDirection: TextDirection.ltr,
            textAlign: textAlign,
            textScaler: textScaler,
            strutStyle: layout.bodyStrut,
            fallbackFontSize: settings.fontSizeValue,
            fallbackLineHeight: settings.effectiveLineHeight,
            paragraphSpacing: settings.paragraphSpacing,
          );
        }

        double height;
        if (text == chunk.text) {
          height = 0;
          BookListDisplaySegment? previous;
          for (final segment in listSegments) {
            final start = segment.displayStartOffset.clamp(0, text.length);
            final end = segment.displayEndOffset.clamp(start, text.length);
            if (start >= end) continue;
            if (previous != null) {
              height += readerListGapBefore(
                previous: previous,
                current: segment,
                lineBoxHeight: settings.effectiveLineBoxHeight,
                paragraphSpacing: settings.paragraphSpacing,
              );
            }
            height += math.max(
              settings.effectiveLineBoxHeight,
              measureListBody(text.substring(start, end), segment.semantics),
            );
            previous = segment;
          }
        } else {
          final semantics = chunk.listSemantics ?? listSegments.first.semantics;
          height = math.max(
            settings.effectiveLineBoxHeight,
            measureListBody(text, semantics),
          );
        }
        textHeightCache[cacheKey] = height;
        logSlowTextMeasure(
          stopwatch: measureStopwatch,
          chunk: chunk,
          text: text,
          kind: 'list',
        );
        return height;
      }

      if (!chunk.isHeading && !chunk.usesPublisherLayout) {
        final height = measureFinalLayoutParagraphTextHeight(
          text: text,
          style: layout.bodyStyle,
          maxWidth: maxWidth,
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
          textScaler: textScaler,
          strutStyle: layout.bodyStrut,
          fallbackFontSize: settings.fontSizeValue,
          fallbackLineHeight: settings.effectiveLineHeight,
          paragraphSpacing: settings.paragraphSpacing,
          boundaries: text == chunk.text ? chunk.textBoundaries : null,
        );
        textHeightCache[cacheKey] = height;
        logSlowTextMeasure(
          stopwatch: measureStopwatch,
          chunk: chunk,
          text: text,
          kind: 'paragraph',
        );
        return height;
      }

      final span = chunk.isHeading
          ? TextSpan(text: text, style: layout.headingStyle)
          : TextSpanUtils.buildSpacedTextSpan(
              text: text,
              baseStyle: layout.bodyStyle,
              paragraphSpacingMultiplier: 1.0,
            );
      final tp = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        locale: chunk.isHeading
            ? layout.headingStyle.locale
            : layout.bodyStyle.locale,
        textAlign: textAlign,
        textScaler: textScaler,
        strutStyle: chunk.isHeading ? layout.headingStrut : layout.bodyStrut,
        textHeightBehavior: readerTextHeightBehavior,
      );
      tp.layout(maxWidth: maxWidth);
      final height = tp.height;
      tp.dispose();
      textHeightCache[cacheKey] = height;
      logSlowTextMeasure(
        stopwatch: measureStopwatch,
        chunk: chunk,
        text: text,
        kind: chunk.isHeading ? 'heading' : 'publisher',
      );
      return height;
    }

    double heightBudgetFor(BookChunk chunk) => chunk.usesPublisherLayout
        ? layout.physicalTextBudget
        : layout.pageHeightBudget;

    List<T>? combineLists<T>(List<T>? first, List<T>? second) {
      final combined = <T>[...?first, ...?second];
      return combined.isEmpty ? null : combined;
    }

    List<LinkMetadata>? shiftLinks(List<LinkMetadata>? links, int delta) {
      if (links == null || links.isEmpty) return null;
      return links
          .map(
            (link) => LinkMetadata(
              start: link.start + delta,
              end: link.end + delta,
              url: link.url,
            ),
          )
          .toList();
    }

    List<InlineStyle>? shiftInlineStyles(List<InlineStyle>? styles, int delta) {
      if (styles == null || styles.isEmpty) return null;
      return styles
          .map(
            (style) => InlineStyle(
              start: style.start + delta,
              end: style.end + delta,
              type: style.type,
            ),
          )
          .toList();
    }

    List<FootnoteRef>? shiftFootnotes(List<FootnoteRef>? footnotes, int delta) {
      if (footnotes == null || footnotes.isEmpty) return null;
      return footnotes
          .map(
            (footnote) => FootnoteRef(
              position: footnote.position + delta,
              label: footnote.label,
              content: footnote.content,
            ),
          )
          .toList();
    }

    BookChunk buildSplitChunk(
      BookChunk original,
      int startOffset,
      int endOffset, {
      ReaderTextBoundaryKind trailingBoundaryKind =
          ReaderTextBoundaryKind.structural,
    }) => buildCanonicalTextFragment(
      original,
      startOffset,
      endOffset,
      trailingBoundaryKind: trailingBoundaryKind,
    );

    Future<List<ReaderTextRange>?> splitOversizedRange(
      String text,
      int startOffset,
      int endOffset,
      BookChunk original,
      FrameBudgetedRangeTask schedulerTask,
    ) async {
      final localText = text.substring(startOffset, endOffset);
      final analysis = _readerTextBoundaryService.analyze(
        localText,
        linkRanges: (original.links ?? const [])
            .map(
              (link) => (
                start: (link.start - startOffset).clamp(0, localText.length),
                end: (link.end - startOffset).clamp(0, localText.length),
              ),
            )
            .where((range) => range.start < range.end)
            .toList(),
      );
      final unitRanges = <ReaderTextRange>[];
      final clauseRanges = _readerTextBoundaryService.clauseRanges(
        localText,
        protectedSpans: analysis.protectedSpans,
      );
      for (final clause in clauseRanges) {
        final absoluteStart = startOffset + clause.start;
        final absoluteEnd = startOffset + clause.end;
        if (measureTextHeight(
              text.substring(absoluteStart, absoluteEnd),
              original,
            ) <=
            layout.physicalTextBudget) {
          unitRanges.add(
            ReaderTextRange(
              start: absoluteStart,
              end: absoluteEnd,
              trailingBoundaryKind: clause.trailingBoundaryKind,
            ),
          );
          continue;
        }
        final clauseText = localText.substring(clause.start, clause.end);
        final clauseProtected = analysis.protectedSpans
            .where((span) => span.start < clause.end && span.end > clause.start)
            .map(
              (span) => ReaderProtectedSpan(
                start: (span.start - clause.start).clamp(0, clauseText.length),
                end: (span.end - clause.start).clamp(0, clauseText.length),
                kind: span.kind,
              ),
            )
            .toList();
        for (final token in _readerTextBoundaryService.wordRanges(
          clauseText,
          protectedSpans: clauseProtected,
        )) {
          unitRanges.add(
            ReaderTextRange(
              start: absoluteStart + token.start,
              end: absoluteStart + token.end,
              trailingBoundaryKind: token.trailingBoundaryKind,
            ),
          );
        }
      }
      if (unitRanges.isEmpty) {
        return [
          ReaderTextRange(
            start: startOffset,
            end: endOffset,
            trailingBoundaryKind: ReaderTextBoundaryKind.structural,
          ),
        ];
      }

      final pieces = <ReaderTextRange>[];
      int pieceStart = startOffset;
      int pieceEnd = startOffset;

      void flushPiece(
        int start,
        int end,
        ReaderTextBoundaryKind trailingBoundaryKind,
      ) {
        if (start < end) {
          pieces.add(
            ReaderTextRange(
              start: start,
              end: end,
              trailingBoundaryKind: trailingBoundaryKind,
            ),
          );
        }
      }

      for (final token in unitRanges) {
        if (!await cooperativeCheckpoint(schedulerTask)) return null;
        final tokenStart = token.start;
        final tokenEnd = token.end;
        final tokenText = text.substring(tokenStart, tokenEnd);
        final tokenHeight = measureTextHeight(tokenText, original);

        if (tokenHeight > layout.physicalTextBudget) {
          flushPiece(pieceStart, pieceEnd, ReaderTextBoundaryKind.word);

          var graphemePieceStart = tokenStart;
          final graphemes = _readerTextBoundaryService.graphemeRanges(
            tokenText,
          );
          for (var i = 0; i < graphemes.length; i++) {
            graphemeCandidates++;
            if (i % 12 == 0 && !await cooperativeCheckpoint(schedulerTask)) {
              return null;
            }
            final cursor = tokenStart + graphemes[i].end;
            final candidate = text.substring(graphemePieceStart, cursor);
            final candidateHeight = measureTextHeight(candidate, original);
            if (candidateHeight > layout.physicalTextBudget) {
              final previousEnd = tokenStart + graphemes[i].start;
              if (previousEnd > graphemePieceStart) {
                flushPiece(
                  graphemePieceStart,
                  previousEnd,
                  ReaderTextBoundaryKind.emergencyGrapheme,
                );
                graphemePieceStart = previousEnd;
              } else {
                flushPiece(
                  graphemePieceStart,
                  cursor,
                  ReaderTextBoundaryKind.emergencyGrapheme,
                );
                graphemePieceStart = cursor;
              }
            }
          }
          flushPiece(graphemePieceStart, tokenEnd, token.trailingBoundaryKind);
          pieceStart = tokenEnd;
          pieceEnd = tokenEnd;
          continue;
        }

        if (pieceStart == pieceEnd) pieceStart = tokenStart;
        final candidate = text.substring(pieceStart, tokenEnd);
        final candidateHeight = measureTextHeight(candidate, original);
        if (candidateHeight > layout.physicalTextBudget &&
            pieceEnd > pieceStart) {
          flushPiece(pieceStart, pieceEnd, ReaderTextBoundaryKind.word);
          pieceStart = tokenStart;
        }
        pieceEnd = tokenEnd;
      }

      flushPiece(pieceStart, pieceEnd, unitRanges.last.trailingBoundaryKind);
      return pieces.isEmpty
          ? [
              ReaderTextRange(
                start: startOffset,
                end: endOffset,
                trailingBoundaryKind: ReaderTextBoundaryKind.structural,
              ),
            ]
          : pieces;
    }

    List<({int start, int end})> preservedLineRanges(String text) {
      final ranges = <({int start, int end})>[];
      var start = 0;
      for (var i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) {
          ranges.add((start: start, end: i + 1));
          start = i + 1;
        }
      }
      if (start < text.length) ranges.add((start: start, end: text.length));
      return ranges;
    }

    Future<List<BookChunk>?> splitChunkByHeight(
      BookChunk original,
      FrameBudgetedRangeTask schedulerTask,
    ) async {
      if (original.type != BookChunkType.text || original.isHeading) {
        return [original];
      }
      final text = original.text ?? '';
      if (text.isEmpty) return [original];
      if (original.blockRole == BookBlockRole.table) {
        final table = singleTableBlock(text);
        final tableBudget = heightBudgetFor(original);
        final tableHeight = table == null
            ? null
            : await estimateTableHeightCooperative(
                table,
                original,
                schedulerTask,
                stopAfter: tableBudget,
              );
        if (table != null && tableHeight == null) return null;
        if (table != null && tableHeight! > tableBudget) {
          final tableChunks = <BookChunk>[];
          var currentRows = <List<String>>[];
          var currentRowStart = 0;
          final tableStyle = tableMeasurementStyle(table, original);
          final headerHeight = table.headers.isEmpty
              ? 0.0
              : tableRowHeight(
                  table.headers,
                  tableStyle.headerStyle,
                  tableStyle.columnWidth,
                );
          final baseHeight = 22.0 + headerHeight;
          var currentHeight = baseHeight;

          var tableRowIndex = 0;
          for (final row in table.rows) {
            if (tableRowIndex % 2 == 0 &&
                !await cooperativeCheckpoint(schedulerTask)) {
              return null;
            }
            tableRowIndex++;
            tableRows++;
            final rowHeight = tableRowHeight(
              row,
              tableStyle.cellStyle,
              tableStyle.columnWidth,
            );
            final candidateHeight = currentHeight + rowHeight;
            if (currentRows.isNotEmpty && candidateHeight > tableBudget) {
              tableChunks.add(
                buildTableRowFragment(
                  original,
                  table,
                  currentRowStart,
                  tableRowIndex - 1,
                ),
              );
              currentRowStart = tableRowIndex - 1;
              currentRows = [row];
              currentHeight = baseHeight + rowHeight;
            } else {
              currentRows = [...currentRows, row];
              currentHeight = candidateHeight;
            }
          }

          if (currentRows.isNotEmpty) {
            tableChunks.add(
              buildTableRowFragment(
                original,
                table,
                currentRowStart,
                table.rows.length,
              ),
            );
          }
          return tableChunks.isNotEmpty ? tableChunks : [original];
        }
      }
      final chunkBudget = heightBudgetFor(original);
      final sourceRanges = original.preserveLineBreaks
          ? preservedLineRanges(text)
                .map(
                  (range) => ReaderTextRange(
                    start: range.start,
                    end: range.end,
                    trailingBoundaryKind: ReaderTextBoundaryKind.word,
                  ),
                )
                .toList()
          : _readerTextBoundaryService
                .analyze(
                  text,
                  linkRanges: (original.links ?? const [])
                      .map((link) => (start: link.start, end: link.end))
                      .toList(),
                )
                .sentenceRanges;
      final shouldExposeSentenceBoundaries =
          !original.preserveLineBreaks && sourceRanges.length > 1;
      final shouldSkipWholeChunkMeasurement =
          text.length > 2400 ||
          '\n'.allMatches(text).length > 8 ||
          readerLayoutWordCount(text) > 360;
      if (!shouldSkipWholeChunkMeasurement) {
        final totalHeight = measureTextHeight(text, original);
        if (totalHeight <= chunkBudget && !shouldExposeSentenceBoundaries) {
          return [original];
        }
        if (!await cooperativeCheckpoint(schedulerTask)) return null;
      } else {
        diagnostic('range_large_chunk_direct_split', {
          'book': input.diagnosticBookId,
          'generation':
              input.currentGenerationToken?.call() ?? input.generationToken,
          'sourceIndex': original.index,
          'textLength': text.length,
          'wordCount': readerLayoutWordCount(text),
          'lineBreaks': '\n'.allMatches(text).length,
          'blockRole': original.blockRole.name,
          'publisherLayout': original.usesPublisherLayout,
        });
      }

      final splitRanges = <ReaderTextRange>[];
      for (final range in sourceRanges) {
        if (!await cooperativeCheckpoint(schedulerTask)) return null;
        if (range.start >= range.end) continue;

        final rangeText = text.substring(range.start, range.end);
        final rangeHeight = measureTextHeight(rangeText, original);

        if (rangeHeight <= layout.physicalTextBudget) {
          splitRanges.add(range);
        } else {
          final oversized = await splitOversizedRange(
            text,
            range.start,
            range.end,
            original,
            schedulerTask,
          );
          if (oversized == null) return null;
          splitRanges.addAll(oversized);
        }
      }

      if (splitRanges.isEmpty) return [original];

      if (!original.preserveLineBreaks &&
          (shouldExposeSentenceBoundaries || splitRanges.length > 1)) {
        return splitRanges
            .map(
              (range) => buildSplitChunk(
                original,
                range.start,
                range.end,
                trailingBoundaryKind: range.trailingBoundaryKind,
              ),
            )
            .toList();
      }

      final subChunks = <BookChunk>[];
      int currentStart = splitRanges.first.start;
      int currentEnd = splitRanges.first.end;

      var splitIndex = 0;
      for (final range in splitRanges.skip(1)) {
        if (splitIndex % 4 == 0 &&
            !await cooperativeCheckpoint(schedulerTask)) {
          return null;
        }
        splitIndex++;
        final candidateText = text.substring(currentStart, range.end);
        final candidateHeight = measureTextHeight(candidateText, original);

        if (candidateHeight <= chunkBudget) {
          currentEnd = range.end;
          continue;
        }

        subChunks.add(
          buildSplitChunk(
            original,
            currentStart,
            currentEnd,
            trailingBoundaryKind: ReaderTextBoundaryKind.word,
          ),
        );
        currentStart = range.start;
        currentEnd = range.end;
      }

      subChunks.add(
        buildSplitChunk(
          original,
          currentStart,
          currentEnd,
          trailingBoundaryKind: splitRanges.last.trailingBoundaryKind,
        ),
      );
      return subChunks.isNotEmpty ? subChunks : [original];
    }

    bool shareLogicalParagraph(BookChunk first, BookChunk second) {
      final firstId = first.logicalParagraphId;
      final secondId = second.logicalParagraphId;
      if (firstId != null && secondId != null) {
        return firstId == secondId &&
            first.logicalParagraphEndOffset ==
                second.logicalParagraphStartOffset;
      }

      final firstRanges = first.effectiveSourceRanges;
      final secondRanges = second.effectiveSourceRanges;
      if (firstRanges.isEmpty || secondRanges.isEmpty) return false;

      final lastFirstRange = firstRanges.last;
      final firstSecondRange = secondRanges.first;
      return lastFirstRange.originalChunkIndex ==
              firstSecondRange.originalChunkIndex &&
          lastFirstRange.originalEndOffset ==
              firstSecondRange.originalStartOffset;
    }

    String mergeSeparator(BookChunk first, BookChunk second) {
      return shareLogicalParagraph(first, second) ? '' : '\n\n';
    }

    BookChunk mergeChunks(BookChunk first, BookChunk second) {
      final firstText = first.text ?? '';
      final secondText = second.text ?? '';
      final separator = mergeSeparator(first, second);
      final secondOffset = firstText.length + separator.length;
      final sameParagraph = separator.isEmpty;
      final mergedListSegments = _mergeBookListDisplaySegments(
        first,
        second,
        secondOffset,
        separator.length,
      );

      final mergedSourceRanges = <ChunkSourceRange>[
        ...first.effectiveSourceRanges,
        ...second.effectiveSourceRanges.map(
          (range) => range.shiftDisplayOffsets(secondOffset),
        ),
      ];

      return BookChunk(
        index: first.index,
        type: BookChunkType.text,
        section: first.section,
        sourceFile: first.sourceFile,
        isHeading: first.isHeading,
        isDialogue: first.isDialogue && second.isDialogue,
        blockRole: first.blockRole,
        publisherTextAlign: first.publisherTextAlign,
        publisherLeftIndent: first.publisherLeftIndent,
        publisherRightIndent: first.publisherRightIndent,
        preserveLineBreaks: first.preserveLineBreaks,
        preserveWhitespace: first.preserveWhitespace,
        text: '$firstText$separator$secondText',
        links: combineLists(
          first.links,
          shiftLinks(second.links, secondOffset),
        ),
        inlineStyles: combineLists(
          first.inlineStyles,
          shiftInlineStyles(second.inlineStyles, secondOffset),
        ),
        footnotes: combineLists(
          first.footnotes,
          shiftFootnotes(second.footnotes, secondOffset),
        ),
        sourceRanges: mergedSourceRanges,
        logicalParagraphId: sameParagraph ? first.logicalParagraphId : null,
        logicalParagraphStartOffset: sameParagraph
            ? first.logicalParagraphStartOffset
            : 0,
        logicalParagraphEndOffset: sameParagraph
            ? second.logicalParagraphEndOffset
            : null,
        isLogicalParagraphStart: sameParagraph && first.isLogicalParagraphStart,
        isLogicalParagraphEnd: sameParagraph && second.isLogicalParagraphEnd,
        listDisplaySegments: mergedListSegments,
        textBoundaries: [
          ...?first.textBoundaries,
          if (!sameParagraph)
            DisplayTextBoundary(
              offset: firstText.length,
              kind: ReaderTextBoundaryKind.structural,
              synthesizedTextLength: separator.length,
            ),
          ...?second.textBoundaries?.map(
            (boundary) => boundary.shift(secondOffset),
          ),
        ],
      );
    }

    double chunkHeight(BookChunk chunk) {
      final contractBlock = resolveContractBlock(chunk);
      if (contractBlock != null) {
        return ReaderLayoutMeasurementAdapter.blockHeight(contractBlock);
      }
      final text = chunk.text ?? '';
      if (text.isEmpty) return 0.0;
      return measureTextHeight(text, chunk);
    }

    bool isTinyChunk(BookChunk chunk, double height) {
      final text = chunk.text ?? '';
      if (text.isEmpty) return true;
      final budget = heightBudgetFor(chunk);
      final fillRatio = budget <= 0 ? 1.0 : height / budget;
      return readerLayoutWordCount(text) <= layout.tinyWordCount ||
          height <= layout.minUsefulHeight ||
          fillRatio <= layout.tinyHeightRatio;
    }

    bool canUseSoftBodyMerge(BookChunk first, BookChunk second) {
      return !first.isHeading &&
          !second.isHeading &&
          !first.usesPublisherLayout &&
          !second.usesPublisherLayout;
    }

    bool shouldMergeChunks(
      BookChunk pendingChunk,
      BookChunk nextChunk, {
      required double pendingHeight,
      required double nextHeight,
      required double mergedHeight,
    }) {
      if (!readerChunksShareHardMergeBoundary(pendingChunk, nextChunk) ||
          mergedHeight > heightBudgetFor(pendingChunk)) {
        return false;
      }

      final mergeTiny =
          isTinyChunk(pendingChunk, pendingHeight) ||
          isTinyChunk(nextChunk, nextHeight);
      final matchingPresentation =
          pendingChunk.isDialogue == nextChunk.isDialogue;
      if (matchingPresentation) return true;
      if (!canUseSoftBodyMerge(pendingChunk, nextChunk)) return false;
      return mergeTiny;
    }

    List<int> rebalanceSplitOffsets(String text) {
      final offsets = <int>{};
      for (final range in readerSentenceRanges(text)) {
        if (range.end > 0 && range.end < text.length) offsets.add(range.end);
      }
      return offsets.toList()..sort((a, b) => b.compareTo(a));
    }

    var consumedEndExclusive = input.startCursor.isLogicalEnd
        ? input.snapshot.sourceCount
        : input.startCursor.sourceOrdinalHint;
    final finalized = <_EngineFinalizedCard>[];
    _EngineCandidate? deferredPredecessor;
    _EngineCandidate? pendingTail;

    CanonicalPaginationSourceSlice sliceForRange(
      BookChunk chunk,
      ChunkSourceRange range,
    ) {
      final owner = input.snapshot.ownerAt(range.originalChunkIndex);
      final source = sourceChunks[range.originalChunkIndex];
      if (source.blockRole == BookBlockRole.table) {
        final table = singleTableBlock(source.text ?? '');
        if (table == null) {
          throw const FormatException(
            'Canonical table ownership requires decodable row structure.',
          );
        }
        return _sourceSliceWithEvidence(
          owner: owner,
          source: source,
          fragment: source,
          sourceIdentity: owner.sourceIdentity,
          logicalOwnerIdentity:
              range.logicalParagraphId ??
              source.logicalParagraphId ??
              owner.sourceIdentity,
          tableRowStart: 0,
          tableRowEndExclusive: table.rows.length,
        );
      }
      final start = range.originalStartOffset;
      final end = range.originalEndOffset;
      final fullSource = start == 0 && end == (source.text?.length ?? 0);
      final chunkIsExactRange =
          chunk.effectiveSourceRanges.length == 1 &&
          range.displayStartOffset == 0 &&
          range.displayEndOffset == (chunk.text?.length ?? 0);
      final fragment = chunkIsExactRange
          ? chunk
          : fullSource
          ? source
          : buildSplitChunk(source, start, end);
      final usesExplicitTextFragment =
          fullSource &&
          canonicalJsonEncode(fragment.toJson()) !=
              canonicalJsonEncode(source.toJson());
      return _sourceSliceWithEvidence(
        owner: owner,
        source: source,
        fragment: fragment,
        sourceIdentity: owner.sourceIdentity,
        logicalOwnerIdentity:
            range.logicalParagraphId ??
            source.logicalParagraphId ??
            owner.sourceIdentity,
        startUtf16: start,
        endUtf16: end,
        usesExplicitTextFragment: usesExplicitTextFragment,
      );
    }

    CanonicalPaginationSourceSlice sliceForInterval({
      required CanonicalPaginationSourceOwner owner,
      required BookChunk source,
      required String logicalOwnerIdentity,
      int? startUtf16,
      int? endUtf16,
      int? tableRowStart,
      int? tableRowEndExclusive,
      bool usesExplicitTextFragment = false,
      ReaderTextBoundaryKind trailingBoundaryKind =
          ReaderTextBoundaryKind.structural,
    }) {
      late final BookChunk fragment;
      if (tableRowStart != null && tableRowEndExclusive != null) {
        final table = singleTableBlock(source.text ?? '')!;
        fragment = buildTableRowFragment(
          source,
          table,
          tableRowStart,
          tableRowEndExclusive,
        );
      } else if (startUtf16 != null && endUtf16 != null) {
        fragment =
            startUtf16 == 0 &&
                endUtf16 == (source.text?.length ?? 0) &&
                !usesExplicitTextFragment
            ? source
            : buildSplitChunk(
                source,
                startUtf16,
                endUtf16,
                trailingBoundaryKind: trailingBoundaryKind,
              );
      } else {
        fragment = source;
      }
      return _sourceSliceWithEvidence(
        owner: owner,
        source: source,
        fragment: fragment,
        sourceIdentity: owner.sourceIdentity,
        logicalOwnerIdentity: logicalOwnerIdentity,
        startUtf16: startUtf16,
        endUtf16: endUtf16,
        tableRowStart: tableRowStart,
        tableRowEndExclusive: tableRowEndExclusive,
        usesExplicitTextFragment: usesExplicitTextFragment,
      );
    }

    List<CanonicalPaginationSourceSlice> coalesceSlices(
      Iterable<CanonicalPaginationSourceSlice> inputSlices,
    ) {
      final result = <CanonicalPaginationSourceSlice>[];
      for (final slice in inputSlices) {
        if (result.isNotEmpty) {
          final previous = result.last;
          final sameOwner =
              previous.sourceIdentity == slice.sourceIdentity &&
              previous.sectionIdentity == slice.sectionIdentity &&
              previous.spineIdentity == slice.spineIdentity &&
              previous.sourceDigest == slice.sourceDigest &&
              previous.structuralType == slice.structuralType &&
              previous.logicalOwnerIdentity == slice.logicalOwnerIdentity;
          final contiguousText =
              previous.endUtf16 != null &&
              previous.endUtf16 == slice.startUtf16 &&
              previous.tableRowStart == null &&
              slice.tableRowStart == null;
          final contiguousRows =
              previous.tableRowEndExclusive != null &&
              previous.tableRowEndExclusive == slice.tableRowStart &&
              previous.startUtf16 == null &&
              slice.startUtf16 == null;
          if (sameOwner && (contiguousText || contiguousRows)) {
            final owner = input.snapshot.ownerAt(previous.sourceOrdinalHint);
            final source = sourceChunks[previous.sourceOrdinalHint];
            final trailingBoundaryKind = ReaderTextBoundaryKind.values
                .where((kind) => kind.name == slice.splitBoundaryKind)
                .firstOrNull;
            result[result.length - 1] = sliceForInterval(
              owner: owner,
              source: source,
              logicalOwnerIdentity: previous.logicalOwnerIdentity,
              startUtf16: contiguousText ? previous.startUtf16 : null,
              endUtf16: contiguousText ? slice.endUtf16 : null,
              tableRowStart: contiguousRows ? previous.tableRowStart : null,
              tableRowEndExclusive: contiguousRows
                  ? slice.tableRowEndExclusive
                  : null,
              usesExplicitTextFragment:
                  contiguousText &&
                  (previous.usesExplicitTextFragment ||
                      slice.usesExplicitTextFragment ||
                      (previous.startUtf16 == 0 &&
                          slice.endUtf16 == (source.text?.length ?? 0))),
              trailingBoundaryKind:
                  trailingBoundaryKind ?? ReaderTextBoundaryKind.structural,
            );
            continue;
          }
        }
        result.add(slice);
      }
      return result;
    }

    CanonicalPaginationFrontierCandidate descriptorFor(BookChunk chunk) {
      final tableInterval = tableRowIntervals[chunk];
      if (tableInterval != null) {
        final owner = input.snapshot.ownerAt(chunk.index);
        final source = sourceChunks[chunk.index];
        final logicalOwner = source.logicalParagraphId ?? owner.sourceIdentity;
        final slice = sliceForInterval(
          owner: owner,
          source: source,
          logicalOwnerIdentity: logicalOwner,
          tableRowStart: tableInterval.start,
          tableRowEndExclusive: tableInterval.endExclusive,
        );
        return CanonicalPaginationFrontierCandidate(
          sourceSlices: <CanonicalPaginationSourceSlice>[slice],
          reconstructedCardDigest: canonicalBookChunkOwnershipDigest(chunk),
        );
      }
      final slices = <CanonicalPaginationSourceSlice>[];
      for (final range in chunk.effectiveSourceRanges) {
        slices.add(sliceForRange(chunk, range));
      }
      if (slices.isEmpty) {
        final owner = input.snapshot.ownerAt(chunk.index);
        final source = sourceChunks[chunk.index];
        slices.add(
          sliceForInterval(
            owner: owner,
            source: source,
            logicalOwnerIdentity:
                source.logicalParagraphId ?? owner.sourceIdentity,
            startUtf16: source.type == BookChunkType.text ? 0 : null,
            endUtf16: source.type == BookChunkType.text
                ? (source.text?.length ?? 0)
                : null,
          ),
        );
      }
      return CanonicalPaginationFrontierCandidate(
        sourceSlices: coalesceSlices(slices),
        reconstructedCardDigest: canonicalBookChunkOwnershipDigest(chunk),
      );
    }

    _EngineCandidate? reconstructCandidate(
      List<CanonicalPaginationSourceSlice> sourceSlices, {
      String? storedDigest,
    }) {
      BookChunk? rebuilt;
      final originals = <int>[];
      final descriptorKeys = <String>{};
      for (var sliceIndex = 0; sliceIndex < sourceSlices.length; sliceIndex++) {
        final slice = sourceSlices[sliceIndex];
        final ordinal = input.snapshot.resolveOrdinal(
          sourceIdentity: slice.sourceIdentity,
          ordinalHint: slice.sourceOrdinalHint,
        );
        if (ordinal == null ||
            input.snapshot.ownerAt(ordinal).sourceDigest !=
                slice.sourceDigest) {
          diagnostic(
            'canonical_frontier_reconstruction_mismatch',
            <String, Object?>{
              'kind': 'source_owner',
              'sliceIndex': sliceIndex,
              'sourceIdentity': slice.sourceIdentity,
              'sourceOrdinalHint': slice.sourceOrdinalHint,
            },
          );
          return null;
        }
        final owner = input.snapshot.ownerAt(ordinal);
        final source = sourceChunks[ordinal];
        final start = slice.startUtf16;
        final end = slice.endUtf16;
        final rowStart = slice.tableRowStart;
        final rowEnd = slice.tableRowEndExclusive;
        late final BookChunk part;
        if (rowStart != null && rowEnd != null) {
          final table = singleTableBlock(source.text ?? '');
          if (table == null ||
              rowStart < 0 ||
              rowEnd <= rowStart ||
              rowEnd > table.rows.length) {
            return null;
          }
          part = buildTableRowFragment(source, table, rowStart, rowEnd);
        } else {
          ReaderTextBoundaryKind? boundaryKind;
          if (slice.splitBoundaryKind != 'none') {
            boundaryKind = ReaderTextBoundaryKind.values
                .where((kind) => kind.name == slice.splitBoundaryKind)
                .firstOrNull;
            if (boundaryKind == null) return null;
          }
          if (start != null && end != null) {
            final text = source.text ?? '';
            final graphemeBoundaries = <int>{0, text.length};
            for (final range in _readerTextBoundaryService.graphemeRanges(
              text,
            )) {
              graphemeBoundaries
                ..add(range.start)
                ..add(range.end);
            }
            if (!graphemeBoundaries.contains(start) ||
                !graphemeBoundaries.contains(end)) {
              return null;
            }
          }
          part =
              start == null ||
                  end == null ||
                  (start == 0 &&
                      end == (source.text?.length ?? 0) &&
                      !slice.usesExplicitTextFragment)
              ? source
              : buildSplitChunk(
                  source,
                  start,
                  end,
                  trailingBoundaryKind:
                      boundaryKind ?? ReaderTextBoundaryKind.structural,
                );
        }
        final expectedSlice = _sourceSliceWithEvidence(
          owner: owner,
          source: source,
          fragment: part,
          sourceIdentity: owner.sourceIdentity,
          logicalOwnerIdentity: slice.logicalOwnerIdentity,
          startUtf16: start,
          endUtf16: end,
          tableRowStart: rowStart,
          tableRowEndExclusive: rowEnd,
          usesExplicitTextFragment: slice.usesExplicitTextFragment,
        );
        if (canonicalJsonEncode(expectedSlice.toCanonicalJson()) !=
            canonicalJsonEncode(slice.toCanonicalJson())) {
          diagnostic(
            'canonical_frontier_reconstruction_mismatch',
            <String, Object?>{
              'kind': 'source_slice',
              'sliceIndex': sliceIndex,
              'stored': slice.toCanonicalJson(),
              'reconstructed': expectedSlice.toCanonicalJson(),
            },
          );
          return null;
        }
        final descriptorKey = canonicalJsonEncode(slice.toCanonicalJson());
        if (!descriptorKeys.add(descriptorKey)) return null;
        rebuilt = rebuilt == null ? part : mergeChunks(rebuilt, part);
        if (!originals.contains(ordinal)) originals.add(ordinal);
      }
      if (rebuilt == null) return null;
      final reconstructedDigest = canonicalBookChunkOwnershipDigest(rebuilt);
      if (storedDigest != null && reconstructedDigest != storedDigest) {
        diagnostic(
          'canonical_frontier_reconstruction_mismatch',
          <String, Object?>{
            'kind': 'card_digest',
            'storedDigest': storedDigest,
            'reconstructedDigest': reconstructedDigest,
            'sourceSlices': sourceSlices
                .map((slice) => slice.toCanonicalJson())
                .toList(growable: false),
          },
        );
        return null;
      }
      return _EngineCandidate(
        chunk: rebuilt,
        originals: List<int>.unmodifiable(originals),
        descriptor: CanonicalPaginationFrontierCandidate(
          sourceSlices: sourceSlices,
          reconstructedCardDigest: reconstructedDigest,
        ),
      );
    }

    _EngineCandidate candidateFor(BookChunk chunk, List<int> originals) {
      final descriptor = descriptorFor(chunk);
      final candidate = reconstructCandidate(descriptor.sourceSlices);
      if (candidate == null) {
        throw const FormatException(
          'Kernel candidate could not be normalized from source ownership.',
        );
      }
      return _EngineCandidate(
        chunk: candidate.chunk,
        originals: List<int>.unmodifiable(originals),
        descriptor: candidate.descriptor,
      );
    }

    _EngineCandidate mergeCandidates(
      _EngineCandidate first,
      _EngineCandidate second,
    ) {
      final originals = <int>[...first.originals];
      for (final ordinal in second.originals) {
        if (!originals.contains(ordinal)) originals.add(ordinal);
      }
      final candidate = reconstructCandidate(
        coalesceSlices(<CanonicalPaginationSourceSlice>[
          ...first.descriptor.sourceSlices,
          ...second.descriptor.sourceSlices,
        ]),
      );
      if (candidate == null) {
        throw const FormatException(
          'Merged kernel candidate could not be normalized from source ownership.',
        );
      }
      return _EngineCandidate(
        chunk: candidate.chunk,
        originals: List<int>.unmodifiable(originals),
        descriptor: candidate.descriptor,
      );
    }

    int candidateDescriptorBytes(_EngineCandidate? candidate) {
      var bytes = 0;
      if (candidate == null) return bytes;
      for (final slice in candidate.descriptor.sourceSlices) {
        bytes +=
            2 *
            (slice.sourceIdentity.length +
                slice.sectionIdentity.length +
                slice.spineIdentity.length +
                slice.sourceDigest.length +
                slice.structuralType.length +
                slice.logicalOwnerIdentity.length +
                slice.structuralDigest.length);
        bytes += 48;
      }
      return bytes;
    }

    int frontierBytes() =>
        candidateDescriptorBytes(deferredPredecessor) +
        candidateDescriptorBytes(pendingTail);

    CanonicalPaginationFrontier frontier() => CanonicalPaginationFrontier(
      deferredPredecessor: deferredPredecessor?.descriptor,
      pendingTail: pendingTail?.descriptor,
    );

    bool updateFrontierPeak({_EngineCandidate? proofAtom}) {
      final entries =
          frontier().structuralEntryCount +
          (proofAtom?.descriptor.sourceSlices.length ?? 0);
      peakFrontierEntries = math.max(peakFrontierEntries, entries);
      peakPrivateFrontierBytes = math.max(
        peakPrivateFrontierBytes,
        frontierBytes() + candidateDescriptorBytes(proofAtom),
      );
      return entries <= input.frontierEntryCap &&
          frontier().cardCandidateCount <= 2;
    }

    final rangeStopwatch = Stopwatch()..start();
    var staleObserved = false;
    var cardBudgetObserved = false;
    final schedulerTask = input.scheduler.startTask(
      id: input.generationToken,
      priority: input.priority,
      isExternallyCancelled: () {
        final current = input.currentGenerationToken?.call();
        staleObserved = current != null && current != input.generationToken;
        return staleObserved || input.isCancelled();
      },
    );

    Future<bool> checkpoint(
      String stage, {
      int sourceChunksProcessed = 0,
      int displayChunksProduced = 0,
    }) async {
      cancellationCheckpoints++;
      diagnostic('canonical_cancellation_checkpoint', <String, Object?>{
        'stage': stage,
        'generation': input.generationToken,
      });
      final current = input.currentGenerationToken?.call();
      if (current != null && current != input.generationToken) {
        staleObserved = true;
        return false;
      }
      if (input.isCancelled()) return false;
      return schedulerTask.checkpoint(
        sourceChunksProcessed: sourceChunksProcessed,
        displayChunksProduced: displayChunksProduced,
      );
    }

    _EngineStopKind interruptedKind() => cardBudgetObserved
        ? _EngineStopKind.budgetExhausted
        : staleObserved
        ? _EngineStopKind.stale
        : _EngineStopKind.cancelled;

    CanonicalPaginationWorkDiagnostics diagnostics() {
      final currentFrontier = frontier();
      return CanonicalPaginationWorkDiagnostics(
        sourceChunksEntered: sourceChunksEntered,
        sourceChunksFullyConsumed: sourceChunksFullyConsumed,
        atomicFragmentsProcessed: atomicFragmentsProcessed,
        referencedUtf16Extent: referencedUtf16Extent,
        tableRows: tableRows,
        graphemeCandidates: graphemeCandidates,
        rebalanceCandidates: rebalanceCandidates,
        cardsFinalized: cardsFinalized,
        frontierEntries: currentFrontier.structuralEntryCount,
        peakFrontierEntries: peakFrontierEntries,
        peakPrivateFrontierBytes: peakPrivateFrontierBytes,
        cancellationCheckpoints: cancellationCheckpoints,
      );
    }

    _EngineRunResult finish(
      _EngineStopKind kind,
      CanonicalPaginationCursor cursor, {
      String? message,
    }) {
      if (rangeStopwatch.isRunning) rangeStopwatch.stop();
      final metrics = schedulerTask.finish();
      final work = diagnostics();
      final withScheduler = CanonicalPaginationWorkDiagnostics(
        sourceChunksEntered: work.sourceChunksEntered,
        sourceChunksFullyConsumed: work.sourceChunksFullyConsumed,
        atomicFragmentsProcessed: work.atomicFragmentsProcessed,
        referencedUtf16Extent: work.referencedUtf16Extent,
        tableRows: work.tableRows,
        graphemeCandidates: work.graphemeCandidates,
        rebalanceCandidates: work.rebalanceCandidates,
        cardsFinalized: work.cardsFinalized,
        frontierEntries: work.frontierEntries,
        peakFrontierEntries: work.peakFrontierEntries,
        peakPrivateFrontierBytes: work.peakPrivateFrontierBytes,
        cancellationCheckpoints: work.cancellationCheckpoints,
        schedulerSlices: metrics.sliceCount,
        schedulerYields: metrics.yieldCount,
      );
      return _EngineRunResult(
        kind: kind,
        finalizedCards: List<_EngineFinalizedCard>.unmodifiable(finalized),
        frontier: frontier(),
        nextCursor: cursor,
        diagnostics: withScheduler,
        elapsedMilliseconds: rangeStopwatch.elapsedMilliseconds,
        sliceCount: metrics.sliceCount,
        yieldCount: metrics.yieldCount,
        longestWorkIntervalMilliseconds:
            metrics.longestWorkInterval.inMilliseconds,
        maxSliceDurationMilliseconds: metrics.maxSliceDuration.inMilliseconds,
        totalYieldMilliseconds: metrics.totalYieldDuration.inMilliseconds,
        maxSourceChunksPerSlice: metrics.maxSourceChunksPerSlice,
        maxDisplayChunksPerSlice: metrics.maxDisplayChunksPerSlice,
        cancellationLatencyMilliseconds:
            metrics.cancellationLatency?.inMilliseconds,
        inspectedSourceChunks: inspectedSourceChunks,
        consumedEndExclusive: consumedEndExclusive,
        message: message,
      );
    }

    Future<bool> emit(_EngineCandidate candidate) async {
      if (cardsFinalized >= input.workBudget.maxFinalizedCards) {
        cardBudgetObserved = true;
        return false;
      }
      if (!await checkpoint('before_finalization')) return false;
      finalized.add(
        _EngineFinalizedCard(
          chunk: candidate.chunk,
          originals: candidate.originals,
          descriptor: candidate.descriptor,
          resolvedLayout: switch (resolveContractBlock(candidate.chunk)) {
            final block? => ReaderCardLayoutResolver.resolve(
              contract: layout.contract!,
              block: block,
              physicalSourceIdentity: canonicalBookChunkOwnershipDigest(
                candidate.chunk,
              ),
            ),
            null => null,
          },
        ),
      );
      cardsFinalized++;
      diagnostic('canonical_card_finalized', <String, Object?>{
        'cardsFinalized': cardsFinalized,
        'sourceSlices': candidate.descriptor.sourceSlices.length,
      });
      return checkpoint('after_finalization', displayChunksProduced: 1);
    }

    bool canAttach(_EngineCandidate predecessor, _EngineCandidate tail) {
      final tailHeight = chunkHeight(tail.chunk);
      if (!isTinyChunk(tail.chunk, tailHeight) ||
          !readerCanAttemptDisplayMerge(predecessor.chunk, tail.chunk)) {
        return false;
      }
      final merged = mergeChunks(predecessor.chunk, tail.chunk);
      return chunkHeight(merged) <= heightBudgetFor(predecessor.chunk);
    }

    Future<bool> resolveCompletedFrontier() async {
      final predecessor = deferredPredecessor;
      final tail = pendingTail;
      if (predecessor != null && tail != null) {
        if (canAttach(predecessor, tail)) {
          diagnostic('canonical_frontier_transition', <String, Object?>{
            'transition': 'tiny_tail_backward_attachment',
          });
          if (!await emit(mergeCandidates(predecessor, tail))) return false;
          deferredPredecessor = null;
          pendingTail = null;
          return true;
        }
        if (!await emit(predecessor)) return false;
        deferredPredecessor = null;
        if (!await emit(tail)) return false;
        pendingTail = null;
        return true;
      }
      if (predecessor != null) {
        if (!await emit(predecessor)) return false;
        deferredPredecessor = null;
      }
      if (tail != null) {
        if (!await emit(tail)) return false;
        pendingTail = null;
      }
      return true;
    }

    Future<bool> releaseDeferredWhenProven() async {
      final predecessor = deferredPredecessor;
      final tail = pendingTail;
      if (predecessor == null || tail == null) return true;
      if (canAttach(predecessor, tail)) return true;
      diagnostic('canonical_frontier_transition', <String, Object?>{
        'transition': 'tiny_tail_attachment_became_impossible',
      });
      if (!await emit(predecessor)) return false;
      deferredPredecessor = null;
      return true;
    }

    bool targetIsFinalized() {
      final target = input.target;
      return target != null &&
          finalized.any(
            (card) => card.descriptor.sourceSlices.any(
              (slice) => _canonicalSliceContainsTarget(slice, target),
            ),
          );
    }

    bool targetSourceIsFullyAdvanced(CanonicalPaginationCursor nextCursor) {
      final target = input.target;
      if (target == null) return true;
      final cursorAdvanced =
          nextCursor.isLogicalEnd ||
          nextCursor.sourceIdentity != target.sourceIdentity;
      if (!cursorAdvanced) return false;
      return <_EngineCandidate?>[deferredPredecessor, pendingTail].every(
        (candidate) =>
            candidate == null ||
            candidate.descriptor.sourceSlices.every(
              (slice) => slice.sourceIdentity != target.sourceIdentity,
            ),
      );
    }

    Future<(_EngineCandidate, _EngineCandidate)?> tryRebalance(
      _EngineCandidate pending,
      _EngineCandidate next,
    ) async {
      final pendingChunk = pending.chunk;
      final nextChunk = next.chunk;
      if (pendingChunk.usesPublisherLayout || nextChunk.usesPublisherLayout) {
        return null;
      }
      if (pendingChunk.effectiveListDisplaySegments.isNotEmpty ||
          nextChunk.effectiveListDisplaySegments.isNotEmpty) {
        return null;
      }
      final nextHeight = chunkHeight(nextChunk);
      if (!isTinyChunk(nextChunk, nextHeight) ||
          !readerCanAttemptDisplayMerge(pendingChunk, nextChunk)) {
        return null;
      }
      final pendingText = pendingChunk.text ?? '';
      if (pendingText.isEmpty ||
          isTinyChunk(pendingChunk, chunkHeight(pendingChunk))) {
        return null;
      }

      var offsetIndex = 0;
      for (final splitOffset in rebalanceSplitOffsets(pendingText)) {
        rebalanceCandidates++;
        if (offsetIndex % 4 == 0 && !await checkpoint('during_rebalance')) {
          return null;
        }
        offsetIndex++;
        final headText = pendingText.substring(0, splitOffset).trim();
        final tailText = pendingText.substring(splitOffset).trim();
        if (headText.isEmpty || tailText.isEmpty) continue;
        final head = buildSplitChunk(
          pendingChunk,
          0,
          splitOffset,
          trailingBoundaryKind: ReaderTextBoundaryKind.sentence,
        );
        final tail = buildSplitChunk(
          pendingChunk,
          splitOffset,
          pendingText.length,
        );
        if (isTinyChunk(head, chunkHeight(head))) continue;
        final mergedTail = mergeChunks(tail, nextChunk);
        if (chunkHeight(mergedTail) > heightBudgetFor(tail)) continue;
        return (
          candidateFor(head, pending.originals),
          candidateFor(
            mergedTail,
            <int>{...pending.originals, ...next.originals}.toList(),
          ),
        );
      }
      return null;
    }

    _EngineCandidate? reconstruct(
      CanonicalPaginationFrontierCandidate? descriptor,
    ) {
      if (descriptor == null) return null;
      return reconstructCandidate(
        descriptor.sourceSlices,
        storedDigest: descriptor.reconstructedCardDigest,
      );
    }

    deferredPredecessor = reconstruct(
      input.initialFrontier.deferredPredecessor,
    );
    pendingTail = reconstruct(input.initialFrontier.pendingTail);
    if ((input.initialFrontier.deferredPredecessor != null &&
            deferredPredecessor == null) ||
        (input.initialFrontier.pendingTail != null && pendingTail == null)) {
      return finish(
        _EngineStopKind.invalid,
        input.startCursor,
        message: 'Provisional frontier could not be reconstructed exactly.',
      );
    }
    if (!updateFrontierPeak()) {
      return finish(
        _EngineStopKind.frontierBoundViolation,
        input.startCursor,
        message: 'Restored frontier exceeds ${input.frontierEntryCap} entries.',
      );
    }

    diagnostic(
      rangeRequest == null
          ? 'canonical_generation_begin'
          : 'range_generation_begin',
      <String, Object?>{
        'book': input.diagnosticBookId,
        'generation': input.generationToken,
        'sourceStart': input.startCursor.sourceOrdinalHint,
        'sourceEndExclusive': input.endSourceOrdinalExclusive,
        if (rangeRequest != null) 'direction': rangeRequest.direction.name,
        if (rangeRequest != null) 'reason': rangeRequest.reason,
      },
    );

    if (!await checkpoint('before_source_work')) {
      return finish(interruptedKind(), input.startCursor);
    }
    if (input.startCursor.isLogicalEnd) {
      if (!await resolveCompletedFrontier()) {
        return finish(interruptedKind(), input.startCursor);
      }
      if (!await checkpoint('before_result_assembly')) {
        return finish(interruptedKind(), input.startCursor);
      }
      if (targetIsFinalized()) {
        return finish(_EngineStopKind.targetFinalized, input.startCursor);
      }
      return finish(
        _EngineStopKind.logicalEnd,
        const CanonicalPaginationCursor.logicalEnd(),
      );
    }

    var nextCursor = input.startCursor;
    var sourceIndex = input.startCursor.sourceOrdinalHint;
    var stopForLegacyAnchor = false;
    while (sourceIndex < input.endSourceOrdinalExclusive) {
      if (sourceChunksEntered >= input.workBudget.maxSourceChunks) {
        return finish(_EngineStopKind.budgetExhausted, nextCursor);
      }
      if (!await checkpoint('before_source')) {
        return finish(interruptedKind(), nextCursor);
      }
      final owner = input.snapshot.ownerAt(sourceIndex);
      if (owner.sourceIdentity != nextCursor.sourceIdentity ||
          owner.sectionIdentity != nextCursor.sectionIdentity) {
        return finish(
          _EngineStopKind.invalid,
          nextCursor,
          message: 'Next cursor does not match its stable source owner.',
        );
      }

      sourceChunksEntered++;
      final originalChunk = sourceChunks[sourceIndex];
      diagnostic('canonical_split_begin', <String, Object?>{
        'sourceIdentity': owner.sourceIdentity,
        'sourceOrdinalHint': sourceIndex,
      });
      final subChunks = await splitChunkByHeight(originalChunk, schedulerTask);
      if (subChunks == null) {
        return finish(interruptedKind(), nextCursor);
      }
      final startOffset = sourceIndex == input.startCursor.sourceOrdinalHint
          ? input.startCursor.textOffsetUtf16
          : 0;
      final startTableRow =
          sourceIndex == input.startCursor.sourceOrdinalHint &&
              input.startCursor.kind == CanonicalPaginationCursorKind.tableRow
          ? input.startCursor.tableRowIndex
          : null;
      final usable = <BookChunk>[];
      var foundRestartBoundary = startOffset == 0 && startTableRow == null;
      for (final chunk in subChunks) {
        final tableInterval = tableRowIntervals[chunk];
        if (startTableRow != null && tableInterval != null) {
          if (foundRestartBoundary) {
            usable.add(chunk);
            continue;
          }
          if (tableInterval.endExclusive <= startTableRow) continue;
          if (tableInterval.start != startTableRow) {
            return finish(
              _EngineStopKind.invalid,
              nextCursor,
              message: 'Restart row is not an atomic table split boundary.',
            );
          }
          foundRestartBoundary = true;
          usable.add(chunk);
          continue;
        }
        final ranges = chunk.effectiveSourceRanges
            .where((range) => range.originalChunkIndex == sourceIndex)
            .toList();
        if (startOffset == 0 || ranges.isEmpty || foundRestartBoundary) {
          usable.add(chunk);
          continue;
        }
        final start = ranges.first.originalStartOffset;
        final end = ranges.last.originalEndOffset;
        if (end <= startOffset) continue;
        if (start != startOffset) {
          return finish(
            _EngineStopKind.invalid,
            nextCursor,
            message: 'Restart offset is not an atomic split boundary.',
          );
        }
        foundRestartBoundary = true;
        usable.add(chunk);
      }
      if (!foundRestartBoundary) {
        return finish(
          _EngineStopKind.invalid,
          nextCursor,
          message:
              'Restart offset did not resolve to an atomic split boundary.',
        );
      }

      for (var subIndex = 0; subIndex < usable.length; subIndex++) {
        if (atomicFragmentsProcessed >= input.workBudget.maxAtomicFragments) {
          return finish(_EngineStopKind.budgetExhausted, nextCursor);
        }
        if (!await checkpoint('before_atomic_fragment')) {
          return finish(interruptedKind(), nextCursor);
        }
        final chunk = usable[subIndex];
        if (chunk.type == BookChunkType.text && (chunk.text?.isEmpty ?? true)) {
          nextCursor = sourceIndex + 1 < input.endSourceOrdinalExclusive
              ? _sourceStartCursor(input.snapshot, sourceIndex + 1)
              : const CanonicalPaginationCursor.logicalEnd();
          continue;
        }
        final next = candidateFor(chunk, <int>[sourceIndex]);
        final cursorBeforeAtom = nextCursor;
        atomicFragmentsProcessed++;
        referencedUtf16Extent += next.descriptor.referencedUtf16Extent;
        if (subIndex + 1 < usable.length) {
          final following = usable[subIndex + 1];
          final followingTableInterval = tableRowIntervals[following];
          if (followingTableInterval != null) {
            nextCursor = CanonicalPaginationCursor(
              kind: CanonicalPaginationCursorKind.tableRow,
              sourceIdentity: owner.sourceIdentity,
              sectionIdentity: owner.sectionIdentity,
              sourceOrdinalHint: sourceIndex,
              tableRowIndex: followingTableInterval.start,
            );
          } else {
            final nextRange = following.effectiveSourceRanges.first;
            nextCursor = CanonicalPaginationCursor(
              kind: CanonicalPaginationCursorKind.sourceText,
              sourceIdentity: owner.sourceIdentity,
              sectionIdentity: owner.sectionIdentity,
              sourceOrdinalHint: sourceIndex,
              textOffsetUtf16: nextRange.originalStartOffset,
            );
          }
        } else if (sourceIndex + 1 < input.endSourceOrdinalExclusive) {
          nextCursor = _sourceStartCursor(input.snapshot, sourceIndex + 1);
        } else {
          nextCursor = const CanonicalPaginationCursor.logicalEnd();
        }
        if (!updateFrontierPeak(proofAtom: next)) {
          return finish(
            _EngineStopKind.frontierBoundViolation,
            nextCursor,
            message:
                'Frontier plus proof atom exceeded ${input.frontierEntryCap} entries.',
          );
        }

        if (pendingTail == null) {
          pendingTail = next;
        } else {
          final pending = pendingTail!;
          final hardCompatible = readerCanAttemptDisplayMerge(
            pending.chunk,
            next.chunk,
          );
          if (!hardCompatible) {
            diagnostic('canonical_frontier_transition', <String, Object?>{
              'transition': 'hard_structural_boundary',
            });
            if (!await resolveCompletedFrontier()) {
              return finish(
                interruptedKind(),
                cardBudgetObserved ? cursorBeforeAtom : nextCursor,
              );
            }
            pendingTail = next;
          } else {
            final pendingHeight = chunkHeight(pending.chunk);
            final nextHeight = chunkHeight(next.chunk);
            final merged = mergeCandidates(pending, next);
            final mergedHeight = chunkHeight(merged.chunk);
            if (shouldMergeChunks(
              pending.chunk,
              next.chunk,
              pendingHeight: pendingHeight,
              nextHeight: nextHeight,
              mergedHeight: mergedHeight,
            )) {
              diagnostic('canonical_frontier_transition', <String, Object?>{
                'transition': 'direct_compatible_merge',
              });
              pendingTail = merged;
              if (!await releaseDeferredWhenProven()) {
                return finish(
                  interruptedKind(),
                  cardBudgetObserved ? cursorBeforeAtom : nextCursor,
                );
              }
            } else {
              diagnostic('canonical_frontier_transition', <String, Object?>{
                'transition': 'measured_merge_failure',
              });
              final rebalanced = await tryRebalance(pending, next);
              final currentGeneration = input.currentGenerationToken?.call();
              if (input.isCancelled() ||
                  (currentGeneration != null &&
                      currentGeneration != input.generationToken)) {
                staleObserved =
                    currentGeneration != null &&
                    currentGeneration != input.generationToken;
                return finish(
                  interruptedKind(),
                  cardBudgetObserved ? cursorBeforeAtom : nextCursor,
                );
              }
              if (rebalanced != null) {
                diagnostic('canonical_frontier_transition', <String, Object?>{
                  'transition': 'sentence_rebalance',
                });
                if (deferredPredecessor != null) {
                  final old = deferredPredecessor!;
                  if (!await emit(old)) {
                    return finish(
                      interruptedKind(),
                      cardBudgetObserved ? cursorBeforeAtom : nextCursor,
                    );
                  }
                  deferredPredecessor = null;
                }
                deferredPredecessor = rebalanced.$1;
                pendingTail = rebalanced.$2;
              } else {
                final old = deferredPredecessor;
                if (old != null) {
                  if (canAttach(old, pending)) {
                    if (!await emit(mergeCandidates(old, pending))) {
                      return finish(
                        interruptedKind(),
                        cardBudgetObserved ? cursorBeforeAtom : nextCursor,
                      );
                    }
                    deferredPredecessor = null;
                    pendingTail = null;
                  } else {
                    if (!await emit(old)) {
                      return finish(
                        interruptedKind(),
                        cardBudgetObserved ? cursorBeforeAtom : nextCursor,
                      );
                    }
                    deferredPredecessor = null;
                    deferredPredecessor = pending;
                  }
                } else {
                  deferredPredecessor = pending;
                }
                pendingTail = next;
              }
            }
          }
        }

        if (!updateFrontierPeak()) {
          return finish(
            _EngineStopKind.frontierBoundViolation,
            nextCursor,
            message: 'Canonical frontier exceeded its two-card entry cap.',
          );
        }

        final legacyAnchor = input.legacyAnchor;
        if (legacyAnchor != null &&
            readerAnchoredCardBoundaryIsFinalized(
              emittedCards: finalized.map((card) => card.chunk).toList(),
              pendingCard: pendingTail?.chunk,
              sourceIndex: legacyAnchor.sourceIndex,
              textOffset: legacyAnchor.textOffset,
            )) {
          stopForLegacyAnchor = true;
          break;
        }
        if (targetIsFinalized() && targetSourceIsFullyAdvanced(nextCursor)) {
          if (!await checkpoint('before_result_assembly')) {
            return finish(interruptedKind(), nextCursor);
          }
          return finish(_EngineStopKind.targetFinalized, nextCursor);
        }
        if (cardsFinalized >= input.workBudget.maxFinalizedCards) {
          if (subIndex == usable.length - 1) {
            inspectedSourceChunks++;
            sourceChunksFullyConsumed++;
            consumedEndExclusive = sourceIndex + 1;
          }
          return finish(_EngineStopKind.budgetExhausted, nextCursor);
        }
      }

      inspectedSourceChunks++;
      sourceChunksFullyConsumed++;
      consumedEndExclusive = sourceIndex + 1;
      if (!await checkpoint('after_source', sourceChunksProcessed: 1)) {
        return finish(interruptedKind(), nextCursor);
      }
      if (stopForLegacyAnchor) break;
      if (input.terminalPolicy ==
              _EngineTerminalPolicy.canonicalLogicalEndOnly &&
          sourceIndex + 1 < input.endSourceOrdinalExclusive &&
          input.snapshot.ownerAt(sourceIndex + 1).sectionIdentity !=
              owner.sectionIdentity) {
        if (!await resolveCompletedFrontier()) {
          return finish(interruptedKind(), nextCursor);
        }
        if (!await checkpoint('before_result_assembly')) {
          return finish(interruptedKind(), nextCursor);
        }
        return finish(_EngineStopKind.sectionBoundary, nextCursor);
      }
      sourceIndex++;
    }

    final isTrustedLogicalEnd =
        !stopForLegacyAnchor &&
        input.endSourceOrdinalExclusive == input.snapshot.sourceCount;
    if (isTrustedLogicalEnd ||
        input.terminalPolicy == _EngineTerminalPolicy.legacyRequestEnd) {
      if (!await resolveCompletedFrontier()) {
        return finish(interruptedKind(), nextCursor);
      }
      if (!await checkpoint('before_result_assembly')) {
        return finish(interruptedKind(), nextCursor);
      }
      if (targetIsFinalized() && targetSourceIsFullyAdvanced(nextCursor)) {
        return finish(_EngineStopKind.targetFinalized, nextCursor);
      }
      return finish(
        isTrustedLogicalEnd
            ? _EngineStopKind.logicalEnd
            : _EngineStopKind.legacyRequestEnd,
        isTrustedLogicalEnd
            ? const CanonicalPaginationCursor.logicalEnd()
            : nextCursor,
      );
    }
    return finish(_EngineStopKind.budgetExhausted, nextCursor);
  }

  (CanonicalPaginationRejectionReason, String)? _validateCanonicalRequest(
    CanonicalPaginationRequest request,
  ) {
    final snapshot = request.sourceSnapshot;
    if (request.bookId.isEmpty ||
        request.publicationFingerprint.isEmpty ||
        request.controlledLayoutIdentity.isEmpty ||
        request.paginationAlgorithmIdentity.isEmpty ||
        request.paginationAlgorithmIdentity !=
            readerPaginationAlgorithmVersion ||
        request.bookId != snapshot.bookId ||
        request.publicationFingerprint != snapshot.publicationFingerprint) {
      return (
        CanonicalPaginationRejectionReason.requestIdentityMismatch,
        'Request publication/layout/pagination identity is incomplete or '
            'does not match the pinned source snapshot.',
      );
    }
    if (snapshot.sourceCount > CanonicalPaginationBounds.activeSourceCeiling) {
      return (
        CanonicalPaginationRejectionReason.invalidBudget,
        'Pinned active source window exceeds '
            '${CanonicalPaginationBounds.activeSourceCeiling} sources.',
      );
    }
    final budget = request.workBudget;
    if (budget.maxSourceChunks <= 0 ||
        budget.maxSourceChunks >
            CanonicalPaginationBounds.activeSourceCeiling ||
        budget.maxAtomicFragments <= 0 ||
        budget.maxAtomicFragments > budget.envelope.maxEntries ||
        budget.maxFinalizedCards <= 0 ||
        budget.maxFinalizedCards >
            CanonicalPaginationBounds.activeCardCeiling ||
        (budget.maxFrontierEntries != null &&
            budget.maxFrontierEntries! <= 0)) {
      return (
        CanonicalPaginationRejectionReason.invalidBudget,
        'Canonical source, fragment, card, or frontier budget is invalid.',
      );
    }

    final restart = request.restart;
    if (restart is CanonicalPaginationTrustedSectionStart) {
      if (!snapshot.isTrustedSectionStart(
            restart.sourceOrdinalHint,
            restart.sectionIdentity,
          ) ||
          snapshot.resolveOrdinal(
                sourceIdentity: restart.sourceIdentity,
                ordinalHint: restart.sourceOrdinalHint,
              ) ==
              null) {
        return (
          CanonicalPaginationRejectionReason.invalidRestart,
          'Trusted section restart does not resolve to a proved section start.',
        );
      }
    } else if (restart is CanonicalPaginationContinuation) {
      final validation = _validateContinuationForRequest(request, restart);
      if (validation is CanonicalPaginationContinuationRejected) {
        return (
          _continuationRejectionReason(validation.kind),
          validation.message,
        );
      }
    } else if (restart is! CanonicalPaginationPublicationStart) {
      return (
        CanonicalPaginationRejectionReason.invalidRestart,
        'Unsupported canonical restart authority.',
      );
    }

    final target = request.target;
    if (target != null) {
      final ordinal = snapshot.resolveOrdinal(
        sourceIdentity: target.sourceIdentity,
        ordinalHint: target.sourceOrdinalHint,
      );
      if (ordinal == null ||
          snapshot.ownerAt(ordinal).sectionIdentity != target.sectionIdentity) {
        return (
          CanonicalPaginationRejectionReason.invalidTarget,
          'Target source owner does not resolve exactly.',
        );
      }
      final source = snapshot.resolveOrdinalSource(ordinal);
      final extent = source.text?.length ?? 0;
      if (target.textOffsetUtf16 < 0 || target.textOffsetUtf16 >= extent) {
        return (
          CanonicalPaginationRejectionReason.invalidTarget,
          'Target UTF-16 offset is outside its stable source.',
        );
      }
    }
    return null;
  }

  CanonicalPaginationContinuationValidationResult
  _validateContinuationForRequest(
    CanonicalPaginationRequest request,
    CanonicalPaginationContinuation continuation,
  ) {
    final decoded = CanonicalPaginationContinuationCodec.decode(
      continuation.canonicalEncoding,
    );
    if (decoded is CanonicalPaginationContinuationRejected) return decoded;
    final snapshot = request.sourceSnapshot;
    final key = continuation.key;
    if (key.bookId != request.bookId ||
        key.publicationFingerprint != request.publicationFingerprint) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind
            .incompatiblePublication,
        message: 'Continuation publication identity is incompatible.',
      );
    }
    if (key.parserSourceIdentity != snapshot.parserSourceIdentity ||
        key.sourceRevision != snapshot.sourceRevision ||
        key.sourceSnapshotDigest != snapshot.snapshotDigest) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind
            .incompatibleParserSourceSnapshot,
        message: 'Continuation parser/source snapshot is incompatible.',
      );
    }
    if (key.paginationAlgorithmIdentity !=
        request.paginationAlgorithmIdentity) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind
            .incompatiblePaginationIdentity,
        message: 'Continuation pagination identity is incompatible.',
      );
    }
    if (key.controlledLayoutIdentity != request.controlledLayoutIdentity) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind.incompatibleLayout,
        message: 'Continuation controlled-layout identity is incompatible.',
      );
    }
    if (continuation.terminal) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind
            .terminalStateContradiction,
        message: 'A terminal continuation cannot be resumed.',
      );
    }
    final parent = request.continuationParent;
    if (continuation.chainOrdinal == 0) {
      if (parent != null || continuation.parentDigest != null) {
        return const CanonicalPaginationContinuationRejected(
          kind: CanonicalPaginationContinuationValidationKind.brokenParentChain,
          message: 'A root continuation cannot claim a parent.',
        );
      }
    } else {
      if (parent == null) {
        return const CanonicalPaginationContinuationRejected(
          kind: CanonicalPaginationContinuationValidationKind.brokenParentChain,
          message: 'A non-root continuation requires its exact parent.',
        );
      }
      final parentDecoded = CanonicalPaginationContinuationCodec.decode(
        parent.canonicalEncoding,
      );
      if (parentDecoded is CanonicalPaginationContinuationRejected ||
          continuation.parentDigest != parent.integrityDigest) {
        return const CanonicalPaginationContinuationRejected(
          kind: CanonicalPaginationContinuationValidationKind.brokenParentChain,
          message: 'Continuation parent digest is missing or incorrect.',
        );
      }
      if (parent.terminal ||
          !_continuationIdentityMatches(parent.key, continuation.key) ||
          !_cursorResolves(snapshot, parent.nextSourceCursor)) {
        return const CanonicalPaginationContinuationRejected(
          kind: CanonicalPaginationContinuationValidationKind.staleForkReplay,
          message: 'Continuation parent belongs to another or terminal chain.',
        );
      }
      if (continuation.chainOrdinal != parent.chainOrdinal + 1) {
        return const CanonicalPaginationContinuationRejected(
          kind: CanonicalPaginationContinuationValidationKind.ordinalMismatch,
          message: 'Continuation chain ordinal is not the expected successor.',
        );
      }
      if (!continuation.startSourceCursor.samePositionAs(
        parent.nextSourceCursor,
      )) {
        return const CanonicalPaginationContinuationRejected(
          kind: CanonicalPaginationContinuationValidationKind.brokenParentChain,
          message: 'Continuation start cursor does not continue its parent.',
        );
      }
    }
    if (!key.boundaryCursor.samePositionAs(continuation.nextSourceCursor) ||
        !_cursorResolves(snapshot, continuation.startSourceCursor) ||
        !_cursorResolves(snapshot, continuation.nextSourceCursor) ||
        !_cursorResolves(
          snapshot,
          continuation.previousFinalizedBoundary.endCursor,
        )) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind
            .invalidCursorOffsetRowInterval,
        message: 'Continuation cursor does not resolve in the pinned source.',
      );
    }
    if ((!continuation.nextSourceCursor.isLogicalEnd &&
            key.sectionIdentity !=
                continuation.nextSourceCursor.sectionIdentity) ||
        _compareStableCursors(
              continuation.startSourceCursor,
              continuation.nextSourceCursor,
            ) >
            0) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind
            .invalidCursorOffsetRowInterval,
        message: 'Continuation section or cursor order is invalid.',
      );
    }
    if (!_frontierOwnersResolve(snapshot, continuation.frontier)) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind
            .invalidSectionSourceOwner,
        message: 'Continuation section/source owner is invalid.',
      );
    }
    if (!_frontierSourceDescriptorsResolve(snapshot, continuation.frontier)) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind.invalidFrontier,
        message: 'Continuation frontier owner/range evidence is invalid.',
      );
    }
    final expectedBoundaryEnd =
        _frontierStartCursor(continuation.frontier) ??
        continuation.nextSourceCursor;
    if (!continuation.previousFinalizedBoundary.endCursor.samePositionAs(
      expectedBoundaryEnd,
    )) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind.invalidFrontier,
        message: 'Finalized boundary does not meet the frontier exactly.',
      );
    }
    final frontierEnd = _frontierEndCursor(snapshot, continuation.frontier);
    if (frontierEnd != null &&
        !frontierEnd.samePositionAs(continuation.nextSourceCursor)) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind.invalidFrontier,
        message: 'Frontier end does not meet the next cursor exactly.',
      );
    }
    final cardIdentity = continuation.previousFinalizedBoundary.cardIdentity;
    if (cardIdentity != null &&
        (cardIdentity.publicationFingerprint !=
                request.publicationFingerprint ||
            cardIdentity.layoutFingerprint !=
                request.controlledLayoutIdentity ||
            cardIdentity.paginationVersion !=
                request.paginationAlgorithmIdentity ||
            !_finalizedBoundaryIdentityResolves(
              snapshot,
              continuation.previousFinalizedBoundary,
            ))) {
      return const CanonicalPaginationContinuationRejected(
        kind: CanonicalPaginationContinuationValidationKind.invalidFrontier,
        message: 'Previous finalized boundary identity is incompatible.',
      );
    }
    return CanonicalPaginationContinuationAccepted(continuation);
  }

  bool _continuationIdentityMatches(
    CanonicalPaginationContinuationKey first,
    CanonicalPaginationContinuationKey second,
  ) =>
      first.bookId == second.bookId &&
      first.publicationFingerprint == second.publicationFingerprint &&
      first.parserSourceIdentity == second.parserSourceIdentity &&
      first.sourceRevision == second.sourceRevision &&
      first.sourceSnapshotDigest == second.sourceSnapshotDigest &&
      first.paginationAlgorithmIdentity == second.paginationAlgorithmIdentity &&
      first.controlledLayoutIdentity == second.controlledLayoutIdentity;

  bool _finalizedBoundaryIdentityResolves(
    CanonicalPaginationSourceSnapshot snapshot,
    CanonicalPaginationFinalizedBoundary boundary,
  ) {
    final identity = boundary.cardIdentity;
    if (identity == null || identity.ranges.isEmpty) return false;
    final intervalKeys = <String>{};
    var previousOrdinal = -1;
    CanonicalPaginationCursor? derivedEnd;
    for (final range in identity.ranges) {
      final sourceIdentity = range.sourceIdentity;
      if (!range.hasCanonicalStructuralOwnership || sourceIdentity == null) {
        return false;
      }
      final matches = snapshot.owners
          .where(
            (owner) =>
                owner.sourceIdentity == sourceIdentity &&
                owner.sectionIdentity == range.sectionIdentity &&
                owner.spineIdentity == range.spineIdentity &&
                owner.sourceDigest == range.sectionChecksum,
          )
          .toList(growable: false);
      if (matches.length != 1 ||
          matches.single.sourceOrdinalHint < previousOrdinal) {
        return false;
      }
      final ordinal = matches.single.sourceOrdinalHint;
      previousOrdinal = ordinal;
      final owner = snapshot.ownerAt(ordinal);
      final source = snapshot.resolveOrdinalSource(ordinal);
      final expectedType = _canonicalStructuralType(source);
      final start = range.startUtf16;
      final end = range.endUtf16;
      final rowStart = range.tableRowStart;
      final tableEnd = range.tableRowEndExclusive;
      late final BookChunk fragment;
      if (start != null || end != null) {
        final text = source.text ?? '';
        if (start == null ||
            end == null ||
            start < 0 ||
            end <= start ||
            end > text.length ||
            range.structuralType != expectedType ||
            range.contentChecksum != null ||
            rowStart != null ||
            tableEnd != null ||
            !_isGraphemeBoundary(text, start) ||
            !_isGraphemeBoundary(text, end)) {
          return false;
        }
        final boundaryKind = ReaderTextBoundaryKind.values
            .where((kind) => kind.name == range.splitBoundaryKind)
            .firstOrNull;
        if (boundaryKind == null && range.splitBoundaryKind != 'none') {
          return false;
        }
        fragment =
            start == 0 &&
                end == text.length &&
                range.usesExplicitTextFragment != true
            ? source
            : buildCanonicalTextFragment(
                source,
                start,
                end,
                trailingBoundaryKind:
                    boundaryKind ?? ReaderTextBoundaryKind.structural,
              );
        derivedEnd = end < text.length
            ? CanonicalPaginationCursor(
                kind: CanonicalPaginationCursorKind.sourceText,
                sourceIdentity: owner.sourceIdentity,
                sectionIdentity: owner.sectionIdentity,
                sourceOrdinalHint: ordinal,
                textOffsetUtf16: end,
              )
            : ordinal + 1 < snapshot.sourceCount
            ? _sourceStartCursor(snapshot, ordinal + 1)
            : const CanonicalPaginationCursor.logicalEnd();
      } else {
        if (range.contentChecksum != owner.sourceDigest ||
            range.structuralType != expectedType) {
          return false;
        }
        if (rowStart != null || tableEnd != null) {
          final table = normalizedReaderTableFromText(source.text ?? '');
          if (rowStart == null ||
              tableEnd == null ||
              rowStart < 0 ||
              tableEnd <= rowStart ||
              table == null ||
              tableEnd > table.rows.length) {
            return false;
          }
          fragment = buildCanonicalTableRowFragment(
            source,
            table,
            rowStart,
            tableEnd,
          );
          derivedEnd = tableEnd < table.rows.length
              ? CanonicalPaginationCursor(
                  kind: CanonicalPaginationCursorKind.tableRow,
                  sourceIdentity: owner.sourceIdentity,
                  sectionIdentity: owner.sectionIdentity,
                  sourceOrdinalHint: ordinal,
                  tableRowIndex: tableEnd,
                )
              : ordinal + 1 < snapshot.sourceCount
              ? _sourceStartCursor(snapshot, ordinal + 1)
              : const CanonicalPaginationCursor.logicalEnd();
        } else {
          fragment = source;
          derivedEnd = ordinal + 1 < snapshot.sourceCount
              ? _sourceStartCursor(snapshot, ordinal + 1)
              : const CanonicalPaginationCursor.logicalEnd();
        }
      }
      final expectedSlice = _sourceSliceWithEvidence(
        owner: owner,
        source: source,
        fragment: fragment,
        sourceIdentity: owner.sourceIdentity,
        logicalOwnerIdentity: range.logicalBlockId,
        startUtf16: start,
        endUtf16: end,
        tableRowStart: rowStart,
        tableRowEndExclusive: tableEnd,
        usesExplicitTextFragment: range.usesExplicitTextFragment == true,
      );
      final expectedRange = CanonicalReaderCardIdentityBuilder.build(
        publicationFingerprint: identity.publicationFingerprint,
        controlledLayoutIdentity: identity.layoutFingerprint,
        paginationAlgorithmIdentity: identity.paginationVersion,
        orderedSourceSlices: <CanonicalPaginationSourceSlice>[expectedSlice],
      ).ranges.single;
      if (canonicalJsonEncode(expectedRange.toJson()) !=
          canonicalJsonEncode(range.toJson())) {
        return false;
      }
      final intervalKey = canonicalJsonEncode(<String, Object?>{
        'ordinal': ordinal,
        'start': start,
        'end': end,
        'tableStart': rowStart,
        'tableEnd': tableEnd,
      });
      if (!intervalKeys.add(intervalKey)) return false;
    }
    return derivedEnd != null && derivedEnd.samePositionAs(boundary.endCursor);
  }

  CanonicalPaginationRejectionReason _continuationRejectionReason(
    CanonicalPaginationContinuationValidationKind kind,
  ) => switch (kind) {
    CanonicalPaginationContinuationValidationKind.accepted =>
      CanonicalPaginationRejectionReason.invalidRestart,
    CanonicalPaginationContinuationValidationKind.unsupportedContractKind =>
      CanonicalPaginationRejectionReason.unsupportedContractKind,
    CanonicalPaginationContinuationValidationKind.corruptDigest =>
      CanonicalPaginationRejectionReason.corruptDigest,
    CanonicalPaginationContinuationValidationKind.incompatiblePublication =>
      CanonicalPaginationRejectionReason.incompatiblePublication,
    CanonicalPaginationContinuationValidationKind
        .incompatibleParserSourceSnapshot =>
      CanonicalPaginationRejectionReason.incompatibleParserSourceSnapshot,
    CanonicalPaginationContinuationValidationKind
        .incompatiblePaginationIdentity =>
      CanonicalPaginationRejectionReason.incompatiblePaginationIdentity,
    CanonicalPaginationContinuationValidationKind.incompatibleLayout =>
      CanonicalPaginationRejectionReason.incompatibleLayout,
    CanonicalPaginationContinuationValidationKind.invalidSectionSourceOwner =>
      CanonicalPaginationRejectionReason.invalidSectionSourceOwner,
    CanonicalPaginationContinuationValidationKind
        .invalidCursorOffsetRowInterval =>
      CanonicalPaginationRejectionReason.invalidCursorOffsetRowInterval,
    CanonicalPaginationContinuationValidationKind.invalidFrontier =>
      CanonicalPaginationRejectionReason.invalidFrontier,
    CanonicalPaginationContinuationValidationKind.brokenParentChain =>
      CanonicalPaginationRejectionReason.brokenParentChain,
    CanonicalPaginationContinuationValidationKind.ordinalMismatch =>
      CanonicalPaginationRejectionReason.ordinalMismatch,
    CanonicalPaginationContinuationValidationKind.staleForkReplay =>
      CanonicalPaginationRejectionReason.staleForkReplay,
    CanonicalPaginationContinuationValidationKind.terminalStateContradiction =>
      CanonicalPaginationRejectionReason.terminalStateContradiction,
    CanonicalPaginationContinuationValidationKind.boundViolation =>
      CanonicalPaginationRejectionReason.boundViolation,
    CanonicalPaginationContinuationValidationKind.requiredEarlierRestart =>
      CanonicalPaginationRejectionReason.requiredEarlierRestart,
  };

  bool _frontierSourceDescriptorsResolve(
    CanonicalPaginationSourceSnapshot snapshot,
    CanonicalPaginationFrontier frontier,
  ) {
    final intervalKeys = <String>{};
    var previousOrdinal = -1;
    int? previousTextEnd;
    int? previousRowEnd;
    for (final candidate in <CanonicalPaginationFrontierCandidate?>[
      frontier.deferredPredecessor,
      frontier.pendingTail,
    ]) {
      if (candidate == null) continue;
      if (candidate.sourceSlices.isEmpty ||
          candidate.reconstructedCardDigest.isEmpty) {
        return false;
      }
      for (final slice in candidate.sourceSlices) {
        final ordinal = snapshot.resolveOrdinal(
          sourceIdentity: slice.sourceIdentity,
          ordinalHint: slice.sourceOrdinalHint,
        );
        if (ordinal == null || ordinal < previousOrdinal) return false;
        if (ordinal != previousOrdinal) {
          previousTextEnd = null;
          previousRowEnd = null;
        }
        previousOrdinal = ordinal;
        final owner = snapshot.ownerAt(ordinal);
        if (owner.sectionIdentity != slice.sectionIdentity ||
            owner.spineIdentity != slice.spineIdentity ||
            owner.sourceDigest != slice.sourceDigest ||
            slice.logicalOwnerIdentity.isEmpty ||
            slice.structuralType.isEmpty ||
            slice.structuralDigest.isEmpty) {
          return false;
        }
        final source = snapshot.resolveOrdinalSource(ordinal);
        final hasTextRange = slice.startUtf16 != null;
        final hasTableRange = slice.tableRowStart != null;
        if (hasTextRange && hasTableRange) return false;
        if (hasTextRange) {
          if (slice.startUtf16! < 0 ||
              slice.endUtf16! <= slice.startUtf16! ||
              slice.endUtf16! > (source.text?.length ?? 0) ||
              (previousTextEnd != null &&
                  slice.startUtf16! < previousTextEnd)) {
            return false;
          }
          previousTextEnd = slice.endUtf16;
          previousRowEnd = null;
        } else if (hasTableRange) {
          final table = normalizedReaderTableFromText(source.text ?? '');
          if (table == null ||
              slice.tableRowStart! < 0 ||
              slice.tableRowEndExclusive! <= slice.tableRowStart! ||
              slice.tableRowEndExclusive! > table.rows.length) {
            return false;
          }
          if (previousRowEnd != null && slice.tableRowStart! < previousRowEnd) {
            return false;
          }
          previousRowEnd = slice.tableRowEndExclusive;
          previousTextEnd = null;
        } else if (source.type == BookChunkType.text) {
          return false;
        }
        final intervalKey = canonicalJsonEncode(<String, Object?>{
          'owner': slice.sourceIdentity,
          'start': slice.startUtf16,
          'end': slice.endUtf16,
          'rowStart': slice.tableRowStart,
          'rowEnd': slice.tableRowEndExclusive,
        });
        if (!intervalKeys.add(intervalKey)) return false;
      }
    }
    return true;
  }

  CanonicalPaginationCursor? _frontierEndCursor(
    CanonicalPaginationSourceSnapshot snapshot,
    CanonicalPaginationFrontier frontier,
  ) {
    final candidate = frontier.pendingTail ?? frontier.deferredPredecessor;
    if (candidate == null || candidate.sourceSlices.isEmpty) return null;
    final slice = candidate.sourceSlices.last;
    final source = snapshot.resolveOrdinalSource(slice.sourceOrdinalHint);
    final ordinal = slice.sourceOrdinalHint;
    if (slice.tableRowEndExclusive != null) {
      final table = normalizedReaderTableFromText(source.text ?? '');
      if (table != null && slice.tableRowEndExclusive! < table.rows.length) {
        return CanonicalPaginationCursor(
          kind: CanonicalPaginationCursorKind.tableRow,
          sourceIdentity: slice.sourceIdentity,
          sectionIdentity: slice.sectionIdentity,
          sourceOrdinalHint: ordinal,
          tableRowIndex: slice.tableRowEndExclusive!,
        );
      }
    } else if (slice.endUtf16 != null &&
        slice.endUtf16! < (source.text?.length ?? 0)) {
      return CanonicalPaginationCursor(
        kind: CanonicalPaginationCursorKind.sourceText,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: ordinal,
        textOffsetUtf16: slice.endUtf16!,
      );
    }
    return ordinal + 1 < snapshot.sourceCount
        ? _sourceStartCursor(snapshot, ordinal + 1)
        : const CanonicalPaginationCursor.logicalEnd();
  }

  int _compareStableCursors(
    CanonicalPaginationCursor first,
    CanonicalPaginationCursor second,
  ) {
    if (first.isLogicalEnd) return second.isLogicalEnd ? 0 : 1;
    if (second.isLogicalEnd) return -1;
    var result = first.sourceOrdinalHint.compareTo(second.sourceOrdinalHint);
    if (result != 0) return result;
    result = first.tableRowIndex.compareTo(second.tableRowIndex);
    if (result != 0) return result;
    return first.textOffsetUtf16.compareTo(second.textOffsetUtf16);
  }

  bool _frontierOwnersResolve(
    CanonicalPaginationSourceSnapshot snapshot,
    CanonicalPaginationFrontier frontier,
  ) {
    for (final candidate in <CanonicalPaginationFrontierCandidate?>[
      frontier.deferredPredecessor,
      frontier.pendingTail,
    ]) {
      if (candidate == null) continue;
      for (final slice in candidate.sourceSlices) {
        final ordinal = snapshot.resolveOrdinal(
          sourceIdentity: slice.sourceIdentity,
          ordinalHint: slice.sourceOrdinalHint,
        );
        if (ordinal == null) return false;
        final owner = snapshot.ownerAt(ordinal);
        if (owner.sectionIdentity != slice.sectionIdentity ||
            owner.spineIdentity != slice.spineIdentity ||
            owner.sourceDigest != slice.sourceDigest) {
          return false;
        }
      }
    }
    return true;
  }

  bool _cursorResolves(
    CanonicalPaginationSourceSnapshot snapshot,
    CanonicalPaginationCursor cursor,
  ) {
    if (cursor.isLogicalEnd) return true;
    final ordinal = snapshot.resolveOrdinal(
      sourceIdentity: cursor.sourceIdentity,
      ordinalHint: cursor.sourceOrdinalHint,
    );
    if (ordinal == null ||
        snapshot.ownerAt(ordinal).sectionIdentity != cursor.sectionIdentity) {
      return false;
    }
    final source = snapshot.resolveOrdinalSource(ordinal);
    return switch (cursor.kind) {
      CanonicalPaginationCursorKind.wholeSource =>
        cursor.textOffsetUtf16 == 0 && cursor.tableRowIndex == 0,
      CanonicalPaginationCursorKind.sourceText =>
        cursor.textOffsetUtf16 >= 0 &&
            cursor.textOffsetUtf16 <= (source.text?.length ?? 0) &&
            cursor.tableRowIndex == 0 &&
            _isGraphemeBoundary(source.text ?? '', cursor.textOffsetUtf16),
      CanonicalPaginationCursorKind.tableRow =>
        cursor.textOffsetUtf16 == 0 &&
            cursor.tableRowIndex >= 0 &&
            cursor.tableRowIndex <=
                (normalizedReaderTableFromText(
                      source.text ?? '',
                    )?.rows.length ??
                    -1),
      CanonicalPaginationCursorKind.end => false,
    };
  }

  bool _isGraphemeBoundary(String text, int offset) {
    if (offset == 0 || offset == text.length) return true;
    return _readerTextBoundaryService
        .graphemeRanges(text)
        .any((range) => range.start == offset || range.end == offset);
  }

  CanonicalPaginationCursor _sourceStartCursor(
    CanonicalPaginationSourceSnapshot snapshot,
    int ordinal,
  ) {
    final owner = snapshot.ownerAt(ordinal);
    return CanonicalPaginationCursor(
      kind: CanonicalPaginationCursorKind.wholeSource,
      sourceIdentity: owner.sourceIdentity,
      sectionIdentity: owner.sectionIdentity,
      sourceOrdinalHint: ordinal,
    );
  }

  int _derivedFrontierEntryCap(ReaderCardPaginatorLayout layout) {
    final lineBox = math.max(1.0, layout.settings.effectiveLineBoxHeight);
    final lineCapacity =
        (math.max(layout.pageHeightBudget, layout.physicalTextBudget) / lineBox)
            .ceil();
    return (2 * lineCapacity) + 1;
  }

  CanonicalFinalizedReaderCard _finalizedCanonicalCard(
    CanonicalPaginationRequest request,
    _EngineFinalizedCard finalized,
  ) {
    final identity = CanonicalReaderCardIdentityBuilder.build(
      publicationFingerprint: request.publicationFingerprint,
      controlledLayoutIdentity: request.controlledLayoutIdentity,
      paginationAlgorithmIdentity: request.paginationAlgorithmIdentity,
      orderedSourceSlices: finalized.descriptor.sourceSlices,
    );
    return CanonicalFinalizedReaderCard(
      card: finalized.chunk,
      identity: identity,
      sourceSlices: finalized.descriptor.sourceSlices,
      resolvedLayout: finalized.resolvedLayout,
    );
  }

  CanonicalPaginationContinuation _buildContinuation({
    required CanonicalPaginationRequest request,
    required CanonicalPaginationCursor startCursor,
    required CanonicalPaginationCursor nextCursor,
    required CanonicalPaginationFrontier frontier,
    required List<CanonicalFinalizedReaderCard> finalizedCards,
    required CanonicalPaginationCheckpointReason checkpointReason,
    required int sourcesSinceCheckpoint,
    required int cardsSinceCheckpoint,
    required bool terminal,
  }) {
    final restart = request.restart;
    final parent = restart is CanonicalPaginationContinuation ? restart : null;
    final boundaryEnd = _frontierStartCursor(frontier) ?? nextCursor;
    final previousBoundary = finalizedCards.isNotEmpty
        ? CanonicalPaginationFinalizedBoundary(
            kind: CanonicalPaginationBoundaryKind.finalizedCard,
            endCursor: boundaryEnd,
            cardIdentity: finalizedCards.last.identity,
          )
        : CanonicalPaginationFinalizedBoundary(
            kind:
                parent?.previousFinalizedBoundary.kind ??
                (restart is CanonicalPaginationTrustedSectionStart
                    ? CanonicalPaginationBoundaryKind.sectionStart
                    : CanonicalPaginationBoundaryKind.publicationStart),
            endCursor: boundaryEnd,
            cardIdentity: parent?.previousFinalizedBoundary.cardIdentity,
          );
    final sectionIdentity = nextCursor.isLogicalEnd
        ? (finalizedCards.isNotEmpty
              ? finalizedCards.last.sourceSlices.last.sectionIdentity
              : parent?.key.sectionIdentity ?? 'publication-end')
        : nextCursor.sectionIdentity;
    return CanonicalPaginationContinuation.create(
      key: CanonicalPaginationContinuationKey(
        bookId: request.bookId,
        publicationFingerprint: request.publicationFingerprint,
        parserSourceIdentity: request.sourceSnapshot.parserSourceIdentity,
        sourceRevision: request.sourceSnapshot.sourceRevision,
        sourceSnapshotDigest: request.sourceSnapshot.snapshotDigest,
        paginationAlgorithmIdentity: request.paginationAlgorithmIdentity,
        controlledLayoutIdentity: request.controlledLayoutIdentity,
        sectionIdentity: sectionIdentity,
        boundaryCursor: nextCursor,
      ),
      startSourceCursor: startCursor,
      nextSourceCursor: nextCursor,
      frontier: frontier,
      previousFinalizedBoundary: previousBoundary,
      chainOrdinal: parent == null ? 0 : parent.chainOrdinal + 1,
      parentDigest: parent?.integrityDigest,
      checkpointReason: checkpointReason,
      sourcesSinceCheckpoint: sourcesSinceCheckpoint,
      cardsSinceCheckpoint: cardsSinceCheckpoint,
      terminal: terminal,
    );
  }

  CanonicalPaginationCursor? _frontierStartCursor(
    CanonicalPaginationFrontier frontier,
  ) {
    final candidate = frontier.deferredPredecessor ?? frontier.pendingTail;
    if (candidate == null || candidate.sourceSlices.isEmpty) return null;
    final slice = candidate.sourceSlices.first;
    if (slice.tableRowStart != null) {
      return CanonicalPaginationCursor(
        kind: slice.tableRowStart == 0
            ? CanonicalPaginationCursorKind.wholeSource
            : CanonicalPaginationCursorKind.tableRow,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: slice.sourceOrdinalHint,
        tableRowIndex: slice.tableRowStart == 0 ? 0 : slice.tableRowStart!,
      );
    }
    if (slice.startUtf16 != null) {
      return CanonicalPaginationCursor(
        kind: slice.startUtf16 == 0
            ? CanonicalPaginationCursorKind.wholeSource
            : CanonicalPaginationCursorKind.sourceText,
        sourceIdentity: slice.sourceIdentity,
        sectionIdentity: slice.sectionIdentity,
        sourceOrdinalHint: slice.sourceOrdinalHint,
        textOffsetUtf16: slice.startUtf16!,
      );
    }
    return CanonicalPaginationCursor(
      kind: CanonicalPaginationCursorKind.wholeSource,
      sourceIdentity: slice.sourceIdentity,
      sectionIdentity: slice.sectionIdentity,
      sourceOrdinalHint: slice.sourceOrdinalHint,
    );
  }

  CanonicalPaginationSourceSlice _sourceSliceWithEvidence({
    required CanonicalPaginationSourceOwner owner,
    required BookChunk source,
    required BookChunk fragment,
    required String sourceIdentity,
    required String logicalOwnerIdentity,
    int? startUtf16,
    int? endUtf16,
    int? tableRowStart,
    int? tableRowEndExclusive,
    bool usesExplicitTextFragment = false,
  }) {
    final boundaries = fragment.textBoundaries ?? const <DisplayTextBoundary>[];
    return CanonicalPaginationSourceSlice(
      sourceIdentity: sourceIdentity,
      sectionIdentity: owner.sectionIdentity,
      spineIdentity: owner.spineIdentity,
      sourceOrdinalHint: owner.sourceOrdinalHint,
      sourceDigest: owner.sourceDigest,
      structuralType: _canonicalStructuralType(source),
      structuralOwnerRole: _canonicalStructuralOwnerRole(source),
      logicalOwnerIdentity: logicalOwnerIdentity,
      structuralDigest: readerSha256(<String, Object?>{
        'type': source.type.name,
        'role': source.blockRole.name,
        'heading': source.isHeading,
        'dialogue': source.isDialogue,
        'logicalParagraphId': source.logicalParagraphId,
      }),
      fragmentDigest: canonicalBookChunkOwnershipDigest(fragment),
      publisherLayoutDigest: readerSha256(<String, Object?>{
        'align': source.publisherTextAlign?.name,
        'leftIndent': source.publisherLeftIndent,
        'rightIndent': source.publisherRightIndent,
        'preserveLineBreaks': source.preserveLineBreaks,
        'preserveWhitespace': source.preserveWhitespace,
        'usesPublisherLayout': source.usesPublisherLayout,
      }),
      richMetadataDigest: readerSha256(<String, Object?>{
        'links': fragment.links?.map((value) => value.toJson()).toList(),
        'inlineStyles': fragment.inlineStyles
            ?.map((value) => value.toJson())
            .toList(),
        'footnotes': fragment.footnotes
            ?.map((value) => value.toJson())
            .toList(),
      }),
      listFragmentDigest: readerSha256(<String, Object?>{
        'semantics': fragment.listSemantics?.toJson(),
        'segments': fragment.effectiveListDisplaySegments
            .map((value) => value.toJson())
            .toList(),
      }),
      splitBoundaryKind: boundaries.isEmpty
          ? 'none'
          : boundaries.last.kind.name,
      isLogicalParagraphStart: fragment.isLogicalParagraphStart,
      isLogicalParagraphEnd: fragment.isLogicalParagraphEnd,
      usesExplicitTextFragment: usesExplicitTextFragment,
      startUtf16: startUtf16,
      endUtf16: endUtf16,
      tableRowStart: tableRowStart,
      tableRowEndExclusive: tableRowEndExclusive,
    );
  }

  String _canonicalStructuralType(BookChunk chunk) => switch (chunk.type) {
    BookChunkType.image => 'image',
    BookChunkType.milestone => 'synthetic:milestone',
    BookChunkType.text when chunk.isHeading => 'heading',
    BookChunkType.text => chunk.blockRole.name,
  };

  String _canonicalStructuralOwnerRole(BookChunk chunk) {
    final sourceFile = chunk.sourceFile;
    if (sourceFile != null && sourceFile.startsWith('generated:')) {
      final generatedRole = sourceFile.substring('generated:'.length);
      if (generatedRole.isNotEmpty) return 'generated:$generatedRole';
    }
    return switch (chunk.type) {
      BookChunkType.image => 'source:image',
      BookChunkType.milestone => 'generated:milestone',
      BookChunkType.text when chunk.isHeading => 'source:heading',
      BookChunkType.text when chunk.blockRole == BookBlockRole.table =>
        'source:table',
      BookChunkType.text when chunk.listSemantics != null =>
        chunk.sourceFile?.toLowerCase().endsWith('nav.xhtml') == true
            ? 'source:navigation'
            : 'source:list',
      BookChunkType.text => 'source:${chunk.blockRole.name}',
    };
  }
}
