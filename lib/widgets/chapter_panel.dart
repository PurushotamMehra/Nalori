import 'package:flutter/material.dart';
import '../models/bookmark.dart';
import '../models/position_history.dart';
import '../models/reading_settings.dart';
import '../models/stable_book_location.dart';
import '../services/chapter_navigation_service.dart';
import 'reading_card.dart' show kBookmarkPink;

/// A side-drawer panel for "Chapters" and "Bookmarks".
///
/// Slides in from the left edge. The Chapters tab shows expandable
/// sections with hierarchy. The Bookmarks tab shows all saved bookmarks
/// with search, remove, and undo support.
class ChapterPanel extends StatefulWidget {
  final List<ChapterInfo> chapters;
  final int currentPage;
  final StableBookLocation? currentStableLocation;
  final List<ChapterNavigationTarget> chapterNavigationTargets;
  final Map<int, int> originalToDisplay;
  final ValueChanged<int> onNavigate;
  final ValueChanged<ChapterInfo>? onNavigateChapter;
  final ValueChanged<Bookmark>? onNavigateBookmark;
  final ValueNotifier<PositionHistory?>? positionHistoryNotifier;
  final VoidCallback? onGoBack;
  final ReadingSettings? settings;

  // ── Bookmark support ──
  final List<Bookmark> bookmarks;
  final int totalDisplayPages;
  final Map<int, String> chunkTexts;
  final String Function(int originalChunkIndex)? buildLocationLabel;
  final String Function(Bookmark bookmark)? buildBookmarkLocationLabel;
  final Function(Bookmark bookmark) onRemoveBookmark;
  final VoidCallback onClearAllBookmarks;
  final Function(List<Bookmark>) onRestoreBookmarks;

  const ChapterPanel({
    super.key,
    required this.chapters,
    required this.currentPage,
    this.currentStableLocation,
    this.chapterNavigationTargets = const [],
    required this.originalToDisplay,
    required this.onNavigate,
    this.onNavigateChapter,
    this.onNavigateBookmark,
    this.positionHistoryNotifier,
    this.onGoBack,
    this.settings,
    required this.bookmarks,
    required this.totalDisplayPages,
    this.chunkTexts = const {},
    this.buildLocationLabel,
    this.buildBookmarkLocationLabel,
    required this.onRemoveBookmark,
    required this.onClearAllBookmarks,
    required this.onRestoreBookmarks,
  });

