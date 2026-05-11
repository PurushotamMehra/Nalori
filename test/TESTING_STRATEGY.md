# Testing Strategy - Nalori Application

## Overview

This document outlines the testing methodology for the Nalori Flutter application. The app is an EPUB-based eBook reader with features including book import, reading, highlighting, bookmarking, dictionary lookups, and reading statistics.

---

## 1. Testing Philosophy

### Core Principles
- **Test Pyramid**: Prioritize unit tests at the base, integration tests in the middle, and widget/E2E tests at the top
- **Test Driven Development**: Write tests before implementing new features when possible
- **Isolation**: Each test should focus on a single responsibility
- **Repeatability**: Tests must produce consistent results across runs
- **Fast Execution**: Unit tests should run in milliseconds; no test should exceed a few seconds

### Testing Levels

| Level | Purpose | Speed | Scope |
|-------|---------|-------|-------|
| Unit Tests | Test business logic and services | Fast (<100ms) | Single function/class |
| Widget Tests | Test UI components in isolation | Medium (<1s) | Single widget |
| Integration Tests | Test feature flows | Slow (<30s) | Multiple screens |
| E2E Tests | Test full user journeys | Slowest | Complete app |

---

## 2. Test Organization

### Directory Structure
```
test/
├── unit/
│   ├── services/
│   │   ├── epub_parser_test.dart
│   │   ├── bookmark_service_test.dart
│   │   ├── highlight_service_test.dart
│   │   ├── reading_stats_service_test.dart
│   │   ├── dictionary_service_test.dart
│   │   ├── book_import_service_test.dart
│   │   └── library_service_test.dart
│   └── models/
│       ├── book_metadata_test.dart
│       ├── highlight_test.dart
│       ├── bookmark_test.dart
│       └── reading_settings_test.dart
├── widget/
│   ├── screens/
│   │   ├── reader_screen_test.dart
│   │   ├── home_screen_test.dart
│   │   ├── book_list_screen_test.dart
│   │   └── search_screen_test.dart
│   └── widgets/
│       ├── reading_card_test.dart
│       ├── chapter_panel_test.dart
│       └── navigation_panel_test.dart
├── integration/
│   ├── book_import_flow_test.dart
│   ├── reading_flow_test.dart
│   └── bookmark_highlight_flow_test.dart
├── fixtures/
│   ├── books/
│   │   └── sample_book.epub
│   └── data/
│       └── sample_metadata.json
├── mocks/
│   ├── mock_services.dart
│   └── mock_data.dart
└── test_helpers/
    └── test_utils.dart
```

### Naming Conventions
- Unit tests: `{class_name}_test.dart`
- Widget tests: `{widget_name}_test.dart`
- Integration tests: `{feature}_flow_test.dart`
- Test methods: `should_{expected_behavior}_when_{condition}`

---

## 3. Unit Testing Strategy

### 3.1 Services Testing

Each service in `lib/services/` requires comprehensive unit tests covering:

#### EPUB Parser Service (`epub_parser.dart`)
- **What it does**: Parses EPUB files and extracts content, chapters, and metadata
- **Test scenarios**:
  - Parse valid EPUB file and extract chapters
  - Handle malformed EPUB files gracefully
  - Extract metadata (title, author, cover image)
  - Handle empty or corrupted EPUB files
  - Parse chapters with special characters
  - Handle EPUB with missing required files
- **Mock dependencies**: File system operations

#### Bookmark Service (`bookmark_service.dart`)
- **What it does**: Manages bookmarks for books
- **Test scenarios**:
  - Add bookmark at specific position
  - Remove bookmark
  - Get all bookmarks for a book
  - Prevent duplicate bookmarks at same position
  - Persist bookmarks across app restarts
- **Mock dependencies**: SharedPreferences, storage

#### Highlight Service (`highlight_service.dart`)
- **What it does**: Manages text highlighting in books
- **Test scenarios**:
  - Create highlight with text and position
  - Delete highlight
  - Update highlight color
  - Get highlights for a book
  - Get highlights for specific chapter
  - Prevent overlapping highlights
- **Mock dependencies**: SharedPreferences, storage

#### Reading Stats Service (`reading_stats_service.dart`)
- **What it does**: Tracks and calculates reading statistics
- **Test scenarios**:
  - Record reading session with duration
  - Calculate total reading time
  - Calculate pages read per session
  - Calculate reading speed (words per minute)
  - Track reading streak
  - Calculate completion percentage
- **Mock dependencies**: SharedPreferences

#### Dictionary Service (`dictionary_service.dart`)
- **What it does**: Provides word definitions and saves vocabulary
- **Test scenarios**:
  - Look up word definition
  - Handle word not found
  - Save word to vocabulary list
  - Get saved words
  - Delete saved word
  - Search saved words
- **Mock dependencies**: HTTP client (for API), SharedPreferences

#### Book Import Service (`book_import_service.dart`)
- **What it does**: Imports EPUB files into the app library
- **Test scenarios**:
  - Import valid EPUB file
  - Validate EPUB format before import
  - Handle duplicate book imports
  - Copy file to app storage
  - Generate unique book ID
  - Handle import failures gracefully
