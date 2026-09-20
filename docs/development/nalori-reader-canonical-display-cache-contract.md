# Nalori canonical display-cache segment contract

Status: approved and implemented P06 contract. `CHANGE-20260912-032` completes
P06-002's strict logical codec/admission boundary, `CHANGE-20260912-033`
completes controlled P06-003 memory/disk transport, eviction and regeneration
equivalence, and `CHANGE-20260912-034` completes P06-004 scoped
display-derivative invalidation. `CHANGE-20260913-035` completes P06-005's
controlled evidence-sufficient regeneration, and `CHANGE-20260913-036`
independently audits and strengthens the P06-004/P06-005 trust boundaries.
`CHANGE-20260913-037` completes finite retention, `CHANGE-20260913-038`
completes the isolated v4 physical rollout, and `CHANGE-20260914-039`
corrects the device-exposed startup, write-ordering and restart-evidence
regressions in host controls. The latest ordinary A059 run supersedes those
success claims: P06 remains 7/7 and is `REGRESSED_ON_DEVICE`.
CHANGE-20260919-040 specifies [lazy snapshot handoff](nalori-lazy-snapshot-handoff-design.md)
without implementing it. P04's relevant gate is
`ARCHITECTURAL_CORRECTION_REQUIRED`; P07 remains blocked.
Authority: this document specifies the logical and physical evidence required
before a canonical display-cache segment can be retained, written or reused.

## 1. Scope and verified baseline

This contract covers a bounded derivative of one canonical reader-card sequence. It is deliberately narrower than parsed-source storage, checkpoints, stable locations, reader publication, cache clearing, eviction policy, or migration implementation.

### Verified baseline

- P04 retains 8/8 historical completed tasks but its lazy-input/publication gate is ARCHITECTURAL_CORRECTION_REQUIRED; P05 retains its completed 7/7 evidence.
- CHANGE-20260910-029 established F001-F211, U-01-U-10, P05 161/161, repeated P03 57/57 evidence, unchanged P04 final-gate 3/3, and frozen P02 9/9 controls.
- ReaderCompatibilityClassifier distinguishes exact compatibility, authoritative source/layout/renderer/pagination changes, incomplete evidence, corruption, and unsupported revisions. Its result is advisory: it cannot publish, write, restore, settle, or migrate.
- A whole or segmented legacy display-cache hit is observable, but P04 rejects it with canonicalRegenerationRequired because the record lacks finalized continuation and seam proof. ReaderScreen then regenerates from source.
- No current persistent display-cache representation has P04/P05 authority. P06 is the first phase permitted to give a future persistent display record such authority.

### Scope boundary

Established current behavior is described in sections 2-4. Sections 5-14 are
the approved logical contract; P06-002 implements its strict candidate
codec/admission boundary, P06-003 adds only controlled transports and
candidate-to-P04 evidence, and P06-004 adds exact scoped invalidation only.
Sections 15-19 retain live physical reuse, migration, retention and later-test
ownership.

The following are not cache identity: display/card/window/request indexes, controller state, generation id, access time, LRU position, object identity, raw settings, rounded viewport values, filenames, and a record merely being resident.

## 2. Current cache implementations and authority flow

### Established current behavior

| Path | Current writer and reader | Current authority |
| --- | --- | --- |
| Whole display cache | lib/services/book_cache_service.dart: BookCacheService.cacheDisplayChunks and loadDisplayChunks; called by lib/screens/reader_screen.dart | A gzip JSON derivative keyed by legacy layout strings. It is read and logged, then ReaderScreen rejects it before canonical publication. |
| Segmented disk cache | lib/services/segmented_display_cache_service.dart: writeSegment, loadRange, loadAroundSource, loadManifest | Prepared DisplayRangeResult range storage. It checks legacy manifest/payload fields and an FNV checksum, but does not establish P04 cards, P05 identity, or seams. |
| Memory cache | lib/services/display_section_memory_cache.dart: DisplaySectionMemoryCache.put and get | An LRU of copied DisplayRangeResult maps keyed by cacheKey plus integer SourceChunkRange. It has no serialized or canonical evidence. |
| Progressive display state | lib/services/progressive_display_state.dart: publishCanonical, publishInitial, append/prepend paths | publishCanonical is the P04 validate-before-commit authority. Legacy range assembly is window-local only; cached legacy ranges may not invoke canonical publication. |
| ReaderScreen whole-cache admission | lib/screens/reader_screen.dart: _loadOrRebuildDisplayChunks | A whole-cache hit is inspected, emits reader_display_cache_record_found, then is rejected as canonicalRegenerationRequired and source regeneration continues. |
| ReaderScreen segmented-cache admission | lib/screens/reader_screen.dart: _loadProgressiveSegmentsAroundSource | A center segment may be loaded and logged, but rejectNonCanonicalCachePublication rejects it and returns false. Current loadAroundSource itself selects integer-adjacent neighbors; that is not future canonical joining. |
| Retained prospective paths | lib/screens/reader_screen.dart: _cacheProgressiveDisplayRange and _loadCachedProgressiveDisplayRange | Both are marked unused and retained for P06 integration. They currently write/read memory and legacy segments, then reconstruct mutable request fields. They are not publication authority. |
| Derivative cleanup | lib/services/lazy_reader_cache_cleanup_service.dart: deleteDerivativesForBook and clearAllDerivatives | Deletes whole and segmented derivatives with other reader-owned derivatives. This task neither invokes nor changes it. |

The current flow is therefore:

    legacy memory/disk record -> observable hit -> P04 fail-closed rejection
    -> bounded canonical source regeneration -> ProgressiveDisplayState.publishCanonical

The future flow must preserve the final publication step. A validated cache record can at most be a candidate input to that step; it never replaces the publication transaction.

## 3. Current formats, keys and records

### Current values, declaration, write/read/compare sites

| Value | Declaration | Written or propagated | Read or compared | Audit result |
| --- | --- | --- | --- | --- |
| Whole display-cache format 3 | lib/services/book_cache_service.dart: BookCacheService.displayCacheFormatVersion | _serializeDisplayChunks writes v; ReaderScreen writes it to diagnostics and chapter-layout displaySchema | _deserializeDisplayChunks does not compare v | Remains 3. The absence of a decode-time version check is legacy behavior. |
| Display-layout version v14 | lib/services/book_cache_service.dart: BookCacheService.displayLayoutVersion | displayChunkKey, ReaderScreen DisplayGenerationSignature/layout diagnostics, chapter-layout displaySchema, segmented manifest/payload layout field | Legacy whole-cache key lookup; segmented _isManifestCompatible and _isSegmentPayloadCompatible | Remains v14; it is an old layout string, not F196/F206/F208 identity. |
| Segmented display-cache format 3 | lib/services/segmented_display_cache_service.dart: segmentedDisplayCacheFormatVersion | SegmentedDisplayCacheKey default; _upsertSegmentRecord manifest; _serializeSegment payload | _isManifestCompatible and _isSegmentPayloadCompatible | Remains 3. |
| Pagination algorithm nalori_cards_v16_lists | lib/models/reader_checkpoint.dart: readerPaginationAlgorithmVersion | ReaderCard/ReaderCheckpoint defaults; checkpoint construction; ReaderCardPaginator canonical requests and continuations; ReaderScreen canonical sessions | ReaderCheckpointCoordinator.resolveRestore; ReaderCardPaginator continuation/request validation | Remains nalori_cards_v16_lists; P06 uses F204 rather than a free-form string. |
| Checkpoint record format 1 | lib/models/reader_checkpoint.dart: ReaderCheckpoint.currentFormatVersion | ReaderCheckpoint creation and canonical payload formatVersion | ReaderCheckpoint.fromJson rejects a version other than currentFormatVersion | Remains 1; a checkpoint is not a display segment. |
| Checkpoint-store schema 1 | lib/services/reader_checkpoint_store.dart: ReaderCheckpointStore.schemaVersion | OpenDatabaseOptions version on store open | SQLite open/migration schema selection | Remains 1; it is outside this display-cache contract. |
| Stable-location version 2 | lib/models/stable_book_location.dart: StableBookLocation.currentVersion | StableBookLocation constructor default and JSON v | StableBookLocation.fromJson reads v and defaults a missing value to currentVersion | Remains 2; it is a source-location format, not a segment format. |

No value in this table changes in P06-001. A future logical semantic revision is an evidence tag, not an assignment of a deployed file-format number.

### Existing paths, keys, and payloads

