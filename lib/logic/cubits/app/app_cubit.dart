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

  void setParticipantSetting(String identity, {bool? muted, double? volume}) {
    final existing =
        state.participantSettings[identity] ?? const ParticipantSetting();
    final updated = Map<String, ParticipantSetting>.from(
      state.participantSettings,
    )..[identity] = existing.copyWith(muted: muted, volume: volume);
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
