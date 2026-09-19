import 'dart:convert';

import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/progressive_display_state.dart';
import 'package:nalori/utils/reader_content_parser.dart';

/// A projection of production paginator output for P03 characterization.
///
/// This contains only production output and source-coverage accounting.  It
/// deliberately does not split, pack, merge, or synthesize card identities.
final class ReaderCardPaginationEvidence {
  const ReaderCardPaginationEvidence({
    required this.requestedSourceRange,
    required this.cards,
    required this.coverage,
    required this.diagnosticPhases,
  });

  factory ReaderCardPaginationEvidence.project({
    required DisplayRangeResult result,
    required List<BookChunk> sourceChunks,
    required Map<int, int> readableSourceExtents,
    required String publicationFingerprint,
    required String layoutFingerprint,
    List<String> diagnosticPhases = const [],
  }) => ReaderCardPaginationEvidence.projectSnapshot(
    requestedSourceRange: result.request.sourceRange.toString(),
    displayChunks: result.displayChunks,
    displayToOriginal: result.displayToOriginal,
    sourceChunks: sourceChunks,
    readableSourceExtents: readableSourceExtents,
    publicationFingerprint: publicationFingerprint,
    layoutFingerprint: layoutFingerprint,
    diagnosticPhases: diagnosticPhases,
  );

  /// Projects the real card snapshot owned by [ProgressiveDisplayState].
  ///
  /// The state has already assembled production [DisplayRangeResult] values;
  /// this method performs no range joining, splitting, packing, or identity
  /// substitution.
  factory ReaderCardPaginationEvidence.projectSnapshot({
    required String requestedSourceRange,
    required List<BookChunk> displayChunks,
    required List<List<int>> displayToOriginal,
    required List<BookChunk> sourceChunks,
    required Map<int, int> readableSourceExtents,
    required String publicationFingerprint,
    required String layoutFingerprint,
    List<ReaderCardIdentity>? cardIdentities,
    List<String> diagnosticPhases = const [],
  }) {
    if (cardIdentities != null &&
        cardIdentities.length != displayChunks.length) {
      throw StateError('Canonical identity count does not match card count.');
    }
    final identities =
        cardIdentities ??
        <ReaderCardIdentity>[
          for (var cardIndex = 0; cardIndex < displayChunks.length; cardIndex++)
            ReaderCardIdentity.fromCard(
              publicationFingerprint: publicationFingerprint,
              layoutFingerprint: layoutFingerprint,
              card: displayChunks[cardIndex],
              sourceChunks: sourceChunks,
              sourceIndices: displayToOriginal[cardIndex],
              locationsBySourceIndex: const {},
            ),
        ];

    final sourceUseCount = <int, int>{};
    for (final card in displayChunks) {
      for (final sourceIndex
          in card.effectiveSourceRanges
              .map((range) => range.originalChunkIndex)
              .toSet()) {
        sourceUseCount[sourceIndex] = (sourceUseCount[sourceIndex] ?? 0) + 1;
      }
    }

    final cards = <ReaderCardEvidence>[];
    for (var cardIndex = 0; cardIndex < displayChunks.length; cardIndex++) {
      final card = displayChunks[cardIndex];
      final identity = identities[cardIndex];
      final ranges = <ReaderCardSourceRangeEvidence>[];
      final cardRanges = card.effectiveSourceRanges;
      for (var rangeIndex = 0; rangeIndex < cardRanges.length; rangeIndex++) {
        final range = cardRanges[rangeIndex];
        final identityRange = rangeIndex < identity.ranges.length
            ? identity.ranges[rangeIndex]
            : null;
        ranges.add(
          ReaderCardSourceRangeEvidence(
            sourceIndex: range.originalChunkIndex,
            sourceStartUtf16: range.originalStartOffset,
            sourceEndUtf16: range.originalEndOffset,
            displayStartUtf16: range.displayStartOffset,
            displayEndUtf16: range.displayEndOffset,
            sectionIdentity: identityRange?.sectionIdentity ?? 'unavailable',
            sectionChecksum: identityRange?.sectionChecksum ?? 'unavailable',
            logicalBlockId: identityRange?.logicalBlockId ?? 'unavailable',
            structuralType: identityRange?.structuralType ?? 'unavailable',
            logicalBlockStartUtf16: identityRange?.startUtf16,
            logicalBlockEndUtf16: identityRange?.endUtf16,
          ),
        );
      }
      cards.add(
        ReaderCardEvidence(
          structuralType:
              '${card.type.name}/${card.isHeading ? 'heading' : card.blockRole.name}',
          rawText: card.text ?? '',
          visibleText: _visibleText(card),
          sourceRanges: ranges,
          identity: ReaderCardIdentityEvidence.fromIdentity(identity),
          observableOrigins: _observableOrigins(
            cardIndex: cardIndex,
            cardCount: displayChunks.length,
            sourceRanges: ranges,
            sourceUseCount: sourceUseCount,
          ),
        ),
      );
    }

    return ReaderCardPaginationEvidence(
      requestedSourceRange: requestedSourceRange,
      cards: cards,
      coverage: ReaderSourceCoverageEvidence.fromCards(
        cards: cards,
        readableSourceExtents: readableSourceExtents,
      ),
      diagnosticPhases: List<String>.unmodifiable(diagnosticPhases),
    );
  }

