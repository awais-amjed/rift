import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/call_clip_audio.dart';
import 'package:rift/data/classes/participant_info.dart';
import 'package:rift/logic/services/call_clip/call_clip_native.dart';
import 'package:rift/logic/services/call_clip/clip_recorder.dart';

/// The one rule clipping is built on: nothing of the call is kept before the
/// call has been told this client is clipping. The recorder decides the order
/// (ring, then the published flag, then writing), so a fake native records
/// what it was asked, in order, and a fake publish can be held open.
class _FakeNative implements CallClipNative {
  final List<String> calls = [];
  CallClipAudio? next;

  @override
  bool get available => true;

  @override
  void configure(int seconds, {required bool includeMic}) =>
      calls.add('configure $seconds${includeMic ? ' mic' : ''}');

  @override
  void setWriting(bool on) => calls.add('writing $on');

  @override
  CallClipAudio? snapshot() => next;
}

void main() {
  late _FakeNative native;
  late List<bool> published;
  late Completer<bool>? holdPublish;
  late ClipRecorder recorder;

  setUp(() {
    native = _FakeNative();
    published = [];
    holdPublish = null;
    recorder = ClipRecorder(
      native,
      publish: (clipping) async {
        published.add(clipping);
        native.calls.add('publish $clipping');
        final hold = holdPublish;
        return hold == null ? true : hold.future;
      },
    );
  });

  Future<void> update({
    bool enabled = true,
    bool connected = true,
    bool inCall = true,
    String? call = 'channel-a',
    int seconds = 60,
    bool includeMic = false,
  }) => recorder.update(
    enabled: enabled,
    connected: connected,
    inCall: inCall,
    call: inCall ? call : null,
    seconds: seconds,
    includeMic: includeMic,
  );

  test('turned on in a call: ring, then the flag, then writing', () async {
    await update();
    expect(native.calls, ['configure 60', 'publish true', 'writing true']);
  });

  test('nothing is written while the flag is still on its way', () async {
    holdPublish = Completer<bool>();
    final pending = update();
    await Future<void>.delayed(Duration.zero);
    expect(native.calls, isNot(contains('writing true')));
    holdPublish!.complete(true);
    await pending;
    expect(native.calls.last, 'writing true');
  });

  test('a flag that failed to publish keeps writing off', () async {
    holdPublish = Completer<bool>()..complete(false);
    await update();
    expect(native.calls, isNot(contains('writing true')));
    expect(recorder.recording, isFalse);
  });

  test('a rejoin pauses writing and waits for the flag again', () async {
    await update();
    native.calls.clear();
    recorder.pause();
    expect(native.calls, ['writing false']);
    native.calls.clear();
    await update();
    expect(native.calls, ['publish true', 'writing true']);
  });

  test('while connecting nothing is written', () async {
    await update(connected: false);
    expect(native.calls, ['writing false', 'configure 60']);
    expect(published, isEmpty);
  });

  test('turned off: writing stops first, the ring is freed', () async {
    await update();
    native.calls.clear();
    await update(enabled: false);
    expect(native.calls, ['writing false', 'configure 0', 'publish false']);
  });

  test('leaving the call frees the ring', () async {
    await update();
    native.calls.clear();
    await update(inCall: false, connected: false);
    expect(native.calls.first, 'writing false');
    expect(native.calls, contains('configure 0'));
  });

  test('another call starts with an empty ring', () async {
    await update();
    native.calls.clear();
    // Moving to another channel: the connection is made again first.
    recorder.pause();
    await update(connected: false, call: 'channel-b');
    expect(native.calls, ['writing false', 'configure 0', 'configure 60']);
    native.calls.clear();
    await update(call: 'channel-b');
    expect(native.calls, ['publish true', 'writing true']);
  });

  test('a rejoin of the same call keeps the ring', () async {
    await update();
    native.calls.clear();
    recorder.pause();
    await update(connected: false);
    await update();
    expect(native.calls, isNot(contains('configure 0')));
  });

  test('turned off after a rejoin, the flag is not claimed again', () async {
    await update();
    expect(recorder.claiming, isTrue);
    recorder.pause();
    await update(enabled: false, connected: false);
    expect(recorder.claiming, isFalse);
    await update(enabled: false);
    expect(recorder.claiming, isFalse);
    expect(published, [true]);
  });

  test('a new length or the mic reconfigures without a new flag', () async {
    await update();
    native.calls.clear();
    await update(seconds: 30, includeMic: true);
    expect(native.calls, ['configure 30 mic']);
  });

  test('an unchanged update does nothing', () async {
    await update();
    native.calls.clear();
    await update();
    expect(native.calls, isEmpty);
  });

  test('the queue keeps the newest five', () {
    var queue = <CallClipAudio>[];
    for (var i = 0; i < 7; i++) {
      queue = ClipRecorder.enqueue(
        queue,
        CallClipAudio(
          id: i,
          pcm: Int16List(4),
          rate: 48000,
          channels: 2,
          at: DateTime(2026),
        ),
      );
    }
    expect(queue.map((c) => c.id), [2, 3, 4, 5, 6]);
  });

  test('a clip says its own length in whole seconds', () {
    final clip = CallClipAudio(
      id: 1,
      pcm: Int16List(48000 * 2 * 30),
      rate: 48000,
      channels: 2,
      at: DateTime(2026),
    );
    expect(clip.seconds, 30);
    expect(clip.duration, const Duration(seconds: 30));
  });

  test('the clipping mark is part of what a row compares', () {
    const plain = ParticipantInfo(identity: 'u1', userId: 'u1', name: 'Sam');
    const clipping = ParticipantInfo(
      identity: 'u1',
      userId: 'u1',
      name: 'Sam',
      isClipping: true,
    );
    expect(plain == clipping, isFalse);
    expect(plain.sameApartFromSpeaking(clipping), isFalse);
    expect(clipping.withWatching(const {'x'}).isClipping, isTrue);
  });
}
