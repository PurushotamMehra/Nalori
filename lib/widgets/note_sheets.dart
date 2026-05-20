import 'dart:async';

import 'package:flutter/material.dart';

import '../models/highlight.dart';
import '../models/reading_settings.dart';

Future<String?> showNoteEditorSheet(
  BuildContext context, {
  required String title,
  required String highlightedText,
  required Color accentColor,
  ReadingSettings? readingSettings,
  String initialNote = '',
  String submitLabel = 'Save Note',
}) {
  final sheetKey = GlobalKey<_NoteEditorSheetState>();
  return showGeneralDialog<String>(
    context: context,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _NoteEditorDismissLayer(
        sheetKey: sheetKey,
        child: _NoteEditorSheet(
          key: sheetKey,
          title: title,
          highlightedText: highlightedText,
          accentColor: accentColor,
          readingSettings: readingSettings,
          initialNote: initialNote,
          submitLabel: submitLabel,
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _NoteEditorDismissLayer extends StatelessWidget {
  final GlobalKey<_NoteEditorSheetState> sheetKey;
  final Widget child;

  const _NoteEditorDismissLayer({required this.sheetKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => sheetKey.currentState?.requestDismiss(),
        child: child,
      ),
    );
  }
}

Future<bool> _confirmDiscardNote(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Discard note?'),
      content: const Text('Your unsaved note text will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Discard note'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showNoteDetailSheet(
  BuildContext context, {
  required Highlight highlight,
  required String locationLabel,
  ReadingSettings? readingSettings,
  String? contextText,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  VoidCallback? onNavigate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _NoteDetailSheet(
      highlight: highlight,
      locationLabel: locationLabel,
      readingSettings: readingSettings,
      contextText: contextText,
      onEdit: onEdit,
      onDelete: onDelete,
      onNavigate: onNavigate,
    ),
  );
}

Future<void> showNotePreviewPopup(
  BuildContext context, {
  required Highlight highlight,
  ReadingSettings? readingSettings,
  String? contextText,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _NotePreviewPopup(
      highlight: highlight,
      readingSettings: readingSettings,
      contextText: contextText,
      onEdit: onEdit,
      onDelete: onDelete,
    ),
  );
}

class _NoteEditorSheet extends StatefulWidget {
  final String title;
  final String highlightedText;
  final Color accentColor;
  final ReadingSettings? readingSettings;
  final String initialNote;
  final String submitLabel;

  const _NoteEditorSheet({
    super.key,
    required this.title,
    required this.highlightedText,
    required this.accentColor,
    this.readingSettings,
    required this.initialNote,
    required this.submitLabel,
  });

  @override
  State<_NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<_NoteEditorSheet> {
  late final TextEditingController _controller;
  late bool _isSelectedTextExpanded;
  bool _isConfirmingDismiss = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
    _controller.addListener(_handleTextChanged);
    _isSelectedTextExpanded = !_shouldCollapseSelectedText(
      widget.highlightedText,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  bool get _hasUnsavedChanges {
    final current = _controller.text.trim();
    final initial = widget.initialNote.trim();
    return current.isNotEmpty && current != initial;
  }

  bool _shouldCollapseSelectedText(String text) {
    final trimmed = text.trim();
    return trimmed.length > 220 || '\n'.allMatches(trimmed).length >= 2;
  }

  void _handleTextChanged() {
    setState(() {});
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  Future<void> requestDismiss() async {
    if (!_hasUnsavedChanges) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (_isConfirmingDismiss) return;
    _isConfirmingDismiss = true;
    final discard = await _confirmDiscardNote(context);
    _isConfirmingDismiss = false;
    if (!mounted || !discard) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readerTheme = _ReaderSheetTheme.from(context, widget.readingSettings);
    final mediaSize = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final selectedText = widget.highlightedText.trim();
    final shouldCollapseSelectedText = _shouldCollapseSelectedText(
      selectedText,
    );
    final maxSheetHeight = (mediaSize.height - viewInsets.bottom - 32)
        .clamp(340.0, mediaSize.height * 0.88)
        .toDouble();
    final expandedPreviewMaxHeight = (maxSheetHeight * 0.24)
        .clamp(96.0, 180.0)
        .toDouble();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(requestDismiss());
      },
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: viewInsets.bottom + 16,
              top: 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                onVerticalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity > 420) unawaited(requestDismiss());
                },
                child: Material(
                  color: readerTheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: readerTheme.divider,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: readerTheme.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Reference the selected text while writing your note.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: readerTheme.muted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Selected text',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: readerTheme.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: readerTheme.subtleSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: widget.accentColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 4,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: widget.accentColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: _isSelectedTextExpanded
                                      ? ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: expandedPreviewMaxHeight,
                                          ),
                                          child: SingleChildScrollView(
                                            primary: false,
                                            child: Text(
                                              '"$selectedText"',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color: readerTheme.text,
                                                    height: 1.45,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                            ),
                                          ),
                                        )
                                      : Text(
                                          '"$selectedText"',
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: readerTheme.text,
                                                height: 1.45,
                                                fontStyle: FontStyle.italic,
                                              ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (shouldCollapseSelectedText)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                setState(
                                  () => _isSelectedTextExpanded =
                                      !_isSelectedTextExpanded,
                                );
                              },
                              icon: Icon(
                                _isSelectedTextExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 18,
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: readerTheme.muted,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                              ),
                              label: Text(
                                _isSelectedTextExpanded
                                    ? 'Show less'
                                    : 'Show more',
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            expands: true,
                            maxLines: null,
                            maxLength: 1000,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            style: TextStyle(color: readerTheme.text),
                            cursorColor: widget.accentColor,
                            decoration: InputDecoration(
                              labelText: 'Your note',
                              hintText:
                                  'Capture the thought, question, or insight here.',
                              helperText:
                                  'Press the keyboard done button or Save Note.',
                              alignLabelWithHint: true,
                              labelStyle: TextStyle(color: readerTheme.muted),
                              hintStyle: TextStyle(
                                color: readerTheme.muted.withValues(
                                  alpha: 0.72,
                                ),
                              ),
                              helperStyle: TextStyle(
                                color: readerTheme.muted.withValues(
                                  alpha: 0.82,
                                ),
                              ),
                              counterStyle: TextStyle(color: readerTheme.muted),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: readerTheme.divider,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: readerTheme.divider,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide(
                                  color: widget.accentColor,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: requestDismiss,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  foregroundColor: readerTheme.text,
                                  side: BorderSide(color: readerTheme.divider),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _canSubmit ? _submit : null,
                                icon: const Icon(Icons.check_rounded),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  backgroundColor: widget.accentColor,
                                  foregroundColor: _foregroundFor(
                                    widget.accentColor,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                label: Text(widget.submitLabel),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteDetailSheet extends StatefulWidget {
  final Highlight highlight;
  final String locationLabel;
  final ReadingSettings? readingSettings;
  final String? contextText;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onNavigate;

  const _NoteDetailSheet({
    required this.highlight,
    required this.locationLabel,
    this.readingSettings,
    this.contextText,
    this.onEdit,
    this.onDelete,
    this.onNavigate,
  });

  @override
  State<_NoteDetailSheet> createState() => _NoteDetailSheetState();
}

class _NoteDetailSheetState extends State<_NoteDetailSheet>
    with SingleTickerProviderStateMixin {
  late bool _isSelectedTextExpanded;

  @override
  void initState() {
    super.initState();
    final previewText = _previewText;
    _isSelectedTextExpanded = previewText.length <= 260;
  }

  String get _previewText => widget.contextText?.trim().isNotEmpty == true
      ? widget.contextText!.trim()
      : widget.highlight.text.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final readerTheme = _ReaderSheetTheme.from(context, widget.readingSettings);
    final noteText = widget.highlight.note?.trim() ?? '';
    final previewText = _previewText;
    final shouldCollapse = previewText.length > 260;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Material(
          color: readerTheme.surface,
          borderRadius: BorderRadius.circular(22),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: readerTheme.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Note',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: readerTheme.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: readerTheme.subtleSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: readerTheme.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bookmark_border_rounded,
                        size: 14,
                        color: readerTheme.muted,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width - 118,
                        ),
                        child: Text(
                          widget.locationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: readerTheme.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your note',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: readerTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: readerTheme.subtleSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    noteText,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: readerTheme.text,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Selected text',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: readerTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: readerTheme.subtleSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: widget.highlight.color.withValues(alpha: 0.34),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4,
                        height: 52,
                        decoration: BoxDecoration(
                          color: widget.highlight.color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: Text(
                            '"$previewText"',
                            maxLines: shouldCollapse && !_isSelectedTextExpanded
                                ? 4
                                : null,
                            overflow: shouldCollapse && !_isSelectedTextExpanded
                                ? TextOverflow.ellipsis
                                : TextOverflow.visible,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: readerTheme.muted,
                              fontStyle: FontStyle.italic,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (shouldCollapse)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(
                          () => _isSelectedTextExpanded =
                              !_isSelectedTextExpanded,
                        );
                      },
                      icon: Icon(
                        _isSelectedTextExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: readerTheme.muted,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      label: Text(
                        _isSelectedTextExpanded ? 'Show less' : 'Show more',
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                if (widget.onEdit != null || widget.onNavigate != null)
                  Row(
                    children: [
                      if (widget.onEdit != null)
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onEdit?.call();
                            },
                            icon: const Icon(Icons.edit_rounded),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              backgroundColor: readerTheme.accent,
                              foregroundColor: _foregroundFor(
                                readerTheme.accent,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            label: const Text('Edit Note'),
                          ),
                        ),
                      if (widget.onEdit != null && widget.onNavigate != null)
                        const SizedBox(width: 10),
                      if (widget.onNavigate != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onNavigate?.call();
                            },
                            icon: const Icon(Icons.my_location_rounded),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              foregroundColor: readerTheme.text,
                              side: BorderSide(color: readerTheme.divider),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            label: const Text('Go To Text'),
                          ),
                        ),
                    ],
                  ),
                if (widget.onDelete != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDelete?.call();
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: colorScheme.error.withValues(
                          alpha: colorScheme.brightness == Brightness.dark
                              ? 0.18
                              : 0.10,
                        ),
                        foregroundColor: colorScheme.error.withValues(
                          alpha: 0.90,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      label: const Text('Delete Note'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotePreviewPopup extends StatelessWidget {
  final Highlight highlight;
  final ReadingSettings? readingSettings;
  final String? contextText;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _NotePreviewPopup({
    required this.highlight,
    this.readingSettings,
    this.contextText,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final readerTheme = _ReaderSheetTheme.from(context, readingSettings);
    final noteText = highlight.note?.trim() ?? '';
    final previewText = contextText?.trim().isNotEmpty == true
        ? contextText!.trim()
        : highlight.text.trim();

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: double.infinity,
        height: MediaQuery.sizeOf(context).height,
        child: SafeArea(
          top: false,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Material(
                    color: readerTheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.46,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (onDelete != null) ...[
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    tooltip: 'Delete note',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      onDelete?.call();
                                    },
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: colorScheme.error.withValues(
                                        alpha: 0.82,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                Expanded(
                                  child: Text(
                                    'Note',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: readerTheme.text,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                if (onEdit != null)
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    tooltip: 'Edit note',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      onEdit?.call();
                                    },
                                    icon: Icon(
                                      Icons.edit_rounded,
                                      color: readerTheme.accent,
                                    ),
                                  ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 40,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  tooltip: 'Close',
                                  onPressed: () => Navigator.pop(context),
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: readerTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: readerTheme.subtleSurface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: highlight.color.withValues(
                                    alpha: 0.34,
                                  ),
                                ),
                              ),
                              child: Text(
                                '"$previewText"',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: readerTheme.muted,
                                  height: 1.4,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              noteText,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: readerTheme.text,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _foregroundFor(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

class _ReaderSheetTheme {
  final Color surface;
  final Color subtleSurface;
  final Color text;
  final Color muted;
  final Color divider;
  final Color accent;

  const _ReaderSheetTheme({
    required this.surface,
    required this.subtleSurface,
    required this.text,
    required this.muted,
    required this.divider,
    required this.accent,
  });

  factory _ReaderSheetTheme.from(
    BuildContext context,
    ReadingSettings? settings,
  ) {
    final theme = Theme.of(context);
    if (settings == null) {
      final scheme = theme.colorScheme;
      return _ReaderSheetTheme(
        surface: scheme.surface,
        subtleSurface: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        divider: theme.dividerColor,
        accent: scheme.primary,
      );
    }

    return _ReaderSheetTheme(
      surface: settings.menuColor,
      subtleSurface: settings.backgroundColor.withValues(
        alpha: settings.isDark ? 0.42 : 0.7,
      ),
      text: settings.textColor,
      muted: settings.mutedColor,
      divider: settings.textColor.withValues(
        alpha: settings.isDark ? 0.2 : 0.14,
      ),
      accent: settings.accentColor,
    );
  }
}
