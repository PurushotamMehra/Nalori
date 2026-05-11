import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class ImageFileShareService {
  static const MethodChannel _androidShareChannel = MethodChannel(
    'quote_card/share',
  );

  Future<void> shareImage({
    required XFile file,
    required String title,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _androidShareChannel.invokeMethod<void>('shareImage', {
          'path': file.path,
          'mimeType': file.mimeType ?? 'image/png',
          'title': title,
          'text': text ?? '',
        });
        return;
      } on MissingPluginException {
        // Fall back to share_plus for tests or older native builds.
      }
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [file.name],
        text: text,
        title: title,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