| Representation | Physical path / filename | Current key or lookup | Current record/payload |
| --- | --- | --- | --- |
| Whole display | application documents/book_cache, test root directly; sanitized key plus .json.gz; display_manifest.json | BookCacheService.displayChunkKey: delimiter concatenation containing book id, v14, raw settings, fixed decimals, truncated dimensions, rounded safe areas | gzip JSON v, dc BookChunk list, dto display-to-original lists, otd original-to-display map; manifest _CacheEntry. |
| Segmented display | application documents/book_cache/display_segments/safe(cacheKey)/manifest.json and segment_start_end.json.gz | SegmentedDisplayCacheKey contains bookId, cacheKey, DisplayGenerationSignature, sourceChunkCount, parserVersion, format default | Manifest plus DisplaySegmentRecord; gzip payload carries legacy signature strings, integer range, BookChunk list and maps. |
| Section-scoped segment | same segmented root under a cacheKey with lazy_spine_checksum suffix | ReaderScreen _cacheCompleteSectionScopedDisplayRanges rebases to a local SourceChunkRange and cache key | A legacy segment whose source/display indexes were deliberately shifted to local section coordinates. |
| Memory display section | process memory only | DisplaySectionMemoryCacheKey(cacheKey, SourceChunkRange(start,end)) | DisplaySectionMemoryCacheEntry with copied BookChunks/maps and estimatedBytes. |
| Cached range result | transient process object | request SourceChunkRange, direction, generation, reason, target index | DisplayRangeResult / PreparedDisplayRange cards and maps; it is not a durable cache record. |
| Chapter layout record | display_segments/chapter_layout_records/safe(layoutKey).json | ChapterCardLayoutKey includes chapter identity, legacy display schema and legacy settings/viewport strings | A chapter-layout derivative, not a canonical display-card segment. |

## 4. Current field-level evidence inventory

The table is an audit of current fields, not approval of their use. Stable means stable only within the stated current representation, not canonical authority.

| Field | Writer | Reader | Current authority | Stable or transient | Canonical evidence supplied | Missing evidence | P06 owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CachedDisplayChunks.displayChunks | BookCacheService._serializeDisplayChunks | _deserializeDisplayChunks; ReaderScreen diagnostic only | Derivative payload | Transient cards serialized | Visible BookChunk payload | Finalized-card identity, exact slices, P05 physical layout, seams, continuation | P06-002/005 |
| CachedDisplayChunks.displayToOriginal | same | same | Display-to-source projection | Mutable display indexes | Integer source membership | Stable owners, offsets/rows, source snapshot, ordering proof | P06-002/005 |
| CachedDisplayChunks.originalToDisplay | same | same | Reverse projection | Mutable display indexes | Integer lookup | No card identity, no source ownership, no seam | P06-002/005 |
| Whole payload v | _serializeDisplayChunks | _deserializeDisplayChunks ignores it | Format label only | Stable literal | Value 3 | Decode-time comparison and canonical revision | P06-002/004 |
| Whole display manifest key | cacheDisplayChunks | loadDisplayChunks, deleteDisplayChunks, eviction | Lookup/LRU | Raw legacy key | Book scope mixed into string | Publication/source/P04/P05 evidence | P06-002/004 |
| _CacheEntry.fileSizeBytes | cacheDisplayChunks | eviction | Retention | Transient metadata | File size | Integrity, ownership, bounds proof | P06-006 |
| _CacheEntry.cachedAtMs / lastAccessedMs | cacheDisplayChunks/loadDisplayChunks | eviction | Retention only | Transient time | LRU ordering | All canonical evidence; forbidden from identity | P06-006 |
| SegmentedDisplayCacheKey.bookId | ReaderScreen _segmentedDisplayCacheKey / callers | manifest compatibility | Book lookup scope | Raw scope | Cross-book separation attempt | Opaque scoped digest, publication identity | P06-002 |
| SegmentedDisplayCacheKey.cacheKey | ReaderScreen legacy key construction | directory/manifest/payload compatibility | Lookup | Delimited legacy string | Legacy settings/layout discriminator | F196/F202/F204/F206/F207/F208 | P06-002/004 |
| SegmentedDisplayCacheKey.signature | ReaderScreen generation construction | manifest/payload compatibility | Operation compatibility | Runtime value | Parsed/layout/settings/viewport strings | Canonical bytes and source/pagination proof | P06-002 |
| SegmentedDisplayCacheKey.sourceChunkCount | callers | manifest compatibility | Range shape check | Mutable window/section count | Integer count | Stable snapshot source cardinality and interval owners | P06-002 |
| SegmentedDisplayCacheKey.displayCacheVersion / parserVersion | constructor defaults/callers | manifest compatibility | Legacy format/parser check | Stable literal/current input | Version values | P04 source snapshot and P05 compatibility | P06-002/004 |
| Manifest.version | _upsertSegmentRecord | _isManifestCompatible | Format label | Stable literal | Segmented value 3 | Canonical record semantic revision | P06-004 |
| Manifest.bookId / cacheKey | _upsertSegmentRecord | _isManifestCompatible | Lookup scope | Raw/delimited | Book/cache routing | Opaque scope, all fingerprint evidence | P06-002 |
| Manifest.parsedContentVersion / parserVersion | _upsertSegmentRecord | _isManifestCompatible | Legacy parse check | Stable literal/current input | Parser version number | F202 source compatibility and snapshot digest | P06-002 |
| Manifest.displayLayoutVersion | _upsertSegmentRecord | _isManifestCompatible | Legacy layout check | Old string | v14 | F196/F206/F208 and resolved font evidence | P06-002 |
| Manifest.settingsSignature / viewportSignature | _upsertSegmentRecord | _isManifestCompatible / layout identity | Legacy layout check | Raw strings | Some settings and geometry | Exact binary identity; raw settings, rounded dimensions and safe-area loss forbidden | P06-002 |
| Manifest.sourceChunkCount / complete | _upsertSegmentRecord | _isCompleteCoverage | Integer coverage claim | Window-local | Adjacent integer coverage | Card/seam/continuation proof; complete section is insufficient | P06-002 |
| Manifest.createdAtMs / updatedAtMs | _upsertSegmentRecord | diagnostics/retention | Metadata | Transient time | None | Canonical identity; forbidden from key | P06-006 |
| DisplaySegmentRecord.sourceStart / sourceEndExclusive | writeSegment | loadRange/loadAroundSource/_isCompleteCoverage | Integer range routing | Mutable source-window index | Apparent half-open range | Stable cursor interval and source owners | P06-002 |
| DisplaySegmentRecord.actualSourceStart / actualSourceEndExclusive | writeSegment | record/payload checks | Duplicate integer routing | Mutable source-window index | Same numeric bounds | Stable interval; section rebasing invalidates global meaning | P06-002 |
| DisplaySegmentRecord.fileName | writeSegment | _segmentFile | Physical location | Transient storage detail | Filename range hint | Digest-only name and logical identity | P06-004 |
| DisplaySegmentRecord.displayChunkCount / map counts | writeSegment | manifest/range validation | Shape diagnostic | Mutable display cardinality | Counts | Ordered canonical cards and exact slices | P06-002 |
| DisplaySegmentRecord.checksum | writeSegment FNV over compressed bytes | loadSegment | Corruption detection | Stable bytes under legacy encoding | 63-bit FNV compressed payload check | SHA-256, canonical coverage declaration, manifest binding | P06-002/007 |
| DisplaySegmentRecord.generationId | writeSegment | diagnostics/stale write checks | Write race hint | Runtime generation | Operation association | Canonical identity; must be excluded | P06-002/007 |
| DisplaySegmentRecord created/updated/access times, status, fileSize | write/touch/eviction | retention and load validation | Retention/ready flag | Transient metadata | File state | Seams, continuation, source/layout identity | P06-006/007 |
| Segment payload bookId/cacheKey | _serializeSegment | _deserializeSegment/_isSegmentPayloadCompatible | Legacy scope/key check | Raw legacy fields | Scope/legacy key equality | Opaque scope and canonical key bytes | P06-002 |
| Segment payload parsedContentVersion/parserVersion | _serializeSegment | only parsedContentVersion survives _SerializedDisplaySegment payload check; parserVersion is manifest-only | Partial parser check | Legacy current input | Parser integer | Exact F202 and source snapshot linkage | P06-002 |
| Segment payload displayLayoutVersion/settingsSignature/viewportSignature | _serializeSegment | _isSegmentPayloadCompatible | Legacy layout comparison | Old/raw string | Legacy matching | F196/F206/F208; no raw or rounded identity | P06-002 |
| Segment payload sourceChunkCount/sourceStart/end/actual start/end | _serializeSegment | source count/actual fields are discarded by decoded DTO; start/end compared | Integer interval claim | Mutable local indexes | Numeric range | Stable cursors and exact source interval | P06-002 |
| Segment payload generationId/status | _serializeSegment | discarded by decoded DTO | Diagnostic only | Runtime/transient | None | Must not enter logical record | P06-002 |
| Segment payload displayChunks/displayToOriginal/originalToDisplay | _serializeSegment | _deserializeSegment/CachedDisplaySegment.toResult | Derivative cards/maps | Display indices mutable | Bounded payload and integer map | P04 finalized cards/slices/seams and P05 card layout | P06-002/005 |
| DisplaySectionMemoryCacheKey.cacheKey | DisplaySectionMemoryCache.put | get/pinPreparedRanges | Memory lookup | Raw legacy key | Legacy routing | Canonical key digest/components | P06-002 |
| DisplaySectionMemoryCacheKey.sourceRange | put/pin | get/toResult | Memory lookup/pin | Mutable source window | Integer range | Stable source interval and seam proof | P06-002/006 |
| Memory entry displayChunks/maps | put | get/toResult | In-process derivative | Runtime data | Cards and projections | Same evidence required on disk; no identity/seams | P06-002 |
| Memory entry estimatedBytes | put | eviction diagnostics | Retention | Approximation | Approximate byte estimate | Strict encoded/decoded bounds, checksum | P06-006 |
| Memory entry LRU order and pins | get/put/pinPreparedRanges | eviction | Retention only | Runtime object/map order | Residency preference | Canonical membership; forbidden from identity | P06-006 |
| DisplayRangeRequest.direction/reason | ReaderScreen generators/cache reconstruction | range prep / toResult | Scheduling diagnostic | Mutable operation | None | Must never key or validate canonical record | P06-002 |
| DisplayRangeRequest.generationId/targetOriginalIndex | ReaderScreen | stale/preparation/range logic | Operation freshness/target hint | Runtime mutable indexes | Stale-operation context | Must never key, migrate, or prove card | P06-002/007 |
| DisplayRangeRequest.sourceRange | callers | legacy assembly/cache lookup | Window range | Mutable local index | Apparent interval | Stable source cursors and owners | P06-002 |
| DisplayRangeResult display maps/cards | legacy paginator/cache | legacy state assembly | Prepared derivative | Window-local | Visible payload and integer projections | P04/P05 evidence, seams, continuation | P06-002/005 |
| ProgressiveDisplayState ranges/maps/display chunks | legacy publishInitial/append/prepend | ReaderScreen/current display | Current published window state | Display indexes transient | Current window sequence | Only publishCanonical has card/continuation validation | P06-002 |
| ProgressiveDisplayState canonicalCards/accepted continuation/source snapshot | P04 canonical transactions | publishCanonical/session operations | P04 live canonical state | Stable within pinned session | P04 cards, source snapshot and continuation | Persistent segment header/F196/F206/F208/record checksum | P06-002/005 |
| ReaderScreen display signature/settings/viewport strings | ReaderScreen rebuild/signature code | DisplayGenerationSignature and caches | Legacy generation matching | Raw strings; viewport string | Current inputs only | Resolved F001-F211 identity; delimiter strings forbidden | P06-002 |
| ReaderScreen section-scoped shifted indexes | _cacheCompleteSectionScopedDisplayRanges / _shiftDisplayChunkSourceIndexes | legacy segment read | Local cache layout | Explicitly rebased indexes | Local section packing | Global source identity and predecessor/successor proof | P06-002/005 |
| ChapterCardLayoutKey chapterIdentity/displaySchema/settings/viewport | ReaderScreen _chapterLayoutDescriptor | chapter layout cache | Chapter layout derivative | Includes section/index and legacy strings | Presentation layout hint | Ordered canonical cards/continuation; separate record family | P06-004 |

