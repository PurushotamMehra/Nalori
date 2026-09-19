import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/models/highlight.dart';
import 'package:nalori/services/reader_character_match_service.dart';

void main() {
  Highlight declaration(
    String id,
    String text, {
    int chunkIndex = 0,
    int start = 0,
    Color color = Colors.red,
  }) => Highlight(
    id: id,
    originalChunkIndex: chunkIndex,
    startOffset: start,
    endOffset: start + text.length,
    text: text,
    colorValue: color.toARGB32(),
    type: HighlightType.character,
    createdAt: DateTime(2026, 8, 6),
  );

  BookChunk paragraph(
    int index,
    String text, {
    String? paragraphId,
    int paragraphStart = 0,
  }) => BookChunk(
    index: index,
    type: BookChunkType.text,
    text: text,
    logicalParagraphId: paragraphId ?? 'p$index',
    logicalParagraphStartOffset: paragraphStart,
    logicalParagraphEndOffset: paragraphStart + text.length,
  );

  List<String> termsFor(String name) {
    final plan = buildReaderCharacterMatchPlan(
      highlights: <Highlight>[declaration('one', name)],
    );
    return plan.terms.map((term) => term.text).toList();
  }

  List<String> matchedText(String name, String source) {
    final plan = buildReaderCharacterMatchPlan(
      highlights: <Highlight>[declaration('one', name)],
    );
    final matches = matchReaderCharacterSourceRanges(
      plan: plan,
      sourceChunks: <BookChunk>[paragraph(0, source)],
    );
    return matches
        .map((range) => source.substring(range.startOffset, range.endOffset))
        .toList();
  }

  group('deterministic term derivation', () {
    test('derives complete Elizabeth Bennet and its name parts', () {
      expect(termsFor('Elizabeth Bennet'), <String>[
        'Elizabeth Bennet',
        'Elizabeth',
        'Bennet',
      ]);
    });

    test('derives every Mary Jane Watson name part', () {
      expect(
        termsFor('Mary Jane Watson'),
        containsAll(<String>['Mary Jane Watson', 'Mary', 'Jane', 'Watson']),
      );
    });

    test('preserves hyphens instead of splitting Jean-Luc', () {
      expect(termsFor('Jean-Luc Picard'), <String>[
        'Jean-Luc Picard',
        'Jean-Luc',
        'Picard',
      ]);
      expect(
        termsFor('Jean-Luc Picard'),
        isNot(containsAll(<String>['Jean', 'Luc'])),
      );
    });

    test('excludes particles, honorifics, connectors, and numeric parts', () {
      expect(termsFor('Ludwig van Beethoven'), <String>[
        'Ludwig van Beethoven',
        'Beethoven',
        'Ludwig',
      ]);
      expect(termsFor('Dr. John Watson'), <String>[
        'Dr. John Watson',
        'Watson',
        'John',
      ]);
      expect(termsFor('7 of 9'), <String>['7 of 9']);
    });

    test('preserves initials, apostrophes, and alphanumeric hyphens', () {
      expect(termsFor('J.R. Ewing'), <String>['J.R. Ewing', 'Ewing', 'J.R.']);
      expect(termsFor("O'Brien"), <String>["O'Brien"]);
      expect(termsFor('R2-D2'), <String>['R2-D2']);
    });
  });

  group('matching contract', () {
    test('matches complete phrase, components, and possessive suffixes', () {
      expect(
        matchedText(
          'Elizabeth Bennet',
          "Elizabeth Bennet met Elizabeth's sister and Bennet’s cousin.",
        ),
        <String>['Elizabeth Bennet', "Elizabeth's", 'Bennet’s'],
      );
    });

    test('allows only the narrow leading honorific period variant', () {
      expect(
        matchedText(
          'Dr. John Watson',
          'Dr. John Watson met Dr John Watson. Dr spoke to Watson.',
        ),
        <String>['Dr. John Watson', 'Dr John Watson', 'Watson'],
      );
    });

    test('is case-sensitive for ambiguous common name words', () {
      for (final name in <String>['Will', 'May', 'Rose', 'Mark', 'Bill']) {
        final lower = name.toLowerCase();
        expect(matchedText(name, '$name $lower'), <String>[name]);
      }
    });

    test('uses Unicode-aware name token boundaries', () {
      expect(matchedText('Ana', 'ЖAna Ana AnaЖ Jean-Ana'), <String>['Ana']);
      expect(matchedText('Ana', '中Ana Ana Ana中'), <String>['Ana']);
      expect(matchedText('Jean', 'Jean-Luc Jean'), <String>['Jean']);
    });

    test('compares NFC-equivalent text without changing source offsets', () {
      const source = 'Jose\u0301 met José.';
      expect(matchedText('José', source), <String>['Jose\u0301', 'José']);
    });

    test('handles canonical mark ordering and Hangul composition', () {
      expect(matchedText('À\u0315', 'A\u0315\u0300'), <String>[
        'A\u0315\u0300',
      ]);
      expect(matchedText('가', '가'), <String>['가']);
    });

    test('keeps straight and curly possessive suffixes in styled ranges', () {
      expect(matchedText("O'Brien", "O'Brien's and O'Brien’s"), <String>[
        "O'Brien's",
        'O\'Brien’s',
      ]);
    });

    test('resolves complete phrases before overlapping components', () {
      expect(
        matchedText('Mary Jane Watson', 'Mary Jane Watson met Jane.'),
        <String>['Mary Jane Watson', 'Jane'],
      );
    });
  });

  group('declaration identity and collisions', () {
    test('suppresses a shared part across distinct declaration IDs', () {
      final plan = buildReaderCharacterMatchPlan(
        highlights: <Highlight>[
          declaration('smith', 'John Smith'),
          declaration('watson', 'John Watson', color: Colors.blue),
        ],
      );
      expect(plan.terms.map((term) => term.text), <String>[
        'John Watson',
        'John Smith',
        'Watson',
        'Smith',
      ]);
      expect(plan.terms.map((term) => term.text), isNot(contains('John')));
    });

    test(
      'suppresses duplicate complete phrases instead of choosing a color',
      () {
        final plan = buildReaderCharacterMatchPlan(
          highlights: <Highlight>[
            declaration('red', 'Elizabeth Bennet'),
            declaration('blue', 'Elizabeth Bennet', color: Colors.blue),
          ],
        );
        expect(plan.terms, isEmpty);
        expect(plan.suppressedEffectiveTerms, hasLength(3));
      },
    );

    test(
      'shared-ID segments reconstruct without colliding with themselves',
      () {
        const source = 'Elizabeth Bennet arrived.';
        final plan = buildReaderCharacterMatchPlan(
          highlights: <Highlight>[
            declaration('same', 'Elizabeth'),
            declaration('same', ' Bennet', start: 9),
          ],
          sourceChunks: <BookChunk>[paragraph(0, source)],
        );
        expect(plan.declarations.single.selectedTexts, <String>[
          'Elizabeth Bennet',
        ]);
        expect(
          plan.terms.map((term) => term.text),
          contains('Elizabeth Bennet'),
        );
        expect(plan.suppressedEffectiveTerms, isEmpty);
      },
    );

    test('never concatenates shared-ID selections across paragraphs', () {
      final plan = buildReaderCharacterMatchPlan(
        highlights: <Highlight>[
          declaration('same', 'Mary'),
          declaration('same', 'Jane', chunkIndex: 1),
        ],
        sourceChunks: <BookChunk>[paragraph(0, 'Mary'), paragraph(1, 'Jane')],
      );
      expect(plan.declarations.single.selectedTexts, <String>['Mary', 'Jane']);
      expect(plan.terms.map((term) => term.text), isNot(contains('MaryJane')));
      expect(plan.terms.map((term) => term.text), isNot(contains('Mary Jane')));
    });

    test('is independent of declaration list order and color', () {
      final first = <Highlight>[
        declaration('smith', 'John Smith'),
        declaration('watson', 'John Watson', color: Colors.blue),
      ];
      final second = <Highlight>[first.last, first.first];
      final firstPlan = buildReaderCharacterMatchPlan(highlights: first);
      final secondPlan = buildReaderCharacterMatchPlan(highlights: second);
      expect(
        firstPlan.terms.map((term) => '${term.declarationId}:${term.text}'),
        secondPlan.terms.map((term) => '${term.declarationId}:${term.text}'),
      );
    });
  });

  group('logical paragraphs and display projection', () {
    test(
      'matches across inline-flattened source and a logical chunk split',
      () {
        final plan = buildReaderCharacterMatchPlan(
          highlights: <Highlight>[declaration('one', 'Elizabeth Bennet')],
        );
        final chunks = <BookChunk>[
          paragraph(0, 'Elizabeth ', paragraphId: 'p'),
          paragraph(1, 'Bennet arrived.', paragraphId: 'p', paragraphStart: 10),
        ];
        final ranges = matchReaderCharacterSourceRanges(
          plan: plan,
          sourceChunks: chunks,
        );
        expect(ranges, hasLength(2));
        expect(ranges.first.startOffset, 0);
        expect(ranges.first.endOffset, 10);
        expect(ranges.last.startOffset, 0);
        expect(ranges.last.endOffset, 6);
      },
    );

    test('never matches across a structural paragraph boundary', () {
      final plan = buildReaderCharacterMatchPlan(
        highlights: <Highlight>[declaration('one', 'Elizabeth Bennet')],
      );
      final ranges = matchReaderCharacterSourceRanges(
        plan: plan,
        sourceChunks: <BookChunk>[
          paragraph(0, 'Elizabeth '),
          paragraph(1, 'Bennet'),
        ],
      );
      expect(ranges.map((range) => range.term), <String>[
        'Elizabeth',
        'Bennet',
      ]);
    });

    test('projects one source match across two display cards after reflow', () {
      const source = 'Elizabeth Bennet arrived.';
      final plan = buildReaderCharacterMatchPlan(
        highlights: <Highlight>[declaration('one', 'Elizabeth Bennet')],
      );
      final sourceRanges = matchReaderCharacterSourceRanges(
        plan: plan,
        sourceChunks: <BookChunk>[paragraph(0, source)],
      );
      const firstCard = BookChunk(
        index: 10,
        type: BookChunkType.text,
        text: 'Elizabeth ',
        sourceRanges: <ChunkSourceRange>[
          ChunkSourceRange(
            originalChunkIndex: 0,
            originalStartOffset: 0,
            originalEndOffset: 10,
            displayStartOffset: 0,
            displayEndOffset: 10,
            logicalParagraphId: 'p0',
          ),
        ],
      );
      const secondCard = BookChunk(
        index: 11,
        type: BookChunkType.text,
        text: 'Bennet arrived.',
        sourceRanges: <ChunkSourceRange>[
          ChunkSourceRange(
            originalChunkIndex: 0,
            originalStartOffset: 10,
            originalEndOffset: 25,
            displayStartOffset: 0,
            displayEndOffset: 15,
            logicalParagraphId: 'p0',
          ),
        ],
      );
      final first = projectReaderCharacterRangesToDisplay(
        displayChunk: firstCard,
        sourceRanges: sourceRanges,
      );
      final second = projectReaderCharacterRangesToDisplay(
        displayChunk: secondCard,
        sourceRanges: sourceRanges,
      );
      expect(first.single.startOffset, 0);
      expect(first.single.endOffset, 10);
      expect(second.single.startOffset, 0);
      expect(second.single.endOffset, 6);
    });
  });
}
