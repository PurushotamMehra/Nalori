# Nalori reader measurement, rendering, and layout-identity inventory

## 1. Scope and verified baseline

This is the discovery record for TASK-P05-001, produced by static tracing on
2026-09-09. It records current production behavior; it neither selects the
future contract nor changes code, tests, versions, cache records, checkpoints,
fixtures, or P03/P04 evidence.

The frozen baseline is CHANGE-20260908-021: P04 is COMPLETED (8/8), P03 is
COMPLETED (7/7), overall progress is 32/89 before this task, and P05 had not
started. The independent P04 gate passed 3/3 on three runs; complete P04 was
69/69, unchanged P03 was 57/57, and frozen P02 controls were 9/9. REQ-007,
REQ-008, REQ-011, REQ-012, REQ-013, and REQ-048 remain verified. P04 canonical
memberships, source ownership, identities, continuations, bounds, and source
range oracle are not reopened here. A later, proved measure/render correction
may change physical card boundaries, but cannot be used to relabel a
construction-order defect.

This inventory covers 91 primary field-level rows, plus 25 issue,
unresolved-input, and ownership rows (116 table rows total). “Evidence” names
the durable file and symbol/call path, rather than treating line numbers as
authority. The result labels have the meanings required by P05:
MATCHED, MEASURE_ONLY, RENDER_ONLY, DIFFERENT_RESOLUTION,
MISSING_FROM_IDENTITY, EXTRANEOUS_IN_IDENTITY,
TRANSIENT_CORRECTLY_EXCLUDED, ASYNC_UNCONTROLLED,
PLATFORM_DEPENDENT, and UNRESOLVED.

For table readability only, a filename stem in Evidence expands to this exact
repository-relative path: reader_screen.dart is
lib/screens/reader_screen.dart; reading_card.dart is
lib/widgets/reading_card.dart; reading_card_deck.dart is
lib/widgets/reading_card_deck.dart; reader_card_paginator.dart is
lib/services/reader_card_paginator.dart; book_cache_service.dart is
lib/services/book_cache_service.dart; reading_settings.dart is
lib/models/reading_settings.dart; book_chunk.dart is lib/models/book_chunk.dart;
canonical_pagination.dart is lib/models/canonical_pagination.dart;
reader_checkpoint.dart is lib/models/reader_checkpoint.dart;
final_layout_paragraphs.dart is lib/utils/final_layout_paragraphs.dart;
reader_list_layout.dart is lib/utils/reader_list_layout.dart; and
reader_content_parser.dart is lib/utils/reader_content_parser.dart. Every
other table evidence entry gives its full repository-relative path directly.

## 2. Current layout pipeline and authority flow

There is no final immutable layout contract today. Current authority is split:

1. EPUB/lazy parsing creates BookChunk structural fields, source ranges,
   inline styles, footnotes, list semantics, publisher layout attributes,
   images, and block roles. The parser compatibility identity begins in
   lib/services/lazy_parsed_book.dart (lazyParsedSectionParserVersion) and
   lib/services/epub_parser.dart; canonical source identity is pinned by
   CanonicalPaginationSourceSnapshot.pin in
   lib/services/reader_card_paginator.dart.
2. ReaderScreen reads MediaQuery size, viewPadding, TextScaler and locale in
   _ReaderScreenState._ensureDisplayChunksBuilt. It deliberately derives
   displaySafeArea with _canonicalDisplaySafeArea, which removes bottom
   viewPadding.
3. ReaderScreen constructs a cache key, DisplayGenerationSignature and
   _activeReaderLayoutFingerprint, then waits for GoogleFonts.pendingFonts in
   _loadOrRebuildDisplayChunks. Failure is logged but does not stop fallback
   pagination.
4. _rebuildDisplayChunksAsync calls resolveReaderLayoutMetrics with that
   canonical safe area, then passes styles, struts, scaler, width and height
   budgets to ReaderCardPaginatorLayout. ReaderCardPaginator._runEngine is the
   production measurement/finalization kernel and emits canonical P04 cards.
5. The PageView/ReadingCardDeck gives each ReadingCard its constraints.
   ReadingCard.build independently reads MediaQuery size and raw viewPadding,
   calls resolveReaderLayoutMetrics again, and constructs its Text/selection/
   decoration tree.
6. Canonical ReaderCardIdentity is built from publication fingerprint,
   controlled layout fingerprint, pagination version, and ordered canonical
   source slices in CanonicalReaderCardIdentityBuilder. The layout fingerprint
   is also carried into checkpoints. Whole and segmented display caches have
   additional cache-specific records.

Thus parser/source records are canonical structural authority (P04); the
layout inputs passed to measurement are an adapter; ReadingCard resolves a
second, nonidentical presentation input; and cache/checkpoint compatibility
uses a duplicated string projection of only part of the effective layout.

## 3. Exact card-body geometry

Let V be MediaQuery.sizeOf(context), S be the safe area supplied to the
resolver, M be readerCardMargin, and P be contentPadding. The resolver computes:

    P.left   = S.left + clamp(settings.sideMargin, 12, 56)
    P.right  = S.right + clamp(settings.sideMargin, 12, 56)
    P.top    = S.top + boundaryTop + (cardDepth ? 40 : 0)
    P.bottom = S.bottom + boundaryBottom + (cardDepth ? 42 : 0)
    body width  = max(1, V.width  - P.horizontal - M.horizontal)
    body height = max(1, V.height - P.vertical   - M.vertical)

boundaryTop/boundaryBottom are 14/16 logical px except fullPage (4/6).
When card depth is enabled M is 18/28/18/42 (left/top/right/bottom), except
fullPage where it is 14/22/14/34; otherwise M is zero. Measurement uses a
safety buffer clamp((effectiveLineBoxHeight * .65) + depthBias, 14, 36), with
depthBias 4. Its ordinary page budget is the density ratio (.25/.50/.75/1.0)
of max(body height - safety, 2.4 lines); publisher-layout content can use the
larger physical budget max(page budget, body height - safety).

Rendering puts an AnimatedContainer with M inside the deck constraint and a
Padding with P inside that card. The text child is constrained by the padded
box. Its actual readable rectangle is therefore the formula above, *except*
that ReadingCard uses raw MediaQuery.viewPadding whereas measurement uses the
bottom-stripped displaySafeArea. The depth header/footer are visually positioned
within fixed 40/42 reserves. Page controls, toolbars, speed-reader FAB and
other Stack siblings do not constrain that box; resizeToAvoidBottomInset is
false. Deck transforms and live scale are paint/hit-test effects, not layout
constraints.

