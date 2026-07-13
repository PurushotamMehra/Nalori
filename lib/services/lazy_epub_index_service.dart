import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:epubx/epubx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const bool _lazyEpubDiagEnabled = bool.fromEnvironment('NALORI_EPUB_DIAG');
const String _lazyEpubDiagPrefix = 'NALORI_EPUB_DIAG';

void _lazyEpubDiagLog(String phase, Map<String, Object?> fields) {
  if (!_lazyEpubDiagEnabled) return;
  final parts = <String>[
    _lazyEpubDiagPrefix,
    'phase=$phase',
    'ts=${DateTime.now().toIso8601String()}',
    for (final entry in fields.entries)
      if (entry.value != null) '${entry.key}=${entry.value}',
  ];
  // ignore: avoid_print
  print(parts.join(' '));
}

class LazyEpubManifestItem {
  const LazyEpubManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.fullPath,
    required this.sizeBytes,
    required this.normalizedHref,
    this.properties,
  });

  final String id;
  final String href;
  final String mediaType;
  final String fullPath;
  final int? sizeBytes;
  final String normalizedHref;
  final String? properties;
}

class LazyEpubSpineItem {
  const LazyEpubSpineItem({
    required this.index,
    required this.idRef,
    required this.href,
    required this.mediaType,
    required this.fullPath,
    required this.isLinear,
    required this.sizeBytes,
    required this.sourceChecksum,
    required this.normalizedHref,
    required this.structuralWeight,
    required this.prefixWeight,
  });

  final int index;
  final String idRef;
  final String href;
  final String mediaType;
  final String fullPath;
  final bool isLinear;
  final int? sizeBytes;
  final String sourceChecksum;
  final String normalizedHref;
  final int structuralWeight;
  final int prefixWeight;
}

class LazyEpubChapter {
  const LazyEpubChapter({
    required this.title,
    required this.contentFileName,
    required this.anchor,
    required this.children,
    required this.normalizedHref,
    required this.spineIndex,
    required this.resolution,
  });

  final String title;
  final String contentFileName;
  final String? anchor;
  final List<LazyEpubChapter> children;
  final String normalizedHref;
  final int? spineIndex;
  final String resolution;
}

class LazyEpubIndex {
  const LazyEpubIndex({
    required this.filePath,
    required this.bookId,
    required this.title,
    required this.author,
    required this.authorList,
    required this.contentDirectoryPath,
    required this.manifest,
    required this.spine,
    required this.chapters,
    required this.coverHref,
    required this.schemaVersion,
    required this.publicationFingerprint,
    required this.fileSizeBytes,
    required this.fileModifiedMs,
    required this.normalizedHrefToManifestHref,
    required this.normalizedHrefToSpineIndex,
    required this.totalReadableWeight,
    required this.warnings,
  });

  final String filePath;
  final String bookId;
  final String title;
  final String author;
  final List<String> authorList;
  final String contentDirectoryPath;
  final Map<String, LazyEpubManifestItem> manifest;
  final List<LazyEpubSpineItem> spine;
  final List<LazyEpubChapter> chapters;
  final String? coverHref;
  final int schemaVersion;
  final String publicationFingerprint;
  final int fileSizeBytes;
  final int fileModifiedMs;
  final Map<String, String> normalizedHrefToManifestHref;
  final Map<String, int> normalizedHrefToSpineIndex;
  final int totalReadableWeight;
  final List<String> warnings;

  bool isValidFor(LazyEpubFileIdentity identity) =>
      schemaVersion == LazyEpubIndexService.schemaVersion &&
      fileSizeBytes == identity.sizeBytes &&
      fileModifiedMs == identity.modifiedMs &&
      publicationFingerprint == identity.publicationFingerprint;

  LazyEpubIndex withFilePath(String value) => LazyEpubIndex(
    filePath: value,
    bookId: bookId,
    title: title,
    author: author,
    authorList: authorList,
    contentDirectoryPath: contentDirectoryPath,
    manifest: manifest,
    spine: spine,
    chapters: chapters,
    coverHref: coverHref,
    schemaVersion: schemaVersion,
    publicationFingerprint: publicationFingerprint,
    fileSizeBytes: fileSizeBytes,
    fileModifiedMs: fileModifiedMs,
    normalizedHrefToManifestHref: normalizedHrefToManifestHref,
    normalizedHrefToSpineIndex: normalizedHrefToSpineIndex,
    totalReadableWeight: totalReadableWeight,
    warnings: warnings,
  );

