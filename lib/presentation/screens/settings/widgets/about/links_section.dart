import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/rift_links.dart';
import '../../../../../logic/services/open_link.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';

/// Settings' About: where to read about Rift beyond the app — what it is,
/// running a server of your own, and what it does with your data. Somebody
/// who installed it from a store listing has no other way to find these.
class LinksSection extends StatelessWidget {
  const LinksSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Links'),
        SizedBox(height: 8),
        _LinkRow(
          icon: Icons.public_rounded,
          title: 'Website',
          description: 'What Rift is and how it works.',
          url: RiftLinks.website,
        ),
        _LinkRow(
          icon: Icons.dns_outlined,
          title: 'Self-hosting guide',
          description: 'Run a Rift server of your own.',
          url: RiftLinks.selfHostingGuide,
        ),
        _LinkRow(
          icon: Icons.policy_outlined,
          title: 'Privacy policy',
          description: 'What Rift collects, and why.',
          url: RiftLinks.privacyPolicy,
        ),
      ],
    );
  }
}

/// One page, the whole row the tap target: a link has nothing else on its
/// row to press, unlike a setting.
class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String url;

  const _LinkRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => openExternalLink(url),
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: K.touchTargetMin),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, size: K.iconLarge, color: theme.accentBright),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppText.row.copyWith(color: theme.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: AppText.secondary.copyWith(
                          height: 1.4,
                          color: theme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: K.iconRow,
                  color: theme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
