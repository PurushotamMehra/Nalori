# First finalized successor batch and bounded forward continuation

Date: 2026-09-27. Branch: `rescue/change-039-device-failure-2026-09-19`.
Baseline/unchanged HEAD: `b1aef7ebc1f14ed84a489c598dbffdf0a9dd247e`.

Implements the forward partial-successor amendment in
[handoff design §15](nalori-lazy-snapshot-handoff-design.md#15-partial-successor-pagination-amendment-2026-09-27),
using the [yielding core](nalori-yielding-handoff-proof.md). No stable format,
ordinary append rule, P05 admission rule or persistence schema changed.
Previous proofs/oracles/diagnostics are preserved. No device, commit, push,
scrubber, P07 or ReaderScreen work was performed. P04/P06 stay open at **46/89**.

## Production capability and transitions

A sealed A may hand off to **a finalized prefix of B**, preserving all accepted
A objects, bytes, guards, source ownership and renderer authority. The caller
uses `beginNextYielding`, then `prepare(..., firstBatchOnly: true)`, then
`publishYielding`. The first-batch route requests at most two finalized cards
per paginator call, with the normal bounded frontier/lookahead. It stops when
a nonempty finalized batch is available, rather than driving B to completion.
Zero finalized output is never presented as a readable accepted card.

`LazyPreparedSection` now pins its continuation and completion state instead
of exposing a mutable session's suffix through a getter. Its yielding validator
proves exact ordered B source coverage from the section root through the last
finalized interval. Missing, duplicate, reordered or overlapping slices still
reject. For unfinished B it additionally requires the actual accepted
nonterminal continuation and matching finalized-card boundary. Complete
sections still require complete source coverage. The synchronous full-section
validator rejects unfinished authorities.

The handoff retains the existing sealed-A receipt and exact A+B source extension
proof. Only finalized B cards enter the atomic publication. A current candidate
must still match its pinned session when committed. `generationComplete` now
requires both completed pagination and verified book-end source authority;
loading the final spine section alone cannot mark pagination complete.

| State | Evidence and authority |
| --- | --- |
| Unfinished B | Nonempty finalized prefix; exact nonterminal continuation/frontier; `sectionComplete == false`; no B receipt; no book-end flag. |
| Loaded input exhausted, successor known | Production `inputExhaustedAwaitingSuccessor`, complete coverage and empty sealed frontier; `sectionComplete == true`; B receipt; no book-end flag. |
| Verified book end | Actual terminal pagination plus immutable final-spine evidence and complete coverage; `sectionComplete == true`; terminal continuation, no section receipt. |
| Private work rejected/cancelled/stale | Prior publication and continuation remain accepted; pending branch is released after settlement. |

For more B cards, `beginContinuation(operation)` creates a token bound to the
accepted publication/visible position, and `prepare(token, acceptedB.session.layout,
operation)` prepares a private forward branch. It does not parse, recapture B,
rebuild its layout or call `generateInitial`. `forkForForward` shares immutable
source/cards/layout and uses the existing **validated checkpoint `forkAt`** to
keep the exact accepted suffix and its parent. `generateForward` preserves the
ordinary continuation codec/parent/frontier validation. It neither re-roots nor
relabels a terminal continuation.

`extendLazyYielding` checks actual fork provenance, exact parent-continuation
digest, identical source/layout authority, all accepted card/body objects and
guards, and the candidate's validated ordered coverage. It builds projections
privately and atomically adopts only the new suffix after rechecking ownership,
publication, visible position and session state. Handoff ordinal/source authority
remain unchanged during same-section extension. Stable bodies are reused for
old cards; those cards are never regenerated or re-signed.

Cancellation during private continuation leaves the accepted session untouched.
A later explicit request forks that same accepted suffix and progresses without
rebuilding B. Cancellation while a slice is held remains counted/busy until
settlement. Stale/visible-position races at commit and replayed tokens reject.

Retirement/backward preparation still require a completed section. An unfinished
frontier pins A+B; this task does not transfer that frontier to a B-only snapshot.
After B completes, existing retirement/backward paths work: the new test retires
A, reconstructs A backward, retires B, and performs a first-batch handoff to B
again. Retained renderer leases remain checked by the existing core.

## Work still required before first acceptance

This is **first-batch pagination**, not chapter-size-independent first-card
latency. Before first B acceptance:

- The caller still parses the complete B section. The test uses the real EPUB
  repository/default parser to load A and B, each as a complete parsed section.
- `beginNextYielding` still captures and validates **all B source records**, its
  section identity, membership and digest, then forms/digests the immutable A+B
  source view. No partial-source capture/subdivision was introduced.
- A complete source-bound layout contract must already be supplied. The fixture
  helper captures font evidence for its representative source and builds the
  contract for the full snapshot. The core reuses that contract; the production
  paginator performs layout work for entered sources/frontier candidates, and
  strict font/image/renderer admission runs for emitted/retained cards.
- All retained A cards and the A prefix/source extension are validated before
  handoff. B's emitted stable bodies include complete section membership, so
  encoding/hashing still depends on B's source count even for two cards.
- Finalized-prefix validation covers the accepted prefix; it does not require
  pagination/coverage of unconsumed B. Subsequent requests revalidate the current
  accepted prefix within the resident bounds, so their validation cost can grow
  with the resident card count.

The yielding scheduler remains in use. Indivisible SDK/P05 operations listed
in the preceding yielding proof remain unproved for physical frame latency.
No injected clock result is presented as a device measurement.

## Executable evidence and bounds

The new real-production test file has 11 cases:

- P01 (two cases): known-successor and final-book B, first **2/24** finalized
  cards after **3** pagination work entries versus **24** for the full reference;
  12 successive batches produce exactly the reference stable bodies and guards.
  Accepted objects remain identical across extensions. Cursor hints advance
  through `[5,7,9,11,13,15,17,19,21,23,25]` in the A+B view; B's root is ordinal 2.
  These hints are observations, not source authority. Final section/book-end
  statuses, renderer lease validity and post-completion retirement are checked.
  The successor-known case also checks completed-B backward reconstruction and
  a fresh forward first-batch handoff.
- P02 (four cases): cancellation/staleness before first publication and while
  later B work is deterministically held. Already accepted B and its exact
  continuation stay readable/unchanged; explicit continuation subsequently works.
- P03 (two cases): cancellation/visible change at extension commit preserves B;
  replay rejects and cannot clear later demand.
- P04: a tightened six-card core limit admits the first batch but refuses later
  private work when accepted cards plus live frontier/private reservation would
  exceed the allowance. Accepted B and its continuation survive.
- P05: strict renderer-overflow rejection remains enforced for the initial
  long-paragraph probe; no first-card publication is fabricated.
- P06: 48 finalized cards over **24 batches**, byte-identical to the full
  reference, with at most three records in the current B checkpoint index,
  bounded aggregate guards, two settled sessions (A/current B), and no pending
  work/history of old session forks after each acceptance.

The core counts active and pending sessions, exact checkpoint parents/frontiers,
private candidates, all source roots, rendering leases and yielding reservations.
The card ceiling now also checks live continuation frontier candidates. Partial
preparation reserves space for the ordinary two-card private frontier before
pagination, rather than treating the entire available card allowance as output.
Checkpoint pruning uses validated existing `forkAt`, never digest fabrication or
an old-session reference chain. The parent provenance marker is an inert object;
it does not retain the old session or publication.

Limits remain **432 source units, 96 cards, 25 guards, three sections, 6 MiB,
64 KiB metadata**, with the existing normal 110-entry per-request work envelope.
The reference fixture's whole-section work also fits that envelope. Refusal
preserves accepted cards instead of evicting required authority or rebuilding.
These are core-owned storage estimates, not heap/RSS or whole-app memory.

Observed peaks after exact-parent checkpoint retirement:

| Quantity | 24-card final B | 48-card / 24-batch B | 24-card B plus backward/forward roundtrip |
| --- | ---: | ---: | ---: |
| Source units including scratch/raw | 77 | 149 | 77 |
| Snapshots | 3 | 2 | 4 |
| Sessions including private branch | 3 | 3 | 3 |
| Renderer authorities | 2 | 2 | 3 |
| Finalized cards including private verification | 26 | 50 | 50 |
| Aggregate guards | 11 | 11 | 12 |
| Accounted bytes | 797624 | 1521126 | 1684050 |
| Pending transfers | 1 | 1 | 1 |
| Frontier reservation including work scratch | 4 | 4 | 4 |

After each accepted batch of the longer test, only A and the current B session
remain. After its final batch: seven guards, no pending work/frontier, and
1,358,644 accounted bytes. The separate post-completion retirement tests return
to zero sessions and one retained source view. No limit was raised.

## Verification ledger

Tests ran with host Flutter/Dart SDK cache permission. Each test command was
wrapped in `rtk proxy python3`, using `subprocess.run`, combined output to the
listed `/tmp` log, and an actual return code in its matching `.exit` file.
The SQLite controls use the existing `/tmp/nalori-stable-sqlite` alias.

| Log basename | Result | Exit |
| --- | --- | ---: |
| `nalori-first-batch-initial` | 0 passed / 6 failed, initial long-paragraph fixture | 1 |
| `nalori-first-batch-diagnostic` | 0 passed / 1 failed, same fixture's full-reference diagnostic | 1 |
| `nalori-first-batch-second` | 6 passed / 0 failed, admitted structural fixture | 0 |
| `nalori-first-batch-expanded` | 10 passed / 0 failed, added commit/budget/backward controls | 0 |
| `nalori-first-batch-final` | 77 passed / 0 failed: 10 new + 67 existing handoff/yielding controls | 0 |
| `nalori-first-batch-controls` | 27 passed / 0 failed: canonical state machine and strict publication transactions | 0 |
| `nalori-first-batch-guards` | 11 passed / 0 failed: focused cases after exact-parent guard retirement | 0 |
| `nalori-first-batch-retirement-pin` | 2 passed / 0 failed: existing P01 cases additionally reject prefix retirement while B is unfinished | 0 |

The initial fixture had one heading and 24 seventy-word paragraphs. Its partial
preparation rejected with `Resolved card contains an overflowing block.` The
complete reference diagnostic rejected with `Terminal evidence contradicts the
cursor, frontier, or reason.` Those paths were not repaired or reclassified as
success. P05 preserves the first rejection as a strict admission control. The
positive equality fixture uses short heading/paragraph pairs whose complete
production reference is admitted within existing limits; no frozen fixture,
validator or existing expected result was changed. The separate terminal/frontier
rejection of the long-paragraph probe remains an unresolved limitation.

The 77-case run preceded the small checkpoint-fork retention refinement. The
11-case focused rerun exercises that refinement across 24 batches and reruns
all new first-card cases; full-section callers do not use the new fork method.
Final review also tightened both retirement directions: even when A remains
visible, selecting complete A for prefix retirement must not silently discard
unfinished B. The two P01 cases rerun that exact assertion plus completion,
suffix retirement and the completed-section backward path. This does not add
new unique cases. No preceding 286-case matrix or unrelated screen/parser/device
suites were run.

Exact test commands (the focused command was repeated only for the documented
fixture correction, added cases and guard-retention refinement):

```sh
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_first_batch_handoff_test.dart
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_first_batch_handoff_test.dart --plain-name 'P01 finalized first batch and incremental exact output finalB=false'
rtk flutter test --no-pub --reporter expanded test/reader_contract/regression/lazy_first_batch_handoff_test.dart test/reader_contract/regression/lazy_single_handoff_test.dart test/reader_contract/regression/lazy_forward_retention_test.dart test/reader_contract/regression/lazy_backward_handoff_test.dart test/reader_contract/regression/lazy_yielding_handoff_test.dart
rtk proxy env LD_LIBRARY_PATH=/tmp/nalori-stable-sqlite rtk flutter test --no-pub --reporter expanded test/reader_contract/pagination/reader_card_paginator_canonical_state_machine_test.dart test/reader_contract/pagination/progressive_display_state_canonical_transaction_test.dart
```

The control wrapper supplies that library path through Python's environment
argument. **105 distinct cases pass**: 11 new, 67 handoff/yielding controls and
27 canonical state-machine/publication controls. Intermediate passes and narrow
reruns are not added to that count. The retirement-pin command adds
`--plain-name 'P01 finalized first batch and incremental exact output'` to the
focused file command above.

Final scoped static analysis reports **no issues**, exit **0**; format exits
**0**, and `rtk git diff --check` is clean, exit **0**. Logs and matching exit
files: `/tmp/nalori-first-batch-final-analyze` and
`/tmp/nalori-first-batch-final-format`. The final post-test pass changed only
formatting. Exact commands:

```sh
rtk dart analyze lib/services/lazy_forward_handoff_core.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/progressive_display_state.dart lib/services/reader_card_paginator.dart test/reader_contract/regression/lazy_first_batch_handoff_test.dart test/reader_contract/regression/support/lazy_address_fixture.dart
rtk dart format lib/services/lazy_forward_handoff_core.dart lib/services/lazy_snapshot_handoff_service.dart lib/services/progressive_display_state.dart lib/services/reader_card_paginator.dart test/reader_contract/regression/lazy_first_batch_handoff_test.dart test/reader_contract/regression/support/lazy_address_fixture.dart
rtk git diff --check
```

## Changed files and remaining requirements

```text
docs/development/nalori-lazy-snapshot-handoff-design.md
docs/development/nalori-first-batch-handoff-proof.md
lib/services/lazy_forward_handoff_core.dart
lib/services/lazy_snapshot_handoff_service.dart
lib/services/progressive_display_state.dart
lib/services/reader_card_paginator.dart
test/reader_contract/regression/lazy_first_batch_handoff_test.dart
test/reader_contract/regression/support/lazy_address_fixture.dart
```

Protected untracked artifacts remain excluded and unchanged: `nalori-last-anr.txt`,
`nalori-logcat.txt`, `nalori-meminfo.txt`, `regression.mp4`, `terminal_out.md`.

Remaining requirements: partial/oversized source capture and subdivision;
empty-section chains; first-card backward reconstruction; retirement of A while
B still has a live frontier; the observed long-paragraph rejection paths;
remaining indivisible UI-isolate operations; ReaderScreen integration;
post-handoff reopen/checkpoint/persistence integration; physical-device proof.
Whole-section parsing/capture and membership work remain before the first batch.
