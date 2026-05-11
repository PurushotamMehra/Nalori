import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book_share_payload.dart';
import '../models/quote_card_style.dart';
import '../models/quote_card_theme.dart';
import '../models/quote_share_payload.dart';
import '../services/book_metadata_service.dart';
import '../services/api_client.dart';
import '../services/open_library_metadata_service.dart';
import '../services/quote_card_export_service.dart';
import '../services/quote_card_palette_service.dart';
import '../services/quote_card_save_service.dart';
import '../services/quote_card_share_service.dart';
import '../ui/app_visuals.dart';
import '../widgets/quote_card_canvas.dart';

class QuoteCardPreviewScreen extends StatefulWidget {
  final QuoteSharePayload? payload;
  final BookSharePayload? bookPayload;
  final ReadingRecapPayload? recapPayload;

  const QuoteCardPreviewScreen({super.key, required this.payload})
    : bookPayload = null,
      recapPayload = null,
      onCoverChanged = null,
      assert(payload != null);

  const QuoteCardPreviewScreen.book({
    super.key,
    required BookSharePayload payload,
    this.onCoverChanged,
  }) : payload = null,
       recapPayload = null,
       bookPayload = payload;

  const QuoteCardPreviewScreen.readingRecap({
    super.key,
    required ReadingRecapPayload payload,
    this.onCoverChanged,
  }) : payload = null,
       bookPayload = null,
       recapPayload = payload;

  final VoidCallback? onCoverChanged;

  bool get isBookCard => bookPayload != null;
  bool get isReadingRecap => recapPayload != null;

  String? get coverImagePath => isReadingRecap
      ? recapPayload!.coverImagePath
      : isBookCard
      ? bookPayload!.coverImagePath
      : payload!.coverImagePath;

  String get bookTitle => isReadingRecap
      ? recapPayload!.bookTitle
      : isBookCard
      ? bookPayload!.bookTitle
      : payload!.bookTitle;

  @override
  State<QuoteCardPreviewScreen> createState() => _QuoteCardPreviewScreenState();
}

class _QuoteCardPreviewScreenState extends State<QuoteCardPreviewScreen> {
  static const List<QuoteCardStyle> _styles = [
    QuoteCardStyle.classic,
    QuoteCardStyle.polaroid,
    QuoteCardStyle.brokenFrame,
    QuoteCardStyle.editorialGlass,
    QuoteCardStyle.socialStory,
  ];

  final _cardKey = GlobalKey();
  final _paletteService = QuoteCardPaletteService();
  final _exportService = QuoteCardExportService();
  final _shareService = QuoteCardShareService();
  final _saveService = QuoteCardSaveService();
  final _metadataService = BookMetadataService();
  late final PageController _stylePageController;

  late List<QuoteCardTheme> _themes;
  BookSharePayload? _bookPayload;
  ReadingRecapPayload? _recapPayload;
  int _selectedThemeIndex = 0;
  bool _isSharing = false;
  bool _isSaving = false;
  bool _isChangingCover = false;
  TextAlign _textAlign = TextAlign.left;
  QuoteCardStyle _cardStyle = QuoteCardStyle.classic;
  _ShareEditorTab _selectedEditorTab = _ShareEditorTab.theme;

  QuoteCardTheme get _selectedTheme => _themes[_selectedThemeIndex];
  BookSharePayload get _currentBookPayload =>
      _bookPayload ?? widget.bookPayload!;
  ReadingRecapPayload get _currentRecapPayload =>
      _recapPayload ?? widget.recapPayload!;
  String? get _currentCoverImagePath => widget.isBookCard
      ? _currentBookPayload.coverImagePath
      : widget.isReadingRecap
      ? _currentRecapPayload.coverImagePath
      : widget.coverImagePath;

  @override
  void initState() {
    super.initState();
    _bookPayload = widget.bookPayload;
    _recapPayload = widget.recapPayload;
    _themes = QuoteCardPaletteService.fallbackThemes();
    _stylePageController = PageController(
      initialPage: _styleIndexFor(_cardStyle),
      viewportFraction: 0.88,
    );
    _loadThemes();
  }

  @override
  void dispose() {
    _stylePageController.dispose();
    super.dispose();
  }