| Input/field | Source of authority | Measurement consumer | Rendering consumer | Identity/fingerprint consumer | Current equivalence | Classification | Evidence | Owning follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Logical viewport width | MediaQuery.sizeOf in ReaderScreen | availableWidth in resolveReaderLayoutMetrics | ReadingCard LayoutBuilder and resolver | cache key, viewportSignature, layout fingerprint | Same logical V.width at a generation | MATCHED | lib/screens/reader_screen.dart: _ensureDisplayChunksBuilt, resolveReaderLayoutMetrics; lib/widgets/reading_card.dart: ReadingCardState.build | P05-002 |
| Logical viewport height | MediaQuery.sizeOf in ReaderScreen | availableHeight, budgets and tiny-fragment policy | ReadingCard SizedBox/resolver | same | Same V.height unless a rebuild races a view transition | MATCHED | reader_screen.dart: _rebuildDisplayChunksAsync; reading_card.dart: build | P05-002 |
| Orientation | Derived only from V.width/V.height | No explicit branch | No explicit branch | dimensions only | Width/height changes are represented; orientation name is not needed | MATCHED | reader_screen.dart: _ensureDisplayChunksBuilt | P05-002 |
| Device-pixel ratio | Ambient MediaQuery | Not read | Not read | Not included | Logical layout agrees, but raster/hinting consequences are not identified | PLATFORM_DEPENDENT | reader_screen.dart: resolveReaderLayoutMetrics; reading_card.dart: build | P05-007 |
| Safe-area left/right | MediaQuery.viewPadding | displaySafeArea preserves left/right | raw viewPadding | canonical L/R in key/signature | Same numeric values in current flow | MATCHED | reader_screen.dart: _canonicalDisplaySafeArea, _ensureDisplayChunksBuilt; reading_card.dart: build | P05-002 |
| Safe-area top | MediaQuery.viewPadding | displaySafeArea preserves top | raw viewPadding | canonical top in key/signature | Same numeric value | MATCHED | reader_screen.dart: _canonicalDisplaySafeArea/_ensureDisplayChunksBuilt; reading_card.dart: ReadingCardState.build | P05-002 |
| Safe-area bottom | MediaQuery.viewPadding | _canonicalDisplaySafeArea replaces it with 0 | ReadingCard.build uses raw bottom | key/fingerprint encode 0; diagnostic records raw value only | Measured body is taller than rendered body by raw bottom inset | DIFFERENT_RESOLUTION | reader_screen.dart: _canonicalDisplaySafeArea, _ensureDisplayChunksBuilt, _rebuildDisplayChunksAsync; reading_card.dart: ReadingCardState.build | P05-002, P05-003, P05-005 |
| System viewInsets / keyboard | MediaQuery ambient | Not read | Scaffold.resizeToAvoidBottomInset is false; card does not read viewInsets | Not included | Keyboard cannot trigger controlled reflow; obscuration behavior needs a widget probe | UNRESOLVED | reader_screen.dart: ReaderScreen Scaffold build; _ensureDisplayChunksBuilt | P05-005 |
| Card-depth mode | settings.enableCardDepth | M, reserves, safety bias | M, border/header/footer/back layers | cache key, settingsSignature | Same resolver input | MATCHED | reader_screen.dart: readerCardMargin, resolveReaderLayoutMetrics; reading_card.dart: _buildReadingSurface | P05-002 |
| Density/full-page mode | settings.contentDensity | boundary insets, density ratio, tiny policy | boundary insets and card margin; does not enforce paginator budget | densityMultiplier, not enum name | Same resolved margin/insets; multiplier is a separate projection | MATCHED | reader_screen.dart: readerDensityPolicy, readerBoundaryTopInset, readerCardMargin | P05-002 |
| User side margin | settings.sideMargin | P.left/P.right after 12..56 clamp | same resolver | raw sideMargin in signatures/cache | Same final clamp, but identity distinguishes values that clamp identically | EXTRANEOUS_IN_IDENTITY | reader_screen.dart: readerHorizontalContentPadding, _ensureDisplayChunksBuilt; book_cache_service.dart: displayChunkKey | P05-002, P05-006 |
| Fixed top/bottom boundaries | constants kBoundaryTop/Bottom and fullPage variants | Included in P | Included in P | Only indirectly by density/card mode and v14 | Same constants now; no explicit renderer-version identity | MATCHED | reader_screen.dart: constants, resolveReaderLayoutMetrics | P05-002 |
| Depth header/footer reservation | constants 40/42 | Included in P and budgets | Header/footer painted inside reserved bands | enableCardDepth only | Same fixed reservation, subject to bottom-safe mismatch | MATCHED | reader_screen.dart: kReaderCardDepthHeaderReserve/FooterReserve; reading_card.dart: _buildDepthHeader, _buildDepthFooter | P05-002 |
| Depth border width 1.8 | kReaderCardDepthBorderWidth | Not subtracted by resolver | BoxDecoration.border may inset child layout under Flutter box model | Not separately included | Static code does not prove whether the border changes child constraints relative to P | UNRESOLVED | reader_screen.dart: kReaderCardDepthBorderWidth; reading_card.dart: _buildReadingSurface | P05-007 |
| Paginator safety buffer | effectiveLineBoxHeight and depth | Reduces text budget, affects split/finalization | No corresponding spacer/constraint in card | effective typography inputs, no named buffer | Intentional measurement-only headroom; visual overflow relationship is unproven | MEASURE_ONLY | reader_screen.dart: resolveReaderLayoutMetrics, _rebuildDisplayChunksAsync | P05-002, P05-003 |
| Publisher left/right padding | BookChunk publisher fields | Subtracted per chunk | Padding around body | structural source slices, not layout signature | Same resolveReaderPublisherPadding call | MATCHED | reader_card_paginator.dart: _runEngine.measureTextHeight; reading_card.dart: _buildBodyContent; lib/models/book_chunk.dart | P05-002 |
| Dialogue inset | kReaderDialogueTextInset = 0 | Subtracted only if dialogue | same zero inset | structural source identity | Numerically matched, currently no effect | MATCHED | reader_card_paginator.dart: kReaderDialogueTextInset, _runEngine; reading_card.dart: _buildBodyContent | P05-002 |
| Deck constraints | ReadingCardDeck LayoutBuilder/Positioned.fill | Assumed V in ReaderScreen | Supplies bounded card constraint | Not represented separately | Same only while deck fills MediaQuery viewport; focused probe required for embedding/non-fullscreen route | UNRESOLVED | lib/widgets/reading_card_deck.dart: ReadingCardDeck.build; reader_screen.dart: ReaderScreen build | P05-005 |
| Stack/drag/depth-lift transforms | card deck and _liveScale animations | Not read | Transform/opacity/back layers only | Not included | Paint and hit-test only; should stay out | TRANSIENT_CORRECTLY_EXCLUDED | reading_card_deck.dart: card transform builders; reader_screen.dart: _liveScale; reading_card.dart: _buildBackCardLayer | P05-005 |
| Overlay controls/toolbars/FAB | ReaderScreen Stack | Not read | Positioned siblings over the deck | Not included | Do not change deck constraints; may occlude visually | TRANSIENT_CORRECTLY_EXCLUDED | reader_screen.dart: ReaderScreen build, Scaffold.resizeToAvoidBottomInset | P05-005 |

