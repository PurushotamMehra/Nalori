# Trusted reader-contract tests

This directory is the reader reliability contract suite. Its authority order is:

> approved requirement → trusted test → implementation

The current application and its helper tests are evidence, not the product specification. A passing helper test cannot prove ReaderScreen route, controller, publication, settlement, checkpoint, or lifecycle correctness.

## Layers and boundaries

| Layer | Responsibility | Required production path | Can prove | Cannot prove |
| --- | --- | --- | --- | --- |
| fixtures | Human-reviewable EPUB source, provenance, checksums, anchors, UTF-16 ranges and structural oracle. | Test-only builder plus archive inspection; parser tests may open the built EPUB. | Fixture inputs and authored source truth are stable and complete. | Physical-card boundaries, cache correctness, or reader lifecycle. |
| parser_source | Parser/index/source-identity contract against independently authored fixture oracle. | EpubParserService, LazyEpubIndexService, LazyBookSession where required. | Source text, spine order, structural evidence and stable source targets. | Pagination or durable visible-card behavior. |
| pagination | P02 extraction parity, then P03+ construction-order characterization. | The single production `ReaderCardPaginator` used by `ReaderScreen`. | Ordered source ranges, card identities and visible text for controlled requests. | Canonical equivalence, renderer metrics or ReaderScreen lifecycle by itself. |
| layout | P05+ shared measure/render contract. | Production ReadingCard measurement/render adapters. | Declared layout/fingerprint inputs and source-range consequences. | Device rendering across all platforms. |
| cache | P06+ canonical cache compatibility. | Production whole, segmented and memory cache adapters with temp roots. | Cold/warm/eviction identity equivalence and safe miss behavior. | Source parsing or route lifecycle alone. |
| checkpoint | P07+ journal and checkpoint contract. | ReaderCheckpointStore and ReaderCheckpointCoordinator with real temporary SQLite storage. | Epoch/revision/order and checkpoint persistence. | ReaderScreen controller settlement unless the lifecycle layer drives it. |
| lifecycle | P07+ route/open/settle/flush/close scenarios. | ReaderOpenService, ReaderScreen, real parser/paginator/render and temporary production stores. | End-to-end accepted-card and durable-exit behavior. | Device-only lifecycle effects. |
| navigation | P09+ explicit and adjacent target behavior. | ReaderScreen stable navigation, LazyBookSession and production coordinator. | Stable-target publication, settlement, retry and stale-work behavior. | Construction-order truth without pagination evidence. |

The P02 fixture, parser_source, deterministic support and production paginator seam are created. Later canonical construction-order, layout, cache, checkpoint, lifecycle and navigation tests are deliberately documented, not pre-populated with empty Dart tests.

## Test rules

- Annotate every group or test with its mapped REQ- identifiers, either in its description or in an adjacent comment. The annotation is traceability, not a dependency.
- Later failures must report ordered source ranges, ReaderCardIdentity values and visible text. Local display indexes may aid diagnostics only; they are never truth.
- Expected source text, anchors and UTF-16 half-open ranges are authored in the fixture manifest. Do not use a production parser or paginator to generate an expected oracle.
- Production parsing may be compared against that authored oracle. A parser discrepancy is reported and investigated without changing production code in a fixture task.
- Run focused tests with: flutter test test/reader_contract/<layer>/<file>_test.dart. Do not use the full suite as reader-contract evidence.
- Build archives into a fresh test temporary directory. Cache, SQLite, preferences and singleton state must be isolated per test when those layers are introduced.

Allowed controlled boundaries are test temporary directories, deterministic fixture assembly, archive inspection, explicit asynchronous completers, fake clocks only at real time boundaries, and narrowly documented platform/path adapters. Each later fake must state what production behavior it does not prove.

The following are prohibited:

- treating mutable display indexes as location truth;
- arbitrary card-count assertions without ordered source-range evidence;
- copied or reimplemented production pagination logic in test helpers;
- uncontrolled delays or repeated pumpAndSettle calls as settlement proof;
- network access or public-domain downloads;
- shared cache/database state between tests;
- unexplained signature, snapshot or expected-range updates;
- handcrafted cards used to claim parser-to-paginator or lifecycle correctness;
- golden images as a substitute for source/card/lifecycle evidence.

## Deterministic P02 support

The following support is test infrastructure only. It establishes declared inputs and isolated real stores where the existing production APIs already permit them. It does not establish pagination, restoration, cache equivalence, renderer parity, controller settlement or durable lifecycle behavior.

### Production paginator seam

`lib/services/reader_card_paginator.dart` owns one production
split/merge/rebalance/frontier kernel. `ReaderCardPaginator.paginateCanonical`
drives it through the immutable canonical model in
`lib/models/canonical_pagination.dart`. `ReaderScreen._rebuildDisplayChunks`
still captures the current layout, scheduler priority, cancellation,
diagnostics and optional anchor in `ReaderCardPaginatorRequest`, then calls the
temporary `paginate` compatibility adapter. That adapter delegates to the same
kernel with an isolated legacy request-end terminal policy; the resulting
`DisplayRangeResult` follows the unchanged screen publication path. Conversion
and removal of this adapter belong to `TASK-P04-004`.

`pagination/reader_card_paginator_parity_test.dart` invokes that exact method
directly with the trusted micro-fixture and controlled Lexend layout. Its frozen
P02 baseline compares ordered visible text, structural type, source/display
half-open ranges, spine/logical-block identity ranges, complete
`ReaderCardIdentity` signatures, anchored finalization, range-local tail flush
and cancellation classification. This baseline proves only that the extraction
did not change the captured behavior. It is not a canonical P03 oracle, does not
compare construction orders and must not be updated to hide a later failure.

The compatibility request retains its read-only live-view input only until the
adapter is invoked; the adapter immediately pins canonical serialized source
records before asynchronous work. Cancellation remains evaluated at the
production scheduler checkpoints. Legacy request-end terminal treatment is
explicitly adapter-only and preserves the frozen P02 output, including the
known independently packed-range risk. It is not canonical continuation or
finalization authority.

