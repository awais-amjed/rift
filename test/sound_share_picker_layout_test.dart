import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/soundshare/sound_share_picker_dialog.dart';
import 'package:sizer/sizer.dart';

import 'helpers/memory_storage.dart';

/// The Share sound picker with nothing to list.
///
/// No native library is loaded in a test, so the source list comes back empty
/// — which is the state that broke: the message's column took every pixel the
/// dialog may grow to, so an empty picker stood at full height with three
/// lines pinned to its top-left.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('an empty picker is sized to its message and centres it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: Sizer(
          builder: (_, _, _) =>
              const MaterialApp(home: Scaffold(body: SoundSharePickerDialog())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final message = find.text('Nothing is playing');
    expect(message, findsOneWidget);

    // The surface the dialog paints, not the [Dialog], which spans the screen
    // to position it.
    final dialog = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    // Header, message and buttons — nowhere near the 70% of the window it
    // is allowed to take.
    expect(dialog.height, lessThan(360));

    final title = tester.getRect(message);
    final hint = tester.getRect(
      find.text('Start playing something in an app, then refresh.'),
    );
    expect(title.center.dx, closeTo(dialog.center.dx, 1));
    expect(hint.center.dx, closeTo(dialog.center.dx, 1));
  });
}
