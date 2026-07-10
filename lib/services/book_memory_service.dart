import 'dart:io';

import '../models/book_memory_entry.dart';
import '../models/book_chunk.dart';
import '../models/book_metadata.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/saved_word.dart';
import '../utils/character_name_utils.dart';
import 'book_character_occurrence_service.dart';
import 'book_cache_service.dart';
import 'book_memory_entry_service.dart';
import 'book_metadata_service.dart';
import 'book_preparse_service.dart';
import 'bookmark_service.dart';
import 'dictionary_service.dart';
import 'highlight_service.dart';

class BookMemoryService {
  final BookMetadataService _metadataService;
  final BookCacheService _cacheService;
  final Future<BookPreparationResult> Function(File file)? _prepareBook;

  BookMemoryService({
    BookMetadataService? metadataService,
    BookCacheService? cacheService,
    Future<BookPreparationResult> Function(File file)? prepareBook,
  }) : _metadataService = metadataService ?? BookMetadataService(),
       _cacheService = cacheService ?? BookCacheService(),
       _prepareBook = prepareBook;

  Future<BookMemorySnapshot> load(String bookId, {File? bookFile}) async {
    await _metadataService.init();

    final metadata = _metadataService.getMetadata(bookId);
    final bookmarks = await BookmarkService(bookId: bookId).load();
    final highlights = await HighlightService(bookId: bookId).load();
    final words = await DictionaryService(bookId: bookId).loadWords();
    final entries = await BookMemoryEntryService(bookId: bookId).loadForBook();
    CachedBook? cached;
    if (bookFile != null) {
      final prepareBook =
          _prepareBook ?? BookPreparseService.instance.ensureParsed;
      final preparation = await prepareBook(bookFile);
      cached = preparation.cachedBook;
    } else {
      cached = await _cacheService.loadCachedBook(bookId);
    }
    final occurrenceService = BookCharacterOccurrenceService(bookId: bookId);
    var occurrenceIndex = await occurrenceService.load();

    var snapshot = BookMemorySnapshot.fromStorage(
      bookId: bookId,
      metadata: metadata,
      bookmarks: bookmarks,
      highlights: highlights,
      words: words,
      entries: entries,
      occurrenceIndex: occurrenceIndex,
      chapters: cached?.chapters ?? const [],
    );

    if (cached != null && snapshot.characters.isNotEmpty) {
      final updated = _updateOccurrenceIndex(
        occurrenceIndex,
        snapshot.characters,
        cached.chunks,
      );
      if (!identical(updated, occurrenceIndex)) {
        occurrenceIndex = updated;
        await occurrenceService.save(occurrenceIndex);
        snapshot = BookMemorySnapshot.fromStorage(
          bookId: bookId,
          metadata: metadata,
          bookmarks: bookmarks,
          highlights: highlights,
          words: words,
          entries: entries,
          occurrenceIndex: occurrenceIndex,
          chapters: cached.chapters,
        );
      }
    }

    return snapshot;
  }

  StoredCharacterOccurrenceIndex _updateOccurrenceIndex(
    StoredCharacterOccurrenceIndex current,
    List<CharacterMemoryGroup> characters,
    List<BookChunk> chunks,
  ) {
    final updated = Map<String, StoredCharacterOccurrence>.from(
      current.occurrences,
    );
    final activeSourceIds = characters.map((item) => item.sourceId).toSet();
    for (final sourceId in updated.keys.toList()) {
      if (!activeSourceIds.contains(sourceId)) {
        updated.remove(sourceId);
      }
    }
    var changed = updated.length != current.occurrences.length;
    final sourceSignature = _chunkSourceSignature(chunks);

    for (final character in characters) {
      final stored = current[character.sourceId];
      if (stored != null &&
          stored.isFresh(
            expectedAliases: character.aliases,
            expectedSourceSignature: sourceSignature,
          )) {
        continue;
      }
      updated[character.sourceId] = _scanCharacterOccurrences(
        character.aliases,
        chunks,
        sourceSignature,
      );
      changed = true;
    }

    return changed ? current.copyWith(updated) : current;
  }

  StoredCharacterOccurrenceIndex updateOccurrenceIndexForTesting(
    StoredCharacterOccurrenceIndex current,
    List<CharacterMemoryGroup> characters,
    List<BookChunk> chunks,
  ) {
    return _updateOccurrenceIndex(current, characters, chunks);
  }

