# Nalori EPUB semantic-content audit

Audit status: complete, read-only. No files were edited, staged, committed, cleaned, or otherwise modified during the audit.

The audited worktree already contained extensive relevant uncommitted work: 50 tracked files differed from `HEAD` (`+4,554/-1,102`) plus untracked checkpoint, derived-index, source-projection, and boundary files. The current worktree was treated as the applicable architecture because it matches the requested system description, while key parser, model, and pagination behavior was compared against `HEAD`. The list and table defects described below exist in `HEAD`; logical-paragraph, derived-index, and checkpoint infrastructure is currently uncommitted worktree architecture.

## 1. Executive summary

Nalori's failures come from four confirmed architectural gaps:

1. The source model's structural vocabulary is too small. `BookBlockRole` distinguishes prose, headings, poetry, quotes, tables, and preformatted text, but has no list container/item, table cell, figure/caption relationship, definition list, scene break, aside, footnote body, heading level, language, or direction model. See [book_chunk.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/models/book_chunk.dart:12>).

2. Generated presentation is mixed into authoritative source text. List markers are written into the parser's text buffer; resolved footnote labels are replaced with generated bracketed text; tables are serialized as a `NALORI_TABLE_V1:` Base64 string stored in `BookChunk.text`. That directly affects UTF-16 offsets, search, Book Memory, checkpoints, copying, and Speed Reader.

3. Pagination understands height and text boundaries, but not parent-child structural relationships. It can split table rows safely and repeat the current header array, but has no list-item state, heading-following-block rule, figure-caption grouping, rowspan group, continuation state, or source/display distinction.

4. The outer card vertically centers every content type inside a non-scrollable `SingleChildScrollView`, under `ClipRRect`. This is the direct reason dense or oversized structured content is centered and can be clipped. See [reading_card.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reading_card.dart:2730>).

Recommended direction: preserve the lazy source architecture and add a narrow semantic sidecar to authoritative `BookChunk`s. Keep generated markers, repeated table headers, and continuation labels only in derived display-fragment metadata. Introduce one central authoritative-text projection used by Search, Book Memory, Speed Reader, copying, annotations, and checkpoints.

Do not rewrite the reader, eagerly parse the book, or make display-card indexes authoritative.

## 2. Current pipeline

### EPUB package and spine

The lazy path opens an EPUB reference, reads package metadata, manifest, spine, navigation, and checksums without materializing all XHTML. `LazyEpubManifestItem` retains the manifest `properties` string; `LazyEpubSpineItem` retains spine identity and checksums; `LazyEpubChapter` retains title, href, anchor, hierarchy, and resolved spine index. See [lazy_epub_index_service.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/lazy_epub_index_service.dart:26>) and its chapter mapping at [line 527](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/lazy_epub_index_service.dart:527>).

The section repository retains at most three parsed sections and a 6 MiB estimated in-memory section budget by default. It loads one XHTML section, linked image resources, and selected linked footnotes, then parses and caches that section. See [lazy_section_repository.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/lazy_section_repository.dart:275>) and [line 444](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/lazy_section_repository.dart:444>).

Publisher stylesheet links are discovered, but `_readSectionImageResources` rejects every non-image resource. CSS therefore never reaches section parsing. See [lazy_section_repository.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/lazy_section_repository.dart:780>).

### XHTML construction and parsing

`parseLazySection` creates a synthetic one-XHTML `EpubBook`, with the section HTML plus image resources. It explicitly sets `Content.Css = {}` and calls the same `_extractContent` path used by eager parsing. See [epub_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:250>).

`_extractContent`:

- Parses the XHTML body.
- Prescans simplified footnote IDs.
- Recursively walks DOM nodes.
- Uses one mutable text buffer plus inline-style, link, and footnote buffers.
- Flushes that buffer into `BookChunk`s at recognized block boundaries.
- Records DOM `id` and legacy `name` anchors against the current chunk index.
- Normalizes ordinary whitespace, while preserving whitespace for `<pre>` and line breaks for detected verse.
- Assigns current-worktree logical paragraph IDs per flush.

The central flush is at [epub_parser.dart:713](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:713>); the DOM visitor and anchor registration begin at [line 858](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:858>).

### Authoritative chunk model

`BookChunk` is the shared parser/display carrier. Its principal semantic fields are:

- `type`: text, image, or milestone.
- `blockRole`: paragraph, heading, poem, stanza, quote, epigraph, letter, table, or preformatted.
- Text, links, bold/italic spans, and footnotes.
- Publisher alignment and left/right indent.
- Source file, source ranges, logical paragraph identity, and UTF-16 paragraph offsets in the current worktree.

See [book_chunk.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/models/book_chunk.dart:237>) and source-range fallback at [line 410](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/models/book_chunk.dart:410>).

The current uncommitted work adds logical paragraph IDs, paragraph-relative offsets, and explicit synthesized text boundaries. Ordinary prose is substantially safer because of that work. It does not solve generated list/table content because those values still enter `BookChunk.text` before source identity is assigned.

### Derived indexes

`buildDerivedIndexSegment` groups all non-empty `chunk.text` by logical paragraph ID and copies every UTF-16 code unit into the Search/Book Memory index. It does not ask whether text is source-authored or generated. See [derived_book_index_service.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/derived_book_index_service.dart:411>).

Consequences:

- List bullets and numbers are indexed.
- Resolved footnote bracket labels are indexed.
- Encoded table payloads are indexed instead of visible cell text.
- The direct search fallback also searches `chunk.text`; see [search_screen.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/search_screen.dart:230>).
- Legacy Book Memory scanning likewise consumes `chunk.text`; see [book_memory_service.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/book_memory_service.dart:380>).

### Pagination and display projection

`ReaderScreen._rebuildDisplayChunks` calculates available width/height from reader settings, measures each source chunk, splits oversized chunks, and packs compatible fragments into display cards.

Relevant code:

- Hard merge compatibility: [reader_screen.dart:269](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:269>).
- Text/table measurement: [reader_screen.dart:3472](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:3472>).
- Source-preserving text fragment construction: [reader_screen.dart:3857](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:3857>).
- Height-driven splitting: [reader_screen.dart:4105](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:4105>).
- Display merging and synthesized-boundary mapping: [reader_screen.dart:4315](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:4315>).
- Source-chunk pagination loop: [reader_screen.dart:4723](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:4723>).

