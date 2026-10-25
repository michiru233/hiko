import 'package:flutter/material.dart';

/// 配色变体（对应 Material Color Utilities 的 `Variant`）。
///
/// **默认 [tonalSpot]，不是 [expressive]。**
/// 这个选择很关键：`expressive` 会把主色的色相旋转 240°，也就是用户选了蓝色、
/// 界面的 primary 变成别的颜色 —— 对「用户自选强调色」的产品语义是破坏性的。
/// M3E 的「vibrant」指的是色彩更饱和（[vibrant]），不是换色相。
enum M3ESchemeVariant {
  /// Material You 2021 默认：低彩度、柔和，主色基本等于种子色
  tonalSpot(DynamicSchemeVariant.tonalSpot),

  /// 高彩度、色相不变 —— 想更「有颜色」时用这档
  vibrant(DynamicSchemeVariant.vibrant),

  /// 主色色相与种子色不同（+240°），靠色相制造新鲜感
  expressive(DynamicSchemeVariant.expressive),

  /// 令牌贴近种子色，primaryContainer 直接用种子色
  content(DynamicSchemeVariant.content),

  /// 与 content 类似，但容器色会为对比度做调整
  fidelity(DynamicSchemeVariant.fidelity),

  /// 近乎灰阶
  neutral(DynamicSchemeVariant.neutral),

  /// 纯灰阶
  monochrome(DynamicSchemeVariant.monochrome);

  const M3ESchemeVariant(this.flutter);

  final DynamicSchemeVariant flutter;
}

/// 无障碍对比度档（M3 规范自带三档）。
enum M3EContrast {
  /// 标准：混合高低对比，靠层级降低认知负担
  standard(0),

  /// 中：正文至少 3:1
  medium(0.5),

  /// 高：正文至少 7:1
  high(1);

  const M3EContrast(this.level);

  /// 喂给 `ColorScheme.fromSeed(contrastLevel:)` 的值（0 / 0.5 / 1）。
  final double level;
}

/// M3E 颜色角色全集。
///
/// 共 37 个角色：4 主色 + 4 次色 + 4 三色 + 4 错误 + 8 表面 + 5 容器 + 3 反色 + 3 描边/底影。
///
/// **层深的表达方式**：`surface` 是页面底，`surfaceContainerLow` 是内容面，
/// `surfaceContainerHigh` 是浮起面（菜单、播放条），`surfaceContainerHighest` 是最亮面。
/// 层级靠这五档明度差，不靠投影 —— 这是 M3E 与旧版玻璃拟态最根本的分歧。
@immutable
class M3EColors {
  const M3EColors({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.scrim,
    required this.shadow,
    required this.surfaceTint,
  });

  /// 从种子色生成整套角色。
  ///
  /// 直接用 Flutter 的 [ColorScheme.fromSeed]：它内部走的就是 Material Color
  /// Utilities（HCT + 色调板），并且**自 3.47 起支持 `dynamicSchemeVariant`
  /// 与 `contrastLevel`** —— 所以整个 M3E 配色层不需要任何第三方依赖。
  factory M3EColors.fromSeed({
    required Color seed,
    required Brightness brightness,
    M3ESchemeVariant variant = M3ESchemeVariant.tonalSpot,
    M3EContrast contrast = M3EContrast.standard,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: variant.flutter,
      contrastLevel: contrast.level,
    );
    return M3EColors.fromColorScheme(scheme);
  }

  /// 由已有 [ColorScheme] 转换（迁移期复用 Material 的配色结果）。
  factory M3EColors.fromColorScheme(ColorScheme scheme) => M3EColors(
        brightness: scheme.brightness,
        primary: scheme.primary,
        onPrimary: scheme.onPrimary,
        primaryContainer: scheme.primaryContainer,
        onPrimaryContainer: scheme.onPrimaryContainer,
        secondary: scheme.secondary,
        onSecondary: scheme.onSecondary,
        secondaryContainer: scheme.secondaryContainer,
        onSecondaryContainer: scheme.onSecondaryContainer,
        tertiary: scheme.tertiary,
        onTertiary: scheme.onTertiary,
        tertiaryContainer: scheme.tertiaryContainer,
        onTertiaryContainer: scheme.onTertiaryContainer,
        error: scheme.error,
        onError: scheme.onError,
        errorContainer: scheme.errorContainer,
        onErrorContainer: scheme.onErrorContainer,
        surface: scheme.surface,
        onSurface: scheme.onSurface,
        onSurfaceVariant: scheme.onSurfaceVariant,
        surfaceDim: scheme.surfaceDim,
        surfaceBright: scheme.surfaceBright,
        surfaceContainerLowest: scheme.surfaceContainerLowest,
        surfaceContainerLow: scheme.surfaceContainerLow,
        surfaceContainer: scheme.surfaceContainer,
        surfaceContainerHigh: scheme.surfaceContainerHigh,
        surfaceContainerHighest: scheme.surfaceContainerHighest,
        outline: scheme.outline,
        outlineVariant: scheme.outlineVariant,
        inverseSurface: scheme.inverseSurface,
        onInverseSurface: scheme.onInverseSurface,
        inversePrimary: scheme.inversePrimary,
        scrim: scheme.scrim,
        shadow: scheme.shadow,
        surfaceTint: scheme.surfaceTint,
      );

  final Brightness brightness;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;

  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;

  /// 比 [surface] 暗一档（深色模式下是「更低」的底）
  final Color surfaceDim;

  /// 比 [surface] 亮一档（深色模式下是「更高」的浮起底）
  final Color surfaceBright;

  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  final Color outline;
  final Color outlineVariant;

  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;

  final Color scrim;
  final Color shadow;
  final Color surfaceTint;

  bool get isDark => brightness == Brightness.dark;

  /// 转回 Material 的 [ColorScheme]，供尚未迁移的组件兜底。
  ColorScheme toColorScheme() => ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        surfaceDim: surfaceDim,
        surfaceBright: surfaceBright,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        outline: outline,
        outlineVariant: outlineVariant,
        inverseSurface: inverseSurface,
        onInverseSurface: onInverseSurface,
        inversePrimary: inversePrimary,
        scrim: scrim,
        shadow: shadow,
        surfaceTint: surfaceTint,
      );

  /// 五档容器色的有序列表（Lowest → Highest），用于回归锁与调试。
  List<Color> get containerScale => <Color>[
        surfaceContainerLowest,
        surfaceContainerLow,
        surfaceContainer,
        surfaceContainerHigh,
        surfaceContainerHighest,
      ];
}
