import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/mention_suggestions.dart';
import 'package:rift/logic/services/mentions.dart';

/// The `@` menu's logic, without a composer.
///
/// The half worth testing is not "does a list appear" — it is where the caret
/// counts as being inside a mention, and what the text looks like afterwards.
/// Both are invisible until they are wrong, and then they are wrong while
/// somebody is in the middle of a sentence.
void main() {
  ServerMember member(String username, String displayName, {String? id}) =>
      ServerMember(
        id: id ?? username,
        username: username,
        displayName: displayName,
        permissions: UserPermissions(),
      );

  final roster = [
    member('charlie', 'Sam'),
    member('animbot', 'Anim Bot'),
    member('hookw', 'Hook Watcher'),
    member('sammy', 'Sammy Davis'),
  ];

  group('where the caret counts as a mention', () {
    test('right after the @', () {
      expect(MentionSuggestions.queryAt('hi @', 4), '');
    });

    test('part-way through a name', () {
      expect(MentionSuggestions.queryAt('hi @sa', 6), 'sa');
    });

    test('not once there is a space — the name is settled', () {
      // Otherwise the menu keeps offering to replace a finished sentence.
      expect(MentionSuggestions.queryAt('hi @sam and', 11), isNull);
    });

    test('not inside an email address', () {
      // `a@b.com` is an address. The parser that draws the message agrees, so
      // the menu has to as well or it offers a mention that will never render.
      expect(MentionSuggestions.queryAt('mail me at a@b', 14), isNull);
    });

    test('after punctuation, which is a word boundary', () {
      expect(MentionSuggestions.queryAt('(@sa', 4), 'sa');
    });

    test('the @ before the caret is the one that counts', () {
      expect(MentionSuggestions.queryAt('@one @tw', 8), 'tw');
    });
  });

  group('who a query offers', () {
    test('an empty query offers everybody', () {
      expect(MentionSuggestions.suggest('', roster).length, 4);
    });

    test('matches a display name, not just a username', () {
      // The whole point: you type the name you know.
      final out = MentionSuggestions.suggest('anim', roster);
      expect(out.single.username, 'animbot');
    });

    test('a two-word display name is reachable without a space', () {
      // A mention token cannot contain a space, so "Hook Watcher" has no other
      // way to be typed.
      expect(
        MentionSuggestions.suggest('hookw', roster).first.username,
        'hookw',
      );
      expect(
        MentionSuggestions.suggest('hookwat', roster).single.displayName,
        'Hook Watcher',
      );
    });

    test('a prefix beats a match in the middle', () {
      final out = MentionSuggestions.suggest('sam', roster);
      expect(out.first.displayName, 'Sam');
    });

    test('the sender is left out, because pinging yourself is a mistake', () {
      final out = MentionSuggestions.suggest(
        'sam',
        roster,
        excludeUserId: 'charlie',
      );
      expect(out.map((m) => m.username), isNot(contains('charlie')));
    });
  });

  group('what a pick writes into the field', _wireTests);

  group('bots are addressed with a slash, not an at', _botTests);

  group('who may be named at all', _audienceTests);

  group('what picking somebody does to the text', () {
    test('writes the display name, which is what the writer is reading', () {
      // The username arrives later, in toWire — a text field cannot show one
      // string and hold another without the caret landing in the wrong place.
      final out = MentionSuggestions.apply('hi @sa', 6, roster.first);
      expect(out.text, 'hi @Sam ');
      expect(out.cursor, out.text.length);
    });

    test('leaves a trailing space, because the next thing is a word', () {
      expect(MentionSuggestions.apply('@', 1, roster.first).text, '@Sam ');
    });

    test('only replaces the mention, not what surrounds it', () {
      final out = MentionSuggestions.apply('hey @sa there', 7, roster.first);
      expect(out.text, 'hey @Sam  there');
      expect(out.cursor, 'hey @Sam '.length);
    });

    test('a stale press with the caret elsewhere changes nothing', () {
      // The menu can outlive the mention it was opened for.
      final out = MentionSuggestions.apply('done and sent', 13, roster.first);
      expect(out.text, 'done and sent');
    });
  });
}

