import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **样式账本锁**（1.99.48）—— 防回流的最后一道门。
///
/// 这条锁的判据不是「某个屏幕长什么样」，而是「业务层还有没有自己的样式真源」：
/// 只要 `lib/ui`（除 `m3e/` 与 `theme.dart` 桥）里再出现旧调色板、`hintColor`、
/// 字面色值、裸菜单 API，就说明有人又开了一条旁路。
///
/// 为什么按「账本」而不是按「组件」锁：M3E 的收益来自**唯一真源**，
/// 只要允许「先写一个近似值、以后再说」，1.99.38 之前那种
/// 「同一支灰在六个文件里是六个值」的债就会原样长回来。
///
/// 1.99.48 只锁**颜色与符号**这一层（本版清的就是这层）。
/// 圆角 / 字号 / 动效三类的字面值属于 1.99.49 的批次，
/// 清完之后把 [_pendingInNextVersion] 里的条目移进 [_forbidden] 即可 ——
/// 这条注释就是那次改动的清单，别另开一份文档。
const List<String> _pendingInNextVersion = <String>[
  'BorderRadius.circular(', // 44 处字面值（28 处不在十档），1.99.49 统一走 M3EShape
  'fontSize:', // 56 处字面值（12 处离格），1.99.49 统一走 M3EType
  'Curves.', // 5 处裸曲线，1.99.49 走 M3EMotion.fallbackCurve
];

const List<String> _forbidden = <String>[
  'HikoColors', // 旧调色板（1.99.48 已删）
  'hintColor', // Material 旧中性色
  'Color(0x', // 字面色值：只能出现在 tokens/ 里
  'showMenu(', // 菜单必须走 M3EMenu
  'PopupMenuButton(', // 同上
  'MenuAnchor(', // 同上（M3EMenu 内部自己用）
];

/// 允许持有字面样式的地方：设计系统本身 + 旧主题桥。
bool _allowed(String path) =>
    path.startsWith('lib/ui/m3e/') || path == 'lib/ui/theme.dart';

/// 注释行不算违规 —— 仓库里大量「1.99.40：PopupMenuButton → M3EMenu」
/// 这类演进说明，它们记录的正是**不该再写**什么。
bool _isComment(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

void main() {
  test('lib/ui 业务层不得再出现旧调色板 / hintColor / 字面色值 / 裸菜单', () {
    final files =
        Directory('lib/ui')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .map((f) => f.path)
            .where((p) => !_allowed(p))
            .toList()
          ..sort();

    expect(files, isNotEmpty, reason: '没扫到文件，路径口径可能变了');

    final offenders = <String>[];
    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_isComment(lines[i])) continue;
        for (final needle in _forbidden) {
          if (lines[i].contains(needle)) {
            offenders.add('$path:${i + 1} → $needle');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '业务层只能从 m3e.dart（M3E 角色 / M3ESemantic）取样式：\n'
          '${offenders.join('\n')}',
    );
  });

  test('字面色值只允许待在 tokens/ 里', () {
    final tokenFiles = Directory('lib/ui/m3e/tokens')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path)
        .toList();
    expect(
      tokenFiles.where((p) => File(p).readAsStringSync().contains('Color(0x')),
      isNotEmpty,
      reason: '一个色值都不在 tokens 里，说明色值源头另有其处',
    );
  });

  test('待清清单与仓库现状一致（1.99.49 收尾时删掉这条）', () {
    // 这一条不是防回流，而是防止「清单写了、实际没清」：
    // 清单里的每一项都必须在业务层**确实还存在**，否则说明清完了却没搬进
    // _forbidden（锁会出现假空档）。
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path)
        .where((p) => !_allowed(p));

    for (final needle in _pendingInNextVersion) {
      final hits = files
          .where(
            (p) =>
                File(p)
                    .readAsLinesSync()
                    .any((l) => !_isComment(l) && l.contains(needle)),
          )
          .length;
      expect(
        hits,
        greaterThan(0),
        reason:
            '「$needle」在业务层已经没有了 —— 请把它从 _pendingInNextVersion '
            '移到 _forbidden，别让账本和代码对不上',
      );
    }
  });
}
