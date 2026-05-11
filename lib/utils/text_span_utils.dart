import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TextSpanUtils {
  /// Builds a TextSpan that applies a specialized styling to paragraph breaks (`\n\n`)
  /// so that paragraph spacing can be controlled independently of line height.
  ///
  /// The returned TextSpan maintains the exact same string length as the input text,
  /// ensuring that any character-level highlights or selections remain accurate.
  static TextSpan buildSpacedTextSpan({
    required String text,
    required TextStyle baseStyle,
    required double paragraphSpacingMultiplier,
    GestureRecognizer? recognizer,
  }) {
    // Fast path if no paragraphs exist
    if (!text.contains('\n\n')) {
      return TextSpan(text: text, style: baseStyle, recognizer: recognizer);
    }

    final spans = <InlineSpan>[];
    int cursor = 0;

    // We search for `\n\n` and style the second `\n` to control the gap.
    final regex = RegExp(r'\n\n');
    final matches = regex.allMatches(text);

    // At very low multiplier (<= 0.15): replace the second \n with a
    // zero-width space so it takes up zero vertical space.
    // Otherwise: render the second \n with a scaled-down fontSize.
    final bool collapseGap = paragraphSpacingMultiplier <= 0.15;

    final double targetFontSize = baseStyle.fontSize ?? 16.0;

    final gapStyle = collapseGap
        ? baseStyle.copyWith(fontSize: 0.01, height: 0.01)
        : baseStyle.copyWith(
            fontSize: (targetFontSize * paragraphSpacingMultiplier).clamp(
              1.0,
              targetFontSize * 5.0,
            ),
            height: 1.0,
          );

    for (final match in matches) {
      // Add text before the `\n\n` including the first `\n`
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, match.start + 1),
            style: baseStyle,
            recognizer: recognizer,
          ),
        );
      } else if (match.start == cursor) {
        spans.add(
          TextSpan(text: '\n', style: baseStyle, recognizer: recognizer),
        );
      }

      if (collapseGap) {
        // Replace newline with zero-width space to eliminate the gap entirely
        spans.add(
          TextSpan(
            text:
                '\u200B', // zero-width space — same string length, zero visual height
            style: gapStyle,
            recognizer: recognizer,
          ),
        );
      } else {
        // Render the second `\n` with the scaled gap style
        spans.add(
          TextSpan(text: '\n', style: gapStyle, recognizer: recognizer),
        );
      }

      cursor = match.end;
    }

    // Add remaining text
    if (cursor < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(cursor),
          style: baseStyle,
          recognizer: recognizer,
        ),
      );
    }

    return TextSpan(children: spans);
  }
}
