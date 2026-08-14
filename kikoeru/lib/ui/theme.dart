import 'package:flutter/material.dart';

import '../data/settings_store.dart';

/// 主题：移植旧版 styles.css 的浅/深两套配色 + 6 强调色，
/// 用 Material 3 ColorScheme.fromSeed 生成组件色，覆盖表面色保持原观感。
class KikoeruColors {
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

ThemeData buildKikoeruTheme(AppSettings settings) {
  final dark = settings.theme == 'dark';
  final accent = parseHexColor(settings.accent);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  final bg = dark ? KikoeruColors.darkBg : KikoeruColors.lightBg;
  final ink = dark ? KikoeruColors.darkInk : KikoeruColors.lightInk;
  final muted = dark ? KikoeruColors.darkMuted : KikoeruColors.lightMuted;
  final line = dark ? KikoeruColors.darkLine : KikoeruColors.lightLine;
  final card = dark ? KikoeruColors.darkCard : KikoeruColors.lightCard;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
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
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? KikoeruColors.darkCard : const Color(0xFFFAF9F7),
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
