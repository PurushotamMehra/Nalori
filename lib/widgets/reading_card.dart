import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/reading_settings.dart';
import '../controllers/speed_read_controller.dart';
import '../ui/app_visuals.dart';
import '../utils/final_layout_paragraphs.dart';
import '../utils/reader_content_parser.dart';
import '../widgets/highlight_palette_sheet.dart';
import '../widgets/note_sheets.dart';
import '../widgets/reader_table_block.dart';
import '../widgets/speed_read_overlay.dart';
import '../screens/reader_screen.dart'
    show
        kBoundaryBottom,
        kContentPaddingH,
        kReaderCardDepthBorderWidth,
        kReaderDialogueTextInset,
        resolveReaderChunkTextAlign,
        resolveReaderLayoutMetrics,
        resolveReaderPublisherPadding;
import '../utils/text_span_utils.dart';

/// Instagram-like dark pink color for bookmarks.
const Color kBookmarkPink = Color(0xFFE1306C);

class ReadingCard extends StatefulWidget {
  final BookChunk chunk;
  final ReadingSettings settings;
  final SpeedReadController? speedReadController;
  final Function(String url)? onLinkTap;
  final Bookmark? bookmark;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTripleTap;
  final VoidCallback? onBookmarkLongPress;
  final VoidCallback? onImageTap;
  final String? chapterTitle;
  final String? chapterPageLabel;
  final double? chapterProgress;
  final double depthLiftProgress;
  final bool showStackLayers;
  final ValueChanged<bool>? onInteractionBlockedChanged;

  /// Highlights that apply to this chunk (matched by original chunk index).
  final List<Highlight> highlights;

  /// Map of character name → highlight color, built from ALL character highlights
  /// across the entire book. Used to style every occurrence of each name.
  final Map<String, Color> characterNames;

  /// The colors available to pick from for highlights.
  final List<Color> highlightPalette;

  /// The default color for new highlights (syncs across pages).
  final Color defaultHighlightColor;

  /// Called when the user selects a new color for future highlights.
  final ValueChanged<Color>? onDefaultHighlightColorChanged;

  /// Called when the user creates a new highlight via text selection.
  final void Function(
    int startOffset,
    int endOffset,
    String text,
    Color color,
    HighlightType type,
    String? note,
  )?
  onHighlightCreated;

  /// Called when a new note highlight should be created from frozen
  /// original mapped ranges captured before the note sheet opens.
  final Future<void> Function(
    List<MappedTextRange> mappedRanges,
    String text,
    Color color,
    String note,
  )?
  onMappedNoteCreated;

  /// Called when the user long-presses an existing highlight to change color.
  final void Function(Highlight highlight, Color newColor)?
  onHighlightColorChange;

  /// Adds a custom color to the saved palette.
  final Future<List<Color>> Function(Color color)? onAddCustomColor;

  /// Removes a saved custom color from the palette.
  final Future<List<Color>> Function(Color color)? onRemoveCustomColor;

  /// Restores the saved palette back to the system colors.
  final Future<List<Color>> Function()? onResetHighlightPalette;

  /// Called when an existing highlight should be removed entirely
  final void Function(String id)? onHighlightDeleted;

  /// Called when a note is added/updated on an existing highlight
  final void Function(String highlightId, String note)? onNoteUpdated;

  /// Called when a note is removed from an existing highlight
  final void Function(String highlightId)? onNoteRemoved;

  /// Called when a tap occurs outside the active highlight or text selection
  final void Function(Offset? globalPosition)? onTapOutside;

  /// Called when user taps the Dictionary button on a selected word
  final void Function(
    String word, {
    int? originalChunkIndex,
    int? originalStartOffset,
    int? originalEndOffset,
    String? contextSentence,
  })?
  onDictionaryLookup;

  /// Called when user shares the active text selection as a quote card.
  final void Function(int startOffset, int endOffset, String text)?
  onQuoteShareRequested;

  /// Used to clear highlight menus when the page changes
  final bool isActivePage;

  const ReadingCard({
    super.key,
    this.isActivePage = true,
    required this.chunk,
    required this.settings,
    this.speedReadController,
    this.onLinkTap,
    this.bookmark,
    this.onDoubleTap,
    this.onTripleTap,
    this.onBookmarkLongPress,
    this.onImageTap,
    this.chapterTitle,
    this.chapterPageLabel,
    this.chapterProgress,
    this.depthLiftProgress = 0,
    this.showStackLayers = true,
    this.onInteractionBlockedChanged,
    this.highlights = const [],
    this.characterNames = const {},
    this.highlightPalette = kHighlightColors,
    this.defaultHighlightColor = const Color(0xFFEF5350),
    this.onDefaultHighlightColorChanged,
    this.onHighlightCreated,
    this.onMappedNoteCreated,
    this.onHighlightColorChange,
    this.onAddCustomColor,
    this.onRemoveCustomColor,
    this.onResetHighlightPalette,
    this.onHighlightDeleted,
    this.onNoteUpdated,
    this.onNoteRemoved,
    this.onTapOutside,
    this.onDictionaryLookup,
    this.onQuoteShareRequested,
  });

  @override
  State<ReadingCard> createState() => _ReadingCardState();
}

