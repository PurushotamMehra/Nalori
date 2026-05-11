import 'package:flutter/material.dart';

import '../models/highlight.dart';
import '../models/reading_settings.dart';
import '../services/dictionary_service.dart';
import 'highlight_palette_sheet.dart';
import 'note_sheets.dart';

/// A bottom-sheet panel for "Highlights", "Notes", and "Dictionary".
///
/// Previously called NavigationPanel and also included Bookmarks.
/// Bookmarks have been moved to ChapterPanel (side drawer).
/// The Notes tab is a placeholder for a future feature.
class AnnotationsPanel extends StatefulWidget {
  final int currentPage;

  /// Maps original chunk index → display page index.
  final Map<int, int> originalToDisplay;

  /// Total number of display pages (for "Page X of Y" labels).
  final int totalDisplayPages;

  /// Chunk text content indexed by original chunk index.
  /// Used for highlight context previews.
  final Map<int, String> chunkTexts;

  /// Builds the storage location label for highlights and notes.
  final String Function(int originalChunkIndex)? buildLocationLabel;

  final ValueChanged<int> onNavigate;

  // ── Highlights ──
  final List<Highlight> highlights;
  final Function(String id)? onRemoveHighlight;
  final Function(Highlight hl, Color color)? onChangeHighlightColor;
  final List<Color> highlightPalette;
  final Future<List<Color>> Function(Color color)? onAddCustomColor;
  final Future<List<Color>> Function(Color color)? onRemoveCustomColor;
  final Future<List<Color>> Function()? onResetHighlightPalette;
  final Function(String id, String note)? onNoteUpdated;
  final Function(String id)? onNoteRemoved;
  final DictionaryService dictionaryService;
  final ReadingSettings? settings;

  const AnnotationsPanel({
    super.key,
    required this.currentPage,
    required this.originalToDisplay,
    required this.totalDisplayPages,
    this.chunkTexts = const {},
    this.buildLocationLabel,
    required this.onNavigate,
    required this.highlights,
    this.onRemoveHighlight,
    this.onChangeHighlightColor,
    this.highlightPalette = kHighlightColors,
    this.onAddCustomColor,
    this.onRemoveCustomColor,
    this.onResetHighlightPalette,
    this.onNoteUpdated,
    this.onNoteRemoved,
    required this.dictionaryService,
    this.settings,
  });

  /// Convenience entry point — show as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required int currentPage,
    required Map<int, int> originalToDisplay,
    required int totalDisplayPages,
    Map<int, String> chunkTexts = const {},
    String Function(int originalChunkIndex)? buildLocationLabel,
    required ValueChanged<int> onNavigate,
    List<Highlight> highlights = const [],
    Function(String id)? onRemoveHighlight,
    Function(Highlight hl, Color color)? onChangeHighlightColor,
    List<Color> highlightPalette = kHighlightColors,
    Future<List<Color>> Function(Color color)? onAddCustomColor,
    Future<List<Color>> Function(Color color)? onRemoveCustomColor,
    Future<List<Color>> Function()? onResetHighlightPalette,
    Function(String id, String note)? onNoteUpdated,
    Function(String id)? onNoteRemoved,
    required DictionaryService dictionaryService,
    ReadingSettings? settings,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AnnotationsPanel(
        currentPage: currentPage,
        originalToDisplay: originalToDisplay,
        totalDisplayPages: totalDisplayPages,
        chunkTexts: chunkTexts,
        buildLocationLabel: buildLocationLabel,
        onNavigate: (index) {
          Navigator.pop(context); // close sheet first
          onNavigate(index);
        },
        highlights: highlights,
        onRemoveHighlight: onRemoveHighlight,
        onChangeHighlightColor: onChangeHighlightColor,
        highlightPalette: highlightPalette,
        onAddCustomColor: onAddCustomColor,
        onRemoveCustomColor: onRemoveCustomColor,
        onResetHighlightPalette: onResetHighlightPalette,
        onNoteUpdated: onNoteUpdated,
        onNoteRemoved: onNoteRemoved,
        dictionaryService: dictionaryService,
        settings: settings,
      ),
    );
  }

  @override
  State<AnnotationsPanel> createState() => _AnnotationsPanelState();
}

class _AnnotationsPanelState extends State<AnnotationsPanel> {
  // ── Local highlight state for immediate UI updates ──
  late List<Highlight> _localHighlights;
  late List<Color> _highlightPalette;
  late _PanelColors _themeColors;

