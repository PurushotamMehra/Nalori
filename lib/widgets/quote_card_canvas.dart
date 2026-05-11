import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/book_share_payload.dart';
import '../models/quote_card_style.dart';
import '../models/quote_card_theme.dart';
import '../models/quote_share_payload.dart';
import '../models/reading_settings.dart';
import '../ui/app_visuals.dart';

const int _storyCacheWidth = 1080;
const int _bookCoverCacheWidth = 640;

Widget _coverImage(
  String coverImagePath, {
  Key? key,
  int cacheWidth = _storyCacheWidth,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  return Image.file(
    File(coverImagePath),
    key: key,
    fit: BoxFit.cover,
    cacheWidth: cacheWidth,
    errorBuilder: errorBuilder,
  );
}

class QuoteCardCanvas extends StatelessWidget {
  final QuoteSharePayload payload;
  final QuoteCardTheme theme;
  final TextAlign textAlign;
  final QuoteCardStyle cardStyle;

  const QuoteCardCanvas({
    super.key,
    required this.payload,
    required this.theme,
    this.textAlign = TextAlign.left,
    this.cardStyle = QuoteCardStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    switch (cardStyle) {
      case QuoteCardStyle.polaroid:
        return _buildPolaroidStyle(context);
      case QuoteCardStyle.brokenFrame:
        return _buildBrokenFrameStyle(context);
      case QuoteCardStyle.editorialGlass:
        return _buildEditorialGlassStyle(context);
      case QuoteCardStyle.socialStory:
        return _buildSocialStoryStyle(context);
      case QuoteCardStyle.classic:
        return _buildClassicStyle(context);
    }
  }

  Widget _buildClassicStyle(BuildContext context) {
    final crossAxisAlignment = textAlign == TextAlign.left
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: DecoratedBox(
          decoration: theme.isSolidColor
              ? BoxDecoration(color: theme.backgroundColors.first)
              : BoxDecoration(gradient: theme.gradient),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 42, 36, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Expanded(
                      flex: 12,
                      child: Align(
                        alignment: textAlign == TextAlign.left
                            ? Alignment.centerLeft
                            : Alignment.center,
                        child: _QuoteText(
                          quote: payload.quote,
                          color: theme.quoteColor,
                          fontFamily: payload.fontFamily,
                          textAlign: textAlign,
                          cardStyle: cardStyle,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _BookFooter(
                      payload: payload,
                      theme: theme,
                      crossAxisAlignment: crossAxisAlignment,
                      cardStyle: cardStyle,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 34,
                right: 34,
                child: _NaloriWatermark(
                  fontFamily: payload.fontFamily,
                  theme: theme,
                  cardStyle: cardStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPolaroidStyle(BuildContext context) {
    final crossAxisAlignment = textAlign == TextAlign.left
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;

    final isAmoled = theme.name == 'AMOLED';
    final canvasColor = isAmoled
        ? Colors.black
        : const Color(0xFFF9F6F0); // Warm polaroid white or AMOLED black
    final shadowColor = isAmoled
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.15);

    // We override the theme for footer so it works on canvas
    final footerTheme = QuoteCardTheme(
      name: 'Polaroid Override',
      backgroundColors: [canvasColor],
      quoteColor: isAmoled ? Colors.white70 : Colors.black87,
      metadataColor: isAmoled ? Colors.white70 : Colors.black87,
      accentColor: isAmoled ? Colors.white38 : Colors.black26,
      logoColor: isAmoled ? Colors.white : Colors.black,
    );

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: DecoratedBox(
          decoration: BoxDecoration(color: canvasColor),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: theme.isSolidColor ? null : theme.gradient,
                      color: theme.isSolidColor
                          ? theme.backgroundColors.first
                          : null,
                      borderRadius: BorderRadius.circular(
                        4,
                      ), // Very slight curve
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor,
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Align(
                        alignment: textAlign == TextAlign.left
                            ? Alignment.centerLeft
                            : Alignment.center,
                        child: _QuoteText(
                          quote: payload.quote,
                          color: theme.quoteColor,
                          fontFamily: payload.fontFamily,
                          textAlign: textAlign,
                          cardStyle: cardStyle,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _BookFooter(
                        payload: payload,
                        theme: footerTheme,
                        crossAxisAlignment: crossAxisAlignment,
                        cardStyle: cardStyle,
                      ),
                    ),
                    _NaloriWatermark(
                      fontFamily: payload.fontFamily,
                      theme: footerTheme,
                      cardStyle: cardStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrokenFrameStyle(BuildContext context) {
    final crossAxisAlignment = textAlign == TextAlign.left
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;

    final borderColor = theme.quoteColor.withValues(alpha: 0.25);

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: DecoratedBox(
          decoration: theme.isSolidColor
              ? BoxDecoration(color: theme.backgroundColors.first)
              : BoxDecoration(gradient: theme.gradient),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CustomPaint(
                    painter: _BrokenFramePainter(
                      color: borderColor,
                      cornerRadius: 48,
                      topGapWidth: 100, // Space for watermark
                      bottomGapWidth: 340, // Space for footer
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 86, 52, 156),
                child: Align(
                  alignment: textAlign == TextAlign.left
                      ? Alignment.centerLeft
                      : Alignment.center,
                  child: _QuoteText(
                    quote: payload.quote,
                    color: theme.quoteColor,
                    fontFamily: payload.fontFamily,
                    textAlign: textAlign,
                    cardStyle: cardStyle,
                  ),
                ),
              ),
              Positioned(
                bottom: 34,
                left: 24,
                right: 68,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _BookFooter(
                      payload: payload,
                      theme: theme,
                      crossAxisAlignment: crossAxisAlignment,
                      cardStyle: cardStyle,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 88,
                child: _NaloriWatermark(
                  fontFamily: payload.fontFamily,
                  theme: theme,
                  cardStyle: cardStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorialGlassStyle(BuildContext context) {
    final crossAxisAlignment = textAlign == TextAlign.left
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;

    final coverImagePath = payload.coverImagePath?.trim();
    final hasCover = coverImagePath != null && coverImagePath.isNotEmpty;
    final isDarkTheme = theme.quoteColor.computeLuminance() > 0.5;

    final overlayColor = isDarkTheme
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.3);

    final glassBorderColor = isDarkTheme
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.1);

    final glassFillColor = isDarkTheme
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.white.withValues(alpha: 0.4);

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Layer
            if (hasCover)
              _coverImage(coverImagePath)
            else
              DecoratedBox(
                decoration: theme.isSolidColor
                    ? BoxDecoration(color: theme.backgroundColors.first)
                    : BoxDecoration(gradient: theme.gradient),
              ),

            // Blur and dark overlay
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: DecoratedBox(
                decoration: BoxDecoration(color: overlayColor),
              ),
            ),

            // Glass Card
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: glassFillColor,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: glassBorderColor),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: textAlign == TextAlign.left
                                      ? Alignment.centerLeft
                                      : Alignment.center,
                                  child: _QuoteText(
                                    quote: payload.quote,
                                    color: theme.quoteColor,
                                    fontFamily: payload.fontFamily,
                                    textAlign: textAlign,
                                    cardStyle: cardStyle,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              _BookFooter(
                                payload: payload,
                                theme: theme,
                                crossAxisAlignment: crossAxisAlignment,
                                cardStyle: cardStyle,
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 24,
                          top: 24,
                          child: _NaloriWatermark(
                            fontFamily: payload.fontFamily,
                            theme: theme,
                            cardStyle: cardStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialStoryStyle(BuildContext context) {
    final crossAxisAlignment = textAlign == TextAlign.left
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;

    final isDarkTheme = theme.quoteColor.computeLuminance() > 0.5;
    final overlayColor = isDarkTheme
        ? Colors.black.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.45);

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Faded Background
            DecoratedBox(
              decoration: theme.isSolidColor
                  ? BoxDecoration(color: theme.backgroundColors.first)
                  : BoxDecoration(gradient: theme.gradient),
            ),
            DecoratedBox(decoration: BoxDecoration(color: overlayColor)),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: const SizedBox.expand(),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 48),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 32,
                                offset: const Offset(0, 16),
                              ),
                            ],
                            gradient: theme.isSolidColor
                                ? null
                                : theme.gradient,
                            color: theme.isSolidColor
                                ? theme.backgroundColors.first
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 48,
                            ),
                            child: Align(
                              alignment: textAlign == TextAlign.left
                                  ? Alignment.centerLeft
                                  : Alignment.center,
                              child: _QuoteText(
                                quote: payload.quote,
                                color: theme.quoteColor,
                                fontFamily: payload.fontFamily,
                                textAlign: textAlign,
                                cardStyle: cardStyle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Footer and Branding underneath
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _BookFooter(
                            payload: payload,
                            theme: theme,
                            crossAxisAlignment: crossAxisAlignment,
                            cardStyle: cardStyle,
                          ),
                        ),
                        _NaloriWatermark(
                          fontFamily: payload.fontFamily,
                          theme: theme,
                          cardStyle: cardStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookCardCanvas extends StatelessWidget {
  final BookSharePayload payload;
  final QuoteCardTheme theme;
  final TextAlign textAlign;
  final QuoteCardStyle cardStyle;

  const BookCardCanvas({
    super.key,
    required this.payload,
    required this.theme,
    this.textAlign = TextAlign.left,
    this.cardStyle = QuoteCardStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    switch (cardStyle) {
      case QuoteCardStyle.polaroid:
        return _buildPolaroidStyle(context);
      case QuoteCardStyle.brokenFrame:
        return _buildBrokenFrameStyle(context);
      case QuoteCardStyle.editorialGlass:
        return _buildEditorialGlassStyle(context);
      case QuoteCardStyle.socialStory:
        return _buildSocialStoryStyle(context);
      case QuoteCardStyle.classic:
        return _buildClassicStyle(context);
    }
  }

  Widget _buildClassicStyle(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: DecoratedBox(
          decoration: theme.isSolidColor
              ? BoxDecoration(color: theme.backgroundColors.first)
              : BoxDecoration(gradient: theme.gradient),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(36, 54, 36, 46),
            child: _BookCardBody(
              payload: payload,
              theme: theme,
              textAlign: textAlign,
              cardStyle: cardStyle,
              coverHeight: 330,
              coverRadius: 8,
              metadataGap: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPolaroidStyle(BuildContext context) {
    final isAmoled = theme.name == 'AMOLED';
    final canvasColor = isAmoled ? Colors.black : const Color(0xFFF9F6F0);
    final shadowColor = isAmoled
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.16);
    final innerCanvasColor = isAmoled
        ? const Color(0xFF111111)
        : Colors.white.withValues(alpha: 0.72);

    final footerTheme = QuoteCardTheme(
      name: 'Polaroid Override',
      backgroundColors: [canvasColor],
      quoteColor: isAmoled ? Colors.white70 : Colors.black87,
      metadataColor: isAmoled ? Colors.white70 : Colors.black87,
      accentColor: isAmoled ? Colors.white38 : Colors.black26,
      logoColor: isAmoled ? Colors.white : Colors.black,
    );

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: DecoratedBox(
          decoration: BoxDecoration(color: canvasColor),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 34),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: innerCanvasColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 28, 26, 26),
                child: _BookCardBody(
                  payload: payload,
                  theme: footerTheme,
                  textAlign: textAlign,
                  cardStyle: cardStyle,
                  coverHeight: 322,
                  coverRadius: 6,
                  metadataGap: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrokenFrameStyle(BuildContext context) {
    final borderColor = theme.quoteColor.withValues(alpha: 0.25);

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: DecoratedBox(
          decoration: theme.isSolidColor
              ? BoxDecoration(color: theme.backgroundColors.first)
              : BoxDecoration(gradient: theme.gradient),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor, width: 2.0),
                      borderRadius: BorderRadius.circular(48),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 66, 44, 58),
                child: _BookCardBody(
                  payload: payload,
                  theme: theme,
                  textAlign: textAlign,
                  cardStyle: cardStyle,
                  coverHeight: 300,
                  coverRadius: 8,
                  metadataGap: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorialGlassStyle(BuildContext context) {
    final coverImagePath = payload.coverImagePath?.trim();
    final hasCover = coverImagePath != null && coverImagePath.isNotEmpty;
    final isDarkTheme = theme.quoteColor.computeLuminance() > 0.5;
    final overlayColor = isDarkTheme
        ? Colors.black.withValues(alpha: 0.36)
        : Colors.white.withValues(alpha: 0.34);
    final glassBorderColor = isDarkTheme
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.1);
    final glassFillColor = isDarkTheme
        ? Colors.white.withValues(alpha: 0.11)
        : Colors.white.withValues(alpha: 0.46);

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover)
              _coverImage(coverImagePath)
            else
              DecoratedBox(
                decoration: theme.isSolidColor
                    ? BoxDecoration(color: theme.backgroundColors.first)
                    : BoxDecoration(gradient: theme.gradient),
              ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: DecoratedBox(
                decoration: BoxDecoration(color: overlayColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 44, 22, 34),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: glassFillColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: glassBorderColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                      child: _BookCardBody(
                        payload: payload,
                        theme: theme,
                        textAlign: textAlign,
                        cardStyle: cardStyle,
                        coverHeight: 316,
                        coverRadius: 8,
                        metadataGap: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialStoryStyle(BuildContext context) {
    final coverImagePath = payload.coverImagePath?.trim();
    final hasCover = coverImagePath != null && coverImagePath.isNotEmpty;
    final isDarkTheme = theme.quoteColor.computeLuminance() > 0.5;
    final overlayColor = isDarkTheme
        ? Colors.black.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.48);

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasCover)
              _coverImage(coverImagePath)
            else
              DecoratedBox(
                decoration: theme.isSolidColor
                    ? BoxDecoration(color: theme.backgroundColors.first)
                    : BoxDecoration(gradient: theme.gradient),
              ),
            DecoratedBox(decoration: BoxDecoration(color: overlayColor)),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
              child: const SizedBox.expand(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 62, 30, 48),
              child: _BookCardBody(
                payload: payload,
                theme: theme,
                textAlign: textAlign,
                cardStyle: cardStyle,
                coverHeight: 336,
                coverRadius: 8,
                metadataGap: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReadingRecapCardCanvas extends StatelessWidget {
  final ReadingRecapPayload payload;
  final QuoteCardTheme theme;
  final TextAlign textAlign;
  final QuoteCardStyle cardStyle;

  const ReadingRecapCardCanvas({
    super.key,
    required this.payload,
    required this.theme,
    this.textAlign = TextAlign.left,
    this.cardStyle = QuoteCardStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 620;
            final horizontalPadding = compact ? 28.0 : 36.0;

            return DecoratedBox(
              decoration: theme.isSolidColor
                  ? BoxDecoration(color: theme.backgroundColors.first)
                  : BoxDecoration(gradient: theme.gradient),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  compact ? 42 : 52,
                  horizontalPadding,
                  compact ? 34 : 44,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Reading Recap',
                      style: GoogleFonts.inter(
                        color: theme.metadataColor.withValues(alpha: 0.78),
                        fontSize: compact ? 16 : 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: compact ? 18 : 24),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width:
                                constraints.maxWidth - (horizontalPadding * 2),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _RecapMetric(
                                  label: 'Reading time',
                                  value: payload.totalReadingTime,
                                  theme: theme,
                                  compact: compact,
                                ),
                                SizedBox(height: compact ? 12 : 16),
                                _RecapMetric(
                                  label: 'Average pace',
                                  value: payload.averageWpm,
                                  theme: theme,
                                  compact: compact,
                                ),
                                if (payload.fastestChapter != null) ...[
                                  SizedBox(height: compact ? 12 : 16),
                                  _RecapMetric(
                                    label: 'Fastest chapter',
                                    value: payload.fastestChapter!,
                                    theme: theme,
                                    compact: true,
                                  ),
                                ],
                                if (payload.longestChapter != null) ...[
                                  SizedBox(height: compact ? 12 : 16),
                                  _RecapMetric(
                                    label: 'Longest chapter',
                                    value: payload.longestChapter!,
                                    theme: theme,
                                    compact: true,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 14 : 20),
                    Text(
                      payload.bookTitle,
                      textAlign: textAlign,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: theme.quoteColor,
                        fontSize: compact ? 25 : 30,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    if (payload.author.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        payload.author,
                        textAlign: textAlign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: theme.metadataColor.withValues(alpha: 0.82),
                          fontSize: compact ? 13 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    SizedBox(height: compact ? 16 : 20),
                    BrandMark(size: compact ? 18 : 22, color: theme.logoColor),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecapMetric extends StatelessWidget {
  final String label;
  final String value;
  final QuoteCardTheme theme;
  final bool compact;

  const _RecapMetric({
    required this.label,
    required this.value,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 11 : 14,
      ),
      decoration: BoxDecoration(
        color: theme.quoteColor.withValues(alpha: 0.08),
        border: Border.all(color: theme.quoteColor.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: theme.metadataColor.withValues(alpha: 0.72),
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: compact ? 5 : 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: theme.quoteColor,
              fontSize: compact ? 17 : 28,
              height: 1.08,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookCardBody extends StatelessWidget {
  final BookSharePayload payload;
  final QuoteCardTheme theme;
  final TextAlign textAlign;
  final QuoteCardStyle cardStyle;
  final double coverHeight;
  final double coverRadius;
  final double metadataGap;

  const _BookCardBody({
    required this.payload,
    required this.theme,
    required this.textAlign,
    required this.cardStyle,
    required this.coverHeight,
    required this.coverRadius,
    required this.metadataGap,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = textAlign == TextAlign.left
        ? Alignment.centerLeft
        : Alignment.center;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _BookHeroCover(
                payload: payload,
                theme: theme,
                height: coverHeight,
                borderRadius: coverRadius,
                cardStyle: cardStyle,
              ),
            ),
          ),
        ),
        SizedBox(height: metadataGap),
        Align(
          alignment: alignment,
          child: _BookCardMetadata(
            payload: payload,
            theme: theme,
            textAlign: textAlign,
            cardStyle: cardStyle,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: alignment,
          child: _NaloriWatermark(
            fontFamily: payload.fontFamily,
            theme: theme,
            cardStyle: cardStyle,
          ),
        ),
      ],
    );
  }
}

class _BookHeroCover extends StatelessWidget {
  final BookSharePayload payload;
  final QuoteCardTheme theme;
  final double height;
  final double borderRadius;
  final QuoteCardStyle cardStyle;

  const _BookHeroCover({
    required this.payload,
    required this.theme,
    required this.height,
    required this.borderRadius,
    required this.cardStyle,
  });

  @override
  Widget build(BuildContext context) {
    final coverImagePath = payload.coverImagePath?.trim();
    final hasCover = coverImagePath != null && coverImagePath.isNotEmpty;
    final width = height * (2 / 3);
    final isGlass = cardStyle == QuoteCardStyle.editorialGlass;

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.logoColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: isGlass
                ? Colors.white.withValues(alpha: 0.22)
                : theme.quoteColor.withValues(alpha: 0.14),
            width: isGlass ? 1.0 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 26,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: hasCover
              ? Image.file(
                  File(coverImagePath),
                  key: const ValueKey('book-card-book-cover'),
                  fit: BoxFit.cover,
                  cacheWidth: _bookCoverCacheWidth,
                  errorBuilder: (context, error, stackTrace) {
                    return _GeneratedBookCover(payload: payload, theme: theme);
                  },
                )
              : _GeneratedBookCover(
                  key: const ValueKey('book-card-generated-cover'),
                  payload: payload,
                  theme: theme,
                ),
        ),
      ),
    );
  }
}

class _GeneratedBookCover extends StatelessWidget {
  final BookSharePayload payload;
  final QuoteCardTheme theme;

  const _GeneratedBookCover({
    super.key,
    required this.payload,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final hash = payload.bookTitle.hashCode;
    final hue1 = (hash % 360).abs().toDouble();
    final hue2 = ((hash ~/ 360) % 360).abs().toDouble();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1.0, hue1, 0.38, 0.34).toColor(),
            HSLColor.fromAHSL(1.0, hue2, 0.48, 0.22).toColor(),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final titleStyle = _fitTextStyleToWidth(
              text: payload.bookTitle,
              style: _readerFont(
                payload.fontFamily,
                const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.08,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              maxWidth: constraints.maxWidth,
              maxLines: 5,
              minFontSize: 14,
              step: 0.5,
            );
            final authorStyle = _fitTextStyleToWidth(
              text: payload.author,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
              maxWidth: constraints.maxWidth,
              maxLines: 2,
              minFontSize: 10,
              step: 0.5,
            );

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 2,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 18),
                Text(
                  payload.bookTitle,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: titleStyle,
                ),
                if (payload.author.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    payload.author,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: authorStyle,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BookCardMetadata extends StatelessWidget {
  final BookSharePayload payload;
  final QuoteCardTheme theme;
  final TextAlign textAlign;
  final QuoteCardStyle cardStyle;

  const _BookCardMetadata({
    required this.payload,
    required this.theme,
    required this.textAlign,
    required this.cardStyle,
  });

  @override
  Widget build(BuildContext context) {
    final isPremium =
        cardStyle == QuoteCardStyle.polaroid ||
        cardStyle == QuoteCardStyle.brokenFrame ||
        cardStyle == QuoteCardStyle.editorialGlass ||
        cardStyle == QuoteCardStyle.socialStory;

    return SizedBox(
      width: 430,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisAlignment = textAlign == TextAlign.left
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center;
          final titleMaxLines = cardStyle == QuoteCardStyle.brokenFrame ? 3 : 2;
          final baseTitleStyle = _readerFont(
            payload.fontFamily,
            TextStyle(
              color: theme.quoteColor,
              fontSize: isPremium ? 25 : 28,
              height: 1.08,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          );
          final baseAuthorStyle = GoogleFonts.inter(
            color: theme.quoteColor,
            fontSize: isPremium ? 15 : 16,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          );
          final titleStyle = _fitTextStyleToWidth(
            text: payload.bookTitle,
            style: baseTitleStyle,
            maxWidth: constraints.maxWidth,
            maxLines: titleMaxLines,
            minFontSize: isPremium ? 15 : 17,
            step: 0.5,
          );
          final authorStyle = _fitTextStyleToWidth(
            text: payload.author,
            style: baseAuthorStyle,
            maxWidth: constraints.maxWidth,
            maxLines: 1,
            minFontSize: 11,
            step: 0.5,
          );

          return Column(
            crossAxisAlignment: crossAxisAlignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                payload.bookTitle,
                textAlign: textAlign,
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: titleStyle,
              ),
              if (payload.author.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  payload.author,
                  textAlign: textAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: authorStyle,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _QuoteText extends StatelessWidget {
  final String quote;
  final Color color;
  final ReaderFontFamily fontFamily;
  final TextAlign textAlign;
  final QuoteCardStyle cardStyle;

  const _QuoteText({
    required this.quote,
    required this.color,
    required this.fontFamily,
    this.textAlign = TextAlign.left,
    this.cardStyle = QuoteCardStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    final isPremium =
        cardStyle == QuoteCardStyle.polaroid ||
        cardStyle == QuoteCardStyle.brokenFrame ||
        cardStyle == QuoteCardStyle.editorialGlass ||
        cardStyle == QuoteCardStyle.socialStory;
    final quotePadding = _quotePaddingFor(cardStyle);
    final maxLines = _maxLinesFor(cardStyle);
    final minFontSize = _minFontSizeFor(cardStyle);
    final lineHeight = switch (cardStyle) {
      QuoteCardStyle.brokenFrame => 1.06,
      QuoteCardStyle.editorialGlass => 1.08,
      QuoteCardStyle.socialStory => 1.06,
      QuoteCardStyle.polaroid => 1.12,
      QuoteCardStyle.classic => 1.12,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 480.0;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 640.0;
        final availableWidth = (maxWidth - quotePadding.horizontal).clamp(
          120.0,
          maxWidth,
        );
        final availableHeight = (maxHeight - quotePadding.vertical).clamp(
          120.0,
          maxHeight,
        );
        final quoteStyle = _fitTextStyleToBox(
          text: quote,
          style: _readerFont(
            fontFamily,
            TextStyle(
              color: color,
              fontSize: 84,
              height: lineHeight,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          maxWidth: availableWidth,
          maxHeight: availableHeight,
          maxLines: maxLines,
          minFontSize: minFontSize,
        );
        final quoteMarkSize =
            (quoteStyle.fontSize ?? 36) * (isPremium ? 2.5 : 2.9);

        return Padding(
          padding: quotePadding,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -(quoteMarkSize * 0.42),
                left: textAlign == TextAlign.left ? -(quoteMarkSize * 0.14) : 0,
                child: IgnorePointer(
                  child: Text(
                    '“',
                    key: const ValueKey('quote-card-decorative-quote-mark'),
                    textScaler: TextScaler.noScaling,
                    style: _readerFont(
                      fontFamily,
                      TextStyle(
                        color: color.withValues(alpha: isPremium ? 0.08 : 0.18),
                        fontSize: quoteMarkSize,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: availableWidth,
                height: availableHeight,
                child: Align(
                  alignment: textAlign == TextAlign.left
                      ? Alignment.centerLeft
                      : Alignment.center,
                  child: Text(
                    quote,
                    textAlign: textAlign,
                    textScaler: TextScaler.noScaling,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: quoteStyle,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  EdgeInsets _quotePaddingFor(QuoteCardStyle cardStyle) {
    return switch (cardStyle) {
      QuoteCardStyle.classic => const EdgeInsets.fromLTRB(16, 28, 12, 18),
      QuoteCardStyle.polaroid => const EdgeInsets.fromLTRB(12, 20, 12, 14),
      QuoteCardStyle.brokenFrame => const EdgeInsets.all(20),
      QuoteCardStyle.editorialGlass => const EdgeInsets.fromLTRB(
        16,
        22,
        16,
        18,
      ),
      QuoteCardStyle.socialStory => const EdgeInsets.all(16),
    };
  }

  int _maxLinesFor(QuoteCardStyle cardStyle) {
    return switch (cardStyle) {
      QuoteCardStyle.classic => 20,
      QuoteCardStyle.polaroid => 22,
      QuoteCardStyle.brokenFrame => 24,
      QuoteCardStyle.editorialGlass => 26,
      QuoteCardStyle.socialStory => 26,
    };
  }

  double _minFontSizeFor(QuoteCardStyle cardStyle) {
    return switch (cardStyle) {
      QuoteCardStyle.classic => 18,
      QuoteCardStyle.polaroid => 17,
      QuoteCardStyle.brokenFrame => 14,
      QuoteCardStyle.editorialGlass => 13,
      QuoteCardStyle.socialStory => 12,
    };
  }
}

class _BookFooter extends StatelessWidget {
  final QuoteSharePayload payload;
  final QuoteCardTheme theme;
  final CrossAxisAlignment crossAxisAlignment;
  final QuoteCardStyle cardStyle;

  const _BookFooter({
    required this.payload,
    required this.theme,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.cardStyle = QuoteCardStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    final coverImagePath = payload.coverImagePath?.trim();
    final showCover = coverImagePath != null && coverImagePath.isNotEmpty;
    final isPremium =
        cardStyle == QuoteCardStyle.polaroid ||
        cardStyle == QuoteCardStyle.brokenFrame ||
        cardStyle == QuoteCardStyle.editorialGlass ||
        cardStyle == QuoteCardStyle.socialStory;
    final isBrokenFrame = cardStyle == QuoteCardStyle.brokenFrame;
    final isEditorialGlass = cardStyle == QuoteCardStyle.editorialGlass;

    return LayoutBuilder(
      builder: (context, constraints) {
        final titleMaxLines = isBrokenFrame ? 3 : 2;
        final coverHeight = isPremium ? (isBrokenFrame ? 64.0 : 48.0) : 0.0;
        final coverGap = showCover ? (isBrokenFrame ? 16.0 : 12.0) : 0.0;
        final availableWidth =
            (constraints.maxWidth -
                    (showCover ? (coverHeight * (2 / 3)) + coverGap : 0.0))
                .clamp(120.0, constraints.maxWidth);

        final baseTitleStyle = isPremium
            ? _metadataTitleStyle(payload.fontFamily, theme).copyWith(
                fontSize: isBrokenFrame ? 17 : 13,
                height: isBrokenFrame ? 1.02 : 1.1,
              )
            : _metadataTitleStyle(payload.fontFamily, theme);
        final baseAuthorStyle = isPremium
            ? _metadataAuthorStyle(
                payload.fontFamily,
                theme,
              ).copyWith(fontSize: isBrokenFrame ? 12 : 11)
            : _metadataAuthorStyle(payload.fontFamily, theme);

        final titleStyle = _fitTextStyleToWidth(
          text: payload.bookTitle,
          style: baseTitleStyle,
          maxWidth: availableWidth,
          maxLines: titleMaxLines,
          minFontSize: isBrokenFrame ? 11 : (isPremium ? 10 : 12),
          step: 0.5,
        );
        final authorStyle = _fitTextStyleToWidth(
          text: payload.author,
          style: baseAuthorStyle,
          maxWidth: availableWidth,
          maxLines: 1,
          minFontSize: isBrokenFrame ? 10 : 9,
          step: 0.5,
        );

        if (isPremium) {
          final isDarkTheme = theme.quoteColor.computeLuminance() > 0.5;
          final glassBoxBorderColor = isDarkTheme
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.1);
          final glassBoxFillColor = isDarkTheme
              ? Colors.black.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.05);

          final innerContent = Row(
            mainAxisAlignment: crossAxisAlignment == CrossAxisAlignment.center
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              if (showCover) ...[
                SizedBox(
                  height: coverHeight,
                  width: coverHeight * (2 / 3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isEditorialGlass
                            ? glassBoxBorderColor
                            : theme.quoteColor.withValues(alpha: 0.1),
                        width: isEditorialGlass ? 1.0 : 0.5,
                      ),
                      borderRadius: BorderRadius.circular(
                        isEditorialGlass ? 8 : (isBrokenFrame ? 6 : 4),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        isEditorialGlass ? 8 : (isBrokenFrame ? 6 : 4),
                      ),
                      child: _BookCoverThumbnail(
                        key: const ValueKey('quote-card-book-cover'),
                        coverImagePath: coverImagePath,
                        theme: theme,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: coverGap),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      crossAxisAlignment == CrossAxisAlignment.center
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      payload.bookTitle,
                      maxLines: titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: titleStyle,
                    ),
                    if (payload.author.isNotEmpty) ...[
                      SizedBox(height: isBrokenFrame ? 5 : 4),
                      Text(
                        payload.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: authorStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final premiumContent = isBrokenFrame
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: innerContent,
                )
              : innerContent;

          if (isEditorialGlass) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: glassBoxFillColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: glassBoxBorderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: premiumContent,
              ),
            );
          }

          return premiumContent;
        }

        const authorGap = 6.0;
        final titleHeight = _textHeight(
          payload.bookTitle,
          titleStyle,
          availableWidth,
          maxLines: titleMaxLines,
        );
        final authorHeight = payload.author.isEmpty
            ? 0.0
            : authorGap +
                  _textHeight(payload.author, authorStyle, availableWidth);
        final metadataHeight = titleHeight + authorHeight;
        final classicCoverHeight = metadataHeight.clamp(36.0, 72.0);

        return Column(
          crossAxisAlignment: crossAxisAlignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 48, height: 2, color: theme.accentColor),
            const SizedBox(height: 18),
            Row(
              children: [
                if (showCover) ...[
                  SizedBox(
                    width: classicCoverHeight * (2 / 3),
                    height: classicCoverHeight,
                    child: _BookCoverThumbnail(
                      key: const ValueKey('quote-card-book-cover'),
                      coverImagePath: coverImagePath,
                      theme: theme,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: SizedBox(
                    height: metadataHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          payload.bookTitle,
                          maxLines: titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                          style: titleStyle,
                        ),
                        if (payload.author.isNotEmpty) ...[
                          const SizedBox(height: authorGap),
                          Text(
                            payload.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: TextScaler.noScaling,
                            style: authorStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  TextStyle _metadataTitleStyle(
    ReaderFontFamily fontFamily,
    QuoteCardTheme theme,
  ) {
    return _readerFont(
      fontFamily,
      TextStyle(
        color: theme.quoteColor,
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }

  TextStyle _metadataAuthorStyle(
    ReaderFontFamily fontFamily,
    QuoteCardTheme theme,
  ) {
    return _readerFont(
      fontFamily,
      TextStyle(
        color: theme.quoteColor,
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    );
  }

  double _textHeight(
    String text,
    TextStyle style,
    double maxWidth, {
    int maxLines = 1,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      // Required before layout in widget tests and some Flutter embedders.
      // ignore: avoid_redundant_argument_values
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth);

    return painter.height;
  }
}

class _NaloriWatermark extends StatelessWidget {
  final ReaderFontFamily fontFamily;
  final QuoteCardTheme theme;
  final QuoteCardStyle cardStyle;

  const _NaloriWatermark({
    required this.fontFamily,
    required this.theme,
    this.cardStyle = QuoteCardStyle.classic,
  });

  @override
  Widget build(BuildContext context) {
    final color = _watermarkColorFor(theme);
    final isBrokenFrame = cardStyle == QuoteCardStyle.brokenFrame;
    final isPremium =
        cardStyle == QuoteCardStyle.polaroid ||
        isBrokenFrame ||
        cardStyle == QuoteCardStyle.editorialGlass ||
        cardStyle == QuoteCardStyle.socialStory;
    final logoSize = isBrokenFrame ? 28.0 : (isPremium ? 20.0 : 30.0);
    final textSize = isBrokenFrame ? 14.0 : (isPremium ? 10.0 : 12.0);
    final gap = isBrokenFrame ? 6.0 : (isPremium ? 3.0 : 5.0);
    final opacity = isBrokenFrame ? 0.62 : (isPremium ? 0.5 : 0.72);

    final watermarkBase = Opacity(
      opacity: opacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(isPremium ? 4 : 6),
            child: BrandMark(
              key: const ValueKey('quote-card-nalori-icon'),
              size: logoSize,
              color: color,
            ),
          ),
          SizedBox(width: gap),
          Text(
            AppBrand.name,
            textScaler: TextScaler.noScaling,
            style: _readerFont(
              fontFamily,
              TextStyle(
                color: color,
                fontSize: textSize,
                height: 1,
                fontWeight: isPremium ? FontWeight.w500 : FontWeight.w300,
                letterSpacing: isBrokenFrame ? 0.2 : (isPremium ? 0.4 : 0),
              ),
            ),
          ),
        ],
      ),
    );

    return watermarkBase;
  }
}

Color _watermarkColorFor(QuoteCardTheme theme) {
  if (theme.backgroundColors.isEmpty) return theme.quoteColor;

  final averageLuminance =
      theme.backgroundColors.fold<double>(
        0,
        (total, color) => total + color.computeLuminance(),
      ) /
      theme.backgroundColors.length;

  return averageLuminance > 0.46 ? const Color(0xFF111111) : Colors.white;
}

class _BookCoverThumbnail extends StatelessWidget {
  final String coverImagePath;
  final QuoteCardTheme theme;

  const _BookCoverThumbnail({
    super.key,
    required this.coverImagePath,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.logoColor.withValues(alpha: 0.1)),
      child: Image.file(
        File(coverImagePath),
        fit: BoxFit.cover,
        cacheWidth: 240,
        errorBuilder: (context, error, stackTrace) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.accentColor.withValues(alpha: 0.55),
                  theme.logoColor.withValues(alpha: 0.14),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

TextStyle _readerFont(ReaderFontFamily fontFamily, TextStyle baseStyle) {
  switch (fontFamily) {
    case ReaderFontFamily.inter:
      return GoogleFonts.inter(textStyle: baseStyle);
    case ReaderFontFamily.robotoMono:
      return GoogleFonts.robotoMono(textStyle: baseStyle);
    case ReaderFontFamily.merriweather:
      return GoogleFonts.merriweather(textStyle: baseStyle);
    case ReaderFontFamily.lora:
      return GoogleFonts.lora(textStyle: baseStyle);
    case ReaderFontFamily.ebGaramond:
      return GoogleFonts.ebGaramond(textStyle: baseStyle);
    case ReaderFontFamily.literata:
      return GoogleFonts.literata(textStyle: baseStyle);
    case ReaderFontFamily.atkinsonHyperlegible:
      return GoogleFonts.atkinsonHyperlegible(textStyle: baseStyle);
    case ReaderFontFamily.lexend:
      return GoogleFonts.lexend(textStyle: baseStyle);
  }
}

TextStyle _fitTextStyleToWidth({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required int maxLines,
  required double minFontSize,
  double step = 1,
}) {
  if (text.trim().isEmpty) return style;

  final startingFontSize = style.fontSize ?? minFontSize;
  for (
    double fontSize = startingFontSize;
    fontSize >= minFontSize;
    fontSize -= step
  ) {
    final candidate = style.copyWith(fontSize: fontSize);
    final painter = TextPainter(
      text: TextSpan(text: text, style: candidate),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth);

    if (!painter.didExceedMaxLines) {
      return candidate;
    }
  }

  return style.copyWith(fontSize: minFontSize);
}

TextStyle _fitTextStyleToBox({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required double maxHeight,
  required int maxLines,
  required double minFontSize,
  double step = 1,
}) {
  if (text.trim().isEmpty) return style;

  final startingFontSize = style.fontSize ?? minFontSize;
  for (
    double fontSize = startingFontSize;
    fontSize >= minFontSize;
    fontSize -= step
  ) {
    final candidate = style.copyWith(fontSize: fontSize);
    final painter = TextPainter(
      text: TextSpan(text: text, style: candidate),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: maxWidth);

    if (!painter.didExceedMaxLines && painter.height <= maxHeight) {
      return candidate;
    }
  }

  return style.copyWith(fontSize: minFontSize);
}

class _BrokenFramePainter extends CustomPainter {
  final Color color;
  final double strokeWidth = 2.0;
  final double cornerRadius;
  final double topGapWidth;
  final double bottomGapWidth;

  _BrokenFramePainter({
    required this.color,
    this.cornerRadius = 24.0,
    required this.topGapWidth,
    required this.bottomGapWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();

    // The gap for the top logo is immediately to the left of the top-right corner.
    final logoGapStart = size.width - topGapWidth - cornerRadius;

    // 1. Top edge (starts left of the logo gap)
    path.moveTo(logoGapStart, 0);
    path.lineTo(cornerRadius, 0);

    // 2. Top-left corner
    path.arcToPoint(
      Offset(0, cornerRadius),
      radius: Radius.circular(cornerRadius),
      clockwise: false,
    );

    // 3. Left edge down to near the footer
    final leftLineEndY =
        size.height - 110; // Clean halt, safely above book details
    path.lineTo(0, leftLineEndY);

    // 4. Right part of the frame: Top-right corner -> Right edge -> Bottom-right corner
    // We removed the extra horizontal bottom line completely for a cleaner look.
    path.moveTo(size.width - cornerRadius, 0);
    path.arcToPoint(
      Offset(size.width, cornerRadius),
      radius: Radius.circular(cornerRadius),
    );
    path.lineTo(size.width, size.height - cornerRadius);
    path.arcToPoint(
      Offset(size.width - cornerRadius, size.height),
      radius: Radius.circular(cornerRadius),
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BrokenFramePainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        cornerRadius != oldDelegate.cornerRadius ||
        topGapWidth != oldDelegate.topGapWidth ||
        bottomGapWidth != oldDelegate.bottomGapWidth;
  }
}
