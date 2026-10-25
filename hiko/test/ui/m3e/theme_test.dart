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

  testWidgets('没有 M3ETheme 时 of 抛出可读错误', (tester) async {
    late Object error;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            try {
              M3ETheme.of(context);
            } catch (e) {
              error = e;
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(error, isA<FlutterError>());
    expect('$error', contains('M3ETheme'));
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
