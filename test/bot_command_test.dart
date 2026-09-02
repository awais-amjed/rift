import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/bot_manifest.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/services/bot_command.dart';

ServerMember bot(
  String username, {
  List<String> commands = const [],
  String? dataUse,
}) => ServerMember(
  id: 'id-$username',
  username: username,
  displayName: username,
  permissions: const UserPermissions(),
  isBot: true,
  manifest: BotManifest(
    dataUse: dataUse,
    commands: [for (final c in commands) BotCommandSpec(name: c)],
  ),
);

/// Whether a line is a command decides whether it is **encrypted**.
///
/// That is the only reason this is a pure function with its own file: getting
/// it wrong in the quiet direction — a line that should have been sealed going
/// out in the clear — would look like a typo rather than a leak, and nobody
/// would be looking at a widget test to catch it.
void main() {
  group('what is not a command', () {
    final bots = [
      bot('musicbot', commands: ['play', 'skip']),
    ];

    test('an ordinary message', () {
      expect(BotCommands.parse('hello everyone', bots), isNull);
    });

    test('a slash nobody claimed', () {
      // The one that matters. `/shrug` has to go out sealed like anything
      // else — a slash falling through to plaintext because nothing matched
      // is the exact failure this design exists to prevent.
      expect(BotCommands.parse('/shrug', bots), isNull);
    });

    test('a path that happens to start with a slash', () {
      expect(BotCommands.parse('/usr/share/doc is where', bots), isNull);
    });

    test('a half-typed command', () {
      expect(BotCommands.parse('/pl', bots), isNull);
    });

    test('a bare slash', () {
      expect(BotCommands.parse('/', bots), isNull);
      expect(BotCommands.parse('/ ', bots), isNull);
    });

    test('a slash that is not at the start', () {
      expect(BotCommands.parse('see /play in the docs', bots), isNull);
    });

    test('anything at all, when no bots are present', () {
      // Every surface without bots — DMs, central — passes an empty list, and
      // that is what turns the whole path off.
      expect(BotCommands.parse('/play something', const []), isNull);
    });
  });

  group('what is', () {
    final music = bot('musicbot', commands: ['play', 'skip']);
    final bots = [music];

    test('a declared verb resolves to the bot that declared it', () {
      final parsed = BotCommands.parse('/play rick astley', bots);
      expect(parsed, isNotNull);
      expect(parsed!.bot.username, 'musicbot');
      expect(parsed.text, '/play rick astley');
    });

    test('case does not matter', () {
      expect(BotCommands.parse('/PLAY a song', bots)?.bot.username, 'musicbot');
    });

    test('the bot username always works, manifest or not', () {
      // Which is what makes a bot usable before anybody writes an SDK for it.
      final plain = bot('helper');
      expect(
        BotCommands.parse('/helper do the thing', [plain])?.bot.username,
        'helper',
      );
    });

    test('a verb with no arguments is still a command', () {
      expect(BotCommands.parse('/skip', bots), isNotNull);
    });

    test('the whole line is kept, slash included', () {
      // The client does not split arguments, because it does not know what any
      // command's arguments mean.
      expect(BotCommands.parse('  /play a  b  ', bots)?.text, '/play a  b');
    });

    test('two bots claiming one verb resolve stably, in roster order', () {
      final a = bot('alpha', commands: ['play']);
      final b = bot('beta', commands: ['play']);
      expect(BotCommands.parse('/play x', [a, b])?.bot.username, 'alpha');
      expect(BotCommands.parse('/play x', [b, a])?.bot.username, 'beta');
    });

    test('a declared verb beats a bot name', () {
      // `/helper` is both a bot and somebody else's verb; the verb wins, and
      // `/helper` the bot is still reachable by its own name only when nothing
      // declares it.
      final named = bot('helper');
      final claimer = bot('other', commands: ['helper']);
      expect(
        BotCommands.parse('/helper x', [named, claimer])?.bot.username,
        'other',
      );
    });
  });

  group('the menu', () {
    final music = bot('musicbot', commands: ['play', 'skip']);
    final helper = bot('helper');

    test('a bare slash offers everything', () {
      final out = BotCommands.suggest('/', [music, helper]);
      expect(out.map((e) => e.name), ['play', 'skip', 'helper']);
    });

    test('typing narrows it by prefix', () {
      expect(BotCommands.suggest('/pl', [music, helper]).map((e) => e.name), [
        'play',
      ]);
    });

    test('a bot with no manifest is offered under its own name', () {
      // A bot you cannot call is worse than a menu entry with no description.
      expect(BotCommands.suggest('/hel', [music, helper]).map((e) => e.name), [
        'helper',
      ]);
    });

    test('it closes once arguments are being typed', () {
      // Otherwise it would go on offering to replace the verb while somebody
      // is in the middle of writing what comes after it.
      expect(BotCommands.suggest('/play ric', [music]), isEmpty);
    });

    test('nothing is offered without a slash', () {
      expect(BotCommands.suggest('play', [music]), isEmpty);
    });
  });

  group('the manifest', () {
    test('survives a bot that publishes nonsense', () {
      // Written by somebody else's program, so a field of the wrong type is a
      // field to ignore rather than a reason to render nothing.
      final m = BotManifest.fromJson({
        'commands': [
          {'name': 'play'},
          {'name': 42},
          'not a map',
          {'description': 'no name'},
        ],
      });
      expect(m.commands.map((c) => c.name), ['play']);
    });

    test('null is an empty manifest, not a crash', () {
      expect(BotManifest.fromJson(null).commands, isEmpty);
    });

    test('command names are lower-cased on the way in', () {
      final m = BotManifest.fromJson({
        'commands': [
          {'name': 'PLAY'},
        ],
      });
      expect(m.commands.single.name, 'play');
    });
  });

  /// Which commands want the bot in your call.
  ///
  /// It is what stops `/roll 2d6` pulling a program into whatever conversation
  /// the sender happens to be sitting in — a summon seals a media key and puts
  /// a speaker in the room, and doing that for a dice roll is noise nobody
  /// asked for.
  group('a command that wants the bot in your call', () {
    ServerMember music() => ServerMember(
      id: 'id-musicbot',
      username: 'musicbot',
      displayName: 'musicbot',
      permissions: const UserPermissions(),
      isBot: true,
      manifest: const BotManifest(
        commands: [
          BotCommandSpec(name: 'play', needsVoice: true),
          BotCommandSpec(name: 'queue'),
        ],
      ),
    );

    test('the flag is read off the verb that matched', () {
      expect(BotCommands.parse('/play a song', [music()])?.needsVoice, isTrue);
      expect(BotCommands.parse('/queue', [music()])?.needsVoice, isFalse);
    });

    test('a bot addressed by name declares nothing, so it summons nothing', () {
      // `/musicbot play x` resolves by username and carries no manifest entry
      // to read the flag from. Guessing yes here would summon on every
      // by-name command, which is every command a bot with no manifest has.
      expect(
        BotCommands.parse('/musicbot play a song', [music()])?.needsVoice,
        isFalse,
      );
    });

    test('it survives the wire, and defaults to off', () {
      final m = BotManifest.fromJson({
        'commands': [
          {'name': 'play', 'voice': true},
          {'name': 'roll'},
          {'name': 'skip', 'voice': 'yes please'},
        ],
      });
      expect(m.commands[0].needsVoice, isTrue);
      expect(m.commands[1].needsVoice, isFalse);
      // Tolerant like the rest of the manifest: somebody else's program wrote
      // this, so a field of the wrong type is a field to ignore.
      expect(m.commands[2].needsVoice, isFalse);
    });

    test('and round-trips, without writing the default out', () {
      const spec = BotCommandSpec(name: 'play', needsVoice: true);
      expect(spec.toJson()['voice'], true);
      expect(
        const BotCommandSpec(name: 'roll').toJson().containsKey('voice'),
        isFalse,
      );
    });
  });
}
