import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;

import '../../../data/classes/screen_share_settings.dart';
import '../../services/call_foreground_service.dart';
import '../../services/host_platform.dart';
import '../../../src/rust/api/screenshare.dart';
import '../../../src/rust/api/screenshare/types.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

part 'screenshare_state.dart';

/// Cubit managing screen sharing.
///
/// Two implementations behind one state. On a desktop the capture, encoding
/// and publishing all happen in Rust, against libwebrtc's desktop capturer.
/// On web and on a phone the SDK does it: the browser has its own picker, and
/// Android has MediaProjection, which libwebrtc does not expose a desktop
/// capturer for at all — [_sdkCapturesScreen] is which of the two applies.
class ScreenshareCubit extends Cubit<ScreenshareState> {
  /// Whether the LiveKit SDK captures the screen here, rather than Rust.
  static bool get _sdkCapturesScreen => kIsWeb || HostPlatform.isMobile;

  final ServerCubit _serverCubit;
  final LiveKitCubit? _livekitCubit;

  StreamSubscription<ScreenshareEvent>? _eventSub;

  ScreenshareCubit({
    required ServerCubit serverCubit,
    LiveKitCubit? livekitCubit,
  }) : _serverCubit = serverCubit,
       _livekitCubit = livekitCubit,
       super(const ScreenshareState()) {
    // Desktop screen sharing runs in Rust; listen for its lifecycle events
    // (e.g. the shared window being closed) so we can stop and update the UI.
    // Nothing to listen to where the SDK is doing the capturing.
    if (!_sdkCapturesScreen) {
      _eventSub = screenshareEventStream().listen(_onRustScreenshareEvent);
    }
  }

  void _onRustScreenshareEvent(ScreenshareEvent event) {
    if (event == ScreenshareEvent.sourceClosed &&
        state.status == ScreenshareStatus.sharing) {
      // The captured window was closed — tear the session down and reset UI.
      stopScreenShare();
    }
  }

