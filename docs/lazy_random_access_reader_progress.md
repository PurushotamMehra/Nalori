# Nalori Lazy Random-Access Reader Progress

## Overall Status

- Overall state: Planning complete / implementation not started
- Current phase: Phase 1
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
| Phase 1 — Stop avoidable legacy work safely | Not started | — | — | No | Canonical first implementation phase. |
| Phase 2 — Persistent structural index | Not started | — | — | No | Depends on Phase 1 exit criteria. |
| Phase 3 — Stable random-access navigation | Not started | — | — | No | Depends on persistent publication identity. |
| Phase 4 — Shared section work and cache retention | Not started | — | — | No | Depends on canonical section identity. |
| Phase 5 — ReaderScreen and Card Mode responsiveness | Not started | — | — | No | Depends on stable navigation and bounded source ownership. |
| Phase 6 — Search and Book Memory migration | Not started | — | — | No | Depends on stable destinations and section validity. |
| Phase 7 — Legacy retirement | Not started | — | — | No | Requires evidence that all production consumers have migrated. |

## Phase 1 Checklist

- [ ] Remove automatic whole-library preparsing from normal library refresh.
- [ ] Add explicit preparation outcomes for cached, stored, terminal oversized, invalidated/changed, and retryable failure states.
- [ ] Persist an oversized terminal status so unchanged files are not retried.
- [ ] Add a lightweight validity probe that does not deserialize `CachedBook` payloads.
- [ ] Invalidate preparation outcomes and caches when file identity changes.
- [ ] Preserve explicit legacy reader compatibility through `BookLoadingScreen`/`BookPreparseService`.
- [ ] Preserve explicit Book Memory compatibility while it still depends on `CachedBook`.
- [ ] Coordinate cache, outcome, deletion, and reset cleanup for Phase 1-owned data.
- [ ] Add and run focused Phase 1 tests.
- [ ] Run `flutter analyze`.
- [ ] Run `git diff --check` and inspect the scoped diff.

## Completed Work

- EPUB parsing system audit completed in `docs/epub_parsing_system_audit.md`.
- Lazy random-access architectural verification completed in `docs/lazy_random_access_reader_verification.md`.
- Canonical implementation plan and this progress tracker completed.

No production implementation has started, and no phase is complete.

## Current Codebase Risks

- `BookListScreen._refreshLibrary` still queues all valid books through `BookPreparseService`, so automatic eager work remains active until Phase 1.
- Oversized whole-book cache output has no durable terminal outcome and can be reparsed after later queue passes.
- A lightweight `hasCachedBook` probe exists, but current preparation still loads/deserializes the full `CachedBook` on a cache hit before returning it.
- `CachedBook` remains required by the explicit legacy reader path and by `BookMemoryService`; automatic preparation cannot be removed by deleting compatibility APIs.
- Cache/outcome identity is filename/mtime-oriented and must not suppress preparation after same-name content replacement.
- Book deletion currently removes the legacy whole-book cache but does not coordinate every lazy/display cache owner; Phase 1 cleanup must stay scoped while preserving the later full-deletion boundary.

## Decisions and Deviations Log

| Date | Phase | Decision or Deviation | Evidence | Impact |
|---|---|---|---|---|

## Files Changed by Phase

### Phase 1

None. Implementation not started.

## Tests and Verification by Phase

### Phase 1

None. Implementation not started.

## Known Blockers

None currently known.

## Next Exact Step

Implement Phase 1 only using the canonical plan and update this progress document with files changed, tests, decisions, blockers and exit-criteria status.
