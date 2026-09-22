/// Where a permission is exercised, and so where it belongs in a list of them.
enum PermissionGroup {
  server('Server'),
  text('Text channels'),
  voice('Voice channels');

  final String label;

  const PermissionGroup(this.label);
}

/// Over the helper budget and one job: the permission bits, each with the
/// comment that says what it lets someone do.
///
/// One bit of `roles.permissions` (`006_roles.sql`).
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
///
/// The descriptions are the product. Somebody ticking a box in a permission
/// matrix is deciding what another person can do to a room full of people, and
/// a name alone ("Manage channels") does not say whether that includes deleting
/// one. Each line says what it lets somebody *do*, and where it differs from
/// what the name suggests, it says that instead.
enum ServerPermission {
  // ── Server ──────────────────────────────────────────────
  administrator(
    0,
    PermissionGroup.server,
    'Administrator',
    'Everything below, and everything added later. Cannot be taken back by '
        'anybody holding a lower role.',
  ),
  manageServer(
    1,
    PermissionGroup.server,
    'Manage server',
    'Rename the server, change its icon, and set how long messages are kept.',
  ),

  /// Retired by `005_bots.sql`: roles are an administrator's to shape, and
  /// the bit opens nothing any more. Kept so the number stays taken and an
  /// old role carrying it still parses; hidden from the editor.
  manageRoles(
    2,
    PermissionGroup.server,
    'Manage roles',
    'Retired. Creating, editing and handing out roles is an administrator\'s.',
  ),
  manageChannels(
    3,
    PermissionGroup.server,
    'Manage channels',
    'Create, rename and delete channels the whole server can see. Does not '
        'reach inside a private channel.',
  ),
  createInvite(
    4,
    PermissionGroup.server,
    'Create invites',
    'Mint invite links. An invite can never carry more than its maker holds.',
  ),
  kickMembers(
    5,
    PermissionGroup.server,
    'Kick members',
    'Remove somebody from the server. They can come back with a new invite.',
  ),
  banMembers(
    6,
    PermissionGroup.server,
    'Ban members',
    'End somebody’s membership for good. Their messages stay.',
  ),
  manageBots(
    7,
    PermissionGroup.server,
    'Manage bots',
    'Give a bot the key to a channel or a call, and take it back. The channel '
        'says so to everyone in it for as long as the grant lasts.',
  ),
  manageWebhooks(
    8,
    PermissionGroup.server,
    'Manage webhooks',
    'Create and revoke the URLs that let an outside service post here.',
  ),

  // ── Text ────────────────────────────────────────────────
  viewChannel(
    9,
    PermissionGroup.text,
    'View channels',
    'See a channel and read it. A private channel answers to its own member '
        'list instead — this cannot open one.',
  ),
  sendMessages(
    10,
    PermissionGroup.text,
    'Send messages',
    'Post in a channel they can see.',
  ),
  attachFiles(
    11,
    PermissionGroup.text,
    'Attach files',
    'Send images and files, within the server’s size limit.',
  ),
  addReactions(
    12,
    PermissionGroup.text,
    'Add reactions',
    'React to a message. Reactions are not encrypted — the server sees '
        'who reacted with what.',
  ),
  mentionAll(
    13,
    PermissionGroup.text,
    'Mention everyone',
    'Use @all, which rings every member’s phone rather than one.',
  ),
  manageMessages(
    14,
    PermissionGroup.text,
    'Manage messages',
    'Delete anybody’s message. Never edit one — nobody may rewrite '
        'a message under its author’s name.',
  ),

  // ── Voice ───────────────────────────────────────────────
  connect(
    15,
    PermissionGroup.voice,
    'Connect',
    'Join a voice channel they can see.',
  ),
  speak(
    16,
    PermissionGroup.voice,
    'Speak',
    'Unmute in a call. Without it somebody can still listen, which is what a '
        'listen-only channel is.',
  ),
  screenShare(
    17,
    PermissionGroup.voice,
    'Share screen',
    'Share a screen or a window in a call.',
  ),
  muteMembers(
    18,
    PermissionGroup.voice,
    'Mute members',
    'Server-mute somebody, which survives them rejoining.',
  ),
  deafenMembers(
    19,
    PermissionGroup.voice,
    'Deafen members',
    'Server-deafen somebody. Deafening denies the microphone as well as the '
        'ears.',
  ),
  moveMembers(
    20,
    PermissionGroup.voice,
    'Move members',
    'Drag somebody into another call, or disconnect them from one.',
  ),

  // ── 020 ─────────────────────────────────────────────────
  createPrivateChannel(
    21,
    PermissionGroup.server,
    'Create private channels',
    'Make a channel only the people they pick can see — including from '
        'server admins, who hold no key to it either.',
  ),

  // ── 036 ─────────────────────────────────────────────────
  addBots(
    22,
    PermissionGroup.server,
    'Add bots',
    'Make an invite a bot can join with. A program that will sit in every '
        'public channel is not the same decision as inviting a person.',
  ),
  summonBots(
    23,
    PermissionGroup.voice,
    'Summon bots',
    'Bring a bot into a call to play or announce something. It publishes and '
        'cannot hear — listening is a separate grant only Manage bots gives.',
  ),

  // ── Soundboard ──────────────────────────────────────────
  manageSoundboard(
    24,
    PermissionGroup.server,
    'Manage soundboard',
    'Add and remove the clips on the server\'s soundboard. What a whole call '
        'hears is not one member\'s to decide.',
  ),
  useSoundboard(
    25,
    PermissionGroup.voice,
    'Use soundboard',
    'Play a clip into a call. Everyone hearing it can turn it down or off '
        'for themselves, which is a setting on their device and not a grant.',
  );

  final int bit;
  final PermissionGroup group;
  final String label;
  final String description;

  const ServerPermission(this.bit, this.group, this.label, this.description);

  int get mask => 1 << bit;

  /// Everything in [group], in bit order — which is the order the migration
  /// assigns them and the order they read best in.
  static List<ServerPermission> inGroup(PermissionGroup group) =>
      values.where((p) => p.group == group && !p.isRetired).toList()
        ..sort((a, b) => a.bit.compareTo(b.bit));

  /// A bit the server no longer reads. Not offered, never granted.
  bool get isRetired => this == manageRoles;
}

/// The bits a member or a role holds.
extension PermissionBits on int {
  /// `ADMINISTRATOR` implies every other bit, exactly as `app.has_perm` folds
  /// it into the mask rather than checking it separately.
  bool has(ServerPermission permission) =>
      this & (ServerPermission.administrator.mask | permission.mask) != 0;

  /// Set without the implication — what a *role* literally carries, which is
  /// what a checkbox in the editor has to show.
  bool carries(ServerPermission permission) => this & permission.mask != 0;

  int with_(ServerPermission permission) => this | permission.mask;

  int without(ServerPermission permission) => this & ~permission.mask;
}
