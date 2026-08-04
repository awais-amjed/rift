import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/services/channel_search.dart';

Channel _channel(String name) =>
    Channel(id: name, name: name, channelType: ChannelType.text);

List<String> _names(List<Channel> channels) => [
  for (final c in channels) c.name,
];

void main() {
  final channels = [
    _channel('design-general'),
    _channel('general'),
    _channel('random'),
    _channel('Announcements'),
  ];

  test('an empty query keeps every channel, in order', () {
    expect(_names(ChannelSearch.filter(channels, '')), [
      'design-general',
      'general',
      'random',
      'Announcements',
    ]);
    expect(_names(ChannelSearch.filter(channels, '   ')).length, 4);
  });

  test('a prefix match outranks a mid-name match', () {
    // The whole point of the ranking: typing "gen" should land on #general
    // even though #design-general comes first in the server's own order.
    expect(_names(ChannelSearch.filter(channels, 'gen')), [
      'general',
      'design-general',
    ]);
  });

  test('matching ignores case in both directions', () {
    expect(_names(ChannelSearch.filter(channels, 'ANNOUNCE')), [
      'Announcements',
    ]);
    expect(
      _names(ChannelSearch.filter(channels, 'r')).contains('random'),
      true,
    );
  });

  test('ties keep the server order so the list does not reshuffle', () {
    final ties = [_channel('alpha-one'), _channel('alpha-two')];
    expect(_names(ChannelSearch.filter(ties, 'alpha')), [
      'alpha-one',
      'alpha-two',
    ]);
  });

  test('no match yields an empty list, not everything', () {
    expect(ChannelSearch.filter(channels, 'zzz'), isEmpty);
  });

  test('the source list is never mutated', () {
    final source = [_channel('b'), _channel('a')];
    ChannelSearch.filter(source, 'a');
    expect(_names(source), ['b', 'a']);
  });
}
