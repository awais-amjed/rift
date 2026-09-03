import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/public_server.dart';
import 'package:rift/data/repositories/public_server_repository.dart';
import 'package:rift/logic/cubits/public_servers/public_servers_cubit.dart';

PublicServer server(String id) => PublicServer(
  id: id,
  serverId: id,
  ownerId: 'owner',
  supabaseUrl: 'https://example.test',
  inviteCode: 'code',
  name: id,
  isListed: true,
  memberCount: 0,
  updatedAt: DateTime(2026),
);

/// Answers browse from a script, and records what it was asked for.
class _FakeRepo implements PublicServerRepository {
  final List<int> offsets = [];
  final List<({List<PublicServer> results, bool hasMore})> pages;

  /// Held open when set, so a test can look at the state mid-flight.
  Completer<void>? gate;

  _FakeRepo(this.pages);

  @override
  Future<APIResponse> browse({
    String? query,
    String? tag,
    int limit = 50,
    int offset = 0,
  }) async {
    offsets.add(offset);
    if (gate != null) await gate!.future;
    final page = pages.isEmpty
        ? (results: <PublicServer>[], hasMore: false)
        : pages.removeAt(0);
    return APIResponse.success({
      'results': page.results,
      'has_more': page.hasMore,
    });
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PublicServersCubit paging', () {
    test('browse starts at the top and reports whether more follows', () async {
      final repo = _FakeRepo([
        (results: [server('a')], hasMore: true),
      ]);
      final cubit = PublicServersCubit(repo: repo);

      await cubit.browse();
      expect(repo.offsets, [0]);
      expect(cubit.state.results.map((s) => s.id), ['a']);
      expect(cubit.state.hasMore, isTrue);
      expect(cubit.state.hasBrowsed, isTrue);
    });

    test('loadMore appends from where the list ended', () async {
      // Offset comes from how many rows are held, not from a page counter —
      // so a short page cannot leave the two disagreeing.
      final repo = _FakeRepo([
        (results: [server('a'), server('b')], hasMore: true),
        (results: [server('c')], hasMore: false),
      ]);
      final cubit = PublicServersCubit(repo: repo);

      await cubit.browse();
      await cubit.loadMore();

      expect(repo.offsets, [0, 2]);
      expect(cubit.state.results.map((s) => s.id), ['a', 'b', 'c']);
      expect(cubit.state.hasMore, isFalse);
    });

    test('loadMore past the end asks for nothing', () async {
      final repo = _FakeRepo([
        (results: [server('a')], hasMore: false),
      ]);
      final cubit = PublicServersCubit(repo: repo);

      await cubit.browse();
      await cubit.loadMore();

      expect(repo.offsets, [0], reason: 'the end was already reached');
    });

    test('a second loadMore while one is in flight is dropped', () async {
      // The case a scroll listener hits constantly: it fires per frame, and
      // each frame would otherwise ask for the same page again.
      final repo = _FakeRepo([
        (results: [server('a')], hasMore: true),
        (results: [server('b')], hasMore: false),
      ]);
      final cubit = PublicServersCubit(repo: repo);
      await cubit.browse();

      repo.gate = Completer<void>();
      final first = cubit.loadMore();
      await cubit.loadMore();
      expect(repo.offsets, [0, 1]);

      repo.gate!.complete();
      await first;
      expect(cubit.state.results.map((s) => s.id), ['a', 'b']);
    });

    test('a new search throws away the pages of the old one', () async {
      final repo = _FakeRepo([
        (results: [server('a')], hasMore: true),
        (results: [server('b')], hasMore: true),
        (results: [server('z')], hasMore: false),
      ]);
      final cubit = PublicServersCubit(repo: repo);

      await cubit.browse();
      await cubit.loadMore();
      expect(cubit.state.results, hasLength(2));

      // Re-browsing replaces rather than appends, or a search would show the
      // previous query's results underneath its own.
      await cubit.browse();
      expect(cubit.state.results.map((s) => s.id), ['z']);
      expect(cubit.state.hasMore, isFalse);
      expect(repo.offsets, [0, 1, 0]);
    });
  });
}
