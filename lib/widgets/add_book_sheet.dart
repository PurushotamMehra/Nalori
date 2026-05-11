import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/reading_settings.dart';
import '../ui/app_visuals.dart';

class AddBookSheet extends StatelessWidget {
  final ReadingSettings settings;
  final VoidCallback onImportEpub;
  final VoidCallback onBrowseProjectGutenberg;

  const AddBookSheet({
    super.key,
    required this.settings,
    required this.onImportEpub,
    required this.onBrowseProjectGutenberg,
  });

  void _handleAction(BuildContext context, VoidCallback action) {
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: settings.menuColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: settings.mutedColor.withValues(alpha: 0.14)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AddBookDragHandle(),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.addABook,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: settings.textColor,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      l10n.addBookSheetSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: settings.mutedColor,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AddBookActionCard(
                settings: settings,
                title: l10n.importEpub,
                subtitle: l10n.importEpubSubtitle,
                icon: Icons.file_upload_outlined,
                badge: l10n.recommended,
                primary: true,
                onTap: () => _handleAction(context, onImportEpub),
              ),
              const SizedBox(height: 10),
              AddBookActionCard(
                settings: settings,
                title: l10n.browseProjectGutenberg,
                subtitle: l10n.browseProjectGutenbergSubtitle,
                icon: Icons.public_rounded,
                onTap: () => _handleAction(context, onBrowseProjectGutenberg),
              ),
              const SizedBox(height: 12),
              AddBookSupportNote(settings: settings),
            ],
          ),
        ),
      ),
    );
  }
}

class AddBookActionCard extends StatelessWidget {
  final ReadingSettings settings;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final bool primary;
  final VoidCallback onTap;

  const AddBookActionCard({
    super.key,
    required this.settings,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.badge,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = settings.accentColor;
    final foreground = primary ? settings.textColor : settings.mutedColor;
    final iconBackground = primary
        ? accent.withValues(alpha: 0.18)
        : settings.textColor.withValues(alpha: 0.055);
    final borderColor = primary
        ? accent.withValues(alpha: 0.36)
        : settings.mutedColor.withValues(alpha: 0.12);

    return Semantics(
      button: true,
      label: '$title, $subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppUi.cardRadius(12),
          child: Ink(
            decoration: BoxDecoration(
              color: primary
                  ? Color.alphaBlend(
                      accent.withValues(alpha: settings.isDark ? 0.10 : 0.08),
                      settings.backgroundColor,
                    )
                  : settings.backgroundColor.withValues(
                      alpha: settings.isDark ? 0.72 : 0.54,
                    ),
              borderRadius: AppUi.cardRadius(12),
              border: Border.all(color: borderColor),
              boxShadow: primary
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: primary
                            ? accent.withValues(alpha: 0.20)
                            : settings.mutedColor.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: primary ? accent : foreground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: settings.textColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                              ),
                            ),
                            if (badge != null) ...[
                              const SizedBox(width: 8),
                              _AddBookBadge(
                                label: badge!,
                                backgroundColor: accent.withValues(alpha: 0.16),
                                textColor: accent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: settings.mutedColor,
                                fontSize: 12,
                                height: 1.28,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: primary
                        ? accent
                        : settings.mutedColor.withValues(alpha: 0.72),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AddBookSupportNote extends StatelessWidget {
  final ReadingSettings settings;

  const AddBookSupportNote({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: settings.mutedColor.withValues(alpha: 0.72),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              l10n.addBookSupportNote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: settings.mutedColor.withValues(alpha: 0.74),
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBookBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _AddBookBadge({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _AddBookDragHandle extends StatelessWidget {
  const _AddBookDragHandle();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
