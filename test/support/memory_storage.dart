import 'package:hydrated_bloc/hydrated_bloc.dart';

/// In-memory [Storage] for tests that build a `HydratedCubit` — `ThemeCubit`
/// is one, so any widget test that provides a theme needs this or it throws
/// `type 'Null' is not a subtype of type 'ThemeCubit'` on teardown.
///
/// Extracted because 38 test files had each written their own copy. Use it in
/// new tests rather than adding a 39th:
///
/// ```dart
/// setUpAll(() => HydratedBloc.storage = MemoryStorage());
/// ```
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