  final String requestedSourceRange;
  final List<ReaderCardEvidence> cards;
  final ReaderSourceCoverageEvidence coverage;
  final List<String> diagnosticPhases;

  Map<String, Object?> toJson() => <String, Object?>{
    'requestedSourceRange': requestedSourceRange,
    'cards': cards.map((card) => card.toJson()).toList(growable: false),
    'coverage': coverage.toJson(),
    'diagnosticPhases': diagnosticPhases,
  };

  String describe() => const JsonEncoder.withIndent('  ').convert(toJson());
}

final class ReaderCardEvidence {
  const ReaderCardEvidence({
    required this.structuralType,
    required this.rawText,
    required this.visibleText,
    required this.sourceRanges,
    required this.identity,
    required this.observableOrigins,
  });

  final String structuralType;
  final String? rawText;
  final String visibleText;
  final List<ReaderCardSourceRangeEvidence> sourceRanges;
  final ReaderCardIdentityEvidence identity;
  final List<String> observableOrigins;

  Map<String, Object?> toJson() => <String, Object?>{
    'structuralType': structuralType,
    'rawText': rawText,
    'visibleText': visibleText,
    'sourceRanges': sourceRanges
        .map((range) => range.toJson())
        .toList(growable: false),
    'identity': identity.toJson(),
    'observableOrigins': observableOrigins,
  };
}

final class ReaderCardSourceRangeEvidence {
  const ReaderCardSourceRangeEvidence({
    required this.sourceIndex,
    required this.sourceStartUtf16,
    required this.sourceEndUtf16,
    required this.displayStartUtf16,
    required this.displayEndUtf16,
    required this.sectionIdentity,
    required this.sectionChecksum,
    required this.logicalBlockId,
    required this.structuralType,
    required this.logicalBlockStartUtf16,
    required this.logicalBlockEndUtf16,
  });

  final int sourceIndex;
  final int sourceStartUtf16;
  final int sourceEndUtf16;
  final int displayStartUtf16;
  final int displayEndUtf16;
  final String sectionIdentity;
  final String sectionChecksum;
  final String logicalBlockId;
  final String structuralType;
  final int? logicalBlockStartUtf16;
  final int? logicalBlockEndUtf16;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': '[$sourceIndex:$sourceStartUtf16,$sourceEndUtf16)',
    'display': '[$displayStartUtf16,$displayEndUtf16)',
    'sectionIdentity': sectionIdentity,
    'sectionChecksum': sectionChecksum,
    'logicalBlockId': logicalBlockId,
    'structuralType': structuralType,
    'logicalBlockRange': '[$logicalBlockStartUtf16,$logicalBlockEndUtf16)',
  };
}

