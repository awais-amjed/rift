import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/app_modal.dart';
import 'invite_modal.dart';

/// The invite dialog with what it reads, for whichever place opens it: the
/// rail's menu, the sidebar header and the Members page.
Widget inviteModal(BuildContext context, {required Server server}) {
  return BlocProvider.value(
    value: context.read<ServerCubit>(),
    child: InviteModal(server: server),
  );
}

/// Open it from anywhere with a plain context. A context menu goes through
/// [showDialogFromMenu] with [inviteModal] instead.
Future<void> showInviteModal(BuildContext context, {required Server server}) {
  return showCustomDialog(
    context: context,
    build: (_) => inviteModal(context, server: server),
  );
}