  StoredCharacterOccurrence _scanCharacterOccurrences(
    List<String> aliases,
    List<BookChunk> chunks,
    String sourceSignature,
  ) {
    CharacterOccurrencePosition? first;
    CharacterOccurrencePosition? last;
    var count = 0;
    final sortedAliases = List<String>.from(aliases)
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final chunk in _storySearchChunks(chunks)) {
      final text = chunk.text;
      if (text == null || text.isEmpty) continue;
      final chunkMatches = <_CharacterTextMatch>[];
      for (final alias in sortedAliases) {
        for (final match in BookMemorySnapshot._characterMatches(text, alias)) {
          final overlaps = chunkMatches.any(
            (existing) =>
                existing.start < match.end && match.start < existing.end,
          );
          if (!overlaps) chunkMatches.add(match);
        }
      }
      chunkMatches.sort((a, b) => a.start.compareTo(b.start));
      for (final match in chunkMatches) {
        count++;
        final position = CharacterOccurrencePosition(
          chunkIndex: chunk.index,
          startOffset: match.start,
          endOffset: match.end,
          text: text.substring(match.start, match.end),
        );
        if (first == null ||
            BookMemorySnapshot._comparePosition(position, first) < 0) {
          first = position;
        }
        if (last == null ||
            BookMemorySnapshot._comparePosition(position, last) > 0) {
          last = position;
        }
      }
    }

    return StoredCharacterOccurrence(
      aliases: aliases,
      first: first,
      last: last,
      count: count,
      sourceSignature: sourceSignature,
    );
  }

  List<BookChunk> _storySearchChunks(List<BookChunk> chunks) {
    final storyChunks = <BookChunk>[];
    for (final chunk in chunks) {
      final text = chunk.text;
      if (text == null || text.trim().isEmpty) continue;
      if (chunk.section != ChunkSection.content) continue;
      if (_isPostStoryMarker(text)) break;
      if (_isBackMatterHeading(chunk, text)) break;
      storyChunks.add(chunk);
    }
    return storyChunks;
  }

  bool _isPostStoryMarker(String text) {
    final normalized = _normalizedBoundaryText(text);
    return normalized.contains('end of the project gutenberg ebook') ||
        normalized.contains('end of this project gutenberg ebook') ||
        normalized.contains('start full license') ||
        normalized.contains('end full license') ||
        normalized.contains('the full project gutenberg license') ||
        normalized.contains('full project gutenberg license') ||
        normalized.contains('full project gutenberg tm license') ||
        normalized.contains('full project gutenbergtm license') ||
        normalized.contains('full project gutenberg license available') ||
        normalized.contains('project gutenberg literary archive foundation');
  }

  bool _isBackMatterHeading(BookChunk chunk, String text) {
    if (!chunk.isHeading) return false;
    final normalized = _normalizedBoundaryText(text);
    const headings = {
      'about the author',
      'acknowledgments',
      'acknowledgements',
      'also by',
      'appendix',
      'bibliography',
      'copyright',
      'further reading',
      'license',
      'licence',
      'notes',
      'publisher',
      'table of contents',
    };
    return headings.contains(normalized);
  }

  String _normalizedBoundaryText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\u2122*_\-]+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _chunkSourceSignature(List<BookChunk> chunks) {
    const occurrenceScanVersion = 2;
    if (chunks.isEmpty) return 'empty';
    var textLength = 0;
    for (final chunk in chunks) {
      textLength += chunk.text?.length ?? 0;
    }
    return 'v$occurrenceScanVersion:${chunks.length}:${chunks.first.index}:${chunks.last.index}:$textLength';
  }
}

class BookMemorySnapshot {
  final String bookId;
  final String title;
  final String author;
  final String? coverImagePath;
  final int lastReadIndex;
  final int totalChunks;
  final int? lastReadTime;
  final List<Bookmark> bookmarks;
  final List<Highlight> highlights;
  final List<Highlight> notes;
  final List<SavedWord> words;
  final List<CharacterMemoryGroup> characters;
  final List<BookMemoryEntry> entries;
  final List<ChapterInfo> chapters;
  final Map<String, BookMemoryEntry> _entriesBySource;

  BookMemorySnapshot({
    required this.bookId,
    required this.title,
    required this.author,
    required this.coverImagePath,
    required this.lastReadIndex,
    required this.totalChunks,
    required this.lastReadTime,
    required this.bookmarks,
    required this.highlights,
    required this.notes,
    required this.words,
    required this.characters,
    required this.entries,
    required this.chapters,
  }) : _entriesBySource = _buildEntriesBySource(entries);

