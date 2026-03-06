import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import '../controls/control_bar.dart';
import 'participant_tile.dart';

/// Main video/audio area. Connects to LiveKit and renders participant tiles.
class VideoGrid extends StatefulWidget {
  const VideoGrid({super.key});

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  @override
  Widget build(BuildContext context) {
    return BlocListener<AppCubit, AppState>(
      listenWhen: (prev, curr) =>
          prev.selectedChannelId != curr.selectedChannelId,
      listener: (context, appState) {
        final livekitCubit = context.read<LiveKitCubit>();
        final serverState = context.read<ServerCubit>().state;
        final server = serverState.selectedServer;

        if (appState.selectedChannelId == null) {
          livekitCubit.disconnect();
          return;
        }

        if (server == null) return;

        if (server.user == null) {
          // Will be handled by error view
          return;
        }

        if (server.livekitUrl == null) {
          // Will be handled by error view
          return;
        }

        // Connect to the selected channel
        livekitCubit.connectToChannel(
          channelId: appState.selectedChannelId!,
          supabaseUrl: server.supabaseUrl,
          token: server.token,
          livekitUrl: server.livekitUrl!,
          micEnabled: appState.audioEnabled,
          cameraEnabled: appState.videoEnabled,
        );
      },
      child: BlocBuilder<AppCubit, AppState>(
        builder: (context, appState) {
          if (appState.selectedChannelId == null) {
            return const _NoChannelView();
          }

          return BlocBuilder<LiveKitCubit, LiveKitState>(
            builder: (context, livekitState) {
              final server = context.read<ServerCubit>().state.selectedServer;

              // Check for user/server requirements
              if (server?.user == null) {
                return const _ErrorView(
                  error: 'Please create a user account to join voice channels',
                );
              }

              if (server?.livekitUrl == null) {
                return const _ErrorView(
                  error: 'This server has no LiveKit URL configured',
                );
              }

              // Show connection states
              switch (livekitState.connectionState) {
                case LiveKitConnectionState.disconnected:
                  return const _NoChannelView();
                case LiveKitConnectionState.connecting:
                  return const _ConnectingView();
                case LiveKitConnectionState.error:
                  return _ErrorView(
                    error: livekitState.error ?? 'Unknown error',
                  );
                case LiveKitConnectionState.connected:
                  if (livekitState.room == null) {
                    return const _ConnectingView();
                  }
                  return _RoomView(room: livekitState.room!);
              }
            },
          );
        },
      ),
    );
  }
}

/// Room is connected — shows participant tiles + control bar.
class _RoomView extends StatefulWidget {
  final Room room;

  const _RoomView({required this.room});

  @override
  State<_RoomView> createState() => _RoomViewState();
}

class _RoomViewState extends State<_RoomView> {
  late final EventsListener<RoomEvent> _listener;

  @override
  void initState() {
    super.initState();
    _listener = widget.room.createListener();
    _listener.on<ParticipantConnectedEvent>((_) => setState(() {}));
    _listener.on<ParticipantDisconnectedEvent>((_) => setState(() {}));
    _listener.on<TrackPublishedEvent>((_) => setState(() {}));
    _listener.on<TrackUnpublishedEvent>((_) => setState(() {}));
    _listener.on<ActiveSpeakersChangedEvent>((_) => setState(() {}));
    _listener.on<TrackMutedEvent>((_) => setState(() {}));
    _listener.on<TrackUnmutedEvent>((_) => setState(() {}));
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final participants = <Participant>[
      if (widget.room.localParticipant != null) widget.room.localParticipant!,
      ...widget.room.remoteParticipants.values,
    ];

    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        return Stack(
          children: [
            participants.isEmpty
                ? const _WaitingForParticipants()
                : _ParticipantGrid(
                    participants: participants,
                    participantSettings: appState.participantSettings,
                  ),
            const ControlBar(),
          ],
        );
      },
    );
  }
}

class _ParticipantGrid extends StatelessWidget {
  final List<Participant> participants;
  final Map<String, dynamic> participantSettings;

  const _ParticipantGrid({
    required this.participants,
    required this.participantSettings,
  });

  @override
  Widget build(BuildContext context) {
    // Compute grid columns based on participant count
    int cols = 1;
    if (participants.length >= 2) cols = 2;
    if (participants.length >= 5) cols = 3;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final p = participants[index];
        final setting = participantSettings[p.identity];
        final isMuted = (setting as dynamic)?.muted ?? false;
        return ParticipantTileWidget(participant: p, isMuted: isMuted);
      },
    );
  }
}

class _WaitingForParticipants extends StatelessWidget {
  const _WaitingForParticipants();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline,
                size: 64,
                color: themeState.textQuaternary,
              ),
              const SizedBox(height: 16),
              Text(
                'Waiting for others...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: themeState.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'re the first one here',
                style: TextStyle(fontSize: 14, color: themeState.textTertiary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NoChannelView extends StatelessWidget {
  const _NoChannelView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          color: themeState.bgSecondary,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎙️', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text(
                  'No Channel Selected',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a voice channel from the sidebar to join',
                  style: TextStyle(
                    fontSize: 14,
                    color: themeState.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          color: themeState.bgSecondary,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: CustomColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Connecting...',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Joining voice channel',
                  style: TextStyle(
                    fontSize: 14,
                    color: themeState.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;

  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          color: themeState.bgSecondary,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text(
                  'Connection Error',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    error,
                    style: const TextStyle(
                      fontSize: 14,
                      color: CustomColors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
