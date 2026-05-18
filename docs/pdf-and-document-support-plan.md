# PDF and Document Support Implementation Plan

## Goal

Add PDF support to Nalori quickly without destabilizing the existing EPUB reader.

The fastest good path is to treat PDF as a first-class supported file type with its own reader screen, not as a PDF-to-EPUB conversion step. PDF-to-EPUB conversion is likely to produce poor reading output for many real PDFs because PDFs are fixed-layout page documents, not structured book documents.

This plan keeps the existing EPUB card reader intact and adds document support in phases.

## Current State

Nalori is currently EPUB-only across the import and reading pipeline:

- `lib/services/book_import_service.dart`
  - Android method channel calls `pickEpub`.
  - File picker allows only `epub`.
  - Imported downloaded book bytes are normalized to `.epub`.
- `android/app/src/main/kotlin/com/nalori/reader/MainActivity.kt`
  - Android native picker uses only `application/epub+zip`.
  - Native copied import path validates `.epub`.
- `lib/services/library_service.dart`
  - Lists only files whose extension is `.epub`.
- `lib/services/book_metadata_service.dart`
  - Validates and extracts metadata through `EpubReader.readBook`.
- `lib/services/epub_parser.dart`
  - Produces `BookChunk`, anchors, chapters, and search index from EPUB content.
- `lib/services/book_preparse_service.dart`
  - Always parses through `EpubParserService`.
- `lib/screens/book_loading_screen.dart`
  - Assumes an EPUB parse/cache flow before opening `ReaderScreen`.
- `lib/screens/book_list_screen.dart`
  - UI text and fallback title cleanup assume `.epub`.

The existing `ReaderScreen` is not directly tied to the EPUB file format. It consumes a parsed content model:

- title
- `bookId`
- `List<BookChunk>`
- anchor map
- chapter tree
- search index

That makes future text-oriented formats easier to add, but PDF should still start as a separate reader because it is page-based.

## Product Decision

### Recommended MVP

Implement PDF as a separate reader path:

```text
Import .pdf -> store in books/ -> show in library -> open PdfReaderScreen -> remember last page
```

Do not convert PDF to EPUB for the first version.

### Why Not PDF-to-EPUB First

PDF conversion creates more risk than value for the MVP:

- Paragraph order can be wrong.
- Page headers, footers, page numbers, and watermarks often pollute extracted text.
- Multi-column PDFs can interleave columns incorrectly.
- Scanned PDFs need OCR, which is outside the current app architecture.
- Tables, footnotes, equations, images, and captions need custom handling.
- A broken conversion would look like a broken Nalori reader.

PDF-to-text/card mode can be added later as an optional feature for simple text-heavy PDFs.

## Supported Formats Roadmap

### Phase 1: EPUB and PDF

Support:

- `.epub`
- `.pdf`

Behavior:

- EPUB continues to use the existing card reader.
- PDF opens in a dedicated PDF reader.

### Phase 2: Simple Text Documents

Support:

- `.txt`
- `.html`
- `.xhtml`
- `.md`

Behavior:

- These formats can feed the existing `BookChunk` card reader.
- HTML/XHTML can reuse extracted DOM parsing logic from the EPUB parser once that logic is separated from EPUB container handling.

### Phase 3: Structured Documents

Support:

- `.docx`
- `.fb2`
- `.fb2.zip`

Behavior:

- Convert parsed paragraphs/headings into `BookChunk`.
- Metadata and chapter extraction should be best-effort.

### Phase 4: Experimental Formats

Support only if there is enough user demand:

- DRM-free `.mobi`
- DRM-free `.azw3`
- `.cbz`

Notes:

- Kindle DRM should not be supported.
- CBZ needs an image/page reader, not the existing text card reader.

## Format Architecture

Add a small format abstraction before adding more formats.

### New Enum

Create a model such as:

```dart
enum BookFormat {
  epub,
  pdf,
  txt,
  html,
  markdown,
  docx,
  fb2,
  unknown,
}
```

Suggested file:

- `lib/models/book_format.dart`

### Format Detection Service

Create a service or utility that detects format by extension first, with optional MIME/magic-byte validation later.

Suggested file:

- `lib/services/book_format_service.dart`

Initial behavior:

- `.epub` -> `BookFormat.epub`
- `.pdf` -> `BookFormat.pdf`
- everything else -> `BookFormat.unknown`

Later behavior:

- validate EPUB zip signature and package files.
- validate PDF `%PDF-` header.
- detect `.fb2.zip`.

### Metadata Strategy

The current `BookMetadata` can continue to use `id` as filename, but it should gain a format field.

Suggested addition:

```dart
final BookFormat format;
```

Migration behavior:

- Existing metadata without a format should default to `BookFormat.epub`.
- Or infer format from `id` during `BookMetadata.fromMap`.

For the MVP, if we want the smallest code change, we can infer from file extension without storing format. Storing format is cleaner and better for future formats.

## PDF MVP Scope

### Must Have

- Import `.pdf` through the file picker.
- Show PDFs in the existing library.
- Open PDFs from the library.
- Dedicated `PdfReaderScreen`.
- Page navigation.
- Remember last opened page.
- Delete PDF files and associated progress/metadata.
- Display a reasonable title, using filename if PDF metadata is unavailable.

### Should Have

- Show PDF badge/icon in the library card/list item.
- Show progress as page count percentage.
- Preserve existing app theme colors around the PDF viewer.
- Support back navigation and system navigation cleanly.

### Nice to Have

- PDF search.
- Text selection/copy.
- First-page thumbnail as cover.
- Jump to page.
- Last page viewed label.
- PDF outline/bookmarks if available.
- Text extraction for simple PDFs.

### Not in MVP

- PDF-to-EPUB conversion.
- OCR for scanned PDFs.
- Highlights synced to PDF text coordinates.
- Quote-card sharing from PDF selected text.
- Nalori card reader mode for PDF.
- PDF annotations.

## Package Choice

Two likely package paths:

### Option A: Syncfusion PDF Viewer

Package:

- `syncfusion_flutter_pdfviewer`

Pros:

- Fastest route to a full-featured PDF viewer.
- Built-in page navigation patterns.
- Search and text selection support are more mature than basic renderers.
- Better fit if PDF is a must-have product feature.

Cons:

- Requires confirming Syncfusion licensing for the app.
- Adds a large dependency.

Recommendation:

- Use this if licensing is acceptable.

### Option B: pdfx

Package:

- `pdfx`

Pros:

- Smaller/simple viewer path.
- Good enough for basic display and page navigation.

Cons:

- More custom work for search, selection, outline, and reader features.
- Less product-complete for a reader app.

Recommendation:

- Use only if Syncfusion licensing is not acceptable.

## Implementation Phases

## Phase 0: Dependency and Licensing Decision

Owner decision before coding:

- Choose `syncfusion_flutter_pdfviewer` or `pdfx`.

Acceptance criteria:

- Dependency selected.
- Licensing implications documented.
- Minimum Android/iOS requirements checked.

Estimated work:

- 0.5 day.

## Phase 1: Generalize Import and Library File Types

### Files to Touch

- `lib/services/book_import_service.dart`
- `android/app/src/main/kotlin/com/nalori/reader/MainActivity.kt`
- `lib/services/library_service.dart`
- `lib/widgets/add_book_sheet.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_en_IN.arb`
- generated localization files after `flutter gen-l10n`

### Work

1. Rename user-facing import language:
   - "Import EPUB" -> "Import book/document" or "Import file".
   - "Choose a book file from this device" can stay, or become "Choose an EPUB or PDF file from this device".

2. Update Dart picker:
   - allowed extensions: `epub`, `pdf`.
   - dialog title should not say EPUB only.

3. Update Android native picker:
   - Replace `pickEpub` with `pickBookFile`, or keep method name temporarily and broaden behavior.
   - MIME types:
     - `application/epub+zip`
     - `application/pdf`
   - Validate selected filename extension as `.epub` or `.pdf`.

4. Update import copy helpers:
   - Rename `_safeEpubFileName` to `_safeBookFileName`.
   - Preserve the original supported extension instead of always returning `.epub`.

5. Update library listing:
   - Return `.epub` and `.pdf` files.
   - Sort behavior can stay unchanged.

### Acceptance Criteria

- User can import an EPUB exactly as before.
- User can import a PDF without it being rejected.
- Library shows both EPUB and PDF files.
- Unsupported files are still rejected.
- Existing downloaded Project Gutenberg EPUB flow still saves `.epub`.

### Tests

- Unit test `BookImportService` filename normalization if practical.
- Unit test `LibraryService` filtering if this service has test coverage.
- Manual Android file picker test with EPUB, PDF, and unsupported file.

Estimated work:

- 0.5 to 1.5 days.

## Phase 2: Format Detection and Open Routing

### Files to Touch

- `lib/models/book_format.dart` new
- `lib/services/book_format_service.dart` new
- `lib/screens/book_list_screen.dart`
- `lib/screens/book_loading_screen.dart`
- `lib/services/book_preparse_service.dart`

### Work

1. Add `BookFormat` enum.

2. Add extension-based detection:
   - `.epub`
   - `.pdf`

3. Change library open flow:
   - EPUB -> existing `BookLoadingScreen`.
   - PDF -> new `PdfReaderScreen`.

