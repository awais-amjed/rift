/// How long a call has been going, as the call's chrome writes it: `04:07`,
/// and `1:04:07` once it passes an hour.
///
/// One formatter for every place a call shows its length — its own header,
/// the bar standing in for it over other screens, the pill left behind when
/// the controls fade — so the three can never disagree by a format.
String formatCallDuration(Duration elapsed) {
  final d = elapsed.isNegative ? Duration.zero : elapsed;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
