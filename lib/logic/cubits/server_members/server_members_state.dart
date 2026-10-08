part of 'server_members_cubit.dart';

/// What the client knows about a server's members right now.
///
/// It used to be one list: every member, fetched whole. That list was capped at
/// 1000 rows by PostgREST, so on a large server it was not the roster — it was
/// the first thousand names alphabetically, and everything reading it treated
/// the rest as though they did not exist.
///
/// So it is three things now, because the client needs three different answers
/// and only one of them can be a whole list:
///
///  * [bots] — all of them. A bot is a program somebody registered and runs, so
///    there are a handful, and they are listed apart from people anyway
///    (BOTS.md §9).
///  * [known] — people resolved by id, because we had the id first: Realtime
///    presence, a voice room's participants, a message's author. Bounded by who
///    is actually about rather than by how many have ever joined.
///  * [people] — alphabetical pages of everybody, as far as they have been
///    scrolled. [peopleCount] is what says how many there are in total, since
///    the length of a page says only how far somebody has read.
class ServerMembersState extends Equatable {
  /// Which server this describes. Null when no server is selected.
  final String? serverId;

  /// Every bot on the server.
  final List<ServerMember> bots;

  /// People resolved by id rather than paged in — presence, call participants,
  /// message authors. The only record of somebody a page has not reached.
  final Map<String, ServerMember> known;

  /// Alphabetical pages of people, as far as they have been loaded.
  final MemberPage people;

  /// How many people there are, from `member_counts` rather than from the
  /// length of what has been loaded.
  final int peopleCount;

  /// Every role on this server, most senior first. Empty until the first load
  /// lands, and on a server too old to have any.
  final List<Role> roles;

  /// Which roles each member holds, most senior first. Filled for the members
  /// on screen, not for everybody — except while [roleCounts] is kept, when
  /// it holds every holder on the server.
  final Map<String, List<Role>> memberRoles;

  /// How many members hold each role, by role id. Null unless something is
  /// showing the counts ([ServerMembersCubit.countRoles]): counting reads
  /// every assignment on the server, and only the Roles page needs it.
  final Map<String, int>? roleCounts;

  /// Whether the first load for [serverId] has landed — which is what the
  /// sidebar shows a spinner for. A server with no other members is *loaded*
  /// and empty, not pending.
  final bool loaded;

  final bool loading;
  final String? error;

  ServerMembersState({
    this.serverId,
    this.bots = const [],
    this.known = const {},
    this.people = MemberPage.empty,
    this.peopleCount = 0,
    this.roles = const [],
    this.memberRoles = const {},
    this.roleCounts,
    this.loaded = false,
    this.loading = false,
    this.error,
  });

  /// Everybody we can name, by user id.
  ///
  /// Built once per state. Pages last so a freshly paged row wins over an
  /// older resolved copy of the same person — they carry the same columns, but
  /// the page is the more recent read.
  late final Map<String, ServerMember> byId = {
    for (final bot in bots) bot.id: bot,
    ...known,
    for (final member in people.members) member.id: member,
  };

  /// Whether more people can be paged in.
  bool get hasMorePeople => people.hasMore;

  /// The most senior role [userId] holds that has a colour, or null.
  ///
  /// Colour rather than rank alone: a role that carries permissions and no
  /// colour is deliberately invisible, and letting it override the one above it
  /// that *was* given a colour would make the choice pointless.
  Role? colourRoleFor(String userId) {
    for (final role in memberRoles[userId] ?? const <Role>[]) {
      if (role.displayColor != null) return role;
    }
    return null;
  }

  /// The most senior role [userId] holds — what a chip beside their name
  /// says, colour or not. Null for somebody holding none, which is
  /// what most members are: the baseline is not a role anybody holds.
  Role? topRoleFor(String userId) => memberRoles[userId]?.firstOrNull;

  /// The current display name for [userId].
  ///
  /// [fallback] is the copy frozen into a LiveKit token or a presence payload,
  /// used only for somebody this roster hasn't got — the seconds between them
  /// joining a call and our lookup landing. Everything that renders a name goes
  /// through here, so a rename shows up in one place rather than three.
  ///
  /// It matters more than it did: with the roster paged, somebody far down the
  /// alphabet is *routinely* not in hand, and the fallback is what keeps their
  /// name on screen while [ServerMembersCubit.resolve] fetches the real one.
  String nameFor(String userId, String fallback) =>
      byId[userId]?.displayName ?? fallback;

  /// The current picture for [userId], by the same rule as [nameFor]: the
  /// roster's copy for anybody it holds — none, if they removed theirs — and
  /// [fallback] only for somebody it has not resolved yet.
  String? avatarFor(String userId, String? fallback) {
    final member = byId[userId];
    return member == null ? fallback : member.avatarPath;
  }

  ServerMembersState copyWith({
    List<ServerMember>? bots,
    Map<String, ServerMember>? known,
    MemberPage? people,
    int? peopleCount,
    List<Role>? roles,
    Map<String, List<Role>>? memberRoles,
    Map<String, int>? roleCounts,
    bool clearRoleCounts = false,
    bool? loaded,
    bool? loading,
    String? error,
  }) => ServerMembersState(
    serverId: serverId,
    bots: bots ?? this.bots,
    known: known ?? this.known,
    people: people ?? this.people,
    peopleCount: peopleCount ?? this.peopleCount,
    roles: roles ?? this.roles,
    memberRoles: memberRoles ?? this.memberRoles,
    roleCounts: clearRoleCounts ? null : (roleCounts ?? this.roleCounts),
    loaded: loaded ?? this.loaded,
    loading: loading ?? this.loading,
    error: error,
  );

  @override
  List<Object?> get props => [
    serverId,
    bots,
    known,
    people,
    peopleCount,
    roles,
    memberRoles,
    roleCounts,
    loaded,
    loading,
    error,
    byId,
  ];
}
