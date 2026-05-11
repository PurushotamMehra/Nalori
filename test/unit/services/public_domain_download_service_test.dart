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
            return http.Response.bytes([0x50, 0x4B, 0x03, 0x04, 0x00], 200);
          }),
          saveBookBytes: ({required fileName, required bytes}) async {
            savedFileName = fileName;
            savedBytes = bytes;
            return File('/tmp/$fileName');
          },
        );

        final file = await service.downloadBook(_book);

        expect(savedFileName, 'gutenberg_1342_pride-and-prejudice.epub');
        expect(savedBytes, [0x50, 0x4B, 0x03, 0x04, 0x00]);
        expect(file.path, endsWith(savedFileName!));
      },
    );

    test('rejects downloaded content that is not an EPUB archive', () async {
      final service = PublicDomainDownloadService(
        client: MockClient((request) async {
          return http.Response.bytes([1, 2, 3, 4, 5], 200);
        }),
        saveBookBytes: ({required fileName, required bytes}) async {
          fail('Invalid EPUB bytes should not be saved');
        },
      );

      expect(
        () => service.downloadBook(_book),
        throwsA(isA<PublicDomainDownloadException>()),
      );
    });
  });
}

const _book = PublicDomainBook(
  id: 1342,
  title: 'Pride and Prejudice',
  authors: ['Austen, Jane'],
  epubUrl: 'https://example.com/book.epub',
  downloadCount: 123,
);
