import 'package:flutter/foundation.dart';

import '../models/book_chunk.dart';
import '../models/highlight.dart';
import 'book_authoritative_text_service.dart';
import 'reader_unicode_normalization.dart';

/// Reader-only policy for deterministic character declaration expansion.
const Set<String> readerCharacterHonorifics = <String>{
  'mr',
  'mrs',
  'ms',
  'dr',
  'prof',
};

/// Tokens that are useful inside a complete name but unsafe on their own.
const Set<String> readerCharacterConnectors = <String>{
  'and',
  'da',
  'de',
  'del',
  'der',
  'di',
  'la',
  'le',
  'of',
  'the',
  'van',
  'von',
};

@immutable
class ReaderCharacterDeclaration {
  const ReaderCharacterDeclaration({
    required this.id,
    required this.selectedTexts,
    required this.colorValue,
  });

  final String id;
  final List<String> selectedTexts;
  final int colorValue;
}

@immutable
class ReaderCharacterTerm {
  const ReaderCharacterTerm({
    required this.declarationId,
    required this.text,
    required this.variants,
    required this.effectiveKey,
    required this.colorValue,
    required this.isCompletePhrase,
  });

  final String declarationId;
  final String text;
  final List<String> variants;
  final String effectiveKey;
  final int colorValue;
  final bool isCompletePhrase;
}

@immutable
class ReaderCharacterMatchPlan {
  const ReaderCharacterMatchPlan({
    required this.declarations,
    required this.terms,
    required this.suppressedEffectiveTerms,
  });

  final List<ReaderCharacterDeclaration> declarations;
  final List<ReaderCharacterTerm> terms;
  final Set<String> suppressedEffectiveTerms;
}

/// A generated half-open range in original source-chunk UTF-16 coordinates.
@immutable
class ReaderCharacterSourceRange {
  const ReaderCharacterSourceRange({
    required this.declarationId,
    required this.originalChunkIndex,
    required this.startOffset,
    required this.endOffset,
    required this.colorValue,
    required this.term,
  });

  final String declarationId;
  final int originalChunkIndex;
  final int startOffset;
  final int endOffset;
  final int colorValue;
  final String term;
}

/// A generated half-open range in one visible display card's UTF-16 text.
@immutable
class ReaderCharacterDisplayRange {
  const ReaderCharacterDisplayRange({
    required this.declarationId,
    required this.startOffset,
    required this.endOffset,
    required this.colorValue,
  });

  final String declarationId;
  final int startOffset;
  final int endOffset;
  final int colorValue;
}

ReaderCharacterMatchPlan buildReaderCharacterMatchPlan({
  required List<Highlight> highlights,
  List<BookChunk> sourceChunks = const <BookChunk>[],
}) {
  final characterGroups = <String, List<Highlight>>{};
  for (final highlight in highlights) {
    if (!highlight.isCharacter) continue;
    characterGroups
        .putIfAbsent(highlight.id, () => <Highlight>[])
        .add(highlight);
  }

  final chunksByIndex = <int, BookChunk>{
    for (final chunk in sourceChunks) chunk.index: chunk,
  };
  final declarations = <ReaderCharacterDeclaration>[];
  final unsuppressedTerms = <ReaderCharacterTerm>[];
  final declarationIds = characterGroups.keys.toList()..sort();

  for (final declarationId in declarationIds) {
    final segments = characterGroups[declarationId]!;
    final selectedTexts = _reconstructDeclarationTexts(segments, chunksByIndex);
    if (selectedTexts.isEmpty) continue;
    final sortedSegments = segments.toList()..sort(_compareHighlightsBySource);
    final colorValue = sortedSegments.first.resolvedColorValue;
    final declaration = ReaderCharacterDeclaration(
      id: declarationId,
      selectedTexts: List<String>.unmodifiable(selectedTexts),
      colorValue: colorValue,
    );
    declarations.add(declaration);

    final byEffectiveKey = <String, ReaderCharacterTerm>{};
    for (final selectedText in selectedTexts) {
      for (final term in _deriveTerms(declaration, selectedText)) {
        final existing = byEffectiveKey[term.effectiveKey];
        if (existing == null || _compareTerms(term, existing) < 0) {
          byEffectiveKey[term.effectiveKey] = term;
        }
      }
    }
    unsuppressedTerms.addAll(byEffectiveKey.values);
  }

  final declarationIdsByTerm = <String, Set<String>>{};
  for (final term in unsuppressedTerms) {
    declarationIdsByTerm
        .putIfAbsent(term.effectiveKey, () => <String>{})
        .add(term.declarationId);
  }
  final suppressed = <String>{
    for (final entry in declarationIdsByTerm.entries)
      if (entry.value.length > 1) entry.key,
  };
  final terms =
      unsuppressedTerms
          .where((term) => !suppressed.contains(term.effectiveKey))
          .toList()
        ..sort(_compareTerms);

  return ReaderCharacterMatchPlan(
    declarations: List<ReaderCharacterDeclaration>.unmodifiable(declarations),
    terms: List<ReaderCharacterTerm>.unmodifiable(terms),
    suppressedEffectiveTerms: Set<String>.unmodifiable(suppressed),
  );
}