  Future<void> _loadThemes() async {
    final themes = await _paletteService.loadThemes(_currentCoverImagePath);
    if (!mounted || themes.isEmpty) return;
    setState(() {
      _themes = themes;
      _selectedThemeIndex = _selectedThemeIndex.clamp(0, themes.length - 1);
    });
  }

  Future<void> _changeBookCover() async {
    if ((!widget.isBookCard && !widget.isReadingRecap) || _isChangingCover) {
      return;
    }
    setState(() => _isChangingCover = true);

    try {
      await _metadataService.init();
      final candidates = await _metadataService.findCoverCandidates(
        widget.isReadingRecap
            ? _currentRecapPayload.bookId
            : _currentBookPayload.bookId,
      );
      if (!mounted) return;

      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No cover options found.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final coverPath = await _showCoverPicker(candidates);
      if (coverPath == null || !mounted) return;

      setState(() {
        if (widget.isBookCard) {
          _bookPayload = _currentBookPayload.copyWith(
            coverImagePath: coverPath,
          );
        }
      });
      widget.onCoverChanged?.call();
      await _loadThemes();
    } finally {
      if (mounted) setState(() => _isChangingCover = false);
    }
  }

  Future<void> _uploadBookCover() async {
    if ((!widget.isBookCard && !widget.isReadingRecap) || _isChangingCover) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: 'Choose a cover image',
    );
    if (result == null || result.files.isEmpty) return;

    final sourcePath = result.files.single.path;
    if (sourcePath == null) return;

