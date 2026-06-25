# Large EPUB Fix Execution

Current status: Phase 6 started. Phase 5 passed; Phase 6 gate is not yet passed.

Fixture used only as a local diagnostic input:

- Path: `/home/uttam/Desktop/Antigravity Projects/Nalori/Dialogues -- Plato.epub`
- SHA-256: `8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d`
- Repository policy: do not commit this EPUB.

## Source-Control Baseline

Initial command:

```bash
git status --short
```

Pre-existing modified files:

- `lib/screens/home_screen.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/book_cache_service.dart`
- `lib/services/epub_parser.dart`
- `lib/utils/reader_content_parser.dart`
- `lib/widgets/reader_table_block.dart`
- `test/unit/services/epub_parser_chapter_test.dart`
- `test/unit/utils/reader_content_parser_test.dart`

Pre-existing untracked path:

- `docs/diagnostics/`

These changes match the diagnostic instrumentation and artifacts described in
`docs/diagnostics/large_epub_parsing_investigation.md`. They were preserved.

## Phase 0 - Reconfirm Baseline And Map Current Display Behaviour

### Goal

Reconfirm the large EPUB baseline and map:

- `ReaderScreen._ensureDisplayChunksBuilt`
- `ReaderScreen._loadOrRebuildDisplayChunks`
- `ReaderScreen._rebuildDisplayChunks`
- `BookPreparseService`
- `BookCacheService`
- `EpubParserService`
- saved-position restoration
- settings and viewport changes
- display cache keys

### Files Modified

- `lib/screens/home_screen.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/book_cache_service.dart`
- `lib/services/book_preparse_service.dart`
- `docs/diagnostics/large_epub_fix_execution.md`

Production changes in this phase are guarded diagnostics only:

- `NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR`
- expanded display-generation signature logs
- parsed-cache hit logs under `NALORI_EPUB_DIAG`

These must be reviewed for Phase 9 cleanup.

### Commands Run

```bash
pwd
git status --short
sed -n '1,220p' /home/uttam/.codex/RTK.md
sed -n '1,220p' docs/diagnostics/large_epub_parsing_investigation.md
sed -n '1,220p' /home/uttam/.codex/skills/karpathy-guidelines/SKILL.md
rtk rg -n "_ensureDisplayChunksBuilt|_loadOrRebuildDisplayChunks|_rebuildDisplayChunks|display cache|DisplayChunk|generation|layout" lib/screens/reader_screen.dart
rtk rg -n "class BookPreparseService|ensureParsed|queueBooks|preparse|inFlight|priority|cancel" lib/services
rtk rg -n "class BookCacheService|display|cacheBook|load|save|version|signature" lib/services/book_cache_service.dart
rtk rg -n "class EpubParserService|parseFileInBackground|_parseBytes|_extractContent|BookChunk|anchor|chapter" lib/services/epub_parser.dart lib/utils/reader_content_parser.dart
rtk sha256sum 'Dialogues -- Plato.epub'
rtk flutter devices
rtk adb -s 00162352B003164 shell run-as com.nalori.reader ls -l app_flutter/books/dialogues_plato.epub
rtk timeout 180 rtk flutter run --profile -d 00162352B003164 --dart-define=NALORI_EPUB_DIAG=true --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub
rtk adb -s 00162352B003164 logcat -d -v time | grep -E 'NALORI_EPUB_DIAG|reader_display_|FATAL EXCEPTION|ANR in|OutOfMemory|lowmemorykiller|LMKD|Signal|Killing'
rtk bash -lc "rtk timeout 300 rtk flutter run --profile -d 00162352B003164 --dart-define=NALORI_EPUB_DIAG=true --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub > /tmp/nalori_phase0_profile.log 2>&1"
rtk bash -lc "grep -E 'reader_display_|parse_file_background_begin|epub_reader_read_book_end|extract_content_end|cache_book_|Lost connection|FATAL|OutOfMemory|ANR' /tmp/nalori_phase0_profile.log | tail -160"
rtk flutter analyze
rtk bash -lc "rtk timeout 420 rtk flutter run --profile -d 00162352B003164 --dart-define=NALORI_EPUB_DIAG=true --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub > /tmp/nalori_phase0_cold_display.log 2>&1"
rtk bash -lc "grep -E 'display_cache_delete_for_book|preparse_cache_hit|parse_file_background_begin|reader_display_(signature|load_begin|cache_hit|cache_miss|request_skipped|rebuild_begin|rebuild_end|load_end)|display_cache_write_end|Lost connection|FATAL|OutOfMemory|ANR' /tmp/nalori_phase0_cold_display.log"
rtk sha256sum 'Dialogues -- Plato.epub'
```

The first `adb logcat` attempt failed because the sandbox could not start the
ADB daemon. It was rerun with approval for `rtk adb`.

### Cold Display-Cache Setup

Parsed cache and display cache are stored separately:

- Parsed cache manifest: `app_flutter/book_cache/manifest.json`
- Display cache manifest: `app_flutter/book_cache/display_manifest.json`
- Parsed payload version: `4`
- Display payload version: `2`
- Display layout version: `v11`

The diagnostic cache-control hook was invoked with:

```text
NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub
```

It called `BookCacheService.deleteDisplayChunks('dialogues_plato.epub')`, which
only matches display-cache keys/files with that sanitized book prefix. It does
not touch:

- parsed EPUB/content cache
- book metadata
- reading position
- bookmarks
- highlights
- notes
- dictionary entries
- character data
- other books' caches
- user settings

Exact deleted display keys:

```text
dialogues_plato.epub_dc_v11_18.0_lexend_regular_0.75_lineHeight_1.3_paragraphSpacing_1.0_sideMargin_24.0_460x1020_0_1.00_54_0_0_0
dialogues_plato.epub_dc_v11_18.0_lexend_regular_0.75_lineHeight_1.3_paragraphSpacing_1.0_sideMargin_24.0_460x1020_0_1.00_54_24_0_0
```

Exact deleted files:

```text
/data/user/0/com.nalori.reader/app_flutter/book_cache/dialogues_plato.epub_dc_v11_18.0_lexend_regular_0.75_lineHeight_1.3_paragraphSpacing_1.0_sideMargin_24.0_460x1020_0_1.00_54_0_0_0.json.gz
/data/user/0/com.nalori.reader/app_flutter/book_cache/dialogues_plato.epub_dc_v11_18.0_lexend_regular_0.75_lineHeight_1.3_paragraphSpacing_1.0_sideMargin_24.0_460x1020_0_1.00_54_24_0_0.json.gz
```

The parsed cache for `dialogues_plato.epub` was not deleted. In the cold
display-cache run, the foreground diagnostic book still reparsed before display
layout. That indicates the existing parsed-cache freshness check did not accept
the prior parsed entry in that install/run, not that the diagnostic display-cache
clear removed parsed content. The run still isolated the confirmed display
path after parsing completed, and subsequent parsed cache writes remained
separate from display-cache writes.

### Android Profile Evidence

Device:

- `A059`
- Android 16 / API 36
- Device ID: `00162352B003164`

Current fixture verification:

```text
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d  Dialogues -- Plato.epub
```

The fixture exists in the app sandbox:

```text
app_flutter/books/dialogues_plato.epub, 2,920,023 bytes
```

Profile run 1:

- Command used `flutter run --profile` with the guarded diagnostic open hook.
- The foreground large EPUB started parsing at `2026-06-07T02:33:50.729821`.
- `EpubReader.readBook` completed in `11,894 ms` in this run.
- The run then showed unrelated background preparsing activity.
- The outer 180 second timeout ended the run with `Lost connection to device`.
- This run did not produce a clean completed display-rebuild gate.

Profile run 2:

- Output captured in `/tmp/nalori_phase0_profile.log`.
- The reader opened `dialogues_plato.epub` and logged:

```text
reader_display_load_begin ... book=dialogues_plato.epub generation=1 sourceChunks=20460
reader_display_cache_hit ... book=dialogues_plato.epub generation=1 displayChunks=8528
```

- This validates that a complete display cache currently exists and is accepted.
- It does not reproduce the cold full display rebuild because the cache hit bypasses `_rebuildDisplayChunks`.
- The same run also confirmed unrelated background preparsing while the reader was active, including another Dialogues copy:

```text
parse_file_background_begin ... book=Dialogues_--_Plato_--_2022_--_Standard_Ebooks_--_4a09cf05cc1e1ec92a2d7e0f9e3f2146_--_Anna_s_Archive.epub
epub_reader_read_book_end ... elapsedMs=2293
extract_content_end ... chunks=20460
  cache_book_write_end ... bytes=2887784
```

Profile run 3, controlled cold display-cache:

- Output captured in `/tmp/nalori_phase0_cold_display.log`.
- Display cache clear logged exact keys and files listed above.
- Fixture SHA-256 after the run remained:

```text
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
```

Display-generation signature:

```text
book=dialogues_plato.epub
parsedCacheVersion=4
displayCacheVersion=2
layoutVersion=v11
fontSize=18.0
fontFamily=lexend
fontWeight=regular
density=0.75
lineHeight=1.3
paragraphSpacing=1.0
sideMargin=24.0
screenW=460.8
screenH=1020.5866666666667
enableCardDepth=false
textScaleFactor=1.0
safeAreaTop=53.76
safeAreaBottom=0.0
safeAreaLeft=0.0
safeAreaRight=0.0
cacheKey=dialogues_plato.epub_dc_v11_18.0_lexend_regular_0.75_lineHeight_1.3_paragraphSpacing_1.0_sideMargin_24.0_460x1020_0_1.00_54_0_0_0
```

Fresh cold display-cache measurements:

| Metric | Measurement |
|---|---:|
| Source chunks | 20,460 |
| Display cache result | miss |
| Generation ID | 1 |
| Rebuild isolate | main |
| Rebuild start | 2026-06-07T02:46:41.377930 |
| Rebuild end | 2026-06-07T02:47:12.683792 |
| Full display rebuild duration | 31,305 ms |
| Display chunks produced | 8,528 |
| Display-to-original entries | 8,528 |
| Original-to-display entries | 20,460 |
| RSS at signature | 320,593,920 bytes |
| RSS at cache miss | 322,473,984 bytes |
| RSS at rebuild begin | 323,186,688 bytes |
| Highest logged RSS during rebuild | 428,019,712 bytes |
| RSS at rebuild end | 418,807,808 bytes |
| Display cache write size | 3,201,857 bytes |
| Display cache write duration | 7 ms |

Progress logs confirm a long main-isolate full-book layout pass:

```text
elapsedMs=5001 sourceIndex=2587 displayChunksSoFar=1339
elapsedMs=10002 sourceIndex=4358 displayChunksSoFar=2213
elapsedMs=15023 sourceIndex=6291 displayChunksSoFar=3181
elapsedMs=20076 sourceIndex=9277 displayChunksSoFar=4377
elapsedMs=25077 sourceIndex=15783 displayChunksSoFar=6535
elapsedMs=30336 sourceIndex=18793 displayChunksSoFar=8026
```

Comparison with the previous baseline:

| Metric | Previous baseline | Fresh Phase 0 run |
|---|---:|---:|
| Parsed source chunks | 20,460 | 20,460 |
| Display chunks | about 8,528 | 8,528 |
| First full display rebuild | about 31,719 ms | 31,305 ms |
| Main isolate | yes | yes |

This confirms the same architectural problem.

### Baseline Evidence Status

The historical cold-run evidence in
`docs/diagnostics/large_epub_parsing_investigation.md` remains the authoritative
cold baseline:

- `EpubReader.readBook`: about `3.5 s`
- Nalori content extraction: about `4.6 s`
- Main-isolate display rebuild generation 1: `31,719 ms`
- Main-isolate display rebuild generation 2: `31,069 ms`
- Peak process RSS during extraction: about `893 MB`
- Parsed source chunks: `20,460`
- Display chunks: about `8,500`

The current Phase 0 profile attempts did not invalidate that evidence, but they
also did not refresh the cold display-rebuild measurement because the app already
had a complete display cache for the diagnostic filename.

### Current Display-Generation Design

`ReaderScreen._ensureDisplayChunksBuilt` computes a display cache key from:

- book ID
- font size
- font family
- font weight
- density multiplier
- line height
- paragraph spacing
- side margin
- screen width and height
- card mode
- text scale factor
- safe-area top, bottom, left, and right
- hardcoded display layout version `v11`

It stores `_lastScreenSize`, `_lastSafeArea`, and `_lastTextScaler`, sets
`_hasCompletedDisplayChunkBuild = false`, and then either skips if
`_isRebuildingChunks` is true or starts `_loadOrRebuildDisplayChunks`.

Important correctness concern found in Phase 0:

- The method records the latest screen/safe-area/text-scaler values before the
  `_isRebuildingChunks` check.
- If a new legitimate layout signature arrives while a full rebuild is active,
  the active rebuild is not cancelled and the new signature is skipped until a
  later build invalidates state again.
- This is not a complete coordinator; it is a boolean guard plus a generation
  counter.

`ReaderScreen._loadOrRebuildDisplayChunks`:

- increments `_rebuildGeneration`
- loads a whole display-cache payload by exact key
- applies the cached complete display list if present
- otherwise calls `_rebuildDisplayChunksAsync`
- rejects a loaded cache only if the local generation became stale

`ReaderScreen._rebuildDisplayChunksAsync`:

- logs generation and source chunk count
- sets `_isRebuildingChunks = true`
- yields once
- calls `_rebuildDisplayChunks`
- restores position
- asynchronously starts a whole-book display-cache write

`ReaderScreen._rebuildDisplayChunks`:

- uses Flutter UI-bound layout APIs, especially `TextPainter` and text styles
  derived from `ReadingSettings`
- parses table blocks for measurement
- splits oversized text chunks by measured height
- merges small chunks by density policy
- first builds a center-out initial preview if `_displayChunks` is empty
- then clears the temporary preview data and performs a full source-chunk loop
  from index `0` through the entire book
- yields only after the outer loop stopwatch exceeds `16 ms`
- still performs all final layout on the main isolate
- swaps the complete final lists into `_displayChunks`, `_displayToOriginal`,
  and `_originalToDisplay`
- inserts milestone cards only in the final full-book list

### Second Rebuild Assessment

The current cache key includes viewport and safe-area dimensions, text scaling,
card mode, and all layout-affecting reader settings.

The controlled cache deletion found two existing Dialogues display signatures:

| Input | Generation/signature 1 | Generation/signature 2 |
|---|---|---|
| book | `dialogues_plato.epub` | `dialogues_plato.epub` |
| layout version | `v11` | `v11` |
| font | `18.0 lexend regular` | `18.0 lexend regular` |
| density | `0.75` | `0.75` |
| line height | `1.3` | `1.3` |
| paragraph spacing | `1.0` | `1.0` |
| side margin | `24.0` | `24.0` |
| viewport | `460x1020` | `460x1020` |
| card mode | `false` | `false` |
| text scale | `1.00` | `1.00` |
| safe-area top | `54` | `54` |
| safe-area bottom | `0` | `24` |
| safe-area left/right | `0/0` | `0/0` |

The prior second rebuild was therefore not an identical duplicate. It was caused
by a safe-area/system-inset signature change, most likely the navigation/system
UI inset becoming visible or stabilizing after the first layout. The fresh run
did not produce a second generation during the observed window.

However, Phase 0 also found that the current lifecycle can still waste work:

- An in-flight old-signature rebuild is allowed to run to completion after a
  changed signature request.
- Stale completion is checked before publish, but the old full rebuild still
  burns main-isolate time.
- Cache writes are started without awaiting or passing a generation/signature
  token into `BookCacheService.cacheDisplayChunks`; stale-generation cache-write
  prevention is therefore incomplete.

### Display-Generation Dependencies

Requires Flutter/UI isolate:

- `TextPainter`
- `TextSpan`
- `TextScaler`
- `TextDirection`
- `StrutStyle`
- `ReadingSettings.getTextStyle`
- `ReadingSettings.getHeadingStrutStyle`
- `ReadingSettings.getBodyStrutStyle`
- available width/height derived from `MediaQuery` and safe area

Pure Dart candidates:

- source-range selection
- sentence/token range discovery
- stable source anchor planning
- table block parsing and serialization
- link/style/footnote/source-range slicing
- merge/split candidate planning before exact height measurement
- cache serialization and deserialization, which already use `Isolate.run`

### Saved Position And Navigation Mapping

Saved position currently uses:

- `BookMetadata.lastReadIndex`, which is a source/original chunk index
- initial original chunk and offset passed through `BookLoadingScreen`
- `_targetOriginalIndex`
- `_targetProgressRatio`
- `_PageAnchor` based on normalized page text
- `_displayToOriginal`
- `_originalToDisplay`

Navigation features depending on absolute display indices or final display count:

- `PageView.builder.itemCount`
- current page number and scrubber labels
- manual "Go To" page number
- chapter panel page labels
- previous/next chapter lookup through `_originalToDisplay`
- bookmarks and bookmark display hints
- highlights/notes display-page targeting
- dictionary/book-memory "Go To"
- position history
- Speed Read page advance
- completion and milestone cards

Features using stable-ish source data:

- bookmarks store source chunk index and original start offset
- highlights/notes store original chunk index and offsets
- chapter entries store source chunk index
- anchor restoration compares normalized text and source candidates

### Parser And Cache Retention

`EpubParserService.parseFileInBackground`:

- reads the full EPUB bytes on the main isolate
- sends the full byte buffer to `Isolate.run`
- calls `EpubReader.readBook`
- eagerly receives a complete `EpubBook`
- traverses all decoded HTML and creates a complete `List<BookChunk>`
- returns the full parsed result to the UI side

`BookCacheService.cacheBook`:

- serializes the complete parsed book as one JSON/gzip payload in an isolate
- writes one parsed cache file

`BookCacheService.cacheDisplayChunks`:

- serializes the complete display list and mappings as one JSON/gzip payload in
  an isolate
- writes one display cache file
- updates one display manifest

The current reader therefore retains the complete parsed chunk list plus a
complete display chunk list for normal reading, and cold parsing temporarily
retains additional full-book EPUB/HTML/DOM/cache buffers.

### Content And Navigation Invariants Documented

The existing parser and reader rely on preserving:

- source chunk order
- source file and section metadata
- `ChunkSourceRange` mappings for split and merged display chunks
- links, inline styles, and footnote offsets during splits/merges
- table blocks encoded through `ReaderTableBlock`
- image chunks as non-text display chunks
- chapter chunk indices from the EPUB TOC
- original chunk indices for bookmarks, highlights, notes, dictionary entries,
  character occurrences, book memory, and saved position

Any progressive implementation must not publish display chunks without correct
`_displayToOriginal` and `_originalToDisplay` coverage for the available range.

### Phase 0 Failures And Corrections

Failure:

- Direct `adb shell ls` of the app-private fixture path returned permission
  denied.

Correction:

- Used `adb shell run-as com.nalori.reader ...`, which confirmed the fixture.

Failure:

- First profile attempt ended with `Lost connection to device` when the outer
  timeout killed `flutter run`.

Correction:

- Reran profile with output captured to `/tmp/nalori_phase0_profile.log`.

Failure:

- Second profile attempt hit an existing display cache and therefore did not
  reproduce the cold full display rebuild.

Correction:

- Recorded the cache-hit evidence and did not claim a refreshed cold baseline.

### Phase 0 Gate Result

Gate status: passed.

Evidence:

- A genuine cold display-cache rebuild was captured.
- `reader_display_cache_miss`, `reader_display_rebuild_begin`,
  `reader_display_rebuild_progress`, and `reader_display_rebuild_end` were
  captured.
- The full-book display rebuild path was freshly measured at `31,305 ms`.
- The rebuild ran on the main isolate.
- Generation signature inputs were captured.
- The previous second rebuild was narrowed to a `safeAreaBottom` signature
  change (`0` to `24`), not an identical duplicate request.
- Background preparsing/cache activity was documented during the active reader
  run.
- `rtk flutter analyze` passed after diagnostic Dart changes.

Next phase allowed to begin: yes.

## Phase 2 - In-Memory Progressive Display Ranges

### Existing Preview Path Findings

Before this change, `_rebuildDisplayChunks` used a two-step path:

- start at `_targetOriginalIndex`
- generate a center-out preview until roughly two screens of height were
  covered
- publish the preview only when `_displayChunks` was empty
- immediately clear `newDisplayChunks`, `newDisplayToOriginal`, and
  `newOriginalToDisplay`
- reset `pending` merge state
- iterate from source chunk `0` through all `widget.chunks.length`
- insert milestone cards using final display-count percentages
- replace the preview with complete `_displayChunks`, `_displayToOriginal`,
  and `_originalToDisplay`
- mark `_displayChunksComplete = true`
- write a whole-book display cache

The preview built temporary display-to-source and source-to-display mappings,
but those mappings were discarded before the final all-book pass. The final
structures replacing it were the full display chunk list, full
display-to-original list, and full original-to-display map.

Methods that assumed complete display coverage included:

- saved-position restore fallbacks through `_originalToDisplay`
- chapter previous/next navigation
- chapter panel chapter and bookmark navigation
- search result navigation
- annotation navigation
- internal link navigation
- page jump and scrubber labels
- book-completion detection at the last display page
- saved reading position forcing the last original chunk when the current page
  was the last display page
- milestone-card insertion based on final display count

Appending display chunks is safe for `PageController` because existing display
indexes remain stable. Prepending requires preserving the current source anchor
and re-resolving it after insertion; otherwise visible text can jump by the
number of inserted display pages.

The split/merge algorithm can merge small adjacent source chunks and can split
oversized paragraphs, tables, and publisher-layout chunks. Phase 2 therefore
uses canonical source-chunk range ownership and flushes pending merge state at
range boundaries. This prevents cross-range duplicate ownership. Boundary
chunks may be less merged than the old complete-book layout, but source
characters and semantic blocks remain owned by exactly one published range.

Milestone cards depend on final display percentages and are deferred while the
final display count is unknown. They are not inserted into partial ranges.

Tables, images, headings, chapter boundaries, links, footnotes, inline styles,
and annotations remain owned by their source chunks. Oversized single chunks are
still split internally by the existing semantic/text/table split rules.

### Implementation

Added `lib/services/progressive_display_state.dart` with typed state:

- `SourceChunkRange`
- `DisplayRangeRequest`
- `DisplayRangeResult`
- `PreparedDisplayRange`
- `ProgressiveDisplayState`
- `DisplayRangeDirection`
- `DisplayBoundaryState`

The state tracks:

- generation signature
- source chunk count
- prepared source/display ranges
- display chunks for prepared ranges
- display-to-source mappings
- source-to-display mappings for prepared chunks
- active foreground/lookahead request
- failed request/error
- unavailable before/after flags
- initial-window readiness
- incomplete/complete final display-count state

`ReaderScreen._rebuildDisplayChunks` now creates a bounded range generator over
the existing layout algorithm. The generator accepts a `DisplayRangeRequest` and
iterates only `request.sourceRange.start` through
`request.sourceRange.endExclusive`. Diagnostics report the inspected source
count, generated display count, and elapsed time for each range.

Initial policy after profiling:

```text
target source chunk
+ 16 source chunks look-behind
+ 79 source chunks lookahead
minimum initial source window: 96 chunks
adjacent ranges: 192 source chunks
```

The initial range is published as the real reader state. The code no longer
clears it and no longer starts the immediate full-book loop. After initial
publication, at most one bounded forward lookahead range is requested.

The Phase 1 generation token remains active in `readyPartial` state while the
display is incomplete, so stale range results are still rejected after
settings/viewport changes or reader disposal.

Complete display-cache writes are skipped while `_displayChunksComplete` is
false:

```text
reader_display_cache_write_skipped_partial reason=progressive_display_incomplete
```

### Boundary and Navigation Behaviour

Forward and backward page controls now request the next/previous bounded range
when the user reaches an unavailable prepared edge. The reader stays on the
current valid page until content arrives.

Normal page changes request bounded adjacent ranges near prepared edges.
Duplicate range requests join the active range task rather than queuing
unbounded work.

Prepending captures the visible source anchor before insertion, publishes the
new range, and re-resolves the anchor using source-range mappings. The fallback
integer shift is used only if anchor resolution fails.

Navigation by source anchor now requests a bounded target window when the
target source chunk is not prepared. This covers:

- search result navigation
- annotations panel navigation
- bookmark Go To
- chapter panel navigation
- previous/next chapter controls
- internal link/anchor navigation
- position-history Go Back fallback

Non-adjacent target navigation publishes a new prepared window around the
target rather than generating all intervening source chunks.

While the final display count is unknown:

- page labels show `N+`
- bottom progress shows `Preparing pages`
- page-jump validation is limited to currently available pages
- the final prepared page is not treated as book completion
- saved position on the last prepared page is not forced to the final source
  chunk

A localized boundary status overlay shows:

- `Preparing next pages...`
- `Preparing previous pages...`
- `Preparing destination...`
- retry UI for a failed range

The overlay is not a display page and is not persisted as reading position.

### Files Modified

- `lib/screens/reader_screen.dart`
- `lib/services/progressive_display_state.dart`
- `test/unit/services/progressive_display_state_test.dart`
- `docs/diagnostics/large_epub_fix_execution.md`

### Tests Added

`test/unit/services/progressive_display_state_test.dart` covers:

- bounded initial range around a target
- incomplete state with unknown final display count
- initial range publication and mappings
- forward append mapping shifts
- backward prepend mapping shifts
- non-adjacent append rejection
- boundary threshold decisions

Phase 1 coordinator tests were rerun to verify stale-generation behaviour still
passes.

### Commands Run

```bash
rtk dart format lib/services/progressive_display_state.dart lib/screens/reader_screen.dart test/unit/services/progressive_display_state_test.dart
rtk flutter test test/unit/services/progressive_display_state_test.dart
rtk flutter test test/unit/services/display_generation_coordinator_test.dart test/unit/services/progressive_display_state_test.dart
rtk flutter analyze
rtk flutter test
rtk flutter clean
rtk bash -lc "rtk timeout 220 rtk flutter run --profile -d 00162352B003164 --dart-define=NALORI_EPUB_DIAG=true --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub --dart-define=NALORI_DIAG_NAVIGATE_ORIGINAL_INDEX=5000 --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=20 --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=180 > /tmp/nalori_phase2_progressive_profile_auto_nav_final_clean.log 2>&1"
```

### Automated Verification

```text
rtk flutter test test/unit/services/progressive_display_state_test.dart: passed
rtk flutter test test/unit/services/display_generation_coordinator_test.dart test/unit/services/progressive_display_state_test.dart: passed
rtk flutter analyze: passed
rtk flutter test: passed, 427 tests
```

### Android Profile Evidence

Fixture:

```text
Dialogues -- Plato.epub
SHA-256: 8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
```

Artifact:

```text
/tmp/nalori_phase2_progressive_profile_auto_nav_final_clean.log
```

Final clean-build profile run:

```text
reader_display_cache_miss ... book=dialogues_plato.epub
initial_range_ready ... sourceStart=5462 sourceEndExclusive=5558 inspectedSourceChunks=96 displayChunks=36 elapsedMs=156
reader_display_rebuild_end ... elapsedMs=175 displayChunks=36 originalToDisplay=96 complete=false mode=progressive_initial_range
reader_display_cache_write_skipped_partial ... reason=progressive_display_incomplete
range_append ... sourceStart=5558 sourceEndExclusive=5750 displayChunksAdded=62
diag_auto_navigation_begin ... targetOriginalIndex=5000 backwardPages=20 forwardPages=180
boundary_wait_begin ... targetOriginalIndex=5000 sourceStart=4984 sourceEndExclusive=5080
range_generation_end ... direction=target inspectedSourceChunks=96 displayChunks=33 elapsedMs=68
range_publish ... direction=target displayChunks=33 complete=false
range_request ... direction=backward sourceStart=4792 sourceEndExclusive=4984 reason=backward_boundary
range_prepend ... displayChunksInserted=63 sourceStart=4792 sourceEndExclusive=4984
range_request ... direction=forward sourceStart=5080 sourceEndExclusive=5272 reason=forward_boundary
range_append ... displayChunksAdded=59 sourceStart=5080 sourceEndExclusive=5272
range_request ... direction=forward sourceStart=5272 sourceEndExclusive=5464 reason=forward_boundary
range_append ... displayChunksAdded=64 sourceStart=5272 sourceEndExclusive=5464
diag_auto_navigation_end ... currentPage=181 displayChunks=219 complete=false
```

Negative checks:

```text
reader_display_rebuild_progress: absent
displayChunks=8528: absent
full_generation_complete: absent
ANR/OOM/LMKD/FATAL: absent
```

`Lost connection to device` appears at the end of the log because `rtk timeout`
terminated the host `flutter run` attach process after the capture window. It
was not accompanied by app crash, ANR, OOM, or LMKD evidence.

The diagnostic open alias still performs full parsed EPUB loading in this
profile path; the display-cache clearing hook did not delete parsed content.
This is documented as diagnostic-hook behavior and remains separate from the
display pipeline. A `preparse_cache_hit` for `dialogues_plato.epub` also
appeared during the run after the parsed cache had been written.

Background preparsing of unrelated books still occurred during the foreground
reader profile run. This is the known Phase 5 workload-priority problem and was
not treated as Phase 2 completion work.

### Content and Boundary Integrity

Phase 2 range ownership is source-chunk based:

- initial range `5462..5558`
- target range `4984..5080`
- backward adjacent range `4792..4984`
- forward adjacent ranges `5080..5272` and `5272..5464`

Every published range reports `inspectedSourceChunks` equal to its requested
source range length and `originalToDisplay` coverage equal to that length for
the generated source chunks. Adjacent publish events are contiguous at source
boundaries. No overlapping range was published for append/prepend operations.

Committed unit tests verify non-adjacent append rejection and prepend/append
mapping shifts. Existing parser/content/table/link/footnote tests remained
green in the full suite.

### Temporary Instrumentation

Added diagnostic-only auto navigation defines for Android profile verification:

```text
NALORI_DIAG_NAVIGATE_ORIGINAL_INDEX
NALORI_DIAG_AUTO_BACKWARD_PAGES
NALORI_DIAG_AUTO_FORWARD_PAGES
```

They run only when `NALORI_EPUB_DIAG=true` and at least one diagnostic auto-nav
define is provided. They must be removed in Phase 9 with the other diagnostic
startup hooks.

### Phase 2 Gate Result

Gate status: passed.

Evidence:

- The initial window is the real published reader state, not a disposable
  preview.
- The old immediate full-book rebuild no longer starts.
- No complete display cache is written for partial output.
- A typed partial range model exists.
- Forward expansion appends bounded ranges.
- Backward expansion prepends bounded ranges and preserves source-anchor
  position.
- Direct navigation to a source target outside the prepared window generates
  only the target vicinity.
- Localized boundary wait diagnostics fire for unprepared target content.
- Final display count is not fabricated (`complete=false`, partial cache write
  skipped, page label uses `+` in UI).
- Phase 1 duplicate/stale generation protections still pass.
- Static analysis, targeted tests, and the full test suite pass.
- Android profile evidence shows no full 20,460-source display pass and no
  8,528-display complete rebuild during the observed run.
- First readable display after display-cache miss in the clean profile run:
  156-175 ms, versus the 31-33 second full-display baseline.

Next phase allowed to begin: yes.

## Phase 2 - Initial Reading Window

### Goal

Make the reader usable from a bounded initial display window before full-book
pagination completes, without fabricating final page count.

### Implementation So Far

Added explicit partial-display state in `ReaderScreen`:

- `_displayChunksComplete`
- `reader_display_initial_window_candidate` diagnostic
- `reader_display_initial_window_ready` diagnostic
- visible page-count labels show `N+` while pagination is incomplete
- bottom percentage label shows `Preparing pages` while pagination is incomplete

This formalizes and measures the existing center-out initial window path.

### Files Modified

- `lib/screens/reader_screen.dart`
- `docs/diagnostics/large_epub_fix_execution.md`

### Commands Run

```bash
rtk dart format lib/screens/reader_screen.dart
rtk flutter analyze
rtk flutter clean
rtk bash -lc "rtk timeout 420 rtk flutter run --profile -d 00162352B003164 --dart-define=NALORI_EPUB_DIAG=true --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub > /tmp/nalori_phase2_initial_window_profile3.log 2>&1"
```

### Profile Evidence

Artifact:

```text
/tmp/nalori_phase2_initial_window_profile3.log
```

Key lines:

```text
preparse_cache_hit ... book=dialogues_plato.epub parsedCacheVersion=4 sourceChunks=20460 anchors=4596 chapters=12
reader_display_cache_miss ... generation=1
reader_display_rebuild_begin ... generation=1 sourceChunks=20460
reader_display_initial_window_candidate ... elapsedMs=21 sourceStartIndex=5 candidateDisplayChunks=4 existingDisplayChunks=0 sourceChunksCovered=17
reader_display_initial_window_ready ... elapsedMs=21 sourceStartIndex=5 sourceChunksCovered=17 displayChunks=4 hasEarlierContent=true hasLaterContent=true
reader_display_rebuild_end ... elapsedMs=32652 displayChunks=8528 displayToOriginal=8528 originalToDisplay=20460
```

Measurements:

| Metric | Measurement |
|---|---:|
| Parsed cache | hit |
| Display cache | miss |
| Source chunks | 20,460 |
| Initial window ready after display rebuild start | 21 ms |
| Initial display chunks | 4 |
| Source chunks covered in initial mapping | 17 |
| Full display rebuild duration | 32,652 ms |
| Final display chunks | 8,528 |

This proves initial readable display can be produced promptly, but it does not
yet satisfy the full Phase 2 architecture.

### Phase 2 Gate Result

Gate status: failed/incomplete.

Reasons:

- Full-book display generation still starts immediately after the initial
  window and occupies the main isolate for about 32.7 seconds.
- There is not yet a durable partial display model with explicit available
  source/display ranges.
- Boundary navigation is not yet implemented as priority range generation.
- There is no localized unavailable-range loading state.
- Cache persistence is still whole-display-cache based.
- The implementation therefore has evidence for fast initial window generation,
  but does not yet meet the progressive range-generation requirements.

Next phase allowed to begin: no.

Temporary instrumentation to remove or harden in Phase 9:

- `NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR` in `lib/screens/home_screen.dart`
- expanded display signature logs in `lib/screens/reader_screen.dart`
- `preparse_cache_hit` diagnostic logs in `lib/services/book_preparse_service.dart`

## Phase 1 - Single-Flight Display-Generation Coordinator

### Goal

Prevent duplicate and stale display-generation work for the same book, parsed
content version, layout/settings signature, and viewport signature.

### Implementation

Added `lib/services/display_generation_coordinator.dart` with:

- explicit generation signatures
- explicit generation tokens
- lifecycle states including `loadingCache`, `complete`, `cancelled`, and `failed`
- identical request join semantics
- changed-signature replacement semantics
- stale publish/cache-write checks
- reader-dispose cancellation

Integrated the coordinator into `ReaderScreen._ensureDisplayChunksBuilt`,
`_loadOrRebuildDisplayChunks`, and `_rebuildDisplayChunksAsync`.

Cache writes now accept a `shouldWrite` callback in
`BookCacheService.cacheDisplayChunks`, rechecking the active generation token
before serialization, before writing, and after writing. If a token becomes
stale after a file write, the file is discarded before manifest publication.

### Files Modified

- `lib/services/display_generation_coordinator.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/book_cache_service.dart`
- `test/unit/services/display_generation_coordinator_test.dart`
- `docs/diagnostics/large_epub_fix_execution.md`

### Tests Added

`test/unit/services/display_generation_coordinator_test.dart` covers:

- identical concurrent requests join the active generation
- settings changes replace and cancel previous generations
- viewport/orientation changes replace previous generations
- old generations cannot publish or write cache after replacement
- active generations can write only their exact cache key
- reader close cancels active work
- completion clears active generation state

### Commands Run

```bash
rtk dart format lib/services/display_generation_coordinator.dart lib/screens/reader_screen.dart test/unit/services/display_generation_coordinator_test.dart
rtk flutter test test/unit/services/display_generation_coordinator_test.dart
rtk flutter analyze
rtk bash -lc "rtk timeout 420 rtk flutter run --profile -d 00162352B003164 --dart-define=NALORI_EPUB_DIAG=true --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub > /tmp/nalori_phase1_singleflight_profile_fixed.log 2>&1"
rtk flutter test
```

### Failures Encountered

The initial diagnostic `deleteDisplayChunks` helper scanned all files with the
book prefix and therefore also deleted `dialogues_plato.epub.json.gz`, the
parsed cache for the diagnostic copy. This did not delete book metadata,
reading position, bookmarks, highlights, notes, dictionary entries, character
data, user settings, or the EPUB file, but it violated the intended
display-cache-only behavior.

Correction:

- `deleteDisplayChunks` now derives files exclusively from keys in
  `display_manifest.json`.
- It no longer scans arbitrary files by prefix.
- A follow-up run verified that only this display file was removed:

```text
/data/user/0/com.nalori.reader/app_flutter/book_cache/dialogues_plato.epub_dc_v11_18.0_lexend_regular_0.75_lineHeight_1.3_paragraphSpacing_1.0_sideMargin_24.0_460x1020_0_1.00_54_0_0_0.json.gz
```

### Profile Evidence

Artifact:

```text
/tmp/nalori_phase1_singleflight_profile_fixed.log
```

Large EPUB run:

```text
reader_display_load_begin ... generation=1 ... cacheKey=dialogues_plato.epub_dc_v11_...
reader_display_cache_miss ... generation=1
reader_display_rebuild_begin ... generation=1 sourceChunks=20460
reader_display_rebuild_end ... generation=1 elapsedMs=30933 displayChunks=8528 displayToOriginal=8528 originalToDisplay=20460
display_cache_write_end ... bytes=3201875
reader_display_load_end ... generation=1 displayChunks=8528
```

No second `reader_display_load_begin`, `reader_display_rebuild_begin`,
`reader_display_generation_cancelled`, or stale cache-write event appeared in
the observed window. This demonstrates exactly one generation for the unchanged
signature on the large EPUB profile run.

Background preparsing still ran concurrently with foreground opening. This is
not fixed in Phase 1 and remains scheduled for Phase 5.

### Verification

```text
rtk flutter analyze: passed
rtk flutter test test/unit/services/display_generation_coordinator_test.dart: passed
rtk flutter test: passed, 421 tests
Android profile large EPUB run: passed Phase 1 single-flight evidence
```

### Phase 1 Gate Result

Gate status: passed.

Evidence:

- Exactly one display generation ran for the unchanged large EPUB signature.
- Identical requests are joined by coordinator unit tests.
- Changed settings/viewport signatures create replacement tokens in unit tests.
- Stale tokens cannot publish or write cache in unit tests.
- Reader dispose cancels active work in unit tests and integration wiring.
- Large-book profile logs show no duplicate identical generation.
- Existing automated test suite passed.

Next phase allowed to begin: yes.

## Phase 3 - Frame-Friendly Progressive Range Generation

### Goal

Preserve the Phase 2 bounded progressive range architecture while preventing
each bounded range from running as one uninterrupted main-isolate task.

Phase 3 specifically targeted the remaining UI-bound display layout work:

- `TextPainter`
- `TextSpan`
- `TextScaler`
- `StrutStyle`
- exact viewport-height measurement
- Flutter font/layout resolution

These dependencies still require main-isolate execution. The Phase 3 change
therefore makes that work cooperative and frame-budgeted rather than moving
Flutter UI-bound objects to an isolate.

### Implementation

Added `lib/services/frame_budgeted_range_scheduler.dart`.

The scheduler provides:

- explicit priority classes:
  - `directTarget`
  - `boundaryWait`
  - `initialVisible`
  - `speculativeLookahead`
- a default 8 ms frame budget
- deterministic checkpoint/yield behavior
- cancellation between slices
- higher-priority preemption of lower-priority active work
- metrics for total range time, slice count, yield count, longest work
  interval, max slice duration, source chunks per slice, display chunks per
  slice, and cancellation latency

`ReaderScreen` now uses scheduler checkpoints in bounded range generation:

- before each source chunk
- before each subchunk/layout measurement
- after each source chunk is processed
- after final pending display chunks are flushed
- before stale/cancelled results can publish

The Phase 2 range ownership and mapping model was not replaced. Prepared ranges
are still published only after a complete bounded range succeeds.

Added active range request tracking in `ReaderScreen`:

- duplicate identical range requests join existing work
- direct target navigation can preempt speculative lookahead
- stale/preempted generation IDs cannot publish
- preempted range cleanup cannot clear the preparing flag for a newer active
  range

### Files Modified

- `lib/services/frame_budgeted_range_scheduler.dart`
- `lib/services/progressive_display_state.dart`
- `lib/screens/reader_screen.dart`
- `test/unit/services/frame_budgeted_range_scheduler_test.dart`
- `docs/diagnostics/large_epub_fix_execution.md`

### Tests Added

`test/unit/services/frame_budgeted_range_scheduler_test.dart` covers:

- work split across multiple scheduler slices
- continuation resuming with deterministic output
- cancellation between slices
- higher-priority preemption
- duplicate task ID joining
- scheduler disposal cancelling active work

Existing Phase 1/2 targeted tests were rerun to verify no regression in:

- display-generation coordinator stale-token behavior
- progressive display state append/prepend/mapping behavior

### Commands Run

```bash
rtk dart format lib/services/frame_budgeted_range_scheduler.dart lib/services/progressive_display_state.dart lib/screens/reader_screen.dart test/unit/services/frame_budgeted_range_scheduler_test.dart
rtk flutter test test/unit/services/frame_budgeted_range_scheduler_test.dart
rtk flutter analyze
rtk flutter test test/unit/services/progressive_display_state_test.dart
rtk flutter test test/unit/services/display_generation_coordinator_test.dart
rtk flutter test
sha256sum 'Dialogues -- Plato.epub'
rtk adb logcat -c
rtk adb shell am force-stop com.nalori.reader
rtk bash -lc "rtk timeout 190 rtk flutter run --profile -d 00162352B003164 --dart-define=NALORI_EPUB_DIAG=true --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub --dart-define=NALORI_DIAG_NAVIGATE_ORIGINAL_INDEX=5000 --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=20 --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=180 > /tmp/nalori_phase3_profile_final.log 2>&1"
rtk adb shell dumpsys gfxinfo com.nalori.reader
rtk adb shell dumpsys meminfo com.nalori.reader
rtk flutter test
```

### Verification Results

```text
rtk flutter analyze: passed
rtk flutter test test/unit/services/frame_budgeted_range_scheduler_test.dart: passed
rtk flutter test test/unit/services/progressive_display_state_test.dart: passed
rtk flutter test test/unit/services/display_generation_coordinator_test.dart: passed
rtk flutter test: passed, 433 tests
Fixture SHA-256: 8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
Android profile run: completed under timeout wrapper; app-side log had no ANR/OOM/fatal markers
```

### Android Profile Evidence

Artifact:

```text
/tmp/nalori_phase3_profile_final.log
```

Profile run setup:

- Device: `00162352B003164`
- Build mode: Flutter profile
- EPUB: `dialogues_plato.epub`
- Fixture checksum: `8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d`
- Parsed cache: hit
- Display cache: miss

Key run evidence:

```text
preparse_cache_hit book=dialogues_plato.epub parsedCacheVersion=4 sourceChunks=20460 anchors=4596 chapters=12
reader_display_cache_miss ... generation=1 ... sourceChunks=20460
reader_display_rebuild_begin ... sourceChunks=20460
progressive_generation_begin ... rangeGeneration=2 sourceChunks=20460
```

Initial range:

```text
sourceStart=5375 sourceEndExclusive=5471
inspectedSourceChunks=96
displayChunks=35
elapsedMs=160
sliceCount=13
yieldCount=12
longestWorkIntervalMs=9
maxSliceDurationMs=9
maxSourceChunksPerSlice=14
maxDisplayChunksPerSlice=5
reader_display_rebuild_end elapsedMs=161 displayChunks=35 complete=false mode=progressive_initial_range
```

Initial bounded lookahead:

```text
sourceStart=5471 sourceEndExclusive=5663
inspectedSourceChunks=192
displayChunks=62
elapsedMs=191
sliceCount=19
yieldCount=18
longestWorkIntervalMs=11
maxSliceDurationMs=11
range_publish displayChunks=97 complete=false
```

Direct target range near source index 5000:

```text
sourceStart=4984 sourceEndExclusive=5080
inspectedSourceChunks=96
displayChunks=33
elapsedMs=90
sliceCount=10
yieldCount=9
longestWorkIntervalMs=12
maxSliceDurationMs=12
boundary_wait_end targetOriginalIndex=5000
```

Backward boundary prepend:

```text
sourceStart=4792 sourceEndExclusive=4984
inspectedSourceChunks=192
displayChunks=63
elapsedMs=121
sliceCount=13
yieldCount=12
longestWorkIntervalMs=11
maxSliceDurationMs=11
range_prepend displayChunksInserted=63
```

Forward boundary ranges:

```text
sourceStart=5080 sourceEndExclusive=5272
inspectedSourceChunks=192
displayChunks=59
elapsedMs=140
sliceCount=15
yieldCount=14
longestWorkIntervalMs=8
maxSliceDurationMs=8

sourceStart=5272 sourceEndExclusive=5464
inspectedSourceChunks=192
displayChunks=64
elapsedMs=147
sliceCount=15
yieldCount=14
longestWorkIntervalMs=8
maxSliceDurationMs=8
```

End of scripted navigation:

```text
diag_auto_navigation_end currentPage=194 displayChunks=219 complete=false
```

Negative checks:

```text
reader_display_rebuild_progress: absent
full_generation_complete: absent
displayChunks=8528: absent
ANR: absent
FATAL EXCEPTION: absent
OutOfMemory: absent
LMKD/lowmemorykiller: absent
```

The final `Lost connection to device` line was produced by the host-side
`rtk timeout` wrapper terminating the profile attach. It was not accompanied by
an app-side fatal, ANR, OOM, or LMKD marker.

### Frame And Memory Evidence

Live process sample during the final profile run:

```text
pid=24392
dumpsys meminfo TOTAL RSS: 404392 KB
dumpsys meminfo TOTAL PSS: 293579 KB
```

`dumpsys gfxinfo` was available, but the sample contained only 9 rendered
frames and mostly startup/navigation transition jank:

```text
Total frames rendered: 9
Janky frames: 8
50th percentile: 36ms
90th percentile: 97ms
Number Slow UI thread: 5
```

This gfxinfo sample is not treated as strong steady-state responsiveness
evidence because the frame sample was very small and captured startup/reader
transition work. The authoritative Phase 3 evidence for display generation is
the scheduler instrumentation showing all measured display ranges split into
9-19 slices, with max measured display-generation slices between 8 ms and
12 ms in the supplied EPUB profile scenario.

### Failures Encountered

The first integration pass allowed a preempted range's `finally` block to clear
the preparing flag for a newer active same-direction range.

Correction:

- active range cleanup now checks whether a different active range has replaced
  the finishing task
- preemption clears the old direction's preparing flag immediately
- stale/preempted range IDs remain blocked from publishing

Targeted tests and analysis were rerun after this correction, followed by a new
Android profile run and a full test-suite run.

### Background Work Observation

The final profile log still showed unrelated background preparsing while the
foreground reader was active. This was already identified in earlier phases and
is explicitly Phase 5 work. It did not reintroduce complete-book display
generation and did not invalidate the Phase 3 display-generation gate.

### Phase 3 Gate Result

Gate status: passed.

Evidence:

- No return of full-book display generation.
- Initial, target, backward, and forward ranges remained bounded.
- Display range work was split into scheduler-controlled slices.
- Longest measured display-generation work interval was 12 ms.
- No measured display-generation slice exceeded 12 ms.
- Direct target work has a higher scheduler priority than speculative
  lookahead.
- Cancellation/preemption is token-based and stale ranges cannot publish.
- Phase 1 coordinator tests still pass.
- Phase 2 progressive range-state tests still pass.
- Static analysis passed.
- Full test suite passed.
- Android profile verification passed for the supplied large EPUB.

Next phase allowed to begin: yes, Phase 4.

## Phase 4 - Persistent Partial Display Caching

### Current Status

Gate status: passed.

The segmented display-cache implementation is in place, unit-tested, analyzed,
full-suite tested, and verified on the supplied large EPUB for:

- cold segmented-cache writes
- reopen-from-partial-cache behavior
- layout-affecting signature switch
- return to original compatible signature reuse
- stable source-anchor restoration

Phase 5 is authorized.

### Current Display Cache Findings

Current display cache implementation:

- Service: `lib/services/book_cache_service.dart`
- Complete-display cache manifest: `display_manifest.json`
- Parsed-book cache manifest: `manifest.json`
- Complete-display cache format version: `BookCacheService.displayCacheFormatVersion == 2`
- Display layout version: `BookCacheService.displayLayoutVersion == 'v11'`
- Complete-display cache file: one gzip JSON file per full display cache key
- Complete-display payload:
  - `dc`: complete `displayChunks`
  - `dto`: complete display-to-original mapping
  - `otd`: complete original-to-display mapping

Parsed content and display layout cache are stored separately:

- parsed EPUB/content cache uses `manifest.json` and `<bookId>.json.gz`
- display cache uses `display_manifest.json` and `<displayKey>.json.gz`

Selective display-cache invalidation is possible without deleting parsed
content or user annotation data. `deleteDisplayChunks(bookId)` removes entries
from `display_manifest.json` and deletes only files derived from those display
manifest keys.

Legacy complete display-cache compatibility policy:

- Existing complete `v11` display caches remain readable through
  `BookCacheService.loadDisplayChunks(cacheKey)`.
- A valid complete cache is still accepted before the segmented partial cache is
  consulted.
- If no valid complete cache exists, the reader loads segmented display ranges
  or generates the missing bounded range progressively.
- The old complete cache format is not destroyed or migrated eagerly.

### Phase 4 Implementation

New service:

- `lib/services/segmented_display_cache_service.dart`

Reader integration:

- `lib/screens/reader_screen.dart`

Temporary diagnostic hook added for the remaining gate:

- `NALORI_DIAG_SWITCH_LAYOUT_SIGNATURE=true`
- Runs only with `NALORI_EPUB_DIAG` enabled.
- Uses the real `_handleSettingsUpdate` path.
- Records Layout A, switches to a different reader font size, waits for
  relayout, optionally exercises Layout B lookahead, restores Layout A, and logs
  the restored signature and source anchor.
- It does not clear Layout A's segmented cache and does not inject fake cache
  records.
- This hook is temporary instrumentation for Phase 9 cleanup.

Diagnostic display-cache clearing now removes only the diagnostic book's
complete display cache and segmented display cache:

- `lib/screens/home_screen.dart`

Segmented cache root:

```text
book_cache/display_segments/
  <safe-display-cache-key>/
    manifest.json
    manifest.json.tmp
    segment_<source-start>_<source-end-exclusive>.json.gz
    segment_<source-start>_<source-end-exclusive>.json.gz.tmp
```

Segment identity:

- Source range start.
- Source range end-exclusive.
- Full display cache key, including layout/settings/viewport signature.
- Segmented display-cache format version.
- Display layout algorithm version.
- Parsed-content version and parser version.

The segment filename does not use display-page indices. This preserves segment
identity when earlier ranges are prepended and display indices shift.

Manifest payload:

- `version`
- `bookId`
- `cacheKey`
- `parsedContentVersion`
- `parserVersion`
- `displayLayoutVersion`
- `settingsSignature`
- `viewportSignature`
- `sourceChunkCount`
- `complete`
- `createdAtMs`
- `updatedAtMs`
- lightweight `segments` metadata

Segment record payload:

- `sourceStart`
- `sourceEndExclusive`
- `actualSourceStart`
- `actualSourceEndExclusive`
- `fileName`
- `displayChunkCount`
- `displayToOriginalCount`
- `originalToDisplayCount`
- compressed payload checksum
- `generationId`
- `createdAtMs`
- `updatedAtMs`
- `status`
- `fileSizeBytes`

Segment file payload:

- the same compatibility metadata as the manifest
- display chunks for that segment only
- display-to-original mappings for that segment only
- original-to-display mappings for covered source chunks only

The manifest is intentionally lightweight and does not contain `displayChunks`.

### Atomicity And Recovery

Segment write flow:

```text
validate generation token
serialize completed immutable segment in an isolate
write segment_<range>.json.gz.tmp with flush
read and validate the temp payload
validate generation token again
rename temp segment to final segment file
upsert lightweight segment record
write manifest.json.tmp with flush
rename manifest.json.tmp to manifest.json
run bounded display-segment cleanup
```

The service checks the generation-token callback:

- before serialization
- after serialization
- before rename
- after rename and before manifest publication

If a write is stale before manifest publication, the segment is rejected and the
manifest is not updated. Startup cleanup removes abandoned `*.tmp` files. A race
found during Android profiling caused startup temp cleanup to delete an active
write temp file; `ensureInitialized()` now runs cleanup only once per service
instance, and segment writes are serialized through an internal write queue.

Corruption recovery:

- Missing segment file: remove only that segment record.
- Invalid gzip/JSON: remove only that segment record and file.
- Checksum mismatch: remove only that segment record and file.
- Metadata mismatch: remove only that segment record and file.
- Corrupt manifest: reject the segmented cache and leave segment payloads
  untouched for future recovery work.
- Duplicate or overlapping manifest records: normalize the manifest to
  non-overlapping ready records.
- Unsupported segmented format version: reject as incompatible.

Cache cleanup:

- Segment cache budget is currently 40 MiB across signatures.
- Individual segment payload cap is 3 MiB.
- Cleanup evicts least-recently-updated inactive signature directories and
  never evicts the signature currently being written.
- Parsed content, metadata, annotations, reading positions, and the EPUB file are
  not part of segmented display-cache cleanup.

### Reader Behavior

Open flow after complete display-cache miss:

```text
resolve requested source anchor
load segmented manifest for the exact layout/settings/viewport signature
load the segment containing the requested source position
load at most one adjacent segment before and one adjacent segment after
publish those segments as ProgressiveDisplayState
show the reader
generate only missing bounded ranges on demand
write newly generated ranges independently
```

Range-generation flow:

- Before generating a requested forward/backward/target range, the reader checks
  for an exact cached segment with the same source range.
- Cached exact ranges publish through the same append/prepend/target code path
  as generated ranges.
- Cached results use `elapsedMilliseconds=0` and do not rewrite the segment.
- Gaps remain explicit misses. The reader does not infer pages for unknown
  source ranges.

### Tests Added

New test file:

- `test/unit/services/segmented_display_cache_service_test.dart`

Covered cases:

- first segment write
- lightweight manifest that does not serialize display chunks
- center plus adjacent lazy segment load
- exact source-range load without adjacent decoding
- separated cached islands and source-gap miss
- stale generation denied before manifest publication
- incompatible layout signature skipped
- corrupt segment removal without deleting valid neighbors
- checksum mismatch removal without deleting valid neighbors
- corrupt manifest rejection
- old segmented cache version rejection
- duplicate and overlapping manifest-record normalization
- stale temp cleanup
- contiguous complete coverage detection

Existing Phase 1-3 service tests were rerun:

- `display_generation_coordinator_test.dart`
- `progressive_display_state_test.dart`
- `frame_budgeted_range_scheduler_test.dart`

### Commands Run

```bash
rtk dart format lib/services/segmented_display_cache_service.dart lib/screens/reader_screen.dart lib/screens/home_screen.dart test/unit/services/segmented_display_cache_service_test.dart
rtk flutter analyze
rtk flutter test test/unit/services/segmented_display_cache_service_test.dart
rtk flutter test test/unit/services/display_generation_coordinator_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/frame_budgeted_range_scheduler_test.dart test/unit/services/segmented_display_cache_service_test.dart
rtk flutter test
rtk sha256sum 'Dialogues -- Plato.epub'
rtk adb kill-server
rtk adb start-server
rtk adb devices -l
rtk flutter devices
rtk flutter emulators
```

Results:

- Static analysis: passed.
- Targeted Phase 1-4 service tests: passed, 32 tests.
- Full Flutter test suite: passed, 446 tests before the diagnostic hook and
  passed again after the diagnostic hook.
- Fixture SHA-256:
  `8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d`.

### Android Profile Evidence

Cold segmented-cache profile log:

- `/tmp/nalori_phase4_cold_segments_fixed.log`

Reopen-from-segmented-cache profile log:

- `/tmp/nalori_phase4_reopen_segments_exact_clean.log`

Cold run:

- Complete display cache and segmented display cache for
  `dialogues_plato.epub` were cleared.
- Parsed/content cache and annotations were not deleted.
- Segmented cache miss occurred for the active display signature.
- Initial generated range:
  - source range `5375..5471`
  - inspected source chunks: `96`
  - display chunks: `32`
  - generation time: `114 ms`
  - longest work interval: `8 ms`
- Reader published partial state:
  - `reader_display_rebuild_end elapsedMs=129`
  - `displayChunks=32`
  - `complete=false`
  - `mode=progressive_initial_range`
- Segment writes:
  - `5375..5471`, `11,089` bytes, `112 ms`, manifest `2 ms`
  - `5471..5663`, `21,097` bytes, `17 ms`, manifest `4 ms`
  - `4984..5080`, `11,610` bytes, `19 ms`, manifest `10 ms`
  - `4792..4984`, `20,657` bytes, `23 ms`, manifest `8 ms`
  - `5080..5272`, `20,491` bytes, `25 ms`, manifest `4 ms`
  - `5272..5464`, `21,366` bytes, `19 ms`, manifest `7 ms`
- Final observed partial state:
  - `displayChunks=219`
  - `complete=false`
- No `reader_display_rebuild_progress`.
- No `full_generation_complete`.
- No `displayChunks=8528`.
- No ANR/OOM/LMKD/fatal markers in the captured log.

Reopen run:

- Segmented manifest loaded.
- Initial segmented cache hit:
  - target source index: `5307`
  - center segment: `5272..5464`
  - loaded segments before reader ready: `3`
  - published source coverage: `5080..5656`
  - published display chunks: `185`
  - reader ready time: `83 ms`
  - `complete=false`
  - `mode=progressive_segment_cache`
- Cached forward exact-range reuse:
  - `5656..5848`
  - `rangeElapsedMs=0`
  - appended `61` display chunks
- Cached direct target exact-range reuse:
  - `4984..5080`
  - `rangeElapsedMs=0`
  - prepended `33` display chunks
- Cached backward exact-range reuse:
  - `4792..4984`
  - `rangeElapsedMs=0`
  - prepended `63` display chunks
- Final observed partial state:
  - `displayChunks=342`
  - `complete=false`
- The reader did not load the full book display cache and did not regenerate
  the valid cached ranges used in this scenario.

The profile runs ended with `Lost connection to device` because the host-side
`flutter run` session was timed out after the diagnostic scenario. The captured
reader logs before timeout contain no app fatal, ANR, OOM, LMKD, or full-book
display-generation marker.

### Phase 4 Signature-Switch Verification

The implementation produced profile-mode evidence for:

```text
change font/density/margins
confirm incompatible layout segments are skipped
return to original layout signature
confirm compatible original segments are reused
```

The invalidation behavior is covered by unit tests and by the display cache key
including font family, font size, font weight, density, line height, paragraph
spacing, side margin, card mode, viewport, safe area, and text scale.

Diagnostic profile command:

```bash
rtk timeout 260 rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub \
  --dart-define=NALORI_DIAG_NAVIGATE_ORIGINAL_INDEX=5307 \
  --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=2 \
  --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=1 \
  --dart-define=NALORI_DIAG_SWITCH_LAYOUT_SIGNATURE=true
```

Attempted log path:

- `/tmp/nalori_phase4_signature_switch.log`

First profile attempt result:

```text
No supported devices found with name or id matching '00162352B003164'.
```

Device recovery attempts:

- `rtk adb kill-server`: succeeded.
- `rtk adb start-server`: succeeded.
- `rtk adb devices -l`: no attached devices.
- `rtk flutter devices`: only Linux desktop and Chrome web were visible.
- `rtk flutter emulators`: no Android emulator sources are installed.

Because no Android device or Android emulator is currently available, the
remaining Phase 4 profile-mode signature-switch scenario cannot be executed in
this repository session.

The phone was reconnected with USB debugging enabled. The diagnostic fixture was
restored into the app sandbox at:

```text
/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub
```

On-device fixture checksum:

```text
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
```

Second profile attempt completed the signature-switch scenario.

Layout A:

- Font size: `23.1`
- Font size enum: `l`
- Font family: `lora`
- Font weight: `medium`
- Density: `0.75`
- Viewport: `460.8 x 1020.5866666666667`
- Safe area: `53.76,0.0,0.0,0.0`
- Cache key:
  `dialogues_plato.epub_dc_v11_23.1_lora_medium_0.75_lineHeight_1.3_paragraphSpacing_1.0_sideMargin_24.0_460x1020_0_1.00_54_0_0_0`
- Layout A segment directory:
  `app_flutter/book_cache/display_segments/dialogues_plato.epub_dc_v11_23.1_lora_medium_0.75_lineHeight_1.3_paragraphSpaci_03c44c81a93b5503`
- Layout A segment inventory:
  - `segment_0_96.json.gz`, `10,976` bytes
  - `segment_96_288.json.gz`, `22,286` bytes
  - `segment_5291_5387.json.gz`, `11,660` bytes
  - `manifest.json`, `1,569` bytes
- Layout A target segment checksum:
  `95ce77461492a266fc0b4eb3491ba6cf70eb044e1fb006788ae503c93d601f5c`
- Layout A source anchor before switch:
  - `sourceAnchor=5309`
  - `anchorOriginalIndex=5309`

Layout B:

- Font size: `18.900000000000002`
- Font size enum: `m`
- Same font family, font weight, density, viewport, and safe area as Layout A.
- Cache key:
  `dialogues_plato.epub_dc_v11_18.900000000000002_lora_medium_0.75_lineHeight_1.3_paragraphSpacing_1.0_sideMargin_24.0_460x1020_0_1.00_54_0_0_0`
- Layout B segment directory:
  `app_flutter/book_cache/display_segments/dialogues_plato.epub_dc_v11_18.900000000000002_lora_medium_0.75_lineHeight_1.3__0a88a51c327f27e7`
- Layout B segment inventory:
  - `segment_5293_5389.json.gz`, `11,612` bytes
  - `segment_5389_5581.json.gz`, `20,901` bytes
  - `segment_5581_5773.json.gz`, `20,892` bytes
  - `manifest.json`, `1,622` bytes
- Layout B target segment checksum:
  `d7c7179561c8c6bc554129d1665b267a1dfc8e9ccdf6ef9c4727589015fbaedd`

Switch A to B:

- `layout_signature_changed` logged old font size `23.1`, new font size
  `18.900000000000002`.
- Phase 1 coordinator logged
  `reader_display_generation_cancelled reason=signature_changed`, replacing
  generation `1` with generation `2`.
- Layout B segmented cache miss:
  `segment_cache_miss sourceIndex=5309 reason=no_manifest_or_segments`.
- Layout B initial range:
  - source range `5293..5389`
  - inspected source chunks `96`
  - display chunks `27`
  - generation time `70 ms`
  - reader ready `72 ms`
  - `complete=false`
- Layout B writes:
  - `5293..5389`, `11,612` bytes, `148 ms`, manifest `3 ms`
  - `5389..5581`, `20,901` bytes, `98 ms`, manifest `10 ms`
  - `5581..5773`, `20,892` bytes, `35 ms`, manifest `3 ms`
- Layout B source anchor after relayout: `5309`.

Switch B back to A:

- `layout_signature_changed` logged old font size `18.900000000000002`, new
  font size `23.1`.
- Phase 1 coordinator logged
  `reader_display_generation_cancelled reason=signature_changed`, replacing
  generation `2` with generation `3`.
- The restored Layout A cache key exactly matched the original Layout A key.
- Layout A target segment loaded from disk:
  - `segment_cache_range_loaded sourceStart=5291 sourceEndExclusive=5387`
  - `displayChunks=42`
  - `bytes=11660`
  - `elapsedMs=8`
- Layout A segmented cache hit:
  - `sourceIndex=5309`
  - `centerStart=5291`
  - `centerEnd=5387`
  - `loadedSegments=1`
- Layout A reader ready:
  - `reader_display_rebuild_end elapsedMs=12`
  - `displayChunks=42`
  - `complete=false`
  - `mode=progressive_segment_cache`
- Source anchor preservation:
  - original anchor `5309`
  - restored anchor `5309`
- No valid Layout A target segment regeneration occurred. The only Layout A
  generation after restore was a bounded missing lookahead range
  `5387..5579`, which was not already cached.

Negative-marker check:

- No ANR marker.
- No OOM marker.
- No LMKD/lowmemorykiller marker.
- No fatal exception marker.
- No `full_generation_complete`.
- No `displayChunks=8528`.
- No `reader_display_rebuild_progress`.

The final log contains `Lost connection to device` because the app/tool was
force-stopped after the completed diagnostic sequence. It is not treated as a
reader crash because the diagnostic end marker had already been captured:

```text
diag_auto_navigation_end generation=3 currentPage=7 displayChunks=124 complete=false
```

### Phase 4 Gate Result

Passed items:

- Partial display segments persist independently.
- Reopen can use the segment containing the saved source position.
- Valid cached initial/forward/target/backward ranges are not regenerated.
- Reader does not load all segments before becoming usable.
- Append and prepend cache reuse work in profile mode.
- Distant cached source islands are supported by exact source-range cache hits.
- Source gaps remain explicit misses.
- Temporary files are cleaned up on startup.
- Corrupt segments regenerate individually by invalidating only the bad segment.
- Stale generation writes are denied before manifest publication.
- Legacy complete cache remains readable through the existing complete-cache
  path.
- Layout/version invalidation is implemented and unit-tested.
- No full display-cache rewrite occurs for each range.
- Phase 1-3 tests continue to pass.
- Static analysis passes.
- Full test suite passes.

Final gate decision:

- Phase 4 passed.
- Next phase allowed to begin: yes, Phase 5.

## Phase 5 - Foreground/Background Workload Priority

### Goal

Prevent unrelated library-wide background preparsing from competing with the
actively opening reader and its visible progressive ranges.

Required priority order for this phase:

- current visible reader range
- adjacent range required by navigation
- initial window for a book the user is actively opening
- bounded lookahead for the active book
- remaining active-book background work
- unrelated library-wide background preparse

### Files Modified