  /// Starts screen sharing with the given settings.
  Future<void> startScreenShare({required ScreenShareSettings settings}) async {
    emit(state.copyWith(status: ScreenshareStatus.connecting));

    try {
      // Hand to the SDK wherever it can do the job itself. On web the browser
      // owns the picker; on a phone LiveKit drives MediaProjection, which is
      // the only way in — the Rust pipeline below captures a *desktop*, and
      // libwebrtc does not build its capturer for Android at all.
      if (_sdkCapturesScreen) {
        if (_livekitCubit == null) {
          emit(
            state.copyWith(
              status: ScreenshareStatus.error,
              error: 'LiveKit cubit not available',
            ),
          );
          return;
        }

        final channelId = _livekitCubit.state.currentChannelId;
        if (channelId == null) {
          emit(
            state.copyWith(
              status: ScreenshareStatus.error,
              error: 'Not connected to a channel',
            ),
          );
          return;
        }

        // Android wants consent, and then a foreground service declaring
        // mediaProjection running *before* the capture starts. A refusal at
        // the consent sheet is the user saying no, which needs no error of
        // ours on top of it.
        if (HostPlatform.isMobile) {
          if (!await Helper.requestCapturePermission() ||
              !await CallForegroundService.screenShareStarting()) {
            emit(state.copyWith(status: ScreenshareStatus.idle));
            return;
          }
        }

        await _livekitCubit.toggleScreenShare();

        emit(
          state.copyWith(
            status: ScreenshareStatus.sharing,
            channelId: channelId,
            settings: settings,
          ),
        );
        return;
      }

      // Resolve server context
      final server = _serverCubit.state.selectedServer;
      if (server == null) {
        emit(
          state.copyWith(
            status: ScreenshareStatus.error,
            error: 'No server selected',
          ),
        );
        return;
      }

      final livekitUrl = server.livekitUrl;
      if (livekitUrl == null) {
        emit(
          state.copyWith(
            status: ScreenshareStatus.error,
            error: 'No LiveKit URL configured',
          ),
        );
        return;
      }

      final user = server.user;
      if (user == null) {
        emit(
          state.copyWith(
            status: ScreenshareStatus.error,
            error: 'No user info available',
          ),
        );
        return;
      }

      final channelId = _livekitCubit?.state.currentChannelId;
      if (channelId == null) {
        emit(
          state.copyWith(
            status: ScreenshareStatus.error,
            error: 'Not connected to a channel',
          ),
        );
        return;
      }

      // On desktop, delegate to the Rust LiveKit implementation.
      // Get a screenshare-specific token via ServerCubit.
      final response = await _serverCubit.getChannelToken(
        channelId,
        screenShare: true,
      );

      if (!response.success) {
        emit(
          state.copyWith(
            status: ScreenshareStatus.error,
            error: response.error ?? 'Failed to get channel token',
          ),
        );
        return;
      }

      // The token carries the identity, including the per-device segment
      // that keeps the base and screenshare connections paired.
      final livekitToken = response.data['token'] as String;

      // The call's key, for the second connection this is about to open into
      // the same encrypted room.
      final encryption = _livekitCubit?.callEncryption;
      if (encryption == null) {
        emit(
          state.copyWith(
            status: ScreenshareStatus.error,
            error:
                'Cannot share yet — this call’s encryption key is not ready. '
                'Rejoining the channel usually clears it.',
          ),
        );
        return;
      }

      final config = ScreenShareConfig(
        livekitUrl: livekitUrl,
        livekitToken: livekitToken,
        resolution: settings.resolution,
        fps: settings.fps,
        bitrate: settings.bitrate,
        shareAudio: settings.shareAudio,
        captureFullScreen: settings.captureFullScreen,
        selectedVideoSourceIndex: settings.selectedVideoSourceIndex,
        codec: settings.videoCodec,
        selectedAudioSourceIndex: settings.selectedAudioSource?.index,
        selectedAudioSourceSink: settings.selectedAudioSource?.sink,
        selectedAudioSourcePid: settings.selectedVideoSourcePid,
        // The same key the call itself uses. Without it the Rust side refuses
        // to connect, which is the right way round: a screen share that fails
        // is a bug report, a screen share the server can watch is not.
        e2EeKey: encryption.key,
        e2EeKeyIndex: encryption.index,
      );

      final result = await startScreenshare(config: config);
      debugPrint('✓ Rust connection result: $result');

      emit(
        state.copyWith(
          status: ScreenshareStatus.sharing,
          channelId: channelId,
          settings: settings,
        ),
      );
    } catch (e) {
      debugPrint('✗ Screen share error: $e');
      emit(
        state.copyWith(
          status: ScreenshareStatus.error,
          error: 'Failed to start screen share: $e',
        ),
      );
    }
  }

  /// Stops screen sharing.
  Future<void> stopScreenShare() async {
    if (state.status != ScreenshareStatus.sharing) return;

    emit(state.copyWith(status: ScreenshareStatus.stopping));

    try {
      // Hand to the SDK wherever it can do the job itself. On web the browser
      // owns the picker; on a phone LiveKit drives MediaProjection, which is
      // the only way in — the Rust pipeline below captures a *desktop*, and
      // libwebrtc does not build its capturer for Android at all.
      if (_sdkCapturesScreen) {
        if (_livekitCubit != null) {
          await _livekitCubit.toggleScreenShare();
        }
        // The capture has stopped, so the service drops back to the plain
        // call type — the call is still running and still needs holding up.
        await CallForegroundService.screenShareStopped();

        emit(
          state.copyWith(
            status: ScreenshareStatus.idle,
            clearChannelId: true,
            clearSettings: true,
            clearError: true,
          ),
        );
        return;
      }

      // On desktop, use the Rust implementation.
      debugPrint('Stopping screenshare...');
      final result = await stopScreenshare();
      debugPrint('✓ Rust disconnect result: $result');

      emit(
        state.copyWith(
          status: ScreenshareStatus.idle,
          clearChannelId: true,
          clearSettings: true,
          clearError: true,
        ),
      );
    } catch (e) {
      debugPrint('✗ Stop screenshare error: $e');
      emit(
        state.copyWith(
          status: ScreenshareStatus.error,
          error: 'Failed to stop screen share: $e',
        ),
      );
    }
  }

  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() async {
    await _eventSub?.cancel();
    return super.close();
  }
}
