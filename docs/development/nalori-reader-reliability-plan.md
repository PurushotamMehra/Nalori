# Nalori reader reliability repair plan

Plan baseline: 2026-08-27  
Repository baseline: `feature/lazy-random-access-reader` at `9d77165`, with substantial pre-existing modified and untracked work.  
Plan status: P00/P01 complete, P02 core complete at 7/8 with its optional task deferred, P03 complete at 7/7, P04 historical tasks complete at 8/8 with its lazy-input/publication exit gate `ARCHITECTURAL_CORRECTION_REQUIRED`, P05 `COMPLETED` at 7/7, and P06 `REGRESSED_ON_DEVICE` at 7/7. Latest ordinary A059 evidence supersedes CHANGE-039's host-only correction claims. `CHANGE-20260919-040` specifies the required immutable lazy snapshot handoff and adds red characterization; it implements no production correction. Overall progress remains 46/89. P04/P06 exit gates are open, and P07 remains unstarted and blocked.

Current scoped design: [canonical lazy snapshot handoff](nalori-lazy-snapshot-handoff-design.md), task `DESIGN-P04-LAZY-SNAPSHOT-HANDOFF`. Next task is `IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001`, whose entry proofs and bounded prompt are in section 10 of that design. Neither identifier adds a historical checklist task or changes the 89-task denominator. Recovery commit `a130bda2785a57ed2e94ae3fd0630572d3f9d010` and the five protected diagnostic files remain immutable evidence.

Latest entry proof: `CHANGE-20260921-041` amends navigation/performance requirements
and records the [source-address inventory](nalori-lazy-source-address-inventory.md)
and [current stopped entry report](nalori-lazy-snapshot-handoff-entry-proof.md).
The report's current bounded prompt supersedes the earlier next-task wording.
Address witness controls pass, but exact payload reopen, held-speculation
preemption and legacy window-only semantic fallback remain red. All three
implementation-entry gates remain unsatisfied; production handoff is not
authorized. The chapter-local scrubber in §7A is deferred and UNSTARTED.

`CHANGE-20260913-036` is a non-task independent audit of P06-004/P06-005. It
strengthens exact memory scope, strict-admission provenance, asynchronous
freshness ordering and stable-start replacement anchoring. At that audit point
P06 remained 5/7 and overall progress remained 44/89; CHANGE-037/038
supersede those progress figures.

## 1. Document purpose and authority

This document is the authoritative scope, dependency, task, and progress plan for repairing Nalori's reader pagination, physical-card identity, restoration, checkpoint durability, lazy-boundary navigation, cache equivalence, and reader-specific automated tests. It governs future work that can be executed in bounded Codex tasks without treating the current implementation or AI-written tests as the product specification.

The authority order is:

> approved product behaviour → trustworthy test → implementation

The plan was prepared from the current working tree, not from historical completion claims alone. Sources inspected include:

- `docs/development/nalori-test-suite-audit.md`;
- `docs/epub_parsing_system_audit.md`;
- `docs/epub_semantic_content_pipeline_audit.md`;
- `docs/lazy_random_access_reader_plan.md`;
- `docs/lazy_random_access_reader_progress.md`;
- `docs/lazy_random_access_reader_verification.md`;
- `docs/lazy_reader_smooth_navigation_progress.md`;
- `docs/reader_checkpoint_adb_verification.md`;
- current reader, source-identity, parsing, lazy-session, display-state, cache, checkpoint, persistence, coordinator, rendering, search, Book Memory, bookmark, highlight, and note-projection code;
- current reader-related tests, the synthetic feature-rich EPUB fixture, test support, and the full test audit inventory;
- read-only Git status and recent lazy-reader phase history.

Historical reports are architectural evidence. Their file paths, symbols, and claims must be reconfirmed when a phase begins because the working tree has continued to change and many relevant files are currently untracked.

Deliberately outside this repair scope are non-reader test-suite cleanup, unrelated product behaviour, general UI redesign, catalogue policy, Speed Read product policy, quote/share presentation, golden-test adoption as a substitute for behavioural tests, giant-XHTML parser redesign unless a reader requirement proves it necessary, and removal of legacy parser/cache paths beyond the minimum required for reader correctness. Device and emulator testing is not authorized for Codex; final device verification belongs to the product owner.

This plan records intended work. `docs/development/nalori-reader-reliability-change-log.md` is the append-only ledger of what actually changed, what commands ran, and what evidence was obtained. A checked task in this plan is valid only when the corresponding change-log evidence exists.

## 2. Current-state executive assessment

### Verified current defects

CHANGE-040 qualification: snapshot exhaustion is currently treated as
`terminalBookEnd` even when the lazy spine index proves another section exists.
Forward integration resumes that terminal continuation; caught range failure
can resolve normally upstream and does not latch/cancel matching background
work. Host fixed-snapshot evidence below does not prove lazy snapshot handoff.

1. `ReaderCardPaginator.paginateCanonical` exposes the immutable forward state-machine kernel with a revision-pinned source snapshot, the sole canonical continuation representation, strict reconstruction/chain validation, 48-source/eight-card checkpoint cadence, and a bounded 25-record in-memory index. `ReaderScreen` consumes bounded canonical publication-start/trusted-section initial, stable target-first, exact-suffix forward, and checkpoint-rooted forward-regenerated backward outcomes. All live canonical display mutations pass through `ProgressiveDisplayState.publishCanonical`, which validates a private candidate and commits cards, coverage maps, ranges, continuation and stable anchors once. Legacy cache records are observed but rejected pending P06 and regenerate from source.
2. `ReaderCheckpointCoordinator.resolveRestore` correctly returns no result when an exact same-layout signature is missing, but `ReaderScreen._restorePosition` can then continue with `_pendingExactStableRestore` and resolve a display card from the saved stable source location. That path can silently turn a same-layout exact-card failure into source-anchor restoration without proving a genuine layout or pagination incompatibility.
3. Current segmented and in-memory display caches persist and return independently generated `DisplayRangeResult` objects. Their validity checks establish record and layout-key compatibility, not canonical equivalence with a cold, full-section pagination sequence.
4. `ReaderScreen._completeStableLocationNavigation` currently polls up to 30 times using `Future.delayed(const Duration(milliseconds: 50))`. Completion therefore depends on elapsed time rather than an explicit publication/controller-settlement signal.
5. `CHANGE-20260906-014` connects initial, target-first, and forward ReaderScreen generation to that canonical kernel. `CHANGE-20260906-015` replaces the remaining ReaderScreen backward bridge with bounded forward regeneration from a strict earlier checkpoint or trusted root and turns `P03-PREPEND-001` green. `CHANGE-20260907-016` finalizes ordered structural ownership and canonical physical-card signatures. `CHANGE-20260907-017` adds validate-before-commit canonical display transactions, rejects legacy cache publication, regenerates canonically, and turns `P03-CACHE-001` through `P03-CACHE-005` green without changing cache formats.

### Strongly supported risks

- The visible position is projected through `_currentPage`, `_activeDisplayIndex`, `ReaderPositionSession`, `ReaderVisiblePositionCoordinator`, controller intents, progressive publication state, and checkpoint state. The coordinator is intended to be authoritative, but delayed publications and callbacks still traverse several mutable index projections.
- Route pop awaits `_flushReaderPersistence`, while `dispose` and application lifecycle callbacks start unawaited flushes. The staging and journal queues are useful safeguards, but immediate-exit durability and cross-book isolation lack a production-path proof.
- The current layout fingerprint includes many settings and a `fontMetricIdentity`, but measurement/render agreement for resolved font metrics, inline structures, heading decoration/spacing, directionality, and exact card-body constraints is not established through one shared contract.
- Lazy prepend, eviction reconciliation, cache replacement, and chapter-layout work have anchor-preservation guards, but they consume independently paginated ranges. Anchor preservation alone does not prove adjacent card order or unchanged published boundaries.
- Search, Book Memory, bookmarks, highlights, and notes have stable-source projection helpers and stable-location call sites, but their complete route-to-reader publication/settlement lifecycle is not covered.

### Unverified hypotheses requiring discovery

- Whether every rendered `ReadingCard` path uses exactly the same safe-area, publisher padding, inline spans, locale, direction, text-height behaviour, strut, heading spacing, and resolved font metrics as pagination measurement.
- Whether every controller reattachment and card-deck transition emits a causally identifiable settlement event on all supported platforms.
- Whether current cache manifests contain enough source-boundary evidence to migrate any existing display segment safely, rather than invalidate it.
- Whether a current exact checkpoint can always request enough canonical predecessor state to regenerate its physical card without eagerly paginating a section or book.
- Which Book Memory, search, TOC, bookmark, highlight, note, internal-link, and history entry points still carry a mutable index as more than a transient hint.

### Components that appear comparatively reliable

- `StableBookLocation` and `LazySourceChunkIdentity` contain durable publication, section, parser, local-chunk, and source-offset evidence, although end-to-end ownership remains unverified.
- `ReaderCardIdentity` hashes ordered canonical source ranges with publication, layout, and pagination identities.
- `ReaderCheckpointStore` and `ReaderCheckpointCoordinator` have explicit session epochs, revisions, integrity checks, serialised writes, restore barriers, and stale-write rejection. These are strong low-level foundations, not lifecycle proof.
- `DisplayGenerationCoordinator` and `ReaderVisiblePositionCoordinator` model generation/intent ownership and reject several stale or synthetic mutations.
- `LazyBookSession` resolves and loads stable source targets without requiring whole-book pagination.

### Missing production-path coverage

There is no trustworthy test that performs this lifecycle through real reader production paths:

```text
open book A → settle an exact visible physical card → persist checkpoint
→ close reader A → open book B → settle/close B → reopen book A
→ verify the exact card signature and visible source text
```

There is also no canonical matrix comparing complete ordered card identities across full-section, target-first, forward-first, backward-first, singleton-then-expansion, cold-cache, warm-cache, eviction/reload, prepend, and heading-seam construction. Both are blocker-level gaps.

## 3. Non-negotiable invariants

- Stable source identity is authoritative across parsing, persistence, navigation, reflow, and lazy-window replacement.
- Display indexes are transient coordinates within one publication only; they are never durable or canonical location truth.
- Accepted settled-card commitment has one owner. Preview, cancelled, rejected, stale, synthetic, or mismatched events cannot commit.
- Lazy reading remains bounded by explicit source/display/cache budgets. No repair may require whole-book pagination or unlimited card retention.
- Reopening under an identical layout must restore the exact accepted physical-card signature and visible source coverage.
- Semantic fallback is permitted only after a proved publication/layout/parser/pagination incompatibility, never because a partial publication omitted an expected signature.
- Already accepted or published card boundaries are immutable when adjacent lazy content is loaded; expansion extends the canonical sequence.
- Canonical adjacent navigation is derived from stable card/source identity, not `_currentPage ± 1` carried across publications.
- Coordinator correction and stale-generation rejection remain enabled.
- Checkpoint epoch/revision and stale-write protections remain unless stronger evidence justifies an explicitly migrated replacement.
- Persistence never targets a lazy session that has not successfully opened and acquired ownership for the book.
- Production behaviour is not altered to satisfy an unapproved, obsolete, contradictory, or false-confidence test.
- Expected card signatures are never mass-updated without an explained identity change, mapped requirements, and replacement evidence.
- Correctness does not depend on arbitrary delays, repeated uncontrolled `pumpAndSettle`, cache clearing, or caught-and-ignored lifecycle errors.

## 4. Current architecture map

| Component/file | Important symbols | Current responsibility | Authoritative state owned | Inputs/outputs | Known risk or competing owner |
| --- | --- | --- | --- | --- | --- |
| `lib/services/epub_parser.dart` | `EpubParserService` | Parses EPUB source into semantic `BookChunk` data | Parsed source content for the invoked parse | EPUB resources → chunks, chapters, anchors | Eager/lazy equivalence and structural identity need stronger fixture proof |
| `lib/services/lazy_epub_index_service.dart` | `LazyEpubIndexService`, `LazyEpubIndex`, `LazyEpubIndexStore` | Builds/persists publication structure and readable spine metadata | Publication fingerprint and structural index records | EPUB file → index/handle | Historical reports may not describe current schema exactly; reconfirm per migration task |
| `lib/services/lazy_parsed_book.dart` | `LazySectionIdentity`, `LazySourceChunkIdentity`, `ParsedSection` | Defines stable section/source identities and parsed-section payloads | Section identity within one parser/publication contract | Index/resource evidence → parsed section | Generated structural fragments need deterministic ownership rules |
| `lib/models/stable_book_location.dart` | `StableBookLocation` | Serialises durable source position plus compatibility hints | Durable semantic source location | Source identity/offset → JSON/location | `localDisplayIndex` remains present as a compatibility hint and must never regain authority |
| `lib/services/reader_source_projection_service.dart` | `readerStableLocationMatchesSource`, `readerSourceIndexForStableLocation`, `readerDisplayIndexForStableLocation`, annotation projection helpers | Maps stable source evidence into the current window/display | No durable state; pure resolution/projection | Stable location + current source/card maps → transient indexes | Helper tests cannot prove route, publication, or settlement behaviour |
| `lib/services/lazy_section_repository.dart` and `lib/services/lazy_book_session.dart` | `LazySectionRepository`, `LazyBookSession`, `prepareNavigation`, `loadAround`, adjacent loaders | Opens a book, resolves source targets, owns bounded parsed sections | Live lazy session and loaded source-section window | Stable location/spine requests → loaded source window | Session/window ownership can diverge from ReaderScreen display ownership during async work |
| `lib/services/reader_card_paginator.dart`; `lib/models/canonical_pagination.dart`; `lib/models/canonical_pagination_checkpoint_index.dart`; `lib/services/progressive_display_state.dart`; `lib/screens/reader_screen.dart` delegation | `ReaderCardPaginator.paginateCanonical`, `CanonicalReaderPaginationSession`, `CanonicalPaginationContinuation`, `CanonicalPaginationCheckpointIndex`, `ProgressiveDisplayState.publishCanonical`, `paginateLegacyForP02` | The service owns one production split/merge/rebalance/frontier kernel plus bounded initial/target/forward/backward orchestration and finalized structural identities; ReaderScreen pins one source/layout generation and consumes typed canonical outcomes through one transactional publication boundary; legacy range-end behavior is isolated to frozen historical parity evidence | Paginator owns immutable request computation and canonical frontier/chain state; the bounded index owns accepted process-local records; ProgressiveDisplayState owns validate-before-commit cards/maps/ranges/anchors; ReaderScreen retains scheduling/controller application authority | Stable source snapshot + publication/layout/pagination identity + publication/trusted-section/validated-continuation restart or stable target + bounded controls → finalized cards with ordered structural identity, logical end, provisional continuation, required-earlier restart, or rejection | Transactional publication completed by `CHANGE-20260907-017`; persistent cache compatibility remains P06 |
| `lib/services/progressive_display_state.dart` | `DisplayRangeRequest`, `DisplayRangeResult`, `PreparedDisplayRange`, `ProgressiveDisplayState` | Tracks prepared source ranges and concatenates display results | Window-local range/card/index maps | Generated/cached ranges → progressive display snapshot | Concatenation validates adjacency of source ranges, not canonical card seams |
| `lib/services/display_generation_coordinator.dart` | `DisplayGenerationCoordinator`, `ReaderNavigationPublicationCoordinator`, `ReaderVisiblePositionCoordinator`, navigation/correction intents | Rejects stale generation, navigation, settlement, and correction work | Intended visible-location/intent authority | Requests/callbacks/generations → accept/reject decisions | Screen also stores several mutable visible indexes and pending targets |
| `lib/models/reader_checkpoint.dart` | `ReaderCardSourceRange`, `ReaderSemanticAnchor`, `ReaderCardIdentity`, `ReaderCheckpoint`, `readerPaginationAlgorithmVersion` | Defines exact card signatures and checkpoint payload | Canonical card/source identity model | Card/source/layout/publication → signature/checkpoint JSON | Signature quality inherits paginator source-range correctness and layout-fingerprint completeness |
| `lib/services/reader_checkpoint_store.dart` | `ReaderCheckpointStore`, `ReaderCheckpointCoordinator`, `resolveRestore`, `verifyPublished`, `commitCard` | Journal persistence, epochs/revisions, restore barrier and migration | Durable per-book checkpoint journal | Checkpoint candidates/cards → stored/rejected records | Screen can bypass the coordinator's exact miss by continuing with pending stable restore |
| `lib/screens/reader_screen.dart` persistence | `_onPageChanged`, `_onPageSettled`, `_captureCommittedPosition`, `_persistCommittedPosition`, `_flushReaderPersistence`, `_flushAndPopReaderRoute` | Converts settlement into checkpoint and compatibility metadata writes | Pending reader-position queue and screen-side commit projections | Controller/deck settlement → journal/metadata/stats | Pop is awaited; dispose/lifecycle are unawaited and unproven under immediate exit/book switching |
| `lib/screens/reader_screen.dart` restore | `_initReadingPosition`, `_resolveCanonicalCheckpointRestore`, `_restorePosition`, `_scheduleCheckpointPublicationVerification` | Selects initial target, publishes it, verifies, enables ordinary writes | Pending checkpoint resolution and restore fields | Saved checkpoint + current cards/layout → visible card/restore completion | Exact miss can proceed to stable-location card resolution; default/late publications need lifecycle proof |
| `lib/screens/reader_screen.dart` navigation | `_navigateToStableLocation`, `_completeStableLocationNavigation`, `_nextReaderPage`, `_previousReaderPage` | Executes explicit and adjacent navigation | Pending navigation token, intent and transient display target | Stable target/committed anchor → prepared window/controller move | Stable navigation polls with 50 ms delays; adjacent identity is not yet a canonical card API |
| `lib/screens/reader_screen.dart` lazy integration | `_prepareProgressiveDisplayRange`, `_ensureAdjacentSectionAvailable`, `_integrateLazyForwardSection`, `_integrateLazyBackwardSection`, eviction reconciliation | Loads, caches, appends/prepends, retries, and republishes ranges | Active range/lazy-operation flags and window projections | Boundary intent → new source/display window | Anchor guards do not prove immutable seams; retry closures need fresh-intent evidence |
| `lib/services/book_cache_service.dart` | `BookCacheService`, `displayChunkKey`, display/cache version constants | Whole parsed/display derivatives and layout cache key | Whole-cache files/manifests | Layout/source data ↔ cached chunks | Cache key and current card algorithm version are separate; safe reuse/migration needs one compatibility contract |
| `lib/services/segmented_display_cache_service.dart` and `lib/services/display_section_memory_cache.dart` | `SegmentedDisplayCacheService`, `DisplaySegmentRecord`, `DisplaySectionMemoryCache` | Disk and memory retention of prepared display ranges | Cached range records and bounded retention metadata | `DisplayRangeResult` ↔ segment record | Stores independently packed islands; serialization correctness is not cold/warm identity equivalence |
| `lib/widgets/reading_card.dart` and `lib/widgets/reading_card_deck.dart` | `ReadingCard`, `ReadingCardDeck` | Renders cards and emits interactive-deck settlement | Widget-local rendering/gesture state | `BookChunk` + settings/annotations → pixels and callbacks | Measurement/rendering contract and causal settlement need controlled production-path tests |
| Search, TOC, Book Memory and annotation integration | `DerivedBookIndexSession`, `DerivedBookSearchService`, `ReaderOpenService`, `ChapterNavigationTarget`, ReaderScreen stable-navigation/projection call sites | Resolves explicit jumps and projections into reader source | Derived indexes and caller-owned durable records | Search/memory/chapter/annotation target → `StableBookLocation` → reader | Complete route-to-settlement coverage is absent; mutable compatibility indexes remain reachable |
| Current test foundations | `reader_checkpoint_store_test.dart`, `display_generation_coordinator_test.dart`, `progressive_display_state_test.dart`, `segmented_display_cache_service_test.dart`, reader widget tests, `feature_rich_lazy_reader.epub` | Exercises models/helpers/storage/component widgets | Test-local fakes, handcrafted cards/ranges, temp stores | Synthetic inputs → assertions | No real canonical paginator matrix or full ReaderScreen A→B→A lifecycle harness |

## 5. Requirement registry

No requirement is `VERIFIED` in this planning task. Existing helper tests and historical reports are insufficient verification.

