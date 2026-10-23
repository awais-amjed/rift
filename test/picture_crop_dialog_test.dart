import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/picture_crop/picture_crop_dialog.dart';

/// In-memory stand-in so [ThemeCubit] (a HydratedCubit) can be built in tests.
class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// A plain RGB PNG of [width]×[height], written by hand so the test needs no
/// image package of its own.
Uint8List _png(int width, int height) {
  Uint8List chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final out = BytesBuilder()
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc(body)));
    return out.toBytes();
  }

  final rows = BytesBuilder();
  for (var y = 0; y < height; y++) {
    rows.addByte(0);
    for (var x = 0; x < width; x++) {
      rows.add([x % 256, y % 256, 128]);
    }
  }
  return (BytesBuilder()
        ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(chunk('IHDR', [..._u32(width), ..._u32(height), 8, 2, 0, 0, 0]))
        ..add(chunk('IDAT', ZLibCodec().encode(rows.toBytes())))
        ..add(chunk('IEND', const [])))
      .toBytes();
}

List<int> _u32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];

int _crc(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 == 1 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// The size a PNG says it is, from its header.
({int width, int height}) _sizeOf(Uint8List png) {
  final header = ByteData.sublistView(png, 16, 24);
  return (width: header.getUint32(0), height: header.getUint32(4));
}

/// The crop dialog answers a square, whatever the shape it was given: every
/// avatar and icon is drawn square, and a picture that was not got its edges
/// cut off by the clip wherever it was shown, with no say in which.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('Apply answers a square cut from a wide picture', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Uint8List? answer;
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  answer = await Navigator.of(context).push<Uint8List>(
                    MaterialPageRoute(
                      builder: (_) =>
                          PictureCropDialog(picture: _png(300, 200)),
                    ),
                  ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Not pumpAndSettle: the loading dots go round until the picture is in.
    await tester.pump(const Duration(milliseconds: 500));

    // The picture is decoded off the main isolate, which only real time
    // moves along.
    final apply = find.widgetWithText(FilledButton, 'Apply');
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }

    for (var i = 0; i < 20 && answer == null; i++) {
      await settle();
      if (find.text('Crop picture').evaluate().isNotEmpty &&
          tester.widget<FilledButton>(apply).onPressed != null) {
        break;
      }
    }
    await tester.tap(apply);
    for (var i = 0; i < 20 && answer == null; i++) {
      await settle();
    }

    expect(answer, isNotNull);
    final size = _sizeOf(answer!);
    expect(size.width, size.height);
    expect(size.width, lessThanOrEqualTo(200));
  });
}
