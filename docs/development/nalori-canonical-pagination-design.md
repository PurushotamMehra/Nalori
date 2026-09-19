# Nalori canonical pagination design

Design task: `TASK-P04-001`  
Date: 2026-08-31  
Status: implementation-ready specification; no production or test implementation is included  
Requirements: `REQ-007`–`REQ-013`, `REQ-027`–`REQ-028`, `REQ-040`, `REQ-044`–`REQ-045`, `REQ-048`, `REQ-051`

## 1. Authority and goals

This document is the canonical construction contract for P04. Its authority order is:

> approved reader requirements → P03 relational evidence → stable parser/source evidence → implementation

Current physical-card membership is evidence of the defect, not an oracle. The design changes only card construction, continuation, restart, and publication seams. It does not repair the parser, source oracle, structural pipeline, measurement/render agreement, restoration UX, or persistent cache format.

For one compatible publication, parser/source snapshot, pagination algorithm, and controlled layout identity, there is exactly one forward canonical card sequence. Target-first, forward-first, forward regeneration used for prepend, singleton expansion, cache replay, eviction, and reload may expose different bounded portions of that sequence, but may not create different card membership.

The core invariants are:

1. Source order and complete readable half-open coverage are preserved without loss, gaps, duplication, overlap, reordering, or out-of-range content.
2. Stable source and structural evidence owns every byte. Display, controller, and current-window indexes are projections only.
3. A request end is not a logical source end and cannot finalize a provisional tail.
4. A card becomes publishable only after adjacent merge, tiny-tail backward attachment, sentence rebalance, heading, and structural rules can no longer change its membership.
5. An accepted or published card is immutable. Later work either extends the sequence at a proved seam or is rejected without mutation.
6. Pagination is forward-only. Backward preparation regenerates forward from an earlier checkpoint and proves the existing seam.
7. Work, retained frontier state, checkpoint density, and published-window state have explicit bounds. Whole-book pagination is forbidden.

## 2. Proven P03 evidence

P03 established 23 deterministic failures: 12 target-first, two forward/prepend, four singleton-expansion, and five cache-replay cases. It also established all of the following, which P04 must preserve:

- no source loss, gaps, duplicates, overlaps, reordering, or out-of-range content;
- structural ownership passed in all six full/target/forward/prepend/singleton structural constructions;
- source 7 retained the same four physical split ranges under split stress: `[0,58)`, `[58,125)`, `[125,191)`, `[191,198)`;
- list, table, inline style, link, footnote, repeated-text, and cross-spine source evidence survived construction;
- memory and segmented caches faithfully replayed the independently flushed source-4 island; they did not introduce a second corruption mechanism.

The failure mechanism is narrower: `ReaderCardPaginator.paginate` creates a fresh packing frontier for every `DisplayRangeRequest`, and its final `flush` treats request exhaustion as if the logical input ended. `ProgressiveDisplayState.append` and `prepend` then concatenate independently finalized islands. The repair is predecessor context, retained frontier state, canonical continuation, deterministic forward regeneration, and seam rejection—not parser or structural-pipeline repair.

## 3. Current-kernel state inventory

### 3.1 Inputs and request-local fields

The current kernel is `ReaderCardPaginator.paginate` in `lib/services/reader_card_paginator.dart`. Its current input and mutable state are:

| Current symbol/field | Current role | Canonical disposition |
| --- | --- | --- |
| `ReaderCardPaginatorRequest.range` | `DisplayRangeRequest` with direction, `SourceChunkRange`, generation ID, reason, and optional target original index | Direction/reason/generation remain operation metadata. A raw range start is not restart authority. |
| `sourceChunks` | Unmodifiable live list view | Replace at the contract boundary with a revision-pinned immutable source snapshot/resolver. |
| `layout` | Width, page/physical height budgets, tiny thresholds, settings, styles, struts, scaler | Required controlled immutable input; P05 later completes its fingerprint authority. |
| `scheduler`, `priority`, `isCancelled` | Cooperative work and cancellation | Operation control only; never continuation identity. |
| `diagnosticBookId`, `parentGeneration`, `currentGenerationForDiagnostics`, `onDiagnostic` | Diagnostics/stale evidence | Operation metadata only. |
| `finalizeAnchor` (`sourceIndex`, `textOffset`) | Early-stop hint | Replace with a stable target cursor; neither field alone is restart authority. |
| `newDisplayChunks` | Request-local cards, including cards that `flush` may still replace | Split into finalized output and an unpublished frontier. |
| `newDisplayToOriginal` | Request-local display projection | Rebuild from finalized cards; never continuation state. |
| `newOriginalToDisplay` | Request-local display projection | Rebuild from finalized cards; never continuation state. |
| `textHeightCache` | Request-local measurement memo keyed by chunk/text/dialogue/width | Recomputable optimization; never authority or continuation state. |
| `pending` | Current merged/split `BookChunk` | Canonical frontier state, represented as stable source slices plus structural evidence. |
| `pendingOriginals` | Source indexes projected into `pending` | Replace with ordered stable source-slice owners; indexes may be validated hints only. |
| `inspectedSourceChunks`, `consumedEndExclusive` | Diagnostics and shortened result range | Operation counters only; canonical source cursor replaces range authority. |

`ProgressiveDisplayState` also owns `ranges`, `displayChunks`, `displayToOriginal`, and `originalToDisplay`. Those maps are transient display projection. Its current append/prepend checks source-range adjacency, but it has no predecessor/successor continuation, card-identity seam, or immutable-prefix/suffix proof.

### 3.2 Fields used by split, merge, flush, and rebalance

The current decisions use these `BookChunk` fields and derived values:

- source/structure: `index`, `type`, `section`, `sourceFile`, `sourceRanges`, `blockRole`, `isHeading`, `isDialogue`;
- publisher layout: `publisherTextAlign`, `publisherFirstLineIndent`, `publisherLeftIndent`, `publisherRightIndent`, `preserveLineBreaks`, `preserveWhitespace`, and `usesPublisherLayout`;
- text structure: `text`, `logicalParagraphId`, `logicalParagraphStartOffset`, `logicalParagraphEndOffset`, `isLogicalParagraphStart`, `isLogicalParagraphEnd`, and `textBoundaries`;
- rich content: `links`, `inlineStyles`, and `footnotes` with offsets shifted during split/merge;
- lists: `listSemantics`, `listDisplaySegments`, their stable list/item/block IDs, depth/order/ordinal/marker metadata, source offsets, and fragment states;
- measurements/classification: `heightBudgetFor`, `chunkHeight`, `isTinyChunk`, `readerLayoutWordCount`, `minUsefulHeight`, `tinyWordCount`, `tinyHeightRatio`, presentation match, hard merge key, and measured merged height;
- tables: parsed row/column structure and the selected row interval when a table is split.

