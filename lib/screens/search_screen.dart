import 'dart:async';

import 'package:flutter/material.dart';

import '../models/book_chunk.dart';
import '../models/reading_settings.dart';
import '../services/reading_settings_service.dart';

class SearchScreen extends StatefulWidget {
  final List<BookChunk> chunks;
  final Map<String, List<int>> searchIndex;
  final ReadingSettings? initialSettings;

  const SearchScreen({
    super.key,
    required this.chunks,
    required this.searchIndex,
    this.initialSettings,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchResult {
  final int chunkIndex;
  final String snippet;
  final int matchStart; // in snippet
  final int matchEnd; // in snippet

  const _SearchResult({
    required this.chunkIndex,
    required this.snippet,
    required this.matchStart,
    required this.matchEnd,
  });
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ReadingSettingsService _settingsService = ReadingSettingsService();
  ReadingSettings _settings = const ReadingSettings();

  List<_SearchResult> _results = [];
  bool _isSearching = false;
  String _progressText = '';
  int _searchId = 0; // for cancellation

  /// Max results to display — prevents building thousands of widgets.
  static const int _maxResults = 100;

  /// Debounce timer for search input.
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialSettings != null) {
      _settings = widget.initialSettings!;
    }
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (widget.initialSettings != null) return;
    final s = await _settingsService.loadSettings();
    if (mounted) {
      setState(() => _settings = s);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Debounced search — waits 300ms after last keystroke before searching.
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  /// Batched async search — processes chunks in batches, yielding
  /// between batches so the UI stays responsive. Cancelable: if the
  /// user types a new query, the old search is aborted.
  Future<void> _performSearch(String query) async {
    // Cancel any in-progress search
    _searchId++;
    final thisSearchId = _searchId;

    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _progressText = '';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _progressText = 'Searching…';
      _results = [];
    });

    final trimmedQuery = query.trim();
    final lowerQuery = trimmedQuery.toLowerCase();

    // For plain text (no regex specials), use fast case-insensitive contains.
    // Only build a regex if the query has special characters.
    final hasRegexChars = RegExp(r'[.*+?^${}()|[\]\\]').hasMatch(trimmedQuery);

    RegExp? regex;
    if (hasRegexChars) {
      try {
        regex = RegExp(RegExp.escape(trimmedQuery), caseSensitive: false);
      } catch (_) {
        setState(() {
          _results = [];
          _isSearching = false;
          _progressText = '';
        });
        return;
      }
    }

    final found = <_SearchResult>[];

    // Narrow down chunks using the search index if possible
    List<BookChunk> chunksToSearch = widget.chunks;
    if (!hasRegexChars &&
        !lowerQuery.contains(' ') &&
        widget.searchIndex.isNotEmpty) {
      // Find all unique words in the index that contain the query
      final matchingKeys = widget.searchIndex.keys.where(
        (k) => k.contains(lowerQuery),
      );
      // Gather all chunk indices that contain any of these words
      final chunkIndices = <int>{};
      for (final key in matchingKeys) {
        chunkIndices.addAll(widget.searchIndex[key]!);
      }

      final sortedIndices = chunkIndices.toList()..sort();
      // O(1) map lookups!
      chunksToSearch = sortedIndices.map((i) => widget.chunks[i]).toList();
    }

    final totalChunks = chunksToSearch.length;
    const batchSize = 200;

    for (
      int batchStart = 0;
      batchStart < totalChunks;
      batchStart += batchSize
    ) {
      // --- Check cancellation ---
      if (_searchId != thisSearchId) return;

      final batchEnd = (batchStart + batchSize).clamp(0, totalChunks);

      // Update progress
      final percent = totalChunks == 0
          ? 100
          : ((batchEnd / totalChunks) * 100).round();
      if (mounted && _searchId == thisSearchId) {
        setState(() => _progressText = 'Searching… $percent%');
      }

      // Process batch
      for (int i = batchStart; i < batchEnd; i++) {
        final chunk = chunksToSearch[i];
        if (chunk.type != BookChunkType.text) continue;
        final text = chunk.text ?? '';
        if (text.isEmpty) continue;

        // Find match position
        int matchStart;
        int matchEnd;

        if (regex != null) {
          final m = regex.firstMatch(text);
          if (m == null) continue;
          matchStart = m.start;
          matchEnd = m.end;
        } else {
          // Fast path: plain text, case-insensitive indexOf
          final lowerText = text.toLowerCase();
          matchStart = lowerText.indexOf(lowerQuery);
          if (matchStart < 0) continue;
          matchEnd = matchStart + lowerQuery.length;
        }

        final contextStart = (matchStart - 50).clamp(0, text.length);
        final contextEnd = (matchEnd + 50).clamp(0, text.length);

        String snippet = text.substring(contextStart, contextEnd);
        int localStart = matchStart - contextStart;
        int localEnd = matchEnd - contextStart;

        if (contextStart > 0) {
          snippet = '...$snippet';
          localStart += 3;
          localEnd += 3;
        }
        if (contextEnd < text.length) {
          snippet = '$snippet...';
        }

        found.add(
          _SearchResult(
            chunkIndex: chunk.index,
            snippet: snippet,
            matchStart: localStart,
            matchEnd: localEnd,
          ),
        );

        // Hit max results — stop early
        if (found.length >= _maxResults) break;
      }

      if (found.length >= _maxResults) break;

      // Yield to the main thread between batches so UI stays responsive
      await Future.delayed(Duration.zero);
    }

    // Final cancellation check
    if (_searchId != thisSearchId || !mounted) return;

    setState(() {
      _results = found;
      _isSearching = false;
      _progressText = found.length >= _maxResults
          ? '$_maxResults+ matches — showing first $_maxResults'
          : '${found.length} match${found.length == 1 ? '' : 'es'} found';
    });
  }

  @override
  Widget build(BuildContext context) {
    final textColor = _settings.textColor;
    final mutedColor = _settings.mutedColor;
    final matchColor = _settings.readerAccentColor;

    return Scaffold(
      backgroundColor: _settings.backgroundColor,
      appBar: AppBar(
        backgroundColor: _settings.menuColor,
        foregroundColor: textColor,
        elevation: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'Search within book...',
            hintStyle: TextStyle(color: mutedColor),
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: Icon(Icons.clear, color: textColor),
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
            ),
          ),
          onChanged: _onSearchChanged,
          onSubmitted: _performSearch,
        ),
      ),
      body: Column(
        children: [
          // ── Progress / result count bar ──
          if (_progressText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: _settings.menuColor.withValues(alpha: 0.5),
              child: Text(
                _progressText,
                style: TextStyle(color: mutedColor, fontSize: 12),
              ),
            ),

          // ── Search indicator ──
          if (_isSearching)
            LinearProgressIndicator(
              color: matchColor,
              backgroundColor: Colors.transparent,
            ),

          // ── Results ──
          Expanded(
            child:
                _results.isEmpty &&
                    !_isSearching &&
                    _searchController.text.isNotEmpty
                ? Center(
                    child: Text(
                      'No matches found.',
                      style: TextStyle(color: textColor, fontSize: 16),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: mutedColor.withValues(alpha: 0.3)),
                    itemBuilder: (context, index) {
                      final res = _results[index];

                      final spans = <TextSpan>[
                        TextSpan(
                          text: res.snippet.substring(0, res.matchStart),
                          style: TextStyle(color: textColor),
                        ),
                        TextSpan(
                          text: res.snippet.substring(
                            res.matchStart,
                            res.matchEnd,
                          ),
                          style: TextStyle(
                            color: matchColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: res.snippet.substring(res.matchEnd),
                          style: TextStyle(color: textColor),
                        ),
                      ];

                      return InkWell(
                        onTap: () {
                          Navigator.pop(context, res.chunkIndex);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: RichText(text: TextSpan(children: spans)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
