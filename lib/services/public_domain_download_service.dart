import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    final uri = _downloadUriFor(book);
    if (cancelToken?.isCancelled == true) {
      throw const PublicDomainDownloadCancelledException();
    }

    final request = http.Request('GET', uri);
    final http.StreamedResponse response;
    try {
      response = await _client.send(request, headers: _headers);
    } on Object catch (error) {
      if (error is TimeoutException ||
          error is SocketException ||
          error is http.ClientException) {
        throw const PublicDomainDownloadException(
          "Couldn't download this EPUB. Please check your connection and try again.",
        );
      }
      rethrow;
    }

    if (response.statusCode != 200) {
      throw const PublicDomainDownloadException(
        "Couldn't download this EPUB. Please check your connection and try again.",
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
    if (cancelToken?.isCancelled == true) {
      throw const PublicDomainDownloadCancelledException();
    }

    final bytes = <int>[];
    for (final chunk in chunks) {
      bytes.addAll(chunk);
    }
    if (!_isValidEpub(bytes)) {
      throw const PublicDomainDownloadException(
        'This file does not appear to be a valid EPUB.',
      );
    }

    try {
      return await _saveBookBytes(fileName: fileNameFor(book), bytes: bytes);
    } catch (_) {
      throw const PublicDomainDownloadException(
        "Couldn't import this book. Please try again.",
      );
    }
  }

  String fileNameFor(PublicDomainBook book) {
    final slug = _slugify(book.title);
    return 'gutenberg_${book.id}_$slug.epub';
  }

  Uri _downloadUriFor(PublicDomainBook book) {
    final uri = Uri.tryParse(book.epubUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      throw const PublicDomainDownloadException(
        'This book does not have a readable EPUB download available.',
      );
    }
    return uri;
  }

  bool _isValidEpub(List<int> bytes) {
    try {
      if (bytes.length <= 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
        return false;
      }

      var hasContainer = false;
      var hasEpubMimeType = false;
      var offset = 0;
      while (offset + 30 <= bytes.length) {
        final signature = _readUint32(bytes, offset);
        if (signature != 0x04034B50) break;

        final compressionMethod = _readUint16(bytes, offset + 8);
        final compressedSize = _readUint32(bytes, offset + 18);
        final fileNameLength = _readUint16(bytes, offset + 26);
        final extraLength = _readUint16(bytes, offset + 28);
        final nameStart = offset + 30;
        final nameEnd = nameStart + fileNameLength;
        final dataStart = nameEnd + extraLength;
        final dataEnd = dataStart + compressedSize;
        if (nameEnd > bytes.length || dataStart > bytes.length) return false;

        final name = utf8.decode(bytes.sublist(nameStart, nameEnd));
        if (name == 'META-INF/container.xml') {
          hasContainer = true;
        }
        if (name == 'mimetype' &&
            compressionMethod == 0 &&
            dataEnd <= bytes.length) {
          final value = utf8.decode(bytes.sublist(dataStart, dataEnd)).trim();
          hasEpubMimeType = value == 'application/epub+zip';
        }
        if (hasContainer && hasEpubMimeType) return true;
        if (dataEnd > bytes.length) return false;
        offset = dataEnd;
      }

      return hasContainer && hasEpubMimeType;
    } catch (_) {
      return false;
    }
  }

  int _readUint16(List<int> bytes, int offset) {
    return ByteData.sublistView(
      Uint8List.fromList(bytes),
      offset,
      offset + 2,
    ).getUint16(0, Endian.little);
  }

  int _readUint32(List<int> bytes, int offset) {
    return ByteData.sublistView(
      Uint8List.fromList(bytes),
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
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
