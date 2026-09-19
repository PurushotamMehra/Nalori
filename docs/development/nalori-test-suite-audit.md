# Nalori automated test-suite audit

Audit date: 2026-08-26. This is a review of the current working tree, which already contained extensive modified and untracked source and test work. Existing tests were treated as evidence, never as product approval. No production source, test, fixture, configuration, dependency, cache, or lockfile was changed for this audit.

## 1. Executive verdict

**No. The current suite is not a trustworthy release gate, and reader tests are not a trustworthy reader-regression gate.** A passing run would show that many isolated helpers, serialisers, cache records, and widget harnesses still behave as currently coded. It would not show that an actual reader session paginates canonically, settles the visible card, persists it, switches books, and restores that same card.

In particular, a pass does **not** imply that last-read restoration, pagination, cache equivalence, or navigation work. There is no production-path test of:

```text
open book → settle visible card → persist checkpoint → close reader
→ open another book → reopen original → exact card identity and visible text
```

That is a blocker-level gap before this suite can be used to release repairs in those areas.

At file level, 3 of 94 test files are narrow `KEEP`s and 14 are `KEEP_WITH_MINOR_IMPROVEMENT`s (about 18% useful as narrow checks). 21 are `REPLACE`, 9 are `REWRITE`, one is `DELETE_FALSE_CONFIDENCE`, and one needs `INVESTIGATE_FLAKINESS`; 45 encode non-reader or unapproved behaviour and are `PRODUCT_DECISION_REQUIRED`. These are file-level signals rather than a quality percentage: the 898 Dart test declarations are very unevenly distributed, and a high count of unit assertions is not high reader coverage.

The checkpoint journal's revision/epoch tests are comparatively strong. They do not rescue the release gate because they stop before `ReaderScreen`, its asynchronous exact-restore fallback, the real controller, and persistent multi-book lifecycle.

## 2. Audit scope and methodology

### Inspected

- `test/` in full: 93 Dart test files, the Python tool test, support helpers, mocks, documentation, and the single EPUB fixture.
- The absence of `integration_test/` and `test/goldens/`; no package-local tests were found under `packages/epubx/`.
- Reader production paths in `ReaderScreen`, `DisplayGenerationCoordinator`, `ProgressiveDisplayState`, `LazyBookSession`, cache services, `ReaderOpenService`, `ReaderCheckpointStore`, source-location models, and reader rendering widgets.
- Test-only seams, `@visibleForTesting` APIs, diagnostic environment switches, `pubspec.yaml`, the Android CI workflow, README commands, and relevant history. The dominant reader-test additions arrived in the five “Complete lazy random-access reader phase” commits (2026-07) and are also present as current uncommitted work.

### Test configuration and CI inventory

- Test-only dependencies declared in `pubspec.yaml`: Flutter's `flutter_test`, `archive`, `image`, `flutter_lints`, `mockito`, `build_runner`, `mocktail`, `sqflite_common_ffi`, and `sqlite3_flutter_libs`. `mockito`, `mocktail`, and `build_runner` are declared but the checked-in tests use only the one unused mocktail wrapper; no generated mocks are present. `integration_test` is neither declared nor present.
- `.github/workflows/android-ci.yml` runs `flutter pub get`, a repository-wide formatter check, `flutter analyze`, `flutter test`, and Android builds. Its sole test command is the unsharded `flutter test`; it does not run the Python catalogue test, integration tests, goldens, repeatability checks, or a reader lifecycle suite.
- README documents `flutter test`. `test/TESTING_STRATEGY.md` also documents old `test/widget/` and `test/integration/` commands and a coverage target; neither matches the current tree. No `dart_test.yaml`, custom golden configuration, test script, or integration directory exists.

### Commands and runtime evidence

| Command | Result |
| --- | --- |
| `rtk flutter --version` / `rtk dart --version` | Did not yield versions. Flutter attempted to update its engine stamp and failed: `/home/uttam/Desktop/Code/flutter/bin/internal/update_engine_version.sh: line 71: .../cache/engine.stamp.tmp.16: Read-only file system`; line 78 similarly failed for `engine.realm`. |
| `rtk flutter test` | One full non-device attempt. It reached the runner counter `+81` in about 9 seconds without a failure, then produced no further runner output before the 30-second execution capture ended. The transcript contains no final summary or exit status, so passed/failed/skipped/timed-out totals are **indeterminate**, not a pass. No test process remained afterwards. |
| `rtk flutter test test/widgets/reading_card_renderer_consistency_test.dart --reporter expanded` | Targeted investigation of the file shown at the end of the full-run transcript: **3 passed**, 0 failed/skipped/timed out, about 1 second. A second and third rerun were not justified after the focused pass; the full-run capture limitation remains recorded. |

Static enumeration found 898 Dart `test`/`testWidgets` declarations: 760 unit-style declarations and 138 widget declarations. The separate Python unittest file has 2 tests and is not run by `flutter test`. No integration or golden test is present. The full command was not rerun, in accordance with the one-full-suite limit.

### Limitations

The Flutter SDK cache is read-only for version reporting, and the tool transcript did not retain a final status for the one full invocation. Runtime claims below are therefore explicitly marked as static, focused-runtime, or unavailable. I did not run devices, emulators, integration-device tests, formatters, generators, coverage, or any command that changes product/test artefacts.

## 3. Test-suite map

### By test type and module

| Area | Files | Dart declarations | Type | Main disposition |
| --- | ---: | ---: | --- | --- |
| Root reader/quote tests | 5 | 53 | 1 unit-style, 4 widget | 2 `REPLACE`, 2 decision-required, 1 keep |
| `unit/models` | 10 | 138 | unit | persistence/source models useful; settings and annotation product policy unapproved |
| `unit/controllers`, `unit/ui`, `unit/utils` | 6 | 45 | unit | small pure checks; list/table parser expectations need replacement |
| `unit/screens` | 4 | 20 | unit/helper | none mounts `ReaderScreen`; core cases are replacements |
| `unit/services` | 50 | 525 | unit/service | cache/journal pieces useful; reader integration largely absent |
| `widgets` | 18 | 117 | widget | direct-component and bespoke-harness tests, not reader lifecycle |
| `tool` | 1 | 2 Python tests | other | catalogue generator only; excluded from Flutter CI |
| `integration_test` / goldens | 0 | 0 | — | absent |

### Recommended-action totals (94 files, including the Python test)

| Action | Files | Meaning in this audit |
| --- | ---: | --- |
| `KEEP` | 3 | narrow deterministic checks with an already-clear technical contract |
| `KEEP_WITH_MINOR_IMPROVEMENT` | 14 | preserve only at their current limited abstraction; strengthen assertions/fixtures |
| `REWRITE` | 9 | desired scenario, but synthetic or implementation-coupled |
| `REPLACE` | 21 | important area tested through the wrong abstraction/outcome |
| `DELETE_FALSE_CONFIDENCE` | 1 | helper assertion cannot establish its claimed production behaviour |
| `INVESTIGATE_FLAKINESS` | 1 | timing/settling-heavy widget file needs controlled repeatability evidence |
| `PRODUCT_DECISION_REQUIRED` | 45 | behaviour is encoded but not approved in supplied product contracts |

There were no files confidently classed as `DELETE_DUPLICATE` or `DELETE_OBSOLETE` without a product review. Some support files are unused and are candidates after that review (section 10), but are not test files being changed now.

## 4. Behaviour currently encoded by tests

### Approved or directionally aligned reader behaviour

- Stable source fields survive JSON and additive legacy migration.
- A stable source offset should prevail over a mutable display index after a genuine reflow.
- Reader-card identity includes ordered source ranges and structural block type.
- A journal should reject stale session/revision writes and preserve a pending exact checkpoint from a default page.
- Explicit user settlement, rather than preview, should be the persistence source.
- Lazy session navigation resolves chapters/anchors through source identity, and cache records are rejected on version/fingerprint mismatch.

These are only *directionally* aligned until the user approves the detailed contract and a production-path test proves them.

### Undocumented or product-policy behaviour

The suite fixes many UI and product choices without evidence of approval: density ratios (25/50/75/100), exact margins/reserves, font/theme palettes, quote-card layout, Speed Read pacing, card-depth work priority, colour choices, bookmark/note dialog interaction, Book Memory ordering, Gutenberg result treatment, and retention budgets. These are `PRODUCT_DECISION_REQUIRED`, not release requirements.

### Contradictory or unsafe behaviour

