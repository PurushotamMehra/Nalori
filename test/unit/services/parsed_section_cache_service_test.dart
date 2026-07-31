import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/parsed_section_retention_policy.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late ParsedSectionCacheService cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'nalori_parsed_section_cache_',
    );
    cache = ParsedSectionCacheService(rootDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes and loads independent parsed sections', () async {
    final first = _section(0, 'text/one.xhtml', 'First section text.');
    final second = _section(1, 'text/two.xhtml', 'Second section text.');

    await cache.writeSection(first);
    await cache.writeSection(second);

    final loadedFirst = await cache.loadSection(first.identity);
    final loadedSecond = await cache.loadSection(second.identity);
    final manifest = await cache.loadManifest(first.identity.bookId);

    expect(loadedFirst, isNotNull);
    expect(loadedSecond, isNotNull);
    expect(loadedFirst!.chunks.single.text, 'First section text.');
    expect(loadedSecond!.chunks.single.text, 'Second section text.');
    expect(manifest!.records, hasLength(2));
    expect(manifest.records.map((record) => record.spineIndex), [0, 1]);
  });

  test('source checksum change misses only the changed section', () async {
    final original = _section(0, 'text/one.xhtml', 'Original text.');
    final changedIdentity = LazySectionIdentity(
      bookId: original.identity.bookId,
      publicationFingerprint: original.identity.publicationFingerprint,
      spineIndex: original.identity.spineIndex,
      href: original.identity.href,
      normalizedHref: original.identity.normalizedHref,
      fullPath: original.identity.fullPath,
      sourceChecksum: 'changed',
      parserVersion: original.identity.parserVersion,
      dependencySignature: original.identity.dependencySignature,
      dependencySchemaVersion: original.identity.dependencySchemaVersion,
    );

    await cache.writeSection(original);

    expect(await cache.loadSection(original.identity), isNotNull);
    expect(await cache.loadSection(changedIdentity), isNull);
  });

  test('repeated manifest loads preserve cached manifest state', () async {
    final section = _section(0, 'text/one.xhtml', 'Cached text.');
    await cache.writeSection(section);

    final first = await cache.loadManifest(section.identity.bookId);
    final second = await cache.loadManifest(section.identity.bookId);

    expect(first?.records, hasLength(1));
    expect(second?.records, hasLength(1));
  });

  test('external manifest changes invalidate cached parsed manifest', () async {
    final section = _section(0, 'text/one.xhtml', 'Cached text.');
    await cache.writeSection(section);
    expect(await cache.loadManifest(section.identity.bookId), isNotNull);

    final manifestFile = File(
      p.join(tempDir.path, section.identity.bookId, 'manifest.json'),
    );
    final json =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    json['version'] = -1;
    await manifestFile.writeAsString(jsonEncode(json), flush: true);

    expect(await cache.loadManifest(section.identity.bookId), isNull);
  });

  test('missing payload is removed from the lightweight manifest', () async {
    final section = _section(0, 'text/one.xhtml', 'Cached text.');
    await cache.writeSection(section);

    final manifest = await cache.loadManifest(section.identity.bookId);
    final record = manifest!.records.single;
    await File(
      p.join(tempDir.path, section.identity.bookId, record.fileName),
    ).delete();

    expect(await cache.loadSection(section.identity), isNull);
    final repaired = await cache.loadManifest(section.identity.bookId);
    expect(repaired!.records, isEmpty);
  });

  test('hydration manifest resumes from completed section records', () async {
    final first = _section(0, 'text/one.xhtml', 'First section text.');
    await cache.writeSection(first);

    final hydration = await cache.ensureHydrationManifest(
      bookId: first.identity.bookId,
      publicationFingerprint: first.identity.publicationFingerprint,
      sourceChecksum: 'book-checksum',
      parserVersion: lazyParsedSectionParserVersion,
      dependencySignature: first.identity.dependencySignature,
      readableSpineIndexes: [0, 1, 2],
      skippedSpineIndexes: [3],
    );

    expect(hydration.completedSpineIndexes, [0]);
    expect(hydration.pendingSpineIndexes, [1, 2]);
    expect(hydration.skippedSpineIndexes, [3]);
    expect(hydration.status, 'inProgress');
  });

  test(
    'hydration manifest is completed when pending sections are written',
    () async {
      final first = _section(0, 'text/one.xhtml', 'First section text.');
      final second = _section(1, 'text/two.xhtml', 'Second section text.');

      await cache.ensureHydrationManifest(
        bookId: first.identity.bookId,
        publicationFingerprint: first.identity.publicationFingerprint,
        sourceChecksum: 'book-checksum',
        parserVersion: lazyParsedSectionParserVersion,
        dependencySignature: first.identity.dependencySignature,
        readableSpineIndexes: [0, 1],
        skippedSpineIndexes: const [],
      );
      await cache.writeSection(first);
      await cache.writeSection(second);

      final manifest = await cache.loadManifest(first.identity.bookId);
      expect(manifest!.hydration?.completedSpineIndexes, [0, 1]);
      expect(manifest.hydration?.pendingSpineIndexes, isEmpty);
      expect(manifest.hydration?.status, 'complete');
    },
  );

  test(
    'two instances merge concurrent writes for different sections',
    () async {
      final other = ParsedSectionCacheService(rootDirectory: tempDir);
      final first = _section(0, 'text/one.xhtml', 'First concurrent text.');
      final second = _section(1, 'text/two.xhtml', 'Second concurrent text.');

      await Future.wait([
        cache.writeSection(first),
        other.writeSection(second),
      ]);

      final manifest = await cache.loadManifest(first.identity.bookId);
      expect(manifest!.records.map((record) => record.spineIndex), [0, 1]);
    },
  );

  test('two instances safely write the same section identity', () async {
    final other = ParsedSectionCacheService(rootDirectory: tempDir);
    final section = _section(0, 'text/one.xhtml', 'Same concurrent text.');

    await Future.wait([
      cache.writeSection(section),
      other.writeSection(section),
    ]);

    final manifest = await cache.loadManifest(section.identity.bookId);
    expect(manifest!.records, hasLength(1));
    expect(await cache.loadSection(section.identity), isNotNull);
    final temporaryFiles = await tempDir
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.contains('.tmp.'))
        .toList();
    expect(temporaryFiles, isEmpty);
  });

  test(
    'publication and dependency identity round-trip and invalidate',
    () async {
      final section = _section(0, 'text/one.xhtml', 'Identity text.');
      await cache.writeSection(section);
      final record = (await cache.loadManifest(
        section.identity.bookId,
      ))!.records.single;

      expect(record.publicationFingerprint, 'publication-v1');
      expect(record.normalizedHref, section.identity.normalizedHref);
      expect(record.dependencySignature, 'dependencies-v1');
      expect(record.cacheSchemaVersion, lazyParsedSectionCacheFormatVersion);
      expect(record.fileSizeBytes, greaterThan(0));
      expect(record.lastAccessedAtMs, greaterThan(0));
      expect(
        await cache.loadSection(
          _copyIdentity(
            section.identity,
            publicationFingerprint: 'replacement',
          ),
        ),
        isNull,
      );
      expect(
        await cache.loadSection(
          _copyIdentity(section.identity, dependencySignature: 'changed-deps'),
        ),
        isNull,
      );
    },
  );

  test('unprovable version-one records miss and are removed safely', () async {
    final bookDir = Directory(p.join(tempDir.path, 'legacy.epub'));
    await bookDir.create(recursive: true);
    await File(p.join(bookDir.path, 'payload.json.gz')).writeAsBytes([1, 2, 3]);
    await File(p.join(bookDir.path, 'manifest.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'bookId': 'legacy.epub',
        'createdAtMs': 1,
        'updatedAtMs': 1,
        'records': <Object>[],
      }),
      flush: true,
    );

    expect(await cache.loadManifest('legacy.epub'), isNull);
    expect(await bookDir.exists(), isFalse);
  });

  test('delete generation prevents stale write resurrection', () async {
    final section = _section(0, 'text/one.xhtml', 'Stale write text.');
    final generation = cache.generationForBook(section.identity.bookId);
    await cache.deleteForBook(section.identity.bookId);

    await expectLater(
      cache.writeSection(section, expectedGeneration: generation),
      throwsA(isA<ParsedSectionCacheWriteInvalidated>()),
    );
    expect(await cache.loadManifest(section.identity.bookId), isNull);
  });

  test('byte budget evicts cold least-recently-used records first', () async {
    var now = DateTime(2026, 1, 1);
    final clock = () => now;
    final generous = ParsedSectionCacheService(
      rootDirectory: tempDir,
      policy: const ParsedSectionCachePolicy(
        configuredBudgetBytes: 1024 * 1024,
        minimumBudgetBytes: 0,
      ),
      clock: clock,
      accessUpdateInterval: Duration.zero,
      retentionRegistry: ParsedSectionRetentionRegistry(),
    );
    final first = _section(0, 'text/one.xhtml', 'First LRU text.');
    final second = _section(1, 'text/two.xhtml', 'Second LRU text.');
    final third = _section(2, 'text/three.xhtml', 'Third LRU text.');
    await generous.writeSection(first);
    now = now.add(const Duration(minutes: 1));
    await generous.writeSection(second);
    now = now.add(const Duration(minutes: 1));
    await generous.writeSection(third);
    now = now.add(const Duration(minutes: 1));
    await generous.loadSection(first.identity);
    final usage = (await generous.enforceBudget()).usageBytes;
    final smallest = (await generous.loadManifest(first.identity.bookId))!
        .records
        .map((record) => record.fileSizeBytes)
        .reduce((a, b) => a < b ? a : b);
    final constrained = ParsedSectionCacheService(
      rootDirectory: tempDir,
      policy: ParsedSectionCachePolicy(
        configuredBudgetBytes: usage - smallest,
        minimumBudgetBytes: 0,
      ),
      clock: clock,
      retentionRegistry: ParsedSectionRetentionRegistry(),
    );

    final result = await constrained.enforceBudget();

    expect(result.usageBytes, lessThanOrEqualTo(result.budgetBytes));
    expect(await constrained.loadSection(second.identity), isNull);
    expect(await constrained.loadSection(first.identity), isNotNull);
  });

  test('active target protection survives cold byte pressure', () async {
    final registry = ParsedSectionRetentionRegistry();
    final generous = ParsedSectionCacheService(
      rootDirectory: tempDir,
      policy: const ParsedSectionCachePolicy(
        configuredBudgetBytes: 1024 * 1024,
        minimumBudgetBytes: 0,
      ),
      retentionRegistry: registry,
    );
    final active = _section(0, 'text/active.xhtml', 'Active protected text.');
    final cold = _section(1, 'text/cold.xhtml', 'Cold evictable text.');
    await generous.writeSection(active);
    await generous.writeSection(cold);
    final manifest = await generous.loadManifest(active.identity.bookId);
    final budget = manifest!.records
        .firstWhere((record) => record.spineIndex == 0)
        .fileSizeBytes;
    registry.setActive(
      owner: Object(),
      bookId: active.identity.bookId,
      publicationFingerprint: active.identity.publicationFingerprint,
      nearbySections: [active.identity],
    );
    final constrained = ParsedSectionCacheService(
      rootDirectory: tempDir,
      policy: ParsedSectionCachePolicy(
        configuredBudgetBytes: budget,
        minimumBudgetBytes: 0,
      ),
      retentionRegistry: registry,
    );

    await constrained.enforceBudget();

    expect(await constrained.loadSection(active.identity), isNotNull);
    expect(await constrained.loadSection(cold.identity), isNull);
  });

  test(
    'display derivatives are offered eviction before parsed source',
    () async {
      final section = _section(
        0,
        'text/source.xhtml',
        'Reusable parsed source.',
      );
      final generous = ParsedSectionCacheService(
        rootDirectory: tempDir,
        policy: const ParsedSectionCachePolicy(
          configuredBudgetBytes: 1024 * 1024,
          minimumBudgetBytes: 0,
        ),
        retentionRegistry: ParsedSectionRetentionRegistry(),
      );
      await generous.writeSection(section);
      final record = (await generous.loadManifest(
        section.identity.bookId,
      ))!.records.single;
      final payload = File(
        p.join(tempDir.path, section.identity.bookId, record.fileName),
      );
      var displayEvictionRanWhileSourceExisted = false;
      final constrained = ParsedSectionCacheService(
        rootDirectory: tempDir,
        policy: const ParsedSectionCachePolicy(
          configuredBudgetBytes: 0,
          minimumBudgetBytes: 0,
        ),
        retentionRegistry: ParsedSectionRetentionRegistry(),
        evictDisplayDerivativesBeforeSource: () async {
          displayEvictionRanWhileSourceExisted = await payload.exists();
        },
      );

      await constrained.enforceBudget();

      expect(displayEvictionRanWhileSourceExisted, isTrue);
      expect(await payload.exists(), isFalse);
    },
  );

  test('low storage reduces budget and suspends P4 speculative work', () {
    final service = ParsedSectionCacheService(
      rootDirectory: tempDir,
      policy: const ParsedSectionCachePolicy(
        configuredBudgetBytes: 1000,
        minimumBudgetBytes: 0,
      ),
      storagePressureProvider: () => ParsedCacheStoragePressure.low,
    );

    expect(service.allowsPriority(2), isTrue);
    expect(service.allowsPriority(4), isFalse);
    expect(
      const ParsedSectionCachePolicy(
        configuredBudgetBytes: 1000,
        minimumBudgetBytes: 0,
      ).effectiveBudget(ParsedCacheStoragePressure.low),
      500,
    );
    expect(ParsedSectionCachePolicy.defaultBudgetBytes, 192 * 1024 * 1024);
  });
}