  int? spineIndexForHref(String href) {
    final normalized = p.posix.normalize(
      Uri.decodeFull(href.split('#').first.split('?').first.trim()),
    );
    return normalizedHrefToSpineIndex[normalized];
  }
}

class LazyEpubSection {
  const LazyEpubSection({
    required this.spineIndex,
    required this.href,
    required this.fullPath,
    required this.mediaType,
    required this.html,
  });

  final int spineIndex;
  final String href;
  final String fullPath;
  final String mediaType;
  final String html;
}

class LazyEpubResource {
  const LazyEpubResource({
    required this.path,
    required this.mediaType,
    required this.bytes,
  });

  final String path;
  final String mediaType;
  final Uint8List bytes;
}

class LazyEpubBookHandle {
  LazyEpubBookHandle._({
    required EpubBookRef bookRef,
    required this.index,
    required Map<String, EpubContentFileRef> contentRefs,
  }) : _bookRef = bookRef,
       _contentRefs = contentRefs;

  final EpubBookRef _bookRef;
  final LazyEpubIndex index;
  final Map<String, EpubContentFileRef> _contentRefs;

  Future<LazyEpubSection> readSection(int spineIndex) async {
    if (spineIndex < 0 || spineIndex >= index.spine.length) {
      throw RangeError.index(spineIndex, index.spine, 'spineIndex');
    }
    final spineItem = index.spine[spineIndex];
    final ref = _contentRefs[spineItem.href];
    if (ref == null) {
      throw StateError(
        'EPUB spine item ${spineItem.href} is missing from content refs.',
      );
    }
    if (ref is! EpubTextContentFileRef) {
      throw StateError(
        'EPUB spine item ${spineItem.href} is not text content.',
      );
    }
    _lazyEpubDiagLog('lazy_section_resource_read_begin', {
      'book': index.bookId,
      'spineIndex': spineIndex,
      'href': spineItem.href,
      'fullPath': spineItem.fullPath,
    });
    final stopwatch = Stopwatch()..start();
    final html = await ref.readContentAsText();
    stopwatch.stop();
    _lazyEpubDiagLog('lazy_section_resource_read_end', {
      'book': index.bookId,
      'spineIndex': spineIndex,
      'href': spineItem.href,
      'fullPath': spineItem.fullPath,
      'htmlChars': html.length,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    return LazyEpubSection(
      spineIndex: spineIndex,
      href: spineItem.href,
      fullPath: spineItem.fullPath,
      mediaType: spineItem.mediaType,
      html: html,
    );
  }

  Future<LazyEpubResource> readResource(String hrefOrPath) async {
    final manifestItem =
        index.manifest[hrefOrPath] ??
        index.manifest.values
            .where((item) => item.fullPath == hrefOrPath)
            .firstOrNull;
    if (manifestItem == null) {
      throw StateError('EPUB resource $hrefOrPath is missing from manifest.');
    }
    final ref = _contentRefs[manifestItem.href];
    if (ref == null) {
      throw StateError(
        'EPUB resource ${manifestItem.href} is missing from content refs.',
      );
    }
    _lazyEpubDiagLog('lazy_resource_load_begin', {
      'book': index.bookId,
      'path': manifestItem.href,
      'mediaType': manifestItem.mediaType,
    });
    final stopwatch = Stopwatch()..start();
    final bytes = await ref.readContentAsBytes();
    stopwatch.stop();
    _lazyEpubDiagLog('lazy_resource_load_end', {
      'book': index.bookId,
      'path': manifestItem.href,
      'mediaType': manifestItem.mediaType,
      'bytes': bytes.length,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    return LazyEpubResource(
      path: manifestItem.href,
      mediaType: manifestItem.mediaType,
      bytes: Uint8List.fromList(bytes),
    );
  }

  Future<LazyEpubResource?> readCoverResource() async {
    final coverHref = index.coverHref;
    if (coverHref == null) return null;
    return readResource(coverHref);
  }

  Future<void> close() async {
    final archive = _bookRef.EpubArchive();
    final files = archive?.files;
    if (files == null) return;
    for (final file in files) {
      await file.close();
    }
  }
}

class LazyEpubIndexService {
  LazyEpubIndexService({
    LazyEpubIndexStore? store,
    void Function()? onIndexBuild,
  }) : _store = store ?? LazyEpubIndexStore(),
       _onIndexBuild = onIndexBuild;

  static const int schemaVersion = 1;

  final LazyEpubIndexStore _store;
  final void Function()? _onIndexBuild;

  Future<LazyEpubBookHandle> openBookIndex(File file) async {
    final stopwatch = Stopwatch()..start();
    _lazyEpubDiagLog('lazy_epub_index_open_begin', {
      'path': file.path,
      'book': p.basename(file.path),
    });
    final stat = await file.stat();
    final bytes = await file.readAsBytes();
    final identity = LazyEpubFileIdentity(
      sizeBytes: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      publicationFingerprint: sha256.convert(bytes).toString(),
    );
    final bookRef = await EpubReader.openBook(bytes);
    final contentRefs = _contentRefs(bookRef);
    LazyEpubIndex? cached;
    try {
      cached = await _store.load(p.basename(file.path));
    } catch (_) {
      // Persistence is an optimization; a valid live archive remains usable.
    }
    if (cached != null && cached.isValidFor(identity)) {
      final handle = LazyEpubBookHandle._(
        bookRef: bookRef,
        index: cached.withFilePath(file.path),
        contentRefs: contentRefs,
      );
      stopwatch.stop();
      _lazyEpubDiagLog('lazy_epub_index_cache_hit', {
        'path': file.path,
        'book': cached.bookId,
        'spineItems': cached.spine.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      return handle;
    }
    _onIndexBuild?.call();
    final schema = bookRef.Schema;
    final package = schema?.Package;
    if (schema == null || package == null) {
      throw StateError('EPUB schema is missing.');
    }

    final manifestItems = package.Manifest?.Items ?? const <EpubManifestItem>[];
    final byId = <String, LazyEpubManifestItem>{};
    final byHref = <String, LazyEpubManifestItem>{};
    final contentDirectoryPath = schema.ContentDirectoryPath ?? '';
    final archive = bookRef.EpubArchive();

    for (final item in manifestItems) {
      final id = item.Id;
      final href = item.Href;
      final mediaType = item.MediaType;
      if (id == null || href == null || mediaType == null) continue;
      final fullPath = _fullContentPath(contentDirectoryPath, href);
      final lazyItem = LazyEpubManifestItem(
        id: id,
        href: href,
        mediaType: mediaType,
        fullPath: fullPath,
        sizeBytes: _archiveEntrySize(archive, fullPath),
        normalizedHref: _normalizeHref(href),
        properties: item.Properties,
      );
      byId[id] = lazyItem;
      byHref[href] = lazyItem;
    }

    final spineRefs = package.Spine?.Items ?? const <EpubSpineItemRef>[];
    final spine = <LazyEpubSpineItem>[];
    var prefixWeight = 0;
    for (var i = 0; i < spineRefs.length; i++) {
      final idRef = spineRefs[i].IdRef;
      if (idRef == null) continue;
      final manifestItem = byId[idRef];
      if (manifestItem == null) continue;
      spine.add(
        LazyEpubSpineItem(
          index: spine.length,
          idRef: idRef,
          href: manifestItem.href,
          mediaType: manifestItem.mediaType,
          fullPath: manifestItem.fullPath,
          isLinear: spineRefs[i].IsLinear ?? true,
          sizeBytes: manifestItem.sizeBytes,
          sourceChecksum: _archiveEntryChecksum(
            archive,
            manifestItem.fullPath,
            manifestItem.sizeBytes,
          ),
          normalizedHref: manifestItem.normalizedHref,
          structuralWeight: spineRefs[i].IsLinear == false
              ? 0
              : (manifestItem.sizeBytes ?? 1).clamp(1, 1 << 31).toInt(),
          prefixWeight: prefixWeight,
        ),
      );
      if (spine.last.isLinear) {
        prefixWeight += spine.last.structuralWeight;
      }
    }

    final warnings = <String>[];
    List<EpubChapterRef> chapterRefs;
    try {
      chapterRefs = await bookRef.getChapters();
    } catch (_) {
      chapterRefs = const [];
      warnings.add('toc_unavailable');
    }
    if (chapterRefs.isEmpty && spine.isNotEmpty && warnings.isEmpty) {
      warnings.add('toc_empty');
    }
    final normalizedManifest = <String, String>{
      for (final item in byHref.values) item.normalizedHref: item.href,
    };
    final normalizedSpine = <String, int>{
      for (final item in spine) item.normalizedHref: item.index,
    };

    final handle = LazyEpubBookHandle._(
      bookRef: bookRef,
      index: LazyEpubIndex(
        filePath: file.path,
        bookId: p.basename(file.path),
        title: bookRef.Title ?? 'Unknown Title',
        author: bookRef.Author ?? '',
        authorList: (bookRef.AuthorList ?? const <String?>[])
            .whereType<String>()
            .toList(growable: false),
        contentDirectoryPath: contentDirectoryPath,
        manifest: byHref,
        spine: spine,
        chapters: _mapChapters(chapterRefs, normalizedSpine),
        coverHref: _findCoverHref(package, byId, byHref),
        schemaVersion: schemaVersion,
        publicationFingerprint: identity.publicationFingerprint,
        fileSizeBytes: identity.sizeBytes,
        fileModifiedMs: identity.modifiedMs,
        normalizedHrefToManifestHref: normalizedManifest,
        normalizedHrefToSpineIndex: normalizedSpine,
        totalReadableWeight: prefixWeight,
        warnings: warnings,
      ),
      contentRefs: contentRefs,
    );
    try {
      await _store.write(handle.index);
    } catch (_) {
      // Keep malformed or platform-unavailable storage from breaking opens.
    }
    stopwatch.stop();
    _lazyEpubDiagLog('lazy_epub_index_open_end', {
      'path': file.path,
      'book': p.basename(file.path),
      'bytes': bytes.length,
      'spineItems': spine.length,
      'manifestItems': byHref.length,
      'chapters': handle.index.chapters.length,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    return handle;
  }

  static Map<String, EpubContentFileRef> _contentRefs(EpubBookRef bookRef) {
    final refs = <String, EpubContentFileRef>{};
    final content = bookRef.Content;
    if (content == null) return refs;
    refs.addAll(content.Html ?? {});
    refs.addAll(content.Css ?? {});
    refs.addAll(content.Images ?? {});
    refs.addAll(content.Fonts ?? {});
    refs.addAll(content.AllFiles ?? {});
    return refs;
  }

  static String _fullContentPath(String contentDirectoryPath, String href) {
    final decodedHref = Uri.decodeFull(href);
    if (contentDirectoryPath.isEmpty) return decodedHref;
    return p.posix.normalize(p.posix.join(contentDirectoryPath, decodedHref));
  }

  static int? _archiveEntrySize(Archive? archive, String fullPath) {
    final files = archive?.files;
    if (files == null) return null;
    for (final file in files) {
      if (file.name == fullPath) {
        return file.size;
      }
    }
    return null;
  }

  static String _archiveEntryChecksum(
    Archive? archive,
    String fullPath,
    int? sizeBytes,
  ) {
    final files = archive?.files;
    if (files != null) {
      for (final file in files) {
        if (file.name == fullPath && file.crc32 != null) {
          return file.crc32!.toRadixString(16).padLeft(8, '0');
        }
      }
    }
    return '${fullPath.hashCode.toUnsigned(32).toRadixString(16)}_${sizeBytes ?? 'unknown'}';
  }

  static List<LazyEpubChapter> _mapChapters(
    List<EpubChapterRef> refs,
    Map<String, int> normalizedSpine,
  ) {
    return refs
        .map(
          (chapter) => LazyEpubChapter(
            title: chapter.Title ?? '',
            contentFileName: chapter.ContentFileName ?? '',
            anchor: chapter.Anchor,
            children: _mapChapters(
              chapter.SubChapters ?? const [],
              normalizedSpine,
            ),
            normalizedHref: _normalizeHref(chapter.ContentFileName ?? ''),
            spineIndex:
                normalizedSpine[_normalizeHref(chapter.ContentFileName ?? '')],
            resolution:
                normalizedSpine.containsKey(
                  _normalizeHref(chapter.ContentFileName ?? ''),
                )
                ? 'resolved'
                : 'unresolved',
          ),
        )
        .toList(growable: false);
  }

  static String _normalizeHref(String href) {
    final withoutFragment = href.split('#').first.split('?').first.trim();
    if (withoutFragment.isEmpty) return '';
    return p.posix.normalize(Uri.decodeFull(withoutFragment));
  }

  static String? _findCoverHref(
    EpubPackage package,
    Map<String, LazyEpubManifestItem> byId,
    Map<String, LazyEpubManifestItem> byHref,
  ) {
    final metas = package.Metadata?.MetaItems ?? const <EpubMetadataMeta>[];
    for (final meta in metas) {
      if ((meta.Name ?? '').toLowerCase() == 'cover') {
        final item = byId[meta.Content];
        if (item != null) return item.href;
      }
    }
    for (final item in byHref.values) {
      final properties = (item.properties ?? '').toLowerCase();
      if (properties.split(RegExp(r'\s+')).contains('cover-image')) {
        return item.href;
      }
    }
    return null;
  }
}

final class _LazyIndexFileCoordinator {
  Future<void> tail = Future<void>.value();
  final Map<String, int> generations = {};
  final Set<String> deleting = {};
  int globalGeneration = 0;

  int generation(String bookId) =>
      globalGeneration * 0x100000000 + (generations[bookId] ?? 0);

  Future<T> exclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    tail = tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    tail = tail.catchError((_) {});
    return completer.future;
  }
}

final class LazyEpubIndexStore {
  LazyEpubIndexStore({Directory? directory}) : _directory = directory;

  static final Map<String, _LazyIndexFileCoordinator> _coordinators = {};
  final Directory? _directory;

  String get _scopeKey =>
      _directory?.absolute.path ?? '__default_lazy_epub_index_store__';

  _LazyIndexFileCoordinator get _coordinator =>
      _coordinators.putIfAbsent(_scopeKey, _LazyIndexFileCoordinator.new);

  Future<Directory> _root() async {
    final value = _directory;
    if (value != null) {
      if (!await value.exists()) await value.create(recursive: true);
      return value;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(appDir.path, 'lazy_epub_indexes'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  Future<LazyEpubIndex?> load(String bookId) async {
    return _coordinator.exclusive(() => _loadUnlocked(bookId));
  }

  Future<LazyEpubIndex?> _loadUnlocked(String bookId) async {
    if (_coordinator.deleting.contains(bookId)) return null;
    final file = await _fileFor(bookId);
    if (!await file.exists()) return null;
    try {
      return _indexFromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
  }

  Future<void> write(LazyEpubIndex index) async {
    final generation = _coordinator.generation(index.bookId);
    await _coordinator.exclusive(() async {
      if (_coordinator.deleting.contains(index.bookId) ||
          generation != _coordinator.generation(index.bookId)) {
        return;
      }
      final file = await _fileFor(index.bookId);
      final temporary = File('${file.path}.tmp.$generation');
      await temporary.writeAsString(jsonEncode(_indexToJson(index)));
      if (_coordinator.deleting.contains(index.bookId) ||
          generation != _coordinator.generation(index.bookId)) {
        if (await temporary.exists()) await temporary.delete();
        return;
      }
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
  }

  Future<void> deleteForBook(String bookId) async {
    final coordinator = _coordinator;
    coordinator.generations[bookId] =
        (coordinator.generations[bookId] ?? 0) + 1;
    coordinator.deleting.add(bookId);
    await coordinator.exclusive(() async {
      try {
        final file = await _fileFor(bookId);
        if (await file.exists()) await file.delete();
      } finally {
        coordinator.deleting.remove(bookId);
      }
    });
  }

  Future<void> clearAll() async {
    final coordinator = _coordinator;
    coordinator.globalGeneration++;
    await coordinator.exclusive(() async {
      final root = await _root();
      if (await root.exists()) await root.delete(recursive: true);
    });
  }

  Future<File> _fileFor(String bookId) async => File(
    p.join((await _root()).path, '${sha256.convert(utf8.encode(bookId))}.json'),
  );
}

final class LazyEpubFileIdentity {
  const LazyEpubFileIdentity({
    required this.sizeBytes,
    required this.modifiedMs,
    required this.publicationFingerprint,
  });

  final int sizeBytes;
  final int modifiedMs;
  final String publicationFingerprint;
}

Map<String, dynamic> _indexToJson(LazyEpubIndex index) => {
  'schemaVersion': index.schemaVersion,
  'filePath': index.filePath,
  'bookId': index.bookId,
  'title': index.title,
  'author': index.author,
  'authorList': index.authorList,
  'contentDirectoryPath': index.contentDirectoryPath,
  'coverHref': index.coverHref,
  'publicationFingerprint': index.publicationFingerprint,
  'fileSizeBytes': index.fileSizeBytes,
  'fileModifiedMs': index.fileModifiedMs,
  'manifest': index.manifest.map(
    (key, value) => MapEntry(key, _manifestToJson(value)),
  ),
  'spine': index.spine.map(_spineToJson).toList(),
  'chapters': index.chapters.map(_chapterToJson).toList(),
  'normalizedHrefToManifestHref': index.normalizedHrefToManifestHref,
  'normalizedHrefToSpineIndex': index.normalizedHrefToSpineIndex,
  'totalReadableWeight': index.totalReadableWeight,
  'warnings': index.warnings,
};

LazyEpubIndex _indexFromJson(Map<String, dynamic> json) => LazyEpubIndex(
  filePath: json['filePath'] as String,
  bookId: json['bookId'] as String,
  title: json['title'] as String,
  author: json['author'] as String,
  authorList: (json['authorList'] as List).cast<String>(),
  contentDirectoryPath: json['contentDirectoryPath'] as String,
  manifest: (json['manifest'] as Map<String, dynamic>).map(
    (key, value) =>
        MapEntry(key, _manifestFromJson(value as Map<String, dynamic>)),
  ),
  spine: (json['spine'] as List)
      .map((value) => _spineFromJson(value as Map<String, dynamic>))
      .toList(),
  chapters: (json['chapters'] as List)
      .map((value) => _chapterFromJson(value as Map<String, dynamic>))
      .toList(),
  coverHref: json['coverHref'] as String?,
  schemaVersion: json['schemaVersion'] as int,
  publicationFingerprint: json['publicationFingerprint'] as String,
  fileSizeBytes: json['fileSizeBytes'] as int,
  fileModifiedMs: json['fileModifiedMs'] as int,
  normalizedHrefToManifestHref:
      (json['normalizedHrefToManifestHref'] as Map<String, dynamic>)
          .cast<String, String>(),
  normalizedHrefToSpineIndex:
      (json['normalizedHrefToSpineIndex'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as int),
      ),
  totalReadableWeight: json['totalReadableWeight'] as int,
  warnings: (json['warnings'] as List).cast<String>(),
);

Map<String, dynamic> _manifestToJson(LazyEpubManifestItem item) => {
  'id': item.id,
  'href': item.href,
  'mediaType': item.mediaType,
  'fullPath': item.fullPath,
  'sizeBytes': item.sizeBytes,
  'normalizedHref': item.normalizedHref,
  'properties': item.properties,
};

LazyEpubManifestItem _manifestFromJson(Map<String, dynamic> json) =>
    LazyEpubManifestItem(
      id: json['id'] as String,
      href: json['href'] as String,
      mediaType: json['mediaType'] as String,
      fullPath: json['fullPath'] as String,
      sizeBytes: json['sizeBytes'] as int?,
      normalizedHref: json['normalizedHref'] as String,
      properties: json['properties'] as String?,
    );

Map<String, dynamic> _spineToJson(LazyEpubSpineItem item) => {
  'index': item.index,
  'idRef': item.idRef,
  'href': item.href,
  'mediaType': item.mediaType,
  'fullPath': item.fullPath,
  'isLinear': item.isLinear,
  'sizeBytes': item.sizeBytes,
  'sourceChecksum': item.sourceChecksum,
  'normalizedHref': item.normalizedHref,
  'structuralWeight': item.structuralWeight,
  'prefixWeight': item.prefixWeight,
};

LazyEpubSpineItem _spineFromJson(Map<String, dynamic> json) =>
    LazyEpubSpineItem(
      index: json['index'] as int,
      idRef: json['idRef'] as String,
      href: json['href'] as String,
      mediaType: json['mediaType'] as String,
      fullPath: json['fullPath'] as String,
      isLinear: json['isLinear'] as bool,
      sizeBytes: json['sizeBytes'] as int?,
      sourceChecksum: json['sourceChecksum'] as String,
      normalizedHref: json['normalizedHref'] as String,
      structuralWeight: json['structuralWeight'] as int,
      prefixWeight: json['prefixWeight'] as int,
    );

Map<String, dynamic> _chapterToJson(LazyEpubChapter chapter) => {
  'title': chapter.title,
  'contentFileName': chapter.contentFileName,
  'anchor': chapter.anchor,
  'normalizedHref': chapter.normalizedHref,
  'spineIndex': chapter.spineIndex,
  'resolution': chapter.resolution,
  'children': chapter.children.map(_chapterToJson).toList(),
};

LazyEpubChapter _chapterFromJson(Map<String, dynamic> json) => LazyEpubChapter(
  title: json['title'] as String,
  contentFileName: json['contentFileName'] as String,
  anchor: json['anchor'] as String?,
  children: (json['children'] as List)
      .map((value) => _chapterFromJson(value as Map<String, dynamic>))
      .toList(),
  normalizedHref: json['normalizedHref'] as String,
  spineIndex: json['spineIndex'] as int?,
  resolution: json['resolution'] as String,
);