1. `reader_layout_metrics_test.dart` accepts “same text after card boundaries change” for a source offset. That is appropriate only after a genuine layout change. The approved contract requires the *same committed physical card* with an identical layout. The file never asserts the same-layout distinction.
2. `reader_checkpoint_store_test.dart` correctly says a same-layout partial publication must not downgrade to semantic restoration, but it invokes `ReaderCheckpointCoordinator` directly. `ReaderScreen` is never put through its cache miss/partial publication path, so the passing helper test cannot prevent the verified screen-level downgrade and rewrite.
3. `progressive_display_state_test.dart` calls prepend/append successful if source-index maps survive. It never compares card signatures or ordered source ranges, so it permits independently packed pagination islands that violate canonical seams.
4. `segmented_display_cache_service_test.dart` accepts deliberately separated cache islands and separately serialised synthetic chunks. That storage behaviour is not a proof that cold and warm pagination yield the same cards; it can coexist with the verified cold/warm disagreement.
5. `reader_navigation_settlement_test.dart` calls a small `PageView` harness and a coordinator with `String` pages. It calls the result a “real swipe,” but it bypasses `ReaderScreen`, generated display cards, checkpoint commit, and close/reopen. This is misleading nomenclature rather than product-path evidence.

### Obsolete architectural assumptions

`test/TESTING_STRATEGY.md` describes directories and files that do not exist (`test/widget/`, `test/integration/`, several old test names), recommends `integration_test` although it is not a dependency, and sets coverage targets despite no current coverage gate. It is a stale strategy document, not proof of test architecture. The per-book lazy-route preference remains a product decision; it should not be retained merely because `lazy_reader_route_service_test.dart` passes.

## 5. Full file inventory

Reliability labels below state the highest defensible value of the *current* test, not whether the feature matters. “Manual chunks” means production parser/layout/reader entry paths are bypassed.

