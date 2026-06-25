import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book_metadata.dart';
import '../models/book_share_payload.dart';
import '../models/reading_settings.dart';
import '../l10n/app_localizations.dart';
import '../services/reading_settings_service.dart';
import '../services/book_cache_service.dart';
import '../services/book_memory_entry_service.dart';
import '../services/book_import_service.dart';
import '../services/book_preparse_service.dart';
import '../services/book_metadata_service.dart';
import '../services/library_service.dart';
import '../services/metadata_enhancement_preferences.dart';
import '../services/open_library_metadata_service.dart';
import '../services/public_domain_book_service.dart';
import '../services/reading_stats_service.dart';
import '../ui/app_visuals.dart';
import '../widgets/add_book_sheet.dart';
import '../widgets/floating_progress_hud.dart';
import 'book_loading_screen.dart';
import 'book_memory_screen.dart';
import 'contact_screen.dart';
import 'how_to_use_screen.dart';
import 'public_domain_books_screen.dart';
import 'quote_card_preview_screen.dart';
import 'stats_screen.dart';

/// Screen 1 — displays the list of available books + import button.
class BookListScreen extends StatefulWidget {
  final File? initiallyOpenFile;

  const BookListScreen({super.key, this.initiallyOpenFile});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  static final Uri _privacyPolicyUri = Uri.parse(
    'https://gist.github.com/PurushotamMehra/1043d695f471272de8cdeb431afddf5e',
  );

  final LibraryService _library = LibraryService();
  final BookImportService _importer = BookImportService();
  final BookCacheService _bookCacheService = BookCacheService();
  final BookMetadataService _metadataService = BookMetadataService();
  final ReadingSettingsService _settingsService = ReadingSettingsService();
  final ReadingStatsService _statsService = ReadingStatsService();
  final MetadataEnhancementPreferences _metadataEnhancementPreferences =
      MetadataEnhancementPreferences();
  final PublicDomainBookService _publicDomainBookService =
      PublicDomainBookService();

  bool _loading = true;
  List<File> _books = [];
  ReadingSettings _settings = const ReadingSettings();
  FloatingProgressHudData? _progressHud;
  _SortMode _sortMode = _SortMode.recentlyRead;
  _LibraryViewMode _viewMode = _LibraryViewMode.list;
  String _searchQuery = '';
  bool _isImportingBook = false;
  bool _enhanceBookDetailsOnline = false;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Future<_BookCardReadingSummary>> _bookCardSummaryFutures =
      {};
  final Map<String, bool> _coverExistsByBookId = {};