final class ReaderCardIdentityEvidence {
  const ReaderCardIdentityEvidence({
    required this.publicationFingerprint,
    required this.layoutFingerprint,
    required this.paginationVersion,
    required this.signature,
  });

  factory ReaderCardIdentityEvidence.fromIdentity(
    ReaderCardIdentity identity,
  ) => ReaderCardIdentityEvidence(
    publicationFingerprint: identity.publicationFingerprint,
    layoutFingerprint: identity.layoutFingerprint,
    paginationVersion: identity.paginationVersion,
    signature: identity.signature,
  );

  final String publicationFingerprint;
  final String layoutFingerprint;
  final String paginationVersion;
  final String? signature;

  Map<String, Object?> toJson() => <String, Object?>{
    'publicationFingerprint': publicationFingerprint,
    'layoutFingerprint': layoutFingerprint,
    'paginationVersion': paginationVersion,
    'signature': signature,
  };
}

final class ReaderSourceCoverageEvidence {
  const ReaderSourceCoverageEvidence({
    required this.covered,
    required this.gaps,
    required this.overlaps,
    required this.duplicates,
    required this.outsideReadableSource,
  });

  factory ReaderSourceCoverageEvidence.fromCards({
    required List<ReaderCardEvidence> cards,
    required Map<int, int> readableSourceExtents,
  }) {
    final bySource = <int, List<ReaderCardSourceRangeEvidence>>{};
    for (final card in cards) {
      for (final range in card.sourceRanges) {
        bySource.putIfAbsent(range.sourceIndex, () => []).add(range);
      }
    }

    final covered = <String>[];
    final gaps = <String>[];
    final overlaps = <String>[];
    final duplicates = <String>[];
    final outside = <String>[];
    final exactRangeCounts = <String, int>{};
    for (final entry in bySource.entries) {
      for (final range in entry.value) {
        final key =
            '${range.sourceIndex}:'
            '${range.sourceStartUtf16}:${range.sourceEndUtf16}';
        exactRangeCounts[key] = (exactRangeCounts[key] ?? 0) + 1;
      }
    }
    for (final entry in exactRangeCounts.entries) {
      if (entry.value > 1) {
        duplicates.add('${entry.key} repeated ${entry.value} times');
      }
    }
    for (final entry in readableSourceExtents.entries) {
      final sourceIndex = entry.key;
      final extent = entry.value;
      final ranges = [...?bySource[sourceIndex]]
        ..sort((a, b) {
          final byStart = a.sourceStartUtf16.compareTo(b.sourceStartUtf16);
          return byStart != 0
              ? byStart
              : a.sourceEndUtf16.compareTo(b.sourceEndUtf16);
        });
      var cursor = 0;
      for (final range in ranges) {
        if (range.sourceStartUtf16 < 0 || range.sourceEndUtf16 > extent) {
          outside.add(
            'source $sourceIndex [${range.sourceStartUtf16},${range.sourceEndUtf16}) outside [0,$extent)',
          );
        }
        if (range.sourceStartUtf16 > cursor) {
          gaps.add('source $sourceIndex [$cursor,${range.sourceStartUtf16})');
        }
        if (range.sourceStartUtf16 < cursor) {
          overlaps.add(
            'source $sourceIndex [${range.sourceStartUtf16},${range.sourceEndUtf16}) overlaps cursor $cursor',
          );
        }
        cursor = cursor < range.sourceEndUtf16 ? range.sourceEndUtf16 : cursor;
      }
      if (cursor < extent) gaps.add('source $sourceIndex [$cursor,$extent)');
      if (cursor >= extent && ranges.isNotEmpty) {
        covered.add('source $sourceIndex [0,$extent)');
      }
    }
    for (final sourceIndex in bySource.keys) {
      if (!readableSourceExtents.containsKey(sourceIndex)) {
        outside.add('source $sourceIndex is outside the requested oracle');
      }
    }
    return ReaderSourceCoverageEvidence(
      covered: covered,
      gaps: gaps,
      overlaps: overlaps,
      duplicates: duplicates,
      outsideReadableSource: outside,
    );
  }

