import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;

import '../../../data/classes/notice.dart';
import '../../../data/classes/screen_share_settings.dart';
import '../../../data/classes/server_limits.dart';
import '../../../src/rust/api/screenshare.dart';
import '../../../src/rust/api/screenshare/types.dart';
import '../../helper_methods.dart';
import '../../services/call_foreground_service.dart';
import '../../services/gpu_codecs.dart';
import '../../services/host_platform.dart';
import '../livekit/livekit_cubit.dart';
import '../server/server_cubit.dart';
import 'stream_change_notice.dart';

part 'screenshare_state.dart';

/// Cubit managing screen sharing.
///
/// Two implementations behind one state. On a desktop the capture, encoding
/// and publishing all happen in Rust, against libwebrtc's desktop capturer.
/// On web and on a phone the SDK does it: the browser has its own picker, and
/// Android has MediaProjection, which libwebrtc does not expose a desktop
/// capturer for at all — [_sdkCapturesScreen] is which of the two applies.
class ScreenshareCubit extends Cubit<ScreenshareState> {
  /// Whether the LiveKit SDK captures the screen here, rather than Rust.
  static bool get _sdkCapturesScreen => kIsWeb || HostPlatform.isMobile;

  final ServerCubit _serverCubit;
  final LiveKitCubit? _livekitCubit;

  StreamSubscription<ScreenshareEvent>? _eventSub;

  ScreenshareCubit({
    required ServerCubit serverCubit,
    LiveKitCubit? livekitCubit,
  }) : _serverCubit = serverCubit,
       _livekitCubit = livekitCubit,
       super(const ScreenshareState()) {
    // Desktop screen sharing runs in Rust; listen for its lifecycle events
    // (e.g. the shared window being closed) so we can stop and update the UI.
    // Nothing to listen to where the SDK is doing the capturing.
    if (!_sdkCapturesScreen) {
      _eventSub = screenshareEventStream().listen(_onRustScreenshareEvent);
    }
  }

  /// Record a failure *and* say it out loud.
  ///
  /// Every refusal here used to be emitted into [ScreenshareState.error] and
  /// nothing ever read it — no listener, no widget, not even `hasError`. So
  /// pressing Start sharing and having it fail showed nothing at all: the
  /// control went back to not-sharing and the reason, which is usually
  /// actionable ("this call's encryption key is not ready", "no frames
  /// arrived from the selected source in 10 seconds"), stayed in a field.
  /// The notice beside it is what says it: `NoticeListeners` shows it.
  void _fail(String message) {
    emit(
      state.copyWith(
        status: ScreenshareStatus.error,
        error: message,
        notice: Notice.error(message, duration: Notice.long),
      ),
    );
  }

  void _onRustScreenshareEvent(ScreenshareEvent event) {
    switch (event) {
      case ScreenshareEvent.sourceClosed:
        if (state.status == ScreenshareStatus.sharing) {
          // The captured window was closed — tear the session down and
          // reset UI.
          stopScreenShare();
        }
      case ScreenshareEvent.encoderFellBack:
        // The share is still up; only how it is encoded changed.
        if (state.isSharing) emit(state.copyWith(codec: VideoCodec.vp9));
        emit(
          state.copyWith(
            notice: Notice.info(
              'Sharing as VP9',
              'Your graphics card could not encode H264 this time.',
            ),
          ),
        );
    }
  }

