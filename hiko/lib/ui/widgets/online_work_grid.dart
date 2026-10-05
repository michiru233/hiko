import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import '../screens/online_screen.dart';

// ------------------------------------------------------------ 卡面尺寸常量
//
// 1.99.21 起在线网格是**瀑布流**（`flutter_staggered_grid_view`），卡片高度由内容
// 决定，所以这里不再有 `onlineCardTextBlockHeight` / `onlineCardTagRowHeight`
// 那一套「高度预算」—— 它们存在的唯一理由就是固定高度的 `SliverGrid`，
// 而固定高度又是「标签只能单行 + `+N` 截断」的根源。
// 剩下的常量只管卡片内部的间距与字号，只在卡片与测试里被取用。

/// 卡片内边距（四边，`OnlineWorkCard` 的 `Container.padding`）
const double kOnlineCardPadding = 4;

/// 封面↔标题之间的间距
const double kOnlineCardTitleGap = 6;

/// 标题基准字号与行高。与本地卡面（`album_card.dart` 的 13 / 1.3）保持一致 ——
/// 两边现在都是同一套瀑布流，两种卡片看起来该是一对兄弟。
///
/// 行高**必须显式写死**：不写就由字体 metrics 决定（约 1.15–1.20），
/// 多行标题的行位置会随字体漂移。
const double kOnlineCardTitleFontSize = 13;
const double kOnlineCardLineHeight = 1.3;

/// 同一组胶囊的组内纵横间距
const double kOnlineCardPillGap = 5;

/// 相邻两组胶囊之间的间距。必须**明显大于** [kOnlineCardPillGap]，
/// 否则「分组」在视觉上不存在（看起来就是一堆挤在一起的胶囊）。
const double kOnlineCardPillGroupGap = 6;

/// 网格的列间距 / 行间距（在线卡片比本地卡片矮，用紧凑一点的 14）
const double kOnlineGridSpacing = 14;

/// 在线作品网格（在线浏览页与在线收藏页共用，1.93.0 抽出）。
///
/// 抽出来的理由和 `detail_kit.dart` 一样：两处用同一套列宽公式与卡片装配，
/// 复制一份必然漂移 —— 而「浏览页和收藏页的卡片不一样大」是最扎眼的那种漂移。
///
/// 1.96.0 起自己读 `onlineGridColumns`（列数）；1.99.21 改成瀑布流后不再读
/// `onlineCardTextScale` / 标签字号 —— 那两个旋钮只有「算卡高」时才需要，
/// 而卡高现在由内容说了算，卡片自己读设置即可。
class OnlineWorkGrid extends ConsumerWidget {
  const OnlineWorkGrid({
    super.key,
    required this.works,
    required this.isMobile,
    required this.onTap,
    this.selectedId,
    this.onContextMenu,
    this.showTags = false,
    this.onTagTap,
  });

  final List<OnlineWork> works;
  final bool isMobile;
  final ValueChanged<OnlineWork> onTap;

  /// 桌面端右侧详情面板正在展示的作品（高亮边框）
  final int? selectedId;

  /// 右键 / 长按菜单（在线收藏页用来提供「移出本歌单 / 加入其它歌单」）
  final void Function(OnlineWork work, Offset globalPosition)? onContextMenu;

  /// 卡面是否显示标签胶囊（1.94.0；设置项 `showOnlineTags` 控制，默认开）
  final bool showTags;

  /// 点卡面标签 → 按该标签筛选。为 null 时标签只展示不可点
  final ValueChanged<OnlineTag>? onTagTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = isMobile ? 16.0 : 48.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - pad * 2;
        final columns = _resolveColumns(
          isMobile: isMobile,
          configured: ref
              .watch(settingsProvider.select((s) => s.onlineGridColumns))
              .round(),
          available: available,
        );
        return MasonryGridView.count(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
          crossAxisCount: columns,
          mainAxisSpacing: kOnlineGridSpacing,
          crossAxisSpacing: kOnlineGridSpacing,
          itemCount: works.length,
          itemBuilder: (context, index) => _buildWorkCard(
            works[index],
            selected: selectedId == works[index].id,
            showTags: showTags,
            onTagTap: onTagTap,
            onTap: () => onTap(works[index]),
            onContextMenu: onContextMenu == null
                ? null
                : (position) => onContextMenu!(works[index], position),
          ),
        );
      },
    );
  }
}