  factory BookMemorySnapshot.empty({
    required String bookId,
    String title = 'Unknown Book',
    String author = 'Unknown Author',
  }) {
    return BookMemorySnapshot(
      bookId: bookId,
      title: title,
      author: author,
      coverImagePath: null,
      lastReadIndex: 0,
      totalChunks: 0,
      lastReadTime: null,
      bookmarks: const [],
      highlights: const [],
      notes: const [],
      words: const [],
      characters: const [],
      entries: const [],
      chapters: const [],
    );
  }

  factory BookMemorySnapshot.fromStorage({
    required String bookId,
    required BookMetadata? metadata,
    required List<Bookmark> bookmarks,
    required List<Highlight> highlights,
    required List<SavedWord> words,
    List<BookMemoryEntry> entries = const [],
    StoredCharacterOccurrenceIndex? occurrenceIndex,
    required List<ChapterInfo> chapters,
  }) {
    final logicalAnnotations = _logicalAnnotations(highlights);
    final regularHighlights = logicalAnnotations
        .where((item) => item.isRegularHighlight && !item.hasNote)
        .toList(growable: false);
    final notes = logicalAnnotations
        .where((item) => !item.isCharacter && item.hasNote)
        .toList(growable: false);
    final characters = _characterGroups(
      highlights,
      regularHighlights,
      notes,
      occurrenceIndex,
    );

    return BookMemorySnapshot(
      bookId: bookId,
      title: _fallbackText(metadata?.title, bookId),
      author: _fallbackText(metadata?.author, 'Unknown Author'),
      coverImagePath: metadata?.coverImagePath,
      lastReadIndex: metadata?.lastReadIndex ?? 0,
      totalChunks: metadata?.totalChunks ?? 0,
      lastReadTime: metadata?.lastReadTime,
      bookmarks: List.unmodifiable(bookmarks),
      highlights: regularHighlights,
      notes: notes,
      words: List.unmodifiable(words),
      characters: characters,
      entries: List.unmodifiable(entries.where((entry) => !entry.isEmpty)),
      chapters: List.unmodifiable(chapters),
    );
  }

  double get progress {
    if (totalChunks <= 1) return totalChunks == 1 ? 1.0 : 0.0;
    return (lastReadIndex / (totalChunks - 1)).clamp(0.0, 1.0);
  }

  int get totalMemoryItems =>
      bookmarks.length +
      highlights.length +
      notes.length +
      words.length +
      characters.length;

  List<BookMemoryEntry> get recentWrittenEntries {
    final written = entries.where((entry) => !entry.isEmpty).toList();
    written.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return List.unmodifiable(written);
  }

  BookMemoryEntry? entryForSource(BookMemorySourceType type, String sourceId) {
    return _entriesBySource[_entrySourceKey(type, sourceId)];
  }

  bool hasEntryForSource(BookMemorySourceType type, String sourceId) {
    return entryForSource(type, sourceId) != null;
  }

  String locationLabel(int chunkIndex) {
    if (chunkIndex < 0) return 'Page/Chunk 1';
    final chapter = _chapterForChunk(chunkIndex);
    final fallback = 'Page/Chunk ${chunkIndex + 1}';
    if (chapter == null) return fallback;
    return '${chapter.title} • $fallback';
  }

  ChapterInfo? _chapterForChunk(int chunkIndex) {
    if (chapters.isEmpty) return null;

    final flat = <ChapterInfo>[];
    void walk(List<ChapterInfo> nodes) {
      for (final chapter in nodes) {
        flat.add(chapter);
        if (chapter.children.isNotEmpty) walk(chapter.children);
      }
    }

    walk(chapters);
    flat.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

    ChapterInfo? current;
    for (final chapter in flat) {
      if (chapter.chunkIndex <= chunkIndex) {
        current = chapter;
      } else {
        break;
      }
    }
    return current;
  }

