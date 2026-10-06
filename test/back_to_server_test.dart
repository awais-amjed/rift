import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/enums/home_surface.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

/// In-memory stand-in so [AppCubit] (a HydratedCubit) can be built in tests.
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

/// Home is a detour from a server: coming back opens the half of it that was
/// left. It used to open the channels whatever was left, losing a server DM.
void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  test('back from Home to the server DMs that were open', () {
    final cubit = AppCubit()
      ..setSurface(HomeSurface.serverDms)
      ..setSurface(HomeSurface.centralDms)
      ..backToServer();
    expect(cubit.state.surface, HomeSurface.serverDms);
  });

  test('back from Home to the channels that were open', () {
    final cubit = AppCubit()
      ..setSurface(HomeSurface.serverDms)
      ..setSurface(HomeSurface.server)
      ..setSurface(HomeSurface.centralDms)
      ..backToServer();
    expect(cubit.state.surface, HomeSurface.server);
  });

  test('a fresh app goes back to the channels', () {
    final cubit = AppCubit()
      ..setSurface(HomeSurface.centralDms)
      ..backToServer();
    expect(cubit.state.surface, HomeSurface.server);
  });

  test('already on the server, it stays where it is', () {
    final cubit = AppCubit()
      ..setSurface(HomeSurface.serverDms)
      ..backToServer();
    expect(cubit.state.surface, HomeSurface.serverDms);
  });
}
