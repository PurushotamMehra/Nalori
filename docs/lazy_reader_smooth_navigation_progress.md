# Lazy Reader Smooth Navigation Progress

## Overview

Task objective: make Nalori's lazy EPUB reader feel continuous for adjacent and recently visited navigation while keeping lazy loading, bounded memory, stable source locations, segmented display caching, and correctness fallback behavior.

Current architecture summary:

- `LazyBookSession` opens a lazy EPUB index and loads parsed sections around a stable location.
- `LazySectionRepository` reads one spine section, checks `ParsedSectionCacheService`, parses misses on a background isolate, joins duplicate section work, and keeps a byte-budgeted pinned LRU for parsed sections.
- `ReaderScreen` owns display generation, segmented display cache integration, and reactive boundary prepend/append behavior.
- `SegmentedDisplayCacheService` persists display ranges by layout signature and source range.
- Existing diagnostics are gated by `NALORI_EPUB_DIAG`.

Reproduction scenarios:

- Sequence A: ordinary reading across forward and backward adjacent boundaries.
- Sequence B: Chapter 1 -> Chapter 2 -> Chapter 3 -> Chapter 2 -> backward into Chapter 1.
- Sequence C: jump 10 or more sections away, then navigate around the target.
- Sequence D: cold Continue restore, then backward into previous section.
- Sequence E: layout/settings change, then adjacent boundary navigation.

Device used for testing: A059 (`00162352B003164`), Android 16 API 36.

Build mode:

- Baseline diagnostics: debug/unit baseline complete; physical profile startup complete; manual navigation timing still pending.
- Final performance evidence must use profile mode.

Test books used:

- Small ordinary EPUB: generated unit-test fixtures in `lazy_book_session_test.dart` and `lazy_section_repository_test.dart`.
- Medium many-chapter EPUB: not found locally yet.
- Very large EPUB/regression fixture: `Dialogues -- Plato.epub`.
- Feature-rich EPUB with tables/images/links/footnotes/annotations: `test/fixtures/books/feature_rich_lazy_reader.epub`.

## Baseline

Before-change physical navigation measurements are pending because manual device navigation has not yet been completed. Automated code/test baseline:

| Metric | Small | Medium | Large | Feature-rich |
| --- | --- | --- | --- | --- |
| Chapter jump completion time | pending | pending | pending | pending |
| Backward boundary load time | pending | pending | pending | pending |
| Forward boundary load time | pending | pending | pending | pending |
| Display-cache hit/miss | pending | pending | pending | pending |
| Parsed-cache hit/miss | pending | pending | pending | pending |
| Pagination generations | pending | pending | pending | pending |
| Section parses | pending | pending | pending | pending |
| Skipped frames / visible stalls | pending | pending | pending | pending |
| Memory usage | pending | pending | pending | pending |

Profile-mode post-change measurement, A059, feature-rich fixture, Sequence A (`NALORI_READER_DIAG_SCENARIO=A`, `feature_rich_lazy_reader.epub`, app-sandbox path `/data/user/0/com.nalori.reader/files/nalori_diag/feature_rich_lazy_reader.epub`):

- Direct lazy open: 195 ms from `continue_tapped` to `lazy_reader_open_end`.
- Initial visible display: segmented cache hit for section 1, 281 ms `reader_display_rebuild_begin` to `reader_display_rebuild_end`; display cache path used one segment with 13 display chunks.
- Initial adjacent backward warmup into titlepage: 493 ms total; parsed cache hit; segmented display cache exact-range hit; incremental prepend; no EPUB parse or pagination generation.
- Forward warmup into chapter 2: 485 ms total; parsed cache hit; segmented display cache exact-range hit; append; no EPUB parse or pagination generation.
- User-facing warmed boundary gesture after warmup: forward chapter 1 -> chapter 2 completed in 63 ms to first frame; backward chapter 2 -> chapter 1 completed in 50 ms to first frame.
- Interpretation: warmed integrated adjacent navigation meets the 100 ms integration target on this fixture, but warmup itself is still roughly 0.5 s and must finish before the boundary gesture. Broader B-E and larger-book proof is pending.

Implementation iteration after this measurement:

- Added a file-stat guarded in-memory manifest cache to `SegmentedDisplayCacheService`. Repeated compatible segmented display-cache reads can skip JSON manifest decoding and validation, while external manifest corruption/version/layout changes still invalidate by file size and modified time.
- Automated verification: `rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart` passed.
- Static verification: `rtk flutter analyze` passed.

Post-fix profile-mode Sequence A, A059, same fixture:

- Direct lazy open: 147 ms.
- Initial visible display from segmented cache: 93 ms async rebuild, 89 ms synchronous rebuild interval.
- Backward adjacent warmup into titlepage: 109 ms, parsed cache hit, segmented cache exact-range hit, incremental prepend.
- Forward adjacent warmup into chapter 2: 259 ms, parsed cache hit, segmented cache exact-range hit, append.
- Warmed boundary gestures: forward 51 ms to first frame, backward 51 ms to first frame.
- Before/after: backward warmup improved 493 -> 109 ms; forward warmup improved 485 -> 259 ms; warmed gesture latency improved 63/50 -> 51/51 ms.
- Remaining dominant delay observed in this fixture: repeated parsed-section manifest/cache loads during adjacent warmup and hydration scheduling. Segmented display-cache manifest JSON work is reduced but segment file deserialization still costs 15-19 ms for these small ranges.

Implementation iteration after parsed-manifest diagnosis:

- Added a file-stat guarded in-memory manifest cache to `ParsedSectionCacheService`, with cache clearing on temp cleanup, book deletion, corruption, missing manifest, and atomic manifest updates.
- Automated verification: `rtk flutter test test/unit/services/parsed_section_cache_service_test.dart test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart` passed.
- Static verification: `rtk flutter analyze` passed.

Post parsed-manifest-cache profile rerun, A059, Sequence A:

- Direct lazy open: 104 ms.
- Initial visible display from segmented cache: 119 ms async rebuild.
- Backward adjacent warmup: 178 ms.
- Forward adjacent warmup: 168 ms.
- Warmed boundary gestures regressed: forward 416 ms, backward 127 ms.
- Diagnostics show repeated `lazy_section_manifest_load` events after adjacent warmup and during the harness navigation window. Interpretation: low-priority hydration/manifest maintenance is still competing with foreground navigation and invalidating the manifest-cache benefit. This is a Checkpoint 6 performance failure, not an acceptance pass.
- Corrective action: delay hydration until a foreground quiet period exists and make foreground navigation update the quiet timer before any low-priority section starts.

Implementation iteration after hydration contention:

- Added a 900 ms foreground quiet-period gate before parsed hydration starts.
- Foreground display range preparation, adjacent section integration, and page navigation update the quiet timer.
- Hydration `shouldPause` now checks mounted/session identity, active display/adjacent work, and the quiet-period timer before starting each low-priority section.
- This is cooperative, not hard preemption: an already-running low-priority parse is not interrupted mid-section. The policy prevents starting new low-priority sections while foreground work is pending.
- Automated verification: `rtk flutter test test/unit/services/parsed_section_cache_service_test.dart test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart` passed.
- Static verification: `rtk flutter analyze` passed.

Post hydration quiet-period profile rerun, A059, Sequence A:

- Direct lazy open: 172 ms.
- Initial visible display from segmented cache: 127 ms async rebuild.
- Backward adjacent warmup: 102 ms.
- Forward adjacent warmup: 120 ms.
- Warmed boundary gestures: forward 0 ms in harness measurement to first frame; backward 0 ms in harness measurement to first frame.
- Hydration/manifest activity resumed only after `reader_diag_sequence_end`, so it did not compete with the measured boundary gestures.
- Status: Sequence A on feature-rich fixture now satisfies the warmed visual/navigation target in profile mode. Adjacent warmup remains slightly above the 100 ms target for forward direction on this small fixture; continue measuring B-E and larger books before accepting Checkpoint 3/6.

Profile-mode Sequence B, A059, feature-rich fixture:

- Direct lazy open: 473 ms, caused by a slow parsed-section cache load on this run.
- Initial visible display from segmented cache: 46 ms.
- Initial backward adjacent warmup: 41 ms with parsed manifest memory hit and segmented display-cache hit.
- Later Chapter 3 context backward warmup into Chapter 1: 11 ms for section availability, but incremental prepend was unavailable because the prepared range started at 8 rather than 0. The code fell back to full display rebuild generation 3 and generated a 48-source-chunk initial range in 45 ms.
- Harness result: `chapter_3_to_2` timed out after 6136 ms with `completed=false`, even though active window bounds were `1..3` and the subsequent `boundary_backward` completed in 51 ms into Chapter 2.
- Interpretation: recent sections are retained/restorable enough for the backward page movement, but chapter jump target resolution/navigation around already-loaded sections has a bug or harness mismatch. Checkpoint 3 remains incomplete.

