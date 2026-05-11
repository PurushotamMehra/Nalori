import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class BookImageExportService {
  Future<XFile> exportImageBytes(
    Uint8List imageBytes, {
    required String fileStem,
  }) async {
    if (imageBytes.isEmpty) {
      throw StateError('Book image is empty.');
    }

    final detected = _detectImageFormat(imageBytes);
    final safeStem = _safeStem(fileStem);
    final fileName = '$safeStem.${detected.extension}';
    final tempDir = await getTemporaryDirectory();
    final file = File(p.join(tempDir.path, fileName));
    await file.writeAsBytes(imageBytes, flush: true);
    return XFile(file.path, name: fileName, mimeType: detected.mimeType);
  }

  String _safeStem(String fileStem) {
    final sanitized = fileStem
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (sanitized.isEmpty) {
      return 'book_image_${DateTime.now().millisecondsSinceEpoch}';
    }
    return sanitized;
  }

  _DetectedImageFormat _detectImageFormat(Uint8List bytes) {
    if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47])) {
      return const _DetectedImageFormat('png', 'image/png');
    }
    if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) {
      return const _DetectedImageFormat('jpg', 'image/jpeg');
    }
    if (_startsWithAscii(bytes, 'GIF87a') ||
        _startsWithAscii(bytes, 'GIF89a')) {
      return const _DetectedImageFormat('gif', 'image/gif');
    }
    if (_startsWithAscii(bytes, 'BM')) {
      return const _DetectedImageFormat('bmp', 'image/bmp');
    }
    if (bytes.length >= 12 &&
        _startsWithAscii(bytes, 'RIFF') &&
        _startsWithAscii(bytes.sublist(8), 'WEBP')) {
      return const _DetectedImageFormat('webp', 'image/webp');
    }
    return const _DetectedImageFormat('png', 'image/png');
  }

  bool _startsWith(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i += 1) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  bool _startsWithAscii(List<int> bytes, String text) {
    if (bytes.length < text.length) return false;
    for (var i = 0; i < text.length; i += 1) {
      if (bytes[i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }
}

class _DetectedImageFormat {
  final String extension;
  final String mimeType;

  const _DetectedImageFormat(this.extension, this.mimeType);
}
