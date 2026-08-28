// A bot with a panel: `/poll <question>` posts one, and pressing a button
// redraws it in place rather than posting a new line.
//
//   dart run bot_sdk/example/panel_bot.dart <url> <anonKey> <serverId> <seedFile>
//
// Which is the whole point. A poll that announced every vote as a message
// would be the log a panel exists to replace.
import 'dart:io';

import 'package:rift/data/repositories/crypto_repository.dart';
import 'package:rift_bot/rift_bot.dart';

void main(List<String> args) async {
  final session = BotSession(
    url: args[0],
    anonKey: args[1],
    serverId: args[2],
    seed: CryptoRepository.fromBase64(File(args[3]).readAsStringSync().trim()),
  );
  final bot = Bot(session);

  await session.login();
  await session.publishManifest({
    'description': 'Runs a poll on a panel',
    'commands': [
      {
        'name': 'poll',
        'description': 'Start a poll',
        'usage': '/poll <question>',
      },
    ],
  });

  // Panel id → its question and tallies. In memory, so a restart forgets:
  // this is an example of the shape, not of how to keep state.
  final polls = <int, ({String question, int yes, int no})>{};

  List<Map<String, dynamic>> draw(({String question, int yes, int no}) poll) {
    final total = poll.yes + poll.no;
    return [
      {'type': 'heading', 'text': poll.question},
      {
        'type': 'fields',
        'items': [
          {'label': 'Yes', 'value': '${poll.yes}'},
          {'label': 'No', 'value': '${poll.no}'},
        ],
      },
      {
        'type': 'progress',
        'value': total == 0 ? 0 : poll.yes / total,
        'text': total == 1 ? '1 vote' : '$total votes',
      },
      {
        'type': 'actions',
        'items': [
          {'label': 'Yes', 'action': 'yes', 'style': 'primary'},
          {'label': 'No', 'action': 'no'},
        ],
      },
    ];
  }

  await bot.listen((message) async {
    // A press, not a command. `panelId` is the panel it came from, which is
    // the row to redraw.
    if (message.isAction) {
      final id = message.panelId;
      final poll = id == null ? null : polls[id];
      if (poll == null) return;

      final next = message.actionId == 'yes'
          ? (question: poll.question, yes: poll.yes + 1, no: poll.no)
          : (question: poll.question, yes: poll.yes, no: poll.no + 1);
      polls[id!] = next;
      await bot.editPanel(message.channelId, id, draw(next));
      return;
    }

    if (message.command != 'poll') return;
    final question = message.arguments.isEmpty
        ? 'Yes or no?'
        : message.arguments;
    final poll = (question: question, yes: 0, no: 0);
    final id = await bot.panel(message.channelId, draw(poll));
    if (id != null) polls[id] = poll;
  });

  stdout.writeln('panel bot listening');
}
