import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../models/book_chunk.dart';
import '../models/derived_book_index.dart';
import '../models/reading_settings.dart';
import '../models/stable_book_location.dart';
import '../services/book_authoritative_text_service.dart';
import '../services/derived_book_index_service.dart';
import '../services/reading_settings_service.dart';

class SearchScreen extends StatefulWidget {
  final List<BookChunk> chunks;
  final Map<String, List<int>> searchIndex;
  final Map<int, StableBookLocation> stableLocationsByChunkIndex;
  final DerivedBookIndexSession? derivedIndexSession;
  final ReadingSettings? initialSettings;

  const SearchScreen({
    super.key,
    required this.chunks,
    required this.searchIndex,
    this.stableLocationsByChunkIndex = const {},
    this.derivedIndexSession,
    this.initialSettings,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ReadingSettingsService _settingsService = ReadingSettingsService();
  ReadingSettings _settings = const ReadingSettings();

  final DerivedBookSearchService _derivedSearch =
      const DerivedBookSearchService();
  List<DerivedSearchResult> _results = [];
  DerivedIndexSnapshot? _derivedSnapshot;
  StreamSubscription<DerivedIndexSnapshot>? _indexSubscription;
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
    _attachDerivedIndex();
  }

  Future<void> _attachDerivedIndex() async {
    final session = widget.derivedIndexSession;
    if (session == null) return;
    _indexSubscription = session.changes.listen((snapshot) {
      if (!mounted) return;
      _derivedSnapshot = snapshot;
      final query = _searchController.text;
      if (query.trim().isNotEmpty) unawaited(_performSearch(query));
    });
    final snapshot = session.snapshot ?? await session.initialize();
    if (!mounted) return;
    setState(() => _derivedSnapshot = snapshot);
    session.start();
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
    _indexSubscription?.cancel();
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
    final snapshot = _derivedSnapshot;
    if (snapshot != null && snapshot.segments.isNotEmpty) {
      final merged = <String, DerivedSearchResult>{};
      for (final result in _derivedSearch.search(snapshot, trimmedQuery)) {
        merged[result.range.stableKey] = result;
      }
      for (final result in _searchUnindexedLoadedChunks(
        trimmedQuery,
        snapshot.segments.keys.toSet(),
      )) {
        merged.putIfAbsent(result.range.stableKey, () => result);
      }
      final found = merged.values.toList()
        ..sort((a, b) {
          final rank = a.rank.compareTo(b.rank);
          if (rank != 0) return rank;
          final spine = a.range.location.spineIndex.compareTo(
            b.range.location.spineIndex,
          );
          if (spine != 0) return spine;
          return a.range.paragraphStart.compareTo(b.range.paragraphStart);
        });
      if (found.length > _maxResults) {
        found.removeRange(_maxResults, found.length);
      }
      if (_searchId != thisSearchId || !mounted) return;
      final coverage = (snapshot.coverage * 100).round();
      setState(() {
        _results = found;
        _isSearching = false;
        _progressText = snapshot.isComplete
            ? '${found.length} match${found.length == 1 ? '' : 'es'} found · Full book'
            : '${found.length} match${found.length == 1 ? '' : 'es'} · $coverage% indexed';
      });
      return;
    }
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

    final found = <DerivedSearchResult>[];

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
        final text = authoritativeBookChunkTextOrEmpty(chunk);
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

        final base = widget.stableLocationsByChunkIndex[chunk.index];
        if (base != null) {
          final logicalStart = chunk.logicalParagraphStartOffset + matchStart;
          found.add(
            DerivedSearchResult(
              range: DerivedSourceRange(
                indexGeneration: 0,
                location: base.copyWith(
                  internalSegmentId: chunk.logicalParagraphId,
                  textOffset: matchStart,
                  contextText: text.substring(matchStart, matchEnd),
                ),
                logicalParagraphId:
                    chunk.logicalParagraphId ?? 'legacy-chunk-${chunk.index}',
                paragraphChecksum: sha256.convert(utf8.encode(text)).toString(),
                paragraphStart: logicalStart,
                paragraphEnd: logicalStart + (matchEnd - matchStart),
                matchText: text.substring(matchStart, matchEnd),
              ),
              snippet: snippet,
              matchStart: localStart,
              matchEnd: localEnd,
              rank: 0,
            ),
          );
        }

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

  List<DerivedSearchResult> _searchUnindexedLoadedChunks(
    String query,
    Set<int> indexedSpines,
  ) {
    final normalizedQuery = normalizeSearchTextWithSourceMap(query).text;
    if (normalizedQuery.isEmpty) return const [];
    final results = <DerivedSearchResult>[];
    for (final chunk in widget.chunks) {
      final base = widget.stableLocationsByChunkIndex[chunk.index];
      final text = authoritativeBookChunkText(chunk);
      if (base == null ||
          text == null ||
          indexedSpines.contains(base.spineIndex)) {
        continue;
      }
      final normalized = normalizeSearchTextWithSourceMap(text);
      final normalizedStart = normalized.text.indexOf(normalizedQuery);
      if (normalizedStart < 0) continue;
      final normalizedEnd = normalizedStart + normalizedQuery.length;
      final sourceStart = normalized.sourceStartForRange(
        normalizedStart,
        normalizedEnd,
      );
      final sourceEnd = normalized.sourceEndForRange(
        normalizedStart,
        normalizedEnd,
      );
      final contextStart = (sourceStart - 50).clamp(0, text.length);
      final contextEnd = (sourceEnd + 50).clamp(0, text.length);
      var snippet = text.substring(contextStart, contextEnd);
      var matchStart = sourceStart - contextStart;
      var matchEnd = sourceEnd - contextStart;
      if (contextStart > 0) {
        snippet = '…$snippet';
        matchStart++;
        matchEnd++;
      }
      if (contextEnd < text.length) snippet = '$snippet…';
      final logicalStart = chunk.logicalParagraphStartOffset + sourceStart;
      final matchText = text.substring(sourceStart, sourceEnd);
      results.add(
        DerivedSearchResult(
          range: DerivedSourceRange(
            indexGeneration: 0,
            location: base.copyWith(
              internalSegmentId: chunk.logicalParagraphId,
              textOffset: sourceStart,
              contextText: matchText,
            ),
            logicalParagraphId:
                chunk.logicalParagraphId ?? 'legacy-chunk-${chunk.index}',
            paragraphChecksum: sha256.convert(utf8.encode(text)).toString(),
            paragraphStart: logicalStart,
            paragraphEnd: logicalStart + matchText.length,
            matchText: matchText,
          ),
          snippet: snippet,
          matchStart: matchStart,
          matchEnd: matchEnd,
          rank: 0,
        ),
      );
    }
    return results;
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
                          Navigator.pop(context, res.range);
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
