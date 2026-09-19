import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/epub_parser.dart';

import '../support/reader_contract_fixture.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'nalori_reader_contract_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  group('[REQ-032, REQ-034, REQ-051] reader-contract fixture foundation', () {
    test(
      'validates authored provenance, source evidence, and UTF-16 ranges',
      () async {
        final manifest = await loadReaderContractFixtureManifest();
        final fixture = manifest.fixture('reader-core-micro-v1');

        expect(fixture.name, 'Reader core micro EPUB');
        expect(fixture.spine.map((section) => section['href']), [
          'text/chapter-one.xhtml',
          'text/chapter-two.xhtml',
        ]);
        expect(
          fixture.requirements,
          containsAll(<String>['REQ-032', 'REQ-034', 'REQ-051']),
        );
      },
    );

    test(
      'rejects incomplete, stale, or internally inconsistent manifests',
      () async {
        final original = await loadReaderContractFixtureManifestJson();

        final missingPurpose = _copyManifest(original);
        _firstFixture(missingPurpose).remove('purpose');
        await expectLater(
          ReaderContractFixtureManifest(missingPurpose).validate(),
          throwsA(isA<FormatException>()),
        );

        final duplicateId = _copyManifest(original);
        final duplicate = Map<String, dynamic>.from(
          (duplicateId['fixtures'] as List).first as Map,
        );
        (duplicateId['fixtures'] as List).add(duplicate);
        await expectLater(
          ReaderContractFixtureManifest(duplicateId).validate(),
          throwsA(isA<FormatException>()),
        );

        final missingStructureEvidence = _copyManifest(original);
        (_firstFixture(missingStructureEvidence)['structureEvidence']
                as Map<String, dynamic>)
            .remove('table');
        await expectLater(
          ReaderContractFixtureManifest(missingStructureEvidence).validate(),
          throwsA(isA<FormatException>()),
        );

        final staleChecksum = _copyManifest(original);
        ((((staleChecksum['fixtures'] as List).first
                        as Map<String, dynamic>)['sourceFiles']
                    as List)
                .first
            as Map<String, dynamic>)['sha256'] = List<String>.filled(
          64,
          '0',
        ).join();
        await expectLater(
          ReaderContractFixtureManifest(staleChecksum).validate(),
          throwsA(isA<FormatException>()),
        );

        final outsideRange = _copyManifest(original);
        final outsideRangeData = _firstRange(outsideRange);
        outsideRangeData['endUtf16'] = 100000;
        await expectLater(
          ReaderContractFixtureManifest(outsideRange).validate(),
          throwsA(isA<FormatException>()),
        );

        final differentSubstring = _copyManifest(original);
        _firstRange(differentSubstring)['expectedSubstring'] = 'not the range';
        await expectLater(
          ReaderContractFixtureManifest(differentSubstring).validate(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'assembles required EPUB entries and preserves manifest spine order',
      () async {
        final fixture = (await loadReaderContractFixtureManifest()).fixture(
          'reader-core-micro-v1',
        );
        final epub = await buildReaderContractFixtureEpub(
          fixture: fixture,
          outputDirectory: Directory('${temporaryDirectory.path}/first'),
        );
        final entries = await inspectReaderContractEpub(epub);

        expect(entries.map((entry) => entry.path), fixture.archiveEntryOrder);
        expect(entries.map((entry) => entry.path), contains('mimetype'));
        expect(
          entries.map((entry) => entry.path),
          contains('META-INF/container.xml'),
        );
        expect(
          entries.map((entry) => entry.path),
          contains('OEBPS/content.opf'),
        );
        expect(entries.map((entry) => entry.path), contains('OEBPS/nav.xhtml'));

        final expectedChecksums = fixture.sourceFiles.map(
          (source) => source['sha256'],
        );
        expect(entries.map((entry) => entry.sha256), expectedChecksums);
        final opf = utf8.decode(
          entries
              .singleWhere((entry) => entry.path == 'OEBPS/content.opf')
              .bytes,
        );
        expect(
          opf.indexOf('<itemref idref="chapter-one"'),
          lessThan(opf.indexOf('<itemref idref="chapter-two"')),
        );
      },
    );

    test('separately built copies have identical logical contents', () async {
      final fixture = (await loadReaderContractFixtureManifest()).fixture(
        'reader-core-micro-v1',
      );
      final first = await buildReaderContractFixtureEpub(
        fixture: fixture,
        outputDirectory: Directory('${temporaryDirectory.path}/first'),
      );
      final second = await buildReaderContractFixtureEpub(
        fixture: fixture,
        outputDirectory: Directory('${temporaryDirectory.path}/second'),
      );

      final firstEntries = await inspectReaderContractEpub(first);
      final secondEntries = await inspectReaderContractEpub(second);
      expect(
        firstEntries.map((entry) => entry.path),
        orderedEquals(secondEntries.map((entry) => entry.path)),
      );
      expect(
        firstEntries.map((entry) => entry.sha256),
        orderedEquals(secondEntries.map((entry) => entry.sha256)),
      );
      for (var index = 0; index < firstEntries.length; index++) {
        expect(
          firstEntries[index].bytes,
          orderedEquals(secondEntries[index].bytes),
        );
      }
    });

    test(
      'production parsing exposes the independently authored source evidence',
      () async {
        final fixture = (await loadReaderContractFixtureManifest()).fixture(
          'reader-core-micro-v1',
        );
        final epub = await buildReaderContractFixtureEpub(
          fixture: fixture,
          outputDirectory: Directory('${temporaryDirectory.path}/parser'),
        );
        final parsed = await EpubParserService().loadAndParseFromFile(epub);
        final text = parsed.chunks.map((chunk) => chunk.text ?? '').join('\n');

        for (final section in fixture.spine) {
          for (final expected in section['parserExpectedSubstrings'] as List) {
            expect(text, contains(expected));
          }
        }
        expect(parsed.chunks.where((chunk) => chunk.isHeading), isNotEmpty);
        expect(
          parsed.chunks.any((chunk) => chunk.listSemantics != null),
          isTrue,
        );
        expect(
          parsed.chunks.any((chunk) => chunk.blockRole == BookBlockRole.table),
          isTrue,
        );
        expect(
          parsed.chunks.any(
            (chunk) => (chunk.inlineStyles?.isNotEmpty ?? false),
          ),
          isTrue,
        );
        expect(
          parsed.chunks.any((chunk) => (chunk.links?.isNotEmpty ?? false)),
          isTrue,
        );
      },
    );
  });
}

Map<String, dynamic> _copyManifest(Map<String, dynamic> original) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(original)) as Map);

Map<String, dynamic> _firstFixture(Map<String, dynamic> manifest) =>
    (manifest['fixtures'] as List).first as Map<String, dynamic>;

Map<String, dynamic> _firstRange(Map<String, dynamic> manifest) {
  final fixture = _firstFixture(manifest);
  final section = (fixture['spine'] as List).first as Map<String, dynamic>;
  return (section['ranges'] as List).first as Map<String, dynamic>;
}
