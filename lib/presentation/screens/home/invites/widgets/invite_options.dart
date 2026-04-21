/// Expiry presets shown in the invite modal.
class InviteExpiryOption {
  final String label;
  final int? seconds; // null = never expires

  const InviteExpiryOption(this.label, this.seconds);
}

const List<InviteExpiryOption> inviteExpiryOptions = [
  InviteExpiryOption('1 hour',  3600),
  InviteExpiryOption('1 day',   86400),
  InviteExpiryOption('7 days',  604800),
  InviteExpiryOption('30 days', 2592000),
  InviteExpiryOption('Never',   null),
];

/// Max-uses presets shown in the invite modal.
class InviteUsesOption {
  final String label;
  final int? value; // null = unlimited

  const InviteUsesOption(this.label, this.value);
}

const List<InviteUsesOption> inviteUsesOptions = [
  InviteUsesOption('1',  1),
  InviteUsesOption('5',  5),
  InviteUsesOption('10', 10),
  InviteUsesOption('25', 25),
  InviteUsesOption('∞',  null),
];

