import 'package:share_plus/share_plus.dart';

import 'image_file_save_service.dart';

class QuoteCardSaveService {
  final ImageFileSaveService _saveService;

  QuoteCardSaveService({ImageFileSaveService? saveService})
    : _saveService = saveService ?? ImageFileSaveService();

  Future<String> saveQuoteImage(XFile file) => _saveService.saveImage(file);
}
