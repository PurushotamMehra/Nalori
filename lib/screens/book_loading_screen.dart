import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;

import '../models/book_metadata.dart';
import '../models/reading_settings.dart';
import '../services/book_metadata_service.dart';
import '../services/book_preparse_service.dart';
import 'reader_screen.dart';

/// Transitional loading screen — displayed while parsing an EPUB.
class BookLoadingScreen extends StatefulWidget {
  final File bookFile;
  final ReadingSettings settings;

  const BookLoadingScreen({
    super.key,
    required this.bookFile,
    required this.settings,
  });

  @override
  State<BookLoadingScreen> createState() => _BookLoadingScreenState();
}

class _BookLoadingScreenState extends State<BookLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  String _statusText = 'Opening book…';
  bool _failed = false;
  String? _errorMessage;
  BookMetadata? _metadata;
  bool _hasCover = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _loadAndParse();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadAndParse() async {
    final bookId = p.basename(widget.bookFile.path);
    final metadataService = BookMetadataService();

    // Try to load metadata for display (title, cover)
    await metadataService.init();
    final meta = metadataService.getMetadata(bookId);
    final hasCover =
        meta?.coverImagePath != null &&
        await File(meta!.coverImagePath!).exists();
    if (mounted) {
      setState(() {
        _metadata = meta;
        _hasCover = hasCover;
      });
    }

    try {
      if (mounted) {
        setState(() => _statusText = 'Loading book…');
      }
      final parsed = await BookPreparseService.instance.ensureParsed(
        widget.bookFile,
      );

      if (!mounted) return;

      final readingSummary = BookReadingSummary.fromParsedBook(
        chunks: parsed.chunks,
        chapters: parsed.chapters,
      );
      unawaited(
        metadataService.updateReadingSummary(
          bookId: bookId,
          summary: readingSummary,
          totalChunks: parsed.chunks.length,
        ),
      );

      setState(() => _statusText = 'Almost ready…');

      // Small delay so the transition feels intentional
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted) return;

      await Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => ReaderScreen(
            title: parsed.title,
            bookId: bookId,
            chunks: parsed.chunks,
            anchorMap: parsed.anchorMap,
            chapters: parsed.chapters,
            searchIndex: parsed.searchIndex,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );

      // Reader closed — pop the loading screen too so we return to book list
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _errorMessage = e.toString();
        _statusText = 'Failed to open book';
      });
    }
  }

  ReadingSettings get _s => widget.settings;

  @override
  Widget build(BuildContext context) {
    final coverPath = _metadata?.coverImagePath;
    final hasCover = coverPath != null && _hasCover;
    final title =
        _metadata?.title ?? p.basenameWithoutExtension(widget.bookFile.path);
    final author = _metadata?.author;

    return Scaffold(
      backgroundColor: _s.backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Blurred cover background ──
          if (hasCover)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Image.file(
                  File(coverPath),
                  fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.55),
                  colorBlendMode: BlendMode.darken,
                ),
              ),
            ),

          // ── Scrim overlay ──
          Positioned.fill(
            child: Container(
              color: _s.backgroundColor.withValues(alpha: hasCover ? 0.7 : 1.0),
            ),
          ),

          // ── Content ──
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Cover / placeholder ──
                      if (hasCover)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 28,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              File(coverPath),
                              width: 130,
                              height: 195,
                              fit: BoxFit.cover,
                              cacheWidth: 260,
                            ),
                          ),
                        )
                      else
                        _buildGeneratedCover(title, author ?? ''),

                      const SizedBox(height: 32),

                      // ── Title ──
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: _s.textColor,
                          letterSpacing: -0.3,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                      if (author != null && author.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          author,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: _s.mutedColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 40),

                      // ── Progress indicator or error ──
                      if (_failed) ...[
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.redAccent,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage ?? 'Unknown error',
                          style: GoogleFonts.inter(
                            color: Colors.redAccent,
                            fontSize: 13,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _s.textColor,
                                side: BorderSide(
                                  color: _s.mutedColor.withValues(alpha: 0.2),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: Text(
                                'Go Back',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _failed = false;
                                  _errorMessage = null;
                                  _statusText = 'Opening book…';
                                });
                                _loadAndParse();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE85D04),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'Retry',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Color(0xFFE85D04),
                            strokeWidth: 2.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _statusText,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _s.mutedColor,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Generates a deterministic gradient cover from the book title
  Widget _buildGeneratedCover(String title, String author) {
    final hash = title.hashCode;
    final hue1 = (hash % 360).abs().toDouble();
    final hue2 = ((hash ~/ 360) % 360).abs().toDouble();

    return Container(
      width: 130,
      height: 195,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
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
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            if (author.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                author,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