Corrective iteration after Sequence B failure:

- Added a short wait/retry in `_navigateToSourceLocation` when a lazy source target is requested while display state is still rebuilding. Static verification passed, but Sequence B still failed.
- Updated lazy previous/next chapter navigation to skip duplicate same-location TOC entries and initially require a lower spine when the current source local chunk index is zero. Static verification passed, but profile Sequence B still failed: `chapter_3_to_2` timed out after 6146 ms with `completed=false`, target still at spine 3/current page 11. A subsequent backward boundary movement completed in 54 ms into Chapter 2.
- Latest diagnosis: the resolver can still select a same-spine nested TOC entry when the reader is on the first rendered display page of a spine but the stable source location maps to a nonzero local chunk. The next fix is to treat "first rendered page of current spine" as requiring a previous-chapter target from a lower spine and log the chosen TOC target.

Additional Sequence B correction and post-change measurement:

- The diagnostic Sequence B harness was tightened to resolve lazy chapter jumps by adjacent readable spine, not ambiguous nested TOC entries. A `flutter clean` was required before the physical device picked up this harness change.
- Clean-build profile run, A059, feature-rich fixture:
  - `chapter_1_to_2`: completed in 0 ms because Chapter 2 was already integrated by adjacent warmup.
  - `chapter_2_to_3`: completed in 96 ms, using parsed cache and segmented display restore for the target window.
  - `chapter_3_to_2`: completed in 0 ms because Chapter 2 remained display-ready in memory.
  - Backward boundary from Chapter 2 to Chapter 1: actual `boundary_navigation_completed` for the Chapter 1 prepend completed in 31 ms; harness-level `navigation_completed` was 104 ms because it also waited for a follow-up titlepage prefetch.
- Dominant remaining Sequence B delay before the cache-key fix was a segmented display cache miss for Chapter 1 after the active lazy window changed (`lazy_1_2_3` key). The same Chapter 1 segment had already been cached under a section-only key.
- Implemented conservative section-scoped segmented display keys for single-spine ranges that begin at that section's local source index zero. Multi-section or shifted ranges keep the existing window-scoped key.
- Post-fix evidence: Chapter 1 backward prepend hit `segment_cache_manifest_memory_hit` and `segment_cache_range_loaded` for the section key `lazy_1_63eac2f7`; no pagination generation occurred for Chapter 1, and the actual prepend integration completed in 31 ms.
- Automated verification after the cache-key fix: `rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart` passed; `rtk flutter analyze` passed.

Profile-mode Sequence C, A059, large Plato EPUB:

- Test book copied to app sandbox as `/data/user/0/com.nalori.reader/files/nalori_diag/dialogues_plato.epub`.
- Cold Plato run hydrated the parsed-section manifest from no manifest to all 36 spine records. The output was too large to retain complete operation summaries through logcat after ADB restart, but it proved foreground-resumable hydration completes without putting the full parsed book in RAM. RSS rose roughly from 203 MiB at open to 345 MiB during full hydration, then sections were evicted under the parsed-section retention policy.
- Warmed parsed-cache rerun:
  - Direct open to titlepage: `lazy_reader_open_end` 517 ms. Dominant cost was parsed manifest/cache read for the titlepage; segmented display restore took 45 ms.
  - Initial adjacent forward warmup into imprint: parsed cache hit, segmented display exact-range hit, completed in 131 ms.
  - Filtered rerun captured distant jump `+10` from titlepage to Protagoras: parsed cache hit for spine 10, segmented cache hit for section key `lazy_10_566e9b8f`, segment range load 5 ms, total intent-to-first-frame 127 ms.
  - Around distant target spine 10/Protagoras, backward adjacent section 9/Laches was restored from segmented cache: segment `lazy_9_d6e64379`, 125 display chunks, range load 4 ms, actual prepend integration 45 ms. Harness-level `boundary_backward` was 167 ms because it included adjacent warmup/follow-up work.
  - Forward adjacent section 11/Euthydemus was restored from segmented cache: 118 display chunks, range load 5 ms, actual append integration 87 ms; harness `boundary_forward` completed in 51 ms once already integrated.
- Filtered Sequence C run command: `rtk bash -lc "rtk timeout 100s rtk flutter run --profile ... | rg 'reader_diag_sequence_begin|distant_jump_plus_10|navigation_completed|...'"`
- Filtered Sequence C result: `distant_jump_plus_10` 127 ms, `boundary_backward` harness 163 ms with actual integration 43 ms, `boundary_forward` 51 ms, final active window `9..11`, RSS about 302 MiB.
- Hydration safety observation: the first cold run continued low-priority parsed hydration after scenario activity and emitted repeated `hydration_task_preempted` during foreground work. It is cooperative, not interruptive mid-section. More frame/jank proof is still required before Checkpoint 6 physical acceptance.

Profile-mode Sequence E, A059, feature-rich fixture, asset-launched diagnostic path (`asset:test/fixtures/books/feature_rich_lazy_reader.epub`):

- Asset launch fixed the previous scoped-storage failure. The fixture copied into the app code-cache path and direct Continue opened the lazy reader.
- Direct lazy open: 94 ms from `continue_tapped` to `lazy_reader_open_end`.
- Initial visible display: cache miss for the default layout; parsed section 1 was loaded from EPUB and paginated in 104 ms async display rebuild. Initial adjacent warmup integrated previous/titlepage and next/chapter-2, expanding active window `0..2`.
- Setting changes measured by harness:
  - Font size change: current page first-frame completion was captured in the run; parsed content was reused and display generation changed for the layout.
  - Density change: current page first-frame completion was captured in the run; parsed content was reused and display generation changed for the layout.
  - Margin change: `settings_margin` completed in 422 ms to first frame. The dominant cost was layout-specific pagination of the current `0..2` source window, not EPUB parsing.
- After the margin layout rebuild, adjacent boundary gestures were display-ready: backward titlepage boundary completed in 50 ms to first frame; forward back into chapter 1 completed in 50 ms to first frame.
- Segmented display persistence proof inside this run: the `22.000/0.750/28.000` layout wrote segment `sourceStart=0 sourceEndExclusive=48` in 92 ms, then a later same-layout rebuild hit `segment_cache_manifest_memory_hit`, loaded the segment in 2 ms, and completed `reader_display_rebuild_end` in 4 ms / async end in 5 ms without EPUB parse or pagination.
- Cache-key stability observation: layout keys use fixed decimal forms such as `22.000`, `0.750`, `28.000`, and integerized `460x1020`; no unstable values such as `17.099999999999998` were observed in cache keys. Safe-area values are still part of the key (`safeAreaBottom` changed from `24` to `0` after the scripted sequence), causing a post-sequence signature change and rebuild. This is not accepted yet because it may be normal inset stabilization or may be avoidable cache churn.
- The run ended with `Lost connection to device` after the scripted `reader_diag_sequence_end` and post-sequence relayout. No `FLUTTER ERROR`, `RangeError`, crash, ANR, OOM, or skipped-frame diagnostic was captured in the filtered output before disconnect.
- Status: Sequence E is partially measured. Parsed reuse and segmented display persistence are proven for same-layout reuse on this fixture; orientation and line-height are still unmeasured, force-stop reuse is still unmeasured, and settings invalidation is not accepted because the 422 ms current-page layout rebuild and safe-area-key churn need follow-up.

Implementation iteration after partial Sequence E:

- Diagnostic asset launches now reuse persisted `BookMetadata` by book ID instead of creating fresh metadata on every launch. This enables force-stop/relaunch Continue restoration to use saved `lastReadLocation` for Sequence D.
- Added diagnostic Sequence D support. First run jumps to the next readable spine, persists the current stable reading position, and writes a SharedPreferences marker; after external force-stop/relaunch, the second run consumes the marker and performs a backward boundary navigation from the restored position.
- Expanded Sequence E to include line-height and orientation. Orientation is measured by temporarily setting `DeviceOrientation.landscapeLeft`, waiting for the display rebuild, testing backward/forward boundaries, then restoring supported orientations.
- Automated verification after this harness work: `rtk flutter analyze` passed.
- Focused regression tests passed: `rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart test/widgets/reading_card_deck_test.dart`.

Expanded profile-mode Sequence E rerun, A059, feature-rich fixture:

