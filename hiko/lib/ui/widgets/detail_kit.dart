/// 详情页共用件（本地专辑详情抽屉 ↔ 在线作品详情面板）。
///
/// 1.91.0 抽出：两处详情页要求视觉完全一致，复制一份必然漂移，
/// 所以把颜色、间距、圆角、字号这些常量收在这里，两边都从这里取。
/// 数值全部照搬 1.83–1.90 的 `detail_drawer.dart`，未做任何视觉调整。
library;

import 'package:flutter/material.dart';

import '../../utils/time.dart';
import '../theme.dart';

// ------------------------------------------------------------------ 调色板

/// 社团胶囊紫（1.77 起沿用）
const Color hikoCircleColor = Color(0xFFB39DDB);

/// 声优胶囊蓝
const Color hikoVoiceColor = Color(0xFF90CAF9);

/// DLsite 标签底色 / 字色
const Color hikoTagBgColor = Color(0xFFE3F4F2);
const Color hikoTagFgColor = Color(0xFF2E8A8F);

/// 收藏红 / 评分金（详情页操作胶囊用）
const Color hikoFavoriteColor = Color(0xFFD34C44);
const Color hikoRatingColor = Color(0xFFE8B33C);

// ------------------------------------------------------------------ 样式件

/// 详情页里的描边胶囊按钮（收藏 / 评分 / 整理专辑 / 在浏览器打开…）
ButtonStyle hikoOutlinedPillStyle({
  required bool isDark,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
}) =>
    OutlinedButton.styleFrom(
      padding: padding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(
        color: isDark ? HikoColors.darkGlassBorder : HikoColors.lightGlassBorderSubtle,
      ),
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
    );

/// 详情页里的实心胶囊按钮（从头播放 / 播放全部）
ButtonStyle hikoFilledPillStyle() => FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      elevation: 0,
    );

/// 可点胶囊的悬停 / 按下反馈（1.95.0 裁决 Q2=甲、Q3=丙）。
///
/// **为什么不能靠 `InkWell` 自带的 hover 高亮**：ink 画在最近的 `Material` 上，
/// 而在本项目里那层在胶囊**不透明底色之下**（详情面板 / 卡片的底色都是不透明的），
/// 于是墨迹被完全盖住 —— 用户看到的就是「指针碰上去毫无变化，不知道这东西能点」
/// （1.95.0 用户实测反馈）。所以这里自己管状态，由 [builder] 把反馈画在胶囊自己身上。
///
/// 反馈画在 `foregroundDecoration` 上，**刻意不影响布局尺寸**：卡面标签行的单行截断
/// 是拿 `TextPainter` 量出胶囊宽度算的（`OnlineWorkCard._CardTagRow`），
/// 任何会改变胶囊宽度的装饰都必须同步改那个预算，否则「量」与「画」当场脱节。
///
/// 不可点（[onTap] 为空）时**必须不出现任何反馈** —— 那会让用户以为能点。
class HikoPillInteraction extends StatefulWidget {
  const HikoPillInteraction({
    super.key,
    required this.onTap,
    required this.builder,
    this.borderRadius,
    this.onContextMenu,
  });

  final VoidCallback? onTap;

  /// [active] = 悬停或按下；[onTap] 为空时恒为 `false`
  final Widget Function(BuildContext context, bool active) builder;

  final BorderRadius? borderRadius;

  /// 右键（桌面）/ 长按（触屏）菜单，回调里给的是**全局**坐标
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  State<HikoPillInteraction> createState() => _HikoPillInteractionState();
}

class _HikoPillInteractionState extends State<HikoPillInteraction> {
  bool _hover = false;
  bool _pressed = false;

  bool get _interactive => widget.onTap != null;

