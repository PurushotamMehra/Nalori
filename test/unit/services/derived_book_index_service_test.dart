import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/derived_book_index.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/models/stable_book_location.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/services/derived_book_index_service.dart';
import 'package:nalori/services/book_character_occurrence_service.dart';
import 'package:nalori/services/book_memory_service.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:nalori/services/reader_open_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('nalori_derived_index_');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('segment and manifest serialize without losing source identity', () {
    final segment = buildDerivedIndexSegment(_section());
    final decoded = DerivedIndexSegment.fromJson(segment.toJson());

    expect(decoded.schemaVersion, derivedBookIndexSchemaVersion);
    expect(decoded.publicationFingerprint, 'fingerprint-a');
    expect(decoded.paragraphs.single.logicalParagraphId, 'p-1');
    expect(decoded.paragraphs.single.text, 'Café across cards');
    expect(decoded.paragraphs.single.sourceSegments, hasLength(2));
  });

  test('partial segment publication is validated and resumes', () async {
    final store = DerivedBookIndexStore(rootDirectory: temporary);
    final initial = await store.open(
      bookId: 'book.epub',
      publicationFingerprint: 'fingerprint-a',
      parserVersion: lazyParsedSectionParserVersion,
      totalSections: 2,
    );
    final partial = await store.publishSegment(
      expectedManifest: initial.manifest,
      segment: buildDerivedIndexSegment(_section()),
    );

    expect(partial.manifest.records, hasLength(1));
    expect(partial.isComplete, isFalse);
    final resumed = await store.open(
      bookId: 'book.epub',
      publicationFingerprint: 'fingerprint-a',
      parserVersion: lazyParsedSectionParserVersion,
      totalSections: 2,
    );
    expect(resumed.segments.keys, [0]);
    expect(resumed.coverage, 0.5);
  });

  test(
    'schema inputs invalidate independently and preserve complete index',
    () async {
      final store = DerivedBookIndexStore(rootDirectory: temporary);
      final initial = await store.open(
        bookId: 'book.epub',
        publicationFingerprint: 'fingerprint-a',
        parserVersion: lazyParsedSectionParserVersion,
        totalSections: 1,
      );
      final complete = await store.publishSegment(
        expectedManifest: initial.manifest,
        segment: buildDerivedIndexSegment(_section()),
      );
      expect(complete.isComplete, isTrue);

      final replacement = await store.open(
        bookId: 'book.epub',
        publicationFingerprint: 'fingerprint-b',
        parserVersion: lazyParsedSectionParserVersion,
        totalSections: 1,
      );
      expect(replacement.segments, isEmpty);
      expect(replacement.manifest.generation, complete.manifest.generation + 1);
      final bookDirectory = await temporary
          .list()
          .where((entry) => entry is Directory)
          .cast<Directory>()
          .single;
      expect(
        File(p.join(bookDirectory.path, 'previous_manifest.json')).existsSync(),
        isTrue,
      );
    },
  );

  test('older generation cannot publish over replacement', () async {
    final store = DerivedBookIndexStore(rootDirectory: temporary);
    final old = await store.open(
      bookId: 'book.epub',
      publicationFingerprint: 'fingerprint-a',
      parserVersion: lazyParsedSectionParserVersion,
      totalSections: 1,
    );
    await store.open(
      bookId: 'book.epub',
      publicationFingerprint: 'fingerprint-b',
      parserVersion: lazyParsedSectionParserVersion,
      totalSections: 1,
    );

    expect(
      () => store.publishSegment(
        expectedManifest: old.manifest,
        segment: buildDerivedIndexSegment(_section()),
      ),
      throwsA(isA<DerivedIndexGenerationRejected>()),
    );
  });

  test('corrupt segment becomes a resumable cache miss', () async {
    final store = DerivedBookIndexStore(rootDirectory: temporary);
    final initial = await store.open(
      bookId: 'book.epub',
      publicationFingerprint: 'fingerprint-a',
      parserVersion: lazyParsedSectionParserVersion,
      totalSections: 1,
    );
    final complete = await store.publishSegment(
      expectedManifest: initial.manifest,
      segment: buildDerivedIndexSegment(_section()),
    );
    final directory = await temporary
        .list()
        .where((entry) => entry is Directory)
        .cast<Directory>()
        .single;
    final segmentFile = File(
      p.join(directory.path, complete.manifest.records.single.fileName),
    );
    await segmentFile.writeAsString('partial', flush: true);

    final recovered = await store.loadForBook('book.epub');
    expect(recovered, isNotNull);
    expect(recovered!.segments, isEmpty);
    expect(recovered.isComplete, isFalse);
  });

  test(
    'separate derived budget evicts least-recent unprotected book',
    () async {
      final store = DerivedBookIndexStore(
        rootDirectory: temporary,
        byteBudget: 1,
      );
      await store.open(
        bookId: 'old.epub',
        publicationFingerprint: 'old',
        parserVersion: lazyParsedSectionParserVersion,
        totalSections: 0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.open(
        bookId: 'current.epub',
        publicationFingerprint: 'current',
        parserVersion: lazyParsedSectionParserVersion,
        totalSections: 0,
      );
      await store.enforceBudget(protectedBookId: 'current.epub');

      expect(await store.loadForBook('old.epub'), isNull);
      expect(await store.loadForBook('current.epub'), isNotNull);
    },
  );

  test('Unicode phrase search maps normalized match to UTF-16 source', () {
    final segment = buildDerivedIndexSegment(_section());
    final manifest = _manifest(recordCount: 1, complete: true);
    final snapshot = DerivedIndexSnapshot(
      manifest: manifest,
      segments: {0: segment},
    );

    final results = const DerivedBookSearchService().search(
      snapshot,
      'CAFÉ ACROSS',
    );

    expect(results, hasLength(1));
    expect(results.single.range.matchText, 'Café across');
    expect(results.single.range.paragraphStart, 0);
    expect(results.single.range.paragraphEnd, 11);
    expect(results.single.range.location.localChunkIndex, 0);
    expect(results.single.range.location.textOffset, 0);
  });

  test('exact phrase ranks before weaker token match and deduplicates', () {
    final exact = buildDerivedIndexSegment(_section());
    final weak = buildDerivedIndexSegment(
      _section(
        spineIndex: 1,
        fingerprint: 'fingerprint-a',
        paragraphId: 'p-2',
        first: 'Across many pages, Café appears',
        second: '',
      ),
    );
    final snapshot = DerivedIndexSnapshot(
      manifest: _manifest(recordCount: 2, complete: true, total: 2),
      segments: {0: exact, 1: weak},
    );

    final results = const DerivedBookSearchService().search(
      snapshot,
      'Café across',
    );
    expect(results, hasLength(2));
    expect(results.first.rank, 0);
    expect(results.last.rank, 1);
    expect(results.map((item) => item.range.stableKey).toSet(), hasLength(2));
  });

  test('split paragraph range produces transient emphasis on both chunks', () {
    final snapshot = DerivedIndexSnapshot(
      manifest: _manifest(recordCount: 1, complete: true),
      segments: {0: buildDerivedIndexSegment(_section())},
    );
    final result = const DerivedBookSearchService()
        .search(snapshot, 'across cards')
        .single;
    final highlights = buildTransientSearchHighlights(
      range: result.range,
      sourceChunks: _section().chunks,
    );

    expect(highlights, hasLength(2));
    expect(highlights.map((item) => item.text).join(), 'across cards');
    expect(
      highlights.every((item) => item.id.startsWith('__transient_search__')),
      isTrue,
    );
  });

  test(
    'background indexing neither moves nor expands the reader window',
    () async {
      final source = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(temporary.path, 'parsed')),
          ),
        ),
      );
      addTearDown(source.close);
      await source.open(
        File(
          p.join('test', 'fixtures', 'books', 'feature_rich_lazy_reader.epub'),
        ),
      );
      final initial = source.initialLocation();
      await source.loadAround(initial, after: 0);
      final locationBefore = source.currentLocation;
      final loadedBefore = source.loadedSpineIndices.toSet();
      final indexSession = DerivedBookIndexSession(
        source: source,
        store: DerivedBookIndexStore(
          rootDirectory: Directory(p.join(temporary.path, 'derived')),
        ),
      );
      addTearDown(indexSession.dispose);

      indexSession.start();
      await indexSession.done;

      expect(indexSession.snapshot?.isComplete, isTrue);
      expect(source.currentLocation, locationBefore);
      expect(source.loadedSpineIndices.toSet(), loadedBefore);

      final completed = indexSession.snapshot!;
      final targetSegment = completed.segments.values
          .where((segment) => segment.paragraphs.isNotEmpty)
          .reduce((a, b) => a.spineIndex > b.spineIndex ? a : b);
      final targetText = targetSegment.paragraphs.first.text.trim();
      final query = targetText.substring(0, targetText.length.clamp(1, 18));
      final result = const DerivedBookSearchService()
          .search(completed, query)
          .firstWhere(
            (item) =>
                item.range.location.spineIndex == targetSegment.spineIndex,
          );
      expect(loadedBefore, isNot(contains(targetSegment.spineIndex)));

      final prepared = await source.prepareNavigation(
        result.range.location,
        canCommit: () => true,
      );
      expect(prepared.superseded, isFalse);
      expect(
        prepared.resolution.location?.spineIndex,
        targetSegment.spineIndex,
      );
      expect(
        prepared.window?.sections.map((section) => section.identity.spineIndex),
        contains(targetSegment.spineIndex),
      );
    },
  );

  test(
    'owner cancellation before launch publishes no speculative segment',
    () async {
      final source = LazyBookSession(
        repository: LazySectionRepository(
          cache: ParsedSectionCacheService(
            rootDirectory: Directory(p.join(temporary.path, 'cancel_parsed')),
          ),
        ),
      );
      addTearDown(source.close);
      await source.open(
        File(
          p.join('test', 'fixtures', 'books', 'feature_rich_lazy_reader.epub'),
        ),
      );
      final indexSession = DerivedBookIndexSession(
        source: source,
        store: DerivedBookIndexStore(
          rootDirectory: Directory(p.join(temporary.path, 'cancel_derived')),
        ),
      );
      addTearDown(indexSession.dispose);

      indexSession.start();
      indexSession.cancel();
      await indexSession.done;

      expect(indexSession.snapshot?.manifest.records, isEmpty);
      expect(indexSession.isRunning, isFalse);
    },
  );

  test('Book Memory adds stable moments incrementally without duplication', () {
    final memory = BookMemorySnapshot.fromStorage(
      bookId: 'book.epub',
      metadata: null,
      bookmarks: const [],
      highlights: [
        Highlight(
          id: 'character',
          originalChunkIndex: 0,
          startOffset: 0,
          endOffset: 4,
          text: 'Café',
          type: HighlightType.character,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
      ],
      words: const [],
      chapters: const [],
      indexedSectionCount: 1,
      totalIndexSectionCount: 2,
    );
    final snapshot = DerivedIndexSnapshot(
      manifest: _manifest(recordCount: 1, complete: false, total: 2),
      segments: {0: buildDerivedIndexSegment(_section())},
    );
    final service = BookMemoryService();
    final first = service.updateDerivedOccurrenceIndexForTesting(
      StoredCharacterOccurrenceIndex.empty(),
      memory.characters,
      snapshot,
    );
    final resumed = service.updateDerivedOccurrenceIndexForTesting(
      first,
      memory.characters,
      snapshot,
    );

    final occurrence = first[memory.characters.single.sourceId];
    expect(memory.indexedCoverage, 0.5);
    expect(occurrence?.count, 1);
    expect(occurrence?.first?.sourceRange?.location.spineIndex, 0);
    expect(identical(first, resumed), isTrue);
    expect(memory.highlights, isEmpty);
    expect(memory.characters.single.highlights.single.id, 'character');
  });

  test(
    'explicit indexed navigation wins restore without overwriting checkpoint',
    () {
      const checkpoint = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 0,
        href: 'one.xhtml',
        sourceChecksum: 'one',
      );
      const target = StableBookLocation(
        bookId: 'book.epub',
        spineIndex: 2,
        href: 'three.xhtml',
        sourceChecksum: 'three',
      );

      expect(
        selectReaderOpenRestoreLocation(
          checkpointLocation: checkpoint,
          requestedLocation: target,
          metadataLocation: checkpoint,
          requestedLocationIsNavigationTarget: true,
        ),
        target,
      );
      expect(
        selectReaderOpenPersistedLastRead(
          existingLocation: checkpoint,
          resolvedTarget: target,
          canMigratePersisted: true,
          canMigrateLegacyPosition: false,
          requestedLocationIsNavigationTarget: true,
        ),
        checkpoint,
      );
    },
  );
}

