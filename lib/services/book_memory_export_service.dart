import '../models/book_memory_entry.dart';
import '../models/highlight.dart';
import 'book_memory_service.dart';

class BookMemoryExportService {
  String buildMarkdown(BookMemorySnapshot memory) {
    final buffer = StringBuffer()
      ..writeln('# ${memory.title}')
      ..writeln()
      ..writeln('Author: ${memory.author}')
      ..writeln('Progress: ${(memory.progress * 100).round()}%')
      ..writeln('Last read: ${_formatDateMillis(memory.lastReadTime)}')
      ..writeln();

    final linkedEntryIds = <String>{};

    _writeBookNotes(buffer, memory, linkedEntryIds);
    _writeBookmarks(buffer, memory, linkedEntryIds);
    _writeHighlights(buffer, memory, linkedEntryIds);
    _writeNotes(buffer, memory, linkedEntryIds);
    _writeWords(buffer, memory, linkedEntryIds);
    _writeCharacters(buffer, memory, linkedEntryIds);
    _writeUnlinkedThoughts(buffer, memory, linkedEntryIds);

    return buffer.toString().trimRight();
  }

  void _writeBookNotes(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Set<String> linkedEntryIds,
  ) {
    buffer.writeln('## Book Notes');
    final notes = memory.entries
        .where((entry) => entry.sourceType == BookMemorySourceType.free)
        .toList();
    if (notes.isEmpty) {
      buffer
        ..writeln('None.')
        ..writeln();
      return;
    }

    for (final entry in notes) {
      linkedEntryIds.add(entry.id);
      _writeEntry(buffer, entry);
    }
    buffer.writeln();
  }

  void _writeBookmarks(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Set<String> linkedEntryIds,
  ) {
    buffer.writeln('## Bookmarks');
    if (memory.bookmarks.isEmpty) {
      buffer
        ..writeln('None.')
        ..writeln();
      return;
    }

    for (final bookmark in memory.bookmarks) {
      buffer.writeln(
        '- ${bookmark.name} (${memory.locationLabel(bookmark.chunkIndex)}, ${_formatDate(bookmark.createdAt)})',
      );
      final preview = _clean(bookmark.previewText);
      if (preview != null) buffer.writeln('  > $preview');
      _writeLinkedEntry(
        buffer,
        memory,
        linkedEntryIds,
        BookMemorySourceType.bookmark,
        bookmark.locationKey,
      );
    }
    buffer.writeln();
  }

  void _writeHighlights(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Set<String> linkedEntryIds,
  ) {
    buffer.writeln('## Highlights');
    if (memory.highlights.isEmpty) {
      buffer
        ..writeln('None.')
        ..writeln();
      return;
    }

    for (final highlight in memory.highlights) {
      _writeHighlightLine(buffer, memory, highlight);
      _writeLinkedEntry(
        buffer,
        memory,
        linkedEntryIds,
        BookMemorySourceType.highlight,
        highlight.id,
      );
    }
    buffer.writeln();
  }

  void _writeNotes(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Set<String> linkedEntryIds,
  ) {
    buffer.writeln('## Notes');
    if (memory.notes.isEmpty) {
      buffer
        ..writeln('None.')
        ..writeln();
      return;
    }

    for (final note in memory.notes) {
      final noteText = _clean(note.note) ?? '';
      buffer.writeln(
        '- $noteText (${memory.locationLabel(note.originalChunkIndex)}, ${_formatDate(note.createdAt)})',
      );
      final quote = _clean(note.text);
      if (quote != null) buffer.writeln('  > $quote');
      _writeLinkedEntry(
        buffer,
        memory,
        linkedEntryIds,
        BookMemorySourceType.note,
        note.id,
      );
    }
    buffer.writeln();
  }

