/// The lengths a moderator picks from when timing somebody out. A short fixed
/// list, like Discord's, because a time-out is a cool-down and nobody needs
/// to type "37 minutes"; the server takes up to 28 days.
enum TimeOutLength {
  tenMinutes(Duration(minutes: 10), '10 minutes'),
  hour(Duration(hours: 1), '1 hour'),
  day(Duration(days: 1), '1 day'),
  week(Duration(days: 7), '1 week');

  final Duration duration;
  final String label;

  const TimeOutLength(this.duration, this.label);
}
