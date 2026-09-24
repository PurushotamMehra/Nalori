import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// Existing transitive SQLite test dependency, as in the P02 sandbox.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/open.dart';
// Existing SQLite dependency; read-only audit of the real journal.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/reader_checkpoint_store.dart';
import 'package:nalori/services/reading_stats_service.dart';

import '../pagination/reader_core_pagination_harness.dart';
import 'support/lazy_address_fixture.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/lazy_checkpoint_recovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReaderCoreParsedFixture fixture;
  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('handoff-screen-');
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    GoogleFonts.config.allowRuntimeFetching = false;
    // UI chrome requests Google Fonts names; serve the real bundled Inter
    // bytes under those names. Reader Lexend evidence uses unchanged assets.
    final manifest =
        const StandardMessageCodec().decodeMessage(
              await rootBundle.load('AssetManifest.bin'),
            )!
            as Map;
    final aliases = <String, String>{};
    for (final entry in {
      400: 'Regular',
      500: 'Medium',
      600: 'SemiBold',
      700: 'Bold',
      800: 'ExtraBold',
    }.entries) {
      final alias = 'assets/Inter-${entry.value}.ttf';
      aliases[alias] = 'assets/fonts/reader/Inter-${entry.key}-Normal.ttf';
      manifest[alias] = [
        {'asset': alias},
      ];
    }
    final manifestBytes = const StandardMessageCodec().encodeMessage(manifest);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = const StringCodec().decodeMessage(message)!;
          if (key == 'AssetManifest.bin') return manifestBytes;
          final file = File(aliases[key] ?? 'build/unit_test_assets/$key');
          if (!await file.exists()) return null;
          return ByteData.sublistView(await file.readAsBytes());
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => fixture.temporaryDirectory.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('reader_controls'),
          (_) async => null,
        );
  });
  tearDownAll(() async {
    await fixture.close();
  });

  var sequence = 0;
  var storeSequence = 0;
  late ReaderCheckpointStore activeStore;
  late String databasePath;
  setUp(() {
    databasePath =
        '${fixture.temporaryDirectory.path}/authority-${storeSequence++}.sqlite';
    activeStore = ReaderCheckpointStore.forTesting(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: databasePath,
    );
  });
  Future<_ScreenRun> mount(
    WidgetTester tester, {
    int? heldParse,
    bool holdWrite = false,
    bool holdPagination = false,
    bool unavailableCheckpoint = false,
    bool failFirstTarget = false,
    int? failTarget,
    bool failWrite = false,
    bool holdCommit = false,
    bool libraryRoute = false,
    bool holdInitialPreparation = false,
    bool failInitialPreparation = false,
    bool initialExplicitTarget = false,
    File? reopenFile,
    ReaderCheckpoint? savedCheckpoint,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final root = '${fixture.temporaryDirectory.path}/authority-${sequence++}';
    final epub = await tester.runAsync(() async {
      await Directory(root).create(recursive: true);
      if (reopenFile != null) return reopenFile;
      return File(
        '$root/book-$sequence.epub',
      ).writeAsBytes(buildAddressFixture(sectionCount: 10));
    });
    final run = _ScreenRun()..epub = epub!;
    var initial = true;
    var failPreparation = failFirstTarget || failInitialPreparation;
    run.access = ReaderAdjacentWorkTestAccess(
      checkpointStore: activeStore,
      warmupDelay: (_) => run.warmup.future,
      nowMilliseconds: () => run.clockMillis,
      hydrationQuietDelay: (duration) async {
        await run.hydration.future;
        run.clockMillis += duration.inMilliseconds;
      },
      indexQuietDelay: (_) => run.hydration.future,
      beforeTargetPagination: () async {
        run.preparations++;
        if (((!initial || failInitialPreparation) && failPreparation) ||
            run.access.requestedTarget?.spineIndex == failTarget &&
                failTarget != null) {
          failPreparation = false;
          throw const ReaderPreparationException(
            ReaderPreparationFailureKind.paginationRejected,
            'Deterministic target rejection',
          );
        }
        if ((initial && holdInitialPreparation) ||
            (!initial &&
                holdPagination &&
                run.access.requestedTarget?.spineIndex == 5)) {
          if (!run.paginationEntered.isCompleted) {
            run.paginationEntered.complete();
          }
          await run.paginationRelease.future;
        }
      },
      onEvent: (event) {
        run.events.add(event);
        if (event == 'first_card_accepted' || event == 'published') {
          run.publications.add((
            event,
            run.access.operationOwner,
            run.access.acceptedOwner,
            run.access.publicationDigest,
            run.access.readableCardDigest,
          ));
        }
      },
    );
    run.lazy = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory('$root/cache'),
          beforePhysicalWrite: (section) async {
            run.events.add('write_start:${section.identity.spineIndex}');
            if (failWrite && section.identity.spineIndex == 5) {
              throw const FileSystemException('injected write failure');
            }
            if (section.identity.spineIndex == 5 && holdWrite) {
              run.writeEntered.complete();
              await run.writeRelease.future;
            }
          },
          beforePhysicalCommit: (section) async {
            if (holdCommit && section.identity.spineIndex == 5) {
              run.commitEntered.complete();
              await run.commitRelease.future;
            }
          },
          onPhysicalWriteComplete: (section) =>
              run.events.add('write_end:${section.identity.spineIndex}'),
        ),
        workCoordinator: run.work = SharedLazySectionWorkCoordinator(
          onLaunch: (identity, quantum) =>
              run.launchQuanta[identity.spineIndex] = quantum,
        ),
        parser: (request) async {
          run.activeParsers++;
          if (run.activeParsers > run.maximumParsers) {
            run.maximumParsers = run.activeParsers;
          }
          try {
            run.starts.add(request.identity.spineIndex);
            run.events.add('parse:${request.identity.spineIndex}');
            if (request.identity.spineIndex == heldParse) {
              if (!run.parseEntered.isCompleted) run.parseEntered.complete();
              await request.cancellation!.checkpoint(
                run.parseRelease.future,
                request.identity,
              );
            }
            return EpubParserService().parseLazySection(
              identity: request.identity,
              html: request.html,
              section: request.section,
              resourceBytes: request.resourceBytes,
              resourceMediaTypes: request.resourceMediaTypes,
              footnoteContentById: request.footnoteContentById,
            );
          } finally {
            if (request.cancellation!.isCancelled) {
              run.cancelledQuantum = run.work.schedulerQuantum;
            }
            run.activeParsers--;
          }
        },
      ),
    );
    addTearDown(() async {
      await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
      run.releaseAll();
      await tester.runAsync(run.lazy.close);
      await _quanta(tester, 10);
      var statsFlushed = false;
      ReadingStatsService().flushPendingWrites().then(
        (_) => statsFlushed = true,
      );
      await _until(tester, () => statsFlushed);
      var checkpointClosed = false;
      activeStore.close().then((_) => checkpointClosed = true);
      await _until(tester, () => checkpointClosed);
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump(const Duration(seconds: 2));
      ReadingStatsService().clearForTest();
    });
    final window = await tester.runAsync(() async {
      await run.lazy.open(epub);
      return run.lazy.loadAround(run.lazy.initialLocation(), after: 0);
    });
    ReaderCheckpoint? checkpoint = savedCheckpoint;
    if (unavailableCheckpoint) {
      checkpoint = ReaderCheckpoint.create(
        bookId: run.lazy.index.bookId,
        publicationFingerprint: run.lazy.index.publicationFingerprint,
        semanticAnchor: const ReaderSemanticAnchor(
          sectionIdentity: 'missing',
          sectionChecksum: 'missing',
          logicalBlockId: 'missing',
          structuralType: 'text',
          blockOffsetUtf16: 0,
        ),
        card: ReaderCardIdentity(
          publicationFingerprint: run.lazy.index.publicationFingerprint,
          layoutFingerprint: 'legacy',
          ranges: const [
            ReaderCardSourceRange(
              sectionIdentity: 'missing',
              sectionChecksum: 'missing',
              logicalBlockId: 'missing',
              structuralType: 'text',
              startUtf16: 0,
              endUtf16: 1,
            ),
          ],
        ),
        layoutFingerprint: 'legacy',
        state: ReaderCheckpointState.exactCommitted,
        sessionEpoch: 1,
        revision: 1,
        navigationSource: 'test',
      );
    }
    if (unavailableCheckpoint) {
      await tester.runAsync(() async {
        await activeStore.beginSession(run.lazy.index.bookId);
        await activeStore.commit(checkpoint!);
      });
    }
    run.savedCheckpoint = checkpoint;
    final screen = ReaderScreen(
      initialCheckpoint: checkpoint,
      initialLocationIsNavigationTarget: initialExplicitTarget,
      title: 'Authority proof',
      bookId: run.lazy.index.bookId,
      chunks: window!.chunks,
      anchorMap: window.anchorMap,
      chapters: window.chapters,
      searchIndex: window.searchIndex,
      lazySession: run.lazy,
      initialStableLocationsByChunkIndex: window.locationsByChunkIndex,
      initialHasContentAfter: window.hasContentAfter,
      initialSettings: const ReadingSettings(),
      adjacentWorkTestAccess: run.access,
    );
    await tester.runAsync(
      () => tester.pumpWidget(
        libraryRoute
            ? MaterialApp(
                initialRoute: '/reader',
                routes: {
                  '/': (_) => const Scaffold(body: Text('Proof Library')),
                  '/reader': (_) => screen,
                },
              )
            : MaterialApp(home: screen),
      ),
    );
    if (holdInitialPreparation) {
      await _until(tester, () => run.paginationEntered.isCompleted);
      return run;
    }
    await _until(
      tester,
      () =>
          (run.access.cardCount > 0 || run.access.presentedFailure != null) &&
          !run.access.building,
    );
    if (!unavailableCheckpoint &&
        savedCheckpoint == null &&
        !failInitialPreparation) {
      await _until(tester, () => run.access.readyForNavigation);
    }
    initial = false;
    if (savedCheckpoint == null && !unavailableCheckpoint) run.events.clear();
    run.publications.clear();
    return run;
  }

  _screenTestWidgets('A01 RED real foreground preempts held boundary prefetch', (
    tester,
  ) async {
    final run = await mount(tester, heldParse: 1);
    final warm = run.access.forward(reason: 'stable_location_adjacent_warmup');
    await _until(tester, () => run.parseEntered.isCompleted);
    run.access.navigate(run.target(5));
    await _quanta(tester, 30);
    final beforeRelease = List<int>.from(run.starts);
    // ignore: avoid_print
    print(
      'A01 startsBeforeRelease=$beforeRelease owner=${run.access.operationOwner}',
    );
    run.parseRelease.complete();
    await _until(tester, () => run.starts.contains(5));
    await tester.runAsync(() async {
      await warm;
    });
    tester.takeException();
    expect(beforeRelease, contains(5));
    expect(
      run.launchQuanta[5],
      run.cancelledQuantum! + 1,
      reason: 'foreground starts in the next scheduler quantum',
    );
    expect(run.maximumParsers, 1);
  });

  _screenTestWidgets('A02 RED real first card precedes physical cache write', (
    tester,
  ) async {
    final run = await mount(tester, holdWrite: true);
    StableBookLocation? result;
    run.access.navigate(run.target(5)).then((value) => result = value);
    await _until(tester, () => run.writeEntered.isCompleted && result != null);
    final trace = List<String>.from(run.events);
    // ignore: avoid_print
    print('A02 heldWriteTrace=$trace');
    expect(run.events, isNot(contains('write_end:5')));
    run.writeRelease.complete();
    await _until(tester, () => run.events.contains('write_end:5'));
    expect(trace, contains('first_card_accepted'));
    expect(
      trace.indexOf('published'),
      lessThan(trace.indexOf('write_start:5')),
    );
  });

  _screenTestWidgets('A03 RED real private target retains accepted publication', (
    tester,
  ) async {
    final run = await mount(tester, holdPagination: true);
    final oldPublication = run.access.publicationDigest;
    final oldCard = run.access.readableCardDigest;
    run.access.navigate(run.target(5));
    await _until(tester, () => run.paginationEntered.isCompleted);
    final retained = run.access.publicationDigest == oldPublication;
    // ignore: avoid_print
    print(
      'A03 publicationRetained=$retained cardRetained=${run.access.readableCardDigest == oldCard} starts=${run.starts}',
    );
    expect(run.starts, [0, 5]);
    expect(run.access.readableCardDigest, oldCard);
    expect(retained, isTrue);
    final owner = run.access.operationOwner;
    run.paginationRelease.complete();
    await _until(
      tester,
      () => run.access.taskResult == ReaderTargetTaskResult.ready,
    );
    final acceptance = run.publications.firstWhere(
      (e) => e.$1 == 'first_card_accepted',
    );
    final publication = run.publications.firstWhere((e) => e.$1 == 'published');
    expect(acceptance.$2, owner);
    expect(acceptance.$4, oldPublication);
    expect(acceptance.$5, oldCard);
    expect(publication.$3, owner);
    expect(publication.$4, isNot(oldPublication));
    expect(publication.$5, isNot(oldCard));
    expect(run.starts, [0, 5]);
    expect(run.maximumParsers, 1);
    expect(run.access.preparing || run.access.building, isFalse);
  });

  _screenTestWidgets('A05 RED real caught terminal failure settles failure', (
    tester,
  ) async {
    final run = await mount(tester);
    final old = run.access.readableCardDigest;
    bool? result;
    run.access.forward().then((value) => result = value);
    await _until(tester, () => result != null);
    final error = tester.takeException();
    // ignore: avoid_print
    print(
      'A05 result=$result failure=${run.access.failure} surfaced=${run.access.presentedFailure} error=$error',
    );
    expect(run.access.readableCardDigest, old);
    expect(result, isFalse);
  });

  _screenTestWidgets('A06 RED close revokes held target cache callback', (
    tester,
  ) async {
    final run = await mount(tester, heldParse: 5);
    bool settled = false;
    run.access.navigate(run.target(5)).then((_) => settled = true);
    await _until(tester, () => run.parseEntered.isCompleted);
    await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
    run.parseRelease.complete();
    await _until(tester, () => settled);
    // ignore: avoid_print
    print('A06 afterClose=${run.events}');
    expect(run.events, isNot(contains('write_start:5')));
  });

  _screenTestWidgets('A07 RED real unavailable recovery has typed Retry Back', (
    tester,
  ) async {
    final run = await mount(
      tester,
      unavailableCheckpoint: true,
      libraryRoute: true,
    );
    // ignore: avoid_print
    print(
      'A07 recovery=${run.access.recovery} presented=${run.access.presentedFailure} cards=${run.access.cardCount}',
    );
    expect(run.access.recovery, isA<LazyRestorePreparation>());
    expect(
      (run.access.recovery as LazyRestorePreparation).kind,
      LazyRestoreKind.exactUnavailable,
    );
    final checksum = run.savedCheckpoint!.integrityChecksum;
    final initialAttempts = run.preparations;
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Back to library'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await _until(
      tester,
      () => run.preparations == initialAttempts + 1 && !run.access.building,
    );
    expect(run.access.preparing, isFalse);
    expect(
      (await tester.runAsync(
        () => activeStore.loadNewestValid(run.savedCheckpoint!.bookId),
      ))!.integrityChecksum,
      checksum,
    );
    await tester.tap(find.text('Back to library'));
    await _quanta(tester, 40);
    expect(find.text('Proof Library'), findsOneWidget);
    expect(run.access.attached, isFalse);
    expect(await tester.runAsync(run.epub.exists), isTrue);
    expect(
      (await tester.runAsync(
        () => activeStore.loadNewestValid(run.savedCheckpoint!.bookId),
      ))!.integrityChecksum,
      checksum,
    );
  });

  for (final exact in [true, false]) {
    _screenTestWidgets(
      'A08 RED real ${exact ? "exact v2" : "semantic v1"} recovery wiring',
      (tester) async {
        final first = await mount(tester);
        final body = first.access.acceptedStableBodies.first;
        final legacyCard = first.access.readableIdentity!;
        final location = first.access.readableLocation!;
        await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
        first.releaseAll();
        await tester.runAsync(first.lazy.close);
        final store = activeStore;
        final epoch = (await tester.runAsync(
          () => store.beginSession(location.bookId),
        ))!;
        final checkpoint = exact
            ? ReaderCheckpoint.createLazy(
                bookId: location.bookId,
                body: body,
                sessionEpoch: epoch,
                revision: 1,
                committedAtMillis: 1,
              )
            : ReaderCheckpoint.create(
                bookId: location.bookId,
                publicationFingerprint: body.identity.publicationFingerprint,
                card: legacyCard,
                semanticAnchor: legacyCard.firstMeaningfulAnchor(),
                stableLocation: location,
                layoutFingerprint: legacyCard.layoutFingerprint,
                state: ReaderCheckpointState.exactCommitted,
                sessionEpoch: epoch,
                revision: 1,
                navigationSource: 'test',
              );
        await tester.runAsync(() => store.commit(checkpoint));
        final run = await mount(
          tester,
          reopenFile: first.epub,
          savedCheckpoint: checkpoint,
          holdInitialPreparation: true,
        );
        expect(run.access.cardCount, 0);
        expect(
          (await tester.runAsync(
            () => activeStore.loadNewestValid(location.bookId),
          ))!.integrityChecksum,
          checkpoint.integrityChecksum,
        );
        run.paginationRelease.complete();
        await _until(
          tester,
          () => run.access.cardCount > 0 && !run.access.building,
        );
        // ignore: avoid_print
        print(
          'A08 exact=$exact recovery=${(run.access.recovery as LazyRestorePreparation?)?.kind} reason=${(run.access.recovery as LazyRestorePreparation?)?.reason} cards=${run.access.cardCount}',
        );
        await _until(tester, () => run.events.contains('checkpoint_committed'));
        expect(
          run.events.indexOf('checkpoint_committed'),
          greaterThan(run.events.indexOf('published')),
        );
        final restored = (await tester.runAsync(
          () => activeStore.loadNewestValid(location.bookId),
        ))!;
        expect(restored.formatVersion, 2);
        expect(
          restored.payloadJson()['lazyMigration'],
          exact ? isNull : 'lazy_semantic_migration_v1',
        );
        final db = sqlite.sqlite3.open(databasePath);
        final originals = db.select(
          'SELECT integrity_checksum FROM reader_checkpoint_journal WHERE book_id = ? AND session_epoch = ?',
          [location.bookId, epoch],
        );
        expect(
          originals.single['integrity_checksum'],
          checkpoint.integrityChecksum,
        );
        db.dispose();
        expect(run.access.recovery, isA<LazyRestorePreparation>());
        expect(
          (run.access.recovery as LazyRestorePreparation).kind,
          exact
              ? LazyRestoreKind.exactStableBody
              : LazyRestoreKind.semanticMigrationV1,
        );
      },
    );
  }

  _screenTestWidgets('B01 real same-target speculative parsing is promoted', (
    tester,
  ) async {
    final run = await mount(tester, heldParse: 1);
    final warm = run.access.forward(reason: 'stable_location_adjacent_warmup');
    await _until(tester, () => run.parseEntered.isCompleted);
    StableBookLocation? result;
    final demand = run.access.navigate(run.target(1));
    demand.then((value) => result = value);
    expect(run.access.navigate(run.target(1)), same(demand));
    await _quanta(tester, 2);
    expect(run.starts, [0, 1]);
    run.parseRelease.complete();
    await _until(tester, () => result != null);
    await tester.runAsync(() async {
      await warm;
    });
    expect(run.starts, [0, 1]);
    expect(run.access.taskResult, ReaderTargetTaskResult.ready);
    expect(run.access.preparing, isFalse);
  });

  _screenTestWidgets('B10 real hydration target is joined and promoted', (
    tester,
  ) async {
    final run = await mount(tester, heldParse: 1);
    run.hydration.complete();
    run.access.hydrate();
    await _until(tester, () => run.parseEntered.isCompleted);
    final parserCount = run.starts.where((index) => index == 1).length;
    run.access.navigate(run.target(1));
    await _quanta(tester, 2);
    expect(run.parseRelease.isCompleted, isFalse);
    expect(run.cancelledQuantum, isNull);
    run.parseRelease.complete();
    await _until(
      tester,
      () => run.access.taskResult == ReaderTargetTaskResult.ready,
    );
    expect(run.starts.where((index) => index == 1).length, parserCount);
    expect(run.maximumParsers, 1);
  });

  _screenTestWidgets('B02 real latest target wins over held old pagination', (
    tester,
  ) async {
    final run = await mount(tester, holdPagination: true);
    final old = run.access.readableCardDigest;
    bool firstSettled = false;
    StableBookLocation? firstResult;
    run.access.navigate(run.target(5)).then((value) {
      firstResult = value;
      firstSettled = true;
    });
    await _until(tester, () => run.paginationEntered.isCompleted);
    expect(run.access.readableCardDigest, old);
    StableBookLocation? latest;
    run.access.navigate(run.target(9)).then((value) => latest = value);
    final owner = run.access.operationOwner;
    await _until(tester, () => latest != null);
    final accepted = run.access.publicationDigest;
    expect(firstSettled, isTrue);
    expect(firstResult, isNull);
    expect(run.starts, [0, 5, 9]);
    expect(run.access.acceptedOwner, owner);
    expect(run.publications.where((e) => e.$1 == 'published').length, 1);
    run.paginationRelease.complete();
    await _quanta(tester, 20);
    expect(run.access.publicationDigest, accepted);
    expect(run.access.taskResult, ReaderTargetTaskResult.ready);
    expect(run.access.presentedFailure, isNull);
    expect(run.access.preparing || run.access.building, isFalse);
    expect(run.events, isNot(contains('write_start:5')));
  });

  _screenTestWidgets('B09 stale completion preserves newer target failure', (
    tester,
  ) async {
    final run = await mount(tester, holdPagination: true, failTarget: 9);
    final oldCard = run.access.readableCardDigest;
    run.access.navigate(run.target(5));
    await _until(tester, () => run.paginationEntered.isCompleted);
    var settled = false;
    run.access.navigate(run.target(9)).then((_) => settled = true);
    await _until(tester, () => settled);
    expect(tester.takeException(), isA<ReaderPreparationException>());
    final failure = run.access.presentedFailure;
    expect(failure, isNotNull);
    run.paginationRelease.complete();
    await _quanta(tester, 20);
    expect(run.access.presentedFailure, same(failure));
    expect(run.access.taskResult, ReaderTargetTaskResult.failed);
    expect(run.access.readableCardDigest, oldCard);
    expect(run.access.preparing || run.access.building, isFalse);
    expect(run.publications, isEmpty);
  });

  _screenTestWidgets(
    'B03 real deterministic target failure latches until explicit retry',
    (tester) async {
      final run = await mount(tester, failFirstTarget: true);
      final old = run.access.readableCardDigest;
      final publication = run.access.publicationDigest;
      bool settled = false;
      StableBookLocation? result;
      final task = run.access.navigate(run.target(5));
      expect(run.access.navigate(run.target(5)), same(task));
      task.then((value) {
        result = value;
        settled = true;
      });
      await _until(tester, () => settled);
      expect(tester.takeException(), isA<ReaderPreparationException>());
      expect(result, isNull);
      expect(run.access.taskResult, ReaderTargetTaskResult.failed);
      expect(run.access.readableCardDigest, old);
      expect(run.access.publicationDigest, publication);
      final count = run.preparations;
      run.lazy.handleMemoryPressure();
      run.access.hydrate();
      run.access.warmup(run.target(5));
      expect(await run.access.forward(), isFalse);
      await _quanta(tester, 20);
      expect(run.preparations, count);
      expect(
        run.events.where(
          (e) =>
              e == 'hydration_started' ||
              e == 'indexing_started' ||
              e == 'write_start:5',
        ),
        isEmpty,
      );
      expect(run.access.preparing || run.access.building, isFalse);
      await tester.tap(find.text('Retry').first);
      await _until(
        tester,
        () => run.access.taskResult == ReaderTargetTaskResult.ready,
      );
      expect(run.preparations, count + 1);
      expect(run.access.taskResult, ReaderTargetTaskResult.ready);
    },
  );

  _screenTestWidgets('B04 real cache write failure preserves readable target', (
    tester,
  ) async {
    final run = await mount(tester, failWrite: true);
    StableBookLocation? result;
    run.access.navigate(run.target(5)).then((value) => result = value);
    await _until(
      tester,
      () => result != null && run.events.contains('write_start:5'),
    );
    final readable = run.access.readableCardDigest;
    final count = run.preparations;
    await _quanta(tester, 20);
    expect(run.access.readableCardDigest, readable);
    expect(run.preparations, count);
    expect(run.access.presentedFailure, isNull);
    expect(run.access.preparing || run.access.building, isFalse);
  });

  _screenTestWidgets('B05 real same-element book switch revokes old target', (
    tester,
  ) async {
    final old = await mount(tester, heldParse: 5);
    bool settled = false;
    StableBookLocation? oldResult;
    old.access.navigate(old.target(5)).then((value) {
      oldResult = value;
      settled = true;
    });
    await _until(tester, () => old.parseEntered.isCompleted);
    final oldEpoch = old.access.bookOpenEpoch;
    final next = await mount(tester);
    final readable = next.access.readableCardDigest;
    expect(old.access.attached, isFalse);
    expect(next.access.bookOpenEpoch, isNot(oldEpoch));
    expect(settled, isTrue);
    expect(oldResult, isNull);
    old.parseRelease.complete();
    await _quanta(tester, 20);
    expect(next.access.readableCardDigest, readable);
    expect(next.access.presentedFailure, isNull);
    expect(old.events, isNot(contains('write_start:5')));
  });

  _screenTestWidgets(
    'B06 real supersession revokes a held physical cache commit',
    (tester) async {
      final run = await mount(tester, holdCommit: true);
      StableBookLocation? target;
      run.access.navigate(run.target(5)).then((value) => target = value);
      await _until(
        tester,
        () => target != null && run.commitEntered.isCompleted,
      );
      target = null;
      run.access.navigate(run.target(9)).then((value) => target = value);
      await _until(tester, () => target?.spineIndex == 9);
      run.commitRelease.complete();
      await _quanta(tester, 40);
      expect(run.events, isNot(contains('write_end:5')));
      expect(run.access.taskResult, ReaderTargetTaskResult.ready);
      expect(run.access.preparing || run.access.building, isFalse);
    },
  );

  for (final cancel in [true, false]) {
    _screenTestWidgets(
      'B07 real ${cancel ? "cancelled" : "failed"} semantic migration preserves checkpoint',
      (tester) async {
        final first = await mount(tester);
        final legacy = first.access.readableIdentity!;
        final location = first.access.readableLocation!;
        await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
        first.releaseAll();
        await _quanta(tester, 5);
        final epoch = (await tester.runAsync(
          () => activeStore.beginSession(location.bookId),
        ))!;
        final checkpoint = ReaderCheckpoint.create(
          bookId: location.bookId,
          publicationFingerprint: legacy.publicationFingerprint,
          card: legacy,
          semanticAnchor: legacy.firstMeaningfulAnchor(),
          stableLocation: location,
          layoutFingerprint: legacy.layoutFingerprint,
          state: ReaderCheckpointState.exactCommitted,
          sessionEpoch: epoch,
          revision: 1,
          navigationSource: 'migration-proof',
        );
        await tester.runAsync(() => activeStore.commit(checkpoint));
        final run = await mount(
          tester,
          reopenFile: first.epub,
          savedCheckpoint: checkpoint,
          holdInitialPreparation: cancel,
          failInitialPreparation: !cancel,
        );
        if (cancel) {
          await tester.runAsync(
            () => tester.pumpWidget(const SizedBox.shrink()),
          );
          run.paginationRelease.complete();
        } else {
          expect(tester.takeException(), isA<ReaderPreparationException>());
          expect(run.access.preparing || run.access.building, isFalse);
        }
        await _quanta(tester, 20);
        final saved = await tester.runAsync(
          () => activeStore.loadNewestValid(location.bookId),
        );
        expect(saved!.integrityChecksum, checkpoint.integrityChecksum);
        expect(run.events, isNot(contains('checkpoint_committed')));
        expect(run.events, isNot(contains('published')));
      },
    );
  }

  _screenTestWidgets(
    'B08 real hydration and indexing start after accepted target',
    (tester) async {
      final run = await mount(tester);
      run.access.navigate(run.target(5));
      await _until(
        tester,
        () => run.access.taskResult == ReaderTargetTaskResult.ready,
      );
      expect(run.starts, [0, 5]);
      expect(
        run.events.where(
          (e) => e == 'hydration_started' || e == 'indexing_started',
        ),
        isEmpty,
      );
      run.hydration.complete();
      await _until(
        tester,
        () =>
            run.events.contains('hydration_started') &&
            run.events.contains('indexing_started'),
      );
      final publication = run.events.indexOf('published');
      expect(run.events.indexOf('hydration_started'), greaterThan(publication));
      expect(run.events.indexOf('indexing_started'), greaterThan(publication));
      expect(run.maximumParsers, 1);
    },
  );

  _screenTestWidgets('B11 explicit initial target persists accepted lazy v2', (
    tester,
  ) async {
    final run = await mount(tester, initialExplicitTarget: true);
    ReaderCheckpoint? saved;
    for (var i = 0; i < 200 && saved == null; i++) {
      await _quanta(tester, 1);
      saved = await tester.runAsync<ReaderCheckpoint?>(
        () => activeStore.loadNewestValid(run.lazy.index.bookId),
      );
    }
    expect(saved, isNotNull);
    expect(saved!.formatVersion, 2);
    expect(saved.lazyStableBody, isNotNull);
    expect(run.access.preparing || run.access.building, isFalse);
  });

  _screenTestWidgets('A04 RED real identical target joins one future', (
    tester,
  ) async {
    final run = await mount(tester, heldParse: 5);
    final first = run.access.navigate(run.target(5));
    final second = run.access.navigate(run.target(5));
    await _until(tester, () => run.parseEntered.isCompleted);
    // ignore: avoid_print
    print(
      'A04 identicalFuture=${identical(first, second)} parserStarts=${run.starts}',
    );
    expect(first, same(second));
  });
}

