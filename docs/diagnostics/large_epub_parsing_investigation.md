# Large EPUB Parsing Investigation

## 1. Executive Conclusion

**Confirmed:** the profile-mode Android run did not fail inside `epubx`, HTML parsing, DOM traversal, table handling, or cache writing. The expensive user-visible stall is `ReaderScreen._rebuildDisplayChunks` in `lib/screens/reader_screen.dart`, which runs on the main Flutter isolate after parsing and spent 31.7 s rebuilding display chunks for 20,460 parsed chunks. A second rebuild for the same book also took 31.1 s. **Highly likely:** debug-mode overhead makes this main-isolate display rebuild appear frozen and can trigger an Android input-dispatch ANR; `dumpsys activity lastanr` had a prior Nalori ANR for `Input dispatching timed out`. **Confirmed but not the termination cause in the instrumented profile run:** full-book parsing creates heavy memory pressure, peaking at about 893 MB RSS during content extraction. There was no current evidence of `OutOfMemoryError`, LMKD killing Nalori, a native crash, or a parser loop in the profile reproduction.

## 2. Reproduction Details

- Source fixture: `/home/uttam/Desktop/Antigravity Projects/Nalori/Dialogues -- Plato.epub`
- Android test copy: `/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub`
- SHA-256: `8436f8b96e3ae60a96e3e8c210e678f4439b032465aa7dfae83f4995db1b6a9d`
- Device: `A059`, Android 16 / API 36, package `com.nalori.reader`
- Build mode measured: `flutter run --profile`
- Diagnostic command:

```bash
rtk flutter run --profile -d 00162352B003164 \
  --dart-define=NALORI_EPUB_DIAG=true \
  --dart-define=NALORI_DIAG_OPEN_EPUB=/data/user/0/com.nalori.reader/app_flutter/books/dialogues_plato.epub
```

- Result: profile mode completed parse, cache, reader open, and display rebuild without debugger disconnect.
- Time to usable reader layout: about 42 s from parse start, dominated by display rebuild after parse.
- Debug mode: not rerun after profile evidence; the previous non-instrumented failure and `lastanr` are consistent with debug overhead on the confirmed main-isolate rebuild.

## 3. Current Pipeline

```text
Book import/open
  -> BookImportService.importBook
     lib/services/book_import_service.dart
  -> BookListScreen._importBook / _openBook
     lib/screens/book_list_screen.dart
  -> BookMetadataService.extractAndCacheMetadata
     lib/services/book_metadata_service.dart
     reads File.readAsBytes() and EpubReader.readBook(bytes) on caller isolate during metadata extraction
  -> BookLoadingScreen._loadAndParse
     lib/screens/book_loading_screen.dart
  -> BookPreparseService.ensureParsed
     lib/services/book_preparse_service.dart
     cache lookup, in-flight dedupe, parse scheduling
  -> EpubParserService.parseFileInBackground
     lib/services/epub_parser.dart
     File.readAsBytes() on main isolate, sends 2.92 MB Uint8List to Isolate.run
  -> EpubParserService._parseBytes
     background isolate, EpubReader.readBook(bytes)
  -> epubx EpubReader.readBook
     packages/epubx/lib/src/epub_reader.dart
     openBook -> readContent -> readCover -> getChapters -> readChapters
  -> EpubParserService._extractContent
     iterates book.Content.Html, parses each HTML string, prescans footnotes, traverses DOM, handles tables/images/anchors, normalizes text, creates BookChunk list
  -> BookCacheService.cacheBook
     lib/services/book_cache_service.dart
     builds full JSON map, jsonEncode + gzip in isolate, writes one .json.gz
  -> ReaderScreen._ensureDisplayChunksBuilt / _loadOrRebuildDisplayChunks
     lib/screens/reader_screen.dart
  -> ReaderScreen._rebuildDisplayChunks
     main isolate, lays out/splits all parsed chunks into display chunks, then writes display cache
```

`parseFileInBackground` does move `EpubReader.readBook`, HTML parsing, DOM traversal, chunk generation, and parsed-book serialization work off the main isolate. `File.readAsBytes()` still happens on the main isolate, but it took only 13 ms for this fixture. Reader display rebuild and display cache orchestration run on the main isolate.

