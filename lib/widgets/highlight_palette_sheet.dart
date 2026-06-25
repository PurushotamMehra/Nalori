import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/highlight.dart';
import '../models/reading_settings.dart';
import '../services/highlight_palette_service.dart';

typedef HighlightPaletteMutation = Future<List<Color>> Function(Color color);
typedef HighlightPaletteReset = Future<List<Color>> Function();

const double _kCompactSheetSize = 0.17;
const double _kExpandedSheetSize = 0.62;
const double _kExpandedThreshold = 0.3;

Future<void> showHighlightPaletteSheet(
  BuildContext context, {
  required List<Color> palette,
  required Color selectedColor,
  required ValueChanged<Color> onColorSelected,
  required HighlightPaletteMutation onAddCustomColor,
  required HighlightPaletteMutation onRemoveCustomColor,
  required HighlightPaletteReset onResetPalette,
  ReadingSettings? readingSettings,
  String title = 'Highlight colors',
  int maxPaletteColors = HighlightPaletteService.maxHighlightColors,
  Color fallbackColor = const Color(0xFFEF5350),
  String compactHint =
      'Pick a saved color, or tap + and drag up for the color wheel.',
  String expandedHint =
      'Save the draft to your palette, remove it, or use it directly.',
  String resetMessage = 'Reset to the system colors.',
}) {
  Color? stagedColor;

  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _HighlightPaletteSheet(
      initialPalette: palette,
      selectedColor: selectedColor,
      onColorStaged: (color) => stagedColor = color,
      onAddCustomColor: onAddCustomColor,
      onRemoveCustomColor: onRemoveCustomColor,
      onResetPalette: onResetPalette,
      readingSettings: readingSettings,
      title: title,
      maxPaletteColors: maxPaletteColors,
      fallbackColor: fallbackColor,
      compactHint: compactHint,
      expandedHint: expandedHint,
      resetMessage: resetMessage,
    ),
  ).then((result) {
    final resolvedColor = result ?? stagedColor;
    if (resolvedColor == null ||
        isSameHighlightColor(resolvedColor, selectedColor)) {
      return;
    }
    onColorSelected(resolvedColor);
  });
}

class _HighlightPaletteSheet extends StatefulWidget {
  final List<Color> initialPalette;
  final Color selectedColor;
  final ValueChanged<Color> onColorStaged;
  final HighlightPaletteMutation onAddCustomColor;
  final HighlightPaletteMutation onRemoveCustomColor;
  final HighlightPaletteReset onResetPalette;
  final ReadingSettings? readingSettings;
  final String title;
  final int maxPaletteColors;
  final Color fallbackColor;
  final String compactHint;
  final String expandedHint;
  final String resetMessage;

  const _HighlightPaletteSheet({
    required this.initialPalette,
    required this.selectedColor,
    required this.onColorStaged,
    required this.onAddCustomColor,
    required this.onRemoveCustomColor,
    required this.onResetPalette,
    this.readingSettings,
    required this.title,
    required this.maxPaletteColors,
    required this.fallbackColor,
    required this.compactHint,
    required this.expandedHint,
    required this.resetMessage,
  });

  @override
  State<_HighlightPaletteSheet> createState() => _HighlightPaletteSheetState();
}

class _HighlightPaletteSheetState extends State<_HighlightPaletteSheet> {
  late final DraggableScrollableController _sheetController;
  late final TextEditingController _hexController;

  late List<Color> _palette;
  late Color _selectedColor;
  late HSVColor _draftColor;

  bool _isMutating = false;
  double _sheetSize = _kCompactSheetSize;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController();
    _sheetController.addListener(_handleSheetSizeChanged);

