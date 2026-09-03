import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/member_page.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/member_roster_pager.dart';

ServerMember member(String name) => ServerMember(
  id: name,
  username: name.toLowerCase(),
  displayName: name,
  permissions: const UserPermissions(),
);

MemberPage page(List<String> names, {required bool hasMore}) =>
    MemberPage(members: [for (final n in names) member(n)], hasMore: hasMore);

void main() {
  group('MemberRosterPager', () {
    test('the first call fetches the first page', () async {
      final asked = <({String name, String id})?>[];
      final pager = MemberRosterPager(
        fetchPage: (after) async {
          asked.add(after);
          return page(['Alice', 'Bob'], hasMore: false);
        },
      );

      expect(pager.hasMore, isTrue, reason: 'nothing asked for yet');
      expect(await pager.next(), isTrue);
      expect(asked, [null]);
      expect(pager.loaded.members.map((m) => m.displayName), ['Alice', 'Bob']);
      expect(pager.hasMore, isFalse);
      expect(pager.isLoaded, isTrue);
    });

    test(
      'the next page resumes after the last row, not at an offset',
      () async {
        final asked = <({String name, String id})?>[];
        var call = 0;
        final pager = MemberRosterPager(
          fetchPage: (after) async {
            asked.add(after);
            return call++ == 0
                ? page(['Alice'], hasMore: true)
                : page(['Bob'], hasMore: false);
          },
        );

        await pager.next();
        await pager.next();
        expect(asked[1], (name: 'Alice', id: 'Alice'));
        expect(pager.loaded.members.map((m) => m.displayName), [
          'Alice',
          'Bob',
        ]);
      },
    );

    test('asking past the end does nothing', () async {
      var calls = 0;
      final pager = MemberRosterPager(
        fetchPage: (after) async {
          calls++;
          return page(['Alice'], hasMore: false);
        },
      );

      await pager.next();
      expect(await pager.next(), isFalse);
      expect(calls, 1);
    });

    test('a second call while one is in flight is dropped', () async {
      // The case a scroll listener hits constantly: it fires per frame, and
      // without the guard each frame would launch its own duplicate page.
      final gate = Completer<MemberPage?>();
      var calls = 0;
      final pager = MemberRosterPager(
        fetchPage: (after) {
          calls++;
          return gate.future;
        },
      );

      final first = pager.next();
      expect(await pager.next(), isFalse);
      expect(calls, 1);

      gate.complete(page(['Alice'], hasMore: false));
      expect(await first, isTrue);
    });

    test('a page landing after a reset is thrown away', () async {
      // Switching servers mid-fetch. The old answer must not be appended to
      // the new list — that is how a sidebar ends up showing two servers.
      final gate = Completer<MemberPage?>();
      final pager = MemberRosterPager(fetchPage: (after) => gate.future);

      final inFlight = pager.next();
      pager.reset();
      gate.complete(page(['Alice'], hasMore: false));

      expect(await inFlight, isFalse);
      expect(pager.loaded.members, isEmpty);
      expect(pager.hasMore, isTrue, reason: 'reset starts over, not ends');
    });

    test('a failed page stops the walk without claiming the end', () async {
      var calls = 0;
      final pager = MemberRosterPager(
        fetchPage: (after) async =>
            calls++ == 0 ? null : page(['Alice'], hasMore: false),
      );

      expect(await pager.next(), isFalse);
      expect(pager.isLoaded, isFalse);
      expect(pager.hasMore, isTrue, reason: 'a failure is retryable');

      expect(await pager.next(), isTrue);
      expect(pager.loaded.members, hasLength(1));
    });

    test('an empty server is loaded, not still loading', () async {
      final pager = MemberRosterPager(
        fetchPage: (after) async => page(const [], hasMore: false),
      );

      await pager.next();
      expect(pager.loaded.members, isEmpty);
      expect(pager.isLoaded, isTrue);
      expect(pager.hasMore, isFalse);
    });
  });
}
