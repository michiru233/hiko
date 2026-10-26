import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

/// `M3EType.scaled` 的回归锁（1.99.49）。
///
/// 这个入口存在的唯一目的：让「用户文字倍率」不再把基准字号抄到调用点
/// （以前是 `fontSize: 12 * textScale`，基准一改就漂两处）。
/// 所以锁的重点不是「能放大」，而是**基准仍来自角色**、**行高比例不变**。
void main() {
  const type = M3EType();

  test('倍率 1 时原样返回角色样式（连行高与字距都不动）', () {
    for (final role in M3ETypeRole.values) {
      expect(type.scaled(role, 1), type.role(role));
    }
  });

  test('放大只改字号：字号 × 倍率，其余字段逐项相等', () {
    const factor = 1.3;
    for (final role in M3ETypeRole.values) {
      final base = type.role(role);
      final scaled = type.scaled(role, factor);
      expect(
        scaled.fontSize,
        closeTo(base.fontSize! * factor, 0.0001),
        reason: '$role 的字号没有按倍率放大',
      );
      expect(scaled.height, base.height, reason: '$role 的行高比例被改掉了');
      expect(scaled.fontWeight, base.fontWeight);
      expect(scaled.letterSpacing, base.letterSpacing);
    }
  });

  test('emphasized 变体缩放后仍是 emphasized 的字重', () {
    final scaled = type.scaled(M3ETypeRole.titleLarge, 1.3, emphasized: true);
    expect(
      scaled.fontWeight,
      type.role(M3ETypeRole.titleLarge, emphasized: true).fontWeight,
    );
    expect(
      scaled.fontSize,
      closeTo(type.role(M3ETypeRole.titleLarge).fontSize! * 1.3, 0.0001),
    );
  });

  test('基准字号只来自 token 表（不是调用点抄的第二份）', () {
    expect(
      type.labelSmall.fontSize,
      m3eTypeSpecs[M3ETypeRole.labelSmall]!.size,
    );
    expect(type.bodySmall.fontSize, m3eTypeSpecs[M3ETypeRole.bodySmall]!.size);
    expect(
      type.scaled(M3ETypeRole.bodySmall, 0.5).fontSize,
      closeTo(m3eTypeSpecs[M3ETypeRole.bodySmall]!.size * 0.5, 0.0001),
    );
  });
}
