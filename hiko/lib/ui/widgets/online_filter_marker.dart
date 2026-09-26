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
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 3, top: 3, bottom: 3),
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
                style: const TextStyle(fontSize: 11, color: hikoTagFgColor),
              ),
            ),
          ),
          _MarkerCloseButton(onClear: onClear, tooltip: '退出标签筛选', color: hikoTagFgColor),
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
      padding: const EdgeInsets.only(left: 8, right: 3, top: 3, bottom: 3),
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

  final VoidCallback onClear;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onClear,
      borderRadius: BorderRadius.circular(8),
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(Icons.close, size: 13, color: color),
        ),
      ),
    );
  }
}
