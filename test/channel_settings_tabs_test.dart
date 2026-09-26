import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/presentation/screens/home/channels/settings/channel_settings_tab.dart';

/// Which pages a channel's settings offer, and to whom. The server refuses
/// every write a page could make without the right; this is what stops the
/// dialog offering a page of refusals.
void main() {
  const text = Channel(id: 't', name: 'general', channelType: ChannelType.text);
  const voice = Channel(
    id: 'v',
    name: 'Lounge',
    channelType: ChannelType.voice,
  );
  const privateText = Channel(
    id: 'p',
    name: 'staff',
    channelType: ChannelType.text,
    isPrivate: true,
  );

  test('a manager of a text channel gets every page', () {
    expect(visibleChannelSettingsTabs(text, canManage: true), [
      ChannelSettingsTab.overview,
      ChannelSettingsTab.access,
      ChannelSettingsTab.bots,
      ChannelSettingsTab.webhooks,
      ChannelSettingsTab.delete,
    ]);
  });

  test('a voice channel has no webhooks, which post messages', () {
    expect(
      visibleChannelSettingsTabs(voice, canManage: true),
      isNot(contains(ChannelSettingsTab.webhooks)),
    );
  });

  test('a member inside a private channel sees who else is, and only that', () {
    expect(visibleChannelSettingsTabs(privateText, canManage: false), [
      ChannelSettingsTab.access,
    ]);
  });

  test('a member of a public channel gets nothing', () {
    expect(visibleChannelSettingsTabs(text, canManage: false), isEmpty);
  });
}
