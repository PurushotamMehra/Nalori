import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import 'image_file_share_service.dart';

class QuoteCardShareService {
  final ImageFileShareService _shareService;

  QuoteCardShareService({ImageFileShareService? shareService})
    : _shareService = shareService ?? ImageFileShareService();

  Future<void> shareQuoteImage({
    required XFile file,
    required String bookTitle,
    String? title,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    final shareText = text ?? 'Quote from "$bookTitle"';
    final shareTitle = title ?? 'Quote card';
    return _shareService.shareImage(
      file: file,
      title: shareTitle,
      text: shareText,
      sharePositionOrigin: sharePositionOrigin,
    );
  }
}
