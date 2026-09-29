/// 在线筛选行的「可关闭标记」三件套（1.97.1 从 `online_screen.dart` 抽出）。
///
/// 抽成公开组件的理由是**可测**：它们住在第二行最挤的角落里，窄屏（安卓竖屏）
/// 会被 flex 压到 60–90px 宽 —— 1.97.1 修的正是这个场景下的溢出
/// （标记内部文字不可收缩 → `RenderFlex overflow` → ✕ 被顶出屏幕外）。
/// 回归锁在 `test/ui/online_filter_marker_test.dart`，要锁就必须能独立 pump。
///
/// ## 布局不变量（1.97.1）
///
/// 标记内部结构必须是 `Row(min, [Flexible(文字), 关闭钮])` —— **文字必须可收缩**：
/// - 外层（筛选行）用 `Flexible` 给标记分配宽度，空间紧张时分配额可以小于期望宽；
/// - 内层若再放一个「不可收缩的文字 + 关闭钮」的 Row，溢出的恰好是关闭钮，
///   用户就只剩一个退不出的筛选（1.97.0 实机截图问题）。
/// `ConstrainedBox(maxWidth: 140)` 只作桌面上限，不承担收缩职责。
///
/// ## 布局不变量（1.99.5 追加）
///
/// **✕ 的可点区域 ≥36×36**（`_MarkerCloseButton.hitSize`）：19×19 的热区在真机上
/// 偏一指节就落空。所以四件套共用同一个关闭钮实现，高度不变量也只在那一处；
/// 新增标记一律走 [OnlineSimpleFilterMarker]，不要再手抄布局。
library;

import 'package:flutter/material.dart';

import '../../data/online/online_provider.dart';
import 'detail_kit.dart';

/// 标签筛选的可关闭标记（1.94.0 裁决 Q7=甲）。
///
/// 形态照搬本地 1.77 那套「社团 / 声优」标记：淡色胶囊 + 尾巴上的 ✕，
/// 颜色用标签自己的青色，和卡面标签保持同一套配色。
class OnlineTagFilterMarker extends StatelessWidget {
  const OnlineTagFilterMarker({
    super.key,
    required this.tag,
    required this.onClear,
    this.maxTextWidth = 140,
  });

  final String tag;
  final VoidCallback onClear;

  /// 文字的宽度上限。内联在第二行时用默认 140（给状态行让位）；
  /// 移动端独占一行时可传更大值，长名字能显示得更完整。
  final double maxTextWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = hikoTagFgColorOf(isDark);
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 0),
      decoration: BoxDecoration(
        color: hikoTagBgColor.withValues(alpha: isDark ? 0.2 : 0.8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 文字必须可收缩（见文件头「布局不变量」）：
          // 空间不足时牺牲自己的省略号，保住右边的 ✕
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTextWidth),
              child: Text(
                '标签：$tag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: fg),
              ),
            ),
          ),
          _MarkerCloseButton(onClear: onClear, tooltip: '退出标签筛选', color: fg),
        ],
      ),
    );
  }
}

/// 声优 / 社团筛选的可关闭标记（1.97.0）。
///
/// 底色用维度自己的胶囊色（声优蓝 / 社团紫），和详情页的人名胶囊同一套配色 ——
/// 用户从那颗胶囊点进来，回过头看到同色标记才能对上「我是从哪筛进来的」。
class OnlineCreatorFilterMarker extends StatelessWidget {
  const OnlineCreatorFilterMarker({
    super.key,
    required this.filter,
    required this.onClear,
    this.maxTextWidth = 140,
  });

  final OnlineCreatorFilter filter;
  final VoidCallback onClear;

  /// 同 [OnlineTagFilterMarker.maxTextWidth]。
  final double maxTextWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = filter.kind == OnlineCreatorKind.va
        ? hikoVoiceColor
        : hikoCircleColor;
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTextWidth),
              child: Text(
                '${filter.label}：${filter.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
          ),
          _MarkerCloseButton(
            onClear: onClear,
            tooltip: '退出${filter.label}筛选',
            color: color,
          ),
        ],
      ),
    );
  }
}

/// 黑名单的可点标记（1.95.0 裁决 Q1=甲）。
///
/// 形态刻意比筛选标记低调（灰系、无彩色）：黑名单是**背景状态**而不是
/// 「你正在看什么」。点开进管理页，是唯一的出口。
/// 1.97.1：文字同样改成可收缩 —— 这颗标记与筛选标记同住一个会被挤压的角落。
class OnlineBlockedTagsMarker extends StatelessWidget {
  const OnlineBlockedTagsMarker({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.hintColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Tooltip(
        message: '管理标签黑名单',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 12, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '已屏蔽 $count 个标签',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkerCloseButton extends StatelessWidget {
  const _MarkerCloseButton({
    required this.onClear,
    required this.tooltip,
    required this.color,
  });

  /// ✕ 的**可点区域**边长（1.99.5，裁决 Q1=A）。
  ///
  /// 修的是一个实机问题：此前 ✕ 的热区就是「13px 图标 + 3px 内边距」= **19×19**，
  /// 只有 Material 最小推荐值（48）的 16% 面积 —— widget 测试里量化过：
  /// 中心点击命中，**指尖偏 14px 就完全落空**（回调不再触发），
  /// 用户感受就是「点不了」。
  ///
  /// 取值 36 与「标记整体的高度代价」：
  /// 热区想变大，承载它的盒子就必须变高（Flutter 的 hit test 不会命中父级尺寸
  /// 之外，OverflowBox 那套绕不过去），所以这里同步把容器的上下内边距**归零**，
  /// 让标记高度正好等于热区高度 —— 胶囊从 21px 长到 36px（可点面积 ×3.6），
  /// 文字左起点与横向留白不变，图标仍是 13px（观感是「胶囊略厚」，不是「✕ 变大」）。
  static const double hitSize = 36;

  final VoidCallback onClear;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: hitSize,
      height: hitSize,
      child: InkWell(
        onTap: onClear,
        // 圆形水波纹跟随 36 的热区，比原来 8 的圆角更贴合手感
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: Center(
            child: Icon(Icons.close, size: 13, color: color),
          ),
        ),
      ),
    );
  }
}

/// 通用「可关闭筛选标记」（1.99.5）。
///
/// 1.97.1 抽出的三件套只覆盖了标签 / 声优社团 / 黑名单三种；1.99.5 新增的
/// **字幕**与**分级**筛选也需要「看得见 + 一键退出」的出口（裁决 Q3=B 的
/// 那条理由：不许出现看不见的筛选）。与其再抄一份布局，这里把共同部分抽出来，
/// 保证四条布局不变量（文字 Flexible / ✕ 热区 36 / 圆角/内边距/字号一致）
/// 只在一处生效。
class OnlineSimpleFilterMarker extends StatelessWidget {
  const OnlineSimpleFilterMarker({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onClear,
    this.icon,
    this.color,
    this.maxTextWidth = 140,
  });

  final String label;
  final String tooltip;
  final VoidCallback onClear;

  /// 可选前置图标（字幕 / 分级各一个，帮助区分同族标记）
  final IconData? icon;

  /// 底色与文字色。默认取主题 hintColor（中性灰，与黑名单标记同族）。
  final Color? color;

  /// 同 [OnlineTagFilterMarker.maxTextWidth]。
  final double maxTextWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.hintColor;
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 0),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          // 文字必须可收缩（见文件头「布局不变量」）
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTextWidth),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c),
              ),
            ),
          ),
          _MarkerCloseButton(onClear: onClear, tooltip: tooltip, color: c),
        ],
      ),
    );
  }
}
