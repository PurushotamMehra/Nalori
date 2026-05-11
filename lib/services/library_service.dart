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

  /// Returns the internal books directory, creating it if necessary.
  Future<Directory> _getBooksDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDir.path, 'books'));
  }
}
