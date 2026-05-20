# Book Parsing And Reader Page Layout

This note documents the current reader pipeline without proposing code changes.
The important split is:

1. EPUB parsing turns HTML files into semantic `BookChunk`s.
2. Reader layout rebuilds those chunks into visible display pages by measuring
   rendered text height against the active reader area.
3. The card renderer applies visual treatment for headings, dialogue, publisher
   blocks, tables, preformatted text, images, highlights, and selection.

## Main Files

- `lib/services/epub_parser.dart`: EPUB load, DOM traversal, text extraction,
  block role detection, dialogue detection, sentence splitting, table rendering,
  images, links, footnotes, chapters, anchors, and initial chunk merging.
- `lib/models/book_chunk.dart`: chunk data model and source-range mapping.
- `lib/screens/reader_screen.dart`: reader-area metrics, sentence ranges for
  layout, measured page splitting, display chunk merging, milestone insertion,
  and original/display page maps.
- `lib/utils/final_layout_paragraphs.dart`: paragraph splitting and exact text
  height measurement for final layout.
- `lib/utils/reader_content_parser.dart`: display-time parsing of text into
  paragraph/table/preformatted blocks.
- `lib/widgets/reading_card.dart`: actual page/card rendering.
- `lib/widgets/reader_table_block.dart`: rendered table and preformatted widgets.

## Stage 1: EPUB To Original Chunks

`EpubParserService` reads an EPUB with `epubx`, parses each HTML content file,
walks the DOM, and emits `BookChunk` objects.

### What Is Extracted

- Book title from `EpubBook.Title`.
- HTML spine/content from `book.Content?.Html`.
- Front matter vs content using filename patterns and TOC hints.
- Anchors from element `id` and `name` attributes.
- Chapter list from EPUB table of contents.
- Text chunks.
- Image chunks.
- Link metadata from `<a href>`.
- Footnote references and resolved footnote text.
- Inline bold/italic styles.
- Ordered and unordered list markers.
- Tables rendered into plain aligned text.
- Publisher-style block metadata.
- Dialogue metadata.

### Block Roles

The parser assigns a `BookBlockRole` when the DOM suggests special layout:

- `paragraph`: normal prose.
- `heading`: `h1` to `h6`.
- `quote`: `<blockquote>`.
- `epigraph`: class/type/role contains `epigraph`.
- `letter`: class/type/role contains `letter` or `correspondence`.
- `poem` / `stanza`: class/type/role contains verse/poem/poetry/stanza.
- `preformatted`: `<pre>`.
- `table`: `<table>`.

Those roles matter later because `chunk.usesPublisherLayout` is true for every
role except `paragraph` and `heading`. Publisher-layout chunks keep more of the
book's intended alignment, indentation, and line breaks.

Example from the parser:

```dart
BookBlockRole? detectBlockRole(dom.Element node) {
  final tag = node.localName;
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
```

### Dialogue Detection

Dialogue is not forced onto a new page by itself. It is marked as metadata on a
text chunk and later affects styling and merge compatibility.

Current dialogue detection:

- Text shorter than 8 trimmed characters is not dialogue.
- Counts quote characters: `"`, left/right curly double quotes, guillemets.
- Treats text as dialogue when quote ratio is above `0.03`.
- Also treats text as dialogue when it starts with a quote/guillemet/em dash and
  has enough quote evidence.
- If there are no quote characters, starting with a dialogue lead character is
  enough.

Example:

```dart
bool isLikelyDialogueText(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.length < 8) return false;

  int doubleQuoteCount = 0;
  for (int i = 0; i < text.length; i++) {
    if (_dialogueQuoteChars.contains(text[i])) doubleQuoteCount++;
  }

  final startsLikeDialogue = _dialogueLeadChars.any(trimmed.startsWith);
  if (doubleQuoteCount == 0) return startsLikeDialogue;

  final quoteRatio = doubleQuoteCount / text.length;
  if (quoteRatio > 0.03) return true;

  return startsLikeDialogue && doubleQuoteCount >= 2;
}
```

### First Chunk Size

The EPUB parser targets short original chunks:

- `_targetWords = 50`.
- `_hardMaxWords = 80`.
- If a normal paragraph exceeds `_hardMaxWords`, it is split by sentence.
- Publisher-layout chunks are not split at this parser stage just because they
  exceed `_hardMaxWords`; they are preserved and handled during display layout.
- Very tiny chunks under 15 words may be merged with the next compatible chunk.

### Sentence Splitting

The parser splits on `.`, `!`, and `?`, but avoids common abbreviations such as
`Mr.`, `Dr.`, `etc.`, dotted abbreviations such as `U.S.`, and initials. Closing
quotes after a terminator stay with the sentence.

## Stage 2: Original Chunks To Display Pages

The reader does not decide page breaks by word count alone. It measures real
painted height using Flutter `TextPainter` and the current settings:

- screen size;
- safe area;
- font family, size, weight;
- line height;
- paragraph spacing;
- side margin;
- content density;
- text scaler;
- card depth mode;
- publisher indent and alignment.

