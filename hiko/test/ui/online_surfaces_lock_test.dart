import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 在线三面的「不再退回 Material 控件」源码锁（1.99.45）。
///
/// 1.99.45 把在线浏览 / 收藏 / 卡片 / 分页 / 详情里的 chip、按钮、搜索框全部
/// 换成 M3E 版本。这一层最容易回流：`ChoiceChip` 之类自带 padding 与选中态，
/// 随手一写就能跑，于是又长回第三套规格（审计 C-09）。
///
/// 只扫在线相关文件，并且跳过注释行（`/// 1.99.40：PopupMenuButton → M3EMenu`
/// 这类说明是合理的）。
void main() {
  const files = <String>[
    'lib/ui/screens/online_screen.dart',
    'lib/ui/screens/online_favorites_screen.dart',
    'lib/ui/widgets/online_work_grid.dart',
    'lib/ui/widgets/online_card_kit.dart',
    'lib/ui/widgets/online_detail_panel.dart',
  ];

  const forbidden = <String>[
    'ChoiceChip(',
    'FilterChip(',
    'ActionChip(',
    'InputChip(',
    'PopupMenuButton',
    'FilledButton(',
    'OutlinedButton(',
    'TextButton(',
    'ElevatedButton(',
    'hintColor',
  ];

  test('在线面不再出现 Material chip / 按钮 / hintColor', () {
    final offenders = <String>[];
    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
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
      reason: '在线面统一用 M3EChip / M3EButton / M3ESearchBar / M3EIconButton',
    );
  });

  test('在线卡与本地卡同一件材质：M3ECard + 16 圆角 + 封面 12', () {
    final card = File('lib/ui/screens/online_screen.dart').readAsStringSync();
    expect(card.contains('M3ECard('), isTrue);
    expect(
      card.contains('radius: M3EShape.lg'),
      isTrue,
      reason: '卡片 16 圆角（与 AlbumCard 一致）',
    );
    expect(
      card.contains('M3EShape.md),\n              child: AspectRatio('),
      isTrue,
      reason: '封面 12 圆角（16 − 4 内边距）',
    );
    expect(
      card.contains('M3EElevation.level1'),
      isFalse,
      reason: '内容卡零投影，旧在线卡的 level1 阴影不得回流',
    );
  });
}
