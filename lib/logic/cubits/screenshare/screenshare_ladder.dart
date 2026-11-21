part of 'screenshare_cubit.dart';

/// A running desktop share staying something its watchers can play: it moves
/// down the [ShareLadder] for a watcher who needs it, and back up once nobody
/// does ([ShareRungFollow]). Moving republishes the picture, as a codec picked
/// from the menu does, so viewers see it blink and stay subscribed. A phone's
/// or browser's share has no such knob, and every viewer plays what it sends.
mixin _ScreenshareLadderMixin on Cubit<ScreenshareState> {
  /// Who is watching this share now, as `LiveKitCubit` last said.
  List<ShareWatcher> _watchers = const [];

  /// A change to the running share is on its way to Rust: a rung move, or
  /// one from the menu ([ScreenshareCubit.changeQuality]). While it is, the
  /// ladder holds still, and it looks again once the change is through.
  bool _changingShare = false;

  /// The last change to the running share, which the next waits for. Each
  /// sends the whole of the share's settings, so two at once sent the older
  /// ones last: a watcher arriving while the sound was turned off put it
  /// back on, under a menu that said it was off.
  Future<void> _lastChange = Future.value();

  /// Runs [change] once every change before it is through, holding the
  /// ladder meanwhile. [change] reads the share's settings when it runs, not
  /// when it was asked for.
  Future<T> _oneChangeAtATime<T>(Future<T> Function() change) {
    final run = _lastChange.then((_) async {
      _changingShare = true;
      try {
        return await change();
      } finally {
        _changingShare = false;
      }
    });
    _lastChange = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  late final ShareRungFollow _rungFollow = ShareRungFollow(
    onMove: (rung) => unawaited(_moveToRung(rung)),
  );

  /// The call's connections changed: [watchers] are watching this share.
  void followWatchers(List<ShareWatcher> watchers) {
    _watchers = watchers;
    _followRung();
  }

  /// Puts the share where its watchers need it, or sets that going.
  void _followRung() {
    final top = state.topCodec;
    final current = state.codec;
    if (!state.isSharing || _changingShare || top == null || current == null) {
      return;
    }
    _rungFollow.update(top: top, current: current, watchers: _watchers);
  }

  Future<void> _moveToRung(VideoCodec rung) async {
    // Another change is through first, and looks again for itself.
    if (_changingShare) return;
    final moved = await _oneChangeAtATime(() => _moveNowToRung(rung));
    // Whatever changed while it moved.
    if (moved) _followRung();
  }

  /// Whether the share is still up to follow its watchers.
  Future<bool> _moveNowToRung(VideoCodec rung) async {
    final settings = state.settings;
    final from = state.codec;
    if (!state.isSharing || settings == null || from == null) return false;
    if (rung == from) return true;
    try {
      final applied = await updateScreenshare(
        quality: ShareQuality(
          resolution: settings.resolution,
          fps: settings.fps,
          // Auto's bitrate follows the codec; one picked by hand stays.
          bitrate: settings.bitrateToSend(
            codec: rung,
            limits: state.limits,
            h264High: HostPlatform.encodesH264OnGpuOnly,
          ),
          codec: rung,
          shareAudio: settings.shareAudio && HostPlatform.capturesSystemAudio,
        ),
      );
      if (!state.isSharing) return false;
      emit(state.copyWith(codec: applied.codec));
      // Otherwise it fell back, which says so itself.
      if (applied.codec != rung) return true;
      emit(
        state.copyWith(
          notice: ShareLadder.isBelow(rung, from)
              ? _steppedDownNotice(rung)
              : Notice.info(
                  'Sharing as ${ScreenShareSettings.nameOf(rung)} again',
                  'Everyone watching can play it.',
                ),
        ),
      );
      return true;
    } catch (e) {
      // Rust ends a share whose picture it could not put back, and says so.
      HelperMethods.printDebug('✗ Moving the share to ${rung.name}: $e');
      return false;
    }
  }

  /// The note for a share held at [rung] by those watching.
  Notice _steppedDownNotice(VideoCodec rung) => Notice.info(
    'Sharing as ${ScreenShareSettings.nameOf(rung)}',
    'So ${ShareLadder.whoFor(ShareLadder.holdingAt(rung, _watchers))} can watch.',
  );
}
