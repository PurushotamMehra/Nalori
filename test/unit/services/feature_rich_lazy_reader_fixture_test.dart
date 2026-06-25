import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'nalori_feature_rich_lazy_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'fixture opens at meaningful Chapter 1 with nested TOC targets',
    () async {
      final session = await _openSession(tempDir);
      addTearDown(session.close);

      final index = session.index;
      final initial = session.initialLocation();

      expect(index.spine.map((item) => item.href), [
        'titlepage.xhtml',
        'chapter-1.xhtml',
        'chapter-2.xhtml',
        'chapter-3.xhtml',
        'notes.xhtml',
      ]);
      expect(
        index.chapters.map((chapter) => chapter.title),
        contains('Part I'),
      );
      expect(
        index.chapters.map((chapter) => chapter.title),
        contains('Part II'),
      );
      expect(initial.spineIndex, 1);
      expect(initial.href, 'chapter-1.xhtml');
      expect(initial.anchorId, 'chapter-1');

      final partOne = index.chapters.firstWhere(
        (chapter) => chapter.title == 'Part I',
      );
      final partTwo = index.chapters.firstWhere(
        (chapter) => chapter.title == 'Part II',
      );
      expect(partOne.children.map((chapter) => chapter.title), [
        'Chapter 1',
        'Chapter 2',
      ]);
      expect(partTwo.children.map((chapter) => chapter.title), ['Chapter 3']);
      expect(session.resolveChapterTarget(partOne.children[1])?.spineIndex, 2);
      expect(
        session.resolveChapterTarget(partTwo.children.first)?.spineIndex,
        3,
      );
    },
  );

  test(
    'cross-section footnote and backlink load exact target sections',
    () async {
      final session = await _openSession(tempDir);
      addTearDown(session.close);

      final initialWindow = await session.loadAround(
        session.initialLocation(),
        after: 0,
      );
      expect(session.loadedSpineIndices, [1]);
      expect(_containsText(initialWindow.chunks, _originContext), isTrue);
      expect(_containsText(initialWindow.chunks, _footnoteContext), isFalse);

      final noteTarget = session.resolveAnchor('notes.xhtml', 'note-1');
      expect(noteTarget, isNotNull);
      final noteWindow = await session.loadAround(noteTarget!, after: 0);
      expect(
        noteWindow.sections.map((section) => section.identity.spineIndex),
        [4],
      );
      expect(_containsText(noteWindow.chunks, _footnoteContext), isTrue);

      final backlinkTarget = session.resolveAnchor(
        'chapter-1.xhtml',
        'origin-paragraph',
      );
      expect(backlinkTarget, isNotNull);
      final originWindow = await session.loadAround(backlinkTarget!, after: 0);
      expect(_containsText(originWindow.chunks, _originContext), isTrue);
    },
  );

  test(
    'cross-section internal anchor resolves exact Chapter 2 paragraph',
    () async {
      final session = await _openSession(tempDir);
      addTearDown(session.close);

      await session.loadAround(session.initialLocation(), after: 0);
      final target = session.resolveAnchor(
        'chapter-2.xhtml',
        'chapter-2-target',
      );
      expect(target, isNotNull);

      final window = await session.loadAround(target!, after: 0);
      expect(
        window.sections.map((section) => section.identity.spineIndex),
        contains(2),
      );
      expect(_containsText(window.chunks, _chapter2TargetContext), isTrue);
    },
  );

  test('image and table parse only when current section is loaded', () async {
    final session = await _openSession(tempDir);
    addTearDown(session.close);

    final chapterTwo = session.resolveAnchor(
      'chapter-2.xhtml',
      'chapter-2-target',
    );
    expect(chapterTwo, isNotNull);
    final chapterTwoWindow = await session.loadAround(chapterTwo!, after: 0);
    final chapterTwoSection = chapterTwoWindow.sections.firstWhere(
      (section) => section.identity.spineIndex == 2,
    );
    expect(
      chapterTwoSection.resourceHrefs,
      isNot(contains('images/generated-square.png')),
    );
    expect(
      chapterTwoWindow.chunks.any((chunk) => chunk.type == BookChunkType.image),
      isFalse,
    );

    final chapterOneWindow = await session.loadAround(
      session.initialLocation(),
      after: 0,
    );
    final chapterOneSection = chapterOneWindow.sections.firstWhere(
      (section) => section.identity.spineIndex == 1,
    );
    expect(
      chapterOneSection.resourceHrefs,
      contains('images/generated-square.png'),
    );
    expect(
      chapterOneWindow.chunks.any((chunk) => chunk.type == BookChunkType.image),
      isTrue,
    );
    expect(
      chapterOneWindow.chunks.any(
        (chunk) => chunk.blockRole == BookBlockRole.table,
      ),
      isTrue,
    );
  });

  test('repeated phrase navigation remains context-disambiguated', () async {
    final session = await _openSession(tempDir);
    addTearDown(session.close);

    final chapterOne = await session.loadAround(
      session.resolveAnchor('chapter-1.xhtml', 'origin-paragraph')!,
      after: 0,
    );
    final chapterTwo = await session.loadAround(
      session.resolveAnchor('chapter-2.xhtml', 'chapter-2-target')!,
      after: 0,
    );

    expect(_containsText(chapterOne.chunks, 'luminous pebble'), isTrue);
    expect(_containsText(chapterTwo.chunks, 'luminous pebble'), isTrue);
    expect(_containsText(chapterOne.chunks, _originContext), isTrue);
    expect(_containsText(chapterTwo.chunks, _chapter2TargetContext), isTrue);
  });

  test(
    'missing and malformed fragments do not produce false exact matches',
    () async {
      final session = await _openSession(tempDir);
      addTearDown(session.close);

      final missing = session.resolveAnchor('notes.xhtml', 'missing-note');
      expect(missing, isNotNull);
      final window = await session.loadAround(missing!, after: 0);

      expect(window.anchorMap.containsKey('missing-note'), isFalse);
      expect(_containsText(window.chunks, _footnoteContext), isTrue);
      expect(session.resolveAnchor('missing.xhtml', 'note-1'), isNull);
    },
  );
}

Future<LazyBookSession> _openSession(Directory tempDir) async {
  final fixture = File(
    p.join('test', 'fixtures', 'books', 'feature_rich_lazy_reader.epub'),
  );
  expect(await fixture.exists(), isTrue);
  final session = LazyBookSession(
    repository: LazySectionRepository(
      cache: ParsedSectionCacheService(
        rootDirectory: Directory(p.join(tempDir.path, 'cache')),
      ),
    ),
  );
  await session.open(fixture);
  return session;
}

bool _containsText(List<BookChunk> chunks, String expected) {
  final normalizedExpected = _normalize(expected);
  return chunks
      .map((chunk) => _normalize(chunk.text ?? ''))
      .any((text) => text.contains(normalizedExpected));
}

String _normalize(String input) {
  return input.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

const _originContext =
    'Synthetic paragraph with a unique source context for lazy footnote testing.';
const _footnoteContext =
    'Synthetic footnote content for lazy cross section navigation.';
const _chapter2TargetContext =
    'Chapter 2 target paragraph for a cross section internal link.';
