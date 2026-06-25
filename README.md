<p align="center">
  <img src="assets/images/nalori_app_icon.png" width="112" alt="Nalori app icon" />
</p>

<h1 align="center">Nalori</h1>

<p align="center">
  A local-first Flutter EPUB reader that turns long-form books into focused, swipeable reading cards.
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" />
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white" />
  <img alt="Status" src="https://img.shields.io/badge/status-active%20development-orange" />
</p>

Nalori is an Android reading app built for people who want the ease of vertical scrolling without replacing books with short-form content. It imports EPUB files, preserves book structure, and lays content out according to the active screen size and typography settings.

The project combines **Flutter UI engineering**, **EPUB parsing**, **background processing**, **responsive text layout**, **local persistence**, and **network-resilient catalogue access**.

> Screenshots and packaged releases are being prepared. The repository currently represents an actively developed product.

## Highlights

- **Focused reading cards** with vertical or horizontal navigation and multiple content-density modes.
- **Responsive pagination** based on measured rendered height rather than a fixed word count.
- **EPUB-aware parsing** for chapters, headings, links, footnotes, images, lists, dialogue, poems, preformatted text, and tables.
- **Fast reopen times** through compressed disk caches, cache invalidation, and LRU eviction.
- **Background preparation** that parses books outside the main UI flow and deduplicates concurrent work.
- **Reading memory** with progress, bookmarks, highlights, notes, dictionary history, search, and reading statistics.
- **Deep customization** across themes, fonts, font weights, line height, margins, alignment, and card presentation.
- **Public-domain discovery** through Gutendex with request deduplication, rate limiting, retries, TTL caches, and stale-cache fallback.
- **Local-first design** with imported books and reading state stored on the device; no account is required.
- **Accessibility foundations** including semantic labels, scalable text-aware layout, and high-legibility font options.

## How it works

```mermaid
flowchart LR
    A[Import EPUB or browse public-domain books] --> B[Validate and store locally]
    B --> C[Parse EPUB in background]
    C --> D[Semantic book chunks]
    D --> E[Compressed parsed-book cache]
    E --> F[Measure text for the current device and settings]
    F --> G[Display pages and reading cards]
    G --> H[Progress, notes, highlights, bookmarks and statistics]
```

The parsing model and the visual layout model are deliberately separate. A book is parsed once into reusable semantic chunks; visible pages are then rebuilt for the current device, safe area, font, density, spacing, and reader mode.

Read the [architecture overview](docs/ARCHITECTURE.md) for the main components, data flow, caching strategy, and design decisions.

## Technology

| Area | Implementation |
|---|---|
| Application | Flutter and Dart |
| EPUB processing | Local `epubx` package, HTML DOM parsing |
| Concurrency | Dart isolates and shared in-flight futures |
| Persistence | App documents storage and `shared_preferences` |
| Networking | `http` with timeout, retry, rate-limit and deduplication policies |
| Book sources | Local EPUB imports, Gutendex catalogue, optional Open Library metadata |
| Quality | Flutter lints, unit/widget tests, mocked dependencies |

## Project structure

```text
lib/
├── controllers/   # Stateful reading behaviours such as speed reading
├── models/        # Book, reader, annotation and settings models
├── screens/       # Library, reader, memory, search and settings flows
├── services/      # Parsing, storage, metadata, networking and caches
├── ui/            # Shared visual system and colour policies
├── utils/         # Text measurement, parsing and mapping helpers
└── widgets/       # Reusable reader and library components

packages/epubx/    # Project-owned EPUB parsing dependency
test/              # Automated tests
```

## Getting started

### Prerequisites

- Flutter SDK compatible with Dart `^3.9.2`
- Android Studio or the Android SDK command-line tools
- An Android emulator or physical device

### Run locally

```bash
git clone https://github.com/PurushotamMehra/Nalori.git
cd Nalori
flutter pub get
flutter run
```

### Verify the project

```bash
flutter analyze
flutter test
```

Nalori does not require API keys for its current public-domain catalogue and optional metadata integrations.

## Engineering decisions

### Parse once, lay out many times

EPUB structure is independent of a phone's dimensions, while page boundaries are not. Nalori therefore caches parsed semantic content separately from display chunks generated for a particular screen and typography configuration.

### Keep expensive work away from interaction

EPUB parsing, compression, and deserialization use background isolates where appropriate. A serial preparation queue avoids resource spikes, while shared in-flight operations prevent duplicate parsing and network requests.

### Preserve source meaning

The parser retains source-file and text-range mappings so annotations, chapter navigation, search results, and restored reading positions can remain meaningful after content is split or merged for display.

### Degrade gracefully

Malformed EPUB structures fall back to simpler extraction paths. Network catalogue calls use timeouts, retries, rate limiting, cache-first reads, and stale-cache fallback rather than making the local library dependent on a remote service.

## Current status

Nalori is under active development. The core reader, local library, annotations, customization, reading statistics, speed reading, and public-domain catalogue are implemented. Current work is focused on large-book loading, stable whole-book navigation, EPUB fidelity, and release polish.

## Privacy

Imported books and reading activity are stored locally in the app's private storage. Network access is used only for features that require remote data, such as public-domain discovery or optional metadata enhancement.

## Author

Built by [Purushotam Mehra](https://github.com/PurushotamMehra).
