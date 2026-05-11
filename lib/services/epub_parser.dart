import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:epubx/epubx.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../models/book_chunk.dart';
import '../models/bookmark.dart';

/// Service responsible for loading, parsing, and chunking EPUB content.
///
/// Produces small, paragraph-sized chunks for a TikTok/Reels-style
/// vertical-swipe reading experience. Each card holds roughly one paragraph
/// so the reader never feels overwhelmed.
/// Top-level function for Isolate.run — creates a fresh service
/// instance inside the isolate and parses the raw EPUB bytes.
/// Must be top-level (not a closure) for isolate compatibility.
Future<
  ({
    String title,
    List<BookChunk> chunks,
    Map<String, int> anchorMap,
    List<ChapterInfo> chapters,
    Map<String, List<int>> searchIndex,
  })
>
_parseInIsolate(Uint8List bytes) {
  final service = EpubParserService();
  return service._parseBytes(bytes);
}

const _dialogueQuoteChars = ['"', '\u201C', '\u201D', '\u00AB', '\u00BB'];
const _dialogueLeadChars = [
  '"',
  '\u201C',
  '\u201D',
  '\u00AB',
  '\u00BB',
  '\u2014',
];

@visibleForTesting
bool isLikelyDialogueText(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.length < 8) return false;

  int doubleQuoteCount = 0;
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    if (_dialogueQuoteChars.contains(char)) {
      doubleQuoteCount++;
    }
  }

  final startsLikeDialogue = _dialogueLeadChars.any(trimmed.startsWith);
  if (doubleQuoteCount == 0) {
    return startsLikeDialogue;
  }

  final quoteRatio = doubleQuoteCount / text.length;
  if (quoteRatio > 0.03) {
    return true;
  }

  return startsLikeDialogue && doubleQuoteCount >= 2;
}

class EpubParserService {
  /// Target maximum words per card — keeps each card short and digestible.
  static const int _targetWords = 50;

  /// Hard ceiling — if a single paragraph exceeds this, it gets split.
  static const int _hardMaxWords = 80;

  /// Common abbreviations that should NOT trigger sentence breaks.
  static const _abbreviations = <String>{
    'mr',
    'mrs',
    'ms',
    'dr',
    'prof',
    'sr',
    'jr',
    'st',
    'ave',
    'blvd',
    'dept',
    'est',
    'govt',
    'inc',
    'ltd',
    'gen',
    'sgt',
    'cpl',
    'pvt',
    'rev',
    'hon',
    'pres',
    'gov',
    'ofc',
    'etc',
    'vol',
    'vs',
    'fig',
    'approx',
  };

  /// Dotted abbreviations like U.S., e.g., i.e.
  static const _dottedAbbreviations = <String>{
    'u.s',
    'u.k',
    'u.n',
    'e.g',
    'i.e',
    'a.m',
    'p.m',
    'a.d',
    'b.c',
    'ph.d',
    'm.d',
    'd.c',
  };

  // ─── Public API ──────────────────────────────────────────────────────

  /// Parses an EPUB file in a background [Isolate] so the main
  /// thread stays free for UI rendering at 60 FPS.
  ///
  /// Reads file bytes on the main thread (fast I/O), then sends
  /// them to an isolate for the heavy parsing work.
  static Future<
    ({
      String title,
      List<BookChunk> chunks,
      Map<String, int> anchorMap,
      List<ChapterInfo> chapters,
      Map<String, List<int>> searchIndex,
    })
  >
  parseFileInBackground(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    return Isolate.run(() => _parseInIsolate(bytes));
  }

  /// Loads the EPUB file from the given [assetPath] (asset bundle).
  Future<
    ({
      String title,
      List<BookChunk> chunks,
      Map<String, int> anchorMap,
      List<ChapterInfo> chapters,
      Map<String, List<int>> searchIndex,
    })
  >
  loadAndParse(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    return _parseBytes(bytes);
  }

  /// Loads the EPUB file from a local [File].
  Future<
    ({
      String title,
      List<BookChunk> chunks,
      Map<String, int> anchorMap,
      List<ChapterInfo> chapters,
      Map<String, List<int>> searchIndex,
    })
  >
  loadAndParseFromFile(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    return _parseBytes(bytes);
  }

  // ─── Core parsing ────────────────────────────────────────────────────

