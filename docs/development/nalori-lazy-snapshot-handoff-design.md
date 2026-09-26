# Canonical lazy snapshot handoff

Task: `DESIGN-P04-LAZY-SNAPSHOT-HANDOFF`

Change: `CHANGE-20260919-040 — Specify lazy snapshot handoff and input-exhaustion semantics`

Recorded: 2026-09-20 (requested change ID retained)

Baseline: `a130bda2785a57ed2e94ae3fd0630572d3f9d010`, branch
`rescue/change-039-device-failure-2026-09-19`

Status: DESIGN_SPECIFIED_WITH_IMPLEMENTATION_GATES; no production correction.

This addendum supersedes the loaded-snapshot end assumption in P04 sections
4, 7, 9, 10 and 17 and qualifies P06 terminal admission. It does not rewrite
their historical task evidence. P04's lazy-input/publication exit gate is
`ARCHITECTURAL_CORRECTION_REQUIRED` (8/8 historical tasks); P06 is
`REGRESSED_ON_DEVICE` (7/7); overall progress is 46/89. P07 is unstarted.

## 1. Invalidated assumption and inspected paths

An immutable source snapshot proves its own contents, not completeness of the
publication. At baseline `paginateCanonical` sets its end ordinal to
`snapshot.sourceCount`; `_runEngine` calls equality with that count a trusted
logical end. This produces a validly encoded but semantically false book-end
claim for a lazy window. The EPUB index can simultaneously prove a successor.

| Inspected authority/path | Finding and consequence |
| --- | --- |
| `canonical_pagination.dart`: snapshot pinning, cursor, continuation create/codec | Pinning copies canonical records; digest includes count, all owners and records. Codec requires `terminal == terminalBookEnd == nextCursor.isLogicalEnd` and empty terminal frontier. Keep those checks. |
| `reader_card_paginator.dart`: `paginateCanonical`, `_runEngine`, `_buildContinuation` | One production assignment of checkpoint reason `terminalBookEnd`; terminal bool follows engine logical end or end cursor plus empty frontier. Trusted internal section boundaries already finalize under a hard reset. |
| Same file: `_validateContinuationForRequest` | Exact source revision/digest, layout, algorithm, parent, ordinal and cursor checks; terminal resume and terminal parent reject. Do not bypass them. |
| `CanonicalReaderPaginationSession`: constructor, `generateInitial/Target/Forward`, `_trustedSectionStartFor`, `_acceptSingle`, deferred commit | One final snapshot and checkpoint index per session; forward resumes its accepted suffix. No existing expanded-snapshot handoff. Target restart selects compatible checkpoint or trusted section root. |
| `ReaderScreen`: `_rebuildDisplayChunksAsync`, `_canonicalPaginationSourceKeys`, `_appendLazySectionToSourceWindow`, `_integrateLazyForwardSection` | Pins current window once; later append changes source/projection arrays, not the captured session. Source revision cancellation also becomes true after the append. Terminal validation can reject before cancellation is examined. |
| Screen eviction/backward integration | Canonical eviction remap is rejected; replacement clears progressive state and enables another rebuild. Canonical backward insertion also cannot use the noncanonical incremental path. These must become explicit authority transfers, not implicit regeneration. |
| `ProgressiveDisplayState.publishCanonical` | Ordinary append requires same session/snapshot and exact parent/seam. Replacement can discard publication; it is not an implementation of handoff. |
| `LazyEpubIndex`, `LazySectionIdentity`, `LazySourceChunkIdentity`, `LazyBookSession` | Spine gives ordered linear candidates; section identity includes checksum/parser/dependency evidence; source owner adds section-local chunk index. `nextReadableSpineIndex` also consults mutable known-empty residency, so its return value alone is not immutable proof. |
| `CanonicalPaginationCheckpointIndex`, backward regeneration | Index belongs to exactly one snapshot; at most two restart candidates, bounded forward regeneration and exact committed-card/successor proof. Copying checkpoints to a new digest would forge authority. |
| `CanonicalDisplaySegmentRecordBuilder`, admission, cursor derivation | Builder converts terminal bool to `logicalEnd` right proof. Admission checks codec and matching snapshot but lacks independent publication-end proof. Card-end helpers in paginator, progressive state, segment model/admission also infer logical end from last snapshot ordinal. All require audit in implementation. |
| `ReaderLayoutContractBuilder`, `ReaderLayoutContract.identity` | F202 includes source revision/snapshot digest; both compatibility composites include F202. Using a freshly built A+B composite as the same packing identity would change signatures. |
| Restoration and backward source projection | Exact card signatures and stable source ranges are authority. Window/display/source ordinals are lookup hints; an old signature cannot be silently replaced by a newly signed card. |

