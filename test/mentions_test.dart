import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/mentions.dart';

/// Who a message names, and what counts as "you".
///
/// The one place in the app that answers either question, because the sender's
/// composer, the renderer, the desktop notifier and the push isolate all ask
/// it and any disagreement between two of them is somebody missing a ping or
/// getting one nobody sent.
void main() {
  const roster = {'alice': 'id-alice', 'bob': 'id-bob', 'carol': 'id-carol'};

  MentionTargets resolve(String text, {String? me}) =>
      Mentions.resolve(text, idsByUsername: roster, excludeUserId: me);

  group('resolve', () {
    test('finds a name on the roster', () {
      expect(resolve('hey @alice').userIds, ['id-alice']);
    });

    test('ignores a name nobody answers to', () {
      final named = resolve('hey @nobody and @alice');
      expect(named.userIds, ['id-alice']);
      expect(named.all, isFalse);
    });

    test('is case-insensitive on both sides', () {
      expect(resolve('@ALICE').userIds, ['id-alice']);
      expect(
        Mentions.resolve(
          '@alice',
          idsByUsername: const {'Alice': 'id-alice'},
        ).userIds,
        ['id-alice'],
      );
    });

    test('names each person once, however often they are named', () {
      expect(resolve('@bob @bob @bob').userIds, ['id-bob']);
    });

    test('drops the sender — a message never pings its own author', () {
      expect(resolve('@alice @bob', me: 'id-alice').userIds, ['id-bob']);
    });

    test('an empty message names nobody', () {
      expect(resolve('').userIds, isEmpty);
      expect(resolve('').all, isFalse);
    });
  });

  group('@all', () {
    test('is a flag, not everybody listed', () {
      final named = resolve('@all standup in 5');
      expect(named.all, isTrue);
      expect(named.userIds, isEmpty);
    });

    test('rides alongside named people', () {
      final named = resolve('@all and especially @carol');
      expect(named.all, isTrue);
      expect(named.userIds, ['id-carol']);
    });
  });

  group('what the parser refuses to call a mention', () {
    test('inside a code span', () {
      expect(resolve('try `@alice` in the docs').userIds, isEmpty);
      expect(resolve('```\n@all\n```').all, isFalse);
    });

    test('escaped', () {
      expect(resolve(r'\@alice is how you write it').userIds, isEmpty);
    });

    test('mid-word, which is what an email address looks like', () {
      expect(resolve('write to me@alice.dev').userIds, isEmpty);
    });

    test('but a mention inside bold is still a mention', () {
      expect(resolve('**@bob**').userIds, ['id-bob']);
    });
  });

  group('cap', () {
    test('stops at the ceiling the database also applies', () {
      final many = {
        for (var i = 0; i < Mentions.maxTargets + 20; i++) 'u$i': 'id-$i',
      };
      final text = many.keys.map((n) => '@$n').join(' ');
      final named = Mentions.resolve(text, idsByUsername: many);
      expect(named.userIds, hasLength(Mentions.maxTargets));
    });
  });

  group('mentionableFor', () {
    test('always includes @all — being in the room is being named', () {
      expect(Mentions.mentionableFor('alice'), {'all', 'alice'});
    });

    test('lower-cases the name, so the roster spelling does not matter', () {
      expect(Mentions.mentionableFor('Alice'), contains('alice'));
    });

    test('an anonymous reader is still reached by @all', () {
      expect(Mentions.mentionableFor(null), {'all'});
      expect(Mentions.mentionableFor('  '), {'all'});
    });
  });

  group('namesMe', () {
    test('by username', () {
      expect(Mentions.namesMe('ping @bob', username: 'bob'), isTrue);
      expect(Mentions.namesMe('ping @bob', username: 'alice'), isFalse);
    });

    test('by @all, for everybody in the room', () {
      expect(Mentions.namesMe('@all please read', username: 'alice'), isTrue);
    });

    test('not by an ordinary line', () {
      expect(Mentions.namesMe('morning everyone', username: 'alice'), isFalse);
    });
  });

  group('rosterOf', () {
    ServerMember member(String id, String username) => ServerMember(
      id: id,
      username: username,
      displayName: 'Display Name',
      permissions: const UserPermissions(),
    );

    test('keys by username, not display name', () {
      // Display names can be changed by their owner and can collide; keying on
      // one would ping whoever happened to share it.
      final roster = Mentions.rosterOf([
        member('id-a', 'alice'),
        member('id-b', 'bob'),
      ]);
      expect(roster, {'alice': 'id-a', 'bob': 'id-b'});
      expect(roster.containsKey('Display Name'), isFalse);
    });

    test('an empty roster names nobody rather than throwing', () {
      expect(Mentions.rosterOf(const []), isEmpty);
      expect(
        Mentions.resolve(
          '@alice',
          idsByUsername: Mentions.rosterOf(const []),
        ).userIds,
        isEmpty,
      );
    });
  });
}
