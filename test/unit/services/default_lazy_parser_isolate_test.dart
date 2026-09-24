import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';

import '../../reader_contract/regression/support/lazy_address_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'I01 default worker exits before foreground reuses its single slot',
    () async {
      final run = await _Run.open(hold: {0});
      addTearDown(run.close);
      final speculative = run.session.loadSection(
        0,
        priority: LazySectionWorkPriority.boundaryPrefetch,
      );
      final cancelled = expectLater(
        speculative,
        throwsA(isA<SharedSectionWorkCancelled>()),
      );
      await run.started(0);
      final joined = run.session.loadSection(
        0,
        priority: LazySectionWorkPriority.boundaryPrefetch,
      );
      final joinedCancelled = expectLater(
        joined,
        throwsA(isA<SharedSectionWorkCancelled>()),
      );
      expect(run.live, {0});
      final target = run.session.resolveChapterTarget(
        run.session.index.chapters[1],
      )!;
      final demand = run.session.prepareNavigation(
        target,
        canCommit: () => true,
      );
      await Future.wait([cancelled, joinedCancelled]);
      final prepared = await demand;
      expect(prepared.superseded, isFalse);
      expect(prepared.window!.sections.single.identity.spineIndex, 1);
      expect(run.session.currentLocation!.spineIndex, 1);
      expect(run.session.loadedSpineIndices, [1]);
      expect(run.repository.retainedSpineIndices, [1]);
      expect(
        run.events.indexOf('started:0'),
        lessThan(run.events.indexOf('killSent:0')),
      );
      expect(
        run.events.indexOf('killSent:0'),
        lessThan(run.events.indexOf('exited:0')),
      );
      expect(
        run.events.indexOf('exited:0'),
        lessThan(run.events.indexOf('spawnRequested:1')),
      );
      expect(run.events.where((e) => e == 'spawnRequested:0'), hasLength(1));
      expect(run.maximumLive, 1);
      expect(run.live, isEmpty);
      expect(run.coordinator.activeJobCount, 0);
      // This port belongs to the physically exited worker. Releasing it cannot
      // resurrect a result; the successor's completed lifecycle is our barrier.
      run.resume[0]!.send(null);
      await run.session.close();
      expect(run.events, isNot(contains('resultReceived:0')));
      expect(run.writes, isEmpty);
      expect(await run.cache.loadSection(run.identities[0]!), isNull);
      run.printTrace('I01');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'I02 closing session exits active worker and settles queued work',
    () async {
      final run = await _Run.open(hold: {0});
      addTearDown(run.close);
      final active = run.session.loadSection(
        0,
        priority: LazySectionWorkPriority.boundaryPrefetch,
      );
      final activeCancelled = expectLater(
        active,
        throwsA(isA<SharedSectionWorkCancelled>()),
      );
      await run.started(0);
      final queued = run.session.loadSection(
        1,
        priority: LazySectionWorkPriority.boundaryPrefetch,
      );
      final queuedCancelled = expectLater(
        queued,
        throwsA(isA<SharedSectionWorkCancelled>()),
      );
      expect(run.coordinator.activeJobCount, 2);
      expect(run.live, {0});
      await run.session.close();
      run.events.add('closeCompleted');
      await Future.wait([activeCancelled, queuedCancelled]);
      expect(
        run.events,
        containsAllInOrder([
          'spawnRequested:0',
          'started:0',
          'killSent:0',
          'exited:0',
          'closeCompleted',
        ]),
      );
      expect(run.events, isNot(contains('spawnRequested:1')));
      expect(run.events, isNot(contains('resultReceived:0')));
      expect(run.live, isEmpty);
      expect(run.maximumLive, 1);
      expect(run.coordinator.activeJobCount, 0);
      expect(run.session.currentLocation, isNull);
      expect(run.session.loadedSpineIndices, isEmpty);
      expect(run.repository.retainedSpineIndices, isEmpty);
      expect(run.writes, isEmpty);
      expect(await run.cache.loadSection(run.identities[0]!), isNull);
      run.printTrace('I02');
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  for (final close in [false, true]) {
    test(
      'I03 default worker real result is rejected after ${close ? "close" : "supersession"}',
      () async {
        final run = await _Run.open(hold: {0});
        addTearDown(run.close);
        final target = run.session.resolveChapterTarget(
          run.session.index.chapters[0],
        )!;
        final old = run.session.prepareNavigation(
          target,
          canCommit: () => true,
        );
        final oldCancelled = expectLater(
          old,
          throwsA(isA<SharedSectionWorkCancelled>()),
        );
        await run.started(0);
        Future<void>? closing;
        Future<ParsedSection>? successor;
        // The observation runs only after a genuine ParsedSection traverses the
        // default worker's result port, before production admission checks.
        run.afterResult = (spine) {
          if (spine != 0) return;
          run.events.add(close ? 'closeRequested' : 'foregroundRequested');
          if (close) {
            closing = run.session.close();
          } else {
            // Unlike prepareNavigation's resolver, loadSection registers the
            // foreground demand synchronously before its first await.
            successor = run.session.loadSection(1);
          }
        };
        run.resume[0]!.send(null);
        await oldCancelled;
        run.events.add('oldSettledCancelled');
        expect(run.events, contains('resultReceived:0'));
        expect(
          run.events.indexOf('resultReceived:0'),
          lessThan(run.events.indexOf('oldSettledCancelled')),
        );
        expect(run.events, contains('exited:0'));
        if (close) {
          await closing!;
          expect(run.session.currentLocation, isNull);
          expect(run.session.loadedSpineIndices, isEmpty);
          expect(run.repository.retainedSpineIndices, isEmpty);
        } else {
          final parsed = await successor!;
          expect(
            parsed.chunks.map((c) => c.text).join(' '),
            contains('Section 2 text.'),
          );
          final latestTarget = run.session.resolveChapterTarget(
            run.session.index.chapters[1],
          )!;
          final latest = await run.session.prepareNavigation(
            latestTarget,
            canCommit: () => true,
          );
          expect(latest.window!.sections.single.identity.spineIndex, 1);
          expect(run.session.currentLocation!.spineIndex, 1);
          expect(run.session.loadedSpineIndices, [1]);
          expect(run.repository.retainedSpineIndices, [1]);
          expect(
            run.events.indexOf('exited:0'),
            lessThan(run.events.indexOf('spawnRequested:1')),
          );
        }
        expect(run.maximumLive, 1);
        expect(run.live, isEmpty);
        expect(run.coordinator.activeJobCount, 0);
        expect(run.writes, isEmpty);
        expect(await run.cache.loadSection(run.identities[0]!), isNull);
        run.printTrace(close ? 'I03-close' : 'I03-supersede');
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }

  test(
    'I04 unhooked default parser returns valid production section',
    () async {
      final run = await _Run.open(observe: false);
      addTearDown(run.close);
      final target = run.session.resolveChapterTarget(
        run.session.index.chapters[1],
      )!;
      final prepared = await run.session.prepareNavigation(
        target,
        canCommit: () => true,
      );
      final section = prepared.window!.sections.single;
      expect(section.identity.spineIndex, 1);
      expect(
        section.identity.sourceChecksum,
        run.session.index.spine[1].sourceChecksum,
      );
      expect(section.parserVersion, lazyParsedSectionParserVersion);
      expect(
        section.chunks.map((c) => c.text).join(' '),
        contains('Section 2 text.'),
      );
      expect(section.anchorMap, contains('s2'));
      expect(prepared.superseded, isFalse);
      expect(run.session.currentLocation!.spineIndex, 1);
      expect(run.coordinator.activeJobCount, 0);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

class _Run {
  late Directory root;
  late ParsedSectionCacheService cache;
  late LazySectionRepository repository;
  late LazyBookSession session;
  final coordinator = SharedLazySectionWorkCoordinator();
  final events = <String>[];
  final live = <int>{};
  int maximumLive = 0;
  final resume = <int, SendPort>{};
  final identities = <int, LazySectionIdentity>{};
  final _started = <int, Completer<void>>{};
  final writes = <int>[];
  void Function(int)? afterResult;

  Future<void> started(int spine) =>
      (_started[spine] ??= Completer<void>()).future;

  static Future<_Run> open({
    Set<int> hold = const {},
    bool observe = true,
  }) async {
    final run = _Run();
    run.root = await Directory.systemTemp.createTemp('nalori-default-isolate-');
    final epub = await File(
      '${run.root.path}/workers.epub',
    ).writeAsBytes(buildAddressFixture(sectionCount: 3));
    run.cache = ParsedSectionCacheService(
      rootDirectory: Directory('${run.root.path}/cache'),
      beforePhysicalWrite: (section) async =>
          run.writes.add(section.identity.spineIndex),
    );
    run.repository = LazySectionRepository(
      cache: run.cache,
      workCoordinator: run.coordinator,
      // Deliberately no parser argument: this must execute the production
      // _defaultLazySectionParser -> Isolate.spawn -> _parseSectionWorker.
      isolateTestAccess: observe
          ? LazyParserIsolateTestAccess(
              onStarted: (identity, port) {
                final spine = identity.spineIndex;
                run.events.add('started:$spine');
                run.resume[spine] = port;
                (run._started[spine] ??= Completer<void>()).complete();
                if (!hold.contains(spine)) port.send(null);
              },
              onEvent: (identity, event) {
                final spine = identity.spineIndex;
                run.identities[spine] = identity;
                run.events.add('${event.name}:$spine');
                if (event == LazyParserIsolateEvent.spawnRequested) {
                  expect(run.live.add(spine), isTrue);
                  if (run.live.length > run.maximumLive) {
                    run.maximumLive = run.live.length;
                  }
                } else if (event == LazyParserIsolateEvent.exited) {
                  expect(run.live.remove(spine), isTrue);
                } else if (event == LazyParserIsolateEvent.resultReceived) {
                  run.afterResult?.call(spine);
                }
              },
            )
          : null,
    );
    run.session = LazyBookSession(repository: run.repository);
    await run.session.open(epub);
    return run;
  }

  void printTrace(String name) {
    // ignore: avoid_print
    print(
      '$name workerLifecycle=$events maxSpawnToExit=$maximumLive writes=$writes',
    );
  }

  Future<void> close() async {
    final closing = session.close();
    for (final port in resume.values) {
      port.send(null);
    }
    await closing;
    if (await root.exists()) await root.delete(recursive: true);
  }
}
