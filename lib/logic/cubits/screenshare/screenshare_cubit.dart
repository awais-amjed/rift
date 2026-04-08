import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/screen_share_settings.dart';
import '../../../src/rust/api/screenshare.dart';
import '../../../src/rust/api/screenshare/types.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';

part 'screenshare_state.dart';

/// Cubit for managing screen sharing via Rust LiveKit integration.
class ScreenshareCubit extends Cubit<ScreenshareState> {
  final ServerCubit _serverCubit;
  final LiveKitCubit? _livekitCubit;

  ScreenshareCubit({
    required ServerCubit serverCubit,
    LiveKitCubit? livekitCubit,
  }) : _serverCubit = serverCubit,
       _livekitCubit = livekitCubit,
       super(const ScreenshareState());

  /// Start screen sharing with the given settings.
  ///
  /// Server context (auth token, LiveKit URL, user identity) is resolved
  /// internally via [_serverCubit] and [_livekitCubit].
  Future<void> startScreenShare({
    required ScreenShareSettings settings,
  }) async {
    emit(state.copyWith(status: ScreenshareStatus.connecting));

    try {
      // On web, use LiveKit's native screen sharing
      if (kIsWeb) {
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
          emit(state.copyWith(status: ScreenshareStatus.error, error: 'Not connected to a channel'));
          return;
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
        emit(state.copyWith(status: ScreenshareStatus.error, error: 'No server selected'));
        return;
      }

      final livekitUrl = server.livekitUrl;
      if (livekitUrl == null) {
        emit(state.copyWith(status: ScreenshareStatus.error, error: 'No LiveKit URL configured'));
        return;
      }

      final user = server.user;
      if (user == null) {
        emit(state.copyWith(status: ScreenshareStatus.error, error: 'No user info available'));
        return;
      }

      final channelId = _livekitCubit?.state.currentChannelId;
      if (channelId == null) {
        emit(state.copyWith(status: ScreenshareStatus.error, error: 'Not connected to a channel'));
        return;
      }

      // On desktop platforms, use Rust implementation.
      // Get a screenshare-specific LiveKit token via ServerCubit (handles Bearer auth + refresh).
      final response = await _serverCubit.getChannelToken(channelId, screenShare: true);

      if (!response.success) {
        emit(
          state.copyWith(
            status: ScreenshareStatus.error,
            error: response.error ?? 'Failed to get channel token',
          ),
        );
        return;
      }

      final livekitToken = response.data['token'] as String;
      final identityWithScreenshare = '${user.id}_screenshare';

      debugPrint('=== SCREENSHARE DATA ===');
      debugPrint('LiveKit URL: $livekitUrl');
      debugPrint('LiveKit Token: $livekitToken');
      debugPrint('Channel ID: $channelId');
      debugPrint('Identity: $identityWithScreenshare');
      debugPrint('Display Name: ${user.displayName}');
      debugPrint('Resolution: ${settings.resolution}p');
      debugPrint('FPS: ${settings.fps}');
      debugPrint('Bitrate: ${settings.bitrate} Mbps');
      debugPrint('Share Audio: ${settings.shareAudio}');
      debugPrint(
        'Capture Type: ${settings.captureFullScreen ? "Full Screen" : "Window"}',
      );
      debugPrint('Selected Source Index: ${settings.selectedVideoSourceIndex}');
      debugPrint('Codec: ${settings.codec}');
      debugPrint('========================');

      final config = ScreenShareConfig(
        livekitUrl: livekitUrl,
        livekitToken: livekitToken,
        channelId: channelId,
        identity: identityWithScreenshare,
        displayName: user.displayName,
        resolution: settings.resolution,
        fps: settings.fps,
        bitrate: settings.bitrate,
        shareAudio: settings.shareAudio,
        captureFullScreen: settings.captureFullScreen,
        selectedVideoSourceIndex: settings.selectedVideoSourceIndex,
        codec: settings.codec,
        selectedAudioSourceIndex: settings.selectedAudioSource?.index,
        selectedAudioSourceSink: settings.selectedAudioSource?.sink,
        selectedAudioSourcePid: settings.selectedVideoSourcePid,
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

  /// Stop screen sharing.
  Future<void> stopScreenShare() async {
    if (state.status != ScreenshareStatus.sharing) return;

    emit(state.copyWith(status: ScreenshareStatus.stopping));

    try {
      // On web, use LiveKit's native screen sharing
      if (kIsWeb) {
        if (_livekitCubit != null) {
          await _livekitCubit.toggleScreenShare();
        }

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

      // On desktop platforms, use Rust implementation
      // Call Rust function to stop screen sharing
      debugPrint('=== STOPPING SCREENSHARE ===');
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

  /// Clear any error state.
  void clearError() {
    emit(state.copyWith(clearError: true));
  }
}
