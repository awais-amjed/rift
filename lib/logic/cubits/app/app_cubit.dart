import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:equatable/equatable.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/classes/call_shortcuts.dart';
import '../../../data/classes/key_shortcut.dart';
import '../../../data/classes/participant_info.dart';
import '../../../data/classes/participant_setting.dart';
import '../../../data/classes/screen_share_settings.dart';
import '../../../data/classes/seen_key.dart';
import '../../../data/constants.dart';
import '../../../data/enums/app_sound.dart';
import '../../../data/enums/home_surface.dart';
import '../../../data/enums/noise_suppression.dart';
import '../../../data/enums/sensitive_content_mode.dart';
import '../../../data/participant_identity.dart';
import '../../services/call_volume.dart';
import '../../services/hydrated_keys.dart';
import '../../services/login_launch/login_launch.dart';
import '../../services/mic_volume.dart';
import '../../services/noise_filter.dart';

part 'app_cubit.g.dart';
part 'app_state.dart';

/// This device's layout and preferences: which pane is open, which channel is
/// selected, audio and share settings, per-person volumes. Persisted, and never
/// sent anywhere.
class AppCubit extends HydratedCubit<AppState> {
  AppCubit() : super(const AppState()) {
    // The filter lives in the native audio pipeline, which starts with none.
    unawaited(NoiseFilter.use(state.noiseSuppression));
    MicVolume.apply(state.inputVolume);
  }

  /// A fixed name, not the class's: see [HydratedKeys].
  @override
  String get storagePrefix => HydratedKeys.app;

  // ── Persisted: sidebar ───────────────────────────────────

  void toggleSidebar() {
    emit(state.copyWith(sidebarOpen: !state.sidebarOpen));
  }

  /// The half of the selected server last on screen — its channels or its
  /// DMs. Home is a detour from a server, not a way out of it, so coming back
  /// finds the server as it was left; going straight to its channels lost a
  /// DM the person was in the middle of.
  HomeSurface _serverSurface = HomeSurface.server;

  /// Switch the centre pane. Mutually exclusive by construction — there is
  /// no state where two surfaces are open.
  void setSurface(HomeSurface surface) {
    if (surface != HomeSurface.centralDms) _serverSurface = surface;
    emit(state.copyWith(surface: surface));
  }

  /// Back to the selected server from wherever the centre pane is, on the
  /// half of it that was open last.
  void backToServer() => setSurface(_serverSurface);

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

  /// Binds [action] to [keys], or unbinds it with null.
  void setCallShortcut(CallShortcut action, KeyShortcut? keys) {
    emit(
      state.copyWith(callShortcuts: state.callShortcuts.withKeys(action, keys)),
    );
  }

  /// What the desktop says the push-to-talk key is, or null once no desktop
  /// shortcut is bound.
  void setDesktopPushToTalkPending(bool pending) {
    if (pending == state.desktopPushToTalkPending) return;
    emit(state.copyWith(desktopPushToTalkPending: pending));
  }

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

  void setShowOfflineChip(bool value) =>
      emit(state.copyWith(showOfflineChip: value));

  void setBetaUpdates(bool value) => emit(state.copyWith(betaUpdates: value));

  void setAddToAppMenu(bool value) => emit(state.copyWith(addToAppMenu: value));

  // ── Persisted: starting at sign-in ───────────────────────

  bool get launchesAtLogin => state.launchAtLogin ?? LoginLaunch.onByDefault;

  void setLaunchAtLogin(bool value) {
    emit(state.copyWith(launchAtLogin: value));
    unawaited(applyLoginLaunch());
  }

  void setStartMinimized(bool value) {
    emit(state.copyWith(startMinimized: value));
    unawaited(applyLoginLaunch());
  }

  /// Puts the computer's sign-in entry in line with these settings. Also run
  /// at every start, so the entry follows the program if it moves.
  Future<void> applyLoginLaunch() => LoginLaunch.apply(
    enabled: launchesAtLogin,
    minimized: state.startMinimized,
  );

  // ── Persisted: switching voice channels ──────────────────

  void setAskBeforeVoiceSwitch(bool value) =>
      emit(state.copyWith(askBeforeVoiceSwitch: value));

  // ── Persisted: Windows ducking ───────────────────────────

  void setShowDuckingHint(bool value) =>
      emit(state.copyWith(showDuckingHint: value));

  // ── Audio processing (mic capture) ───────────────────────
  // The LiveKitCubit watches AppState and re-publishes the mic track when any
  // of these change, so a toggle takes effect mid-call.