    setState(() => _isChangingCover = true);
    try {
      await _metadataService.init();
      final updated = await _metadataService.saveLocalCover(
        bookId: widget.isReadingRecap
            ? _currentRecapPayload.bookId
            : _currentBookPayload.bookId,
        sourceFile: File(sourcePath),
      );
      if (updated == null || !mounted) return;

      setState(() {
        if (widget.isBookCard) {
          _bookPayload = _currentBookPayload.copyWith(
            coverImagePath: updated.coverImagePath,
          );
        }
      });
      widget.onCoverChanged?.call();
      await _loadThemes();
    } finally {
      if (mounted) setState(() => _isChangingCover = false);
    }
  }

  Future<String?> _showCoverPicker(List<BookCoverCandidate> candidates) {
    var saving = false;
    return showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF151515),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const Text(
                        'Choose a cover',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentBookPayload.bookTitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.58),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  Navigator.pop(ctx);
                                  await _uploadBookCover();
                                },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Upload from device'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
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
                                        final updated = await _metadataService
                                            .applyCoverCandidate(
                                              _currentBookPayload.bookId,
                                              candidate,
                                            );
                                        if (ctx.mounted) {
                                          Navigator.pop(
                                            ctx,
                                            updated?.coverImagePath,
                                          );
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
                                                      ApiClient.userAgent,
                                                },
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.08,
                                                          ),
                                                      child: const Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        color: Colors.white54,
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
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.55,
                                        ),
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
                        const LinearProgressIndicator(color: Colors.white),
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

  Future<void> _shareQuoteCard() async {
    if (_isSharing || _isSaving) return;
    HapticFeedback.selectionClick();
    setState(() => _isSharing = true);

    try {
      final file = await _exportService.exportBoundary(
        _cardKey,
        fileName:
            '${widget.isReadingRecap
                ? 'reading_recap'
                : widget.isBookCard
                ? 'book_card'
                : 'quote_card'}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (!mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;

      await _shareService.shareQuoteImage(
        file: file,
        bookTitle: widget.bookTitle,
        title: widget.isReadingRecap
            ? 'Reading recap'
            : widget.isBookCard
            ? 'Book card'
            : 'Quote card',
        text: widget.isReadingRecap
            ? 'Reading recap: "${widget.bookTitle}"'
            : widget.isBookCard
            ? 'Book recommendation: "${widget.bookTitle}"'
            : null,
        sharePositionOrigin: origin,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not share ${widget.isBookCard ? 'book' : 'quote'} card: $error',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _saveQuoteCard() async {
    if (_isSharing || _isSaving) return;
    HapticFeedback.selectionClick();
    setState(() => _isSaving = true);

    try {
      final file = await _exportService.exportBoundary(
        _cardKey,
        fileName:
            '${widget.isReadingRecap
                ? 'reading_recap'
                : widget.isBookCard
                ? 'book_card'
                : 'quote_card'}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final savedLocation = await _saveService.saveQuoteImage(file);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.isReadingRecap
                ? 'Reading recap'
                : widget.isBookCard
                ? 'Book'
                : 'Quote'} card saved to $savedLocation',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save ${widget.isBookCard ? 'book' : 'quote'} card: $error',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  int _styleIndexFor(QuoteCardStyle style) {
    final index = _styles.indexOf(style);
    return index < 0 ? 0 : index;
  }

  String _styleLabel(QuoteCardStyle style) {
    return switch (style) {
      QuoteCardStyle.classic => 'Classic',
      QuoteCardStyle.polaroid => 'Polaroid',
      QuoteCardStyle.brokenFrame => 'Broken Frame',
      QuoteCardStyle.editorialGlass => 'Glass',
      QuoteCardStyle.socialStory => 'Social',
    };
  }

  void _setCardStyle(QuoteCardStyle style, {bool animatePage = true}) {
    if (_cardStyle == style) return;
    HapticFeedback.selectionClick();
    setState(() => _cardStyle = style);

    final page = _styleIndexFor(style);
    if (!_stylePageController.hasClients) return;
    if (animatePage) {
      _stylePageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _stylePageController.jumpToPage(page);
    }
  }

  Future<void> _openFullScreenPreview() async {
    HapticFeedback.selectionClick();
    final selectedStyle = await Navigator.of(context).push<QuoteCardStyle>(
      PageRouteBuilder(
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullScreenSharePreview(
          payload: widget.payload,
          bookPayload: widget.isBookCard ? _currentBookPayload : null,
          recapPayload: widget.isReadingRecap ? _currentRecapPayload : null,
          theme: _selectedTheme,
          textAlign: _textAlign,
          initialStyle: _cardStyle,
          styles: _styles,
          styleLabel: _styleLabel,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    if (!mounted || selectedStyle == null) return;
    _setCardStyle(selectedStyle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(child: _buildPreviewStage()),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stageWidth = constraints.maxWidth;
        final stageHeight = constraints.maxHeight;
        final maxPreviewWidth = math.max(220.0, stageWidth - 40);
        final previewWidth = math.min(maxPreviewWidth, 360.0);
        final previewHeight = previewWidth * 16 / 9;

        return DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFF090909)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, stageHeight - 28),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: stageWidth,
                      height: previewHeight,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PageView.builder(
                            key: const ValueKey('share-style-page-view'),
                            controller: _stylePageController,
                            physics: const PageScrollPhysics(),
                            itemCount: _styles.length,
                            onPageChanged: (index) {
                              final style = _styles[index];
                              if (_cardStyle == style) return;
                              HapticFeedback.selectionClick();
                              setState(() => _cardStyle = style);
                            },
                            itemBuilder: (context, index) {
                              final style = _styles[index];
                              final selected = style == _cardStyle;
                              return AnimatedPadding(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: selected ? 0 : 18,
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _openFullScreenPreview,
                                  child: Center(
                                    child: SizedBox(
                                      width: previewWidth,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: selected ? 0.46 : 0.28,
                                              ),
                                              blurRadius: selected ? 34 : 20,
                                              offset: const Offset(0, 18),
                                            ),
                                          ],
                                        ),
                                        child: _buildPreviewCanvas(
                                          cardStyle: style,
                                          exportable: selected,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          Positioned(
                            top: 10,
                            right: math.max(
                              22,
                              (stageWidth - previewWidth) / 2 + 12,
                            ),
                            child: Tooltip(
                              message: 'Full-screen preview',
                              child: IconButton.filled(
                                onPressed: _openFullScreenPreview,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.44,
                                  ),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.fullscreen_rounded),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _styleLabel(_cardStyle),
                      key: const ValueKey('share-selected-style-label'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _styleDots(_cardStyle),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewCanvas({
    required QuoteCardStyle cardStyle,
    bool exportable = false,
  }) {
    final canvas = widget.isReadingRecap
        ? ReadingRecapCardCanvas(
            payload: _currentRecapPayload,
            theme: _selectedTheme,
            textAlign: _textAlign,
            cardStyle: cardStyle,
          )
        : widget.isBookCard
        ? BookCardCanvas(
            payload: _currentBookPayload,
            theme: _selectedTheme,
            textAlign: _textAlign,
            cardStyle: cardStyle,
          )
        : QuoteCardCanvas(
            payload: widget.payload!,
            theme: _selectedTheme,
            textAlign: _textAlign,
            cardStyle: cardStyle,
          );

    if (!exportable) return canvas;
    return RepaintBoundary(key: _cardKey, child: canvas);
  }

  Widget _styleDots(QuoteCardStyle selectedStyle) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final style in _styles)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: style == selectedStyle ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: style == selectedStyle
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final modeLabel = widget.isReadingRecap
        ? 'Recap'
        : widget.isBookCard
        ? 'Book'
        : 'Quote';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            color: Colors.white,
            tooltip: 'Close',
          ),
          const Expanded(
            child: Text(
              'Share',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 18, color: Colors.white),
                const SizedBox(width: 7),
                Text(
                  modeLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlignmentToggle() {
    return _scrollingOptions(
      children: [
        _alignmentOption(
          icon: Icons.format_align_left_rounded,
          value: TextAlign.left,
          label: 'Left',
        ),
        _alignmentOption(
          icon: Icons.format_align_center_rounded,
          value: TextAlign.center,
          label: 'Center',
        ),
      ],
    );
  }

  Widget _alignmentOption({
    required IconData icon,
    required TextAlign value,
    required String label,
  }) {
    final selected = _textAlign == value;
    return _editorChip(
      label: label,
      icon: icon,
      selected: selected,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _textAlign = value);
      },
    );
  }

  Widget _buildStyleToggle() {
    return Center(
      child: Row(
        key: const ValueKey('share-style-indicator'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _styleLabel(_cardStyle),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 12),
          _styleDots(_cardStyle),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEditorTabs(),
              const SizedBox(height: 12),
              SizedBox(height: 42, child: _buildSelectedTabControls()),
              const SizedBox(height: 14),
              _buildActionRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorTabs() {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _editorTabButton(_ShareEditorTab.theme, 'Theme'),
          _editorTabButton(_ShareEditorTab.layout, 'Layout'),
          _editorTabButton(_ShareEditorTab.style, 'Style'),
        ],
      ),
    );
  }

  Widget _editorTabButton(_ShareEditorTab tab, String label) {
    final selected = _selectedEditorTab == tab;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (selected) return;
          HapticFeedback.selectionClick();
          setState(() => _selectedEditorTab = tab);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTabControls() {
    switch (_selectedEditorTab) {
      case _ShareEditorTab.theme:
        return _buildThemeControls();
      case _ShareEditorTab.layout:
        return _buildAlignmentToggle();
      case _ShareEditorTab.style:
        return _buildStyleToggle();
    }
  }

  Widget _buildThemeControls() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _themes.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final theme = _themes[index];
        final selected = index == _selectedThemeIndex;
        return _editorChip(
          label: theme.name,
          selected: selected,
          swatchColors: theme.backgroundColors,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedThemeIndex = index);
          },
        );
      },
    );
  }

  Widget _scrollingOptions({required List<Widget> children}) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) => children[index],
    );
  }

  Widget _editorChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    List<Color>? swatchColors,
  }) {
    final foreground = selected
        ? Colors.black
        : Colors.white.withValues(alpha: 0.82);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.13),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatchColors != null) ...[
              _themeSwatch(swatchColors),
              const SizedBox(width: 8),
            ] else if (icon != null) ...[
              Icon(icon, size: 17, color: foreground),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeSwatch(List<Color> colors) {
    final swatchColors = colors.isEmpty
        ? const [Color(0xFF222222), Color(0xFF444444)]
        : colors.take(3).toList();

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.black.withValues(alpha: 0.16)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: swatchColors.length == 1
              ? [swatchColors.first, swatchColors.first]
              : swatchColors,
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _isSharing || _isSaving ? null : _shareQuoteCard,
            icon: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
            label: Text(_isSharing ? 'Preparing...' : 'Share'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white24,
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        if (widget.isBookCard) ...[
          const SizedBox(width: 10),
          _secondaryActionButton(
            tooltip: 'Change cover',
            icon: Icons.photo_library_outlined,
            isLoading: _isChangingCover,
            onPressed: _isSharing || _isSaving || _isChangingCover
                ? null
                : _changeBookCover,
          ),
        ],
        const SizedBox(width: 10),
        _secondaryActionButton(
          tooltip: 'Save image',
          icon: Icons.file_download_outlined,
          isLoading: _isSaving,
          onPressed: _isSharing || _isSaving ? null : _saveQuoteCard,
        ),
      ],
    );
  }

  Widget _secondaryActionButton({
    required String tooltip,
    required IconData icon,
    required bool isLoading,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 54,
      height: 52,
      child: Tooltip(
        message: tooltip,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: const Color(0xFF202020),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white12,
            disabledForegroundColor: Colors.white38,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(icon, semanticLabel: tooltip),
        ),
      ),
    );
  }
}

