import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Types of content in a book chunk.
enum BookChunkType { text, image, milestone }

/// Semantic block roles that carry publisher-intended layout.
enum BookBlockRole {
  paragraph,
  heading,
  poem,
  stanza,
  quote,
  epigraph,
  letter,
  table,
  preformatted,
}

/// Text alignment declared by the book itself.
enum BookTextAlign { left, center, right, justify }

/// Whether this chunk belongs to front/back matter or main content.
enum ChunkSection {
  /// Non-content pages: copyright, preface, TOC, dedication, etc.
  frontMatter,

  /// Actual book content (chapters).
  content,
}

/// Inline text formatting style types.
enum InlineStyleType { bold, italic, boldItalic }

/// Represents a range of text with inline formatting (bold/italic).
@immutable
class InlineStyle {
  final int start;
  final int end;
  final InlineStyleType type;

  const InlineStyle({
    required this.start,
    required this.end,
    required this.type,
  });

  InlineStyle copyWith({int? start, int? end, InlineStyleType? type}) {
    return InlineStyle(
      start: start ?? this.start,
      end: end ?? this.end,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {'s': start, 'e': end, 't': type.index};

  factory InlineStyle.fromJson(Map<String, dynamic> json) => InlineStyle(
    start: json['s'] as int,
    end: json['e'] as int,
    type: InlineStyleType.values[json['t'] as int],
  );
}

/// A link within a text chunk.
@immutable
class LinkMetadata {
  final int start;
  final int end;
  final String url;

  const LinkMetadata({
    required this.start,
    required this.end,
    required this.url,
  });

  LinkMetadata copyWith({int? start, int? end, String? url}) {
    return LinkMetadata(
      start: start ?? this.start,
      end: end ?? this.end,
      url: url ?? this.url,
    );
  }

  Map<String, dynamic> toJson() => {'s': start, 'e': end, 'u': url};

  factory LinkMetadata.fromJson(Map<String, dynamic> json) => LinkMetadata(
    start: json['s'] as int,
    end: json['e'] as int,
    url: json['u'] as String,
  );
}

/// Represents a footnote reference within text.
@immutable
class FootnoteRef {
  /// Position in the text where the footnote marker appears.
  final int position;

  /// The footnote label (e.g., "1", "2", "*").
  final String label;

  /// The actual footnote content text.
  final String content;

  const FootnoteRef({
    required this.position,
    required this.label,
    required this.content,
  });

  Map<String, dynamic> toJson() => {'p': position, 'l': label, 'c': content};

  factory FootnoteRef.fromJson(Map<String, dynamic> json) => FootnoteRef(
    position: json['p'] as int,
    label: json['l'] as String,
    content: json['c'] as String,
  );
}

/// Maps a visible display-text span back to its source range in an original chunk.
@immutable
class ChunkSourceRange {
  final int originalChunkIndex;
  final int originalStartOffset;
  final int originalEndOffset;
  final int displayStartOffset;
  final int displayEndOffset;

  const ChunkSourceRange({
    required this.originalChunkIndex,
    required this.originalStartOffset,
    required this.originalEndOffset,
    required this.displayStartOffset,
    required this.displayEndOffset,
  });

  ChunkSourceRange shiftDisplayOffsets(int delta) => ChunkSourceRange(
    originalChunkIndex: originalChunkIndex,
    originalStartOffset: originalStartOffset,
    originalEndOffset: originalEndOffset,
    displayStartOffset: displayStartOffset + delta,
    displayEndOffset: displayEndOffset + delta,
  );

  Map<String, dynamic> toJson() => {
    'ci': originalChunkIndex,
    'os': originalStartOffset,
    'oe': originalEndOffset,
    'ds': displayStartOffset,
    'de': displayEndOffset,
  };

  factory ChunkSourceRange.fromJson(Map<String, dynamic> json) =>
      ChunkSourceRange(
        originalChunkIndex: json['ci'] as int,
        originalStartOffset: json['os'] as int,
        originalEndOffset: json['oe'] as int,
        displayStartOffset: json['ds'] as int,
        displayEndOffset: json['de'] as int,
      );
}

/// A translated range carrying both display-space and original-space offsets.
@immutable
class MappedTextRange {
  final int originalChunkIndex;
  final int originalStartOffset;
  final int originalEndOffset;
  final int displayStartOffset;
  final int displayEndOffset;

  const MappedTextRange({
    required this.originalChunkIndex,
    required this.originalStartOffset,
    required this.originalEndOffset,
    required this.displayStartOffset,
    required this.displayEndOffset,
  });

  MappedTextRange mergeWith(MappedTextRange other) => MappedTextRange(
    originalChunkIndex: originalChunkIndex,
    originalStartOffset: originalStartOffset,
    originalEndOffset: other.originalEndOffset,
    displayStartOffset: displayStartOffset,
    displayEndOffset: other.displayEndOffset,
  );
}

/// Represents a single readable chunk (card) of content from an EPUB book.
@immutable
class BookChunk {
  final int index;
  final BookChunkType type;
  final ChunkSection section;
  final String? text;
  final Uint8List? imageBytes;
  final List<LinkMetadata>? links;

  /// Inline formatting styles (bold, italic, etc.)
  final List<InlineStyle>? inlineStyles;

  /// Footnote references within this chunk's text.
  final List<FootnoteRef>? footnotes;

  /// Whether this chunk represents a heading (h1-h6).
  final bool isHeading;

  /// Whether this chunk is predominantly dialogue (>40% quote characters).
  final bool isDialogue;

  /// Semantic block role for special publisher layout.
  final BookBlockRole blockRole;

  /// Optional book-declared alignment for special blocks.
  final BookTextAlign? publisherTextAlign;

  /// Book-declared logical indentation for special blocks.
  final double publisherLeftIndent;
  final double publisherRightIndent;

  /// Preserve line breaks from the source instead of treating the block as prose.
  final bool preserveLineBreaks;

  /// Preserve whitespace more aggressively, used for preformatted content.
  final bool preserveWhitespace;

  /// The EPUB source file key this chunk was parsed from (e.g. "preface.xhtml").
  /// Used to group front-matter chunks by their originating file.
  final String? sourceFile;

  /// Mapping from display-text offsets back to original chunk offsets.
  /// Populated for rebuilt display chunks; original chunks fall back to identity.
  final List<ChunkSourceRange>? sourceRanges;

  const BookChunk({
    required this.index,
    required this.type,
    this.section = ChunkSection.content,
    this.text,
    this.imageBytes,
    this.links,
    this.inlineStyles,
    this.footnotes,
    this.isHeading = false,
    this.isDialogue = false,
    this.blockRole = BookBlockRole.paragraph,
    this.publisherTextAlign,
    this.publisherLeftIndent = 0,
    this.publisherRightIndent = 0,
    this.preserveLineBreaks = false,
    this.preserveWhitespace = false,
    this.sourceFile,
    this.sourceRanges,
  });

  bool get usesPublisherLayout =>
      blockRole != BookBlockRole.paragraph &&
      blockRole != BookBlockRole.heading;

  /// Create a copy with a different section.
  BookChunk withSection(ChunkSection newSection) => BookChunk(
    index: index,
    type: type,
    section: newSection,
    text: text,
    imageBytes: imageBytes,
    links: links,
    inlineStyles: inlineStyles,
    footnotes: footnotes,
    isHeading: isHeading,
    isDialogue: isDialogue,
    blockRole: blockRole,
    publisherTextAlign: publisherTextAlign,
    publisherLeftIndent: publisherLeftIndent,
    publisherRightIndent: publisherRightIndent,
    preserveLineBreaks: preserveLineBreaks,
    preserveWhitespace: preserveWhitespace,
    sourceFile: sourceFile,
    sourceRanges: sourceRanges,
  );

  BookChunk copyWith({
    int? index,
    BookChunkType? type,
    ChunkSection? section,
    String? text,
    Uint8List? imageBytes,
    List<LinkMetadata>? links,
    List<InlineStyle>? inlineStyles,
    List<FootnoteRef>? footnotes,
    bool? isHeading,
    bool? isDialogue,
    BookBlockRole? blockRole,
    BookTextAlign? publisherTextAlign,
    double? publisherLeftIndent,
    double? publisherRightIndent,
    bool? preserveLineBreaks,
    bool? preserveWhitespace,
    String? sourceFile,
    List<ChunkSourceRange>? sourceRanges,
  }) {
    return BookChunk(
      index: index ?? this.index,
      type: type ?? this.type,
      section: section ?? this.section,
      text: text ?? this.text,
      imageBytes: imageBytes ?? this.imageBytes,
      links: links ?? this.links,
      inlineStyles: inlineStyles ?? this.inlineStyles,
      footnotes: footnotes ?? this.footnotes,
      isHeading: isHeading ?? this.isHeading,
      isDialogue: isDialogue ?? this.isDialogue,
      blockRole: blockRole ?? this.blockRole,
      publisherTextAlign: publisherTextAlign ?? this.publisherTextAlign,
      publisherLeftIndent: publisherLeftIndent ?? this.publisherLeftIndent,
      publisherRightIndent: publisherRightIndent ?? this.publisherRightIndent,
      preserveLineBreaks: preserveLineBreaks ?? this.preserveLineBreaks,
      preserveWhitespace: preserveWhitespace ?? this.preserveWhitespace,
      sourceFile: sourceFile ?? this.sourceFile,
      sourceRanges: sourceRanges ?? this.sourceRanges,
    );
  }

  List<ChunkSourceRange> get effectiveSourceRanges {
    final chunkText = text;
    if (type != BookChunkType.text || chunkText == null || chunkText.isEmpty) {
      return const [];
    }

    final ranges = sourceRanges;
    if (ranges != null && ranges.isNotEmpty) {
      return ranges;
    }

    return [
      ChunkSourceRange(
        originalChunkIndex: index,
        originalStartOffset: 0,
        originalEndOffset: chunkText.length,
        displayStartOffset: 0,
        displayEndOffset: chunkText.length,
      ),
    ];
  }

  List<MappedTextRange> mapDisplayRangeToOriginal(
    int displayStartOffset,
    int displayEndOffset,
  ) {
    final chunkText = text;
    if (chunkText == null || chunkText.isEmpty) return const [];

    final start = math.max(0, math.min(displayStartOffset, chunkText.length));
    final end = math.max(0, math.min(displayEndOffset, chunkText.length));
    if (start >= end) return const [];

    final mapped = <MappedTextRange>[];
    for (final range in effectiveSourceRanges) {
      final overlapStart = math.max(start, range.displayStartOffset);
      final overlapEnd = math.min(end, range.displayEndOffset);
      if (overlapStart >= overlapEnd) continue;

      mapped.add(
        MappedTextRange(
          originalChunkIndex: range.originalChunkIndex,
          originalStartOffset:
              range.originalStartOffset +
              (overlapStart - range.displayStartOffset),
          originalEndOffset:
              range.originalStartOffset +
              (overlapEnd - range.displayStartOffset),
          displayStartOffset: overlapStart,
          displayEndOffset: overlapEnd,
        ),
      );
    }

    return _mergeContiguousMappedRanges(mapped);
  }

  List<MappedTextRange> mapOriginalRangeToDisplay(
    int originalChunkIndex,
    int originalStartOffset,
    int originalEndOffset,
  ) {
    if (originalStartOffset >= originalEndOffset) return const [];

    final mapped = <MappedTextRange>[];
    for (final range in effectiveSourceRanges) {
      if (range.originalChunkIndex != originalChunkIndex) continue;

      final overlapStart = math.max(
        originalStartOffset,
        range.originalStartOffset,
      );
      final overlapEnd = math.min(originalEndOffset, range.originalEndOffset);
      if (overlapStart >= overlapEnd) continue;

      mapped.add(
        MappedTextRange(
          originalChunkIndex: originalChunkIndex,
          originalStartOffset: overlapStart,
          originalEndOffset: overlapEnd,
          displayStartOffset:
              range.displayStartOffset +
              (overlapStart - range.originalStartOffset),
          displayEndOffset:
              range.displayStartOffset +
              (overlapEnd - range.originalStartOffset),
        ),
      );
    }

    return _mergeContiguousMappedRanges(mapped);
  }

  static List<MappedTextRange> _mergeContiguousMappedRanges(
    List<MappedTextRange> ranges,
  ) {
    if (ranges.length < 2) return ranges;

    final merged = <MappedTextRange>[ranges.first];
    for (final range in ranges.skip(1)) {
      final previous = merged.last;
      final canMerge =
          previous.originalChunkIndex == range.originalChunkIndex &&
          previous.originalEndOffset == range.originalStartOffset &&
          previous.displayEndOffset == range.displayStartOffset;

      if (canMerge) {
        merged[merged.length - 1] = previous.mergeWith(range);
      } else {
        merged.add(range);
      }
    }

    return merged;
  }

  // ─── Serialization (compact keys to reduce cache size) ─────────

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'i': index,
      't': type.index,
      'sc': section.index,
    };
    if (text != null) map['tx'] = text;
    if (imageBytes != null) map['img'] = base64Encode(imageBytes!);
    if (links != null && links!.isNotEmpty) {
      map['lk'] = links!.map((l) => l.toJson()).toList();
    }
    if (inlineStyles != null && inlineStyles!.isNotEmpty) {
      map['is'] = inlineStyles!.map((s) => s.toJson()).toList();
    }
    if (footnotes != null && footnotes!.isNotEmpty) {
      map['fn'] = footnotes!.map((f) => f.toJson()).toList();
    }
    if (isHeading) map['h'] = true;
    if (isDialogue) map['dl'] = true;
    if (blockRole != BookBlockRole.paragraph) map['br'] = blockRole.index;
    if (publisherTextAlign != null) map['pa'] = publisherTextAlign!.index;
    if (publisherLeftIndent != 0) map['pli'] = publisherLeftIndent;
    if (publisherRightIndent != 0) map['pri'] = publisherRightIndent;
    if (preserveLineBreaks) map['plb'] = true;
    if (preserveWhitespace) map['pw'] = true;
    if (sourceFile != null) map['sf'] = sourceFile;
    if (sourceRanges != null && sourceRanges!.isNotEmpty) {
      map['sr'] = sourceRanges!.map((r) => r.toJson()).toList();
    }
    return map;
  }

