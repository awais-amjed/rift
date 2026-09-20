import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/soundboard_sound.dart';
import '../../../data/enums/server_permission.dart';
import '../../../data/participant_identity.dart';
import '../../services/server_topic_watcher.dart';
import '../../services/server_topics.dart';
import '../../services/soundboard_cache.dart';
import '../../services/soundboard_play.dart';
import '../../services/soundboard_player.dart';
import '../app/app_cubit.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

part 'soundboard_state.dart';

/// The selected server's soundboard: the library, and what happens when
/// somebody presses one.
///
/// **A press never reaches the server.** It is a packet on the call's own
/// LiveKit data channel, and everybody who receives it plays the clip out of
/// their own speakers at their own volume — see [SoundboardPlay] for why that
/// shape rather than a published track. So this cubit does two unrelated
/// jobs that only look related: it keeps the *library* (an ordinary table,
/// refreshed on a realtime doorbell), and it is the ear on the data channel.
class SoundboardCubit extends Cubit<SoundboardState> {
  final ServerCubit _serverCubit;
  final AppCubit _appCubit;
  LiveKitCubit? _livekitCubit;

  /// Per-sender rate limiting, applied on the way *in*. A cooldown the sender
  /// honours is one a modified client deletes.
  final SoundboardGate _gate = SoundboardGate();

  late final ServerTopicWatcher _watcher;

  SoundboardCubit({
    required ServerCubit serverCubit,
    required AppCubit appCubit,
    LiveKitCubit? livekitCubit,
  }) : _serverCubit = serverCubit,
       _appCubit = appCubit,
       _livekitCubit = livekitCubit,
       super(const SoundboardState()) {
    _watcher = ServerTopicWatcher(
      serverCubit: serverCubit,
      topicOf: (server) => ServerTopics.server(server.id),
      event: ServerEvent.soundboard,
      onChanged: () => unawaited(refresh()),
      onServerChanged: (server) {
        _gate.clear();
        if (server == null) {
          emit(const SoundboardState());
          return;
        }
        emit(
          SoundboardState(
            status: SoundboardStatus.loading,
            serverId: server.id,
          ),
        );
        unawaited(refresh());
      },
    );
  }

  void setLiveKitCubit(LiveKitCubit cubit) => _livekitCubit = cubit;

  /// Whether this member may add to or remove from the library.
  bool get canManage =>
      _serverCubit.state.selectedServer?.user?.permissions.can(
        ServerPermission.manageSoundboard,
      ) ??
      false;

  /// Whether this member may fire one into a call.
  bool get canPlay =>
      _serverCubit.state.selectedServer?.user?.permissions.can(
        ServerPermission.useSoundboard,
      ) ??
      false;

  // ── The library ─────────────────────────────────────────

  Future<void> refresh() async {
    final serverId = _serverCubit.state.selectedServer?.id;
    if (serverId == null) return;

    final result = await _serverCubit.listSounds();
    // The rail moved while this was in flight; the answer is another
    // server's and drawing it under this one's name would be a lie.
    if (isClosed || _serverCubit.state.selectedServer?.id != serverId) return;

    emit(
      state.copyWith(
        status: result.error == null
            ? SoundboardStatus.ready
            : SoundboardStatus.error,
        serverId: serverId,
        sounds: result.sounds,
        error: result.error,
        clearError: result.error == null,
      ),
    );
  }

  /// Add a clip. Returns the reason it did not work, or null.
  Future<String?> add({
    required String name,
    String? emoji,
    required Uint8List bytes,
    required String contentType,
    required Duration duration,
  }) async {
    final result = await _serverCubit.addSound(
      name: name,
      emoji: emoji,
      bytes: bytes,
      contentType: contentType,
      duration: duration,
    );
    if (result.error != null) return result.error;
    // Shown at once rather than waited for: the realtime doorbell will bring
    // the same row along in a moment, and a picker that stays empty until it
    // does reads as a failed upload.
    if (!isClosed && result.sound != null) {
      emit(state.copyWith(sounds: [...state.sounds, result.sound!]));
    }
    return null;
  }

