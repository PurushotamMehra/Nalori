import 'package:flutter/material.dart';

import '../models/public_domain_book.dart';
import '../models/reading_settings.dart';
import '../services/public_domain_book_service.dart';
import '../ui/app_visuals.dart';
import '../widgets/floating_progress_hud.dart';

typedef PublicDomainPrimaryBookAction =
    Future<String?> Function({ValueChanged<double?>? onProgress});

class PublicDomainBookDetailScreen extends StatefulWidget {
  final PublicDomainBook book;
  final ReadingSettings settings;
  final bool isDownloaded;
  final PublicDomainPrimaryBookAction onPrimaryAction;
  final Future<void> Function(PublicDomainPerson author) onAuthorSelected;
  final Future<void> Function(String topic) onTopicSelected;

  const PublicDomainBookDetailScreen({
    super.key,
    required this.book,
    required this.settings,
    required this.isDownloaded,
    required this.onPrimaryAction,
    required this.onAuthorSelected,
    required this.onTopicSelected,
  });

  @override
  State<PublicDomainBookDetailScreen> createState() =>
      _PublicDomainBookDetailScreenState();
}

class _PublicDomainBookDetailScreenState
    extends State<PublicDomainBookDetailScreen> {
  final _service = PublicDomainBookService();

  late PublicDomainBook _book;
  late bool _isDownloaded;
  String? _downloadedPath;
  double? _downloadProgress;
  bool _loadingDetails = false;
  bool _performingPrimaryAction = false;

  ReadingSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _isDownloaded = widget.isDownloaded;
    _loadDetailsIfNeeded();
  }

  Future<void> _loadDetailsIfNeeded() async {
    if (!_needsFullRecord(_book)) return;

    setState(() => _loadingDetails = true);
    try {
      final detailedBook = await _service.fetchBookDetails(widget.book.id);
      if (!mounted) return;
      setState(() {
        _book = detailedBook;
        _loadingDetails = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDetails = false);
    }
  }

  bool _needsFullRecord(PublicDomainBook book) {
    return (book.summary == null || book.summary!.trim().isEmpty) &&
        book.subjects.isEmpty &&
        book.bookshelves.isEmpty &&
        book.authorDetails.isEmpty &&
        book.translators.isEmpty &&
        book.editors.isEmpty;
  }

  Future<void> _runPrimaryAction() async {
    if (_performingPrimaryAction) return;

    if (_isDownloaded && _downloadedPath != null) {
      Navigator.pop(context, _downloadedPath);
      return;
    }

    setState(() {
      _performingPrimaryAction = true;
      _downloadProgress = null;
    });
    try {
      final pathToOpen = await widget.onPrimaryAction(
        onProgress: _isDownloaded
            ? null
            : (progress) {
                if (!mounted) return;
                setState(() => _downloadProgress = progress);
              },
      );
      if (!mounted) return;
      if (pathToOpen != null) {
        if (_isDownloaded) {
          Navigator.pop(context, pathToOpen);
          return;
        }
        setState(() {
          _isDownloaded = true;
          _downloadedPath = pathToOpen;
          _downloadProgress = 1;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _performingPrimaryAction = false);
      }
    }
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
        ),
      ),
      child: Scaffold(
        backgroundColor: _s.backgroundColor,
        appBar: AppBar(
          backgroundColor: _s.backgroundColor,
          foregroundColor: _s.textColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Project Gutenberg',
            style: _s.uiText(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHero(),
                          const SizedBox(height: 24),
                          if (_book.summary != null &&
                              _book.summary!.trim().isNotEmpty)
                            _buildTextSection('Description', _book.summary!),
                          _buildPeopleSection(
                            title: 'Authors',
                            people: _book.authorDetails,
                            onTap: widget.onAuthorSelected,
                          ),
                          _buildTopicSection(
                            title: 'Bookshelves',
                            topics: _book.bookshelves,
                          ),
                          _buildTopicSection(
                            title: 'Subjects',
                            topics: _book.subjects,
                          ),
                          _buildInfoSection(),
                          _buildPeopleSection(
                            title: 'Translators',
                            people: _book.translators,
                          ),
                          _buildPeopleSection(
                            title: 'Editors',
                            people: _book.editors,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      color: _s.backgroundColor,
                      border: Border(
                        top: BorderSide(
                          color: _s.mutedColor.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    child: _buildPrimaryActionButton(),
                  ),
                ],
              ),
              if (_loadingDetails)
                FloatingProgressHud(
                  data: const FloatingProgressHudData(
                    title: 'Fetching book details',
                    message: 'Loading the full Project Gutenberg record…',
                  ),
                  settings: _s,
                  backgroundColor: _s.backgroundColor,
                  surfaceColor: _s.menuColor,
                  textColor: _s.textColor,
                  mutedColor: _s.mutedColor,
                  accentColor: _s.accentColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryActionButton() {
    if (_performingPrimaryAction && !_isDownloaded) {
      final progress = _downloadProgress;
      final label = progress == null
          ? 'Preparing download'
          : progress >= 1
          ? 'Adding to library'
          : 'Downloading ${(progress * 100).floor()}%';

      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _s.accentColor.withValues(alpha: 0.24),
                ),
              ),
              if (progress != null)
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: _s.accentColor),
                  ),
                )
              else
                Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: _s.accentColor,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              Center(
                child: Text(
                  label,
                  style: _s.uiText(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _performingPrimaryAction ? null : _runPrimaryAction,
        icon: Icon(
          _isDownloaded ? Icons.menu_book_rounded : Icons.download_rounded,
          size: 18,
        ),
        label: Text(_isDownloaded ? 'Read Book' : 'Download Book'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _s.accentColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _s.mutedColor.withValues(alpha: 0.14),
          disabledForegroundColor: _s.mutedColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: _s.uiText(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppUi.surfaceCard(_s, prominent: true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCover(),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _book.title,
                  style: _s.uiText(
                    color: _s.textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _book.authorLabel,
                  style: _s.uiText(
                    color: _s.mutedColor,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoPill('Free public-domain EPUB'),
                    _buildInfoPill('${_book.downloadCount} downloads'),
                    for (final code in _book.languages)
                      _buildInfoPill(labelForLanguageCode(code)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover() {
    final coverUrl = _book.coverUrl;
    final fallback = _buildGeneratedCover();
    if (coverUrl == null) return fallback;

    return ClipRRect(
      borderRadius: AppUi.cardRadius(AppUi.radiusSm),
      child: Stack(
        children: [
          fallback,
          Image.network(
            coverUrl,
            width: 108,
            height: 156,
            fit: BoxFit.cover,
            cacheWidth: 216,
            headers: const {'User-Agent': PublicDomainBookService.userAgent},
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: child,
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedCover() {
    final initials = _book.title
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Container(
      width: 108,
      height: 156,
      decoration: BoxDecoration(
        color: _s.accentColor.withValues(alpha: 0.16),
        borderRadius: AppUi.cardRadius(AppUi.radiusSm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _s.isDark ? 0.2 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? 'B' : initials,
        style: _s.uiText(
          color: _s.accentColor,
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildTextSection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(title),
          const SizedBox(height: 10),
          Text(
            body,
            style: _s.uiText(
              color: _s.mutedColor.withValues(alpha: 0.95),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeopleSection({
    required String title,
    required List<PublicDomainPerson> people,
    Future<void> Function(PublicDomainPerson person)? onTap,
  }) {
    if (people.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(title),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final person in people)
                ActionChip(
                  onPressed: onTap == null ? null : () => onTap(person),
                  backgroundColor: _s.menuColor,
                  disabledColor: _s.menuColor,
                  side: BorderSide(
                    color: _s.mutedColor.withValues(alpha: 0.14),
                  ),
                  shape: AppUi.shape(AppUi.radiusSm),
                  label: Text(
                    person.displayLabel,
                    style: _s.uiText(
                      color: _s.textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopicSection({
    required String title,
    required List<String> topics,
  }) {
    if (topics.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(title),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final topic in topics)
                ActionChip(
                  onPressed: () => widget.onTopicSelected(topic),
                  backgroundColor: _s.menuColor,
                  side: BorderSide(
                    color: _s.mutedColor.withValues(alpha: 0.14),
                  ),
                  shape: AppUi.shape(AppUi.radiusSm),
                  label: Text(
                    topic,
                    style: _s.uiText(
                      color: _s.textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Details'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_book.mediaType != null && _book.mediaType!.isNotEmpty)
                _buildInfoPill(_book.mediaType!),
              for (final code in _book.languages)
                _buildInfoPill(labelForLanguageCode(code)),
              _buildInfoPill('Project Gutenberg #${_book.id}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: AppUi.neutralPill(_s),
      child: Text(
        label,
        style: _s.uiText(
          color: _s.textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 2,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: _s.accentColor.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        Text(
          title.toUpperCase(),
          style: _s.uiText(
            color: _s.textColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}