Future<void> _quanta(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 2000 && !predicate(); i++) {
    await _quanta(tester, 1);
  }
  expect(predicate(), isTrue, reason: 'deterministic scheduler gate reached');
}

class _ScreenRun {
  ReaderCheckpoint? savedCheckpoint;
  late File epub;
  late ReaderAdjacentWorkTestAccess access;
  late LazyBookSession lazy;
  late SharedLazySectionWorkCoordinator work;
  final launchQuanta = <int, int>{};
  int? cancelledQuantum;
  int clockMillis = 1;
  int activeParsers = 0;
  int maximumParsers = 0;
  int preparations = 0;
  final publications = <(String, int?, int?, String, String)>[];
  final starts = <int>[];
  final events = <String>[];
  final warmup = Completer<void>();
  final hydration = Completer<void>();
  final parseEntered = Completer<void>();
  final parseRelease = Completer<void>();
  final writeEntered = Completer<void>();
  final writeRelease = Completer<void>();
  final commitEntered = Completer<void>();
  final commitRelease = Completer<void>();
  final paginationEntered = Completer<void>();
  final paginationRelease = Completer<void>();
  StableBookLocation target(int spine) =>
      lazy.resolveChapterTarget(lazy.index.chapters[spine])!;
  void releaseAll() {
    for (final gate in [
      warmup,
      hydration,
      parseRelease,
      writeRelease,
      paginationRelease,
      commitRelease,
    ]) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

// Cleanup belongs inside the widget-test body, before Flutter verifies timers.
// Package addTearDown still closes each fixture's real session/database.
void _screenTestWidgets(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
      await _quanta(tester, 10);
      var flushed = false;
      ReadingStatsService().flushPendingWrites().then((_) => flushed = true);
      await _until(tester, () => flushed);
      ReadingStatsService().clearForTest();
    }
  });
}