  static String _fallbackText(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  static List<CharacterMemoryGroup> _characterGroups(
    List<Highlight> allHighlights,
    List<Highlight> regularHighlights,
    List<Highlight> notes,
    StoredCharacterOccurrenceIndex? occurrenceIndex,
  ) {
    final identities = <_CharacterIdentity>[];

    for (final highlight in allHighlights.where((item) => item.isCharacter)) {
      final name = _normalizeDisplayName(highlight.text);
      if (name.isEmpty) continue;
      final aliases = _characterAliases(name);
      final existing = identities.where((identity) {
        return identity.matchesAnyAlias(aliases);
      }).toList();
      if (existing.isEmpty) {
        identities.add(_CharacterIdentity(name, aliases, [highlight]));
        continue;
      }

      final target = existing.first;
      target.add(name, aliases, highlight);
      for (final duplicate in existing.skip(1)) {
        target.merge(duplicate);
        identities.remove(duplicate);
      }
    }

    final groups = identities.map((identity) {
      final highlights = List<Highlight>.from(identity.highlights)
        ..sort(_compareHighlightLocation);
      final sourceId = _normalizeCharacterName(identity.name);
      final occurrence = occurrenceIndex?[sourceId];
      return CharacterMemoryGroup(
        name: identity.name,
        aliases: List.unmodifiable(identity.aliases),
        highlights: List.unmodifiable(highlights),
        firstOccurrence: occurrence?.first,
        lastOccurrence: occurrence?.last,
        occurrenceCount: occurrence?.count ?? 0,
        linkedHighlights: List.unmodifiable(
          regularHighlights.where(
            (item) => _matchesCharacterAlias(item.text, identity.aliasList),
          ),
        ),
        linkedNotes: List.unmodifiable(
          notes.where(
            (item) => _matchesCharacterAlias(item.text, identity.aliasList),
          ),
        ),
      );
    }).toList();
    groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(groups);
  }

  static String characterSourceId(String text) {
    return _normalizeCharacterName(text);
  }

  static List<Highlight> _logicalAnnotations(List<Highlight> highlights) {
    final grouped = <String, List<Highlight>>{};
    final order = <String>[];

    for (final highlight in highlights.where((item) => !item.isCharacter)) {
      if (!grouped.containsKey(highlight.id)) {
        order.add(highlight.id);
        grouped[highlight.id] = <Highlight>[];
      }
      grouped[highlight.id]!.add(highlight);
    }

    return List.unmodifiable(order.map((id) => _mergeHighlights(grouped[id]!)));
  }

  static Highlight _mergeHighlights(List<Highlight> items) {
    if (items.length == 1) return items.single;

    final first = items.first;
    final sorted = List<Highlight>.from(items)
      ..sort((a, b) {
        final chunkCompare = a.originalChunkIndex.compareTo(
          b.originalChunkIndex,
        );
        if (chunkCompare != 0) return chunkCompare;
        return a.startOffset.compareTo(b.startOffset);
      });
    final mergedText = sorted
        .map((item) => item.text.trim())
        .where((text) => text.isNotEmpty)
        .join(' ');
    final mergedNote = sorted
        .map((item) => item.note?.trim() ?? '')
        .firstWhere((note) => note.isNotEmpty, orElse: () => '');

    return Highlight(
      id: first.id,
      originalChunkIndex: sorted.first.originalChunkIndex,
      startOffset: sorted.first.startOffset,
      endOffset: sorted.last.endOffset,
      text: mergedText,
      colorIndex: first.colorIndex,
      colorValue: first.colorValue,
      type: first.type,
      createdAt: first.createdAt,
      note: mergedNote.isEmpty ? first.note : mergedNote,
    );
  }

  static String _normalizeCharacterName(String text) {
    return normalizeCharacterNameForKey(text);
  }

  static String _normalizeDisplayName(String text) {
    return normalizeCharacterNameForDisplay(text);
  }

  static List<String> _characterAliases(String name) {
    return characterNameAliases(name);
  }

  static bool _matchesCharacterAlias(String text, List<String> aliases) {
    return aliases.any((alias) => _characterMatches(text, alias).isNotEmpty);
  }

  static List<_CharacterTextMatch> _characterMatches(
    String text,
    String alias,
  ) {
    final normalizedAlias = alias.trim();
    if (normalizedAlias.isEmpty) return const [];

    final matches = <_CharacterTextMatch>[];
    final textLower = text.toLowerCase();
    final aliasLower = normalizedAlias.toLowerCase();
    var searchFrom = 0;

    while (searchFrom < textLower.length) {
      final index = textLower.indexOf(aliasLower, searchFrom);
      if (index == -1) break;
      final end = index + normalizedAlias.length;
      final charBefore = index > 0 ? text[index - 1] : ' ';
      final charAfter = end < text.length ? text[end] : ' ';
      final startsCleanly = !RegExp(r'[A-Za-z]').hasMatch(charBefore);
      final endsCleanly =
          !RegExp(r'[A-Za-z]').hasMatch(charAfter) ||
          charAfter == '\'' ||
          charAfter == '\u2019';
      if (startsCleanly && endsCleanly) {
        matches.add(_CharacterTextMatch(index, end));
      }
      searchFrom = index + 1;
    }

    return matches;
  }

  static int _compareHighlightLocation(Highlight a, Highlight b) {
    final chunk = a.originalChunkIndex.compareTo(b.originalChunkIndex);
    if (chunk != 0) return chunk;
    return a.startOffset.compareTo(b.startOffset);
  }

  static int _comparePosition(
    CharacterOccurrencePosition a,
    CharacterOccurrencePosition b,
  ) {
    final chunk = a.chunkIndex.compareTo(b.chunkIndex);
    if (chunk != 0) return chunk;
    return a.startOffset.compareTo(b.startOffset);
  }

  static Map<String, BookMemoryEntry> _buildEntriesBySource(
    List<BookMemoryEntry> entries,
  ) {
    final bySource = <String, BookMemoryEntry>{};
    for (final entry in entries) {
      if (entry.sourceType == BookMemorySourceType.free) continue;
      final sourceId = entry.sourceId;
      if (sourceId == null || sourceId.trim().isEmpty || entry.isEmpty) {
        continue;
      }
      bySource[_entrySourceKey(entry.sourceType, sourceId)] = entry;
    }
    return Map.unmodifiable(bySource);
  }

  static String _entrySourceKey(BookMemorySourceType type, String sourceId) {
    return '${type.name}:${sourceId.trim()}';
  }
}

class CharacterMemoryGroup {
  final String name;
  final List<String> aliases;
  final List<Highlight> highlights;
  final CharacterOccurrencePosition? firstOccurrence;
  final CharacterOccurrencePosition? lastOccurrence;
  final int occurrenceCount;
  final List<Highlight> linkedHighlights;
  final List<Highlight> linkedNotes;