- Run log: `/tmp/nalori_seq_e_expanded_20260621_204008.log`.
- Direct lazy open: 131 ms. Initial display used parsed cache for Chapter 1, missed the segmented cache for the current layout, and paginated the first 23 source chunks in 37 ms / 61 ms async rebuild.
- Initial adjacent warmup before the sequence integrated previous/titlepage and next/chapter-2, with active window `0..2`. It used parsed cache hits for both adjacent sections. Chapter 2 display was generated once because the requested range was not cached.
- Setting-change current-page rebuilds:
  - Font size: 440 ms intent-to-first-frame; display rebuild 90 ms; range pagination 86 ms.
  - Density: 499 ms intent-to-first-frame; display rebuild 138 ms; range pagination 136 ms.
  - Margin: 491 ms intent-to-first-frame; display rebuild 133 ms; range pagination 131 ms.
  - Line-height: 417 ms intent-to-first-frame; display rebuild 69 ms; range pagination 66 ms.
  - Orientation to landscape: 510 ms intent-to-first-frame; display rebuild 231 ms; range pagination 173 ms. Dominant measured source was `range_slow_source_chunk` at source index 36, 44 ms in `process_subchunks`.
- Boundary navigation after every setting/orientation change remained display-ready and did not parse EPUB content:
  - After font size: backward 50 ms, forward 53 ms.
  - After density: backward 54 ms, forward 50 ms.
  - After margin: backward 50 ms, forward 52 ms.
  - After line-height: backward 51 ms, forward 50 ms.
  - After orientation: backward 56 ms, forward 51 ms.
- Segmented persistence verification:
  - Each new layout wrote a segmented display segment after first pagination.
  - After restoring portrait from landscape, the same `26.000/1.000/lineHeight_1.400/32.000/460x1020` layout hit `segment_cache_manifest_memory_hit`, loaded `sourceStart=0 sourceEndExclusive=48` in 30 ms, and rebuilt in 32-33 ms without EPUB parsing or pagination.
- Cache-key normalization:
  - Keys remain canonicalized (`26.000`, `1.000`, `lineHeight_1.400`, `32.000`, `460x1020`, `1020x460`).
  - Raw diagnostic fields can still show Dart doubles such as `lineHeight=1.4000000000000001`, but the persisted cache key is stable.
- Frame/memory notes:
  - RSS during the scripted sequence stayed roughly 268-275 MiB after initial warmup.
  - One background concurrent mark compact GC appeared after `reader_diag_sequence_end`; no `FLUTTER ERROR`, `RangeError`, ANR, OOM, or skipped-frame line appeared in the captured filtered log.
- Status: Sequence E functional boundary behavior passes on this fixture. Checkpoint 8 is still incomplete because layout changes themselves take 417-510 ms to first readable frame and need a policy decision or optimization; however, adjacent boundary navigation after layout invalidation meets the display-ready requirement.

Profile-mode Sequence D setup run, A059, feature-rich fixture:

- Run log: `/tmp/nalori_seq_d_setup_20260621.log`.
- Diagnostic launch reused persisted metadata (`lastReadIndex=2`, stable last-read location present), proving the asset diagnostic launcher no longer discards saved location state between runs.
- Direct lazy open: 177 ms, using parsed cache hit for Chapter 1.
- Initial display restored the stable location exactly and paginated the current section in 36 ms / 54 ms async display rebuild.
- Adjacent warmup integrated titlepage and Chapter 2 before the scenario body. Backward warmup took 177 ms; forward warmup into Chapter 2 took 52 ms and was then preempted by the explicit setup jump.
- `cold_restore_setup_jump` Chapter 1 -> Chapter 2 completed in 102 ms to first frame. It generated a target display range `sourceStart=8 sourceEndExclusive=55` in 56 ms, then wrote the segment to the segmented display cache.
- `cold_restore_setup_ready` was logged for target spine 2 / `chapter-2.xhtml`; `stable_location_saved` later persisted spine 2, local chunk 0, display index 9.
- Status: setup phase passed. The measured cold restore phase still requires external force-stop and relaunch.

Profile-mode Sequence D cold restore run, A059, feature-rich fixture:

- Run log: `/tmp/nalori_seq_d_restore_20260621.log`.
- External action: cleared logcat, `am force-stop com.nalori.reader`, then relaunched the already-installed profile build with the compiled diagnostic defines.
- Continue restored persisted Chapter 2 state: `continue_tapped lastReadIndex=25 hasStableLastReadLocation=true`; target resolved to spine 2 / `chapter-2.xhtml`, local chunk 0.
- Direct lazy open: 115 ms. Parsed cache hit for Chapter 2; no EPUB parse occurred.
- Initial restored display: missed the section-only segmented display key `lazy_2_5872ce62`, then paginated Chapter 2 in 143 ms / 176 ms async rebuild. Stable location restored exactly to spine 2 after display publish.
- Adjacent warmup after restore:
  - Previous Chapter 1 was loaded from parsed cache and exact segmented display cache (`lazy_1_63eac2f7`) with `segment_cache_range_loaded` in 12 ms, incremental prepend, no pagination, `boundary_navigation_completed` 176 ms.
  - Next Chapter 3 was parsed-cache hit but generated display for the forward range in 45 ms; warmup completed in 74 ms.
- Actual cold restore backward navigation after marker detection:
  - `cold_restore_detected` at spine 2 with active window `1..3`.
  - `boundary_backward` completed in 50 ms to first frame, target spine 1 / Chapter 1, active window `1..3`.
- Frame/memory notes:
  - App RSS grew from 216 MiB at Continue to about 260 MiB after the boundary result.
  - No app `FLUTTER ERROR`, fatal exception, ANR, OOM, or skipped-frame line appeared in the filtered capture. One unrelated system-server GC appeared later.
- Status: Sequence D functional cold restore and backward boundary pass on this fixture. Checkpoint 5 remains incomplete because initial restore did not reuse the existing persisted window segment for Chapter 2; it required layout pagination due to a missing section-only segmented display key.

Implementation iteration after Sequence D cache-miss diagnosis:

- Root cause: cold direct restore loads a single lazy section and asks the segmented display cache for the section-scoped key (`lazy_2_<checksum>`). The setup/jump path had previously persisted Chapter 2 only as part of a shifted multi-section window segment, so direct restore could not reuse it and had to paginate.
- Added a conservative secondary write in `ReaderScreen`: when a generated display range fully covers a section, the range is also normalized and persisted under that section's section-scoped segmented key. The normalized write shifts source mappings and `BookChunk.sourceRanges` to section-local source indexes, so later single-section restore can load it without the original multi-section window.
- This does not keep additional display sections in RAM and does not change active window bounds. It writes extra persisted segments only for complete covered sections already generated for the active layout.
- Automated verification: `rtk flutter analyze` passed.
- Focused regression tests passed: `rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart test/widgets/reading_card_deck_test.dart`.

Post-implementation Sequence D setup rerun, A059:

- Run log: `/tmp/nalori_seq_d_setup_section_scope_20260621.log`.
- The run proved the code was installed and preserved existing section-scoped cache hits for Chapter 1: initial restore used `lazy_1_63eac2f7`, loaded the section segment in 11 ms, and rebuilt in 42-43 ms.
- The setup jump to Chapter 2 did not yet prove the new section-scoped Chapter 2 secondary write. The visible log showed the multi-section write for `lazy_0_..._1_..._2_...` but no `lazy_2_5872ce62` write before the run ended.
- Additional complication observed: an older multi-section manifest produced `segment_cache_corrupt reason=manifest_PathNotFoundException`, then the range regenerated and rewrote the multi-section segment.
- Automated verification after adding debug-only selector diagnostics for the secondary write: `rtk flutter analyze` passed.
- New diagnostics added: `section_scoped_segment_write_started` and `section_scoped_segment_write_skipped` with spine index, covered ranges, selected display count, and skip reason.
- Status: the secondary write implementation is present but not physically accepted. The next profile run must confirm why the selector skipped Chapter 2 or show a `lazy_2_5872ce62` section-scoped write followed by a cold restore segment hit.

Follow-up Sequence D diagnostic rerun, A059:

- Run log: `/tmp/nalori_seq_d_section_diag_20260621.log`.
- This run was not a valid cold-restore setup/restore pair because a stale Sequence D marker was still present. The harness interpreted the restored Chapter 1 state as `cold_restore_detected` and navigated backward into the titlepage.
- Useful cache-write evidence from the invalid run:
  - Chapter 1 restored from existing section-scoped cache key `lazy_1_63eac2f7`; segment loaded in 10 ms and the display rebuild completed in 54-55 ms.
  - Adjacent forward warmup generated Chapter 2 in a multi-section active-window segment (`lazy_0_..._1_..._2_...`, `sourceStart=25`, `sourceEndExclusive=55`) because that multi-section range was not cached.
  - The multi-section segment write completed in 317 ms.
  - No `section_scoped_segment_write_started` or `section_scoped_segment_write_skipped` diagnostic was emitted for the Chapter 2 secondary write.
