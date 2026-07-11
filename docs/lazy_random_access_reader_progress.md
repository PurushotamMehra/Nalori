# Nalori Lazy Random-Access Reader Progress

## Overall Status

- Overall state: Phase 2 complete / later phases not started
- Current phase: Phase 3 (not started)
- Last updated: 2026-07-11
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
| Phase 3 — Stable random-access navigation | Not started | — | — | No | Depends on persistent publication identity. |
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

## Current Codebase Risks

- `CachedBook` remains required by the explicit legacy reader path and by temporary Book Memory compatibility; Phase 6/7 own their replacement and retirement.
- Phase 1 preparation identity is intentionally filesystem-based (book ID, size, and modification time) plus cache/parser contract fields. A stronger publication fingerprint belongs to Phase 2.
- Book deletion now clears Phase 1 whole-cache/preparation metadata and the Phase 2 structural index; coordinated parsed-section/display cleanup remains a later-phase boundary.
- Phase 2 structural validity hashes the complete EPUB bytes. This is stronger than timestamps and catches same-name/same-size replacement, but does not remove the current archive-open cost; further open-path optimization belongs to later profiling work.

## Decisions and Deviations Log

| Date | Phase | Decision or Deviation | Evidence | Impact |
|---|---|---|---|---|
| 2026-07-11 | 1 | Use a small `preparation_manifest.json` owned by `BookCacheService`, rather than changing `CachedBook` payload format. | Existing payloads must remain readable; validity must be checked without decompression/deserialization. | Adds an independently invalidatable metadata format while retaining legacy payload compatibility. |
| 2026-07-11 | 1 | Book Memory explicitly prepares only its requested file when its compatibility payload is absent. | Audit confirmed it consumed `CachedBook`; removing refresh preparation otherwise left it unprepared. | Preserves the temporary compatibility path without whole-library work. |
| 2026-07-11 | 1 | No automatic lazy-to-legacy fallback was added. | Canonical plan explicitly excludes route-selection/fallback expansion in this phase. | Existing lazy-reader policy remains unchanged. |
| 2026-07-11 | 2 | Persist `LazyEpubIndex` directly, with `LazyEpubIndexStore` as a storage adapter. | Canonical plan requires extending the current model and keeping the live archive separate. | No parallel structural model or reader route was introduced. |
| 2026-07-11 | 2 | Treat unavailable persistence as a cache miss rather than failing a lazy open. | Existing host-side lazy tests do not initialize path-provider storage; lazy opening must retain its previous fallback behavior. | Valid production storage reuses records; storage failure safely rebuilds in memory. |

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

Focused coverage proves structural serialization/round trip, valid persisted reopen without rebuilding, same-name replacement fingerprint invalidation, incompatible schema recovery, corrupt-record recovery, normalized chapter/spine mappings, linear/non-linear weights, deletion cleanup, and direct lazy section-loading regressions.

## Known Blockers

No Phase 2 blockers. Legacy `CachedBook` remains intentionally in use by the explicit legacy reader and temporary Book Memory compatibility path until Phase 6/7.

## Next Exact Step

Begin Phase 3 only after separately approving stable random-access navigation scope.
