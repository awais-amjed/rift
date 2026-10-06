import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_toast.dart';
import 'package:toastification/toastification.dart';

import 'support/memory_storage.dart';

/// A toast's words can be selected, so an error can be pasted somewhere —
/// unless the toast is a button, where a click on its text must press it.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onTap,
    ValueChanged<bool>? onHover,
  }) async {
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: AppToast(
              title: 'Error',
              description: 'Upload failed: 413 Payload Too Large',
              type: ToastificationType.error,
              onClose: () {},
              onTap: onTap,
              onHover: onHover,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('an ordinary toast is selectable', (tester) async {
    await pump(tester);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('a toast that is a button is not', (tester) async {
    var pressed = false;
    await pump(tester, onTap: () => pressed = true);
    expect(find.byType(SelectionArea), findsNothing);
    await tester.tap(find.textContaining('Upload failed'));
    expect(pressed, isTrue);
  });

  testWidgets('it says when the mouse is on it', (tester) async {
    final hovers = <bool>[];
    await pump(tester, onHover: hovers.add);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.textContaining('Upload failed')));
    await tester.pump();
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(hovers, [true, false]);
  });
}
