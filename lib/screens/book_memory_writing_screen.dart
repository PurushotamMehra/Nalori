import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book_memory_entry.dart';
import '../models/reading_settings.dart';
import '../services/book_memory_entry_service.dart';
import '../ui/app_visuals.dart';

class BookMemorySourcePreview {
  final BookMemorySourceType sourceType;
  final String? sourceId;
  final String title;
  final String subtitle;
  final String? body;
  final String? date;
  final Color color;
  final int? originalChunkIndex;
  final List<String> details;
  final List<BookMemoryDetailItem> detailItems;

  const BookMemorySourcePreview({
    required this.sourceType,
    required this.sourceId,
    required this.title,
    required this.subtitle,
    this.body,
    this.date,
    required this.color,
    this.originalChunkIndex,
    this.details = const [],
    this.detailItems = const [],
  });
}

class BookMemoryDetailItem {
  final String section;
  final String label;
  final String text;
  final BookMemorySourceType? sourceType;
  final String? sourceId;
  final int? originalChunkIndex;
  final int? originalStartOffset;
  final BookMemorySourcePreview? sourcePreview;
  final bool spoilerProtected;

  const BookMemoryDetailItem({
    required this.section,
    required this.label,
    required this.text,
    this.sourceType,
    this.sourceId,
    this.originalChunkIndex,
    this.originalStartOffset,
    this.sourcePreview,
    this.spoilerProtected = false,
  });
}

class BookMemoryWritingScreen extends StatefulWidget {
  final File bookFile;
  final String bookId;
  final ReadingSettings settings;
  final BookMemorySourceType sourceType;
  final String? sourceId;
  final String? entryId;
  final BookMemorySourcePreview? sourcePreview;

  const BookMemoryWritingScreen({
    super.key,
    required this.bookFile,
    required this.bookId,
    required this.settings,
    required this.sourceType,
    this.sourceId,
    this.entryId,
    this.sourcePreview,
  });

  @override
  State<BookMemoryWritingScreen> createState() =>
      _BookMemoryWritingScreenState();
}

class _BookMemoryWritingScreenState extends State<BookMemoryWritingScreen> {
  late final BookMemoryEntryService _service;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  Timer? _saveDebounce;
  BookMemoryEntry? _entry;
  bool _loading = true;
  bool _saving = false;
  bool _closing = false;
  bool _changed = false;
  String _status = 'Not saved';

  ReadingSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _service = BookMemoryEntryService(bookId: widget.bookId);
    _titleController = TextEditingController();
    _bodyController = TextEditingController();
    _titleController.addListener(_handleTextChanged);
    _bodyController.addListener(_handleTextChanged);
    _loadEntry();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadEntry() async {
    BookMemoryEntry? entry;
    if (widget.entryId != null) {
      entry = await _service.loadById(widget.entryId!);
    } else if (widget.sourceType != BookMemorySourceType.free &&
        widget.sourceId != null) {
      entry = await _service.loadForSource(widget.sourceType, widget.sourceId!);
    }

    if (!mounted) return;
    setState(() {
      _entry = entry;
      _titleController.text = entry?.title ?? '';
      _bodyController.text = entry?.body ?? '';
      _status = entry == null ? 'Not saved' : 'Saved';
      _loading = false;
      _changed = false;
    });
  }

