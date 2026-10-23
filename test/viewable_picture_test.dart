import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/media/media_cubit.dart';
import 'package:rift/logic/services/media_store.dart';
import 'package:rift/presentation/common/viewable_picture.dart';

/// A profile's picture opens full size, and only when there is a picture:
/// an initial has nothing behind it to open.
void main() {
  const host = 'https://srv.example';
  const path = 'avatars/lana.png';
  // A 1×1 PNG.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC',
  );

  Future<void> pump(WidgetTester tester, MediaCubit media) => tester.pumpWidget(
    BlocProvider.value(
      value: media,
      child: MaterialApp(
        home: Center(
          child: ViewablePicture(
            origin: host,
            path: path,
            name: 'Lana',
            child: const SizedBox.square(dimension: 56),
          ),
        ),
      ),
    ),
  );

  testWidgets('opens the picture it holds', (tester) async {
    // Held before the cubit starts, which begins from what the store holds.
    final images = MediaStore(maxEntries: 8)..put(path, png, origin: host);
    final media = MediaCubit(
      images: images,
      attachments: MediaStore(maxEntries: 8),
      retryAfter: const [],
    );
    addTearDown(media.close);
    await pump(tester, media);

    await tester.tap(find.byType(ViewablePicture));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Save'), findsOneWidget);
  });

  testWidgets('an initial opens nothing', (tester) async {
    final media = MediaCubit(
      images: MediaStore(maxEntries: 8),
      attachments: MediaStore(maxEntries: 8),
      retryAfter: const [],
    );
    addTearDown(media.close);
    await pump(tester, media);

    await tester.tap(find.byType(ViewablePicture));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
  });
}
