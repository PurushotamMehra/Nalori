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

  group('mapFinalLayoutParagraphSelectionToTextRange', () {
    test('maps flattened cross-paragraph selection to display offsets', () {
      const text = 'First\n\nSecond\n\nThird';
      final segments = splitFinalLayoutParagraphSegments(text);

      final mapped = mapFinalLayoutParagraphSelectionToTextRange(
        segments: segments,
        selectionStart: 2,
        selectionEnd: 8,
      );

      expect(mapped, isNotNull);
      expect(mapped!.startOffset, 2);
      expect(mapped.endOffset, 10);
      expect(
        text.substring(mapped.startOffset, mapped.endOffset),
        'rst\n\nSec',
      );
    });

    test('maps a paragraph-boundary start to the next paragraph', () {
      const text = 'First\n\nSecond\n\nThird';
      final segments = splitFinalLayoutParagraphSegments(text);

      final mapped = mapFinalLayoutParagraphSelectionToTextRange(
        segments: segments,
        selectionStart: 5,
        selectionEnd: 11,
      );

      expect(mapped, isNotNull);
      expect(mapped!.startOffset, 7);
      expect(mapped.endOffset, 13);
      expect(text.substring(mapped.startOffset, mapped.endOffset), 'Second');
    });

    test('maps a paragraph-boundary end to the previous paragraph', () {
      const text = 'First\n\nSecond\n\nThird';
      final segments = splitFinalLayoutParagraphSegments(text);

      final mapped = mapFinalLayoutParagraphSelectionToTextRange(
        segments: segments,
        selectionStart: 0,
        selectionEnd: 5,
      );

      expect(mapped, isNotNull);
      expect(mapped!.startOffset, 0);
      expect(mapped.endOffset, 5);
      expect(text.substring(mapped.startOffset, mapped.endOffset), 'First');
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
