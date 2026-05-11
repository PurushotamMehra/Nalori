import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/utils/reader_content_parser.dart';

void main() {
  group('parseReaderContentBlocks', () {
    test('detects and parses a simple markdown table', () {
      const text = '''
Field | Description | Type
--- | --- | ---
latitude | Latitude of a given location | decimal
longitude | Longitude of a given location | decimal''';

      final blocks = parseReaderContentBlocks(text);

      expect(blocks, hasLength(1));
      expect(blocks.single.type, ReaderContentBlockType.table);
      expect(blocks.single.table!.headers, ['Field', 'Description', 'Type']);
      expect(blocks.single.table!.rows, [
        ['latitude', 'Latitude of a given location', 'decimal'],
        ['longitude', 'Longitude of a given location', 'decimal'],
      ]);
      expect(blocks.single.table!.logicalText, isNot(contains('--- | ---')));
    });

    test('detects ASCII pipe table with separator row', () {
      const text = '''
API | Detail
--- | ---
GET /v1/businesses/{:id} | Return detailed information about a business
POST /v1/businesses | Add a business''';

      final table = parseReaderContentBlocks(text).single.table!;

      expect(table.headers, ['API', 'Detail']);
      expect(table.rows.first, [
        'GET /v1/businesses/{:id}',
        'Return detailed information about a business',
      ]);
    });

    test('joins wrapped pipe header cells into the table header row', () {
      const text = '''
Field | Description
| Type
--- | ---
| ---
latitude | Latitude of a given location | decimal''';

      final blocks = parseReaderContentBlocks(text);
      final table = blocks.single.table!;

      expect(table.headers, ['Field', 'Description', 'Type']);
      expect(table.rows.single, [
        'latitude',
        'Latitude of a given location',
        'decimal',
      ]);
      expect(blocks.single.rawText, startsWith('Field | Description'));
    });

    test('does not create delimiter pipe cells', () {
      const text = '''
API | Detail
--- | ---
GET /v1/businesses/{:id} | Return detailed information about a business
POST /v1/businesses | Add a business''';

      final table = parseReaderContentBlocks(text).single.table!;
      final allCells = [...table.headers, for (final row in table.rows) ...row];

      expect(table.columnCount, 2);
      expect(allCells, isNot(contains('|')));
      expect(
        table.rows.every((row) => row.length == table.headers.length),
        isTrue,
      );
    });

    test('treats box drawing vertical bars as delimiters', () {
      const text = '''
API │ Detail
──── │ ───
GET /v1/businesses/{:id} │ Return detailed information about a business
POST /v1/businesses │ Add a business''';

      final table = parseReaderContentBlocks(text).single.table!;
      final allCells = [...table.headers, for (final row in table.rows) ...row];

      expect(table.headers, ['API', 'Detail']);
      expect(table.columnCount, 2);
      expect(allCells, isNot(contains('│')));
      expect(allCells, isNot(contains('|')));
      expect(table.rows.first, [
        'GET /v1/businesses/{:id}',
        'Return detailed information about a business',
      ]);
    });

    test('joins wrapped box drawing header cells into headers', () {
      const text = '''
Field │ Description
│ Type
──────
──────
latitude │ Latitude of a given location │ decimal
longitude │ Longitude of a given location │ decimal''';

      final blocks = parseReaderContentBlocks(text);
      final table = blocks.single.table!;

      expect(table.headers, ['Field', 'Description', 'Type']);
      expect(table.columnCount, 3);
      expect(table.rows.first, [
        'latitude',
        'Latitude of a given location',
        'decimal',
      ]);
    });

    test('attaches separated pipe header preamble to following body rows', () {
      const text = '''
API | Detail
---
---

GET /v1/businesses/{:id} | Return detailed information about a business
POST /v1/businesses | Add a business
PUT /v1/businesses/{:id} | Update details of a business''';

      final blocks = parseReaderContentBlocks(text);
      final table = blocks.single.table!;

      expect(table.headers, ['API', 'Detail']);
      expect(table.rows.first, [
        'GET /v1/businesses/{:id}',
        'Return detailed information about a business',
      ]);
      expect(table.rows, hasLength(3));
    });

    test('attaches wrapped separated header preamble to body rows', () {
      const text = '''
Field │ Description
│ Type
──────
──────

latitude │ Latitude of a given location │ decimal
longitude │ Longitude of a given location │ decimal
radius │ Optional. Default is 5000 meters │ int''';

      final blocks = parseReaderContentBlocks(text);
      final table = blocks.single.table!;

      expect(table.headers, ['Field', 'Description', 'Type']);
      expect(table.rows.first, [
        'latitude',
        'Latitude of a given location',
        'decimal',
      ]);
      expect(table.rows.last, [
        'radius',
        'Optional. Default is 5000 meters',
        'int',
      ]);
    });

    test('promotes header paragraph and separator junk into table headers', () {
      const text = '''
API | Detail
__________________________ | ______________
--------------------------

GET /v1/businesses/{:id} | Return detailed information about a business
POST /v1/businesses | Add a business
PUT /v1/businesses/{:id} | Update details of a business''';

      final blocks = parseReaderContentBlocks(text);
      final table = blocks.single.table!;

      expect(table.headers, ['API', 'Detail']);
      expect(table.rows.first, [
        'GET /v1/businesses/{:id}',
        'Return detailed information about a business',
      ]);
      expect(table.rows, hasLength(3));
    });

    test('handles missing cells safely', () {
      const text = '''
Field | Description | Type
--- | --- | ---
latitude | Latitude of a given location | decimal
radius | Optional value''';

      final table = parseReaderContentBlocks(text).single.table!;

      expect(table.rows.last, ['radius', 'Optional value', '']);
    });

    test('handles extra spaces around pipes', () {
      const text = '''
| Field   |  Type |
| --- | --- |
| latitude | decimal |''';

      final table = parseReaderContentBlocks(text).single.table!;

      expect(table.headers, ['Field', 'Type']);
      expect(table.rows.single, ['latitude', 'decimal']);
    });

    test('does not detect normal prose as a table', () {
      const text =
          'This sentence mentions Field | Description once, but it is prose.';

      final blocks = parseReaderContentBlocks(text);

      expect(blocks, hasLength(1));
      expect(blocks.single.type, ReaderContentBlockType.paragraph);
    });

    test('splits paragraphs around a detected table with offsets', () {
      const text = '''
Before table.

Field | Type
--- | ---
latitude | decimal

After table.''';

      final blocks = parseReaderContentBlocks(text);

      expect(blocks.map((block) => block.type), [
        ReaderContentBlockType.paragraph,
        ReaderContentBlockType.table,
        ReaderContentBlockType.paragraph,
      ]);
      expect(text.substring(blocks[1].startOffset), startsWith('Field | Type'));
      expect(text.substring(blocks[2].startOffset), startsWith('\nAfter'));
    });

    test(
      'uses preformatted fallback for table-like content that cannot parse',
      () {
        const text = '''
Field | Description
--- --- ---
latitude only''';

        final blocks = parseReaderContentBlocks(text);

        expect(
          blocks.any(
            (block) => block.type == ReaderContentBlockType.preformatted,
          ),
          isTrue,
        );
      },
    );
  });

  group('readerSpeedReadText', () {
    test('uses parsed table cell text without separator rows', () {
      const text = '''
API | Detail
--- | ---
GET /v1/businesses | Add a business''';

      final speedText = readerSpeedReadText(text);

      expect(speedText, contains('API Detail'));
      expect(speedText, contains('GET /v1/businesses Add a business'));
      expect(speedText, isNot(contains('---')));
    });
  });
}