## 4. EPUB Structural Analysis

| Metric | Problem EPUB | Working control EPUB |
|---|---:|---:|
| Compressed size | 2,920,023 bytes | 1,860 bytes |
| Total uncompressed size | 9,573,982 bytes | 1,294 bytes |
| Compression ratio | 3.28x | 0.70x |
| File entries | 48 | 8 |
| XHTML/HTML/XML files | 39 | 3 |
| Images | 3 | 0 |
| Fonts | 0 | 0 |
| CSS files | 3 | 0 |
| SVG files | 0 | 0 |
| OPF package path | `epub/content.opf` | `EPUB/content.opf` |
| Spine items | 36 | 1 |
| TOC/nav items | 137 | 1 |
| Total XHTML/HTML/XML size | 9,089,083 bytes | 719 bytes |
| Total image size | 421,563 bytes | 0 |
| Largest image | 344,727 bytes | 0 |
| Largest XHTML | `epub/text/laws.xhtml`, 1,725,278 bytes | 350 bytes |
| Table count estimate | 28 | 1 |
| DOM node estimate | 105,554 | 32 |
| Nalori parsed chunks | 20,460 | 4 |
| Host Nalori parse duration | 3,271 ms | 19 ms |
| Android profile display rebuild | 31,719 ms | not run |

Archive validation found no missing spine refs, duplicate spine paths, repeated spine documents, malformed ZIP, cyclic nav pattern, zip-bomb indicator, huge base64 inline resource, fonts, SVG payload, or unusually large image resource. The book is unusual because it is mostly text XHTML: about 9.1 MB of HTML, especially `laws.xhtml` and `republic.xhtml`.

Largest/high-impact sections:

- `epub/text/laws.xhtml`: 1,725,278 archive bytes; Android parse chapter line reported 1,715,952 HTML chars, 6,397 nodes, 12 tables, 555,411 extracted text chars, 2,560 chunks.
- `epub/text/republic.xhtml`: 1,324,895 archive bytes; Android parse chapter line reported 1,316,166 HTML chars, 17,593 nodes, 1,181,473 extracted text chars, 7,328 chunks.

## 5. Timeline

| Time | Event |
|---|---|
| 02:16:59.970 | `parse_file_background_begin`, main isolate, RSS 482,738,176 |
| 02:16:59.984 | `read_as_bytes_end`, 13 ms, bytes sent to isolate: 2,920,023 |
| 02:16:59.993 | `EpubReader.readBook` starts in `_RemoteRunner._remoteExecute` |
| 02:17:03.532 | `EpubReader.readBook` ends, 3,539 ms |
| 02:17:03.533 | Nalori content extraction begins |
| 02:17:06.332 | `laws.xhtml` ends, 598 ms, RSS 824,971,264 |
| 02:17:07.588 | `republic.xhtml` ends, 346 ms, RSS 874,237,952 |
| 02:17:08.100 | extraction ends, 4,567 ms, RSS 892,887,040, chunks 20,460 |
| 02:17:09.700 | reader display rebuild begins on main isolate |
| 02:17:41.419 | reader display rebuild ends, 31,719 ms, display chunks 8,528 |
| 02:17:42.021 | display cache write ends |
| 02:19:08.647 | second display rebuild begins after settings/layout change |
| 02:19:39.717 | second display rebuild ends, 31,069 ms |

## 6. Performance Measurements

| Phase | Duration | Memory before | Peak/after | Main isolate? | Result |
|---|---:|---:|---:|---|---|
| File `readAsBytes` | 13 ms | 482.7 MB RSS | 473.1 MB RSS | yes | OK |
| Isolate message send | immediate | 473.1 MB RSS | 2.92 MB payload | yes | OK |
| `EpubReader.readBook` | 3,539 ms | 476.1 MB RSS | 488.4 MB RSS | no | OK |
| Nalori HTML extraction/traversal/chunking | 4,567 ms | 488.4 MB RSS | 892.9 MB RSS | no | OK, high memory |
| Parsed cache serialization | 1,060 ms | 812.3 MB RSS | 314.6 MB RSS after | awaited on main, work in isolate | OK |
| Parsed cache write | 7 ms | n/a | 2,887,784 bytes | main async file write | OK |
| Reader display rebuild generation 1 | 31,719 ms | 281.5 MB RSS | 392.4 MB RSS | yes | UI stall |
| Display cache serialization | 591 ms | 392.9 MB RSS | 413.2 MB RSS | awaited on main, work in isolate | OK |
| Display cache write | 8 ms | n/a | 3,201,875 bytes | main async file write | OK |
| Reader display rebuild generation 2 | 31,069 ms | 306.8 MB RSS | 389.5 MB RSS | yes | repeated UI stall |

