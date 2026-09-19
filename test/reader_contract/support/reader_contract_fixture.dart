import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _contractRoot = 'test/reader_contract';
const _manifestPath =
    'test/reader_contract/fixtures/reader_contract_fixture_manifest.json';

class ReaderContractFixtureManifest {
  ReaderContractFixtureManifest(this.data);

  final Map<String, dynamic> data;

  int get version => _requiredInt(data, 'manifestVersion');

  List<ReaderContractFixture> get fixtures => _requiredList(data, 'fixtures')
      .map(
        (value) =>
            ReaderContractFixture(Map<String, dynamic>.from(value as Map)),
      )
      .toList(growable: false);

  ReaderContractFixture fixture(String id) =>
      fixtures.singleWhere((fixture) => fixture.id == id);

  Future<void> validate({Directory? repositoryRoot}) async {
    if (version != 1) {
      throw FormatException('Unsupported fixture manifest version: $version');
    }
    final ids = <String>{};
    for (final fixture in fixtures) {
      if (!ids.add(fixture.id)) {
        throw FormatException(
          'Duplicate reader-contract fixture ID: ${fixture.id}',
        );
      }
      await fixture.validate(repositoryRoot: repositoryRoot);
    }
  }
}

class ReaderContractFixture {
  ReaderContractFixture(this.data);

  final Map<String, dynamic> data;

  String get id => _requiredString(data, 'id');
  String get name => _requiredString(data, 'name');
  String get type => _requiredString(data, 'type');
  String get purpose => _requiredString(data, 'purpose');
  List<String> get requirements => _stringList(data, 'requirements');
  List<Map<String, dynamic>> get sourceFiles => _mapList(data, 'sourceFiles');
  List<Map<String, dynamic>> get spine => _mapList(data, 'spine');
  List<String> get archiveEntryOrder => sourceFiles
      .map((source) => _requiredString(source, 'archivePath'))
      .toList(growable: false);

