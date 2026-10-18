import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/app_button.dart';
import '../../../../common/empty_state.dart';
import '../add_server/show_add_server_dialog.dart';

/// Where a server's channels go when there is no server: a phone's whole
/// page, a desktop's sidebar under the header.
///
/// A button rather than directions to one. "Tap the header" taught a gesture
/// to someone with nothing else on the screen to press — and the channel
/// list drawn empty in its place said "An admin has to create the first one"
/// about a server that did not exist.
class NoServerYet extends StatelessWidget {
  const NoServerYet({super.key});

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.dns_outlined,
    title: 'No server yet',
    message: 'Join one with an invite link, or find a public one.',
    action: AppButton(
      label: 'Add a server',
      icon: const Icon(Icons.add_rounded, size: K.iconRow),
      onPressed: () => showAddServerDialog(context),
    ),
  );
}
