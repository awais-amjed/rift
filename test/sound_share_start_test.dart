import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/sound_share/sound_share_cubit.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';
import 'package:rift/src/rust/api/soundshare.dart';
import 'package:rift/src/rust/frb_generated.dart';

/// Rust's side of a sound share: one session at a time, as
/// `sharing::sound` keeps it, with a start that waits on [holdStart].
class _Rust implements RustLibApi {
  Completer<String>? holdStart;
  bool running = false;
  int starts = 0;
  int stops = 0;

  @override
  Stream<SoundShareEvent> crateApiSoundshareSoundShareEventStream() =>
      const Stream.empty();

  @override
  Future<String> crateApiSoundshareStartSoundShare({
    required SoundShareConfig config,
  }) async {
    starts++;
    if (running) throw 'Already sharing sound';
    running = true;
    return holdStart == null ? 'started' : holdStart!.future;
  }

  @override
  Future<String> crateApiSoundshareStopSoundShare() async {
    stops++;
    running = false;
    return 'stopped';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call implements LiveKitCubit {
  @override
  LiveKitState get state => const LiveKitState(
    currentChannelId: 'voice',
    connectionState: LiveKitConnectionState.connected,
  );

  @override
  Server? get callServer => null;

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

const _music = AudioSource(
  index: 7,
  sink: 1,
  appName: 'Player',
  binary: 'player',
  mediaName: 'Song',
  appId: 'player',
  playing: true,
);

void main() {
  final rust = _Rust();

  setUpAll(() => RustLib.initMock(api: rust));

  setUp(() {
    rust
      ..holdStart = null
      ..running = false
      ..starts = 0
      ..stops = 0;
  });

  SoundShareCubit newCubit() {
    final cubit = SoundShareCubit(livekitCubit: _Call());
    addTearDown(cubit.close);
    return cubit;
  }

  // A second press while the first connected was refused in Rust and marked
  // the running share failed, which nothing would then stop, leaving the
  // call included.
  test('a second press while one connects starts nothing', () async {
    final cubit = newCubit();
    rust.holdStart = Completer();
    final first = cubit.startSoundShare(source: _music);
    await pumpEventQueue();
    await cubit.startSoundShare(source: _music);
    rust.holdStart!.complete('started');
    await first;
    expect(rust.starts, 1);
    expect(cubit.state.isSharing, isTrue);
    await cubit.stopSoundShare();
    expect(rust.stops, 1);
    expect(rust.running, isFalse);
  });

  test(
    'a share Rust still runs is shown running, so it can be stopped',
    () async {
      final cubit = newCubit();
      rust.running = true;
      await cubit.startSoundShare(source: _music);
      expect(cubit.state.isSharing, isTrue);
      await cubit.stopSoundShare();
      expect(rust.running, isFalse);
    },
  );
}
