import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/frame_budgeted_range_scheduler.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/reader_card_paginator.dart';

import '../pagination/reader_core_pagination_harness.dart';

// Deliberately red design characterization. No replacement paginator or screen
// lifecycle is implemented here. See the design's seam-gap table for the
// ReaderScreen scheduling/catch/hydration paths that these tests cannot drive.
void main() {
  late ReaderCoreParsedFixture fixture;
  var cacheSequence = 0;

  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('change-040-handoff-');
  });
  tearDownAll(() => fixture.close());

  Future<({LazyBookSession lazy, LazyLoadedContentWindow window})> open(
    WidgetTester tester, {
    bool finalSection = false,
  }) async {
    final lazy = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(
            '${fixture.temporaryDirectory.path}/lazy-${cacheSequence++}',
          ),
        ),
        workCoordinator: SharedLazySectionWorkCoordinator(),
      ),
    );
    addTearDown(lazy.close);
    final window = await tester.runAsync(() async {
      final index = await lazy.open(fixture.epubFile);
      final item = finalSection
          ? index.spine.lastWhere((item) => item.isLinear)
          : index.spine.firstWhere((item) => item.isLinear);
      return lazy.loadAround(
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
        after: 0,
      );
    });
    return (lazy: lazy, window: window!);
  }

  testWidgets('H01 RED known successor must not produce terminalBookEnd', (
    tester,
  ) async {
    final input = await open(tester);
    expect(input.window.hasContentAfter, isTrue);
    expect(
      input.lazy.nextReadableSpineIndex(
        input.window.sections.last.identity.spineIndex,
      ),
      isNotNull,
    );
    final harness = await _harness(tester, input.window);
    final session = _session(input.window, harness);
    final accepted = await _exhaust(session, harness);

    expect(
      accepted.continuation.checkpointReason,
      isNot(CanonicalPaginationCheckpointReason.terminalBookEnd),
      reason:
          'The production lazy index proves a successor, but the pinned '
          'canonical input has no availability authority.',
    );
  });

  testWidgets('H02 RED loaded successor must be reachable by forward path', (
    tester,
  ) async {
    final input = await open(tester);
    final harness = await _harness(tester, input.window);
    final session = _session(input.window, harness);
    final accepted = await _exhaust(session, harness);
    final originalDigest = session.sourceSnapshot.snapshotDigest;
    final successor = await tester.runAsync(
      () => input.lazy.loadNextReadableSectionAfter(
        input.window.sections.last.identity.spineIndex,
      ),
    );
    expect(successor, isNotNull);
    final expanded = input.lazy.loadedWindow();
    expect(expanded.chunks.length, greaterThan(input.window.chunks.length));
    // Loading B must never mutate the session pinned to A.
    expect(session.sourceSnapshot.snapshotDigest, originalDigest);
    expect(session.sourceSnapshot.sourceCount, input.window.chunks.length);
    final result = await session.generateForward(
      acceptedPublishedSuffix: accepted.continuation.previousFinalizedBoundary,
      operation: harness.canonicalOperationForP04(),
    );

    expect(
      result,
      isA<CanonicalReaderPaginationPathAccepted>(),
      reason: _rejection(result),
    );
  });

  testWidgets('H03 RED speculative and demand priorities hit same suffix', (
    tester,
  ) async {
    final input = await open(tester);
    expect(input.window.hasContentAfter, isTrue);
    final harness = await _harness(tester, input.window);
    final session = _session(input.window, harness);
    final accepted = await _exhaust(session, harness);
    final boundary = accepted.continuation.previousFinalizedBoundary;
    final results = await Future.wait([
      session.generateForward(
        acceptedPublishedSuffix: boundary,
        // The existing harness defaults to speculativeLookahead.
        operation: harness.canonicalOperationForP04(),
      ),
      session.generateForward(
        acceptedPublishedSuffix: boundary,
        operation: harness.canonicalOperationForP04(
          priority: DisplayRangeTaskPriority.boundaryWait,
        ),
      ),
    ]);

    expect(
      results,
      everyElement(isA<CanonicalReaderPaginationPathAccepted>()),
      reason: results.map(_rejection).join('\n'),
    );
  });

  test('H04 RED demand boundary failure must reach retry presentation', () {
    expect(
      readerShouldSurfacePreparationFailure('lazy_forward_boundary'),
      isTrue,
      reason:
          'Both forward integration callers use this production reason. '
          'This tests the predicate only, not catch/upstream settlement.',
    );
  });

  testWidgets('H06 CONTROL final spine has valid terminalBookEnd', (
    tester,
  ) async {
    final input = await open(tester, finalSection: true);
    expect(input.window.hasContentAfter, isFalse);
    expect(
      input.lazy.nextReadableSpineIndex(
        input.window.sections.last.identity.spineIndex,
      ),
      isNull,
    );
    final harness = await _harness(tester, input.window);
    final accepted = await _exhaust(_session(input.window, harness), harness);

    expect(accepted.continuation.terminal, isTrue);
    expect(accepted.continuation.nextSourceCursor.isLogicalEnd, isTrue);
    expect(accepted.continuation.frontier.cardCandidateCount, 0);
    expect(
      accepted.continuation.checkpointReason,
      CanonicalPaginationCheckpointReason.terminalBookEnd,
    );
    expect(
      CanonicalPaginationContinuationCodec.decode(
        accepted.continuation.canonicalEncoding,
      ),
      isA<CanonicalPaginationContinuationAccepted>(),
    );
  });
}

