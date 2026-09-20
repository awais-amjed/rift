import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/friend.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
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
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => MultiBlocProvider(
      providers: providers,
      child: MemberProfileDialog(userId: userId, fallbackName: name),
    ),
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
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => MultiBlocProvider(
      providers: providers,
      child: CentralProfileDialog(friend: friend),
    ),
  );
}