`readerChunksShareHardMergeBoundary` requires compatible text/list structure, section, source file, heading status, block role, publisher alignment/indents, and whitespace policies. `shouldMergeChunks` additionally requires the measured merge to fit and applies dialogue/tiny soft-body rules. `tryRebalancePendingWithTinyNext` examines all sentence-end offsets in the pending text, from latest to earliest, and chooses the first non-tiny head whose tail plus the tiny next chunk fits. It excludes publisher-layout and list fragments. `flush` can merge a tiny `pending` backward into `newDisplayChunks.last`; therefore the last request-local card is not necessarily final before the tail is resolved.

### 3.3 Source consumption and split representation

A source chunk is fully consumed only after its deterministic table/text split has produced all atomic layout units and each unit has advanced the packing frontier. The canonical cursor therefore cannot be only `sourceIndex + 1`. It must identify either the next source or the exact within-source boundary of the next unconsumed fragment.

Text splitting uses sentence boundaries, then clause boundaries, then word boundaries, then grapheme-safe fallback for an oversized token. `buildSplitChunk` retains and clips `sourceRanges`, links, inline styles, footnotes, logical paragraph offsets/start/end flags, list display segments/fragment states, and text boundaries. A table split is owned by the original table source plus a stable row interval. P04 must preserve the same ownership metadata on every generated table fragment; visible table text alone is insufficient.

The immediate next nonempty atomic unit is the only direct lookahead input to merge and rebalance. Tiny-tail backward attachment creates one additional dependency: a previously formed predecessor cannot publish while the following provisional tail remains eligible to attach backward. Consequently the canonical unpublished frontier contains at most two physical-card candidates:

- `deferredPredecessor`: a formed card that may still absorb a tiny tail;
- `pendingTail`: the current accumulating card.

No earlier card can change. Once the pending tail becomes non-tiny, hits an incompatible hard boundary, overflows the predecessor, or reaches a logical end and its attach/no-attach result is decided, the deferred predecessor is final.

### 3.4 Current publication, caches, and cancellation

`ReaderScreen._rebuildDisplayChunks` adapts its current source list, layout fields, generation, scheduler, cancellation closure, and optional anchor into the paginator. `_prepareProgressiveDisplayRange` may load memory/disk data or generate a range, then calls `publishInitial`, `append`, or `prepend`; `_applyProgressiveDisplayState` checks that the committed stable card can still be resolved, but it does not prove exact card seams or unchanged prefixes/suffixes.

`DisplaySectionMemoryCache` keys an entry by cache key and `SourceChunkRange` and stores cards/maps. `SegmentedDisplayCacheService` compatibility currently uses manifest/payload combinations of format version, book/cache key, parsed/parser/layout/settings/viewport identities, source count, and requested range. Neither cache stores canonical frontier or seam-chain evidence. Its replay is therefore evidence only until P06.

The exact cache/display compatibility inventory is:

| File/symbol | Current fields used | Canonical assessment |
| --- | --- | --- |
| `lib/services/display_generation_coordinator.dart` — `DisplayGenerationSignature` | `bookId`, `parsedContentVersion`, `layoutSignature`, `settingsSignature`, `viewportSignature`, `cacheKey` | Useful compatibility tuple; not a packing restart or seam proof. |
| `lib/services/display_section_memory_cache.dart` — `DisplaySectionMemoryCacheKey` | `cacheKey`, `sourceRange` | Range-local lookup only; no publication/parser/continuation chain. |
| `DisplaySectionMemoryCacheEntry` | `key`, `displayChunks`, `displayToOriginal`, `originalToDisplay`, `estimatedBytes` | Stores an independently generated island and transient maps; `toResult` recreates a range result without continuation. |
| `lib/services/segmented_display_cache_service.dart` — `SegmentedDisplayCacheKey` | `bookId`, `cacheKey`, `signature`, `sourceChunkCount`, `displayCacheVersion`, `parserVersion` | Stronger request compatibility, but still no canonical predecessor/successor state. |
| `DisplaySegmentRecord` | `sourceStart`, `sourceEndExclusive`, `actualSourceStart`, `actualSourceEndExclusive`, `fileName`, display/map counts, `checksum`, `generationId`, timestamps, `status`, `fileSizeBytes` | Record/checksum evidence; requested/actual range fields are not finalized-card seam evidence. |
| `SegmentedDisplayCacheManifest` | `version`, `bookId`, `cacheKey`, `parsedContentVersion`, `parserVersion`, `displayLayoutVersion`, `settingsSignature`, `viewportSignature`, `sourceChunkCount`, `complete`, timestamps, `segments` | Current manifest compatibility identity; it validates the stored range family, not canonical membership. |
| `CachedDisplaySegment` | `record`, `displayChunks`, `displayToOriginal`, `originalToDisplay` | `toResult` replays stored cards/maps exactly and supplies no continuation. |
| `_SerializedDisplaySegment` | `version`, `bookId`, `cacheKey`, `parsedContentVersion`, `displayLayoutVersion`, `settingsSignature`, `viewportSignature`, `sourceStart`, `sourceEnd`, cards/maps | Payload compatibility omits parser version, source count, and canonical seam/frontier evidence; P06 owns any persistent correction. |

Cancellation is already checked before sources/subchunks, within table/text split loops, within rebalance, at flush transitions, and through `FrameBudgetedRangeTask`. A cancelled result exposes no cards. The canonical design preserves that publication property: stale/cancelled work may build private local state, but publishes neither cards nor continuation authority.

## 4. Canonical state machine

Named states:

- `RESTART_VALIDATED`
- `SOURCE_CONSUMPTION_ACTIVE`
- `PENDING_ACCUMULATING`
- `PENDING_PROVISIONAL`
- `CARD_FINALIZABLE`
- `CARD_EMITTED`
- `CONTINUATION_EMITTED`
- `TARGET_SATISFIED`
- `LOGICAL_END_REACHED`
- `BUDGET_EXHAUSTED_PROVISIONAL`
- `CANCELLED_STALE_REJECTED`
- `INVALID_RESTART_REJECTED`

`CARD_EMITTED` means canonical and immutable within the private result. It does not mean accepted by `ProgressiveDisplayState`; publication is a separate seam transaction.