### Reader Area Height

`resolveReaderLayoutMetrics` computes the usable reader bounds. It subtracts:

- safe-area insets;
- top and bottom reader boundary padding;
- horizontal side margins;
- optional card-depth margins;
- optional card-depth header/footer reserves.

It also creates a safety buffer based on line height. The effective text budget
is density-based:

- low density: 25% of usable text height;
- medium density: 50%;
- high density: 75%;
- full page: 100%.

Example:

```dart
final lineHeightPx = settings.fontSizeValue * settings.lineHeight;
final safetyBuffer = ((lineHeightPx * 0.65) + depthBias).clamp(14.0, 36.0);
final usableTextHeight = math.max(
  availableHeight - safetyBuffer,
  lineHeightPx * 2.4,
);
final densityTextHeight = usableTextHeight * policy.pageHeightRatio;
```

### Height Measurement

Normal prose uses `measureFinalLayoutParagraphTextHeight`, which splits on two
or more line breaks and adds paragraph gaps. Headings and publisher-layout
chunks use `TextPainter` with the relevant style and strut.

Example:

```dart
if (!chunk.isHeading && !chunk.usesPublisherLayout) {
  return measureFinalLayoutParagraphTextHeight(
    text: text,
    style: bodyStyle,
    maxWidth: maxWidth,
    textAlign: textAlign,
    textScaler: textScaler,
    paragraphSpacing: _settings.paragraphSpacing,
    strutStyle: bodyStrut,
    fallbackFontSize: _settings.fontSizeValue,
    fallbackLineHeight: _settings.lineHeight,
  );
}
```

### When A New Page Is Created

A new display page is created when adding more content would exceed the current
height budget or when the next chunk is not merge-compatible.

The main algorithm:

1. Split an oversized original chunk by height.
2. Keep sentence ranges for prose.
3. Keep line ranges for `preserveLineBreaks` chunks, such as poems,
   preformatted blocks, and rendered tables.
4. If a sentence or line still exceeds the physical page height, split by token.
5. If a token itself is too tall, split by character.
6. Try to merge adjacent compatible chunks if the merged measured height still
   fits.
7. Flush the pending chunk into `newDisplayChunks` when merge fails.

Example of the page-limit decision:

```dart
final candidateText = text.substring(currentStart, range.end);
final candidateHeight = measureTextHeight(candidateText, original);

if (candidateHeight <= chunkBudget) {
  currentEnd = range.end;
  continue;
}

subChunks.add(buildSplitChunk(original, currentStart, currentEnd));
currentStart = range.start;
currentEnd = range.end;
```

### Merge Compatibility

Two chunks may share a display page only when their presentation boundaries are
compatible:

- both are text;
- same section;
- same source file;
- same heading state;
- same block role;
- same publisher alignment and indents;
- same line-break and whitespace preservation.

Then the merge must fit the measured height budget. Dialogue normally merges
with dialogue; normal prose with normal prose. A small chunk can sometimes merge
across dialogue presentation only if both chunks are ordinary body text with no
publisher layout.

Example:

```dart
bool sharesHardMergeBoundary(BookChunk first, BookChunk second) {
  return first.section == second.section &&
      first.sourceFile == second.sourceFile &&
      first.isHeading == second.isHeading &&
      first.blockRole == second.blockRole &&
      first.publisherTextAlign == second.publisherTextAlign &&
      first.publisherLeftIndent == second.publisherLeftIndent &&
      first.publisherRightIndent == second.publisherRightIndent &&
      first.preserveLineBreaks == second.preserveLineBreaks &&
      first.preserveWhitespace == second.preserveWhitespace;
}
```

### Tiny-Chunk Handling

The reader tries to avoid pages with just a few words. A chunk is "tiny" when:

- word count is under the density policy's tiny-word threshold;
- measured height is under the minimum useful height;
- or the chunk fills only a small ratio of its budget.

Tiny chunks can be attached to the previous page if they fit and are compatible.
There is also a rebalancing step where the previous pending prose chunk may be
split near a sentence boundary so its tail can join a tiny next chunk.

## Special Layout Cases

### Headings

Headings are original chunks with `isHeading = true` and `blockRole = heading`.
They are centered by `resolveReaderChunkTextAlign`. They are not split by
`splitChunkByHeight`; a heading remains a whole chunk.

### Dialogue

Dialogue is not a hard page-break rule. It is:

- detected during EPUB parsing;
- stored as `BookChunk.isDialogue`;
- rendered with a subtle quote watermark;
- eligible for same-page merging mainly with other dialogue chunks;
- part of the measurement cache key, because dialogue can affect available
  width and styling.

Current constant `kReaderDialogueTextInset` is `0.0`, so dialogue currently does
not consume extra horizontal inset, but the plumbing exists.

### Quotes, Epigraphs, Letters, Poems, Stanzas, Preformatted Blocks

These are publisher-layout chunks. They get:

- preserved line breaks for poem/stanza/preformatted;
- default or parsed text alignment;
- default or parsed left/right indentation;
- a full physical height budget instead of the density-reduced page budget;
- stricter merge boundaries.