| Test file | Module | Tests | Type | Production symbols exercised | Mocks / fixtures | Behaviour asserted | Reliability | Action |
| --- | --- | ---: | --- | --- | --- | --- | --- | --- |
| `test/quote_card_canvas_test.dart` | sharing | 8 | widget | quote/book canvas widgets | fixed payload, disabled font fetch | no overflow and template layout | visual policy, no golden | `PRODUCT_DECISION_REQUIRED` |
| `test/quote_card_preview_screen_test.dart` | sharing | 5 | widget | `QuoteCardPreviewScreen` | fixed payload | editor controls/style navigation | `pumpAndSettle`; unapproved UX | `PRODUCT_DECISION_REQUIRED` |
| `test/reader_layout_metrics_test.dart` | reader layout | 31 | unit | exported `ReaderScreen` metric/helper seams | fixed viewport, `TextPainter`, manual chunks | metrics, sentence ranges, reflow helpers, preparation policy | broad but helper-only and many arbitrary constants | `REPLACE` |
| `test/reading_card_note_save_test.dart` | annotations | 8 | widget | `ReadingCard`, note popups, quote callback | manual chunks/highlights | note dismissal/preview/save and icon colour | direct widget; timings; no durable projection lifecycle | `REPLACE` |
| `test/text_painter_test.dart` | typography | 1 | unit | Flutter `TextPainter` | none | empty-newline behaviour | deterministic platform primitive | `KEEP` |
| `test/unit/controllers/speed_read_controller_test.dart` | speed read | 12 | unit | `SpeedReadController` | fixed words | delay/pacing/restart policy | exact pacing is unapproved product policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/models/book_chunk_test.dart` | source mapping | 5 | unit | `BookChunk`, `ChunkSourceRange` | manual chunks | selection mapping and compact JSON | strong local mapping; no parser/render round trip | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/models/book_memory_entry_test.dart` | Book Memory | 2 | unit | `BookMemoryEntry` | maps | serialisation/defaults | no approved behaviour | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/models/book_metadata_test.dart` | library data | 14 | unit | `BookMetadata` | maps/timestamps | JSON, copy/equality/default fields | sound data check but persistence contract needs documentation | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/models/bookmark_test.dart` | annotations | 19 | unit | `Bookmark` | maps | JSON, naming/colour/legacy fields | undocumented annotation policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/models/highlight_test.dart` | annotations | 8 | unit | `Highlight` | maps | serialisation/range policy | undocumented product policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/models/quote_share_payload_test.dart` | sharing | 5 | unit | `QuoteSharePayload` | maps | payload construction | unapproved sharing policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/models/reader_position_session_test.dart` | reader settlement | 6 | unit | `ReaderPositionSession` | integers only | committed/preview/modal state | desired concept but no real controller/card identity | `REWRITE` |
| `test/unit/models/reading_settings_test.dart` | settings | 62 | unit | `ReadingSettings` | fixed colour/settings literals | themes, serialization, density/palette | many arbitrary visual constants | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/models/saved_word_test.dart` | dictionary | 13 | unit | `SavedWord` | maps | model persistence | unapproved UX/data policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/models/stable_book_location_test.dart` | source identity | 4 | unit | `StableBookLocation`, annotation models | fixed location | JSON/additive migration | good narrow compatibility check; no resolve path | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/screens/reader_annotation_projection_test.dart` | reader annotations | 9 | unit | exported `ReaderScreen` projection seam | manual windows/identities | highlight alias/projection | bypasses parser, actual annotations, and screen | `REPLACE` |
| `test/unit/screens/reader_card_depth_lazy_completion_test.dart` | reader priority | 2 | unit | `lazySectionPriorityForReaderReason` | string reason | priority mapping | asserts a helper only; caller can be wrong | `DELETE_FALSE_CONFIDENCE` |
| `test/unit/screens/reader_list_pagination_test.dart` | reader lists | 4 | unit | list helper seams | manual list chunks | fragment metadata/merge rules | no real packing or renderer | `REPLACE` |
| `test/unit/screens/reader_start_chapter_detection_test.dart` | reader open | 5 | unit | start-chapter helper | synthetic chapters | front-matter heuristics | desired idea, heuristic not approved | `REWRITE` |
| `test/unit/services/api_client_test.dart` | network | 1 | unit | API client | mocked HTTP | request/error result | endpoint/product policy undocumented | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/book_cache_service_test.dart` | whole cache | 11 | unit | `BookCacheService` | temp filesystem/manual display | schema/cache invalidation | storage only; no warm/cold pagination equivalence | `REPLACE` |
| `test/unit/services/book_memory_entry_service_test.dart` | Book Memory | 10 | unit | entry service | mock preferences | CRUD/filtering | product policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/book_memory_export_service_test.dart` | Book Memory | 2 | unit | export service | temp files | export format | product decision required | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/book_memory_service_test.dart` | Book Memory | 14 | unit | memory service | preferences/temp paths | persistence/search | product decision required | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/book_metadata_service_lazy_index_test.dart` | reader metadata | 2 | unit | metadata/lazy index | temp EPUB/cache | lazy index metadata | real service but narrow and fixture-built | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/book_preparse_service_test.dart` | reader background work | 6 | unit | `BookPreparseService` | temp files | queue/cancel priorities | coordinator isolated from screen | `REWRITE` |
| `test/unit/services/book_reader_theme_service_test.dart` | themes | 1 | unit | theme service | fixed palette | reader theme | unapproved visual policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/bookmark_service_test.dart` | annotations | 25 | unit | bookmark service | mock preferences | bookmark CRUD/colours | product policy and legacy indexes | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/card_depth_chapter_progress_service_test.dart` | reader progress | 21 | unit | card-depth progress | manual locations | chapter/page progress | display/card-index assumptions are not canonical truth | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/chapter_card_layout_service_test.dart` | reader pagination | 5 | unit | chapter layout cache | callback generator/manual pages | totals/cache invalidation | does not generate canonical cards | `REPLACE` |
| `test/unit/services/chapter_navigation_service_test.dart` | TOC navigation | 10 | unit | `ChapterNavigationService` | synthetic chapters/locations | ordering/deduping/next/previous | useful logic, no lazy+screen navigation | `REWRITE` |
| `test/unit/services/cover_palette_service_test.dart` | covers | 2 | unit | palette service | pixels | colour clustering | unapproved visual preference | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/derived_book_index_service_test.dart` | search/Memory | 13 | unit | derived index service | manual chunks/temp files | index/search/projection | cannot validate authoritative-vs-generated source content | `REPLACE` |
| `test/unit/services/dictionary_service_test.dart` | dictionary | 15 | unit | dictionary service | preferences/delay | lookup/saved words | real delay and unapproved feature policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/display_generation_coordinator_test.dart` | reader generation | 33 | unit | coordinators | `String` locations, completers | generation/intents/correction state | strong state-machine unit, not `ReaderScreen` | `REPLACE` |
| `test/unit/services/display_section_memory_cache_test.dart` | reader cache | 3 | unit | memory cache | hand-built ranges | compatible hit/LRU | never compares real cards or cold/warm result | `REPLACE` |
| `test/unit/services/epub_parser_chapter_test.dart` | EPUB parser | 7 | unit | parser extraction | temporary mini EPUBs | TOC/dialogue/inline/poem/table parsing | real parser, but narrow generated corpus | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/epub_parser_list_test.dart` | EPUB structured blocks | 12 | unit | lazy section parser/projection | inline XHTML | list semantics/authoritative offsets | critical but current synthetic projection assumptions | `REWRITE` |
| `test/unit/services/feature_rich_lazy_reader_fixture_test.dart` | EPUB/lazy nav | 6 | unit | `LazyBookSession`/repository | one generated EPUB | TOC, links, footnotes, image/table | real archive path; expected strings only | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/frame_budgeted_range_scheduler_test.dart` | reader scheduling | 7 | unit | range scheduler | deterministic tasks | slice/yield/cancel/preemption | clear local contract | `KEEP` |
| `test/unit/services/highlight_palette_service_test.dart` | annotations | 6 | unit | palette service | preferences | palette persistence | unapproved UX policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/highlight_service_test.dart` | annotations | 13 | unit | highlight service | preferences | CRUD/range operations | product policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/lazy_book_session_test.dart` | lazy reader | 22 | unit | `LazyBookSession` | generated mini EPUBs/temp cache | open, resolve, load, bounded ownership | real session, no card pagination/screen | `REWRITE` |
| `test/unit/services/lazy_epub_index_service_test.dart` | EPUB index | 8 | unit | index service | generated archives/temp cache | lazy index/resources/rebuild | good local persistence/index coverage | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/lazy_reader_cache_cleanup_service_test.dart` | reader cache cleanup | 3 | unit | cleanup service | temp roots | derivative-only deletion/races | good boundary, needs real roots contract | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/lazy_reader_route_service_test.dart` | reader routing | 1 | unit | lazy-route preference | mock preferences | per-book disable marker | whether fallback remains is unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/lazy_section_parser_equivalence_test.dart` | EPUB parser | 1 | unit | eager/lazy parser | generated EPUB | joined visible text equality | text equality ignores identity, styles, offsets | `REWRITE` |
| `test/unit/services/lazy_section_repository_test.dart` | lazy loading | 8 | unit | repository/cache | temp archives/cache | joining, retention, hydration/resources | no real reader or canonical display output | `REWRITE` |
| `test/unit/services/library_service_test.dart` | library | 3 | unit | library service | temp filesystem | library CRUD | product behaviour undocumented | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/open_library_metadata_service_test.dart` | metadata | 5 | unit | Open Library service | mocked HTTP/preferences | lookup/cache | external/product policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/parsed_section_cache_service_test.dart` | parsed cache | 18 | unit | parsed cache/retention | real temp filesystem | records, corruption, LRU, generation | good storage coverage; no parser-to-display equivalence | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/parsed_section_retention_policy_test.dart` | parsed cache | 3 | unit | retention registry | synthetic identities | recent-book protection | retention product policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/progressive_display_state_test.dart` | reader pagination | 12 | unit | `ProgressiveDisplayState` | synthetic `DisplayRangeResult`s | range append/prepend/remap | maps only; never physical card identity | `REPLACE` |
| `test/unit/services/public_domain_book_service_test.dart` | catalogue | 28 | unit | public-domain service | preferences/mock responses | browse/search/cache/paging | catalogue UX/policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/public_domain_catalog_database_test.dart` | catalogue DB | 9 | unit | database | sqlite FFI/temp DB | query/schema results | useful technical data check | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/public_domain_catalog_installer_test.dart` | catalogue install | 5 | unit | installer | sqlite FFI/temp artifacts | manifest/install validation | good local technical check | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/public_domain_download_service_test.dart` | downloads | 8 | unit | download service | mocked HTTP/temp files | progress/validation | product/network policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/quote_card_palette_service_test.dart` | sharing | 2 | unit | quote palette | settings | palette selection | unapproved visual policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/reader_character_match_service_test.dart` | reader annotations | 21 | unit | character matcher | manual chunks | declaration/match offsets | source-authority gaps remain | `REPLACE` |
| `test/unit/services/reader_checkpoint_store_test.dart` | checkpoints | 25 | unit | identity/store/coordinator | sqlite FFI/manual cards | identity, journal, restore protocol | store ordering strong; lifecycle path absent | `REPLACE` |
| `test/unit/services/reader_open_service_test.dart` | reader open | 5 | unit | open selection/service | synthetic locations plus temp EPUB | precedence/migration/lazy chapter | screen fallback and persistence path bypassed | `REPLACE` |
| `test/unit/services/reader_source_projection_service_test.dart` | source restore | 11 | unit | projection helpers | manual windows/chunks | reflow/bookmark/source mapping | important but no real parser/screen/cache | `REPLACE` |
| `test/unit/services/reader_structural_progress_service_test.dart` | reader progress | 16 | unit | progress/queue | manual locations | progress, snapshots, scrub | display index and helpers substitute production lifecycle | `REPLACE` |
| `test/unit/services/reader_text_boundary_service_test.dart` | reader splitting | 7 | unit | boundary service | fixed Unicode strings | sentence/word/grapheme boundaries | useful pure deterministic check | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/reading_settings_service_test.dart` | settings | 25 | unit | settings service | mock preferences | persisted defaults/values | policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/reading_stats_service_test.dart` | statistics | 21 | unit | stats service | real clock/preferences | streaks/totals | real-time and product policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/services/segmented_display_cache_service_test.dart` | reader cache | 23 | unit | segment cache | real temp FS/manual ranges | segment records, LRU, corruption | cache mechanism only; no canonical pagination | `REPLACE` |
| `test/unit/services/shared_lazy_section_work_coordinator_test.dart` | lazy work | 8 | unit | shared work coordinator | completers/identities | join/cancel/retry | deterministic local concurrency contract | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/services/user_education_service_test.dart` | onboarding | 2 | unit | education service | preferences | viewed-state persistence | product policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/ui/continue_reading_colors_test.dart` | UI | 4 | unit | continue-reading colour logic | fixed colours | derived accent colours | unapproved visual policy | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/utils/character_name_utils_test.dart` | reader characters | 2 | unit | name aliases | literals | alias heuristics | product policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/utils/contrast_utils_test.dart` | UI | 3 | unit | contrast helpers | fixed colours | foreground contrast | colour policy unapproved | `PRODUCT_DECISION_REQUIRED` |
| `test/unit/utils/final_layout_paragraphs_test.dart` | reader layout | 8 | unit | final paragraph mapping | fixed text/ranges | offsets/separators/gaps | useful source mapping, not final renderer packing | `KEEP_WITH_MINOR_IMPROVEMENT` |
| `test/unit/utils/reader_content_parser_test.dart` | structured blocks | 16 | unit | table/content parser | text fixtures | table detection/projection | parser duplicates presentation decisions | `REPLACE` |
| `test/widgets/add_book_sheet_test.dart` | library UI | 4 | widget | add-book sheet | fake callbacks | sheet interactions | unapproved UX | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/annotations_panel_character_declaration_test.dart` | annotations UI | 1 | widget | panel | manual declaration | listing rule | unapproved UX | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/book_memory_screen_test.dart` | Book Memory UI | 3 | widget | screen | mock preferences | tabs/filtering | unapproved UX | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/book_memory_source_detail_screen_test.dart` | Book Memory UI | 6 | widget | detail screen | manual previews | detail/expansion/navigation | bypasses actual reader source navigation | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/book_memory_writing_screen_test.dart` | Book Memory UI | 2 | widget | writing screen | manual preview | visual ordering | unapproved UX/timing | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/bookmark_edit_dialog_test.dart` | annotations UI | 4 | widget | bookmark dialog | manual colour state | palette/dialog behaviour | unapproved UX | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/chapter_panel_accessibility_test.dart` | TOC UI | 3 | widget | chapter panel | manual chapters | labels/focus/action | no actual target resolve/navigation | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/how_to_use_screen_test.dart` | onboarding UI | 1 | widget | how-to screen | none | rendered copy | unapproved content | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/public_domain_books_screen_test.dart` | catalogue UI | 16 | widget | books screen | fake service/completers | loading/search/pagination | callback timing and unapproved product UX | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/reader_copy_quote_connection_test.dart` | reader sharing | 5 | widget | quote route/share channel | platform-channel mock | copy/share UI flow | not reader location navigation | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/reader_navigation_settlement_test.dart` | reader navigation | 4 | widget harness | coordinator/correction scheduler | custom `PageView`, `String` pages | swipe/correction state | bypasses `ReaderScreen`, cards, persistence | `REPLACE` |
| `test/widgets/reader_typography_rendering_test.dart` | reader typography | 1 | widget | raw `RichText` | fixed width/font settings | painter/render height | not `ReadingCard`/screen measurement context | `REPLACE` |
| `test/widgets/reading_card_chapter_progress_test.dart` | reader card UI | 1 | widget | `ReadingCard` | manual chunk/progress | footer text | unapproved presentation | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/reading_card_deck_test.dart` | reader controller | 23 | widget | `ReadingCardDeck` | custom card builder/controllers | swipes, controller, stack | many fixed 100–650ms pumps and `pumpAndSettle` | `INVESTIGATE_FLAKINESS` |
| `test/widgets/reading_card_list_test.dart` | reader lists | 7 | widget | `ReadingCard` list render | manual list chunks | markers/geometry/highlights | no parser/pagination/source lifecycle | `REPLACE` |
| `test/widgets/reading_card_renderer_consistency_test.dart` | reader rendering | 3 | widget | deck/card renderer | manual chunks, font fetch disabled | preview/active geometry and inline callbacks | useful focused rendering, but implementation-coupled | `REWRITE` |
| `test/widgets/reading_card_speed_read_test.dart` | speed read UI | 7 | widget | `ReadingCard`/controller | fixed timings | active-word visual behaviour | time-based and unapproved policy | `PRODUCT_DECISION_REQUIRED` |
| `test/widgets/reading_card_table_test.dart` | reader structured blocks | 26 | widget | `ReadingCard`/table renderer | manual text/chunks | table/list/highlight/note rendering | mixes source content with generated display assumptions | `REPLACE` |
| `test/tool/test_generate_gutenberg_catalog.py` | catalogue tool | 2 | Python unittest | Python generator | temporary RDF and subprocess | catalogue output/reproducibility | isolated, deterministic tool contract; absent from CI | `KEEP` |

