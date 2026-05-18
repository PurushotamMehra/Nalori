# Nalori Project Documentation

## 1. Project Idea

Nalori is a Flutter EPUB reader built around focused, vertical reading cards. Instead of showing a full page of dense ebook text, Nalori breaks an EPUB into smaller card-sized reading units and lets the reader move through the book with a swipe-first interface.

The app combines a personal offline EPUB library, Project Gutenberg discovery, reading progress tracking, bookmarks, highlights, notes, dictionary lookup, speed reading, reading stats, and shareable quote or book cards.

At a product level, the idea is to make long-form reading feel easier to start, easier to resume, and easier to continue on a phone.

## 2. Problem We Are Trying To Solve

Traditional mobile ebook readers often copy the printed-book model directly onto a small screen. This can create several problems:

- Long pages can feel heavy and hard to restart after a break.
- Readers lose momentum when they need to manually manage where they stopped.
- EPUB imports can feel technical or unreliable when metadata, covers, chapters, and malformed content are inconsistent.
- Readers often need separate apps or manual notes for vocabulary, highlights, stats, and sharing.
- Public-domain books are available online, but finding and importing them into a clean reading workflow adds friction.

Nalori tries to solve these issues by making reading sessions lightweight, structured, and phone-native.

## 3. How Nalori Solves It

Nalori turns each imported or downloaded EPUB into parsed content chunks, then rebuilds those chunks into display pages that fit the current screen, typography, density, and reader settings.

The solution has four main parts:

1. EPUB ingestion and caching: Books are imported from local files or downloaded from Project Gutenberg, parsed through the local `epubx` package, and cached for faster reopening.
2. Focused reader UI: Text, images, tables, chapters, links, bookmarks, highlights, and notes are rendered inside a fullscreen reader with swipe navigation.
3. Personal reading memory: Progress, last-read position, bookmarks, highlights, saved words, settings, reading pace, and reading history are persisted locally.
4. Discovery and sharing: Users can browse public-domain EPUBs, enrich metadata from Open Library, and export quote, book, or reading recap cards.

The result is an EPUB reader that is not only a file viewer, but a reading system: it imports books, prepares them, helps the user read, remembers what matters, and makes progress visible.

## 4. Folder Structure

