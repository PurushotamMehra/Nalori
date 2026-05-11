# Nalori Play Store Readiness and Performance Audit

Audit date: 2026-05-04

Scope: validate the existing `PERFORMANCE_AUDIT.md`/DeepSeek review against current source, check Android release readiness, and identify rough edges before a near-term Play Store submission.

## Verdict

Nalori is close, but the current repository is not ready to upload to Play Console as-is.

The app passes static analysis, passes the full Flutter test suite, and can produce a release app bundle. The blocker is packaging/signing: the generated release `.aab` is signed with the Android debug certificate because `android/key.properties` is absent and `android/app/build.gradle.kts` falls back to the debug signing config. Play Console will reject or make this unusable for a real production release.

## Verification Run

| Check | Result | Notes |
|---|---:|---|
| `flutter analyze` | Pass | No analyzer issues found. |
| `flutter test` | Pass | 245 tests passed. |
| `flutter build appbundle` | Pass | Built `build/app/outputs/bundle/release/app-release.aab`, 47.3 MB. |
| AAB signer inspection | Fail for release | `jarsigner` reports signer `CN=Android Debug`. |
| Git state | Dirty | Multiple existing source files are modified and `PERFORMANCE_AUDIT.md` was untracked before this overwrite. Review before tagging/releasing. |

Environment used:

- Flutter 3.35.7 stable
- Dart 3.9.2
- Android Gradle Plugin 8.9.1
- App version in `pubspec.yaml`: `0.1.0+1`

## Play Store Blockers

### P0 - Release Bundle Is Debug-Signed

Evidence:

- `android/app/build.gradle.kts` uses release signing only when `android/key.properties` exists.
- If it does not exist, `release.signingConfig` falls back to `signingConfigs.getByName("debug")`.
- Current bundle verification shows signer `C=US, O=Android, CN=Android Debug`.

Impact:

- This `.aab` should not be uploaded as the first Play Store artifact.
- Even if upload were accepted somewhere in an internal path, it is the wrong signing identity for production.

Required before upload:

- Add the real upload key configuration locally in `android/key.properties` or configure signing in CI/secrets.
- Remove or hard-fail the debug fallback for `release` builds so a bad artifact cannot be produced accidentally.
- Rebuild and verify the signer again before upload.

### P0 - Release Candidate Is From a Dirty Worktree

Evidence:

- `git status --short` shows modified app source files in models, screens, services, tests, and `pubspec.yaml`.

Impact:

- The tested artifact may include unreviewed local changes.
- A Play submission should be traceable to a clean commit/tag.

Required before upload:

- Review the modified files, commit the intended release state, and rebuild from that clean commit.

## Play Store Rough Edges

### P1 - Version Is Still Initial Placeholder

Evidence:

- `pubspec.yaml` is `version: 0.1.0+1`.
- `android/local.properties` maps this to `flutter.versionName=0.1.0` and `flutter.versionCode=1`.

Impact:

- This is acceptable for the first upload, but it looks like an early internal build.
- After the first Play upload, `versionCode` must increase for every release.

Recommendation:

- Decide whether the launch should be `1.0.0+1` or keep `0.1.0+1` for closed/internal testing.

### P1 - Launch Screen Is Still Flutter Template-Like

Evidence:

- `android/app/src/main/res/drawable/launch_background.xml` is the stock white background with commented placeholder image.
- `drawable-v21/launch_background.xml` uses `?android:colorBackground`.

Impact:

- Not a Play blocker, but the cold start experience is less polished than the app UI.

Recommendation:

- Add a simple branded launch background or centered Nalori mark before public release.

### P2 - Broad Internet Permission Must Match Store Disclosure

Evidence:

- `AndroidManifest.xml` declares `android.permission.INTERNET`.
- App features include dictionary and public-domain book lookup/download, so the permission appears justified.

Impact:

- Not a blocker, but Play listing privacy/data-safety answers must disclose network usage accurately.

### P2 - Legacy External Storage Permission Is Probably Harmless But Should Be Rechecked

Evidence:

- `WRITE_EXTERNAL_STORAGE` is declared with `android:maxSdkVersion="28"`.

Impact:

- This should not affect modern Android devices, but it is worth confirming the export/share/save flows do not need any broader storage permissions.

Recommendation:

- Keep it only if pre-Android 10 export behavior still needs it; otherwise remove it to reduce permission surface.

## DeepSeek Performance Review Validity

The prior audit was directionally useful, but it overstated some issues and missed release readiness blockers.

### Valid Findings

| Finding | Current validity | Notes |
|---|---:|---|
| Batched reader persistence writes implemented | Valid | Debounced position/stats persistence is present. |
| Lightweight library summaries implemented | Valid | Current modified source includes summary model/load paths. |
| Reader layout measurement cache implemented | Valid | `reader_screen.dart` has text measurement caching around the display chunk path. |
| Speed-read rebuild work remains | Valid | `reading_card.dart` still rebuilds selectable rich text from an `AnimatedBuilder` during speed-read updates. |
| Sync `File.existsSync()` in build methods | Valid | Present in `home_screen.dart`, `book_loading_screen.dart`, and `book_list_screen.dart`. |
| Some `Image.file` calls lack decode sizing | Valid | `quote_card_canvas.dart` still has several uncapped file image decodes. |
| Chapter panel uses eager `ListView(children: ...)` | Valid | Current `chapter_panel.dart` eagerly maps chapter entries. |
| `jsonDecode` for stats on main isolate | Valid but lower priority | The data shape is bounded by daily stats and book insights; not a launch blocker. |

### Overstated Or Stale Findings

| Finding | Status | Correction |
|---|---|---|
| `debugPrint` calls are a high-impact performance issue | Overstated | They are noisy and some interpolate strings before call, but this is not a Play blocker. Convert routine parser/cache logs to debug-only before launch. Keep crash diagnostics intentional. |
| `main.dart` debug prints should stay as-is | Partly questionable | Release crash logging through `debugPrint` is weak. Consider a real crash reporter later; do not treat this as a performance optimization. |
| `MediaQuery.of` missed in only 3 places | Mostly valid but minor | The listed spots exist, but this is cleanup, not release readiness. |
| `SingleChildScrollView` settings panel is a material launch risk | Overstated | It may be optimized later; current analyzer/tests/build do not indicate a blocker. |
| Metadata-only `EpubReader.openBook()` is unused | Valid but not urgent | `book_metadata_service.dart` and `epub_parser.dart` still call `readBook()`. This matters for large imports, not Play upload. |

## Highest-Value Fixes Before Upload

1. Configure real release signing and make missing signing fail the release build.
2. Rebuild the `.aab` from a clean commit and verify the signer is not `Android Debug`.
3. Decide launch version name/code and update `pubspec.yaml` if needed.
4. Replace routine release logging with `if (kDebugMode) debugPrint(...)` or a small local debug logger.
5. Remove `File.existsSync()` from widget build methods by precomputing cover existence during load/state updates.
6. Add decode bounds to remaining cover `Image.file` call sites in quote card rendering.
7. Do a device smoke test on a release build: first launch, import EPUB, open reader, swipe 20 pages, dictionary lookup, public-domain download, quote/card export/share, app resume after backgrounding.

## Release Checklist

- [ ] Clean worktree or intentional release commit.
- [ ] Real upload signing configured outside git.
- [ ] `flutter build appbundle` produces a non-debug-signed `.aab`.
- [ ] Play Console package name confirmed: `com.nalori.reader`.
- [ ] Version code/name chosen for launch track.
- [ ] Data safety form covers public-domain lookup/download, dictionary/network calls, local EPUB files, saved words/highlights/bookmarks/stats.
- [ ] Store listing assets ready: icon, feature graphic, screenshots, short description, full description.
- [ ] Release smoke test completed on at least one physical Android device.

## Bottom Line

Do not upload the current `app-release.aab`.

After fixing signing and rebuilding from a clean release commit, the app looks technically close enough for internal or closed testing. The performance rough edges are real but not severe enough to block an initial Play track unless manual smoke testing exposes jank on large EPUBs.