  /// Convenience entry point — show as a side drawer from the left.
  static Future<void> show(
    BuildContext context, {
    required List<ChapterInfo> chapters,
    required int currentPage,
    StableBookLocation? currentStableLocation,
    List<ChapterNavigationTarget> chapterNavigationTargets = const [],
    required Map<int, int> originalToDisplay,
    required ValueChanged<int> onNavigate,
    ValueChanged<ChapterInfo>? onNavigateChapter,
    ValueChanged<Bookmark>? onNavigateBookmark,
    ValueNotifier<PositionHistory?>? positionHistoryNotifier,
    VoidCallback? onGoBack,
    ReadingSettings? settings,
    required List<Bookmark> bookmarks,
    required int totalDisplayPages,
    Map<int, String> chunkTexts = const {},
    String Function(int originalChunkIndex)? buildLocationLabel,
    String Function(Bookmark bookmark)? buildBookmarkLocationLabel,
    required Function(Bookmark bookmark) onRemoveBookmark,
    required VoidCallback onClearAllBookmarks,
    required Function(List<Bookmark>) onRestoreBookmarks,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close chapter panel',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim, secondaryAnim) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: ChapterPanel(
              chapters: chapters,
              currentPage: currentPage,
              currentStableLocation: currentStableLocation,
              chapterNavigationTargets: chapterNavigationTargets,
              originalToDisplay: originalToDisplay,
              positionHistoryNotifier: positionHistoryNotifier,
              settings: settings,
              onGoBack: () {
                Navigator.pop(ctx);
                if (onGoBack != null) onGoBack();
              },
              onNavigate: (index) {
                Navigator.pop(ctx);
                onNavigate(index);
              },
              onNavigateChapter: onNavigateChapter == null
                  ? null
                  : (chapter) {
                      Navigator.pop(ctx);
                      onNavigateChapter(chapter);
                    },
              onNavigateBookmark: onNavigateBookmark == null
                  ? null
                  : (bookmark) {
                      Navigator.pop(ctx);
                      onNavigateBookmark(bookmark);
                    },
              bookmarks: bookmarks,
              totalDisplayPages: totalDisplayPages,
              chunkTexts: chunkTexts,
              buildLocationLabel: buildLocationLabel,
              buildBookmarkLocationLabel: buildBookmarkLocationLabel,
              onRemoveBookmark: onRemoveBookmark,
              onClearAllBookmarks: onClearAllBookmarks,
              onRestoreBookmarks: onRestoreBookmarks,
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  State<ChapterPanel> createState() => _ChapterPanelState();
}

class _ChapterPanelState extends State<ChapterPanel>
    with SingleTickerProviderStateMixin {
  // ── Bookmark local state ──
  late List<Bookmark> _localBookmarks;
  List<Bookmark>? _undoBookmarks;
  late _PanelColors _themeColors;
  late final TabController _tabController;
  final ScrollController _chaptersScrollController = ScrollController();
  final Set<String> _expandedSectionKeys = <String>{};
  final Map<String, GlobalKey> _chapterKeys = <String, GlobalKey>{};
  final _bookmarkSearchController = TextEditingController();
  String _bookmarkFilter = '';

  static int _lastSelectedTab = 0;

  static const _frontMatterPatterns = [
    'cover',
    'title page',
    'titlepage',
    'copyright',
    'dedication',
    'epigraph',
    'foreword',
    'preface',
    'acknowledgment',
    'acknowledgement',
    'about the author',
    'about the book',
    'also by',
    'other books',
    'table of contents',
    'contents',
    'half title',
    'halftitle',
    'frontispiece',
    'colophon',
    'publisher',
    'edition',
    'isbn',
    'introduction',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _lastSelectedTab,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _lastSelectedTab = _tabController.index;
      }
    });
    _localBookmarks = List.from(widget.bookmarks);
    _expandedSectionKeys.addAll(_currentSectionKeys(widget.chapters));
    _bookmarkSearchController.addListener(() {
      setState(
        () => _bookmarkFilter = _bookmarkSearchController.text.toLowerCase(),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollCurrentIntoView(),
    );
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
    _tabController.dispose();
    _chaptersScrollController.dispose();
    _bookmarkSearchController.dispose();
    super.dispose();
  }

  String _chapterKey(ChapterInfo chapter) =>
      '${chapter.depth}:${chapter.chunkIndex}:${chapter.title}';

  List<ChapterInfo> _flattenChapters(List<ChapterInfo> chapters) {
    final flat = <ChapterInfo>[];
    void walk(List<ChapterInfo> nodes) {
      for (final chapter in nodes) {
        flat.add(chapter);
        if (chapter.children.isNotEmpty) walk(chapter.children);
      }
    }

    walk(chapters);
    flat.sort((a, b) {
      final aDisplay = widget.originalToDisplay[a.chunkIndex] ?? a.chunkIndex;
      final bDisplay = widget.originalToDisplay[b.chunkIndex] ?? b.chunkIndex;
      return aDisplay.compareTo(bDisplay);
    });
    return flat;
  }

  Set<String> _currentSectionKeys(List<ChapterInfo> chapters) {
    final keys = <String>{};
    bool walk(ChapterInfo chapter) {
      final containsSelf = _sectionContainsPage(chapter, widget.currentPage);
      var containsChild = false;
      for (final child in chapter.children) {
        containsChild = walk(child) || containsChild;
      }
      if (chapter.children.isNotEmpty && (containsSelf || containsChild)) {
        keys.add(_chapterKey(chapter));
      }
      return containsSelf || containsChild;
    }

    for (final chapter in chapters) {
      walk(chapter);
    }
    return keys;
  }

  void _scrollCurrentIntoView() {
    if (!mounted || !_chaptersScrollController.hasClients) return;
    final key = _currentChapterKey();
    if (key == null) return;
    final context = _chapterKeys[key]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.34,
    );
  }