  void _setHover(bool value) {
    if (_hover != value) setState(() => _hover = value);
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // 不可点：直接交还子树，不挂 MouseRegion（连手型光标都不该有）
    if (!_interactive) return widget.builder(context, false);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: InkWell(
        onTap: widget.onTap,
        // 墨迹虽然看不见（见类注释），但 onHighlightChanged 仍是一个可靠的
        // 「按下 / 松开」信号，拿来驱动同一套反馈，不必再包一层 GestureDetector
        onHighlightChanged: _setPressed,
        onSecondaryTapDown: widget.onContextMenu == null
            ? null
            : (d) => widget.onContextMenu!(d.globalPosition),
        onLongPress: widget.onContextMenu == null
            ? null
            : () {
                // 触屏没有右键：长按落在胶囊中央，菜单跟随该点弹出
                // （与 `OnlineWorkCard` 的卡片菜单同一套做法）
                final box = context.findRenderObject() as RenderBox?;
                widget.onContextMenu!(box == null
                    ? Offset.zero
                    : box.localToGlobal(box.size.center(Offset.zero)));
              },
        borderRadius: widget.borderRadius,
        child: widget.builder(context, _hover || _pressed),
      ),
    );
  }
}

/// 悬停/按下反馈的过渡时长（三处胶囊统一，避免同样的手感配出三种速度）
const Duration kPillHoverDuration = Duration(milliseconds: 140);

/// 悬停/按下时的描边。**始终非空**（不活跃时是透明边）——
/// `AnimatedContainer` 只在对应字段非空时才建 tween，给 `null` 会让「亮起来」
/// 这一步没有过渡、只有「灭掉」有，看起来像闪一下。
/// 透明边不占布局，所以引不进尺寸变化。
BoxDecoration hikoPillHoverOutline({
  required bool active,
  required Color color,
  required BorderRadius borderRadius,
}) =>
    BoxDecoration(
      borderRadius: borderRadius,
      border: Border.all(
        color: active ? color.withValues(alpha: 0.55) : Colors.transparent,
        width: 1,
      ),
    );

