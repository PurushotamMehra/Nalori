import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book_memory_entry.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/reading_settings.dart';
import '../models/saved_word.dart';
import '../services/book_character_occurrence_service.dart';
import '../services/book_memory_export_service.dart';
import '../services/book_memory_service.dart';
import '../ui/app_visuals.dart';
import 'book_loading_screen.dart';
import 'book_memory_source_detail_screen.dart';
import 'book_memory_writing_screen.dart';

class BookMemoryScreen extends StatefulWidget {
  final File bookFile;
  final String bookId;
  final ReadingSettings settings;
  final Future<BookMemorySnapshot>? memoryFuture;

  const BookMemoryScreen({
    super.key,
    required this.bookFile,
    required this.bookId,
    required this.settings,
    this.memoryFuture,
  });

  @override
  State<BookMemoryScreen> createState() => _BookMemoryScreenState();
}

class _BookMemoryScreenState extends State<BookMemoryScreen> {
  late Future<BookMemorySnapshot> _memoryFuture;
  final BookMemoryService _memoryService = BookMemoryService();
  final BookMemoryExportService _exportService = BookMemoryExportService();
  final TextEditingController _searchController = TextEditingController();
  _MemorySort _memorySort = _MemorySort.newest;
  int? _selectedColorValue;
  _MemoryCategory? _activeCategory;

  ReadingSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _reloadMemory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reloadMemory() {
    _memoryFuture = widget.memoryFuture ?? _memoryService.load(widget.bookId);
  }

  void _refreshMemory() {
    if (widget.memoryFuture != null) return;
    setState(_reloadMemory);
  }

  Future<void> _copyExport(BookMemorySnapshot memory) async {
    await Clipboard.setData(
      ClipboardData(text: _exportService.buildMarkdown(memory)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Book Memory copied as Markdown'),
        backgroundColor: _s.menuColor,
      ),
    );
  }

