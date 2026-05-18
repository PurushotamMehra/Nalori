import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/reading_settings.dart';
import 'package:nalori/screens/reader_screen.dart';
import 'package:nalori/utils/final_layout_paragraphs.dart';

void main() {
  const screenSize = Size(412, 915);
  const safeArea = EdgeInsets.only(top: 44, bottom: 34);

  group('resolveReaderLayoutMetrics', () {
    test(
      'full-page density expands the readable area toward the screen edges',
      () {
        const medium = ReadingSettings();
        const fullPage = ReadingSettings(
          contentDensity: ContentDensity.fullPage,
        );

        final mediumMetrics = resolveReaderLayoutMetrics(
          screenSize,
          safeArea,
          medium,
        );
        final fullPageMetrics = resolveReaderLayoutMetrics(
          screenSize,
          safeArea,
          fullPage,
        );

        expect(
          fullPageMetrics.contentPadding.top,
          lessThan(mediumMetrics.contentPadding.top),
        );
        expect(
          fullPageMetrics.contentPadding.bottom,
          lessThan(mediumMetrics.contentPadding.bottom),
        );
        expect(
          fullPageMetrics.availableHeight,
          greaterThan(mediumMetrics.availableHeight),
        );
      },
    );

    test('keeps a safety buffer even for full-page Card Mode layouts', () {
      const settings = ReadingSettings(
        contentDensity: ContentDensity.fullPage,
        enableCardDepth: true,
        fontSize: ReaderFontSize.xl,
        lineHeight: 2.2,
      );

      final metrics = resolveReaderLayoutMetrics(
        screenSize,
        safeArea,
        settings,
      );

      expect(metrics.cardMargin.top, 22);
      expect(metrics.cardMargin.bottom, 34);
      expect(metrics.safetyBuffer, greaterThanOrEqualTo(14));
      expect(metrics.maxTextHeight, lessThan(metrics.availableHeight));
      expect(metrics.targetTextHeight, metrics.preferredMaxTextHeight);
      expect(metrics.preferredMaxTextHeight, metrics.maxTextHeight);
    });

    test(
      'Card Mode metadata and footer reserves reduce usable text height',
      () {
        const flat = ReadingSettings(
          contentDensity: ContentDensity.fullPage,
          enableCardDepth: false,
        );
        const depth = ReadingSettings(
          contentDensity: ContentDensity.fullPage,
          enableCardDepth: true,
        );

        final flatMetrics = resolveReaderLayoutMetrics(
          screenSize,
          safeArea,
          flat,
        );
        final depthMetrics = resolveReaderLayoutMetrics(
          screenSize,
          safeArea,
          depth,
        );

        expect(
          depthMetrics.contentPadding.top,
          flatMetrics.contentPadding.top + kReaderCardDepthHeaderReserve,
        );
        expect(
          depthMetrics.contentPadding.bottom,
          flatMetrics.contentPadding.bottom + kReaderCardDepthFooterReserve,
        );
        expect(
          depthMetrics.availableHeight,
          flatMetrics.availableHeight -
              depthMetrics.cardMargin.vertical -
              kReaderCardDepthHeaderReserve -
              kReaderCardDepthFooterReserve,
        );
        expect(
          depthMetrics.maxTextHeight,
          lessThan(depthMetrics.availableHeight),
        );
      },
    );

    test('horizontal safe area reduces readable width in landscape', () {
      const landscape = Size(915, 412);
      const landscapeInsets = EdgeInsets.only(left: 44, right: 34);

      final metrics = resolveReaderLayoutMetrics(
        landscape,
        landscapeInsets,
        const ReadingSettings(enableCardDepth: false),
      );

      expect(metrics.contentPadding.left, kContentPaddingH + 44);
      expect(metrics.contentPadding.right, kContentPaddingH + 34);
      expect(
        metrics.availableWidth,
        landscape.width - metrics.contentPadding.horizontal,
      );
    });

    test('supported edge combinations keep positive bounded text budgets', () {
      const screens = <Size>[
        Size(320, 568),
        Size(390, 844),
        Size(412, 915),
        Size(768, 1024),
        Size(1024, 768),
      ];
      const lineHeights = <double>[1.0, 1.4, 2.2];

      for (final size in screens) {
        for (final cardDepth in <bool>[false, true]) {
          for (final density in ContentDensity.values) {
            for (final fontSize in ReaderFontSize.values) {
              for (final lineHeight in lineHeights) {
                final settings = ReadingSettings(
                  enableCardDepth: cardDepth,
                  contentDensity: density,
                  fontSize: fontSize,
                  lineHeight: lineHeight,
                );
                final metrics = resolveReaderLayoutMetrics(
                  size,
                  safeArea,
                  settings,
                );

                expect(metrics.availableWidth, greaterThan(0));
                expect(metrics.availableHeight, greaterThan(0));
                expect(metrics.maxTextHeight, greaterThan(0));
                expect(
                  metrics.maxTextHeight,
                  lessThanOrEqualTo(metrics.availableHeight),
                );
                expect(
                  metrics.targetTextHeight,
                  lessThanOrEqualTo(metrics.maxTextHeight),
                );
              }
            }
          }
        }
      }
    });
  });

  group('readerDensityPolicy', () {
    test('maps density directly to readable height ratios', () {
      expect(readerDensityPolicy(ContentDensity.low).pageHeightRatio, 0.25);
      expect(readerDensityPolicy(ContentDensity.medium).pageHeightRatio, 0.50);
      expect(readerDensityPolicy(ContentDensity.high).pageHeightRatio, 0.75);
      expect(readerDensityPolicy(ContentDensity.fullPage).pageHeightRatio, 1.0);
    });

    test('density budgets scale by roughly 25/50/75/100 percent', () {
      const base = ReadingSettings();
      final budgets = ContentDensity.values.map((density) {
        final metrics = resolveReaderLayoutMetrics(
          screenSize,
          safeArea,
          base.copyWith(contentDensity: density),
        );
        return metrics.maxTextHeight;
      }).toList();

      expect(budgets[1] / budgets[0], closeTo(2.0, 0.01));
      expect(budgets[2] / budgets[0], closeTo(3.0, 0.01));
      expect(budgets[3] / budgets[0], greaterThanOrEqualTo(4.0));
      expect(readerSoftWordCap(ContentDensity.low), lessThan(96));
    });
  });

  group('readerSentenceRanges', () {
    test('keeps abbreviations and closing quotes with the sentence', () {
      const text =
          '“Tut-tut!” said Mr. Utterson. “I trust you are better.” Next.';
      final ranges = readerSentenceRanges(
        text,
      ).map((range) => text.substring(range.start, range.end).trim()).toList();

      expect(ranges, [
        '“Tut-tut!” said Mr. Utterson.',
        '“I trust you are better.”',
        'Next.',
      ]);
      expect(readerTextEndsAtSentenceBoundary(ranges.first), isTrue);
    });
  });

  group('final paragraph layout measurement', () {
    const style = TextStyle(fontSize: 18, height: 1.2);
    const maxWidth = 360.0;

    double measure(String text, double paragraphSpacing) {
      return measureFinalLayoutParagraphTextHeight(
        text: text,
        style: style,
        maxWidth: maxWidth,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.start,
        textScaler: TextScaler.noScaling,
        strutStyle: null,
        fallbackFontSize: 18,
        fallbackLineHeight: 1.2,
        paragraphSpacing: paragraphSpacing,
      );
    }

    test('increasing paragraphSpacing increases multi-paragraph height', () {
      const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';

      expect(measure(text, 2), greaterThan(measure(text, 1)));
      expect(measure(text, 0), lessThan(measure(text, 1)));
    });

    test('paragraphSpacing changes page fit for multi-paragraph text', () {
      const text = 'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.';
      final oneXHeight = measure(text, 1);
      final pageBudget = oneXHeight + 1;

      expect(measure(text, 1), lessThanOrEqualTo(pageBudget));
      expect(measure(text, 2), greaterThan(pageBudget));
      expect(measure(text, 0), lessThan(oneXHeight));
    });

    test(
      'single paragraphs measure the same across paragraphSpacing values',
      () {
        final text = List.filled(
          40,
          'Long wrapped prose remains one measured paragraph.',
        ).join(' ');

        expect(measure(text, 0), measure(text, 1));
        expect(measure(text, 2), measure(text, 1));
      },
    );
  });

  group('readerSettingsRequireDisplayChunkRebuild', () {
    test('returns true when only paragraphSpacing changes', () {
      const old = ReadingSettings(paragraphSpacing: 1);
      const updated = ReadingSettings(paragraphSpacing: 1.5);

      expect(readerSettingsRequireDisplayChunkRebuild(old, updated), isTrue);
    });
  });

  group('dialogue layout', () {
    test('quote decoration does not shrink measured text width', () {
      expect(kReaderDialogueTextInset, 0);
    });
  });
}
