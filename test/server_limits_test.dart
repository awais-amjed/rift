import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server_limits.dart';
import 'package:rift/data/enums/channel_type.dart';

void main() {
  group('ServerLimits defaults', () {
    test('both sweeps are off, so upgrading changes nothing', () {
      const limits = ServerLimits.defaults;
      expect(limits.messageRetentionDays, ServerLimits.unlimited);
      expect(limits.messageHistoryCap, ServerLimits.unlimited);
      expect(limits.sweepsHistory, isFalse);
    });

    test('the size cap defaults to the bucket ceiling that predated it', () {
      // 25 MB — what the server's 005_storage.sql hardcoded
      // before 007 made it a column.
      expect(ServerLimits.defaults.maxAttachmentBytes, 26214400);
    });

    test('sweepsHistory notices either knob on its own', () {
      expect(
        const ServerLimits(messageRetentionDays: 30).sweepsHistory,
        isTrue,
      );
      expect(const ServerLimits(messageHistoryCap: 500).sweepsHistory, isTrue);
    });
  });

  group('ServerLimits.fromJson', () {
    test('reads the flat snake_case shape both sources use', () {
      final limits = ServerLimits.fromJson(const {
        'max_attachment_bytes': 8388608,
        'message_retention_days': 90,
        'message_history_cap': 5000,
      });
      expect(limits.maxAttachmentBytes, 8388608);
      expect(limits.messageRetentionDays, 90);
      expect(limits.messageHistoryCap, 5000);
    });

    test('a server too old to have the columns still parses as defaults', () {
      // getServerDetails on a pre-007 server returns the row without them —
      // this must read as "no limits", not throw.
      final limits = ServerLimits.fromJson(const {
        'id': 'abc',
        'name': 'Old Server',
      });
      expect(limits, ServerLimits.defaults);
    });

    test('a server still reporting the dropped quota columns ignores them', () {
      // An earlier draft of 007 shipped daily quotas. A server that ran it and
      // hasn't been migrated forward must not confuse the client.
      final limits = ServerLimits.fromJson(const {
        'max_attachment_bytes': 1048576,
        'default_channel_daily_quota': 50,
        'dm_daily_quota': 20,
      });
      expect(limits.maxAttachmentBytes, 1048576);
      expect(limits.messageRetentionDays, ServerLimits.unlimited);
      expect(limits.messageHistoryCap, ServerLimits.unlimited);
    });

    test('a non-numeric value falls back rather than throwing', () {
      final limits = ServerLimits.fromJson(const {
        'message_history_cap': 'lots',
      });
      expect(limits.messageHistoryCap, ServerLimits.unlimited);
    });

    test('round-trips through toJson', () {
      const limits = ServerLimits(
        maxAttachmentBytes: 1048576,
        messageRetentionDays: 7,
        messageHistoryCap: 100,
        dmRetentionDays: 0,
        dmHistoryCap: 250,
      );
      expect(ServerLimits.fromJson(limits.toJson()), limits);
    });

    test('toJson names the DM overrides even when they are null', () {
      // The endpoint reads presence, not truthiness: an omitted key means
      // "leave it alone" and an explicit null means "go back to inheriting".
      // Dropping the key would make going back to inherit impossible.
      final json = ServerLimits.defaults.toJson();
      expect(json.containsKey('dm_retention_days'), isTrue);
      expect(json['dm_retention_days'], isNull);
      expect(json.containsKey('dm_history_cap'), isTrue);
    });
  });

  group('DM retention overrides', () {
    test('null inherits the server-wide numbers', () {
      const limits = ServerLimits(
        messageRetentionDays: 30,
        messageHistoryCap: 500,
      );
      expect(limits.dmRetentionDays, isNull);
      expect(limits.effectiveDmRetentionDays, 30);
      expect(limits.effectiveDmHistoryCap, 500);
    });

    test('zero exempts DMs from a sweep the channels still get', () {
      // The policy this feature exists for: trim the busy channels, keep the
      // DMs. Reading 0 back as null would put the server's 30 days on and
      // start deleting conversations the admin had exempted.
      const limits = ServerLimits(messageRetentionDays: 30, dmRetentionDays: 0);
      expect(limits.effectiveDmRetentionDays, ServerLimits.unlimited);
      expect(limits.messageRetentionDays, 30, reason: 'channels unaffected');
    });

    test('a number of its own wins over the server-wide one', () {
      const limits = ServerLimits(messageHistoryCap: 500, dmHistoryCap: 50);
      expect(limits.effectiveDmHistoryCap, 50);
    });

    test('the two overrides are independent', () {
      const limits = ServerLimits(
        messageRetentionDays: 30,
        messageHistoryCap: 500,
        dmHistoryCap: 50,
      );
      expect(limits.effectiveDmRetentionDays, 30, reason: 'still inherits');
      expect(limits.effectiveDmHistoryCap, 50);
    });

    test('sweepsHistory sees a server that only trims its DMs', () {
      // Nothing server-wide, a cap on DMs alone: the sweep does run.
      const limits = ServerLimits(dmHistoryCap: 50);
      expect(limits.messageHistoryCap, ServerLimits.unlimited);
      expect(limits.sweepsHistory, isTrue);
    });

    test('and stays false when DMs explicitly opt out of nothing', () {
      expect(const ServerLimits(dmRetentionDays: 0).sweepsHistory, isFalse);
    });

    test('an override is not equal to the same number inherited', () {
      // Both sweep DMs every 30 days today, but they are different settings:
      // change the server-wide number and only one of them follows.
      const inherited = ServerLimits(messageRetentionDays: 30);
      const explicit = ServerLimits(
        messageRetentionDays: 30,
        dmRetentionDays: 30,
      );
      expect(inherited.effectiveDmRetentionDays, explicit.dmRetentionDays);
      expect(inherited, isNot(explicit));
    });
  });

  group('ServerLimits.allowsAttachment', () {
    const limits = ServerLimits(maxAttachmentBytes: 1000);

    test('a file at exactly the cap is allowed', () {
      expect(limits.allowsAttachment(1000), isTrue);
    });

    test('one byte over is not', () {
      expect(limits.allowsAttachment(1001), isFalse);
    });
  });

  group('Channel retention overrides', () {
    Channel parse(Map<String, dynamic> json) => Channel.fromJson({
      'id': 'c1',
      'name': 'general',
      'channel_type': 'text',
      ...json,
    });

    test('null means inherit, and is what a channel starts as', () {
      final channel = parse(const {});
      expect(channel.retentionDays, isNull);
      expect(channel.historyCap, isNull);
    });

    test('zero is a real value, not the absence of one', () {
      // A channel opting *out* of a server-wide sweep. Reading this back as
      // null would silently put the server's number back on and start
      // deleting a channel the admin had exempted.
      final channel = parse(const {'retention_days': 0, 'history_cap': 0});
      expect(channel.retentionDays, 0);
      expect(channel.historyCap, 0);
      expect(channel.retentionDays, isNot(isNull));
    });

    test('the two overrides are independent', () {
      final channel = parse(const {'history_cap': 500});
      expect(channel.retentionDays, isNull, reason: 'still inherits');
      expect(channel.historyCap, 500);
    });

    test('survives a toJson round trip', () {
      const channel = Channel(
        id: 'c1',
        name: 'announcements',
        channelType: ChannelType.text,
        retentionDays: 30,
        historyCap: 0,
      );
      final back = Channel.fromJson(channel.toJson());
      expect(back.retentionDays, 30);
      expect(back.historyCap, 0);
    });

    test('only a text channel has messages to sweep', () {
      expect(parse(const {}).hasMessages, isTrue);
      // A voice channel carries the columns and ignores them — the settings
      // dialog hides them rather than offering a switch wired to nothing.
      expect(parse(const {'channel_type': 'voice'}).hasMessages, isFalse);
    });
  });

  group('what a call may cost (migration 028)', () {
    test('a server that has not said anything caps nothing', () {
      const limits = ServerLimits.defaults;
      expect(limits.maxVoiceParticipants, ServerLimits.unlimited);
      expect(limits.maxShareMbps, ServerLimits.unlimited);
      // And an operator who set nothing gets whatever the sharer picked.
      expect(limits.shareMbps(10), 10);
    });

    test('a share is held to the smaller of the two numbers', () {
      const capped = ServerLimits(maxShareMbps: 3);
      expect(capped.shareMbps(10), 3, reason: 'the operator wins');
      expect(capped.shareMbps(2), 2, reason: 'so does a modest sharer');
      expect(capped.shareMbps(3), 3);
    });

    test('a server too old to know about these parses without them', () {
      // The columns arrived in 028; a client that has been updated will meet
      // servers that have not, and the answer is "no limit" rather than a
      // crash or a zero that reads as "nothing may be shared".
      final limits = ServerLimits.fromJson(const {
        'max_attachment_bytes': 26214400,
        'message_retention_days': 0,
        'message_history_cap': 0,
      });
      expect(limits.maxVoiceParticipants, ServerLimits.unlimited);
      expect(limits.maxShareMbps, ServerLimits.unlimited);
      expect(limits.shareMbps(10), 10);
    });

    test('both survive a round trip, and count towards equality', () {
      const limits = ServerLimits(maxVoiceParticipants: 25, maxShareMbps: 3);
      final back = ServerLimits.fromJson(limits.toJson());
      expect(back.maxVoiceParticipants, 25);
      expect(back.maxShareMbps, 3);
      expect(back, limits);
      expect(back.hashCode, limits.hashCode);
      // A limits object that ignored them would compare equal to one that
      // set them, and the settings dialog would decide nothing had changed.
      expect(const ServerLimits(maxVoiceParticipants: 25), isNot(limits));
    });
  });

  group('how large the place may get (migration 029)', () {
    test('a server that has not said anything caps neither', () {
      const limits = ServerLimits.defaults;
      expect(limits.maxMembers, ServerLimits.unlimited);
      expect(limits.maxStorageBytes, ServerLimits.unlimited);
      expect(limits.hasRoomFor(1 << 30, used: 1 << 40), isTrue);
      expect(limits.remainingStorage(999), isNull);
    });

    test('storage room is what is left, and never negative', () {
      const limits = ServerLimits(maxStorageBytes: 1000);
      expect(limits.hasRoomFor(400, used: 500), isTrue);
      expect(limits.hasRoomFor(500, used: 500), isTrue, reason: 'exactly full fits');
      expect(limits.hasRoomFor(501, used: 500), isFalse);
      expect(limits.remainingStorage(500), 400 + 100);
      // A cap lowered below what is already held reads as nothing left,
      // rather than as a negative allowance a caller might add to.
      expect(limits.remainingStorage(5000), 0);
    });

    test('a server too old to know about these parses without them', () {
      final limits = ServerLimits.fromJson(const {
        'max_attachment_bytes': 26214400,
      });
      expect(limits.maxMembers, ServerLimits.unlimited);
      expect(limits.maxStorageBytes, ServerLimits.unlimited);
      expect(limits.hasRoomFor(1 << 30, used: 0), isTrue);
    });

    test('both survive a round trip and count towards equality', () {
      const limits = ServerLimits(maxMembers: 50, maxStorageBytes: 1048576);
      final back = ServerLimits.fromJson(limits.toJson());
      expect(back, limits);
      expect(back.hashCode, limits.hashCode);
      expect(const ServerLimits(maxMembers: 50), isNot(limits));
    });
  });
}
