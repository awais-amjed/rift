import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/limit_field.dart';
import '../../../../../theme/app_text.dart';
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
  final ThemeState themeState;
  final bool enabled;

  const ServerLimitsSection({
    super.key,
    required this.controllers,
    required this.themeState,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(label: 'Limits', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          "Nothing here is on unless you turn it on. Leave a box empty and "
          "there's no limit.",
          style: AppText.label.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: themeState.textTertiary,
          ),
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
          controller: controllers.channelQuota,
          label: 'Messages per member in a channel',
          unit: 'per day',
          hint: 'No limit',
          helper:
              'The default for every channel. A single channel can override '
              'it from its own settings.',
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        LimitField(
          controller: controllers.dmQuota,
          label: 'Direct messages per member',
          unit: 'per day',
          hint: 'No limit',
          helper: "Counts across all of a member's conversations here.",
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        LimitField(
          controller: controllers.retentionDays,
          label: 'Delete messages older than',
          unit: 'days',
          hint: 'Keep forever',
          helper: 'Deleted for good, nightly. There is no undo and no archive.',
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
              'permanent.',
          enabled: enabled,
        ),
      ],
    );
  }
}