List<ReaderCharacterSourceRange> matchReaderCharacterSourceRanges({
  required ReaderCharacterMatchPlan plan,
  required List<BookChunk> sourceChunks,
}) {
  if (plan.terms.isEmpty || sourceChunks.isEmpty) return const [];
  final paragraphs = _buildLogicalParagraphs(sourceChunks);
  final accepted = <ReaderCharacterSourceRange>[];

  for (final paragraph in paragraphs) {
    final normalizedParagraph = readerNormalizeSourceForComparison(
      paragraph.text,
    );
    final candidates = <_ParagraphMatch>[];
    for (final term in plan.terms) {
      for (final variant in term.variants) {
        final normalizedVariant = readerNormalizeForComparison(variant);
        if (normalizedVariant.isEmpty) continue;
        var searchFrom = 0;
        while (searchFrom < normalizedParagraph.text.length) {
          final normalizedStart = normalizedParagraph.text.indexOf(
            normalizedVariant,
            searchFrom,
          );
          if (normalizedStart < 0) break;
          final normalizedEnd = normalizedStart + normalizedVariant.length;
          final sourceStart = normalizedParagraph.sourceStartForRange(
            normalizedStart,
            normalizedEnd,
          );
          var sourceEnd = normalizedParagraph.sourceEndForRange(
            normalizedStart,
            normalizedEnd,
          );
          sourceEnd = _includePossessiveSuffix(paragraph.text, sourceEnd);
          if (_hasNameTokenBoundary(paragraph.text, sourceStart, sourceEnd)) {
            candidates.add(
              _ParagraphMatch(start: sourceStart, end: sourceEnd, term: term),
            );
          }
          searchFrom = normalizedStart + 1;
        }
      }
    }

    candidates.sort(_compareParagraphMatches);
    final selected = <_ParagraphMatch>[];
    for (final candidate in candidates) {
      if (selected.any((match) => _rangesOverlap(match, candidate))) continue;
      selected.add(candidate);
    }
    selected.sort((a, b) => a.start.compareTo(b.start));

    for (final match in selected) {
      for (final segment in paragraph.segments) {
        final overlapStart = match.start > segment.paragraphStart
            ? match.start
            : segment.paragraphStart;
        final overlapEnd = match.end < segment.paragraphEnd
            ? match.end
            : segment.paragraphEnd;
        if (overlapStart >= overlapEnd) continue;
        accepted.add(
          ReaderCharacterSourceRange(
            declarationId: match.term.declarationId,
            originalChunkIndex: segment.originalChunkIndex,
            startOffset:
                segment.sourceStart + (overlapStart - segment.paragraphStart),
            endOffset:
                segment.sourceStart + (overlapEnd - segment.paragraphStart),
            colorValue: match.term.colorValue,
            term: match.term.text,
          ),
        );
      }
    }
  }

  accepted.sort((a, b) {
    final chunk = a.originalChunkIndex.compareTo(b.originalChunkIndex);
    if (chunk != 0) return chunk;
    final start = a.startOffset.compareTo(b.startOffset);
    if (start != 0) return start;
    final end = b.endOffset.compareTo(a.endOffset);
    if (end != 0) return end;
    return a.declarationId.compareTo(b.declarationId);
  });
  return List<ReaderCharacterSourceRange>.unmodifiable(accepted);
}

