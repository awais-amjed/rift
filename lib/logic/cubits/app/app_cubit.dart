import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/classes/participant_info.dart';
import '../../../data/classes/participant_setting.dart';
import '../../../data/classes/screen_share_settings.dart';
import '../../../data/constants.dart';
import '../../../data/enums/home_surface.dart';
import '../../../data/enums/sensitive_content_mode.dart';
import '../../../data/participant_identity.dart';
import '../../services/windows_audio_ducking/windows_audio_ducking.dart';

part 'app_cubit.g.dart';
part 'app_state.dart';

class AppCubit extends HydratedCubit<AppState> {
  AppCubit() : super(const AppState());

  // ── Persisted: sidebar ───────────────────────────────────

  void toggleSidebar() {
    emit(state.copyWith(sidebarOpen: !state.sidebarOpen));
  }

  /// Switch the centre pane. Mutually exclusive by construction — there is
  /// no state where two surfaces are open.
  void setSurface(HomeSurface surface) {
    emit(state.copyWith(surface: surface));
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

  /// What the desktop says the push-to-talk key is, or null once no desktop
  /// shortcut is bound.
  void setDesktopPushToTalkKey(String? key) {
    emit(
      key == null
          ? state.copyWith(clearDesktopPushToTalkKey: true)
          : state.copyWith(desktopPushToTalkKey: key),
    );
  }

  void setScreenShareSettings(ScreenShareSettings settings) {
    emit(state.copyWith(screenShareSettings: settings));
  }

  void setSensitiveContentMode(SensitiveContentMode mode) =>
      emit(state.copyWith(sensitiveContentMode: mode));

  void setLinkPreviewsEnabled(bool value) =>
      emit(state.copyWith(linkPreviewsEnabled: value));

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

  /// How many emoji the picker's "frequently used" row remembers. One row of
  /// eight, which is what the design shows.
  static const int maxRecentEmojis = 8;

  /// Moves [emoji] to the front of the recents, dropping the oldest past the
  /// cap. Re-picking something already there promotes it rather than adding a
  /// duplicate.
  void noteEmojiUsed(String emoji) {
    final next = [emoji, ...state.recentEmojis.where((e) => e != emoji)];
    emit(
      state.copyWith(
        recentEmojis: next.take(maxRecentEmojis).toList(growable: false),
      ),
    );
  }

  void setShowStreamStats(bool value) =>
      emit(state.copyWith(showStreamStats: value));

  void setStatsOverlayPinned(bool pinned) {
    emit(state.copyWith(statsOverlayPinned: pinned));
  }

  /// Stores the dragged sidebar width. Deliberately unclamped here: the bounds
  /// depend on the window, and [SidebarSizing.clamp] applies them on the way
  /// out. Storing a clamped value would make a width chosen on a small window
  /// permanent once the window grew again.
  void setSidebarWidth(double width) {
    if (!width.isFinite || width == state.sidebarWidth) return;
    emit(state.copyWith(sidebarWidth: width));
  }

  /// The member list's width, unclamped for the same reason as
  /// [setSidebarWidth]; `MembersSidebarSizing.clamp` applies the bounds on
  /// the way out.
  void setMembersSidebarWidth(double width) {
    if (!width.isFinite || width == state.membersSidebarWidth) return;
    emit(state.copyWith(membersSidebarWidth: width));
  }

  /// Flips what the user sees. While focus has the list out of the way,
  /// that is always "show it", and the choice is kept after focus ends.
  void toggleMembersSidebar() {
    emit(
      state.copyWith(
        membersSidebarOpen: !state.membersSidebarShown,
        membersHiddenForFocus: false,
      ),
    );
  }

  /// A call tile entered or left focus. Hides the member list for the
  /// duration without touching the saved choice.
  void setStageFocused(bool focused) {
    if (focused == state.membersHiddenForFocus) return;
    emit(state.copyWith(membersHiddenForFocus: focused));
  }

  void setOutputDeviceId(String? deviceId) {
    emit(
      state.copyWith(
        outputDeviceId: deviceId,
        clearOutputDeviceId: deviceId == null,
      ),
    );
  }

  void setInputDeviceId(String? deviceId) {
    emit(
      state.copyWith(
        inputDeviceId: deviceId,
        clearInputDeviceId: deviceId == null,
      ),
    );
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

  // ── Persisted: the soundboard, as this device hears it ───
  // Neither of these asks a server anything. Everybody in a call plays a
  // clip out of their own speakers, so how loud it is here is settled here.

  void setSoundboardMuted(bool muted) =>
      emit(state.copyWith(soundboardMuted: muted));

  /// One person's soundboard, off or back on — their **voice untouched**.
  ///
  /// Three settings per person share [participantSettings] under three keys,
  /// and this is the one that is easy to write by mistake: somebody whose
  /// airhorn is too loud has not said anything wrong, and muting them for
  /// it would be the wrong answer to the only complaint anybody has. Named
  /// rather than left to callers spelling the key themselves, which is how
  /// two of them came to write the voice one instead.
  void setSoundboardMutedFor(String userId, bool muted) =>
      setParticipantSetting(
        ParticipantIdentity.soundboardSettingsKey(userId),
        muted: muted,
      );

  void setSoundboardVolume(double volume) =>
      emit(state.copyWith(soundboardVolume: volume.clamp(0.0, 1.0)));

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
