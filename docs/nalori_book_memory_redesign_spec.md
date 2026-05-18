# Nalori Book Memory Redesign — Product + Implementation Spec

## 0. Purpose

This document defines the redesigned **Book Memory** feature for Nalori.

The current Book Memory implementation is mostly a gallery/archive of things the user saved while reading:

- Bookmarks
- Highlights
- Notes
- Saved dictionary words
- Character tags/highlights
- Basic reading progress

That is useful, but it is not enough.

The new direction is:

> **Book Memory should be a per-book thinking and writing space, not just a saved-items gallery.**

Every saved reading moment should become something the user can open, think about, write around, organize, and eventually export.

Book Memory should feel like:

- a reading journal
- a book-specific notes app
- a place to offload thoughts
- a way to turn passive highlights into active thinking
- a personal archive for each book

It should still show bookmarks/highlights/notes/words/characters, but those should act as **source material** for deeper writing.

---

## 1. Core Product Idea

### Current mental model

```text
Book Memory = everything saved from this book
```

### Desired mental model

```text
Book Memory = a notebook for this book, powered by saved reading moments
```

A bookmark, highlight, note, word, or character is not only an item in a list. It can become a **writing prompt**.

Example:

```text
User highlights a sentence
→ It appears in Book Memory
→ User opens it
→ User sees the highlighted sentence and context
→ User can add a title and long-form thoughts
→ That becomes a Book Memory entry
```

The same should work for:

- bookmarks
- highlights
- notes
- saved words
- character tags
- free book-level notes

---

## 2. Feature Principles

### 2.1 Reading-first

Book Memory should support reading, not distract from it.

The user should be able to:

- quickly return to text
- view what they saved
- write thoughts without friction
- avoid clutter if they accidentally open a writing page

### 2.2 Saved items and written thoughts are separate

A saved highlight is not the same as a written note about that highlight.

A bookmark is not the same as a journal entry about that bookmark.

A saved word is not the same as the user’s own memory hook or explanation.

So the app needs a separation between:

```text
Source item = bookmark / highlight / reader note / word / character
Book Memory Entry = user-written title/body attached to that source item
```

### 2.3 Do not create empty writing entries

If a user opens a writing page and does not type anything, do not save anything.

A Book Memory Entry should only be created if the user adds:

- a title, or
- body text

If both title and body are empty, leaving the page should not create clutter.

### 2.4 Calm premium UI

Book Memory should match Nalori’s visual language:

- dark/light theme aware
- rounded cards
- subtle borders
- muted surfaces
- accent color used intentionally
- readable spacing
- no noisy dashboards
- no overly bright destructive actions

### 2.5 Writing space matters

The actual writing page should feel like a real notes app page, not a small modal.

The user should get a proper full-page or near-full-page writing area.

---

## 3. Required New Concept: BookMemoryEntry

Add a new data concept for long-form writing inside Book Memory.

Suggested model:

```dart
class BookMemoryEntry {
  final String id;
  final String bookId;

  /// bookmark | highlight | note | word | character | free
  final String sourceType;

  /// ID of the linked source item.
  /// Null when sourceType == free.
  final String? sourceId;

  final String title;
  final String body;

  final int createdAtMs;
  final int updatedAtMs;
}
```

### Source types

Use stable source type values:

```text
bookmark
highlight
note
word
character
free
```

### Important behavior

- One source item can have one BookMemoryEntry for now.
- If the entry already exists, opening the writing page should edit the existing entry.
- If no entry exists, opening the writing page should show empty title/body fields.
- If the user exits with both title and body empty, do not create an entry.
- If an existing entry is edited and both title/body become empty, ask whether to delete the entry.

### Storage

Create a storage/service layer, for example:

```text
lib/services/book_memory_entry_service.dart
```

Responsibilities:

- load entries by bookId
- load entry by sourceType + sourceId
- create/update entry
- delete entry
- count entries
- search entries
- expose helper: hasEntryForSource(sourceType, sourceId)

Do not duplicate bookmark/highlight/note/word/character storage. BookMemoryEntry should only store the user’s extra writing.

---

## 4. Main Screens Needed

Implement Book Memory as a set of screens/components, not a single giant list.

### Required screens

1. `BookMemoryScreen`
2. `BookMemorySourceDetailScreen`
3. `BookMemoryWritingScreen`
4. Optional later: `BookMemoryEntryViewerScreen` if view/edit modes are separated

---

# 5. BookMemoryScreen