There is no general structural fragment state beyond ordinary `BookChunk` fields.

### ReadingCard and specialized rendering

`ReadingCard` uses `Text.rich` as its canonical prose renderer. The active card adds `SelectionArea`, links, notes, highlights, and interaction; preview cards use the same prose layout without active recognizers. See [reading_card.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reading_card.dart:3187>) and the active selection wrapper at [line 3200](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reading_card.dart:3200>).

Structured text is reparsed by `parseReaderContentBlocks`:

- Tables use `ReaderTableBlockWidget`.
- Heuristically detected preformatted blocks use `ReaderPreformattedBlockWidget`.
- Both are wrapped in `SelectionContainer.disabled`.

See [reading_card.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reading_card.dart:3256>).

The same structured widget is used for active and preview cards, so preview/active geometry is consistent. It is consistently limited: table cells cannot currently be selected, highlighted, linked, or noted.

## 3. Root causes

### Confirmed causes

1. **List state is only three scalar variables.** `insideOl`, `insideUl`, and one `olCounter` cannot represent nesting, list identity, parent items, marker style, `start`, `reversed`, or `value`. See [epub_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:598>).

2. **Markers are inserted into source text.** `<li>` writes `"$olCounter. "` or `"• "` directly into `textBuffer`. See [epub_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:1107>).

3. **Block children detach markers.** With `<li><p>Text</p></li>`, the marker is written before entering `<p>`. Because `<p>` is a block, the visitor immediately calls `flush()` before reading its text. This creates a marker-only chunk followed by an unrelated paragraph chunk.

4. **Direct-text lists are over-flattened.** `<li>Text</li>` items remain in one shared buffer separated only by newline. The entire list may become one ordinary paragraph-role chunk, with no item identity or depth.

5. **Nested list type can be wrong.** Entering a nested `<ul>` does not clear `insideOl`; `<li>` checks `insideOl` first. An unordered list nested under an ordered list can therefore receive numeric markers.

6. **Tables are stored as encoded presentation text.** The parser serializes `ReaderTableBlock` and puts that encoding in `BookChunk.text`. See [epub_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:1008>) and [reader_content_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/utils/reader_content_parser.dart:126>).

7. **Table cell semantics are too weak.** A cell retains only plain normalized text, `isHeader`, `rowSpan`, and `columnSpan`. Inline styles, links, image relationships, source IDs, language, direction, and source ranges are lost. See [reader_content_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/utils/reader_content_parser.dart:7>) and `_normalizedTableCellText` at [epub_parser.dart:1658](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:1658>).

8. **Merged cells are flattened for rendering.** `ReaderTableBlock.fromCellRows` expands cells into a rectangular list of strings. The widget renders that expanded representation with Flutter `Table`; it does not render `rowspan` or `colspan`.

9. **Every table column uses equal flex.** `ReaderTableBlockWidget` assigns `FlexColumnWidth()` to every column. See [reader_table_block.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reader_table_block.dart:80>).

10. **Table pagination drops source and span metadata.** `buildTableChunk` reconstructs a table from `headers` and `rows` only. It does not copy source ranges, logical paragraph fields, inline metadata, `cellRows`, or continuation state. See [reader_screen.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:4140>).

11. **Oversized rows remain oversized.** A row taller than the card is added when `currentRows` is empty. No vertical fallback is introduced, so the resulting fragment still exceeds the budget.

12. **All content is vertically centered and clipped.** The root surface uses `ClipRRect → Center → non-scrollable SingleChildScrollView`. See [reading_card.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reading_card.dart:2730>).

13. **Heading levels are discarded.** All `<h1>`–`<h6>` set the same boolean `currentIsHeading`; no level survives. See [epub_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:1143>).

14. **Publisher stylesheets are ignored.** Lazy parsing supplies an empty CSS map, and the repository loads only images. Current style parsing consists of inline `text-align`, inline margins, and class-name heuristics.

15. **Structural tags are missing from the block set.** `<dl>`, `<dt>`, `<dd>`, `<aside>`, and table substructures are absent. `<hr>` is a block but produces no content, so it disappears. See [epub_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:1761>).

16. **Footnote presentation changes source text.** A resolved noteref adds `FootnoteRef` but replaces the link's actual visible text with generated `[$displayLabel]`. See [epub_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:959>).

17. **Direction and language are not modeled.** Measurement uses `TextDirection.ltr` for prose and tables. See [reader_screen.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:3490>).

### Hypotheses requiring fixture/device confirmation

- Wide in-card horizontal table scrolling may conflict with horizontal card navigation gestures. Both recognizers exist, but actual arbitration depends on the card-deck implementation and device gesture.
- Some publisher contents pages may appear less broken when their `<li>` content is direct text rather than child paragraphs. The model remains structurally unsafe in both cases.
- Actual visual clipping severity depends on card height, density, and whether an oversized table is horizontally or vertically dominant.
- Flutter may bidirectionally render some plain `Text.rich` content acceptably through inherited direction, but pagination measurements and annotation geometry remain explicitly LTR and can diverge.

## 4. Semantic support matrix

Priority: P0 immediate, P1 next, P2 specialized readability, P3 explicit format strategy.

