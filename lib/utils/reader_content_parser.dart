enum ReaderContentBlockType { paragraph, table, preformatted }

class ReaderContentBlock {
  final ReaderContentBlockType type;
  final String rawText;
  final int startOffset;
  final ReaderTableBlock? table;

  const ReaderContentBlock._({
    required this.type,
    required this.rawText,
    required this.startOffset,
    this.table,
  });

  const ReaderContentBlock.paragraph({
    required String rawText,
    required int startOffset,
  }) : this._(
         type: ReaderContentBlockType.paragraph,
         rawText: rawText,
         startOffset: startOffset,
       );

  const ReaderContentBlock.table({
    required String rawText,
    required int startOffset,
    required ReaderTableBlock table,
  }) : this._(
         type: ReaderContentBlockType.table,
         rawText: rawText,
         startOffset: startOffset,
         table: table,
       );

  const ReaderContentBlock.preformatted({
    required String rawText,
    required int startOffset,
  }) : this._(
         type: ReaderContentBlockType.preformatted,
         rawText: rawText,
         startOffset: startOffset,
       );
}

class ReaderTableBlock {
  final List<String> headers;
  final List<List<String>> rows;

  const ReaderTableBlock({required this.headers, required this.rows});

  int get columnCount {
    final rowCounts = rows.map((row) => row.length);
    return <int>[headers.length, ...rowCounts].fold(0, (a, b) => a > b ? a : b);
  }

  String get logicalText {
    return [
      if (headers.isNotEmpty) headers.join(' '),
      for (final row in rows) row.join(' '),
    ].join('\n');
  }
}

List<ReaderContentBlock> parseReaderContentBlocks(String text) {
  if (text.isEmpty) return const [];

  final lines = _splitLinesWithOffsets(text);
  final blocks = <ReaderContentBlock>[];
  var paragraphStartLine = 0;
  var i = 0;

  void flushParagraphBefore(int lineIndex) {
    if (paragraphStartLine >= lineIndex) return;
    final start = lines[paragraphStartLine].startOffset;
    final end = lines[lineIndex - 1].endOffset;
    final raw = text.substring(start, end);
    if (raw.trim().isNotEmpty) {
      blocks.add(
        ReaderContentBlock.paragraph(rawText: raw, startOffset: start),
      );
    }
  }

  while (i < lines.length) {
    final parsed = _parseTableAt(lines, i, text);
    if (parsed != null) {
      final forwardAttached = _attachFollowingTableBody(parsed, lines, i, text);
      if (forwardAttached != null) {
        flushParagraphBefore(i);
        blocks.add(forwardAttached.block);
        i = forwardAttached.nextLineIndex;
        paragraphStartLine = i;
        continue;
      }

      final attached = _attachPrecedingTableHeader(
        parsed,
        lines,
        paragraphStartLine,
        i,
        text,
      );
      flushParagraphBefore(attached.preambleStartLine);
      blocks.add(attached.block);
      i = parsed.nextLineIndex;
      paragraphStartLine = i;
      continue;
    }
    i++;
  }

  flushParagraphBefore(lines.length);

  final cleanedBlocks = _attachHeaderParagraphsToTables(blocks);

  if (cleanedBlocks.isEmpty) {
    return [ReaderContentBlock.paragraph(rawText: text, startOffset: 0)];
  }
  return cleanedBlocks;
}

bool containsReaderTable(String text) {
  return parseReaderContentBlocks(
    text,
  ).any((block) => block.type == ReaderContentBlockType.table);
}

String readerSpeedReadText(String text) {
  final blocks = parseReaderContentBlocks(text);
  if (!blocks.any((block) => block.type == ReaderContentBlockType.table)) {
    return text;
  }
  return blocks
      .map((block) {
        final table = block.table;
        return table == null ? block.rawText : table.logicalText;
      })
      .where((value) => value.trim().isNotEmpty)
      .join('\n\n');
}

List<ReaderContentBlock> _attachHeaderParagraphsToTables(
  List<ReaderContentBlock> blocks,
) {
  if (blocks.length < 2) return blocks;

  final merged = <ReaderContentBlock>[];
  var index = 0;
  while (index < blocks.length) {
    if (index + 1 < blocks.length &&
        blocks[index].type == ReaderContentBlockType.paragraph &&
        blocks[index + 1].type == ReaderContentBlockType.table) {
      final paragraph = blocks[index];
      final tableBlock = blocks[index + 1];
      final table = tableBlock.table;
      final headers = table == null
          ? null
          : _headerCellsFromPreambleParagraph(
              paragraph.rawText,
              table.columnCount,
            );

      if (headers != null && table != null) {
        merged.add(
          ReaderContentBlock.table(
            rawText: '${paragraph.rawText}\n${tableBlock.rawText}',
            startOffset: paragraph.startOffset,
            table: ReaderTableBlock(
              headers: headers,
              rows: [table.headers, ...table.rows],
            ),
          ),
        );
        index += 2;
        continue;
      }
    }

    merged.add(blocks[index]);
    index++;
  }

  return merged;
}

