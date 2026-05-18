import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/book_chunk.dart';
import '../models/reading_settings.dart';
import '../utils/reader_content_parser.dart';

class ReaderTableBlockWidget extends StatelessWidget {
  final ReaderTableBlock table;
  final ReadingSettings settings;
  final TextStyle baseTextStyle;

  const ReaderTableBlockWidget({
    super.key,
    required this.table,
    required this.settings,
    required this.baseTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    final columnCount = table.columnCount;
    if (columnCount < 2) return const SizedBox.shrink();

    final fontSize = (baseTextStyle.fontSize ?? settings.fontSizeValue).clamp(
      13.0,
      18.0,
    );
    final cellStyle = baseTextStyle.copyWith(
      color: settings.readerTextColor,
      fontSize: fontSize,
      height: settings.lineHeight.clamp(1.2, 1.45),
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    final headerStyle = cellStyle.copyWith(fontWeight: FontWeight.w800);
    final borderColor = settings.readerMutedColor.withValues(
      alpha: settings.isDark ? 0.26 : 0.32,
    );
    final fillColor = Color.alphaBlend(
      settings.readerMutedColor.withValues(
        alpha: settings.isDark ? 0.08 : 0.06,
      ),
      settings.backgroundColor,
    );
    final headerFill = Color.alphaBlend(
      settings.readerAccentColor.withValues(
        alpha: settings.isDark ? 0.10 : 0.08,
      ),
      fillColor,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const outerHorizontalPadding = 4.0;
        final minWidth = columnCount * 96.0;
        final rawMaxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minWidth;
        final maxWidth = math.max(
          1.0,
          rawMaxWidth - outerHorizontalPadding * 2,
        );
        final cellRows = _expandedCellRows(columnCount);
        final readableColumnWidths = columnCount >= 3
            ? _readableColumnWidths(cellRows, columnCount, fontSize)
            : const <double>[];
        final readableTableWidth = readableColumnWidths.fold<double>(
          0,
          (sum, width) => sum + width,
        );
        final useHorizontalScroll =
            readableColumnWidths.isNotEmpty && readableTableWidth > maxWidth;
        final tableWidth = useHorizontalScroll
            ? readableTableWidth
            : maxWidth.clamp(minWidth, double.infinity);

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: outerHorizontalPadding,
            vertical: 8,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fillColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                key: const ValueKey('reader-table-horizontal-scroll'),
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  key: const ValueKey('reader-table-content-width'),
                  width: tableWidth.toDouble(),
                  child: Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(color: borderColor),
                      verticalInside: BorderSide(
                        color: borderColor.withValues(alpha: 0.72),
                      ),
                    ),
                    columnWidths: _columnWidths(
                      cellRows,
                      columnCount,
                      fixedWidths: useHorizontalScroll
                          ? readableColumnWidths
                          : null,
                    ),
                    children: [
                      if (table.continued)
                        TableRow(
                          decoration: BoxDecoration(color: headerFill),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              child: Text(
                                'Table continued',
                                style: headerStyle.copyWith(
                                  fontSize: fontSize - 1,
                                ),
                              ),
                            ),
                            for (var i = 1; i < columnCount; i++)
                              const SizedBox.shrink(),
                          ],
                        ),
                      for (final row in cellRows)
                        _buildCellRow(row, cellStyle, headerStyle, headerFill),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  TableRow _buildCellRow(
    List<BookTableCellData> cells,
    TextStyle cellStyle,
    TextStyle headerStyle,
    Color headerFill,
  ) {
    final isHeaderRow =
        cells.isNotEmpty && cells.every((cell) => cell.isHeader);
    return TableRow(
      decoration: BoxDecoration(
        color: isHeaderRow ? headerFill : Colors.transparent,
      ),
      children: [
        for (final cell in cells)
          Builder(
            builder: (context) {
              final softWrap = _shouldWrapCellText(cell.text);
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: cell.inlineStyles == null || cell.inlineStyles!.isEmpty
                    ? Text(
                        cell.text,
                        textAlign: TextAlign.left,
                        softWrap: softWrap,
                        overflow: softWrap
                            ? TextOverflow.clip
                            : TextOverflow.visible,
                        style: cell.isHeader ? headerStyle : cellStyle,
                      )
                    : RichText(
                        text: _cellSpan(cell, cellStyle, headerStyle),
                        textAlign: TextAlign.left,
                        softWrap: softWrap,
                        overflow: softWrap
                            ? TextOverflow.clip
                            : TextOverflow.visible,
                      ),
              );
            },
          ),
      ],
    );
  }

  bool _shouldWrapCellText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    if (RegExp(r'\s').hasMatch(trimmed)) return true;
    return trimmed.length > 24;
  }