| EPUB structure | Parser support | Pagination support | Renderer support | Source-range safety | Current failure mode | Recommended treatment | Priority |
|---|---|---|---|---|---|---|---|
| Simple `<ul>/<li>` | Marker generation only | Ordinary text splitting | Prose only | Unsafe: bullet is source text | Marker spacing/line separation | List/item IDs; visual marker; hanging-indent renderer | P0 |
| Simple `<ol>/<li>` | Counter from 1 | Ordinary text splitting | Prose only | Unsafe: number is source text | Detached or incorrect number | Parse deterministic ordinal; visual marker | P0 |
| Nested lists | Not modeled | None | None | Unsafe | Depth lost; nested UL may become numbered | Parser list stack with parent IDs and depth | P0 |
| `start/reversed/type/value` | Ignored | None | None | Unsafe | Wrong numbering | Parse HTML list-numbering algorithm | P0 |
| Multi-block list item | Children flush independently | Unrelated chunks | Prose | Unsafe | Marker-only cards; excessive gaps | Item parent ID and block index; splittable fragments | P0 |
| Tables and rows | Encoded table block | Splits complete rows | Dedicated widget | Unsafe: encoded payload is authoritative | Search/offset corruption | Source table/cell semantics plus derived renderer model | P0 |
| `<thead>/<tbody>/<tfoot>` | Not distinguished | First expanded row only | Header array only | Unsafe | Wrong/repeated headers; footer lost | Row-group roles and multiple header rows | P0 |
| `<caption>` | Ignored | None | None | Lost | Caption detached/disappears | Caption source range grouped with table | P0 |
| `rowspan/colspan` | Parsed into cell model | Discarded on split | Flattened | Unsafe | Merged relationships lost | Occupancy grid; rowspan-connected atomic row groups | P0 |
| Headings h1–h6 | Boolean heading | Atomic, but no keep-with-next | One heading style | Text safe; level lost | Stranded heading; hierarchy lost | Preserve level, ID, keep-with-following rule | P1 |
| `<blockquote>` | Quote role | Text/line splitting | Indented `Text.rich` | Mostly safe | No citation/child structure | Quote container; preserve block children and cite | P1 |
| `<q>/<cite>` | `cite` italic; `q` generic | Ordinary | Prose | Text safe | `<q>` quote semantics lost | Inline semantic span; locale-aware quote decoration | P2 |
| Epigraphs | Class/type heuristic | Generic structured text | Indented/centered | Mostly safe | Attribution relationships lost | Epigraph group with optional citation | P1 |
| Figures/captions | Figure block boundary; image separate | Independent chunks | Image/prose separately | Caption text safe; relation lost | Image/caption split | Figure ID; image-alt-caption relationships | P1 |
| Images | Raster bytes | Atomic chunk | `BoxFit.contain` | No text range | Alt text lost | Preserve alt/title, aspect ratio, figure identity | P1 |
| Inline/external SVG | Inline SVG skipped; SVG image bytes unsupported by `Image.memory` | None | None | Lost | Missing graphics | Sanitized SVG renderer or accessible fallback | P2 |
| Definition lists | Unrecognized | Ordinary text | Prose | Text may concatenate | Term/definition hierarchy lost | Definition-list and term/definition roles | P2 |
| `<pre>` | Role and whitespace retained | Line-based split | Often prose; heuristic pre widget only | Text mostly safe | Generic rendering or clipping | Explicit code/pre renderer and fragment state | P1 |
| `<code>` | Unrecognized inline | Ordinary | Reader font | Text safe; semantics lost | No monospace/code treatment | Inline code semantic span | P2 |
| Poetry/verse/line groups | Class/type heuristics; `<br>` newline | Preserved-line split | `Text.rich` with layout padding | Mostly safe | Weak line-group/stanza hierarchy | Verse/line/stanza source nodes | P1 |
| Plays/dialogue | Dialogue heuristic only | Ordinary prose | Dialogue decoration | Text safe | Speaker/stage relationships lost | Speaker, speech, stage-direction roles | P2 |
| Scene breaks/ornaments | `<hr>` disappears; image ornament isolated | None | None/image | Lost or detached | Missing break | Scene-break source node; generated ornament fallback | P1 |
| Footnotes/endnotes | Simplified ID prescan and noteref heuristic | Generic | Popup for recognized refs | Unsafe marker offsets | False positives; body/backlink flattening | Role-driven note model; source label unchanged | P1 |
| Internal anchors/links | Anchors and prose links retained | Stable lazy resolver | Active prose links | Safe in prose | Links lost in tables/images; broken target silent | Preserve links in all structures; accessible failure | P1 |
| Sup/sub/small caps/decoration | Flattened | Ordinary | None | Text safe | Meaningful typography lost | Extend inline semantic span set | P2 |
| MathML | Generic descendant text only | Ordinary | Prose | Formula semantics unsafe | Formula flattened | Sanitized MathML renderer; text/alt fallback | P3 |
| Ruby | Base and annotation concatenate | Ordinary | Prose | Ambiguous | Ruby annotation flattened into text | Ruby span model and renderer | P2 |
| CJK/language metadata | Text retained; no language | Generic boundaries | Default text | Partly safe | Wrong breaking/font/annotation geometry | Propagate `lang`, locale, CJK break policy | P2 |
| RTL/mixed direction | No model | LTR measurement | Inherited/default render | Unsafe geometry | Wrong alignment, wrapping, offsets | `dir`/bidi metadata through measure and render | P2 |
| Sidebars/asides/callouts | Flattened | Ordinary | Prose | Text safe | Relationships and visual distinction lost | Aside/callout role; top-aligned block | P2 |
| Fixed-layout EPUB | Not detected | Reflowed | Ordinary reader | Semantically wrong | Absolute layout destroyed | Detect rendition metadata; route to dedicated/unsupported mode | P3 |
| Media overlays | Package field exists upstream but not mapped | None | None | N/A | Ignored | Preserve SMIL reference; later synchronized-audio design | P3 |
| Audio/video | Generic fallback text only | None | None | N/A | Media absent | Explicit unsupported/accessible fallback, later player | P3 |
| Scripted EPUB | No filtering/model | None | None | Potentially unsafe | Body script text may enter content; behavior ignored | Strip scripts in reflow mode; flag scripted publication | P3 |
| EPUB 2 NCX | Parsed hierarchically | Stable chapter targets | Reader Menu tree | Hrefs/anchors retained | Exceptions can erase TOC | Harden malformed navigation fallback | P1 |
| EPUB 3 nav | Partial | Stable chapter targets | Reader Menu tree | Hrefs/anchors retained | Exact `properties="nav"` and first-`nav` assumptions | Token match plus `epub:type="toc"` selection | P1 |
| Publisher contents page | Parsed like ordinary XHTML/list | Generic | Prose/list failure | Unsafe markers | Number/title separation and hierarchy loss | Same list/link semantics; later TOC-specific presentation | P1/P3 experience |

## 5. Lists audit

### Current representation

There is no list source representation. The parser has `insideOl`, `insideUl`, and `olCounter`. An `<ol>` resets the single counter to zero. Each `<li>` increments it and writes a textual prefix. Unordered items write `• `. No list or item ID, depth, parent, marker style, or ordinal metadata survives.

### Exact marker-separation mechanisms

