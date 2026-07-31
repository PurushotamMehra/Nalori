# Nalori Lazy Random-Access Reader Progress

## Overall Status

- Overall state: Phase 5 complete (host-side implementation and verification)
- Current phase: Physical-device/profile validation before Phase 6
- Last updated: 2026-07-14
- Source plan: `docs/lazy_random_access_reader_plan.md`
- Evidence:
  - `docs/epub_parsing_system_audit.md`
  - `docs/lazy_random_access_reader_verification.md`

## Product Decisions

These are current defaults that may be adjusted through measured profiling; they are not immutable constants.

- Parsed source-cache budget: **192 MiB**
- Display-cache budget: **48 MiB**
- Budgets must be configurable and adaptable under low-storage conditions.
- Cold parsed sections remain until byte pressure rather than expiring on a fixed timer.
- Last-access eviction is used for cold parsed sections.
- Obsolete and cold display layouts are evicted before parsed source sections.
- The active book receives the highest cache protection.
- The two most recently meaningfully read books receive secondary parsed-cache protection.
- Entire sessions and entire books must not be retained in memory.
- Percentage jumps may initially use weighted approximate structural progression and refine after the target section is parsed.
- Book Memory may display clearly labelled partial indexing coverage while background preparation continues.
- Legacy positions, bookmarks and annotations should migrate automatically after successful stable resolution.
- Legacy fields remain temporarily as fallback during the migration period.
- Partial Card Mode progress such as `n / ?` is acceptable.
- Exact Card Mode chapter totals must not trigger broad foreground parsing or pagination.

## Phase Status

| Phase | Status | Started | Completed | Exit Criteria Met | Notes |
|---|---|---|---|---|---|
| Phase 1 — Stop avoidable legacy work safely | Complete | 2026-07-11 | 2026-07-11 | Yes | Explicit legacy and Book Memory preparation retained; normal refresh no longer queues whole books. |
| Phase 2 — Persistent structural index | Complete | 2026-07-11 | 2026-07-11 | Yes | Existing `LazyEpubIndex` is persisted and reused after validity checks. |
| Phase 3 — Stable random-access navigation | Complete | 2026-07-12 | 2026-07-12 | Yes | All reader destinations resolve through publication-aware stable source targets and direct section loading. |
| Phase 4 — Shared section work and cache retention | Complete | 2026-07-13 | 2026-07-13 | Yes | Cross-session section jobs, coordinated schema-v2 parsed cache, byte retention tiers, and deletion generations implemented. |
| Phase 5 — ReaderScreen and Card Mode responsiveness | Complete | 2026-07-13 | 2026-07-13 | Yes | Bounded section-aware source ownership, target-first display publication, byte-budgeted display retention, and partial structural Card progress implemented. |
| Phase 6 — Search and Book Memory migration | Not started | — | — | No | Depends on stable destinations and section validity. |
| Phase 7 — Legacy retirement | Not started | — | — | No | Requires evidence that all production consumers have migrated. |

## Phase 1 Checklist

- [x] Remove automatic whole-library preparsing from normal library refresh.
- [x] Add explicit preparation outcomes for cached, stored, terminal oversized, and retryable failure states.
- [x] Persist an oversized terminal status so unchanged files are not retried.
- [x] Add a lightweight validity probe that does not deserialize `CachedBook` payloads.
- [x] Invalidate preparation outcomes and caches when file identity, cache limit, or format/version changes.
- [x] Preserve explicit legacy reader compatibility through `BookLoadingScreen`/`BookPreparseService`.
- [x] Preserve explicit Book Memory compatibility while it still depends on `CachedBook`.
- [x] Coordinate cache, outcome, deletion, and reset cleanup for Phase 1-owned data.
- [x] Add and run focused Phase 1 tests.
- [x] Run `flutter analyze`.
- [x] Run `git diff --check` and inspect the scoped diff.

## Completed Work

- EPUB parsing system audit completed in `docs/epub_parsing_system_audit.md`.
- Lazy random-access architectural verification completed in `docs/lazy_random_access_reader_verification.md`.
- Phase 1 implemented and verified on 2026-07-11.

Phase 1 removed the normal-library-refresh `BookPreparseService.queueBooks` submission. The singleton service and its explicit queue API remain for diagnostics, tests, and other deliberate callers.

`BookPreparseService.ensureParsed` now returns `BookPreparationResult` with `alreadyCached`, `stored`, `tooLarge`, or `failed`. Cache hits are probed first; background callers that only need validity do not load or deserialize `CachedBook`. Foreground legacy loading obtains the payload only when it is valid and needed. A known oversized result returns `tooLarge` without reparsing.

`BookCacheService` now persists `preparation_manifest.json` next to the existing whole-book manifest and payloads. Each record stores the outcome, book ID, EPUB size, modification time, serialized size, applicable cache limit, whole-cache format version, and preparation-version owner. The lightweight `probeBook` result distinguishes valid payload, no cache, stale, known too large, missing payload, corrupt metadata, and unsupported version. Changed file evidence, cache-limit changes, format/preparation-version changes, missing payloads, `deleteCachedBook`, and `clearAll` invalidate or clear the record.

Book Memory now explicitly requests preparation only for its own `bookFile` when it needs its temporary `CachedBook` compatibility data. A `tooLarge` result leaves its existing partial/unavailable snapshot path in place; repeated access rechecks the durable outcome and does not repeat the EPUB parser work. The legacy foreground route reports a controlled unavailable error for a known oversized book rather than claiming it was cached.

Phase 2 persists the existing `LazyEpubIndex` in schema-versioned JSON under the app documents `lazy_epub_indexes` directory. A record includes publication SHA-256 fingerprint, file size and modification time, manifest/spine/chapter hierarchy, normalized href maps, chapter-to-spine resolution status, linear state, per-spine structural weights and prefix weights, total readable weight, source checksums, and TOC warnings. The live `EpubBookRef` and archive content references are deliberately not serialized.

On a valid reopen, the service opens the live archive only to obtain resource references, then reuses the persisted manifest/spine/TOC map without calling the structural index builder. A changed fingerprint, file evidence, schema version, missing/corrupt JSON, or unsupported record causes a safe rebuild and replacement. Storage is deliberately opportunistic: an unavailable persistence directory does not prevent the existing lazy-open path from functioning.

Phase 3 upgrades `StableBookLocation` to schema v2 with publication fingerprint, normalized href, section and weighted-publication progression, and parsed-source version evidence. `LazyBookSession.resolveStableLocation` now returns explicit confidence and reason data and applies the canonical ranked order: publication/section identity, anchor or stable source identity, source offset, unique quote plus surrounding context, in-section progression, weighted publication progression, then legacy local indexes only as migration hints. Logical-book or publication mismatches are rejected before section parsing. Ambiguous quote-only targets remain unresolved.

`ReaderOpenService`, `BookLoadingScreen`, and `ReaderScreen` now use this resolver for last-read restore, chapters, internal links, bookmarks, highlights, notes, saved words, history Back, and weighted percentage jumps. A target resolver loads the requested XHTML section directly; distant and backward navigation does not parse intermediate sections. Relative cross-section links are normalized against the current section. Internal-link navigation records a stable return point, so footnote return and Back survive lazy-window replacement. Stable history JSON is additive to the existing legacy SharedPreferences fields.

Successful legacy last-read, bookmark, highlight/note, and saved-word resolution persists the stable replacement while preserving original indexes, offsets, text, and other legacy fields. Ambiguous quote recovery is navigable only when a lower-confidence progression exists, but is not automatically persisted as an exact migration. Same-filename publication replacement rejects the stale fingerprint and starts from the new publication's meaningful initial target without reusing the old legacy percentage.