```text
Nalori/
|-- android/                         Android Flutter host project
|-- assets/
|   |-- images/                      App icon and Nalori mark assets
|   `-- fonts/                       Local font asset directory
|-- docs/                            Project documentation and release notes
|-- ios/                             iOS Flutter host project
|-- lib/
|   |-- controllers/                 Stateful feature controllers
|   |-- l10n/                        Localization ARB and generated localization files
|   |-- models/                      Data models for books, chunks, settings, highlights, bookmarks, sharing
|   |-- screens/                     Full app screens and flows
|   |-- services/                    Storage, parsing, metadata, downloads, stats, sharing, settings
|   |-- ui/                          Shared visual system helpers
|   |-- utils/                       Text parsing, text spans, and name normalization helpers
|   `-- widgets/                     Reusable reader, library, annotation, quote, and navigation widgets
|-- packages/
|   `-- epubx/                       Local EPUB parser/reader package used by the app
|-- test/
|   |-- unit/                        Unit tests for models, services, controllers, utils, UI helpers
|   |-- widgets/                     Widget tests
|   |-- fixtures/                    Test EPUB and data fixtures
|   |-- mocks/                       Test mocks
|   `-- test_helpers/                Shared test utilities
|-- AGENTS.md                        Repository instructions for coding agents
|-- analysis_options.yaml            Dart analyzer settings
|-- l10n.yaml                        Flutter localization configuration
|-- pubspec.yaml                     Flutter package configuration
`-- README.md                        Short project summary
```

## 5. Core Features

### 5.1 EPUB Import

Nalori lets users import `.epub` files from the device.

What it does:

- Opens a platform file picker.
- Restricts accepted files to EPUB.
- Copies selected books into the app documents directory under `books/`.
- Avoids duplicate imports by reusing an existing copied file.
- Deletes unreadable/corrupted imports when metadata extraction fails.

How it helps the goal:

This makes Nalori a personal reader for the user's own library while keeping the app's internal storage predictable and offline-friendly.

Implementation:

- `BookImportService` handles file picking and internal copying.
- `LibraryService` lists saved EPUB files.
- `BookMetadataService.extractAndCacheMetadata` validates EPUB files and extracts title, author, and cover image.
- `BookListScreen` coordinates import, validation, metadata refresh, and opening the reader.

### 5.2 Project Gutenberg Discovery

Nalori includes a public-domain catalog flow for free EPUBs.

What it does:

- Searches and browses books from the Gutendex API.
- Filters to public-domain EPUB results.
- Supports search, language choices, author/topic entry points, pagination, background refresh, and prefetching.
- Downloads EPUBs with progress and cancellation support.
- Saves downloaded books into the same local library as imported EPUBs.

How it helps the goal:

Users can start reading without needing to find files elsewhere. Discovery, download, import, metadata, and reading are part of one flow.

Implementation:

- `PublicDomainBookService` talks to Gutendex, caches list/detail responses in `SharedPreferences`, and rate-limits requests through `ApiClient`.
- `PublicDomainDownloadService` streams EPUB downloads from Gutenberg, validates that the result looks like an EPUB zip, and saves it through `BookImportService.saveBookBytes`.
- `PublicDomainBooksScreen` shows the catalog and handles local-library matching so downloaded books can be opened instead of downloaded again.
- `PublicDomainBookDetailScreen` provides book details before download/open.

### 5.3 Library Management

The library is the user's main bookshelf.

What it does:

- Lists local EPUBs.
- Supports recently read, title, author, and progress sorting.
- Supports search within the library.
- Supports list and grid layouts.
- Shows continue-reading state and reading summaries.
- Allows deletion of books and associated cached data.
- Provides options to refresh metadata, change cover, revert metadata, share book cards, and share reading recap cards.

How it helps the goal:

Readers can find books quickly, resume the right one, and maintain a clean local collection without leaving the app.

Implementation:

- `BookListScreen` is the main library UI.
- `BookMetadataService` persists book metadata in `books_metadata.json`.
- `BookCacheService` stores parsed-book and display-layout caches in app storage.
- `ReadingStatsService` provides streak and reading summary values used by library cards.
- `CoverPaletteService` and visual helpers use book covers to make cards feel book-specific.

### 5.4 First Run And Resume Flow

Nalori opens into the most useful state for the user.

What it does:

- Shows the "How to use Nalori" screen the first time.
- Finds the most recently read unfinished book.
- Shows a focused resume screen when a book is in progress.
- Falls through to the library when no resumable book exists.

How it helps the goal:

The app reduces restart friction. A returning reader does not need to remember what to open.

Implementation:

- `HomeScreen` loads settings, onboarding state, metadata, local books, and cover palette.
- `UserEducationService` stores whether onboarding has been seen.
- `BookMetadataService.getAllSortedByLastRead` identifies likely resume candidates.
- `BookListScreen(initiallyOpenFile:)` opens the selected book after navigation.

### 5.5 EPUB Parsing And Chunking

Nalori converts EPUB files into reader-friendly units.

What it does:

- Parses EPUB bytes with the local `epubx` package.
- Runs heavy parsing in an isolate to keep the UI responsive.
- Extracts text, images, chapters, anchors, links, footnotes, and a search index.
- Detects front matter and non-main content.
- Splits long paragraphs into smaller chunks while preserving source mappings.
- Includes fallback extraction if DOM parsing fails.

How it helps the goal:

The reader experience depends on reliable, digestible chunks. The parser turns inconsistent EPUB internals into stable app data.

Implementation:

- `EpubParserService.parseFileInBackground` reads bytes and uses `Isolate.run`.
- `_parseBytes` reads the EPUB and returns title, chunks, anchors, chapters, and search index.
- `BookChunk` stores text, image, milestone, style, link, footnote, and original range metadata.
- `ReaderContentParser` identifies tables, preformatted blocks, and logical text for speed reading.
- `BookPreparseService` queues background parse work for books in the library.
- `BookCacheService` compresses and caches parsed book data for faster reopening.

### 5.6 Reader Cards And Page Layout

The reader is the core experience.

What it does:

- Displays each book as swipeable cards.
- Supports vertical and horizontal paging.
- Rebuilds display chunks based on screen size, safe area, text scale, font, line height, card depth, and content density.
- Supports card-depth mode with stacked cards and a custom gesture deck.
- Supports full-page and lower-density reading modes.
- Displays text, images, tables, preformatted blocks, chapter labels, chapter progress, and milestone cards.

How it helps the goal:

The same EPUB can feel comfortable on different devices and with different reader preferences. Cards keep progress visible and each step manageable.

Implementation:

- `ReaderScreen` owns display chunk computation and reader state.
- `resolveReaderLayoutMetrics`, `readerDensityPolicy`, and related helpers calculate available text space.
- `ReadingCard` renders each chunk and handles interactions inside a card.
- `ReadingCardDeck` provides the custom swipe/depth gesture model.
- `ReaderTableBlockWidget` renders table and preformatted content.
- `BookCacheService` can cache display chunks using settings and screen metrics as part of the cache key.

### 5.7 Navigation, Chapters, And Search

Nalori gives readers several ways to move through a book.

What it does:

- Tracks current display page and source chunk position.
- Shows top and bottom reader menus.
- Provides a progress scrubber and chapter markers.
- Shows chapter navigation and bookmark navigation in a side panel.
- Provides in-book search with snippets and jump-to-result behavior.
- Handles EPUB anchors and internal links.
- Stores position history for back navigation.

How it helps the goal:

Readers can move naturally through the book without losing their place.

Implementation:

- `ReaderScreen` manages `PageController`, current display index, original-to-display mappings, and position history.
- `ChapterPanel` renders chapters and bookmarks.
- `SearchScreen` uses the parsed search index for fast single-word narrowing, then searches in batches to keep the UI responsive.
- Link handling uses parsed anchor maps to jump within the book when possible.

### 5.8 Bookmarks

Bookmarks let users mark important locations.

What it does:

- Adds/removes bookmarks on reader pages.
- Prevents duplicate bookmarks at the same original source location.
- Supports bookmark names and colors.
- Saves a default bookmark color preference.
- Shows bookmarks in the chapter/navigation panel.
- Supports clearing and restoring bookmark lists.

How it helps the goal:

Readers can return to important passages without manual page tracking.

Implementation:

- `BookmarkService` stores bookmarks per book in `SharedPreferences` under `bookmarks_<bookId>`.
- `Bookmark` stores chunk index, original source offset, name, preview text, and color index.
- `ReaderScreen` maps display pages back to original chunk offsets before creating bookmarks.
- `ReadingCard` handles tap gestures and visual bookmark state.

### 5.9 Highlights, Notes, And Annotation Panel

Nalori supports active reading, not just passive reading.

What it does:

- Lets users select text and create highlights.
- Supports custom highlight colors and a saved palette.
- Lets users add notes to selected passages.
- Collapses multi-range annotations into readable panel entries.
- Supports filtering highlights by search text, note text, color, or character-style annotations.
- Lets users edit note text, remove notes, change highlight colors, and delete highlights.

How it helps the goal:

The reader can capture meaning, not only page position. This makes Nalori useful for study, rereading, and reflection.

Implementation:

- `HighlightService` stores per-book highlights in `SharedPreferences` under `highlights_<bookId>`.
- `HighlightPaletteService` stores palette and default color choices.
- `ReadingCard` owns selection UI and dispatches highlight/note actions.
- `NoteSheets` and `HighlightPaletteSheet` provide focused editing interfaces.
- `AnnotationsPanel` lists highlights, notes, and dictionary words.
- `ReaderScreen` maps display selections back to original EPUB offsets so annotations survive display reflow.

### 5.10 Dictionary And Saved Words

Nalori includes a vocabulary workflow.

What it does:

- Looks up selected words through the Free Dictionary API.
- Displays the first definition found.
- Lets users save and remove words.
- Stores optional source context and original chunk offsets.
- Shows saved words in a dedicated list.

How it helps the goal:

Readers can understand difficult words without leaving the reading flow.

Implementation:

- `DictionaryService.lookupWord` calls `https://api.dictionaryapi.dev`.
- Saved words are stored per book in `SharedPreferences` under `saved_words_<bookId>`.
- `SavedWord` stores word, meaning, book ID, timestamp, context, and source offsets.
- `SavedWordsScreen` renders saved vocabulary for a book.

