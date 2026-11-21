import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/call_clip_audio.dart';
import 'package:rift/data/classes/stored_clip.dart';
import 'package:rift/logic/services/call_clip/clip_library.dart';
import 'package:rift_crypto/rift_crypto.dart';

String seedOf(int fill) =>
    CryptoRepository.toBase64(Uint8List.fromList(List.filled(32, fill)));

/// The last stretch of the call, kept on this device: the newest ten,
/// sealed under a key from the seed, like the saved conversations
/// (CALLS.md, *Clipping a call*).
void main() {
  final seed = seedOf(1);
  late Directory root;
  late ClipLibrary library;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rift_clip_library_test');
    library = ClipLibrary(root: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  CallClipAudio audio(int fill, {DateTime? at}) => CallClipAudio(
    id: fill,
    // Two channels, 0.1 s at 48 kHz: a tone that reads back exactly.
    pcm: Int16List.fromList(List.generate(9600, (i) => (i * fill) % 30000)),
    rate: 48000,
    channels: 2,
    at: at ?? DateTime.utc(2026, 11, 21, 9, 0, fill),
  );

  Future<StoredClip> add(int fill, {String place = 'General · Rift Test'}) =>
      library.add(
        seed,
        audio(fill),
        serverId: 's1',
        channelId: 'c1',
        place: place,
        fromDmCall: false,
      );

  List<File> files() =>
      root.listSync(recursive: true).whereType<File>().toList();

  test('lists what it kept, newest first, with where it came from', () async {
    await add(1);
    await add(2, place: 'Fuck San · Garcie’s Server');
    final clips = await library.list(seed);
    expect(clips.map((c) => c.place), [
      'Fuck San · Garcie’s Server',
      'General · Rift Test',
    ]);
    expect(clips.first.serverId, 's1');
    expect(clips.first.channelId, 'c1');
    expect(clips.first.fromDmCall, isFalse);
    expect(clips.first.duration, const Duration(milliseconds: 100));
    expect(clips.first.at, DateTime.utc(2026, 11, 21, 9, 0, 2));
  });

  test('opens a kept clip to the same samples', () async {
    final kept = await add(3);
    final opened = await library.load(seed, kept);
    expect(opened, isNotNull);
    expect(opened!.pcm, audio(3).pcm);
    expect(opened.rate, 48000);
    expect(opened.channels, 2);
    // Local, as a press's own time is: the trim view prints it, and names
    // the saved file by it.
    expect(opened.at.isUtc, isFalse);
    expect(opened.at.isAtSameMomentAs(kept.at), isTrue);
  });

  test('keeps only the newest ten', () async {
    for (var i = 1; i <= 12; i++) {
      await add(i);
    }
    final clips = await library.list(seed);
    expect(clips, hasLength(ClipLibrary.keep));
    expect(clips.last.at, DateTime.utc(2026, 11, 21, 9, 0, 3));
    // The two dropped leave nothing behind.
    expect(files(), hasLength(ClipLibrary.keep * 2));
  });

  test('is sealed: no name or sample appears on the disk', () async {
    await add(5, place: 'Secret Room · Hidden Server');
    final samples = audio(5).pcm.buffer.asUint8List();
    final run = String.fromCharCodes(samples.sublist(100, 140));
    for (final file in files()) {
      final text = String.fromCharCodes(file.readAsBytesSync());
      expect(text, isNot(contains('Secret')));
      expect(text, isNot(contains('Hidden')));
      expect(text, isNot(contains(run)));
    }
  });

  test('another seed opens nothing, and its copies go', () async {
    await add(1);
    expect(await library.list(seedOf(2)), isEmpty);
    expect(files(), isEmpty);
  });

  test('deletes one, or all', () async {
    final first = await add(1);
    await add(2);
    await library.delete(first.id);
    expect(
      (await library.list(seed)).map((c) => c.id),
      isNot(contains(first.id)),
    );
    expect(files(), hasLength(2));
    await library.clear();
    expect(await library.list(seed), isEmpty);
    expect(files(), isEmpty);
  });

  test('tells its listeners each time the list changes', () async {
    var heard = 0;
    final sub = library.changes.listen((_) => heard++);
    final kept = await add(1);
    await library.delete(kept.id);
    await library.clear();
    await Future<void>.delayed(Duration.zero);
    expect(heard, 3);
    await sub.cancel();
  });

  test('two clips in the same instant are both kept', () async {
    final at = DateTime.utc(2026, 11, 21, 9);
    await library.add(
      seed,
      audio(1, at: at),
      serverId: null,
      channelId: null,
      place: 'A',
      fromDmCall: true,
    );
    await library.add(
      seed,
      audio(2, at: at),
      serverId: null,
      channelId: null,
      place: 'B',
      fromDmCall: true,
    );
    final clips = await library.list(seed);
    expect(clips, hasLength(2));
    expect(clips.every((c) => c.fromDmCall && c.serverId == null), isTrue);
  });

  test('a clip kept by a newer Rift is left, not thrown away', () async {
    final crypto = CryptoRepository();
    final key = await crypto.deriveClipKey(CryptoRepository.fromBase64(seed));
    final sealed = await crypto.encryptBytes(
      data: Uint8List.fromList(utf8.encode(jsonEncode({'v': 2, 'clip': {}}))),
      key: key,
    );
    final meta = File('${root.path}/1.meta')
      ..writeAsBytesSync([...sealed.iv, ...sealed.ciphertext]);
    await add(5);
    expect((await library.list(seed)), hasLength(1));
    expect(meta.existsSync(), isTrue);
  });

  test('a file half written when Rift quit goes', () async {
    await add(1);
    final left = File('${root.path}/9.pcm.tmp')..writeAsBytesSync([1, 2, 3]);
    expect(await library.list(seed), hasLength(1));
    expect(left.existsSync(), isFalse);
  });

  test('a clear that cannot delete everything still finishes', () async {
    await add(1);
    // Files in a folder that may not be written cannot be deleted.
    Process.runSync('chmod', ['500', root.path]);
    addTearDown(() => Process.runSync('chmod', ['700', root.path]));
    await expectLater(library.clear(), completes);
    await expectLater(library.wipe(), completes);
  }, testOn: 'linux');

  test('a wipe tells the readers and drops the key', () async {
    var wiped = 0;
    final sub = library.wiped.listen((_) => wiped++);
    await add(1);
    await library.wipe();
    await Future<void>.delayed(Duration.zero);
    expect(wiped, 1);
    expect(root.existsSync() ? files() : const <File>[], isEmpty);
    await sub.cancel();
  });

  test('the clip key is a rung of its own', () async {
    final crypto = CryptoRepository();
    final bytes = CryptoRepository.fromBase64(seed);
    final clipKey = await crypto.deriveClipKey(bytes);
    expect(clipKey, hasLength(32));
    expect(clipKey, await crypto.deriveClipKey(bytes));
    expect(clipKey, isNot(await crypto.deriveMessageCacheKey(bytes)));
    expect(clipKey, isNot(await crypto.deriveLocalVaultKey(bytes)));
  });
}
