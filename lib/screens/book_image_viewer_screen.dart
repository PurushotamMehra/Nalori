import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book_share_payload.dart';
import '../models/reading_settings.dart';
import '../services/book_image_export_service.dart';
import '../services/image_file_save_service.dart';
import '../services/image_file_share_service.dart';
import '../ui/app_visuals.dart';
import 'quote_card_preview_screen.dart';

class BookImageViewerScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String bookTitle;
  final String author;
  final String bookId;
  final String imageLabel;
  final ReaderFontFamily fontFamily;

  const BookImageViewerScreen({
    super.key,
    required this.imageBytes,
    required this.bookTitle,
    required this.author,
    required this.bookId,
    required this.imageLabel,
    required this.fontFamily,
  });

  @override
  State<BookImageViewerScreen> createState() => _BookImageViewerScreenState();
}

class _BookImageViewerScreenState extends State<BookImageViewerScreen>
    with SingleTickerProviderStateMixin {
  final BookImageExportService _exportService = BookImageExportService();
  final ImageFileSaveService _saveService = ImageFileSaveService();
  final ImageFileShareService _shareService = ImageFileShareService();
  late final TransformationController _transformationController;
  late final AnimationController _resetController;
  Animation<Matrix4>? _resetAnimation;

  bool _isSaving = false;
  bool _isSharing = false;
  bool _isOpeningShareCard = false;
  bool _panEnabled = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _transformationController.addListener(_onTransformChanged);
    _resetController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
        )..addListener(() {
          final animation = _resetAnimation;
          if (animation != null) {
            _transformationController.value = animation.value;
          }
        });
  }

  @override
  void dispose() {
    _resetController.dispose();
    _transformationController
      ..removeListener(_onTransformChanged)
      ..dispose();
    super.dispose();
  }

  String get _fileStem =>
      '${widget.bookTitle}_${widget.imageLabel}_${DateTime.now().millisecondsSinceEpoch}';

  double get _currentScale =>
      _transformationController.value.getMaxScaleOnAxis();

  void _onTransformChanged() {
    final shouldEnablePan = _currentScale > 1.001;
    if (shouldEnablePan != _panEnabled && mounted) {
      setState(() => _panEnabled = shouldEnablePan);
    }
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    if (_currentScale <= 1.01) {
      _animateBackToIdentity();
    }
  }

  void _animateBackToIdentity() {
    final begin = Matrix4.copy(_transformationController.value);
    final end = Matrix4.identity();
    _resetAnimation = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOutCubic),
    );
    _resetController
      ..stop()
      ..reset()
      ..forward();
  }

  Future<void> _shareImage() async {
    if (_isSaving || _isSharing || _isOpeningShareCard) return;
    HapticFeedback.selectionClick();
    setState(() => _isSharing = true);

    try {
      final file = await _exportService.exportImageBytes(
        widget.imageBytes,
        fileStem: _fileStem,
      );
      if (!mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;

      await _shareService.shareImage(
        file: file,
        title: 'Book image',
        text: 'Image from "${widget.bookTitle}"',
        sharePositionOrigin: origin,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share image: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _shareImageAsCard() async {
    if (_isSaving || _isSharing || _isOpeningShareCard) return;
    HapticFeedback.selectionClick();
    setState(() => _isOpeningShareCard = true);

    try {
      final coverFile = await _exportService.exportImageBytes(
        widget.imageBytes,
        fileStem: _fileStem,
      );
      if (!mounted) return;

      final payload = BookSharePayload.fromBook(
        bookTitle: widget.bookTitle,
        author: widget.author,
        bookId: widget.bookId,
        coverImagePath: coverFile.path,
        fontFamily: widget.fontFamily,
      );

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QuoteCardPreviewScreen.book(payload: payload),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open share card: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpeningShareCard = false);
    }
  }

  Future<void> _saveImage() async {
    if (_isSaving || _isSharing || _isOpeningShareCard) return;
    HapticFeedback.selectionClick();
    setState(() => _isSaving = true);

    try {
      final file = await _exportService.exportImageBytes(
        widget.imageBytes,
        fileStem: _fileStem,
      );
      final savedLocation = await _saveService.saveImage(file);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image saved to $savedLocation'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save image: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return InteractiveViewer(
                  transformationController: _transformationController,
                  maxScale: 6,
                  panEnabled: _panEnabled,
                  onInteractionEnd: _handleInteractionEnd,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Center(
                      child: Image.memory(
                        widget.imageBytes,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) {
                          return const Text(
                            'Could not display this image.',
                            style: TextStyle(color: Colors.white70),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(12, safeArea.top + 8, 12, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white,
                    tooltip: 'Close',
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(child: BrandMark(size: 20)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.imageLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.bookTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: safeArea.bottom + 24,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xCC121212),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving || _isSharing || _isOpeningShareCard
                          ? null
                          : _saveImage,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Save'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving || _isSharing || _isOpeningShareCard
                          ? null
                          : _shareImage,
                      icon: _isSharing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Share image'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving || _isSharing || _isOpeningShareCard
                          ? null
                          : _shareImageAsCard,
                      icon: _isOpeningShareCard
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share card'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE85D04),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white38,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
