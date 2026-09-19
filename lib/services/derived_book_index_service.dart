import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book_chunk.dart';
import '../models/derived_book_index.dart';
import '../models/stable_book_location.dart';
import 'book_authoritative_text_service.dart';
import 'lazy_book_session.dart';
import 'lazy_parsed_book.dart';
import 'reader_unicode_normalization.dart';

const int derivedBookIndexSchemaVersion = 1;
const int derivedBookSearchNormalizationVersion = 1;
const int defaultDerivedIndexBudgetBytes = 64 * 1024 * 1024;

final class DerivedIndexGenerationRejected implements Exception {
  const DerivedIndexGenerationRejected();
}

final class DerivedBookIndexStore {
  DerivedBookIndexStore({
    Directory? rootDirectory,
    this.byteBudget = defaultDerivedIndexBudgetBytes,
  }) : _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;
  final int byteBudget;

  Future<Directory> _root() async {
    final explicit = _rootDirectory;
    if (explicit != null) {
      await explicit.create(recursive: true);
      return explicit;
    }
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'derived_book_index_v1'));
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> _bookDirectory(String bookId) async {
    final root = await _root();
    final safe = sha256.convert(utf8.encode(bookId)).toString();
    final directory = Directory(p.join(root.path, safe));
    await directory.create(recursive: true);
    return directory;
  }

  Future<DerivedIndexSnapshot> open({
    required String bookId,
    required String publicationFingerprint,
    required String parserVersion,
    required int totalSections,
  }) async {
    final directory = await _bookDirectory(bookId);
    await _removeTemporaryFiles(directory);
    final manifestFile = File(p.join(directory.path, 'manifest.json'));
    final old = await _readManifest(manifestFile);
    final matches =
        old != null &&
        old.schemaVersion == derivedBookIndexSchemaVersion &&
        old.normalizationVersion == derivedBookSearchNormalizationVersion &&
        old.bookId == bookId &&
        old.publicationFingerprint == publicationFingerprint &&
        old.parserVersion == parserVersion &&
        old.totalSections == totalSections;
    DerivedIndexManifest manifest;
    if (matches) {
      manifest = old;
    } else {
      if (old?.complete == true) {
        await _atomicWrite(
          File(p.join(directory.path, 'previous_manifest.json')),
          utf8.encode(jsonEncode(old!.toJson())),
        );
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      manifest = DerivedIndexManifest(
        schemaVersion: derivedBookIndexSchemaVersion,
        normalizationVersion: derivedBookSearchNormalizationVersion,
        bookId: bookId,
        publicationFingerprint: publicationFingerprint,
        parserVersion: parserVersion,
        generation: (old?.generation ?? 0) + 1,
        totalSections: totalSections,
        records: const [],
        complete: totalSections == 0,
        createdAtMs: now,
        updatedAtMs: now,
        lastAccessedAtMs: now,
      );
      await _writeManifest(directory, manifest);
    }
    return _validatedSnapshot(directory, manifest);
  }

  Future<DerivedIndexSnapshot?> loadForBook(String bookId) async {
    final directory = await _bookDirectory(bookId);
    final manifest = await _readManifest(
      File(p.join(directory.path, 'manifest.json')),
    );
    if (manifest == null ||
        manifest.schemaVersion != derivedBookIndexSchemaVersion ||
        manifest.normalizationVersion !=
            derivedBookSearchNormalizationVersion) {
      return null;
    }
    return _validatedSnapshot(directory, manifest);
  }

  Future<DerivedIndexSnapshot> publishSegment({
    required DerivedIndexManifest expectedManifest,
    required DerivedIndexSegment segment,
  }) async {
    final directory = await _bookDirectory(expectedManifest.bookId);
    final current = await _readManifest(
      File(p.join(directory.path, 'manifest.json')),
    );
    if (current == null ||
        current.generation != expectedManifest.generation ||
        current.publicationFingerprint !=
            expectedManifest.publicationFingerprint ||
        segment.publicationFingerprint != current.publicationFingerprint ||
        segment.schemaVersion != current.schemaVersion ||
        segment.normalizationVersion != current.normalizationVersion) {
      throw const DerivedIndexGenerationRejected();
    }
    final bytes = utf8.encode(jsonEncode(segment.toJson()));
    final checksum = sha256.convert(bytes).toString();
    final fingerprint = sha256
        .convert(utf8.encode(current.publicationFingerprint))
        .toString()
        .substring(0, 12);
    final fileName =
        'g${current.generation}_${fingerprint}_s${segment.spineIndex}.json';
    await _atomicWrite(File(p.join(directory.path, fileName)), bytes);
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = DerivedIndexSegmentRecord(
      spineIndex: segment.spineIndex,
      href: segment.href,
      sourceChecksum: segment.sourceChecksum,
      fileName: fileName,
      fileChecksum: checksum,
      fileSizeBytes: bytes.length,
      paragraphCount: segment.paragraphs.length,
      generation: current.generation,
    );
    final records =
        current.records
            .where((item) => item.spineIndex != segment.spineIndex)
            .toList()
          ..add(record)
          ..sort((a, b) => a.spineIndex.compareTo(b.spineIndex));
    final complete = records.length == current.totalSections;
    final updated = current.copyWith(
      records: List.unmodifiable(records),
      complete: complete,
      updatedAtMs: now,
      lastAccessedAtMs: now,
    );
    await _writeManifest(directory, updated);
    if (complete) {
      final previous = File(p.join(directory.path, 'previous_manifest.json'));
      if (await previous.exists()) await previous.delete();
      await _removeUnreferencedSegments(directory, updated);
    }
    final snapshot = await _validatedSnapshot(directory, updated);
    await enforceBudget(protectedBookId: current.bookId);
    return snapshot;
  }

  Future<DerivedIndexSnapshot> _validatedSnapshot(
    Directory directory,
    DerivedIndexManifest manifest,
  ) async {
    final validRecords = <DerivedIndexSegmentRecord>[];
    final segments = <int, DerivedIndexSegment>{};
    for (final record in manifest.records) {
      try {
        final file = File(p.join(directory.path, record.fileName));
        final bytes = await file.readAsBytes();
        if (bytes.length != record.fileSizeBytes ||
            sha256.convert(bytes).toString() != record.fileChecksum) {
          continue;
        }
        final segment = DerivedIndexSegment.fromJson(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        );
        if (segment.schemaVersion != manifest.schemaVersion ||
            segment.normalizationVersion != manifest.normalizationVersion ||
            segment.bookId != manifest.bookId ||
            segment.publicationFingerprint != manifest.publicationFingerprint ||
            segment.parserVersion != manifest.parserVersion ||
            segment.spineIndex != record.spineIndex ||
            segment.sourceChecksum != record.sourceChecksum) {
          continue;
        }
        validRecords.add(record);
        segments[record.spineIndex] = segment;
      } catch (_) {
        // A bad derivative is a cache miss. User data and parsed source remain.
      }
    }
    var validated = manifest;
    if (validRecords.length != manifest.records.length) {
      final now = DateTime.now().millisecondsSinceEpoch;
      validated = manifest.copyWith(
        records: List.unmodifiable(validRecords),
        complete: false,
        updatedAtMs: now,
        lastAccessedAtMs: now,
      );
      await _writeManifest(directory, validated);
    }
    return DerivedIndexSnapshot(
      manifest: validated,
      segments: Map.unmodifiable(segments),
    );
  }

  Future<void> enforceBudget({String? protectedBookId}) async {
    final root = await _root();
    final directories = await root
        .list()
        .where((entry) => entry is Directory)
        .cast<Directory>()
        .toList();
    final candidates = <({Directory directory, int bytes, int accessed})>[];
    var total = 0;
    for (final directory in directories) {
      var bytes = 0;
      await for (final entry in directory.list()) {
        if (entry is File) bytes += await entry.length();
      }
      final manifest = await _readManifest(
        File(p.join(directory.path, 'manifest.json')),
      );
      total += bytes;
      if (manifest?.bookId != protectedBookId) {
        candidates.add((
          directory: directory,
          bytes: bytes,
          accessed: manifest?.lastAccessedAtMs ?? 0,
        ));
      }
    }
    candidates.sort((a, b) => a.accessed.compareTo(b.accessed));
    for (final candidate in candidates) {
      if (total <= byteBudget) break;
      await candidate.directory.delete(recursive: true);
      total -= candidate.bytes;
    }
  }

  Future<void> removeBook(String bookId) async {
    final directory = await _bookDirectory(bookId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> clearAll() async {
    final root = await _root();
    if (!await root.exists()) return;
    await for (final entry in root.list()) {
      if (entry is Directory) await entry.delete(recursive: true);
      if (entry is File) await entry.delete();
    }
  }

  Future<DerivedIndexManifest?> _readManifest(File file) async {
    if (!await file.exists()) return null;
    try {
      return DerivedIndexManifest.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeManifest(
    Directory directory,
    DerivedIndexManifest manifest,
  ) {
    return _atomicWrite(
      File(p.join(directory.path, 'manifest.json')),
      utf8.encode(jsonEncode(manifest.toJson())),
    );
  }

  Future<void> _atomicWrite(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> _removeTemporaryFiles(Directory directory) async {
    await for (final entry in directory.list()) {
      if (entry is File && entry.path.endsWith('.tmp')) {
        await entry.delete();
      }
    }
  }

  Future<void> _removeUnreferencedSegments(
    Directory directory,
    DerivedIndexManifest manifest,
  ) async {
    final retained = manifest.records.map((record) => record.fileName).toSet();
    await for (final entry in directory.list()) {
      if (entry is! File || !p.basename(entry.path).startsWith('g')) continue;
      if (!retained.contains(p.basename(entry.path))) await entry.delete();
    }
  }
}

final class DerivedBookIndexSession {
  DerivedBookIndexSession({
    required LazyBookSession source,
    DerivedBookIndexStore? store,
  }) : _source = source,
       _store = store ?? DerivedBookIndexStore();

  final LazyBookSession _source;
  final DerivedBookIndexStore _store;
  final StreamController<DerivedIndexSnapshot> _changes =
      StreamController<DerivedIndexSnapshot>.broadcast();
  DerivedIndexSnapshot? _snapshot;
  int _ownerGeneration = 0;
  bool _running = false;
  Future<void>? _activeRun;

  Stream<DerivedIndexSnapshot> get changes => _changes.stream;
  DerivedIndexSnapshot? get snapshot => _snapshot;
  bool get isRunning => _running;
  Future<void> get done => _activeRun ?? Future<void>.value();

  Future<DerivedIndexSnapshot> initialize() async {
    final index = _source.index;
    final readable = index.spine.where((item) => item.isLinear).length;
    final loaded = await _store.open(
      bookId: index.bookId,
      publicationFingerprint: index.publicationFingerprint,
      parserVersion: lazyParsedSectionParserVersion,
      totalSections: readable,
    );
    _snapshot = loaded;
    return loaded;
  }

  void start() {
    if (_running) return;
    _running = true;
    final owner = ++_ownerGeneration;
    _activeRun = _run(owner);
    unawaited(_activeRun);
  }

  Future<void> indexNextSection() async {
    final current = _snapshot ?? await initialize();
    final indexed = current.manifest.indexedSpineIndexes;
    final target = _source.index.spine
        .where((item) => item.isLinear && !indexed.contains(item.index))
        .firstOrNull;
    if (target == null) return;
    final owner = _ownerGeneration;
    final section = await _source.loadSectionForDerivedIndex(target.index);
    if (owner != _ownerGeneration) return;
    final segment = buildDerivedIndexSegment(section);
    final updated = await _store.publishSegment(
      expectedManifest: current.manifest,
      segment: segment,
    );
    if (owner != _ownerGeneration) return;
    _snapshot = updated;
    _changes.add(updated);
  }

  Future<void> _run(int owner) async {
    try {
      _snapshot ??= await initialize();
      while (owner == _ownerGeneration && !(_snapshot?.isComplete ?? true)) {
        await indexNextSection();
        if (owner != _ownerGeneration) return;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } on DerivedIndexGenerationRejected {
      // A newer owner/rebuild won publication. The next owner reloads it.
    } catch (error, stack) {
      if (!_changes.isClosed) _changes.addError(error, stack);
    } finally {
      if (owner == _ownerGeneration) _running = false;
    }
  }

  void cancel() {
    _ownerGeneration++;
    _running = false;
  }

  Future<void> dispose() async {
    cancel();
    await _changes.close();
  }
}

DerivedIndexSegment buildDerivedIndexSegment(ParsedSection section) {
  final groups = <String, List<BookChunk>>{};
  for (final chunk in section.chunks) {
    final text = authoritativeBookChunkText(chunk);
    if (text == null || text.isEmpty) continue;
    final id =
        chunk.logicalParagraphId ??
        '${section.identity.normalizedHref}#chunk-${chunk.index}';
    groups.putIfAbsent(id, () => <BookChunk>[]).add(chunk);
  }
  final paragraphs = <DerivedIndexedParagraph>[];
  for (final entry in groups.entries) {
    final chunks = entry.value
      ..sort(
        (a, b) => a.logicalParagraphStartOffset.compareTo(
          b.logicalParagraphStartOffset,
        ),
      );
    var length = 0;
    for (final chunk in chunks) {
      final chunkText = authoritativeBookChunkTextOrEmpty(chunk);
      final end = chunk.logicalParagraphId == null
          ? chunkText.length
          : (chunk.logicalParagraphEndOffset ??
                chunk.logicalParagraphStartOffset + chunkText.length);
      if (end > length) length = end;
    }
    final units = List<int>.filled(length, 0x20);
    final sourceSegments = <DerivedParagraphSourceSegment>[];
    for (final chunk in chunks) {
      final textUnits = authoritativeBookChunkTextOrEmpty(chunk).codeUnits;
      final paragraphStart = chunk.logicalParagraphId == null
          ? 0
          : chunk.logicalParagraphStartOffset;
      final paragraphEnd = (paragraphStart + textUnits.length).clamp(
        0,
        units.length,
      );
      for (var i = paragraphStart; i < paragraphEnd; i++) {
        units[i] = textUnits[i - paragraphStart];
      }
      sourceSegments.add(
        DerivedParagraphSourceSegment(
          localChunkIndex: chunk.index,
          paragraphStart: paragraphStart,
          paragraphEnd: paragraphEnd,
          chunkStart: 0,
        ),
      );
    }
    final text = String.fromCharCodes(units);
    final normalized = normalizeSearchTextWithSourceMap(text);
    paragraphs.add(
      DerivedIndexedParagraph(
        logicalParagraphId: entry.key,
        text: text,
        normalizedText: normalized.text,
        normalizedSourceStarts: normalized.sourceStarts,
        normalizedSourceEnds: normalized.sourceEnds,
        checksum: sha256.convert(utf8.encode(text)).toString(),
        contextBefore: text.substring(0, text.length.clamp(0, 48)),
        contextAfter: text.substring((text.length - 48).clamp(0, text.length)),
        sourceSegments: List.unmodifiable(sourceSegments),
        section: chunks.first.section,
        isHeading: chunks.first.isHeading,
      ),
    );
  }
  return DerivedIndexSegment(
    schemaVersion: derivedBookIndexSchemaVersion,
    normalizationVersion: derivedBookSearchNormalizationVersion,
    bookId: section.identity.bookId,
    publicationFingerprint: section.identity.publicationFingerprint,
    spineIndex: section.identity.spineIndex,
    href: section.identity.href,
    normalizedHref: section.identity.normalizedHref,
    sourceChecksum: section.identity.sourceChecksum,
    parserVersion: section.parserVersion,
    paragraphs: List.unmodifiable(paragraphs),
  );
}

ReaderUnicodeNormalizedText normalizeSearchTextWithSourceMap(String source) {
  final canonical = readerNormalizeSourceForComparison(source);
  final buffer = StringBuffer();
  final starts = <int>[];
  final ends = <int>[];
  var offset = 0;
  for (final rune in canonical.text.runes) {
    final runeText = String.fromCharCode(rune);
    final runeEnd = offset + runeText.length;
    var sourceStart = canonical.sourceStarts[offset];
    var sourceEnd = canonical.sourceEnds[offset];
    for (var i = offset + 1; i < runeEnd; i++) {
      if (canonical.sourceStarts[i] < sourceStart) {
        sourceStart = canonical.sourceStarts[i];
      }
      if (canonical.sourceEnds[i] > sourceEnd) {
        sourceEnd = canonical.sourceEnds[i];
      }
    }
    final folded = runeText.toLowerCase();
    buffer.write(folded);
    for (var i = 0; i < folded.length; i++) {
      starts.add(sourceStart);
      ends.add(sourceEnd);
    }
    offset = runeEnd;
  }
  return ReaderUnicodeNormalizedText(
    text: buffer.toString(),
    sourceStarts: List.unmodifiable(starts),
    sourceEnds: List.unmodifiable(ends),
  );
}

final class DerivedBookSearchService {
  const DerivedBookSearchService();

  List<DerivedSearchResult> search(
    DerivedIndexSnapshot snapshot,
    String query, {
    int maxResults = 100,
  }) {
    final normalizedQuery = normalizeSearchTextWithSourceMap(query.trim()).text;
    if (normalizedQuery.isEmpty) return const [];
    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final found = <DerivedSearchResult>[];
    final segmentEntries = snapshot.segments.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final segmentEntry in segmentEntries) {
      final segment = segmentEntry.value;
      for (final paragraph in segment.paragraphs) {
        var rank = 0;
        final normalizedMatches = <({int start, int end})>[];
        var searchFrom = 0;
        while (searchFrom <= paragraph.normalizedText.length) {
          final start = paragraph.normalizedText.indexOf(
            normalizedQuery,
            searchFrom,
          );
          if (start < 0) break;
          final end = start + normalizedQuery.length;
          normalizedMatches.add((start: start, end: end));
          searchFrom = end;
        }
        if (normalizedMatches.isEmpty &&
            tokens.length > 1 &&
            tokens.every(paragraph.normalizedText.contains)) {
          rank = 1;
          final start = paragraph.normalizedText.indexOf(tokens.first);
          normalizedMatches.add((
            start: start,
            end: start + tokens.first.length,
          ));
        }
        for (final normalizedMatch in normalizedMatches) {
          final normalizedStart = normalizedMatch.start;
          final normalizedEnd = normalizedMatch.end;
          final sourceStart = _minimum(
            paragraph.normalizedSourceStarts,
            normalizedStart,
            normalizedEnd,
          );
          final sourceEnd = _maximum(
            paragraph.normalizedSourceEnds,
            normalizedStart,
            normalizedEnd,
          );
          final sourceSegment = paragraph.sourceSegments.firstWhere(
            (item) =>
                sourceStart >= item.paragraphStart &&
                sourceStart < item.paragraphEnd,
            orElse: () => paragraph.sourceSegments.first,
          );
          final chunkOffset =
              sourceSegment.chunkStart +
              (sourceStart - sourceSegment.paragraphStart).clamp(
                0,
                sourceSegment.paragraphEnd - sourceSegment.paragraphStart,
              );
          final contextStart = (sourceStart - 50).clamp(
            0,
            paragraph.text.length,
          );
          final contextEnd = (sourceEnd + 50).clamp(0, paragraph.text.length);
          var snippet = paragraph.text.substring(contextStart, contextEnd);
          var snippetStart = sourceStart - contextStart;
          var snippetEnd = sourceEnd - contextStart;
          if (contextStart > 0) {
            snippet = '…$snippet';
            snippetStart++;
            snippetEnd++;
          }
          if (contextEnd < paragraph.text.length) snippet = '$snippet…';
          final exactText = paragraph.text.substring(sourceStart, sourceEnd);
          final locationContextEnd = sourceEnd.clamp(
            sourceStart,
            sourceSegment.paragraphEnd,
          );
          final beforeStart = (sourceStart - 48).clamp(
            0,
            paragraph.text.length,
          );
          final afterEnd = (sourceEnd + 48).clamp(0, paragraph.text.length);
          final location = StableBookLocation(
            bookId: segment.bookId,
            spineIndex: segment.spineIndex,
            href: segment.href,
            normalizedHref: segment.normalizedHref,
            sourceChecksum: segment.sourceChecksum,
            publicationFingerprint: segment.publicationFingerprint,
            sourceParserVersion: segment.parserVersion,
            internalSegmentId: paragraph.logicalParagraphId,
            localChunkIndex: sourceSegment.localChunkIndex,
            textOffset: chunkOffset,
            contextBefore: paragraph.text.substring(beforeStart, sourceStart),
            contextText: paragraph.text.substring(
              sourceStart,
              locationContextEnd,
            ),
            contextAfter: paragraph.text.substring(sourceEnd, afterEnd),
          );
          found.add(
            DerivedSearchResult(
              range: DerivedSourceRange(
                indexGeneration: snapshot.manifest.generation,
                location: location,
                logicalParagraphId: paragraph.logicalParagraphId,
                paragraphChecksum: paragraph.checksum,
                paragraphStart: sourceStart,
                paragraphEnd: sourceEnd,
                matchText: exactText,
              ),
              snippet: snippet,
              matchStart: snippetStart,
              matchEnd: snippetEnd,
              rank: rank,
            ),
          );
        }
      }
    }
    found.sort((a, b) {
      final rank = a.rank.compareTo(b.rank);
      if (rank != 0) return rank;
      final spine = a.range.location.spineIndex.compareTo(
        b.range.location.spineIndex,
      );
      if (spine != 0) return spine;
      final paragraph = a.range.logicalParagraphId.compareTo(
        b.range.logicalParagraphId,
      );
      if (paragraph != 0) return paragraph;
      return a.range.paragraphStart.compareTo(b.range.paragraphStart);
    });
    final deduplicated = <String, DerivedSearchResult>{};
    for (final result in found) {
      deduplicated.putIfAbsent(result.range.stableKey, () => result);
      if (deduplicated.length >= maxResults) break;
    }
    return List.unmodifiable(deduplicated.values);
  }
}

int _minimum(List<int> values, int start, int end) {
  var result = values[start];
  for (var i = start + 1; i < end; i++) {
    if (values[i] < result) result = values[i];
  }
  return result;
}

int _maximum(List<int> values, int start, int end) {
  var result = values[start];
  for (var i = start + 1; i < end; i++) {
    if (values[i] > result) result = values[i];
  }
  return result;
}