### P04 immutable forward state machine and canonical continuations

`pagination/reader_card_paginator_canonical_state_machine_test.dart` invokes
the real `ReaderCardPaginator.paginateCanonical` entry point. A
`CanonicalPaginationSourceSnapshot` pins publication, parser/source revision,
ordered stable owners, section/spine identities, exact serialized source
records and per-source/snapshot digests. Caller list replacement or mutation
cannot change the request. A source ordinal is only a validated lookup hint
paired with a stable owner; display, controller and window indexes are absent
from restart and target authority.

The only canonical restart forms are publication start, trusted section start,
and a validated `CanonicalPaginationContinuation`. The continuation is a
strictly canonical JSON scalar/list/map record with SHA-256 integrity, exact
parent digest and ordinal, stable publication/parser/snapshot/pagination/layout
key, exact cursors, finalized-boundary proof, cadence/terminal evidence, and at
most `deferredPredecessor` plus `pendingTail`. Frontier slices carry stable
source/section/spine ownership, exact UTF-16 or table-row intervals, and
re-derived structural/split/list/publisher/rich-metadata digests. They copy zero
source text and carry no display, window, controller, cache, widget, or
generation authority.

`CanonicalPaginationContinuationCodec` rejects noncanonical bytes, missing or
unknown fields/types/kinds, integrity changes, contradictory terminal/cadence
state, and malformed nested card identities. Before resume, the paginator also
requires exact request identities and chain parent/ordinal, validates every
cursor and owner against the pinned snapshot, and reconstructs both frontier
candidates through the real production kernel. Stored measurement or
classification evidence cannot override production remeasurement. A full-span
split fragment includes an explicit provenance flag because `buildSplitChunk`
can produce structural metadata different from the unsplit source even when
the UTF-16 interval is `[0,length)`; the continuation still stores no text.

`CanonicalPaginationCheckpointIndex` is process-local and publication-window
scoped. It transactionally deduplicates the active record, rejects older
replays, and stable-cursor sorts only accepted chain records. It retains at
most 25 and protects the prefix guard, active suffix and
its parent plus section-boundary records, and reports typed bound or required-
earlier-restart outcomes without partial insertion. It is not a display cache.
Checkpoint counters carry across provisional requests and emit at the first of
48 fully consumed sources or eight finalized cards, as well as trusted section
boundaries and terminal logical end.

The P04-002 focused 18-test file covers immutable snapshots and mismatch rejection,
repeated-text owners, request exhaustion versus logical end, stable targets,
direct merge, measured failure, structural boundaries, backward tiny-tail
attachment and growth, sentence rebalance with publisher/list exclusions,
frontier-cap rejection, all specified cancellation/stale points, table-row
restart reconstruction, standard/split-stress structural preservation, source
7's four ranges, and deterministic repeated invocation. Rejected results expose
no publishable cards, accepted restart authority or cache-write authority.
`pagination/reader_card_paginator_continuation_checkpoint_test.dart` adds 12
production-path tests for deterministic bytes/digests, strict mutations and
compatibility rejection, exact frontier reconstruction, zero copied text,
parent/ordinal/fork behavior, roots/boundaries/terminal state, 48-source and
eight-card cadence, provisional request exhaustion, deterministic repeated
chains, 25-record retention/dedup/guards, and cancellation/staleness authority.
P04-003 does not wire canonical results into ReaderScreen, implement target or
prepend traversal, finalize P04-006 structural policy, transact progressive
publication, or make the P03 equality files green.

`pagination/reader_card_paginator_canonical_paths_test.dart` is the focused
P04-004 production-consumption contract. `CanonicalReaderPaginationSession`
pins one book/publication/parser/source snapshot and controlled layout, owns
the bounded 25-record continuation index, selects publication or trusted
section roots and the nearest compatible predecessor (with one earlier-record
recovery only), resolves targets by stable source owner plus UTF-16 offset,
and resumes forward work only after the actual published suffix card/ranges
match the accepted continuation boundary. Normal work is capped at 110 atomic
source/fragment entries and seven discarded predecessor cards; recovery is
capped at 158 and fifteen. Only finalized cards cross into the existing
`ProgressiveDisplayState` publication layer; provisional frontier state never
does, and request exhaustion remains a nonterminal continuation rather than a
logical end.

ReaderScreen initial, stable-target, forward, and backward routes use that
session and have no call site to `paginateLegacyForP02`. The named legacy
adapter remains executable only for frozen historical parity/reference
evidence. P04-005 backward preparation chooses the nearest validated
checkpoint strictly before the desired predecessor, permits one bounded
earlier-restart fallback (including a compatible trusted section or
publication root), and regenerates exclusively in forward source order. The
operation returns at most seven normal or fifteen recovery predecessor cards
only after reproducing the accepted published prefix and exact committed card,
then proving the predecessor/current/successor cursor chain. Normal work is
capped at 110 atomic source/fragment entries, recovery at 158, and the shared
checkpoint index remains capped at 25 records. Typed pending/rejected outcomes
carry no publishable predecessor or cache-write authority. P04-005 does not
change append/prepend mutation semantics or claim transactional seam proof;
that publication boundary remains P04-007. Persistent display-cache
compatibility is not inferred from canonical cards and remains P06 work.

P04-006 finalizes canonical physical-card ownership in
`CanonicalReaderCardIdentityBuilder`, the only conversion from accepted
canonical source slices to a canonical `ReaderCardIdentity`. Every ordered
identity range signs its stable source, section, spine and logical owner; exact
half-open UTF-16 or table-row interval; structural owner role; structure,
fragment, publisher-layout, rich-metadata and list-fragment digests; paragraph
start/end flags; split boundary; and explicit full-span split provenance.
Source ordinal hints remain validated lookup aids and are removed from both
source/fragment ownership digests and card signatures. Visible text and image
bytes are content checksums, never sole owner authority.

