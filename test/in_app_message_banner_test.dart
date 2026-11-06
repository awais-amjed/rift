import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/in_app_message_banner.dart';

import 'support/memory_storage.dart';

/// The card a message arriving in a focused window shows: it opens the
/// conversation when pressed, and closes without opening it.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(
    WidgetTester tester, {
    String what = 'mentioned you in #general',
    String? place = "Gracie's Server",
    VoidCallback? onTap,
    VoidCallback? onClose,
  }) => tester.pumpWidget(
    BlocProvider<ThemeCubit>(
      create: (_) => ThemeCubit(),
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: InAppMessageBanner(
              senderId: 'u1',
              sender: 'Gracie',
              avatarPath: null,
              what: what,
              place: place,
              isMention: true,
              onTap: onTap ?? () {},
              onClose: onClose ?? () {},
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('a press opens it', (tester) async {
    var opened = 0;
    await pump(tester, onTap: () => opened++);
    await tester.tap(find.textContaining('mentioned you'));
    expect(opened, 1);
  });

  testWidgets('swiped up, it closes without opening', (tester) async {
    var opened = 0;
    var closed = 0;
    await pump(tester, onTap: () => opened++, onClose: () => closed++);
    await tester.fling(
      find.textContaining('mentioned you'),
      const Offset(0, -80),
      800,
    );
    await tester.pumpAndSettle();
    expect((opened, closed), (0, 1));
  });

  testWidgets('long words stay on their line, in the width it has', (
    tester,
  ) async {
    await pump(tester, what: 'mentioned you in #${'very-long-' * 20}channel');
    expect(tester.takeException(), isNull);
    final width = tester.getSize(find.byType(Container).first).width;
    expect(width, lessThanOrEqualTo(InAppMessageBanner.maxWidth));
  });
}
