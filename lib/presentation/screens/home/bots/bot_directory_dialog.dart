import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/public_bot.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/public_bots/public_bots_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../common/app_modal.dart';
import 'add_bot_modal.dart';
import 'bot_listing_form_modal.dart';
import 'browse_bots_modal.dart';
import 'my_bots_modal.dart';

enum _Step { browse, add, mine, form }

/// The bot directory: find one, add it to a server you run, or list your own.
///
/// Built the same way [AddServerDialog] is — a step per modal rather than a
/// body swapped inside one frame, because a step's title, width and footer
/// belong to the step.
///
/// Opened from the Bots page of the manage-server dialog, which is where
/// somebody already goes to see what a bot can reach. It does not live on the
/// server rail beside "Add server": a bot is not something you join, and
/// putting it there would suggest a second kind of thing to belong to.
class BotDirectoryDialog extends StatefulWidget {
  const BotDirectoryDialog({super.key});

  @override
  State<BotDirectoryDialog> createState() => _BotDirectoryDialogState();
}

class _BotDirectoryDialogState extends State<BotDirectoryDialog> {
  _Step _step = _Step.browse;

  /// The bot the add step is for.
  PublicBot? _adding;

  /// The listing the form step is editing, or null when it is creating one.
  PublicBot? _editing;

  void _go(_Step step) => setState(() => _step = step);

  void _close() => Navigator.of(context).pop();

  /// Whether this client runs a server it could put a bot on at all.
  ///
  /// Decided once, here, rather than per row: it is a fact about the client.
  /// A browser that offered Add on every row and then showed an empty picker
  /// would be asking somebody to find out the hard way.
  bool get _canAdd => context
      .watch<ServerCubit>()
      .state
      .servers
      .any(
        (s) => s.user?.permissions.can(ServerPermission.manageBots) ?? false,
      );

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _Step.browse => BrowseBotsModal(
        canAdd: _canAdd,
        onAdd: (bot) => setState(() {
          _adding = bot;
          _step = _Step.add;
        }),
        onList: () => _go(_Step.mine),
        onCancel: _close,
      ),
      _Step.add => AddBotModal(
        bot: _adding!,
        onCancel: () => _go(_Step.browse),
        onDone: () => _go(_Step.browse),
      ),
      _Step.mine => MyBotsModal(
        onEdit: (bot) => setState(() {
          _editing = bot;
          _step = _Step.form;
        }),
        onCancel: () => _go(_Step.browse),
      ),
      _Step.form => BotListingFormModal(
        editing: _editing,
        onCancel: () => _go(_Step.mine),
        // Back to the list rather than out: publishing one bot is often
        // publishing two, and the list is where the cap is shown.
        onSaved: () => _go(_Step.mine),
      ),
    };
  }
}

/// Open the directory with its cubit, from anywhere that holds a
/// [ServerCubit].
///
/// The cubit is made here rather than at the app root because nothing needs
/// it until this dialog opens — an account that never looks at the directory
/// never asks central about it, which is the same bargain
/// `PublicServersCubit` makes.
Future<void> showBotDirectory(BuildContext context) {
  final servers = context.read<ServerCubit>();
  final backup = context.read<SupabaseBackupCubit>();
  return showCustomDialog<void>(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: servers),
        BlocProvider.value(value: backup),
        BlocProvider(create: (_) => PublicBotsCubit()),
      ],
      child: const BotDirectoryDialog(),
    ),
  );
}