List<ReaderCharacterDisplayRange> projectReaderCharacterRangesToDisplay({
  required BookChunk displayChunk,
  required List<ReaderCharacterSourceRange> sourceRanges,
}) {
  final projected = <ReaderCharacterDisplayRange>[];
  for (final sourceRange in sourceRanges) {
    final mapped = displayChunk.mapOriginalRangeToDisplay(
      sourceRange.originalChunkIndex,
      sourceRange.startOffset,
      sourceRange.endOffset,
    );
    for (final range in mapped) {
      projected.add(
        ReaderCharacterDisplayRange(
          declarationId: sourceRange.declarationId,
          startOffset: range.displayStartOffset,
          endOffset: range.displayEndOffset,
          colorValue: sourceRange.colorValue,
        ),
      );
    }
  }
  projected.sort((a, b) {
    final start = a.startOffset.compareTo(b.startOffset);
    if (start != 0) return start;
    final end = b.endOffset.compareTo(a.endOffset);
    if (end != 0) return end;
    return a.declarationId.compareTo(b.declarationId);
  });
  return List<ReaderCharacterDisplayRange>.unmodifiable(projected);
}

List<String> _reconstructDeclarationTexts(
  List<Highlight> highlights,
  Map<int, BookChunk> chunksByIndex,
) {
  final segments = <_DeclarationSegment>[];
  for (final highlight in highlights) {
    final chunk = chunksByIndex[highlight.originalChunkIndex];
    final chunkText = chunk?.text;
    final sourceMatches =
        chunkText != null &&
        highlight.startOffset >= 0 &&
        highlight.endOffset <= chunkText.length &&
        highlight.startOffset < highlight.endOffset &&
        chunkText.substring(highlight.startOffset, highlight.endOffset) ==
            highlight.text;
    if (sourceMatches) {
      final paragraphKey = chunk!.logicalParagraphId == null
          ? 'chunk:${chunk.index}'
          : 'paragraph:${chunk.logicalParagraphId}';
      segments.add(
        _DeclarationSegment(
          paragraphKey: paragraphKey,
          start: chunk.logicalParagraphStartOffset + highlight.startOffset,
          end: chunk.logicalParagraphStartOffset + highlight.endOffset,
          text: highlight.text,
        ),
      );
      continue;
    }

    final stable = highlight.stableLocation;
    final sourceKey = stable == null
        ? 'legacy:${highlight.originalChunkIndex}'
        : <Object?>[
            stable.bookId,
            stable.publicationFingerprint,
            stable.spineIndex,
            stable.normalizedHref ?? stable.href,
            stable.sourceChecksum,
            stable.sourceParserVersion,
            stable.localChunkIndex,
          ].join('|');
    final start = stable?.textOffset ?? highlight.startOffset;
    segments.add(
      _DeclarationSegment(
        paragraphKey: sourceKey,
        start: start,
        end: start + highlight.text.length,
        text: highlight.text,
      ),
    );
  }

  segments.sort((a, b) {
    final paragraph = a.paragraphKey.compareTo(b.paragraphKey);
    if (paragraph != 0) return paragraph;
    final start = a.start.compareTo(b.start);
    if (start != 0) return start;
    final end = a.end.compareTo(b.end);
    if (end != 0) return end;
    return a.text.compareTo(b.text);
  });

  final texts = <String>[];
  StringBuffer? current;
  _DeclarationSegment? previous;
  for (final segment in segments) {
    final contiguous =
        previous != null &&
        previous.paragraphKey == segment.paragraphKey &&
        previous.end == segment.start;
    if (!contiguous) {
      if (current != null) _addDeclarationText(texts, current.toString());
      current = StringBuffer(segment.text);
    } else {
      current!.write(segment.text);
    }
    previous = segment;
  }
  if (current != null) _addDeclarationText(texts, current.toString());
  return texts;
}

void _addDeclarationText(List<String> texts, String raw) {
  final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isNotEmpty && !texts.contains(text)) texts.add(text);
}

List<ReaderCharacterTerm> _deriveTerms(
  ReaderCharacterDeclaration declaration,
  String selectedText,
) {
  final tokens = selectedText.split(' ');
  final terms = <ReaderCharacterTerm>[
    _buildTerm(
      declaration: declaration,
      text: selectedText,
      isCompletePhrase: true,
    ),
  ];
  if (tokens.length == 1) return terms;

  for (final token in tokens) {
    if (!_isUsefulStandaloneComponent(token)) continue;
    terms.add(
      _buildTerm(
        declaration: declaration,
        text: token,
        isCompletePhrase: false,
      ),
    );
  }
  return terms;
}