## 4. Typography and resolved-font flow

ReaderFontFamily, ReaderFontWeight, ReaderFontSize, lineHeight and the static
ReaderFontMetricProfile are the declared configuration. ReadingSettings
getTextStyle selects a GoogleFonts family, requested normal body weight, an
optically compensated logical font size, height, color, and heading
weight w900/letterSpacing 2. getBodyStrutStyle/getHeadingStrutStyle force the
declared family/size/weight line box with leading zero. Measurement copies locale
onto TextStyle but not onto the separately constructed StrutStyle; rendering
does the same pattern.

The following identities must not be conflated:

- Declared configuration identity: settings font family/weight/size, static
  reader_typography_v1 profile values, requested GoogleFonts family and
  variants.
- Font-file byte identity: only test/reader_contract assets supply recorded
  Lexend 400/600/700/900 SHA-256 values. pubspec.yaml declares them as assets,
  not production fonts; the contract harness registers them under its
  test-only FontLoader alias.
- Resolved runtime font identity: GoogleFonts pendingFonts is awaited after
  requesting normal/heading styles, but a failure is accepted and the actual
  platform/fallback face is neither captured nor fingerprinted. List w600,
  inline w700/italic, table w500/w800, and preformatted monospace are not
  explicitly primed by that request.
- Resolved metric/glyph identity: Flutter does not expose one here. No
  current digest proves the selected face, glyph fallback, shaping, line
  metrics, or missing-glyph fallback. Test-only Lexend byte hashes therefore
  do not prove production runtime metric identity.

| Input/field | Source of authority | Measurement consumer | Rendering consumer | Identity/fingerprint consumer | Current equivalence | Classification | Evidence | Owning follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Declared family | ReadingSettings.fontFamily | body/heading TextStyle and struts | getTextStyle and struts | cache/settingsSignature/fontMetricIdentity | Same requested family | MATCHED | lib/models/reading_settings.dart: getTextStyle, getBodyStrutStyle, fontMetricIdentity; reader_screen.dart: _rebuildDisplayChunksAsync | P05-002 |
| Requested body weight | ReadingSettings.fontWeightValue | body style and body strut | body style and body strut | cache/settingsSignature/fontMetricIdentity | Same requested normal weight | MATCHED | reading_settings.dart: fontWeightValue, getTextStyle | P05-002 |
| Heading w900 | getTextStyle(isHeading:true) | heading TextSpan | heading SelectableText | Not separately named; settings family/metric only | Both request w900; availability/resolution unproven | ASYNC_UNCONTROLLED | reading_settings.dart: getTextStyle; reader_card_paginator.dart: measureTextHeight; reading_card.dart: _buildHeadingContent | P05-004 |
| Inline bold/italic | BookChunk.inlineStyles | Plain span measurement omits style runs | _styledTextSpan applies w700 and FontStyle.italic | rich source digest, no renderer typography field | Render can wrap/measure differently | DIFFERENT_RESOLUTION | reading_card_paginator.dart: _runEngine.measureTextHeight; reading_card.dart: _styledTextSpan | P05-003 |
| Footnote marker typography | BookChunk.footnotes | Measured as ordinary literal marker | 0.75 size, w600, link recognizer | footnote/rich source digest only | Render has different metrics | DIFFERENT_RESOLUTION | reading_card.dart: _buildStyledTextSpan; reader_card_paginator.dart: _runEngine.measureTextHeight | P05-003 |
| Font size and optical compensation | semantic size plus static profile | body/heading styles, line-box/safety | same style construction | fontSizeValue plus fontMetricIdentity | Same declared result, not verified resolved metrics | MATCHED | reading_settings.dart: fontSizeMultiplier, fontSizeValue, effectiveLineBoxHeight | P05-002 |
| Line height and forced strut | lineHeight/static profile | TextPainter + body/heading strut | Text.rich/SelectableText + strut | lineHeight/fontMetricIdentity | Same declared strut shape; locale absent from strut | MATCHED | reading_settings.dart: getBodyStrutStyle, getHeadingStrutStyle; final_layout_paragraphs.dart | P05-002 |
| Letter/word spacing | TextStyle defaults; heading letterSpacing 2 | heading style; body 0 | same styles; table/pre override styles | No separate field | Body/heading match; wordSpacing remains implicit null | MATCHED | reading_settings.dart: getTextStyle; reader_card_paginator.dart: tableMeasurementStyle | P05-002 |
| Table/preformatted typography | renderer-specific constants | Table estimator uses cell 13..18, height 1.2..1.45, w500/w800; no preformatted branch | table widget and monospace preformatted widget | No distinct renderer-structure input | Table constants differ; preformatted is unmeasured | DIFFERENT_RESOLUTION | reader_card_paginator.dart: tableMeasurementStyle; lib/widgets/reader_table_block.dart: ReaderTableBlockWidget/ReaderPreformattedBlockWidget | P05-003 |
| Text width basis | V, safe area, margins, publisher/list insets | TextPainter maxWidth | padded LayoutBuilder, Row/Expanded | viewport/margins in key | Same except raw bottom does not change width; table minimum width differs | MATCHED | reader_screen.dart: resolveReaderLayoutMetrics; reader_list_layout.dart; reading_card.dart: _buildBodyContent | P05-002 |
| Text alignment | settings.resolvedTextAlign and chunk role | resolveReaderChunkTextAlign to TextPainter | same helper to Text.rich | Omitted from key/signature and rebuild predicate | Static helper agrees, but justify/RTL line-breaking and update lifecycle require a mutation test | MISSING_FROM_IDENTITY | lib/models/reading_settings.dart: resolvedTextAlign; lib/models/book_chunk.dart: resolveReaderChunkTextAlign; reader_screen.dart: readerSettingsRequireDisplayChunkRebuild | P05-002, P05-007 |
| Directionality | Ambient Directionality | Every paginator TextPainter forces LTR | Text widgets inherit ambient Directionality | Omitted | RTL can differ from LTR measurement | DIFFERENT_RESOLUTION | reader_card_paginator.dart: _runEngine TextPainter calls; reading_card.dart: Text.rich/SelectableText | P05-002, P05-003 |
| Locale | Localizations.maybeLocaleOf | copied to body/heading TextStyle and TextPainter | copied to TextStyle | language tag in key/signature | Same TextStyle locale; struts lack locale and fallback face unknown | MATCHED | reader_screen.dart: _ensureDisplayChunksBuilt, _rebuildDisplayChunksAsync; reading_card.dart: build | P05-002 |
| Text scaling | MediaQuery.textScalerOf | ReaderCardPaginatorLayout.textScaler | MediaQuery.textScalerOf | scale(1.0) only, rounded to 2 decimals in cache key | Same live scaler normally; nonlinear curve identity can collide | MISSING_FROM_IDENTITY | reader_screen.dart: _ensureDisplayChunksBuilt, _rebuildDisplayChunksAsync; book_cache_service.dart: displayChunkKey | P05-002, P05-007 |
| Accessibility bold/high contrast | MediaQuery/platform | Reader code does not read | Explicit reader styles; ambient engine effect not established | Omitted | Need platform/widget probe to show whether explicit styles neutralize or inherit it | UNRESOLVED | reader_screen.dart: _ensureDisplayChunksBuilt; reading_card.dart: build | P05-007 |
| Declared static metric profile | readerFontMetricProfiles | font size/line box/safety | style/strut construction | fontMetricIdentity | Correctly participates as declared metric policy, not as resolved face | MATCHED | reading_settings.dart: readerFontMetricProfiles, fontMetricIdentity | P05-002 |
| Google Fonts readiness/fallback | GoogleFonts font loader/platform fallback | pendingFonts awaited; error continues into pagination | widgets can resolve later or use fallback | declared metric string only | No ready/fallback/resolved transition identity | ASYNC_UNCONTROLLED | reader_screen.dart: _loadOrRebuildDisplayChunks; reading_settings.dart: getTextStyle | P05-004 |
| Bundled test Lexend files | pubspec assets and FontLoader harness | Controlled test-only harness | Controlled test-only harness | Not production identity | Bytes are useful fixture evidence only | PLATFORM_DEPENDENT | pubspec.yaml: assets/fonts/reader_contract; test/reader_contract/README.md: deterministic layout/font environment | P05-004 |
| Missing glyph and platform fallback order | Font manager/GoogleFonts/platform | TextPainter resolves implicitly | Text widgets resolve implicitly | Omitted | Cannot determine face or metrics statically | PLATFORM_DEPENDENT | reading_settings.dart: GoogleFonts calls; reader_screen.dart: GoogleFonts.pendingFonts | P05-004, P05-007 |

