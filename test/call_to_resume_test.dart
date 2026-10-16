import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/call_to_resume.dart';
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

/// Restart to update quits Rift in the middle of a call; the next start puts
/// the person back in it, once, and only straight after the restart.
void main() {
  final savedAt = DateTime.utc(2026, 10, 17, 12);
  final call = CallToResume(channelId: 'c1', savedAt: savedAt, deafened: true);

  test('rejoined only straight after the restart', () {
    expect(call.isFreshAt(savedAt.add(const Duration(seconds: 20))), isTrue);
    expect(call.isFreshAt(savedAt.add(CallToResume.keptFor)), isTrue);
    expect(
      call.isFreshAt(
        savedAt.add(CallToResume.keptFor + const Duration(seconds: 1)),
      ),
      isFalse,
    );
    // A clock set back is not fresh forever.
    expect(call.isFreshAt(savedAt.subtract(const Duration(hours: 1))), isFalse);
  });

  test('saved with the app\'s settings', () {
    expect(CallToResume.fromJson(call.toJson()), call);
    final state = const AppState().copyWith(callToResume: call);
    expect(AppState.fromJson(state.toJson()).callToResume, call);
    expect(AppState.fromJson(const AppState().toJson()).callToResume, isNull);
  });

  group('the start after', () {
    late AppCubit app;

    setUp(() {
      HydratedBloc.storage = _MemoryStorage();
      app = AppCubit();
    });

    tearDown(() => app.close());

    test('takes the call once', () {
      app.rememberCallToResume(call);
      final now = savedAt.add(const Duration(seconds: 15));
      expect(app.takeCallToResume(now), call);
      expect(app.state.callToResume, isNull);
      expect(app.takeCallToResume(now), isNull);
    });

    test('drops one it found too late', () {
      app.rememberCallToResume(call);
      expect(
        app.takeCallToResume(savedAt.add(const Duration(hours: 9))),
        isNull,
      );
      expect(app.state.callToResume, isNull);
    });
  });
}
