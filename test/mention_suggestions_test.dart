import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/mention_suggestions.dart';

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

  group('what picking somebody does to the text', () {
    test('writes the username, not the display name', () {
      // Display names change and collide; the message must not depend on one.
      final out = MentionSuggestions.apply('hi @sa', 6, roster.first);
      expect(out.text, 'hi @charlie ');
      expect(out.cursor, out.text.length);
    });

    test('leaves a trailing space, because the next thing is a word', () {
      expect(MentionSuggestions.apply('@', 1, roster.first).text, '@charlie ');
    });

    test('only replaces the mention, not what surrounds it', () {
      final out = MentionSuggestions.apply('hey @sa there', 7, roster.first);
      expect(out.text, 'hey @charlie  there');
      expect(out.cursor, 'hey @charlie '.length);
    });

    test('a stale press with the caret elsewhere changes nothing', () {
      // The menu can outlive the mention it was opened for.
      final out = MentionSuggestions.apply('done and sent', 13, roster.first);
      expect(out.text, 'done and sent');
    });
  });
}