/// 详情页顶部「眼眉」胶囊（本地：分类 · ALBUM 01；在线：来源 · RJ 号）。
/// [onTap] 为空时去掉下拉箭头，表示纯标识不可交互。
class HikoEyebrowPill extends StatelessWidget {
  const HikoEyebrowPill({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final radius = BorderRadius.circular(999);
    return HikoPillInteraction(
      onTap: onTap,
      borderRadius: radius,
      builder: (context, active) => AnimatedContainer(
        duration: kPillHoverDuration,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: active ? 0.22 : 0.12),
          borderRadius: radius,
          border: Border.all(
            color: primary.withValues(alpha: active ? 0.55 : 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 14, color: primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 社团（紫）/ 声优（蓝）分色胶囊。[onTap] 为空即纯展示。
class HikoPersonPill extends StatelessWidget {
  const HikoPersonPill({
    super.key,
    required this.name,
    required this.color,
    this.selected = false,
    this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return HikoPillInteraction(
      onTap: onTap,
      borderRadius: radius,
      builder: (context, active) => AnimatedContainer(
        duration: kPillHoverDuration,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: active
                ? (selected ? 0.42 : 0.28)
                : (selected ? 0.32 : 0.15),
          ),
          borderRadius: radius,
          border: Border.all(
            color: color.withValues(
              alpha: active
                  ? 1.0
                  : (selected ? 0.7 : 0.4),
            ),
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// DLsite 标签胶囊（青色小方角）
///
/// 1.94.0 起也用在**在线卡片的标签行**上（裁决 Q4=按推荐：与本地卡面视觉一致）。
/// 那一处必须做「单行 + 按像素宽度挑前缀 + `+N`」，所以把 [textStyle] 与
/// [horizontalPadding] 提出来当公开常量 —— 量宽度和画出来必须用同一个样式，
/// 两边各写一份字号/内边距是必然会漂移的那种做法。
class HikoTagChip extends StatelessWidget {
  const HikoTagChip({
    super.key,
    required this.tag,
    this.onTap,
    this.muted = false,
    this.blocked = false,
    this.onContextMenu,
  });

  /// 标签文字样式。卡面标签行做宽度预估时用的就是它
  static const TextStyle textStyle =
      TextStyle(fontSize: 9, fontWeight: FontWeight.w500);

  /// 左右内边距（单侧）
  static const double horizontalPadding = 8;

  final String tag;
  final VoidCallback? onTap;

  /// 弱化样式：用于 `+N` 这种「不是标签、但占同一个位置」的胶囊
  final bool muted;

  /// 该标签已被加入**黑名单**（1.95.0 裁决 Q4=乙）：灰掉 + 删除线。
  ///
  /// 与 [muted] 的区别是语义而非外观 —— 两者都走弱化配色，但 `blocked` 额外加删除线，
  /// 好让「这个标签是我自己屏蔽掉的」和「这个胶囊只是个 `+N`」在视觉上可区分。
  final bool blocked;

  /// 右键（桌面）/ 长按（触屏）弹出标签菜单（1.95.0 裁决 Q3=甲）。
  /// 只有可点的标签才该给菜单 —— 不可点的标签给菜单等于给了个死操作。
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = muted || blocked;
    final fg = dim
        ? (isDark ? HikoColors.darkMuted : HikoColors.lightMuted)
        : hikoTagFgColor;
    final radius = BorderRadius.circular(6);

    return HikoPillInteraction(
      onTap: onTap,
      borderRadius: radius,
      // 菜单也只在可点时给：不可点的标签（服务端只给了名字、拿不到 id）没有可做的事
      onContextMenu: onTap == null ? null : onContextMenu,
      builder: (context, active) => AnimatedContainer(
        duration: kPillHoverDuration,
        padding: const EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          // 悬停/按下时「底色加深」：同一支底色抬高 alpha，不换色相，
          // 免得一排标签在指针扫过时闪成另一种颜色
          color: dim
              ? (isDark
                  ? Colors.white.withValues(alpha: active ? 0.13 : 0.06)
                  : Colors.black.withValues(alpha: active ? 0.09 : 0.04))
              : hikoTagBgColor.withValues(
                  alpha: active
                      ? (isDark ? 0.36 : 0.95)
                      : (isDark ? 0.2 : 0.8),
                ),
          borderRadius: radius,
        ),
        foregroundDecoration: hikoPillHoverOutline(
          active: active,
          color: fg,
          borderRadius: radius,
        ),
        child: Text(
          tag,
          style: textStyle.copyWith(
            color: fg,
            decoration: blocked ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

/// 详情页信息行（上方一条分隔线，两端对齐）
class HikoInfoRow extends StatelessWidget {
  const HikoInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: theme.hintColor)),
          Text(value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// 胶囊分段开关里的单个 Tab
class HikoTabButton extends StatelessWidget {
  const HikoTabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.hasBadge = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool hasBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? primaryColor : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? (isDark ? Colors.white : primaryColor)
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
            if (hasBadge) ...[
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 双 Tab 分段开关外壳（曲目列表 / 歌词字幕）
class HikoSegmentedTabs extends StatelessWidget {
  const HikoSegmentedTabs({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? HikoColors.darkGlassBorderSubtle
              : HikoColors.lightGlassBorderSubtle,
        ),
      ),
      child: Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 4),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// 详情页曲目行：圆形播放/暂停键 + 两位序号 + 标题 + 时长。
///
/// 本地与在线共用同一套视觉（1.91.0 抽出）。[indent] 供在线按目录层级缩进，
/// 本地传 0。[name] 由调用方映射（本地 `Track.name`、在线剥掉扩展名的标题）。
class HikoTrackRow extends StatelessWidget {
  const HikoTrackRow({
    super.key,
    required this.index,
    required this.name,
    required this.durationSeconds,
    required this.active,
    required this.playing,
    required this.onTap,
    this.indent = 0.0,
    this.trailing,
  });

  /// 展示用序号（1 起）。在线按「所在目录内」编号，本地按专辑内编号
  final int index;
  final String name;
  final double durationSeconds;
  final bool active;
  final bool playing;
  final VoidCallback onTap;
  final double indent;

  /// 右侧时长左边额外的角标（在线用来放字幕图标）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              InkWell(
                onTap: onTap,
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: active
                        ? theme.colorScheme.primary
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    // Material 图标：与播放条统一，避免文字符号在 Android 字体渲染异常
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 13,
                      color: active ? theme.colorScheme.onPrimary : theme.hintColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 20,
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: active ? theme.colorScheme.primary : theme.hintColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              ?trailing,
              Text(
                durationSeconds > 0 ? formatTime(durationSeconds) : '--:--',
                style: TextStyle(
                  fontSize: 10,
                  color: active ? theme.colorScheme.primary : theme.hintColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
