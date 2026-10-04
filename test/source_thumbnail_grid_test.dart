import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/screenshare/widgets/source_thumbnail_grid.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

import 'support/memory_storage.dart';

/// A minimised window has no picture, and is listed anyway: a minimised game
/// is what people go looking for. Its tile says why there is no picture and
/// when the share of it will start.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('a minimised window says its share starts when it is opened', (
    tester,
  ) async {
    CaptureSource? picked;
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: SourceThumbnailGrid(
              sources: const [
                CaptureSource(index: 0, title: 'Browser', minimised: false),
                CaptureSource(index: 1, title: 'Game', minimised: true),
              ],
              selectedIndex: 0,
              thumbnails: const {},
              captureFullScreen: false,
              onChanged: (source) => picked = source,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Starts when you open it'), findsOneWidget);
    await tester.tap(find.text('Game'));
    expect(picked?.index, 1);
  });
}
