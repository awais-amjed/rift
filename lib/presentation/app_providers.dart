import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/repositories/server_reach_probe.dart';
import '../data/repositories/session_repository.dart';
import '../logic/cubits/app/app_cubit.dart';
import '../logic/cubits/central_dm/central_dm_cubit.dart';
import '../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../logic/cubits/dm/dm_cubit.dart';
import '../logic/cubits/dm_call/dm_call_cubit.dart';
import '../logic/cubits/livekit/livekit_cubit.dart';
import '../logic/cubits/media/media_cubit.dart';
import '../logic/cubits/network/network_cubit.dart';
import '../logic/cubits/notifications/server_notifications_cubit.dart';
import '../logic/cubits/public_servers/public_servers_cubit.dart';
import '../logic/cubits/reports/reports_cubit.dart';
import '../logic/cubits/screenshare/screenshare_cubit.dart';
import '../logic/cubits/server/server_cubit.dart';
import '../logic/cubits/server_events/server_events_cubit.dart';
import '../logic/cubits/server_members/server_members_cubit.dart';
import '../logic/cubits/server_reach/server_reach_cubit.dart';
import '../logic/cubits/sound_share/sound_share_cubit.dart';
import '../logic/cubits/soundboard/soundboard_cubit.dart';
import '../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../logic/cubits/theme/theme_cubit.dart';
import '../logic/cubits/token/token_cubit.dart';
import '../logic/cubits/update/update_cubit.dart';
import '../logic/cubits/vault/vault_cubit.dart';
import '../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../logic/cubits/voice_stats/voice_stats_cubit.dart';

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
            serverCubit: context.read<ServerCubit>(),
            session: session,
          ),
        ),
        BlocProvider(create: _createScreenshareCubit),
        BlocProvider(create: _createSoundShareCubit),
        BlocProvider(
          // Not lazy: this is the ear on the call's data channel. A clip
          // somebody presses has to be heard whether or not anything on
          // screen has ever asked for the library.
          lazy: false,
          create: _createSoundboardCubit,
        ),
        BlocProvider(
          create: (context) =>
              VoiceStatsCubit(livekitCubit: context.read<LiveKitCubit>()),
        ),
        BlocProvider(create: (_) => VoiceListenersCubit(session: session)),
        BlocProvider(
          create: (context) => ChannelPresenceCubit(
            serverCubit: context.read<ServerCubit>(),
            livekitCubit: context.read<LiveKitCubit>(),
            session: session,
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
            session: session,
            vaultCubit: vaultCubit,
          ),
        ),
        BlocProvider(
          create: (context) => DmCubit(
            serverCubit: context.read<ServerCubit>(),
            session: session,
            vaultCubit: vaultCubit,
          ),
        ),
        BlocProvider(
          // Not lazy: a call has to ring whatever is on screen, on every
          // server, from the moment the app is up.
          lazy: false,
          create: (context) => DmCallCubit(
            serverCubit: context.read<ServerCubit>(),
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
              serverCubit: context.read<ServerCubit>(),
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
          // Not lazy: the Reports badge has to move when a report arrives,
          // not when somebody first opens the page.
          lazy: false,
          create: (context) => ReportsCubit(
            serverCubit: context.read<ServerCubit>(),
            session: session,
            vaultCubit: vaultCubit,
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
        BlocProvider(
          // Not lazy: it looks for a newer Rift in the background, whether or
          // not anything on screen shows it yet.
          lazy: false,
          create: (_) => UpdateCubit(appCubit: appCubit),
        ),
      ],
      child: child,
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
      session: session,
      livekitCubit: context.read<LiveKitCubit>(),
    );
    // So a LiveKit disconnect tears down an active share.
    context.read<LiveKitCubit>().setScreenshareCubit(screenshareCubit);
    return screenshareCubit;
  }

  SoundShareCubit _createSoundShareCubit(BuildContext context) {
    final soundShareCubit = SoundShareCubit(
      session: session,
      livekitCubit: context.read<LiveKitCubit>(),
    );
    // So a LiveKit disconnect tears down an active share.
    context.read<LiveKitCubit>().setSoundShareCubit(soundShareCubit);
    return soundShareCubit;
  }

  SoundboardCubit _createSoundboardCubit(BuildContext context) {
    final soundboardCubit = SoundboardCubit(
      session: session,
      appCubit: appCubit,
      livekitCubit: context.read<LiveKitCubit>(),
    );
    // So a press arriving on the data channel reaches it, and so leaving a
    // call or deafening cuts off a clip already playing.
    context.read<LiveKitCubit>().setSoundboardCubit(soundboardCubit);
    return soundboardCubit;
  }

  ServerMembersCubit _createServerMembersCubit(BuildContext context) {
    final serverCubit = context.read<ServerCubit>();
    final tokenCubit = context.read<TokenCubit>();
    final members = ServerMembersCubit(session: session);
    // A cached LiveKit token still grants what it was minted with, so being
    // muted has to throw it away — otherwise rejoining restores the old
    // permissions until it expires.
    members.setOnSelfModerationChanged(() {
      final url = serverCubit.state.selectedServer?.supabaseUrl;
      if (url != null) tokenCubit.invalidateServerTokens(url);
    });
    // Presence reports ids; with the roster paged, an id is routinely somebody
    // no page has reached. Resolving them is what keeps the sidebar's Online
    // group from being "the online people who sort early in the alphabet".
    members.watchPresence(
      context.read<ChannelPresenceCubit>().stream.map(
        (state) => state.onlineUserIds,
      ),
    );
    // Which participants in a call are bots, so their media is keyed with the
    // derived key rather than the channel key (BOTS.md §6b). Set here rather
    // than injected because the roster is built after LiveKitCubit and would
    // otherwise be a construction cycle.
    context.read<LiveKitCubit>().isBotResolver = (userId) =>
        members.state.byId[userId]?.isBot ?? false;
    return members;
  }

  ServerEventsCubit _createServerEventsCubit(BuildContext context) {
    return ServerEventsCubit(
      serverCubit: context.read<ServerCubit>(),
      session: session,
      // A deleted channel has to put you out of its call and close its chat.
      livekitCubit: context.read<LiveKitCubit>(),
      chatCubit: context.read<ChannelChatCubit>(),
    );
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
