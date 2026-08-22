/// Human-readable ages, hand-rolled because this project's dependency list is
/// deliberately thin and `intl` would be a runtime dependency bought for four
/// strings.
///
/// Two ladders, because the two surfaces have different budgets: the popover
/// can afford "20 minutes ago", the AppBar pill cannot.
library;

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _clock(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// The popover ladder, per the spec: under 1 h → "20 minutes ago"; under 24 h
/// → "3 hours ago"; under 7 d → "Sunday 9:42 AM"; older → "11 Aug, 9:42 AM".
///
/// A [then] in the future reads "just now" rather than a negative age. Two
/// machines with skewed clocks are a real case here, and "in -3 minutes" is
/// worse than a small lie.
String relativeAge(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.isNegative || d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) {
    return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
  }
  if (d.inHours < 24) {
    return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  }
  if (d.inDays < 7) return '${_weekdays[then.weekday - 1]} ${_clock(then)}';
  return '${then.day} ${_months[then.month - 1]}, ${_clock(then)}';
}

/// The pill ladder. Same boundaries, fewer characters, because this sits in an
/// AppBar next to four other actions.
String compactAge(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.isNegative || d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return 'on ${then.day} ${_months[then.month - 1]}';
}
