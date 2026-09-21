# Lazy source-address consumer inventory — CHANGE-20260921-041

Scope: production `lib/**/*.dart` at HEAD
`008989ca3457e5ed6c3fdb48b8d1337f8fbbbea4`. No production source was edited.
This inventories `BookChunk.index` (serialized root `payload.i`),
`sourceOrdinalHint`, their codecs/copies, and downstream projection/persistence
boundaries. It is not an assertion that every integer in the reader is an address.

## Semantics and decision

Categories: **S** stable identity/identity evidence; **P** persisted or
checkpoint data; **Q** source projection; **R** runtime resident-list lookup;
**O** display/source ordering; **D** diagnostics only. A use can have more than
one category. “S (snapshot)” means snapshot-bound authority, not a stable lazy
address. “P” includes physical cache/continuation codecs, not just the user
checkpoint table.

- `BookChunk.index` is section-local in `ParsedSection`, dense across the
  loaded window in `LazyBookSession.loadedWindow`, and copied from the first
  source into paginator display fragments. It is **not** a whole-book stable
  address. The same root JSON key therefore persists two different domains:
  parsed-section records and emitted display records.
- `canonicalBookChunkOwnershipDigest` removes root `i` and source-range
  `ci`. The canonical card signature excludes ordinal hints, but its builder
  checks their ordering. That does not remove them from card/continuation bytes.
  `CanonicalPaginationSourceSnapshot.pin` includes checked ordinals in its
  snapshot evidence and requires `chunk.index == ordinal`.
- `CanonicalReaderCardIdentityBuilder.build` signs stable source ownership,
  slices, structural evidence and layout identity. In contrast,
  `ReaderCardIdentity.fromCard` has a legacy block-id fallback to
  `source.index` when stable/local ownership is absent. That fallback is
  identity-bearing and cannot silently become a new lazy address.
- `CanonicalDisplaySegmentCardRecord.fromFinalized` serializes the **entire**
  card JSON as structural payload. Cursor/owner/slice codecs also encode the
  ordinal; cache admission/migration checks exact source intervals. A new lazy
  address must not reinterpret old physical records under unchanged validators.
- Runtime lookup is already partly separated through `LazySourceChunkIdentity`
  and `StableBookLocation`. Its existence does not prove all consumers use it:
  display-range remapping actually rewrites `index`/`originalChunkIndex`.
  That legacy operation cannot be used to claim unchanged retained-card bytes.
- Derived indexing uses **section-local** parsed indexes in stable section
  records. Search/memory/annotation paths also have numeric fallback keys and
  resident maps. Preserve the distinction; do not globally replace every
  numeric index.
- `BookListSemantics.toJson/fromJson` at
  `lib/models/book_list_semantics.dart:70,87` uses `i` for a **string itemId**.
  Enum `.index`, controller/card display positions and OPF spine positions are
  separate types/domains; they are not root `payload.i`.

