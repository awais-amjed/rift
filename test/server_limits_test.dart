import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/chat_quota.dart';
import 'package:rift/data/classes/server_limits.dart';
import 'package:rift/data/enums/channel_type.dart';

void main() {
  group('ServerLimits defaults', () {
    test('every count-based limit is off, so upgrading changes nothing', () {
      const limits = ServerLimits.defaults;
      expect(limits.defaultChannelDailyQuota, ServerLimits.unlimited);
      expect(limits.dmDailyQuota, ServerLimits.unlimited);
      expect(limits.messageRetentionDays, ServerLimits.unlimited);
      expect(limits.messageHistoryCap, ServerLimits.unlimited);
      expect(limits.sweepsHistory, isFalse);
    });

    test('the size cap defaults to the bucket ceiling that predated it', () {
      // 25 MB — what self_hosted_server_migrations/005_storage.sql hardcoded
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
        'default_channel_daily_quota': 50,
        'dm_daily_quota': 20,
        'message_retention_days': 90,
        'message_history_cap': 5000,
      });
      expect(limits.maxAttachmentBytes, 8388608);
      expect(limits.defaultChannelDailyQuota, 50);
      expect(limits.dmDailyQuota, 20);
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

    test('a non-numeric value falls back rather than throwing', () {
      final limits = ServerLimits.fromJson(const {'dm_daily_quota': 'lots'});
      expect(limits.dmDailyQuota, ServerLimits.unlimited);
    });

    test('round-trips through toJson', () {
      const limits = ServerLimits(
        maxAttachmentBytes: 1048576,
        defaultChannelDailyQuota: 5,
        dmDailyQuota: 3,
        messageRetentionDays: 7,
        messageHistoryCap: 100,
      );
      expect(ServerLimits.fromJson(limits.toJson()), limits);
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

  group('Channel.dailyQuota', () {
    test('null means inherit, and is what a channel starts as', () {
      final channel = Channel.fromJson(const {
        'id': 'c1',
        'name': 'general',
        'channel_type': 'text',
      });
      expect(channel.dailyQuota, isNull);
    });

    test('zero is a real value, not the absence of one', () {
      // A channel opting *out* of a server-wide quota. Reading this back as
      // null would silently put the server default back on.
      final channel = Channel.fromJson(const {
        'id': 'c1',
        'name': 'general',
        'channel_type': 'text',
        'daily_quota': 0,
      });
      expect(channel.dailyQuota, 0);
      expect(channel.dailyQuota, isNot(isNull));
    });

    test('survives a toJson round trip', () {
      const channel = Channel(
        id: 'c1',
        name: 'announcements',
        channelType: ChannelType.text,
        dailyQuota: 5,
      );
      expect(Channel.fromJson(channel.toJson()).dailyQuota, 5);
    });
  });

  group('ChatQuota', () {
    test('unlimited is not exhausted, however you ask', () {
      const quota = ChatQuota.unlimited;
      expect(quota.isLimited, isFalse);
      // The trap this type exists for: quota 0 must never read as "spent".
      expect(quota.isExhausted, isFalse);
      expect(quota.fraction, 1.0);
    });

    test('a limit with room left', () {
      const quota = ChatQuota(quota: 10, remaining: 4);
      expect(quota.isLimited, isTrue);
      expect(quota.isExhausted, isFalse);
      expect(quota.fraction, closeTo(0.4, 1e-9));
    });

    test('zero remaining under a real limit is exhausted', () {
      const quota = ChatQuota(quota: 10, remaining: 0);
      expect(quota.isExhausted, isTrue);
      expect(quota.fraction, 0.0);
    });

    test('a quota the server sent without a remaining is not a limit', () {
      // What chat_quota() returns when the server set nothing.
      const quota = ChatQuota(quota: 0, remaining: null);
      expect(quota.isLimited, isFalse);
      expect(quota.isExhausted, isFalse);
    });

    test('spendOne walks down and stops at zero', () {
      var quota = const ChatQuota(quota: 3, remaining: 2);
      quota = quota.spendOne();
      expect(quota.remaining, 1);
      quota = quota.spendOne();
      expect(quota.remaining, 0);
      quota = quota.spendOne();
      expect(quota.remaining, 0, reason: 'must not go negative');
    });

    test('spendOne on an unlimited surface changes nothing', () {
      expect(ChatQuota.unlimited.spendOne(), ChatQuota.unlimited);
    });

    test('spent keeps the limit and empties what is left', () {
      const quota = ChatQuota(quota: 10, remaining: 7);
      expect(quota.spent, const ChatQuota(quota: 10, remaining: 0));
      expect(quota.spent.isExhausted, isTrue);
    });

    test('spent on an unlimited surface stays unlimited', () {
      // A quota_exceeded we somehow got without a known limit must not
      // wedge the composer shut.
      expect(ChatQuota.unlimited.spent.isExhausted, isFalse);
    });

    test('fromResult carries the RPC shape through', () {
      final quota = ChatQuota.fromResult((quota: 5, remaining: 2));
      expect(quota, const ChatQuota(quota: 5, remaining: 2));
    });
  });
}