- `lib/services/book_preparse_service.dart`
- `test/unit/services/book_preparse_service_test.dart`
- `docs/diagnostics/large_epub_fix_execution.md`

No Phase 2-4 progressive display, scheduler, or segmented-cache architecture was
rewritten.

### Implementation

`BookPreparseService` now has explicit foreground pressure:

- `beginForegroundWork(reason)`
- `endForegroundWork(reason)`
- `hasForegroundPressure`

Foreground `ensureParsed` requests:

- mark foreground pressure while checking cache or parsing;
- remove the same book from the background queue;
- join an existing in-flight parse for the same book;
- log priority and queue state under `NALORI_EPUB_DIAG`.

Background queue work:

- waits for foreground pressure to clear before starting a background
  `ensureParsed`;
- resumes queued books after foreground pressure ends;
- continues to serialize parses through the existing single `_parseTail` chain,
  so multiple background parses are not launched concurrently;
- preserves completed background work and queued tasks.

The service was made injectable for deterministic tests without touching the
global singleton behavior used by production code.

### Tests Added

`test/unit/services/book_preparse_service_test.dart` verifies:

- a queued background book does not begin parsing while foreground pressure is
  active;
- a foreground book starts before the paused background queue;
- the background queue resumes after foreground pressure ends.

### Commands Run

```bash
rtk dart format lib/services/book_preparse_service.dart test/unit/services/book_preparse_service_test.dart
rtk flutter test test/unit/services/book_preparse_service_test.dart
rtk flutter analyze
rtk flutter test
rtk timeout 180 rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub \
  --dart-define=NALORI_DIAG_NAVIGATE_ORIGINAL_INDEX=5307 \
  --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=2 \
  --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=1
rtk adb -s 00162352B003164 shell am force-stop com.nalori.reader
```

Test results:

- Targeted Phase 5 test: passed.
- Static analysis: passed.
- Full test suite: passed, `447` tests.

Android profile log:

- `/tmp/nalori_phase5_profile.log`

### Android Profile Evidence

Fixture checksum remained:

```text
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
```

Foreground reader open:

```text
preparse_foreground_begin reason=ensureParsed:dialogues_plato.epub foregroundPressure=1 queuedBooks=0 inFlight=0
preparse_background_paused reason=background_queue:dialogues_plato.epub foregroundPressure=1 queuedBooks=7 inFlight=0
preparse_cache_hit book=dialogues_plato.epub priority=foreground sourceChunks=20460
preparse_foreground_end reason=ensureParsed:dialogues_plato.epub foregroundPressure=0 queuedBooks=7 inFlight=0
preparse_background_resumed reason=background_queue:dialogues_plato.epub foregroundPressure=0 queuedBooks=7
```

Reader display used the Phase 4 segmented cache and did not rebuild the full
book:

```text
segment_cache_range_loaded sourceStart=5291 sourceEndExclusive=5387 displayChunks=42 bytes=11660 elapsedMs=4
segment_cache_hit sourceIndex=5309 loadedSegments=1
reader_display_rebuild_end elapsedMs=32 displayChunks=42 complete=false mode=progressive_segment_cache
diag_auto_navigation_end currentPage=7 displayChunks=124 complete=false
```

Unrelated background preparsing resumed only after foreground pressure cleared:

```text
preparse_parse_begin book=The_Book_of_Five_Rings... foregroundPressure=0
preparse_parse_end book=The_Book_of_Five_Rings... sourceChunks=391 foregroundPressure=0
preparse_parse_begin book=Dialogues_--_Plato_--_2022... foregroundPressure=0
preparse_parse_end book=Dialogues_--_Plato_--_2022... sourceChunks=20460 foregroundPressure=0
```

Negative-marker check found no:

- `FATAL`
- `ANR`
- `OutOfMemory`
- `LMKD` or `lowmemorykiller`
- `full_generation_complete`
- `displayChunks=8528`
- `reader_display_rebuild_progress`

The app was force-stopped after the scenario; the captured diagnostic sequence
had already completed.

### Phase 5 Gate Result

Passed items:

- No unrelated heavy book parse ran while the active foreground book open held
  foreground pressure.
- Foreground parsed-cache lookup and reader preparation completed before
  background preparsing resumed.
- Background work was paused, not discarded.
- Background queue work resumed after the active reader reached its stable
  initial segmented-cache state.
- Parse concurrency remains bounded by the existing single parse chain.
- No lost or duplicate queue tasks were observed in the automated test or
  profile log.
- Phase 1-4 behavior remained intact: no full-book display generation, no
  duplicate identical generation, bounded progressive display state, and
  segmented display-cache reuse.
- Static analysis, targeted tests, and full test suite passed.

Final gate decision:

- Phase 5 passed.
- Next phase allowed to begin: yes, Phase 6.

## Phase 6 - Lazy Section-Level EPUB Processing

### Current Status

Phase 6 has started. The lightweight EPUB index primitive is implemented and
tested, but the Phase 6 gate is not passed yet.

Outstanding Phase 6 requirements include:

- route normal reader opening through section-level parsing instead of the full
  parsed-book cache;
- parse and cache source content per section;
- migrate saved anchors/bookmarks/highlights/notes/dictionary/character
  navigation to stable section anchors where needed;
- run old full parsing versus new section parsing content-equivalence checks;
- profile the supplied large EPUB on Android and demonstrate reduced peak RSS;
- verify memory release as sections are cached or evicted.

### Inspection Findings

The vendored `packages/epubx` implementation has two relevant paths:

- `EpubReader.openBook(bytes)` decodes the ZIP archive, reads the container,
  OPF/package, manifest, spine, navigation, and builds content refs.
- `EpubReader.readBook(bytes)` calls `openBook`, then eagerly reads every HTML,
  CSS, image, font, unknown file, cover image, and chapter HTML into memory.

Current Nalori parsing still calls:

```dart
EpubReader.readBook(bytes)
```

inside `EpubParserService._parseBytes`, then extracts content from the complete
`EpubBook.Content.Html` map. This is still the full-book memory path and is not
Phase 6-complete.

The least risky path is a Nalori-specific lazy index layer around
`EpubBookRef` and content refs, rather than replacing the whole vendored EPUB
stack immediately.

### Full-Book Dependency Map

Remaining complete parsed-book dependencies found before reader routing:

- `BookLoadingScreen._loadAndParse`
  - calls `BookPreparseService.instance.ensureParsed(widget.bookFile)`;
  - waits for a complete `CachedBook`;
  - calculates `BookReadingSummary.fromParsedBook(chunks, chapters)`;
  - writes `totalChunks: parsed.chunks.length`;
  - pushes `ReaderScreen` with complete `chunks`, `anchorMap`, `chapters`, and
    `searchIndex`.
- `BookPreparseService.ensureParsed`
  - checks the one-file parsed-book cache via
    `BookCacheService.hasCachedBook(bookId, modifiedMs)`;
  - loads the full parsed cache via `BookCacheService.loadCachedBook(bookId)`;
  - otherwise calls `EpubParserService.parseFileInBackground(file)`;
  - writes the full parsed result with `BookCacheService.cacheBook`.
- `EpubParserService.parseFileInBackground`
  - reads the entire EPUB file into a byte buffer on the caller side;
  - sends the complete byte buffer to an isolate;
  - calls `EpubReader.readBook(bytes)`;
  - extracts every HTML entry into one global `List<BookChunk>`;
  - builds one global anchor map and one global chapter list.
- `BookCacheService`
  - stores one gzip JSON parsed-book payload keyed by sanitized book ID and file
    modified timestamp;
  - parsed cache format version is currently `4`;
  - display cache compatibility uses `BookCacheService.parsedBookCacheFormatVersion`
    as the parsed-content version input.
- `ReaderScreen`
  - takes `List<BookChunk> chunks` as a required constructor input;
  - initializes saved position by clamping last-read/global chunk index to
    `widget.chunks.length - 1`;
  - all progressive display ranges are source ranges over this complete list;
  - display mapping stores global original chunk indices in `_displayToOriginal`
    and `_originalToDisplay`;
  - direct jumps, chapter navigation, annotation navigation, speed read, and
    position history resolve through those global indices.
- `BookMetadata`
  - persists `lastReadIndex` and `totalChunks`;
  - reading summary is built from complete chunks and chapters.
- `Bookmark`
  - persists `chunkIndex` plus `originalStartOffset`;
  - `locationKey` is `${chunkIndex}:${originalStartOffset}`.
- `Highlight`
  - persists `originalChunkIndex`, `startOffset`, and `endOffset`;
  - notes and character introductions reuse the same model.
- `ChapterInfo`
  - persists `chunkIndex`;
  - nested chapter structure contains only global chunk-index targets, not href
    or anchor IDs.
- Book Memory and dictionary/character "Go To"
  - use bookmark/highlight/dictionary source models that ultimately navigate
    back to global chunk indices and offsets.
- Search within book
  - `searchIndex` is passed to `ReaderScreen` as a complete-book map, but eager
    search-index generation has already been disabled; current value may be
    empty.
- Scrubber/progress and page labels
  - Phase 2 already avoids a fabricated final display page count while display
    pagination is incomplete, but source progress is still derived from global
    source chunk indices.

Operations that need whole-book metadata but not whole-book content:

- title/author/cover metadata;
- manifest and spine order;
- EPUB navigation/TOC;
- section href/resource path resolution;
- approximate whole-book progress from section sizes.

Operations that need content outside currently loaded sections:

- far chapter/bookmark/highlight/note/dictionary/character target navigation;
- full-text search if reintroduced;
- exact final display page count;
- full reading summary if it depends on all text;
- final content-equivalence diagnostics.

Legacy global chunk indices remain the compatibility bridge for existing saved
positions and annotations. Phase 6 must add section/href anchors but keep a
fallback path from existing global indices to the correct section, using full
parsed-cache compatibility or a migrated section index where available.

Two EPUB spine items may map to one logical chapter when the TOC references an
anchor inside one file or omits intermediate spine entries. Conversely, a large
spine item such as `laws.xhtml` or `republic.xhtml` may contain many logical
chapters/anchors and may require internal semantic segmentation if isolated DOM
parsing still spikes memory.

### Implementation So Far

Added `lib/services/lazy_epub_index_service.dart`.

It provides:

- `LazyEpubIndexService.openBookIndex(File)`
- `LazyEpubBookHandle`
- `LazyEpubIndex`
- `LazyEpubManifestItem`
- `LazyEpubSpineItem`
- `LazyEpubChapter`
- `LazyEpubSection`
- `LazyEpubResource`

The index contains:

- book path and book ID;
- title, author, and author list;
- content directory path;
- manifest entries keyed by href;
- spine order resolved from OPF `itemref` IDs to manifest hrefs;
- NCX/navigation chapter refs without reading chapter HTML;
- cover href from OPF metadata or EPUB 3 `cover-image` properties;
- uncompressed archive entry sizes where available.

The handle supports:

- reading exactly one spine section by index;
- reading a cover or arbitrary manifest resource on demand;
- closing archive entries after use.

The local `epubx` public export was expanded to expose its ref/content metadata
types needed by Nalori without importing another package's `src/` paths:

- `EpubContentRef`
- `EpubContentFileRef`
- `EpubTextContentFileRef`
- `EpubByteContentFileRef`
- `EpubMetadataMeta`
- `Archive` as re-exported by `epubx`

Added `lib/services/lazy_parsed_book.dart`.

It defines the stable Phase 6 content model:

- `LazySectionIdentity`
- `LazyBookSectionDescriptor`
- `ParsedSection`
- `LazyParsedBook`
- `SectionParseStatus`

Added canonical `lib/models/stable_book_location.dart`.

`StableBookLocation` contains:

- schema version;
- book ID;
- spine index;
- normalized href;
- source checksum;
- optional internal segment ID;
- optional local chunk/block index;
- local text offset;
- optional EPUB anchor ID;
- surrounding text context;
- optional legacy global chunk index fallback.

This is now the canonical stable source-location model. The old
`StableContentAnchor` service-local name is retained only as a typedef to avoid
splitting the model.

Additive migration fields were added to:

- `BookMetadata.lastReadLocation`
- `Bookmark.stableLocation`
- `Highlight.stableLocation`
- `SavedWord.stableLocation`
- `PositionHistory.stableLocation`
- `ChapterInfo.stableLocation`

Legacy integer fields remain readable and are still written where existing code
has them:

- `BookMetadata.lastReadIndex`
- `Bookmark.chunkIndex`
- `Highlight.originalChunkIndex`
- `SavedWord.originalChunkIndex`
- `PositionHistory.chunkIndex/displayIndex`
- `ChapterInfo.chunkIndex`

This is intentionally additive. Existing records without stable locations still
decode. New or migrated records can dual-write a stable location without losing
legacy compatibility.

Stable section identity currently uses:

- book ID;
- spine index;
- normalized manifest href/full archive path;
- source-entry checksum from ZIP CRC32 where available, otherwise a stable
  path/size fallback;
- parser version `section_v1`;
- parsed-section cache format version `1`.

Added `lib/services/parsed_section_cache_service.dart`.

The parsed-section cache is separate from both:

- the legacy one-file full parsed-book cache;
- the Phase 4 segmented display cache.

Cache structure:

```text
book_cache/parsed_sections/<book-id>/
  manifest.json
  section_<spine-index>_<href>_<source-checksum>.json.gz
```

Manifest entries contain:

- book ID;
- spine index;
- href/full path;
- source checksum;
- parser version;
- chunk count;
- anchor count;
- word/text counts;
- resource hrefs;
- payload checksum;
- file size;
- created/updated timestamps;
- status.

Writes are atomic:

```text
serialize parsed section
→ write .tmp
→ read/validate .tmp
→ rename to final payload
→ atomically rewrite lightweight manifest
```

The cache:

- writes independent parsed sections;
- loads valid sections by exact identity;
- treats source-checksum/parser-version changes as misses;
- removes missing/corrupt payload records without deleting other sections;
- cleans stale `.tmp` files.

Added `EpubParserService.parseLazySection`.

This is a section-level parser adapter that does not call
`EpubReader.readBook`. It builds a synthetic one-section `EpubBook` and reuses
the existing `_extractContent` implementation so DOM traversal, headings, text,
tables, links, footnotes, inline styles, chunk splitting, and tiny-chunk merging
match the current full parser as closely as possible. Resource hrefs are
collected from the parsed DOM and stored with the section record.

Limitations of the current adapter:

- image bytes are not yet loaded through a lazy resource resolver during section
  parsing;
- section chapter output is empty because chapter targets still need to be
  built from the lazy EPUB navigation model;
- very large single-XHTML internal segmentation is not implemented yet.

Added `lib/services/lazy_section_repository.dart`.

It coordinates:

- lazy EPUB index opening;
- parsed-section cache cleanup;
- parsed-section cache lookup before reading XHTML;
- one-section XHTML read on cache miss;
- section parsing in a background isolate via `compute`;
- parsed-section cache write;
- bounded in-memory retention with LRU-style eviction.

Default retained section limit is `3`.

Diagnostics added:

- `lazy_epub_index_open_begin`
- `lazy_epub_index_open_end`
- `lazy_section_request`
- `lazy_section_resource_read_begin`
- `lazy_section_resource_read_end`
- `lazy_section_parse_begin`
- `lazy_section_parse_end`
- `lazy_section_parse_complete`
- `lazy_section_cache_hit`
- `lazy_section_cache_miss`
- `lazy_section_cache_write_begin`
- `lazy_section_cache_write_end`
- `lazy_section_cache_corrupt`
- `lazy_section_cache_temp_cleanup`
- `lazy_section_evict`
- `lazy_resource_load_begin`
- `lazy_resource_load_end`

### Tests Added

Added `test/unit/services/lazy_epub_index_service_test.dart` with a generated
legal EPUB fixture.

Covered behavior:

- opening a lightweight index;
- preserving spine order;
- resolving manifest metadata and uncompressed section sizes;
- reading only the requested second spine section;
- confirming the second section does not contain first-section text;
- resolving and reading the OPF cover resource;
- reading an arbitrary CSS resource on demand.

Added `test/unit/services/parsed_section_cache_service_test.dart`.

Covered behavior:

- first independent section write;
- second independent section write;
- exact cache hit;
- source-checksum change miss;
- missing payload recovery with manifest repair.

Added `test/unit/services/lazy_section_parser_equivalence_test.dart`.

Covered behavior:

- existing full parser output versus joined lazy section parser output;
- generated legal EPUB with headings, links, a footnote-like aside, and a table;
- normalized visible text equality;
- source-file ownership across joined lazy sections.

Added `test/unit/services/lazy_section_repository_test.dart`.

Covered behavior:

- requested sections parse through the repository;
- retained sections are bounded and distant sections are evicted;
- reopening can load a previously parsed section from the parsed-section cache.

Added `test/unit/models/stable_book_location_test.dart`.

Covered behavior:

- stable location JSON round trip and equality;
- legacy bookmark JSON remains readable;
- bookmark migration can add a stable location while retaining legacy fields;
- highlight, saved word, and position history preserve legacy fields and stable
  locations;
- book metadata stores stable last-read location without dropping
  `lastReadIndex`.

### Commands Run

```bash
rtk dart format packages/epubx/lib/epubx.dart lib/services/lazy_epub_index_service.dart test/unit/services/lazy_epub_index_service_test.dart
rtk flutter test test/unit/services/lazy_epub_index_service_test.dart
rtk flutter test test/unit/services/parsed_section_cache_service_test.dart
rtk flutter test test/unit/services/lazy_section_parser_equivalence_test.dart
rtk flutter test test/unit/services/lazy_section_repository_test.dart
rtk flutter test test/unit/models/stable_book_location_test.dart
rtk flutter test test/unit/services/lazy_epub_index_service_test.dart test/unit/services/parsed_section_cache_service_test.dart test/unit/services/lazy_section_parser_equivalence_test.dart test/unit/services/lazy_section_repository_test.dart
rtk flutter analyze
rtk flutter test
```

Results:

- Lazy-index targeted test: passed, `2` tests.
- Parsed-section cache targeted test: passed, `3` tests.
- Lazy parser equivalence targeted test: passed, `1` test.
- Lazy section repository targeted test: passed, `2` tests.
- Stable location migration targeted test: passed, `4` tests.
- Combined Phase 6 targeted tests: passed, `8` tests.
- Static analysis: passed.
- Full test suite: passed, `455` tests after the Phase 6 additions.

### Failures And Corrections

Failure:

- The synthetic EPUB fixture used `ArchiveFile.noCompress` with a plain
  `List<int>` for the cover image. Archive `3.6.1` expects a `Uint8List` or
  stream for that constructor.

Correction:

- Switched the fixture cover entry to `ArchiveFile(...)`.

Failure:

- Static analysis flagged dynamic calls in the new lazy service.

Correction:

- Exported the needed `epubx` ref types and used typed
  `EpubContentFileRef`/`EpubTextContentFileRef`/`Archive` paths.

Failure:

- Static analysis flagged a direct production import of transitive package
  `archive`.

Correction:

- Re-exported `Archive` through the local `epubx` package and removed the direct
  Nalori import.

Failure:

- The first parsed-section cache test used a plain `List<int>` where the shared
  checksum helper expects a `Uint8List`.

Correction:

- Converted test text bytes through `Uint8List.fromList`.

Failure:

- The repository test assumed a parsed section had one chunk. The existing
  parser correctly emits a heading chunk plus a paragraph chunk.

Correction:

- Changed the assertion to compare visible text across all chunks in the
  section.

Failure:

- The first repository implementation read XHTML before checking the cache in
  order to compute a source checksum.

Correction:

- Added source-entry checksums to the lightweight index from ZIP CRC32 where
  available, allowing parsed-section cache lookup before XHTML resource read.

### Phase 6 Gate Result

Gate status: not passed.

Reason:

- The reader still uses the existing complete parsed-book cache and
  `EpubReader.readBook` path for normal progressive reading.
- The section-level parsed cache exists, but `BookLoadingScreen` and
  `ReaderScreen` are not routed through it.
- Stable section-anchor migration is defined at the model level but not wired
  into persisted bookmarks, highlights, notes, dictionary entries, character
  introductions, or saved reading positions.
- Global `ChapterInfo.chunkIndex` targets still need href/anchor-based lazy
  navigation.
- Lazy image/resource loading is indexed but not yet integrated into section
  parsing/rendering.
- Very large single-XHTML internal segmentation is not implemented.
- Android memory profiling has not been rerun for a production lazy reader
  opening path.
- Full private-EPUB content equivalence has not been captured.

Next work remains in Phase 6.

## Phase 6 Continued - Production Lazy Reader Routing

### Scope Completed In This Iteration

Implemented the first production reader-contract migration slice:

- `BookLoadingScreen` now opens `LazyBookSession` directly for EPUBs.
- The normal diagnostic open path no longer calls
  `BookPreparseService.ensureParsed` before reader readiness.
- `ReaderScreen` accepts a lazy session and a loaded content window instead of
  assuming the supplied chunks are the complete book.
- New persisted reader data writes stable locations where the current loaded
  source window can provide them.
- Chapter panel navigation can route through `ChapterInfo.stableLocation`.
- Lazy forward boundary navigation loads the next spine section before display
  range generation when the current prepared window reaches an unloaded-section
  sentinel.
- Background preparse now supports active-book suppression so the foreground
  EPUB cannot be parsed as an unrelated background queue item during lazy open.
- Progressive display state now records external unavailable content before and
  after the loaded lazy window, so a fully covered local section window is not
  incorrectly marked as complete.

### Files Modified

Production:

- `lib/models/stable_book_location.dart`
- `lib/models/book_metadata.dart`
- `lib/models/bookmark.dart`
- `lib/models/highlight.dart`
- `lib/models/position_history.dart`
- `lib/models/saved_word.dart`
- `lib/screens/book_loading_screen.dart`
- `lib/screens/book_list_screen.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/book_preparse_service.dart`
- `lib/services/bookmark_service.dart`
- `lib/services/dictionary_service.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/parsed_section_cache_service.dart`
- `lib/services/progressive_display_state.dart`
- `lib/widgets/chapter_panel.dart`

Tests:

- `test/unit/models/stable_book_location_test.dart`
- `test/unit/services/book_preparse_service_test.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/services/progressive_display_state_test.dart`

### Stable Location Schema

`StableBookLocation` records:

- `bookId`
- `spineIndex`
- normalized section `href`
- section `sourceChecksum`
- optional internal segment id
- local chunk/block index
- local text offset
- EPUB anchor id
- surrounding normalized text context
- optional legacy global chunk index fallback

Existing records remain readable because the new location is optional. New
reader writes add stable locations when the currently loaded source window can
resolve one, while preserving legacy integer indices during the transition.

### Lazy Session Contract

`LazyBookSession` owns:

- lazy EPUB index handle
- `LazySectionRepository`
- parsed-section cache access
- loaded section map
- loaded-window reindexing
- stable-location maps for ephemeral loaded-window chunk indices
- chapter target resolution through href/fragment metadata
- section retention/eviction through the repository

The loaded window exposes only parsed sections currently needed by the reader.
Unloaded sections are not represented as fake chunks.

### Android Profile Evidence

All profile runs used:

```bash
rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_CLEAR_PARSED_CACHE_FOR=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub \
  --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=18
```

Device:

- `A059`
- Android 16 / API 36
- Device ID: `00162352B003164`

Fixture checksum before and after:

```text
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
```

#### Failed Profile Attempts

Profiles captured in:

- `/tmp/nalori_phase6_lazy_profile_4.log`
- `/tmp/nalori_phase6_lazy_profile_5.log`

Failures found:

- active foreground book still ran `EpubReader.readBook`;
- complete parsed cache was written for `dialogues_plato.epub`;
- initial loaded local window reported `complete=true`;
- lazy external content before/after was not represented in the display state.

Corrections:

- added `BookPreparseService.suppressBackgroundBook`;
- suppressed/resumed the active book around lazy reader open;
- added regression test for active-book background suppression;
- added external unavailable before/after flags to `ProgressiveDisplayState`;
- added regression test proving a locally covered lazy window remains
  incomplete when external sections exist.

The profile build initially reused stale Dart artifacts. `rtk flutter clean`
was run before the next authoritative profile.

#### Passing Production Lazy-Open Evidence

Clean profile captured in:

- `/tmp/nalori_phase6_lazy_profile_6.log`

Evidence:

- `preparse_foreground_begin reason=lazyOpen:dialogues_plato.epub`
- `preparse_background_suppressed_book book=dialogues_plato.epub`
- `lazy_reader_index_ready sectionsIndexed=36 elapsedMs=214`
- parsed before reader ready:
  - spine `1`, `text/imprint.xhtml`, `7` chunks
  - spine `2`, `text/dedication.xhtml`, `1` chunk
- `lazy_reader_section_ready sectionsParsedBeforeReady=2 chunks=8 elapsedMs=345`
- initial display:
  - `sourceStart=0`
  - `sourceEndExclusive=8`
  - `inspectedSourceChunks=8`
  - `displayChunks=4`
  - `elapsedMs=14`
  - `maxSliceDurationMs=8`
  - `hasEarlierContent=true`
  - `hasLaterContent=true`
  - `complete=false`
- active book forbidden full-parse check:
  - no `epub_reader_read_book_start` for `dialogues_plato.epub`
  - no `cache_book_write_start` for `dialogues_plato.epub`
- peak RSS observed in this run: `297,963,520` bytes.

This is below the Phase 6 preferred peak target of approximately `536 MB` for
the initial cold lazy-open scenario, and far below the prior approximately
`893 MB` complete extraction baseline. It is not yet sufficient for the full
Phase 6 memory gate because large-section jumps and repeated distant navigation
have not been measured.

#### Passing Lazy Forward Boundary Evidence

Profile captured in:

- `/tmp/nalori_phase6_lazy_profile_7.log`

This run verified that the reader no longer generates repeated synthetic
sentinel ranges at the prepared edge. Instead it loads the next section and then
generates a real bounded display range.

Evidence:

- initial lazy open:
  - `sectionsIndexed=36`
  - `sectionsParsedBeforeReady=2`
  - `chunks=8`
  - `elapsedMs=426`
- initial display:
  - `sourceStart=0`
  - `sourceEndExclusive=8`
  - `inspectedSourceChunks=8`
  - `displayChunks=4`
  - `elapsedMs=26`
  - `maxSliceDurationMs=11`
  - `hasEarlierContent=true`
  - `hasLaterContent=true`
  - `complete=false`
- first forward lazy section:
  - requested spine `3`, `text/preface-1.xhtml`
  - parsed `29` chunks
  - appended source range `8..37`
  - generated display range `8..37`
  - inspected `29` source chunks
  - produced `13` display chunks
  - elapsed `66 ms`
  - max slice `11 ms`
- second forward lazy section:
  - requested spine `4`, `text/preface-2.xhtml`
  - parsed `184` chunks
  - appended source range `37..221`
  - generated display range `37..221`
  - inspected `184` source chunks
  - produced `81` display chunks
  - elapsed `133 ms`
  - max slice `11 ms`
- repository retention:
  - `lazy_section_evict spineIndex=1 retained=3`
- active book forbidden full-parse check:
  - no `epub_reader_read_book_start` for `dialogues_plato.epub`
  - no `cache_book_write_start` for `dialogues_plato.epub`
- peak RSS observed in this run: `305,274,880` bytes.

The `Lost connection to device` line is from the outer `rtk timeout` ending
`flutter run`; no `FATAL`, `ANR`, `OutOfMemory`, `LMKD`, or low-memory-killer
marker appeared in the captured log.

### Verification Commands

```bash
rtk dart format \
  lib/services/book_preparse_service.dart \
  lib/screens/book_loading_screen.dart \
  lib/services/progressive_display_state.dart \
  lib/screens/reader_screen.dart \
  test/unit/services/book_preparse_service_test.dart \
  test/unit/services/progressive_display_state_test.dart

rtk flutter analyze

rtk flutter test \
  test/unit/services/book_preparse_service_test.dart \
  test/unit/services/progressive_display_state_test.dart \
  test/unit/services/lazy_book_session_test.dart

rtk flutter test

sha256sum 'Dialogues -- Plato.epub'
```

Results:

- Static analysis: passed.
- Targeted tests: passed, `11` tests.
- Full test suite: passed, `463` tests.
- Fixture SHA-256 remained unchanged.

### Phase 6 Gate Result

Gate status: not passed.

Completed and verified:

- production EPUB reader now opens the diagnostic book through the lazy session;
- initial opening does not call `EpubReader.readBook`;
- no complete parsed `List<BookChunk>` is required before reader readiness;
- no complete parsed-cache write occurs for the active diagnostic book;
- only bounded initial sections parse before reader readiness;
- forward lazy section expansion works from the prepared boundary;
- parsed-section cache writes independent section payloads;
- section repository evicts distant sections;
- initial lazy-open memory is substantially lower than the previous full-book
  extraction baseline.

Remaining Phase 6 requirements before passing:

- backward section loading from an unloaded previous section;
- far chapter jumps to unloaded sections, including `republic.xhtml` and
  `laws.xhtml`;
- saved-position restore evidence after restart through parsed-section and
  display-segment cache hits;
- bookmark, highlight, note, dictionary and character "Go To" through stable
  lazy locations when target sections are unloaded;
- internal link, footnote and backlink lazy resolution;
- whole-book scrubber coordinate and unloaded target loading;
- Speed Read crossing unloaded section boundaries;
- lazy resource rendering/eviction evidence for images and referenced assets;
- isolated large-XHTML measurements for `republic.xhtml` and `laws.xhtml`;
- private EPUB full-vs-lazy joined content-equivalence diagnostic;
- Android memory run covering distant jumps and eviction after large sections.

Next work remains in Phase 6. Do not advance to Phase 7.

### Large Section Jump Evidence

Added temporary diagnostic navigation:

```text
NALORI_DIAG_NAVIGATE_SPINE_INDEX=<spine-index>
```

This hook is guarded by `NALORI_EPUB_DIAG` and uses the real lazy-session stable
location path:

```text
StableBookLocation(bookId, spineIndex, href, sourceChecksum)
→ LazyBookSession.loadAround
→ ReaderScreen source-window replacement
→ progressive initial display range
```

It does not inject fake cache records and must be removed or reviewed in
Phase 9.

Spine indices from the supplied EPUB:

- `republic.xhtml`: spine `22`
- `laws.xhtml`: spine `30`

#### republic.xhtml

Profile log:

- `/tmp/nalori_phase6_republic_jump.log`

Evidence:

- diagnostic target: `spineIndex=22 href=text/republic.xhtml`
- direct lazy target request: `lazy_reader_section_requested direction=target spineIndex=22`
- target section read:
  - `htmlChars=1,316,166`
  - resource read elapsed `51 ms`
- target section parse:
  - `chunks=5,403`
  - `anchors=1,284`
  - `wordCount=217,515`
  - `textCharCount=1,185,051`
  - `resources=372`
  - parse elapsed `328 ms`
- parsed-section cache payload:
  - `section_22_text_republic.xhtml_83260d4f.json.gz`
  - `464,724` bytes
- bounded neighbor:
  - spine `23`, `text/timaeus.xhtml`
  - `1,635` chunks
  - parse elapsed `112 ms`
- post-jump display:
  - initial source range `0..96` within the loaded target window
  - inspected `96` source chunks
  - produced `45` display chunks
  - elapsed `52 ms`
  - max slice `8 ms`
  - `complete=false`
- peak RSS observed: `341,315,584` bytes.
- active-book forbidden full-parse check:
  - no `epub_reader_read_book_start` for `dialogues_plato.epub`
  - no `cache_book_write_start` for `dialogues_plato.epub`

#### laws.xhtml

Initial laws profile:

- `/tmp/nalori_phase6_laws_jump.log`

Failure found:

- target section navigation worked, but automatic post-target lookahead generated
  `sourceStart=96 sourceEndExclusive=288` inside the large `laws.xhtml` window.
- That speculative range produced a `520-522 ms` main-isolate slice.
- This violates the Phase 3/6 responsiveness invariant even though it was
  bounded and not a full-book rebuild.

Correction:

- Lazy-session readers now skip automatic initial lookahead after publishing a
  valid initial range.
- Boundary-demand generation still works, but speculative post-jump work does
  not run immediately inside huge sections.

Corrected laws profile:

- `/tmp/nalori_phase6_laws_jump_3.log`

Evidence:

- diagnostic target: `spineIndex=30 href=text/laws.xhtml`
- direct lazy target request: `lazy_reader_section_requested direction=target spineIndex=30`
- target section read:
  - `htmlChars=1,715,952`
  - resource read elapsed `59 ms`
- target section parse:
  - `chunks=2,477`
  - `anchors=78`
  - `wordCount=101,912`
  - `textCharCount=1,626,135`
  - `resources=604`
  - parse elapsed `377 ms`
- parsed-section cache payload:
  - `section_30_text_laws.xhtml_56d84896.json.gz`
  - size previously measured as `578,984` bytes
- bounded neighbor:
  - spine `31`, `text/appendix.xhtml`
  - `349` chunks
  - parse completed before target display publication
- post-jump display:
  - initial source range `0..96` within the loaded target window
  - inspected `96` source chunks
  - produced `43` display chunks
  - elapsed `63 ms`
  - max slice `8 ms`
  - `complete=false`
- lazy speculative lookahead was skipped:

```text
range_request_skipped_lazy_initial_lookahead ... sourceStart=96 sourceEndExclusive=288 reason=lazy_initial_window_ready
```

- peak RSS observed: `349,175,808` bytes.
- active-book forbidden full-parse check:
  - no `epub_reader_read_book_start` for `dialogues_plato.epub`
  - no `cache_book_write_start` for `dialogues_plato.epub`
- no `FATAL`, `ANR`, `OutOfMemory`, `LMKD`, or low-memory-killer marker appeared
  in the captured log. `Lost connection to device` was caused by the outer
  diagnostic timeout ending `flutter run`.

Interpretation:

- Large individual XHTML sections are currently parseable in isolation under
  the Phase 6 memory target.
- Internal semantic segmentation is not yet required by measured memory for
  these two sections, but it remains a possible future optimization if
  responsiveness or memory regresses on other devices.
- The parsed target section itself can be large (`republic.xhtml` produced
  `5,403` chunks), so retention and eviction evidence remains required before
  the final Phase 6 gate can pass.

Post-correction verification:

```bash
rtk flutter analyze
rtk flutter test test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart
rtk flutter test
sha256sum 'Dialogues -- Plato.epub'
```

Results:

- Static analysis: passed.
- Targeted tests: passed.
- Full test suite: passed, `463` tests.
- Fixture SHA-256 remained
  `8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d`.

### Phase 6 stabilization correction: rollout safety and reader usability

Manual testing after the initial lazy-reader routing found production reader
regressions: new books could start in front matter, previously parsed books
could enter the incomplete lazy route, chapter state was derived from the
loaded source window, next/previous chapter controls could disappear for
unloaded targets, backward unloaded-section navigation was missing, and the
scrubber represented only loaded display pages.

This correction does **not** mark Phase 6 complete. It makes the production
reader safe while the remaining lazy-reader parity work continues.

#### Files modified

- `lib/screens/book_loading_screen.dart`
- `lib/screens/book_list_screen.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/lazy_reader_route_service.dart`
- `lib/widgets/chapter_panel.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/services/lazy_reader_route_service_test.dart`

#### Rollout safety

Added:

- global lazy-reader kill switch:
  - `--dart-define=NALORI_ENABLE_LAZY_READER=true`
  - default is disabled.
- optional diagnostic allow-list:
  - `--dart-define=NALORI_LAZY_READER_ONLY_BOOK=<book-id>`
- per-book lazy disable marker:
  - SharedPreferences key `lazy_reader_disabled_books_v1`
  - implemented by `LazyReaderRouteService`
- explicit route diagnostics:
  - `reader_open_route route=legacy|lazy reason=...`

Rules:

- Normal EPUB opening uses the legacy source-content route unless lazy is
  explicitly enabled.
- A book marked disabled for lazy uses the legacy route even when the global
  flag is enabled.
- An existing book with `lastReadIndex > 0` but no persisted
  `StableBookLocation` uses the legacy route with reason
  `legacy_saved_position_requires_migration`.
- No lazy cache, legacy cache, EPUB file, bookmark, highlight, note,
  dictionary entry, character record, or reading position is deleted when
  switching routes.
- The legacy route still uses the Phase 1-5 progressive display pipeline where
  compatible; it does not restore the old full-book display wait.

Android profile safety run:

- log: `/tmp/nalori_phase6_safety_legacy_route.log`
- command used lazy disabled by default:

```bash
rtk timeout 95 rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub
```

Evidence:

```text
reader_open_route ... book=dialogues_plato.epub route=legacy reason=lazy_reader_disabled_or_not_allowed diagnosticBookOpen=true lazyDisabledForBook=false
preparse_cache_hit ... sourceChunks=20460 anchors=4596 chapters=12
legacy_reader_ready ... sourceChunks=20460 chapters=12 elapsedMs=330
initial_range_ready ... displayChunks=159 complete=false
reader_display_cache_write_skipped_partial ... reason=progressive_display_incomplete
```

No `lazy_reader_open_begin` was emitted in this run. No `FATAL`, `ANR`, `OOM`,
or `LMKD` marker was found; `Lost connection to device` was the expected outer
`timeout` ending `flutter run`.

#### Lazy reader usability repairs

Implemented:

- `LazyBookSession.initialLocation()` now chooses a meaningful first reading
  target for new books:
  1. Chapter-1-like TOC entry.
  2. First non-front-matter TOC entry.
  3. First linear spine item whose href is not obvious front matter.
  4. First spine item fallback.
- Unloaded lazy chapters now retain distinct synthetic `chunkIndex` values and
  stable locations instead of all collapsing to `chunkIndex=0`.
- Lazy chapter rail previous/next controls now use TOC stable-location order,
  not loaded-window chunk mappings.
- Lazy chapter panel current/completed/unread state can use the current
  `StableBookLocation`.
- Lazy chapter navigation uses `ChapterInfo.stableLocation` and can target
  unloaded sections.
- Added inverse unloaded-section loading:
  - reaching the beginning of the loaded window requests the previous spine
    section;
  - the section is prepended to the source window;
  - the visible stable location is preserved by resolving it after prepend;
  - display generation is restarted around the preserved location.
- Lazy-mode bottom scrubber is no longer display-page-based. It is now a
  structural spine/TOC scrubber that spans the whole EPUB and navigates to the
  selected section through stable locations.

Targeted tests added:

- `new lazy book starts at first meaningful reading chapter`
- `unloaded chapter targets retain distinct stable order`
- per-book lazy disable marker round trip.

Verification after the repair:

```bash
rtk dart format lib/services/lazy_book_session.dart lib/screens/reader_screen.dart lib/widgets/chapter_panel.dart lib/screens/book_list_screen.dart lib/screens/book_loading_screen.dart lib/services/lazy_reader_route_service.dart test/unit/services/lazy_reader_route_service_test.dart
rtk flutter analyze
rtk flutter test test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_reader_route_service_test.dart test/unit/models/stable_book_location_test.dart
rtk flutter test
```

Results:

- Static analysis: passed.
- Targeted tests: passed, `9` tests in the invoked files.
- Full test suite: passed, `466` tests.

Lazy-enabled Android profile run:

- log: `/tmp/nalori_phase6_lazy_stabilization.log`
- command enabled lazy only for the diagnostic book and exercised a far
  `republic.xhtml` target plus backward/forward page movement:

```bash
rtk timeout 130 rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_ENABLE_LAZY_READER=true \
  --dart-define=NALORI_LAZY_READER_ONLY_BOOK=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub \
  --dart-define=NALORI_DIAG_NAVIGATE_SPINE_INDEX=22 \
  --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=12 \
  --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=8
```

Evidence:

```text
reader_open_route ... route=lazy reason=lazy_reader_enabled
lazy_reader_index_ready ... sectionsIndexed=36 elapsedMs=163
lazy_reader_target_resolved ... spineIndex=30 href=text/laws.xhtml
lazy_reader_section_ready ... sectionsParsedBeforeReady=2 chunks=2826 elapsedMs=661
initial_range_ready ... sourceStart=0 sourceEndExclusive=96 displayChunks=54 longestWorkIntervalMs=11 complete=false
diag_auto_navigation_stable_target ... spineIndex=22 href=text/republic.xhtml
lazy_reader_section_requested ... direction=target spineIndex=22 href=text/republic.xhtml
lazy_reader_target_resolved ... spineIndex=22 href=text/republic.xhtml loadedChunks=7038
lazy_reader_section_requested ... direction=backward spineIndex=21 href=text/gorgias.xhtml
lazy_reader_section_ready ... direction=backward spineIndex=21 chunks=616
lazy_reader_section_requested ... direction=backward spineIndex=20 href=text/phaedo.xhtml
lazy_reader_section_ready ... direction=backward spineIndex=20 chunks=1020
range_prepend ... direction=backward sourceStart=167 sourceEndExclusive=359
range_prepend ... direction=backward sourceStart=0 sourceEndExclusive=167
diag_auto_navigation_end ... currentPage=98 displayChunks=278 complete=false
```

No `FATAL`, `ANR`, `OOM`, or `LMKD` marker appeared in the extracted log.

Issue still observed:

- One bounded range after a large prepend recorded `longestWorkIntervalMs=567`.
  That is localized and not a full-book rebuild, but it violates the desired
  responsiveness threshold and must be corrected before the final Phase 6 gate.

Correction attempted:

- Lazy-session initial and source-target display windows were reduced from the
  default `96` source chunks to `48` source chunks:
  - lazy look-behind: `8`
  - lazy look-ahead: `39`
  - lazy minimum window: `48`
- Legacy/non-lazy progressive display windows remain unchanged.

Verification:

```bash
rtk dart format lib/screens/reader_screen.dart
rtk flutter analyze
rtk flutter test test/unit/services/progressive_display_state_test.dart test/unit/services/frame_budgeted_range_scheduler_test.dart test/unit/services/lazy_book_session_test.dart
rtk flutter clean
rtk timeout 150 rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_ENABLE_LAZY_READER=true \
  --dart-define=NALORI_LAZY_READER_ONLY_BOOK=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub \
  --dart-define=NALORI_DIAG_NAVIGATE_SPINE_INDEX=22 \
  --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=12 \
  --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=8
```

Results:

- Static analysis: passed.
- Targeted range/scheduler/session tests: passed, `17` tests.
- Clean profile log:
  `/tmp/nalori_phase6_lazy_stabilization_clean_small_window.log`
- Clean profile evidence:

```text
reader_open_route ... route=lazy reason=lazy_reader_enabled lastReadIndex=56 hasStableLastReadLocation=true
lazy_reader_section_ready ... sectionsParsedBeforeReady=2 chunks=440 elapsedMs=257
initial_range_ready ... sourceStart=48 sourceEndExclusive=96 inspectedSourceChunks=48 displayChunks=92 longestWorkIntervalMs=149
diag target republic.xhtml ... initial_range_ready sourceStart=0 sourceEndExclusive=48 inspectedSourceChunks=48 displayChunks=30 longestWorkIntervalMs=8
backward section phaedo.xhtml ... initial_range_ready sourceStart=1012 sourceEndExclusive=1060 inspectedSourceChunks=48 displayChunks=26 longestWorkIntervalMs=8
backward range_publish ... sourceStart=1503 sourceEndExclusive=1695 rangeElapsedMs=210 longestWorkIntervalMs=111 complete=false
diag_auto_navigation_end ... currentPage=129 displayChunks=150 complete=false
```

Interpretation:

- The smaller lazy initial window is active after a clean rebuild and removes
  the previous 567 ms outlier.
- Two localized stalls remain above the preferred threshold:
  - `149 ms` for one 48-source-chunk initial lazy window.
  - `111 ms` for a 192-source-chunk backward range.
- These do not represent full-book generation and did not produce ANR/OOM
  markers, but they still block the final Phase 6 gate until the range scheduler
  yields inside expensive chunk/table flushes or lazy adjacent ranges become
  adaptive.

Current gate status:

- Immediate rollout safety: passed.
- Correct new-book first meaningful lazy location: targeted automated test
  passed.
- Existing books without stable saved locations: protected by legacy fallback.
- Whole-book chapter targets: structurally available through stable locations.
- Previous/next chapter controls: repaired for lazy stable order; manual UI
  verification is still required.
- Backward unloaded-section loading: profile evidence captured.
- Structural scrubber: implemented; manual UI verification still required.
- Bookmarks/notes: not changed and protected by legacy default route; full lazy
  parity still requires manual/profile verification.