  String? _currentChapterKey() {
    ChapterInfo? current;
    for (final chapter in _flattenChapters(widget.chapters)) {
      final state = _chapterReadState(chapter);
      if (state == _ChapterReadState.current) {
        current = chapter;
      }
    }
    return current == null ? null : _chapterKey(current);
  }

  GlobalKey _keyForChapter(ChapterInfo chapter) =>
      _chapterKeys.putIfAbsent(_chapterKey(chapter), GlobalKey.new);

  bool _isFrontMatter(String title) {
    final lower = title.toLowerCase().trim();
    for (final pattern in _frontMatterPatterns) {
      if (lower.contains(pattern)) return true;
    }
    return false;
  }

  bool _sectionContainsPage(ChapterInfo section, int page) {
    if (widget.chapterNavigationTargets.isNotEmpty &&
        widget.currentStableLocation != null) {
      return _chapterOrDescendantIsCurrent(section);
    }
    if (widget.currentStableLocation != null &&
        section.stableLocation != null) {
      return _chapterReadState(section) == _ChapterReadState.current;
    }
    final sectionDisplayIdx =
        widget.originalToDisplay[section.chunkIndex] ?? section.chunkIndex;
    if (page < sectionDisplayIdx) return false;

    int maxOrigIdx = section.chunkIndex;
    void walkMax(ChapterInfo ch) {
      if (ch.chunkIndex > maxOrigIdx) maxOrigIdx = ch.chunkIndex;
      for (final child in ch.children) {
        walkMax(child);
      }
    }

    walkMax(section);
    final maxDisplayIdx = widget.originalToDisplay[maxOrigIdx] ?? maxOrigIdx;
    return page >= sectionDisplayIdx && page <= maxDisplayIdx + 50;
  }

  int _displayIndexForChapter(ChapterInfo chapter) =>
      widget.originalToDisplay[chapter.chunkIndex] ?? chapter.chunkIndex;

  _ChapterReadState _chapterReadState(ChapterInfo chapter) {
    final currentStable = widget.currentStableLocation;
    final chapterStable = chapter.stableLocation;
    final canonicalTargets = widget.chapterNavigationTargets;
    if (currentStable != null && canonicalTargets.isNotEmpty) {
      final target = _targetForChapter(chapter);
      final currentTarget = ChapterNavigationService.currentTarget(
        canonicalTargets,
        currentStable,
      );
      if (target == null || currentTarget == null) {
        return _ChapterReadState.unread;
      }
      if (identical(target, currentTarget)) return _ChapterReadState.current;
      return ChapterNavigationService.compareTargets(target, currentTarget) < 0
          ? _ChapterReadState.completed
          : _ChapterReadState.unread;
    }

    if (currentStable != null && chapterStable != null) {
      final flat = _flattenChapters(
        widget.chapters,
      ).where((entry) => entry.stableLocation != null).toList();
      final position = flat.indexWhere(
        (candidate) =>
            candidate.stableLocation == chapterStable &&
            candidate.title == chapter.title &&
            candidate.depth == chapter.depth,
      );
      final currentOrder = _currentStableChapterIndex(flat, currentStable);
      if (position < 0 || currentOrder < 0) return _ChapterReadState.unread;
      if (position == currentOrder) return _ChapterReadState.current;
      return position < currentOrder
          ? _ChapterReadState.completed
          : _ChapterReadState.unread;
    }

    final start = _displayIndexForChapter(chapter);
    final flat = _flattenChapters(widget.chapters);
    final position = flat.indexWhere(
      (candidate) =>
          candidate.chunkIndex == chapter.chunkIndex &&
          candidate.title == chapter.title &&
          candidate.depth == chapter.depth,
    );
    final nextStart = position >= 0 && position + 1 < flat.length
        ? _displayIndexForChapter(flat[position + 1])
        : widget.totalDisplayPages;
    final end = nextStart <= start ? start : nextStart - 1;

    if (widget.currentPage >= start && widget.currentPage <= end) {
      return _ChapterReadState.current;
    }
    if (widget.currentPage > end) return _ChapterReadState.completed;
    return _ChapterReadState.unread;
  }

