import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/screenshare/screenshare_cubit.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';
import 'package:rift/src/rust/frb_generated.dart';

/// Rust's side of a share, as far as these tests ask: a start fails with
/// [startError] or waits on [holdStart], and the calls are counted.
class _Rust implements RustLibApi {
  Object? startError;
  Completer<String>? holdStart;
  int starts = 0;
  int stops = 0;

  /// A switch fails with [switchError] or waits on [holdSwitch], and
  /// answers [switchSound] for whether the sound goes on.
  Object? switchError;
  Completer<bool>? holdSwitch;
  bool switchSound = true;
  ShareSource? switchedTo;
  int switches = 0;

  @override
  Stream<ScreenshareEvent> crateApiScreenshareScreenshareEventStream() =>
      const Stream.empty();

  @override
  Future<List<VideoCodec>> crateApiScreenshareGpuVideoCodecs() async => [];

  @override
  Future<String> crateApiScreenshareStartScreenshare({
    required ScreenShareConfig config,
  }) async {
    starts++;
    if (startError != null) throw startError!;
    return holdStart == null ? 'started' : holdStart!.future;
  }

  @override
  Future<bool> crateApiScreenshareSwitchScreenshare({
    required ShareSource source,
  }) async {
    switches++;
    switchedTo = source;
    if (switchError != null) throw switchError!;
    return holdSwitch == null ? switchSound : holdSwitch!.future;
  }

  @override
  Future<String> crateApiScreenshareStopScreenshare() async {
    stops++;
    return 'stopped';
  }

  /// Changes to the running share, as sent; each waits on [holdUpdate].
  final List<ShareQuality> updates = [];
  Completer<void>? holdUpdate;