### 5.11 Speed Read Mode

Speed Read gives an alternate way to move through text.

What it does:

- Tokenizes the current page into readable word tokens.
- Advances through words at a configurable words-per-minute value.
- Supports adaptive pacing based on word length and punctuation.
- Supports lyrics-style and window-style display modes.
- Supports manual or automatic page advance.
- Pauses and resumes around menus, app lifecycle changes, page transitions, and image viewing.

How it helps the goal:

Readers can switch from normal card reading to a more guided, momentum-focused mode.

Implementation:

- `SpeedReadController` owns tokenization, timers, active word index, WPM, adaptive pacing, pause/resume, and page-change behavior.
- `calculateSpeedReadWordDelayMs` adjusts delay for token length and terminal punctuation.
- `SpeedReadOverlay` renders the active speed-read experience.
- `ReaderScreen` integrates speed read controls, settings, auto-advance, and lifecycle pause logic.

### 5.12 Reading Stats And Insights

Nalori tracks reading progress over time.

What it does:

- Records pages read.
- Records active reading sessions and splits them across calendar days.
- Tracks current streak, longest streak, total books completed, and heatmap data.
- Estimates reading pace globally and per book.
- Stores chapter-level pace data when insights are enabled.
- Shows monthly/yearly heatmap and summary dashboard.