/// 在线作品网格的 **sliver 形态**（1.99.7）：给在线浏览页移动端的
/// `CustomScrollView` 用 —— 头部要做成 floating 的滚动收起，
/// 网格必须以 sliver 身份跟它住在同一个滚动视图里。
/// 列宽公式与卡片装配与 [OnlineWorkGrid] 共用同一份实现，不会漂移。
class OnlineWorkGridSliver extends ConsumerWidget {
  const OnlineWorkGridSliver({
    super.key,
    required this.works,
    required this.isMobile,
    this.selectedId,
    required this.onTap,
    this.onContextMenu,
    this.showTags = false,
    this.onTagTap,
  });

  final List<OnlineWork> works;
  final bool isMobile;
  final int? selectedId;
  final ValueChanged<OnlineWork> onTap;

  /// 右键 / 长按菜单（在线收藏页用来提供「移出本歌单 / 加入其它歌单」）
  final void Function(OnlineWork work, Offset globalPosition)? onContextMenu;

  final bool showTags;
  final ValueChanged<OnlineTag>? onTagTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = isMobile ? 16.0 : 48.0;
    // sliver 里拿不到 box 约束，移动端视口就是整屏宽（与本组件唯一的使用场景一致）
    final available = MediaQuery.sizeOf(context).width - pad * 2;
    final columns = _resolveColumns(
      isMobile: isMobile,
      configured: ref
          .watch(settingsProvider.select((s) => s.onlineGridColumns))
          .round(),
      available: available,
    );
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: columns,
        mainAxisSpacing: kOnlineGridSpacing,
        crossAxisSpacing: kOnlineGridSpacing,
        childCount: works.length,
        itemBuilder: (context, index) => _buildWorkCard(
          works[index],
          selected: selectedId == works[index].id,
          showTags: showTags,
          onTagTap: onTagTap,
          onTap: () => onTap(works[index]),
          onContextMenu: onContextMenu == null
              ? null
              : (position) => onContextMenu!(works[index], position),
        ),
      ),
    );
  }
}

/// 单张卡片的装配（两种网格共用，1.99.7）—— 顶层私有函数而不是实例方法：
/// sliver 形态需要的是同一份装配，挂在 `OnlineWorkGrid` 上就得再抄一遍。
Widget _buildWorkCard(
  OnlineWork work, {
  required bool selected,
  required bool showTags,
  required ValueChanged<OnlineTag>? onTagTap,
  required VoidCallback onTap,
  required void Function(Offset position)? onContextMenu,
}) =>
    OnlineWorkCard(
      work: work,
      selected: selected,
      showTags: showTags,
      onTagTap: onTagTap,
      onTap: onTap,
      onContextMenu: onContextMenu,
    );

/// 列数解析：0 = 自动（桌面按可用宽度塞「至少 200px 一张」，移动端 2 列），
/// 固定档位（3–8）两端共用（裁决 Q4=甲）。
///
/// 瀑布流用的是 `SliverSimpleGridDelegateWithFixedCrossAxisCount`，
/// 所以自动档必须在这里就把列数算成整数 —— 交给
/// `WithMaxCrossAxisExtent` 去算会得到另一个列数（它按 `ceil` 取，
/// 900 宽下是 4 列而不是 3），「自动档」的既有观感会当场变。
int _resolveColumns({
  required bool isMobile,
  required int configured,
  required double available,
}) {
  const spacing = kOnlineGridSpacing;
  return configured > 0
      ? configured
      : (isMobile
          ? 2
          : ((available + spacing) / (200 + spacing)).floor().clamp(3, 8));
}

/// 在线分页条（浏览页走服务端翻页；收藏页在已拉到的列表上做本地切片）。
///
/// 桌面：每页条数 + 首页/末页 + 上一页/下一页 + 当前页 ±2 的页码 + 跳页输入
/// （1.92.0 浏览页形态，裁决 Q6=A）。移动端（1.99.0）：上一页/下一页钉在
/// 两端不参与横滑，页码只留当前页 ±1 —— 原先整套塞一行，窄屏上「下一页」
/// 被挤出可视区，翻页得先把分页条往右滑；首末页由跳页输入覆盖。
/// **越界由调用方夹**，这里只负责把点击翻译成页码意图。
class OnlinePager extends StatelessWidget {
  const OnlinePager({
    super.key,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.isMobile,
    required this.onPage,
    required this.onPageSize,
  });

  final int page;
  final int pageSize;
  final int totalCount;
  final bool isMobile;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  int get totalPages =>
      pageSize <= 0 ? 0 : (totalCount + pageSize - 1) ~/ pageSize;