| Requirement ID | Requirement | Priority | Current assessment | Planned phase | Verification evidence required | Final status |
| --- | --- | --- | --- | --- | --- | --- |
| REQ-001 | Identical layout reopen restores the exact accepted physical card. | BLOCKER | Exact identity model exists; production lifecycle unproven and downgrade path remains. | P07–P08 | Real ReaderScreen close/reopen asserting saved and visible signatures plus source text | NOT_STARTED |
| REQ-002 | Genuine layout change restores the card containing the same semantic source anchor. | BLOCKER | Genuine-change classification is complete; real semantic restoration remains P07/P08-owned and unverified. | P05, P07–P08 | Controlled layout change with same source offset and different compatible signature | NOT_STARTED |
| REQ-003 | Same-layout exact-signature failure never silently downgrades to semantic restoration. | BLOCKER | Coordinator rejects; screen can continue through `_pendingExactStableRestore`. | P07–P08 | Partial/corrupt publication test proving no approximate commit or rewrite | NOT_STARTED |
| REQ-004 | Default, body fallback, or temporary target cannot become authoritative during restoration. | BLOCKER | Restore barrier exists; no screen lifecycle proof. | P07–P08 | Delayed/default publication race test with durable checkpoint unchanged | NOT_STARTED |
| REQ-005 | One coordinator-owned restoration intent is created, settled, verified, and consumed before navigation/commits are enabled. | BLOCKER | Intent and barrier components exist but ownership is distributed in screen state. | P07–P08 | Intent-state trace through real controller and checkpoint store | NOT_STARTED |
| REQ-006 | Later append, prepend, cache replacement, controller reattachment, chapter work, or stale callback cannot replace the verified restored card. | BLOCKER | Generation/anchor guards exist; complete race matrix absent. | P07–P09 | Controlled delayed-operation matrix asserting exact signature remains authoritative | NOT_STARTED |
| REQ-007 | Identical content/layout yields identical ordered physical-card identities regardless of lazy construction order. | BLOCKER | Fixed-snapshot P03/P04 evidence preserved; CHANGE-040 exposes missing lazy snapshot/packing-identity handoff. | P03–P04 | Complete ordered identity matrix including successive immutable lazy snapshots | ARCHITECTURAL_CORRECTION_REQUIRED |
| REQ-008 | Full-section, target-first, forward-first, backward-first, and singleton-then-expansion construction agree. | BLOCKER | All required construction paths are green under the frozen controlled layout and oracle. | P03–P04 | Same fixture/layout across all named orders | VERIFIED |
| REQ-009 | Cold cache, warm cache, eviction, and regeneration produce identical ordered identities. | BLOCKER | CHANGE-038 host evidence preserved; partial-window terminal records lack independent book-end authority (CHANGE-040). | P03, P06 | Cold/warm/evict/reload identity and visible-text equality with lazy end-proof admission | REGRESSED_ON_DEVICE |
| REQ-010 | Loading lazy content extends the canonical sequence without repacking accepted or published cards. | BLOCKER | Ordinary same-snapshot transaction evidence preserved; device adjacent integration resumes terminal input and cannot cross snapshots. | P04, P06 | Authenticated handoff and unchanged accepted-card bytes/signatures | ARCHITECTURAL_CORRECTION_REQUIRED |
| REQ-011 | Split/continued paragraphs, headings, generated fragments, repeated text, and section seams have deterministic identities. | BLOCKER | Frozen structural matrices and manual source review prove deterministic reviewed ownership and identities. | P03–P04 | Controlled fixtures with manually validated ranges and signatures | VERIFIED |
| REQ-012 | Physical-card identity uses stable canonical inputs, never mutable window-local indexes. | BLOCKER | Canonical identity, continuation, reindex, prepend and replacement evidence excludes mutable index authority. | P03–P04 | Signature tests under reindex/prepend/window replacement | VERIFIED |
| REQ-013 | Append and prepend preserve exact source coverage without gaps or duplication. | BLOCKER | Fixed-snapshot coverage proof preserved; cross-snapshot forward/backward seams remain unproved (CHANGE-040). | P03–P04 | Ordered half-open coverage across handoff, retention and backward regeneration | ARCHITECTURAL_CORRECTION_REQUIRED |
| REQ-014 | Measurement and rendering share one versioned layout contract. | HIGH | CHANGE-029 proves exact production measure/render parity across the structural matrix and repeated P03 construction orders. | P05 | Production paginator/renderer parity tests over approved structures; repeated complete P03 evidence | VERIFIED |
| REQ-015 | Layout identity covers all pagination-affecting viewport, typography, structure, locale/direction, parser/source, renderer, and algorithm inputs. | BLOCKER | CHANGE-029 covers F001–F211 exactly once with downstream classifier results and typed invalid-evidence rejection. | P05 | Exhaustive field mutation, canonical decoder and physical-identity tests | VERIFIED |
| REQ-016 | Transient reader-control visibility does not change card-body pagination. | HIGH | CHANGE-027/029 prove controls, overlays, keyboard, active/preview wrappers and every Speed Reader state preserve canonical geometry. | P05 | Same ordered identities with controls hidden/visible and stale-preview rejection | VERIFIED |
| REQ-017 | Font fallback or changed resolved metrics is a genuine layout change. | BLOCKER | CHANGE-025/026/029 prove terminal coverage and genuine identity transition for changed metric and opaque-fallback observations; pending/rejected evidence has zero authority. | P05 | Deterministic terminal/pending/rejected/changed font-evidence matrix | VERIFIED |
| REQ-018 | Only an accepted, settled, immutable visible card can become checkpoint authority. | BLOCKER | Screen distinguishes page change and settlement; lifecycle proof absent. | P07–P08 | Real controller/deck settlement and journal assertions | NOT_STARTED |
| REQ-019 | Preview, cancelled, rejected, stale, or mismatched settlements never commit. | BLOCKER | Coordinator/helper guards exist; screen race matrix missing. | P07–P08 | Controlled cancellation/stale callback tests against SQLite journal | NOT_STARTED |
| REQ-020 | Accepted swipe followed immediately by exit durably saves the new card. | BLOCKER | Immediate staging exists; exit ordering unproven. | P07–P08 | Settle→pop/background/close test with reopened exact signature | NOT_STARTED |
| REQ-021 | Route pop, backgrounding, and book switching flush the authoritative pending checkpoint correctly. | BLOCKER | Pop awaits; lifecycle/dispose start unawaited flushes. | P07–P08 | Separate ordered flush tests with explicit completion gates | NOT_STARTED |
| REQ-022 | A previous session/book cannot overwrite or influence the active book. | BLOCKER | Per-book journal/epochs exist; complete two-book lifecycle absent. | P07–P08 | Delayed A write while B active, then A reopen | NOT_STARTED |
| REQ-023 | Existing epoch/revision and stale-write protections are preserved unless evidence supports a replacement. | HIGH | Low-level implementation/tests appear strong; not verified in repaired lifecycle. | P07–P08 | Preserved store suite plus integrated stale-write test | NOT_STARTED |
| REQ-024 | Persistence never executes against a lazy session that has not opened. | BLOCKER | Initialization order appears guarded; no failure/open-cancel proof. | P07–P08 | Failed/cancelled open with persistence spy/store assertion | NOT_STARTED |
| REQ-025 | Previous/next resolves through canonical adjacent card identities. | BLOCKER | Screen begins from committed source anchor but advances via transient local index. | P09 | Canonical adjacency contract across prepared/unprepared boundaries | NOT_STARTED |
| REQ-026 | `_currentPage ± 1`-style indexes are never location truth across publications. | BLOCKER | Current indexes are widely used as projections; durable authority audit incomplete. | P01, P09 | Static owner audit plus reindex/window-replacement tests | NOT_STARTED |
| REQ-027 | Backward prepend preserves the committed card and exact adjacent order. | BLOCKER | Anchor remapping exists; canonical seam proof absent. | P03–P04, P09 | Prepend signature/coverage/visible-card assertions | NOT_STARTED |
| REQ-028 | Generated heading cards have deterministic ownership, identity, and ordering. | BLOCKER | Heading generation exists; seam ownership unproven. | P03–P04, P09 | Heading-before/body/adjacent navigation fixture matrix | NOT_STARTED |
| REQ-029 | Range/navigation preparation failure leaves the current card stable and clears failed/loading state. | BLOCKER | Failure handlers exist; state and visible identity not fully asserted. | P07, P09 | Injected failure with exact current signature and cleared state | NOT_STARTED |
| REQ-030 | Retry creates a fresh intent/generation from the committed anchor. | BLOCKER | Retry closures re-call methods; freshness/anchor evidence absent. | P09 | Generation/intent ID and committed-anchor assertions | NOT_STARTED |
| REQ-031 | TOC, search, Book Memory, bookmark, highlight, note, internal-link, and history jumps resolve through stable source identity. | BLOCKER | Stable call sites/helpers exist; complete paths are not all proved. | P07, P09 | Route-level jump matrix asserting stable target, visible text, settlement | NOT_STARTED |
| REQ-032 | New reader tests derive from approved requirements. | BLOCKER | Audit found many unapproved legacy assumptions. | P01–P03, P10 | Every trusted test names requirement IDs and approved outcome | NOT_STARTED |
| REQ-033 | Important tests use real parsing, pagination, source ranges, signatures, checkpoint serialization, and lifecycle paths wherever practical. | BLOCKER | Current suite mainly uses helpers/handcrafted cards. | P02–P03, P07 | Layered harness proof with documented exceptions | NOT_STARTED |
| REQ-034 | Reader assertions compare stable identity and visible source content, not display indexes or arbitrary counts. | BLOCKER | Current tests frequently assert indexes/counts. | P02–P03, P07, P10 | Assertion review and replacement matrix | NOT_STARTED |
| REQ-035 | Arbitrary delays and uncontrolled `pumpAndSettle` are not proof of settlement. | BLOCKER | Production polling and timing-heavy widget tests remain. | P02, P07, P09 | Explicit completer/fake-clock/event-gate tests | NOT_STARTED |
| REQ-036 | Legacy tests are deleted or substantially rewritten only after stronger replacement coverage and recorded rationale exist. | HIGH | Reconciliation has not begun. | P10 | Replacement evidence and ledger row per changed test | NOT_STARTED |
| REQ-037 | Non-reader test cleanup is deferred unless directly affected by reader repair. | HIGH | Scope is defined; future enforcement required. | All, P10 | Scoped diffs and change-log disclosures | NOT_STARTED |
| REQ-038 | Codex runs no device tests without explicit approval; owner performs final device verification. | HIGH | Planning task complied; release execution remains future. | P11 | Manual handoff record and owner-supplied result | NOT_STARTED |
| REQ-039 | Existing tests remain evidence, not automatic behavioural authority. | BLOCKER | Audit establishes this; future implementation discipline required. | All, P10 | Requirement mapping before production response to any failure | NOT_STARTED |
| REQ-040 | Display indexes must not become canonical. | BLOCKER | Compatibility fields/projections remain and need bounded use. | P01, P04, P09 | Owner audit and reindex tests | NOT_STARTED |
| REQ-041 | Coordinator correction must not be disabled as a repair. | BLOCKER | Correction exists; future changes must preserve it. | P08–P09 | Rejected-callback correction test | NOT_STARTED |
| REQ-042 | No repair may add arbitrary timing delays. | BLOCKER | Existing navigation polling must be replaced, not extended. | P02, P07, P09 | Event-driven async tests and static review | NOT_STARTED |
| REQ-043 | Lifecycle errors must be fixed at ownership/ordering boundaries, not suppressed or merely caught. | BLOCKER | Error handling exists; root ordering is unproved. | P07–P08 | Failure injection with propagated/recorded outcome | NOT_STARTED |
| REQ-044 | The reader must not eagerly paginate the entire book. | BLOCKER | P04 work bounds and P06 per-record/work/restart/chain limits remain green under the live cache path; P11 still owns release profiling. | P04, P06, P11 | Work counters showing bounded source/card generation | CURRENTLY_PASSES_NARROW_CONTRACT |
| REQ-045 | Display-card memory retention must remain bounded. | BLOCKER | CHANGE-037/038 enforce 12-record/12-MiB memory and 48-record/24-MiB disk bounds through long traversal, stable three-record pins and typed pinned pressure; P11 still owns release profiling. | P04, P06, P11 | Peak resident cards/bytes under long traversal | CURRENTLY_PASSES_NARROW_CONTRACT |
| REQ-046 | Clearing caches is not a permanent repair. | HIGH | Scoped invalidation, safe misses, bounded regeneration and the v4 physical rollout recover from corrupt/absent derivatives without clearing parsed source, checkpoints or user data. | P06 | Cold/warm equivalence and controlled invalidation evidence | VERIFIED |
| REQ-047 | Approximate restoration is never accepted for an identical layout. | BLOCKER | Current screen fallback risk contradicts this. | P07–P08 | Exact-miss test proves blocked/rebuild path and unchanged checkpoint | NOT_STARTED |
| REQ-048 | Later chunks cannot repack accepted cards. | BLOCKER | Fixed-snapshot proof retained; immutable card preservation through lazy snapshot and retention handoffs is unproved (CHANGE-040). | P03–P04 | Byte/signature preservation across multiple handoffs and backward regeneration | ARCHITECTURAL_CORRECTION_REQUIRED |
| REQ-049 | The single-owner `StableBookLocation` architecture must not be weakened. | BLOCKER | Model is strong; screen projections and compatibility paths need owner audit. | P01, P08–P09 | Authority map plus all jump/commit tests | NOT_STARTED |
| REQ-050 | Production code must not be distorted to preserve an obsolete legacy test. | BLOCKER | Legacy reconciliation has not begun. | P10 | Test-to-requirement decision and replacement proof | NOT_STARTED |
| REQ-051 | Expected signatures are not automatically updated without explaining the identity change. | BLOCKER | CHANGE-026 reviewed the documented shared-contract signature transition; later phase corpus/reconciliation obligations remain. | P03–P06, P10 | Reviewed source-range diff, requirement link, and ledger rationale | IMPLEMENTED_NOT_VERIFIED |

## 6. Phase dependency map

| Phase | Title | Depends on | Why the dependency exists |
| --- | --- | --- | --- |
| P00 | Planning baseline | — | Establishes stable IDs, scope, and evidence rules. |
| P01 | Behaviour contract and baseline confirmation | P00 | Current owners, paths, and version boundaries must be known before tests or code change. |
| P02 | Trusted harness and controlled fixtures | P01 | The harness needs the complete ownership/version inventory. It also owns the smallest behaviour-preserving extraction that makes the one production paginator callable by P03. |
| P03 | Construction-order characterization | P02 | The controlled micro-fixture and P02-extracted production paginator expose current behaviour—known defect included—through one identity/text oracle. |
| P04 | Canonical pagination and continuation/seam state | P03 | The repair begins only from deterministic failing P03 contracts. It evolves the already-extracted paginator; it does not repeat the extraction. |
| P05 | Measurement/rendering layout contract | P02, P04 | P04 proves order/seam determinism under one controlled layout environment. P05 establishes final measure/render authority, then reruns the complete P03 matrix. |
| P06 | Canonical display caches and migration | P04, P05 | Cache validity is meaningful only after card construction and layout identity are canonical. |
| P07 | Production-path restore/checkpoint lifecycle tests | P02, P05, P06 | Lifecycle fixtures require stable identities, deterministic layout, and controlled cold/warm cache states. |
| P08 | Gated restoration and durable committed authority | P07 | Production repairs must be driven by failing screen/store lifecycle regressions. |
| P09 | Navigation, backward preparation, and retry | P04, P06, P08 | Adjacent navigation requires canonical cards/cache and a settled committed anchor. |
| P10 | Legacy reader-test reconciliation | P03–P09 | Legacy tests can be judged only after stronger requirement-derived replacements exist. |
| P11 | Release gate and manual-device handoff | P04–P10 | Final evidence must exercise the integrated repaired system and reconciled suite. |

Critical path:

```text
P00 → P01 → P02 → P03 → P04 → P05 → P06 → P07 → P08 → P09 → P10 → P11
```

P02's production extraction is a **production test-seam refactor, not behavioural repair**. Its parity evidence must show the extracted API still preserves the current independently packed range behaviour. P03 can therefore characterize the real defect without a P02→P04 dependency. P04 cannot start behavioural work until P03 has deterministic failing evidence. P05 may begin selected discovery after P02, but after any legitimate layout correction it must rerun the full P03 equivalence matrix. P06 alone finalizes persistent cache compatibility, invalidation, migration, and version changes after P04/P05 are stable. Phase boundaries must remain independently reversible: test seam, canonical pagination, layout identity, cache migration, lifecycle authority, and navigation each have different rollback and data-compatibility risks.

## 7. Detailed implementation phases

### P00 — Planning baseline

**Objective.** Establish the authoritative repair scope, stable identifiers, evidence ledger, and current-tree baseline without changing production code or tests.

**Why now.** Every later task needs fixed requirement/task IDs and must distinguish intended work from actual proof.

**Entry criteria.** Approved reader requirements supplied; completed test audit available; repository readable. All were met on 2026-08-27.

**Exact scope.** Read-only inspection of current code, tests, fixtures, reports, status, and history; creation of only these two tracking documents.

**Explicit non-scope.** Any implementation, test execution, test cleanup, fixture creation, formatting, dependency change, schema/version change, device work, or Git mutation.

**Verified files/symbols likely affected.** Only this plan and `docs/development/nalori-reader-reliability-change-log.md`.

**Discovery questions.** None block this planning baseline. Unresolved technical and product questions are registered for later phases.

**Task checklist.**

- [x] TASK-P00-001 — Capture the current branch/commit, dirty-worktree warning, inspected report set, and current architecture evidence.
- [x] TASK-P00-002 — Assign stable requirement IDs `REQ-001` through `REQ-051` and phase/task identifiers.
- [x] TASK-P00-003 — Create the implementation-ready phase, test, migration, risk, decision, release, and maintenance plan.
- [x] TASK-P00-004 — Initialize the append-only change log and cross-check plan/log IDs, task counts, phase counts, and permitted file changes.

**Tests to add before or alongside implementation.** None; this is documentation only.

**Expected failing behaviour before repair.** The audit and current code show blocker gaps, but no test was run or changed in this phase.

**Acceptance criteria and required automated evidence.** Both documents exist; unique requirement IDs and task IDs agree; read-only inspection commands are recorded; only the two requested files were created/updated. No test pass is claimed.

**Required manual evidence.** Product-owner review of this plan's open decisions before behaviour outside the approved contract is encoded.

**Rollback/migration considerations.** Documentation can be amended by a new recorded planning change. Earlier ledger history must not be rewritten.

**Risks.** Current untracked implementation may be mistaken for committed history; historical completion statements may be mistaken for current proof.

**Invariants.** Authority order, dirty-work preservation, no test authority by default, and no implementation work.

**Exit criteria.** Both documents are written and verified; the initial change-log entry exists.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| COMPLETED | Registry only; no implementation requirement completed | — | 4 / 4 | `CHANGE-20260827-001` | None |

### P01 — Behaviour contract and baseline confirmation

**Objective.** Freeze a current, reviewable ownership/call-path/version baseline and turn every approved requirement into an executable scenario before source or test edits.

**Why at this point.** The working tree is substantially ahead of the last committed phase and contains untracked reader infrastructure. Tests and repair boundaries cannot be chosen safely from historical reports alone.

**Entry criteria.** P00 complete; no unrelated work is discarded. `DEC-REQ-001` and `DEC-REQ-002` may affect later P08 failure handling but do not block this read-only investigation.

**Exact scope.** Read-only/source-level call traces for pagination, restore, persistence, layout, cache, navigation, and projections; identification of current versions and authorities; refinement of this plan and ledger when evidence changes scope.

**Explicit non-scope.** Production changes, tests, fixtures, cache/schema bumps, signature changes, or legacy-test edits.

**Verified files/symbols likely affected.** `lib/screens/reader_screen.dart`; `lib/models/stable_book_location.dart`; `lib/models/reader_checkpoint.dart`; `lib/services/reader_checkpoint_store.dart`; `lib/services/progressive_display_state.dart`; `lib/services/display_generation_coordinator.dart`; `lib/services/lazy_book_session.dart`; `lib/services/reader_source_projection_service.dart`; cache services; relevant route/search/Memory/annotation callers; both tracking documents.

**Discovery questions that must be answered first.** Which object is authoritative at every transition? Which exact callback proves settlement for `PageView` and `ReadingCardDeck`? What evidence distinguishes a genuine layout change from a partial publication? Which version fields govern parser, layout, pagination, segment cache, and checkpoint compatibility? Which explicit-jump paths still carry index-only compatibility data?

**Task checklist.**

- [x] TASK-P01-001 — Record a fresh `git status --short`, HEAD, relevant file inventory, and current version constants before implementation; link the snapshot in the ledger.
- [x] TASK-P01-002 — Trace open→restore→publication→controller settlement→commit→flush→close for eager and lazy routes, naming every state owner and hand-off. Depends on TASK-P01-001.
- [x] TASK-P01-003 — Trace append, prepend, eviction replacement, cache hit/miss, controller reattachment, and chapter-layout publication against the committed stable anchor. Depends on TASK-P01-001.
- [x] TASK-P01-004 — Inventory all layout/pagination/cache/checkpoint version fields and write an explicit compatibility decision table without choosing a new value. Depends on TASK-P01-001.
- [x] TASK-P01-005 — Inventory TOC, search, Book Memory, bookmark, highlight, note, internal-link, Back/history, and percentage-jump call sites; classify every index as transient hint, compatibility evidence, or forbidden authority. Depends on TASK-P01-002.
- [x] TASK-P01-006 — Convert discoveries into scenario-level preconditions/events/outcomes mapped to `REQ-*`; add a change-log decision entry for any scope correction. Depends on TASK-P01-002 through TASK-P01-005.

**Tests to add before or alongside implementation.** None in this phase. The output is the contract matrix consumed by P02/P03/P07.

**Expected failing behaviour before repair.** Same-layout exact misses may proceed to source-location restore; independent ranges may disagree; navigation may time-poll; lifecycle durability remains unproved.

**Acceptance criteria.** No unknown competing owner remains undocumented; every approved requirement has at least one executable scenario; all existing version boundaries and explicit-jump entry points are named from current code.

**Required automated evidence.** Exact read-only commands, commit/status, and symbol/path references recorded in a change entry; no test result required.

**Required manual evidence.** None for P01 completion. Product-facing choices remain recorded for their later implementation phases; technical questions stay assigned to code discovery.

**Rollback/migration considerations.** None; no runtime data changes. If the baseline changes during execution, add a new entry rather than editing the old snapshot silently.

**Risks.** Missing a late callback or compatibility writer; confusing a derived display index with authority; expanding into unrelated legacy cleanup.

**Invariants.** REQ-026, REQ-037, REQ-039, REQ-040, and REQ-049.

**Exit criteria.** All six P01 tasks are completed together in one bounded read-only execution: P02/P03/P07 can cite one complete current call-path, ownership, version, and explicit-jump contract; all unresolved gaps are explicit technical discoveries or later product decisions.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| COMPLETED | REQ-026, REQ-032, REQ-039, REQ-040, REQ-049 remain unverified | P00 | 6 / 6 | CHANGE-20260827-003 | No investigation blocker; implementation/test evidence remains required |

**P01 outcome.** Completed as a static current-tree baseline. It does not verify product behaviour or start P02. The detailed evidence, known defects, and P02 seam are recorded immediately below.

### P01 verified current-tree evidence — CHANGE-20260827-003

Static inspection date: 2026-08-27, Asia/Kolkata. Historical reports were used only to locate paths. Every conclusion below names a current-tree symbol. No Flutter/Dart test, analyzer, formatter, generator, migration, emulator, or device command ran.

#### TASK-P01-001 — fresh implementation and version baseline

| Item | Current evidence |
| --- | --- |
| Branch / HEAD | feature/lazy-random-access-reader at 9d7716597d95d578699e7a54544d92d5b4b234b6 (9d77165). |
| Relevant modified state | Modified reader files include models book_chunk, book_metadata, reading_settings; screens book_list_screen, book_loading_screen, book_memory_screen, book_memory_source_detail_screen, book_memory_writing_screen, reader_screen, search_screen; services book_cache_service, bookmark_service, display_generation_coordinator, epub_parser, lazy_book_session, lazy_parsed_book, progressive_display_state, reader_open_service, reader_structural_progress_service, segmented_display_cache_service; and widgets chapter_panel, reading_card, reading_card_deck. This is pre-existing work. |
| Material untracked state | Untracked current-tree reader evidence includes models derived_book_index, reader_checkpoint, reader_text_boundary; services derived_book_index_service, reader_checkpoint_store, reader_source_projection_service, reader_visible_correction_scheduler and related source/normalization services; reader-focused unit/widget tests; and the tracking documents. It is not a committed implementation claim. |
| Material committed state | stable_book_location, lazy_epub_index_service and display_section_memory_cache are committed. The committed bases of reader_screen, lazy_book_session, display_generation_coordinator, progressive_display_state and segmented_display_cache_service are modified in this tree. |
| Directory / test inventory | Reader paths inspected: lib/models/{book_chunk,stable_book_location,reader_checkpoint,derived_book_index,reader_position_session}.dart; lib/services/{reader_open_service,lazy_book_session,lazy_epub_index_service,lazy_parsed_book,lazy_section_repository,book_cache_service,segmented_display_cache_service,display_section_memory_cache,progressive_display_state,display_generation_coordinator,reader_checkpoint_store,reader_source_projection_service,derived_book_index_service}.dart; lib/screens/{book_list_screen,book_loading_screen,reader_screen,search_screen,book_memory_screen}.dart; lib/widgets/{reading_card,reading_card_deck,chapter_panel}.dart. Focused existing tests include checkpoint store, progressive display, segmented cache, lazy session/open, source projection, derived index, reader list pagination and reader navigation settlement. None invokes the production paginator kernel through a trusted lifecycle harness. |
| Static SDK constraints | pubspec.yaml declares app version 1.0.1+2, Dart SDK ^3.9.2, a Flutter SDK dependency and local packages/epubx. No Flutter SDK constraint was declared in inspected repository configuration; no SDK command was run. |

