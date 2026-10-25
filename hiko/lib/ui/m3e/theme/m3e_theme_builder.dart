import 'package:flutter/material.dart';

import '../../../data/settings_store.dart';
import '../../theme.dart' show parseHexColor;
import '../tokens/color_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'm3e_theme.dart';

/// 把 [AppSettings] 翻译成 [M3EThemeData]。
///
/// 过渡期（1.99.26~1.99.29）只有两个输入：强调色与明暗。
/// 1.99.30 接入「配色来源」（跟随系统 / 自选图片 / 预设）与对比度档、
/// 动效档，届时本函数签名会扩参数，但调用点只有 `main.dart` 一处。
M3EThemeData buildM3EThemeData(AppSettings settings) => M3EThemeData.fromSeed(
      seed: parseHexColor(settings.accent),
      brightness: settings.theme == 'dark' ? Brightness.dark : Brightness.light,
    );

/// 记忆化用的缓存键。
///
/// `M3EThemeData.fromSeed` 要跑一整套 HCT 色调板（几十次色彩空间转换），
/// 而 `MaterialApp.builder` 会因为 MediaQuery 变化（键盘弹起、窗口缩放）频繁重建 ——
/// 不缓存的话每次重建都白算一遍配色。
String m3eThemeCacheKey(AppSettings settings) =>
    '${settings.accent}|${settings.theme}';

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
