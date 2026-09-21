import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/reader_checkpoint.dart';
import '../models/stable_book_location.dart';

typedef ReaderCheckpointTrace =
    void Function(String event, Map<String, Object?> fields);

enum ReaderCheckpointCommitStatus {
  applied,
  staleSessionRejected,
  staleRevisionRejected,
  invalidRejected,
}

@immutable
class ReaderCheckpointCommitResult {
  const ReaderCheckpointCommitResult(this.status, {this.checkpoint});

  final ReaderCheckpointCommitStatus status;
  final ReaderCheckpoint? checkpoint;

  bool get applied => status == ReaderCheckpointCommitStatus.applied;
}

/// Atomic append journal for the canonical last-read checkpoint.
///
/// The metadata JSON registry and SharedPreferences are compatibility mirrors,
/// never inputs to this store after a canonical checkpoint exists.
class ReaderCheckpointStore {
  factory ReaderCheckpointStore() => _instance;

  ReaderCheckpointStore.forTesting({
    required DatabaseFactory databaseFactory,
    required String databasePath,
    this.trace,
  }) : _databaseFactoryOverride = databaseFactory,
       _databasePathOverride = databasePath;

  ReaderCheckpointStore._()
    : _databaseFactoryOverride = null,
      _databasePathOverride = null,
      trace = null;

  static final ReaderCheckpointStore _instance = ReaderCheckpointStore._();
  static const int schemaVersion = 1;
  static const String _databaseFileName = 'reader_checkpoints.sqlite3';
  static const int _recordsRetainedPerBook = 8;

  final DatabaseFactory? _databaseFactoryOverride;
  final String? _databasePathOverride;
  ReaderCheckpointTrace? trace;
  Database? _databaseInstance;
  Future<Database>? _openOperation;
  Future<void> _writeTail = Future<void>.value();

  Future<Database> _database() {
    final existing = _databaseInstance;
    if (existing != null) return Future.value(existing);
    final opening = _openOperation;
    if (opening != null) return opening;
    final operation = _open();
    _openOperation = operation;
    return operation;
  }

