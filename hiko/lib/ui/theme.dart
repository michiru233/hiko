import 'package:flutter/material.dart';

import '../data/settings_store.dart';
import 'm3e/tokens/shape_tokens.dart';
import 'transitions/fullscreen_player_route.dart';

/// '#6559d8' → Color
Color parseHexColor(String hex) {
  var value = hex.replaceAll('#', '');
  if (value.length == 6) value = 'FF$value';
  return Color(int.tryParse(value, radix: 16) ?? 0xFF6559D8);
}

/// 旧主题桥：把 [AppSettings] 翻成一份 [ThemeData]，给尚未迁到 M3E 的
/// Material 组件兜底（对话框、输入框、滚动条、Tooltip 等）。
///
/// **1.99.48 起这里不再有自己的调色板**：`HikoColors` 那 14 支写死的浅/深色
/// 已全部删除，文字 / 分隔线 / 卡片面改为从 `ColorScheme` 的角色派生
/// （见下方的 `ink / line / card`）。
/// 业务代码需要颜色时只能用 M3E 角色或 `M3ESemantic`，不要再往这里加常量。
ThemeData buildHikoTheme(AppSettings settings) {
  // 1.99.30：主题三态（light/dark/system）；system 走 platformDispatcher
  //（与 m3e_theme_builder.hikoBrightness 同语义，就地内联避免反向依赖）
  final dark = switch (settings.theme) {
    'dark' => true,
    'system' =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
    _ => false,
  };
  final accent = parseHexColor(settings.accent);
  // 1.99.35：对比度档传给 ColorScheme（与 M3E 主题同一档），保证
  // scaffold 与 M3EAppBar/rail 的 surface 逐字节一致（用户反馈三区色不统一）
  final contrastLevel = switch (settings.contrast) {
    'medium' => 0.5,
    'high' => 1.0,
    _ => 0.0,
  };
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: dark ? Brightness.dark : Brightness.light,
    contrastLevel: contrastLevel,
  );
  // 1.99.35：页面底色统一到 M3E surface（与 M3EAppBar/rail 同层），
  // 旧 darkBg/lightBg 与 fromSeed 派生色并存导致「顶条/顶栏/rail 三区三色」
  final bg = scheme.surface;
  // 1.99.48：旧 `HikoColors` 的 ink / line / card 三支改由角色派生 ——
  // 它们本来就是 onSurface / outlineVariant / 内容面的同义复述，
  // 单独存一份只会在换种子色时与 M3E 那半边错开。
  final ink = scheme.onSurface;
  final line = scheme.outlineVariant;
  final card = scheme.surfaceContainerLow;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 1.99.30（D6）：背景图不再铺底，scaffold 永远实底；
    // Scaffold 全透明让背景透出（1.84）
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
      // 1.99.48：删掉 `fontFamily: 'DM Sans'` —— 这个字体从未打进包，
      // 声明它只让两端的回退链多绕一层（macOS 落到系统字、Android 落到
      // 系统 CJK），实际形同虚设。回退链保留，Windows 的 CJK 缺字还要靠它。
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
    // 1.99.30 M3E 对话框壳（plan §8.8）：角 28、surfaceContainerHigh、
    // 标题 headlineSmall —— 6 个 AlertDialog 一次覆盖
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
        fontFamilyFallback: const ['Noto Sans SC', 'Noto Sans JP'],
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      thumbColor: Colors.white,
      overlayColor: accent.withValues(alpha: 0.12),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    // 1.88 应用统一转场语言：整页「底部 8px 升起 + 淡入」入场，
    // 被新页覆盖时「150ms 前载退场（淡出 + 0.98 微缩 + 3px 渐变模糊）」。
    // 挂在主题上而非单个路由：退场由「被覆盖的那一级」自己的 secondaryAnimation
    // 驱动，只能靠全局转场器统一。静态路由（如首页）静息态零图层开销。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: HikoPageTransitionsBuilder(),
        TargetPlatform.iOS: HikoPageTransitionsBuilder(),
        TargetPlatform.macOS: HikoPageTransitionsBuilder(),
        TargetPlatform.windows: HikoPageTransitionsBuilder(),
        TargetPlatform.linux: HikoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: HikoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    // 1.99.48（审计 D-08）：桌面滚动条与 Tooltip 此前完全走 Material 默认 ——
    // 亮色下滚动条是一条灰黑细线、Tooltip 的圆角与字号也和 M3E 不接。
    // 这里按 M3E 的形状与反色面补两条，免得「只差这两个控件」看起来像两个应用。
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(M3EShape.xs),
      crossAxisMargin: 2,
      thumbColor: WidgetStatePropertyAll(
        scheme.onSurfaceVariant.withValues(alpha: 0.45),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(M3EShape.xs),
      ),
      textStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 12,
        fontFamilyFallback: const ['Noto Sans SC', 'Noto Sans JP'],
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF292735),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 12),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
  );
}