LazySectionIdentity _copyIdentity(
  LazySectionIdentity identity, {
  String? publicationFingerprint,
  String? dependencySignature,
}) {
  return LazySectionIdentity(
    bookId: identity.bookId,
    publicationFingerprint:
        publicationFingerprint ?? identity.publicationFingerprint,
    spineIndex: identity.spineIndex,
    href: identity.href,
    normalizedHref: identity.normalizedHref,
    fullPath: identity.fullPath,
    sourceChecksum: identity.sourceChecksum,
    parserVersion: identity.parserVersion,
    dependencySignature: dependencySignature ?? identity.dependencySignature,
    dependencySchemaVersion: identity.dependencySchemaVersion,
  );
}

ParsedSection _section(int spineIndex, String href, String text) {
  final identity = LazySectionIdentity(
    bookId: 'book.epub',
    publicationFingerprint: 'publication-v1',
    spineIndex: spineIndex,
    href: href,
    normalizedHref: href,
    fullPath: 'OEBPS/$href',
    sourceChecksum: fnv1aHex(Uint8List.fromList(text.codeUnits)),
    parserVersion: lazyParsedSectionParserVersion,
    dependencySignature: 'dependencies-v1',
    dependencySchemaVersion: lazyParsedSectionDependencySchemaVersion,
  );
  return ParsedSection(
    identity: identity,
    chunks: [
      BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: text,
        sourceFile: href,
      ),
    ],
    anchorMap: {'ch$spineIndex': 0},
    chapters: [],
    wordCount: text.split(RegExp(r'\s+')).length,
    textCharCount: text.length,
    resourceHrefs: const [],
    parserVersion: lazyParsedSectionParserVersion,
  );
}
