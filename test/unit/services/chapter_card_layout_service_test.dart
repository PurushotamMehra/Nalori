import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/services/chapter_card_layout_service.dart';

void main() {
  ChapterCardLayoutKey key(String settings) => ChapterCardLayoutKey(
    bookId: 'book.epub',
    publicationFingerprint: 'publication',
    chapterIdentity: 'chapter-1:0:chapter-2:0',
    parserSchema: 2,
    displaySchema: 'display-v3',
    settingsSignature: settings,
    viewportSignature: '400x800|portrait',
    cardMode: true,
  );

  StableBookLocation location(int offset) => StableBookLocation(
    bookId: 'book.epub',
    spineIndex: 1,
    href: 'chapter-1.xhtml',
    sourceChecksum: 'checksum',
    publicationFingerprint: 'publication',
    localChunkIndex: 0,
    textOffset: offset,
  );

  ChapterCardLayout layout(ChapterCardLayoutKey key, [int pages = 3]) {
    return ChapterCardLayout(
      key: key,
      pages: List.generate(
        pages,
        (index) => ChapterCardSourceRange(
          start: location(index * 100),
          end: location((index + 1) * 100),
        ),
      ),
      completedAtMs: 1,
    );
  }

  test('complete layout maps exact within-chunk cards to page numbers', () {
    final complete = layout(key('layout-a'));

    expect(complete.pageNumberFor(location(0)), 1);
    expect(complete.pageNumberFor(location(145)), 2);
    expect(complete.pageNumberFor(location(299)), 3);
    expect(complete.totalCards, 3);
  });

  test('cached total is reused without starting generation', () async {
    final coordinator = ChapterCardLayoutCoordinator();
    final cached = layout(key('layout-a'));
    var generated = 0;

    final result = await coordinator.ensure(
      key: cached.key,
      load: () async => cached,
      generate: (_) async {
        generated++;
        return cached;
      },
    );

    expect(result, same(cached));
    expect(generated, 0);
  });

  test('layout change invalidates only the changed layout key', () async {
    final coordinator = ChapterCardLayoutCoordinator();
    final first = layout(key('layout-a'));
    final second = layout(key('layout-b'), 4);

    expect(
      await coordinator.ensure(
        key: first.key,
        load: () async => first,
        generate: (_) async => null,
      ),
      same(first),
    );
    expect(
      await coordinator.ensure(
        key: second.key,
        load: () async => second,
        generate: (_) async => null,
      ),
      same(second),
    );
    expect(second.totalCards, 4);
  });

  test(
    'stale chapter counting cannot publish over the latest chapter',
    () async {
      final coordinator = ChapterCardLayoutCoordinator();
      final firstBarrier = Completer<ChapterCardLayout?>();
      final first = layout(key('layout-a'));
      final second = layout(key('layout-b'));

      final firstFuture = coordinator.ensure(
        key: first.key,
        load: () async => null,
        generate: (_) => firstBarrier.future,
      );
      final secondFuture = coordinator.ensure(
        key: second.key,
        load: () async => second,
        generate: (_) async => null,
      );
      firstBarrier.complete(first);

      expect(await firstFuture, isNull);
      expect(await secondFuture, same(second));
      expect(coordinator.published, same(second));
    },
  );

  test(
    'cancelled counting stays unpublished and does not block reading',
    () async {
      final coordinator = ChapterCardLayoutCoordinator();
      final barrier = Completer<ChapterCardLayout?>();
      final expected = layout(key('layout-a'));
      var visibleCardPublished = false;

      final future = coordinator.ensure(
        key: expected.key,
        load: () async => null,
        generate: (_) => barrier.future,
      );
      visibleCardPublished = true;
      coordinator.cancel();
      barrier.complete(expected);

      expect(visibleCardPublished, isTrue);
      expect(await future, isNull);
      expect(coordinator.published, isNull);
    },
  );
}
