# Nalori Lazy Random-Access Reader Progress

## Overall Status

- Overall state: Phase 3 complete / later phases not started
- Current phase: Phase 4 (not started)
- Last updated: 2026-07-12
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
| Phase 4 — Shared section work and cache retention | Not started | — | — | No | Depends on canonical section identity. |
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

## Current Codebase Risks

- `CachedBook` remains required by the explicit legacy reader path and by temporary Book Memory compatibility; Phase 6/7 own their replacement and retirement.
- Phase 1 preparation identity is intentionally filesystem-based (book ID, size, and modification time) plus cache/parser contract fields. A stronger publication fingerprint belongs to Phase 2.
- Book deletion now clears Phase 1 whole-cache/preparation metadata and the Phase 2 structural index; coordinated parsed-section/display cleanup remains a later-phase boundary.
- Phase 2 structural validity hashes the complete EPUB bytes. This is stronger than timestamps and catches same-name/same-size replacement, but does not remove the current archive-open cost; further open-path optimization belongs to later profiling work.
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

## Known Blockers

No Phase 3 blocker. Legacy `CachedBook` remains intentionally in use by the explicit legacy reader and temporary Book Memory compatibility path until Phase 6/7. Phase 5 owns removal of the remaining legacy-index decoration fallback documented above.

## Next Exact Step

Keep Phase 3 unstaged/uncommitted until review of the focused annotation fix; do not begin Phase 4 without separate approval.