| Current state | Event/input | Required evidence | State mutation | Card emission allowed? | Continuation emitted? | Failure/rejection |
| --- | --- | --- | --- | --- | --- | --- |
| start | Request plus restart | Compatible publication, parser/source snapshot, algorithm, layout, section, checksum, chain evidence | Validate and pin source snapshot; load zero-, one-, or two-card frontier | No | No | `INVALID_RESTART_REJECTED` on any mismatch |
| `RESTART_VALIDATED` | Begin work | Cursor is in range and stable owner resolves exactly | Enter source cursor; restore frontier descriptors by re-derivation | No | No | Reject missing/ambiguous source owner or offset |
| `SOURCE_CONSUMPTION_ACTIVE` | Next source available | Stable source identity and section order match snapshot | Deterministically split or advance an empty source | No | No | Reject source checksum/order/schema mismatch |
| `SOURCE_CONSUMPTION_ACTIVE` | Next atomic unit | Exact source slice and structural owner | Put unit in empty tail or evaluate against tail | No | No | Reject invalid fragment offsets/metadata |
| `PENDING_ACCUMULATING` | Adjacent unit fits direct merge | Hard boundary, presentation/tiny rule, and exact measured merged height all pass | Merge source slices and rich metadata; advance cursor | No | No | Measurement/source reconstruction failure rejects result |
| `PENDING_ACCUMULATING` | Direct merge fails; next is rebalance candidate | Immediate next is tiny; publisher/list exclusions pass; deterministic sentence offsets available | Choose latest valid split; form head and tail+next; retain any still-attachable head as frontier | Only a head proved unable to absorb its successor | No | Cancellation rejects all private output |
| `PENDING_ACCUMULATING` | Direct merge/rebalance fail | Next-unit hard-boundary and height/classification evidence | Move current tail to deferred predecessor; start next tail, or mark current finalizable if attachment is impossible | Only if attachment is already impossible | No | None; request range is irrelevant |
| `PENDING_PROVISIONAL` | Tail grows or classification changes | Recomputed tiny/merge/height evidence | Keep two-card frontier, attach backward, or release predecessor | Only released predecessor | No | Reject if frontier would exceed two cards |
| `PENDING_PROVISIONAL` | Immediate next proves no further membership change | Ordered next cursor, hard boundary/overflow, completed rebalance and backward-attach decision | Move proved card to `CARD_FINALIZABLE` | Not yet | No | None |
| `PENDING_PROVISIONAL` | Request budget exhausted | Valid cursor, intact frontier, work counters within bounds | Stop without flushing; retain frontier in continuation | Finalized prefix only; never frontier | Yes, provisional successor | None unless payload bounds fail |
| `CARD_FINALIZABLE` | Build identity | Final ordered source ranges and compatible publication/layout/pagination evidence | Create immutable card and `ReaderCardIdentity` | Yes | No | Reject fallback to visible text/display index |
| `CARD_EMITTED` | More source required | Emitted card end equals frontier predecessor boundary | Append to private finalized prefix; continue | Yes | At checkpoint cadence or result end | Reject internal gap/overlap/owner mismatch |
| `CARD_EMITTED` | Target range is in emitted card | Stable target cursor is contained by exactly one finalized source range | Record target card identity/range/offset evidence | Yes | Yes | Reject ambiguous or missing target containment |
| `CONTINUATION_EMITTED` | Caller requests more forward work | Continuation validates and chains to last emitted boundary | Resume at `RESTART_VALIDATED` | No until new proof | Successor replaces prior continuation | Incompatible/stale continuation rejected |
| any active state | Trusted section boundary | Stable spine/section index proves hard merge reset | Resolve/emit frontier under logical section-end rule; enter next section start | Yes after proof | Yes | Reject contradictory source section metadata |
| any active state | Trusted book end | Source snapshot count/end identity and frontier integrity | Resolve backward attachment, finalize terminal tail, mark logical end | Yes | Terminal continuation marker | Reject incomplete snapshot/end evidence |
| `CARD_EMITTED` | Target card finalized and bounded successor continuation exists | Exact target containment plus chain checksum | `TARGET_SATISFIED`; discard nonrequested finalized predecessors only now | Target/result cards only | Yes | Budget exhaustion returns non-success, never a provisional target |
| any active state | Cancellation, generation superseded, source snapshot stale | Cancellation/generation/snapshot token | Discard all private cards and continuation; no state publication | No | No | `CANCELLED_STALE_REJECTED` |
| validation | Missing/corrupt/incompatible restart | Failed field validation or broken parent digest | No canonical state acquired | No | No | `INVALID_RESTART_REJECTED`; try defined earlier fallback only |

## 5. Canonical finalization rule

### 5.1 Exact rule

A card `C` is canonical-finalizable if and only if all of the following are true:

1. `C` consists solely of an ordered, gap-free list of stable source slices derived from the pinned source snapshot.
2. Every deterministic split/rebalance decision affecting those slices is complete. For a paragraph this includes the chosen sentence/clause/word/grapheme boundary; for a table it includes its row interval; for a list it includes the exact item/block fragment state.
3. One of these membership proofs exists:
   - the immediate next nonempty atomic unit has been classified, direct merge failed or overflowed, every eligible rebalance candidate failed, and the next/tail cannot attach backward into `C`;
   - a stable hard structural boundary has been reached and the tail attach/no-attach decision has been completed;
   - trusted logical section or book end has been reached and terminal backward attachment has been completed.
4. No `deferredPredecessor` relationship remains for `C`.
5. Publication/layout/parser/pagination identities used for measurement still equal the request identities.

Height alone is never the finalization proof. A visually full card is finalized after the next ordered nonempty unit or a trusted hard/logical end proves that merge, rebalance, and backward attachment cannot change it. A short card uses the same proof; it is not flushed merely because the caller stopped asking for source.

The lookahead is exact rather than an arbitrary count: consume adjacent atomic units until the immediate-unit rule resolves the current frontier. Merge/rebalance consult only the immediate next unit. A deferred predecessor may wait while a tiny tail absorbs more adjacent units, but the frontier stays at two cards and the number of nonempty structural entries is bounded by the line-capacity rule in section 13.

### 5.2 Required cases

| Case | Canonical treatment |
| --- | --- |
| Full-height card | Inspect the next nonempty atom or trusted hard/logical end. Finalize only after measured merge/rebalance/backward-attach failure; do not infer from `height >= budget`. |
| Short card | Continue consuming compatible adjacent atoms. Finalize at a proved hard boundary, measured failure with no valid rebalance/attachment, or logical end. |
| Section final card | Section identity/source file is a hard merge key. A trusted section-end marker resolves the frontier exactly; the next section cannot merge backward. |
| Book final card | Trusted source-snapshot end resolves the frontier, including one final tiny-tail backward attachment. It emits a terminal continuation marker. |
| Request budget ends | Return finalized prefix plus a provisional continuation. Emit neither frontier card nor an identity for it. |
| Split paragraph | The next cursor contains the exact logical/source UTF-16 boundary. A fragment finalizes only by the same immediate-unit rule; continued fragments retain paragraph ID and start/end flags. |
| Heading plus prose | A heading and body prose never share a card because `isHeading`/`blockRole` is a hard boundary. The prose supplies boundary evidence but not heading membership. Consecutive heading/generated-heading fragments may merge only when their stable section, source file, heading role, and generated owner are compatible. |
| List | Merge only compatible same-list/direct-nesting fragments under `readerListSemanticsShareListOrDirectNesting`; never sentence-rebalance a list. Finalize on incompatible list structure, measured overflow, hard boundary, or logical end. |
| Table | Isolated from text/list merge. Oversized tables split only at stable row boundaries and each fragment retains table owner and row interval. |
| Image/milestone/nontext | Isolated atomic card. Prior frontier resolves first; the structure finalizes from its intrinsic source/generated owner and the next hard boundary. |

