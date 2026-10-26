/// How long a call has been going, as the call's chrome writes it: `12s` in
/// its first minute, then `4m`, `1h 4m`, and `1d 2h` once it passes a day.
///
/// Whole minutes past the first: nobody needs to watch a call's length tick,
/// and a clock that changes every second redrew the window every second of
/// every call, behind a game too. The first minute counts seconds, since
/// `0m` looked broken, so its [CallClock] wakes each second only then. Two
/// units at most, so a call left on for days stays as short as one an hour in.
///
/// One formatter for every place a call shows its length — its own header,
/// the bar standing in for it over other screens, the pill left behind when
/// the controls fade — so the three can never disagree by a format.
String formatCallDuration(Duration elapsed) {
  final d = elapsed.isNegative ? Duration.zero : elapsed;
  if (d < const Duration(minutes: 1)) return '${d.inSeconds}s';
  if (d < const Duration(hours: 1)) return '${d.inMinutes}m';
  if (d < const Duration(days: 1)) {
    return _pair(d.inHours, 'h', d.inMinutes.remainder(60), 'm');
  }
  return _pair(d.inDays, 'd', d.inHours.remainder(24), 'h');
}

/// `1h 4m`, or `1h` alone when the smaller unit is nought.
String _pair(int big, String bigUnit, int small, String smallUnit) =>
    small == 0 ? '$big$bigUnit' : '$big$bigUnit $small$smallUnit';