The audit explicitly finds display indexes, card ordinals, source-window indexes, and section indexes without stable source identity in current cache routing. It also finds adjacency inferred from integer ranges in loadAroundSource and _isCompleteCoverage; raw setting strings and rounded/integer viewport and safe-area values in displayChunkKey; old layout/pagination strings; timestamps and LRU state; and runtime identity checks such as identical(token.signature, signature). None is eligible as a future canonical segment key component or seam proof.

### Current encoding, corruption, write, and retention behavior

Whole records and segment payloads are gzip JSON. Whole records have no checksum. Segments use FNV-1a reduced to a nonnegative 63-bit value over compressed bytes; the manifest has no checksum. Decoding gzip/JSON has no logical decoded-byte limit before allocation.

Segment writes use a temporary file, decode it for a range check, delete an existing final file, then rename. Manifest writes similarly replace through a temporary file after deleting the prior target. Whole-cache writes and display-manifest writes are direct. These are current implementation facts, not sufficient future atomicity guarantees.

Whole-cache decode failure deletes the payload and returns a miss. Segment failures remove the segment record/payload where the path reaches _removeSegmentRecord; malformed manifests can become a miss. Retention uses whole-cache 20 MiB / 5 MiB per-file limits, segmented 48 MiB policy / 3 MiB per-file limit, memory 8 MiB approximate limit, timestamps, active/recent integer ranges, and pins. These are legacy retention controls, not canonical identity.

## 5. Canonical segment key

### Approved future contract

CanonicalDisplaySegmentKey has 13 encoded fields and one derived digest, for a total of 14 named fields:

| # | Field | Meaning and rule |
| ---: | --- | --- |
| 1 | recordKind | Fixed canonical_display_segment value. |
| 2 | semanticRevision | Logical contract revision canonical_display_segment_contract_v1. It is not a deployed disk-format version and does not alter current value 3. |
| 3 | bookStorageScopeDigest | SHA-256 of the canonical isolated storage/book scope. It prevents cross-book lookup but is not physical layout identity. |
| 4 | publicationFingerprint | Exact P04 publication identity. |
| 5 | sourceCompatibilityFingerprint | F202. |
| 6 | layoutMetricsFingerprint | F196. |
| 7 | rendererLayoutFingerprint | F206. |
| 8 | paginationAlgorithmFingerprint | F204. |
| 9 | compatibilityClassifierRevision | F207 revision value. |
| 10 | readerCompatibilityFingerprint | F208. |
| 11 | stableStartCursor | Canonical source cursor at the inclusive interval start. |
| 12 | stableEndCursor | Canonical source cursor at the exclusive interval end, or logical-end sentinel. |
| 13 | boundaryRole | One of bookStartAnchored, continuationAnchored, interior, or logicalEndAnchored. It identifies required proof shape, never grants authority by itself. |
| 14 | keyDigest | Derived lower-case SHA-256 over exact canonical key bytes; never supplied independently. |

The key bytes use the strict canonical binary field encoding already approved for P05-type evidence: fixed ascending field tags, explicit type/length, canonical unsigned integer encoding, exact finite binary64 where a number is permitted, normalized lower-case fixed-length digest bytes, and no duplicate, unknown, reordered, or trailing field. Cursor fields use CanonicalSourceCursor canonical encoding, including explicit book-start and logical-end sentinel forms. Digest fields are binary digests, not strings concatenated with delimiters.

Forbidden key inputs include a display index, card ordinal, source ordinal hint by itself, SourceChunkRange integer index, segment ordinal, request direction/reason/target, generation id, filename, cacheKey, settingsSignature, viewportSignature, raw font-family/size strings, rounded screen/safe-area values, timestamps, LRU position, pins, and runtime object identity. A segment ordinal never substitutes for a stable half-open interval. F208 equality alone is not a key sufficiency or canonical-membership proof.

### Lookup, filenames, and strict validation

The manifest lookup key and on-disk filename use keyDigest only, for example seg-sha256-<digest>.cseg. The storage directory may first be isolated by bookStorageScopeDigest. Raw book ids, publication ids, titles, legacy cache keys, source indexes, and settings do not appear in filenames.

Manifest lookup may use keyDigest to locate a candidate only. Strict validation recomputes all 13 encoded components from the record and current source/layout inputs, recomputes keyDigest, and compares every component. The record repeats its compatibility fields so a swapped manifest index cannot change meaning. Equal digests/key bytes do not by themselves prove a card, seam, continuation, or publication.

## 6. Canonical segment record

### Approved future logical record

CanonicalDisplaySegmentRecord has 32 top-level fields. It is a bounded immutable derivative. It has no access time, creation time, display index, card ordinal, generation id, LRU state, pin state, controller state, or raw settings field.

