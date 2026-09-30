import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../src/rust/api/screenshare/types.dart';
import '../../../src/rust/api/soundshare.dart' as rust;
import '../../helper_methods.dart';
import '../../services/host_platform.dart';
import '../../services/screen_share_sources.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

part 'sound_share_state.dart';

/// Sharing what an application is playing, with no picture attached.
///
/// A screen share's quieter sibling, and the same shape: a second connection
/// into the call, opened in Rust, publishing one track. The difference is what
/// the room does with it — a screen share is watched by whoever asks, a shared
/// track is heard by everyone by default, like a person talking.
///
/// Desktop only. Capturing another application's output needs PulseAudio or
/// WASAPI, so on a phone and on the web [isSupported] is false and the control
/// is not offered at all.
class SoundShareCubit extends Cubit<SoundShareState> {
  final ServerCubit _serverCubit;
  final LiveKitCubit? _livekitCubit;

  StreamSubscription<rust.SoundShareEvent>? _eventSub;

  /// Whether this platform can share an application's sound.
  static bool get isSupported => HostPlatform.capturesSystemAudio;

  SoundShareCubit({
    required ServerCubit serverCubit,
    LiveKitCubit? livekitCubit,
  }) : _serverCubit = serverCubit,
       _livekitCubit = livekitCubit,
       super(const SoundShareState()) {
    if (isSupported) {
      _eventSub = rust.soundShareEventStream().listen(_onRustEvent);
    }
  }

  /// The application quit, or stopped playing. There is nothing left to share,
  /// so the session comes down rather than sitting there publishing silence.
  void _onRustEvent(rust.SoundShareEvent event) {
    if (event == rust.SoundShareEvent.sourceEnded && state.isSharing) {
      stopSoundShare();
    }
  }

  /// Starts sharing [source] into the call this client is in.
  Future<void> startSoundShare({required AudioSource source}) async {
    if (!isSupported) return;
    emit(state.copyWith(status: SoundShareStatus.connecting));

    try {
      final server = _serverCubit.state.selectedServer;

      final livekit = _livekitCubit;
      final channelId = livekit?.state.callKey;
      if (livekit == null || channelId == null) {
        return _fail('Not in a call');
      }

      // The call's key, for the second connection this is about to open into
      // the same encrypted room. Without it the Rust side refuses to connect,
      // which is the right way round: a share that fails is a bug report, a
      // share the server can listen to is not.
      final encryption = _livekitCubit?.callEncryption;
      if (encryption == null) {
        return _fail(
          'Cannot share yet — this call’s encryption key is not ready. '
          'Rejoining the channel usually clears it.',
        );
      }

      // Its own identity, so this connection can sit alongside the caller's
      // own — and alongside their screen share, if they have one up.
      final response = await livekit.shareToken(soundShare: true);
      if (!response.success) {
        return _fail(response.error ?? 'Failed to get channel token');
      }

      // Where to take it. Same rule as the screen share: this is a second
      // connection into the call's own room, so it follows the mint's answer
      // rather than the server row.
      final livekitUrl =
          response.data['livekit_url'] as String? ?? server?.livekitUrl;
      if (livekitUrl == null) {
        return _fail('No LiveKit URL configured');
      }

      final result = await rust.startSoundShare(
        config: rust.SoundShareConfig(
          livekitUrl: livekitUrl,
          livekitToken: response.data['token'] as String,
          selectedAudioSourceIndex: source.index,
          selectedAudioSourceSink: source.sink,
          // Windows lists a source by its process, with the process id in
          // `index`, and captures by process; without the id the capture
          // falls back to the whole mix, which carries the call back in.
          selectedAudioSourcePid: HostPlatform.listsAudioSourcesByProcess
              ? source.index
              : null,
          // Published as the track's name, which is how everyone else's tile
          // says what is playing rather than only whose it is.
          sourceLabel: ScreenShareSources.appLabel(source),
          e2EeKey: encryption.key,
          e2EeKeyIndex: encryption.index,
        ),
      );
      HelperMethods.printDebug('✓ Sound share connection result: $result');

      emit(
        state.copyWith(
          status: SoundShareStatus.sharing,
          channelId: channelId,
          source: source,
          clearError: true,
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('✗ Sound share error: $e');
      _fail('Failed to share sound: $e');
    }
  }

  /// Stops the share. Safe to call when nothing is running.
  Future<void> stopSoundShare() async {
    if (state.status != SoundShareStatus.sharing) return;
    emit(state.copyWith(status: SoundShareStatus.stopping));

    try {
      final result = await rust.stopSoundShare();
      HelperMethods.printDebug('✓ Sound share disconnect result: $result');
      emit(
        state.copyWith(
          status: SoundShareStatus.idle,
          clearChannelId: true,
          clearSource: true,
          clearError: true,
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('✗ Stop sound share error: $e');
      _fail('Failed to stop sharing sound: $e');
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));

  /// Record a failure *and* say it out loud — see [ScreenshareCubit._fail],
  /// which had the same gap: the control bar reads only `isSharing`, so a
  /// refusal emitted into `error` was a field nothing ever looked at.
  void _fail(String message) {
    emit(state.copyWith(status: SoundShareStatus.error, error: message));
    HelperMethods.showError(
      error: message,
      autoCloseDuration: const Duration(seconds: 6),
    );
  }

  @override
  Future<void> close() async {
    await _eventSub?.cancel();
    return super.close();
  }
}
