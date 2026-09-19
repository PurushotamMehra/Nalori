import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import '../models/reader_text_boundary.dart';

enum ReaderProtectedSpanKind {
  initialism,
  spacedInitials,
  number,
  version,
  domain,
  url,
  email,
  ellipsis,
  contextualAbbreviation,
  link,
  repeatedPeriodToken,
}

@immutable
class ReaderProtectedSpan {
  const ReaderProtectedSpan({
    required this.start,
    required this.end,
    required this.kind,
  });

  final int start;
  final int end;
  final ReaderProtectedSpanKind kind;

  bool containsBoundary(int offset) => start < offset && offset < end;
}

@immutable
class ReaderBoundaryCandidate {
  const ReaderBoundaryCandidate({
    required this.offset,
    required this.kind,
    required this.accepted,
    required this.reason,
  });

  final int offset;
  final ReaderTextBoundaryKind kind;
  final bool accepted;
  final String reason;
}

@immutable
class ReaderTextRange {
  const ReaderTextRange({
    required this.start,
    required this.end,
    required this.trailingBoundaryKind,
  });

  final int start;
  final int end;
  final ReaderTextBoundaryKind trailingBoundaryKind;
}

@immutable
class ReaderTextBoundaryAnalysis {
  const ReaderTextBoundaryAnalysis({
    required this.text,
    required this.protectedSpans,
    required this.sentenceCandidates,
    required this.sentenceRanges,
  });

  final String text;
  final List<ReaderProtectedSpan> protectedSpans;
  final List<ReaderBoundaryCandidate> sentenceCandidates;
  final List<ReaderTextRange> sentenceRanges;
}

class ReaderTextBoundaryService {
  const ReaderTextBoundaryService();

  static const _sentenceClosers = <String>{
    '"',
    "'",
    ')',
    ']',
    '}',
    '”',
    '’',
    '»',
  };

  static const _titles = <String>{'mr', 'mrs', 'ms', 'dr', 'prof'};
  static const _months = <String>{
    'jan',
    'feb',
    'mar',
    'apr',
    'jun',
    'jul',
    'aug',
    'sep',
    'sept',
    'oct',
    'nov',
    'dec',
  };
  static const _labels = <String>{'no', 'fig', 'vol'};
  static const _conventional = <String>{
    'jr',
    'sr',
    'vs',
    'etc',
    'rev',
    'hon',
    'gen',
    'col',
    'lt',
  };
  static const _attributionVerbs = <String>{
    'said',
    'asked',
    'cried',
    'replied',
    'returned',
    'remarked',
    'answered',
    'continued',
    'whispered',
    'shouted',
    'murmured',
    'exclaimed',
  };

