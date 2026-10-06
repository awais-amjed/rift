import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/helper_methods.dart';
import '../../../logic/services/linux_desktop_entry.dart';
import '../app_button.dart';
import '../setting_row.dart';

/// Settings' way to put a Linux folder copy in the app menu, for whoever said
/// "Not now" when it was offered.
class AppMenuRow extends StatefulWidget {
  const AppMenuRow({super.key});

  @override
  State<AppMenuRow> createState() => _AppMenuRowState();
}

class _AppMenuRowState extends State<AppMenuRow> {
  late Future<bool> _inMenu = LinuxDesktopEntry.inMenu();

  Future<void> _add() async {
    await LinuxDesktopEntry.ensure(replace: true);
    if (!mounted) return;
    context.read<AppCubit>().setAddToAppMenu(true);
    HelperMethods.showSuccess(message: 'Rift is in your app menu.');
    setState(() => _inMenu = LinuxDesktopEntry.inMenu());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _inMenu,
      builder: (context, snapshot) {
        final inMenu = snapshot.data ?? false;
        return SettingRow(
          title: 'App menu',
          description: inMenu
              ? 'Rift is in your app menu.'
              : 'Open Rift from your apps like anything else, with its icon.',
          control: inMenu
              ? const SizedBox.shrink()
              : AppButton(
                  label: 'Add',
                  variant: AppButtonVariant.secondary,
                  onPressed: snapshot.hasData ? _add : null,
                ),
        );
      },
    );
  }
}
