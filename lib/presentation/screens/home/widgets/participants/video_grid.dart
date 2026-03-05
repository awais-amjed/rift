import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../data/classes/participant_info.dart';
import '../../../../../data/repositories/server_repository.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
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
  final _repository = ServerRepository();
  Room? _room;
  final List<EventsListener<RoomEvent>> _listeners = [];

  String? _currentChannelId;
  bool _isConnecting = false;
  bool _hasLeft = false;
  String? _error;

  @override
  void dispose() {
    _cleanupRoom();
    super.dispose();
  }

  void _cleanupRoom() {
    for (final l in _listeners) {
      l.dispose();
    }
    _listeners.clear();
    _room?.disconnect();
    _room?.dispose();
    _room = null;
  }

  Future<void> _connectToChannel(String channelId) async {
    final server = context.read<ServerCubit>().state.selectedServer;
    if (server == null) return;
    if (server.user == null) {
      setState(
        () => _error = 'Please create a user account to join voice channels',
      );
      return;
    }
    if (server.livekitUrl == null) {
      setState(() => _error = 'This server has no LiveKit URL configured');
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
      _hasLeft = false;
    });

    final response = await _repository.getChannelToken(
      server.supabaseUrl,
      server.token,
      channelId,
    );

    if (!mounted) return;

    if (!response.success) {
      setState(() {
        _isConnecting = false;
        _error = response.error ?? 'Failed to get channel token';
      });
      return;
    }

    if (_hasLeft) {
      setState(() => _isConnecting = false);
      return;
    }

    final livekitToken = response.data['token'] as String;
    final room = Room(
      roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
    );
    _room = room;

    _setupRoomListeners(room);

    try {
      final appState = context.read<AppCubit>().state;
      await room.connect(
        server.livekitUrl!,
        livekitToken,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: appState.audioEnabled),
          camera: TrackOption(enabled: appState.videoEnabled),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to connect: $e';
        _isConnecting = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isConnecting = false);
    }
  }

  void _setupRoomListeners(Room room) {
    final listener = room.createListener();
    _listeners.add(listener);

    listener
      ..on<ParticipantConnectedEvent>((e) => _syncParticipants(room))
      ..on<ParticipantDisconnectedEvent>((e) => _syncParticipants(room))
      ..on<TrackPublishedEvent>((e) => _syncParticipants(room))
      ..on<TrackUnpublishedEvent>((e) => _syncParticipants(room))
      ..on<ActiveSpeakersChangedEvent>((e) => _syncParticipants(room))
      ..on<RoomDisconnectedEvent>((e) {
        if (!_hasLeft) {
          setState(() => _room = null);
          context.read<AppCubit>().setSelectedChannelId(null);
        }
      });
  }

  void _syncParticipants(Room room) {
    if (!mounted) return;
    final appCubit = context.read<AppCubit>();
    final settings = appCubit.state.participantSettings;

    final allParticipants = <Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];

    // Apply saved volume settings
    // Note: Volume control is not available in this version of LiveKit SDK
    // TODO: Implement volume control when SDK supports it
    for (final p in room.remoteParticipants.values) {
      final saved = settings[p.sid];
      if (saved != null && saved.muted) {
        // Mute functionality can still be handled through track enable/disable
        // if needed in the future
      }
    }

    final infos = allParticipants
        .map(
          (p) => ParticipantInfo(
            identity: p.sid,
            name: p.name,
            isSpeaking: p.isSpeaking,
            isMicrophoneEnabled: p.isMicrophoneEnabled(),
            isCameraEnabled: p.isCameraEnabled(),
            isLocal: p is LocalParticipant,
          ),
        )
        .toList();

    appCubit.setParticipants(infos);

    if (mounted) setState(() {});
  }

  void _handleLeave() {
    _hasLeft = true;
    _cleanupRoom();
    context.read<AppCubit>()
      ..setParticipants([])
      ..setSelectedChannelId(null);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AppCubit, AppState>(
      listenWhen: (prev, curr) =>
          prev.selectedChannelId != curr.selectedChannelId,
      listener: (context, state) {
        if (state.selectedChannelId == null) {
          if (!_hasLeft) _cleanupRoom();
          return;
        }
        if (state.selectedChannelId != _currentChannelId) {
          _currentChannelId = state.selectedChannelId;
          _cleanupRoom();
          _connectToChannel(state.selectedChannelId!);
        }
      },
      child: BlocBuilder<AppCubit, AppState>(
        builder: (context, state) {
          if (state.selectedChannelId == null || _hasLeft) {
            return const _NoChannelView();
          }
          if (_error != null) {
            return _ErrorView(error: _error!);
          }
          if (_isConnecting || _room == null) {
            return const _ConnectingView();
          }
          return _RoomView(room: _room!, onLeave: _handleLeave);
        },
      ),
    );
  }
}

/// Room is connected — shows participant tiles + control bar.
class _RoomView extends StatefulWidget {
  final Room room;
  final VoidCallback onLeave;

  const _RoomView({required this.room, required this.onLeave});

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
            ControlBar(room: widget.room, onLeave: widget.onLeave),
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
