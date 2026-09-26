import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import '../screens/online_screen.dart';
import 'detail_kit.dart';

// ------------------------------------------------------------ 卡面尺寸预算
//
// 全部集中在这里，是因为「量」与「画」必须同源：网格拿这些函数算
// `mainAxisExtent`，卡片拿同一批常量排版。1.96.0 之前它们是写死的
// 62 / 24，字号一旦可调就会从「宽度溢出」变成「高度裁切」——
// 而高度裁切比宽度溢出更难发现（文字被切掉半行，看起来像字体坏了）。

/// 卡片内边距（四边，`OnlineWorkCard` 的 `Container.padding`）
const double kOnlineCardPadding = 4;

/// 封面↔标题、标题↔副标题之间的间距
const double kOnlineCardTitleGap = 6;
const double kOnlineCardSubtitleGap = 2;

/// 标题 / 副标题的基准字号与行高
const double kOnlineCardTitleFontSize = 12;
const double kOnlineCardSubtitleFontSize = 11;

/// 行高系数。**必须显式写死**：不写就由字体 metrics 决定（约 1.15–1.20），
/// 本函数只能拿一个系数去乘 —— 两者一错位，放大字号时就会裁掉半行字。
const double kOnlineCardLineHeight = 1.3;

/// 标签胶囊与副标题之间的期望间距。
/// 实际渲染时标签行是 `Align(bottomLeft)` 贴底的，所以这段间距会落在胶囊**上方**。
const double kOnlineCardTagGap = 5;

/// 卡面文字区（含卡片内边距）的高度预算。标题按**两行**算（最坏情况）。
///
/// [textScale] 是在线卡片文字的相对倍率（`onlineCardTextScale`），
/// [scaler] 是根层的全局字号缩放 —— 两者都要进预算，缺一个就会裁切：
/// 前者漏掉是「在线外观」失灵，后者漏掉正是 1.95.0 `_chipWidth` 踩过的坑。
double onlineCardTextBlockHeight(TextScaler scaler, double textScale) =>
    kOnlineCardPadding * 2 +
    kOnlineCardTitleGap +
    scaler.scale(kOnlineCardTitleFontSize * textScale) *
        kOnlineCardLineHeight *
        2 +
    kOnlineCardSubtitleGap +
    scaler.scale(kOnlineCardSubtitleFontSize * textScale) *
        kOnlineCardLineHeight;

/// 卡面标签行的整块高度：胶囊高（纵向内边距 + 一行文字）+ 与副标题的间距。
///
/// [tagFontSize] 是标签胶囊的**绝对**字号（`HikoTagFontScope`），不是卡片倍率 ——
/// 标签胶囊走的是那一套，两者是不同的旋钮。
///
/// **必须显式预留**：封面是 `Expanded`，标签行会去抢封面的高度 ——
/// `mainAxisExtent` 不加这一块，正方形封面就被压扁（1.94.0 之前的 `+62`
/// 是按「没有标签行」算的）。
///
/// **作品没有标签时这块空高也要留**：`SliverGrid` 的高度是整屏统一的，
/// 让没标签的卡片把空高还给封面，会导致同一屏里「有标签的封面小、没标签的封面大」
/// —— 那比多一行留白难看得多。卡片那边用 `SizedBox(height: …)` 占位。
double onlineCardTagRowHeight(TextScaler scaler, double tagFontSize) =>
    HikoTagChip.verticalPadding * 2 +
    scaler.scale(tagFontSize) * HikoTagChip.lineHeight +
    kOnlineCardTagGap;


/// 在线作品网格（在线浏览页与在线收藏页共用，1.93.0 抽出）。
///
/// 抽出来的理由和 `detail_kit.dart` 一样：两处用同一套列宽公式与卡片尺寸，
/// 复制一份必然漂移 —— 而「浏览页和收藏页的卡片不一样大」是最扎眼的那种漂移。
///
/// 1.96.0 起自己读两个在线外观设置（`onlineCardTextScale` / `onlineGridColumns`）：
/// 它们同时决定「卡片怎么画」和「卡片占多高」，放在调用方传参反而会多出
/// 「调用方记得传」这个失误面 —— 而这里漏传是静默的，只会表现为卡片高度对不上。
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

  /// 卡面是否显示标签行（1.94.0；设置项 `showOnlineTags` 控制，默认开）
  final bool showTags;

  /// 点卡面标签 → 按该标签筛选。为 null 时标签只展示不可点
  final ValueChanged<OnlineTag>? onTagTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = isMobile ? 16.0 : 48.0;
    const spacing = 14.0;
    // `select` 而非整个 settings：否则改任何一个无关设置都会重建整张网格
    final cardScale =
        ref.watch(settingsProvider.select((s) => s.onlineCardTextScale));
    final configured =
        ref.watch(settingsProvider.select((s) => s.onlineGridColumns)).round();
    // 全局字号缩放与标签字号都要进高度预算（见文件头的「量画同源」说明）
    final scaler = MediaQuery.textScalerOf(context);
    final tagFontSize = HikoTagFontScope.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - pad * 2;
        // 0 = 自动：桌面按可用宽度塞下「至少 200px 一张」，移动端维持 2 列。
        // 固定档位（3–8）两端共用 —— 裁决 Q4=甲：一个值管两端，
        // 代价是手机上也能选出很窄的列，但那是用户自己选的。
        final columns = configured > 0
            ? configured
            : (isMobile
                ? 2
                : ((available + spacing) / (200 + spacing)).floor().clamp(3, 8));
        final cardWidth = (available - spacing * (columns - 1)) / columns;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            // 封面正方形 + 两行标题 + 一行副标题（+ 标签行），
            // 高度按当前字号算出来，避免不同标题把网格撑歪
            mainAxisExtent: cardWidth +
                onlineCardTextBlockHeight(scaler, cardScale) +
                (showTags ? onlineCardTagRowHeight(scaler, tagFontSize) : 0),
          ),
          itemCount: works.length,
          itemBuilder: (context, index) {
            final work = works[index];
            return OnlineWorkCard(
              work: work,
              selected: selectedId == work.id,
              showTags: showTags,
              textScale: cardScale,
              onTagTap: onTagTap,
              onTap: () => onTap(work),
              onContextMenu: onContextMenu == null
                  ? null
                  : (position) => onContextMenu!(work, position),
            );
          },
        );
      },
    );
  }
}

/// 在线分页条（浏览页走服务端翻页；收藏页在已拉到的列表上做本地切片）。
///
/// 形态与 1.92.0 的浏览页完全一致（裁决 Q6=A）：每页条数 + 首页/末页 +
/// 上一页/下一页 + 当前页 ±2 的页码 + 跳页输入。**越界由调用方夹**，
/// 这里只负责把点击翻译成页码意图。
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
                  // 移动端页码半径缩到 1（当前 ±1）：窄屏上 ±2 的序列
                  // 会把「共 N 页」和跳页挤到滚动区外面去
                  for (final item in buildPageItems(page, total,
                      radius: isMobile ? 1 : 2))
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