The device trace shows a terminal rejection followed by completion messages
and another adjacent request. Range preparation catches/reports the rejection
and resolves `Future<void>` normally. `lazy_forward_boundary` is excluded by
`readerShouldSurfacePreparationFailure`. Warmup then reaches hydration, which
has no display-failure input and iterates readable sections. The supplied
logcat directly proves generation 2 -> failed append -> eviction replacement
-> generation 3. It does not establish the generation-1-to-2 trigger in that
same process. Do not combine the different terminal/logcat runs into one trace.

## 2. Selected architecture and invariant

Select **a sealed section-boundary receipt followed by an authenticated
successor session**. A remains immutable. Build A+B privately, prove the exact
prefix, and start the successor at B's verified section root with an empty
frontier. A dedicated handoff-append transaction adopts that successor and
appends only new cards. It never restarts/repackages A and never manufactures
a nonterminal version of A's terminal continuation.

This is a new in-memory authority operation, not ordinary append, not a new
display generation, and not a serialized continuation-schema extension.
Handoff lineage advances on successful integration, never as automatic error
recovery. Snapshot eviction uses a separately proved retention transfer (§7).

Invariant: **An accepted publication may change source authority only by a
current, single-use transfer proving unchanged retained source owners and
accepted card bytes/signatures, exact hard-section adjacency, compatible
packing evidence, and a valid successor root. Failure changes neither the
publication nor its authority and prevents all matching work until retry.**

Rejected alternatives:

- clear `terminal`, resume it, or forge its parent/digest: violates codec and
  chain evidence, and cannot add missing source to immutable A;
- treat `terminalBookEnd` as input exhaustion: contradicts book-end/cache proof;
- mutate A or its resolver/list: invalidates every accepted snapshot digest;
- new generation/full-range replacement: repacks published cards and masks
  deterministic failure; forbidden even if later card text looks identical;
- feed a root continuation for B to ordinary append: loses parent/seam proof;
- assume that any partial chunk boundary is a safe section root: can flush a
  provisional same-section tail;
- retain A, A+B, A+B+C indefinitely: unbounded source, checkpoint and lineage
  memory; retention transfer is mandatory.

## 3. Three different outcomes, and publication-end authority

| Outcome | Required evidence | Resume/publication behavior |
| --- | --- | --- |
| `inputExhaustedAwaitingSuccessor` | Complete current parsed section, sealed hard section boundary, immutable spine authority names a successor candidate | Empty frontier may publish finalized section tail; return a section-end receipt, **not** a v1 terminal continuation. Await/deduplicate a handoff. |
| `verifiedLogicalBookEnd` | Complete final linear section and immutable spine authority proves no later linear section (or a verified chain of empty sections reaches that end) | Finalize terminal tail and create the existing valid `terminalBookEnd` continuation. It is never resumable. |
| `cancelled / stale / failed` | Operation ownership mismatch, cancellation, or typed deterministic rejection | No new continuation, receipt, publication or cache-write authority. Cancelled/stale work settles quietly; deterministic failure latches. None means book end. |

Within a section, an input limit is still provisional budget exhaustion: keep
the two-card frontier and obtain more of that *same section* under bounded
work. No section-end receipt is permitted without complete-section evidence.
Unknown availability is `needsSourceEvidence`, never implicit book end.

Create an immutable `PublicationSpineAuthority` from a defensive copy of the
opened index: book ID, publication fingerprint, index schema, parser and
dependency identities, and a domain-separated digest over every ordered
`(spineIndex, idRef, normalizedHref, fullPath, isLinear, sourceChecksum)` tuple.
This is metadata, not whole-book content parsing. Pin it to the file/index
identity used to parse sections; on file/publication change reject the owner.
Do not use a live List or the current resident `knownEmpty` map as proof.

It proves the next **candidate section exists**, not that it contains readable
text. Loading an empty section yields an immutable empty-section certificate
with its complete parsed source digest and parser/dependency identities. Each
bounded attempt loads at most one candidate. Empty candidates advance an
aggregate adjacency digest and stable candidate cursor, never recurse over
the book in one task. Reaching the final candidate with valid empty proofs
can establish logical end. Nonlinear items are skipped only by the pinned
linear reading-order policy; explicit nonlinear targets retain their separate
navigation scope and must not claim the linear book has ended.

## 4. Exact records and prefix proof

All encodings below are domain-separated canonical encodings; SHA-256 digests
are recomputed from fields, never caller-trusted strings. Types are proposed
in-memory types, not new persisted fields. Runtime tokens are a separate
authorization envelope and do not contribute to stable identity.

`SectionEndReceiptV1` contains:

- `kind`, `bookId`, `publicationFingerprint`, `spineAuthorityDigest`;
- `snapshotDigest`, `sourceRevision`, `parserSourceIdentity`,
  `sectionIdentity`, `sectionSourceCount`, `sectionSourceRecordsDigest`,
  `completeSectionProofDigest`;
- `lastConsumedOwner` (full stable owner including section-local index and
  source digest), `sectionEndPosition` (UTF-16/table/atomic exclusive end),
  `emptyFrontierDigest`, `lastAcceptedContinuationDigest` if one exists;