  bool get hasPrev => page > 1;
  bool get hasNext => page < totalPages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pad = isMobile ? 16.0 : 48.0;
    final total = totalPages;

    final numbers = <Widget>[
      for (final item in isMobile
          ? mobilePageItems(page, total)
          : buildPageItems(page, total, radius: 2))
        if (item == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '…',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          )
        else
          _PageNumberButton(
            page: item,
            current: item == page,
            onPressed: () => onPage(item),
          ),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(pad, 6, pad, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // 每页条数入口挪进 设置→在线外观（1.97.0 裁决 Q1）：
          // 移动端分页条一行要塞下页码与跳页，这颗 chip 是最先挤爆的那个；
          // 桌面保持原样（用户裁决：不涉及 mac 就不动 mac 端）。
          if (!isMobile) ...[
            _PageSizeButton(pageSize: pageSize, onSelected: onPageSize),
            const SizedBox(width: 10),
          ],
          if (isMobile) ...[
            _PagerIcon(
              icon: Icons.chevron_left_rounded,
              tooltip: '上一页',
              onPressed: hasPrev ? () => onPage(page - 1) : null,
            ),
            // ±1 三颗页码最宽 ~114px，Expanded 内放得下；极端字号缩放时
            // FittedBox 等比缩而不是溢出/滚动
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: numbers,
                ),
              ),
            ),
            _PagerIcon(
              icon: Icons.chevron_right_rounded,
              tooltip: '下一页',
              onPressed: hasNext ? () => onPage(page + 1) : null,
            ),
          ] else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PagerIcon(
                      icon: Icons.first_page_rounded,
                      tooltip: '首页',
                      onPressed: hasPrev ? () => onPage(1) : null,
                    ),
                    _PagerIcon(
                      icon: Icons.chevron_left_rounded,
                      tooltip: '上一页',
                      onPressed: hasPrev ? () => onPage(page - 1) : null,
                    ),
                    ...numbers,
                    _PagerIcon(
                      icon: Icons.chevron_right_rounded,
                      tooltip: '下一页',
                      onPressed: hasNext ? () => onPage(page + 1) : null,
                    ),
                    _PagerIcon(
                      icon: Icons.last_page_rounded,
                      tooltip: '末页',
                      onPressed: hasNext ? () => onPage(total) : null,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 10),
          _PageJumpField(totalPages: total, onSubmit: onPage),
        ],
      ),
    );
  }
}

/// 移动端页码序列：当前页 ±1 夹到 1..N 去重（如第 1 页 → `[1, 2]`）。
/// 不放首末页与省略号 —— 它们是分页条在窄屏上溢出的元凶，远页跳转交给跳页输入。
List<int> mobilePageItems(int page, int total) => [
      for (final p in {page - 1, page, page + 1})
        if (p >= 1 && p <= total) p,
    ]..sort();

/// 每页条数选择（20 / 60 / 100；实测服务端支持到 500）
class _PageSizeButton extends StatelessWidget {
  const _PageSizeButton({required this.pageSize, required this.onSelected});

  final int pageSize;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '每页条数',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final size in OnlineBrowseNotifier.pageSizeOptions)
          PopupMenuItem(
            value: size,
            child: Text('每页 $size 条', style: const TextStyle(fontSize: 12)),
          ),
      ],
      child: Chip(
        label: Text('每页 $pageSize 条', style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _PagerIcon extends StatelessWidget {
  const _PagerIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
      padding: EdgeInsets.zero,
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.page,
    required this.current,
    required this.onPressed,
  });

  final int page;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 28,
        child: TextButton(
          onPressed: current ? null : onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(32, 28),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            backgroundColor: current
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            '$page',
            style: TextStyle(
              fontSize: 11,
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              color: current ? theme.colorScheme.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// 跳页输入：回车生效，越界由调用方夹到有效范围
class _PageJumpField extends StatefulWidget {
  const _PageJumpField({required this.totalPages, required this.onSubmit});

  final int totalPages;
  final ValueChanged<int> onSubmit;

  @override
  State<_PageJumpField> createState() => _PageJumpFieldState();
}

class _PageJumpFieldState extends State<_PageJumpField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '共 ${widget.totalPages} 页',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          height: 28,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              isDense: true,
              hintText: '跳页',
              hintStyle: TextStyle(fontSize: 11, color: theme.hintColor),
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (value) {
              final page = int.tryParse(value.trim());
              if (page == null) return;
              widget.onSubmit(page);
              _controller.clear();
            },
          ),
        ),
      ],
    );
  }
}