    _palette = widget.initialPalette.map(_normalizeColor).toList();
    _selectedColor = _normalizeColor(widget.selectedColor);
    _draftColor = HSVColor.fromColor(_selectedColor);
    _hexController = TextEditingController(
      text: highlightColorHex(_selectedColor),
    );
  }

  @override
  void dispose() {
    _sheetController.removeListener(_handleSheetSizeChanged);
    _sheetController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  Color get _draftMaterialColor => _normalizeColor(_draftColor.toColor());

  bool get _isExpanded => _sheetSize >= _kExpandedThreshold;

  bool get _draftExistsInPalette => _containsColor(_draftMaterialColor);

  bool get _canAddDraftColor =>
      !_draftExistsInPalette && _palette.length < widget.maxPaletteColors;

  bool get _canRemoveDraftColor => _draftExistsInPalette && _palette.length > 1;

  void _handleSheetSizeChanged() {
    if (!_sheetController.isAttached) return;
    final newSize = _sheetController.size;
    if ((newSize - _sheetSize).abs() < 0.001) return;
    setState(() => _sheetSize = newSize);
  }

  Color _normalizeColor(Color color) => Color(highlightColorValue(color));

  bool _paletteContains(List<Color> palette, Color color) =>
      palette.any((entry) => isSameHighlightColor(entry, color));

  bool _containsColor(Color color) => _paletteContains(_palette, color);

  void _syncDraftColor(Color color) {
    final normalized = _normalizeColor(color);
    _draftColor = HSVColor.fromColor(normalized);
    _hexController.text = highlightColorHex(normalized);
    _hexError = null;
  }

  void _selectAndClose(Color color) {
    final normalized = _normalizeColor(color);
    Navigator.pop(context, normalized);
  }

  void _stageSelectedColor(Color color) {
    final normalized = _normalizeColor(color);
    setState(() {
      _selectedColor = normalized;
      _syncDraftColor(normalized);
    });
    widget.onColorStaged(normalized);
  }

  void _handlePaletteTap(Color color) {
    if (_isExpanded) {
      _stageSelectedColor(color);
      return;
    }
    _selectAndClose(color);
  }

  Future<void> _expandSheet() async {
    if (!_sheetController.isAttached) return;
    await _sheetController.animateTo(
      _kExpandedSheetSize,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _addDraftColorToPalette() async {
    final draftColor = _draftMaterialColor;

    if (_draftExistsInPalette) {
      _showMessage(
        '${highlightColorHex(draftColor)} is already in your palette.',
      );
      return;
    }

    if (!_canAddDraftColor) {
      _showMessage(
        'You can save up to ${widget.maxPaletteColors} colors. Remove one first.',
      );
      return;
    }

    setState(() => _isMutating = true);
    final updatedPalette = await widget.onAddCustomColor(draftColor);
    if (!mounted) return;

    setState(() {
      _palette = updatedPalette.map(_normalizeColor).toList();
      _selectedColor = draftColor;
      _syncDraftColor(draftColor);
      _isMutating = false;
    });
    widget.onColorStaged(draftColor);

    _showMessage('Saved ${highlightColorHex(draftColor)} to your palette.');
  }

  Future<void> _removeDraftColorFromPalette() async {
    final draftColor = _draftMaterialColor;
    if (!_draftExistsInPalette) return;
    if (!_canRemoveDraftColor) {
      _showMessage('Keep at least one color in your palette.');
      return;
    }

    setState(() => _isMutating = true);
    final updatedPalette = await widget.onRemoveCustomColor(draftColor);
    if (!mounted) return;

    final normalizedUpdatedPalette = updatedPalette
        .map(_normalizeColor)
        .toList();
    final fallback = _paletteContains(normalizedUpdatedPalette, _selectedColor)
        ? _selectedColor
        : normalizedUpdatedPalette.lastOrNull ?? widget.fallbackColor;

    setState(() {
      _palette = normalizedUpdatedPalette;
      _selectedColor = _normalizeColor(fallback);
      _syncDraftColor(_selectedColor);
      _isMutating = false;
    });
    widget.onColorStaged(_selectedColor);

    _showMessage('Removed ${highlightColorHex(draftColor)} from your palette.');
  }

  Future<void> _resetPalette() async {
    setState(() => _isMutating = true);
    final updatedPalette = await widget.onResetPalette();
    if (!mounted) return;

    final normalizedUpdatedPalette = updatedPalette
        .map(_normalizeColor)
        .toList();
    final nextSelected =
        _paletteContains(normalizedUpdatedPalette, _draftMaterialColor)
        ? _draftMaterialColor
        : normalizedUpdatedPalette.lastOrNull ?? widget.fallbackColor;

    setState(() {
      _palette = normalizedUpdatedPalette;
      _selectedColor = _normalizeColor(nextSelected);
      _syncDraftColor(_selectedColor);
      _isMutating = false;
    });
    widget.onColorStaged(_selectedColor);

    _showMessage(widget.resetMessage);
  }

  void _handleHexChanged(String value) {
    final parsed = parseHighlightHexColor(value);
    setState(() {
      if (value.trim().isEmpty) {
        _hexError = 'Enter a 6-digit hex color.';
        return;
      }
      if (parsed == null) {
        _hexError = 'Use a valid #RRGGBB color.';
        return;
      }

      _syncDraftColor(parsed);
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _useDraftColor() {
    _selectAndClose(_draftMaterialColor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readerTheme = _ReaderPaletteTheme.from(
      context,
      widget.readingSettings,
    );
    final wheelSize = math.min(MediaQuery.sizeOf(context).width - 72, 260.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: _kCompactSheetSize,
          minChildSize: _kCompactSheetSize,
          maxChildSize: _kExpandedSheetSize,
          snap: true,
          snapSizes: const [_kCompactSheetSize, _kExpandedSheetSize],
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: readerTheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: readerTheme.divider,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: readerTheme.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_isMutating)
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.1,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 54,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final color in _palette) ...[
                                  _PaletteSwatch(
                                    key: ValueKey(
                                      'highlight_palette_${highlightColorHex(color)}',
                                    ),
                                    color: color,
                                    isSelected: isSameHighlightColor(
                                      color,
                                      _selectedColor,
                                    ),
                                    selectionColor: readerTheme.text,
                                    checkColor: readerTheme.surface,
                                    onTap: () => _handlePaletteTap(color),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                _AddSwatchButton(
                                  enabled: !_isMutating,
                                  theme: readerTheme,
                                  onTap: _expandSheet,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isExpanded
                                ? widget.expandedHint
                                : widget.compactHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: readerTheme.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isExpanded)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(height: 1, color: readerTheme.divider),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: readerTheme.subtleSurface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: readerTheme.divider),
                              ),
                              child: Row(
                                children: [
                                  _ColorDot(
                                    color: _draftMaterialColor,
                                    size: 48,
                                    borderColor: readerTheme.surface,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _draftExistsInPalette
                                              ? 'Saved color'
                                              : 'Draft color',
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                                color: readerTheme.muted,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          highlightColorHex(
                                            _draftMaterialColor,
                                          ),
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                color: readerTheme.text,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _isMutating
                                        ? null
                                        : _draftExistsInPalette
                                        ? (_canRemoveDraftColor
                                              ? _removeDraftColorFromPalette
                                              : null)
                                        : (_canAddDraftColor
                                              ? _addDraftColorToPalette
                                              : null),
                                    icon: Icon(
                                      _draftExistsInPalette
                                          ? Icons.delete_outline_rounded
                                          : Icons.add_rounded,
                                    ),
                                    label: Text(
                                      _draftExistsInPalette
                                          ? 'Remove'
                                          : 'Add Color',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: _draftExistsInPalette
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Center(
                              child: SizedBox(
                                width: wheelSize,
                                height: wheelSize,
                                child: _ColorWheelPicker(
                                  color: _draftColor,
                                  onChanged: (color) {
                                    setState(() {
                                      _draftColor = color;
                                      _hexController.text = highlightColorHex(
                                        _draftMaterialColor,
                                      );
                                      _hexError = null;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _SliderSection(
                              label: 'Brightness',
                              valueLabel:
                                  '${(_draftColor.value * 100).round()}%',
                              value: _draftColor.value,
                              activeColor: _draftMaterialColor,
                              theme: readerTheme,
                              onChanged: (value) {
                                setState(() {
                                  _draftColor = _draftColor.withValue(value);
                                  _hexController.text = highlightColorHex(
                                    _draftMaterialColor,
                                  );
                                  _hexError = null;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _hexController,
                              onChanged: _handleHexChanged,
                              style: TextStyle(color: readerTheme.text),
                              cursorColor: _draftMaterialColor,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[#0-9a-fA-F]'),
                                ),
                                LengthLimitingTextInputFormatter(7),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Hex',
                                hintText: '#FFAA33',
                                errorText: _hexError,
                                prefixIcon: Icon(
                                  Icons.tag_rounded,
                                  color: readerTheme.muted,
                                ),
                                isDense: true,
                                labelStyle: TextStyle(color: readerTheme.muted),
                                hintStyle: TextStyle(
                                  color: readerTheme.muted.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                                counterStyle: TextStyle(
                                  color: readerTheme.muted,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: readerTheme.divider,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: readerTheme.divider,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isMutating
                                        ? null
                                        : _resetPalette,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(50),
                                      foregroundColor: readerTheme.text,
                                      side: BorderSide(
                                        color: readerTheme.divider,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text('Reset Palette'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _isMutating || _hexError != null
                                        ? null
                                        : _useDraftColor,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(50),
                                      backgroundColor: readerTheme.accent,
                                      foregroundColor: _foregroundFor(
                                        readerTheme.accent,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text('Use Color'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final Color selectionColor;
  final Color checkColor;
  final VoidCallback onTap;

  const _PaletteSwatch({
    super.key,
    required this.color,
    required this.isSelected,
    required this.selectionColor,
    required this.checkColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? selectionColor
                : Colors.white.withValues(alpha: 0.82),
            width: isSelected ? 3 : 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.24),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: isSelected ? Icon(Icons.check_rounded, color: checkColor) : null,
      ),
    );
  }
}

class _AddSwatchButton extends StatelessWidget {
  final bool enabled;
  final _ReaderPaletteTheme theme;
  final VoidCallback onTap;

  const _AddSwatchButton({
    required this.enabled,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.45,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: theme.subtleSurface,
            shape: BoxShape.circle,
            border: Border.all(color: theme.divider, width: 1.4),
          ),
          child: Icon(Icons.add_rounded, color: theme.muted),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final double size;
  final Color? borderColor;

  const _ColorDot({required this.color, required this.size, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: (borderColor ?? Colors.white).withValues(alpha: 0.82),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
    );
  }
}

class _SliderSection extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final Color activeColor;
  final _ReaderPaletteTheme theme;
  final ValueChanged<double> onChanged;

  const _SliderSection({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.activeColor,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: this.theme.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              valueLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: this.theme.muted,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: activeColor,
            thumbColor: activeColor,
            overlayColor: activeColor.withValues(alpha: 0.14),
          ),
          child: Slider(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _ColorWheelPicker extends StatelessWidget {
  final HSVColor color;
  final ValueChanged<HSVColor> onChanged;

  const _ColorWheelPicker({required this.color, required this.onChanged});

  void _updateColor(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final vector = localPosition - center;
    final radius = math.min(size.width, size.height) / 2;
    final distance = vector.distance.clamp(0.0, radius);
    final saturation = (distance / radius).clamp(0.0, 1.0);
    final hue =
        ((math.atan2(vector.dy, vector.dx) * 180 / math.pi) + 360) % 360;

    onChanged(HSVColor.fromAHSV(1, hue, saturation, color.value));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size.square(
          math.min(constraints.maxWidth, constraints.maxHeight),
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => _updateColor(details.localPosition, size),
          onPanUpdate: (details) => _updateColor(details.localPosition, size),
          child: CustomPaint(
            size: size,
            painter: _ColorWheelPainter(color: color),
          ),
        );
      },
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final HSVColor color;

  const _ColorWheelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final wheelPath = Path()..addOval(rect);

    canvas.save();
    canvas.clipPath(wheelPath);

    final sweepPaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, sweepPaint);

    final whiteOverlay = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withValues(alpha: 0.0)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, whiteOverlay);

    if (color.value < 1.0) {
      final darkOverlay = Paint()
        ..color = Colors.black.withValues(alpha: 1.0 - color.value);
      canvas.drawCircle(center, radius, darkOverlay);
    }

    canvas.restore();

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.5);
    canvas.drawCircle(center, radius - 0.6, outlinePaint);

    final selectorAngle = color.hue * math.pi / 180;
    final selectorOffset = Offset(
      center.dx + math.cos(selectorAngle) * color.saturation * radius,
      center.dy + math.sin(selectorAngle) * color.saturation * radius,
    );

    final selectorShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(selectorOffset, 12, selectorShadow);

    final selectorFill = Paint()..color = color.toColor();
    canvas.drawCircle(selectorOffset, 10, selectorFill);

    final selectorBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;
    canvas.drawCircle(selectorOffset, 10, selectorBorder);
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

Color _foregroundFor(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

class _ReaderPaletteTheme {
  final Color surface;
  final Color subtleSurface;
  final Color text;
  final Color muted;
  final Color divider;
  final Color accent;

  const _ReaderPaletteTheme({
    required this.surface,
    required this.subtleSurface,
    required this.text,
    required this.muted,
    required this.divider,
    required this.accent,
  });

  factory _ReaderPaletteTheme.from(
    BuildContext context,
    ReadingSettings? settings,
  ) {
    final theme = Theme.of(context);
    if (settings == null) {
      final scheme = theme.colorScheme;
      return _ReaderPaletteTheme(
        surface: scheme.surface,
        subtleSurface: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        text: scheme.onSurface,
        muted: scheme.onSurfaceVariant,
        divider: theme.dividerColor,
        accent: scheme.primary,
      );
    }

    return _ReaderPaletteTheme(
      surface: settings.menuColor,
      subtleSurface: settings.backgroundColor.withValues(
        alpha: settings.isDark ? 0.42 : 0.7,
      ),
      text: settings.textColor,
      muted: settings.mutedColor,
      divider: settings.textColor.withValues(
        alpha: settings.isDark ? 0.2 : 0.14,
      ),
      accent: settings.accentColor,
    );
  }
}
