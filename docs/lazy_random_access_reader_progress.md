# Nalori Lazy Random-Access Reader Progress

## Overall Status

- Overall state: Phase 4 complete / later phases not started
- Current phase: Phase 4 complete (unstaged review checkpoint)
- Last updated: 2026-07-13
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
| Phase 5 — ReaderScreen and Card Mode responsiveness | Not started | — | — | No | Depends on stable navigation and bounded source ownership. |
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

## Current Codebase Risks

- `CachedBook` remains required by the explicit legacy reader path and by temporary Book Memory compatibility; Phase 6/7 own their replacement and retirement.
- Phase 1 preparation identity is intentionally filesystem-based (book ID, size, and modification time) plus cache/parser contract fields. A stronger publication fingerprint belongs to Phase 2.
- Book deletion now routes Phase 1 whole/display cache, Phase 2 structural index, parsed-section/hydration, and segmented-display derivatives through the Phase 4 coordinated cleanup transaction.
- Phase 2 structural validity hashes the complete EPUB bytes. This is stronger than timestamps and catches same-name/same-size replacement, but does not remove the current archive-open cost; further open-path optimization belongs to later profiling work.
- The dependency signature is intentionally conservative and publication-wide because Phase 2 does not persist per-resource content hashes. Any EPUB byte replacement invalidates all parsed sections for that publication; narrower dependency invalidation can be considered only with evidence and a future index schema.
- A launched XHTML parse remains non-preemptible. Closing the launching session releases owner interest and stops future hydration sections, but its archive handle remains alive until that one reusable job finishes. Giant-XHTML subdivision/preemption remains explicitly deferred.
- Active-nearby parsed data can temporarily remain over the effective disk budget when a single protected section exceeds it. The next enforcement after protection is released evicts it if required; device-level storage behavior remains a runtime validation item.
- Phase 5 must remove the remaining render-time fallback from annotations without a stable location to legacy/global/window-relative `Highlight.originalChunkIndex`. Such records can still collide with a current lazy-window index. Character-name rendering has two layers: literal whole-name matching is source-text safe, while the direct stored occurrence range uses this legacy index and can color an unrelated same-length range. Phase 5 acceptance must make all direct decoration ranges section-aware across append, prepend, replacement, split, and merge; Phase 6 still owns Book Memory occurrence-index migration.

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

Physical-device runtime validation was not performed by instruction. Host-side tests cannot prove device filesystem latency, low-storage OS behavior, or giant-XHTML parse latency; those remain deferred runtime validation, not Phase 5 implementation work.

## Known Blockers

No Phase 4 blocker. Legacy `CachedBook` remains intentionally in use by the explicit legacy reader and temporary Book Memory compatibility path until Phase 6/7. Phase 5 owns ReaderScreen bounded-window/display restructuring and removal of the remaining legacy-index decoration fallback documented above. Giant-XHTML subdivision and foreground legacy-parser retirement remain later explicit phases.

## Next Exact Step

Review the unstaged Phase 4 diff and host-side evidence. Do not begin Phase 5 until Phase 4 is accepted and committed as a clean checkpoint; after approval, the next implementation step is Phase 5 ReaderScreen bounded source/display ownership and Card Mode responsiveness.