- Phase 6 final gate: **not passed**.

### Phase 6A responsiveness correction, clean-build evidence

Problem after the first lazy-reader stabilization:

- The lazy route no longer performed full-book display generation, but two
  localized range operations still produced main-isolate stalls above the
  Phase 6A threshold:
  - `149 ms` for a 48-source initial lazy window.
  - `111 ms` for a 192-source backward range.

Additional instrumentation added:

- `range_slow_text_measure`
- `range_slow_source_chunk`
- `range_large_chunk_direct_split`

Findings:

- The repeated problematic initial window around `gorgias.xhtml` /
  `republic.xhtml` included a single very large two-column table source chunk:

```text
sourceIndex=615
blockRole=table
publisherLayout=true
textLength=284144
tableRows=1082
tableColumns=2
```

- Before the clean rebuild, Flutter profile runs continued to report stale
  slice metrics (`maxDisplayChunksPerSlice=251`) even after scheduler changes.
  A clean build was required to validate the exact current code.

Corrections made:

- Table height splitting now uses incremental per-row height accounting instead
  of re-measuring a growing candidate table for each row.
- Table display chunks are prevented from being merged back together after
  splitting, so a large table split cannot be undone by the small-chunk merge
  path.
- The range scheduler now has unit-based slice budgets in addition to elapsed
  frame budget:
  - `sourceChunksPerSliceBudget=4`
  - `displayChunksPerSliceBudget=12`
- This preserves deterministic range boundaries and segmented display-cache
  identities while forcing dense table/display output to yield regularly.

Verification commands:

```bash
rtk dart format lib/screens/reader_screen.dart lib/services/frame_budgeted_range_scheduler.dart test/unit/services/frame_budgeted_range_scheduler_test.dart
rtk flutter analyze
rtk flutter test test/unit/services/frame_budgeted_range_scheduler_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart
rtk flutter clean
rtk flutter analyze
rtk flutter test test/unit/services/frame_budgeted_range_scheduler_test.dart
rtk timeout 190 rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_ENABLE_LAZY_READER=true \
  --dart-define=NALORI_LAZY_READER_ONLY_BOOK=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub \
  --dart-define=NALORI_DIAG_NAVIGATE_SPINE_INDEX=22 \
  --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=12 \
  --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=8
```

Evidence:

- Clean-build profile log:
  `/tmp/nalori_phase6_clean_build_unit_budget_profile.log`
- Fixture SHA-256 before run:
  `8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d`

```text
reader_open_route ... route=lazy reason=lazy_reader_enabled
lazy_reader_target_resolved ... spineIndex=21 href=text/gorgias.xhtml
lazy_reader_section_ready ... sectionsParsedBeforeReady=2 chunks=6019 elapsedMs=747
range_large_chunk_direct_split ... sourceIndex=614
range_slow_source_chunk ... phaseName=split sourceIndex=615 elapsedMs=348 subChunks=315 tableRows=1082 tableColumns=2
range_slow_source_chunk ... phaseName=process_subchunks sourceIndex=615 elapsedMs=216 subChunks=315 displayChunksProduced=315 tableRows=1082 tableColumns=2
range_generation_end ... sourceStart=607 sourceEndExclusive=655 inspectedSourceChunks=48 displayChunks=344 elapsedMs=624 sliceCount=73 yieldCount=72 longestWorkIntervalMs=18 maxSliceDurationMs=18 maxSourceChunksPerSlice=4 maxDisplayChunksPerSlice=12
initial_range_ready ... elapsedMs=624 displayChunks=344 longestWorkIntervalMs=18 maxSliceDurationMs=18
diag_auto_navigation_end ... currentPage=316 displayChunks=344 complete=false
```

Interpretation:

- The large table remains expensive in total, but the work is now divided into
  scheduler-controlled slices.
- Maximum continuous display-generation work in the reproduced cold-display
  lazy profile dropped from `149-242 ms` to `18 ms`.
- The generated range remained bounded (`48` inspected source chunks).
- No full-book display generation occurred.
- No `ANR`, `OOM`, `LMKD`, or `FATAL` marker appeared. The profile command
  ended with the expected timeout and Flutter `Lost connection to device`
  message after the scripted scenario.

Phase 6A gate result:

- Responsiveness stall fix: **passed for the reproduced large-table lazy
  scenario**.
- Remaining Phase 6 gates still require exact-revision full-suite verification,
  feature-parity/manual checks, full content equivalence, and repeated distant
  jump memory boundedness before Phase 6 can pass.

### Phase 6B exact-revision verification

Verification commands after the Phase 6A scheduler/table fixes:

```bash
rtk flutter analyze
rtk flutter test
```

Results:

- Static analysis: passed.
- Full Flutter test suite: passed, `467` tests.

Notes:

- This verification was run after the clean-build Android profile evidence and
  after the scheduler unit-budget test was added.
- Phase 6B exact-revision automated verification is passed.
- Phase 6 final gate remains open for manual/profile feature parity,
  equivalence, and memory-bounded repeated-jump verification.

### Phase 6C stabilization update: no-TOC lazy fallback

Failure found after adding the lazy-session chapter/focus regression tests:

- A generated EPUB with no EPUB 3 `nav` manifest item failed during
  `LazyEpubIndexService.openBookIndex`.
- The exception occurred inside the vendored `epubx` schema reader before
  Nalori could use its linear-spine fallback:

```text
Exception: EPUB parsing error: TOC item, not found in EPUB manifest.
packages/epubx/src/readers/navigation_reader.dart
packages/epubx/src/readers/schema_reader.dart
```

Correction:

- `packages/epubx/lib/src/readers/schema_reader.dart` now treats the navigation
  document as optional at schema-open time.
- Package, manifest, and spine parsing still run normally.
- When navigation is unavailable or malformed, `EpubSchema.Navigation` is set to
  `null`, allowing Nalori to build the whole-book fallback structure from the
  linear spine.

Related lazy-session behavior verified:

- `LazyBookSession.loadNextSection()` and `loadPreviousSection()` now advance
  the session's current stable focus to the newly loaded section and release
  distant sections. This supports repeated previous/next unloaded-section
  navigation instead of keeping retention centered on the original section.
- A no-TOC new lazy book now starts at the first non-front-matter linear spine
  item rather than failing before the reader can open.

Verification commands:

```bash
rtk dart format packages/epubx/lib/src/readers/schema_reader.dart lib/services/lazy_book_session.dart test/unit/services/lazy_book_session_test.dart
rtk flutter test test/unit/services/lazy_book_session_test.dart
rtk flutter analyze
rtk flutter test test/unit/services/lazy_epub_index_service_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/parsed_section_cache_service_test.dart test/unit/services/lazy_section_parser_equivalence_test.dart test/unit/services/lazy_reader_route_service_test.dart test/unit/services/lazy_book_session_test.dart
rtk flutter test
```

Results:

- `lazy_book_session_test.dart`: passed, including:
  - next/previous section loading updates current lazy focus;
  - new lazy book without TOC starts at first non-front-matter spine.
- Phase 6 targeted lazy tests: passed, `15` tests.
- Static analysis: passed.
- Full Flutter test suite: passed, `469` tests.

Gate impact:

- No-TOC linear-spine fallback is now covered by automated tests.
- This is necessary for the Phase 6 chapter/scrubber stabilization gate, but
  Phase 6 final gate is still open pending on-device manual/profile checks for
  chapter controls, structural scrubber, saved-position restart, annotations,
  links/footnotes, Speed Read, resources, content equivalence, and repeated
  distant-jump memory boundedness.

### Phase 6C stabilization update: lazy display-segment cache identity

Failure found in the lazy distant-jump profile:

- When switching between lazy loaded windows, segmented display-cache manifests
  were repeatedly rejected even though the logged layout/settings/viewport
  signature matched.
- Root cause: the Phase 4 segmented display cache was keyed by the whole-book
  display layout signature plus local source indices. In the lazy reader, source
  indices are scoped to the currently loaded section window, so `sourceStart=0`
  can mean `republic.xhtml`, `laws.xhtml`, `uncopyright.xhtml`, or another
  loaded window.
- Treating those local ranges as one book-level namespace caused
  `sourceChunkCount` incompatibility and would also risk range identity
  collisions.

Correction:

- Lazy segmented display-cache keys are now scoped by the loaded section-window
  identity:

```text
<layout cache key>_lazy_<spine>_<section checksum>_<spine>_<section checksum>...
```

- Layout, settings, viewport, parser version and display-layout version remain
  part of the compatibility checks.
- Legacy/non-lazy display segment keys are unchanged.

Verification commands:

```bash
rtk dart format lib/screens/reader_screen.dart
rtk flutter analyze
rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/lazy_book_session_test.dart
rtk flutter clean
rtk flutter test test/unit/services/segmented_display_cache_service_test.dart
rtk timeout 190 rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_ENABLE_LAZY_READER=true \
  --dart-define=NALORI_LAZY_READER_ONLY_BOOK=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub \
  --dart-define=NALORI_DIAG_NAVIGATE_SPINE_SEQUENCE=22,30,22 \
  --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=6
```

Clean-build profile evidence:

- Log: `/tmp/nalori_phase6_scoped_cache_clean_profile.log`
- No `segment_cache_signature_rejected` entries occurred after the scoped-key
  clean build.
- Returning to `republic.xhtml` reused the cached scoped display segment:

```text
segment_cache_range_loaded ... cacheKey=..._lazy_22_83260d4f_23_b6a46630 sourceStart=0 sourceEndExclusive=48 displayChunks=30 elapsedMs=2
segment_cache_hit ... cacheKey=..._lazy_22_83260d4f_23_b6a46630 sourceIndex=0 centerStart=0 centerEnd=48 loadedSegments=1
initial_range_ready ... cache=segmented displayChunks=30
reader_display_rebuild_end ... elapsedMs=11 complete=false mode=progressive_segment_cache
```

- `laws.xhtml` used a separate scoped segment namespace:

```text
cacheKey=..._lazy_30_56d84896_31_07034814
```

- A later `segment_cache_rejected reason=stale_after_rename` occurred after the
  lazy window had already moved on; this is expected stale-generation protection
  and did not publish an obsolete segment as current reader state.

Performance and memory evidence from the same run:

```text
Initial lazy open at saved location:
  sectionsParsedBeforeReady=2
  sourceStart=1171 sourceEndExclusive=1219
  inspectedSourceChunks=48
  displayChunks=24
  elapsedMs=91
  longestWorkIntervalMs=8

republic.xhtml first target:
  sourceStart=0 sourceEndExclusive=48
  inspectedSourceChunks=48
  displayChunks=30
  elapsedMs=30
  longestWorkIntervalMs=7

laws.xhtml target:
  sourceStart=0 sourceEndExclusive=48
  inspectedSourceChunks=48
  displayChunks=28
  elapsedMs=29
  longestWorkIntervalMs=4

republic.xhtml return:
  segment cache hit
  reader_display_rebuild_end elapsedMs=11

large table after backward section load:
  sourceStart=608 sourceEndExclusive=656
  displayChunks=344
  elapsedMs=475
  longestWorkIntervalMs=15

Peak RSS in run:
  approximately 344 MB
```

Gate impact:

- Lazy display-segment cache reuse for a distant return path is now verified on
  Android profile mode.
- Phase 6 still remains open for complete feature-parity checks, saved-position
  restart, annotation/navigation parity, Speed Read, resource verification,
  full-vs-lazy content equivalence, and final repeated-jump memory boundedness.

### Phase 6C/6F update: structural lazy labels and saved-location tests

Issue found during Phase 6 review:

- Lazy mode used the structural scrubber for navigation, but the adjacent
  bottom-menu label and page-jump dialog still presented loaded-window page
  semantics as if they represented the whole book.
- This violated the Phase 6 scrubber requirement because final display page
  count is unknown while lazy/progressive pagination is incomplete.

Correction:

- `ReaderScreen` now shows a structural section/chapter label for lazy books
  while display pagination is incomplete.
- The page-number dialog is replaced in that state with a short "Jump by
  Chapter" dialog that points the user to the whole-book chapter list/scrubber.
- The legacy complete-book/page-jump UI remains unchanged for non-lazy books
  and for any future complete display-pagination state.

Additional targeted coverage:

- `valid saved stable location is used as initial lazy target`
- `incompatible saved stable location falls back to meaningful start`

Verification commands:

```bash
rtk dart format lib/screens/reader_screen.dart test/unit/services/lazy_book_session_test.dart
rtk flutter test test/unit/services/lazy_book_session_test.dart
rtk flutter analyze
rtk flutter test
rtk sha256sum 'Dialogues -- Plato.epub'
```

Results:

- `lazy_book_session_test.dart`: passed, `8` tests.
- Static analysis: passed.
- Full Flutter test suite: passed, `471` tests.
- Fixture SHA-256 remained
  `8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d`.

### Phase 6 Android profile: lazy navigation, chapters, backward prepend, memory

Profile command:

```bash
rtk timeout 210 rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_ENABLE_LAZY_READER=true \
  --dart-define=NALORI_LAZY_READER_ONLY_BOOK=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=dialogues_plato.epub \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub \
  --dart-define=NALORI_DIAG_NAVIGATE_SPINE_SEQUENCE=22,30,35,4,22 \
  --dart-define=NALORI_DIAG_AUTO_NEXT_CHAPTERS=2 \
  --dart-define=NALORI_DIAG_AUTO_PREV_CHAPTERS=3 \
  --dart-define=NALORI_DIAG_AUTO_BACKWARD_PAGES=12 \
  --dart-define=NALORI_DIAG_AUTO_FORWARD_PAGES=8
```

Filtered log artifact:

```text
/tmp/nalori_phase6_lazy_nav_profile_20260609.log
```

Key evidence:

```text
reader_open_route ... route=lazy reason=lazy_reader_enabled lastReadIndex=1635 hasStableLastReadLocation=true
lazy_reader_index_ready ... sectionsIndexed=36 elapsedMs=146
lazy_reader_target_resolved ... spineIndex=24 href=text/critias.xhtml
lazy_reader_section_ready ... sectionsParsedBeforeReady=2 chunks=1219 elapsedMs=279
initial_range_ready ... sourceStart=1171 sourceEndExclusive=1219 inspectedSourceChunks=48 displayChunks=24 elapsedMs=71 longestWorkIntervalMs=4
reader_display_rebuild_end ... elapsedMs=97 displayChunks=24 complete=false mode=progressive_initial_range
reader_display_cache_write_skipped_partial ... reason=progressive_display_incomplete

diag_auto_navigation_stable_target ... spineIndex=22 href=text/republic.xhtml
lazy_reader_target_resolved ... spineIndex=22 href=text/republic.xhtml loadedChunks=7038
initial_range_ready ... sourceStart=0 sourceEndExclusive=48 displayChunks=30 elapsedMs=40 longestWorkIntervalMs=8

diag_auto_navigation_stable_target ... spineIndex=30 href=text/laws.xhtml
lazy_reader_target_resolved ... spineIndex=30 href=text/laws.xhtml loadedChunks=2826
initial_range_ready ... sourceStart=0 sourceEndExclusive=48 displayChunks=28 elapsedMs=28 longestWorkIntervalMs=3

diag_auto_navigation_stable_target ... spineIndex=35 href=text/uncopyright.xhtml
initial_range_ready ... sourceStart=0 sourceEndExclusive=8 displayChunks=7 elapsedMs=7 longestWorkIntervalMs=2 hasLaterContent=false

diag_auto_navigation_stable_target ... spineIndex=4 href=text/preface-2.xhtml
lazy_section_cache_miss ... spineIndex=4 href=text/preface-2.xhtml
lazy_reader_target_resolved ... spineIndex=4 href=text/preface-2.xhtml loadedChunks=189
initial_range_ready ... sourceStart=0 sourceEndExclusive=48 displayChunks=26 elapsedMs=31 longestWorkIntervalMs=7

diag_auto_navigation_stable_target ... spineIndex=22 href=text/republic.xhtml
segment_cache_range_loaded ... cacheKey=..._lazy_22_83260d4f_23_b6a46630 sourceStart=0 sourceEndExclusive=48 displayChunks=30 elapsedMs=2
segment_cache_hit ... loadedSegments=1
reader_display_rebuild_end ... elapsedMs=9 complete=false mode=progressive_segment_cache

diag_auto_next_chapter ... step=1 title=Timaeus
range_publish ... direction=target sourceStart=5395 sourceEndExclusive=5443 rangeElapsedMs=29 longestWorkIntervalMs=4
diag_auto_next_chapter ... step=2 title=Critias
lazy_reader_target_resolved ... spineIndex=24 href=text/critias.xhtml loadedChunks=2854

diag_auto_prev_chapter ... step=1 title=Introduction and Analysis
diag_auto_prev_chapter ... step=2 title=Introduction and Analysis
diag_auto_prev_chapter ... step=3 title=Introduction and Analysis
range_generation_end ... direction=backward sourceStart=1435 sourceEndExclusive=1627 inspectedSourceChunks=192 displayChunks=136 elapsedMs=135 longestWorkIntervalMs=3
range_prepend ... displayChunksInserted=136 sourceStart=1435 sourceEndExclusive=1627
range_publish ... direction=backward displayChunks=164 complete=false
diag_auto_navigation_end ... currentPage=139 displayChunks=164 complete=false
```

Memory/performance summary:

- Peak logged Nalori RSS in this run: `332,099,584` bytes (~317 MB).
- Previous full extraction baseline: ~893 MB RSS.
- Largest observed range total in this run: `135 ms`, but sliced with
  `longestWorkIntervalMs=3`.
- No full-book display generation occurred.
- No complete display-cache write occurred.
- Segmented display cache was reused on return to `republic.xhtml`.
- Section retention stayed bounded by eviction logs (`retained=3`).
- The log contains system `lowmemorykiller` pressure messages, but each says
  `Not killing`; no Nalori `FATAL EXCEPTION`, `ANR in`, `OutOfMemory`, or
  `am_crash` marker appears. The Nalori process exit was the expected timeout
  ending the profile run.

Phase 6 gate impact:

- Passed evidence for:
  - production lazy route behind allow-list;
  - saved stable location route selection;
  - structural TOC/spine distant targets;
  - `republic.xhtml`, `laws.xhtml`, final-spine, and early-spine navigation;
  - previous/next chapter diagnostic actions through stable targets;
  - backward range prepend from unloaded/earlier content;
  - bounded display slices;
  - bounded retained sections and low RSS relative to baseline;
  - partial segmented display-cache reuse.
- Still open:
  - manual annotation parity for bookmark rename/colour, highlights, notes,
    dictionary and character occurrence navigation in initially unloaded
    sections;
  - internal link, footnote and backlink navigation in lazy mode;
  - Speed Read crossing an unloaded section boundary;
  - lazy image/resource rendering in the reader;
  - full private-EPUB legacy-vs-lazy content equivalence diagnostic;
  - a real force-stop/reopen saved-position restart using lazy parsed-section
    and segmented-display caches.

Phase 6 final gate result: **not passed yet**. Lazy reading remains
default-off and restricted to diagnostic/allow-listed use.

### Phase 6 update: lazy resource and footnote content parity

Date: 2026-06-09.

Files modified in this update:

- `lib/services/epub_parser.dart`
- `lib/services/lazy_parsed_book.dart`
- `lib/services/lazy_section_repository.dart`
- `test/unit/services/lazy_section_repository_test.dart`

Design correction:

- `parseLazySection` now receives explicit section classification instead of
  asking a synthetic one-file `EpubBook` to infer front matter/content from
  incomplete global context.
- `LazySectionRepository` reads only image resources referenced by the current
  XHTML section and passes those bytes to the parser isolate. It does not load
  distant images.
- Cross-section footnote/endnote content is loaded only when the target note
  XHTML appears before the current section in manifest order. This preserves
  the legacy parser's order-dependent bracketed footnote-marker behavior without
  parsing the whole book.
- Lazy parsed-section parser version was bumped from `section_v1` to
  `section_v2`, so image-less or footnote-incomplete cached sections are treated
  as stale and regenerated independently.

Targeted tests:

```text
rtk flutter test \
  test/unit/services/lazy_section_repository_test.dart \
  test/unit/services/lazy_section_parser_equivalence_test.dart
```

Result: passed, 4 tests.

Full verification on the exact current revision:

```text
rtk flutter analyze
rtk flutter test
```

Results:

- `rtk flutter analyze`: passed, no issues.
- `rtk flutter test`: passed, 472 tests.

Private EPUB content-equivalence diagnostic:

```text
rtk timeout 300 rtk flutter test /tmp/nalori_private_lazy_equivalence_test.dart \
  --dart-define=NALORI_PRIVATE_EPUB_PATH=/home/uttam/Desktop/Antigravity\ Projects/Nalori/Dialogues\ --\ Plato.epub
```

Result: passed.

Objective output summary:

```text
full_chunks=20460
lazy_chunks=20439
full_tables=28
lazy_tables=28
full_images=3
lazy_images=3
spine_source_mismatches=<empty>
full_only_sources=toc.xhtml
```

Interpretation:

- All 36 spine-item source texts matched source-by-source after normalization.
- Table count matched.
- Image count matched.
- The legacy complete parser additionally parses `toc.xhtml`, which is an EPUB
  navigation document outside the 36-item linear spine. The lazy production
  reader uses the linear spine for readable content and the EPUB navigation
  index for chapter/TOC UI.

Android profile verification after the resource/footnote fix:

Command output captured at:

```text
/tmp/nalori_phase6_lazy_profile_after_resources_run_20260609.log
```

Profile command used lazy mode only for `dialogues_plato.epub`, cleared only
that book's segmented display cache and parsed-section cache, and navigated
through `republic.xhtml`, `laws.xhtml`, the final spine item, an early section,
and backward ranges.

Key metrics:

```text
Fixture SHA-256: 8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
Route: lazy, allow-listed diagnostic book
Index open: 37 ms
Initial section before readiness: text/timaeus.xhtml, 1635 chunks, 188 ms parse
Adjacent section before readiness: text/critias.xhtml, 207 chunks, 26 ms parse
Initial display window: 48 source chunks, 29 display chunks, 36 ms range time
Initial reader display rebuild end: 73 ms, complete=false
Republic parse: 5401 chunks, 334 ms
Republic initial range: 48 source chunks, 30 display chunks, 34 ms
Laws parse: 2477 chunks, 375 ms
Laws initial range: 48 source chunks, 28 display chunks, 30 ms
Backward prepend: 192 source chunks, 136 display chunks, 126 ms total
Maximum longestWorkIntervalMs: 12 ms
Maximum maxSliceDurationMs: 12 ms
Peak logged RSS: 361,148,416 bytes (~344 MB)
Retained section count: bounded at 3 via lazy_section_evict logs
Full display generation: not observed
EpubReader.readBook in lazy route: not observed
Complete display-cache write: not observed
```

Failure-marker scan:

- No `FATAL EXCEPTION`, `ANR in`, `OutOfMemory`, `am_crash`,
  `lowmemorykiller`, or `LMKD` marker appeared in the preserved run output.
- The final `Lost connection to device` line was the expected `rtk timeout`
  termination of the profile session.

Memory comparison:

```text
Previous full extraction baseline: ~893 MB RSS
Latest lazy peak: ~344 MB RSS
Reduction: ~61.5%
Preferred Phase 6 memory target: below ~536 MB RSS
Result: passed for this profile scenario
```

Phase 6 gate impact:

- Fixed and verified:
  - lazy same-section image preservation;
  - lazy referenced-resource loading limited to the current section;
  - legacy-compatible cross-section footnote marker/content handling;
  - private EPUB source-by-source text equivalence for all spine items;
  - low main-isolate display slices after the resource fix;
  - memory below the Phase 6 target in Android profile mode.
- Still open before Phase 6 can pass:
  - manual annotation parity for bookmark rename/colour, highlights, notes,
    dictionary and character occurrence navigation in initially unloaded
    sections;
  - internal link, footnote and backlink navigation actions in the reader UI;
  - Speed Read crossing an unloaded section boundary;
  - real force-stop/reopen saved-position restart using lazy parsed-section and
    segmented-display caches;
  - complete Phase 6 stabilization matrix on new book, existing book,
    multi-part book, supplied large EPUB, and no-useful-TOC book.

Phase 6 final gate result remains: **not passed**. Lazy reading must remain
default-off with the kill switch and legacy fallback retained.

### Phase 6 saved-position force-stop/reopen verification

Diagnostic code added:

- `ReaderScreen` now prefers `initialStableLocation` over legacy loaded-window
  index during lazy reader initialization when the stable location resolves
  inside the loaded section window.
- Guarded `NALORI_EPUB_DIAG` logs now emit `stable_location_initial_restore`
  and `stable_location_saved` with spine index, href, local chunk index,
  text offset, source checksum and normalized context.
- Diagnostic auto-navigation flushes the normal reading-position save path
  before emitting `diag_auto_navigation_end`. This is temporary
  instrumentation for Phase 9 cleanup.

Targeted validation after this change:

```text
rtk dart format lib/screens/reader_screen.dart
rtk flutter test test/unit/services/lazy_book_session_test.dart test/unit/models/stable_book_location_test.dart
rtk flutter analyze
```

All commands passed.

Device setup note:

- The first profile retry hit an Android install signature mismatch. Flutter
  uninstalled and reinstalled `com.nalori.reader`, which removed app-private
  diagnostic data on the device.
- The private EPUB was restored to:

```text
/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub
```

- On-device checksum after restore:

```text
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
```

Save run:

```text
/tmp/nalori_phase6_saved_position_save_20260612_retry.log
```

Command opened the supplied EPUB through the allow-listed lazy route, navigated
to `text/republic.xhtml`, moved forward two pages, and flushed the production
metadata save path.

Saved stable location:

```text
spineIndex=22
href=text/republic.xhtml
sourceChecksum=83260d4f
localChunkIndex=3
textOffset=0
legacyGlobalChunkIndex=3
context=but no other dialogue of plato has the same largeness of view and the same perfection of style; no other shows an equal knowledge of the world, or contains more of those thoughts which are new as well as old, and not of one age only but of all.
```

Save-run cache/performance evidence:

```text
Route: lazy
Index ready: 2706 ms
Initial display after title/imprint window: 25 ms
Republic parsed-section cache: miss, parsed/written
Timaeus adjacent parsed-section cache: miss, parsed/written
Republic segmented display cache: miss, generated 48 source chunks / 32 display chunks
Republic range generation: 40 ms total, max slice 8 ms
Reader display mode: progressive_initial_range, complete=false
Full-book parse: not observed
Full display generation: not observed
```

Reopen run after force-stop/timeout:

```text
/tmp/nalori_phase6_saved_position_reopen_20260612.log
```

Reopen evidence:

```text
reader_open_route route=lazy lastReadIndex=3 hasStableLastReadLocation=true
lazy_reader_target_resolved spineIndex=22 href=text/republic.xhtml
stable_location_initial_restore spineIndex=22 href=text/republic.xhtml localChunkIndex=3 textOffset=0 resolvedOriginalIndex=3 targetOriginalIndex=3 usedStableLocation=true
```

Restored normalized context:

```text
but no other dialogue of plato has the same largeness of view and the same perfection of style; no other shows an equal knowledge of the world, or contains more of those thoughts which are new as well as old, and not of one age only but of all.
```

Result:

```text
before force-stop normalized context == after reopen normalized context
```

Reopen cache evidence:

```text
Index open: 26 ms
Reader target resolved: 111 ms elapsed
Parsed-section cache hits: republic.xhtml and timaeus.xhtml
Segmented display cache hit: lazy_22_83260d4f_23_b6a46630, segment 0..48
Display ready from segment cache: 50 ms, complete=false
Full-book parse: not observed
EpubReader.readBook: not observed
```

Failure-marker scan:

- No `FATAL EXCEPTION`, `ANR in`, `OutOfMemory`, `am_crash`,
  `lowmemorykiller`, or `LMKD` marker appeared in the saved-position save or
  reopen logs.
- The final `Lost connection to device` lines were expected `rtk timeout`
  termination of attached profile sessions.

Gate result for saved-position force-stop/reopen: **passed**.

Phase 6 final gate result remains: **not passed**. Remaining required feature
parity work: bookmarks, highlights/notes, dictionary/character Go To,
internal links/footnotes/backlinks, Speed Read across unloaded sections,
stabilization matrix, full latest tests, and final Android profile gate.

### Phase 6 parity continuation - annotations, links, Speed Read

Date: 2026-06-12.

Production code changes made in this continuation:

- `ReaderScreen._navigateToStableLocation` now resolves existing loaded
  targets through `_sourceIndexForStableLocation` instead of a section-only
  first match.
- `_sourceIndexForStableLocation` now prefers loaded EPUB anchor IDs before
  falling back to local chunk matching. This prevents fragment/chapter/internal
  link targets from collapsing to the first chunk in a loaded section.
- Stable-location navigation now performs a post-display completion step:
  after a target lazy section/window is loaded and displayed, it resolves the
  exact display page from source chunk, offset, and normalized context, then
  navigates to that display page.
- `AnnotationsPanel` navigation now forwards stable locations for highlights,
  notes, dictionary entries, and character records. `ReaderScreen` prefers the
  stable location and falls back to legacy chunk/offset fields only when needed.
- Internal link taps now route unloaded lazy targets through
  `LazyBookSession.resolveAnchor(href, fragment)` and
  `_navigateToStableLocation`.
- Speed Read auto page advance now requests the next progressive/lazy range
  when the current page completes at an unavailable boundary instead of
  returning early.
- Concrete progressive display-range requests are clamped to the currently
  loaded source chunk list before cache lookup or generation. This prevents the
  lazy "content exists after this window" sentinel from being treated as a real
  source chunk.

Temporary diagnostic additions for Phase 9 cleanup:

- `NALORI_DIAG_ANNOTATION_PARITY`
- `NALORI_DIAG_SPEED_READ_BOUNDARY`
- `stable_location_restore_check`
- `stable_location_pending_restore_set`
- `stable_location_navigation_complete`
- `diag_annotation_goto_result`
- `diag_speed_read_boundary_result`

Targeted commands after the code changes:

```text
rtk dart format lib/screens/reader_screen.dart
rtk flutter analyze
rtk flutter test test/unit/services/lazy_book_session_test.dart test/unit/models/stable_book_location_test.dart test/unit/models/highlight_test.dart test/unit/models/bookmark_test.dart test/unit/models/saved_word_test.dart
rtk flutter test test/unit/controllers/speed_read_controller_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_parser_equivalence_test.dart
rtk flutter test test/unit/controllers/speed_read_controller_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart
rtk flutter test
```

Results:

```text
Static analysis: passed
Focused annotation/navigation tests: passed
Focused Speed Read/progressive/lazy tests: passed
Full suite: passed, 472 tests
```

EPUB checksum verification:

```text
Local fixture:
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d  Dialogues -- Plato.epub

On-device app-private copy:
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d  app_flutter/books/dialogues_plato.epub
```

Annotation parity profile evidence:

```text
/tmp/nalori_phase6_annotation_parity_final_20260612.log
```

Scenario:

```text
lazy open Dialogues
→ navigate to republic.xhtml
→ create diagnostic bookmark/highlight/note/dictionary/character records at
  spineIndex=22, href=text/republic.xhtml, localChunkIndex=3
→ navigate to titlepage.xhtml to unload/evict republic
→ Book Memory / annotation Go To for each record
```

Expected normalized context:

```text
but no other dialogue of plato has the same largeness of view and the same perfection of style; no other shows an equal knowledge of the world, or contains more of those thoughts which are new as well as old, and not of one age only but of all.
```

Result:

```text
bookmark contextMatch=true
highlight contextMatch=true
note contextMatch=true
dictionary contextMatch=true
character contextMatch=true
```

Cache/performance evidence from that run:

```text
reader_open_route route=lazy
parsed-section cache hits: republic.xhtml, timaeus.xhtml, titlepage.xhtml, imprint.xhtml
segmented display cache hits: republic/timaeus and titlepage/imprint windows
republic stable target displayIndex=2
reader_display_rebuild_end republic cache hit: 12 ms
complete=false
EpubReader.readBook: not observed
full display generation: not observed
```

Failure encountered and correction:

- Initial annotation profile runs showed the first bookmark Go To after a lazy
  section reload landing on `republic introduction and analysis` instead of
  local chunk 3. The cause was section-level fallback through
  `_originalToDisplay`, where source chunk 3 was mapped into an earlier display
  card containing multiple source chunks.
- Correction: stable-location navigation now completes after the target display
  window is ready and uses the source text/offset locator to choose the exact
  display page. The corrected clean profile run produced
  `contextMatch=true` for all five target types.

Speed Read boundary profile evidence:

```text
/tmp/nalori_phase6_speed_read_boundary_auto_20260612.log
```

Scenario:

```text
lazy open Dialogues
→ navigate near the end of the loaded lazy section window
→ start Speed Read on the boundary page
→ force auto page-advance only inside the diagnostic
→ let Speed Read request and enter the next unavailable range
```

Important events:

```text
lazy_section_cache_hit spineIndex=24 href=text/critias.xhtml
range_generation_end initial 48 source chunks, 30 display chunks, 49 ms total, maxSliceDurationMs=3
range_generation_end target 47 source chunks, 25 display chunks, 38 ms total, maxSliceDurationMs=4
lazy_reader_section_requested direction=forward spineIndex=26 href=text/theaetetus.xhtml
range_generation_end forward 192 source chunks, 107 display chunks, 132 ms total, maxSliceDurationMs=7
range_append displayChunksAdded=107
boundary_wait_begin direction=forward currentPage=131
range_generation_end forward 192 source chunks, 105 display chunks, 141 ms total, maxSliceDurationMs=10
range_append displayChunksAdded=105
diag_speed_read_boundary_result crossedBoundary=true speedReadActive=true speedReadPaused=false speedReadPageComplete=false
```

Failure encountered and correction:

- A diagnostic run near the end of the lazy window exposed a real
  `RangeError`: the target range was planned as `6989..7037` while the loaded
  source list ended at `7036`. This came from the lazy sentinel used to report
  unavailable later content.
- Correction: concrete progressive display requests are clamped to the loaded
  source list before cache lookup or display generation.
- Clean profile evidence after the fix shows the request clamped to
  `6989..7036`, no `RangeError`, and subsequent lazy forward generation.

Failure-marker scans:

- No `FATAL EXCEPTION`, `ANR in`, `OutOfMemory`, `am_crash`,
  `lowmemorykiller`, or `LMKD` marker appeared in the final annotation or
  Speed Read profile logs.
- The final `Lost connection to device` lines were expected `rtk timeout`
  termination of attached profile sessions.

Internal-link / footnote profile evidence:

```text
/tmp/nalori_phase6_internal_link_footnote_20260612.log
```

Scenario:

```text
lazy open Dialogues
→ navigate to republic.xhtml through the real stable lazy navigation path
→ search the loaded lazy window for an internal link and footnote refs
→ invoke the real reader `_onLinkTap` path for the internal link
```

Result:

```text
Internal link found:
sourceIndex=251
url=#republic-book-3-p-276

Navigation result:
afterSpineIndex=22
afterHref=text/republic.xhtml
afterLocalChunkIndex=3252
afterContext=most assuredly. and when a beautiful soul harmonizes with a beautiful form, and the two are cast in one mould, that will be the fairest of sights to him who has an eye to see it?
```

This proves same-section internal anchor navigation routes through the lazy
reader path and resolves to a non-loaded local chunk inside `republic.xhtml`
without full-book parsing.

Footnote result:

```text
diag_footnote_content_skipped reason=no_loaded_footnotes
```

No footnote refs were present in the loaded private-EPUB diagnostic window, so
footnote/backlink UI remains unverified in Android profile. Parser/resource
parity for linked footnote content remains covered by automated equivalence
tests, but the Phase 6 final gate still requires a direct reader UI profile on
a fixture with loaded footnotes/backlinks.

Failure-marker scan:

- No `FATAL EXCEPTION`, `ANR in`, `OutOfMemory`, `am_crash`,
  `lowmemorykiller`, or `LMKD` marker appeared in the internal-link profile
  log.
- `EpubReader.readBook` and full-display generation were not observed.

Phase 6 gate status after this continuation:

```text
Saved-position force-stop/reopen: passed
Bookmark Go To parity: passed on private EPUB profile
Highlight Go To parity: passed on private EPUB profile
Note Go To parity: passed on private EPUB profile
Dictionary Go To parity: passed on private EPUB profile
Character Go To parity: passed on private EPUB profile
Internal link lazy routing: passed for same-section private EPUB anchor
Footnote/backlink UI: parser/resource parity exists; direct reader UI tap evidence still needed on a footnote fixture
Speed Read across lazy boundary: passed on private EPUB profile
Latest static analysis: passed
Latest full test suite: passed, 472 tests
EPUB checksum: unchanged
```

Phase 6 final gate result remains: **not passed**. Remaining required work:
direct UI/profile evidence for internal links and footnotes/backlinks,
stabilization matrix across several book types, final repeated-jump memory
boundedness profile on the current revision, and rollout-safety verification
after those checks.

## Phase 6 synthetic feature-rich EPUB and footnote/backlink UI evidence

Added a deterministic legal synthetic EPUB generator:

```text
tool/generate_feature_rich_lazy_reader_epub.dart
```

Generated fixture:

```text
test/fixtures/books/feature_rich_lazy_reader.epub
size: 4,783 bytes
content: generated synthetic text only
image: generated 4x4 PNG from package:image encoder
spine: titlepage.xhtml, chapter-1.xhtml, chapter-2.xhtml, chapter-3.xhtml, notes.xhtml
TOC: Part I -> Chapters 1-2, Part II -> Chapter 3, Notes
```

Fixture coverage:

```text
Chapter 1:
  saved-position target paragraph
  same-section anchor
  cross-section link to Chapter 2
  cross-section noteref to notes.xhtml#note-1
  generated PNG image
  table
  repeated phrase: luminous pebble
  repeated name: Mira

Notes:
  note-1 footnote
  backlink to chapter-1.xhtml#origin-paragraph
```

Automated tests added:

```text
test/unit/services/feature_rich_lazy_reader_fixture_test.dart
```

Targeted test result:

```bash
rtk flutter test test/unit/services/feature_rich_lazy_reader_fixture_test.dart
```

Result:

```text
6 tests passed
```

The tests verify:

```text
meaningful Chapter 1 start
nested TOC Part I/Part II targets
cross-section footnote target loading
backlink target loading
cross-section internal anchor loading
notes section not loaded before requested
image resource loaded only for Chapter 1
table chunk parsed
repeated phrase context disambiguation
missing fragment does not produce a false exact match
```

Android profile footnote/backlink UI evidence:

```text
Device: 00162352B003164
Build mode: profile
Book: feature_rich_lazy_reader.epub
Lazy route: allow-listed only for feature_rich_lazy_reader.epub
Command intent:
  NALORI_ENABLE_LAZY_READER=true
  NALORI_LAZY_READER_ONLY_BOOK=feature_rich_lazy_reader.epub
  NALORI_DIAG_FOOTNOTE_BACKLINK=true
  NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR=feature_rich_lazy_reader.epub
  NALORI_DIAG_CLEAR_PARSED_CACHE_FOR=feature_rich_lazy_reader.epub
```

Important evidence from the final clean run:

```text
reader_open_route route=lazy
lazy_epub_index_open_end spineItems=5 manifestItems=7 chapters=4 elapsedMs=9
lazy_section_cache_miss spineIndex=1 href=chapter-1.xhtml reason=no_manifest
lazy_resource_load_begin path=images/generated-square.png mediaType=image/png
lazy_resource_load_end path=images/generated-square.png bytes=77 elapsedMs=0
lazy_section_parse_end spineIndex=1 href=chapter-1.xhtml chunks=23 resources=4
diag_footnote_forward_result contextMatch=true
  url=notes.xhtml#note-1
  expectedContext=synthetic footnote content for lazy cross section navigation.
  actualContext=synthetic footnote content for lazy cross section navigation. return
  spineIndex=4 href=notes.xhtml localChunkIndex=1
diag_footnote_backlink_result contextMatch=true
  url=chapter-1.xhtml#origin-paragraph
  expectedContext=synthetic paragraph with a unique source context for lazy footnote testing.
  actualContext=synthetic paragraph with a unique source context for lazy footnote testing. mira studies the repeated phrase luminous pebble before following the cross section note. 1
  spineIndex=1 href=chapter-1.xhtml localChunkIndex=1
reader_display_rebuild_end generation=3 elapsedMs=13 displayChunks=26 complete=false mode=progressive_segment_cache
```

Corrections made during fixture validation:

- The initial EPUB 3 `nav.xhtml` used `span`-only Part entries. The vendored
  navigation reader does not retain those as usable lazy chapter targets, so
  the fixture now uses linked Part entries pointing at stable section anchors.
- A hand-written tiny PNG produced `Exception: Could not decompress image` in
  Flutter `Image.memory`. The fixture now generates PNG bytes through
  `package:image`, and the final profile output showed the resource loading
  successfully with no repeated image decode error in the visible diagnostic
  output.

Gate impact:

```text
Direct Android footnote forward-link UI evidence: passed
Direct Android backlink UI evidence: passed
Cross-section lazy href/fragment resolution: passed on synthetic fixture
Lazy image resource loading for current section: passed in targeted tests and profile resource logs
Full Phase 6 gate: still not passed
```

Remaining Phase 6 work:

```text
final stabilization matrix across required EPUB types
repeated distant-jump memory/eviction profile on current revision
rollout-safety verification on current revision
latest analysis and full suite after final Phase 6 changes
```

## Phase 6 final stabilization evidence

Additional automated fixture:

```text
test/fixtures/books/feature_rich_lazy_reader.epub
tool/generate_feature_rich_lazy_reader_epub.dart
```

The fixture is deterministic, synthetic, and legal to commit. It contains
front matter, Part I, Chapters 1-2, Part II, Chapter 3, a notes section, a
generated PNG image, a table, repeated phrases/names, a same-section anchor,
a cross-section internal link, a cross-section footnote, and a backlink.

Targeted tests:

```bash
rtk flutter test test/unit/services/feature_rich_lazy_reader_fixture_test.dart \
  test/unit/services/lazy_reader_route_service_test.dart \
  test/unit/services/lazy_book_session_test.dart \
  test/unit/services/lazy_section_parser_equivalence_test.dart \
  test/unit/services/lazy_section_repository_test.dart
```

Result:

```text
19 tests passed
```

Final exact-revision verification:

```bash
rtk flutter pub get
rtk dart format tool/generate_feature_rich_lazy_reader_epub.dart test/unit/services/feature_rich_lazy_reader_fixture_test.dart lib/screens/reader_screen.dart
rtk flutter analyze
rtk flutter test
rtk sha256sum 'Dialogues -- Plato.epub'
```

Results:

```text
rtk flutter analyze: passed
rtk flutter test: passed, 478 tests before Phase 7 metadata change
Fixture SHA-256: 8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
```

Direct Android reader UI footnote/backlink evidence:

```text
Device: 00162352B003164
Build mode: profile
Lazy route: allow-listed to feature_rich_lazy_reader.epub
```

Evidence:

```text
reader_open_route route=lazy
lazy_epub_index_open_end spineItems=5 manifestItems=7 chapters=4 elapsedMs=9
lazy_section_cache_miss spineIndex=1 href=chapter-1.xhtml reason=no_manifest
lazy_resource_load_end path=images/generated-square.png bytes=77
diag_footnote_forward_result contextMatch=true
  url=notes.xhtml#note-1
  expectedContext=synthetic footnote content for lazy cross section navigation.
  actualContext=synthetic footnote content for lazy cross section navigation. return
  spineIndex=4 href=notes.xhtml localChunkIndex=1
diag_footnote_backlink_result contextMatch=true
  url=chapter-1.xhtml#origin-paragraph
  expectedContext=synthetic paragraph with a unique source context for lazy footnote testing.
  actualContext=synthetic paragraph with a unique source context for lazy footnote testing. mira studies the repeated phrase luminous pebble before following the cross section note. 1
  spineIndex=1 href=chapter-1.xhtml localChunkIndex=1
reader_display_rebuild_end elapsedMs=13 displayChunks=26 complete=false mode=progressive_segment_cache
```

Repeated distant-jump memory and eviction profile:

```text
Device: 00162352B003164
Build mode: profile
Book: dialogues_plato.epub
Navigation sequence: 1,22,18,35,1,24,22
```