Text fragments are reconstructed through the shared production
`buildCanonicalTextFragment` helper, including clipped bold/italic/link and
footnote offsets and list-fragment state. Tables use the shared
`buildCanonicalTableRowFragment` helper and always own exact decoded body-row
intervals, including a full table; headers remain structural context. Images
receive parser-stable source-reference owners. Source-authored headings and
navigation/list content retain parser owners, while generated title,
navigation and milestone sources use explicit `generated:*` roles and stable
publication/section-local logical owners. A section/spine change is a hard
identity boundary, even for identical text.

The strict continuation codec requires the complete canonical ownership field
set, rejects partial/unknown/contradictory evidence, and stores only digests
and ranges—not copied source text. No persistent codec/cache/checkpoint version
changed. `ReaderCardIdentity.fromCard` remains the frozen P02 and pre-P07
checkpoint/cache projection; it is not canonical identity authority and its
legacy encoding/signatures remain unchanged. Moving canonical identity through
the progressive publication transaction remains P04-007; checkpoint/cache
consumption remains P07/P06.

`pagination/reader_card_paginator_structural_identity_test.dart` drives the
real canonical session/paginator through source and generated headings,
navigation, repeated text, split and continued paragraphs, full-span split
provenance, lists, exact table rows and decoded content, rich inline offsets,
images/milestones, section seams, full/target/forward/backward/singleton
construction, deterministic reruns, ordinal-hint independence, and strict
malformed/index-evidence rejection. It adds no test identity signer or
pagination algorithm.

### P03 full-range characterization

`pagination/reader_card_paginator_full_range_characterization_test.dart`
executes one complete `[0,20)` request against the same real production
`ReaderCardPaginator.paginate` entry point and controlled Lexend environment.
Its independently reviewed source evidence is transcribed from the fixture
manifest plus `nav.xhtml`, `chapter-one.xhtml`, `chapter-two.xhtml`, and the
ordered OPF spine. It compares every observed card's structural type, decoded
visible table text, raw source/display half-open ranges, section/logical-block
identity fields, and full source coverage. The test emits the resulting
`ReaderCardIdentity` values and observable origin labels for the evidence
ledger; it does not freeze opaque expected signatures.

`pagination/reader_card_pagination_evidence.dart` is the intentionally small
projection/comparator for later P03 work. It only projects production results;
it contains no packing, splitting, merging, rebalancing, or identity logic. A
later construction-order mismatch reports its request label, first divergent
card, expected/actual ranges, identities and visible text, source
gap/overlap/duplication evidence, and neighboring seam cards. The current
full-range physical membership is a reviewed characterization only. It is not
canonical membership and does not establish equivalence for target-first,
append, prepend, singleton, retry, cache, or any other construction order.

### P03 construction-order characterization

The bounded `TASK-P03-002/003/004/006` matrix consists of:

- `pagination/reader_card_paginator_target_first_matrix_test.dart`;
- `pagination/reader_card_paginator_forward_backward_matrix_test.dart`;
- `pagination/reader_card_paginator_singleton_expansion_matrix_test.dart`;
- `pagination/reader_card_paginator_structural_ownership_test.dart`; and
- `pagination/reader_core_pagination_harness.dart`, which supplies request and
  evidence plumbing only.

Every construction invokes `ReaderCardPaginator.paginate`. Multi-range results
are published only through `ProgressiveDisplayState.publishInitial`, `append`,
and `prepend`; the harness never concatenates cards or recreates split, pack,
merge, flush, rebalance, or identity rules. Each equality case dynamically
regenerates its full-range reference under the same layout inputs and compares
the complete ordered physical sequence. The comparator reports scenario,
order, layout, requested ranges and target plus the first divergent card,
source/display/logical ownership, full `ReaderCardIdentity`, raw/visible text,
nearby seam cards, and coverage gaps/overlaps/duplicates/out-of-range ranges.

The 20-source fixture is smaller than ReaderScreen's current minimum target
windows (48 source units for lazy and 96 otherwise), so the live screen
selector would return `[0,20)` for every anchor. To exercise the real
range-local boundary without inventing an offset API, the target matrix calls
the production `ProgressiveDisplayState.targetRange` selector with explicit
controlled `lookBehind=1`, `lookAhead=1`, and `minimumWindow=3`, then follows
ReaderScreen's lazy forward-before-backward expansion order. Targets remain
source-index based. The paginator's optional text offset is an anchor-
finalization input, not an offset-capable target-range selector. Current
diagnostics expose range begin/end and result metadata, but not pending state,
tail-flush events, rebalance decisions, or anchor-finalization events; those
are reported only where observable from returned cards.

`ReaderContractLayoutInputs.splitStress()` is a P03-only declaration using the
same verified Lexend 400/600/700/900 assets. Relative to `standard()`, only the
logical-surface height (`844→300`), viewport height (`844→300`), and recorded
card-body height (`680→58`) change. All widths, safe-area, scale, locale,
direction, font/checksum, accessibility, brightness, and reading-setting
inputs remain identical. The real paginator splits long fixture source 7 into
four contiguous half-open physical ranges: `[0,58)`, `[58,125)`, `[125,191)`,
and `[191,198)`. Never compare identities between the standard and split-
stress declarations, and do not treat this variant as the final P05 layout
contract. Because production request ranges are source-index based, the split
partition isolates source 7 as `[7,8)` and exercises all four real physical
splits; it cannot start between those emitted text offsets.

The construction equality assertions are deliberately ordinary `isNull`
mismatch assertions. Current independently packed behavior makes some of them
fail, so their focused commands exit nonzero. Do not skip them, invert them,
or replace the dynamic full-range reference with per-order output. Structural
ownership/coverage assertions are separate and can remain green while
physical-card equality is red.

### P03 cache-order characterization and failure ledger

`pagination/reader_card_paginator_cache_order_test.dart` and
`pagination/reader_core_cache_order_harness.dart` exercise production
`DisplaySectionMemoryCache`, `SegmentedDisplayCacheService`, cache key and
signature models, and `ProgressiveDisplayState`. Each case owns a unique
`ReaderContractSandbox`, book/session/publication identity and disk root. The
harness never opens or clears a default path and does not reproduce memory
eviction, segment compatibility, serialization, paginator, or progressive
assembly policy.