### Reader-critical individual test register

The following is deliberately explicit because these titles sound stronger than the paths they actually take. A semicolon-separated set with one disposition means **each named test in that set** has that disposition.

| File / named test set | Individual classification and audit finding |
| --- | --- |
| `reader_checkpoint_store_test.dart` — “every split card…unique signature”; “ordered ranges…reconstruction”; “same paragraph split…exact split”; “cards containing multiple paragraphs…ordered coverage”; “headings, tables, preformatted, images, and synthetic cards are explicit” | `KEEP_WITH_MINOR_IMPROVEMENT`: deterministic identity construction, but cards are manual; retain as source-identity unit contracts only. |
| Same file — “same layout restores the exact committed signature”; “same-layout partial publication cannot downgrade to semantic restore”; “default page cannot overwrite a pending restore”; “delayed lazy-window publication cannot displace exact restore”; “unloaded chapter resolves after its semantic section is loaded” | `REPLACE`: desired approved scenarios, yet they call the coordinator directly and do not execute `ReaderScreen` exact miss/fallback/persist behaviour. |
| Same file — “fifty rapid navigations survive immediate close”; “background flush waits for an in-flight persistence operation”; “out-of-order completion cannot overwrite the newer revision”; “stale revision and stale session are rejected inside the store”; “corrupt newest record recovers the previous valid checkpoint”; “abrupt termination simulation needs no dispose callback”; “seeded 1000-operation navigation layout background reopen stress” | `KEEP_WITH_MINOR_IMPROVEMENT`: the SQLite journal’s epoch/revision ordering is real and strong; use an injected clock/controlled IO in the stress test and do not equate it with screen lifecycle. |
| Same file — “explicit entry target does not reload the stored checkpoint”; “chapter bookmark link search and scrubber use one commit path”; “canceled scrubber or gesture does not create a checkpoint”; “density reflow commits the exact new card before exit”; “termination during reflow reopens from pending semantic anchor”; “rapid density changes reject older pagination completions”; “font text-scale orientation and viewport changes restore the anchor”; “legacy location is migrated once into a canonical exact card” | `REPLACE`: correct direction cannot be trusted until the actual controller/lazy/pagination/reopen path is covered. |
| `display_generation_coordinator_test.dart` — “identical concurrent requests join active generation”; “settings change replaces and cancels previous generation”; “rapid font-family reflows…”; “orientation or viewport…”; “old generation cannot publish…”; “active generation can write…”; “book close cancels…”; “completion clears…” | `KEEP_WITH_MINOR_IMPROVEMENT` as a generic state-machine unit only. It says nothing about emitted cards. |
| Same file — “pending navigation preserves…”; “barrier-controlled A B C…”; “stale completion…”; “late older restore future…”; “initial controller settlement…”; “generation rejection…”; “lazy publication restore…”; “correction is scoped…”; “slow cache and pagination…”; “prepend trim replacement and rebase…”; “old publication after user swipes…”; “synthetic controller callback…”; “latest explicit target…”; “chapter jump…”; “unloaded chapter intent…”; “intent is consumed…”; “rapid explicit commands…”; “previous and next arrows…”; “arrow intent…”; “intent-driven controller callback…”; “search Book Memory and bookmark intents…”; “failed resolution…”; “intent computed…”; “unresolvable anchor…”; “disposed reader…” | `REWRITE`: the target state machine is valuable, but `String` locations and direct coordinator calls prevent it from detecting real PageController, restoration, or range-island defects. |
| `progressive_display_state_test.dart` — “initial range…”; “publishes initial…”; “external lazy content…”; “appends…”; “anchored initial consumption…”; “prepends…”; “shifts…”; “rejects non-adjacent append…”; “boundary thresholds…”; “eviction remap preserves…”; “eviction remap cannot…”; “repeated window remaps…” | `REPLACE`: all operate on hand-authored `DisplayRangeResult`s. They test array assembly, not canonical packing/card signatures. |
| `segmented_display_cache_service_test.dart` — all 23 named tests from “chapter totals persist…” through “low storage reduces retention…” | `REPLACE` for reader correctness. Keep only the corruption/version/LRU portions when split into a cache-format suite; add cold/warm/canonical-card equivalence tests outside this file. The accepted “separated islands” case is specifically not sufficient seam evidence. |
| `lazy_book_session_test.dart` — “opens index…”; “resolves chapter…”; “new lazy book…”; “title-like front matter…”; “late meaningful-read…”; “unloaded chapter…”; “valid saved…”; “cold restore window…”; “incompatible saved…”; “next and previous…”; “readable adjacent…”; “resolved empty…”; “adjacent readable…”; “loaded window…”; “new lazy book without TOC…”; “publication mismatch…”; “ranked resolver…”; “ambiguous quote…”; “section and weighted…”; “section chunk locations…”; “superseded navigation…”; “sequential reading…” | `REWRITE`: useful real-session coverage with generated EPUBs, but no screen/card/checkpoint proof and no construction-order equality. |
| `lazy_section_repository_test.dart` — “loads requested…”; “duplicate requests…”; “two sessions join…”; “pinned sections…”; “reopens…”; “loads only section-local…”; “close stops hydration…”; “low storage…” | `REWRITE`: repository/cache mechanics only; require real EPUB corpus and consumer equivalence. |
| `lazy_epub_index_service_test.dart` — all 8 named tests | `KEEP_WITH_MINOR_IMPROVEMENT`: preserve the index-only technical contract, add a real EPUB2/EPUB3 corpus and source-map assertions. |
| `feature_rich_lazy_reader_fixture_test.dart` — all 6 named tests | `KEEP_WITH_MINOR_IMPROVEMENT`: this is the best end-to-end *session* fixture, but it asserts text containment and section presence—not exact offsets, card identity, renderer, or lifecycle. |
| `epub_parser_chapter_test.dart` — all 7 named tests | `KEEP_WITH_MINOR_IMPROVEMENT`: retain parser regression seeds; separate dialogue/presentation policy from structural parsing and add validated expected source ranges. |
| `epub_parser_list_test.dart` — all 12 named tests | `REWRITE`: it is important structured-block coverage, but it currently accepts generated marker/derived projection choices that the semantic-content audit identifies as unsafe. |
| `lazy_section_parser_equivalence_test.dart` — “joined lazy section output matches full parser visible text” | `REWRITE`: visible-text equality can pass while IDs, offsets, inline spans, resources, and card seams disagree. |
| `stable_book_location_test.dart` — all 4; `book_chunk_test.dart` — all 5; `reader_text_boundary_service_test.dart` — all 7; `final_layout_paragraphs_test.dart` — all 8 | `KEEP_WITH_MINOR_IMPROVEMENT`: stable, deterministic narrow contracts. Add source parser → display renderer round trips, RTL/CJK/emoji, headings, tables, and non-generated authoritative text. |
| `reader_source_projection_service_test.dart` — “font family reflow…”; each “$layoutChange reflow…” case; “repeated display text…”; “card boundaries…”; “captured source…”; “bookmark follows…”; “same window-relative…”; “stable identity…”; “ambiguous legacy…”; “uniquely verified…”; “multi-source…” | `REPLACE`: meaningful source-identity intent, but all windows/locations are manually manufactured; no actual canonical display or Book Memory/search route is used. |
| `reader_annotation_projection_test.dart` — all 9 named tests; `reader_character_match_service_test.dart` — all 21 | `REPLACE`: validate projection helpers only and cannot prove that a rendered annotation uses authoritative source offsets after parser/list/table transformations. |
| `reader_structural_progress_service_test.dart` — all 16 named tests; `reader_position_session_test.dart` — all 6 | `REWRITE`: preserve the committed-vs-preview idea, but remove display-index truth and bind it to settled cards through the screen lifecycle. |
| `reader_open_service_test.dart` — all 5 named tests | `REPLACE`: selection precedence is tested, not actual loading, restoration publication, fallback, or checkpoint rewrite. |
| `chapter_navigation_service_test.dart` — all 10; `reader_start_chapter_detection_test.dart` — all 5 | `REWRITE`: retain stable-source navigation intent after approval of front-matter policy; add lazy load + ReaderScreen controller settlement. |
| `reader_layout_metrics_test.dart` — “full-page density…” through “chapter-total work…” (all 31 titles) | Split: `PRODUCT_DECISION_REQUIRED` for ratios/margins/buffers/preparing copy; `KEEP_WITH_MINOR_IMPROVEMENT` for pure sentence/source-range cases; `REPLACE` for reflow, anchored lookahead, and “exact source offset restores…” because they never call the packing generator. The file as a whole remains `REPLACE`. |
| `reader_list_pagination_test.dart` — all 4; `reading_card_list_test.dart` — all 7; `reading_card_table_test.dart` — all 26 | `REPLACE`: direct manually-constructed list/table chunks cannot validate parser authority, repeated headers/markers, card seams, selection, or source navigation. |
| `reader_typography_rendering_test.dart` — “painter and rendered body…”; `reading_card_renderer_consistency_test.dart` — all 3 | `REPLACE` then `REWRITE`, respectively. The first mounts raw `RichText`, not the screen/card measurement stack. The latter was the focused 3/3 runtime pass and is useful renderer evidence, but it relies on exact private widget/render-object structure and manual cards. |
| `reader_navigation_settlement_test.dart` — all 4; `reading_card_deck_test.dart` — all 23 | `REPLACE` for the custom `PageView` harness; `INVESTIGATE_FLAKINESS` for the deck file because it uses many exact-duration pumps and `pumpAndSettle`. Neither is ReaderScreen lifecycle coverage. |
| `reading_card_note_save_test.dart` — all 8; `reader_copy_quote_connection_test.dart` — all 5; `reading_card_speed_read_test.dart` — all 7; `reading_card_chapter_progress_test.dart` — 1 | `REPLACE` for the source/reflow note test; `PRODUCT_DECISION_REQUIRED` for share, pacing, and presentation policy. None performs bookmark/highlight/note navigation through stable location into an open reader. |

