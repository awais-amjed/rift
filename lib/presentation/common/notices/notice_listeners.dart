import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';

import '../../../data/classes/notice.dart';
import '../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../logic/cubits/dm/dm_cubit.dart';
import '../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/sound_share/sound_share_cubit.dart';
import '../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../logic/helper_methods.dart';

/// Shows every [Notice] a cubit sets, once, as a toast.
///
/// Sits inside the toast overlay at the root of the app, so a notice shows
/// whatever screen is up — what the cubits' own toasts did before they moved
/// here. A cubit with notices of its own gets a line in [build].
class NoticeListeners extends StatelessWidget {
  final Widget child;

  const NoticeListeners({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        _on<ServerCubit, ServerState>((s) => s.notice),
        _on<ChannelChatCubit, ChannelChatState>((s) => s.notice),
        _on<DmCubit, DmState>((s) => s.notice),
        _on<CentralDmCubit, CentralDmState>((s) => s.notice),
        _on<DmCallCubit, DmCallState>((s) => s.notice),
        _on<ScreenshareCubit, ScreenshareState>((s) => s.notice),
        _on<SoundShareCubit, SoundShareState>((s) => s.notice),
        _on<SupabaseBackupCubit, SupabaseBackupState>((s) => s.notice),
      ],
      child: child,
    );
  }

  static BlocListener<C, S> _on<C extends StateStreamable<S>, S>(
    Notice? Function(S state) notice,
  ) => BlocListener<C, S>(
    listenWhen: (before, after) =>
        notice(after) != null && notice(after) != notice(before),
    listener: (context, state) => _show(notice(state)!),
  );

  static void _show(Notice notice) => HelperMethods.showToast(
    title: notice.title,
    description: notice.message,
    type: switch (notice.kind) {
      NoticeKind.info => ToastificationType.info,
      NoticeKind.success => ToastificationType.success,
      NoticeKind.error => ToastificationType.error,
    },
    autoCloseDuration: notice.duration,
  );
}