  factory BookChunk.fromJson(Map<String, dynamic> json) {
    return BookChunk(
      index: json['i'] as int,
      type: BookChunkType.values[json['t'] as int],
      section: ChunkSection.values[json['sc'] as int],
      text: json['tx'] as String?,
      imageBytes: json['img'] != null
          ? base64Decode(json['img'] as String)
          : null,
      links: json['lk'] != null
          ? (json['lk'] as List)
                .map((e) => LinkMetadata.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
      inlineStyles: json['is'] != null
          ? (json['is'] as List)
                .map((e) => InlineStyle.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
      footnotes: json['fn'] != null
          ? (json['fn'] as List)
                .map((e) => FootnoteRef.fromJson(e as Map<String, dynamic>))
                .toList()
          : null,
      isHeading: json['h'] == true,
      isDialogue: json['dl'] == true,
      blockRole: json['br'] != null
          ? BookBlockRole.values[json['br'] as int]
          : BookBlockRole.paragraph,
      publisherTextAlign: json['pa'] != null
          ? BookTextAlign.values[json['pa'] as int]
          : null,
      publisherLeftIndent: (json['pli'] as num?)?.toDouble() ?? 0,
      publisherRightIndent: (json['pri'] as num?)?.toDouble() ?? 0,
      preserveLineBreaks: json['plb'] == true,
      preserveWhitespace: json['pw'] == true,
      sourceFile: json['sf'] as String?,
      sourceRanges: json['sr'] != null
          ? (json['sr'] as List)
                .map(
                  (e) => ChunkSourceRange.fromJson(e as Map<String, dynamic>),
                )
                .toList()
          : null,
    );
  }
}
