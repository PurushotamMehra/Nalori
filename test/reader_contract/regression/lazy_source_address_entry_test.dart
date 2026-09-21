import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/canonical_pagination.dart';
import 'package:nalori/models/reader_checkpoint.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_epub_index_service.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';

import '../pagination/reader_core_pagination_harness.dart';

// A comparison witness, deliberately test-only: not a persistent codec, not
// admission/publication authority, and not a normalization of retained cards.
final class _SectionWitness {
  _SectionWitness(LazyEpubIndex index, ParsedSection section)
    : spine = readerSha256([
        index.bookId,
        index.publicationFingerprint,
        index.schemaVersion,
        for (final item in index.spine)
          [
            item.index,
            item.idRef,
            item.normalizedHref,
            item.fullPath,
            item.isLinear,
            item.sourceChecksum,
          ],
      ]),
      identity = canonicalJsonEncode(section.identity.toJson()),
      records = canonicalJsonEncode(
        section.chunks.map((c) => c.toJson()).toList(),
      ) {
    final actual = section.identity;
    final expected = LazySectionIdentity.fromIndexItem(
      bookId: index.bookId,
      publicationFingerprint: index.publicationFingerprint,
      item: index.spine[actual.spineIndex],
      sourceChecksum: index.spine[actual.spineIndex].sourceChecksum,
      dependencySignature: lazySectionDependencySignature(index),
    );
    if (identity != canonicalJsonEncode(expected.toJson()) ||
        section.parserVersion != expected.parserVersion) {
      throw StateError('section authority mismatch');
    }
    validate(section);
  }

  final String spine;
  final String identity;
  final String records;

  void validate(ParsedSection section) {
    if (canonicalJsonEncode(section.identity.toJson()) != identity ||
        section.parserVersion != section.identity.parserVersion ||
        canonicalJsonEncode(section.chunks.map((c) => c.toJson()).toList()) !=
            records) {
      throw StateError('section identity/ordered source records changed');
    }
    for (var local = 0; local < section.chunks.length; local++) {
      if (section.chunks[local].index != local) {
        throw StateError('invalid section-local owner');
      }
    }
  }

  // Canonical JSON is used only to compare this proposed in-memory tuple in
  // tests. No disk/cache/checkpoint format or new source key is installed.
  String address(ParsedSection section, int local) {
    validate(section);
    if (local < 0 || local >= section.chunks.length) {
      throw RangeError.index(local, section.chunks);
    }
    return canonicalJsonEncode([
      spine,
      identity,
      local,
      canonicalBookChunkOwnershipDigest(section.chunks[local]),
    ]);
  }
}

void main() {
  late ReaderCoreParsedFixture fixture;
  late LazyBookSession session;
  late LazyLoadedContentWindow expanded;
  setUpAll(() async {
    fixture = await ReaderCoreParsedFixture.load('source-address-proof-');
    session = LazyBookSession(
      repository: LazySectionRepository(
        cache: ParsedSectionCacheService(
          rootDirectory: Directory('${fixture.temporaryDirectory.path}/cache'),
        ),
        workCoordinator: SharedLazySectionWorkCoordinator(),
      ),
    );
    await session.open(fixture.epubFile);
    expanded = await session.loadAround(session.initialLocation());
  });
  tearDownAll(() async {
    await session.close();
    await fixture.close();
  });

  test(
    'A01 section-local address survives resident eviction and bounded reload',
    () async {
      expect(expanded.sections.length, 2);
      final b = expanded.sections.last;
      final witness = _SectionWitness(session.index, b);
      final expected = witness.address(b, 0);
      final location = session.locationForSectionChunk(b, 0);
      await session.prepareNavigation(location, canCommit: () => true);
      session.handleMemoryPressure();
      expect(session.loadedSpineIndices, [b.identity.spineIndex]);
      final alone = session.loadedWindow();
      expect(alone.chunks.first.index, 0);
      expect(
        expanded.chunks
            .firstWhere((c) => c.sourceFile == alone.chunks.first.sourceFile)
            .index,
        isNot(alone.chunks.first.index),
      );
      expect(witness.address(alone.sections.single, 0), expected);
      // Evict B from both session/repository through the actual pressure path.
      await session.prepareNavigation(
        session.locationForSectionChunk(expanded.sections.first, 0),
        canCommit: () => true,
      );
      session.handleMemoryPressure();
      expect(
        session.loadedSpineIndices,
        isNot(contains(b.identity.spineIndex)),
      );
      final reloaded = await session.prepareNavigation(
        location,
        canCommit: () => true,
      );
      final rebuilt = reloaded.window!.sections.firstWhere(
        (s) => s.identity.spineIndex == b.identity.spineIndex,
      );
      expect(witness.address(rebuilt, 0), expected);
      expect(session.retainedSectionCount, lessThanOrEqualTo(3));
    },
  );

  test('A02 equal local positions in different sections cannot alias', () {
    final a = expanded.sections.first;
    final b = expanded.sections.last;
    expect(a.chunks.first.index, b.chunks.first.index);
    expect(
      _SectionWitness(session.index, a).address(a, 0),
      isNot(_SectionWitness(session.index, b).address(b, 0)),
    );
  });

  for (final change in [
    'insert',
    'remove',
    'reorder',
    'text',
    'parser',
    'dependency',
    'image',
    'structure',
  ]) {
    test('A03 rejects $change against exact section witness', () {
      final source = expanded.sections.first;
      final witness = _SectionWitness(session.index, source);
      final json =
          jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>;
      final chunks = json['chunks'] as List;
      switch (change) {
        case 'insert':
          chunks.add(chunks.last);
          break;
        case 'remove':
          chunks.removeLast();
          break;
        case 'reorder':
          final first = chunks[0];
          chunks[0] = chunks[1];
          chunks[1] = first;
          break;
        case 'text':
          (chunks[0] as Map)['tx'] = 'changed';
          break;
        case 'parser':
          (json['identity'] as Map)['parserVersion'] = 'changed';
          break;
        case 'dependency':
          (json['identity'] as Map)['dependencySignature'] = 'changed';
          break;
        case 'image':
          // Adding contradictory image bytes is a source-record mutation.
          (chunks[0] as Map)['img'] = base64Encode([1, 2, 3]);
          break;
        case 'structure':
          (chunks[0] as Map)['br'] = BookBlockRole.paragraph.index;
          break;
      }
      final changed = ParsedSection.fromJson(json);
      expect(() => witness.address(changed, 0), throwsStateError);
    });
  }
}
