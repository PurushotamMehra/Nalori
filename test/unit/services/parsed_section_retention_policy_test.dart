import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/parsed_section_retention_policy.dart';

void main() {
  test(
    'two most recently meaningfully read books get secondary protection',
    () {
      final registry = ParsedSectionRetentionRegistry();
      registry.recordMeaningfulRead(bookId: 'old.epub', readAtMs: 100);
      registry.recordMeaningfulRead(bookId: 'recent.epub', readAtMs: 300);
      registry.recordMeaningfulRead(bookId: 'second.epub', readAtMs: 200);

      final snapshot = registry.snapshot();

      expect(snapshot.recentBookIds, ['recent.epub', 'second.epub']);
      expect(
        snapshot.protectionFor(_identity('recent.epub')),
        ParsedSectionProtection.recentBook,
      );
      expect(
        snapshot.protectionFor(_identity('old.epub')),
        ParsedSectionProtection.cold,
      );
    },
  );

  test('last visible recent section and neighbors get stronger protection', () {
    final registry = ParsedSectionRetentionRegistry();
    final visible = _identity('recent.epub', spineIndex: 4);
    final adjacent = _identity('recent.epub', spineIndex: 5);
    registry.recordMeaningfulRead(
      bookId: 'recent.epub',
      readAtMs: 300,
      lastVisible: visible,
      adjacent: [adjacent],
    );

    final snapshot = registry.snapshot();

    expect(
      snapshot.protectionFor(visible),
      ParsedSectionProtection.recentNearby,
    );
    expect(
      snapshot.protectionFor(adjacent),
      ParsedSectionProtection.recentNearby,
    );
  });

  test('low and critical pressure reduce secondary protection', () {
    final registry = ParsedSectionRetentionRegistry();
    registry.recordMeaningfulRead(bookId: 'first.epub', readAtMs: 300);
    registry.recordMeaningfulRead(bookId: 'second.epub', readAtMs: 200);

    expect(
      registry.snapshot(pressure: ParsedCacheStoragePressure.low).recentBookIds,
      ['first.epub'],
    );
    expect(
      registry
          .snapshot(pressure: ParsedCacheStoragePressure.critical)
          .recentBookIds,
      isEmpty,
    );
  });
}

LazySectionIdentity _identity(String bookId, {int spineIndex = 0}) {
  final href = 'text/$spineIndex.xhtml';
  return LazySectionIdentity(
    bookId: bookId,
    publicationFingerprint: '$bookId-publication',
    spineIndex: spineIndex,
    href: href,
    normalizedHref: href,
    fullPath: 'OEBPS/$href',
    sourceChecksum: 'checksum-$spineIndex',
    parserVersion: lazyParsedSectionParserVersion,
    dependencySignature: 'dependencies',
    dependencySchemaVersion: lazyParsedSectionDependencySchemaVersion,
  );
}