The proposed tuple and exact fragment/membership requirements are in
[design §12](nalori-lazy-snapshot-handoff-design.md#12-stable-lazy-source-address-proposal-and-explicit-representation-gate).
No persistent encoding is selected. The production paginator counterexample
still emits `i=14` / hint 14 for B in A+B and `i=0` / hint 0 for B alone.
An address witness is insufficient to close that exact-byte gate.

## Codec declarations and indirect consumers

These declarations/string-literal codecs supplement resolved expression
references in the appendix (the analyzer does not visit every declaration
token as a SimpleIdentifier):

| Exact file/symbol evidence | Category and meaning |
| --- | --- |
| `lib/models/book_chunk.dart`: `BookChunk.index` :239, constructor :303, `toJson` :607, `fromJson` :657 | R/P: numeric root `i` producer/consumer; parser-local or window-relative depending on owner. |
| `lib/models/book_chunk.dart`: `ChunkSourceRange`, `effectiveSourceRanges`, `mapDisplayRangeToOriginal`, `mapOriginalRangeToDisplay` | Q/P/R: `originalChunkIndex` / `ci` is copied from index or explicit ranges, then projected with offsets. |
| `lib/models/canonical_pagination.dart`: `CanonicalPaginationSourceKey` :47,53; `SourceOwner` :62,69; `Cursor` :234,250; `SourceSlice` :280,304; `SectionStart` :631,636; target cursor :1470,1476 | R/O, plus P for serialized cursor/slice/owner; ordinal must agree with independently bound owner. |
| Same file: continuation cursor whitelist :1109 and slice whitelist :1192 | P/R: strict decoding includes hint; no migration was made. |
| `lib/services/progressive_display_state.dart` `_stableSliceProof` :1649, called by `_sameStableFinalizedCard` | S/R: helper excludes hint in one semantic comparison; `_sameFinalizedCard` still compares exact card bytes at :1657–1658. Not permission to normalize R02. |
| `lib/models/stable_book_location.dart` fields :44, `toJson` :124–125, `fromJson` :154, equality :193/hash :219 | P/Q: optional `legacyGlobalChunkIndex` is still serialized and compared. It cannot authorize new lazy identity. Stable section/local fields are distinct. |
| `lib/models/reader_checkpoint.dart` `ReaderCheckpoint.create`, `fromPayload`, `sanitizeStableLocation` :598 | P/S/Q: checkpoint contains signature/anchor/stable location and composite layout identity; not original card payload, ordered slice hints, resolved blocks, or historical window recipe. |
| `lib/services/reader_checkpoint_store.dart` `ReaderCheckpointCoordinator.resolveRestore` :500–563 | P/S: same layout requires signature; changed composite layout selects semantic anchor. L01/L02 execute this after SQLite reopen. |
| `lib/models/bookmark.dart` `Bookmark.locationKey/isSameLocation/toJson/fromJson` :85–128; `ChapterInfo.toJson/fromJson` :182–190 | P/Q: legacy numeric bookmark/chapter chunk keys persist; durable location also persists. No rewrite or migration is authorized. |
| `lib/services/bookmark_service.dart` bookmark creation/location matching :79–185, legacy matching :249–283 | P/Q: consumes projected `chunkIndex`; no new-address compatibility claim from the int type. |
| `lib/services/reader_source_projection_service.dart` `readerHasDurableSourceIdentity` :16, `readerStableLocationMatchesSource` :24, `readerSourceIndexForStableLocation` :67 | Q/R/S: stable book/publication/section/local identity maps uniquely to a resident index, with source offsets checked separately. |
| Same file `resolveReaderBookmarksForSourceWindow` :140, `readerBookmarkProjectionKey` :188, `readerMappedSourceSegments` :204, `_uniquelyVerifiedLegacyBookmarkIndex` :246 | Q/P: stable bookmark rebinding and separately verified legacy preview matching. Legacy matching is not exact checkpoint recovery. |
| `lib/services/parsed_section_cache_service.dart` `ParsedSection.fromJson` call :1280 | P: decode of section-local chunks via parsed-section codec, separate from display-card cache. |
| `lib/services/book_memory_service.dart` occurrence sorting/merging :768–784, :845–854 | Q/O: indirect projected chunk indexes and original offsets, not a stable lazy card number. |

## Resolved producer/consumer appendix

Resolved Dart analysis scanned all production Dart units: **321 expression
records, 280 unique file/line/kind records**, grouped below by enclosing symbol.
Duplicate named-argument/member references on a line are collapsed here. Methods
with the same name in one file share a row; all observed lines are listed.
Line numbers refer to the unchanged production tree, not test files.

### `lib/models/book_chunk.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `withSection` | 336, 337 | R, Q |
| `copyWith` | 393, 394 | R, Q |
| `effectiveSourceRanges` | 463 | Q, R |
| `mapDisplayRangeToOriginal` | 491 | Q, R |
| `mapOriginalRangeToDisplay` | 536 | Q, R |
| `toJson` | 607 | P, R, Q |
| `BookChunk` | 656 | P, R, Q |

### `lib/models/canonical_display_segment.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `CanonicalDisplaySegmentSourceOwner` | 371 | P, R |
| `CanonicalDisplaySegmentCardRecord` | 447 | P (exact payload) |
| `buildForPublication` | 846 | P, R |
| `build` | 890, 893 | P, R |
| `_encodeCursor` | 1675 | P, R |
| `_decodeCursor` | 1697, 1709 | P, R |
| `_encodeSourceOwner` | 1774 | P, R |
| `_decodeSourceOwner` | 1791 | P, R |
| `_encodeSlice` | 1834 | P, R |
| `_decodeSlice` | 1901 | P, R |
| `_sliceStartCursor` | 2214, 2225, 2233 | R, O |
| `_sliceEndCursor` | 2242, 2248, 2254, 2265, 2270, 2273, 2278 | R, O |

### `lib/models/canonical_pagination.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `canonicalBookChunkOwnershipDigest` | 13 | S (excludes i/ci) |
| `<top-level>` | 39 | R, O |
| `toDigestJson` | 76 | S (snapshot only), R |
| `CanonicalPaginationSourceSnapshot` | 129, 130, 137, 144 | S (snapshot only), R |
| `resolveSource` | 210 | R, O |
| `CanonicalPaginationCursor` | 243 | R, O |
| `toCanonicalJson` | 260, 330 | P, R |
| `samePositionAs` | 269 | R, O |
| `build` | 377, 400 | S, O, R (checked order) |
| `_validateSlice` | 453 | S, O, R (checked order) |
| `_decodeCursor` | 1126, 1138 | P, R |
| `_decodeSlice` | 1224 | P, R |
| `CanonicalFinalizedReaderCard` | 1502, 1504 | P (exact bytes) |

### `lib/models/canonical_pagination_checkpoint_index.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `predecessorsAtOrBefore` | 101 | R, O |
| `predecessorsBefore` | 131 | R, O |
| `_compareCursor` | 397 | R, O |

### `lib/models/reader_checkpoint.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `ReaderCardIdentity` | 254, 267, 307 | Q, S, P |

### `lib/screens/reader_screen.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `_resolveLegacyListHighlightByText` | 254 | Q, R |
| `readerDisplayIndexContainingSourceOffset` | 388 | Q, R |
| `publicationDigest` | 488 | D (test observation) |
| `_canonicalPaginationSourceKeys` | 2610 | S, R (stable owner + hint) |
| `_canonicalPaginationSourceRevision` | 2620 | S (snapshot revision) |
| `_displayIndexNearestOriginalOffset` | 3626 | Q, R |
| `_displayIndexContainingSourceText` | 3652 | Q, R |
| `canonicalTarget` | 4558 | R, O |
| `generateCanonicalDisplayRange` | 4773 | R, O |
| `_shiftDisplayChunkSourceIndexes` | 5988 | Q, R |
| `_appendLazySectionToSourceWindow` | 7293, 7296, 7299, 7307 | R, Q (producer) |
| `_prependLazySectionToSourceWindow` | 7349, 7352, 7355, 7363, 7383 | R, Q (producer) |
| `_publishedBoundaryEvidenceForDisplay` | 8800 | P, R (exact boundary bytes) |
| `_prepareChapterLayoutSource` | 9076 | R, Q (producer) |
| `_chapterCardLayoutFromResult` | 9178 | Q, R |
| `_insertMilestoneCards` | 9383 | R, Q (producer) |
| `_firstLocationForDisplayIndex` | 9517 | Q, R |
| `_bookmarkAnchorForDisplayPage` | 10445 | Q, R |
| `_openAnnotationsPanel` | 11159 | Q, R |
| `_sourceWordCountForDisplayIndex` | 11722 | Q, R |
| `_chunkByOriginalIndex` | 11743, 11747 | Q, R |
| `_sourceWordCountForOriginalRange` | 11755 | Q, R |
| `_showChapterPanel` | 12980 | Q, R |
| `_displayIndexForBookmark` | 14499 | Q, R |
| `_buildReadingCard` | 14552 | Q, R |

### `lib/screens/search_screen.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `_performSearch` | 267, 280 | Q, S (legacy fallback) |
| `_searchUnindexedLoadedChunks` | 324, 366 | Q, S (legacy fallback) |

### `lib/services/book_cache_service.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `_serializeDisplayChunks` | 909 | P |
| `_deserializeDisplayChunks` | 926 | P |
| `_serializeBook` | 954 | P |
| `_deserializeBook` | 974 | P |

### `lib/services/book_memory_service.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `_scanCharacterOccurrences` | 397 | Q, O |
| `_chunkSourceSignature` | 486 | R (scan cache key) |

### `lib/services/canonical_display_cache_migration_service.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `_exactIntervalOwners` | 587, 590, 604 | P, R, O (validated admission) |

### `lib/services/canonical_display_segment_admission.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `_validateBoundaries` | 591 | P, R, O (validated admission) |
| `_intervalOwnersResolve` | 674, 677, 694 | P, R, O (validated admission) |
| `_allSlicesResolve` | 710, 718 | P, R, O (validated admission) |
| `_cursorResolves` | 762 | P, R, O (validated admission) |
| `_sliceStart` | 801 | P, R, O (validated admission) |
| `_sliceEnd` | 811, 817, 822, 825, 830 | P, R, O (validated admission) |

### `lib/services/derived_book_index_service.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `buildDerivedIndexSegment` | 419, 455 | S, P, Q (section-local) |

### `lib/services/epub_parser.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `flush` | 865 | R, Q (local/eager producer) |
| `visit` | 1057, 1135, 1263 | R, Q (local/eager producer) |
| `buildSearchIndexInBackground` | 1480 | Q, R |
| `emitPending` | 1510 | R, Q (local/eager producer) |
| `_mergeTinyChunks` | 1519, 1520, 1528, 1555, 1606, 1611 | R, Q (local/eager producer) |
| `_fallbackExtract` | 1689, 1709, 1718 | R, Q (local/eager producer) |

### `lib/services/lazy_book_session.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `loadedWindow` | 643, 647, 653 | R, Q (local to resident map) |
| `_anchorChunkIndex` | 813 | R, Q (local to resident map) |

### `lib/services/lazy_parsed_book.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `toJson` | 200 | P |
| `ParsedSection` | 218 | P |

### `lib/services/progressive_display_state.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `_remapDisplayChunkSourceIndexes` | 413, 437 | Q, R |
| `hasUnavailableBefore` | 577 | R, O, Q (publication validation) |
| `nextForwardRange` | 628 | R, O, Q (publication validation) |
| `_buildCanonicalCandidate` | 1205, 1215, 1216, 1271 | R, O, Q (publication validation) |
| `_validateCanonicalCard` | 1307 | R, O, Q (publication validation) |
| `_validateOrderedCoverage` | 1399, 1405, 1419, 1434, 1435 | R, O, Q (publication validation) |
| `_compareCursor` | 1474, 1475 | R, O, Q (publication validation) |
| `_cardStartCursor` | 1497 | R, O, Q (publication validation) |
| `_cardEndCursor` | 1508, 1515, 1526, 1530, 1531, 1536 | R, O, Q (publication validation) |
| `_cursorBelongsToSnapshot` | 1614 | R, O, Q (publication validation) |
| `_sameFinalizedCard` | 1657, 1658 | S (exact card bytes), R |
| `_shiftDisplayChunkSourceIndexes` | 1786, 1788 | Q, R |

### `lib/services/reader_card_paginator.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `acceptedPublishedCard` | 401, 404, 405 | R, O, Q (source/boundary checks) |
| `publishedSuffixBoundary` | 441, 444, 445 | R, O, Q (source/boundary checks) |
| `targetForStableOwner` | 465, 486 | R, O, Q (source/boundary checks) |
| `_generateTargetInternal` | 539, 559 | R, O, Q (source/boundary checks) |
| `_generateBackwardInternal` | 784, 851, 856, 880 | R, O, Q (source/boundary checks) |
| `_validateAcceptedPublishedEvidence` | 1225, 1226, 1291, 1292 | R, O, Q (source/boundary checks) |
| `_backwardRestartAttempts` | 1341, 1343, 1352 | R, O, Q (source/boundary checks) |
| `_restartSourceOrdinal` | 1360, 1363 | R, O, Q (source/boundary checks) |
| `_sameFinalizedCard` | 1374, 1375 | S (exact bytes), P |
| `_targetCursorAsSourceCursor` | 1395 | R, O, Q (source/boundary checks) |
| `_cardStartCursor` | 1410, 1420 | R, O, Q (source/boundary checks) |
| `_cardEndCursor` | 1427, 1435, 1445, 1449, 1450 | R, O, Q (source/boundary checks) |
| `_sourceStartCursor` | 1460, 5507 | R, O, Q (source/boundary checks) |
| `_compareStableCursors` | 1470, 5424 | R, O, Q (source/boundary checks) |
| `_trustedSectionStartFor` | 1527 | R, O, Q (source/boundary checks) |
| `canonicalPathDisplayResult` | 1760, 1776 | Q, R |
| `buildCanonicalTextFragment` | 2076, 2077 | Q, R (payload producer) |
| `buildCanonicalTableRowFragment` | 2135, 2136 | Q, R (payload producer) |
| `readerDisplayChunkContainsSourceOffset` | 2243 | Q, R |
| `paginateLegacyForP02` | 2406, 2425 | R, O, Q (source/boundary checks) |
| `paginateCanonical` | 2549 | R, O, Q (source/boundary checks) |
| `logSlowTextMeasure` | 2938 | D |
| `measureTextHeight` | 2959 | R (copy preserves index) |
| `splitChunkByHeight` | 3477 | D |
| `shareLogicalParagraph` | 3576, 3577 | Q, R |
| `mergeChunks` | 3606, 3607, 3612, 3613 | Q, R (payload producer) |
| `_runEngine` | 3723, 4467, 4494, 4523, 4527, 4552, 4607, 4611, 4616 | R, Q, O; D at 3958/4467 |
| `sliceForRange` | 3758, 3768, 3769 | R, O, Q (source/boundary checks) |
| `coalesceSlices` | 3860, 3861 | R, O, Q (source/boundary checks) |
| `descriptorFor` | 3895, 3896, 3911, 3915, 3916 | R, O, Q (source/boundary checks) |
| `reconstructCandidate` | 3947, 3958 | R, Q, O; D at 3958/4467 |
| `_validateCanonicalRequest` | 4868, 4873, 4900 | R, O, Q (source/boundary checks) |
| `_finalizedBoundaryIdentityResolves` | 5133, 5136, 5184, 5216 | R, O, Q (source/boundary checks) |
| `_frontierSourceDescriptorsResolve` | 5323 | R, O, Q (source/boundary checks) |
| `_frontierEndCursor` | 5390, 5391, 5399, 5409 | R, O, Q (source/boundary checks) |
| `_frontierOwnersResolve` | 5443 | R, O, Q (source/boundary checks) |
| `_cursorResolves` | 5464 | R, O, Q (source/boundary checks) |
| `_frontierStartCursor` | 5609, 5620, 5628 | R, O, Q (source/boundary checks) |
| `_sourceSliceWithEvidence` | 5649 | R, O, Q (source/boundary checks) |

### `lib/services/reader_character_match_service.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `buildReaderCharacterMatchPlan` | 127 | Q, O, R |
| `_reconstructDeclarationTexts` | 319 | Q, O, R |
| `_buildLogicalParagraphs` | 558, 570, 600 | Q, O, R |

### `lib/services/reader_source_projection_service.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `readerDisplayIndexForStableLocation` | 104 | Q, R |
| `readerStableLocationForDisplayIndex` | 126 | Q, R |

### `lib/services/segmented_display_cache_service.dart`

| Symbol | Lines | Categories |
| --- | --- | --- |
| `_serializeSegment` | 2387 | P |
| `_deserializeSegment` | 2401 | P |

## Audit method and limitations

Used resolved `BookChunk` element ownership for `index/toJson/fromJson/copyWith/
withSection/effectiveSourceRanges`, BookChunk construction, and every expression
named `sourceOrdinalHint`; supplemented declarations/codecs and indirect
`originalChunkIndex`, bookmark, stable-location and checkpoint consumers by
source inspection. Temporary analyzer script:
`rtk proxy dart --packages=.dart_tool/package_config.json /tmp/nalori_address_inventory.dart`
(exit 0, 321 records); output `/tmp/nalori-address-inventory.json`.
No generated file is a production dependency.

Cross-check commands:

```sh
rtk rg -n "sourceOrdinalHint" lib
rtk rg -n "originalChunkIndex|legacyGlobalChunkIndex" lib
rtk rg -n "'i'|index:" lib/models/book_chunk.dart lib/models/book_list_semantics.dart
rtk rg -n "BookChunk.fromJson|chunk.toJson|card.toJson" lib
```

This is a source audit, not a dynamic claim that every branch executed.
The candidate witness only authenticates a complete parsed-section record
against a previously captured section identity. Strict production lazy admission,
slice/offset validation under the new tuple, exact emitted bytes, checkpoint
discriminator/codec, and bookmark/annotation round trips remain entry work.
