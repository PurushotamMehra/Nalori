import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nalori/services/open_library_metadata_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('OpenLibraryMetadataService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'cleans author-prefixed titles and returns confident matches',
      () async {
        final service = OpenLibraryMetadataService(
          client: MockClient((request) async {
            expect(request.url.path, '/search.json');
            expect(
              request.url.queryParameters['title'],
              'The Book of Five Rings',
            );
            expect(request.url.queryParameters['author'], 'Miyamoto Musashi');
            expect(
              request.headers['User-Agent'],
              contains('naloriapp@gmail.com'),
            );

            return http.Response(
              jsonEncode({
                'docs': [
                  {
                    'key': '/works/OL123W',
                    'title': 'The Book of Five Rings',
                    'author_name': ['Miyamoto Musashi'],
                    'cover_i': 987654,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final match = await service.findBestMatch(
          title: 'Miyamoto Musashi - The Book of Five Rings',
          author: 'Miyamoto Musashi',
        );

        expect(match, isNotNull);
        expect(match!.title, 'The Book of Five Rings');
        expect(match.author, 'Miyamoto Musashi');
        expect(match.workKey, '/works/OL123W');
        expect(match.coverId, 987654);
        expect(match.confidence, greaterThanOrEqualTo(0.9));
      },
    );

    test('rejects low-confidence search results', () async {
      final service = OpenLibraryMetadataService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'docs': [
                {
                  'key': '/works/OL999W',
                  'title': 'A Different Book',
                  'author_name': ['Someone Else'],
                },
              ],
            }),
            200,
          );
        }),
      );

      final match = await service.findBestMatch(
        title: 'The Book of Five Rings',
        author: 'Miyamoto Musashi',
      );

      expect(match, isNull);
    });

    test('fetches cover bytes only for image responses', () async {
      final service = OpenLibraryMetadataService(
        client: MockClient((request) async {
          expect(request.url.host, 'covers.openlibrary.org');
          expect(request.url.path, '/b/id/123-M.jpg');
          expect(request.url.queryParameters['default'], 'false');

          return http.Response.bytes(
            List<int>.filled(300, 1),
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );

      final bytes = await service.fetchCoverBytes(123);

      expect(bytes, isNotNull);
      expect(bytes, hasLength(300));
    });

    test('returns up to three cover candidates from matching docs', () async {
      var coverRequests = 0;
      final service = OpenLibraryMetadataService(
        client: MockClient((request) async {
          if (request.url.host == 'covers.openlibrary.org') {
            coverRequests += 1;
            expect(request.url.queryParameters['default'], 'false');
            return http.Response.bytes(
              List<int>.filled(300, 1),
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }

          expect(request.url.host, 'openlibrary.org');
          expect(request.url.path, '/search.json');
          expect(request.url.queryParameters['fields'], contains('cover_i'));
          expect(
            request.url.queryParameters['fields'],
            contains('cover_edition_key'),
          );

          return http.Response(
            jsonEncode({
              'docs': [
                {
                  'key': '/works/OL1W',
                  'title': 'Moby Dick',
                  'author_name': ['Herman Melville'],
                  'cover_i': 111,
                  'cover_edition_key': 'OL1M',
                },
                {
                  'key': '/works/OL2W',
                  'title': 'Moby-Dick; or, The Whale',
                  'author_name': ['Herman Melville'],
                  'cover_i': 222,
                },
              ],
            }),
            200,
          );
        }),
      );

      final candidates = await service.findCoverCandidates(
        title: 'Moby-Dick; or, The Whale',
        author: 'Herman Melville',
      );

      expect(candidates, hasLength(3));
      expect(candidates.first.source, 'open_library');
      expect(
        candidates.first.imageUrl,
        startsWith('https://covers.openlibrary.org'),
      );
      expect(candidates.first.imageUrl, contains('/b/id/'));
      expect(
        candidates.map((candidate) => candidate.imageUrl).toSet(),
        hasLength(3),
      );

      final bytes = await service.fetchCoverCandidateBytes(candidates.first);
      expect(bytes, isNotNull);
      expect(coverRequests, 3);
    });

    test(
      'drops cover candidates whose image endpoint fails validation',
      () async {
        final service = OpenLibraryMetadataService(
          client: MockClient((request) async {
            if (request.url.host == 'covers.openlibrary.org') {
              final isValidCover = request.url.path.contains('/222-');
              return http.Response.bytes(
                isValidCover ? List<int>.filled(300, 1) : [1, 2, 3],
                isValidCover ? 200 : 404,
                headers: {
                  'content-type': isValidCover ? 'image/jpeg' : 'text/plain',
                },
              );
            }

            return http.Response(
              jsonEncode({
                'docs': [
                  {
                    'key': '/works/OL1W',
                    'title': 'Moby Dick',
                    'author_name': ['Herman Melville'],
                    'cover_i': 111,
                  },
                  {
                    'key': '/works/OL2W',
                    'title': 'Moby Dick',
                    'author_name': ['Herman Melville'],
                    'cover_i': 222,
                  },
                ],
              }),
              200,
            );
          }),
        );

        final candidates = await service.findCoverCandidates(
          title: 'Moby Dick',
          author: 'Herman Melville',
        );

        expect(candidates, hasLength(1));
        expect(candidates.single.imageUrl, contains('/222-'));
      },
    );
  });
}