  void setNoiseSuppression(NoiseSuppression value) {
    unawaited(NoiseFilter.use(value));
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

  /// Where the user left the line between a DM call and its messages.
  void setDmCallStageShare(double share) {
    if (!share.isFinite || share == state.dmCallStageShare) return;
    emit(state.copyWith(dmCallStageShare: share));
  }

  /// Give a DM call the whole conversation pane, or put the split back.
  /// [chatOpen] says whether its messages come along beside it — yes when
  /// somebody asked for more room, no when a stream asked for it.
  void setDmCallExpanded(bool expanded, {bool chatOpen = true}) {
    if (expanded == state.dmCallExpanded &&
        (!expanded || chatOpen == state.dmCallChatOpen)) {
      return;
    }
    emit(state.copyWith(dmCallExpanded: expanded, dmCallChatOpen: chatOpen));
  }

  void toggleDmCallChat() =>
      emit(state.copyWith(dmCallChatOpen: !state.dmCallChatOpen));

  /// A focused call's controls faded out, or came back.
  void setStageChromeHidden(bool hidden) {
    if (hidden == state.stageChromeHidden) return;
    emit(state.copyWith(stageChromeHidden: hidden));
  }

  void setOutputDeviceId(String? deviceId) {
    emit(
      state.copyWith(
        outputDeviceId: deviceId,
        clearOutputDeviceId: deviceId == null,
      ),
    );
  }

  /// See [AppState.outputVolume]. The LiveKitCubit puts it on every track.
  void setOutputVolume(double volume) =>
      emit(state.copyWith(outputVolume: volume.clamp(0.0, CallVolume.max)));

  /// See [AppState.inputVolume]. Applied at once, mid-call and mid-test.
  void setInputVolume(double volume) {
    final clamped = volume.clamp(0.0, MicVolume.max);
    MicVolume.apply(clamped);
    emit(state.copyWith(inputVolume: clamped));
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
    final existing = state.settingFor(userId);
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

  /// How loud one person's soundboard is here — see [setSoundboardMutedFor].
  void setSoundboardVolumeFor(String userId, double volume) =>
      setParticipantSetting(
        ParticipantIdentity.soundboardSettingsKey(userId),
        volume: volume.clamp(0.0, 1.0),
      );

  void setSoundboardVolume(double volume) =>
      emit(state.copyWith(soundboardVolume: volume.clamp(0.0, 1.0)));

  // ── Persisted: Rift's own sounds ─────────────────────────

  void setSoundMuted(AppSound sound, bool muted) =>
      _setSound(sound, muted: muted);

  void setSoundVolume(AppSound sound, double volume) =>
      _setSound(sound, volume: volume.clamp(0.0, 1.0));

  void _setSound(AppSound sound, {bool? muted, double? volume}) {
    final updated = Map<String, ParticipantSetting>.from(state.appSounds)
      ..[sound.name] = sound
          .settingIn(state.appSounds)
          .copyWith(muted: muted, volume: volume);
    emit(state.copyWith(appSounds: updated));
  }

  // ── Persisted: people whose keys you have checked ────────

  /// Remember that [code] is what you saw when you checked [person] — see
  /// [AppState.verifiedCodes].
  ///
  /// Comparing the codes is also looking at the change, if there was one.
  void setVerified(String person, String code) => emit(
    state.copyWith(
      verifiedCodes: {...state.verifiedCodes, person: code},
      seenKeys: _acknowledged(person),
    ),
  );

  /// Take that back, whether because it was a mistake or because their key
  /// changed and the old answer is worse than none.
  void clearVerified(String person) => emit(
    state.copyWith(
      verifiedCodes: {...state.verifiedCodes}..remove(person),
      seenKeys: _acknowledged(person),
    ),
  );

  /// Record [key] as [person]'s current chat key — see [SeenKey]. Called by
  /// whatever surface is about to seal to it or show it; the same key again
  /// emits nothing.
  void noteChatKey(String person, String key) {
    final before = state.seenKeys[person];
    final after = SeenKey.noting(before, key, DateTime.now());
    if (identical(before, after)) return;
    emit(state.copyWith(seenKeys: {...state.seenKeys, person: after}));
  }

  /// The person has looked at their changed key — the header stops saying so.
  /// The lines in the conversation stay: they are history.
  void acknowledgeKeyChange(String person) {
    if (!(state.seenKeys[person]?.unacknowledgedChange ?? false)) return;
    emit(state.copyWith(seenKeys: _acknowledged(person)));
  }

  Map<String, SeenKey>? _acknowledged(String person) {
    final seen = state.seenKeys[person];
    if (seen == null || !seen.unacknowledgedChange) return null;
    return {...state.seenKeys, person: seen.acknowledge()};
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
