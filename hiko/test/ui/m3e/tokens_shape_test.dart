import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/tokens/shape_tokens.dart';

/// 形状 token 回归锁：这十个数值是 M3E 的形状标尺，
/// 改动会让整站圆角关系（尤其嵌套规则）失衡，所以逐值锁死。
void main() {
  test('十档圆角与 token 表逐值相等', () {
    expect(M3EShape.scale, <double>[0, 4, 8, 12, 16, 20, 28, 32, 48, 999]);
  });

  test('Express 新增的三档在标尺里（20 / 32 / 48）', () {
    expect(M3EShape.scale, contains(M3EShape.lgPlus));
    expect(M3EShape.scale, contains(M3EShape.xlPlus));
    expect(M3EShape.scale, contains(M3EShape.xxl));
  });

  test('嵌套内圆角 = 外圆角 − padding', () {
    // 卡片 16dp、内边距 4dp → 封面 12dp
    expect(M3EShape.nested(M3EShape.lg, 4), M3EShape.md);
    expect(M3EShape.nested(M3EShape.xl, 16), 12);
  });

  test('嵌套内圆角不会算成负数', () {
    expect(M3EShape.nested(M3EShape.sm, 20), 0);
    expect(M3EShape.nested(0, 8), 0);
  });

  test('radius() 与 BorderRadius.circular 等价', () {
    expect(M3EShape.radius(M3EShape.lg), BorderRadius.circular(16));
  });

  test('border() 用同一半径生成圆角矩形', () {
    final border = M3EShape.border(M3EShape.xl);
    expect(
      border.borderRadius,
      BorderRadius.circular(M3EShape.xl),
    );
  });
}