  @override
  Future<ShareQuality> crateApiScreenshareUpdateScreenshare({
    required ShareQuality quality,
  }) async {
    updates.add(quality);
    final hold = holdUpdate;
    if (hold != null) {
      holdUpdate = null;
      await hold.future;
    }
    return quality;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A call the share can belong to.
class _Call implements LiveKitCubit {
  static const inCall = LiveKitState(
    currentChannelId: 'voice',
    connectionState: LiveKitConnectionState.connected,
  );

  LiveKitState callState = inCall;

  @override
  LiveKitState get state => callState;

  @override
  Server? get callServer => Server(
    id: 'server',
    name: 'Server',
    supabaseUrl: 'http://server',
    token: 'token',
    user: const ServerUser(
      id: 'me',
      username: 'me',
      displayName: 'Me',
      permissions: UserPermissions(),
    ),
  );

  @override
  ({Uint8List key, int index})? get callEncryption =>
      (key: Uint8List(32), index: 0);

  @override
  Future<APIResponse> shareToken({
    bool screenShare = false,
    bool soundShare = false,
    bool watch = false,
  }) async => APIResponse(
    success: true,
    data: const {'token': 'share', 'livekit_url': 'ws://server'},
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final rust = _Rust();

  setUpAll(() => RustLib.initMock(api: rust));

  setUp(() {
    rust
      ..startError = null
      ..holdStart = null
      ..starts = 0
      ..stops = 0
      ..switchError = null
      ..holdSwitch = null
      ..switchSound = true
      ..switchedTo = null
      ..switches = 0
      ..updates.clear()
      ..holdUpdate = null;
  });

  late _Call call;

  ScreenshareCubit newCubit() {
    call = _Call();
    final cubit = ScreenshareCubit(livekitCubit: call);
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> start(ScreenshareCubit cubit) => cubit.startScreenShare(
    settings: const ScreenShareSettings(),
    gpuCapture: true,
  );

  group('a second Share press', () {
    test('gives up the attempt still waiting on the desktop', () {
      final cubit = newCubit();
      final first = cubit.beginAttempt()!;
      final second = cubit.beginAttempt()!;
      expect(first.abandoned, isTrue);
      expect(second.abandoned, isFalse);
    });

    test('tells whoever is waiting on the given-up attempt', () async {
      final cubit = newCubit();
      final first = cubit.beginAttempt()!;
      cubit.beginAttempt();
      await first.whenAbandoned;
    });

    test('starts nothing while a share is connecting', () async {
      final cubit = newCubit();
      rust.holdStart = Completer();
      final first = start(cubit);
      await pumpEventQueue();
      expect(cubit.state.isConnecting, isTrue);
      expect(cubit.beginAttempt(), isNull);
      rust.holdStart!.complete('started');
      await first;
    });

    test('starts nothing while a share runs', () async {
      final cubit = newCubit();
      await start(cubit);
      expect(cubit.state.isSharing, isTrue);
      expect(cubit.beginAttempt(), isNull);
    });

    test('can start again after a failed start', () async {
      final cubit = newCubit();
      rust.startError = 'No frames arrived';
      await start(cubit);
      expect(cubit.state.hasError, isTrue);
      expect(cubit.beginAttempt(), isNotNull);
    });
  });

  group('a start that comes late', () {
    // Dave's log, Nov 5: a sound dialog left open over a live share. Its
    // Start sharing marked the share failed while Rust went on sending, so
    // the bar offered Share screen and nothing could stop it.
    test('leaves the running share alone', () async {
      final cubit = newCubit();
      await start(cubit);
      await start(cubit);
      expect(rust.starts, 1);
      expect(cubit.state.isSharing, isTrue);
    });
  });

  group('Rust already sharing what the app thought was not', () {
    test('shows the share as running, so it can be stopped', () async {
      final cubit = newCubit();
      rust.startError = 'Already sharing screen';
      await start(cubit);
      expect(cubit.state.isSharing, isTrue);
      expect(cubit.state.notice, isNotNull);
      await cubit.stopScreenShare();
      expect(rust.stops, 1);
      expect(cubit.state.isSharing, isFalse);
    });

    test('any other failure is still a failure', () async {
      final cubit = newCubit();
      rust.startError = 'No frames arrived';
      await start(cubit);
      expect(cubit.state.hasError, isTrue);
      expect(cubit.state.isSharing, isFalse);
    });
  });

  group('a desktop picker closed without a choice', () {
    // Rust's words for it (`capture_pw::open`): the person chose nothing,
    // and knows it.
    const closed = "The desktop's picker was closed without a choice";

    test('is no failed start', () async {
      final cubit = newCubit();
      rust.startError = closed;
      await start(cubit);
      expect(cubit.state.hasError, isFalse);
      expect(cubit.state.status, ScreenshareStatus.idle);
      expect(cubit.state.notice, isNull);
      expect(cubit.beginAttempt(), isNotNull);
    });

    test('says nothing at a switch', () async {
      final cubit = newCubit();
      await start(cubit);
      final before = cubit.state.notice;
      rust.switchError = closed;
      await cubit.switchSource(
        settings: const ScreenShareSettings(captureFullScreen: true),
      );
      expect(cubit.state.isSharing, isTrue);
      expect(cubit.state.notice, before);
    });
  });

  group('switching what is shared', () {
    const window = ScreenShareSettings(
      shareAudio: true,
      captureFullScreen: false,
      selectedVideoSourceIndex: 0,
      selectedVideoSourcePid: 5,
      selectedVideoSourceTitle: 'Game',
    );
    const screen = ScreenShareSettings(
      captureFullScreen: true,
      selectedVideoSourceIndex: 1,
      selectedVideoSourceTitle: 'Screen 2',
    );
    const otherWindow = ScreenShareSettings(
      captureFullScreen: false,
      selectedVideoSourceIndex: 3,
      selectedVideoSourcePid: 42,
      selectedVideoSourceTitle: 'Browser',
    );

    Future<ScreenshareCubit> sharing() async {
      final cubit = newCubit();
      await cubit.startScreenShare(settings: window, gpuCapture: true);
      return cubit;
    }

    test('shares the source picked, on the running share', () async {
      final cubit = await sharing();
      await cubit.switchSource(settings: screen);
      expect(rust.switches, 1);
      expect(rust.starts, 1);
      expect(rust.switchedTo!.captureFullScreen, isTrue);
      expect(rust.switchedTo!.selectedVideoSourceIndex, 1);
      expect(cubit.state.isSharing, isTrue);
      expect(cubit.state.settings!.captureFullScreen, isTrue);
      expect(cubit.state.settings!.selectedVideoSourceTitle, 'Screen 2');
      expect(cubit.state.notice, isNotNull);
    });

    test('a window brings its own process for its sound', () async {
      final cubit = await sharing();
      await cubit.switchSource(settings: otherWindow);
      expect(rust.switchedTo!.selectedAudioSourcePid, 42);
    });

    test('ticks the sound as it came out', () async {
      final cubit = await sharing();
      rust.switchSound = false;
      await cubit.switchSource(settings: otherWindow);
      expect(cubit.state.settings!.shareAudio, isFalse);
    });

    test('a switch that fails leaves the share as it was', () async {
      final cubit = await sharing();
      rust.switchError = 'The desktop\'s picker had no answer';
      await cubit.switchSource(settings: screen);
      expect(cubit.state.isSharing, isTrue);
      expect(cubit.state.settings!.captureFullScreen, isFalse);
      expect(cubit.state.settings!.selectedVideoSourceTitle, 'Game');
      expect(cubit.state.notice, isNotNull);
    });

    test('a second switch while one runs is not made', () async {
      final cubit = await sharing();
      rust.holdSwitch = Completer();
      final first = cubit.switchSource(settings: screen);
      await pumpEventQueue();
      await cubit.switchSource(settings: otherWindow);
      rust.holdSwitch!.complete(true);
      await first;
      expect(rust.switches, 1);
      expect(cubit.state.settings!.selectedVideoSourceTitle, 'Screen 2');
    });

    const music = AudioSource(
      index: 7,
      sink: 1,
      appName: 'Player',
      binary: 'player',
      mediaName: 'Song',
      appId: 'player',
      playing: true,
    );
    const browser = AudioSource(
      index: 9,
      sink: 1,
      appName: 'Browser',
      binary: 'browser',
      mediaName: 'Video',
      appId: 'browser',
      playing: true,
    );

    test('keeps the running share\'s sound when none was asked', () async {
      final cubit = newCubit();
      await cubit.startScreenShare(
        settings: window.copyWith(selectedAudioSource: music),
        gpuCapture: true,
      );
      // The dialog's draft holds the saved settings' sound, not the share's.
      await cubit.switchSource(
        settings: screen.copyWith(selectedAudioSource: browser),
      );
      expect(rust.switchedTo!.selectedAudioSource, music);
      expect(cubit.state.settings!.selectedAudioSource, music);
    });

    test('takes the sound picked for the new window', () async {
      final cubit = newCubit();
      await cubit.startScreenShare(
        settings: window.copyWith(selectedAudioSource: music),
        gpuCapture: true,
      );
      await cubit.switchSource(
        settings: otherWindow.copyWith(selectedAudioSource: browser),
        soundPicked: true,
      );
      expect(rust.switchedTo!.selectedAudioSource, browser);
      expect(cubit.state.settings!.selectedAudioSource, browser);
    });

    test('a switch the share was stopped during says nothing', () async {
      final cubit = await sharing();
      rust.holdSwitch = Completer();
      final switching = cubit.switchSource(settings: screen);
      await pumpEventQueue();
      await cubit.stopScreenShare();
      final afterStop = cubit.state.notice;
      rust.holdSwitch!.completeError('The share was stopped');
      await switching;
      expect(cubit.state.notice, afterStop);
    });

    test('nothing is switched while nothing is shared', () async {
      final cubit = newCubit();
      await cubit.switchSource(settings: screen);
      expect(rust.switches, 0);
    });
  });

  group('a call left while its share starts', () {
    test('stops Rust waiting on the picker, and says nothing', () async {
      final cubit = newCubit();
      rust.holdStart = Completer();
      final starting = start(cubit);
      await pumpEventQueue();
      expect(rust.starts, 1);

      call.callState = const LiveKitState();
      await cubit.followCall();
      expect(rust.stops, 1);

      // What Rust answers the start that heard the stop.
      rust.holdStart!.completeError('The share was stopped');
      await starting;
      expect(cubit.state.status, ScreenshareStatus.idle);
      expect(cubit.state.notice, isNull);
    });

    test('a start still fetching its token never reaches Rust', () async {
      final cubit = newCubit();
      final starting = start(cubit);
      call.callState = const LiveKitState();
      await starting;
      expect(rust.starts, 0);
      expect(cubit.state.status, ScreenshareStatus.idle);
    });

    test('a start in the same call is left alone', () async {
      final cubit = newCubit();
      rust.holdStart = Completer();
      final starting = start(cubit);
      await pumpEventQueue();
      await cubit.followCall();
      expect(rust.stops, 0);
      rust.holdStart!.complete('started');
      await starting;
      expect(cubit.state.isSharing, isTrue);
    });
  });

  group('changes to a running share', () {
    test('go to Rust one at a time, each with the latest settings', () async {
      final cubit = newCubit();
      await cubit.startScreenShare(
        settings: const ScreenShareSettings(shareAudio: true),
        gpuCapture: true,
      );
      final top = cubit.state.codec!;
      expect(top, isNot(VideoCodec.vp8));

      rust.holdUpdate = Completer();
      final hold = rust.holdUpdate!;
      final soundOff = cubit.changeQuality(shareAudio: false);
      await pumpEventQueue();
      // A watcher who plays only VP8 arrives while the sound goes off.
      cubit.followWatchers([
        (name: 'Dave', plays: {VideoCodec.vp8}),
      ]);
      await pumpEventQueue();
      expect(rust.updates, hasLength(1));

      hold.complete();
      await soundOff;
      await pumpEventQueue();
      expect(rust.updates, hasLength(2));
      expect(rust.updates.last.codec, VideoCodec.vp8);
      expect(rust.updates.last.shareAudio, isFalse);
      expect(cubit.state.settings!.shareAudio, isFalse);
      expect(cubit.state.codec, VideoCodec.vp8);
    });
  });
}
