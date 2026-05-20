import 'package:flutter/material.dart';

class FinalLayoutParagraphSegment {
  final String text;
  final int startOffset;

  const FinalLayoutParagraphSegment({
    required this.text,
    required this.startOffset,
  });
}

class FinalLayoutParagraphSelection {
  final int startOffset;
  final int endOffset;

  const FinalLayoutParagraphSelection({
    required this.startOffset,
    required this.endOffset,
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

FinalLayoutParagraphSelection? mapFinalLayoutParagraphSelectionToTextRange({
  required List<FinalLayoutParagraphSegment> segments,
  required int selectionStart,
  required int selectionEnd,
}) {
  if (segments.isEmpty) return null;

  final start = selectionStart < selectionEnd ? selectionStart : selectionEnd;
  final end = selectionStart < selectionEnd ? selectionEnd : selectionStart;
  if (start == end) return null;

  final totalLength = segments.fold<int>(
    0,
    (sum, segment) => sum + segment.text.length,
  );
  final clampedStart = start.clamp(0, totalLength);
  final clampedEnd = end.clamp(0, totalLength);
  if (clampedStart >= clampedEnd) return null;

  final originalStart = _mapFlattenedOffsetToOriginalOffset(
    segments,
    clampedStart,
    preferPreviousSegment: false,
  );
  final originalEnd = _mapFlattenedOffsetToOriginalOffset(
    segments,
    clampedEnd,
    preferPreviousSegment: true,
  );
  if (originalStart == null || originalEnd == null) return null;
  if (originalStart >= originalEnd) return null;

  return FinalLayoutParagraphSelection(
    startOffset: originalStart,
    endOffset: originalEnd,
  );
}

int? _mapFlattenedOffsetToOriginalOffset(
  List<FinalLayoutParagraphSegment> segments,
  int flattenedOffset, {
  required bool preferPreviousSegment,
}) {
  var cursor = 0;
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    final nextCursor = cursor + segment.text.length;
    if (flattenedOffset < nextCursor) {
      return segment.startOffset + (flattenedOffset - cursor);
    }
    if (flattenedOffset == nextCursor) {
      if (preferPreviousSegment || i == segments.length - 1) {
        return segment.startOffset + segment.text.length;
      }
      return segments[i + 1].startOffset;
    }
    cursor = nextCursor;
  }

  final last = segments.last;
  if (flattenedOffset == cursor) {
    return last.startOffset + last.text.length;
  }
  return null;
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
