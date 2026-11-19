part of 'screenshare_cubit.dart';

/// A running desktop share switched to another screen or window, on the same
/// connection, so those watching keep watching (`switch_screenshare`).
mixin _ScreenshareSwitchMixin on Cubit<ScreenshareState> {
  /// A switch is on its way. A second waits for nothing: Rust takes them one
  /// at a time, and the menu that asked has closed.
  bool _switching = false;

  /// Switches the running share to the source picked in [settings], keeping
  /// its quality. [portalChoice] is a window already picked in the desktop's
  /// own picker, as for a start. The sound is ticked as it came out: a window
  /// on Windows brings its own app's, which may play nothing.
  ///
  /// On Linux the sound is the running share's unless [soundPicked]: a window
  /// whose sound was asked for (`WindowSoundStep`) brings what was picked,
  /// and anything else keeps what the share plays. The dialog's own draft
  /// holds the saved settings' sound, which is not the share's.
  ///
  /// A switch that fails leaves the share as it was on Linux, where the old
  /// capture runs until the new one has a picture; on Windows the old one is
  /// already gone, and Rust ends the share (`SourceClosed`).
  Future<void> switchSource({
    required ScreenShareSettings settings,
    String? portalChoice,
    bool soundPicked = false,
  }) async {
    final current = state.settings;
    if (!state.isSharing ||
        current == null ||
        ScreenshareCubit._sdkCapturesScreen ||
        _switching) {
      return;
    }
    _switching = true;
    if (!soundPicked) {
      settings = settings.copyWith(
        clearAudioSource: true,
      ).copyWith(selectedAudioSource: current.selectedAudioSource);
    }
    try {
      final soundOn = await switchScreenshare(
        source: ShareSource(
          captureFullScreen: settings.captureFullScreen,
          selectedVideoSourceIndex: settings.selectedVideoSourceIndex,
          portalChoice: portalChoice,
          selectedAudioSource: settings.selectedAudioSource,
          selectedAudioSourcePid: settings.selectedVideoSourcePid,
        ),
      );
      if (!state.isSharing) return;
      final now = current.withSourceOf(settings).copyWith(shareAudio: soundOn);
      emit(
        state.copyWith(
          settings: now,
          notice: Notice.success(
            'Now sharing',
            now.captureFullScreen
                ? 'Your screen'
                : now.selectedVideoSourceTitle ?? 'A window',
          ),
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('✗ Screen share switch error: $e');
      // Stopped while it waited on the desktop's picker: nothing to say.
      if (!state.isSharing) return;
      emit(
        state.copyWith(
          notice: Notice.error(
            'Could not switch the stream: $e',
            duration: Notice.long,
          ),
        ),
      );
    } finally {
      _switching = false;
    }
  }
}
