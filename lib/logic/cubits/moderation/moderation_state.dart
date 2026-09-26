part of 'moderation_cubit.dart';

/// Whether this account moderates the Rift directory, and what is waiting
/// for it.
class ModerationState {
  // ── Role ──────────────────────────────────────────────────

  /// Decides only whether the moderation page is shown. Central refuses every
  /// moderation call from anyone it does not list, whatever this says.
  final bool isModerator;

  // ── The three lists ───────────────────────────────────────

  final List<ModerationCase> queue;
  final List<ModerationListing> hidden;
  final List<PublisherBan> bans;

  /// Whether a load has ever finished. Before one has, empty lists mean
  /// "not asked yet" rather than "nothing waiting".
  final bool hasLoaded;
  final bool loading;

  /// Listing and account ids with an action in flight, so the one card being
  /// acted on can say so while the rest stay usable.
  final Set<String> busy;

  final String? error;

  const ModerationState({
    this.isModerator = false,
    this.queue = const [],
    this.hidden = const [],
    this.bans = const [],
    this.hasLoaded = false,
    this.loading = false,
    this.busy = const {},
    this.error,
  });

  ModerationState copyWith({
    bool? isModerator,
    List<ModerationCase>? queue,
    List<ModerationListing>? hidden,
    List<PublisherBan>? bans,
    bool? hasLoaded,
    bool? loading,
    Set<String>? busy,
    String? error,
    bool clearError = false,
  }) {
    return ModerationState(
      isModerator: isModerator ?? this.isModerator,
      queue: queue ?? this.queue,
      hidden: hidden ?? this.hidden,
      bans: bans ?? this.bans,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
