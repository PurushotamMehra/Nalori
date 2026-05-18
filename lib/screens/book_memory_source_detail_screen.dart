import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book_memory_entry.dart';
import '../models/reading_settings.dart';
import '../services/book_memory_entry_service.dart';
import '../services/highlight_service.dart';
import '../ui/app_visuals.dart';
import 'book_loading_screen.dart';
import 'book_memory_writing_screen.dart';

class BookMemorySourceDetailScreen extends StatefulWidget {
  final File bookFile;
  final String bookId;
  final ReadingSettings settings;
  final BookMemorySourcePreview preview;

  const BookMemorySourceDetailScreen({
    super.key,
    required this.bookFile,
    required this.bookId,
    required this.settings,
    required this.preview,
  });

  @override
  State<BookMemorySourceDetailScreen> createState() =>
      _BookMemorySourceDetailScreenState();
}

class _BookMemorySourceDetailScreenState
    extends State<BookMemorySourceDetailScreen> {
  late final BookMemoryEntryService _entryService;
  BookMemoryEntry? _entry;
  bool _changed = false;
  final Set<int> _expandedDetails = <int>{};
  final Set<int> _revealedSpoilerDetails = <int>{};

  ReadingSettings get _s => widget.settings;
  BookMemorySourcePreview get _preview => widget.preview;

  @override
  void initState() {
    super.initState();
    _entryService = BookMemoryEntryService(bookId: widget.bookId);
    _loadEntry();
  }

  Future<void> _loadEntry() async {
    final sourceId = _preview.sourceId;
    if (_preview.sourceType == BookMemorySourceType.free || sourceId == null) {
      return;
    }
    final entry = await _entryService.loadForSource(
      _preview.sourceType,
      sourceId,
    );
    if (!mounted) return;
    setState(() => _entry = entry);
  }

  Future<void> _goToText({
    int? overrideChunkIndex,
    int? originalStartOffset,
  }) async {
    final chunkIndex = overrideChunkIndex ?? _preview.originalChunkIndex;
    if (chunkIndex == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookLoadingScreen(
          bookFile: widget.bookFile,
          settings: _s,
          // initialOriginalChunkIndex: chunkIndex,
          // initialOriginalStartOffset: originalStartOffset,
        ),
      ),
    );
  }

  Future<void> _writeAboutSource() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BookMemoryWritingScreen(
          bookFile: widget.bookFile,
          bookId: widget.bookId,
          settings: _s,
          sourceType: _preview.sourceType,
          sourceId: _preview.sourceId,
          entryId: _entry?.id,
          sourcePreview: _preview,
        ),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _loadEntry();
    }
  }

  Future<void> _openLinkedSource(BookMemorySourcePreview preview) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BookMemorySourceDetailScreen(
          bookFile: widget.bookFile,
          bookId: widget.bookId,
          settings: _s,
          preview: preview,
        ),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _loadEntry();
    }
  }

  Future<void> _deleteSource() async {
    final sourceId = _preview.sourceId;
    if (sourceId == null || !_canDeleteSource) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _s.menuColor,
        surfaceTintColor: Colors.transparent,
        shape: AppUi.shape(),
        title: Text(
          'Delete ${_sourceLabel(_preview.sourceType).toLowerCase()}?',
          style: _s.uiText(color: _s.textColor, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This removes the saved source item. Any writing linked to it is kept.',
          style: _s.uiText(color: _s.mutedColor, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await HighlightService(bookId: widget.bookId).remove(sourceId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  bool get _canDeleteSource =>
      _preview.sourceType == BookMemorySourceType.highlight ||
      _preview.sourceType == BookMemorySourceType.note;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppUi.readerTheme(_s),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          Navigator.pop(context, _changed);
        },
        child: Scaffold(
          backgroundColor: _s.backgroundColor,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context, _changed),
            ),
            title: Text(
              _sourceLabel(_preview.sourceType),
              style: _s.uiText(fontWeight: FontWeight.w800),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              _sourceHeader(),
              const SizedBox(height: 14),
              if (_isReaderNote) ...[
                _userNoteSection(),
                const SizedBox(height: 14),
              ],
              if (_entry != null) ...[
                _entryCard(_entry!),
                const SizedBox(height: 14),
              ],
              if (!_isReaderNote && _hasDetails)
                _isCharacter ? _characterDetailsCard() : _detailsCard(),
            ],
          ),
          bottomNavigationBar: _bottomActions(),
        ),
      ),
    );
  }

  Widget _sourceHeader() {
    final body = _preview.body?.trim();
    final title = _preview.title.trim();
    final primaryText = _isReaderNote && body != null && body.isNotEmpty
        ? body
        : title;
    final showSupportingBody =
        !_isReaderNote && body != null && body.isNotEmpty && body != title;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppUi.surfaceCard(_s, prominent: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 8,
                  decoration: BoxDecoration(
                    color: _preview.color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primaryText,
                        style: _s.uiText(
                          color: _s.textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _preview.date == null
                            ? _preview.subtitle
                            : '${_preview.subtitle} • ${_preview.date}',
                        style: _s.uiText(
                          color: _s.mutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showSupportingBody) ...[
            const SizedBox(height: 16),
            Text(
              body,
              style: _s.uiText(
                color: _s.textColor.withValues(alpha: 0.9),
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _userNoteSection() {
    final note = _preview.title.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your note',
          style: _s.uiText(
            color: _s.mutedColor,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: AppUi.surfaceCard(_s),
          child: Text(
            note.isEmpty ? 'No note text' : note,
            style: _s.uiText(
              color: note.isEmpty
                  ? _s.mutedColor
                  : _s.textColor.withValues(alpha: 0.88),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomActions() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: OutlinedButton(
                onPressed: _canDeleteSource ? _deleteSource : null,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(
                    color: Colors.redAccent.withValues(
                      alpha: _canDeleteSource ? 0.45 : 0.16,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppUi.cardRadius(12),
                  ),
                ),
                child: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _preview.originalChunkIndex == null
                    ? null
                    : _goToText,
                icon: const Icon(Icons.short_text_rounded, size: 18),
                label: const Text('Go to Text'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _writeAboutSource,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(_primaryActionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(BookMemoryEntry entry) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppUi.surfaceCard(_s),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: _s.accentColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.title.trim().isNotEmpty ? entry.title : 'Writing saved',
              style: _s.uiText(
                color: _s.textColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppUi.surfaceCard(_s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final detail in _preview.details) ...[
            Text(
              detail,
              style: _s.uiText(
                color: _s.textColor.withValues(alpha: 0.86),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (detail != _preview.details.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _characterDetailsCard() {
    final sections = _characterDetailSections();
    return Column(
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          _characterDetailSection(sections[i], initiallyExpanded: true),
          if (i != sections.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _characterDetailSection(
    _CharacterDetailSection section, {
    required bool initiallyExpanded,
  }) {
    return Container(
      decoration: AppUi.surfaceCard(_s),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: _s.mutedColor,
          collapsedIconColor: _s.mutedColor,
          title: Text(
            section.title,
            style: _s.uiText(
              color: _s.textColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          children: [
            for (var i = 0; i < section.items.length; i++) ...[
              _characterDetailItem(
                section.items[i],
                Object.hash(section.title, i),
              ),
              if (i != section.items.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _characterDetailItem(BookMemoryDetailItem item, int index) {
    final expanded = _expandedDetails.contains(index);
    final spoilerRevealed = _revealedSpoilerDetails.contains(index);
    final isHiddenSpoiler = item.spoilerProtected && !spoilerRevealed;
    final displayText = isHiddenSpoiler
        ? 'Hidden to avoid spoilers'
        : item.text;
    final text = expanded ? displayText : _previewText(displayText);
    final canExpand = item.text.length > _detailPreviewLength;
    final canNavigate =
        item.originalChunkIndex != null &&
        (!item.spoilerProtected || spoilerRevealed);
    final trailingActions = <Widget>[
      if (item.spoilerProtected)
        _iconActionButton(
          icon: spoilerRevealed
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          tooltip: spoilerRevealed ? 'Hide' : 'Unhide',
          onPressed: () {
            setState(() {
              if (spoilerRevealed) {
                _revealedSpoilerDetails.remove(index);
              } else {
                _revealedSpoilerDetails.add(index);
              }
            });
          },
        ),
      if (canNavigate)
        _iconActionButton(
          icon: Icons.short_text_rounded,
          tooltip: 'Go to text',
          onPressed: () => _goToText(
            overrideChunkIndex: item.originalChunkIndex,
            originalStartOffset: item.originalStartOffset,
          ),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _s.mutedColor.withValues(alpha: 0.06),
        borderRadius: AppUi.cardRadius(10),
        border: Border.all(color: _s.mutedColor.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.label.trim().isNotEmpty) ...[
                      Text(
                        item.label,
                        style: _s.uiText(
                          color: _s.mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                    ],
                    Text(
                      text,
                      style: _s.uiText(
                        color: _s.textColor.withValues(alpha: 0.86),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingActions.isNotEmpty) ...[
                const SizedBox(width: 10),
                Wrap(spacing: 4, children: trailingActions),
              ],
            ],
          ),
          if (canExpand && !isHiddenSpoiler) ...[
            const SizedBox(height: 6),
            _inlineActionButton(
              label: expanded ? 'Show less' : 'Show more',
              onPressed: () {
                setState(() {
                  if (expanded) {
                    _expandedDetails.remove(index);
                  } else {
                    _expandedDetails.add(index);
                  }
                });
              },
            ),
          ],
          if (item.sourcePreview != null) ...[
            const SizedBox(height: 4),
            _inlineActionButton(
              label: 'Open memory',
              icon: Icons.open_in_new_rounded,
              onPressed: () => _openLinkedSource(item.sourcePreview!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _inlineActionButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    String? tooltip,
  }) {
    final button = TextButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: tooltip == null
          ? button
          : Tooltip(message: tooltip, child: button),
    );
  }

  List<_CharacterDetailSection> _characterDetailSections() {
    if (_preview.detailItems.isNotEmpty) {
      final bySection = <String, List<BookMemoryDetailItem>>{};
      for (final item in _preview.detailItems) {
        bySection
            .putIfAbsent(item.section, () => <BookMemoryDetailItem>[])
            .add(item);
      }
      return bySection.entries
          .map((entry) => _CharacterDetailSection(entry.key, entry.value))
          .where((section) => section.items.isNotEmpty)
          .toList(growable: false);
    }

    final sections = <_CharacterDetailSection>[];
    _CharacterDetailSection? current;

    for (final detail in _preview.details) {
      if (_isCharacterSectionTitle(detail)) {
        current = _CharacterDetailSection(detail, <BookMemoryDetailItem>[]);
        sections.add(current);
        continue;
      }
      current ??= _CharacterDetailSection(
        'Information',
        <BookMemoryDetailItem>[],
      );
      if (!sections.contains(current)) sections.add(current);
      current.items.add(_ParsedCharacterDetailItem.from(detail).toDetailItem());
    }

    return sections
        .where((section) => section.items.isNotEmpty)
        .toList(growable: false);
  }

  bool _isCharacterSectionTitle(String detail) {
    return detail == 'Occurrences' ||
        detail == 'Marked occurrences' ||
        detail == 'Marked moments' ||
        detail == 'Linked highlights and notes';
  }

  String _previewText(String text) {
    final singleLine = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.length <= _detailPreviewLength) return singleLine;
    return '${singleLine.substring(0, _detailPreviewLength).trimRight()}...';
  }

  String _sourceLabel(BookMemorySourceType type) {
    return switch (type) {
      BookMemorySourceType.bookmark => 'Bookmark',
      BookMemorySourceType.highlight => 'Highlight',
      BookMemorySourceType.note => 'Reader Note',
      BookMemorySourceType.word => 'Saved Word',
      BookMemorySourceType.character => 'Character',
      BookMemorySourceType.free => 'Book Note',
    };
  }

  bool get _isReaderNote => _preview.sourceType == BookMemorySourceType.note;
  bool get _isCharacter =>
      _preview.sourceType == BookMemorySourceType.character;
  bool get _hasDetails =>
      _preview.details.isNotEmpty || _preview.detailItems.isNotEmpty;

  String get _primaryActionLabel {
    if (_isReaderNote) return 'Edit';
    return _entry == null ? 'Write' : 'Edit';
  }

  static const int _detailPreviewLength = 120;
}

class _CharacterDetailSection {
  final String title;
  final List<BookMemoryDetailItem> items;

  _CharacterDetailSection(this.title, this.items);
}

class _ParsedCharacterDetailItem {
  final String? label;
  final String text;

  const _ParsedCharacterDetailItem({required this.label, required this.text});

  factory _ParsedCharacterDetailItem.from(String raw) {
    final separator = raw.indexOf(': ');
    if (separator == -1) {
      return _ParsedCharacterDetailItem(label: null, text: raw);
    }
    return _ParsedCharacterDetailItem(
      label: raw.substring(0, separator),
      text: raw.substring(separator + 2),
    );
  }

  BookMemoryDetailItem toDetailItem() {
    return BookMemoryDetailItem(
      section: 'Information',
      label: label ?? '',
      text: text,
    );
  }
}