## 5. Structural-content measurement/render map

P04 freezes ownership/source ranges for structures. This table concerns only
how that already-owned structure is measured and painted. The shared pure
helpers are finalLayoutParagraphs.dart (segment splitting, paragraph gap and
TextPainter measurement), reader_list_layout.dart (indent/marker/gap), and
BookChunk publisher/alignment resolvers. Equality of helper names is not
treated as proof where their input TextSpans differ.

| Input/field | Source of authority | Measurement consumer | Rendering consumer | Identity/fingerprint consumer | Current equivalence | Classification | Evidence | Owning follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Ordinary paragraph text | BookChunk.text/textBoundaries | measureFinalLayoutParagraphTextHeight | splitFinalLayoutParagraphSegments plus Text.rich | canonical source text/ranges; not a layout field | Same split/gap helper and declared style when no rich decoration | MATCHED | lib/utils/final_layout_paragraphs.dart; reader_card_paginator.dart: _runEngine.measureTextHeight; reading_card.dart: buildParagraphSeparatedBodyContent | P05-003 |
| Continued/split paragraph | canonical fragment/source range/text boundaries | same helper with boundaries only for whole chunk | same helper with chunk boundaries | ordered canonical source slices | Shared helper; fragment-path parity needs a focused split widget case | UNRESOLVED | final_layout_paragraphs.dart; reader_card_paginator.dart: measureTextHeight; reading_card.dart: buildParagraphSeparatedBodyContent | P05-007 |
| Source heading text | BookChunk.isHeading | TextPainter heading span only | centered SelectableText, then 20px gap and divider text | heading structural source digest | Renderer has unmeasured decoration/gap | RENDER_ONLY | reader_card_paginator.dart: measureTextHeight; reading_card.dart: _buildHeadingContent | P05-003 |
| Generated navigation/chapter heading | canonical generated structural owner | Paginator treats resulting heading chunk as above | same heading path; card header title is separate fixed overlay | generated source identity and slices | Generated source identity is frozen; visual decoration is not measured | RENDER_ONLY | reader_screen.dart: canonical source construction; reading_card.dart: _buildHeadingContent/_buildDepthHeader | P05-003 |
| Publisher structured prose/poem/quote/epigraph/letter | BookBlockRole, preserve flags, publisher alignment/padding | usesPublisherLayout takes TextSpanUtils.buildSpacedTextSpan | usually paragraph-segment renderer unless content parser detects table/pre | publisher structural digest in source slice | Separate paragraph-spacing implementations; effective line/break equivalence is unproved | UNRESOLVED | lib/models/book_chunk.dart: usesPublisherLayout; reader_card_paginator.dart: measureTextHeight; reading_card.dart: _buildBodyContent | P05-003, P05-007 |
| Ordered/unordered list marker/indent | effectiveListDisplaySegments/list semantics | resolveReaderListLayoutMetrics; marker width based on base body style | same metrics; marker rendered w600 with body strut | list structural digest | Body inset helper matches, marker weight differs | DIFFERENT_RESOLUTION | lib/utils/reader_list_layout.dart; reader_card_paginator.dart: measureTextHeight; reading_card.dart: buildListContent | P05-003 |
| List body rich spans | inlineStyles/footnotes/highlights | plain body TextSpan | styled/highlighted body TextSpan | rich/list source digests | Same width/inset, different run metrics | DIFFERENT_RESOLUTION | reader_card_paginator.dart: measureTextHeight; reading_card.dart: buildTextBlock | P05-003 |
| Decoded table width/rows | ReaderContentBlock parser/table role | estimateTableHeight: min 120 or 156 columns, cell padding arithmetic, +22 | ReaderTableBlockWidget: table min width count*156, padding/border/widget layout | table row structural source ranges | Different column basis and nonshared vertical box model | DIFFERENT_RESOLUTION | lib/utils/reader_content_parser.dart; reader_card_paginator.dart: tableMeasurementStyle/estimateTableHeight; lib/widgets/reader_table_block.dart: ReaderTableBlockWidget | P05-003 |
| Table cell spans/row spans | ReaderTableCell parser model | Expanded text rows only | widget consumes decoded ReaderTableBlock | table structural digest | Static measurement does not establish widget handling equivalence for spans | UNRESOLVED | reader_content_parser.dart: ReaderTableBlock.fromCellRows; reader_card_paginator.dart: tableMeasurementStyle | P05-007 |
| Preformatted content | BookBlockRole.preformatted/content parser | No preformatted branch; normal/publisher TextPainter can wrap | ReaderPreformattedBlockWidget uses monospace, horizontal scrolling, padding/border | structural source digest | Materially different font/wrap/box | DIFFERENT_RESOLUTION | reader_card_paginator.dart: measureTextHeight; lib/widgets/reader_table_block.dart: ReaderPreformattedBlockWidget; reader_content_parser.dart | P05-003 |
| Rich bold/italic/link spans | inlineStyles and links | Plain text spans except headings/publisher generic style | _styledTextSpan gives bold/italic/recognizers | rich metadata digest in canonical slice | Run style omitted by measurement | DIFFERENT_RESOLUTION | reading_card.dart: _styledTextSpan; reader_card_paginator.dart: measureTextHeight | P05-003 |
| Footnote references | FootnoteRef positions/labels | Ordinary literal characters | reduced tappable marker style | footnote digest in source slice | Run style omitted by measurement | DIFFERENT_RESOLUTION | reading_card.dart: _buildStyledTextSpan; lib/models/book_chunk.dart: FootnoteRef | P05-003 |
| Explicit fragments/separator synthesis | textBoundaries/canonical slice builder | final-layout splitting and canonical finalizer | final-layout splitting | canonical source ranges/fragment digest | Normal paragraph helper is shared; generated/publisher cases need parity proof | UNRESOLVED | final_layout_paragraphs.dart; reader_card_paginator.dart: buildCanonical.../measureTextHeight | P05-007 |
| Images | BookChunk.imageBytes/type | Text height is zero/empty; image retained as atomic source chunk | Image.memory intrinsic decode plus 16px lower padding | content checksum/source slice, no image metric identity | Rendered image has no corresponding measured height and can resolve asynchronously | RENDER_ONLY | reader_card_paginator.dart: _runEngine.measureTextHeight; reading_card.dart: _buildBodyContent | P05-003, P05-007 |
| Inline widgets | Parser/InlineSpan API | No WidgetSpan found in production reader path | No WidgetSpan found; image is block Image.memory | N/A | Not currently present; keep contract field guarded against future introduction | TRANSIENT_CORRECTLY_EXCLUDED | repository symbol search: WidgetSpan/InlineSpan; reading_card.dart | P05-002 |