  Future<void> validate({Directory? repositoryRoot}) async {
    const requiredTextFields = [
      'id',
      'name',
      'type',
      'provenance',
      'license',
      'builder',
      'checksumPolicy',
      'purpose',
      'permittedUpdateProcedure',
    ];
    for (final field in requiredTextFields) {
      _requiredString(data, field);
    }
    if (sourceFiles.isEmpty || spine.length < 2) {
      throw FormatException(
        '$id must declare source files and two spine sections',
      );
    }
    if (requirements.isEmpty ||
        _stringList(data, 'knownExclusions').isEmpty ||
        _stringList(data, 'structures').isEmpty) {
      throw FormatException('$id is missing scope or requirement evidence');
    }

    final root = repositoryRoot ?? Directory.current;
    final contentsByArchivePath = <String, String>{};
    for (final source in sourceFiles) {
      final archivePath = _requiredString(source, 'archivePath');
      if (contentsByArchivePath.containsKey(archivePath)) {
        throw FormatException('$id has duplicate archive path: $archivePath');
      }
      final sourcePath = _requiredString(source, 'path');
      final file = File(p.join(root.path, _contractRoot, sourcePath));
      if (!await file.exists()) {
        throw FormatException('$id source file is missing: $sourcePath');
      }
      final bytes = await file.readAsBytes();
      final actualChecksum = sha256.convert(bytes).toString();
      if (actualChecksum != _requiredString(source, 'sha256')) {
        throw FormatException('$id source checksum is stale: $sourcePath');
      }
      contentsByArchivePath[archivePath] = utf8.decode(bytes);
    }

    final evidence = _requiredMap(data, 'structureEvidence');
    for (final structure in _stringList(data, 'structures')) {
      final item = evidence[structure];
      if (item is! Map) {
        throw FormatException(
          '$id structure has no source evidence: $structure',
        );
      }
      final itemMap = Map<String, dynamic>.from(item);
      final source =
          contentsByArchivePath[_requiredString(itemMap, 'archivePath')];
      if (source == null ||
          !source.contains(_requiredString(itemMap, 'contains'))) {
        throw FormatException(
          '$id structure lacks source evidence: $structure',
        );
      }
    }

    final opf = contentsByArchivePath['OEBPS/content.opf'];
    if (opf == null) {
      throw FormatException('$id is missing OEBPS/content.opf');
    }
    var previousSpinePosition = -1;
    for (final section in spine) {
      final href = _requiredString(section, 'href');
      final source = contentsByArchivePath['OEBPS/$href'];
      if (source == null) {
        throw FormatException('$id spine source is missing: $href');
      }
      final manifestId = _requiredString(section, 'manifestId');
      if (!opf.contains('id="$manifestId" href="$href"')) {
        throw FormatException(
          '$id OPF manifest does not map $manifestId to $href',
        );
      }
      final spinePosition = opf.indexOf('<itemref idref="$manifestId"');
      if (spinePosition < 0 || spinePosition <= previousSpinePosition) {
        throw FormatException(
          '$id OPF spine order is incomplete or out of order',
        );
      }
      previousSpinePosition = spinePosition;
      final anchors = _stringList(section, 'manuallyValidatedAnchors');
      if (anchors.isEmpty ||
          _stringList(section, 'structuralOrder').isEmpty ||
          _stringList(section, 'parserExpectedSubstrings').isEmpty) {
        throw FormatException('$id spine oracle is incomplete: $href');
      }
      var previousAnchorPosition = -1;
      for (final anchor in anchors) {
        final anchorPosition = source.indexOf('id="$anchor"');
        if (anchorPosition < 0 || anchorPosition <= previousAnchorPosition) {
          throw FormatException(
            '$id source anchor order is incomplete: $href#$anchor',
          );
        }
        previousAnchorPosition = anchorPosition;
      }
      for (final range in _mapList(section, 'ranges')) {
        if (!anchors.contains(_requiredString(range, 'anchor'))) {
          throw FormatException(
            '$id range lacks a declared stable anchor: $href',
          );
        }
        _validateUtf16Range(range);
      }
    }

    final repeatedLocations = <String>{};
    String? repeatedText;
    for (final occurrence in _mapList(data, 'repeatedTextOccurrences')) {
      final href = _requiredString(occurrence, 'href');
      final anchor = _requiredString(occurrence, 'anchor');
      final text = _requiredString(occurrence, 'text');
      final section = _spineSection(href);
      if (!_stringList(section, 'manuallyValidatedAnchors').contains(anchor) ||
          !_requiredString(
            section,
            'normalizedExpectedSourceText',
          ).contains(text)) {
        throw FormatException('$id repeated text lacks stable source evidence');
      }
      if (repeatedText != null && repeatedText != text) {
        throw FormatException('$id repeated-text occurrences disagree');
      }
      repeatedText = text;
      repeatedLocations.add('$href#$anchor');
    }
    if (repeatedLocations.length < 2) {
      throw FormatException('$id needs two distinct repeated-text occurrences');
    }

    final seam = _requiredMap(data, 'sourceSeam');
    _validateSeamEndpoint(
      href: _requiredString(seam, 'fromHref'),
      anchor: _requiredString(seam, 'fromAnchor'),
      text: _requiredString(seam, 'fromText'),
    );
    _validateSeamEndpoint(
      href: _requiredString(seam, 'toHref'),
      anchor: _requiredString(seam, 'toAnchor'),
      text: _requiredString(seam, 'toText'),
    );
  }

  Map<String, dynamic> _spineSection(String href) =>
      spine.singleWhere((section) => _requiredString(section, 'href') == href);

