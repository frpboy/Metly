String fmt(num v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  int c = 0;
  for (int i = s.length - 1; i >= 0; i--) {
    buf.write(s[i]);
    c++;
    if (c == 3 && i != 0) {
      buf.write(',');
      c = 0;
    }
  }
  return String.fromCharCodes(buf.toString().codeUnits.reversed);
}

String timeFmt(DateTime t) {
  final l = t.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay =
      l.year == now.year && l.month == now.month && l.day == now.day;
  final hm = '$h:$m ${l.timeZoneName}';
  if (sameDay) return hm;
  final d = l.day.toString().padLeft(2, '0');
  final mo = l.month.toString().padLeft(2, '0');
  return '$d/$mo/${l.year} $hm';
}
