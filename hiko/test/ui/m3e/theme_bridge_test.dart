import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/theme.dart';

/// 旧主题桥的清理锁（1.99.48）。
///
/// `theme.dart` 是「还没迁到 M3E 的 Material 组件」的兜底，理论上应当越来越薄。
/// 1.99.48 删掉了它自己的 14 支调色板（`HikoColors`）与从未打包的 `DM Sans`
/// 声明，并补上了审计 D-08 点名的滚动条 / Tooltip 主题。
///
/// 这三件事都特别容易长回来：加一支颜色只要一行、写个字体名不报错、
/// 少一条主题在亮色下才看得出来。所以逐项上锁。
void main() {
  String source(String path) => File(path).readAsStringSync();

  group('旧调色板', () {
    test('theme.dart 不再定义 HikoColors', () {
      final body = source('lib/ui/theme.dart');
      expect(body.contains('class HikoColors'), isFalse);
    });

    test('全 lib 不再引用 HikoColors（注释里的历史说明除外）', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final t = lines[i].trimLeft();
          if (t.startsWith('//') || t.startsWith('*')) continue;
          if (lines[i].contains('HikoColors')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('文字 / 分隔线 / 卡片面改由角色派生', () {
      final body = source('lib/ui/theme.dart');
      expect(body.contains('scheme.onSurface'), isTrue);
      expect(body.contains('scheme.outlineVariant'), isTrue);
      expect(body.contains('scheme.surfaceContainerLow'), isTrue);
    });
  });

  group('字体', () {
    test('theme.dart 不再声明 DM Sans（注释里的历史说明不算）', () {
      final lines = File('lib/ui/theme.dart').readAsLinesSync();
      final offenders = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final t = lines[i].trimLeft();
        if (t.startsWith('//') || t.startsWith('*')) continue;
        if (lines[i].contains('DM Sans'))
          offenders.add('${i + 1}: ${lines[i]}');
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('运行时 textTheme 与对话框标题都不是 DM Sans', () {
      final theme = buildHikoTheme(const AppSettings());
      expect(theme.textTheme.bodyMedium?.fontFamily, isNot('DM Sans'));
      expect(theme.dialogTheme.titleTextStyle?.fontFamily, isNot('DM Sans'));
    });

    test('CJK 回退链保留（Windows 缺字还要靠它）', () {
      final theme = buildHikoTheme(const AppSettings());
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        containsAll(<String>['Noto Sans SC', 'Noto Sans JP']),
      );
    });
  });

  group('审计 D-08：滚动条与 Tooltip', () {
    test('滚动条主题在位：6dp 粗、4dp 圆角、中性拇指', () {
      final theme = buildHikoTheme(const AppSettings());
      expect(theme.scrollbarTheme.thickness?.resolve(<WidgetState>{}), 6);
      expect(theme.scrollbarTheme.radius, const Radius.circular(4));
      expect(
        theme.scrollbarTheme.thumbColor?.resolve(<WidgetState>{}),
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
      );
    });

    test('Tooltip 主题在位：反色面 + 4dp 圆角 + 12sp', () {
      final theme = buildHikoTheme(const AppSettings());
      final decoration = theme.tooltipTheme.decoration as BoxDecoration?;
      expect(decoration?.color, theme.colorScheme.inverseSurface);
      expect(
        (decoration?.borderRadius as BorderRadius?)?.topLeft,
        const Radius.circular(4),
      );
      expect(theme.tooltipTheme.textStyle?.fontSize, 12);
      expect(
        theme.tooltipTheme.textStyle?.color,
        theme.colorScheme.onInverseSurface,
      );
    });
  });
}