  final List<String> covered;
  final List<String> gaps;
  final List<String> overlaps;
  final List<String> duplicates;
  final List<String> outsideReadableSource;

  bool get complete =>
      gaps.isEmpty &&
      overlaps.isEmpty &&
      duplicates.isEmpty &&
      outsideReadableSource.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'covered': covered,
    'gaps': gaps,
    'overlaps': overlaps,
    'duplicates': duplicates,
    'outsideReadableSource': outsideReadableSource,
  };
}

/// Returns a seam-focused comparison failure for later P03 construction-order
/// tests.  It compares full ordered evidence, never card count alone.
String? readerCardPaginationEvidenceMismatch({
  required String constructionLabel,
  required ReaderCardPaginationEvidence expected,
  required ReaderCardPaginationEvidence actual,
  String scenario = 'unspecified',
  String controlledLayoutIdentity = 'unspecified',
  List<String> requestedRanges = const [],
  int? targetSourceIndex,
}) {
  final header = _comparisonHeader(
    scenario: scenario,
    constructionLabel: constructionLabel,
    controlledLayoutIdentity: controlledLayoutIdentity,
    requestedRanges: requestedRanges,
    targetSourceIndex: targetSourceIndex,
  );
  if (expected.requestedSourceRange != actual.requestedSourceRange) {
    return '$header\nrequested source range differs: '
        'expected ${expected.requestedSourceRange}; '
        'actual ${actual.requestedSourceRange}.\n'
        '${_coverageDescription(actual.coverage)}';
  }

  final comparedCount = expected.cards.length < actual.cards.length
      ? expected.cards.length
      : actual.cards.length;
  for (var index = 0; index < comparedCount; index++) {
    if (!_sameCard(expected.cards[index], actual.cards[index])) {
      return _cardMismatchDescription(
        constructionLabel: constructionLabel,
        cardIndex: index,
        expected: expected.cards[index],
        actual: actual.cards[index],
        expectedCards: expected.cards,
        actualCards: actual.cards,
        actualCoverage: actual.coverage,
        comparisonHeader: header,
      );
    }
  }
  if (expected.cards.length != actual.cards.length) {
    final index = comparedCount;
    return _cardMismatchDescription(
      constructionLabel: constructionLabel,
      cardIndex: index,
      expected: index < expected.cards.length ? expected.cards[index] : null,
      actual: index < actual.cards.length ? actual.cards[index] : null,
      expectedCards: expected.cards,
      actualCards: actual.cards,
      actualCoverage: actual.coverage,
      comparisonHeader: header,
    );
  }
  if (!actual.coverage.complete) {
    return '$header\ncard evidence matches but source membership '
        'is invalid.\n${_coverageDescription(actual.coverage)}';
  }
  return null;
}

