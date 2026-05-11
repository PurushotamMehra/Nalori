import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ImageFileSaveService {
  static const MethodChannel _androidShareChannel = MethodChannel(
    'quote_card/share',
  );

  Future<String> saveImage(XFile file) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final savedPath = await _androidShareChannel.invokeMethod<String>(
          'saveImage',
          {'path': file.path, 'mimeType': file.mimeType ?? 'image/png'},
        );
        return savedPath ?? 'Photos';
      } on MissingPluginException {
        // Fall through to app-documents save for tests or older native builds.
      }
    }

    final directory = await getApplicationDocumentsDirectory();
    final savedFile = File(p.join(directory.path, file.name));
    await File(file.path).copy(savedFile.path);
    return savedFile.path;
  }
}