  Future<String?> rename({
    required SoundboardSound sound,
    required String name,
    String? emoji,
  }) async {
    final result = await _serverCubit.renameSound(
      soundId: sound.id,
      name: name,
      emoji: emoji,
    );
    if (!result.success) return result.error;
    if (!isClosed) {
      emit(
        state.copyWith(
          sounds: [
            for (final s in state.sounds)
              if (s.id == sound.id)
                s.copyWith(name: name, emoji: emoji, clearEmoji: emoji == null)
              else
                s,
          ],
        ),
      );
    }
    return null;
  }

  Future<String?> remove(SoundboardSound sound) async {
    final result = await _serverCubit.deleteSound(
      soundId: sound.id,
      objectPath: sound.objectPath,
    );
    if (!result.success) return result.error;
    if (!isClosed) {
      emit(
        state.copyWith(
          sounds: [
            for (final s in state.sounds)
              if (s.id != sound.id) s,
          ],
        ),
      );
    }
    return null;
  }

  // ── Pressing one ────────────────────────────────────────

  /// Fire [sound] into the call this client is in.
  ///
  /// Sent to the room and played here separately, because LiveKit does not
  /// echo a data packet back to its sender — and because the presser's own
  /// per-person settings are not theirs to apply to themselves.
  Future<void> press(SoundboardSound sound) async {
    final room = _livekitCubit?.state.room;
    if (room == null || _livekitCubit?.state.currentChannelId == null) return;
    if (!canPlay) return;

    // The same gate as a listener's, keyed on ourselves: a held-down button
    // should not flood the room even though nothing here would stop it.
    if (!_gate.admit('', DateTime.now())) return;

    emit(state.copyWith(pressed: {...state.pressed, sound.id}));
    Timer(SoundboardPlay.cooldown, () {
      if (isClosed) return;
      emit(state.copyWith(pressed: {...state.pressed}..remove(sound.id)));
    });

    try {
      await room.localParticipant?.publishData(
        SoundboardPlay.encode(sound.id),
        reliable: true,
        topic: SoundboardPlay.topic,
      );
    } catch (e) {
      debugPrint('SoundboardCubit: could not send the press – $e');
    }

    await _playLocally(sound, volume: _volumeFor(null));
  }

  /// Somebody else pressed one. Called by [LiveKitCubit] for every data packet
  /// on [SoundboardPlay.topic] — which has already established that it came
  /// from a participant rather than from the server.
  void hear({required String userId, required String soundId}) {
    if (!_gate.admit(userId, DateTime.now())) return;

    final volume = _volumeFor(userId);
    if (volume <= 0) return;

    // A clip this client has never heard of — added while we were away, or a
    // press from a newer client. Re-reading the library is the right answer
    // and is cheap; the clip that prompted it is simply missed.
    final sound = state.sounds.where((s) => s.id == soundId).firstOrNull;
    if (sound == null) {
      unawaited(refresh());
      return;
    }

    unawaited(_playLocally(sound, volume: volume));
  }

  /// Stop anything still playing — leaving a call, or being deafened
  /// part-way through somebody's airhorn.
  Future<void> silence() async {
    _gate.clear();
    await SoundboardPlayer.instance.stopAll();
  }

  Future<void> _playLocally(
    SoundboardSound sound, {
    required double volume,
  }) async {
    if (volume <= 0) return;
    final source = await SoundboardCache.instance.source(
      sound.objectPath,
      () => _serverCubit.loadSound(sound.objectPath),
    );
    if (source == null || isClosed) return;
    await SoundboardPlayer.instance.play(source, volume: volume);
  }

  /// How loud a clip from [userId] should be here, 0 for silent.
  ///
  /// Four things can silence one and they are deliberately all on this
  /// device: being deafened, muting the soundboard, muting that person's
  /// soundboard, or turning either volume to nothing. Null is our own press,
  /// which no per-person setting applies to.
  double _volumeFor(String? userId) {
    if (_livekitCubit?.state.isDeafenedEffective ?? false) return 0;

    final app = _appCubit.state;
    if (app.soundboardMuted) return 0;

    if (userId == null) return app.soundboardVolume;

    final setting = app
        .participantSettings[ParticipantIdentity.soundboardSettingsKey(userId)];
    if (setting?.muted ?? false) return 0;
    return app.soundboardVolume * (setting?.volume ?? 1.0);
  }

  @override
  Future<void> close() async {
    await _watcher.dispose();
    await SoundboardPlayer.instance.stopAll();
    return super.close();
  }
}
