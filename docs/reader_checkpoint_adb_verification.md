# Reader checkpoint physical-device verification

These checks cover Android termination behavior that the ordinary Flutter test
runner cannot reproduce. Use a debug build with bounded reader diagnostics:

```sh
flutter run --dart-define=NALORI_EPUB_DIAG=true
adb logcat | grep -E 'checkpoint_|restore_|layout_transition|stale_pagination|lazy_window'
```

Use one EPUB and keep its font, density, orientation, and viewport unchanged
unless the procedure explicitly says otherwise. Record the last
`checkpoint_store_success` card signature before termination and the
`restore_complete` signature after reopening.

## Force-stop

1. Open the book and rapidly move forward 20–50 cards.
2. As soon as the final card settles, run:

   ```sh
   adb shell am force-stop com.nalori.reader
   adb shell monkey -p com.nalori.reader -c android.intent.category.LAUNCHER 1
   ```

3. Reopen the book. With an unchanged layout, the restore strategy must be
   `exact_signature`, and the restored signature must equal the last successful
   durable signature.

## Background immediately after navigation

1. Navigate several cards rapidly and, immediately after the final settlement,
   run `adb shell input keyevent KEYCODE_HOME`.
2. Resume Nalori from the launcher or recents screen.
3. Confirm the exact signature is restored. Repeat while switching directly to
   another application.

## Remove from recents

1. Navigate to a distinctive card and wait only for the page to settle.
2. Run `adb shell input keyevent KEYCODE_APP_SWITCH`, then swipe Nalori away on
   the device (the swipe coordinates are device-specific).
3. Launch Nalori again with the `monkey` command above and verify the exact
   signature.

## Kill during density reflow

1. Change density and immediately force-stop after
   `layout_transition_candidate`/`checkpoint_store_success` for
   `layoutTransitionPending`, but before `restore_reflow_complete` succeeds.
2. Relaunch Nalori. It must apply the persisted target settings, resolve the
   saved semantic block/UTF-16 offset, and durably commit the containing card
   under the new layout.
3. Force-stop and reopen once more without changing layout. The second reopen
   must use `exact_signature` and reproduce that newly committed signature.
4. Repeat while changing density several times quickly. Confirm older
   generations emit `stale_pagination_rejected` (or the existing display
   generation cancellation diagnostic) and never publish or commit.

Do not compare page numbers: compare card signatures for unchanged layouts and
the logged semantic block identity plus UTF-16 offset for changed layouts.