  Future<void> _openChunk(
    int? originalChunkIndex, {
    int? originalStartOffset,
  }) async {
    if (originalChunkIndex == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookLoadingScreen(
          bookFile: widget.bookFile,
          settings: _s,
          // initialOriginalChunkIndex: originalChunkIndex,
          // initialOriginalStartOffset: originalStartOffset,
        ),
      ),
    );
  }

  Future<void> _openWriting({
    required BookMemorySourceType sourceType,
    String? sourceId,
    String? entryId,
    BookMemorySourcePreview? preview,
  }) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BookMemoryWritingScreen(
          bookFile: widget.bookFile,
          bookId: widget.bookId,
          settings: _s,
          sourceType: sourceType,
          sourceId: sourceId,
          entryId: entryId,
          sourcePreview: preview,
        ),
      ),
    );
    if (changed == true) _refreshMemory();
  }

  Future<void> _openSourceDetail(BookMemorySourcePreview preview) async {
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
    if (changed == true) _refreshMemory();
  }

  void _handleBack() {
    if (_activeCategory != null) {
      setState(() {
        _activeCategory = null;
        _searchController.clear();
        _selectedColorValue = null;
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = _s.isDark ? ThemeData.dark() : ThemeData.light();

    return Theme(
      data: baseTheme.copyWith(
        scaffoldBackgroundColor: _s.backgroundColor,
        colorScheme: baseTheme.colorScheme.copyWith(
          surface: _s.backgroundColor,
          onSurface: _s.textColor,
          primary: _s.accentColor,
        ),
      ),
      child: FutureBuilder<BookMemorySnapshot>(
        future: _memoryFuture,
        builder: (context, snapshot) {
          final memory = snapshot.data;
          final loadedMemory = memory ?? _emptyFallback();
          return PopScope(
            canPop: _activeCategory == null,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              _handleBack();
            },
            child: Scaffold(
              backgroundColor: _s.backgroundColor,
              appBar: AppBar(
                backgroundColor: _s.backgroundColor,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: _s.textColor),
                  tooltip: 'Back',
                  onPressed: _handleBack,
                ),
                title: Text(
                  _activeCategory?.label ?? 'Book Memory',
                  style: _s.uiText(
                    color: _s.textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.ios_share_rounded, color: _s.textColor),
                    tooltip: 'Export Markdown',
                    onPressed: memory == null
                        ? null
                        : () => _copyExport(memory),
                  ),
                ],
              ),
              body: snapshot.connectionState == ConnectionState.waiting
                  ? Center(
                      child: CircularProgressIndicator(color: _s.accentColor),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _activeCategory == null
                          ? _buildJournal(loadedMemory)
                          : _buildCategory(loadedMemory, _activeCategory!),
                    ),
              bottomNavigationBar:
                  snapshot.connectionState == ConnectionState.waiting
                  ? null
                  : _categorySelector(loadedMemory),
              floatingActionButton:
                  snapshot.connectionState == ConnectionState.waiting ||
                      _activeCategory != null
                  ? null
                  : _newBookNoteFab(loadedMemory),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.endContained,
            ),
          );
        },
      ),
    );
  }

  BookMemorySnapshot _emptyFallback() {
    return BookMemorySnapshot.empty(bookId: widget.bookId);
  }

  Widget _buildJournal(BookMemorySnapshot memory) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _bookHeader(memory),
        if (memory.recentWrittenEntries.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionLabel('Book Memory notes'),
          const SizedBox(height: 8),
          ...memory.recentWrittenEntries.map(
            (entry) => _writtenEntryTile(memory, entry),
          ),
        ],
        if (memory.totalMemoryItems == 0 && memory.entries.isEmpty) ...[
          const SizedBox(height: 14),
          _emptyState('No memory saved for this book yet.'),
        ],
        const SizedBox(height: 88),
      ],
    );
  }

  Widget _newBookNoteFab(BookMemorySnapshot memory) {
    final foreground = AppUi.foregroundFor(_s.accentColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 76),
      child: FloatingActionButton.extended(
        heroTag: 'new-book-memory-note',
        tooltip: 'New Book Note',
        backgroundColor: _s.accentColor,
        foregroundColor: foreground,
        elevation: 2,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text(
          'Note',
          style: _s.uiText(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius(16)),
        onPressed: () => _openWriting(
          sourceType: BookMemorySourceType.free,
          preview: BookMemorySourcePreview(
            sourceType: BookMemorySourceType.free,
            sourceId: null,
            title: memory.title,
            subtitle: 'Book note',
            color: _s.accentColor,
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: _s.uiText(
        color: _s.mutedColor,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _writtenEntryTile(BookMemorySnapshot memory, BookMemoryEntry entry) {
    final preview = _previewForEntry(memory, entry);
    final iconColor = preview?.color ?? _s.accentColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppUi.surfaceCard(_s),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openWriting(
            sourceType: entry.sourceType,
            sourceId: entry.sourceId,
            entryId: entry.id,
            preview: preview,
          ),
          borderRadius: AppUi.cardRadius(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.edit_note_rounded, color: iconColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title.trim().isNotEmpty
                            ? entry.title
                            : entry.body,
                        style: _s.uiText(
                          color: _s.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _entrySourceLabel(memory, entry),
                        style: _s.uiText(
                          color: _s.mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _s.mutedColor.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookHeader(BookMemorySnapshot memory) {
    final coverPath = memory.coverImagePath;
    final hasCover = coverPath != null && File(coverPath).existsSync();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppUi.surfaceCard(_s, prominent: true),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppUi.cardRadius(8),
            child: SizedBox(
              width: 72,
              height: 106,
              child: hasCover
                  ? Image.file(File(coverPath), fit: BoxFit.cover)
                  : _fallbackCover(memory),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memory.title,
                  style: _s.uiText(
                    color: _s.textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Text(
                  memory.author,
                  style: _s.uiText(
                    color: _s.mutedColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Text(
                  '${(memory.progress * 100).round()}% complete • Last read ${_formatDateMillis(memory.lastReadTime)}',
                  style: _s.uiText(
                    color: _s.mutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackCover(BookMemorySnapshot memory) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _s.accentColor.withValues(alpha: 0.14),
        border: Border.all(color: _s.accentColor.withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Text(
          memory.title.trim().isEmpty ? 'N' : memory.title.trim()[0],
          style: _s.uiText(
            color: _s.accentColor,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _categorySelector(BookMemorySnapshot memory) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _s.menuColor.withValues(alpha: _s.isDark ? 0.78 : 0.9),
            borderRadius: AppUi.cardRadius(20),
            border: Border.all(color: _s.mutedColor.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _s.isDark ? 0.22 : 0.1),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                _categoryButton(
                  memory,
                  _MemoryCategory.bookmarks,
                  Icons.bookmark_rounded,
                  memory.bookmarks.length,
                ),
                _categoryButton(
                  memory,
                  _MemoryCategory.highlights,
                  Icons.format_color_fill_rounded,
                  memory.highlights.length,
                ),
                _categoryButton(
                  memory,
                  _MemoryCategory.notes,
                  Icons.sticky_note_2_rounded,
                  memory.notes.length,
                ),
                _categoryButton(
                  memory,
                  _MemoryCategory.words,
                  Icons.translate_rounded,
                  memory.words.length,
                ),
                _categoryButton(
                  memory,
                  _MemoryCategory.characters,
                  Icons.person_search_rounded,
                  memory.characters.length,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryButton(
    BookMemorySnapshot memory,
    _MemoryCategory category,
    IconData icon,
    int count,
  ) {
    final active = _activeCategory == category;
    final foreground = active ? _s.accentColor : _s.mutedColor;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Tooltip(
          message: category.label,
          child: Semantics(
            button: true,
            label: category.label,
            child: Material(
              color: active
                  ? _s.accentColor.withValues(alpha: _s.isDark ? 0.18 : 0.12)
                  : _s.backgroundColor.withValues(
                      alpha: _s.isDark ? 0.55 : 0.8,
                    ),
              borderRadius: AppUi.cardRadius(14),
              child: InkWell(
                onTap: () => _selectCategory(category),
                borderRadius: AppUi.cardRadius(14),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: AppUi.cardRadius(14),
                    border: Border.all(
                      color: active
                          ? _s.accentColor.withValues(alpha: 0.62)
                          : _s.mutedColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(child: Icon(icon, size: 21, color: foreground)),
                      Positioned(
                        top: 5,
                        right: 6,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: active ? _s.accentColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: active
                                  ? _s.accentColor
                                  : _s.mutedColor.withValues(alpha: 0.34),
                            ),
                          ),
                          child: Text(
                            _compactCount(count),
                            textAlign: TextAlign.center,
                            style: _s.uiText(
                              color: active
                                  ? AppUi.foregroundFor(_s.accentColor)
                                  : _s.mutedColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
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
    );
  }

  void _selectCategory(_MemoryCategory category) {
    setState(() {
      _activeCategory = category;
      _searchController.clear();
      _selectedColorValue = null;
    });
  }

  String _compactCount(int count) {
    if (count > 99) return '99+';
    return '$count';
  }

  Widget _buildCategory(BookMemorySnapshot memory, _MemoryCategory category) {
    return switch (category) {
      _MemoryCategory.bookmarks => _buildBookmarks(memory),
      _MemoryCategory.highlights => _buildHighlights(memory),
      _MemoryCategory.notes => _buildNotes(memory),
      _MemoryCategory.words => _buildWords(memory),
      _MemoryCategory.characters => _buildCharacters(memory),
    };
  }

  Widget _categoryScaffold({
    required BookMemorySnapshot memory,
    required _MemoryCategory category,
    required int count,
    required Iterable<Widget> children,
  }) {
    return ListView(
      key: ValueKey(category),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _categoryPageControls(memory, category, count),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _emptyCategoryScaffold({
    required BookMemorySnapshot memory,
    required _MemoryCategory category,
    required int count,
    required String title,
    required String message,
  }) {
    return _categoryScaffold(
      memory: memory,
      category: category,
      count: count,
      children: [
        const SizedBox(height: 36),
        Icon(
          category.icon,
          color: _s.mutedColor.withValues(alpha: 0.7),
          size: 32,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: _s.uiText(
            color: _s.textColor,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 7),
        Text(
          message,
          style: _s.uiText(color: _s.mutedColor, fontSize: 13, height: 1.35),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _filteredCategoryEmpty(
    BookMemorySnapshot memory,
    _MemoryCategory category,
    int count,
  ) {
    return _categoryScaffold(
      memory: memory,
      category: category,
      count: count,
      children: [
        const SizedBox(height: 28),
        _emptyState('No matching memory items.'),
      ],
    );
  }

  Widget _buildBookmarks(BookMemorySnapshot memory) {
    final bookmarks = memory.bookmarks
        .where((bookmark) {
          final entry = memory.entryForSource(
            BookMemorySourceType.bookmark,
            bookmark.locationKey,
          );
          return _matchesQueryAndColor(
            entry: entry,
            sourceText:
                '${bookmark.name} ${memory.locationLabel(bookmark.chunkIndex)} ${bookmark.previewText ?? ''} ${_colorName(bookmark.color)}',
            color: bookmark.color,
          );
        })
        .toList(growable: false);
    _sortBookmarks(bookmarks);

    if (memory.bookmarks.isEmpty) {
      return _emptyCategoryScaffold(
        memory: memory,
        category: _MemoryCategory.bookmarks,
        count: 0,
        title: 'No bookmarks yet',
        message: 'Bookmark pages while reading to return to them here.',
      );
    }
    if (bookmarks.isEmpty) {
      return _filteredCategoryEmpty(
        memory,
        _MemoryCategory.bookmarks,
        memory.bookmarks.length,
      );
    }
    return _categoryScaffold(
      memory: memory,
      category: _MemoryCategory.bookmarks,
      count: memory.bookmarks.length,
      children: bookmarks.map((bookmark) {
        final preview = _bookmarkPreview(memory, bookmark);
        final entry = memory.entryForSource(
          BookMemorySourceType.bookmark,
          bookmark.locationKey,
        );
        return _memoryTile(
          color: bookmark.color,
          title: bookmark.name,
          subtitle: memory.locationLabel(bookmark.chunkIndex),
          body: bookmark.previewText,
          date: _formatDate(bookmark.createdAt),
          hasWriting: entry != null,
          onTap: () => _openSourceDetail(preview),
          onGoToText: () => _openChunk(
            bookmark.chunkIndex,
            originalStartOffset: bookmark.originalStartOffset,
          ),
          onWrite: () => _openWriting(
            sourceType: BookMemorySourceType.bookmark,
            sourceId: bookmark.locationKey,
            entryId: entry?.id,
            preview: preview,
          ),
        );
      }),
    );
  }

  Widget _buildHighlights(BookMemorySnapshot memory) {
    final highlights = memory.highlights
        .where((highlight) {
          final entry = memory.entryForSource(
            BookMemorySourceType.highlight,
            highlight.id,
          );
          return _matchesQueryAndColor(
            entry: entry,
            sourceText:
                '${highlight.text} ${memory.locationLabel(highlight.originalChunkIndex)} ${_colorName(highlight.color)}',
            color: highlight.color,
          );
        })
        .toList(growable: false);
    _sortHighlights(highlights);

    if (memory.highlights.isEmpty) {
      return _emptyCategoryScaffold(
        memory: memory,
        category: _MemoryCategory.highlights,
        count: 0,
        title: 'No highlights yet',
        message: 'Highlight passages to build your book memory.',
      );
    }
    if (highlights.isEmpty) {
      return _filteredCategoryEmpty(
        memory,
        _MemoryCategory.highlights,
        memory.highlights.length,
      );
    }
    return _categoryScaffold(
      memory: memory,
      category: _MemoryCategory.highlights,
      count: memory.highlights.length,
      children: highlights.map(
        (highlight) => _highlightTile(memory, highlight, title: highlight.text),
      ),
    );
  }

  Widget _buildNotes(BookMemorySnapshot memory) {
    final notes = memory.notes
        .where((note) {
          final entry = memory.entryForSource(
            BookMemorySourceType.note,
            note.id,
          );
          return _matchesQueryAndColor(
            entry: entry,
            sourceText:
                '${note.note ?? ''} ${note.text} ${memory.locationLabel(note.originalChunkIndex)} ${_colorName(note.color)}',
            color: note.color,
          );
        })
        .toList(growable: false);
    _sortHighlights(notes);

    if (memory.notes.isEmpty) {
      return _emptyCategoryScaffold(
        memory: memory,
        category: _MemoryCategory.notes,
        count: 0,
        title: 'No notes yet',
        message: 'Add notes while reading or write a book note.',
      );
    }
    if (notes.isEmpty) {
      return _filteredCategoryEmpty(
        memory,
        _MemoryCategory.notes,
        memory.notes.length,
      );
    }
    return _categoryScaffold(
      memory: memory,
      category: _MemoryCategory.notes,
      count: memory.notes.length,
      children: notes.map(
        (note) => _highlightTile(
          memory,
          note,
          title: note.note?.trim().isEmpty == false ? note.note! : 'Note',
          body: note.text,
        ),
      ),
    );
  }

  Widget _buildWords(BookMemorySnapshot memory) {
    final words = memory.words
        .where((word) {
          final entry = memory.entryForSource(
            BookMemorySourceType.word,
            word.id,
          );
          return _matchesQueryAndColor(
            entry: entry,
            sourceText:
                '${word.word} ${word.meaning} ${word.contextSentence ?? ''} ${word.originalChunkIndex == null ? '' : memory.locationLabel(word.originalChunkIndex!)}',
          );
        })
        .toList(growable: false);
    _sortWords(words);

    if (memory.words.isEmpty) {
      return _emptyCategoryScaffold(
        memory: memory,
        category: _MemoryCategory.words,
        count: 0,
        title: 'No saved words yet',
        message: 'Save definitions while reading to build your word bank.',
      );
    }
    if (words.isEmpty) {
      return _filteredCategoryEmpty(
        memory,
        _MemoryCategory.words,
        memory.words.length,
      );
    }
    return _categoryScaffold(
      memory: memory,
      category: _MemoryCategory.words,
      count: memory.words.length,
      children: words.map((word) => _wordTile(memory, word)),
    );
  }

  Widget _buildCharacters(BookMemorySnapshot memory) {
    final characters = memory.characters
        .where((character) {
          final sourceId = BookMemorySnapshot.characterSourceId(character.name);
          final entry = memory.entryForSource(
            BookMemorySourceType.character,
            sourceId,
          );
          return _matchesQueryAndColor(
            entry: entry,
            sourceText:
                '${character.name} ${character.highlights.map((item) => '${item.text} ${memory.locationLabel(item.originalChunkIndex)} ${_colorName(item.color)}').join(' ')}',
            color: character.first.color,
          );
        })
        .toList(growable: false);
    _sortCharacters(characters);

    if (memory.characters.isEmpty) {
      return _emptyCategoryScaffold(
        memory: memory,
        category: _MemoryCategory.characters,
        count: 0,
        title: 'No characters yet',
        message: 'Tag names while reading to build a character map.',
      );
    }
    if (characters.isEmpty) {
      return _filteredCategoryEmpty(
        memory,
        _MemoryCategory.characters,
        memory.characters.length,
      );
    }
    return _categoryScaffold(
      memory: memory,
      category: _MemoryCategory.characters,
      count: memory.characters.length,
      children: characters.map((character) {
        final preview = _characterPreview(memory, character);
        final sourceId = BookMemorySnapshot.characterSourceId(character.name);
        final entry = memory.entryForSource(
          BookMemorySourceType.character,
          sourceId,
        );
        return _memoryTile(
          color: character.first.color,
          title: character.name,
          subtitle:
              '${character.count} marked moment${character.count == 1 ? '' : 's'}'
              '${character.occurrenceCount > 0 ? ' • ${character.occurrenceCount} mention${character.occurrenceCount == 1 ? '' : 's'}' : ''}',
          body: _characterCardBody(memory, character),
          date: _formatDate(character.latestMarked.createdAt),
          hasWriting: entry != null,
          onTap: () => _openSourceDetail(preview),
          onGoToText: () => _openChunk(
            character.firstMarked.originalChunkIndex,
            originalStartOffset: character.firstMarked.startOffset,
          ),
          onWrite: () => _openWriting(
            sourceType: BookMemorySourceType.character,
            sourceId: sourceId,
            entryId: entry?.id,
            preview: preview,
          ),
        );
      }),
    );
  }

  Widget _highlightTile(
    BookMemorySnapshot memory,
    Highlight highlight, {
    required String title,
    String? body,
  }) {
    final type = highlight.hasNote
        ? BookMemorySourceType.note
        : BookMemorySourceType.highlight;
    final preview = _highlightPreview(
      memory,
      highlight,
      sourceType: type,
      title: title,
      body: body,
    );
    final entry = memory.entryForSource(type, highlight.id);
    return _memoryTile(
      color: highlight.color,
      title: title,
      subtitle: memory.locationLabel(highlight.originalChunkIndex),
      body: body,
      date: _formatDate(highlight.createdAt),
      hasWriting: entry != null,
      onTap: () => _openSourceDetail(preview),
      onGoToText: () => _openChunk(
        highlight.originalChunkIndex,
        originalStartOffset: highlight.startOffset,
      ),
      onWrite: () => _openWriting(
        sourceType: type,
        sourceId: highlight.id,
        entryId: entry?.id,
        preview: preview,
      ),
    );
  }

  Widget _wordTile(BookMemorySnapshot memory, SavedWord word) {
    final hasLocation = word.originalChunkIndex != null;
    final preview = _wordPreview(memory, word);
    final entry = memory.entryForSource(BookMemorySourceType.word, word.id);
    return _memoryTile(
      color: _s.accentColor,
      title: word.word,
      subtitle: hasLocation
          ? memory.locationLabel(word.originalChunkIndex!)
          : 'No saved location',
      body: word.meaning,
      date: _formatDateMillis(word.timestamp),
      hasWriting: entry != null,
      onTap: () => _openSourceDetail(preview),
      onGoToText: hasLocation
          ? () => _openChunk(
              word.originalChunkIndex,
              originalStartOffset: word.originalStartOffset,
            )
          : null,
      onWrite: () => _openWriting(
        sourceType: BookMemorySourceType.word,
        sourceId: word.id,
        entryId: entry?.id,
        preview: preview,
      ),
    );
  }

  Widget _categoryPageControls(
    BookMemorySnapshot memory,
    _MemoryCategory category,
    int count,
  ) {
    final colorOptions = _activeColorOptions(memory, category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count saved',
          style: _s.uiText(
            color: _s.mutedColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          style: _s.uiText(color: _s.textColor, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Search memory',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: AppUi.cardRadius(12),
              borderSide: BorderSide(
                color: _s.mutedColor.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (category.supportsColor) ...[
              PopupMenuButton<int?>(
                tooltip: 'Filter color',
                initialValue: _selectedColorValue,
                onSelected: (value) =>
                    setState(() => _selectedColorValue = value),
                itemBuilder: (context) => [
                  const PopupMenuItem<int?>(child: Text('All colors')),
                  for (final colorValue in colorOptions)
                    PopupMenuItem<int?>(
                      value: colorValue,
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Color(colorValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(_colorName(Color(colorValue))),
                        ],
                      ),
                    ),
                ],
                child: _controlPill(
                  icon: Icons.palette_outlined,
                  label: _selectedColorValue == null
                      ? 'All colors'
                      : _colorName(Color(_selectedColorValue!)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            PopupMenuButton<_MemorySort>(
              tooltip: 'Sort',
              initialValue: _memorySort,
              onSelected: (value) => setState(() => _memorySort = value),
              itemBuilder: (context) => _MemorySort.values
                  .map(
                    (sort) =>
                        PopupMenuItem(value: sort, child: Text(sort.label)),
                  )
                  .toList(),
              child: _controlPill(
                icon: Icons.sort_rounded,
                label: _memorySort.shortLabel,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _controlPill({required IconData icon, required String label}) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _s.mutedColor.withValues(alpha: 0.08),
        borderRadius: AppUi.cardRadius(999),
        border: Border.all(color: _s.mutedColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _s.mutedColor, size: 17),
          const SizedBox(width: 5),
          Text(
            label,
            style: _s.uiText(
              color: _s.textColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesQueryAndColor({
    required BookMemoryEntry? entry,
    required String sourceText,
    Color? color,
  }) {
    if (_selectedColorValue != null &&
        (color == null || color.toARGB32() != _selectedColorValue)) {
      return false;
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      sourceText,
      entry?.title ?? '',
      entry?.body ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  List<int> _activeColorOptions(
    BookMemorySnapshot memory,
    _MemoryCategory category,
  ) {
    final colors = <int>{};
    switch (category) {
      case _MemoryCategory.bookmarks:
        colors.addAll(memory.bookmarks.map((item) => item.color.toARGB32()));
      case _MemoryCategory.highlights:
        colors.addAll(memory.highlights.map((item) => item.color.toARGB32()));
      case _MemoryCategory.notes:
        colors.addAll(memory.notes.map((item) => item.color.toARGB32()));
      case _MemoryCategory.characters:
        colors.addAll(
          memory.characters.map((item) => item.first.color.toARGB32()),
        );
      case _MemoryCategory.words:
        break;
    }
    final sorted = colors.toList()..sort();
    return sorted;
  }

  String _colorName(Color color) {
    final value = color.toARGB32();
    const names = <int, String>{
      0xFFE1306C: 'Pink',
      0xFF4FC3F7: 'Blue',
      0xFFFFB74D: 'Amber',
      0xFF81C784: 'Green',
      0xFFCE93D8: 'Purple',
      0xFFFFD54F: 'Yellow',
      0xFFFF8A65: 'Orange',
      0xFFEF5350: 'Red',
    };
    return names[value] ??
        '#${value.toRadixString(16).substring(2).toUpperCase()}';
  }

  void _sortBookmarks(List<Bookmark> bookmarks) {
    switch (_memorySort) {
      case _MemorySort.readingOrder:
        bookmarks.sort((a, b) {
          final chunk = a.chunkIndex.compareTo(b.chunkIndex);
          if (chunk != 0) return chunk;
          return a.originalStartOffset.compareTo(b.originalStartOffset);
        });
      case _MemorySort.newest:
        bookmarks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _MemorySort.oldest:
        bookmarks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  void _sortHighlights(List<Highlight> highlights) {
    switch (_memorySort) {
      case _MemorySort.readingOrder:
        highlights.sort((a, b) {
          final chunk = a.originalChunkIndex.compareTo(b.originalChunkIndex);
          if (chunk != 0) return chunk;
          return a.startOffset.compareTo(b.startOffset);
        });
      case _MemorySort.newest:
        highlights.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _MemorySort.oldest:
        highlights.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  void _sortWords(List<SavedWord> words) {
    switch (_memorySort) {
      case _MemorySort.readingOrder:
        words.sort((a, b) {
          final aChunk = a.originalChunkIndex ?? 1 << 30;
          final bChunk = b.originalChunkIndex ?? 1 << 30;
          final chunk = aChunk.compareTo(bChunk);
          if (chunk != 0) return chunk;
          return (a.originalStartOffset ?? 0).compareTo(
            b.originalStartOffset ?? 0,
          );
        });
      case _MemorySort.newest:
        words.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      case _MemorySort.oldest:
        words.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
  }

  void _sortCharacters(List<CharacterMemoryGroup> characters) {
    switch (_memorySort) {
      case _MemorySort.readingOrder:
        characters.sort((a, b) {
          final chunk = a.firstMarked.originalChunkIndex.compareTo(
            b.firstMarked.originalChunkIndex,
          );
          if (chunk != 0) return chunk;
          return a.firstMarked.startOffset.compareTo(b.firstMarked.startOffset);
        });
      case _MemorySort.newest:
        characters.sort(
          (a, b) =>
              b.latestMarked.createdAt.compareTo(a.latestMarked.createdAt),
        );
      case _MemorySort.oldest:
        characters.sort(
          (a, b) =>
              a.oldestMarked.createdAt.compareTo(b.oldestMarked.createdAt),
        );
    }
  }

  BookMemorySourcePreview _bookmarkPreview(
    BookMemorySnapshot memory,
    Bookmark bookmark,
  ) {
    return BookMemorySourcePreview(
      sourceType: BookMemorySourceType.bookmark,
      sourceId: bookmark.locationKey,
      title: bookmark.name,
      subtitle: memory.locationLabel(bookmark.chunkIndex),
      body: bookmark.previewText,
      date: _formatDate(bookmark.createdAt),
      color: bookmark.color,
      originalChunkIndex: bookmark.chunkIndex,
    );
  }

  BookMemorySourcePreview _highlightPreview(
    BookMemorySnapshot memory,
    Highlight highlight, {
    required BookMemorySourceType sourceType,
    required String title,
    String? body,
  }) {
    return BookMemorySourcePreview(
      sourceType: sourceType,
      sourceId: highlight.id,
      title: title,
      subtitle: memory.locationLabel(highlight.originalChunkIndex),
      body: body ?? highlight.text,
      date: _formatDate(highlight.createdAt),
      color: highlight.color,
      originalChunkIndex: highlight.originalChunkIndex,
      details: sourceType == BookMemorySourceType.note
          ? ['Selected text: ${highlight.text}']
          : const [],
    );
  }

  BookMemorySourcePreview _wordPreview(
    BookMemorySnapshot memory,
    SavedWord word,
  ) {
    final location = word.originalChunkIndex == null
        ? 'No saved location'
        : memory.locationLabel(word.originalChunkIndex!);
    return BookMemorySourcePreview(
      sourceType: BookMemorySourceType.word,
      sourceId: word.id,
      title: word.word,
      subtitle: location,
      body: word.contextSentence?.trim().isNotEmpty == true
          ? '${word.meaning}\n\n${word.contextSentence}'
          : word.meaning,
      date: _formatDateMillis(word.timestamp),
      color: _s.accentColor,
      originalChunkIndex: word.originalChunkIndex,
    );
  }

  BookMemorySourcePreview _characterPreview(
    BookMemorySnapshot memory,
    CharacterMemoryGroup character,
  ) {
    final linkedCount = character.linkedInputCount;
    final detailItems = _characterDetailItems(memory, character);
    return BookMemorySourcePreview(
      sourceType: BookMemorySourceType.character,
      sourceId: BookMemorySnapshot.characterSourceId(character.name),
      title: character.name,
      subtitle:
          '${character.count} marked moment${character.count == 1 ? '' : 's'}',
      body:
          'First marked: ${memory.locationLabel(character.firstMarked.originalChunkIndex)}',
      date: _formatDate(character.latestMarked.createdAt),
      color: character.first.color,
      originalChunkIndex: character.firstMarked.originalChunkIndex,
      details: [
        'Occurrences',
        'First occurrence: ${_characterOccurrenceLabel(memory, character.firstOccurrence)}',
        'Marked occurrences',
        ...character.highlights.map(
          (highlight) =>
              '${memory.locationLabel(highlight.originalChunkIndex)}: ${highlight.text}',
        ),
        'Last occurrence: ${_characterOccurrenceLabel(memory, character.lastOccurrence)}',
        if (linkedCount > 0) ...[
          'Linked highlights and notes',
          ...character.linkedHighlights.map(
            (highlight) =>
                'Highlight - ${memory.locationLabel(highlight.originalChunkIndex)}: ${highlight.text}',
          ),
          ...character.linkedNotes.map(
            (note) =>
                'Note - ${memory.locationLabel(note.originalChunkIndex)}: ${note.text}',
          ),
        ],
      ],
      detailItems: detailItems,
    );
  }

  List<BookMemoryDetailItem> _characterDetailItems(
    BookMemorySnapshot memory,
    CharacterMemoryGroup character,
  ) {
    final items = <BookMemoryDetailItem>[
      BookMemoryDetailItem(
        section: 'Occurrences',
        label: 'First occurrence',
        text: _characterOccurrenceLabel(memory, character.firstOccurrence),
        originalChunkIndex: _visibleOccurrenceChunk(
          memory,
          character.firstOccurrence,
        ),
        originalStartOffset: character.firstOccurrence?.startOffset,
        spoilerProtected: _isFutureOccurrence(
          memory,
          character.firstOccurrence,
        ),
      ),
      BookMemoryDetailItem(
        section: 'Occurrences',
        label: 'Mention count',
        text: character.occurrenceCount <= 0
            ? 'Not available yet'
            : '${character.occurrenceCount} mention${character.occurrenceCount == 1 ? '' : 's'} found',
      ),
      ...character.highlights.map(
        (highlight) => BookMemoryDetailItem(
          section: 'Marked occurrences',
          label: memory.locationLabel(highlight.originalChunkIndex),
          text: highlight.text,
          sourceType: BookMemorySourceType.character,
          sourceId: highlight.id,
          originalChunkIndex: highlight.originalChunkIndex,
          originalStartOffset: highlight.startOffset,
        ),
      ),
      BookMemoryDetailItem(
        section: 'Occurrences',
        label: 'Last occurrence',
        text: character.lastOccurrence == null
            ? _characterOccurrenceLabel(memory, character.lastOccurrence)
            : memory.locationLabel(character.lastOccurrence!.chunkIndex),
        originalChunkIndex: character.lastOccurrence?.chunkIndex,
        originalStartOffset: character.lastOccurrence?.startOffset,
        spoilerProtected: character.lastOccurrence != null,
      ),
      ...character.linkedHighlights.map(
        (highlight) => BookMemoryDetailItem(
          section: 'Linked highlights',
          label: memory.locationLabel(highlight.originalChunkIndex),
          text: highlight.text,
          sourceType: BookMemorySourceType.highlight,
          sourceId: highlight.id,
          originalChunkIndex: highlight.originalChunkIndex,
          originalStartOffset: highlight.startOffset,
          sourcePreview: _highlightPreview(
            memory,
            highlight,
            sourceType: BookMemorySourceType.highlight,
            title: highlight.text,
          ),
        ),
      ),
      ...character.linkedNotes.map(
        (note) => BookMemoryDetailItem(
          section: 'Linked notes',
          label: memory.locationLabel(note.originalChunkIndex),
          text: note.text,
          sourceType: BookMemorySourceType.note,
          sourceId: note.id,
          originalChunkIndex: note.originalChunkIndex,
          originalStartOffset: note.startOffset,
          sourcePreview: _highlightPreview(
            memory,
            note,
            sourceType: BookMemorySourceType.note,
            title: note.note?.trim().isEmpty == false ? note.note! : 'Note',
            body: note.text,
          ),
        ),
      ),
    ];
    return items;
  }

  String _characterCardBody(
    BookMemorySnapshot memory,
    CharacterMemoryGroup character,
  ) {
    final parts = [
      'First marked: ${memory.locationLabel(character.firstMarked.originalChunkIndex)}',
      if (character.linkedInputCount > 0)
        '${character.linkedInputCount} linked highlight${character.linkedInputCount == 1 ? '' : 's'}/notes',
    ];
    return parts.join('\n');
  }

  String _characterOccurrenceLabel(
    BookMemorySnapshot memory,
    CharacterOccurrencePosition? position,
  ) {
    if (position == null) return 'Not found in cached text';
    if (position.chunkIndex > memory.lastReadIndex) {
      return 'Found later in the book';
    }
    return memory.locationLabel(position.chunkIndex);
  }

  bool _isFutureOccurrence(
    BookMemorySnapshot memory,
    CharacterOccurrencePosition? position,
  ) {
    return position != null && position.chunkIndex > memory.lastReadIndex;
  }

  int? _visibleOccurrenceChunk(
    BookMemorySnapshot memory,
    CharacterOccurrencePosition? position,
  ) {
    if (_isFutureOccurrence(memory, position)) return null;
    return position?.chunkIndex;
  }

  BookMemorySourcePreview? _previewForEntry(
    BookMemorySnapshot memory,
    BookMemoryEntry entry,
  ) {
    final sourceId = entry.sourceId;
    if (entry.sourceType == BookMemorySourceType.free || sourceId == null) {
      return BookMemorySourcePreview(
        sourceType: BookMemorySourceType.free,
        sourceId: null,
        title: memory.title,
        subtitle: 'Book note',
        color: _s.accentColor,
      );
    }

    switch (entry.sourceType) {
      case BookMemorySourceType.bookmark:
        for (final bookmark in memory.bookmarks) {
          if (bookmark.locationKey == sourceId) {
            return _bookmarkPreview(memory, bookmark);
          }
        }
      case BookMemorySourceType.highlight:
        for (final highlight in memory.highlights) {
          if (highlight.id == sourceId) {
            return _highlightPreview(
              memory,
              highlight,
              sourceType: BookMemorySourceType.highlight,
              title: highlight.text,
            );
          }
        }
      case BookMemorySourceType.note:
        for (final note in memory.notes) {
          if (note.id == sourceId) {
            return _highlightPreview(
              memory,
              note,
              sourceType: BookMemorySourceType.note,
              title: note.note?.trim().isEmpty == false ? note.note! : 'Note',
              body: note.text,
            );
          }
        }
      case BookMemorySourceType.word:
        for (final word in memory.words) {
          if (word.id == sourceId) return _wordPreview(memory, word);
        }
      case BookMemorySourceType.character:
        for (final character in memory.characters) {
          if (BookMemorySnapshot.characterSourceId(character.name) ==
              sourceId) {
            return _characterPreview(memory, character);
          }
        }
      case BookMemorySourceType.free:
        break;
    }

    return BookMemorySourcePreview(
      sourceType: entry.sourceType,
      sourceId: sourceId,
      title: 'Source no longer available',
      subtitle: _entryTypeLabel(entry.sourceType),
      color: _s.mutedColor,
    );
  }

  String _entrySourceLabel(BookMemorySnapshot memory, BookMemoryEntry entry) {
    final preview = _previewForEntry(memory, entry);
    if (entry.sourceType == BookMemorySourceType.free) return 'Book note';
    if (preview == null || preview.title == 'Source no longer available') {
      return '${_entryTypeLabel(entry.sourceType)} • source no longer available';
    }
    return '${_entryTypeLabel(entry.sourceType)} • ${preview.title}';
  }

  String _entryTypeLabel(BookMemorySourceType type) {
    return switch (type) {
      BookMemorySourceType.bookmark => 'Bookmark',
      BookMemorySourceType.highlight => 'Highlight',
      BookMemorySourceType.note => 'Reader note',
      BookMemorySourceType.word => 'Saved word',
      BookMemorySourceType.character => 'Character',
      BookMemorySourceType.free => 'Book note',
    };
  }

  Widget _memoryTile({
    required Color color,
    required String title,
    required String subtitle,
    required String date,
    String? body,
    bool hasWriting = false,
    VoidCallback? onTap,
    VoidCallback? onGoToText,
    VoidCallback? onWrite,
  }) {
    final cleanBody = body?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppUi.surfaceCard(_s),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppUi.cardRadius(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: _s.uiText(
                          color: _s.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$subtitle • $date',
                        style: _s.uiText(
                          color: _s.mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (cleanBody != null && cleanBody.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Text(
                          cleanBody,
                          style: _s.uiText(
                            color: _s.textColor.withValues(alpha: 0.82),
                            fontSize: 13,
                            height: 1.35,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        hasWriting
                            ? Icons.edit_note_rounded
                            : Icons.edit_note_outlined,
                        color: hasWriting ? _s.accentColor : _s.mutedColor,
                        size: 20,
                      ),
                      tooltip: hasWriting ? 'Edit writing' : 'Write',
                      onPressed: onWrite,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(
                        onGoToText == null
                            ? Icons.location_disabled_outlined
                            : Icons.short_text_rounded,
                        color: _s.mutedColor.withValues(alpha: 0.75),
                        size: 20,
                      ),
                      tooltip: onGoToText == null
                          ? 'No saved location'
                          : 'Go to text',
                      onPressed: onGoToText,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          text,
          style: _s.uiText(
            color: _s.mutedColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDateMillis(int? millis) {
    if (millis == null || millis <= 0) return 'Never';
    return _formatDate(DateTime.fromMillisecondsSinceEpoch(millis));
  }
}

enum _MemoryCategory { bookmarks, highlights, notes, words, characters }

extension _MemoryCategoryLabel on _MemoryCategory {
  String get label {
    return switch (this) {
      _MemoryCategory.bookmarks => 'Bookmarks',
      _MemoryCategory.highlights => 'Highlights',
      _MemoryCategory.notes => 'Notes',
      _MemoryCategory.words => 'Words',
      _MemoryCategory.characters => 'Characters',
    };
  }

  IconData get icon {
    return switch (this) {
      _MemoryCategory.bookmarks => Icons.bookmark_rounded,
      _MemoryCategory.highlights => Icons.format_color_fill_rounded,
      _MemoryCategory.notes => Icons.sticky_note_2_rounded,
      _MemoryCategory.words => Icons.translate_rounded,
      _MemoryCategory.characters => Icons.person_search_rounded,
    };
  }

  bool get supportsColor {
    return switch (this) {
      _MemoryCategory.bookmarks ||
      _MemoryCategory.highlights ||
      _MemoryCategory.notes ||
      _MemoryCategory.characters => true,
      _MemoryCategory.words => false,
    };
  }
}

enum _MemorySort { newest, oldest, readingOrder }

extension _MemorySortLabel on _MemorySort {
  String get label {
    return switch (this) {
      _MemorySort.newest => 'Recently marked',
      _MemorySort.oldest => 'Oldest marked',
      _MemorySort.readingOrder => 'Reading order',
    };
  }

  String get shortLabel {
    return switch (this) {
      _MemorySort.newest => 'Newest',
      _MemorySort.oldest => 'Oldest',
      _MemorySort.readingOrder => 'Reading',
    };
  }
}