  void _handleTextChanged() {
    if (_loading || _closing) return;
    _changed = true;
    _saveDebounce?.cancel();
    final hasText = _hasDraftText;
    setState(() => _status = hasText ? 'Saving...' : 'Not saved');
    if (!hasText) return;
    _saveDebounce = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  bool get _hasDraftText =>
      _titleController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty;

  bool get _shouldShowSourcePreview {
    final preview = widget.sourcePreview;
    return preview != null && preview.sourceType != BookMemorySourceType.free;
  }

  Future<BookMemoryEntry?> _saveDraft() async {
    if (_saving || !_hasDraftText) return _entry;
    setState(() {
      _saving = true;
      _status = 'Saving...';
    });

    BookMemoryEntry? saved;
    if (_entry != null) {
      saved = await _service.updateEntry(
        id: _entry!.id,
        title: _titleController.text,
        body: _bodyController.text,
      );
    } else if (widget.sourceType == BookMemorySourceType.free) {
      saved = await _service.createFreeEntry(
        title: _titleController.text,
        body: _bodyController.text,
      );
    } else if (widget.sourceId != null) {
      saved = await _service.upsertSourceEntry(
        sourceType: widget.sourceType,
        sourceId: widget.sourceId!,
        title: _titleController.text,
        body: _bodyController.text,
      );
    }

    if (!mounted) return saved;
    setState(() {
      _entry = saved ?? _entry;
      _saving = false;
      _changed = false;
      _status = saved == null ? 'Not saved' : 'Saved';
    });
    return saved;
  }

  Future<bool> _finishEditing() async {
    _saveDebounce?.cancel();
    _closing = true;
    if (!_hasDraftText) {
      if (_entry == null) return true;
      final delete = await _confirmDeleteEmptyEntry();
      if (delete == true) {
        await _service.deleteEntry(_entry!.id);
        return true;
      }
      _closing = false;
      return false;
    }

    if (_changed) {
      await _saveDraft();
    }
    return true;
  }

  Future<bool?> _confirmDeleteEmptyEntry() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _s.menuColor,
        surfaceTintColor: Colors.transparent,
        shape: AppUi.shape(),
        title: Text(
          'Delete empty writing?',
          style: _s.uiText(color: _s.textColor, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This writing has no title or body. Delete the saved entry?',
          style: _s.uiText(color: _s.mutedColor, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _done() async {
    if (await _finishEditing() && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppUi.readerTheme(_s),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final shouldPop = await _finishEditing();
          if (!mounted || !shouldPop) return;
          Navigator.pop(this.context, true);
        },
        child: Scaffold(
          backgroundColor: _s.backgroundColor,
          appBar: AppBar(
            title: Text(
              _entry == null ? 'New Writing' : 'Edit Writing',
              style: _s.uiText(fontWeight: FontWeight.w800),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: _done,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _saveIndicator(),
              ),
              TextButton(
                onPressed: _done,
                child: Text(
                  'Done',
                  style: _s.uiText(
                    color: _s.accentColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          body: _loading
              ? Center(child: CircularProgressIndicator(color: _s.accentColor))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _titleField(),
                      if (_shouldShowSourcePreview) ...[
                        const SizedBox(height: 12),
                        BookMemorySourcePreviewCard(
                          settings: _s,
                          preview: widget.sourcePreview!,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          decoration: AppUi.surfaceCard(_s, prominent: true),
                          child: TextField(
                            controller: _bodyController,
                            expands: true,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            textAlignVertical: TextAlignVertical.top,
                            style: _s.uiText(
                              color: _s.textColor,
                              fontSize: 16,
                              height: 1.55,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Write your thoughts...',
                              hintStyle: _s.uiText(color: _s.mutedColor),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.all(16),
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

  Widget _titleField() {
    return Container(
      decoration: AppUi.surfaceCard(_s, radius: AppUi.radiusMd),
      child: TextField(
        controller: _titleController,
        textCapitalization: TextCapitalization.sentences,
        style: _s.uiText(
          color: _s.textColor,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
        decoration: InputDecoration(
          hintText: 'Add a title',
          hintStyle: _s.uiText(
            color: _s.mutedColor,
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _saveIndicator() {
    final saved = _status == 'Saved';
    final saving = _saving || _status == 'Saving...';
    return Tooltip(
      message: saved
          ? 'Saved'
          : saving
          ? 'Saving'
          : 'Unsaved changes',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Icon(
          saved
              ? Icons.check_circle_rounded
              : saving
              ? Icons.sync_rounded
              : Icons.circle_outlined,
          key: ValueKey(_status),
          color: saved ? _s.accentColor : _s.mutedColor,
          size: 17,
        ),
      ),
    );
  }
}

class BookMemorySourcePreviewCard extends StatelessWidget {
  final ReadingSettings settings;
  final BookMemorySourcePreview preview;

  const BookMemorySourcePreviewCard({
    super.key,
    required this.settings,
    required this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = _primaryText;
    final supportingText = _supportingText(primaryText);
    final metadata = [
      preview.subtitle,
      if (preview.date != null && preview.date!.trim().isNotEmpty)
        preview.date!,
    ].where((item) => item.trim().isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppUi.surfaceCard(settings, radius: AppUi.radiusMd),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 7,
              decoration: BoxDecoration(
                color: preview.color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SourceTypeBadge(settings: settings, preview: preview),
                  const SizedBox(height: 10),
                  Text(
                    primaryText,
                    style: settings.uiText(
                      color: settings.textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                    maxLines: preview.sourceType == BookMemorySourceType.word
                        ? 2
                        : 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (supportingText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      supportingText,
                      style: settings.uiText(
                        color: settings.textColor.withValues(alpha: 0.78),
                        fontSize: 13,
                        height: 1.4,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Text(
                      metadata,
                      style: settings.uiText(
                        color: settings.mutedColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _primaryText {
    final title = preview.title.trim();
    final body = preview.body?.trim();
    if (preview.sourceType == BookMemorySourceType.note &&
        body != null &&
        body.isNotEmpty) {
      return body;
    }
    return title.isEmpty ? _sourceTypeLabel(preview.sourceType) : title;
  }

  String? _supportingText(String primaryText) {
    final body = preview.body?.trim();
    if (body == null || body.isEmpty) return null;
    if (_sameText(body, primaryText)) return null;
    if (preview.sourceType == BookMemorySourceType.note) return null;
    return body;
  }

  static bool _sameText(String a, String b) {
    return a.trim().replaceAll(RegExp(r'\s+'), ' ') ==
        b.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}

class _SourceTypeBadge extends StatelessWidget {
  final ReadingSettings settings;
  final BookMemorySourcePreview preview;

  const _SourceTypeBadge({required this.settings, required this.preview});

  @override
  Widget build(BuildContext context) {
    final color = preview.color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: settings.isDark ? 0.16 : 0.12),
        borderRadius: AppUi.cardRadius(AppUi.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_sourceTypeIcon(preview.sourceType), size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              _sourceTypeLabel(preview.sourceType),
              style: settings.uiText(
                color: settings.textColor.withValues(alpha: 0.86),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _sourceTypeIcon(BookMemorySourceType type) {
  return switch (type) {
    BookMemorySourceType.bookmark => Icons.bookmark_rounded,
    BookMemorySourceType.highlight => Icons.format_color_fill_rounded,
    BookMemorySourceType.note => Icons.sticky_note_2_rounded,
    BookMemorySourceType.word => Icons.translate_rounded,
    BookMemorySourceType.character => Icons.person_search_rounded,
    BookMemorySourceType.free => Icons.edit_note_rounded,
  };
}

String _sourceTypeLabel(BookMemorySourceType type) {
  return switch (type) {
    BookMemorySourceType.bookmark => 'Bookmark',
    BookMemorySourceType.highlight => 'Highlight',
    BookMemorySourceType.note => 'Reader Note',
    BookMemorySourceType.word => 'Word',
    BookMemorySourceType.character => 'Character',
    BookMemorySourceType.free => 'Free Note',
  };
}