| # | Field | Exact meaning |
| ---: | --- | --- |
| 1 | recordKind | Must equal the key record kind. |
| 2 | semanticRevision | Must be supported and equal the key revision. |
| 3 | canonicalKeyBytes | Exact encoded 13-component key input, excluding derived digest. |
| 4 | keyDigest | SHA-256 of canonicalKeyBytes. |
| 5 | bookStorageScopeDigest | Repeated key component, independently compared. |
| 6 | publicationFingerprint | Repeated P04 component. |
| 7 | sourceCompatibilityFingerprint | F202. |
| 8 | layoutMetricsFingerprint | F196. |
| 9 | rendererLayoutFingerprint | F206. |
| 10 | paginationAlgorithmFingerprint | F204. |
| 11 | compatibilityClassifierRevision | F207 revision. |
| 12 | readerCompatibilityFingerprint | F208, recomputed from F196/F202/F204/F206/F207. |
| 13 | sourceSnapshotLink | Exact P04 source snapshot digest, source revision, parser/source-schema identity, publication linkage, and stable-source cardinality. |
| 14 | encodingMarker | Supported canonical record encoding marker. |
| 15 | compressionMarker | Supported compression marker; compression is transport, not identity. |
| 16 | declaredTopLevelFieldCount | Must be exactly 32. |
| 17 | declaredCardCount | Exact count of orderedFinalizedCards. |
| 18 | declaredSourceSliceCount | Sum of every card source-slice count. |
| 19 | declaredBlockLayoutCount | Sum of every card block-layout count. |
| 20 | declaredEncodedByteCount | Exact compressed/container bytes, checked before read/allocation. |
| 21 | declaredDecodedByteCount | Exact decoded canonical bytes, checked before decompression/allocation. |
| 22 | stableStartCursor | Inclusive source boundary. |
| 23 | stableEndCursor | Exclusive source boundary or logical-end sentinel. |
| 24 | exactHalfOpenSourceInterval | The source-snapshot-linked [start,end) interval descriptor, including ordered stable source owners. |
| 25 | orderedFinalizedCards | Bounded ordered CanonicalDisplaySegmentCardRecord array. |
| 26 | leftBoundaryProof | Book-start or predecessor/restart proof for the first card. |
| 27 | rightBoundaryProof | Logical-end or successor/frontier/continuation proof for the final card. |
| 28 | continuationEvidence | Strict P04 continuation encoding and resume evidence after this segment. |
| 29 | manifestBinding | Non-authoritative index receipt: key digest, record digest, declared segment/card/source/byte totals, and manifest revision. It permits bounded lookup/accounting but never publication. |
| 30 | checksumAlgorithm | Fixed sha256. |
| 31 | checksumDigest | SHA-256 of the exact coverage defined in section 11. |
| 32 | checksumCoverageRevision | Fixed canonical_display_segment_checksum_v1 declaration. |

Every required top-level field is present exactly once. Count fields and nested count fields must match before materializing variable-length collections. The sourceSnapshotLink is evidence that slices remain reconstructible from the pinned source snapshot; it is not a source-text substitute.

### Ordered finalized card record

Each CanonicalDisplaySegmentCardRecord has 11 fields:

| # | Field | Exact meaning |
| ---: | --- | --- |
| 1 | physicalCardSignature | Recomputed canonical ReaderCardIdentity/signature for this finalized card. |
| 2 | physicalLayoutCompositeFingerprint | F210. |
| 3 | physicalCardIdentityComponents | F211, including its required F197/F202/F204/F210 and P04 source-slice components. |
| 4 | cardStartCursor | Exact canonical start cursor. |
| 5 | cardEndCursor | Exact canonical exclusive end cursor. |
| 6 | orderedStableSourceSlices | Ordered P04 slices with stable owner/source/section/spine identity, structural owner and role, split/fragment/list/rich/publisher evidence, and exact UTF-16 or canonical table-row intervals. |
| 7 | orderedBlockLayoutFingerprints | Ordered F209 block-layout fingerprints. |
| 8 | structuralCardPayload | Bounded visible/render derivative required to reconstruct the card, including the resolved block/card payload needed for display. |
| 9 | structuralCardPayloadDigest | SHA-256 of the canonical derivative payload. |
| 10 | declaredSourceSliceCount | Exact source-slice array count. |
| 11 | declaredBlockLayoutCount | Exact block-layout array count. |

The payload is derivative evidence. Validation rederives the card identity, F210/F211, ordered source slices, owner/role, intervals, block layout fingerprints, and visible payload from the pinned source snapshot and accepted P04/P05 contract. Stored card content cannot replace source authority. It may contain bounded card text/render data, but a segment must never be a whole-book display copy.

## 7. Stable source interval and ordered-card rules

The record interval is a stable half-open interval [stableStartCursor, stableEndCursor). The start is inclusive and the end is exclusive. Each endpoint identifies a position in the linked canonical source snapshot; it is not a mutable local source index. A logical-end sentinel is a valid end. A book-start sentinel is a valid beginning only where the record has left book-start authority.

Cards are ordered in final canonical sequence. For every card:

1. cardStartCursor is less than cardEndCursor in the source snapshot order;
2. slices are strictly ordered and collectively match the card cursor interval;
3. UTF-16 intervals are exact [start,end); tables retain both authored UTF-16 ownership and canonical row intervals;
4. structural owner, role, spine/section identity, fragment/split/list/rich/publisher descriptors match pinned source;
5. F209 ordering, F210, F211, physical signature, and payload digest recompute exactly;
6. no slice overlaps, reverses, duplicates, omits, or crosses a source ownership boundary;
7. no card obtains identity from its local ordinal or display index.

Internal adjacent cards must satisfy exact cursor seam equality: previous.cardEndCursor equals next.cardStartCursor. In addition, the source-slice boundary, reconstructed ownership, card identity chain, and P04 continuation/card-finalization evidence must agree. Integer endpoints that look adjacent are never a substitute.

## 8. Predecessor/successor seam evidence

### Left boundary proof

leftBoundaryProof has a kind and exact evidence:

- bookStart: authoritative CanonicalSourceCursor book-start sentinel, first-card start equality, source snapshot/publication equality, and no unproved predecessor;
- predecessor: predecessor finalized-card physical signature/F211, predecessor end cursor, this first-card start cursor, exact seam equality, and the accepted predecessor continuation digest;
- restart: accepted restart/checkpoint linkage, parent/chain digest, prior finalized boundary, and enough P04 source-snapshot/continuation evidence to reconstruct the same first card before it can anchor an isolated record.

An isolated loaded record does not publish merely because it claims predecessor. It must be anchored by a validated book-start proof, an already accepted canonical predecessor/current card, or validated restart/continuation evidence that reconstructs the same sequence.

### Right boundary proof

rightBoundaryProof has a kind and exact evidence:

- logicalEnd: authoritative logical-end sentinel, final-card end equality, terminal continuation, and no successor;
- successor: final-card signature/F211/end cursor, successor first-card signature/start cursor, exact seam equality, and compatible successor record/continuation identity;
- frontier: final-card boundary, accepted previous-finalized boundary, continuation digest, frontier start/end descriptors, next source cursor, and exact equality governed by the continuation rules below.

For an append between a cached and live card, the cached final card and live first finalized card must pass every identity/source/layout check and exact cursor seam. For a prepend between regenerated predecessors and a cached committed card, the regenerated final predecessor and cached first card must pass the same check; the cached right boundary must also reproduce the accepted committed card evidence. The cached record never relaxes P04 prepend proof.

For two separately loaded segments, joining is permitted only after both records are exact canonical compatible and their shared predecessor/successor card identities, cursor seam, source snapshot, compatibility components, continuation parent/chain relation, and boundary kind agree. Adjacent integer ranges, same section, matching filename ranges, or manifest complete coverage are never enough.

## 9. Continuation/frontier persistence semantics

continuationEvidence persists a strict CanonicalPaginationContinuation-compatible evidence object. It contains:

1. strict canonical continuation encoding;
2. SHA-256 continuation digest;
3. continuation key and contract kind;
4. source snapshot/publication/parser/source-revision compatibility;
5. start source cursor;
6. nextSourceCursor as next-unconsumed input evidence;
7. previousFinalizedBoundary as publication seam authority;
8. ordered provisional frontier candidates reconstructed from stable source slices;
9. parent digest and chain ordinal;
10. checkpoint reason;
11. source/card work counters and bounded restart/checkpoint evidence;
12. terminal flag.

No continuation identity may copy source text, display indexes, card ordinals, request fields, controller state, runtime object identity, cache access metadata, or a raw settings string. Frontier candidates retain only the P04 reconstructible stable slice descriptors and reconstructed card digest/identity evidence. Source text remains in the pinned source snapshot; record metadata validates it rather than replacing it.

The P04 seam distinction is mandatory:

- the publication seam comes from previousFinalizedBoundary and finalized/frontier boundary evidence;
- nextSourceCursor identifies unconsumed input;
- if frontier is nonempty, nextSourceCursor must not replace the publication seam.

For an empty frontier, previousFinalizedBoundary.endCursor must equal nextSourceCursor. For a nonempty frontier, previousFinalizedBoundary.endCursor must equal the frontier start, ordered frontier end must equal nextSourceCursor, and the final cached card/right proof must match the accepted previous-finalized boundary. A terminal continuation has empty frontier and logical-end next cursor. Parent/chain evidence must bound the continuation chain; an unbounded chain is rejected.

