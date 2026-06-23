import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/reading_settings.dart';
import '../ui/app_visuals.dart';
import 'highlight_palette_sheet.dart';

class BookmarkEditResult {
  final String name;
  final Color color;

  const BookmarkEditResult({required this.name, required this.color});
}

class BookmarkEditDialog extends StatefulWidget {
  final String initialName;
  final Color initialColor;
  final List<Color> sharedPalette;
  final ReadingSettings settings;
  final Future<List<Color>> Function(Color color) onAddCustomColor;
  final Future<List<Color>> Function(Color color) onRemoveCustomColor;
  final Future<List<Color>> Function() onResetPalette;

  const BookmarkEditDialog({
    super.key,
    required this.initialName,
    required this.initialColor,
    required this.sharedPalette,
    required this.settings,
    required this.onAddCustomColor,
    required this.onRemoveCustomColor,
    required this.onResetPalette,
  });

  @override
  State<BookmarkEditDialog> createState() => _BookmarkEditDialogState();
}

class _BookmarkEditDialogState extends State<BookmarkEditDialog> {
  late final TextEditingController _controller;
  late Color _selectedColor;
  late List<Color> _palette;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _selectedColor = _normalize(widget.initialColor);
    _palette = widget.sharedPalette.map(_normalize).toList();
  }

  @override
  void didUpdateWidget(covariant BookmarkEditDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharedPalette != widget.sharedPalette) {
      _palette = widget.sharedPalette.map(_normalize).toList();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _normalize(Color color) => Color(bookmarkColorValue(color));

  bool _isSameColor(Color a, Color b) =>
      bookmarkColorValue(a) == bookmarkColorValue(b);

  List<Color> get _colorOptions {
    final colors = <Color>[];
    final seen = <int>{};

    void add(Color color) {
      final normalized = _normalize(color);
      if (!seen.add(bookmarkColorValue(normalized))) return;
      colors.add(normalized);
    }

    add(kBookmarkColors.first);
    for (final color in _palette) {
      add(color);
    }
    if (!seen.contains(bookmarkColorValue(_selectedColor))) {
      add(_selectedColor);
    }

    return colors;
  }

  Future<List<Color>> _addCustomColor(Color color) async {
    final updated = await widget.onAddCustomColor(color);
    if (mounted) {
      setState(() => _palette = updated.map(_normalize).toList());
    }
    return updated;
  }

  Future<List<Color>> _removeCustomColor(Color color) async {
    final updated = await widget.onRemoveCustomColor(color);
    if (mounted) {
      setState(() => _palette = updated.map(_normalize).toList());
    }
    return updated;
  }

  Future<List<Color>> _resetPalette() async {
    final updated = await widget.onResetPalette();
    if (mounted) {
      setState(() => _palette = updated.map(_normalize).toList());
    }
    return updated;
  }

  Future<void> _openColorPicker() async {
    await showHighlightPaletteSheet(
      context,
      title: 'Choose bookmark color',
      palette: _palette,
      selectedColor: _selectedColor,
      readingSettings: widget.settings,
      fallbackColor: kBookmarkColors.first,
      onColorSelected: (color) {
        setState(() => _selectedColor = _normalize(color));
      },
      onAddCustomColor: _addCustomColor,
      onRemoveCustomColor: _removeCustomColor,
      onResetPalette: _resetPalette,
    );
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(
      context,
    ).pop(BookmarkEditResult(name: name, color: _selectedColor));
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final screenSize = MediaQuery.sizeOf(context);
    final maxDialogWidth = (screenSize.width - 80).clamp(120.0, 560.0);
    final maxColorHeight = (screenSize.height * 0.28).clamp(116.0, 220.0);

    return AlertDialog(
      backgroundColor: settings.backgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: settings.textColor.withValues(alpha: 0.2)),
      ),
      title: Text('Edit Bookmark', style: TextStyle(color: settings.textColor)),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxDialogWidth.toDouble()),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: settings.textColor),
              decoration: InputDecoration(
                hintText: 'Bookmark name',
                hintStyle: TextStyle(color: settings.mutedColor),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: settings.mutedColor.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: settings.textColor),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxColorHeight),
              child: SingleChildScrollView(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    for (final color in _colorOptions)
                      _BookmarkColorSwatch(
                        key: ValueKey(
                          'bookmark_color_${bookmarkColorHex(color)}',
                        ),
                        color: color,
                        isSelected: _isSameColor(color, _selectedColor),
                        selectionColor: settings.textColor,
                        onTap: () {
                          setState(() => _selectedColor = _normalize(color));
                        },
                      ),
                    _BookmarkAddColorButton(
                      textColor: settings.textColor,
                      mutedColor: settings.mutedColor,
                      onTap: _openColorPicker,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: settings.textColor)),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: settings.accentColor,
            foregroundColor: AppUi.foregroundFor(settings.accentColor),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _BookmarkColorSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final Color selectionColor;
  final VoidCallback onTap;

  const _BookmarkColorSwatch({
    super.key,
    required this.color,
    required this.isSelected,
    required this.selectionColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Bookmark color ${bookmarkColorHex(color)}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? selectionColor : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.bookmark_rounded, color: color, size: 32),
        ),
      ),
    );
  }
}

class _BookmarkAddColorButton extends StatelessWidget {
  final Color textColor;
  final Color mutedColor;
  final VoidCallback onTap;

  const _BookmarkAddColorButton({
    required this.textColor,
    required this.mutedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add bookmark color',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: mutedColor.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.add_rounded, color: textColor, size: 26),
        ),
      ),
    );
  }
}