  // ── Search filters ──
  final _highlightSearchController = TextEditingController();
  final _notesSearchController = TextEditingController();
  final _dictionarySearchController = TextEditingController();
  String _highlightFilter = '';
  String _notesFilter = '';
  String _dictionaryFilter = '';

  // ── Highlight specific filters ──
  final Set<int> _selectedColorFilters = {};
  bool _filterByCharacter = false;

  @override
  void initState() {
    super.initState();
    _localHighlights = List.from(widget.highlights);
    _highlightPalette = widget.highlightPalette.map((color) {
      return Color(highlightColorValue(color));
    }).toList();

    _highlightSearchController.addListener(() {
      setState(
        () => _highlightFilter = _highlightSearchController.text.toLowerCase(),
      );
    });
    _notesSearchController.addListener(() {
      setState(() => _notesFilter = _notesSearchController.text.toLowerCase());
    });
    _dictionarySearchController.addListener(() {
      setState(
        () =>
            _dictionaryFilter = _dictionarySearchController.text.toLowerCase(),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeColors = _PanelColors.fromReaderTheme(Theme.of(context));
  }

  _PanelColors get _colors => widget.settings != null
      ? _PanelColors.fromSettings(widget.settings!)
      : _themeColors;

  @override
  void dispose() {
    _highlightSearchController.dispose();
    _notesSearchController.dispose();
    _dictionarySearchController.dispose();
    super.dispose();
  }

  List<Highlight> _collapseLogicalAnnotations(Iterable<Highlight> highlights) {
    final grouped = <String, List<Highlight>>{};
    for (final highlight in highlights) {
      grouped.putIfAbsent(highlight.id, () => <Highlight>[]).add(highlight);
    }

    final collapsed = <Highlight>[];
    for (final group in grouped.values) {
      group.sort((a, b) {
        final chunkCompare = a.originalChunkIndex.compareTo(
          b.originalChunkIndex,
        );
        if (chunkCompare != 0) return chunkCompare;
        final startCompare = a.startOffset.compareTo(b.startOffset);
        if (startCompare != 0) return startCompare;
        return a.endOffset.compareTo(b.endOffset);
      });

      final primary = group.first;
      final textSegments = <String>[];
      for (final item in group) {
        final trimmed = item.text.trim();
        if (trimmed.isEmpty || textSegments.contains(trimmed)) continue;
        textSegments.add(trimmed);
      }
      final combinedText = textSegments.isEmpty
          ? primary.text
          : textSegments.join('\n\n');
      final noteText = group
          .map((item) => item.note?.trim())
          .whereType<String>()
          .firstWhere(
            (item) => item.isNotEmpty,
            orElse: () => primary.note ?? '',
          );

      collapsed.add(
        primary.copyWith(
          text: combinedText,
          note: noteText.isEmpty ? null : noteText,
        ),
      );
    }

    return collapsed;
  }

  List<Highlight> get _visibleHighlights => _collapseLogicalAnnotations(
    _localHighlights.where((hl) => !hl.isNote && !hl.hasNote),
  );

  List<Highlight> get _visibleNotes =>
      _collapseLogicalAnnotations(_localHighlights.where((hl) => hl.hasNote));

  List<Color> get _availableFilterColors {
    final colors = <Color>[];
    final seen = <int>{};
    final source = _filterByCharacter
        ? _visibleHighlights.where((highlight) => highlight.isCharacter)
        : _visibleHighlights;
    for (final highlight in source) {
      final value = highlight.resolvedColorValue;
      if (!seen.add(value)) continue;
      colors.add(Color(value));
    }
    return colors;
  }

  /// Calculates a human-readable page label.
  String _displayPageLabel(int originalChunkIndex) {
    final customLabel = widget.buildLocationLabel?.call(originalChunkIndex);
    if (customLabel != null && customLabel.isNotEmpty) {
      return customLabel;
    }
    final displayIdx = widget.originalToDisplay[originalChunkIndex];
    if (displayIdx != null) {
      return 'Page ${displayIdx + 1} of ${widget.totalDisplayPages}';
    }
    return 'Page ${originalChunkIndex + 1}';
  }

  /// Get surrounding context for a highlight.
  String? _getHighlightContext(Highlight hl, {int contextChars = 20}) {
    final text = widget.chunkTexts[hl.originalChunkIndex];
    if (text == null || text.isEmpty) return null;

    final start = (hl.startOffset - contextChars).clamp(0, text.length);
    final end = (hl.endOffset + contextChars).clamp(0, text.length);

    final before = start > 0 ? '…' : '';
    final after = end < text.length ? '…' : '';

    final snippet = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
    return '$before$snippet$after';
  }

  String _searchableHighlightText(Highlight hl) {
    return [
      hl.text,
      _getHighlightContext(hl, contextChars: 48) ?? '',
      _displayPageLabel(hl.originalChunkIndex),
      if (hl.isCharacter) hl.text,
    ].join(' ').toLowerCase();
  }

  String? _supportingHighlightContext(Highlight hl) {
    final context = _getHighlightContext(hl);
    if (context == null) return null;
    final title = hl.text.trim();
    if (title.isEmpty) return context;
    final normalizedContext = _normalizePreviewText(context);
    final normalizedTitle = _normalizePreviewText(title);
    if (normalizedContext.isEmpty || normalizedTitle.isEmpty) return null;
    if (normalizedContext == normalizedTitle) return null;
    if (normalizedContext.contains(normalizedTitle) &&
        normalizedContext.length - normalizedTitle.length < 24) {
      return null;
    }
    return context;
  }

  String _normalizePreviewText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[“”"‘’…]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _removeLocalHighlight(String id) {
    setState(() {
      _localHighlights.removeWhere((h) => h.id == id);
      _clearMissingSelectedColor();
    });
  }

  void _clearMissingSelectedColor() {
    if (_selectedColorFilters.isEmpty) return;
    final available = _availableFilterColors.map(highlightColorValue).toSet();
    _selectedColorFilters.removeWhere((color) => !available.contains(color));
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return DefaultTabController(
      length: 3,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.secondaryText.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Tab bar
            TabBar(
              labelColor: colors.text,
              unselectedLabelColor: colors.secondaryText,
              indicatorColor: colors.accent,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: 'Highlights'),
                Tab(text: 'Notes'),
                Tab(text: 'Dictionary'),
              ],
            ),
            Divider(height: 1, color: colors.divider),
            // Tab views
            Expanded(
              child: TabBarView(
                children: [
                  _buildHighlightsList(),
                  _buildNotesList(),
                  _buildDictionaryList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Highlights Tab ─────────────────────────────────────────────────

  Widget _buildHighlightsList() {
    final visibleHighlights = _visibleHighlights;
    if (visibleHighlights.isEmpty) {
      return _buildEmptyState(
        icon: Icons.highlight_rounded,
        title: 'No highlights yet',
        message: 'Select text while reading to create highlights.',
      );
    }

    // Sort newest first
    final sorted = List<Highlight>.from(visibleHighlights)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final characterHighlights = sorted.where((hl) => hl.isCharacter).toList();
    final modeScoped = _filterByCharacter ? characterHighlights : sorted;
    // Filter highlights by search query, color, and character
    final filtered = modeScoped.where((hl) {
      final matchesColor =
          _selectedColorFilters.isEmpty ||
          _selectedColorFilters.contains(hl.resolvedColorValue);
      final matchesSearch =
          _highlightFilter.isEmpty ||
          _searchableHighlightText(hl).contains(_highlightFilter);

      return matchesColor && matchesSearch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _highlightSearchController,
            style: TextStyle(fontSize: 13, color: _colors.text),
            decoration: InputDecoration(
              hintText: 'Search highlights…',
              hintStyle: TextStyle(fontSize: 13, color: _colors.tertiaryText),
              prefixIcon: Icon(
                Icons.search,
                size: 18,
                color: _colors.tertiaryText,
              ),
              suffixIcon: _highlightFilter.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: _colors.secondaryText,
                      ),
                      onPressed: () => _highlightSearchController.clear(),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 12,
              ),
              filled: true,
              fillColor: _colors.controlSurface.withValues(alpha: 0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Color & Character Filters
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterPill(
                  label: 'All',
                  icon: Icons.layers_rounded,
                  selected:
                      !_filterByCharacter && _selectedColorFilters.isEmpty,
                  colors: _colors,
                  onTap: () {
                    setState(() {
                      _filterByCharacter = false;
                      _selectedColorFilters.clear();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Characters',
                  icon: Icons.person_rounded,
                  selected: _filterByCharacter,
                  colors: _colors,
                  onTap: () {
                    setState(() {
                      _filterByCharacter = true;
                      final nextColorValues = _availableFilterColors
                          .map(highlightColorValue)
                          .toSet();
                      _selectedColorFilters.removeWhere(
                        (color) => !nextColorValues.contains(color),
                      );
                    });
                  },
                ),
                if (_filterByCharacter || _selectedColorFilters.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: 'Clear',
                    icon: Icons.clear_all_rounded,
                    selected: false,
                    colors: _colors,
                    onTap: () {
                      setState(() {
                        _filterByCharacter = false;
                        _selectedColorFilters.clear();
                      });
                    },
                  ),
                ],
                const SizedBox(width: 12),
                ..._availableFilterColors.map((color) {
                  final colorValue = highlightColorValue(color);
                  final isSelected = _selectedColorFilters.contains(colorValue);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedColorFilters.remove(colorValue);
                        } else {
                          _selectedColorFilters.add(colorValue);
                        }
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 9),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? _colors.text
                              : _colors.text.withValues(alpha: 0.45),
                          width: isSelected ? 2.2 : 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.22),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: isSelected
                          ? Icon(Icons.check, color: _colors.surface, size: 16)
                          : null,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        Expanded(
          child: _filterByCharacter && characterHighlights.isEmpty
              ? _buildEmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'No character highlights yet',
                  message:
                      'Tag a name while reading to build your character map.',
                )
              : filtered.isEmpty
              ? _buildEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching highlights',
                  message: 'Try a different search or filter.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _buildHighlightRow(context, filtered[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildHighlightRow(BuildContext context, Highlight hl) {
    final pageLabel = _displayPageLabel(hl.originalChunkIndex);
    final contextText = _supportingHighlightContext(hl);
    final title = hl.isCharacter ? hl.text.trim() : '"${hl.text.trim()}"';

    return Dismissible(
      key: ValueKey('highlight-${hl.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.78),
          size: 19,
        ),
      ),
      onDismissed: (_) {
        _removeLocalHighlight(hl.id);
        widget.onRemoveHighlight?.call(hl.id);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onNavigate(hl.originalChunkIndex),
          onLongPress: () => _showColorPicker(context, hl),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(0, 10, 8, 10),
            decoration: BoxDecoration(
              color: _colors.controlSurface.withValues(
                alpha: _colors.isDark ? 0.22 : 0.34,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _colors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 58,
                  decoration: BoxDecoration(
                    color: hl.color,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Untitled highlight' : title,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          fontWeight: hl.isCharacter
                              ? FontWeight.w700
                              : FontWeight.w600,
                          fontStyle: hl.isCharacter
                              ? FontStyle.normal
                              : FontStyle.italic,
                          color: _colors.text,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pageLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _colors.secondaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (contextText != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          contextText,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: _colors.tertiaryText,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.54),
                    size: 16,
                  ),
                  onPressed: () {
                    _removeLocalHighlight(hl.id);
                    widget.onRemoveHighlight?.call(hl.id);
                  },
                  tooltip: 'Remove highlight',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: _colors.secondaryText.withValues(alpha: 0.75),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _colors.secondaryText, size: 42),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: _colors.secondaryText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 7),
            Text(
              message,
              style: TextStyle(color: _colors.tertiaryText, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hintText,
    required bool hasQuery,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: TextField(
        controller: controller,
        style: TextStyle(fontSize: 13, color: _colors.text),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(fontSize: 13, color: _colors.tertiaryText),
          prefixIcon: Icon(Icons.search, size: 18, color: _colors.tertiaryText),
          suffixIcon: hasQuery
              ? IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: _colors.secondaryText,
                  ),
                  onPressed: controller.clear,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 12,
          ),
          filled: true,
          fillColor: _colors.controlSurface.withValues(
            alpha: _colors.isDark ? 0.28 : 0.36,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ─── Notes Tab ────────────────────────────────────────────────────────
  Widget _buildNotesList() {
    final notedHighlights = _visibleNotes
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filteredNotes = notedHighlights.where((hl) {
      if (_notesFilter.isEmpty) return true;
      final searchable = [
        hl.note ?? '',
        hl.text,
        _getHighlightContext(hl, contextChars: 48) ?? '',
        _displayPageLabel(hl.originalChunkIndex),
      ].join(' ').toLowerCase();
      return searchable.contains(_notesFilter);
    }).toList();

    if (notedHighlights.isEmpty) {
      return _buildEmptyState(
        icon: Icons.edit_note_rounded,
        title: 'No notes yet',
        message: 'Add notes to highlights to see them here.',
      );
    }

    return Column(
      children: [
        _buildSearchField(
          controller: _notesSearchController,
          hintText: 'Search notes…',
          hasQuery: _notesFilter.isNotEmpty,
        ),
        Expanded(
          child: filteredNotes.isEmpty
              ? _buildEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching notes',
                  message: 'Try a different search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  itemCount: filteredNotes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _buildNoteRow(context, filteredNotes[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildNoteRow(BuildContext context, Highlight hl) {
    final pageLabel = _displayPageLabel(hl.originalChunkIndex);
    final quote = hl.text.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showNoteDetail(context, hl),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(0, 11, 8, 11),
          decoration: BoxDecoration(
            color: _colors.controlSurface.withValues(
              alpha: _colors.isDark ? 0.22 : 0.34,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _colors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 56,
                decoration: BoxDecoration(
                  color: hl.color,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(999),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pageLabel,
                      style: TextStyle(
                        color: _colors.secondaryText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hl.note ?? '',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _colors.text,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (quote.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '"$quote"',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: _colors.tertiaryText,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.5),
                  size: 16,
                ),
                onPressed: () {
                  _removeLocalHighlight(hl.id);
                  widget.onNoteRemoved?.call(hl.id);
                },
                tooltip: 'Delete note',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _colors.secondaryText.withValues(alpha: 0.75),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNoteEditDialog(BuildContext context, Highlight hl) {
    showNoteEditorSheet(
      context,
      title: 'Edit Note',
      highlightedText: _getHighlightContext(hl, contextChars: 80) ?? hl.text,
      accentColor: hl.color,
      readingSettings: widget.settings,
      initialNote: hl.note ?? '',
      submitLabel: 'Update Note',
    ).then((result) {
      if (result is! String || result.isEmpty) return;
      setState(() {
        for (int i = 0; i < _localHighlights.length; i++) {
          if (_localHighlights[i].id != hl.id) continue;
          _localHighlights[i] = _localHighlights[i].copyWith(note: result);
        }
      });
      widget.onNoteUpdated?.call(hl.id, result);
    });
  }

  void _showNoteDetail(BuildContext context, Highlight hl) {
    showNoteDetailSheet(
      context,
      highlight: hl,
      locationLabel: _displayPageLabel(hl.originalChunkIndex),
      readingSettings: widget.settings,
      contextText: _getHighlightContext(hl, contextChars: 80),
      onNavigate: () => widget.onNavigate(hl.originalChunkIndex),
      onEdit: () => _showNoteEditDialog(context, hl),
      onDelete: () {
        setState(() {
          _localHighlights.removeWhere((h) => h.id == hl.id);
        });
        widget.onNoteRemoved?.call(hl.id);
      },
    );
  }

  // ─── Dictionary Tab ──────────────────────────────────────────────────

  Widget _buildDictionaryList() {
    final words = widget.dictionaryService.words.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final filteredWords = words.where((savedWord) {
      if (_dictionaryFilter.isEmpty) return true;
      return [
        savedWord.word,
        savedWord.meaning,
        savedWord.contextSentence ?? '',
      ].join(' ').toLowerCase().contains(_dictionaryFilter);
    }).toList();
    if (words.isEmpty) {
      return _buildEmptyState(
        icon: Icons.menu_book_rounded,
        title: 'No saved words yet',
        message: 'Save definitions while reading to build your word bank.',
      );
    }

    return Column(
      children: [
        _buildSearchField(
          controller: _dictionarySearchController,
          hintText: 'Search saved words…',
          hasQuery: _dictionaryFilter.isNotEmpty,
        ),
        Expanded(
          child: filteredWords.isEmpty
              ? _buildEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching words',
                  message: 'Try a different search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  itemCount: filteredWords.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final savedWord = filteredWords[index];
                    final canNavigate = savedWord.originalChunkIndex != null;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: canNavigate
                            ? () => widget.onNavigate(
                                savedWord.originalChunkIndex!,
                              )
                            : null,
                        child: Ink(
                          padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                          decoration: BoxDecoration(
                            color: _colors.controlSurface.withValues(
                              alpha: _colors.isDark ? 0.22 : 0.34,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _colors.divider),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      savedWord.word,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: _colors.text,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      savedWord.meaning,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.35,
                                        color: _colors.secondaryText,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 17,
                                ),
                                color: Theme.of(
                                  context,
                                ).colorScheme.error.withValues(alpha: 0.5),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 30,
                                  height: 30,
                                ),
                                tooltip: 'Delete word',
                                onPressed: () async {
                                  await widget.dictionaryService.deleteWord(
                                    savedWord.id,
                                  );
                                  setState(() {});
                                },
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: canNavigate
                                    ? _colors.secondaryText.withValues(
                                        alpha: 0.75,
                                      )
                                    : _colors.secondaryText.withValues(
                                        alpha: 0.24,
                                      ),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _updateHighlightColorLocally(String id, Color color) {
    final normalized = Color(highlightColorValue(color));
    setState(() {
      for (int i = 0; i < _localHighlights.length; i++) {
        if (_localHighlights[i].id != id) continue;
        final existing = _localHighlights[i];
        _localHighlights[i] = existing.copyWith(
          colorIndex:
              defaultHighlightColorIndex(normalized) ?? existing.colorIndex,
          colorValue: highlightColorValue(normalized),
        );
      }
    });
  }

  void _showColorPicker(BuildContext context, Highlight highlight) {
    showHighlightPaletteSheet(
      context,
      title: 'Edit highlight color',
      palette: _highlightPalette,
      selectedColor: highlight.color,
      readingSettings: widget.settings,
      onColorSelected: (color) {
        _updateHighlightColorLocally(highlight.id, color);
        widget.onChangeHighlightColor?.call(highlight, color);
      },
      onAddCustomColor: (color) async {
        final updated =
            await (widget.onAddCustomColor?.call(color) ??
                Future<List<Color>>.value(_highlightPalette));
        if (mounted) {
          setState(() {
            _highlightPalette = updated.map((entry) {
              return Color(highlightColorValue(entry));
            }).toList();
          });
        }
        return updated;
      },
      onRemoveCustomColor: (color) async {
        final updated =
            await (widget.onRemoveCustomColor?.call(color) ??
                Future<List<Color>>.value(_highlightPalette));
        if (mounted) {
          setState(() {
            _highlightPalette = updated.map((entry) {
              return Color(highlightColorValue(entry));
            }).toList();
          });
        }
        return updated;
      },
      onResetPalette: () async {
        final updated =
            await (widget.onResetHighlightPalette?.call() ??
                Future<List<Color>>.value(_highlightPalette));
        if (mounted) {
          setState(() {
            _highlightPalette = updated.map((entry) {
              return Color(highlightColorValue(entry));
            }).toList();
          });
        }
        return updated;
      },
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final _PanelColors colors;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = colors.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.16)
              : colors.controlSurface.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? activeColor
                : colors.secondaryText.withValues(alpha: 0.46),
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? activeColor : colors.secondaryText,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? activeColor : colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelColors {
  final Color surface;
  final Color controlSurface;
  final Color text;
  final Color secondaryText;
  final Color tertiaryText;
  final Color divider;
  final Color accent;
  final bool isDark;

  const _PanelColors({
    required this.surface,
    required this.controlSurface,
    required this.text,
    required this.secondaryText,
    required this.tertiaryText,
    required this.divider,
    required this.accent,
    required this.isDark,
  });

  factory _PanelColors.fromSettings(ReadingSettings? settings) {
    final effective = settings ?? const ReadingSettings();
    final text = effective.textColor;
    final muted = effective.mutedColor;
    return _PanelColors(
      surface: effective.menuColor,
      controlSurface: effective.backgroundColor,
      text: text,
      secondaryText: muted,
      tertiaryText: muted.withValues(alpha: 0.72),
      divider: text.withValues(alpha: effective.isDark ? 0.16 : 0.18),
      accent: effective.accentColor,
      isDark: effective.isDark,
    );
  }

  factory _PanelColors.fromReaderTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = scheme.onSurfaceVariant;
    return _PanelColors(
      surface: scheme.surface,
      controlSurface: scheme.surfaceContainerHighest,
      text: scheme.onSurface,
      secondaryText: muted,
      tertiaryText: muted.withValues(alpha: 0.72),
      divider: theme.dividerColor,
      accent: scheme.primary,
      isDark: isDark,
    );
  }
}
