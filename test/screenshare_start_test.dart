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
  Future<String> crateApiScreenshareStopScreenshare() async {
    stops++;
    return 'stopped';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A call the share can belong to.
class _Call implements LiveKitCubit {
  @override
  LiveKitState get state => const LiveKitState(
    currentChannelId: 'voice',
    connectionState: LiveKitConnectionState.connected,
  );

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
      ..stops = 0;
  });

  ScreenshareCubit newCubit() {
    final cubit = ScreenshareCubit(livekitCubit: _Call());
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
}
