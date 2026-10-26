/// 详情页共用件（本地专辑详情抽屉 ↔ 在线作品详情面板）。
///
/// 1.91.0 抽出：两处详情页要求视觉完全一致，复制一份必然漂移，
/// 所以把颜色、间距、圆角、字号这些常量收在这里，两边都从这里取。
/// 数值全部照搬 1.83–1.90 的 `detail_drawer.dart`，未做任何视觉调整。
library;

import 'package:flutter/material.dart';

import '../../utils/time.dart';
import '../m3e/m3e.dart';

// ------------------------------------------------------------------ 调色板
//
// 1.99.48：社团紫 / 声优蓝 / 收藏红 / 评分金 / 标签青全部迁进
// `m3e/tokens/semantic_color_tokens.dart`。它们承载信息（靠色相区分声优与社团），
// 不属于 Material 的层级色，也不该被种子色算掉 —— 但也不该散落在业务文件里。
// 业务侧统一从 `M3ESemantic` 取。

/// 详情面板宽度（1.99.44 裁决：两端统一 420）。
///
/// 之前本地 480 / 在线 390，同语义两个宽度；420 是折中：
/// 在线信息行与标签不再挤，480 在 1280 窗口下会压掉主网格近一半。
const double kHikoDetailPanelWidth = 420;

// ------------------------------------------------------------------ 样式件

/// 可点胶囊的悬停 / 按下反馈（1.95.0 裁决 Q2=甲、Q3=丙）。
///
/// **为什么不能靠 `InkWell` 自带的 hover 高亮**：ink 画在最近的 `Material` 上，
/// 而在本项目里那层在胶囊**不透明底色之下**（详情面板 / 卡片的底色都是不透明的），
/// 于是墨迹被完全盖住 —— 用户看到的就是「指针碰上去毫无变化，不知道这东西能点」
/// （1.95.0 用户实测反馈）。所以这里自己管状态，由 [builder] 把反馈画在胶囊自己身上。
///
/// 反馈画在 `foregroundDecoration` 上，**刻意不影响布局尺寸**：
/// 在线卡片改成瀑布流后卡高由内容决定，任何会撑大胶囊的装饰都会让
/// 「同一屏里卡片高矮不一」变成两回事（真高矮不一 vs 装饰撑的）。
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

// --------------------------------------------------------- 文字缩放（1.96.0）
//
// 三组可调外观：标签胶囊的**绝对字号**（走 [HikoTagFontScope]，全局生效），
// 在线卡片文字与在线详情面板文字两组**相对倍率**（前者走 `textScale` 参数、
// 后者走 [HikoDetailTextScale] 作用域）。三者都叠在根层
// `MediaQuery.textScaler`（全局 `fontScale`）之上 ——
// 最终字号 = 元素基准字号 × 该组倍率 × 全局 fontScale。

/// 详情页文字的相对倍率作用域（1.96.0 裁决 Q3=甲）。
///
/// **只由在线详情面板挂**（`online_detail_panel.dart` 的 `OnlineDetailBody`）——
/// 本地详情抽屉不套它，于是本地界面完全不受「在线外观」影响。作用域挂在面板边界上，
/// 覆盖范围恰好等于「这个面板里的每一个后代」，不多不少。
///
/// 为什么这一组用作用域、而卡片那一组用参数：这一组要覆盖面板内的**全部**文字
/// （眼眉 / 标题 / 副标题 / 声优社团 / 信息行 / 标签 / 双 Tab / 曲目行 / 目录行 /
/// 空态 / 错误页 / 操作按钮），逐个透传意味着每加一处文字都要记得传一次 ——
/// 漏传是**静默**的，只会表现为「这块字没跟着变大」，极难在走查里发现。
/// 卡片那边只有标题与副标题两处、且都要参与高度预算，参数反而更直白。
class HikoDetailTextScale extends InheritedWidget {
  const HikoDetailTextScale({
    super.key,
    required this.scale,
    required super.child,
  });

  /// 未套作用域（本地详情抽屉）时的倍率
  static const double defaultScale = 1.0;

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HikoDetailTextScale>()?.scale ??
      defaultScale;

  @override
  bool updateShouldNotify(HikoDetailTextScale oldWidget) =>
      scale != oldWidget.scale;
}