## 10. Compatibility and typed outcomes

P06-002 exposes the following 16 logical validation outcomes. An action marked
conditional is permitted only after the stated full validation and P04
transaction; it is not a direct cache authority.

| Outcome | Return cards | Join segment | Publish | Seed canonical pagination | Update memory cache | Rewrite disk cache | Later invalidation/migration |
| --- | --- | --- | --- | --- | --- | --- | --- |
| exactCanonicalCompatible | Candidate only | Conditional exact seam proof | Conditional P04 transaction and anchor | Conditional accepted continuation/source reconstruction | Conditional validated derivative | No implicit rewrite | No |
| safeMissAbsent | No | No | No | No | No | No | No |
| safeMissIncompleteCanonicalEvidence | No | No | No | No | No | No | P06-004/005 may classify/regenerate |
| safeMissIncompatibleSourceOrParser | No | No | No | No | No | No | P06-004 scoped invalidation; P06-005 only if proof exists |
| safeMissChangedLayout | No | No | No | No | No | No | P06-004 scoped invalidation |
| safeMissChangedRendererRules | No | No | No | No | No | No | P06-004 scoped invalidation |
| safeMissChangedPaginationAlgorithm | No | No | No | No | No | No | P06-004 scoped invalidation |
| safeMissUnsupportedRevision | No | No | No | No | No | No | P06-004/005 policy handling |
| rejectedCorruptChecksumOrEncoding | No | No | No | No | No | No | P06-004/007 quarantine/removal decision |
| rejectedBoundaryMismatch | No | No | No | No | No | No | P06-004 safe miss/regeneration decision |
| rejectedContinuationMismatch | No | No | No | No | No | No | P06-004 safe miss/regeneration decision |
| rejectedCardIdentityOrContentMismatch | No | No | No | No | No | No | P06-004 safe miss/regeneration decision |
| rejectedStaleGeneration | No | No | No | No | No | No | P06-007 may discard stale candidate |
| rejectedCrossBookScope | No | No | No | No | No | No | P06-004 may isolate orphaned derivative; never cross-delete |
| rejectedCompatibilityEvidenceCorrupt | No | No | No | No | No | No | P06-004/007 corruption path |
| regenerationRequired | No cached cards | No | No | No cached continuation | No | No | Bounded canonical source regeneration; later invalidation/migration only by owning tasks |

The classifier may help distinguish source/layout/renderer/pagination outcomes, but F208 equality is insufficient. exactCanonicalCompatible requires successful strict decode, field/count/integrity checks, F195-F208 validation/recomputation, source snapshot validation, every card/slice/payload recomputation, both boundary proofs, continuation validation, and contextual anchor/join proof.

## 11. Integrity and canonical encoding

The canonical record checksum algorithm is SHA-256. checksumDigest covers the exact canonical decoded record bytes in ascending tag order with field 31 checksumDigest excluded. It includes all other fields, nested field tags/counts, canonical key bytes, source snapshot link, cursor forms, cards/slices/payload digests, boundary proofs, continuation bytes/digest, and manifest binding. compression bytes are covered separately by declaredEncodedByteCount and container checksum validation when a container format is chosen; compression never changes the logical record digest.

Encoding rules:

- every field has one known tag, explicit presence, canonical type and overflow-safe length;
- all numbers use strict canonical integer encoding or approved finite binary64 encoding; negative zero, NaN, infinity, duplicate, nonminimal, overflow, malformed length, unknown, reordered, and trailing fields are rejected;
- arrays preserve declared order; semantic maps/sets use the P05 approved canonical sort;
- declared top-level/nested counts and encoded/decoded byte counts are checked before allocation;
- decompression occurs only after compressed-size checks and is bounded by declared decoded length and a P06-006 limit;
- unsupported encoding/compression markers are safeMissUnsupportedRevision, malformed encoding/checksum is rejectedCorruptChecksumOrEncoding;
- a manifest is an index/accounting object. Its record digest binding must match, but it is never a substitute for the record checksum or proof.

## 12. Memory/disk equivalence

Memory and disk use the same CanonicalDisplaySegmentKey, CanonicalDisplaySegmentRecord, decoder, compatibility classification, checksum verifier, card verifier, boundary verifier, continuation verifier, and publication transaction inputs. A memory representation may retain decoded objects only after validating the same canonical logical bytes/fields. It never gains authority because serialization was skipped.

Manifest lookup, disk file read, decompression, and memory lookup must not bypass compatibility classification, checksum verification, source/card verification, seam/continuation verification, generation/session freshness, or P04 publication validation. Memory update is a derivative residency operation after validation; it does not create a new accepted continuation.

Access time, LRU position, cache pressure, pinning, current/adjacent residency, file size, and manifest totals control retention only. They are separate metadata and cannot alter canonical identity or acceptance.

### P06-002 accepted logical admission boundary

The implemented boundary in
`lib/models/canonical_display_segment.dart` contains the immutable
`CanonicalDisplaySegmentKey`, record, card, source-interval, boundary,
continuation and manifest-binding models plus `CanonicalDisplaySegmentCodec`.
The key has the approved 13 encoded fields and derived SHA-256 digest; the
record has 32 tagged top-level fields and every card has 11 tagged fields.
The codec accepts an explicit finite `CanonicalDisplaySegmentCodecLimits`
object and rejects noncanonical tags, order, types, lengths, counts,
checksum/manifest binding and unsupported encoding markers before it exposes a
record.

`lib/services/canonical_display_segment_admission.dart` is the one shared
memory/disk validator. Disk candidates decode first; memory records first
encode then decode through the same logical bytes, so neither route bypasses
checksum, `ReaderCompatibilityClassifier`, pinned-snapshot/card/slice,
boundary, frontier or continuation checks. It returns exactly the 16 outcomes
in section 10. An exact result exposes only an immutable candidate: it grants
no cards, join, publication, cache-write, checkpoint or settlement authority.
Future publication remains exclusively P04's
`ProgressiveDisplayState.publishCanonical` transaction. P06-003 extends the
exact outcome with immutable, already revalidated finalized cards and the
accepted continuation solely as typed inputs to that transaction; residence,
decode or admission still grants no direct authority.

The `ReaderScreen` wiring sends every currently reachable legacy whole, segmented and
retained section-memory/section-segment path through the shared
`legacySafeMiss` boundary before continuing its unchanged
`canonicalRegenerationRequired`/bounded-regeneration behavior. Those old
records are not decoded as canonical, migrated, deleted, rewritten or joined.
No new canonical record is written to production disk and no ReaderScreen
warm reuse is enabled.

### P06-003 controlled transport and publication boundary

`CanonicalDisplaySegmentRecordBuilder` is the pure construction owner. It
accepts only pinned source, exact P05 compatibility, finalized P04 cards,
accepted continuation and book-start/restart boundary proof; it derives no
authority from display indexes, integer adjacency, filenames or generation
ids. Records are built only after successful P04 publication in the production
harness path.

`CanonicalDisplaySegmentMemoryTransport` and
`CanonicalDisplaySegmentControlledDiskStore` carry the same logical record
bytes. The disk store requires an explicit caller-owned temporary root and has
no default application path, manifest, version constant or ReaderScreen
connection. Every retrieved representation follows lookup → shared
decode/admission → contextual book-start/predecessor/restart anchoring →
immutable exact candidate → `publishCanonical` → atomic display commit.
Removing either transport entry cannot mutate an accepted display or its
source/checkpoint authority; an absent or rejected candidate instead follows
the same bounded source-generation and P04 publication path.

## 13. Existing-record migratability matrix

