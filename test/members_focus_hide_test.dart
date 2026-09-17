import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

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

/// A focused call tile hides the docked member list, and leaving focus puts
/// back whatever the user had.
void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  test('an open list hides for focus and comes back after', () {
    final cubit = AppCubit();
    expect(cubit.state.membersSidebarShown, isTrue);

    cubit.setStageFocused(true);
    expect(cubit.state.membersSidebarShown, isFalse);
    expect(cubit.state.membersSidebarOpen, isTrue);

    cubit.setStageFocused(false);
    expect(cubit.state.membersSidebarShown, isTrue);
  });

  test('a closed list stays closed after focus', () {
    final cubit = AppCubit()..toggleMembersSidebar();
    cubit
      ..setStageFocused(true)
      ..setStageFocused(false);
    expect(cubit.state.membersSidebarShown, isFalse);
  });

  test('opening the list during focus shows it and keeps it open', () {
    final cubit = AppCubit()..toggleMembersSidebar();
    cubit
      ..setStageFocused(true)
      ..toggleMembersSidebar();
    expect(cubit.state.membersSidebarShown, isTrue);

    cubit.setStageFocused(false);
    expect(cubit.state.membersSidebarShown, isTrue);
  });

  test('the focus flag is not saved', () {
    final cubit = AppCubit()..setStageFocused(true);
    expect(cubit.toJson(cubit.state), isNot(contains('membersHiddenForFocus')));
  });
}
