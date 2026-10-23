import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/repositories/server_icon_repository.dart';
import 'package:rift/logic/cubits/media/media_cubit.dart';
import 'package:rift/logic/services/media_store.dart';
import 'package:rift/presentation/common/rounded_picture.dart';
import 'package:rift/presentation/common/server_icon.dart';

/// A server's icon is a path in its own folder of its own public bucket, and
/// nothing else is ever fetched. `icon_url` is written by an admin, and when it
/// held an address every member's app went to whatever host it named.
void main() {
  const id = 'aaaa0000-0000-4000-8000-000000000001';
  const own = '$id/0a1b2c3d4e5f60718293a4b5.img';

  group('isIconOf', () {
    test('takes an icon in the server\'s own folder', () {
      expect(ServerIconRepository.isIconOf(id, own), isTrue);
    });

    test('refuses an address, another folder, and anything else', () {
      for (final path in [
        null,
        '',
        'https://tracker.example/pixel.png',
        'bbbb0000-0000-4000-8000-000000000001/0a1b2c3d.img',
        '$id/../other/0a1b2c3d.img',
        '$id/0a1b2c3d.png',
        '$id/sub/0a1b2c3d.img',
        id,
      ]) {
        expect(ServerIconRepository.isIconOf(id, path), isFalse, reason: path);
      }
    });
  });

  test('the listing copies from the server\'s own public bucket', () {
    expect(
      ServerIconRepository.publicUrlOf('https://srv.example', id, own),
      'https://srv.example/storage/v1/object/public/servers/$own',
    );
    expect(
      ServerIconRepository.publicUrlOf(
        'https://srv.example',
        id,
        'https://tracker.example/pixel.png',
      ),
      isNull,
    );
  });

  group('ServerIcon', () {
    late List<Uri> fetched;
    late MediaCubit media;

    setUp(() {
      fetched = [];
      final client = MockClient((request) async {
        fetched.add(request.url);
        return http.Response.bytes(Uint8List(0), 404);
      });
      media = MediaCubit(
        images: MediaStore(maxEntries: 8),
        attachments: MediaStore(maxEntries: 8),
        serverIcons: ServerIconRepository(httpClient: client),
        retryAfter: const [],
      );
    });

    tearDown(() => media.close());

    Future<void> pump(WidgetTester tester, String? path) => tester.pumpWidget(
      BlocProvider.value(
        value: media,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ServerIcon(
            supabaseUrl: 'https://srv.example',
            serverId: id,
            name: 'Alpha',
            iconPath: path,
            size: 40,
          ),
        ),
      ),
    );

    testWidgets('fetches its own icon from its own host', (tester) async {
      await pump(tester, own);
      await tester.pump();
      expect(fetched, [
        Uri.parse('https://srv.example/storage/v1/object/public/servers/$own'),
      ]);
      // Nothing to draw yet, so the initial.
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('a server repeating another\'s id and path draws only its '
        'own bytes', (tester) async {
      // Two 1×1 PNGs, red from the impostor and blue from the real host.
      final evil = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
      );
      final real = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC',
      );
      // Its own cubit, made inside the test so its updates run on the test's
      // clock.
      final pictures = MediaCubit(
        images: MediaStore(maxEntries: 8),
        attachments: MediaStore(maxEntries: 8),
        serverIcons: ServerIconRepository(
          httpClient: MockClient((request) async {
            fetched.add(request.url);
            final host = request.url.host;
            return http.Response.bytes(
              host == 'evil.example' ? evil : real,
              200,
            );
          }),
        ),
        retryAfter: const [],
      );
      addTearDown(pictures.close);
      Widget icon(String host) => ServerIcon(
        supabaseUrl: host,
        serverId: id,
        name: 'Alpha',
        iconPath: own,
        size: 40,
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: pictures,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                icon('https://evil.example'),
                icon('https://srv.example'),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(fetched.map((u) => u.host), ['evil.example', 'srv.example']);
      expect(
        pictures.state.bytes(
          MediaKind.image,
          MediaStore.keyOf('https://srv.example', own),
        ),
        real,
      );
      // Drawn with what came from each widget's own host.
      await tester.pump();
      final drawn = tester
          .widgetList<RoundedPicture>(find.byType(RoundedPicture))
          .map((p) => (p.image as MemoryImage).bytes)
          .toList();
      expect(drawn, [evil, real]);
    });

    testWidgets('never fetches an address the row names', (tester) async {
      await pump(tester, 'https://tracker.example/pixel.png');
      await tester.pump();
      expect(fetched, isEmpty);
      expect(find.text('A'), findsOneWidget);
    });
  });
}