The post-Phase 3 annotation smoke-test regression is fixed at the render boundary. Persisted annotations deliberately retain legacy `originalChunkIndex`, but `_ReaderPageView` previously filtered and mapped every decoration only through that field. Lazy target-window replacement reindexes source chunks, so a correctly resolved stable annotation could disappear or decorate an unrelated equal-offset range until a later card/layout rebuild. ReaderScreen now projects stable annotation identity (`bookId`, publication when available, spine index, and local chunk index) onto the active source-window index before building cards. The projection is ephemeral: persisted annotations and display/source caches are unchanged, existing display chunks are redecorated without XHTML parsing or pagination, and one migrated record produces one visual record.

## Phase 3 Checklist

- [x] Extend stable locations with publication, normalized section, source-parser, section-progression, and weighted-publication evidence.
- [x] Implement ranked, publication-aware resolution with explicit confidence and reason.
- [x] Reject logical-book and publication-fingerprint mismatches before target loading.
- [x] Integrate the resolver into ReaderScreen stable navigation.
- [x] Restore and persist stable last-read positions automatically.
- [x] Navigate chapters, anchors, internal cross-section links, bookmarks, highlights, notes, and saved words through stable targets.
- [x] Persist successful legacy migrations while retaining legacy fields.
- [x] Preserve unresolved and ambiguous legacy evidence.
- [x] Persist stable Back/history state and record stable footnote return points.
- [x] Use Phase 2 structural weights for percentage jumps.
- [x] Verify direct backward and distant unloaded-section navigation.
- [x] Cover parser-version/chunk-count fallback and same-filename replacement safety.
- [x] Run focused Phase 3 and affected lazy-reader regression tests.
- [x] Run `flutter analyze` and `git diff --check`.

## Phase 4 Checklist

- [x] Join identical parsed-section work across reader sessions by complete stable identity.
- [x] Promote queued shared work when a P0-P2 owner joins speculative work.
- [x] Separate owner interest, queued cancellation, launched non-preemptible parsing, and atomic commit behavior.
- [x] Serialize parsed payload/manifest mutation across service instances and use unique temporary paths.
- [x] Upgrade parsed payloads/manifests to cache schema v2 with publication, dependency, parser, byte-size, status, and access identity.
- [x] Safely miss and remove schema-v1 records whose publication identity cannot be proven.
- [x] Enforce a configurable 192 MiB default parsed-source budget using actual payload bytes.
- [x] Evict corrupt/orphaned data first and valid cold records by persisted last access.
- [x] Protect the active publication, current/adjacent sections, and active P0-P2 work.
- [x] Protect the two most recently meaningfully read books and useful last-visible/adjacent sections secondarily.
- [x] Add injectable low/critical storage pressure with smaller effective budgets and speculative-work gating.
- [x] Add `lastOpenedAt` and `lastMeaningfulReadAt` with conservative legacy migration.
- [x] Coordinate parsed, segmented-display, whole/display, hydration, structural-index, and shared-job deletion/reset generations.
- [x] Preserve annotations, saved words, bookmarks, notes, and stable locations in cache-only cleanup.
- [x] Run focused Phase 4, Phase 2 structural, Phase 3 navigation/annotation, cache, and host-side regression tests.
- [x] Run `flutter analyze` and `git diff --check`.

## Phase 4 Completed Work

`SharedLazySectionWorkCoordinator` now extends the repository's existing priority path into a process-wide queue. Its key is the complete `LazySectionIdentity`: logical book ID, publication fingerprint, spine index, normalized href, full path, source checksum, parser version, dependency schema version, and dependency signature. The dependency signature is conservatively publication-wide because current parsed output can embed linked images and footnote content; it combines the publication fingerprint, dependency schema version, and normalized manifest resource inventory. A changed publication, source checksum, parser version, dependency signature, or schema therefore cannot join stale work.

Owners join one future and may promote queued work. P0 explicit navigation, P1 visible work, P2 adjacent/boundary work, P3 preview, P4 current-book hydration, P5 recent retention, and P6 derived/layout work retain the plan's ordering. An owner leaving removes only its interest. A queued speculative job with no owners is cancelled before launch; a launched parse is allowed to finish because the current isolate parse is not safely preemptible; an atomic reusable cache commit finishes unless a deletion generation invalidates it. Failures remove the shared entry and a later request retries. Repository close stops new hydration scheduling, releases its owner, and keeps the launching archive handle only until already-launched work settles; no session or whole book is retained as a cache.

`ParsedSectionCacheService` now uses one process-wide file coordinator per physical cache root. Serialization may happen outside the critical section, but payload rename, manifest read-modify-write, hydration completion, access touch, eviction, deletion, and reset mutation are serialized. Payload and manifest temporary filenames are unique per process operation. The ready manifest record is published only after the flushed payload validates and is atomically renamed. Per-book and global generations/tombstones reject stale writes after delete/reset. Concurrent same-identity writers converge on one record; different-section writers merge into the manifest union.

Parsed cache schema v2 persists publication fingerprint, spine index, href, normalized href, full path, XHTML checksum, parser version, cache schema version, dependency signature/schema, resource hrefs, payload checksum and actual byte size, created/updated time, last-access time, and ready status. Hydration identity now includes publication and dependency evidence. Schema-v1 manifests cannot prove publication compatibility, so they miss and their cache-only directory is removed rather than blindly migrated. Missing, size-mismatched, corrupt-manifest, temporary, and orphaned derivatives are repaired or removed without deserializing every valid section.

The parsed-source budget defaults to 192 MiB through `ParsedSectionCachePolicy` and is injectable. Normal accounting sums actual payload file sizes from lightweight manifests/stat calls. Cache hits update `lastAccessedAtMs` at most once per record per five minutes by default; the clock and interval are injectable, and tests set the interval to zero when deterministic ordering is required. Budget enforcement runs after writes, on repository open/close, and through explicit policy calls. Atomic writes may briefly exceed the budget, then enforcement settles usage. Active-nearby data may remain as a narrowly controlled protected overage if it alone exceeds the effective budget.

Retention tiers are byte-aware. Active target/adjacent identities and P0-P2 work are hardest-protected; the remaining active publication sorts behind them but ahead of recent/cold data. The two newest `lastMeaningfulReadAt` books receive secondary protection, with their last-visible and adjacent identities protected more strongly when a live session has supplied them. Other valid records stay cold and remain until pressure, then evict least-recently-used first. Low storage halves the configured budget, keeps one recent book, and blocks P4-P6 scheduling; critical pressure uses one quarter of the budget, removes secondary recent-book protection, and blocks all speculative priorities. The policy and pressure provider are host-testable and do not query physical storage directly.

`BookMetadata` now stores `lastOpenedAt` separately from `lastMeaningfulReadAt`. Existing records migrate `lastReadTime` into meaningful recency only when legacy progress or a stable last-read location proves reading; import-only metadata is not promoted. Successful reader open updates `lastOpenedAt`, while committed reading-position persistence updates meaningful recency and the last-visible retention identity.

`LazyReaderCacheCleanupService` is the coordinated cache-only deletion/reset path. It invalidates shared jobs first, then removes parsed payloads/manifests/hydration/temp files, segmented display derivatives, whole/display cache derivatives, and the Phase 2 structural index. Parsed, segmented, and structural writers use process-wide generations so stale work cannot recreate deleted records. Cache cleanup deliberately does not call bookmark, highlight/note, saved-word, metadata-location, or other user-data services. The existing explicit product book-delete action still owns its pre-existing user-data deletion semantics, then invokes this derivative transaction.

## Phase 5A Checkpoint — Complete

