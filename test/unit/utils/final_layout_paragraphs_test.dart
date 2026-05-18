import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/utils/final_layout_paragraphs.dart';

void main() {
  group('splitFinalLayoutParagraphSegments', () {
    test('splits final display paragraph separators with original offsets', () {
      const text = 'First\n\nSecond\n\nThird';

      final segments = splitFinalLayoutParagraphSegments(text);

      expect(segments.map((segment) => segment.text), [
        'First',
        'Second',
        'Third',
      ]);
      expect(segments.map((segment) => segment.startOffset), [0, 7, 15]);
    });

    test('does not split single newlines', () {
      const text = 'First\nSecond\nThird';

      final segments = splitFinalLayoutParagraphSegments(text);

      expect(segments, hasLength(1));
      expect(segments.single.text, text);
      expect(segments.single.startOffset, 0);
    });

    test('does not split long wrapped prose without paragraph separators', () {
      final text = List.filled(
        40,
        'Long wrapped prose remains one final layout paragraph.',
      ).join(' ');

      final segments = splitFinalLayoutParagraphSegments(text);

      expect(segments, hasLength(1));
      expect(segments.single.text, text);
    });
  });

  group('final layout paragraph measurement', () {
    test('uses the shared paragraph gap helper between measured segments', () {
      const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';
      const style = TextStyle(fontSize: 18, height: 1.2);
      const maxWidth = 600.0;
      const paragraphSpacing = 1.5;

      final paragraphGap = finalLayoutParagraphGapForStyle(
        style: style,
        fallbackFontSize: 16,
        fallbackLineHeight: 1,
        paragraphSpacing: paragraphSpacing,
      );
      final segments = splitFinalLayoutParagraphSegments(text);
      final segmentHeight = segments.fold<double>(
        0,
        (total, segment) =>
            total +
            measureFinalLayoutParagraphTextHeight(
              text: segment.text,
              style: style,
              maxWidth: maxWidth,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              textScaler: TextScaler.noScaling,
              strutStyle: null,
              fallbackFontSize: 16,
              fallbackLineHeight: 1,
              paragraphSpacing: paragraphSpacing,
            ),
      );

      final measured = measureFinalLayoutParagraphTextHeight(
        text: text,
        style: style,
        maxWidth: maxWidth,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.start,
        textScaler: TextScaler.noScaling,
        strutStyle: null,
        fallbackFontSize: 16,
        fallbackLineHeight: 1,
        paragraphSpacing: paragraphSpacing,
      );

      expect(measured, segmentHeight + paragraphGap * 2);
    });
  });
}