#### Exact-title addendum for the reader-critical files

This addendum expands the compact “all” references above. Every title below receives the action displayed after it; when a line contains several titles, the action applies to **each** title on that line.

| File | Exact named tests → individual action |
| --- | --- |
| `segmented_display_cache_service_test.dart` | `chapter totals persist and invalidate by exact layout identity`; `writes first segment with lightweight manifest only`; `segment round-trips paragraph identity and packing seams`; `loads center segment and adjacent cached segments lazily`; `loads an exact cached source range without adjacent decoding`; `preserves separated islands and reports a source gap as miss`; `stale generation is denied before manifest publication`; `incompatible layout signature is skipped`; `v13 display segments are rejected by the v14 layout identity`; `repeated compatible loads preserve validated manifest state`; `cached manifest is not reused for incompatible layout keys`; `corrupt segment is removed without deleting valid neighbors`; `checksum mismatch invalidates only the affected segment`; `corrupt manifest is rejected without decoding segments`; `old segmented cache version is rejected`; `duplicate and overlapping manifest records are normalized`; `stale temporary files are removed during initialization`; `complete contiguous source coverage is detected`; `default policy is configurable and defaults to 48 MiB`; `actual-byte LRU evicts the coldest display range`; `active visible range is protected under byte pressure`; `obsolete layouts evict before current valid layout ranges`; `low storage reduces retention without touching external data` → `REPLACE` as reader correctness tests (split cache-format checks later). |
| `lazy_epub_index_service_test.dart` | `opens a lightweight index without reading every spine section`; `reads cover and arbitrary resources on demand`; `persists, restores, and validates the existing structural index`; `same-name replacement invalidates fingerprint and rebuilds`; `round trips non-linear structural weights and deletion recovery`; `corrupt persisted index safely rebuilds`; `incompatible persisted schema safely rebuilds`; `incomplete TOC records a warning and keeps direct section loading` → `KEEP_WITH_MINOR_IMPROVEMENT`. |
| `feature_rich_lazy_reader_fixture_test.dart` | `fixture opens at meaningful Chapter 1 with nested TOC targets`; `cross-section footnote and backlink load exact target sections`; `cross-section internal anchor resolves exact Chapter 2 paragraph`; `image and table parse only when current section is loaded`; `repeated phrase navigation remains context-disambiguated`; `missing and malformed fragments do not produce false exact matches` → `KEEP_WITH_MINOR_IMPROVEMENT`. |
| `epub_parser_chapter_test.dart` | `uses TOC anchors when multiple chapters share one HTML file`; `keeps and marks a long quoted paragraph as dialogue`; `treats long spoken paragraphs as dialogue even with low quote ratio`; `keeps a long paragraph containing A.M. structurally whole`; `does not synthesize spaces across adjacent inline markup`; `preserves poem and quote layout metadata`; `preserves HTML table structure for reader rendering` → `KEEP_WITH_MINOR_IMPROVEMENT` (separate unapproved presentation policy before retaining). |
| `epub_parser_list_test.dart` | `simple unordered direct-text items exclude generated bullets`; `paragraph child never produces a marker-only source chunk`; `multi-paragraph item retains one stable item relationship`; `nested UL inside OL retains type depth and parent item`; `nested OL inside UL retains ordered child relationship`; `ordered start value and marker type are deterministic`; `alphabetic and Roman marker functions cover HTML marker types`; `orphan malformed item falls back to normalized prose`; `authoritative projection and derived index exclude markers`; `Book Memory and character matching use item-body offsets`; `ordinary prose identity and text remain unchanged without lists`; `ordinary prose identity after a block-first list item stays stable` → `REWRITE`. |
| `lazy_section_repository_test.dart` | `loads requested sections and evicts beyond retention limit`; `duplicate section requests join one in-flight load`; `two sessions join one parser invocation for the same section`; `pinned sections are not evicted by retention pressure`; `reopens from parsed-section cache without reparsing payload`; `loads only section-local image resources into parsed chunks`; `close stops hydration before another section is scheduled`; `low storage suspends parsed hydration before parsing` → `REWRITE`. |
| `progressive_display_state_test.dart` | `initial range is bounded around target and does not know final count`; `publishes initial prepared range with mappings`; `external lazy content keeps covered local window incomplete`; `appends adjacent range and shifts local mappings`; `anchored initial consumption and continuation meet exactly once`; `prepends adjacent range and preserves existing source mappings`; `shifts prepared source indexes after lazy prepend`; `rejects non-adjacent append to prevent hidden gaps`; `boundary thresholds request expansion near prepared edges only`; `eviction remap preserves stable card text and source boundaries`; `eviction remap cannot retain stale or gapped display cards`; `repeated window remaps do not duplicate skip or reorder text` → `REPLACE`. |
| `reader_layout_metrics_test.dart` | `full-page density expands the readable area toward the screen edges`; `keeps a safety buffer even for full-page Card Mode layouts`; `Card Mode metadata and footer reserves reduce usable text height`; `horizontal safe area reduces readable width in landscape`; `side margins change available width without changing card margin`; `available width matches render formula in flat and card modes`; `supported edge combinations keep positive bounded text budgets`; `maps density directly to readable height ratios`; `density budgets scale by roughly 25/50/75/100 percent` → `PRODUCT_DECISION_REQUIRED`. `keeps abbreviations and closing quotes with the sentence`; `handles initials, decimals, ellipses, and Unicode punctuation`; `protects compact initialisms but accepts their contextual ending`; `preserves exact source across sentence boundaries`; `uses clauses before words for an oversized sentence`; `increasing paragraphSpacing increases multi-paragraph height`; `paragraphSpacing changes page fit for multi-paragraph text`; `single paragraphs measure the same across paragraphSpacing values` → `KEEP_WITH_MINOR_IMPROVEMENT`. `returns true when only paragraphSpacing changes`; `returns true when only sideMargin changes`; `covers every persisted layout-affecting reader setting`; `lazy replacement accepts a measured forward source ceiling`; `uses measured line capacity instead of one paragraph`; `includes but never crosses a genuine structural boundary`; `does not finalize an anchored card until a next card exists`; `quote decoration does not shrink measured text width`; `pending navigation keeps a published readable card visible`; `true initial opening may show full preparing state`; `routine successful preparation never shows floating status`; `explicit navigation failures remain actionable`; `exact source offset restores the same text after card boundaries change`; `chapter-total work never falls back to whole-book pagination` → `REPLACE` except visual-status policy, which is `PRODUCT_DECISION_REQUIRED`. |
| `reader_source_projection_service_test.dart` | `font family reflow preserves the exact source offset`; each generated `$layoutChange reflow follows source text across new boundaries`; `repeated display text cannot override the stable source offset`; `card boundaries use half-open source ranges`; `captured source location survives lazy-window replacement`; `bookmark follows its stable source after window reindexing`; `same window-relative index with another identity never renders`; `stable identity and offset override conflicting legacy fields`; `ambiguous legacy bookmark remains unresolved`; `uniquely verified legacy bookmark remains compatible`; `multi-source mapping persists each exact source substring` → `REPLACE`. |
| `reader_structural_progress_service_test.dart` | `within-chunk cards retain distinct exact structural positions`; `position revisions remain ordered when the clock repeats`; `exit flush takes the latest visible card snapshot`; `rapid navigation persists only the newest immutable snapshot`; `route and lifecycle flushes wait for ordered position writes`; `lazy global progress uses weighted stable source progression`; `loaded lazy window never reports false 100 percent`; `missing structural progression is safely unknown`; `legacy complete publication can retain exact display progress`; `committed stable location becomes canonical persisted progress`; `persistence uses published current location, not requested target`; `final published source end persists exact publication completion`; `loaded-window end and penultimate cards remain below completion`; `chapter boundary proof uses source end inside one XHTML file`; `chapter boundary proof crosses only the next readable section`; `structural scrub changes preview and commit one final navigation` → `REWRITE` (do not use display index as canonical truth). |
| `reader_list_pagination_test.dart` | `list metadata and display fragments round trip through JSON`; `long item slice states expose marker only on opening fragment`; `list body ranges remain authoritative UTF-16 source ranges`; `list blocks merge only within the same list relationship` → `REPLACE`. |
| `reading_card_list_test.dart` | `list marker and body share a hanging-indent row`; `continuation preserves indent without repeating marker`; `nested list uses restrained additional indentation`; `only list cards are top aligned`; `active and preview list geometry is identical`; `highlights and notes address only item body offsets`; `Speed Reader animates item body without consuming marker` → `REPLACE`. |
| `reading_card_table_test.dart` | `ReadingCard renders detected table as table UI`; `ReadingCard does not render wrapped raw header above table`; `ReadingCard does not render box drawing delimiter column`; `ReadingCard consumes separated raw header preamble`; `ReadingCard consumes header paragraph before table body`; `ReadingCard keeps normal prose on selectable text path`; `ReadingCard scales merged prose paragraph separators`; `ReadingCard does not add paragraph padding inside wrapped prose`; `ReadingCard spaces only explicit structural boundaries`; `ReadingCard keeps highlight offsets inside split paragraphs`; `ReadingCard redecorates existing text when highlights change`; `ReadingCard does not color an unrelated same-length range`; `ReadingCard removes and recolors generated ranges on update`; `ReadingCard keeps generated styling across inline nodes`; `ReadingCard layers generated styling with normal highlights`; `ReadingCard paints note blocks inside split paragraphs`; `ReadingCard gives dark notes a readable foreground`; `ReadingCard gives yellow notes dark foreground in dark mode`; `ReadingCard treats regular highlights with notes as note blocks`; `ReadingCard keeps regular highlight foreground unchanged`; `ReadingCard toggles reader controls when split text is tapped`; `ReadingCard does not toggle reader controls on split text long press`; `ReadingCard does not wrap inactive split paragraphs in selection area`; `ReadingCard keeps default paragraph block spacing unchanged`; `ReadingCard scales only final paragraph block spacing`; `ReadingCard uses preformatted fallback for broken table text` → `REPLACE` (colour/spacing portions additionally require product approval). |
| `reading_card_deck_test.dart` | `swipe up changes to the next card`; `idle deck builds only current and two forward depth cards`; `swipe down changes to the previous card`; `index zero can request and retry a structural previous destination`; `controller animates vertical next card before committing`; `programmatic next then upward swipe remains enabled`; `repeated programmatic arrow then swipe keeps advancing`; `controller replacement cancels navigation without locking deck`; `published target window unlocks and accepts the next swipe`; `incomplete swipe snaps back`; `upward swipe keeps previous card out of the stack`; `first and last card resist unavailable directions`; `disabled deck ignores swipe gestures`; `drag beginning on selectable text can still change page`; `stationary long press on selectable text does not navigate`; `current card is not remounted when deck swipe is disabled`; `ignores late pointer events after disposal`; `drag transforms reuse existing card widgets`; `horizontal swipe left changes to the next card`; `horizontal swipe right changes to the previous card`; `controller animates horizontal next card before committing`; `incomplete horizontal swipe snaps back`; `horizontal forward swipe keeps previous card out of the stack` → `INVESTIGATE_FLAKINESS` first, then `REWRITE` against the accepted navigation state machine. |
| `reader_navigation_settlement_test.dart` | `real swipes remain committed after initial restoration`; `scroll-end correction runs after layout once without looping`; `pending correction is inert after reader replacement`; `multiple correction requests coalesce to the latest owner` → `REPLACE`. |
| `reader_annotation_projection_test.dart` | `stable annotation projects onto the current lazy-window index`; `window replacement removes stale projection then restores target`; `stable projection resolves exact segment text after reindexing`; `migration projects one record without duplicate visual spans`; `character span stays on source text instead of same-length text`; `legacy same-length span is not projected onto unrelated window text`; `legacy annotation remains visible when exact source evidence matches`; `legacy marker-bearing list offset uses a unique body-text alias`; `legacy list alias refuses ambiguous duplicate body text` → `REPLACE`. |
| `reader_position_session_test.dart` | `normal navigation updates committed and active positions`; `scrub preview preserves committed reading position`; `preview promotion makes preview the committed position`; `clearing preview returns to committed without committing preview`; `navigation generation changes when visible position changes`; `modal state freezes active position and prevents commits` → `REWRITE`. |
| `stable_book_location_test.dart` | `stable book location round trips through JSON`; `legacy bookmark JSON remains readable and stable location is additive`; `highlight, saved word and history preserve legacy fields`; `book metadata stores stable last-read location without dropping index` → `KEEP_WITH_MINOR_IMPROVEMENT`. |
| `book_chunk_test.dart` | `falls back to identity mapping for original chunks`; `splits display selections across mapped source ranges`; `maps stored original ranges back into display offsets`; `round-trips special block presentation through compact JSON`; `round-trips logical paragraph and explicit boundary metadata` → `KEEP_WITH_MINOR_IMPROVEMENT`. |
| `reader_text_boundary_service_test.dart` | `protects compact and spaced initialisms with contextual endings`; `uses a small contextual abbreviation supplement`; `protects numbers versions domains urls and email addresses`; `handles ellipses quotes and CJK terminators`; `reports rejected protected candidates with exact UTF-16 offsets`; `word opportunities do not split spaced initials`; `grapheme ranges preserve combining variation and ZWJ sequences` → `KEEP_WITH_MINOR_IMPROVEMENT`. |
| `final_layout_paragraphs_test.dart` | `splits final display paragraph separators with original offsets`; `does not split single newlines`; `does not split long wrapped prose without paragraph separators`; `uses explicit structural metadata instead of packing seams`; `maps flattened cross-paragraph selection to display offsets`; `maps a paragraph-boundary start to the next paragraph`; `maps a paragraph-boundary end to the previous paragraph`; `uses the shared paragraph gap helper between measured segments` → `KEEP_WITH_MINOR_IMPROVEMENT`. |
| `reader_open_service_test.dart` | `canonical journal location wins over valid legacy metadata`; `explicit navigation target is the only checkpoint override`; `legacy last-read position migrates through structural weights`; `replacement mismatch does not reuse the old legacy percentage`; `canonical checkpoint loads an otherwise unloaded chapter` → `REPLACE`. |
| `chapter_card_layout_service_test.dart` | `complete layout maps exact within-chunk cards to page numbers`; `cached total is reused without starting generation`; `layout change invalidates only the changed layout key`; `stale chapter counting cannot publish over the latest chapter`; `cancelled counting stays unpublished and does not block reading` → `REPLACE`. |
| `display_section_memory_cache_test.dart` | `returns layout-compatible exact range without disk work`; `does not reuse ranges across layout cache keys`; `evicts least recently used unpinned range under budget pressure` → `REPLACE`. |
| `reader_typography_rendering_test.dart` | `painter and rendered body use identical resolved typography` → `REPLACE`. |
| `reading_card_renderer_consistency_test.dart` | `Card Mode keeps the same paragraph layout and source identity through forward and backward commits`; `only the committed card adds selection while preserving the paragraph renderer`; `canonical paragraph keeps inline styles links and footnotes across activation` → `REWRITE`. |
| `reading_card_note_save_test.dart` | `unsaved note dismiss asks before discarding text`; `view note popup closes outside but not inside`; `reader note preview closes from outside tap`; `note preview uses the resolved source segment after reflow`; `long selected note text starts collapsed and can expand`; `Card Mode bookmark icon keeps assigned bookmark color`; `Save Note commits a highlight-backed note without tapping the checkmark`; `selected text can be sent to the quote share callback` → the source/reflow test is `REPLACE`; all other presentation/sharing tests are `PRODUCT_DECISION_REQUIRED`. |
| `chapter_navigation_service_test.dart` | `orders same-spine anchors by resolved local source position`; `resolved anchor refines structural chapter progression`; `previous from chapter start is strictly earlier`; `nested TOC includes unique parent section targets`; `parent duplicate of first child is excluded in favor of child`; `same-spine parent before child remains navigable in order`; `dedupes identical fragments but preserves distinct same-href anchors`; `front matter is skipped for first reading chapter`; `unnumbered child chapter entries under sections remain navigable`; `unresolved first-open targets resolve after source maps arrive` → `REWRITE`. |

