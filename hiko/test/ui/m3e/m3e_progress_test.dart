import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// 1.99.57：进度条收口到 `M3EProgress`。
///
/// 建这个组件之前全产品有三套实现（Material 细条 / 详情与播放条各自写轨道色 /
/// 下载中心自绘 Stack）。这里锁三件事：**两种形态的高度与轨道策略**、
/// **颜色默认值与覆盖**、**NaN 不得漏进绘制**（下载进度 `0/0` 会算出 NaN）。
void main() {
  LinearProgressIndicator inner(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );

  testWidgets('默认 4dp 带轨道，指示色取 primary', (tester) async {
    final theme = testTheme();
    await tester.pumpWidget(
      wrapM3E(
        const SizedBox(width: 200, child: M3EProgress(value: 0.5)),
        theme: theme,
      ),
    );

    final bar = inner(tester);
    expect(bar.value, 0.5);
    expect(bar.minHeight, 4);
    expect(bar.backgroundColor, theme.colors.surfaceContainerHighest);
    expect(
      (bar.valueColor as AlwaysStoppedAnimation<Color>).value,
      theme.colors.primary,
    );
    expect(tester.getSize(find.byType(M3EProgress)).height, 4);
  });

  testWidgets('thin 形态是 2dp 且无轨道（透明底）', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const SizedBox(width: 200, child: M3EProgress.thin()),
      ),
    );

    final bar = inner(tester);
    expect(bar.minHeight, 2);
    expect(bar.value, isNull, reason: 'thin 默认不定量');
    expect(bar.backgroundColor, Colors.transparent);
    expect(tester.getSize(find.byType(M3EProgress)).height, 2);
  });

  testWidgets('颜色可覆盖：轨道与指示都跟着传参走', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const SizedBox(
          width: 200,
          child: M3EProgress(
            value: 0.25,
            color: Colors.red,
            trackColor: Colors.green,
          ),
        ),
      ),
    );

    final bar = inner(tester);
    expect(bar.backgroundColor, Colors.green);
    expect((bar.valueColor as AlwaysStoppedAnimation<Color>).value, Colors.red);
  });

  testWidgets('NaN 收成 0，不会交给 Canvas', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const SizedBox(width: 200, child: M3EProgress(value: double.nan)),
      ),
    );

    final bar = inner(tester);
    expect(bar.value, 0.0);
    expect(bar.value!.isNaN, isFalse);
  });

  testWidgets('超出 0~1 的值被夹住', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const SizedBox(width: 200, child: M3EProgress(value: 1.7)),
      ),
    );
    expect(inner(tester).value, 1.0);
  });
}
