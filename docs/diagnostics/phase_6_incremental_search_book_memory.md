# Phase 6 — Incremental Search and Book Memory

Status: implementation complete; host verification complete except for tests
that require the unavailable host `libsqlite3.so` and the final physical-device
matrix.

## Architecture found before Phase 6

The lazy reader already had the correct lower layers:

- `LazyEpubIndexService` owns the persistent publication/spine structure and
  publication fingerprint.
- `LazySectionRepository` and `ParsedSectionCacheService` parse and cache one
  authoritative source section at a time. The parser emits stable logical
  paragraph IDs and paragraph-relative UTF-16 coordinates.
- `LazyBookSession.resolveStableLocation` validates publication/section source
  identity, loads an unloaded section, and prepares a bounded lazy window.
- Reader display cards are disposable projections of source chunks. Existing
  navigation-generation and display-publication coordinators prevent stale
  windows/cards from publishing.

The two remaining legacy consumers were:

- `SearchScreen`, which searched only `ReaderScreen._sourceChunks` and returned
  an integer window chunk index.
- `BookMemoryService`, which explicitly prepared or loaded whole-book
  `CachedBook.chunks`/`chapters` and scanned those mutable global chunk indexes
  for character occurrences.

Book Memory “Go to Text” opened `BookLoadingScreen` with a legacy whole-book
chunk index. Lazy open selected the saved checkpoint/window instead, so that
integer often did not identify anything in the loaded window.

## Root causes

1. A search result's identity was a mutable reader-window chunk index, not a
   source identity.
2. The preview retained only a snippet-local match offset. The authoritative
   source UTF-16 range was discarded.
3. Search could not see unloaded sections because its input was
   `_sourceChunks`.
4. Book Memory character moments persisted only legacy chunk/offset fields.
5. Book Memory explicit navigation did not take precedence over checkpoint
   restore during lazy open.
6. Split logical paragraphs and display-card reflow made a display/card index
   inherently unsuitable as persistent result identity.

## Final ownership and data flow

```text
EPUB source
  -> structural index + authoritative lazy parsed sections
  -> versioned persistent derived paragraph segments
  -> progressive search / Book Memory character occurrences
  -> StableBookLocation + DerivedSourceRange
  -> existing stable-location resolver
  -> existing lazy source window, pagination and display-card projection
```

The derived index is not a reader, paginator, checkpoint store, or display-card
authority. It never publishes a reader window and never updates current reader
location. `LazyBookSession.loadSectionForDerivedIndex` schedules section work at
`LazySectionWorkPriority.derivedIndexing` and deliberately does not add the
section to the reader's loaded-section set.

## Index format, ownership and invalidation

The index lives under application support in `derived_book_index_v1`, with one
hashed directory per book. Its schema is owned solely by
`DerivedBookIndexStore`:

- derived schema: `1`;
- search normalization schema: `1`;
- source parser identity: `section_v3` (read as an input; the parsed-source
  schema was not changed);
- independent default disk budget: 64 MiB.

Each manifest records book ID, EPUB publication fingerprint, parser version,
normalization version, generation, total readable section count, indexed
section records, completion state and access timestamps. Each section record
contains spine/href/source checksum, file checksum, byte size, paragraph count
and generation.

Each validated section segment contains normalized logical paragraphs from the
existing parser. A paragraph stores:

- stable logical-paragraph ID;
- authoritative source text and paragraph checksum;
- canonical Unicode/case-folded search text;
- deterministic normalized-code-unit to original UTF-16 start/end maps;
- source chunk segments with paragraph-relative coordinates;
- section/spine/href, source checksum, parser version and publication
  fingerprint.

Segment bytes are checksum-validated before use. A segment temporary file is
flushed and renamed before its record is atomically added to the manifest.
Missing, partial, malformed or checksum-invalid segments become resumable cache
misses. A stale generation cannot publish. Cancellation/owner loss increments
the owner generation, preventing an in-flight parse from publishing.

Fingerprint, parser, normalization, schema or readable-section-count mismatch
starts a new generation. A previously complete manifest is retained as
`previous_manifest.json` during replacement construction and is removed only
after a complete validated replacement publishes. First builds expose only
individually validated partial segments. Derived eviction is coordinated with
book deletion/reset, but does not modify the 192 MiB parsed-source or 48 MiB
display-layout budgets.

## 6A — Incremental derived-index foundation

Complete.

- Added persistent manifest/segment models and JSON round trips.
- Added section-to-logical-paragraph construction using existing parser output.
- Added Unicode normalization with exact original UTF-16 range maps.
- Added atomic partial publication, checksum recovery, resume, generation
  rejection, replacement preservation and independent LRU-style budget
  eviction.