## 6. Runtime results

| Run | Discovered | Passed | Failed | Skipped | Timed out | Duration | Interpretation |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Full `rtk flutter test` | statically 898 Dart declarations; runner final discovery unavailable | observed through `+81` only | none emitted before transcript ceased | unavailable | unavailable | execution window 30.2s | **Indeterminate**; not a pass and not evidence of a deterministic failure. |
| Focused renderer file | 3 | 3 | 0 | 0 | 0 | about 1s | deterministic in this single targeted run; does not resolve whole-suite capture limitation. |

The version command failure is environmental (read-only Flutter SDK cache), not a repository test failure. The focused renderer result means the full run’s apparent stall cannot be assigned to that test file. No further full run was made; no suspicious file produced varying outcomes in the permitted targeted investigation.

## 7. High-confidence tests to preserve

- `text_painter_test.dart`: one narrow Flutter text-engine invariant.
- `frame_budgeted_range_scheduler_test.dart`: deterministic explicit-task scheduling/cancel contract.
- `test_generate_gutenberg_catalog.py`: a real subprocess/reproducibility test with temporary inputs, provided CI is deliberately extended to run it.
- Narrow parts of `reader_checkpoint_store_test.dart`: SQLite epoch/revision rejection, flush ordering, and corrupt-newest recovery. Keep them after splitting identity construction from lifecycle claims.
- `stable_book_location_test.dart`, `book_chunk_test.dart`, `reader_text_boundary_service_test.dart`, and `final_layout_paragraphs_test.dart`: useful pure source mapping/Unicode building blocks, once their contracts are grounded in authoritative-source fixtures.
- `epub_parser_chapter_test.dart`, `lazy_epub_index_service_test.dart`, `parsed_section_cache_service_test.dart`, and `feature_rich_lazy_reader_fixture_test.dart`: useful local parser/index/cache/session coverage, not release evidence for reader behaviour.