State retained instead of a request-tail flush is: next stable source cursor, `deferredPredecessor` if any, `pendingTail` if any, their ordered source slices and structural metadata, the previous finalized boundary, chain identity, and integrity evidence. No rendered card array is retained.

## 6. Immutable request model

The future request is an immutable value. It contains:

- publication fingerprint and book ID;
- parser/source schema identity and a revision-pinned immutable source snapshot or stable section resolver;
- current `readerPaginationAlgorithmVersion` identity and controlled layout identity/inputs;
- one validated restart or continuation;
- optional stable target source identity plus source UTF-16 offset;
- output policy (`initial`, `target`, `forward`, or `backward-regeneration`) and explicit work/output budgets;
- generation/operation token, scheduler, cancellation predicate, and diagnostics as noncanonical controls.

The source snapshot must guarantee that a stable section/source identity resolves to the same `BookChunk` content and structural metadata for the request lifetime. `List.unmodifiable` over a mutable live list is insufficient. A request cannot accept a display index, current window index, controller index, or `_currentPage`-style value as a restart, target, or identity input. A source ordinal may be carried only as a validated lookup hint paired with stable source identity.

## 7. Immutable continuation payload

The conceptual payload is `CanonicalPaginationContinuation`. P04 may implement deterministic in-memory serialization tests, but P06 alone chooses persistent cache schema, compatibility, migration, invalidation, and version changes.

| Field | Stable authority/source | Why required | Validation rule | Bounded size | Forbidden alternative |
| --- | --- | --- | --- | --- | --- |
| `contractKind` | P04 continuation contract constant, not a persisted-cache version | Prevent decoding another record type | Exact supported kind | One scalar | Inferring type from cache path |
| `publicationFingerprint` / `bookId` | Open publication/source authority | Prevent cross-book/publication reuse | Exact request match | Fixed hashes/IDs | Filename or screen book label |
| `parserSourceIdentity` | Parsed-content version, parser version/schema, immutable snapshot digest | Ensure slices reconstruct identically | Exact identity and digest match | Fixed tuple | Source count alone |
| `paginationAlgorithmIdentity` | Existing pagination identity | Prevent algorithm-crossing replay | Exact request match | One string/hash | Current card count |
| `controlledLayoutIdentity` | Captured layout signature/fingerprint | Ensure measurements/classifications agree | Exact request match; P05 later completes fields | One hash plus validated inputs held by request | Widget tree, `BuildContext`, viewport index |
| `spineSectionIdentity` | Stable spine index/href/section identity | Scope cursor and hard boundaries | Resolves exactly in pinned snapshot | One fixed tuple | Current loaded-section array index alone |
| `nextSourceCursor` | Stable source owner plus validated local ordinal and UTF-16/row/fragment offset | Identify next unconsumed atom | Owner resolves uniquely; offsets are grapheme/row/fragment boundaries and within extent | One cursor | Display or controller index |
| `deferredPredecessor` | Reconstructable ordered source-slice descriptors | Preserve a card still eligible for tiny-tail attachment | Rebuild and remeasure exactly; max one descriptor group | At most one card frontier | Retained rendered `BookChunk` as unchecked authority |
| `pendingTail` | Reconstructable ordered source-slice descriptors | Resume merge/rebalance without request-tail flush | Rebuild text/rich metadata and remeasure exactly | At most one card frontier | Flushed tail identity |
| Each `SourceSlice` | `ChunkSourceRange`, stable logical/source owner, exact UTF-16 or table-row interval | Preserve split offsets, repeated-text disambiguation, and ownership | Ordered, nonempty readable interval; source/logical offsets agree; checksum matches | At most `U` entries across frontier after deterministic coalescing | Visible text checksum alone |
| Structural metadata | `BookChunkType`, `BookBlockRole`, heading/dialogue, publisher layout, paragraph/list/table/generated fragment owner | Resume hard merge and finalization classification | Must equal metadata re-derived from source | Fixed metadata per slice/group | Recomputed structure from rendered text |
| Frontier decision state | Whether predecessor is deferred, chosen split boundary, list/table fragment state | Distinguish exact pending geometry from unconsumed source | Recompute all merge/tiny/height predicates; stored classification is validation evidence, not independent truth | Fixed flags/offsets | Mutable display membership |
| Full-span split provenance | Production `buildSplitChunk` result for a source interval equal to `[0, source.length)` | Distinguish an explicitly split fragment whose structural flags/metadata differ from the unsplit source | Rebuild with the production split helper and require every derived digest/flag to match | One boolean per text slice | Copied fragment text or assuming every full-span interval is the original chunk |
| `previousFinalizedBoundary` | Last canonical `ReaderCardIdentity`, exact end cursor, or publication-start sentinel | Chain continuation and validate append/prepend seam | Identity recomputes from finalized ranges; end equals frontier start | One identity/cursor | Previous display index |
| `chainOrdinal` / `parentDigest` | Monotonic in-memory continuation chain | Reject stale/forked continuations | Expected parent digest and ordinal at seam | Two scalars/hash | Screen generation alone |
| Checkpoint reason / interval counters | Accepted predecessor checkpoint plus fully consumed source/finalized-card accounting | Preserve the 48-source/eight-card cadence across smaller requests | Counters are nonnegative and within their stride; cadence reasons require the exact reached stride; provisional exhaustion must be below both | Two bounded integers plus one enum | Mutable request/window start or generation counter |
| `integrityDigest` | Canonical encoding of all payload fields | Detect corruption/partial reconstruction | Recompute before use | One hash | Cache file checksum as authority |
| Terminal flag | Trusted section/book end evidence | Distinguish resumable and terminal continuation | Must agree with snapshot boundary | One enum | Empty result interpreted as end |

Not stored because it is derivable or noncanonical: measured height caches, rendered widgets/spans, complete retained card arrays, display maps, request/source-window indexes, target display index, controller state, cache file location, scheduler/generation counters, or arbitrary widget state. Detailed work counters are returned as diagnostics; only the two bounded checkpoint-interval counters above participate in continuation cadence.

The payload is safely serializable as a canonical scalar/list/map structure because it contains stable identities and offsets, not runtime objects or copied text. P04 serialization is an in-memory contract only. P06 decides whether any field is persisted and how old cache records are invalidated or migrated.

## 8. Safe restart boundaries

