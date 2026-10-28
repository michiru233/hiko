import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「提示与进度只有一条路径」的源码锁（1.99.57）。
///
/// 收口前的事实：同一个「已复制」在本地是 M3E toast、在在线详情是
/// Material SnackBar；进度条则有 Material 细条 / 详情与播放条各自写轨道色 /
/// 下载中心自绘 `Stack` 三套（审计 C-08 与 P0-2）。
///
/// 这类债不会一次改错，而是**慢慢长回来**：`showSnackBar` 是一行就能写完的
/// API，`LinearProgressIndicator` 也是，任何一次「先让它跑起来」都会绕过组件。
/// 所以锁在源码层，而不是锁截图。
///
/// 口径与 `style_ledger_lock_test` / `no_material_dialogs_test` 一致：
/// 只扫 `lib/ui`、排除 `m3e/`（设计系统自己实现它们）、跳过注释行 ——
/// 文档里提到这些名字恰恰是在解释「为什么不再用」。
void main() {
  bool isComment(String line) {
    final t = line.trimLeft();
    return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
  }

  List<File> businessFiles() => Directory('lib/ui')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('${Platform.pathSeparator}m3e'
          '${Platform.pathSeparator}'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('提示只能走 showHikoToast，不得再用 ScaffoldMessenger / SnackBar', () {
    const forbidden = <String>[
      'showSnackBar',
      'SnackBar(',
      'ScaffoldMessenger.',
    ];
    final offenders = <String>[];
    for (final file in businessFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (isComment(lines[i])) continue;
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
      reason: '轻提示统一用 showHikoToast（材质见 M3ESnackbar）：\n'
          '${offenders.join('\n')}',
    );
  });

  test('进度条只能用 M3EProgress，业务层不得出现 LinearProgressIndicator', () {
    final offenders = <String>[];
    for (final file in businessFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (isComment(lines[i])) continue;
        if (lines[i].contains('LinearProgressIndicator')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '用 M3EProgress（有值时带轨道 4dp，.thin() 是 2dp 活动条）：\n'
          '${offenders.join('\n')}',
    );
  });

  test('提示面的颜色只有一个来源：M3ESemantic.toastSurface', () {
    // 谁在业务层写死 toast 面颜色，就说明又开了一条旁路。
    final holders = <String>{};
    for (final file in businessFiles()) {
      final text = file.readAsStringSync();
      if (text.contains('M3ESemantic.toastSurface') ||
          text.contains('M3ESemantic.onToastSurface')) {
        holders.add(file.path);
      }
    }
    expect(
      holders,
      <String>{'lib/ui/widgets/activity_overlay.dart'},
      reason: 'toast 面只应出现在 activity_overlay 的活动条上；'
          '轻提示请用 M3ESnackbar',
    );
  });
}