| Identity/version | Defined in and tree status | Current static identity |
| --- | --- | --- |
| Whole parsed source cache | BookCacheService in modified lib/services/book_cache_service.dart | parsedBookCacheFormatVersion 6; wholeBookPreparationVersion whole_book_preparation_v1. |
| Lazy structural index | committed LazyEpubIndexService.schemaVersion | 1; validity also requires file size and modified time; index builds publication fingerprint. |
| Lazy parsed source | modified lib/services/lazy_parsed_book.dart | lazyParsedSectionCacheFormatVersion 3; parser section_v4_lists; dependency schema 1; LazySectionIdentity contains publication, href, checksum, parser and dependency identities. |
| Eager source identity | modified ReaderScreen._ensureCanonicalSourceIdentity | parser version eager_6. |
| Whole display cache | modified BookCacheService | displayCacheFormatVersion 3; displayLayoutVersion v14. Payload writes v but deserialize does not validate it. |
| Segmented display cache | modified SegmentedDisplayCacheService | segmentedDisplayCacheFormatVersion 3; manifest validates book/key/parser/layout/settings/viewport/source-count; payload comparison omits serialized parser version. |
| Memory display cache | committed DisplaySectionMemoryCache | cache key plus SourceChunkRange; no separate format/version or canonical seam identity. |
| Pagination/card | untracked lib/models/reader_checkpoint.dart | readerPaginationAlgorithmVersion nalori_cards_v16_lists; ReaderCardIdentity hashes publication, layout, pagination and ordered source ranges. |
| Layout / metrics | modified reading_settings plus cache-key builders | typography normalization reader_typography_v1; metric identity, locale, scale, viewport and safe-area terms enter layout/cache identities. Paint/measure equivalence is unverified. |
| Stable location | committed StableBookLocation.currentVersion | 2; publication/spine/href/normalized href/checksum/parser/local chunk/offset are durable evidence; legacyGlobalChunkIndex and localDisplayIndex are compatibility fields. |
| Checkpoint journal | untracked ReaderCheckpoint and ReaderCheckpointStore | checkpoint format 1; SQLite schema 1; per-book epoch/revision, checksum, eight retained records. |
| Derived search / Memory index | untracked derived_book_index and service | schema 1; normalization 1; manifest/segment also carry publication, parser, checksum and generation. |
| Legacy preference/metadata position | modified ReaderScreen._persistCommittedPosition and metadata | eager-only last_read_<bookId>; metadata lastReadIndex/lastReadLocation/revision/time are post-checkpoint compatibility mirrors. No separate legacy schema constant found. |

#### TASK-P01-002 — lifecycle and authority trace

The lazy route is primary only while BookLoadingScreen._shouldUseLazyReader permits it. A per-book disable, disabled global flag, or nonmatching NALORI_LAZY_READER_ONLY_BOOK reaches BookLoadingScreen._loadLegacy, which calls BookPreparseService.ensureParsed and pushes ReaderScreen with no LazyBookSession. It is reachable production code.

| Sequence step / scenario | File / symbol | Event/input; state read → state written | Authority before → after | Async / stale-work protection | Failure or fallback |
| --- | --- | --- | --- | --- | --- |
| Cold lazy open, no display cache | BookListScreen._openBook → BookLoadingScreen._loadAndParse → ReaderOpenService.openLazy → LazyBookSession.open/loadAround → ReaderScreen init/_initReadingPosition/_rebuildDisplayChunks | Tap reads metadata/checkpoint; session opens index, resolves target, loads source window, updates last-opened; screen creates checkpoint coordinator, initial progressive state and cards. | candidate metadata/checkpoint → resolved live session source → visible coordinator initial intent after verified publication. | validation/store/index/section awaits; ReaderOpenOperation, mounted, display/rebuild/range generations. | Loading error on open failure; cache miss regenerates; default-publication race remains unproved. |
| Reachable eager/legacy open | BookLoadingScreen._loadLegacy; BookPreparseService.ensureParsed; ReaderScreen without session | Reads whole parsed cache/source; builds or loads whole display cache and initializes screen checkpoint flow. | whole source/index projections → screen/coordinator. | parse/cache awaits, mounted, display token. | Too-large/parse failure shows loading error; legacy prefs/index mirrors remain reachable. |
| Warm compatible cache | ReaderScreen._ensureDisplayChunksBuilt/_loadOrRebuildDisplayChunks; BookCacheService; segmented loader | Reads whole cache first or segmented center/adjacent records; writes display/maps then restore state. | coordinator target/checkpoint → candidate cache window only after anchor resolution. | rebuild token, display token, mounted/range checks. | Whole-cache decode error deletes file and rebuilds; compatibility is key/manifest based, not canonical proof. |
| Exact same-layout checkpoint | ReaderCheckpointCoordinator.initialize/resolveRestore; ReaderScreen restore/verification | Reads valid same-publication checkpoint; exact requires equal layout, pagination and signature; verification enables ordinary writes. | journal card → initial restore intent → verified exact visible card. | store session, post-frame controller attach, intent/window/publication generations. | Coordinator exact miss returns null; separate screen fallback exists below. |
| Genuine layout incompatibility | Coordinator resolveRestore; ReaderScreen verification | Layout or pagination mismatch selects semantic-anchor-containing card and writes a new exact card only during verified restore. | old checkpoint → semantic restore intent → verified current-layout checkpoint. | layout token and restore barrier. | No typed parser/source/layout classifier; semantic branch is broader than approved contract. |
| Same-layout exact signature missing from partial window | Coordinator resolveRestore; ReaderScreen._restorePosition/_scheduleCheckpointPublicationVerification | Coordinator logs same-layout exact miss and returns null; screen keeps pending exact stable location, source-maps it, infers semantic verification and may rewrite. | exact card should remain blocked → source-containing card can commit. | later publication/controller steps still guarded by generation, not by exact-miss class. | VERIFIED_CURRENT_FAILURE: partial absence silently downgrades. |
| Ordinary accepted swipe | ReaderScreen._onPageChanged/_onPageSettled/_runCommittedPageEffects; ReaderPageView/ReadingCardDeck | Page callback writes local visible indexes; settled callback resolves stable card, coordinator accepts, then immutable position is staged/persisted. | coordinator committed location → accepted next stable card. | PageView waits for ScrollEnd; deck callback follows animation; intent expected index/generations reject stale work. | Missing stable or synthetic/mismatched result is rejected and corrected. |
| Preview/cancelled/rejected swipe | ReaderPositionSession; _onPageChanged/_onPageSettled/_restoreAuthoritativeVisibleIndex | Preview changes only local preview/visible fields; rejected/synthetic settlement never runs committed effects. | existing coordinator location remains. | preview/scrub/modal flags; synthetic flag; coordinator/correction controller identity. | Visibility can precede accepted settlement; correction reverts rejected result. |
| Immediate route exit after settlement | _runCommittedPageEffects/_scheduleReadingPositionSave/_flushAndPopReaderRoute | Settled card captures card/location/revision, stages queue and starts flush; PopScope awaits reader persistence before pop. | accepted card → journal → metadata/preferences mirrors. | queue serializes latest revision; store checks epoch/revision; pop waits settings, queue, store, stats. | scheduling catches/logs save failure; production-path proof absent. |
| Background / dispose | didChangeAppLifecycleState, dispose, _stageCommittedLifecycleSnapshot/_flushReaderPersistence | Re-resolves committed anchor, stages snapshot, starts flush; dispose cancels work, disposes coordinator and closes session. | last accepted card → queue/journal only if flush completes. | lifecycle and dispose invoke flush unawaited. | Not awaited; errors are caught at scheduling boundary or can outlive widget/session. |
| Book A → B → A | ReaderCheckpointStore.beginSession/commit; ReaderScreen dispose; ReaderOpenService | Each coordinator begins per-book epoch; commit requires current epoch and newer revision. | A journal/session → B separate journal/session → later A epoch. | store serialization/epoch/revision; screen mounted/intents/generations. | Strong low-level isolation, but no held-write full lifecycle proof. |

Lifecycle findings:

- A card is committed only by an accepted ReaderScreen._onPageSettled decision. PageView.onPageChanged is visual/preview-stage only; ReadingCardDeck.onIndexChanged follows drag/animation completion.
- Visibility can precede settlement because _currentPage, _activeDisplayIndex and ReaderPositionSession.markVisible mutate before acceptance. Only settlement reaches _runCommittedPageEffects and checkpoint staging.
- ReaderCheckpointCoordinator.current with ReaderCheckpointStore is the intended checkpoint authority. Screen indexes/targets, session state, metadata and preferences are projections, transport or mirrors.
- Normal lazy opening transfers a session only after openLazy completes. _captureCommittedPosition has no explicit LazyBookSession-open token check; failed paths with no chunks return before coordinator initialization. This is a narrow static safeguard, not a verified cancellation contract.

#### TASK-P01-003 — lazy publication, anchors, and competing owners

| Publication path | Start authority / source interval | Range state, map and anchor behaviour | Ownership and current risk |
| --- | --- | --- | --- |
| Initial range | Initial coordinator target or _targetOriginalIndex; initialSourceRange then readerFirstVisibleSourceRange. | generateDisplayRange starts empty local maps/pending; lazy target may stop when anchored boundary finalizes; source maps become local display maps. | Target is re-resolved before index assignment, but no predecessor continuation proves card boundary. |
| Forward append | committed stable anchor; nextForwardRange adjacent to prepared tail. | Fresh generator clears pack state; state.append shifts result indexes by existing length. | Source adjacency only; newly flushed tail can alter physical-card seam. |
| Backward prepend | committed stable anchor; nextBackwardRange. | Fresh generator; state.prepend shifts existing local display indexes and remaps source indexes. | Anchor is re-resolved/controller rebased, but predecessor seam/order remains unproved. |
| Cross-section loading | _ensureAdjacentSectionAvailable / lazy integration. | Session changes source window, then adjacent target range generates. | Source indexes are mutable; stable source identities are copied/re-resolved, without canonical continuation. |
| Target/singleton publication | explicit stable intent or _navigateToSourceLocation targetRange. | Range-local empty pack can publishInitial and replace state. | Target may be visible before settlement; exact-miss fallback is verified authority failure. |
| Lazy-window replacement | _navigateToStableLocation/_replaceLazySourceWindow. | Cancels display work, increments rebuild/range generation, discards progressive state and rebuilds target. | Tokens/intents reject stale work; completion still polls time. |
| Memory hit | _loadCachedProgressiveDisplayRange. | Returns stored DisplayRangeResult keyed by cache/range; normal append/prepend path. | No version or canonical seam proof; cannot persist until later accepted settlement. |
| Disk-segment hit | SegmentedDisplayCacheService.loadRange/loadAroundSource. | Manifest/payload-compatible independent range enters same state path. | Records lack card/continuation proof; payload parser comparison omission. |
| Miss/regeneration | _prepareProgressiveDisplayRange invokes generator. | Range generation then optional async cache write; tokens checked before publish. | Stale work generally suppressed; valid request tail is still independent. |
| Eviction/reconciliation | _reconcileLazyWindowAfterEviction or _replaceLazySourceWindowForEviction. | Stable-key remap preserves prepared snapshot where possible; otherwise resets/rebuilds pending stable target. | Exact checkpoint signature checked on remap, but neighboring seam remains unproved. |
| Controller reattachment | _applyProgressiveDisplayState / correction scheduler. | Stable anchor maps to new local index then post-frame controller correction occurs. | Old committed anchor can correct visible index; real platform callback coverage unverified. |
| Chapter calculation/delayed publish | _scheduleChapterCardLayoutCompletion / _activeChapterLayoutTask. | Range waits for or cancels chapter task before fresh request. | Shared renderer/measurement boundary is unclassified. |
| Range failure/retry | _prepareProgressiveDisplayRange failure closure. | Retry reuses captured direction/source interval but gets new range generation. | No fresh explicit stable intent is acquired; P09 owns repair. |

| State field/object | File / symbol | Intended role | Durable or transient | Writers/readers | Visibility/persistence influence | Risk |
| --- | --- | --- | --- | --- | --- | --- |
| ReaderVisiblePositionCoordinator.committedLocation / active intent | display_generation_coordinator | Intended accepted visible authority and intent phases. | Transient session authority. | settlement, restore/nav, publication/correction. | Direct visible target; feeds capture. | Intended sole owner, but screen mirrors compete. |
| ReaderCheckpointCoordinator.current | reader_checkpoint_store | Current checkpoint/restore barrier. | Durable mirror of journal. | initialize/commit/restore; screen. | Restore and write enablement. | Exact-miss screen fallback competes. |
| SQLite checkpoint journal | reader_checkpoint_store | Durable last-read authority. | Durable. | store/coordinator. | Reopen/persistence. | Strong store, lifecycle unverified. |
| _currentPage and _activeDisplayIndex | ReaderScreen | Local current-card coordinates. | Transient. | callbacks/publication/controller/UI. | Directly visible; captured as local hint. | Competing mutable owner; forbidden durable authority. |
| ReaderPositionSession fields | reader_position_session | Preview/modal/local visible/committed index and generation. | Transient. | swipe/scrub/modal/commit. | Gates capture and reflects view. | Projection with no stable identity. |
| _controllerIntent, _syntheticControllerTargetIndex, correction | ReaderScreen/coordinator scheduler | Expected explicit target versus synthetic rebase. | Transient. | nav/publication/settlement/controller. | Accepts or rejects settlement. | Necessary guard; divergent field risk. |
| _pendingDisplayNavigationToken, _pendingExactStableRestore, restore resolution | ReaderScreen/navigation coordinator | Pending publication/restore target. | Transient. | open/restore/nav/publication. | Selects visible target and verification strategy. | Exact-miss pending stable target competes. |
| _targetOriginalIndex, ratio/candidates and source/display maps | ReaderScreen/ProgressiveDisplayState | Local range target/window projection. | Transient. | nav/cache/range/chapter. | Requests range and display position. | Mutable index/ratio must be hint only. |
| rebuild/range generations and display token | ReaderScreen/display coordinator | Reject stale work. | Transient. | rebuild/nav/preemption/async. | Blocks stale publication. | Guard, not compatibility authority. |
| ProgressiveDisplayState ranges/maps | progressive_display_state | Current display snapshot. | Transient/cache-derived. | initial/append/prepend/cache/range. | Direct card/mapping source. | Concatenates pagination islands. |
| ReaderPositionPersistenceQueue | reader_structural_progress_service | Latest position staging/write tail. | Transient staging. | settlement/lifecycle/persist. | Controls durable order. | Background/dispose do not await. |
| Metadata, preferences, LazyBookSession.currentLocation | metadata/ReaderScreen/session | Compatibility/session mirrors. | Durable metadata/prefs; transient session. | Persist after checkpoint; later open reads. | Influences next target only when canonical missing. | Eager index path remains reachable. |

#### TASK-P01-004 — current compatibility decision table

| Stored/current identity | Defined in | Written by / read by | Equality / mismatch effect | Exact restore / semantic migration / cache reuse | Unverified gap |
| --- | --- | --- | --- | --- | --- |
| Publication fingerprint | lazy index/session, stable location, checkpoint | index/session write; ReaderOpenService, resolver, coordinator read | Checkpoint accepted only if equal; mismatch ignores checkpoint and source may initial-open. | Exact no; cross-publication semantic not proven; caches should miss through identity/key. | No typed recovery for unresolvable source. |
| Spine + normalized href | stable location, LazySectionIdentity, card range | parser/session write; projection/resolver read | Direct book/spine/local/href match; resolver has alternate source evidence. | Exact only full match; semantic may use checksum/progression; section cache key includes href. | Ambiguity classifier not centralised. |
| Source checksum + parser version | lazy source identity/stable location | parser/index write; resolver/projection/cache read | Exact source match rejects mismatch; resolver can quote/progression fallback. | Exact no; semantic potentially resolver; lazy cache identity includes both. | Checkpoint branch does not classify parser/source mismatch first. |
| Stable location format version | StableBookLocation.currentVersion 2 | JSON writers/readers | No single restore gate identified by static trace. | Exact/semantic unverified; cache n/a. | P05/P08 need explicit migration/classifier. |
| Pagination algorithm version | reader_checkpoint/card | card/checkpoint write; coordinator read | Exact requires equality; mismatch selects semantic branch. | Exact no; semantic currently yes; display caches do not explicitly validate it. | Cache/card canonicality absent. |
| Layout fingerprint | ReaderScreen/card | card/checkpoint write; coordinator read | Exact requires equal string; mismatch treated as layout change. | Exact no; semantic currently yes; cache key/manifest carries layout terms. | Genuine layout versus partial/default publication unclassified. |
| Card signature inputs | ReaderCardIdentity | display card identity/checkpoint verify | Hash covers publication/layout/pagination plus ordered section/checksum/block/type/offset/content ranges. | Exact no when absent; screen can semantic-anchor; caches do not store signature proof. | Range-local packing can produce noncanonical but internally valid signature. |
| Checkpoint format/integrity and DB schema | ReaderCheckpoint 1 / Store 1 | coordinator/store write/read | Payload checksum/format required; corrupt newest skipped and later removed during commit. | Exact no from invalid record; semantic only a remaining valid record; cache n/a. | No DB upgrade path or approved corrupt-recovery UX. |
| Whole display cache format/layout key | BookCacheService | whole cache write/load; ReaderScreen read | Key has v14/typography/metric/locale/density/viewport/safe area; payload v3 is not validated. | Exact only incidental later card match; semantic can occur in screen; key permits reuse. | Old/noncanonical same-key cache can publish. |
| Segmented manifest/record | SegmentedDisplayCacheService | range cache write/load | Manifest v3 validates book/key/parser/layout/settings/viewport/source count; payload omits parser compare and no signature/continuation. | Exact not guaranteed; semantic later screen path; compatible islands reused. | No cold canonical predecessor/seam evidence. |
| Font metric / typography | reading_settings/cache key/layout fingerprint | settings/layout write; cache/card read indirectly | metric identity/layout key equality; mismatch rebuilds or semantic-restores. | Exact no; semantic yes; cache no key match. | Font readiness and paint/measure agreement unverified. |
| Viewport / card body | cache key and ReaderScreen fingerprint | screen writes; cache/coordinator read | dimensions/safe areas/card depth/scale/margins/settings enter key. | Exact no; semantic yes; cache no key match. | Overlay, bottom, publisher padding, direction and renderer box parity unclassified. |
| Derived search / Memory identity | DerivedIndexManifest/Segment/Range | derived session write; BookLoading/ReaderScreen read | schema/normalization/book/publication/parser/checksum/generation required. | Stable target still resolves source; stale derived range rejected; cache applies only to derived index. | Legacy callers can provide index/offset hints without range. |

Identical layout currently means equal layout fingerprint and pagination version plus matching card signature. A genuine layout change is inferred, not typed. Parser/source incompatibility is source-resolution evidence rather than a restore class. An old whole display payload is not payload-version checked. Partial exact-signature absence is a verified failure, corrupt checkpoints safe-miss, and an unresolvable semantic anchor has no approved product recovery. Classifiers/migrations remain P05/P06/P08; P01 chooses no version.

#### TASK-P01-005 — explicit jump and index authority

| Entry point | Caller / input | Stable evidence and mutable index class | Resolver/publication/settlement/final checkpoint | Status |
| --- | --- | --- | --- | --- |
| TOC/chapter | ChapterPanel callbacks; chapter location or chunkIndex | Stable when provided; legacy chunkIndex is COMPATIBILITY_EVIDENCE. | Lazy stable navigation common intent; legacy _navigateToSourceLocation. | Stable primary; legacy bypass reachable. |
| Search | ReaderScreen search result / DerivedSourceRange | Stable location, source segments, generation; display hint TRANSIENT_HINT. | Validates range then common stable intent/settlement. | Narrow lazy path strong; lifecycle unverified. |
| Book Memory | Memory/detail/writing screens → BookLoading initialDerivedSourceRange; fallback original index/offset | Derived target stable; fallback index/offset COMPATIBILITY_EVIDENCE. | Derived validates before open; fallback source navigation. | Fallback UNVERIFIED and must lose authority. |
| Bookmark | _navigateAndMigrateLegacyBookmark | Stable durable; legacy chunkIndex COMPATIBILITY_EVIDENCE. | Lazy resolves/migrates then stable; no-session direct source. | Eager compatibility bypass. |
| Highlight/note | _navigateAndMigrateLegacyAnnotation | Stable durable; original index/offset COMPATIBILITY_EVIDENCE. | Lazy resolves/migrates then stable; eager direct source. | Eager bypass. |
| Internal link/footnote | _onLinkTap anchor or legacy map index | Lazy resolved anchor stable; legacy index COMPATIBILITY_EVIDENCE. | Lazy common stable intent; legacy direct jump/source. | Settlement paths diverge. |
| Reader Back/history | _navigateBackLink history location or chunk index | Stable durable; legacy chunkIndex COMPATIBILITY_EVIDENCE. | Lazy stable; legacy direct source. | Stale callback case unverified. |
| Progress/scrubber | structural scrub policy / weighted progression | Lazy stable location after release; preview display index TRANSIENT_HINT; eager page index FORBIDDEN_AUTHORITY across windows. | Lazy stable navigation; eager direct page jump. | Lazy narrow contract only. |
| Next/previous | _nextReaderPage/_previousReaderPage | currentPage plus/minus one is FORBIDDEN_AUTHORITY across publication. | Local movement/boundary preparation then normal settlement. | Verified architecture risk, P09. |
| Restored last read | ReaderOpenService and ReaderScreen restore | checkpoint stable/card/semantic anchor; local display is compatibility only. | Coordinator intent → verification → checkpoint. | Same-layout partial miss VERIFIED_CURRENT_FAILURE. |
| Library/open handoff | BookListScreen/BookLoading/ReaderOpenService | Normal open has no index; optional derived range stable. | Lazy resolves before ReaderScreen; legacy separate. | Stable except legacy explicit inputs. |