Phase 5A completed on 2026-07-13. `LazyBookSession` is now the authoritative owner of a configurable active-and-nearby parsed-section window. The default retains the current readable spine item plus one readable neighbor in each direction, for a maximum of three loaded source sections. Distance is calculated in readable-spine order rather than raw spine-index arithmetic, so non-linear items do not distort retention. Every committed visible source location recenters the session, releases cold sections, and updates repository pins. ReaderScreen reconciles its copied source window with the authoritative session window whenever adjacent loading reveals an eviction; distant replacement continues to use the same bounded window.

Every loaded window now carries a bidirectional `LazySourceChunkIdentity` mapping. Identity includes the complete `LazySectionIdentity` (logical book, publication fingerprint, spine index, href, normalized href, full path, source checksum, parser version, and dependency identity) plus the section-local source chunk index. Window-relative integer indexes remain pagination coordinates only. Append/prepend projection now retains publication, normalized href, checksum, parser, and local identity; it no longer writes a window-relative value into `legacyGlobalChunkIndex`.

Lazy position persistence writes the stable source location and meaningful-read retention data without overwriting legacy whole-book `lastReadIndex` or `totalChunks` with current-window values. The legacy SharedPreferences integer is likewise no longer rewritten by the lazy route. Stable annotation projection verifies publication, normalized section, checksum, spine, and local chunk identity. An annotation without a stable location is rendered in a lazy window only when its stored offsets reproduce its exact stored text, preventing a same-length range from appearing on unrelated content while preserving verifiable legacy annotations. Existing `ChunkSourceRange` projection remains the selection/highlight offset authority across split and merged display chunks.

Phase 5A files changed so far:

- `lib/services/lazy_parsed_book.dart`
- `lib/services/lazy_book_session.dart`
- `lib/screens/reader_screen.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/screens/reader_annotation_projection_test.dart`
- `docs/lazy_random_access_reader_progress.md`

Phase 5A focused verification:

- Session, structural index, feature-rich navigation/link/footnote, annotation projection, coordinated cleanup, parsed cache, and shared-work suites — 63 passed.
- Stable-location, bookmark, highlight/note, saved-word/dictionary, reader-open migration, Card progress, display-memory, and split/merge selection/render suites — 93 passed.

Phase 5A risks carried into 5B/5C: ReaderScreen still clears display state during some bounded-window replacements, segmented display retention still uses its pre-Phase-5 fixed budget/write-recency policy, and Card Mode still has the forced next-chapter-boundary completion path. These are the explicit ownership of checkpoints 5B and 5C, not unresolved 5A identity defects.

## Phase 5B Checkpoint — Complete

Phase 5B completed on 2026-07-13. Lazy display generation now paginates the single source chunk containing the requested stable target first and publishes that replacement before forward/back nearby range preparation. Distant navigation and bounded source eviction retain the previously published card, its source-identity snapshot, and its decorations while the replacement is prepared. The retained card is made non-interactive during the handoff, so old display coordinates cannot be persisted against the new source window. A valid cached target range can still publish immediately. Every publication and cache write remains guarded by the active `DisplayGenerationToken`; identical signatures join, replacement signatures cancel the old owner, and stale/cancelled work cannot publish or commit.

Typography, density, spacing, margin, Card Mode, viewport, safe-area, orientation, and text-scale changes remain display-only. ReaderScreen preserves the stable source anchor, retains the parsed source window, changes only layout-dependent state, and uses the same target-first publication path. The focused setting matrix covers font size, family, weight, line height, paragraph spacing, side margin, content density, and Card Mode; viewport/text-scale/safe-area participate in the generation signature. No settings path calls `LazyBookSession.loadSection`, the XHTML parser, or an unrelated source reload. Annotation/character decoration uses the published source snapshot, so styling changes do not require a typography toggle to refresh.

`SegmentedDisplayCacheService` is now schema v2. Its default `SegmentedDisplayCachePolicy` budget is configurable and defaults to 48 MiB. Accounting uses actual non-temporary files on disk. Each segment persists and updates `lastAccessedAtMs`. Enforcement removes corrupt/orphaned derivatives, then obsolete layouts before current layouts, then cold ranges by last access. Active visible/nearby ranges are protected; a secondary recent-range API is available and is dropped under low/critical pressure. Low storage uses half the configured budget and critical storage one quarter. Display retention is independent from the parsed-source format and budget. When parsed-source pressure would evict source records, the production default first asks the display cache to enforce its derivative budget. Cleanup generations and per-book/reset deletion remain the Phase 4 coordinated paths and cannot delete annotations, locations, parsed source, or other user data.

Schema/migration behavior: segmented display format version 1 records are incompatible disposable derivatives and miss safely; an incompatible layout/version directory is deleted and regenerated. No parsed-source, structural-index, stable-location, annotation, or user-data schema changed in 5B.

Phase 5B files added to the Phase 5 change set:

- `lib/services/segmented_display_cache_service.dart`
- `lib/services/parsed_section_cache_service.dart`
- `test/unit/services/segmented_display_cache_service_test.dart`
- `test/unit/services/parsed_section_cache_service_test.dart`
- `test/reader_layout_metrics_test.dart`

Phase 5B focused verification:

- Segmented display budget/LRU/obsolete/protection/low-storage, parsed-before-display eviction ordering, display generation cancellation/join, progressive range scope, display-memory, settings matrix, Phase 5A source ownership/annotation, and coordinated cleanup suites — 98 passed.
- An earlier display-only focused run covering segmented cache, generation ownership, progressive state, settings, and Card boundary priority — 48 passed before the full 5B checkpoint command.

Phase 5B residual risk owned by 5C: the Card progress path still requests next-chapter-boundary work for an exact denominator, and global/chapter UI still needs to be made explicitly structural when a lazy display range is partial.

## Phase 5C Checkpoint — Complete

Phase 5C completed on 2026-07-13. Card Mode's immediate rendering contract remains the deck's current card, two forward depth cards, and one previous card only while a backward gesture needs it. The lazy display path publishes the target-containing source chunk first, then prepares forward depth/swipe content, then backward readiness. Normal boundary readiness may load the adjacent readable section; no chapter-total path may request source or display work. Distant chapter jumps therefore enter Card Mode through the same direct target-section replacement used by stable navigation, without parsing intermediate sections.

The former `_maybeRequestCardDepthChapterCompletion` / `_completeCardDepthCurrentChapterBoundary` path and its P0 `card_depth_current_chapter_boundary` work have been removed. `CardDepthChapterPageMeta` no longer advertises a completion-work request. Exact Card totals are produced only when a rendered, usable structural next-chapter boundary proves the complete contiguous display range for the current layout, or on the explicitly complete legacy eager route. A locally complete lazy display window is never proof of a final chapter. Missing/unresolved TOC structure and final chapters without proven completion remain `n / ?`, with the provisional rail capped below 100%; no parser or paginator starts solely to replace `?`.

Global lazy progress now comes from `StableBookLocation.publicationProgression`, which is Phase 2 readable-spine prefix weight plus the refined current section/source position. The lazy scrubber uses the current stable weighted progression rather than only the spine prefix. Current display source ranges contribute their original text offset when a source chunk was split into cards. Loaded source/display counts do not participate in lazy publication progress, page totals, jump dialogs, or completion-overlay eligibility. A bounded lazy window can report 100% or book completion only when the stable weighted location itself proves the publication end and no readable section remains.

Chapter title and progress continue to use stable structural chapter targets. When both current and next targets provide weighted or same-section progression, partial chapter rail progress interpolates between those source boundaries. Exact display-card totals remain layout-scoped and require the next target to be rendered contiguously. Missing/malformed structure degrades to `Current chapter`, `n / ?`, or unknown global progress instead of a false loaded-window total.

Phase 5C files added to the Phase 5 change set:

- `lib/services/card_depth_chapter_progress_service.dart`
- `lib/services/reader_structural_progress_service.dart`
- `test/unit/services/card_depth_chapter_progress_service_test.dart`
- `test/unit/services/reader_structural_progress_service_test.dart`
- `test/unit/screens/reader_card_depth_lazy_completion_test.dart`
- `test/widgets/reading_card_deck_test.dart`

Phase 5C focused verification:

- Card denominator policy, structural global/chapter progress, bounded deck composition, Card footer, progressive ranges, and annotation projection — 53 passed.
- Expanded Card/depth/boundary, settings, selection/note, annotation, session/navigation, bookmark/highlight/saved-word, chapter-panel, and malformed-structure regression command — 186 passed.

Phase 5 exit criteria: all canonical host-verifiable Phase 5 criteria are met. Phase 5A, 5B, and 5C are independently green; the combined Phase 2–5 affected regression command passed. No Phase 6 search or Book Memory derived-index work, giant-XHTML subdivision, legacy cache retirement, parallel reader, or Phase 7 work was started.

## Phase 5 Device-Validation Follow-up — Host Fix Complete

Physical-device validation on 2026-07-13 found three focused regressions after the original host-side Phase 5 checkpoint:

1. A successful weighted jump to roughly 80% returned to a library card still showing roughly 10%.
2. Chapter/Card progress near a loaded lazy-section boundary temporarily treated that boundary as the chapter end until the adjacent section arrived.
3. A distant scrubber jump visibly replaced the old card with the full themed `Preparing pages…` state, sometimes more than once, before the target card published.

### Exact root causes

- **Global/library progress:** `ReaderScreen` persisted `lastReadLocation`, but `BookListScreen` and the Home continue card still calculated their displayed/sorted progress exclusively from legacy `lastReadIndex` and `totalChunks`. Lazy navigation also entered the ordinary four-second exploratory-preview path after target publication, so leaving immediately could flush the previous committed position. In addition, manually appended/prepended lazy sections created `StableBookLocation`s without Phase 2 section/publication progression, so sequential positions in those sections could not persist a refined structural percentage.
- **Chapter/Card progress:** the normal `LazyLoadedContentWindow` location builder supplied weighted progression, but ReaderScreen's manual adjacent append/prepend builders did not. `CardDepthChapterProgressService` therefore fell back to its rendered-page ratio, whose denominator was the loaded display range. Same-XHTML chapter anchors also gained a resolved local chunk without adopting that chunk's refined structural progression. Finally, exact totals required a rendered next boundary but did not independently prove that the current chapter start boundary was present, allowing a clipped range to look complete.
- **Scrubber blank flash:** scrubber `onChanged` was already preview-only and `onChangeEnd` committed navigation, but stable target preparation had no independent latest-target generation before display generation began. A non-incremental backward lazy-window replacement still cleared `_displayChunks`, `_displayToOriginal`, and `_originalToDisplay`; that exposed ReaderScreen's full empty `Preparing pages…` branch. Navigation preparation and published display ownership were therefore not fully separated even though target-first pagination existed.

### Contracts after the fix

- **Global progress source of truth and persistence:** the canonical value is `lastReadLocation.publicationProgression`, derived from the successfully published/current stable source location. It uses the Phase 2 readable-spine prefix weight plus refined section/source progression and is clamped to `[0, 1]`. `ReaderStructuralProgressService.metadataForCommittedLocation` writes that location through the existing metadata last-read contract after successful stable navigation and ordinary committed reading. `BookMetadata.readingProgress` is the single library/Home read contract: structural progression first, legacy `lastReadIndex/totalChunks` only for unmigrated eager records. Failed or superseded requested targets are never passed to persistence; legacy fields remain compatibility data and lazy-window size does not participate.
- **Chapter/Card progress source of truth:** current stable weighted/source progression is interpolated between the structural current-chapter target and structural next-chapter target. Manual adjacent integration now uses `LazyBookSession.locationForSectionChunk`, so every integrated source chunk retains section and publication progression. Resolved same-section anchors adopt the parsed anchor location's refined progression. Unknown denominators remain `n / ?`; malformed/missing weighted boundaries fall back only to safe section progression (capped below 100%), never to loaded-card count. Exact `n / total` is allowed only when both the current chapter start and next chapter start are rendered for the same published layout, or on the explicitly complete legacy route. No parser/paginator request is made for a denominator.
- **Pending versus published navigation/display:** `ReaderNavigationPublicationCoordinator` owns a monotonically increasing pending target generation separately from `DisplayGenerationCoordinator`. `LazyBookSession.prepareNavigation` may resolve/parse a target but commits it as the session current window only while the caller still owns the latest generation. The old display arrays and published source/decorations remain untouched during preparation. Only the latest token can associate with and publish the target display snapshot; stale completion/failure cannot clear the old publication or a newer target. ReaderScreen marks the target published only from the target display swap, then moves the page controller and persists the resolved stable location. The remaining backward replacement clear was removed. The full `Preparing pages…` scaffold is now allowed only when no readable display has ever published; target preparation failure retains the old readable snapshot and exposes the existing controlled range failure state.
- **Scrubber event policy:** commit on release. `onChanged` updates only the weighted/chapter preview through `ReaderStructuralScrubCommitPolicy`; `onChangeEnd` yields at most one final navigation target. There is no live navigation per drag tick.

### Files changed by this follow-up

- `lib/models/book_metadata.dart`
- `lib/screens/book_list_screen.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/card_depth_chapter_progress_service.dart`
- `lib/services/chapter_navigation_service.dart`
- `lib/services/display_generation_coordinator.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/reader_structural_progress_service.dart`
- `test/reader_layout_metrics_test.dart`
- `test/unit/models/book_metadata_test.dart`
- `test/unit/services/card_depth_chapter_progress_service_test.dart`
- `test/unit/services/chapter_navigation_service_test.dart`
- `test/unit/services/display_generation_coordinator_test.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/services/reader_structural_progress_service_test.dart`
- `docs/lazy_random_access_reader_progress.md`

### Tests and results

- Focused metadata persistence, structural global progress, chapter/Card structural boundaries, chapter-anchor refinement, latest navigation publication, lazy-session ownership, ReaderScreen preparing-state, and scrubber commit-policy command — **94 passed** after the final scrubber-policy case was added.
- Full repository host regression suite, including stable navigation, annotations, Card deck/depth/boundaries, segmented display cache/generation, library metadata models, and Phase 2–4 suites — **685 passed** on the final worktree.
- `flutter analyze` — no issues found.
- `git diff --check` — passed.

The tests use explicit completion barriers for A -> B -> C publication ownership and session callbacks for superseded navigation. No timing sleep is used to establish correctness. Parser/paginator invocation remains absent from progress-denominator services by construction and the existing no-completion-work test remains green.

### Deviations, remaining runtime risks, and readiness

No canonical-plan contradiction was found, so the plan, verification report, and parsing audit were not changed. The follow-up adds no new persisted schema: canonical progress is read from the already persisted stable-location schema, with legacy integer fields retained. No Phase 6 work began.

Host tests still cannot prove real-device frame timing, filesystem latency, or OEM PageView scheduling. Giant-XHTML parse cancellation/subdivision remains deferred, as do Phase 6 whole-book search and Book Memory derived-index migration and Phase 7 legacy retirement. Phase 5 is again **host-verifiably ready for focused physical-device retesting**, but is intentionally unstaged, uncommitted, and not ready to advance to Phase 6 until those three device scenarios pass.

## Phase 5 Device-Validation Follow-up 2 — Host Fix Complete

Focused physical-device retesting on 2026-07-14 found three further regressions in the otherwise successful Phase 5 follow-up:

1. Some genuine final book pages persisted about 99%, and some genuine final chapter cards remained below 100% before the next chapter appeared.
2. Routine successful navigation and boundary preparation displayed short-lived floating `Preparing…`/ready status messages.
3. After a lazy section was integrated or evicted, an in-session display window could retain forward movement but lose its backward destination until the book was closed and reopened; the visible text could also be repaginated onto different card boundaries during that integration.

### Exact root causes

- **Terminal book progress:** ordinary progress and persistence deliberately used the published card's stable source **start**. That is correct for intermediate cards, but it cannot represent the unread portion covered by the final published card. The previous completion helper also required the bounded display window to be globally complete. A final lazy window can be structurally terminal while earlier publication sections are intentionally absent, so that display-completeness requirement prevented exact completion for some books. Resolved trailing empty spine sections and empty trailing source chunks could also obscure the last readable source boundary.
- **Terminal chapter progress:** `ReaderStructuralProgressService` interpolated the current card's source-start location between chapter targets, and `CardDepthChapterProgressService` correctly capped an unproven structural estimate below 100%. Neither service received proof that the published card's **source end** reached the next chapter anchor or publication end. The UI therefore left the prior chapter below 100%, then changed chapter identity as soon as the next chapter's first location became current.
- **Preparation notifications:** `_buildProgressiveBoundaryStatus` was rendered whenever forward, backward, or target preparation flags were set. It used the same floating status treatment for ordinary in-progress/successful work and actionable failures, so silent target-first publication still produced transient informational UI.
- **Backward trap and layout movement:** `ReadingCardDeck` defined previous availability solely as `currentIndex > 0`; at display index 0 it disabled the backward gesture callback, including for a one-card deck, even when `LazyBookSession` had a structural previous readable section. The normal page view likewise had no index-zero structural-backward request path. In addition, bounded-window eviction entered `_replaceLazySourceWindowForEviction`, discarded the prepared display mapping, and paginated the replacement range around the source anchor. That could split an unchanged visible source range differently and leave the controller index out of sync with the newly published deck. A non-incremental prepend also rebuilt prepared content unnecessarily when its first retained source range did not begin at window index zero.

### Contracts after the fix

- **Terminal global-progress proof:** normal progress remains the Phase 2 weighted progression of the current stable published source start. Exact `1.0` is substituted only by `ReaderPublishedCardBoundaryEvidence` when the successfully published card's effective source range reaches the final readable chunk of a resolved, complete section and `LazyBookSession` proves there is no next readable spine target. Resolved empty trailing chunks/sections are ignored; an unresolved, non-empty, or merely unloaded next section prevents proof. Loaded display index, bounded-window end, rounding, requested navigation percentage, and failed/cancelled targets do not participate. The proven terminal location is persisted immediately through the stable metadata contract, so Home and Book List read exactly `publicationProgression == 1.0`.
- **Terminal chapter-progress proof:** the published card's effective source end is compared with the structural next-chapter target. Completion is proven when it reaches the next same-XHTML anchor/source boundary, reaches the start of the structurally next readable section, or—only for the final chapter—satisfies the publication-terminal proof above. A chapter spanning multiple lazy sections cannot complete at an intermediate section edge. Structural progress may show 100% while the exact Card denominator remains `n / ?`; no parser or paginator runs to prove a denominator. Missing or malformed boundaries stay safely approximate and below 100%.
- **Notification policy:** routine scrubber/chapter navigation, target pagination, adjacent or backward section loading, display warmup, cache reuse, retries that succeed, and settings reflow are silent. The floating boundary status is rendered only for an explicit actionable failure, with its existing retry action where recovery is possible. Initial opening may still use the full preparing scaffold only before any readable snapshot has published.
- **Backward-readiness contract:** structural previous availability comes from `LazyBookSession`, independently of display index and child count. At index zero, both Card Mode and the normal reader can request structural backward preparation. The session reloads an evicted section through the parsed-section repository/cache, clears loading state on every success/failure path, and exposes retry only when an explicit backward attempt fails. A successful prepend publishes at least one valid previous display destination and synchronizes the controller to the preserved stable anchor.
- **Display-layout stability contract:** eviction reconciliation first remaps the contiguous prepared run containing the exact stable source anchor onto the authoritative replacement source window. It preserves each retained `BookChunk`'s text, split offsets, source ranges, decorations, and layout identity, then generates only missing neighboring ranges. If a retained card crosses an evicted source boundary or cannot be mapped completely, reconciliation refuses the remap and uses the existing atomic source-anchor regeneration fallback. Generation ownership still prevents stale work from replacing a newer deck, and controller movement occurs after the remapped or regenerated snapshot is ready.

### Files changed by this follow-up

- `lib/screens/reader_screen.dart`
- `lib/services/card_depth_chapter_progress_service.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/progressive_display_state.dart`
- `lib/services/reader_structural_progress_service.dart`
- `lib/widgets/reading_card_deck.dart`
- `test/reader_layout_metrics_test.dart`
- `test/unit/models/book_metadata_test.dart`
- `test/unit/services/card_depth_chapter_progress_service_test.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/services/progressive_display_state_test.dart`
- `test/unit/services/reader_structural_progress_service_test.dart`
- `test/widgets/reading_card_deck_test.dart`
- `docs/lazy_random_access_reader_progress.md`

### Tests, deviations, risks, and readiness

- Focused terminal-progress, metadata, Card-depth, display-remap, lazy-session, deck-boundary, and notification-policy command — **113 passed** before two final retry/remap assertions were added; both assertions are included in the final full-suite result.
- Expanded affected Phase 2–5 command covering structural/global/chapter progress, Home/library metadata, ReaderScreen policies, lazy append/prepend/replacement services, display publication/cache, Card deck/depth/boundaries, stable navigation, annotations, repository/cache reload, and feature-rich EPUB navigation — **198 passed**.
- Full repository `flutter test -r compact` — **699 passed**.
- `flutter analyze` — no issues found.
- `git diff --check` — passed.

No canonical-plan contradiction was found, and no plan, verification-report, parsing-audit, persisted schema, Phase 6, or Phase 7 work was added. Remaining runtime risk is limited to physical-device gesture arbitration, PageView frame ordering, filesystem/cache latency, and books whose malformed structure cannot supply terminal proof; the latter deliberately remains below 100% rather than inventing completion. Giant-XHTML subdivision and parse preemption remain deferred under the existing plan. Phase 5 remains **host-verifiably complete and ready for another focused physical-device retest**, with all work intentionally unstaged and uncommitted.

## Phase 5 Device-Validation Follow-up 3 — Host Fix Complete

Focused physical-device retesting on 2026-07-14 found three remaining defects in the Phase 5 reader:

1. Reopening could restore an older card and the library progression could lag, especially when several display cards came from one source chunk or the reader was exited immediately.
2. Card Mode chapter progress could repeat across several cards and then jump because the structural input changed only at a source-chunk boundary.
3. Incomplete chapter layouts remained at an unknown denominator instead of completing the current chapter total asynchronously after the readable deck was ready.

### Exact root causes

- **Last-read restoration:** ReaderScreen debounced a mutable display index and resolved that index to a stable location only when the timer fired. A lazy-window replacement or reflow could change the index-to-source mapping before that resolution. The source refinement path also divided a section by source-chunk index and only refined multi-chunk sections, so multiple display cards cut from one source chunk persisted the same location. `LazyBookSession.resolveStableLocation` retained `textOffset` but rebuilt section/publication progression from the local chunk alone. Finally, metadata saves had neither a monotonic reading-position revision nor serialized file writes, so a slower older save could overwrite a newer visible position. Ordinary route pop did not await the final debounced flush.
- **Per-card chapter progress:** every published display card already carried effective source ranges, but Card-depth structural interpolation received the card's source **start**. The source end was used only for terminal-completion proof. Cards split from the same source chunk therefore shared the same start-derived section/publication value until the next source chunk was entered.
- **Exact chapter totals:** the earlier Phase 5 responsiveness contract intentionally removed denominator-driven work. That avoided eager chapter parsing but left no chapter-scoped, low-priority completion coordinator or compatible cache record. The UI consequently had no state transition from an incomplete layout to a proven exact total.