  /// Starts screen sharing with the given settings.
  Future<void> startScreenShare({required ScreenShareSettings settings}) async {
    emit(state.copyWith(status: ScreenshareStatus.connecting));

    try {
      // Hand to the SDK wherever it can do the job itself. On web the browser
      // owns the picker; on a phone LiveKit drives MediaProjection, which is
      // the only way in — the Rust pipeline below captures a *desktop*, and
      // libwebrtc does not build its capturer for Android at all.
      if (_sdkCapturesScreen) {
        if (_livekitCubit == null) {
          _fail('LiveKit cubit not available');
          return;
        }

        final channelId = _livekitCubit.state.callKey;
        if (channelId == null) {
          _fail('Not in a call');
          return;
        }

        // Android wants consent, and then a foreground service declaring
        // mediaProjection running *before* the capture starts. A refusal at
        // the consent sheet is the user saying no, which needs no error of
        // ours on top of it.
        if (HostPlatform.isMobile) {
          if (!await Helper.requestCapturePermission() ||
              !await CallForegroundService.screenShareStarting()) {
            emit(state.copyWith(status: ScreenshareStatus.idle));
            return;
          }
        }

        await _livekitCubit.toggleScreenShare();

        emit(
          state.copyWith(
            status: ScreenshareStatus.sharing,
            channelId: channelId,
            settings: settings,
          ),
        );
        await _endIfCallGone(channelId);
        return;
      }

      // Resolve server context
      final server = _serverCubit.state.selectedServer;
      if (server == null) {
        _fail('No server selected');
        return;
      }

      final user = server.user;
      if (user == null) {
        _fail('No user info available');
        return;
      }

      final livekit = _livekitCubit;
      final channelId = livekit?.state.callKey;
      if (livekit == null || channelId == null) {
        _fail('Not in a call');
        return;
      }

      // On desktop, delegate to the Rust LiveKit implementation, with a
      // screenshare-specific token from whichever mint the call came from —
      // a channel's, or a DM call's.
      final response = await livekit.shareToken(screenShare: true);

      if (!response.success) {
        _fail(response.error ?? 'Failed to get channel token');
        return;
      }

      // The token carries the identity, including the per-device segment
      // that keeps the base and screenshare connections paired.
      final livekitToken = response.data['token'] as String;

      // And where to take it. A share is a second connection into the call's
      // own room, so it has to land on the same LiveKit the call did — which
      // is the mint's answer, not the server row, once a channel can sit on a
      // node of its own.
      final livekitUrl =
          response.data['livekit_url'] as String? ?? server.livekitUrl;
      if (livekitUrl == null) {
        _fail('No LiveKit URL configured');
        return;
      }

      // And the operator's budget for a share, which rides along with the
      // token so a change takes effect on the next share rather than the
      // next sync. A share goes out at full rate to every
      // watcher with nothing downscaling in between, so this is the only
      // thing standing between one person's quality setting and the
      // server's uplink.
      //
      // Kept here rather than enforced at the server because there is
      // nowhere to enforce it: a LiveKit join token has no bitrate field,
      // and nothing server-side throttles a publisher afterwards. So this
      // clamp is the whole of it, deliberately — the case it exists for is
      // somebody left on the 10 Mbps default, not somebody patching the app.
      final allowed = ServerLimits.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      final codec = settings.codecToSend(
        gpuOnlyH264: HostPlatform.encodesH264OnGpuOnly,
        gpu: await GpuCodecs.supported,
      );
      final bitrate = settings.bitrateToSend(codec: codec, limits: allowed);
      // The running share holds the rate it actually goes out at, so its menu
      // ticks that; the dialog's saved choice keeps a 120 the picture is too
      // big for, for when it is not.
      final fps = settings.fpsToSend;

      // The call's key, for the second connection this is about to open into
      // the same encrypted room.
      final encryption = _livekitCubit?.callEncryption;
      if (encryption == null) {
        _fail(
          'Cannot share yet — this call’s encryption key is not ready. '
          'Rejoining the channel usually clears it.',
        );
        return;
      }

      final config = ScreenShareConfig(
        livekitUrl: livekitUrl,
        livekitToken: livekitToken,
        resolution: settings.resolution,
        fps: fps,
        bitrate: bitrate,
        // A hidden toggle keeps whatever it was last set to, so the platform
        // decides here rather than in the settings.
        shareAudio: settings.shareAudio && HostPlatform.capturesSystemAudio,
        captureFullScreen: settings.captureFullScreen,
        selectedVideoSourceIndex: settings.selectedVideoSourceIndex,
        codec: codec,
        priority: settings.priority,
        selectedAudioSourceIndex: settings.selectedAudioSource?.index,
        selectedAudioSourceSink: settings.selectedAudioSource?.sink,
        selectedAudioSourcePid: settings.selectedVideoSourcePid,
        // The same key the call itself uses. Without it the Rust side refuses
        // to connect, which is the right way round: a screen share that fails
        // is a bug report, a screen share the server can watch is not.
        e2EeKey: encryption.key,
        e2EeKeyIndex: encryption.index,
      );

      final result = await startScreenshare(config: config);
      HelperMethods.printDebug('✓ Rust connection result: $result');

      emit(
        state.copyWith(
          status: ScreenshareStatus.sharing,
          channelId: channelId,
          settings: settings.copyWith(fps: fps),
          codec: codec,
          limits: allowed,
        ),
      );
      await _endIfCallGone(channelId);
    } catch (e) {
      HelperMethods.printDebug('✗ Screen share error: $e');
      _fail('Failed to start screen share: $e');
    }
  }

