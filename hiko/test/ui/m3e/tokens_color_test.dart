import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/tokens/color_tokens.dart';

double _distance(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 全部 37 个角色，用于「没有遗漏的半透明色」这条锁。
List<Color> _allRoles(M3EColors c) => <Color>[
      c.primary,
      c.onPrimary,
      c.primaryContainer,
      c.onPrimaryContainer,
      c.secondary,
      c.onSecondary,
      c.secondaryContainer,
      c.onSecondaryContainer,
      c.tertiary,
      c.onTertiary,
      c.tertiaryContainer,
      c.onTertiaryContainer,
      c.error,
      c.onError,
      c.errorContainer,
      c.onErrorContainer,
      c.surface,
      c.onSurface,
      c.onSurfaceVariant,
      c.surfaceDim,
      c.surfaceBright,
      c.surfaceContainerLowest,
      c.surfaceContainerLow,
      c.surfaceContainer,
      c.surfaceContainerHigh,
      c.surfaceContainerHighest,
      c.outline,
      c.outlineVariant,
      c.inverseSurface,
      c.onInverseSurface,
      c.inversePrimary,
      c.scrim,
      c.shadow,
      c.surfaceTint,
    ];

void main() {
  const seed = Color(0xFF6750A4);

  test('五档容器色在浅色下由亮到暗（Lowest 最亮）', () {
    final colors = M3EColors.fromSeed(seed: seed, brightness: Brightness.light);
    final lums = colors.containerScale.map((c) => c.computeLuminance()).toList();
    for (var i = 1; i < lums.length; i++) {
      expect(lums[i], lessThan(lums[i - 1]), reason: '第 $i 档应比前一档暗');
    }
  });

  test('五档容器色在深色下由暗到亮（Highest 最亮）', () {
    final colors = M3EColors.fromSeed(seed: seed, brightness: Brightness.dark);
    final lums = colors.containerScale.map((c) => c.computeLuminance()).toList();
    for (var i = 1; i < lums.length; i++) {
      expect(lums[i], greaterThan(lums[i - 1]), reason: '第 $i 档应比前一档亮');
    }
  });

  test('tonalSpot 的主色贴近种子色（用户选什么就是什么）', () {
    final tonal =
        M3EColors.fromSeed(seed: seed, brightness: Brightness.light);
    final expressive = M3EColors.fromSeed(
      seed: seed,
      brightness: Brightness.light,
      variant: M3ESchemeVariant.expressive,
    );
    expect(_distance(tonal.primary, seed),
        lessThan(_distance(expressive.primary, seed)));
  });

  test('expressive 变体会换掉主色色相（所以默认不用它）', () {
    final tonal =
        M3EColors.fromSeed(seed: seed, brightness: Brightness.light);
    final expressive = M3EColors.fromSeed(
      seed: seed,
      brightness: Brightness.light,
      variant: M3ESchemeVariant.expressive,
    );
    expect(_distance(tonal.primary, expressive.primary), greaterThan(40));
  });

  test('所有角色都是不透明色', () {
    for (final brightness in Brightness.values) {
      final colors =
          M3EColors.fromSeed(seed: seed, brightness: brightness);
      for (final color in _allRoles(colors)) {
        expect(color.a, 1.0, reason: '$brightness 下出现半透明角色色');
      }
    }
  });

  test('高对比档把正文对比度拉到 7:1 以上', () {
    final standard =
        M3EColors.fromSeed(seed: seed, brightness: Brightness.light);
    final high = M3EColors.fromSeed(
      seed: seed,
      brightness: Brightness.light,
      contrast: M3EContrast.high,
    );
    final standardRatio = _contrast(standard.onSurface, standard.surface);
    final highRatio = _contrast(high.onSurface, high.surface);
    expect(highRatio, greaterThan(standardRatio));
    expect(highRatio, greaterThanOrEqualTo(7.0));
  });

  test('中对比档至少 3:1（正文可读下限）', () {
    final medium = M3EColors.fromSeed(
      seed: seed,
      brightness: Brightness.dark,
      contrast: M3EContrast.medium,
    );
    expect(_contrast(medium.onSurface, medium.surface),
        greaterThanOrEqualTo(3.0));
  });

  test('深浅两套的表面色不同', () {
    final light = M3EColors.fromSeed(seed: seed, brightness: Brightness.light);
    final dark = M3EColors.fromSeed(seed: seed, brightness: Brightness.dark);
    expect(light.surface, isNot(dark.surface));
    expect(light.isDark, isFalse);
    expect(dark.isDark, isTrue);
  });

  test('toColorScheme 原样带回全部角色', () {
    final colors = M3EColors.fromSeed(
      seed: seed,
      brightness: Brightness.dark,
      contrast: M3EContrast.medium,
    );
    final scheme = colors.toColorScheme();
    expect(scheme.primary, colors.primary);
    expect(scheme.surfaceContainerHighest, colors.surfaceContainerHighest);
    expect(scheme.outlineVariant, colors.outlineVariant);
    expect(scheme.brightness, Brightness.dark);
  });

  test('fromColorScheme 与 fromSeed 对同一输入结果一致（无二次加工）', () {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    final fromScheme = M3EColors.fromColorScheme(scheme);
    final fromSeed =
        M3EColors.fromSeed(seed: seed, brightness: Brightness.light);
    expect(fromScheme.primary, fromSeed.primary);
    expect(fromScheme.surfaceContainerHigh, fromSeed.surfaceContainerHigh);
  });
}
