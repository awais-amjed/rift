import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/server.dart';
import '../../../../common/status_chip.dart';
import '../../../../theme/custom_colors.dart';
import 'console_update_dialog.dart';

/// "Console 1.7.0 available" under the server's name, for its admins, when
/// its console knows of a newer release (`Server.consoleUpdate`).
///
/// Under the header rather than in its row: the row spends its width on the
/// name and two buttons, and already cut "End-to-end encrypted" to one word.
/// A chip in the title bar, as the app's own update has, would not say which
/// server, and somebody may run several. Telling only: pressing it says what
/// is new and how to update, which happens on the server's own machine.
class ConsoleUpdateRow extends StatelessWidget {
  final Server server;

  const ConsoleUpdateRow({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    final update = server.consoleUpdate;
    final admin = server.user?.permissions.isServerAdmin ?? false;
    if (update == null || !admin) return const SizedBox.shrink();
    return Padding(
      // The header's own left inset, so the chip lines up under its icon.
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          icon: Icons.system_update_alt_rounded,
          label: 'Console ${update.version} available',
          color: CustomColors.success,
          tooltip:
              'A newer release of this server\'s console is out. '
              'Only admins see this.',
          onTap: () => showConsoleUpdateDialog(context, update),
        ),
      ),
    );
  }
}
