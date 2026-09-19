import 'package:flutter/material.dart';

import '../../../../../common/limit_field.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../../settings/widgets/section_title.dart';
import '../server_limits_controllers.dart';

/// The limits half of the server settings dialog.
///
/// Every field here is off by default and says so, because that is the honest
/// framing: a self-hosted server is the operator's hardware and Rift imposes
/// nothing on it. These exist so an operator who *does* want a ceiling has
/// somewhere to say it, not because the software thinks they should.
class ServerLimitsSection extends StatelessWidget {
  final ServerLimitsControllers controllers;
  final bool enabled;

  const ServerLimitsSection({
    super.key,
    required this.controllers,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(label: 'Limits'),
        const SizedBox(height: 4),
        Text(
          'Nothing here is on unless you turn it on. Leave a box empty and '
          "there's no limit. Attachments are what fill a disk, so the two "
          'sweeps below delete their files too.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 14),
        LimitField(
          controller: controllers.attachmentMb,
          label: 'Max attachment size',
          unit: 'MB',
          hint: '25',
          helper: 'Applies to every file, image and voice note on this server.',
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        LimitField(
          controller: controllers.retentionDays,
          label: 'Delete messages older than',
          unit: 'days',
          hint: 'Keep forever',
          helper:
              'Deleted for good, nightly, along with their attachments. A '
              'channel or the DMs can override this.',
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        LimitField(
          controller: controllers.historyCap,
          label: 'Keep at most',
          unit: 'messages',
          hint: 'Keep everything',
          helper:
              'Per channel and per conversation, oldest dropped first. Also '
              'permanent, and also overridable.',
          enabled: enabled,
        ),
        const SizedBox(height: 12),
        Text(
          'Both sweeps reach the direct messages on this server as well. To '
          'give those their own numbers, right-click Server DMs in the '
          'sidebar.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 22),
        SectionTitle(label: 'Calls'),
        const SizedBox(height: 4),
        Text(
          'Calls cost upload, not disk, and the cost is the number talking '
          'times the number listening — so it grows faster than the call '
          'does. Muted microphones are free.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 14),
        LimitField(
          controller: controllers.voiceParticipants,
          label: 'Most people in one call',
          unit: 'people',
          hint: 'No limit',
          helper:
              'Anyone past this is told the call is full. Screen shares '
              "don't count against it — they belong to somebody already in.",
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        LimitField(
          controller: controllers.shareMbps,
          label: 'Most a screen share may use',
          unit: 'Mbps',
          hint: "The sharer's setting",
          helper:
              'A share goes out at full quality to every watcher, so one '
              'person at 10 Mbps costs 10 Mbps for each of them.',
          enabled: enabled,
        ),
      ],
    );
  }
}