The standard Lexend declaration is used on both sides of every comparison.
Two reviewed partition plans each exercise cold full range, cold segmented,
warm memory, warm disk, real memory-policy eviction with disk fallback, and
fresh-service reload. Every reference is a newly generated full request, and
every assembled result is published through production progressive state.
The disk service exposes no `close`; the supported lifecycle evidence is an
awaited write followed by fresh service instances over the same sandbox-owned
root and newly deserialized chunks.

Current results are 12/12 pass. The harness proves each real whole/segmented,
memory, disk, eviction/fallback and fresh-service record was found, then
observably rejects direct publication with
`canonicalRegenerationRequired`. Bounded source regeneration through the real
canonical session publishes into `ProgressiveDisplayState`, and the complete
visible text, source ranges, structural owners, canonical identities and
section/spine seams match the cold canonical sequence. The five historical
cache failure-ledger rows remain preserved as pre-repair evidence.

`pagination/p03_failure_ledger.dart` is the formal 23-row P03 ledger:
12 target-first, two forward/prepend, four singleton-expansion and five
historical cache failures. It records stable IDs, exact tests/requests/layouts, requirement
mappings, full divergence evidence, coverage, repeatability, repair owner and
prohibited shortcuts. `pagination/p03_failure_ledger_integrity_test.dart`
keeps passing evidence separate and validates ledger completeness; it does not
rewrite or delete historical failure evidence.

### Transactional canonical publication

`pagination/progressive_display_state_canonical_transaction_test.dart` uses
the real canonical paginator/session and `ProgressiveDisplayState` to cover
accepted initial, exact-target, append, prepend and replacement publication;
idempotent replay; stable committed/target rebasing; atomic source/display
maps; immutable append prefix and prepend suffix; and fail-closed gap, overlap,
duplicate, reorder, cross-section, continuation, identity, compatibility,
provisional, stale, cancellation, committed-card and injected-error paths.
Rejected outcomes expose no cards, continuation, cache-write authority or
checkpoint/settlement authority and preserve the prior serialized state.

### Layout and font environment

`support/reader_contract_layout_environment.dart` provides:

- `ReaderContractLayoutInputs`, an immutable, byte-for-byte diagnostic declaration of logical surface, device-pixel ratio, viewport, safe area, reader card-body dimensions, text scaler, locale, direction, reader family, weights, font asset paths, declared metric identity, line/strut inputs, controls visibility, brightness and accessibility/media-query inputs;
- `ReaderContractBundledFont`, which verifies and loads only root-bundle assets with `FontLoader`; and
- `ReaderContractLoadedFont`, readiness evidence that every declared asset path and SHA-256 identity completed before the environment becomes ready; and
- `ReaderContractLayoutEnvironment`, which blocks Google Fonts runtime fetching, loads the declared local font before reporting ready, applies Flutter test-view state, wraps a widget with explicit locale/direction/media/theme state, and restores the captured test globals on `close`.

`ReaderContractLayoutInputs.standard()` is the controlled P03/P04 Lexend environment. Production defaults `ReadingSettings.fontFamily` to Lexend regular; its reader card uses w600 for list/structural text, w700 for inline bold and w900 for headings. The smallest corresponding static normal assets are bundled at `assets/fonts/reader_contract/` and declared as ordinary root-bundle assets in `pubspec.yaml`. The test support registers the exact bytes only under the host-only `NaloriReaderContractLexend` alias, so this does not declare or alter production's `GoogleFonts.lexend` runtime family.

Asset provenance, the upstream SIL Open Font License 1.1, original Google Fonts API filenames and the verified SHA-256 value for every binary are in `assets/fonts/reader_contract/PROVENANCE.md` and `assets/fonts/reader_contract/OFL.txt`. The checksums are asset identities, not resolved glyph-metric identities or a P05 layout fingerprint.

Construct and tear down the standard environment like this:

```dart
final environment = await ReaderContractLayoutEnvironment.install(
  tester,
);
addTearDown(() => environment.close(tester));
await tester.pumpWidget(environment.wrap(child));
```

Installation sets `GoogleFonts.config.allowRuntimeFetching` to false before it loads any asset. It reads each declared weight exclusively through `rootBundle`, verifies its SHA-256 before registration, then waits for `FontLoader.load`; a missing/undeclared root-bundle asset, incomplete weight declaration or corrupt byte stream fails clearly before readiness. `wrap` applies the same host alias to its explicit `ThemeData`. There is no Google Fonts request, device-file lookup, Ahem, generic family or developer-machine fallback path. Tests may not call the `@visibleForTesting` corrupt-bundle hook outside this support self-test.

`close` restores mutable Flutter test-view/platform-dispatcher inputs and the prior Google Fonts fetching setting. Flutter does not expose unregistration for a `FontLoader` family, so the fixed immutable host alias remains process-registered for the test process; it must never be reused with different bytes. This is not a resolved metric identity. Current production exposes only a declared typography-profile identity, not resolved glyph/metric identity; P05 must connect this declaration to a real measure/render metric contract.

`controlsVisible` is a recorded input only. It does not claim that the current reader’s controls change its card-body measurements in the same way as later production layout tests will establish.

### Per-test storage sandbox

`support/reader_contract_sandbox.dart` provides `ReaderContractSandbox.create()`. It allocates one unique, explicit system-temp root and book/session/publication identities per test. Always register awaited teardown immediately:

```dart
final sandbox = await ReaderContractSandbox.create();
addTearDown(sandbox.close);

final checkpointStore = sandbox.checkpointStore;
// Use only sandbox.fixtureOutputDirectory and the exposed sandbox stores.
```

`close` closes every created checkpoint store, clears only sandbox-owned service roots, resets the in-memory preferences adapter, then deletes the exact allocated temporary root. It refuses a non-temp deletion target and reports remaining paths if deletion fails. Do not call a default production store or `BookCacheService.clearAll()` from a sandbox: the latter currently also clears a default-path lazy-index store.