## 7. Termination Evidence

The instrumented profile run did not terminate unexpectedly. Searches in the profile log did not find a current Nalori `OutOfMemoryError`, `FATAL EXCEPTION`, `Fatal signal`, `SIGSEGV`, `ANR in`, or LMKD kill of `com.nalori.reader`. There were low-memory pressure events, but they say `Not killing`, and the only Nalori kill was the explicit stop when `flutter run` was quit:

```text
ActivityManager: Killing 8392:com.nalori.reader ... stop com.nalori.reader due to from pid ...
```

`dumpsys activity lastanr` contained a prior Nalori ANR on the same device:

```text
ANR time: 7 Jun 2026 01:47:57
Reason: Input dispatching timed out (... com.nalori.reader.MainActivity is not responding. Waited 5000ms for FocusEvent(hasFocus=true)).
```

That ANR was not from the instrumented profile run, so it is corroborating evidence for UI isolate unresponsiveness, not a fresh captured crash. The observed `Signal Catcher reacting to signal 3` lines are stack-dump symptoms and are not sufficient to identify the root cause.

## 8. Root-Cause Chain

The confirmed chain for the slow/stuck loading behavior is:

```text
Dialogues opens with no parsed/display cache
-> parse runs in background isolate and succeeds
-> Nalori creates 20,460 parsed chunks from 9.1 MB of XHTML text
-> ReaderScreen receives the complete parsed result
-> display cache miss
-> ReaderScreen._rebuildDisplayChunks lays out/splits all 20,460 chunks on the main isolate
-> the rebuild takes about 31 seconds per generation
-> loading/rebuild UI appears stuck and is vulnerable to debug-mode ANR/disconnect
```

The confirmed memory-pressure chain is:

```text
compressed bytes
-> epubx eagerly decodes full archive/content via readBook
-> EpubBook retains full HTML strings and resource bytes
-> Nalori parses HTML into transient DOM nodes and creates extracted text/chunks/anchors
-> cache serialization creates complete JSON/gzip buffers
-> Android RSS reaches about 893 MB during extraction
```

This memory chain is expensive, but it did not produce an OOM/LMKD/native crash in the profile reproduction.

## 9. Specific Trigger Inside The EPUB

No malformed/cyclic EPUB structure was identified. The trigger is aggregate text size and generated chunk volume, with `republic.xhtml` and `laws.xhtml` the largest contributors:

- `text/republic.xhtml`: 7,328 chunks from one section, 1,181,473 extracted text chars, 17,593 nodes.
- `text/laws.xhtml`: largest source file, 2,560 chunks, 12 tables, 555,411 extracted text chars.

The exact slow phase is not one of those chapters alone; it is the full-book display pagination/layout pass over the resulting 20,460 chunks.

## 10. Ranked Causes

