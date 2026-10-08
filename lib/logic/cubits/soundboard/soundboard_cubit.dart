import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/apis/soundboard_api.dart';
import '../../../data/classes/equality_props.dart';
import '../../../data/classes/soundboard_sound.dart';
import '../../../data/enums/server_permission.dart';
import '../../../data/participant_identity.dart';
import '../../../data/repositories/session_repository.dart';
import '../../helper_methods.dart';
import '../../services/server_topic_watcher.dart';
import '../../services/server_topics.dart';
import '../../services/soundboard_cache.dart';
import '../../services/soundboard_play.dart';
import '../../services/soundboard_player.dart';
import '../app/app_cubit.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

part 'soundboard_library.dart';
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
/// The library is `soundboard_library.dart`; the ear is here.
class SoundboardCubit extends Cubit<SoundboardState>
    with _SoundboardLibraryMixin {
  final SessionRepository _session;
  @override
  final SoundboardApi _api;
  final AppCubit _appCubit;
  LiveKitCubit? _livekitCubit;

  /// What a server will hold, mirrored from `app.soundboard_max()` so the
  /// page can count down to it rather than finding out on a refusal.
  static const int maxSounds = 48;

  /// Per-sender rate limiting, applied on the way *in*. A cooldown the sender
  /// honours is one a modified client deletes.
  final SoundboardGate _gate = SoundboardGate();

  /// How long a chip naming the presser stays up, and how many at once.
  ///
  /// Short, because it is an answer to a question the sound just asked and
  /// not a feed. Three, because a fourth would be the control bar's height
  /// again and the chips sit directly above it.
  static const Duration heardLifetime = Duration(milliseconds: 2400);
  static const int maxRecent = 3;

  /// One expiry per chip, so hovering one does not hold the others up.
  final Map<String, Timer> _heardTimers = {};

  late final ServerTopicWatcher _watcher;

  /// Whether this is the app's own soundboard, which plays into calls. One
  /// pinned to a server for a settings page plays only previews, and closing
  /// it must not cut off a clip the call is playing.
  final bool _ownsPlayback;

  /// The selected server's soundboard — the app's own — or, given
  /// [serverId], that one server's library, for Manage server opened on a
  /// server the person is not looking at. Whoever opens that page owns that
  /// one and closes it; it plays only previews.
  SoundboardCubit({
    required ServerCubit serverCubit,
    required SessionRepository session,
    required AppCubit appCubit,
    LiveKitCubit? livekitCubit,
    String? serverId,
  }) : _session = session,
       _api = SoundboardApi(session: session),
       _appCubit = appCubit,
       _livekitCubit = livekitCubit,
       _ownsPlayback = serverId == null,
       super(const SoundboardState()) {
    // The one thing still read off the cubit: hearing the selection move.
    _watcher = ServerTopicWatcher(
      serverCubit: serverCubit,
      fixedServerId: serverId,
      topicOf: (server) => ServerTopics.server(server.id),
      event: ServerEvent.soundboard,
      onChanged: () => unawaited(refresh()),
      onServerChanged: (server) {
        _gate.clear();
        _clearHeard();
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

  @override
  String? get _libraryServerId => _watcher.serverId;

  /// Whether this member may fire one into a call. Widgets read the same
  /// permission off `ServerState`, where a change to it rebuilds them.
  bool get _canPlay =>
      _session.selectedServer?.user?.permissions.can(
        ServerPermission.useSoundboard,
      ) ??
      false;

  // ── Pressing one ────────────────────────────────────────

  /// Fire [sound] into the call this client is in.
  ///
  /// Sent to the room and played here separately, because LiveKit does not
  /// echo a data packet back to its sender — and because the presser's own
  /// per-person settings are not theirs to apply to themselves.
  Future<void> press(SoundboardSound sound) async {
    final room = _livekitCubit?.state.room;
    if (room == null || !(_livekitCubit?.state.inCall ?? false)) return;
    if (!_canPlay) return;

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
      HelperMethods.printDebug(
        'SoundboardCubit: could not send the press – $e',
      );
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

    // Announced only for a clip that is about to be audible. A press this
    // device silenced must not put a line on screen, or the mute has stopped
    // being a mute and become a notification.
    _announce(userId: userId, soundId: soundId);
    unawaited(_playLocally(sound, volume: volume));
  }

  // ── Who pressed it ──────────────────────────────────────

  void _announce({required String userId, required String soundId}) {
    if (isClosed) return;
    final now = DateTime.now();
    final id = '$userId:${now.microsecondsSinceEpoch}';
    final next = [
      ...state.recent,
      SoundboardHeard(id: id, userId: userId, soundId: soundId, at: now),
    ];
    while (next.length > maxRecent) {
      _heardTimers.remove(next.removeAt(0).id)?.cancel();
    }
    emit(state.copyWith(recent: next));
    _heardTimers[id] = Timer(heardLifetime, () => dismissHeard(id));
  }

  /// Keep a chip up — the pointer is on it. A 2.4s window you cannot hit is
  /// not an affordance, and the mute button lives inside that window.
  void holdHeard(String id) => _heardTimers.remove(id)?.cancel();

  /// Start its clock again, optionally longer: a chip that has turned into
  /// its own receipt is offering an undo and needs to outlive the press.
  void releaseHeard(String id, {Duration? after}) {
    if (isClosed || !state.recent.any((h) => h.id == id)) return;
    _heardTimers[id]?.cancel();
    _heardTimers[id] = Timer(after ?? heardLifetime, () => dismissHeard(id));
  }

  void dismissHeard(String id) {
    _heardTimers.remove(id)?.cancel();
    if (isClosed || !state.recent.any((h) => h.id == id)) return;
    emit(
      state.copyWith(
        recent: [
          for (final heard in state.recent)
            if (heard.id != id) heard,
        ],
      ),
    );
  }

  void _clearHeard() {
    for (final timer in _heardTimers.values) {
      timer.cancel();
    }
    _heardTimers.clear();
  }

  /// Play [sound] on this device and nowhere else.
  ///
  /// For the person managing the library, who has to know which of three
  /// airhorns this one is. Goes through the same rule as a press of our own,
  /// so the mute does not reach it and being deafened does.
  Future<void> preview(SoundboardSound sound) =>
      _playLocally(sound, volume: _volumeFor(null));

  /// Stop anything still playing — leaving a call, or being deafened
  /// part-way through somebody's airhorn.
  Future<void> silence() async {
    _gate.clear();
    _clearHeard();
    if (!isClosed && state.recent.isNotEmpty) {
      emit(state.copyWith(recent: const []));
    }
    await SoundboardPlayer.instance.stopAll();
  }

  Future<void> _playLocally(
    SoundboardSound sound, {
    required double volume,
  }) async {
    if (volume <= 0) return;
    final source = await SoundboardCache.instance.source(
      sound.objectPath,
      () => _api.loadSound(sound.objectPath, serverId: _watcher.serverId),
    );
    if (source == null || isClosed) return;
    await SoundboardPlayer.instance.play(source, volume: volume);
  }

  /// How loud a clip from [userId] should be here, 0 for silent. Null is a
  /// clip this device asked for — our own press, or the manage page's
  /// preview.
  ///
  /// Everything that can silence one is on this device, and the rule itself
  /// is [SoundboardVolume], which is pure and tested.
  double _volumeFor(String? userId) {
    final app = _appCubit.state;
    final setting = userId == null
        ? null
        : app.participantSettings[ParticipantIdentity.soundboardSettingsKey(
            userId,
          )];
    return SoundboardVolume.resolve(
      deafened: _livekitCubit?.state.isDeafenedEffective ?? false,
      muted: app.soundboardMuted,
      globalVolume: app.soundboardVolume,
      fromSelf: userId == null,
      personMuted: setting?.muted ?? false,
      personVolume: setting?.volume ?? 1.0,
    );
  }

  @override
  Future<void> close() async {
    _clearHeard();
    await _watcher.dispose();
    if (_ownsPlayback) await SoundboardPlayer.instance.stopAll();
    return super.close();
  }
}