Lazy stable paths use _navigateToStableLocation, LazyBookSession.prepareNavigation, ReaderVisibleNavigationIntent and accepted _onPageSettled before capture. Eager/legacy fallbacks and next/previous cross-window arithmetic do not meet that contract. Synthetic settlement is rejected, but visibility can occur before verified settlement; stale work is guarded by intent, mounted/session, rebuild/range generation, publication token and controller identity rather than one state field.

#### TASK-P01-006 — executable scenario contract

| Scenario ID | Requirements | Preconditions / trigger order | Expected authority / forbidden outcome | Production path | Trusted layer | Repair | Current result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SCN-P01-001 exact same-layout reopen | REQ-001, REQ-018 | Saved exact card; reopen unchanged. | Exact signature settles; not source-only approximation. | coordinator + ReaderScreen restore | P07 | P08 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-002 genuine layout change | REQ-002, REQ-014–REQ-017 | Same source, classified changed layout. | Verified semantic card then new exact; not unclassified downgrade. | layout transition/restore | P05/P07 | P08 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-003 partial exact miss | REQ-003, REQ-047 | Same layout; initial window omits signature. | Barrier stays closed; not fallback/rewrite. | resolveRestore/screen restore | P07 | P08 | VERIFIED_CURRENT_FAILURE |
| SCN-P01-004 canonical regeneration | REQ-007–REQ-010, REQ-048 | Controlled source/layout across orders. | Equal ordered identities; not seam-dependent cards. | paginator/progressive state | P02/P03 | P04 | UNVERIFIED |
| SCN-P01-005 default publication race | REQ-004–REQ-006 | Hold target, publish default/cache. | Only active restore settles; not default authority. | publication/settlement | P07 | P08 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-006 accepted swipe then exit | REQ-020–REQ-021 | Settle, then immediate pop. | Latest journal flushes; not lost/preview card. | settlement/queue/pop | P07 | P08 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-007 cancelled swipe then exit | REQ-019–REQ-021 | Preview/cancel then exit. | Old committed card persists; not preview. | callback/settlement/exit | P07 | P08 | CURRENTLY_PASSES_NARROW_CONTRACT |
| SCN-P01-008 A/B stale write | REQ-022–REQ-024 | Hold A write; settle B; reopen A. | Per-book epoch/revision isolation; not contamination. | store/session/dispose | P07 | P08 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-009 failed/cancelled open | REQ-043, REQ-049 | Fail before openLazy transfer. | No unowned persistence; not pre-open commit. | ReaderOpen/BookLoading | P07 | P08 | CURRENTLY_PASSES_NARROW_CONTRACT |
| SCN-P01-010 forward append | REQ-009–REQ-010, REQ-048 | Settled initial tail. | Exact anchor/successor order; not flushed-tail seam. | progressive append | P03 | P04/P09 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-011 backward prepend | REQ-009–REQ-010, REQ-027, REQ-048 | Settled initial head. | Exact predecessor/current order; not index-shift seam. | prepend | P03/P07 | P04/P09 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-012 cold/warm/eviction | REQ-009, REQ-046, REQ-048 | Same layout all cache states. | Identical ordered identities/anchor; not canonical island. | caches/eviction | P03/P06/P07 | P06 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-013 singleton expansion | REQ-007–REQ-010, REQ-048 | Target first then adjacent content. | Target signature persists; not repacked. | target/append/prepend | P03 | P04 | UNVERIFIED |
| SCN-P01-014 heading boundary | REQ-011, REQ-028 | Generated heading at seam. | One owner/order; not skip/duplicate. | chapter/range work | P02/P03 | P04/P09 | UNVERIFIED |
| SCN-P01-015 failure/retry | REQ-029–REQ-030, REQ-042 | Fail held boundary range then retry. | Fresh anchor/generation; not old target commit. | retry/navigation poll | P07/P09 | P09 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-016 explicit jumps | REQ-025, REQ-031, REQ-049 | TOC/search/Memory/bookmark/highlight/note target each. | Stable target/common settlement; not caller-index bypass. | inventory above | P07/P09 | P09 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-017 controller reattach | REQ-041, REQ-049 | Committed anchor then controller rebuild. | Coordinator anchor corrects; not old callback commit. | correction/post-frame | P07 | P08/P09 | STRONGLY_SUPPORTED_RISK |
| SCN-P01-018 delayed chapter publish | REQ-005, REQ-011, REQ-042 | Delay/preempt chapter task. | Latest intent publishes; not pending/default authority. | chapter/range scheduler | P07/P09 | P08/P09 | STRONGLY_SUPPORTED_RISK |

#### P01 decisions, blockers, and corrected downstream scope

- No new requirement is needed; findings map to existing REQ-001–051, especially REQ-001–010, REQ-018–031 and REQ-040–049. No requirement status becomes VERIFIED from static inspection.
- No product choice blocks P02. DEC-REQ-001 and DEC-REQ-002 are P08 decisions; DEC-REQ-003 is optional for core P02/P03/P04; DEC-REQ-004 is P11-only.
- Technical blockers for repair/testing, not P01: no test-callable production paginator; no canonical continuation/seam proof; no shared paint/measurement classifier; unawaited lifecycle flushes; broad exact-miss fallback; time polling; reachable legacy/index callers.
- Exact P02 extraction seam: mechanically extract the complete range-local kernel inside ReaderScreen._rebuildDisplayChunks: generateDisplayRange plus captured newDisplayChunks, newDisplayToOriginal, newOriginalToDisplay, pending, pendingOriginals, splitChunkByHeight, mergeChunks, flush, tryRebalancePendingWithTinyNext, measurement/height callbacks, scheduler checkpoint/cancellation adapter, and anchored-finalization input. ReaderScreen supplies current layout/measurement/diagnostic adapters; the sole production API returns existing DisplayRangeResult unchanged. Extracting only the named closure leaves its mutable packing kernel inaccessible and invites duplicate test logic.
- Recommended P02 grouping: (1) contract support and controlled fixture provenance, (2) deterministic layout/store/event adapters, and (3) one mechanical paginator-kernel extraction with parity proof. P03 characterizes that one implementation; P04 alone changes continuation/seams. No P02 task is started here.

### P02 — Trusted reader harness and controlled fixtures

**Objective.** Build a layered, deterministic reader-contract test foundation that reaches real parsing, pagination, identity, persistence, and screen lifecycle paths while keeping each layer's claim bounded.

**Why at this point.** Characterization and repair tests need shared fixtures and event controls. Creating them after implementation would allow the implementation to define the oracle.

**Entry criteria.** P01 contract/owner maps complete; controlled micro-fixture provenance/range-review rules defined; proposed test and production-seam paths confirmed not to conflict with current work. `DEC-REQ-003` is not an entry criterion.

**Exact scope.** New reader-contract test support, deterministic controlled micro-fixture manifests/builders, host layout environment, isolated cache/SQLite roots, explicit async controls, narrowly documented fakes, and—if necessary—the smallest mechanical production extraction that exposes the current paginator to tests.

**Explicit non-scope.** Canonical continuation, construction-order repair, changed split/merge/flush/identity/output behaviour, cache-format/version changes, legacy-test deletion/rewrites, device tests, network calls, arbitrary sleeps, whole-book pagination, or unexplained signature snapshots. P02 must not retain both the old closure and a second independent paginator implementation.

**Verified files/symbols likely affected.** Current test examples in `test/unit/services/feature_rich_lazy_reader_fixture_test.dart`, `lazy_book_session_test.dart`, `reader_checkpoint_store_test.dart`, `segmented_display_cache_service_test.dart`, widget tests, `test/fixtures/books/feature_rich_lazy_reader.epub`; production `lib/screens/reader_screen.dart` (`_rebuildDisplayChunks`, local `generateDisplayRange`, split/merge/flush helpers); production models `ReaderCardIdentity`, `DisplayRangeResult`, and `BookChunk`; production seams named in P01. Proposed new paths, to be created only in this phase: `test/reader_contract/support/`, `test/reader_contract/fixtures/`, focused contract files under `test/reader_contract/`, and, only if mechanical extraction is required, one production paginator component such as `lib/services/reader_card_paginator.dart`.

**Discovery questions that must be answered first.** Can the production paginator be invoked without mounting the whole screen? If not, which smallest closure boundary can be mechanically extracted while retaining its current inputs and output behaviour? Which fonts are bundled and deterministically available in host tests? Which SQLite/path-provider seams can use real production adapters with temporary roots? Realistic public-domain edition selection is deliberately deferred and does not gate the core path.

**Task checklist.**

- [x] TASK-P02-001 — Define the proposed `test/reader_contract/` layer boundaries, naming rules, requirement annotations, and prohibited assertion patterns. Depends on P01.
- [x] TASK-P02-002 — Create a fixture manifest format recording origin, license, checksum, structures, purpose, manually validated anchors/ranges, and permitted updates. Depends on TASK-P02-001.
- [x] TASK-P02-003 — Design/build minimal controlled EPUB fixtures for split paragraphs, repeated text, headings/generated fragments, lists/tables/inline spans, and cross-section seams; document every expected source range. Depends on TASK-P02-002.
- [ ] TASK-P02-004 — Optionally select and document a small realistic public-domain Gutendex corpus after owner approval of exact editions and repository size/license policy. It is supplementary coverage, has no network access in tests, and may be deferred without blocking P02 exit, P03, or P04. Depends on TASK-P02-002 and DEC-REQ-003.
- [x] TASK-P02-005 — Create a test-callable production paginator API. If `ReaderScreen`'s local closure cannot be invoked safely, mechanically extract that one implementation into a production component during P02 as a **production test-seam refactor, not behavioural repair**. Preserve current packing, splitting, flushing, identity, and output behaviour—including the independently packed-range defect—without duplicate test logic or coexisting independent old/new implementations. Add focused parity/characterization evidence for controlled inputs, and expose complete ordered source ranges, `ReaderCardIdentity` values, and visible text for P03. Depends on TASK-P02-001, TASK-P02-003, and TASK-P02-006; does not depend on P04. Completed by `CHANGE-20260829-007`: `ReaderCardPaginator.paginate` now owns the one kernel used by both `ReaderScreen` and direct controlled-layout parity tests; no canonical behavior was changed.
- [x] TASK-P02-006 — Establish deterministic viewport, safe-area, locale, direction, text-scaler, font readiness, and renderer configuration for host tests. Depends on P01 layout inventory. Completed by `CHANGE-20260828-006` with verified root-bundle Lexend 400/600/700/900 assets under a test-only alias, byte-identity diagnostics, explicit fail-closed validation and focused host-state restoration evidence. This is a controlled P03/P04 host environment, not P05 measurement/render parity.
- [x] TASK-P02-007 — Establish per-test temporary filesystem, segmented/whole cache, SQLite checkpoint, preferences, and singleton reset isolation using production stores wherever practical. Depends on TASK-P02-001. Completed by `CHANGE-20260828-005` with unique roots/identities, real configurable stores and focused isolation/awaited-teardown evidence.
- [x] TASK-P02-008 — Provide explicit completers/event probes/fake clock only at real async boundaries and document what each fake replaces and cannot prove. Depends on TASK-P02-001 and P01 settlement trace. Completed by `CHANGE-20260828-005` with typed gates/probes only; no fake clock was added because no relevant injected clock boundary exists.

**Tests to add before or alongside implementation.** Harness self-tests for isolation, controlled micro-fixture checksums/provenance/manual source-range review, deterministic font/layout readiness, real checkpoint DB creation, proof that the paginator API uses the one production implementation, and focused parity/characterization cases showing extraction preserves current results for controlled inputs.

**Expected failing behaviour before repair.** The screen-local closure may require the authorised mechanical extraction. After extraction, P03 construction-order cases should demonstrate the current independently packed-range mismatch. That failure is expected evidence, not a reason to weaken assertions or change P02 extraction behaviour.

**Acceptance criteria.** Tests can call one real production paginator and compare complete ordered source ranges, card identities, and visible text without relying on indexes; parity cases show extraction has not changed current results; async completion is event-driven; repeated tests start from clean isolated stores; each mock has an explicit limitation. Controlled synthetic/micro EPUBs are sufficient; realistic public-domain fixtures are optional and do not gate P02.

**Required automated evidence.** Focused harness/fixture test commands with counts and exit status; repeat at least one deterministic fixture twice; `git diff --check` for the scoped phase.

**Required manual evidence.** Human review of controlled micro-fixture XHTML, source offsets, structures, and expected ranges. Approval of realistic public-domain editions is required only before TASK-P02-004 adds them.

**Rollback/migration considerations.** Test-only additions must be removable without runtime effects. The production test-seam extraction must preserve behaviour and remain independently revertible; it changes no persistent format/version. Fixture checksum changes require a ledger explanation and cannot be hidden as snapshot updates.

**Risks.** The extraction accidentally changes range-local packing, splitting, flushing, identity, or output; two paginator implementations drift; tests reimplement pagination in the oracle; production dependencies hide behind fakes; nondeterministic fonts; oversized fixtures; tests prove only serialization.

**Invariants.** REQ-032 through REQ-035, REQ-039, REQ-042, REQ-044, and REQ-051.

**Exit criteria.** P03 can invoke the one behaviour-preserved production paginator through a test-callable API, using controlled micro-fixtures and complete identity/range/text output; P03 and P07 can express their matrices without new ad hoc fakes, delays, mutable-index assertions, duplicated production logic, or realistic-public-domain fixture selection.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| CORE_COMPLETED | REQ-032–REQ-035, REQ-039, REQ-042, REQ-051 remain unverified | P01 | 7 / 8 | CHANGE-20260827-004; CHANGE-20260828-005; CHANGE-20260828-006; CHANGE-20260829-007 | None for the approved core path; DEC-REQ-003/TASK-P02-004 remain explicitly deferred and non-blocking |

### P02 first-slice evidence — CHANGE-20260827-004

`TASK-P02-001` through `TASK-P02-003` created source truth only; they did not extract the paginator, characterize construction order, or change runtime behaviour. `test/reader_contract/README.md` establishes the authority order `approved requirement → trusted test → implementation`, layer ownership, requirement annotations, permitted fakes, and prohibitions on mutable-index truth, count-only assertions, copied pagination, uncontrolled delay/`pumpAndSettle`, network use, shared stores, unexplained snapshots, and handcrafted-card lifecycle claims.

| Evidence | Current path / result | Bound of the claim |
| --- | --- | --- |
| Fixture contract | `test/reader_contract/fixtures/reader_contract_fixture_manifest.json`; `test/reader_contract/support/reader_contract_fixture.dart` | The manifest validates visible component paths/SHA-256, provenance, purpose, structures and source evidence, OPF spine order, anchors, repeated-text locations, seam endpoints, and independently authored UTF-16 half-open ranges. It does not derive its oracle from production parsing or pagination. |
| Controlled EPUB | `test/reader_contract/fixtures/reader_core_micro/` | Two-spine generated EPUB source includes chapter/subsection headings, short mergeable prose, a long rocket-containing paragraph, repeated prose at two anchors, ordered list, table, bold/italic spans, footnote-style link, heading/seam source and cross-section continuation. No opaque archive, physical-card signature, or card-count oracle is committed. |
| Focused foundation test | `test/reader_contract/parser_source/reader_contract_fixture_test.dart` | Five focused checks prove manifest rejection paths, deterministic logical archive entries, OPF spine order, independent range consistency, and current `EpubParserService` source/structure exposure. It does not prove production pagination, cache, checkpoint, or ReaderScreen lifecycle behaviour. |
| Existing fixture boundary | `test/fixtures/books/feature_rich_lazy_reader.epub` | Inspected only for conventions. It remains non-authoritative because it lacks the new visible-source/provenance/range manifest contract. |

The focused parser run opened the generated fixture as `Nalori Reader Core Micro Fixture` with two top-level chapters, 20 chunks and 65 parser anchors. This is parser-source evidence only; all requirement dashboard rows remain `NOT_STARTED`.

**Historical status at CHANGE-20260827-004.** The micro-fixture source truth was established, while deterministic viewport/font/renderer configuration (`TASK-P02-006`), production temporary-store isolation (`TASK-P02-007`), explicit real-boundary event controls (`TASK-P02-008`) and the production paginator seam (`TASK-P02-005`) were still absent. The current status and next scope are updated by CHANGE-20260828-005 below. Human review of the visible XHTML/oracles remains required by the overall P02 manual-evidence gate; it does not require a public-domain corpus.

### P02 deterministic-control evidence — CHANGE-20260828-005

**Historical status at `CHANGE-20260828-005`.** `TASK-P02-007` and `TASK-P02-008` were complete test-support work only. `TASK-P02-006` remained incomplete because the repository/app asset configuration then had no local reader text font. No production reader, paginator or layout implementation was changed to create a seam.

| Evidence | Verified test-support path / result | Bound of the claim |
| --- | --- | --- |
| Layout declaration and fail-closed font loader | `test/reader_contract/support/reader_contract_layout_environment.dart`; `reader_contract_layout_environment_test.dart` | Records deterministic logical surface, DPR, viewport, safe area, card body, scaler, locale, direction, typography/strut declarations, controls, font family/weights/assets, declared metric identity and media inputs; blocks runtime font fetching; restores Flutter test bindings. It cannot report current reader-font readiness, resolved font metrics or measure/render parity without an approved local reader font. |
| Temporary storage sandbox | `test/reader_contract/support/reader_contract_sandbox.dart`; `reader_contract_sandbox_test.dart` | Creates unique temp roots/identities and isolates real configurable whole/segmented/memory caches, lazy/derived indexes and `ReaderCheckpointStore` SQLite; uses only a SharedPreferences platform mock. It proves temporary-store close/reopen/isolation, not ReaderScreen injection, default-path service behavior or OS preference durability. |
| Explicit async controls | `test/reader_contract/support/reader_contract_async.dart`; `reader_contract_async_test.dart` | Provides typed one-shot gates and per-test chronological evidence without elapsed-time correctness. It cannot prove production stale-work acceptance, controller attachment/publication, settlement or persistence completion until a real boundary exposes those events. |

**Historical missing production seams at `CHANGE-20260828-005`.** (1) `ReaderSettings` selected Google Fonts but the then-current app assets declared no local reader text font, so `FontLoader` had no permitted input and resolved metric identity remained a P05 concern. (2) `BookCacheService.clearAll()` also clears a default-path `LazyEpubIndexStore`; sandbox cleanup therefore cannot call it, and ReaderScreen currently does not inject the individually configurable cache/index instances. (3) The screen-local paginator scheduler, controller attachment, display publication/settlement and final persistence completion do not expose an injectable/observable event boundary; P02-005, P07 and P09 must expose/use real boundaries rather than a test coordinator.

**Historical risks/blockers at `CHANGE-20260828-005`.** Temporary-store and generic async support then existed, but P02 still lacked a ready local reader-font environment (`TASK-P02-006`) and the single behaviour-preserving production paginator seam (`TASK-P02-005`). `TASK-P02-004` remained explicitly deferred and non-blocking. No P03 task had started; P02 support self-tests did not verify any product requirement.

**Historical recommended next P02 scope.** First resolve the missing bundled reader-font seam in a separately authorized, non-production-repair task. Then run `TASK-P02-005` alone: mechanically extract the complete existing ReaderScreen paginator kernel into one callable production implementation, preserve all current behavior (including the known defect), and add only focused parity evidence with the controlled fixture. Keep `TASK-P02-004` deferred.

### P02 bundled reader-font evidence — CHANGE-20260828-006

`TASK-P02-006` is complete as deterministic test infrastructure. The current
production default is `ReaderFontFamily.lexend` / regular, selected by
`ReadingSettings.getTextStyle` through `GoogleFonts.lexend`; `ReadingCard`
also requests w600 structural/list text, w700 inline bold and w900 headings.
The installed `google_fonts` 8.0.2 Lexend descriptor table supplies verified
normal static delivery objects for each of those weights. No production Dart
font selection or pagination behavior changed.

| Evidence | Verified test-support path / result | Bound of the claim |
| --- | --- | --- |
| Controlled local assets | `assets/fonts/reader_contract/Lexend-Regular.ttf`, `Lexend-SemiBold.ttf`, `Lexend-Bold.ttf`, `Lexend-Black.ttf`; `OFL.txt`; `PROVENANCE.md` | The upstream SIL OFL 1.1 licensed Lexend 400/600/700/900 static bytes, origin URLs, API filenames and SHA-256 asset identities are committed and reviewable. Asset checksums are not resolved glyph-metric identities. |
| Root-bundle layout environment | `test/reader_contract/support/reader_contract_layout_environment.dart`; `reader_contract_layout_environment_test.dart`; `pubspec.yaml` | The standard P03/P04 declaration deterministically records all layout/media inputs, disables runtime Google Fonts fetching, verifies and loads all four declared root-bundle assets under `NaloriReaderContractLexend`, then reports ready. It fails clearly for incomplete, corrupt or undeclared assets and restores mutable test bindings on close. |
| Focused font self-test | `rtk flutter test test/reader_contract/support/reader_contract_layout_environment_test.dart` | Nine self-tests passed: equal declarations, distinguishing inputs, root-bundle readiness, repeated installs, safe-area/controls isolation, test-state restoration, undeclared/missing asset failure, corrupt bytes and incomplete declarations. It does not prove production measurement/render parity, actual fallback resolution, physical-card boundaries or pagination. |

**Historical state at CHANGE-20260828-006.** Six of eight tasks were complete.
`TASK-P02-004` was explicitly deferred and non-blocking, while
`TASK-P02-005` remained the only core execution blocker. The current state is
updated by `CHANGE-20260829-007` below.

### P02 production paginator extraction evidence — CHANGE-20260829-007

`ReaderScreen._rebuildDisplayChunks` now captures its existing layout values,
scheduler priority, cancellation/generation checks, diagnostics and optional
anchor in a `ReaderCardPaginatorRequest`, then calls the single production
`ReaderCardPaginator.paginate` kernel. The kernel returns the existing
`DisplayRangeResult`; screen scheduling, cache publication, controller
settlement, navigation and persistence ownership remain outside it.

The focused trusted-fixture parity cases call that same method with the
controlled Lexend environment and freeze ordered visible text, structure,
half-open source/display ranges, spine/logical-block identity ranges, complete
`ReaderCardIdentity` signatures, anchor finalization, current range-local tail
flush and cancellation classification. The old closure was private, so a
direct pre-extraction call was impossible; unchanged pre/post host tests,
direct kernel evidence, screen delegation and a one-implementation source
review are the strongest practical alternative. The baseline is extraction
evidence only, not a canonical P03 oracle or construction-order expectation.

