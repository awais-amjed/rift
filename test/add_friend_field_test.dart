import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/central_dm/central_dm_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/dms/widgets/friends/add_friend_field.dart';

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

class _StubCentralDmCubit extends Cubit<CentralDmState>
    implements CentralDmCubit {
  _StubCentralDmCubit() : super(const CentralDmState());

  final List<String> asked = [];

  /// What the next ask answers with. False is the "nobody is using that
  /// handle" case, which the field has to survive without losing the typing.
  bool succeeds = true;

  @override
  Future<bool> addFriendByHandle(String handle) async {
    asked.add(handle);
    return succeeds;
  }

  @override
  void setHandleQuery(String? query) {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The one way onto the central tier.
///
/// It used to be a search drop-down: three letters and the directory answered
/// with a list of strangers, and picking one sent them a request. What these
/// check is that the replacement is a *decision* — a full handle, typed, and
/// then a button — and that nothing about it can be used to browse.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<_StubCentralDmCubit> pump(WidgetTester tester) async {
    final cubit = _StubCentralDmCubit();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<CentralDmCubit>.value(value: cubit),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Padding(
            padding: EdgeInsets.all(8),
            child: AddFriendField(),
          )),
        ),
      ),
    );
    return cubit;
  }

  testWidgets('an empty field asks nobody', (tester) async {
    final cubit = await pump(tester);

    // Not merely ignored — the button is off, so there is nothing to press
    // hopefully and nothing that looks like it might search.
    final button = tester.widget<InkWell>(
      find.ancestor(of: find.text('Send request'), matching: find.byType(InkWell)),
    );
    expect(button.onTap, isNull);

    await tester.tap(find.text('Send request'));
    await tester.pump();
    expect(cubit.asked, isEmpty);
  });

  testWidgets('a full handle is sent when the button is pressed', (
    tester,
  ) async {
    final cubit = await pump(tester);

    await tester.enterText(find.byType(TextField), 'river_stone');
    await tester.pump();
    await tester.tap(find.text('Send request'));
    await tester.pump();

    expect(cubit.asked, ['river_stone']);
    // Cleared, because it worked: leaving it filled invites a second identical
    // request at the next stray Enter.
    expect(find.text('river_stone'), findsNothing);
  });

  testWidgets('Enter is the same decision as the button', (tester) async {
    final cubit = await pump(tester);

    await tester.enterText(find.byType(TextField), 'river_stone');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(cubit.asked, ['river_stone']);
  });

  testWidgets('a refused handle stays in the field', (tester) async {
    final cubit = await pump(tester);
    cubit.succeeds = false;

    await tester.enterText(find.byType(TextField), 'rivar_stone');
    await tester.pump();
    await tester.tap(find.text('Send request'));
    await tester.pump();

    // A handle that came back "nobody is using that" is one the user may have
    // mistyped, and retyping something you can no longer see is worse than
    // fixing what is in front of you.
    expect(find.text('rivar_stone'), findsOneWidget);
  });

  testWidgets('typing is held to the shape a handle can have', (tester) async {
    final cubit = await pump(tester);

    // Handles are lowercase `[a-z0-9_]` by the column's own CHECK, so a
    // capital or a space is a keystroke to absorb rather than an error to
    // report after the round trip.
    await tester.enterText(find.byType(TextField), 'River Stone!');
    await tester.pump();
    await tester.tap(find.text('Send request'));
    await tester.pump();

    expect(cubit.asked, ['riverstone']);
  });
}
