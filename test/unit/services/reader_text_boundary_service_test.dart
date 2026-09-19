import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/reader_text_boundary.dart';
import 'package:nalori/services/reader_text_boundary_service.dart';

void main() {
  const service = ReaderTextBoundaryService();

  List<String> sentences(String text) {
    final analysis = service.analyze(text);
    return analysis.sentenceRanges
        .map((range) => text.substring(range.start, range.end).trim())
        .toList();
  }

  test('protects compact and spaced initialisms with contextual endings', () {
    expect(sentences('1 A.M., as Shackleton...'), ['1 A.M., as Shackleton...']);
    expect(sentences('10 P.M. He returned.'), ['10 P.M.', 'He returned.']);
    expect(sentences('The U.S.A. was involved.'), ['The U.S.A. was involved.']);
    expect(sentences('J. R. R. Tolkien wrote...'), [
      'J. R. R. Tolkien wrote...',
    ]);
  });

  test('uses a small contextual abbreviation supplement', () {
    expect(sentences('Dr. Smith arrived. Prof. Rao spoke.'), [
      'Dr. Smith arrived.',
      'Prof. Rao spoke.',
    ]);
    expect(sentences('It happened on Jan. 4. No. 5 was selected.'), [
      'It happened on Jan. 4.',
      'No. 5 was selected.',
    ]);
  });

  test('protects numbers versions domains urls and email addresses', () {
    const text =
        'The value was 3.14. Version v2.1.4 works. '
        'Visit example.com today. Email a.b@example.com.';
    expect(sentences(text), [
      'The value was 3.14.',
      'Version v2.1.4 works.',
      'Visit example.com today.',
      'Email a.b@example.com.',
    ]);
  });

  test('handles ellipses quotes and CJK terminators', () {
    expect(sentences('Wait... what happened?'), ['Wait...', 'what happened?']);
    expect(sentences('"Stop." He turned.'), ['"Stop."', 'He turned.']);
    expect(sentences('今日は晴れ。次です！本当？'), ['今日は晴れ。', '次です！', '本当？']);
  });

  test('reports rejected protected candidates with exact UTF-16 offsets', () {
    const text = 'At 1 A.M., as dawn broke.';
    final analysis = service.analyze(text);
    final tokenStart = text.indexOf('A.M.');
    final tokenEnd = tokenStart + 'A.M.'.length;

    expect(
      analysis.protectedSpans.any(
        (span) =>
            span.start == tokenStart &&
            span.end == tokenEnd &&
            span.kind == ReaderProtectedSpanKind.initialism,
      ),
      isTrue,
    );
    expect(
      analysis.sentenceCandidates.any(
        (candidate) =>
            candidate.offset == tokenStart + 2 &&
            !candidate.accepted &&
            candidate.reason == 'inside_protected_initialism',
      ),
      isTrue,
    );
    expect(
      analysis.sentenceCandidates.any(
        (candidate) =>
            candidate.offset == tokenEnd &&
            !candidate.accepted &&
            candidate.reason == 'protected_token_continues_with_punctuation',
      ),
      isTrue,
    );
  });

  test('word opportunities do not split spaced initials', () {
    const text = 'J. R. R. Tolkien';
    final analysis = service.analyze(text);
    final ranges = service.wordRanges(
      text,
      protectedSpans: analysis.protectedSpans,
    );

    expect(
      ranges.map((range) => text.substring(range.start, range.end)).toList(),
      ['J. R. R. ', 'Tolkien'],
    );
  });

  test('grapheme ranges preserve combining variation and ZWJ sequences', () {
    const text = 'e\u0301✈️👨‍👩‍👧‍👦';
    final ranges = service.graphemeRanges(text);

    expect(ranges, hasLength(3));
    expect(
      ranges.map((range) => text.substring(range.start, range.end)).join(),
      text,
    );
    expect(
      ranges.every(
        (range) =>
            range.trailingBoundaryKind ==
            ReaderTextBoundaryKind.emergencyGrapheme,
      ),
      isTrue,
    );
  });
}