| Test control | Production boundary replaced/configured | What remains real | What this control can prove | What it cannot prove |
| --- | --- | --- | --- | --- |
| `fixtureOutputDirectory` | Test-only EPUB fixture output path | Fixture assembly and archive files | Fresh fixture-file location per test | Network/download behavior or reader opening |
| `wholeCache` | `BookCacheService.testing(cacheDirectory: ...)` | Production whole-cache serialization | Files and reads stay beneath a unique root | Whole/segmented cache equivalence or default-path clear behavior |
| `segmentedDisplayCache` | `SegmentedDisplayCacheService(rootDirectory: ...)` | Production segmented-cache serialization | Isolated segment files and payload reads | Paginator correctness or cache acceptance policy |
| `memoryDisplayCache` | A new `DisplaySectionMemoryCache` instance | Production in-memory cache implementation | Process-memory state is not reused by the test | Cross-process persistence |
| `checkpointStore` | `ReaderCheckpointStore.forTesting` with a unique SQLite file | Production checkpoint schema, journal/store code and SQLite reads/writes | Close/reopen of the same temporary database and sandbox separation | ReaderScreen settlement, lifecycle flush ordering or OS/device durability |
| `preferences` | `SharedPreferences.setMockInitialValues` platform adapter | Preference key/value call surface | Tests start without default preferences and cannot see another sandbox’s seeded value | Operating-system preference durability or platform plugin behavior |
| `lazyIndexStore` / `derivedIndexStore` | Existing directory-taking constructors | Production index-store implementations | Future navigation tests have isolated index roots | That current ReaderScreen injects these instances or uses their data at the right lifecycle point |

The SharedPreferences mock is a process-global test-framework adapter. Do not run sandboxes concurrently or use it to claim device persistence. The sandbox never opens production default user-data paths; if a production service lacks a configurable root, leave that boundary unavailable and document the seam rather than substituting a fake.

### Explicit asynchronous controls

`support/reader_contract_async.dart` provides:

- `ReaderContractGate<T>`, a typed one-shot boundary gate. `wait` records entry and holds completion; `release`, `fail` or `close` explicitly resolves it; and
- `ReaderContractEventProbe`, a per-test chronological event log carrying optional book, session, intent, generation, publication and card-identity evidence. It can require an event/order or require a named event to be absent with immediate diagnostics.

Use a gate only at an actual injectable production boundary once one exists:

```dart
final probe = ReaderContractEventProbe();
final gate = ReaderContractGate<Result>(label: 'named-production-boundary', probe: probe);
final operation = gate.wait(evidence: evidenceFromTheRealBoundary);
await gate.entered;
gate.release(result, evidence: publicationEvidence);
expect(await operation, result);
```

Gates and probes are not a second coordinator, navigation state machine, controller-settlement flag or fake clock. They cannot prove that production accepts/rejects stale work; later tests must make that assertion against real production state and use the probe only as causal evidence. Closing a gate produces deterministic completion errors, and callers that started an operation must await it during teardown.

The paginator is directly callable and retains the production scheduler and
checkpoint/cancellation callbacks, but no `ReaderContractGate<T>` is connected
to it: pausing release would add a second scheduling boundary and alter ordering.
Controller attachment/display publication/settlement and persistence-completion
events remain unavailable P07/P09 seams rather than simulated behavior.

Do not misuse this support by:

- replacing the declared Lexend bytes, using a system/Ahem/generic font, or reusing the host alias with different bytes and then treating fallback text as reader-font evidence;
- using layout declarations or controls visibility as a physical-card-count expectation;
- calling default cache clear methods, a default database path, or device preferences from a sandbox test;
- treating mocked preferences as durable storage;
- using `Future.delayed`, wall-clock sleep or repeated `pumpAndSettle` to make a gate test pass; or
- recording probe events from a fake coordinator and claiming production stale-work or controller-settlement proof.

Connected evidence now includes P03 construction-order and cache-order tests
using the extracted paginator and the same Lexend declaration. Planned later
connections are: measure/render identity in P05; cache equivalence in P06; real
store lifecycle in P07; and actual publication/navigation evidence in P09.

### P05 immutable layout-contract design reference

`docs/development/nalori-reader-layout-contract-design.md` is the normative
documentation contract for future P05 layout tests. It defines one immutable
session/generation `ReaderLayoutContract`, one per-source-block
`ResolvedReaderBlockLayout`, all-four-side stable `viewPadding` geometry,
source/captured direction resolution, exact used-size text-scale responses,
terminal observable font-metric evidence, shared structural box/span specs,
separated layout/source/pagination/renderer compatibility identities, and
strict finite binary canonical encoding. At CHANGE-023 this was design-only
evidence; the P05-003 production implementation and parity gate are documented
below. The test-only Lexend hashes remain asset—not runtime
resolved-metric—evidence.

### P05 deterministic production font gate

`layout/reader_font_evidence_gate_test.dart` exercises the production
`ReaderFontEvidenceGate`, manifest catalog, canonical encoder and real Flutter
`TextPainter`. The application ships 74 descriptor-matched static TTF files
for all eight reader choices under `assets/fonts/reader/`; the separate
`assets/fonts/reader_contract/` Lexend files remain controlled test-only asset
evidence. Reader typography never asks Google Fonts to fetch a font.

Delivery evidence is session-level. Source repertoire/metric evidence belongs
to the exact stable canonical source unit or range-keyed slice being resolved,
never whichever neighboring sections happen to occupy the mutable reader
window. Source input is ephemeral, hashed incrementally, limited to 2,048
UTF-16 units per exact slice, and absent from serialized evidence. Each capture
uses 11 role requests, at most six sizes, two widths and 33 TextPainter runs;
it repeats observations without delays and requires byte-identical results.
The LRU retains at most 25 records, 32,768 bytes each/819,200 bytes total.

The gate remains separately callable, and P05-003 makes the shared paginator/
renderer contract consume it. Only `readyTerminalBundled` has layout authority.
Opaque glyph fallback observations name no face; missing assets, digest/
coverage failures, unstable metrics, cancellation and staleness are typed
no-authority outcomes. RISK-006 remains open for P05-007 transition evidence.

### P05 shared production layout contract

