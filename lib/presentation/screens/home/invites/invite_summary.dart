import '../../../../data/classes/role.dart';
import 'widgets/invite_options.dart';

/// The one line under the dialog's title: what this link will do.
///
/// Pure, and separate from the dialog, because it is the only place the three
/// choices are stated together — and the sentence a person reads before handing
/// somebody a link is worth being able to test without pumping a widget.
class InviteSummary {
  const InviteSummary._();

  static String of({
    required int expiryIndex,
    required int usesIndex,
    Role? role,
  }) {
    final expiry = inviteExpiryOptions[expiryIndex];
    final uses = inviteUsesOptions[usesIndex];

    final expiryText = expiry.seconds == null
        ? 'Never expires'
        : 'Expires in ${expiry.label}';
    final usesText = uses.value == null
        ? 'Unlimited uses'
        : '${uses.label} use${uses.value == 1 ? '' : 's'}';

    // The role goes first when there is one. It is the part that changes what
    // the person on the other end can *do*, and the other two only say for how
    // long they can do it.
    final parts = [
      if (role != null) 'Joins as ${role.name}',
      expiryText,
      usesText,
    ];
    return parts.join(' · ');
  }
}