class _FullScreenSharePreview extends StatefulWidget {
  final QuoteSharePayload? payload;
  final BookSharePayload? bookPayload;
  final ReadingRecapPayload? recapPayload;
  final QuoteCardTheme theme;
  final TextAlign textAlign;
  final QuoteCardStyle initialStyle;
  final List<QuoteCardStyle> styles;
  final String Function(QuoteCardStyle style) styleLabel;

  const _FullScreenSharePreview({
    required this.payload,
    required this.bookPayload,
    required this.recapPayload,
    required this.theme,
    required this.textAlign,
    required this.initialStyle,
    required this.styles,
    required this.styleLabel,
  });

  @override
  State<_FullScreenSharePreview> createState() =>
      _FullScreenSharePreviewState();
}

class _FullScreenSharePreviewState extends State<_FullScreenSharePreview> {
  late final PageController _pageController;
  late QuoteCardStyle _selectedStyle;

  @override
  void initState() {
    super.initState();
    _selectedStyle = widget.initialStyle;
    _pageController = PageController(
      initialPage: _styleIndexFor(_selectedStyle),
      viewportFraction: 0.92,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _styleIndexFor(QuoteCardStyle style) {
    final index = widget.styles.indexOf(style);
    return index < 0 ? 0 : index;
  }

  void _close() {
    Navigator.of(context).pop(_selectedStyle);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<QuoteCardStyle>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  key: const ValueKey('fullscreen-style-page-view'),
                  controller: _pageController,
                  itemCount: widget.styles.length,
                  onPageChanged: (index) {
                    final style = widget.styles[index];
                    if (_selectedStyle == style) return;
                    HapticFeedback.selectionClick();
                    setState(() => _selectedStyle = style);
                  },
                  itemBuilder: (context, index) {
                    final style = widget.styles[index];
                    final selected = style == _selectedStyle;
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final maxCardWidth = math.max(
                          300.0,
                          constraints.maxWidth - 24,
                        );
                        final cardWidth = math.min(maxCardWidth, 430.0);

                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            8,
                            selected ? 58 : 82,
                            8,
                            selected ? 72 : 96,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                0,
                                constraints.maxHeight - (selected ? 130 : 178),
                              ),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                width: cardWidth,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                        blurRadius: 40,
                                        offset: const Offset(0, 20),
                                      ),
                                    ],
                                  ),
                                  child: _buildCanvas(style),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: _close,
                  color: Colors.white,
                  tooltip: 'Close preview',
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 18,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.styleLabel(_selectedStyle),
                      key: const ValueKey('fullscreen-selected-style-label'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _styleDots(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(QuoteCardStyle style) {
    if (widget.recapPayload != null) {
      return ReadingRecapCardCanvas(
        payload: widget.recapPayload!,
        theme: widget.theme,
        textAlign: widget.textAlign,
        cardStyle: style,
      );
    }

    if (widget.bookPayload != null) {
      return BookCardCanvas(
        payload: widget.bookPayload!,
        theme: widget.theme,
        textAlign: widget.textAlign,
        cardStyle: style,
      );
    }

    return QuoteCardCanvas(
      payload: widget.payload!,
      theme: widget.theme,
      textAlign: widget.textAlign,
      cardStyle: style,
    );
  }

  Widget _styleDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final style in widget.styles)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: style == _selectedStyle ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: style == _selectedStyle
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

enum _ShareEditorTab { theme, layout, style }
