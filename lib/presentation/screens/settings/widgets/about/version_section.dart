import 'package:flutter/material.dart';

import '../../../../../logic/services/app_log.dart';
import '../../../../common/setting_row.dart';
import '../section_title.dart';

/// Which Rift this is, as a bug report and the log name it: the version and
/// its build. For the copies whose updater does not show it — a phone, the
/// web, a Linux folder copy.
class VersionSection extends StatefulWidget {
  /// A line on where newer versions come from, if there is one to say.
  final String? whereUpdatesCome;

  const VersionSection({super.key, this.whereUpdatesCome});

  @override
  State<VersionSection> createState() => _VersionSectionState();
}

class _VersionSectionState extends State<VersionSection> {
  // Asked once: the answer never changes while the app runs.
  final _about = AppLog.about();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Version'),
        const SizedBox(height: 12),
        FutureBuilder(
          future: _about,
          builder: (context, snapshot) {
            final version = snapshot.data?.version.split('+');
            return SettingRow(
              title: version == null ? 'Rift' : 'Rift ${version.first}',
              description: [
                if (version != null && version.length > 1)
                  'Build ${version.last}.',
                ?widget.whereUpdatesCome,
              ].join(' '),
              control: const SizedBox.shrink(),
            );
          },
        ),
      ],
    );
  }
}