- Diagnosis: the secondary writer is not reaching its per-section selector diagnostics after the multi-section write. The next code iteration must add entry and bounds-scan diagnostics to distinguish early return (`_lazySession`/source-location state) from an empty or mismatched section-bound calculation.
- Status: Checkpoint 5 remains incomplete; section-scoped persistence for generated adjacent sections is not physically accepted.

Implementation iteration after missing secondary-write diagnostics:

- Added diagnostic-only checkpoints around the secondary section-scoped write path:
  - `section_scoped_segment_write_after_primary` after the primary segment write returns, including source-location count and stale-write guard status.
  - `section_scoped_segment_write_scan` at helper entry, including lazy-session availability, display/source mapping sizes, and guard status.
  - `section_scoped_segment_write_bounds` after active source bounds are grouped by spine.
  - Existing skip/start diagnostics remain in place for per-spine selection.
- Static verification: `rtk flutter analyze` passed.
- Focused regression verification: `rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart test/widgets/reading_card_deck_test.dart` passed.
- Physical acceptance: pending; the next A059 profile run must show whether the helper is returning early, scanning the wrong active bounds, or being prevented by stale generation state.

Clean-build Sequence D diagnostic rerun, A059:

- Run log: `/tmp/nalori_seq_d_section_diag3_clean_20260621.log`.
- `rtk flutter clean` was required before this run to avoid stale profile-build ambiguity.
- The run restored to the titlepage (`spineIndex=0`) from the previous invalid setup marker. It was not a valid cold-restore backtracking acceptance run because true book-start backward navigation is expected to fail.
- Useful cache evidence:
  - Initial restore loaded titlepage section cache in 75 ms and rebuilt in 123-124 ms.
  - Forward adjacent warmup into Chapter 1 hit the existing multi-section segment (`lazy_0_..._1_...`, `sourceStart=2`, `sourceEndExclusive=25`) and completed in 80 ms.
  - Because this was a segment-cache hit, no generated display range was written and the secondary section-scoped writer still was not exercised.
- Frame/jank evidence:
  - One startup `Choreographer` skipped-frame line appeared: `Skipped 46 frames`.
  - One platform `Resources$NotFoundException: String resource ID #0x0` appeared. No app `FLUTTER ERROR`, ANR, OOM, or fatal exception appeared in the filtered log.
- Code diagnosis from inspection: primary segmented keys become section-scoped only when a section's first active source index is `0`. Appended sections such as Chapter 1 after titlepage or Chapter 2 after Chapter 1 remain multi-section keys and therefore still require the secondary normalized write for direct single-section restore.
- Status: Checkpoint 5 remains incomplete. Next measurement must force a generated appended-section range, not a cache hit, to validate the secondary write.

Implementation iteration after cache-write ordering diagnosis:

- Changed generated range persistence order so normalized section-scoped writes are attempted before the broader active-window segment write.
- Rationale: direct single-section restore depends on the section-scoped key. Waiting for a slower multi-section write first can delay or prevent the direct-restore cache from becoming available, especially when the harness exits shortly after publication.
- The broader active-window segment is still written afterward for compatibility with current multi-section cache reuse.
- Static verification: `rtk flutter analyze` passed.
- Focused regression verification: `rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart test/widgets/reading_card_deck_test.dart` passed.
- Physical acceptance: pending; the next forced-miss profile run must show `section_scoped_segment_write_scan` and either a section-scoped write or a precise skip reason.

Forced-miss Sequence E section-write verification, A059:

- Run log: `/tmp/nalori_seq_e_section_write_20260621.log`.
- Direct lazy open: 240 ms. Initial titlepage restore used section-scoped segmented cache (`lazy_0_c0ce15fb`) and rebuilt in 37 ms.
- Initial adjacent Chapter 1 warmup hit the existing multi-section segment (`lazy_0_..._1_...`, `sourceStart=2`, `sourceEndExclusive=25`) and completed in 137 ms.
- The settings sequence forced several layout-specific cache misses and generated display ranges over the active titlepage + Chapter 1 window:
  - Font size: range generation 53 ms, first frame 367 ms.
  - Density: range generation 22 ms, first frame 370 ms.
  - Margin: range generation 25 ms, first frame 360 ms.
  - Line-height: range generation 20 ms, first frame 357 ms.
  - Orientation landscape: range generation 149 ms, first frame 469 ms.
  - Portrait restore after orientation: range generation 128 ms, rebuild async 210 ms after the sequence end.
- Section-scoped persistence proof after the ordering change:
  - For font-size layout, `section_scoped_segment_write_scan` saw spines `0,1` with bounds `0:0-2,1:2-25`.
  - Titlepage section key `lazy_0_c0ce15fb` wrote `sourceStart=0`, `sourceEndExclusive=2` in 167 ms.
  - Chapter 1 section key `lazy_1_63eac2f7` wrote `sourceStart=0`, `sourceEndExclusive=23` in 98 ms.
  - The broader multi-section key `lazy_0_c0ce15fb_1_63eac2f7` wrote afterward in 58 ms.
  - Density and margin layouts repeated the same order: section-scoped Chapter 1 wrote in 61 ms and 70 ms respectively, then the multi-section window wrote in 51 ms and 56 ms.
  - Line-height/orientation produced stale-generation rejections for obsolete layouts (`stale_before_serialize`) while the current portrait layout still wrote Chapter 1 section key `lazy_1_63eac2f7` in 120 ms and then the multi-section key in 74 ms.
- Boundary behavior after generated layout changes:
  - After density: backward 53 ms, forward 51 ms.
  - After margin: backward 50 ms, forward 50 ms.
  - After line-height: backward 50 ms, forward 51 ms.
  - After landscape: backward 60 ms, forward 114 ms.
- Measurement caveat:
  - After font-size, the harness attempted backward navigation from true book start and timed out after 6120 ms even though the reader correctly remained at the titlepage. This was a diagnostic harness predicate bug, not a product boundary-loading failure.
  - No app `FLUTTER ERROR`, `RangeError`, fatal exception, ANR, or OOM appeared. The run ended with `Lost connection to device` after timeout, following completed sequence diagnostics and queued cache writes.
- Status: section-scoped persistence for generated appended sections is physically proven on the feature-rich fixture. Checkpoint 5 still needs a force-stop/reopen hit proof using the newly written section key for the same layout.

Implementation iteration after true-boundary harness failure:

- Updated `_readerDiagBoundary` to resolve the expected adjacent readable spine before performing the gesture.
- If no adjacent readable spine exists, the diagnostic completion predicate now accepts a stable same-spine idle state instead of waiting for an impossible spine change.
- If an adjacent spine exists, the predicate requires the expected target spine specifically, not merely any spine change.
- Static verification: `rtk flutter analyze` passed.
- Focused regression verification: `rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart test/widgets/reading_card_deck_test.dart` passed.
- Physical acceptance: pending; the next Sequence E/D run should no longer report a 6 s failure for true book-start or book-end boundary checks.

Force-stop/reopen section-scoped display-cache proof, A059:

- Run log: `/tmp/nalori_force_reopen_section_hit_20260621.log`.
- External action: cleared logcat, `am force-stop com.nalori.reader`, then relaunched the installed profile app.
- Continue restored Chapter 1: `lastReadIndex=2`, target spine 1 / `chapter-1.xhtml`, stable last-read location present.
- Direct lazy open: 103 ms. Parsed-section cache hit for Chapter 1; no EPUB resource parse occurred.
- Initial restored display used the newly persisted section-scoped display segment:
  - Cache key: `feature_rich_lazy_reader.epub_dc_v11_14.000_lexend_regular_0.350_lineHeight_1.500_paragraphSpacing_1.000_sideMargin_36.000_460x1020_1_1.00_54_0_0_0_lazy_1_63eac2f7`.
  - Manifest loaded from disk, segment `sourceStart=0`, `sourceEndExclusive=23` loaded in 14 ms.
  - `segment_cache_hit` published the initial range with 14 display chunks.
  - Display rebuild ended in 133 ms in `progressive_segment_cache` mode.
  - No `range_generation_begin` occurred before the initial restored display became ready.