How it helps the goal:

Visible progress encourages consistency and helps users understand their reading habits.

Implementation:

- `ReadingStatsService` stores stats in `SharedPreferences` under `reading_stats_v1`.
- `ReaderScreen` records page reads, active session intervals, completion, and reading insight samples.
- `StatsScreen` renders streaks, summary metrics, reading pace, heatmap, and weekly breakdown.
- `BookMetadataService.updateReadingSummary` stores book-level summaries built from parsed chunks and chapters.

### 5.13 Reader Settings And Themes

Nalori gives readers control over comfort and style.

What it does:

- Supports app themes and reader themes.
- Supports font family, font weight, font size, line height, text alignment, paging axis, and content density.
- Supports card depth, blue-light filter, dim text, reading insights, volume-button paging, and custom reader themes.
- Supports reader presets and hidden built-in preset management.
- Supports book-specific custom reader theme data.

How it helps the goal:

Reading comfort is personal. Settings let the same app work for different eyes, devices, books, and environments.

Implementation:

- `ReadingSettings` defines all reader and app settings.
- `ReadingSettingsService` persists settings and exposes a `ValueNotifier` so the app can update theme state.
- `ReaderScreen` has a settings modal with category tabs for appearance, layout, navigation, reading, and effects.
- `BookReaderThemeService` can load cover-derived theme palettes.
- `AppUi` converts settings into Flutter themes and text styles.

### 5.14 Metadata And Cover Enhancement

Nalori improves library presentation when users allow online enhancement.

What it does:

- Extracts embedded title, author, and cover from EPUBs.
- Searches Open Library for cleaner metadata.
- Applies high-confidence remote title/author/cover matches.
- Finds multiple cover candidates.
- Allows local cover upload.
- Allows reverting to embedded book metadata.

How it helps the goal:

A clean library is easier to scan and more pleasant to return to. Metadata enhancement reduces messy filenames and missing covers.

Implementation:

- `BookMetadataService` stores embedded and remote metadata fields.
- `OpenLibraryMetadataService` searches Open Library, scores candidate matches, caches lookups, and validates cover images.
- `MetadataEnhancementPreferences` stores whether online enhancement is enabled.
- `BookListScreen` exposes refresh/change/revert cover and metadata actions.
- `QuoteCardPreviewScreen` can also change or upload covers for share cards.

### 5.15 Quote, Book, Image, And Recap Sharing

Nalori turns reading moments into shareable images.

What it does:

- Shares selected quotes as designed quote cards.
- Shares book cards from the library.
- Shares reading recap cards with progress and stats.
- Supports several quote card styles and themes.
- Generates themes from cover palettes when possible.
- Exports rendered cards as PNG files.
- Saves or shares exported images.
- Opens EPUB images in a dedicated viewer and can export image bytes.

How it helps the goal:

Sharing turns reading into a visible habit and gives users a way to preserve or recommend passages and books.

Implementation:

- `QuoteSharePayload`, `BookSharePayload`, and `ReadingRecapPayload` describe share content.
- `QuoteCardPreviewScreen` provides editing, cover changes, styles, themes, save, and share actions.
- `QuoteCardCanvas` renders the card UI.
- `QuoteCardExportService` captures a `RenderRepaintBoundary` at 1080px output width.
- `QuoteCardShareService`, `QuoteCardSaveService`, `ImageFileShareService`, and `ImageFileSaveService` handle platform save/share flows.
- `BookImageViewerScreen` and `BookImageExportService` handle embedded book image viewing/export.

