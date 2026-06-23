import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/epub_parser.dart';

const _prefix = 'NALORI_EPUB_DIAG_STAGE';

int _rss() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return -1;
  }
}

void _diagPrint(Map<String, Object?> payload) {
  // ignore: avoid_print
  print(jsonEncode(payload));
}

Future<T> _measure<T>(
  String fixture,
  String stage,
  Future<T> Function() body, {
  Map<String, Object?> fields = const {},
}) async {
  final before = _rss();
  final sw = Stopwatch()..start();
  try {
    final result = await body();
    sw.stop();
    _diagPrint({
      'prefix': _prefix,
      'fixture': fixture,
      'stage': stage,
      'result': 'ok',
      'elapsedMs': sw.elapsedMilliseconds,
      'rssBefore': before,
      'rssAfter': _rss(),
      'isolate': Isolate.current.debugName ?? Isolate.current.hashCode,
      ...fields,
    });
    return result;
  } catch (error, stackTrace) {
    sw.stop();
    _diagPrint({
      'prefix': _prefix,
      'fixture': fixture,
      'stage': stage,
      'result': 'error',
      'elapsedMs': sw.elapsedMilliseconds,
      'rssBefore': before,
      'rssAfter': _rss(),
      'error': error.toString(),
      'stackTop': stackTrace.toString().split('\n').take(3).join(' | '),
    });
    rethrow;
  }
}

Uint8List _makeControlEpub() {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add(
    'META-INF/container.xml',
    '<?xml version="1.0"?><container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );
  add(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="utf-8"?><package '
        'xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="id"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">control</dc:identifier>'
        '<dc:title>Control EPUB</dc:title><dc:creator>Nalori</dc:creator>'
        '<dc:language>en</dc:language></metadata><manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/><item id="chap1" href="chapter1.xhtml" '
        'media-type="application/xhtml+xml"/></manifest><spine>'
        '<itemref idref="chap1"/></spine></package>',
  );
  add(
    'OEBPS/nav.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Control</title></head><body><nav>'
        '<ol><li><a href="chapter1.xhtml">Chapter One</a></li></ol>'
        '</nav></body></html>',
  );
  add(
    'OEBPS/chapter1.xhtml',
    '<?xml version="1.0" encoding="utf-8"?><html '
        'xmlns="http://www.w3.org/1999/xhtml"><head><title>Control</title>'
        '</head><body><h1>Chapter One</h1>'
        '<p>This is a small valid EPUB used as a parser control.</p>'
        '<p>It has ordinary paragraphs and a simple table.</p>'
        '<table><tr><th>A</th><th>B</th></tr>'
        '<tr><td>One</td><td>Two</td></tr></table></body></html>',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Future<void> _runFixture(String fixture, File file) async {
  final bytes = await _measure(
    fixture,
    'read_compressed_bytes',
    file.readAsBytes,
    fields: {'path': file.path},
  );

  final bookRef = await _measure(
    fixture,
    'epub_reader_open_book',
    () => EpubReader.openBook(bytes),
    fields: {'bytes': bytes.length},
  );
  _diagPrint({
    'prefix': _prefix,
    'fixture': fixture,
    'stage': 'open_book_summary',
    'htmlRefs': bookRef.Content?.Html?.length,
    'imageRefs': bookRef.Content?.Images?.length,
    'fontRefs': bookRef.Content?.Fonts?.length,
    'cssRefs': bookRef.Content?.Css?.length,
    'spineItems': bookRef.Schema?.Package?.Spine?.Items?.length,
    'rssAfter': _rss(),
  });

  final book = await _measure(
    fixture,
    'epub_reader_read_book',
    () => EpubReader.readBook(bytes),
    fields: {'bytes': bytes.length},
  );
  _diagPrint({
    'prefix': _prefix,
    'fixture': fixture,
    'stage': 'read_book_summary',
    'htmlFiles': book.Content?.Html?.length,
    'images': book.Content?.Images?.length,
    'fonts': book.Content?.Fonts?.length,
    'css': book.Content?.Css?.length,
    'chapters': book.Chapters?.length,
    'rssAfter': _rss(),
  });

  final parsed = await _measure(
    fixture,
    'nalori_load_and_parse_from_file',
    () => EpubParserService().loadAndParseFromFile(file),
  );
  _diagPrint({
    'prefix': _prefix,
    'fixture': fixture,
    'stage': 'nalori_parse_summary',
    'title': parsed.title,
    'chunks': parsed.chunks.length,
    'anchors': parsed.anchorMap.length,
    'chapters': parsed.chapters.length,
    'textChars': parsed.chunks.fold<int>(
      0,
      (sum, chunk) => sum + (chunk.text?.length ?? 0),
    ),
    'imageBytes': parsed.chunks.fold<int>(
      0,
      (sum, chunk) => sum + (chunk.imageBytes?.length ?? 0),
    ),
    'rssAfter': _rss(),
  });

  await _measure(fixture, 'json_encode_parsed_chunks', () async {
    final data = {
      'chunks': parsed.chunks.map((BookChunk c) => c.toJson()).toList(),
      'anchors': parsed.anchorMap,
      'chapters': parsed.chapters.map((c) => c.toJson()).toList(),
    };
    final encoded = jsonEncode(data);
    _diagPrint({
      'prefix': _prefix,
      'fixture': fixture,
      'stage': 'json_encode_summary',
      'jsonChars': encoded.length,
      'rssAfter': _rss(),
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('large EPUB parser diagnostics', () async {
    final problem = File('Dialogues -- Plato.epub');
    expect(problem.existsSync(), isTrue);

    final control = File('${Directory.systemTemp.path}/nalori_control.epub');
    control.writeAsBytesSync(_makeControlEpub());

    await _runFixture('problem', problem);
    await _runFixture('control', control);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