- `<li><p>Item text</p></li>` produces a marker before entering `<p>`. Because `<p>` flushes before its children, the marker becomes a separate source chunk.
- Multiple `<p>` elements in an item become separate logical paragraphs with no common item identity.
- Direct-text list items can remain together in one buffer, so pagination sees the list as one prose paragraph and can split on sentence/word boundaries without item awareness.
- A nested `<ul>` inside `<ol>` leaves `insideOl == true`, causing the nested item to take the ordered branch.
- Current-worktree logical paragraph IDs are allocated per flush, so a marker-only flush and item-text flush receive unrelated identities.
- The initial tiny-chunk merge behavior in `HEAD` could sometimes hide the issue by merging short chunks with prose separators, but it still did not restore list identity. The current worktree's stricter logical-paragraph merge keeps those flushes separate.

### Ordered-list correctness

The parser ignores `ol[start]`, `ol[reversed]`, `ol[type]`, `li[value]`, CSS `list-style-type`, and continuation across malformed but repairable nested markup. Numbering is deterministic only for a simple, forward, base-10 list starting at one.

### Annotation and indexing effects

Because markers are part of `BookChunk.text`:

- Selection/highlight/note offsets include generated prefixes.
- Search indexes bullets and ordinals.
- Copy and quote sharing include them as though publisher-authored.
- Speed Reader receives them as ordinary tokens.
- Removing or reformatting them later shifts persisted offsets unless migrated.

### Recommended source model

Each list-related source block needs:

- `listId`
- `parentListId`
- `parentItemId`
- `itemId`
- `ordered`
- `depth`
- `markerStyle`
- `start`
- `reversed`
- resolved `ordinal`
- optional item `value`
- item position: first/middle/final
- block index within the item
- item block count or end flag
- generated-marker flag
- malformed-source recovery flags

The source chunk's text must contain only the item block's normalized publisher text. The marker is derived from metadata and rendered separately.

Long items remain splittable:

- Opening fragment: marker visible with at least one measured text line.
- Middle/end fragments: hanging indent retained, marker suppressed, optional subtle continuation affordance.
- Nested child list: grouped under its parent item but independently splittable.
- Marker has no source range and is excluded from selection, search, copy, Book Memory, character matching, and Speed Reader.

Use a parser stack, not nested booleans. Each stack frame should hold list type, stable ID, depth, marker style, next ordinal, reversed state, and parent item.

## 6. Tables audit

### Current representation

`ReaderTableCell` stores only plain `text`, `isHeader`, `columnSpan`, and `rowSpan`. `ReaderTableBlock.fromCellRows` expands cells into rectangular string rows. It considers the first row a header when that row contains any `<th>`. It does not distinguish caption, row groups, multiple header rows, header scope, footer, cell source ranges, inline content, links, or images.

The source chunk then stores an encoded JSON/Base64 representation in `BookChunk.text`.

### Renderer and sizing

`ReaderTableBlockWidget` clamps table font size to 13–18, calculates `minWidth = columnCount * 156`, uses a horizontal `SingleChildScrollView`, assigns every column equal flex, and renders every cell as plain `Text`. See [reader_table_block.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reader_table_block.dart:51>).

This explains the short-label-column defect. There is no content-sensitive min/preferred width calculation.

### Pagination and overflow

Current pagination does one useful thing: it splits long tables only between complete expanded rows and includes the header array in every split fragment.

Limitations:

- Header repetition is not tagged as generated/repeated.
- No “Table continued” state.
- No caption grouping.
- No `<thead>` identity; only the first expanded header-like row.
- `rowspan`-connected rows can be split apart.
- Split fragments discard source metadata and original span structure.
- A row taller than the card remains oversized.
- The centered, clipped card shell can hide the top and bottom of that row.
- A wide table can scroll horizontally, but width classification and navigation-gesture arbitration are not tested.
- No expanded-table viewer exists.
- Active and preview cards are geometrically consistent, but both disable selection for tables.

### Search, Book Memory, and source offsets

The encoded payload is consumed by the derived index as source text. Visible cell terms are therefore not reliably searchable. Book Memory and character matching can receive encoded data. `readerSpeedReadText` decodes table blocks into `logicalText`, but this text no longer shares offsets with the encoded source chunk.

### Recommended adaptive-table design

Preserve these source semantics:

- `tableId`
- caption block/range
- row groups: head/body/foot
- stable row and cell IDs
- logical grid coordinates
- `rowSpan`, `columnSpan`
- header role and `scope`
- cell authoritative text segments
- cell inline styles, links, language, and direction
- source-range mapping for every cell

Use content-derived sizing:

1. Measure each column's min-content width from its longest unbreakable segment.
2. Measure max/preferred content width with the active reader typography.
3. Allocate min widths first.
4. Distribute remaining width according to `(preferred - min)` demand.
5. Do not give a short label column equal width merely because it shares a table with prose.
6. If total min-content width exceeds available width, classify the table as wide and scroll/expand; do not shrink text universally.

Recommended objective classifications:

| Class | Threshold | On-card behavior |
|---|---|---|
| Compact | ≤3 columns, ≤6 data rows, no spans, preferred width ≤ card, height ≤60% of text budget | Fit card with content-weighted columns |
| Long narrow | Min-content width ≤ card and either >6 rows or height >60% | Row pagination; repeat true headers; continuation label |
| Wide | Min-content width >105% of card or ≥5 meaningful columns | Constrained horizontal viewport plus “Open table” |
| Complex | Any rowspan, colspan, multiple header rows, or irregular occupancy | Preserve grid; split only between rowspan-independent row groups; expanded viewer available |
| Layout table | Explicit `role="presentation"`, or a conservative combination of no headers/caption, mostly empty/image-only cells, and layout-oriented attributes | Render as layout flow only when classification is high-confidence; otherwise retain data-table behavior |

For a row taller than the card:

- Never silently clip or split it at an arbitrary vertical pixel.
- Show a bounded, top-aligned preview with an “Open full table” affordance.
- Open a dedicated scrollable table route/sheet.
- Opening and closing the viewer must not change the reader checkpoint.
- The underlying stable location remains the table or first visible cell.

Repeated headers and “Table continued” are generated display material. Repeated header instances should be non-selectable or explicitly mapped back to their original source without being copied twice.

## 7. Other readability structures

### P1: immediate foundations after lists/tables

