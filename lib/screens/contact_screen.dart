import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/reading_settings.dart';
import '../ui/app_visuals.dart';

class ContactScreen extends StatelessWidget {
  static const supportEmail = 'naloriapp@gmail.com';
  static const _contactLinks = <_ContactLink>[
    _ContactLink(
      label: 'Email us',
      subtitle: supportEmail,
      icon: Icons.mail_outline_rounded,
      url: 'mailto:$supportEmail?subject=Nalori%20feedback',
    ),
    _ContactLink(
      label: 'GitHub',
      subtitle: 'View the project repository',
      icon: Icons.code_rounded,
      url: 'https://github.com/PurushotamMehra/ShortFormBook',
    ),
    _ContactLink(
      label: 'GitHub Issues',
      subtitle: 'Report bugs or request improvements',
      icon: Icons.bug_report_outlined,
      url: 'https://github.com/PurushotamMehra/ShortFormBook/issues',
    ),
  ];

  final ReadingSettings settings;

  const ContactScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = AppUi.appTheme(settings);

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: settings.backgroundColor,
        appBar: AppBar(title: const Text('Contact')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: AppUi.surfaceCard(settings, prominent: true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: AppUi.accentPill(
                      settings,
                    ).copyWith(borderRadius: AppUi.cardRadius(AppUi.radiusMd)),
                    child: Icon(
                      Icons.support_agent_rounded,
                      color: settings.accentColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Need help or feedback?',
                    style: settings.getAppTextStyle(
                      TextStyle(
                        color: settings.textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Send questions, bug reports, or ideas. Nalori opens links in your default apps when available.',
                    style: settings.getAppTextStyle(
                      TextStyle(
                        color: settings.mutedColor,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: AppUi.surfaceCard(settings),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _contactLinks.length; i++) ...[
                    _ContactLinkTile(
                      settings: settings,
                      link: _contactLinks[i],
                    ),
                    if (i != _contactLinks.length - 1)
                      Divider(
                        height: 1,
                        color: settings.mutedColor.withValues(alpha: 0.14),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactLinkTile extends StatelessWidget {
  final ReadingSettings settings;
  final _ContactLink link;

  const _ContactLinkTile({required this.settings, required this.link});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(link.url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not open ${link.label}.')));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: settings.accentColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(link.icon, color: settings.accentColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: settings.getAppTextStyle(
                        TextStyle(
                          color: settings.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      link.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: settings.getAppTextStyle(
                        TextStyle(
                          color: settings.mutedColor,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.open_in_new_rounded,
                color: settings.mutedColor,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactLink {
  final String label;
  final String subtitle;
  final IconData icon;
  final String url;

  const _ContactLink({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.url,
  });
}
