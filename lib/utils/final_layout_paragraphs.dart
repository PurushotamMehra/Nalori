import 'package:flutter/material.dart';

class FinalLayoutParagraphSegment {
  final String text;
  final int startOffset;

  const FinalLayoutParagraphSegment({
    required this.text,
    required this.startOffset,
  });
}

final RegExp finalLayoutParagraphSeparatorPattern = RegExp(
  r'(?:\r\n|\r|\n){2,}',
);

List<FinalLayoutParagraphSegment> splitFinalLayoutParagraphSegments(
  String text,
) {
  final matches = finalLayoutParagraphSeparatorPattern.allMatches(text);
  if (matches.isEmpty) {
    return [FinalLayoutParagraphSegment(text: text, startOffset: 0)];
  }

  final segments = <FinalLayoutParagraphSegment>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      segments.add(
        FinalLayoutParagraphSegment(
          text: text.substring(cursor, match.start),
          startOffset: cursor,
        ),
      );
    }
    cursor = match.end;
  }

  if (cursor < text.length) {
    segments.add(
      FinalLayoutParagraphSegment(
        text: text.substring(cursor),
        startOffset: cursor,
      ),
    );
  }

  return segments.isEmpty
      ? [FinalLayoutParagraphSegment(text: text, startOffset: 0)]
      : segments;
}

double finalLayoutParagraphGap({
  required double fontSize,
  required double lineHeight,
  required double paragraphSpacing,
}) {
  return fontSize * lineHeight * paragraphSpacing;
}

double finalLayoutParagraphGapForStyle({
  required TextStyle style,
  required double fallbackFontSize,
  required double fallbackLineHeight,
  required double paragraphSpacing,
}) {
  return finalLayoutParagraphGap(
    fontSize: style.fontSize ?? fallbackFontSize,
    lineHeight: style.height ?? fallbackLineHeight,
    paragraphSpacing: paragraphSpacing,
  );
}

double measureFinalLayoutParagraphTextHeight({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
  required TextAlign textAlign,
  required TextScaler textScaler,
  required StrutStyle? strutStyle,
  required double fallbackFontSize,
  required double fallbackLineHeight,
  required double paragraphSpacing,
}) {
  final segments = splitFinalLayoutParagraphSegments(text);
  if (segments.length == 1) {
    return _measureTextPainterHeight(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textDirection: textDirection,
      textAlign: textAlign,
      textScaler: textScaler,
      strutStyle: strutStyle,
    );
  }

  final paragraphGap = finalLayoutParagraphGapForStyle(
    style: style,
    fallbackFontSize: fallbackFontSize,
    fallbackLineHeight: fallbackLineHeight,
    paragraphSpacing: paragraphSpacing,
  );

  var height = paragraphGap * (segments.length - 1);
  for (final segment in segments) {
    height += _measureTextPainterHeight(
      text: segment.text,
      style: style,
      maxWidth: maxWidth,
      textDirection: textDirection,
      textAlign: textAlign,
      textScaler: textScaler,
      strutStyle: strutStyle,
    );
  }
  return height;
}

double _measureTextPainterHeight({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
  required TextAlign textAlign,
  required TextScaler textScaler,
  required StrutStyle? strutStyle,
}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textAlign: textAlign,
    textScaler: textScaler,
    strutStyle: strutStyle,
  );
  tp.layout(maxWidth: maxWidth);
  final height = tp.height;
  tp.dispose();
  return height;
}
