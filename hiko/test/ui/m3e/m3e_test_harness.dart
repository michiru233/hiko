import 'package:flutter/material.dart';
import 'package:hiko/ui/m3e/m3e.dart';

/// M3E 组件测试的统一外壳。
///
/// 组件要求 `M3ETheme` 祖先（找不到会抛 FlutterError），
/// 所以所有组件测试都必须过这一层，而不是各自 `MaterialApp` 裸跑。
M3EThemeData testTheme({
  Brightness brightness = Brightness.light,
  M3EMotionLevel motionLevel = M3EMotionLevel.full,
  M3ESchemeVariant variant = M3ESchemeVariant.tonalSpot,
  Color seed = const Color(0xFF6750A4),
}) =>
    M3EThemeData.fromSeed(
      seed: seed,
      brightness: brightness,
      variant: variant,
      motionLevel: motionLevel,
    );

Widget wrapM3E(
  Widget child, {
  M3EThemeData? theme,
  Brightness brightness = Brightness.light,
}) {
  final data = theme ?? testTheme(brightness: brightness);
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: M3ETheme(
      data: data,
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
