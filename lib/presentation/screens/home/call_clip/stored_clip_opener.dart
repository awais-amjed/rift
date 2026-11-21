import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/classes/stored_clip.dart';
import '../../../../logic/cubits/clip_history/clip_history_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../common/server_context_scope.dart';
import '../../../common/show_custom_dialog.dart';
import 'call_clip_dialog.dart';

/// Opens a kept clip in the trim view again: from the Clips card in a call,
/// or the list in Settings. In the scope of the server it was clipped on
/// while that is still on the list, so Add to soundboard goes to that
/// server's soundboard; with the server gone, or from a DM call, there is no
/// Add, only Save.
Future<void> openStoredClip(BuildContext context, StoredClip clip) async {
  final audio = await context.read<ClipHistoryCubit>().open(clip);
  if (!context.mounted) return;
  if (audio == null) {
    HelperMethods.showError(error: "Couldn't open the clip.");
    return;
  }
  final serverId = clip.serverId;
  final onList =
      serverId != null &&
      context.read<ServerCubit>().state.serverOn(serverId) != null;
  await showCustomDialog<void>(
    context: context,
    build: (_) {
      final dialog = CallClipDialog(
        clip: audio,
        fromDmCall: clip.fromDmCall,
        serverId: onList ? serverId : null,
      );
      return onList
          ? ServerContextScope(serverId: serverId, child: dialog)
          : dialog;
    },
  );
}