### Exact last-read persistence contract

- A committed position is captured immediately on every successfully published visible-card change. Its stable location includes publication/book identity, readable spine and href, source checksum, section-local source-chunk identity, and the card's exact within-chunk text offset. The location is captured from the published display snapshot rather than from a requested/superseded target or a later interpretation of the display index.
- `ReaderStructuralProgressService.refineSourceOffset` and `LazyBookSession.refineSourceLocation` use `(localChunkIndex + textOffset/sourceTextLength) / sectionChunkCount`, preserving fractional internal precision even when a section has one source chunk. Phase 2 readable-spine weights then refine `publicationProgression` from that same location. Terminal publication proof may still commit the final card's proven source end at exactly `1.0`.
- A monotonic `lastReadRevision` is stored additively in `BookMetadata`. ReaderScreen stages only the newest captured snapshot; `BookMetadataService` serializes file writes and preserves the higher revision if delayed callers complete out of order. The canonical library/Home progression remains `lastReadLocation.publicationProgression`; legacy chunk fields are compatibility data only.
- The latest snapshot is flushed on the awaited ReaderScreen route-pop path and requested on application inactive/hidden/paused/detached and disposal paths. Normal route exit therefore waits for metadata, reading-session, and pending-stat writes. Disposal remains a best-effort final safeguard because Flutter disposal itself cannot be asynchronous.
- Restore resolution selects the exact section/local chunk and then the display card whose effective source range contains the persisted text offset. A typography, margin, density, orientation, or viewport change may alter card boundaries without altering the restored source text. Failed, cancelled, preview-only, or superseded navigation never stages its unseen target.

### Per-card chapter-progress contract

- Every published display card exposes a refined source start and source end derived from its effective source ranges. Card Mode chooses the chapter from the start but calculates the structural rail from the current card's **end** between the structural chapter start and next-chapter/publication-end boundary.
- The rail receives unrounded `double` precision and rebuilds on every committed card change. The integer percentage label may repeat after rounding, but any changed source end changes the underlying rail value. Section index, source-chunk index, display index, and loaded-window size are not progress denominators.
- The prior explicit terminal proof is unchanged: the genuine last card can reach 100% from its source end, while an unproven loaded-window edge remains below 100%.

### Background chapter-total and cache contract

- ReaderScreen publishes the target/current card and its required forward, backward, and depth readiness first. It then schedules only the structurally bounded current chapter at `layoutPagination` priority. Source sections are loaded into a detached chapter list, the live session is returned to the published stable anchor in a `finally` path, and the result never replaces the visible deck.
- The coordinator waits for active foreground range work and is cooperatively cancelled as soon as navigation, boundary preparation, chapter change, layout change, or disposal needs ownership. Latest chapter/layout key wins; stale and cancelled generations cannot publish or write. Successful or failed background counting is silent.
- Complete page source ranges and totals are cached under publication fingerprint, structural start/next-boundary identity, parsed schema, display schema/layout version, viewport/safe-area/orientation identity, all layout-affecting reader settings, and Card Mode. Identical layouts reuse the record without pagination. A layout-affecting change produces a different key and recalculates only that chapter/layout derivative; the existing 48 MiB segmented display budget accounts for these records.
- Before proof, Card Mode displays `Page n` and continues using structural progress. After the latest compatible chapter layout completes, it displays `n / total`. If malformed or missing structure would make the request cover the whole readable publication, background counting is deliberately skipped and `Page n` remains; Phase 5 never paginates the whole book merely to obtain a denominator.

### Files changed by this follow-up

- `lib/models/book_metadata.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/book_metadata_service.dart`
- `lib/services/card_depth_chapter_progress_service.dart`
- `lib/services/chapter_card_layout_service.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/reader_structural_progress_service.dart`
- `lib/services/segmented_display_cache_service.dart`
- `test/reader_layout_metrics_test.dart`
- `test/unit/models/book_metadata_test.dart`
- `test/unit/services/card_depth_chapter_progress_service_test.dart`
- `test/unit/services/chapter_card_layout_service_test.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/services/reader_structural_progress_service_test.dart`
- `test/unit/services/segmented_display_cache_service_test.dart`
- `docs/lazy_random_access_reader_progress.md`

### Tests, deviations, risks, and readiness

- Focused persistence, per-card progress, chapter-layout coordinator/cache, lazy resolver, metadata ordering, and ReaderScreen layout-policy command — **119 passed**.
- Expanded affected Phase 2–5 command covering structural indexes, stable resolution/open, metadata, chapter navigation/progress, lazy session/parser/cache ownership, display generation/publication/cache, Card deck/boundaries, annotations, bookmarks, highlights, dictionary locations, and feature-rich navigation — **276 passed**.
- Full repository `flutter test -r compact` — **714 passed**.
- `flutter analyze` — no issues found.
- `git diff --check` — passed.

No canonical-plan contradiction was found, so the plan, verification report, and parsing audit were not changed. The only persisted-contract addition is the backward-compatible `lastReadRevision` metadata field; existing metadata without it loads as revision zero. No Phase 6 work began. Host tests cannot reproduce abrupt process termination before the platform services finish a background flush, device filesystem latency, or real frame/gesture ordering. Giant-XHTML subdivision, whole-book search, Book Memory derived-index migration, and legacy parser/cache retirement remain deferred to their planned phases. Phase 5 remains **host-verifiably complete and ready for focused physical-device retesting**, with all changes intentionally unstaged and uncommitted.

## Current Codebase Risks

- `CachedBook` remains required by the explicit legacy reader path and by temporary Book Memory compatibility; Phase 6/7 own their replacement and retirement.
- Phase 1 preparation identity is intentionally filesystem-based (book ID, size, and modification time) plus cache/parser contract fields. A stronger publication fingerprint belongs to Phase 2.
- Book deletion now routes Phase 1 whole/display cache, Phase 2 structural index, parsed-section/hydration, and segmented-display derivatives through the Phase 4 coordinated cleanup transaction.
- Phase 2 structural validity hashes the complete EPUB bytes. This is stronger than timestamps and catches same-name/same-size replacement, but does not remove the current archive-open cost; further open-path optimization belongs to later profiling work.
- The dependency signature is intentionally conservative and publication-wide because Phase 2 does not persist per-resource content hashes. Any EPUB byte replacement invalidates all parsed sections for that publication; narrower dependency invalidation can be considered only with evidence and a future index schema.
- A launched XHTML parse remains non-preemptible. Closing the launching session releases owner interest and stops future hydration sections, but its archive handle remains alive until that one reusable job finishes. Giant-XHTML subdivision/preemption remains explicitly deferred.
- Active-nearby parsed data can temporarily remain over the effective disk budget when a single protected section exceeds it. The next enforcement after protection is released evicts it if required; device-level storage behavior remains a runtime validation item.
- Legacy annotations without a stable location remain migration hints. The lazy render path now requires their stored offsets to reproduce the exact stored text before projection, so unrelated same-length window indexes do not decorate. Phase 6 still owns Book Memory occurrence-index migration and whole-book derived indexes.
- The current parser still materializes and parses the complete target XHTML section. Card Mode no longer expands beyond required target/adjacent readiness, but giant-XHTML subdivision and mid-parse cancellation remain later work.
- Host tests cannot reproduce device filesystem latency, memory pressure, orientation-frame timing, or OS low-storage callbacks. These are explicit physical-device/profile validation items before Phase 6, not unresolved Phase 5 implementation failures.