/// Compact machine-readable form of the same first-difference calculation
/// used by [readerCardPaginationEvidenceMismatch].
///
/// This is diagnostic evidence for the P03 ledger, not another oracle.
String readerCardPaginationCompactMismatch({
  required ReaderCardPaginationEvidence expected,
  required ReaderCardPaginationEvidence actual,
}) {
  final comparedCount = expected.cards.length < actual.cards.length
      ? expected.cards.length
      : actual.cards.length;
  var firstDivergence = -1;
  for (var index = 0; index < comparedCount; index++) {
    if (!_sameCard(expected.cards[index], actual.cards[index])) {
      firstDivergence = index;
      break;
    }
  }
  if (firstDivergence < 0 && expected.cards.length != actual.cards.length) {
    firstDivergence = comparedCount;
  }
  if (firstDivergence < 0) {
    return jsonEncode(<String, Object?>{
      'firstDivergence': null,
      'coverage': actual.coverage.toJson(),
    });
  }

  Map<String, Object?>? compactCard(List<ReaderCardEvidence> cards, int index) {
    if (index < 0 || index >= cards.length) return null;
    final card = cards[index];
    return <String, Object?>{
      'index': index,
      'structure': card.structuralType,
      'sourceRanges': card.sourceRanges
          .map(
            (range) =>
                '${range.sourceIndex}:'
                '[${range.sourceStartUtf16},${range.sourceEndUtf16})@'
                '[${range.displayStartUtf16},${range.displayEndUtf16})|'
                '${range.sectionIdentity}|${range.logicalBlockId}|'
                '${range.structuralType}|'
                '[${range.logicalBlockStartUtf16},${range.logicalBlockEndUtf16})',
          )
          .toList(growable: false),
      'identity': card.identity.signature,
      'visibleText': card.visibleText,
    };
  }

  final expectedCard = firstDivergence < expected.cards.length
      ? expected.cards[firstDivergence]
      : null;
  final actualCard = firstDivergence < actual.cards.length
      ? actual.cards[firstDivergence]
      : null;
  return jsonEncode(<String, Object?>{
    'firstDivergence': firstDivergence,
    'classification': _differenceKinds(expectedCard, actualCard),
    'reference': compactCard(expected.cards, firstDivergence),
    'actual': compactCard(actual.cards, firstDivergence),
    'referencePredecessor': compactCard(expected.cards, firstDivergence - 1),
    'referenceSuccessor': compactCard(expected.cards, firstDivergence + 1),
    'actualPredecessor': compactCard(actual.cards, firstDivergence - 1),
    'actualSuccessor': compactCard(actual.cards, firstDivergence + 1),
    'coverage': <String, Object?>{
      'gaps': actual.coverage.gaps,
      'overlaps': actual.coverage.overlaps,
      'duplicates': actual.coverage.duplicates,
      'outside': actual.coverage.outsideReadableSource,
    },
  });
}

String _visibleText(BookChunk card) {
  final blocks = parseReaderContentBlocks(card.text ?? '');
  if (blocks.length == 1 && blocks.single.table != null) {
    return blocks.single.table!.logicalText
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  return card.text ?? '';
}

List<String> _observableOrigins({
  required int cardIndex,
  required int cardCount,
  required List<ReaderCardSourceRangeEvidence> sourceRanges,
  required Map<int, int> sourceUseCount,
}) {
  final origins = <String>[];
  if (sourceRanges.length > 1) origins.add('merging-observed');
  if (sourceRanges.any(
    (range) => (sourceUseCount[range.sourceIndex] ?? 0) > 1,
  )) {
    origins.add('splitting-observed');
  }
  if (cardIndex == cardCount - 1) origins.add('final-tail-flush-observed');
  if (origins.isEmpty) origins.add('pending/rebalance-not-observable');
  return origins;
}

bool _sameCard(ReaderCardEvidence expected, ReaderCardEvidence actual) {
  if (expected.structuralType != actual.structuralType ||
      expected.visibleText != actual.visibleText ||
      (expected.rawText != null && expected.rawText != actual.rawText) ||
      expected.identity.publicationFingerprint !=
          actual.identity.publicationFingerprint ||
      expected.identity.layoutFingerprint !=
          actual.identity.layoutFingerprint ||
      expected.identity.paginationVersion !=
          actual.identity.paginationVersion ||
      (expected.identity.signature != null &&
          expected.identity.signature != actual.identity.signature) ||
      expected.sourceRanges.length != actual.sourceRanges.length) {
    return false;
  }
  for (var index = 0; index < expected.sourceRanges.length; index++) {
    if (jsonEncode(expected.sourceRanges[index].toJson()) !=
        jsonEncode(actual.sourceRanges[index].toJson())) {
      return false;
    }
  }
  return true;
}

String _cardMismatchDescription({
  required String constructionLabel,
  required int cardIndex,
  required ReaderCardEvidence? expected,
  required ReaderCardEvidence? actual,
  required List<ReaderCardEvidence> expectedCards,
  required List<ReaderCardEvidence> actualCards,
  required ReaderSourceCoverageEvidence actualCoverage,
  required String comparisonHeader,
}) {
  String context(List<ReaderCardEvidence> cards) {
    final start = cardIndex > 0 ? cardIndex - 1 : 0;
    final end = cardIndex + 2 < cards.length ? cardIndex + 2 : cards.length;
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      for (var index = start; index < end; index++)
        'card[$index]': cards[index].toJson(),
    });
  }

  final differenceKinds = _differenceKinds(expected, actual);
  return '$comparisonHeader\n'
      'first divergent card: $cardIndex\n'
      'difference classification: ${differenceKinds.join(', ')}\n'
      'expected: ${const JsonEncoder.withIndent('  ').convert(expected?.toJson())}\n'
      'actual: ${const JsonEncoder.withIndent('  ').convert(actual?.toJson())}\n'
      'expected seam context:\n${context(expectedCards)}\n'
      'actual seam context:\n${context(actualCards)}\n'
      '${_coverageDescription(actualCoverage)}';
}