  @override
  void initState() {
    super.initState();
    _refreshLibrary();
    if (widget.initiallyOpenFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openBook(widget.initiallyOpenFile!);
      });
    }
  }

  @override
  void dispose() {
    BookPreparseService.instance.cancelQueue();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshLibrary() async {
    setState(() => _loading = true);
    _bookCardSummaryFutures.clear();
    _coverExistsByBookId.clear();

    // Load Settings
    final s = await _settingsService.loadSettings();
    final enhanceBookDetailsOnline = await _metadataEnhancementPreferences
        .loadEnhanceBookDetailsOnline();
    setState(() {
      _settings = s;
      _enhanceBookDetailsOnline = enhanceBookDetailsOnline;
    });

    await _metadataService.init();
    await _statsService.init();
    final books = await _library.getLocalBooks();
    final validBooks = <File>[];
    final coverExistsByBookId = <String, bool>{};

    // Ensure metadata exists for all books
    for (final file in books) {
      final bookId = p.basename(file.path);
      var meta = _metadataService.getMetadata(bookId);

      // Clean up previously saved fake corrupted metadata entries
      if (meta != null && meta.title.startsWith('Corrupted File:')) {
        try {
          await file.delete();
        } catch (_) {}
        await _metadataService.deleteMetadata(bookId);
        continue;
      }

      if (meta == null) {
        meta = await _metadataService.extractAndCacheMetadata(file);
        if (meta == null) {
          // It's newly found but corrupted. Delete from disk.
          try {
            await file.delete();
          } catch (_) {}
          continue;
        }
        if (_enhanceBookDetailsOnline) {
          meta =
              await _metadataService.enhanceMetadataFromOpenLibrary(bookId) ??
              meta;
        }
      }
      coverExistsByBookId[bookId] =
          meta.coverImagePath != null &&
          await File(meta.coverImagePath!).exists();
      validBooks.add(file);
    }

    // Sort based on current mode
    _sortBooks(validBooks);

    if (mounted) {
      setState(() {
        _books = validBooks;
        _coverExistsByBookId
          ..clear()
          ..addAll(coverExistsByBookId);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _publicDomainBookService.maybePrefetchDefaultList();
        if (widget.initiallyOpenFile != null) {
          BookPreparseService.instance.cancelQueue();
          return;
        }
        BookPreparseService.instance.queueBooks(validBooks);
      });
    }
  }

  void _sortBooks(List<File> books) {
    switch (_sortMode) {
      case _SortMode.recentlyRead:
        books.sort((a, b) {
          final metaA = _metadataService.getMetadata(p.basename(a.path));
          final metaB = _metadataService.getMetadata(p.basename(b.path));
          final timeA = metaA?.lastReadTime ?? 0;
          final timeB = metaB?.lastReadTime ?? 0;
          return timeB.compareTo(timeA);
        });
      case _SortMode.title:
        books.sort((a, b) {
          final metaA = _metadataService.getMetadata(p.basename(a.path));
          final metaB = _metadataService.getMetadata(p.basename(b.path));
          final titleA = metaA?.title ?? p.basename(a.path);
          final titleB = metaB?.title ?? p.basename(b.path);
          return titleA.toLowerCase().compareTo(titleB.toLowerCase());
        });
      case _SortMode.author:
        books.sort((a, b) {
          final metaA = _metadataService.getMetadata(p.basename(a.path));
          final metaB = _metadataService.getMetadata(p.basename(b.path));
          final authorA = metaA?.author ?? '';
          final authorB = metaB?.author ?? '';
          return authorA.toLowerCase().compareTo(authorB.toLowerCase());
        });
      case _SortMode.progress:
        books.sort((a, b) {
          final metaA = _metadataService.getMetadata(p.basename(a.path));
          final metaB = _metadataService.getMetadata(p.basename(b.path));
          final progA = (metaA != null && metaA.totalChunks > 1)
              ? metaA.lastReadIndex / (metaA.totalChunks - 1)
              : (metaA?.totalChunks == 1 ? 1.0 : 0.0);
          final progB = (metaB != null && metaB.totalChunks > 1)
              ? metaB.lastReadIndex / (metaB.totalChunks - 1)
              : (metaB?.totalChunks == 1 ? 1.0 : 0.0);
          return progB.compareTo(progA); // highest progress first
        });
    }
  }

  Future<void> _importBook() async {
    if (mounted) {
      setState(() => _isImportingBook = true);
    }
    final imported = await _importer.importBook();
    if (imported == null) {
      if (mounted) setState(() => _isImportingBook = false);
      return;
    }

    try {
      final bookId = p.basename(imported.path);

      // Extract immediately so we can show an error if it's corrupted
      var meta = _metadataService.getMetadata(bookId);
      if (meta == null) {
        meta = await _metadataService.extractAndCacheMetadata(imported);
        if (meta == null) {
          // Extraction failed (corrupted file)
          try {
            await imported.delete();
          } catch (_) {}

          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: _settings.backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _settings.mutedColor.withValues(alpha: 0.1),
                ),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Corrupted File',
                      style: _settings.uiText(
                        color: _settings.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                'The EPUB file you selected is malformed or missing key metadata, and cannot be added to your library.',
                style: _settings.uiText(
                  color: _settings.mutedColor,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: _settings.accentColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    'OK',
                    style: _settings.uiText(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          );
          return; // Stop here, don't refresh library to show a ghost
        }
      } else if (meta.managedFilePath != imported.path) {
        await _metadataService.updateManagedFilePath(
          bookId: bookId,
          managedFilePath: imported.path,
        );
      }
      if (_enhanceBookDetailsOnline) {
        await _metadataService.enhanceMetadataFromOpenLibrary(bookId);
      }

      await _refreshLibrary();
    } finally {
      if (mounted) setState(() => _isImportingBook = false);
    }
  }

  Future<void> _openBook(File file) async {
    final bookId = p.basename(file.path);
    BookPreparseService.instance.cancelQueue();
    BookPreparseService.instance.beginForegroundWork('readerOpen:$bookId');
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              BookLoadingScreen(bookFile: file, settings: _settings),
        ),
      );
    } finally {
      BookPreparseService.instance.endForegroundWork('readerOpen:$bookId');
    }

    // Re-sort and refresh UI when returning from reading
    _refreshLibrary();
  }

  Future<void> _openBookMemory(File file) async {
    final bookId = p.basename(file.path);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookMemoryScreen(
          bookFile: file,
          bookId: bookId,
          settings: _settings,
        ),
      ),
    );
    _refreshLibrary();
  }

  Future<void> _browsePublicDomainBooks() async {
    final bookPath = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => PublicDomainBooksScreen(settings: _settings),
      ),
    );

    if (bookPath != null && mounted) {
      await _openBook(File(bookPath));
      return;
    }

    if (mounted) {
      _refreshLibrary();
    }
  }

  void _showAddBookOptions() {
    _publicDomainBookService.maybePrefetchDefaultList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return AddBookSheet(
          settings: _settings,
          onImportEpub: () {
            if (mounted) _importBook();
          },
          onBrowseProjectGutenberg: () {
            if (mounted) _browsePublicDomainBooks();
          },
        );
      },
    );
  }

  Future<void> _handleEnhanceBookDetailsToggle(bool enabled) async {
    if (enabled) {
      final confirmed = await _confirmOnlineBookDetailsLookup();
      if (!confirmed) return;
    }

    await _metadataEnhancementPreferences.setEnhanceBookDetailsOnline(enabled);
    if (!mounted) return;
    setState(() => _enhanceBookDetailsOnline = enabled);
  }

  Future<void> _handleReadingInsightsToggle(bool enabled) async {
    final updated = _settings.copyWith(readingInsightsEnabled: enabled);
    await _settingsService.saveSettings(updated);
    if (!mounted) return;
    setState(() => _settings = updated);
  }

  Future<bool> _ensureOnlineBookDetailsOptIn() async {
    if (_enhanceBookDetailsOnline) return true;

    final confirmed = await _confirmOnlineBookDetailsLookup();
    if (!confirmed) return false;

    await _metadataEnhancementPreferences.setEnhanceBookDetailsOnline(true);
    if (mounted) {
      setState(() => _enhanceBookDetailsOnline = true);
    }
    return true;
  }

  Future<bool> _confirmOnlineBookDetailsLookup() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: _settings.menuColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: _settings.mutedColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _settings.accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.cloud_sync_rounded,
                          color: _settings.accentColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Enhance book details online?',
                          style: _settings.uiText(
                            color: _settings.textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Book titles and authors may be sent to Open Library to find cleaner metadata and covers. Your files, notes, highlights, and reading data stay on this device.',
                    style: _settings.uiText(
                      color: _settings.mutedColor,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _settings.textColor,
                            side: BorderSide(
                              color: _settings.mutedColor.withValues(
                                alpha: 0.25,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Not Now',
                            style: _settings.uiText(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _settings.accentColor,
                            foregroundColor: _settings.backgroundColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Turn On',
                            style: _settings.uiText(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  Future<void> _refreshBookDetails(File file) async {
    final allowed = await _ensureOnlineBookDetailsOptIn();
    if (!allowed || !mounted) return;

    final bookId = p.basename(file.path);
    setState(() {
      _progressHud = const FloatingProgressHudData(
        title: 'Fetching book details',
        message: 'Checking Open Library for a close metadata match…',
      );
    });

    final previous = _metadataService.getMetadata(bookId);
    BookMetadata? updated;
    try {
      updated = await _metadataService.enhanceMetadataFromOpenLibrary(bookId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not fetch book details: $error'),
          backgroundColor: _settings.menuColor,
        ),
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _progressHud = null);
      }
    }
    if (!mounted) return;

    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No confident Open Library match found.'),
          backgroundColor: _settings.menuColor,
        ),
      );
      return;
    }

    await _refreshLibrary();
    if (!mounted) return;
    final titleChanged = previous == null || previous.title != updated.title;
    final authorChanged = previous == null || previous.author != updated.author;
    final onlyCoverChanged = !titleChanged && !authorChanged;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          onlyCoverChanged
              ? 'Updated the cover without replacing the book metadata.'
              : 'Updated details for "${updated.title}"',
        ),
        backgroundColor: _settings.menuColor,
      ),
    );
  }

  Future<void> _changeBookCover(File file) async {
    final allowed = await _ensureOnlineBookDetailsOptIn();
    if (!allowed || !mounted) return;

    final bookId = p.basename(file.path);
    final metadata = _metadataService.getMetadata(bookId);
    if (metadata == null) return;

    setState(() {
      _progressHud = const FloatingProgressHudData(
        title: 'Fetching cover options',
        message: 'Looking for alternative covers for this book…',
      );
    });
    List<BookCoverCandidate> candidates;
    try {
      candidates = await _metadataService.findCoverCandidates(bookId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not fetch cover options: $error'),
          backgroundColor: _settings.menuColor,
        ),
      );
      return;
    } finally {
      if (mounted) {
        setState(() => _progressHud = null);
      }
    }
    if (!mounted) return;

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No cover options found.'),
          backgroundColor: _settings.menuColor,
        ),
      );
      return;
    }

    final coverPath = await _showCoverPicker(
      title: metadata.title,
      candidates: candidates,
      onUpload: () => _uploadBookCover(file),
      onSelected: (candidate) async {
        final updated = await _metadataService.applyCoverCandidate(
          bookId,
          candidate,
        );
        await _refreshLibrary();
        return updated?.coverImagePath;
      },
    );
    if (!mounted || coverPath == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Cover updated.'),
        backgroundColor: _settings.menuColor,
      ),
    );
  }

  Future<void> _revertToBookMetadata(File file) async {
    final bookId = p.basename(file.path);
    final updated = await _metadataService.revertToBookMetadata(bookId);
    if (updated == null || !mounted) return;

    await _refreshLibrary();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Restored the title and author from the EPUB file.',
        ),
        backgroundColor: _settings.menuColor,
      ),
    );
  }

  Future<void> _uploadBookCover(File file) async {
    final bookId = p.basename(file.path);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Choose a cover image',
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    final updated = await _metadataService.saveLocalCover(
      bookId: bookId,
      sourceFile: File(sourcePath),
    );
    if (!mounted) return;

    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not use that image as a cover.'),
          backgroundColor: _settings.menuColor,
        ),
      );
      return;
    }

    await _refreshLibrary();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Cover uploaded.'),
        backgroundColor: _settings.menuColor,
      ),
    );
  }

  Future<void> _shareBookCard(File file) async {
    final bookId = p.basename(file.path);
    final metadata = _metadataService.getMetadata(bookId);
    final title = metadata?.title.trim().isNotEmpty == true
        ? metadata!.title
        : p.basenameWithoutExtension(file.path);
    final payload = BookSharePayload.fromBook(
      bookTitle: title,
      author: metadata?.author ?? '',
      bookId: bookId,
      coverImagePath: metadata?.coverImagePath,
      fontFamily: _settings.fontFamily,
    );

    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => QuoteCardPreviewScreen.book(
          payload: payload,
          onCoverChanged: () => _refreshLibrary(),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<void> _shareReadingRecapCard(File file) async {
    final bookId = p.basename(file.path);
    final metadata = _metadataService.getMetadata(bookId);
    final insights = _statsService.getBookInsights(bookId);
    if (insights.activeSeconds <= 0 && insights.calibrationSeconds <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Read a little more before sharing a recap.'),
          backgroundColor: _settings.menuColor,
        ),
      );
      return;
    }

    final title = metadata?.title.trim().isNotEmpty == true
        ? metadata!.title
        : p.basenameWithoutExtension(file.path);
    final fastest = insights.fastestChapter;
    final longest = insights.longestChapter;
    final payload = ReadingRecapPayload.fromBook(
      bookTitle: title,
      author: metadata?.author ?? '',
      bookId: bookId,
      coverImagePath: metadata?.coverImagePath,
      fontFamily: _settings.fontFamily,
      totalReadingTime: ReadingStatsService.formatDuration(
        Duration(
          seconds: insights.completedReadingSeconds ?? insights.activeSeconds,
        ),
      ),
      averageWpm: '${_statsService.estimatedWpmForBook(bookId)} WPM',
      fastestChapter: fastest == null || fastest.wpm == null
          ? null
          : '${fastest.title} · ${fastest.wpm} WPM',
      longestChapter: longest == null
          ? null
          : '${longest.title} · ${ReadingStatsService.formatDuration(Duration(seconds: longest.activeSeconds))}',
    );

    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            QuoteCardPreviewScreen.readingRecap(payload: payload),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Future<String?> _showCoverPicker({
    required String title,
    required List<BookCoverCandidate> candidates,
    required Future<String?> Function(BookCoverCandidate candidate) onSelected,
    Future<void> Function()? onUpload,
  }) async {
    return showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        var saving = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: _settings.menuColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: _settings.mutedColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        'Choose a cover',
                        style: _settings.uiText(
                          color: _settings.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: _settings.uiText(
                          color: _settings.mutedColor,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 18),
                      if (onUpload != null) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: saving
                                ? null
                                : () async {
                                    Navigator.pop(ctx);
                                    await onUpload();
                                  },
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(
                              'Upload from device',
                              style: _settings.uiText(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _settings.accentColor,
                              side: BorderSide(
                                color: _settings.accentColor.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      SizedBox(
                        height: 220,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: candidates.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final candidate = candidates[index];
                            return SizedBox(
                              width: 118,
                              child: InkWell(
                                onTap: saving
                                    ? null
                                    : () async {
                                        setModalState(() => saving = true);
                                        final path = await onSelected(
                                          candidate,
                                        );
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx, path);
                                        }
                                      },
                                borderRadius: BorderRadius.circular(8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: candidate.imageBytes != null
                                            ? Image.memory(
                                                Uint8List.fromList(
                                                  candidate.imageBytes!,
                                                ),
                                                fit: BoxFit.cover,
                                                cacheWidth: 236,
                                              )
                                            : Image.network(
                                                candidate.imageUrl,
                                                fit: BoxFit.cover,
                                                cacheWidth: 236,
                                                headers: const {
                                                  'User-Agent':
                                                      PublicDomainBookService
                                                          .userAgent,
                                                },
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                      color: _settings
                                                          .mutedColor
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      child: Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        color: _settings
                                                            .mutedColor,
                                                      ),
                                                    ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      candidate.source
                                          .replaceAll('_', ' ')
                                          .toUpperCase(),
                                      style: _settings.uiText(
                                        color: _settings.mutedColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (saving) ...[
                        const SizedBox(height: 14),
                        LinearProgressIndicator(color: _settings.accentColor),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Long-press options ─────────────────────────────────────────────

  void _showBookOptions(File file, String bookTitle) {
    final bookId = p.basename(file.path);
    final metadata = _metadataService.getMetadata(bookId);
    final title = metadata?.title ?? bookTitle;
    final author = metadata?.author ?? 'Unknown Author';
    final progress = (metadata != null && metadata.totalChunks > 1)
        ? (metadata.lastReadIndex / (metadata.totalChunks - 1)).clamp(0.0, 1.0)
        : (metadata?.totalChunks == 1 ? 1.0 : 0.0);
    final subtitle = _buildBookOptionsHeaderSubtitle(metadata, progress);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
          ),
          decoration: BoxDecoration(
            color: _settings.menuColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: _settings.mutedColor.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildBookOptionsHeader(
                          title: title,
                          author: author,
                          subtitle: subtitle,
                          metadata: metadata,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildBookOptionsCloseButton(ctx),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildBookOptionSection(
                    title: 'Share',
                    actions: [
                      _BookOptionAction(
                        icon: Icons.ios_share_rounded,
                        title: 'Share Book Card',
                        onTap: () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _shareBookCard(file);
                          });
                        },
                      ),
                      if (_settings.readingInsightsEnabled)
                        _BookOptionAction(
                          icon: Icons.military_tech_outlined,
                          title: 'Share Reading Recap',
                          onTap: () {
                            Navigator.pop(ctx);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _shareReadingRecapCard(file);
                            });
                          },
                        ),
                    ],
                  ),
                  _buildBookOptionSection(
                    title: 'Book Info',
                    actions: [
                      _BookOptionAction(
                        icon: Icons.cloud_sync_outlined,
                        title: 'Refresh Book Details',
                        subtitle: 'Verify online details first',
                        onTap: () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _refreshBookDetails(file);
                          });
                        },
                      ),
                      if (metadata?.canRevertToBookMetadata == true)
                        _BookOptionAction(
                          icon: Icons.restore_rounded,
                          title: 'Use Book Metadata',
                          subtitle: 'Restore title and author from EPUB',
                          onTap: () {
                            Navigator.pop(ctx);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _revertToBookMetadata(file);
                            });
                          },
                        ),
                    ],
                  ),
                  _buildBookOptionSection(
                    title: 'Cover',
                    actions: [
                      _BookOptionAction(
                        icon: Icons.photo_library_outlined,
                        title: 'Change Cover',
                        onTap: () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _changeBookCover(file);
                          });
                        },
                      ),
                      _BookOptionAction(
                        icon: Icons.add_photo_alternate_outlined,
                        title: 'Upload Cover',
                        onTap: () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _uploadBookCover(file);
                          });
                        },
                      ),
                    ],
                  ),
                  _buildBookOptionSection(
                    title: 'Reading',
                    actions: [
                      _BookOptionAction(
                        icon: Icons.auto_stories_outlined,
                        title: 'Book Memory',
                        subtitle: 'Bookmarks, notes, words, and characters',
                        onTap: () {
                          Navigator.pop(ctx);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _openBookMemory(file);
                          });
                        },
                      ),
                      _BookOptionAction(
                        icon: Icons.restart_alt_rounded,
                        title: 'Start from Beginning',
                        subtitle: 'Reset progress to the first chapter',
                        onTap: () {
                          Navigator.pop(ctx);
                          _startFromBeginning(bookId);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildBookOptionSection(
                    title: 'Danger Zone',
                    isDangerZone: true,
                    actions: [
                      _BookOptionAction(
                        icon: Icons.delete_outline_rounded,
                        title: 'Delete Book',
                        subtitle: 'Remove book and all its data',
                        isDangerous: true,
                        onTap: () {
                          Navigator.pop(ctx);
                          _confirmDelete(file, bookTitle);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookOptionsHeader({
    required String title,
    required String author,
    required String subtitle,
    required BookMetadata? metadata,
  }) {
    final coverPath = metadata?.coverImagePath;
    final hasCover =
        coverPath != null &&
        (_coverExistsByBookId[metadata?.id ?? ''] ?? false);

    return Row(
      children: [
        ClipRRect(
          borderRadius: AppUi.cardRadius(8),
          child: hasCover
              ? Image.file(
                  File(coverPath),
                  width: 44,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 88,
                )
              : _buildGeneratedCover(title, author, width: 44, height: 64),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: _settings.uiText(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _settings.textColor,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                author,
                style: _settings.uiText(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _settings.mutedColor,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: _settings.uiText(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _settings.accentColor.withValues(alpha: 0.88),
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _buildBookOptionsHeaderSubtitle(
    BookMetadata? metadata,
    double progress,
  ) {
    if (metadata == null) return 'Ready to read';

    final progressPercent = (progress * 100).toInt();
    final chapterNumber = metadata.readingSummary?.chapterNumberFor(
      metadata.lastReadIndex,
    );
    final parts = <String>[];

    if (metadata.lastReadIndex > 0) {
      parts.add('$progressPercent% complete');
      if (chapterNumber != null) {
        parts.add('Chapter $chapterNumber');
      }
    } else {
      parts.add('Not started');
    }

    return parts.join(' • ');
  }

  Widget _buildBookOptionsCloseButton(BuildContext ctx) {
    return Material(
      color: _settings.mutedColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => Navigator.pop(ctx),
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.close_rounded,
            size: 19,
            color: _settings.mutedColor,
          ),
        ),
      ),
    );
  }

  Widget _buildBookOptionSection({
    required String title,
    required List<_BookOptionAction> actions,
    bool isDangerZone = false,
  }) {
    if (actions.isEmpty) return const SizedBox.shrink();

    final sectionColor = isDangerZone ? Colors.redAccent : _settings.mutedColor;

    return Padding(
      padding: EdgeInsets.only(top: isDangerZone ? 10 : 0, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
            child: Text(
              title,
              style: _settings.uiText(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: sectionColor.withValues(alpha: isDangerZone ? 0.9 : 0.7),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: (isDangerZone ? Colors.redAccent : _settings.textColor)
                  .withValues(alpha: isDangerZone ? 0.055 : 0.035),
              borderRadius: AppUi.cardRadius(14),
              border: Border.all(
                color: (isDangerZone ? Colors.redAccent : _settings.mutedColor)
                    .withValues(alpha: isDangerZone ? 0.18 : 0.12),
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  _buildBookOptionRow(actions[i]),
                  if (i != actions.length - 1)
                    Divider(
                      height: 1,
                      indent: 48,
                      color: _settings.mutedColor.withValues(alpha: 0.1),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookOptionRow(_BookOptionAction action) {
    final color = action.isDangerous ? Colors.redAccent : _settings.textColor;
    final iconColor = action.isDangerous
        ? Colors.redAccent
        : _settings.mutedColor.withValues(alpha: 0.9);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: AppUi.cardRadius(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconColor.withValues(
                    alpha: action.isDangerous ? 0.14 : 0.075,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(action.icon, color: iconColor, size: 17),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: _settings.uiText(
                        color: color,
                        fontSize: 14,
                        fontWeight: action.isDangerous
                            ? FontWeight.w700
                            : FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (action.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        action.subtitle!,
                        style: _settings.uiText(
                          color: action.isDangerous
                              ? Colors.redAccent.withValues(alpha: 0.72)
                              : _settings.mutedColor,
                          fontSize: 11,
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startFromBeginning(String bookId) async {
    // Reset reading position
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_read_$bookId');

    // Reset progress in metadata
    final meta = _metadataService.getMetadata(bookId);
    if (meta != null) {
      await _metadataService.updateMetadata(meta.copyWith(lastReadIndex: 0));
    }

    // Clear bookmarks
    await prefs.remove('bookmarks_$bookId');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Progress reset for "${meta?.title ?? bookId}"'),
          backgroundColor: _settings.menuColor,
        ),
      );
    }

    _refreshLibrary();
  }

  void _confirmDelete(File file, String bookTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _settings.menuColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Book?',
          style: _settings.uiText(
            color: _settings.textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This will permanently delete "$bookTitle" and all its reading data.',
          style: _settings.uiText(color: _settings.mutedColor, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: _settings.uiText(color: _settings.textColor),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteBook(file);
            },
            child: Text(
              'Delete',
              style: _settings.uiText(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBook(File file) async {
    final bookId = p.basename(file.path);

    try {
      // 1. Delete the EPUB file
      if (await file.exists()) {
        await file.delete();
      }

      // 2. Delete metadata + cover image
      await _metadataService.deleteMetadata(bookId);

      // 3. Clear reading position, bookmarks, and book memory entries.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_read_$bookId');
      await prefs.remove('bookmarks_$bookId');
      await BookMemoryEntryService(bookId: bookId).clearForBook();

      // 4. Clear disk cache
      final cacheService = BookCacheService();
      await cacheService.deleteCachedBook(bookId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Book deleted'),
            backgroundColor: _settings.menuColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }

    _refreshLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final baseTheme = _settings.isDark ? ThemeData.dark() : ThemeData.light();
    final titleColor = _settings.textColor;
    return Theme(
      data: baseTheme.copyWith(
        scaffoldBackgroundColor: _settings.backgroundColor,
        colorScheme: baseTheme.colorScheme.copyWith(
          surface: _settings.backgroundColor,
          onSurface: _settings.textColor,
          surfaceContainerHighest: _settings.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
        chipTheme: baseTheme.chipTheme.copyWith(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          secondarySelectedColor: _settings.accentColor,
        ),
      ),
      child: Scaffold(
        backgroundColor: _settings.backgroundColor,
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.libraryTitle,
                style: _settings.uiText(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  letterSpacing: -0.4,
                  color: titleColor,
                ),
              ),
              Text(
                _loading ? l10n.loadingBooks : l10n.bookCount(_books.length),
                style: _settings.uiText(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: _settings.mutedColor,
                ),
              ),
            ],
          ),
          centerTitle: false,
          backgroundColor: _settings.backgroundColor,
          foregroundColor: _settings.textColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: _settings.textColor),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: AppUi.neutralPill(_settings),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 16,
                      color: _settings.accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_statsService.currentStreak}',
                      style: _settings.uiText(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _settings.textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        drawer: _buildDrawer(),
        body: Stack(
          children: [
            _buildBody(),
            if (_progressHud != null)
              FloatingProgressHud(
                data: _progressHud!,
                settings: _settings,
                backgroundColor: _settings.backgroundColor,
                surfaceColor: _settings.menuColor,
                textColor: _settings.textColor,
                mutedColor: _settings.mutedColor,
                accentColor: _settings.accentColor,
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddBookOptions,
          backgroundColor: _settings.accentColor,
          foregroundColor: Colors.white,
          elevation: 2,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text(
            l10n.addBook,
            style: _settings.uiText(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final l10n = AppLocalizations.of(context);
    return Drawer(
      backgroundColor: _settings.menuColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              24,
              MediaQuery.paddingOf(context).top + 28,
              24,
              22,
            ),
            decoration: BoxDecoration(
              color: _settings.backgroundColor,
              border: Border(
                bottom: BorderSide(
                  color: _settings.mutedColor.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _settings.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _settings.accentColor.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Center(
                        child: BrandMark(
                          size: 30,
                          color: _settings.accentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppBrand.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _settings.getAppTextStyle(
                              TextStyle(
                                color: _settings.textColor,
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l10n.personalLibraryTagline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _settings.getAppTextStyle(
                              TextStyle(
                                color: _settings.mutedColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              children: [
                _buildDrawerSectionLabel('Library'),
                _buildDrawerGroup(
                  children: [
                    _buildDrawerItem(
                      icon: Icons.bar_chart_rounded,
                      label: l10n.readingStats,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StatsScreen(settings: _settings),
                          ),
                        );
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.palette_outlined,
                      label: 'Themes / Appearance',
                      onTap: () {
                        Navigator.pop(context);
                        _showThemesBottomModal();
                      },
                    ),
                    _buildDrawerSwitchItem(
                      icon: Icons.cloud_sync_outlined,
                      label: l10n.enhanceBookDetailsOnline,
                      subtitle: l10n.enhanceBookDetailsOnlineSubtitle,
                      value: _enhanceBookDetailsOnline,
                      onChanged: _handleEnhanceBookDetailsToggle,
                    ),
                    _buildDrawerSwitchItem(
                      icon: Icons.insights_outlined,
                      label: 'Reading time estimates',
                      subtitle: 'Show time left and reading insights',
                      value: _settings.readingInsightsEnabled,
                      onChanged: _handleReadingInsightsToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildDrawerSectionLabel('Support'),
                _buildDrawerGroup(
                  children: [
                    _buildDrawerItem(
                      icon: Icons.help_outline_rounded,
                      label: l10n.howToUseNalori,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HowToUseScreen(settings: _settings),
                          ),
                        );
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.support_agent_rounded,
                      label: 'Contact',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ContactScreen(settings: _settings),
                          ),
                        );
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.info_outline_rounded,
                      label: l10n.aboutAndLicenses,
                      onTap: () {
                        Navigator.pop(context);
                        _showAboutAndLicenses();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              MediaQuery.paddingOf(context).bottom + 18,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'v1.0.0',
                style: _settings.getAppTextStyle(
                  TextStyle(
                    fontSize: 12,
                    color: _settings.mutedColor.withValues(alpha: 0.58),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutAndLicenses() {
    showAboutDialog(
      context: context,
      applicationName: AppBrand.name,
      applicationVersion: '1.0.0',
      applicationIcon: const BrandMark(size: 40),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Privacy policy'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final launched = await launchUrl(
                    _privacyPolicyUri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (launched || !mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open the privacy policy.'),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open privacy policy'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDrawerSwitchItem({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Semantics(
      button: true,
      toggled: value,
      label: label,
      hint: subtitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _buildDrawerIcon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _settings.getAppTextStyle(
                            TextStyle(
                              color: _settings.textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _settings.getAppTextStyle(
                            TextStyle(
                              color: _settings.mutedColor,
                              fontSize: 11,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ExcludeSemantics(
                  child: Switch(
                    value: value,
                    onChanged: onChanged,
                    activeThumbColor: _settings.accentColor,
                    activeTrackColor: _settings.accentColor.withValues(
                      alpha: 0.32,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerGroup({required List<Widget> children}) {
    return Container(
      decoration: AppUi.surfaceCard(_settings),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(
                height: 1,
                indent: 56,
                color: _settings.mutedColor.withValues(alpha: 0.12),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrawerSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        label.toUpperCase(),
        style: _settings.getAppTextStyle(
          TextStyle(
            color: _settings.mutedColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerIcon(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _settings.accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: _settings.accentColor, size: 19),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                _buildDrawerIcon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _settings.getAppTextStyle(
                        TextStyle(
                          color: _settings.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showThemesBottomModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
              ),
              decoration: BoxDecoration(
                color: _settings.menuColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: _settings.mutedColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        'APP THEME',
                        style: _settings.getAppTextStyle(
                          TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: _settings.mutedColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: kAppThemeChoices.map((theme) {
                            final isSelected = _settings.appTheme == theme;
                            final themeName = theme == AppTheme.system
                                ? 'SYSTEM'
                                : theme.name.toUpperCase().replaceAll(
                                    'SOFTLIGHT',
                                    'SOFT LIGHT',
                                  );

                            final dummySettings = ReadingSettings(
                              appTheme: theme,
                            );
                            final chipBgColor = dummySettings.backgroundColor;
                            final chipTextColor = dummySettings.textColor;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  themeName,
                                  style: _settings.uiText(
                                    color: chipTextColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: chipBgColor,
                                backgroundColor: chipBgColor,
                                showCheckmark: false,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: isSelected
                                        ? _settings.accentColor
                                        : Colors.grey.withValues(alpha: 0.2),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    final updated = _settings.copyWith(
                                      appTheme: theme,
                                    );
                                    setState(() => _settings = updated);
                                    _settingsService.saveSettings(updated);
                                    setModalState(() {});
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'APP FONT',
                        style: _settings.getAppTextStyle(
                          TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: _settings.mutedColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Changes the interface only. Book text keeps its separate reader font.',
                        style: _settings.getAppTextStyle(
                          TextStyle(
                            color: _settings.mutedColor,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final useTwoColumns = constraints.maxWidth >= 360;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: kAppFontChoices.map((font) {
                              final width = useTwoColumns
                                  ? (constraints.maxWidth - 8) / 2
                                  : constraints.maxWidth;
                              return SizedBox(
                                width: width,
                                child: _buildAppFontOption(
                                  font: font,
                                  selected: _settings.appFontFamily == font,
                                  onTap: () {
                                    final updated = _settings.copyWith(
                                      appFontFamily: font,
                                    );
                                    setState(() => _settings = updated);
                                    unawaited(
                                      _settingsService.saveSettings(updated),
                                    );
                                    setModalState(() {});
                                  },
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAppFontOption({
    required AppFontFamily font,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final previewSettings = _settings.copyWith(appFontFamily: font);
    final borderColor = selected
        ? _settings.accentColor
        : _settings.mutedColor.withValues(alpha: 0.16);

    return Semantics(
      button: true,
      selected: selected,
      label: 'App font ${font.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: selected
                  ? _settings.accentColor.withValues(alpha: 0.10)
                  : _settings.backgroundColor.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        font.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: previewSettings.getAppTextStyle(
                          TextStyle(
                            color: _settings.textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Nalori · Read today',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: previewSettings.getAppTextStyle(
                          TextStyle(
                            color: _settings.mutedColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected
                      ? _settings.accentColor
                      : _settings.mutedColor,
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _buildLoadingState();
    }

    if (_books.isEmpty && !_isImportingBook) {
      return _buildEmptyState();
    }

    final displayedBooks = _filteredBooks();
    if (displayedBooks.isEmpty && !_isImportingBook) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 104),
        children: [
          _buildLibraryControls(),
          const SizedBox(height: 14),
          _buildSearchEmptyState(),
        ],
      );
    }

    final heroBook = _selectHeroBook(displayedBooks);
    final remainingBooks = displayedBooks
        .where((file) => heroBook == null || file.path != heroBook.path)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 104),
      children: [
        _buildLibraryControls(),
        if (heroBook != null) ...[
          const SizedBox(height: 16),
          _buildContinueReadingCard(heroBook),
        ],
        const SizedBox(height: 18),
        _buildLibrarySectionHeader(remainingCount: remainingBooks.length),
        const SizedBox(height: 10),
        if (_viewMode == _LibraryViewMode.grid)
          _buildBookGrid(remainingBooks)
        else
          _buildBookList(remainingBooks),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: AppUi.surfaceCard(_settings, prominent: true),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  color: _settings.accentColor,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Loading your library',
                style: _settings.uiText(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _settings.textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Checking your saved EPUBs and refreshing book details.',
                textAlign: TextAlign.center,
                style: _settings.uiText(
                  fontSize: 14,
                  height: 1.45,
                  color: _settings.mutedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: AppUi.surfaceCard(_settings, prominent: true),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: AppUi.accentPill(
                  _settings,
                ).copyWith(borderRadius: AppUi.cardRadius(AppUi.radiusXl)),
                child: Icon(
                  Icons.library_books_rounded,
                  size: 42,
                  color: _settings.accentColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Your library is empty',
                style: _settings.uiText(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _settings.textColor,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Import an EPUB from your device or browse free public-domain books to start reading.',
                style: _settings.uiText(
                  fontSize: 15,
                  color: _settings.mutedColor,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _importBook,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    'Import EPUB',
                    style: _settings.uiText(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _settings.accentColor,
                    foregroundColor: Colors.white,
                    shape: AppUi.shape(),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _browsePublicDomainBooks,
                  icon: const Icon(Icons.public_rounded),
                  label: Text(
                    'Browse Free Books',
                    style: _settings.uiText(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _settings.textColor,
                    side: BorderSide(
                      color: _settings.mutedColor.withValues(alpha: 0.2),
                    ),
                    shape: AppUi.shape(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your EPUBs stay on this device. Online lookup is optional.',
                style: _settings.uiText(
                  fontSize: 12,
                  color: _settings.mutedColor.withValues(alpha: 0.78),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<File> _filteredBooks() {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _books;

    return _books.where((file) {
      final bookId = p.basename(file.path);
      final metadata = _metadataService.getMetadata(bookId);
      final title = (metadata?.title ?? bookId.replaceAll('.epub', ''))
          .toLowerCase();
      final author = (metadata?.author ?? 'Unknown Author').toLowerCase();
      return title.contains(query) || author.contains(query);
    }).toList();
  }

  Widget _buildLibraryControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: AppUi.surfaceCard(_settings, radius: AppUi.radiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: _settings.uiText(
                color: _settings.textColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: 'Search library',
                hintStyle: _settings.uiText(
                  color: _settings.mutedColor,
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _settings.mutedColor,
                  size: 20,
                ),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          color: _settings.mutedColor,
                          size: 20,
                        ),
                      ),
                filled: true,
                fillColor: _settings.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.035),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: AppUi.cardRadius(AppUi.radiusSm),
                  borderSide: BorderSide(
                    color: _settings.mutedColor.withValues(alpha: 0.12),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppUi.cardRadius(AppUi.radiusSm),
                  borderSide: BorderSide(
                    color: _settings.mutedColor.withValues(alpha: 0.12),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppUi.cardRadius(AppUi.radiusSm),
                  borderSide: BorderSide(
                    color: _settings.accentColor,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _SortMode.values.map((mode) {
                final isSelected = _sortMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      mode.label,
                      style: _settings.uiText(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? Colors.white : _settings.mutedColor,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: _settings.accentColor,
                    backgroundColor: _settings.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: isSelected
                          ? BorderSide.none
                          : BorderSide(
                              color: _settings.mutedColor.withValues(
                                alpha: _settings.isDark ? 0.12 : 0.08,
                              ),
                            ),
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _sortMode = mode;
                          _sortBooks(_books);
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: AppUi.surfaceCard(_settings, prominent: true),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 38,
            color: _settings.mutedColor.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 18),
          Text(
            'No books match "$_searchQuery"',
            textAlign: TextAlign.center,
            style: _settings.uiText(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _settings.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different title or author search.',
            textAlign: TextAlign.center,
            style: _settings.uiText(
              fontSize: 14,
              height: 1.45,
              color: _settings.mutedColor,
            ),
          ),
        ],
      ),
    );
  }

  File? _selectHeroBook(List<File> books) {
    if (books.isEmpty) return null;
    final readBooks = books.where((file) {
      final metadata = _metadataService.getMetadata(p.basename(file.path));
      return metadata != null && metadata.lastReadIndex > 0;
    }).toList();
    final candidates = [...(readBooks.isEmpty ? books : readBooks)];
    candidates.sort((a, b) {
      final metadataA = _metadataService.getMetadata(p.basename(a.path));
      final metadataB = _metadataService.getMetadata(p.basename(b.path));
      return (metadataB?.lastReadTime ?? 0).compareTo(
        metadataA?.lastReadTime ?? 0,
      );
    });
    return candidates.first;
  }

  _LibraryBookDisplayData _bookDisplayData(File file) {
    final bookId = p.basename(file.path);
    final metadata = _metadataService.getMetadata(bookId);
    final title = metadata?.title ?? bookId.replaceAll('.epub', '');
    final author = metadata?.author ?? 'Unknown Author';
    final coverPath = metadata?.coverImagePath;
    final hasCover =
        coverPath != null && (_coverExistsByBookId[bookId] ?? false);
    final progress = (metadata != null && metadata.totalChunks > 1)
        ? (metadata.lastReadIndex / (metadata.totalChunks - 1)).clamp(0.0, 1.0)
        : (metadata?.totalChunks == 1 ? 1.0 : 0.0);
    final progressPercent = (progress * 100).toInt();

    String? timeAgo;
    if (metadata != null && metadata.lastReadIndex > 0) {
      final lastReadDate = DateTime.fromMillisecondsSinceEpoch(
        metadata.lastReadTime,
      );
      final daysSince = DateTime.now().difference(lastReadDate).inDays;
      if (daysSince == 0) {
        timeAgo = 'Read today';
      } else if (daysSince == 1) {
        timeAgo = 'Yesterday';
      } else if (daysSince < 7) {
        timeAgo = '$daysSince days ago';
      } else if (daysSince < 30) {
        timeAgo = '${(daysSince / 7).floor()}w ago';
      } else {
        timeAgo = '${(daysSince / 30).floor()}mo ago';
      }
    }

    return _LibraryBookDisplayData(
      bookId: bookId,
      metadata: metadata,
      title: title,
      author: author,
      coverPath: coverPath,
      hasCover: hasCover,
      progress: progress,
      progressPercent: progressPercent,
      timeAgo: timeAgo,
    );
  }

  Widget _buildLibrarySectionHeader({required int remainingCount}) {
    final label = remainingCount == 1 ? '1 book' : '$remainingCount books';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library',
                style: _settings.uiText(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _settings.textColor,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _isImportingBook ? 'Adding a book...' : label,
                style: _settings.uiText(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _settings.mutedColor,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        _buildLibraryViewToggle(),
      ],
    );
  }

  Widget _buildLibraryViewToggle() {
    return Semantics(
      label: 'Library view mode',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: _settings.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: AppUi.cardRadius(AppUi.radiusSm),
          border: Border.all(
            color: _settings.mutedColor.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildViewToggleButton(
              mode: _LibraryViewMode.list,
              icon: Icons.view_agenda_outlined,
              tooltip: 'List view',
            ),
            _buildViewToggleButton(
              mode: _LibraryViewMode.grid,
              icon: Icons.grid_view_rounded,
              tooltip: 'Grid view',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewToggleButton({
    required _LibraryViewMode mode,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: AppUi.cardRadius(8),
        onTap: () => setState(() => _viewMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 34,
          height: 30,
          decoration: BoxDecoration(
            color: isSelected ? _settings.accentColor : Colors.transparent,
            borderRadius: AppUi.cardRadius(8),
          ),
          child: Icon(
            icon,
            size: 17,
            color: isSelected ? Colors.white : _settings.mutedColor,
          ),
        ),
      ),
    );
  }

  Widget _buildBookList(List<File> books) {
    final children = <Widget>[];
    if (_isImportingBook) {
      children.add(_buildLoadingBookSkeletonCard(isGrid: false));
    }
    for (final file in books) {
      children.add(_buildCompactBookListCard(file));
    }

    if (children.isEmpty) {
      return _buildRestOfLibraryEmptyState();
    }

    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          children[i],
        ],
      ],
    );
  }

  Widget _buildBookGrid(List<File> books) {
    final itemCount = books.length + (_isImportingBook ? 1 : 0);
    if (itemCount == 0) {
      return _buildRestOfLibraryEmptyState();
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemBuilder: (context, index) {
        if (_isImportingBook && index == 0) {
          return _buildLoadingBookSkeletonCard(isGrid: true);
        }
        final bookIndex = index - (_isImportingBook ? 1 : 0);
        return _buildCompactBookGridCard(books[bookIndex]);
      },
    );
  }

  Widget _buildRestOfLibraryEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: AppUi.surfaceCard(_settings, radius: AppUi.radiusMd),
      child: Text(
        'No other books yet.',
        textAlign: TextAlign.center,
        style: _settings.uiText(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _settings.mutedColor,
        ),
      ),
    );
  }

  Widget _buildContinueReadingCard(File file) {
    final data = _bookDisplayData(file);
    return Semantics(
      button: true,
      label: [
        'Continue reading',
        data.title,
        'by ${data.author}',
        data.progress > 0
            ? '${data.progressPercent} percent complete'
            : 'Not started',
        'Double tap to open. Long press for book options',
      ].join(', '),
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => _openBook(file),
          onLongPress: () => _showBookOptions(file, data.title),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: AppUi.surfaceCard(_settings, prominent: true),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.hasCover)
                  ClipRRect(
                    borderRadius: AppUi.cardRadius(AppUi.radiusSm),
                    child: Image.file(
                      File(data.coverPath!),
                      width: 104,
                      height: 168,
                      fit: BoxFit.cover,
                      cacheWidth: 208,
                    ),
                  )
                else
                  _buildGeneratedCover(
                    data.title,
                    data.author,
                    width: 104,
                    height: 168,
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 168,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_circle_fill_rounded,
                                size: 17,
                                color: _settings.accentColor,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  'Continue Reading',
                                  style: _settings.uiText(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: _settings.accentColor,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            data.title,
                            style: _settings.uiText(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _settings.textColor,
                              height: 1.14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            data.author,
                            style: _settings.uiText(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _settings.mutedColor,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 7),
                          FutureBuilder<_BookCardReadingSummary>(
                            future: _bookCardReadingSummary(
                              data.bookId,
                              data.metadata,
                            ),
                            initialData: const _BookCardReadingSummary(),
                            builder: (context, snapshot) {
                              final summary = snapshot.data;
                              final detailLine = _buildBookCardDetailLine(
                                timeAgo: data.timeAgo,
                                chapterNumber: summary?.chapterNumber,
                                progress: data.progress,
                              );
                              final timeLeft = summary?.timeLeft;
                              final showTimeLeft =
                                  timeLeft != null &&
                                  data.progress > 0 &&
                                  data.progress < 1;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    detailLine,
                                    style: _settings.uiText(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _settings.mutedColor.withValues(
                                        alpha: 0.86,
                                      ),
                                      height: 1.25,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (showTimeLeft) ...[
                                    const SizedBox(height: 5),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          maxWidth: 150,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: AppUi.accentPill(_settings)
                                            .copyWith(
                                              borderRadius: AppUi.cardRadius(
                                                999,
                                              ),
                                            ),
                                        child: Text(
                                          '$timeLeft left',
                                          style: _settings.uiText(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: _settings.accentColor,
                                            height: 1.1,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: data.progress,
                                    minHeight: 7,
                                    backgroundColor: _settings.mutedColor
                                        .withValues(alpha: 0.13),
                                    color: _settings.accentColor.withValues(
                                      alpha: 0.78,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${data.progressPercent}%',
                                style: _settings.uiText(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: _settings.accentColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBookListCard(File file) {
    final data = _bookDisplayData(file);

    return Semantics(
      button: true,
      label: [
        data.title,
        'by ${data.author}',
        data.progress > 0
            ? '${data.progressPercent} percent complete'
            : 'Not started',
        'Double tap to open. Long press for book options',
      ].join(', '),
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => _openBook(file),
          onLongPress: () => _showBookOptions(file, data.title),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: AppUi.surfaceCard(_settings, radius: AppUi.radiusMd),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.hasCover)
                  ClipRRect(
                    borderRadius: AppUi.cardRadius(8),
                    child: Image.file(
                      File(data.coverPath!),
                      width: 72,
                      height: 108,
                      fit: BoxFit.cover,
                      cacheWidth: 144,
                    ),
                  )
                else
                  _buildGeneratedCover(
                    data.title,
                    data.author,
                    width: 72,
                    height: 108,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 108,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            style: _settings.uiText(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _settings.textColor,
                              height: 1.16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data.author,
                            style: _settings.uiText(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _settings.mutedColor,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 7),
                          FutureBuilder<_BookCardReadingSummary>(
                            future: _bookCardReadingSummary(
                              data.bookId,
                              data.metadata,
                            ),
                            initialData: const _BookCardReadingSummary(),
                            builder: (context, snapshot) {
                              final summary = snapshot.data;
                              final detailLine = _buildBookCardDetailLine(
                                timeAgo: data.timeAgo,
                                chapterNumber: summary?.chapterNumber,
                                progress: data.progress,
                              );

                              return Text(
                                detailLine,
                                style: _settings.uiText(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _settings.mutedColor.withValues(
                                    alpha: 0.82,
                                  ),
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: data.progress,
                                    minHeight: 5,
                                    backgroundColor: _settings.mutedColor
                                        .withValues(alpha: 0.12),
                                    color: _settings.accentColor.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${data.progressPercent}%',
                                textAlign: TextAlign.right,
                                style: _settings.uiText(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _settings.accentColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBookGridCard(File file) {
    final data = _bookDisplayData(file);

    return Semantics(
      button: true,
      label: [
        data.title,
        'by ${data.author}',
        data.progress > 0
            ? '${data.progressPercent} percent complete'
            : 'Not started',
        'Double tap to open. Long press for book options',
      ].join(', '),
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => _openBook(file),
          onLongPress: () => _showBookOptions(file, data.title),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _settings.menuColor,
              borderRadius: AppUi.cardRadius(AppUi.radiusMd),
              border: Border.all(
                color: _settings.mutedColor.withValues(
                  alpha: _settings.isDark ? 0.16 : 0.1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _settings.isDark ? 0.28 : 0.12,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (data.hasCover)
                  Image.file(
                    File(data.coverPath!),
                    fit: BoxFit.cover,
                    cacheWidth: 360,
                  )
                else
                  _buildGeneratedCover(
                    data.title,
                    data.author,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.16),
                          Colors.black.withValues(alpha: 0.82),
                        ],
                        stops: const [0.42, 0.68, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 14,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        style: _settings.uiText(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.12,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.55),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.author,
                        style: _settings.uiText(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.78),
                          height: 1.12,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: data.progress,
                    minHeight: 4,
                    backgroundColor: _settings.mutedColor.withValues(
                      alpha: 0.1,
                    ),
                    color: _settings.accentColor.withValues(alpha: 0.74),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingBookSkeletonCard({required bool isGrid}) {
    final color = _settings.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final highlight = _settings.isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.white.withValues(alpha: 0.55);

    if (isGrid) {
      return Semantics(
        label: 'Importing book',
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: AppUi.surfaceCard(_settings, radius: AppUi.radiusMd),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _skeletonBox(
                width: double.infinity,
                height: double.infinity,
                color: color,
                highlight: highlight,
                radius: AppUi.radiusMd,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.62),
                      ],
                      stops: const [0.42, 0.68, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _skeletonBox(
                      width: double.infinity,
                      height: 14,
                      color: Colors.white.withValues(alpha: 0.18),
                      highlight: Colors.white.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 7),
                    _skeletonBox(
                      width: 84,
                      height: 11,
                      color: Colors.white.withValues(alpha: 0.15),
                      highlight: Colors.white.withValues(alpha: 0.08),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: _settings.mutedColor.withValues(alpha: 0.1),
                  color: _settings.accentColor.withValues(alpha: 0.44),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: 'Importing book',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: AppUi.surfaceCard(_settings, radius: AppUi.radiusMd),
        child: Row(
          children: [
            _skeletonBox(
              width: 58,
              height: 86,
              color: color,
              highlight: highlight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 86,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonBox(
                      width: double.infinity,
                      height: 16,
                      color: color,
                      highlight: highlight,
                    ),
                    const SizedBox(height: 9),
                    _skeletonBox(
                      width: 130,
                      height: 12,
                      color: color,
                      highlight: highlight,
                    ),
                    const SizedBox(height: 10),
                    _skeletonBox(
                      width: 92,
                      height: 11,
                      color: color,
                      highlight: highlight,
                    ),
                    const Spacer(),
                    _skeletonBox(
                      width: double.infinity,
                      height: 5,
                      color: color,
                      highlight: highlight,
                      radius: 999,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeletonBox({
    required double width,
    required double height,
    required Color color,
    required Color highlight,
    double radius = 8,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: AppUi.cardRadius(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [highlight, color],
        ),
      ),
    );
  }

  Future<_BookCardReadingSummary> _bookCardReadingSummary(
    String bookId,
    BookMetadata? metadata,
  ) {
    final futureKey =
        '$bookId:${metadata?.lastReadIndex ?? 0}:${metadata?.totalChunks ?? 0}';
    return _bookCardSummaryFutures.putIfAbsent(
      futureKey,
      () => _loadBookCardReadingSummary(bookId, metadata),
    );
  }

  Future<_BookCardReadingSummary> _loadBookCardReadingSummary(
    String bookId,
    BookMetadata? metadata,
  ) async {
    if (metadata == null || metadata.totalChunks <= 0) {
      return const _BookCardReadingSummary();
    }

    final summary = metadata.readingSummary;
    if (summary != null && summary.isUsable) {
      return _summaryFromReadingSummary(bookId, metadata, summary);
    }

    final cachedBook = await _bookCacheService.loadCachedBook(bookId);
    if (cachedBook == null) {
      return const _BookCardReadingSummary();
    }

    final cachedSummary = BookReadingSummary.fromParsedBook(
      chunks: cachedBook.chunks,
      chapters: cachedBook.chapters,
    );
    unawaited(
      _metadataService.updateReadingSummary(
        bookId: bookId,
        summary: cachedSummary,
        totalChunks: cachedBook.chunks.length,
      ),
    );

    return _summaryFromReadingSummary(bookId, metadata, cachedSummary);
  }

  _BookCardReadingSummary _summaryFromReadingSummary(
    String bookId,
    BookMetadata metadata,
    BookReadingSummary summary,
  ) {
    final chapterNumber = summary.chapterNumberFor(metadata.lastReadIndex);
    final timeLeft = !_settings.readingInsightsEnabled
        ? null
        : _bookTimeLeftLabel(
            bookId,
            summary.remainingWordsAfter(metadata.lastReadIndex),
          );
    return _BookCardReadingSummary(
      chapterNumber: chapterNumber,
      timeLeft: timeLeft,
    );
  }

  String? _bookTimeLeftLabel(String bookId, int remainingWords) {
    if (remainingWords <= 0) return null;
    final duration = _statsService.estimateTimeLeft(
      bookId: bookId,
      remainingWords: remainingWords,
    );
    return '~${ReadingStatsService.formatDuration(duration)}';
  }

  String _buildBookCardDetailLine({
    required String? timeAgo,
    required int? chapterNumber,
    required double progress,
  }) {
    final parts = <String>[];
    if (timeAgo != null) {
      parts.add(timeAgo);
    }
    if (chapterNumber != null && progress > 0) {
      parts.add('Chapter $chapterNumber');
    }
    if (parts.isNotEmpty) {
      return parts.join(' • ');
    }
    return progress > 0 ? 'In progress' : 'Start reading';
  }

  /// Generates a deterministic gradient cover from the book title
  Widget _buildGeneratedCover(
    String title,
    String author, {
    double width = 64,
    double height = 92,
  }) {
    final hash = title.hashCode;
    final hue1 = (hash % 360).abs().toDouble();
    final hue2 = ((hash ~/ 360) % 360).abs().toDouble();

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: AppUi.cardRadius(AppUi.radiusSm),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1.0, hue1, 0.4, 0.35).toColor(),
            HSLColor.fromAHSL(1.0, hue2, 0.5, 0.25).toColor(),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: _settings.isDark ? 0.2 : 0.08,
            ),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: _settings.uiText(
                fontSize: width > 70 ? 10 : 8,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCardReadingSummary {
  final int? chapterNumber;
  final String? timeLeft;

  const _BookCardReadingSummary({this.chapterNumber, this.timeLeft});
}

class _LibraryBookDisplayData {
  final String bookId;
  final BookMetadata? metadata;
  final String title;
  final String author;
  final String? coverPath;
  final bool hasCover;
  final double progress;
  final int progressPercent;
  final String? timeAgo;

  const _LibraryBookDisplayData({
    required this.bookId,
    required this.metadata,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.hasCover,
    required this.progress,
    required this.progressPercent,
    required this.timeAgo,
  });
}

class _BookOptionAction {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDangerous;

  const _BookOptionAction({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.isDangerous = false,
  });
}

enum _SortMode {
  recentlyRead('Recent'),
  title('Title'),
  author('Author'),
  progress('Progress');

  final String label;
  const _SortMode(this.label);
}

enum _LibraryViewMode { list, grid }
