import 'package:flutter/material.dart';

/// M3E 的 15 个字体角色。
///
/// 每个角色有「基础」与「emphasized」两套，**字号与行高完全相同，只改字重与字距**
/// （见 [m3eTypeSpecs]）。所以 emphasized 不是另一套排版，而是同一套排版里的强调开关。
enum M3ETypeRole {
  displayLarge,
  displayMedium,
  displaySmall,
  headlineLarge,
  headlineMedium,
  headlineSmall,
  titleLarge,
  titleMedium,
  titleSmall,
  bodyLarge,
  bodyMedium,
  bodySmall,
  labelLarge,
  labelMedium,
  labelSmall,
}

/// 单个角色的排版规格（数值照抄 `TypeScaleTokens.kt` v0_103）。
@immutable
class M3ETypeSpec {
  const M3ETypeSpec({
    required this.size,
    required this.lineHeight,
    required this.tracking,
    required this.weight,
    required this.emphasizedTracking,
    required this.emphasizedWeight,
  });

  /// 字号（sp / 逻辑像素）。**必须是原始值，不含任何用户缩放** ——
  /// 全局字号由 `main.dart` 根层 `TextScaler` 统一放大。
  /// 若在 token 里再乘一次 `settings.fontScale`，1.30 档会变成 1.69（见 §4.3 的坑 1）。
  final double size;

  /// 行高（sp），渲染时换算成 [TextStyle.height] 的倍率。
  final double lineHeight;

  /// 基础字距（sp）。
  final double tracking;

  /// 基础字重。
  final FontWeight weight;

  /// emphasized 字距（sp）。
  final double emphasizedTracking;

  /// emphasized 字重。
  final FontWeight emphasizedWeight;
}