ParsedSection _section({
  int spineIndex = 0,
  String fingerprint = 'fingerprint-a',
  String paragraphId = 'p-1',
  String first = 'Café across ',
  String second = 'cards',
}) {
  final firstEnd = first.length;
  return ParsedSection(
    identity: LazySectionIdentity(
      bookId: 'book.epub',
      publicationFingerprint: fingerprint,
      spineIndex: spineIndex,
      href: 's$spineIndex.xhtml',
      normalizedHref: 's$spineIndex.xhtml',
      fullPath: 'OPS/s$spineIndex.xhtml',
      sourceChecksum: 'checksum-$spineIndex',
      parserVersion: lazyParsedSectionParserVersion,
      dependencySignature: 'dependency',
      dependencySchemaVersion: 1,
    ),
    chunks: [
      BookChunk(
        index: 0,
        type: BookChunkType.text,
        text: first,
        logicalParagraphId: paragraphId,
        logicalParagraphStartOffset: 0,
        logicalParagraphEndOffset: firstEnd,
      ),
      if (second.isNotEmpty)
        BookChunk(
          index: 1,
          type: BookChunkType.text,
          text: second,
          logicalParagraphId: paragraphId,
          logicalParagraphStartOffset: firstEnd,
          logicalParagraphEndOffset: firstEnd + second.length,
        ),
    ],
    anchorMap: const {},
    chapters: const [],
    wordCount: 3,
    textCharCount: first.length + second.length,
    resourceHrefs: const [],
    parserVersion: lazyParsedSectionParserVersion,
  );
}

DerivedIndexManifest _manifest({
  required int recordCount,
  required bool complete,
  int total = 1,
}) {
  return DerivedIndexManifest(
    schemaVersion: derivedBookIndexSchemaVersion,
    normalizationVersion: derivedBookSearchNormalizationVersion,
    bookId: 'book.epub',
    publicationFingerprint: 'fingerprint-a',
    parserVersion: lazyParsedSectionParserVersion,
    generation: 1,
    totalSections: total,
    records: List.generate(
      recordCount,
      (index) => DerivedIndexSegmentRecord(
        spineIndex: index,
        href: 's$index.xhtml',
        sourceChecksum: 'checksum-$index',
        fileName: 'segment-$index',
        fileChecksum: 'file-$index',
        fileSizeBytes: 1,
        paragraphCount: 1,
        generation: 1,
      ),
    ),
    complete: complete,
    createdAtMs: 1,
    updatedAtMs: 1,
    lastAccessedAtMs: 1,
  );
}
