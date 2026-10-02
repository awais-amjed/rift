import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../../data/classes/participant_setting.dart';
import '../../data/enums/app_sound.dart';
import '../../src/rust/api/cue.dart';
import '../helper_methods.dart';
import 'host_platform.dart';

/// Plays Rift's own sounds — a new message, and the call's cues — at the
/// volume each is set to in settings, on the output device chosen there.
///
/// The service manages its own [AudioPlayer] pool so that rapid successive
/// calls never block or cut off a previous sound. The player cannot pick a
/// device on the desktop, so with one chosen, Windows and Linux open it
/// themselves through the Rust library ([_playOnOutput]) and keep the player
/// for when that fails.
class SoundService {
  SoundService._();
  static final SoundService _instance = SoundService._();
  static SoundService get instance => _instance;

  /// The player volume at 100% on a settings slider. Twice what every cue
  /// played at before the sliders existed, so the default sits mid-track
  /// with room to go both ways — see [AppSound.defaultVolume].
  static const _ceiling = 0.3;

  /// How long to wait for a sound to finish before reclaiming its player.
  static const _maxPlaybackWait = Duration(seconds: 10);

  /// The shortest gap between two restarts of a preview. A slider reports
  /// every pixel of a drag, and restarting a tone on each would be a buzz
  /// in which no single tone, and so no volume, can be heard.
  static const _previewGap = Duration(milliseconds: 250);

  /// The shortest gap between two message chimes — see [play].
  static const _messageGap = Duration(seconds: 1);

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  /// Where [play] reads each sound's mute and volume — `AppState.appSounds`,
  /// connected once at startup by [readSettingsFrom].
  ///
  /// A getter rather than a copy, so a change in settings is heard on the
  /// next sound without anything having to tell this service. Until it is
  /// connected every sound plays at its default, which only the push
  /// isolate ever sees, and that plays nothing.
  Map<String, ParticipantSetting> Function() _settings = () => const {};

  /// Connects [play] to the settings — see [_settings].
  void readSettingsFrom(Map<String, ParticipantSetting> Function() settings) =>
      _settings = settings;

  /// Where the sounds go — `AppState.outputDeviceId`, read the same way as
  /// [_settings], so a device picked in settings is used by the next sound.
  String? Function() _outputDevice = () => null;

  /// Connects the sounds to the output picked in settings — see
  /// [_outputDevice].
  void readOutputFrom(String? Function() outputDevice) =>
      _outputDevice = outputDevice;

  /// Plays one side of [sound] — the opening tone, or with [ending] the
  /// closing one — as the settings say: not at all when it is muted, and
  /// otherwise at its share of [_ceiling].
  ///
  /// A burst of messages is one chime, not a run of them: the second of two
  /// arriving inside [_messageGap] says nothing the first did not.
  Future<void> play(AppSound sound, {bool ending = false}) async {
    final setting = sound.settingIn(_settings());
    if (setting.muted || setting.volume <= 0) return;
    if (sound == AppSound.message) {
      final now = DateTime.now();
      if (now.difference(_lastMessage) < _messageGap) return;
      _lastMessage = now;
    }
    await _play(
      ending ? (sound.endAsset ?? sound.startAsset) : sound.startAsset,
      setting.volume * _ceiling,
    );
  }

  DateTime _lastMessage = DateTime.fromMillisecondsSinceEpoch(0);

  /// Plays [sound] at [volume] for somebody choosing it in settings.
  ///
  /// One player, kept, rather than one per call as [play] does: while a tone
  /// is still sounding, a drag only turns it up or down, so the change is
  /// heard *on* the sound rather than as a new one — and a long tone is not
  /// stacked on itself a dozen times by one sweep of the thumb.
  Future<void> preview(AppSound sound, double volume) async {
    final player = _previewPlayer ??= AudioPlayer();
    final gain = volume.clamp(0.0, 1.0) * _ceiling;
    try {
      final cue = _previewCue;
      if (_previewing == sound &&
          cue != null &&
          DateTime.now().isBefore(_previewCueEnds)) {
        await setCueVolume(id: cue, volume: gain);
        return;
      }
      if (_previewing == sound && player.state == PlayerState.playing) {
        await player.setVolume(gain);
        return;
      }
      final now = DateTime.now();
      if (now.difference(_lastPreviewStart) < _previewGap) return;
      _lastPreviewStart = now;
      _previewing = sound;
      await player.stop();
      final previous = _previewCue;
      _previewCue = null;
      if (previous != null) unawaited(stopCue(id: previous));
      final started = await _playOnOutput(sound.startAsset, gain);
      if (started != null) {
        _previewCue = started.id;
        _previewCueEnds = now.add(Duration(milliseconds: started.durationMs));
        return;
      }
      await player.setVolume(gain);
      await player.play(AssetSource(sound.startAsset));
    } catch (e) {
      HelperMethods.printDebug('SoundService: preview failed – $e');
    }
  }