String _coverageDescription(ReaderSourceCoverageEvidence coverage) =>
    'source coverage: gaps=${coverage.gaps}; overlaps=${coverage.overlaps}; '
    'duplicates=${coverage.duplicates}; '
    'outside=${coverage.outsideReadableSource}.';

String _comparisonHeader({
  required String scenario,
  required String constructionLabel,
  required String controlledLayoutIdentity,
  required List<String> requestedRanges,
  required int? targetSourceIndex,
}) =>
    'scenario=$scenario; constructionOrder=$constructionLabel; '
    'layout=$controlledLayoutIdentity; '
    'requestedRanges=${requestedRanges.join(' -> ')}; '
    'target=${targetSourceIndex ?? 'none'}';

List<String> _differenceKinds(
  ReaderCardEvidence? expected,
  ReaderCardEvidence? actual,
) {
  if (expected == null) return const ['extra card'];
  if (actual == null) return const ['missing card'];
  final kinds = <String>[];
  final expectedRanges = expected.sourceRanges
      .map((range) => jsonEncode(range.toJson()))
      .toList(growable: false);
  final actualRanges = actual.sourceRanges
      .map((range) => jsonEncode(range.toJson()))
      .toList(growable: false);
  if (jsonEncode(expectedRanges) != jsonEncode(actualRanges)) {
    kinds.add('changed physical boundary');
    if (expected.visibleText.startsWith(actual.visibleText) ||
        actual.visibleText.startsWith(expected.visibleText)) {
      kinds.add('separately flushed tail/cut membership');
    }
    final expectedSources = expected.sourceRanges
        .map((range) => range.sourceIndex)
        .toList(growable: false);
    final actualSources = actual.sourceRanges
        .map((range) => range.sourceIndex)
        .toList(growable: false);
    if (expectedSources.toSet().length == actualSources.toSet().length &&
        expectedSources.toSet().containsAll(actualSources) &&
        jsonEncode(expectedSources) != jsonEncode(actualSources)) {
      kinds.add('reordered card');
    }
  }
  final expectedOwners = expected.sourceRanges
      .map(
        (range) =>
            '${range.sectionIdentity}|${range.logicalBlockId}|'
            '${range.structuralType}',
      )
      .toList(growable: false);
  final actualOwners = actual.sourceRanges
      .map(
        (range) =>
            '${range.sectionIdentity}|${range.logicalBlockId}|'
            '${range.structuralType}',
      )
      .toList(growable: false);
  if (jsonEncode(expectedOwners) != jsonEncode(actualOwners) ||
      expected.structuralType != actual.structuralType) {
    kinds.add('changed structural owner');
  }
  if (expected.visibleText != actual.visibleText ||
      expected.rawText != actual.rawText) {
    kinds.add('changed visible text');
  }
  if (expected.identity.signature != actual.identity.signature) {
    kinds.add(
      expected.visibleText == actual.visibleText &&
              jsonEncode(expectedRanges) == jsonEncode(actualRanges)
          ? 'changed identity with otherwise equal text/ranges'
          : 'changed ReaderCardIdentity',
    );
  }
  return kinds.isEmpty ? const ['unclassified ordered-card mismatch'] : kinds;
}
