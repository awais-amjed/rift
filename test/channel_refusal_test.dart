import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/apis/channels_api.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/enums/error_code.dart';

/// A channel write the server refused reaches the person in words: a rename
/// onto a taken name used to read `duplicate key value violates unique
/// constraint "channels_server_id_name_key"`.
void main() {
  APIResponse refused(String? code, [String? error]) =>
      APIResponse(success: false, error: error ?? 'raw', errorCode: code);

  test('Postgres and RPC refusals are put into words', () {
    expect(
      channelRefusal(
        refused('23505', 'duplicate key value violates unique constraint'),
        'Failed',
      ),
      'A channel already has that name',
    );
    expect(
      channelRefusal(refused('not_authorized'), 'Failed'),
      "You don't have permission to do that here",
    );
    expect(
      channelRefusal(refused('42501'), 'Failed'),
      "You don't have permission to do that here",
    );
    expect(
      channelRefusal(refused(ErrorCode.channelNotFound), 'Failed'),
      'That channel is gone',
    );
    expect(channelRefusal(refused('bad_name'), 'Failed'), 'Give it a name');
  });

  test('an unknown refusal is the fallback, never the raw text', () {
    expect(
      channelRefusal(refused('P0001', 'some internal text'), 'Failed'),
      'Failed',
    );
    expect(
      channelRefusal(refused(null, 'some internal text'), 'Failed'),
      'Failed',
    );
  });

  test('what the connection said is already a sentence, and is passed on', () {
    expect(
      channelRefusal(
        refused(ErrorCode.serverUnreachable, "Can't reach this server."),
        'Failed',
      ),
      "Can't reach this server.",
    );
    expect(
      channelRefusal(
        refused(ErrorCode.functionMissing, 'This server needs an update'),
        'Failed',
      ),
      'This server needs an update',
    );
  });

  test('a voice channel is named without a #', () {
    const text = Channel(
      id: 't',
      name: 'general',
      channelType: ChannelType.text,
    );
    const voice = Channel(
      id: 'v',
      name: 'Lounge',
      channelType: ChannelType.voice,
    );
    expect(text.label, '#general');
    expect(voice.label, 'Lounge');
  });
}