  _ChapterReadState _sectionReadState(ChapterInfo chapter) {
    if (chapter.children.isEmpty) return _chapterReadState(chapter);
    if (widget.chapterNavigationTargets.isNotEmpty &&
        widget.currentStableLocation != null) {
      if (_chapterOrDescendantIsCurrent(chapter)) {
        return _ChapterReadState.current;
      }
      return _chapterReadState(chapter);
    }
    if (_sectionContainsPage(chapter, widget.currentPage)) {
      return _ChapterReadState.current;
    }
    final start = _displayIndexForChapter(chapter);
    return widget.currentPage > start
        ? _ChapterReadState.completed
        : _ChapterReadState.unread;
  }

  ChapterNavigationTarget? _targetForChapter(ChapterInfo chapter) {
    return widget.chapterNavigationTargets
        .cast<ChapterNavigationTarget?>()
        .firstWhere(
          (target) =>
              target != null &&
              ChapterNavigationService.sameTarget(target, chapter),
          orElse: () => null,
        );
  }

  bool _chapterOrDescendantIsCurrent(ChapterInfo chapter) {
    if (_chapterReadState(chapter) == _ChapterReadState.current) return true;
    for (final child in chapter.children) {
      if (_chapterOrDescendantIsCurrent(child)) return true;
    }
    return false;
  }

  int _currentStableChapterIndex(
    List<ChapterInfo> flat,
    StableBookLocation current,
  ) {
    var currentIndex = -1;
    for (var i = 0; i < flat.length; i++) {
      final location = flat[i].stableLocation;
      if (location == null) continue;
      if (_compareLocations(location, current) <= 0) {
        currentIndex = i;
      } else {
        break;
      }
    }
    return currentIndex;
  }

  int _compareLocations(StableBookLocation a, StableBookLocation b) {
    final spine = a.spineIndex.compareTo(b.spineIndex);
    if (spine != 0) return spine;
    final aChunk = a.localChunkIndex ?? 0;
    final bChunk = b.localChunkIndex ?? 0;
    final chunk = aChunk.compareTo(bChunk);
    if (chunk != 0) return chunk;
    return a.textOffset.compareTo(b.textOffset);
  }

  Color _stateColor(_ChapterReadState state) {
    return switch (state) {
      _ChapterReadState.current => _colors.accent,
      _ChapterReadState.completed => _colors.secondaryText,
      _ChapterReadState.unread => _colors.text,
    };
  }

  String _displayPageLabel(int chunkIndex) {
    final dp = widget.originalToDisplay[chunkIndex] ?? chunkIndex;
    if (dp >= widget.totalDisplayPages && widget.totalDisplayPages > 0) {
      return 'Unloaded';
    }
    return 'Page ${dp + 1}';
  }

  String _displayPageLabelFull(int originalChunkIndex) {
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

  String _bookmarkPageLabel(Bookmark bookmark) {
    final customLabel = widget.buildBookmarkLocationLabel?.call(bookmark);
    if (customLabel != null && customLabel.isNotEmpty) {
      return customLabel;
    }
    return _displayPageLabelFull(bookmark.chunkIndex);
  }

  String? _getChunkPreview(int originalChunkIndex, {int maxChars = 60}) {
    final text = widget.chunkTexts[originalChunkIndex];
    if (text == null || text.isEmpty) return null;
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= maxChars) return cleaned;
    return '${cleaned.substring(0, maxChars)}…';
  }

