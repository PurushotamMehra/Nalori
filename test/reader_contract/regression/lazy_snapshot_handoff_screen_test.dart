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
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/reader_checkpoint_store.dart';

import '../pagination/reader_core_pagination_harness.dart';

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

  testWidgets('S01 real screen catches terminal failure but must settle failure', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final warmup = Completer<void>();
    final hydration = Completer<void>();
    final parseHeld = Completer<void>();
    var starts = 0;
    final access = ReaderAdjacentWorkTestAccess(
      warmupDelay: (_) => warmup.future,
      hydrationQuietDelay: (_) => hydration.future,
    );
    final lazy = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory(
            '${fixture.temporaryDirectory.path}/screen-cache',
          ),
        ),
        workCoordinator: SharedLazySectionWorkCoordinator(),
        parser: (request) async {
          starts++;
          if (starts > 1) await parseHeld.future;
          return EpubParserService().parseLazySection(
            identity: request.identity,
            html: request.html,
            section: request.section,
            resourceBytes: request.resourceBytes,
            resourceMediaTypes: request.resourceMediaTypes,
            footnoteContentById: request.footnoteContentById,
          );
        },
      ),
    );
    addTearDown(() async {
      if (!parseHeld.isCompleted) parseHeld.complete();
      await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
      if (!warmup.isCompleted) warmup.complete();
      if (!hydration.isCompleted) hydration.complete();
      await tester.runAsync(lazy.close);
      await tester.pump(const Duration(seconds: 2));
    });
    final window = await tester.runAsync(() async {
      await lazy.open(fixture.epubFile);
      return lazy.loadAround(lazy.initialLocation(), after: 0);
    });
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            title: 'Handoff proof',
            bookId: lazy.index.bookId,
            chunks: window!.chunks,
            anchorMap: window.anchorMap,
            chapters: window.chapters,
            searchIndex: window.searchIndex,
            lazySession: lazy,
            initialStableLocationsByChunkIndex: window.locationsByChunkIndex,
            initialHasContentAfter: window.hasContentAfter,
            initialSettings: const ReadingSettings(),
            adjacentWorkTestAccess: access,
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 1000 && (access.cardCount == 0 || access.building);
      i++
    ) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump(const Duration(milliseconds: 20));
    }
    // ignore: avoid_print
    print(
      'READY cards=${access.cardCount} building=${access.building} failure=${access.failure} presented=${access.presentedFailure}',
    );
    expect(
      access.cardCount,
      greaterThan(0),
      reason: 'real initial canonical publication required',
    );
    final digest = access.publicationDigest;
    final task = access.forward();
    expect(
      access.forward(),
      same(task),
      reason: 'Repeated boundary joins actual screen future.',
    );
    await tester.runAsync(() => Future<void>(() {}));
    parseHeld.complete();
    bool? result;
    task.then((value) => result = value);
    for (var i = 0; i < 1000 && result == null; i++) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(result, isNotNull, reason: 'adjacent task completed');
    final error = tester.takeException();
    // ignore: avoid_print
    print(
      'SCREEN result=$result error=$error failure=${access.failure} presented=${access.presentedFailure} starts=$starts cards=${access.cardCount} sources=${access.sourceCount}',
    );
    final unchanged = access.publicationDigest == digest;
    await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
    if (!warmup.isCompleted) warmup.complete();
    if (!hydration.isCompleted) hydration.complete();
    await tester.runAsync(lazy.close);
    await tester.pump(const Duration(seconds: 2));
    // Drain the real accepted-publication save while its widget fake zone can
    // still run. Closing the singleton later in tearDownAll cannot pump it.
    var checkpointClosed = false;
    ReaderCheckpointStore().close().then((_) => checkpointClosed = true);
    for (var i = 0; i < 1000 && !checkpointClosed; i++) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump();
    }
    expect(
      checkpointClosed,
      isTrue,
      reason: 'checkpoint writer drained and closed',
    );
    expect(
      error.toString(),
      contains('terminal continuation cannot be resumed'),
    );
    expect(unchanged, isTrue);
    expect(
      result,
      isFalse,
      reason:
          'Caught terminal pagination rejection must not settle adjacent demand as success.',
    );
  });
}