- `lastFinalizedCardSignature`, `lastFinalizedCardBytesDigest`,
  `lastFinalizedSlicesDigest`, `nextCandidateSpineIdentity`;
- `packingIdentity`, `sourceCompatibilityEvidenceDigest`, `receiptDigest`.

`sectionEndPosition` is a tagged **section end**, not
`CanonicalPaginationCursor.logicalEnd`. No v1 cursor is made to resolve a
source outside its snapshot. A zero-card empty section has an explicit
empty-section receipt and preserves the prior accepted card guard.

`LazySnapshotHandoffV1` contains these stable fields:

| Group | Exact fields |
| --- | --- |
| Contract/publication | `kind`, `bookId`, `publicationFingerprint`, `spineAuthorityDigest`, `parserSourceIdentity`, `dependencyIdentity` |
| Lineage | `lineageRootDigest`, `parentSessionDigest`, `successorSessionDigest`, `previousHandoffDigest` (nullable root), `handoffOrdinal` |
| Snapshot binding | `oldSnapshotDigest`, `oldSourceRevision`, `newSnapshotDigest`, `newSourceRevision`, `prefixSourceCount`, `prefixOwnersAndRecordsDigest`, `addedSectionIdentity`, `addedSectionRecordsDigest` |
| Predecessor | `sectionEndReceiptDigest`, `acceptedPublicationDigest`, `acceptedCardCount`, `committedCardSignature`, `lastAcceptedCardSignature`, `lastAcceptedCardBytesDigest`, `lastAcceptedSlicesDigest`, `oldSectionEndPosition` |
| Successor | `nextExpectedSourceOwner`, `nextExpectedCursor` (whole-source/offset zero), `trustedSectionStartProofDigest`, `emptySectionChainDigest` (nullable), `firstNewCardSignature`, `firstNewCardStartCursor` |
| Compatibility | `packingIdentity`, `layoutMetricsFingerprint` (F196), `rendererLayoutFingerprint` (F206), `paginationAlgorithmFingerprint` (F204), `paginationAlgorithmIdentity`, `compatibilityClassifierRevision` (F207), `fontDeliveryDigest`, `oldSourceCompatibilityFingerprint`, `newSourceCompatibilityFingerprint`, `sourceExtensionProofDigest` |
| Integrity | `handoffDigest` over all prior fields |

`successorSessionDigest = H(kind, lineageRootDigest, parentSessionDigest,
previousHandoffDigest, handoffOrdinal, newSnapshotDigest, packingIdentity,
sectionEndReceiptDigest, nextExpectedSourceOwner)`. It excludes handoffDigest
to avoid a circular definition. A prepared record becomes authoritative only
after the publication transaction succeeds. The runtime envelope binds book
open epoch, display/layout owner, cancellation token, expected publication
revision, and retry attempt. Stable digest equality cannot revive an old epoch.

Prefix proof compares every source in A with the corresponding first N
records in A+B: exact source/section/spine identity, source digest, canonical
record bytes (including rich/structural metadata), and validated ordinal.
No reorder, replacement, skipped unproven section, duplicate owner, partial
section, parser/dependency change or source mutation is admissible. A count,
last-card hash, equal text or sampled comparison is insufficient. Incremental
comparison is cooperatively scheduled within the source/byte bounds; the new
snapshot/record is private until the entire comparison succeeds.

The expected B owner becomes known only after its parsed section identity and
checksum validate against spine authority. Its cursor must match the first
unconsumed stable owner, not a display/window index. Prefix and added-section
proofs include heading/generated/list/table ownership and empty-section gaps.

## 5. Packing identity, immutable cards, and atomic publication

For the new lazy protocol, define `LazyPackingIdentityV1` as the digest of
`(domain, publicationFingerprint, spineAuthorityDigest, parserSourceIdentity,
dependencyIdentity, structuralOwnershipRevision, F196, F206, F204, F207,
fontDeliveryDigest)`. It deliberately does not include loaded-window count,
source revision/digest or representative-source probe identity. Those remain
mandatory *separate* snapshot and per-source font/image/structure proofs.

This identity is established before the first card in a new lazy lineage and
is constant across its handoffs. It does not rewrite the P05 F202/F208 codec or
claim old/new F202 equality. The handoff validates exact retained-source
evidence and new B evidence, plus exact F196/F206/F204/renderer/font delivery.
Ordinary full-snapshot paths retain their existing controlled identity. A
genuine metric, renderer, parser or pagination change is not a handoff.

Already published cards retain the identical object payload encoding, ordered
slices, resolved block layouts and signature. Do not re-sign them, change
their index fields, or rewrite source ordinal hints. New cards use the same
lazy packing identity and production canonical identity builder. Build only
external lookup/projection maps; those resolve stable owners first and treat
an ordinal as a checked hint. Compare all retained card bytes and signatures,
not just the visible card, immediately before commit.

Add a distinct `publishSnapshotHandoff` transaction (name is a specification,
not an implemented method):