class _Line {
  final String text;
  final int startOffset;
  final int endOffset;

  const _Line(this.text, this.startOffset, this.endOffset);
}

class _ParsedTable {
  final ReaderContentBlock block;
  final int nextLineIndex;
  final bool hasExplicitHeader;

  const _ParsedTable(
    this.block,
    this.nextLineIndex, {
    required this.hasExplicitHeader,
  });
}

class _LogicalRow {
  final String text;
  final int startOffset;
  final int endOffset;

  const _LogicalRow(this.text, this.startOffset, this.endOffset);
}

List<_Line> _splitLinesWithOffsets(String text) {
  final lines = <_Line>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (code != 10 && code != 13) continue;

    lines.add(_Line(text.substring(start, i), start, i));
    if (code == 13 && i + 1 < text.length && text.codeUnitAt(i + 1) == 10) {
      i++;
    }
    start = i + 1;
  }
  if (start <= text.length) {
    lines.add(_Line(text.substring(start), start, text.length));
  }
  return lines;
}

_ParsedTable? _parseTableAt(List<_Line> lines, int startIndex, String source) {
  final line = lines[startIndex].text;
  if (line.trim().isEmpty) return null;

  return _parsePipeTableAt(lines, startIndex, source) ??
      _parseDelimitedTableAt(lines, startIndex, source, _tabCells) ??
      _parseDelimitedTableAt(lines, startIndex, source, _spacedCells) ??
      _parsePreformattedTableAt(lines, startIndex, source);
}

_ParsedTable? _parsePipeTableAt(
  List<_Line> lines,
  int startIndex,
  String source,
) {
  final logicalRows = <_LogicalRow>[];
  var hasSeparator = false;
  var i = startIndex;

  while (i < lines.length) {
    final raw = lines[i];
    final trimmed = raw.text.trim();
    if (trimmed.isEmpty) break;

    if (!_containsPipeDelimiter(trimmed) && !_isBareSeparatorLine(trimmed)) {
      break;
    }

    if (logicalRows.isNotEmpty && _isPipeContinuation(trimmed)) {
      final previous = logicalRows.removeLast();
      logicalRows.add(
        _LogicalRow(
          '${previous.text} $trimmed',
          previous.startOffset,
          raw.endOffset,
        ),
      );
      i++;
      continue;
    }

    if (!_containsPipeDelimiter(trimmed)) {
      hasSeparator = hasSeparator || _isBareSeparatorLine(trimmed);
      i++;
      continue;
    }

    logicalRows.add(_LogicalRow(raw.text, raw.startOffset, raw.endOffset));
    i++;
  }

  if (logicalRows.length < 2) return null;

  final parsedRows = <List<String>>[];
  final rowOffsets = <_LogicalRow>[];
  for (final row in logicalRows) {
    final cells = _pipeCells(row.text);
    if (cells == null) return null;
    parsedRows.add(cells);
    rowOffsets.add(row);
    if (_isSeparatorRow(cells)) hasSeparator = true;
  }

  return _buildDelimitedTable(
    parsedRows: parsedRows,
    rowOffsets: rowOffsets,
    source: source,
    nextLineIndex: i,
    hasSeparator: hasSeparator,
  );
}

_ParsedTable? _parseDelimitedTableAt(
  List<_Line> lines,
  int startIndex,
  String source,
  List<String>? Function(String line) split,
) {
  final parsedRows = <List<String>>[];
  final rowOffsets = <_LogicalRow>[];
  var hasSeparator = false;
  var i = startIndex;

  while (i < lines.length) {
    final raw = lines[i];
    if (raw.text.trim().isEmpty) break;

    final cells = split(raw.text);
    if (cells == null) break;

    parsedRows.add(cells);
    rowOffsets.add(_LogicalRow(raw.text, raw.startOffset, raw.endOffset));
    if (_isSeparatorRow(cells)) hasSeparator = true;
    i++;
  }

  return _buildDelimitedTable(
    parsedRows: parsedRows,
    rowOffsets: rowOffsets,
    source: source,
    nextLineIndex: i,
    hasSeparator: hasSeparator,
  );
}