/// 详情页顶部「眼眉」胶囊（本地：分类 · ALBUM 01；在线：来源 · RJ 号）。
/// [onTap] 为空时去掉下拉箭头，表示纯标识不可交互。
/// 详情页眉题胶囊（M3E 化，1.99.34）：outlined chip + 分类切换箭头。
///
/// 1.99.34 起**不再展示 ALBUM 内部 id**（用户裁决 D4）：内部 id 是数据层主键，
/// 对用户无意义；RJ 码在元数据行展示。调用方只传分类名。
class HikoEyebrowPill extends StatelessWidget {
  const HikoEyebrowPill({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = M3ETheme.of(context).colors;
    final primary = theme.colorScheme.primary;
    final textScale = HikoDetailTextScale.of(context);
    return M3EPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(M3EShape.full),
      pressScale: 0.97,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(M3EShape.full),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11 * textScale,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 社团（紫）/ 声优（蓝）分色胶囊。[onTap] 为空即纯展示。
///
/// 1.99.34 M3E 化：整胶囊染色底改为「左侧 4dp 色点 + 文字」（深色下不刺眼），
/// 选中态 `secondaryContainer` 底。筛选语义（点选回列表按人筛选）不变。
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
    final colors = M3ETheme.of(context).colors;
    final textScale = HikoDetailTextScale.of(context);
    return M3EPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(M3EShape.full),
      pressScale: 0.97,
      child: AnimatedContainer(
        duration: kPillHoverDuration,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(M3EShape.full),
          border: Border.all(
            color: selected ? colors.secondaryContainer : colors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 12.5 * textScale,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.onSecondaryContainer : colors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标签胶囊的字号作用域（1.96.0 裁决 Q1=甲、Q2=甲）。
///
/// **为什么用 InheritedWidget 而不是给每个 `HikoTagChip` 加参数**：
/// 标签胶囊在五个地方出现（本地卡面、本地详情抽屉、在线卡面、在线详情面板、
/// 黑名单管理对话框），而裁决是「一个组件一套字号、全局生效」——
/// 逐个透传意味着每个调用点都要记得传，漏一处就是「这一处的标签还是 9 号」，
/// 而这种漏法在视觉上极难被发现。挂在根层一次性生效才是这个语义的正确表达。
///
/// 值由 `main.dart` 从 `settings.tagFontSize` 取（默认 11）。
class HikoTagFontScope extends InheritedWidget {
  const HikoTagFontScope({
    super.key,
    required this.fontSize,
    required super.child,
  });

  /// 未套作用域时的兜底字号 —— 与设置默认值一致（1.94.0 之前的硬编码是 9，
  /// 1.96.0 裁决 Q2 起提到 11）
  static const double defaultFontSize = 11;

  final double fontSize;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HikoTagFontScope>()?.fontSize ??
      defaultFontSize;

  @override
  bool updateShouldNotify(HikoTagFontScope oldWidget) =>
      fontSize != oldWidget.fontSize;
}

/// DLsite 标签胶囊（青色小方角）
///
/// 1.94.0 起也用在**在线卡片的标签组**上（裁决 Q4=按推荐：与本地卡面视觉一致）。
/// 1.99.21 在线网格改成瀑布流后，卡面标签不再截断 —— 全部展示、放不下就换行，
/// 所以「单行 + 按像素宽度挑前缀 + `+N`」那一套连同 `_chipWidth` 一起删掉了。
/// [textStyleFor] / [horizontalPadding] 保留为公开常量：多处排版仍要从同一个
/// 样式取字号与内边距，各写一份必然会漂移。
///
/// 1.96.0：字号改由 [HikoTagFontScope] 提供（默认 11），`textStyle` 常量随之变成
/// [textStyleFor] 函数 —— 本地卡面与在线卡面因此共用同一把字号旋钮。
class HikoTagChip extends StatelessWidget {
  const HikoTagChip({
    super.key,
    required this.tag,
    this.onTap,
    this.muted = false,
    this.blocked = false,
    this.onContextMenu,
  });

  /// 标签文字样式（给定字号）。卡面标签行做宽度预估时用的就是它
  static TextStyle textStyleFor(double fontSize) => TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: lineHeight,
      );

  /// 行高。**必须显式写死** —— 不写就由字体 metrics 决定（约 1.15–1.20），
  /// 而标签行的行距是按一个系数排的，两者一错位，多行标签之间就会出现
  /// 忽宽忽窄的缝（调大字号尤其明显）。
  static const double lineHeight = 1.2;

  /// 纵向内边距（单侧）
  static const double verticalPadding = 4;

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
    final fontSize = HikoTagFontScope.of(context);
    final dim = muted || blocked;
    final fg = dim
        ? M3ETheme.of(context).colors.onSurfaceVariant
        : M3ESemantic.tagForeground(isDark);
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
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          // 悬停/按下时「底色加深」：同一支底色抬高 alpha，不换色相，
          // 免得一排标签在指针扫过时闪成另一种颜色
          color: dim
              ? (isDark
                  ? Colors.white.withValues(alpha: active ? 0.13 : 0.06)
                  : Colors.black.withValues(alpha: active ? 0.09 : 0.04))
              : M3ESemantic.tagBackground.withValues(
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
          style: textStyleFor(fontSize).copyWith(
            color: fg,
            decoration: blocked ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

/// 曲名展示清洗（1.99.12）：剥掉与左侧序号列重复的 `Track01_` 类半角前缀，
/// 长中文标题省出的宽度通常正好让两行放下。只改显示不改数据；
/// 剥完为空（名字本身就叫 Track01）时保留原名。
final RegExp _trackPrefixRegex =
    RegExp(r'^\s*track\s*\d{1,4}[\s_\-.]+', caseSensitive: false);

String hikoTrackDisplayName(String name) {
  final stripped = name.replaceFirst(_trackPrefixRegex, '');
  return stripped.isEmpty ? name : stripped;
}

/// 曲目行内标题：默认最多两行，点标题展开全文、再点收起（1.99.12）。
/// 点标题不再触发行播放（内层手势赢过行 InkWell）——播放仍走左侧圆钮。
class _ExpandableTrackTitle extends StatefulWidget {
  const _ExpandableTrackTitle({required this.name, required this.style});

  final String name;
  final TextStyle style;

  @override
  State<_ExpandableTrackTitle> createState() => _ExpandableTrackTitleState();
}

class _ExpandableTrackTitleState extends State<_ExpandableTrackTitle> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableTrackTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.name,
        maxLines: _expanded ? null : 2,
        overflow: _expanded ? null : TextOverflow.ellipsis,
        style: widget.style,
      ),
    );
  }
}

/// 详情页曲目行（M3E，1.99.34；1.99.44 起本地与在线共用）：56dp、角 16、
/// 当前曲目 `secondaryContainer`。
///
/// 按压走 [M3EPressable] 弹簧，选中态靠色阶不靠描边（plan-hiko-detail-m3e.md §4.5）。
/// 字号仍乘 [HikoDetailTextScale]（详情倍率旋钮语义不变）。
///
/// 1.99.44 把旧 [HikoTrackRow] 的三个在线专用能力并进来，随后删掉旧类：
/// [indent]（按目录层级缩进）、[trailing]（时长左边的字幕角标）、
/// [titleFontSize]（曲名基准字号旋钮）。
class HikoTrackRowM3E extends StatelessWidget {
  const HikoTrackRowM3E({
    super.key,
    required this.index,
    required this.name,
    required this.durationSeconds,
    required this.active,
    required this.playing,
    required this.onTap,
    this.indent = 0.0,
    this.trailing,
    this.titleFontSize,
  });

  final int index;
  final String name;
  final double durationSeconds;
  final bool active;
  final bool playing;
  final VoidCallback onTap;

  /// 按目录层级缩进（在线详情用）。本地传 0。
  final double indent;

  /// 时长左侧的额外角标（在线用来放「有字幕」图标）。
  final Widget? trailing;

  /// 曲名**基准**字号；不传用 `bodyMedium`。仍乘 [HikoDetailTextScale]。
  final double? titleFontSize;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final type = M3ETheme.of(context).type;
    final textScale = HikoDetailTextScale.of(context);
    final onActive = colors.onSecondaryContainer;
    final titleSize = (titleFontSize ?? type.bodyMedium.fontSize ?? 14) *
        textScale;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: M3EPressable(
        onTap: onTap,
        pressScale: 0.97,
        borderRadius: BorderRadius.circular(M3EShape.lg),
        stateLayerColor: active ? onActive : colors.onSurface,
        child: AnimatedContainer(
          duration: kPillHoverDuration,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(M3EShape.lg),
          ),
          child: Row(
            children: [
              Icon(
                playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 22,
                color: active ? onActive : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                index.toString().padLeft(2, '0'),
                style: type.labelMedium.copyWith(
                  color: active ? onActive : colors.onSurfaceVariant,
                  fontSize: type.labelMedium.fontSize != null
                      ? type.labelMedium.fontSize! * textScale
                      : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ExpandableTrackTitle(
                  name: hikoTrackDisplayName(name),
                  style: type.bodyMedium.copyWith(
                    color: active ? onActive : colors.onSurface,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    fontSize: titleSize,
                  ),
                ),
              ),
              ?trailing,
              Text(
                durationSeconds > 0 ? formatTime(durationSeconds) : '--:--',
                style: type.labelMedium.copyWith(
                  color: active ? onActive : colors.onSurfaceVariant,
                  fontSize: type.labelMedium.fontSize != null
                      ? type.labelMedium.fontSize! * textScale
                      : null,
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

/// 详情页信息行（M3E，1.99.34）：56dp，label 左 / value 右，放进
/// `M3ECard(surfaceContainerLow)` 的分组卡里用。[progress] 给了就在
/// value 下方画 4dp 细进度条（完成进度行专用）。
class HikoDetailInfoRowM3E extends StatelessWidget {
  const HikoDetailInfoRowM3E({
    super.key,
    required this.label,
    required this.value,
    this.progress,
  });

  final String label;
  final String value;

  /// 0~1；null = 不显示进度条
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final type = M3ETheme.of(context).type;
    final textScale = HikoDetailTextScale.of(context);
    return SizedBox(
      height: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: type.bodyMedium.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: type.bodyMedium.fontSize != null
                        ? type.bodyMedium.fontSize! * textScale
                        : null,
                  ),
                ),
              ),
              Text(
                value,
                textAlign: TextAlign.right,
                style: type.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: type.bodyMedium.fontSize != null
                      ? type.bodyMedium.fontSize! * textScale
                      : null,
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: progress!.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor:
                      colors.outlineVariant.withValues(alpha: 0.6),
                  valueColor: AlwaysStoppedAnimation(colors.primary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
