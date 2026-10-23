import 'package:flutter/material.dart';

import '../../../../../../data/classes/public_server.dart';
import '../../../../../common/label_pill.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../profile/person/widgets/profile_section.dart';

/// What the server says about itself: its directory listing's description
/// and tags.
///
/// The listing is the only place a server describes itself, and its admin
/// wrote it for strangers browsing the directory, so it is just as true for
/// somebody already inside.
class ServerProfileAbout extends StatelessWidget {
  final PublicServer listing;

  const ServerProfileAbout({super.key, required this.listing});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final description = listing.description?.trim() ?? '';
    return ProfileSection(
      label: 'About',
      spaced: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          if (description.isNotEmpty)
            Text(
              description,
              style: AppText.body.copyWith(color: theme.textSecondary),
            ),
          if (listing.tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final tag in listing.tags) LabelPill(label: tag)],
            ),
        ],
      ),
    );
  }
}