## 5.1 Purpose

This is the home screen for a book’s memory/journal.

It should be accessible from the book list/book card menu.

It should not require opening the reader first.

## 5.2 Header

Header should show:

- Back button
- Book title
- Author if available
- Export/share icon, if export exists or is planned

Example:

```text
←   The Trial
    Franz Kafka                                      export icon
```

## 5.3 Tabs

Keep the current tabs, but make them feel like notebook sections:

```text
Overview | Bookmarks | Highlights | Notes | Words | Characters
```

If the tabs overflow horizontally, allow horizontal scrolling.

## 5.4 Overview redesign

The Overview tab should not feel like only a stats dashboard.

It should communicate:

```text
This is your notebook for this book.
```

Recommended structure:

### Top progress card

Shows:

- reading percentage
- progress bar
- last read date/time
- current chapter/location if available

### Primary writing action

Add a button/card:

```text
+ New Book Note
```

This creates a free BookMemoryEntry:

```text
sourceType = free
sourceId = null
```

Use case:

- overall thoughts
- theories
- chapter summaries
- book review draft
- emotional reaction
- random thoughts not linked to a highlight

### Recent thoughts section

Show recent BookMemoryEntries that have user-written content.

Example:

```text
Recent thoughts
- Why K. feels trapped
- Notes on Chapter 3
- My theory about the trial
```

If no written entries exist:

```text
No book thoughts yet
Write about a bookmark, highlight, word, character, or start a free book note.
```

### Collected section

Then show the saved item counts:

- Bookmarks
- Highlights
- Notes
- Saved Words
- Characters

Each should still be tappable and open the relevant tab.

## 5.5 Current overview issue

The current implementation shows counts clearly, but it feels like:

```text
stats + list
```

Improve it so it feels like:

```text
journal home + saved reading material
```

---

# 6. Saved Item List Tabs

Each tab should list saved source items. The list items should support two separate actions:

1. View the source item/details
2. Open/write the Book Memory entry attached to that item

This distinction is important.

## 6.1 Interaction model

Recommended interaction:

```text
Tap main card area -> open source detail page
Tap small pencil/notebook icon -> open writing page
Tap chevron only if it means source detail
```

Avoid using only `>` for writing because users usually understand chevron as “open details.”

Better right-edge actions:

```text
[small pencil icon]  = write/edit memory entry
[chevron]           = view source detail
```

If only one trailing icon can fit, prefer a pencil/notebook icon for writing and make the main card open details.

## 6.2 Written-state indicator

Each saved item should visually indicate whether it already has a BookMemoryEntry.

Examples:

```text
Empty pencil icon = no writing yet
Filled note icon = has writing
Small dot/badge = has writing
```

This helps users know which saved moments have been turned into actual thoughts.

## 6.3 Global list controls

For each tab, add or prepare for:

- Search
- Sort
- Filter

Minimum sort/filter requirements:

### Sort options

```text
Reading order
Recently marked
Oldest marked
Recently written
Color
```

### Filter options

```text
All
Has writing
No writing yet
Color
```

Color sorting/filtering should apply where color exists:

- highlights
- character tags
- possibly bookmarks if bookmarks have colors

---

# 7. Bookmark Tab

## 7.1 Bookmark list card

Each bookmark card should show:

- Bookmark label/title
- Chapter name
- Page/chunk/location
- Date saved
- Text preview
- Written-state indicator
- Small action to write/edit memory entry

Example:

```text
Bookmark 7                                      [pencil]
Chapter 8 - Block, the businessman
Page/Chunk 1532 · 2026-05-12

"Well of course you have," called out K...
```

## 7.2 Bookmark source detail page

When tapping the main bookmark card area, open a source detail screen.

Show:

- Type label: Bookmark
- Chapter
- Page/chunk/location
- Date saved
- Bookmarked text/context
- Actions:
  - Go to text
  - Write about this
  - Delete bookmark, if supported

## 7.3 Bookmark writing page

When opening the writing page for a bookmark:

```text
Bookmark Entry

Title
[optional title field]

Bookmarked text
[fixed source preview card]

My thoughts
[large writing area]
```

The fixed source preview should not take too much space. If long, make it collapsible.

---

# 8. Highlights Tab

## 8.1 Highlight list card

Each highlight card should show:

- Left vertical color bar using highlight color
- Highlight text preview
- Chapter
- Page/chunk/location
- Date marked
- Written-state indicator
- Small action to write/edit memory entry

