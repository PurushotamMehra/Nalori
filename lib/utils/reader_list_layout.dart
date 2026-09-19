import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book_list_semantics.dart';

const double _listDepthStep = 12;
const double _maxNestedListIndent = 36;
const double _listMarkerGap = 8;

@immutable
class ReaderListLayoutMetrics {
  const ReaderListLayoutMetrics({
    required this.leadingIndent,
    required this.markerWidth,
    required this.markerGap,
  });

  final double leadingIndent;
  final double markerWidth;
  final double markerGap;

  double get bodyInset => leadingIndent + markerWidth + markerGap;
}

ReaderListLayoutMetrics resolveReaderListLayoutMetrics({
  required BookListSemantics semantics,
  required TextStyle style,
  required TextScaler textScaler,
}) {
  final markerPainter = TextPainter(
    text: TextSpan(text: bookListMarkerText(semantics), style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  final measuredMarkerWidth = markerPainter.width;
  markerPainter.dispose();

  return ReaderListLayoutMetrics(
    leadingIndent: math.min(
      _maxNestedListIndent,
      semantics.depth * _listDepthStep,
    ),
    markerWidth: measuredMarkerWidth.clamp(18.0, 52.0),
    markerGap: _listMarkerGap,
  );
}

double readerListGapBefore({
  required BookListDisplaySegment previous,
  required BookListDisplaySegment current,
  required double lineBoxHeight,
  required double paragraphSpacing,
}) {
  final sameBlock =
      previous.semantics.itemId == current.semantics.itemId &&
      previous.semantics.blockIndex == current.semantics.blockIndex;
  if (sameBlock) return 0;

  final sameItem = previous.semantics.itemId == current.semantics.itemId;
  final multiplier = sameItem ? 0.42 : 0.28;
  return lineBoxHeight * multiplier * paragraphSpacing;
}