| Restart type | Required evidence | Maximum predecessor work | Can reconstruct pending state? | Valid for target-first? | Valid for backward preparation? | Rejection/fallback |
| --- | --- | --- | --- | --- | --- | --- |
| Publication/book beginning | Matching publication/source snapshot and first stable source cursor; empty frontier/start sentinel | Zero | Yes, empty | Yes | Only for first bounded region | Reject incompatible snapshot |
| Spine/section beginning | Stable spine/href identity and verified hard reset from prior section/source file | Zero within section | Yes, empty because cross-section merge is forbidden | Yes | Yes for section start | Fall back to prior validated continuation if boundary metadata conflicts |
| Validated continuation checkpoint | Every field in section 7, parent digest, and exact source reconstruction | At most normal checkpoint interval | Yes, exactly | Yes | Yes | Try one immediately preceding chain checkpoint |
| Finalized boundary with sufficient predecessor state | Final card identity/end cursor plus empty frontier, or full continuation carrying nonempty frontier | At most one checkpoint interval | Yes only when frontier evidence is complete | Yes | Yes | A card identity without frontier/next cursor is insufficient |
| Missing/corrupt/incompatible continuation recovery | Earlier valid checkpoint whose chain reaches the rejected record | At most two checkpoint intervals in one attempt | Yes | Yes | Yes | If no valid record inside fallback bound, return `requiredRegenerationFromEarlierRestart`; publish nothing |
| Target without nearby checkpoint | Stable target plus an advancing canonical checkpoint frontier | One bounded advancement attempt; no approximate target card | Eventually, from produced continuation | Yes after checkpoint frontier reaches target | No direct prepend | Advance at most one checkpoint interval per operation; never start at target index |
| Backward preparation | Checkpoint strictly before the first desired predecessor and committed current-card identity | Section 13 backward bound | Yes | No | Yes | Earlier checkpoint once; otherwise typed regeneration requirement |

A random lazy-window boundary, raw `SourceChunkRange.start`, target source index, cache segment start, or current visible/display index is not a safe restart.

When the nearest checkpoint is invalid, the selector verifies its parent and may fall back exactly one additional checkpoint interval. A second missing/incompatible interval stops the attempt with `requiredRegenerationFromEarlierRestart`. Recovery then advances the canonical checkpoint frontier in separate bounded, cancellable operations from the last valid restart; it does not scan an unbounded section or publish an approximate island.

## 9. Target, forward, and backward algorithms

### 9.1 Target-first

```text
resolve stable target against pinned publication/source snapshot
select nearest compatible predecessor checkpoint whose cursor <= target
if absent, select section/publication start only within the bounded advance policy
resume forward canonical state, retaining the two-card frontier
discard no finalized predecessor until its state effect and chain are consumed
continue until the unique target-containing card is canonical-finalized
emit target card, requested bounded neighbors, exact containment evidence,
and successor continuation
if work bound expires first, emit no provisional target; return continuation-needed
```

Target evidence is the target stable source owner/offset, finalized card identity, exact containing `SourceSlice`, and offset within that slice. A repeated visible string is never target evidence. At most seven canonical predecessor cards from the normal nearest checkpoint are emitted privately and discarded after the target is finalized; one-checkpoint recovery permits at most fifteen.

### 9.2 Normal forward expansion

Forward generation resumes only from the accepted suffix continuation. It validates that `previousFinalizedBoundary` equals the published last card and that the next cursor equals the published suffix end. It emits only newly finalized cards. The previously published suffix is never supplied for repacking and never replaced. A budget end returns a new provisional continuation; a logical end returns a terminal continuation.

### 9.3 Backward/prepend generation

Backward generation never reverses source or packs from right to left:

```text
select a validated checkpoint strictly earlier than the desired predecessor
regenerate forward canonically
retain only finalized predecessor cards needed by the bounded prepend window
continue through the already committed/current boundary
recompute and compare the committed current card identity and exact source ranges
inspect enough successor state to prove that boundary final
if every identity/cursor/coverage/structure check agrees, prepend only predecessors
otherwise reject the entire result and require an earlier restart
```

The exact previous/current/next order is proved by the continuation chain: predecessor end cursor equals current start, regenerated current identity equals committed identity, and current end cursor equals the accepted successor continuation start. At a section boundary, regeneration may start at that section only when the desired predecessor is in that section; crossing into the previous section requires its earlier checkpoint/section start and separately proves the cross-section hard seam.

If no earlier checkpoint exists within the normal bound, one preceding checkpoint fallback is allowed. If the publication/section beginning is within that bound it is valid; otherwise the prepend is rejected as `requiredRegenerationFromEarlierRestart`. No committed card is changed while recovery advances.

## 10. Structural and identity ownership

| Structure | Stable owner | May merge? | Required context | Finalization boundary | Identity inputs | Seam rule |
| --- | --- | --- | --- | --- | --- | --- |
| Generated navigation fragment | Parser/generated owner ID plus nav source file, list/item/block ID, source interval | Only compatible adjacent generated nav/list fragments | Same section/file, generated owner class, list nesting and layout | Incompatible generated owner/list, overflow, nav end | Publication/layout/pagination + owner IDs + ranges, never label text | Exactly one owner; no regeneration from target label |
| Chapter heading | Section href/spine plus logical heading block and source range | With compatible consecutive heading fragments only | Same section/file/heading role/layout | Body prose, incompatible heading, overflow, section end | Stable heading block and ranges | Heading/body seam cannot overlap or transfer ownership |
| Subsection heading | Logical heading block within section | Same rule as chapter heading | Predecessor heading continuation and immediate next | Hard role change/overflow | Logical block plus ranges | Target-first must reproduce full heading group |
| Section-start heading | New section/spine stable identity | Only within its own section and compatible heading group | Trusted cross-section hard reset | Body or section end | Section identity, logical block, ranges | Previous section terminal tail finalizes before it |
| Split/continued paragraph | Source/logical paragraph ID and exact UTF-16 offsets/start/end flags | Compatible adjacent fragments under current merge rules | Exact previous/next paragraph offsets and boundary kind | Overflow/rebalance/hard/logical end | Ordered ranges and paragraph offsets | Adjacent offsets meet exactly; no gap/overlap |
| Repeated identical text | Distinct stable source owner/logical block/offset | According to structure, not text equality | Stable owner resolution | Ordinary canonical rule | Owner identity/checksum plus ranges | Visible checksum cannot collapse occurrences |
| Ordered/unordered list | Stable list/item/block IDs, depth, ordering/ordinal/marker metadata | Same list or direct nesting only | List fragment state and adjacent item semantics | Incompatible list, overflow, structural/end | List IDs/ordinal/fragment ranges | Marker/item ownership remains with source item |
| Table | Stable table logical block plus row interval | No text/list merge; row fragments only within table | Table model and row boundary | Fragment fit, table end, structural/end | Table owner + source range + row interval | No row duplicated/lost at segment seam |
| Inline bold/italic/link | Parent source/logical block; exact inline offsets and target metadata | With parent paragraph under normal rules | Offset shifting/clipping through split/merge | Parent card boundary | Parent ranges plus inline span offsets/checksums | Span intervals remain within owning slice |
| Footnote reference/body | Reference/body stable owner, link target, exact offsets | With owning paragraph if normal merge permits | Reference-target metadata retained; body remains its parsed owner | Parent/structural boundary | Owner/range/link metadata | Reference cannot migrate by equal visible marker |
| Image | Stable source/resource owner and checksum | No | Prior frontier resolved; resource owner valid | Intrinsic atomic boundary | Resource/source identity and checksum | Isolated, gap-free source order |
| Generated milestone | Explicit generator kind, stable neighboring canonical boundaries, deterministic ordinal | No | Both neighboring finalized boundaries | Atomic once both owners known | Generator kind + predecessor/successor identities | Must not be generated from mutable display count/index |
| Cross-section seam | Two stable section/spine identities | Never across seam | Trusted end/start evidence | End of prior section | Terminal prior and start-next cursors | Prior tail finalizes before next section starts |
| Terminal tail | Last stable source slices | Eligible final tiny backward attachment only | Trusted section/book end | Terminal attach/no-attach completed | Final ranges and terminal marker | Request end is not terminal evidence |