1. Require current epoch/owner, unlatch state, exact accepted publication
   revision and unconsumed receipt. Validate old authority and all prefix,
   section adjacency, compatibility and boundedness proofs.
2. Create successor session over immutable A+B. Start at the trusted B root;
   the successor's ordinary continuation chain has a root ordinal of zero.
   H is its external predecessor authority. Never put the old terminal/receipt
   digest into a v1 continuation's `parentDigest`.
3. Run bounded production pagination only for B. Validate its first card
   starts at the expected owner/cursor, and the last A slice ends exactly at
   the proved hard section boundary. This explicit two-section relation is
   not equality between logical-end and a non-end cursor.
4. Validate every retained A card against the prefix proof, every B card
   against A+B, committed-card preservation, complete source coverage,
   continuation/receipt authority for B, and all normal structural rules.
5. Build maps privately. Compare-and-swap publication, adopted successor
   session, accepted receipt/continuation and lineage together. Mark H used.
   Nothing observable changes on rejection or cancellation. Cancellation
   predicates bind the session's pinned snapshot and operation owner, never
   infer freshness from a shared mutable `_sourceChunks` list. Adopt the new
   source/projection window only in this commit, not before pagination.

Normal `publishCanonical` append continues to reject differing session/digest
and broken parents. Replacement is never a handoff. A root without H cannot
append to a nonempty publication. If B yields only provisional work, retain
one bounded private attempt and the old publication; resume that attempt,
not another generation. If B is final, its genuine terminal result can be
adopted in the same transaction with independent book-end evidence.

## 6. Single ownership, failure, cancellation and retry

One reader owner serializes forward/backward integration and retention changes.
Join key: `(bookOpenEpoch, lineage/session digest, accepted suffix/receipt
digest, expected target section, packingIdentity)`. Repeated demand joins the
same future. Warmup uses that key; a joining foreground request promotes its
priority without creating another parser/paginator/handoff. Opposite direction
work queues behind the authority transaction and revalidates afterwards.

Preparation returns a typed success/pending/cancelled/stale/failed result.
Reporting an exception is not settlement success. Any deterministic parse,
pagination, compatibility or publication failure must atomically:

- latch the owning book-open/layout lineage (not just a source-count signature);
- settle every matching waiter with failure; stop forward/backward warmup,
  range scheduling, hydration and derived-index/cache-write continuations;
- release matching queued repository work and invalidate in-flight commit
  authority; settle its future even if physical isolate work cannot stop yet;
- keep the current readable card and publication byte-identical, show the
  existing retry affordance for demand or later demand joining failed warmup;
- forbid automatic rebuild through eviction, changed source signatures,
  `setState`, preparation flags or completion callbacks.

An explicit retry alone creates a new attempt under that owner; it rechecks
file/index/layout identity and rebuilds only uncommitted B/proofs. It does not
resume a terminal chain or regenerate A. A legitimate book switch/close
invalidates the epoch, settles all old work, and cancels queued background jobs;
late callbacks must not clear a new book's task/latch or resume hydration.
Failure remains actionable even when no new card was produced. Cancellation
of stale work never authorizes a retry by itself.

## 7. Bounds, retention, repeated handoffs and backward navigation

Keep the existing 48-source/eight-card checkpoint cadence, two-card frontier
and derived entry cap; normal/recovery pagination work envelopes remain
110/158 entries (layout-dependent formulas in P04), 96 resident published
cards and 25 resident continuation/receipt/lineage guards in aggregate.
No per-session allowance may multiply these limits. Keep the existing parsed
repository's three-section/6 MiB retention policy, and the canonical 432-source
resident ceiling. A privately expanded snapshot shares immutable backing
records with A; it must not double retained text/decoded graphs. H stores
digests/owners/cursors only, no copied text or full card arrays. At most one
handoff is preparing/committing. Receipt + H encoded metadata is capped at
64 KiB; oversized evidence returns typed bound failure, not truncation.

Admit at most one new section per attempt. Snapshot comparison checks one
source/encoded-record slice per cancellation quantum; retain the established
grapheme/table/rebalance checkpoints. Bound hashing/encoding too: byte batches
no larger than 64 KiB between scheduler checkpoints. Source/payload over-budget
cases must have explicit pending/bound outcomes and tests; a large section
cannot justify disabling demand navigation or silent whole-book loading.

A+B is the logical immutable expansion for this transaction, not permission
to retain the entire reading history. Once old published cards leave the
96-card window and their sections are not committed/frontier/seam dependencies,
perform a separate `retainSnapshotSuffix` transaction. It proves the retained
snapshot is an exact owner/record suffix, preserves every remaining card byte,
and transfers compatible *live frontier descriptors* after owner reconstruction
into a new session-root envelope. It never edits/relabels an old continuation
or resumes a terminal one. Stable-owner resolver/projection changes are
required: current dense ordinals cannot be used as identity. Retention keeps
references to the original encoded source records; an explicit stable-owner
to resident-slot table replaces dense-index assumptions. It must not reindex
or reserialize retained source/card payloads. Ordinary full-snapshot decoding
remains strict; the lazy resolver needs an explicit, separately validated
address-space contract and its own red tests before this transfer can ship.
Do not mix source
eviction with forward integration or silently fall back to replacement.

