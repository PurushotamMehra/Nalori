import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TextPainter evaluates empty newlines correctly', () {
    const baseStyle = TextStyle(fontSize: 16.0, height: 1.0);
    const gapStyleLoose = TextStyle(fontSize: 16.0, height: 2.5);
    const gapStyleTight = TextStyle(fontSize: 16.0, height: 1.0);

    double measure(TextStyle style) {
      final span = TextSpan(
        children: [
          const TextSpan(text: 'Hello\n', style: baseStyle),
          TextSpan(text: '\n', style: style),
          const TextSpan(text: 'World', style: baseStyle),
        ],
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
      tp.layout();
      return tp.height;
    }

    final tight = measure(gapStyleTight);
    final loose = measure(gapStyleLoose);

    print('Tight: \$tight');
    print('Loose: \$loose');

    expect(loose > tight, true);
  });
}
