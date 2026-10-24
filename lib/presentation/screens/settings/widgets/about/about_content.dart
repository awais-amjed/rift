import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/update/update_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../section_divider.dart';
import 'links_section.dart';
import 'updates_section.dart';
import 'version_section.dart';

/// Settings' About tab: which Rift this is, on Windows and Linux the
/// updater, and links to Rift's pages on the web. Where Rift replaces itself
/// the updater's row already names the version, so the plain one is only for
/// the copies that cannot.
class AboutContent extends StatelessWidget {
  const AboutContent({super.key});

  @override
  Widget build(BuildContext context) {
    final updates =
        HostPlatform.selfUpdates &&
        context.select<UpdateCubit, bool>((c) => c.state.canUpdate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!updates) ...[
          VersionSection(whereUpdatesCome: _whereUpdatesCome),
          if (HostPlatform.selfUpdates) const SectionDivider(),
        ],
        if (HostPlatform.selfUpdates) const UpdatesSection(),
        const SectionDivider(),
        const LinksSection(),
      ],
    );
  }

  /// The line under the version, for a copy that does not update itself.
  /// A Linux folder copy says nothing here: the updater's row below already
  /// says why it cannot.
  static String? get _whereUpdatesCome {
    if (kIsWeb) return 'Reload the page to get the newest version.';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'New versions come from Google Play, or joinrift.app if you '
          'installed it from there.';
    }
    return null;
  }
}
