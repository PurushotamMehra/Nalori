import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service for importing EPUB files into internal app storage.
class BookImportService {
  static const MethodChannel _androidImportChannel = MethodChannel(
    'book_import',
  );

  /// Opens the system file picker, lets the user select an .epub file,
  /// and copies it into the internal books directory.
  ///
  /// Returns the local [File] on success, or `null` if the user cancelled
  /// or an error occurred.
  Future<File?> importBook() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final sourcePath = await _androidImportChannel.invokeMethod<String>(
            'pickEpub',
          );
          if (sourcePath == null || sourcePath.isEmpty) return null;
          if (p.extension(sourcePath).toLowerCase() != '.epub') return null;
          return _copyIntoBooksDirectory(File(sourcePath));
        } on MissingPluginException {
          // Fall back to file_picker for tests or older native builds.
        }
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub'],
        dialogTitle: 'Select an EPUB book',
      );

      if (result == null || result.files.isEmpty) {
        return null; // User cancelled.
      }

      final pickedFile = result.files.single;
      final sourcePath = pickedFile.path;

      if (sourcePath == null) {
        return null; // No file path available.
      }

      if (p.extension(sourcePath).toLowerCase() != '.epub') {
        // Some platform pickers still expose an "all files" view. Keep the
        // app import pipeline EPUB-only even if the picker lets one through.
        return null;
      }

      return _copyIntoBooksDirectory(File(sourcePath));
    } catch (e) {
      // Log error only — no dialogs needed.
      // ignore: avoid_print
      print('BookImportService: import failed — $e');
      return null;
    }
  }

  Future<File> _copyIntoBooksDirectory(File sourceFile) async {
    // Get the internal books directory.
    final booksDir = await _getBooksDirectory();
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }

    // Build the destination path.
    final fileName = p.basename(sourceFile.path);
    final destPath = p.join(booksDir.path, fileName);

    // Prevent duplicate imports.
    final destFile = File(destPath);
    if (await destFile.exists()) {
      return destFile; // Already imported.
    }

    // Copy the file into internal storage.
    return sourceFile.copy(destPath);
  }

  Future<File> saveBookBytes({
    required String fileName,
    required List<int> bytes,
  }) async {
    final booksDir = await _getBooksDirectory();
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }

    final safeFileName = _safeEpubFileName(fileName);
    final destFile = File(p.join(booksDir.path, safeFileName));
    if (await destFile.exists()) {
      return destFile;
    }

    return destFile.writeAsBytes(bytes, flush: true);
  }

  /// Returns the internal books directory.
  Future<Directory> _getBooksDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDir.path, 'books'));
  }

  String _safeEpubFileName(String fileName) {
    final basename = p.basename(fileName);
    final withoutExtension = p.basenameWithoutExtension(basename);
    final safeBase = withoutExtension
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
        .trim();
    final normalizedBase = safeBase.isEmpty ? 'book' : safeBase;
    return '$normalizedBase.epub';
  }
}
