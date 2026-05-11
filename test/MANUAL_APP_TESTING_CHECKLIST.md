# Nalori Manual App Testing Checklist

Use this checklist for hands-on testing on a real Android device or emulator. Test with at least one known-good EPUB, one large EPUB, and one intentionally invalid or non-EPUB file.

## Setup

| Test | Expected Output |
| --- | --- |
| Install a fresh debug or release build with no previous app data. | App installs and opens without crashes. |
| Launch after clearing app storage. | First-run education screen appears once. |
| Relaunch after completing first-run education. | First-run education does not appear again. |
| Launch with airplane mode enabled. | App opens; local library and reader remain usable. Online features fail gracefully. |

## First Run And Help

| Test | Expected Output |
| --- | --- |
| Tap `Start reading` on the first-run screen. | App continues to the Library or continue-reading flow. |
| Open hamburger menu, tap `How to use Nalori`. | Help screen opens and shows all guidance sections. |
| Back out of the help screen. | Returns to Library without changing library state. |
| Check hamburger menu entries. | Only working entries are shown: Reading Stats, How to use Nalori, Themes, and Enhance book details online. |

## Library Empty State

| Test | Expected Output |
| --- | --- |
| Open Library with no books. | Empty state explains import and public-domain options. |
| Tap `Import EPUB`. | System file picker opens directly. |
| Cancel the file picker. | Returns to empty Library without errors. |
| Tap `Browse Free Books`. | Public-domain browser opens. |
| Read the privacy line under empty-state buttons. | Text says EPUBs stay on device and online lookup is optional. |

## Book Import

| Test | Expected Output |
| --- | --- |
| Import a valid EPUB. | Book appears in Library with title and author metadata when available. |
| Import a duplicate EPUB. | App handles duplicate cleanly without corrupting the Library. |
| Import a corrupted EPUB or non-EPUB file. | App shows an error and does not add a broken book. |
| Import a large EPUB. | Loading completes without crash; book can be opened. |
| Restart app after importing books. | Imported books remain in Library. |

## Public-Domain Books

| Test | Expected Output |
| --- | --- |
| Open `Browse Free Books`. | Public-domain catalog loads when online. |
| Search for a title or author. | Results update and remain scrollable. |
| Open a public-domain book detail page. | Detail page displays book information and download option. |
| Download a public-domain EPUB. | Book imports into Library and can be opened. |
| Repeat public-domain browsing while offline. | App shows a graceful error or empty state, not a crash. |

## Library Management

| Test | Expected Output |
| --- | --- |
| Search Library by book title. | Matching books remain visible; non-matches disappear. |
| Search Library by author. | Matching author results appear. |
| Tap the clear search icon. | Search field clears and all books return. |
| Change sort mode to title, author, progress, and recent. | Book order updates according to selected mode. |
| Open the add-book floating action button. | Import and Browse Free Books options are available. |
| Toggle `Enhance book details online`. | Preference changes and remains set after reopening the drawer. |

## Reader Basics

| Test | Expected Output |
| --- | --- |
| Open a book from Library. | Loading screen transitions into Reader. |
| First reader open after fresh app data. | Gesture hint appears once near the bottom and disappears after a few seconds. |
| Dismiss the gesture hint manually. | Hint closes and does not reappear on next reader open. |
| Swipe up in vertical paging mode. | Reader advances to the next page. |
| Swipe down in vertical paging mode. | Reader returns to the previous page. |
| Tap once in the middle of the reader. | Reader controls appear or hide. |
| Tap back in reader controls. | Returns to Library. |
| Close and reopen a partially read book. | Reader resumes near the last position. |

## Reader Controls

| Test | Expected Output |
| --- | --- |
| Open chapter list from bottom controls. | Chapter panel opens with available chapters. |
| Tap a chapter. | Reader jumps to that chapter. |
| Drag the progress scrubber. | Page preview/progress changes and reader lands on selected page. |
| Use page jump dialog. | Reader jumps to the entered valid page. |
| Enter an invalid page number. | App prevents invalid navigation or stays on current page. |
| Open reader search. | Search screen opens for the current book. |
| Search for text that exists. | Matching results appear and can be opened. |
| Search for text that does not exist. | Empty search state appears without crash. |

## Bookmarks, Highlights, Notes, And Dictionary

| Test | Expected Output |
| --- | --- |
| Double tap or use bookmark action on a page. | Bookmark is created and visible in annotations/bookmark UI. |
| Remove a bookmark. | Bookmark disappears and stays removed after reopening book. |
| Select text and create a highlight. | Highlight appears in selected color. |
| Change highlight color. | Existing highlight updates to the new color. |
| Add a note to selected text. | Note is saved and visible from annotations. |
| Edit a note. | Updated note persists after closing and reopening reader. |
| Delete a highlight or note. | Item disappears and does not return after reopening. |
| Select a word and run dictionary lookup online. | Definition appears when found. |
| Save a dictionary word. | Word appears in saved words/vocabulary area. |
| Run dictionary lookup offline. | App handles the failure gracefully. |

## Quote Cards And Sharing

| Test | Expected Output |
| --- | --- |
| Select text and create a quote card. | Quote card preview opens with selected quote. |
| Change quote card style/theme if available. | Preview updates without layout overflow. |
| Save quote card to gallery. | Image saves successfully, including on Android versions that require storage permission. |
| Share quote card. | Android share sheet opens with the generated image. |
| Deny storage permission when saving. | App explains or gracefully handles denied permission. |

## Themes And Reading Settings

| Test | Expected Output |
| --- | --- |
| Open Library `Themes`. | Theme selector opens and applies selected app theme. |
| Open Reader settings. | Settings sheet opens. |
| Change font family and font size. | Reader text updates and remains readable. |
| Change content density. | Page layout updates without clipped text. |
| Toggle Card Mode. | Reader changes between card/deck and flat reading presentation. |
| Change paging axis to horizontal. | Swipes left/right navigate pages. |
| Toggle volume button paging on a physical Android device. | Volume keys page when enabled and adjust volume when disabled. |
| Enable blue light or dim text settings. | Reader colors change without making text unreadable. |

## Speed Read And Insights

| Test | Expected Output |
| --- | --- |
| Start Speed Read. | Speed Read overlay starts on current page text. |
| Pause and resume Speed Read. | Reading pauses and resumes without losing position. |
| Change WPM. | Speed Read pace changes. |
| Switch Speed Read display mode. | Overlay changes mode without crash. |
| Finish several pages with insights enabled. | Reading stats update after returning to Library/Stats. |
| Open Reading Stats. | Stats screen opens and shows current reading activity. |

## Persistence And Recovery

| Test | Expected Output |
| --- | --- |
| Force close app while reading, then reopen. | App launches and can resume the book. |
| Rotate device if orientation is supported. | Layout remains usable and text does not overlap controls. |
| Put app in background and return. | Reader state and position remain stable. |
| Restart device or emulator after importing books. | Library data and reading progress persist. |
| Delete an imported book file from app storage if possible. | App does not crash and cleans up or hides unavailable book. |

## Regression Smoke Test

| Test | Expected Output |
| --- | --- |
| Fresh install, complete first-run education, import EPUB, read 3 pages, bookmark, highlight, add note, return to Library. | Entire flow completes without crash and all saved items persist. |
| Relaunch app and tap Continue Reading if shown. | Same book opens near last position. |
| Open hamburger menu after all flows. | No placeholder entries are present; all visible entries perform an action. |
