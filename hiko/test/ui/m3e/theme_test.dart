import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

void main() {
  final data = testTheme();

  testWidgets('M3ETheme.of 取回挂载的数据', (tester) async {
    late M3EThemeData read;
    await tester.pumpWidget(
      MaterialApp(
        home: M3ETheme(
          data: data,
          child: Builder(
            builder: (context) {
              read = context.m3e;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(identical(read, data), isTrue);
  });

  testWidgets('没有 M3ETheme 时回退到 Material 主题派生（不崩）', (tester) async {
    late M3EThemeData read;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFF006874)),
        home: Builder(
          builder: (context) {
            read = M3ETheme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(read.colors.primary.a, 1.0);
    expect(read.motion.level, M3EMotionLevel.full);
  });

  testWidgets('回退结果按 (主色, 明暗) 缓存，不会每次重建都重算', (tester) async {
    final themes = <M3EThemeData>[];
    Widget app(String tag) => MaterialApp(
          theme: ThemeData(colorSchemeSeed: const Color(0xFF006874)),
          home: Builder(
            builder: (context) {
              themes.add(M3ETheme.of(context));
              return Text(tag);
            },
          ),
        );
    await tester.pumpWidget(app('a'));
    await tester.pumpWidget(app('b')); // 强制重建，走第二次 of()
    expect(themes.length, greaterThanOrEqualTo(2));
    expect(identical(themes.first, themes.last), isTrue);
  });

  testWidgets('maybeOf 在没有祖先时返回 null', (tester) async {
    M3EThemeData? read;
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            called = true;
            read = M3ETheme.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(called, isTrue);
    expect(read, isNull);
  });

  test('toThemeData 把 M3E 色与字阶桥给 Material', () {
    final theme = data.toThemeData();
    expect(theme.colorScheme.primary, data.colors.primary);
    expect(theme.scaffoldBackgroundColor, data.colors.surface);
    expect(theme.textTheme.titleLarge!.fontSize, 22);
    expect(theme.textTheme.bodyMedium!.fontSize, 14);
  });

  test('copyWith 只替换指定部分', () {
    const off = M3EMotion(level: M3EMotionLevel.off);
    final copy = data.copyWith(motion: off);
    expect(copy.motion.level, M3EMotionLevel.off);
    expect(identical(copy.colors, data.colors), isTrue);
    expect(identical(copy.type, data.type), isTrue);
  });

  test('缓存键只受强调色与明暗影响', () {
    // main.dart 用它决定是否重算配色：多一个无关字段会白白重跑 HCT。
    const a = AppSettings(accent: '#6559d8', theme: 'light');
    const b = AppSettings(accent: '#6559d8', theme: 'light');
    const c = AppSettings(accent: '#6559d8', theme: 'dark');
    expect(m3eThemeCacheKey(a), m3eThemeCacheKey(b));
    expect(m3eThemeCacheKey(a), isNot(m3eThemeCacheKey(c)));
  });
}