Only active seam guards and adjacent session/root evidence remain pinned.
`previousHandoffDigest` is a compact link, not a retained object chain. Each
guard is self-contained for its local source/adjacency proof; old bodies may
be discarded. If preserving committed/frontier data exceeds a bound, settle
with explicit preparation failure; do not evict needed authority or loop.

Backward navigation uses the existing bounded forward-regeneration algorithm
within the section owning the desired predecessor. Old snapshot checkpoints
are usable only with their exact snapshot; never transplant them to the new
index. Across a handoff, reconstruct the bounded predecessor section and hard
seam from spine/source evidence, regenerate through the committed card under
the same lazy packing identity, and compare full card/slice/layout bytes and
signature plus successor cursor. A dedicated proved prepend transfer imports
only predecessors. Multiple historical handoffs require no traversal of an
unbounded receipt chain: section roots plus pinned index/source evidence are
the restart authority. One earlier-checkpoint fallback is allowed. A missing
seam or out-of-bound restart returns pending/required evidence, never a guessed
card or whole-book scan. This retention/backward transfer needs its own red
tests before implementation; forward-only success cannot close P04.

## 8. Persistence, cache compatibility and exact restoration

No persistent schema/version constant changes in this task or the first
handoff implementation. Retain `canonical_display_v4`, the v1 continuation
codec and checkpoint/stable-location schemas. Do not serialize receipts/H as
v1 continuations or invent a terminal record for input exhaustion.

The new lazy packing identity intentionally differs from old window-dependent
identity. New lazy records and old records are not interchangeable even if
visible text matches. The existing format can still encode ordinary compatible
segments contained in one snapshot with legal v1 predecessor/terminal proof.
Handoff-spanning and suspended-boundary records have **no write authority**
until a separately authorized P06 persistence contract exists. This narrows
unsupported evidence, not all display caching or lazy loading.

For both memory and disk admission add an independent contextual end-proof
gate: an existing terminal record for a partial window is a typed
`unverifiedLogicalEnd` safe miss, even if codec, checksum and snapshot match.
Do not clear its terminal flag, convert it, publish it as a prefix, or delete
source/user data. Genuine last-section records still require exact compatible
identities and full source/section completeness. Mid-book local ordinal zero
is not publication start; builder/admission must check spine authority too.
Any invalidation is scoped to display derivatives; no migration of checkpoints,
annotations, bookmarks, parsed-section caches or source EPUBs is authorized.

New-protocol reopen reconstructs the deterministic lazy packing identity from
publication/index/layout evidence, loads bounded owning-section data and
regenerates from a trusted section root/checkpoint to find the exact stored
signature. Match signature, source slices and resolved layout before settlement.
No persistent lineage journal is required; section-root packing cannot depend
on which preceding windows happened to be loaded. Hash links are for current
session CAS/replay protection, not a prerequisite for reconstructing a book.

Old checkpoints contain window-dependent signatures. They cannot be silently
re-signed, treated as a same-layout semantic migration, or reset. Compatible
old evidence may be inspected for exact restoration only; if it cannot be
proved, retain the checkpoint and return the existing explicit exact-unavailable
failure. **Legacy checkpoint recovery is an implementation-entry blocker**:
tests must establish whether bounded exact reconstruction with retained old
evidence is possible and how the existing retry UI presents failure. Any new
reset/migration UX requires separate authorization (existing DEC-REQ-001/002);
this design does not authorize it. No numeric pagination-version bump is
chosen: unchanged packing rules plus the new lazy identity domain already
separate signatures; a discovered packing-rule change requires a fresh review.

## 9. Characterization and exact missing seams

New file: `test/reader_contract/regression/lazy_snapshot_handoff_characterization_test.dart`.
It uses real lazy index/repository/parser, pinned snapshots, the production
canonical session/paginator/codec and existing controlled layout harness.
It is outside the frozen P02–P06 files and deliberately red. No fake paginator,
fixture/oracle changes, timing sleeps or production seam additions.

| Requested case | Coverage and limitation |
| --- | --- |
| 1. Known successor becomes terminal | H01 asserts real index/window successor, exhausts a production session, then expects not `terminalBookEnd`. Red at the semantic assertion. Availability has no argument in the current canonical API; this absence is the defect characterized. |
| 2. Append successor then forward | H02 loads B with production lazy session, verifies expanded window and immutable A, calls current canonical forward; expects accepted output and prints the actual typed terminal rejection. It does not invoke private screen integration. |
| 3. Warmup/foreground same failure | H03 submits speculative/boundary priorities simultaneously to the same real accepted suffix. It proves the common paginator failure for both priorities, not ReaderScreen join/priority promotion or callback ordering. Full screen scheduling remains blocked on the seam below. |
| 4. Caught failure looks successful | H04 proves the production boundary failure-presentation predicate excludes demand. Catch/upstream completion is source/device evidence only; H04 is explicitly not a settlement test. |
| 5. Hydration after failure | No fabricated red test: repository hydration has no display-failure parameter, and screen catch/scheduler state is private. The source path and recorded failure/completion trace are evidence, not an executable red for this case. |
| 6. Genuine final section | H06 uses the real last linear section, confirms no successor and validates terminal reason/end/empty frontier through the codec. Green control. |