**Current P02 state.** The approved core is complete at seven of eight tasks.
`TASK-P02-004` remains unchecked, deferred and non-blocking. P03 is complete
at seven of seven tasks, while no pagination or cache product requirement is
verified merely by the red characterization. P04 entry criteria are met, but
every P04 task remains unstarted.

### P03 — Pagination construction-order characterization

**Objective.** Add approved, expected-to-fail regressions that expose the current range-boundary, load-order, cache-order, and heading-seam defects using complete physical-card identity sequences.

**Why at this point.** P04 must repair a precisely demonstrated contract. Characterization must precede canonicalization and must not bless current output merely because it is current.

**Entry criteria.** P02 controlled micro-fixture, test-callable behaviour-preserved production paginator, layout host, and identity oracle available; P01 contract matrix complete. Realistic public-domain fixture selection is not required.

**Exact scope.** Tests only for construction-order/card-identity/coverage/cache equivalence. Expected failures are recorded honestly.

**Explicit non-scope.** Production paginator changes, version bumps, cache clearing, snapshot approval, reader lifecycle, or legacy-test cleanup.

**Verified files/symbols likely affected.** Proposed new pagination contract files in `test/reader_contract/`; controlled fixtures/support from P02; the P02-extracted production paginator API; current production `ReaderCardIdentity` and `DisplayRangeResult`. Existing tests remain unchanged.

**Discovery questions that must be answered first.** What is the smallest canonical predecessor context required to finalize a target card? How are section-start/end and generated-heading ownership represented? Which cached records are able to recreate continuation state?

**Task checklist.**

- [x] TASK-P03-001 — Record the full-section baseline as ordered source ranges, signatures, and visible text for each controlled fixture; manually validate the oracle rather than accepting current snapshots. Depends on P02. Completed by `CHANGE-20260829-008`: one full `[0,20)` reader-core-micro-v1 production request under controlled Lexend has independently reviewed source/display/logical-card evidence, coverage diagnostics and a noncanonical comparison projection; it establishes no construction-order equivalence.
- [x] TASK-P03-002 — Compare target-first construction at every meaningful anchor against the full-section baseline. Depends on TASK-P03-001. Completed by `CHANGE-20260830-009`: fifteen authored anchors use the real target-range selector, paginator and progressive append/prepend owner; twelve deterministic physical-sequence equality failures remain red.
- [x] TASK-P03-003 — Compare forward-first and backward-first construction, including ranges that cut through mergeable and split paragraphs. Depends on TASK-P03-001. Completed by `CHANGE-20260830-009`: five meaningful partition plans run in both directions; the merge/long/repeat plan fails in both directions, while the Lexend split-stress declaration proves four contiguous physical ranges for source 7.
- [x] TASK-P03-004 — Compare singleton-target publication followed by bidirectional expansion against the same canonical sequence. Depends on TASK-P03-001. Completed by `CHANGE-20260830-009`: five prose/structural anchors run both expansion orders; mergeable prose and the subsection heading remain independently flushed identity islands in four deterministic red cases.
- [x] TASK-P03-005 — Compare cold generation, warm memory cache, warm disk segment cache, eviction, and reload using independently generated expected sequences. Depends on TASK-P03-001 and P02 isolation. Completed by `CHANGE-20260831-010`: twelve sandboxed standard-Lexend cache cases exercise real memory and segmented-disk stores across two reviewed plans; seven controls pass and five merge/long/repeat replay states remain deterministically red with complete coverage.
- [x] TASK-P03-006 — Assert heading/generated-fragment ownership, repeated-text disambiguation, lists/tables/inline spans, and section-seam half-open coverage. Depends on TASK-P03-001. Completed by `CHANGE-20260830-009`: six full/target/forward/prepend/singleton constructions pass independently authored ownership, visible-content and complete half-open coverage assertions even where physical membership differs.
- [x] TASK-P03-007 — Record every expected failure by requirement and exact mismatch; prove the test fails for the intended identity/coverage reason before P04 starts. Depends on TASK-P03-002 through TASK-P03-006. Completed by `CHANGE-20260831-010`: a directly testable 23-row ledger maps all 18 construction and five cache failures to stable IDs, exact requests/evidence, requirements, coverage, repeatability, prohibited shortcuts and P04/P06 repair ownership; its three integrity tests pass.

**Tests to add before or alongside implementation.** All tasks in this phase are tests. Each must compare the full ordered identity list, ordered half-open ranges, and visible source text; count-only or index-only checks are forbidden.

**Expected failing behaviour before repair.** Target/range boundaries produce different first/last cards; separately flushed tails create seams; backward/forward order and cache source can change signatures; heading seams may acquire inconsistent ownership.

**Acceptance criteria.** Every approved construction order and cache state is represented under one controlled explicit layout environment; failures are deterministic and diagnostic; complete ordered source ranges, card identities, and visible text are compared; no expectation is copied from a legacy test, current arbitrary count, or unreviewed full-section output.

**Required automated evidence.** Exact focused commands, test counts, mismatched signature/range diagnostics, captured exit codes, and up to three reruns of any suspicious file.

**Required manual evidence.** Review controlled fixture XHTML, source offsets/half-open ranges, structures, and the proposed canonical sequence. Full-section current output is an input for comparison, never automatically the correct oracle. This is source/content review, not device testing.

**Rollback/migration considerations.** No runtime migration. Tests must remain failing until P04/P06 repairs; they must not be skipped.

**Risks.** Treating full-section current output as automatically correct; enormous parameter matrices; failure messages that reveal only a count; accidental cache reuse in the cold case.

**Invariants.** REQ-007 through REQ-013, REQ-027, REQ-028, REQ-032 through REQ-035, REQ-048, and REQ-051.

**Exit criteria.** The current defect is reproducible through the real paginator in all required dimensions and P04 has a precise red test set.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| COMPLETED | REQ-007–REQ-013, REQ-027–REQ-028, REQ-032–REQ-035, REQ-048, REQ-051 remain unverified | P02 | 7 / 7 | `CHANGE-20260829-008`; `CHANGE-20260830-009`; `CHANGE-20260831-010` | None; P03 exit criteria and P04 entry criteria are met |

### P03 full-range characterization evidence — CHANGE-20260829-008

`TASK-P03-001` records one real `ReaderCardPaginator.paginate` request over
the complete twenty-source-unit `reader-core-micro-v1` fixture interval under
the deterministic controlled Lexend environment. The trusted test projects all
nine current physical cards with structural type, raw/decoded visible text,
source/display/logical half-open ranges, spine/logical-block identity fields,
calculated `ReaderCardIdentity`, full source coverage, repeated-prose identity,
and observable origin labels. The source oracle is transcribed from the
manifest, transparent XHTML and ordered OPF spine; it contains no card count or
signature oracle. The complete current full-range membership is reviewed
characterization evidence only, not a canonical expected sequence or proof of
any other construction order. See the append-only ledger for the full boundary
review, identity signatures, diagnostics and focused command result.

### P03 construction-order matrix evidence — CHANGE-20260830-009

`TASK-P03-002/003/004/006` use one shared test harness that invokes only
`ReaderCardPaginator.paginate` and publishes each returned result through the
real `ProgressiveDisplayState.publishInitial`, `append`, and `prepend` methods.
The full-range reference is regenerated dynamically under the identical
layout declaration for every comparison; no nine-card signature list is used
as a canonical oracle. The target matrix covers fifteen authored source
anchors, five range partitions cover forward/prepend seams, and five singleton
anchors cover both expansion orders. Complete source/display/logical ranges,
structural ownership, `ReaderCardIdentity`, visible text, gaps, overlaps,
duplicates, and out-of-range membership are compared.

The standard Lexend declaration remains unchanged. A P03-only split-stress
variant changes only logical-surface height `844→300`, viewport height
`844→300`, and recorded card-body height `680→58`; widths, safe area, text
scale, locale/direction, all Lexend assets/weights/checksums, reading settings,
and every other declared input remain identical. Source 7 is genuinely split
by the real kernel into `[0,58)`, `[58,125)`, `[125,191)`, and `[191,198)`.
This is not the final P05 layout contract.

The equality files intentionally remain red: target-first is 3 pass / 12 fail,
the forward/backward file is 8 pass / 2 fail, and singleton expansion is 6
pass / 4 fail. The structural file is independently green at 6/6. All red
cases retain complete source coverage with no gaps, overlaps, duplicate exact
ranges, or out-of-range membership; the defects are separately flushed
physical boundaries, changed visible-card grouping, and consequent identity
changes. See the append-only ledger for every scenario, request sequence,
repeatability result, and remaining boundary limitations.

### P03 cache-order and formal-ledger evidence — CHANGE-20260831-010

`TASK-P03-005` exercises the real bounded `DisplaySectionMemoryCache` and
real `SegmentedDisplayCacheService` beneath a unique `ReaderContractSandbox`
root for every case. It uses the same production display-key/signature/key
models as ReaderScreen, persists real `DisplayRangeResult` segments, proves
memory hits/misses and policy eviction through public behavior, reloads
persisted bytes through fresh disk-service instances, and publishes every
retrieved result through `ProgressiveDisplayState`. The production disk
service has no close method; awaited writes followed by fresh instances over
the same sandbox-owned root are the available close/reopen boundary.

Two reviewed standard-Lexend plans run six cache states each. Both cold
full-range controls and all five segmented/replay states for the inline/
section-seam plan pass. For the merge/long/repeat plan, cold full range passes
while cold segmented, warm memory, warm disk, memory-eviction fallback, and
fresh-service reload fail the same complete ordered equality contract. Each
red replay preserves complete, ordered coverage but retains the independently
flushed source-4 island rather than full-range membership `4,5,6,7`; cache I/O
introduces no additional loss, duplication, overlap, reordering, or text
change.

`p03_failure_ledger.dart` records 23 permanent red scenarios: twelve target,
two forward/prepend, four singleton-expansion, and five cache replay. Passing
construction/cache/structural evidence is kept in a separate summary. The
ledger-integrity test validates row counts, scenario IDs, required fields,
approved requirement mappings, coverage statements, and P04/P06 ownership.
The four behavioral files remain intentionally red at their ordinary equality
assertions; P04/P06 must make them green without changing the approved
relational oracle.

### P04 — Canonical pagination and continuation/seam state

**Objective.** Replace request-local packing with one deterministic, bounded canonical pagination state machine whose cards and continuation checkpoints are independent of lazy request boundaries and construction order.

**Why at this point.** P03 provides the failing oracle. Layout fingerprints and caches cannot be made trustworthy while card membership itself changes with range construction.

**Entry criteria.** P03 red tests deterministically demonstrate each required mismatch under the controlled explicit layout environment; source-range expectations are manually validated. `DEC-REQ-001` concerns later P08 exact-miss failure handling and does not block P04.

**Exact scope.** Evolve the P02-extracted, characterized production paginator into a canonical deterministic API; define canonical forward packing state and restart checkpoints; finalize card boundaries with deterministic context; preserve published identities; support bounded target-first/forward/backward generation; make generated structures deterministic. P04 proves construction-order/seam determinism under one controlled explicit layout environment and receives immutable layout inputs rather than arbitrary widget state.

**Explicit non-scope.** Repeating P02's mechanical extraction; ReaderScreen restore/commit policy; final measurement/rendering layout contract; cache format/version compatibility or migration; UI redesign; whole-book pagination; unlimited continuation retention; legacy-test reconciliation; or automatic signature expectation updates. P04 may use the then-current verified measurement behaviour during initial canonicalization but does not freeze it as final authority.

**Verified files/symbols likely affected.** The single P02-extracted production paginator component and its `ReaderScreen` integration (`_rebuildDisplayChunks` and existing generator assignment); `lib/services/progressive_display_state.dart`; `lib/models/book_chunk.dart`; `lib/models/reader_checkpoint.dart`; `lib/utils/final_layout_paragraphs.dart`; `lib/utils/reader_list_layout.dart`. P04 must modify that one implementation rather than retaining/recreating a second paginator.

**Discovery questions that must be answered first.** Resolved by `TASK-P04-001` and `docs/development/nalori-canonical-pagination-design.md`: the unpublished frontier contains a deferred predecessor plus pending tail; restart authority is publication/section start or a validated chained continuation; immediate atomic lookahead plus the bounded tiny-tail frontier resolves merge/rebalance/finalization; checkpoints occur at the first of 48 consumed source chunks or eight finalized cards; generated structures use stable source/generated-owner evidence; and backward preparation regenerates forward from an earlier checkpoint and verifies the committed card.

**Target design.** The implementation-ready contract is `docs/development/nalori-canonical-pagination-design.md`. Pagination runs forward from publication/section start or a validated continuation, retains at most a two-card unpublished frontier, and finalizes only after adjacent merge, rebalance, backward tiny-tail attachment and logical-end evidence are exhausted. A request boundary never flushes provisional state. Checkpoints occur at the first of 48 consumed source chunks or eight finalized cards; the controlled standard-layout two-card frontier cap is 61 coalesced structural entries, normal target/backward work is bounded to 110 source/fragment entries, and one-checkpoint recovery is capped at 158. Continuations contain stable source slices, structure, compatibility and chain evidence, never display/window/controller indexes or rendered-card arrays. Append/prepend are transactional seam validations and cannot repack published cards.

**Task checklist.**

- [x] TASK-P04-001 — Specify the canonical pagination state machine, finalization rule, safe restart boundaries, continuation payload, bounded checkpoint spacing, and generated-structure ownership. Depends on P03 diagnostics. Completed by `CHANGE-20260831-011`; that entry is design evidence only, with implementation tracked by the later P04 tasks.
- [x] TASK-P04-002 — Evolve the P02-extracted, characterized production paginator into the canonical deterministic API: accept explicit immutable pagination/layout inputs and valid predecessor continuation/restart state; emit ordered cards and successor continuation evidence; preserve bounded operation; reject mutable window-local index authority; and change behaviour only against approved failing P03 contracts. Depends on TASK-P04-001 and deterministic P03 failures. Completed by `CHANGE-20260902-012`: one shared kernel now exposes the revision-pinned immutable request/result/frontier model and bounded forward state machine; a temporary legacy request-end adapter preserves P02/ReaderScreen behavior and is assigned to `TASK-P04-004`.
- [x] TASK-P04-003 — Implement serializable/in-memory canonical continuation checkpoints keyed only by stable source/layout/pagination inputs, with validation that rejects window-index evidence. Depends on TASK-P04-001 and TASK-P04-002. Completed by `CHANGE-20260905-013`: deterministic canonical encoding/integrity/linear-chain validation, exact pinned-snapshot frontier reconstruction, 48-source/eight-card plus section/terminal cadence, and transactional 25-record in-memory retention are independently green without ReaderScreen integration.
- [x] TASK-P04-004 — Implement bounded initial/target/forward generation from the nearest valid predecessor checkpoint and prevent request-tail flush from becoming a canonical seam. Depends on TASK-P04-003. Completed by `CHANGE-20260906-014`: ReaderScreen pins one immutable source/layout generation, selects only publication/trusted-section/validated-continuation restarts, resolves targets by stable owner and offset, performs one bounded earlier-checkpoint recovery, verifies the exact accepted forward suffix, publishes finalized cards only, and keeps legacy request-end treatment behind the backward-only P04-005 bridge.
- [x] TASK-P04-005 — Implement backward preparation by forward regeneration from a bounded earlier canonical checkpoint, preserving exact predecessor order and the committed card. Depends on TASK-P04-003 and TASK-P04-004. Completed by `CHANGE-20260906-015`: the canonical session selects a strict earlier validated checkpoint or bounded trusted root, permits one earlier restart fallback, regenerates only forward through the committed boundary and successor evidence, returns only finalized predecessors after exact identity/source/structure/cursor validation, and leaves rejected/pending work unpublished.
- [x] TASK-P04-006 — Define deterministic identities/ownership for split and continued paragraphs, headings, generated fragments, repeated text, images, lists, tables, and section seams. Depends on TASK-P04-002. Completed by `CHANGE-20260907-016`: the sole canonical finalization builder signs ordered stable source/section/spine/logical owners, exact UTF-16 or table-row intervals, fragment/structure/layout/rich/list evidence and explicit split provenance; ordinal hints are excluded, malformed evidence and seam crossing reject, and source membership/layout remain unchanged.
- [x] TASK-P04-007 — Integrate canonical results into `ProgressiveDisplayState` so append/prepend validate seam boundary evidence, complete coverage, and immutable published signatures before mutation. Depends on TASK-P04-004 through TASK-P04-006. Completed by `CHANGE-20260907-017`: one typed initial/append/prepend/replacement transaction validates generation/session/source/layout/pagination, continuation and physical seams, builds all lists/maps/ranges/indexes privately, preserves committed cards, and swaps the accepted snapshot once; legacy whole/segmented/memory/disk islands fail closed and regenerate canonically.
- [x] TASK-P04-008 — Make all P03 construction-order/coverage tests pass without changing their approved oracle; add bounded-work and retained-state assertions. Depends on TASK-P04-007. Completed by `CHANGE-20260908-021`: three independent unchanged final-gate executions passed 3/3 with identical plan, canonical card/text/ownership/identity, continuation, containment, work and retention evidence; complete P04 passed 69/69, unchanged P03 57/57, frozen P02 controls 9/9, scoped analysis reported no issues, and frozen hashes remained unchanged.

**Tests to add before or alongside implementation.** P03 tests remain the primary red/green gate. Add unit contracts for immutable paginator inputs, continuation serialization/validation, restart-point selection, tail finalization, seam rejection, published-card immutability, and bounded checkpoint/card retention. The P02 parity tests remain unchanged as evidence that P04, rather than extraction, is the first behaviour-changing phase.

**Expected failing behaviour before repair.** Ordered identities and seam coverage differ by construction order, and request-local tails are treated as final cards.

**Acceptance criteria.** Under the controlled explicit layout environment, all named construction orders yield identical complete ordered source ranges, card identities, and visible text; append/prepend add canonical cards without altering accepted/published signatures; source ranges form a gap-free, nonoverlapping ordered coverage; work and retained state remain bounded. Current full-section output is not accepted as correct without manual source-range review. P04 does not finalize persistent display-cache compatibility, migration, or version values.

**Required automated evidence.** Focused paginator matrix with exact counts and exit status; repeated construction-order randomization using a fixed recorded seed; instrumentation/assertions for maximum predecessor work, continuation records, and resident display cards; no whole-book work on a distant target fixture.

**Required manual evidence.** Review of source-range ownership at split paragraphs, headings, generated fragments, and section seams. No device test yet.

**Rollback/migration considerations.** Keep current cache formats isolated; do not bump, finalize, or consume new persisted cache compatibility/migration versions in this phase. P02 extraction remains separately revertible; P04 changes only the single extracted implementation. Any signature change must be explained at source-range and controlled-layout-input level in the ledger.

**Risks.** Continuation payload accidentally embeds mutable indexes; an uncontrolled widget/layout input leaks into P04; lookbehind becomes unbounded; generated headings duplicate at seams; rebalancing requires more future content than assumed; current full-section output is treated as authority; existing accepted-card guard masks canonical mismatch instead of fixing it.

**Invariants.** REQ-007 through REQ-013, REQ-027–REQ-028, REQ-040, REQ-044–REQ-045, REQ-048, and REQ-051.

**Exit criteria.** Canonical paginator tests are green across all orders under the controlled layout environment, boundedness is measured, P03 evidence remains the behavioural oracle, and no final layout/cache/restore policy or persistent version has been prematurely changed.

CHANGE-040 reopens the relevant exit gate: loaded-input exhaustion must not
claim book end; authenticated successor sessions must preserve accepted cards
across expansion, bounded retention and backward regeneration. The selected
contract is `nalori-lazy-snapshot-handoff-design.md`. All eight historical
checkboxes above remain completed; their fixed-snapshot proof is not withdrawn.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| ARCHITECTURAL_CORRECTION_REQUIRED | Historical fixed-snapshot/structural evidence retained; lazy input, handoff, coverage, retention and backward exit proofs reopened | P03 | 8 / 8 | Historical CHANGE-011 through CHANGE-021 preserved; `CHANGE-20260919-040` design and red characterization supersede lazy exit claims | Implement/prove immutable snapshot handoff, packing identity, exact restoration compatibility and bounded retention |

### P05 — Measurement/rendering layout contract and fingerprint

**Objective.** Make pagination measurement and card rendering consume one explicit, versioned layout contract and classify every metrics change correctly.

**Why at this point.** P04 stabilizes construction semantics under one controlled layout environment. Before caches and restoration rely on identities, P05 must establish the final shared layout authority and rerun the complete P03 equivalence matrix so a real measure/render correction cannot be mistaken for construction-order success.

**Entry criteria.** P04 canonical paginator API exists; P02 deterministic host fonts/viewport are available; current measurement and rendering paths have been inventoried.

**Exact scope.** One immutable final layout-input model; shared card-body constraints and typography/structure resolution; deterministic font readiness/metric identity; complete layout fingerprint; controls/safe-area invariance; genuine-change classification; source-range/layout-input explanation for every legitimate boundary/signature change; and rerunning the complete P03 matrix after each layout correction.

**Explicit non-scope.** New reader themes, density values, heading visual redesign, device-specific tuning, golden snapshots as the identity oracle, cache migration, or restoration logic.

**Verified files/symbols likely affected.** `lib/screens/reader_screen.dart` (`resolveReaderLayoutMetrics`, `_canonicalDisplaySafeArea`, signature builders, measurement helpers); `lib/models/reading_settings.dart`; `lib/services/book_cache_service.dart` (`displayChunkKey`); `lib/widgets/reading_card.dart`; `lib/widgets/reading_card_deck.dart`; `lib/utils/final_layout_paragraphs.dart`; `lib/utils/reader_list_layout.dart`. A proposed shared model such as `lib/models/reader_layout_contract.dart` may be introduced only after TASK-P05-001; it does not currently exist.

**Discovery questions that must be answered first.** What exact box does `ReadingCard` paint text into? Are safe-area bottom and controls overlays excluded consistently? How are Google/bundled/fallback fonts resolved and identified? Which inline widgets, spans, heading decorations, list markers, tables, locale/direction, and publisher attributes affect height? Which parser/source versions can alter rendered structure without a settings change?

**Task checklist.**