ReaderCharacterTerm _buildTerm({
  required ReaderCharacterDeclaration declaration,
  required String text,
  required bool isCompletePhrase,
}) {
  final variants = <String>{text};
  if (isCompletePhrase) {
    final firstSpace = text.indexOf(' ');
    if (firstSpace > 0) {
      final first = text.substring(0, firstSpace);
      final honorific = _honorificKey(first);
      if (readerCharacterHonorifics.contains(honorific)) {
        final rest = text.substring(firstSpace);
        variants.add(
          first.endsWith('.')
              ? '${first.substring(0, first.length - 1)}$rest'
              : '$first.$rest',
        );
      }
    }
  }
  final sortedVariants = variants.toList()
    ..sort((a, b) {
      final length = b.length.compareTo(a.length);
      return length != 0 ? length : a.compareTo(b);
    });
  final effectiveVariants =
      sortedVariants.map(readerNormalizeForComparison).toList()..sort();
  return ReaderCharacterTerm(
    declarationId: declaration.id,
    text: text,
    variants: List<String>.unmodifiable(sortedVariants),
    effectiveKey: effectiveVariants.join('\u0000'),
    colorValue: declaration.colorValue,
    isCompletePhrase: isCompletePhrase,
  );
}

bool _isUsefulStandaloneComponent(String token) {
  final policyKey = _honorificKey(token);
  if (readerCharacterHonorifics.contains(policyKey) ||
      readerCharacterConnectors.contains(policyKey)) {
    return false;
  }
  if (_isPureNumeric(token)) return false;
  return token.runes.any(readerIsUnicodeLetter);
}

String _honorificKey(String token) {
  final withoutPeriod = token.endsWith('.')
      ? token.substring(0, token.length - 1)
      : token;
  return withoutPeriod.toLowerCase();
}

bool _isPureNumeric(String token) =>
    token.isNotEmpty && token.runes.every(readerIsUnicodeNumber);

int _compareHighlightsBySource(Highlight a, Highlight b) {
  String stableKey(Highlight highlight) {
    final stable = highlight.stableLocation;
    if (stable == null) return '';
    return <Object?>[
      stable.bookId,
      stable.publicationFingerprint,
      stable.spineIndex,
      stable.normalizedHref ?? stable.href,
      stable.sourceChecksum,
      stable.sourceParserVersion,
      stable.localChunkIndex,
      stable.textOffset,
    ].join('|');
  }

  final stable = stableKey(a).compareTo(stableKey(b));
  if (stable != 0) return stable;
  final chunk = a.originalChunkIndex.compareTo(b.originalChunkIndex);
  if (chunk != 0) return chunk;
  final start = a.startOffset.compareTo(b.startOffset);
  if (start != 0) return start;
  return a.endOffset.compareTo(b.endOffset);
}

int _compareTerms(ReaderCharacterTerm a, ReaderCharacterTerm b) {
  final longestA = a.variants.fold<int>(
    0,
    (n, text) => text.length > n ? text.length : n,
  );
  final longestB = b.variants.fold<int>(
    0,
    (n, text) => text.length > n ? text.length : n,
  );
  final length = longestB.compareTo(longestA);
  if (length != 0) return length;
  final key = a.effectiveKey.compareTo(b.effectiveKey);
  if (key != 0) return key;
  return a.declarationId.compareTo(b.declarationId);
}

class _DeclarationSegment {
  const _DeclarationSegment({
    required this.paragraphKey,
    required this.start,
    required this.end,
    required this.text,
  });

  final String paragraphKey;
  final int start;
  final int end;
  final String text;
}

class _LogicalParagraphSegment {
  const _LogicalParagraphSegment({
    required this.originalChunkIndex,
    required this.sourceStart,
    required this.paragraphStart,
    required this.paragraphEnd,
  });

  final int originalChunkIndex;
  final int sourceStart;
  final int paragraphStart;
  final int paragraphEnd;
}

class _LogicalParagraph {
  const _LogicalParagraph({required this.text, required this.segments});

  final String text;
  final List<_LogicalParagraphSegment> segments;
}