  void _validateSeamEndpoint({
    required String href,
    required String anchor,
    required String text,
  }) {
    final section = _spineSection(href);
    if (!_stringList(section, 'manuallyValidatedAnchors').contains(anchor) ||
        !_requiredString(
          section,
          'normalizedExpectedSourceText',
        ).contains(text)) {
      throw FormatException(
        '$id source seam lacks independently authored evidence',
      );
    }
  }
}

class ReaderContractArchiveEntry {
  const ReaderContractArchiveEntry({
    required this.path,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final Uint8List bytes;
  final String sha256;
}

Future<Map<String, dynamic>> loadReaderContractFixtureManifestJson({
  Directory? repositoryRoot,
}) async {
  final root = repositoryRoot ?? Directory.current;
  final file = File(p.join(root.path, _manifestPath));
  return Map<String, dynamic>.from(
    jsonDecode(await file.readAsString()) as Map,
  );
}

Future<ReaderContractFixtureManifest> loadReaderContractFixtureManifest({
  Directory? repositoryRoot,
}) async {
  final manifest = ReaderContractFixtureManifest(
    await loadReaderContractFixtureManifestJson(repositoryRoot: repositoryRoot),
  );
  await manifest.validate(repositoryRoot: repositoryRoot);
  return manifest;
}

Future<File> buildReaderContractFixtureEpub({
  required ReaderContractFixture fixture,
  required Directory outputDirectory,
  Directory? repositoryRoot,
}) async {
  final root = repositoryRoot ?? Directory.current;
  await fixture.validate(repositoryRoot: root);
  await outputDirectory.create(recursive: true);
  final archive = Archive();
  for (final source in fixture.sourceFiles) {
    final sourcePath = _requiredString(source, 'path');
    final bytes = await File(
      p.join(root.path, _contractRoot, sourcePath),
    ).readAsBytes();
    archive.addFile(
      ArchiveFile(
        _requiredString(source, 'archivePath'),
        bytes.length,
        Uint8List.fromList(bytes),
      ),
    );
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('Could not encode fixture ${fixture.id}');
  }
  final epub = File(p.join(outputDirectory.path, '${fixture.id}.epub'));
  await epub.writeAsBytes(encoded, flush: true);
  return epub;
}

Future<List<ReaderContractArchiveEntry>> inspectReaderContractEpub(
  File epub,
) async {
  final archive = ZipDecoder().decodeBytes(await epub.readAsBytes());
  return archive.files
      .where((file) => file.isFile)
      .map((file) {
        final bytes = Uint8List.fromList(file.content as List<int>);
        return ReaderContractArchiveEntry(
          path: file.name,
          bytes: bytes,
          sha256: sha256.convert(bytes).toString(),
        );
      })
      .toList(growable: false);
}

void _validateUtf16Range(Map<String, dynamic> range) {
  final source = _requiredString(range, 'sourceText');
  final start = _requiredInt(range, 'startUtf16');
  final end = _requiredInt(range, 'endUtf16');
  if (start < 0 || end <= start || end > source.length) {
    throw const FormatException('Invalid UTF-16 half-open range');
  }
  if (source.substring(start, end) !=
      _requiredString(range, 'expectedSubstring')) {
    throw const FormatException(
      'UTF-16 range resolves to a different substring',
    );
  }
}

List<dynamic> _requiredList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.isEmpty) {
    throw FormatException('Missing fixture manifest list: $key');
  }
  return value;
}

List<Map<String, dynamic>> _mapList(Map<String, dynamic> json, String key) =>
    _requiredList(json, key)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map || value.isEmpty) {
    throw FormatException('Missing fixture manifest map: $key');
  }
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing fixture manifest text: $key');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw FormatException('Missing fixture manifest number: $key');
  }
  return value.toInt();
}

List<String> _stringList(Map<String, dynamic> json, String key) =>
    _requiredList(json, key)
        .map((value) {
          if (value is! String || value.trim().isEmpty) {
            throw FormatException('Invalid fixture manifest string list: $key');
          }
          return value;
        })
        .toList(growable: false);