  Future<Database> _open() async {
    final factory = _databaseFactoryOverride ?? databaseFactory;
    final path =
        _databasePathOverride ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          _databaseFileName,
        );
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          await database.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (database, _) => _createSchema(database),
      ),
    );
    _databaseInstance = db;
    return db;
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE reader_checkpoint_sessions (
        book_id TEXT PRIMARY KEY,
        current_epoch INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE reader_checkpoint_journal (
        record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id TEXT NOT NULL,
        session_epoch INTEGER NOT NULL,
        revision INTEGER NOT NULL,
        committed_at_ms INTEGER NOT NULL,
        checkpoint_json TEXT NOT NULL,
        integrity_checksum TEXT NOT NULL,
        UNIQUE(book_id, session_epoch, revision)
      )
    ''');
    await db.execute(
      'CREATE INDEX reader_checkpoint_latest '
      'ON reader_checkpoint_journal('
      'book_id, session_epoch DESC, revision DESC, record_id DESC)',
    );
  }

  Future<int> beginSession(String bookId) {
    return _serialize(() async {
      final db = await _database();
      return db.transaction((txn) async {
        final rows = await txn.query(
          'reader_checkpoint_sessions',
          columns: const ['current_epoch'],
          where: 'book_id = ?',
          whereArgs: [bookId],
          limit: 1,
        );
        final epoch = rows.isEmpty
            ? 1
            : ((rows.single['current_epoch'] as num).toInt() + 1);
        await txn.insert('reader_checkpoint_sessions', {
          'book_id': bookId,
          'current_epoch': epoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        _trace('checkpoint_session_begin', {
          'book': bookId,
          'sessionEpoch': epoch,
        });
        return epoch;
      });
    });
  }

  Future<ReaderCheckpoint?> loadNewestValid(String bookId) async {
    final db = await _database();
    final rows = await db.query(
      'reader_checkpoint_journal',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'session_epoch DESC, revision DESC, record_id DESC',
      limit: _recordsRetainedPerBook,
    );
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['checkpoint_json']! as String);
        if (decoded is! Map) throw const FormatException('Invalid payload');
        final checkpoint = ReaderCheckpoint.fromPayload(
          Map<String, Object?>.from(decoded),
          integrityChecksum: row['integrity_checksum']! as String,
        );
        if (checkpoint.bookId != bookId) {
          throw const FormatException('Mismatched checkpoint book');
        }
        if (checkpoint.sessionEpoch != (row['session_epoch'] as num).toInt() ||
            checkpoint.revision != (row['revision'] as num).toInt()) {
          throw const FormatException('Mismatched checkpoint ordering');
        }
        _trace('checkpoint_load_valid', {
          'book': bookId,
          'sessionEpoch': checkpoint.sessionEpoch,
          'revision': checkpoint.revision,
          'cardSignature': checkpoint.card?.signature,
          'state': checkpoint.state.name,
        });
        return checkpoint;
      } catch (error) {
        _trace('checkpoint_load_corrupt_skipped', {
          'book': bookId,
          'sessionEpoch': row['session_epoch'],
          'revision': row['revision'],
          'reason': error.runtimeType.toString(),
        });
      }
    }
    _trace('checkpoint_load_missing', {'book': bookId});
    return null;
  }

  Future<ReaderCheckpointCommitResult> commit(
    ReaderCheckpoint checkpoint, {
    bool Function()? canCommit,
    String? expectedPreviousChecksum,
  }) {
    return _serialize(() async {
      if (canCommit?.call() == false) throw const _CheckpointCommitCancelled();
      _trace('checkpoint_store_start', {
        'book': checkpoint.bookId,
        'publicationFingerprint': checkpoint.publicationFingerprint,
        'sessionEpoch': checkpoint.sessionEpoch,
        'revision': checkpoint.revision,
        'cardSignature': checkpoint.card?.signature,
        'state': checkpoint.state.name,
      });
      if (!checkpoint.isValid ||
          readerSha256(checkpoint.payloadJson()) !=
              checkpoint.integrityChecksum) {
        _trace('checkpoint_store_rejected', {
          'book': checkpoint.bookId,
          'reason': 'invalid_checkpoint',
        });
        return ReaderCheckpointCommitResult(
          ReaderCheckpointCommitStatus.invalidRejected,
          checkpoint: checkpoint,
        );
      }

      final db = await _database();
      return db.transaction((txn) async {
        final sessionRows = await txn.query(
          'reader_checkpoint_sessions',
          columns: const ['current_epoch'],
          where: 'book_id = ?',
          whereArgs: [checkpoint.bookId],
          limit: 1,
        );
        final currentEpoch = sessionRows.isEmpty
            ? null
            : (sessionRows.single['current_epoch'] as num).toInt();
        if (currentEpoch != checkpoint.sessionEpoch) {
          _trace('checkpoint_store_rejected', {
            'book': checkpoint.bookId,
            'sessionEpoch': checkpoint.sessionEpoch,
            'currentSessionEpoch': currentEpoch,
            'revision': checkpoint.revision,
            'reason': 'stale_session',
          });
          return ReaderCheckpointCommitResult(
            ReaderCheckpointCommitStatus.staleSessionRejected,
            checkpoint: checkpoint,
          );
        }

        final latestRows = await txn.query(
          'reader_checkpoint_journal',
          columns: const [
            'record_id',
            'session_epoch',
            'revision',
            'checkpoint_json',
            'integrity_checksum',
          ],
          where: 'book_id = ?',
          whereArgs: [checkpoint.bookId],
          orderBy: 'session_epoch DESC, revision DESC, record_id DESC',
          limit: _recordsRetainedPerBook,
        );
        ReaderCheckpoint? latestValid;
        for (final row in latestRows) {
          try {
            final decoded = jsonDecode(row['checkpoint_json']! as String);
            if (decoded is! Map) throw const FormatException('Invalid payload');
            final candidate = ReaderCheckpoint.fromPayload(
              Map<String, Object?>.from(decoded),
              integrityChecksum: row['integrity_checksum']! as String,
            );
            if (candidate.bookId != checkpoint.bookId) {
              throw const FormatException('Mismatched checkpoint book');
            }
            if (candidate.sessionEpoch !=
                    (row['session_epoch'] as num).toInt() ||
                candidate.revision != (row['revision'] as num).toInt()) {
              throw const FormatException('Mismatched checkpoint ordering');
            }
            latestValid = candidate;
            break;
          } catch (error) {
            // Invalid journal rows never participate in ordering and are
            // removed transactionally before the next valid append.
            await txn.delete(
              'reader_checkpoint_journal',
              where: 'record_id = ?',
              whereArgs: [row['record_id']],
            );
            _trace('checkpoint_corrupt_row_removed', {
              'book': checkpoint.bookId,
              'sessionEpoch': row['session_epoch'],
              'revision': row['revision'],
              'reason': error.runtimeType.toString(),
            });
          }
        }
        if (latestValid != null) {
          if (latestValid.formatVersion == 2 && checkpoint.formatVersion != 2) {
            return ReaderCheckpointCommitResult(
              ReaderCheckpointCommitStatus.invalidRejected,
              checkpoint: checkpoint,
            );
          }
          final latestEpoch = latestValid.sessionEpoch;
          final latestRevision = latestValid.revision;
          if (checkpoint.sessionEpoch < latestEpoch ||
              (checkpoint.sessionEpoch == latestEpoch &&
                  checkpoint.revision <= latestRevision)) {
            _trace('checkpoint_store_rejected', {
              'book': checkpoint.bookId,
              'sessionEpoch': checkpoint.sessionEpoch,
              'revision': checkpoint.revision,
              'latestSessionEpoch': latestEpoch,
              'latestRevision': latestRevision,
              'reason': 'stale_revision',
            });
            return ReaderCheckpointCommitResult(
              ReaderCheckpointCommitStatus.staleRevisionRejected,
              checkpoint: checkpoint,
            );
          }
        }

        if (canCommit?.call() == false ||
            (expectedPreviousChecksum != null &&
                latestValid?.integrityChecksum != expectedPreviousChecksum)) {
          throw const _CheckpointCommitCancelled();
        }
        await txn.insert('reader_checkpoint_journal', {
          'book_id': checkpoint.bookId,
          'session_epoch': checkpoint.sessionEpoch,
          'revision': checkpoint.revision,
          'committed_at_ms': checkpoint.committedAtMillis,
          'checkpoint_json': canonicalJsonEncode(checkpoint.payloadJson()),
          'integrity_checksum': checkpoint.integrityChecksum,
        });
        await txn.rawDelete(
          'DELETE FROM reader_checkpoint_journal '
          'WHERE book_id = ? AND record_id NOT IN ('
          'SELECT record_id FROM reader_checkpoint_journal '
          'WHERE book_id = ? '
          'ORDER BY session_epoch DESC, revision DESC, record_id DESC LIMIT ?)',
          [checkpoint.bookId, checkpoint.bookId, _recordsRetainedPerBook],
        );
        // A lost publication owner rolls back the entire journal transaction,
        // including pruning. Legacy callers have no additional guard.
        if (canCommit?.call() == false) {
          throw const _CheckpointCommitCancelled();
        }
        _trace('checkpoint_store_success', {
          'book': checkpoint.bookId,
          'publicationFingerprint': checkpoint.publicationFingerprint,
          'sessionEpoch': checkpoint.sessionEpoch,
          'revision': checkpoint.revision,
          'cardSignature': checkpoint.card?.signature,
        });
        return ReaderCheckpointCommitResult(
          ReaderCheckpointCommitStatus.applied,
          checkpoint: checkpoint,
        );
      });
    }).catchError((Object error, StackTrace stackTrace) {
      if (error is _CheckpointCommitCancelled) {
        return ReaderCheckpointCommitResult(
          ReaderCheckpointCommitStatus.staleSessionRejected,
          checkpoint: checkpoint,
        );
      }
      _trace('checkpoint_store_failure', {
        'book': checkpoint.bookId,
        'sessionEpoch': checkpoint.sessionEpoch,
        'revision': checkpoint.revision,
        'error': error.runtimeType.toString(),
      });
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> deleteBook(String bookId) {
    return _serialize(() async {
      final db = await _database();
      await db.transaction((txn) async {
        await txn.delete(
          'reader_checkpoint_journal',
          where: 'book_id = ?',
          whereArgs: [bookId],
        );
        await txn.delete(
          'reader_checkpoint_sessions',
          where: 'book_id = ?',
          whereArgs: [bookId],
        );
      });
    });
  }

  Future<void> flush() => _writeTail;

  Future<void> close() async {
    await flush();
    final db = _databaseInstance;
    _databaseInstance = null;
    _openOperation = null;
    await db?.close();
  }

  @visibleForTesting
  Future<void> insertCorruptNewest({
    required String bookId,
    required int sessionEpoch,
    required int revision,
  }) async {
    final db = await _database();
    await db.insert('reader_checkpoint_journal', {
      'book_id': bookId,
      'session_epoch': sessionEpoch,
      'revision': revision,
      'committed_at_ms': DateTime.now().millisecondsSinceEpoch,
      'checkpoint_json': '{"incomplete":true}',
      'integrity_checksum': 'corrupt',
    });
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final operation = _writeTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _writeTail = operation.catchError((_) {});
    return completer.future;
  }

  void _trace(String event, Map<String, Object?> fields) {
    trace?.call(event, fields);
  }
}

final class _CheckpointCommitCancelled implements Exception {
  const _CheckpointCommitCancelled();
}

enum ReaderRestoreMatchStrategy { exactSignature, semanticAnchor }

@immutable
class ReaderRestoreResolution {
  const ReaderRestoreResolution({
    required this.index,
    required this.strategy,
    this.fallbackReason,
  });

  final int index;
  final ReaderRestoreMatchStrategy strategy;
  final String? fallbackReason;
}

@immutable
class ReaderLayoutTransitionToken {
  const ReaderLayoutTransitionToken({
    required this.generation,
    required this.layoutFingerprint,
  });

  final int generation;
  final String layoutFingerprint;
}

/// Owns the restore barrier and the persist-before-commit protocol used by the
/// Flutter reader. It is intentionally UI-independent so abrupt termination,
/// delayed writes, and randomized event sequences can be tested directly.
class ReaderCheckpointCoordinator {
  ReaderCheckpointCoordinator({
    required this.store,
    required this.bookId,
    required this.publicationFingerprint,
    ReaderCheckpointTrace? trace,
  }) : _traceCallback = trace;

  final ReaderCheckpointStore store;
  final String bookId;
  final String publicationFingerprint;
  final ReaderCheckpointTrace? _traceCallback;

  ReaderCheckpoint? _current;
  int _sessionEpoch = 0;
  int _revision = 0;
  int _layoutGeneration = 0;
  bool _initialized = false;
  bool _ordinaryWritesEnabled = false;

  ReaderCheckpoint? get current => _current;
  int get sessionEpoch => _sessionEpoch;
  bool get ordinaryWritesEnabled => _ordinaryWritesEnabled;
  bool get isInitialized => _initialized;

  Future<ReaderCheckpoint?> initialize({
    ReaderCheckpoint? preloaded,
    bool ignoreStored = false,
  }) async {
    final loaded = ignoreStored
        ? preloaded
        : preloaded ?? await store.loadNewestValid(bookId);
    if (loaded != null &&
        loaded.publicationFingerprint == publicationFingerprint) {
      _current = loaded;
      _trace('restore_start', {
        'book': bookId,
        'savedSessionEpoch': loaded.sessionEpoch,
        'savedRevision': loaded.revision,
        'savedCardSignature': loaded.card?.signature,
        'savedLayoutFingerprint': loaded.layoutFingerprint,
        'state': loaded.state.name,
      });
    } else if (loaded != null) {
      _trace('restore_checkpoint_ignored', {
        'book': bookId,
        'reason': 'publication_fingerprint_mismatch',
      });
    }
    _sessionEpoch = await store.beginSession(bookId);
    _initialized = true;
    _ordinaryWritesEnabled = false;
    return _current;
  }

  ReaderRestoreResolution? resolveRestore({
    required List<ReaderCardIdentity> cards,
    required String currentLayoutFingerprint,
  }) {
    final checkpoint = _current;
    if (checkpoint == null ||
        checkpoint.formatVersion != ReaderCheckpoint.currentFormatVersion) {
      return null;
    }
    final exactExpected =
        checkpoint.state == ReaderCheckpointState.exactCommitted &&
        checkpoint.layoutFingerprint == currentLayoutFingerprint &&
        checkpoint.paginationVersion == readerPaginationAlgorithmVersion;
    if (exactExpected) {
      final signature = checkpoint.card?.signature;
      final exact = signature == null
          ? -1
          : cards.indexWhere((card) => card.signature == signature);
      if (exact >= 0) {
        _trace('restore_resolved', {
          'book': bookId,
          'strategy': 'exact_signature',
          'displayIndex': exact,
          'cardSignature': signature,
        });
        return ReaderRestoreResolution(
          index: exact,
          strategy: ReaderRestoreMatchStrategy.exactSignature,
        );
      }
      // The layout and pagination identity promise an exact physical card.
      // A partial/cache publication that does not contain that signature is
      // not evidence of reflow and must not downgrade to a semantic neighbor.
      _trace('restore_resolution_failed', {
        'book': bookId,
        'reason': 'same_layout_exact_signature_missing',
        'expectedCardSignature': signature,
      });
      return null;
    }

    final semantic = cards.indexWhere(
      (card) => card.containsAnchor(checkpoint.semanticAnchor),
    );
    if (semantic < 0) {
      _trace('restore_resolution_failed', {
        'book': bookId,
        'reason': 'semantic_anchor_missing',
      });
      return null;
    }
    final reason =
        checkpoint.state == ReaderCheckpointState.layoutTransitionPending
        ? 'layout_transition_pending'
        : 'layout_changed';
    _trace('restore_resolved', {
      'book': bookId,
      'strategy': 'semantic_anchor',
      'displayIndex': semantic,
      'cardSignature': cards[semantic].signature,
      'fallbackReason': reason,
    });
    return ReaderRestoreResolution(
      index: semantic,
      strategy: ReaderRestoreMatchStrategy.semanticAnchor,
      fallbackReason: reason,
    );
  }

  bool verifyPublished({
    required ReaderCardIdentity visibleCard,
    required ReaderRestoreMatchStrategy strategy,
  }) {
    final checkpoint = _current;
    if (checkpoint == null ||
        checkpoint.formatVersion != ReaderCheckpoint.currentFormatVersion) {
      return false;
    }
    final matches = strategy == ReaderRestoreMatchStrategy.exactSignature
        ? visibleCard.signature == checkpoint.card?.signature
        : visibleCard.containsAnchor(checkpoint.semanticAnchor);
    _trace('restore_verification', {
      'book': bookId,
      'strategy': strategy.name,
      'visibleCardSignature': visibleCard.signature,
      'expectedCardSignature': checkpoint.card?.signature,
      'verified': matches,
    });
    if (matches && strategy == ReaderRestoreMatchStrategy.exactSignature) {
      _ordinaryWritesEnabled = true;
    }
    return matches;
  }

  void completeEmptyRestoreBarrier() {
    _ordinaryWritesEnabled = true;
  }

  Future<ReaderCheckpointCommitResult> commitCard({
    required ReaderCardIdentity card,
    required StableBookLocation? stableLocation,
    required String navigationSource,
    bool duringRestore = false,
    ReaderLayoutTransitionToken? layoutToken,
  }) async {
    if (!_initialized) {
      throw StateError('Reader checkpoint coordinator is not initialized');
    }
    if (!_ordinaryWritesEnabled && !duringRestore) {
      _trace('checkpoint_candidate_rejected', {
        'book': bookId,
        'cardSignature': card.signature,
        'reason': 'restore_barrier_active',
      });
      return const ReaderCheckpointCommitResult(
        ReaderCheckpointCommitStatus.invalidRejected,
      );
    }
    if (layoutToken != null &&
        (layoutToken.generation != _layoutGeneration ||
            layoutToken.layoutFingerprint != card.layoutFingerprint)) {
      _trace('stale_pagination_rejected', {
        'book': bookId,
        'generation': layoutToken.generation,
        'activeGeneration': _layoutGeneration,
        'cardSignature': card.signature,
      });
      return const ReaderCheckpointCommitResult(
        ReaderCheckpointCommitStatus.staleRevisionRejected,
      );
    }
    final contextChecksum = _contextChecksum(stableLocation);
    final checkpoint = ReaderCheckpoint.create(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      card: card,
      semanticAnchor: card.firstMeaningfulAnchor(
        contextChecksum: contextChecksum,
      ),
      stableLocation: stableLocation,
      layoutFingerprint: card.layoutFingerprint,
      state: ReaderCheckpointState.exactCommitted,
      sessionEpoch: _sessionEpoch,
      revision: ++_revision,
      navigationSource: navigationSource,
    );
    _trace('checkpoint_candidate', {
      'book': bookId,
      'publicationFingerprint': publicationFingerprint,
      'sessionEpoch': checkpoint.sessionEpoch,
      'revision': checkpoint.revision,
      'navigationSource': navigationSource,
      'cardSignature': card.signature,
      'layoutFingerprint': card.layoutFingerprint,
      'anchorSection': checkpoint.semanticAnchor.sectionIdentity,
      'anchorBlock': checkpoint.semanticAnchor.logicalBlockId,
      'anchorOffset': checkpoint.semanticAnchor.blockOffsetUtf16,
    });
    final result = await store.commit(checkpoint);
    if (result.applied &&
        (layoutToken == null || layoutToken.generation == _layoutGeneration)) {
      _current = checkpoint;
      _ordinaryWritesEnabled = true;
    }
    return result;
  }

  Future<ReaderLayoutTransitionToken?> beginLayoutTransition({
    required String targetLayoutFingerprint,
    required Map<String, Object?> targetLayoutSettings,
    required String navigationSource,
  }) async {
    final current = _current;
    if (current == null) return null;
    final token = ReaderLayoutTransitionToken(
      generation: ++_layoutGeneration,
      layoutFingerprint: targetLayoutFingerprint,
    );
    _ordinaryWritesEnabled = false;
    final pending = ReaderCheckpoint.create(
      bookId: bookId,
      publicationFingerprint: publicationFingerprint,
      card: current.card,
      semanticAnchor: current.semanticAnchor,
      stableLocation: current.stableLocation,
      layoutFingerprint: targetLayoutFingerprint,
      state: ReaderCheckpointState.layoutTransitionPending,
      sessionEpoch: _sessionEpoch,
      revision: ++_revision,
      navigationSource: navigationSource,
      targetLayoutSettings: targetLayoutSettings,
    );
    _trace('layout_transition_candidate', {
      'book': bookId,
      'publicationFingerprint': publicationFingerprint,
      'sessionEpoch': pending.sessionEpoch,
      'revision': pending.revision,
      'generation': token.generation,
      'targetLayoutFingerprint': targetLayoutFingerprint,
      'anchorSection': pending.semanticAnchor.sectionIdentity,
      'anchorBlock': pending.semanticAnchor.logicalBlockId,
      'anchorOffset': pending.semanticAnchor.blockOffsetUtf16,
    });
    final result = await store.commit(pending);
    if (result.applied && token.generation == _layoutGeneration) {
      _current = pending;
    }
    return result.applied ? token : null;
  }

  Future<ReaderCheckpointCommitResult> migrateLegacy({
    required ReaderCardIdentity card,
    required StableBookLocation? stableLocation,
  }) {
    return commitCard(
      card: card,
      stableLocation: stableLocation,
      navigationSource: 'legacy_migration',
      duringRestore: true,
    );
  }

  Future<void> flush() => store.flush();

  String? _contextChecksum(StableBookLocation? location) {
    final values = [
      location?.contextBefore,
      location?.contextText,
      location?.contextAfter,
    ].whereType<String>().join('|').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (values.isEmpty) return null;
    return readerSha256(values);
  }

  void _trace(String event, Map<String, Object?> fields) {
    _traceCallback?.call(event, fields);
  }
}