  Future<
    ({
      String title,
      List<BookChunk> chunks,
      Map<String, int> anchorMap,
      List<ChapterInfo> chapters,
      Map<String, List<int>> searchIndex,
    })
  >
  _parseBytes(Uint8List bytes) async {
    final EpubBook book = await EpubReader.readBook(bytes);
    final String title = book.Title ?? 'Unknown Title';

    try {
      final result = _extractContent(book);
      if (kDebugMode) {
        debugPrint(
          'EpubParser: parsed "$title" -> ${result.chunks.length} chunks, '
          '${result.anchorMap.length} anchors, ${result.chapters.length} chapters',
        );
      }

      if (result.chunks.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'EpubParser: DOM parsing produced 0 chunks, trying fallback',
          );
        }
        final fallback = _fallbackExtract(book);
        return (
          title: title,
          chunks: fallback,
          anchorMap: <String, int>{},
          chapters: <ChapterInfo>[],
          searchIndex: <String, List<int>>{},
        );
      }
      return (
        title: title,
        chunks: result.chunks,
        anchorMap: result.anchorMap,
        chapters: result.chapters,
        searchIndex: result.searchIndex,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('EpubParser: _extractContent failed: $e\n$stack');
      }
      final fallback = _fallbackExtract(book);
      return (
        title: title,
        chunks: fallback,
        anchorMap: <String, int>{},
        chapters: <ChapterInfo>[],
        searchIndex: <String, List<int>>{},
      );
    }
  }

  // ─── Front-matter detection ────────────────────────────────────────

  /// Filename patterns that indicate a file is NOT main book content.
  static const _frontMatterFilePatterns = [
    'cover',
    'title',
    'titlepage',
    'copyright',
    'rights',
    'dedication',
    'epigraph',
    'foreword',
    'preface',
    'prologue',
    'acknowledgment',
    'acknowledgement',
    'about',
    'also',
    'toc',
    'contents',
    'nav',
    'index',
    'half-title',
    'halftitle',
    'frontispiece',
    'colophon',
    'publisher',
    'edition',
    'isbn',
    'introduction',
    'frontmatter',
    'backmatter',
    'endnotes',
    'appendix',
    'glossary',
    'bibliography',
  ];

  /// Check whether a content-map key (HTML filename) looks like front matter.
  bool _isFrontMatterFile(String key) {
    final lower = p
        .basename(key)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _frontMatterFilePatterns.any(
      (pat) => lower.contains(pat.replaceAll('-', '')),
    );
  }

  /// Determine the first content-map key that is actual book content,
  /// by also consulting the EPUB's Table of Contents chapter titles.
  String? _findFirstContentKey(
    Map<String, EpubTextContentFile> contentMap,
    EpubBook book,
  ) {
    // Gather the set of content filenames referenced by TOC chapters
    // whose titles look like real chapters (i.e. NOT front matter).
    final tocChapters = book.Chapters ?? [];
    final chapterFiles = <String>{};

    void collectChapterFiles(List<EpubChapter> chapters) {
      for (final ch in chapters) {
        final title = (ch.Title ?? '').toLowerCase().trim();
        final isFM = _frontMatterFilePatterns.any((pat) => title.contains(pat));
        if (!isFM && ch.ContentFileName != null) {
          chapterFiles.add(ch.ContentFileName!);
          chapterFiles.add(p.basename(ch.ContentFileName!));
        }
        if (ch.SubChapters != null) collectChapterFiles(ch.SubChapters!);
      }
    }

    collectChapterFiles(tocChapters);

    // Walk the content map in order; first key that is either:
    // (a) referenced by a real TOC chapter, or
    // (b) does NOT match any front-matter filename pattern
    // … is our first content file.
    for (final key in contentMap.keys) {
      final baseName = p.basename(key);
      if (chapterFiles.contains(key) || chapterFiles.contains(baseName)) {
        return key;
      }
    }
    // Fallback: first file that doesn't look like front matter by name.
    for (final key in contentMap.keys) {
      if (!_isFrontMatterFile(key)) return key;
    }
    return contentMap.keys.firstOrNull;
  }

  // ─── DOM-based extraction ────────────────────────────────────────────

  ({
    List<BookChunk> chunks,
    Map<String, int> anchorMap,
    List<ChapterInfo> chapters,
    Map<String, List<int>> searchIndex,
  })
  _extractContent(EpubBook book) {
    final List<BookChunk> chunks = [];
    final Map<String, int> anchorMap = {};
    final Map<String, List<int>> searchIndex = {};
    int chunkIndex = 0;

    final contentMap = book.Content?.Html;
    if (contentMap == null || contentMap.isEmpty) {
      return (
        chunks: chunks,
        anchorMap: anchorMap,
        chapters: <ChapterInfo>[],
        searchIndex: searchIndex,
      );
    }

    // Determine which key marks the start of real content.
    final firstContentKey = _findFirstContentKey(contentMap, book);
    bool reachedContent = false;

    // Current card buffer.
    final StringBuffer textBuffer = StringBuffer();
    final List<LinkMetadata> linkBuffer = [];
    final List<InlineStyle> styleBuffer = [];
    final List<FootnoteRef> footnoteBuffer = [];
    // Track the section for the current file being parsed.
    ChunkSection currentSection = ChunkSection.frontMatter;
    // Track the current source file key for grouping.
    String currentKey = '';
    // Track if parsing inside a heading tag (h1-h6).
    bool currentIsHeading = false;

    // ── Inline style tracking (D-9) ──
    final List<InlineStyleType> activeStyles = [];

    InlineStyleType? currentStyle() {
      if (activeStyles.isEmpty) return null;
      bool hasBold = false;
      bool hasItalic = false;
      for (final s in activeStyles) {
        if (s == InlineStyleType.bold || s == InlineStyleType.boldItalic) {
          hasBold = true;
        }
        if (s == InlineStyleType.italic || s == InlineStyleType.boldItalic) {
          hasItalic = true;
        }
      }
      if (hasBold && hasItalic) return InlineStyleType.boldItalic;
      if (hasBold) return InlineStyleType.bold;
      if (hasItalic) return InlineStyleType.italic;
      return null;
    }

    // ── List tracking (D-10) ──
    int olCounter = 0;
    bool insideOl = false;
    bool insideUl = false;

    // ── Verse/poetry tracking (D-12) ──
    bool insideVerse = false;
    BookBlockRole currentBlockRole = BookBlockRole.paragraph;
    BookTextAlign? currentPublisherTextAlign;
    double currentPublisherLeftIndent = 0;
    double currentPublisherRightIndent = 0;
    bool currentPreserveLineBreaks = false;
    bool currentPreserveWhitespace = false;

    String classText(dom.Element node) =>
        (node.attributes['class'] ?? '').toLowerCase();

    BookTextAlign? parseTextAlign(dom.Element node) {
      final style = (node.attributes['style'] ?? '').toLowerCase();
      if (style.contains(RegExp(r'text-align\s*:\s*center'))) {
        return BookTextAlign.center;
      }
      if (style.contains(RegExp(r'text-align\s*:\s*right'))) {
        return BookTextAlign.right;
      }
      if (style.contains(RegExp(r'text-align\s*:\s*justify'))) {
        return BookTextAlign.justify;
      }
      if (style.contains(RegExp(r'text-align\s*:\s*left'))) {
        return BookTextAlign.left;
      }

      final classes = classText(node);
      if (classes.contains(RegExp(r'(^|[-_\s])center(ed)?($|[-_\s])'))) {
        return BookTextAlign.center;
      }
      if (classes.contains(RegExp(r'(^|[-_\s])right($|[-_\s])'))) {
        return BookTextAlign.right;
      }
      if (classes.contains(RegExp(r'(^|[-_\s])justify($|[-_\s])'))) {
        return BookTextAlign.justify;
      }
      if (classes.contains(RegExp(r'(^|[-_\s])left($|[-_\s])'))) {
        return BookTextAlign.left;
      }
      return null;
    }

    double? parseCssLength(dom.Element node, String property) {
      final style = (node.attributes['style'] ?? '').toLowerCase();
      final match = RegExp('$property\\s*:\\s*([^;]+)').firstMatch(style);
      if (match == null) return null;

      final rawValue = match.group(1)!.trim();
      final valueMatch = RegExp(r'-?\d+(\.\d+)?').firstMatch(rawValue);
      if (valueMatch == null) return null;

      final value = double.tryParse(valueMatch.group(0)!);
      if (value == null || value <= 0) return null;

      final pxValue = rawValue.contains('em') || rawValue.contains('rem')
          ? value * 16
          : rawValue.contains('%')
          ? value * 0.4
          : value;
      return pxValue.clamp(0, 72).toDouble();
    }

    BookBlockRole? detectBlockRole(dom.Element node) {
      final tag = node.localName;
      final classes = classText(node);
      final epubType = (node.attributes['epub:type'] ?? '').toLowerCase();
      final role = (node.attributes['role'] ?? '').toLowerCase();
      final markers = '$classes $epubType $role';

      if (tag == 'pre') return BookBlockRole.preformatted;
      if (tag == 'blockquote') return BookBlockRole.quote;
      if (markers.contains('epigraph')) return BookBlockRole.epigraph;
      if (markers.contains('stanza')) return BookBlockRole.stanza;
      if (markers.contains('verse') ||
          markers.contains('poem') ||
          markers.contains('poetry')) {
        return BookBlockRole.poem;
      }
      if (markers.contains('letter') || markers.contains('correspondence')) {
        return BookBlockRole.letter;
      }
      return null;
    }

    ({double left, double right}) defaultIndentFor(BookBlockRole role) {
      return switch (role) {
        BookBlockRole.quote => (left: 20.0, right: 16.0),
        BookBlockRole.epigraph => (left: 24.0, right: 24.0),
        BookBlockRole.letter => (left: 12.0, right: 8.0),
        BookBlockRole.table => (left: 0.0, right: 0.0),
        BookBlockRole.poem ||
        BookBlockRole.stanza ||
        BookBlockRole.preformatted => (left: 0.0, right: 0.0),
        BookBlockRole.paragraph ||
        BookBlockRole.heading => (left: 0.0, right: 0.0),
      };
    }

    // ── Footnote content storage (D-13) ──
    final Map<String, String> footnoteContentMap = {};

    void prescanFootnotes(dom.Element body) {
      for (final el in body.querySelectorAll('[id]')) {
        final id = el.id;
        if (id.isEmpty) continue;
        if (id.startsWith('fn') ||
            id.startsWith('note') ||
            id.startsWith('footnote') ||
            id.startsWith('endnote')) {
          final text = el.text.trim();
          if (text.isNotEmpty) {
            footnoteContentMap[id] = text;
          }
        }
      }
    }

    // Flush the buffer into a new card chunk.
    void flush() {
      if (textBuffer.isEmpty) return;
      final rawText = textBuffer.toString();
      final text = rawText.trim();
      if (text.isEmpty) {
        textBuffer.clear();
        linkBuffer.clear();
        styleBuffer.clear();
        footnoteBuffer.clear();
        return;
      }

      // Adjust offsets for trimmed leading whitespace.
      final leadingWs = rawText.length - rawText.trimLeft().length;
      final adjustedStyles = styleBuffer
          .map((s) {
            final ns = (s.start - leadingWs).clamp(0, text.length);
            final ne = (s.end - leadingWs).clamp(0, text.length);
            if (ns >= ne) return null;
            return s.copyWith(start: ns, end: ne);
          })
          .whereType<InlineStyle>()
          .toList();

      final adjustedFootnotes = footnoteBuffer.map((f) {
        final np = (f.position - leadingWs).clamp(0, text.length);
        return FootnoteRef(position: np, label: f.label, content: f.content);
      }).toList();

      final detectedDialogue = !currentIsHeading && isLikelyDialogueText(text);
      final chunkRole = currentIsHeading
          ? BookBlockRole.heading
          : currentBlockRole;

      if (_wordCount(text) <= _hardMaxWords ||
          chunkRole != BookBlockRole.paragraph) {
        chunks.add(
          BookChunk(
            index: chunkIndex++,
            type: BookChunkType.text,
            text: text,
            section: currentSection,
            sourceFile: currentKey,
            links: List.from(linkBuffer),
            inlineStyles: adjustedStyles.isNotEmpty ? adjustedStyles : null,
            footnotes: adjustedFootnotes.isNotEmpty ? adjustedFootnotes : null,
            isHeading: currentIsHeading,
            isDialogue: detectedDialogue,
            blockRole: chunkRole,
            publisherTextAlign: currentPublisherTextAlign,
            publisherLeftIndent: currentPublisherLeftIndent,
            publisherRightIndent: currentPublisherRightIndent,
            preserveLineBreaks: currentPreserveLineBreaks,
            preserveWhitespace: currentPreserveWhitespace,
          ),
        );
      } else {
        // Text is too large — split by sentence, drop links/styles/footnotes.
        final subTexts = _splitBySentence(text, _targetWords);
        for (final sub in subTexts) {
          chunks.add(
            BookChunk(
              index: chunkIndex++,
              type: BookChunkType.text,
              text: sub,
              section: currentSection,
              sourceFile: currentKey,
              isHeading: currentIsHeading,
              isDialogue: detectedDialogue,
              blockRole: chunkRole,
              publisherTextAlign: currentPublisherTextAlign,
              publisherLeftIndent: currentPublisherLeftIndent,
              publisherRightIndent: currentPublisherRightIndent,
              preserveLineBreaks: currentPreserveLineBreaks,
              preserveWhitespace: currentPreserveWhitespace,
            ),
          );
        }
      }
      textBuffer.clear();
      linkBuffer.clear();
      styleBuffer.clear();
      footnoteBuffer.clear();
    }

    if (kDebugMode) {
      debugPrint('EpubParser: HTML content entries = ${contentMap.length}');
      debugPrint('EpubParser: first content key = $firstContentKey');
    }

    for (final entry in contentMap.entries) {
      final key = entry.key;
      final htmlContent = entry.value;
      final htmlString = htmlContent.Content;
      if (htmlString == null || htmlString.isEmpty) continue;

      currentKey = key;

      if (!reachedContent) {
        if (key == firstContentKey ||
            p.basename(key) ==
                (firstContentKey != null ? p.basename(firstContentKey) : '')) {
          reachedContent = true;
          currentSection = ChunkSection.content;
        } else {
          currentSection = ChunkSection.frontMatter;
        }
      } else {
        currentSection = _isFrontMatterFile(key)
            ? ChunkSection.frontMatter
            : ChunkSection.content;
      }

      try {
        final document = html_parser.parse(htmlString);
        final body = document.body;
        if (body == null) continue;

        // Pre-scan for footnote content in this chapter (D-13).
        prescanFootnotes(body);

        // Recursive DOM walker.
        void visit(dom.Node node) {
          if (node is dom.Element) {
            void recordAnchor(String anchor) {
              final decodedAnchor = _decodeUriValue(anchor).trim();
              if (decodedAnchor.isEmpty) return;

              anchorMap[decodedAnchor] = chunkIndex;
              if (currentKey.isNotEmpty) {
                anchorMap['$currentKey#$decodedAnchor'] = chunkIndex;
                anchorMap['${p.basename(currentKey)}#$decodedAnchor'] =
                    chunkIndex;
              }
            }

            if (node.id.isNotEmpty) {
              recordAnchor(node.id);
            }
            final nameAttr = node.attributes['name'];
            if (nameAttr != null && nameAttr.isNotEmpty) {
              recordAnchor(nameAttr);
            }

            final tag = node.localName;
            final detectedRole = detectBlockRole(node);
            if (detectedRole != null) {
              flush();

              final previousRole = currentBlockRole;
              final previousAlign = currentPublisherTextAlign;
              final previousLeftIndent = currentPublisherLeftIndent;
              final previousRightIndent = currentPublisherRightIndent;
              final previousPreserveLineBreaks = currentPreserveLineBreaks;
              final previousPreserveWhitespace = currentPreserveWhitespace;
              final wasInsideVerse = insideVerse;

              final defaultIndent = defaultIndentFor(detectedRole);
              currentBlockRole = detectedRole;
              currentPublisherTextAlign =
                  parseTextAlign(node) ??
                  previousAlign ??
                  (detectedRole == BookBlockRole.epigraph
                      ? BookTextAlign.center
                      : null);
              currentPublisherLeftIndent =
                  parseCssLength(node, 'margin-left') ?? defaultIndent.left;
              currentPublisherRightIndent =
                  parseCssLength(node, 'margin-right') ?? defaultIndent.right;
              currentPreserveLineBreaks =
                  detectedRole == BookBlockRole.poem ||
                  detectedRole == BookBlockRole.stanza ||
                  detectedRole == BookBlockRole.preformatted ||
                  previousPreserveLineBreaks;
              currentPreserveWhitespace =
                  detectedRole == BookBlockRole.preformatted ||
                  previousPreserveWhitespace;
              insideVerse = insideVerse || currentPreserveLineBreaks;

              for (final child in node.nodes) {
                visit(child);
              }
              flush();

              currentBlockRole = previousRole;
              currentPublisherTextAlign = previousAlign;
              currentPublisherLeftIndent = previousLeftIndent;
              currentPublisherRightIndent = previousRightIndent;
              currentPreserveLineBreaks = previousPreserveLineBreaks;
              currentPreserveWhitespace = previousPreserveWhitespace;
              insideVerse = wasInsideVerse;
              return;
            }

            // ── Images (D-16) ──
            if (tag == 'img') {
              final src = node.attributes['src'];
              if (src != null) {
                final imageBytes = _resolveImage(book, src);
                if (imageBytes != null) {
                  flush();
                  chunks.add(
                    BookChunk(
                      index: chunkIndex++,
                      type: BookChunkType.image,
                      section: currentSection,
                      sourceFile: currentKey,
                      imageBytes: imageBytes,
                    ),
                  );
                }
              }
              return;
            }

            // ── SVG — skip ──
            if (tag == 'svg') return;

            // ── Links (<a>) with footnote detection (D-13) ──
            if (tag == 'a' && node.attributes.containsKey('href')) {
              final href = node.attributes['href']!;

              final epubType = node.attributes['epub:type'] ?? '';
              final isFootnoteLink =
                  epubType == 'noteref' ||
                  href.contains('#fn') ||
                  href.contains('#note') ||
                  href.contains('#footnote') ||
                  href.contains('#endnote');

              if (isFootnoteLink) {
                final anchor = href.contains('#') ? href.split('#').last : '';
                final fnContent = footnoteContentMap[anchor];
                if (fnContent != null && fnContent.isNotEmpty) {
                  final label = node.text.trim();
                  final displayLabel = label.isNotEmpty ? label : '*';
                  footnoteBuffer.add(
                    FootnoteRef(
                      position: textBuffer.length,
                      label: displayLabel,
                      content: fnContent,
                    ),
                  );
                  textBuffer.write('[$displayLabel]');
                  return;
                }
              }

              final startIdx = textBuffer.length;
              for (final child in node.nodes) {
                visit(child);
              }
              final endIdx = textBuffer.length;
              if (endIdx > startIdx) {
                linkBuffer.add(
                  LinkMetadata(start: startIdx, end: endIdx, url: href),
                );
              }
              return;
            }

            // ── <br> — inline line break ──
            if (tag == 'br') {
              textBuffer.write('\n');
              return;
            }

            // ── Tables (D-14) ──
            if (tag == 'table') {
              flush();
              final tableText = _renderTable(node);
              if (tableText.isNotEmpty) {
                chunks.add(
                  BookChunk(
                    index: chunkIndex++,
                    type: BookChunkType.text,
                    text: tableText,
                    section: currentSection,
                    sourceFile: currentKey,
                    blockRole: BookBlockRole.table,
                    preserveLineBreaks: true,
                  ),
                );
              }
              return;
            }

            // ── Inline style tags: bold (D-9) ──
            if (tag == 'b' || tag == 'strong') {
              activeStyles.add(InlineStyleType.bold);
              final startPos = textBuffer.length;
              for (final child in node.nodes) {
                visit(child);
              }
              final endPos = textBuffer.length;
              activeStyles.removeLast();
              if (endPos > startPos) {
                styleBuffer.add(
                  InlineStyle(
                    start: startPos,
                    end: endPos,
                    type: InlineStyleType.bold,
                  ),
                );
              }
              return;
            }

            // ── Inline style tags: italic (D-9) ──
            if (tag == 'i' || tag == 'em' || tag == 'cite') {
              activeStyles.add(InlineStyleType.italic);
              final startPos = textBuffer.length;
              for (final child in node.nodes) {
                visit(child);
              }
              final endPos = textBuffer.length;
              activeStyles.removeLast();
              if (endPos > startPos) {
                styleBuffer.add(
                  InlineStyle(
                    start: startPos,
                    end: endPos,
                    type: InlineStyleType.italic,
                  ),
                );
              }
              return;
            }

            // ── Lists (D-10) ──
            if (tag == 'ul') {
              flush();
              final wasUl = insideUl;
              insideUl = true;
              for (final child in node.nodes) {
                visit(child);
              }
              insideUl = wasUl;
              flush();
              return;
            }

            if (tag == 'ol') {
              flush();
              final wasOl = insideOl;
              final prevCounter = olCounter;
              insideOl = true;
              olCounter = 0;
              for (final child in node.nodes) {
                visit(child);
              }
              insideOl = wasOl;
              olCounter = prevCounter;
              flush();
              return;
            }

            if (tag == 'li') {
              if (textBuffer.isNotEmpty &&
                  !textBuffer.toString().endsWith('\n')) {
                textBuffer.write('\n');
              }
              if (insideOl) {
                olCounter++;
                textBuffer.write('$olCounter. ');
              } else if (insideUl) {
                textBuffer.write('• ');
              }
              for (final child in node.nodes) {
                visit(child);
              }
              return;
            }

            // ── Verse/poetry detection (D-12) ──
            final classes = node.attributes['class'] ?? '';
            final isVerseBlock =
                tag == 'pre' ||
                classes.contains('verse') ||
                classes.contains('poem') ||
                classes.contains('stanza') ||
                classes.contains('poetry');

            if (isVerseBlock && !insideVerse) {
              flush();
              insideVerse = true;
              for (final child in node.nodes) {
                visit(child);
              }
              insideVerse = false;
              flush();
              return;
            }

            // ── Block elements → flush BEFORE entering ──
            final isBlock = _blockTags.contains(tag);
            final isHeadingNode = [
              'h1',
              'h2',
              'h3',
              'h4',
              'h5',
              'h6',
            ].contains(tag);

            if (isBlock && !insideVerse) {
              flush();
            }

            final wasHeading = currentIsHeading;
            if (isHeadingNode) currentIsHeading = true;

            for (final child in node.nodes) {
              visit(child);
            }

            if (isBlock && !insideVerse) {
              flush();
            }
            if (isHeadingNode) currentIsHeading = wasHeading;
          } else if (node is dom.Text) {
            String text;
            if (currentPreserveWhitespace) {
              text = node.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
            } else if (insideVerse || currentPreserveLineBreaks) {
              text = node.text
                  .replaceAll('\r\n', '\n')
                  .replaceAll('\r', '\n')
                  .replaceAll(RegExp(r'[ \t]+'), ' ');
            } else {
              text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            }
            if (text.isNotEmpty) {
              final style = currentStyle();
              final startPos = textBuffer.length;

              if (!insideVerse) {
                if (textBuffer.isNotEmpty &&
                    !textBuffer.toString().endsWith(' ') &&
                    !textBuffer.toString().endsWith('\n')) {
                  textBuffer.write(' ');
                }
              }
              textBuffer.write(text);

              if (style != null) {
                final endPos = textBuffer.length;
                styleBuffer.add(
                  InlineStyle(start: startPos, end: endPos, type: style),
                );
              }
            }
          }
        }

        visit(body);
        flush(); // end of chapter
      } catch (e) {
        if (kDebugMode) {
          debugPrint('EpubParser: error parsing chapter: $e');
        }
      }
    }

    // Merge tiny chunks (< 10 words) with the next chunk to avoid
    // cards with just one or two words.
    final mergeResult = _mergeTinyChunks(chunks);
    final merged = mergeResult.chunks;
    final mergedAnchorMap = _remapAnchorMap(
      anchorMap,
      mergeResult.originalToMerged,
    );

    // Extract chapters from EPUB Table of Contents.
    final chapters = _extractTocChapters(book, merged, mergedAnchorMap);

    // Log section breakdown.
    final fmCount = merged
        .where((c) => c.section == ChunkSection.frontMatter)
        .length;
    final contentCount = merged
        .where((c) => c.section == ChunkSection.content)
        .length;
    if (kDebugMode) {
      debugPrint(
        'EpubParser: $fmCount front-matter chunks, $contentCount content chunks',
      );
    }

    // Build the search index
    // Note: Search Index generation has been moved out of eager load.
    // We return an empty map to speed up EPUB load by ~2x.
    // It can be generated lazily later.
    return (
      chunks: merged,
      anchorMap: mergedAnchorMap,
      chapters: chapters,
      searchIndex: <String, List<int>>{},
    );
  }

  /// Generates a search index from a list of chunks. This should be run in a background isolate.
  static Future<Map<String, List<int>>> buildSearchIndexInBackground(
    List<BookChunk> chunks,
  ) async {
    return Isolate.run(() {
      final Map<String, List<int>> index = {};
      for (final chunk in chunks) {
        if (chunk.type != BookChunkType.text) continue;
        final text = chunk.text ?? '';
        if (text.isEmpty) continue;

        final wordsInChunk = <String>{};
        final words = text.toLowerCase().split(RegExp(r'\s+'));
        for (final word in words) {
          final cleanWord = word.replaceAll(RegExp(r'^[\W_]+|[\W_]+$'), '');
          if (cleanWord.isEmpty) continue;
          if (!wordsInChunk.add(cleanWord)) continue;

          index.putIfAbsent(cleanWord, () => []).add(chunk.index);
        }
      }
      return index;
    });
  }

  // ─── Post-processing ─────────────────────────────────────────────────

  /// Merge very small consecutive text chunks so we don't get 1-word cards.
  ({List<BookChunk> chunks, Map<int, int> originalToMerged}) _mergeTinyChunks(
    List<BookChunk> input,
  ) {
    if (input.isEmpty) {
      return (chunks: input, originalToMerged: <int, int>{});
    }

    final List<BookChunk> result = [];
    final Map<int, int> originalToMerged = {};
    ({BookChunk chunk, List<int> sourceIndices})? pending;
    int idx = 0;

    void emitPending() {
      final value = pending;
      if (value == null) return;

      final mergedIndex = idx++;
      for (final sourceIndex in value.sourceIndices) {
        originalToMerged[sourceIndex] = mergedIndex;
      }
      result.add(value.chunk.copyWith(index: mergedIndex));
      pending = null;
    }

    for (final chunk in input) {
      if (chunk.type != BookChunkType.text) {
        // Flush pending, then add the image.
        emitPending();
        final mergedIndex = idx++;
        originalToMerged[chunk.index] = mergedIndex;
        result.add(chunk.copyWith(index: mergedIndex));
        continue;
      }

      final text = chunk.text ?? '';
      if (text.isEmpty) continue;

      if (pending == null) {
        pending = (chunk: chunk, sourceIndices: [chunk.index]);
        continue;
      }

      final pendingValue = pending!;
      final pendingChunk = pendingValue.chunk;
      final pendingText = pendingChunk.text ?? '';
      final pendingWords = _wordCount(pendingText);
      final chunkWords = _wordCount(text);
      final matchingPublisherLayout =
          pendingChunk.blockRole == chunk.blockRole &&
          pendingChunk.publisherTextAlign == chunk.publisherTextAlign &&
          pendingChunk.publisherLeftIndent == chunk.publisherLeftIndent &&
          pendingChunk.publisherRightIndent == chunk.publisherRightIndent &&
          pendingChunk.preserveLineBreaks == chunk.preserveLineBreaks &&
          pendingChunk.preserveWhitespace == chunk.preserveWhitespace;

      // Only merge chunks from the same section AND same source file. Do not merge headings with normal text
      if (pendingWords < 15 &&
          (pendingWords + chunkWords) <= _hardMaxWords &&
          pendingChunk.section == chunk.section &&
          pendingChunk.sourceFile == chunk.sourceFile &&
          pendingChunk.isHeading == chunk.isHeading &&
          matchingPublisherLayout) {
        pending = (
          chunk: BookChunk(
            index: 0, // re-index later
            type: BookChunkType.text,
            section: pendingChunk.section,
            sourceFile: pendingChunk.sourceFile,
            isHeading: pendingChunk.isHeading,
            isDialogue: pendingChunk.isDialogue || chunk.isDialogue,
            blockRole: pendingChunk.blockRole,
            publisherTextAlign: pendingChunk.publisherTextAlign,
            publisherLeftIndent: pendingChunk.publisherLeftIndent,
            publisherRightIndent: pendingChunk.publisherRightIndent,
            preserveLineBreaks: pendingChunk.preserveLineBreaks,
            preserveWhitespace: pendingChunk.preserveWhitespace,
            text: '$pendingText\n\n$text',
            links: [
              ...?pendingChunk.links,
              // Offset the current chunk's links by the combined text position.
              ...?chunk.links?.map(
                (l) => LinkMetadata(
                  start: l.start + pendingText.length + 2,
                  end: l.end + pendingText.length + 2,
                  url: l.url,
                ),
              ),
            ],
            inlineStyles: [
              ...?pendingChunk.inlineStyles,
              ...?chunk.inlineStyles?.map(
                (s) => s.copyWith(
                  start: s.start + pendingText.length + 2,
                  end: s.end + pendingText.length + 2,
                ),
              ),
            ],
            footnotes: [
              ...?pendingChunk.footnotes,
              ...?chunk.footnotes?.map(
                (f) => FootnoteRef(
                  position: f.position + pendingText.length + 2,
                  label: f.label,
                  content: f.content,
                ),
              ),
            ],
          ),
          sourceIndices: [...pendingValue.sourceIndices, chunk.index],
        );
      } else {
        // Emit pending and start fresh.
        emitPending();
        pending = (chunk: chunk, sourceIndices: [chunk.index]);
      }
    }

    emitPending();

    return (chunks: result, originalToMerged: originalToMerged);
  }

  Map<String, int> _remapAnchorMap(
    Map<String, int> anchorMap,
    Map<int, int> originalToMerged,
  ) {
    return anchorMap.map((anchor, originalIndex) {
      final mergedIndex = originalToMerged[originalIndex] ?? originalIndex;
      return MapEntry(anchor, mergedIndex);
    });
  }

  String _decodeUriValue(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  // ─── Fallback extraction ─────────────────────────────────────────────

  List<BookChunk> _fallbackExtract(EpubBook book) {
    final html = book.Content?.Html;
    if (html == null || html.isEmpty) {
      return [
        const BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: 'Could not parse this book.',
        ),
      ];
    }

    final buf = StringBuffer();
    for (final entry in html.values) {
      final content = entry.Content;
      if (content == null) continue;
      final stripped = content.replaceAll(RegExp(r'<[^>]*>'), ' ');
      buf.write(stripped);
      buf.write('\n\n');
    }

    final fullText = buf.toString().trim();
    if (fullText.isEmpty) {
      return [
        const BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: 'Could not parse this book.',
        ),
      ];
    }

    final subTexts = _splitBySentence(fullText, _targetWords);
    final chunks = <BookChunk>[];
    for (int i = 0; i < subTexts.length; i++) {
      chunks.add(
        BookChunk(index: i, type: BookChunkType.text, text: subTexts[i]),
      );
    }
    if (kDebugMode) {
      debugPrint('EpubParser: fallback produced ${chunks.length} chunks');
    }
    return chunks;
  }

  // ─── Text splitting utilities ────────────────────────────────────────

  /// Split text into chunks of approximately [targetWords] words each,
  /// breaking at sentence boundaries.
  List<String> _splitBySentence(String text, int targetWords) {
    final sentences = _splitIntoSentences(text);
    final List<String> result = [];
    final buf = StringBuffer();

    for (final s in sentences) {
      final bufWords = _wordCount(buf.toString());
      final sWords = _wordCount(s);
      if (bufWords + sWords > targetWords && buf.isNotEmpty) {
        result.add(buf.toString().trim());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(s);
    }
    if (buf.isNotEmpty && buf.toString().trim().isNotEmpty) {
      result.add(buf.toString().trim());
    }
    return result;
  }

  /// Count words efficiently by counting whitespace boundaries.
  /// Avoids allocating a regex object and split array on each call.
  int _wordCount(String s) {
    final len = s.length;
    if (len == 0) return 0;
    int count = 0;
    bool inWord = false;
    for (int i = 0; i < len; i++) {
      final c = s.codeUnitAt(i);
      // Space (32), tab (9), newline (10), carriage return (13)
      final isSpace = c == 32 || c == 9 || c == 10 || c == 13;
      if (!isSpace) {
        if (!inWord) {
          count++;
          inWord = true;
        }
      } else {
        inWord = false;
      }
    }
    return count;
  }

  List<String> _splitIntoSentences(String text) {
    final List<String> sentences = [];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      buffer.write(char);
      if ((char == '.' || char == '!' || char == '?') &&
          _isEndOfSentence(text, i)) {
        while (i + 1 < text.length && _isClosingQuote(text[i + 1])) {
          i++;
          buffer.write(text[i]);
        }
        sentences.add(buffer.toString().trim());
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty && buffer.toString().trim().isNotEmpty) {
      sentences.add(buffer.toString().trim());
    }
    return sentences;
  }

  bool _isEndOfSentence(String text, int i) {
    // Check for abbreviations before the period
    if (text[i] == '.') {
      // Extract the word before the dot
      int wordStart = i - 1;
      while (wordStart >= 0 &&
          text[wordStart] != ' ' &&
          text[wordStart] != '\n') {
        wordStart--;
      }
      wordStart++;
      if (wordStart < i) {
        final wordBeforeDot = text.substring(wordStart, i).toLowerCase();
        // Check single-word abbreviations (e.g., "Dr", "Mr")
        if (_abbreviations.contains(wordBeforeDot)) return false;
        // Check dotted abbreviations (e.g., "U.S", "e.g")
        if (_dottedAbbreviations.contains(wordBeforeDot)) return false;
        // Single uppercase letter + dot (initials like "J." in "J. K. Rowling")
        if (wordBeforeDot.length == 1 &&
            wordBeforeDot == wordBeforeDot.toUpperCase() &&
            wordBeforeDot != wordBeforeDot.toLowerCase()) {
          return false;
        }
      }
    }

    int j = i + 1;
    while (j < text.length && _isClosingQuoteOrSpace(text[j])) {
      j++;
    }
    if (j >= text.length) return true;
    final next = text[j];
    return next == next.toUpperCase() && next != next.toLowerCase();
  }

  bool _isClosingQuoteOrSpace(String char) {
    return char == ' ' ||
        char == '\n' ||
        char == '\r' ||
        char == '\t' ||
        _isClosingQuote(char);
  }

  bool _isClosingQuote(String char) {
    return char == '"' ||
        char == '\u201D' ||
        char == '\u2019' ||
        char == '\u00BB';
  }

  // ─── Table rendering (D-14) ──────────────────────────────────────────

  /// Renders an HTML <table> element as formatted plain text.
  /// Simple tables get aligned columns; complex ones get row-per-line.
  String _renderTable(dom.Element tableNode) {
    final rows = <List<String>>[];

    for (final tr in tableNode.querySelectorAll('tr')) {
      final cells = <String>[];
      for (final cell in tr.children) {
        if (cell.localName == 'td' || cell.localName == 'th') {
          cells.add(cell.text.trim());
        }
      }
      if (cells.isNotEmpty) {
        rows.add(cells);
      }
    }

    if (rows.isEmpty) return '';

    // Find max columns
    final maxCols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    if (maxCols == 0) return '';

    // Normalize column count
    for (final row in rows) {
      while (row.length < maxCols) {
        row.add('');
      }
    }

    // For simple tables (≤4 cols), use column-aligned format
    if (maxCols <= 4) {
      // Find max width for each column
      final colWidths = List<int>.filled(maxCols, 0);
      for (final row in rows) {
        for (int c = 0; c < maxCols; c++) {
          if (row[c].length > colWidths[c]) {
            colWidths[c] = row[c].length;
          }
        }
      }

      final buf = StringBuffer();
      for (int r = 0; r < rows.length; r++) {
        for (int c = 0; c < maxCols; c++) {
          buf.write(rows[r][c].padRight(colWidths[c]));
          if (c < maxCols - 1) buf.write('  │  ');
        }
        if (r < rows.length - 1) buf.write('\n');

        // Add separator after first row (header)
        if (r == 0 && rows.length > 1) {
          for (int c = 0; c < maxCols; c++) {
            buf.write('─' * colWidths[c]);
            if (c < maxCols - 1) buf.write('──┼──');
          }
          buf.write('\n');
        }
      }
      return buf.toString();
    }

    // For wider tables, simple row-per-line format
    final buf = StringBuffer();
    for (int r = 0; r < rows.length; r++) {
      buf.write(rows[r].join('  |  '));
      if (r < rows.length - 1) buf.write('\n');
    }
    return buf.toString();
  }

  // ─── Image resolution ────────────────────────────────────────────────

  Uint8List? _resolveImage(EpubBook book, String src) {
    try {
      final images = book.Content?.Images;
      if (images == null) return null;

      final filename = p.basename(src);
      for (final key in images.keys) {
        if (key.endsWith(filename)) {
          final content = images[key];
          if (content?.Content == null) continue;
          return Uint8List.fromList(content!.Content!);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('EpubParser: failed to resolve image "$src": $e');
      }
    }
    return null;
  }

  // ─── Constants ───────────────────────────────────────────────────────

  static const Set<String> _blockTags = {
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'blockquote',
    'section',
    'article',
    'header',
    'footer',
    'main',
    'figure',
    'figcaption',
    'pre',
    'hr',
    // 'br' removed — handled as inline \n in the visitor, not a block flush
  };

  // ─── EPUB Table of Contents extraction ─────────────────────────────

  /// Builds a hierarchical chapter list from the EPUB's built-in TOC
  /// (`EpubBook.Chapters`). Each `EpubChapter` has a `Title`,
  /// `ContentFileName`, and recursive `SubChapters`.
  ///
  /// We match each chapter's content filename against the actual parsed
  /// chunks' `sourceFile` field to find the correct starting chunk index.
  /// This is accurate because `sourceFile` was recorded during parsing.
  List<ChapterInfo> _extractTocChapters(
    EpubBook book,
    List<BookChunk> chunks,
    Map<String, int> anchorMap,
  ) {
    final epubChapters = book.Chapters;
    if (epubChapters == null || epubChapters.isEmpty) {
      if (kDebugMode) {
        debugPrint('EpubParser: No TOC chapters found in this EPUB');
      }
      return [];
    }

    // Build a map: source filename → first chunk index from that file.
    // This is the definitive mapping because chunk.sourceFile was set
    // during actual parsing, after all merging/splitting.
    final Map<String, int> fileToFirstChunk = {};
    for (int i = 0; i < chunks.length; i++) {
      final sf = chunks[i].sourceFile;
      if (sf != null && !fileToFirstChunk.containsKey(sf)) {
        fileToFirstChunk[sf] = i;
        // Also store by basename for fuzzy matching
        final baseName = p.basename(sf);
        if (!fileToFirstChunk.containsKey(baseName)) {
          fileToFirstChunk[baseName] = i;
        }
      }
    }

    if (kDebugMode) {
      debugPrint(
        'EpubParser: TOC has ${epubChapters.length} top-level chapters',
      );
    }

    List<String> chapterAnchorCandidates(EpubChapter chapter) {
      final candidates = <String>[];
      final contentFile = chapter.ContentFileName;
      final rawAnchor = chapter.Anchor;
      if (contentFile == null || contentFile.isEmpty) {
        if (rawAnchor != null && rawAnchor.isNotEmpty) {
          candidates.add(_decodeUriValue(rawAnchor));
        }
        return candidates;
      }

      final hashIndex = contentFile.indexOf('#');
      final filePart = hashIndex >= 0
          ? contentFile.substring(0, hashIndex)
          : contentFile;
      final anchor = rawAnchor?.isNotEmpty == true
          ? rawAnchor!
          : hashIndex >= 0
          ? contentFile.substring(hashIndex + 1)
          : null;

      if (anchor == null || anchor.isEmpty) return candidates;

      final decodedFile = _decodeUriValue(filePart);
      final decodedAnchor = _decodeUriValue(anchor);
      candidates
        ..add('$decodedFile#$decodedAnchor')
        ..add('${p.basename(decodedFile)}#$decodedAnchor')
        ..add(decodedAnchor);
      return candidates;
    }

    int? anchoredChunkIndex(EpubChapter chapter) {
      for (final candidate in chapterAnchorCandidates(chapter)) {
        final match = anchorMap[candidate];
        if (match != null) return match;
      }
      return null;
    }

    // Recursively walk EpubChapters to build ChapterInfo tree.
    List<ChapterInfo> walkChapters(List<EpubChapter> chapters, int depth) {
      final List<ChapterInfo> result = [];
      for (final ch in chapters) {
        final title = ch.Title?.trim() ?? '';
        if (title.isEmpty) continue;

        // Find chunk index for this chapter's content.
        int chunkIdx = 0;
        final contentFile = ch.ContentFileName;
        final anchorChunk = anchoredChunkIndex(ch);
        if (anchorChunk != null) {
          chunkIdx = anchorChunk;
        } else if (contentFile != null) {
          // EPUB TOC entries can have anchors: "chapter1.xhtml#section2"
          // Strip the fragment to get the file path.
          final hashIndex = contentFile.indexOf('#');
          final filePart = hashIndex >= 0
              ? contentFile.substring(0, hashIndex)
              : contentFile;
          final decodedFilePart = _decodeUriValue(filePart);

          // Try exact file match, then basename match
          chunkIdx =
              fileToFirstChunk[decodedFilePart] ??
              fileToFirstChunk[p.basename(decodedFilePart)] ??
              0;
        }

        // Clamp to valid range
        if (chunks.isNotEmpty) {
          chunkIdx = chunkIdx.clamp(0, chunks.length - 1);
        }

        // Recurse into sub-chapters
        final children = (ch.SubChapters != null && ch.SubChapters!.isNotEmpty)
            ? walkChapters(ch.SubChapters!, depth + 1)
            : <ChapterInfo>[];

        result.add(
          ChapterInfo(
            title: title,
            chunkIndex: chunkIdx,
            depth: depth,
            children: children,
          ),
        );
      }
      return result;
    }

    return walkChapters(epubChapters, 0);
  }
}
