import 'package:flutter/material.dart';

import '../models/reader_layout_contract.dart';
import '../models/reading_settings.dart';
import '../utils/reader_content_parser.dart';

class ReaderTableBlockWidget extends StatelessWidget {
  final ReaderTableBlock table;
  final ReadingSettings settings;
  final TextStyle baseTextStyle;
  final ReaderLayoutContract? layoutContract;
  final ResolvedReaderTableLayout? resolvedLayout;

  const ReaderTableBlockWidget({
    super.key,
    required this.table,
    required this.settings,
    required this.baseTextStyle,
    this.layoutContract,
    this.resolvedLayout,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = resolvedLayout;
    final contract = layoutContract;
    if (resolved != null && contract != null) {
      return _buildResolved(context, resolved, contract);
    }
    final columnCount = table.columnCount;
    if (columnCount < 2) return const SizedBox.shrink();

    final fontSize = (baseTextStyle.fontSize ?? settings.fontSizeValue).clamp(
      13.0,
      18.0,
    );
    final cellStyle = baseTextStyle.copyWith(
      color: settings.readerTextColor,
      fontSize: fontSize,
      height: settings.effectiveLineHeight.clamp(1.2, 1.45),
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

  Widget _buildResolved(
    BuildContext context,
    ResolvedReaderTableLayout resolved,
    ReaderLayoutContract contract,
  ) {
    final borderColor = settings.readerMutedColor.withValues(
      alpha: settings.isDark ? 0.26 : 0.32,
    );
    return SizedBox(
      key: const ValueKey('reader-resolved-table-layout'),
      height: resolved.totalHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: contract.structure.tableOuterVerticalPadding,
        ),
        child: SingleChildScrollView(
          key: const ValueKey('reader-table-horizontal-scroll'),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: resolved.horizontalScrollWidth,
            height: resolved.rowHeights.fold<double>(
              0,
              (sum, value) => sum + value,
            ),
            child: Stack(
              children: [
                for (final cell in resolved.cells)
                  Positioned(
                    left: resolved.columnWidths
                        .take(cell.column)
                        .fold<double>(0, (sum, value) => sum + value),
                    top: resolved.rowHeights
                        .take(cell.row)
                        .fold<double>(0, (sum, value) => sum + value),
                    width: cell.width,
                    height: cell.height,
                    child: _resolvedCell(cell, contract, borderColor),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resolvedCell(
    ResolvedReaderTableCell cell,
    ReaderLayoutContract contract,
    Color borderColor,
  ) {
    final role = cell.isHeader
        ? ReaderLayoutTextRole.tableHeader
        : ReaderLayoutTextRole.tableCell;
    final spec = contract.typography[role];
    return Container(
      width: cell.width,
      padding: EdgeInsets.symmetric(
        horizontal: contract.structure.tableCellHorizontalPadding,
        vertical: contract.structure.tableCellVerticalPadding,
      ),
      decoration: BoxDecoration(border: Border.all(color: borderColor)),
      child: Text(
        cell.text,
        textAlign: spec.textAlign,
        textDirection: spec.textDirection,
        textScaler: TextScaler.noScaling,
        softWrap: spec.softWrap,
        style: spec.toTextStyle().copyWith(color: settings.readerTextColor),
        strutStyle: spec.toStrutStyle(),
        textHeightBehavior: readerTextHeightBehavior,
      ),
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
              strutStyle: StrutStyle.fromTextStyle(
                style,
                forceStrutHeight: true,
              ),
              textHeightBehavior: readerTextHeightBehavior,
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
  final ReaderLayoutContract? layoutContract;
  final List<ResolvedReaderPreformattedLine>? resolvedLines;
  final double? resolvedTotalHeight;

  const ReaderPreformattedBlockWidget({
    super.key,
    required this.text,
    required this.settings,
    required this.baseTextStyle,
    this.layoutContract,
    this.resolvedLines,
    this.resolvedTotalHeight,
  });

  @override
  Widget build(BuildContext context) {
    final contract = layoutContract;
    if (contract != null &&
        resolvedLines != null &&
        resolvedTotalHeight != null) {
      final spec = contract.typography[ReaderLayoutTextRole.preformatted];
      return SizedBox(
        key: const ValueKey('reader-resolved-preformatted-layout'),
        height: resolvedTotalHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: contract.structure.preformattedOuterVerticalPadding,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: settings.readerMutedColor.withValues(alpha: 0.28),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.all(
                contract.structure.preformattedInnerPadding,
              ),
              child: Text(
                text,
                style: spec.toTextStyle().copyWith(
                  color: settings.readerTextColor,
                ),
                strutStyle: spec.toStrutStyle(),
                textDirection: spec.textDirection,
                textScaler: TextScaler.noScaling,
                softWrap: false,
                textHeightBehavior: readerTextHeightBehavior,
              ),
            ),
          ),
        ),
      );
    }
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