## Decisions and Deviations Log

| Date | Phase | Decision or Deviation | Evidence | Impact |
|---|---|---|---|---|
| 2026-07-11 | 1 | Use a small `preparation_manifest.json` owned by `BookCacheService`, rather than changing `CachedBook` payload format. | Existing payloads must remain readable; validity must be checked without decompression/deserialization. | Adds an independently invalidatable metadata format while retaining legacy payload compatibility. |
| 2026-07-11 | 1 | Book Memory explicitly prepares only its requested file when its compatibility payload is absent. | Audit confirmed it consumed `CachedBook`; removing refresh preparation otherwise left it unprepared. | Preserves the temporary compatibility path without whole-library work. |
| 2026-07-11 | 1 | No automatic lazy-to-legacy fallback was added. | Canonical plan explicitly excludes route-selection/fallback expansion in this phase. | Existing lazy-reader policy remains unchanged. |
| 2026-07-11 | 2 | Persist `LazyEpubIndex` directly, with `LazyEpubIndexStore` as a storage adapter. | Canonical plan requires extending the current model and keeping the live archive separate. | No parallel structural model or reader route was introduced. |
| 2026-07-11 | 2 | Treat unavailable persistence as a cache miss rather than failing a lazy open. | Existing host-side lazy tests do not initialize path-provider storage; lazy opening must retain its previous fallback behavior. | Valid production storage reuses records; storage failure safely rebuilds in memory. |
| 2026-07-12 | 3 | Persist parser-version evidence in stable source locations in addition to the planned publication/section fields. | XHTML checksums do not change when parser chunk boundaries change. | Local chunk indexes are exact only for the same parsed-source version; quote/progression recovery handles parser changes. |
| 2026-07-12 | 3 | Do not persist ambiguous quote recovery when navigation falls through to weighted progression. | The plan requires unresolved or ambiguous legacy evidence to remain available. | Users can still navigate approximately, but the legacy record is retained until a unique recovery succeeds. |
| 2026-07-12 | 3 | Keep existing ReaderScreen destination entry points and route them through the session resolver. | ReaderScreen already had lazy chapter, link, annotation, and window-replacement plumbing. | Phase 3 remains an incremental migration rather than a reader rewrite; Phase 4 was not started. |
| 2026-07-12 | 3 | Project stable annotation records onto current lazy-window indexes only at render time. | Navigation used stable identity, but ReadingCard filtering still used retained legacy `originalChunkIndex`; typography changes rebuilt cards and masked the stale projection. | Visible/nearby cards redecorate immediately after annotation changes, migration, navigation, and window replacement without reparsing or repagination. |
| 2026-07-13 | 4 | Use a publication-wide dependency signature for schema v2 parsed sections. | Current output can include linked images and footnotes, while Phase 2 has a publication fingerprint but no per-resource content hashes. | Safely invalidates on any EPUB replacement; may rebuild more sections than a future narrower resource graph. |
| 2026-07-13 | 4 | Treat schema-v1 parsed records as unprovable rather than migrating them. | Version 1 stores section checksum/parser fields but no publication fingerprint or dependency identity. | Old derivatives miss and rebuild safely; no user data or structural index is affected. |
| 2026-07-13 | 4 | Throttle persisted access updates to once per record per five minutes. | Every cache hit does not need a manifest write, but eviction order must reflect meaningful reuse. | Reduces write churn while preserving deterministic LRU after the throttle interval; clock/interval are injectable. |
| 2026-07-13 | 4 | Keep launched parsing non-preemptible and cancel only ownerless queued speculation. | The existing `compute` parse has no safe mid-parse cancellation handle. | Useful work can survive close/reopen and commit atomically; giant-section preemption remains deferred. |
| 2026-07-13 | 4 | Add generation/tombstone coordination to existing parsed, segmented-display, and structural stores for cleanup races. | Independent instances and stale jobs could otherwise recreate deleted derivatives. | Book deletion/reset has one cache-only transaction without redesigning display retention or source parsing. |
| 2026-07-13 | 5 | Keep `LazyBookSession` authoritative and expose complete section/source identities into ReaderScreen rather than adding a parallel reader model. | Phase 3 stable navigation and Phase 4 repository/cache identity already define canonical ownership. | ReaderScreen integer indexes are bounded-window coordinates only; append, prepend, replacement, eviction, annotations, and persistence share the existing stable model. |
| 2026-07-13 | 5 | Bump only the disposable segmented display format to schema v2. | Last-access and range-retention data are layout derivatives; parsed source and user records need no Phase 5 format change. | Old display ranges safely miss/delete/regenerate; parsed sections, annotations, bookmarks, saved words, and stable locations are preserved. |
| 2026-07-13 | 5 | Remove exact-denominator work instead of lowering its priority. | Card readiness needs two forward cards and one backward destination, not a completed chapter. | Superseded by the 2026-07-14 device follow-up below; visible readiness is still never blocked by denominator work. |
| 2026-07-14 | 5 | Complete exact Card chapter totals only after visible readiness, through a cancellable chapter-scoped cache job. | Device feedback requires eventual exact totals, while the Phase 5 responsiveness and no-whole-book constraints still apply. | UI shows `Page n` first, then `n / total`; layout-keyed work is foreground-preemptible and never expands an unbounded/malformed chapter to the whole publication. |

## Files Changed by Phase

### Phase 1

- `lib/screens/book_list_screen.dart`
- `lib/screens/book_loading_screen.dart`
- `lib/screens/book_memory_screen.dart`
- `lib/services/book_cache_service.dart`
- `lib/services/book_memory_service.dart`
- `lib/services/book_preparse_service.dart`
- `test/unit/services/book_cache_service_test.dart`
- `test/unit/services/book_memory_service_test.dart`
- `test/unit/services/book_preparse_service_test.dart`
- `docs/lazy_random_access_reader_progress.md`

### Phase 2

- `docs/lazy_random_access_reader_progress.md`
- `lib/screens/book_list_screen.dart`
- `lib/services/book_cache_service.dart`
- `lib/services/book_metadata_service.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/lazy_epub_index_service.dart`
- `lib/services/lazy_section_repository.dart`
- `test/unit/services/lazy_epub_index_service_test.dart`
- `test/unit/services/lazy_section_parser_equivalence_test.dart`

### Phase 3

- `docs/lazy_random_access_reader_progress.md`
- `lib/models/stable_book_location.dart`
- `lib/models/highlight.dart`
- `lib/screens/book_loading_screen.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/bookmark_service.dart`
- `lib/services/dictionary_service.dart`
- `lib/services/highlight_service.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/reader_open_service.dart`
- `test/unit/models/stable_book_location_test.dart`
- `test/unit/screens/reader_annotation_projection_test.dart`
- `test/unit/services/bookmark_service_test.dart`
- `test/unit/services/dictionary_service_test.dart`
- `test/unit/services/highlight_service_test.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/services/reader_open_service_test.dart`
- `test/widgets/reading_card_table_test.dart`

### Phase 4

