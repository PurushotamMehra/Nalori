import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart';
import 'package:path/path.dart' as p;

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
    this.properties,
  });

  final String id;
  final String href;
  final String mediaType;
  final String fullPath;
  final int? sizeBytes;
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
  });

  final int index;
  final String idRef;
  final String href;
  final String mediaType;
  final String fullPath;
  final bool isLinear;
  final int? sizeBytes;
  final String sourceChecksum;
}

class LazyEpubChapter {
  const LazyEpubChapter({
    required this.title,
    required this.contentFileName,
    required this.anchor,
    required this.children,
  });

  final String title;
  final String contentFileName;
  final String? anchor;
  final List<LazyEpubChapter> children;
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
  const LazyEpubIndexService();

  Future<LazyEpubBookHandle> openBookIndex(File file) async {
    final stopwatch = Stopwatch()..start();
    _lazyEpubDiagLog('lazy_epub_index_open_begin', {
      'path': file.path,
      'book': p.basename(file.path),
    });
    final bytes = await file.readAsBytes();
    final bookRef = await EpubReader.openBook(bytes);
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
        properties: item.Properties,
      );
      byId[id] = lazyItem;
      byHref[href] = lazyItem;
    }

    final spineRefs = package.Spine?.Items ?? const <EpubSpineItemRef>[];
    final spine = <LazyEpubSpineItem>[];
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
        ),
      );
    }

    final chapterRefs = await bookRef.getChapters();
    final contentRefs = <String, EpubContentFileRef>{};
    final content = bookRef.Content;
    if (content != null) {
      contentRefs.addAll(content.Html ?? {});
      contentRefs.addAll(content.Css ?? {});
      contentRefs.addAll(content.Images ?? {});
      contentRefs.addAll(content.Fonts ?? {});
      contentRefs.addAll(content.AllFiles ?? {});
    }

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
        chapters: _mapChapters(chapterRefs),
        coverHref: _findCoverHref(package, byId, byHref),
      ),
      contentRefs: contentRefs,
    );
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

  static List<LazyEpubChapter> _mapChapters(List<EpubChapterRef> refs) {
    return refs
        .map(
          (chapter) => LazyEpubChapter(
            title: chapter.Title ?? '',
            contentFileName: chapter.ContentFileName ?? '',
            anchor: chapter.Anchor,
            children: _mapChapters(chapter.SubChapters ?? const []),
          ),
        )
        .toList(growable: false);
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