  /// The preview playing on the chosen output, which a drag turns up or down
  /// as [_previewPlayer] would be. Kept after it ends: turning a finished cue
  /// up does nothing, and the next preview replaces it.
  int? _previewCue;

  /// When [_previewCue] runs out — the cue player does not say, and a drag
  /// over a tone still sounding should turn it, not start it again.
  DateTime _previewCueEnds = DateTime.fromMillisecondsSinceEpoch(0);

  AudioPlayer? _previewPlayer;
  AppSound? _previewing;

  /// Plays [sound] over and over until [stopLoop] — a ringtone, which has no
  /// natural end: it stops when somebody answers.
  ///
  /// One looping player at a time, since two rings at once is a device that
  /// is ringing either way. Asking for the one already looping is a no-op,
  /// so a state emitted every second does not restart the tone each time.
  Future<void> loop(AppSound sound) async {
    if (_looping == sound) return;
    await stopLoop();
    final setting = sound.settingIn(_settings());
    if (setting.muted || setting.volume <= 0) return;
    _looping = sound;
    final volume = setting.volume * _ceiling;
    final cue = (await _playOnOutput(
      sound.startAsset,
      volume,
      looping: true,
    ))?.id;
    if (cue != null) {
      // Stopped while the device was opening: the ring outlived its call.
      if (_looping != sound) {
        unawaited(stopCue(id: cue));
      } else {
        _loopCue = cue;
      }
      return;
    }
    final player = _loopPlayer ??= AudioPlayer();
    try {
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(volume);
      await player.play(AssetSource(sound.startAsset));
    } catch (e) {
      HelperMethods.printDebug('SoundService: loop failed – $e');
    }
  }

  /// The ring playing on the chosen output, if [loop] put it there.
  int? _loopCue;

  /// Stops whatever [loop] started. Safe when nothing is looping.
  Future<void> stopLoop() async {
    if (_looping == null) return;
    _looping = null;
    final cue = _loopCue;
    _loopCue = null;
    if (cue != null) unawaited(stopCue(id: cue));
    try {
      await _loopPlayer?.stop();
    } catch (e) {
      HelperMethods.printDebug('SoundService: stop loop failed – $e');
    }
  }

  AudioPlayer? _loopPlayer;
  AppSound? _looping;
  DateTime _lastPreviewStart = DateTime.fromMillisecondsSinceEpoch(0);

  // ──────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────

  /// Plays [asset] on the output chosen in settings — decoded in the Rust
  /// library — and answers the started cue, or null when there is no device to open (none chosen, or not on Windows
  /// or Linux) or it could not be played there, and the caller should use the
  /// player instead. Null rather than silence, because a cue on the wrong
  /// device is better than none.
  Future<CueStarted?> _playOnOutput(
    String asset,
    double volume, {
    bool looping = false,
  }) async {
    if (!HostPlatform.playsCuesOnChosenOutput) return null;
    final device = _outputDevice();
    // WebRTC's own "default: …" entry is the system default, which the
    // player already follows.
    if (device == null || device.isEmpty || device.startsWith('default: ')) {
      return null;
    }
    try {
      return await playCue(
        deviceId: device,
        mp3: await _bytesOf(asset),
        volume: volume,
        looping: looping,
      );
    } catch (e) {
      HelperMethods.printDebug('SoundService: $asset on $device failed – $e');
      return null;
    }
  }

  /// Each sound's file, read once.
  final Map<String, Uint8List> _bytes = {};

  Future<Uint8List> _bytesOf(String asset) async => _bytes[asset] ??=
      (await rootBundle.load('assets/$asset')).buffer.asUint8List();

  Future<void> _play(String asset, double volume) async {
    if (await _playOnOutput(asset, volume) != null) return;
    // A fresh player per sound so simultaneous calls don't interfere — which
    // means every one of them has to be handed back, see [_recycle].
    final player = AudioPlayer();
    try {
      await player.setVolume(volume);
      await player.play(AssetSource(asset));
    } catch (e) {
      HelperMethods.printDebug('SoundService: failed to play $asset – $e');
      await _dispose(player);
      return;
    }
    unawaited(_recycle(player));
  }

  /// Disposes [player] once it finishes, or after [_maxPlaybackWait] if the
  /// completion event never arrives.
  ///
  /// `onPlayerComplete` is declared `Stream<void>` but carries `AudioEvent` at
  /// runtime, so `Future.timeout` on it fails a cast on its own `onTimeout`
  /// callback — which used to throw before the disposal was ever scheduled and
  /// leak a native audio pipeline per sound. Racing a plain delay avoids
  /// touching the future's type at all.
  Future<void> _recycle(AudioPlayer player) async {
    try {
      await Future.any([
        player.onPlayerComplete.first.then<void>((_) {}),
        Future<void>.delayed(_maxPlaybackWait),
      ]);
    } catch (e) {
      HelperMethods.printDebug('SoundService: playback wait failed – $e');
    }
    await _dispose(player);
  }

  Future<void> _dispose(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (e) {
      HelperMethods.printDebug('SoundService: failed to dispose player – $e');
    }
  }
}