  ReaderTextBoundaryAnalysis analyze(
    String text, {
    List<({int start, int end})> linkRanges = const [],
  }) {
    if (text.isEmpty) {
      return const ReaderTextBoundaryAnalysis(
        text: '',
        protectedSpans: [],
        sentenceCandidates: [],
        sentenceRanges: [],
      );
    }

    final spans = protectedSpans(text, linkRanges: linkRanges);
    final candidates = <ReaderBoundaryCandidate>[];
    final acceptedEnds = <int, ReaderTextBoundaryKind>{};

    var index = 0;
    while (index < text.length) {
      final char = text[index];
      if (!_isSentenceTerminator(char)) {
        index++;
        continue;
      }

      if (char == '.' && index + 1 < text.length && text[index + 1] == '.') {
        var runEnd = index + 1;
        while (runEnd < text.length && text[runEnd] == '.') {
          runEnd++;
        }
        for (var dot = index; dot < runEnd - 1; dot++) {
          candidates.add(
            ReaderBoundaryCandidate(
              offset: dot + 1,
              kind: ReaderTextBoundaryKind.sentence,
              accepted: false,
              reason: 'inside_protected_ellipsis',
            ),
          );
        }
        index = runEnd - 1;
      }

      final punctuationEnd = index + 1;
      final containing = spans
          .where((span) => span.containsBoundary(punctuationEnd))
          .firstOrNull;
      if (containing != null) {
        candidates.add(
          ReaderBoundaryCandidate(
            offset: punctuationEnd,
            kind: ReaderTextBoundaryKind.sentence,
            accepted: false,
            reason: 'inside_protected_${containing.kind.name}',
          ),
        );
        index++;
        continue;
      }

      var contentEnd = punctuationEnd;
      while (contentEnd < text.length &&
          _sentenceClosers.contains(text[contentEnd])) {
        contentEnd++;
      }
      final endingSpans = spans
          .where((span) => span.end == punctuationEnd)
          .toList(growable: false);
      if (endingSpans.isNotEmpty &&
          contentEnd < text.length &&
          ',;:'.contains(text[contentEnd])) {
        candidates.add(
          ReaderBoundaryCandidate(
            offset: punctuationEnd,
            kind: ReaderTextBoundaryKind.sentence,
            accepted: false,
            reason: 'protected_token_continues_with_punctuation',
          ),
        );
        index++;
        continue;
      }
      final permitsUnspaced = char == '。' || char == '！' || char == '？';
      if (contentEnd < text.length &&
          !_isWhitespace(text[contentEnd]) &&
          !permitsUnspaced) {
        candidates.add(
          ReaderBoundaryCandidate(
            offset: punctuationEnd,
            kind: ReaderTextBoundaryKind.sentence,
            accepted: false,
            reason: 'requires_whitespace_after_terminator',
          ),
        );
        index++;
        continue;
      }

      var rangeEnd = contentEnd;
      while (rangeEnd < text.length && _isWhitespace(text[rangeEnd])) {
        rangeEnd++;
      }

      final rejection = _contextualSentenceRejection(
        text,
        punctuationIndex: index,
        contentEnd: contentEnd,
        nextOffset: rangeEnd,
        endingSpans: endingSpans,
      );
      final attribution =
          contentEnd > punctuationEnd &&
          _continuesWithDialogueAttribution(text, rangeEnd);
      final accepted = rejection == null && !attribution;
      candidates.add(
        ReaderBoundaryCandidate(
          offset: punctuationEnd,
          kind: ReaderTextBoundaryKind.sentence,
          accepted: accepted,
          reason: accepted
              ? 'accepted_sentence_boundary'
              : attribution
              ? 'dialogue_attribution_continuation'
              : rejection!,
        ),
      );
      if (accepted) {
        acceptedEnds[rangeEnd] = ReaderTextBoundaryKind.sentence;
      }
      index++;
    }

    final ranges = _rangesFromEnds(
      text,
      acceptedEnds,
      defaultFinalKind: ReaderTextBoundaryKind.structural,
    );
    return ReaderTextBoundaryAnalysis(
      text: text,
      protectedSpans: List.unmodifiable(spans),
      sentenceCandidates: List.unmodifiable(candidates),
      sentenceRanges: List.unmodifiable(ranges),
    );
  }

  List<ReaderProtectedSpan> protectedSpans(
    String text, {
    List<({int start, int end})> linkRanges = const [],
  }) {
    final spans = <ReaderProtectedSpan>[];

    void collect(RegExp pattern, ReaderProtectedSpanKind kind) {
      for (final match in pattern.allMatches(text)) {
        var end = match.end;
        if (kind == ReaderProtectedSpanKind.url) {
          while (end > match.start && '.,;:!?)]}'.contains(text[end - 1])) {
            end--;
          }
        }
        if (match.start < end) {
          spans.add(
            ReaderProtectedSpan(start: match.start, end: end, kind: kind),
          );
        }
      }
    }

    collect(
      RegExp(
        r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+",
      ),
      ReaderProtectedSpanKind.email,
    );
    collect(
      RegExp(r'''(?:https?://|www\.)[^\s<>"']+''', caseSensitive: false),
      ReaderProtectedSpanKind.url,
    );
    collect(
      RegExp(r'\b(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}\b'),
      ReaderProtectedSpanKind.domain,
    );
    collect(
      RegExp(r'\bv?\d+(?:\.\d+){1,}\b', caseSensitive: false),
      ReaderProtectedSpanKind.version,
    );
    collect(
      RegExp(r'\b(?:[A-Za-z]\.){2,}'),
      ReaderProtectedSpanKind.initialism,
    );
    collect(
      RegExp(r'\b(?:[A-Za-z]\.\s+){1,}[A-Za-z]\.'),
      ReaderProtectedSpanKind.spacedInitials,
    );
    collect(RegExp(r'(?:\.{3,}|…+)'), ReaderProtectedSpanKind.ellipsis);
    collect(
      RegExp(r'\b[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+\b'),
      ReaderProtectedSpanKind.repeatedPeriodToken,
    );
    collect(
      RegExp(
        r'\b(?:Mr|Mrs|Ms|Dr|Prof|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec|No|Fig|Vol|Jr|Sr|Vs|Etc|Rev|Hon|Gen|Col|Lt)\.',
        caseSensitive: false,
      ),
      ReaderProtectedSpanKind.contextualAbbreviation,
    );
    for (final range in linkRanges) {
      final start = range.start.clamp(0, text.length);
      final end = range.end.clamp(start, text.length);
      if (start < end) {
        spans.add(
          ReaderProtectedSpan(
            start: start,
            end: end,
            kind: ReaderProtectedSpanKind.link,
          ),
        );
      }
    }

    spans.sort((left, right) {
      final start = left.start.compareTo(right.start);
      if (start != 0) return start;
      final end = right.end.compareTo(left.end);
      if (end != 0) return end;
      return left.kind.index.compareTo(right.kind.index);
    });
    return List.unmodifiable(spans);
  }

