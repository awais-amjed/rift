import '../../../../../data/apis/push_api.dart';

/// Turning a server's push notifications on and off, for the settings dialog.
///
/// Separate from the dialog because it is the one control there that acts
/// immediately instead of on Save. Turning push on mints a credential on
/// central and writes it into this server; a form that held half of that until
/// Save would have to explain what it was holding, and would have a second way
/// to half-succeed on top of the one Save already has.
class PushToggle {
  const PushToggle._();

  /// Whether this server can currently ring its members' phones, or null if it
  /// could not be asked — a server too old to have the endpoint, or one that is
  /// not answering. Null leaves the toggle inert rather than claiming push is
  /// off, which would invite an admin to "fix" it by turning on what is on.
  static Future<bool?> status(PushApi push, String serverId) async {
    final result = await push.pushStatus(serverId: serverId);
    if (!result.success) return null;
    return (result.data as Map<String, dynamic>?)?['enabled'] == true;
  }

  /// Apply a change. Returns the error to show, or null when it landed.
  static Future<String?> set(
    PushApi push,
    String serverId, {
    required bool enabled,
  }) async {
    final result = enabled
        ? await push.enablePush(serverId: serverId)
        : await push.disablePush(serverId: serverId);
    if (result.success) return null;

    // The one refusal an admin can act on, so it gets a sentence instead of a
    // raised token.
    if (result.errorCode == 'too_many_relays') {
      return 'This account has enrolled as many servers for notifications as '
          'it can. Turn notifications off on one of the others first.';
    }
    return result.error ?? 'Could not change notification settings';
  }
}