`layout/reader_layout_contract_shared_test.dart` is the 34-case focused
P05-003 contract/parity gate. It uses the production font gate, immutable
contract builder, block/card resolvers, measurement/render adapters and real
`ReadingCard`/table/preformatted widgets. It covers F001–F211 exactly once,
effective settings and nonlinear used-size scaling, all-four-side geometry,
explicit LTR/RTL/alignment, paragraphs/headings/rich spans/footnotes/lists,
publisher layout, decoded table spans, Roboto Mono preformatted layout, fixed
image evidence, Speed Reader/selection/paint-only invariance, typed
font/image/stale rejection, deterministic identities and retained-state
bounds.

`layout/reader_layout_construction_order_smoke_test.dart` drives the canonical
production paginator/session with the new contract through full, repeated
forward, target-first and bounded backward construction. It requires identical
ordered source slices, canonical card signatures and physical-layout
fingerprints. `layout/reader_layout_standard_transition_test.dart` records the
frozen standard fixture's old/new boundary and signature transition without
editing a P03/P04 fixture or oracle. P05-007 still owns the exhaustive P03
matrix and reviewed oracle transition.

### P05 transient-control and stable-safe-area invariance

`layout/reader_transient_state_invariance_test.dart` is the focused four-case
P05-005 production seam. It uses the real immutable contract builder, terminal
font gate, block/card resolvers, canonical paginator session, progressive
publication boundary, `ReadingCard`, and cached `ReadingCardDeck`. Its fixed
390×420 standard deck uses `Scaffold(resizeToAvoidBottomInset: false)` and
explicit, bounded test pumps only; it does not use `pumpAndSettle` or an
arbitrary delay.

The 14-transition repeated transient sequence covers controls/overlays,
keyboard `viewInsets`, active/preview changes, cached-deck programmatic
transform, selection/link/annotation paint state, fixed bookmark/chapter/
progress reservations, and active/paused Speed Reader cursor/WPM plus lyrics
and window modes. It asserts byte-identical contract identity/body geometry,
ordered block/card layouts, ordered canonical source slices, physical-card
signatures, and accepted publication state. Transient transitions cause zero
pagination operations and zero publication/checkpoint/cache-write authority
changes. A stale old-layout candidate and an incomplete candidate both leave
the newer accepted display authority byte-identical.

Stable raw `viewPadding` is deliberately different: bottom `18→42` reduces
body height by 24, top `24→39` by 15, left `3→17` reduces body width by 14, and
right `5→21` by 16; every change has a different immutable identity. Unchanged
stable padding with a changed keyboard `viewInsets` is byte-identical. The
cached deck contains zero old-preview cards after a genuine safe-area contract
replacement. This is narrow standard-deck evidence only: P05-007 still owns
the complete U-01/U-02/U-10 probes, one-field matrix, late-font transition and
complete P03 construction-order rerun.

### P05 typed compatibility classification

`layout/reader_compatibility_classifier_test.dart` exercises the pure
`ReaderCompatibilityClassifier` over typed F195–F208 canonical evidence. The
production model separates `LayoutMetricsIdentity`,
`SourceCompatibilityIdentity`, `PaginationAlgorithmIdentity`,
`RendererLayoutIdentity`, and `ReaderCompatibilityIdentity` from the existing
legacy strings still consumed by paginator/card/cache/checkpoint paths. This
task intentionally does not wire the classifier into those paths.

Evidence must be complete, byte-canonical, digest-consistent and supported
before comparison. The decoder rejects malformed/trailing/out-of-order fields,
invalid finite values, stale component digests, inconsistent F208 links and
unknown revisions fail closed. Results use lowercase snake-case reason codes
and a fixed dimension order: layout metrics, source compatibility, pagination
algorithm, renderer layout. Results retain diagnostic fingerprints only; they
retain no source text or mutable indexes and expose no cache, checkpoint,
publication or settlement authority.

`exact_compatible` means only all four authoritative identity layers match.
It permits later exact-reuse/card validation, never semantic migration; a
missing requested physical-card signature stays an exact miss. Genuine single
or compound differences are advisory-only semantic-migration candidates. P06
owns canonical cache/card validation and migration; P07/P08 own real restore,
semantic containment and checkpoint consumption. Book identity is intentionally
not a layout metric or classifier input; later consumers retain book-scope
isolation checks.

### P04 final-gate contract (independent sign-off complete)

`pagination/reader_card_paginator_p04_final_gate_test.dart` is the preserved
`TASK-P04-008` evidence gate. It uses fixed seeds `40400801`–`40400812`: ten
legal fixture construction orders and two isolated real-cache orders. For the
same seed it compares regenerated plan JSON, complete visible text and ordered
canonical source slices/owners/roles, card identities/signatures, continuation
chains, work diagnostics and retained state. It uses only the real parser,
canonical paginator/session/index/identity builder,
`ProgressiveDisplayState.publishCanonical`, controlled Lexend layout and
sandboxed production cache services. Do not replace a rejected legal plan with
an invalid-input rejection and count that as equivalence.

`CHANGE-20260908-019` corrects the two failures preserved by
`CHANGE-20260908-018`. The append transaction now uses the accepted
previous-finalized/frontier boundary as physical publication authority while
leaving `nextSourceCursor` as next-unconsumed input evidence. Seed `40400802`
therefore publishes the source-4-through-source-7 card after the source-2/3
target card even though its predecessor continuation has advanced input to
source 5. Frontier candidates are normalized and measured from stable source
slices at construction and resume; strict reconstruction rederives split,
table, structural, rich, list and paragraph evidence from the pinned snapshot,
uses stable ownership digests, and still rejects altered evidence. No source
text is encoded.

`CHANGE-20260908-020` corrects the next two preserved defects without changing
the gate. A legal regenerated prepend now proves the accepted committed card by
stable identity, ordered source ownership and intervals, visible content,
structural ownership/roles, and physical cursors; transient display/window,
request and ordinal hints are excluded. The backward proof continuation may
extend through successor evidence, while the accepted forward continuation,
stable anchor, committed card and suffix remain byte-equivalent. Seeds
`40400802`–`40400810` now accept the same canonical result, while the existing
content, ownership, anchor, seam, stale/cancelled and continuation-corruption
rejections remain atomic.