Quotes default to left/right indentation. Epigraphs default to centered
alignment.

### Tables

HTML `<table>` is first rendered to plain text in `epub_parser.dart`, with simple
tables aligned using separators and wider tables using `|` delimiters. The chunk
gets `blockRole = table` and `preserveLineBreaks = true`.

At display time, `parseReaderContentBlocks` tries to recover structured tables
from text. It can detect:

- markdown pipe tables;
- box-drawing vertical separators;
- tab-delimited rows;
- rows separated by two or more spaces;
- separator rows made of hyphens/underscores/box drawing lines;
- wrapped pipe headers;
- header preambles separated from body rows.

If table-like text cannot be parsed into a valid table, it can become a
preformatted block instead.

### Paragraph Spacing

Paragraph display is based on two or more newlines. Those become separate
segments with a measured gap:

```dart
finalLayoutParagraphSeparatorPattern = RegExp(r'(?:\r\n|\r|\n){2,}');

double finalLayoutParagraphGap({
  required double fontSize,
  required double lineHeight,
  required double paragraphSpacing,
}) {
  return fontSize * lineHeight * paragraphSpacing;
}
```

### Images

Images are their own `BookChunkType.image` chunks. During display rebuild,
non-text chunks flush the current pending text, become their own pending chunk,
and are immediately flushed. That means images are separate display pages in
the layout pipeline.

### Milestones

After display chunks are fully rebuilt, synthetic milestone cards are inserted
at 25%, 50%, and 75% for longer books. These are not parsed from the EPUB.

## Things Included In Actual Parsing Logic

The actual parsing logic includes:

- EPUB byte loading, optionally in an isolate.
- Title extraction.
- HTML content map traversal.
- First-content-file detection.
- Front-matter filename classification.
- DOM parsing through `html_parser`.
- Recursive DOM visiting.
- Anchor recording from `id` and `name`.
- Block tag flushing.
- Heading state tracking.
- Text normalization.
- Whitespace preservation for preformatted content.
- Line-break preservation for verse-like content.
- Inline `<br>` handling.
- Bold/italic/cite/strong/em style ranges.
- Link ranges.
- Footnote pre-scan and noteref replacement.
- Ordered and unordered list marker generation.
- Image resolution from EPUB image assets.
- SVG skipping.
- HTML table extraction and plain-text rendering.
- Publisher block role detection.
- Publisher text alignment parsing from CSS/classes.
- Publisher left/right indent parsing from CSS.
- Dialogue detection.
- Word counting.
- Sentence splitting with abbreviation handling.
- Overlong paragraph splitting.
- Tiny original chunk merging.
- Anchor remapping after merging.
- TOC chapter extraction and source-file/anchor matching.
- Lazy search-index support.

The page-layout logic includes:

- Reader metric calculation from screen, safe area, settings, density, and card
  depth.
- Painted text height measurement.
- Paragraph-gap measurement.
- Width adjustment for publisher padding and dialogue inset.
- Prose sentence range splitting.
- Preserved-line splitting for publisher-layout blocks.
- Token and character fallback splitting for oversized ranges.
- Link/style/footnote/source-range slicing during splits.
- Merge separator choice using source contiguity.
- Display chunk merging under hard presentation boundaries.
- Tiny page rebalancing.
- Original-to-display and display-to-original maps.
- Milestone insertion.
- Display chunk caching.

## Short End-To-End Example

Input EPUB HTML:

```html
<h1 id="ch1">Chapter One</h1>
<p>"Well, it was this way," returned Mr. Enfield. "I was coming home."</p>
<blockquote style="text-align:right">A quoted passage.</blockquote>
<table>
  <tr><th>Field</th><th>Type</th></tr>
  <tr><td>latitude</td><td>decimal</td></tr>
</table>
```

Original chunks roughly become:

```dart
BookChunk(
  type: BookChunkType.text,
  text: 'Chapter One',
  isHeading: true,
  blockRole: BookBlockRole.heading,
)

BookChunk(
  type: BookChunkType.text,
  text: '"Well, it was this way," returned Mr. Enfield. "I was coming home."',
  isDialogue: true,
  blockRole: BookBlockRole.paragraph,
)

BookChunk(
  type: BookChunkType.text,
  text: 'A quoted passage.',
  blockRole: BookBlockRole.quote,
  publisherTextAlign: BookTextAlign.right,
  publisherLeftIndent: 20,
  publisherRightIndent: 16,
)

BookChunk(
  type: BookChunkType.text,
  text: 'Field  │  Type\n──────┼──────\nlatitude  │  decimal',
  blockRole: BookBlockRole.table,
  preserveLineBreaks: true,
)
```

Display pages are then decided by measured height. If heading plus dialogue do
not share hard merge boundaries, they become separate display chunks. If a long
dialogue paragraph exceeds the height budget, it splits by sentence. If the
quote block has publisher layout, it receives the physical page budget and
publisher padding, and it does not soft-merge with ordinary prose.
