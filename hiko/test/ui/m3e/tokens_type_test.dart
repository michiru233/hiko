import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/tokens/type_tokens.dart';

/// 字阶回归锁：30 个样式逐值比对 `TypeScaleTokens.kt`。
///
/// 为什么逐角色写而不是「循环里塞一堆 expect」：某个角色被改坏时，
/// 测试名会直接指出是哪一个（`titleMedium 基础档`），而不是「某个断言失败了」。
void main() {
  const type = M3EType();

  for (final role in M3ETypeRole.values) {
    test('${role.name} 基础档：字号/行高/字重/字距与 token 一致', () {
      final spec = m3eTypeSpecs[role]!;
      final style = type.role(role);
      expect(style.fontSize, spec.size);
      expect(style.fontWeight, spec.weight);
      expect(style.letterSpacing, spec.tracking);
      expect(style.height, closeTo(spec.lineHeight / spec.size, 1e-9));
    });

    test('${role.name} emphasized 档：字号不变，只改字重与字距', () {
      final spec = m3eTypeSpecs[role]!;
      final base = type.role(role);
      final emphasized = type.role(role, emphasized: true);
      expect(emphasized.fontSize, base.fontSize);
      expect(emphasized.height, base.height);
      expect(emphasized.fontWeight, spec.emphasizedWeight);
      expect(emphasized.letterSpacing, spec.emphasizedTracking);
    });
  }

  test('emphasized 字重规律：title 中/小与全部 label 升到 700，其余 500', () {
    const boldRoles = <M3ETypeRole>{
      M3ETypeRole.titleMedium,
      M3ETypeRole.titleSmall,
      M3ETypeRole.labelLarge,
      M3ETypeRole.labelMedium,
      M3ETypeRole.labelSmall,
    };
    for (final role in M3ETypeRole.values) {
      final expected =
          boldRoles.contains(role) ? FontWeight.w700 : FontWeight.w500;
      expect(type.role(role, emphasized: true).fontWeight, expected,
          reason: role.name);
    }
  });

  test('display/headline/titleLarge 的 emphasized 字距归零（规范明确归一化）', () {
    for (final role in <M3ETypeRole>[
      M3ETypeRole.displayLarge,
      M3ETypeRole.displayMedium,
      M3ETypeRole.displaySmall,
      M3ETypeRole.headlineLarge,
      M3ETypeRole.headlineMedium,
      M3ETypeRole.headlineSmall,
      M3ETypeRole.titleLarge,
    ]) {
      expect(type.role(role, emphasized: true).letterSpacing, 0,
          reason: role.name);
    }
  });

  test('字号缩放锁：token 必须是原始 sp，不预先乘用户缩放', () {
    // 用户的 fontScale（0.85~1.30）由 main.dart 根层 TextScaler 统一放大；
    // token 里再乘一次会让 1.30 档变成 1.69。这条锁防止有人「顺手」在这里乘。
    expect(type.titleLarge.fontSize, 22);
    expect(type.bodyLarge.fontSize, 16);
    expect(type.labelSmall.fontSize, 11);
  });

  test('行高按 sp 换算成倍率（bodyLarge 16/24 → 1.5）', () {
    expect(type.bodyLarge.height, 1.5);
    expect(type.titleMedium.height, 1.5);
    expect(type.labelSmall.height, closeTo(16 / 11, 1e-9));
  });

  test('toTextTheme 映射全部 15 个基础角色', () {
    final textTheme = type.toTextTheme();
    expect(textTheme.displayLarge, type.displayLarge);
    expect(textTheme.displayMedium, type.displayMedium);
    expect(textTheme.displaySmall, type.displaySmall);
    expect(textTheme.headlineLarge, type.headlineLarge);
    expect(textTheme.headlineMedium, type.headlineMedium);
    expect(textTheme.headlineSmall, type.headlineSmall);
    expect(textTheme.titleLarge, type.titleLarge);
    expect(textTheme.titleMedium, type.titleMedium);
    expect(textTheme.titleSmall, type.titleSmall);
    expect(textTheme.bodyLarge, type.bodyLarge);
    expect(textTheme.bodyMedium, type.bodyMedium);
    expect(textTheme.bodySmall, type.bodySmall);
    expect(textTheme.labelLarge, type.labelLarge);
    expect(textTheme.labelMedium, type.labelMedium);
    expect(textTheme.labelSmall, type.labelSmall);
  });

  test('字体族留空（由 DefaultTextStyle 继承系统字体）', () {
    for (final role in M3ETypeRole.values) {
      expect(type.role(role).fontFamily, isNull, reason: role.name);
    }
  });
}