| Existing type | Stable publication/source identity | Final P05 identity | Final P04 identity/cards/slices | Boundary/continuation | Strict checksum | Bounded segment ownership | Classification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Whole CachedDisplayChunks gzip v3 plus display_manifest | No; raw key/book routing only | No; v14/raw settings only | No; BookChunks/maps without canonical cards/slices | No | No | No; may contain whole display | Nonmigratable safe miss |
| SegmentedDisplayCacheManifest v3 | Book id/parser/count only | No; legacy layout/settings/viewport strings | No | No; integer coverage only | No manifest checksum | Integer range/file only | Nonmigratable safe miss |
| DisplaySegmentRecord plus gzip segment v3 | Raw book/key/parser only | No | No; BookChunk/maps and local indexes | No; integer adjacency only | Legacy FNV only | File size/range only; section-rebased records invalidate global ownership | Nonmigratable safe miss |
| DisplaySectionMemoryCacheEntry | Legacy key/range only | No | No | No | No | Approximate bytes only | Nonmigratable safe miss |
| DisplayRangeResult / PreparedDisplayRange / raw card list/maps | May be a process-local range hint | No | No persistent canonical evidence | No | No | No | Useful only as a nonauthoritative lookup hint; never migrate/publish |
| ChapterCardLayout record | Chapter/presentation hint only | Partial legacy layout input | No canonical card sequence | No | Existing record-specific integrity only | Chapter bounded, not display segment ownership | Useful only as a nonauthoritative lookup hint |
| P04 live CanonicalPaginationContinuation | Exact P04 snapshot/key evidence | Does not itself carry all final P05 header evidence | Frontier/boundary only; no ordered segment card payload | Yes for its own chain | SHA-256 continuation digest | Bounded continuation, not a segment | Structurally migratable without guessing only as continuationEvidence inside a newly built, live validated record; not a standalone disk migration |
| P04 live CanonicalFinalizedReaderCard plus accepted state/source snapshot and P05 resolved layout | Yes within accepted live transaction | Yes when current F196/F206/F208/F210/F211 are supplied | Yes for an accepted card/slices | Only together with accepted continuation/boundary | Constituent identities/digests | Must be partitioned under future bounds | Structurally migratable without guessing only to create a new record in the same validated live transaction; not legacy disk reuse |
| ReaderCheckpoint / StableBookLocation | Stable recovery hint | Checkpoint layout/pagination fields, not final F196-F208 segment header | Optional card signature/location, not ordered segment cards/slices | No segment continuation | Checkpoint has its own checksum | No segment ownership | Useful only as a nonauthoritative recovery hint |
| Any malformed, duplicate, truncated, unknown-revision, checksum-failing current record | Indeterminate | Indeterminate | Indeterminate | Indeterminate | Failed/unsupported | Indeterminate | Corrupt/unsupported when malformed |

DISC-002 is answered for current display-cache records: no existing persistent whole, segmented, or memory display record can prove the complete canonical contract. P06-004 owns scoped safe-miss/invalidation and P06-005 owns any future migration decision. A section-local result is not canonical merely because it covers every local source chunk: it lacks predecessor/successor packing proof and may have rebased indexes.

## 14. Bounds and allocation safety

### Inherited, already measured/approved bounds

P04 bounds remain authoritative: 48 source units and eight finalized cards per canonical advancement; normal/recovery work envelopes 110/158 atomic entries; active source/card envelopes 432/96; bounded frontier candidates/entries; 25 retained continuation records; and source-text-free continuation evidence. P05 retains its exact source-font slice, layout/font-evidence, resolved card/block, and finite identity-evidence bounds recorded by CHANGE-029.

Legacy retention settings are observed rather than adopted: whole display 20 MiB total and 5 MiB per file, segmented 48 MiB policy and 3 MiB per file, and memory 8 MiB approximate estimated bytes.

### Required but deferred to P06-006 measurement

P06-006 must choose, measure, and enforce segment card count, distinct source-slice count, compressed byte limit, decoded byte limit, decompression ratio/limit, maximum manifest records/totals, maximum continuation chain and restart depth, aggregate disk/memory totals, pin count, and current/adjacent retention. It must document pressure behavior and atomic-replacement recovery. P06-001 intentionally assigns no new numeric budget.

Until then, this contract requires finite card/source counts, finite encoded/decoded sizes, overflow-safe lengths/totals, no whole-book display segment, no unbounded continuation chain, explicit manifest totals, validation before large allocation, decompression limits, and a separate current/adjacent pin representation. Pinning is retention metadata, never identity.

## 15. P06-002 through P06-007 ownership

| Task | Owned implementation work after this contract |
| --- | --- |
| P06-002 | Completed by `CHANGE-20260912-032`: logical key/record codec and shared strict memory/disk admission reject incomplete/adjacent legacy islands while preserving P04 publication authority. No migration, budget policy, persistent format activation, write, or reuse. |
| P06-003 | Completed by `CHANGE-20260912-033`: controlled cold generation, memory reuse, reopened temp-root disk reuse, memory/disk eviction, rejection/regeneration, mixed coverage and construction orders reproduce the complete P03 ordered identity through strict admission and P04 publication. Live production reuse remains inactive. |
| P06-004 | Completed by `CHANGE-20260912-034`: shared typed policy/executor maps all 16 admission outcomes to no action, exact memory eviction, exact derivative invalidation, same-scope quarantine, retained unsupported future record, deferred migration assessment or failed-safe receipt. It accepts only opaque exact lookup receipts under explicit caller-owned display roots, never a decoded filename/book id/path. |
| P06-005 | Implement only proven migrations. Existing display records are safe misses unless a future record meets this contract without guessing. |
| P06-006 | Measure and finalize byte/card/source/manifest/decompression/chain budgets, atomic retention, and pin policy. |
| P06-007 | Add corruption, malformed field/count, partial write, rename race, stale generation, rollback, cross-book, and recovery tests; record actual physical format/version decisions. |

RISK-007 is partially mitigated by P04 fail-closed behavior plus controlled
P06-003 exact-reuse evidence, but live persistent rollout remains unresolved.
RISK-008 is partially mitigated by scoped derivative invalidation, but migration
and bounds remain open. REQ-009 and REQ-051 remain
IMPLEMENTED_NOT_VERIFIED; REQ-010 remains unverified.

## 16. Required focused tests

P06 implementation must add focused tests before claiming reuse:

1. canonical key canonical-byte/digest stability, forbidden-field exclusion, and cross-book separation;
2. strict field presence/order/duplicate/unknown/trailing/length/overflow/decompression rejection;
3. every F196/F202/F204/F206/F207/F208 exact/change/corrupt classification outcome;
4. exact source interval, UTF-16/table-row slice, structural owner/role, F209/F210/F211, visible payload, and card identity recomputation;
5. every internal, predecessor, successor, frontier, book-start, and logical-end seam;
6. empty and nonempty frontier distinction proving previousFinalizedBoundary rather than nextSourceCursor;
7. cached-to-live append, regenerated-to-cached prepend, isolated anchoring, and two-record join rejection where integer ranges merely touch;
8. identical validation results for decoded disk and memory representation;
9. all 16 outcomes and their no-authority action matrix;
10. current whole, segmented, section-scoped, memory, range, chapter-layout, checkpoint, and malformed-record migratability classifications;
11. P03 cold/warm/eviction/reopen comparisons with canonical records only after P06-003;
12. P06-004 exact whole/segmented/section/chapter-layout/memory invalidation,
    same-scope quarantine, path rejection, idempotence, failure receipts and
    protected-data preservation;
13. P06-006 byte/card/decoded-size/manifest/pin bounds and P06-007 corruption/write-race recovery.

