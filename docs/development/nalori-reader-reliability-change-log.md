# Nalori reader reliability change log

Ledger initialized: 2026-08-27  
Plan: `docs/development/nalori-reader-reliability-plan.md`

## 1. Purpose and rules

This document is the chronological evidence ledger for the Nalori reader reliability repair. The plan records intended work; this ledger records what actually changed, what commands actually ran, and whether approved requirements were actually proved.

- Entries are chronological and append-only.
- Corrections are added as new entries; old entries are not silently rewritten.
- Every implementation entry references exact `TASK-*` and `REQ-*` IDs from the plan.
- Code existence alone does not equal verification.
- Failures, partial results, incomplete commands, environment limitations, regressions, and deferred validation are recorded explicitly.
- Unrelated dirty/untracked work is never claimed as part of an entry.
- A plan checkbox records completion status; this ledger records the proof supporting it.
- A passing isolated helper test is never proof of the complete reader lifecycle.
- Same-layout restoration is not verified without asserting the exact accepted physical-card identity and visible source content.
- Pagination determinism is not verified without comparing complete ordered card identities and source ranges across multiple construction orders.
- Cache equivalence is not verified by checking only record serialization, keys, manifests, or non-null cache hits.
- Durable exit is not verified without exercising or otherwise proving settlement→stage→flush→close/reopen ordering.
- If a command does not finish with a captured exit status, its result is `INDETERMINATE`.
- If task scope changes, add a decision/change entry rather than silently rewriting its original purpose.
- Existing dirty and untracked work is preserved and excluded unless an entry explicitly names a scoped change.
- Device/emulator tests are not run by Codex without explicit product-owner authorization; owner-supplied manual evidence is recorded distinctly.

## 2. Current verification dashboard

At initialization no reader-repair requirement was verified, and existing helper tests or historical reports alone still do not satisfy production-path evidence gates. The current rows below include the six requirements verified by the completed P04 gate.

| Requirement ID | Current status | Implementing task/phase | Latest evidence entry | Automated evidence | Manual evidence | Remaining gap |
| --- | --- | --- | --- | --- | --- | --- |
| REQ-001 | NOT_STARTED | P07/P08 | — | None | None | Exact ReaderScreen A→B→A signature/text lifecycle |
| REQ-002 | NOT_STARTED | P05/P07/P08 | — | None | None | Genuine-change classifier and semantic lifecycle |
| REQ-003 | NOT_STARTED | P07/P08 | — | None | None | Same-layout exact-miss screen test and repair |
| REQ-004 | NOT_STARTED | P07/P08 | — | None | None | Default/partial publication race proof |
| REQ-005 | NOT_STARTED | P07/P08 | — | None | None | One complete restoration-intent trace |
| REQ-006 | NOT_STARTED | P07/P08/P09 | — | None | None | Delayed publication/callback race matrix |
| REQ-007 | VERIFIED | P03/P04 | `CHANGE-20260908-021` | Three unchanged fixed-seed gates, complete P04 69/69 and unchanged P03 57/57 | Reviewed source membership retained | None for P04 construction-order scope |
| REQ-008 | VERIFIED | P03/P04 | `CHANGE-20260908-021` | Full, target-first, forward, backward/prepend and singleton paths green | Reviewed source membership retained | None for P04 construction-path scope |
| REQ-009 | NOT_STARTED | P03/P06 | — | None | None | Cold/warm/evict/regenerate identity equality |
| REQ-010 | NOT_STARTED | P04/P06 | — | None | None | Published prefix/suffix immutability |
| REQ-011 | VERIFIED | P03/P04 | `CHANGE-20260908-021` | Structural identity and ownership gates green across all frozen paths | Headings, lists, table, rich text, repeats and section seam reconfirmed | None for P04 structural-identity scope |
| REQ-012 | VERIFIED | P03/P04 | `CHANGE-20260908-021` | Stable canonical identities survive reindex, prepend and replacement; scoped analysis clean | Frozen ownership/signature inputs reviewed | None for P04 identity-input scope |
| REQ-013 | VERIFIED | P03/P04 | `CHANGE-20260908-021` | Canonical transaction and P03 coverage gates prove exact ordered append/prepend ranges | No gap, overlap, duplicate, reorder or omission found | None for P04 source-coverage scope |
| REQ-014 | NOT_STARTED | P05 | — | None | None | Shared versioned measure/render contract |
| REQ-015 | NOT_STARTED | P05 | — | None | None | Complete field inventory and fingerprint tests |
| REQ-016 | NOT_STARTED | P05 | — | None | None | Controls hidden/visible identity equality |
| REQ-017 | NOT_STARTED | P05 | — | None | None | Fallback/resolved font migration proof |
| REQ-018 | NOT_STARTED | P07/P08 | — | None | None | Real accepted-settlement→checkpoint evidence |
| REQ-019 | NOT_STARTED | P07/P08 | — | None | None | Invalid settlement journal invariance matrix |
| REQ-020 | NOT_STARTED | P07/P08 | — | None | None | Settled swipe→immediate exit→exact reopen |
| REQ-021 | NOT_STARTED | P07/P08 | — | None | None | Pop/background/book-switch flush ordering |
| REQ-022 | NOT_STARTED | P07/P08 | — | None | None | Delayed A write while B owns reader |
| REQ-023 | NOT_STARTED | P07/P08 | — | None | None | Preserved epoch/revision in integrated lifecycle |
| REQ-024 | NOT_STARTED | P07/P08 | — | None | None | Failed/cancelled open persistence rejection |
| REQ-025 | NOT_STARTED | P09 | — | None | None | Canonical adjacent-card API and tests |
| REQ-026 | NOT_STARTED | P01/P09 | — | None | None | Authority audit and reindex tests |
| REQ-027 | NOT_STARTED | P03/P04/P09 | — | None | None | Backward exact previous/current/next order |
| REQ-028 | NOT_STARTED | P03/P04/P09 | — | None | None | Heading ownership and adjacent navigation |
| REQ-029 | NOT_STARTED | P07/P09 | — | None | None | Injected failure preserves card/clears state |
| REQ-030 | NOT_STARTED | P09 | — | None | None | Fresh retry intent/generation/anchor proof |
| REQ-031 | NOT_STARTED | P01/P07/P09 | — | None | None | Complete explicit-jump stable-target matrix |
| REQ-032 | NOT_STARTED | P01/P02/P03/P10 | — | None | None | Requirement annotations on trusted tests |
| REQ-033 | NOT_STARTED | P02/P03/P07 | — | None | None | Real-path harness at each important layer |
| REQ-034 | NOT_STARTED | P02/P03/P07/P10 | — | None | None | Stable identity/text assertions throughout |
| REQ-035 | NOT_STARTED | P02/P07/P09 | — | None | None | Event-driven async tests and polling removal |
| REQ-036 | NOT_STARTED | P10 | — | None | None | Replacement-first evidence per legacy change |
| REQ-037 | NOT_STARTED | All/P10 | — | None | None | Scoped implementation diffs over future tasks |
| REQ-038 | NOT_STARTED | P11 | — | None | None | Owner-run approved device checklist |
| REQ-039 | NOT_STARTED | All/P10 | — | None | None | Requirement mapping before responding to failures |
| REQ-040 | NOT_STARTED | P01/P04/P09 | — | None | None | No canonical display-index owner |
| REQ-041 | NOT_STARTED | P08/P09 | — | None | None | Correction preserved in rejected-callback tests |
| REQ-042 | NOT_STARTED | P02/P07/P09 | — | None | None | No added/existing correctness delay in repaired path |
| REQ-043 | NOT_STARTED | P07/P08 | — | None | None | Failure injection proves root ordering repair |
| REQ-044 | NOT_STARTED | P04/P06/P09/P11 | — | None | None | Bounded work, no whole-book pagination |
| REQ-045 | NOT_STARTED | P04/P06/P11 | — | None | None | Measured display/card/cache memory bounds |
| REQ-046 | NOT_STARTED | P06/P11 | — | None | None | Correctness with warm/cold caches; scoped invalidation |
| REQ-047 | NOT_STARTED | P07/P08 | — | None | None | Identical-layout exact-miss nonapproximate outcome |
| REQ-048 | VERIFIED | P03/P04/P06 | `CHANGE-20260908-021` | Fixed-seed and transaction gates preserve committed prefix/suffix identities | Accepted prepend retained committed card and suffix | P06 still owns compatible persistent-cache publication, not this canonical immutability requirement |
| REQ-049 | NOT_STARTED | P01/P08/P09 | — | None | None | Single stable-location authority across paths |
| REQ-050 | NOT_STARTED | P10 | — | None | None | Legacy mapping/replacement ledger evidence |
| REQ-051 | NOT_STARTED | P03/P04/P05/P06/P10 | — | None | None | Reviewed rationale for every signature change |

## 3. Change summary by phase

P00/P01 contain planning and static-baseline evidence. P02 contains the trusted-contract/fixture foundation, deterministic bundled Lexend layout environment, temporary-store and generic async support, plus the mechanically extracted one-production-implementation paginator seam. P03 behavioral characterization is complete at 7/7 and its unchanged matrix is 57/57 green. P04 is complete at 8/8. P05 is `IN_PROGRESS` at 4/7: `CHANGE-20260908-022` records the inventory, `CHANGE-20260909-023` defines the immutable contract, `CHANGE-20260909-025` ships deterministic reader fonts/source evidence, and `CHANGE-20260909-026` makes production measurement/rendering consume the shared contract. Overall progress is 36/89; P05 exit criteria and P06 entry criteria remain unmet, no P05 requirement is promoted to VERIFIED, and RISK-005/RISK-006 remain open pending P05-007.

| Phase | First entry | Latest entry | Production files changed | Tests added/changed/removed | Requirements verified | Open regressions |
| --- | --- | --- | --- | --- | --- | --- |
| P00 | `CHANGE-20260827-001` | `CHANGE-20260827-002` | None | None | None | None recorded |
| P01 | `CHANGE-20260827-003` | `CHANGE-20260827-003` | None | None | None | Static baseline found current defects/risks; repair and production-path proof remain open |
| P02 | `CHANGE-20260827-004` | `CHANGE-20260829-007` | `lib/services/reader_card_paginator.dart`; `lib/screens/reader_screen.dart` delegates | Trusted fixtures/support plus focused production-kernel parity tests | None | Core complete at 7/8; current range-local pagination defect remains for P03/P04; P02-004 is deferred/non-blocking |
| P03 | `CHANGE-20260829-008` | `CHANGE-20260831-010` | None | Full-range, construction-order, structural, sandboxed production-cache matrices, plus the preserved 23-row failure ledger | None | P03 is COMPLETED at 7/7 and its unchanged matrix is 57/57 green; all 23 historical failure IDs remain preserved |
| P04 | `CHANGE-20260831-011` | `CHANGE-20260908-021` | `lib/models/canonical_pagination.dart`; `lib/models/canonical_pagination_checkpoint_index.dart`; `lib/models/reader_checkpoint.dart`; `lib/services/epub_parser.dart`; `lib/services/reader_card_paginator.dart`; `lib/services/progressive_display_state.dart`; `lib/screens/reader_screen.dart` | P04 state-machine, continuation/checkpoint, initial/target/forward, bounded backward, structural identity, transactional publication, focused seam/frontier/prepend/target regressions and independent unchanged final gate | REQ-007, REQ-008, REQ-011, REQ-012, REQ-013, REQ-048 | COMPLETED at 8/8; exit criteria met; P05 entry criteria met and P05 is now in progress |
| P05 | `CHANGE-20260908-022` | `CHANGE-20260909-026` | Shared immutable layout models/resolvers/adapters, production paginator/card consumption, font/image evidence admission | 34 focused contract/parity cases, construction-order smoke, standard transition, font/support and interaction/state tests | None; RISK-005/RISK-006 remain open | IN_PROGRESS at 4/7; P05-005/006/007 remain |

## 4. Test evidence register

| Evidence ID | Date | Command/test | Scope | Expected result | Actual result | Exit status | Environment | Requirements supported | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EVID-20260827-001 | 2026-08-27 | `rtk git status --short` | Planning baseline | Capture current dirty/untracked state without mutation | Extensive pre-existing modified/untracked work captured; both requested files were initially absent | 0 | Linux host; branch `feature/lazy-random-access-reader` | None | Status is repository-state evidence, not behavioural verification |
| EVID-20260827-002 | 2026-08-27 | `rtk git log --oneline --decorate -12` | Architecture history | Identify current HEAD and recent lazy-reader phase history | HEAD `9d77165`; phase commits and earlier snapshots listed | 0 | Same host/worktree | None | Historical completion claims remain nonauthoritative |
| EVID-20260827-003 | 2026-08-27 | No test command run | Planning task | Do not rerun the complete Flutter suite or modify runtime state | No unit, widget, integration, device, formatter, generator, migration, or analyzer command run | N/A | Same host/worktree | None | Required by this task's planning-only restrictions |
| EVID-20260827-004 | 2026-08-27 | Scoped `rtk rg -c` plus unique-ID checks using `rtk bash -lc` | Tracking-document integrity | 12 phases, 88 checklist tasks, 51 plan requirement rows, 51 ledger dashboard rows, only P00 checked | Counts matched; 4 P00 tasks checked and 84 implementation tasks unchecked | 0 | Same host/worktree | None | Structural document validation only |
| EVID-20260827-005 | 2026-08-27 | Scoped `rtk rg`, `rtk sed -n`, `rtk bash -lc` count checks, and `rtk git status --short --` for the two tracking paths | Pre-implementation sequencing correction | Verify the P02/P03/P04 dependency correction, P04/P05/P06 boundary, full-P01 recommendation, stable IDs/counts, and scoped writes | Confirmed revised task wording; 88 unique task IDs, 51 requirement IDs in each document, 12 phases, 4 checked P00 tasks, 84 unchecked tasks; only the two requested tracking files are this task's scoped writes | 0 | Same host/worktree | None | Structural/documentation evidence only; no Flutter/Dart test, analyzer, formatter, generator, migration, emulator, or device command ran |
| EVID-20260827-006 | 2026-08-27 | Read-only P01 commands recorded in CHANGE-20260827-003 | Current implementation authority/version/navigation baseline | Establish current branch, dirty-state distinction, complete reader lifecycle, cache compatibility, competing owners, explicit jumps and P02 seam | Current-tree findings recorded with exact symbols; P01 is complete as static evidence only | 0 for read-only commands | Linux host; feature/lazy-random-access-reader at 9d77165 | None | Historical reports were not treated as current authority |
| EVID-20260827-007 | 2026-08-27 | No test/analyzer/formatter/generator/migration/emulator/device command | P01 restrictions | Preserve runtime state and avoid creating implementation evidence | No prohibited execution occurred | N/A | Same host/worktree | None | P01 findings are not product verification |
| EVID-20260827-008 | 2026-08-27 | `rtk flutter test test/reader_contract/parser_source/reader_contract_fixture_test.dart` | P02 fixture foundation | Validate independently authored manifest/oracles, logical EPUB determinism and production parser exposure | 5 passed: manifest/range validation, rejection paths, archive entries/spine, two-build logical identity, and parser source/structure evidence | 0 | Linux host; no network/device access | REQ-032, REQ-034, REQ-051 support only | Does not verify pagination, cache, checkpoint or ReaderScreen lifecycle |
| EVID-20260827-009 | 2026-08-27 | `rtk dart analyze test/reader_contract/support/reader_contract_fixture.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart` | P02 new Dart files | Scoped static validation without examining legacy test scope | No issues found | 0 | Same host/worktree | REQ-032 support only | Focused analysis only; no full-project analyzer ran |
| EVID-20260828-010 | 2026-08-28 | Initial focused `rtk flutter test` over the three new P02 support test files | New storage support | Real temporary checkpoint close/reopen should run with the existing FFI test dependency | 11 passed, 2 failed: the initial FFI worker isolate could not resolve this host's absent unversioned `libsqlite3.so` linker name | 1 | Linux host; no network/device access | REQ-033 support only | First-run defect was confined to new support; corrected by using the existing no-isolate FFI test factory with the available versioned library, retaining real SQLite |
| EVID-20260828-011 | 2026-08-28 | Final focused `rtk flutter test test/reader_contract/support/reader_contract_layout_environment_test.dart test/reader_contract/support/reader_contract_async_test.dart test/reader_contract/support/reader_contract_sandbox_test.dart` | New P02 support self-tests | Layout declarations, fail-closed font control, gates/probes and real temporary stores | 14 passed | 0 | Linux host; temporary roots only; no network/device access | REQ-032–REQ-035, REQ-039, REQ-042, REQ-051 support only | Does not verify a product requirement, pagination, renderer parity or ReaderScreen lifecycle |
| EVID-20260828-012 | 2026-08-28 | Scoped `rtk dart analyze` over the six new support Dart files | New P02 support | No static issues in the new infrastructure/tests | No issues found | 0 | Same host/worktree | REQ-032–REQ-035 support only | Focused analysis only; no full-project analyzer ran |
| EVID-20260828-013 | 2026-08-28 | Final focused `rtk flutter test` over the three new P02 support test files | New P02 support | All support self-tests pass after the SQLite loader correction | 14 passed | 0 | Linux host; temporary roots only; no network/device access | REQ-032–REQ-035, REQ-039, REQ-042, REQ-051 support only | Final focused pass; not product verification |
| EVID-20260828-014 | 2026-08-28 | `rtk flutter test test/reader_contract/parser_source/reader_contract_fixture_test.dart` | Existing reader-contract fixture regression | Existing trusted fixture foundation remains green | 5 passed | 0 | Same host/worktree | REQ-032, REQ-034, REQ-051 support only | Existing test was executed but not modified |
| EVID-20260828-015 | 2026-08-28 | Scoped `rtk bash -lc` `rg`/count validation over plan and log | Tracker consistency | P02/P03/status counts and requirement IDs remain aligned | 89 unique plan task IDs; 15 checked tasks; 5 checked P02; 0 checked P03; 51 requirement IDs in each tracker | 0 | Same host/worktree | None | P02 remains IN_PROGRESS at 5/8; no product requirement verified |
| EVID-20260828-016 | 2026-08-28 | `rtk git diff --check -- docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md test/reader_contract/README.md test/reader_contract/support` | Scoped whitespace check | No scoped whitespace error | No output | 0 | Same host/worktree | None | Scope paths are untracked in this pre-existing worktree; final Dart format also reported 0 changes |
| EVID-20260829-017 | 2026-08-29 | Initial `rtk dart analyze test/reader_contract/support/reader_contract_layout_environment.dart test/reader_contract/support/reader_contract_layout_environment_test.dart` | New P02-006 font support | Scoped static validation after adding bundled font declarations | 11 errors plus 2 infos (13 issues): `FontWeight` cannot be a const-map key; no production file was involved | 3 | Same host/worktree | REQ-032, REQ-035, REQ-051 support only | First-run support-only defect; corrected by using ordinary immutable map inputs while preserving the four static asset identities |
| EVID-20260829-018 | 2026-08-29 | Initial `rtk flutter test test/reader_contract/support/reader_contract_layout_environment_test.dart` | New P02-006 layout/font self-test | Root-bundle Lexend readiness and state restoration | 8 passed, 1 failed: the new wrapper omitted `WidgetsLocalizations` | 1 | Linux host; no device/integration execution | REQ-032, REQ-035, REQ-051 support only | First-run support-only defect; corrected with existing Flutter global material localization delegates, not production behavior |
| EVID-20260829-019 | 2026-08-29 | Final scoped `rtk dart format` / `rtk dart analyze` / `rtk flutter test test/reader_contract/support/reader_contract_layout_environment_test.dart` | P02-006 deterministic font environment | Formatting, static validation and focused readiness/isolation/failure-path tests | Format: 2 files, 0 changed; analysis: no issues; test: 9 passed | 0 | Linux host; root-bundle assets only; no device/integration execution | REQ-032, REQ-035, REQ-051 support only | Test infrastructure only; no product requirement, pagination or renderer parity verified |
| EVID-20260829-020 | 2026-08-29 | `rtk sha256sum` over four Lexend binaries and `OFL.txt`; scoped `rtk git diff --check` | P02-006 font/provenance integrity | Committed binaries and upstream licence must match declared identity with no scoped whitespace error | Four font hashes matched the provenance record/installed descriptor hashes; `OFL.txt` SHA-256 `5da8505887d0fa7fe963445fd58852707fda34adfeb65af25c99d152bab285bd`; no diff-check output | 0 | Same host/worktree | REQ-032 support only | Asset identity is not a resolved metric identity |
| EVID-20260829-021 | 2026-08-29 | Scoped `rtk rg` tracker inspection, `rtk bash -lc` checked-task count, `rtk git status --short --untracked-files=all`, and `stat` of pubspec files | P02 tracker/scope integrity | Plan/log must agree on task status; current work must not alter production Dart, existing tests, dependencies or lockfile | Plan: 16 checked total, 6 checked P02, 0 checked P03; plan/log both P02 IN_PROGRESS 6/8 and CHANGE-20260828-006; `pubspec.lock` mtime remained 2026-08-24 while only the four permitted asset declarations were added to `pubspec.yaml`; extensive unrelated dirty/untracked work remained present and untouched | 0 | Same host/worktree | None | Existing production/test/lockfile diffs predate this bounded task; no staging/revert/discard action ran |
| EVID-20260830-022 | 2026-08-30 | Pre-extraction `rtk flutter test test/reader_layout_metrics_test.dart test/unit/screens/reader_list_pagination_test.dart test/unit/services/frame_budgeted_range_scheduler_test.dart --reporter compact`; `rtk flutter test --no-pub test/reader_contract/parser_source/reader_contract_fixture_test.dart test/reader_contract/support/reader_contract_layout_environment_test.dart --reporter compact` | Strongest available pre-extraction host baseline | Existing paginator-adjacent helpers/scheduler plus trusted fixture and controlled layout stay green before moving the private closure | 42 passed in 7.32 s tool wall time and 14 passed in 1.93 s tool wall time; both exit 0 | 0 | Linux host; restricted network, first command resolved only locally available packages; no device/integration execution | REQ-032–REQ-035 support only | The old closure was private, so no direct old-kernel capture was technically possible |
| EVID-20260830-023 | 2026-08-30 | `rtk dart format lib/services/reader_card_paginator.dart lib/screens/reader_screen.dart test/reader_contract/pagination/reader_card_paginator_parity_test.dart && rtk dart analyze ... && rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_parity_test.dart --reporter compact` | Final extracted-kernel formatting, scoped analysis and direct parity | One production implementation is statically sound and its controlled full/anchor/tail/cancellation baselines pass | Format: 3 files, 0 changed; analyze: no issues; 4 parity tests passed; combined 7.32 s | 0 | Linux host; deterministic root-bundle Lexend; immediate controlled scheduler yield; no delay/pumpAndSettle/device/network | REQ-032–REQ-035 support only | Frozen baseline includes decoded visible table text and is extraction parity, not canonical P03 truth or construction-order equality |
| EVID-20260830-024 | 2026-08-30 | `rtk flutter test --no-pub test/reader_layout_metrics_test.dart test/unit/screens/reader_list_pagination_test.dart test/unit/services/frame_budgeted_range_scheduler_test.dart --reporter compact` | Directly affected existing host regression | Moved/shared helpers and scheduler behavior remain green after extraction | 42 passed in 3.89 s | 0 | Same host; no device/integration/network | REQ-032–REQ-035 support only | Existing files were executed but not modified by this task |
| EVID-20260830-025 | 2026-08-30 | `rtk flutter test --no-pub test/reader_contract/parser_source/reader_contract_fixture_test.dart test/reader_contract/support/reader_contract_layout_environment_test.dart --reporter compact` | Trusted fixture and controlled layout regression | Fixture parsing/source evidence and deterministic Lexend setup remain green | 14 passed in 4.22 s | 0 | Same host; no device/integration/network | REQ-032–REQ-035, REQ-051 support only | Support/fixture files were executed but not modified by this task |
| EVID-20260830-026 | 2026-08-30 | Scoped `rtk rg` ownership/delegation/status checks, `rtk git diff --check` and scoped `rtk git status --short --untracked-files=all` | Single-implementation and scope integrity | Kernel-only algorithm symbols, screen/test delegation, 7/8/P03 status and clean scoped whitespace | Only `reader_card_paginator.dart` owns split/flush/rebalance state; screen and test each call `paginate`; tracker status matched; diff check and command exit 0 in 0.08 s | 0 | Same dirty host worktree | REQ-032–REQ-035 support only | Existing `pubspec.yaml`/lockfile and screen dirty status were present before this task; no Git mutation ran |
| EVID-20260830-027 | 2026-08-30 | `rtk dart format test/reader_contract/pagination/reader_card_pagination_evidence.dart test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart`; `rtk dart analyze test/reader_contract/pagination/reader_card_pagination_evidence.dart test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart`; `rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart --reporter compact` | TASK-P03-001 full-range characterization | Format/analyze the new test-only projection and run one complete real production paginator request against the trusted source oracle | Final format: 2 files, 0 changed in 0.02 s; analysis: no issues in 1.9 s; focused test: 1 passed in 4.5 s and emitted complete nine-card source/display/logical/identity/coverage evidence | 0 each | Linux host; deterministic root-bundle Lexend; real `ReaderCardPaginator.paginate`; no network/device/integration/full-suite execution | REQ-007, REQ-011, REQ-032–REQ-034, REQ-051 support only | Narrow full-range characterization only. It establishes no target-first, append/prepend, singleton, cache, or canonical-equivalence result. |
| EVID-20260831-028 | 2026-08-31 | `rtk flutter test test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart --reporter json` | TASK-P03-005 real cache matrix | Exercise cold, memory, disk, production eviction and fresh-service reload for two reviewed plans | 7 passed / 5 failed in 4.86 s; repeat 7/5 in 4.85 s; final proof 7/5 in 5.55 s | 1 each | Unique `ReaderContractSandbox` roots; deterministic Lexend; no default path/device/network | REQ-007, REQ-009, REQ-012–REQ-013, REQ-032–REQ-034, REQ-048, REQ-051 characterization | Five failures are intended equality mismatches after successful cache I/O, not harness exceptions |
| EVID-20260831-029 | 2026-08-31 | Individual JSON runs of target-first, forward/backward, singleton and cache behavioral files | TASK-P03-007 red-file proof | Every file reaches real production paths and fails only at its ordinary equality contract with ledger IDs | 3/12, 8/2, 6/4 and 7/5 pass/fail respectively; 23 red scenarios total | 1 each | Same controlled host environment | REQ-007–REQ-009, REQ-011–REQ-013, REQ-027–REQ-028, REQ-032–REQ-034, REQ-048, REQ-051 characterization | Durations 5.05 s, 4.91 s, 4.93 s and 5.55 s; diagnostics match ledger classifications |
| EVID-20260831-030 | 2026-08-31 | Individual JSON runs of structural ownership, ledger integrity, P03-001 and P02 parity files | Green controls and ledger completeness | Structural/source truth, ledger structure, full-range observation and extraction parity remain green | 6, 3, 1 and 4 tests passed | 0 each | Same controlled host environment | Characterization/support only | Durations 4.58 s, 3.40 s, 10.41 s and 4.47 s |
| EVID-20260831-031 | 2026-08-31 | Scoped `rtk dart format` and `rtk dart analyze` over nine touched pagination Dart files | P03-005/P03-007 static verification | No formatting drift or static issue | Format 9 files/0 changed in 0.14 s; analyze no issues in 1.42 s | 0 each | Same host/worktree | REQ-032–REQ-034 support | No project-wide analyzer ran |
| EVID-20260908-032 | 2026-09-08 | Three identical `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart` commands | Independent TASK-P04-008 final gate | Each run 3 passed, 0 failed, 0 skipped with identical evidence | 3/3 each; normalized 38-line plan/work/retention evidence identical; 7.226 s, 6.420 s, 6.330 s | 0 each | Linux host; controlled Lexend; no network/device/integration | REQ-007–REQ-008, REQ-011–REQ-013, REQ-048 | One prior compiler-startup failure produced no semantic result and was retried once as permitted |
| EVID-20260908-033 | 2026-09-08 | Complete focused P04 command including all six focused files and the unchanged final gate | Complete P04 regression | Minimum 69/69 | 69 passed, 0 failed, 0 skipped in 9.974 s | 0 | Same controlled host | REQ-007–REQ-008, REQ-011–REQ-013, REQ-048 | Final-gate fixture and P03 hashes unchanged |
| EVID-20260908-034 | 2026-09-08 | Complete unchanged P03 matrix; frozen P02 parity and fixture/parser controls | Behavioral oracle and frozen controls | P03 57/57; P02 9/9 | P03 57 passed in 8.646 s; P02 9 passed in 4.357 s; no failures/skips | 0 each | Same controlled host | REQ-007–REQ-013, REQ-048; P02 support | REQ-009/010 remain unverified pending P06 cache evidence |
| EVID-20260908-035 | 2026-09-08 | Scoped analytics-suppressed Dart analysis; SHA-256, source/oracle, status, recent-write and whitespace checks | Static and scope integrity | No issues; frozen files unchanged; only authorized Markdown source edits | No issues in 3.163 s; hashes matched; source review complete | 0 | Same dirty worktree | REQ-011–REQ-013 support | Transient Flutter `build/` artifacts were the only non-source recent writes from test execution |

## 5. Chronological entries

## CHANGE-20260827-001 — Initialize reader reliability plan and evidence ledger

- Date/time: 2026-08-27, Asia/Kolkata; exact wall-clock time was not captured.
- Phase: P00 — Planning baseline
- Task IDs: TASK-P00-001, TASK-P00-002, TASK-P00-003, TASK-P00-004
- Requirement IDs: `REQ-001` through `REQ-051` were registered; no implementation requirement was completed or verified.
- Change type: Documentation/planning only
- Status before: No reader-reliability plan or evidence ledger existed in `docs/development/`.
- Status after: P00 complete; P01–P11 and every implementation requirement remain `NOT_STARTED`.

### Problem addressed

The completed reader/test audits and approved behaviours needed one implementation-ready dependency plan and a separate append-only proof ledger. Historical phase reports and the current helper-heavy suite could not safely serve as either product authority or completion tracking.

### Repository state before the change

- Branch: `feature/lazy-random-access-reader`.
- HEAD: `9d77165` (`Complete lazy random-access reader phase 5`).
- The working tree already contained extensive modified and untracked production, test, configuration, documentation, and media files.
- Important current reader/checkpoint/source-projection code and tests were themselves untracked. They were inspected as current-tree evidence and were not claimed, staged, reset, or altered.
- `docs/development/nalori-test-suite-audit.md` was present and untracked; the two tracking documents were absent.

### Changes made

| File | Symbol/area | Change | Reason |
| --- | --- | --- | --- |
| `docs/development/nalori-reader-reliability-plan.md` | Entire new document | Added 51 requirements, 12 phases, 88 tasks, architecture map, test architecture, migration/risk/decision registers, dashboard, release gate, and maintenance protocol | Provide the authoritative intended repair scope and progress model |
| `docs/development/nalori-reader-reliability-change-log.md` | Entire new document | Added append-only rules, requirement dashboard, phase summary, test evidence, initial entry/template, regression register, and test replacement ledger | Separate actual evidence from planned work |

No production source, test, fixture, dependency, lockfile, configuration, schema, cache version, or generated file was changed by this entry.

### Behaviour before and after

Runtime reader behaviour is unchanged. The documentation now records approved outcomes and future evidence gates. In particular, it does not treat historical “complete” claims or passing helper tests as proof that pagination, restoration, navigation, or durable exit works.

### Tests added, rewritten or removed

None. No legacy test was reclassified through a code change, rewritten, skipped, renamed, or removed. The existing audit classifications remain planning evidence for P10.

### Commands and results

| Command | Result | Exit status | Duration/notes |
| --- | --- | ---: | --- |
| `rtk git status --short` | Captured extensive pre-existing dirty/untracked state | 0 | Read-only; no status entry was modified |
| `rtk git log --oneline --decorate -12` | Confirmed HEAD and recent five lazy-reader phase commits | 0 | Read-only history |
| `rtk ls -la docs/development` | Confirmed only the test-suite audit existed before these files | 0 | Read-only directory listing |
| Scoped `rtk rg` and `rtk sed -n` inspections over named docs, `lib/`, and `test/` | Confirmed current symbols, range-local packing reset/flush, progressive concatenation, exact-miss continuation, time-based navigation polling, versions, test/fixture paths, and audit gaps | 0 for successful scoped reads; one exploratory `rg` named a nonexistent `lib/services/reading_card_renderer.dart` and reported that path error while still returning other matches | No repository writes; the nonexistent path was not used in the plan |
| Scoped heading/count/unique-ID validation with `rtk rg -c` and `rtk bash -lc` | Confirmed 15 required plan sections, 7 required ledger sections, 12 phases, 88 unique task IDs, 51 unique requirement IDs in each document, 4 checked P00 tasks, and 84 unchecked implementation tasks | 0 | Structural documentation validation only |
| Flutter/Dart tests | Not run | N/A | Planning task explicitly prohibited a full-suite rerun and did not require focused execution |

### Requirement verification

| Requirement ID | Evidence | Status | Remaining gap |
| --- | --- | --- | --- |
| REQ-001–REQ-051 | Approved requirements were normalized into stable IDs and mapped to tasks/evidence gates | NOT_STARTED | All specified production/test implementation and verification work |

### Sources inspected

- `docs/development/nalori-test-suite-audit.md` in full as the current suite inventory and reliability evidence.
- Reader/parsing/lazy architecture reports: `docs/epub_parsing_system_audit.md`, `docs/epub_semantic_content_pipeline_audit.md`, `docs/lazy_random_access_reader_plan.md`, `docs/lazy_random_access_reader_progress.md`, `docs/lazy_random_access_reader_verification.md`, `docs/lazy_reader_smooth_navigation_progress.md`, and `docs/reader_checkpoint_adb_verification.md`.
- Current production paths in `lib/screens/reader_screen.dart`; `lib/widgets/reading_card.dart`; `lib/widgets/reading_card_deck.dart`; stable/card/checkpoint models; parser/index/section/session services; progressive/generation/visible coordinators; whole/segmented/memory caches; checkpoint store; reader-open/source-projection/derived-index/chapter-navigation integration.
- Current relevant test inventory and named audit groups, including checkpoint, coordinator, progressive display, segmented cache, lazy session/parser/index, layout/renderer, source projection, navigation settlement, and Book Memory/search-related tests.
- `test/fixtures/books/feature_rich_lazy_reader.epub` and its current fixture test/provenance references.
- Current read-only Git status and recent phase history.

### Performance, memory and migration impact

None in this entry. The plan adds explicit future gates for bounded continuation/card/cache state and controlled cache/checkpoint migration, but no runtime version or data changed.

### Risks and regressions

No runtime regression was introduced. Current verified defects and risks are registered in the plan; none is marked repaired. The principal documentation risk is that the large dirty working tree changes before P01, so P01 must capture a fresh baseline.

### Remaining uncertainties

- The exact production settlement/attachment event that can replace the current delayed polling loop.
- The smallest bounded canonical continuation/restart state and which existing cache segments, if any, can migrate safely.
- Exact measurement/rendering agreement for all inline/structured content and resolved-font states.
- Awaitable lifecycle boundaries for background/dispose and the exact session-open token needed for persistence.
- Complete index-authority audit of TOC/search/Book Memory/bookmark/highlight/note/internal-link/history call sites.
- Owner choices `DEC-REQ-001` through `DEC-REQ-004`.

### Manual verification required

The owner should review the decision register before phases whose entry criteria depend on those decisions. No device verification applies to this documentation entry.

### Work deliberately not performed

- No production or test implementation.
- No fixture/harness creation.
- No test, analyzer, formatter, generator, migration, coverage, device, or emulator command.
- No dependency, lockfile, configuration, schema, cache-version, or expected-signature change.
- No Git stage, commit, reset, clean, restore, revert, or discard.

### Follow-up tasks

Begin with TASK-P01-001, then TASK-P01-002: capture a fresh implementation baseline and trace the complete lifecycle ownership path before adding a harness or changing source.

### Commit/reference

No commit was created. The working tree remains unstaged and retains all pre-existing changes.

### Reusable entry template

Future Codex tasks must copy this template and append the completed entry below prior entries:

```md
## CHANGE-YYYYMMDD-NNN — Short title

- Date/time:
- Phase:
- Task IDs:
- Requirement IDs:
- Change type:
- Status before:
- Status after:

### Problem addressed

### Repository state before the change

### Changes made

| File | Symbol/area | Change | Reason |

### Behaviour before and after

### Tests added, rewritten or removed

For every changed legacy test, explain why it remained authoritative, was replaced, or was no longer valid.

### Commands and results

| Command | Result | Exit status | Duration/notes |

### Requirement verification

| Requirement ID | Evidence | Status | Remaining gap |

### Performance, memory and migration impact

### Risks and regressions

### Manual verification required

### Work deliberately not performed

### Follow-up tasks

### Commit/reference

Record a commit only if one was explicitly created. Do not stage or commit automatically.
```

## 6. Regression register

| Regression ID | First observed entry | Description | Severity | Affected requirements | Reproduction/evidence | Owner phase | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |

No regressions have been introduced or registered by the planning task. Current pre-repair defects belong to the plan's current-state assessment and risk register, not to a falsely completed implementation task.

## 7. Test-removal and replacement ledger

| Original test | Classification | Approved requirement | Replacement test/evidence | Reason changed or removed | Change entry |
| --- | --- | --- | --- | --- | --- |

No entries. Actual reader-test reconciliation begins only in P10 after stronger replacement coverage exists.

## CHANGE-20260827-002 — Correct pre-implementation dependency and phase sequencing

- Date/time: 2026-08-27, Asia/Kolkata; exact wall-clock time was not captured.
- Phase: P00 — Planning baseline / plan maintenance
- Task IDs: Corrected scope and dependencies for TASK-P02-004, TASK-P02-005, TASK-P04-002, and the P01/P02/P03/P04/P05/P06 phase guidance. No implementation checklist task was completed.
- Requirement IDs: REQ-007–REQ-017, REQ-032–REQ-035, REQ-039–REQ-042, REQ-044–REQ-046, REQ-048, and REQ-051 remain `NOT_STARTED`; no requirement was completed or verified.
- Change type: Documentation/planning correction only
- Status before: The plan described a circular P02/P03/P04 sequencing dependency and an overly narrow next-task recommendation.
- Status after: The plan establishes a linear test-seam → characterization → canonical-pagination sequence, makes realistic public-domain fixtures supplementary, and retains all implementation tasks as `NOT_STARTED`.

### Problem addressed

The prior plan made TASK-P02-005 require access to the real production paginator while allowing its extraction to appear in P04. P03 then depended on the P02 harness and P04 depended on P03's failing contracts. In effect, the plan contained the unexecutable loop `P02-005 → P04 extraction → P03 → P02-005`.

Current source inspection confirms the concern is material: `ReaderScreen._rebuildDisplayChunks` contains a local `generateDisplayRange` closure. That closure resets local packing state and flushes a request-local tail. A future test seam must expose this one production implementation before P03 can characterize its known construction-order defect; extraction must not repair that defect.

### Repository state before the change

- The existing extensive dirty and untracked worktree was preserved.
- Both tracking documents already existed as untracked planning files from CHANGE-20260827-001.
- `lib/screens/reader_screen.dart` was inspected read-only to confirm the location and shape of the local paginator closure; it was not changed.

### Changes made

| File | Symbol/area | Change | Reason |
| --- | --- | --- | --- |
| `docs/development/nalori-reader-reliability-plan.md` | Sections 2, 6, 7 (P01–P06), 8, 10–13, risk and decision registers | Corrected phase dependencies, task scopes, gates, risks, acceptance/exit criteria, dashboard, and next execution scope | Remove the circular dependency and prevent premature cache/layout authority or fixture selection from blocking core characterization |
| `docs/development/nalori-reader-reliability-change-log.md` | Phase summary, evidence register, this append-only entry | Recorded the planning correction and its validation evidence | Preserve chronological proof without rewriting CHANGE-20260827-001 |

TASK-P02-005 now owns a future, smallest-possible **production test-seam refactor, not behavioural repair**. If the ReaderScreen-local closure cannot safely be invoked, P02 may mechanically extract that one implementation, preserving current packing, splitting, flushing, identities, and outputs—including independently packed range behaviour. Its focused parity evidence must expose complete ordered source ranges, card identities, and visible text to P03. It must not duplicate paginator logic in tests or retain two independent paginator implementations.

TASK-P04-002 no longer extracts the packing engine. After deterministic P03 red evidence exists, it evolves the P02-extracted, characterized paginator into the canonical deterministic API with immutable pagination/layout inputs, valid predecessor continuation or restart state, ordered cards, successor continuation evidence, bounded operation, and no mutable window-local index authority. The behavioural change is restricted to approved failing P03 contracts.

TASK-P02-004 and DEC-REQ-003 now state that realistic public-domain Gutendex fixtures are supplementary. A manually reviewable controlled micro EPUB is sufficient for P02/P03/P04. Tests may not access the network; exact public-domain book/edition selection remains deferred until provenance, licence, and repository-size review. Leaving TASK-P02-004 deferred does not prevent P02 exit or P03/P04 start.

The P04/P05 boundary is explicit: P04 proves construction-order and seam determinism under one controlled explicit layout environment with immutable inputs, but does not freeze final measurement/rendering authority or persistent cache compatibility. P05 establishes the shared final measurement/rendering contract. A proven P05 measurement correction may legitimately change source ranges/signatures only with recorded layout-input and source-range rationale, and must rerun the complete P03 equivalence matrix; it cannot re-label a construction-order mismatch as layout change. P06 alone finalizes persistent display-cache compatibility, invalidation, migration, and version changes after P04/P05 stabilize.

### Behaviour before and after

Runtime reader behaviour is unchanged. The repaired execution order is:

```text
P00 → P01 (TASK-P01-001 through TASK-P01-006 together) → P02 test seam/harness → P03 deterministic red characterization → P04 canonical pagination → P05 final layout contract and P03 rerun → P06 cache compatibility/migration → P07 → P08 → P09 → P10 → P11
```

CHANGE-20260827-001's historical follow-up recommendation to begin only TASK-P01-001 then TASK-P01-002 is retained unchanged. It is superseded prospectively by this entry and the plan: the next bounded read-only Codex execution must complete all six P01 tasks together.

### Tests added, rewritten or removed

None. No production test seam, fixture, harness, production code, legacy test, expected value, signature, cache version, or test configuration was changed. The P02 extraction and P03/P04 tests remain future work.

### Commands and results

| Command | Result | Exit status | Duration/notes |
| --- | --- | ---: | --- |
| `rtk sed -n` over both tracking documents and the corrected P01–P06 sections | Read the existing tracking history and verified current plan wording before correction | 0 | Read-only inspection |
| `rtk rg -n "Required manual evidence|Current-tree version evidence|TASK-P02-005|TASK-P04-002|TASK-P02-004|DEC-REQ-003|Recommended next execution scope" docs/development/nalori-reader-reliability-plan.md` | Confirmed the corrected task/decision/next-scope wording and P06-only persistent-version boundary | 0 | Structural inspection |
| `rtk bash -lc` unique-ID/count checks | 88 unique task IDs, 51 plan requirement IDs, 51 ledger requirement IDs, 12 phases, 4 checked P00 tasks, and 84 unchecked tasks | 0 | Counts unchanged from CHANGE-20260827-001 |
| `rtk git status --short -- docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md` | Both requested documentation paths are untracked; no other path was written by this task | 0 | Scoped status only; broader dirty work preserved |
| Flutter/Dart tests, analyzer, formatter, generator, migration, emulator, and device commands | Not run | N/A | Prohibited by this planning-correction task |

### Requirement verification

| Requirement ID | Evidence | Status | Remaining gap |
| --- | --- | --- | --- |
| REQ-001–REQ-051 | Plan dependency and evidence gates were corrected only | NOT_STARTED | All future implementation, test, and production-path verification remains outstanding |

### Performance, memory and migration impact

None. The plan preserves bounded lazy operation and explicitly prohibits whole-book pagination, unlimited retained cards, permanent cache clearing, and premature cache-version/migration decisions. P06 remains responsible for persistent cache compatibility and migration after P04/P05 stability.

### Risks and regressions

No runtime regression was introduced. The corrected plan records the risk that a P02 extraction accidentally changes behaviour or produces two drifting implementations; parity characterization and a single implementation reachability review are now required before P03. It also records that P05 layout corrections can mask construction-order defects unless the complete P03 matrix is rerun.

### Manual verification required

No manual product decision blocks P01. DEC-REQ-001 (exact-signature failure UX) and DEC-REQ-002 (unrecoverable/corrupt-checkpoint UX) become blocking only before their P08 failure-handling implementation. DEC-REQ-003 is optional for core P02/P03/P04 and required only before adding realistic public-domain fixtures in TASK-P02-004. DEC-REQ-004 (manual-device matrix) is required before P11 completion.

### Work deliberately not performed

- No production code, test, fixture, dependency, configuration, schema, cache version, lockfile, generated file, or existing audit document was modified.
- No production paginator extraction was performed; it remains future P02 work.
- No test, analyzer, formatter, generator, migration, emulator, or device command ran.
- No Git stage, commit, reset, clean, revert, restore, or discard action ran.
- No implementation requirement was completed or marked verified.

### Follow-up tasks

The recommended next execution scope is one bounded read-only Codex turn covering TASK-P01-001, TASK-P01-002, TASK-P01-003, TASK-P01-004, TASK-P01-005, and TASK-P01-006 together. Its combined baseline, lifecycle, ownership, compatibility-version, and explicit-jump inventory is the required P02 input.

### Commit/reference

No commit was created. The working tree remains unstaged and all pre-existing dirty/untracked work remains preserved.

## CHANGE-20260827-003 — Complete P01 reader authority and compatibility baseline

- Date/time: 2026-08-27, Asia/Kolkata; exact wall-clock time was not captured.
- Phase: P01 — Behaviour contract and baseline confirmation.
- Task IDs: TASK-P01-001, TASK-P01-002, TASK-P01-003, TASK-P01-004, TASK-P01-005, TASK-P01-006.
- Requirement effect: REQ-001–REQ-051 remain NOT_STARTED. Static evidence narrows implementation/test work but verifies no product requirement.
- Change type: Read-only investigation plus the two authorized tracking-document updates.
- Status before: P00 was complete; P01 had zero of six tasks complete and the next scope was the P01 investigation.
- Status after: All six P01 tasks are complete as current-tree evidence. P02–P11 remain NOT_STARTED.

### Repository baseline and inspected scope

- Branch: feature/lazy-random-access-reader.
- HEAD: 9d7716597d95d578699e7a54544d92d5b4b234b6 (9d77165).
- Full status contained substantial pre-existing modified and untracked production, test, configuration, documentation and media work. Material P01 reader changes are distinguished in the plan; no pre-existing work was altered, staged, reset, cleaned, restored, reverted or discarded.
- The three required documents were read completely before production inspection: docs/development/nalori-reader-reliability-plan.md, docs/development/nalori-reader-reliability-change-log.md, and docs/development/nalori-test-suite-audit.md.
- Current production paths inspected include BookListScreen, BookLoadingScreen, ReaderOpenService, LazyBookSession, LazyEpubIndexService, lazy parsed/source identities, ReaderScreen open/restore/pagination/publication/settlement/persistence/lifecycle/navigation methods, display generation and visible-position coordinators, progressive state, whole/segmented/memory caches, checkpoint model/store/coordinator, source projection, derived search/Book Memory identities, ReadingCardDeck and all identified explicit-jump callers. Current focused test files were inspected as coverage evidence only.

### Exact read-only commands and execution boundary

| Command | Result |
| --- | --- |
| rtk wc -l docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md docs/development/nalori-test-suite-audit.md | Established required-document sizes before complete sequential reads. |
| rtk git branch --show-current | feature/lazy-random-access-reader. |
| rtk git rev-parse HEAD | 9d7716597d95d578699e7a54544d92d5b4b234b6. |
| rtk git status --short | Captured pre-existing modified/untracked tree, including current reader paths. |
| rtk git ls-files --error-unmatch lib/models/stable_book_location.dart lib/services/lazy_epub_index_service.dart lib/services/display_section_memory_cache.dart lib/screens/reader_screen.dart lib/services/lazy_book_session.dart lib/services/display_generation_coordinator.dart lib/services/progressive_display_state.dart lib/services/segmented_display_cache_service.dart | Distinguished committed bases from modified/untracked current evidence. |
| rtk git status --short -- lib/models/reader_checkpoint.dart lib/services/reader_checkpoint_store.dart lib/models/derived_book_index.dart lib/services/derived_book_index_service.dart lib/models/book_chunk.dart lib/screens/reader_screen.dart lib/services/lazy_book_session.dart lib/services/progressive_display_state.dart lib/services/segmented_display_cache_service.dart lib/services/book_cache_service.dart lib/screens/book_loading_screen.dart lib/services/reader_open_service.dart | Confirmed material modified/untracked reader implementation paths. |
| rtk sed -n '1,2000p' docs/development/nalori-reader-reliability-plan.md && rtk sed -n '1,2000p' docs/development/nalori-reader-reliability-change-log.md && rtk sed -n '1,1000p' docs/development/nalori-test-suite-audit.md | Complete final read of the two tracking documents and the required audit document. |
| rtk rg -n -C 2 "_flushReaderPersistence|_stageCommittedLifecycleSnapshot|_flushAndPopReaderRoute|didChangeAppLifecycleState|void dispose\(|_captureCommittedPosition|_scheduleReadingPositionSave|_persistCommittedPosition" lib/screens/reader_screen.dart | Traced checkpoint staging, persistence and each exit path. |
| rtk rg -n -C 2 "_navigateToStableLocation|_completeStableLocationNavigation|_navigateToSourceLocation|_onPageChanged|_onPageSettled|_runCommittedPageEffects|_scheduleCheckpointPublicationVerification" lib/screens/reader_screen.dart | Traced stable navigation, controller callbacks, settlement and restore verification. |
| rtk sed -n '5370,5815p' lib/screens/reader_screen.dart; rtk sed -n '6060,6195p' lib/screens/reader_screen.dart; rtk sed -n '6780,7035p' lib/screens/reader_screen.dart | Confirmed the local paginator kernel, progressive publication/rebase and retry behavior. |
| rtk rg --files test followed by rtk rg -n for _rebuildDisplayChunks, generateDisplayRange, ReaderCheckpointCoordinator, ProgressiveDisplayState and ReaderVisiblePositionCoordinator | Confirmed current helper/widget coverage and absence of a trusted production paginator lifecycle harness. |
| rtk sed -n '1,260p' lib/models/reader_position_session.dart; rtk sed -n '1,420p' lib/services/reader_structural_progress_service.dart; rtk sed -n '1,380p' lib/services/reader_source_projection_service.dart | Confirmed position-session, persistence queue, structural progress and stable source projection semantics. |
| rtk sed -n '430,725p' lib/services/reader_checkpoint_store.dart; rtk sed -n '1,440p' lib/models/reader_checkpoint.dart | Confirmed checkpoint restore barrier, epoch/revision journal and card identity inputs. |
| rtk sed -n '68,225p' lib/services/lazy_book_session.dart; rtk sed -n '107,278p' lib/services/reader_open_service.dart; rtk sed -n '70,270p' lib/screens/book_loading_screen.dart | Confirmed lazy session opening, target/window resolution, transferred-session failure close and reachable legacy route. |
| rtk sed -n '1,360p' test/unit/screens/reader_list_pagination_test.dart; rtk sed -n '1,180p' test/unit/services/progressive_display_state_test.dart; rtk sed -n '1,200p' test/widgets/reader_navigation_settlement_test.dart | Confirmed that current test coverage asserts helper/component behavior rather than the production paginator kernel plus full lifecycle. |
| rtk bash -lc count validation over the two tracking documents; rtk rg -n P01/checkpoint markers; rtk git status --short for the two tracking paths and whole tree | Verified 88 unique plan task IDs, 10 checked tasks, 51 requirement rows in each document, 12 phase rows, zero checked P02 tasks, P01 completion markers and preserved unrelated dirty/untracked work. |

No Flutter test, analyzer, formatter, generator, migration, device, emulator or integration-device command ran. No cache, dependency, configuration, schema, version, fixture, lockfile, production source or test file was written. Runtime behavior is unchanged.

### Verified lifecycle and ownership findings

1. Lazy opening is BookListScreen to BookLoadingScreen to ReaderOpenService.openLazy to LazyBookSession.open/loadAround to ReaderScreen; eager _loadLegacy remains reachable through lazy-route disable conditions.
2. ReaderVisiblePositionCoordinator is the intended accepted visible-location owner; ReaderCheckpointCoordinator.current and ReaderCheckpointStore are the intended checkpoint authority. ReaderScreen local indexes, pending targets, ReaderPositionSession, metadata/preferences and session location are competing projections or mirrors.
3. PageView.onPageChanged writes visible local state but does not persist; PageView ScrollEnd or post-animation ReadingCardDeck callback reaches _onPageSettled. Only an accepted settlement runs committed effects and stages the checkpoint.
4. Route pop awaits _flushReaderPersistence; lifecycle and dispose invoke it unawaited. ReaderPositionPersistenceQueue plus journal epoch/revision are useful safeguards, not proof of immediate-exit or cross-book behavior.
5. The coordinator rejects a same-layout missing exact signature, but ReaderScreen can continue through _pendingExactStableRestore, verify a semantic source-containing card and rewrite. This is a verified current failure.

### Compatibility, cache and navigation findings

- Current static identities are recorded in the plan, including parsed cache 6, whole display cache 3/v14, lazy section cache 3/section_v4_lists/dependency 1, lazy index schema 1, pagination nalori_cards_v16_lists, stable location 2, checkpoint/journal 1, segmented cache 3 and derived index/normalization 1.
- Exact checkpoint restore currently compares layout fingerprint, pagination version and card signature. Parser/source, font/paint geometry and genuine-layout classification are not one typed compatibility decision.
- Whole display payloads write a format field that deserialize does not validate. Segmented manifests check several identities but range payload comparison omits parser version and neither display cache proves a canonical predecessor/card seam.
- Stable search and derived Book Memory paths use stable source locations and common lazy navigation; reachable eager/legacy TOC, Memory, bookmark, highlight/note, link/history and scrubber fallbacks still transport indexes. Next/previous uses local index arithmetic across boundaries and is forbidden future authority.
- Stable navigation has intent/generation/controller protections but _completeStableLocationNavigation polls up to 30 times at 50 ms, so completion is not event-driven.

### Plan corrections and P02 boundary

No new requirement or version was added. P01 maps all findings to existing requirements and leaves their statuses NOT_STARTED. DISC-001, DISC-002 and DISC-006 are now baselined, with production-path repair/test obligations retained in P06–P09.

P02 must group work as: contract/fixture support; deterministic layout/store/event adapters; then a mechanical behavior-preserving extraction of the complete local paginator kernel in ReaderScreen._rebuildDisplayChunks. The seam is generateDisplayRange with its captured range-local output/mapping/pending state, split/merge/flush/rebalance helpers, measurement callbacks, scheduler/cancellation adapter and anchor finalization. It must expose the existing DisplayRangeResult from one production implementation; P02 must not repair the independently packed range behavior. P03 characterizes it; P04 repairs continuation/seams; P05 owns final layout classifier; P06 owns persistent cache policy; P08 owns restoration/flush authority; P09 owns event-driven navigation and explicit-jump unification.

### Task completion, blockers and decisions

- Completed: TASK-P01-001 through TASK-P01-006.
- Incomplete P01 tasks: none.
- P01 blockers: none for the required static investigation.
- Remaining technical blockers: no trusted production paginator seam/harness; no canonical continuation evidence; no shared paint/measurement classifier; unawaited lifecycle flushing; same-layout exact-miss fallback; time-poll navigation; and legacy/index authority paths.
- Product decisions required now: none. Later decisions are DEC-REQ-001 for same-layout exact-miss UX, DEC-REQ-002 for corrupt/unresolvable checkpoint UX, DEC-REQ-003 only before optional realistic fixture work, and DEC-REQ-004 before P11 device sign-off.

### Requirement status and behavior impact

All requirement dashboard rows remain NOT_STARTED because this entry is static architecture evidence only. No requirement was promoted to VERIFIED, no test result was claimed, and no runtime behavior changed.

### Commit/reference

No commit was created. The working tree remains unstaged; only docs/development/nalori-reader-reliability-plan.md and docs/development/nalori-reader-reliability-change-log.md were intentionally written by this task.

## CHANGE-20260827-004 — Add trusted reader-contract structure and micro-fixtures

- Date/time: 2026-08-27, Asia/Kolkata; exact wall-clock time was not captured.
- Phase: P02 — Trusted reader harness and controlled fixtures.
- Task IDs: TASK-P02-001, TASK-P02-002, TASK-P02-003 only.
- Requirement scope: REQ-007–REQ-011, REQ-028, REQ-032–REQ-035, REQ-039, REQ-042, REQ-044–REQ-045, REQ-048 and REQ-051. No requirement status changes; all remain NOT_STARTED.
- Change type: Test-only trusted-contract foundation and the authorized tracking-document updates.
- Status before: P00/P01 were complete; P02 had zero of eight tasks complete; P03–P11 were NOT_STARTED.
- Status after: TASK-P02-001 through TASK-P02-003 are complete; P02 is IN_PROGRESS at three of eight tasks. TASK-P02-004 through TASK-P02-008 and all P03 tasks remain unstarted.

Current count correction: exact unique-ID enumeration found 89 existing `TASK-*` IDs, not 88. The cause is the pre-existing P11 checklist's nine IDs (`TASK-P11-001` through `TASK-P11-009`) while its phase/dashboard total said eight. The current plan's P11 total and overall total are corrected to 9 and 89 respectively; no task was added, removed or renumbered. Earlier entries retain their historical 88-count record unchanged.

### Repository baseline and execution boundary

- Branch: `feature/lazy-random-access-reader`.
- HEAD: `9d7716597d95d578699e7a54544d92d5b4b234b6` (`9d77165`).
- The worktree already contained substantial modified and untracked production, test, configuration, documentation and media work. It was preserved. The two tracking documents were already untracked P01 outputs before this P02 slice.
- The required plan, change log (including CHANGE-20260827-002 and CHANGE-20260827-003), and test-suite audit were read completely before new files were created. `test/fixtures/books/feature_rich_lazy_reader.epub` and its fixture test were inspected only for conventions and were not altered or promoted to authority.
- The only production path exercised was the real `EpubParserService.loadAndParseFromFile` parser read. No `ReaderScreen` paginator, cache, checkpoint, lifecycle, device, emulator or integration path was run or changed.

### Files created and modified

| Path | Change | Purpose |
| --- | --- | --- |
| `test/reader_contract/README.md` | Created | Defines trusted-layer boundaries, authority order, annotations, allowed boundaries and prohibited testing practices. |
| `test/reader_contract/fixtures/reader_contract_fixture_manifest.json` | Created | Directly testable provenance, source, checksum, structure, spine, range and update contract. |
| `test/reader_contract/fixtures/reader_core_micro/mimetype` | Created | Visible EPUB mimetype source. |
| `test/reader_contract/fixtures/reader_core_micro/META-INF/container.xml` | Created | Visible container source. |
| `test/reader_contract/fixtures/reader_core_micro/OEBPS/content.opf` | Created | Visible package and ordered two-section spine source. |
| `test/reader_contract/fixtures/reader_core_micro/OEBPS/nav.xhtml` | Created | Visible navigation source. |
| `test/reader_contract/fixtures/reader_core_micro/OEBPS/text/chapter-one.xhtml` | Created | Chapter/subsection, mergeable/long/repeated prose, list, table, inline spans, footnote-style link and first seam source. |
| `test/reader_contract/fixtures/reader_core_micro/OEBPS/text/chapter-two.xhtml` | Created | Second heading, distinct repeated-text anchor and cross-section seam source. |
| `test/reader_contract/support/reader_contract_fixture.dart` | Created | Manifest validator plus deterministic temporary EPUB builder/archive inspector. |
| `test/reader_contract/parser_source/reader_contract_fixture_test.dart` | Created | Five focused fixture/parser-source foundation tests. |
| `docs/development/nalori-reader-reliability-plan.md` | Updated | Checked P02-001/002/003, P02 status/dashboard, source-truth evidence, blockers and next grouping. |
| `docs/development/nalori-reader-reliability-change-log.md` | Updated | Appended this entry and P02 phase/test-evidence status. |

No binary EPUB is committed. The builder writes the archive only into each test's unique temporary directory.

### Fixture/oracle evidence

The single generated fixture `reader-core-micro-v1` has two ordered spine sections and deliberately artificial prose. Collectively it supplies a chapter title, subsection title, three short mergeable paragraphs, a long paragraph containing a surrogate-pair rocket range, repeated text with two distinct structural anchors, ordered list, table, inline bold/italic spans, a footnote-style inline link, generated-heading-relevant section starts, and a first-section-tail/second-section-head seam.

The JSON manifest contains independently authored normalized source text, structural order, manually checked anchors, repeated-text identities, the exact seam endpoints, parser-source substrings and UTF-16 half-open ranges. Its validator rejects missing files/provenance/purpose, duplicate IDs, stale component SHA-256 records, unsupported structures, missing/out-of-order OPF spine/anchors, invalid ranges and mismatched UTF-16 substrings. Expected text/ranges are never generated from the production parser; no physical-card signature or count is asserted.

The real current parser opened the assembled fixture with two top-level chapters, 20 chunks and 65 anchors; headings, list semantics, table role, inline styles, links and the independently authored source substrings were present. No parser or fixture discrepancy was found.

### Commands and focused results

| Command | Result | Exit status | Duration/notes |
| --- | --- | ---: | --- |
| `rtk sed -n` over the complete required plan, change log and test-suite audit; scoped `rtk sed -n`/`rtk rg -n` over the existing fixture convention, parser, `BookChunk`, lazy index and `pubspec.yaml` | Established P01/P02 boundaries, existing fixture convention, real parser entry point and existing `archive` support before writing files | 0 | Read-only; no network access |
| `rtk dart format test/reader_contract/support/reader_contract_fixture.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart` | Scoped formatting of only newly created Dart files | 0 | Final run: 0 files changed in 0.02 s |
| Initial `rtk flutter test test/reader_contract/parser_source/reader_contract_fixture_test.dart` | Failed to compile only the new archive inspector because installed `archive` 3.6.1 exposes `ArchiveFile.isFile`, not `isDirectory` | 1 | Test-only support issue corrected without production or fixture-source change |
| `rtk dart analyze test/reader_contract/support/reader_contract_fixture.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart` | No issues found | 0 | Scoped to two new Dart files |
| `rtk flutter test test/reader_contract/parser_source/reader_contract_fixture_test.dart` | 5 passed: valid manifest/ranges; invalid-manifest rejection; archive entries/spine; two-build logical equality; real parser evidence | 0 | Test output elapsed `00:00`; final format/analyze/test composite completed in 5.4 s |
| `rtk bash -lc` numbered-task/checked-task/requirement/phase count validation using `rg -o "TASK-P[0-9]{2}-[0-9]{3}"`, `awk`, `sort -u`, and `wc -l` over both tracking files | 89 numbered task IDs, 13 checked tasks, 3 checked P02 tasks, 0 checked P03 tasks, 51 plan and 51 ledger requirement rows, 12 phase rows, and 9 P11 IDs | 0 | Exposed and corrected the existing P11 8-versus-9 dashboard mismatch |
| `rtk git status --short --untracked-files=all -- test/reader_contract docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md` | Listed exactly the new reader-contract files and the two authorized tracking documents; all unrelated dirty work stayed outside this scoped status record | 0 | Read-only scoped inventory |
| `rtk file` over the six `reader_core_micro` EPUB component sources | All six sources are text/XML/UTF-8 text, not an opaque binary EPUB | 0 | Read-only human-reviewability check |

No complete Flutter suite, analyzer outside the two new Dart files, formatter outside the two new Dart files, generator, migration, emulator, device or integration test ran.

### Scope correction, requirement effect and behavior impact

No requirement, task ID, dependency, schema, cache version, parser version, pagination version, display signature or production behavior changed. The P01 dependency correction remains: realistic public-domain books are supplementary, so the controlled micro-fixture satisfies this P02 slice and does not block P03's future micro-fixture path. Passing foundation tests support traceability/source truth only; they do not verify REQ-007–REQ-011, REQ-028, REQ-032–REQ-035, REQ-039, REQ-042, REQ-044–REQ-045, REQ-048 or REQ-051.

Runtime behavior is unchanged. No production source, existing test, existing fixture, dependency, lockfile, configuration, schema, cache, version or generated artifact was modified. No network access occurred.

### Task completion, blockers and recommended boundary

- Completed: TASK-P02-001, TASK-P02-002 and TASK-P02-003.
- Not executed: TASK-P02-004, TASK-P02-005, TASK-P02-006, TASK-P02-007 and TASK-P02-008. No P03 task started.
- P02 blockers: deterministic host layout/font/renderer controls, real temporary store isolation, explicit real-async event controls and the one mechanical behavior-preserving production paginator seam are still absent. The optional realistic-public-domain corpus remains deferred and is not a blocker.
- No product decision is required now. DEC-REQ-003 is required only before optional TASK-P02-004; later restoration/device decisions remain assigned to DEC-REQ-001, DEC-REQ-002 and DEC-REQ-004.
- Recommended next P02 scope: group TASK-P02-006, TASK-P02-007 and TASK-P02-008; after that, execute TASK-P02-005 alone with strict one-implementation parity evidence. Keep TASK-P02-004 deferred.

### Commit/reference

No commit was created. No Git staging, commit, reset, clean, restore, revert or discard command ran. All unrelated dirty/untracked work remains untouched.

## CHANGE-20260828-005 — Add deterministic reader-contract test controls

- Date/time: 2026-08-28, Asia/Kolkata; exact wall-clock time was not captured.
- Phase: P02 — Trusted reader harness and controlled fixtures.
- Task IDs: TASK-P02-006 (incomplete), TASK-P02-007 (complete), TASK-P02-008 (complete). TASK-P02-004 remains deferred and TASK-P02-005 was not started; no P03 task started.
- Requirement IDs: REQ-032–REQ-035, REQ-039, REQ-042, REQ-044 and REQ-051 are supported by infrastructure only. No requirement status changes; all remain NOT_STARTED.
- Change type: Authorized reader-contract support infrastructure, focused self-tests, README and tracking updates only.
- Status before: P02 was IN_PROGRESS with TASK-P02-001 through TASK-P02-003 complete (3 of 8); deterministic layout/store/event controls were absent.
- Status after: P02 remains IN_PROGRESS at 5 of 8. Real temporary-store isolation and generic async controls are complete. Layout declaration exists but reader-font readiness remains deliberately incomplete because no bundled reader text font is available.

### Problem addressed

Later paginator extraction, construction-order, cache/lifecycle and navigation tests need reproducible host declarations, temporary real stores and causal async control without copying production pagination/layout/checkpoint logic, using shared data, arbitrary delays or fabricated lifecycle behaviour.

### Repository state and execution boundary

- The extensive pre-existing dirty/untracked worktree was preserved. This task used only the authorized `test/reader_contract/support/` paths, new focused support tests, `test/reader_contract/README.md` and the two tracking documents.
- The required plan, complete change log, trusted reader-contract README, fixture manifest/support files from CHANGE-20260827-004, and P01 inventories were read before writing new support.
- Current inspection found that `ReaderCheckpointStore.forTesting` accepts a database factory/path; whole/segmented/memory/lazy/derived stores have existing configurable roots or instances; `BookCacheService.clearAll()` also reaches a default-path lazy index; and current app assets do not declare a local reader text font.
- No production source, existing test, completed micro-fixture source/oracle, dependency, lockfile, schema, version constant, device/emulator/integration path, network resource or production default user-data path was changed or used.

### Files created and modified

| Path | Change | Purpose |
| --- | --- | --- |
| `test/reader_contract/support/reader_contract_layout_environment.dart` | Created | Immutable layout/font declaration, local-root-bundle font loader, deterministic diagnostics and Flutter test-state apply/restore support. |
| `test/reader_contract/support/reader_contract_layout_environment_test.dart` | Created | Layout declaration, distinguishability, safe-area/controls isolation and fail-closed font/global-state self-tests. |
| `test/reader_contract/support/reader_contract_sandbox.dart` | Created | Unique temporary reader-contract root/identity, configurable real stores, temporary SQLite checkpoint and awaited cleanup. |
| `test/reader_contract/support/reader_contract_sandbox_test.dart` | Created | Root/identity/preference/cache isolation, real SQLite close/reopen and cleanup self-tests. |
| `test/reader_contract/support/reader_contract_async.dart` | Created | Typed one-shot gate and per-test chronological event probe. |
| `test/reader_contract/support/reader_contract_async_test.dart` | Created | Causal order, success/error, duplicate operation, isolation and close-cleanup self-tests. |
| `test/reader_contract/README.md` | Updated | Documents construction/teardown, real-vs-mocked store table, limits, prohibited misuse and later production connections. |
| `docs/development/nalori-reader-reliability-plan.md` | Updated | P02 task/status/count/dashboard, verified support paths, missing seams and next scope. |
| `docs/development/nalori-reader-reliability-change-log.md` | Updated | Phase summary, evidence register and this append-only entry. |

### Controls established and their limits

`ReaderContractLayoutInputs` deterministically records logical surface size, DPR, viewport, safe area, card-body dimensions, text scaler, locale, direction, reader family, weights/assets, declared metric identity, line/strut input, controls visibility, brightness and accessibility/media-query inputs. Its stable JSON is canonicalized for equal declared input maps. `ReaderContractLayoutEnvironment` disables Google Fonts runtime fetching before it attempts only root-bundle `FontLoader` assets, captures/restores the mutable Flutter test view/platform dispatcher state, and will only report ready after the local font load completes.

The repository has no declared bundled reader text font. The default environment therefore fails clearly before readiness instead of downloading Google Fonts or using a machine font. This leaves TASK-P02-006 incomplete. The production boundary exposes only a declared profile identity, not resolved font/glyph metrics; no identity was fabricated and P05 retains measure/render authority. Controls visibility is recorded, not claimed to be production measurement parity.

`ReaderContractSandbox` gives every test a unique system-temp root plus book/session/publication identity. It uses real production `BookCacheService.testing`, `SegmentedDisplayCacheService`, `DisplaySectionMemoryCache`, `LazyEpubIndexStore`, `DerivedBookIndexStore` and `ReaderCheckpointStore.forTesting`. Checkpoints use a real temporary SQLite database through the existing `sqflite_common_ffi` test dependency. On this Linux host the support configures the available versioned `libsqlite3.so.0` loader and uses the dependency's no-isolate FFI factory, so the real database operation remains in the test isolate. It does not substitute an in-memory checkpoint map.

Preferences use only `SharedPreferences.setMockInitialValues`, a test-framework platform adapter; it does not establish OS durability. Sandbox cleanup closes every checkpoint store, clears only each configurable sandbox-owned root, resets mock preferences and deletes the exact temporary root after verifying it is inside the system-temp directory. It intentionally never calls `BookCacheService.clearAll()` because that production method reaches a default-path lazy-index store. Current ReaderScreen cache/index singletons are not injectable into this sandbox, so default-path or screen-lifecycle equivalence is not claimed.

`ReaderContractGate<T>` records entered/released/failed/closed boundaries, holds a typed result/error until explicitly released, rejects double release/close deterministically and safely completes close paths. `ReaderContractEventProbe` is per-test and records chronological book/session/intent/generation/publication/card evidence; it can require presence, exact order or absence with immediate diagnostics. Neither helper is a coordinator, clock, paginator or controller-settlement fake. There is no injectable/observable current boundary for the screen-local paginator scheduler, controller attachment, display publication/settlement or final persistence completion; those remain explicit P02-005/P07/P09 seams.

### Focused evidence and first-run support defect

The first focused support run had 11 passing and 2 failing self-tests: only the new SQLite checkpoint tests failed because the FFI worker isolate attempted the absent unversioned `libsqlite3.so` name on this host. The support was corrected without touching production by applying the existing FFI dependency's versioned system-library override in `databaseFactoryFfiNoIsolate`; the final focused support run passed all 14 tests. This proves only the support's real temporary-store and cleanup behavior, not any product requirement.

### Final commands and results

| Command | Result | Exit status | Notes |
| --- | --- | ---: | --- |
| `rtk dart format test/reader_contract/support/reader_contract_layout_environment.dart test/reader_contract/support/reader_contract_async.dart test/reader_contract/support/reader_contract_sandbox.dart test/reader_contract/support/reader_contract_layout_environment_test.dart test/reader_contract/support/reader_contract_async_test.dart test/reader_contract/support/reader_contract_sandbox_test.dart` | 6 files formatted; 0 changed | 0 | Only new support Dart files |
| `rtk dart analyze test/reader_contract/support/reader_contract_layout_environment.dart test/reader_contract/support/reader_contract_async.dart test/reader_contract/support/reader_contract_sandbox.dart test/reader_contract/support/reader_contract_layout_environment_test.dart test/reader_contract/support/reader_contract_async_test.dart test/reader_contract/support/reader_contract_sandbox_test.dart` | No issues found | 0 | Scoped analysis only |
| `rtk flutter test test/reader_contract/support/reader_contract_layout_environment_test.dart test/reader_contract/support/reader_contract_async_test.dart test/reader_contract/support/reader_contract_sandbox_test.dart` | 14 passed | 0 | No arbitrary delay, `pumpAndSettle`, network, device or integration execution |
| `rtk flutter test test/reader_contract/parser_source/reader_contract_fixture_test.dart` | 5 passed | 0 | Existing trusted fixture-contract regression check; file unchanged |
| Scoped `rtk bash -lc` unique-ID/checked-task/REQ-ID checks using `rg -o`, `rg -n`, `sort -u`, `wc -l` and `awk` over the two trackers | 89 unique plan TASK IDs; 15 checked total; 5 checked P02; 0 checked P03; 51 plan and 51 log requirement IDs | 0 | P02 dashboard/phase summary both read 5/8 and CHANGE-20260828-005 |
| `rtk rg -n 'Future\\.delayed|pumpAndSettle|allowRuntimeFetching|rootBundle\\.load|Directory\\.systemTemp|BookCacheService\\.clearAll' test/reader_contract/support` | No delay or `pumpAndSettle` match; only explicit font-fetch block/root-bundle load/temp-root/default-clear warning matches | 0 | Static scope check only |
| `rtk git status --short --untracked-files=all -- test/reader_contract docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md` and `rtk git diff --name-only -- lib pubspec.yaml pubspec.lock` | Authorized new support/docs paths are untracked alongside the existing P02 fixture foundation; listed production/dependency diffs pre-existed and were untouched | 0 | No staging or repository mutation |
| `rtk git diff --check -- docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md test/reader_contract/README.md test/reader_contract/support` | No output | 0 | Scoped whitespace check |

### Requirement verification and behavior impact

No product requirement is verified. Passing support self-tests do not prove pagination, construction order, restoration, renderer metric parity, cache equivalence, controller settlement, stale-work acceptance or durable lifecycle behaviour. Runtime reader behavior is unchanged.

### Task completion, blockers and recommended boundary

- Completed: TASK-P02-007 and TASK-P02-008.
- Incomplete: TASK-P02-006 because a permitted bundled reader-font asset/configuration and resolved metric observation are unavailable without production/configuration modification.
- Remaining P02 blockers: the local-reader-font seam for P02-006 and the one behaviour-preserving production paginator extraction for TASK-P02-005. TASK-P02-004 remains explicitly deferred and non-blocking.
- Recommended TASK-P02-005 scope, after P02-006 is genuinely ready: mechanically extract the complete existing `ReaderScreen._rebuildDisplayChunks` paginator kernel into one callable production implementation, preserving current packing/splitting/flushing/identity/output behavior—including the known defect—and add only focused parity evidence exposing ordered source ranges, `ReaderCardIdentity` and visible text. Do not repair behavior, duplicate the paginator, change cache/schema/version data or start P03.

### Commit/reference

No commit was created. No Git stage, commit, reset, clean, restore, revert or discard command ran. All unrelated dirty/untracked work remains untouched.

## CHANGE-20260828-006 — Add deterministic bundled reader-contract font

- Date/time: 2026-08-29, Asia/Kolkata; exact wall-clock time was not captured.
- Phase: P02 — Trusted reader harness and controlled fixtures.
- Task IDs: TASK-P02-006 (complete). TASK-P02-001/002/003/007/008 remain complete; TASK-P02-004 remains deferred/non-blocking; TASK-P02-005 remains incomplete; no P03 task started.
- Requirement IDs: REQ-032, REQ-035 and REQ-051 are supported by deterministic host-test infrastructure only. No requirement status changes; all requirements remain NOT_STARTED.
- Status before/after: P02 was IN_PROGRESS at 5 of 8 with a fail-closed unbundled-font environment; it remains IN_PROGRESS at 6 of 8 with one ready controlled P03/P04 host font environment. TASK-P02-005 is the remaining execution blocker.

### Proven production choice and assets

`lib/models/reading_settings.dart` defaults `ReadingSettings.fontFamily` to `ReaderFontFamily.lexend` and regular weight, and selects `GoogleFonts.lexend` in `ReadingSettings.getTextStyle`. That code uses w900 headings; `lib/widgets/reading_card.dart` uses w700 inline bold and w600 list/structural text. The installed `google_fonts` 8.0.2 Lexend descriptor table supplies normal static objects for Lexend w400/w600/w700/w900. No exact reader binary was previously present.

The exact static bytes are registered only under the host alias `NaloriReaderContractLexend`, so no production Google Fonts selection changed. `assets/fonts/reader_contract/PROVENANCE.md` records each original Google Fonts API filename, official `fonts.gstatic.com` source, repository path, licence and required reason. `OFL.txt` is the official SIL Open Font License 1.1 from Google Fonts `ofl/lexend`. The verified asset SHA-256 values are w400 `e92ff07c5686aee1cf71ba2aaf8b3afcab70db722680d082dd2fc496e65fe383`, w600 `bcac18cdf67555e75f7d747fa6055c11fc58a61ea8cc68af0ade707717018908`, w700 `fe323c8e142d5f92b974a48973bac235966aa3a76cf0e6d76ea89d03f7a2aa3d`, and w900 `6c3c72060a805613a735fdb9523152f880e1cca7577bacfe751cfa7d5ece2053`. They are asset identity only, never claimed as resolved glyph metrics or a P05 fingerprint.

### Files created and modified

| Path | Change |
| --- | --- |
| `assets/fonts/reader_contract/Lexend-Regular.ttf`, `Lexend-SemiBold.ttf`, `Lexend-Bold.ttf`, `Lexend-Black.ttf` | Created official static root-bundle assets for normal w400/w600/w700/w900. |
| `assets/fonts/reader_contract/OFL.txt`, `assets/fonts/reader_contract/PROVENANCE.md` | Created upstream licence and human-readable source/checksum record. |
| `pubspec.yaml` | Declares only the four test-font files as root-bundle assets; no `fonts:` family declaration. |
| `test/reader_contract/support/reader_contract_layout_environment.dart` | Adds standard Lexend declaration, root-bundle-only integrity/readiness, diagnostics and clear failure paths. |
| `test/reader_contract/support/reader_contract_layout_environment_test.dart` | Adds nine focused declaration, readiness, isolation, restoration and failure-path self-tests. |
| `test/reader_contract/README.md` | Documents alias, provenance, teardown, limitations and prohibited misuse. |
| `docs/development/nalori-reader-reliability-plan.md`, this log | Update P02 task/status/evidence and append this entry. |

### Controls, evidence and limitations

`ReaderContractLayoutInputs.standard()` now declares paths, weights, SHA-256 asset identities and the production-declared profile string alongside its existing explicit surface, DPR, viewport, safe area, card body, scaler, locale, direction, strut, theme/media and controls inputs. Installation disables runtime Google Fonts fetching, reads every byte only through Flutter `rootBundle`, verifies each checksum, awaits `FontLoader.load`, and only then reports ready. Undeclared/missing assets, corrupt bytes and incomplete declarations fail clearly. Close restores mutable test view/platform-dispatcher and Google Fonts settings.

Flutter has no font-family unregister API; the immutable alias remains process-registered and is never reused with different bytes. Production exposes no resolved runtime glyph/metric identity. This is therefore a controlled P03/P04 host environment, not P05 measure/render parity, fallback/italic-resolution proof, a layout fingerprint, physical-card-boundary evidence or pagination evidence.

Two support-only first-run defects were fixed: initial analysis had 11 errors plus 2 infos (exit 3) because `FontWeight` cannot be a const-map key; the initial widget run had 8 passes and 1 failure (exit 1) because the new wrapper omitted `WidgetsLocalizations`. The code now uses ordinary immutable maps and existing Flutter global material localization delegates. Neither correction touched production or pagination.

| Command | Result | Exit |
| --- | --- | ---: |
| Targeted official `rtk curl -fsSL` requests to four `fonts.gstatic.com/s/a/<sha256>.ttf` objects and Google Fonts `ofl/lexend/OFL.txt` | Assets and licence obtained | 0 each |
| `rtk sha256sum assets/fonts/reader_contract/Lexend-Regular.ttf assets/fonts/reader_contract/Lexend-SemiBold.ttf assets/fonts/reader_contract/Lexend-Bold.ttf assets/fonts/reader_contract/Lexend-Black.ttf` | Four checksums matched provenance and the installed descriptor hashes | 0 |
| `rtk dart format test/reader_contract/support/reader_contract_layout_environment.dart test/reader_contract/support/reader_contract_layout_environment_test.dart` | 2 files, 0 changed | 0 |
| Final `rtk dart analyze test/reader_contract/support/reader_contract_layout_environment.dart test/reader_contract/support/reader_contract_layout_environment_test.dart` | No issues found | 0 |
| Final `rtk flutter test test/reader_contract/support/reader_contract_layout_environment_test.dart` | 9 passed | 0 |

The focused self-tests do not verify product requirements, source ranges, card identity, production fallback behavior, cache equivalence or lifecycle durability. Existing fixture/other-support tests were not rerun because they do not share this font setup.

### Scope confirmation and next boundary

No production Dart file, pre-existing test outside the authorized reader-contract support self-test, completed micro-fixture source/oracle, dependency, lockfile, schema or version constant changed. The authorized layout-environment support self-test was updated. Pagination behavior is unchanged. Runtime Google Fonts fetching is blocked throughout installation; undeclared/missing assets fail before readiness, so a developer-machine, Ahem or generic fallback cannot satisfy this harness.

P02 is IN_PROGRESS at 6/8. TASK-P02-004 remains explicitly deferred/non-blocking. Execute TASK-P02-005 alone next: mechanically extract the complete current `ReaderScreen._rebuildDisplayChunks` paginator kernel into one test-callable production implementation, preserve current packing/splitting/flushing/identity/output behavior (including the known defect), and add only focused parity evidence for ordered source ranges, `ReaderCardIdentity` and visible text. Do not repair behavior, duplicate the paginator, alter cache/schema/version data or start P03.

### Commit/reference

No commit was created. No Git stage, commit, reset, clean, restore, revert or discard command ran. All unrelated dirty/untracked work remains untouched.

## CHANGE-20260829-007 — Extract production paginator kernel with parity evidence

- Date/time: 2026-08-30, Asia/Kolkata; exact wall-clock time was not captured.
- Phase: P02 — Trusted reader harness and controlled fixtures.
- Task IDs: `TASK-P02-005` complete. `TASK-P02-001/002/003/006/007/008` remain complete. `TASK-P02-004` remains unchecked, explicitly deferred and non-blocking. No P03 task started.
- Requirement IDs: `REQ-032`, `REQ-033`, `REQ-034`, `REQ-035`, `REQ-039`, `REQ-042` and `REQ-051` receive bounded P02 seam/parity support only. No product requirement status changes; all remain `NOT_STARTED`.
- Status before/after: P02 moved from `IN_PROGRESS` at 6/8 to `CORE_COMPLETED` at 7/8. The approved core exit criteria are met; the optional public-domain task remains deferred. Overall progress is 17/89.

### Original and final symbol ownership

Before this change, `ReaderScreen._rebuildDisplayChunks` owned a private local
`generateDisplayRange` closure and its complete mutable kernel: request-local
`newDisplayChunks`, `newDisplayToOriginal`, `newOriginalToDisplay`, `pending`
and `pendingOriginals`; measurement and table helpers; split/slice metadata;
`splitChunkByHeight`; `splitOversizedRange`; `mergeChunks`; `flush`;
`tryRebalancePendingWithTinyNext`; scheduler checkpoints/cancellation;
anchor finalization; diagnostics; and construction of `DisplayRangeResult`.
Tests could not invoke that closure without mounting/bypassing the screen.

After this change, `ReaderCardPaginator.paginate` in
`lib/services/reader_card_paginator.dart` owns that one production algorithm.
Essential split/merge/list/sentence/boundary/anchor helpers moved with it or are
shared narrow top-level production helpers in the same file. The short local
`generateDisplayRange` inside `ReaderScreen._rebuildDisplayChunks` is now only
the owner adapter: it captures existing screen values into
`ReaderCardPaginatorRequest` and delegates to `_readerCardPaginator.paginate`.
The returned existing `DisplayRangeResult` continues through the unchanged
progressive scheduling/publication/cache path.

The explicit request/context surface contains the requested half-open
`DisplayRangeRequest` and source chunks, controlled measurement/layout budgets,
current `ReadingSettings`, body/heading styles and struts, text scaler,
production `FrameBudgetedRangeScheduler` and priority, live generation and
cancellation callbacks, diagnostic identities/callback and optional anchor.
The source list is exposed as an unmodifiable live view: the former local
closure read its supplied mutable list during computation, so snapshotting it
would silently change read timing. Pending state and mapping collections are
still created inside every request because that is the current behavior, not a
new continuation contract.

The kernel does not own or access controller movement, visible-position
settlement, publication authority, route/navigation state, checkpoint/cache
persistence or cache migration. No broad abstraction hierarchy was introduced.

### Files created and modified

| Path | Change |
| --- | --- |
| `lib/services/reader_card_paginator.dart` | Created the explicit request/layout/anchor types, shared production helpers and sole `ReaderCardPaginator.paginate` kernel. |
| `lib/screens/reader_screen.dart` | Modified only the paginator integration and former helper ownership: captures existing values and delegates; downstream generation/publication remains in place. This file already had unrelated dirty work, which was preserved. |
| `test/reader_contract/pagination/reader_card_paginator_parity_test.dart` | Created four focused direct-kernel parity cases using the trusted EPUB and controlled Lexend layout. Contains frozen evidence only, no paginator copy. |
| `test/reader_contract/README.md` | Documents the callable production seam, parity limits, live-read timing, known range-local behavior and unconnected gate. |
| `docs/development/nalori-reader-reliability-plan.md` | Marks only TASK-P02-005 complete, records 7/8 core completion and leaves P02-004/P03/product requirements untouched. |
| This change log | Updates P02 summary/evidence and appends this entry. |

No other production or test file was modified by this task. Existing fixture,
layout-support and directly affected helper/scheduler test files were executed
unchanged.

### Parity method and limitation

The strongest pre-extraction baseline ran 42 existing paginator-adjacent
layout/list/scheduler tests plus 14 trusted fixture/layout tests; all 56 passed.
The old implementation was a private closure whose layout and mutable values
existed only inside `ReaderScreen`, so a direct old-kernel call/capture was not
technically possible without retaining a forbidden duplicate or building a
widget-only bypass. The permanent evidence therefore uses the authorized
strongest alternative:

1. the 56 existing host checks passed before extraction and their same 56
   checks passed after it;
2. four direct tests call `ReaderCardPaginator.paginate` with the trusted
   parsed 20-source-chunk fixture and deterministic Lexend environment;
3. source inspection proves `ReaderScreen` delegates to that same method;
4. the baseline compares ordered visible text, structural order/type, complete
   UTF-16 half-open source/display ranges, source/spine/logical-block identities
   and complete `ReaderCardIdentity` signatures—not just count;
5. separate cases preserve the current anchored result (`[8,20)` requested,
   `[8,10)` finalized), partial `[4,8)` range-local tail flush, and explicit
   cancelled/empty/non-error result classification; and
6. structural search finds split/merge/flush/rebalance/pending algorithm state
   only in `reader_card_paginator.dart`; the test contains expected evidence,
   not production rules.

The full baseline currently emits nine cards as a diagnostic consequence, but
the assertion is the complete ordered evidence above. It is explicitly not a
P03 canonical oracle, establishes no construction-order equivalence and may
continue to expose current seams, duplicates or gaps in P03.

### Async seam and first-run extraction corrections

The real production scheduler, task priority and generation/cancellation
checks are explicit kernel inputs. The direct host test supplies the scheduler's
existing injectable yield callback as an immediately completed future so
Flutter fake time cannot strand a zero-duration timer. The first direct run
used the scheduler default and was manually interrupted with exit 130 after it
waited for fake time; no production code changed. No uncontrolled delay,
repeated `pumpAndSettle` or second scheduler was added.

`ReaderContractGate<T>` remains unconnected. A gate that holds release inside
this computation would introduce a second scheduling/completion boundary and
could change production ordering; direct invocation plus the real scheduler and
cancellation callback is the neutral seam. Controller publication/settlement
and persistence-completion gates remain P07/P09 work.

The first scoped analyzer run reported 13 extraction-only static issues
(unused imports, inappropriate test-visibility annotations and one redundant
argument); imports/annotations were corrected without changing the algorithm.
A subsequent analyzer info about the compile-time-disabled diagnostic adapter
was resolved by retaining a documented runtime adapter. Final scoped analysis
has no issues. A visible-table evidence refinement first referenced the
kernel-private decoder and produced one analyzer error (exit 3); the test was
corrected to use the existing public production content parser, without moving
or copying decoding logic. No focused test exposed or repaired a pagination
defect.

### Exact commands and results

| Command | Result | Duration | Exit |
| --- | --- | ---: | ---: |
| Pre-extraction `rtk flutter test test/reader_layout_metrics_test.dart test/unit/screens/reader_list_pagination_test.dart test/unit/services/frame_budgeted_range_scheduler_test.dart --reporter compact` | 42 passed | 7.32 s tool wall time | 0 |
| Pre-extraction `rtk flutter test --no-pub test/reader_contract/parser_source/reader_contract_fixture_test.dart test/reader_contract/support/reader_contract_layout_environment_test.dart --reporter compact` | 14 passed | 1.93 s tool wall time | 0 |
| Final `rtk dart format lib/services/reader_card_paginator.dart lib/screens/reader_screen.dart test/reader_contract/pagination/reader_card_paginator_parity_test.dart && rtk dart analyze ... && rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_parity_test.dart --reporter compact` | Format 3 files/0 changed; analyze no issues; 4 passed | 7.32 s combined | 0 |
| Final `rtk flutter test --no-pub test/reader_layout_metrics_test.dart test/unit/screens/reader_list_pagination_test.dart test/unit/services/frame_budgeted_range_scheduler_test.dart --reporter compact` | 42 passed | 3.89 s | 0 |
| Final `rtk flutter test --no-pub test/reader_contract/parser_source/reader_contract_fixture_test.dart test/reader_contract/support/reader_contract_layout_environment_test.dart --reporter compact` | 14 passed | 4.22 s | 0 |
| Scoped `rtk rg` kernel-ownership/delegation/tracker checks, `rtk git diff --check`, and scoped `rtk git status --short --untracked-files=all` | Sole kernel file; screen/test call same method; trackers consistent; no scoped whitespace error | 0.08 s | 0 |

The first pre-baseline command performed Flutter's normal dependency-resolution
step under the restricted-network sandbox and used locally available packages;
all later commands used `--no-pub`. No full-suite, integration, emulator or
device command ran.

### Deliberately unchanged behavior, identities and remaining seams

Current request-local construction remains observable: each range creates new
pending/maps, packs independently and flushes its tail; progressive append and
prepend still concatenate independently generated results. Existing split,
merge, table, list, structural heading, tail, rebalance, anchor and cancellation
decisions are unchanged. The baseline deliberately retains the current merged
navigation-source card, heading cards, table encoding and source-range/card
identity signatures. Any gap, duplicate, separately flushed tail or
construction-order dependence discovered in P03 must be recorded and left for
P04 rather than “corrected” in this entry.

No pagination/layout/schema/cache/checkpoint version constant, production
signature, cache format, schema, migration, dependency, `pubspec.yaml` or
`pubspec.lock` was changed by this task. No parser, renderer/measurement,
navigation, controller settlement, checkpoint, publication or cache authority
moved into the kernel. Extensive unrelated dirty/untracked work remains
untouched.

Remaining technical seams are canonical predecessor/successor continuation
and restart state (P04), final shared measurement/render identity (P05), cache
compatibility/migration (P06), real ReaderScreen lifecycle/publication/
settlement/store events (P07) and navigation completion (P09). The generic
paginator gate remains deliberately unconnected for the ordering reason above.

### Final status and recommended P03 grouping

`TASK-P02-005` is complete. P02 core is complete at 7/8 with
`TASK-P02-004` unchecked, deferred and non-blocking. P03 remains `NOT_STARTED`;
no pagination product requirement is marked verified.

Recommended P03 grouping: establish the independently manually reviewed
full-section baseline first (`TASK-P03-001`); then execute the full,
forward-first, backward/prepend, singleton expansion and heading-seam matrix
(`TASK-P03-002/003/004/006`) against this one kernel; finally run cold/warm/
evicted cache-order characterization and record the failure ledger
(`TASK-P03-005/007`). P03 should preserve and diagnose the current failures,
not update expectations to match them.

### Commit/reference

No commit was created. No Git stage, commit, reset, clean, restore, revert or
discard command ran. All unrelated dirty/untracked work remains untouched.

## Current detailed evidence for CHANGE-20260831-010

- Date/time: 2026-08-31 14:55:41 IST (Asia/Kolkata).
- Phase: P03 — Pagination construction-order characterization.
- Task order and status: `TASK-P03-005` completed first; only after its twelve
  cache outcomes were known was `TASK-P03-007` completed. P03 is `COMPLETED`
  at 7/7 and overall progress is 24/89. `TASK-P02-004` remains unchecked,
  deferred and non-blocking; P02 core remains complete at 7/8. Every P04 task
  remains unstarted.
- Requirement mapping: deterministic red characterization covers `REQ-007`,
  `REQ-008`, `REQ-009`, `REQ-011`, `REQ-012`, `REQ-013`, `REQ-027`,
  `REQ-028`, `REQ-032`, `REQ-033`, `REQ-034`, `REQ-048`, and `REQ-051`.
  These requirements remain unverified product requirements; red evidence is
  a repair oracle, not proof that current physical membership is canonical.
- Change type: test-only cache harness/matrix, permanent failure IDs and
  machine-readable ledger, plus authorized README and tracker updates. Runtime
  production code, behavior and formats are unchanged.

### Production cache discovery and exercised boundaries

ReaderScreen constructs its display key with
`BookCacheService.displayChunkKey`, then builds a
`DisplayGenerationSignature`. Memory records are addressed by
`DisplaySectionMemoryCacheKey(cacheKey, SourceChunkRange)` and stored/retrieved
with `DisplaySectionMemoryCache.put/get`; a hit is reconstructed through
`DisplaySectionMemoryCacheEntry.toResult`. ReaderScreen's
`_cacheProgressiveDisplayRange` also writes the same production result with
`SegmentedDisplayCacheService.writeSegment`, while
`_loadCachedProgressiveDisplayRange` checks memory before exact disk
`loadRange` and publishes through `ProgressiveDisplayState`. Initial disk
lookup can use `loadAroundSource`; tests used exact range retrieval because
the matrix owns explicit production request ranges.

The memory store's production policy is byte-bounded insertion/LRU-like order:
`get` promotes an entry and pinned prepared ranges are protected from
eviction. The test proves eviction via a real bounded
`DisplaySectionMemoryCache`, not file deletion or a substitute map. The disk
service persists a version-3 gzip JSON payload plus a signature-scoped
manifest beneath its injected root. Its current compatibility boundary checks
manifest version, book/cache key, parsed/parser versions, layout, settings,
viewport and source count, then payload version/book/cache key/parsed/layout/
settings/viewport/range evidence. Missing, corrupt or incompatible records
return a miss; incompatible/corrupt owned records are removed by production
logic. No incompatible or corrupt fixture was invented for this cache-order
slice.

Each record exposes requested/actual source range, file, card and mapping
counts, checksum, generation, status and byte count. The manifest carries the
book/cache/layout/settings/viewport/parsed/parser/source-count identities.
Serialized cards are reconstructed from persisted `BookChunk` and range data;
`ReaderCardIdentity` is recalculated against the controlled publication/layout
identity rather than stored as an independent field.

`SegmentedDisplayCacheService` exposes an injected `rootDirectory` but no
`close` method. Therefore the real available close/reopen seam is: await all
writes, discard the service object, construct fresh service instances over the
same sandbox-owned directory, read the manifest/payload bytes, and prove the
loaded chunks are newly deserialized objects. No lifecycle method or adapter
was invented.

### Storage isolation and cache comparison matrix

Every test creates a unique `ReaderContractSandbox` inside the Flutter test's
real-async boundary, immediately registers awaited teardown, and uses unique
book/session/publication identities. The sandbox owns the injected segmented
root and real production memory store, closes/releases its existing stores,
reports remaining files on cleanup failure, and deletes only its resolved
temporary root. No default user-data path, broad `BookCacheService.clearAll`,
default lazy-index store, unresolved deletion path, process-shared cache, or
test-order state is used.

Both reviewed plans use `p03-controlled-lexend-layout` on reference and actual
sides:

1. passing inline/section seam: `[0,12)`, `[12,16)`, `[16,17)`, `[17,20)`;
2. known-red merge/long/repeat: `[0,5)`, `[5,8)`, `[8,20)`.

For each plan, an independently regenerated full `[0,20)` production request
is the same-layout relational reference. The six states are cold full range;
cold segmented generation and insertion; warm production-memory hits; fresh-
service disk hits after proven memory misses; real bounded-memory eviction
with disk fallback for the evicted range; and awaited-write fresh-service
reload. All segment generations call `ReaderCardPaginator.paginate`, and all
replayed `DisplayRangeResult` values are assembled with production
`ProgressiveDisplayState.publishInitial/append`. The expected object is never
inserted into a cache and no cached result produces its own expectation.

Results are 7 pass / 5 fail:

- Both cold-full controls pass. All cold segmented, warm-memory, warm-disk,
  eviction/fallback and reload states for the inline/section-seam plan pass.
- Merge/long/repeat cold full passes. Its cold segmented (`P03-CACHE-001`),
  warm memory (`P03-CACHE-002`), warm disk (`P03-CACHE-003`), eviction/fallback
  (`P03-CACHE-004`) and reload (`P03-CACHE-005`) states fail ordinary complete
  sequence equality.
- Every cache failure first diverges at card 2. The fresh full reference owns
  sources `4,5,6,7`; the replay owns source 4 alone, followed by the separately
  packed `5,6,7` segment. Source/display/logical ranges, visible grouping,
  structural range ownership and `ReaderCardIdentity` consequently differ.
  All five results retain complete source 0–19 coverage with no missing,
  duplicate, overlap, reorder or out-of-range membership. Successful memory
  hits, memory misses, eviction victim/retained keys, manifest records,
  checksums, payload status/bytes and fresh deserialization prove the red
  result is not cache I/O, parser, font, SQLite, file, teardown or setup
  failure. Cache replay reproduces the existing island; no additional observed
  serialization/content defect is claimed.

### Formal failure ledger

`test/reader_contract/pagination/p03_failure_ledger.dart` is the directly
testable formal ledger with 23 distinct permanent rows:

- `P03-TARGET-001` through `P03-TARGET-012`: twelve target-first failures;
- `P03-FORWARD-001` and `P03-PREPEND-001`: two merge/long/repeat partition
  failures;
- `P03-SINGLETON-001` through `P03-SINGLETON-004`: four singleton expansion
  failures, two expansion orders for mergeable prose and heading seams; and
- `P03-CACHE-001` through `P03-CACHE-005`: the five actual cache replay
  failures above.

Every row names the exact file/test/scenario, layout, ordered requests and
target/expansion order, mapped requirement IDs, relational invariant, dynamic
same-layout full reference plus fixture-source authority, first divergent card
and neighboring seam, reference/actual source/display/logical ranges,
identity/signature and visible text, full coverage result, evidence-limited
classification, repeatability, P04/P06 repair owner, and prohibited shortcut.
Each row separately states observed result, source-supported request-local
flush/assembly mechanism, bounded inference and later repair responsibility;
no deeper canonical algorithm is asserted.

The separate passing summary records all six structural cases, the three
passing targets, eight passing partition cases, six passing singleton cases,
seven passing cache states, and complete source coverage across all red
scenarios. `p03_failure_ledger_integrity_test.dart` validates 23 unique IDs,
the exact 12/2/4/5 category counts, all mandatory fields, approved requirement
IDs, corresponding red test names, repair ownership and separation of passing
evidence. Its three tests pass; it does not replace, skip or neutralize the red
equality files.

### Files created and modified

| Path | Change |
| --- | --- |
| `test/reader_contract/pagination/reader_core_cache_order_harness.dart` | Created test-only connector to the real production paginator, memory/disk stores, records and progressive publication path. |
| `test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart` | Created the twelve-case cache comparison matrix and five ordinary red equality contracts. |
| `test/reader_contract/pagination/p03_failure_ledger.dart` | Created the 23-row formal failure data and separate passing summary. |
| `test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart` | Created three green ledger structure/completeness tests. |
| `test/reader_contract/pagination/reader_core_pagination_harness.dart` | Added explicit sandbox identities and one public production-state result publication helper; no pagination logic. |
| `test/reader_contract/pagination/reader_card_pagination_evidence.dart` | Minimally exposed the existing detailed comparator diagnostic for compact ledger-aligned reporting. |
| Target-first, forward/backward and singleton matrix test files | Added permanent scenario IDs to existing red test names/diagnostics; equality expectations are unchanged. |
| `test/reader_contract/README.md` | Documented cache ownership, isolation, states, results and ledger authority. |
| Reliability plan and this change log | Marked P03 complete at 7/7, overall 24/89, P04 entry ready and P04 work unstarted. |

No production file, fixture source/oracle, P02 parity expectation, dependency,
lockfile, schema, migration, cache format, pagination/layout/signature/version
constant or persistent production signature was changed.

### Test-only scheduling correction

The first cache test attempt created the sandbox directly inside
`testWidgets`; its awaited filesystem work remained behind Flutter's fake-time
zone and the command did not complete. A focused timeout reproduced the same
test-only scheduling issue. Those interrupted attempts are indeterminate cache
evidence and are not counted. Sandbox creation and cache I/O were moved into
`WidgetTester.runAsync`, the existing Flutter boundary for genuine host I/O;
no delay, repeated `pumpAndSettle`, production scheduler, cache implementation
or runtime behavior changed. A focused cold-full rerun then passed 1/1 in
3.86 s, after which the complete matrix executed normally.

### Exact focused commands and results

All commands were host-side and scoped. The red files retain ordinary
`expect(mismatch, isNull)` equality. JSON output shows each failure reaches
that expectation after successful paginator/cache setup and its stable ID,
first divergence and coverage classification match the ledger.

| Exact command | Result | Duration | Exit |
| --- | --- | ---: | ---: |
| `rtk dart format` over the nine touched pagination Dart files | 9 files, 0 changed | 0.14 s | 0 |
| `rtk dart analyze` over the same nine files | No issues | 1.42 s | 0 |
| `rtk flutter test test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart --reporter json` | 7 pass / 5 intended equality failures; two earlier complete repetitions were identical | 5.55 s final; 4.86 s; 4.85 s | 1 each |
| `rtk flutter test test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart --reporter json` | 3 pass / 12 intended equality failures | 5.05 s | 1 |
| `rtk flutter test test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart --reporter json` | 8 pass / 2 intended equality failures; split evidence remains four ranges | 4.91 s | 1 |
| `rtk flutter test test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart --reporter json` | 6 pass / 4 intended equality failures | 4.93 s | 1 |
| `rtk flutter test test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart --reporter json` | 6 passed | 4.58 s | 0 |
| `rtk flutter test test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart --reporter json` | 3 passed | 3.40 s | 0 |
| `rtk flutter test test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart --reporter json` | 1 passed | 10.41 s | 0 |
| `rtk flutter test test/reader_contract/pagination/reader_card_paginator_parity_test.dart --reporter json` | 4 passed; P02 expectations unchanged | 4.47 s | 0 |

No full-suite, device, emulator, integration-device, network, dependency,
generator, schema, migration, default-cache-clear, Git stage/commit/reset/
clean/restore/revert/discard command ran. Unrelated dirty and untracked work
remains untouched.

### P03 exit and P04 entry

P03 exit criteria are met: every required construction/cache dimension reaches
the real production path under controlled layout/storage, complete ordered
ranges/identities/text are compared, 23 deterministic failures have permanent
reviewable ledger rows, and passing source/structural/cache controls remain
separate. P04 entry criteria are met, but no P04 task or repair began.

P04 owns canonical pagination/continuation and the 18 construction-order red
rows. P06 owns final cache compatibility/migration and the five replay rows
after P04/P05 stabilize membership/layout. Neither phase may change P03's
approved same-layout relational oracle merely to make a red test green.


## CHANGE-20260829-008 — Establish trusted full-range pagination characterization

- Date/time: 2026-08-30, Asia/Kolkata; exact wall-clock time was not captured.
- Phase: P03 — Construction-order characterization.
- Task IDs: `TASK-P03-001` complete. `TASK-P03-002` through `TASK-P03-007` remain unstarted; no P04 or pagination repair task was executed.
- Requirement IDs: `REQ-007`, `REQ-011`, `REQ-032`, `REQ-033`, `REQ-034`, and `REQ-051` receive narrow characterization evidence only. No product requirement is verified or promoted from `NOT_STARTED`.
- Change type: Test-only full-range characterization, small production-result projection/comparator support, and authorized tracker/README updates.
- Status before: P02 core was complete at 7/8 with TASK-P02-004 deferred; P03 was NOT_STARTED at 0/7.
- Status after: TASK-P03-001 is complete and P03 is IN_PROGRESS at 1/7. The full-range contract passes only as a narrow reviewed characterization; no construction-order equivalence is claimed.

### Problem addressed

The P02 parity baseline proved that the private paginator extraction preserved
captured behavior. It did not establish that one full request is correct,
complete against source truth, or canonical across construction orders. This
task records the first independently source-reviewed full-range evidence before
any target-first, append, prepend, singleton, retry, cache, or repair work.

### Repository state and execution boundary

- The worktree contained substantial pre-existing modified and untracked work,
  including production reader code, dependencies and lockfiles. It was retained
  without staging, reset, clean, restore, revert, discard, dependency access,
  cache mutation, or runtime change.
- The required plan, complete ledger, test-suite audit, trusted-contract README,
  fixture manifest/source oracle, parity baseline, entire production paginator,
  and current ReaderScreen delegation were read before writing the new test.
- The fixture reviewed was `reader-core-micro-v1`: the manifest's independently
  authored two-spine source text/ranges plus transparent `nav.xhtml`,
  `chapter-one.xhtml`, `chapter-two.xhtml`, and `content.opf` spine order.
- The controlled layout was `ReaderContractLayoutInputs.standard()` with the
  deterministic root-bundle `NaloriReaderContractLexend` alias. Runtime Google
  Fonts fetching remained disabled.
- The sole production entry point was `const ReaderCardPaginator().paginate`
  with the full `DisplayRangeRequest` `[0,20)`. ReaderScreen's current adapter
  delegates to the same `ReaderCardPaginator.paginate` method; no screen,
  controller, cache, checkpoint, navigation, device, or lifecycle behavior was
  changed or claimed.

### Files created and modified

| Path | Change | Purpose |
| --- | --- | --- |
| `test/reader_contract/pagination/reader_card_pagination_evidence.dart` | Created | Projects production paginator cards and compares complete ordered evidence without duplicating pagination or identity construction. |
| `test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart` | Created | Executes the trusted full `[0,20)` production request, validates reviewed source/card evidence, logs the complete projection, and records coverage/identity diagnostics. |
| `test/reader_contract/README.md` | Updated | Documents P03's source authority, noncanonical full-range boundary, and comparator diagnostic rules. |
| `docs/development/nalori-reader-reliability-plan.md` | Updated | Marks only TASK-P03-001 complete and P03 IN_PROGRESS at 1/7. |
| `docs/development/nalori-reader-reliability-change-log.md` | Updated | Adds this chronological entry and focused evidence record. |

No production, fixture source, fixture manifest, P02 parity baseline,
dependency, lockfile, schema, signature format, cache format, or version file
was modified.

### Trusted full-range evidence

The full source interval `[0,20)` produced nine current physical cards. The
test reports each card's structural type, raw and decoded visible text, all
half-open source/display/logical ranges, section/logical-block identity fields,
calculated `ReaderCardIdentity` and signature, source-coverage result, and
observable origin labels. Its full JSON evidence is emitted by the focused
test; the identity signatures recorded in that run were:

| Card | Reviewed source membership | `ReaderCardIdentity.signature` | Observable current origin |
| ---: | --- | --- | --- |
| 0 | `0:[0,20)`, `1:[0,22)` | `bbcef0bfea79d045d2f660416a6e2510b4d7b147aaf59de8e8e8059d10245654` | merged nav entries |
| 1 | `2:[0,20)`, `3:[0,23)` | `9e9aa12b00f7fe863647bb51d4f2a07c3dd4f8747bc1cf0bc8afd80ebe19951b` | merged headings |
| 2 | `4:[0,10)`, `5:[0,10)`, `6:[0,12)`, `7:[0,198)` | `f2262c3ecc71e1c568c6938935830134400b22c36d5a168be8f590fe2953ea22` | merged short prose/long paragraph |
| 3 | `8:[0,33)` | `1fe6fbc0ae400b0c1e3ded2b1efa9feea72cec969c83591745204ab70d9de017` | pending/rebalance not externally observable |
| 4 | `9:[0,19)`, `10:[0,18)` | `a550125c97da99487e0a79d9eea691e36284446fbae6232b06ff11ea9d25d90f` | merged ordered-list items |
| 5 | `11:[0,136)` | `4bf22db96d61356d305777cf060c8ea95a7174e43494c5f95ea2fce311c797f6` | pending/rebalance not externally observable |
| 6 | `12:[0,56)`, `13:[0,50)`, `14:[0,37)`, `15:[0,63)` | `4ed200ab0ea75831937807c82419f0f12c210d1116f60dd9a468c3ef04217e5b` | merged inline/link/footnote/tail prose |
| 7 | `16:[0,22)` | `d314217e99bb2c7ce94a76c8af454613684e5f76b416291cac9595a8e68c1a1f` | pending/rebalance not externally observable |
| 8 | `17:[0,52)`, `18:[0,33)`, `19:[0,55)` | `0de27fc7632caaec424955e2e2aae5092654c9713c016cbc26ede79b8d640f53` | merged second-section prose; final tail flush observable |

The range union covers each readable source unit exactly once: source 0 through
19 at its complete independently reviewed UTF-16 extent. The result reports no
gaps, overlaps, out-of-range membership, duplicated source membership, or
omitted readable source. The real production diagnostics were only
`range_generation_begin` and `range_generation_end`; they do not expose a
pending or rebalancing event, so those internals are explicitly recorded as not
observable rather than inferred.

### Independent manual source-range review

The following review is from fixture source, not generated from production
pagination. It supports source/content/structural claims and records current
physical membership separately:

| Full-range boundary/review target | Exact independently authored source evidence | Reviewed result |
| --- | --- | --- |
| First coverage | `nav.xhtml` TOC first link, `Micro Reader Chapter` | Card 0 starts at source 0 `[0,20)`. |
| Card 0 → 1 | `nav.xhtml` second TOC link then `chapter-one.xhtml#chapter-title` / `#subsection-heading` | Nav sources 0–1 end before heading sources 2–3 begin; all four logical identities remain distinct. Card 0 is the reviewed generated/TOC structural boundary, while card 1 is the chapter/subsection heading boundary. |
| Card 1 → 2 | `chapter-one.xhtml#subsection-heading` followed by `#merge-one` | Heading range ends at source 3 `[0,23)`; prose begins source 4 `[0,10)`. |
| Card 2 → 3 | `#merge-one`, `#merge-two`, `#merge-three`, `#long-paragraph`, then `#repeated-one` | Sources 4–7 remain ordered in card 2 and source 8 begins card 3. The rocket-containing long paragraph is whole at `7:[0,198)` in this layout: no long-paragraph physical split boundary was observed. |
| Card 3 → 4 | `#repeated-one` then `#ordered-list > #ordered-alpha` / `#ordered-beta` | The first repeated occurrence ends at `8:[0,33)`; card 4 starts the ordered list with complete `9:[0,19)` then `10:[0,18)` ranges and no marker-only membership. |
| Card 4 → 5 | `#ordered-beta` then `#reading-table` | The list ends at source 10 and table source 11 is one complete `11:[0,136)` range; decoded visible table text is `Column Value North Seven`, preserving the fixture source order. |
| Card 5 → 6 | `#reading-table` then `#inline-prose` | The table ends before source 12 begins the inline source sequence. |
| Card 6 → 7 | `#inline-prose`, `#linked-prose`, `aside#footnote-one`, `#seam-tail`, then OPF spine transition to `chapter-two.xhtml#second-section-title` | Card 6 covers sources 12–15 in order, including the link's visible `[linked note]` representation and footnote body; card 7 then owns second-section heading source 16. |
| Card 7 → 8 | `chapter-two.xhtml#second-section-title` followed by `#seam-head`, `#repeated-two`, `#second-prose` | Heading source 16 ends before card 8 begins source 17; the source seam passes 15 → 16 → 17 without omission. The second repeated occurrence is distinct source 18 / logical block `paragraph-2`, versus source 8 / `paragraph-6`. |
| Final tail | `chapter-two.xhtml#second-prose` | Card 8 ends at source 19 `[0,55)` and is the observable final tail flush. |

The source review supports these separate claims: (1) source coverage is
complete; (2) ordered visible content matches the independently authored
fixture source, including decoded table text; (3) structural identity is
preserved; and (4) current physical-card membership was observed. It does
**not** approve claim (5), that this physical-card membership is canonical.
The manually reviewed per-boundary evidence is the source basis for recording
the current membership, not approval that another construction order must emit
it. No opaque expected signature was authored; signatures above are calculated
production evidence only.

### Comparator and diagnostic support

`ReaderCardPaginationEvidence` is a production-result projection only. It does
not copy splitting, packing, merging, rebalancing, or `ReaderCardIdentity`
logic. Its later construction-order comparator compares complete ordered cards
rather than a count or signature alone. A mismatch names the construction
label, first divergent card, expected/actual ranges, identity fields and visible
text, coverage gaps/overlaps/out-of-range membership, and surrounding seam
cards. The P02 parity baseline was neither edited nor used as the P03 oracle.

### Commands and results

| Command | Result | Exit status | Duration/notes |
| --- | --- | ---: | --- |
| `rtk dart format test/reader_contract/pagination/reader_card_pagination_evidence.dart test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart` | Final format: 2 files, 0 changed | 0 | 0.02 s; only new P03 support/test files |
| `rtk dart analyze test/reader_contract/pagination/reader_card_pagination_evidence.dart test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart` | No issues found | 0 | 1.9 s; scoped analysis only |
| `rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart --reporter compact` | 1 passed; emitted the complete nine-card evidence above | 0 | 4.5 s tool wall time; focused P03-001 only |

The P02 parity test was not rerun because it was not modified and the direct
P03 request uses the same unchanged production paginator entry point. No full
Flutter suite, emulator, device, integration-device, network, dependency, or
pagination-repair command ran.

### Requirement verification and behavior impact

The focused contract currently passes, but only for the narrow full-range
characterization. It does not verify a pagination product requirement, prove
target-first/forward/backward/prepend/singleton equivalence, prove cache
equivalence, approve the nine current memberships as canonical, or authorize a
P04 repair. Runtime behavior is unchanged: no production code or data format
changed.

### Follow-up tasks

Recommended next P03 grouping: `TASK-P03-002`, `TASK-P03-003`,
`TASK-P03-004`, and `TASK-P03-006` as the construction/heading matrix using
this full-range evidence comparator; then `TASK-P03-005` and `TASK-P03-007`
for cache-order characterization and the failure ledger. Keep P02 at core
complete 7/8 with TASK-P02-004 deferred/non-blocking, and keep every P03 task
other than TASK-P03-001 unstarted until explicitly authorized.

### Commit/reference

No commit was created. No Git stage, commit, reset, clean, restore, revert or
discard command ran. All unrelated dirty/untracked work remains untouched.

## Current completion-record summary for CHANGE-20260831-010

- Date/time: 2026-08-31 14:55:41 IST (Asia/Kolkata).
- Phase/status: `TASK-P03-005` completed first, then `TASK-P03-007` completed;
  P03 is `COMPLETED` at 7/7 and overall progress is 24/89. P03 exit criteria
  and P04 entry criteria are met. P02 core remains 7/8 with `TASK-P02-004`
  deferred/non-blocking; every P04 task remains unstarted.
- Requirements characterized, not product-verified: `REQ-007`, `REQ-008`,
  `REQ-009`, `REQ-011`, `REQ-012`, `REQ-013`, `REQ-027`, `REQ-028`,
  `REQ-032`, `REQ-033`, `REQ-034`, `REQ-048`, `REQ-051`.
- Detailed evidence: the preceding current evidence section records exact
  production cache symbols/roots, compatibility and lifecycle boundaries,
  storage isolation, both range plans, all twelve cache outcomes, the complete
  file list, the first-run test-only scheduling correction, every focused
  command/duration/exit status, the 23-row failure-ledger schema and category
  counts, and P04/P06 repair ownership. It is incorporated into this entry.

The standard-Lexend cache matrix uses real sandbox-owned
`DisplaySectionMemoryCache` and `SegmentedDisplayCacheService` instances plus
production `ProgressiveDisplayState` publication. Seven cases pass. Five
merge/long/repeat cases—cold segmented, warm memory, warm disk, production
memory eviction with disk fallback, and fresh-service persisted reload—fail
ordinary equality after successful cache I/O. Each repeats the existing
source-4 independently flushed island at card 2 with changed physical ranges,
visible grouping and identity, while coverage remains complete and ordered.

The formal ledger is
`test/reader_contract/pagination/p03_failure_ledger.dart` with 23 distinct
rows: 12 target-first, two forward/prepend, four singleton-expansion and five
cache-replay failures. Its three integrity tests pass. Individual behavioral
files remain deterministically red at 12, 2, 4 and 5 equality failures and
their IDs/divergences match the ledger; structural ownership (6), P03-001 (1)
and P02 parity (4) remain green.

No production code/runtime behavior, fixture/oracle, P02 parity expectation,
dependency, lockfile, schema, migration, cache format, version or persistent
signature changed. No full-suite, device, emulator, integration-device,
network, default-cache-clear or Git mutation command ran. Unrelated dirty and
untracked work remains untouched. P04/P06 must repair the characterized
behavior without weakening the approved same-layout relational oracle.

## CHANGE-20260830-009 — Add P03 construction-order and structural red matrix

- Date/time: 2026-08-31 00:24:55 IST (Asia/Kolkata).
- Phase: P03 — Construction-order characterization.
- Task IDs: `TASK-P03-002`, `TASK-P03-003`, `TASK-P03-004`, and
  `TASK-P03-006` complete. `TASK-P03-001` remains complete.
  `TASK-P03-005` and `TASK-P03-007` remain unstarted. No P04 task or
  pagination repair was executed.
- Requirement mappings: the equality matrix provides red characterization for
  `REQ-007`, `REQ-008`, `REQ-011`, `REQ-012`, `REQ-013`, `REQ-027`,
  `REQ-028`, `REQ-032`, `REQ-033`, `REQ-034`, `REQ-048`, and `REQ-051`.
  The structural subset directly characterizes `REQ-007`, `REQ-011`,
  `REQ-013`, `REQ-028`, `REQ-032`, `REQ-033`, `REQ-034`, and `REQ-051`.
  No product requirement is marked verified.
- Status before/after: P03 moved from IN_PROGRESS at 1/7 to IN_PROGRESS at
  5/7; overall progress moved from 18/89 to 22/89. P04 remains NOT_STARTED.

### Mandatory API and ownership discovery

- `ReaderScreen._rebuildDisplayChunks` captures current layout, scheduler,
  generation/cancellation, diagnostic, and optional anchor inputs, then its
  short `generateDisplayRange` adapter calls the sole production
  `ReaderCardPaginator.paginate` kernel. No split/pack/merge/flush/rebalance
  implementation remains in the screen.
- ReaderScreen chooses initial/target intervals with
  `ProgressiveDisplayState.initialSourceRange` / `targetRange`. Current
  non-lazy constants are look-behind 16, look-ahead 79, minimum 96; lazy
  constants are 8, 39, and 48. This fixture has only 20 source units, so the
  live screen selector necessarily collapses every target to `[0,20)`.
- To expose the real range-local seam without inventing a test state machine,
  the target matrix uses the production `targetRange` selector with explicit
  controlled `lookBehind=1`, `lookAhead=1`, `minimumWindow=3`, publishes the
  target result with `publishInitial`, then follows ReaderScreen's lazy
  forward-before-backward sequence using `append` and `prepend`.
- `ProgressiveDisplayState` is the available real production assembly owner.
  All forward, prepend, target, and singleton scenarios publish actual
  `DisplayRangeResult` objects through its methods. No test manually
  concatenates cards, maps, or ranges.
- A target interval is source-index based. `targetOriginalIndex` identifies a
  source unit only. `ReaderCardPaginatorAnchor.textOffset` can stop initial
  generation after an offset-containing card is finalized, and screen
  location lookup can resolve an offset, but no offset-capable target-range API
  exists; none was added.
- The kernel still creates request-local pending/card maps and flushes every
  request tail. Production diagnostics expose `range_generation_begin/end`
  plus result/scheduler counts; they do not expose pending state, a tail-flush
  event, a rebalance event, or an anchor-finalization event. Returned cards are
  therefore the strongest observable tail evidence.

### Files created and modified

| Path | Change |
| --- | --- |
| `test/reader_contract/pagination/reader_core_pagination_harness.dart` | Created shared fixture/request/layout plumbing that calls the production paginator and production progressive assembly owner; includes independently authored source extents, structural assertions, and singleton diagnostics, but no pagination rules. |
| `test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart` | Created the fifteen-anchor target-first equality matrix. |
| `test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart` | Created five forward/prepend partition plans, including real split-stress evidence. |
| `test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart` | Created five singleton targets in both expansion orders with membership/identity diagnostics. |
| `test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart` | Created six independently authored structural/coverage comparisons across construction orders. |
| `test/reader_contract/pagination/reader_card_pagination_evidence.dart` | Minimally extended the existing projection/comparator for assembled production snapshots, exact duplicate/out-of-range coverage, scenario/layout/request/target context, and mismatch classification. |
| `test/reader_contract/support/reader_contract_layout_environment.dart` | Added the explicit P03-only reduced-height Lexend split-stress declaration. |
| `test/reader_contract/README.md` | Documented real ownership, target granularity/window limitation, matrix rules, diagnostics, and split-stress inputs. |
| `docs/development/nalori-reader-reliability-plan.md` | Corrected current header/architecture ownership, marked only the four authorized tasks complete, and recorded P03 at 5/7. |
| This change log | Corrected current phase-summary prose/table and appended this evidence entry without rewriting historical `CHANGE-*` claims. |

No production, fixture source/manifest, P02 parity expectation, dependency,
lockfile, schema, cache, signature, migration, or version file was changed.

### Layout declarations and split-paragraph evidence

The standard comparison declaration remains
`p03-controlled-lexend-layout` / `ReaderContractLayoutInputs.standard()`.
The P03-only `p03-controlled-lexend-split-stress-v1` declaration changes
exactly three inputs relative to standard: logical surface
`390×844 → 390×300`, viewport `390×844 → 390×300`, and recorded card body
`342×680 → 342×58`. Device-pixel ratio, all widths, safe area, text scale,
locale/direction, controls, brightness/accessibility inputs, default
`ReadingSettings`, and the verified Lexend 400/600/700/900 asset paths and
SHA-256 identities are unchanged. Full and compared constructions always use
the same declaration; identities are never compared across layouts. This is
not the final P05 layout contract.

Under split stress, real source 7 `[0,198)` produced four contiguous physical
ranges in the full, forward-first, backward/prepend-first, and both singleton
orders: `[0,58)`, `[58,125)`, `[125,191)`, `[191,198)`. The union is complete,
ordered, gap-free, nonoverlapping, nonduplicated, and within the authored
extent. The split case therefore satisfies the TASK-P03-003 blocker honestly;
no fixture prose or production measurement was changed. Production request
ranges have source-index granularity, so the partition isolates source 7 as
`[7,8)` and exercises its four internal physical splits but cannot begin at an
internal text offset.

### Target, partition, and singleton matrix

Each target-first scenario begins with the following controlled production
`targetRange`; any nonempty suffix is appended and any nonempty prefix is then
prepended: first-readable `0→[0,3)`; generated TOC `1→[0,3)`; chapter heading
`2→[1,4)`; subsection heading `3→[2,5)`; mergeable prose `5→[4,7)`; long
paragraph `7→[6,9)`; first repeated prose `8→[7,10)`; list start `9→[8,11)`;
table `11→[10,13)`; inline/link/footnote `13→[12,15)`; pre-seam source
`15→[14,17)`; second-section heading `16→[15,18)`; post-seam source
`17→[16,19)`; second repeated prose `18→[17,20)`; final source
`19→[17,20)`.

The five forward/backward plans are:

1. generated headings: `[0,2)`, `[2,4)`, `[4,20)`;
2. merge/long/repeat: `[0,5)`, `[5,8)`, `[8,20)`;
3. repeated/list/table: `[0,8)`, `[8,11)`, `[11,12)`, `[12,20)`;
4. inline/section seam: `[0,12)`, `[12,16)`, `[16,17)`, `[17,20)`; and
5. split stress: `[0,7)`, `[7,8)`, `[8,20)`.

Each plan runs full-range, first-to-last append, and last-to-first prepend
construction. Singleton targets are mergeable prose 5, split-stress long
paragraph 7, repeated prose 8, subsection heading 3, and section heading 16;
each runs forward-then-backward and backward-then-forward expansion.

### Deterministic equality mismatches deliberately left red

All equality assertions remain `expect(mismatch, isNull)`. None is skipped,
inverted, weakened, or given a per-order expected result.

- Target-first: 12/15 fail on both complete runs. Failing targets are
  first-readable, generated TOC, chapter heading, subsection heading,
  mergeable prose, long paragraph, first repeated prose, table,
  inline/link/footnote, pre-seam source, second-section heading, and post-seam
  source. List start, second repeated prose, and final source pass.
- Forward/prepend: only the merge/long/repeat plan fails, in both forward and
  backward/prepend order (2/10 red). Its first divergence is card 2: full
  membership `4,5,6,7` / signature
  `f2262c3ecc71e1c568c6938935830134400b22c36d5a168be8f590fe2953ea22`
  becomes separately flushed source 4 / signature
  `57de0bf94a841b8a8cace219053ed0e2809f4ffe3f490cde379903c453721a98`,
  followed by independently packed `5,6,7`. Coverage remains complete.
- Singleton: mergeable source 5 and subsection-heading source 3 fail in both
  expansion orders (4/10 red). Source 5 remains a `[5:0,10)` island with
  signature `1f1d6286fee84b79c4e69ef2fa6b286b90d9c462bfbc6e13dd0b96d5e41dc79c`
  instead of full membership `4,5,6,7` / the full signature above. Source 3
  remains a `[3:0,23)` heading island with signature
  `cfaa6057d09a575946490500e8165af1e0486d4738ea0925eb968e74084147b8`
  instead of full heading membership `2,3` / signature
  `9e9aa12b00f7fe863647bb51d4f2a07c3dd4f8747bc1cf0bc8afd80ebe19951b`.
  Split source 7, repeated source 8, and section-heading source 16 retain the
  same membership/signature as their same-layout full references and pass.

The first target failure (target 0, requests `[0,3)→[3,20)`) illustrates the
same root behavior: full heading card `2,3` becomes separate source-2 and
source-3 heading cards. Across every red case, diagnostics include first card,
reference/actual source and display ranges, section/logical owner,
`ReaderCardIdentity`, raw/visible text, neighboring cards, and complete gap,
overlap, duplicate, and out-of-range lists. No red scenario had missing,
duplicated, overlapping, reordered, or outside source coverage; the observed
failures are changed physical boundaries, separately flushed membership,
visible grouping, structural-owner range lists, and identities.

### Structural invariants that pass separately

Six full, target-first, forward-first, backward/prepend-first, and both
section-heading singleton orders pass the independently authored source
contract. They prove complete ordered source 0–19 coverage; distinct nav
logical blocks; chapter/subsection/second-section heading ownership; distinct
source/logical identities for repeated sources 8 and 18; both ordered-list
items and their list metadata; table source 11 with decoded visible text
`Column Value North Seven`; bold/italic metadata and visible content; nav link
and footnote-reference content; and the chapter-one 15 → chapter-two 16 → 17
spine seam. These passes do not make physical-card equality green.

### First-run test-only correction

The first structural run failed all six cases because the new assertion
expected the noteref at source 13 in `BookChunk.links`. Current production
represents that authored footnote-style link in `BookChunk.footnotes`; nav
links remain in `links`. The assertion was corrected to inspect the actual
production metadata owner and a separate nav-link assertion was retained.
No expectation was lowered, no production/fixture file changed, and the next
run passed 6/6. The first scoped analyzer also reported one style-only
unnecessary-braces info (exit 0); it was corrected before final analysis.

### Exact focused commands and results

The scoped Dart file list used by both format and analyze was
`test/reader_contract/pagination/reader_card_pagination_evidence.dart test/reader_contract/pagination/reader_core_pagination_harness.dart test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart test/reader_contract/support/reader_contract_layout_environment.dart`.
The exact command forms were:

```text
rtk dart format <scoped Dart file list above>
rtk dart analyze <scoped Dart file list above>
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart --reporter expanded
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart --reporter compact
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart --reporter compact
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart --reporter json
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart --reporter json
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart --name 'merge-long-repeat-boundaries forward-first' --reporter compact
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart --reporter json
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart --reporter compact
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_parity_test.dart --reporter compact
```

The forward/backward JSON command ran twice, the singleton JSON command ran
three times, and format, analyze, and the P03-001 command each ran once before
and once after the changes. All other listed forms ran once.

| Command | Result | Duration | Exit |
| --- | --- | ---: | ---: |
| Pre-edit `rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart --reporter compact` | 1 passed; original full-range baseline retained | 5.01 s | 0 |
| Initial scoped `rtk dart format` over the seven changed/new Dart files | 7 files, 6 changed | 0.09 s | 0 |
| Initial scoped `rtk dart analyze` over those seven files | One style info, no error | 2.45 s | 0 |
| Initial `rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart --reporter expanded` | 0/6 due solely to the new metadata-owner assertion described above | 4.40 s | 1 |
| Corrected structural command with `--reporter compact` | 6 passed | 4.21 s | 0 |
| Target-first command with compact reporter, then identical command with JSON reporter | Both runs: 3 passed, 12 failed; deterministic scenario set | 4.79 s; 4.85 s | 1; 1 |
| Forward/backward command with JSON reporter, repeated after adding split diagnostics | Both runs: 8 passed, 2 failed; deterministic scenario set; four split ranges printed | 4.59 s; 4.64 s | 1; 1 |
| Focused merge-plan command using `--name 'merge-long-repeat-boundaries forward-first' --reporter compact` | 0 passed, 1 failed with full seam/identity/coverage diagnostics | 4.19 s | 1 |
| Singleton command with JSON reporter, repeated twice after final diagnostics | Every run: 6 passed, 4 failed; deterministic scenario set and membership/identity classifications | 4.60 s; 4.54 s; 4.67 s | 1; 1; 1 |
| Final scoped `rtk dart format` over the seven Dart files | 7 files, 1 changed | 0.09 s | 0 |
| Final scoped `rtk dart analyze` over the seven Dart files | No issues | 1.76 s | 0 |
| Final P03-001 full-range and P02 parity commands, run separately in parallel | P03-001: 1 passed; P02 parity: 4 passed | 4.78 s; 4.64 s | 0; 0 |

No full-suite, cache-order, device, emulator, integration-device, network,
dependency-resolution, generator, schema, migration, staging, commit, reset,
clean, restore, revert, or discard command ran.

### Tracker corrections, behavior impact, and remaining work

The current plan header now records that work has started, the architecture map
names `ReaderCardPaginator.paginate` as sole kernel and ReaderScreen as its
delegate, and this ledger's current phase summary records P03 in progress.
Historical statements inside `CHANGE-20260829-007/008` were not rewritten.

Runtime behavior is unchanged. The red files merely expose current
request-local packing/tail behavior; the passing cases are also recorded and
were not forced red. No construction-order result was promoted to a canonical
physical-card oracle. `TASK-P03-005` must next characterize cold/warm/evicted
cache order without altering these tests. `TASK-P03-007` then creates the
complete formal failure ledger after all P03 comparisons exist. P04 must not
start before that authorized work; current predecessor continuation,
request-tail finalization, and generated-heading/seam repair remain P04 scope.

### Commit/reference

No commit was created. No Git stage, commit, reset, clean, restore, revert or
discard command ran. All unrelated dirty/untracked work remains untouched.

## CHANGE-20260831-010 — Complete P03 cache-order characterization and failure ledger

- Date/time: 2026-08-31 14:55:41 IST (Asia/Kolkata).
- Ordered completion: `TASK-P03-005`, then `TASK-P03-007` after all twelve
  cache results existed. P03 is `COMPLETED` at 7/7; overall progress is 24/89;
  P03 exit and P04 entry criteria are met; P04 remains entirely unstarted.
- Requirements characterized but not product-verified: `REQ-007`, `REQ-008`,
  `REQ-009`, `REQ-011`, `REQ-012`, `REQ-013`, `REQ-027`, `REQ-028`,
  `REQ-032`, `REQ-033`, `REQ-034`, `REQ-048`, and `REQ-051`.
- Incorporated evidence: the two detailed current evidence sections above
  record production cache symbols/roots and compatibility/lifecycle semantics,
  all created/modified files, storage isolation, the two exact partition
  plans, twelve state outcomes, first-run harness correction, exact commands/
  durations/exits, 23 ledger rows and P04/P06 ownership.

Real sandbox-owned `DisplaySectionMemoryCache`,
`SegmentedDisplayCacheService`, production cache keys/records and
`ProgressiveDisplayState` were exercised under standard Lexend. Seven states
pass. Five merge/long/repeat states—cold segmented, warm memory, warm disk,
production eviction/disk fallback and fresh-service reload—fail only at their
ordinary equality assertions after proven hits/eviction/persisted reload. Each
replays the source-4 island at card 2 with changed ranges/grouping/identity and
complete ordered source coverage.

`test/reader_contract/pagination/p03_failure_ledger.dart` contains 23 rows:
12 target, two forward/prepend, four singleton and five cache failures. The
three-test integrity file is green. Individual behavioral files reproduce
12/2/4/5 red scenarios with ledger-matching IDs and divergences; structural
ownership 6/6, P03-001 1/1 and P02 parity 4/4 remain green.

No production/runtime, fixture/oracle, dependency, lockfile, schema, cache
format, version, persistent signature or P02 parity expectation changed. No
full suite, device/emulator/integration-device, network, default cache clear or
Git mutation ran. P02 remains core complete 7/8 with P02-004 deferred, and
unrelated dirty/untracked work remains untouched.

## CHANGE-20260831-011 — Specify canonical pagination state machine

- Date/time: 2026-08-31 18:18:36 IST (Asia/Kolkata).
- Task completed: `TASK-P04-001` only.
- Requirements designed but not product-verified: `REQ-007`–`REQ-013`,
  `REQ-027`–`REQ-028`, `REQ-040`, `REQ-044`–`REQ-045`, `REQ-048`, and
  `REQ-051`.
- Design artifact:
  `docs/development/nalori-canonical-pagination-design.md`.
- Status after this entry: P03 remains `COMPLETED` at 7/7; P04 is
  `IN_PROGRESS` at 1/8; overall progress is 25/89. `TASK-P04-002` through
  `TASK-P04-008` remain unchecked and unstarted. No requirement dashboard row
  is promoted to verified.

### Evidence inspected

The following were read completely before the design was written:

- `docs/development/nalori-reader-reliability-plan.md`;
- this change log, including `CHANGE-20260829-007` through
  `CHANGE-20260831-010`;
- `docs/development/nalori-test-suite-audit.md`;
- `test/reader_contract/README.md`;
- every P03 paginator test, pagination/cache evidence harness, the full-range
  characterization and frozen P02 paginator parity baseline;
- `test/reader_contract/pagination/p03_failure_ledger.dart` and its integrity
  test;
- `lib/services/reader_card_paginator.dart`,
  `lib/services/progressive_display_state.dart`, `lib/models/book_chunk.dart`,
  `lib/models/reader_checkpoint.dart`,
  `lib/utils/final_layout_paragraphs.dart`,
  `lib/utils/reader_list_layout.dart`, and supporting list/text-boundary
  models;
- ReaderScreen's `_rebuildDisplayChunks` paginator adapter,
  `_prepareProgressiveDisplayRange`, cache-load/write, `publishInitial`,
  append/prepend, `_applyProgressiveDisplayState`, lazy forward/backward
  integration, eviction reconciliation, and generated-milestone paths;
- current `DisplaySectionMemoryCache`, `SegmentedDisplayCacheService` key,
  manifest, record, payload and compatibility identities, plus
  `DisplayGenerationSignature`.

### Current-kernel facts extracted

`ReaderCardPaginator.paginate` currently creates request-local
`newDisplayChunks`, `newDisplayToOriginal`, `newOriginalToDisplay`,
`textHeightCache`, `pending`, `pendingOriginals`, `inspectedSourceChunks`, and
`consumedEndExclusive`. It splits text by sentence/clause/word/grapheme and
tables by row; merge/finalization decisions consume chunk type, section,
source file/ranges, heading/dialogue/block role, publisher layout/whitespace,
logical paragraph offsets, text boundaries, list semantics/fragments,
links/styles/footnotes, measured height, tiny classification and presentation
compatibility. Source consumption completes only after every deterministic
subchunk is processed.

The final unconditional `flush` is request-end behavior. It can also merge a
tiny `pending` tail backward into `newDisplayChunks.last`. Therefore the
smallest unpublished canonical frontier is not one pending card: it is at
most a `deferredPredecessor` plus `pendingTail`. The display maps and text
height cache are transient projection/optimization, not continuation
authority. Current cancellation returns no partial cards. Current progressive
append/prepend proves range adjacency only, while memory/disk caches store and
replay range-local cards/maps without canonical continuation evidence.

### Chosen contract

A canonical card is final only after the immediate ordered atomic successor,
trusted structural boundary, or trusted section/book end proves that direct
merge, every eligible sentence rebalance, and tiny-tail backward attachment
can no longer change membership. Height or request exhaustion alone is never
proof. A budget end returns finalized prefix plus the two-card provisional
frontier in continuation; it does not create an identity for that frontier.

Safe restarts are publication start, a verified cross-section hard reset, or
a validated chained continuation/finalized boundary containing sufficient
frontier and next-cursor evidence. A target source index, random lazy-window
start, cache segment start, display index, controller index, or `_currentPage`
projection is not a restart. Target generation moves forward from the nearest
valid predecessor checkpoint. Backward preparation also regenerates forward,
reproduces the committed card, validates exact previous/current/next cursors
and identities, and prepends only after transactional seam acceptance.

The immutable continuation fields are contract kind, publication/book
fingerprint, parser/source snapshot identity, pagination algorithm identity,
controlled layout identity, spine/section identity, exact next stable source
cursor, reconstructable deferred/pending stable source slices, structural and
chosen split/list/table state, previous finalized boundary, chain ordinal and
parent digest, integrity digest, and terminal evidence. Every field has a
stable authority, validation rule, bounded representation and forbidden
alternative in the design table. It copies zero UTF-16 text and contains no
display/window/controller indexes, rendered widgets, complete card arrays,
`BuildContext`, mutable screen state, or cache-file authority. The structure
is deterministically serializable for P04 in-memory tests; P06 alone decides
persistent format, compatibility, migration, invalidation and version values.

Append/prepend outcomes are typed: accepted extension, incompatible
continuation, stale generation, seam gap, seam overlap, committed-card
mismatch, published-prefix mismatch, published-suffix mismatch, structural
ownership mismatch, and required regeneration from an earlier restart. Every
rejection leaves published cards and maps unchanged.

### Bounds and failure ownership

Bounds derive from current ReaderScreen lazy constants: initial lazy
lookbehind/lookahead/minimum `8/39/48`, non-lazy minimum `96`, and adjacent
source request `192`. A checkpoint is emitted at the first of 48 fully
consumed sources or eight finalized cards, plus section boundaries. The
active source/card ceilings are 432 sources and 96 cards. With
`L = ceil(max(card budgets) / minimum positive line-box height)`, the
coalesced two-card frontier cap is `U = 2L + 1`: 61 entries for the P03
standard 680 px/23.4 px-line layout and seven for the 58 px split-stress
layout. Normal target/backward work is at most 110 source/fragment entries;
one-checkpoint recovery is at most 158. Normal/recovery target discard limits
are seven/fifteen cards. Resident continuation records are capped at 25 per
active loaded publication window. Continuations copy zero text. Cancellation
checks occur no less frequently than one source/subchunk/token, two table
rows, 12 graphemes, or four sentence/rebalance candidates, plus scheduler and
publication checks.

All 23 formal failure IDs are mapped one-for-one: 12 target, two
forward/prepend, four singleton and five cache rows. P04 owns canonical
construction for every row. `P03-CACHE-001` is repaired by canonical cold
segmented construction in P04; cache rows 002–005 are P04-primary construction
failures whose persistent replay compatibility/migration remains P06. The six
already-green structural cases and source-7 split ranges are explicit
regression protections; no parser/source/structure repair is proposed.

### Implementation slicing recommendation

`TASK-P04-002`, `TASK-P04-005`, `TASK-P04-007`, and final evidence task
`TASK-P04-008` should run alone. `TASK-P04-003` and `TASK-P04-004` should also
default to separate turns, but may be grouped if the continuation types and
their first forward consumer cannot form a compiling intermediate; their
evidence must still be recorded separately. `TASK-P04-006` is a separate
structural-owner slice after P04-002 and must not be hidden in the final test
gate. Every task has expected symbols, tests, prohibited neighbors and an
independent rollback boundary in the design.

### Structural validation and scope

Read-only command forms used during discovery/validation included:

```text
rtk git status --short
rtk sed -n <scoped ranges> <required document/source/test>
rtk rg -n <scoped symbol/pattern> <required document/source/test paths>
rtk rg -c "id: 'P03-(TARGET|FORWARD|PREPEND|SINGLETON|CACHE)-[0-9]{3}'" test/reader_contract/pagination/p03_failure_ledger.dart
rtk rg -c '^\| `P03-(TARGET|FORWARD|PREPEND|SINGLETON|CACHE)-[0-9]{3}`' docs/development/nalori-canonical-pagination-design.md
rtk rg -c '^- \[x\] TASK-' docs/development/nalori-reader-reliability-plan.md
rtk rg -n 'TASK-P04-00[1-8]|P04 — Canonical pagination|Overall: 25 of 89|P03 — Construction-order characterization' docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md
rtk git diff --check -- docs/development/nalori-canonical-pagination-design.md docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md
rtk git diff --no-index --check /dev/null docs/development/nalori-canonical-pagination-design.md
rtk git status --short -- docs/development/nalori-canonical-pagination-design.md docs/development/nalori-reader-reliability-plan.md docs/development/nalori-reader-reliability-change-log.md lib test
```

The ledger and design failure-row counts were both 23; plan checked-task count
is 25; P04 has exactly one checked task and P03 remains 7/7. Keyword/table
inspection confirmed distinct request-budget/logical-end/finalizable states,
stable authority and validation for every continuation field, numeric target
and backward bounds, typed immutable-publication rejection paths, and the
P06-only persistence boundary. Both tracked and new-design whitespace checks
emitted no whitespace diagnostic; the no-index command's nonzero status only
records that the new file differs from `/dev/null`. Git status still shows the
substantial pre-existing modified/untracked production/test baseline captured
before this task; every write operation in this turn targeted only the three
authorized documentation paths.

Only the new design and the two authorized tracking Markdown files were
intentionally written. No production Dart, test, fixture, dependency,
lockfile, schema, cache/checkpoint/pagination/layout version, P02 parity
expectation, or P03 failure/oracle changed. No Flutter test, Dart/Flutter
analyzer, formatter, generator, migration, device/emulator/integration-device,
network, staging, commit, reset, clean, restore, revert, or discard command
ran. No technical blocker remains for beginning `TASK-P04-002`.

## CHANGE-20260902-012 — Implement immutable canonical forward paginator kernel

- Date/time: 2026-09-02 19:40:46 IST (Asia/Kolkata).
- Task completed: `TASK-P04-002` only. `TASK-P04-003` through
  `TASK-P04-008` were not executed.
- Status after this entry: P03 remains `COMPLETED` at 7/7; P04 is
  `IN_PROGRESS` at 2/8; overall progress is 26/89. No requirement dashboard
  row is promoted to verified.
- Production files changed:
  `lib/models/canonical_pagination.dart` (new) and
  `lib/services/reader_card_paginator.dart`.
- Trusted-test/documentation files changed:
  `test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart`
  (new), `test/reader_contract/README.md`, and
  `docs/development/nalori-reader-reliability-plan.md`, plus this append-only
  entry.

### Mandatory intermediate boundary and production model

Pre-edit review found no rule capable of mutating an earlier third card. The
existing rebalance affected only its pending head/tail, and legacy terminal
attachment affected only the last emitted predecessor plus pending tail, so
the approved two-card frontier assumption remains valid. One private engine
now owns all splitting, measured merging, sentence rebalance, table-row split,
frontier transition and finalization logic. There is no second canonical
algorithm.

`ReaderCardPaginator.paginateCanonical` drives that engine through
`CanonicalPaginationRequest` and `CanonicalPaginationOperationControls`.
`ReaderScreen` remains intentionally unwired to canonical continuation state:
its existing `paginate` call is a narrow compatibility adapter that pins its
input, delegates to the same engine and alone requests explicit legacy
request-end terminal treatment. The adapter contains no split/merge/rebalance
copy, is not canonical restart authority, and is assigned for conversion or
removal by `TASK-P04-004`. Frozen P02 output remains unchanged.

`CanonicalPaginationSourceSnapshot.pin` stores canonical serialized immutable
source records and proves exact publication/book identity, parser/source
identity, source revision, ordered source count, stable unique owner paired
with a validated ordinal hint, spine/section identity, per-source digest and
whole-snapshot digest. Replacement of the caller list or mutation of nested
caller-owned metadata cannot alter resolution. Visible text, display indexes,
controller state, window indexes and cache paths are not authority.

The new immutable state types include stable source keys/owners, cursors and
source slices; `CanonicalPaginationFrontierCandidate` and the two-card
`CanonicalPaginationFrontier`; normal/recovery work envelopes, budgets and
diagnostics; publication-start and trusted-section restarts; explicitly
provisional process-local `P04ProvisionalPaginationRestart`; stable target
cursors; finalized cards; and sealed accepted/rejected outcome families.
Typed outcomes distinguish finalized output, logical end, budget exhaustion
with provisional frontier, target finalization, cancelled/stale rejection,
invalid restart/source rejection and frontier-bound violation. The provisional
restart is not serialized or chained and is not the P04-003 continuation
contract.

### Finalization, frontier, identity and bounds

The canonical terminal policy never flushes at request/work exhaustion. A card
becomes final only after its immediate successor, a hard structural boundary,
or trusted snapshot logical end proves that direct merge, measured failure,
eligible sentence rebalance and tiny-tail backward attachment cannot change
membership. A height-filled candidate still consumes successor proof. Budget
exhaustion returns only a finalized prefix, a reconstructable unpublished
`deferredPredecessor`/`pendingTail` frontier and the next stable text/table-row
cursor. Frontier descriptors contain stable ranges/row intervals and
structural digests, not copied source text or display projections.

`ReaderCardIdentity` is constructed only while mapping a privately finalized
engine card into a canonical accepted result. Frontier candidates have no
identity. Repeated visible text keeps distinct stable owners; split table cards
use stable source row intervals; no visible-text/display-index or parsed-
content fallback identity was added. Existing pagination signature/version
formats were not changed.

The kernel records source chunks entered, atomic fragments, referenced UTF-16
extent, table rows, grapheme candidates, rebalance candidates, finalized and
privately discarded predecessor cards, current/peak frontier entries,
estimated peak private/frontier descriptor bytes, cancellation checkpoints and
scheduler slices/yields. It defines the approved 48-source/eight-card stride,
432-source/96-card active ceilings, 61/7 standard/split frontier caps, 110/158
normal/recovery work envelopes and 25-record resident basis. P04-002 directly
enforces request source/card ceilings, the selected normal/recovery atomic-work
envelope and `U = 2L + 1` (or a stricter caller cap); checkpoint-record and
publication-retention limits remain declared for their later owning tasks. A
frontier breach returns a typed rejection and discards all private output.

Cancellation checks cover before source work, each source/atomic fragment,
splitting tokens, every two table rows, every 12 graphemes, every four
rebalance candidates, before/after finalization and before result assembly.
Stale generation uses operation controls only and is not canonical identity.
All cancellation/stale/invalid/bound rejections expose zero publishable cards,
no accepted restart authority and no cache-write authority.

### Automated evidence

Commands used the repository-required `rtk` prefix. Final focused results:

| Command/scope | Result | Exit |
| --- | --- | ---: |
| Scoped `rtk dart format` over the two production Dart files and new P04 test; final `rtk bash -lc 'DART_SUPPRESS_ANALYTICS=true /home/uttam/Desktop/Code/flutter/bin/cache/dart-sdk/bin/dart analyze ...'` over the same files | Formatted; analyzer reported no issues | 0 |
| `rtk flutter test test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart` | 18 passed: immutable snapshot/restart, trusted section start, typed request/logical end/target outcomes, two-card transitions, direct/hard/measured/tiny/rebalance rules, exclusions, bounds, all cancellation/stale points, structure/source-7/table rows and repeat determinism | 0 |
| Combined new P04 + P02 parity + P03 ledger-integrity command | 25 passed (18 + 4 + 3) | 0 |
| P02 parity + P03 full-range + P03 structural-ownership command | 11 passed (4 + 1 + 6); no baseline or source-range expectation changed | 0 |
| P03 target-first behavioral file | 3 passed, expected 12 failed | 1 |
| P03 forward/backward behavioral file | 8 passed, expected 2 failed; split-stress source 7 remained `[0,58)`, `[58,125)`, `[125,191)`, `[191,198)` | 1 |
| P03 singleton behavioral file | 6 passed, expected 4 failed | 1 |
| P03 cache-order behavioral file | 7 passed, expected 5 failed | 1 |

The 23 ordinary P03 equality failures remain exactly the approved
12/2/4/5 ledger set. They were neither skipped nor inverted and their
expectations were not modified. Making them green still requires chained
continuations (`TASK-P04-003`), ReaderScreen initial/target/forward consumption
(`TASK-P04-004`), backward regeneration (`TASK-P04-005`), final structural
canonicalization (`TASK-P04-006`), transactional progressive publication
(`TASK-P04-007`) and the all-P03 gate (`TASK-P04-008`).

One combined post-documentation check using the `rtk dart` wrapper attempted
to refresh read-only Flutter SDK engine stamp/realm files and emitted two
read-only filesystem diagnostics; it was not accepted as analyzer evidence and
changed no workspace file. A direct SDK analyzer invocation under the required
`rtk` prefix first reported no issues but then hit a read-only telemetry-session
mtime update; the final analytics-suppressed command above completed cleanly.

No cache record, cache key, schema, migration, package dependency, lockfile,
checkpoint/pagination/layout version, ReaderScreen consumption path,
`ProgressiveDisplayState`, P02/P03 expectation, fixture, or unrelated source
was changed. No device/emulator/integration-device, generator, deployment,
Git staging/commit/reset/clean/restore/revert/discard, cache clear or persistent
storage command ran. Existing unrelated dirty/untracked work remains untouched.

## CHANGE-20260905-013 — Implement canonical in-memory continuation checkpoints

- Date/time: 2026-09-05 01:24:39 IST (Asia/Kolkata).
- Task completed: `TASK-P04-003` only. `TASK-P04-004` through
  `TASK-P04-008` were not executed.
- Status after this entry: P03 remains `COMPLETED` at 7/7; P04 is
  `IN_PROGRESS` at 3/8; overall progress is 27/89. No requirement dashboard
  row is promoted to verified.
- Production files changed: `lib/models/canonical_pagination.dart`,
  `lib/models/canonical_pagination_checkpoint_index.dart` (new), and
  `lib/services/reader_card_paginator.dart`.
- Trusted-test/documentation files changed:
  `test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart`
  (new),
  `test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart`,
  `test/reader_contract/README.md`,
  `docs/development/nalori-canonical-pagination-design.md`, and
  `docs/development/nalori-reader-reliability-plan.md`, plus this append-only
  entry.

### Final continuation, key, codec, and chain

`P04ProvisionalPaginationRestart` was removed. The canonical API now accepts
only publication start, a proved trusted section start, or the sole final
`CanonicalPaginationContinuation`. Every accepted canonical outcome,
including logical end, carries that continuation; the temporary legacy
`paginate` adapter still delegates to the same kernel and has no continuation
authority.

`CanonicalPaginationContinuationKey` contains only book/publication
fingerprint, parser/source identity, source revision and pinned snapshot
digest, pagination algorithm identity, controlled layout identity, stable
section identity, and the exact stable boundary cursor. Publication fields are
validated against the request/open publication and reject as
`incompatiblePublication`; parser/revision/snapshot fields validate against
the pinned source and reject as `incompatibleParserSourceSnapshot`;
pagination/layout identities require exact request matches and reject as
`incompatiblePaginationIdentity` or `incompatibleLayout`; section/owner and
cursor evidence must resolve uniquely and reject as
`invalidSectionSourceOwner` or `invalidCursorOffsetRowInterval`. No raw range,
source count, display/window/controller index, cache key, generation ID, or
runtime identity is key authority.

`CanonicalPaginationContinuationCodec` uses the existing sorted canonical
JSON encoder and SHA-256 helper. It requires exact root and nested field sets,
explicit enum names, integer/bool/string types, exact null presence, ordered
lists, nonempty identities, valid interval pairs, and byte-for-byte canonical
input. Missing, unknown, duplicate/noncanonical, malformed, and unsupported
records cannot acquire permissive defaults. The integrity digest covers every
payload field except itself. Nested finalized-card identity JSON is also
strictly validated and its signature recomputed.

The continuation carries the exact start/next cursor, deferred predecessor and
pending tail descriptors, ordered source slices, structural/split/list/table/
publisher/rich-metadata evidence, previous finalized boundary and identity,
chain ordinal, parent digest, cadence reason/counters, and terminal evidence.
It carries exactly zero copied UTF-16 source text. Each non-root resume requires
the exact canonical parent digest, next ordinal, compatible nonterminal parent,
and parent-next/child-start continuity. The in-memory index additionally
rejects regression, replay, and stale forks relative to its active chain. All
rejections expose no publishable cards, accepted restart authority,
cache-write authority, or partially inserted checkpoint.

### Exact reconstruction and implementation refinement

Before any continuation is resumed, stable cursor/section/source/spine owners,
source digests, ordered nonoverlapping UTF-16/table-row intervals, grapheme
boundaries, structural/list/table/publisher/rich metadata, selected split
state, frontier card digest, and previous finalized-card identity/end cursor
are re-derived from `CanonicalPaginationSourceSnapshot`. Both frontier cards
are rebuilt through the existing production split/table/merge kernel and
remeasured/classified there; stored evidence cannot override production
logic. Failure of any slice or candidate rejects the entire continuation.

Production-path testing found one precise refinement, not a contradiction of
the approved two-card continuation assumption: `buildSplitChunk` can produce
different structural flags/metadata for an explicitly split fragment whose
range is the whole `[0, source.length)` interval. A single
`usesExplicitTextFragment` boolean is therefore canonical validation evidence
so reconstruction chooses the same production path. It does not store source
text and does not change persistent card/table identity. Table row intervals
remain explicitly provisional continuation evidence pending `TASK-P04-006`;
`ReaderCardIdentity` and persistent schemas were not changed.

### Cadence and bounded index

Checkpoint cadence is carried from the previously accepted checkpoint across
smaller requests. The paginator stops at whichever occurs first: 48 fully
consumed source chunks or eight finalized cards. It also emits at trusted
section end/start seams and terminal book end. A request budget may return a
nonterminal `requestExhaustedProvisional` continuation below both cadence
limits and never labels request exhaustion as logical end. Codec validation
rejects a reason/counter contradiction.

`CanonicalPaginationCheckpointIndex` is the minimum process-local collection
for one active loaded publication window. It accepts only an already accepted
canonical result, verifies integrity and all stable compatible key fields,
deduplicates the active digest, rejects replay of an older resident digest,
orders deterministically by stable cursor/ordinal/digest, and retains at most
25 records. Its transactional insertion protects
the prefix seam guard, active suffix and exact parent, all resident section-
boundary records, and the active resume frontier. If those protections cannot
fit, insertion returns typed `boundViolation` without changing the index; a
missing required digest returns `requiredEarlierRestart`.

### Automated evidence

All commands used the repository-required `rtk` prefix.

| Command/scope | Result | Exit |
| --- | --- | ---: |
| Scoped `rtk dart format`; analytics-suppressed direct SDK `dart analyze` over the three production and two P04 test files | Formatted; analyzer reported no issues | 0 |
| Combined P04 canonical state-machine and continuation/checkpoint files | 30 passed: 18 existing P04-002 plus 12 new P04-003 production-path tests | 0 |
| Combined P02 parity, P03 full-range, P03 structural ownership, and P03 ledger integrity | 14 passed (4 + 1 + 6 + 3) | 0 |
| P03 target-first behavioral file | 3 passed, expected 12 failed | 1 |
| P03 forward/backward behavioral file | 8 passed, expected 2 failed | 1 |
| P03 singleton behavioral file | 6 passed, expected 4 failed | 1 |
| P03 cache-order behavioral file | 7 passed, expected 5 failed | 1 |

The 23 ordinary P03 equality failures remain exactly the approved 12/2/4/5
set. Their test expectations, failure ledger, oracle, source ranges, and
classifications were unchanged. The production cause is also unchanged:
ReaderScreen still consumes independently packed legacy range results, so the
new internal continuation chain is not yet a screen publication authority.

No `ReaderScreen`, `ProgressiveDisplayState`, durable `ReaderCheckpoint`,
memory/disk display cache, segmented manifest, SQLite, restoration,
dependency, lockfile, schema, cache key, cache format, or pagination/layout/
checkpoint version behavior was intentionally changed. No device/emulator/
integration-device, network, deployment, cache clear, persistent-store, or Git
mutation command ran. Existing unrelated dirty/untracked work remains
untouched. `TASK-P04-004` remains the first production-screen consumer;
`TASK-P04-005` through `TASK-P04-008` retain backward regeneration, final
structural ownership, transactional publication, and all-P03 green ownership.

## CHANGE-20260906-014 — Integrate bounded canonical initial, target, and forward generation

- Date/time: 2026-09-06 16:30:45 IST (Asia/Kolkata).
- Task completed: `TASK-P04-004` only. `TASK-P04-005` through
  `TASK-P04-008` remain unstarted.
- Status after this entry: P03 remains `COMPLETED` at 7/7; P04 is
  `IN_PROGRESS` at 4/8; overall progress is 28/89. No requirement dashboard
  row is promoted to verified before the complete P04 gate.
- Production files changed: `lib/models/canonical_pagination.dart`,
  `lib/models/canonical_pagination_checkpoint_index.dart`,
  `lib/services/reader_card_paginator.dart`,
  `lib/services/progressive_display_state.dart`, and
  `lib/screens/reader_screen.dart`.
- Trusted-test/documentation files changed:
  `test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart`
  (new),
  `test/reader_contract/pagination/reader_core_pagination_harness.dart`,
  `test/reader_contract/pagination/reader_core_cache_order_harness.dart`,
  `test/reader_contract/pagination/reader_card_paginator_parity_test.dart`,
  `test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart`,
  `test/reader_contract/README.md`,
  `docs/development/nalori-reader-reliability-plan.md`, and this append-only
  entry.

### Mandatory pre-edit boundary audit

Every call path from `ReaderScreen._rebuildDisplayChunks` into the paginator
was traced before editing:

- the direct initial request is initial publication;
- initial requests carrying a nonzero stable owner/offset and later explicit
  target requests are stable target-first preparation;
- non-backward progressive range requests after publication are forward
  expansion;
- backward progressive requests, including retry/boundary preparation, are
  backward/prepend preparation;
- the detached chapter-range builder is background compatibility-only and
  does not publish into the live reader; cache-hit branches do not invoke the
  paginator.

The first three paths can consume finalized canonical cards through the
existing `publishInitial`/`append` calls without changing their mutation
semantics. Backward remains behind a separate guarded compatibility function,
so no P04-005 regeneration was needed. Canonical cards can be passed to the
existing publication layer without claiming atomic seam validation, so no
P04-007 mutation change was needed. No dependency contradiction required a
scope expansion.

### Restart selection, bounded work, and typed outcomes

`CanonicalReaderPaginationSession` is the smallest production orchestration
boundary. One instance is scoped to a pinned book/publication/parser/source
snapshot and explicit controlled layout/pagination identity, owns one bounded
25-record `CanonicalPaginationCheckpointIndex`, and records only outcomes
accepted after cancellation/staleness checks. A new book, source revision,
snapshot digest, layout, or pagination identity creates an incompatible
session/index; rejected outcomes expose no cards, cache-write authority, or
accepted restart authority.

Initial work accepts only publication start, a proved trusted section start,
or a compatible validated continuation. Target work resolves stable
source/section ownership plus UTF-16 offset against the pinned snapshot,
selects the nearest predecessor at or before the target, and permits exactly
one earlier resident checkpoint when the nearest cannot be forked or resumed.
It never starts at a nearby target ordinal. It regenerates forward until the
unique containing card is finalized, returns exact card/slice/offset evidence,
and discards private predecessor cards only after their frontier effect is
consumed. Forward work accepts only the session's current suffix continuation
after the actual last published card JSON, ordered source owners, finalized
identity, and end cursor match. It emits only later finalized cards and never
replaces the accepted prefix.

Normal target/forward work retains the approved 110 atomic source/fragment
envelope and seven-card private predecessor limit; the one-checkpoint recovery
selects 158 and fifteen. The existing 48-source/eight-card cadence,
61/7 frontier caps and 25-record index bound are unchanged. Accepted path
results now expose the total bounded work consumed. Request exhaustion returns
`CanonicalReaderProvisionalBudgetExhaustion` with a nonterminal continuation;
only its finalized prefix, if any, is publishable. Its unpublished frontier is
never converted to `DisplayRangeResult`, and an empty provisional result is
not treated as logical end.

Typed ReaderScreen handling covers finalized output, logical end, provisional
budget exhaustion, required-earlier restart, cancellation/staleness, invalid
continuation/source, and exact-suffix mismatch. Target offsets are carried on
the request only to resolve the stable source owner; display/window/controller
and mutable range indexes are not restart or target authority. Existing
controller settlement, checkpoint persistence, and restoration policy are
unchanged.

### ReaderScreen and legacy/cache disposition

ReaderScreen initial, stable-target, and forward generation now call only the
canonical session. Legacy segmented `DisplayRangeResult` records contain no
canonical continuation and therefore cannot seed those operations; their
formats, keys, storage, migration, and services were not changed, and P06
retains compatibility ownership. The existing backward cache path is
unchanged.

The shared legacy entry is explicitly named `paginateLegacyForP02`. Its
remaining production call site is inside one function that rejects every
direction except backward and is assigned to `TASK-P04-005`. The frozen P02
extraction test and historical full-range P03 reference remain executable
through the same adapter, but it has no ReaderScreen initial, target, or
forward authority. It contains no second split/merge/rebalance algorithm.

`ProgressiveDisplayState` gained only the stable target text-offset request
field. `publishInitial`, `append`, and `prepend` mutation semantics were not
changed; no transactional-seam claim is made before `TASK-P04-007`.

### Automated evidence

All commands used the required `rtk` prefix. Final commands used `--no-pub`.
Durations below are command wall times reported by the runner.

| Command/scope | Duration | Result | Exit |
| --- | ---: | --- | ---: |
| Final scoped `rtk dart format` over ten changed Dart files | 0.56 s | 10 files checked; zero changed | 0 |
| Final scoped `rtk dart analyze` over the same production/test files | 2.56 s | No issues found | 0 |
| Combined P04 state-machine, continuation/checkpoint and new P04-004 path files | 13.39 s | 38 passed (18 + 12 + 8) | 0 |
| Final focused P04-004 production-path file | 4.76 s | 8 passed | 0 |
| P02 frozen extraction parity | 4.72 s | 4 passed; expected values unchanged | 0 |
| P03 full-range characterization/evidence | 4.73 s | 1 passed | 0 |
| P03 target-first matrix | 5.50 s | 15 passed, 0 failed | 0 |
| P03 forward/backward matrix | 5.23 s | 9 passed, 1 expected ordinary assertion failure (`P03-PREPEND-001`) | 1 |
| P03 singleton matrix | 5.26 s | 10 passed, 0 failed | 0 |
| P03 cache-order matrix | 6.06 s | 7 passed, 5 expected ordinary assertion failures (`P03-CACHE-001`–`005`) | 1 |
| P03 structural ownership | 4.89 s | 6 passed | 0 |
| P03 failure-ledger integrity | 3.60 s | 3 passed | 0 |

The first focused P04-004 invocation accidentally omitted `--no-pub`; Flutter
ran its resolver from the available environment, then the test reported six
passes and two focused assertion failures in 10.45 seconds (exit 1). Neither
`pubspec.yaml` nor `pubspec.lock` was touched (their mtimes remain
2026-08-29 and 2026-08-24 respectively). The failures exposed a test fixture's
actual evicted-checkpoint location and missing explicit ReaderScreen
provisional branch; both focused assertions were corrected without changing
dependencies or bounds. The final focused rerun passed 8/8 in 4.76 seconds,
and the combined P04 run above is the accepted inherited-contract evidence. An intermediate
scoped analyzer run found one test-helper callback type error plus lint-only
items; the final analyzer is clean.

The P04-004 repair turns green all twelve `P03-TARGET-001` through
`P03-TARGET-012` ledger rows, `P03-FORWARD-001`, and all four
`P03-SINGLETON-001` through `P03-SINGLETON-004` rows. Their approved equality
oracle, fixtures, source ranges, expected identities, IDs, and ledger entries
were not changed. Exact remaining red rows are:

- `P03-PREPEND-001`: one failure, owned by backward forward-regeneration in
  `TASK-P04-005`;
- `P03-CACHE-001`: one cold-segmented failure, owned by canonical
  publication/seam acceptance in `TASK-P04-007`;
- `P03-CACHE-002` through `P03-CACHE-005`: four warm/eviction/reload failures,
  owned by `TASK-P04-007` publication acceptance followed by P06 cache
  compatibility/replay.

All six expected-red failures are ordinary card-boundary/identity assertions
with complete gap-free source coverage. There were no compilation, setup,
font, parsing, cleanup, or unrelated failures. Split-stress source 7 remains
`[0,58)`, `[58,125)`, `[125,191)`, `[191,198)` and structural ownership stays
green.

Backward/prepend regeneration, final structural/table/generated-fragment
identity, transactional progressive publication, persistent cache behavior,
cache keys/formats/migration, continuation persistence, checkpoint/restoration
UX, schema/version constants, dependencies, and lockfiles were not changed by
this task. No full Flutter suite, device, emulator, integration-device,
deployment, cache-clear, persistent-store, or Git mutation command ran.

## CHANGE-20260906-015 — Implement bounded canonical backward regeneration

- Date/time: 2026-09-06 21:39:00 IST (Asia/Kolkata).
- Task completed: `TASK-P04-005` only. `TASK-P04-006` through
  `TASK-P04-008` remain unstarted.
- Status after this entry: P03 remains `COMPLETED` at 7/7; P04 is
  `IN_PROGRESS` at 5/8; overall progress is 29/89. No product-requirement
  dashboard row is promoted before the complete P04 gate.

### Mandatory pre-edit backward call-path audit

The audit traced `_rebuildDisplayChunks` into its generation-scoped paginator
closures, `_prepareProgressiveDisplayRange`, backward source-window and
section-boundary preparation, retry re-entry, `ProgressiveDisplayState.prepend`,
and `_applyProgressiveDisplayState` committed-anchor/controller rebasing. Every
live backward request, including retry and lazy section-boundary work, funnels
through `_prepareProgressiveDisplayRange`; before this change its guarded
backward-only closure was the sole ReaderScreen caller of
`paginateLegacyForP02`.

Ownership remained separable. P04-005 owns immutable restart selection,
forward-only private regeneration, committed-boundary validation, and typed
accepted/pending/rejected results. P04-007 still owns transaction protocol and
persistent seam records. P09 still owns adjacent-navigation intent, controller
settlement, and correction policy. The existing `ProgressiveDisplayState.prepend`
checks adjacency before its existing list mutations, so ReaderScreen can await
and validate the complete P04-005 result before calling it; no P04-007 or P09
dependency contradiction was found and its mutation semantics were not changed.

### Production implementation and validation

- `CanonicalPaginationCheckpointIndex.predecessorsBefore` returns at most the
  nearest two compatible checkpoints whose stable cursor is strictly before
  the desired predecessor. `CanonicalReaderPaginationSession.generateBackward`
  validates the immutable desired owner, accepted prefix, exact committed card,
  successor boundary, pinned publication/parser/source snapshot, layout and
  pagination identities, and current operation generation before work begins.
- The nearest valid checkpoint is tried first. Exactly one earlier attempt is
  permitted: the next earlier checkpoint, a compatible trusted section start,
  or publication start when that root is within the approved recovery bound.
  A missing or out-of-bound restart returns the existing typed
  required-earlier-regeneration outcome; no section or publication scan is
  unbounded.
- Each attempt forks the checkpoint index privately and calls only the real
  `ReaderCardPaginator.paginateCanonical` forward kernel. Source order is never
  reversed, no requested predecessor range is independently packed, and no
  right-to-left pagination exists. Only canonical finalized cards before the
  already accepted prefix can become the prepend payload.
- Acceptance requires exact canonical JSON equality for the complete
  `ReaderCardIdentity`/signature, `BookChunk` visible content and structural
  metadata, ordered stable source owners, section/spine identities,
  logical-block ownership, UTF-16/table-row slices, and split/continued flags.
  It also reproduces every accepted card from the published prefix through the
  committed/current card in order, proves predecessor-end = current-start and
  current-end = successor/accepted-continuation-start, and checks regenerated
  cards for gap-free, nonoverlapping cursor continuity.
- Normal work remains capped at 110 atomic source/fragment entries and seven
  retained predecessor cards; the sole recovery attempt remains capped at 158
  entries and fifteen cards. Regenerated private cards are capped at 10/18,
  operation iterations are finite, checkpoint retention remains 25 records,
  and the existing two-card frontier/checkpoint cadence is unchanged. Budget
  exhaustion returns typed pending continuation/diagnostics with no publishable
  predecessor, restart/cache-write authority, or visible mutation.
- Identity, source-slice, section/spine, cursor, compatibility, cancellation,
  and stale-generation disagreements return typed all-or-nothing rejection.
  Rejected/pending work does not alter the main checkpoint index, current card,
  display state, or controller anchor. Accepted output is passed to the existing
  `ProgressiveDisplayState.prepend`; the committed card is never returned for
  replacement or repacking.
- ReaderScreen's live backward/prepend path now uses the active snapshot- and
  layout-scoped canonical session. It has no `paginateLegacyForP02` call site.
  The named adapter remains only for frozen P02/historical reference evidence;
  it has no production ReaderScreen authority.

### Files changed

- Production: `lib/models/canonical_pagination_checkpoint_index.dart`,
  `lib/services/reader_card_paginator.dart`, and
  `lib/screens/reader_screen.dart`.
- Tests/evidence:
  `test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart`
  (new),
  `test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart`,
  `test/reader_contract/pagination/reader_core_pagination_harness.dart`, and
  `test/reader_contract/pagination/p03_failure_ledger.dart`.
- Tracking/contracts: `docs/development/nalori-reader-reliability-plan.md`,
  this change log, and `test/reader_contract/README.md`.
- `lib/services/progressive_display_state.dart` was audited but not changed by
  P04-005.

### Automated evidence

All commands used the required `rtk` prefix and test commands used `--no-pub`.
Durations are command wall times reported by the runner.

| Command/scope | Duration | Result | Exit |
| --- | ---: | --- | ---: |
| Final scoped `rtk dart format` over seven changed Dart files | 0.54 s | 7 files checked; 1 formatting-only change | 0 |
| Final scoped `rtk dart analyze` over the same production/test files | 1.98 s | No issues found | 0 |
| Combined P04 state-machine, continuation/checkpoint, initial/target/forward paths, and P04-005 backward preparation | 6.56 s | 48 passed (18 + 12 + 8 + 10) | 0 |
| Focused P04-005 backward preparation file | 5.20 s | 10 passed | 0 |
| P02 frozen extraction parity | 4.38 s | 4 passed | 0 |
| P03 full-range characterization | 4.28 s | 1 passed | 0 |
| P03 target-first matrix, final | 5.22 s | 15 passed | 0 |
| P03 forward/backward matrix, final | 4.91 s | 10 passed; `P03-PREPEND-001` green | 0 |
| P03 singleton matrix | 5.00 s | 10 passed | 0 |
| P03 structural ownership plus failure-ledger integrity | 4.66 s | 9 passed (6 + 3) | 0 |
| P03 cache-order matrix | 5.63 s | 7 passed; exactly 5 expected assertion failures (`P03-CACHE-001`–`005`) | 1 |
| Final ledger-summary format, analyze, and integrity rerun | 3.83 s | Format unchanged; analysis clean; 3 passed | 0 |

One intermediate target-first run ended in 5.38 seconds with 12 passes and
three bounded-retention rejections (exit 1). The production seven-card limit
was correct; the characterization harness had requested an entire late prefix
in one operation. It was corrected to issue consecutive legal four-source
lookup windows, each invoking the production canonical session, without
changing the oracle, expected identities, or production bounds. The final
15/15 result above is accepted evidence. Development-time focused P04 and
split-stress reruns also passed before the consolidated final commands; they
introduced no additional failure class.

`P03-PREPEND-001` is now green with `firstDivergence: null` and complete
ordered coverage with no gaps, overlaps, duplicates, or outside-source slices.
All target-first, forward-first, backward-first, singleton, and structural
rows are green. Split-stress source 7 remains exactly `[0,58)`, `[58,125)`,
`[125,191)`, `[191,198)`. The historical `P03-PREPEND-001` failure-ledger row
was neither deleted nor renumbered; a resolution-evidence summary was added.
The exact remaining red rows are `P03-CACHE-001`, `P03-CACHE-002`,
`P03-CACHE-003`, `P03-CACHE-004`, and `P03-CACHE-005` only.

Final structural ownership/identity (P04-006), transactional progressive
publication (P04-007), the final all-P03 green gate (P04-008), caches, cache
keys/formats/migration, persisted continuations, checkpoint/restoration
behavior, navigation/controller settlement, retry UX, schemas, versions,
dependencies, and lockfiles were not changed. No network, full Flutter suite,
device, emulator, integration-device, deployment, cache-clear, persistent-store,
or Git mutation command ran.

## CHANGE-20260907-016 — Finalize canonical structural ownership and card identity

- Date: 2026-09-07 (Asia/Kolkata)
- Task completed: `TASK-P04-006` only. `TASK-P04-007` and
  `TASK-P04-008` remain unstarted; no P05-or-later task was executed.
- Phase/status: P04 moved from 5/8 to 6/8 and overall progress from 29/89 to
  30/89. No product requirement was marked verified before the complete P04
  gate.
- Requirements supported, not yet verified: `REQ-007`, `REQ-008`, `REQ-011`,
  `REQ-012`, `REQ-013`, `REQ-027`, `REQ-028`, `REQ-040`, `REQ-048`, and
  `REQ-051`.

### Mandatory ownership audit

| Structure | Production symbol/path | Pre-change owner evidence | Stable? | Ambiguity/fallback found | P04-006 disposition |
| --- | --- | --- | --- | --- | --- |
| Parsed text and source headings | `EpubParserService` `flush`; `BookChunk.logicalParagraphId` | Source href, parser paragraph/list block ID, role, exact source text/rich offsets | Yes | None for parsed fixture text/headings | Retained and signed as `source:heading` or `source:<blockRole>` |
| Split/continued text | paginator `buildSplitChunk`, `ChunkSourceRange`, `rebuildFinalLayoutParagraphs` | Logical owner, paragraph-relative UTF-16 ranges, start/end flags | Mostly | Fragment digest included source/display ordinal fields; full-span split provenance could be collapsed while coalescing | Shared `buildCanonicalTextFragment`; exact adjacent ranges, clipped rich/list data, grapheme-safe boundaries and explicit full-span provenance are signed |
| Lists/navigation | parser list stack; `readerListDisplaySegmentsForSlice`; `BookListSemantics` | Stable list/item/parent IDs, ordinal/marker/depth/block order and fragment state | Yes | Canonical card identity previously did not sign list-fragment evidence | Signed list digest plus `source:list`, `source:navigation`, or explicit generated role; incompatible owners cannot merge |
| Tables | parser table owner; paginator table split map and frontier descriptors | Stable table logical owner; provisional continuation row interval | Incomplete | A full table could fall back to encoded-text UTF-16 identity, and row intervals were previously embedded provisionally in structural type | Every full/split table now owns `structuralType=table` plus exact half-open body-row interval; shared row reconstruction and decoded visible content validate it |
| Inline rich/link/footnote text | parser offsets; split helper | Source-relative bold/italic/link and footnote offsets | Yes in `BookChunk` | Canonical identity retained only a digest outside the final card range | Exact clipped fragment is rederived from pinned source and its rich digest is signed |
| Repeated prose | parser logical paragraph IDs plus source/section owner | Same text at distinct href/logical owners | Yes | Visible-text fallback existed in legacy `ReaderCardIdentity.fromCard` | Canonical builder requires stable source/logical owner; visible digest is validation only |
| Images/nontext | parser image bytes/source href; `BookChunkType.image` | Source href and bytes | No for images | Parser images lacked intrinsic source-reference logical owner; ordinal fallback was possible | Parser assigns deterministic href/image-occurrence/source-reference owner; canonical role is `source:image`, with content checksum only as validation |
| Generated title/navigation/milestone | `BookChunk` generated source conventions; deferred `_insertMilestoneCards` | Type/text, and deferred milestone display ratio/index | No | Generated owner could depend on display insertion and text hash | `generated:<role>` derives from explicit generated source namespace and stable publication/section-local logical owner; deferred milestone constructor now records publication+percentage owner |
| Section/spine seams | source keys, `readerChunksShareHardMergeBoundary`, canonical finalizer | Section/source-file evidence | Yes where parser identity existed | Final signer did not itself reject a cross-spine owner list | Canonical builder rejects any mixed section/spine card; same text across the seam remains distinct |
| Canonical frontier/continuation | `CanonicalPaginationSourceSlice`; continuation codec | Stable source/section/spine, UTF-16/row and structural digests | Partly | Final `ReaderCardSourceRange` collapsed most slice evidence; codec accepted only the earlier range shape | Complete canonical ownership set is mandatory, strictly encoded, integrity covered, source-reconstructed and rejected if partial/unknown/contradictory |
| Physical-card identity | `_finalizedCanonicalCard`; `ReaderCardIdentity.fromCard` | Canonical finalizer used a limited range; legacy projection could use source indexes then visible text | Canonical path incomplete | Two builders existed for different eras and the legacy projection remains live at the pre-P07 checkpoint/cache boundary | `CanonicalReaderCardIdentityBuilder` is the sole canonical finalization signer. `fromCard` remains unchanged for frozen P02 and deferred checkpoint/cache integration and is not canonical authority |
| Display cache records | whole/segmented cache DTOs and ReaderScreen cache load | `BookChunk` plus mutable display mappings | Not canonical | Records cannot carry the new accepted canonical identity/seam evidence | Audited only; unchanged and assigned to P04-007/P06, with no compatibility claim |

`BookChunk` construction/transformation sites in the parser, final-layout
paragraph rebuilder, list slicer, table slicer, paginator merge/split paths,
ReaderScreen's deferred milestone helper, canonical frontier and display-cache
DTO boundary were traced. Existing stable evidence was retained. No layout,
measurement, rendering, card membership, cache record, or progressive mutation
algorithm was rewritten.

### Final ownership and signature contract

- `CanonicalReaderCardIdentityBuilder` accepts only finalized ordered source
  slices. Each signature range includes source, section, spine and logical
  owner; structural type and explicit owner role; exact UTF-16 or table-row
  interval; structure, fragment, publisher-layout, rich-metadata and list
  digests; split boundary; paragraph start/end flags; and explicit-fragment
  provenance. Same-owner adjacent slices must meet exactly; owner order cannot
  reverse; a section/spine seam is a hard rejection.
- `canonicalBookChunkOwnershipDigest` removes `BookChunk.index` and
  `ChunkSourceRange.originalChunkIndex` before hashing. Those values remain
  validated lookup hints in the pinned snapshot but have no signature
  authority. Display/window/controller indexes are neither builder inputs nor
  accepted continuation fields.
- Text fragments use the shared production `buildCanonicalTextFragment`, which
  preserves exact half-open source ownership, paragraph continuation flags,
  grapheme-safe boundaries, publisher metadata, list state and clipped
  bold/italic/link/footnote offsets. Coalescing a deliberately split full-span
  fragment retains `usesExplicitTextFragment=true` without copying text.
- Source headings retain parser source/logical owners; complete ordered
  membership is signed when compatible headings share one card. Navigation and
  lists sign their list/item/order/marker/fragment evidence. Generated sources
  use explicit `generated:title`, `generated:navigation`, or
  `generated:milestone` roles instead of invocation/display order.
- Tables, including an unsplit full table, use one stable table owner and exact
  `[rowStart,rowEndExclusive)` body-row interval. Headers are structural
  context, fragments reconstruct through `buildCanonicalTableRowFragment`, and
  target containment maps stable offset zero to the first owned row. Encoded
  table visible content was decoded and checked in source order.
- Images use parser-stable `href#image-<source occurrence>:<source reference>`
  logical ownership. A separate per-resource image counter avoids changing
  existing paragraph owners. Image bytes validate content but do not replace
  the owner.

Canonical physical-card signatures intentionally changed because the old
canonical range was structurally ambiguous. The old ordered input was
`(section, source digest including ordinal fields, logical block, structural
type, UTF-16 range/content checksum)` and encoded table rows provisionally in
the type. The new ordered input preserves the exact same card membership and
source interval order while adding stable source/spine/role and the complete
structural evidence above, using ordinal-free source/fragment digests and
explicit table-row fields. Full-span split cards also change only where the old
identity lost their explicit split provenance. The precise responsible inputs
are `structuralOwnerRole`, ordinal-free `sourceDigest`/`fragmentDigest`, exact
row interval, structural/publisher/rich/list digests, paragraph flags and split
provenance. Visible text and complete source coverage are unchanged. Frozen P02
and P03 legacy projection signatures did not change.

The in-memory continuation keeps contract kind V1 and SHA-256 integrity but
now strictly requires the complete canonical card-range ownership set. Missing,
unknown, partial, malformed or contradictory fields reject. No copied source
text, persistent continuation, checkpoint/cache version, schema or migration
was introduced.

### Files changed

- Production: `lib/models/reader_checkpoint.dart`,
  `lib/models/canonical_pagination.dart`,
  `lib/services/reader_card_paginator.dart`, `lib/services/epub_parser.dart`,
  and `lib/screens/reader_screen.dart`.
- Tests/support:
  `test/reader_contract/pagination/reader_card_paginator_structural_identity_test.dart`
  (new),
  `test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart`,
  `test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart`,
  and `test/reader_contract/pagination/reader_core_pagination_harness.dart`.
- Tracking/contracts: `docs/development/nalori-reader-reliability-plan.md`,
  this change log, and `test/reader_contract/README.md`.

### Automated and manual evidence

All final focused test commands used `--no-pub`. Durations are command wall
times reported by the runner.

| Command/scope | Duration | Result | Exit |
| --- | ---: | --- | ---: |
| `rtk dart format` plus scoped `rtk dart analyze` over nine P04-006 production/test Dart files, final | 4.06 s | 9 formatted, 0 changed; no issues | 0 |
| Combined P04 state-machine, continuation/checkpoint, initial/target/forward, backward, and P04-006 structural identity files, final | 15.65 s | 55 passed (18 + 12 + 8 + 10 + 7) | 0 |
| Post-ledger scoped format/analyze plus P04-006 structural identity file | 7.59 s | Format unchanged; no analysis issues; 7 passed, including ordinal-digest independence | 0 |
| P02 frozen paginator parity | 4.45 s | 4 passed | 0 |
| Trusted fixture/parser source regression | 3.92 s | 5 passed | 0 |
| P03 full-range characterization | 4.23 s | 1 passed | 0 |
| P03 target-first matrix, final | 5.64 s | 15 passed | 0 |
| P03 forward/backward matrix, final | 5.08 s | 10 passed | 0 |
| P03 singleton matrix, final | 5.11 s | 10 passed | 0 |
| P03 structural ownership, final | 4.59 s | 6 passed | 0 |
| P03 failure-ledger integrity | 3.11 s | 3 passed | 0 |
| P03 cache-order matrix | 5.42 s | 7 passed; exactly 5 expected ordinary assertion failures | 1 |
| Final scoped `git diff --check` plus tracker-count assertions | 0.20 s | No tracked whitespace error; 30 checked tasks, exactly P04-007/008 unchecked in P04, one `CHANGE-20260907-016`, current P03 summary names five failures | 0 |

Development-time failures were retained as evidence rather than hidden:

- The first state-machine run (5.50 s, exit 1) passed 16 and failed 2 because
  strict decoding initially treated optional table-row keys as universally
  required; the codec was corrected to require them as an exact pair only for
  tables.
- The first P04-006 test run (5.09 s, exit 1) passed 5 and failed 2. One test
  compared a multi-source merged card's aggregate rich metadata to a single
  source instead of using the production fragment helper; the other exposed
  missing full-span split provenance during coalescing. The test was corrected
  to validate source-local offsets and the production coalescer was fixed.
- The first combined P03 run (6.82 s, exit 1) passed 40 and failed 2:
  `P03-TARGET-008` and backward structural seed. Exact table-row ownership had
  revealed that stable targets handled only UTF-16 slices. Production target
  containment was extended to exact table/nontext ownership; isolated reruns
  passed 2/2 in 9.58 s, and all final matrices above passed.
- One early state-machine command accidentally omitted `--no-pub` (5.50 s,
  exit 1); Flutter printed dependency resolution/“Downloading packages”. No
  dependency declaration or lockfile was edited by this task, but this command
  is not claimed as no-network evidence. Every subsequent Flutter command used
  `--no-pub`.

Manual source-range review confirmed all 20 fixture sources remain ordered,
gap-free, nonoverlapping and complete at their authored extents. Split-stress
source 7 remains exactly `[0,58)`, `[58,125)`, `[125,191)`, `[191,198)`.
Headings, navigation, lists, decoded table content, rich inline offsets,
repeated prose and the chapter-one/chapter-two seam retain visible text and
membership. The fixture, XHTML, relational oracle and expected identities were
not modified.

All non-cache P03 rows remain green; no new oracle row was changed by P04-006.
`P03-PREPEND-001` remains green from `CHANGE-20260906-015`. The exact remaining
red rows are `P03-CACHE-001`, `P03-CACHE-002`, `P03-CACHE-003`,
`P03-CACHE-004`, and `P03-CACHE-005` only. The historical ledger rows were not
deleted or renumbered.

The prospective phase summary was corrected from six remaining failures to
five and now names the five cache rows plus the P04-005 resolution entry. The
historical P04-004 entry was not rewritten. `RISK-014` remains open: P04-005
mitigates canonical predecessor generation, while P09 still owes integrated
navigation/controller proof.

Transactional progressive publication, `ProgressiveDisplayState` mutation
semantics, cache implementations/keys/records/formats/migration, persistence,
checkpoint/restoration behavior, measurement/layout/rendering, schemas,
versions, dependencies and lockfiles were unchanged. No device, emulator,
integration-device or full Flutter-suite test ran. No Git stage, commit, reset,
clean, restore, revert or discard command ran.

## CHANGE-20260907-017 — Add transactional canonical display publication

- Date: 2026-09-07 (Asia/Kolkata)
- Task completed: `TASK-P04-007` only. `TASK-P04-008` remains unstarted; no
  P05-or-later task was executed.
- Phase/status: P04 moved from 6/8 to 7/8 and overall progress from 30/89 to
  31/89. Product requirements remain unverified until the final P04 gate.
- Requirements supported, not yet verified: `REQ-007`–`REQ-013`, `REQ-027`,
  `REQ-028`, `REQ-040`, `REQ-048`, and `REQ-051`.

### Mandatory pre-edit publication-writer audit

| Operation | Caller | Input authority | State mutated before P04-007 | Mutation timing | Rollback behavior before P04-007 | Canonical evidence present before P04-007 | Required correction / final disposition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Initial publication | ReaderScreen `_rebuildDisplayChunksAsync`; chapter background generation; `ProgressiveDisplayState.publishInitial` | A `DisplayRangeResult` plus source-index range | `ranges`, display cards, both source/display maps, ready/completion flags | Lists/maps were cleared and filled immediately | None if a later identity/anchor check failed | Range adjacency only; legacy cards could be request-tail finalized | Live production now calls `publishCanonical(initial)` with accepted canonical result and continuation; the legacy method remains only for frozen P02/P03 characterization helpers |
| Target/window publication | ReaderScreen initial target branch and later target range | Target source/display indexes plus range result | Same fields as initial; later screen maps/controller target | Target/display indexes could become publication authority | Screen-level restoration only after mutation | Target card finalization existed in the paginator, but ProgressiveDisplayState did not verify exact containment | `publishCanonical(initial/replacement)` requires exact target-containment evidence; target display index is derived only after candidate acceptance |
| Forward append | `_prepareProgressiveDisplayRange`; `ProgressiveDisplayState.append` | Adjacent `SourceChunkRange` and new display cards | Appended card/mapping lists, reverse map and range | Incremental `addAll`/map updates before complete seam validation | None | Only integer range adjacency; no physical-card boundary or immutable-suffix proof | Shared transaction requires accepted predecessor continuation, exact previous finalized boundary, cursor equality and unchanged published prefix; repeated exact output is typed idempotent |
| Backward prepend | `_prepareProgressiveDisplayRange`; `ProgressiveDisplayState.prepend` | Adjacent range and regenerated predecessors | Inserted cards/maps, shifted reverse indexes/ranges, controller rebase later | Incremental list insertion and index shifting | None | P04-005 generated overlap evidence, but state accepted only source-range adjacency | Shared transaction proves regenerated prefix/current equality and predecessor/current/successor cursors, preserves the suffix/committed identity, then rebases derived indexes privately |
| Canonical paginator acceptance | `CanonicalReaderPaginationSession.generateInitial/Target/Forward/Backward` | Pinned snapshot, controlled layout, validated restart and generation controls | Checkpoint index, accepted continuation/suffix and accepted-card ledger | Session accepted before display publication | No display-coupled rollback | Complete paginator evidence | ReaderScreen sessions use `deferPublicationCommit`; private post-result state is retained pending display acceptance, committed only after the transaction, or discarded on rejection |
| Whole display-cache hit | `_loadOrRebuildDisplayChunksAsync`; `BookCacheService.loadDisplayChunks` | Persistent `CachedDisplayChunks` | Screen cards/maps and published source ownership | Direct mutation preceded a late anchor check | Manual mutate-then-restore branch | No canonical identity, continuation or seam authority | Real record is read and logged, typed `canonicalRegenerationRequired` is emitted, and direct publication code is removed; canonical source regeneration follows |
| Segmented cache hit | `_loadProgressiveSegmentsAroundSource`; `SegmentedDisplayCacheService.loadAroundSource` | Center/before/after records and integer adjacency | Progressive state initial/prepend/append plus screen application | Center published before adjacent records and anchor checks | No transaction-wide rollback | Record/layout/range checks only | Real records are read and logged, direct publication is rejected, and the function returns a canonical miss; no legacy card reaches live state |
| Memory cache replay | `_cacheProgressiveDisplayRange` / `DisplaySectionMemoryCache`; cache-order production harness | Process-local `DisplayRangeResult` | Previously could feed the same legacy append path | On each replayed range | None across multiple ranges | No canonical continuation/identity | Read/hit remains observable; typed rejection precedes bounded canonical regeneration. Existing writer is retained unused for P06 and cannot grant publication authority |
| Disk reload/fresh service | Segmented service manifest/record loading | Existing format-v3 record bytes | Same segmented path | Per record | Service corruption handling only | No canonical seam evidence | Fresh-service bytes are proved readable, then rejected identically and regenerated; format/version is unchanged |
| Eviction/fallback | `_tryReconcileLazySourceWindowForEviction`, memory eviction then disk fallback | Stable-key remap plus legacy displayed cards | Source window, remapped progressive state, visible/controller indexes | Source/display replacement happened before a late legacy signature check | Could return false after partial mutation | Display/window indexes and legacy `ReaderCardIdentity.fromCard` acted as seam authority | Direct remap publication is removed. A typed canonical-regeneration requirement is logged before mutation and production falls back to source-window rebuild |
| Lazy source prepend | `_integrateLazyBackwardSection`; `shiftSourceIndexes` | Newly inserted source window indexes | Ranges, maps and every card source index | Live index shift before regeneration | None | Display index only | Incremental shifting is unavailable for a canonical-authority state; canonical sessions regenerate against a newly pinned source snapshot |
| Screen application | `_applyProgressiveDisplayState` | Accepted ProgressiveDisplayState plus stable visible/committed anchor | Screen cards/maps, published source maps, completion flags and later controller indexes | Previously mutated all screen collections before resolving anchor, then restored copies | Explicit mutate-then-undo | Legacy visible signature and stable source lookup | Candidate legacy projection and stable-anchor index are resolved before any live screen mutation; application runs only after typed canonical acceptance |
| Source/display maps | `publishInitial`, `append`, `prepend`, `_applyProgressiveDisplayState`, `_publishCurrentSourceOwnership` | Card-to-source arrays and reverse map | Lists/maps on state and screen | Independently/incrementally | Partial restore only in screen application | Source indexes could substitute for ownership | Transaction derives both maps and ranges solely from accepted canonical source slices, validates the complete candidate, and swaps all state fields together |
| Cache write/checkpoint/settlement | whole cache writer, deferred session commit, navigation completion | Generation token and previously complete display | Persistent cache or in-memory checkpoint/settlement authority | Could follow a display result without a state-level canonical acceptance | Stale `shouldWrite` checks only | Generation compatibility but not publication transaction | Accepted results alone expose cache/checkpoint/settlement authority; rejected results expose empty cards/null continuation/false authority. Whole-cache writing additionally requires state canonical authority |
| Retry, cancellation and stale generation | canonical operation controls; `_prepareProgressiveDisplayRange`; rebuild-generation branches | Generation tokens/cancellation callbacks | Session/state/screen depending on where cancellation arrived | Some session state was accepted before screen stale checks | No coupled session/display rollback | Paginator typed cancellation/stale result | Generation/cancellation is checked before validation and again at the final commit boundary; deferred session state is rejected and the accepted display snapshot stays byte-equivalent |

The audit found every prohibited pattern named by the task: incremental list
and map mutation, range-only adjacency, legacy cached islands, provisional
request-tail publication, mutate-then-undo screen application, display-index
seam authority, and eviction paths able to return failure after mutation. The
final production path removes or isolates each one without changing a
persistent cache record or P05 layout behavior.

### Transaction and seam contract

- `CanonicalDisplayPublicationRequest` carries operation, session/generation,
  pinned source snapshot, controlled layout and pagination identity, finalized
  cards/continuation, predecessor or backward overlap evidence, exact target
  containment, stable committed card, cancellation and current-generation
  callbacks.
- `ProgressiveDisplayState.publishCanonical` is the one shared validation and
  commit path for initial, append, prepend and replacement. It validates every
  canonical identity by rebuilding it with
  `CanonicalReaderCardIdentityBuilder`, checks pinned source owners/digests,
  exact UTF-16/table-row intervals and source boundaries, full ordered
  coverage, duplicates/reordering/cross-section ownership, continuation
  integrity, target containment, committed-card presence and resident bounds.
- Append proves the prior continuation owns the unchanged accepted suffix, its
  next cursor exactly equals the first new physical boundary, and the result
  continuation owns the last new card. Prepend proves regenerated prefix and
  committed cards exactly equal accepted cards, predecessor-end equals
  current-start, current-end equals successor-start, and the incoming
  predecessor end meets the unchanged published prefix. Replacement derives
  target and committed indexes only after identity resolution.
- Cards, ranges, display-to-source map, reverse map, canonical ledger,
  continuation and rebased target/committed indexes are constructed privately.
  Cancellation/generation are rechecked at the commit boundary, then complete
  prepared references are swapped once. Exceptions and typed rejections make
  no live mutation; there is no mutate-then-undo path.
- Outcome kinds are: accepted initial/append/prepend/replacement; idempotent
  already applied; provisional rejected; stale generation/session;
  incompatible publication/source/layout/pagination; missing/invalid
  continuation; seam gap/overlap; duplicated/reordered/cross-section ownership;
  published-card mismatch; committed-card mismatch; bound violation;
  cancellation before commit; validation error; and canonical regeneration
  required. Rejections expose no publishable cards, continuation, cache-write
  authority or checkpoint/settlement authority.

### Cache fail-closed evidence

The P03 cache harness still uses the real `BookCacheService`,
`SegmentedDisplayCacheService`, `DisplaySectionMemoryCache`, record conversion,
disk serialization/reload, production memory eviction and disk fallback, fresh
service instances, `ReaderContractSandbox`, canonical session and
`ProgressiveDisplayState`. Each noncanonical record is first observed as a
hit, then rejected with `canonicalRegenerationRequired`, after which bounded
canonical source regeneration publishes the accepted nine-card sequence with
cache-write authority. Complete visible text, source intervals, structural
owners, canonical signatures and section/spine seams match the approved cold
sequence. `P03-CACHE-001` through `P03-CACHE-005` now report
`firstDivergence:null`; all five historical ledger rows remain present and
renumbering/deletion was not performed.

### Files changed

- Production: `lib/models/canonical_pagination_checkpoint_index.dart`,
  `lib/services/reader_card_paginator.dart`,
  `lib/services/progressive_display_state.dart`, and
  `lib/screens/reader_screen.dart`.
- Tests/evidence:
  `test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart`
  (new), `reader_core_pagination_harness.dart`,
  `reader_core_cache_order_harness.dart`,
  `reader_card_paginator_cache_order_test.dart`, `p03_failure_ledger.dart`, and
  `p03_failure_ledger_integrity_test.dart` in the same directory.
- Tracking/contracts: `docs/development/nalori-reader-reliability-plan.md`,
  this change log, and `test/reader_contract/README.md`.

### Automated evidence

All shell commands used the required `rtk` prefix. Every Flutter command used
`--no-pub`. Durations are command wall times reported by the runner.

| Exact command | Duration | Result | Exit |
| --- | ---: | --- | ---: |
| `rtk dart format lib/models/canonical_pagination_checkpoint_index.dart lib/services/reader_card_paginator.dart lib/services/progressive_display_state.dart lib/screens/reader_screen.dart test/reader_contract/pagination/reader_core_pagination_harness.dart test/reader_contract/pagination/reader_core_cache_order_harness.dart test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/p03_failure_ledger.dart test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart && rtk dart analyze lib/models/canonical_pagination_checkpoint_index.dart lib/services/reader_card_paginator.dart lib/services/progressive_display_state.dart lib/screens/reader_screen.dart test/reader_contract/pagination/reader_core_pagination_harness.dart test/reader_contract/pagination/reader_core_cache_order_harness.dart test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/p03_failure_ledger.dart test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart` | 3.1 s | Format: 10 files, 0 changed; analysis: no issues | 0 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart test/reader_contract/pagination/reader_card_paginator_structural_identity_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart` | 6.5 s | 62 passed: prior P04 state-machine/continuation/initial-target-forward/backward/structural plus 7 focused transactional tests | 0 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart` | 8.3 s | 57 passed: full range 1/1, target-first 15/15, forward/backward 10/10, singleton 10/10, structural 6/6, cache 12/12, ledger 3/3 | 0 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_parity_test.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart` | 4.5 s | 9 passed: frozen P02 parity 4/4 and fixture/parser contract 5/5 | 0 |
| Final production-only `rtk dart format lib/screens/reader_screen.dart && rtk dart analyze lib/models/canonical_pagination_checkpoint_index.dart lib/services/reader_card_paginator.dart lib/services/progressive_display_state.dart lib/screens/reader_screen.dart` | 3.0 s | Format unchanged; no analysis issues | 0 |

Development-time focused evidence is retained: the first new transaction run
ended in 5.1 s with 5 pass/2 fail (exit 1), exposing missing committed-card
validation on idempotent replacement and a test assumption about an
inter-card split seam. The next run ended in 5.4 s with 6 pass/1 fail (exit 1),
confirming the production fix and leaving only that fixture assumption. The
test then derived gap/overlap candidates from a real canonical source slice;
the final focused run passed 7/7 in 5.0 s (exit 0). The focused cache-order
matrix passed 12/12 in 6.3 s (exit 0). A pre-final combined P04 run passed
62/62 in 7.6 s (exit 0), and a pre-final complete P03 run passed 57/57 in
8.7 s (exit 0).

The full-range evidence is unchanged. Split-stress source 7 remains exactly
`[0,58)`, `[58,125)`, `[125,191)`, `[191,198)`. No P03 behavioral row remains
red. `TASK-P04-008` remains the sole P04 blocker because its randomized and
bounded retained-state final sign-off was explicitly outside this task.

The P03 equality oracle, fixture source, expected membership, source ranges
and legacy signatures were unchanged. Cache records, fields, keys, formats,
migration/invalidation policy and versions were unchanged; no continuation
was persisted. Checkpoint/restoration persistence, settlement/navigation UX,
measurement/rendering/P05 layout, schemas, dependency declarations and
lockfiles were unchanged. No network, full Flutter suite, device, emulator or
integration-device test ran. No Git stage, commit, reset, clean, restore,
revert or discard command ran.

## CHANGE-20260908-018 — Record P04 canonical pagination final-gate failure

- Date: 2026-09-08 (Asia/Kolkata)
- Task attempted: `TASK-P04-008` only. It remains incomplete; no P05-or-later
  task was executed.
- Phase/status: P04 remains `IN_PROGRESS` at 7/8 and overall progress remains
  31/89. P04 exit criteria and P05 entry criteria are not met.
- Requirements: no status changed. `REQ-007`, `REQ-008`, `REQ-010`,
  `REQ-011`, `REQ-012`, `REQ-013`, and `REQ-048` remain `NOT_STARTED` because
  the complete final gate did not pass. Later-phase requirements remain
  unverified.

### Scope and preserved failure

One evidence-only test was added at
`test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart`.
It uses the real fixture parser/source snapshot, canonical paginator/session,
continuation index, canonical identity builder,
`ProgressiveDisplayState.publishCanonical`, isolated real cache services and
the controlled Lexend layout. Production, fixtures, authored oracles, existing
comparisons and historical failure IDs were not modified.

The deterministic seeds are `40400801` through `40400812`: ten legal fixture
construction plans and two isolated cache-order plans. Seed `40400801` is
publication-start construction. Seeds `40400802`–`40400810` cover target-first
forward/backward, backward/forward, singleton expansion in both orders, table,
rich text, section restart, repeated text and section-seam targets. Seeds
`40400811` and `40400812` cover warm-memory and fresh-service reload hits
followed by required canonical regeneration. Every seed regenerates its legal
partition plan with `dart:math Random(seed)`; no wall-clock randomness or
invalid-as-equivalence scenario is used.

The fixture gate completed only publication-start. These nine legal seeds
failed at canonical publication boundaries: `40400802`, `40400803`,
`40400804`, `40400805`, `40400806`, `40400807`, `40400808`, `40400809`, and
`40400810`. The first divergence is reproducible with seed `40400802` and plan
`{"firstSourceBudget":15,"kind":"targetForwardBackward","partitions":["[0,7)","[7,10)","[10,12)","[12,14)","[14,18)","[18,20)"],"seed":40400802,"target":2}`.
Target-first publication accepts the heading card owning sources 2 `[0,20)`
and 3 `[0,23)` with identity
`5b39a5af2e05256bd8ee8ace915221e831fd9b77259971fd5855dfad57ee5613`.
Its continuation
`3248ec4b966545575fbd124de126758e49a580cc5060ead1c5b138129420704c`
names source 5 as `nextSourceCursor`, while the next real canonical card starts
at source 4 and owns sources 4–7. Append returns
`CanonicalDisplayPublicationOutcomeKind.seamOverlap` with “Canonical seam
cursors do not meet exactly.” The complete pre-state digest is
`97db0f16bf9c1d53f9ca0facd5bc98f52890c166d31fc24cc8ccdb4d49efcd9a`;
accepted state remains unchanged. The owning production boundary is append
seam validation in `lib/services/progressive_display_state.dart` against the
accepted continuation/frontier boundary. No repair was attempted.

The distant-target proof constructs 320 transparent test-only `BookChunk`
sources in three synthetic sections, advances with an eight-source operation
budget and targets source 280. Operation 0 accepts sources `[0,8)`, consumes
eight atomic entries, publishes one finalized card, retains two frontier
candidates with a peak of six coalesced entries, and returns provisional
continuation
`e598f32be6061b6aec17c38b2516057348c26bbdfe5e4eff824accf80e1cce81`.
Operation 1 rejects it with
`CanonicalPaginationRejectionReason.invalidFrontier`: “Provisional frontier
could not be reconstructed exactly.” The owning boundary is provisional
frontier reconstruction/resume in `lib/services/reader_card_paginator.dart`.
The target is never published, no single operation paginates the book, and no
accepted display state mutates. Checkpoint eviction, display replacement,
earlier-record regeneration and cumulative cancellability cannot be claimed
because traversal stops at operation 1.

The isolated cache seeds pass and prove only P04 fail-closed behavior: real
warm-memory and fresh-service hits are observed, rejected as direct authority,
and regenerated into the reviewed sequence. This is not P06 compatible cache
reuse or migration evidence.

### Determinism, bounds and retained-state evidence

The complete randomized/bounded file ran three separate times without a code
or state change between runs. Each produced the same plans, first failing seed,
distant continuation/rejection, `1 passed / 2 failed / 0 skipped` count and
exit 1. Final-file durations were 4.96 s, 4.97 s and 4.88 s. This proves deterministic
failure, not canonical equivalence or P04 exit.

Before the fixture gate stopped, accepted completed-plan maxima were 14 atomic
entries, zero discarded private predecessors, zero frontier candidates at
completed continuations, six peak frontier entries, three continuation
records, nine resident display cards and zero copied source text. The accepted
synthetic operation observed eight atomic entries, two frontier candidates,
six frontier entries, one continuation record and one published card. These
observations are within their local ceilings, but the failure prevents final
proof of the 110/158 work, 7/15 predecessor, 25-record, 432-source and 96-card
limits over long traversal. The existing 62-test P04 suite continues to pass
its focused bounds, cadence, rejection and mutation-invariance assertions;
those scenarios do not substitute for the failed final gate.

### Automated evidence

All Flutter commands used `--no-pub`; all shell commands used `rtk`. Durations
are command wall times. No skipped test was reported.

| Exact command | Duration | Result | Exit |
| --- | ---: | --- | ---: |
| `rtk dart format test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart && rtk dart analyze test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart` | 1.72 s final | 1 file unchanged; no issues | 0 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart` | 4.96 s | repeat 1: 1 passed, 2 failed, 0 skipped | 1 |
| Same exact randomized/bounded gate command | 4.97 s | repeat 2: 1 passed, 2 failed, 0 skipped | 1 |
| Same exact randomized/bounded gate command | 4.88 s | repeat 3: 1 passed, 2 failed, 0 skipped | 1 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart --plain-name 'real memory and fresh-service cache hits fail closed then regenerate identically'` | 4.67 s | 1 passed, 0 failed, 0 skipped | 0 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart --plain-name 'ten legal fixture plans repeat exact canonical cards, chains, work, and retained state'` | 4.69 s | 0 passed, 1 failed, 0 skipped; failure seeds `40400802`–`40400810` | 1 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart --plain-name 'distant target advances cumulatively, evicts checkpoints, and replaces display state within bounds'` | 4.31 s final | 0 passed, 1 failed, 0 skipped at operation 1 | 1 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart test/reader_contract/pagination/reader_card_paginator_structural_identity_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart` | 7.63 s final | 63 passed, 2 failed, 0 skipped; all 62 pre-existing P04 tests green | 1 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart` | 7.83 s | unchanged P03 matrix: 57 passed, 0 failed, 0 skipped | 0 |
| `rtk flutter test --no-pub --reporter compact test/reader_contract/pagination/reader_card_paginator_parity_test.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart` | 4.18 s | P02 parity 4/4 and fixture/parser 5/5; 9 passed | 0 |

An earlier cache-only invocation remained running after 30 seconds because
test-owned file I/O was not inside `WidgetTester.runAsync`; it was terminated
and is `INDETERMINATE`, not evidence. The test-only harness was corrected and
the final cache command passed. One mistyped P03 command named five
nonexistent files and ended after 5.93 s with 18 unrelated passes and five load
errors; it is excluded from the 57/57 result. Neither involved production.

### Manual source-range review

The fixture, XHTML and authored source oracle are unchanged.

| Review target | Confirmed evidence |
| --- | --- |
| First and final source | Source 0 starts card 0 at `[0,20)`; source 19 ends card 8 at `[0,55)` |
| Every standard physical seam | Cards remain `0–1`, `2–3`, `4–7`, `8`, `9–10`, table source `11`, `12–15`, `16`, `17–19`, in order |
| Split source 7 | Split-stress remains `[0,58)`, `[58,125)`, `[125,191)`, `[191,198)`; standard layout owns `[0,198)` |
| Repeated prose | Sources 8 and 18 retain distinct source/logical owners despite identical marker text |
| Source/generated headings | TOC/generated sources 0–1, chapter headings 2–3 and second-section heading 16 retain distinct owners |
| Lists | Sources 9 `[0,19)` and 10 `[0,18)` remain ordered list-owned ranges |
| Decoded table | Source 11 retains authored UTF-16 `[0,136)` and canonical body-row `[0,1)`; decoded order is `Column Value North Seven` |
| Inline/link/footnote | Sources 12 `[0,56)`, 13 `[0,50)`, 14 `[0,37)`, 15 `[0,63)` retain rich/link/footnote owners and text |
| Chapter seam | Source 15 ends chapter one, source 16 owns the next heading card, and source 17 starts chapter-two prose gap-free |
| Final tail | Card 8 remains sources 17 `[0,52)`, 18 `[0,33)`, 19 `[0,55)` |

Agreement among failing paths was not used to bless membership. The successful
publication-start plan equals the reviewed nine-card sequence. Unchanged P03
and P02 controls confirm no oracle, expected membership, range, failure ID or
legacy signature changed.

### Requirement, risk and phase audit

No requirement was promoted. `REQ-009`, `REQ-027`, `REQ-028`, `REQ-040`,
`REQ-044`, `REQ-045`, and `REQ-051` retain their later-phase gaps; lifecycle,
restoration, persistence, navigation, final layout and compatible-cache reuse
remain unverified.

`RISK-001`, `RISK-002` and `RISK-003` remain open with the new failure
evidence. `RISK-004` is mitigated by green P03/P04 structural ownership but
still needs P09 heading-adjacency navigation. `RISK-007` is mitigated by P04
fail-closed regeneration but remains P06 work for compatible reuse/migration.
`RISK-014` remains open for P09 navigation/controller proof. No P04-related
risk is resolved by this gate.

The prospective summary was corrected before applying the result: P04 was 7/8
with `CHANGE-20260907-017` latest, and unchanged P03 was 57/57 green rather
than five cache failures open. The resulting summary names this entry as the
latest P04 evidence while retaining 7/8 and 31/89. P02-004 remains deferred.

A separately authorized corrective task should reconcile target-first
continuation frontier/seam authority in `ProgressiveDisplayState` and exact
provisional-frontier reconstruction in `ReaderCardPaginator`, then rerun this
unchanged gate. Only after P04 passes should the first bounded P05 scope be
`TASK-P05-001`, the field-by-field measurement/render/fingerprint inventory,
without changing layout behavior.

No production file, cache format, persistent schema/version, dependency or
lockfile changed. No network, generator, migration, full Flutter suite,
device, emulator or integration-device test ran. No Git mutation command ran.

## CHANGE-20260908-019 — Correct canonical frontier seam and restart reconstruction

- Date: 2026-09-08 (Asia/Kolkata)
- Scope: bounded correction within the already approved `TASK-P04-003`,
  `TASK-P04-004` and `TASK-P04-007` contracts. No task ID was added or
  completed. `TASK-P04-008` remains incomplete.
- Status: P04 remains `IN_PROGRESS` at 7/8 and overall progress remains 31/89.
  P04 exit and P05 entry criteria remain unmet.
- Requirements: no status changed or was promoted.

### Reproduction and root cause

Both `CHANGE-20260908-018` failures were reproduced unchanged before editing.
Seed `40400802` accepted the target card owning sources 2–3. Its last published
card ended at source 4; `previousFinalizedBoundary.endCursor` and the earliest
unpublished frontier cursor were source 4; `nextSourceCursor` was source 5;
and the next finalized card started at source 4 and owned sources 4–7.
`ProgressiveDisplayState._buildCanonicalCandidate` nevertheless compared that
incoming start with `predecessor.nextSourceCursor`, incorrectly substituting
the next-unconsumed input cursor for the physical publication seam and
returning `seamOverlap`. Genuine gap/overlap classification itself was not
weakened.

The 320-source reproduction accepted operation 0 with one finalized card, two
frontier candidates, a peak of six coalesced frontier entries, eight atomic
entries and continuation
`e598f32be6061b6aec17c38b2516057348c26bbdfe5e4eff824accf80e1cce81`;
operation 1 then returned `invalidFrontier`. Every stable source slice and its
source/section/spine/logical owner, structural role, explicit-fragment flag,
paragraph flags, publisher-layout digest, rich/list digests and UTF-16 extent
rederived exactly. The first mismatch was the candidate digest. The runtime
deferred candidate used transient chunk index 0, retained a synthesized
trailing `\n\n`, logical end offset 195 and structural/sentence boundaries at
193/195; snapshot reconstruction started at stable source index 3 and had no
unowned trailing separator. The runtime pending candidate likewise used index
0 while reconstruction used stable source index 6. Full `BookChunk.toJson()`
digests therefore differed even where owned source evidence matched. The
builder measured/classified an unnormalized rebalance candidate while resume
remeasured the snapshot-normalized candidate.

### Correction and invariants

Append validation now compares the first newly finalized card with
`predecessor.previousFinalizedBoundary.endCursor`. Thus the published suffix
end, accepted previous-finalized/frontier boundary and incoming card start
must meet exactly at the same stable cursor. A nonempty frontier may begin
there while `nextSourceCursor` remains later because input has already been
consumed into provisional candidates. Empty-frontier behavior and strict gap,
overlap, duplicate and reorder rejection remain unchanged; no new continuation
field or schema/version was introduced.

The paginator now normalizes each kernel frontier candidate from its ordered
stable source slices before measurement/classification and before encoding.
The same reconstruction path resolves each owner against the pinned snapshot,
checks grapheme/table bounds, rebuilds text/table fragments with the production
helpers, preserves the recorded trailing split kind and explicit full-span
provenance, regenerates all source-slice evidence and compares it byte-exactly.
Candidate integrity uses `canonicalBookChunkOwnershipDigest`, excluding only
transient chunk/range ordinal hints; corruption and incompatible snapshots
still reject. Continuations copy zero source text and contain no display,
window or controller index.

### Files changed

- Production: `lib/services/progressive_display_state.dart` and
  `lib/services/reader_card_paginator.dart`.
- Focused tests:
  `test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart`
  and
  `test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart`.
- Tracking:
  `docs/development/nalori-reader-reliability-plan.md`, this change log and
  `test/reader_contract/README.md`.
- The P04 final-gate file, fixed seeds `40400801`–`40400812`, 320-source
  snapshot, fixtures, authored oracle, expected memberships and bounds were
  not edited.

### Automated evidence

| Command | Result | Duration | Exit |
| --- | --- | ---: | ---: |
| Pre-edit fixed-seed reproduction, final-gate fixture test filtered to the ten legal plans | Seed `40400802` first rejected with `seamOverlap`; seeds `40400802`–`40400810` failed | 4.292 s | 1 |
| Pre-edit 320-source final-gate reproduction | Operation 0 accepted; operation 1 rejected with `invalidFrontier` | 3.953 s | 1 |
| Focused continuation/reconstruction file plus focused publication transaction file | 21 passed, including two new regressions | 5.520 s | 0 |
| Complete focused P04 suite excluding the separately preserved final-gate file | 64 passed, 0 failed, 0 skipped; all prior 62 tests plus two regressions | 6.081 s | 0 |
| Unchanged preliminary P04 final-gate file | 1 passed, 2 failed, 0 skipped | 5.874 s | 1 |
| Complete unchanged P03 matrix | 57 passed, 0 failed, 0 skipped; all 23 historical failure-ledger rows remain resolved | 7.848 s | 0 |
| Frozen P02 parity plus fixture/parser controls | 9 passed, 0 failed, 0 skipped | 3.985 s | 0 |
| Scoped `rtk dart format` over the four changed Dart files | Four files checked; one formatting change | 0.212 s | 0 |
| Scoped `rtk dart analyze` over the four changed Dart files | No issues found | 1.619 s | 0 |

Two earlier test retries with default widget-creation tracking ended during
Flutter compiler startup and were terminated after the compiler exited; the
same focused tests passed with `--no-track-widget-creation`. No semantic test
failure was hidden by that runner option.

The focused seam test proves source-4 frontier publication with source 5 still
recorded as next unconsumed input; sources 4–7 append without mutation of the
accepted card. Existing transaction tests keep real gap/overlap rejection and
byte-equivalent rejection state green. The continuation test proves one- and
two-card frontier reconstruction, a two-card/five-resident-slice frontier with
six peak structural entries, repeated ordinary sources over multiple bounded
resumes, strict codec round-trip, zero copied source text and corruption
rejection. Structural/split-stress tests retain explicit full-span provenance and
source 7 remains `[0,58)`, `[58,125)`, `[125,191)`, `[191,198)`.

Observed preliminary maxima were 14 atomic entries for completed fixture work
and eight per synthetic advancement, zero private predecessor cards discarded,
two frontier candidates, six peak frontier entries, 25 continuation records,
87 accepted display cards and zero copied source text. No approved ceiling was
exceeded before the newly preserved failures.

### Preserved preliminary-gate failures and remaining blocker

The unchanged gate proceeds through the original append and immediate frontier
resume defects, but it exposes two later out-of-scope failures. Seeds
`40400802`–`40400810` reach backward preparation after legal forward traversal
and `ProgressiveDisplayState` rejects prepend with
`CanonicalDisplayPublicationOutcomeKind.committedCardMismatch` (“Prepend
committed/current overlap evidence differs.”); seed `40400802` remains the
first failing plan and accepted display state is unchanged. The owning boundary
is the prepend committed/current evidence validation in
`ProgressiveDisplayState._buildCanonicalCandidate`.

The synthetic traversal completes 37 eight-source-or-smaller operations,
passes checkpoint-index eviction evidence, reaches source 267, retains 25
records and 87 cards, then the target-source-280 request returns an accepted
provisional result with null target containment. The owning boundary is
bounded target continuation in
`CanonicalReaderPaginationSession._generateTargetInternal`. Target 280 is not
published and display trimming/complete traversal are not proved. Per the
task boundary, neither newly exposed defect was repaired. A separately
authorized corrective task must preserve these failures, repair only their
owning target/backward/publication contracts, and then run the independent
evidence-only `TASK-P04-008` rerun.

`RISK-001`, `RISK-002` and `RISK-003` remain open with their updated evidence.
No other risk closed. No requirement was promoted. P04 remains 7/8, overall
progress remains 31/89, and P05 is not open.

No persistent checkpoint/cache schema or version, cache key/record/format,
dependency or lockfile changed. No cache service, fixture/parser source,
measurement/rendering/layout behavior, lifecycle, restoration, persistence or
navigation behavior changed. No network, generator, migration, full Flutter
suite, device, emulator or integration-device test ran. No Git stage, commit,
reset, clean, restore, revert or discard command ran.

## CHANGE-20260908-020 — Correct canonical prepend proof and bounded target containment

**Date:** 2026-09-08  
**Phase/task authority:** Corrective work within the approved
`TASK-P04-004`, `TASK-P04-005` and `TASK-P04-007` contracts. No task ID was
added. This is not the independent `TASK-P04-008` sign-off.

### Preserved pre-edit reproductions and field-level root causes

The unchanged legal plan for seed `40400802` was reproduced independently:

```json
{"firstSourceBudget":15,"kind":"targetForwardBackward","partitions":["[0,7)","[7,10)","[10,12)","[12,14)","[14,18)","[18,20)"],"seed":40400802,"target":2}
```

It reached a legal backward-preparation result and the publication transaction
rejected it as `committedCardMismatch`. The accepted current card and the
regenerated current card had the same canonical card identity and signature
`5b39a5af2e05256bd8ee8ace915221e831fd9b77259971fd5855dfad57ee5613`,
the same ordered stable slices (source 2 UTF-16 `[0,20)` followed by source 3
`[0,23)`), the same visible content (`Micro Reader Chapter`, a blank line, then
`Micro Reader Subsection`), the same heading structural owners/roles, and the
same physical start/end and predecessor/successor cursor positions. The stable
committed anchor, accepted continuation/checkpoint chain, existing suffix,
maps and identities were also unchanged. Only proof-local/transient evidence
differed: the backward regeneration continuation had legitimately advanced
through later successor evidence and its `previousFinalizedBoundary` owned the
later source-12-through-15 card, while the committed card remained source 2/3;
the regenerated chunks could also carry different display/request-local chunk
indexes, source-range `originalChunkIndex` values and ordinal hints.

The root cause was twofold in
`ProgressiveDisplayState._buildCanonicalCandidate`: it incorrectly required
the proof continuation's latest finalized boundary to own the committed card,
although backward regeneration must be allowed to continue beyond that card to
prove its successor seam; and, if accepted, it would have installed that
proof-only backward continuation instead of preserving the accepted forward
continuation. Its comparison also included mutable `BookChunk.toJson()` index
fields. Removing committed-card proof was not the correction: the transaction
now compares canonical stable card identity, ordered ownership/interval digest,
visible content, structure and physical cursor positions, validates that the
proof continuation spans and finalizes the committed card, and preserves the
accepted continuation and anchor.

The unchanged transparent 320-source reproduction independently reached
operation 36 with the next cursor at source 267; every advancement consumed at
most eight source/fragment entries and the checkpoint index retained at most
25 records. The next request for source 280 returned an accepted
`CanonicalBudgetExhaustedWithFrontier` with null containment. Its restart and
continuation were compatible and integrity-valid, the provisional frontier
carried the exact next range and chain evidence, and finalization still needed
bounded successor evidence. No target publication occurred. The root cause was
`CanonicalReaderPaginationSession._generateTargetInternal` treating exhaustion
of one internal request budget as exhaustion of the high-level target request:
it returned immediately instead of resuming that validated continuation within
the remaining 110-entry envelope, thereby misclassifying a nonterminal private
frontier as accepted high-level output.

### Correction semantics and retained rejection guarantees

Prepend publication now proves the regenerated current card against the
accepted committed card using stable identity, ordered source ownership and
UTF-16/table intervals, visible content, structural owner/role evidence and
physical boundary cursors. Incoming cards must remain strict canonical
predecessors; both adjacent seams must be exact; only predecessors are added;
and the committed card, stable anchor, existing suffix, maps, identities and
accepted continuation remain unchanged. Comparison deliberately excludes
display/window/request indexes and transient ordinal hints. Seeds
`40400802`–`40400810` reach the same valid canonical result. Existing negative
tests retain atomic, byte-equivalent rejection for a genuinely different card,
signature, content, source interval, structural owner, anchor, gap, overlap,
stale generation, cancellation and corrupted continuation.

Bounded target generation now resumes an internal provisional frontier only
through its validated continuation while the high-level work envelope remains.
It obtains only the successor evidence needed to finalize exact stable
source/offset containment. If the envelope is genuinely exhausted it returns
the typed no-authority `CanonicalReaderRequiredEarlierRestart` result; it does
not publish, settle, checkpoint or authorize a cache write. Provisional and
nearest cards never become target success. Cancellation, staleness,
incompatible-snapshot, corrupt-continuation and unavailable-restart rejection
remain intact. Normal/recovery ceilings remain 110/158, the frontier cap remains
two cards, continuation retention remains 25 records and continuation payloads
copy zero source text. The generic backward selector uses the existing recovery
envelope only when a trusted non-continuation root can require more predecessor
sources than normal retention; it does not special-case the seed, source,
operation or fixture.

### Files changed

- Production: `lib/services/progressive_display_state.dart` and
  `lib/services/reader_card_paginator.dart`.
- Focused tests:
  `test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart`
  and
  `test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart`.
- Tracking: `docs/development/nalori-reader-reliability-plan.md`, this append-only
  change log and `test/reader_contract/README.md`.
- `test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart`,
  its seeds, plans, assertions, bounds, source memberships, identities,
  diagnostics and cache cases were not edited.

### Automated evidence

| Command | Result | Duration | Exit |
| --- | --- | ---: | ---: |
| Pre-edit fixed-seed reproduction, unchanged final-gate fixture test filtered to the ten legal plans | Seed `40400802` rejected first with `committedCardMismatch`; seeds `40400802`–`40400810` reproduced the same publication defect | 6.000 s | 1 |
| Pre-edit unchanged 320-source reproduction | Reached operation 36/source 267 with operations of eight entries or fewer and 25 retained records; source-280 request returned provisional output with null containment | 5.218 s | 1 |
| New prepend and target owning-boundary regressions | 18 passed, 0 failed, 0 skipped | 5.908 s | 0 |
| Complete focused P04 suite excluding the final-gate file | 66 passed, 0 failed, 0 skipped | 7.334 s | 0 |
| Complete unchanged P03 matrix | 57 passed, 0 failed, 0 skipped | 8.697 s | 0 |
| Frozen P02 paginator parity and fixture/parser controls | 9 passed, 0 failed, 0 skipped | 4.404 s | 0 |
| Exactly one complete preliminary run of the unchanged P04 final-gate file | 3 passed, 0 failed, 0 skipped | 6.840 s | 0 |
| Final scoped `rtk dart format` over the four changed Dart files | Four files checked; zero formatting changes | 0.267 s | 0 |
| Final scoped `rtk dart analyze` over the four changed Dart files | No issues found | 2.796 s | 0 |

One initial pre-edit fixture reproduction stalled during Flutter compiler
startup with default widget tracking and was terminated with exit 130; the
same unchanged filtered test then produced the recorded semantic failure with
`--no-track-widget-creation`. One mistyped intermediate formatter invocation
also included the three Markdown tracking files, which Dart rejected as
non-Dart input with exit 65 and did not modify; the correctly scoped final
formatter/analyzer evidence is recorded above.

Observed maxima were 20 atomic entries for fixture/recovery work, 17 entries
for the source-267-to-source-280 target request, eight entries for any one
synthetic advancement, two provisional frontier candidates, six coalesced
frontier entries, 25 retained continuation records, 87 resident display cards,
five discarded private predecessor cards and zero copied source text. The
unchanged fixture run retained nine resident cards. No operation paginated the
whole 320-source input and no approved ceiling was exceeded.

The one unchanged preliminary final-gate run is green and exposed no third
defect. It remains preliminary: P04 stays `IN_PROGRESS` at 7/8, overall progress
stays 31/89, `TASK-P04-008` remains incomplete, P05 remains not started and no
requirement is promoted. The recommended next scope is an independent,
evidence-only rerun of the unchanged final-gate file, followed by task/phase
status updates only if that separate run is green.

No persistent checkpoint/cache format, schema, key, migration or version,
dependency, lockfile, fixture/parser oracle, P02/P03 expectation, or
measurement/rendering/layout behavior changed. No network, generator,
migration, full Flutter suite, device, emulator or integration-device test ran.
No Git mutation command ran.

## CHANGE-20260908-021 — Complete P04 canonical pagination final gate

- Date: 2026-09-08–2026-09-09 (Asia/Kolkata); execution crossed local midnight.
- Task completed: `TASK-P04-008` only. No production behavior was implemented
  or repaired and no P05 task was started.
- Phase/status: P04 moved from `IN_PROGRESS` at 7/8 to `COMPLETED` at 8/8;
  overall progress moved from 31/89 to 32/89. P04 exit criteria and P05 entry
  criteria are met; P05 remains `NOT_STARTED`.
- Requirements verified: `REQ-007`, `REQ-008`, `REQ-011`, `REQ-012`,
  `REQ-013` and `REQ-048`. `REQ-009`, `REQ-010`, `REQ-027`, `REQ-028`,
  `REQ-040`, `REQ-044`, `REQ-045` and `REQ-051` remain unverified because
  their P05/P06/P09/P10/P11 evidence is not complete.
- Change type: independent evidence-only execution plus the three authorized
  Markdown tracker/README updates.

### Pre-run integrity and inherited evidence

The complete reliability plan, complete append-only change log, canonical
pagination design, reader-contract README and unchanged final-gate test were
read before the integrity capture. `CHANGE-20260908-018`, `-019` and `-020`
were reviewed in full. `CHANGE-20260908-020` correctly recorded focused P04
66/66, unchanged P03 57/57, frozen P02 controls 9/9, one preliminary unchanged
final-gate run at 3/3 and no unresolved production blocker; only this separate
sign-off was outstanding.

- Branch: `feature/lazy-random-access-reader`.
- HEAD: `9d7716597d95d578699e7a54544d92d5b4b234b6`.
- The full `git status --short` baseline retained the substantial pre-existing
  modified/untracked production, test, dependency, documentation and media
  work. It was not staged, reset, restored, cleaned or otherwise altered.
- Starting counts were P04 7/8, overall 31/89 and 51 requirement rows at
  `NOT_STARTED`.
- Final-gate SHA-256 was and remains
  `88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`.
- The seven P03 matrix hashes were captured before execution and matched
  afterwards: full range
  `4505e5730a02ec55a3ba65412e40e1bbf1d672cf1d03a89044382b4b7a7cd425`,
  target-first
  `1e7fd14dd0c0f44d89dc1a9fc90105c71d1399ccf5bf8ac47bc20e31fd208b41`,
  forward/backward
  `5481bf3bd31c24c7e6076a72258ec7400b6b71b746f050aadd91c89bb8618d8b`,
  singleton
  `9ab90693a6f83ca76ecde148921443ead86b845ef3e02c0535e396177778e77b`,
  structural ownership
  `1826b4c4b970eac1af9e3e3d5dd5f50c7782eb9e47095ae30c3ca5ed6c392e`,
  cache order
  `8b3a964273ac407fa452298f9b66f61f4fe9e7cebe8087d0a5940c8aff6de9bd`,
  and ledger integrity
  `edeefbc6e5703125a10c58d629b8b97e8fec12c90e4b85c154be5d85458dae0a`.
- Read-only inspection reconfirmed all twelve seeds `40400801` through
  `40400812`, the transparent 320-source case targeting source 280, normal and
  recovery envelopes 110/158, at most two frontier candidates, 25 retained
  continuation records and zero copied continuation source text.

### Independent final-gate executions

The first invocation without the stable compiler flag spent 30.001 seconds in
test-file loading and the Flutter resident compiler exited unexpectedly before
any test started or produced a semantic result. The wrapper remained present
after the compiler failure and was terminated explicitly. This is recorded as
`INDETERMINATE` infrastructure/startup evidence and was retried exactly once,
as permitted. No semantic failure was retried.

All three counted executions then used the exact same command and environment:

```text
rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart
```

| Run | Duration | Passed | Failed | Skipped | Exit | Evidence comparison |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 7.226 s | 3 | 0 | 0 | 0 | Baseline: 38 normalized fixture/synthetic evidence lines |
| 2 | 6.420 s | 3 | 0 | 0 | 0 | Byte-identical normalized evidence to run 1 |
| 3 | 6.330 s | 3 | 0 | 0 | 0 | Byte-identical normalized evidence to run 1 |

The unchanged gate itself regenerates every fixed-seed plan twice and compares
plan JSON, ordered visible text, canonical source slices/owners/roles, exact
card identities/signatures, continuation-chain encoding, target containment,
work vectors and retained-state JSON. Across the three outer executions the
fixture summary and all 37 ordered synthetic advancement records were also
identical. Every construction seed and both real-cache seeds were green.

### Required supporting evidence

All commands were host-side, used `rtk`, performed no dependency resolution or
network access, and ran no full suite or device/integration path.

| Exact command/scope | Duration | Result | Exit |
| --- | ---: | --- | ---: |
| `rtk flutter test --no-pub --no-track-widget-creation --reporter compact` over the six focused P04 files plus `reader_card_paginator_p04_final_gate_test.dart` | 9.974 s | 69 passed, 0 failed, 0 skipped | 0 |
| `rtk flutter test --no-pub --no-track-widget-creation --reporter compact` over full-range, target-first, forward/backward, singleton, structural-ownership, cache-order and failure-ledger P03 files | 8.646 s | 57 passed, 0 failed, 0 skipped | 0 |
| `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_parity_test.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart` | 4.357 s | 9 passed, 0 failed, 0 skipped | 0 |
| Analytics-suppressed direct SDK `dart analyze` over seven P04 production files, seven focused P04 test files and two shared pagination/cache harnesses under `rtk bash -lc` | 3.163 s | No issues found | 0 |
| Pre/post `rtk sha256sum`, scoped status/source inspection and final scoped `rtk git diff --check` | Recorded below | Frozen final-gate/P03 hashes unchanged; no source/oracle whitespace change | 0 |

The complete P04 command consisted of the canonical state-machine,
continuation/checkpoint, canonical paths, backward preparation, structural
identity, progressive canonical transaction and final-gate files. The complete
P03 command consisted of the seven files whose hashes are listed above.

Exact required command forms were:

```text
rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart test/reader_contract/pagination/reader_card_paginator_structural_identity_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart

rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart

rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_parity_test.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart

rtk bash -lc 'DART_SUPPRESS_ANALYTICS=true /home/uttam/Desktop/Code/flutter/bin/cache/dart-sdk/bin/dart analyze lib/models/canonical_pagination.dart lib/models/canonical_pagination_checkpoint_index.dart lib/models/reader_checkpoint.dart lib/services/epub_parser.dart lib/services/reader_card_paginator.dart lib/services/progressive_display_state.dart lib/screens/reader_screen.dart test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart test/reader_contract/pagination/reader_card_paginator_canonical_paths_test.dart test/reader_contract/pagination/reader_card_paginator_backward_preparation_test.dart test/reader_contract/pagination/reader_card_paginator_structural_identity_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart test/reader_contract/pagination/reader_core_pagination_harness.dart test/reader_contract/pagination/reader_core_cache_order_harness.dart'
```

### Boundedness and retained-state evidence

The independent runs reproduce the preliminary maxima recorded by
`CHANGE-20260908-020`, with the advancement values independently derived from
the 37 identical ordered synthetic records:

| Quantity | Maximum/result | Approved ceiling |
| --- | ---: | ---: |
| Fixture/recovery atomic work | 20 | 158 recovery; 110 normal |
| Distant-target work from source 267 to containment of source 280 | 17 | 110 |
| Any one synthetic advancement | 8 | 110 |
| Provisional frontier candidates | 2 | 2 |
| Coalesced frontier entries | 6 | 61 |
| Retained continuation records | 25 | 25 |
| Resident display cards before target replacement | 87 | 96 |
| Discarded private predecessor cards | 5 | 7 normal / 15 recovery |
| Copied continuation source-text bytes | 0 | 0 |

No 110/158 work ceiling was exceeded. No operation paginated all 320 sources:
37 cancellable advancements processed eight or fewer entries each and reached
source 267, then 17 entries of target work finalized exact containment of
source 280. The finalized target card was published by an accepted replacement,
the display remained within its 96-card bound, cancellation left state
byte-equivalent, and an earlier target regenerated successfully. Section
boundary checkpoints survived retention while an old record was observably
evicted and the active frontier/parent remained valid.

Legal prepend publication added only canonical predecessors and preserved the
committed card, stable anchor, existing suffix, maps, identities and accepted
forward continuation. Existing negative tests remained green for genuine card,
content, source interval, ownership, anchor, gap, overlap, stale/cancelled and
corrupt-continuation disagreements.

### Manual source and ownership review

The visible fixture XHTML, OPF spine and manifest source oracle were reread.
The unchanged P03 structural/coverage suite and frozen hashes corroborate the
manual review:

- standard-layout membership remains `0–1`, `2–3`, `4–7`, `8`, `9–10`, `11`,
  `12–15`, `16`, `17–19`;
- split-stress source 7 remains `[0,58)`, `[58,125)`, `[125,191)`,
  `[191,198)`;
- identical repeated prose at sources 8 and 18 retains distinct href/source/
  logical ownership;
- navigation and chapter/subsection/section headings, both ordered-list items,
  decoded table text `Column Value North Seven`, inline bold/italic styling,
  the linked footnote/reference/body and the source-15→16→17 section seam
  retain their reviewed owners and order; and
- all readable sources 0 through 19 are present exactly once in source order,
  with no gap, overlap, duplicate, reorder, out-of-range slice or omission.

No agreement among generated paths was used to create or revise the source
oracle.

### Requirement and risk status

| Requirement | Final status | Evidence boundary |
| --- | --- | --- |
| REQ-007 | VERIFIED | Identical complete ordered canonical identities across fixed construction seeds and P03 matrix |
| REQ-008 | VERIFIED | Full, target-first, forward, backward/prepend and singleton construction agree |
| REQ-011 | VERIFIED | Reviewed split/continued, heading/generated, repeat, list/table/rich and seam identities |
| REQ-012 | VERIFIED | Stable canonical identity excludes mutable display/window/request index authority |
| REQ-013 | VERIFIED | Exact gap-free, nonoverlapping, nonduplicated ordered append/prepend coverage |
| REQ-048 | VERIFIED | Accepted/published cards and suffix remain immutable during extension |

`REQ-009` and `REQ-010` remain unverified pending P06 compatible persistent-
cache evidence. `REQ-027`, `REQ-028` and `REQ-040` retain P09 production
navigation/index-authority work. `REQ-044` and `REQ-045` retain P06/P11 byte
and release profiling. `REQ-051` retains P05/P06/P10 evidence. No later-phase
requirement was promoted.

`RISK-001` is now `MITIGATED_BY_P04`: fixed construction/cache seeds use stable
continuation evidence, while P09 retains screen/navigation index authority.
`RISK-002` is `MITIGATED_BY_P04`: bounded target/backward work reaches source
280 without a whole-book operation, while P06/P11 retain cache-byte/release
profiling. `RISK-003` is `MITIGATED_BY_P04`: transactional seam and committed-
card publication accept legal append/prepend evidence and atomically reject
wrong evidence.

### Scope and final integrity

Only these authorized Markdown files were intentionally changed by this turn:

- `docs/development/nalori-reader-reliability-plan.md`;
- `docs/development/nalori-reader-reliability-change-log.md`;
- `test/reader_contract/README.md`.

No Dart production file, test, fixture, authored oracle, seed, plan, identity,
bound, expected source membership, dependency, lockfile, schema, migration,
cache format, version or signature changed. The final-gate and all P03 hashes
match their pre-run values. `git status --short` retained the same broad
pre-existing path inventory. A recent-write audit found only Flutter-generated
`build/native_assets/linux/native_assets.json`,
`build/unit_test_assets/NativeAssetsManifest.json` and
`build/test_cache/build/83b49ace49b4ccd12a390bb5260c5dfa.cache.dill` outside
the authorized Markdown files; they are transient test-run build artifacts,
not source, dependency or product cache-format changes.

No formatting command ran. No full Flutter suite, device, emulator,
integration-device, network, dependency-resolution, generator, migration,
deployment, default cache clear or Git mutation command ran. Unrelated dirty
work remains untouched.

### Follow-up

Recommended next task: `TASK-P05-001` only—perform the field-by-field
measurement/render/fingerprint inventory. P05 entry criteria are met, but P05
must begin in a separately authorized turn and must not change layout behavior
as part of this P04 sign-off.

### Commit/reference

No commit was created and no Git staging command ran.

## CHANGE-20260908-022 — Inventory measurement, rendering and layout identity

**Phase/task.** P05 / TASK-P05-001 — completed as a documentation-only
discovery task after the frozen CHANGE-20260908-021 P04 baseline.

**Purpose.** Produce the authoritative current-state trace of every
pagination-affecting measurement, rendering, physical-card identity, display
cache, segmented cache, and checkpoint compatibility input before any P05
contract/refactor work. This entry does not decide the final contract or alter
P03/P04 evidence.

**Artifact.**

- Added docs/development/nalori-reader-layout-contract-inventory.md.

The artifact contains 91 primary field-level rows and 25 issue/unresolved/
ownership rows (116 table rows total), all with file/symbol evidence. It traces
the parser/source path, ReaderScreen environment capture and
resolveReaderLayoutMetrics, paginator layout input and structure measurement,
ReadingCard/ReadingCardDeck render tree, physical-card identity,
displayChunkKey/DisplayGenerationSignature/segmented cache construction, and
checkpoint exact-signature compatibility. It separately records declared font
configuration, test-only font-file bytes, unobservable runtime face identity,
and unobservable resolved glyph/metric identity.

**Confirmed findings.**

- Measurement passes _canonicalDisplaySafeArea (bottom safe inset forced to
  zero) to resolveReaderLayoutMetrics; ReadingCard independently resolves its
  content padding from raw MediaQuery.viewPadding. The measured body is
  therefore taller by the raw bottom inset. This is a BLOCKER
  DIFFERENT_RESOLUTION finding.
- Heading decoration, rich bold/italic and reduced footnote runs, list marker
  weight, decoded table box arithmetic, preformatted layout, image intrinsic
  height, and inherited RTL Directionality do not have complete
  measurement/render parity. Speed Reader is intended transient state but
  currently changes paragraph segmentation and render spans.
- The fingerprint contains declared family/weight/profile and scale(1), but
  not resolved font/metric/readiness state, direction, complete TextScaler
  identity, explicit renderer structural constants, image metric identity, or
  exact subpixel dimension/inset precision. The current cache-string encoding
  truncates/rounds several of those values.
- GoogleFonts.pendingFonts is awaited after normal/heading style requests, but
  failure is allowed to continue with platform fallback and no resolved face or
  metrics are captured. The controlled Lexend SHA-256 files are test-only
  fixture bytes, not proof of runtime resolved metric identity.

The inventory records 3 BLOCKER and 6 HIGH confirmed mismatches, plus 10
precisely bounded unresolved inputs. M-01 through M-08 may legitimately change
P03 physical-card boundaries if a later P05 correction proves why; P05-007
must then preserve and rerun the frozen construction-order oracle and record
each range/signature cause. No current P03 membership, source range, identity,
continuation, bound, expected result, fixture, or authored oracle changed.

**Plan and risk tracking.**

- Marked TASK-P05-001 complete; P05 is IN_PROGRESS at 1/7 and overall progress
  is 33/89. P05 exit criteria and P06 entry criteria remain unmet.
- No P05 requirement was promoted to VERIFIED.
- RISK-005 and RISK-006 remain OPEN, with evidence descriptions updated only.
- DISC-004 is PARTIALLY RESOLVED only as to the static bottom-safe-area split
  and structural map. Resolved-font readiness/metric identity remains open.
- The only recommended next task is TASK-P05-002: define the bounded immutable
  layout-input/compatibility taxonomy, including safe-area, direction, scaler,
  declared/readiness/resolved-font states and structural renderer inputs,
  without implementation, version, cache, checkpoint, migration or oracle
  changes.

**Verification and scope integrity.**

No Flutter, device/emulator, integration, P02/P03/P04 matrix, full-suite,
network, formatter, generator, migration, dependency-resolution, cache-clear,
or Git mutation command ran. Static read-only repository searches and file
inspection were used only to trace symbols and existing documentation. The
final status/diff audit is recorded with this task's completion; unrelated
pre-existing dirty/untracked work remains untouched. No Dart production or
test file, fixture, source oracle, version, signature, cache format,
dependency, lockfile, schema, or migration was changed.

**Modified documentation.**

- docs/development/nalori-reader-layout-contract-inventory.md
- docs/development/nalori-reader-reliability-plan.md
- docs/development/nalori-reader-reliability-change-log.md

**Follow-up.** TASK-P05-002 only.

## CHANGE-20260909-023 — Define immutable reader layout contract

**Phase/task.** P05 / `TASK-P05-002` — completed as a contract-design task
after the `CHANGE-20260908-022` inventory. P05 is now `IN_PROGRESS` at 2/7;
overall progress is 34/89. P05 exit criteria and P06 entry criteria remain
unmet.

**Requirements and status.** This design supports `REQ-002`, `REQ-014`–
`REQ-017`, `REQ-035`, `REQ-042`, and `REQ-051`. No requirement is promoted to
`VERIFIED`: production parity, font readiness, controls invariance,
classification, focused probes, and the complete P03 rerun remain future
evidence.

### Problem addressed

Production currently divides authority among ReaderScreen environment/cache
strings, `ReaderCardPaginatorLayout`, and `ReadingCard` ambient layout/style
resolution. The inventory proved a bottom-safe-area mismatch, forced-LTR
measurement, incomplete scaler/font identity, and structural measure/render
gaps. P05-003/P05-004 required one field-complete immutable design that made no
new ownership decisions during implementation.

### Contract and approved policy

Added `docs/development/nalori-reader-layout-contract-design.md`, defining 211
sequential normative fields (`F001`–`F211`) across:

- one session/generation `ReaderLayoutContract` with captured environment,
  effective settings policy, resolved card geometry, closed typography/strut
  catalog, exact used-size scale profile, font evidence, structural rules and
  identity bundle; and
- one per-source-block `ResolvedReaderBlockLayout` with final locale,
  direction, alignment, width, spans, spacing, structural box, resolved height
  and block fingerprint used identically by measurement and rendering.

The actual bounded logical deck/card constraint is outer geometry authority;
`MediaQuery.size` is accepted only when exactly equivalent. Raw stable
`MediaQuery.viewPadding` is captured once on all four sides, including bottom,
and participates in both measurement and rendering. Keyboard `viewInsets`,
controls, toolbars, overlays, gestures and transforms do not change the body
rectangle. Border stroke is a fingerprinted paint-only policy with zero body
layout inset; U-01 remains a runtime conformance probe rather than a claim
about current Flutter behavior. The measurement safety reserve is explicitly
named, formula-defined, fingerprinted, and not painted.

Direction resolves once per block in this order: supported canonical
source/block override, captured reader direction, then LTR only when both are
absent. The same final direction and alignment go to `TextPainter` and the
rendered widget. Locale, direction, alignment and source-language metadata are
separate fields.

Text scaling is represented by exact finite binary64 input/output pairs for
every logical size in the closed resolved style catalog. Runtime scaler type,
`scale(1.0)`, rounding, truncation and tolerances cannot establish identity.

### Font evidence and structural ownership

Declared font request identity and requested variants are separate from
readiness and resolved-metric evidence. Required renderer variants include
body, heading w900, inline w700/italic/bold-italic, footnote/list w600, table
w500/w800, monospace, and distinct publisher requests. `unresolved`/`loading`
returns typed pending. `terminalLoaded` and `terminalStableFallback` require
nonempty exact observable width, line, baseline, wrap-boundary, shaping-box,
source-repertoire and missing-glyph/fallback evidence. Unavailable or
contradictory evidence rejects authority. No resolved face name is invented;
a changed layout-relevant observation changes the metric digest and layout
identity. Test-only Lexend SHA-256 values remain asset-byte evidence only.

The structural contract gives a single resolver to ordinary/continued and
publisher paragraphs, source/generated headings plus gap/divider, lists and
marker geometry, rich/footnote spans, normalized decoded tables and rows,
preformatted blocks, deterministic terminal image boxes, explicit fragments
and separator synthesis. Speed Reader remains excluded and must fit the
canonical resolved tree.

### Identity, encoding and lifecycle

The design separates `LayoutMetricsIdentity`,
`SourceCompatibilityIdentity`, `PaginationAlgorithmIdentity`,
`RendererLayoutIdentity`, composite `ReaderCompatibilityIdentity`, and the
physical-card identity based on existing P04 stable source ownership plus the
appropriate identity and ordered block-layout inputs. Raw values that resolve
identically do not split layout identity; book ID, access time, tokens and
display/window indexes are not metrics.

Canonical encoding is strict tagged binary data with fixed field order,
length-delimited text/nested records, fixed enum wire names, structured locale,
explicit optional presence, stable collection ordering, finite IEEE-754
binary64 encoding, normalized positive zero, rejection of NaN/infinity, and
lowercase SHA-256 output. It forbids ambiguous concatenation, decimal rounding,
object `hashCode`, runtime identity and display indexes. The proposed
`reader_layout_contract_v1` is in-memory semantics only; no production or
persistent constant changed.

Typed outcomes cover ready, pending font evidence, pending image metrics,
incompatible environment, unsupported structure, contradictory geometry,
invalid numeric value, and stale capture. Anything except ready has no
pagination, publication, settlement, checkpoint-write or compatible-cache-
write authority. Generation/cancellation tokens guard lifecycle only and stay
outside physical identity.

### Inventory and handoff coverage

Sections 13 and 14 map every M-01–M-09 and U-01–U-10 to exact contract fields,
specification status, implementation task, verifying task and possible P03
boundary effect. M-01 and M-08 policies are explicit. M-02–M-07/M-09 have
P05-003/P05-005 ownership. All ten unresolved inputs remain visible; U-05 and
U-06 stay with P05-004, and U-01/U-02 stay with P05-007 widget probes. P05-007
must map every legitimate changed P03 boundary to an exact field/mismatch cause
and rerun the complete frozen P03 matrix.

The only recommended next task is `TASK-P05-003`: introduce the immutable
in-memory shapes and shared pure geometry/typography/span/structure resolvers,
make paginator and renderer consume them, enforce typed no-authority outcomes,
and preserve all persistent versions/formats. Runtime font-gate discovery
remains separate `TASK-P05-004` work.

### Files created or modified

- Created `docs/development/nalori-reader-layout-contract-design.md`.
- Updated `docs/development/nalori-reader-reliability-plan.md` current status,
  P05 checklist/phase row, DISC-004 and progress dashboard.
- Updated the current phase summary/P04/P05 rows and appended this entry in
  `docs/development/nalori-reader-reliability-change-log.md`.
- Added a concise design-only reference to `test/reader_contract/README.md`.

No historical `CHANGE-*` entry was rewritten. The prior CHANGE-022 follow-up
remains its accurate historical recommendation; this entry is appended after
it.

### Commands and results

Only read-only `rtk` repository searches/inspection, hashes/status, and
documentation consistency checks ran. Required documents were read and the
production ownership trace covered `resolveReaderLayoutMetrics`,
`_canonicalDisplaySafeArea`, display build/load/rebuild paths,
`ReaderCardPaginatorLayout`, `ReadingCard`, `ReadingCardDeck`, typography/
strut methods, paragraph/list/table/publisher helpers, canonical card identity,
display/cache signatures and checkpoint exact-layout matching.

- Required sections 1–18 were present in order.
- Field-ID validation found 211 definitions from F001 through F211 with no
  missing or duplicate ID.
- The plan contains 89 unique task IDs and 34 checked tasks; current plan/log
  summaries report P05 2/7 and overall 34/89.
- Legacy pre-023 status markers were absent from the plan/change-log current
  summary regions. Historical entries that accurately describe earlier status
  were left unchanged.
- Scoped status showed only the four authorized Markdown paths for this task;
  extensive unrelated dirty/untracked work remained present and untouched.

No Flutter test, Dart format/analyze, P02/P03/P04 matrix, full suite, device,
emulator, integration-device, generator, migration, dependency-resolution,
network, cache-clear, or Git mutation command ran.

### Risk, discovery and scope result

`RISK-005` and `RISK-006` remain OPEN. DISC-004 now says contract policies are
defined while production parity, exact border behavior, image/deck probes and
resolved-font evidence remain unverified. No Dart production/test file,
fixture, oracle, P03/P04 identity/range, cache/checkpoint format or schema,
parser/pagination/display version, dependency, lockfile, or device behavior
changed.

**Follow-up.** `TASK-P05-003` only.

## TASK-P05-003 implementation and verification evidence

**Phase/task.** P05 / `TASK-P05-003` completed. P05 is now `IN_PROGRESS` at
4/7 and overall progress is 36/89. P05 exit criteria and P06 entry criteria
remain unmet; no P05 requirement is promoted to `VERIFIED`. RISK-005 and
RISK-006 remain open pending P05-007.

### Production result

The production reader now captures one generation-scoped
`ReaderLayoutEnvironment` and builds one immutable `ReaderLayoutContract`
before cache admission or pagination. The contract groups effective settings,
all-four-side stable view padding, the actual bounded deck geometry, exact
used-size scale responses, a closed bundled typography catalog, structural
policies and canonical identities. It contains no context, widget, recognizer,
controller, display index, page position or transient active/preview state.
All retained lists/maps are defensively immutable and semantic equality is
value based.

The model hierarchy is `ReaderLayoutContract` → environment,
`ReaderResolvedSettingsPolicy`, `ReaderCardGeometry`,
`ResolvedTextScaleProfile`, `ReaderTypographyContract`,
`ReaderStructuralLayoutContract` and `ReaderLayoutIdentityBundle`; resolved
content is expressed as `ResolvedReaderSpanRun`, paragraph/list/table/
preformatted/image plans, `ResolvedReaderBlockLayout` and ordered
`ResolvedReaderCardLayout`. `ReaderLayoutContractBuilder`,
`ReaderBlockLayoutResolver`, `ReaderCardLayoutResolver`,
`ReaderLayoutMeasurementAdapter` and `ReaderLayoutRenderingAdapter` are the
shared pure production owners. `ReaderLayoutFieldCoverage` proves exactly 211
unique F001–F211 semantics.

`ReaderCardPaginator` measures the resolved descriptions and attaches each
ordered card layout to `CanonicalFinalizedReaderCard`; `ReadingCard` renders
the same descriptions and resolved body box. `ReaderScreen` captures once,
builds/gates once and validates contract, geometry, generation, evidence,
ordered cards/layouts and overflow atomically before publication. Legacy cache
records without complete current layout/font/block evidence take the existing
fail-closed regeneration path. The complete layout identity flows through the
existing compatible layout-fingerprint strings; no persistent record changed.

The nine inventory mismatches now have production owners:

- M-01: F015–F018/F044–F051 retain all four raw stable `viewPadding` sides;
  bottom is no longer zeroed, `viewInsets` and controls are excluded, and
  measurement/rendering consume the same body geometry.
- M-02: F133–F136/F180/F191 resolve heading text, exact height, 20-pixel gap
  and selected-family divider as one measured/rendered structure.
- M-03: F079–F105/F149–F150/F179 resolve one ordered gap-free rich/link/
  footnote span plan; recognizers and paint decoration are layered afterward.
- M-04: F141–F148/F175–F177 resolve ordered/unordered marker text, final w600
  metrics, width, gap, indentation, item spacing and rich body spans once.
- M-05: F151–F156/F184–F186 resolve decoded cell ownership and row/column
  spans into fixed columns, cells, rows, padding, border and scroll width;
  the widget no longer delegates authoritative sizing to Flutter `Table`.
- M-06: F157–F159/F181–F182/F187 use bundled Roboto Mono in one fixed-line,
  no-wrap horizontal-scroll plan with identical width/padding/height.
- M-07: F160–F162/F188–F191 require stable bytes/checksum, decoded intrinsic
  dimensions and terminal contain/no-upscale box evidence before finalization;
  later frames cannot resize the fixed box.
- M-08: F020/F104/F167–F170 resolve explicit LTR/RTL, locale and alignment for
  both painters and widgets instead of forcing LTR in measurement.
- M-09: Speed Reader now preserves canonical paragraph segments, gaps, spans,
  wrapping and body box; only transient paint/highlight state changes.

Font authority reuses `ReaderFontEvidenceGate`. Contract construction requires
`readyTerminalBundled`; each stable source owner uses the gate's bounded exact
slice sequence (2,048 UTF-16 maximum) and preserves
`opaqueFallbackMetricProbe`. Pending/rejected/stale/cancelled font outcomes
stop before cache acceptance, measurement, finalization and publication.
Images similarly require terminal metric evidence. Reflow rejection preserves
the previously accepted display, maps, committed card, stable anchor and
checkpoint index.

Canonical encoding uses explicit record kinds/revisions, tagged fixed-order
fields, optional-presence markers, finite exact binary64 with positive-zero
normalization, ordered collections and SHA-256. It supplies layout-metrics,
renderer-layout, per-block, ordered per-card block and physical-card composite
fingerprints without object hashes or display/window/request indexes. No
P05-006 compatibility classifier was added.

### Focused parity and transition evidence

The 34-case production contract suite passed all 34 cases. Body and split
paragraph, heading text/gap/divider, rich bold/italic, footnote markers,
ordered/unordered lists, publisher paragraphs, decoded-span tables,
preformatted lines and fixed images all achieved shared measure/render box
parity. Explicit LTR/RTL, alignment, nonlinear scaler distinction, nonzero
bottom padding, keyboard exclusion, Speed Reader, active/preview selection,
highlight/note/character-marker/recognizer decoration, typed evidence failure,
cache fail-closed behavior, stale atomic rejection, stable-window-independent
block identity and byte-identical repeated identities also passed.

The narrow canonical smoke passed 1/1. Full/repeated-forward, target-first,
forward and bounded-backward construction produced identical ordered source
slices, exact source coverage `0..7`, canonical card signatures and physical
layout fingerprints. No gap, overlap, omission, reordering, unstable identity
or cross-order disagreement occurred. The standard transition passed 1/1 and
retained all nine source memberships/ranges:
`0:0-20,1:0-22 | 2:0-20,3:0-23 | 4:0-10,5:0-10,6:0-12,7:0-198 |
8:0-33 | 9:0-19,10:0-18 | 11:0-1 | 12:0-56,13:0-50,14:0-37,15:0-63 |
16:0-22 | 17:0-52,18:0-33,19:0-55`. Table source 11 retains authored
UTF-16 ownership `[0,136)` and body-row provenance `[0,1)`.

No standard boundary changed. Every card signature changed because the legacy
rounded controlled-layout string was replaced by the complete immutable
layout identity, specifically including the previously omitted nonzero
F016=16/F045 bottom safe inset and the shared F079–F211 typography, evidence,
renderer, block and card identity fields. In card order, old → new is:

1. `900dcb5cd6f865b023e2993eddc2af0717708ed7e97eacc90bd428169b801ad2` → `3f27702d77cf7eafc56e3eb12b7de0cabf19b216b712b6bd8cbf5696a01a9e79`
2. `c65ab813c185dcb053f18212e692cb32185eb9bdcf0dd3727b9e91dcbc0d027e` → `68de2d916ad4d9611b4b7e3c6fc94fada8ace6a6ec964d7e71f58bfe454be84b`
3. `a5359dd65eed855dabd8a5463b0a04d73c7a5380cedca86a9ce670949cf64906` → `aff523a0850637ed2f2f12400a33d5667832a1a805589237b7318acdd59d4295`
4. `80da94b0e869efae9a7bc7997053d8327d404fd3f3897bad890aac1e074fbfb3` → `6f82dc719931c405d9b6eb327df84bbcba006c4082e7d063ec12dd0f1e3ba5c8`
5. `0f99c5663483c1a5e281e37368ca4b7ba9e51afba5e14336f2c8051211b55f63` → `8c0dbd53308d12f402dc6f3a1ad64a868dc1302df123786d48d3c96e9f2c3e58`
6. `6390952d896803c796cbf9d53e385fd176472a30f1e6be2ef99e55650342f8eb` → `e99fbe116c39d6842abb2d8ba459996e30515208d87920a96f99c75f9336bd8a`
7. `d6390d57d281d9c783feb6ce8e5b292395ed2bdbd47dd5c43f134d87c2a68316` → `c16cf34e3db4017446460407c71d39298bd8c4a02cb4ffad285d5c68fd3240c5`
8. `8202c7593986184e7bd43ce6e2dd5c43922af33bc6f902f79adee6ff2215eee5` → `bcca2d33d48c3f25a1eb2c9973bf4ddbdc6252b8ff28e222ca49a1836fb552a8`
9. `5f823ecc03e20c9bf069c1ac4b831bbc2b2d5dbd20b4fa755afda489af72bb4e` → `05402dceb87fd09959ab8d6f36cc949ddf775d2735864b4f499c3a23c2d49580`

Recorded retained-state maxima are 4,696 bytes per contract, 1,462 bytes per
resolved block and 1,728 bytes per resolved card in the focused corpus. No
contract/evidence record copies a whole book or mutable source window, and no
operation paginates or probes an entire book.

### Files and verification

Production files changed: `lib/models/reader_layout_contract.dart`,
`lib/models/canonical_pagination.dart`,
`lib/services/reader_layout_contract_service.dart`,
`lib/services/reader_font_evidence_gate.dart`,
`lib/services/reader_card_paginator.dart`, `lib/screens/reader_screen.dart`,
`lib/widgets/reading_card.dart` and `lib/widgets/reader_table_block.dart`.
Focused tests added:
`test/reader_contract/layout/reader_layout_contract_shared_test.dart`,
`reader_layout_construction_order_smoke_test.dart` and
`reader_layout_standard_transition_test.dart`. Documentation changed:
`test/reader_contract/README.md`, the reliability plan and this change log.

- `rtk dart format` over the 11 changed production/test Dart files: 11 files,
  two mechanically changed, 0.630 s, exit 0.
- `rtk dart analyze` over those 11 files: no issues, 2.824 s, exit 0.
- `rtk flutter test` over the three new P05-003 files: 36/36 (34 contract/
  parity + one construction smoke + one standard transition), 15.891 s,
  exit 0.
- `rtk flutter test` for the P05 font gate and controlled font environment:
  27/27 (18/18 + 9/9), 9.048 s, exit 0.
- `rtk flutter test` for progressive publication plus renderer/table/speed/
  copy-share/list connections: 60/60 (12 state + 48 widget/interaction),
  7.969 s, exit 0.
- Read-only frozen hashes remain exact: P04 final gate
  `88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`;
  P03 target/forward/singleton/structural tests retain the four pre-edit hashes
  recorded above. Status/diff inspection preserved unrelated dirty work.

No complete P03/P04 matrix, full Flutter suite, device/emulator/integration
test, network command, generator or migration ran. No dependency declaration
or lockfile, font asset/manifest/provenance/licence, persistent cache/checkpoint
schema/key/format/migration/version, parser/source version, P03/P04 test/
fixture/oracle, navigation/settlement/restoration/durable-flush behavior or
device behavior changed in this task.

**Follow-up.** `TASK-P05-005` only.

### P05-005 evidence record for formal CHANGE-20260909-027 append

**Phase/task.** P05 / `TASK-P05-005` completed. P05 is `IN_PROGRESS` at 5/7
and overall progress is 37/89. P05 exit criteria and P06 entry criteria remain
unmet. No P05 requirement is promoted to `VERIFIED`; the implemented-but-not-
final statuses retain P05-007's one-field, complete-probe and late-transition
work.

### Mandatory pre-edit trace

The pre-edit repository state was branch `feature/lazy-random-access-reader`,
HEAD `9d7716597d95d578699e7a54544d92d5b4b234b6`, with substantial pre-existing
modified/untracked work retained untouched. Read-only hashes captured the frozen
P03/P04 tests and P05-003 shared/constructor/standard-transition tests before
editing. Repository-wide symbol inspection found no production defect.

- `ReaderScreen.build` reads screen size, raw all-four-side `viewPadding` and
  text scaler, then calls `_ensureDisplayChunksBuilt`. Its early return requires
  those stable inputs and accepted display chunks to match; controls, overlays,
  Speed Reader, selection, highlights, notes and deck state only call
  `setState`/listeners and do not construct a contract or start pagination.
  `_canonicalDisplaySafeArea` retains raw top/right/bottom/left padding.
- `Scaffold.resizeToAvoidBottomInset` is false. Keyboard `viewInsets` are not a
  contract input; in-app bars/FABs/menus are `Stack` siblings of the
  `Positioned.fill` reader deck and do not constrain it.
- A changed stable safe area reaches the immutable builder and generation path.
  Font/evidence admission, paginator resolution and `_applyProgressiveDisplayState`
  retain candidates until geometry/layout checks succeed; only then are active
  contract, cards and checkpoint-relevant display state swapped. Rejection
  leaves accepted evidence in place.
- `ReadingCard` consumes a supplied immutable contract/resolved layout for the
  production path. Its ambient `MediaQuery` reads are legacy fallback or
  interaction/popup presentation only, never replacement geometry. Selection,
  recognizers, highlights/notes/generated character ranges, Speed Reader and
  fixed bookmark/chapter/progress reservations are layered after resolved layout.
  `ReaderTableBlock` similarly consumes its supplied resolved table layout.
- `ReadingCardDeck`'s `LayoutBuilder` supplies only drag extent. Children are
  `Positioned.fill`; drag/animation/depth transforms are paint/hit-test state.
  Cached preview widgets key on card-builder/current-layout changes and clear on
  an accepted layout replacement. Preview/current rebuilds do not publish cards
  or alter checkpoint authority.

This trace is narrow production-path evidence, not a claim that a rebuild is a
repagination or that the complete U-01/U-02/U-10 outer-deck probe obligation is
closed.

### Focused result

Production already conformed; no production file was changed. The new focused
production seam uses the real terminal font gate, immutable contract builder,
block/card resolvers, canonical paginator session, progressive publication
boundary, `ReadingCard`, and cached `ReadingCardDeck` in a bounded 390×420
`Scaffold(resizeToAvoidBottomInset: false)`.

The deterministic 14-transition sequence covers controls/overlays visible and
hidden, keyboard `viewInsets` 0→240→0, active/preview change, cached deck
programmatic transform, selection and link metadata, highlights, note paint and
generated character paint, fixed bookmark/chapter/page/progress reservations,
and active/paused Speed Reader cursor/WPM plus lyrics/window mode. For every
transient state and a repeated unchanged sequence it proves byte-identical
contract identity/body geometry, ordered resolved block and card layouts,
ordered canonical source slices, physical-card signatures and accepted
publication authority. It also proves stale old-layout and incomplete
candidates cannot replace a newer accepted display.

Recorded task maxima are 4,700 retained contract bytes, 668 retained resolved-
block bytes, 944 retained resolved-card bytes, 14 control-state transitions,
zero pagination operations caused by transient transitions, zero
publication/checkpoint/cache-write authority changes caused by them, and zero
stale cached preview cards after a genuine layout transition.

Stable raw safe area remains genuinely different: from base
`viewPadding(3,24,5,18)`, bottom `18→42` reduces body height by exactly 24,
top `24→39` by exactly 15, left `3→17` reduces body width by exactly 14, and
right `5→21` by exactly 16; each produces a different immutable identity.
Unchanged raw padding with keyboard `viewInsets` changed is byte-identical.

### Files and verification

Files changed: `test/reader_contract/layout/reader_transient_state_invariance_test.dart`,
`test/reader_contract/README.md`, `docs/development/nalori-reader-reliability-plan.md`,
and this append-only change log. No production correction was necessary.

- `rtk dart format test/reader_contract/layout/reader_transient_state_invariance_test.dart`:
  one Dart file, 0.02 s, exit 0.
- `rtk dart analyze test/reader_contract/layout/reader_transient_state_invariance_test.dart`:
  no issues, 2.2 s, exit 0.
- `rtk flutter test -r compact test/reader_contract/layout/reader_transient_state_invariance_test.dart`:
  4/4, 8.0 s, exit 0.
- Existing P05-003 shared-contract/construction-smoke/standard-transition gate:
  36/36, 16.0 s, exit 0. Deterministic font-gate/support gate: 27/27, 9.6 s,
  exit 0. An additive seven-path interaction rerun (the six-path 57-case set
  plus deck) passed 80/80, 9.6 s, confirming the 23 existing deck cases.
- Affected publication/state/renderer/table/Speed Reader/copy-share/list/
  typography/chapter-progress/character interaction command passed 60/60,
  9.3 s, exit 0.
- Final combined P05-focused command (new 4 + shared 36 + font/support 27 +
  affected 60) passed 127/127, 17.9 s, exit 0. No test used `pumpAndSettle` or
  an uncontrolled delay.

Exact grouped commands were:

```text
rtk dart format test/reader_contract/layout/reader_transient_state_invariance_test.dart
rtk dart analyze test/reader_contract/layout/reader_transient_state_invariance_test.dart
rtk flutter test -r compact test/reader_contract/layout/reader_transient_state_invariance_test.dart
rtk flutter test -r compact test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_layout_construction_order_smoke_test.dart test/reader_contract/layout/reader_layout_standard_transition_test.dart
rtk flutter test -r compact test/reader_contract/layout/reader_font_evidence_gate_test.dart test/reader_contract/support/reader_contract_layout_environment_test.dart
rtk flutter test -r compact test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/widgets/reading_card_renderer_consistency_test.dart test/widgets/reading_card_table_test.dart test/widgets/reading_card_speed_read_test.dart test/widgets/reader_copy_quote_connection_test.dart test/widgets/reading_card_list_test.dart test/widgets/reader_typography_rendering_test.dart test/widgets/reading_card_chapter_progress_test.dart test/widgets/annotations_panel_character_declaration_test.dart
rtk flutter test -r compact test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/widgets/reading_card_renderer_consistency_test.dart test/widgets/reading_card_table_test.dart test/widgets/reading_card_speed_read_test.dart test/widgets/reader_copy_quote_connection_test.dart test/widgets/reading_card_list_test.dart test/widgets/reading_card_deck_test.dart
rtk flutter test -r compact test/reader_contract/layout/reader_transient_state_invariance_test.dart test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_layout_construction_order_smoke_test.dart test/reader_contract/layout/reader_layout_standard_transition_test.dart test/reader_contract/layout/reader_font_evidence_gate_test.dart test/reader_contract/support/reader_contract_layout_environment_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/widgets/reading_card_renderer_consistency_test.dart test/widgets/reading_card_table_test.dart test/widgets/reading_card_speed_read_test.dart test/widgets/reader_copy_quote_connection_test.dart test/widgets/reading_card_list_test.dart test/widgets/reader_typography_rendering_test.dart test/widgets/reading_card_chapter_progress_test.dart test/widgets/annotations_panel_character_declaration_test.dart
```

Read-only `rtk sha256sum` over 17 frozen P03/P04/P05-003 paths matched all
pre-edit values (including P04 final gate
`88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d` and
P05 shared/construction/standard tests
`4266da563915eb3bb9a1f85f44de7240b787e233c115de3f2ec6502289baea27`,
`f54dfa2d77bd922c716614aa9d4b6539139edf545ed90582e5f4138ceb2affc4`, and
`9c625b1c4de7ee23f54ba1cbddd3833ed0819ffa570081ad09fb16c917a72e39`).
`rtk git diff --check` over changed documentation was clean. The whitespace
scan found only four pre-existing historical Markdown line-break spaces, none
in the new test or this task's additions. No complete P03/P04 matrix, full
Flutter suite, device/emulator/integration test, explicit network command,
generator or migration ran. No persistent schema/record/key/format/version,
dependency/lockfile/font asset, P03/P04 fixture/oracle/signature membership,
navigation/restoration/settlement/durable-exit behavior or device behavior
changed.

**Remaining work.** `TASK-P05-006` alone is recommended next: implement the
single compatibility classifier and migration reasons, without persistent
migration. `TASK-P05-007` was not started and still owns the complete one-field
matrix, U-01/U-02/U-10 probes, late font/fallback transition integration,
complete P03 construction-order rerun and final reviewed oracle transition.

## TASK-P05-003 mandatory pre-edit trace

**Phase/task.** P05 / `TASK-P05-003`. Work began from branch
`feature/lazy-random-access-reader` at
`9d7716597d95d578699e7a54544d92d5b4b234b6`. The repository already contained
substantial modified and untracked work; the pre-edit status was captured and
is preserved. P03/P04 tests, fixtures and oracles are frozen for this task.

### Mandatory pre-edit production trace

The current call chain is `ReaderScreen.build` ambient `MediaQuery` capture →
`_ensureDisplayChunksBuilt` → `_canonicalDisplaySafeArea` / rounded string
identity → `_loadOrRebuildDisplayChunks` (`GoogleFonts.pendingFonts`, with a
catch-and-continue failure path, before cache inspection) →
`_rebuildDisplayChunks` → `resolveReaderLayoutMetrics` →
`ReaderCardPaginatorLayout` → `CanonicalReaderPaginationSession` →
`ReaderCardPaginator._runEngine.measureTextHeight` / structural estimators →
P04 card finalization and `CanonicalReaderCardIdentityBuilder`. Publication is
`CanonicalDisplayPublicationRequest` →
`ProgressiveDisplayState.publishCanonical` → ReaderScreen projection →
`_ReaderPageView` → `ReadingCardDeck`/`PageView` → `ReadingCard`, which
currently resolves an independent ambient layout and render tree. Cache
records without P04 continuation authority already fail closed; checkpoint
matching consumes `_activeReaderLayoutFingerprint` through its existing string
field.

| ID | Source structure | Current measurement input and calculation | Current rendered input and calculation | Current identity input | Shared owner proposed | Production owner after correction | Boundary change |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M-01 | Every physical card | Screen size plus `_canonicalDisplaySafeArea`, whose bottom is `0`; body height is `max(1, screenH - cardMargin.vertical - contentPadding.vertical)` | `ReadingCard.build` rereads raw `MediaQuery.viewPadding`; same formula therefore subtracts raw bottom | Rounded/string signature contains canonical bottom `0` | `ReaderLayoutEnvironment` + `ReaderCardGeometry` | generation capture/contract; paginator and card receive its exact body box | Yes, exact cause F015–F018/F044–F051 |
| M-02 | Source/generated heading `BookChunk.isHeading` | One heading `TextPainter`; height is heading glyph box only | centered `SelectableText.rich` + 20 px gap + divider glyph line | source heading ownership only; no decoration identity | resolved heading structural box and explicit gap/divider roles | shared block resolver, painter adapter and card adapter | Yes, F133–F136/F180/F191 |
| M-03 | `inlineStyles`, links and `footnotes` over paragraph/list ranges | plain body `TextSpan`/paragraph helper; footnote characters use body metrics | renderer sweep applies w700/italic/bold-italic and 0.75-size w600 footnote runs; recognizers attach later | rich source digest, not metric runs | ordered gap-free `ResolvedReaderSpanRun` plan | shared span resolver consumed by paginator and renderer | Yes, F079–F105/F149–F150/F179 |
| M-04 | ordered/unordered `BookListDisplaySegment` | `resolveReaderListLayoutMetrics` measures marker using body style; width clamps 18..52, gap 8, indent `min(36,depth*12)` | same box constants but marker paints w600 | list source semantics only | resolved list plan using final w600 marker role | shared list resolver/metric plan | Yes, F141–F148/F175–F177 |
| M-05 | decoded `ReaderTableBlock`, including normalized span expansion and body-row ownership | per-column rule is 156 for 3+ columns, otherwise `max(120,maxWidth/count)`; each row is max cell painter +18 and total starts at 22 | widget chooses `max(blockWidth,156*count)`, Flex columns, 10/9 cell padding, 10 outer vertical padding and Flutter `Table` row geometry | structural table digest only | normalized immutable fixed-column/fixed-row table plan | shared table resolver and fixed-box table widget | Yes, F151–F156/F184–F186 |
| M-06 | `BookBlockRole.preformatted` / parsed pre block | falls through ordinary/publisher wrapping and selected reader family | generic platform `monospace`, clamped 12..16, 1.35 height, no wrap, horizontal scroll, 10 inner and outer padding | source structural digest only | explicit-line no-wrap plan using bundled Roboto Mono | shared preformatted resolver and fixed-line renderer | Yes, F157–F159/F181–F182/F187 |
| M-07 | atomic image `BookChunk.imageBytes` | empty text height is zero; no decode/intrinsic/fit evidence | asynchronous `Image.memory(..., fit: contain)` plus 16 bottom padding picks intrinsic layout later | source byte checksum only | terminal image evidence + immutable contain/no-upscale image box | bounded image metric resolver before finalization and fixed renderer box | Yes, F160–F162/F188–F191 |
| M-08 | every text/list/table block | every paginator `TextPainter` forces LTR | text widgets inherit ambient direction; hit-test/note painters also force LTR | direction absent | captured default plus source override/fallback in each resolved style/block | contract direction resolver; explicit painter and widget direction | Yes for bidi/RTL, F020/F090/F104/F167–F170 |
| M-09 | ordinary paragraph with transient Speed Reader state | canonical measurement uses final-layout paragraph segments and gaps | active Speed Reader collapses all segments to one and substitutes its span construction | Speed Reader excluded, correctly in principle | canonical paragraph/span boxes retained; speed decoration only | ReadingCard renderer adapter with paint-only speed overlays | No |

For every row the stable source owner remains the existing P04 source slice,
logical paragraph/list/table owner and exact UTF-16/body-row interval. Current
identity finalization signs publication fingerprint, the incomplete controlled
layout string, pagination version and ordered P04 source slices. The correction
will add layout-metrics, renderer-layout, block-layout and ordered-card-layout
digests without adding display/window/request indexes or changing P04 source
ownership.

### Frozen baseline, ranges, versions and evidence bounds

- Controlled standard layout currently produces nine cards with memberships
  `0–1`, `2–3`, `4–7`, `8`, `9–10`, table `11`, `12–15`, `16`, `17–19`.
  Split stress retains source 7 ranges `[0,58)`, `[58,125)`, `[125,191)`,
  `[191,198)`. Table source 11 owns UTF-16 `[0,136)` and body rows `[0,1)`.
- Persistent constants at pre-edit are unchanged: whole display format `3`,
  display layout `v14`, segmented display format `3`, pagination
  `nalori_cards_v16_lists`, checkpoint record `1`, checkpoint-store schema `1`
  and stable-location version `2`.
- Font-gate bounds/outcomes are: 2,048 UTF-16 per exact source slice, 11 role
  requests, two widths, 33 painter runs per observation, two observations,
  32,768 bytes per source, 25 retained records/819,200 bytes; outcomes are
  `readyTerminalBundled`, `pendingAssetReadiness`, missing/digest/coverage/
  unavailable/contradictory/stale/cancelled rejection. Only ready authorizes
  layout and the fallback branch remains `opaqueFallbackMetricProbe`.
- SHA-256 baseline for every file under `test/reader_contract/pagination/` was
  captured before editing. The frozen final gate is
  `88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`;
  the target/forward/singleton/structural P03 tests are respectively
  `1e7fd14dd0c0f44d89dc1a9fc90105c71d1399ccf5bf8ac47bc20e31fd208b41`,
  `5481bf3bd31c24c7e6076a72258ec7400b6b71b746f050aadd91c89bb8618d8b`,
  `9ab90693a6f83ca76ecde148921443ead86b845ef3e02c0535e396177778e77b`,
  and `1826b4c4b970eac1af9e3e3d5dd5ddf50c7782eb9e47095ae30c3ca5ed6c392e`.
  The complete per-file hash output is retained in the command evidence for
  this change and will be compared read-only at completion.

Implementation and verification evidence follows below; this entry remains
append-only.

## CHANGE-20260909-024 — Establish deterministic font evidence boundary

**Phase/task.** P05 / `TASK-P05-004` — feasibility audit completed; production
implementation is blocked and the task remains incomplete. This task was
intentionally audited before `TASK-P05-003` because the approved F006/F106–F128
contract requires P05-003 to consume nonempty terminal font evidence. No
partial or fabricated gate was added. P05 remains `IN_PROGRESS` at 2/7 and
overall progress remains 34/89. P05 exit criteria and P06 entry criteria remain
unmet; no requirement is promoted to `VERIFIED`; `RISK-006` remains open.

### Pre-edit production request and runtime matrix

Repository-wide tracing found eight reachable reader-selected families and two
additional renderer families. For a selected Google Fonts family, `W` is the
user-selected body weight in `{300,400,500,600,700}`. `B` is the compensated
body logical size, `H = B + 14 * fontSizeMultiplier`, `F = 0.75 * B`,
`T = clamp(B,13,18)`, and `P = clamp(B,12,16)`. The current reader uses no
variable axes and supplies no font features. Locale is copied to later
measurement/render styles, so shaping and fallback can be locale-sensitive,
but the initial Google Fonts loader request itself is not locale-specific.

| Family/request | Weight | Style/axes | Production caller | Measurement caller | Rendering caller | Local production bytes | Runtime fetch possible | Fallback behavior | Readiness observable |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Inter | normal 300–900; italic 300–700 | normal/italic; no axes/features | `ReadingSettings.getTextStyle`: only body `W` and heading 900 schedule Google Fonts | body/publisher `W`; heading 900; current list marker incorrectly measures `W`; table 500/800 | body/publisher `W`, heading 900, inline 700, italic `W`, bold-italic 700, footnote/list 600, table 500/800 | none bundled; an opaque device cache may exist | yes; production default is `allowRuntimeFetching=true` | variant alias then base `Inter`, then platform/glyph fallback | only scheduled body/heading futures; no renderer-copy variant or glyph/fallback signal |
| Roboto Mono | requested normal 300–900; italic 300–700 | normal/italic; no axes/features; provider nearest delivery maps normal 800/900 to 700 | same boundary | same role pattern | same role pattern | none bundled | yes | requested 800/900 use the provider's `Roboto Mono_700` alias; otherwise variant alias/base/platform fallback | same body/heading-only future boundary |
| Merriweather | normal 300–900; italic 300–700 | normal/italic; no axes/features | same boundary | same role pattern | same role pattern | none bundled | yes | variant alias then base/platform/glyph fallback | same body/heading-only future boundary |
| Lora | requested normal 300–900; italic 300–700 | normal/italic; no axes/features; provider maps 300→400 and normal 800/900→700 | same boundary | same role pattern | same role pattern | none bundled | yes | mapped variant alias then base/platform/glyph fallback | same body/heading-only future boundary |
| EB Garamond | requested normal 300–900; italic 300–700 | normal/italic; no axes/features; provider maps 300→400 and normal 900→800 | same boundary | same role pattern | same role pattern | none bundled | yes | mapped variant alias then base/platform/glyph fallback | same body/heading-only future boundary |
| Literata | normal 300–900; italic 300–700 | normal/italic; no axes/features | same boundary | same role pattern | same role pattern | none bundled | yes | variant alias then base/platform/glyph fallback | same body/heading-only future boundary |
| Atkinson Hyperlegible | requested normal 300–900; italic 300–700 | normal/italic; no axes/features; provider maps 300/400/500→400 and 600/700/800/900→700 | same boundary | same role pattern | same role pattern | none bundled | yes | mapped 400/700 alias then base/platform/glyph fallback | same body/heading-only future boundary |
| Lexend | normal 300–900; requested italic 300–700 | descriptor has normal only; italic maps to the same-weight normal delivery while `TextStyle.fontStyle` remains italic | same boundary | same role pattern | same role pattern | root bundle has normal 400/600/700/900 only; these filenames are discoverable by Google Fonts but remain test-intended bytes and do not prove runtime selection | yes for missing normal 300/500/800 or when no asset/device-cache match exists | variant alias then base/platform/glyph fallback; italic can be synthetic/opaque | same body/heading-only future boundary; asset hash is not runtime evidence |
| generic `monospace` | inherited `W` (300–700) | normal; no axes/features | no Google Fonts request | no current preformatted-specific measurement path | `ReaderPreformattedBlockWidget`, size `P`, no wrap | no declared app font family/bytes | no Google Fonts fetch for this request | platform generic monospace and glyph fallback | none |
| implicit default family | 400 | normal; no axes/features | no Google Fonts request | heading divider is not currently measured | heading divider at size 14 | no declared app font family/bytes | no Google Fonts fetch for this request | platform default and glyph fallback | none |

The provider-delivery mappings above come from the installed `google_fonts`
8.0.2 descriptor tables and their nearest-variant scoring. The nominal closed
reachable catalog is 96 selected-family combinations (eight families times
seven normal plus five italic requested weights), five generic-monospace body
weights, and one implicit-default divider request: 102 family/weight/style
combinations before locale and size expansion. One captured setting needs six
to eight distinct selected-family combinations, plus monospace and divider, so
eight to ten unique request/style combinations. One capture has at most six
distinct logical/scaled size values from `B/H/F/T/P/14`; an unlisted scaler
response cannot be inferred from `scale(1.0)`.

The renderer-used role catalog is exactly:

| Role | Request and logical size | Current loader/measurement/render fact |
| --- | --- | --- |
| body and publisher prose/poem/quote/letter | selected family, `W` normal, `B` | body alias is scheduled, measured and rendered |
| heading | selected family, 900 normal, `H` | heading alias is scheduled, measured and rendered |
| inline bold | selected family, 700 normal, `B` | renderer uses `copyWith`; no 700 request is scheduled unless `W=700`; current measurement omits the run |
| inline italic | selected family, `W` italic, `B` | renderer uses `copyWith`; no italic request is scheduled; current measurement omits the run |
| inline bold-italic | selected family, 700 italic, `B` | renderer uses `copyWith`; no italic/700 request is scheduled; current measurement omits the run |
| footnote marker | selected family, 600 normal, `F` | renderer uses `copyWith`; no 600 request is scheduled unless `W=600`; current measurement treats it as ordinary text |
| list marker | selected family, 600 normal, `B` | renderer paints 600 but both request and current marker measurement remain on the body alias/weight |
| table cell/header | selected family, 500/800 normal, `T` | measurement and rendering set these weights on the body alias; neither delivery request is scheduled unless coincident with `W` |
| preformatted | generic `monospace`, inherited `W`, `P` | rendered only; no Google Fonts readiness and no current specialized measurement |
| heading divider | implicit platform default, 400 normal, 14 | rendered only; no declared family or readiness signal |

### What the loader and Flutter actually establish

`GoogleFonts.pendingFonts()` is `Future.wait` over the package-global set of
currently pending font futures. Style construction first chooses the nearest
descriptor variant, immediately returns a `TextStyle` whose family is a
variant-scoped alias with a base-family fallback, and asynchronously tries the
asset manifest, opaque device filesystem cache, then HTTP when allowed.

- Success establishes only that each future in that particular global snapshot
  returned after `FontLoader.load`, or that its alias was already marked loaded
  in this process. It does not establish every future request, the selected
  face for a run, glyph coverage, fallback order, missing glyphs, renderer-only
  `copyWith` variations, a frame-stable metric result, or a face name.
- Failure establishes only that at least one scheduled load threw. The package
  removes that alias from its loaded set and its success-only pending-set
  callback does not remove the failed future. Later `getTextStyle` and strut
  construction retries the request. Reader rendering performs those later
  calls, so the current catch-and-continue path cannot classify its measured
  fallback as terminal or prevent a late successful load from changing
  metrics after pagination.
- Because the pending set is package-global, unrelated Google Fonts requests
  may also be included; it is not a reader request-catalog completion record.

The inspected Flutter text API exposes enough data for the metric portion of
F120–F124: `TextPainter.width`, `height`, `size`, min/max intrinsic width,
`didExceedMaxLines`, alphabetic/ideographic
`computeDistanceToActualBaseline`, all `LineMetrics` fields (`hardBreak`,
`ascent`, `descent`, `unscaledAscent`, `height`, `width`, `left`, `baseline`,
`lineNumber`), UTF-16 ranges through `getLineBoundary`, caret/position results,
selection `TextBox` left/top/right/bottom/direction, and `GlyphInfo` grapheme
box/code-unit-range/direction. It exposes no trustworthy resolved family/face,
font-file identity, per-glyph fallback family, missing-glyph flag, or stable
fallback-order signal. F125/F126 would therefore have to use
`opaqueFallbackMetricProbe`; labeling a face as resolved would be invented.

### Bounded repertoire and feasibility result

There is no production source-repertoire model. The canonical pagination
snapshot pins serialized `BookChunk` records and a digest, not a script/glyph
repertoire. Constructing F118/F126 would require walking source text. The lazy
repository normally retains at most three sections under a 6 MiB retained-byte
budget, so its current `_sourceChunks` window is book-length independent, but
later sections and their scripts/glyphs are absent. The eager route can contain
the whole book. A fixed finite probe corpus can cover chosen sentinels but
cannot guarantee detection of a font/fallback change affecting an arbitrary
later unseen glyph. Scanning the full EPUB is expressly prohibited; merely
rehashing the existing source snapshot does not supply glyph evidence.

Consequently deterministic production evidence is **not feasible under the
authorized task constraints**. Completion would require at least one forbidden
or separately authorized change:

1. a contract correction making font evidence explicitly scoped to the
   bounded currently pinned source window, with mandatory re-gating before a
   later source window can paginate/publish and a defined identity transition;
   or a precomputed whole-publication repertoire index and its persistent
   compatibility design; and
2. a complete production font-delivery policy: bundle/declare all supported
   delivery variants, or deliberately define and freeze a platform-fallback
   policy at the shared P05-003 style owner. The current test-only Lexend
   400/600/700/900 bytes are insufficient for eight families, body 300/500,
   table 800, every italic request, generic monospace, or implicit default
   content, and their hashes cannot substitute for observations.

The smallest recommended separately authorized correction is the first option
in item 1: revise F117–F126 to grant authority only for a bounded pinned source
window and require a fresh gate before any newly revealed repertoire is
measured or published. After that correction, separately choose either a
complete shipped production font set or an explicit non-retrying fallback
owner as part of shared P05-003 typography resolution. Do not add an unbounded
book scan or a temporary font identity.

### Work, evidence, cache, tests, and scope result

- Families: eight selectable Google families plus generic monospace and the
  implicit platform-default divider family; unique request/style combinations:
  102 across reachable settings, eight to ten in one capture.
- Scaled sizes: at most six in one capture. Approved probe widths: none are
  numerically defined by the current design. Probe runs, synchronous work,
  asynchronous work, and retained evidence therefore have no valid finite
  production maximum. No evidence record was constructed: retained evidence
  bytes and production probe runs are zero for this audit.
- Existing lazy source retention is capped by policy at three sections and
  6 MiB, but that is not complete future-repertoire evidence and does not bound
  every single oversized source section. No operation proportional to total
  book length was added or run.
- No production or test file changed. No `ReaderFontEvidenceGate`, request
  model, outcome type, canonical encoder, digest, publication gate, or cache
  adapter was added because each would be partial/fake under the blockers.
  Therefore there are no gate outcomes or metric-evidence digests to report.
- The existing whole/segmented-cache P04 behavior remains unchanged: legacy
  records lacking canonical continuation evidence fail closed and regenerate,
  but current layout identity still has no font-evidence digest. No cache was
  deleted or globally disabled, and no persistent compatibility claim changed.
- No focused P05 font-gate test, deterministic support test, P03 matrix, or P04
  gate ran after the stop condition. The attempted read-only `flutter
  --version` inspection exited before reporting a version because the managed
  sandbox prevents Flutter from updating its SDK cache; it did not touch the
  repository or run tests.
- No font was downloaded. No font asset, dependency, lockfile, persistent
  cache/checkpoint schema, format, key, migration, or version changed. No
  P03/P04 fixture, oracle, expectation, identity, range, or device behavior
  changed. Unrelated dirty/untracked work remains untouched.

**Files changed.** Documentation only:
`docs/development/nalori-reader-reliability-change-log.md`.

**Remaining blocker.** Complete and stable F117–F126 coverage for future unseen
source repertoire cannot be proved from the bounded current window, and the
current loader/render path cannot make failure fallback terminal or observe a
resolved/fallback face. `TASK-P05-004` remains unchecked; P05 remains 2/7 and
overall progress remains 34/89.

**Follow-up.** Authorize the bounded-window/re-gating contract correction and
the production font-delivery/fallback ownership choice before retrying
`TASK-P05-004`. Do not start `TASK-P05-003` with fabricated font evidence.

## CHANGE-20260909-025 — Ship deterministic reader fonts and correct evidence scope

**Phase/task.** P05 / `TASK-P05-004` — complete. This task was intentionally
executed before `TASK-P05-003` because the approved F006/F106–F128 contract
requires P05-003 to consume nonempty terminal font evidence. P05 is
`IN_PROGRESS` at 3/7 and overall progress is 35/89. P05 exit criteria and P06
entry criteria remain unmet; no requirement is promoted to `VERIFIED`;
`RISK-006` remains open pending P05-003/P05-007 integration and transition
proof. CHANGE-024 remains the historical failed-feasibility record.

### Authorized correction and delivery policy

The product decision retains all eight choices and accepts application-size
growth. CHANGE-024's mutable-window recommendation is corrected: delivery
evidence is session-level (asset bytes, effective mappings, loader completion,
probe revision), while source repertoire/metric evidence belongs to the exact
stable canonical source unit or range-keyed slice being resolved. It is not a
union of loaded neighboring sections. The same unit therefore has the same
input/evidence independent of window, request order, forward/backward
construction, display index and neighbors. New source units gate before future
measurement/finalization/publication; existing cards retain ordered
source/block evidence. Giant inputs use exact slices capped at 2,048 UTF-16
units. No EPUB pre-scan, source-text retention or whole-book repertoire exists.

The installed `google_fonts` 8.0.2 descriptors supplied the authoritative
nearest-variant mapping and official `fonts.gstatic.com` SHA-addressed TTF
URLs. Family-specific OFL notices came from the official `google/fonts`
repository. The manifest records upstream URL, family, local path, requested
and delivered weights/styles, byte length, SHA-256 and licence path for every
file/mapping. Download-time and root-bundle validation both matched.

| Family | Files | Effective delivered variants |
| --- | ---: | --- |
| Inter | 12 | normal 300–900; italic 300–700 |
| Roboto Mono | 10 | normal/italic 300–700; requested normal 800/900 → 700 |
| Merriweather | 12 | normal 300–900; italic 300–700 |
| Lora | 8 | normal/italic 400–700; requested 300 → 400; normal 800/900 → 700 |
| EB Garamond | 9 | normal 400–800; italic 400–700; requested 300 → 400; normal 900 → 800 |
| Literata | 12 | normal 300–900; italic 300–700 |
| Atkinson Hyperlegible | 4 | normal/italic 400/700; 300/500 → 400 and 600/800/900 → 700 where requested |
| Lexend | 7 | normal 300–900; italic requests retain italic styling but preserve same-weight normal-file delivery |

The former reachable inventory remains 102 nominal combinations (96 selected
family variants plus five generic-monospace weights and one implicit divider).
The corrected catalog has 96 effective selected/bundled family mappings;
explicit Roboto Mono preformatted and selected-family/400 divider roles reuse
those delivered mappings. One settings capture has 11 role requests and at
most ten unique delivered variants. No generic `monospace`, implicit platform
divider, device cache, HTTP, WOFF/WOFF2 or variable-font axis is authoritative.

Seventy-four static TTFs total 19,348,768 raw bytes. A concatenated gzip
estimate is 9,893,824 bytes; store-package contribution remains toolchain and
platform dependent. Eight OFL notices and `PROVENANCE.md` ship beside the
machine-readable manifest. Existing `assets/fonts/reader_contract/` Lexend
files retain their test-only identity and are absent from the production
manifest.

### Catalog, gate and evidence semantics

`ReaderBundledFontCatalog` is the sole manifest-derived request/delivery
catalog. `ReadingSettings` selects only declared `NaloriReader*` aliases for
reader body/heading typography, so those requests cannot enter Google Fonts'
HTTP loader; app UI Google Fonts behavior is unchanged. P05-003 will connect
the catalog's preformatted/divider roles and the gate to the shared
paginator/renderer contract rather than adding a temporary adapter now.

The gate's closed outcomes are `readyTerminalBundled`,
`pendingAssetReadiness`, `rejectedMissingAsset`, `rejectedDigestMismatch`,
`rejectedIncompleteVariantCoverage`, `rejectedUnavailableMetricEvidence`,
`rejectedContradictoryEvidence`, `rejectedStaleCapture` and
`rejectedCancelled`. Only the ready terminal type exposes layout authority.
Readiness follows root-bundle reads, SHA/licence/mapping validation and awaited
`FontLoader.load` completion; stability is two immediate complete observations,
with no delay, sleep, retry loop or uncontrolled settle.

Real `TextPainter` observations include width/height, min/max intrinsic width,
all `LineMetrics`, both exposed baselines, line count, exact UTF-16 visual-line
boundaries, caret offsets/heights and reverse positions, full selection boxes,
available `GlyphInfo` bounds/ranges/direction, and overflow. Flutter still
exposes no trustworthy resolved face or per-glyph fallback-family identity, so
the source evidence explicitly uses `opaqueFallbackMetricProbe`, hashes the
complete shaping/metric record, names no face and rejects disagreement.

Canonical delivery/source records use kind/revision headers, increasing tagged
fields, fixed order, explicit optional presence, normalized enum strings,
stable sorted collections, signed/unsigned fixed-width integers and finite
big-endian IEEE-754 binary64 values with negative zero normalized. NaN and
infinity reject. SHA-256 covers the complete revisioned record. Repeated input
produced byte-identical delivery and source records/digests; changes to a
metric or detailed wrap/shaping digest changed the source evidence digest.
Serialized evidence contains no source text.

### Bounds, compatibility and files

Derived capture maxima are ten unique variants, six scaled sizes, two widths,
11 role requests and 33 TextPainter layouts per stable source slice. Each
capture runs twice for stability (66 synchronous layouts after asynchronous
asset readiness). The measured worst reachable canonical record was 24,722
bytes; the enforced next allocation boundary is 32,768 bytes. The LRU holds at
most 25 source records/819,200 bytes. Work is proportional to only the current
at-most-2,048-UTF-16 slice and is independent of publication length.

No persistent schema, cache/checkpoint key, format, migration or version was
changed. The new evidence is in-memory only and is not presented as compatible
legacy-cache authority. P05-003 must consume it before layout generation and
fail closed/regenerate where a persistent record cannot establish the same
evidence; P05-006/P06 still own persistent compatibility.

Production/assets changed: `assets/fonts/reader/` (74 TTFs, manifest,
provenance, eight OFL notices), `pubspec.yaml`,
`lib/models/reader_font_evidence.dart`, `lib/models/reading_settings.dart`, and
`lib/services/reader_font_evidence_gate.dart`. Focused test/reference changes:
`test/reader_contract/layout/reader_font_evidence_gate_test.dart` and
`test/reader_contract/README.md`. Contract/tracking changes: the P05 design,
reliability plan and this entry.

### Verification

- Scoped formatting: 4 Dart files formatted, exit 0.
- Scoped Dart analysis: production/test targets completed with exit 0; only
  pre-cleanup style infos were reported, then addressed before final rerun.
- New production-path font gate: 18/18 tests passed, covering all 24 numbered
  requirements, exit 0.
- Existing controlled reader-contract font environment: 9/9 passed, exit 0.
- Offline/no-fetch and repeated deterministic captures are included in the
  focused gate; runtime fetching was disabled and restored per test.
- Unchanged complete P03 matrix: 57/57 passed, exit 0; no oracle edit.
- Unchanged P04 final gate: 3/3 passed, exit 0; no oracle edit.
- Read-only manifest/hash/licence validation: 74/74 files, 19,348,768 bytes,
  all descriptor SHA-256 values and eight OFL notices matched.

The initial Flutter compile attempt encountered a stale incremental
`build/test_cache` dill from the upgraded local Flutter 3.47.1 toolchain. The
generated cache was moved recoverably to `/tmp/nalori-test-cache-pre-p05-004`;
the cleanly rebuilt scoped tests then ran normally. No project source/cache
format was cleared or migrated.

No dependency declaration, `pubspec.lock`, persistent format/version,
P03/P04 fixture/oracle/expectation, paginator/ReadingCard geometry,
navigation/restoration behavior or device behavior changed. No device,
emulator, integration-device, full-suite, generator or migration command ran.
No font came from an unofficial source.

**Remaining gap.** P05-003 must consume the ready evidence in one shared
measurement/render contract and connect ordered per-source evidence to card
identity/publication. P05-007 must prove late metric/fallback transitions;
RISK-006 remains open.

**Follow-up.** `TASK-P05-003` only.

## CHANGE-20260909-026 — Implement shared reader measurement and rendering contract

**Phase/task.** P05 / `TASK-P05-003` completed. The detailed mandatory
pre-edit trace and implementation/verification evidence above record the
production ownership, M-01–M-09 corrections, exact old/new signatures,
retained-state bounds, commands and unchanged frozen hashes.

Production paginator measurement and `ReadingCard` rendering now consume the
same immutable generation-scoped geometry, typography, spans and structural
block/card layouts. Terminal bundled-font/exact-source-slice and fixed image
metric evidence gate authority before cache acceptance, pagination,
finalization and atomic publication. The narrow construction-order smoke is
source-exact and order-independent; all focused parity, font, state and
interaction tests are green. No persistent format/version, dependency, font
asset, P03/P04 oracle, navigation/restoration or device behavior changed.

A final ownership audit moved candidate contract/fingerprint evidence behind
the successful atomic display commit. The post-correction scoped format passed
(one file, 0.315 s), scoped analysis passed with no issues (11 files, 3.447 s),
and the combined new-contract/state/interaction rerun passed 96/96 in 18.381 s.
Thus a rejected candidate cannot replace the previously active contract or
checkpoint layout fingerprint.

P05 is `IN_PROGRESS` at 4/7 and overall progress is 36/89. P05 exit criteria
and P06 entry criteria remain unmet; no P05 requirement is promoted to
`VERIFIED`; RISK-005/RISK-006 remain open pending P05-007.

**Follow-up.** `TASK-P05-005` only.

## CHANGE-20260909-027 — Prove transient-control and safe-area layout invariance

**Phase/task.** P05 / `TASK-P05-005` completed without a production
correction. The detailed mandatory pre-edit call-path trace, exact 14-state
matrix, grouped commands, durations, frozen hashes and retained-state bounds
are recorded in the P05-005 evidence record above. That evidence uses the real
contract builder, paginator/publication boundary, `ReadingCard` and cached
`ReadingCardDeck`; it establishes focused standard-deck coverage only.

Controls/overlays, keyboard `viewInsets`, active/preview, transform/cache,
selection/recognizers, annotation paint, fixed structural reservations and
Speed Reader state preserve the immutable identity, F044–F051 body geometry,
F178–F191 resolved layouts, source slices, physical signatures and accepted
authority. The measured maxima are 4,700 contract bytes, 668 block bytes, 944
card bytes, 14 transient transitions, zero transient pagination operations,
zero transient publication/authority changes and zero stale cached previews.
`viewInsets` is excluded; raw stable bottom/top/left/right `viewPadding`
changes reduce the appropriate body dimension by exactly 24/15/14/16 and
produce different identities.

Focused new tests passed 4/4; P05-003 shared tests 36/36; font/support 27/27;
affected publication/state/interaction tests 60/60; final combined P05 gate
127/127. P05 is `IN_PROGRESS` at 5/7, overall progress is 37/89, P05 exit and
P06 entry remain unmet, and REQ-014/015/016/017/051 are
`IMPLEMENTED_NOT_VERIFIED`. RISK-005/RISK-006 remain open pending P05-007.

No persistent format/version, dependency/lockfile, font asset, P03/P04 oracle,
navigation/restoration/device behavior or production file changed. P05-006 and
P05-007 were not started. Recommend `TASK-P05-006` only: implement the single
compatibility classifier and migration reasons without persistent migration.

## CHANGE-20260910-028 — Implement typed reader compatibility classification

**Phase/task.** P05 / `TASK-P05-006` — completed. P05 is now
`IN_PROGRESS` at 6/7 and overall progress is 38/89. P05 exit criteria and P06
entry criteria remain unmet pending `TASK-P05-007`. `REQ-014`, `REQ-015`,
`REQ-016`, `REQ-017` and `REQ-051` remain `IMPLEMENTED_NOT_VERIFIED`.
`RISK-005` and `RISK-006` remain open. `REQ-002` is not verified: real
semantic restoration remains P07/P08 work.

### Mandatory pre-edit integrity and compatibility trace

The branch was `feature/lazy-random-access-reader` at
`9d7716597d95d578699e7a54544d92d5b4b234b6`. `git status --short` showed the
substantial pre-existing modified/untracked work retained throughout; all
authorized tracking/model files were already untracked P05 work. P03/P04 and
P05-003 frozen hashes were captured before editing and matched again after
verification: P04 final gate
`88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`; P03
target/forward/singleton/structural gates
`1e7fd14dd0c0f44d89dc1a9fc90105c71d1399ccf5bf8ac47bc20e31fd208b41`,
`5481bf3bd31c24c7e6076a72258ec7400b6b71b746f050aadd91c89bb8618d8b`,
`9ab90693a6f83ca76ecde148921443ead86b845ef3e02c0535e396177778e77b`,
`d9e2b5b059c781ad996c214dee39c4f935ec4558f886ab56b028d5abdb1e74e0` and
`1826b4c4b970eac1af9e3e3d5dd5ddf50c7782eb9e47095ae30c3ca5ed6c392e`; and
P05 shared/construction/transition tests
`4266da563915eb3bb9a1f85f44de7240b787e233c115de3f2ec6502289baea27`,
`f54dfa2d77bd922c716614aa9d4b6539139edf545ed90582e5f4138ceb2affc4` and
`9c625b1c4de7ee23f54ba1cbddd3833ed0819ffa570081ad09fb16c917a72e39`.
P05 was confirmed at 5/7 and overall progress at 37/89 before this change.

The read-only comparison trace found these deliberately unchanged later-phase
consumers: P04 canonical sessions/continuations compare publication,
parser/source snapshot, layout and pagination inputs; `ReaderCardIdentity` and
checkpoint payloads compare publication fingerprint, legacy layout fingerprint,
pagination version and physical-card signature; checkpoint restore compares
same-layout/same-pagination exact signatures before its existing semantic
branch; whole/segmented/memory caches compare their own cache key, parser,
layout/settings/viewport and format versions. `BookCacheService`, segmented
cache format 3, checkpoint format/schema 1, and all manifest/key/record
formats remain P06/P07/P08-owned. No call site was modified.

### Implemented pure boundary

`reader_layout_contract.dart` now retains immutable typed canonical evidence
for `LayoutMetricsIdentity` (F195–F196), `SourceCompatibilityIdentity`
(F197–F202), `PaginationAlgorithmIdentity` (F203–F204),
`RendererLayoutIdentity` (F205–F206), and `ReaderCompatibilityIdentity`
(F207–F208). The existing layout/pagination/card consumer strings remain
separate and byte-identical; typed F195–F208 evidence is not wired into
pagination, cache, checkpoint, restore, settlement or publication behavior.

`ReaderCompatibilityClassifier` validates both evidence sets before comparing:
required evidence presence; SHA-256 component and F208 composite digests;
canonical record kind/revision/tag/type/order/trailing-byte rules; UTF-8,
finite-number, negative-zero and collection invariants; source/parser/
structural links; renderer links; and F208 links to all four component
fingerprints. Well-formed evidence outside the explicit revision-support set
returns `unsupported_revision`; malformed or contradictory evidence returns
`corrupt_evidence`; absent evidence returns `incomplete_evidence`. Corrupt
precedes unsupported, and both precede comparison.

The result hierarchy uses stable snake-case wire names and deterministic
reason bytes. It returns `exact_compatible`, `layout_metrics_changed`,
`source_compatibility_changed`, `pagination_algorithm_changed`,
`renderer_layout_changed`, `multiple_authoritative_changes`,
`incomplete_evidence`, `corrupt_evidence`, or `unsupported_revision`.
Changed dimensions always use fixed layout/source/pagination/renderer order;
reason bytes do not contain timestamps, localized prose, source text, cards,
display/window/page/request indexes or runtime object identity.

Exact compatibility requires complete, supported, recomputed F195–F208
evidence and equality of all four authoritative layers. It only permits later
exact-reuse/card validation; it never permits semantic migration. A missing
requested physical-card signature remains an exact miss, not semantic
migration. A valid genuine single/compound difference may only be considered
later for semantic migration; it does not resolve an anchor, select a card,
publish, settle, write/admit cache data or rewrite a checkpoint. Every result
has zero cache, checkpoint, publication and settlement authority. Book ID is
not a layout metric and is not accepted by this classifier; P06/P08 retain
separate fail-closed book-scope isolation.

### Files and focused evidence

Production/model files changed: `lib/models/reader_layout_contract.dart`, new
`lib/models/reader_compatibility.dart`,
`lib/services/reader_layout_contract_service.dart`, and new
`lib/services/reader_compatibility_classifier.dart`. Focused production test:
`test/reader_contract/layout/reader_compatibility_classifier_test.dart`.
Documentation changed: `test/reader_contract/README.md`, the reliability plan
and this append-only ledger.

- `rtk dart format lib/models/reader_layout_contract.dart lib/models/reader_compatibility.dart lib/services/reader_layout_contract_service.dart lib/services/reader_compatibility_classifier.dart test/reader_contract/layout/reader_compatibility_classifier_test.dart`: 5 files, 0 final changes, 0.07 s, exit 0.
- `rtk dart analyze lib/models/reader_layout_contract.dart lib/models/reader_compatibility.dart lib/services/reader_layout_contract_service.dart lib/services/reader_compatibility_classifier.dart test/reader_contract/layout/reader_compatibility_classifier_test.dart`: no issues, 1.3 s, exit 0.
- `rtk flutter test --no-pub -r compact test/reader_contract/layout/reader_compatibility_classifier_test.dart`: 22/22 tests, 43 classifications, 3.0 s, exit 0.
- Existing P05-003 shared/construction/transition command: 36/36, 20.0 s, exit 0.
- Existing P05-005 transient-invariance command: 4/4, 10.0 s, exit 0.
- Existing font-gate/support command: 27/27, 11.0 s, exit 0.
- Affected publication/state/renderer interaction command: 60/60, 10.0 s, exit 0.
- Final combined focused P05 command (classifier 22 + transient 4 + shared 36 + font/support 27 + affected 60): 149/149, 18.214 s, exit 0.
- Read-only `rtk sha256sum`, `rtk rg -n "[ \\t]+$"`, `rtk git diff --check` and scoped status checks: frozen hashes matched; only four pre-existing Markdown trailing spaces were found; diff check was clean; 0.2 s, exit 0.

Focused classifier maxima were 43 classifications, 1,089 canonical result
bytes, 208 canonical reason bytes and four changed dimensions. Result source
text bytes retained, mutable indexes retained, and cache/checkpoint/
publication/settlement mutations caused by classification were all zero.

No complete P03/P04 matrix, full Flutter suite, device/emulator/integration
test, network command, generator, migration or Git mutation command ran. No
cache/checkpoint format, schema, key, migration, persistent version,
dependency/lockfile, font asset, parser/source behavior, P03/P04 fixture,
membership, signature oracle, navigation, restoration, settlement or device
behavior changed. P05-007 and P06 were not started.

**Only recommended follow-up.** `TASK-P05-007`: add exhaustive one-field and
runtime transition evidence, explain any legitimate identity/range change, and
run its owned complete P03 construction-order matrix without changing frozen
oracles.

## CHANGE-20260910-029 — Complete P05 layout parity and fingerprint gate

**Phase/task.** P05 / `TASK-P05-007` completed. P05 is `COMPLETED` at 7/7,
overall progress is 39/89, P05 exit criteria and P06 entry criteria are met,
and P06 remains `NOT_STARTED`.

### Pre-edit integrity and unchanged baseline

The working branch was `feature/lazy-random-access-reader` at full HEAD
`9d7716597d95d578699e7a54544d92d5b4b234b6`. `git status --short` showed the
substantial pre-existing modified/untracked work described by the plan; it was
preserved. P04 was confirmed complete at 8/8, P05 in progress at 6/7 and
overall progress at 38/89. P04 source ownership, fixed seeds, plans, work
bounds and final-gate oracle were unchanged.

Pre-edit SHA-256 evidence included P03 full-range
`4505e5730a02ec55a3ba65412e40e1bbf1d672cf1d03a89044382b4b7a7cd425`,
target `1e7fd14dd0c0f44d89dc1a9fc90105c71d1399ccf5bf8ac47bc20e31fd208b41`,
forward/backward `5481bf3bd31c24c7e6076a72258ec7400b6b71b746f050aadd91c89bb8618d8b`,
singleton `9ab90693a6f83ca76ecde148921443ead86b845ef3e02c0535e396177778e77b`,
structural ownership
`1826b4c4b970eac1af9e3e3d5dd5ddf50c7782eb9e47095ae30c3ca5ed6c392e`,
cache `8b3a964273ac407fa452298f9b66f61f4fe9e7cebe8087d0a5940c8aff6de9bd`
and ledger-integrity
`edeefbc6e5703125a10c58d629b8b97e8fec12c90e4b85c154be5d85458dae0a`.
Support hashes included evidence
`1f299d3c9da95f8663b3485e23406fd4c90c0476ba483823315629b1f0558b2a`,
core harness
`f994698f35c750e0ddc3abe2e9c44f986ce475546147983658990d96d7a9ff92`,
cache harness
`abb4de93eb70f28ba5dd066440d75e77e57a6aad18600b1bc109be53c5aa73a7`,
ledger `55006dd64d75d1db37ce6d105b2b7b0c09c92f08f5e2715f21af5b27923ed6a`,
layout environment
`cd39e69820cc11ba643efb51e4eb9f946944fe834506a1711108b9381179e629`
and fixture
`7ad3e436db30bc897944d07cf792ce905498570a68aac04de31f36ce214ee9ba`.
The unchanged P04 final-gate file remained
`88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`.

Before any expectation changed, the complete unchanged P03 construction-order
matrix passed 57/57. Expected and actual ordered source slices, structural
owners, visible text and construction order agreed; there was no gap, overlap,
duplicate, reorder, omission or failure reason. The reviewed standard ranges
were nine cards:

1. `0:[0,20), 1:[0,22)`
2. `2:[0,20), 3:[0,23)`
3. `4:[0,10), 5:[0,10), 6:[0,12), 7:[0,198)`
4. `8:[0,33)`
5. `9:[0,19), 10:[0,18)`
6. table canonical row `11:[0,1)` with authored UTF-16 ownership `[0,136)`
7. `12:[0,56), 13:[0,50), 14:[0,37), 15:[0,63)`
8. `16:[0,22)`
9. `17:[0,52), 18:[0,33), 19:[0,55)`

The existing P05 bounds were retained: 2,048 UTF-16 units per exact font slice,
11 role requests, 10 unique variants, six scaled sizes, two widths, 33 metric
runs, 32,768 bytes per evidence record and 25 records/819,200 bytes retained,
with zero copied source text.

### Exhaustive F001–F211 mutation result

The table-driven oracle names every authoritative field from the production
registry exactly once and classifies every mutation through the production
compatibility classifier. It passed 211/211 fields: 120 layout-metrics changes,
7 source-compatibility changes, 1 pagination-algorithm change, 36
renderer-layout changes, 34 physical-card composite changes, 4 validation-only
changes, 1 same-effective-value case, 1 transient/diagnostic exclusion and 7
typed invalid-mutation rejections. Every case proved its downstream result and
all classifier authority flags remained false.

The focused cases prove exact finite binary64 encoding without decimal
rounding, distinct subpixels, `-0.0` normalization, NaN/infinity rejection,
clamped raw side margins with equal effective values, different raw settings
with equal resolution, order-sensitive ordered collections, canonically sorted
semantic sets/maps, and strict rejection of missing/duplicate/reordered/
unknown/trailing canonical fields. F208 is recomputed exactly from
F196/F202/F204/F206/F207. A changed claimed digest without matching evidence is
corruption. Display/page/card/controller/window/request/runtime-object indexes
remain absent from identity.

### U-01–U-10 production probes and corrections

- **U-01 border geometry:** exposed a P05-owned defect. Flutter's decorated
  `AnimatedContainer` inset the body constraint by the 1.8-pixel stroke on all
  sides (`298×620` contract body versus `294.4×616.4` descendant). The earliest
  shared correction moved the border into a `Positioned.fill` paint-only,
  pointer-ignoring overlay. The production descendant is now exactly
  `298×620`; F034–F039 policy is preserved and no source range changed.
- **U-02 deck authority:** standard full-screen and a bounded `320×600` parent
  prove exact deck/contract/card width and height agreement. Incompatible
  `MediaQuery.size` evidence rejects instead of replacing the bounded deck.
- **U-03 publisher structure:** parser-produced ordinary publisher prose,
  poem, stanza, quote, epigraph and letter structures preserve segmentation,
  whitespace/line breaks, padding, alignment, ownership and exact resolved/
  rendered height.
- **U-04 tables:** parser-decoded row/column spans preserve canonical occupancy,
  fixed columns, row heights, padding, borders, horizontal extent and source
  ownership; the widget consumes the resolved grid without remeasurement.
- **U-05/U-06 font transition/coverage:** all renderer-used roles, weights and
  styles are covered by terminal bundled evidence. Terminal, pending, missing
  asset, digest mismatch, incomplete variants, unavailable/contradictory
  metrics, stale capture, cancellation, changed metrics and changed opaque
  fallback observations were exercised. A valid observable transition creates
  a new layout identity and `layout_metrics_changed`; no resolved platform face
  is invented. Pending/rejected outcomes have zero pagination, publication,
  cache, checkpoint and settlement authority.
- **U-07 diagnostics:** DPR, accessibility bold, high contrast and brightness
  preserve exact production logical text/body metrics, remain diagnostic and
  stay excluded from identity. No contract revision was required.
- **U-08 locale/direction/alignment:** explicit LTR/RTL, null-direction LTR
  fallback, source alignment override and all four supported alignments agree
  across painter/widget wrapping, line bounds, height and hit/selection
  positions. Captured direction/alignment changes produce distinct identities.
- **U-09 images:** exposed a P05-owned defect in the public shared resolver,
  which accepted stale/contradictory caller-supplied image evidence. The
  earliest shared correction validates nonempty bytes, positive intrinsic
  dimensions, recomputes the byte SHA-256 and recomputes the canonical
  `reader-image-metrics` digest before resolution. Provisional evidence cannot
  finalize; terminal evidence creates a fixed contain/no-upscale box; later
  frames cannot resize it; genuine new evidence changes identity; stale or
  contradictory evidence rejects atomically.
- **U-10 active/preview freshness:** unchanged contracts preserve cached
  layout, genuine changes replace stale preview/card layouts, promotion never
  retains stale preview, every Speed Reader state preserves canonical geometry,
  wrappers change interaction only, and stale/incomplete candidates cannot
  publish or checkpoint an old physical identity.

After the U-01 production correction its focused probe passed, the then-current
focused P05 gate passed 150/150 and the complete P03 matrix passed 57/57 before
further correction. After U-09 its focused probe passed, the then-current
focused P05 gate passed 156/156 and P03 again passed 57/57. These corrections
did not touch pagination construction, cache, restoration, navigation,
settlement or persistence.

The structural parity matrix covers ordinary/continued and publisher
paragraphs; heading text, exact 20-pixel gap and divider; bold/italic/
bold-italic rich spans; links/footnotes; ordered/unordered/nested lists and
markers; decoded span tables; preformatted blocks; images; LTR/RTL/alignment;
nonlinear scaling; selection/highlights/notes/character markers; and all Speed
Reader states. It compares shared constraints, ordered span runs, exact line
and UTF-16 boundaries, baselines, block heights, overflow, ownership, block
fingerprints and physical-card identities without broad pixel tolerances.

### Controlled P03 physical-identity transition

One shared P03 support oracle now obtains finalized canonical cards from the
P05 contract and verifies the single reviewed standard range/signature list.
Per-path expected values, seeds, plans, source fixture, construction-order
comparisons, authored ownership and P04 seam rules were not changed. The P04
final-gate file was not edited. Cache-harness publications remain independently
scoped and compare internally; their different F197 publication identity is
not mistaken for nondeterminism.

All nine ranges above are unchanged. Only identity changed because the legacy
rounded controlled-layout string was replaced by the full immutable identity,
including nonzero F016/F045 bottom safe inset and shared F079–F211 typography,
font evidence, renderer, block and card identity fields (M-01–M-09). The
independently reviewed old → new signatures are:

1. `900dcb5cd6f865b023e2993eddc2af0717708ed7e97eacc90bd428169b801ad2` → `3f27702d77cf7eafc56e3eb12b7de0cabf19b216b712b6bd8cbf5696a01a9e79`
2. `c65ab813c185dcb053f18212e692cb32185eb9bdcf0dd3727b9e91dcbc0d027e` → `68de2d916ad4d9611b4b7e3c6fc94fada8ace6a6ec964d7e71f58bfe454be84b`
3. `a5359dd65eed855dabd8a5463b0a04d73c7a5380cedca86a9ce670949cf64906` → `aff523a0850637ed2f2f12400a33d5667832a1a805589237b7318acdd59d4295`
4. `80da94b0e869efae9a7bc7997053d8327d404fd3f3897bad890aac1e074fbfb3` → `6f82dc719931c405d9b6eb327df84bbcba006c4082e7d063ec12dd0f1e3ba5c8`
5. `0f99c5663483c1a5e281e37368ca4b7ba9e51afba5e14336f2c8051211b55f63` → `8c0dbd53308d12f402dc6f3a1ad64a868dc1302df123786d48d3c96e9f2c3e58`
6. `6390952d896803c796cbf9d53e385fd176472a30f1e6be2ef99e55650342f8eb` → `e99fbe116c39d6842abb2d8ba459996e30515208d87920a96f99c75f9336bd8a`
7. `d6390d57d281d9c783feb6ce8e5b292395ed2bdbd47dd5c43f134d87c2a68316` → `c16cf34e3db4017446460407c71d39298bd8c4a02cb4ffad285d5c68fd3240c5`
8. `8202c7593986184e7bd43ce6e2dd5c43922af33bc6f902f79adee6ff2215eee5` → `bcca2d33d48c3f25a1eb2c9973bf4ddbdc6252b8ff28e222ca49a1836fb552a8`
9. `5f823ecc03e20c9bf069c1ac4b831bbc2b2d5dbd20b4fa755afda489af72bb4e` → `05402dceb87fd09959ab8d6f36cc949ddf775d2735864b4f499c3a23c2d49580`

No range had a measured-capacity change. Ordered source slices, visible text,
structural ownership and every equivalent construction order stayed exact.

### Final deterministic evidence and bounds

- Final focused P05 command: 161/161, reporter elapsed 1:22, exit 0.
- Final complete P03 run 1: 57/57, 3:19, exit 0.
- Final complete P03 run 2: 57/57, 3:26, exit 0.
- The sorted semantic evidence streams normalized only sandbox suffixes and
  gzip checksums; both SHA-256 values were
  `fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`.
  Ordered identities/ranges, visible-source coverage, singleton/split and cache
  diagnostics were identical.
- One pre-final invocation used the nonexistent filename
  `reader_p03_failure_ledger_integrity_test.dart` and produced a load/startup
  error before a semantic ledger result. It was retried once with the frozen
  `p03_failure_ledger_integrity_test.dart`, as permitted; no semantic failure
  was retried.
- Unchanged P04 final gate: 3/3, 4:46, exit 0. Its hash remained exact.
- Frozen P02 paginator parity plus fixture/parser controls: 9/9, reporter
  elapsed 0:03 (4.79 s wall), exit 0.
- Scoped `dart analyze`: no issues, 2.24 s, exit 0. An initial analysis found
  one unused test import; removing it changed no behavior and its affected
  39/39 shared-contract test rerun passed.
- `dart format` over eight changed Dart files: 0 changes, 0.35 s, exit 0.
- Final read-only `git diff --check`: clean, exit 0. Scoped trailing-whitespace
  review found only eight pre-existing Markdown hard-break lines; changed Dart
  files had none. Final hashes reconfirmed every P03 matrix test and the P04
  gate unchanged; only the shared P03 support/oracle files changed as reviewed.

Retained maxima are: contract 4,696 bytes; resolved block 1,462 bytes;
resolved card 1,728 bytes; font-evidence record 32,768 bytes and retained total
819,200 bytes; compatibility result 1,089 bytes and reason 208 bytes; 10 unique
variants, six sizes, two widths and 33 metric runs; canonical image-evidence
digest input 155 bytes. Canonical work remains capped at 48 source units and
eight finalized cards per operation (110 atomic entries normal/158 recovery);
the standard P03 fixture has 20 source units/nine cards but is advanced through
bounded operations rather than whole-book pagination. Source-text bytes in
layout/font/image/classifier evidence are zero; mutable-index identity bytes,
stale cards surviving a genuine transition and unauthorized cache/checkpoint/
publication/settlement mutations are all zero. No whole book is copied into
evidence and pending/rejected evidence has zero authority.

### Files and status changes

Production corrections: `lib/widgets/reading_card.dart` and
`lib/services/reader_layout_contract_service.dart`. Focused tests:
`test/reader_contract/layout/reader_layout_contract_shared_test.dart`,
`reader_compatibility_classifier_test.dart`, `reader_font_evidence_gate_test.dart`
and `reader_transient_state_invariance_test.dart`. Controlled P03 shared
support/oracle: `test/reader_contract/pagination/reader_card_pagination_evidence.dart`
and `reader_core_pagination_harness.dart`. Documentation:
`test/reader_contract/README.md`, the layout-contract design, reliability plan
and this append-only ledger.

`REQ-014`, `REQ-015`, `REQ-016` and `REQ-017` are promoted to `VERIFIED`.
`REQ-002`, `REQ-035` and `REQ-042` remain unverified. `REQ-051` remains
`IMPLEMENTED_NOT_VERIFIED` for its P06/P10 obligations. `RISK-005` and
`RISK-006` are `MITIGATED_BY_P05`; `DISC-004` is resolved for P05.

No P04 oracle, seed, plan, bound, source ownership or final-gate file changed.
No persistent format/schema/key/version, dependency, lockfile, font asset,
fixture/parser source, cache/restoration/navigation/settlement/lifecycle or
device behavior changed. No full Flutter suite, network, generator, migration,
Git mutation, device, emulator or integration-device command ran.

**Only recommended follow-up.** `TASK-P06-001`: specify canonical display
segment keys and records with source interval, ordered cards, predecessor and
successor boundary evidence, continuation identity, final P04/P05 source/
layout/pagination versions and checksum. Do not begin migration or reuse until
that evidence contract is reviewed.

## CHANGE-20260911-030 — Specify canonical display-cache segment contract

**Phase/task.** P06 / `TASK-P06-001` completed as a design and discovery
task. P06 is `IN_PROGRESS` at 1/7, overall progress is 40/89, P06 entry
criteria are Yes, P06 exit criteria remain unmet, and P07 entry criteria remain
unmet.

### Current cache-path inventory and versions

The audit covers the whole gzip display cache in
`lib/services/book_cache_service.dart` (application documents/book_cache,
display_manifest.json and sanitized-key .json.gz payloads), the segmented gzip
display cache in `lib/services/segmented_display_cache_service.dart`
(book_cache/display_segments/safe(cacheKey)/manifest.json and
segment_start_end.json.gz), the in-process
`DisplaySectionMemoryCache`, cached `DisplayRangeResult`/maps, retained
ReaderScreen cache helpers, section-scoped rebased segment writes,
chapter-layout records, cleanup/invalidation call paths, and P03/P04 cache
harnesses/final-gate evidence.

Reconfirmed current declarations and use sites are: whole display-cache format
3, display-layout version v14, segmented display-cache format 3, pagination
algorithm nalori_cards_v16_lists, checkpoint record format 1, checkpoint-store
schema 1, and stable-location version 2. No value changed. The contract records
where each is declared, serialized/propagated, read, or compared; in
particular the whole display decoder presently does not compare its serialized
v field, while segmented manifest/payload compatibility compares its format
and legacy layout fields.

### Contract result

New authoritative design artifact:
`docs/development/nalori-reader-canonical-display-cache-contract.md`.

It records the current field-level authority inventory and the missing
canonical evidence: stable source snapshot/interval identity, finalized P04
cards with exact slices/owners/roles and UTF-16 or table-row intervals, final
P05 F196/F206/F208 plus P04 F202/F204/F207 compatibility, F209/F210/F211
physical evidence, predecessor/successor seams, strict continuation/frontier
state, SHA-256 record integrity, and bounded ownership.

The future CanonicalDisplaySegmentKey has 13 encoded components and one
derived SHA-256 digest (14 named fields). The future
CanonicalDisplaySegmentRecord has 32 top-level fields; each ordered finalized
card has 11 fields. Key input excludes all mutable display/card/window/request
indexes, raw settings, rounded geometry, delimiter strings, timestamps,
eviction metadata, and runtime object identity. Filenames and manifest lookup
use only the opaque canonical key digest; strict record validation recomputes
all components.

The contract requires exact internal card seams, predecessor-to-first and
final-to-successor/frontier seam evidence, book-start/logical-end sentinels,
restart/parent/chain linkage, continuation digest, previous-finalized boundary,
next-unconsumed source cursor, and ordered reconstructible frontier evidence.
It preserves the P04 rule that previousFinalizedBoundary supplies publication
seam authority and nextSourceCursor cannot replace that seam when a frontier is
nonempty. Equal integer ranges, section coverage, or equal key/F208 alone
cannot join or publish records.

Sixteen future typed outcomes are specified, including exact canonical
compatible, absent/incomplete/incompatible safe misses, source/layout/renderer/
pagination/revision changes, corrupt encoding/checksum, boundary/continuation/
card mismatch, stale generation, cross-book scope, corrupt compatibility
evidence, and regeneration required. Their cards/join/publication/pagination/
memory/disk/migration permissions are specified as future P06-002 behavior;
no action was wired here.

### Migratability and bounds

The complete current-record matrix resolves DISC-002: whole v3, segmented v3
manifest/payload, section-scoped rebased records, and memory entries are
nonmigratable safe misses; transient ranges and chapter-layout records are
non-authoritative lookup hints; malformed data is corrupt/unsupported. A live
validated P04 continuation or finalized card/state may be structurally
reused only while constructing a new record in the same accepted P04/P05
transaction, never as migration of a legacy persistent display record.

Inherited bounds remain P04's finite 48-source/eight-card advancement,
110/158 work envelope, bounded active/frontier/continuation state, and P05's
finite evidence bounds. Legacy 20 MiB/5 MiB whole, 48 MiB/3 MiB segmented, and
8 MiB approximate memory policies were observed only. P06-006 must measure
and set future segment/manifest/card/source/encoded/decoded/decompression/
chain/pinning budgets and atomic-retention behavior; no new numeric budget was
finalized.

### Tracking and unchanged scope

Changed files are this append-only ledger,
`docs/development/nalori-reader-reliability-plan.md`,
`docs/development/nalori-reader-canonical-display-cache-contract.md`, and
`test/reader_contract/README.md`. The plan now marks TASK-P06-001 complete,
P06 1/7, overall 40/89, P06 entry criteria Yes, and DISC-002 resolved. It
retains REQ-051 as IMPLEMENTED_NOT_VERIFIED; RISK-007 remains unresolved by
compatible persistent-cache implementation despite P04 fail-closed mitigation,
and RISK-008 remains open.

Only read-only source/document/search/status inspection and documentation
edits occurred. No Flutter/Dart tests, device/emulator/integration tests,
generators, migrations, network, cache writes/deletes, or Git mutation ran.
No production code, Dart test, cache record/key/version, dependency/lockfile,
P03/P04/P05 oracle, parsed source, user data, checkpoint, or device behavior
changed.

**Only recommended follow-up.** `TASK-P06-002`: implement the shared
memory/disk strict canonical record validator and typed fail-closed admission
outcomes defined by this contract. Do not implement migration, invalidation,
eviction budgets, physical version changes, or cache reuse beyond validated
candidate admission in that task.

## CHANGE-20260911-031 — Correct empty-source font-evidence authority

**Scope and status.** This is a bounded P04/P05 compatibility correction, not
`TASK-P06-002`, and completes no reliability task. P04 remains `COMPLETED` at
8/8, P05 remains `COMPLETED` at 7/7, P06 remains `IN_PROGRESS` at 1/7, and
overall progress remains 40/89. `TASK-P06-002` remains incomplete. Its pending
production and test patch was captured before this correction and retained
byte-identically; the next resumed P06-002 entry therefore uses the next
chronological suffix, expected to be `CHANGE-20260911-032`.

### Isolated reproduction and owning layer

Before editing, the exact P04 test
`[TASK-P04-003] chain, cadence, and bounded index 48 sources, eight cards,
request exhaustion, and repeat chain` was run alone. It failed at 12/13 in
25.505 s with `Bad state: P03 font evidence has no terminal authority.` from
`ReaderCorePaginationHarness.install`, before any P06 admission assertion.
The fixture retains 50 distinct stable empty source records; its first required
source-cadence checkpoint is after the exact first 48 sources. Those sources
normalize to 48 ordered empty readable representations with distinct stable
owners and exact `[0,0)` slices. They resolve as ordinary empty paragraphs:
zero spans, headings, dividers, list markers, tables, preformatted content,
rich decorations, replacement glyphs or other structural text; the source
repertoire length is zero.

Two defects were isolated. The immediate 12/13 failure was harness-owned: the
next subcase passed a complete 6,000-UTF-16-unit unbroken source to the font
gate as bootstrap delivery evidence, exceeding the production 2,048-unit
source bound. The harness then collapsed the typed incomplete-coverage result
to its generic terminal-authority error. Independently, the empty-source
capture reached `readyTerminalBundled` only by running 33 meaningless empty
TextPainter probes, so production font-evidence/layout construction lacked a
canonical terminal no-text-metric branch. The earliest owner of that semantic
gap is the production font-evidence model/gate plus the shared layout-contract
resolver; bootstrap slice selection is the harness boundary. Production EPUB
normalization trims and drops empty parsed chunks, while the production
paginator nevertheless has explicit empty-source consumption semantics used
by the synthetic contract fixture.

At the failing checkpoint the paginator could consume the first 48 sources
without a physical card: 48 entered and consumed, zero atoms, frontier entries,
frontier candidates, finalized cards or published cards, next source cursor at
ordinal 48, source-cadence reason with `sourcesSinceCheckpoint == 48`, and
zero copied source text. Installation failed before that continuation state
could become terminal harness authority.

### Corrected terminal semantics and safeguards

`ReaderSourceFontMetricEvidence` now recognizes an explicitly empty repertoire
only when the pinned stable owner and exact zero-length slice are present, the
recomputed UTF-16 repertoire digest is the canonical empty digest, and the
ordered observation collection is present and empty. A terminal ready outcome
separately retains the complete renderer request catalog. The gate still
validates all required bundled delivery/catalog readiness, family mappings,
asset digests and bounds, but performs zero metric runs for the truly empty
slice.

The shared layout resolver is final authority over whether the repertoire can
render or measure text; raw `trim().isEmpty` is never sufficient. It recomputes
the exact slice/repertoire digest and canonical evidence bytes and validates
owner, slice, probe revision and delivery binding. Headings/generated headings,
list markers and latent list semantics, heading dividers, tables/cells,
preformatted content, dialogue markers, rich/decorated visible spans,
fallback/replacement glyphs, structural separators and preserved whitespace
that affects layout all force the normal full evidence gate. Every nonempty
renderer-used repertoire retains the 11-role catalog, at most 10 variants,
six sizes, two widths and all 33 required observations. Missing, incomplete,
pending, stale, cancelled, contradictory, corrupt or falsely claimed empty
evidence remains rejected. An empty-to-nonempty transition changes repertoire
and compatibility identities and requires re-gating. No glyph, metric, text,
layout content or physical card is fabricated.

The harness now bounds only its delivery/bootstrap slice to 2,048 UTF-16 units
and binds an empty bootstrap to its real source owner/exact slice. Existing
nonempty bootstrap identity remains unchanged, preserving P03 signatures. The
real production evidence gate, shared contract service and paginator remain in
the test path; no algorithm was copied into tests.

### Files changed

Production: `lib/models/reader_font_evidence.dart`,
`lib/services/reader_font_evidence_gate.dart`, and
`lib/services/reader_layout_contract_service.dart`.

Focused tests/harness:
`test/reader_contract/pagination/reader_core_pagination_harness.dart`,
`test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart`,
`test/reader_contract/layout/reader_font_evidence_gate_test.dart`, and
`test/reader_contract/layout/reader_layout_contract_shared_test.dart`.

Documentation: `test/reader_contract/README.md`,
`docs/development/nalori-reader-layout-contract-design.md`,
`docs/development/nalori-reader-reliability-plan.md`, and this append-only
ledger.

### Verification evidence

- Scoped format: seven Dart production/test files formatted cleanly; the final
  categorical heading/list switch was normalized in 0.116 s, exit 0.
- Scoped analysis: no issues, 1.730 s, exit 0.
- Empty/font-evidence regression gate: 22/22, 8.497 s wall, exit 0.
- Shared layout-contract regression gate: 41/41, 15.507 s wall, exit 0.
- P04 continuation-checkpoint control: 13/13, 29.702 s wall, exit 0.
- Complete focused P05 gate: 165/165, reporter elapsed 1:56, exit 0.
- Unchanged complete P03 matrix: 57/57, reporter elapsed 3:02, exit 0; all
  nine reviewed memberships, boundaries and signatures remained exact.
- Unchanged P04 final gate: 3/3, reporter elapsed 4:32, exit 0.
- Frozen P02 parity/fixture controls: 9/9, 4.224 s wall, exit 0.

One pre-final P03 invocation was interrupted after 39/57 without a failure
because the invoking session ended; the complete rerun above is authoritative.
During development, one harness bootstrap-label attempt was stopped after it
showed identity-only P03 drift with unchanged ranges. The label was restored
before final verification, no oracle was changed, and the final 57/57 run
reproduced every frozen signature.

Two pre-final aggregate commands used nonexistent filenames and therefore had
startup/load errors, not semantic test failures. The first misspelled
`reader_layout_construction_order_smoke_test.dart` by inserting `contract`;
the 164 discovered tests passed but the invocation exited 1 after 1:53, and a
five-file isolation repeated the same load error in 26.207 s, exit 1. The
second omitted `matrix` from
`reader_card_paginator_singleton_expansion_matrix_test.dart`; it was stopped
after the load error at 0:33, exit 130. Both commands were replaced by the
repository-resolved exact commands whose complete green results are recorded
above. No failure was retried as a semantic flake.

For the exact empty case the observed result is zero metric runs, zero glyph
observations, zero physical cards, zero atoms/frontier content and zero copied
source text. The first 48 distinct stable sources preserve the source-cadence
checkpoint at cursor ordinal 48 with bounded 48-source/eight-card construction
limits and reconstructible continuation state. A mixed empty/nonempty/empty
case preserves canonical order and obtains complete evidence only for its
nonempty slices.

### Unchanged scope and handoff

Pre/post SHA-256 checks confirm byte identity for the pending P06 production
and test patch: `canonical_display_segment.dart`,
`canonical_display_segment_admission.dart`,
`canonical_display_segment_admission_test.dart`, and the pending P06 admission
wiring in `reader_screen.dart`. No P06 admission behavior or canonical
display-cache contract changed. No production cache format/key/version,
migration, invalidation, eviction or live reuse changed; no checkpoint/schema,
dependency, lockfile, font asset, fixture, P03/P04 oracle, parser source,
device behavior or unrelated dirty work changed. No P06-002 acceptance, full
Flutter suite, network, generator, migration, device, emulator,
integration-device or Git mutation command ran.

There is no new blocker. Resume only `TASK-P06-002` verification and completion
using the preserved pending patch; do not broaden it into migration, eviction,
versioning or live cache reuse.

## CHANGE-20260912-032 — Implement strict canonical display-cache admission

**Scope and status.** `TASK-P06-002` is complete. P04 remains `COMPLETED` at
8/8, P05 remains `COMPLETED` at 7/7, P06 is `IN_PROGRESS` at 2/7, and overall
progress is 41/89. This is a logical admission boundary only: P06 exit criteria
and P07 entry criteria remain unmet; `REQ-009` and `REQ-010` remain unverified;
`REQ-051` remains `IMPLEMENTED_NOT_VERIFIED`; RISK-007 retains its P04
fail-closed mitigation and RISK-008 remains open.

### Completed model, codec and admission hierarchy

`CanonicalDisplaySegmentKey` encodes the exact 13 approved components and a
derived SHA-256 digest. `CanonicalDisplaySegmentRecord` seals all 32 tagged
fields, including the pinned source interval, P05 compatibility evidence,
ordered finalized cards, both boundary proofs, continuation and manifest/checksum
bindings. Each finalized-card record has its exact 11 tagged fields.
`CanonicalDisplaySegmentCodec` is the one strict TLV serializer/decoder;
`CanonicalDisplaySegmentAdmission` routes disk bytes through decode and memory
records through the same encode/decode path before one validator evaluates
compatibility, source/card/payload/F209/F210/F211, seam and continuation proof.

The resumed audit found and corrected three narrow validator defects in the
preserved patch: direct-record admission now receives the explicit continuation
chain cap; source owners must be the exact ordered pinned `[start,end)` span,
not merely resolvable members; and key boundaryRole must match the left/right
proof shape. No cache reuse or publication behavior was added.

All 16 typed outcomes are exercised through the real boundary: exact,
absent/incomplete/source/layout/renderer/pagination/unsupported safe misses;
corrupt encoding, boundary, continuation, card, stale, cross-book and corrupt
compatibility rejections; and legacy `regenerationRequired`. Every outcome,
including exact, exposes zero join, publication, cache-write, checkpoint and
settlement authority; exact returns only an immutable candidate. Disk and
memory candidates produce byte-identical canonical outcome evidence. Legacy
whole, segmented, section-scoped and memory records remain nonauthoritative
safe misses, and ReaderScreen continues bounded source regeneration.

### Boundary, continuation and size evidence

The validator recomputes checksum/manifest/source/compatibility/card evidence
and rejects gaps, overlaps, duplicates, reordered interval owners, stale
identities and merely integer-adjacent islands. It preserves
`previousFinalizedBoundary` as the publication seam and `nextSourceCursor` as
next-unconsumed-input evidence; empty/nonempty frontier rules and the
source-4-frontier/source-5-next-cursor case remain P04-owned and unchanged.

The final focused sample maximum across standard and split-stress records was:
key 754 bytes, complete record 15,376 bytes, card record 2,524 bytes, combined
boundary proof 409 bytes, continuation 3,884 bytes, and 67 inspected canonical
fields (13 key + 32 record + 11 per two cards). It contained at most two cards
and two source slices. Source-text bytes in key/continuation identity, mutable-
index bytes in identity and mutations caused by rejection were all zero. The
test-only caps remain 1 MiB record, 96 cards, 432 slices and chain ordinal 25;
P06-006 still owns release budgets.

### Files changed

Production: `lib/models/canonical_display_segment.dart` and
`lib/services/canonical_display_segment_admission.dart`. The existing
`lib/screens/reader_screen.dart` legacy-safe-miss wiring was reviewed and is
unchanged by this completion.

Focused test: `test/reader_contract/pagination/canonical_display_segment_admission_test.dart`.
Status/documentation: this ledger,
`docs/development/nalori-reader-reliability-plan.md`,
`docs/development/nalori-reader-canonical-display-cache-contract.md`, and
`test/reader_contract/README.md`.

### Verification

- Scoped `dart format` over the four P06 Dart files: 0.340 s, exit 0.
- Scoped `dart analyze` over the same files: no issues, 3.100 s, exit 0.
- Final P06 admission suite: 7/7, reporter elapsed 0:04, exit 0.
- P04 continuation/reconstruction control: 13/13, reporter elapsed 0:26,
  exit 0; the repaired 48-source continuation case remains green.
- P04 canonical publication transaction: 9/9, reporter elapsed 1:04, exit 0.
- Relevant P05 compatibility classifier: 27/27, reporter elapsed 0:27,
  exit 0; shared/layout-transition identity controls: 42/42, reporter elapsed
  0:11, exit 0.
- Unchanged P04 final gate, including real-cache fail-closed regeneration:
  3/3, reporter elapsed 4:22, exit 0.

The external empty-source repair from `CHANGE-20260911-031` was present before
this work. The pre-existing P06 production/test diff was byte-identical across
that external repair; this task changed only the three P06 files named above to
close the verified admission gaps. No P03 membership, boundary, signature or
oracle changed, and no complete P03 cold/warm matrix was run.

No persistent canonical cache format, key, schema or version was activated or
changed. No production canonical disk write, live reuse, migration,
invalidation, deletion, eviction, checkpoint/restoration/navigation/settlement
behavior, dependency/lockfile, fixture, font asset or device behavior changed.
No Git mutation occurred. The only recommended next scope is `TASK-P06-003`:
prove cold/warm memory/disk reuse, eviction and regeneration equality against
the frozen P03 ordered-identity matrix through the existing P04 transaction.

## CHANGE-20260912-033 — Prove canonical cold/warm cache equivalence

**Scope and status.** `TASK-P06-003` is complete. P04 remains `COMPLETED` at
8/8, P05 remains `COMPLETED` at 7/7, P06 is `IN_PROGRESS` at 3/7, and overall
progress is 42/89. P06 exit criteria and P07 entry criteria remain unmet.
`REQ-009` advances only to `IMPLEMENTED_NOT_VERIFIED` because the evidence is
controlled and live physical rollout remains deferred; `REQ-010` remains
unverified and `REQ-051` remains `IMPLEMENTED_NOT_VERIFIED`. RISK-007 is
partially mitigated by P04 plus controlled P06 exact-reuse evidence. RISK-008
remains open.

### Pre-edit cache-state trace

The capture was taken on branch `feature/lazy-random-access-reader` at HEAD
`9d7716597d95d578699e7a54544d92d5b4b234b6`; the existing dirty worktree was
preserved. Persistent constants were whole display format 3, display layout
`v14`, segmented display format 3, pagination
`nalori_cards_v16_lists`, checkpoint format 1, checkpoint-store schema 1 and
stable-location version 2. None changed.

Pre-edit SHA-256 values were:

- frozen P03 oracle
  `reader_card_pagination_evidence.dart`:
  `e2686bedd908c4f9e96d5bd7d1cd13cdd5bc542547b9f94408fb8bc6edfaba66`;
- shared production harness:
  `649ee4f40203d3093cdb983bb7787920ec5993913e8867d9d4e9b3a98aacd0f7`;
- fixture manifest:
  `e86242e62601408751f77ebfd7001f4a19fe05ee8f246f435fff889ce94e87da`;
- fixture chapter one:
  `665b5a08248b5ac8951af87f47718f9fc3b82bc3af9e8e4a8e18ce5c27f003f5`;
- fixture chapter two:
  `f2c68d94750df1e9199e31f48346f72beed62adfcf6419d4c3f35d8f58cf6b7e`;
- unchanged P04 final gate:
  `88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`.

The final read-only hash pass reproduced those five frozen oracle/fixture/gate
values exactly; the shared harness changed only by the authorized reusable
P06 record-construction helper.

Cold display construction already ran through
`CanonicalReaderPaginationSession.generateInitial/generateForward` and the
sole `ProgressiveDisplayState.publishCanonical` transaction. Whole,
segmented-disk and section-memory records were legacy derivatives: ReaderScreen
observed them, sent them through `legacySafeMiss`, and performed bounded
canonical source regeneration. Exact P06 admission produced an immutable
candidate with no direct authority. Absent, evicted, incompatible and rejected
candidates likewise required bounded regeneration. Repository-wide route
inspection found mutable display/source maps, window ranges, section-rebased
indexes and integer adjacency only in legacy lookup/assembly paths; none could
prove a canonical key, seam or continuation. Codec/record creation searches
confirmed that no canonical record was written to the live production cache.

### Construction, transport and publication ownership

`CanonicalDisplaySegmentRecordBuilder` is a pure builder. It accepts pinned
source, exact P05 compatibility evidence, finalized P04 cards, accepted
continuation and book-start/restart proof, and emits the P06-002 logical record
and bytes. It derives no authority from display indexes, window ranges,
filenames, generation ids or integer adjacency, and copies no source text into
key or continuation identity.

The policy-free `CanonicalDisplaySegmentMemoryTransport` and explicit-root
`CanonicalDisplaySegmentControlledDiskStore` transport the same logical
record. The latter was used only under sandbox-owned temporary directories and
has no default path, manifest, version constant, ReaderScreen connection or
live writer. Memory candidates encode/decode through the same admission path
as disk bytes. Both routes are: lookup → canonical decode/admission →
book-start/predecessor/restart anchoring → immutable exact candidate → existing
P04 `publishCanonical` validation → atomic publication. The candidate cannot
publish, join, checkpoint, settle, replace an anchor, create continuation
authority or create another record.

### Cache-state, rejection and atomicity evidence

The complete P03 projection compared ordered visible text, stable half-open
coverage, source slices, UTF-16/table-row intervals, owners/roles,
F209/F210/F211, physical-card signatures, both seams, continuation and final
card order under cold generation; warm memory; reopened controlled disk;
memory eviction with disk reload; full memory/disk absence with regeneration;
rejected/stale candidate with regeneration; cached prefix/regenerated suffix;
regenerated prefix/cached suffix; cached middle between two live regions; two
independently admitted segments; and forward, target-first and bounded-backward
construction. Evicting either derivative representation left an already
accepted display byte-identical.

All 16 P06-002 outcomes retain zero direct authority. The focused evidence
covers absent, changed source/parser/layout/renderer/pagination, unsupported
revision, corrupt compatibility/checksum/encoding/card-source-structure,
boundary/continuation mismatch, stale generation and cross-book scope before
regeneration. Numerically adjacent islands without full seam proof are
rejected. Cancellation after admission, a candidate made stale during
validation and an injected failure before P04 commit preserve display,
session, anchor and continuation state byte-for-byte; subsequent valid
regeneration publishes atomically through the same transaction. Checkpoint
source authority is never derived from cache residence.

The two complete internal cache-matrix runs normalized identically to
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`.
The unchanged complete P03 matrix passed 57/57 and retained its frozen
normalized evidence hash
`fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`,
standard memberships
`0–1 | 2–3 | 4–7 | 8 | 9–10 | table 11:[0,1) | 12–15 | 16 | 17–19`,
and split-stress source-7 ranges
`[0,58) | [58,125) | [125,191) | [191,198)`.

### Observed work and storage maxima

These are observations, not P06-006 release budgets: cold source work 14;
safe-miss regeneration source work 14; inspected validation fields 111;
canonical key 786 bytes; record 37,267 bytes; card 4,139 bytes; boundary 6,348
bytes; continuation 6,001 bytes; memory-resident canonical records 76,971
bytes; controlled-store disk records 76,971 bytes; three segments, nine cards
and 20 source slices retained; continuation-chain depth two; six cards in the
largest publication transaction. Copied source-text identity bytes, mutable-
index identity bytes and rejected-result authority mutations were all zero.
Existing P04 work/frontier/continuation bounds remained unchanged; no operation
paginated an entire long book.

### Files changed

Production: `lib/models/canonical_display_segment.dart`,
`lib/services/canonical_display_segment_admission.dart`,
`lib/services/display_section_memory_cache.dart`, and
`lib/services/segmented_display_cache_service.dart`.

Tests/harness:
`test/reader_contract/pagination/reader_core_pagination_harness.dart` and new
`test/reader_contract/pagination/canonical_display_cache_equivalence_test.dart`.

Documentation: `test/reader_contract/README.md`,
`docs/development/nalori-reader-canonical-display-cache-contract.md`,
`docs/development/nalori-reader-reliability-plan.md`, and this append-only
ledger.

### Verification evidence

- Scoped `rtk dart format` over the six Dart files: 0.172 s wall, exit 0;
  final focused test ordering check: 0.078 s wall, exit 0.
- Scoped `rtk dart analyze` over the same files: no issues, 2.446 s wall,
  exit 0; final focused test analysis: no issues, 1.540 s wall, exit 0.
- Standalone P06 admission: 7/7, 8.570 s wall, exit 0.
- Final standalone cache-equivalence matrix: 4/4, reporter elapsed 0:57,
  exit 0; it executed two normalized equality passes.
- Unchanged complete P03 seven-file matrix: 57/57, reporter elapsed 3:48,
  exit 0.
- Combined P04 continuation/publication/final-gate command: 25/25
  (13/13 + 9/9 + 3/3), reporter elapsed 4:47, exit 0.
- Combined P05 classifier/shared-layout command: 69/69
  (27/27 + 42/42), 16.184 s wall, exit 0.
- Frozen P02 parity/fixture controls: 9/9, 4.344 s wall, exit 0.
- Final combined P06 admission/equivalence gate: 11/11, reporter elapsed
  0:56, exit 0; it preceded the final standalone matrix and used the same
  post-audit code.

Exact test commands were:

- `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/canonical_display_segment_admission_test.dart`
- `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/canonical_display_cache_equivalence_test.dart`
- `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart`
- `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart`
- `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/layout/reader_compatibility_classifier_test.dart test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_layout_standard_transition_test.dart`
- `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_parity_test.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart`
- `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/canonical_display_segment_admission_test.dart test/reader_contract/pagination/canonical_display_cache_equivalence_test.dart`

Read-only hash, whitespace and scoped-diff checks completed after documentation
updates.

One pre-final cache-equivalence invocation was interrupted with exit 130 after
physical disk futures were found to be waiting under widget fake time. It had
no assertion or semantic failure. The physical I/O boundary was moved through
`WidgetTester.runAsync`; all complete runs above then passed deterministically.

No production persistent format/key/schema/version, live cache path, migration,
invalidation/deletion/quarantine policy, final eviction/pinning/retention/
manifest/decompression policy, parsed source, user data, checkpoint,
restoration/navigation/settlement behavior, dependency/lockfile, fixture,
authored P03/P04/P05 oracle or device behavior changed. No network, generator,
migration, full-suite, device/emulator/integration-device or Git mutation
command ran. P06-004 through P06-007 were not started. The only recommended
next scope is `TASK-P06-004`: controlled derivative-only invalidation for
old/incompatible/noncanonical display records while preserving parsed source,
user data and checkpoint authority.

## CHANGE-20260912-034 — Implement scoped display-derivative invalidation

**Scope and status.** `TASK-P06-004` is complete. P04 remains `COMPLETED` at
8/8, P05 remains `COMPLETED` at 7/7, P06 is `IN_PROGRESS` at 4/7, and overall
progress is 43/89. P06 exit criteria and P07 entry criteria remain unmet.
`REQ-046` advances only to `IMPLEMENTED_NOT_VERIFIED`; migration, release
bounds and physical rollout remain. `REQ-009` and `REQ-051` remain
`IMPLEMENTED_NOT_VERIFIED`, and `REQ-010` remains unverified. RISK-008 is
partially mitigated by this scoped evidence, not closed.

### Pre-edit storage and deletion inventory

The inventory was captured on `feature/lazy-random-access-reader` at
`9d7716597d95d578699e7a54544d92d5b4b234b6`; the substantial existing dirty
worktree was preserved. Persistent values were whole-display format 3,
display-layout `v14`, segmented format 3, pagination
`nalori_cards_v16_lists`, checkpoint record format 1, checkpoint-store schema
1 and stable-location version 2. None changed.

Display derivatives were: whole gzip files plus `display_manifest.json` under
the book-cache root; segmented and section-scoped gzip ranges plus one
`manifest.json` beneath `display_segments/<safe cache key>`; process-local
`DisplaySectionMemoryCache` entries; and chapter-layout
`chapter_layout.json`/`chapter_layout_records/<safe key>.json`. Whole,
segmented, section-memory and section-scoped representations are the known
nonmigratable legacy derivatives. Parsed source (`parsed_sections`), lazy EPUB
indexes (`lazy_epub_indexes`), derived/search/Book Memory
(`derived_book_index_v1/<book hash>`), EPUB files (`Documents/books`), covers,
book metadata, checkpoints (`reader_checkpoints.sqlite3`), stable locations,
bookmarks, highlights, notes, saved words, character data, settings and
unrelated books remain independent protected authorities.

The audit found broad methods `BookCacheService.clearAll`, segmented
`clearAll`/`deleteForBook`, and
`LazyReaderCacheCleanupService.deleteDerivativesForBook`/
`clearAllDerivatives`; their call sites can affect parsed source, lazy indexes,
derived indexes or whole cache roots. None is called by this task. Existing
legacy paths were derived from cache keys or record filenames, which made them
unsuitable for controlled deletion. The new path derives only service-owned
deterministic direct-child filenames from trusted caller inputs, then
revalidates root containment, no link, no absolute path, no `..`, no separator
or NUL. Decoded payload book ids, filenames, cache keys and fields never select
a target. Existing mixed payload/manifest failure paths were inventoried; the
new exact paths leave candidates ineligible and return diagnostics rather than
falling back to a clear.

Pre-edit frozen source hashes were P03 full/target/forward/singleton/
structural/cache/ledger respectively
`4505e5730a02ec55a3ba65412e40e1bbf1d672cf1d03a89044382b4b7a7cd425`,
`1e7fd14dd0c0f44d89dc1a9fc90105c71d1399ccf5bf8ac47bc20e31fd208b41`,
`5481bf3bd31c24c7e6076a72258ec7400b6b71b746f050aadd91c89bb8618d8b`,
`9ab90693a6f83ca76ecde148921443ead86b845ef3e02c0535e396177778e77b`,
`1826b4c4b970eac1af9e3e3d5dd5ddf50c7782eb9e47095ae30c3ca5ed6c392e`,
`8b3a964273ac407fa452298f9b66f61f4fe9e7cebe8087d0a5940c8aff6de9bd`,
and `edeefbc6e5703125a10c58d629b8b97e8fec12c90e4b85c154be5d85458dae0a`.
The unchanged P04 final-gate hash was
`88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`.
The frozen P05 shared/construction/standard hashes were
`7962ecd954484cd4a07c3c879048bbfa7a5bf60d2b2c6826b224ae7abb9081f6`,
`f54dfa2d77bd922c716614aa9d4b6539139edf545ed90582e5f4138ceb2affc4`,
and `9c625b1c4de7ee23f54ba1cbddd3833ed0819ffa570081ad09fb16c917a72e39`.

### Taxonomy and exact behavior

`CanonicalDisplayCacheInvalidationService` consumes a P06 admission outcome,
explicit caller-owned display root/book scope, opaque trusted lookup/manifest
receipt, candidate type and migration-eligibility evidence. Its reasons cover
exact/absent, incomplete/source/layout/renderer/pagination change, unsupported
future revision, checksum/encoding/boundary/continuation/card/compatibility
corruption, stale generation, cross-book scope, legacy nonmigratability,
migration deferral and unsafe/mutation failure. Its actions are no action,
exact memory eviction, exact disk invalidation, same-scope quarantine, retained
future record, deferred migration assessment and failed-safe invalidation.

All 16 outcomes map deterministically: exact/absent retain with no action;
legacy incomplete/source/layout/renderer/pagination and regeneration-required
records invalidate exactly; strict candidates with possible P06-005 evidence
defer; unsupported revisions retain; corruption/boundary/continuation/card/
compatibility and cross-book evidence quarantine exactly; stale generation
evicts only an exact memory entry and never deletes persistent storage; and
unknown/deferred evidence remains a safe miss. Bounded canonical regeneration
is always allowed, but does not authorize mutation.

Whole-cache invalidation removes only one trusted manifest reference and its
deterministic gzip payload. Segmented/section invalidation removes only one
range reference and deterministic range payload. Corrupt disk candidates are
renamed only to a deterministic same-directory quarantine name before their
exact reference is removed. Section-memory removes one private map key and
pin. Chapter-layout removes/quarantines one independently verified record.
Missing payloads are a typed successful exact-reference cleanup/no-op;
repetition is idempotent. Manifest-update or payload-delete failure returns a
failed-safe diagnostic; a surviving orphan or quarantine is ineligible, and
no broad recovery occurs.

### Preservation, testing, and maxima

Focused tests use real production cache services exclusively under
`Directory.systemTemp` sandbox roots; no default application path is cleaned.
They prove byte-equivalent preservation of EPUBs, parsed source/parser
manifests, covers/metadata, stable locations, checkpoints/journal, bookmarks,
highlights, notes, saved words, character declarations/names, search/Book
Memory indexes, settings and unrelated books. Accepted in-memory display and
continuation state, committed anchor, publication, checkpoint and settlement
remain unchanged. Receipts contain no copied source text or mutable display
index identity.

The P06-004 focused suite passes 21/21, including all requested exact,
absent, whole, segmented, section, memory, migration deferral, future,
corruption, cross-book, forged-path/symlink, idempotence, stale-manifest,
injected-failure, regeneration and preservation cases. Affected cache-service
tests pass 37/37 (whole 11, segmented 23, memory 3). P06 admission is 7/7;
P06 equivalence is 4/4 with normalized hash
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`;
P05 classifier is 27/27; unchanged P04 final gate is 3/3; and the final
combined P06 admission/equivalence/invalidation suite is 32/32.

Observed P06-004 maxima (not P06-006 release budgets) are plan 240 bytes,
receipt 461 bytes, one payload file and one manifest entry touched, one
retained/quarantined record, one memory entry evicted and one protected root
inspected per action. Source-text bytes copied, mutable-index identity bytes,
publication/checkpoint/settlement/cache-write authority mutations and unrelated
files changed are all zero.

### Files and limits

Production: `lib/models/canonical_display_cache_invalidation.dart`,
`lib/services/canonical_display_cache_invalidation_service.dart`,
`lib/services/book_cache_service.dart`,
`lib/services/segmented_display_cache_service.dart`, and
`lib/services/display_section_memory_cache.dart`.

Tests: `test/reader_contract/pagination/canonical_display_cache_invalidation_test.dart`.
Documentation: `test/reader_contract/README.md`,
`docs/development/nalori-reader-canonical-display-cache-contract.md`,
`docs/development/nalori-reader-reliability-plan.md`, and this ledger.

Scoped formatting and static analysis pass with no issues. No migration,
persistent format/key/version choice, live cache write/reuse, final
eviction/pinning/retention policy, dependency/lockfile, P03/P04/P05 authored
oracle, ReaderScreen/device behavior or protected-data service changed.
P06-005 through P06-007 were not started. The only recommended next scope is
`TASK-P06-005`: assess and implement only evidence-sufficient migration while
retaining/deferring all other strict candidates and preserving this exact
invalidation boundary.

Final read-only SHA-256 checks reproduced the seven frozen P03 files, P04
final gate and three P05 oracle files; the P03 normalized hash remains
`fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`.
Scoped diff checking is clean. Whitespace inspection found only the
pre-existing Markdown hard breaks at the document headers; no task line adds
trailing whitespace.

---

## CHANGE-20260913-035 — Implement evidence-sufficient canonical cache migration

**Phase/task.** `TASK-P06-005` completed. P06 remains `IN_PROGRESS` at 5/7;
overall progress is 44/89. P06 exit criteria and P07 entry criteria remain
unmet. P06-006 and P06-007 remain unstarted.

### Pre-edit assessment and frozen boundaries

The pre-edit branch was `feature/lazy-random-access-reader` at
`9d7716597d95d578699e7a54544d92d5b4b234b6`; the worktree was already dirty
with unrelated application and test changes, which this task preserved. The
persistent constants were inspected and not changed: whole display format 3,
display layout `v14`, segmented display format 3,
`nalori_cards_v16_lists`, checkpoint record/store schemas 1/1 and stable
location schema 2. Stored representations were whole v3 gzip DTO, segmented
manifest/range v3, section-scoped segments, section-memory `DisplayRangeResult`
copies, raw ranges/maps and chapter-layout derivatives. None supplies all P04
continuation/publication and P05 terminal evidence; the existing matrix is
therefore honest: whole/segmented/section-scoped/section-memory/raw ranges are
nonmigratable; chapter layout is a nonauthoritative hint; checkpoint/stable
locations are recovery hints; continuation alone is insufficient.

P06-004's deferred strict-candidate path was inspected. Its exact scoped
invalidation service remains the sole old-candidate deletion authority. No
production source/parser-version correspondence resolver exists: exact stable
location reconstruction is only valid under its matching source identity and
parser snapshot, bookmark text recovery is not correspondence evidence, and
the parser's local anchor merge map is not a revision remapper. All current
candidate rewrite/delete paths were reviewed; this task adds only a controlled
strict replacement handoff after full validation.

Frozen SHA-256 checks remain: P03 full
`4505e5730a02ec55a3ba65412e40e1bbf1d672cf1d03a89044382b4b7a7cd425`,
target `1e7fd14dd0c0f44d89dc1a9fc90105c71d1399ccf5bf8ac47bc20e31fd208b41`,
forward `5481bf3bd31c24c7e6076a72258ec7400b6b71b746f050aadd91c89bb8618d8b`,
singleton `9ab90693a6f83ca76ecde148921443ead86b845ef3e02c0535e396177778e77b`,
structural `1826b4c4b970eac1af9e3e3d5dd5ddf50c7782eb9e47095ae30c3ca5ed6c392e`,
cache `8b3a964273ac407fa452298f9b66f61f4fe9e7cebe8087d0a5940c8aff6de9bd`
and ledger `edeefbc6e5703125a10c58d629b8b97e8fec12c90e4b85c154be5d85458dae0a`;
P04 final gate `88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`;
P05 shared `7962ecd954484cd4a07c3c879048bbfa7a5bf60d2b2c6826b224ae7abb9081f6`,
construction `f54dfa2d77bd922c716614aa9d4b6539139edf545ed90582e5f4138ceb2affc4`
and standard `9c625b1c4de7ee23f54ba1cbddd3833ed0819ffa570081ad09fb16c917a72e39`.
The frozen P06-003 normalized hash remains
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`.

### Eligibility, planner and outcomes

Added a typed `CanonicalDisplayCacheMigrationService`, plan, eligibility,
reason, outcome, diagnostics and controlled replacement receipt. It assesses
the old bytes nonauthoritatively, classifies compatibility, requires strict
integrity/scope/source linkage/stable cursor/ordered ownership/boundary and
continuation/current P05 evidence, resolves only the current pinned source,
performs bounded current P04 pagination and controlled `publishCanonical`,
rebuilds and strictly admits the current canonical record, retains it in a
controlled transport, then requests P06-004's exact replacement handoff.

Explicit outcomes cover exact/no migration, successful regeneration,
nonmigratable legacy, incomplete, corrupt, unsupported-future-retained,
source correspondence unavailable/ambiguous, incompatible scope, budget
exhaustion, stale, cancelled, current contract unavailable, regenerated
admission failure, replacement failure and bounded source regeneration
required. Every non-success has zero migrated cards, continuation,
publication, checkpoint/settlement, live-write and deferred-candidate deletion
authority. A success contains only a new current strict record and controlled
replacement receipt; it does not activate a live path.

Layout-only, renderer-only, pagination-only and ordered layout/renderer/
pagination compound strict-canonical changes regenerate exactly once. Old
physical cards, F209/F210/F211 and signatures are never copied; new values are
computed by current P04/P05/P06 construction. Semantic source ownership is
re-proven even when physical boundaries differ. Source/parser and compound
source changes return `sourceCorrespondenceUnavailable` because no explicit
unique resolver exists; no visible-text, repeated-text, nearest-match or
mutable-index remapping is used.

### Controlled evidence and atomicity

`canonical_display_cache_migration_test.dart` passes 7/7 focused cases. It
proves the entire field-level matrix; all current legacy forms return typed
safe misses; exact compatibility does not migrate; source/parser absence and
ambiguous/repeated text cannot migrate; corrupt, incomplete and future records
do not migrate, with future bytes retained; and stale/cancelled/budget paths
mutate neither accepted display nor storage. Successful strict cases admit
under current identities, byte-match ordinary cold current-contract generation,
preserve ordered source coverage across changed card boundaries, and retain the
old controlled candidate until validation is complete. Injected strict-admission
and replacement failures preserve old bytes. Successful controlled replacement
is deterministic and idempotent; P06-004 is the only deletion authority.

Observed maxima are assessment/result 268/32 bytes; old/new record
15,376/14,805 bytes; two source units and two cards regenerated; two physical
boundary changes; one changed compatibility dimension; zero source-remap
candidates; one controlled record retained/replaced; and one attempt per
record. Copied old-card identity bytes, copied source-text identity bytes,
mutable-index authority bytes, partial records exposed, protected-data
mutations and live-cache writes are all zero. Parsed source, checkpoints and
all tested user-data roots remain byte-equivalent.

### Verification and status

Scoped formatting and static analysis pass with no issues. New migration cases
pass 7/7; P06 invalidation passes 21/21; P06 admission passes 7/7; P05
compatibility passes 27/27. The unchanged P06 equivalence control remains 4/4
at its frozen normalized hash above, and the unchanged combined P06 baseline
is 32/32. Bounded individual P04 continuation/publication controls exercised
by migration pass; the established P04 continuation/publication/final-gate
controls remain 13/13, 9/9 and 3/3. The complete P03 matrix was intentionally
not run and its oracles were not altered.

Production files changed: `lib/models/canonical_display_cache_migration.dart`,
`lib/models/canonical_display_cache_invalidation.dart`,
`lib/services/canonical_display_cache_migration_service.dart`,
`lib/services/canonical_display_cache_invalidation_service.dart` and
`lib/services/segmented_display_cache_service.dart`. Test changed:
`test/reader_contract/pagination/canonical_display_cache_migration_test.dart`.
Documentation changed: the canonical cache contract, reliability plan,
reader-contract README and this append-only ledger.

`REQ-009`, `REQ-046` and `REQ-051` remain `IMPLEMENTED_NOT_VERIFIED`; `REQ-010`
remains unverified. `RISK-008` is
`PARTIALLY_MITIGATED_BY_P06_004_005_CONTROLLED`: controlled bounded migration
evidence has improved, but final bounds and physical rollout are still open.
No legacy conversion, persistent format/key/version, live cache reuse/write,
dependency/lockfile, P03/P04/P05 oracle, ReaderScreen/device behavior,
navigation/restoration/checkpoint/settlement behavior or production cache path
changed. The only recommended next scope is `TASK-P06-006`.

---

## CHANGE-20260913-036 — Independently audit P06 invalidation and migration

**Audit scope and status.** Independently audited completed TASK-P06-004 and
TASK-P06-005, with TASK-P06-003 treated as a required frozen dependency and
regression control. This is not a numbered task. P06 remains `IN_PROGRESS` at
5/7, overall progress remains 44/89, P06 exit and P07 entry criteria remain
unmet, requirement statuses are unchanged, and P06-006/P06-007 remain
unstarted.

### Pre-edit capture and baseline

The branch was `feature/lazy-random-access-reader` at
`9d7716597d95d578699e7a54544d92d5b4b234b6`; the existing dirty worktree was
recorded and preserved. CHANGE-033 and CHANGE-034 attribution, all requested
production/test files, the P03 shared harness, ReaderScreen legacy safe-miss
boundary and repository-wide cache/invalidation reachability were reviewed.
Persistent constants remained whole display format 3, display layout `v14`,
segmented display format 3, pagination `nalori_cards_v16_lists`, checkpoint
record/store schemas 1/1 and stable-location schema 2.

CHANGE-033 attribution was canonical segment model/admission, memory and
segmented controlled transports, the P03 shared harness, equivalence test and
the four cache-contract documents. CHANGE-034 attribution was the invalidation
model/service, whole/segmented/section-memory cache services, invalidation test
and the same four documents. CHANGE-035 attribution was the migration and
invalidation models/services, segmented controlled transport, migration test
and the same four documents. Every attributed file was inspected in its
current state.

Frozen pre-edit SHA-256 evidence remained P03 full
`4505e5730a02ec55a3ba65412e40e1bbf1d672cf1d03a89044382b4b7a7cd425`,
target `1e7fd14dd0c0f44d89dc1a9fc90105c71d1399ccf5bf8ac47bc20e31fd208b41`,
forward `5481bf3bd31c24c7e6076a72258ec7400b6b71b746f050aadd91c89bb8618d8b`,
singleton `9ab90693a6f83ca76ecde148921443ead86b845ef3e02c0535e396177778e77b`,
structural `1826b4c4b970eac1af9e3e3d5dd5ddf50c7782eb9e47095ae30c3ca5ed6c392e`,
cache `8b3a964273ac407fa452298f9b66f61f4fe9e7cebe8087d0a5940c8aff6de9bd`
and ledger `edeefbc6e5703125a10c58d629b8b97e8fec12c90e4b85c154be5d85458dae0a`;
P04 final gate
`88eef247740cb193e2cf8ab8e3465894493bea0c5e5392e8f69cdf77472c998d`;
P05 shared
`7962ecd954484cd4a07c3c879048bbfa7a5bf60d2b2c6826b224ae7abb9081f6`,
construction
`f54dfa2d77bd922c716614aa9d4b6539139edf545ed90582e5f4138ceb2affc4`
and standard
`9c625b1c4de7ee23f54ba1cbddd3833ed0819ffa570081ad09fb16c917a72e39`.
The frozen P06-003 normalized hash was
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`.

The revised pre-edit invalidation/migration baseline passed 28/28 (21/21 plus
7/7). An earlier broader P06 invocation was intentionally interrupted when the
audit scope was corrected, after 29 passing cases and with no semantic
failure; it was not retried as a baseline assertion. All frozen dependency
controls were subsequently run to completion after the focused corrections.

ReaderScreen still reads only legacy whole/segmented derivatives and forces
`legacySafeMiss`/`canonicalRegenerationRequired`; its retained-memory helpers
also return no reusable canonical candidate. No canonical transport has a
default production root or live writer. Existing broad clear/delete methods
are reachable only through their pre-existing cache/cleanup APIs, not through
the P06-004/P06-005 policy services. No candidate, builder, admission result,
migration plan or invalidation receipt directly publishes display, checkpoint
or settlement state; accepted replacement generation still passes through
`ProgressiveDisplayState.publishCanonical`.

### Findings and corrections

**BLOCKER: none. MEDIUM: none. LOW: none. HIGH: four.** Each high finding was
first reproduced with a focused failing assertion, then corrected at the
earliest owning boundary.

1. **HIGH — prefix-colliding cross-book memory eviction.**
   `DisplaySectionMemoryCache.lookupForInvalidation` accepted every key with
   the raw prefix `<bookScope>_`. A `book-a` scope could therefore obtain an
   exact eviction receipt for a resident `book-a_other_dc_v14_*` key. The
   lookup now permits only the exact supplied book key or the production cache
   namespace `<bookScope>_dc_`. The regression proves the forged cross-book
   receipt is rejected and the other book's entry remains intact.
2. **HIGH — stale migration could delete the old candidate after an await.**
   Freshness/cancellation was checked before
   `retainValidatedRecord`, but not after that await or after asynchronous old
   receipt lookup. A request becoming stale during retention could reach the
   P06-004 deletion handoff. Freshness and cancellation are now rechecked after
   both awaits and before invalidation; the regression flips freshness during
   retention and proves a typed stale result with old bytes retained.
3. **HIGH — caller-forgeable exact admission authority.** The public
   `CanonicalDisplaySegmentAdmissionResult.exact` constructor produced a value
   indistinguishable from one returned by strict validation. Migration now
   requires a private strict-admission attestation minted only inside
   `CanonicalDisplaySegmentAdmissionService`; public exact values remain
   diagnostic and nonauthoritative. The regression proves a caller-assembled
   exact result cannot establish migration eligibility.
4. **HIGH — replacement was not anchored to the assessed segment.** A
   regenerator could return an independently valid current-contract segment
   for another interval; isolated strict admission succeeded and the assessed
   old segment could then be deleted. Before retention, migration now requires
   the regenerated record's stable start cursor to equal the old record's
   stable start. The regression supplies a later old segment and a valid
   book-start replacement and proves strict-admission failure with no old-byte
   deletion.

### Independent conclusions

The P06-003 expected sequence ultimately comes from the separately authored
frozen P03 oracle and real pinned-source production pagination. No cache record
builder seeds the cold result. The shared projection covers ordered text,
source slices, UTF-16/table intervals, owners, roles, F209/F210/F211,
signatures, boundaries, continuation and final order. Memory uses codec
round-trip validation rather than object identity; controlled disk writes real
bytes and a fresh service instance decodes them; eviction removes the exact
memory/disk derivative and absence regenerates from bounded source. Mixed
regions use distinct records/operations and numerically adjacent records still
require seam proof. All accepted paths execute contextual anchoring and P04
publication.

P06-004 targets derive from explicit caller-owned roots and opaque lookup
receipts. Absolute paths, separators, NUL, `..`, forged names, sibling-prefix
paths, existing parent symlinks and target symlinks reject. Mutations remain
limited to one exact memory entry, one exact payload plus manifest reference,
or one same-scope quarantine target. All 16 outcome mappings remain fail
closed: future revisions and evidence-sufficient strict candidates are
retained, legacy derivatives invalidate exactly, corruption/cross-book claims
quarantine only the current trusted scope, and stale generation evicts only
exact memory. Missing payloads, stale references, repeated actions, malformed
manifests and injected failures cannot make a partial record reusable or reach
parsed source, EPUB, index, checkpoint, user-data or unrelated-book roots.

P06-005 still admits only strict-attested, evidence-sufficient canonical
records with unchanged source/parser evidence. Every legacy format is an
unconditional safe miss; no cards, ranges, continuations, checkpoints, visible
text or chapter-layout hints are converted or copied, and there is no text or
nearest-occurrence correspondence. Current P04/P05 regeneration recomputes
F209/F210/F211 and physical signatures, equals ordinary current-contract cold
generation, and every replacement passes strict P06 admission. The old record
remains until validated retention and the final freshness gate; only P06-004
can invalidate it. No live writer/reuse path is active.

### Final verification, files and deferrals

Scoped Dart formatting completed and scoped static analysis reported no
issues. P06 admission passed 7/7; equivalence passed 4/4 twice and again in the
combined run; invalidation passed 21/21; migration passed 7/7; affected whole,
segmented and section-memory cache services passed 37/37. The complete P03
matrix passed 57/57. P04 continuation/publication/final gate passed 13/13,
9/9 and 3/3 (25/25 combined). P05 classifier/shared-layout compatibility
passed 27/27 and 42/42 (69/69 combined). Frozen P02 passed 9/9. The final
focused P06 run passed 39/39: the prior admission/equivalence/invalidation core
remains 32/32 plus migration 7/7.

The P06 normalized hash remained
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`;
the P03 normalized hash remained
`fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`.
Observed maxima remained P06 equivalence cold/safe-miss source work 14/14,
111 validation fields, 76,971 controlled memory/disk bytes, three segments and
nine cards; migration assessment/result 268/32 bytes, old/new record
15,376/14,805 bytes, two source units/cards, one retained/replaced record and
one attempt. Invalidation observed plan bytes 242, one exact payload/reference
or memory entry and one protected root per action. Authority/protected-data
mutations and live-cache writes remained zero.

Production files changed by the audit:
`lib/services/display_section_memory_cache.dart`,
`lib/services/canonical_display_segment_admission.dart` and
`lib/services/canonical_display_cache_migration_service.dart`. Tests changed:
`test/reader_contract/pagination/canonical_display_cache_invalidation_test.dart`
and
`test/reader_contract/pagination/canonical_display_cache_migration_test.dart`.
Documentation changed: the canonical cache contract, reliability plan,
reader-contract README and this append-only ledger.

P06-006 retains ownership of final budgets, pinning and retention. P06-007
retains ownership of concurrent symlink-swap/TOCTOU stress, physical atomic
replacement, crash recovery and production rollout. No persistent format,
key, schema or version; live reuse/write; legacy migration; final retention
policy; dependency/lockfile; frozen oracle; ReaderScreen; navigation,
restoration, checkpoint, settlement or device behavior changed. It is safe to
proceed to TASK-P06-006 using the next available change-log ID, expected
`CHANGE-20260913-037`.

## CHANGE-20260913-037 — Enforce bounded canonical cache retention and pinning

**Task:** TASK-P06-006
**Status:** COMPLETED
**Requirements:** REQ-009, REQ-010, REQ-013, REQ-044, REQ-045, REQ-046,
REQ-048, REQ-051

Added the isolated `CanonicalDisplayCacheService` controlled retention layer
and publication-minted write/pin capabilities. Release ceilings are enforced
before logical retention, physical allocation, decompression and decoding:
12 cards, 96 source slices, 192 block layouts, 512 KiB compressed, 1 MiB
decoded, 64x decompression, 48/128 KiB manifest records/bytes, 12/12 MiB
memory records/bytes, 48/24 MiB disk records/bytes, continuation depth 25,
restart depth 2, three pins, 12-card/96-slice validation work and 655,616
temporary bytes. Checked addition rejects overflow and inconsistent manifest
counts/totals.

The evidence maximum was six cards, 20 slices across the three-record set,
six block layouts, 37,397 decoded bytes, 8,453 compressed bytes, an 8,549-byte
container, 5x rounded-up ratio, continuation depth two, three records and
76,971 aggregate controlled bytes. Limits retain the P04 48-source/eight-card
window, 25-record continuation and two-restart bounds with the documented
headroom in the canonical cache contract.

Only an accepted canonical publication can authorize the current record and
its unique stable-cursor predecessor/successor, capped at three. Preview,
stale, rejected, cancelled and merely resident candidates cannot pin.
Deterministic lexicographic eviction removes only unpinned v4 display
derivatives, commits reference removal before payload deletion and is
idempotent. Pinned-only pressure returns a typed result without exceeding the
bound. The controlled payload/manifest protocol preserves the prior valid
reference until the final manifest install; failure cannot publish cards,
settle navigation or acquire checkpoint authority.

Focused formatting and analysis passed. The new P06-006 suite passed 6/6 in
25.8 seconds (exit 0). The unchanged P06 admission/equivalence/invalidation/
migration control passed 39/39 in 64.0 seconds (exit 0), with normalized P06
hash `714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`.
No source, checkpoint, user-data or frozen-oracle bytes changed.

Production files changed: `lib/services/progressive_display_state.dart` and
`lib/services/canonical_display_cache_service.dart`. Focused test added:
`test/reader_contract/pagination/canonical_display_cache_budget_test.dart`.
Documentation changed: the canonical cache contract, reliability plan and
this append-only ledger. P06 is IN_PROGRESS at 6/7 and overall progress is
45/89. P06 exit and P07 entry criteria remain unmet until TASK-P06-007.

## CHANGE-20260913-038 — Complete canonical display-cache physical rollout

**Task:** TASK-P06-007
**Status:** COMPLETED
**Requirements:** REQ-009, REQ-010, REQ-013, REQ-044, REQ-045, REQ-046,
REQ-048, REQ-051

Activated the canonical display cache in an isolated production namespace only
after the complete P06-006 gate passed. P01 recorded both legacy physical
display formats at 3 and reserved the first persistent successor decision for
P06; the canonical successor is therefore physical format 4, namespace
`canonical_display_v4`, manifest revision `canonical_display_manifest_v4` and
container revision `canonical_display_container_v4`. Existing whole/segmented
format 3, display layout `v14`, pagination `nalori_cards_v16_lists`, canonical
logical revision 1, checkpoint record/store 1/1 and stable location 2 are
unchanged. The new payload key is
`seg-sha256-<keyDigest>-<recordChecksum>.cseg4.gz` beneath an opaque
book-scope digest, so legacy/older applications cannot reinterpret it.

The strict manifest has eight exact fields and binds record count/total bytes,
stable key and book-scope digests, logical checksum, container checksum,
encoded/decoded sizes and payload filename. The 96-byte physical header binds
magic `NLCSEG4\n`, format 4, declared decoded/compressed sizes and the gzip
digest. File/declaration/ratio ceilings are checked before body allocation or
decode, and decompression also enforces its streamed output ceiling.

ReaderScreen creates the isolated service, derives a text-free opaque book
scope and first obtains caller-owned accepted P04 generation evidence. Memory
and disk candidates share the exact codec, compatibility, source/card, seam,
continuation and contextual-anchoring admission path. Reuse reaches visible
state only through `ProgressiveDisplayState.publishCanonical`. Only after that
publication and canonical-session commit can display state mint a private
record/source-bound write capability; the service also requires the private
strict-admission attestation. Cache candidates cannot mint their own
publication or write authority. Failed/absent candidates regenerate from
source without deletion.

Writes use bounded temporary payload write/flush/close, atomic payload rename,
bounded temporary manifest write/flush/close and atomic manifest commit last.
The previous valid manifest and payload remain reusable until replacement
commits. Startup discards temporary and valid-manifest-unreferenced payloads;
malformed manifests never authorize orphan deletion. Reference removal precedes
payload eviction. Digest-only names, normalized containment, non-following
enumeration, parent/target symlink rejection, opaque scopes and per-root writer
coordination reject traversal, TOCTOU, sibling-prefix, cross-book and rename
races. Freshness/cancellation is checked at each asynchronous precommit
boundary. A post-manifest-commit cancellation cannot turn a complete durable
write into a partial one.

The nine adversarial physical cases cover truncated payloads, malformed tags,
counts and lengths, checksum/manifest binding corruption, unsupported legacy,
current and future revisions, partial payload writes, payload success plus
manifest failure, missing referenced payload, interruptions before/after every
atomic rename, temporary/orphan recovery, concurrent same-key and different-
book writers, stale generation and cancellation at every boundary, rename and
symlink-swap races, traversal and sibling-prefix collision, old-application
rollback, current application legacy/current/future handling, failed migration
replacement retaining old bytes, corrupt warm regeneration, memory/disk/full
eviction, current/adjacent pinned pressure and fresh-service reopening. Every
failure preserves accepted cards and produces no partial publication,
checkpoint or settlement authority. Parsed source, EPUB, cover/metadata,
checkpoints, bookmarks, highlights, notes, saved words and characters remain
byte-equivalent.

The production-shaped test proves cold generation → canonical publication →
authorized physical write → closed/fresh services → strict disk admission →
contextual anchoring → `publishCanonical`, with equal visible text, cards,
source slices, F209/F210/F211, signatures, boundaries, continuation and final
order. Corrupt and fully evicted derivatives regenerate identically from
source without cache clearing. The adversarial self-review found one retention
defect: an unpinned newly written record could report `stored` even when it was
the deterministic eviction victim. The boundary now rejects that write and
retains exact accounting; its regression passes.

### Verification

- Scoped formatting: four Dart files, exit 0; scoped static analysis: no
  issues in 3.1 seconds, exit 0.
- P06-006 budget/pinning: 6/6 in 25.8 seconds, then 6/6 in 22 seconds after
  adding exact physical aggregate measurements; both exit 0.
- P06-007 physical corruption/race/rollback: 9/9 in 44 seconds, exit 0.
- P06 admission: 7/7 in 7 seconds; equivalence: 4/4 in 56 seconds and 4/4
  in 55 seconds; invalidation: 21/21 in 3 seconds; migration: 7/7 in 60
  seconds; all exit 0.
- Relevant whole/segmented/section-memory cache services: 37/37 in 3 seconds,
  exit 0.
- Frozen P03 matrix: 57/57 in 3 minutes 16 seconds, exit 0. P04 continuation,
  publication and final gates: 13/13 in 29 seconds, 9/9 in 1 minute 8 seconds,
  and 3/3 in 4 minutes 30 seconds; all exit 0.
- P05 classifier and shared/layout: 27/27 in 3 seconds and 42/42 in 14
  seconds; frozen P02: 9/9 in 3 seconds; all exit 0.
- Final combined focused P06 gate: 54/54 in 1 minute 4 seconds, exit 0.

Final read-only integrity checks retained branch
`feature/lazy-random-access-reader` at
`9d7716597d95d578699e7a54544d92d5b4b234b6`, reproduced every recorded frozen
P03/P04/P05 SHA-256 value, confirmed the exact legacy/current version constants
and reported no scoped Dart or diff whitespace error. The whitespace scan found
only four pre-existing intentional Markdown hard-break lines in the plan and
ledger; none is in the P06-006/P06-007 additions.

Both equivalence runs and the combined gate normalized to
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`.
The frozen P03 normalized hash remained
`fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`.
Observed largest-record maxima were six cards, 14 source slices, six block
layouts, 37,397 decoded bytes, 8,453 compressed bytes, 8,549 container bytes,
5x rounded ratio and continuation depth one; the complete equivalence set
observed three records, nine cards, 20 slices and depth two. The live v4
three-record measurement was a 1,892-byte manifest, 77,405 memory bytes,
18,479 disk bytes and 10,441 maximum observed replacement bytes. All selected
release ceilings are recorded in contract section 21.

Production files changed:
`lib/services/progressive_display_state.dart`,
`lib/services/canonical_display_cache_service.dart` and
`lib/screens/reader_screen.dart`. Focused test changed:
`test/reader_contract/pagination/canonical_display_cache_budget_test.dart`.
Documentation changed: the canonical cache contract, reliability plan,
reader-contract README and this append-only ledger. No dependency, lockfile,
parsed-source format, checkpoint schema/authority, user data, frozen oracle,
restoration, navigation, settlement or device behavior changed. No complete
Flutter suite, device, emulator or integration-device test was run.

REQ-009, REQ-010 and REQ-046 are VERIFIED. REQ-013 and REQ-048 retain their
P04 verified evidence. REQ-044 and REQ-045 pass the narrow host contract while
P11 retains release/device profiling. REQ-051 remains
IMPLEMENTED_NOT_VERIFIED pending its later corpus/reconciliation evidence.
RISK-007 and RISK-008 are MITIGATED_BY_P06; DISC-007 is resolved for P06 host
evidence with P11 profiling retained. P06 is COMPLETED at 7/7 and overall
progress is 46/89. P06 exit criteria and the documented dependency portion of
P07 entry criteria are met. P07 was not started; the only recommended next
task is TASK-P07-001.

## CHANGE-20260914-039 — Correct reader ANR, table pagination, and startup regression

- Correction resumed and host verification completed: 2026-09-19 IST.
- Branch/HEAD: `feature/lazy-random-access-reader` at
  `9d7716597d95d578699e7a54544d92d5b4b234b6`.
- Scope: urgent P06 device-regression correction only. No P07 task was started,
  no task count was added, and overall progress remains 46/89.

### Device evidence and reopened gate

Owner device evidence supersedes the previous host-only P06 exit decision. An
ordinary `flutter run`, without reader diagnostics and without recording,
reproduced the failure. Repeatedly opening The Prince remained on Preparing
pages, reached Android's stop/wait dialog, and often stopped at the title or a
short chapter boundary. The run recorded 592 and 2,156 skipped frames, a
23,965 ms HWUI frame and six cache-miss/rebuild generations. Endurance failed
deterministically in `ReaderBlockLayoutResolver._resolveTable` through
`ReaderCardPaginator._runEngine`,
`CanonicalReaderPaginationSession._generateInitialInternal` and
`_ReaderScreenState._rebuildDisplayChunks`; target generation repeated the same
failure. Android signal-3/tombstone activity was ANR trace collection, not
evidence of a native crash. Earlier device evidence also established five-
second input-dispatch ANRs, 1.6/2.23/2.49-second main-isolate split operations,
approximately 517 MB PSS and 596 MB RSS, roughly 38-section/153-operation
derived hydration, and canonical write rejection reading `A record without an
accepted restart must begin at book start.` Vendor resource, dependency-update
and back-callback warnings remain unrelated.

P06 therefore remains 7/7 but its status is
`CORRECTION_IMPLEMENTED_NOT_DEVICE_VERIFIED`; its exit criteria are unmet.
The P06 dependency portion of P07 entry is unmet and P07 remains unstarted.

### Pre-edit audit and confirmed root causes

The normalized baselines were P06
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`
and frozen P03
`fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`.
Persistent/cache declarations were unchanged: parsed-book 6,
`whole_book_preparation_v1`, whole-display 3, layout `v14`, segmented 3,
canonical physical/manifest/container 4, pagination
`nalori_cards_v16_lists`, checkpoint/store 1/1, stable-location 2, lazy-section
3 with parser `section_v4_lists` and dependency schema 1, and derived-index
schema/normalization 1/1.

Book selection and Continue both enter `BookListScreen._openBook`, proceed
through `BookLoadingScreen` and `ReaderOpenService.open`, and create a bounded
`LazyBookSession`. Stable restoration resolves through the session before
ReaderScreen build calls `_ensureDisplayChunksBuilt`. That method is the only
starter of `_loadOrRebuildDisplayChunks`; the latter is the only starter of
`_rebuildDisplayChunksAsync`. Canonical generation runs through the production
paginator/session, publication through `ProgressiveDisplayState.publishCanonical`,
then post-publication admission/write work through
`CanonicalDisplayCacheService`. Parsed hydration and `DerivedBookIndexSession`
are scheduled only after display publication and a quiet boundary.

The production EPUB parser could emit a valid single-row table but its decoder
required at least two rows. It consequently returned lossy fallback text while
retaining `BookBlockRole.table`; `_resolveTable` then rejected that exact shape
at the former line 1258. Every ReaderScreen build invoked
`_ensureDisplayChunksBuilt`; failed generations cleared their flags while
leaving an empty display, so the next build began another identical generation.
This explains why generations 1–6 each reached cache miss/rebuild. Initial and
target paths could repeat the same deterministic failure. Legacy display-cache
reads/writes, cache compression/hashing, derived hydration and indexing were
also on or too near the first-card path. Mid-book record construction supplied
book-start semantics when accepted predecessor/restart proof was absent. The
physical writer was awaited and its first isolate closure accidentally captured
the service's `_writeTail` Future; the focused regression exposed and corrected
that unsendable capture with a top-level isolate entry point.

Retained owners were the current/adjacent parsed sections, ReaderScreen source
chunks, table/layout intermediates, font asset bytes/evidence, canonical
records/cards, decoded images, derived-index section work and obsolete
generation closures. There was no Android memory-pressure cancellation and
unpinned-derivative eviction boundary.

### Corrections and failing regressions

The table regression was made red with a production-parser one-row table, then
the parser, reader content codec, paginator and layout resolver were routed
through one canonical table-normalization boundary. It preserves cell/row
order, inline text, header/body role, row/column spans, structural owner,
canonical row intervals, source slices and identities. Unsupported input now
throws `ReaderTableNormalizationException`; ReaderScreen exposes a stable
recoverable error with Retry and Back instead of remaining in Preparing.

The generation regression was made red for duplicate, replacement, failure and
cancellation paths. `DisplayGenerationSignature` now includes source snapshot
and target identity. Equal callers join one future; a new target stales the old
token; deterministic failure blocks automatic restart; explicit Retry creates
the only retry. The authoritative wrapper clears rebuilding/preparing in
`finally`, settles every terminal future, and prevents stale publication,
checkpoint/cache authority and indexing.

The critical path now resolves the bounded target/source window, generates and
publishes the first useful canonical card plus immediate continuation, and only
then schedules hydration/indexing and canonical cache work. Legacy derivatives
that cannot pass P04/P06 admission are not read or written on this path.
Background section work defaults to concurrency one, yields, and is cancelled
or paused for input, target generation, navigation, backgrounding, book change
and memory pressure.

`FrameBudgetedRangeScheduler` exposes completed slice evidence and retains its
injectable clock/yield boundary. Paragraph splitting, table pagination and
finalization cross resumable production checkpoints. Deterministic synthetic-
clock tests force long paragraph and large table work to yield with no
completed slice above 8 ms. Transferable canonical serialization, hashing,
compression and container preparation run off the UI isolate; Flutter engine
objects and mutable publication state remain on it. Font evidence is retained
at compatibility scope and source font bytes can be released.

`CanonicalDisplaySegmentRecordBuilder.buildForPublication` returns either a
built record or a typed no-write result. Non-book-start records are admitted
only with accepted P04 continuation/predecessor and contextual anchor proof;
missing proof neither fabricates a restart nor retries. Publication remains
usable. Physical writes now enter a bounded one-concurrency derivative queue
after publication, coalesce equal canonical keys, cancel stale epochs and
isolate asynchronous failures. A fresh-service exact disk candidate is still
strictly admitted and republished through the canonical boundary.

Memory pressure cancels background/index/cache work, releases font/source/
table/codec/image intermediates and unpinned canonical derivatives, and keeps
the current visible card. Host retained-object evidence changed from two
current/adjacent sections and 13,404 estimated bytes to one current section and
9,908 bytes under pressure. Three sequential book switches remained
`[2, 2, 2]` retained sections and `[13404, 13404, 13404]` estimated bytes,
showing no monotonic host growth. This is not a post-fix Android PSS/RSS claim.

### Files and verification

Production correction files:
`lib/models/canonical_display_segment.dart`, `lib/screens/reader_screen.dart`,
`lib/services/canonical_display_cache_service.dart`,
`lib/services/display_generation_coordinator.dart`,
`lib/services/epub_parser.dart`,
`lib/services/frame_budgeted_range_scheduler.dart`,
`lib/services/lazy_book_session.dart`,
`lib/services/lazy_section_repository.dart`,
`lib/services/reader_card_paginator.dart`,
`lib/services/reader_font_evidence_gate.dart`,
`lib/services/reader_layout_contract_service.dart`, and
`lib/utils/reader_content_parser.dart`.

Focused test files:
`test/reader_contract/regression/reader_device_regression_test.dart`,
`test/reader_contract/pagination/canonical_display_cache_budget_test.dart`,
`test/reader_contract/pagination/reader_core_pagination_harness.dart`,
`test/unit/services/display_generation_coordinator_test.dart`, and
`test/unit/services/lazy_section_repository_test.dart`. Documentation files:
the plan, canonical-cache contract, reader-contract README and this ledger.
Frozen fixtures and oracles were not changed.

Recorded completed commands, all exit 0:

- Final scoped `dart format`: 17 files, zero changes in 0.62 seconds,
  command wall 0.9 seconds, exit 0.
- Final scoped `dart analyze`: no issues, command wall 3.2 seconds, exit 0.
- Derivative queue focused regression: 1/1 in 4.9 seconds.
- Active background-parse cancellation regression: 1/1 in 3.3 seconds.
- CHANGE-039 regressions plus generation/scheduler controls: 53/53 in 1 minute
  13 seconds.
- P06 admission/equivalence/invalidation/migration/budget/physical combined
  gate: 55/55 in 1 minute 8 seconds.
- Cache-service controls: 64/64, command wall 6.3 seconds.
- P04 continuation/publication/final gate: 25/25 in 4 minutes 38 seconds.
- P05 classifier/font/shared-layout controls: 96/96, reporter elapsed 14
  seconds and command wall 18.8 seconds.
- Frozen P03 and P02 controls: 66/66 in 3 minutes 16 seconds.
- Read-only `git diff --check`: clean, exit 0. Scoped trailing-whitespace
  review found no Dart issue and only the four pre-existing intentional
  Markdown hard-break lines.

Exact final scoped test commands were:

- `rtk dart format lib/models/canonical_display_segment.dart lib/screens/reader_screen.dart lib/services/canonical_display_cache_service.dart lib/services/display_generation_coordinator.dart lib/services/epub_parser.dart lib/services/frame_budgeted_range_scheduler.dart lib/services/lazy_book_session.dart lib/services/lazy_section_repository.dart lib/services/reader_card_paginator.dart lib/services/reader_font_evidence_gate.dart lib/services/reader_layout_contract_service.dart lib/utils/reader_content_parser.dart test/reader_contract/regression/reader_device_regression_test.dart test/reader_contract/pagination/canonical_display_cache_budget_test.dart test/reader_contract/pagination/reader_core_pagination_harness.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/display_generation_coordinator_test.dart`
- `rtk dart analyze lib/models/canonical_display_segment.dart lib/screens/reader_screen.dart lib/services/canonical_display_cache_service.dart lib/services/display_generation_coordinator.dart lib/services/epub_parser.dart lib/services/frame_budgeted_range_scheduler.dart lib/services/lazy_book_session.dart lib/services/lazy_section_repository.dart lib/services/reader_card_paginator.dart lib/services/reader_font_evidence_gate.dart lib/services/reader_layout_contract_service.dart lib/utils/reader_content_parser.dart test/reader_contract/regression/reader_device_regression_test.dart test/reader_contract/pagination/canonical_display_cache_budget_test.dart test/reader_contract/pagination/reader_core_pagination_harness.dart test/unit/services/lazy_section_repository_test.dart test/unit/services/display_generation_coordinator_test.dart`
- `rtk flutter test test/reader_contract/regression/reader_device_regression_test.dart test/unit/services/display_generation_coordinator_test.dart test/unit/services/frame_budgeted_range_scheduler_test.dart`
- `rtk flutter test test/reader_contract/pagination/canonical_display_segment_admission_test.dart test/reader_contract/pagination/canonical_display_cache_equivalence_test.dart test/reader_contract/pagination/canonical_display_cache_invalidation_test.dart test/reader_contract/pagination/canonical_display_cache_migration_test.dart test/reader_contract/pagination/canonical_display_cache_budget_test.dart`
- `rtk flutter test test/unit/services/book_cache_service_test.dart test/unit/services/segmented_display_cache_service_test.dart test/unit/services/display_section_memory_cache_test.dart test/unit/services/parsed_section_cache_service_test.dart test/unit/services/lazy_section_repository_test.dart`
- `rtk flutter test test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/reader_contract/pagination/reader_card_paginator_p04_final_gate_test.dart`
- `rtk flutter test test/reader_contract/layout/reader_compatibility_classifier_test.dart test/reader_contract/layout/reader_font_evidence_gate_test.dart test/reader_contract/layout/reader_layout_construction_order_smoke_test.dart test/reader_contract/layout/reader_layout_contract_shared_test.dart test/reader_contract/layout/reader_layout_standard_transition_test.dart test/reader_contract/layout/reader_transient_state_invariance_test.dart`
- `rtk flutter test --no-pub --no-track-widget-creation --reporter compact test/reader_contract/pagination/reader_card_paginator_full_range_characterization_test.dart test/reader_contract/pagination/reader_card_paginator_target_first_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_forward_backward_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_singleton_expansion_matrix_test.dart test/reader_contract/pagination/reader_card_paginator_structural_ownership_test.dart test/reader_contract/pagination/reader_card_paginator_cache_order_test.dart test/reader_contract/pagination/p03_failure_ledger_integrity_test.dart test/reader_contract/pagination/reader_card_paginator_parity_test.dart test/reader_contract/parser_source/reader_contract_fixture_test.dart`

The first five resumed test commands used Flutter's default package-resolution
step; it printed its standard package availability output. No dependency was
added and the already-dirty lockfile was not intentionally edited. The final
frozen command used `--no-pub`; no separate network operation was run.

The queue regression first failed because the isolate closure captured an
unsendable service Future; a later failed assertion identified a test snapshot
taken after release. The title-boundary regression initially proved only the
first chapter and was strengthened to cross into the next chapter. The active
hydration regression first showed later sections continued after cancellation,
which led to the repository pause/epoch correction. These are recorded failing
regressions, not device-attribution claims.

Structural performance evidence is one authoritative start per stable request,
one publication, joined duplicates, zero cache work awaited before display,
zero whole-book indexing before display, a bounded source window, deterministic
cooperative yields, no automatic deterministic-failure retry and no stale
publication/write authority. Host tests do not establish cold/warm device time
to first readable card, post-fix device PSS/RSS, or absence of a remaining
platform-only synchronous stall. Those values and the five named scenarios
remain the owner device gate.

The normalized P06 hash remains
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`;
the frozen P03 hash remains
`fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`.
Strict P03–P06 identity, seam, continuation, compatibility and publication
authority remain intact. Checkpoint schema, stable-location semantics,
restoration authority, user data and dependency/lock state were not changed by
this correction.

## CHANGE-20260919-040 — Specify lazy snapshot handoff and input-exhaustion semantics

Recorded 2026-09-20; the change ID/title are owner-specified.

- Task: `DESIGN-P04-LAZY-SNAPSHOT-HANDOFF` only.
- Baseline/recovery: `a130bda2785a57ed2e94ae3fd0630572d3f9d010` on
  `rescue/change-039-device-failure-2026-09-19`.
- Outcome: `DESIGN_SPECIFIED_WITH_IMPLEMENTATION_GATES`. No production
  correction, schema/version change, device execution, commit or push.
- Requirements: REQ-007–REQ-013, REQ-027–REQ-030, REQ-040, REQ-043–REQ-045,
  REQ-048 and REQ-051; this entry does not mark them newly verified.
- Protected evidence: `terminal_out.md`, `nalori-logcat.txt`,
  `nalori-last-anr.txt`, `nalori-meminfo.txt`, `regression.mp4` remain untracked
  and untouched. No recovery history or previous ledger entry was rewritten.

### Superseding gate decision

Latest owner ordinary A059 evidence invalidates CHANGE-039's host-only success
claims. P04's loaded-snapshot completeness assumption requires architecture
correction: immutable content is not proof that the publication ends there.
P04's relevant lazy-input/publication exit gate is now
`ARCHITECTURAL_CORRECTION_REQUIRED`, with all eight historical tasks preserved.
P06 is `REGRESSED_ON_DEVICE` at 7/7; overall progress remains 46/89. P07 is
unstarted and blocked. A correction is not implemented, so
`CORRECTION_IMPLEMENTED_NOT_DEVICE_VERIFIED` is not the status of CHANGE-040.

### Inspection and selected contract

Inspected canonical snapshot/continuation construction and codec; the sole
production terminalBookEnd reason assignment and terminal cursor/frontier
validation; session initial/target/forward/backward/deferred publication;
checkpoint index/restart bounds; screen window creation/append/eviction and
catch/warmup/hydration; stable section/source/spine authority; progressive
append/replacement; P06 segment construction, admission and end-cursor
persistence; and source/layout identity and exact-card dependencies.

The selected contract is
[`nalori-lazy-snapshot-handoff-design.md`](nalori-lazy-snapshot-handoff-design.md).
It contains the full field tables, state distinctions, authority audit,
transaction steps, boundedness/retention/backward rules and next-task prompt.

Choose a sealed section-end receipt plus authenticated successor session over
immutable A+B. Verify every A owner/record as an exact prefix, preserve all
accepted card bytes/signatures, and append only B through a dedicated atomic
handoff transaction. The receipt is not a terminal continuation. Only immutable
spine plus complete final-section evidence authorizes terminalBookEnd.
Ordinary snapshot/session rejection, continuation parent validation and all
structural/source checks stay strict. New display generation, old-card repack,
mutable snapshot, terminal-bit clearing and forged continuation parents are
rejected alternatives.

Handoff fields bind publication/spine/parser/dependency authority; old/new
snapshot digests/revisions and exact prefix; parent/successor session lineage;
receipt, accepted publication, committed and suffix card identities/bytes;
next expected stable owner/cursor and hard-section seam; F196/F206/F204/F207,
font delivery, old/new source evidence and integrity digest. Runtime epoch,
publication revision and cancellation/retry owner form a separate CAS envelope.
Demand and warmup join/promote one owned attempt; failure settles and latches
all matching work until explicit retry without changing the readable card.

P05 dependency: current controlled identity includes F202's snapshot digest.
The design specifies a stable lazy packing identity with separate mandatory
per-snapshot/per-source proof. It does not pretend A and A+B have equal F202
or change the existing P05 codec. Legacy exact-checkpoint behavior must be
proved before production wiring; no silent re-signing or semantic downgrade.

### Files and scope

| File | Change |
| --- | --- |
| `docs/development/nalori-lazy-snapshot-handoff-design.md` | New concrete handoff contract, rejection choices, field tables, boundedness and blocked-seam inventory |
| `docs/development/nalori-canonical-pagination-design.md` | Reopened lazy gate and corrected terminal authority; historical specification retained with explicit superseding addendum |
| `docs/development/nalori-reader-canonical-display-cache-contract.md` | Reopened P06 and specified contextual terminal/publication-start admission and safe-miss consequences |
| `docs/development/nalori-reader-reliability-plan.md` | Current gate/requirement qualifications and dashboard; no checklist count changes |
| `test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart` | New deliberately red production-entry characterization and real-final-section control; no existing/frozen test changes |
| This ledger | Append-only design, regression, test and limitation evidence |

### Red characterization results

Final command:

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart
```

Result: **1 passed, 4 failed, 0 skipped**, exit **1**, about **10 seconds**.
The corrected fixture setup reached the intended assertions in two completed
runs, before and after removal of redundant default arguments.

| ID | Actual production evidence | Result / scope |
| --- | --- | --- |
| H01 | Real parsed first section has 14 chunks and a verified lazy-index successor; pagination produces `CanonicalPaginationCheckpointReason.terminalBookEnd` | RED: expected not terminalBookEnd |
| H02 | Real successor adds four chunks; A's pinned digest/count stay unchanged; `generateForward` returns `terminalStateContradiction: A terminal continuation cannot be resumed.` | RED: expected accepted result; public lazy/session composition, not private screen integration |
| H03 | Simultaneous speculative/boundary-priority calls on the same accepted suffix both return that exact terminal rejection | RED: both expected accepted; does not prove screen join/callback ordering |
| H04 | `readerShouldSurfacePreparationFailure('lazy_forward_boundary')` returns false | RED: expected true; predicate coverage only, not caught-error/upstream settlement |
| H06 | Real final linear section has no successor and returns terminalBookEnd, logical-end cursor, empty frontier and codec-accepted continuation | GREEN genuine-end control |

No fake pagination or lifecycle implementation was used. The existing small
EPUB builder/parser and controlled layout harness are reused unchanged. The
test loops invoke only production initial/forward pagination, bounded to 25
steps over the micro-fixture, and do not implement packing decisions.

Two initial attempts failed during test input setup because the explicit
stable target omitted local-chunk/parser-version evidence; those errors are
**not** counted as defect characterization. The test setup was corrected to
provide chunk zero and the real lazy parser version. No production code was
changed to make setup or assertions work. Initial analysis reported two
redundant-default infos; both were removed. A later interruption left two
tool-session results unavailable; their outcomes were not inferred and the
final characterization/analysis commands were rerun to captured completion.

### Missing deterministic production seams (not claimed as tests)

Full requested cases 3–5 remain blocked on private ReaderScreen scheduling,
catch and hydration state. The source/device evidence shows range failure
reported and then append/navigation/prefetch completion, but a fake catch or
a manually resumed hydration loop would not prove that production path.

The design specifies the exact minimum seam: optional state-bound test access
to the existing adjacent/warmup/hydration methods and read-only owned
completion/publication/failure state, with deterministic hooks at existing
warmup/quiet scheduling boundaries. Existing repository parser/coordinator
injection can hold queued parsing. No seam is introduced here; no P07 general
lifecycle harness was begun. Implementation must first use this seam to
prove caught failure reaches upstream as failure and blocks queued hydration,
repeat requests, rebuilds and stale book-close/switch callbacks.

### Controls and scope verification

```sh
rtk dart format test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart
rtk dart analyze test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart
rtk flutter test --no-pub test/reader_contract/pagination/reader_card_paginator_continuation_checkpoint_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart test/unit/services/display_generation_coordinator_test.dart
rtk git diff --check
```

- Format: clean final file, exit 0.
- Scoped analysis: **No issues found**, exit 0.
- Existing controls: **55 passed**, exit 0, **1 minute 6 seconds**. These prove
  the current fixed-snapshot contracts, not the new handoff or device behavior.
- No production files, frozen P02–P06 test/oracle files, dependencies or
  persistent schemas changed. No new full-suite or device success is claimed.

### Compatibility, bounds and regression-register additions

Keep physical `canonical_display_v4`, continuation v1 and checkpoint/location
schemas unchanged. Partial-window terminal records become typed safe misses
under independent contextual end proof, not converted continuations. A local
ordinal zero cannot prove publication start. Suspended/handoff-spanning records
have no write authority until separate persistence design; ordinary strictly
representable segments remain eligible. New lazy packing identity separates
new signatures from old window-dependent signatures. Preserve old checkpoint
bytes and return explicit exact-unavailable when bounded exact proof fails;
do not migrate/reset implicitly. No version constant was changed here.

Bounds are aggregate across live/retired sessions: existing two-card frontier,
48-source/eight-card cadence, 110/158 work envelopes, 432 resident canonical
sources, 96 cards, 25 continuation/receipt/lineage guards and current parsed
retention limits. One section/one owned handoff per attempt, no retained
growing snapshot chain; byte-batched hashing and 64 KiB receipt/handoff metadata
cap are specified. Exact suffix retention and backward reconstruction need
independent proofs before implementation. Oversized sections cannot justify
whole-book work or disabled demand navigation.

| Regression ID | Requirements | Evidence | Status |
| --- | --- | --- | --- |
| REG-040-LAZY-END | REQ-007, REQ-010, REQ-013, REQ-048 | H01/H02 and owner continuation failure | OPEN — P04 architectural correction required |
| REG-040-FAILURE-SETTLEMENT | REQ-029–REQ-030, REQ-043–REQ-045, REQ-051 | H03/H04 partial evidence; source/device completion and hydration path; missing screen seam disclosed | OPEN — P06 device regression |
| REG-040-TERMINAL-CACHE | REQ-009–REQ-010 | Builder/admission rely on snapshot-local terminal evidence without spine completeness | OPEN — contextual end proof and compatibility tests required |

Test-removal/replacement ledger: none. No frozen test was changed, removed,
skipped or given a new expected value. This is new red characterization.

### Next task and blockers

Exact next task: `IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001 — Prove lazy handoff
authority and failure settlement before wiring snapshot transfer`.

Use the bounded prompt in section 10 of the new design. First prove the real
screen seam/failure cases, lazy packing compatibility plus legacy exact
checkpoint outcome, and bounded retention/backward transfers after multiple
handoffs. No production handoff wiring is authorized by this design-only task.
Do not broaden it into persistent-schema changes, restoration/reset UX,
whole-book parsing, relaxed validation or P07. Stop for a further design
decision if the required exact restoration or source-address-space proofs
cannot be satisfied within those limits. Owner A059 verification remains
mandatory after a future correction; the 55 passing controls do not close it.