Avoid repeating the same highlighted text twice.

## 8.2 Highlight source detail page

When tapping a highlight card, open a detail page that shows the highlighted text cleanly.

Important:

- The highlighted text should be shown without full highlight background colors.
- Use a simple quote card.
- Show metadata separately.

Detail page should show:

```text
Highlight

"Highlighted text..."

Chapter: ...
Location: ...
Color: Orange
Marked on: ...
Type: normal / character / note-linked, if available
```

Actions:

- Go to text
- Write about this
- Delete highlight, if supported

## 8.3 Highlight writing page

```text
Highlight Entry

Title
[optional]

Highlighted passage
[fixed quote/source card]

My thoughts
[large writing area]
```

The source quote card should be collapsible if long.

---

# 9. Notes Tab

Notes are different because they already contain user-written quick notes from the reader.

Book Memory writing should not overwrite or confuse the original reader note.

## 9.1 Conceptual separation

```text
Reader note = quick note attached while reading
Book Memory entry = deeper reflection/writing about that reader note
```

## 9.2 Notes list card

Each note card should show:

- User’s original reader note as primary text
- Chapter/page/location
- Selected text preview as secondary text
- Written-state indicator for deeper BookMemoryEntry
- Small action to write/edit deeper memory entry

Example:

```text
Original note text...                          [pencil]
Page 13 · THE TURN OF THE SCREW
"Selected text preview..."
```

## 9.3 Note source detail page

When tapping the note card, show original note detail:

```text
Note

Original note:
[test test test]

Selected text:
[collapsible quote box]

Chapter
Location
Date
Color/source info if available
```

Actions:

- Go to text
- Write more about this
- Edit original note
- Delete note

## 9.4 Note writing page

This is for deeper writing about an existing note.

```text
Note Reflection

Title
[optional]

Original note
[fixed source card]

Selected text
[collapsible quote card]

More thoughts
[large writing area]
```

Do not confuse this with editing the original reader note.

---

# 10. Words Tab

## 10.1 Word list card

Each word card should show:

- Word
- Definition
- Chapter/location if available
- Date saved if available
- Written-state indicator
- Small action to write/edit memory entry

## 10.2 Word source detail page

Show:

```text
Word

Definition

Saved from:
Chapter
Location
Original sentence/context if available
```

Actions:

- Go to text, if location exists
- Write about this
- Delete saved word, if supported

## 10.3 Word writing page

```text
Word Note

Title
[optional]

Word + definition
[fixed source card]

Context sentence
[optional/collapsible]

My thoughts / memory hook
[large writing area]
```

Use case:

- vocabulary memory hook
- why the word mattered
- personal example sentence

---

# 11. Characters Tab

Characters can become one of Nalori’s most unique Book Memory features.

## 11.1 Character list

Group character-tagged highlights by character/name if possible.

Each character card should show:

- Character/name
- Color dot/bar
- Number of user-marked moments
- First marked location
- Mention count, if available
- Written-state indicator
- Small action to write/edit character notes

Example:

```text
K.                                      [pencil]
3 marked moments · 47 mentions
First marked: Chapter 1
```

## 11.2 Character source detail page

When opening a character detail page, show:

```text
Character: K.
Color: Orange

First marked:
Chapter X · location

User-marked moments:
- quote 1
- quote 2
- quote 3

Occurrences in book:
47 mentions
```

### Mention count

If possible, calculate how many times the character name occurs in the parsed book text.

Implementation note:

- Use parsed chunks/search index if available.
- Count case-sensitive or case-insensitive depending on existing character matching behavior.
- Avoid false positives where possible, but do not over-engineer initially.

If mention count is not available yet:

- show marked moments count only
- leave a TODO for mention count

## 11.3 Character writing page

```text
Character Notes

Title
[optional]

Character info
[name, color, first marked, marked moments count, mention count]

Marked moments
[collapsible list]

My thoughts
[large writing area]
```

Use case:

- character theories
- relationship notes
- timeline notes
- emotional reaction

---

# 12. Free Book Notes

Add support for free book-level notes.

This is important because not every thought is attached to a saved item.

## 12.1 Entry point

On Overview tab, add:

```text
+ New Book Note
```

## 12.2 Free note writing page

```text
Book Note

Title
[optional]

My thoughts
[large writing area]
```

No source preview is needed.

## 12.3 Where free notes appear

Free notes should appear in:

- Overview → Recent thoughts
- Maybe a future “Journal” tab
- Search results
- Export

Consider adding a future tab:

```text
Journal
```

But do not add it immediately unless needed.

---

# 13. BookMemoryWritingScreen

## 13.1 Purpose

This is the main writing space.

It should feel like a notes app page.

It should not feel like a small modal or CRUD form.

## 13.2 Layout

Recommended layout:

```text
Header:
Back button             Save status / Done

Source type label:
Highlight / Bookmark / Note / Word / Character / Book Note

Title field:
Untitled / Add title

Source preview area:
Fixed details about the source item
Collapsible if long

Writing area:
Large text field
```

## 13.3 Source preview

The source preview is fixed/reference material.

The writing area is editable user thought.

They must be visually separate.

### Source preview rules

- It should not take over the whole page.
- If long, collapse it by default.
- Show “Show more / Show less” or chevron expand.
- Source preview should be read-only.

## 13.4 Writing area

The writing area should be the main focus.

Requirements:

- multiline
- large enough to feel like a page
- no artificial small height
- keyboard friendly
- auto-scroll when typing
- theme-aware
- comfortable text size

## 13.5 Save behavior

Use auto-save or simple save-on-exit.

Recommended:

```text
Auto-save after user enters title/body.
Do not create entry while both title and body are empty.
```

Rules:

- If no existing entry and title/body are empty: back exits without saving.
- If no existing entry and user types title/body: create entry.
- If existing entry and user edits: update entry.
- If existing entry and user clears both title/body: ask whether to delete memory entry.

## 13.6 Save status

Optional but useful:

```text
Saved
Saving...
Unsaved
```

Keep it subtle.

---

# 14. BookMemorySourceDetailScreen

## 14.1 Purpose

This screen shows the saved source item clearly.

It is not the writing page.

It answers:

```text
What is this saved thing?
Where did it come from?
What actions can I take?
```

## 14.2 Common layout

```text
Header:
Back
Item type
Write icon / Go to text / menu

Main content:
Source item details

Actions:
Go to text
Write about this
Delete, if supported
```

## 14.3 Source types

Implement detail rendering per type:

- bookmark detail
- highlight detail
- note detail
- word detail
- character detail

Do not overcomplicate. Use shared components where possible.

---

# 15. Sorting, Filtering, and Search

Book Memory should eventually support sorting and filtering across the whole feature.

## 15.1 Required now or soon

At least implement sorting/filtering in a clean way so it can be expanded.

Useful sort options:

```text
Reading order
Recently marked
Oldest marked
Recently written
Color
```

Useful filters:

```text
Has writing
No writing yet
Color
Type
```

## 15.2 Color sorting/filtering

User requested the whole Book Memory to be sortable by color and when it was marked.

Where color applies:

- highlights
- character tags
- maybe bookmarks if bookmark color exists
- maybe notes if note-linked highlight has color

Color sort should group by color in a stable order.

Color filter should only show colors that actually exist in the current book memory data.

Do not hardcode color filters.

## 15.3 Search

Search should eventually include:

- bookmark preview text
- highlighted text
- original reader notes
- dictionary words
- dictionary definitions
- character names
- BookMemoryEntry titles
- BookMemoryEntry bodies

---

# 16. Export Requirements

The original Book Memory goal included export. The new writing model makes export more valuable.

Export should eventually include both:

1. saved source items
2. user-written BookMemoryEntries

## 16.1 Markdown export structure

Suggested single-file export:

```md
# The Trial — Book Memory

Author: Franz Kafka
Progress: 74%
Last read: 2026-05-12

## My Book Notes

### Why K. feels trapped

My thoughts...

## Bookmarks

### Bookmark 7

Source:
> bookmarked text

My thoughts:
...

## Highlights

### Highlight from Chapter 3

Source:
> highlighted text

My thoughts:
...

## Notes

### Original note

Source note:
...

Selected text:
> ...

More thoughts:
...

## Saved Words

### inclined
Definition: ...
My memory hook: ...

## Characters

### K.
Marked moments: 3
Mentions: 47
My thoughts: ...
```

## 16.2 Export formats later

Free/basic:

- single Markdown export for one book

Pro/later:

- folder/zip export
- export all books
- JSON backup
- Obsidian-ready folder
- CSV dictionary export
- AI summary
- cloud sync

Do not add premium gating unless premium infrastructure already exists.

---

# 17. UI Redesign Notes

## 17.1 Current issue