  const CharacterMemoryGroup({
    required this.name,
    required this.aliases,
    required this.highlights,
    required this.firstOccurrence,
    required this.lastOccurrence,
    required this.occurrenceCount,
    required this.linkedHighlights,
    required this.linkedNotes,
  });

  String get sourceId => BookMemorySnapshot.characterSourceId(name);
  int get count => highlights.length;
  Highlight get first => firstMarked;
  Highlight get firstMarked => highlights.first;

  Highlight get oldestMarked =>
      highlights.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);

  Highlight get latestMarked =>
      highlights.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);

  int get linkedInputCount => linkedHighlights.length + linkedNotes.length;
}

class _CharacterIdentity {
  String name;
  final Set<String> aliases;
  final List<Highlight> highlights;

  _CharacterIdentity(this.name, List<String> aliases, this.highlights)
    : aliases = aliases.toSet();

  void add(String nextName, List<String> nextAliases, Highlight highlight) {
    if (_nameScore(nextName) > _nameScore(name)) name = nextName;
    _addAliases(nextAliases);
    highlights.add(highlight);
  }

  void merge(_CharacterIdentity other) {
    if (_nameScore(other.name) > _nameScore(name)) name = other.name;
    _addAliases(other.aliases);
    highlights.addAll(other.highlights);
  }

  List<String> get aliasList => aliases.toList(growable: false);

  bool matchesAnyAlias(List<String> nextAliases) {
    final normalized = aliases.map(BookMemorySnapshot._normalizeCharacterName);
    final nextNormalized = nextAliases.map(
      BookMemorySnapshot._normalizeCharacterName,
    );
    return normalized.any(nextNormalized.contains);
  }

  void _addAliases(Iterable<String> nextAliases) {
    final normalized = aliases
        .map(BookMemorySnapshot._normalizeCharacterName)
        .toSet();
    for (final alias in nextAliases) {
      if (normalized.add(BookMemorySnapshot._normalizeCharacterName(alias))) {
        aliases.add(alias);
      }
    }
  }

  int _nameScore(String value) {
    return value.split(RegExp(r'\s+')).length * 1000 + value.length;
  }
}

class _CharacterTextMatch {
  final int start;
  final int end;

  const _CharacterTextMatch(this.start, this.end);
}