  /// Whether a running share's quality can be changed without stopping it:
  /// on a desktop, where Rust captures. The SDK's capture has no such knob.
  static bool get changesQualityLive => !_sdkCapturesScreen;

  /// Changes the running share's frame rate, height or sound in place, and
  /// returns the settings now in effect — null if nothing changed.
  ///
  /// Sound is reported as it came out, not as it was asked for: an
  /// application that stopped playing has nothing to capture, and a menu
  /// ticked for sound nobody hears is the wrong menu. The sharer is told the
  /// change went through ([streamChangeNotice]): the viewers' picture
  /// blinking is the only other sign of it.
  Future<ScreenShareSettings?> changeQuality({
    int? fps,
    int? resolution,
    bool? shareAudio,
  }) async {
    final current = state.settings;
    if (!state.isSharing || current == null || !changesQualityLive) {
      return null;
    }
    final asked = current.copyWith(
      fps: fps,
      resolution: resolution,
      shareAudio: shareAudio,
    );
    // A picture too big for 120 fps takes 60 with it.
    final wanted = asked.copyWith(fps: asked.fpsToSend);
    try {
      final applied = await updateScreenshare(
        quality: ShareQuality(
          resolution: wanted.resolution,
          fps: wanted.fps,
          // Auto's bitrate follows the picture, so a bigger or faster one
          // is given more.
          bitrate: wanted.bitrateToSend(
            codec: state.codec ?? wanted.videoCodec,
            limits: state.limits,
          ),
          shareAudio: wanted.shareAudio && HostPlatform.capturesSystemAudio,
        ),
      );
      if (!state.isSharing) return null;
      final now = wanted.copyWith(shareAudio: applied.shareAudio);
      emit(state.copyWith(settings: now));
      if (wanted.shareAudio && !applied.shareAudio) {
        emit(
          state.copyWith(
            notice: Notice.error(
              'Could not share this stream’s sound.',
              duration: Notice.long,
            ),
          ),
        );
      } else {
        final notice = streamChangeNotice(
          now: now,
          fpsChanged: fps != null,
          fpsLowered: fps == null && now.fps < current.fps,
          soundChanged: shareAudio != null,
        );
        emit(
          state.copyWith(
            notice: Notice.success(notice.title, notice.description),
          ),
        );
      }
      return now;
    } catch (e) {
      HelperMethods.printDebug('✗ Screen share change error: $e');
      emit(
        state.copyWith(
          notice: Notice.error(
            'Could not change the stream: $e',
            duration: Notice.long,
          ),
        ),
      );
      return null;
    }
  }

