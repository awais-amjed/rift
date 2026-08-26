import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/notification_level.dart';

/// One setting read by four things that must agree — the ring trigger, the
/// desktop notifier, the badge, and the push isolate. These are about the
/// parts they agree *on*: what the names are, what the defaults are, and what
/// each level lets through.
void main() {
  group('parse', () {
    test('reads the names the schemas use', () {
      for (final level in NotificationLevel.values) {
        expect(
          NotificationLevel.parse(level.name, fallback: NotificationLevel.all),
          level,
        );
      }
    });

    test('anything unrecognised falls back rather than guessing', () {
      for (final raw in [
        null,
        '',
        'ALL',
        'quiet',
        7,
        ['all'],
      ]) {
        expect(
          NotificationLevel.parse(raw, fallback: NotificationLevel.mentions),
          NotificationLevel.mentions,
          reason: 'for $raw',
        );
      }
    });

    test('round-trips through toJson', () {
      for (final level in NotificationLevel.values) {
        expect(
          NotificationLevel.parse(
            level.toJson(),
            fallback: NotificationLevel.none,
          ),
          level,
        );
      }
    });
  });

  group('defaults', () {
    test('a channel is mentions-only and a DM is everything', () {
      expect(NotificationLevel.channelDefault, NotificationLevel.mentions);
      expect(NotificationLevel.dmDefault, NotificationLevel.all);
    });

    test('a server has no opinion until somebody gives it one', () {
      // And the level standing in for "no opinion" has to be the one a channel
      // would have picked anyway, or the server menu would be showing a level
      // that nothing on the server is actually at. This is the assertion that
      // fails if the two ever drift apart.
      expect(NotificationLevel.serverDefault, NotificationLevel.channelDefault);
      expect(NotificationLevel.serverDefault, NotificationLevel.mentions);
    });

    test('turning a whole server up is a real setting, not the default', () {
      // Which is what makes it worth storing: picking `all` on a server has to
      // reach the channels inside it, or the menu row does nothing.
      expect(NotificationLevel.serverDefault, isNot(NotificationLevel.all));
      expect(
        NotificationLevel.resolve(
          scope: null,
          server: NotificationLevel.all,
          fallback: NotificationLevel.channelDefault,
        ),
        NotificationLevel.all,
      );
    });

    test('a DM is not offered a level that would behave like another', () {
      expect(
        NotificationLevel.dmChoices,
        isNot(contains(NotificationLevel.mentions)),
      );
      expect(NotificationLevel.channelChoices, hasLength(3));
    });
  });

  group('announces', () {
    test('all lets everything through', () {
      expect(NotificationLevel.all.announces(mentioned: false), isTrue);
      expect(NotificationLevel.all.announces(mentioned: true), isTrue);
    });

    test('mentions lets through only what named you', () {
      expect(NotificationLevel.mentions.announces(mentioned: false), isFalse);
      expect(NotificationLevel.mentions.announces(mentioned: true), isTrue);
    });

    test('none lets nothing through, being named included', () {
      expect(NotificationLevel.none.announces(mentioned: true), isFalse);
      expect(NotificationLevel.none.announces(mentioned: false), isFalse);
    });

    test('only none counts as muted', () {
      expect(NotificationLevel.none.isMuted, isTrue);
      expect(NotificationLevel.all.isMuted, isFalse);
      expect(NotificationLevel.mentions.isMuted, isFalse);
    });
  });

  group('mapFrom', () {
    test('reads a prefs map', () {
      final levels = NotificationLevel.mapFrom({
        'a': 'none',
        'b': 'all',
      }, fallback: NotificationLevel.mentions);
      expect(levels, {'a': NotificationLevel.none, 'b': NotificationLevel.all});
    });

    test('drops entries that say the default, so absent means default', () {
      final levels = NotificationLevel.mapFrom({
        'a': 'mentions',
        'b': 'none',
      }, fallback: NotificationLevel.mentions);
      expect(levels.containsKey('a'), isFalse);
      expect(levels['b'], NotificationLevel.none);
    });

    test('one bad entry cannot cost the others', () {
      final levels = NotificationLevel.mapFrom({
        'a': 'none',
        7: 'none',
        'c': 'nonsense',
      }, fallback: NotificationLevel.all);
      expect(levels, {'a': NotificationLevel.none});
    });

    test('anything that is not a map is no levels at all', () {
      for (final raw in [
        null,
        'none',
        42,
        <String>['a'],
      ]) {
        expect(
          NotificationLevel.mapFrom(raw, fallback: NotificationLevel.all),
          isEmpty,
          reason: 'for $raw',
        );
      }
    });
  });

  group('resolve — the fallback chain', () {
    test('the scope wins when it has an opinion', () {
      expect(
        NotificationLevel.resolve(
          scope: NotificationLevel.all,
          server: NotificationLevel.none,
          fallback: NotificationLevel.mentions,
        ),
        NotificationLevel.all,
        reason: 'a channel turned up inside a muted server stays up',
      );
    });

    test('the server answers for a scope that has no opinion', () {
      expect(
        NotificationLevel.resolve(
          scope: null,
          server: NotificationLevel.none,
          fallback: NotificationLevel.mentions,
        ),
        NotificationLevel.none,
      );
    });

    test('the default answers when nobody has one', () {
      expect(
        NotificationLevel.resolve(
          scope: null,
          server: null,
          fallback: NotificationLevel.mentions,
        ),
        NotificationLevel.mentions,
      );
    });
  });

  group('tryParse', () {
    test('tells "not set" from "set to something"', () {
      expect(NotificationLevel.tryParse('none'), NotificationLevel.none);
      expect(NotificationLevel.tryParse('nonsense'), isNull);
      expect(NotificationLevel.tryParse(null), isNull);
    });
  });

  group('mapFrom with no fallback', () {
    test('keeps every level, because none of them is an absence', () {
      // What the server scope wants: `all` there is somebody saying "tell me
      // everything on this server", not the absence of an opinion.
      final levels = NotificationLevel.mapFrom({
        's1': 'all',
        's2': 'none',
      }, fallback: null);
      expect(levels, {
        's1': NotificationLevel.all,
        's2': NotificationLevel.none,
      });
    });

    test('still drops what it cannot read', () {
      expect(
        NotificationLevel.mapFrom({'s1': 'loud'}, fallback: null),
        isEmpty,
      );
    });
  });
}
