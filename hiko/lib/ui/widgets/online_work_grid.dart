import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../screens/online_screen.dart';

/// 在线作品网格（在线浏览页与在线收藏页共用，1.93.0 抽出）。
///
/// 抽出来的理由和 `detail_kit.dart` 一样：两处用同一套列宽公式与卡片尺寸，
/// 复制一份必然漂移 —— 而「浏览页和收藏页的卡片不一样大」是最扎眼的那种漂移。
class OnlineWorkGrid extends StatelessWidget {
  const OnlineWorkGrid({
    super.key,
    required this.works,
    required this.isMobile,
    required this.onTap,
    this.selectedId,
    this.onContextMenu,
  });

  final List<OnlineWork> works;
  final bool isMobile;
  final ValueChanged<OnlineWork> onTap;

  /// 桌面端右侧详情面板正在展示的作品（高亮边框）
  final int? selectedId;

  /// 右键 / 长按菜单（在线收藏页用来提供「移出本歌单 / 加入其它歌单」）
  final void Function(OnlineWork work, Offset globalPosition)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final pad = isMobile ? 16.0 : 48.0;
    const spacing = 14.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - pad * 2;
        final columns = isMobile
            ? 2
            : ((available + spacing) / (200 + spacing)).floor().clamp(3, 8);
        final cardWidth = (available - spacing * (columns - 1)) / columns;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            // 封面正方形 + 两行标题 + 一行副标题，用固定高度避免不同标题把网格撑歪
            mainAxisExtent: cardWidth + 62,
          ),
          itemCount: works.length,
          itemBuilder: (context, index) {
            final work = works[index];
            return OnlineWorkCard(
              work: work,
              selected: selectedId == work.id,
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
          _PageSizeButton(pageSize: pageSize, onSelected: onPageSize),
          const SizedBox(width: 10),
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
                  for (final item in buildPageItems(page, total))
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
