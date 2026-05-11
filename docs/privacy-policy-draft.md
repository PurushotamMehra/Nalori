# Privacy Policy for Nalori

Effective date: May 6, 2026

Contact: naloriapp@gmail.com

## Overview

Nalori is an EPUB reader designed to work mostly offline. Nalori does not have sign-up, login, user accounts, user profiles, cloud sync, subscriptions, payments, ads, analytics, crash reporting SDKs, or a Nalori developer backend/account system in the current build.

Nalori stores your reading data locally on your device. Some optional online features may send limited lookup or download requests to third-party services when you choose to use those features.

## Data Stored Locally On Your Device

Nalori may store the following data locally on your device:

- EPUB books you import.
- Public-domain EPUB books you download, if the public-domain download feature is available in your build.
- Highlights.
- Notes.
- Bookmarks.
- Saved words and saved word meanings.
- Reading progress.
- Reading statistics.
- Reader settings and app preferences.
- Book metadata and cover images used by the app.
- Generated quote or book card images when you choose to create, save, or share them.

This data is stored in app storage on your device, including local files and local preferences. Nalori does not upload your imported books, highlights, notes, bookmarks, saved words, reading progress, reading statistics, or settings to a Nalori server.

## Optional Online Features

Nalori can use the internet for optional features. When you use these features, limited request data may be sent to third-party services so the feature can work.

| Feature | Data that may be sent | Purpose |
| --- | --- | --- |
| Book details, metadata, and cover lookup | Book title, author, metadata query, cover identifier, or cover image URL request | Find cleaner book details and cover images |
| Dictionary or word meaning lookup | The word you choose to look up | Retrieve a dictionary definition |
| Public-domain book browsing, if present | Search text, topic, language, page number, selected book identifier, or catalog filters | Browse public-domain books |
| Public-domain book download, if present | Request for the selected EPUB download URL | Download the selected public-domain book |

These optional online requests are not sent to a Nalori developer backend. They are sent directly to the relevant third-party service or download host.

## Third-Party Services Used

Based on the current app code, Nalori may use these third-party services for optional online features:

- Gutendex (`gutendex.com`) for public-domain book catalog browsing and book details.
- Open Library (`openlibrary.org`) for book metadata lookup.
- Open Library Covers (`covers.openlibrary.org`) for cover image lookup.
- Free Dictionary API (`api.dictionaryapi.dev`) for word definition lookup.
- Public-domain EPUB download hosts returned by catalog results, such as Project Gutenberg download URLs when provided by the catalog.

These third-party services may process requests according to their own terms and privacy policies.

## Sharing And Exporting

Nalori lets you create, save, or share quote and book card images. Content or images are shared only when you choose an Android share/save flow or another export action.

When you use Android sharing, the content you choose to share is passed to the app or service you select from the Android share sheet. Nalori does not control how the receiving app or service handles that shared content.

## Permissions

Nalori currently requests:

- `INTERNET`, used for optional online lookup and public-domain browsing/download features.
- `WRITE_EXTERNAL_STORAGE` with `maxSdkVersion="28"`, used only on older Android versions for saving exported images where applicable.

## Accounts And Data Deletion URL

Nalori does not currently offer account creation, login, user profiles, or cloud sync.

Because there is no Nalori account system, an account deletion URL is not currently required. If Nalori adds account creation in a future version, this policy and the app will need to provide the required account deletion process.

## Ads, Analytics, Crash Reporting, And Payments

The current build does not include:

- Ads or ads SDKs.
- Analytics SDKs.
- Crash reporting SDKs.
- Payments, subscriptions, billing SDKs, or in-app purchases.
- Authentication SDKs or a Nalori backend account system.

## How To Delete Local Data

You can delete local Nalori data in these ways:

- Delete in-app items where the app provides deletion controls, such as local books, saved words, highlights, notes, or bookmarks if supported by the current screen.
- Clear Nalori app storage from Android system settings.
- Uninstall Nalori from your device.

Data sent to third-party services through optional online lookup or download requests is controlled by those third parties.

## Data Retention

Local data remains on your device until you delete it in the app where supported, clear Nalori app storage, or uninstall Nalori.

Nalori does not maintain a developer-operated backend account database for your reading data in the current build.

## Security

Nalori stores reading data locally on your device using Android app storage and local preferences. Access to local app data is governed by Android and your device security settings.

Where the current code performs online lookups using fixed service endpoints, it uses HTTPS for Gutendex catalog requests, Open Library metadata and cover requests, and Free Dictionary API requests. Public-domain EPUB downloads use the download URL provided by the catalog result.

No method of storage or transmission can be guaranteed to be perfectly secure.

## Children And Target Audience

Nalori is not directed to children unless the app is intentionally marketed that way in the future. If Nalori is later targeted to children, this policy and the app’s Play Console declarations should be reviewed for child-directed requirements.

## Changes To This Policy

This draft may be updated before publication. After publication, the effective date should be updated when the policy changes.

## Contact

If you have questions about this privacy policy, contact:

naloriapp@gmail.com
