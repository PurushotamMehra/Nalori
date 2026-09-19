import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/display_generation_coordinator.dart';

void main() {
  DisplayGenerationSignature signature({
    String bookId = 'book.epub',
    String settings = 'settings-a',
    String viewport = 'viewport-a',
    String cacheKey = 'cache-a',
  }) {
    return DisplayGenerationSignature(
      bookId: bookId,
      parsedContentVersion: 4,
      layoutSignature: 'layout-v1',
      settingsSignature: settings,
      viewportSignature: viewport,
      cacheKey: cacheKey,
    );
  }

  test('identical concurrent requests join active generation', () {
    final coordinator = DisplayGenerationCoordinator();
    final first = coordinator.request(signature());
    final second = coordinator.request(signature());

    expect(first.kind, DisplayGenerationRequestKind.start);
    expect(second.kind, DisplayGenerationRequestKind.join);
    expect(identical(first.token, second.token), isTrue);
    expect(first.token.isCancelled, isFalse);
  });

  test('settings change replaces and cancels previous generation', () {
    final coordinator = DisplayGenerationCoordinator();
    final first = coordinator.request(signature());
    final second = coordinator.request(
      signature(settings: 'settings-b', cacheKey: 'cache-b'),
    );

    expect(second.kind, DisplayGenerationRequestKind.replace);
    expect(second.cancelledToken, same(first.token));
    expect(first.token.isCancelled, isTrue);
    expect(first.token.cancellationReason, 'signature_changed');
    expect(coordinator.canPublish(first.token), isFalse);
    expect(coordinator.canPublish(second.token), isTrue);
  });

  test(
    'rapid font-family reflows allow only the latest lookahead to publish',
    () {
      final coordinator = DisplayGenerationCoordinator();
      final lora = coordinator.request(
        signature(settings: 'font-lora', cacheKey: 'cache-lora'),
      );
      final atkinson = coordinator.request(
        signature(settings: 'font-atkinson', cacheKey: 'cache-atkinson'),
      );
      final merriweather = coordinator.request(
        signature(
          settings: 'font-merriweather',
          cacheKey: 'cache-merriweather',
        ),
      );

      expect(lora.token.isCancelled, isTrue);
      expect(atkinson.token.isCancelled, isTrue);
      expect(coordinator.canPublish(lora.token), isFalse);
      expect(coordinator.canPublish(atkinson.token), isFalse);
      expect(
        coordinator.canWriteCache(atkinson.token, 'cache-atkinson'),
        isFalse,
      );
      expect(coordinator.canPublish(merriweather.token), isTrue);
    },
  );

  test('orientation or viewport change replaces previous generation', () {
    final coordinator = DisplayGenerationCoordinator();
    final first = coordinator.request(signature());
    final second = coordinator.request(
      signature(viewport: 'viewport-b', cacheKey: 'cache-b'),
    );

    expect(second.kind, DisplayGenerationRequestKind.replace);
    expect(first.token.isCancelled, isTrue);
    expect(coordinator.activeToken, same(second.token));
  });

  test('old generation cannot publish or write cache after replacement', () {
    final coordinator = DisplayGenerationCoordinator();
    final first = coordinator.request(signature());
    coordinator.request(signature(settings: 'settings-b', cacheKey: 'cache-b'));

    expect(coordinator.canPublish(first.token), isFalse);
    expect(coordinator.canWriteCache(first.token, 'cache-a'), isFalse);
  });

  test('active generation can write only its complete cache key', () {
    final coordinator = DisplayGenerationCoordinator();
    final first = coordinator.request(signature());

    expect(coordinator.canWriteCache(first.token, 'cache-a'), isTrue);
    expect(coordinator.canWriteCache(first.token, 'cache-other'), isFalse);
  });

  test('book close cancels active work and leaves coordinator idle', () {
    final coordinator = DisplayGenerationCoordinator();
    final first = coordinator.request(signature());

    coordinator.cancelActive('reader_disposed');

    expect(first.token.isCancelled, isTrue);
    expect(first.token.cancellationReason, 'reader_disposed');
    expect(coordinator.activeToken, isNull);
    expect(coordinator.canPublish(first.token), isFalse);
  });

  test('completion clears active generation', () {
    final coordinator = DisplayGenerationCoordinator();
    final first = coordinator.request(signature());

    coordinator.complete(first.token);

    expect(first.token.state, DisplayGenerationState.complete);
    expect(coordinator.activeToken, isNull);
    expect(coordinator.canPublish(first.token), isFalse);
  });

  test('pending navigation preserves the last published readable snapshot', () {
    final coordinator = ReaderNavigationPublicationCoordinator<String>();
    coordinator.markReadablePublished();

    final pending = coordinator.begin('target-b');

    expect(coordinator.hasPublishedReadableContent, isTrue);
    expect(coordinator.publishedGeneration, 0);
    expect(coordinator.pending, same(pending));
  });

  test('barrier-controlled A B C navigation publishes only latest C', () async {
    final coordinator = ReaderNavigationPublicationCoordinator<String>();
    coordinator.markReadablePublished();
    final barriers = {
      for (final target in ['A', 'B', 'C']) target: Completer<void>(),
    };
    final published = <String>[];

    Future<void> prepareAndPublish(String target) async {
      final token = coordinator.begin(target);
      await barriers[target]!.future;
      if (!coordinator.isLatest(token)) return;
      published.add(target);
      coordinator.markReadablePublished(token);
    }

    final a = prepareAndPublish('A');
    final b = prepareAndPublish('B');
    final c = prepareAndPublish('C');
    barriers['B']!.complete();
    barriers['A']!.complete();
    await Future.wait([a, b]);
    expect(published, isEmpty);
    expect(coordinator.hasPublishedReadableContent, isTrue);

    barriers['C']!.complete();
    await c;
    expect(published, ['C']);
    expect(coordinator.pending, isNull);
  });

  test('stale completion or latest failure never clears old publication', () {
    final coordinator = ReaderNavigationPublicationCoordinator<String>();
    coordinator.markReadablePublished();
    final a = coordinator.begin('A');
    final c = coordinator.begin('C');

    coordinator.markReadablePublished(a);
    coordinator.fail(c);

    expect(coordinator.hasPublishedReadableContent, isTrue);
    expect(coordinator.publishedGeneration, 0);
    expect(coordinator.pending, isNull);
  });

  group('authoritative visible position', () {
    ReaderVisiblePositionCoordinator<String> restored([String at = 'worsley']) {
      final coordinator = ReaderVisiblePositionCoordinator<String>(
        sessionId: 'reader-1',
        readerGeneration: 7,
      );
      final restore = coordinator.beginInitialRestore(
        target: at,
        reason: 'checkpoint_restore',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 11,
      )!;
      expect(
        coordinator
            .completeIntent(
              intent: restore,
              resolvedLocation: at,
              windowGeneration: 3,
              publicationGeneration: 11,
            )
            .accepted,
        isTrue,
      );
      return coordinator;
    }

    test('late older restore future cannot move a completed restore', () {
      final coordinator = ReaderVisiblePositionCoordinator<String>(
        sessionId: 'reader-1',
        readerGeneration: 1,
      );
      final restore = coordinator.beginInitialRestore(
        target: 'worsley',
        reason: 'journal_checkpoint',
        expectedWindowGeneration: 1,
        expectedPublicationGeneration: 1,
      )!;
      expect(
        coordinator
            .completeIntent(
              intent: restore,
              resolvedLocation: 'worsley',
              windowGeneration: 1,
              publicationGeneration: 1,
            )
            .accepted,
        isTrue,
      );

      final late = coordinator.completeIntent(
        intent: restore,
        resolvedLocation: 'caird',
        windowGeneration: 1,
        publicationGeneration: 1,
      );

      expect(late.accepted, isFalse);
      expect(late.reason, 'intent_consumed');
      expect(coordinator.committedLocation, 'worsley');
      expect(
        coordinator.beginInitialRestore(
          target: 'legacy-metadata',
          reason: 'late_legacy_restore',
          expectedWindowGeneration: 1,
          expectedPublicationGeneration: 1,
        ),
        isNull,
      );
    });

    test('initial controller settlement commits before later user swipes', () {
      final coordinator = ReaderVisiblePositionCoordinator<String>(
        sessionId: 'reader-restore-swipe',
        readerGeneration: 1,
      );
      final restore = coordinator.beginInitialRestore(
        target: 'page-a',
        reason: 'checkpoint_restore',
        expectedWindowGeneration: 2,
        expectedPublicationGeneration: 4,
      )!;

      expect(coordinator.markControllerMoved(restore), isTrue);
      expect(
        coordinator
            .completeIntent(
              intent: restore,
              resolvedLocation: 'page-a',
              windowGeneration: 2,
              publicationGeneration: 4,
            )
            .accepted,
        isTrue,
      );
      expect(coordinator.activeIntent, isNull);
      expect(coordinator.settleUser('page-b').accepted, isTrue);
      expect(coordinator.settleUser('page-c').accepted, isTrue);
      expect(coordinator.committedLocation, 'page-c');
    });

    test('generation rejection consumes the current controller intent', () {
      final coordinator = restored('page-a');
      final intent = coordinator.beginExplicit(
        target: 'page-b',
        reason: 'next_arrow',
        expectedWindowGeneration: 2,
        expectedPublicationGeneration: 4,
      )!;
      coordinator.markControllerMoved(intent);

      final decision = coordinator.completeIntent(
        intent: intent,
        resolvedLocation: 'page-b',
        windowGeneration: 3,
        publicationGeneration: 4,
      );

      expect(decision.accepted, isFalse);
      expect(decision.reason, 'window_generation_mismatch');
      expect(intent.isConsumed, isTrue);
      expect(coordinator.activeIntent, isNull);
      expect(coordinator.isGestureSuppressed, isFalse);
      expect(coordinator.settleUser('page-c').accepted, isTrue);
    });

    test('lazy publication restore settles before a user swipe', () {
      final coordinator = ReaderVisiblePositionCoordinator<String>(
        sessionId: 'lazy-restore',
        readerGeneration: 1,
      );
      final restore = coordinator.beginInitialRestore(
        target: 'page-a',
        reason: 'lazy_initial_restore',
        expectedWindowGeneration: 1,
        expectedPublicationGeneration: 1,
      )!;
      expect(
        coordinator.markWindowPublished(
          intent: restore,
          resolvedLocation: 'page-a',
          windowGeneration: 2,
          publicationGeneration: 3,
        ),
        isTrue,
      );
      coordinator.markControllerMoved(restore);
      expect(
        coordinator
            .completeIntent(
              intent: restore,
              resolvedLocation: 'page-a',
              windowGeneration: 2,
              publicationGeneration: 3,
            )
            .accepted,
        isTrue,
      );

      expect(coordinator.settleUser('page-b').accepted, isTrue);
      expect(coordinator.committedLocation, 'page-b');
      expect(coordinator.activeIntent, isNull);
    });

    test('correction is scoped to generation controller and reader', () {
      final coordinator = restored('page-a');
      final oldController = Object();
      final currentController = Object();
      final first = coordinator.requestCorrection(
        target: 'page-a',
        reason: 'first',
        expectedWindowGeneration: 2,
        expectedPublicationGeneration: 4,
        controllerIdentity: oldController,
      )!;
      final latest = coordinator.requestCorrection(
        target: 'page-a',
        reason: 'latest',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 5,
        controllerIdentity: currentController,
      )!;

      expect(first.phase, ReaderVisibleCorrectionPhase.superseded);
      expect(
        coordinator.isCurrentCorrection(
          first,
          windowGeneration: 2,
          publicationGeneration: 4,
          controllerIdentity: oldController,
        ),
        isFalse,
      );
      expect(
        coordinator.isCurrentCorrection(
          latest,
          windowGeneration: 3,
          publicationGeneration: 5,
          controllerIdentity: currentController,
        ),
        isTrue,
      );
      coordinator.dispose();
      expect(
        coordinator.isCurrentCorrection(
          latest,
          windowGeneration: 3,
          publicationGeneration: 5,
          controllerIdentity: currentController,
        ),
        isFalse,
      );
      expect(latest.phase, ReaderVisibleCorrectionPhase.cancelled);
    });

    test('slow cache and pagination orderings cannot own position', () {
      for (final order in [
        ['cache', 'pagination'],
        ['pagination', 'cache'],
      ]) {
        final coordinator = ReaderVisiblePositionCoordinator<String>(
          sessionId: 'reader-$order',
          readerGeneration: 1,
        );
        final restore = coordinator.beginInitialRestore(
          target: 'worsley',
          reason: 'checkpoint_restore',
          expectedWindowGeneration: 2,
          expectedPublicationGeneration: 4,
        )!;
        for (final source in order) {
          expect(
            coordinator
                .rejectSynthetic(reason: '${source}_publication')
                .accepted,
            isFalse,
          );
          expect(coordinator.authoritativeTarget, 'worsley');
        }
        coordinator.completeIntent(
          intent: restore,
          resolvedLocation: 'worsley',
          windowGeneration: 2,
          publicationGeneration: 4,
        );
        expect(coordinator.committedLocation, 'worsley');
      }
    });

    test('prepend trim replacement and rebase preserve source anchor', () {
      final coordinator = restored();
      for (final operation in ['prepend', 'trim', 'replace', 'rebase']) {
        expect(coordinator.canPublishPreserving('worsley'), isTrue);
        expect(
          coordinator.rejectSynthetic(reason: operation).accepted,
          isFalse,
        );
        expect(coordinator.committedLocation, 'worsley');
      }
      expect(coordinator.canPublishPreserving('window-edge'), isFalse);
    });

    test('old publication after user swipes cannot return to old page', () {
      final coordinator = restored('page-a');
      expect(coordinator.settleUser('page-b').accepted, isTrue);
      expect(coordinator.settleUser('page-c').accepted, isTrue);

      final late = coordinator.rejectSynthetic(reason: 'old_window_build');

      expect(late.accepted, isFalse);
      expect(coordinator.committedLocation, 'page-c');
    });

    test('synthetic controller callback cannot commit a location', () {
      final coordinator = restored();

      final synthetic = coordinator.rejectSynthetic(
        reason: 'controller_correction_callback',
      );

      expect(synthetic.accepted, isFalse);
      expect(coordinator.committedLocation, 'worsley');
    });

    test('latest explicit target applies once and is consumed', () {
      final coordinator = restored();
      final search = coordinator.beginExplicit(
        target: 'search-target',
        reason: 'search',
        expectedWindowGeneration: 8,
        expectedPublicationGeneration: 13,
      )!;
      final bookmark = coordinator.beginExplicit(
        target: 'bookmark-target',
        reason: 'bookmark',
        expectedWindowGeneration: 8,
        expectedPublicationGeneration: 13,
      )!;

      expect(
        coordinator
            .completeIntent(
              intent: search,
              resolvedLocation: 'search-target',
              windowGeneration: 8,
              publicationGeneration: 13,
            )
            .accepted,
        isFalse,
      );
      expect(
        coordinator
            .completeIntent(
              intent: bookmark,
              resolvedLocation: 'bookmark-target',
              windowGeneration: 8,
              publicationGeneration: 13,
            )
            .accepted,
        isTrue,
      );
      expect(bookmark.isConsumed, isTrue);
      expect(bookmark.phase, ReaderVisibleNavigationPhase.settled);
      expect(coordinator.isGestureSuppressed, isFalse);
      expect(
        coordinator
            .completeIntent(
              intent: bookmark,
              resolvedLocation: 'bookmark-target',
              windowGeneration: 8,
              publicationGeneration: 13,
            )
            .accepted,
        isFalse,
      );
    });

    test('chapter jump within the loaded window settles and unlocks', () {
      final coordinator = restored('chapter-before');
      final intent = coordinator.beginExplicit(
        target: 'loaded-chapter',
        reason: 'chapter',
        expectedWindowGeneration: 5,
        expectedPublicationGeneration: 9,
      )!;

      expect(coordinator.markControllerMoved(intent), isTrue);
      final settled = coordinator.completeIntent(
        intent: intent,
        resolvedLocation: 'loaded-chapter',
        windowGeneration: 5,
        publicationGeneration: 9,
      );

      expect(settled.accepted, isTrue);
      expect(coordinator.committedLocation, 'loaded-chapter');
      expect(coordinator.activeIntent, isNull);
      expect(coordinator.isGestureSuppressed, isFalse);
    });

    test('unloaded chapter intent survives its publication then settles', () {
      final coordinator = restored('chapter-before');
      final intent = coordinator.beginExplicit(
        target: 'chapter-request',
        reason: 'chapter',
        expectedWindowGeneration: 5,
        expectedPublicationGeneration: 9,
      )!;

      expect(coordinator.isGestureSuppressed, isTrue);
      expect(
        coordinator.resolveIntentTarget(
          intent: intent,
          target: 'chapter-resolved',
          expectedWindowGeneration: 5,
          expectedPublicationGeneration: 9,
        ),
        isTrue,
      );
      expect(
        coordinator.markWindowPublished(
          intent: intent,
          resolvedLocation: 'chapter-resolved',
          windowGeneration: 6,
          publicationGeneration: 10,
        ),
        isTrue,
      );

      expect(coordinator.activeIntent, same(intent));
      expect(intent.phase, ReaderVisibleNavigationPhase.windowPublished);
      expect(intent.expectedWindowGeneration, 6);
      expect(intent.expectedPublicationGeneration, 10);
      expect(coordinator.committedLocation, 'chapter-before');
      expect(coordinator.markControllerMoved(intent), isTrue);

      final settled = coordinator.completeIntent(
        intent: intent,
        resolvedLocation: 'chapter-resolved',
        windowGeneration: 6,
        publicationGeneration: 10,
      );

      expect(settled.accepted, isTrue);
      expect(coordinator.committedLocation, 'chapter-resolved');
      expect(coordinator.activeIntent, isNull);
      expect(coordinator.isGestureSuppressed, isFalse);
    });

    test('intent is consumed only after controller-visible settlement', () {
      final coordinator = restored('before');
      final intent = coordinator.beginExplicit(
        target: 'after',
        reason: 'next_arrow',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 11,
      )!;

      coordinator.markWindowPublished(
        intent: intent,
        resolvedLocation: 'after',
        windowGeneration: 3,
        publicationGeneration: 11,
      );
      expect(intent.isConsumed, isFalse);
      expect(coordinator.committedLocation, 'before');
      expect(coordinator.markControllerMoved(intent), isTrue);
      expect(intent.isConsumed, isFalse);

      final settled = coordinator.completeIntent(
        intent: intent,
        resolvedLocation: 'after',
        windowGeneration: 3,
        publicationGeneration: 11,
      );

      expect(settled.accepted, isTrue);
      expect(coordinator.committedLocation, 'after');
      expect(coordinator.activeIntent, isNull);
      expect(coordinator.isGestureSuppressed, isFalse);
    });

    test('rapid explicit commands leave only the latest intent valid', () {
      final coordinator = restored('page-a');
      final first = coordinator.beginExplicit(
        target: 'page-b',
        reason: 'next_arrow',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 11,
      )!;
      final latest = coordinator.beginExplicit(
        target: 'page-c',
        reason: 'next_arrow',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 11,
      )!;

      expect(first.isConsumed, isTrue);
      expect(first.phase, ReaderVisibleNavigationPhase.cancelled);
      expect(coordinator.isCurrent(first), isFalse);
      expect(coordinator.isCurrent(latest), isTrue);
      expect(
        coordinator
            .completeIntent(
              intent: first,
              resolvedLocation: 'page-b',
              windowGeneration: 3,
              publicationGeneration: 11,
            )
            .accepted,
        isFalse,
      );
      expect(coordinator.committedLocation, 'page-a');
    });

    test('previous and next arrows settle within the current window', () {
      final coordinator = restored('page-b');
      for (final target in ['page-a', 'page-c']) {
        final intent = coordinator.beginExplicit(
          target: target,
          reason: target == 'page-a' ? 'previous_arrow' : 'next_arrow',
          expectedWindowGeneration: 3,
          expectedPublicationGeneration: 11,
        )!;
        expect(coordinator.markControllerMoved(intent), isTrue);

        final decision = coordinator.completeIntent(
          intent: intent,
          resolvedLocation: target,
          windowGeneration: 3,
          publicationGeneration: 11,
        );

        expect(decision.accepted, isTrue);
        expect(coordinator.committedLocation, target);
        expect(coordinator.activeIntent, isNull);
        expect(coordinator.isGestureSuppressed, isFalse);
      }
    });

    test('arrow intent survives lazy-window extension and then settles', () {
      final coordinator = restored('window-edge');
      final intent = coordinator.beginExplicit(
        target: 'adjacent-stable-card',
        reason: 'next_arrow',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 11,
      )!;

      expect(coordinator.authoritativeTarget, 'window-edge');
      expect(coordinator.canPublishPreserving('window-edge'), isTrue);
      expect(coordinator.canPublishPreserving('adjacent-stable-card'), isFalse);
      expect(
        coordinator.resolveIntentTarget(
          intent: intent,
          target: 'adjacent-stable-card',
          expectedWindowGeneration: 3,
          expectedPublicationGeneration: 11,
        ),
        isTrue,
      );
      expect(coordinator.authoritativeTarget, 'adjacent-stable-card');

      expect(
        coordinator.markWindowPublished(
          intent: intent,
          resolvedLocation: 'adjacent-stable-card',
          windowGeneration: 4,
          publicationGeneration: 12,
        ),
        isTrue,
      );
      expect(coordinator.committedLocation, 'window-edge');
      coordinator.markControllerMoved(intent);
      final decision = coordinator.completeIntent(
        intent: intent,
        resolvedLocation: 'adjacent-stable-card',
        windowGeneration: 4,
        publicationGeneration: 12,
      );

      expect(decision.accepted, isTrue);
      expect(coordinator.committedLocation, 'adjacent-stable-card');
    });

    test('intent-driven controller callback is not rejected as synthetic', () {
      final coordinator = restored('before');
      final intent = coordinator.beginExplicit(
        target: 'visible-target',
        reason: 'chapter',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 11,
      )!;
      coordinator.markControllerMoved(intent);

      final callback = coordinator.completeIntent(
        intent: intent,
        resolvedLocation: 'visible-target',
        windowGeneration: 3,
        publicationGeneration: 11,
      );

      expect(callback.accepted, isTrue);
      expect(callback.reason, 'explicit_intent_committed');
    });

    test('search Book Memory and bookmark intents still settle', () {
      final coordinator = restored('before');
      for (final reason in ['search', 'book_memory', 'bookmark']) {
        final target = '$reason-target';
        final intent = coordinator.beginExplicit(
          target: target,
          reason: reason,
          expectedWindowGeneration: 3,
          expectedPublicationGeneration: 11,
        )!;
        coordinator.markControllerMoved(intent);
        expect(
          coordinator
              .completeIntent(
                intent: intent,
                resolvedLocation: target,
                windowGeneration: 3,
                publicationGeneration: 11,
              )
              .accepted,
          isTrue,
        );
      }
      expect(coordinator.committedLocation, 'bookmark-target');
    });

    test('failed resolution clears intent and gesture suppression', () {
      final coordinator = restored('existing');
      final intent = coordinator.beginExplicit(
        target: 'missing',
        reason: 'chapter',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 11,
      )!;

      coordinator.cancelActiveIntent(failed: true);

      expect(intent.phase, ReaderVisibleNavigationPhase.failed);
      expect(coordinator.activeIntent, isNull);
      expect(coordinator.committedLocation, 'existing');
      expect(coordinator.isGestureSuppressed, isFalse);
    });

    test('intent computed for an old window generation is rejected', () {
      final coordinator = restored();
      final intent = coordinator.beginExplicit(
        target: 'chapter-target',
        reason: 'book_memory',
        expectedWindowGeneration: 5,
        expectedPublicationGeneration: 9,
      )!;

      final stale = coordinator.completeIntent(
        intent: intent,
        resolvedLocation: 'chapter-target',
        windowGeneration: 6,
        publicationGeneration: 9,
      );

      expect(stale.accepted, isFalse);
      expect(stale.reason, 'window_generation_mismatch');
      expect(coordinator.committedLocation, 'worsley');
    });

    test(
      'unresolvable anchor rejects publication without an edge fallback',
      () {
        final coordinator = restored();

        expect(coordinator.canPublishPreserving('missing-anchor'), isFalse);
        expect(coordinator.committedLocation, 'worsley');
      },
    );

    test('disposed reader invalidates work retained by its session', () {
      final oldReader = restored();
      final retained = oldReader.beginExplicit(
        target: 'old-reader-target',
        reason: 'search',
        expectedWindowGeneration: 3,
        expectedPublicationGeneration: 11,
      )!;
      oldReader.dispose();
      final reopened = restored('last-swipe');

      expect(
        oldReader
            .completeIntent(
              intent: retained,
              resolvedLocation: 'old-reader-target',
              windowGeneration: 3,
              publicationGeneration: 11,
            )
            .accepted,
        isFalse,
      );
      expect(reopened.committedLocation, 'last-swipe');
    });
  });
}