- **Headings:** preserve levels 1–6 and keep a heading with at least two following text lines when practical. Current headings are all centered and atomic but can strand at a card end.
- **Figures:** retain figure/image/caption/alt relationships. Keep image and caption together when they fit; otherwise place caption with the image opening or continuation affordance.
- **Blockquotes and epigraphs:** retain child blocks and citations. Current role and indentation support is useful but too flat.
- **Scene breaks:** convert `<hr>`, asterisms, and ornamental-only blocks into explicit scene-break nodes. They must not disappear or be indexed as prose.
- **Footnotes/internal links:** retain source label text unchanged, model noteref/body/backlink roles, and route all internal links through stable href/fragment resolution.

### P2: specialized reflow content

- **Verse:** preserve poem/stanza/line identities rather than only newline-bearing text.
- **Definitions:** add list/term/definition grouping.
- **Pre/code:** an explicit preformatted/code source role should choose the specialized renderer directly; current `<pre>` metadata does not guarantee that path.
- **Plays:** recognize common EPUB roles/classes for speaker, speech, and stage direction.
- **Asides/callouts:** use a distinct, top-aligned container without honoring hostile floats or fixed widths.
- **Ruby/CJK/RTL:** propagate language and direction through parsing, measurement, rendering, and annotation geometry.

### P3: formats needing explicit strategy

- **MathML:** use a sanitized semantic renderer with accessible text/alt fallback.
- **Fixed layout:** detect `rendition:layout` and related metadata. Do not feed fixed-layout XHTML into ordinary reflow and claim fidelity.
- **Media overlays/audio/video:** retain metadata now so later support is not blocked, but do not mix media playback into the first structural phase.
- **Scripted EPUBs:** strip executable scripts in reflow mode and surface an explicit capability state.

## 8. Data-model recommendation

Use targeted additive extensions.

### Authoritative source semantics

Add an optional semantic sidecar to `BookChunk`, for example `BookStructureSemantics`, rather than replacing `BookChunk`.

It should contain:

- Stable structural node ID.
- Node kind.
- Parent structure ID.
- Optional list, table, heading, figure, note, language, and direction payloads.
- Authoritative text segments and their logical block IDs.
- DOM recovery flags for malformed content.

Ordinary prose chunks remain unchanged.

For tables, stop using the encoded sentinel as authoritative text. Store a canonical source projection containing every actual caption/cell text exactly once, plus table semantics. A central accessor such as `authoritativeTextSegmentsForChunk` should provide source text to downstream consumers.

### Derived semantic index data

Search and Book Memory should consume authoritative text segments, not raw `chunk.text`.

Derived data may include:

- Normalized searchable cell/list-item text.
- Stable semantic node ID.
- Logical paragraph/cell ID.
- UTF-16 source start/end.
- Structural kind for ranking or snippets.

This remains rebuildable and subject to existing derived-index budgets.

### Display-layout fragment metadata

Introduce ephemeral or display-cache-scoped metadata:

- `fragmentState`: complete, beginning, continuation, end.
- `breakPolicy`: atomic, splittable.
- Parent structure ID.
- Item block or table row range.
- `showListMarker`.
- `repeatTableHeader`.
- `showContinuationBefore/After`.
- `verticalPlacement`: prose-centered or structured-top.
- Generated header/marker/label state.

This metadata depends on the layout signature and is not authoritative source data.

### Generated visual-only content

The following must have no source range:

- List bullets and numbering.
- Hanging-indent guides.
- Repeated table headers.
- “Table continued”.
- Continuation arrows or badges.
- Fallback scene-break ornaments.

They must be excluded from Search, Book Memory, character matching, Speed Reader, copying, notes, highlights, and persisted offsets.

## 9. Pagination and rendering design

Use semantic constraints as hard rules or soft penalties around the existing height measurement.

### Hard rules

- Never place a list marker without at least one rendered line of its item.
- Never repeat a marker on item continuation fragments.
- Split tables only between complete rows or rowspan-connected row groups.
- Never silently clip an oversized table row.
- Preserve explicit verse/preformatted line boundaries.
- Generated display content must not change source coverage or checkpoint signatures.
- Active and preview cards must receive the same display-fragment model.

### Soft keep rules

Apply when the grouped content can fit without creating a materially underfilled prior card:

- Heading plus at least two following lines.
- Figure plus caption.
- Table caption plus all header rows plus one data row.
- Footnote marker plus opening footnote line.
- Avoid one-line widows/orphans at card edges.
- Keep short definition terms with the first definition line.
- Keep speaker label with the opening dialogue line.

### Alignment

Top-align a card when its dominant content is:

- A list.
- A table.
- A printed contents/reference page.
- Code/preformatted content.
- Definitions.
- A long quote/epigraph.
- A structured continuation fragment.

Retain the existing centered prose behavior for ordinary narrative cards. A heading followed by normal prose can remain under prose alignment unless classified as a structured/reference page.

### Specialized renderers

- Lists: marker column plus `Text.rich` body, using measured hanging indent.
- Tables: semantic grid with adaptive widths; active mode uses cell-aware rich text and links.
- Pre/code: explicit renderer selected by source role, not table heuristics.
- Verse: line/stanza renderer with source mapping.
- Figures: image, alt, caption, and interaction in one structural component.

### Oversized fallbacks

- Oversized list item: split text normally; marker only on first fragment.
- Oversized figure: scale within aspect-ratio limits; place caption on a continuation card if necessary.
- Oversized table row or complex table: bounded preview and expanded viewer.
- Unbreakable code/verse line: horizontal scroll, never shrink below reader accessibility minimum.
- Corrupt semantics: fall back to normalized prose while retaining original href/source identity.

## 10. Compatibility and migration risks

