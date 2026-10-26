import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **样式账本锁**（1.99.48 落地，1.99.49 收口）。
///
/// 判据不是「某个屏幕长什么样」，而是「业务层还有没有自己的样式真源」：
/// 只要 `lib/ui`（除 `m3e/` 与 `theme.dart` 桥）里再出现旧调色板、`hintColor`、
/// 字面色值、字面圆角 / 字号、裸曲线、裸菜单 API、调用点上的裸时长，
/// 就说明有人又开了一条旁路。
///
/// 为什么按「账本」而不是按「组件」锁：M3E 的收益来自**唯一真源**，
/// 只要允许「先写一个近似值、以后再说」，1.99.38 之前那种
/// 「同一支灰在六个文件里是六个值」的债就会原样长回来。
///
/// 三类「字面值」的判定口径（1.99.49 起全部生效）：
/// - 圆角：禁止 `BorderRadius.circular(` 与 `M3EShape.radius(数字)` —— 只能用档位。
/// - 字号：禁止 `fontSize: 数字` —— 只能用字阶（含 `M3EType.scaled` 的倍率写法）。
/// - 时长：禁止调用点上的 `Duration(milliseconds:…)`，但**放行具名声明**
///   （`const Duration kXxx = Duration(…)`）。
///
/// 为什么时长不是「一律换 M3EMotion」：仓库里 23 个时长里有 12 个根本不是动效
/// （HTTP 连接超时、toast 停留、搜索防抖、定位高亮、封面呼吸），把它们塞进
/// 弹簧 token 会让「动效关」档顺手关掉定时器。所以规则是**必须具名**：
/// 名字本身回答了「这是动效还是等待」。
void main() {
  /// 允许持有字面样式的地方：设计系统本身 + 旧主题桥。
  bool allowed(String path) =>
      path.startsWith('lib/ui/m3e/') || path == 'lib/ui/theme.dart';

  /// 注释行不算违规 —— 仓库里大量「1.99.40：PopupMenuButton → M3EMenu」
  /// 这类演进说明，它们记录的正是**不该再写**什么。
  bool isComment(String line) {
    final t = line.trimLeft();
    return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
  }

  /// 具名时长声明放行：`const Duration kFoo = Duration(…)`。
  bool isNamedDuration(String line) =>
      RegExp(r'const\s+Duration\s+\w+\s*=').hasMatch(line);

  const forbidden = <String>[
    'HikoColors', // 旧调色板（1.99.48 已删）
    'hintColor', // Material 旧中性色
    'Color(0x', // 字面色值：只能出现在 tokens/ 里
    'showMenu(', // 菜单必须走 M3EMenu
    'PopupMenuButton(', // 同上
    'MenuAnchor(', // 同上（M3EMenu 内部自己用）
    'BorderRadius.circular(', // 圆角必须走 M3EShape
    'Curves.', // 曲线必须走 M3EMotion
  ];

  final forbiddenPatterns = <(String, RegExp)>[
    ('fontSize 字面值', RegExp(r'fontSize:\s*[0-9]')),
    ('radius 字面值', RegExp(r'M3EShape\.radius\(\s*[0-9]')),
  ];

  List<String> businessFiles() =>
      Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .where((p) => !allowed(p))
          .toList()
        ..sort();

  test('业务层不得再出现旧调色板 / hintColor / 字面色值 / 裸菜单 / 裸圆角曲线', () {
    final files = businessFiles();
    expect(files, isNotEmpty, reason: '没扫到文件，路径口径可能变了');

    final offenders = <String>[];
    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (isComment(lines[i])) continue;
        for (final needle in forbidden) {
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

  test('圆角与字号必须走档位 / 字阶，不得写字面数字', () {
    final offenders = <String>[];
    for (final path in businessFiles()) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (isComment(lines[i])) continue;
        for (final (label, pattern) in forbiddenPatterns) {
          if (pattern.hasMatch(lines[i])) {
            offenders.add('$path:${i + 1} → $label: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('调用点上不得出现裸时长；具名声明放行', () {
    final offenders = <String>[];
    final pattern = RegExp(r'Duration\((milliseconds|seconds):');
    for (final path in businessFiles()) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (isComment(lines[i])) continue;
        if (!pattern.hasMatch(lines[i])) continue;
        if (isNamedDuration(lines[i])) continue;
        offenders.add('$path:${i + 1} → ${lines[i].trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '时长必须具名（动效走 M3EMotion，等待/超时用具名常量）：\n'
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

  test('唯一的字面字号常量只允许在 online_screen 使用', () {
    // 封面角标 9sp（`kCoverBadgeFontSize`）能留下，前提是**有名字、有注释**
    // 解释为什么不在标尺上 —— 直接写 `fontSize: 9` 会被上一条锁拦住。
    final hits = <String>{};
    for (final path in businessFiles()) {
      final lines = File(path).readAsLinesSync();
      for (final line in lines) {
        if (isComment(line)) continue;
        if (line.contains('kCoverBadgeFontSize')) hits.add(path);
      }
    }
    expect(hits, <String>{
      'lib/ui/screens/online_screen.dart',
    }, reason: '字面字号常量的使用面变了：要么该迁进字阶，要么更新这条锁');
  });
}