## 6. Interaction and decoration classification

| Input/field | Source of authority | Measurement consumer | Rendering consumer | Identity/fingerprint consumer | Current equivalence | Classification | Evidence | Owning follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Active versus preview card | deck index/isActivePage | Not read | enables selection/handlers; speed-read condition | Not included | Expected interaction-only except speed-read branch below | TRANSIENT_CORRECTLY_EXCLUDED | reading_card_deck.dart: deck item build; reading_card.dart: _usesInteractiveText | P05-005 |
| SelectionArea/SelectionListener | isActivePage and selection state | Not read | wrapper and selection menu | Not included | Wrapper should not change text constraints; verify selection widget parity | TRANSIENT_CORRECTLY_EXCLUDED | reading_card.dart: wrapSelectableBody, _usesInteractiveText | P05-007 |
| Selection color/highlight color | settings and annotation state | Not read | DefaultSelectionStyle/TextSpan background/foreground | Not included | Paint only when no font/style substitution | TRANSIENT_CORRECTLY_EXCLUDED | reading_card.dart: _activeSelectionColor, _buildHighlightedTextSpan | P05-005 |
| Link and footnote recognizers | links/FootnoteRef and active state | Not read | TapGestureRecognizer | Not included | Recognizers alone have no layout effect; footnote style is separately a mismatch | TRANSIENT_CORRECTLY_EXCLUDED | reading_card.dart: _styledTextSpan, _buildStyledTextSpan | P05-003 |
| Highlights and notes | Highlight service/ranges | Not read | span backgrounds and _NoteHighlightBackdrop TextPainter | Not included | Decoration/overlay only; must remain excluded unless it changes text style | TRANSIENT_CORRECTLY_EXCLUDED | reading_card.dart: _buildHighlightedTextSpan, _NoteHighlightBackdrop | P05-005 |
| Character-name markers | character match ranges | Not read | colored/shadowed spans | Not included | Paint/shadow only in current span construction | TRANSIENT_CORRECTLY_EXCLUDED | reading_card.dart: _buildHighlightedTextSpan | P05-005 |
| Speed Reader active state | SpeedReadController/current card | Not read | replaces normal paragraph segments with one span and applies speed spans | Not included | Intended transient state changes render tree, paragraph gaps and footnote handling | RENDER_ONLY | reading_card.dart: _buildBodyContent, buildParagraphSeparatedBodyContent, _buildSpeedReadTextSpan | P05-003, P05-005 |
| Speed Reader lyrics/window overlay | speed display mode/controller | Not read | Text span styling and Positioned.fill overlay | Not included | Overlay itself paint-only; active-body branch above can change layout | TRANSIENT_CORRECTLY_EXCLUDED | reading_card.dart: SpeedReadOverlay, _buildBodyContent | P05-005 |
| Tap/pointer/gesture callbacks | Listener/GestureDetector/controller | Not read | input only | Not included | No constraint change | TRANSIENT_CORRECTLY_EXCLUDED | reading_card.dart: build, _handleFullSurfacePointerUp | P05-005 |
| Card/deck animation progress | animation controllers/depthLift | Not read | AnimatedContainer, Transform, opacity/back layers | Not included | Paint/hit test only | TRANSIENT_CORRECTLY_EXCLUDED | reading_card_deck.dart; reading_card.dart: _buildReadingSurface | P05-005 |
| Cached preview widgets | ReadingCardDeck cache | Not read | retained widget instances for previews | Not included | Does not change constraints, but stale inherited MediaQuery needs widget test | UNRESOLVED | reading_card_deck.dart: cache/build logic | P05-007 |
| Current-card rebuild | settings generation/PageView | triggers only selected fields in rebuild predicate | cards rebuild as Flutter state changes | partial settings set | textAlign and resolved environment can change without cache rebuild | MISSING_FROM_IDENTITY | reader_screen.dart: readerSettingsRequireDisplayChunkRebuild, _ensureDisplayChunksBuilt | P05-002, P05-007 |
| Bookmark/progress/chapter header text | navigation/bookmark state | fixed reserves only | one-line header/footer, icon/progress paint | Not included | Fixed reserved height prevents body geometry change | TRANSIENT_CORRECTLY_EXCLUDED | reading_card.dart: _buildDepthHeader, _buildDepthFooter | P05-005 |

