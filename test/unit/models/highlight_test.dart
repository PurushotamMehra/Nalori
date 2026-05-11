import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/highlight.dart';
import 'dart:convert';

void main() {
  group('Highlight model', () {
    test('uses legacy palette color when colorValue is absent', () {
      final highlight = Highlight(
        id: 'legacy',
        originalChunkIndex: 0,
        startOffset: 0,
        endOffset: 4,
        text: 'Text',
        colorIndex: 1,
        createdAt: DateTime(2026, 4, 9),
      );

      expect(highlight.color, const Color(0xFF81C784));
      expect(highlight.resolvedColorValue, const Color(0xFF81C784).toARGB32());
    });

    test('prefers saved colorValue over legacy colorIndex', () {
      final highlight = Highlight(
        id: 'custom',
        originalChunkIndex: 0,
        startOffset: 0,
        endOffset: 4,
        text: 'Text',
        colorValue: const Color(0xFF127A6E).toARGB32(),
        createdAt: DateTime(2026, 4, 9),
      );

      expect(highlight.color, const Color(0xFF127A6E));
      expect(highlight.resolvedColorValue, const Color(0xFF127A6E).toARGB32());
    });

    test('exposes type helpers', () {
      final characterHighlight = Highlight(
        id: 'character',
        originalChunkIndex: 0,
        startOffset: 0,
        endOffset: 8,
        text: 'Captain',
        type: HighlightType.character,
        createdAt: DateTime(2026, 4, 9),
      );

      final noteHighlight = Highlight(
        id: 'note',
        originalChunkIndex: 0,
        startOffset: 0,
        endOffset: 8,
        text: 'Captain',
        type: HighlightType.note,
        note: 'Remember this.',
        createdAt: DateTime(2026, 4, 9),
      );

      expect(characterHighlight.isCharacter, isTrue);
      expect(characterHighlight.isRegularHighlight, isFalse);
      expect(noteHighlight.isNote, isTrue);
      expect(noteHighlight.hasNote, isTrue);
    });

    test('copyWith can update colorValue and note independently', () {
      final original = Highlight(
        id: 'copy',
        originalChunkIndex: 2,
        startOffset: 4,
        endOffset: 12,
        text: 'Original',
        createdAt: DateTime(2026, 4, 9),
      );

      final updated = original.copyWith(
        colorValue: const Color(0xFF3366CC).toARGB32(),
        note: 'Saved note',
      );

      expect(updated.color, const Color(0xFF3366CC));
      expect(updated.note, 'Saved note');
      expect(updated.colorIndex, 0);
    });

    test('serializes and deserializes custom colors', () {
      final highlight = Highlight(
        id: 'serialize',
        originalChunkIndex: 5,
        startOffset: 10,
        endOffset: 20,
        text: 'Highlighted text',
        colorIndex: 4,
        colorValue: const Color(0xFF7E57C2).toARGB32(),
        type: HighlightType.note,
        note: 'Keep this detail',
        createdAt: DateTime(2026, 4, 9, 10, 30),
      );

      final decoded = Highlight.fromJson(highlight.toJson());

      expect(decoded.id, highlight.id);
      expect(decoded.color, const Color(0xFF7E57C2));
      expect(decoded.type, HighlightType.note);
      expect(decoded.note, 'Keep this detail');
    });

    test('decodes legacy character + note payloads into two annotations', () {
      final legacyPayload = jsonEncode([
        {
          'id': 'base',
          'ci': 0,
          'so': 0,
          'eo': 5,
          'tx': 'Alice',
          'co': 0,
          'ic': true,
          'nt': 'Main character',
          'ca': '2026-04-09T00:00:00.000',
        },
      ]);
      final decoded = Highlight.decodeList(legacyPayload);

      expect(decoded, hasLength(2));
      expect(decoded.first.type, HighlightType.character);
      expect(decoded.last.type, HighlightType.note);
      expect(decoded.last.note, 'Main character');
    });
  });

  group('highlight color helpers', () {
    test('normalizes color equality by ARGB value', () {
      expect(
        isSameHighlightColor(
          const Color(0xFFFFD54F),
          Color(const Color(0xFFFFD54F).toARGB32()),
        ),
        isTrue,
      );
    });

    test('finds the default palette index for base colors', () {
      expect(defaultHighlightColorIndex(const Color(0xFFFF8A65)), 2);
      expect(defaultHighlightColorIndex(const Color(0xFF123456)), isNull);
    });
  });
}