Minimum seam for full cases 3–5: add an optional test access handle to an
otherwise normally mounted `ReaderScreen`, using its existing lazy session,
initial chunks/settings/location constructor inputs. The handle must delegate
to the actual `_ensureAdjacentSectionAvailable`,
`_scheduleLazyAdjacentWarmup` and hydration scheduling methods; expose
read-only current publication digest, owner/generation, task completion result
and failure state. Supply deterministic completion hooks only at the existing
16 ms warmup and hydration-quiet scheduling boundaries. Use the repository's
existing injected coordinator/parser hooks to hold/release parse work.
No alternate catch, simulated success future, replacement pagination or new
independent lifecycle coordinator is valid evidence. Install/uninstall the
handle with the real state; stale handles cannot act on a replacement book.

Implementation tests must hold queued hydration, trigger the real terminal
rejection, observe the returned adjacent task and error handler, release the
queue and assert zero later parse starts/rebuilds. They must also join demand
to warmup, repeat the same target, and close/switch before release. This is a
narrow adjacent-work seam, not authorization to begin the P07 checkpoint DB /
A→B→A restoration harness. No seam is introduced in this design task.

Commands, exact final results and test-setup corrections are recorded in
CHANGE-040. Red cases are not skipped/quarantined and must not be counted as
a passing regression gate.

## 10. Implementation gates and exact next task

Next task: `IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001 — Prove lazy handoff
authority and failure settlement before wiring snapshot transfer`.

The architecture is selected; these implementation-entry proofs remain open:

1. Add the narrow screen seam and make cases 3–5 truly red through that path.
2. Prove the lazy packing identity/per-source compatibility split against
   actual P05 resolved layouts, source/font/image evidence, reload and legacy
   exact-checkpoint behavior. No source/layout validator bypass.
3. Prove bounded retention/frontier transfer and backward exact-card
   regeneration after at least two handoffs, including empty and oversized
   sections. No whole-book resident snapshot or per-session bound multiplication.

Expected later production files: `lib/models/canonical_pagination.dart`,
`canonical_pagination_checkpoint_index.dart`; `lib/services/reader_card_paginator.dart`,
`progressive_display_state.dart`, `lazy_book_session.dart`,
`lazy_epub_index_service.dart`, `lazy_section_repository.dart`,
`reader_layout_contract_service.dart`, `display_generation_coordinator.dart`;
`lib/screens/reader_screen.dart`; `lib/models/canonical_display_segment.dart`
and `lib/services/canonical_display_segment_admission.dart` (contextual proof
gates only). A focused in-memory handoff model may be added. Persistent
checkpoint/schema changes and a general reader rewrite are not in scope.

Bounded next-task prompt:

> Implement only IMPLEMENT-P04-LAZY-SNAPSHOT-HANDOFF-001 from CHANGE-040.
> Preserve recovery commit, branch, protected evidence and frozen oracles.
> First add the specified narrow real-screen adjacent-work seam and deterministic
> failing tests for join/caught failure/queued hydration/repeated target/close
> and switch. Prove the selected packing identity, legacy exact-checkpoint
> outcome, retention transfer and backward seams in focused tests before
> wiring production snapshot handoff. Do not turn H01–H03 green by passing a
> false no-successor claim or rebuilding publication. Do not persist the new
> record, change schemas, alter frozen expectations, start P07 or run devices.
> Stop with exact evidence if the three entry proofs need a new compatibility,
> restoration UX or bounded-source architecture decision. Only after those
> proofs may a separately reviewable implementation wire receipt -> immutable
> successor session -> atomic handoff append and failure latch. No commits or
> pushes. P04/P06 remain open until host controls and owner A059 evidence pass.

Design completion is not correction implementation, device verification or
permission to weaken these gates.

## 11. Accepted navigation and performance amendment (2026-09-21)

These are owner-approved acceptance requirements, not achieved claims. They
amend the forward-looking design; prior failure evidence remains unchanged.

**Adjacent reading** consumes a verified section-boundary receipt and immutable
snapshot handoff. **Direct target preparation** serves chapter-list, bookmark,
search-result, annotation and other stable-location jumps. Chapter 1 → chapter 6
resolves chapter 6 from pinned spine/stable-location authority and parses,
paginates and hands off through **zero** intermediate chapters. A chain of
adjacent handoffs is never a random-access implementation.