  TextSpan _cellSpan(
    BookTableCellData cell,
    TextStyle cellStyle,
    TextStyle headerStyle,
  ) {
    final style = cell.isHeader ? headerStyle : cellStyle;
    final inlineStyles = cell.inlineStyles;
    if (inlineStyles == null || inlineStyles.isEmpty) {
      return TextSpan(text: cell.text, style: style);
    }

    final children = <TextSpan>[];
    var cursor = 0;
    for (final inlineStyle in inlineStyles) {
      final start = inlineStyle.start.clamp(0, cell.text.length);
      final end = inlineStyle.end.clamp(start, cell.text.length);
      if (cursor < start) {
        children.add(TextSpan(text: cell.text.substring(cursor, start)));
      }
      children.add(
        TextSpan(
          text: cell.text.substring(start, end),
          style: switch (inlineStyle.type) {
            InlineStyleType.bold => const TextStyle(
              fontWeight: FontWeight.w800,
            ),
            InlineStyleType.italic => const TextStyle(
              fontStyle: FontStyle.italic,
            ),
            InlineStyleType.boldItalic => const TextStyle(
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
            ),
          },
        ),
      );
      cursor = end;
    }
    if (cursor < cell.text.length) {
      children.add(TextSpan(text: cell.text.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }

  Map<int, TableColumnWidth> _columnWidths(
    List<List<BookTableCellData>> rows,
    int columnCount, {
    List<double>? fixedWidths,
  }) {
    if (fixedWidths != null && fixedWidths.length >= columnCount) {
      return {
        for (var i = 0; i < columnCount; i++)
          i: FixedColumnWidth(fixedWidths[i]),
      };
    }

    final flexes = table.columnFlexes;
    if (flexes != null && flexes.length >= columnCount) {
      return {
        for (var i = 0; i < columnCount; i++)
          i: i == 0 && columnCount == 2 && flexes[i] <= 14
              ? const IntrinsicColumnWidth()
              : FlexColumnWidth(flexes[i].clamp(6, 56).toDouble()),
      };
    }

    final maxLengths = List<int>.filled(columnCount, 0);
    for (final row in rows) {
      for (var i = 0; i < row.length && i < columnCount; i++) {
        final longestWord = row[i].text
            .split(RegExp(r'\s+'))
            .fold<int>(0, (max, word) => word.length > max ? word.length : max);
        final score = row[i].text.length.clamp(longestWord, 48);
        if (score > maxLengths[i]) maxLengths[i] = score;
      }
    }

    final firstColumnIsLabel =
        columnCount == 2 &&
        maxLengths.first <= 16 &&
        rows.every((row) => row.isEmpty || row.first.text.length <= 24);

    return {
      for (var i = 0; i < columnCount; i++)
        i: firstColumnIsLabel && i == 0
            ? const IntrinsicColumnWidth()
            : FlexColumnWidth(maxLengths[i].clamp(8, 48).toDouble()),
    };
  }

  List<double> _readableColumnWidths(
    List<List<BookTableCellData>> rows,
    int columnCount,
    double fontSize,
  ) {
    const horizontalCellPadding = 36.0;
    final charWidth = fontSize * 0.84;
    final widths = List<double>.filled(columnCount, 88);

    for (var column = 0; column < columnCount; column++) {
      var longestSafeToken = 0;
      var longestHeader = 0;
      var hasLongProse = false;

      for (final row in rows) {
        if (column >= row.length) continue;
        final cell = row[column];
        final text = cell.text.trim();
        if (text.isEmpty) continue;
        if (cell.isHeader && text.length > longestHeader) {
          longestHeader = text.length;
        }
        if (text.length >= 32 && RegExp(r'\s').hasMatch(text)) {
          hasLongProse = true;
        }
        for (final token in text.split(RegExp(r'\s+'))) {
          final segmentLength = _longestSafeTokenSegment(token);
          if (segmentLength > longestSafeToken) {
            longestSafeToken = segmentLength;
          }
        }
      }

      final tokenWidth =
          (longestSafeToken > longestHeader
                  ? longestSafeToken
                  : longestHeader) *
              charWidth +
          horizontalCellPadding;
      final proseFloor = hasLongProse ? 184.0 : 88.0;
      widths[column] = tokenWidth.clamp(proseFloor, 280).toDouble();
    }

    return widths;
  }

  int _longestSafeTokenSegment(String token) {
    var longest = 0;
    var current = 0;
    for (final rune in token.runes) {
      final char = String.fromCharCode(rune);
      if (char == '/' ||
          char == '_' ||
          char == '-' ||
          char == '.' ||
          char == '{' ||
          char == '}') {
        if (current > longest) longest = current;
        current = 0;
        continue;
      }
      current++;
    }
    return current > longest ? current : longest;
  }

  List<List<BookTableCellData>> _expandedCellRows(int columnCount) {
    final structured = table.cellRows;
    if (structured != null) {
      return [for (final row in structured) _expandRow(row, columnCount)];
    }

    return [
      if (table.headers.isNotEmpty)
        _expandRow([
          for (final header in table.headers)
            BookTableCellData(text: header, isHeader: true),
        ], columnCount),
      for (final row in table.rows)
        _expandRow([
          for (final cell in row) BookTableCellData(text: cell),
        ], columnCount),
    ];
  }

  List<BookTableCellData> _expandRow(
    List<BookTableCellData> row,
    int columnCount,
  ) {
    final expanded = <BookTableCellData>[];
    for (final cell in row) {
      expanded.add(cell);
      for (var i = 1; i < cell.colspan; i++) {
        expanded.add(const BookTableCellData(text: ''));
      }
    }
    if (expanded.length > columnCount) return expanded.sublist(0, columnCount);
    return [
      ...expanded,
      for (var i = expanded.length; i < columnCount; i++)
        const BookTableCellData(text: ''),
    ];
  }
}

enum DialogueTableVisualStyle { bookLikeCompact, bookLikeTable, card }

class DialogueTableBlockWidget extends StatelessWidget {
  final ReaderTableBlock table;
  final ReadingSettings settings;
  final TextStyle baseTextStyle;
  final DialogueTableVisualStyle visualStyle;

  const DialogueTableBlockWidget({
    super.key,
    required this.table,
    required this.settings,
    required this.baseTextStyle,
    this.visualStyle = DialogueTableVisualStyle.bookLikeTable,
  });

  @override
  Widget build(BuildContext context) {
    final rows = _dialogueRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    final fontSize = (baseTextStyle.fontSize ?? settings.fontSizeValue).clamp(
      14.0,
      20.0,
    );
    final textStyle = baseTextStyle.copyWith(
      color: settings.readerTextColor,
      fontSize: fontSize,
      height: settings.lineHeight.clamp(1.22, 1.50),
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    final labelStyle = textStyle.copyWith(
      color: settings.readerTextColor.withValues(
        alpha: settings.isDark ? 0.86 : 0.82,
      ),
      fontWeight: FontWeight.w800,
    );
    final ruleColor = settings.readerMutedColor.withValues(
      alpha: settings.isDark ? 0.16 : 0.20,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackRows = constraints.maxWidth < 390 || fontSize >= 18;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: stackRows
              ? _StackedDialogueTable(
                  rows: rows,
                  labelStyle: labelStyle,
                  textStyle: textStyle,
                  ruleColor: ruleColor,
                )
              : _InlineDialogueTable(
                  rows: rows,
                  labelStyle: labelStyle,
                  textStyle: textStyle,
                  ruleColor: ruleColor,
                ),
        );
      },
    );
  }

  List<({String speaker, String text})> _dialogueRows() {
    final structured = table.cellRows;
    if (structured != null) {
      return [
        for (final row in structured)
          if (row.length >= 2)
            (speaker: row[0].text.trim(), text: row[1].text.trim()),
      ];
    }
    return [
      for (final row in table.rows)
        if (row.length >= 2) (speaker: row[0].trim(), text: row[1].trim()),
    ];
  }
}

class _InlineDialogueTable extends StatelessWidget {
  final List<({String speaker, String text})> rows;
  final TextStyle labelStyle;
  final TextStyle textStyle;
  final Color ruleColor;

  const _InlineDialogueTable({
    required this.rows,
    required this.labelStyle,
    required this.textStyle,
    required this.ruleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FixedColumnWidth(14),
        2: FlexColumnWidth(),
      },
      children: [
        for (var i = 0; i < rows.length; i++)
          TableRow(
            decoration: BoxDecoration(
              border: i == rows.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: ruleColor.withValues(alpha: 0.55),
                      ),
                    ),
            ),
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: i == 0 ? 0 : 7,
                  bottom: i == rows.length - 1 ? 0 : 7,
                ),
                child: Text(
                  rows[i].speaker,
                  style: labelStyle,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: i == 0 ? 2 : 9,
                  bottom: i == rows.length - 1 ? 0 : 7,
                ),
                child: Center(
                  child: SizedBox(
                    width: 1,
                    height:
                        (textStyle.fontSize ?? 16) * (textStyle.height ?? 1.35),
                    child: ColoredBox(color: ruleColor),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  top: i == 0 ? 0 : 7,
                  bottom: i == rows.length - 1 ? 0 : 7,
                ),
                child: Text(rows[i].text, style: textStyle, softWrap: true),
              ),
            ],
          ),
      ],
    );
  }
}

