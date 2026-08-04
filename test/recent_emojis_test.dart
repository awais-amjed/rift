import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
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

/// The emoji picker's "frequently used" row. It is a most-recently-used list,
/// which is only useful if re-picking something moves it rather than piling up
/// duplicates, and if it stays one row long.
void main() {
  // Per test, not once: a HydratedCubit restores from whatever storage holds,
  // so a shared store would let one test's picks seed the next one's cubit.
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  test('a fresh app has no recents', () {
    expect(AppCubit().state.recentEmojis, isEmpty);
  });

  test('the newest pick comes first', () {
    final cubit = AppCubit()
      ..noteEmojiUsed('👍')
      ..noteEmojiUsed('🔥');

    expect(cubit.state.recentEmojis, ['🔥', '👍']);
  });

  test('re-picking promotes rather than duplicating', () {
    final cubit = AppCubit()
      ..noteEmojiUsed('👍')
      ..noteEmojiUsed('🔥')
      ..noteEmojiUsed('👍');

    expect(cubit.state.recentEmojis, ['👍', '🔥']);
  });

  test('the row stays one row long, dropping the oldest', () {
    final cubit = AppCubit();
    // One more than fits.
    const picks = [
      '1️⃣',
      '2️⃣',
      '3️⃣',
      '4️⃣',
      '5️⃣',
      '6️⃣',
      '7️⃣',
      '8️⃣',
      '9️⃣',
    ];
    for (final emoji in picks) {
      cubit.noteEmojiUsed(emoji);
    }

    expect(cubit.state.recentEmojis.length, AppCubit.maxRecentEmojis);
    expect(cubit.state.recentEmojis.first, '9️⃣');
    // The very first pick has aged out.
    expect(cubit.state.recentEmojis, isNot(contains('1️⃣')));
  });

  test('recents survive a copyWith that does not mention them', () {
    final cubit = AppCubit()..noteEmojiUsed('🎉');
    final next = cubit.state.copyWith(audioEnabled: false);

    expect(next.recentEmojis, ['🎉']);
  });
}
