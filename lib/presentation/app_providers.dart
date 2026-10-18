import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/repositories/server_reach_probe.dart';
import '../data/repositories/session_repository.dart';
import '../logic/cubits/app/app_cubit.dart';
import '../logic/cubits/central_dm/central_dm_cubit.dart';
import '../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../logic/cubits/dm/dm_cubit.dart';
import '../logic/cubits/dm_call/dm_call_cubit.dart';
import '../logic/cubits/ducking/ducking_cubit.dart';
import '../logic/cubits/livekit/livekit_cubit.dart';
import '../logic/cubits/media/media_cubit.dart';
import '../logic/cubits/network/network_cubit.dart';
import '../logic/cubits/notifications/server_notifications_cubit.dart';
import '../logic/cubits/public_servers/public_servers_cubit.dart';
import '../logic/cubits/screenshare/screenshare_cubit.dart';
import '../logic/cubits/server/server_cubit.dart';
import '../logic/cubits/server_reach/server_reach_cubit.dart';
import '../logic/cubits/sound_share/sound_share_cubit.dart';
import '../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../logic/cubits/theme/theme_cubit.dart';
import '../logic/cubits/token/token_cubit.dart';
import '../logic/cubits/update/update_cubit.dart';
import '../logic/cubits/vault/vault_cubit.dart';
import '../logic/cubits/voice_stats/voice_stats_cubit.dart';
import '../logic/services/server_context.dart';
import '../logic/services/server_hub.dart';

/// Over the widget budget and one job: every app-wide cubit and the wiring
/// between them, which is only readable in one place.
///
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

  /// Being signed in to the servers, shared by the vault and every cubit
  /// that makes server calls (see [SessionRepository]).
  final SessionRepository session;
  final Widget child;

  const AppProviders({
    super.key,
    required this.appCubit,
    required this.vaultCubit,
    required this.session,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(value: session, child: _providers());
  }

  Widget _providers() {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit()),
        BlocProvider(create: (_) => MediaCubit()),
        BlocProvider(create: (_) => DuckingCubit()),
        BlocProvider(create: (_) => _createServerCubit()),
        BlocProvider(create: _createNetworkCubit),
        BlocProvider(create: (_) => ServerReachCubit.of(session)),
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
            session: session,
          ),
        ),
        BlocProvider(create: _createScreenshareCubit),
        BlocProvider(create: _createSoundShareCubit),
        BlocProvider(
          create: (context) =>
              VoiceStatsCubit(livekitCubit: context.read<LiveKitCubit>()),
        ),
        BlocProvider(
          create: (context) =>
              ChannelChatCubit(session: session, vaultCubit: vaultCubit),
        ),
        BlocProvider(
          create: (context) =>
              DmCubit(session: session, vaultCubit: vaultCubit),
        ),
        BlocProvider(
          // Not lazy: a call has to ring whatever is on screen, on every
          // server, from the moment the app is up.
          lazy: false,
          create: (context) => DmCallCubit(
            session: session,
            livekitCubit: context.read<LiveKitCubit>(),
            vaultCubit: vaultCubit,
            appCubit: appCubit,
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
          create: (context) {
            final notifications = ServerNotificationsCubit(
              session: session,
              chatCubit: context.read<ChannelChatCubit>(),
              // Which conversation is open decides which DM rows count as
              // read...
              dmCubit: context.read<DmCubit>(),
              // ...and the surface decides whether it's on screen at all.
              appCubit: appCubit,
            );
            // A person muted to nothing still shows up calling, quietly.
            context.read<DmCallCubit>().injectNotifications(notifications);
            return notifications;
          },
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
        BlocProvider(
          // Not lazy: it looks for a newer Rift in the background, whether or
          // not anything on screen shows it yet.
          lazy: false,
          create: (_) => UpdateCubit(appCubit: appCubit),
        ),
      ],
      child: RepositoryProvider(
        // Not lazy: it holds the selected server's context and the call's —
        // the roster that tells a member their own moderation changed, the
        // Reports badge, the doorbell, the call's ear for soundboard presses
        // — whether or not anything on screen reads them yet.
        lazy: false,
        create: _createServerHub,
        dispose: (hub) => unawaited(hub.dispose()),
        child: child,
      ),
    );
  }

  ServerCubit _createServerCubit() {
    final serverCubit = ServerCubit(session: session);
    // A backup import immediately reconciles the server list...
    vaultCubit.setOnServersImported(serverCubit.syncWithImportedVault);
    // ...and an export captures the full one.
    vaultCubit.setGetServersForExport(serverCubit.getServersForExport);
    return serverCubit;
  }

  /// When the platform is unsure about the internet, the servers you joined
  /// settle it — and nobody else is asked.
  NetworkCubit _createNetworkCubit(BuildContext context) {
    final servers = context.read<ServerCubit>();
    final probe = ServerReachProbe();
    return NetworkCubit(
      confirm: () =>
          probe.anyAnswers(servers.state.servers.map((s) => s.supabaseUrl)),
    );
  }

  ScreenshareCubit _createScreenshareCubit(BuildContext context) {
    final screenshareCubit = ScreenshareCubit(
      livekitCubit: context.read<LiveKitCubit>(),
    );
    // So a LiveKit disconnect tears down an active share.
    context.read<LiveKitCubit>().setScreenshareCubit(screenshareCubit);
    return screenshareCubit;
  }

  SoundShareCubit _createSoundShareCubit(BuildContext context) {
    final soundShareCubit = SoundShareCubit(
      livekitCubit: context.read<LiveKitCubit>(),
    );
    // So a LiveKit disconnect tears down an active share.
    context.read<LiveKitCubit>().setSoundShareCubit(soundShareCubit);
    return soundShareCubit;
  }

  /// Each server's live cubits ([ServerContext]), and the call's two
  /// questions of its server's: which participants are bots, and whose
  /// soundboard a press comes from.
  ServerHub _createServerHub(BuildContext context) {
    final livekit = context.read<LiveKitCubit>();
    final serverCubit = context.read<ServerCubit>();
    final tokenCubit = context.read<TokenCubit>();
    final chatCubit = context.read<ChannelChatCubit>();
    final hub = ServerHub(
      session: session,
      open: (serverId) => ServerContext.open(
        serverId,
        session: session,
        appCubit: appCubit,
        vaultCubit: vaultCubit,
        tokenCubit: tokenCubit,
        serverCubit: serverCubit,
        livekitCubit: livekit,
        chatCubit: chatCubit,
      ),
    );
    // So a press arriving on the data channel reaches the call's library, and
    // so leaving a call or deafening cuts off a clip already playing.
    livekit.setSoundboardOf(() => hub[livekit.state.callServerId]?.soundboard);
    // Which participants in a call are bots, so their media is keyed with the
    // derived key rather than the channel key (BOTS.md §6b). Asked of the
    // call's server, never the selected one: a rotation taken while the
    // member reads another server keyed the call's bots as people, and they
    // went silent.
    livekit.isBotResolver = (userId) =>
        hub[livekit.state.callServerId]?.members.state.byId[userId]?.isBot ??
        false;
    return hub;
  }

  SupabaseBackupCubit _createBackupCubit(BuildContext context) {
    final backupCubit = SupabaseBackupCubit(vaultCubit: vaultCubit);
    vaultCubit.setOnVaultChanged(backupCubit.autoBackup);
    final serverCubit = context.read<ServerCubit>();
    serverCubit.setOnServersChanged(backupCubit.autoBackup);
    backupCubit.setMergeCloudServers(serverCubit.mergeCloudManifest);
    return backupCubit;
  }
}
