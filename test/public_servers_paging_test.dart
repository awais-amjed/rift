import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/public_server.dart';
import 'package:rift/data/enums/directory_sort.dart';
import 'package:rift/data/repositories/public_server_repository.dart';
import 'package:rift/logic/cubits/public_servers/public_servers_cubit.dart';
import 'package:rift/presentation/screens/home/servers/server_settings/listing_draft.dart';

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
  final List<DirectorySort> sorts = [];

  /// What [setLiked] answers: a count, or a refusal.
  APIResponse likeAnswer = APIResponse.success(1);
  final List<({List<PublicServer> results, bool hasMore})> pages;

  /// Held open when set, so a test can look at the state mid-flight.
  Completer<void>? gate;

  /// Per call, by its number from 0: held until completed, and answered with
  /// a failure when listed in [failing].
  final Map<int, Completer<void>> holds = {};
  final Set<int> failing = {};
  int _calls = 0;

  _FakeRepo(this.pages);

  @override
  Future<APIResponse> browse({
    String? query,
    String? tag,
    DirectorySort sort = DirectorySort.top,
    int limit = 50,
    int offset = 0,
  }) async {
    final call = _calls++;
    offsets.add(offset);
    sorts.add(sort);
    // Taken in call order, before any hold: a held call still owns its page.
    final page = failing.contains(call) || pages.isEmpty
        ? (results: <PublicServer>[], hasMore: false)
        : pages.removeAt(0);
    if (gate != null) await gate!.future;
    if (holds[call] case final hold?) await hold.future;
    if (failing.contains(call)) return APIResponse.error('central is down');
    return APIResponse.success({
      'results': page.results,
      'has_more': page.hasMore,
    });
  }

  @override
  Future<APIResponse> setLiked(String listingId, {required bool liked}) async =>
      likeAnswer;

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

  group('PublicServersCubit order and likes', () {
    test('browses by likes first, and New asks again by newest', () async {
      final repo = _FakeRepo([
        (results: [server('a')], hasMore: false),
        (results: [server('b')], hasMore: false),
      ]);
      final cubit = PublicServersCubit(repo: repo);

      await cubit.browse();
      cubit.setSort(DirectorySort.fresh);
      await Future<void>.delayed(Duration.zero);

      expect(repo.sorts, [DirectorySort.top, DirectorySort.fresh]);
      expect(cubit.state.results.map((s) => s.id), ['b']);
    });

    test('a like lands with the count central answers', () async {
      final repo = _FakeRepo([
        (results: [server('a'), server('b')], hasMore: false),
      ])..likeAnswer = APIResponse.success(7);
      final cubit = PublicServersCubit(repo: repo);
      await cubit.browse();

      expect(await cubit.toggleLike('a'), isNull);
      final a = cubit.state.results.first;
      expect(a.likedByMe, isTrue);
      expect(a.likeCount, 7);
      expect(cubit.state.results.last.likedByMe, isFalse);
      expect(cubit.state.liking, isEmpty);
    });

    test('a refused like is handed back and leaves the list alone', () async {
      // A refusal (no handle claimed) is not the list failing: the browser
      // keeps its rows and says why once.
      final repo = _FakeRepo([
        (results: [server('a')], hasMore: false),
      ])..likeAnswer = APIResponse.error('Claim a handle first.');
      final cubit = PublicServersCubit(repo: repo);
      await cubit.browse();

      expect(await cubit.toggleLike('a'), 'Claim a handle first.');
      expect(cubit.state.error, isNull);
      expect(cubit.state.results.single.likedByMe, isFalse);
      expect(cubit.state.liking, isEmpty);
    });
  });

  group('PublicServersCubit after the Nov 23 review', () {
    test(
      'a browse that cuts off a page in flight leaves paging working',
      () async {
        // The page in flight was dropped as stale without clearing its flag, so
        // every later loadMore returned early for the rest of the session.
        final repo = _FakeRepo([
          (results: [server('a')], hasMore: true),
          (results: [server('stale')], hasMore: true),
          (results: [server('x')], hasMore: true),
          (results: [server('y')], hasMore: false),
        ]);
        final cubit = PublicServersCubit(repo: repo);
        await cubit.browse();

        repo.holds[1] = Completer<void>();
        final cut = cubit.loadMore();
        await cubit.browse();
        repo.holds[1]!.complete();
        await cut;

        expect(cubit.state.loadingMore, isFalse);
        await cubit.loadMore();
        expect(cubit.state.results.map((s) => s.id), ['x', 'y']);
      },
    );

    test('a slow failure does not replace a newer search\'s results', () async {
      final repo = _FakeRepo([
        (results: [server('ab')], hasMore: false),
        (results: [server('abc')], hasMore: false),
      ]);
      final cubit = PublicServersCubit(repo: repo);

      repo.holds[0] = Completer<void>();
      repo.failing.add(0);
      final slow = cubit.browse();
      await cubit.browse();
      repo.holds[0]!.complete();
      await slow;

      expect(cubit.state.error, isNull);
      expect(cubit.state.results.map((s) => s.id), ['ab']);
    });

    test(
      'a failed further page keeps the list and waits for a retry',
      () async {
        final repo = _FakeRepo([
          (results: [server('a')], hasMore: true),
          (results: [server('b')], hasMore: false),
        ]);
        final cubit = PublicServersCubit(repo: repo);
        await cubit.browse();

        repo.failing.add(1);
        await cubit.loadMore();
        expect(cubit.state.error, isNull, reason: 'the list is not an error');
        expect(cubit.state.moreFailed, isTrue);
        expect(cubit.state.results.map((s) => s.id), ['a']);

        // Scrolling does not ask again; the footer's Try again does.
        await cubit.loadMore();
        expect(repo.offsets, [0, 1]);
        await cubit.loadMore(retry: true);
        expect(cubit.state.moreFailed, isFalse);
        expect(cubit.state.results.map((s) => s.id), ['a', 'b']);
      },
    );

    test('a listing is found however its address is spelled', () async {
      final repo = _FakeRepo([]);
      final cubit = PublicServersCubit(repo: repo);
      cubit.emit(
        cubit.state.copyWith(
          myListings: [
            PublicServer(
              id: 'l',
              serverId: 's',
              ownerId: 'me',
              supabaseUrl: 'https://Example.test/',
              inviteCode: 'code',
              name: 'S',
              isListed: true,
              memberCount: 1,
              updatedAt: DateTime(2026),
            ),
          ],
        ),
      );
      expect(cubit.listingFor('https://example.test', 's')?.id, 'l');
    });
  });

  group('ListingDraft', () {
    test('touches nothing on central until central has answered', () {
      final draft = ListingDraft()..isListed = true;
      expect(draft.touchesDirectory, isFalse);
      draft.seed(null);
      draft.isListed = true;
      expect(draft.touchesDirectory, isTrue);
      draft.dispose();
    });

    test(
      'a late answer about the account switch keeps a change made meanwhile',
      () {
        final draft = ListingDraft()..seed(server('a'));
        draft.needsAccount = true;
        draft.seedNeedsAccount(false);
        expect(draft.needsAccount, isTrue);
        expect(draft.savedNeedsAccount, isFalse);

        final quiet = ListingDraft()..seed(server('a'));
        quiet.seedNeedsAccount(true);
        expect(quiet.needsAccount, isTrue);
        draft.dispose();
        quiet.dispose();
      },
    );

    test(
      'another account\'s listing is not ours to delete or reuse a picture of',
      () {
        final draft = ListingDraft()..seed(server('a'), ownedElsewhere: true);
        expect(draft.ownedElsewhere, isTrue);
        expect(draft.ownedByMe, isFalse);
        draft.seed(server('a'));
        expect(draft.ownedByMe, isTrue);
        draft.seed(null, ownedElsewhere: true);
        expect(draft.ownedElsewhere, isFalse);
        draft.dispose();
      },
    );
  });
}
