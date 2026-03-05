import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../../data/classes/participant_info.dart';
import '../../../data/classes/screen_share_settings.dart';

part 'app_state.dart';

class AppCubit extends HydratedCubit<AppState> {
  AppCubit() : super(const AppState());

  // ──────────────────────────────────────────────────────────
  // Persisted: sidebar
  // ──────────────────────────────────────────────────────────

  void setIsPinned(bool isPinned) {
    emit(state.copyWith(isPinned: isPinned));
  }

  // ──────────────────────────────────────────────────────────
  // Persisted: media
  // ──────────────────────────────────────────────────────────

  void setAudioEnabled(bool enabled) {
    emit(state.copyWith(audioEnabled: enabled));
  }

  void setVideoEnabled(bool enabled) {
    emit(state.copyWith(videoEnabled: enabled));
  }

  void setScreenShareSettings(ScreenShareSettings settings) {
    emit(state.copyWith(screenShareSettings: settings));
  }

  // ──────────────────────────────────────────────────────────
  // Persisted: participant volume / mute
  // ──────────────────────────────────────────────────────────

  void setParticipantSetting(String identity, {bool? muted, double? volume}) {
    final existing =
        state.participantSettings[identity] ?? const ParticipantSetting();
    final updated = Map<String, ParticipantSetting>.from(
      state.participantSettings,
    )..[identity] = existing.copyWith(muted: muted, volume: volume);
    emit(state.copyWith(participantSettings: updated));
  }

  // ──────────────────────────────────────────────────────────
  // Transient: sidebar hover
  // ──────────────────────────────────────────────────────────

  void setIsHovered(bool isHovered) {
    emit(state.copyWith(isHovered: isHovered));
  }

  // ──────────────────────────────────────────────────────────
  // Transient: channel selection
  // ──────────────────────────────────────────────────────────

  void setSelectedChannelId(String? channelId) {
    emit(
      state.copyWith(
        selectedChannelId: channelId,
        clearSelectedChannelId: channelId == null,
        participants: const [],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Transient: live participants
  // ──────────────────────────────────────────────────────────

  void setParticipants(List<ParticipantInfo> participants) {
    emit(state.copyWith(participants: participants));
  }

  // ──────────────────────────────────────────────────────────
  // Hydration
  // ──────────────────────────────────────────────────────────

  @override
  AppState? fromJson(Map<String, dynamic> json) => AppState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(AppState state) => state.toJson();
}