`ReaderCardIdentity` is created only after `CARD_FINALIZABLE`, using canonical finalized `ReaderCardSourceRange` evidence and compatible publication/layout/pagination identities. The existing synthetic fallback is not permitted when stable source ranges should exist. A generated-only card requires the deterministic generated-owner inputs above; text and mutable indexes are forbidden substitutes.

The current exact identity fields are preserved: `ReaderCardSourceRange.sectionIdentity`, `sectionChecksum`, `logicalBlockId`, `structuralType`, `startUtf16`, `endUtf16`, and optional `contentChecksum`; `ReaderCardIdentity.publicationFingerprint`, `layoutFingerprint`, `paginationVersion`, ordered `ranges`, and derived `signature`. `ReaderCardIdentity.fromCard` currently derives these from `BookChunk.effectiveSourceRanges` and stable locations, falls back through source-index projection when ranges are absent, and finally has a text-derived synthetic fallback. P04 may use the first two paths only after canonical finalization and stable-owner validation. The final synthetic fallback is allowed solely for a generated-only structure satisfying the explicit generated-owner rule; it cannot rescue missing ownership on parsed text/list/table/image content.

## 11. Progressive seam validation and published-card immutability

The future paginator/result contract supplies finalized cards, predecessor and successor continuations, exact source cursors, compatibility identities, target evidence, and work accounting. `ProgressiveDisplayState` applies an extension transactionally: validate against an immutable snapshot, build new projection maps privately, then swap only on complete acceptance.

Append/prepend validation must prove:

1. publication, parser/source snapshot, pagination, and controlled layout identities match;
2. the supplied continuation is the exact accepted suffix/prefix chain record;
3. the adjoining source cursors meet exactly;
4. ordered source slices are gap-free and nonoverlapping, including within-source offsets;
5. every already-published card identity and finalized range in the preserved prefix/suffix is unchanged;
6. the committed card identity is still present exactly when the transaction concerns it;
7. structural owners, list/table fragment boundaries, paragraph continuation flags, and section seams agree;
8. the generation is current at the final atomic swap.

Typed outcomes:

| Outcome | Meaning | Mutation allowed |
| --- | --- | --- |
| `acceptedExtension` | Every compatibility, seam, identity, structure, and generation proof passed | Atomic append/prepend only |
| `incompatibleContinuation` | Chain/publication/parser/layout/pagination evidence differs | None |
| `staleGeneration` | Generation/snapshot changed before acceptance | None |
| `seamGap` | Successor start is after accepted end | None |
| `seamOverlap` | Successor start is before accepted end or repeats a slice | None |
| `committedCardMismatch` | Regenerated committed/current card identity or ranges differ | None |
| `publishedPrefixIdentityMismatch` | Append would alter an accepted prefix | None |
| `publishedSuffixIdentityMismatch` | Prepend would alter an accepted suffix | None |
| `structuralOwnershipMismatch` | Owner/paragraph/list/table/section metadata conflicts | None |
| `requiredRegenerationFromEarlierRestart` | Available restart is insufficient to prove the seam within bounds | None; schedule bounded recovery |

There is no “best effort” splice and no silent replacement/repacking of an accepted card. Rebuilding transient `displayToOriginal`/`originalToDisplay` maps after acceptance is permitted because those maps are projections, not card authority.

## 12. Cancellation and stale-work behavior

All source resolution, splitting, measurement, frontier mutation, identity creation, and result assembly occurs privately. Cancellation or staleness at any checkpoint returns `cancelledStaleRejected` with no cards, no accepted continuation, and no cache-write authority. Previously published state remains untouched.

Cancellation is checked at least:

- before every source and every atomic subchunk;
- every two table rows while table splitting;
- every oversized token and every 12 grapheme candidates;
- every four sentence split or rebalance candidates;
- before/after each frontier finalization, card emission, and continuation creation;
- at the scheduler's existing frame-budget checkpoint and immediately before the progressive-state atomic swap.

A continuation assembled by a stale generation is discarded even if its checksum is internally valid. Generation IDs prevent publication races, but are not part of canonical identity and cannot make an otherwise incompatible continuation valid.

## 13. Boundedness and memory limits

### 13.1 Derived constants

The current screen uses lazy initial lookbehind/lookahead/minimum values `8/39/48`, a non-lazy minimum of `96`, and adjacent source requests of `192`. P04 uses these existing lazy constraints to derive initial bounds:

- source checkpoint stride `S = min(lazyMinimumInitialSources, adjacentSources / 4) = min(48, 192 / 4) = 48` fully consumed source chunks;
- card checkpoint stride `C = lazyInitialLookBehind = 8` canonical cards;
- active source-window ceiling `Ws = lazyMinimumInitialSources + (2 * adjacentSources) = 48 + (2 * 192) = 432` source chunks: one centered lazy window plus one adjacent preparation in each direction;
- active canonical publication-window ceiling `Wc = nonLazyMinimumInitialSources = 96` resident cards until profiling in P11 approves a smaller value; P04 must prove it is never exceeded;
- let `L = ceil(max(pageHeightBudget, physicalTextBudget) / minPositiveLineBoxHeight)` be the maximum measured line capacity of one card. After contiguous slices with the same stable source/logical owner are coalesced, the two-card frontier plus its immediate proof atom has structural-entry cap `U = (2 * L) + 1`. For the P03 standard `680` px card and default `23.4` px line box, `L = 30` and `U = 61`. For split-stress `58` px, `L = 3` and `U = 7`.