## 8. False-confidence and misleading tests

The following can all pass with the verified production faults intact:

1. Every range-generation call can start empty and flush a tail: no test runs `ReaderScreen.generateDisplayRange` across target-first, forward-first, backward-first, singleton-plus-expansion, or heading seams while comparing ordered card signatures.
2. Exact restore can be downgraded in `ReaderScreen`: coordinator tests prove only that the coordinator would reject a downgrade if called correctly. They never run the screen path that makes the fallback and writes it back.
3. Cold cache and warm cache can differ: cache tests serialise hand-authored ranges and check cache keys/manifests, not independently generated identity sequences.
4. A swipe can persist the wrong page: the custom `PageView` harness commits strings directly; it has no actual display-card mapping or checkpoint store.
5. Measurement can disagree with rendering: raw `TextPainter` and `RichText` use controlled style/width but omit ReaderScreen safe-area, Google font resolution timing, inline widgets, heading spacing, and actual `ReadingCard` construction.
6. Search, Book Memory, bookmarks, highlights, and notes can navigate to a mutable display index: helper projections manufacture stable identities and never make the complete route resolve against an open book.

`expect(tester.takeException(), isNull)`, `pumpAndSettle`, `findsOneWidget`, string containment, cache-hit/non-null checks, collection lengths, exact private widget-tree checks, and arbitrary margins/counts recur throughout the suite. They are not inherently invalid, but are weak where named as product regressions.

## 9. Contradictory, obsolete, and duplicate tests

### Resolved by the supplied approved reader contract

| Conflict | Tests encoding it | Resolution |
| --- | --- | --- |
| Exact physical card vs approximate semantic card under unchanged layout | checkpoint coordinator says exact; layout/source helper permits changed boundaries | Identical layout must restore exact committed physical card. Semantic migration is only for genuine layout/parser/cache version change. |
| Default page vs checkpoint authority | checkpoint helper rejects default overwrite, but no screen test | Pending verified exact restore must win and must not be overwritten. |
| Display index vs stable source identity | progress/session/card-depth helpers store indexes; source projections favour identity | Display index is transient only; stable source identity is canonical. |
| Page callback vs settlement | deck/harness tests infer index from callback; coordinator state assumes settlement | Persist only accepted settled cards; previews/cancelled swipes must preserve last committed card. |
| Adjacent mappings vs canonical seams | progressive state permits independently supplied adjacent ranges; cache accepts islands | Backward prepend must preserve anchor and exact adjacent order; independent islands are not a pagination contract. |
| Synthetic controller callbacks | coordinator has both rejection and intent-authorised acceptance tests | The screen must accept only callbacks causally tied to a current intent and visible settled card; test that through the real controller. |

### Duplicated effort without meaningful new state

- `reader_layout_metrics_test.dart`, `reader_text_boundary_service_test.dart`, and `final_layout_paragraphs_test.dart` repeat sentence/paragraph seam concepts at three abstraction levels without joining the actual layout generator.
- `reader_position_session_test.dart`, `reader_structural_progress_service_test.dart`, `display_generation_coordinator_test.dart`, and `reader_navigation_settlement_test.dart` independently model committed/preview/settled state. Each adds a different partial harness but none provides the missing integrated proof.
- Whole-cache, segmented-cache, and memory-cache tests repeat key/layout compatibility, while none compares cold/warm canonical output.

Do not delete these solely for overlap yet. First approve the canonical state machine, then retain one test per public contract and replace the others with production-path tests.

## 10. Fixture and mock audit

### Fixtures

| Fixture / source | Provenance and contents | Assessment | Missing coverage |
| --- | --- | --- | --- |
| `test/fixtures/books/feature_rich_lazy_reader.epub` (4,783 bytes) | Documented in `docs/diagnostics/large_epub_fix_execution.md`; generated deterministically by `tool/generate_feature_rich_lazy_reader_epub.dart`. EPUB3 container/OPF/nav, title page, three chapters, notes, one generated 4x4 PNG; includes nested TOC, same/cross-section anchors, footnote/backlink, repeated phrase, one image/table. | Legal synthetic fixture with a documented purpose. It is valuable, but it has no CSS, real publisher variation, validated expected UTF-16 ranges, or expected physical card signatures. | Full-section/canonical seam matrix; heading seams; real public-domain EPUBs; EPUB2 NCX/fixed-layout/RTL/ruby/complex inline/CSS/font cases; validated selection offsets. |
| Inline temporary EPUBs in parser/index/session tests | Created in test code with minimal XHTML/package data. | Good micro-fixtures for an isolated branch; provenance/purpose generally lives in code, not a fixture manifest. | Multi-section realistic documents and manually checked source/renderer expectations. |
| `Dialogues -- Plato.epub` application asset | A public-domain-looking production asset declared in `pubspec.yaml`; it is not used as a test fixture by the suite. | No reader regression evidence comes from it. Verify provenance/license before making it a fixture. | At least two realistic public-domain Gutendex EPUBs with documented license, checksum, structures, and expected semantic anchors. |
| Goldens | None. | No unreviewed snapshots; also no visual baseline. | Use only focused, reviewed goldens after contract approval; do not generate them as a pagination oracle. |

### Helpers, fakes, seams, and what they hide

| Support | Replaces | What it hides / recommendation |
| --- | --- | --- |
| `test/mocks/mock_data.dart`, `test/mocks/mock_services.dart`, `test/test_helpers/test_utils.dart` | `SharedPreferences` and model data | `rg` found no consumers outside their own declarations. `TestUtils` also injects `DateTime.now()`. Treat as unused support candidates; do not revive them. Remove only in a later approved cleanup. |
| `SharedPreferences.setMockInitialValues` | plugin-backed durable preferences | Hides plugin lifecycle, cross-book persistence, and process restart. Suitable for local services, not restoration proof. |
| sqlite FFI stores in checkpoint/catalog tests | mobile database/plugin lifecycle | Good for atomic store semantics, but not app startup, disposal, or multi-route lifecycle. |
| custom `PageView` correction harness | `ReaderScreen`/real display deck | Hides display mapping, lazy ranges, actual controller ownership, checkpoint writes and restoration. Replace with a narrow ReaderScreen harness. |
| manual `BookChunk`, `StableBookLocation`, and `DisplayRangeResult` builders | parser, paginator, source projection, cache load | Make it impossible to observe range-boundary packing, real signatures, generated/source content drift, or cold/warm disagreement. Use only in pure model tests. |
| `ReaderCheckpointStore.forTesting` | production DB factory/path | Appropriate injectable seam; retain it, but drive it from real screen lifecycle tests. |
| ReaderScreen's 16 `@visibleForTesting` helper exports | private layout/projection/merge logic | They encourage tests to lock temporary helper names and bypass stateful production flow. Narrow them behind dedicated services or replace with public contract tests after repair. |
| diagnostic `NALORI_*` switches | normal routing/cache/open behaviour | Diagnostic modes are not test mode. They must not become acceptance evidence; the current widget/unit suite does not exercise device diagnostics. |

