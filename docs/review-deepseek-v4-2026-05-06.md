# Nalori — Play Store Readiness Review

**Reviewer:** Utopiya (opencode, powered by deepseek-v4-pro)
**Date:** 2026-05-06
**Scope:** Full codebase audit against Google Play Store submission requirements, Android best practices, and production-readiness standards.
**Method:** Static analysis of all source files (+ unit & widget test suite), build configuration, permissions, privacy posture, architecture, and polish. No runtime testing was performed.

---

## Overall Score: 82 / 100 — "Production-capable, needs Polish"

The app is architecturally sound, well-tested, privacy-respecting, and technically close to submission-ready. The gaps are concentrated in launch polish, accessibility, and a few code-maintainability risks. After resolving the P0/P1 items below, Nalori can enter internal/closed testing with confidence.

---

## Scoring Breakdown

| Category | Score | Max | Weight |
|---|---|---|---|
| Architecture & Code Quality | 20 | 25 | High |
| Android / Play Store Config | 18 | 25 | High |
| Performance & Optimization | 13 | 15 | Medium |
| Testing & QA | 12 | 15 | Medium |
| Privacy & Compliance | 9 | 10 | Medium |
| UI/UX & Store Polish | 6 | 10 | Low |
| **TOTAL** | **78** | **100** | — |

> Adjusted upward to **82** for the strong privacy-first posture, comprehensive lint ruleset, and isolate-based heavy processing — traits rarely seen in apps at this stage.

---

## 1. Architecture & Code Quality (20 / 25)

### Strengths

- **Clean separation of concerns.** Models, services, screens, widgets, and utils are well-organized into distinct directories (`lib/models`, `lib/services`, `lib/screens`, `lib/widgets`, `lib/utils`). No circular dependencies observed.
- **Strong lint configuration.** `analysis_options.yaml` enforces 50+ rules covering performance (`prefer_const_constructors`), immutability (`prefer_final_fields`), memory safety (`cancel_subscriptions`, `close_sinks`), and type safety (`avoid_dynamic_calls`). This is excellent discipline.
- **Proper resource cleanup.** Controllers (`TextEditingController`, `ScrollController`, `AnimationController`) are consistently disposed in `dispose()` methods. Timer cancellation is handled (`_tapTimer?.cancel()`, `_selectionMenuTimer?.cancel()`).
- **Error handling is present.** `FlutterError.onError` and `PlatformDispatcher.instance.onError` are wired in `main.dart`. Services use explicit `throw` with typed exceptions. 56 `try` blocks across the codebase. `catch` blocks are present for async operations.
- **No dead code.** No `TODO`, `FIXME`, or `HACK` markers found. No leftover test-only code in production source.
- **Isolate usage is correct.** `BookCacheService` uses `Isolate.run()` for serialize/deserialize `lib/services/book_cache_service.dart:138`. `EpubParserService` runs parsing in an isolate via a top-level function `lib/services/epub_parser.dart:32`.
- **No unnecessary DI framework.** No unused state management packages (no Provider/Riverpod/BLoC). Uses simple constructor injection and manual singleton patterns — appropriate for this app's scope.

### Weaknesses

- **`reader_screen.dart` is 7,847 lines.** This is the single largest risk in the codebase. A single file this size makes debugging, testing, and future feature additions difficult. It holds page layout, chunking, settings, overlays, annotations, speed-read, bookmarks — effectively the entire reader experience in one monolithic `State`. This should be decomposed into smaller, focused widget classes.
- **`debugPrint` leakage.** ~40 `debugPrint` calls remain in production code across `reader_screen.dart`, `epub_parser.dart`, and `book_cache_service.dart`. While not a crash risk, they write to the system log on every user device. Should be gated behind `if (kDebugMode)` or replaced with a structured logger.
- **No localization / i18n.** All user-facing strings are hardcoded in English. No `MaterialApp.localizationsDelegates` or `intl` package. This limits market reach on Play Store.
- **No immutable model generation.** Models are hand-written with `const` constructors but lack `copyWith` consistency across all models. Some models (e.g., `ReadingSettings`, `ReadingChapterStats`) have `copyWith`; others do not.
- **`onActivityResult` uses deprecated override.** `MainActivity.kt:135` uses `@Deprecated("Deprecated in Java")` — should migrate to the `ActivityResultContracts` API for AndroidX compatibility.

