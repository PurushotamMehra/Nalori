import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    http.Client? client,
    Map<String, Duration> minIntervalByHost = const {},
    this.timeout = const Duration(seconds: 12),
    this.maxRetries = 1,
    bool? respectRateLimits,
  }) : _client = client ?? http.Client(),
       _minIntervalByHost = minIntervalByHost,
       _respectRateLimits = respectRateLimits ?? client == null;

  static const contactEmail = 'naloriapp@gmail.com';
  static const contactUrl =
      'https://gist.github.com/PurushotamMehra/1043d695f471272de8cdeb431afddf5e';
  static const userAgent = 'Nalori/1.0 (+$contactUrl; $contactEmail)';

  static final Map<String, Future<void>> _hostQueues = {};
  static final Map<String, DateTime> _lastRequestAt = {};

  final http.Client _client;
  final Map<String, Duration> _minIntervalByHost;
  final bool _respectRateLimits;
  final Duration timeout;
  final int maxRetries;
  final Map<String, Future<http.Response>> _inFlightGets = {};
  final _random = Random();

  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    bool dedupe = true,
    Duration? timeout,
    int? maxRetries,
  }) {
    final requestHeaders = _headers(headers);
    final requestTimeout = timeout ?? this.timeout;
    final requestMaxRetries = maxRetries ?? this.maxRetries;
    final key =
        '${uri.toString()}|${requestHeaders.entries.join('&')}|'
        '${requestTimeout.inMilliseconds}|$requestMaxRetries';
    if (dedupe) {
      final existing = _inFlightGets[key];
      if (existing != null) return existing;
    }

    final future = _sendWithRetry(() {
      return _withHostTurn(uri, () {
        return _client
            .get(uri, headers: requestHeaders)
            .timeout(requestTimeout);
      });
    }, maxRetries: requestMaxRetries);
    if (!dedupe) return future;

    _inFlightGets[key] = future;
    return future.whenComplete(() => _inFlightGets.remove(key));
  }

  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    Map<String, String>? headers,
  }) {
    request.headers.addAll(_headers(headers));
    return _withHostTurn(request.url, () {
      return _client.send(request).timeout(timeout);
    });
  }

  Map<String, String> _headers(Map<String, String>? headers) {
    return {'User-Agent': userAgent, if (headers != null) ...headers};
  }

  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() send, {
    required int maxRetries,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await send();
        final retryDelay = _retryDelayFor(response, attempt);
        if (retryDelay == null || attempt >= maxRetries) return response;
        await Future<void>.delayed(retryDelay);
      } on Object catch (error) {
        if (!_isRetryableTransportError(error) || attempt >= maxRetries) {
          rethrow;
        }
        await Future<void>.delayed(_jitteredBackoff(attempt));
      }
      attempt += 1;
    }
  }

  bool _isRetryableTransportError(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException;
  }

  Duration? _retryDelayFor(http.Response response, int attempt) {
    if (response.statusCode != 429 &&
        response.statusCode != 502 &&
        response.statusCode != 503 &&
        response.statusCode != 504) {
      return null;
    }

    final retryAfter = response.headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter.trim());
      if (seconds != null && seconds > 0) {
        return Duration(seconds: seconds.clamp(1, 30).toInt());
      }
    }
    return _jitteredBackoff(attempt);
  }

  Duration _jitteredBackoff(int attempt) {
    final baseMs = 350 * (1 << attempt.clamp(0, 3).toInt());
    return Duration(milliseconds: baseMs + _random.nextInt(250));
  }

  Future<T> _withHostTurn<T>(Uri uri, Future<T> Function() action) async {
    if (!_respectRateLimits) return action();

    final host = uri.host;
    final previous = _hostQueues[host] ?? Future<void>.value();
    final completer = Completer<void>();
    _hostQueues[host] = previous.catchError((_) {}).then((_) {
      return completer.future;
    });

    await previous.catchError((_) {});
    try {
      final interval = _minIntervalByHost[host] ?? Duration.zero;
      final lastRequestAt = _lastRequestAt[host];
      if (lastRequestAt != null && interval > Duration.zero) {
        final elapsed = DateTime.now().difference(lastRequestAt);
        if (elapsed < interval) {
          await Future<void>.delayed(interval - elapsed);
        }
      }
      return await action();
    } finally {
      _lastRequestAt[host] = DateTime.now();
      if (!completer.isCompleted) completer.complete();
    }
  }
}
