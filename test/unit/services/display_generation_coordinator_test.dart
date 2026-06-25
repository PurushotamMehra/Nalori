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
}
