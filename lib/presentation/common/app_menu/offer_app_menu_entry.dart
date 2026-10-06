import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/services/linux_desktop_entry.dart';
import '../confirm_dialog.dart';

/// Asks once whether a Linux folder copy should add itself to the app menu,
/// as the AppImage does unasked. Not asked again either way: Settings has the
/// button for a change of mind.
Future<void> offerAppMenuEntry(BuildContext context) async {
  if (!LinuxDesktopEntry.offersToAdd) return;
  final app = context.read<AppCubit>();
  if (app.state.addToAppMenu != null) return;
  if (await LinuxDesktopEntry.inMenu()) return;
  if (!context.mounted) return;
  final add = await showConfirmDialog(
    context: context,
    title: 'Add Rift to your app menu?',
    message: 'Open it from your apps like anything else, with its icon.',
    confirmLabel: 'Add',
    cancelLabel: 'Not now',
    icon: Icons.apps_rounded,
  );
  if (add) await LinuxDesktopEntry.ensure(replace: true);
  app.setAddToAppMenu(add);
}