| Existing system | Required compatibility treatment |
|---|---|
| Lazy section parsing | Parse semantics only for the loaded XHTML and its already-resolved dependencies. Do not parse other spine sections. |
| Memory budgets | Retain the 3-section/6 MiB ownership policy and existing parsed/display budgets. Include semantic sidecar size in existing cost estimates. |
| Parsed cache | New serialized semantic fields require a future controlled parser/cache version change. Old records should decode with `semantics == null`; invalid sections rebuild lazily. No version was changed in this audit. |
| Display caches | Structural fragment rules change page boundaries; future implementation must change the pagination/display signature so exact-layout caches are not reused incorrectly. |
| Stable paragraph IDs | Preserve current IDs for unchanged prose. Derive new structural IDs deterministically from normalized href plus DOM ID/path, not card order. |
| Existing list/table positions | Provide legacy aliases/context fallback. Old list offsets that included a marker need prefix-to-body adjustment. Old encoded-table locations should resolve to table start or a context-matched cell. |
| StableBookLocation | Continue using publication fingerprint, spine, href, checksum, internal segment ID, offset, context, and progression. Semantic IDs are additive. |
| Search | Rebuild derived sections from authoritative segments. Search results inside cells/items must return stable logical IDs and UTF-16 ranges. |
| Book Memory/characters | Use the same authoritative projection as Search. Generated markers and payload encodings must never be scanned. |
| Checkpoint restoration | Exact restoration remains valid only under the same parser/layout signatures. After reflow or model upgrades, use semantic node/cell/item anchors plus context. |
| Bookmarks | Table-level bookmarks may target the table; text bookmarks inside a cell target the cell logical ID and offset. |
| Highlights/notes | Preserve ordinary prose IDs. Add cell/item source projection; do not allow highlights to bind to generated marker/header content. |
| Multi-range notes | Store each semantic source range independently; display projection may span multiple list blocks or cells. |
| Selection | List marker column is outside selectable source text. Table selection must map to cell ranges; repeated headers are non-authoritative. |
| Copy/quote sharing | Assemble selected authoritative ranges in reading order. Do not duplicate repeated headers or include continuation labels. |
| Speed Reader | Feed item/cell authoritative text in reading order. No bullets unless the publisher actually authored them. |
| Preview/active consistency | Build both from the same immutable fragment DTO; only active interaction wrappers differ. |
| Font/size/density/orientation | Recompute fragment state and adaptive widths; semantic IDs and source offsets remain unchanged. |
| Corrupt EPUB recovery | If semantic parsing fails, emit normalized prose with a recovery diagnostic and stable href-based identity. Never discard the whole section solely because one structure is malformed. |
| Fixed-layout EPUB | Detect before reflow. Do not migrate fixed-layout positions into mutable card indexes. |

The future implementation will require cache/parser/pagination versioning, but that should invalidate only derived parsed/display artifacts—not user annotations or stable locations.

## 11. Test plan

### Proposed test locations

- `test/fixtures/epub_semantics/`: deterministic EPUB fixtures.
- `test/unit/services/epub_parser_structures_test.dart`: source semantics and UTF-16 invariants.
- `test/unit/models/book_structure_semantics_test.dart`: serialization/backward compatibility.
- `test/reader_structural_pagination_test.dart`: fragment/group rules.
- `test/widgets/reading_card_list_test.dart`
- `test/widgets/adaptive_reader_table_test.dart`
- `test/widgets/reading_card_structured_alignment_test.dart`
- `test/unit/services/structured_derived_index_test.dart`
- `test/unit/services/structured_source_projection_test.dart`
- `test/unit/services/structured_lazy_navigation_test.dart`

### Fixture and invariant matrix

| Fixture/test | Source-model invariant | Render/layout invariant |
|---|---|---|
| Simple unordered list | Body text excludes bullet; list/item IDs exist | Bullet and first text line share one fragment |
| Long wrapped item | One stable item ID across fragments | Marker only on opening fragment |
| Nested lists | Correct parent IDs/depth and list type | Hanging indents and hierarchy remain visible |
| Multi-paragraph item | All blocks share item ID; separate paragraph offsets | Paragraph spacing is item-aware, not card-like |
| Ordered `start=7` | Ordinals begin at 7 | Visible labels 7, 8… |
| Roman/alphabetic list | Marker style retained | Correct generated marker glyphs |
| `reversed` and `li[value]` | Deterministic resolved ordinals | Continuity survives pagination/lazy reload |
| Malformed list markup | Safe recovered structure or prose fallback | No marker-only blank card |
| Small two-column table | Cell ranges/styles/links retained | Short label column receives less width |
| Long narrow table | Row groups and headers retained | Split only between rows; repeat true headers |
| Wide table | Intrinsic width classification deterministic | No overflow; horizontal/expanded affordance |
| Rowspan/colspan | Logical grid and spans round-trip | Merged relationships render correctly |
| Caption and multiple header rows | Caption/head/body roles retained | Caption, headers, and first row kept together |
| Row taller than card | Source row remains one semantic row | Bounded preview; no clipping; expand action |
| Table links/styles | Per-cell spans/ranges retained | Active links/styles work; preview dimensions match |
| Search in table cell | Indexed string equals cell source text | Navigation lands on containing cell/table fragment |
| Heading at boundary | Heading level retained | Heading kept with following lines when practical |
| Blockquote/epigraph | Quote/cite relationships retained | Indent/alignment preserved and top-safe |
| Poetry/`<br>` | Exact line boundaries retained | Lines never collapsed into prose |
| Definition list | Term/definition parentage retained | Term kept with opening definition |
| Pre/code | Whitespace and code role retained | Monospace/scroll behavior; no silent shrink |
| Figure/caption | Figure/image/caption/alt linked | Figure and caption kept together when possible |
| Footnote/backlink | Noteref text unchanged; target/backlink IDs stable | Forward and back navigation use lazy resolver |
| Publisher contents page | List/link hierarchy retained | Number and title remain together/indented |
| EPUB 3 nav | Correct `epub:type=toc` selected | Reader Menu hierarchy and targets work |
| EPUB 2 NCX | Recursive hierarchy/hrefs retained | Same stable target behavior as EPUB 3 |
| RTL/mixed bidi | `dir` and language retained | Measurement matches render; offsets map correctly |
| CJK/ruby | Ruby and locale structure retained | Line breaking and annotations do not overlap |
| Hostile CSS | Sanitized semantic properties deterministic | Fixed widths/colors/margins cannot overflow card |
| Reflow matrix | Source IDs/offsets unchanged | No stale marker/header state after settings change |
| Legacy location | Alias/context migration resolves | Returns to equivalent source, not old card index |
| Corrupt table/list | Parser emits diagnostic and fallback | Readable prose rather than section failure |

For every structured fixture, run source tests against both lazy section parsing and the eager compatibility path because both call `_extractContent`.

### Existing coverage and gaps

Existing tests cover:

- Parser anchors, dialogue, long paragraph integrity, inline whitespace, quote/poem metadata, and one HTML table with spans: [epub_parser_chapter_test.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/test/unit/services/epub_parser_chapter_test.dart:14>).
- Heuristic and encoded table decoding: [reader_content_parser_test.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/test/unit/utils/reader_content_parser_test.dart:6>).
- Basic table widget rendering and prose annotations: [reading_card_table_test.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/test/widgets/reading_card_table_test.dart:20>).
- Lazy footnote/link/image/table loading: [feature_rich_lazy_reader_fixture_test.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/test/unit/services/feature_rich_lazy_reader_fixture_test.dart:25>).
- Active/preview prose consistency: [reading_card_renderer_consistency_test.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/test/widgets/reading_card_renderer_consistency_test.dart:19>).
- UTF-16 search projection, stable locations, and layout reflow.

There are no parser tests containing `<ul>` or `<ol>`, and no structural pagination tests for list items, table headers, adaptive columns, oversized rows, captions, top alignment, definitions, ruby, bidi, or fixed-layout detection.

### Commands and results

Inspection commands were read-only and, after loading `RTK.md`, used the required `rtk` prefix:

- `rtk git status --short`, run before and after: same pre-existing dirty state; audit created no source changes.
- `rtk git diff --stat`: 50 tracked files, `4,554 insertions`, `1,102 deletions`.
- `rtk git diff --` relevant parser/model/reader/table files: used to separate current-worktree architecture from `HEAD`.
- `rtk git show HEAD:<file> | rtk rg ...`: confirmed the list-marker and table-pagination behavior also exists in `HEAD`.
- Repository-wide `rtk rg -n`, `rtk rg --files`, `rtk sed -n`, `rtk ls -la`, and fixture/archive inventory commands: successful.
- One early fixture shell loop failed because its local shell variable was incorrectly quoted; it made no changes. The relevant fixture was subsequently exercised through its test suite.

Tests:

1. Parser/table/lazy fixture/renderer batch:

   `rtk flutter test test/unit/services/epub_parser_chapter_test.dart test/unit/utils/reader_content_parser_test.dart test/widgets/reading_card_table_test.dart test/unit/services/feature_rich_lazy_reader_fixture_test.dart test/widgets/reading_card_renderer_consistency_test.dart`

   Result: **58 passed, 0 failed**.

2. Layout/index/projection/checkpoint/location batch:

   Result: **67 passed, 18 failed**. Every reported failure came from `reader_checkpoint_store_test.dart` because the environment lacks `libsqlite3.so`; the error was `SqfliteFfiException: Failed to load dynamic library 'libsqlite3.so'`.

3. Same batch excluding the SQLite-dependent checkpoint-store suite:

   Result: **62 passed, 0 failed**.

No analyzer, dependency, build, cache migration, or write command was run during the audit.

## 12. Phased implementation plan

### Phase 1 — Semantic model foundations

- **Scope:** Add optional structural semantics, authoritative text-segment projection, fragment-state types, language/direction fields, and legacy aliases.
- **Likely files:** `lib/models/book_chunk.dart`; new `lib/models/book_structure_semantics.dart`; `lib/services/epub_parser.dart`; `lib/services/lazy_parsed_book.dart`; `lib/services/derived_book_index_service.dart`; `lib/services/reader_source_projection_service.dart`.
- **Tests:** Model serialization, old-cache decoding, source projection, generated-text exclusion.
- **Acceptance:** Ordinary prose IDs/ranges unchanged; Search/Book Memory use the authoritative projection; lazy budgets unchanged.
- **Risks:** Cache incompatibility and legacy logical-ID drift.
- **Excluded:** New visual styling, contents UI, media, fixed layout.

### Phase 2 — Lists

- **Scope:** Parser stack, complete HTML numbering semantics, list/item relationships, hanging-indent renderer, continuation fragments.
- **Likely files:** `epub_parser.dart`, `book_structure_semantics.dart`, `reader_screen.dart`, `reading_card.dart`; new `reader_list_block.dart`.
- **Tests:** All list fixtures, search/highlight/copy/Speed Reader inside items, lazy reload continuity.
- **Acceptance:** No marker-only card; nested hierarchy preserved; marker appears only on the opening fragment; markers have no source offsets.
- **Risks:** Changed chunk boundaries and legacy marker-offset migration.
- **Excluded:** Printed-contents-specific styling and list CSS beyond marker semantics.

### Phase 3 — Adaptive tables and expanded viewer

- **Scope:** Cell source metadata, captions/row groups/spans, intrinsic widths, row-safe fragmentation, repeated headers, continuation state, oversized fallback, expanded viewer.
- **Likely files:** `epub_parser.dart`, `reader_content_parser.dart`, `reader_table_block.dart`, `reader_screen.dart`, `reading_card.dart`; new `expanded_table_viewer.dart`.
- **Tests:** Table fixture matrix plus source selection/search/navigation.
- **Acceptance:** Short columns remain narrow; no card overflow; no mid-row split; true headers repeat; oversized rows remain accessible.
- **Risks:** Measurement/render divergence, gesture conflicts, complex span layout cost.
- **Excluded:** General-purpose HTML/CSS table engine and layout-table perfection.

### Phase 4 — Structural pagination and alignment

- **Scope:** Shared grouping policy, heading keep-with-next, figure/caption, table caption/header grouping, widows/orphans, structured top alignment.
- **Likely files:** `reader_screen.dart`, `final_layout_paragraphs.dart`, `reading_card.dart`, display-cache/signature services.
- **Tests:** Boundary fixtures across font, density, orientation, viewport, and card modes.
- **Acceptance:** Hard constraints always hold; soft constraints degrade predictably; ordinary prose remains unchanged.
- **Risks:** Page-count changes and exact-layout cache invalidation.
- **Excluded:** New semantic categories beyond those already modeled.

### Phase 5 — Headings, figures, blockquotes, scene breaks

- **Scope:** Heading levels, figure/alt/caption relationships, quote citations, scene-break source nodes.
- **Likely files:** Parser/model, `reading_card.dart`, new small specialized widgets.
- **Tests:** Structure parsing, grouping, accessibility labels, source mapping.
- **Acceptance:** Hierarchy survives; related blocks remain together when possible; `<hr>` no longer disappears.
- **Risks:** Publisher class heuristics misclassifying decorative blocks.
- **Excluded:** Full publisher CSS cascade and SVG/MathML.