  List<ReaderTextRange> clauseRanges(
    String text, {
    List<ReaderProtectedSpan>? protectedSpans,
  }) {
    if (text.isEmpty) return const [];
    final spans = protectedSpans ?? this.protectedSpans(text);
    final ends = <int, ReaderTextBoundaryKind>{};
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char != ',' &&
          char != ';' &&
          char != ':' &&
          char != '—' &&
          char != '–') {
        continue;
      }
      final boundary = index + 1;
      if (spans.any((span) => span.containsBoundary(boundary))) continue;
      if (boundary < text.length && !_isWhitespace(text[boundary])) continue;
      var end = boundary;
      while (end < text.length && _isWhitespace(text[end])) {
        end++;
      }
      ends[end] = ReaderTextBoundaryKind.clause;
    }
    return _rangesFromEnds(
      text,
      ends,
      defaultFinalKind: ReaderTextBoundaryKind.structural,
    );
  }

  List<ReaderTextRange> wordRanges(
    String text, {
    List<ReaderProtectedSpan>? protectedSpans,
  }) {
    if (text.isEmpty) return const [];
    final spans = protectedSpans ?? this.protectedSpans(text);
    final ends = <int, ReaderTextBoundaryKind>{};
    var index = 0;
    while (index < text.length) {
      if (!_isWhitespace(text[index])) {
        index++;
        continue;
      }
      while (index < text.length && _isWhitespace(text[index])) {
        index++;
      }
      if (index < text.length &&
          !spans.any((span) => span.containsBoundary(index))) {
        ends[index] = ReaderTextBoundaryKind.word;
      }
    }
    return _rangesFromEnds(
      text,
      ends,
      defaultFinalKind: ReaderTextBoundaryKind.structural,
    );
  }

  List<ReaderTextRange> graphemeRanges(String text) {
    if (text.isEmpty) return const [];
    final ranges = <ReaderTextRange>[];
    var offset = 0;
    for (final grapheme in text.characters) {
      final end = offset + grapheme.length;
      ranges.add(
        ReaderTextRange(
          start: offset,
          end: end,
          trailingBoundaryKind: ReaderTextBoundaryKind.emergencyGrapheme,
        ),
      );
      offset = end;
    }
    return List.unmodifiable(ranges);
  }

  String? _contextualSentenceRejection(
    String text, {
    required int punctuationIndex,
    required int contentEnd,
    required int nextOffset,
    required List<ReaderProtectedSpan> endingSpans,
  }) {
    if (text[punctuationIndex] != '.') return null;
    final immediate = contentEnd < text.length ? text[contentEnd] : '';
    if (endingSpans.isNotEmpty && ',;:'.contains(immediate)) {
      return 'protected_token_continues_with_punctuation';
    }

    final token = _asciiWordBefore(text, punctuationIndex).toLowerCase();
    final nextWord = _asciiWordAt(text, nextOffset);
    final nextStartsUpper = _startsWithAsciiUpper(text, nextOffset);
    final nextStartsDigit = _startsWithAsciiDigit(text, nextOffset);

    if (_titles.contains(token) && nextWord.isNotEmpty) {
      return 'title_abbreviation_continuation';
    }
    if (_months.contains(token) && nextStartsDigit) {
      return 'month_abbreviation_continuation';
    }
    if (_labels.contains(token) && nextStartsDigit) {
      return 'label_abbreviation_continuation';
    }
    if (_conventional.contains(token) &&
        nextWord.isNotEmpty &&
        !nextStartsUpper) {
      return 'conventional_abbreviation_continuation';
    }

    for (final span in endingSpans) {
      if (span.kind == ReaderProtectedSpanKind.spacedInitials &&
          nextWord.isNotEmpty) {
        return 'spaced_initial_name_continuation';
      }
      if ((span.kind == ReaderProtectedSpanKind.initialism ||
              span.kind == ReaderProtectedSpanKind.repeatedPeriodToken) &&
          nextWord.isNotEmpty &&
          !nextStartsUpper) {
        return 'initialism_continuation';
      }
    }

    if (endingSpans.isEmpty && token.length == 1 && nextStartsUpper) {
      return 'single_initial_continuation';
    }
    return null;
  }

  bool _continuesWithDialogueAttribution(String text, int start) {
    final first = _asciiWordAt(text, start).toLowerCase();
    if (_attributionVerbs.contains(first)) return true;
    if (first != 'he' &&
        first != 'she' &&
        first != 'they' &&
        first != 'we' &&
        first != 'i') {
      return false;
    }
    var cursor = _skipWhitespace(text, start);
    while (cursor < text.length && _isAsciiLetter(text[cursor])) {
      cursor++;
    }
    return _attributionVerbs.contains(_asciiWordAt(text, cursor).toLowerCase());
  }

  List<ReaderTextRange> _rangesFromEnds(
    String text,
    Map<int, ReaderTextBoundaryKind> ends, {
    required ReaderTextBoundaryKind defaultFinalKind,
  }) {
    final ranges = <ReaderTextRange>[];
    var start = 0;
    final sortedEnds =
        ends.keys.where((end) => end > 0 && end < text.length).toList()..sort();
    for (final end in sortedEnds) {
      if (start >= end) continue;
      ranges.add(
        ReaderTextRange(
          start: start,
          end: end,
          trailingBoundaryKind: ends[end]!,
        ),
      );
      start = end;
    }
    if (start < text.length) {
      ranges.add(
        ReaderTextRange(
          start: start,
          end: text.length,
          trailingBoundaryKind: defaultFinalKind,
        ),
      );
    }
    return ranges;
  }

  static bool _isSentenceTerminator(String char) =>
      char == '.' ||
      char == '!' ||
      char == '?' ||
      char == '…' ||
      char == '。' ||
      char == '！' ||
      char == '？';

  static bool _isWhitespace(String char) => char.trim().isEmpty;

  static bool _isAsciiLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  static int _skipWhitespace(String text, int start) {
    var index = start;
    while (index < text.length && _isWhitespace(text[index])) {
      index++;
    }
    return index;
  }

  static String _asciiWordAt(String text, int start) {
    var index = _skipWhitespace(text, start);
    final wordStart = index;
    while (index < text.length && _isAsciiLetter(text[index])) {
      index++;
    }
    return text.substring(wordStart, index);
  }

  static String _asciiWordBefore(String text, int end) {
    var start = end - 1;
    while (start >= 0 && _isAsciiLetter(text[start])) {
      start--;
    }
    return text.substring(start + 1, end);
  }

  static bool _startsWithAsciiUpper(String text, int start) {
    final index = _skipWhitespace(text, start);
    if (index >= text.length) return false;
    final code = text.codeUnitAt(index);
    return code >= 65 && code <= 90;
  }

  static bool _startsWithAsciiDigit(String text, int start) {
    final index = _skipWhitespace(text, start);
    if (index >= text.length) return false;
    final code = text.codeUnitAt(index);
    return code >= 48 && code <= 57;
  }
}