## 11. Reader-core coverage matrix

| Approved requirement | Current evidence | Production-path coverage | Required replacement |
| --- | --- | --- | --- |
| Same layout restores exact committed card | coordinator-only checkpoint tests | No | real ReaderScreen reopen and exact `ReaderCardIdentity` plus visible text |
| Genuine layout change follows semantic anchor | manual source projection/checkpoint helpers | No | controlled settings/viewport change after a committed card |
| New lazy chunk leaves committed boundaries unchanged | none | No | canonical full-source vs target/forward/backward expansion signature comparison |
| Cold/warm cache ordered identities equal | cache format tests only | No | generate, persist, reload, compare all ordered card identities/ranges |
| Different lazy construction orders canonical membership equal | none | No | full, target-first, forward-first, backward-first, singleton-expand matrix |
| Settled swipe then exit saves new card | session/coordinator/harness fragments | No | real deck/controller settlement + checkpoint store + close |
| Preview/cancel then exit preserves committed card | position helper/direct deck | No | real cancelled gesture + close/reopen |
| Independent book checkpoints | store uses book id | No | A → B → A open lifecycle against durable store |
| Fallback cannot overwrite verified restore | direct coordinator test | No | delayed cache/open path in ReaderScreen |
| Heading card deterministic and adjacent | identity unit includes heading type | No | real heading seam cards and next/previous navigation |
| Backward prepend preserves anchor/order | progressive mappings only | No | actual prepended cards/signatures around anchor |
| Failed preparation remains stable and clears state | coordinator generic failure | No | real failed range then retry from committed anchor |
| Retry creates fresh intent/generation | coordinator token tests | No | real error injection at range prepare in ReaderScreen |
| Parser/cache/layout migration controlled | cache version and coordinator helper tests | Partial, not screen | old record → migration → semantic restore → exact recommit lifecycle |
| Display index is transient | source/progress helpers conflict with index-heavy tests | No | assertions that navigation uses identity even after reindexing |
| Search/Book Memory jump uses stable source | service helpers/direct detail widgets | No | search/memory result → open lazy reader → settled target verification |
| Annotations resolve across reflow | manual projections/note card | No | persisted bookmark/highlight/note after reflow, reload, and target navigation |
| Measurement/render consistency | raw painter and card widgets | Partial | one controlled ReaderScreen viewport/font/safe-area/inline/heading contract |

No current fixture compares exact ordered source ranges and physical-card signatures across full-section pagination, target-first, forward-first, backward-first, singleton then expansion, cold/warm cache, eviction/reload, prepend, and heading seams. This missing matrix is why the suite does not prevent the five verified pagination/cache failures.

## 12. Non-reader product decisions required

Approval is required before preserving or changing tests for:

- Reader density ratios, safety buffers, margins, card-depth footer/header reserves, font/theme/colour palette, Speed Read pacing, quote-card templates, and rendered-copy layout.
- Bookmark/highlight/note naming, colours, save/dismiss flows, generated-character presentation, Book Memory structure/export/detail UX, and share behaviour.
- Front-matter heuristics, first-reading-chapter selection, per-book lazy fallback preference, cache retention budgets, and card-depth chapter-progress presentation.
- Public-domain catalogue search/paging/sorting/download/cache UX, Open Library metadata policy, dictionary/saved-word behaviour, onboarding and library UI.

This report intentionally does not decide any of them.

## 13. Proposed trusted test architecture

Create a small hierarchy with one authoritative fixture vocabulary and no duplicated pagination implementation inside tests.

1. **Pure deterministic pagination contracts**: a public paginator interface consumes source blocks + immutable layout metrics and emits card identity/ranges. Compare entire ordered sequences, not counts/percentages.
2. **Source-location and identity contracts**: stable location, semantic anchor, card range/signature JSON, headings/images/tables/list fragments, and legacy migration. Use only manually validated expected ranges.
3. **Checkpoint-store tests**: retain SQLite epoch/revision/corruption tests. Keep the store independent of widgets.
4. **ReaderScreen lifecycle/widget tests**: inject a controlled parser/session, clock, checkpoint store, cache and controller observer. Exercise open/settle/close/reopen/two-book routes, not exported helper functions.
5. **Cache-equivalence tests**: compare canonical identities from fresh generation, warm disk cache, memory cache, eviction/reload and all construction orders.
6. **Navigation state-machine tests**: table-driven intents (swipe, cancel, retry, next/previous, TOC, search, Book Memory, bookmark) that are settled only by real visible cards.
7. **Small manually controlled EPUBs**: files with one intent each: heading seam, split paragraph, nested lists, table/header continuation, footnote/backlink, inline styles, image, CJK/RTL/grapheme.
8. **Realistic public-domain Gutendex fixtures**: a documented, rights-safe corpus with provenance, checksum, source structures, and approved expected anchors; do not rely on raw text substring checks alone.

Use a fake monotonic clock and explicit completers, never real delays. Disable network and runtime font fetching. Make cache paths unique per test and assert cleanup. Widget tests should use a fixed device metrics/safe-area/font configuration supplied by the harness.

## 14. Cleanup and replacement plan

| Stage | Scope / likely files | Entry criteria | Completion criteria | Risks | Must not change yet |
| --- | --- | --- | --- | --- | --- |
| 1. Approve contracts | Reader contract document; test decision register | owner reviews sections 4, 9, 11, 12 | signed decisions for exact restore, canonical pagination, navigation, annotations and non-reader policies | silently blessing implementation quirks | production code and existing tests |
| 2. Preserve high-confidence checks | narrow model/store/parser/index/tool tests | approved technical contracts | copied/labelled retained tests with no broadened claims | retaining a helper as an integration test | existing assertions/fixtures |
| 3. Create missing failing regressions | new controlled fixture/harness files under `test/reader_contract/` | approved reader contract and fixture design | failing tests for all matrix rows, especially lifecycle and equivalence | reproducing production logic in test code | production repairs, cache/schema versions |
| 4. Replace false confidence | reader layout/progressive/coordinator/cache/navigation/widget tests | failures reproduce through production path | old helper claims removed only after a stronger replacement passes | losing narrow utility checks | product behaviour decisions |
| 5. Remove obsolete/duplicate checks | helper/support files and duplicate state-model tests | replacement test identified for every deletion | dead support references confirmed absent; one canonical test per contract | deleting useful compatibility coverage | unrelated module cleanup |
| 6. Implement production repairs | `ReaderScreen`, paginator/cache/session/checkpoint integration as indicated by failures | trusted failing tests exist | canonical card equality and lifecycle regressions pass | changing source/schema before migration tested | unrelated UI/dependency/config changes |
| 7. Verify trusted release gate | CI workflow and focused test shards | full runner environment records versions/status | deterministic non-device suite, selected real fixtures, no network/device dependency | mistaking coverage for quality | goldens/coverage targets as substitutes |
| 8. Repeat for remaining modules | catalogue, annotations, sharing, settings, UI | reader release gate is trusted | product decisions and tests reconciled module by module | broad rewrite without owner approval | reader contract tests |

## 15. Final decision register

### Decisions the owner must approve

- Exact-card versus semantic restore boundary and controlled migration rules.
- Canonical pagination/seam, heading, list/table, cache-equivalence and retry contracts.
- Which non-reader UI/persistence behaviours are actual product requirements (section 12).
- Whether per-book lazy fallback, front-matter heuristics, colour/layout/pacing constants, and cache budgets remain product behaviour.
- The rights-safe realistic EPUB corpus and its manually validated expected anchors/ranges.

### Tests safe to keep immediately (within their narrow scope)

- `test/text_painter_test.dart`
- `test/unit/services/frame_budgeted_range_scheduler_test.dart`
- `test/tool/test_generate_gutenberg_catalog.py` (after explicitly adding it to CI)
- The storage-ordering subset of `test/unit/services/reader_checkpoint_store_test.dart`
- The source-model/parser/index/cache subset listed in section 7, labelled as unit checks rather than reader acceptance tests.

### Tests/groups that must not influence production changes until reviewed

- All `ReaderScreen` exported-helper tests; `progressive_display_state`, display-generation, cache, checkpoint lifecycle, and navigation harness tests.
- `reader_layout_metrics_test.dart`, card deck/renderer/list/table tests, and reflow/annotation projection tests when used as a specification.
- Every `PRODUCT_DECISION_REQUIRED` UI, settings, annotations, catalogue, sharing, and Book Memory test.
- The stale `test/TESTING_STRATEGY.md` architecture and any passing full-suite inference.