_ParsedTable? _buildDelimitedTable({
  required List<List<String>> parsedRows,
  required List<_LogicalRow> rowOffsets,
  required String source,
  required int nextLineIndex,
  required bool hasSeparator,
}) {
  if (parsedRows.length < 2) return null;

  final nonSeparatorRows = parsedRows
      .where((row) => !_isSeparatorRow(row))
      .toList(growable: false);
  if (nonSeparatorRows.length < 2) return null;

  final separatorIndex = parsedRows.indexWhere(_isSeparatorRow);
  final List<String> headers;
  final List<List<String>> rows;
  final columnCount = separatorIndex > 0
      ? parsedRows[separatorIndex - 1].length
      : nonSeparatorRows.first.length;

  if (columnCount < 2) return null;

  final consistentRows = nonSeparatorRows
      .where((row) => row.length >= 2 && (columnCount - row.length).abs() <= 1)
      .length;
  if (consistentRows < 2) return null;
  if (!hasSeparator && consistentRows < 3) return null;

  if (separatorIndex > 0) {
    headers = _normalizeCells(parsedRows[separatorIndex - 1], columnCount);
    rows = [
      for (
        var rowIndex = separatorIndex + 1;
        rowIndex < parsedRows.length;
        rowIndex++
      )
        if (!_isSeparatorRow(parsedRows[rowIndex]))
          _normalizeCells(parsedRows[rowIndex], columnCount),
    ];
  } else {
    headers = _normalizeCells(nonSeparatorRows.first, columnCount);
    rows = [
      for (final row in nonSeparatorRows.skip(1))
        _normalizeCells(row, columnCount),
    ];
  }

  if (headers.length < 2 || rows.isEmpty) return null;

  final start = rowOffsets.first.startOffset;
  final end = rowOffsets.last.endOffset;
  final rawText = source.substring(start, end);

  return _ParsedTable(
    ReaderContentBlock.table(
      rawText: rawText,
      startOffset: start,
      table: ReaderTableBlock(headers: headers, rows: rows),
    ),
    nextLineIndex,
    hasExplicitHeader: separatorIndex > 0,
  );
}

({ReaderContentBlock block, int preambleStartLine}) _attachPrecedingTableHeader(
  _ParsedTable parsed,
  List<_Line> lines,
  int paragraphStartLine,
  int tableStartLine,
  String source,
) {
  final table = parsed.block.table;
  if (table == null || parsed.hasExplicitHeader) {
    return (block: parsed.block, preambleStartLine: tableStartLine);
  }

  final preamble = _trailingTablePreamble(
    lines,
    paragraphStartLine,
    tableStartLine,
  );
  if (preamble == null || preamble.headers.length != table.columnCount) {
    return (block: parsed.block, preambleStartLine: tableStartLine);
  }

  final startOffset = lines[preamble.startLine].startOffset;
  final endOffset = parsed.block.startOffset + parsed.block.rawText.length;
  final adjustedTable = ReaderTableBlock(
    headers: preamble.headers,
    rows: [table.headers, ...table.rows],
  );

  return (
    block: ReaderContentBlock.table(
      rawText: source.substring(startOffset, endOffset),
      startOffset: startOffset,
      table: adjustedTable,
    ),
    preambleStartLine: preamble.startLine,
  );
}

({ReaderContentBlock block, int nextLineIndex})? _attachFollowingTableBody(
  _ParsedTable parsed,
  List<_Line> lines,
  int preambleStartLine,
  String source,
) {
  if (parsed.block.type != ReaderContentBlockType.preformatted) return null;

  final preamble = _trailingTablePreamble(
    lines,
    preambleStartLine,
    parsed.nextLineIndex,
  );
  if (preamble == null) return null;

  var bodyStartLine = parsed.nextLineIndex;
  while (bodyStartLine < lines.length &&
      lines[bodyStartLine].text.trim().isEmpty) {
    bodyStartLine++;
  }
  if (bodyStartLine >= lines.length) return null;

  final bodyParsed = _parseTableAt(lines, bodyStartLine, source);
  final bodyTable = bodyParsed?.block.table;
  if (bodyParsed == null ||
      bodyTable == null ||
      bodyParsed.hasExplicitHeader ||
      preamble.headers.length != bodyTable.columnCount) {
    return null;
  }

  final startOffset = lines[preamble.startLine].startOffset;
  final endOffset =
      bodyParsed.block.startOffset + bodyParsed.block.rawText.length;
  return (
    block: ReaderContentBlock.table(
      rawText: source.substring(startOffset, endOffset),
      startOffset: startOffset,
      table: ReaderTableBlock(
        headers: preamble.headers,
        rows: [bodyTable.headers, ...bodyTable.rows],
      ),
    ),
    nextLineIndex: bodyParsed.nextLineIndex,
  );
}

