import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/services/channel_eviction.dart';

Channel _channel(String id, [String name = 'general']) =>
    Channel(id: id, name: name, channelType: ChannelType.text);

/// Deleting a channel has to put everyone standing in it out. The event that
/// says so doesn't name the channel, so the rule is "anything I'm pointed at
/// that the server no longer lists is gone" — which has two edges worth
/// pinning, because both would evict people who shouldn't be.
void main() {
  group('ChannelEviction.isGone', () {
    final live = ChannelEviction.liveIds([_channel('a'), _channel('b')]);

    test('a channel still listed is not gone', () {
      expect(ChannelEviction.isGone('a', live), isFalse);
      expect(ChannelEviction.isGone('b', live), isFalse);
    });

    test('a channel no longer listed is gone', () {
      expect(ChannelEviction.isGone('c', live), isTrue);
    });

    // Nothing open. Without this guard, every channel-list change would try to
    // evict a member who was sitting in no channel at all.
    test('nothing open is never gone', () {
      expect(ChannelEviction.isGone(null, live), isFalse);
      expect(ChannelEviction.isGone(null, <String>{}), isFalse);
    });

    // The list really can empty out — the last channel deleted, or a ban
    // putting them all out of reach — and then whoever is in one does leave.
    test('an empty list evicts whoever is in something', () {
      expect(ChannelEviction.isGone('a', <String>{}), isTrue);
    });
  });

  test('liveIds keeps ids, not names', () {
    final ids = ChannelEviction.liveIds([
      _channel('id-1', 'general'),
      _channel('id-2', 'general-2'),
    ]);

    expect(ids, {'id-1', 'id-2'});
  });
}