Observed jump results:

| Target | RSS | Retained sections | Loaded spine indices | Complete |
|---|---:|---:|---|---|
| spine 1 / imprint | 299,769,856 | 3 | 1,2 | false |
| spine 22 / republic | 323,620,864 | 3 | 22,23 | false |
| spine 18 / apology | 319,434,752 | 3 | 18,19 | false |
| spine 35 / uncopyright | 308,977,664 | 3 | 35 | false |
| spine 1 / imprint | 312,696,832 | 3 | 1,2 | false |
| spine 24 / critias | 314,712,064 | 3 | 24,25 | false |
| spine 22 / republic | 318,025,728 | 3 | 22,23 | false |

Eviction evidence included:

```text
lazy_section_evict spineIndex=22 href=text/republic.xhtml retained=3
lazy_section_evict spineIndex=23 href=text/timaeus.xhtml retained=3
lazy_section_evict spineIndex=1 href=text/imprint.xhtml retained=3
lazy_section_evict spineIndex=18 href=text/apology.xhtml retained=3
lazy_section_evict spineIndex=19 href=text/crito.xhtml retained=3
lazy_section_evict spineIndex=35 href=text/uncopyright.xhtml retained=3
lazy_section_evict spineIndex=24 href=text/critias.xhtml retained=3
```

Returning to `republic.xhtml` used parsed-section cache hits for the previously
cached section. Maximum observed layout slice in the repeated-jump profile was
12 ms. RSS remained bounded at approximately 300-324 MB and did not trend
toward the prior 893 MB full-extraction baseline.

Rollout-safety verification:

| Scenario | Evidence | Result |
|---|---|---|
| Default lazy disabled | `reader_open_route route=legacy reason=lazy_reader_disabled_or_not_allowed` for synthetic fixture | Pass |
| Allow-list mismatch | lazy enabled but allow-list set to Dialogues; synthetic fixture opened with legacy route | Pass |
| Per-book disable marker | `test/unit/services/lazy_reader_route_service_test.dart` verifies independent reversible marker | Pass |
| Data safety | Route switches did not clear metadata, annotations, parsed-section cache, segmented display cache, or EPUB files | Pass |

Failure-marker scan:

```text
No FATAL EXCEPTION, ANR in, OutOfMemory, or am_crash marker appeared in the
final Phase 6 profile windows. Low-memory pressure messages were present but
explicitly logged as "Not killing" or "Ignoring"; no LMKD kill occurred.
```

Phase 6 stabilization matrix:

| Fixture | Workflow | Expected target | Actual target | Context match | Cache behavior | Evidence | Pass/fail |
|---|---|---|---|---|---|---|---|
| Synthetic feature-rich EPUB | footnote forward link | `notes.xhtml#note-1` | `notes.xhtml`, local chunk 1 | yes | notes section loaded on demand | Android profile `diag_footnote_forward_result` | Pass |
| Synthetic feature-rich EPUB | footnote backlink | `chapter-1.xhtml#origin-paragraph` | `chapter-1.xhtml`, local chunk 1 | yes | chapter 1 reused/loaded on demand | Android profile `diag_footnote_backlink_result` | Pass |
| Synthetic feature-rich EPUB | cross-section internal link | `chapter-2.xhtml#chapter-2-target` | Chapter 2 target paragraph | yes | target section loaded only when requested | targeted test | Pass |
| Synthetic feature-rich EPUB | image/table | generated image + Chapter 1 table | image resource and table chunk present only in Chapter 1 window | yes | no distant image before section load | targeted test + profile resource log | Pass |
| Synthetic feature-rich EPUB | nested chapters and parts | Part I, Chapters 1-2, Part II, Chapter 3 | complete nested TOC targets | yes | index-only chapter model | targeted test | Pass |
| Synthetic feature-rich EPUB | repeated phrase disambiguation | exact section context | separate Chapter 1/2 contexts | yes | stable section anchors | targeted test | Pass |
| Plato private EPUB | content equivalence | legacy full parser output | lazy joined 36 spine sections | yes | sequential diagnostic only | prior Phase 6 equivalence run | Pass |
| Plato private EPUB | tables/images | 28 tables, 3 images | 28 tables, 3 images | yes | section-local resources | prior Phase 6 evidence | Pass |
| Plato private EPUB | repeated distant jumps | bounded retained sections | retained sections stayed at 3 | n/a | cache hits on return; evictions observed | Android profile | Pass |
| No-TOC generated fixture | initial/chapter fallback | linear spine fallback | first substantive spine target | yes | index-only fallback | existing lazy session tests | Pass |
| Legacy route | lazy disabled | complete-reader route | legacy route selected | n/a | no lazy data deletion | Android route profile | Pass |

Phase 6 final gate result: **passed, with lazy still default-off**.

Rationale:

- Production lazy route exists but is guarded by `NALORI_ENABLE_LAZY_READER`.
- Lazy route does not call `EpubReader.readBook`.
- Reader readiness does not require a complete parsed `List<BookChunk>`.
- Parsed sections and display segments are cached independently.
- Footnote, backlink, internal link, annotation, saved-position, Speed Read,
  chapter, scrubber, resource, content-equivalence, and memory-boundedness
  evidence is recorded above and in the earlier Phase 6 sections.
- Latest exact revision passed static analysis and the full automated suite.
- The private EPUB checksum remained unchanged.

Lazy reading remains disabled by default until Phase 8 makes the rollout
decision.

## Phase 7 - Lightweight metadata and import path

### Goal

Remove full EPUB content parsing from metadata/import extraction. Metadata and
cover extraction should use the lightweight EPUB index and direct cover
resource loading.

### Implementation

`BookMetadataService.extractAndCacheMetadata` now uses:

```text
LazyEpubIndexService.openBookIndex
→ index title/author metadata
→ LazyEpubBookHandle.readCoverResource
→ save cover bytes
→ close handle
```

It no longer calls `EpubReader.readBook` during metadata extraction.

Files modified:

- `lib/services/book_metadata_service.dart`
- `test/unit/services/book_metadata_service_lazy_index_test.dart`

Tests added:

- metadata extraction uses lightweight index and cover resource
- malformed EPUB metadata input returns a recoverable null result

Commands run:

```bash
rtk dart format lib/services/book_metadata_service.dart test/unit/services/book_metadata_service_lazy_index_test.dart
rtk flutter test test/unit/services/book_metadata_service_lazy_index_test.dart
rtk flutter analyze
rtk flutter test
```

Results:

```text
metadata targeted tests: passed, 2 tests
rtk flutter analyze: passed
rtk flutter test: passed, 480 tests
```

Android profile import/listing evidence:

Synthetic import-probe:

```text
book=feature_rich_lazy_reader_import_probe.epub
reader_open_route route=lazy
lazy_epub_index_open_end bytes=4783 spineItems=5 manifestItems=7 chapters=4 elapsedMs=16
lazy_reader_index_ready sectionsIndexed=5 elapsedMs=42
lazy_reader_section_ready sectionsParsedBeforeReady=2 chunks=53
range_generation_end inspectedSourceChunks=48 displayChunks=26 elapsedMs=66 maxSliceDurationMs=3
```

Large private-EPUB import-probe:

```text
book=dialogues_plato_import_probe.epub
reader_open_route route=lazy
lazy_epub_index_open_end bytes=2920023 spineItems=36 manifestItems=44 chapters=12 elapsedMs=24
lazy_resource_load_end path=images/cover.jpg mediaType=image/jpeg bytes=344727 elapsedMs=44
lazy_reader_section_ready sectionsParsedBeforeReady=2 chunks=11 elapsedMs=474
range_generation_end inspectedSourceChunks=11 displayChunks=8 elapsedMs=5 maxSliceDurationMs=1
```

No `EpubReader.readBook` event appeared in the successful lazy import-probe
flows. The full legacy route remains available when lazy mode is disabled.

Phase 7 gate result: **passed for local metadata/import extraction**.

Notes:

- EPUB 2 NCX and EPUB 3 navigation behavior are covered by existing
  `LazyEpubIndexService` tests.
- Malformed metadata recovery is covered by the new metadata service test.
- No automatic complete-book background parse was observed in the import-probe
  lazy profile windows; foreground work suppressed background preparse.

## Phase 8 - Regression and rollout decision

Gate status: **not passed / not complete**.

Reason:

The lazy reader remains default-off by design. Although Phase 6 stabilization
and Phase 7 metadata/import extraction have passed the evidence above, the full
legacy-versus-lazy product regression matrix and final rollout decision have
not been completed in this continuation. Lazy mode must therefore remain
disabled by default, with the global kill switch, allow-list, per-book disable,
and legacy fallback retained.

## Phase 9 - Cleanup and production hardening

Gate status: **not started**.

Cleanup is intentionally deferred because Phase 8 has not passed. Temporary
guarded diagnostics still present and to review/remove in Phase 9 include:

- `NALORI_DIAG_OPEN_EPUB`
- `NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR`
- `NALORI_DIAG_CLEAR_PARSED_CACHE_FOR`
- `NALORI_DIAG_FOOTNOTE_BACKLINK`
- `NALORI_DIAG_NAVIGATE_SPINE_SEQUENCE`
- excessive per-phase `NALORI_EPUB_DIAG` logs that are not useful as retained
  guarded diagnostics

## Phase 8 - Final regression and rollout decision

This section supersedes the earlier incomplete Phase 8 note.

### Regression matrix summary

| Fixture | Workflow | Legacy result | Lazy result | Exact context/feature parity | Intentional difference | Android/manual evidence | Pass/fail | Severity if failed |
|---|---|---|---|---|---|---|---|---|
| Feature-rich synthetic EPUB | New-book first location | legacy route opened from cached parsed content | lazy route opened Chapter 1 semantic content | yes | lazy builds from section window | Android profile + fixture tests | Pass | n/a |
| Feature-rich synthetic EPUB | Nested TOC and parts | complete part/chapter panel | complete Part I / Chapters 1-2 / Part II / Chapter 3 targets | yes | lazy targets are stable href/spine locations | targeted tests | Pass | n/a |
| Feature-rich synthetic EPUB | Cross-section link | navigates to target paragraph | loads Chapter 2 on demand and navigates to target paragraph | yes | section is parsed lazily | Phase 6 Android UI evidence + targeted tests | Pass | n/a |
| Feature-rich synthetic EPUB | Footnote forward/backlink | footnote and backlink resolve | `notes.xhtml#note-1` and `chapter-1.xhtml#origin-paragraph` resolve exactly | yes | notes section loads only on tap | Android `diag_footnote_*` evidence from Phase 6 | Pass | n/a |
| Feature-rich synthetic EPUB | Image and table | image/table render in reader | image loaded only with Chapter 1 section; table chunk preserved | yes | resource bytes loaded lazily | resource log + fixture tests | Pass | n/a |
| Feature-rich synthetic EPUB | Bookmark/highlight/note/dictionary/character | legacy records preserved | stable locations resolve exact repeated-context targets | yes | stable anchors are additive | targeted tests + Phase 6 Android evidence | Pass | n/a |
| Feature-rich synthetic EPUB | Speed Read boundary | page text advances | unloaded next section is foreground-loaded and playback continues | yes | boundary may briefly wait for lazy load | widget tests + Phase 6 Android evidence | Pass | n/a |
| Previously read EPUB | Saved position | legacy `lastReadIndex` retained | stable location restores exact context; legacy-only records route legacy until safe | yes | legacy fallback is explicit | force-stop/reopen evidence | Pass | n/a |
| Multi-part EPUB | Previous/Next Chapter | previous/next works by chapter list | previous/next uses TOC stable targets across unloaded parts | yes | lazy does not require loaded chunk mapping | Android large profile + tests | Pass | n/a |
| Plato private EPUB | Large section jumps | legacy can eventually parse full book | lazy jumps to Republic, Laws, final, early and cached Republic sections | yes | lazy retains bounded section window | Android Phase 8 profile | Pass | n/a |
| Plato private EPUB | Backward page/part loading | full parsed content already present | previous unloaded sections parsed or loaded and prepended | yes | localized boundary load | Android Phase 8 profile | Pass | n/a |
| Plato private EPUB | Source equivalence | full parser output | lazy joined 36 spine sections | yes | verification diagnostic only | Phase 6 equivalence | Pass | n/a |
| Plato private EPUB | Tables/images | 28 tables, 3 images | 28 tables, 3 images | yes | resources section-scoped | Phase 6 equivalence | Pass | n/a |
| Generated no-TOC EPUB | Chapter fallback | linear spine fallback | linear spine structural scrubber/fallback | yes | labels are spine-section based | targeted tests | Pass | n/a |
| EPUB 2 NCX fixture | Navigation metadata | NCX chapters available | lazy index reads NCX chapter targets | yes | index-only navigation | LazyEpubIndexService tests | Pass | n/a |
| EPUB 3 nav fixture | Navigation metadata | nav chapters available | lazy index reads EPUB 3 nav targets | yes | index-only navigation | LazyEpubIndexService tests | Pass | n/a |
| Rollout safety | Lazy disabled | `route=legacy` | explicit kill switch still routes legacy | yes | lazy default now enabled; explicit false disables | code + tests | Pass | n/a |
| Rollout safety | Allow-list | n/a | only exact allow-listed book can use lazy when set | yes | operational rollout guard retained | code + tests | Pass | n/a |
| Rollout safety | Per-book disable | n/a | disabled book returns to legacy route | yes | marker is non-destructive | `lazy_reader_route_service_test.dart` | Pass | n/a |

### Android profile evidence

Final large-book Phase 8 run:

```text
Device: 00162352B003164
Build mode: profile
Book: dialogues_plato.epub
Lazy route: enabled
Navigation sequence: 22,30,35,4,22
Chapter actions: next x2, previous x3
Page actions: backward x12, forward x8
```

Key observations:

```text
reader_open_route route=lazy reason=lazy_reader_enabled
lazy_epub_index_open_end bytes=2920023 spineItems=36 manifestItems=44 chapters=12 elapsedMs=20
lazy_reader_section_ready sectionsParsedBeforeReady=2 chunks=7036 elapsedMs=773
initial segmented display cache hit: 30 display chunks, complete=false
republic.xhtml target: retainedSections=2, displayChunks=30, complete=false
laws.xhtml target: lazy_section_cache_miss then section parse; retainedSections=3
uncopyright target: retainedSections=3, displayChunks=7, complete=false
preface-2 target: retainedSections=3, displayChunks=26, complete=false
return to republic.xhtml: retainedSections=3, displayChunks=30, complete=false
next chapter: Timaeus, then Critias
previous chapter: Introduction and Analysis repeated through prior targets
backward ranges: 192 source chunks per request; 136 and 124 display chunks
largest RSS in run: approximately 365 MB
largest range total: 502 ms through 87 slices
maximum uninterrupted layout slice: 8 ms
```

Eviction evidence:

```text
lazy_section_evict spineIndex=22 href=text/republic.xhtml retained=3
lazy_section_evict spineIndex=23 href=text/timaeus.xhtml retained=3
lazy_section_evict spineIndex=30 href=text/laws.xhtml retained=3
lazy_section_evict spineIndex=31 href=text/appendix.xhtml retained=3
lazy_section_evict spineIndex=35 href=text/uncopyright.xhtml retained=3
```

Crash-marker scan:

```text
No FATAL EXCEPTION, AndroidRuntime crash, ANR in, OutOfMemory, am_crash, or
LMKD kill appeared in the final Phase 8/9 windows. Low-memory pressure events
were present but logged as "Not killing" or "Ignoring".
```

Clean Phase 9 profile smoke:

```text
Command: rtk timeout 75 rtk flutter run -d 00162352B003164 --profile
Result: app launched without diagnostic auto-open or auto-navigation flags.
No app-level fatal/ANR/OOM marker appeared in the post-run log scan.
```

### Performance comparison

| Metric | Baseline full-book path | Final lazy/default path | Result |
|---|---:|---:|---|
| Large EPUB full extraction peak RSS | ~893 MB | ~365 MB in final Phase 8 run; ~300-324 MB in repeated-jump run | Pass |
| Time to first readable display after parsed data | ~31.7 s display rebuild | initial lazy segment 51-117 ms once sections available; section ready 773 ms in final large run | Pass |
| Full display chunks generated before ready | ~8,528 | 30-34 in large lazy runs | Pass |
| Full source chunks processed before ready | 20,460 | section-window only; final large run 7,036 loaded source chunks from Republic/Timaeus cache and 48 display-inspected chunks | Pass |
| Maximum display-layout slice | 31-33 s continuous main-isolate rebuild | 8 ms final large run; latest prior maximum 12 ms | Pass |
| Complete display cache rewrite | full one-file cache | skipped for partial; segmented payload writes only | Pass |
| Metadata/import extraction | full EPUB read | lightweight index + cover resource | Pass |

### Rollout decision

Phase 8 gate result: **passed**.

Decision: lazy EPUB reading is enabled by default by changing
`NALORI_ENABLE_LAZY_READER` to default `true`.

Safeguards retained:

- `--dart-define=NALORI_ENABLE_LAZY_READER=false` remains the global kill
  switch.
- `NALORI_LAZY_READER_ONLY_BOOK` remains available for allow-list rollout.
- Per-book lazy disable state remains available.
- Legacy fallback remains available.
- Legacy persisted fields remain in place and are not destructively migrated.

Reasoning:

- No release-blocking lazy-reader regression remained in the Phase 6 and Phase 8
  evidence.
- Chapter/part navigation, backward loading, scrubber, saved-position restore,
  annotations, dictionary/character targets, links/footnotes, Speed Read,
  images, tables, cache reuse, corruption recovery coverage, and memory
  boundedness passed through targeted tests and Android profile/manual evidence.
- Lazy route avoids `EpubReader.readBook` and avoids requiring a complete parsed
  `List<BookChunk>` before reader readiness.

## Phase 9 - Final cleanup and hardening

This section supersedes the earlier Phase 9 not-started note.

### Cleanup performed

Production code removed:

- `NALORI_DIAG_OPEN_EPUB`
- `NALORI_DIAG_CLEAR_DISPLAY_CACHE_FOR`
- `NALORI_DIAG_CLEAR_PARSED_CACHE_FOR`
- `NALORI_DIAG_NAVIGATE_ORIGINAL_INDEX`
- `NALORI_DIAG_NAVIGATE_SPINE_INDEX`
- `NALORI_DIAG_NAVIGATE_SPINE_SEQUENCE`
- `NALORI_DIAG_ANNOTATION_PARITY`
- `NALORI_DIAG_SPEED_READ_BOUNDARY`
- `NALORI_DIAG_INTERNAL_LINK_PARITY`
- `NALORI_DIAG_FOOTNOTE_BACKLINK`
- `NALORI_DIAG_EXPECT_FOOTNOTE_TEXT`
- `NALORI_DIAG_EXPECT_BACKLINK_TEXT`
- `NALORI_DIAG_AUTO_NEXT_CHAPTERS`
- `NALORI_DIAG_AUTO_PREV_CHAPTERS`
- `NALORI_DIAG_AUTO_FORWARD_PAGES`
- `NALORI_DIAG_AUTO_BACKWARD_PAGES`
- `NALORI_DIAG_SWITCH_LAYOUT_SIGNATURE`
- diagnostic startup open, display-cache clear, and parsed-cache clear hooks
- diagnostic auto-navigation, annotation-record creation, footnote/backlink
  automation, speed-read automation, internal-link automation, and layout-switch
  automation in `ReaderScreen`
- untracked raw Android Logcat artifacts
  `nalori_large_epub_android_profile_internal_logcat.log` and
  `nalori_large_epub_android_profile_logcat.log`

Search verification:

```text
rg "/home/uttam|Dialogues -- Plato|dialogues_plato|NALORI_DIAG_" lib test tool pubspec.yaml
→ no matches

rg "NALORI_DIAG_|diag_auto|diag_annotation|diag_speed_read|diag_footnote|diag_internal_link|diag_layout_switch|Diagnostic" lib
→ no matches
```

Diagnostics intentionally retained:

- `NALORI_EPUB_DIAG` guarded high-level route, cache, parse, cancellation, and
  severe performance logging.
- `reader_open_route` including fallback/route reason.
- section cache hit/miss/corruption logging.
- display generation cancellation and range timing logging.
- lazy section parse/resource-load failure logging.

Production hardening retained:

- Global kill switch.
- Allow-list.
- Per-book disable marker.
- Legacy fallback.
- Legacy persisted annotation/location fields.
- Section/display cache versioning and atomic segmented writes.
- Parsed-section cache versioning and per-section recovery.

Private fixture check:

```text
rtk sha256sum 'Dialogues -- Plato.epub'
8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d
```

The private EPUB remains untracked and was not committed.

### Final verification

Commands:

```bash
rtk dart format lib/screens/book_loading_screen.dart lib/screens/home_screen.dart lib/screens/reader_screen.dart
rtk flutter analyze
rtk flutter test
rtk timeout 75 rtk flutter run -d 00162352B003164 --profile
rtk sha256sum 'Dialogues -- Plato.epub'
```

Results:

```text
rtk flutter analyze: passed
rtk flutter test: passed, 480 tests
clean Android profile smoke: launched; no fatal/ANR/OOM/am_crash marker
private EPUB checksum: unchanged
```

Phase 9 gate result: **passed**.

## Final outcome

Large-EPUB reliability issue: **fixed with high confidence**.

The main root cause was the legacy reader path requiring full-book parsed
content and then performing complete display pagination on the main Flutter
isolate before the reader was usable. Nalori now has a lazy section-level EPUB
reader, parsed-section cache, segmented display cache, progressive display
state, frame-budgeted range generation, and bounded foreground/background
scheduling.

Remaining technical debt:

| Severity | Item | Rationale |
|---|---|---|
| Medium | Legacy full parsed-reader path remains | Required for fallback and legacy-only saved-position safety; remove only after more production telemetry. |
| Medium | `NALORI_EPUB_DIAG` logs are still verbose when enabled | Guarded and off by default, but should be sampled or routed through structured telemetry before broader release diagnostics. |
| Low | Lazy default rollout should monitor rare EPUB structures | Synthetic, EPUB 2/3, no-TOC, large, image/table/footnote fixtures passed, but the EPUB ecosystem is broad. |
| Low | Exact global display page entry remains inherently approximate until full pagination exists | Structural scrubber is the intended partial-pagination behavior. |
