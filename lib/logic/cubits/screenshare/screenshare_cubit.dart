import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/screen_share_settings.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../src/rust/api/screenshare.dart';

part 'screenshare_state.dart';

/// Cubit for managing screen sharing via Rust LiveKit integration.
class ScreenshareCubit extends Cubit<ScreenshareState> {
  final ServerRepository _repository;

  ScreenshareCubit({required ServerRepository repository})
    : _repository = repository,
      super(const ScreenshareState());

  /// Start screen sharing with the given settings.
  /// Generates a new token with screen_share flag, and passes data to Rust.
  Future<void> startScreenShare({
    required String supabaseUrl,
    required String token,
    required String channelId,
    required String livekitUrl,
    required String userId,
    required String displayName,
    required ScreenShareSettings settings,
  }) async {
    emit(state.copyWith(status: ScreenshareStatus.connecting));

    try {
      // Get a new LiveKit token with screen_share = true
      final response = await _repository.getChannelToken(
        supabaseUrl,
        token,
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

      final livekitToken = response.data['token'] as String;
      final identityWithScreenshare = '${userId}_screenshare';

      // Print data to debug output
      debugPrint('=== SCREENSHARE DATA ===');
      debugPrint('LiveKit URL: $livekitUrl');
      debugPrint('LiveKit Token: $livekitToken');
      debugPrint('Channel ID: $channelId');
      debugPrint('Identity: $identityWithScreenshare');
      debugPrint('Display Name: $displayName');
      debugPrint('Resolution: ${settings.resolution}p');
      debugPrint('FPS: ${settings.fps}');
      debugPrint('Bitrate: ${settings.bitrate} Mbps');
      debugPrint('Share Audio: ${settings.shareAudio}');
      debugPrint('========================');

      // Call Rust function to start screen sharing
      final config = ScreenShareConfig(
        livekitUrl: livekitUrl,
        livekitToken: livekitToken,
        channelId: channelId,
        identity: identityWithScreenshare,
        displayName: displayName,
        resolution: settings.resolution,
        fps: settings.fps,
        bitrate: settings.bitrate,
        shareAudio: settings.shareAudio,
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
