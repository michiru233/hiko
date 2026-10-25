import 'package:flutter/material.dart';

import '../../../data/settings_store.dart';
import '../../theme.dart' show parseHexColor;
import '../tokens/color_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'm3e_theme.dart';

/// 设置 → 亮度解析（1.99.30 起三态：light / dark / system）。
///
/// `system` 走 platformDispatcher（MaterialApp 之上拿不到 MediaQuery）；
/// 平台亮度变化时由 main.dart 的 WidgetsBindingObserver 触发重建。
Brightness hikoBrightness(AppSettings settings) => switch (settings.theme) {
      'dark' => Brightness.dark,
      'system' => WidgetsBinding.instance.platformDispatcher.platformBrightness,
      _ => Brightness.light,
    };

M3EContrast _contrastFromKey(String key) => switch (key) {
      'medium' => M3EContrast.medium,
      'high' => M3EContrast.high,
      _ => M3EContrast.standard,
    };

M3EMotionLevel _motionFromKey(String key) => switch (key) {
      'reduced' => M3EMotionLevel.reduced,
      'off' => M3EMotionLevel.off,
      _ => M3EMotionLevel.full,
    };

/// 把 [AppSettings] 翻译成 [M3EThemeData]。
///
/// 种子色由调用方解析（1.99.30 配色来源链：custom 图片 / system 壁纸 /
/// preset 强调色，解析有异步 IO，落在 main.dart 的一层缓存里），
/// 本函数只负责「种子 + 明暗 + 对比度 + 动效档」的纯装配。
M3EThemeData buildM3EThemeData(AppSettings settings, {Color? seed}) =>
    M3EThemeData.fromSeed(
      seed: seed ?? parseHexColor(settings.accent),
      brightness: hikoBrightness(settings),
      contrast: _contrastFromKey(settings.contrast),
      motionLevel: _motionFromKey(settings.motionLevel),
    );

/// 记忆化用的缓存键。
///
/// `M3EThemeData.fromSeed` 要跑一整套 HCT 色调板（几十次色彩空间转换），
/// 而 `MaterialApp.builder` 会因为 MediaQuery 变化（键盘弹起、窗口缩放）频繁重建 ——
/// 不缓存的话每次重建都白算一遍配色。
String m3eThemeCacheKey(AppSettings settings, {Color? seed}) =>
    '${seed?.value ?? settings.accent}|${settings.theme}|'
    '${settings.seedSource}|${settings.contrast}|${settings.motionLevel}';

/// 供测试与调试直接构造：不带 AppSettings 的完整主题。
M3EThemeData debugM3ETheme({
  Color seed = const Color(0xFF6559D8),
  Brightness brightness = Brightness.light,
  M3ESchemeVariant variant = M3ESchemeVariant.tonalSpot,
  M3EContrast contrast = M3EContrast.standard,
  M3EMotionLevel motionLevel = M3EMotionLevel.full,
}) =>
    M3EThemeData.fromSeed(
      seed: seed,
      brightness: brightness,
      variant: variant,
      contrast: contrast,
      motionLevel: motionLevel,
    );