## 7. Identity/fingerprint/cache/checkpoint field map

The same effective setting is currently encoded several times: a display cache
string, DisplayGenerationSignature settings/viewport strings, the combined
reader layout fingerprint, canonical physical-card identity, segmented cache
records, and checkpoint matching. These have different purposes. Inclusion in
a physical-card identity is not evidence that a value itself changes layout:
publication/source/pagination compatibility must remain there even if it is
not a geometric input.

| Input/field | Source of authority | Measurement consumer | Rendering consumer | Identity/fingerprint consumer | Current equivalence | Classification | Evidence | Owning follow-up |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Book ID | route/book source | scopes source | scopes book data | whole cache key, generation, checkpoint | Compatibility scope, not layout | EXTRANEOUS_IN_IDENTITY | book_cache_service.dart: displayChunkKey; reader_screen.dart: _ensureDisplayChunksBuilt | P05-006 |
| Publication fingerprint | lazy EPUB index/source | pinned source snapshot | resolves displayed source | canonical card, checkpoint | Correct non-layout publication compatibility | EXTRANEOUS_IN_IDENTITY | lib/models/canonical_pagination.dart; lib/models/reader_checkpoint.dart | P05-006 |
| Parser/source revision/snapshot | canonical source pin | determines chunks | determines chunks | canonical source slices/continuation | Correct structural compatibility, not a setting | EXTRANEOUS_IN_IDENTITY | reader_screen.dart: _canonicalPaginationSourceRevision/_canonicalParserSourceIdentity; canonical_pagination.dart | P05-006 |
| lazyParsedSectionParserVersion | lazy parser declaration | can alter structure | can alter structure | parsed source cache/session identity; not direct display key | Structural change may reach same display layout key | MISSING_FROM_IDENTITY | lib/services/lazy_parsed_book.dart; lazy_section_repository.dart | P05-002, P05-006 |
| Parsed display cache format version | BookCacheService constant | generation signature only | none | reader fingerprint/segmented manifest | Record compatibility, not geometry | EXTRANEOUS_IN_IDENTITY | book_cache_service.dart; reader_screen.dart: _ensureDisplayChunksBuilt | P05-006 |
| displayLayoutVersion v14 | BookCacheService constant | none by itself | none by itself | cache key, layout signature, manifests | Duplicated format marker; not proof every renderer input included | EXTRANEOUS_IN_IDENTITY | book_cache_service.dart: displayLayoutVersion/displayChunkKey; segmented_display_cache_service.dart | P05-002, P05-006 |
| Pagination version nalori_cards_v16_lists | reader checkpoint constant | paginator behavior | emitted chunks | canonical identity/continuations/checkpoints | Correct algorithm compatibility, not geometry | EXTRANEOUS_IN_IDENTITY | lib/models/reader_checkpoint.dart: readerPaginationAlgorithmVersion; reader_card_paginator.dart | P05-006 |
| Canonical ordered source ranges | canonical finalized source slices | output of measurement | maps displayed cards | ReaderCardIdentity signature | Correct P04 physical-card identity | MATCHED | canonical_pagination.dart: ReaderCardIdentity/CanonicalReaderCardIdentityBuilder | P05-006 |
| Source structural/rich/list/publisher digests | canonical source slice builder | selects measure behavior | selects render behavior | physical-card source slice | Captured structural input, but not renderer algorithm/style constants | MATCHED | canonical_pagination.dart; lib/models/book_chunk.dart | P05-002 |
| Declared font family/weight/size/profile | ReadingSettings | styles/struts/budget | styles/struts | cache/settings/fingerprint | Included, with declared rather than resolved identity | MATCHED | reading_settings.dart; reader_screen.dart: _ensureDisplayChunksBuilt | P05-002 |
| Resolved font file/glyph metrics/readiness state | font loader/platform | implicit TextPainter result | implicit Text widget result | None | Critical metric identity omitted | MISSING_FROM_IDENTITY | reader_screen.dart: _loadOrRebuildDisplayChunks; reading_settings.dart: GoogleFonts calls | P05-002, P05-004 |
| Font fallback failure transition | GoogleFonts pendingFonts catch | fallback may be measured | later face may render | None | No distinct identity/rebuild is guaranteed | ASYNC_UNCONTROLLED | reader_screen.dart: _loadOrRebuildDisplayChunks | P05-004 |
| Locale language tag | Localizations | TextStyle.locale | TextStyle.locale | cache/settings/fingerprint | Included | MATCHED | reader_screen.dart: _ensureDisplayChunksBuilt | P05-002 |
| Text direction | Directionality | forced LTR | ambient direction | None | May change shaping/wrapping without identity | MISSING_FROM_IDENTITY | reader_card_paginator.dart: TextPainter construction; reading_card.dart: Text.rich | P05-002 |
| TextScaler identity | MediaQuery TextScaler | TextPainter scale curve | Text widget scale curve | scale(1) scalar only | Nonlinear or same-scale different scaler may collide | MISSING_FROM_IDENTITY | reader_screen.dart: _ensureDisplayChunksBuilt; book_cache_service.dart: displayChunkKey | P05-002 |
| Screen/safe dimensions precision | MediaQuery values | exact doubles | exact doubles | cache truncates screen to int, safe areas round, scaler to 2 decimals | Distinct effective constraints can share cache key | MISSING_FROM_IDENTITY | book_cache_service.dart: displayChunkKey; reader_screen.dart: generation signature | P05-002, P05-006 |
| Bottom-safe-area policy | _canonicalDisplaySafeArea | always 0 bottom | raw bottom | fingerprint encodes 0 | Identity matches measurement, not renderer | DIFFERENT_RESOLUTION | reader_screen.dart: _canonicalDisplaySafeArea; reading_card.dart: build | P05-002 |
| Text alignment | settings.textAlign | painter alignment | Text.rich alignment | excluded | May be harmless in LTR left/center/right but justify/RTL not proved | MISSING_FROM_IDENTITY | reading_settings.dart: resolvedTextAlign; reader_screen.dart: readerSettingsRequireDisplayChunkRebuild | P05-002 |
| Content density | settings.contentDensity | page ratio/tiny policy/margins | margins only | densityMultiplier | Multiplier maps current enum values but hides policy semantics | UNRESOLVED | reader_screen.dart: readerDensityPolicy, _ensureDisplayChunksBuilt | P05-002 |
| Renderer structural constants | heading divider/gap, table/pre widgets, list marker w600 | not all represented | directly change render tree | only broad v14 | Layout-affecting renderer code not explicit input | MISSING_FROM_IDENTITY | reading_card.dart: _buildHeadingContent/buildListContent; lib/widgets/reader_table_block.dart: ReaderTableBlockWidget/ReaderPreformattedBlockWidget | P05-002 |
| Image intrinsic/decode identity | image bytes/ImageStream | absent | Image.memory layout after decode | source content checksum only | Structural bytes exist but no resolved size/readiness identity | MISSING_FROM_IDENTITY | reading_card.dart: _buildBodyContent; lib/models/book_chunk.dart | P05-002, P05-007 |
| Segmented display cache identity | SegmentedDisplayCacheKey | cached derived cards | cached derived cards | book, scoped cacheKey, generation signature, sourceChunkCount | Duplicates incomplete display signature; section scope adds source checksums | UNRESOLVED | reader_screen.dart: _segmentedDisplayCacheKey/_segmentedDisplayCacheScope; segmented_display_cache_service.dart | P05-006 |
| Checkpoint exact match | ReaderCheckpoint fields | selects exact/semantic recovery | restoration target | publication, layout fingerprint, pagination, card signature | Correctly rejects a mismatched declared layout; inherits incomplete fingerprint | MATCHED | lib/models/reader_checkpoint.dart; lib/services/reader_checkpoint_store.dart | P05-006 |
| Display/cache generation or request token | coordinator/scheduler | cancellation/publication guard | none | diagnostics/cache scope only | Transient control correctly not physical identity | TRANSIENT_CORRECTLY_EXCLUDED | reader_screen.dart: DisplayGenerationSignature/coordinator; reader_card_paginator.dart: CanonicalPaginationOperationControls | P05-006 |

