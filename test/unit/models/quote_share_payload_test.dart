import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/quote_share_payload.dart';
import 'package:nalori/models/reading_settings.dart';

void main() {
  group('QuoteSharePayload', () {
    test('normalizes selected quote whitespace', () {
      expect(
        QuoteSharePayload.normalizeQuote('  This\nis\t a   quote.  '),
        'This is a quote.',
      );
    });

    test('normalizes quote punctuation spacing without changing meaning', () {
      expect(
        QuoteSharePayload.normalizeQuote(
          "  ' I know you , '  the eyes seemed to say ,  ' I see through you . ' ",
        ),
        "'I know you,' the eyes seemed to say, 'I see through you.'",
      );
    });

    test('caps long quotes with a trailing ellipsis', () {
      final quote = List.filled(160, 'word').join(' ');

      final normalized = QuoteSharePayload.normalizeQuote(quote, maxLength: 80);

      expect(normalized.length, lessThanOrEqualTo(80));
      expect(normalized, endsWith('...'));
    });

    test('falls back to an untitled book when title is empty', () {
      final payload = QuoteSharePayload.fromSelection(
        quote: 'A useful line.',
        bookTitle: '   ',
        author: '',
        bookId: 'book.epub',
        displayIndex: 4,
        fontFamily: ReaderFontFamily.lora,
      );

      expect(payload.bookTitle, 'Untitled Book');
      expect(payload.author, isEmpty);
      expect(payload.fontFamily, ReaderFontFamily.lora);
      expect(payload.attribution, 'Untitled Book');
    });
  });
}
