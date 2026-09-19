import 'dart:io';
import 'dart:ffi';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
// sqlite3 is resolved by the existing sqflite_common_ffi test dependency.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nalori/services/book_cache_service.dart';
import 'package:nalori/services/derived_book_index_service.dart';
import 'package:nalori/services/display_section_memory_cache.dart';
import 'package:nalori/services/lazy_epub_index_service.dart';
import 'package:nalori/services/reader_checkpoint_store.dart';
import 'package:nalori/services/segmented_display_cache_service.dart';

/// A unique book/session identity for a reader-contract test. It is test data,
/// not a production identifier format or a production session substitute.
final class ReaderContractSandboxIdentity {
  const ReaderContractSandboxIdentity({
    required this.bookId,
    required this.sessionId,
    required this.publicationFingerprint,
  });

  final String bookId;
  final String sessionId;
  final String publicationFingerprint;
}

/// Owns only paths created beneath one explicitly allocated system-temp root.
///
/// Production connections are real where their existing constructors accept a
/// root. This class never instantiates a default-path cache/store.
final class ReaderContractSandbox {
  ReaderContractSandbox._({
    required this.root,
    required this.identity,
    required this.fixtureOutputDirectory,
    required this.wholeCacheDirectory,
    required this.segmentedDisplayCacheDirectory,
    required this.lazyIndexDirectory,
    required this.derivedIndexDirectory,
    required this.checkpointDatabaseFile,
    required this.wholeCache,
    required this.segmentedDisplayCache,
    required this.memoryDisplayCache,
    required this.lazyIndexStore,
    required this.derivedIndexStore,
    required this.preferences,
  });

  static int _nextIdentity = 0;
  static bool _sqliteInitialized = false;

  final Directory root;
  final ReaderContractSandboxIdentity identity;
  final Directory fixtureOutputDirectory;
  final Directory wholeCacheDirectory;
  final Directory segmentedDisplayCacheDirectory;
  final Directory lazyIndexDirectory;
  final Directory derivedIndexDirectory;
  final File checkpointDatabaseFile;
  final BookCacheService wholeCache;
  final SegmentedDisplayCacheService segmentedDisplayCache;
  final DisplaySectionMemoryCache memoryDisplayCache;
  final LazyEpubIndexStore lazyIndexStore;
  final DerivedBookIndexStore derivedIndexStore;
  final SharedPreferences preferences;
  final List<ReaderCheckpointStore> _checkpointStores =
      <ReaderCheckpointStore>[];
  bool _closed = false;

  static Future<ReaderContractSandbox> create({
    Map<String, Object> initialPreferences = const <String, Object>{},
  }) async {
    _initializeSqlite();
    final serial = ++_nextIdentity;
    final root = await Directory.systemTemp.createTemp(
      'nalori_reader_contract_${serial}_',
    );
    final identity = ReaderContractSandboxIdentity(
      bookId: 'reader-contract-book-$serial.epub',
      sessionId: 'reader-contract-session-$serial',
      publicationFingerprint: 'reader-contract-publication-$serial',
    );
    final fixtureOutputDirectory = Directory(p.join(root.path, 'fixture'));
    final wholeCacheDirectory = Directory(p.join(root.path, 'whole-cache'));
    final segmentedDisplayCacheDirectory = Directory(
      p.join(root.path, 'segmented-display-cache'),
    );
    final lazyIndexDirectory = Directory(p.join(root.path, 'lazy-index'));
    final derivedIndexDirectory = Directory(p.join(root.path, 'derived-index'));
    final checkpointDatabaseFile = File(
      p.join(root.path, 'checkpoint', 'reader_checkpoints.sqlite3'),
    );
    for (final directory in <Directory>[
      fixtureOutputDirectory,
      wholeCacheDirectory,
      segmentedDisplayCacheDirectory,
      lazyIndexDirectory,
      derivedIndexDirectory,
      checkpointDatabaseFile.parent,
    ]) {
      await directory.create(recursive: true);
    }

    // This replaces the platform adapter before any getInstance call, so test
    // code never reads or writes the device's default preferences path.
    SharedPreferences.setMockInitialValues(initialPreferences);
    final sandbox = ReaderContractSandbox._(
      root: root,
      identity: identity,
      fixtureOutputDirectory: fixtureOutputDirectory,
      wholeCacheDirectory: wholeCacheDirectory,
      segmentedDisplayCacheDirectory: segmentedDisplayCacheDirectory,
      lazyIndexDirectory: lazyIndexDirectory,
      derivedIndexDirectory: derivedIndexDirectory,
      checkpointDatabaseFile: checkpointDatabaseFile,
      wholeCache: BookCacheService.testing(cacheDirectory: wholeCacheDirectory),
      segmentedDisplayCache: SegmentedDisplayCacheService(
        rootDirectory: segmentedDisplayCacheDirectory,
      ),
      memoryDisplayCache: DisplaySectionMemoryCache(),
      lazyIndexStore: LazyEpubIndexStore(directory: lazyIndexDirectory),
      derivedIndexStore: DerivedBookIndexStore(
        rootDirectory: derivedIndexDirectory,
      ),
      preferences: await SharedPreferences.getInstance(),
    );
    sandbox.createCheckpointStore();
    return sandbox;
  }

