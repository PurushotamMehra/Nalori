import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/speed_read_controller.dart';
import '../models/reading_settings.dart';

class SpeedReadOverlay extends StatefulWidget {
  final SpeedReadController controller;
  final TextPainter textPainter;
  final ReadingSettings settings;
  final Offset textOffset;

  const SpeedReadOverlay({
    super.key,
    required this.controller,
    required this.textPainter,
    required this.settings,
    this.textOffset = Offset.zero,
  });

  @override
  State<SpeedReadOverlay> createState() => _SpeedReadOverlayState();
}

class _SpeedReadOverlayState extends State<SpeedReadOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _opacityController;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _opacityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.controller.isPaused ? 0.3 : 1.0,
    );
    _opacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _opacityController, curve: Curves.easeInOut),
    );

    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(covariant SpeedReadOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _opacityController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (!mounted) return;

    if (widget.controller.isPaused && _opacityController.value > 0.3) {
      _opacityController.reverse();
    } else if (!widget.controller.isPaused && _opacityController.value < 1.0) {
      _opacityController.forward();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isActive || widget.controller.tokens.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeToken = widget.controller.activeToken;
    if (activeToken == null) return const SizedBox.shrink();

    final accentColor = widget.settings.readerAccentColor;

    final boxes = widget.textPainter.getBoxesForSelection(
      TextSelection(
        baseOffset: activeToken.startOffset,
        extentOffset: activeToken.endOffset,
      ),
      boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
    );

    if (boxes.isEmpty) return const SizedBox.shrink();

    final rects = _mergeLineRects(
      boxes.map((box) => box.toRect().shift(widget.textOffset)).toList(),
    );
    final horizontalPad = (widget.settings.fontSizeValue * 0.18)
        .clamp(5.0, 10.0)
        .toDouble();
    final verticalPad = (widget.settings.fontSizeValue * 0.08)
        .clamp(3.0, 7.0)
        .toDouble();

    return Stack(
      children: List.generate(rects.length * 3, (rawIndex) {
        final index = rawIndex ~/ 3;
        final layer = rawIndex % 3;
        final rect = rects[index];
        final paddedRect = Rect.fromLTRB(
          rect.left - horizontalPad,
          rect.top - verticalPad,
          rect.right + horizontalPad,
          rect.bottom + verticalPad,
        );

        if (layer == 0) {
          return AnimatedPositioned(
            key: ValueKey('speed_read_line_$index'),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            top: paddedRect.center.dy - 1,
            height: 2,
            child: AnimatedBuilder(
              animation: _opacityAnimation,
              builder: (context, child) => Opacity(
                opacity: _opacityAnimation.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        accentColor.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        if (layer == 1) {
          final tickHeight = paddedRect.height > 18
              ? paddedRect.height - 6
              : paddedRect.height;
          return AnimatedPositioned(
            key: ValueKey('speed_read_tick_$index'),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            left: paddedRect.left - 7,
            top: paddedRect.top + 3,
            width: 3,
            height: tickHeight,
            child: AnimatedBuilder(
              animation: _opacityAnimation,
              builder: (context, child) => Opacity(
                opacity: _opacityAnimation.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return AnimatedPositioned(
          key: ValueKey('speed_read_lens_$index'),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          left: paddedRect.left,
          top: paddedRect.top,
          width: paddedRect.width,
          height: paddedRect.height,
          child: AnimatedBuilder(
            animation: _opacityAnimation,
            builder: (context, child) {
              final opacity = _opacityAnimation.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16 * opacity),
                  borderRadius: BorderRadius.circular(7.0),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.48 * opacity),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.22 * opacity),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }),
    );
  }

  List<Rect> _mergeLineRects(List<Rect> rects) {
    if (rects.length <= 1) return rects;

    final sorted = [...rects]
      ..sort((a, b) {
        final vertical = a.center.dy.compareTo(b.center.dy);
        return vertical == 0 ? a.left.compareTo(b.left) : vertical;
      });

    final merged = <Rect>[];
    for (final rect in sorted) {
      if (merged.isEmpty) {
        merged.add(rect);
        continue;
      }

      final last = merged.last;
      final sameLine =
          (last.center.dy - rect.center.dy).abs() <
          (last.height + rect.height) * 0.35;
      if (sameLine) {
        merged[merged.length - 1] = last.expandToInclude(rect);
      } else {
        merged.add(rect);
      }
    }
    return merged;
  }
}