---

## 2. Android / Play Store Config (18 / 25)

### Strengths

- **Application ID is correct.** `com.nalori.reader` is applied consistently in `build.gradle.kts:31` and `AndroidManifest.xml` namespace.
- **Release signing infrastructure exists.** `android/key.properties` points to `upload-keystore.jks` (2,267 bytes — a real keystore file). `build.gradle.kts:38-46` reads release signing config.
- **Method channels are well-structured.** Three channels (`quote_card/share`, `book_import`, `reader_controls`) handle native platform operations. Volume-button paging is implemented correctly with `dispatchKeyEvent` in `MainActivity.kt:96`.
- **FileProvider is configured for share flows.** `MainActivity.kt:176` uses `FileProvider.getUriForFile` for sharing quote cards — correct Android pattern.
- **Side-by-side manifest is minimal and clean.** Only `MAIN/LAUNCHER` intent filter. No exported services or receivers beyond the single `Activity`.
- **Permissions are justified.** `INTERNET` for optional dictionary/cover/public-domain features. `WRITE_EXTERNAL_STORAGE` capped at `maxSdkVersion="28"` — only applies to pre-Android 10 devices.
- **AndroidX is adopted.** `GeneratedPluginRegistrant.java` imports `androidx.annotation`. No legacy support library imports.

### Weaknesses

- **No code shrinking.** `build.gradle.kts:49-57` lacks `minifyEnabled`, `shrinkResources`, and `proguardFiles`. The AAB ships uncompressed and unobfuscated. Should enable R8 + a minimal ProGuard keep-rules file.
- **Release signing falls back to debug.** `build.gradle.kts:53-55` — if `key.properties` is absent, the release build silently uses the debug keystore. The `GradleException` on line 62 is a good safety net, but it fires too late (task-graph level). A CI pipeline could still produce a bad artifact if `key.properties` is missing but no `Release` task name matches. Better: fail early in `signingConfigs` block rather than after task graph resolution.
- **Launch screen is Flutter template.** `android/app/src/main/res/drawable/launch_background.xml` is the stock white background. No branded Nalori mark or dark theme. The cold-start gap between launch screen and the app's beautifully dark `ThemeData.dark()` with `#000000` background is jarring.
- **`CompressJPEG.Online_img(512x512).jpg` is in `assets/images/` but not declared in `pubspec.yaml`.** It is unreferenced and should be removed from the source tree, or evaluated as a test fixture.
- **No `android:allowBackup` or `android:fullBackupOnly` declaration.** Android 12+ requires explicit backup rules or `dataExtractionRules`. While not a rejection-causing issue for all apps, Play may flag it in pre-launch reports.
- **`minSdk` is tied to Flutter default.** `build.gradle.kts:32` uses `flutter.minSdkVersion`. This is currently fine but should be pinned to an explicit value before production to avoid surprise bumps.
- **No `targetSdkVersion` override.** Also tied to Flutter default. Should be explicitly set for Play Store target API level compliance tracking.

---

## 3. Performance & Optimization (13 / 15)

### Strengths

- **Isolate-based heavy lifting.** EPUB parsing, cache serialization, and deserialization all happen off the UI thread. This is the single most impactful performance decision in the app.
- **Display chunk caching.** `BookCacheService` manages a separate LRU-budgeted cache for display chunks (`CachedDisplayChunks`), avoiding recomputation on reader re-entry.
- **Lightweight library summaries.** Library cards now load summary data instead of decompressing full parsed book caches — a significant optimization for scroll performance in large libraries.
- **Debounced reader persistence.** Position writes and stats updates are batched/debounced. In-memory counters update immediately; disk flushes are deferred.
- **Measurement caching during display chunk rebuilds.** Rebuild-local caches avoid repeated `TextPainter` measurements for the same chunk/range/width.
- **Lazy lists are used correctly.** `ListView.separated`, `ListView.builder`, and `GridView.builder` are used for all scrollable collections. No eager `ListView(children: [...])` in hot paths.
- **Image loading uses `cacheWidth` where appropriate.** Cover images from disk are decoded at bounded sizes in `home_screen.dart`, `book_list_screen.dart`, and `book_loading_screen.dart`.
- **Speed-read rebuild optimization completed.** Per the implementation plan, speed-read tick work was reduced by caching span/painter artifacts.