### Phase 6 — Footnotes and internal links

- **Scope:** Role-based noteref/note/backlink parsing, unchanged source labels, link preservation in structured content, broken-anchor UX, stable return history.
- **Likely files:** `epub_parser.dart`, `lazy_section_repository.dart`, `lazy_book_session.dart`, `reader_screen.dart`, structured widgets.
- **Tests:** Same-section, cross-section, unloaded-target, malformed-anchor, backlink, link-history cases.
- **Acceptance:** Links resolve lazily; checkpoint is not overwritten by temporary traversal; return action uses the existing stable stack.
- **Risks:** Publisher note conventions and relative href normalization.
- **Excluded:** Contents redesign and external browser policy changes.

### Phase 7 — Poetry, definitions, code, plays, asides

- **Scope:** Verse line groups, definition lists, inline code, explicit pre renderer, speaker/stage roles, callouts.
- **Likely files:** Parser/model, pagination, specialized widgets.
- **Tests:** Whitespace, line breaks, selection, pagination, copy/Speed Reader.
- **Acceptance:** Intentional line/block relationships survive reflow.
- **Risks:** Over-classification from publisher class names.
- **Excluded:** Math, ruby, fixed-layout, media.

### Phase 8 — International and fixed-layout handling

- **Scope:** `lang`, `dir`, bidi measurement, CJK breaks, ruby, MathML fallback, fixed-layout and scripted/media capability detection.
- **Likely files:** EPUB index/model, parser, measurement/rendering, open-route capability handling.
- **Tests:** RTL/mixed/CJK/ruby fixtures and fixed-layout metadata fixtures.
- **Acceptance:** Measurement matches rendered direction; unsupported fixed/scripted content is explicit rather than incorrectly flattened.
- **Risks:** Font fallback and platform rendering differences.
- **Excluded:** Full fixed-layout viewer, SMIL playback, JavaScript execution.

### Phase 9 — Contents experience

- **Scope:** Harden EPUB 2/3 nav selection; use semantic list/link support for publisher pages; later optional contents-page-specific presentation.
- **Likely files:** vendored `epubx` navigation reader, lazy index/session, chapter panel, parser, reader link navigation.
- **Tests:** Multiple `<nav>` elements, tokenized properties, nested hierarchy, missing/broken anchors, printed contents.
- **Acceptance:** Reader Menu and printed contents remain distinct; both target stable lazy locations; return history works.
- **Risks:** Malformed navigation and duplicated publisher TOCs.
- **Excluded:** This entire phase from the first implementation.

## 13. Recommended first implementation slice

The smallest safe slice that visibly addresses the reported list and table failures is:

1. Add optional list/table semantic sidecars and a central authoritative-text projection.
2. Replace list booleans/counter with a parser stack.
3. Stop inserting generated list markers into source text.
4. Add a list renderer with marker column, hanging indent, nesting depth, and opening/continuation state.
5. Add simple adaptive table widths using measured min/preferred content.
6. Preserve true header rows and captions; split only between rowspan-independent rows.
7. Add explicit table continuation state.
8. Top-align list/table cards.
9. Add a non-clipping oversized-row fallback with an expanded viewer.
10. Update Search, Book Memory, Speed Reader, selection mapping, and checkpoint source coverage to use authoritative list/table text.

Likely touched files:

- [book_chunk.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/models/book_chunk.dart:237>)
- [epub_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/epub_parser.dart:530>)
- [reader_content_parser.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/utils/reader_content_parser.dart:7>)
- [reader_screen.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/screens/reader_screen.dart:3420>)
- [reading_card.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reading_card.dart:2696>)
- [reader_table_block.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/widgets/reader_table_block.dart:6>)
- [derived_book_index_service.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/derived_book_index_service.dart:411>)
- [book_memory_service.dart](</home/uttam/Desktop/Antigravity Projects/Nalori/lib/services/book_memory_service.dart:380>)

Acceptance criteria:

- No bullet/number can be separated from the first item line.
- Nested depth and ordered values survive parsing, caching, reflow, and lazy reload.
- Generated markers never occur in authoritative text or indexes.
- Two-column label/value tables allocate visibly unequal widths where content warrants it.
- Tables never extend beyond their card without a scroll/expand affordance.
- Long tables repeat actual headers and show continuation state.
- No row is split or silently vertically clipped.
- List/table cards are top-aligned; ordinary narrative cards retain current behavior.
- Search, highlights, notes, copying, Speed Reader, and restoration pass inside list items and table cells.
- Existing ordinary-prose renderer and source-projection tests remain unchanged and pass.

Explicitly exclude contents UI, general CSS cascade, headings/figures beyond any prerequisite grouping hooks, MathML, ruby, fixed-layout rendering, media overlays, and a broad `BookChunk` rewrite.

## 14. Open decisions

1. **Wide-table interaction:** use in-card horizontal scrolling or make wide tables preview-only.  
   Recommended default: compact/long-narrow tables remain interactive on-card; wide/complex tables show a bounded preview and open a dedicated viewer.

2. **Table selection scope:** require full cross-cell selection immediately or begin with cell-local selection.  
   Recommended default: cell-local rich selection/highlights plus continuous copy/export in the expanded viewer; add cross-cell on-card selection only if Flutter selection behavior proves stable.

3. **Legacy list/table migration depth:** preserve every old generated-marker offset or rely on context fallback for unreleased formats.  
   Recommended default: inspect release history; if these logical IDs reached users, add explicit marker-prefix and encoded-table aliases. Otherwise invalidate only parsed/derived caches.

4. **Structured-card alignment:** top-align every card containing structured content or only dominant structured cards.  
   Recommended default: top-align list/table/pre/reference fragments and their continuations; leave mixed heading-plus-narrative cards under ordinary prose behavior.

5. **Layout-table classification:** automatically reinterpret presentation-like tables or always treat ambiguous cases as data.  
   Recommended default: only reinterpret explicit `role="presentation"` or high-confidence layout signatures; ambiguous tables remain data tables.

6. **Fixed-layout EPUB product behavior:** reject, warn and reflow, or build a separate viewer.  
   Recommended default: detect and clearly mark unsupported fixed layout now; do not silently reflow it as though structure were preserved.