4. Keep EPUB preparse queue EPUB-only:
   - Do not send PDFs through `BookPreparseService`.
   - `BookPreparseService.queueBooks` should skip non-EPUB files or receive only EPUBs.

5. Update fallback title display:
   - Replace `.replaceAll('.epub', '')` with extension-agnostic basename cleanup.

### Acceptance Criteria

- Opening EPUB still uses the existing EPUB loading/card reader.
- Opening PDF does not call `EpubParserService`.
- PDF open path is isolated from EPUB parse/cache failures.

### Tests

- Unit test format detection.
- Widget or unit-level test for open routing if existing tests make this practical.
- Manual test with one EPUB and one PDF in library.

Estimated work:

- 0.5 to 1 day.

## Phase 3: PDF Reader Screen

### Files to Add

- `lib/screens/pdf_reader_screen.dart`

### Files to Touch

- `pubspec.yaml`
- `lib/screens/book_list_screen.dart`
- `lib/services/book_metadata_service.dart`
- possibly `android/app/build.gradle.kts` or platform config only if the chosen package requires it

### Work

1. Add selected PDF dependency.

2. Build `PdfReaderScreen`:
   - input: `File bookFile`, `String bookId`, `ReadingSettings settings`.
   - render local PDF.
   - show minimal top controls:
     - back
     - title
     - current page / total pages
   - preserve app background/theme around viewer.

3. Track current page:
   - Use `SharedPreferences` initially:
     - key: `last_pdf_page_$bookId`
   - Store 0-based or 1-based consistently.
   - Restore page on open.

4. Progress:
   - Update `BookMetadata.lastReadIndex` as page index.
   - Update `BookMetadata.totalChunks` as page count for PDFs, or add PDF-specific fields later.
   - For MVP speed, reusing `lastReadIndex`/`totalChunks` is acceptable if documented.

5. Title:
   - Use existing metadata title if available.
   - Else use cleaned filename.

### Acceptance Criteria

- PDF opens from local file.
- User can swipe/scroll/navigate pages.
- App remembers last page after closing/reopening.
- Progress shown in library roughly matches page progress.
- EPUB progress behavior is unchanged.

### Tests

- Manual import/open PDF.
- Manual close/reopen restores page.
- Manual delete removes PDF and does not break library.
- If package allows controller mocking, add a basic `PdfReaderScreen` widget smoke test.

Estimated work:

- 1 to 2.5 days, depending on package choice.

## Phase 4: PDF Metadata and Library Polish

### Files to Touch

- `lib/services/book_metadata_service.dart`
- `lib/screens/book_list_screen.dart`
- possibly `lib/models/book_metadata.dart`

### Work

1. Metadata extraction:
   - EPUB uses current `EpubReader` path.
   - PDF should not be treated as corrupted just because EPUB parsing fails.
   - Basic MVP:
     - title from cleaned filename.
     - author as `Unknown Author`.
     - no cover.
   - Better version:
     - read PDF document info if chosen package exposes it.
     - generate first-page thumbnail as cover if practical.

2. Library UI:
   - Add PDF badge or icon.
   - Avoid EPUB-specific error copy for PDF failures.
   - Use generic unsupported/corrupt messaging:
     - "This file could not be added."
     - "Nalori supports EPUB and PDF files."

3. Search/sort:
   - Library search should work for PDF titles/authors.
   - Progress sort should treat PDF page progress like EPUB chunk progress.

### Acceptance Criteria

- PDF import never attempts EPUB metadata extraction.
- PDF appears with reasonable title.
- Library cards make file type clear.
- Existing EPUB cover behavior remains unchanged.

### Tests

- Unit test metadata creation for PDF fallback.
- Manual test with PDF missing metadata.
- Manual test EPUB metadata still extracts title/author/cover.

Estimated work:

- 0.5 to 1.5 days.

## Phase 5: Deletion, Reset, Stats, and Cache Hygiene

### Files to Touch

- `lib/screens/book_list_screen.dart`
- `lib/services/book_cache_service.dart`
- `lib/services/reading_stats_service.dart`
- `lib/services/bookmark_service.dart`
- any services keyed by `bookId`

### Work

1. Delete flow:
   - Ensure deleting a PDF removes:
     - file
     - metadata
     - last page preference
     - stats if created
     - any generic book services keyed by `bookId`

2. Reset progress:
   - EPUB reset removes `last_read_$bookId`.
   - PDF reset should remove `last_pdf_page_$bookId` and reset metadata progress.

3. Cache:
   - EPUB parsed-book cache should remain EPUB-only.
   - PDF viewer package may have its own cache; clear only if exposed and necessary.

