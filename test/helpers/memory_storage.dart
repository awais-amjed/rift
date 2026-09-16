import 'package:hydrated_bloc/hydrated_bloc.dart';

/// In-memory stand-in so a `HydratedCubit` such as `ThemeCubit` can be built
/// in a widget test without touching disk.
class MemoryStorage implements Storage {
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
