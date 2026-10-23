import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_limits.dart';
import '../../../../../../logic/services/byte_format.dart';
import '../../../profile/person/widgets/profile_fact.dart';
import '../../../profile/person/widgets/profile_facts.dart';
import '../../../profile/person/widgets/profile_section.dart';

/// What the server allows: how big a file, how long messages are kept, how
/// many fit in a call, and whether what is said here is sealed.
///
/// The limits an operator sets were seen only by admins, in Manage server,
/// and a member found each one by running into it. These are the ones a
/// member runs into; storage and the DM rate are the server's business.
class ServerProfileLimits extends StatelessWidget {
  final Server server;

  const ServerProfileLimits({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    return ProfileSection(
      label: 'Limits',
      child: ProfileFacts(facts: _facts()),
    );
  }

  List<ProfileFact> _facts() {
    final limits = server.limits;
    final number = NumberFormat.decimalPattern();
    // A channel whose encryption an admin turned off, which its own header
    // says too. Counted, so "Encrypted" is never a claim about all of them
    // when it is true of most.
    final plain = server.channels
        .where((c) => c.hasMessages && !c.isEncrypted)
        .length;
    return [
      ProfileFact(
        label: 'Messages',
        value: switch (plain) {
          0 => 'End-to-end encrypted',
          1 => 'Encrypted, but for 1 channel',
          _ => 'Encrypted, but for $plain channels',
        },
      ),
      ProfileFact(
        label: 'Kept for',
        value: switch (limits.messageRetentionDays) {
          ServerLimits.unlimited => 'Forever',
          1 => '1 day',
          final days => '${number.format(days)} days',
        },
      ),
      if (limits.messageHistoryCap != ServerLimits.unlimited)
        ProfileFact(
          label: 'History',
          value: 'Last ${number.format(limits.messageHistoryCap)} per channel',
        ),
      ProfileFact(
        label: 'Files',
        value: 'Up to ${humanSize(limits.maxAttachmentBytes)}',
      ),
      ProfileFact(
        label: 'Calls',
        value: limits.maxVoiceParticipants == ServerLimits.unlimited
            ? 'No limit'
            : 'Up to ${number.format(limits.maxVoiceParticipants)} people',
      ),
      if (limits.maxShareMbps != ServerLimits.unlimited)
        ProfileFact(
          label: 'Streams',
          value: 'Up to ${limits.maxShareMbps} Mbps',
        ),
      if (limits.maxMembers != ServerLimits.unlimited)
        ProfileFact(
          label: 'Members',
          value: 'Up to ${number.format(limits.maxMembers)}',
        ),
    ];
  }
}
