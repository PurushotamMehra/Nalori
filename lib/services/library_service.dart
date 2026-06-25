import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service for listing locally stored EPUB files.
class LibraryService {
  /// Returns all .epub files in the internal books directory.
  Future<List<File>> getLocalBooks() async {
    final booksDir = await _getBooksDirectory();

    if (!await booksDir.exists()) {
      return [];
    }

    final entities = booksDir.listSync();
    final epubs = entities
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.epub')
        .toList();

    // Sort alphabetically by filename.
    epubs.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    return epubs;
  }

  Future<File?> localBookForMetadata({
    required String bookId,
    String? managedFilePath,
  }) async {
    if (managedFilePath != null && managedFilePath.isNotEmpty) {
      final exact = File(managedFilePath);
      if (await _isReadableEpubFile(exact)) return exact;
    }

    final legacy = await deterministicManagedBookFile(bookId);
    if (await _isReadableEpubFile(legacy)) return legacy;
    return null;
  }

  Future<File> deterministicManagedBookFile(String bookId) async {
    final booksDir = await _getBooksDirectory();
    return File(p.join(booksDir.path, p.basename(bookId)));
  }

  Future<bool> isReadableEpubFile(File file) => _isReadableEpubFile(file);

  Future<bool> _isReadableEpubFile(File file) async {
    if (p.extension(file.path).toLowerCase() != '.epub') return false;
    try {
      final stat = await file.stat();
      return stat.type == FileSystemEntityType.file && stat.size > 0;
    } catch (_) {
      return false;
    }
  }

  /// Returns the internal books directory, creating it if necessary.
  Future<Directory> _getBooksDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDir.path, 'books'));
  }
}
