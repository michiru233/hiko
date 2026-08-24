import 'package:flutter/material.dart';

import '../data/settings_store.dart';

/// 主题：移植旧版 styles.css 的浅/深两套配色 + 6 强调色，
/// 用 Material 3 ColorScheme.fromSeed 生成组件色，覆盖表面色保持原观感。
class HikoColors {
  // 浅色
  static const lightBg = Color(0xFFF6F5F2);
  static const lightInk = Color(0xFF20232A);
  static const lightMuted = Color(0xFF888B92);
  static const lightLine = Color(0xFFE6E3DE);
  static const lightSidebar = Color(0xFFEFEEE9);
  static const lightTrack = Color(0xFFE6E2DE);
  static const lightCard = Colors.white;

  // 深色
  static const darkBg = Color(0xFF1D1F24);
  static const darkInk = Color(0xFFE7E5E0);
  static const darkMuted = Color(0xFF9A9AA1);
  static const darkLine = Color(0xFF2E3138);
  static const darkSidebar = Color(0xFF17181D);
  static const darkTrack = Color(0xFF3A3D45);
  static const darkCard = Color(0xFF23252C);
}

/// '#6559d8' → Color
Color parseHexColor(String hex) {
  var value = hex.replaceAll('#', '');
  if (value.length == 6) value = 'FF$value';
  return Color(int.tryParse(value, radix: 16) ?? 0xFF6559D8);
}

ThemeData buildHikoTheme(AppSettings settings) {
  final dark = settings.theme == 'dark';
  final accent = parseHexColor(settings.accent);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  final bg = dark ? HikoColors.darkBg : HikoColors.lightBg;
  final ink = dark ? HikoColors.darkInk : HikoColors.lightInk;
  final line = dark ? HikoColors.darkLine : HikoColors.lightLine;
  final card = dark ? HikoColors.darkCard : HikoColors.lightCard;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
  );

  // 全局 Ink 按压反馈（1.32）：M3 水波纹 + 按压 overlay ≥0.12 alpha
  // （splash 为扩散波纹略强以保证深色背景可见；highlight 为按压持续 overlay）
  final pressedOverlay = accent.withValues(alpha: 0.12);
  final inkOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) return pressedOverlay;
    if (states.contains(WidgetState.hovered)) {
      return accent.withValues(alpha: 0.06);
    }
    return null;
  });

  // 桌面端统一点击指针（Material 组件默认 adaptiveClickable，这里显式兜底）；
  // 按钮类 overlay 压到 ≥0.12（M3 默认 0.08~0.10 偏弱，实机观感"没反馈"）
  ButtonStyle inkButtonStyle() => ButtonStyle(
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
        overlayColor: inkOverlay,
      );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
      fontFamily: 'DM Sans',
      fontFamilyFallback: const ['Noto Sans SC', 'Noto Sans JP'],
    ),
    dividerColor: line,
    canvasColor: bg,
    cardColor: card,
    splashFactory: InkRipple.splashFactory,
    splashColor: accent.withValues(alpha: dark ? 0.28 : 0.18),
    highlightColor: pressedOverlay,
    filledButtonTheme: FilledButtonThemeData(style: inkButtonStyle()),
    outlinedButtonTheme: OutlinedButtonThemeData(style: inkButtonStyle()),
    textButtonTheme: TextButtonThemeData(style: inkButtonStyle()),
    iconButtonTheme: IconButtonThemeData(style: inkButtonStyle()),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? HikoColors.darkCard : const Color(0xFFFAF9F7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      thumbColor: Colors.white,
      overlayColor: accent.withValues(alpha: 0.12),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF292735),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
  );
}