- **Mock dependencies**: File system, path provider

#### Library Service (`library_service.dart`)
- **What it does**: Manages the book library
- **Test scenarios**:
  - Add book to library
  - Remove book from library
  - Get all books in library
  - Search books by title/author
  - Sort books (by title, author, date added)
  - Get recently read books
- **Mock dependencies**: Storage, file system

#### Reading Settings Service (`reading_settings_service.dart`)
- **What it does**: Manages user reading preferences
- **Test scenarios**:
  - Save and retrieve font size
  - Save and retrieve theme (light/dark)
  - Save and retrieve font family
  - Save and retrieve line height
  - Handle default settings
- **Mock dependencies**: SharedPreferences

### 3.2 Models Testing

Test model classes for:
- **Serialization/Deserialization**: JSON to model and back
- **Validation**: Ensure valid data only
- **Edge cases**: Null values, empty data, boundary conditions
- **Equality**: Model comparison and cloning

---

## 4. Widget Testing Strategy

### 4.1 Screen Tests

#### Reader Screen (`reader_screen.dart`)
- Display book content correctly
- Handle scrolling and pagination
- Apply user reading settings (font, theme)
- Show/hide navigation controls
- Display chapter progress
- Handle loading states
- Show error states

#### Home Screen (`home_screen.dart`)
- Display library section
- Display recently read books
- Show continue reading section
- Navigate to correct screens on tap

#### Book List Screen (`book_list_screen.dart`)
- Display all books in library
- Show book metadata (title, author, cover)
- Sort and filter books
- Handle empty library state
- Show loading states

#### Search Screen (`search_screen.dart`)
- Search functionality
- Display search results
- Handle no results state
- Navigate to book on selection

#### Stats Screen (`stats_screen.dart`)
- Display reading statistics
- Show charts/graphs for progress
- Handle empty stats state

#### Saved Words Screen (`saved_words_screen.dart`)
- Display saved vocabulary
- Search saved words
- Delete saved words
- Navigate to definition

### 4.2 Widget Component Tests

- `reading_card.dart`: Book card display, tap actions
- `chapter_panel.dart`: Chapter list display, selection
- `navigation_panel.dart`: Navigation controls, progress
- `book_completion_overlay.dart`: Completion display

### Widget Testing Best Practices
- Use `WidgetTester` for interaction simulation
- Mock all service dependencies
- Test both success and error states
- Verify correct widget rendering with different data
- Test keyboard accessibility

---

## 5. Integration Testing Strategy

### 5.1 Book Import Flow
1. User selects "Import Book"
2. File picker opens
3. User selects EPUB file
4. App validates file
5. Book appears in library
6. Book can be opened and read

### 5.2 Reading Flow
1. Open book from library
2. Book loads with last read position
3. User reads and scrolls
4. Progress is tracked
5. User can navigate chapters
6. Settings can be adjusted
7. Reading session is saved on exit

### 5.3 Bookmark & Highlight Flow
1. While reading, user creates highlight
2. Highlight is saved and displayed
3. User can view all highlights
4. User can delete highlights
5. Bookmarks can be added/removed
6. All annotations persist across sessions

---

## 6. Test Fixtures

### Sample EPUB Files
- Valid EPUB with multiple chapters
- EPUB with special characters in title
- EPUB with cover image
- EPUB without cover image
- Empty/minimal EPUB

### Mock Data
- Sample book metadata JSON
- Sample reading stats data
- Sample bookmarks array
- Sample highlights array

---

## 7. Testing Tools & Libraries

### Required Packages (Dev Dependencies)
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.0        # Mocking framework
  build_runner: ^2.4.0   # Code generation
  mocktail: ^1.0.0       # Simplified mocking
  integration_test:
    sdk: flutter
```

### Additional Recommendations
- **flutter_test**: Built-in testing framework
- **mockito**: For creating mocks and stubs
- **fake_async**: For testing asynchronous code

---

## 8. Test Execution

### Running Tests
```bash
# Run all unit tests
flutter test test/unit/

# Run all widget tests
flutter test test/widget/

# Run all integration tests
flutter test test/integration/

# Run a specific test file
flutter test test/unit/services/epub_parser_test.dart

# Run tests with coverage
flutter test --coverage
```

### CI/CD Integration
- Run tests on every pull request
- Enforce minimum code coverage (target: 70%)
- Block merges if tests fail

---

## 9. Coverage Goals

| Component | Target Coverage |
|-----------|-----------------|
| Services | 80%+ |
| Models | 90%+ |
| Widgets | 60%+ |
| Overall | 70%+ |

---

## 10. Testing Checklist

Before considering a feature complete:
- [ ] Unit tests written for all new services
- [ ] Unit tests written for all new models
- [ ] Widget tests written for new UI components
- [ ] Integration tests written for user flows
- [ ] All tests passing
- [ ] Code coverage meets targets
- [ ] No lint errors

---

## 11. Maintenance

- Review and update tests when refactoring
- Remove obsolete tests when features are removed
- Update fixtures when sample data changes
- Regularly review test performance
- Keep mock data realistic and representative
