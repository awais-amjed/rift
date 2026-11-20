import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_switch.dart';
import 'package:rift/presentation/screens/settings/widgets/voice_audio/clipping/clipping_section.dart';

import 'support/memory_storage.dart';

/// Clipping in Voice & Audio: off until turned on, and once on, how far
/// back a clip goes and whether your own voice is in it.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<AppCubit> pump(WidgetTester tester) async {
    final app = AppCubit();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>.value(value: app),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlocBuilder<AppCubit, AppState>(
                builder: (_, state) => ClippingSection(appState: state),
              ),
            ),
          ),
        ),
      ),
    );
    return app;
  }

  testWidgets('off by default, and says the call will know', (tester) async {
    final app = await pump(tester);
    expect(app.state.clippingEnabled, isFalse);
    expect(
      find.text('People in the call see that you have clipping on.'),
      findsOneWidget,
    );
    expect(find.text('Clip length'), findsNothing);
    expect(find.text('Include my mic'), findsNothing);
  });

  testWidgets('turned on, the length and the mic appear', (tester) async {
    final app = await pump(tester);
    await tester.tap(find.byType(AppSwitch).first);
    await tester.pumpAndSettle();
    expect(app.state.clippingEnabled, isTrue);
    expect(find.text('Clip length'), findsOneWidget);
    expect(find.text('1 minute'), findsOneWidget);
    expect(find.text('Include my mic'), findsOneWidget);
  });

  testWidgets('a length picked from the list is kept', (tester) async {
    final app = await pump(tester);
    app.setClippingEnabled(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 minute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 minutes').last);
    await tester.pumpAndSettle();
    expect(app.state.clipSeconds, 120);
  });

  testWidgets('the mic switch keeps your voice in clips', (tester) async {
    final app = await pump(tester);
    app.setClippingEnabled(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppSwitch).last);
    await tester.pumpAndSettle();
    expect(app.state.clipIncludeMic, isTrue);
  });
}
