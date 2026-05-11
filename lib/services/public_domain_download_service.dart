import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/public_domain_book.dart';
import 'api_client.dart';
import 'book_import_service.dart';
import 'public_domain_book_service.dart';

typedef SaveBookBytes =
    Future<File> Function({required String fileName, required List<int> bytes});
typedef PublicDomainDownloadProgress =
    void Function(int receivedBytes, int? totalBytes);

class PublicDomainDownloadCancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class PublicDomainDownloadService {
  PublicDomainDownloadService({
    http.Client? client,
    SaveBookBytes? saveBookBytes,
  }) : _client = ApiClient(
         client: client,
         minIntervalByHost: const {
           'www.gutenberg.org': Duration(seconds: 1),
           'gutenberg.org': Duration(seconds: 1),
         },
         timeout: const Duration(seconds: 30),
       ),
       _saveBookBytes = saveBookBytes ?? BookImportService().saveBookBytes;

  final ApiClient _client;
  final SaveBookBytes _saveBookBytes;

  Future<File> downloadBook(
    PublicDomainBook book, {
    PublicDomainDownloadProgress? onProgress,
    PublicDomainDownloadCancelToken? cancelToken,
  }) async {
    final uri = Uri.parse(book.epubUrl);
    final request = http.Request('GET', uri);
    final response = await _client.send(request, headers: _headers);

    if (response.statusCode != 200) {
      throw PublicDomainDownloadException(
        'Book download failed (${response.statusCode})',
      );
    }

    final totalBytes = response.contentLength;
    final chunks = <List<int>>[];
    var receivedBytes = 0;
    await for (final chunk in response.stream) {
      if (cancelToken?.isCancelled == true) {
        throw const PublicDomainDownloadCancelledException();
      }
      chunks.add(chunk);
      receivedBytes += chunk.length;
      onProgress?.call(receivedBytes, totalBytes);
    }

    final bytes = <int>[];
    for (final chunk in chunks) {
      bytes.addAll(chunk);
    }
    if (!_looksLikeEpub(bytes)) {
      throw const PublicDomainDownloadException(
        'Downloaded file is not a valid EPUB',
      );
    }

    return _saveBookBytes(fileName: fileNameFor(book), bytes: bytes);
  }

  String fileNameFor(PublicDomainBook book) {
    final slug = _slugify(book.title);
    return 'gutenberg_${book.id}_$slug.epub';
  }

  bool _looksLikeEpub(List<int> bytes) {
    return bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  }

  String _slugify(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    if (slug.isEmpty) return 'book';
    return slug.length <= 48 ? slug : slug.substring(0, 48);
  }

  Map<String, String> get _headers => const {
    'Accept': 'application/epub+zip,application/octet-stream;q=0.9,*/*;q=0.1',
    'User-Agent': PublicDomainBookService.userAgent,
  };
}

class PublicDomainDownloadException implements Exception {
  final String message;

  const PublicDomainDownloadException(this.message);

  @override
  String toString() => message;
}

class PublicDomainDownloadCancelledException
    extends PublicDomainDownloadException {
  const PublicDomainDownloadCancelledException()
    : super('Book download cancelled');
}