- Added low-priority incremental scheduling, bounded source retention,
  cancellation and owner-generation publication checks.
- Added derived cleanup to the coordinated reader derivative deletion/reset.

## 6B — Reliable full-book search

Complete.

- `SearchScreen` consumes already indexed segments immediately, displays
  indexed percentage/full-book state, listens for new segments, and reruns only
  the latest query.
- Indexing continues at low priority without moving the current reader card.
- Exact normalized phrase occurrences rank before the token-based weaker
  fallback; results are deterministically sorted and deduplicated by stable
  source identity/range.
- Preview construction retains the exact authoritative paragraph range.
- Current-window compatibility remains available, but it emits a
  `DerivedSourceRange` built from the chunk's stable location. A result without
  a stable location is not offered as a broken integer navigation target.
- Existing annotation categories remain in their existing panels. Their stable
  locations are preserved and Book Memory source previews now use the same
  source-range navigation carrier.

## 6C — Exact Go to Text

Complete.

- Search selection returns `DerivedSourceRange`, never a card/window index.
- Reader selection validates book, fingerprint and derived generation, then
  invokes `_navigateToStableLocation`.
- The existing resolver loads only the target section, verifies source/parser
  identity, supports logical-paragraph identity as an additional stable source
  anchor, and retains its existing context/progression fallbacks.
- The source range's first source chunk/offset selects the exact display card
  after pagination. Existing navigation/display generations suppress rapid
  stale selections and stale pagination.
- A transient in-memory emphasis is projected from paragraph UTF-16 ranges
  across all source chunks/display cards touched by the match. It expires after
  five seconds or when another target starts. No `HighlightService` write or
  `Highlight` record creation occurs.
- Search resolution does not commit the previous page merely because an
  off-window target is being prepared. Normal settled-page handling remains the
  authority after the actual jump.
- Book Memory explicit targets take precedence over saved checkpoint restore;
  lazy open does not rewrite the stored last-read location or inject the old
  checkpoint for that explicit navigation.

## 6D — Incremental Book Memory

Complete.

- Production Book Memory no longer calls eager whole-book preparation when a
  book file is available. It opens the lightweight lazy structure, publishes at
  least one validated segment, then continues the shared persistent build in
  the background.
- The screen displays derived indexed coverage and refreshes while preparation
  is partial. Reopening resumes the manifest's remaining sections.
- Character occurrence scans consume derived logical paragraphs and persist a
  backward-compatible stable `DerivedSourceRange` on first/last moments.
- Stable source IDs plus per-coverage source signatures prevent duplicate
  moments on refresh/resume.
- Bookmarks, highlights, notes, words and character moments carry stable
  source-range targets into `BookLoadingScreen` and the same resolver.
- User-created annotations and Book Memory writing remain in their existing
  services and are never removed or replaced by partial/corrupt derived state.
- Injected legacy preparation and no-file `CachedBook` reads remain as explicit
  compatibility paths for tests/legacy callers until parser retirement.

## Verification evidence

Baseline before edits:

- `flutter test` for Book Memory, lazy session and source projection: 48 passed.

Phase 6 focused command (excluding the host SQLite-dependent reader-open file):

- derived index/search/navigation/Book Memory, cleanup, lazy session, source
  projection and Book Memory widgets: 73 passed.
- focused derived-index suite alone: 13 passed.
- `flutter analyze`: no issues.
- `git diff --check`: passed with no output.

The isolated `reader_open_service_test.dart` could not run in this host because
`sqflite_common_ffi` could not load `libsqlite3.so`. The first two cases surface
the same checkpoint-store open failure as `ReaderOpenException`; the checkpoint
case reports the missing dynamic library directly. This is an environment
blocker, not recorded as a pass.

The full Flutter suite was not run after the isolated reader-open suite proved
that this host lacks `libsqlite3.so`; it is not recorded as a pass. No dependency
was installed because dependency/environment changes are outside this phase.

## Remaining limitations and follow-up

- Host tests cannot reproduce device filesystem rename latency, low-storage
  callbacks, process death during a flush, or real PageView/frame settlement.
- Giant-XHTML subdivision remains deliberately out of scope; one very large
  spine section is still the unit of parse/index work.
- Legacy annotations that never acquired a stable location remain compatibility
  hints; they are not allowed to reintroduce integer-only search navigation.
- The separate legacy-parser/cache retirement remains Phase 7 work.
- Physical-device verification is still required for off-window selection,
  rapid selection cancellation, orientation/typography reflow and real storage
  pressure.