The current screen is clean but basic. It looks like a data dashboard.

Improve it to feel like a notebook.

## 17.2 Design direction

Use language like:

- Book Journal
- Recent thoughts
- Collected from reading
- Write about this
- My thoughts
- Source

Avoid making it feel like a database.

## 17.3 Card style

Cards should be:

- rounded
- subtle border
- dark/light theme aware
- not too tall unless content requires it
- readable but compact

## 17.4 Actions

Avoid too many icons on each card.

Recommended:

- main card tap = source detail
- small pencil/notebook icon = write/edit memory
- optional chevron = details if needed

## 17.5 Empty states

Examples:

### No written thoughts

```text
No book thoughts yet
Write about a bookmark, highlight, word, character, or start a free book note.
```

### No highlights

```text
No highlights yet
Highlight lines while reading to collect important moments here.
```

### No characters

```text
No character notes yet
Tag names while reading to build a character map.
```

---

# 18. Navigation Back to Reader

Saved items should support “Go to text” where possible.

Supported:

- bookmarks
- highlights
- notes
- saved words with location
- character marked moments

Behavior:

```text
Open ReaderScreen for the book
Jump to original chunk/display page/location
Optionally focus or briefly flash the source item
```

If a source item lacks location data, disable or hide Go to Text gracefully.

---

# 19. Implementation Phases

Do not implement everything in one huge risky change.

Recommended phases:

## Phase 1 — Data model and writing page

- Add BookMemoryEntry model/service
- Add writing page
- Allow writing entries attached to bookmarks/highlights/notes/words/characters
- Do not save empty entries

## Phase 2 — Source detail pages

- Add source detail screen
- Main card tap opens detail
- Pencil opens writing page
- Add written-state indicators

## Phase 3 — Overview redesign

- Add New Book Note
- Add Recent thoughts
- Move saved counts into “Collected from reading”
- Make the screen feel like a notebook

## Phase 4 — Sort/filter/search

- Add sort by marked date
- Add sort/filter by color
- Add filter: has writing / no writing
- Improve search

## Phase 5 — Character detail upgrade

- Group by character
- Show first marked location
- Show marked moments
- Add mention count if feasible

## Phase 6 — Export upgrade

- Export Markdown including source items and user writing
- Later: folder/zip/JSON/Obsidian export

---

# 20. Acceptance Criteria

## Book Memory concept

- Book Memory is no longer just a gallery of saved items.
- Users can write long-form thoughts attached to saved items.
- Users can also create free book-level notes.

## Data

- BookMemoryEntry exists separately from saved source data.
- Source items are not duplicated.
- Empty entries are not created.
- Existing saved bookmarks/highlights/notes/words/characters remain intact.

## List behavior

- Main card tap opens source detail.
- Pencil/notebook action opens writing page.
- Cards show whether writing already exists for that source item.

## Writing page

- Has optional title field.
- Shows source item in a fixed read-only area.
- Provides a large writing area.
- Does not save empty entries.
- Saves/updates non-empty entries.

## Source detail

- Shows source item clearly.
- Has Go to Text where possible.
- Has Write about this action.

## Overview

- Shows reading progress.
- Shows New Book Note action.
- Shows recent written thoughts.
- Shows saved item counts.

## Sorting/filtering

- Structure supports sorting by marked date and color.
- Structure supports filtering by written/unwritten status.

## UI

- Feels like a book notebook/journal.
- Matches Nalori’s calm premium aesthetic.
- Works in dark and light themes.
- No layout overflow on small screens.

## Export readiness

- Export service should eventually include both source items and BookMemoryEntry writing.
- Markdown export should be easy to extend.

---

# 21. Important Non-Goals for Initial Implementation

Do not implement these immediately unless simple and safe:

- AI summary
- cloud sync
- payment gating
- multi-entry per source item
- rich text editor
- image attachments
- voice notes
- full Obsidian folder export
- advanced character graph

The first goal is to make Book Memory a usable writing space.

---

# 22. Short Summary for Codex

Build Book Memory into a per-book notebook.

Every saved item — bookmark, highlight, note, word, character — should have:

1. a source detail view
2. an optional linked writing entry

The writing entry should have:

- optional title
- fixed source preview
- large user writing area
- no save if empty

The Overview should feel like a journal home with:

- reading progress
- New Book Note
- recent thoughts
- collected item counts

This should be implemented with a separate `BookMemoryEntry` model/service so user-written thoughts are not mixed with the original saved source data.
