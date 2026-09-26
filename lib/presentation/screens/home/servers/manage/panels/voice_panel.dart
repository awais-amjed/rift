import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../server_settings/voice/voice_region_dialog.dart';
import '../../server_settings/voice/voice_regions_section.dart';
import '../widgets/manage_panel.dart';

/// Where this server's calls are held: the regions a channel may be pinned
/// to, each with the LiveKit it runs and the key that LiveKit signs with.
///
/// Its own page rather than half of Overview, which is where it started. One
/// LiveKit was a URL and two secret fields, and sat under the server's name
/// happily enough; regions made it a list that grows, with its own errors and
/// its own load figures, and Overview became a page about voice infrastructure
/// with the server's name at the top of it.
///
/// No Save. The server's own key pair used to sit under the list with a Save
/// of its own, but it is only the default region's key — every other region
/// carries its own — so it is set in that region's dialog like the rest, and
/// everything on this page acts when its dialog is confirmed. The footer holds
/// Add region, which opens that same dialog.
///
/// Takes the server rather than reading the selection, because the dialog
/// opens from the rail's menu for any server, including one you are not
/// looking at. The region list says why it still needs the server open.
class VoicePanel extends StatelessWidget {
  final Server server;

  const VoicePanel({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    // Only for the server the app is on: the region list says why.
    final isSelected = context.select<ServerCubit, bool>(
      (c) => c.state.selectedServer?.id == server.id,
    );
    return ManagePanel(
      title: 'Regions',
      subtitle: 'Where this server holds calls',
      // In the footer, where Roles keeps New role and Bots keeps Browse bots:
      // the page's one way to add something, found where the others are.
      footer: [
        if (isSelected)
          AppButton(
            label: 'Add region',
            onPressed: () => showVoiceRegionDialog(context),
          ),
      ],
      child: VoiceRegionsSection(serverId: server.id),
    );
  }
}