({List<String> headers, int startLine})? _trailingTablePreamble(
  List<_Line> lines,
  int paragraphStartLine,
  int tableStartLine,
) {
  var i = tableStartLine - 1;
  while (i >= paragraphStartLine && lines[i].text.trim().isEmpty) {
    i--;
  }
  while (i >= paragraphStartLine) {
    final trimmed = lines[i].text.trim();
    if (_isBareSeparatorLine(trimmed)) {
      i--;
      continue;
    }
    final cells = _pipeCells(trimmed);
    if (cells != null && cells.every(_isSeparatorCell)) {
      i--;
      continue;
    }
    break;
  }
  if (i < paragraphStartLine) return null;

  var headerText = lines[i].text;
  var headerStart = i;
  while (headerStart > paragraphStartLine) {
    final previous = lines[headerStart - 1].text.trim();
    if (!_containsPipeDelimiter(previous)) break;
    if (!_isPipeContinuation(headerText.trim())) break;
    headerStart--;
    headerText = '${lines[headerStart].text} $headerText';
  }

  final headers = _pipeCells(headerText);
  if (headers == null || headers.length < 2) return null;
  return (headers: headers, startLine: headerStart);
}

List<String>? _headerCellsFromPreambleParagraph(
  String paragraph,
  int columnCount,
) {
  if (columnCount < 2) return null;

  final contentLines = paragraph
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .where((line) => !_isVisualSeparatorLine(line))
      .toList();
  if (contentLines.isEmpty) return null;

  final pipeCandidates = <String>[];
  final looseCells = <String>[];
  for (final line in contentLines) {
    if (_containsPipeDelimiter(line)) {
      pipeCandidates.add(line);
      continue;
    }
    if (_looksLikeHeaderToken(line)) {
      looseCells.add(_cleanHeaderToken(line));
    }
  }

  if (pipeCandidates.isNotEmpty) {
    final cells = _pipeCells(pipeCandidates.join(' '));
    final normalized = _normalizeHeaderCells(cells, columnCount);
    if (normalized != null) return normalized;
  }

  if (looseCells.length >= columnCount) {
    return looseCells.take(columnCount).toList();
  }

  if (contentLines.length == 1) {
    final spaced = _spacedHeaderCells(contentLines.single, columnCount);
    if (spaced != null) return spaced;
  }

  return null;
}

List<String>? _normalizeHeaderCells(List<String>? cells, int columnCount) {
  if (cells == null || cells.length < 2) return null;
  final cleaned = cells
      .map(_cleanHeaderToken)
      .where((cell) => cell.isNotEmpty)
      .toList();
  if (cleaned.length != columnCount) return null;
  if (!cleaned.every(_looksLikeHeaderToken)) return null;
  return cleaned;
}

List<String>? _spacedHeaderCells(String line, int columnCount) {
  final cells = line
      .split(RegExp(r'\s{2,}'))
      .map(_cleanHeaderToken)
      .where((cell) => cell.isNotEmpty)
      .toList();
  if (cells.length != columnCount) return null;
  if (!cells.every(_looksLikeHeaderToken)) return null;
  return cells;
}

bool _looksLikeHeaderToken(String value) {
  final cleaned = _cleanHeaderToken(value);
  if (cleaned.isEmpty || cleaned.length > 40) return false;
  if (_isVisualSeparatorLine(cleaned)) return false;
  return RegExp(r'[A-Za-z]').hasMatch(cleaned);
}

String _cleanHeaderToken(String value) {
  return value
      .replaceAll(RegExp(r'^[\s|│┃:]+'), '')
      .replaceAll(RegExp(r'[\s|│┃:]+$'), '')
      .trim();
}

bool _isVisualSeparatorLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return true;
  if (_isBareSeparatorLine(trimmed)) return true;

  var separatorLike = 0;
  var total = 0;
  for (final rune in trimmed.runes) {
    if (rune == 32 || rune == 9) continue;
    total++;
    if (_isHorizontalSeparatorRune(rune) ||
        _isPipeDelimiterRune(rune) ||
        rune == 43 || // +
        rune == 58) {
      separatorLike++;
    }
  }
  return total > 0 && separatorLike / total >= 0.75;
}