### Weaknesses

- **`File.existsSync()` in build methods.** Present in `home_screen.dart`, `book_loading_screen.dart`, and `book_list_screen.dart`. Synchronous file I/O blocks the UI thread during frame build. Should precompute existence during state load.
- **Uncapped `Image.file` in quote card rendering.** `quote_card_canvas.dart:1841` and others call `Image.file()` without `cacheWidth`/`cacheHeight`, decoding full-resolution images for card rendering that doesn't need them.
- **130+ `debugPrint` calls with string interpolation.** While not individually expensive, many include template strings that are evaluated before the print call even in release mode. Should be gated.
- **Speed-read still rebuilds `SelectableText.rich` via `AnimatedBuilder` per word.** `reading_card.dart:2296` — every word tick triggers a full rich-text tree rebuild. This is acknowledged in prior reviews and marked as a lower-priority remaining item.

---

## 4. Testing & QA (12 / 15)

### Strengths

- **Test count is good.** 245 tests pass per prior audit verification (`flutter test` all green).
- **Test organization is excellent.** 34 test files organized into `test/unit/`, `test/widgets/`, and `test/mocks/`. Follows the testing strategy documented in `test/TESTING_STRATEGY.md`.
- **Both mockito and mocktail are available.** Tests use both libraries appropriately depending on the use case (mockito for class mocks, mocktail for function/closure mocks).
- **Comprehensive test coverage.** Unit tests cover models (7 files), services (14 files), UI helpers (3 files), and utils (1 file). Widget tests cover screens, overlays, and complex reading cards.
- **Manual testing checklist exists.** `test/MANUAL_APP_TESTING_CHECKLIST.md` covers 68 test cases across setup, first-run, import, public-domain, library, reader, annotations, sharing, themes, speed-read, and persistence.
- **Test helpers are extracted.** `test/test_helpers/test_utils.dart` centralizes common test utilities. `test/mocks/mock_data.dart` and `mock_services.dart` keep test fixtures DRY.
- **Testing strategy is documented.** `test/TESTING_STRATEGY.md` describes the test pyramid, directory structure, naming conventions, and CI considerations.

### Weaknesses

- **No integration or E2E tests.** The testing strategy document calls for integration and E2E tests, but none exist in the test suite. All 245 tests are unit or widget-level.
- **No golden/image tests.** Quote card rendering and book card generation lack visual regression tests. Given the complexity of the canvas rendering in `quote_card_canvas.dart` (2,015 lines, multiple style variants), this is a gap.
- **No CI/CD configuration.** No `.github/workflows/`, no GitLab CI, no Cirrus CI. The test suite must be run manually. For Play Store submission with future updates, automated testing on push is important.
- **Test coverage for `reader_screen.dart` is ambiguous.** The 7,847-line reader has widget tests but the sheer size of the file makes comprehensive coverage difficult. No coverage report is generated.
- **No performance benchmark tests.** No tests measure frame timing, memory usage, or load time for large EPUBs. Performance regressions can only be caught manually.

---

## 5. Privacy & Compliance (9 / 10)

### Strengths