## 8. Confirmed measurement/render mismatches

| ID | Confirmed issue | Severity | Classification | Owning task | Can correction legitimately change P03 physical boundaries? | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| M-01 | Measurement removes raw bottom viewPadding, but ReadingCard includes it in P.bottom. | BLOCKER | DIFFERENT_RESOLUTION | P05-002 then P05-003/P05-005 | Yes. The future policy must be explicit and every changed boundary explained. | reader_screen.dart: _canonicalDisplaySafeArea/_rebuildDisplayChunksAsync; reading_card.dart: build |
| M-02 | Heading measurement omits the renderer’s 20px gap and decorative divider. | HIGH | RENDER_ONLY | P05-003 | Yes, if content/budget interaction changes a card. | reader_card_paginator.dart: measureTextHeight; reading_card.dart: _buildHeadingContent |
| M-03 | Body/list measurement uses plain spans; renderer applies bold, italic and reduced footnote-marker runs. | HIGH | DIFFERENT_RESOLUTION | P05-003 | Yes. | reader_card_paginator.dart: measureTextHeight; reading_card.dart: _styledTextSpan/_buildStyledTextSpan |
| M-04 | List marker width is measured with base body style but painted w600. | HIGH | DIFFERENT_RESOLUTION | P05-003 | Yes. | reader_list_layout.dart; reader_card_paginator.dart: measureTextHeight; reading_card.dart: buildListContent |
| M-05 | Table estimator and table widget use different width minima, padding and vertical box arithmetic. | HIGH | DIFFERENT_RESOLUTION | P05-003 | Yes. | reader_card_paginator.dart: tableMeasurementStyle/estimateTableHeight; lib/widgets/reader_table_block.dart: ReaderTableBlockWidget |
| M-06 | Preformatted content is measured as normal/publisher text but rendered as padded monospace horizontal-scroll content. | BLOCKER | DIFFERENT_RESOLUTION | P05-003 | Yes. | reader_card_paginator.dart: measureTextHeight; lib/widgets/reader_table_block.dart: ReaderPreformattedBlockWidget |
| M-07 | Image cards have no image-height measurement while Image.memory paints an asynchronously decoded intrinsic image plus padding. | BLOCKER | RENDER_ONLY | P05-003 | Yes. | reader_card_paginator.dart: measureTextHeight; reading_card.dart: _buildBodyContent |
| M-08 | Paginator forces LTR while renderer inherits Directionality, and direction is absent from identity. | HIGH | DIFFERENT_RESOLUTION | P05-002 then P05-003 | Yes for bidi/RTL content. | reader_card_paginator.dart: TextPainter calls; reading_card.dart: Text.rich/SelectableText |
| M-09 | Active Speed Reader collapses normal paragraph segmentation and changes span handling without re-pagination. | HIGH | RENDER_ONLY | P05-003/P05-005 | No for the intended repair: speed state is transient and rendered text must fit canonical boundaries. | reading_card.dart: _buildBodyContent/buildParagraphSeparatedBodyContent |

Confirmed count: 3 BLOCKER, 6 HIGH, 0 MEDIUM, 0 LOW. These are code-path
findings, not a new P03 oracle. M-01 through M-08 make it possible that a
proved correction changes P03 card boundaries; P05-007 must separately show
that construction-order invariants remain intact.

## 9. Missing or unresolved layout inputs

| ID | What static tracing cannot determine | Smallest focused evidence | Owner | Blocks P05-002? |
| --- | --- | --- | --- | --- |
| U-01 | Whether BoxDecoration.border consumes 1.8 logical px of the child constraint in the precise AnimatedContainer/ClipRRect tree. | One bounded ReadingCard widget probe records the descendant text LayoutBuilder size and compares it with resolveReaderLayoutMetrics. | P05-007 | No; P05-002 can require a single authority for border treatment. |
| U-02 | Whether ReadingCardDeck is always constrained exactly to MediaQuery V in every production embedding/route. | Widget probe with nontrivial parent constraints and safe area records deck/card/reader resolver sizes. | P05-007 | No. |
| U-03 | Whether publisher prose/poem preserve-break output has the same paragraph/gap behavior under TextSpanUtils versus final-layout segments. | One parser-produced publisher-layout fixture measured by paginator and rendered with exact height/overflow assertion. | P05-007 | No. |
| U-04 | Table row/column-span widget height parity, including borders and TextPainter rounding. | One decoded row/column-span table parity widget test. | P05-007 | No. |
| U-05 | Runtime resolved face, fallback order, glyph fallback and line metrics after pendingFonts success/failure. | Runtime probe records requested styles, pendingFonts outcome, TextPainter line/width metrics and a stable resolved-face signal if Flutter exposes one; otherwise records the absence. | P05-004 | No; P05-002 must model readiness/identity state without claiming a digest exists. |
| U-06 | Whether w600/w700/italic/w500/w800/monospace variants are loaded before their first rendering and whether they alter metrics later. | Variant-specific readiness-to-measure probe around every renderer-used style. | P05-004 | No. |
| U-07 | Effects of DPR, accessibility bold/high contrast, platform font fallback and non-linear TextScaler at the actual body/heading sizes. | Parameterized host widget/TextPainter probe with same scale(1) but different curve/direction/accessibility values. | P05-007 | No. |
| U-08 | Whether text alignment (especially justify and RTL) changes height or needs a reflow when settings change. | One-field mutation test for four aligns under LTR and RTL, asserting cache/signature/rebuild behavior. | P05-007 | No. |
| U-09 | Image intrinsic dimensions/frame readiness and whether an image can overflow the nonscrollable card. | ImageStream listener plus bounded card widget probe for known asset dimensions and delayed decode. | P05-007 | No. |
| U-10 | Cached preview widget inherited-environment freshness during a MediaQuery/font transition. | Deck cache test changes MediaQuery/settings and compares active/preview text constraints. | P05-007 | No. |

