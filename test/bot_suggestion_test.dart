import 'package:flutter/painting.dart' show TextRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/bot_manifest.dart';
import 'package:rift/data/classes/bot_suggestion.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/bot_command.dart';

ServerMember bot(String username, List<BotCommandSpec> commands) =>
    ServerMember(
      id: 'id-$username',
      username: username,
      displayName: username,
      permissions: const UserPermissions(),
      isBot: true,
      manifest: BotManifest(commands: commands),
    );

/// Suggestions are the one time the composer sends a bot anything before
/// Enter, so *when* it asks is the property worth pinning down (WIRE.md §7).
void main() {
  final music = bot('musicbot', const [
    BotCommandSpec(name: 'play', suggests: true),
    BotCommandSpec(name: 'skip'),
  ]);

  group('when the composer asks', () {
    test('a suggesting verb, a space and words', () {
      final q = BotCommands.suggestionQuery('/play thats so tr', [music])!;
      expect(q.bot, music);
      expect(q.command, 'play');
      expect(q.query, 'thats so tr');
    });

    test('the verb is matched however it was capitalised', () {
      expect(
        BotCommands.suggestionQuery('/Play abc', [music])?.command,
        'play',
      );
    });

    test('nothing before the space, or nothing after it', () {
      expect(BotCommands.suggestionQuery('/pla', [music]), isNull);
      expect(BotCommands.suggestionQuery('/play', [music]), isNull);
      expect(BotCommands.suggestionQuery('/play   ', [music]), isNull);
    });

    test('a verb that did not switch suggestions on', () {
      expect(BotCommands.suggestionQuery('/skip now', [music]), isNull);
    });

    test('an ordinary message, or a bot addressed by name', () {
      expect(
        BotCommands.suggestionQuery('play thats so true', [music]),
        isNull,
      );
      expect(BotCommands.suggestionQuery('/musicbot play x', [music]), isNull);
    });

    test('the bot a send would go to, even when it is the one not offering', () {
      // Two bots claim /play; the first is the one `parse` addresses, so it is
      // the only one to ask — and it offers nothing.
      final quiet = bot('aquiet', const [BotCommandSpec(name: 'play')]);
      expect(BotCommands.suggestionQuery('/play x', [quiet, music]), isNull);
    });

    test('a line longer than a request may carry', () {
      expect(
        BotCommands.suggestionQuery('/play ${'x' * 201}', [music]),
        isNull,
      );
    });
  });

  group('where the command is drawn', () {
    final player = bot('musicbot', const [
      BotCommandSpec(name: 'play', usage: '<song, artist or link>'),
    ]);

    test('the verb and what follows its space, with the verb\'s usage', () {
      final shape = BotCommands.shapeOf('/play thats so', [player])!;
      expect(shape.verb, const TextRange(start: 0, end: 5));
      expect(shape.argument, const TextRange(start: 6, end: 14));
      expect(shape.usage, '<song, artist or link>');
    });

    test('an empty argument right after the space, for the placeholder', () {
      final shape = BotCommands.shapeOf('/play ', [player])!;
      expect(shape.argument, const TextRange(start: 6, end: 6));
    });

    test('the argument starts at its first word, past extra spaces', () {
      expect(
        BotCommands.shapeOf('  /play   x', [player])!.argument,
        const TextRange(start: 10, end: 11),
      );
    });

    test('not while the verb is still being typed', () {
      expect(BotCommands.shapeOf('/play', [player]), isNull);
      expect(BotCommands.shapeOf('/pl', [player]), isNull);
    });

    test('nothing that would not go out as a command', () {
      // Drawn as a command only when it is one: `/shrug x` is sealed text.
      expect(BotCommands.shapeOf('/shrug x', [player]), isNull);
      expect(BotCommands.shapeOf('hi /play x', [player]), isNull);
      expect(BotCommands.shapeOf('/ x', [player]), isNull);
    });

    test('a bot called by its own name, with no usage to offer', () {
      final shape = BotCommands.shapeOf('/musicbot play x', [player])!;
      expect(shape.verb, const TextRange(start: 0, end: 9));
      expect(shape.usage, isNull);
    });
  });

  group('which answer is taken', () {
    Map<String, dynamic> answer({
      Object? v = 1,
      Object? id = 'req-1234',
      Object? botId = 'id-musicbot',
      Object? items,
    }) => {
      'v': v,
      'id': id,
      'bot': botId,
      'items':
          items ??
          [
            {'label': 'That’s So True — Gracie Abrams · 2:47', 'value': 'link'},
          ],
    };

    test('the one naming this request and this bot', () {
      expect(
        BotSuggestion.fromAnswer(
          answer(),
          id: 'req-1234',
          botId: 'id-musicbot',
        ),
        [
          const BotSuggestion(
            label: 'That’s So True — Gracie Abrams · 2:47',
            value: 'link',
          ),
        ],
      );
    });

    test('not one naming another request, another bot, or another version', () {
      for (final other in [
        answer(id: 'req-9999'),
        answer(id: null),
        answer(botId: 'id-otherbot'),
        answer(v: 2),
        answer(items: 'nope'),
      ]) {
        expect(
          BotSuggestion.fromAnswer(other, id: 'req-1234', botId: 'id-musicbot'),
          isNull,
        );
      }
    });

    test('a bad row is dropped, not the answer', () {
      final rows = BotSuggestion.fromAnswer(
        answer(
          items: [
            {'label': 'Fine', 'value': 'ok'},
            {'label': 'Second line', 'value': 'a\nb'},
            {'label': '', 'value': 'x'},
            {'label': 'No value'},
            'not a row',
            {'label': 'L' * 101, 'value': 'long label'},
          ],
        ),
        id: 'req-1234',
        botId: 'id-musicbot',
      )!;
      expect(rows.map((r) => r.value), ['ok']);
    });

    test('ten at most', () {
      final rows = BotSuggestion.fromAnswer(
        answer(
          items: [
            for (var i = 0; i < 15; i++) {'label': 'Song $i', 'value': 'v$i'},
          ],
        ),
        id: 'req-1234',
        botId: 'id-musicbot',
      )!;
      expect(rows, hasLength(10));
    });
  });

  test('the manifest flag survives a round trip', () {
    final spec = BotCommandSpec.fromJson({'name': 'play', 'suggest': true});
    expect(spec.suggests, isTrue);
    expect(spec.toJson()['suggest'], isTrue);
    expect(
      BotCommandSpec.fromJson({'name': 'skip'}).toJson().containsKey('suggest'),
      isFalse,
    );
  });
}