4. Stats:
   - For MVP, PDF reading stats can be simple:
     - last opened
     - progress
   - Avoid pretending WPM/chapter estimates apply to PDFs unless text extraction exists.

### Acceptance Criteria

- Delete and reset work for EPUB and PDF.
- EPUB cache deletion still works.
- PDF does not create invalid EPUB cache entries.

### Tests

- Manual delete PDF.
- Manual reset PDF progress.
- Regression check delete/reset EPUB.

Estimated work:

- 0.5 to 1 day.

## Phase 6: Optional PDF Search and Navigation Enhancements

Only start after the MVP is stable.

### Features

- Search within PDF.
- Jump to page.
- PDF outline/table of contents if available.
- Text selection/copy.
- Basic share selected text if supported by package.

### Acceptance Criteria

- Search results navigate correctly.
- Selection works on text PDFs.
- Scanned PDFs fail gracefully.

Estimated work:

- 1 to 3 days, package-dependent.

## Phase 7: Optional PDF Text/Card Mode

This is not the main PDF experience. It should be an optional action such as "Read as cards" or "Extract text".

### Work

1. Add a PDF text extraction service.

2. Clean extracted text:
   - remove repeated headers/footers where obvious.
   - remove page numbers.
   - join hyphenated line breaks.
   - rebuild paragraphs.

3. Feed cleaned paragraphs into `BookChunk`.

4. Cache extracted result separately from the PDF viewer page progress.

5. Make failure clear:
   - scanned PDF -> "Text could not be extracted from this PDF."
   - complex layout -> allow user to continue in PDF viewer.

### Acceptance Criteria

- Simple text novels can be read in card mode.
- Complex PDFs do not corrupt the normal PDF viewing path.
- User can choose between PDF view and extracted card view.

Estimated work:

- 3 to 7 days for a reasonable first version.
- More if OCR is added, which is not recommended initially.

## Testing Matrix

### EPUB Regression

- Import EPUB.
- Download Project Gutenberg EPUB.
- Open EPUB reader.
- Resume progress.
- Search.
- Bookmarks/highlights.
- Delete EPUB.
- Reset EPUB progress.

### PDF MVP

- Import PDF from Android file picker.
- Import PDF from non-Android file picker if supported platform is tested.
- Open text PDF.
- Open image-heavy PDF.
- Open large PDF.
- Reopen PDF and restore last page.
- Delete PDF.
- Reset PDF progress.
- Verify PDF is not parsed as EPUB.

### Unsupported Files

- Try `.docx` before support exists.
- Try `.mobi` before support exists.
- Try renamed unsupported file with `.pdf` extension.
- Try corrupted PDF.

### Performance

- Large EPUB library with mixed EPUB/PDF files.
- Large PDF open time.
- Memory usage when scrolling a long PDF.
- Return from PDF reader to library.

## Risks and Mitigations

### Risk: PDF Package Licensing

Mitigation:

- Decide package before implementation.
- If Syncfusion licensing is not acceptable, use `pdfx` for a simpler MVP.

### Risk: Existing EPUB Flows Regress

Mitigation:

- Keep EPUB parser unchanged.
- Route by file format before parsing.
- Add tests for format detection and EPUB import.

### Risk: Metadata Model Becomes Ambiguous

Mitigation:

- Add `BookFormat` to metadata or consistently infer from filename.
- Document that `lastReadIndex` means chunk index for EPUB and page index for PDF if reusing it.

### Risk: PDF Feature Expectations Are Too High

Mitigation:

- MVP should promise viewing and page progress only.
- Search/selection/extraction should be follow-up phases.

### Risk: Scanned PDFs

Mitigation:

- Normal PDF viewer handles scanned PDFs visually.
- Text/card mode should state that scanned PDFs require OCR and are unsupported initially.

## Suggested Implementation Order

1. Choose PDF package.
2. Add `BookFormat` and detection.
3. Update import picker and library listing for `.pdf`.
4. Add open routing.
5. Add `PdfReaderScreen`.
6. Store/restore PDF page progress.
7. Add PDF metadata fallback.
8. Polish library UI with PDF badge.
9. Add delete/reset cleanup.
10. Run EPUB regression tests and PDF manual tests.

## Estimated Total Effort

Fast MVP:

- 3 to 5 working days.

Polished PDF reader with search, metadata, thumbnails, and better navigation:

- 1 to 2 weeks.

PDF-to-card extraction:

- Add another 3 to 7 working days for a basic version, longer for high-quality extraction.

## Final Recommendation

Implement native PDF viewing first. It is faster, more reliable, and preserves the quality of the existing EPUB reader.

Do not implement PDF-to-EPUB as the primary PDF path. Add optional PDF text extraction later only after the native PDF reader is stable.