- [x] TASK-P05-001 — Produce a field-by-field measurement/render/fingerprint inventory and identify every mismatch or unresolved input. Depends on P02 and P04. Completed by `CHANGE-20260908-022`; discovery only, with no implementation or oracle change.
- [x] TASK-P05-002 — Define an immutable versioned layout contract containing card-body width/height, safe-area policy, text scaling, locale/direction, resolved font metrics, typography/strut, spacing/density, structural styling, parser/source, renderer, and pagination identities. Depends on TASK-P05-001. Completed by `CHANGE-20260909-023` as documentation-only architecture; no production or persistent version changed.
- [x] TASK-P05-003 — Refactor paginator measurement and `ReadingCard` construction to derive constraints/styles/spans from the same contract or shared pure resolvers. Depends on TASK-P05-002. Completed by `CHANGE-20260909-026`; final exhaustive controls/classification/oracle-transition evidence remains with P05-005 through P05-007.
- [x] TASK-P05-004 — Gate pagination on deterministic font readiness and represent fallback/resolved metric changes as explicit new layout identities. Depends on TASK-P05-002. Completed by `CHANGE-20260909-025`: bundled catalog/gate is production-ready and intentionally precedes P05-003, which must consume it before shared layout authority.
- [x] TASK-P05-005 — Make transient controls visibility invariant by fixing card-body constraints independently of overlay state and asserting safe-area treatment. Depends on TASK-P05-002 and TASK-P05-003. Completed by `CHANGE-20260909-027`; complete U-01/U-02/U-10 and one-field/oracle-transition obligations remain with TASK-P05-007.
- [x] TASK-P05-006 — Implement one compatibility classifier that distinguishes identical layout from genuine parser/source/layout/pagination change and produces a migration reason. Depends on TASK-P05-002 through TASK-P05-005. Completed by `CHANGE-20260910-028`: validated canonical F195–F208 evidence now yields typed exact, genuine-change, invalid-evidence and unsupported-revision outcomes without being wired into cache, checkpoint, restore, settlement or publication decisions.
- [x] TASK-P05-007 — Add parity/fingerprint tests covering one-field changes, inline spans, headings, lists/tables, locale/direction, safe area, controls, and fallback-font transition; rerun the complete P03 construction-order equivalence matrix after each legitimate layout correction, recording source-range/layout-input rationale for every changed identity. Depends on TASK-P05-003 through TASK-P05-006. Completed by `CHANGE-20260910-029` with 211/211 field mutations, U-01–U-10 runtime evidence, two P05-owned conformance corrections and two identical 57/57 final P03 runs.

**Tests to add before or alongside implementation.** Shared-contract unit tests, production paginator/`ReadingCard` parity widgets, complete fingerprint field mutation tests, controls-visible equivalence, and deterministic fallback-to-resolved-font reflow.

**Expected failing behaviour before repair.** Some layout-affecting changes may retain an apparent key, while some measured/rendered structures may disagree; font readiness can change metrics without a controlled migration. A real layout correction may legitimately change boundaries/signatures, but it must not hide a remaining construction-order mismatch.

**Acceptance criteria.** One contract produces both measured and rendered inputs; every pagination-affecting field is fingerprinted; irrelevant overlay visibility does not change identities; font metric changes do; no broad tolerance hides line/card differences; and the complete P03 equivalence matrix passes after any approved layout correction. Every changed identity is recorded with its source-range and layout-input cause.

**Required automated evidence.** Focused layout tests with exact card identities/source ranges and renderer overflow/line-bound assertions; repeat runs under the same host configuration; captured font identities.

**Required manual evidence.** Owner review only if an existing visual product choice must change. Device visual validation is deferred to P11.

**Rollback/migration considerations.** Do not bump or finalize persisted versions until P06. During development, old cache reads must remain isolated from new contract identities. Record every removed/added fingerprint field and every changed range/signature; do not relabel a construction-order mismatch as a layout migration.

**Risks.** Font availability differs between CI and devices; shared helpers still omit inline widget height; over-specific metrics make harmless platform differences invalidate layouts; under-specific identity silently reuses incompatible cards; a layout correction masks an unresolved P03 seam/order failure.

**Invariants.** REQ-014 through REQ-017, REQ-035, REQ-042, and REQ-051.

**Exit criteria.** Layout identity is complete and tested, production measurement/rendering use the same contract, and genuine-change classification is available to cache and restore phases.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| COMPLETED | REQ-002, REQ-014–REQ-017, REQ-035, REQ-042, REQ-051 | P02, P04 | 7 / 7 | `CHANGE-20260908-022` through `CHANGE-20260910-029`; final exhaustive field/runtime parity and repeated P03 evidence are recorded by CHANGE-029 | None for P05; REQ-002 remains for P07/P08, REQ-035/042 for P07/P09 and REQ-051 for P06/P10 |

### P06 — Canonical display-cache segments, invalidation, and migration

**Objective.** Make memory/disk display caches preserve canonical continuation and card identities, reject incompatible islands, migrate safely where possible, and remain bounded.

**Why at this point.** Cache records can be trusted only after pagination and layout identity are deterministic.

**Entry criteria.** P04 canonical continuation/state exists and P05 has established the final measurement/rendering layout contract and rerun the complete P03 matrix; P03 cold/warm tests are red or ready to exercise new formats. These criteria were met and reconfirmed by `CHANGE-20260910-029`.

**Exact scope.** Canonical segment record semantics, continuation/boundary evidence, final P04/P05 layout/pagination compatibility, validity checks, atomic invalidation/migration, corruption handling, retention budgets, and cold/warm/eviction equality. P06 is the first phase allowed to finalize persistent display-cache compatibility, invalidation, migration, and version changes.

**Explicit non-scope.** Checkpoint lifecycle policy, reader navigation, permanent cache clearing, parsed-source cache redesign, whole-book display caching, or version changes before migration analysis.

**Verified files/symbols likely affected.** `lib/services/segmented_display_cache_service.dart`; `lib/services/display_section_memory_cache.dart`; `lib/services/book_cache_service.dart`; `lib/services/progressive_display_state.dart`; canonical paginator module from P04; related focused tests.

**Discovery questions that must be answered first.** Can any current segment prove a canonical predecessor continuation? Are complete-section records safe while partial records are not? Which current manifests distinguish algorithm/layout/source versions? What data can be migrated semantically, and what must become a safe miss? What are measured resident/disk budgets under long traversal?

**Task checklist.**

- [x] TASK-P06-001 — Specify canonical segment keys and records, including source interval, ordered cards, predecessor/successor boundary evidence, continuation identity, layout/pagination/source versions, and checksum. Completed by `CHANGE-20260911-030`; see `docs/development/nalori-reader-canonical-display-cache-contract.md`. Depends on P04/P05.
- [x] TASK-P06-002 — Reject memory/disk records that cannot prove canonical membership or seam compatibility; never merge merely adjacent cache islands. Completed by `CHANGE-20260912-032`: the shared logical codec/admission boundary now verifies the 13-component key, 32-field record, 11-field cards, compatibility, source/card/seam/continuation evidence and all 16 fail-closed outcomes identically for memory and disk candidates. It activates no persistent format, write or reuse. Depends on TASK-P06-001.
- [x] TASK-P06-003 — Make cold generation, warm memory/disk reuse, eviction, and regeneration pass the P03 ordered-identity matrix. Completed by `CHANGE-20260912-033`: pure records built from accepted P04/P05 constituents pass one strict admission/P04 publication path across controlled memory/disk reuse, eviction, regeneration, mixed coverage and construction orders. No live production writer or persistent format was activated. Depends on TASK-P06-002.
- [x] TASK-P06-004 — Define and implement controlled invalidation for old/noncanonical layout and pagination records without clearing unrelated parsed source or user data. Completed by `CHANGE-20260912-034`: shared typed policy/executor performs only exact display-memory eviction, exact derivative/reference removal, or same-scope quarantine beneath an explicit caller-owned root; migration candidates and unsupported future records are retained. Depends on TASK-P06-001.
- [x] TASK-P06-005 — Implement migration only for records with sufficient canonical evidence; otherwise record a typed safe miss and regenerate from source. Completed by `CHANGE-20260913-035`: strict canonical records with unchanged source snapshots and changed layout/renderer/pagination components regenerate through current P04 publication and P06 admission only under controlled transports; all legacy/source-change/future/incomplete/corrupt paths remain typed safe misses. Depends on TASK-P06-004.
- [x] TASK-P06-006 — Preserve/enforce bounded memory and disk budgets, pinned current/adjacent cards, atomic writes, and safe eviction without losing checkpoint source authority. Completed by `CHANGE-20260913-037`: finite pre-allocation record/aggregate/work/temporary limits, stable current-plus-seam-adjacent pin authorization, deterministic unpinned eviction, typed pinned pressure, and previous-record-preserving controlled writes pass the focused and prior P06 gates. Physical production reuse remained gated until TASK-P06-007 completed. Depends on TASK-P06-002.
- [x] TASK-P06-007 — Add corrupt/partial/write-race/rollback tests and record actual format/version changes and migration outcomes in the ledger. Completed by `CHANGE-20260913-038`: the isolated v4 physical format is live behind publication-minted authorization, shared strict admission, contextual anchoring and `publishCanonical`; crash, corruption, concurrency, rollback, reopening and regeneration paths pass the combined control gate. Depends on TASK-P06-003 through TASK-P06-006.

**Tests to add before or alongside implementation.** P03 cache matrix; segment boundary/continuation round trips; incompatible-version misses; corrupt partial files; eviction/reload identity; rollback opening older data; byte/card budget assertions.

**Expected failing behaviour before repair.** P04 now prevents a warm cached island from publishing and regenerates canonically, but no current record can be reused directly because it lacks canonical continuation/seam evidence. P06 must define that evidence, compatibility, migration/invalidation and bounded reuse rather than weakening the fail-closed boundary.

**Acceptance criteria.** Warm/cold/evicted ordered identities and visible text match; incompatible cards are never published; invalidation is typed and scoped; storage remains bounded; cache deletion is not required for steady correctness.

**Required automated evidence.** Exact cache-equivalence commands and counts; temp-root inspection; corruption/migration results; resident/disk byte measurements; captured exit status.

**Required manual evidence.** Review migration policy and rollback implications before releasing a version bump.

**Rollback/migration considerations.** Follow section 10. Do not choose a new numeric/string version until TASK-P01-004 proves the next values. Prefer safe miss over speculative conversion. Preserve checkpoints and source caches when display caches invalidate.

**Risks.** Reusing a syntactically valid but noncanonical record; deleting user/source data; migration doubles storage; over-pinning violates bounds; rollback reads a new format incorrectly.

**Invariants.** REQ-009–REQ-010, REQ-013, REQ-044–REQ-046, REQ-048, and REQ-051.

**Exit criteria.** All cache states produce the canonical identity sequence, migration is documented/tested, and memory/disk bounds are measured.

CHANGE-040 additionally requires rejection of partial-window terminal records,
independent final-spine proof, handoff cache compatibility evidence and the
owner ordinary A059 chapter-crossing/book-switch gate. A host-only pass cannot
close P06 after the latest device regression.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| REGRESSED_ON_DEVICE | Historical P06 host and schema-isolation evidence preserved; partial-window terminal admission, lifecycle and device acceptance unproved | P04, P05 | 7 / 7 | CHANGE-030 through CHANGE-039 historical evidence; `CHANGE-20260919-040` design/red characterization and owner device failure | P04 handoff correction, contextual cache end proof and ordinary A059 acceptance; P07 remains blocked |

### P07 — Production-path restore/checkpoint lifecycle tests

**Objective.** Create failing, deterministic ReaderScreen lifecycle regressions that prove exact/semantic restoration, settlement authority, durable flushing, stale-callback protection, and two-book isolation through production services.

**Why at this point.** P08 must be driven by screen/store failures, not coordinator helpers. P05/P06 provide stable physical identities under deterministic layout/cache conditions.

**Entry criteria.** P02 harness and isolation ready; P05 layout classifier ready; P06 cache states controllable; P01 lifecycle trace complete.

**Exact scope.** Host widget/lifecycle tests using real EPUB parsing, canonical paginator, card signatures, SQLite checkpoint store, ReaderScreen, and explicit event controls. Narrow injection is allowed only at platform/lifecycle/time boundaries.

**Explicit non-scope.** Production lifecycle fixes, legacy-test rewrites, device/emulator tests, arbitrary delays, uncontrolled `pumpAndSettle`, mocked card identity, or helper-only claims.

**Verified files/symbols likely affected.** Proposed new lifecycle files under `test/reader_contract/`; P02 support/fixtures; current `ReaderScreen`, `ReaderCheckpointStore`, `ReaderCheckpointCoordinator`, `ReaderOpenService`, `LazyBookSession`, `ReadingCard`/deck, and real persistence adapters. Existing `reader_navigation_settlement_test.dart` is evidence only and remains unchanged.

**Discovery questions that must be answered first.** How can route pop/background/close be driven and observed without device APIs? What explicit signal means the controller is attached and settled? Which services need dependency injection to use real temp stores without replacing their behaviour? How can a delayed stale callback be held and released deterministically?

**Task checklist.**

- [ ] TASK-P07-001 — Build a real ReaderScreen harness with controlled route lifecycle, production parser/paginator/card renderer, real temp checkpoint DB/cache, and inspectable visible card identity/text. Depends on P02/P05/P06.
- [ ] TASK-P07-002 — Prove the checkpoint DB/serialization used by the harness is the production `ReaderCheckpointStore`, isolated per test and reopened from disk. Depends on TASK-P07-001.
- [ ] TASK-P07-003 — Add the blocker lifecycle: open A→settle exact card→persist→close A→open/close B→reopen A→assert exact signature and visible source text. Depends on TASK-P07-002.
- [ ] TASK-P07-004 — Add a genuine layout/font-metric change lifecycle asserting semantic source-anchor containment, controlled migration reason, and new exact signature only after verification. Depends on TASK-P07-003 and P05.
- [ ] TASK-P07-005 — Add same-layout missing-signature, default/body fallback, partial cache, preview/cancel, stale publication, controller reattachment, and delayed callback races. Depends on TASK-P07-003.
- [ ] TASK-P07-006 — Add settled-swipe→immediate route pop, background, dispose fallback, and book-switch flush-order scenarios; assert journal contents after reopening. Depends on TASK-P07-002.
- [ ] TASK-P07-007 — Add failed/cancelled lazy open and cross-session delayed-write cases proving no unopened-session persistence and no A/B contamination. Depends on TASK-P07-002.
- [ ] TASK-P07-008 — Replace all timing waits in this harness with explicit completers, frame/event probes, or fake clocks; record expected failures by requirement before P08. Depends on TASK-P07-003 through TASK-P07-007.

**Tests to add before or alongside implementation.** All listed lifecycle tests. Each assertion must include stable location, exact card signature where layout is identical, and visible source text; journal rows/revisions are supporting evidence, not substitutes.

**Expected failing behaviour before repair.** Same-layout exact miss may restore another source-containing card; default/late publications may interfere; immediate lifecycle flushing and cross-book isolation may be indeterminate; delayed callbacks may challenge the committed anchor.

**Acceptance criteria.** Tests fail deterministically for the intended production-path reason and can distinguish exact identity, semantic migration, preview, settlement, stale work, and durable flush completion.

**Required automated evidence.** Exact focused commands, counts, exit codes, failure messages, and targeted reruns up to three times for suspicious files. A helper-only pass cannot close any requirement.

**Required manual evidence.** None for phase exit beyond source-offset/signature review. Device verification remains P11 and owner-only.

**Rollback/migration considerations.** Test harness additions have no production-data effect. Tests for older checkpoint/cache formats must use copies in temp roots, never mutate repository fixtures.

**Risks.** A test-only ReaderScreen mode bypasses production entry paths; hidden arbitrary pumps; mock repository makes failures impossible; route disposal cannot be awaited in the same way as product navigation.

**Invariants.** REQ-001 through REQ-006, REQ-018 through REQ-024, REQ-029, REQ-031, REQ-033 through REQ-035, REQ-042–REQ-043, and REQ-047.

**Exit criteria.** Every lifecycle defect/requirement has a real screen/store red test with deterministic event control and no index-only oracle.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| NOT_STARTED | REQ-001–REQ-006, REQ-018–REQ-024, REQ-029, REQ-031, REQ-033–REQ-035, REQ-042–REQ-043, REQ-047 | P02, P05, P06 | 0 / 8 | — | Production-path injection/settlement boundary discovery |

### P08 — Gated restoration, committed-card authority, and durable flushing

**Objective.** Make one coordinator-owned accepted physical card the sole restore/commit authority, eliminate same-layout downgrade/default publication, and guarantee ordered durable flushing across lifecycle and book switches.

**Why at this point.** P07 supplies real red lifecycle tests; P04–P06 make exact signatures and compatibility classifications meaningful.

**Entry criteria.** P07 red tests cover every listed race; P05 genuine-change classifier and P06 canonical cache publication are available; checkpoint journal low-level tests are preserved.

**Exact scope.** Restore intent/barrier lifecycle; exact-versus-semantic branching; publication verification; screen state ownership; accepted settlement; stale/default suppression; per-book/session persistence; awaited flush/close ordering.

**Explicit non-scope.** Adjacent navigation mechanics beyond what restore needs, display-index authority, disabling correction, swallowing lifecycle errors, new delays, test expectation weakening, or checkpoint/cache version choice outside section 10.

**Verified files/symbols likely affected.** `lib/screens/reader_screen.dart` (`_initReadingPosition`, `_restorePosition`, `_jumpToDisplayIndex`, `_scheduleCheckpointPublicationVerification`, `_onPageChanged`, `_onPageSettled`, `_captureCommittedPosition`, `_persistCommittedPosition`, lifecycle/flush methods); `lib/services/display_generation_coordinator.dart`; `lib/services/reader_visible_correction_scheduler.dart`; `lib/services/reader_checkpoint_store.dart`; `lib/models/reader_checkpoint.dart`; `lib/services/reader_open_service.dart`; P07 tests.

**Discovery questions that must be answered first.** Should an exact miss trigger canonical regeneration automatically, block with retry, or show a recovery state? Which state object is removed/demoted so the coordinator is actually single-owner? How can app-background best-effort writes be ordered without pretending Flutter `dispose` is awaitable? Which lazy-session-open token must accompany persistence?

**Task checklist.**

- [ ] TASK-P08-001 — Define the sole authoritative committed-card state and explicitly demote `_currentPage`, `_activeDisplayIndex`, `ReaderPositionSession` indexes, pending targets, and compatibility metadata to derived/transient roles. Depends on P01/P07.
- [ ] TASK-P08-002 — Implement one restoration intent state machine: acquired→canonical window prepared→controller moved→settled→physical identity verified→consumed, with ordinary navigation/commit gated until completion. Depends on TASK-P08-001.
- [ ] TASK-P08-003 — On identical-layout exact-signature miss, prohibit stable-anchor fallback and checkpoint rewrite; execute only the approved canonical-regeneration/retry/failure path. Depends on TASK-P08-002 and DEC-REQ-001.
- [ ] TASK-P08-004 — Permit semantic restoration only from the P05 compatibility classifier's genuine-change result, then create a new exact checkpoint only after visible semantic containment is verified. Depends on TASK-P08-002 and P05.
- [ ] TASK-P08-005 — Prevent default, body fallback, temporary target, partial publication, and controller bootstrap pages from acquiring authority while restoration is pending. Depends on TASK-P08-002.
- [ ] TASK-P08-006 — Guard append/prepend/cache/chapter/controller/stale callbacks with reader session, intent, window, publication, layout, and expected card/source evidence; preserve coordinator correction. Depends on TASK-P08-002 and P06.
- [ ] TASK-P08-007 — Commit only an accepted settled immutable card and reject preview/cancelled/rejected/synthetic/mismatched events without changing the journal or committed anchor. Depends on TASK-P08-001 and TASK-P08-002.
- [ ] TASK-P08-008 — Make route pop, background, book switch, and close flush the staged authoritative checkpoint in a defined order; attach persistence to a successfully opened per-book session token and preserve journal epoch/revision semantics. Depends on TASK-P08-007.
- [ ] TASK-P08-009 — Make all P07 lifecycle/race tests pass, including delayed cross-book writes and exact A→B→A restoration, without adding waits or weakening identities. Depends on TASK-P08-003 through TASK-P08-008.

**Tests to add before or alongside implementation.** P07 tests remain mandatory. Add coordinator state-transition tests only where they clarify invalid transitions; they cannot replace screen lifecycle evidence. Preserve journal corrupt-newest, epoch/revision, and flush-order tests.

**Expected failing behaviour before repair.** Same-layout exact miss can source-restore; authority is projected through multiple fields; immediate exit/background/book switch lacks complete proof; default/late publications can race restoration.

**Acceptance criteria.** Exact A→B→A lifecycle passes; identical-layout miss cannot become approximate or rewrite the checkpoint; genuine changes migrate semantically once; every invalid settlement leaves durable state unchanged; flush completes or returns an explicit failure; sessions/books are isolated.

**Required automated evidence.** P07 lifecycle suite with exact counts/exit status; focused low-level checkpoint/coordinator tests; repeated race permutations controlled by completers; journal row/revision evidence; no hidden errors in Flutter error capture.

**Required manual evidence.** Review the same-layout exact-miss UX selected by DEC-REQ-001. Device lifecycle verification remains P11.

**Rollback/migration considerations.** Preserve old checkpoint journal until new exact checkpoints are verified. Do not overwrite an exact old record during failed migration. Any schema change follows section 10 with rollback tests.

**Risks.** Restore deadlock if controller settlement is unavailable; duplicate commit after intent consumption; background callback outlives session; route pop blocks indefinitely; compatibility mirror writes regress library progress.

**Invariants.** REQ-001 through REQ-006, REQ-018 through REQ-024, REQ-041, REQ-043, REQ-047, and REQ-049.

**Exit criteria.** P07 is green; one authority is documented in code/tests; no same-layout semantic downgrade or unawaited authoritative route-close write remains; migrations are controlled.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| NOT_STARTED | REQ-001–REQ-006, REQ-018–REQ-024, REQ-041, REQ-043, REQ-047, REQ-049 | P07 | 0 / 9 | — | Same-layout exact-miss UX and awaitable lifecycle boundary |

### P09 — Navigation, backward preparation, and retry

**Objective.** Route adjacent and explicit navigation through canonical stable card/source identity, preserve exact order across lazy boundaries, and replace time polling with explicit intent/publication/settlement events.

**Why at this point.** Navigation needs canonical cards/cache (P04/P06) and a stable committed-card owner (P08). Repairing it earlier would preserve mutable-window assumptions.

**Entry criteria.** P04 canonical adjacency data available; P06 segment seams trusted; P08 committed/restoration authority green; P07 harness can drive real screen navigation.

**Exact scope.** Canonical adjacent-card resolution; forward/backward boundary preparation; heading adjacency; preparation failure/cleanup; fresh retry intent; TOC/search/Memory/bookmark/highlight/note/internal-link/history jumps; removal of time-based navigation completion.

