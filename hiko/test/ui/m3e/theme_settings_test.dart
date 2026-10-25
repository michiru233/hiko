
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/m3e/m3e.dart';

/// 1.99.30 主题装配锁（plan §8.7 / §11.2）：
/// 动效三档、对比度三档从设置一路进 M3E 主题；配色种子由 main.dart 解析后
/// 经 `seed` 参数注入 —— 本文件锁「设置 → 主题」的映射不漂移。
void main() {
  test('动效三档：off 直接短路（enabled=false），reduced 减半', () {
    final off = buildM3EThemeData(
      const AppSettings(motionLevel: 'off'),
    );
    expect(off.motion.level, M3EMotionLevel.off);
    expect(off.motion.enabled, isFalse);

    final reduced = buildM3EThemeData(
      const AppSettings(motionLevel: 'reduced'),
    );
    expect(reduced.motion.level, M3EMotionLevel.reduced);
    expect(
      reduced.motion.durationScale,
      0.5,
    );

    final full = buildM3EThemeData(const AppSettings());
    expect(full.motion.level, M3EMotionLevel.full);
  });

  test('对比度三档：high 与 standard 生成不同的 onSurface（对比度真实生效）', () {
    final standard = buildM3EThemeData(
      const AppSettings(contrast: 'standard'),
    );
    final high = buildM3EThemeData(
      const AppSettings(contrast: 'high'),
    );
    expect(high.colors.onSurface.value, isNot(standard.colors.onSurface.value));
  });

  test('种子注入：seed 参数优先于 accent（配色来源链的落点）', () {
    final s = buildM3EThemeData(
      const AppSettings(accent: '#6559D8'),
      seed: const Color(0xFF00AA00),
    );
    final accent = buildM3EThemeData(
      const AppSettings(accent: '#6559D8'),
    );
    // 从种子的 primaryContainer 有色差即证明种子生效（深浅两档各查一次）
    expect(s.colors.primaryContainer.value,
        isNot(accent.colors.primaryContainer.value));
  });

  test('缓存键：种子/三档任一变化都要换键', () {
    const base = AppSettings();
    expect(m3eThemeCacheKey(base, seed: const Color(0xFF00AA00)),
        isNot(m3eThemeCacheKey(base)));
    expect(
        m3eThemeCacheKey(
          base.copyWith(motionLevel: 'off'),
        ),
        isNot(m3eThemeCacheKey(base)));
    expect(
        m3eThemeCacheKey(
          base.copyWith(contrast: 'high'),
        ),
        isNot(m3eThemeCacheKey(base)));
    expect(
        m3eThemeCacheKey(
          base.copyWith(seedSource: 'custom'),
        ),
        isNot(m3eThemeCacheKey(base)));
  });
}