/// 15 个角色的完整规格表。回归锁逐值比对这张表。
const Map<M3ETypeRole, M3ETypeSpec> m3eTypeSpecs = <M3ETypeRole, M3ETypeSpec>{
  M3ETypeRole.displayLarge: M3ETypeSpec(
    size: 57,
    lineHeight: 64,
    tracking: -0.2,
    weight: FontWeight.w400,
    emphasizedTracking: 0,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.displayMedium: M3ETypeSpec(
    size: 45,
    lineHeight: 52,
    tracking: 0,
    weight: FontWeight.w400,
    emphasizedTracking: 0,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.displaySmall: M3ETypeSpec(
    size: 36,
    lineHeight: 44,
    tracking: 0,
    weight: FontWeight.w400,
    emphasizedTracking: 0,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.headlineLarge: M3ETypeSpec(
    size: 32,
    lineHeight: 40,
    tracking: 0,
    weight: FontWeight.w400,
    emphasizedTracking: 0,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.headlineMedium: M3ETypeSpec(
    size: 28,
    lineHeight: 36,
    tracking: 0,
    weight: FontWeight.w400,
    emphasizedTracking: 0,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.headlineSmall: M3ETypeSpec(
    size: 24,
    lineHeight: 32,
    tracking: 0,
    weight: FontWeight.w400,
    emphasizedTracking: 0,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.titleLarge: M3ETypeSpec(
    size: 22,
    lineHeight: 28,
    tracking: 0,
    weight: FontWeight.w400,
    emphasizedTracking: 0,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.titleMedium: M3ETypeSpec(
    size: 16,
    lineHeight: 24,
    tracking: 0.2,
    weight: FontWeight.w500,
    emphasizedTracking: 0.15,
    emphasizedWeight: FontWeight.w700,
  ),
  M3ETypeRole.titleSmall: M3ETypeSpec(
    size: 14,
    lineHeight: 20,
    tracking: 0.1,
    weight: FontWeight.w500,
    emphasizedTracking: 0.1,
    emphasizedWeight: FontWeight.w700,
  ),
  M3ETypeRole.bodyLarge: M3ETypeSpec(
    size: 16,
    lineHeight: 24,
    tracking: 0.5,
    weight: FontWeight.w400,
    emphasizedTracking: 0.15,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.bodyMedium: M3ETypeSpec(
    size: 14,
    lineHeight: 20,
    tracking: 0.2,
    weight: FontWeight.w400,
    emphasizedTracking: 0.25,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.bodySmall: M3ETypeSpec(
    size: 12,
    lineHeight: 16,
    tracking: 0.4,
    weight: FontWeight.w400,
    emphasizedTracking: 0.4,
    emphasizedWeight: FontWeight.w500,
  ),
  M3ETypeRole.labelLarge: M3ETypeSpec(
    size: 14,
    lineHeight: 20,
    tracking: 0.1,
    weight: FontWeight.w500,
    emphasizedTracking: 0.1,
    emphasizedWeight: FontWeight.w700,
  ),
  M3ETypeRole.labelMedium: M3ETypeSpec(
    size: 12,
    lineHeight: 16,
    tracking: 0.5,
    weight: FontWeight.w500,
    emphasizedTracking: 0.5,
    emphasizedWeight: FontWeight.w700,
  ),
  M3ETypeRole.labelSmall: M3ETypeSpec(
    size: 11,
    lineHeight: 16,
    tracking: 0.5,
    weight: FontWeight.w500,
    emphasizedTracking: 0.5,
    emphasizedWeight: FontWeight.w700,
  ),
};

/// M3E 字体层。
///
/// **不打包字体**（见 §4.3）：这是个日文内容为主的库，打包 Latin 字体只会让
/// 中日文与拉丁文混排时字重对不上。这里只给字号/行高/字距/字重，
/// 字体族留空，由 `DefaultTextStyle` 继承系统字体。
@immutable
class M3EType {
  const M3EType();

  /// 基础 15 档。整套值都是常量，构建一次缓存起来，不随主题重建。
  static final Map<M3ETypeRole, TextStyle> _base =
      <M3ETypeRole, TextStyle>{
    for (final role in M3ETypeRole.values) role: _styleOf(role, emphasized: false),
  };

  /// emphasized 15 档（同字号、更重、字距微调）。
  static final Map<M3ETypeRole, TextStyle> _emphasized =
      <M3ETypeRole, TextStyle>{
    for (final role in M3ETypeRole.values) role: _styleOf(role, emphasized: true),
  };

  static TextStyle _styleOf(M3ETypeRole role, {required bool emphasized}) {
    final spec = m3eTypeSpecs[role]!;
    return TextStyle(
      fontSize: spec.size,
      height: spec.lineHeight / spec.size,
      letterSpacing: emphasized ? spec.emphasizedTracking : spec.tracking,
      fontWeight: emphasized ? spec.emphasizedWeight : spec.weight,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  /// 按角色取样式。[emphasized] 为 true 时取加强版（同字号、更重、字距微调）。
  TextStyle role(M3ETypeRole role, {bool emphasized = false}) =>
      (emphasized ? _emphasized : _base)[role]!;

  TextStyle get displayLarge => role(M3ETypeRole.displayLarge);
  TextStyle get displayMedium => role(M3ETypeRole.displayMedium);
  TextStyle get displaySmall => role(M3ETypeRole.displaySmall);
  TextStyle get headlineLarge => role(M3ETypeRole.headlineLarge);
  TextStyle get headlineMedium => role(M3ETypeRole.headlineMedium);
  TextStyle get headlineSmall => role(M3ETypeRole.headlineSmall);
  TextStyle get titleLarge => role(M3ETypeRole.titleLarge);
  TextStyle get titleMedium => role(M3ETypeRole.titleMedium);
  TextStyle get titleSmall => role(M3ETypeRole.titleSmall);
  TextStyle get bodyLarge => role(M3ETypeRole.bodyLarge);
  TextStyle get bodyMedium => role(M3ETypeRole.bodyMedium);
  TextStyle get bodySmall => role(M3ETypeRole.bodySmall);
  TextStyle get labelLarge => role(M3ETypeRole.labelLarge);
  TextStyle get labelMedium => role(M3ETypeRole.labelMedium);
  TextStyle get labelSmall => role(M3ETypeRole.labelSmall);

  TextStyle get displayLargeEmphasized =>
      role(M3ETypeRole.displayLarge, emphasized: true);
  TextStyle get displayMediumEmphasized =>
      role(M3ETypeRole.displayMedium, emphasized: true);
  TextStyle get displaySmallEmphasized =>
      role(M3ETypeRole.displaySmall, emphasized: true);
  TextStyle get headlineLargeEmphasized =>
      role(M3ETypeRole.headlineLarge, emphasized: true);
  TextStyle get headlineMediumEmphasized =>
      role(M3ETypeRole.headlineMedium, emphasized: true);
  TextStyle get headlineSmallEmphasized =>
      role(M3ETypeRole.headlineSmall, emphasized: true);
  TextStyle get titleLargeEmphasized =>
      role(M3ETypeRole.titleLarge, emphasized: true);
  TextStyle get titleMediumEmphasized =>
      role(M3ETypeRole.titleMedium, emphasized: true);
  TextStyle get titleSmallEmphasized =>
      role(M3ETypeRole.titleSmall, emphasized: true);
  TextStyle get bodyLargeEmphasized =>
      role(M3ETypeRole.bodyLarge, emphasized: true);
  TextStyle get bodyMediumEmphasized =>
      role(M3ETypeRole.bodyMedium, emphasized: true);
  TextStyle get bodySmallEmphasized =>
      role(M3ETypeRole.bodySmall, emphasized: true);
  TextStyle get labelLargeEmphasized =>
      role(M3ETypeRole.labelLarge, emphasized: true);
  TextStyle get labelMediumEmphasized =>
      role(M3ETypeRole.labelMedium, emphasized: true);
  TextStyle get labelSmallEmphasized =>
      role(M3ETypeRole.labelSmall, emphasized: true);

  /// 转成 Material 的 [TextTheme]（只映射基础 15 档，emphasized 由调用方按需取）。
  ///
  /// 用途：给还没迁移的 Material 组件兜底，让它们的字号与新体系一致。
  TextTheme toTextTheme() => TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        displaySmall: displaySmall,
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      );
}