## 6. How The App Works End To End

### 6.1 Startup

1. `main.dart` initializes Flutter bindings and error handlers.
2. `NaloriApp` loads reading settings through `ReadingSettingsService`.
3. The app builds `MaterialApp` with localization delegates, supported locales, and themes derived from `ReadingSettings`.
4. `HomeScreen` becomes the first screen.

### 6.2 First Run Or Resume

1. `HomeScreen` checks whether onboarding has been seen.
2. If not, it shows `HowToUseScreen`.
3. If onboarding is complete, it initializes metadata and local library services.
4. It finds the most recent unfinished book with a valid file.
5. If found, it shows a resume card.
6. If not found, it opens `BookListScreen`.

### 6.3 Adding A Book

There are two main ways to add a book:

- Local import through `BookImportService.importBook`.
- Public-domain download through `PublicDomainDownloadService.downloadBook`.

After a book is saved:

1. The EPUB is stored under the app documents `books/` directory.
2. `BookMetadataService` extracts and caches metadata.
3. Optional Open Library enhancement can improve title, author, and cover.
4. `BookListScreen` refreshes the library.
5. `BookPreparseService` can queue the book for background parsing.

### 6.4 Opening A Book

1. The user selects a book in `BookListScreen`.
2. `BookLoadingScreen` opens.
3. `BookPreparseService.ensureParsed` checks `BookCacheService` for a valid parsed cache.
4. If cached data is missing or stale, `EpubParserService.parseFileInBackground` parses the EPUB in an isolate.
5. Parsed output is cached.
6. `BookLoadingScreen` updates book reading summary metadata.
7. `ReaderScreen` opens with title, chunks, anchor map, chapters, and search index.

### 6.5 Reading A Book

1. `ReaderScreen` loads last read index, bookmarks, highlights, highlight palette, dictionary service, settings, metadata, and optional book theme.
2. It computes display chunks from original chunks using current screen and reader settings.
3. It restores the previous reading position.
4. It renders pages with `ReadingCard` inside either `ReadingCardDeck` or a `PageView`, depending on card depth mode.
5. When the page changes, it records reading stats, schedules position persistence, updates speed read state if active, and records completion when the final page is reached.

### 6.6 Saving Progress

Nalori stores reading progress in book metadata:

- `lastReadIndex`
- `lastReadTime`
- `totalChunks`
- `readingSummary`
- cover and theme data

`ReaderScreen` debounces reading position saves so normal reading does not write storage on every tiny state change. Before leaving the reader, it flushes pending reading position and reading session data.

### 6.7 Handling Reader Interactions

Reader interactions are split by responsibility:

- `ReadingCard` handles text selection, highlight menus, note creation UI, dictionary actions, image taps, bookmark visuals, and speed-read word styling.
- `ReaderScreen` owns persistent changes, page movement, metadata updates, stats updates, speed-read orchestration, and navigation to other screens.
- Services own storage and network behavior.

This separation keeps UI gestures close to the rendered page while keeping durable app state in screen-level services.

### 6.8 Searching Inside A Book

1. `ReaderScreen` opens `SearchScreen` with parsed chunks and search index.
2. `SearchScreen` debounces input.
3. For simple single-word queries, it narrows candidates through the prebuilt search index.
4. It searches batches asynchronously so the UI stays responsive.
5. Selecting a result returns the source chunk index.
6. `ReaderScreen` maps that original index to a display page and jumps there.

### 6.9 Annotation Persistence

Highlights and bookmarks are stored against original EPUB chunk and offset data, not only display-page numbers.

This matters because display pages can change when the user changes:

- font
- font size
- line height
- content density
- paging axis
- device size
- text scale
- card depth

By storing original source mappings, Nalori can rebuild pages and still place annotations near the correct text.

### 6.10 Performance Strategy

Nalori uses several techniques to keep reading smooth:

- EPUB parsing runs in an isolate.
- Parsed books are compressed and cached.
- Display chunk caches are keyed by layout-affecting settings.
- Library books can be preparsed in the background.
- Search is debounced, batched, and cancelable.
- Stats writes are debounced where appropriate.
- Network calls use cache-first behavior and host rate limiting.

## 7. Data Storage Overview

Nalori stores user data locally unless a network feature is explicitly used.

Local file storage:

- EPUB files: app documents `books/`
- Cover images: app documents cover directory managed by `BookMetadataService`
- Parsed cache: app documents `book_cache/`
- Temporary exported images: system temp directory

Local preferences:

- Reading settings
- Reader presets
- Hidden built-in presets
- Bookmarks per book
- Highlights per book
- Saved words per book
- Reading stats
- Public-domain catalog caches
- Open Library metadata and cover candidate caches
- First-run education state
- Metadata enhancement preference

Network features:

- Gutendex for Project Gutenberg catalog data.
- Project Gutenberg file hosts for EPUB downloads.
- Open Library for optional metadata and covers.
- Free Dictionary API for word lookup.

## 8. How Features Contribute To The Goal

Nalori's goal is to make long-form reading easier on phones. Each feature supports that goal in a specific way:

- Card reading reduces visual overload.
- Resume flow removes the friction of restarting.
- EPUB import keeps the user in control of their own library.
- Project Gutenberg browsing gives instant access to free books.
- Parser and cache layers make inconsistent EPUB files feel stable.
- Bookmarks, highlights, notes, and saved words support active reading.
- Search and chapter navigation reduce the cost of moving through long books.
- Reader settings improve comfort for different users and contexts.
- Speed Read adds a guided momentum mode.
- Stats make progress visible and encourage continuity.
- Metadata and cover enhancement make the library easier to scan.
- Sharing features help users preserve and recommend meaningful reading moments.

## 9. Main Code Ownership Map

Use this map when changing the project:

- App startup and global theme: `lib/main.dart`, `lib/ui/app_visuals.dart`
- Home/resume/onboarding: `lib/screens/home_screen.dart`, `lib/screens/how_to_use_screen.dart`, `lib/services/user_education_service.dart`
- Library: `lib/screens/book_list_screen.dart`, `lib/services/library_service.dart`
- Import/download: `lib/services/book_import_service.dart`, `lib/services/public_domain_download_service.dart`
- Public-domain catalog: `lib/screens/public_domain_books_screen.dart`, `lib/screens/public_domain_book_detail_screen.dart`, `lib/services/public_domain_book_service.dart`
- EPUB parsing: `lib/services/epub_parser.dart`, `packages/epubx/`
- Parse/display cache: `lib/services/book_cache_service.dart`, `lib/services/book_preparse_service.dart`
- Reader: `lib/screens/reader_screen.dart`, `lib/widgets/reading_card.dart`, `lib/widgets/reading_card_deck.dart`
- Navigation/search: `lib/widgets/chapter_panel.dart`, `lib/widgets/navigation_panel.dart`, `lib/screens/search_screen.dart`
- Bookmarks: `lib/models/bookmark.dart`, `lib/services/bookmark_service.dart`
- Highlights/notes: `lib/models/highlight.dart`, `lib/services/highlight_service.dart`, `lib/services/highlight_palette_service.dart`
- Dictionary: `lib/services/dictionary_service.dart`, `lib/screens/saved_words_screen.dart`
- Speed read: `lib/controllers/speed_read_controller.dart`, `lib/widgets/speed_read_overlay.dart`
- Stats: `lib/services/reading_stats_service.dart`, `lib/screens/stats_screen.dart`
- Metadata/covers: `lib/services/book_metadata_service.dart`, `lib/services/open_library_metadata_service.dart`, `lib/services/cover_palette_service.dart`
- Sharing/export: `lib/screens/quote_card_preview_screen.dart`, `lib/widgets/quote_card_canvas.dart`, `lib/services/quote_card_export_service.dart`, `lib/services/quote_card_share_service.dart`, `lib/services/quote_card_save_service.dart`
- Localization: `lib/l10n/`, `l10n.yaml`
- Tests: `test/unit/`, `test/widgets/`, `test/fixtures/`

## 10. Current Project Summary

Nalori is a mobile-first EPUB reader for focused, card-based reading. It solves the small-screen reading problem by converting EPUBs into readable cards, preserving reading memory, and surrounding the reader with practical tools: import, public-domain discovery, metadata cleanup, search, bookmarks, highlights, notes, dictionary lookup, speed reading, stats, and share cards.

The implementation is structured around Flutter screens and widgets for UI, services for persistence/network/parsing, models for durable data, and a local `epubx` package for EPUB handling. Most user data is stored locally, while optional online features enhance metadata, catalog discovery, downloads, and dictionary lookup.