  static void _initializeSqlite() {
    if (_sqliteInitialized) return;
    // The installed Linux runtime exposes the versioned system library but not
    // its unversioned development symlink. This remains real SQLite through
    // sqflite_common_ffi; it merely makes the existing test dependency load
    // deterministically on this host. Other platforms retain its default.
    if (Platform.isLinux) {
      open.overrideFor(OperatingSystem.linux, _openLinuxSqlite);
    }
    sqfliteFfiInit();
    _sqliteInitialized = true;
  }

  /// Real `ReaderCheckpointStore` backed by this sandbox's SQLite file.
  ReaderCheckpointStore createCheckpointStore() {
    if (_closed) throw StateError('Reader-contract sandbox is closed.');
    final store = ReaderCheckpointStore.forTesting(
      // The no-isolate factory keeps the tested store real while ensuring the
      // host's explicit SQLite loader applies in the same isolate.
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: checkpointDatabaseFile.path,
    );
    _checkpointStores.add(store);
    return store;
  }

  ReaderCheckpointStore get checkpointStore => _checkpointStores.first;

  String get diagnostics => [
    'root=${root.path}',
    'book=${identity.bookId}',
    'session=${identity.sessionId}',
    'fixture=${fixtureOutputDirectory.path}',
    'wholeCache=${wholeCacheDirectory.path}',
    'segmentedDisplayCache=${segmentedDisplayCacheDirectory.path}',
    'checkpoint=${checkpointDatabaseFile.path}',
    'lazyIndex=${lazyIndexDirectory.path}',
    'derivedIndex=${derivedIndexDirectory.path}',
  ].join('\n');

  /// Awaited cleanup. It closes SQLite stores before deleting the unique root,
  /// clears only per-sandbox service roots, and always leaves preferences as a
  /// fresh in-memory test adapter. Preferences mocks do not prove OS durability.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      for (final store in _checkpointStores) {
        await store.close();
      }
      memoryDisplayCache.clear();
      await segmentedDisplayCache.clearAll();
      await lazyIndexStore.clearAll();
      await derivedIndexStore.clearAll();
      // Do not call BookCacheService.clearAll(): its current implementation
      // also clears a default-path lazy index store. The unique root is deleted
      // below after all awaited sandbox-owned operations complete.
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      await _deleteRoot();
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }

  Future<void> _deleteRoot() async {
    final temporaryRoot = Directory.systemTemp.absolute.path;
    final sandboxRoot = root.absolute.path;
    if (!p.isWithin(temporaryRoot, sandboxRoot)) {
      throw StateError(
        'Refusing to delete non-temp reader-contract root: $sandboxRoot',
      );
    }
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (error) {
      final remaining = await _remainingPaths();
      throw StateError(
        'Reader-contract sandbox cleanup failed for $sandboxRoot: $error. '
        'Remaining paths: $remaining',
      );
    }
    if (await root.exists()) {
      throw StateError(
        'Reader-contract sandbox cleanup left root $sandboxRoot. '
        'Remaining paths: ${await _remainingPaths()}',
      );
    }
  }

  Future<List<String>> _remainingPaths() async {
    if (!await root.exists()) return const <String>[];
    final paths = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      paths.add(entity.path);
    }
    paths.sort();
    return paths;
  }
}

DynamicLibrary _openLinuxSqlite() => DynamicLibrary.open('libsqlite3.so.0');