List<_LogicalParagraph> _buildLogicalParagraphs(List<BookChunk> sourceChunks) {
  final grouped = <String, List<BookChunk>>{};
  for (final chunk in sourceChunks) {
    final text = authoritativeBookChunkText(chunk);
    if (chunk.type != BookChunkType.text || text == null || text.isEmpty) {
      continue;
    }
    final key = chunk.logicalParagraphId ?? 'chunk:${chunk.index}';
    grouped.putIfAbsent(key, () => <BookChunk>[]).add(chunk);
  }

  final paragraphs = <_LogicalParagraph>[];
  final keys = grouped.keys.toList()..sort();
  for (final key in keys) {
    final chunks = grouped[key]!
      ..sort((a, b) {
        final offset = a.logicalParagraphStartOffset.compareTo(
          b.logicalParagraphStartOffset,
        );
        return offset != 0 ? offset : a.index.compareTo(b.index);
      });
    StringBuffer? text;
    final segments = <_LogicalParagraphSegment>[];
    var expectedParagraphOffset = -1;

    void publish() {
      if (text == null || segments.isEmpty) return;
      paragraphs.add(
        _LogicalParagraph(
          text: text.toString(),
          segments: List<_LogicalParagraphSegment>.unmodifiable(segments),
        ),
      );
    }

    for (final chunk in chunks) {
      final chunkText = authoritativeBookChunkTextOrEmpty(chunk);
      final paragraphOffset = chunk.logicalParagraphId == null
          ? 0
          : chunk.logicalParagraphStartOffset;
      if (text == null || paragraphOffset != expectedParagraphOffset) {
        publish();
        text = StringBuffer();
        segments.clear();
      }
      final start = text.length;
      text.write(chunkText);
      segments.add(
        _LogicalParagraphSegment(
          originalChunkIndex: chunk.index,
          sourceStart: 0,
          paragraphStart: start,
          paragraphEnd: start + chunkText.length,
        ),
      );
      expectedParagraphOffset = paragraphOffset + chunkText.length;
    }
    publish();
  }
  return paragraphs;
}

class _ParagraphMatch {
  const _ParagraphMatch({
    required this.start,
    required this.end,
    required this.term,
  });

  final int start;
  final int end;
  final ReaderCharacterTerm term;
}

int _compareParagraphMatches(_ParagraphMatch a, _ParagraphMatch b) {
  final length = (b.end - b.start).compareTo(a.end - a.start);
  if (length != 0) return length;
  final start = a.start.compareTo(b.start);
  if (start != 0) return start;
  final term = a.term.effectiveKey.compareTo(b.term.effectiveKey);
  if (term != 0) return term;
  return a.term.declarationId.compareTo(b.term.declarationId);
}

bool _rangesOverlap(_ParagraphMatch a, _ParagraphMatch b) =>
    a.start < b.end && b.start < a.end;

int _includePossessiveSuffix(String text, int end) {
  if (end + 1 < text.length &&
      (text[end] == "'" || text[end] == '\u2019') &&
      text[end + 1] == 's') {
    return end + 2;
  }
  return end;
}

bool _hasNameTokenBoundary(String text, int start, int end) {
  final before = start > 0 ? _runeBefore(text, start) : null;
  final after = end < text.length ? _runeAt(text, end) : null;
  final beforeIsToken =
      before != null &&
      (before == 0x002E
          ? start > 1 && _isNameTokenRune(_runeBefore(text, start - 1))
          : _isNameTokenRune(before));
  final afterIsToken =
      after != null &&
      (after == 0x002E
          ? end + 1 < text.length && _isNameTokenRune(_runeAt(text, end + 1))
          : _isNameTokenRune(after));
  return !beforeIsToken && !afterIsToken;
}

int _runeAt(String text, int offset) {
  final first = text.codeUnitAt(offset);
  if (first >= 0xD800 && first <= 0xDBFF && offset + 1 < text.length) {
    return text.substring(offset, offset + 2).runes.single;
  }
  return first;
}

int _runeBefore(String text, int offset) {
  final previous = text.codeUnitAt(offset - 1);
  if (previous >= 0xDC00 && previous <= 0xDFFF && offset >= 2) {
    return text.substring(offset - 2, offset).runes.single;
  }
  return previous;
}

bool _isNameTokenRune(int rune) =>
    readerIsUnicodeLetter(rune) ||
    readerIsUnicodeNumber(rune) ||
    readerIsUnicodeMark(rune) ||
    readerIsUnicodeConnectorPunctuation(rune) ||
    rune == 0x0027 ||
    rune == 0x2019 ||
    rune == 0x002E ||
    rune == 0x002D ||
    (rune >= 0x2010 && rune <= 0x2015);