The line-capacity derivation first coalesces adjacent slices belonging to the same stable source/logical owner with exactly contiguous offsets; coalescing changes neither ownership nor identity input. Every remaining distinct nonempty mergeable text/list entry consumes at least one measured line/structural separator, and each of the two frontier cards is constrained by the card height budget. Empty source chunks advance the cursor without entering the frontier. Images/tables/generated atomic structures do not accumulate as mergeable zero-height entries. An implementation that observes a counterexample must reject the continuation and add a P04 fixture; it may not silently exceed `U` or invent a boundary.

### 13.2 Required bounds

| Quantity | Bound/invariant | Initial ceiling and proof |
| --- | --- | --- |
| Source units between restart checkpoints | Checkpoint after `S` fully consumed chunks or `C` finalized cards, whichever occurs first; also at section start/end | `48` source chunks and `8` cards; long-source test proves card cadence |
| Copied UTF-16/text in continuation | Source-slice descriptors only; reconstruct from pinned stable source | Exactly `0` copied UTF-16 code units. Record referenced UTF-16 extent for diagnostics. |
| Pending structural entries | Across deferred predecessor, pending tail, and immediate proof atom after stable-owner coalescing | `U`; P03 standard ceiling `61`, split stress `7` |
| Normal target predecessor work | One checkpoint interval plus target-card frontier and one immediate proof atom | At most `S + U + 1 = 110` source/fragment entries and `C - 1 = 7` privately discarded predecessor cards in standard layout |
| One-checkpoint target recovery | Two checkpoint intervals plus target frontier/proof | At most `2S + U + 1 = 158` entries and `2C - 1 = 15` discarded predecessor cards; otherwise typed rejection |
| Backward preparation | Prior checkpoint through regenerated current card plus successor proof | At most `S + U + 1 = 110` entries and at most `C + 2 = 10` finalized/regenerated cards; one fallback raises to the same `158`/`18` recovery envelope |
| Resident continuation records | Checkpoint every `C` cards in `Wc` and every `S` sources in `Ws`, plus prefix/suffix guards and section boundaries | `ceil(96 / 8) + ceil(432 / 48) + 4 = 25` per active loaded publication window before deduplication; evict records with their cards/sources, never the two seam guards |
| Cancellation work quantum | Maximum loop work between explicit checks | `1` source, `1` subchunk/token, `2` table rows, `12` graphemes, or `4` sentence/rebalance candidates, plus scheduler frame budget |
| Emitted result | Only finalized requested cards and bounded neighbor policy | Never more than the caller's explicit card budget; target predecessors are discarded only after target proof |

The counters are a work vector, not a single ambiguous number: source chunks entered, atomic fragments processed, UTF-16 referenced, table rows, grapheme candidates, rebalance offsets, cards finalized, cards discarded, continuation records, continuation descriptor bytes, resident cards, and peak private/frontier bytes. P04 tests must assert every counter on long prose, a single source split into many cards, many tiny mergeable sources, lists, tables, target fallback, and backward regeneration.

If a limit is reached before a card is provably final, the operation returns `budgetExhaustedProvisional` with a bounded continuation and no provisional card. If the continuation itself would exceed `U`, the operation returns a typed bound violation and no publication; TASK-P04-008 must prove the initial ceilings against approved fixtures before tuning. Tuning must preserve the formulas and be recorded; convenience alone is not a reason to change a ceiling.

No operation paginates a whole book. A distant target with no nearby checkpoint advances a canonical checkpoint frontier by at most one `S`/`C` interval per cancellable operation. It cannot publish the target until an attempt begins from a valid checkpoint inside the stated normal/recovery envelope.

## 14. Failure-ledger mapping

All P03 IDs and comparisons remain unchanged.

| Failure ID/scenario class | Observed mismatch | Violated invariant | Proposed state-machine/finalization rule | Implementation task | Green proof |
| --- | --- | --- | --- | --- | --- |
| `P03-TARGET-001` first-readable | Heading reference owns 2,3; request tail made 2 alone | Request end treated as logical end | Retain heading tail; consume compatible heading 3 before finalization | P04-002/004/006 | Existing target equality green |
| `P03-TARGET-002` generated TOC | Same heading seam as TARGET-001 | Target range did not carry successor state | Valid predecessor checkpoint plus provisional successor continuation | P04-003/004/006 | Existing target equality green |
| `P03-TARGET-003` chapter heading | Nav reference owns 0,1; prepend made 0 and 1 islands | Reverse/independent prepend packing | Regenerate forward from publication start/checkpoint and verify current seam | P04-005/007 | Existing target equality green |
| `P03-TARGET-004` subsection heading | Reference 4,5,6,7; actual source 4 island | Target boundary flushed predecessor tail | Two-card frontier and no request-tail finalization | P04-002/004 | Existing target equality green |
| `P03-TARGET-005` mergeable prose | Reference 4–7; actual 4–6 then 7,8 | Successor merge context omitted | Resume exact frontier until immediate-unit membership proof | P04-003/004 | Existing target equality green |
| `P03-TARGET-006` long paragraph | Reference 4–7; actual 4,5 then 6,7,8 | Split/rebalance predecessor context omitted | Exact split cursor plus pending/deferred frontier | P04-002/003/004 | Existing target and split-stress green |
| `P03-TARGET-007` first repeated prose | Reference 4–7; actual 4–6 then 7,8 | Text/window position substituted for canonical context | Stable owner slices and successor continuation | P04-003/004/006 | Existing target equality; repeated owners distinct |
| `P03-TARGET-008` table target | Reference list owns 9,10; actual list islands | List tail flushed at request seam | Preserve list semantics; no list rebalance; finalize with next/hard evidence | P04-004/006 | Existing target equality and structural suite green |
| `P03-TARGET-009` inline/link/footnote | Reference 12–15; actual 12–14 then 15 | Provisional rich-text tail published | Retain source slices and shifted inline/link/footnote offsets until final | P04-004/006 | Existing target equality/content green |
| `P03-TARGET-010` before spine seam | Reference 12–15; actual 12,13 then 14,15 | Target-first start lacked predecessor packing | Restart from earlier checkpoint; discard predecessors after target proof | P04-004/006 | Existing target equality and seam coverage green |
| `P03-TARGET-011` second-section heading | Prior section reference 12–15; actual 12–14 then 15 | Section request made prior tail final too early | Prior section terminal tail finalized only at trusted section end | P04-004/006 | Existing target equality and cross-section ownership green |
| `P03-TARGET-012` after spine seam | Reference 17–19; actual 17,18 then 19 | Second-section request tail flushed | Section-start restart plus retained same-section frontier | P04-003/004/006 | Existing target equality green |
| `P03-FORWARD-001` forward-first | Source 4 island vs reference 4–7 | Append concatenated independent packing | Successor continuation is mandatory; published prefix immutable | P04-004/007 | Existing forward equality green |
| `P03-PREPEND-001` backward/prepend-first | Same source 4 island | Reverse/independent prepend packing | Earlier checkpoint, forward regeneration, committed-card/seam proof | P04-005/007 | Existing prepend equality green |
| `P03-SINGLETON-001` forward then backward | Singleton 5 remained island | Singleton publication accepted provisional card | Target cannot publish until containing card finalized | P04-004/007 | Existing singleton equality green |
| `P03-SINGLETON-002` backward then forward | Same singleton 5 island | Construction order could freeze provisional membership | Immutable canonical target plus validated extensions | P04-004/005/007 | Existing singleton equality green |
| `P03-SINGLETON-003` heading forward then backward | Heading 3 singleton vs reference 2,3 | Missing heading predecessor context | Target restart before heading group; forward finalization | P04-004/006 | Existing singleton equality green |
| `P03-SINGLETON-004` heading backward then forward | Same heading singleton | Prepend could not repair published island | Never publish island; reject mismatched committed card | P04-005/006/007 | Existing singleton equality green |
| `P03-CACHE-001` cold segmented | Fresh segmented construction replayed source-4 island | Generation was noncanonical before storage | P04 canonicalizes cold segment construction | P04-004/007/008 | Existing cold-segmented equality green |
| `P03-CACHE-002` warm memory | Memory replayed canonicality defect exactly | Cache record lacks canonical seam contract | P04 fixes generation; P06 proves memory compatibility/replay | P04 primary; P06 | Existing equality green after P04/P06 ownership gates |
| `P03-CACHE-003` warm disk | Disk manifest/payload replayed island | Compatible bytes were not canonical bytes | P04 fixes generation; P06 owns persistent compatibility/migration | P04 primary; P06 | Existing warm-disk equality green without oracle change |
| `P03-CACHE-004` memory eviction | Disk fallback plus memory hits recreated island | Eviction reassembled independent ranges | Canonical seam generation first; P06 validates mixed-source replay | P04 primary; P06 | Existing eviction equality green |
| `P03-CACHE-005` close/reopen reload | Fresh services loaded persisted island | Persistent record had no continuation authority | P04 defines serializable contract; P06 decides storage/migration | P04 primary; P06 | Existing reload equality green after P06 |

