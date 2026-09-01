import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../logic/cubits/app/app_cubit.dart';
import '../logic/cubits/central_dm/central_dm_cubit.dart';
import '../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../logic/cubits/dm/dm_cubit.dart';
import '../logic/cubits/livekit/livekit_cubit.dart';
import '../logic/cubits/notifications/server_notifications_cubit.dart';
import '../logic/cubits/public_servers/public_servers_cubit.dart';
import '../logic/cubits/screenshare/screenshare_cubit.dart';
import '../logic/cubits/server/server_cubit.dart';
import '../logic/cubits/server_events/server_events_cubit.dart';
import '../logic/cubits/server_members/server_members_cubit.dart';
import '../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../logic/cubits/theme/theme_cubit.dart';
import '../logic/cubits/token/token_cubit.dart';
import '../logic/cubits/vault/vault_cubit.dart';
import '../logic/cubits/voice_stats/voice_stats_cubit.dart';

/// Every app-wide cubit, and the callbacks that wire them to each other.
///
/// [appCubit] and [vaultCubit] are created during bootstrap — the window
/// geometry and the vault check both need them before the first frame — so
/// they are provided by value rather than constructed here.
///
/// Order matters: a `create` may only `context.read` a cubit listed above it.
class AppProviders extends StatelessWidget {
  final AppCubit appCubit;
  final VaultCubit vaultCubit;
  final Widget child;

  const AppProviders({
    super.key,
    required this.appCubit,
    required this.vaultCubit,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit()),
        BlocProvider(create: (_) => _createServerCubit()),
        BlocProvider.value(value: appCubit),
        BlocProvider.value(value: vaultCubit),
        BlocProvider(create: (_) => TokenCubit()),
        BlocProvider(
          create: (context) => LiveKitCubit(
            appCubit: context.read<AppCubit>(),
            tokenCubit: context.read<TokenCubit>(),
            // Calls are end-to-end encrypted with the channel's own key, and
            // the vault is where the identity that unwraps it lives.
            vaultCubit: vaultCubit,
            // So LiveKit can re-authenticate on token expiry.
            serverCubit: context.read<ServerCubit>(),
          ),
        ),
        BlocProvider(create: _createScreenshareCubit),
        BlocProvider(
          create: (context) =>
              VoiceStatsCubit(livekitCubit: context.read<LiveKitCubit>()),
        ),
        BlocProvider(
          create: (context) =>
              VoiceListenersCubit(serverCubit: context.read<ServerCubit>()),
        ),
        BlocProvider(
          create: (context) => ChannelPresenceCubit(
            serverCubit: context.read<ServerCubit>(),
            livekitCubit: context.read<LiveKitCubit>(),
          ),
        ),
        BlocProvider(
          // Not lazy: the roster subscription is also how a member learns that
          // their own moderation state changed, and that has to invalidate
          // their cached LiveKit token whether or not a sidebar is watching.
          lazy: false,
          create: _createServerMembersCubit,
        ),
        BlocProvider(
          create: (context) => ChannelChatCubit(
            serverCubit: context.read<ServerCubit>(),
            // For resolving `@name` to a user id when a message is sent.
            membersCubit: context.read<ServerMembersCubit>(),
            vaultCubit: vaultCubit,
          ),
        ),
        BlocProvider(
          create: (context) => DmCubit(
            serverCubit: context.read<ServerCubit>(),
            vaultCubit: vaultCubit,
          ),
        ),
        BlocProvider(
          // Not lazy: the incoming-DM subscription and its unread badge must
          // run wherever you are in the app, not only once Home is opened.
          lazy: false,
          create: (context) =>
              CentralDmCubit(vaultCubit: vaultCubit, appCubit: appCubit),
        ),
        BlocProvider(
          // Not lazy: the per-server notifications subscription must run
          // whenever a server is selected, not only when a chat view reads it.
          lazy: false,
          create: (context) => ServerNotificationsCubit(
            serverCubit: context.read<ServerCubit>(),
            chatCubit: context.read<ChannelChatCubit>(),
            // Which conversation is open decides which DM rows count as read...
            dmCubit: context.read<DmCubit>(),
            // ...and the surface decides whether it's on screen at all.
            appCubit: appCubit,
          ),
        ),
        BlocProvider(
          // Not lazy: subscribes to the selected server's realtime event
          // doorbell so structural changes (new channels, …) show live.
          lazy: false,
          create: _createServerEventsCubit,
        ),
        BlocProvider(
          // Not lazy: must exist at startup to receive vault/server change
          // callbacks for cloud auto-backup.
          lazy: false,
          create: _createBackupCubit,
        ),
        // Lazy, and the only cubit here that should be: the directory is read
        // when a dialog asks for it, so an account that never browses or
        // publishes never contacts central for this at all.
        BlocProvider(create: (_) => PublicServersCubit()),
      ],
      child: child,
    );
  }

  ServerCubit _createServerCubit() {
    final serverCubit = ServerCubit();
    // Lets ServerCubit re-authenticate on token expiry.
    serverCubit.injectVaultCubit(vaultCubit);
    // A backup import immediately reconciles the server list...
    vaultCubit.setOnServersImported(serverCubit.syncWithImportedVault);
    // ...and an export captures the full one.
    vaultCubit.setGetServersForExport(serverCubit.getServersForExport);
    return serverCubit;
  }

  ScreenshareCubit _createScreenshareCubit(BuildContext context) {
    final screenshareCubit = ScreenshareCubit(
      serverCubit: context.read<ServerCubit>(),
      livekitCubit: context.read<LiveKitCubit>(),
    );
    // So a LiveKit disconnect tears down an active share.
    context.read<LiveKitCubit>().setScreenshareCubit(screenshareCubit);
    return screenshareCubit;
  }

  ServerMembersCubit _createServerMembersCubit(BuildContext context) {
    final serverCubit = context.read<ServerCubit>();
    final tokenCubit = context.read<TokenCubit>();
    final members = ServerMembersCubit(serverCubit: serverCubit);
    // A cached LiveKit token still grants what it was minted with, so being
    // muted has to throw it away — otherwise rejoining restores the old
    // permissions until it expires.
    members.setOnSelfModerationChanged(() {
      final url = serverCubit.state.selectedServer?.supabaseUrl;
      if (url != null) tokenCubit.invalidateServerTokens(url);
    });
    // Which participants in a call are bots, so their media is keyed with the
    // derived key rather than the channel key (BOTS.md §6b). Set here rather
    // than injected because the roster is built after LiveKitCubit and would
    // otherwise be a construction cycle.
    context.read<LiveKitCubit>().isBotResolver = (userId) =>
        members.state.byId[userId]?.isBot ?? false;
    return members;
  }

  ServerEventsCubit _createServerEventsCubit(BuildContext context) {
    final serverCubit = context.read<ServerCubit>();
    final events = ServerEventsCubit(
      serverCubit: serverCubit,
      // A deleted channel has to put you out of its call and close its chat.
      livekitCubit: context.read<LiveKitCubit>(),
      chatCubit: context.read<ChannelChatCubit>(),
    );
    serverCubit.setOnServerEvent(events.notifyServerChanged);
    return events;
  }

  SupabaseBackupCubit _createBackupCubit(BuildContext context) {
    final backupCubit = SupabaseBackupCubit(vaultCubit: vaultCubit);
    vaultCubit.setOnVaultChanged(backupCubit.autoBackup);
    context.read<ServerCubit>().setOnServersChanged(backupCubit.autoBackup);
    return backupCubit;
  }
}