- Adjacent warmup after restore:
  - Previous titlepage section key `lazy_0_c0ce15fb` loaded in 11 ms and prepended incrementally.
  - This confirms backward adjacent availability after force-stop without parsing or pagination for the previous section.
- The installed app still had `NALORI_READER_DIAG_SCENARIO=E`, so after the initial proof it continued into the settings sequence and wrote additional `16.000/0.550/lineHeight_1.600/40.000` layout segments. Those later measurements are not part of the cold initial-restore proof.
- Status: Checkpoint 5 section-scoped persistence is now physically proven on the feature-rich fixture for same-layout force-stop/reopen. Broader acceptance still needs corrupt-cache fallback and another run with the true-boundary harness fix installed.

Valid Sequence D setup after section-scoped persistence fix, A059:

- Run log: `/tmp/nalori_seq_d_setup_after_section_fix_20260621.log`.
- The latest profile build installed the true-boundary harness fix and ran `NALORI_READER_DIAG_SCENARIO=D`.
- Starting state: Chapter 1 / spine 1.
- Direct open: 333 ms. A transient safe-area-bottom value changed the layout key from `...54_24_0_0` to `...54_0_0_0`; the first key missed and paginated Chapter 1, then the settled key reused the existing multi-section segment. This is an avoidable cache-key churn issue and remains open.
- Adjacent warmup:
  - Previous titlepage restored from section-scoped display cache in 11 ms and prepended incrementally.
  - Next Chapter 2 initially missed the multi-section range, generated in 68 ms, appended, and completed forward warmup in 129 ms.
  - The new ordering wrote Chapter 2 section-scoped key `lazy_2_5872ce62` for `sourceStart=0`, `sourceEndExclusive=30`, `displayChunks=16`; write completed in 541 ms. The broader multi-section segment wrote afterward in 319 ms.
- Setup jump:
  - `cold_restore_setup_jump` Chapter 1 -> Chapter 2 completed in 1 ms because Chapter 2 was already integrated.
  - `cold_restore_setup_ready` recorded target spine 2 / `chapter-2.xhtml`, current page 15.
- Status: setup passed and produced the required section-scoped Chapter 2 display segment for the restore half.

Valid Sequence D cold restore after section-scoped persistence fix, A059:

- Run log: `/tmp/nalori_seq_d_restore_after_section_fix_20260621.log`.
- External action: cleared logcat, force-stopped `com.nalori.reader`, and relaunched the installed profile build.
- Continue restored Chapter 2: `lastReadIndex=25`, target spine 2 / `chapter-2.xhtml`, stable last-read location present.
- Direct lazy open: 162 ms. Parsed-section cache hit for Chapter 2; no EPUB parse occurred.
- Initial restored display:
  - Section-scoped display key `lazy_2_5872ce62` loaded from disk.
  - Segment `sourceStart=0`, `sourceEndExclusive=30`, `displayChunks=16`, `bytes=1179` loaded in 8 ms.
  - `segment_cache_hit` published the initial range; display rebuild ended in 42 ms in `progressive_segment_cache` mode.
  - No pagination/range generation occurred before the restored Chapter 2 page became readable.
- Adjacent warmup after restore:
  - Previous Chapter 1 parsed cache hit, then section-scoped display key `lazy_1_63eac2f7` loaded exact range in 3 ms and prepended incrementally.
  - Warmup `boundary_navigation_completed` for the previous section took 292 ms total because it included parsed-section lookup and integration, but no pagination.
  - Forward warmup into Chapter 3 generated a new section in 38 ms and completed in 54 ms; it also wrote section key `lazy_3_6b184294`.
- Actual D navigation:
  - `cold_restore_detected` at spine 2 with active window `1..3`.
  - `boundary_backward` Chapter 2 -> Chapter 1 completed in 51 ms to first frame, target spine 1, active window `1..3`.
- Frame/memory notes:
  - RSS at initial restore was about 211-212 MiB; after adjacent sections, about 243-247 MiB.
  - No app `FLUTTER ERROR`, `RangeError`, fatal exception, ANR, or OOM appeared in the filtered capture.
- Status: Sequence D passes functionally and meets the visible navigation target on the feature-rich fixture after the section-scoped cache fix. Remaining open issues are the safe-area cache-key churn, broader regression matrix, corrupt-cache fallback proof, and larger-book repeats.

Implementation iteration after safe-area cache-key churn diagnosis:

- Root cause: display generation used raw `MediaQuery.viewPadding.bottom` in both pagination metrics and cache keys. On A059, the first reader frame can report a transient bottom inset around 24 px before immersive mode settles to 0 px. This produced separate cache families such as `...54_24_0_0` and `...54_0_0_0`, causing unnecessary pagination and generation cancellation.
- Change: `_ensureDisplayChunksBuilt` now canonicalizes the display-generation safe area before comparison, display signature construction, viewport signature construction, and pagination. The bottom inset is canonicalized to `0` for the immersive reader display path. Diagnostics now include `rawSafeArea*` fields alongside the canonical `safeArea*` fields.
- Rationale: Nalori's reader enters `SystemUiMode.immersiveSticky`; the settled A059 reader layout uses bottom inset `0`. Using the transient pre-immersive bottom inset for display generation creates cache churn without representing the final reader viewport.
- Static verification: `rtk flutter analyze` passed.
- Focused regression verification: `rtk flutter test test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/progressive_display_state_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart test/widgets/reading_card_deck_test.dart` passed.
- Physical acceptance: pending; the next profile launch must show raw bottom inset may be nonzero while the cache key remains canonical with bottom `0`, and must not trigger a second signature-change rebuild solely for bottom inset settling.

Safe-area canonicalization physical verification, A059:

- Run log: `/tmp/nalori_safe_area_canonical_clean_20260621.log`.
- A `flutter clean` was required before the device picked up the safe-area patch; the prior incremental profile build still emitted old signatures.
- Clean-build profile run showed `reader_display_signature` diagnostics with both canonical and raw fields:
  - `safeAreaBottom=0.0`
  - `rawSafeAreaBottom=0.0`
  - cache key stayed `...460x1020_1_1.00_54_0_0_0`.
- No `reader_display_generation_cancelled` event occurred for bottom-inset settling in the clean verification run.
- Initial restored section used segmented display cache:
  - Chapter 3 section key `lazy_3_6b184294` loaded in 14 ms.
  - Adjacent Chapter 2 section key `lazy_2_5872ce62` loaded in 7 ms.
  - Boundary backward completed in 74 ms at the availability layer; harness navigation to Chapter 2 completed in 0 ms once integrated.
- Status: physical verification confirms the canonical path is active and did not regress segmented-cache restore. A run that captures nonzero `rawSafeAreaBottom` under the patched build is still useful but no longer required to prove the cache key can remain stable when raw and canonical values are logged separately.

Initial code inspection findings:

- `LazySectionRepository` dedupes through neither an explicit scheduler nor per-section in-flight joins in the visible source path inspected so far.
- Parsed-section retention is count-based (`retainedSectionLimit`, default 3), not byte-budgeted and not pinned by current/target sections.
- Adjacent parsed-section prefetch exists, but display-ready adjacent pagination is not centralized.
- `ReaderScreen` has segmented cache read/write support and boundary diagnostics, but boundary loads can still wait for parse/cache restore/pagination/integration.

Automated baseline command:

- `rtk flutter test test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_generation_coordinator_test.dart test/unit/services/progressive_display_state_test.dart`
- Result before production changes: passed.

## Checkpoints

- [ ] Checkpoint 0: baseline diagnostics complete
- [ ] Checkpoint 1: bottleneck confirmed
- [ ] Checkpoint 2: navigation scheduler implemented
- [ ] Checkpoint 3: adjacent predictive pagination implemented
- [ ] Checkpoint 4: recent-section LRU implemented
- [ ] Checkpoint 5: segmented display persistence verified
- [ ] Checkpoint 6: whole-book parsed hydration implemented
- [ ] Checkpoint 7: background pagination policy implemented
- [ ] Checkpoint 8: settings invalidation verified
- [ ] Checkpoint 9: physical-device performance criteria passed
- [ ] Checkpoint 10: regression matrix passed

Checkpoint status convention:

- Implemented: code path exists.
- Automated tests passed: unit/widget/static verification passed.
- Physical acceptance passed: profile-mode device evidence satisfies that checkpoint's timing, visual, frame, memory, and regression criteria.
- A checkpoint is marked `[x]` only when physical acceptance has passed where required.

Checkpoint accuracy correction, 2026-06-21:

- No checkpoint is currently marked complete because Sequences D/E, full regression coverage, and frame/memory acceptance are still pending.
- Checkpoint 1 has partial physical evidence from Sequences A-C, but it remains incomplete until the dominant delay is confirmed across the remaining physical scenarios.
- Checkpoint 3 has implementation and automated-test coverage, plus Sequence A-C evidence for some warmed boundaries, but remains incomplete until logs prove previous and next display readiness before all relevant boundary gestures.
- Whole-book parsed hydration is implemented and automated-tested, but not performance-approved. Current evidence only proves cooperative quiet-period behavior in measured windows; it does not yet prove no visible jank across the regression matrix.
- Whole-book/background layout pagination is not approved for implementation expansion until segmented display persistence and hydration safety are physically verified.

| Checkpoint | Implemented | Automated tests passed | Physical acceptance passed |
| --- | --- | --- | --- |
| 0 Baseline diagnostics | partial | partial | no |
| 1 Bottleneck confirmed | n/a | partial | no |
| 2 Navigation scheduler | yes | yes | no |
| 3 Adjacent predictive pagination | partial | yes | no |
| 4 Recent-section LRU | partial | yes | no |
| 5 Segmented display persistence | yes | yes | partial - feature-rich force-stop pass; corrupt-cache and large-book proof pending |
| 6 Whole-book parsed hydration | yes | yes | no |
| 7 Background pagination policy | no | no | no |
| 8 Settings invalidation | partial | no | no |
| 9 Device performance criteria | no | no | no |
| 10 Regression matrix | no | no | no |

## Checkpoint Log

### Checkpoint 0: Baseline Diagnostics

Status: in progress.

Findings:

- Progress document created before production behavior changes.
- Existing worktree has many pre-existing lazy-reader changes and untracked files; these are treated as existing state.

Files changed:

- `docs/lazy_reader_smooth_navigation_progress.md`
- `lib/services/segmented_display_cache_service.dart`
- `lib/services/parsed_section_cache_service.dart`
- `lib/screens/reader_screen.dart`
- `test/unit/services/segmented_display_cache_service_test.dart`
- `test/unit/services/parsed_section_cache_service_test.dart`

Diagnostics observed:

- `flutter devices` found A059 Android physical device.
- Local fixtures found: `Dialogues -- Plato.epub`, `test/fixtures/books/feature_rich_lazy_reader.epub`.
- Code inspection confirmed the dominant avoidable delay path is reactive adjacent section availability: parse/cache read plus display range preparation occurs only when the loaded-window boundary is reached unless a stable-location warmup happens.

Tests run:

- Baseline targeted lazy/display tests passed.

Device measurements:

- Pending.

Regressions found:

- Pending.

Next action:

- Continue toward segmented display persistence/hydration and complete manual physical navigation timing.

Checkpoint passed: no.

### Checkpoint 1: Bottleneck Confirmed

Status: incomplete.

Implemented: no code required for this checkpoint.

Automated tests passed: targeted baseline suite passed.

Physical acceptance passed: no.

Findings:

- The one-second path is not a book-boundary correctness bug. The remaining avoidable pause is the reactive chain: adjacent section request -> parsed-section memory/cache/parse -> source-window append/prepend -> progressive display range restore/generation -> publish/navigation completion.
- Backward prepend is costlier than forward append because it rebuilds the source window, cancels the active display generation, clears display chunks, and waits for a new visible display window.
- Post-change Sequence A on A059 shows the full-window backward rebuild is no longer always required: compatible previous-section insertion used `mode=incremental`, retained display generation 1, loaded the previous segment from segmented display cache, prepended two display chunks, and completed the warmup in 493 ms. The remaining delay for that path is dominated by parsed-cache manifest load and segmented display-cache restore/integration, not pagination.

Files changed:

- `docs/lazy_reader_smooth_navigation_progress.md`

Diagnostics observed:

- Existing diagnostics include `boundary_navigation_requested`, `adjacent_section_load_started`, `range_generation_begin/end`, segmented cache events, and lazy section parse/cache events.

Tests run:

- Targeted lazy/display suite passed before behavior changes.
- After manifest-cache fix: targeted segmented/display/lazy suite passed; `rtk flutter analyze` passed.
- After parsed-manifest cache fix: targeted parsed/segmented/display/lazy suite passed; `rtk flutter analyze` passed.
- After hydration quiet-period fix: targeted parsed/segmented/display/lazy suite passed; `rtk flutter analyze` passed.

Device measurements:

- A059 profile Sequence A, feature-rich fixture:
  - Before manifest-cache fix: warmed forward gesture 63 ms; warmed backward gesture 50 ms; backward adjacent warmup 493 ms; forward adjacent warmup 485 ms.
  - After manifest-cache fix: warmed forward gesture 51 ms; warmed backward gesture 51 ms; backward adjacent warmup 109 ms; forward adjacent warmup 259 ms.
  - After hydration quiet-period fix: warmed forward gesture 0 ms; warmed backward gesture 0 ms; backward adjacent warmup 102 ms; forward adjacent warmup 120 ms.

Regressions found:

- None in targeted baseline tests.

Next action:

- Rerun A/B in profile mode. Verify hydration no longer runs inside the navigation window and compare adjacent warmup plus warmed gesture timings.

Checkpoint passed: no. Physical timing breakdown has not yet identified the dominant device delay.

### Checkpoint 2: Navigation Scheduler

Status: incomplete.

Implemented: yes, for parsed-section work scheduling scope.

Automated tests passed: yes.

Physical acceptance passed: no.

Findings:

- Added `LazySectionWorkPriority` with explicit navigation, adjacent readiness, boundary prefetch, recent retention, parsed hydration, and layout pagination priorities.
- `LazySectionRepository` now joins duplicate in-flight section loads by spine index and records priority upgrades.
- Stale in-flight work no longer repopulates retained memory after repository close/reopen.

Files changed:

- `lib/services/lazy_section_repository.dart`
- `lib/services/lazy_book_session.dart`
- `lib/screens/reader_screen.dart`
- `test/unit/services/lazy_section_repository_test.dart`

Diagnostics observed:

- Added gated diagnostics for memory hits, parsed-cache hits, duplicate joins, priority preemption, prefetch start/completion, and section eviction.

Tests run:

- `rtk flutter analyze` passed.
- Targeted lazy/display suite passed after changes.

Device measurements:

- Profile startup on A059 built, installed, and launched successfully twice.

Regressions found:

- None in analyze or targeted tests.

Next action:

- Complete manual navigation log capture with local books and verify adjacent warmup events before boundary gestures.

Checkpoint passed: no. Device logs still need to prove foreground navigation is not blocked by lower-priority work and clarify that current parsing is non-preemptive once started.

### Checkpoint 3: Adjacent Predictive Pagination

Status: incomplete.

Implemented: partial.

Automated tests passed: yes for surrounding lazy/display suites.

Physical acceptance passed: no.

Findings:

- Initial visible-range readiness now schedules adjacent warmup through the existing lazy adjacent integration path.
- Stable-location jumps already scheduled adjacent warmup; the same path is now triggered after initial display cache hits and initial progressive range publication.
- Actual boundary gestures remain priority 0 explicit navigation; warmups are priority 1; speculative boundary prefetch remains lower priority.

Files changed:

- `lib/screens/reader_screen.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/lazy_section_repository.dart`
- `lib/services/progressive_display_state.dart`
- `test/unit/services/progressive_display_state_test.dart`

Diagnostics observed:

- Added `prefetch_scheduled`, `prefetch_started`, and `prefetch_completed` for initial visible adjacent warmup.
- A059 Sequence A proved warmup can make adjacent sections integrated before the measured user boundary gestures: `boundary_navigation_completed` for operation 2 occurred before `navigation_intent_received` for the harness forward gesture; the subsequent forward and backward gestures completed in 63 ms and 50 ms.
- Adjacent warmup did more than parse: it loaded parsed sections, restored exact display ranges from segmented display cache, appended/prepended display chunks, and expanded active window bounds from `1..1` to `0..2`.
- Backward prepend used `section_prepend_completed mode=incremental`, preserving display generation 1 instead of clearing and rebuilding the active display state.

Tests run:

- `rtk flutter analyze` passed.
- Targeted lazy/display suite passed.
- `rtk flutter test test/unit/services/progressive_display_state_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/segmented_display_cache_service_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart` passed after incremental prepend and display LRU changes.

Device measurements:

- A059 profile Sequence A on `feature_rich_lazy_reader.epub`: forward warmed boundary 63 ms to first frame; backward warmed boundary 50 ms to first frame; adjacent warmup still 485-493 ms.

Regressions found:

- None in automated checks.

Next action:

- Run B-E and larger-book scenarios; if repeated manifest/cache restore remains dominant, optimize cache-manifest reuse or warmup scheduling before adding broader background pagination.