  /// Stops screen sharing.
  Future<void> stopScreenShare() async {
    if (state.status != ScreenshareStatus.sharing) return;

    emit(state.copyWith(status: ScreenshareStatus.stopping));

    try {
      // Hand to the SDK wherever it can do the job itself. On web the browser
      // owns the picker; on a phone LiveKit drives MediaProjection, which is
      // the only way in — the Rust pipeline below captures a *desktop*, and
      // libwebrtc does not build its capturer for Android at all.
      if (_sdkCapturesScreen) {
        if (_livekitCubit != null) {
          await _livekitCubit.toggleScreenShare();
        }
        // The capture has stopped, so the service drops back to the plain
        // call type — the call is still running and still needs holding up.
        await CallForegroundService.screenShareStopped();

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

      // On desktop, use the Rust implementation.
      HelperMethods.printDebug('Stopping screenshare...');
      final result = await stopScreenshare();
      HelperMethods.printDebug('✓ Rust disconnect result: $result');

      emit(
        state.copyWith(
          status: ScreenshareStatus.idle,
          clearChannelId: true,
          clearSettings: true,
          clearError: true,
        ),
      );
    } catch (e) {
      HelperMethods.printDebug('✗ Stop screenshare error: $e');
      _fail('Failed to stop screen share: $e');
    }
  }

  /// Keeps this device's share with its call, which has just connected.
  ///
  /// A region change and a rejoin after the connection gave out both put the
  /// call in a new room, and the share is a connection of its own that none
  /// of that touched — it went on streaming into the room everybody had left.
  /// On a desktop it is moved after them, capture and all, so a Wayland
  /// portal is not asked again. Where the SDK shares the screen the share was
  /// a track on the old room and went with it; a browser starts a share only
  /// from a click, and Android only with fresh consent, so the sharer is told
  /// to start it again.
  ///
  /// A share in any other call ends: it belongs to the call it was started
  /// in. So does one whose call failed to come back, or it streams on to a
  /// room the sharer is not in.
  Future<void> followCall() async {
    if (!state.isSharing) return;
    final livekit = _livekitCubit;
    if (livekit == null) return;
    final gone = _callGone(state.channelId);
    if (_sdkCapturesScreen) return _forgetSdkShare(tell: !gone);
    if (gone) return stopScreenShare();
    // Joining the same call again, which may yet fail: whichever way it
    // ends brings this back here.
    if (livekit.state.connectionState != LiveKitConnectionState.connected) {
      return;
    }

    final response = await livekit.shareToken(screenShare: true);
    final livekitUrl =
        response.data?['livekit_url'] as String? ??
        _serverCubit.state.selectedServer?.livekitUrl;
    final encryption = livekit.callEncryption;
    if (!response.success || livekitUrl == null || encryption == null) {
      return _endUnmoved(response.error ?? 'the call is not ready');
    }
    try {
      await moveScreenshare(
        room: ShareRoom(
          livekitUrl: livekitUrl,
          livekitToken: response.data['token'] as String,
          e2EeKey: encryption.key,
          e2EeKeyIndex: encryption.index,
        ),
      );
    } catch (e) {
      await _endUnmoved('$e');
    }
  }

  /// Whether the call [channelId] names is over for this device — it is in
  /// another call or none, or its join failed — so a share of it must not
  /// go on.
  bool _callGone(String? channelId) {
    final call = _livekitCubit?.state;
    return call == null || call.callKey != channelId || call.isCallOver;
  }

  /// Ends a share that has just come up for a call that ended while it was
  /// starting — the capture, the token and the connect take seconds, and
  /// nothing else is listening for that call any more.
  Future<void> _endIfCallGone(String channelId) async {
    if (!state.isSharing || !_callGone(channelId)) return;
    if (_sdkCapturesScreen) return _forgetSdkShare(tell: false);
    await stopScreenShare();
  }

  /// A share that could not follow its call: stop it rather than leave it
  /// streaming to a room nobody is in, and say why the stream ended.
  Future<void> _endUnmoved(String reason) async {
    HelperMethods.printDebug(
      '✗ Screen share could not follow the call: $reason',
    );
    await stopScreenShare();
    emit(
      state.copyWith(
        notice: Notice.error(
          'Your stream stopped when the call reconnected. Share again to '
          'carry on.',
          duration: Notice.long,
        ),
      ),
    );
  }

  /// The SDK's share went with the room it was published in, so there is
  /// nothing to stop — [stopScreenShare] would toggle the new room's share
  /// *on*. Only the state and the foreground service are put back.
  Future<void> _forgetSdkShare({required bool tell}) async {
    await CallForegroundService.screenShareStopped();
    emit(
      state.copyWith(
        status: ScreenshareStatus.idle,
        clearChannelId: true,
        clearSettings: true,
        clearError: true,
      ),
    );
    if (tell) {
      emit(
        state.copyWith(
          notice: Notice.info(
            'Your stream stopped',
            'The call reconnected. Share again to carry on.',
          ),
        ),
      );
    }
  }

  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() async {
    await _eventSub?.cancel();
    return super.close();
  }
}
