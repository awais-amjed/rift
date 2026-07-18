import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/classes/participant_info.dart';
import '../../../data/classes/participant_setting.dart';
import '../../../data/classes/screen_share_settings.dart';
import '../../services/windows_audio_ducking/windows_audio_ducking.dart';

part 'app_cubit.g.dart';

part 'app_state.dart';

class AppCubit extends HydratedCubit<AppState> {
  AppCubit() : super(const AppState());

  // ── Persisted: sidebar ───────────────────────────────────

  void setIsPinned(bool isPinned) {
    emit(state.copyWith(isPinned: isPinned));
  }

  void setHomeViewOpen(bool open) {
    emit(state.copyWith(homeViewOpen: open));
  }

  // ── Persisted: title bar ─────────────────────────────────

  void setTitleBarVisible(bool visible) {
    emit(state.copyWith(titleBarVisible: visible));
  }

  // ── Persisted: media ─────────────────────────────────────

  void setAudioEnabled(bool enabled) {
    emit(state.copyWith(audioEnabled: enabled));
  }

  void setVideoEnabled(bool enabled) {
    emit(state.copyWith(videoEnabled: enabled));
  }

  void setPushToTalkEnabled(bool enabled) {
    emit(state.copyWith(pushToTalkEnabled: enabled));
  }

  void setPushToTalkKeybind({required int keyId, required String label}) {
    emit(state.copyWith(pushToTalkKeyId: keyId, pushToTalkKeyLabel: label));
  }

  void clearPushToTalkKeybind() {
    emit(state.copyWith(clearPushToTalkKeybind: true));
  }

  void setScreenShareSettings(ScreenShareSettings settings) {
    emit(state.copyWith(screenShareSettings: settings));
  }

  void setDisableAudioDucking(bool value) {
    emit(state.copyWith(disableAudioDucking: value));
    WindowsAudioDucking.apply(disable: value);
  }

  // ── Audio processing (mic capture) ───────────────────────
  // The LiveKitCubit watches AppState and re-publishes the mic track when any
  // of these change, so a toggle takes effect mid-call.

  void setNoiseSuppression(bool value) {
    emit(state.copyWith(noiseSuppression: value));
  }

  void setEchoCancellation(bool value) {
    emit(state.copyWith(echoCancellation: value));
  }

  void setAutoGainControl(bool value) {
    emit(state.copyWith(autoGainControl: value));
  }

  /// Voice-activity gate threshold (0..1). The LiveKitCubit watches this and
  /// gates mic transmission accordingly during a call.
  void setVoiceActivityThreshold(double value) {
    emit(state.copyWith(voiceActivityThreshold: value.clamp(0.0, 1.0)));
  }

  void setStatsOverlayPinned(bool pinned) {
    emit(state.copyWith(statsOverlayPinned: pinned));
  }

  void setOutputDeviceId(String? deviceId) {
    emit(state.copyWith(
      outputDeviceId: deviceId,
      clearOutputDeviceId: deviceId == null,
    ));
  }

  void setInputDeviceId(String? deviceId) {
    emit(state.copyWith(
      inputDeviceId: deviceId,
      clearInputDeviceId: deviceId == null,
    ));
  }

  // ── Persisted: per-participant volume/mute ───────────────
  // Keyed by user id (not the raw LiveKit identity, which carries a per-device
  // segment) so a user's local mute/volume follows them across devices and
  // sessions.

  void setParticipantSetting(String userId, {bool? muted, double? volume}) {
    final existing =
        state.participantSettings[userId] ?? const ParticipantSetting();
    final updated = Map<String, ParticipantSetting>.from(
      state.participantSettings,
    )..[userId] = existing.copyWith(muted: muted, volume: volume);
    emit(state.copyWith(participantSettings: updated));
  }

  // ── Transient: sidebar hover ─────────────────────────────

  void setIsHovered(bool isHovered) {
    emit(state.copyWith(isHovered: isHovered));
  }

  // ── Transient: channel selection ─────────────────────────

  void setSelectedChannelId(String? channelId) {
    emit(
      state.copyWith(
        selectedChannelId: channelId,
        clearSelectedChannelId: channelId == null,
        participants: const [],
      ),
    );
  }

  // ── Transient: live participants ─────────────────────────

  void setParticipants(List<ParticipantInfo> participants) {
    emit(state.copyWith(participants: participants));
  }

  // ── Persisted: window bounds ─────────────────────────────

  void saveWindowSize(Size size) {
    emit(state.copyWith(windowWidth: size.width, windowHeight: size.height));
  }

  void saveWindowPosition(Offset position) {
    emit(state.copyWith(windowX: position.dx, windowY: position.dy));
  }

  // ── Hydration ────────────────────────────────────────────

  @override
  AppState? fromJson(Map<String, dynamic> json) => AppState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(AppState state) => state.toJson();
}
