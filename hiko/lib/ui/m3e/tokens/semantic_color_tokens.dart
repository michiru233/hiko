import 'package:flutter/material.dart';

/// 一对「底色 + 字色」的染色胶囊。
///
/// 在线卡片的元数据胶囊（艺术家 / 社团 / 下载量 / 时长）是同一套语法：
/// 浅底 + 同色相深字；暗色主题下底色降 alpha、字色提亮，**不换色相**。
/// 把这对值收进一个类型，是为了让「底色记住了、字色漏了」这种漂移不可能发生。
@immutable
class M3ETintPair {
  const M3ETintPair({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

/// 产品语义色 —— **不属于** Material 那 37 个角色，也不由种子色派生。
///
/// 为什么必须独立于 [M3EColors]：这些颜色承载的是**信息**而不是层级。
/// 用户把强调色改成绿色，社团胶囊仍然得是紫的、声优仍得是蓝的 ——
/// 否则「靠色相区分声优 / 社团 / 下载量」这条读卡规则当场失效。
/// 把它们塞进 `ColorScheme` 的任何一档，都会在换种子色时被一起算掉。
///
/// 也因此这里全是 `static const`：调色板不随主题变（除了两处明确按明暗分叉的：
/// [tagForeground] 与三个胶囊对），不需要 `context`，也就不必进 [M3EThemeData]。
///
/// **业务代码不得再写字面色值**（`style_ledger_lock` 会拦）：
/// 需要哪一支就从这里取。新增一支前先问「它是不是其实该用
/// `onSurfaceVariant` / `secondaryContainer` 这类层级色」。
abstract final class M3ESemantic {
  // ---------------------------------------------------------------- 分色
  //
  // 详情页与筛选标记上的 4dp 圆点。1.99.47 起不再整底染色（裁决 Q3），
  // 圆点负责区分，胶囊底色交回中性面。

  /// 社团紫
  static const Color circleTint = Color(0xFFB39DDB);

  /// 声优蓝
  static const Color voiceTint = Color(0xFF90CAF9);

  // ---------------------------------------------------------------- 强调
  //
  // 这三个是「动作 / 状态」的固有色，与强调色无关：收藏红不能因为用户把
  // 主色改成蓝色就不再是红的。

  /// 收藏红
  static const Color favorite = Color(0xFFD34C44);

  /// 评分金（星星、评分胶囊）
  static const Color rating = Color(0xFFE8B33C);

  /// 成功绿（检查更新已是最新、完成态）
  static const Color success = Color(0xFF4CAF50);

  // ---------------------------------------------------------------- 统计

  /// 听完
  static const Color statFinished = Color(0xFF4C9E6B);

  /// 听过（与 [rating] 同色：同一支金，两处语义）
  static const Color statStarted = rating;

  /// 未听
  static const Color statUnplayed = Color(0xFF9A8FC2);

  // ------------------------------------------------------------ DLsite 标签

  /// 标签底（青）：暗色主题下靠 alpha 降下来，见 [HikoTagChip] 的用法
  static const Color tagBackground = Color(0xFFE3F4F2);

  /// 标签字（亮色主题）
  static const Color tagForegroundLight = Color(0xFF2E8A8F);

  /// 标签字（暗色主题）：同一色相提亮，保证深底可读
  static const Color tagForegroundDark = Color(0xFF8FDDE2);

  /// 标签字色随主题取亮 / 暗
  static Color tagForeground(bool isDark) =>
      isDark ? tagForegroundDark : tagForegroundLight;

  // ------------------------------------------------------ 在线元数据胶囊
  //
  // 五类胶囊刻意取互不重叠的色相（蓝 / 琥珀金 / 玫红 / 中性灰），
  // RJ 号那支走主色实底（随种子色变），不在这里。

  /// 艺术家（声优）
  static M3ETintPair artistPill(bool isDark) => isDark
      ? const M3ETintPair(
          background: Color(0x3390CAF9),
          foreground: Color(0xFFB6DBFC),
        )
      : const M3ETintPair(
          background: Color(0xFFE1EFFC),
          foreground: Color(0xFF2C6DA8),
        );

  /// 社团（琥珀金：与详情页的紫刻意错开，免得和主色实底的作品号糊成一片）
  static M3ETintPair circlePill(bool isDark) => isDark
      ? const M3ETintPair(
          background: Color(0x33E8C87A),
          foreground: Color(0xFFEFD79B),
        )
      : const M3ETintPair(
          background: Color(0xFFFBF0DA),
          foreground: Color(0xFF8F6410),
        );

  /// 下载量（玫红：与琥珀金同为暖色但色相差得够开）
  static M3ETintPair downloadPill(bool isDark) => isDark
      ? const M3ETintPair(
          background: Color(0x33E88DA8),
          foreground: Color(0xFFF0AFC0),
        )
      : const M3ETintPair(
          background: Color(0xFFFCE9EF),
          foreground: Color(0xFFA8425F),
        );

  /// 时长（中性灰：它就是个数字，不该跟任何一支色相抢注意力）
  static M3ETintPair neutralPill(bool isDark) => isDark
      ? const M3ETintPair(
          background: Color(0x0FFFFFFF),
          foreground: Color(0xFF9A9AA1),
        )
      : const M3ETintPair(
          background: Color(0x0D000000),
          foreground: Color(0xFF888B92),
        );

  // ---------------------------------------------------------------- 提示层
  //
  // 恒暗面：toast / 活动条在亮暗两套主题下都是深底白字（与 `inverseSurface`
  // 不同 —— 后者在暗色主题下会翻成亮面，那时白字就读不出来了）。

  /// 提示层底
  static const Color toastSurface = Color(0xFF292735);

  /// 提示层字
  static const Color onToastSurface = Colors.white;

  // ------------------------------------------------------------ 封面渐变
  //
  // 播放页封面的三段渐变，底端锚点色。亮色主题用白、暗色主题用近黑，
  // 作用是把封面颜色「洗」向页面底色，本身不该被认成任何一种表面色。

  /// 封面渐变底端（暗色主题）
  static const Color artworkVignette = Color(0xFF101010);
}