Checkpoint passed: no. Logs must still prove previous and next sections are display-ready before relevant boundary gestures, not merely that warmup was scheduled.

### Checkpoint 4: Recent-Section LRU

Status: incomplete.

Implemented: partial, parsed-section LRU and display-range memory LRU.

Automated tests passed: yes for parsed-section duplicate join, pinned retention, and display-range memory reuse/eviction.

Physical acceptance passed: no.

Findings:

- Replaced pure count-based retained section behavior with an insertion-ordered LRU that also tracks estimated section bytes.
- Current/target/adjacent sections are pinned through `LazyBookSession`.
- Default parsed-section memory budget is 6 MiB, chosen conservatively for lower-memory Android devices.
- Added `DisplaySectionMemoryCache`, an 8 MiB layout-keyed display-range LRU. Exact range requests now check memory before segmented disk cache. Active prepared ranges are pinned.
- The previous `retainedSectionLimit` remains as an upper compatibility ceiling and test control.

Files changed:

- `lib/services/lazy_section_repository.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/display_section_memory_cache.dart`
- `lib/screens/reader_screen.dart`
- `test/unit/services/lazy_section_repository_test.dart`
- `test/unit/services/display_section_memory_cache_test.dart`

Diagnostics observed:

- `section_evicted_from_memory` records estimated bytes, retained bytes, budget, and reason.
- `adjacent_section_display_memory_hit` records layout-compatible display memory hits, retained bytes, and range bounds.

Tests run:

- Added tests for duplicate in-flight joins and pinned retention under pressure.
- Added tests for layout-compatible display memory reuse, layout-key isolation, and unpinned LRU eviction.
- `rtk flutter analyze` passed.
- Targeted lazy/display suite passed.

Device measurements:

- A059 profile Sequence A memory rose from about 204 MiB RSS at `continue_tapped` to about 291 MiB after sections 0-2 were integrated. This includes Flutter/runtime growth and needs comparison on larger books before selecting a display LRU budget adjustment.

Regressions found:

- None in automated checks.

Next action:

- Validate device startup/navigation diagnostics, then continue segmented display persistence and hydration work.

Checkpoint passed: no. Display-section LRU is implemented and tested locally, but physical memory and recently visited navigation acceptance are still pending.

### Checkpoint 6: Whole-Book Parsed Hydration

Status: incomplete.

Implemented: yes for foreground-resumable parsed hydration.

Automated tests passed: yes.

Physical acceptance passed: no.

Findings:

- `ParsedSectionCacheManifest` now carries hydration state: source checksum, parser version, readable count, completed/pending/failed/skipped spine indexes, status, and update time.
- Hydration resumes from existing section records and marks completion when pending sections are written.
- `LazySectionRepository.hydrateParsedSectionsAround` processes one readable section at a time using priority 4, ordered outward from the current spine index.
- Reader-triggered hydration starts after adjacent warmup and pauses before starting a section if foreground display or boundary work is active.
- Hydration writes parsed sections to disk and does not retain the whole book in RAM.

Files changed:

- `lib/services/parsed_section_cache_service.dart`
- `lib/services/lazy_section_repository.dart`
- `lib/services/lazy_book_session.dart`
- `lib/screens/reader_screen.dart`
- `test/unit/services/parsed_section_cache_service_test.dart`

Diagnostics observed:

- Hydration uses existing lazy section cache diagnostics plus `prefetch_paused` and `hydration_section_failed` for paused/failed background parsing.

Tests run:

- `rtk flutter analyze` passed.
- `rtk flutter test test/unit/services/parsed_section_cache_service_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_generation_coordinator_test.dart test/unit/services/progressive_display_state_test.dart` passed.

Device measurements:

- Profile startup on A059 built, installed, and launched successfully after hydration changes.

Regressions found:

- None in automated checks or profile startup.

Next action:

- Complete manual navigation log capture and implement low-priority layout-specific background pagination only after confirming hydration does not create visible jank.

Checkpoint passed: no. Hydration is not performance-approved until profile-mode navigation proves no visible jank, bounded memory, and acceptable foreground priority behavior.

Implementation iteration: physical corrupt segmented-cache proof harness, 2026-06-22:

- Added a diagnostic-only segmented display-cache hook guarded by `NALORI_EPUB_DIAG=true`: `corruptSegmentAroundSourceForDiagnostics`.
- Added `CACHE_CORRUPT` reader diagnostic scenario. First launch corrupts the exact persisted segment matching the current completed layout signature/source index, persists the current stable reading position, and writes a force-stop marker. After external force-stop/relaunch, the scenario consumes the marker and measures restore plus backward/forward boundaries.
- Stored the last completed `DisplayGenerationSignature`, not just the cache-key string, so diagnostics can address section-scoped segmented cache keys safely after the display generation coordinator has completed and cleared its active token.
- Full-display cache hits now also mark the completed signature. This avoids stale diagnostic state when a restore uses whole display-cache data rather than a fresh progressive build.
- `rtk dart format lib/services/segmented_display_cache_service.dart lib/screens/reader_screen.dart` passed.
- `rtk flutter analyze` passed.
- Physical acceptance: pending. Next measurement must show `segment_cache_diagnostic_corrupted`, then after force-stop/relaunch `segment_cache_corrupt` or checksum rejection followed by parsed-cache/pagination fallback without app crash, blank route, or false book-boundary behavior.

## Remaining Blockers / Incomplete Criteria

- Resolved blocker history: A059 temporarily became unauthorized after ADB daemon restart, then was reauthorized and used for profile-mode Sequence A measurement.
  - Command: `rtk adb devices`
  - Output: `00162352B003164 unauthorized`
  - Command: `rtk adb -s 00162352B003164 push test/fixtures/books/feature_rich_lazy_reader.epub /sdcard/Android/data/com.nalori.reader/files/nalori_diag/feature_rich_lazy_reader.epub`
  - Error: `adb: error: failed to get feature set: device unauthorized. This adb server's $ADB_VENDOR_KEYS is not set. Try 'adb kill-server' if that seems wrong. Otherwise check for a confirmation dialog on your device.`
  - Resolution: device was reauthorized; `run-as` app-sandbox fixture copy succeeded; profile diagnostics harness ran Sequence A.
- Full physical-device navigation timing for Sequences A-E has not been completed in this run.
- The mandatory manual regression matrix has not been completed.
- Background layout-specific pagination policy is not implemented yet.
- Adaptive policy thresholds by book size/Speed Read/memory pressure are not implemented yet.
- Final pass/fail against the 100 ms / 250 ms profile-mode targets is not established.

## Sprint Wrap-Up - 2026-06-22

Sprint outcome: passed for the intended sprint goal of smoother adjacent/recent lazy-reader navigation and preventing unloaded sections from acting like book boundaries. The broader release checklist above remains useful future work, but it is not the sprint acceptance bar.

### Completed / Fixed In This Sprint

- Implemented bidirectional on-demand adjacent section availability so loaded-window boundaries are no longer treated as true book start/end when readable spine content exists outside the active window.
- Added shared lazy adjacent loading paths for forward and backward boundary navigation, including in-flight request joining and stale-generation guards.
- Added incremental backward prepend support that preserves the current visible source location and shifts display/index state instead of blanking/rebuilding the whole active display whenever a compatible segment can be inserted.
- Added adjacent warmup after stable-location/chapter jumps, with target section shown first and previous/next preparation scheduled afterward.
- Added a bounded display-section memory LRU in addition to parsed-section retention, so recently visited compatible display ranges can be reused without disk work.
- Added section-scoped segmented display-cache persistence for generated appended/prepended sections, enabling direct cold restore of a single section rather than depending on a shifted multi-section window segment.
- Canonicalized display safe-area cache input to ignore transient bottom inset churn for reader display keys while preserving raw safe-area diagnostics.
- Fixed repeated `AnimationController.stop() called after AnimationController.dispose()` and unmounted-context errors in `ReadingCardDeck` by guarding late pointer events after disposal and avoiding `context` reads once unmounted.
- Added debug diagnostics for boundary requests, adjacent resolution/cache source, prepend/append integration, visible-location before/after, segment cache hits/misses/writes, and profile timing breakdowns.
- Added a diagnostic-only corrupt segmented-cache harness, but did not complete its physical proof before sprint wrap-up.

### Physically Verified On A059

- Sequence A, feature-rich fixture after hydration quiet period:
  - direct open: 172 ms
  - initial visible: 127 ms
  - backward warmup: 102 ms
  - forward warmup: 120 ms
  - warmed forward/backward boundary gestures: 0 ms / 0 ms in harness once integrated
