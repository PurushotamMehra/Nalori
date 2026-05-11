import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class QuoteCardExportService {
  static const int outputWidth = 1080;

  Future<XFile> exportBoundary(
    GlobalKey boundaryKey, {
    String? fileName,
  }) async {
    final context = boundaryKey.currentContext;
    final boundary = context?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Quote card preview is not ready to export.');
    }

    await WidgetsBinding.instance.endOfFrame;

    final logicalWidth = boundary.size.width;
    if (logicalWidth <= 0) {
      throw StateError('Quote card preview has no exportable size.');
    }

    final image = await _captureImage(
      boundary,
      pixelRatio: outputWidth / logicalWidth,
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Could not encode quote card image.');
      }

      final tempDir = await getTemporaryDirectory();
      final safeName = _safeFileName(
        fileName ?? 'quote_card_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final file = File(p.join(tempDir.path, safeName));
      await file.writeAsBytes(data.buffer.asUint8List());
      return XFile(file.path, name: safeName, mimeType: 'image/png');
    } finally {
      image.dispose();
    }
  }

  String _safeFileName(String fileName) {
    final sanitized = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    if (sanitized.toLowerCase().endsWith('.png')) return sanitized;
    return '$sanitized.png';
  }

  Future<ui.Image> _captureImage(
    RenderRepaintBoundary boundary, {
    required double pixelRatio,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        return await boundary.toImage(pixelRatio: pixelRatio);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        await WidgetsBinding.instance.endOfFrame;
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }
}