  void _writeWords(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Set<String> linkedEntryIds,
  ) {
    buffer.writeln('## Saved Words');
    if (memory.words.isEmpty) {
      buffer
        ..writeln('None.')
        ..writeln();
      return;
    }

    for (final word in memory.words) {
      final location = word.originalChunkIndex == null
          ? 'No saved location'
          : memory.locationLabel(word.originalChunkIndex!);
      buffer.writeln(
        '- ${word.word}: ${word.meaning} ($location, ${_formatDateMillis(word.timestamp)})',
      );
      final context = _clean(word.contextSentence);
      if (context != null) buffer.writeln('  > $context');
      _writeLinkedEntry(
        buffer,
        memory,
        linkedEntryIds,
        BookMemorySourceType.word,
        word.id,
      );
    }
    buffer.writeln();
  }

  void _writeCharacters(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Set<String> linkedEntryIds,
  ) {
    buffer.writeln('## Character Tags');
    if (memory.characters.isEmpty) {
      buffer.writeln('None.');
      return;
    }

    for (final character in memory.characters) {
      final mentionCount = character.occurrenceCount > 0
          ? ', ${character.occurrenceCount} mentions'
          : '';
      buffer.writeln(
        '- ${character.name} (${character.count} marked$mentionCount)',
      );
      if (character.firstOccurrence != null) {
        buffer.writeln(
          '  - First occurrence: ${memory.locationLabel(character.firstOccurrence!.chunkIndex)}',
        );
      }
      if (character.lastOccurrence != null) {
        buffer.writeln(
          '  - Last occurrence: ${memory.locationLabel(character.lastOccurrence!.chunkIndex)}',
        );
      }
      buffer.writeln('  - Marked occurrences:');
      for (final highlight in character.highlights) {
        buffer.writeln(
          '    - ${memory.locationLabel(highlight.originalChunkIndex)}: ${highlight.text}',
        );
      }
      if (character.linkedHighlights.isNotEmpty) {
        buffer.writeln('  - Linked highlights:');
        for (final highlight in character.linkedHighlights) {
          buffer.writeln(
            '    - ${memory.locationLabel(highlight.originalChunkIndex)}: ${highlight.text}',
          );
        }
      }
      if (character.linkedNotes.isNotEmpty) {
        buffer.writeln('  - Linked notes:');
        for (final note in character.linkedNotes) {
          buffer.writeln(
            '    - ${memory.locationLabel(note.originalChunkIndex)}: ${note.text}',
          );
        }
      }
      _writeLinkedEntry(
        buffer,
        memory,
        linkedEntryIds,
        BookMemorySourceType.character,
        BookMemorySnapshot.characterSourceId(character.name),
      );
    }
    buffer.writeln();
  }

  void _writeUnlinkedThoughts(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Set<String> linkedEntryIds,
  ) {
    final unlinked = memory.entries
        .where((entry) => !linkedEntryIds.contains(entry.id))
        .toList();
    if (unlinked.isEmpty) return;

    buffer.writeln('## Unlinked Thoughts');
    for (final entry in unlinked) {
      _writeEntry(buffer, entry);
    }
  }

  void _writeHighlightLine(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Highlight highlight,
  ) {
    buffer.writeln(
      '- ${highlight.text} (${memory.locationLabel(highlight.originalChunkIndex)}, ${_formatDate(highlight.createdAt)})',
    );
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateMillis(int? millis) {
    if (millis == null || millis <= 0) return 'Never';
    return _formatDate(DateTime.fromMillisecondsSinceEpoch(millis));
  }

  String? _clean(String? text) {
    final trimmed = text?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  void _writeLinkedEntry(
    StringBuffer buffer,
    BookMemorySnapshot memory,
    Set<String> linkedEntryIds,
    BookMemorySourceType type,
    String sourceId,
  ) {
    final entry = memory.entryForSource(type, sourceId);
    if (entry == null) return;
    linkedEntryIds.add(entry.id);
    _writeEntry(buffer, entry, indent: '  ');
  }

  void _writeEntry(
    StringBuffer buffer,
    BookMemoryEntry entry, {
    String indent = '',
  }) {
    final title = _clean(entry.title);
    final body = _cleanMultiline(entry.body);
    if (title != null) buffer.writeln('$indent- Writing: $title');
    if (body != null) {
      final bodyIndent = title == null ? '$indent- ' : '$indent  ';
      for (final line in body.split('\n')) {
        buffer.writeln('$bodyIndent$line');
      }
    }
  }

  String? _cleanMultiline(String? text) {
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
  }
}