Bounded target generation now treats an internal request-exhaustion frontier as
private provisional state. It resumes only its validated continuation while the
high-level 110-entry envelope remains, obtains the successor evidence needed to
finalize exact containment, and otherwise returns a typed no-authority restart
outcome. It never exposes or publishes a provisional or nearest card.

The two cache seeds remain green: legacy warm-memory and fresh-service records
are observed, fail closed as publication authority, and regenerate from
source. This is P04 rejection/regeneration evidence only; real compatible
record reuse, cache format/migration and byte budgets remain P06/P11.

The distant synthetic case is boundedness evidence only, not parser or EPUB
coverage. It creates 320 ordinary `BookChunk` sources in three sections,
targets source 280 and permits eight sources per advancement. The unchanged
gate reaches operation 36/source 267 through eight-source-or-smaller
operations, retains at most 25 checkpoint records and 87 resident cards, then
uses 17 entries of bounded target work to return a finalized card containing
source 280. Peak provisional state is two candidates/six coalesced entries and
zero copied source text.

`CHANGE-20260908-021` completes the independent evidence-only sign-off. Three
identical invocations of the unchanged final-gate file each passed 3/3 with no
failures or skips and reproduced the same normalized 38-line plan/work/
retention evidence. The complete focused P04 suite passed 69/69, the unchanged
P03 matrix passed 57/57, frozen P02 parity plus fixture/parser controls passed
9/9, scoped analysis reported no issues, and the final-gate/P03 SHA-256 values
remained unchanged. Fixture/recovery work peaked at 20 entries, distant-target
work at 17, per-advancement work at 8, private predecessor discard at 5,
frontier candidates/entries at 2/6, retained continuations at 25, resident
display cards at 87, and copied continuation source text at zero. P04 is
complete at 8/8; P05 entry criteria are met, but P05 has not started.

The reviewed fixture sequence remains nine standard-layout cards with source
memberships `0–1`, `2–3`, `4–7`, `8`, `9–10`, table source `11`, `12–15`,
`16`, and `17–19`. Under split stress source 7 remains exactly `[0,58)`,
`[58,125)`, `[125,191)`, `[191,198)`. Table source 11 retains authored
UTF-16 `[0,136)` and canonical body-row `[0,1)` ownership. Fixture files,
XHTML, authored oracles and existing P02/P03 expectations are frozen for this
gate.

### P05 final parity/fingerprint gate

`CHANGE-20260910-029` completes `TASK-P05-007`. The layout tests cover every
F001–F211 field exactly once and assert its typed downstream classification,
including exact binary64/subpixel behavior, negative-zero normalization,
finite-value rejection, effective-value equivalence, deterministic ordered and
semantic collections, strict canonical decoding and F208 recomputation.
U-01–U-10 run through production measure/render/font/image/deck paths. The two
proved P05 conformance defects were corrected at their earliest shared
boundaries: `ReadingCard` now paints its border as a zero-inset overlay, and
the shared image resolver atomically recomputes byte and metric digests before
accepting terminal evidence.

The shared P03 support oracle now projects the canonical P05 contract and the
nine independently reviewed physical signatures from CHANGE-026. All nine
standard source ranges remain unchanged; only physical identity changes for
the documented F001–F211 contract/evidence fields. Construction seeds, plans,
visible source, structural ownership and the P04 final gate remain frozen.
The CHANGE-029 final focused P05 gate passed 161/161; after the bounded
empty-repertoire correction its current focused gate passes 165/165. Both
complete P03 runs pass 57/57,
their normalized evidence is byte-identical, the unchanged P04 gate passes
3/3, and frozen P02 controls pass 9/9. P05 owns no cache, checkpoint,
publication, settlement, restoration, navigation, persistent-format or
migration authority.

### P06 canonical display-cache contract

`docs/development/nalori-reader-canonical-display-cache-contract.md` is the
P06-001 authority for canonical segment keys, records, seams, continuations,
compatibility outcomes, and migratability. The completed P06-002 boundary
`pagination/canonical_display_segment_admission_test.dart` uses the real P04
paginator/snapshot and P05 layout contract to exercise the shared logical
memory/disk admission codec. It verifies the 13-component key, 32-field
record, 11-field cards and all 16 no-authority outcomes; legacy whole,
segmented, and memory records remain fail-closed `canonicalRegenerationRequired`
inputs.
`CHANGE-20260911-031` restores the external P04/P05 control: an exact source
slice whose final shared renderer repertoire is canonically empty now carries
explicit terminal zero-observation evidence while retaining bundled delivery
and request-catalog validation. Structural glyphs and layout-significant
whitespace still require the normal complete font matrix. The 48-source
checkpoint cadence again reaches terminal installation with zero cards and
zero metric runs. `CHANGE-20260912-032` completes `TASK-P06-002` after its
7/7 focused admission suite and the repaired 13/13 P04 control.

