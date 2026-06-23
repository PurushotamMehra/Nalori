import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book_metadata.dart';
import '../models/reading_settings.dart';
import '../services/book_metadata_service.dart';
import '../services/cover_palette_service.dart';
import '../services/library_service.dart';
import '../services/reading_settings_service.dart';
import '../services/user_education_service.dart';
import '../ui/continue_reading_colors.dart';
import 'book_list_screen.dart';
import 'how_to_use_screen.dart';
import 'reader_screen.dart';

/// The app's entry screen — shows a quick-resume card for the last-read book
/// or falls through to the library if nothing has been read yet.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _metadataService = BookMetadataService();
  final _coverPaletteService = CoverPaletteService();
  final _settingsService = ReadingSettingsService();
  final _libraryService = LibraryService();
  final _educationService = UserEducationService();

  ReadingSettings _settings = const ReadingSettings();
  BookMetadata? _lastBook;
  File? _lastBookFile;
  CoverPalette? _lastBookCoverPalette;
  bool _lastBookHasCover = false;
  bool _hasSeenHowToUse = true;
  bool _loading = true;
  bool _resumeOpening = false;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _init();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final settings = await _settingsService.loadSettings();
    final hasSeenHowToUse = await _educationService.hasSeenHowToUse();
    await _metadataService.init();

    // Find the most recently read book
    final allMeta = _metadataService.getAllSortedByLastRead();
    BookMetadata? lastRead;
    File? lastFile;

    if (allMeta.isNotEmpty) {
      for (final meta in allMeta) {
        final match = await _libraryService.localBookForMetadata(
          bookId: meta.id,
          managedFilePath: meta.managedFilePath,
        );
        if (match != null) {
          if (meta.managedFilePath != match.path) {
            await _metadataService.updateManagedFilePath(
              bookId: meta.id,
              managedFilePath: match.path,
            );
          }
          // Calculate progress to determine if book is basically finished
          final progress = meta.totalChunks > 1
              ? meta.lastReadIndex / (meta.totalChunks - 1)
              : 0.0;

          // Only show resume if user has actually started reading (index > 0)
          // AND hasn't finished the book yet (progress < 99%)
          if (meta.lastReadIndex > 0 && progress < 0.99) {
            lastRead = meta.managedFilePath == match.path
                ? meta
                : meta.copyWith(managedFilePath: match.path);
            lastFile = match;
            break; // Stop looking after the first most recently active/unfinished book
          }
        }
      }
    }

    var hasCover = false;
    CoverPalette? coverPalette;
    if (lastRead?.coverImagePath != null) {
      hasCover = await File(lastRead!.coverImagePath!).exists();
      coverPalette = await _coverPaletteService.loadPalette(
        lastRead.coverImagePath,
      );
    }

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _lastBook = lastRead;
      _lastBookFile = lastFile;
      _lastBookCoverPalette = coverPalette;
      _lastBookHasCover = hasCover;
      _hasSeenHowToUse = hasSeenHowToUse;
      _loading = false;
    });
    _fadeController.forward();
  }

  Future<void> _completeHowToUse() async {
    await _educationService.markHowToUseSeen();
    if (!mounted) return;
    setState(() {
      _hasSeenHowToUse = true;
    });
  }

  Future<void> _resumeReading() async {
    if (_resumeOpening || _lastBook == null || _lastBookFile == null) return;
    setState(() => _resumeOpening = true);
    final bookFile = await _libraryService.localBookForMetadata(
      bookId: _lastBook!.id,
      managedFilePath: _lastBook!.managedFilePath,
    );
    if (!mounted) return;
    if (bookFile == null) {
      setState(() => _resumeOpening = false);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BookListScreen()),
      );
      _init();
      return;
    }

    final metadata = _lastBook!.managedFilePath == bookFile.path
        ? _lastBook!
        : _lastBook!.copyWith(managedFilePath: bookFile.path);
    if (_lastBook!.managedFilePath != bookFile.path) {
      await _metadataService.updateManagedFilePath(
        bookId: metadata.id,
        managedFilePath: bookFile.path,
      );
      if (!mounted) return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen.directContinue(
          bookFile: bookFile,
          metadata: metadata,
          settings: _settings,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _resumeOpening = false);
    _init();
  }

  void _goToLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookListScreen()),
    ).then((_) => _init()); // refresh when returning
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _settings.backgroundColor,
        body: const SizedBox.shrink(),
      );
    }

    if (!_hasSeenHowToUse) {
      return HowToUseScreen(
        settings: _settings,
        firstRun: true,
        onDone: _completeHowToUse,
      );
    }

    // If no book has been read yet, go straight to library
    if (_lastBook == null || _lastBookFile == null) {
      // Use addPostFrameCallback to avoid build-during-build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const BookListScreen()),
          );
        }
      });
      return Scaffold(backgroundColor: _settings.backgroundColor);
    }

    return Scaffold(
      backgroundColor: _settings.backgroundColor,
      body: FadeTransition(opacity: _fadeAnim, child: _buildResumeCard()),
    );
  }

  Widget _buildResumeCard() {
    final meta = _lastBook!;
    final coverPath = meta.coverImagePath;
    final hasCover = coverPath != null && _lastBookHasCover;
    final progress = meta.totalChunks > 0
        ? (meta.lastReadIndex / meta.totalChunks).clamp(0.0, 1.0)
        : 0.0;
    final progressPercent = (progress * 100).toInt();
    final coverPalette = hasCover ? _lastBookCoverPalette : null;
    final colors = coverPalette == null
        ? ContinueReadingColors.fallback(_settings)
        : ContinueReadingColors.fromCover(
            settings: _settings,
            palette: coverPalette,
          );

    // Time since last read
    final lastReadDate = DateTime.fromMillisecondsSinceEpoch(meta.lastReadTime);
    final daysSince = DateTime.now().difference(lastReadDate).inDays;
    String timeAgo;
    if (daysSince == 0) {
      timeAgo = 'Read today';
    } else if (daysSince == 1) {
      timeAgo = 'Read yesterday';
    } else if (daysSince < 7) {
      timeAgo = '$daysSince days ago';
    } else {
      timeAgo = '${(daysSince / 7).floor()} weeks ago';
    }

    return Semantics(
      label:
          'Resume ${meta.title} by ${meta.author}, $progressPercent percent complete, $timeAgo',
      explicitChildNodes: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasCover)
            Positioned(
              top: 105,
              left: 0,
              right: 0,
              bottom: 0,
              child: ColoredBox(
                color: colors.baseColor,
                child: Image.file(
                  File(coverPath),
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  cacheWidth: 1440,
                ),
              ),
            )
          else
            Positioned.fill(
              child: _buildGeneratedCoverBackground(
                meta.title,
                meta.author,
                _settings,
              ),
            ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 190,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.baseColor,
                    colors.baseColor.withValues(alpha: 0.94),
                    colors.surfaceColor.withValues(alpha: 0.48),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.32, 0.7, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    colors.surfaceColor.withValues(alpha: 0.14),
                    colors.surfaceColor.withValues(alpha: 0.58),
                    colors.baseColor.withValues(alpha: 0.94),
                    colors.baseColor,
                  ],
                  stops: const [0.0, 0.34, 0.58, 0.74, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Text(
                    meta.title,
                    style: _settings.uiText(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: colors.titleColor,
                      letterSpacing: -0.9,
                      height: 1.1,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    meta.author,
                    style: _settings.uiText(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: colors.authorColor,
                      letterSpacing: 0.15,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: colors.statusBackgroundColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colors.statusBorderColor),
                    ),
                    child: Text(
                      '$progressPercent% complete  ·  $timeAgo',
                      style: _settings.uiText(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.statusTextColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _resumeReading,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accentColor,
                        foregroundColor: colors.onAccentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Continue Reading',
                        style: _settings.uiText(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _goToLibrary,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.browseColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Browse Library',
                          style: _settings.uiText(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: colors.progressTrackColor,
                color: colors.accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildGeneratedCoverBackground(
    String title,
    String author,
    ReadingSettings settings,
  ) {
    final hash = title.hashCode;
    final hue1 = (hash % 360).abs().toDouble();
    final hue2 = ((hash ~/ 360) % 360).abs().toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1.0, hue1, 0.42, 0.36).toColor(),
            HSLColor.fromAHSL(1.0, hue2, 0.48, 0.24).toColor(),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              title,
              style: settings.uiText(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.2),
                height: 1.08,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              author,
              style: settings.uiText(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.16),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