- **Privacy policy draft is thorough.** `docs/privacy-policy-draft.md` is 121 lines, covering data stored locally, optional online features, third-party services used, permissions, data deletion, security, children, and contact information. It accurately reflects the current codebase.
- **No analytics, no crash reporting, no ads.** Zero analytics SDKs, crash reporting SDKs, or ad SDKs in `pubspec.yaml` or imports. This simplifies Play Store data safety declarations enormously.
- **No account system.** No authentication, no user profiles, no cloud sync — no data safety questions about account-backed data collection.
- **All network calls use HTTPS.** Gutendex (`gutendex.com`), Open Library (`openlibrary.org`), Free Dictionary API (`api.dictionaryapi.dev`) — all HTTPS endpoints.
- **No `READ_EXTERNAL_STORAGE` permission.** Only `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion="28"`, which does not trigger the broad storage permission warning on modern Android.
- **Contact email is provided.** `naloriapp@gmail.com` in the privacy policy.

### Weaknesses

- **Privacy policy is a draft, not published.** Before Play submission, this needs to be hosted at a public URL and linked in Play Console. The draft content is good — it just needs to be live.
- **No data safety form prepared.** Play Console requires filling out the Data safety section. The privacy policy draft covers the content, but the actual form mapping (data types collected, data shared, encryption, deletion) still needs to be filled.
- **Free Dictionary API uses unencrypted fallback?** `dictionary_service.dart:47` explicitly calls `http.get(Uri.parse('https://...'))`. This is HTTPS, so it's fine. But the URL is hardcoded — should be configurable for future API deprecation.

---

## 6. UI/UX & Store Polish (6 / 10)

### Strengths

- **Dark theme is well-implemented.** `main.dart:42` enforces `ThemeMode.dark` with a pure black AMOLED scaffold (`#000000`). The accent color (`#E85D04` — warm orange) is distinctive.
- **Consistent visual language.** `app_visuals.dart` centralizes the Nalori SVG mark. Reading cards have depth, shadows, and hover states. Quote cards have multiple style variants.
- **First-run education exists.** `HowToUseScreen` covers gestures, settings, privacy, and app features. User education service tracks whether it has been shown.
- **Loading states are handled.** `CircularProgressIndicator` and `LinearProgressIndicator` are used consistently. Empty states for library (no books) and search (no results) are present.
- **Error UI is present.** Book import errors, public-domain download errors, share/save failures, and dictionary lookup failures all show user-facing messages.

### Weaknesses

- **Launch screen is stock Flutter template.** The white/dark launch background does not match the app's brand. A simple branded splash with the Nalori mark would significantly improve perceived quality.
- **No content rating/age-gating preparation.** The privacy policy mentions children/target audience only in passing. Play Console requires a content rating questionnaire.
- **README is 3 lines.** `README.md` contains only a title and one-line description. No setup instructions, no feature list, no build instructions, no contribution guide.
- **No about/licenses page.** While `showAboutDialog` or `LicensePage` could surface OSS licenses automatically from Flutter, there is no accessible about screen. Play Store policy technically requires license attribution for OSS dependencies.
- **No feature graphic, screenshots, or store listing assets.** These are required for Play Console submission and are not present in the repo.
- **No Play Store short description or full description.** Not present in the repo. These need to be prepared before submission.

---

## Issue Severity Triage

### P0 — Must Fix Before Upload

| ID | Issue | Location |
|---|---|---|
| P0-1 | Release signing fallback to debug keystore is too permissive | `android/app/build.gradle.kts:53-55` |
| P0-2 | Rebuild `.aab` from clean commit, verify signer is not `CN=Android Debug` | Build pipeline |
| P0-3 | Publish privacy policy at a public URL, link in Play Console | `docs/privacy-policy-draft.md` |
| P0-4 | Fill Play Console Data safety form | Play Console |

### P1 — Strongly Recommended Before Public Launch

