import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/widgets/detail_kit.dart';

/// 详情「同一语义只有一个组件」的源码锁（1.99.44）。
///
/// 1.99.44 之前：本地详情用 `HikoTrackRowM3E` / `HikoDetailInfoRowM3E`，
/// 在线详情用旧的 `HikoTrackRow` / `HikoInfoRow` / `HikoSegmentedTabs`，
/// 同一屏里两套行高（56 vs 36）、两套选中态（色阶 vs 描边）。这一版把在线换过来
/// 并删掉旧类，这里锁住「别又长回来」。
void main() {
  const oldSymbols = <String>[
    'HikoTrackRow(',
    'HikoInfoRow(',
    'HikoSegmentedTabs(',
    'HikoTabButton(',
  ];

  test('lib/ui 里不再出现旧详情组件', () {
    final offenders = <String>[];
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        for (final needle in oldSymbols) {
          if (lines[i].contains(needle)) {
            offenders.add('${file.path}:${i + 1} → $needle');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: '详情行/信息行只保留 M3E 版');
  });

  test('两端详情面板宽度统一为 420，且都引用同一个常量', () {
    expect(kHikoDetailPanelWidth, 420);

    for (final path in <String>[
      'lib/ui/screens/home_screen.dart', // 本地详情（桌面右侧 M3ESheet）
      'lib/ui/screens/online_screen.dart', // 在线详情
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('kHikoDetailPanelWidth'),
        isTrue,
        reason: '$path 应使用共享宽度常量',
      );
      expect(
        RegExp(r'width:\s*(390|480)').hasMatch(source),
        isFalse,
        reason: '$path 不应再出现写死的详情宽度',
      );
    }
  });
}