class _ReadingCardState extends State<ReadingCard>
    with TickerProviderStateMixin {
  static const Duration _selectionMenuDelay = Duration(milliseconds: 450);

  // ── Pop animation (Instagram style) ──
  late final AnimationController _popController;
  late final Animation<double> _popScale;
  late final Animation<double> _popOpacity;

  // ── Corner bookmark bounce ──
  late final AnimationController _cornerController;
  late final Animation<double> _cornerScale;

  // ── Speed read word crossfade ──
  late final AnimationController _speedReadStyleController;
  int? _lastObservedSpeedReadWordIndex;
  int? _previousSpeedReadWordIndex;

  bool _showPopIcon = false;

  // ── Selection state ──
  int? _selectionStart;
  int? _selectionEnd;
  bool _hasActiveSelection = false;
  bool _showSelectionMenu = false;
  late Color _selectedColor;

  int _consecutiveTaps = 0;
  Timer? _tapTimer;
  Timer? _selectionMenuTimer;

  // ── Editing Existing Highlight ──
  Highlight? _tappedHighlight;
  final bool _justTappedHighlight =
      false; // guard: prevent onTap from clearing immediately

  // ── Cached sorted highlights (avoid re-sorting on every build) ──
  List<Highlight>? _sortedHighlights;
  _PendingNoteDraft? _pendingNoteDraft;

  Offset? _lastPointerPosition;
  Offset? _lastPointerDownPosition;
  bool _isColorPickerOpen = false;
  bool? _lastReportedInteractionBlocked;
  OverlayEntry? _floatingMenuOverlay;
  Color? _lastBookmarkColor;
  bool _speedReadTapHandled = false;
  bool _selectionChangedDuringPointer = false;

  @override
  void initState() {
    super.initState();
    _selectedColor = Color(highlightColorValue(widget.defaultHighlightColor));

    // Pop animation: quick scale-up then fade out
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _popScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.3,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.3,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
    ]).animate(_popController);

    _popOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_popController);

    _popController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _showPopIcon = false);
        _popController.reset();
      }
    });

    // Corner bookmark bounce
    _cornerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _cornerScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.4,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.4,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_cornerController);

    _speedReadStyleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      value: 1.0,
    );
    _attachSpeedReadController(widget.speedReadController);
  }

  @override
  void didUpdateWidget(covariant ReadingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speedReadController != widget.speedReadController) {
      _detachSpeedReadController(oldWidget.speedReadController);
      _lastObservedSpeedReadWordIndex =
          widget.speedReadController?.currentWordIndex;
      _previousSpeedReadWordIndex = null;
      _speedReadStyleController.value = 1.0;
      _attachSpeedReadController(widget.speedReadController);
    }
    // Invalidate sorted highlight cache if highlights changed
    if (widget.highlights != oldWidget.highlights ||
        widget.chunk != oldWidget.chunk) {
      _sortedHighlights = null;
    }
    // Bounce the corner icon when bookmark is added
    if (widget.bookmark != null && oldWidget.bookmark == null) {
      _cornerController.forward(from: 0);
    }

    if (!isSameHighlightColor(
          widget.defaultHighlightColor,
          oldWidget.defaultHighlightColor,
        ) &&
        !_hasActiveSelection &&
        _tappedHighlight == null) {
      _selectedColor = Color(highlightColorValue(widget.defaultHighlightColor));
    }

    // Discard active highlight menus if we scroll away from this page
    if (oldWidget.isActivePage && !widget.isActivePage) {
      if (_hasActiveSelection || _tappedHighlight != null) {
        _cancelSelectionMenuTimer();
        _removeFloatingMenuOverlay();
        setState(() {
          _hasActiveSelection = false;
          _showSelectionMenu = false;
          _tappedHighlight = null;
          _selectionStart = null;
          _selectionEnd = null;
          _pendingNoteDraft = null;
        });
        // We defer unfocusing just slightly to ensure it doesn't conflict with page swiping
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) FocusScope.of(context).unfocus();
        });
        _notifyInteractionBlockedChanged();
      }
    }
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    _selectionMenuTimer?.cancel();
    _removeFloatingMenuOverlay();
    _popController.dispose();
    _cornerController.dispose();
    _detachSpeedReadController(widget.speedReadController);
    _speedReadStyleController.dispose();
    super.dispose();
  }

  void _attachSpeedReadController(SpeedReadController? controller) {
    _lastObservedSpeedReadWordIndex = controller?.currentWordIndex;
    controller?.addListener(_onSpeedReadWordChanged);
  }

  void _detachSpeedReadController(SpeedReadController? controller) {
    controller?.removeListener(_onSpeedReadWordChanged);
  }

  void _onSpeedReadWordChanged() {
    final controller = widget.speedReadController;
    if (controller == null || !controller.isActive) {
      _lastObservedSpeedReadWordIndex = controller?.currentWordIndex;
      _previousSpeedReadWordIndex = null;
      _speedReadStyleController.value = 1.0;
      return;
    }

    final currentIndex = controller.currentWordIndex;
    if (_lastObservedSpeedReadWordIndex == currentIndex) return;

    _previousSpeedReadWordIndex = _lastObservedSpeedReadWordIndex;
    _lastObservedSpeedReadWordIndex = currentIndex;
    _speedReadStyleController.duration = _speedReadTransitionDuration(
      controller,
    );
    _speedReadStyleController.forward(from: 0);
  }

  Duration _speedReadTransitionDuration(SpeedReadController controller) {
    final baseMs = (60000 / controller.wordsPerMinute).round();
    var transitionMs = (baseMs * 0.55).round().clamp(60, 140).toInt();
    if (transitionMs > baseMs) transitionMs = baseMs;
    return Duration(milliseconds: transitionMs);
  }

  void _handleBookmarkAction() {
    if (widget.bookmark != null) {
      _lastBookmarkColor = widget.bookmark!.color;
    }

    widget.onDoubleTap?.call();
    // Show the pop icon animation
    setState(() => _showPopIcon = true);
    _popController.forward(from: 0);
  }

  Highlight? _findRelatedAnnotation(Highlight source, HighlightType type) {
    for (final annotation in widget.highlights) {
      if (annotation.id == source.id) continue;
      if (annotation.type != type) continue;
      if (annotation.originalChunkIndex != source.originalChunkIndex) continue;
      if (annotation.startOffset != source.startOffset ||
          annotation.endOffset != source.endOffset) {
        continue;
      }
      return annotation;
    }
    return null;
  }

  Highlight? _findSelectionSourceAnnotation() {
    final start = _selectionStart;
    final end = _selectionEnd;
    final text = widget.chunk.text ?? '';
    if (start == null || end == null || text.isEmpty) return null;

    final resolvedStart = start.clamp(0, text.length);
    final resolvedEnd = end.clamp(0, text.length);
    if (resolvedStart >= resolvedEnd) return null;

    final resolvedHighlights = _resolvedHighlightsForDisplay(text);

    for (final highlight in resolvedHighlights) {
      if (highlight.isNote) continue;
      if (highlight.startOffset == resolvedStart &&
          highlight.endOffset == resolvedEnd) {
        return highlight;
      }
    }

    return null;
  }

  _PendingNoteDraft? _capturePendingNoteDraft() {
    final start = _selectionStart;
    final end = _selectionEnd;
    final text = widget.chunk.text ?? '';
    if (start == null || end == null || text.isEmpty) return null;

    final resolvedStart = start.clamp(0, text.length);
    final resolvedEnd = end.clamp(0, text.length);
    if (resolvedStart >= resolvedEnd) return null;
    final mappedRanges = widget.chunk.mapDisplayRangeToOriginal(
      resolvedStart,
      resolvedEnd,
    );
    if (mappedRanges.isEmpty) return null;

    return _PendingNoteDraft(
      startOffset: resolvedStart,
      endOffset: resolvedEnd,
      text: text.substring(resolvedStart, resolvedEnd),
      color: _selectedColor,
      mappedRanges: mappedRanges,
    );
  }

  _SelectedTextRange? _selectedTextRange() {
    final start = _selectionStart;
    final end = _selectionEnd;
    final text = widget.chunk.text ?? '';
    if (start == null || end == null || text.isEmpty) return null;

    final resolvedStart = start.clamp(0, text.length);
    final resolvedEnd = end.clamp(0, text.length);
    if (resolvedStart >= resolvedEnd) return null;

    return _SelectedTextRange(
      startOffset: resolvedStart,
      endOffset: resolvedEnd,
      text: text.substring(resolvedStart, resolvedEnd),
    );
  }

  String? _contextPreviewForRange(int startOffset, int endOffset) {
    final text = widget.chunk.text ?? '';
    if (text.isEmpty) return null;
    final start = (startOffset - 80).clamp(0, text.length);
    final end = (endOffset + 80).clamp(0, text.length);
    if (start >= end) return null;
    final before = start > 0 ? '…' : '';
    final after = end < text.length ? '…' : '';
    final snippet = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
    return '$before$snippet$after';
  }

  _ActiveSelectionRange? _activeSelectionRangeForText(
    String text, {
    required int startOffset,
  }) {
    if (!_hasActiveSelection) return null;
    final selectionStart = _selectionStart;
    final selectionEnd = _selectionEnd;
    if (selectionStart == null || selectionEnd == null) return null;

    final textStart = startOffset;
    final textEnd = startOffset + text.length;
    final start = selectionStart.clamp(textStart, textEnd);
    final end = selectionEnd.clamp(textStart, textEnd);
    if (start >= end) return null;

    return _ActiveSelectionRange(
      start: start - startOffset,
      end: end - startOffset,
    );
  }

  Color _activeSelectionColor() {
    final base = widget.settings.selectionColor;
    return base.withValues(alpha: base.a < 0.38 ? 0.5 : base.a);
  }

  void _cancelSelectionMenuTimer() {
    _selectionMenuTimer?.cancel();
    _selectionMenuTimer = null;
  }

  bool get _isInteractionBlocked =>
      _hasActiveSelection ||
      _showSelectionMenu ||
      _tappedHighlight != null ||
      _isColorPickerOpen;

  bool get _shouldShowFloatingMenu =>
      mounted &&
      widget.isActivePage &&
      !_isColorPickerOpen &&
      (_showSelectionMenu || _tappedHighlight != null);

  void _notifyInteractionBlockedChanged() {
    final blocked = _isInteractionBlocked;
    if (_lastReportedInteractionBlocked == blocked) return;
    _lastReportedInteractionBlocked = blocked;
    widget.onInteractionBlockedChanged?.call(blocked);
  }

  void _syncTransientUiAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyInteractionBlockedChanged();
      _syncFloatingMenuOverlay();
    });
  }

  void _syncFloatingMenuOverlay() {
    if (!_shouldShowFloatingMenu) {
      _removeFloatingMenuOverlay();
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final existing = _floatingMenuOverlay;
    if (existing != null) {
      existing.markNeedsBuild();
      return;
    }

    // Keep the highlight toolbar above the real card deck. Rendering it in
    // the root overlay prevents card/deck ClipRect and ClipRRect boundaries
    // from cutting off the menu near the card edges.
    _floatingMenuOverlay = OverlayEntry(builder: (_) => _buildFloatingMenu());
    overlay.insert(_floatingMenuOverlay!);
  }

  void _removeFloatingMenuOverlay() {
    _floatingMenuOverlay?.remove();
    _floatingMenuOverlay = null;
  }

  void _scheduleSelectionMenu() {
    _cancelSelectionMenuTimer();
    _selectionMenuTimer = Timer(_selectionMenuDelay, () {
      if (!mounted || _isColorPickerOpen) return;

      final hasStableSelection =
          _hasActiveSelection &&
          _selectionStart != null &&
          _selectionEnd != null &&
          _selectionStart != _selectionEnd &&
          _tappedHighlight == null &&
          _selectedTextRange() != null;
      if (!hasStableSelection) return;

      setState(() {
        _showSelectionMenu = true;
      });
      _notifyInteractionBlockedChanged();
    });
  }

  void _shareSelectedQuote(_SelectedTextRange? selection) {
    if (selection == null) return;
    widget.onQuoteShareRequested?.call(
      selection.startOffset,
      selection.endOffset,
      selection.text,
    );
    _cancelSelectionMenuTimer();
    setState(() {
      _hasActiveSelection = false;
      _showSelectionMenu = false;
      _selectionStart = null;
      _selectionEnd = null;
      _tappedHighlight = null;
    });
    _notifyInteractionBlockedChanged();
    FocusScope.of(context).unfocus();
  }

  void _copyActiveText({required bool isEditing}) {
    final textToCopy = isEditing
        ? (_tappedHighlight?.text ?? '')
        : (_selectedTextRange()?.text ?? '');
    if (textToCopy.isEmpty) return;

    Clipboard.setData(ClipboardData(text: textToCopy));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: widget.settings.readerTextColor,
        action: SnackBarAction(
          label: 'OK',
          textColor: widget.settings.backgroundColor,
          onPressed: () {},
        ),
      ),
    );
    _cancelSelectionMenuTimer();
    setState(() {
      _hasActiveSelection = false;
      _showSelectionMenu = false;
      _selectionStart = null;
      _selectionEnd = null;
      _tappedHighlight = null;
    });
    _notifyInteractionBlockedChanged();
    FocusScope.of(context).unfocus();
  }

  void _handleRenderedAnnotationTap(Highlight highlight) {
    if (_isColorPickerOpen) return;

    final linkedNote = highlight.hasNote || highlight.isNote
        ? highlight
        : _findRelatedAnnotation(highlight, HighlightType.note);
    if (linkedNote != null) {
      _cancelSelectionMenuTimer();
      setState(() {
        _hasActiveSelection = false;
        _showSelectionMenu = false;
        _selectionStart = null;
        _selectionEnd = null;
        _tappedHighlight = null;
      });
      _notifyInteractionBlockedChanged();
      _showNotePreview(linkedNote, sourceAnnotation: highlight);
      return;
    }

    _cancelSelectionMenuTimer();
    setState(() {
      _hasActiveSelection = false;
      _showSelectionMenu = false;
      _selectionStart = null;
      _selectionEnd = null;
      _tappedHighlight = highlight;
    });
    _notifyInteractionBlockedChanged();
  }

  List<Highlight> _resolvedHighlightsForDisplay(String text) {
    final cached = _sortedHighlights;
    if (cached != null) return cached;

    final resolved = <Highlight>[];
    for (final highlight in widget.highlights) {
      final mappedRanges = widget.chunk.mapOriginalRangeToDisplay(
        highlight.originalChunkIndex,
        highlight.startOffset,
        highlight.endOffset,
      );

      for (final range in mappedRanges) {
        resolved.add(
          Highlight(
            id: highlight.id,
            originalChunkIndex: highlight.originalChunkIndex,
            startOffset: range.displayStartOffset,
            endOffset: range.displayEndOffset,
            text: text.substring(
              range.displayStartOffset,
              range.displayEndOffset,
            ),
            colorIndex: highlight.colorIndex,
            colorValue: highlight.colorValue,
            type: highlight.type,
            createdAt: highlight.createdAt,
            note: highlight.note,
          ),
        );
      }
    }

    resolved.sort((a, b) => a.startOffset.compareTo(b.startOffset));
    _sortedHighlights = resolved;
    return resolved;
  }

  List<Highlight> _resolvedHighlightsForDisplayRange(
    String text,
    int startOffset,
  ) {
    final fullText = widget.chunk.text ?? text;
    final endOffset = startOffset + text.length;
    final resolved = _resolvedHighlightsForDisplay(fullText);
    final ranged = <Highlight>[];

    for (final highlight in resolved) {
      final start = highlight.startOffset.clamp(startOffset, endOffset);
      final end = highlight.endOffset.clamp(startOffset, endOffset);
      if (start >= end) continue;

      ranged.add(
        Highlight(
          id: highlight.id,
          originalChunkIndex: highlight.originalChunkIndex,
          startOffset: start - startOffset,
          endOffset: end - startOffset,
          text: text.substring(start - startOffset, end - startOffset),
          colorIndex: highlight.colorIndex,
          colorValue: highlight.colorValue,
          type: highlight.type,
          createdAt: highlight.createdAt,
          note: highlight.note,
        ),
      );
    }

    return ranged;
  }

  /// Handle selection change from SelectableText.
  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    _onSelectionChangedFromOffset(selection, cause, 0);
  }

  void _onSelectionChangedFromOffset(
    TextSelection selection,
    SelectionChangedCause? cause,
    int startOffset,
  ) {
    if (_isColorPickerOpen) return;

    if (selection.isCollapsed) {
      // Selection cleared
      if (_hasActiveSelection) {
        _cancelSelectionMenuTimer();
        setState(() {
          _hasActiveSelection = false;
          _showSelectionMenu = false;
          _selectionStart = null;
          _selectionEnd = null;
        });
        _notifyInteractionBlockedChanged();
        if (_tappedHighlight == null &&
            widget.speedReadController?.isActive == true) {
          widget.speedReadController!.resume();
        }
      }
      return;
    }

    _cancelSelectionMenuTimer();
    _selectionChangedDuringPointer = true;
    setState(() {
      _selectionStart = startOffset + selection.start;
      _selectionEnd = startOffset + selection.end;
      _hasActiveSelection = true;
      _showSelectionMenu = false;
      _tappedHighlight =
          null; // hide existing highlight editor if new selection starts
    });
    _notifyInteractionBlockedChanged();
    _scheduleSelectionMenu();

    if (widget.speedReadController?.isActive == true) {
      widget.speedReadController!.pause();
    }
  }

  /// Build the floating UI. If a stable selection is visible, it builds the "Save" creator.
  /// If [_tappedHighlight] is not null, it behaves as the editor/deleter.
  Widget _buildFloatingMenu() {
    final isEditing = _tappedHighlight != null;
    final linkedNote = isEditing
        ? (_tappedHighlight!.hasNote
              ? _tappedHighlight
              : _findRelatedAnnotation(_tappedHighlight!, HighlightType.note))
        : null;
    final linkedCharacter = isEditing
        ? (_tappedHighlight!.isCharacter
              ? _tappedHighlight
              : _findRelatedAnnotation(
                  _tappedHighlight!,
                  HighlightType.character,
                ))
        : null;
    final activeColor = isEditing ? _tappedHighlight!.color : _selectedColor;
    final isCharacterActive = linkedCharacter != null;
    final selectedTextRange = isEditing ? null : _selectedTextRange();
    final canShareSelection =
        widget.onQuoteShareRequested != null && selectedTextRange != null;
    final settings = widget.settings;
    final menuColor = settings.menuColor;
    final textColor = settings.readerTextColor;
    final mutedColor = settings.readerMutedColor;
    final backgroundColor = settings.backgroundColor;

    Widget divider() => Container(
      width: 1,
      height: 24,
      color: mutedColor.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );

    double? top;
    double? bottom;

    if (_lastPointerPosition != null) {
      final dy = _lastPointerPosition!.dy;
      final height = MediaQuery.of(context).size.height;
      if (dy > height / 2) {
        bottom = height - dy + 72;
      } else {
        top = dy + 72;
      }
    } else {
      bottom = MediaQuery.viewPaddingOf(context).bottom + kBoundaryBottom + 8;
    }

    return Positioned(
      bottom: bottom,
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 24,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: menuColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isEditing) ...[
                    IconButton(
                      icon: const Icon(Icons.menu_book_rounded, size: 24),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        final selection = _selectedTextRange();
                        if (selection != null) {
                          final mappedRanges = widget.chunk
                              .mapDisplayRangeToOriginal(
                                selection.startOffset,
                                selection.endOffset,
                              );
                          final firstRange = mappedRanges.firstOrNull;
                          widget.onDictionaryLookup?.call(
                            selection.text,
                            originalChunkIndex: firstRange?.originalChunkIndex,
                            originalStartOffset:
                                firstRange?.originalStartOffset,
                            originalEndOffset: firstRange?.originalEndOffset,
                            contextSentence: _contextPreviewForRange(
                              selection.startOffset,
                              selection.endOffset,
                            ),
                          );
                          _cancelSelectionMenuTimer();
                          setState(() {
                            _hasActiveSelection = false;
                            _showSelectionMenu = false;
                            _selectionStart = null;
                            _selectionEnd = null;
                          });
                        }
                      },
                      tooltip: 'Dictionary',
                    ),
                    divider(),
                  ],
                  GestureDetector(
                    onLongPress: () {
                      if (isEditing && linkedNote != null) {
                        widget.onNoteRemoved?.call(linkedNote.id);
                        setState(() {
                          if (_tappedHighlight?.id == linkedNote.id) {
                            _tappedHighlight = null;
                          }
                        });
                      }
                    },
                    child: IconButton(
                      icon: Icon(
                        isEditing && linkedNote != null
                            ? Icons.edit_note_rounded
                            : Icons.edit_rounded,
                        color: isEditing && linkedNote != null
                            ? activeColor
                            : textColor,
                        size: 24,
                      ),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        final sourceAnnotation = isEditing
                            ? _tappedHighlight
                            : _findSelectionSourceAnnotation();
                        final pendingDraft =
                            !isEditing && sourceAnnotation == null
                            ? _capturePendingNoteDraft()
                            : null;
                        if (!isEditing &&
                            sourceAnnotation == null &&
                            pendingDraft == null) {
                          return;
                        }
                        if (!isEditing) {
                          _cancelSelectionMenuTimer();
                          setState(() {
                            _pendingNoteDraft = pendingDraft;
                            _hasActiveSelection = false;
                            _showSelectionMenu = false;
                            _selectionStart = null;
                            _selectionEnd = null;
                            _tappedHighlight = null;
                          });
                        } else {
                          _cancelSelectionMenuTimer();
                          setState(() {
                            _showSelectionMenu = false;
                            _tappedHighlight = null;
                          });
                        }
                        _notifyInteractionBlockedChanged();
                        _showNoteEditor(
                          existingNoteAnnotation: linkedNote,
                          sourceAnnotation: sourceAnnotation,
                          pendingDraft: pendingDraft,
                        );
                      },
                      tooltip: isEditing && linkedNote != null
                          ? 'Edit Note (Long press to remove)'
                          : 'Add Note',
                    ),
                  ),
                  divider(),
                  IconButton(
                    icon: Icon(
                      Icons.person_rounded,
                      color: isCharacterActive ? activeColor : textColor,
                      size: 24,
                    ),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      if (isEditing) {
                        if (linkedCharacter != null) {
                          widget.onHighlightDeleted?.call(linkedCharacter.id);
                          setState(() {
                            if (_tappedHighlight?.id == linkedCharacter.id) {
                              _tappedHighlight = null;
                            }
                          });
                        } else {
                          widget.onHighlightCreated?.call(
                            _tappedHighlight!.startOffset,
                            _tappedHighlight!.endOffset,
                            _tappedHighlight!.text,
                            _tappedHighlight!.color,
                            HighlightType.character,
                            null,
                          );
                        }
                      } else {
                        final selection = _selectedTextRange();
                        if (selection != null) {
                          widget.onHighlightCreated?.call(
                            selection.startOffset,
                            selection.endOffset,
                            selection.text,
                            _selectedColor,
                            HighlightType.character,
                            null,
                          );
                        }
                        _cancelSelectionMenuTimer();
                        setState(() {
                          _hasActiveSelection = false;
                          _showSelectionMenu = false;
                          _selectionStart = null;
                          _selectionEnd = null;
                        });
                        FocusScope.of(context).unfocus();
                      }
                    },
                    tooltip: 'Character Highlight',
                  ),
                  divider(),
                  GestureDetector(
                    onTap: () {
                      _showColorPicker(context, isEditing);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: activeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: textColor, width: 2.0),
                      ),
                      child: Icon(
                        Icons.arrow_drop_down,
                        color: backgroundColor,
                        size: 20,
                      ),
                    ),
                  ),
                  divider(),
                  PopupMenuButton<_HighlightMoreAction>(
                    tooltip: 'More',
                    color: menuColor,
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: textColor,
                      size: 24,
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _HighlightMoreAction.copy,
                        child: Row(
                          children: [
                            Icon(
                              Icons.copy_rounded,
                              color: textColor,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text('Copy', style: TextStyle(color: textColor)),
                          ],
                        ),
                      ),
                      if (canShareSelection)
                        PopupMenuItem(
                          value: _HighlightMoreAction.share,
                          child: Row(
                            children: [
                              Icon(
                                Icons.ios_share_rounded,
                                color: textColor,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text('Share', style: TextStyle(color: textColor)),
                            ],
                          ),
                        ),
                    ],
                    onSelected: (action) {
                      switch (action) {
                        case _HighlightMoreAction.copy:
                          _copyActiveText(isEditing: isEditing);
                          break;
                        case _HighlightMoreAction.share:
                          _shareSelectedQuote(selectedTextRange);
                          break;
                      }
                    },
                  ),
                  divider(),
                  InkWell(
                    onTap: () {
                      if (isEditing) {
                        widget.onHighlightDeleted?.call(_tappedHighlight!.id);
                        setState(() {
                          _tappedHighlight = null;
                        });
                      } else {
                        final selection = _selectedTextRange();
                        if (selection != null) {
                          widget.onHighlightCreated?.call(
                            selection.startOffset,
                            selection.endOffset,
                            selection.text,
                            _selectedColor,
                            HighlightType.highlight,
                            null,
                          );
                        }
                        _cancelSelectionMenuTimer();
                        setState(() {
                          _hasActiveSelection = false;
                          _showSelectionMenu = false;
                          _selectionStart = null;
                          _selectionEnd = null;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isEditing
                            ? Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.15)
                            : activeColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isEditing ? Icons.close_rounded : Icons.check_rounded,
                        color: isEditing
                            ? Theme.of(context).colorScheme.error
                            : activeColor,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context, bool isEditing) {
    _isColorPickerOpen = true;
    _notifyInteractionBlockedChanged();
    _syncFloatingMenuOverlay();
    showHighlightPaletteSheet(
      context,
      title: isEditing ? 'Edit highlight color' : 'Choose highlight color',
      palette: widget.highlightPalette,
      selectedColor: isEditing ? _tappedHighlight!.color : _selectedColor,
      readingSettings: widget.settings,
      onColorSelected: (color) {
        if (isEditing) {
          widget.onHighlightColorChange?.call(_tappedHighlight!, color);
          setState(() {
            _tappedHighlight = _tappedHighlight!.copyWith(
              colorIndex:
                  defaultHighlightColorIndex(color) ??
                  _tappedHighlight!.colorIndex,
              colorValue: highlightColorValue(color),
            );
          });
        } else {
          setState(() {
            _selectedColor = Color(highlightColorValue(color));
          });
          widget.onDefaultHighlightColorChanged?.call(color);
        }
      },
      onAddCustomColor:
          widget.onAddCustomColor ?? ((_) async => widget.highlightPalette),
      onRemoveCustomColor:
          widget.onRemoveCustomColor ?? ((_) async => widget.highlightPalette),
      onResetPalette:
          widget.onResetHighlightPalette ??
          (() async => widget.highlightPalette),
    ).then((_) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        _isColorPickerOpen = false;
        _notifyInteractionBlockedChanged();
        _syncFloatingMenuOverlay();
      });
    });
  }

  /// Apply inline styles (bold/italic) to a TextStyle for a given position.
  TextStyle _applyInlineStyles(TextStyle base, int position, int length) {
    final styles = widget.chunk.inlineStyles;
    if (styles == null || styles.isEmpty) return base;

    bool isBold = false;
    bool isItalic = false;

    for (final s in styles) {
      // Check if any part of this range overlaps with the style
      if (s.start < position + length && s.end > position) {
        switch (s.type) {
          case InlineStyleType.bold:
            isBold = true;
            break;
          case InlineStyleType.italic:
            isItalic = true;
            break;
          case InlineStyleType.boldItalic:
            isBold = true;
            isItalic = true;
            break;
        }
      }
    }

    if (!isBold && !isItalic) return base;
    return base.copyWith(
      fontWeight: isBold ? FontWeight.w700 : null,
      fontStyle: isItalic ? FontStyle.italic : null,
    );
  }

  /// Create a TextSpan for a segment of text, applying inline styles.
  TextSpan _styledTextSpan(
    String text,
    int startInChunk,
    TextStyle baseStyle, {
    Color? backgroundColor,
    GestureRecognizer? recognizer,
  }) {
    final styles = widget.chunk.inlineStyles;
    if (styles == null || styles.isEmpty) {
      final style = backgroundColor != null
          ? baseStyle.copyWith(backgroundColor: backgroundColor)
          : baseStyle;
      return TextSpanUtils.buildSpacedTextSpan(
        text: text,
        baseStyle: style,
        paragraphSpacingMultiplier: 1.0,
        recognizer: recognizer,
      );
    }

    // Split this segment into sub-segments at inline style boundaries
    final endInChunk = startInChunk + text.length;

    // Collect all style boundary points within this range
    final boundaries = <int>{startInChunk, endInChunk};
    for (final s in styles) {
      if (s.start > startInChunk && s.start < endInChunk) {
        boundaries.add(s.start);
      }
      if (s.end > startInChunk && s.end < endInChunk) {
        boundaries.add(s.end);
      }
    }

    final sortedBounds = boundaries.toList()..sort();
    if (sortedBounds.length <= 2) {
      // No sub-segmentation needed, just apply combined style
      final styled = _applyInlineStyles(baseStyle, startInChunk, text.length);
      final style = backgroundColor != null
          ? styled.copyWith(backgroundColor: backgroundColor)
          : styled;
      return TextSpanUtils.buildSpacedTextSpan(
        text: text,
        baseStyle: style,
        paragraphSpacingMultiplier: 1.0,
        recognizer: recognizer,
      );
    }

    // Build sub-spans
    final subSpans = <TextSpan>[];
    for (int i = 0; i < sortedBounds.length - 1; i++) {
      final segStart = sortedBounds[i];
      final segEnd = sortedBounds[i + 1];
      final segText = text.substring(
        segStart - startInChunk,
        segEnd - startInChunk,
      );
      final styled = _applyInlineStyles(baseStyle, segStart, segEnd - segStart);
      final style = backgroundColor != null
          ? styled.copyWith(backgroundColor: backgroundColor)
          : styled;
      subSpans.add(
        TextSpanUtils.buildSpacedTextSpan(
          text: segText,
          baseStyle: style,
          paragraphSpacingMultiplier: 1.0,
          recognizer: recognizer,
        ),
      );
    }

    return TextSpan(children: subSpans);
  }

  /// Show footnote content in a bottom sheet.
  void _showFootnotePopup(FootnoteRef footnote) {
    final settings = widget.settings;
    showModalBottomSheet(
      context: context,
      backgroundColor: settings.menuColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Footnote ${footnote.label}',
              style: TextStyle(
                color: settings.readerTextColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              footnote.content,
              style: TextStyle(
                color: settings.readerTextColor.withValues(alpha: 0.85),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Build TextSpan with highlights, character name styling, inline styles, and footnotes.
  ///
  /// Background highlights and character name styling are treated as TWO
  /// independent layers that can coexist on the same text. A sweep-line
  /// algorithm splits text at every boundary point and applies:
  ///   - Background highlight color (inline backgroundColor)
  ///   - Character name foreground color + simulated bold (text shadows)
  ///   - Both, if the text is inside a highlight AND is a character name.
  TextSpan _buildHighlightedTextSpan(
    String text,
    TextStyle baseStyle,
    TextAlign textAlign, {
    int startOffset = 0,
  }) {
    final fullChunkText = widget.chunk.text;
    final isFullDisplayText =
        startOffset == 0 &&
        (fullChunkText == null || fullChunkText.length == text.length);
    final resolvedHighlights = isFullDisplayText
        ? _resolvedHighlightsForDisplay(text)
        : _resolvedHighlightsForDisplayRange(text, startOffset);
    final hasAnnotations = resolvedHighlights.isNotEmpty;
    final hasCharacterNames = widget.characterNames.isNotEmpty;
    final hasStyles =
        widget.chunk.inlineStyles != null &&
        widget.chunk.inlineStyles!.isNotEmpty;
    final hasFootnotes =
        widget.chunk.footnotes != null && widget.chunk.footnotes!.isNotEmpty;

    // Fast path: no highlights, no character names, no styles, no footnotes
    if (!hasAnnotations && !hasCharacterNames && !hasStyles && !hasFootnotes) {
      return TextSpanUtils.buildSpacedTextSpan(
        text: text,
        baseStyle: baseStyle,
        paragraphSpacingMultiplier: 1.0,
      );
    }

    // No highlights and no character names but has styles or footnotes
    if (!hasAnnotations && !hasCharacterNames) {
      return _buildStyledTextSpan(text, baseStyle, startInChunk: startOffset);
    }

    // ── Step 1: Build independent annotation layers ──
    final bgRanges = <_HighlightBgRange>[]; // Background highlights
    final noteRanges = <_NoteDecorationRange>[]; // Notes
    final charRanges = _buildCharacterStyleRanges(
      text,
      startOffset: startOffset,
      resolvedHighlights: resolvedHighlights,
    );

    if (hasAnnotations) {
      for (final hl in resolvedHighlights) {
        final hlStart = hl.startOffset.clamp(0, text.length);
        final hlEnd = hl.endOffset.clamp(0, text.length);
        if (hlStart >= hlEnd) continue;

        switch (hl.type) {
          case HighlightType.highlight:
            if (hl.hasNote) {
              noteRanges.add(
                _NoteDecorationRange(
                  start: hlStart,
                  end: hlEnd,
                  color: hl.color,
                  highlight: hl,
                ),
              );
            } else {
              bgRanges.add(
                _HighlightBgRange(
                  start: hlStart,
                  end: hlEnd,
                  color: hl.color.withValues(alpha: 0.3),
                  highlight: hl,
                ),
              );
            }
            break;
          case HighlightType.character:
            break;
          case HighlightType.note:
            noteRanges.add(
              _NoteDecorationRange(
                start: hlStart,
                end: hlEnd,
                color: hl.color,
                highlight: hl,
              ),
            );
            break;
        }
      }
    }
    final pendingDraft = _pendingNoteDraft;
    if (pendingDraft != null) {
      final endOffset = startOffset + text.length;
      final draftStart = pendingDraft.startOffset.clamp(startOffset, endOffset);
      final draftEnd = pendingDraft.endOffset.clamp(startOffset, endOffset);
      if (draftStart < draftEnd) {
        noteRanges.add(
          _NoteDecorationRange(
            start: draftStart - startOffset,
            end: draftEnd - startOffset,
            color: pendingDraft.color,
            highlight: null,
          ),
        );
      }
    }

    final selectedRange = _activeSelectionRangeForText(
      text,
      startOffset: startOffset,
    );

    // If only bg highlights (no character names, notes, or active selection),
    // use simple highlight path.
    if (selectedRange == null &&
        charRanges.isEmpty &&
        noteRanges.isEmpty &&
        bgRanges.isNotEmpty) {
      return _buildHighlightOnlySpan(
        text,
        baseStyle,
        bgRanges,
        startOffset: startOffset,
      );
    }
    // If only character names (no bg highlights, notes, or active selection),
    // use simple character path.
    if (selectedRange == null &&
        bgRanges.isEmpty &&
        noteRanges.isEmpty &&
        charRanges.isNotEmpty) {
      return _buildCharacterOnlySpan(
        text,
        baseStyle,
        charRanges,
        startOffset: startOffset,
      );
    }

    // ── Step 2: Sweep-line merge — all layers coexist ──
    // Collect all boundary points
    final boundaries = <int>{0, text.length};
    for (final r in bgRanges) {
      boundaries.add(r.start);
      boundaries.add(r.end);
    }
    for (final r in noteRanges) {
      boundaries.add(r.start);
      boundaries.add(r.end);
    }
    for (final r in charRanges) {
      boundaries.add(r.start);
      boundaries.add(r.end);
    }
    if (selectedRange != null) {
      boundaries.add(selectedRange.start);
      boundaries.add(selectedRange.end);
    }
    final sorted = boundaries.toList()..sort();

    final spans = <InlineSpan>[];
    for (int i = 0; i < sorted.length - 1; i++) {
      final segStart = sorted[i];
      final segEnd = sorted[i + 1];
      if (segStart >= segEnd) continue;

      // Find overlapping background highlight (if any)
      final bg = bgRanges.cast<_HighlightBgRange?>().firstWhere(
        (r) => r!.start <= segStart && r.end >= segEnd,
        orElse: () => null,
      );
      final note = noteRanges.cast<_NoteDecorationRange?>().firstWhere(
        (r) => r!.start <= segStart && r.end >= segEnd,
        orElse: () => null,
      );
      // Find overlapping character range (if any)
      final ch = charRanges.cast<_StyledRange?>().firstWhere(
        (r) => r!.start <= segStart && r.end >= segEnd,
        orElse: () => null,
      );

      // Build the style for this segment
      TextStyle segStyle = baseStyle;
      if (ch != null) {
        // Character name: colored text + simulated bold via shadows
        segStyle = segStyle.copyWith(
          color: ch.color,
          shadows: [
            Shadow(color: ch.color, offset: const Offset(0.4, 0)),
            Shadow(color: ch.color, offset: const Offset(-0.2, 0)),
          ],
        );
      }
      if (bg != null) {
        segStyle = segStyle.copyWith(backgroundColor: bg.color);
      }
      if (note != null) {
        segStyle = segStyle.copyWith(
          backgroundColor: note.color,
          color: widget.settings.backgroundColor,
        );
      }
      if (selectedRange != null &&
          selectedRange.start <= segStart &&
          selectedRange.end >= segEnd) {
        segStyle = segStyle.copyWith(
          backgroundColor: _activeSelectionColor(),
          color: widget.settings.readerTextColor,
        );
      }

      spans.add(
        _styledTextSpan(
          text.substring(segStart, segEnd),
          startOffset + segStart,
          segStyle,
          recognizer: _annotationTapRecognizer(
            note?.highlight ?? bg?.highlight ?? ch?.highlight,
          ),
        ),
      );
    }

    return TextSpan(children: spans);
  }

  List<_StyledRange> _buildCharacterStyleRanges(
    String text, {
    int startOffset = 0,
    List<Highlight>? resolvedHighlights,
  }) {
    final charRanges = <_StyledRange>[];
    final highlights =
        resolvedHighlights ??
        (startOffset == 0
            ? _resolvedHighlightsForDisplay(text)
            : _resolvedHighlightsForDisplayRange(text, startOffset));

    for (final hl in highlights) {
      if (!hl.isCharacter) continue;
      final hlStart = hl.startOffset.clamp(0, text.length);
      final hlEnd = hl.endOffset.clamp(0, text.length);
      if (hlStart >= hlEnd) continue;
      charRanges.add(
        _StyledRange(
          start: hlStart,
          end: hlEnd,
          color: hl.color,
          highlight: hl,
        ),
      );
    }

    if (widget.characterNames.isNotEmpty) {
      final textLower = text.toLowerCase();
      for (final entry in widget.characterNames.entries) {
        final nameLower = entry.key.toLowerCase();
        final color = entry.value;
        int searchFrom = 0;
        while (searchFrom < textLower.length) {
          final idx = textLower.indexOf(nameLower, searchFrom);
          if (idx == -1) break;
          final matchEnd = idx + entry.key.length;

          // Word-boundary check
          final charBefore = idx > 0 ? text[idx - 1] : ' ';
          final charAfter = matchEnd < text.length ? text[matchEnd] : ' ';
          final isWordStart = !RegExp(r'[a-zA-Z]').hasMatch(charBefore);
          final isWordEndOrPossessive =
              !RegExp(r'[a-zA-Z]').hasMatch(charAfter) ||
              (charAfter == '\'' || charAfter == '\u2019');

          if (isWordStart && isWordEndOrPossessive) {
            final alreadyCovered = charRanges.any(
              (r) => r.start == idx && r.end == matchEnd,
            );
            if (!alreadyCovered) {
              charRanges.add(
                _StyledRange(
                  start: idx,
                  end: matchEnd,
                  color: color,
                  highlight: null,
                ),
              );
            }
          }
          searchFrom = idx + 1;
        }
      }
    }

    charRanges.sort((a, b) => a.start.compareTo(b.start));
    return charRanges;
  }

  GestureRecognizer? _annotationTapRecognizer(Highlight? highlight) {
    if (highlight == null) return null;
    return TapGestureRecognizer()
      ..onTap = () => _handleRenderedAnnotationTap(highlight);
  }

  TextSpan _buildSpeedReadTextSpan(
    String text,
    TextStyle baseStyle,
    SpeedReadController controller, {
    required bool dimInactive,
    int startOffset = 0,
  }) {
    final textColor = widget.settings.isCustomReaderThemeActive
        ? widget.settings.speedReadActiveWordColor
        : (baseStyle.color ?? widget.settings.readerTextColor);
    final inactiveColor = dimInactive
        ? widget.settings.isCustomReaderThemeActive
              ? widget.settings.speedReadInactiveWordColor
              : textColor.withValues(
                  alpha: widget.settings.isDark ? 0.34 : 0.38,
                )
        : textColor;
    final activeGlowAlpha = widget.settings.isDark ? 0.22 : 0.14;
    final characterRanges = _buildCharacterStyleRanges(
      text,
      startOffset: startOffset,
    );

    final tokens = controller.tokens;
    final activeIndex = controller.currentWordIndex;
    if (tokens.isEmpty) {
      return _styledTextSpan(
        text,
        startOffset,
        baseStyle.copyWith(color: inactiveColor),
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    final easedProgress = Curves.easeOutCubic.transform(
      _speedReadStyleController.value,
    );
    final previousIndex = _previousSpeedReadWordIndex;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      var start = token.startOffset.clamp(0, text.length);
      final end = token.endOffset.clamp(0, text.length);
      if (end <= start) continue;

      if (start < cursor) {
        if (end <= cursor) continue;
        start = cursor;
      }

      if (cursor < start) {
        spans.add(
          _buildSpeedReadSegmentSpan(
            text: text,
            start: cursor,
            end: start,
            startOffset: startOffset,
            baseStyle: baseStyle,
            fallbackColor: inactiveColor,
            characterRanges: characterRanges,
          ),
        );
      }

      final activeAmount = _speedReadActiveAmountForWord(
        wordIndex: i,
        activeIndex: activeIndex,
        previousIndex: previousIndex,
        progress: easedProgress,
        isPageComplete: controller.isPageComplete,
      );
      spans.add(
        _buildSpeedReadSegmentSpan(
          text: text,
          start: start,
          end: end,
          startOffset: startOffset,
          baseStyle: baseStyle,
          fallbackColor: Color.lerp(inactiveColor, textColor, activeAmount)!,
          characterRanges: characterRanges,
          activeAmount: activeAmount,
          activeGlowAlpha: activeGlowAlpha,
          dimInactive: dimInactive,
        ),
      );
      cursor = end;
    }

    if (cursor < text.length) {
      spans.add(
        _buildSpeedReadSegmentSpan(
          text: text,
          start: cursor,
          end: text.length,
          startOffset: startOffset,
          baseStyle: baseStyle,
          fallbackColor: inactiveColor,
          characterRanges: characterRanges,
        ),
      );
    }

    return TextSpan(children: spans);
  }

  TextSpan _buildSpeedReadSegmentSpan({
    required String text,
    required int start,
    required int end,
    required int startOffset,
    required TextStyle baseStyle,
    required Color fallbackColor,
    required List<_StyledRange> characterRanges,
    double activeAmount = 0,
    double activeGlowAlpha = 0,
    bool dimInactive = false,
  }) {
    if (start >= end) {
      return const TextSpan(text: '');
    }

    final boundaries = <int>{start, end};
    for (final range in characterRanges) {
      final overlapStart = range.start.clamp(start, end);
      final overlapEnd = range.end.clamp(start, end);
      if (overlapStart < overlapEnd) {
        boundaries.add(overlapStart);
        boundaries.add(overlapEnd);
      }
    }

    final sorted = boundaries.toList()..sort();
    if (sorted.length <= 2) {
      final characterRange = _characterRangeForSegment(
        characterRanges,
        start,
        end,
      );
      final style = _speedReadTextStyle(
        baseStyle: baseStyle,
        fallbackColor: fallbackColor,
        characterColor: characterRange?.color,
        activeAmount: activeAmount,
        activeGlowAlpha: activeGlowAlpha,
        dimInactive: dimInactive,
      );
      return _styledTextSpan(
        text.substring(start, end),
        startOffset + start,
        style,
      );
    }

    final spans = <InlineSpan>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final segStart = sorted[i];
      final segEnd = sorted[i + 1];
      if (segStart >= segEnd) continue;

      final characterRange = _characterRangeForSegment(
        characterRanges,
        segStart,
        segEnd,
      );
      final style = _speedReadTextStyle(
        baseStyle: baseStyle,
        fallbackColor: fallbackColor,
        characterColor: characterRange?.color,
        activeAmount: activeAmount,
        activeGlowAlpha: activeGlowAlpha,
        dimInactive: dimInactive,
      );
      spans.add(
        _styledTextSpan(
          text.substring(segStart, segEnd),
          startOffset + segStart,
          style,
        ),
      );
    }

    return TextSpan(children: spans);
  }

  _StyledRange? _characterRangeForSegment(
    List<_StyledRange> ranges,
    int start,
    int end,
  ) {
    for (final range in ranges) {
      if (range.start <= start && range.end >= end) return range;
    }
    return null;
  }

  TextStyle _speedReadTextStyle({
    required TextStyle baseStyle,
    required Color fallbackColor,
    required Color? characterColor,
    required double activeAmount,
    required double activeGlowAlpha,
    required bool dimInactive,
  }) {
    final visibleCharacterColor = characterColor == null
        ? null
        : _speedReadReadableCharacterColor(characterColor);
    final color = visibleCharacterColor == null
        ? fallbackColor
        : Color.lerp(
            dimInactive
                ? visibleCharacterColor.withValues(alpha: fallbackColor.a)
                : visibleCharacterColor,
            visibleCharacterColor,
            activeAmount,
          )!;
    final shadows = <Shadow>[
      if (visibleCharacterColor != null)
        Shadow(color: visibleCharacterColor, offset: const Offset(0.28, 0)),
      if (activeAmount > 0)
        Shadow(
          color: widget.settings.readerAccentColor.withValues(
            alpha: activeGlowAlpha * activeAmount,
          ),
          blurRadius: 3,
        ),
    ];

    return baseStyle.copyWith(
      color: color,
      shadows: shadows.isEmpty ? null : shadows,
    );
  }

  Color _speedReadReadableCharacterColor(Color color) {
    final background = widget.settings.backgroundColor;
    if (_contrastRatio(color, background) >= 3) return color;

    final textColor = widget.settings.readerTextColor;
    for (final amount in const [0.25, 0.4, 0.55, 0.7]) {
      final adjusted = Color.lerp(color, textColor, amount)!;
      if (_contrastRatio(adjusted, background) >= 3) return adjusted;
    }

    return textColor;
  }

  double _contrastRatio(Color foreground, Color background) {
    final fg = foreground.computeLuminance();
    final bg = background.computeLuminance();
    final lighter = fg > bg ? fg : bg;
    final darker = fg > bg ? bg : fg;
    return (lighter + 0.05) / (darker + 0.05);
  }

  double _speedReadActiveAmountForWord({
    required int wordIndex,
    required int activeIndex,
    required int? previousIndex,
    required double progress,
    required bool isPageComplete,
  }) {
    if (isPageComplete) return 0;
    if (wordIndex == activeIndex) return progress;
    if (wordIndex == previousIndex) return 1 - progress;
    return 0;
  }

  int? _speedReadTokenIndexAtTap({
    required Offset localPosition,
    required TextPainter textPainter,
  }) {
    final controller = widget.speedReadController;
    if (controller == null ||
        !controller.isActive ||
        !widget.isActivePage ||
        _isInteractionBlocked) {
      return null;
    }

    if (!(Offset.zero & textPainter.size).contains(localPosition)) {
      return null;
    }

    final textLength = textPainter.plainText.length;
    for (var i = 0; i < controller.tokens.length; i++) {
      final token = controller.tokens[i];
      final start = token.coreStartOffset.clamp(0, textLength);
      final end = token.coreEndOffset.clamp(0, textLength);
      if (start >= end) continue;

      final boxes = textPainter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      for (final box in boxes) {
        final rect = box.toRect().inflate(3);
        if (rect.contains(localPosition)) return i;
      }
    }

    return null;
  }

  bool _handleSpeedReadTextTap({
    required Offset localPosition,
    required Offset globalPosition,
    required TextPainter? textPainter,
  }) {
    if (textPainter == null || _selectionChangedDuringPointer) return false;

    final pointerDownPosition = _lastPointerDownPosition;
    if (pointerDownPosition == null ||
        (globalPosition - pointerDownPosition).distance > 12) {
      return false;
    }

    final tokenIndex = _speedReadTokenIndexAtTap(
      localPosition: localPosition,
      textPainter: textPainter,
    );
    if (tokenIndex == null) return false;

    widget.speedReadController!.jumpToWord(tokenIndex);
    return true;
  }

  /// Fast path: only background highlights (no character names).
  TextSpan _buildHighlightOnlySpan(
    String text,
    TextStyle baseStyle,
    List<_HighlightBgRange> bgRanges, {
    int startOffset = 0,
  }) {
    bgRanges.sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final bg in bgRanges) {
      if (bg.start > cursor) {
        spans.add(
          _styledTextSpan(
            text.substring(cursor, bg.start),
            startOffset + cursor,
            baseStyle,
          ),
        );
      }
      spans.add(
        _styledTextSpan(
          text.substring(bg.start, bg.end),
          startOffset + bg.start,
          baseStyle.copyWith(backgroundColor: bg.color),
          recognizer: _annotationTapRecognizer(bg.highlight),
        ),
      );
      cursor = bg.end;
    }
    if (cursor < text.length) {
      spans.add(
        _styledTextSpan(
          text.substring(cursor),
          startOffset + cursor,
          baseStyle,
        ),
      );
    }
    return TextSpan(children: spans);
  }

  /// Fast path: only character names (no background highlights).
  TextSpan _buildCharacterOnlySpan(
    String text,
    TextStyle baseStyle,
    List<_StyledRange> charRanges, {
    int startOffset = 0,
  }) {
    charRanges.sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    int cursor = 0;
    for (final cr in charRanges) {
      if (cr.start < cursor) {
        if (cr.end <= cursor) continue;
        // Overlap — adjust start
        spans.add(
          _styledTextSpan(
            text.substring(cursor, cr.end),
            startOffset + cursor,
            baseStyle.copyWith(
              color: cr.color,
              shadows: [
                Shadow(color: cr.color, offset: const Offset(0.4, 0)),
                Shadow(color: cr.color, offset: const Offset(-0.2, 0)),
              ],
            ),
            recognizer: _annotationTapRecognizer(cr.highlight),
          ),
        );
        cursor = cr.end;
        continue;
      }
      if (cursor < cr.start) {
        spans.add(
          _styledTextSpan(
            text.substring(cursor, cr.start),
            startOffset + cursor,
            baseStyle,
          ),
        );
      }
      spans.add(
        _styledTextSpan(
          text.substring(cr.start, cr.end),
          startOffset + cr.start,
          baseStyle.copyWith(
            color: cr.color,
            shadows: [
              Shadow(color: cr.color, offset: const Offset(0.4, 0)),
              Shadow(color: cr.color, offset: const Offset(-0.2, 0)),
            ],
          ),
          recognizer: _annotationTapRecognizer(cr.highlight),
        ),
      );
      cursor = cr.end;
    }
    if (cursor < text.length) {
      spans.add(
        _styledTextSpan(
          text.substring(cursor),
          startOffset + cursor,
          baseStyle,
        ),
      );
    }
    return TextSpan(children: spans);
  }

  /// Build a TextSpan with inline styles and footnote markers (no highlights).
  TextSpan _buildStyledTextSpan(
    String text,
    TextStyle baseStyle, {
    int startInChunk = 0,
  }) {
    final footnotes = widget.chunk.footnotes;
    if (footnotes == null || footnotes.isEmpty) {
      // Just inline styles, no footnotes — use the optimized path
      return _styledTextSpan(text, startInChunk, baseStyle);
    }

    // Has footnotes: build spans that include tappable footnote markers
    final spans = <InlineSpan>[];
    int cursor = 0;

    // Sort footnotes by position
    final sortedFn = List<FootnoteRef>.from(footnotes)
      ..sort((a, b) => a.position.compareTo(b.position));

    for (final fn in sortedFn) {
      if (fn.position < startInChunk ||
          fn.position >= startInChunk + text.length) {
        continue;
      }
      final fnPos = (fn.position - startInChunk).clamp(0, text.length);

      // Text before this footnote marker
      if (cursor < fnPos) {
        spans.add(
          _styledTextSpan(
            text.substring(cursor, fnPos),
            startInChunk + cursor,
            baseStyle,
          ),
        );
      }

      // Find the marker text (e.g., "[1]")
      final markerText = '[${fn.label}]';
      final markerEnd = (fnPos + markerText.length).clamp(0, text.length);
      final actualMarker = text.substring(fnPos, markerEnd);

      if (actualMarker == markerText) {
        // Render as tappable superscript
        spans.add(
          TextSpan(
            text: actualMarker,
            style: baseStyle.copyWith(
              fontSize: (baseStyle.fontSize ?? 16) * 0.75,
              color: const Color(0xFF6B9FFA),
              fontWeight: FontWeight.w600,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _showFootnotePopup(fn),
          ),
        );
        cursor = markerEnd;
      } else {
        cursor = fnPos;
      }
    }

    // Remaining text
    if (cursor < text.length) {
      spans.add(
        _styledTextSpan(
          text.substring(cursor),
          startInChunk + cursor,
          baseStyle,
        ),
      );
    }

    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    _syncTransientUiAfterBuild();

    final bgColor = widget.settings.cardBackgroundColor;
    final chunk = widget.chunk;

    // ── Milestone cards get a completely different render path ──
    if (chunk.type == BookChunkType.milestone) {
      return _buildMilestoneCard(context, bgColor);
    }

    final textAlign = resolveReaderChunkTextAlign(chunk, widget.settings);

    final textStyle = widget.settings.getTextStyle(isHeading: chunk.isHeading);

    final safeArea = MediaQuery.viewPaddingOf(context);
    final layoutMetrics = resolveReaderLayoutMetrics(
      MediaQuery.sizeOf(context),
      safeArea,
      widget.settings,
    );
    final contentPadding = layoutMetrics.contentPadding;
    final cardMargin = layoutMetrics.cardMargin;
    final topPad = contentPadding.top;

    // Bookmark icon sits in the gap ABOVE the text boundary line
    const iconSize = 23.0;
    final iconTop = safeArea.top > 0 ? safeArea.top + 2 : 2.0;

    final chunkText = chunk.text;
    final hasText = chunkText != null && chunkText.isNotEmpty;

    return Listener(
      onPointerDown: (event) {
        _speedReadTapHandled = false;
        _selectionChangedDuringPointer = false;
        _lastPointerPosition = event.position;
        _lastPointerDownPosition = event.position;
        _consecutiveTaps++;
        _tapTimer?.cancel();
        if (_consecutiveTaps == 3) {
          _consecutiveTaps = 0;
          widget.onTripleTap?.call();
        } else {
          _tapTimer = Timer(const Duration(milliseconds: 350), () {
            _consecutiveTaps = 0;
          });
        }
      },
      child: RepaintBoundary(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTap: _handleBookmarkAction,
          onTapUp: (details) {
            if (_selectionChangedDuringPointer) {
              return;
            }
            if (_speedReadTapHandled) {
              return;
            }

            // Guard: if we just set _tappedHighlight via long-press, don't clear it
            if (_justTappedHighlight) return;

            // Priority 1: Clear selection / tapped highlight
            if (_hasActiveSelection || _tappedHighlight != null) {
              _cancelSelectionMenuTimer();
              setState(() {
                _hasActiveSelection = false;
                _showSelectionMenu = false;
                _tappedHighlight = null;
                _selectionStart = null;
                _selectionEnd = null;
              });
              FocusScope.of(context).unfocus();
              if (widget.speedReadController?.isActive == true) {
                widget.speedReadController!.resume();
              }
              return;
            }

            // Priority 2: Default action (toggle reader menu for taps on margins)
            widget.onTapOutside?.call(details.globalPosition);
          },
          child: _buildReadingSurface(
            bgColor: bgColor,
            cardMargin: cardMargin,
            contentPadding: contentPadding,
            chunk: chunk,
            chunkText: chunkText,
            hasText: hasText,
            textStyle: textStyle,
            textAlign: textAlign,
            topPad: topPad,
            iconTop: iconTop,
            iconSize: iconSize,
          ),
        ),
      ),
    );
  }

  Widget _buildReadingSurface({
    required Color bgColor,
    required EdgeInsets cardMargin,
    required EdgeInsets contentPadding,
    required BookChunk chunk,
    required String? chunkText,
    required bool hasText,
    required TextStyle textStyle,
    required TextAlign textAlign,
    required double topPad,
    required double iconTop,
    required double iconSize,
  }) {
    final isCardDepth = widget.settings.enableCardDepth;
    final radius = isCardDepth ? AppUi.cardRadius(AppUi.radiusXl) : null;
    final stackToRight =
        widget.settings.pagingAxis == ReaderPagingAxis.horizontal;

    final cardFace = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: cardMargin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: radius ?? BorderRadius.zero,
        border: isCardDepth
            ? Border.all(
                color: widget.settings.borderColor,
                width: kReaderCardDepthBorderWidth,
              )
            : null,
        boxShadow: isCardDepth
            ? AppUi.readerCardShadows(widget.settings, sideShadow: stackToRight)
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius ?? BorderRadius.zero,
        child: Stack(
          children: [
            if (widget.settings.effectiveTheme == AppTheme.newspaper)
              const Positioned.fill(
                child: IgnorePointer(child: _PaperGrainTexture()),
              ),
            Padding(
              padding: contentPadding,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: chunk.isHeading
                            ? _buildHeadingContent(
                                chunkText ?? '',
                                textStyle,
                                constraints,
                              )
                            : _buildBodyContent(
                                chunk,
                                chunkText,
                                hasText,
                                textStyle,
                                textAlign,
                                constraints,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (isCardDepth) ...[
              _buildDepthHeader(contentPadding, textStyle, iconSize),
              _buildDepthFooter(contentPadding, textStyle),
            ] else ...[
              _buildFlatBookmarkIndicator(iconTop, iconSize),
              Positioned(
                top: 0,
                right: 0,
                width: 64,
                height: topPad + 8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleBookmarkAction,
                  onDoubleTap: _handleBookmarkAction,
                  onLongPress: widget.bookmark != null
                      ? widget.onBookmarkLongPress
                      : null,
                ),
              ),
            ],
            if (_showPopIcon) _buildBookmarkPopIcon(),
          ],
        ),
      ),
    );

    if (!isCardDepth || !widget.showStackLayers) return cardFace;

    final lift = widget.depthLiftProgress.clamp(0.0, 1.0).toDouble();
    final backOffsetA = stackToRight
        ? Offset(9 - (lift * 4), 4 - (lift * 2))
        : Offset(0, 11 - (lift * 7));
    final backOffsetB = stackToRight
        ? Offset(17 - (lift * 7), 9 - (lift * 4))
        : Offset(0, 22 - (lift * 13));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildBackCardLayer(
          cardMargin,
          radius!,
          bgColor,
          backOffsetB,
          0.24 + (lift * 0.10),
        ),
        _buildBackCardLayer(
          cardMargin,
          radius,
          bgColor,
          backOffsetA,
          0.42 + (lift * 0.12),
        ),
        cardFace,
      ],
    );
  }

  Widget _buildBackCardLayer(
    EdgeInsets margin,
    BorderRadius radius,
    Color bgColor,
    Offset offset,
    double opacity,
  ) {
    final settings = widget.settings;
    final borderColor = settings.borderColor.withValues(alpha: 0.55);

    return Positioned.fill(
      child: IgnorePointer(
        child: Transform.translate(
          offset: offset,
          child: Container(
            margin: margin,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                settings.readerTextColor.withValues(
                  alpha: settings.isDark ? 0.015 : 0.018,
                ),
                bgColor,
              ).withValues(alpha: opacity),
              borderRadius: radius,
              border: Border.all(color: borderColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDepthHeader(
    EdgeInsets contentPadding,
    TextStyle textStyle,
    double iconSize,
  ) {
    final settings = widget.settings;
    final metaStyle = textStyle.copyWith(
      fontSize: 13,
      height: 1.15,
      letterSpacing: 0,
      color: settings.readerMutedColor.withValues(alpha: 0.74),
      fontWeight: FontWeight.w500,
    );
    final title = (widget.chapterTitle?.trim().isNotEmpty ?? false)
        ? widget.chapterTitle!.trim()
        : 'Current chapter';
    final pageLabel = widget.chapterPageLabel ?? '';
    final iconColor =
        widget.bookmark?.color ??
        settings.readerTextColor.withValues(alpha: 0.32);

    return Positioned(
      left: kContentPaddingH,
      right: kContentPaddingH - 2,
      top: contentPadding.top - 34,
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: metaStyle,
              ),
            ),
            const SizedBox(width: 14),
            Text(pageLabel, maxLines: 1, softWrap: false, style: metaStyle),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleBookmarkAction,
              onDoubleTap: _handleBookmarkAction,
              onLongPress: widget.bookmark != null
                  ? widget.onBookmarkLongPress
                  : null,
              child: AnimatedBuilder(
                animation: _cornerScale,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _cornerScale.value,
                    child: child,
                  );
                },
                child: Icon(
                  widget.bookmark != null
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: iconColor,
                  size: iconSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepthFooter(EdgeInsets contentPadding, TextStyle textStyle) {
    final settings = widget.settings;
    final progress = (widget.chapterProgress ?? 0).clamp(0.0, 1.0).toDouble();
    final trackColor = settings.inactiveControlColor.withValues(alpha: 0.28);
    final fillColor = settings.readerAccentColor;
    final percentStyle = textStyle.copyWith(
      fontSize: 12,
      height: 1,
      letterSpacing: 0,
      color: settings.readerMutedColor.withValues(alpha: 0.72),
      fontWeight: FontWeight.w600,
    );

    return Positioned(
      left: kContentPaddingH,
      right: kContentPaddingH,
      bottom: contentPadding.bottom - 30,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 2.6,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: trackColor,
                  valueColor: AlwaysStoppedAnimation<Color>(fillColor),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('${(progress * 100).round()}%', style: percentStyle),
        ],
      ),
    );
  }

  Widget _buildFlatBookmarkIndicator(double iconTop, double iconSize) {
    return Positioned(
      top: iconTop,
      right: kContentPaddingH - 4,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _cornerScale,
          builder: (context, child) {
            return Transform.scale(scale: _cornerScale.value, child: child);
          },
          child: AnimatedOpacity(
            opacity: widget.bookmark != null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Icon(
              Icons.bookmark_rounded,
              color:
                  widget.bookmark?.color ??
                  _lastBookmarkColor ??
                  widget.settings.bookmarkColor,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkPopIcon() {
    return Center(
      child: AnimatedBuilder(
        animation: _popController,
        builder: (context, child) {
          return Opacity(
            opacity: _popOpacity.value,
            child: Transform.scale(scale: _popScale.value, child: child),
          );
        },
        child: Icon(
          widget.bookmark != null
              ? Icons.bookmark_rounded
              : Icons.bookmark_remove_rounded,
          color:
              widget.bookmark?.color ??
              _lastBookmarkColor ??
              widget.settings.bookmarkColor,
          size: 100,
          shadows: [
            Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20),
          ],
        ),
      ),
    );
  }

  // ── Heading card: vertically centered with decorative divider ──
  Widget _buildHeadingContent(
    String text,
    TextStyle textStyle,
    BoxConstraints constraints,
  ) {
    final settings = widget.settings;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText.rich(
          TextSpan(text: text, style: textStyle),
          textAlign: TextAlign.center,
          strutStyle: settings.getHeadingStrutStyle(),
          selectionColor: _activeSelectionColor(),
          onSelectionChanged: _onSelectionChanged,
          contextMenuBuilder: (context, editableTextState) {
            return const SizedBox.shrink();
          },
        ),
        const SizedBox(height: 20),
        Text(
          '─────── ◆ ───────',
          style: TextStyle(
            color: settings.readerMutedColor.withValues(alpha: 0.45),
            fontSize: 14,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  // ── Body text card: handles regular text + dialogue styling ──
  Widget _buildBodyContent(
    BookChunk chunk,
    String? chunkText,
    bool hasText,
    TextStyle textStyle,
    TextAlign textAlign,
    BoxConstraints constraints,
  ) {
    TextPainter? wordHitTestPainter;
    final speedReadController = widget.speedReadController;
    final isSpeedReadActive =
        speedReadController?.isActive == true && widget.isActivePage;
    final isLyricsSpeedRead =
        isSpeedReadActive &&
        widget.settings.speedReadDisplayMode == SpeedReadDisplayMode.lyrics;
    final isWindowSpeedRead =
        isSpeedReadActive &&
        widget.settings.speedReadDisplayMode == SpeedReadDisplayMode.window;
    final publisherPadding = resolveReaderPublisherPadding(chunk);
    final dialogueInset = chunk.isDialogue ? kReaderDialogueTextInset : 0.0;
    final bodyTextStyle = textStyle.copyWith(
      color: chunk.isDialogue
          ? textStyle.color?.withValues(alpha: 0.92)
          : textStyle.color,
    );
    final contentBlocks = hasText
        ? parseReaderContentBlocks(chunkText!)
        : const <ReaderContentBlock>[];
    final hasStructuredBlocks = contentBlocks.any(
      (block) => block.type != ReaderContentBlockType.paragraph,
    );

    if (hasText && isSpeedReadActive && !hasStructuredBlocks) {
      final span = _buildSpeedReadTextSpan(
        chunkText!,
        bodyTextStyle,
        speedReadController!,
        dimInactive: isLyricsSpeedRead,
      );
      wordHitTestPainter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textAlign: textAlign,
        textScaler: MediaQuery.textScalerOf(context),
        strutStyle: widget.settings.getBodyStrutStyle(),
      );
      final maxWidth =
          constraints.maxWidth - dialogueInset - publisherPadding.horizontal;
      wordHitTestPainter.layout(
        maxWidth: maxWidth.clamp(1.0, double.infinity).toDouble(),
      );
    }

    TextSpan buildBodySpan({String? text, int startOffset = 0}) {
      final spanText = text ?? chunkText!;
      final controller = widget.speedReadController;
      if (!hasStructuredBlocks &&
          controller?.isActive == true &&
          widget.isActivePage) {
        return _buildSpeedReadTextSpan(
          spanText,
          bodyTextStyle,
          controller!,
          dimInactive:
              widget.settings.speedReadDisplayMode ==
              SpeedReadDisplayMode.lyrics,
          startOffset: startOffset,
        );
      }
      return _buildHighlightedTextSpan(
        spanText,
        bodyTextStyle,
        textAlign,
        startOffset: startOffset,
      );
    }

    Widget buildSelectableText({String? text, int startOffset = 0}) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (event) {
          _lastPointerPosition = event.position;
          _speedReadTapHandled = _handleSpeedReadTextTap(
            localPosition: event.localPosition,
            globalPosition: event.position,
            textPainter: wordHitTestPainter,
          );
        },
        child: SelectableText.rich(
          buildBodySpan(text: text, startOffset: startOffset),
          textAlign: textAlign,
          strutStyle: widget.settings.getBodyStrutStyle(),
          selectionColor: _activeSelectionColor(),
          onSelectionChanged: (selection, cause) =>
              _onSelectionChangedFromOffset(selection, cause, startOffset),
          onTap: () {
            if (_selectionChangedDuringPointer) {
              return;
            }
            if (_speedReadTapHandled) {
              return;
            }

            // Guard: if we just set _tappedHighlight via long-press, don't clear it
            if (_justTappedHighlight) return;

            if (_hasActiveSelection || _tappedHighlight != null) {
              _cancelSelectionMenuTimer();
              setState(() {
                _hasActiveSelection = false;
                _showSelectionMenu = false;
                _tappedHighlight = null;
                _selectionStart = null;
                _selectionEnd = null;
              });
              FocusScope.of(context).unfocus();
              if (widget.speedReadController?.isActive == true) {
                widget.speedReadController!.resume();
              }
              return;
            }

            // Let taps on text blocks that miss word tokens act as general toggles.
            widget.onTapOutside?.call(null);
          },
          contextMenuBuilder: (context, editableTextState) {
            return const SizedBox.shrink();
          },
        ),
      );
    }

    Widget buildParagraphSeparatedBodyContent() {
      if (!hasText || isSpeedReadActive) {
        return buildSelectableText();
      }

      final segments = splitFinalLayoutParagraphSegments(chunkText!);
      if (segments.length <= 1) {
        return buildSelectableText();
      }

      final paragraphGap = finalLayoutParagraphGapForStyle(
        style: bodyTextStyle,
        fallbackFontSize: widget.settings.fontSizeValue,
        fallbackLineHeight: widget.settings.lineHeight,
        paragraphSpacing: widget.settings.paragraphSpacing,
      );

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < segments.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : paragraphGap),
              child: buildSelectableText(
                text: segments[i].text,
                startOffset: segments[i].startOffset,
              ),
            ),
        ],
      );
    }

    Widget buildTableAwareContent() {
      final paragraphPadding = 4.0 * widget.settings.paragraphSpacing;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final block in contentBlocks)
            switch (block.type) {
              ReaderContentBlockType.paragraph => Padding(
                padding: EdgeInsets.symmetric(vertical: paragraphPadding),
                child: buildSelectableText(
                  text: block.rawText,
                  startOffset: block.startOffset,
                ),
              ),
              ReaderContentBlockType.table => ReaderTableBlockWidget(
                table: block.table!,
                settings: widget.settings,
                baseTextStyle: bodyTextStyle,
              ),
              ReaderContentBlockType.preformatted =>
                ReaderPreformattedBlockWidget(
                  text: block.rawText,
                  settings: widget.settings,
                  baseTextStyle: bodyTextStyle,
                ),
            },
        ],
      );
    }

    return Stack(
      children: [
        // Dialogue watermark: faded quote glyph
        if (chunk.isDialogue)
          Positioned(
            left: -8,
            top: -8,
            child: IgnorePointer(
              child: Text(
                '\u201c',
                style: TextStyle(
                  fontSize: 56,
                  color: widget.settings.readerTextColor.withValues(
                    alpha: 0.035,
                  ),
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),

        Padding(
          padding: EdgeInsets.only(
            left: dialogueInset + publisherPadding.left,
            right: publisherPadding.right,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chunk.type == BookChunkType.image && chunk.imageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onImageTap,
                    child: Image.memory(chunk.imageBytes!, fit: BoxFit.contain),
                  ),
                ),
              if (hasText)
                Stack(
                  children: [
                    if (isWindowSpeedRead &&
                        wordHitTestPainter != null &&
                        speedReadController != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: SpeedReadOverlay(
                            controller: speedReadController,
                            textPainter: wordHitTestPainter,
                            settings: widget.settings,
                          ),
                        ),
                      ),
                    hasStructuredBlocks
                        ? buildTableAwareContent()
                        : speedReadController == null
                        ? buildParagraphSeparatedBodyContent()
                        : AnimatedBuilder(
                            animation: Listenable.merge([
                              speedReadController,
                              _speedReadStyleController,
                            ]),
                            builder: (context, _) =>
                                buildParagraphSeparatedBodyContent(),
                          ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _showNoteEditor({
    Highlight? existingNoteAnnotation,
    Highlight? sourceAnnotation,
    _PendingNoteDraft? pendingDraft,
  }) {
    final createAnnotation = widget.onHighlightCreated;
    final createMappedNote = widget.onMappedNoteCreated;
    final updateNote = widget.onNoteUpdated;
    final removeNote = widget.onNoteRemoved;
    final selectedStart = _selectionStart;
    final selectedEnd = _selectionEnd;
    final chunkText = widget.chunk.text ?? '';
    final previewText =
        (existingNoteAnnotation?.text ??
                sourceAnnotation?.text ??
                pendingDraft?.text ??
                (() {
                  if (selectedStart == null || selectedEnd == null) return '';
                  final start = selectedStart.clamp(0, chunkText.length);
                  final end = selectedEnd.clamp(0, chunkText.length);
                  if (start >= end) return '';
                  return chunkText.substring(start, end);
                })())
            .trim();

    showNoteEditorSheet(
      context,
      title: existingNoteAnnotation == null ? 'Add note' : 'Edit note',
      highlightedText: previewText,
      accentColor:
          (existingNoteAnnotation ?? sourceAnnotation)?.color ??
          pendingDraft?.color ??
          _selectedColor,
      readingSettings: widget.settings,
      initialNote: existingNoteAnnotation?.note ?? '',
      submitLabel: existingNoteAnnotation == null ? 'Save Note' : 'Update Note',
    ).then((result) {
      if (result is String) {
        if (existingNoteAnnotation == null) {
          if (result.isNotEmpty) {
            if (sourceAnnotation != null && !sourceAnnotation.isNote) {
              updateNote?.call(sourceAnnotation.id, result);
            } else if (pendingDraft != null) {
              if (createMappedNote != null) {
                unawaited(
                  createMappedNote(
                    pendingDraft.mappedRanges,
                    pendingDraft.text,
                    pendingDraft.color,
                    result,
                  ),
                );
              } else {
                createAnnotation?.call(
                  pendingDraft.startOffset,
                  pendingDraft.endOffset,
                  pendingDraft.text,
                  pendingDraft.color,
                  HighlightType.highlight,
                  result,
                );
              }
            } else if (selectedStart != null && selectedEnd != null) {
              final start = selectedStart.clamp(0, chunkText.length);
              final end = selectedEnd.clamp(0, chunkText.length);
              if (start < end) {
                final selectedText = chunkText.substring(start, end);
                createAnnotation?.call(
                  start,
                  end,
                  selectedText,
                  _selectedColor,
                  HighlightType.highlight,
                  result,
                );
              }
            }
          }
          if (!mounted) {
            return;
          }
          _cancelSelectionMenuTimer();
          setState(() {
            _hasActiveSelection = false;
            _showSelectionMenu = false;
            _selectionStart = null;
            _selectionEnd = null;
            _tappedHighlight = null;
            _pendingNoteDraft = null;
          });
        } else {
          if (result.isEmpty) {
            removeNote?.call(existingNoteAnnotation.id);
          } else {
            updateNote?.call(existingNoteAnnotation.id, result);
          }
          if (!mounted) {
            return;
          }
          setState(() {
            if (_tappedHighlight?.id == existingNoteAnnotation.id) {
              _tappedHighlight = null;
            }
            _pendingNoteDraft = null;
          });
        }
      } else if (mounted && _pendingNoteDraft != null) {
        setState(() {
          _pendingNoteDraft = null;
        });
      }
    });
  }

  void _showNotePreview(
    Highlight noteAnnotation, {
    Highlight? sourceAnnotation,
  }) {
    showNotePreviewPopup(
      context,
      highlight: noteAnnotation,
      readingSettings: widget.settings,
      contextText: sourceAnnotation?.text,
      onEdit: () {
        _showNoteEditor(
          existingNoteAnnotation: noteAnnotation,
          sourceAnnotation: sourceAnnotation,
        );
      },
      onDelete: widget.onNoteRemoved == null
          ? null
          : () {
              widget.onNoteRemoved?.call(noteAnnotation.id);
              if (!mounted) return;
              setState(() {
                if (_tappedHighlight?.id == noteAnnotation.id) {
                  _tappedHighlight = null;
                }
              });
            },
    );
  }

  // ── Milestone celebration card ──
  Widget _buildMilestoneCard(BuildContext context, Color bgColor) {
    final settings = widget.settings;
    final text = widget.chunk.text ?? '';

    // Parse milestone percentage from text
    String emoji = '📖';
    if (text.contains('25%')) {
      emoji = '📖';
    } else if (text.contains('50%')) {
      emoji = '🔥';
    } else if (text.contains('75%')) {
      emoji = '🎉';
    }

    return Container(
      color: bgColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 20),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: settings.readerTextColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '─────── ✦ ───────',
                style: TextStyle(
                  color: settings.readerMutedColor.withValues(alpha: 0.45),
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Keep going!',
                style: TextStyle(
                  fontSize: 15,
                  color: settings.readerMutedColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper class representing a character name range for foreground styling.
class _StyledRange {
  final int start;
  final int end;
  final Color color;
  final Highlight? highlight;

  const _StyledRange({
    required this.start,
    required this.end,
    required this.color,
    required this.highlight,
  });
}

/// A background highlight range (start/end offsets + color).
class _HighlightBgRange {
  final int start;
  final int end;
  final Color color;
  final Highlight highlight;

  const _HighlightBgRange({
    required this.start,
    required this.end,
    required this.color,
    required this.highlight,
  });
}

class _NoteDecorationRange {
  final int start;
  final int end;
  final Color color;
  final Highlight? highlight;

  const _NoteDecorationRange({
    required this.start,
    required this.end,
    required this.color,
    required this.highlight,
  });
}

class _ActiveSelectionRange {
  final int start;
  final int end;

  const _ActiveSelectionRange({required this.start, required this.end});
}

class _PendingNoteDraft {
  final int startOffset;
  final int endOffset;
  final String text;
  final Color color;
  final List<MappedTextRange> mappedRanges;

  const _PendingNoteDraft({
    required this.startOffset,
    required this.endOffset,
    required this.text,
    required this.color,
    required this.mappedRanges,
  });
}

class _SelectedTextRange {
  final int startOffset;
  final int endOffset;
  final String text;

  const _SelectedTextRange({
    required this.startOffset,
    required this.endOffset,
    required this.text,
  });
}

enum _HighlightMoreAction { copy, share }

/// Subtle paper-grain texture for newspaper theme.
/// Draws semi-random scattered dots using a seeded pattern.
class _PaperGrainTexture extends StatelessWidget {
  const _PaperGrainTexture();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PaperGrainPainter(), size: Size.infinite);
  }
}

class _PaperGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.025)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    // Deterministic but visually random pattern
    const step = 8.0;
    int seed = 42;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        if (seed % 3 == 0) {
          final dx = x + (seed % 5).toDouble();
          final dy = y + ((seed >> 3) % 5).toDouble();
          canvas.drawCircle(Offset(dx, dy), 0.5, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