Direct target preparation must join identical requests, give the latest
foreground demand publication ownership, preempt/cancel lower-priority warmup
within one scheduler quantum, and keep the current readable card until the
first target card is accepted. Only the target owning section and bounded
necessary evidence may load. First readable target publication precedes
hydration, derived indexing, speculative adjacent work and any awaited physical
cache write. Stale/superseded work cannot publish. A direct target may eventually
replace the visible range under explicit navigation authority; that replacement
must never be used to disguise an adjacent handoff or error recovery.

| Acceptance requirement | Target / evidence method |
| --- | --- |
| Already prepared card navigation | ≤100 ms on A059 |
| Prefetched chapter boundary | ≤250 ms on A059 |
| Cached/parsed direct chapter target | ≤250 ms on A059 |
| Uncached ordinary direct chapter target | First readable card ideally ≤500 ms; hard target ≤1 second |
| Intermediate chapters parsed for 1 → 6 | Zero, deterministic parser counters |
| Awaited hydration/index/cache-write work before first target card | Zero, deterministic completion gates/order trace |
| Foreground preemption | Within one scheduler quantum |
| UI-isolate work | Cooperative ≤8 ms deterministic injected-clock slices |
| ANR / Stop-Wait | Zero; debug must also avoid ANR/unbounded loops |

Host tests use deterministic ordering/counters/injected scheduling, not wall
clock timings. Final latency acceptance requires ordinary profile/release A059
owner evidence. No device execution or latency achievement is asserted here.

The chapter-card scrubber is separately deferred in the reliability plan as
`DEFERRED-UX-CHAPTER-CARD-SCRUBBER-001`, UNSTARTED. It has no authority to expand
this task into reader widget changes.

## 12. Stable lazy source address proposal and explicit representation gate

The smallest source address is a tuple, not a resident ordinal:

`(publicationSpineAuthorityDigest, exactSectionIdentityDigest, localSourcePosition)`.

The pinned publication/spine digest covers book/publication identity, index
schema, parser/dependency revisions and ordered immutable spine tuples. Exact
section ownership includes full checksum, parser/dependency evidence, stable
spine item identity, normalized href/full path and linear/nonlinear scope.
`localSourcePosition` is the parsed source position within that exact complete
section, not the ordinal of a loaded window. Equal positions in different
sections cannot alias. Preceding sections need not be parsed to derive it.

An address names a source. Separate membership evidence binds source canonical
bytes/digest and complete ordered section records/count. Reject insertion,
removal, reordering, mutation, parser/dependency changes or a prefix that does
not exactly preserve those records. Do not accept an address solely because its
integer or text matches. Complete evidence that exceeds the source/byte bounds
returns needs-evidence/bound failure, not an incomplete digest or truncation.

A fragment carries the address plus a tagged interval: text UTF-16 start/end,
table row interval and stable cell ownership where applicable, or atomic source
extent for images/milestones. Structural/logical owner role, heading/list IDs,
list marker/fragment metadata, publisher/rich-layout evidence and exact image
bytes/metrics remain required. Source offsets are checked against the original
section record; text/table/atomic coordinate systems are never interchanged.
Empty sections use complete empty-section certificates, never invented sources.

Runtime maps resolve `(address → resident slot)` and reverse mappings. A dense
index is an optional checked hint only; it cannot affect stable card identity,
persistence, restoration, bookmarks, annotations, projection authority or
handoff. Ordering uses pinned spine order then local source/fragment order,
not current list position. Address equality is independent of packing; the
accepted dual-authority model separately checks all P05 metric, renderer,
pagination/classifier, font, image and structural evidence. A matching address
never authorizes an incompatible rendered card.

**Representation gate:** Existing `BookChunk.toJson()['i']` and canonical slice
`sourceOrdinalHint` are still encoded in current card/continuation/cache payloads.
Their bytes are not to be normalized, deleted, reindexed or re-signed on accepted
cards. The new lazy emission contract needs a distinct in-memory stable body
with resident projections outside that body, from first emission onward. The
ordinary full-snapshot P05 path and its F202/F208 remain unchanged. This paragraph
specifies the separation, not a selected durable encoding, a schema migration,
or permission to rewrite an old body. Before production adoption, prove stable
body/signature/slice/layout bytes for A+B, direct B, eviction, backward and fresh
reopen with production pagination and strict admission. The current R02 red
must remain until that actual contract exists.

## 13. Persistence and legacy recovery gate

No durable encoding is selected by §12. Existing schema fields accepting strings
or integers does not prove that a new address interpretation is backward
compatible. A schema-free claim requires actual encode → close/reopen → bounded
regenerate → exact signature/body/slices/layout validation, including old records
and malformed/ambiguous inputs. The current test-only tuple is not that codec.

Legacy recovery can succeed for a known exact original window: L01 persists a
real old F202/F208 checkpoint, reopens SQLite and regenerates exact original
cards in the small fixture. This is conditional evidence, not a deterministic
way to discover an arbitrary missing historical window. L02 records that a
window-only composite change currently permits semantic restoration under
`layout_changed`; this is not authorized recovery for the new protocol. Preserve
user records; do not silently choose that result, reset, re-sign or delete them.