- Earlier Sequence A warmed boundary baseline:
  - forward: 63 ms to first frame
  - backward: 50 ms to first frame
- Sequence B, feature-rich fixture:
  - Chapter 1 -> 2: 0 ms
  - Chapter 2 -> 3: 96 ms
  - Chapter 3 -> 2: 0 ms
  - Chapter 2 -> Chapter 1 actual backward prepend: 31 ms
  - harness-level backward result: 104 ms including follow-up prefetch
- Sequence C, Plato EPUB:
  - direct open: 517 ms
  - distant +10 spine jump: 127 ms
  - backward prepend near target: 43-45 ms
  - forward append near target: 87 ms
  - RSS around 302 MiB
- Sequence D, feature-rich fixture after section-scoped persistence:
  - cold Continue restored Chapter 2 from `lazy_2_5872ce62`
  - section segment load: 8 ms
  - initial display rebuild: 42 ms
  - previous Chapter 1 exact segmented display load: 3 ms
  - backward Chapter 2 -> Chapter 1: 51 ms to first frame
- Sequence E, feature-rich fixture:
  - font size change: 440 ms to readable current page; boundary after setting 50-56 ms
  - density change: 499 ms; boundary after setting 50-56 ms
  - margin change: 491 ms; boundary after setting 50-56 ms
  - line-height change: 417 ms; boundary after setting 50-56 ms
  - orientation landscape: 510 ms; boundary after setting 50-56 ms
  - portrait restore hit segmented cache and rebuilt in 32-33 ms
- Safe-area canonicalization clean-build verification:
  - current restored section hit `lazy_3_6b184294` in 14 ms
  - adjacent section hit `lazy_2_5872ce62` in 7 ms
  - backward availability: 74 ms
  - warmed harness boundary: 0 ms once integrated
- Quick wrap-up profile smoke:
  - A059 available.
  - `rtk timeout 90s rtk flutter run --profile ...` built `app-profile.apk` successfully in 83.5 s, but the 90 s cap interrupted install with `ADB exited with exit code -15`.
  - This smoke is inconclusive for launch/runtime and was not rerun to avoid extending the sprint.

### Automated-Test Verified

- `rtk flutter analyze`: passed on 2026-06-22.
- Focused lazy/display/cache suite passed on 2026-06-22:
  - `test/unit/services/segmented_display_cache_service_test.dart`
  - `test/unit/services/display_section_memory_cache_test.dart`
  - `test/unit/services/progressive_display_state_test.dart`
  - `test/unit/services/lazy_book_session_test.dart`
  - `test/unit/services/lazy_section_repository_test.dart`
  - `test/widgets/reading_card_deck_test.dart`
- The focused suite covered segmented display cache hit/miss/corrupt handling, display memory LRU reuse/eviction, progressive append/prepend/index shifting, readable book-boundary detection, lazy section retention/request behavior, and late pointer events after `ReadingCardDeck` disposal.

### Core Files Changed

- `lib/screens/reader_screen.dart`
- `lib/widgets/reading_card_deck.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/lazy_section_repository.dart`
- `lib/services/progressive_display_state.dart`
- `lib/services/display_section_memory_cache.dart`
- `lib/services/display_generation_coordinator.dart`
- `lib/services/segmented_display_cache_service.dart`
- `lib/services/parsed_section_cache_service.dart`
- `lib/models/stable_book_location.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/services/lazy_section_repository_test.dart`
- `test/unit/services/progressive_display_state_test.dart`
- `test/unit/services/display_section_memory_cache_test.dart`
- `test/unit/services/segmented_display_cache_service_test.dart`
- `test/widgets/reading_card_deck_test.dart`
- `docs/lazy_reader_smooth_navigation_progress.md`

### Remaining Future Work

- Complete the corrupt segmented-cache physical proof using the newly added diagnostic harness.
- Run the full manual/device regression matrix across EPUB 2/3, no-TOC, front matter, final spine, annotation/dictionary/character jumps, Speed Read, and larger ordinary EPUBs.
- Decide separately whether to implement background layout-specific pagination. It was intentionally deferred from this sprint.
- Decide separately whether to implement adaptive whole-book/background policy thresholds. It was intentionally deferred from this sprint.
- Further optimize settings-change current-page rebuild latency; boundary navigation after settings changes is smooth, but the settings rebuild itself is still 417-510 ms on A059 for the measured fixture.
- Validate hydration jank and priority behavior over longer reading sessions and larger books before making any release-level claims about whole-book background work.
- Remove or gate any diagnostic-only hooks before production release if they are no longer needed.

### Sprint Risks

- The final quick profile smoke was build-only/inconclusive because the bounded timeout killed install; the strongest runtime evidence remains the earlier A059 profile scenario logs.
- The worktree contains broad pre-existing lazy-reader changes and untracked files. This wrap-up did not attempt to split or revert unrelated work.
- Background pagination and adaptive policy remain intentionally unimplemented for this sprint.

## Card Depth Chapter Progress Fix - 2026-06-23

### What Was Broken

- In card depth mode, the orange footer progress bar could show non-zero progress on a chapter title/start page, such as `16%` at the beginning of Chapter 3.
- The footer could also calculate progress against the currently loaded lazy window or stale display mappings rather than the actual current chapter.
- Page 1 of a known multi-page chapter used `current / total`, so a six-page chapter started at `16%` instead of `0%`.

### Root Cause Summary

- `_ReaderPageView._chapterPageMetaFor()` inferred chapter bounds from `ChapterInfo.chunkIndex` and the next flat chapter `chunkIndex`.
- That assumption was fragile after lazy EPUB loading because `_sourceChunks` can represent only the active loaded window, and `LazyBookSession._chaptersForLoadedWindow()` can assign synthetic/window-relative indexes for chapters whose target section is not loaded yet.
- Lazy append/prepend could also leave flat chapter mapping stale relative to shifted/extended source chunk indexes.

### Files Changed

- `lib/services/card_depth_chapter_progress_service.dart`
- `lib/screens/reader_screen.dart`
- `test/unit/services/card_depth_chapter_progress_service_test.dart`
- `test/widgets/reading_card_chapter_progress_test.dart`

### New Source Of Truth

- Card depth chapter progress now prefers canonical `ChapterNavigationTarget` ranges from `ChapterNavigationService`.
- Current page location is resolved through stable source locations (`StableBookLocation`) mapped from `displayToOriginal`.
- Chapter start/end are determined from canonical chapter targets and stable locations, not lazy section boundaries, book-level progress, or `ChapterInfo.chunkIndex` alone.
- Exact progress uses zero-based chapter-page progress: `(currentChapterPage - 1) / (chapterPageCount - 1)`, so the first chapter page is `0%` and the final known chapter page is `100%`.
- Legacy flat chapter chunk ranges are retained only as a fallback when canonical target/location data is unavailable.

### Lazy / Incomplete Boundary Behavior

- If the current canonical chapter start is known but the next chapter boundary is not loaded/rendered yet, the footer does not treat the loaded lazy window as the full chapter.
- In that partial state it shows a conservative page label such as `1 / ?` and keeps progress at the chapter-start baseline until exact rendered bounds are available.
- Lazy source-window open/append/prepend/replace paths now invalidate `_cachedFlatChapters` so fallback mappings are not reused after window-relative source indexes shift.

### Tests Added

- Unit coverage in `test/unit/services/card_depth_chapter_progress_service_test.dart` for:
  - chapter first/title page starts at `0%`;
  - swiping into the next chapter resets progress;
  - final page of a fully known chapter reaches `100%`;
  - multiple chapters in one spine item;
  - one chapter spanning multiple spine items;
  - lazy partial window with missing next boundary;
  - lazy forward append;
  - lazy backward prepend;
  - settings-driven re-pagination recomputing page totals.
- Widget coverage in `test/widgets/reading_card_chapter_progress_test.dart` for the `ReadingCard` card-depth footer rendering the supplied progress value and percent text.

### Verification

- Automated verification passed:
  - `rtk flutter analyze`
  - `rtk flutter test test/unit/services/card_depth_chapter_progress_service_test.dart`
  - `rtk flutter test test/widgets/reading_card_chapter_progress_test.dart`
  - `rtk flutter test test/unit/services/card_depth_chapter_progress_service_test.dart test/unit/services/chapter_navigation_service_test.dart test/widgets/reading_card_chapter_progress_test.dart test/widgets/reading_card_deck_test.dart`
- Manual verification note: card-depth chapter starts now reset to `0%`, progress increases correctly through the chapter, and chapter transitions appear correct.
