import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'frame_budgeted_range_scheduler.dart';

/// Resumable pure work. Each JSON string fragment is <=1024 UTF-16 units;
/// hashing/comparison consumes <=4096 units. No worker/message copies exist.
final class LazyValidationWork {
  LazyValidationWork({
    required this.task,
    required this.isCurrent,
    this.maxTemporaryBytes = 6 * 1024 * 1024,
    this.checkBudget,
  });
  final FrameBudgetedRangeTask task;
  final bool Function() isCurrent;
  final int maxTemporaryBytes;
  final void Function()? checkBudget;
  int temporaryBytes = 0, peakTemporaryBytes = 0, units = 0;
  int heldBytes = 0;
  int heldSources = 0;
  void reserveSource() {
    heldSources++;
    checkBudget?.call();
  }

  int get accountedBytes => temporaryBytes + heldBytes;
  void hold(int bytes) {
    heldBytes += bytes;
    reserve(temporaryBytes);
  }

  void releaseHeld(int bytes) {
    heldBytes -= bytes;
  }

  String phase = 'validation';
  void reserve(int bytes) {
    if (bytes + heldBytes > maxTemporaryBytes) {
      throw StateError('Validation buffer budget exceeded');
    }
    temporaryBytes = bytes;
    checkBudget?.call();
    if (bytes + heldBytes > peakTemporaryBytes) {
      peakTemporaryBytes = bytes + heldBytes;
    }
  }

  Future<void> step(String label) async {
    phase = label;
    units++;
    if (!isCurrent() ||
        !await task.checkpoint(sourceChunksProcessed: 1) ||
        !isCurrent()) {
      throw StateError('Cancelled or stale validation');
    }
  }

  Future<String> encode(Object? value) async {
    final output = StringBuffer();
    var tokens = 0, chars = 0;
    try {
      for (final token in _jsonTokens(value)) {
        reserve(2 * (output.length + token.length) + 64 * 1024);
        output.write(token);
        chars += token.length;
        if (++tokens >= 64 || chars >= 2048) {
          await step('encoding');
          tokens = chars = 0;
        }
      }
      await step('encoding');
      // Joining the bounded output string is an indivisible SDK operation.
      reserve(4 * output.length + 64 * 1024);
      return output.toString();
    } finally {
      temporaryBytes = 0;
    }
  }

  Future<String> digest(Object value) async {
    final result = _DigestSink();
    final sink = sha256.startChunkedConversion(result);
    try {
      if (value is Uint8List) {
        for (var i = 0; i < value.length; i += 16384) {
          reserve(64 * 1024);
          sink.add(
            Uint8List.sublistView(
              value,
              i,
              i + 16384 < value.length ? i + 16384 : value.length,
            ),
          );
          await step('hashing');
        }
      } else if (value is String) {
        for (final fragment in _fragments(value, 4096)) {
          reserve(64 * 1024);
          sink.add(utf8.encode(fragment));
          await step('hashing');
        }
      } else {
        var tokens = 0, chars = 0;
        for (final token in _jsonTokens(value)) {
          reserve(64 * 1024);
          sink.add(utf8.encode(token));
          chars += token.length;
          if (++tokens >= 64 || chars >= 2048) {
            await step('hashing');
            tokens = chars = 0;
          }
        }
      }
      await step('hashing');
      sink.close();
      return result.value!.toString();
    } finally {
      temporaryBytes = 0;
    }
  }

  Future<bool> equalCanonical(Object? a, Object? b) async {
    final left = _jsonTokens(a).iterator, right = _jsonTokens(b).iterator;
    var tokens = 0, chars = 0;
    while (left.moveNext()) {
      if (!right.moveNext() || left.current != right.current) return false;
      chars += left.current.length;
      if (++tokens >= 64 || chars >= 2048) {
        await step('comparison');
        tokens = chars = 0;
      }
    }
    await step('comparison');
    return !right.moveNext();
  }

  Future<int> utf8Length(String value) async {
    var bytes = 0;
    for (final fragment in _fragments(value, 4096)) {
      bytes += utf8.encode(fragment).length;
      await step('byte-count');
    }
    return bytes;
  }

  Future<bool> equal(String a, String b) async {
    if (a.length != b.length) return false;
    for (var start = 0; start < a.length; start += 4096) {
      final end = start + 4096 < a.length ? start + 4096 : a.length;
      if (a.substring(start, end) != b.substring(start, end)) return false;
      await step('comparison');
    }
    return true;
  }

  void finish() {
    temporaryBytes = 0;
    heldBytes = 0;
    heldSources = 0;
    task.finish();
  }
}

Iterable<String> _fragments(String s, int size) sync* {
  for (var start = 0; start < s.length;) {
    var end = start + size < s.length ? start + size : s.length;
    if (end < s.length &&
        s.codeUnitAt(end - 1) >= 0xd800 &&
        s.codeUnitAt(end - 1) <= 0xdbff &&
        s.codeUnitAt(end) >= 0xdc00 &&
        s.codeUnitAt(end) <= 0xdfff) {
      end--;
    }
    yield s.substring(start, end);
    start = end;
  }
}

Iterable<String> _jsonTokens(Object? value) sync* {
  if (value is String) {
    yield '"';
    for (final part in _fragments(value, 1024)) {
      final encoded = jsonEncode(part);
      yield encoded.substring(1, encoded.length - 1);
    }
    yield '"';
  } else if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    yield '{';
    for (var i = 0; i < keys.length; i++) {
      if (i != 0) yield ',';
      yield* _jsonTokens(keys[i]);
      yield ':';
      yield* _jsonTokens(value[keys[i]]);
    }
    yield '}';
  } else if (value is Iterable) {
    yield '[';
    var first = true;
    for (final element in value) {
      if (!first) yield ',';
      first = false;
      yield* _jsonTokens(element);
    }
    yield ']';
  } else {
    yield jsonEncode(value);
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