- `docs/lazy_random_access_reader_progress.md`
- `lib/models/book_metadata.dart`
- `lib/screens/book_list_screen.dart`
- `lib/screens/reader_screen.dart`
- `lib/services/book_cache_service.dart`
- `lib/services/book_metadata_service.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/lazy_epub_index_service.dart`
- `lib/services/lazy_parsed_book.dart`
- `lib/services/lazy_reader_cache_cleanup_service.dart`
- `lib/services/lazy_section_repository.dart`
- `lib/services/parsed_section_cache_service.dart`
- `lib/services/parsed_section_retention_policy.dart`
- `lib/services/reader_open_service.dart`
- `lib/services/segmented_display_cache_service.dart`
- `test/unit/models/book_metadata_test.dart`
- `test/unit/services/lazy_reader_cache_cleanup_service_test.dart`
- `test/unit/services/lazy_section_parser_equivalence_test.dart`
- `test/unit/services/lazy_section_repository_test.dart`
- `test/unit/services/parsed_section_cache_service_test.dart`
- `test/unit/services/parsed_section_retention_policy_test.dart`
- `test/unit/services/shared_lazy_section_work_coordinator_test.dart`

### Phase 5

- `docs/lazy_random_access_reader_progress.md`
- `lib/screens/reader_screen.dart`
- `lib/models/book_metadata.dart`
- `lib/services/book_metadata_service.dart`
- `lib/services/card_depth_chapter_progress_service.dart`
- `lib/services/chapter_card_layout_service.dart`
- `lib/services/lazy_book_session.dart`
- `lib/services/lazy_parsed_book.dart`
- `lib/services/parsed_section_cache_service.dart`
- `lib/services/reader_structural_progress_service.dart`
- `lib/services/segmented_display_cache_service.dart`
- `test/reader_layout_metrics_test.dart`
- `test/unit/screens/reader_annotation_projection_test.dart`
- `test/unit/screens/reader_card_depth_lazy_completion_test.dart`
- `test/unit/services/card_depth_chapter_progress_service_test.dart`
- `test/unit/services/chapter_card_layout_service_test.dart`
- `test/unit/services/lazy_book_session_test.dart`
- `test/unit/services/parsed_section_cache_service_test.dart`
- `test/unit/services/reader_structural_progress_service_test.dart`
- `test/unit/services/segmented_display_cache_service_test.dart`
- `test/widgets/reading_card_deck_test.dart`

## Tests and Verification by Phase

### Phase 1

- `flutter test test/unit/services/book_cache_service_test.dart test/unit/services/book_preparse_service_test.dart test/unit/services/book_memory_service_test.dart test/widgets/book_memory_screen_test.dart` — 31 passed.
- `flutter test test/unit/services/feature_rich_lazy_reader_fixture_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_reader_route_service_test.dart` — 18 passed.
- `flutter analyze` — no issues found.
- `git diff --check` — passed.

Focused coverage proves stored/oversized outcomes, repeated oversized avoidance, changed-file invalidation, cache-limit and format invalidation, missing/corrupt metadata handling, deletion/reset cleanup, no-deserialize validity checks, explicit one-book preparation, queue deduplication, explicit Book Memory preparation, and unchanged lazy session behavior.

### Phase 2

- `flutter test test/unit/services/lazy_epub_index_service_test.dart test/unit/services/lazy_book_session_test.dart test/unit/services/lazy_section_parser_equivalence_test.dart` — passed.
- `flutter test test/unit/services/lazy_epub_index_service_test.dart test/unit/services/book_cache_service_test.dart` — passed.
- `flutter analyze` — no issues found.
- `git diff --check` — passed.

### Phase 3

- Focused stable-location/session/fixture/model/service and ReaderScreen-adjacent tests — passed.
- Affected lazy-reader regression suite (13 test files) — 93 passed.
- Reader-open legacy migration and replacement-safety tests — 2 passed.
- Focused saved-word migration test — 1 passed.
- Annotation projection, highlight service, source-range, ReaderScreen-adjacent, ReadingCard/deck/speed-read/note, and lazy navigation regression tests — 97 passed.
- `flutter analyze` — no issues found.
- `git diff --check` — passed.

Focused coverage proves structural serialization/round trip, valid persisted reopen without rebuilding, same-name replacement fingerprint invalidation, incompatible schema recovery, corrupt-record recovery, normalized chapter/spine mappings, linear/non-linear weights, deletion cleanup, and direct lazy section-loading regressions.

### Phase 4

- `flutter test test/unit/services/shared_lazy_section_work_coordinator_test.dart test/unit/services/parsed_section_cache_service_test.dart test/unit/services/parsed_section_retention_policy_test.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/lazy_reader_cache_cleanup_service_test.dart test/unit/models/book_metadata_test.dart` — 46 passed.
- `flutter test` across the focused Phase 4 files plus `lazy_book_session`, Phase 2 structural index/parser equivalence, reader-open, feature-rich fixture, stable-location, bookmark/dictionary/highlight migration, annotation projection, and ReadingCard regressions — 157 passed.
- `flutter test test/unit/services/segmented_display_cache_service_test.dart` — 15 passed after fixing an initially detected isolate-capture regression in the new deletion guard.
- Final focused cache/deletion command including the 46 Phase 4 checks plus segmented display, whole cache, and Phase 2 structural index suites — 77 passed.
- Remaining affected lazy-route, metadata-index, display-memory, and Card Mode priority/progress suites — 19 passed.
- `flutter analyze` — no issues found.
- `git diff --check` — passed.

Focused coverage uses injected parsers, clocks, budgets, storage pressure, retention registries, cache roots, owner tokens, completion barriers, and file identities. It proves cross-session single invocation, priority promotion, owner cancellation distinctions, close/reopen joining, failure retry, identity non-joining, same/different-section writer union, atomic publication, schema-v2 round trip, safe schema-v1 miss, checksum/dependency/publication invalidation, byte/LRU eviction, access-order changes, active/recent/cold tiers, low-storage gating, hydration close behavior, deletion generations, structural cleanup, and preservation of cache-external user-data sentinels. No assertions rely only on logs or timing sleeps.

### Phase 5

- Phase 5A source/session/identity focused commands — 63 passed and 93 passed.
- Phase 5B display/cache/settings focused checkpoint command — 98 passed (after earlier 48- and 56-test focused runs).
- Phase 5C Card/progress first focused command — 53 passed.
- Phase 5C expanded Card, boundary, settings, selection, annotation, and stable-navigation command — 186 passed.
- Final combined Phase 2 structural, Phase 3 navigation/annotation, Phase 4 shared/cache cleanup, ReaderScreen persistence, lazy session/repository, display generation/cache, settings, Card progress/deck, and metadata command — 278 passed.
- Supplemental feature-rich link/footnote/anchor, lazy-route, chapter detection, saved-word, and whole-cache command — 33 passed.
- `flutter analyze` — no issues found.
- `git diff --check` — passed.

Phase 5 introduced no parsed-source, structural-index, stable-location, annotation, bookmark, saved-word, or user-data schema change. The additive metadata `lastReadRevision` field defaults to zero for older records and prevents delayed saves from replacing a newer exact stable position. Segmented display cache schema v2 and chapter-layout records are disposable layout derivatives. The 48 MiB display and 192 MiB parsed budgets remain separately configurable and pressure-aware. Search remains intentionally current-window scoped until Phase 6.

Physical-device/runtime/profile validation was not performed by instruction. Host-side tests cannot prove device filesystem latency, low-storage OS behavior, giant-XHTML parse latency, or frame timing during real orientation/typography changes; these are the exact next validation step before Phase 6.

## Known Blockers

No Phase 5 implementation blocker. Legacy `CachedBook` remains intentionally in use by the explicit legacy reader and temporary Book Memory compatibility path until Phase 6/7. Whole-book search and Book Memory derived indexes, giant-XHTML subdivision, and legacy parser/cache retirement remain their explicit later phases.

## Next Exact Step

Perform the separately planned physical-device/profile validation of Phase 5 before beginning Phase 6. Keep the current Phase 5 changes unstaged and uncommitted for review.