Unresolved-input count: 10. None is a hard blocker to TASK-P05-002, because
that task can define the field boundary and transition requirements. U-05/U-06
remain blockers to claiming resolved-font readiness is implemented or verified;
they belong to P05-004. No instrumentation is added in this task.

## 10. Non-layout inputs that must remain excluded

The following must remain excluded from pagination identity unless a future
probe proves they alter constraints or text metrics: current/preview display
index, PageController position, deck depth-lift and animation values,
gesture/tap/long-press state, selection ranges/colors/menus, link recognizers,
highlight and note colors, character-marker paint/shadows, bookmark animation
and color, chapter/progress labels, overlay visibility, speed-reader cursor/WPM
and visual mode, generation/cancellation tokens, diagnostics timestamps,
cache access time, controller attachment, and source ordinal/display-index
hints. These are interaction, paint, scheduling, or source-navigation state,
not physical-card layout authority.

Speed Reader is deliberately listed here despite M-09: its state *should* stay
excluded, but current code violates that intent by changing the render tree.
The correction should make the transient renderer fit the canonical contract,
not make every speed-reader tick a pagination identity.

## 11. Proposed ownership boundaries for P05-002 through P05-007

These are task boundaries, not implementation decisions or version choices.

| Later task | Bounded ownership from this inventory | Explicitly not decided here |
| --- | --- | --- |
| P05-002 | Specify every canonical card-body field, bottom-safe-area policy, locale/direction/scaler identity, declared versus resolved font states, structural renderer inputs, and complete compatibility field taxonomy. | Which policy/value/version is selected or how persistent formats migrate. |
| P05-003 | Make measurement and ReadingCard derive geometry, styles, spans, headings, lists, tables, preformatted content and image sizing from common pure authority; eliminate M-01 through M-09. | Cache/checkpoint format mutation or P03 oracle edits. |
| P05-004 | Establish deterministic production font readiness and modeled fallback/resolved-metric transition, including renderer-used variants. | Claiming test-font hashes prove runtime metric identity. |
| P05-005 | Prove overlays, keyboard policy, controls, deck state and interaction-only state cannot change canonical body constraints. | Changing product visual design or speed-reader product policy. |
| P05-006 | Classify exact/incompatible parser/source/layout/pagination/cache/checkpoint cases using the P05 contract. | New persistent cache records, migrations or version bumps (P06). |
| P05-007 | Add focused parity/fingerprint/probe coverage, then run required P03 matrix after approved corrections and record each legitimate range change. | Altering frozen P03/P04 expected data before evidence exists. |

## 12. Required focused tests and runtime probes

No test was run for this inventory. Later focused evidence should be minimal and
must not run the expensive P02/P03/P04 matrices until P05-007 requires it:

1. A card-body widget probe records the resolved P/M arithmetic, actual padded
   text constraints, card border behavior, raw versus canonical safe bottom,
   and deck parent constraints.
2. A measurement/render parity harness accepts one explicit layout input and
   asserts no clipping/overflow plus matching height for ordinary/split text,
   headings, publisher prose, lists, rich spans, footnotes, tables,
   preformatted text and image cards.
3. One-field identity tests mutate each canonical field and prove both
   cache/fingerprint behavior and expected reflow/non-reflow. Include
   subpixel dimensions/insets and non-linear TextScaler collisions.
4. Direction/locale/alignment cases cover LTR and RTL; accessibility/DPR cases
   document whether the platform changes metrics.
5. Font readiness probes cover normal, heading, inline bold/italic, list,
   table and monospace styles; they record requested state, ready/failure
   state, measured output, and any observable resolved identity.
6. Interaction parity verifies inactive/active selection, highlight/note,
   preview cache, overlays, controls and every Speed Reader state do not
   alter canonical text constraints.
7. After an approved layout correction only, P05-007 reruns the complete P03
   construction-order matrix and records each physical boundary change with
   its layout cause, without changing source ownership.

## 13. Open questions and blockers

- The bottom-safe-area mismatch is a BLOCKER for claiming measure/render
  parity. P05-002 must choose and specify the policy before P05-003 changes
  either path.
- Resolved runtime font/metric identity is unknown. The existing host-only
  Lexend file SHA-256 evidence proves neither device face selection nor glyph
  metrics. This keeps RISK-006 open through P05-004.
- The structural mismatches (heading decoration, rich runs, list marker,
  table, preformatted, image) are all implementation blockers for P05-003;
  they do not block authoring the contract.
- A hard runtime probe boundary is not currently missing: U-05 records that a
  resolved-face signal may be unavailable from Flutter. If it remains
  unavailable after P05-004 investigation, the contract must represent the
  observable readiness/metric evidence rather than inventing an identity.
- TASK-P05-002 has no hard external blocker. It must start from this bounded
  inventory and leave resolved-font readiness open; it must not choose
  persistent versions, migrations, or change P03/P04 identities.

## 14. Recommended bounded TASK-P05-002 scope

Define, in documentation and a proposed immutable in-memory contract shape
only, the complete authoritative input taxonomy for one physical reader card:
logical viewport/deck constraint; safe-area and keyboard policy; margin,
padding, border and reserve treatment; density/budget policy; exact typography,
strut, scaler, locale and direction; declared/readiness/resolved-font states;
all structural renderer measurements; source/parser/renderer/pagination
compatibility; and explicitly excluded transient state. Map each field to
measure, render, physical identity, cache compatibility and checkpoint
compatibility. Resolve the specification choices exposed by M-01 and M-08,
but do not refactor Dart, change version strings/records, migrate cache or
checkpoint data, or alter P03/P04 fixtures/oracles in TASK-P05-002.