/// Turning what the writer sees into what the message carries.
///
/// The field holds display names, because `@schematest` about somebody the room
/// calls Awais is a name you translate while writing. The message holds
/// usernames, because a display name can be changed by its owner and can
/// collide. This is the swap between them, and it only ever touches names
/// somebody actually picked.
void _wireTests() {
  test('a picked name becomes the username', () {
    final out = MentionSuggestions.toWire('@Awais hello', {
      'Awais': 'schematest',
    });
    expect(out, '@schematest hello');
  });

  test('a display name with a space survives the swap', () {
    // The mention token cannot contain a space, so this is the only way a
    // two-word name ever reaches the wire correctly.
    final out = MentionSuggestions.toWire('hi @Anim Bot', {
      'Anim Bot': 'animbot',
    });
    expect(out, 'hi @animbot');
  });

  test('a name typed by hand is left alone', () {
    // The composer never established which person it meant, and guessing is how
    // a message pings a stranger who happens to share a name.
    expect(MentionSuggestions.toWire('@Awais hi', const {}), '@Awais hi');
  });

  test('the longer name wins where one contains the other', () {
    final out = MentionSuggestions.toWire('@Sam Two and @Sam', {
      'Sam': 'charlie',
      'Sam Two': 'sam2',
    });
    expect(out, '@sam2 and @charlie');
  });

  test('every occurrence of the same person is swapped', () {
    final out = MentionSuggestions.toWire('@Awais and @Awais', {
      'Awais': 'schematest',
    });
    expect(out, '@schematest and @schematest');
  });

  test('a name with regex characters is matched literally', () {
    // Display names are whatever a person can type.
    final out = MentionSuggestions.toWire('@A.(B)+ hi', {'A.(B)+': 'weird'});
    expect(out, '@weird hi');
  });
}

/// A bot is not mentionable, on any surface.
///
/// BOTS.md §4: a normal message that mentions a bot does nothing. It only ever
/// receives what is addressed to it with `/`, and `messages_select` will not
/// return anything else however the text is written. Two messages that look
/// identical must not have different protection.
///
/// The refusal has to hold everywhere or it becomes a lie somewhere — a menu
/// that offers a bot, a name lit up as though it arrived, a mention recorded in
/// the clear that wakes nobody.
void _botTests() {
  ServerMember bot(String username, String displayName) => ServerMember(
    id: username,
    username: username,
    displayName: displayName,
    permissions: UserPermissions(),
    isBot: true,
  );
  ServerMember person(String username, String displayName) => ServerMember(
    id: username,
    username: username,
    displayName: displayName,
    permissions: UserPermissions(),
  );

  final roster = [person('charlie', 'Sam'), bot('animbot', 'Anim Bot')];

  test('a bot is not among the people a message can name', () {
    expect(Mentions.among(roster).map((m) => m.username), ['charlie']);
  });

  test('and so never reaches the roster a send resolves against', () {
    // Otherwise a bot's id travels in the clear on `messages.mentions` to wake
    // somebody who has no phone.
    expect(Mentions.rosterOf(roster).keys, ['charlie']);
  });

  test('a message naming a bot names nobody', () {
    final named = Mentions.resolve(
      '@animbot play something',
      idsByUsername: Mentions.rosterOf(roster),
    );
    expect(named.userIds, isEmpty);
    expect(named.all, isFalse);
  });

  test('the menu offers people, and the `/` menu offers bots', () {
    // The composer is handed an already-filtered roster; this is the filter.
    final out = MentionSuggestions.suggest('a', Mentions.among(roster));
    expect(out.map((m) => m.username), isNot(contains('animbot')));
  });
}

/// In a private channel, only the people who can open it — and that rule now
/// lives in the query.
///
/// `validate_message_mentions` strips the rest: it keeps only
/// ids passing `app.channel_eligible`. That is silent, so a composer offering
/// the whole server let somebody pick a name, watch it highlight, and never
/// learn the ping was dropped.
///
/// The client used to answer it with a filter over the roster it held. It no
/// longer holds one, so every caller asks `search_members` or
/// `members_by_usernames` **with the channel** and what comes back is already
/// only people a message here reaches. The rule is tested where it is now
/// enforced — `policies_test.sql` §18 and §23. What is left here is the part
/// the client still decides.
void _audienceTests() {
  ServerMember person(String username) => ServerMember(
    id: username,
    username: username,
    displayName: username.toUpperCase(),
    permissions: UserPermissions(),
  );

  final roster = [person('inside'), person('outside')];

  test('everybody the query returned can be named', () {
    expect(Mentions.among(roster).map((m) => m.username), [
      'inside',
      'outside',
    ]);
  });

  test('and resolves into a mention on send', () {
    final named = Mentions.resolve(
      'hi @outside and @inside',
      idsByUsername: Mentions.rosterOf(roster),
    );
    expect(named.userIds, ['outside', 'inside']);
  });

  test('a bot is still not mentionable, wherever it came from', () {
    // The one refusal that is the client's. A bot is addressed with `/`, and
    // the channel-scoped query returns bots because they hold keys — so this
    // filter is what stops the `@` menu teaching a habit that does nothing
    // (BOTS.md §4).
    final bot = ServerMember(
      id: 'musicbot',
      username: 'musicbot',
      displayName: 'musicbot',
      permissions: UserPermissions(),
      isBot: true,
    );

    expect(Mentions.among([...roster, bot]).map((m) => m.id), [
      'inside',
      'outside',
    ]);
    expect(
      Mentions.rosterOf([...roster, bot]).keys,
      isNot(contains('musicbot')),
    );
  });
}
