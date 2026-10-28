import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// 1.99.57：轻提示只有**一个面**。
///
/// 之前有三套材质（Overlay 反色面 / 根通知层 `#292735` / Material SnackBar），
/// 差别小到单独看都成立，但同一个「已复制」在本地与在线观感不同。这里锁住
/// 这个面长什么样，防止有人再在业务里临时 `Container` 一个近似版。
void main() {
  BoxDecoration decorationOf(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(M3ESnackbar),
        matching: find.byType(Container),
      ).first,
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('面用 toastSurface + sm 圆角，文字 onToastSurface 且无下划线', (tester) async {
    await tester.pumpWidget(
      wrapM3E(const M3ESnackbar(message: '已复制 RJ123456')),
    );

    final deco = decorationOf(tester);
    expect(deco.color, M3ESemantic.toastSurface);
    expect(
      deco.borderRadius,
      M3EShape.radius(M3EShape.sm),
      reason: '角必须走档位，不能回到任意数字',
    );

    final text = tester.widget<Text>(find.text('已复制 RJ123456'));
    expect(text.style?.color, M3ESemantic.onToastSurface);
    expect(text.style?.decoration, TextDecoration.none);
  });

  testWidgets('明暗两个主题用同一个面（深色底的提示在任何背景上都读得清）', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        wrapM3E(
          const M3ESnackbar(message: '提示'),
          brightness: brightness,
        ),
      );
      expect(
        decorationOf(tester).color,
        M3ESemantic.toastSurface,
        reason: '$brightness 下提示面被改成了会随主题漂移的颜色',
      );
    }
  });

  testWidgets('给 icon 时多一个前导图标，且与文字同色', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const M3ESnackbar(message: '扫描完成', icon: Icons.check_rounded),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.check_rounded);
    expect(icon.color, M3ESemantic.onToastSurface);
  });
}