Future<ReaderCorePaginationHarness> _harness(
  WidgetTester tester,
  LazyLoadedContentWindow window,
) => ReaderCorePaginationHarness.install(
  tester: tester,
  sourceChunks: window.chunks,
  bookId: window.sections.first.identity.bookId,
  publicationFingerprint: window.sections.first.identity.publicationFingerprint,
);

CanonicalReaderPaginationSession _session(
  LazyLoadedContentWindow window,
  ReaderCorePaginationHarness harness,
) => CanonicalReaderPaginationSession(
  sourceSnapshot: CanonicalPaginationSourceSnapshot.pin(
    bookId: harness.bookId,
    publicationFingerprint: harness.publicationFingerprint,
    parserSourceIdentity: window.sections.first.identity.parserVersion,
    sourceRevision: readerSha256(
      window.chunks.map((chunk) => chunk.toJson()).toList(),
    ),
    sourceChunks: window.chunks,
    sourceKeys: [
      for (var ordinal = 0; ordinal < window.chunks.length; ordinal++)
        CanonicalPaginationSourceKey(
          sourceIdentity:
              window.sourceIdentitiesByChunkIndex[ordinal]!.stableKey,
          sectionIdentity:
              window.sourceIdentitiesByChunkIndex[ordinal]!.section.stableKey,
          spineIdentity:
              window.sourceIdentitiesByChunkIndex[ordinal]!.section.stableKey,
          sourceOrdinalHint: ordinal,
        ),
    ],
  ),
  controlledLayoutIdentity: harness.layoutIdentity,
  layout: harness.paginatorLayout,
);

// Runs only production initial/forward pagination over the tiny parsed section.
// The bound is a test guard, not an alternate pagination implementation.
Future<CanonicalReaderPaginationPathAccepted> _exhaust(
  CanonicalReaderPaginationSession session,
  ReaderCorePaginationHarness harness,
) async {
  var result = await session.generateInitial(
    restart: const CanonicalPaginationPublicationStart(),
    operation: harness.canonicalOperationForP04(),
  );
  for (var step = 0; step < 25; step++) {
    expect(result, isA<CanonicalReaderPaginationPathAccepted>());
    final accepted = result as CanonicalReaderPaginationPathAccepted;
    if (accepted.continuation.terminal) return accepted;
    result = await session.generateForward(
      acceptedPublishedSuffix: accepted.continuation.previousFinalizedBoundary,
      operation: harness.canonicalOperationForP04(),
    );
  }
  throw StateError('Tiny section exceeded characterization work bound.');
}

String _rejection(CanonicalReaderPaginationPathResult result) =>
    result is CanonicalReaderPaginationPathRejected
    ? '${result.rejection.reason.name}: ${result.rejection.message}'
    : result.runtimeType.toString();