| ID | Issue | Location |
|---|---|---|
| P1-1 | Gate production `debugPrint` calls behind `if (kDebugMode)` | `reader_screen.dart`, `epub_parser.dart`, `book_cache_service.dart` |
| P1-2 | Add branded launch screen drawable | `android/app/src/main/res/drawable/launch_background.xml` |
| P1-3 | Enable R8 minification + ProGuard keep rules | `android/app/build.gradle.kts:49-57` |
| P1-4 | Remove `CompressJPEG.Online_img(512x512).jpg` or declare it in assets | `assets/images/` |
| P1-5 | Precompute cover file existence before widget build | `home_screen.dart`, `book_list_screen.dart`, `book_loading_screen.dart` |
| P1-6 | Add `cacheWidth`/`cacheHeight` to uncapped `Image.file` call sites | `quote_card_canvas.dart:1841` and neighbors |
| P1-7 | Create at least 4 screenshots and a feature graphic | Store listing assets |

### P2 — Important, Not Launch-Blocking

| ID | Issue | Location |
|---|---|---|
| P2-1 | Decompose `reader_screen.dart` (7,847 lines) into focused widgets | `lib/screens/reader_screen.dart` |
| P2-2 | Add integration/E2E tests covering: import → read → bookmark → quit → resume | `test/` |
| P2-3 | Add golden/image tests for quote card rendering | `test/widgets/` |
| P2-4 | Set up CI/CD with `flutter analyze` + `flutter test` on push | `.github/workflows/` |
| P2-5 | Add localization support (`intl`, ARB files) | `lib/` |
| P2-6 | Expand `README.md` with setup/build/feature documentation | `README.md` |
| P2-7 | Add about/licenses screen via `showLicensePage` or similar | New screen or `drawer.dart` |
| P2-8 | Migrate deprecated `onActivityResult` to `ActivityResultContracts` | `MainActivity.kt:135` |
| P2-9 | Pin `minSdk` and `targetSdk` explicitly | `android/app/build.gradle.kts:32-33` |
| P2-10 | Add `android:allowBackup` or `dataExtractionRules` | `AndroidManifest.xml` |

---

## Remediation Roadmap

### Phase 1: Pre-Submission (Estimated: 2–4 hours)

1. Confirm `android/key.properties` points to the production upload keystore.
2. Remove the `release { signingConfig = debug }` fallback in `build.gradle.kts`.
3. Rebuild the AAB from a clean git commit and run `jarsigner -verify` to confirm the signer.
4. Publish the privacy policy at a public URL.
5. Fill the Play Console Data safety form using the existing privacy policy draft as source.
6. Complete the Play Console content rating questionnaire.

### Phase 2: Polish Sprint (Estimated: 4–6 hours)

1. Gate all production `debugPrint` calls behind `if (kDebugMode)`.
2. Create a branded `launch_background.xml` with centered Nalori mark.
3. Enable R8 with `minifyEnabled true` and `shrinkResources true`; add minimal ProGuard rules.
4. Remove the unreferenced JPEG from `assets/images/`.
5. Fix `File.existsSync()` in build methods.
6. Add image decode bounds in quote card rendering.
7. Capture device screenshots (4 phone + 1 tablet).
8. Write store short description + full description.

### Phase 3: Production Hardening (Estimated: 1–2 weeks)

1. Decompose `reader_screen.dart` — target <2,000 lines per file.
2. Add 5–10 integration tests for critical user journeys.
3. Set up CI/CD (GitHub Actions, free tier).
4. Add golden tests for quote card rendering.
5. Start i18n scaffold (English ARB files, `AppLocalizations` delegate).
6. Write a real README.

---

## Final Verdict

Nalori is a **genuinely impressive indie app** at this stage. The architecture is clean, the performance decisions are well-reasoned (isolates for heavy work, caching, debouncing), the test suite is substantial (245 tests), and the privacy-first posture is exemplary for a reading app. The codebase shows clear signs of iterative refinement — prior performance audits have been acted upon, and the implementation plan tracks what has been completed.

The app is **ready for internal/closed testing** once the P0 items are resolved (signing verification, privacy policy publication, Data safety form). For an open/public production launch, resolve P1 items as well. The P2 items are improvements that should be addressed in the first post-launch update cycle.

**Do not upload the current AAB without first verifying the signer is not `CN=Android Debug`.**

---

*Review generated by opencode (deepseek-v4-pro). No codebase changes were made during this review except for the creation of this document.*