If exact original evidence is unavailable within aggregate bounds, stop for
DEC-REQ-001/002 and evaluate these explicit alternatives:

1. **Versioned lazy checkpoint/address migration:** separately authorize the
   encoding, version discrimination, exact conversion criteria and rollback;
   preserve old records. Never manufacture new exact authority from text alone.
2. **Typed exact-unavailable:** preserve checkpoint and user data, retain any
   already readable publication, and expose explicit retry/recovery. The owner
   must choose the missing/cold-reader UX; existing nullable restore results do
   not themselves constitute a typed UI outcome.
3. **Bounded authoritative reconstruction:** enumerate only candidates whose
   original window and compatibility evidence are actually available; require
   the original signature and full bytes. Enforce 432 sources/96 cards/25 guards
   and 110/158 work envelopes globally, including simultaneous private attempts.
   Failure/exhaustion preserves the checkpoint. L01's known 18-source fixture
   is not proof for every historical window or oversized section.
4. **Restoration UX:** decide blocking retry, explicit user-authorized reset or
   another nonapproximate outcome under DEC-REQ-001/002. No option is implicitly
   selected by this design amendment.

## 14. Mandatory direct-target and address entry gates

The adjacent-work test handle currently exposes no direct stable-target entry
and no awaitable first-target-card acceptance event. `prepareNavigation` service
counters can prove which sections parsed, but cannot prove the old visible
publication remained readable or when its successor was accepted. Required
future narrow seam: delegate to `_navigateToStableLocation`, expose read-only
navigation owner/publication identity and existing target acceptance/settlement
completion; hold actual parse/pagination work through existing hooks. Do not
introduce an alternate coordinator or a broad reader control API.

D01 service evidence: chapter 1 → 6 parses only `[0,5]` (zero-based).
D02: an explicit target remains queued behind a held chapter-7 boundary prefetch
until parser release. The service does not meet the preemption acceptance gate.
`LazySectionRepository._loadSectionUnshared` additionally awaits
`_cache.writeSection` before returning parsed work; first-card-before-awaited-
physical-write remains an explicit gate. Neither finding is device timing.

The real-screen direct-target test must prove old publication retention, zero
intermediate parsing, current/latest foreground ownership, identical-demand
join, lower-priority preemption and first-card ordering. No pre-handoff approval
is possible from service counters alone. Address/legacy/retention and H01–H06
truth remain independent gates. See the [current entry-proof report](nalori-lazy-snapshot-handoff-entry-proof.md)
and [address inventory](nalori-lazy-source-address-inventory.md) for commands,
counts and exact unresolved coverage. The report's current bounded prompt
supersedes the earlier next-task prompt while these entry blockers remain.

## 15. Partial successor pagination amendment (2026-09-27)

The forward core may accept a finalized prefix of B without exhausting B.
Complete immutable **source capture** of B is still required; partial source
loading, oversized subdivision and frontier transfer during retirement are
not authorized by this amendment. Stable-body/checkpoint formats and ordinary
append/P05 validation remain unchanged.

State transitions:

1. **sealed A → private B prefix**: validate the existing A receipt and exact
   A+B source extension. Start B once at its verified root, retaining the normal
   two-card frontier. Stop after a bounded finalized batch; provisional cards
   never enter publication. A remains accepted while preparation yields.
2. **private prefix → accepted unfinished B**: validate exact ordered coverage
   from B's root through the finalized boundary and the production nonterminal
   continuation/frontier. The dedicated handoff atomically adopts that prefix,
   keeps all A cards/renderer authority, and retains the unfinished B session.
   An unfinished B has no section-end receipt and is not book end, even when
   pinned spine metadata says B is the final section.
3. **accepted unfinished B → private extension → accepted longer B**: fork only
   the exact accepted session state (immutable snapshot, accepted cards, exact
   continuation and checkpoint parents). Resume production `generateForward`;
   never restart at B's root. The candidate proves identical accepted prefix,
   unchanged source/layout and exact parent suffix, then atomically appends new
   finalized cards. No handoff ordinal/source authority change occurs here.
4. **unfinished → complete**: only actual input exhaustion with a successor
   permits B's receipt; only actual terminal pagination plus pinned final-book
   evidence permits book-end status. Complete coverage is required for either.
5. **cancelled/stale private work → prior accepted state**: discard the private
   fork and settle accounting; accepted B cards and its exact continuation stay
   usable by a later explicit request. No automatic rebuild or source recapture.

One core operation owns pending work at a time. Forked checkpoint parents,
frontier, source scratch, private finalized cards and renderer leases count
against the existing aggregate limits. Budget refusal preserves accepted state.
Retirement and backward reconstruction continue to require complete sections;
unfinished frontier retention transfer and backward first-card preparation are
separate requirements. Preparation/validation uses the yielding route and its
same owner/publication/visible-position checks before atomic commit.
