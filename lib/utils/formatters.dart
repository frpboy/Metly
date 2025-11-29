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
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m IST';
}