| Rank | Cause | Classification | Evidence |
|---:|---|---|---|
| 1 | Main Flutter isolate occupied by full reader display rebuild | Confirmed | `_rebuildDisplayChunks` generation 1: 31,719 ms; generation 2: 31,069 ms; `isolate=main` |
| 2 | Excessive card/display generation for a large text book | Confirmed | 20,460 parsed chunks, 8,528/8,643 display chunks |
| 3 | `epubx.readBook` eagerly loads complete decompressed content | Confirmed | `epub_reader.dart` documents `readBook()` loads all data; lines 90-103 read all HTML/CSS/images/fonts; lines 130-162 read text/byte content |
| 4 | Nalori retains multiple full-book representations during parse/cache/open | Confirmed | bytes, `EpubBook`, HTML strings, transient DOM, chunks, JSON/gzip buffers, display chunks |
| 5 | Very large XHTML/spine items | Confirmed | `laws.xhtml` 1.7 MB, `republic.xhtml` 1.3 MB; no duplicate spine refs |
| 6 | Debug-mode overhead turning slow valid work into debugger disconnect/ANR | Highly likely | profile completes; prior `lastanr` is input-dispatch timeout; debug is slower |
| 7 | OOM or LMKD kill | Possible, not reproduced | RSS peaks high; profile log has low-memory pressure but no Nalori kill/OOM |
| 8 | Repeated duplicate work | Partially confirmed | Dialogues was not parsed twice, but display rebuild ran twice and preparse queue parsed other books while reader work was active |
| 9 | Table/pathological HTML traversal | Ruled out for current run | tables present, but chapter traversal completes in hundreds of ms |
| 10 | Native/library crash | Ruled out for current run | no fatal signal/crash-buffer evidence |
| 11 | Malformed/cyclic EPUB navigation/content refs | Ruled out | no missing/duplicate spine paths or suspicious cycles in archive diagnostics |
| 12 | Zip bomb or large embedded images/fonts/SVG | Ruled out | 9.57 MB uncompressed, 3.28x ratio, 3 images, no fonts/SVG |

## 11. Minimal Immediate Fix

The smallest safe fix is to stop doing a complete full-book display rebuild before the reader becomes usable. Build only the initial visible window plus bounded lookahead on the main isolate, show the reader, and continue pagination/display-cache generation incrementally with cancellation and real progress. Also pause or deprioritize `BookPreparseService.queueBooks` while the current book is opening or rebuilding display chunks, because it can add background CPU/memory pressure during the same user-visible operation.

Do not skip content, weaken table handling, or increase heap size. The content is parseable; the immediate problem is unbounded front-loaded display layout.

## 12. Proper Architectural Fix

Nalori should eventually move to per-section work:

- lazy spine/resource extraction instead of requiring full `EpubBook` for reading;
- per-section parsing and per-section cache records;
- bounded lookahead display pagination;
- cancellation/resume for parse and display rebuilds;
- isolate-based parsing for EPUB/HTML/chunk generation, with smaller isolate messages;
- import metadata extraction that does not call full `EpubReader.readBook` on the main isolate;
- incremental serialization instead of whole-book JSON payloads;
- memory limits for images/resources and cache buffers;
- progress tied to real parse/layout phases;
- background preparse throttling while a foreground book is opening.

## 13. Regression Test Plan

- Keep this EPUB as a local private diagnostic fixture identified by SHA-256, without modifying it.
- Add a legally safe generated stress EPUB with about 9 MB XHTML, 35-40 spine items, one 1.5-2 MB XHTML, tables/anchors/footnotes, and 20k-ish generated chunks.
- Add parser diagnostics that assert no missing/duplicate spine refs and no repeated parse run for one open.
- Add a display rebuild benchmark or integration test proving first visible reader content appears without waiting for complete-book display pagination.
- Add cache serialization tests for payload size and no restart loop on cache write failure.
- Add a queue test proving background preparse is paused or throttled during foreground open.

## 14. Files Changed For Diagnostics

Temporary instrumentation:

- `lib/services/epub_parser.dart`: guarded `NALORI_EPUB_DIAG` phase logging, run IDs, RSS/isolate reporting, per-chapter aggregate metrics.
- `lib/services/book_cache_service.dart`: guarded parsed/display cache serialization and write metrics.
- `lib/screens/reader_screen.dart`: guarded display-cache load/rebuild metrics and 5-second progress logs.
- `lib/screens/home_screen.dart`: guarded `NALORI_DIAG_OPEN_EPUB` startup hook for direct Android reproduction.

Diagnostic artifacts:

- `docs/diagnostics/epub_archive_diagnostics.py`
- `docs/diagnostics/large_epub_archive_metrics.json`
- `docs/diagnostics/large_epub_parser_diagnostic.dart`
- `docs/diagnostics/large_epub_parser_diagnostic.log`
- `docs/diagnostics/nalori_large_epub_android_profile_logcat.log`
- `docs/diagnostics/nalori_large_epub_android_profile_internal_logcat.log`
- `docs/diagnostics/large_epub_parsing_investigation.md`

The instrumentation is deliberately guarded by `--dart-define=NALORI_EPUB_DIAG=true` and should be removed or converted to a permanent debug logger after the fix is implemented.
