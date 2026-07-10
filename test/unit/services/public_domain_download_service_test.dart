import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nalori/models/public_domain_book.dart';
import 'package:nalori/services/public_domain_download_service.dart';

void main() {
  group('PublicDomainDownloadService', () {
    test(
      'downloads EPUB bytes and saves them with a stable filename',
      () async {
        String? savedFileName;
        List<int>? savedBytes;

        final service = PublicDomainDownloadService(
          client: MockClient((request) async {
            expect(request.url.toString(), 'https://example.com/book.epub');
            expect(request.headers['User-Agent'], isNotEmpty);
            return http.Response.bytes(_validEpubBytes(), 200);
          }),
          saveBookBytes: ({required fileName, required bytes}) async {
            savedFileName = fileName;
            savedBytes = bytes;
            return File('/tmp/$fileName');
          },
        );

        final file = await service.downloadBook(_book);

        expect(savedFileName, 'gutenberg_1342_pride-and-prejudice.epub');
        expect(savedBytes, _validEpubBytes());
        expect(file.path, endsWith(savedFileName!));
      },
    );

    test('rejects missing EPUB URL before making a request', () async {
      var requested = false;
      final service = PublicDomainDownloadService(
        client: MockClient((request) async {
          requested = true;
          return http.Response.bytes(_validEpubBytes(), 200);
        }),
        saveBookBytes: ({required fileName, required bytes}) async {
          fail('Missing URL should not be saved');
        },
      );

      await expectLater(
        service.downloadBook(_book.copyWith(epubUrl: '')),
        throwsA(
          isA<PublicDomainDownloadException>().having(
            (error) => error.message,
            'message',
            'This book does not have a readable EPUB download available.',
          ),
        ),
      );
      expect(requested, isFalse);
    });

    test('download timeout reports friendly failure and does not save', () async {
      final service = PublicDomainDownloadService(
        client: MockClient((request) async {
          throw TimeoutException('slow');
        }),
        saveBookBytes: ({required fileName, required bytes}) async {
          fail('Failed download should not be saved');
        },
      );

      await expectLater(
        service.downloadBook(_book),
        throwsA(
          isA<PublicDomainDownloadException>().having(
            (error) => error.message,
            'message',
            "Couldn't download this EPUB. Please check your connection and try again.",
          ),
        ),
      );
    });

    test('non-200 response reports friendly failure and does not save', () async {
      final service = PublicDomainDownloadService(
        client: MockClient((request) async => http.Response('missing', 404)),
        saveBookBytes: ({required fileName, required bytes}) async {
          fail('Failed download should not be saved');
        },
      );

      await expectLater(
        service.downloadBook(_book),
        throwsA(
          isA<PublicDomainDownloadException>().having(
            (error) => error.message,
            'message',
            "Couldn't download this EPUB. Please check your connection and try again.",
          ),
        ),
      );
    });

    test('rejects downloaded content that is not a ZIP archive', () async {
      final service = PublicDomainDownloadService(
        client: MockClient((request) async {
          return http.Response.bytes([1, 2, 3, 4, 5], 200);
        }),
        saveBookBytes: ({required fileName, required bytes}) async {
          fail('Invalid EPUB bytes should not be saved');
        },
      );

      await expectLater(
        service.downloadBook(_book),
        throwsA(isA<PublicDomainDownloadException>()),
      );
    });

    test('rejects ZIP without EPUB container metadata', () async {
      final service = PublicDomainDownloadService(
        client: MockClient((request) async {
          return http.Response.bytes(_zipBytes({'not_epub.txt': 'nope'}), 200);
        }),
        saveBookBytes: ({required fileName, required bytes}) async {
          fail('Invalid EPUB bytes should not be saved');
        },
      );

      await expectLater(
        service.downloadBook(_book),
        throwsA(
          isA<PublicDomainDownloadException>().having(
            (error) => error.message,
            'message',
            'This file does not appear to be a valid EPUB.',
          ),
        ),
      );
    });

    test('storage failure reports import error', () async {
      final service = PublicDomainDownloadService(
        client: MockClient((request) async {
          return http.Response.bytes(_validEpubBytes(), 200);
        }),
        saveBookBytes: ({required fileName, required bytes}) async {
          throw const FileSystemException('disk full');
        },
      );

      await expectLater(
        service.downloadBook(_book),
        throwsA(
          isA<PublicDomainDownloadException>().having(
            (error) => error.message,
            'message',
            "Couldn't import this book. Please try again.",
          ),
        ),
      );
    });

    test('cancelled download does not request or save bytes', () async {
      final token = PublicDomainDownloadCancelToken()..cancel();
      var requested = false;
      final service = PublicDomainDownloadService(
        client: MockClient((request) async {
          requested = true;
          return http.Response.bytes(_validEpubBytes(), 200);
        }),
        saveBookBytes: ({required fileName, required bytes}) async {
          fail('Cancelled download should not be saved');
        },
      );

      await expectLater(
        service.downloadBook(_book, cancelToken: token),
        throwsA(isA<PublicDomainDownloadCancelledException>()),
      );
      expect(requested, isFalse);
    });
  });
}

List<int> _validEpubBytes() {
  return _zipBytes({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '<container/>',
  });
}

List<int> _zipBytes(Map<String, String> entries) {
  final bytes = <int>[];
  for (final entry in entries.entries) {
    final name = entry.key.codeUnits;
    final data = entry.value.codeUnits;
    bytes.addAll(_uint32(0x04034B50));
    bytes.addAll(_uint16(20));
    bytes.addAll(_uint16(0));
    bytes.addAll(_uint16(0));
    bytes.addAll(_uint16(0));
    bytes.addAll(_uint16(0));
    bytes.addAll(_uint32(0));
    bytes.addAll(_uint32(data.length));
    bytes.addAll(_uint32(data.length));
    bytes.addAll(_uint16(name.length));
    bytes.addAll(_uint16(0));
    bytes.addAll(name);
    bytes.addAll(data);
  }
  return bytes;
}

List<int> _uint16(int value) => [value & 0xff, (value >> 8) & 0xff];

List<int> _uint32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

const _book = PublicDomainBook(
  id: 1342,
  title: 'Pride and Prejudice',
  authors: ['Austen, Jane'],
  epubUrl: 'https://example.com/book.epub',
  downloadCount: 123,
);