**Explicit non-scope.** Whole-book pagination, global exact display totals, non-reader search/Memory UX, coordinator-correction removal, index-based durable locations, or arbitrary retry delays.

**Verified files/symbols likely affected.** `lib/screens/reader_screen.dart` (`_nextReaderPage`, `_previousReaderPage`, `_completeAdjacentBoundaryNavigation`, `_ensureAdjacentSectionAvailable`, `_integrateLazyForwardSection`, `_integrateLazyBackwardSection`, `_navigateToStableLocation`, `_completeStableLocationNavigation`, chapter jump methods); `lib/services/lazy_book_session.dart`; `lib/services/chapter_navigation_service.dart`; `lib/services/derived_book_index_service.dart`; `lib/services/reader_open_service.dart`; `lib/services/display_generation_coordinator.dart`; source-projection and annotation services; P07/P09 contract tests.

**Discovery questions that must be answered first.** What canonical adjacency token survives window eviction? How is a preceding heading card owned and discovered? Which event replaces the current 50 ms poll? Which failure paths currently leave loading flags or controller intents active? Which explicit jump callers can be exercised through ReaderScreen without test-only alternate routes?

**Task checklist.**

- [ ] TASK-P09-001 — Define a canonical adjacency result containing current identity, adjacent identity/source boundary, required preparation, and generation/intent evidence; never persist a local index. Depends on P04/P08.
- [ ] TASK-P09-002 — Replace cross-publication/window `_currentPage ± 1` truth with lookup from the committed card and canonical sequence; local index may only address the already verified current publication. Depends on TASK-P09-001.
- [ ] TASK-P09-003 — Implement forward boundary preparation/publication/settlement from the committed card, rejecting stale or nonadjacent results. Depends on TASK-P09-001 and P06.
- [ ] TASK-P09-004 — Implement backward preparation through canonical predecessor regeneration/prepend, preserving the committed signature and exact previous/current/next order. Depends on TASK-P09-001 and P04.
- [ ] TASK-P09-005 — Integrate deterministic generated-heading ownership so previous/next and section seams never skip, duplicate, or reorder heading cards. Depends on TASK-P09-003 and TASK-P09-004.
- [ ] TASK-P09-006 — On preparation/navigation failure, cancel/consume the failed intent, clear all matching loading/failure ownership, keep the controller and committed signature stable, and expose only the approved retry state. Depends on TASK-P09-003 and TASK-P09-004.
- [ ] TASK-P09-007 — Make retry acquire a new intent/generation from the current committed card, never from failed target/index state. Depends on TASK-P09-006.
- [ ] TASK-P09-008 — Route TOC, search, Book Memory, bookmark, highlight, note, internal-link, and history jumps through stable source resolution and the same publication/settlement state machine. Depends on TASK-P09-001, TASK-P09-006, and P01 inventory.
- [ ] TASK-P09-009 — Replace the delayed polling loop with explicit window-published/controller-attached/settled completion and pass adjacent/explicit/race tests without sleeps. Depends on TASK-P09-003 through TASK-P09-008.

**Tests to add before or alongside implementation.** Real ReaderScreen forward/backward tests across section/cache/eviction boundaries; heading adjacency; failure then retry with fresh IDs; stale completion; each explicit jump source; exact visible text and card identity after settlement.

**Expected failing behaviour before repair.** Adjacent results rely on independently packed ranges and transient indexes; backward seams can disagree; retry freshness is not proved; stable navigation completion time-polls.

**Acceptance criteria.** Exact canonical adjacency holds through append/prepend/eviction; failure preserves current card and clears state; retry IDs are fresh and anchored; all explicit jumps settle the stable source target; no arbitrary time polling remains.

**Required automated evidence.** Focused navigation suite with exact commands/counts/exit status; controlled completion-order permutations; static search proving the removed correctness-critical delay and no new equivalent delay; bounded-work metrics at distant jumps.

**Required manual evidence.** Owner device verification of gesture/controller behaviour in P11, not in this phase.

**Rollback/migration considerations.** No durable index migration should be introduced. Preserve stable-location JSON compatibility and checkpoint journal. Roll back the phase independently if boundary navigation regresses while retaining P04–P08.

**Risks.** Deadlock waiting for an event; heading ownership ambiguity; a local index slips into durable state; retry uses an obsolete failure closure; explicit jump sources diverge into separate state machines.

**Invariants.** REQ-006, REQ-025 through REQ-031, REQ-035, REQ-040 through REQ-042, REQ-044, and REQ-049.

**Exit criteria.** All adjacent and explicit navigation tests are green, completion is event-driven, failures are stable/retryable, and boundedness is retained.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| NOT_STARTED | REQ-006, REQ-025–REQ-031, REQ-035, REQ-040–REQ-042, REQ-044, REQ-049 | P04, P06, P08 | 0 / 9 | — | Canonical adjacency and settlement event discovery |

### P10 — Legacy reader-test reconciliation

**Objective.** Reconcile reader-related legacy tests against approved requirements and stronger replacement coverage without allowing obsolete tests to shape production.

**Why at this point.** Only after the trusted pagination, lifecycle, and navigation suites are green can a legacy test be safely kept, rewritten, replaced, or removed.

**Entry criteria.** P03–P09 trusted replacements exist and pass; test audit classifications are refreshed against the then-current tree; owner has approved any remaining product decisions.

**Exact scope.** Reader-related tests and directly affected test support only; classification, replacement, strengthening, deduplication, removal, and ledger entries.

**Explicit non-scope.** Broad non-reader cleanup, changing production to satisfy an unmapped test, automatic expected-signature updates, coverage percentage targets, or deleting a test before replacement evidence exists.

**Verified files/symbols likely affected.** Reader files inventoried in `docs/development/nalori-test-suite-audit.md`, especially checkpoint/coordinator/progressive/cache/layout/navigation/rendering/source-projection tests and `test/TESTING_STRATEGY.md` only if directly in scope. Exact affected files must be selected per change entry; do not bulk-edit the suite.

**Discovery questions that must be answered first.** Has any test changed since the audit? Which tests assert approved behaviour at a lower layer and add real boundary value? Which apparent duplicates cover distinct failure states? Which UI/product assumptions still require owner approval?

**Task checklist.**

- [ ] TASK-P10-001 — Refresh the reader-test inventory and map every named test/group to `REQ-*`, production path, replacement evidence, and one approved classification. Depends on P03–P09.
- [ ] TASK-P10-002 — Preserve `KEEP` and `KEEP_WITH_MINOR_IMPROVEMENT` checks only within their defensible layer; strengthen weak identity/content assertions where replacement evidence supports it. Depends on TASK-P10-001.
- [ ] TASK-P10-003 — Replace false-confidence helper/widget claims with the trusted P03/P07/P09 production-path tests before altering or removing the originals. Depends on TASK-P10-001.
- [ ] TASK-P10-004 — Rewrite desired but implementation-coupled tests to assert approved outcomes without private fields, callback counts, arbitrary timings, mutable indexes, or duplicated production logic. Depends on TASK-P10-003.
- [ ] TASK-P10-005 — Delete duplicate/obsolete/false-confidence reader tests only after owner/requirement mapping and stronger green replacement; record every original and replacement in the ledger. Depends on TASK-P10-003 and TASK-P10-004.
- [ ] TASK-P10-006 — Leave `PRODUCT_DECISION_REQUIRED` and unrelated non-reader tests unchanged unless the owner explicitly decides them; record the deferral. Depends on TASK-P10-001.
- [ ] TASK-P10-007 — Run the reconciled focused reader suite and audit every changed expectation/signature with source-range rationale. Depends on TASK-P10-002 through TASK-P10-006.

**Tests to add before or alongside implementation.** No new behavioural scope should originate here. Only gap-closing replacements identified by the mapping are allowed; all must reference existing requirements.

**Expected failing behaviour before repair.** Legacy failures may contradict approved contracts, pass without product-path proof, or lock private/index/count/timing assumptions.

**Acceptance criteria.** Every changed legacy test has a ledger row and stronger replacement; no unmapped failure causes production edits; non-reader decisions remain deferred; signature changes are explained by canonical source/layout identity.

**Required automated evidence.** Exact focused commands and counts before/after each reconciliation batch; no skipped tests; diff review showing only selected reader tests/support; later full-suite evidence belongs to P11.

**Required manual evidence.** Owner approval for product-decision tests and any deletion whose authority is not settled by the supplied reader contract.

**Rollback/migration considerations.** Reconciliation is independently revertible. Preserve replacement tests even if an old test is temporarily retained during review.

**Risks.** Deleting unique boundary coverage; changing production to preserve obsolete output; silently updating signatures; expanding into the 45 non-reader decision-required files.

**Invariants.** REQ-032 through REQ-039, REQ-050, and REQ-051.

**Exit criteria.** Reader tests have explicit authority/classification, trusted replacements precede removals, and the focused reader gate is coherent and green.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| NOT_STARTED | REQ-032–REQ-039, REQ-050–REQ-051 | P03–P09 | 0 / 7 | — | Owner decisions for remaining product-policy tests |

### P11 — Release-gate verification and manual-device handoff

**Objective.** Produce a captured, repeatable non-device release gate, migration/performance evidence, and a precise owner-run device checklist without hiding any blocker or regression.

**Why at this point.** Integrated verification is meaningful only after canonical pagination, layout, caches, lifecycle, navigation, and legacy reconciliation are complete.

**Entry criteria.** P04–P10 exit criteria met; no known blocker requirement is merely helper-tested; environment can report tool versions or the limitation is explicitly recorded.

**Exact scope.** Focused trusted shards, determinism reruns, one complete non-device suite with exit status, static analysis/scoped diff checks, migration and bounded-memory evidence, requirement status updates, owner device handoff.

**Explicit non-scope.** Codex-run device/emulator tests, hiding failures, repeated full-suite runs, coverage percentage as quality target, unrelated cleanup, or declaring release-ready without owner device evidence.

**Verified files/symbols likely affected.** Trusted test files from P02–P10; CI/workflow documentation only if explicitly included in a future task; both tracking documents. Production/test changes should already be complete before this verification phase except narrowly diagnosed regressions.

**Discovery questions that must be answered first.** Can the Flutter SDK version be captured without mutating its read-only cache? Which exact non-device suite command is authoritative? What memory/card/byte bounds are supported on representative books? Which manual device scenarios/platforms are required for release?

**Task checklist.**

- [ ] TASK-P11-001 — Define and run focused trusted shards for parser/source, paginator/layout, cache, checkpoint/lifecycle, and navigation; capture commands, counts, duration, and exit status. Depends on P10.
- [ ] TASK-P11-002 — Repeat construction-order, cold/warm/eviction, and lifecycle race suites under controlled order/seed to prove deterministic outcomes. Depends on TASK-P11-001.
- [ ] TASK-P11-003 — Run the complete non-device Flutter suite exactly once for the gate, capturing Flutter/Dart versions, discovered/passed/failed/skipped/timed-out counts, duration, failing names, and final exit status; an incomplete command is indeterminate. Depends on TASK-P11-001.
- [ ] TASK-P11-004 — Run scoped static analysis and diff-integrity checks; inspect all warnings/errors rather than suppressing them. Depends on TASK-P11-001.
- [ ] TASK-P11-005 — Execute old-cache/checkpoint migration, corrupt/partial data, rollback, and clean-install matrices with documented outcomes and no silent incompatible reuse. Depends on P06/P08.
- [ ] TASK-P11-006 — Measure bounded source/display/cache work and retained memory/storage during long sequential and distant/backward navigation; record representative fixtures/environment. Depends on P04/P06/P09.
- [ ] TASK-P11-007 — Produce the owner-only manual device checklist for exact reopen, accepted/cancelled swipe exit, background/force-stop where appropriate, A/B switching, font/orientation reflow, forward/backward boundaries, retry, TOC/search/Memory jumps, and visual measurement parity. Depends on TASK-P11-001 through TASK-P11-006.
- [ ] TASK-P11-008 — Update every requirement status from evidence, keep incomplete code at `IMPLEMENTED_NOT_VERIFIED`, record regressions, and declare release-ready only after owner manual results and no blocker/high requirement remains unverified. Depends on TASK-P11-003 through TASK-P11-007.

**Tests to add before or alongside implementation.** Only a narrowly identified release-gate gap or regression may add tests here; it must map to an existing requirement and be logged. Do not invent new product contracts at verification time.

**Expected failing behaviour before repair.** The prior audit's full suite was indeterminate, and a passing helper-heavy suite would not prove reader reliability.

**Acceptance criteria.** Section 14 is fully satisfied; all commands have captured exits; deterministic matrices agree; migrations and bounds are documented; owner supplies manual device results; no blocker/high requirement remains unverified.

**Required automated evidence.** All TASK-P11 commands/results in the test evidence register, including failures/indeterminate results. No repeated full suite except a specifically approved follow-up after a diagnosed gate failure.

**Required manual evidence.** Product owner performs and records the device checklist. Codex must not run it without explicit authorization.

**Rollback/migration considerations.** A failed migration or performance gate blocks release and may require rollback to the last compatible version while preserving user checkpoints/source data. Never clear caches as proof of repair.

**Risks.** Environment prevents complete version/status capture; full suite contains unrelated decision-required failures; host pass masks device font/gesture/lifecycle differences; performance measurements omit worst-case structures.

**Invariants.** All requirements, especially REQ-038, REQ-044–REQ-046, and REQ-051.

**Exit criteria.** The release definition is met, owner device evidence is linked, statuses/evidence agree, and no regression is hidden behind completed tasks.

| Phase status | Requirements | Dependencies | Completed / total tasks | Evidence | Blocking issue |
| --- | --- | --- | ---: | --- | --- |
| NOT_STARTED | All `REQ-*` | P04–P10 | 0 / 9 | — | All repair phases plus owner manual-device evidence |

## 7A. Accepted handoff-entry amendments and deferred UX (2026-09-21)

CHANGE-20260921-041 records plan/proof work under
`IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001`, not a completed implementation task.
The [handoff design §§11–14](nalori-lazy-snapshot-handoff-design.md) now requires
separate adjacent receipt/handoff and direct stable-target preparation. A
chapter 1 → 6 target must parse zero intermediate chapters, retain the old
readable card until acceptance, join identical demand, give latest foreground
demand ownership, preempt speculation within one quantum and publish before
hydration/indexing/speculation/awaited physical cache writes.

Acceptance targets, not achievements: prepared navigation ≤100 ms; prefetched
boundary and cached/parsed chapter target ≤250 ms; uncached ordinary target
ideally ≤500 ms/hard ≤1 second; deterministic injected-clock UI slices ≤8 ms;
zero ANR/Stop-Wait, including no debug unbounded loop. Host evidence uses counters
and scheduling gates; final latency belongs to ordinary profile/release A059.
The stable address and exact reopen gate, full screen direct-target gate and
DEC-REQ-001/002 remain open; P07 remains unstarted.

Current evidence: combined address/direct/reopen tests **13 passed / 3 failed**
(D02, R02, L02); unchanged P05/backward/H characterization **101 passed / 4
failed** (H01–H04). Known-original-window legacy SQLite reopen is exact in L01;
bounded discovery of an arbitrary historical window and actual recovery UI are
unproved. Per new reconstruction session maxima: 2 cards, 1 guard, 18 sources,
4 generation entries/entered sources. These are not aggregate two-handoff or
oversized-section bounds. No stable persistent encoding is chosen. See the
entry report for exact commands, mutation-proof limits and required decisions.

### DEFERRED-UX-CHAPTER-CARD-SCRUBBER-001 — Replace whole-book scrubber with chapter-local card scrubber

Status: **UNSTARTED / DEFERRED**, plan only. Excluded from the existing 89-task
historical denominator; adds zero completed tasks. Start only after both the P06
device exit gate and stable-address/reopen gate are satisfied.

- Remove the draggable whole-book scrubber; show only current-chapter card
  navigation, such as Card X of Y.
- Drag/select may navigate only within the current chapter. It must never
  request, parse, hydrate or paginate another chapter.
- The chapter list remains the explicit cross-chapter mechanism and uses direct
  target preparation, never repeated adjacent handoffs.
- If the exact chapter card count is unavailable, do not invent an exact total
  or delay first-card publication to calculate it. Later design must select
  progressive, temporarily disabled or bounded current-chapter-only completion.
- Current-chapter background completion stays low priority and demand-preemptible.
- Font/layout changes invalidate only the chapter-local card count.
- No whole-book dense card number becomes stable or persisted identity.
- No scrubber implementation, reader widget change or UI-test change is part of
  this amendment.

## 8. Trusted test architecture

The trusted suite should be a small hierarchy under a proposed `test/reader_contract/` root. These paths are design targets, not files that exist today.

| Proposed layer | Responsibility | Real production path required | Allowed controls/fakes | What it can prove | What it cannot prove |
| --- | --- | --- | --- | --- | --- |
| `fixtures/` plus `fixture_manifest.yaml` or equivalent reviewed manifest | Store controlled EPUBs, source truth, provenance, checksums, approved anchors/ranges, and structure inventory | Real EPUB archive/index/parser | Deterministic fixture builder only for micro-EPUBs | Fixture bytes and manually reviewed source expectations are stable | Pagination, rendering, persistence, or lifecycle by itself |
| `support/` | Shared temp roots, deterministic layout host, event probes, identity dumps, route driver | Must call production stores/parser/paginator/screen; no duplicate packing | Explicit completers, fake clock at a clock boundary, platform adapter stubs | Isolation and causal control | Product behaviour unless used by a contract test |
| `parser_source/` | EPUB parse, section identity, stable locations, source ranges, structural blocks | `EpubParserService`, lazy index/repository/session, source projection | Temp filesystem; no fake chunks for integration claims | Authoritative source identity and exact offsets | Physical card membership or lifecycle |
| `pagination/` | Characterize current order/seam behaviour, then canonical full/order/continuation/seam contracts | The one production paginator extracted mechanically in P02 and evolved in P04; real `ReaderCardIdentity` | Controlled explicit layout inputs | Complete ordered cards, ranges, identities, bounded continuation | Flutter controller settlement or durable exit |
| `layout/` | Measurement/rendering parity and layout fingerprint | Production layout contract, paginator, `ReadingCard` | Fixed viewport/font/locale/direction; controlled font readiness | Same inputs yield same cards; genuine changes alter identity | Device-specific raster/gesture behaviour |
| `cache/` | Cold/warm/evict/regenerate equivalence and migration | Production memory/disk cache and paginator | Per-test temp cache root, storage-pressure injector | Cached results are canonically equivalent and bounded | Reader lifecycle unless mounted through lifecycle layer |
| `checkpoint/` | Journal integrity, revisions/epochs, exact/semantic migration | Production SQLite store/coordinator/serialization | Temp SQLite root, explicit delayed write gate | Durable ordering and restore decision semantics | Visible card/controller correctness by itself |
| `lifecycle/` | Real ReaderScreen open/settle/close/switch/reopen contract | Reader route, parser, paginator, renderer, store, controller/deck | Route/lifecycle driver, explicit completion probes, deterministic platform adapters | Exact reopen, semantic reflow, authority, durable flush, A/B isolation | Physical-device OS kill guarantees or vendor font rendering |
| `navigation/` | Adjacent boundary, retry, and explicit-jump state machine | Real ReaderScreen, lazy session, canonical paginator/cache, source callers | Injected failure/completer at real I/O/publication boundary | Stable target resolution, canonical adjacency, stale rejection, fresh retry | Non-reader search/Memory presentation policy |
| `real_books/` | Small realistic public-domain corpus regressions | Same production paths as relevant layer | Local vendored files only; no network | Publisher variation and realistic structures | Exhaustive format support or manually known every card boundary |

### Controlled fixture rules

1. Every fixture has provenance, license/public-domain basis, generator/source location, checksum, purpose, and structural inventory.
2. Micro-fixtures isolate one or a small combination of structures: mergeable paragraphs, long split paragraphs, continuation seams, repeated text, headings/generated fragments, images, inline styles/links/footnotes, lists, tables, section boundaries, RTL/CJK/emoji where supported.
3. Expected semantic anchors and UTF-16 half-open ranges are manually reviewed against source XHTML. Expected physical signatures are derived only after the canonical algorithm and layout inputs are approved; updates require a range-level rationale.
4. `test/fixtures/books/feature_rich_lazy_reader.epub` remains useful session evidence, but it needs its generator/provenance and exact source expectations linked into the manifest before trusted-contract use.
5. Realistic public-domain Gutendex EPUB editions are supplementary, network-independent regression coverage. They may be selected and added later, only after owner provenance/license/repository-size approval; their absence does not block controlled micro-fixtures, P02 exit, P03 characterization, or P04 repair.

### Async, storage, font, and viewport control

- Use explicit completers or state/event probes to hold parser, cache, publication, controller attachment, settlement, and write completion. A fake clock is allowed only where production depends on an injected clock; it cannot stand in for controller settlement.
- Do not use `Future.delayed`, arbitrary `pump`, repeated uncontrolled `pumpAndSettle`, or callback-count guesses as proof that a card settled or a write flushed.
- Give every test an isolated temp filesystem/cache root, SQLite database, preferences state, singleton reset, and book/session identity. Tests must pass in any order.
- Load or register the exact host fonts before pagination. Capture font family, resolved metric identity, text scaler, locale, direction, viewport, and safe-area inputs in failure output.
- No test may access network resources. Realistic fixtures are checked in only after provenance/size approval.

### Limits on mocks and handcrafted data

- Handcrafted `BookChunk`, `DisplayRangeResult`, `ReaderCardIdentity`, or stable locations are allowed for pure model validation, not for parser→paginator, cache-equivalence, navigation, or lifecycle claims.
- Fake repositories/sessions are allowed only to induce a precisely controlled failure or completion order after a separate real-service happy path exists. Their replaced behaviour and impossible-to-observe failures must be documented.
- Fake controllers cannot prove ReaderScreen settlement. At least the trusted lifecycle/navigation layer must use the actual widget/controller or card-deck callback path.
- An in-memory checkpoint abstraction cannot prove SQLite serialization, reopen, journal integrity, or durability. Use the real store with a temp database for those claims.
- No test helper may reproduce split/merge/card-signature or stable-location resolution algorithms as its expected-value generator.

## 9. Legacy-test reconciliation policy

Every current test remains evidence until mapped to an approved requirement and a defensible layer. The allowed classifications are:

| Classification | Meaning and required treatment |
| --- | --- |
| `KEEP` | Approved, deterministic, production-faithful within its stated layer, and strong enough to detect meaningful wrong outcomes. Preserve it. |
| `KEEP_WITH_MINOR_IMPROVEMENT` | Approved and useful, but needs a narrow assertion/setup/provenance improvement without changing abstraction. |
| `REWRITE` | The scenario is approved, but timing, private coupling, duplicated logic, or weak assertions make the current test unreliable. Rewrite after the approved oracle is established. |
| `REPLACE` | The requirement matters, but the test exercises the wrong abstraction or outcome. Add stronger replacement first. |
| `DELETE_DUPLICATE` | Another test covers the same requirement, state, boundary, and failure mode with equal or greater fidelity. Different wording/data alone is insufficient. |
| `DELETE_OBSOLETE` | The test encodes removed/unwanted architecture or behaviour and no approved requirement. Require owner/requirement evidence. |
| `DELETE_FALSE_CONFIDENCE` | The test can pass while its stated production claim is broken. Replacement evidence is mandatory before removal. |
| `PRODUCT_DECISION_REQUIRED` | The behaviour has not been approved. Do not change production or the test until the owner decides it. |
| `INVESTIGATE_FLAKINESS` | The scenario may be valid but outcomes depend on uncontrolled time/order/environment. Reproduce and control it before classifying further. |

Before changing or deleting any existing test, a future task must record:

1. the original named test/file and current assertion;
2. mapped `REQ-*` or explicit owner decision;
3. production path actually exercised and important bypasses/mocks;
4. stronger replacement test/evidence and its passing command;
5. why the old test is redundant, obsolete, misleading, or safely rewritten;
6. any changed expected signature with source-range/layout/version explanation;
7. a row in the change log's test-removal/replacement ledger.

A failing legacy test must first be mapped to a requirement. Production code must not change merely to make an unmapped or unapproved test pass. No deletion/substantial rewrite is permitted before stronger replacement coverage is green. Non-reader cleanup remains deferred unless a reader repair directly affects it.

## 10. Cache and checkpoint migration plan

Current-tree version evidence to reconfirm in P01 includes `readerPaginationAlgorithmVersion = 'nalori_cards_v16_lists'`, `BookCacheService.displayCacheFormatVersion = 3`, `BookCacheService.displayLayoutVersion = 'v14'`, `SegmentedDisplayCacheService.segmentedDisplayCacheFormatVersion = 3`, `ReaderCheckpointStore.schemaVersion = 1`, `ReaderCheckpoint.currentFormatVersion = 1`, and `StableBookLocation.currentVersion = 2`. This plan deliberately does not choose successors. P04 may establish canonical in-memory behaviour under its controlled layout environment and P05 may correct layout identity, but neither phase finalizes persistent display-cache compatibility, migration, or version changes; that is P06 work.

### Compatibility and invalidation flow

```text
load derivative/checkpoint
→ validate publication + source/parser identity
→ validate layout + renderer + pagination identity
→ validate checksum/format and canonical boundary evidence
→ exact compatible: reuse/restore exact
→ genuine compatible migration: resolve semantic source anchor, regenerate canonically,
  verify visible containment, then write a new exact record
→ insufficient/corrupt/incompatible evidence: typed safe miss or recovery state;
  never silently publish/rewrite an approximate same-layout result
```

### Display caches

- A pagination-algorithm or layout-contract change must make old noncanonical display cards ineligible for publication.
- Invalidate only incompatible display derivatives. Parsed source, stable locations, annotations, bookmarks, highlights, notes, and checkpoints are separate authorities and must not be cleared as a repair.
- A segment is migratable only if it proves canonical source interval, ordered ranges, layout/pagination identity, and seam/continuation compatibility. Otherwise use a typed safe miss and regenerate from source.
- Corrupt, partial, missing, or checksum-invalid cache data must not produce a partial authoritative deck. Quarantine/delete only the specific derivative according to current cache-service safety rules and record the reason.
- New writes must be atomic, bounded, and safe under concurrent readers. Retention protects the committed/current and necessary adjacent continuation evidence without retaining unlimited cards.
- Rollback must either ignore a future unsupported version safely or read an explicitly documented backwards-compatible record; it must not misinterpret new cards as old-layout compatible.

### Checkpoints

- Preserve the newest valid journal record and current epoch/revision ordering throughout migration.
- An identical-layout/pagination checkpoint demands the exact saved card signature. Missing exact identity triggers the approved recovery path, not semantic commit.
- A proved layout/parser/pagination change may place the checkpoint in an explicit migration/pending state, retain its semantic anchor and old exact record, and disable ordinary writes.
- Regenerate a canonical compatible window, publish and settle the card containing the semantic anchor, verify source containment and current layout identity, then atomically append a new exact signature and re-enable ordinary writes.
- If semantic resolution is ambiguous/unavailable or publication identity changed incompatibly, retain diagnostic/migration evidence and follow the owner-approved recovery policy. Do not rewrite to a default card.
- Corrupt newest journal records continue to fall back only to a valid older record under existing integrity/ordering rules. A repair must not flatten the journal into a single overwrite.
- Persistence and migration require a successfully opened book/session token and matching book/publication identity.

### Bounded storage and rollback gate

P06/P11 must record old/new formats, bytes retained, eviction behaviour, migration counts/outcomes, clean-install behaviour, rollback behaviour, and any intentionally nonmigratable records. A version bump is acceptable only after its tests, invalidation scope, and rollback result are in the ledger.

## 11. Risk register

| Risk ID | Risk | Likelihood | Impact | Detection | Mitigation | Related tasks/requirements | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| RISK-001 | Continuation state still depends on request/window indexes | High | Blocker | Construction-order identity mismatch | Stable source/layout-only continuation schema and reindex tests | TASK-P04-001/003; REQ-007, REQ-012, REQ-040 | REOPENED_BY_CHANGE_040 — fixed-snapshot proof retained; lazy end authority and bounded source-address-space transfer require correction |
| RISK-002 | Canonical target/backward regeneration becomes effectively whole-book work | Medium | Blocker | Source/card work counters on distant target | Bounded periodic restart checkpoints and maximum-work acceptance gate | TASK-P04-003/005/008; REQ-044–REQ-045 | MITIGATED_BY_P04 — bounded canonical target/backward work contains source 280 without any whole-book operation; P06/P11 still own cache-byte and release profiling |
| RISK-003 | Published-card immutability hides a wrong seam rather than rejecting it | High | High | Prefix preserved but adjacent range gap/overlap | Validate both signature and complete half-open seam evidence | TASK-P04-007; REQ-010, REQ-013, REQ-048 | REOPENED_BY_CHANGE_040 — ordinary transaction checks remain strict; cross-snapshot handoff has no valid publication seam yet |
| RISK-004 | Generated headings/fragments duplicate or change ownership at section seams | High | High | Heading-seam identity/adjacency fixtures | Explicit structural owner and canonical ordering | TASK-P03-006, TASK-P04-006, TASK-P09-005; REQ-011, REQ-028 | MITIGATED_BY_P03_P04 — focused structural/source ownership remains green; P09 heading-adjacency navigation evidence remains |
| RISK-005 | A measurement/render correction changes signatures and masks an unresolved construction-order mismatch | High | Blocker | Production parity evidence plus complete P03 rerun under recorded layout inputs | CHANGE-029 explains the nine identity-only F-field transitions, preserves every range/text/owner and reproduces the complete matrix twice | TASK-P05-001/003/007; REQ-007–REQ-008, REQ-014–REQ-015, REQ-051 | MITIGATED_BY_P05 |
| RISK-006 | Font availability changes metrics after checkpoint/cache use | Medium | Blocker | Captured resolved metrics before/after font readiness | CHANGE-025/026/029 prove terminal bundled coverage, changed metric/fallback identity and zero authority for pending/rejected evidence | TASK-P05-007; REQ-017 | MITIGATED_BY_P05 |
| RISK-007 | Warm cache publishes syntactically valid noncanonical islands | High | Blocker | Cold/warm complete identity comparison | Boundary/continuation validation and typed miss | TASK-P06-001/002/003; REQ-009 | REOPENED_BY_CHANGE_040 — codec-valid partial-window terminal evidence lacks independent book-end authority; contextual safe-miss gates required |
| RISK-008 | Cache migration deletes source/user data or exceeds storage | Low | Blocker | Temp-root migration/byte inspection | Scoped derivative-only invalidation, bounded migration, v4 atomic replacement and protected-byte tests | TASK-P06-005/006/007; REQ-045–REQ-046 | MITIGATED_BY_P06 — finite aggregate/temporary bounds, manifest-first eviction and rollback preserve source, checkpoint and user-data bytes |
| RISK-009 | Same-layout exact miss silently becomes semantic restore | High | Blocker | Partial-publication lifecycle test | Separate exact and genuine-change branches; keep barrier closed | TASK-P07-005, TASK-P08-003; REQ-003, REQ-047 | OPEN |
| RISK-010 | Default/late publication acquires checkpoint authority | Medium | Blocker | Held publication/callback race matrix | One restoration intent and gated commits | TASK-P07-005, TASK-P08-002/005/006; REQ-004–REQ-006 | OPEN |
| RISK-011 | Immediate exit loses the latest accepted card | Medium | Blocker | Settle→exit→reopen SQLite lifecycle test | Immediate staging and defined awaited flush order | TASK-P07-006, TASK-P08-008; REQ-020–REQ-021 | OPEN |
| RISK-012 | Delayed session A write contaminates book/session B | Medium | Blocker | Controlled delayed cross-book write | Per-book/session token plus epoch/revision checks | TASK-P07-007, TASK-P08-008/009; REQ-022–REQ-024 | OPEN |
| RISK-013 | Event-driven navigation deadlocks after polling removal | Medium | High | Completion timeout owned by test harness, state trace | Explicit publication/controller/settlement events with cancellation | TASK-P09-009; REQ-029–REQ-030, REQ-042 | OPEN |
| RISK-014 | Backward prepend preserves anchor but produces wrong predecessor | High | Blocker | Previous/current/next signature and coverage assertion | Canonical forward regeneration from earlier checkpoint | TASK-P04-005, TASK-P09-004; REQ-027 | OPEN — P04-005 proves bounded canonical predecessor generation; P09 navigation/controller proof remains |
| RISK-015 | Explicit jump caller still treats a legacy index as truth | Medium | Blocker | Call-site authority audit and window-reindex tests | Route all callers through stable resolver/state machine | TASK-P01-005, TASK-P09-008; REQ-031, REQ-049 | OPEN |
| RISK-016 | The P02 test-seam extraction changes current behaviour, leaves two drifting paginator implementations, or tests reproduce/overmock the defect | High | Blocker | Controlled parity/characterization comparison before P03; one implementation reachability review | One mechanically extracted production implementation, parity evidence, manual source oracle, and mock limits | TASK-P02-005/008, TASK-P03-007; REQ-032–REQ-035 | MITIGATED_BY_P02_P03; repair-phase oracle protection remains |
| RISK-017 | Legacy test failure drives a product regression | High | Blocker | Requirement mapping absent in proposed change | Replacement-first reconciliation policy and ledger | TASK-P10-001/003/005; REQ-036, REQ-039, REQ-050 | OPEN |
| RISK-018 | Host pass masks device gesture/font/lifecycle behaviour | Medium | High | Owner manual checklist and captured device evidence | P11 handoff; keep requirements unverified until owner result | TASK-P11-007/008; REQ-038 | OPEN |

## 12. Decision register

### Approved decisions

- DEC-APP-001 — Approved reader behaviour is exactly the requirement registry `REQ-001` through `REQ-051`; existing tests and current implementation are subordinate.
- DEC-APP-002 — Stable source identity is canonical; display indexes are transient hints.
- DEC-APP-003 — Same-layout restoration is exact physical-card restoration; semantic restoration requires a genuine incompatibility.
- DEC-APP-004 — Lazy pagination remains bounded and never repacks accepted/published cards.
- DEC-APP-005 — Only accepted settlement commits; preview/cancel/stale/default work does not.
- DEC-APP-006 — Epoch/revision protection and coordinator correction are preserved.
- DEC-APP-007 — Tests are replacement-first, production-path oriented, identity/content based, deterministic, and non-device for Codex.
- DEC-APP-008 — Non-reader cleanup is deferred and obsolete tests do not shape production.

### Decisions still required from the product owner

- DEC-REQ-001 — Choose the user-visible recovery when an identical-layout exact signature is unavailable after canonical cache/source regeneration: blocking retry/recovery screen, explicit reset prompt, or another nonapproximate outcome. It is required before TASK-P08-003 implements exact-miss failure handling, not before P01–P07. The implementation may not silently choose a nearby card.
- DEC-REQ-002 — Choose the user-visible outcome for an unresolvable/corrupt checkpoint after no valid journal record or unambiguous semantic anchor remains. It is required before the corresponding P08 recovery implementation, not before P01–P07. Technical handling must preserve evidence and avoid a silent authoritative default.
- DEC-REQ-003 — Approve exact realistic Gutendex/public-domain fixture titles/editions, repository-size budget, and provenance/license record before TASK-P02-004 adds books. It is optional for the core controlled-micro-fixture P02/P03/P04 path.
- DEC-REQ-004 — Approve the final manual-device platform/orientation/font/lifecycle matrix and what owner-observed result blocks release. It is required before P11 completion, not before earlier host-side phases.

### Technical questions resolvable through code inspection or tests

- DISC-001 — BASELINED in P01: coordinator/checkpoint are intended authorities; screen projections and lifecycle exits still require P07/P08 production-path proof.
- DISC-002 — RESOLVED by `CHANGE-20260911-030`: current whole, segmented, section-scoped, and memory display records cannot prove the canonical segment contract and are nonmigratable safe misses; only validated live P04/P05 constituents are structurally reusable while constructing a new record, never as legacy persistent reuse. P06-004/P06-005 own scoped invalidation and any future migration.
- DISC-003 — RESOLVED by `CHANGE-20260831-011`: the smallest safe unpublished frontier is a deferred predecessor plus pending tail reconstructed from stable source slices; restart/checkpoint, chain validation and derived 48-source/eight-card spacing are specified in `docs/development/nalori-canonical-pagination-design.md`.
- DISC-004 — RESOLVED FOR P05 by `CHANGE-20260910-029`: F001–F211 and U-01–U-10 close the layout/font/image/runtime questions, the production border is paint-only, image evidence is atomically recomputed, and the reviewed P03 identity transition reproduces twice. Classifier integration remains intentionally P06/P07/P08-owned.
- DISC-005 — Awaitable publication/controller/settlement event replacing time polling (TASK-P07-001, TASK-P09-009).
- DISC-006 — BASELINED in P01: lazy stable callers and reachable legacy/index fallbacks are inventoried; P09 must unify them.
- DISC-007 — RESOLVED FOR P06 HOST: CHANGE-037 records measured source/display/cache maxima and finite release limits; TASK-P11-006 retains release/device profiling ownership.
- DISC-008 — RESOLVED FOR CONTROLLED HOST TESTS by `CHANGE-20260828-006`: current-production Lexend static 400/600/700/900 bytes are locally bundled under a test-only alias and verified from the Flutter root bundle. Production still exposes no resolved font/glyph-metric identity; final measure/render identity remains P05 work.
- DISC-009 — P02-007 inspection found that `BookCacheService.clearAll()` reaches a default-path lazy-index store and ReaderScreen does not inject individually configurable cache/index instances. Sandbox tests use only existing directory-taking constructors and must not claim default-path or screen lifecycle coverage.
- DISC-010 — PARTIALLY RESOLVED by `CHANGE-20260829-007`: the real paginator is directly callable with its production scheduler plus explicit generation/cancellation evidence. No `ReaderContractGate<T>` was connected because pausing it would add a second scheduling boundary. Controller attachment, display publication/settlement and final persistence-completion events remain P07/P09 discoveries; a test coordinator is not an acceptable substitute.

### Deferred product decisions

- DEC-DEF-001 — Non-reader test behaviours listed as `PRODUCT_DECISION_REQUIRED` in the test audit.
- DEC-DEF-002 — Reader visual/style values not necessary for reliability: density ratios, margins, colours, heading aesthetics, quote/share presentation, and Speed Read policy.
- DEC-DEF-003 — Broader search/Book Memory completeness, ordering, export, and presentation beyond stable-target navigation.
- DEC-DEF-004 — General legacy parser/cache retirement and giant-XHTML subdivision unless profiling proves they block these requirements.

## 13. Progress dashboard

| Phase | Status | Completed tasks | Total tasks | Entry criteria met | Exit criteria met | Blocking issue | Latest change-log entry |
| --- | --- | ---: | ---: | --- | --- | --- | --- |
| P00 — Planning baseline | COMPLETED | 4 | 4 | Yes | Yes | None | `CHANGE-20260827-001` |
| P01 — Behaviour/baseline confirmation | COMPLETED | 6 | 6 | Yes | Yes | No investigation blocker; product behaviour remains unverified | `CHANGE-20260827-003` |
| P02 — Trusted harness/fixtures | CORE_COMPLETED | 7 | 8 | Yes | Yes | None for core; P02-004/DEC-REQ-003 remain deferred/non-blocking | `CHANGE-20260829-007` |
| P03 — Construction-order characterization | COMPLETED | 7 | 7 | Yes | Yes | None | `CHANGE-20260831-010` |
| P04 — Canonical pagination | ARCHITECTURAL_CORRECTION_REQUIRED | 8 | 8 | Yes | No | Immutable lazy snapshot handoff, packing identity and bounded backward/retention proofs | `CHANGE-20260919-040` |
| P05 — Layout contract/fingerprint | COMPLETED | 7 | 7 | Yes | Yes | None; later cache/restoration consumption remains in its owning phases | `CHANGE-20260910-029` |
| P06 — Canonical caches/migration | REGRESSED_ON_DEVICE | 7 | 7 | No (P04 gate reopened) | No | P04 handoff/end-proof correction and ordinary A059 chapter/book-switch verification | `CHANGE-20260919-040` |
| P07 — Lifecycle tests | NOT_STARTED | 0 | 8 | No | No | Reopened P04/P06 gates, DISC-005 and TASK-P07-001 discovery; no P07 work authorized | — |
| P08 — Restore/commit durability | NOT_STARTED | 0 | 9 | No | No | P07 red tests; DEC-REQ-001/002 | — |
| P09 — Navigation/retry | NOT_STARTED | 0 | 9 | No | No | P04/P06/P08; DISC-005/006 | — |
| P10 — Legacy-test reconciliation | NOT_STARTED | 0 | 7 | No | No | P03–P09 replacement evidence | — |
| P11 — Release gate/handoff | NOT_STARTED | 0 | 9 | No | No | P04–P10 and owner device evidence | — |

Overall: 46 of 89 tasks remain historically complete. No historical checklist task was added, unchecked or renumbered. The separate deferred scrubber item is UNSTARTED and excluded from this denominator. P03 is 7/7, P04 is 8/8 with its lazy-input/publication gate `ARCHITECTURAL_CORRECTION_REQUIRED`, P05 is 7/7, and P06 is `REGRESSED_ON_DEVICE` at 7/7. CHANGE-040 is design and red characterization only. Fixed-snapshot P03–P06 evidence remains historical evidence; it does not establish lazy handoff, failure settlement, bounded post-failure work or physical-device acceptance. P04/P06 gates remain open and P07 is unstarted. The next bounded task is IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001, subject to the three implementation-entry proofs in the handoff design. TASK-P02-004 remains deferred and nonblocking. No production correction, schema change or device run was made by CHANGE-040.

## 14. Definition of release-ready

Reader reliability is release-ready only when all of the following are recorded in the change log:

1. The requirement-derived trusted reader-contract suite passes with exact commands, counts, duration, and exit status.
2. Preserved low-level parser/source/checkpoint journal tests pass within their stated scope.
3. Reconciled reader tests pass, and every changed/removed legacy test has replacement evidence and rationale.
4. One complete non-device Flutter suite finishes with a captured exit status and passed/failed/skipped/timed-out counts; an incomplete command is indeterminate.
5. Full-section, target-first, forward-first, backward-first, singleton expansion, cold cache, warm cache, eviction/reload, prepend, and heading seams produce identical canonical ordered identities where the contract says they must.
6. The real ReaderScreen A→B→A lifecycle restores exact card identity and visible source text under an identical layout.
7. Genuine layout/font/parser/pagination changes perform documented semantic migration and create a new exact signature only after verification.
8. Accepted swipe→exit, preview/cancel→exit, route pop, background, book switch, stale write, unopened session, failure, and retry scenarios pass through production paths.
9. No correctness-critical test or production transition depends on uncontrolled network, wall clock, arbitrary delay, uncontrolled `pumpAndSettle`, leftover cache/singleton state, or nondeterministic font availability.
10. Display/source/card/cache work and retained bytes remain within documented bounded limits without whole-book pagination.
11. Cache/checkpoint clean-install, migration, corrupt/partial data, incompatibility, and rollback outcomes are documented and pass.
12. The product owner performs and records the approved manual-device checklist; Codex does not substitute host tests for it.
13. No blocker/high requirement remains `NOT_STARTED`, `IN_PROGRESS`, `BLOCKED`, `IMPLEMENTED_NOT_VERIFIED`, `DEFERRED`, or `REGRESSED` for the intended release scope.
14. No known open blocker/high regression remains in the regression register.

## 15. Plan maintenance protocol

Every future Codex implementation task must:

1. Read this plan and `docs/development/nalori-reader-reliability-change-log.md` before changing code or tests.
2. Select an exact phase and task IDs, list linked requirement IDs, and confirm entry criteria.
3. Capture current status/HEAD and preserve unrelated dirty/untracked work; keep unrelated phases untouched.
4. Add requirement-derived tests before or alongside implementation as the phase specifies; never let a legacy test define behaviour by default.
5. Append a chronological change-log entry after work, including actual files, behaviour, commands, counts, exit status, failures, migration/performance impact, and remaining gaps.
6. Update the test evidence, regression, and test replacement ledgers where applicable.
7. Update task checkboxes, requirement statuses, phase status tables, and the progress dashboard only to match recorded evidence.
8. Mark a task `[x]` only after the production/test/document change exists, required commands completed, results are in the change log, linked requirements have the required evidence, and unresolved failures are disclosed.
9. Use `IMPLEMENTED_NOT_VERIFIED` when code exists but required automated or manual evidence is incomplete. Never promote helper-only evidence to lifecycle verification.
10. Record `REGRESSED` and add a regression row when a previously supported requirement fails; do not hide it by leaving tasks completed without qualification.
11. If scope or a task's purpose changes, append a decision/change entry and update forward-looking text explicitly; do not silently rewrite original ledger history.
12. Never rewrite an earlier change-log entry to make a result appear successful. Corrections are new entries.
13. Never claim same-layout restoration without exact physical-card identity, pagination determinism without complete ordered identity comparisons, cache equivalence from serialization alone, or durable exit without flush/close ordering evidence.
14. Never run device/emulator tests unless the product owner explicitly requests it; link owner-provided manual evidence at P11.
