/// 自然排序（数字感知），对应旧版 ImportScanner.naturalCompare /
/// 桌面 localeCompare(..., {numeric:true})：1.mp3 < 2.mp3 < 10.mp3
int naturalCompare(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final da = _isDigit(ca);
    final db = _isDigit(cb);
    if (da && db) {
      var ni = i;
      while (ni < a.length && _isDigit(a.codeUnitAt(ni))) {
        ni++;
      }
      var nj = j;
      while (nj < b.length && _isDigit(b.codeUnitAt(nj))) {
        nj++;
      }
      final na = int.tryParse(a.substring(i, ni)) ?? 0;
      final nb = int.tryParse(b.substring(j, nj)) ?? 0;
      if (na != nb) return na.compareTo(nb);
      i = ni;
      j = nj;
    } else {
      final cmp = _lower(ca).compareTo(_lower(cb));
      if (cmp != 0) return cmp;
      i++;
      j++;
    }
  }
  return a.length - b.length;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

int _lower(int codeUnit) {
  // ASCII 大写转小写；非 ASCII 原样（与 Kotlin lowercaseChar 行为对齐）
  if (codeUnit >= 0x41 && codeUnit <= 0x5A) return codeUnit + 0x20;
  return codeUnit;
}
