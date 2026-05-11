import 'package:flutter/material.dart';

import '../models/reading_settings.dart';
import '../models/saved_word.dart';
import '../services/dictionary_service.dart';

class SavedWordsScreen extends StatefulWidget {
  final DictionaryService dictionaryService;
  final ReadingSettings? readingSettings;

  const SavedWordsScreen({
    super.key,
    required this.dictionaryService,
    this.readingSettings,
  });

  @override
  State<SavedWordsScreen> createState() => _SavedWordsScreenState();
}

class _SavedWordsScreenState extends State<SavedWordsScreen> {
  @override
  Widget build(BuildContext context) {
    final words = widget.dictionaryService.words;
    final readerTheme = _SavedWordsTheme.from(context, widget.readingSettings);

    return Scaffold(
      backgroundColor: readerTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Saved Words',
          style: TextStyle(
            color: readerTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: readerTheme.text),
      ),
      body: words.isEmpty
          ? Center(
              child: Text(
                'No saved words yet.',
                style: TextStyle(fontSize: 16, color: readerTheme.muted),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: words.length,
              itemBuilder: (context, index) {
                final savedWord = words[index];
                return _buildWordCard(savedWord, readerTheme);
              },
            ),
    );
  }

  Widget _buildWordCard(SavedWord savedWord, _SavedWordsTheme readerTheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: readerTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: readerTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  savedWord.word,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: readerTheme.text,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: Theme.of(context).colorScheme.error,
                onPressed: () async {
                  await widget.dictionaryService.deleteWord(savedWord.id);
                  setState(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Removed "${savedWord.word}"')),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            savedWord.meaning,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: readerTheme.text.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedWordsTheme {
  final Color background;
  final Color card;
  final Color text;
  final Color muted;
  final Color divider;

  const _SavedWordsTheme({
    required this.background,
    required this.card,
    required this.text,
    required this.muted,
    required this.divider,
  });

  factory _SavedWordsTheme.from(
    BuildContext context,
    ReadingSettings? settings,
  ) {
    final theme = Theme.of(context);
    if (settings == null) {
      final scheme = theme.colorScheme;
      return _SavedWordsTheme(
        background: scheme.surface,
        card: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        divider: scheme.onSurface.withValues(alpha: 0.05),
      );
    }

    return _SavedWordsTheme(
      background: settings.backgroundColor,
      card: settings.menuColor.withValues(alpha: settings.isDark ? 0.86 : 0.72),
      text: settings.textColor,
      muted: settings.mutedColor,
      divider: settings.textColor.withValues(
        alpha: settings.isDark ? 0.18 : 0.1,
      ),
    );
  }
}