`pagination/canonical_display_cache_equivalence_test.dart` completes the
controlled P06-003 proof. It builds derivative records only from pinned P04/P05
live constituents after accepted publication, then sends memory records and
fresh-session temp-root disk bytes through the same strict admission,
contextual anchoring and `publishCanonical` transaction. Cold generation,
warm memory, reopened disk, memory eviction with disk reload, full derivative
eviction, rejected-candidate regeneration, mixed cached/regenerated regions,
and forward/target-first/bounded-backward orders compare the complete P03
evidence projection. Two complete internal runs normalize identically to
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`.
The unchanged complete P03 matrix remains 57/57 with frozen normalized evidence
`fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`.
The controlled disk store has no default application path or ReaderScreen
writer; production activation, migration and final retention budgets remain
P06-006 through P06-007.

`pagination/canonical_display_cache_invalidation_test.dart` completes
P06-004's scoped derivative-only invalidation proof. It uses real whole,
segmented, section-memory and chapter-layout cache services under explicit
sandbox roots. The shared policy maps all 16 admission outcomes to a typed
no-op, exact memory eviction, exact disk invalidation, same-scope quarantine,
retained future record, migration deferral or failed-safe receipt. Exact
legacy records remove only their deterministic payload/reference; corrupt
records quarantine only the exact current-scope derivative; future and
potentially migratable records remain untouched. It proves byte-equivalent
parsed source, EPUB, cover/metadata, stable-location, checkpoint/journal,
bookmarks, highlights, notes, saved words, character data, search/Book Memory,
settings and unrelated books, plus idempotence, path rejection, injected
failure and zero publication/checkpoint/settlement authority. It does not
activate live cache writes/reuse, migration, final eviction policy or a new
persistent format.

`pagination/canonical_display_cache_migration_test.dart` completes P06-005's
controlled migration proof (7/7 focused cases). It uses the real strict codec,
admission validator, compatibility classifier, source snapshot, paginator, P04
publication transaction, record builder, P06-004 invalidation service and
controlled memory/disk roots. The field-level matrix rejects every current
whole/segmented/section-scoped/section-memory/chapter-layout/raw-range,
checkpoint/stable-location and continuation-only candidate as a typed safe
miss. A strict canonical candidate can regenerate only after its trusted scope,
source linkage, stable semantic interval, ordered ownership, continuation and
current P05 evidence validate. Layout-only, renderer-only, pagination-only and
ordered compound changes regenerate once, recompute all physical values and
signatures, preserve semantic ownership through changed card boundaries, pass
current P06 admission and byte-match ordinary current-contract cold generation.

No production source/parser correspondence resolver exists. Source/parser
changes, repeated text and ambiguous correspondence therefore produce a typed
safe miss rather than a visible-text search. Future revisions remain retained;
incomplete/corrupt records never migrate; stale, cancelled, budget and
replacement-failure paths do not mutate accepted display or old controlled
storage. The P06-004 controlled replacement plan is the sole deletion handoff,
after new strict validation and retention. Observed migration maxima are
assessment/result 268/32 bytes, old/new record 15,376/14,805 bytes, two source
units/cards, two physical-boundary changes, one compatibility dimension, zero
remap candidates, one retained/replaced record and one attempt. Old-card and
source-text identity copies, mutable-index authority, exposed partial records,
protected-data mutations and live-cache writes are zero. This is not a live
cache activation, new persistent format, atomic-write/recovery protocol or
P06-006/P06-007 implementation.

`CHANGE-20260913-036` independently audits P06-004/P06-005. Focused red/green
regressions prove that prefix-colliding book IDs cannot obtain section-memory
eviction receipts, only strict-validator-minted admission results can authorize
migration assessment, a stale/cancelled request observed after either
asynchronous replacement step cannot reach old-record invalidation, and a
replacement must remain anchored to the old segment's stable start cursor.
The resulting P06 controls remain 7/7 admission, 4/4 equivalence, 21/21
invalidation and 7/7 migration. P06-003 remains a dependency control; P06-006
and P06-007 were unstarted at that audit point. CHANGE-037/038 below supersede
that historical status.

`pagination/canonical_display_cache_budget_test.dart` completes P06-006 and
P06-007 without changing the frozen P02–P05 fixtures or oracles. Its six-test
budget/pinning group proves every record, codec, ratio, manifest, aggregate,
work, chain, restart, pin and temporary-byte boundary below/at/above its
release ceiling; overflow/contradiction rejection; stable current and unique
adjacent pins; deterministic unpinned eviction; long-traversal bounds;
previous-record preservation; ordered reload/regeneration; protected-byte
equivalence; and zero publication/checkpoint/settlement authority on failure.

Its nine-test physical-rollout group uses only sandbox-owned temporary roots.
It exercises truncated and malformed containers/manifests, corrupt checksums
and bindings, legacy/current/future versions, partial writes, every
flush/rename/replace boundary, missing payloads and orphan files, stale and
cancelled generations, same-key and cross-book writers, rename and symlink
races, path/sibling-prefix collisions, rollback, failed migration replacement,
memory/disk/full eviction, pinned pressure and a fresh production-shaped
service reopen. The end-to-end proof is cold P04 generation → canonical
publication → publication-authorized v4 write → service close/reopen → strict
disk admission and contextual anchoring → `publishCanonical`, with identical
visible text, cards, slices, F209/F210/F211, signatures, boundaries,
continuation and final order. All failure paths regenerate from source without
requiring cache deletion.

The final P06 groups pass 6/6 and 9/9. Admission, repeated equivalence,
invalidation and migration remain 7/7, 4/4 twice, 21/21 and 7/7; the final
combined focused P06 gate passes 54/54. The full P03 matrix remains 57/57 with
normalized hash
`fc490459246d163d7ea13ff8c6eba41a4a37b255bae286e7cdbec09b8d738b10`,
and P06 equivalence remains
`714984de61d6068fbfe11f2dce06469af583eb8edab60bf8622c2678b8f6975f`.
P06 reached 7/7 before device evidence reopened its exit gate. The
`CHANGE-20260914-039` correction adds the production-parser table, terminal
single-flight generation, cooperative paginator, publication-before-background,
detached cache-write, restart-evidence and retained-memory regressions in
`regression/reader_device_regression_test.dart`, with queue and repository
controls in their production service test files. P06 remains 7/7 with status
`CORRECTION_IMPLEMENTED_NOT_DEVICE_VERIFIED`; P07 has not started and its P06
entry dependency is unmet until the owner device rerun succeeds.

## Fixture update procedure

Fixture source files are generated test data only; no external text is copied. Change a fixture only by updating its visible EPUB component source, manifest source checksum, structural evidence, source oracle and mapped requirement rationale together. The focused fixture test must pass after two independent logical builds. Do not add card signatures or card counts until later approved phases establish canonical pagination.

The existing test/fixtures/books/feature_rich_lazy_reader.epub remains historical/current coverage evidence. It is not a trusted reader-contract fixture unless a future task supplies its human-readable components, provenance, checksum and source-range oracle under this manifest contract.
