/// 在线卡片上的**元数据胶囊**（1.99.21）。
///
/// 为什么单独一个文件而不是塞进 `online_screen.dart` 当私有类：
/// 「艺术家 / 社团 / RJ号 / 时长 / 下载量 的胶囊颜色必须互相区分」是用户审阅
/// 示意图时点名的要求 —— 而「区分」是能被测试钉住的性质（取色函数是纯函数），
/// 写成 `_Pill` 就只能靠肉眼。
///
/// 与 `HikoTagChip` 的分工：
/// * 这边是**元数据**（固定那几项，由作品属性决定，不可交互）；
/// * 那边是**分类**（数量不定，可点筛、可长按屏蔽）。
/// 两者的字号旋钮也是分开的：元数据跟着在线卡片文字倍率
/// （`onlineCardTextScale`），标签跟着 `HikoTagFontScope`。
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 一类胶囊的底色 / 字色（+ 是否加粗）
class OnlinePillColors {
  const OnlinePillColors({
    required this.bg,
    required this.fg,
    this.bold = false,
  });

  final Color bg;
  final Color fg;
  final bool bold;
}

/// 胶囊类别 —— 决定配色。
///
/// 类是**语义**而不是位置：同一个类目在卡片上的位置将来会变，
/// 但「艺术家就是那支蓝」不该跟着变。
enum OnlinePillKind {
  /// 艺术家（声优）
  artist,

  /// 社团（专辑艺术家）
  circle,

  /// DLsite 作品号
  rj,

  /// 时长
  duration,

  /// 下载量
  download,
}

/// 取某一类胶囊的配色。
///
/// 六类胶囊（含标签那类的青色）刻意取六支**互不重叠的色相**，语法却是同一套：
/// 浅底 + 同色相深字（暗色主题下底色降 alpha、字色提亮，不换色相）——
/// 一排看过去既能互相区分，又不会像六种互不相干的 UI 元件。
///
/// 只有 `rj` 走实底反白：在线卡片上它是最能定位作品的一枚，
/// 也是本地卡面一直以来的处理方式（主色实底 + 反白 + 加粗）。
OnlinePillColors onlinePillColors(
  OnlinePillKind kind, {
  required bool isDark,
  required ColorScheme scheme,
}) {
  switch (kind) {
    case OnlinePillKind.artist:
      // 蓝：与详情页的声优胶囊同色相（`hikoVoiceColor` 0xFF90CAF9）
      return isDark
          ? const OnlinePillColors(
              bg: Color(0x3390CAF9),
              fg: Color(0xFFB6DBFC),
            )
          : const OnlinePillColors(
              bg: Color(0xFFE1EFFC),
              fg: Color(0xFF2C6DA8),
            );
    case OnlinePillKind.circle:
      // 琥珀金：与上面那支紫的社团胶囊（详情页 `hikoCircleColor`）刻意错开，
      // 免得「卡片上一排紫胶囊」和主色实底的作品号糊成一片
      return isDark
          ? const OnlinePillColors(
              bg: Color(0x33E8C87A),
              fg: Color(0xFFEFD79B),
            )
          : const OnlinePillColors(
              bg: Color(0xFFFBF0DA),
              fg: Color(0xFF8F6410),
            );
    case OnlinePillKind.rj:
      return OnlinePillColors(
        bg: scheme.primary.withValues(alpha: 0.9),
        fg: scheme.onPrimary,
        bold: true,
      );
    case OnlinePillKind.duration:
      // 中性灰：它就是个数字，不该跟任何一支色相抢注意力
      return isDark
          ? const OnlinePillColors(
              bg: Color(0x0FFFFFFF),
              fg: HikoColors.darkMuted,
            )
          : const OnlinePillColors(
              bg: Color(0x0D000000),
              fg: HikoColors.lightMuted,
            );
    case OnlinePillKind.download:
      // 玫红：与琥珀金同为暖色但色相差得够开（40° vs 335°），
      // 也和「青色标签」「蓝色艺术家」不会看混
      return isDark
          ? const OnlinePillColors(
              bg: Color(0x33E88DA8),
              fg: Color(0xFFF0AFC0),
            )
          : const OnlinePillColors(
              bg: Color(0xFFFCE9EF),
              fg: Color(0xFFA8425F),
            );
  }
}

/// 元数据胶囊的基准字号。命中 [OnlinePill.scale]（在线卡片文字倍率）
const double kOnlinePillFontSize = 10;

/// 卡面元数据胶囊：艺术家 / 社团 / RJ号 / 时长 / 下载量。
///
/// 文字允许换行（不截断）：社团名与作品名一样长的情况很常见，
/// 截断后只剩「サークル名…」等于没说 —— 卡片本来就是瀑布流可变高，
/// 多占一行没有代价。
class OnlinePill extends StatelessWidget {
  const OnlinePill({
    super.key,
    required this.kind,
    required this.text,
    this.scale = 1.0,
  });

  final OnlinePillKind kind;
  final String text;

  /// 在线卡片文字倍率（设置 `onlineCardTextScale`）。
  ///
  /// 由卡片传入而不是这里自己读：同一个倍率还要给标题用，
  /// 两处各自 `ref.watch` 迟早会读到不同的一帧。
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = onlinePillColors(
      kind,
      isDark: theme.brightness == Brightness.dark,
      scheme: theme.colorScheme,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        softWrap: true,
        style: TextStyle(
          fontSize: kOnlinePillFontSize * scale,
          fontWeight: colors.bold ? FontWeight.w700 : FontWeight.w600,
          color: colors.fg,
        ),
      ),
    );
  }
}