List<String>? _pipeCells(String line) {
  if (!_containsPipeDelimiter(line)) return null;
  var trimmed = _normalizePipeDelimiters(line).trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);

  final cells = trimmed
      .split('|')
      .map((cell) => cell.trim())
      .where((cell) => cell.isNotEmpty && cell != '|')
      .toList();
  if (cells.length < 2) return null;
  return cells;
}

List<String>? _tabCells(String line) {
  if (!line.contains('\t')) return null;
  final cells = line.split('\t').map((cell) => cell.trim()).toList();
  if (cells.length < 2) return null;
  return cells;
}

List<String>? _spacedCells(String line) {
  if (_containsPipeDelimiter(line)) return null;
  final trimmed = line.trim();
  if (!RegExp(r'\S\s{2,}\S').hasMatch(trimmed)) return null;
  final cells = trimmed
      .split(RegExp(r'\s{2,}'))
      .map((cell) => cell.trim())
      .toList();
  if (cells.length < 2) return null;
  return cells;
}

bool _isPipeContinuation(String trimmed) {
  return _startsWithPipeDelimiter(trimmed) && _pipeCount(trimmed) == 1;
}

bool _isBareSeparatorLine(String trimmed) {
  var separatorCount = 0;
  for (final rune in trimmed.runes) {
    if (rune == 32 || rune == 9) continue;
    if (!_isHorizontalSeparatorRune(rune)) return false;
    separatorCount++;
  }
  return separatorCount >= 3;
}

int _pipeCount(String text) {
  var count = 0;
  for (final rune in text.runes) {
    if (_isPipeDelimiterRune(rune)) count++;
  }
  return count;
}

bool _containsPipeDelimiter(String text) {
  return text.runes.any(_isPipeDelimiterRune);
}

bool _startsWithPipeDelimiter(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) return false;
  return _isPipeDelimiterRune(trimmed.runes.first);
}

String _normalizePipeDelimiters(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    buffer.writeCharCode(_isPipeDelimiterRune(rune) ? 124 : rune);
  }
  return buffer.toString();
}

bool _isPipeDelimiterRune(int rune) {
  return rune == 124 || // |
      rune == 0x2502 || // box drawings light vertical
      rune == 0x2503 || // box drawings heavy vertical
      rune == 0xFF5C || // fullwidth vertical line
      rune == 0xFFE8 || // halfwidth forms light vertical
      rune == 0x2223; // divides
}

bool _isHorizontalSeparatorRune(int rune) {
  return rune == 45 || // -
      rune == 95 || // _
      rune == 61 || // =
      rune == 0x2500 || // box drawings light horizontal
      rune == 0x2501 || // box drawings heavy horizontal
      rune == 0x2013 || // en dash
      rune == 0x2014; // em dash
}

_ParsedTable? _parsePreformattedTableAt(
  List<_Line> lines,
  int startIndex,
  String source,
) {
  var i = startIndex;
  var hasSeparator = false;
  final rawLines = <_Line>[];

  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.text.trim();
    if (trimmed.isEmpty) break;
    final looksTableLike =
        _containsPipeDelimiter(line.text) ||
        line.text.contains('\t') ||
        _isBareSeparatorLine(line.text);
    if (!looksTableLike) break;
    hasSeparator =
        hasSeparator ||
        _isBareSeparatorLine(line.text) ||
        _pipeCells(line.text)?.every(_isSeparatorCell) == true;
    rawLines.add(line);
    i++;
  }

  if (rawLines.length < 2 || !hasSeparator) return null;

  final start = rawLines.first.startOffset;
  final end = rawLines.last.endOffset;
  return _ParsedTable(
    ReaderContentBlock.preformatted(
      rawText: source.substring(start, end),
      startOffset: start,
    ),
    i,
    hasExplicitHeader: false,
  );
}

bool _isSeparatorRow(List<String> cells) {
  if (cells.length < 2) return false;
  return cells.every(_isSeparatorCell);
}

bool _isSeparatorCell(String cell) {
  final trimmed = cell.trim();
  if (trimmed.isEmpty) return false;

  var separatorCount = 0;
  for (final rune in trimmed.runes) {
    if (rune == 58 || rune == 32 || rune == 9) continue;
    if (!_isHorizontalSeparatorRune(rune)) return false;
    separatorCount++;
  }
  return separatorCount >= 3;
}

List<String> _normalizeCells(List<String> cells, int columnCount) {
  final normalized = cells.map((cell) => cell.trim()).toList();
  while (normalized.length < columnCount) {
    normalized.add('');
  }
  if (normalized.length > columnCount) {
    return normalized.sublist(0, columnCount - 1)
      ..add(normalized.sublist(columnCount - 1).join(' | '));
  }
  return normalized;
}
