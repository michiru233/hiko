import 'package:flutter/widgets.dart';

/// M3E 形状标尺（10 档）。
///
/// 来源：`androidx.compose.material3.tokens.ShapeTokens`（14_1_0）。
/// 粗体三档（20 / 32 / 48）是 Material 3 Expressive（2025-05）新增的，
/// 旧 M3 只有 0/4/8/12/16/28/full 七档 —— 这正是现在 Hiko 圆角集中在 6~12、
/// 观感偏「旧 Material」的根因（见 plan-hiko-m3e-redesign.md §4.4）。
///
/// **嵌套规则（M3 强制）**：父容器与子元素的圆角**不得相同**，
/// 内圆角 = 外圆角 − 内边距，否则视觉上内外角会「打架」。用 [nested] 计算。
abstract final class M3EShape {
  /// 直角
  static const double none = 0;

  /// 4dp：列表项静息态、小徽标
  static const double xs = 4;

  /// 8dp：芯片、缩略图内角
  static const double sm = 8;

  /// 12dp：卡片内图、FAB 小号
  static const double md = 12;

  /// 16dp：Hiko 内容面基准（卡片、列表容器、FAB 常规）
  static const double lg = 16;

  /// 20dp：Express 新增，大卡片可选档
  static const double lgPlus = 20;

  /// 28dp：对话框、播放页封面、FAB 大号
  static const double xl = 28;

  /// 32dp：Express 新增，封面播放态
  static const double xlPlus = 32;

  /// 48dp：Express 新增，大面积装饰容器
  static const double xxl = 48;

  /// 全圆：按钮、芯片、指示器、播放条
  ///
  /// 用 999 而不是 `double.infinity`：后者会让 `BorderRadius.circular` 在
  /// 部分布局下产生 NaN 宽度（Flutter 的 `RRect` 对无穷半径行为未定义）。
  static const double full = 999;

  /// 全部十档，顺序即标尺顺序。回归锁直接比对这张表。
  static const List<double> scale = <double>[
    none,
    xs,
    sm,
    md,
    lg,
    lgPlus,
    xl,
    xlPlus,
    xxl,
    full,
  ];

  /// 嵌套内圆角：`inner = outer − padding`，下限 0。
  ///
  /// 例：卡片 16dp、内边距 4dp → 封面 12dp。
  static double nested(double outer, double padding) {
    final inner = outer - padding;
    return inner < 0 ? 0 : inner;
  }

  /// 四角同半径。
  static BorderRadius radius(double value) => BorderRadius.circular(value);

  /// 外层盒子的形状。
  static RoundedRectangleBorder border(double value) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(value));
}