  // ── Bookmark management ──

  void _removeBookmark(Bookmark bookmark) {
    setState(() {
      _localBookmarks.removeWhere((b) => b.locationKey == bookmark.locationKey);
    });
    widget.onRemoveBookmark(bookmark);
  }

  void _clearAllBookmarks() {
    if (_localBookmarks.isEmpty) return;
    setState(() {
      _undoBookmarks = List.from(_localBookmarks);
      _localBookmarks.clear();
    });
    widget.onClearAllBookmarks();
  }

  void _undoClearAll() {
    if (_undoBookmarks == null) return;
    final restored = List<Bookmark>.from(_undoBookmarks!);
    setState(() {
      _localBookmarks = restored;
      _undoBookmarks = null;
    });
    widget.onRestoreBookmarks(restored);
  }

  // ── Bottom "Go Back" chip ──

  Widget _buildBottomGoBackButton(BuildContext context) {
    if (widget.positionHistoryNotifier == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<PositionHistory?>(
      valueListenable: widget.positionHistoryNotifier!,
      builder: (context, posHistory, child) {
        if (posHistory != null && widget.onGoBack != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 18, 14),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onGoBack,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _colors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _colors.accent.withValues(alpha: 0.32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.undo_rounded, size: 17, color: _colors.accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Go back to ${posHistory.label}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _colors.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth * 0.85;
    final colors = _colors;

    return Container(
      width: drawerWidth,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 8),
                // Tab bar
                TabBar(
                  controller: _tabController,
                  labelColor: colors.text,
                  unselectedLabelColor: colors.secondaryText,
                  indicatorColor: colors.accent,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: [
                    Tab(
                      child: Semantics(
                        button: true,
                        label: 'Chapters',
                        child: const ExcludeSemantics(child: Text('Chapters')),
                      ),
                    ),
                    Tab(
                      child: Semantics(
                        button: true,
                        label: 'Bookmarks',
                        child: const ExcludeSemantics(child: Text('Bookmarks')),
                      ),
                    ),
                  ],
                ),
                Divider(height: 1, color: colors.divider),
                // Tab views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildChaptersList(context),
                      _buildBookmarksList(context),
                    ],
                  ),
                ),
                _buildBottomGoBackButton(context),
              ],
            ),
            Positioned(
              top: 64,
              left: 0,
              bottom: 76,
              child: _buildProgressRail(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRail() {
    final total = widget.totalDisplayPages <= 0 ? 1 : widget.totalDisplayPages;
    final progress = ((widget.currentPage + 1) / total).clamp(0.0, 1.0);

    return SizedBox(
      width: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 2,
                  height: height * progress,
                  decoration: BoxDecoration(
                    color: _colors.accent.withValues(alpha: 0.48),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(999),
                      bottomRight: Radius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Chapters Tab ──

  Widget _buildChaptersList(BuildContext context) {
    if (widget.chapters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 48, color: _colors.secondaryText),
            const SizedBox(height: 12),
            Text(
              'No chapters found',
              style: TextStyle(fontSize: 16, color: _colors.secondaryText),
            ),
          ],
        ),
      );
    }

    final List<ChapterInfo> bookDetails = [];
    final List<ChapterInfo> chapterContent = [];

    for (final ch in widget.chapters) {
      if (_isFrontMatter(ch.title)) {
        bookDetails.add(ch);
      } else {
        chapterContent.add(ch);
      }
    }

    final hasBookDetails = bookDetails.isNotEmpty;

    return ListView.builder(
      controller: _chaptersScrollController,
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 14),
      itemCount: chapterContent.length + (hasBookDetails ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasBookDetails && index == 0) {
          return _buildExpandableSection(
            context,
            title: 'Book Details',
            icon: Icons.info_outline,
            iconColor: _colors.secondaryText,
            initiallyExpanded: false,
            children: bookDetails,
          );
        }

        final chapterIndex = hasBookDetails ? index - 1 : index;
        return _buildChapterEntry(context, chapterContent[chapterIndex]);
      },
    );
  }

  Widget _buildChapterEntry(BuildContext context, ChapterInfo chapter) {
    final state = _chapterReadState(chapter);
    if (chapter.children.isEmpty) {
      return _buildNavTile(
        context,
        icon: Icons.article_outlined,
        iconColor: _stateColor(state),
        title: chapter.title,
        subtitle: _displayPageLabel(chapter.chunkIndex),
        state: state,
        depth: chapter.depth,
        itemKey: _keyForChapter(chapter),
        onTap: () {
          final chapterCallback = widget.onNavigateChapter;
          if (chapterCallback != null) {
            chapterCallback(chapter);
          } else {
            widget.onNavigate(chapter.chunkIndex);
          }
        },
      );
    }

    final containsCurrentPage = _sectionContainsPage(
      chapter,
      widget.currentPage,
    );

    return _buildExpandableSection(
      context,
      chapter: chapter,
      title: chapter.title,
      icon: Icons.folder_outlined,
      iconColor: _stateColor(_sectionReadState(chapter)),
      initiallyExpanded: containsCurrentPage,
      onHeaderTap: () {
        final chapterCallback = widget.onNavigateChapter;
        if (chapterCallback != null) {
          chapterCallback(chapter);
        } else {
          widget.onNavigate(chapter.chunkIndex);
        }
      },
      children: chapter.children,
    );
  }

  Widget _buildExpandableSection(
    BuildContext context, {
    ChapterInfo? chapter,
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool initiallyExpanded,
    required List<ChapterInfo> children,
    VoidCallback? onHeaderTap,
  }) {
    final sectionKey = chapter == null
        ? 'section:$title'
        : _chapterKey(chapter);
    final state = chapter == null
        ? _ChapterReadState.unread
        : _sectionReadState(chapter);
    final expanded =
        _expandedSectionKeys.contains(sectionKey) ||
        (initiallyExpanded &&
            !_expandedSectionKeys.contains('closed:$sectionKey'));
    final titleColor = state == _ChapterReadState.current
        ? _colors.text
        : _stateColor(
            state,
          ).withValues(alpha: state == _ChapterReadState.completed ? 0.86 : 1);

    return Semantics(
      selected: state == _ChapterReadState.current,
      child: Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: _colors.isDark ? Brightness.dark : Brightness.light,
          dividerColor: Colors.transparent,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _colors.accent,
            brightness: _colors.isDark ? Brightness.dark : Brightness.light,
            surface: _colors.surface,
            onSurface: _colors.text,
            primary: _colors.accent,
          ),
        ),
        child: Container(
          key: chapter == null ? null : _keyForChapter(chapter),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: state == _ChapterReadState.current
                ? _colors.accent.withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ExpansionTile(
            leading: _ChapterStateIndicator(
              color: _stateColor(state),
              active: state == _ChapterReadState.current,
              completed: state == _ChapterReadState.completed,
              child: Icon(icon, color: iconColor, size: 21),
            ),
            title: GestureDetector(
              onTap: onHeaderTap,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: state == _ChapterReadState.current
                      ? FontWeight.w800
                      : FontWeight.w700,
                  color: titleColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            subtitle: chapter == null
                ? null
                : Text(
                    _displayPageLabel(chapter.chunkIndex),
                    style: TextStyle(fontSize: 11, color: _colors.tertiaryText),
                  ),
            initiallyExpanded: expanded,
            onExpansionChanged: (value) {
              setState(() {
                if (value) {
                  _expandedSectionKeys.add(sectionKey);
                  _expandedSectionKeys.remove('closed:$sectionKey');
                } else {
                  _expandedSectionKeys.remove(sectionKey);
                  _expandedSectionKeys.add('closed:$sectionKey');
                }
              });
            },
            tilePadding: const EdgeInsets.only(left: 8, right: 6),
            childrenPadding: const EdgeInsets.only(left: 18, bottom: 4),
            iconColor: _colors.secondaryText,
            collapsedIconColor: _colors.secondaryText,
            dense: true,
            visualDensity: VisualDensity.compact,
            children: children.map((ch) {
              if (ch.children.isNotEmpty) {
                return _buildChapterEntry(context, ch);
              }
              final childState = _chapterReadState(ch);
              return _buildNavTile(
                context,
                icon: Icons.article_outlined,
                iconColor: _stateColor(childState),
                title: ch.title,
                subtitle: _displayPageLabel(ch.chunkIndex),
                state: childState,
                depth: ch.depth,
                itemKey: _keyForChapter(ch),
                onTap: () {
                  final chapterCallback = widget.onNavigateChapter;
                  if (chapterCallback != null) {
                    chapterCallback(ch);
                  } else {
                    widget.onNavigate(ch.chunkIndex);
                  }
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required _ChapterReadState state,
    required int depth,
    Key? itemKey,
    required VoidCallback onTap,
  }) {
    final isCurrent = state == _ChapterReadState.current;
    final isCompleted = state == _ChapterReadState.completed;
    final textColor = isCurrent
        ? _colors.text
        : (isCompleted ? _colors.secondaryText : _colors.text);
    final titleWeight = isCurrent
        ? FontWeight.w800
        : (isCompleted ? FontWeight.w500 : FontWeight.w600);

    return Semantics(
      button: true,
      selected: isCurrent,
      label: title,
      hint: subtitle,
      child: Container(
        key: itemKey,
        margin: EdgeInsets.only(
          left: depth > 1 ? (depth - 1) * 4.0 : 0,
          top: 1,
          bottom: 1,
        ),
        decoration: BoxDecoration(
          color: isCurrent
              ? _colors.accent.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          minLeadingWidth: 32,
          horizontalTitleGap: 10,
          contentPadding: const EdgeInsets.only(left: 8, right: 6),
          leading: _ChapterStateIndicator(
            color: _stateColor(state),
            active: isCurrent,
            completed: isCompleted,
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: ExcludeSemantics(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: titleWeight,
                color: textColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          subtitle: subtitle != null
              ? ExcludeSemantics(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isCurrent ? _colors.accent : _colors.tertiaryText,
                    ),
                  ),
                )
              : null,
          trailing: Icon(
            Icons.chevron_right,
            color: isCurrent ? _colors.accent : _colors.tertiaryText,
            size: 19,
          ),
          dense: true,
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
          onTap: onTap,
        ),
      ),
    );
  }

  // ── Bookmarks Tab ──

  Widget _buildBookmarksList(BuildContext context) {
    // Show undo state
    if (_localBookmarks.isEmpty && _undoBookmarks != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_remove, size: 48, color: _colors.secondaryText),
            const SizedBox(height: 12),
            Text(
              'All bookmarks removed',
              style: TextStyle(fontSize: 16, color: _colors.secondaryText),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _undoClearAll,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
              style: FilledButton.styleFrom(backgroundColor: kBookmarkPink),
            ),
          ],
        ),
      );
    }

    // Show empty state
    if (_localBookmarks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border, size: 48, color: _colors.secondaryText),
            const SizedBox(height: 12),
            Text(
              'No bookmarks yet',
              style: TextStyle(fontSize: 16, color: _colors.secondaryText),
            ),
            const SizedBox(height: 4),
            Text(
              'Double-tap any page to add a bookmark',
              style: TextStyle(fontSize: 13, color: _colors.tertiaryText),
            ),
          ],
        ),
      );
    }

    // Filter bookmarks by search query
    final filtered = _bookmarkFilter.isEmpty
        ? _localBookmarks
        : _localBookmarks.where((b) {
            final nameMatch = b.name.toLowerCase().contains(_bookmarkFilter);
            final previewText =
                b.previewText ?? _getChunkPreview(b.chunkIndex) ?? '';
            final textMatch = previewText.toLowerCase().contains(
              _bookmarkFilter,
            );
            return nameMatch || textMatch;
          }).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 20, 6),
          child: TextField(
            controller: _bookmarkSearchController,
            style: TextStyle(fontSize: 13, color: _colors.text),
            decoration: InputDecoration(
              hintText: 'Search bookmarks…',
              hintStyle: TextStyle(fontSize: 13, color: _colors.tertiaryText),
              prefixIcon: Icon(
                Icons.search,
                size: 18,
                color: _colors.tertiaryText,
              ),
              suffixIcon: _bookmarkFilter.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: _colors.secondaryText,
                      ),
                      onPressed: () => _bookmarkSearchController.clear(),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              filled: true,
              fillColor: _colors.controlSurface.withValues(alpha: 0.38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _colors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _colors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _colors.accent.withValues(alpha: 0.68),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildNoBookmarkResults()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 18, 14),
                  itemCount: filtered.length + 1,
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      return _buildRemoveAllBookmarksButton();
                    }

                    final bookmark = filtered[index];
                    return _buildBookmarkTile(bookmark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNoBookmarkResults() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 36, 20, 16),
      children: [
        Icon(Icons.search_off, size: 36, color: _colors.secondaryText),
        const SizedBox(height: 10),
        Text(
          'No matching bookmarks',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: _colors.secondaryText),
        ),
        const SizedBox(height: 18),
        _buildRemoveAllBookmarksButton(),
      ],
    );
  }

  Widget _buildRemoveAllBookmarksButton() {
    if (_localBookmarks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: OutlinedButton.icon(
        onPressed: _clearAllBookmarks,
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
        label: const Text('Remove All Bookmarks'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red[300],
          side: BorderSide(color: Colors.red[300]!.withValues(alpha: 0.34)),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkTile(Bookmark bookmark) {
    final preview =
        bookmark.previewText ?? _getChunkPreview(bookmark.chunkIndex);
    final pageLabel = _bookmarkPageLabel(bookmark);

    return Semantics(
      button: true,
      label: bookmark.name,
      hint: pageLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final bookmarkNavigation = widget.onNavigateBookmark;
              if (bookmarkNavigation != null) {
                bookmarkNavigation(bookmark);
              } else {
                widget.onNavigate(bookmark.chunkIndex);
              }
            },
            child: Ink(
              padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
              decoration: BoxDecoration(
                color: _colors.controlSurface.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _colors.divider.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 56,
                    decoration: BoxDecoration(
                      color: bookmark.color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  bookmark.name,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: _colors.text,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  pageLabel,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _colors.tertiaryText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (preview != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              preview,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.28,
                                color: _colors.secondaryText,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: _colors.tertiaryText,
                      size: 18,
                    ),
                    onPressed: () => _removeBookmark(bookmark),
                    tooltip: 'Remove bookmark',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ChapterReadState { completed, current, unread }

class _ChapterStateIndicator extends StatelessWidget {
  final Color color;
  final bool active;
  final bool completed;
  final Widget child;

  const _ChapterStateIndicator({
    required this.color,
    required this.active,
    required this.completed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: active ? 4 : 3,
            height: active ? 30 : (completed ? 20 : 14),
            decoration: BoxDecoration(
              color: active
                  ? color
                  : color.withValues(alpha: completed ? 0.58 : 0.22),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 7),
          IconTheme(
            data: IconThemeData(
              color: active
                  ? color
                  : color.withValues(alpha: completed ? 0.74 : 0.9),
              size: 20,
            ),
            child: child,
          ),
        ],
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
