import 'package:flutter/material.dart';

import '../models/reading_settings.dart';
import '../ui/app_visuals.dart';

class HowToUseScreen extends StatelessWidget {
  final ReadingSettings settings;
  final bool firstRun;
  final VoidCallback? onDone;

  const HowToUseScreen({
    super.key,
    required this.settings,
    this.firstRun = false,
    this.onDone,
  });

  static const _sections = [
    (
      icon: Icons.library_add_rounded,
      title: 'Build your library',
      body: 'Import EPUBs from this device or browse free public-domain books.',
    ),
    (
      icon: Icons.swipe_vertical_rounded,
      title: 'Read with gestures',
      body:
          'Swipe up or down to move through pages. Tap once to show reader controls.',
    ),
    (
      icon: Icons.tune_rounded,
      title: 'Use reader tools',
      body:
          'Open chapters, bookmarks, search, annotations, and reading settings from the reader controls.',
    ),
    (
      icon: Icons.text_fields_rounded,
      title: 'Work with text',
      body:
          'Select text for dictionary lookup, highlights, notes, character marks, and quote cards.',
    ),
    (
      icon: Icons.auto_awesome_rounded,
      title: 'Make it yours',
      body:
          'Adjust themes, fonts, density, speed read, volume paging, and reading insights.',
    ),
    (
      icon: Icons.privacy_tip_outlined,
      title: 'Privacy',
      body:
          'Your EPUBs, bookmarks, highlights, notes, saved words, and stats stay on this device. Internet is used for dictionary lookup, public-domain books, and optional book-detail enhancement.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppUi.readerTheme(settings),
      child: Scaffold(
        backgroundColor: settings.backgroundColor,
        appBar: firstRun
            ? null
            : AppBar(
                backgroundColor: settings.backgroundColor,
                foregroundColor: settings.textColor,
                elevation: 0,
                scrolledUnderElevation: 0,
                title: Text(
                  'How to use Nalori',
                  style: settings.uiText(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: settings.textColor,
                  ),
                ),
              ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  children: [
                    _Header(settings: settings),
                    const SizedBox(height: 28),
                    for (final section in _sections) ...[
                      _HelpSection(
                        icon: section.icon,
                        title: section.title,
                        body: section.body,
                        settings: settings,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
              if (firstRun)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: onDone,
                      style: FilledButton.styleFrom(
                        backgroundColor: settings.accentColor,
                        foregroundColor: AppUi.foregroundFor(
                          settings.accentColor,
                        ),
                        shape: AppUi.shape(AppUi.radiusMd),
                      ),
                      child: Text(
                        'Start reading',
                        style: settings.uiText(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ReadingSettings settings;

  const _Header({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: settings.accentColor.withValues(alpha: 0.12),
            borderRadius: AppUi.cardRadius(AppUi.radiusMd),
          ),
          child: const Center(child: BrandMark(size: 32)),
        ),
        const SizedBox(height: 20),
        Text(
          'How to use Nalori',
          style: settings.uiText(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.08,
            color: settings.textColor,
          ),
        ),
      ],
    );
  }
}

class _HelpSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final ReadingSettings settings;

  const _HelpSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppUi.surfaceCard(settings),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: settings.accentColor.withValues(alpha: 0.12),
              borderRadius: AppUi.cardRadius(AppUi.radiusSm),
            ),
            child: Icon(icon, size: 21, color: settings.accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: settings.uiText(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: settings.textColor,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: settings.uiText(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: settings.mutedColor,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
