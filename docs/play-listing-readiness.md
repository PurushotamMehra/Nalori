# Nalori Play Listing Readiness

This document keeps Play Console launch copy and asset guidance in the repo.
Final screenshots and feature graphics should come from a real device or
emulator capture pass.

## Listing Copy

Short description:

Private EPUB reading with a focused library, reader controls, notes, highlights,
and quote-card sharing.

Full description:

Nalori is a personal EPUB reader built for quiet, distraction-free reading.
Import EPUB files from your device, browse public-domain books, and keep your
reading progress, bookmarks, notes, highlights, and saved words organized in one
local library.

Nalori includes flexible reader settings for typography, themes, paging,
reading comfort, and Speed Read mode. You can open chapters, search within a
book, save annotations, look up words, and share polished quote or book cards.

Core features:

- Import EPUB files from the device picker.
- Browse free public-domain books.
- Track progress, streaks, and optional reading insights.
- Add bookmarks, notes, highlights, and character marks.
- Search, chapter navigation, and page jumping while reading.
- Customize theme, font, line height, layout, and paging style.
- Create shareable quote, book, and reading recap cards.

Privacy summary:

Nalori is designed for private reading. EPUB files, reading progress, notes,
highlights, bookmarks, and saved words stay on the device by default. Optional
online book-detail enhancement may send book title or author text to Open
Library to find cleaner metadata and covers. Book files are not uploaded for
that lookup.

## Screenshot Checklist

Capture at least four phone screenshots for the Play listing:

- Library with several books, visible covers, add-book action, and drawer access.
- Reader page with top and bottom controls open, showing page scrubber and tools.
- Chapter and bookmark panel with realistic chapter names.
- Annotation or quote-card flow showing highlights or share-card preview.
- Optional: reading stats screen if enabled data looks realistic.

Capture guidance:

- Use a clean release or release-like build with test EPUBs.
- Avoid personal book files, personal notes, or private account data.
- Use a dark theme to match the launch experience.
- Confirm no placeholder privacy URL is visible in listing screenshots.
- Check all visible text at phone aspect ratios before upload.

## Feature Graphic Brief

Size: 1024 x 500 px.

Direction: dark, quiet reading-focused composition using Nalori's existing mark,
a readable book cover or abstract page surface, and minimal text. Avoid busy
device mockups, dense UI, or marketing claims that are not visible in the app.

Suggested text: Nalori

## Content Rating Notes

Nalori is an EPUB reader and may display user-provided or public-domain text.
The app itself does not include social feeds, gambling, shopping, user-to-user
messaging, or explicit first-party content. Content rating answers should
reflect the app shell and the fact that imported books are user-selected.

## Data Safety Mapping

Data collected by Nalori by default:

- No account data.
- No location data.
- No contacts.
- No advertising ID use.
- No user files uploaded by default.

Data processed locally:

- EPUB files imported by the user.
- Reading progress and reading statistics.
- Bookmarks, notes, highlights, saved words, and preferences.
- Generated quote or book card images.

Optional network processing:

- If the user enables online book-detail enhancement, book title and author text
  may be sent to Open Library to search metadata and covers.

Backup policy:

- Android cloud backup and device-transfer extraction are disabled for private
  reading data in this release configuration.

## Pre-Submission Tasks

- Replace the privacy-policy placeholder with the production URL in app and Play
  Console materials.
- Run a real-device accessibility pass with TalkBack on library, reader, chapter
  panel, annotations, settings, and quote sharing.
- Build the signed release bundle with a complete `android/key.properties`.
- Verify the release signer is not the Android debug certificate.
