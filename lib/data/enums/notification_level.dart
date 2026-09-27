/// How much a conversation is allowed to interrupt you.
///
/// One setting, read by four things that must agree: the push trigger on the
/// server, the desktop app's OS notifications, the badge it draws, and the
/// background isolate a push wakes. They agree because they all spell it this
/// way — `notify_level` in both schemas uses these same three names.
enum NotificationLevel {
  /// Every message.
  all,

  /// Only a message that names you, or `@all`.
  mentions,

  /// Nothing. Still counted as unread — muting a conversation is not the same
  /// as pretending nothing happened in it — just never announced.
  none;

  /// What a channel does until somebody says otherwise.
  ///
  /// A room full of people talking to each other is not addressed to you, and
  /// treating every line in it as though it were is how a chat app becomes a
  /// thing people turn off entirely.
  static const channelDefault = NotificationLevel.mentions;

  /// What a conversation does until somebody says otherwise. A DM *is*
  /// addressed to you; there is nothing to filter down to.
  static const dmDefault = NotificationLevel.all;

  /// The levels a channel offers, in the order they are shown.
  static const channelChoices = [
    NotificationLevel.all,
    NotificationLevel.mentions,
    NotificationLevel.none,
  ];

  /// The levels a DM offers. No `mentions`: there is no room to be named in,
  /// so it would be a third button that behaved exactly like the first.
  static const dmChoices = [NotificationLevel.all, NotificationLevel.none];

  /// What a server does until somebody says otherwise. A server is not a
  /// conversation — it has no messages of its own — so this is not a level it
  /// applies to anything: it is the level whose meaning is *no opinion*, and
  /// picking it in the menu clears the row so every scope inside falls through
  /// to its own default.
  ///
  /// It has to be [channelDefault], because a channel is what most of a server
  /// is and what the menu is read against. A server sitting at `all` while its
  /// channels quietly ring only for mentions is a menu that lies about itself
  /// — and the only honest way to fix it the other way round would be to make
  /// joining a server mean every room in it interrupts you.
  ///
  /// The consequence, which is the point: choosing `all` here is now a real
  /// opinion that gets stored, and it does turn every channel with no level of
  /// its own up to `all`. That is what the label says it does.
  static const serverDefault = channelDefault;

  /// The level actually in force, written down once.
  ///
  /// [scope] is what this exact channel or conversation is set to, [server]
  /// what the server it belongs to is set to, and either may be null for "no
  /// opinion". The nearest opinion wins: **a conversation you have spoken
  /// about individually keeps what you said, even inside a muted server.**
  ///
  /// That ordering is the one you can predict from the menu in front of you —
  /// a channel showing an explicit level is telling you it is in force — and
  /// it is what makes muting a whole server usable rather than something you
  /// turn on once and then fight. Four readers depend on agreeing about it
  /// (the ring trigger, this app's notifier, its badges, and the push
  /// isolate), so `app.notify_level` resolves it in exactly
  /// this order and this is the only copy on the client.
  static NotificationLevel resolve({
    NotificationLevel? scope,
    NotificationLevel? server,
    required NotificationLevel fallback,
  }) => scope ?? server ?? fallback;

  /// The level [raw] names, or null if it names none.
  static NotificationLevel? tryParse(Object? raw) {
    for (final level in NotificationLevel.values) {
      if (level.name == raw) return level;
    }
    return null;
  }

  static NotificationLevel parse(
    Object? raw, {
    required NotificationLevel fallback,
  }) => tryParse(raw) ?? fallback;

  /// `{scopeId: level}` out of the `prefs` half of an `unread_counts()`
  /// answer, on either tier.
  ///
  /// Anything malformed is dropped rather than allowed to cost every level in
  /// the map — one bad entry must not be able to un-mute a channel. Entries
  /// that say [fallback] are dropped too: a scope nobody has an opinion about
  /// should have no key, which is what lets "absent means default" hold
  /// everywhere downstream.
  /// A null [fallback] means every stored level is kept and anything
  /// unreadable is dropped — which is what the server scope wants. There, the
  /// level that means *no opinion* is never written down in the first place
  /// (see [serverDefault]), so anything that did get stored is somebody's
  /// opinion and dropping it would be overriding them.
  static Map<String, NotificationLevel> mapFrom(
    Object? raw, {
    required NotificationLevel? fallback,
  }) {
    if (raw is! Map) return const {};
    final levels = <String, NotificationLevel>{};
    raw.forEach((key, value) {
      if (key is! String) return;
      final level = tryParse(value);
      if (level != null && level != fallback) levels[key] = level;
    });
    return levels;
  }

  String toJson() => name;

  /// Whether a message deserves to be announced.
  ///
  /// [mentioned] is the caller's answer to "did this name me", which only
  /// something holding the plaintext can give — which is the whole reason this
  /// takes it as a parameter rather than working it out.
  bool announces({required bool mentioned}) => switch (this) {
    NotificationLevel.all => true,
    NotificationLevel.mentions => mentioned,
    NotificationLevel.none => false,
  };

  /// Whether this conversation should be left out of the badges that add
  /// several together — a server's chip, the "activity elsewhere" hint.
  ///
  /// Its own unread count is untouched: a muted channel still shows that it has
  /// something in it, the way Discord's does. What muting buys is that it stops
  /// counting towards the number on the outside.
  bool get isMuted => this == NotificationLevel.none;

  /// What to call it in a menu.
  String get label => switch (this) {
    NotificationLevel.all => 'All messages',
    NotificationLevel.mentions => 'Only @mentions',
    NotificationLevel.none => 'Nothing',
  };
}