The six already-green structural constructions remain regression gates. P04 must not change their authored owner tuples or complete coverage. The source-7 split-stress ranges also remain a protected split proof. Cache rows 002–005 do not authorize P04 to choose a disk format or migrate data.

## 15. Compatibility and version boundary

P04 changes construction semantics but this design task changes no version. During implementation, canonical in-memory continuations are valid only under exact publication, parser/source snapshot, pagination, and controlled layout identities. Existing memory/disk range records do not become canonical merely because their current keys match.

P06 alone decides:

- persistent cache format and schema;
- whether old segments can be validated, migrated, or must be invalidated;
- manifest/payload continuation storage;
- compatibility rules across parser/layout/pagination changes;
- cache/checkpoint version bumps and rollback behavior.

P04 may serialize a continuation deterministically for round-trip tests, but must not write it to current cache files or claim persistent compatibility.

The frozen P02 parity baseline proves that extraction was behavior-preserving. It must not be silently updated. P04 is intentionally the first behavior-changing phase. Any legitimate P04 signature/range change requires an explicit ordered source-range rationale linked to a P03 failure or approved ownership rule. P03 relational comparisons are the primary red/green authority. Later treatment of historical P02 expectations must be separately recorded; it cannot be disguised as extraction drift.

## 16. P04 implementation slicing

| Task | Expected files/symbols | Prerequisite artifact | Tests to add/turn green | Prohibited neighboring work | Rollback boundary | Recommendation |
| --- | --- | --- | --- | --- | --- | --- |
| `TASK-P04-002` | `reader_card_paginator.dart`: immutable request/result/frontier and forward state machine; possibly narrow models in `book_chunk.dart` | Sections 3–6 | State transitions, no request-tail flush, full/split/list structural preservation | Progressive publication, cache persistence, layout redesign, versions | Revert core API/state machine only | Run alone |
| `TASK-P04-003` | Paginator continuation model/codec; `reader_checkpoint.dart` only if canonical range identity helpers are shared | Section 7 tables/checksums/bounds | Field validation, deterministic round-trip, corrupt/stale/window-index rejection | Persistent cache read/write or version changes | Revert continuation types/codec | Run alone; may pair with 004 only if API cannot compile separately |
| `TASK-P04-004` | Paginator target/initial/forward selection; ReaderScreen paginator adapter only | Sections 8–9 and working continuation | 12 target failures, forward failure, target bounds, provisional budget result | Backward/prepend, cache migration, restore UX | Revert forward/target adapter | Prefer alone after 003 |
| `TASK-P04-005` | Forward-regeneration prepend path in paginator/ReaderScreen adapter | Backward algorithm and seam identity | Prepend failure, backward singleton orders, current-card mismatch, work bounds | Reverse packing, navigation UX, checkpoint restoration | Revert backward preparation path | Run alone |
| `TASK-P04-006` | Structural ownership helpers in paginator, `book_chunk.dart`, `final_layout_paragraphs.dart`, `reader_list_layout.dart`; `reader_checkpoint.dart` identity inputs if needed | Section 10 | Existing six structural cases stay green; heading/generated/split/table owner unit tests | Parser repairs, fixture changes, visual layout redesign | Revert structural canonicalization independently | Run after 002; do not bury in 008 |
| `TASK-P04-007` | `progressive_display_state.dart`, ReaderScreen publication adapter | Section 11 typed outcomes | Seam gap/overlap, continuation mismatch, prefix/suffix/committed immutability, singleton cases | Cache format, restoration/settlement policy | Revert transactional seam integration | Run alone |
| `TASK-P04-008` | P03 matrix plus new focused P04 boundedness tests only | All prior slices | All 23 ledger rows green at unchanged comparisons; bounds/cancellation/retention counters | P02 expectation edits, fixture edits, legacy reconciliation, production feature work | Test/evidence-only rollback | Run alone as final gate |

Default recommendation: keep every task as a narrow reversible turn. The only acceptable grouping is `TASK-P04-003` with `TASK-P04-004` when continuation types and the first forward consumer cannot form a compiling intermediate; still record both task evidence separately. `TASK-P04-005` and `TASK-P04-007` should always run alone because their rejection paths protect committed state. `TASK-P04-008` is evidence-only and must not absorb implementation fixes without a separate task record.

## 17. Unresolved blockers

No technical decision required by `TASK-P04-001` remains unresolved. Numeric ceilings are fixed by formulas and initial current-layout constants above; implementation instrumentation may demonstrate that a smaller ceiling is safe, but may not weaken the invariant or silently tune it. P05 still owns the final measurement/rendering identity. P06 still owns persistent cache compatibility/migration. P08 still owns exact-restoration recovery UX. None blocks beginning `TASK-P04-002`.
