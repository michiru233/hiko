import 'package:flutter/material.dart';

import '../tokens/color_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/type_tokens.dart';

/// M3E 设计系统的运行时容器。
///
/// 只装「会随主题/设置变的东西」：颜色、字体、动效。
/// 形状与海拔是常量标尺（`M3EShape` / `M3EElevation`），不需要实例化。
@immutable
class M3EThemeData {
  const M3EThemeData({
    required this.colors,
    this.type = const M3EType(),
    this.motion = const M3EMotion(),
  });

  /// 从种子色建整套主题。
  ///
  /// 这是**唯一**的对外构造入口：不允许在业务代码里零散拼颜色，
  /// 否则「同一个界面两套色阶」的问题会立刻回来。
  factory M3EThemeData.fromSeed({
    required Color seed,
    required Brightness brightness,
    M3ESchemeVariant variant = M3ESchemeVariant.tonalSpot,
    M3EContrast contrast = M3EContrast.standard,
    M3ESpringScheme motionScheme = M3ESpringScheme.expressive,
    M3EMotionLevel motionLevel = M3EMotionLevel.full,
  }) =>
      M3EThemeData(
        colors: M3EColors.fromSeed(
          seed: seed,
          brightness: brightness,
          variant: variant,
          contrast: contrast,
        ),
        motion: M3EMotion(scheme: motionScheme, level: motionLevel),
      );

  final M3EColors colors;
  final M3EType type;
  final M3EMotion motion;

  M3EThemeData copyWith({
    M3EColors? colors,
    M3EType? type,
    M3EMotion? motion,
  }) =>
      M3EThemeData(
        colors: colors ?? this.colors,
        type: type ?? this.type,
        motion: motion ?? this.motion,
      );

  /// 转回 Material 配色，供尚未迁移的 Material 组件使用。
  ColorScheme toColorScheme() => colors.toColorScheme();

  /// 转回 [ThemeData]，用于「新主题下渲染旧组件」的过渡期。
  ///
  /// 注意：它**不**包含页面转场（`pageTransitionsTheme`）。转场属于应用级配置，
  /// 仍由 `theme.dart` 的 `buildHikoTheme` 负责，两边不要重复定义。
  ThemeData toThemeData() => ThemeData(
        useMaterial3: true,
        colorScheme: toColorScheme(),
        textTheme: type.toTextTheme(),
        scaffoldBackgroundColor: colors.surface,
        canvasColor: colors.surface,
        dividerColor: colors.outlineVariant,
      );
}

/// 把 [M3EThemeData] 挂进 widget 树。
///
/// 用法（`main.dart` 的 `MaterialApp.builder` 里）：
/// ```dart
/// M3ETheme(data: buildM3EThemeData(settings), child: content)
/// ```
///
/// 为什么不用 `ThemeExtension`：ThemeExtension 必须挂在 [ThemeData] 上，
/// 而 [ThemeData] 会被 `Theme()`、`MaterialApp(theme:)` 反复替换，
/// 迁移期新旧主题并存时会互相覆盖。独立的 InheritedWidget 生命周期清晰。
class M3ETheme extends InheritedWidget {
  const M3ETheme({super.key, required this.data, required super.child});

  final M3EThemeData data;

  static M3EThemeData of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<M3ETheme>();
    if (inherited != null) return inherited.data;
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('找不到 M3ETheme。'),
      ErrorDescription(
        'M3E 组件必须挂在 M3ETheme 之下。应用根层已经由 main.dart 的 '
        'MaterialApp.builder 挂好；单测里请用 M3ETheme(data: …, child: …) 包一层。',
      ),
      ErrorHint('若只想临时读值，用 M3ETheme.maybeOf(context)。'),
    ]);
  }

  static M3EThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<M3ETheme>()?.data;

  @override
  bool updateShouldNotify(M3ETheme oldWidget) => oldWidget.data != data;
}

/// `context.m3e.colors.primary` 这种写法。
extension M3EContext on BuildContext {
  M3EThemeData get m3e => M3ETheme.of(this);
}
