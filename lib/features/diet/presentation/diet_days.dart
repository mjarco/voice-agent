// Days as the diet's screens write and name them.

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String s) {
  final p = s.split('-');
  if (p.length != 3) return DateTime.now();
  return DateTime(int.tryParse(p[0]) ?? 1970, int.tryParse(p[1]) ?? 1, int.tryParse(p[2]) ?? 1);
}

const _weekdays = ['pon', 'wt', 'śr', 'czw', 'pt', 'sob', 'ndz'];

/// "sob 14.11"; with [today], "Dziś, sob 14.11" and "Jutro, ndz 15.11".
String dayLabel(DateTime d, {DateTime? today}) {
  final short = '${_weekdays[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  if (today == null) return short;
  final t = DateTime(today.year, today.month, today.day);
  final diff = DateTime(d.year, d.month, d.day).difference(t).inDays;
  if (diff == 0) return 'Dziś, $short';
  if (diff == 1) return 'Jutro, $short';
  if (diff == -1) return 'Wczoraj, $short';
  return short;
}
