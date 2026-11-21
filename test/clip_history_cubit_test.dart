import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/call_clip_audio.dart';
import 'package:rift/logic/cubits/clip_history/clip_history_cubit.dart';
import 'package:rift/logic/services/call_clip/clip_library.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// The list of recent clips follows the library: what a press keeps, what is
/// deleted, and the whole list going.
void main() {
  final seed = CryptoRepository.toBase64(
    Uint8List.fromList(List.filled(32, 7)),
  );
  late Directory root;
  late ClipLibrary library;
  late ClipHistoryCubit cubit;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rift_clip_history_test');
    library = ClipLibrary(root: () async => root);
    cubit = ClipHistoryCubit(library: library);
  });

  tearDown(() async {
    await cubit.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> keep(int second) => library.add(
    seed,
    CallClipAudio(
      id: second,
      pcm: Int16List(960),
      rate: 48000,
      channels: 2,
      at: DateTime.utc(2026, 11, 21, 9, 0, second),
    ),
    serverId: 's1',
    channelId: 'c1',
    place: 'General · Rift Test',
    fromDmCall: false,
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('nothing is listed before it is loaded with the seed', () async {
    await keep(1);
    await settle();
    expect(cubit.state.loaded, isFalse);
    expect(cubit.state.clips, isEmpty);
    await cubit.load(seed);
    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.clips, hasLength(1));
  });

  test('a clip kept later shows without loading again', () async {
    await cubit.load(seed);
    await keep(1);
    await keep(2);
    await settle();
    expect(cubit.state.clips.map((c) => c.at.second), [2, 1]);
  });

  test('deleting one, then all, empties the list', () async {
    await keep(1);
    await keep(2);
    await cubit.load(seed);
    await cubit.delete(cubit.state.clips.first.id);
    await settle();
    expect(cubit.state.clips.map((c) => c.at.second), [1]);
    await cubit.deleteAll();
    await settle();
    expect(cubit.state.clips, isEmpty);
  });

  test('opens a listed clip', () async {
    await keep(3);
    await cubit.load(seed);
    final audio = await cubit.open(cubit.state.clips.single);
    expect(audio?.frames, 480);
  });
}
