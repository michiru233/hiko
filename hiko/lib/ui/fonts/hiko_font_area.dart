import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../m3e/theme/m3e_theme.dart';
import '../m3e/tokens/type_tokens.dart';
import 'font_registry.dart';

/// 自定义字体可以作用的五个区域。
///
/// 分区而不是一个全局开关：装饰性字体放在歌词上很好看，放在在线列表里
/// 可能就看不清了 —— 用户要能一处一处关。
enum HikoFontAreaId { ui, dialog, playerBar, lyrics, online }

/// 五个区域各自解析出的引擎族名（null = 该区域用系统字体）。
@immutable
class HikoFontFamilies {
  const HikoFontFamilies({
    this.ui,
    this.dialog,
    this.playerBar,
    this.lyrics,
    this.online,
  });

  /// 从设置解出。没有选字体时五个区域全为 null。
  factory HikoFontFamilies.fromSettings(AppSettings settings) {
    final id = settings.userFontId;
    final family = id.isEmpty ? null : FontRegistry.familyOf(id);
    String? pick(bool on) => on ? family : null;
    return HikoFontFamilies(
      ui: pick(settings.userFontOnUi),
      dialog: pick(settings.userFontOnDialog),
      playerBar: pick(settings.userFontOnPlayer),
      lyrics: pick(settings.userFontOnLyrics),
      online: pick(settings.userFontOnOnline),
    );
  }

  final String? ui;
  final String? dialog;
  final String? playerBar;
  final String? lyrics;
  final String? online;

  String? forArea(HikoFontAreaId area) => switch (area) {
    HikoFontAreaId.ui => ui,
    HikoFontAreaId.dialog => dialog,
    HikoFontAreaId.playerBar => playerBar,
    HikoFontAreaId.lyrics => lyrics,
    HikoFontAreaId.online => online,
  };

  bool get isEmpty =>
      ui == null &&
      dialog == null &&
      playerBar == null &&
      lyrics == null &&
      online == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HikoFontFamilies &&
          other.ui == ui &&
          other.dialog == dialog &&
          other.playerBar == playerBar &&
          other.lyrics == lyrics &&
          other.online == online);

  @override
  int get hashCode => Object.hash(ui, dialog, playerBar, lyrics, online);
}

/// 挂在根层（`MaterialApp.builder`，且在 `ActivityOverlayHost` 之外）的字体作用域。
///
/// 它只提供**素材**，不改变任何渲染：
/// - [families]：五个区域该用哪个族名；
/// - [template]：一份**无字体**的根 [ThemeData]；
/// - [baseM3E]：一份**无字体**的根 [M3EThemeData]。
///
/// 为什么必须从"无字体模板"重建，而不是在 ambient 上 `copyWith`：
/// `TextStyle.copyWith(fontFamily: null)` 与 `TextTheme.apply(fontFamily: null)`
/// 都是「保持原值」的空操作 —— 拿它们关字体是关不掉的（外层字体会漏下来）。
class HikoFontScope extends InheritedWidget {
  const HikoFontScope({
    super.key,
    required this.families,
    required this.template,
    required this.baseM3E,
    required super.child,
  });

  final HikoFontFamilies families;
  final ThemeData template;
  final M3EThemeData baseM3E;

  static HikoFontScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HikoFontScope>();

  /// 某个区域当前该用的族名。没有作用域（独立子树/单测）时返回 null。
  static String? familyFor(BuildContext context, HikoFontAreaId area) =>
      maybeOf(context)?.families.forArea(area);

  @override
  bool updateShouldNotify(HikoFontScope oldWidget) =>
      oldWidget.families != families ||
      !identical(oldWidget.template, template) ||
      !identical(oldWidget.baseM3E, baseM3E);
}

/// 把某个区域包成「该区域自己的字体」。
///
/// 三件套缺一不可（对应三条文本取值路径）：
/// 1. `M3ETheme` —— M3E 组件与 `TextField` 走 `context.m3e.type`；
/// 2. `Theme` —— 尚未迁移的 Material 组件与 `EditableText` 走 `Theme.of`；
/// 3. `DefaultTextStyle` —— `Text` 的样式合并基准（内联 `TextStyle` 也在这一路）。
///
/// 因为每层都从 [HikoFontScope] 的无字体模板重建，区域**允许嵌套**：
/// 歌词在播放条里、播放条在界面里，内层关闭时会真正回到系统字，而不是继承外层。
class HikoFontArea extends StatefulWidget {
  const HikoFontArea({super.key, required this.area, required this.child});

  final HikoFontAreaId area;
  final Widget child;

  @override
  State<HikoFontArea> createState() => _HikoFontAreaState();
}

class _HikoFontAreaState extends State<HikoFontArea> {
  HikoFontFamilies? _families;
  ThemeData? _template;
  M3EThemeData? _baseM3E;
  String? _family;
  ThemeData? _theme;
  TextStyle? _defaultStyle;

  void _rebuild(HikoFontScope scope, String? family) {
    _families = scope.families;
    _template = scope.template;
    _baseM3E = scope.baseM3E;
    _family = family;
    final fallback = family == null ? null : kM3ECjkFallback;
    final textTheme = scope.template.textTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
    );
    final primaryTheme = scope.template.primaryTextTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
    );
    _theme = scope.template.copyWith(
      textTheme: textTheme,
      primaryTextTheme: primaryTheme,
    );
    _defaultStyle = textTheme.bodyMedium ?? const TextStyle();
  }

  @override
  Widget build(BuildContext context) {
    final scope = HikoFontScope.maybeOf(context);
    // 没有根作用域（单测 / 独立子树）时原样返回，不引入任何行为
    if (scope == null) return widget.child;
    final family = scope.families.forArea(widget.area);
    // 比较「素材」而不是 scope 实例：builder 每次重建都会 new 一个 scope，
    // 但字体/模板没变时没必要重算 ThemeData（窗口缩放时每帧都会走到这里）。
    final stale =
        _theme == null ||
        family != _family ||
        scope.families != _families ||
        !identical(scope.template, _template) ||
        !identical(scope.baseM3E, _baseM3E);
    if (stale) _rebuild(scope, family);
    return M3ETheme(
      data: scope.baseM3E.copyWith(type: M3EType(fontFamily: family)),
      child: Theme(
        data: _theme!,
        child: DefaultTextStyle(style: _defaultStyle!, child: widget.child),
      ),
    );
  }
}