Existing P03, P04, and P05 oracles remain frozen. P06-002 adds
`test/reader_contract/pagination/canonical_display_segment_admission_test.dart`:
it constructs cards and continuations from the real P04 paginator/snapshot and
P05 layout contract, proves strict key/record bytes, checksum rejection,
cross-book/stale/join failure, empty-frontier proof, all 16 authority flags,
legacy safe misses, and byte-identical memory/disk outcomes. P06-006 and
P06-007 retain release bounds and physical partial-write coverage respectively.
P06-003 adds
`test/reader_contract/pagination/canonical_display_cache_equivalence_test.dart`;
it compares the full P03 evidence projection across cold, memory, reopened
disk, memory-evicted disk reload, full derivative eviction, rejection plus
regeneration, mixed cached/regenerated regions, and forward/target-first/
bounded-backward construction. Its two complete internal runs normalize to
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`.

## 17. Open questions and blockers

There is no product-policy or persistent-version blocker to specifying the logical contract. The semanticRevision is a nondeployed logical tag; P06-004/005/007 must decide any physical file-format/version transition only after implementation evidence.

Open implementation questions, explicitly deferred, are:

- measured numeric segment/manifest/decompression/retention limits and pressure policy (P06-006);
- physical container and atomic replace/recovery protocol (P06-006/007);
- scoped deletion/quarantine timing and migration rollout/rollback policy (P06-004/005/007);
- whether a validated live P04 state is serialized immediately or only at accepted cache-write authority (P06-007 physical rollout, subject to the existing transaction).

None permits reuse of a legacy record. They do not block P06-002 strict rejection because rejection needs no guessed conversion or version bump.

The former external P04/P05 12/13 continuation-control blocker was restored by
`CHANGE-20260911-031`. P06-002 then passed its strict logical admission suite
at 7/7, the continuation/reconstruction control at 13/13, P04 publication at
9/9, relevant P05 controls at 69/69, and the unchanged P04 final gate at 3/3.
No P06 fallback weakens the font gate.

## 18. P06-004 scoped invalidation implementation

`CanonicalDisplayCacheInvalidationService` is the shared policy/executor. It
uses P06 admission outcome, trusted caller-owned storage scope, opaque trusted
lookup/manifest receipt, physical candidate type and migration evidence. It
never derives a target from a decoded record field. The exact cache services
revalidate their direct-child deterministic target, reject absolute/traversal,
forged filename and symlink paths, and touch at most one payload and one
manifest reference per action.

Exact canonical-compatible and absent candidates are untouched. Known legacy
whole, segmented, section-scoped, section-memory and chapter-layout
derivatives are evicted/invalidated exactly; corruption and cross-book claims
are quarantined only inside the current trusted root; stale generation evicts
only an exact memory entry; unsupported future revisions are retained; and
potentially migratable strict records are deferred to P06-005. A missing
payload produces a typed exact-reference cleanup/no-op, repeated calls are
idempotent, and manifest or payload failures produce a fail-closed receipt
without blocking bounded source regeneration. No receipt has publication,
checkpoint, settlement, migration or cache-write authority.

`pagination/canonical_display_cache_invalidation_test.dart` uses real cache
services with sandbox-only roots. It verifies all 16 mappings, exact
file/reference behavior, path safety, injected failure, protected-data
byte-equivalence and zero source/mutable-index/authority copies. Observed
maxima are plan 240 bytes, receipt 461 bytes, one payload file, one manifest
entry, one retained/quarantined/evicted record and one protected root per
action; source text, mutable-index identity, authority and unrelated-file
mutations are zero. No default production cleanup path is invoked.

## 19. P06-005 controlled canonical regeneration

`CanonicalDisplayCacheMigrationService` is the only P06-005 planner/executor.
It treats every old candidate as nonauthoritative evidence and follows this
bounded sequence:

```text
old candidate -> strict integrity/source assessment -> compatibility class
-> eligibility decision -> current pinned-source resolution
-> bounded current-contract pagination -> P04 controlled publication
-> current record build -> strict P06 admission -> controlled replacement
```

The old candidate never supplies cards, F209/F210/F211 values, signatures,
continuation authority, publication authority, checkpoint authority or a live
cache-write permission. Regeneration uses the current P04 paginator and
`ProgressiveDisplayState.publishCanonical`, then the normal canonical record
builder and strict admission. The only deletion handoff is the P06-004
`controlledMigrationReplacement` plan, after the new record has already been
fully validated and retained in the explicit controlled target.

### Eligibility and source rule

A candidate is eligible only when its strict codec/checksum, trusted
caller-owned scope, publication/source linkage, stable start cursor, ordered
semantic source ownership, boundary/continuation evidence, old compatibility
components, a genuine classifier change, current P05 terminal layout/font/image
evidence, an exact current pinned source route and bounded P04 regeneration all
validate. Exact compatibility is `exactRecordNoMigration`.

With an unchanged source snapshot, layout, renderer and/or pagination changes
regenerate from the proven source interval. The fixed classifier order is
retained for compound changes. There is currently no production
source/parser-version correspondence resolver. Source or parser changes
therefore return `sourceCorrespondenceUnavailable` and require ordinary
current-source regeneration. Text search, nearest visible-text matching,
ambiguous or many-to-one correspondence, and mutable indexes are never
authority.

### Typed outcomes and fail-closed matrix

The planner exposes: exact record/no migration; regenerated canonical
migration; nonmigratable legacy evidence; incomplete evidence; corrupt
evidence; unsupported future revision retained; source correspondence
unavailable or ambiguous; incompatible publication/book scope; work budget
exhausted; stale request; cancelled request; current contract unavailable;
regenerated-record strict-admission failure; controlled replacement failure;
and bounded source regeneration required. Other than a successful result,
every outcome has zero migrated cards, continuation, publication,
checkpoint/settlement, live-write and deferred-candidate-deletion authority.
A success contains only a newly admitted current record and the controlled
replacement receipt; it does not activate production storage.

| Candidate evidence | P06-005 result |
| --- | --- |
| Whole v3, segmented v3, section-scoped, section-memory, raw range/map, or chapter-layout | Typed `nonmigratableLegacyEvidence`; no card/range/text conversion. Chapter layout remains a nonauthoritative hint. |
| Checkpoint/stable location or P04 continuation alone | Typed incomplete safe miss; recovery hints are not display segments. |
| Live accepted P04 card plus P05 evidence | Insufficient unless it is contained in a fully strict canonical record with all linkage and current-contract evidence. |
| Strict canonical, layout, renderer, pagination, or valid compound change; compatible unchanged source | Eligible for one bounded regeneration; new physical boundaries may differ while ordered semantic ownership is re-proven. |
| Strict canonical source/parser or compound source change | `sourceCorrespondenceUnavailable` until a production resolver proves unique, exact correspondence. |
| Corrupt, incomplete, cross-scope or unsupported future candidate | Typed safe miss; future records are retained. |

Controlled memory/disk tests prove layout-only, renderer-only, pagination-only
and ordered compound regeneration. They recompute all physical identities and
signatures, preserve semantic ownership despite changed card boundaries, equal
ordinary cold current-contract generation, and leave the old candidate intact
until strict validation and controlled retention finish. Stale, cancelled,
budget-exhausted, source-missing, corrupt and replacement-failure paths expose
no partial record and preserve old storage and accepted display bytes. Repeated
success is deterministic and idempotent. Parsed source, checkpoints and user
data are untouched.

Observed P06-005 maxima (observations, not P06-006 budgets): assessment 268
bytes, result 32 bytes, old record 15,376 bytes, new record 14,805 bytes, two
source units/cards regenerated, two changed physical boundaries, one changed
compatibility dimension, zero source-remap candidates, one retained/replaced
controlled record and one attempt. Copied old-card identity bytes, copied
source-text identity bytes, mutable-index authority bytes, partial records
exposed, protected-data mutations and live-cache writes are all zero.

No persistent format/key/version, default cache path, live reuse/write,
retention/pinning budget, atomic physical protocol or P06-006/P06-007 work is
activated by this result.

## 20. Independent P06-004/P06-005 audit

`CHANGE-20260913-036` independently traced the complete invalidation and
migration paths, with P06-003 retained as a frozen dependency control. Four
high-severity weaknesses were reproduced and corrected:

- section-memory lookup previously accepted any key beginning with
  `<bookScope>_`, allowing a prefix-colliding book such as `book-a_other` to
  obtain an exact eviction receipt under `book-a`; lookup now requires either
  the exact supplied key or the production-shaped `<bookScope>_dc_` namespace;
- migration freshness was checked before, but not after, asynchronous
  replacement retention and old-receipt lookup; both awaits are now followed
  by a stale/cancelled gate before any invalidation handoff;
- a caller could construct a public diagnostic `exact` admission result and
  present it as proof; only results minted by the strict admission validator
  now carry private admission attestation, and migration requires it; and
- a valid current record for a different source interval could replace the old
  strict segment; migration now requires the regenerated record's stable start
  cursor to equal the assessed old segment's stable start before retention.

Focused regressions first failed for each condition and then passed after the
boundary corrections. The audit reconfirmed direct-child/path-component and
symlink checks, exact payload/manifest-reference scope, same-scope quarantine,
future-revision retention, protected-root isolation, idempotent safe misses and
fail-closed partial failures. It also reconfirmed that legacy records are
unconditionally nonmigratable, current strict records require unchanged
source/parser evidence, replacements are produced through current P04/P05 and
strict P06 admission, and P06-004 remains the sole deletion authority.

At the CHANGE-036 audit point, the controlled transport had no default
production root or ReaderScreen writer; concurrent symlink swaps, physical
crash recovery and final retention were still assigned to P06-006/P06-007.
Sections 21–22 and CHANGE-037/038 supersede that historical activation status.
## 21. Release retention budgets (TASK-P06-006)

`CanonicalDisplayCacheBudgets` is the single release limit set. Every
variable-size physical declaration is rejected before allocation,
decompression, logical decoding or retention. Counts and byte totals use
checked addition and contradictory manifest totals are rejected.

| Quantity | Observed P04/P05/P06 maximum | Release limit | Headroom and basis |
| --- | ---: | ---: | --- |
| cards / record and validation cards | 6 | 12 | 2x the largest six-card P04 publication; above the P04 eight-card generation stride without permitting the 96-card resident ceiling in one record |
| stable source slices / record and validation slices | 14 per record; 20 across the three-record equivalence set | 96 | covers two bounded 48-source P04 windows and exceeds the measured per-record maximum by 6.8x |
| block layouts / record | 6 | 192 | two layout blocks per permitted source slice |
| compressed bytes / record | 8,453 | 524,288 | 62x observed; bounds hostile input while retaining layout/font and richer-book headroom |
| decoded bytes / record | 37,397 | 1,048,576 | 28x observed; remains a finite pre-decode ceiling |
| decompression ratio / output | 5x ceiling / 37,397 bytes | 64x / 1,048,576 bytes | ratio and output are independently checked before and during decompression |
| manifest records / bytes | 3 / 1,892 | 48 / 131,072 | four disk windows of 12 records; 69x measured manifest-byte headroom keeps the commit point bounded |
| memory records / bytes | 3 / 77,405 | 12 / 12,582,912 | four observed segment sets; no record can consume beyond the per-record ceiling |
| disk records / bytes | 3 / 18,479 | 48 / 25,165,824 | four times memory record count and exactly twice its aggregate byte ceiling |
| continuation-chain depth | 2 | 25 | preserves the existing P04 25-record continuation bound |
| restart depth | 2 | 2 | preserves the measured and pre-existing bounded fallback; no extra restart is admitted |
| current/adjacent pins | 3 | 3 | current plus the unique stable predecessor and successor only |
| temporary replacement bytes | 10,441 (8,549 container + 1,892 manifest) | 655,616 | one maximum 512-KiB payload, one maximum 128-KiB manifest and 256 bytes protocol overhead |

Pins are minted only by accepted `ProgressiveDisplayState` publication
evidence. They contain key digests derived from stable source/layout/
pagination identity and exact cursor seams; source text, display indexes,
access order and object identity are excluded. Preview, stale, cancelled,
rejected and merely resident candidates cannot mint them. Eviction is
lexicographic by unpinned key digest, is idempotent, commits manifest removal
before deleting payloads, and never traverses outside the isolated display
derivative namespace. If pinned records alone exceed either aggregate bound,
the service returns typed pinned pressure and leaves the prior valid state.

## 22. Physical format and production activation (TASK-P06-007)

P01 recorded whole-display format 3 and segmented-display format 3 as the
current persistent values and reserved P06 as the first phase allowed to
finalize a successor. The isolated canonical format therefore uses the next
monotonic, collision-free value 4; it does not alter or reinterpret either
legacy format. Layout `v14`, pagination `nalori_cards_v16_lists`, logical
canonical segment revision 1, checkpoint record/store schemas 1/1 and stable
location schema 2 are unchanged.

| Physical declaration | Old value | Live canonical value | Declaration/read/write sites |
| --- | --- | --- | --- |
| namespace | legacy whole/segmented service roots | `canonical_display_v4` | service constants/constructor/createDefault; ReaderScreen service creation and opaque book-scope derivation |
| physical format | whole 3; segmented 3; no canonical physical format | 4 | service constant, `_Manifest.encode/decode`, `_encodeContainer` and `_decodeContainerHeader` |
| manifest revision | no canonical manifest | `canonical_display_manifest_v4` | service constant and `_Manifest.encode/decode` exact-key codec |
| container revision | no canonical container | `canonical_display_container_v4` | service constant, `_Manifest.encode/decode` binding and compatibility check |
| payload name | legacy service-specific names | `seg-sha256-<keyDigest>-<recordChecksum>.cseg4.gz` | digest-only manifest entry validation and payload lookup |
| book directory | legacy service-specific scope | `<namespace>/<bookScopeDigest>` | `readAndAdmit`, `writeAuthorized`, root-containment/path/symlink guards and ReaderScreen read/write calls |

The manifest is canonical JSON with exactly `containerRevision`, `entries`,
`formatVersion`, `manifestDigest`, `namespace`, `recordCount`, `revision` and
`totalBytes`. Each entry binds the stable key digest and opaque book scope to
the payload filename, logical record digest, whole-container digest, encoded
container bytes and decoded logical bytes. Checked aggregation rejects
duplicates, contradictory counts/totals and overflow.

Each payload starts with a fixed 96-byte header: eight-byte magic
`NLCSEG4\n`, big-endian uint32 physical version at byte 8, uint64 decoded and
compressed lengths at bytes 12 and 20, the 64-byte lowercase hexadecimal gzip
digest at bytes 28–91, and four required zero bytes. The bounded gzip body
follows. File size, declared compressed/decoded size, decompression ratio,
compressed digest and container digest are checked before logical decode;
streamed decompression enforces its output ceiling during production.

### Live read, publication and write boundary

ReaderScreen first obtains caller-owned P04 generation evidence. A v4 memory
or disk candidate then passes the same strict codec, compatibility,
source/card, seam, continuation and contextual-anchoring admission service.
An accepted candidate reaches visible state only as input to
`ProgressiveDisplayState.publishCanonical`; the cache cannot mint publication
or write authority. After successful publication and canonical session commit,
the display state may mint a private write capability bound to that exact
record and source snapshot. The service additionally requires the private
strict-admission attestation before persisting. A fresh service reopens the
same root, decodes the manifest/container, repeats strict admission and
contextual anchoring, and again publishes only through `publishCanonical`.
Any miss or rejection regenerates from parsed source without cache deletion.

### Crash, recovery, invalidation and rollback outcomes

Replacement writes a bounded temporary payload, flushes/closes it, atomically
renames it, then writes and flushes a bounded temporary manifest and installs
that manifest last. Until the manifest rename, the previous valid reference
and payload remain authoritative. Temporary and valid-manifest-unreferenced
payloads are recovery garbage; a malformed manifest is never trusted to
identify deletions. Reference removal commits before payload eviction, making
missing/repeated cleanup safe and idempotent.

Digest-only paths, normalized root containment, non-following traversal and
parent/target symlink rejection prevent traversal, sibling-prefix,
cross-book and symlink-swap replacement. Per-root coordination serializes
same-key and different-key writers without allowing one book to replace
another. Stale/cancelled state is rechecked at every asynchronous precommit
boundary; once the manifest has atomically committed, the durable record is a
complete write and later cancellation cannot reinterpret it as partial.

Legacy whole/segmented/current noncanonical records remain safe misses and are
not converted. Evidence-sufficient regeneration still follows the audited
P06-005 boundary, and obsolete/corrupt derivatives still use the audited
P06-004 derivative-only invalidation path. Older applications ignore the new
namespace. Current applications ignore legacy, unsupported-current and future
canonical revisions. Failed replacement and rollback retain old bytes; neither
path changes or requires clearing parsed source, EPUBs, checkpoints or user
data.

## 23. Corrective nonblocking write and restart boundary

`CHANGE-20260914-039` makes physical persistence a derivative of an already
accepted display publication. ReaderScreen publishes and commits the current
canonical cards first, then attempts exact memory/fresh-service disk reuse and
otherwise enqueues one authorized write. Compression, hashing and container
preparation run away from the UI isolate; one bounded queue performs physical
writes with concurrency one. Equal canonical keys coalesce, and an epoch
invalidates stale queued writes. Queue failure is reported without revoking
cards that `ProgressiveDisplayState` already accepted.

The publication record builder now has a typed no-write result. A mid-book
record is eligible only when accepted P04 predecessor/restart and contextual
anchor evidence proves its continuation. Missing evidence does not masquerade
as book start, weaken strict admission or cause a retry; reading continues and
only the derivative write is skipped. The old strict builder remains strict.

Memory pressure cancels background parsing/indexing and queued writes, releases
font source bytes and unpinned source/display intermediates, and retains the
visible current card. These host-level guarantees do not establish Android PSS
or RSS. The prior device observation was approximately 517 MB PSS and 596 MB
RSS; post-correction device measurement is still required.

## 24. Reopened lazy input and terminal admission contract

CHANGE-20260919-040 supersedes any assumption that the last source ordinal in
a pinned lazy snapshot proves logical book end. A v1 terminal continuation
can pass codec validation while making that false semantic claim. The live
builder currently derives a logical-end right proof from its terminal flag;
the admission context needs independent immutable spine/complete-section
evidence. P06 remains REGRESSED_ON_DEVICE at 7/7 pending this correction and
the ordinary A059 gate.

The selected [handoff contract](nalori-lazy-snapshot-handoff-design.md) uses a
separate in-memory section-end receipt and authenticated successor session.
It requires exact A-prefix-of-A+B proof and immutable accepted cards. Ordinary
same-snapshot/session and continuation-parent rejection remains unchanged.
Neither receipt nor handoff may be encoded as a v1 terminal continuation.

The first implementation must treat a partial-window terminal record as a
typed `unverifiedLogicalEnd` safe miss on both memory and disk paths, without
conversion, partial publication or destructive cleanup. It must also prove
publication start independently of local source ordinal zero. Genuine final
spine records retain strict source/layout/renderer/pagination and end proof.

The design changes no persistent schema or version. Physical v4 and current
continuation/checkpoint formats stay unchanged; handoff-spanning or suspended
records have no write authority under those formats. Ordinary representable
segments remain eligible after strict contextual admission. Persisting the
new handoff protocol requires a separately approved P06 contract/migration
task. The proposed lazy packing identity separates new lazy signatures from
old window-dependent signatures; it must not silently migrate old exact
checkpoints. Legacy exact restoration and bounded retention are explicit
implementation-entry proofs, not claims of completed compatibility.
