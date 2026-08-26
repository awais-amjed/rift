// A whole Rift bot.
//
//   dart run example/echo_bot.dart <serverUrl> <anonKey> <serverId> <seedFile>
//
// It answers two commands and shows the three things every bot has to get
// right: publish what you answer to, reply in the channel when the room wants
// the answer, and reply privately when it does not.
import 'dart:io';

import 'package:rift/data/repositories/crypto_repository.dart';
import 'package:rift_bot/rift_bot.dart';

Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln(
      'usage: echo_bot <serverUrl> <anonKey> <serverId> <seedFile>',
    );
    exit(64);
  }
  final [url, anonKey, serverId, seedFile] = args;

  // The bot's whole identity. Generated once, kept out of the repo, and
  // treated like an SSH key: whoever has it is the bot.
  final seed = CryptoRepository.fromBase64(
    File(seedFile).readAsStringSync().trim(),
  );

  final session = BotSession(
    url: url,
    anonKey: anonKey,
    serverId: serverId,
    seed: seed,
  );
  final bot = Bot(session);

  await session.login();

  // What the `/` menu offers while this process is asleep, and — the part
  // worth more than any of the crypto — what people are told this bot does
  // with what they hand it, before they type it.
  await session.publishManifest({
    'description': 'Says things back to you',
    'data_use': 'Nothing leaves this server. The bot only echoes.',
    'commands': [
      {
        'name': 'echo',
        'description': 'Say something back to the channel',
        'usage': '/echo <text>',
      },
      {
        'name': 'whisper',
        'description': 'Say something back to you alone',
        'usage': '/whisper <text>',
      },
    ],
  });

  stdout.writeln('echo bot is ${session.userId}, listening…');

  await bot.listen((message) async {
    stdout.writeln('  ${message.command}: ${message.arguments}');
    switch (message.command) {
      case 'echo':
        await bot.reply(
          message,
          message.arguments.isEmpty ? 'Echo what?' : message.arguments,
        );
      case 'whisper':
        // Only the person who asked sees this one. Not hidden by clients
        // agreeing to hide it — the row never reaches anybody else.
        await bot.replyPrivately(
          message,
          message.arguments.isEmpty
              ? 'Whisper what?'
              : 'Between us: ${message.arguments}',
        );
      default:
        await bot.replyPrivately(
          message,
          "I don't know /${message.command}. Try /echo or /whisper.",
        );
    }
  });
}
