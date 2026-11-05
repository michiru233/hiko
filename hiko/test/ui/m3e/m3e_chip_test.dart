import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

/// `M3EChip` 的紧凑档（1.99.70）：在线顶栏只剩「最新」一枚预设，
/// 高度从 32 收到 28，给搜索胶囊让宽度。默认档必须保持 32。
void main() {
  testWidgets('默认 32 高', (tester) async {
    await tester.pumpWidget(
      wrapM3E(const SizedBox(width: 200, child: M3EChip(label: '最新'))),
    );
    expect(tester.getSize(find.byType(M3EChip)).height, 32);
  });

  testWidgets('compact 28 高', (tester) async {
    await tester.pumpWidget(
      wrapM3E(
        const SizedBox(width: 200, child: M3EChip(label: '最新', compact: true)),
      ),
    );
    expect(tester.getSize(find.byType(M3EChip)).height, 28);
  });
}
