import 'package:flutter/material.dart';

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
        final minWidth = columnCount * 156.0;
        final tableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(minWidth, double.infinity)
            : minWidth;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
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
                  width: tableWidth.toDouble(),
                  child: Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(color: borderColor),
                      verticalInside: BorderSide(
                        color: borderColor.withValues(alpha: 0.72),
                      ),
                    ),
                    columnWidths: {
                      for (var i = 0; i < columnCount; i++)
                        i: const FlexColumnWidth(),
                    },
                    children: [
                      if (table.headers.isNotEmpty)
                        _buildRow(
                          _normalizedRow(table.headers, columnCount),
                          headerStyle,
                          headerFill,
                        ),
                      for (final row in table.rows)
                        _buildRow(
                          _normalizedRow(row, columnCount),
                          cellStyle,
                          Colors.transparent,
                        ),
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

  TableRow _buildRow(List<String> cells, TextStyle style, Color fillColor) {
    return TableRow(
      decoration: BoxDecoration(color: fillColor),
      children: [
        for (final cell in cells)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Text(
              cell,
              textAlign: TextAlign.left,
              softWrap: true,
              style: style,
            ),
          ),
      ],
    );
  }

  List<String> _normalizedRow(List<String> row, int columnCount) {
    if (row.length == columnCount) return row;
    if (row.length > columnCount) return row.sublist(0, columnCount);
    return [...row, for (var i = row.length; i < columnCount; i++) ''];
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
