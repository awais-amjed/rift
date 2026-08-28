/// One bit of `roles.permissions` (migration 018).
///
/// The numbers are a wire contract, not an implementation detail: they are
/// assigned once in `app.perm_bit` and never reused, and a retired permission
/// leaves its bit vacant rather than letting the next one inherit it. Any
/// third-party client or SDK reads the same list.
///
/// Two implementations of that list is two things that can disagree, and the
/// disagreement is quiet — a client would simply draw the wrong buttons. The
/// database is the one that decides, so the failure is cosmetic; it is still
/// worth keeping the order here identical to the migration's.
enum ServerPermission {
  // Server
  administrator(0),
  manageServer(1),
  manageRoles(2),
  manageChannels(3),
  createInvite(4),
  kickMembers(5),
  banMembers(6),
  manageBots(7),
  manageWebhooks(8),
  // Text
  viewChannel(9),
  sendMessages(10),
  attachFiles(11),
  addReactions(12),
  mentionAll(13),
  manageMessages(14),
  // Voice
  connect(15),
  speak(16),
  screenShare(17),
  muteMembers(18),
  deafenMembers(19),
  moveMembers(20),
  // 020
  createPrivateChannel(21);

  final int bit;

  const ServerPermission(this.bit);

  int get mask => 1 << bit;
}

/// The bits a member holds, as `my_permissions()` returned them.
extension PermissionBits on int {
  /// `ADMINISTRATOR` implies every other bit, exactly as `app.has_perm` folds
  /// it into the mask rather than checking it separately.
  bool has(ServerPermission permission) =>
      this & (ServerPermission.administrator.mask | permission.mask) != 0;
}
