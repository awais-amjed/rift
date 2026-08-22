import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/token/token_cubit.dart';

/// In-memory stand-in so [TokenCubit] (a HydratedCubit) can be built in tests.
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

/// A LiveKit token is an identity, not a pass to a shared room: its subject is
/// `<userId>~<deviceId>` and its display name is baked in when it is minted.
/// The cache is keyed by channel and survives a restart, so before this it
/// handed a freshly signed-in account the *previous* account's token — which
/// did not mislabel a voice tile so much as sign the new user into the room as
/// the old one, carrying their moderation grant with them. It surfaced as a
/// tile showing the wrong name while the sidebar, which reads live presence,
/// showed the right one.
void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  const url = 'https://server.example';
  const channel = 'channel-1';
  const alice = 'user-alice';
  const bob = 'user-bob';

  test('a token comes back for the user it was minted for', () {
    final cubit = TokenCubit();
    addTearDown(cubit.close);

    cubit.saveToken(url, channel, alice, 'alice-token');

    expect(cubit.getValidToken(url, channel, alice)?.token, 'alice-token');
  });

  test('another user on the same device gets nothing', () {
    // The whole bug: same machine, same channel, different account.
    final cubit = TokenCubit();
    addTearDown(cubit.close);

    cubit.saveToken(url, channel, alice, 'alice-token');

    expect(cubit.getValidToken(url, channel, bob), isNull);
  });

  test("the other user's token is dropped, not merely refused", () {
    // Refusing would leave one identity's credential on disk under another's
    // session, waiting for the first account to sign back in.
    final cubit = TokenCubit();
    addTearDown(cubit.close);

    cubit.saveToken(url, channel, alice, 'alice-token');
    cubit.getValidToken(url, channel, bob);

    expect(cubit.state.tokens, isEmpty);
    expect(cubit.getValidToken(url, channel, alice), isNull);
  });

  test('a token from another server is still refused', () {
    final cubit = TokenCubit();
    addTearDown(cubit.close);

    cubit.saveToken(url, channel, alice, 'alice-token');

    expect(
      cubit.getValidToken('https://other.example', channel, alice),
      isNull,
    );
  });

  test('an entry persisted before the user was recorded is not trusted', () {
    // Restored from disk with no owner. It cannot be shown to belong to
    // anyone, and guessing would reintroduce exactly the bug.
    HydratedBloc.storage.write('TokenCubit', {
      'tokens': {
        channel: {
          'supabaseUrl': url,
          'channelId': channel,
          'token': 'legacy-token',
          'createdAt': DateTime.now().toIso8601String(),
        },
      },
    });

    final cubit = TokenCubit();
    addTearDown(cubit.close);

    expect(cubit.state.tokens, isNotEmpty, reason: 'it should still load');
    expect(cubit.getValidToken(url, channel, alice), isNull);
  });

  test('a round trip through storage keeps the owner', () {
    final first = TokenCubit();
    first.saveToken(url, channel, alice, 'alice-token');
    final stored = first.toJson(first.state)!;
    first.close();

    final second = TokenCubit();
    addTearDown(second.close);
    final restored = second.fromJson(stored)!;

    expect(restored.tokens[channel]?.userId, alice);
  });
}
