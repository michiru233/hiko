import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「对话框不许再退回 Material」的源码锁（1.99.42）。
///
/// 21 处 `AlertDialog` 一次性收口到 `M3EDialog` 之后，最大的风险不是这次改错，
/// 而是下一次有人图快又 `new` 一个 `AlertDialog` —— 它自带 `dialogTheme` 的壳，
/// 看上去「也还行」，于是慢慢长回第二套内边距与按钮。审计 C-10 / C-12 记的正是
/// 这条回流路径。
///
/// 只扫 `lib/ui`（设计系统自己除外），并且跳过注释行：文档里提到这些名字是
/// 合理的（`m3e_dialog.dart` 的解释性注释就写着 `AlertDialog`）。
void main() {
  test('lib/ui 里不再出现 AlertDialog / CheckboxListTile / RadioListTile', () {
    const forbidden = <String>[
      'AlertDialog(',
      'CheckboxListTile(',
      'RadioListTile(',
    ];
    final offenders = <String>[];

    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => !f.path.contains(
            '${Platform.pathSeparator}m3e'
            '${Platform.pathSeparator}',
          ),
        );

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        for (final needle in forbidden) {
          if (lines[i].contains(needle)) {
            offenders.add('${file.path}:${i + 1} → $needle');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '用 M3EDialog / M3EListItem 代替；确需例外请显式记录在计划文件里。',
    );
  });
}
