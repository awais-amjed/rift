import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/friend.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/popover_surface.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/theme_context.dart';
import 'central_profile_dialog.dart';
import 'member_profile_dialog.dart';

/// Open somebody's profile.
///
/// Two functions rather than one, because there are two kinds of person in
/// Rift and nothing links them: a **membership** of one server, and a
/// **central account**. They carry different material, answer to different
/// permissions, and a dialog that tried to be both would have to guess which
/// one it was looking at. The surface knows, so the surface says.
///
/// Both take their cubits from the calling context and hand them to the route
/// — a dialog is a route, and a route rebuilds for reasons that have nothing
/// to do with the dialog, so reading them inside the builder is how a resize
/// becomes "Looking up a deactivated widget's ancestor".
///
/// On a phone both open as a **sheet** instead. A profile is a glance you
/// take in the middle of something else, and the thing behind it — the
/// message, the roster row, the friends list — is what made you take it. A
/// full-screen dialog covers exactly that, and a profile is short enough
/// that it would be a header over a field of empty grey.

/// The sheet route both profiles take on a phone.
///
/// [child] is built once by the caller, while its context is still mounted,
/// for the reason the doc above gives.
Future<void> _showAsSheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.theme.bgSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PopoverSurface.radius),
      ),
    ),
    builder: (_) => child,
  );
}

/// A person on the server that is currently open.
///
/// [name] is what the clicked row was already showing, so the dialog has
/// something to title itself with while the roster is asked about an id it
/// may never have paged in.
Future<void> showMemberProfile(
  BuildContext context, {
  required String userId,
  required String name,
}) {
  final providers = [
    BlocProvider.value(value: context.read<ThemeCubit>()),
    BlocProvider.value(value: context.read<ServerCubit>()),
    BlocProvider.value(value: context.read<ServerMembersCubit>()),
    BlocProvider.value(value: context.read<ChannelPresenceCubit>()),
  ];
  final dialog = MultiBlocProvider(
    providers: providers,
    child: MemberProfileDialog(userId: userId, fallbackName: name),
  );
  if (context.layoutMode.isCompact) return _showAsSheet(context, dialog);
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => dialog,
  );
}

/// A central account, from the friends page or a central conversation.
Future<void> showCentralProfile(
  BuildContext context, {
  required Friend friend,
}) {
  final providers = [
    BlocProvider.value(value: context.read<ThemeCubit>()),
    BlocProvider.value(value: context.read<CentralDmCubit>()),
  ];
  final dialog = MultiBlocProvider(
    providers: providers,
    child: CentralProfileDialog(friend: friend),
  );
  if (context.layoutMode.isCompact) return _showAsSheet(context, dialog);
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => dialog,
  );
}
