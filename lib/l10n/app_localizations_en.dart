// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Nalori';

  @override
  String get libraryTitle => 'Library';

  @override
  String get loadingBooks => 'Loading your books';

  @override
  String bookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String get addBook => 'Add Book';

  @override
  String get addABook => 'Add a book';

  @override
  String get addBookSheetSubtitle =>
      'Import your own EPUB or browse free classics.';

  @override
  String get importEpub => 'Import EPUB';

  @override
  String get importEpubSubtitle => 'Choose a book file from this device';

  @override
  String get recommended => 'Recommended';

  @override
  String get browseProjectGutenberg => 'Browse Project Gutenberg';

  @override
  String get browseProjectGutenbergSubtitle =>
      'Explore free public-domain EPUBs';

  @override
  String get addBookSupportNote =>
      'Supported format: EPUB. Imported books stay on this device.';

  @override
  String get readingStats => 'Reading Stats';

  @override
  String get howToUseNalori => 'How to use Nalori';

  @override
  String get themes => 'Themes';

  @override
  String get enhanceBookDetailsOnline => 'Enhance book details online';

  @override
  String get enhanceBookDetailsOnlineSubtitle =>
      'Find cleaner titles, authors, and covers';

  @override
  String get aboutAndLicenses => 'About and licenses';

  @override
  String get personalLibraryTagline => 'Your personal library';

  @override
  String get privacyPolicyPlaceholder =>
      'Privacy policy: add the production URL before Play release.';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get loading => 'Loading';

  @override
  String get error => 'Error';
}

/// The translations for English, as used in India (`en_IN`).
class AppLocalizationsEnIn extends AppLocalizationsEn {
  AppLocalizationsEnIn() : super('en_IN');

  @override
  String get appTitle => 'Nalori';

  @override
  String get libraryTitle => 'Library';

  @override
  String get loadingBooks => 'Loading your books';

  @override
  String bookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String get addBook => 'Add Book';

  @override
  String get addABook => 'Add a book';

  @override
  String get addBookSheetSubtitle =>
      'Import your own EPUB or browse free classics.';

  @override
  String get importEpub => 'Import EPUB';

  @override
  String get importEpubSubtitle => 'Choose a book file from this device';

  @override
  String get recommended => 'Recommended';

  @override
  String get browseProjectGutenberg => 'Browse Project Gutenberg';

  @override
  String get browseProjectGutenbergSubtitle =>
      'Explore free public-domain EPUBs';

  @override
  String get addBookSupportNote =>
      'Supported format: EPUB. Imported books stay on this device.';

  @override
  String get readingStats => 'Reading Stats';

  @override
  String get howToUseNalori => 'How to use Nalori';

  @override
  String get themes => 'Themes';

  @override
  String get enhanceBookDetailsOnline => 'Enhance book details online';

  @override
  String get enhanceBookDetailsOnlineSubtitle =>
      'Find cleaner titles, authors, and covers';

  @override
  String get aboutAndLicenses => 'About and licenses';

  @override
  String get personalLibraryTagline => 'Your personal library';

  @override
  String get privacyPolicyPlaceholder =>
      'Privacy policy: add the production URL before Play release.';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get loading => 'Loading';

  @override
  String get error => 'Error';
}
