import '../models/album.dart';

/// 给老库里缺失「添加时间」（`date <= 0`，即 1970）的专辑补一个时间戳。
///
/// 为什么需要：`recent_desc` 在 1.99.69 之前根本不读 `date`，靠库数组顺序「假装」
/// 是添加时间；改成真排序后，缺时间的条目会全部沉到 1970，用户升级瞬间看到整库
/// 顺序崩掉。这里按**当前数组顺序**补齐：
///
/// - 数组下标越小 = 时间越新（降序时首项显示在最上面，与原观感一致）；
/// - 有前一条已知时间就 `prev - 1ms`；前导缺失段以第一个已知值为基准往上加；
/// - 间隙不够（下一条已知值和上一条同毫秒或更早）时钳到已知值，允许相等 ——
///   相等时由 `filter.dart` 的下标兜底维持数组序；
/// - 全库都缺时以 [now]（默认当前时间）为基准按下标递减。
///
/// 返回 `identical` 于入参表示「没有任何条目需要补」，调用方据此避免每次启动写盘。
/// 幂等：补过之后再调用不会产生新值。
List<Album> backfillMissingDates(List<Album> albums, {DateTime? now}) {
  if (albums.isEmpty) return albums;

  final ms = <int>[for (final a in albums) a.date.millisecondsSinceEpoch];
  if (!ms.any((v) => v <= 0)) return albums;

  final n = ms.length;

  // nextKnownAfter[i]：严格在 i 之后、第一个已知（>0）的时间戳
  final nextKnownAfter = List<int?>.filled(n, null);
  int? carry;
  for (var i = n - 1; i >= 0; i--) {
    nextKnownAfter[i] = carry;
    if (ms[i] > 0) carry = ms[i];
  }

  final firstKnown = ms.indexWhere((v) => v > 0);
  if (firstKnown < 0) {
    // 整库都没时间：以 now 为基准，下标越大越旧
    final anchor = (now ?? DateTime.now()).millisecondsSinceEpoch;
    for (var i = 0; i < n; i++) {
      ms[i] = anchor - i;
    }
  } else {
    // 前导缺失段：以第一个已知值为基准，下标越小越新
    for (var i = 0; i < firstKnown; i++) {
      ms[i] = ms[firstKnown] + (firstKnown - i);
    }
    // 其余缺失段：紧跟上一条 -1ms；间隙不足时钳到段后第一个已知值
    for (var i = firstKnown + 1; i < n; i++) {
      if (ms[i] > 0) continue;
      final prev = ms[i - 1];
      final next = nextKnownAfter[i];
      var value = prev > 1 ? prev - 1 : 1; // 不允许补出 <=0
      if (next != null && next <= prev && value < next) value = next;
      ms[i] = value;
    }
  }

  return <Album>[
    for (var i = 0; i < n; i++)
      if (albums[i].date.millisecondsSinceEpoch == ms[i])
        albums[i]
      else
        albums[i].copyWith(
          // 必须按毫秒构造：Album.toJson 只存毫秒，带微秒会在重启后漂移
          date: DateTime.fromMillisecondsSinceEpoch(ms[i]),
        ),
  ];
}