class _StackedDialogueTable extends StatelessWidget {
  final List<({String speaker, String text})> rows;
  final TextStyle labelStyle;
  final TextStyle textStyle;
  final Color ruleColor;

  const _StackedDialogueTable({
    required this.rows,
    required this.labelStyle,
    required this.textStyle,
    required this.ruleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : 7,
              bottom: i == rows.length - 1 ? 0 : 7,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(rows[i].speaker, style: labelStyle, softWrap: true),
                const SizedBox(height: 3),
                Text(rows[i].text, style: textStyle, softWrap: true),
              ],
            ),
          ),
          if (i < rows.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              color: ruleColor.withValues(alpha: 0.55),
            ),
        ],
      ],
    );
  }
}

class ReaderPreformattedBlockWidget extends StatelessWidget {
  final String text;
  final ReadingSettings settings;
  final TextStyle baseTextStyle;

  const ReaderPreformattedBlockWidget({
    super.key,
    required this.text,
    required this.settings,
    required this.baseTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    final style = baseTextStyle.copyWith(
      color: settings.readerTextColor,
      fontFamily: 'monospace',
      fontSize: (baseTextStyle.fontSize ?? settings.fontSizeValue).clamp(
        12.0,
        16.0,
      ),
      height: 1.35,
    );
    final borderColor = settings.readerMutedColor.withValues(alpha: 0.28);
    final fillColor = Color.alphaBlend(
      settings.readerMutedColor.withValues(
        alpha: settings.isDark ? 0.08 : 0.06,
      ),
      settings.backgroundColor,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fillColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(10),
          child: Text(text, style: style, softWrap: false),
        ),
      ),
    );
  }
}
