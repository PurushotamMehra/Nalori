import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nalori/services/api_client.dart';

void main() {
  group('ApiClient', () {
    test(
      'request-specific timeout does not change the default timeout',
      () async {
        final client = ApiClient(
          timeout: const Duration(milliseconds: 10),
          maxRetries: 0,
          client: MockClient((request) async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            return http.Response('ok', 200);
          }),
        );

        await expectLater(
          client.get(Uri.https('example.com', '/default')),
          throwsA(isA<TimeoutException>()),
        );

        final response = await client.get(
          Uri.https('example.com', '/override'),
          timeout: const Duration(milliseconds: 80),
        );

        expect(response.statusCode, 200);
      },
    );
  });
}
