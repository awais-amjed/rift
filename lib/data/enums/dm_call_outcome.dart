/// How a DM call ended, as `dm_calls.outcome` records it.
enum DmCallOutcome {
  /// Answered, and later hung up from either end.
  completed,

  /// The caller gave up after it had rung long enough to be answered, or it
  /// rang out.
  missed,

  /// The person called refused it.
  declined,

  /// The caller hung up almost at once — nobody had a chance to answer, so
  /// nobody is told they missed anything.
  cancelled;

  /// Null for a call still going, and for a value this build does not know.
  static DmCallOutcome? fromString(String? value) {
    for (final outcome in DmCallOutcome.values) {
      if (outcome.name == value) return outcome;
    }
    return null;
  }

  String toJson() => name;
}
