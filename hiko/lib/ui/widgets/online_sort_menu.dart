/// 在线页第二行的「排序 + 分级筛选」下拉（1.99.5 从 `online_screen.dart` 抽出）。
///
/// 抽成公开组件同 1.97.1 抽筛选标记的理由：**可测**。这里有一条不显眼但
/// 容易在重构里丢掉的行为 —— 分级复选框**不关菜单**（见 [_AgeFilterItem]）。
/// 若哪天有人图省事改回 `PopupMenuItem(enabled: false)`，功能仍「能用」，
/// 只是每勾一项都要重开菜单；没有回归锁这种退化不会被发现。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';

/// 排序 + **分级筛选**的下拉（裁决 Q6=①，1.99.5 追加分级）。
///
/// 形态对齐 asmr.one 的「排序」菜单：**一条扁平列表，方向写进条目名**
/// （「销量倒序」而不是「销量」+独立箭头），因此没有「再点一次反转」这种隐藏状态。
///
/// 1.99.5（裁决 Q4=B）：**分级（R18 / R15 / 全年龄）三个复选框放在这里** ——
/// 用户点名的位置。勾选语义见 `OnlineBrowseState.ageTerm`：
/// 勾选 = 显示该分级，全勾或全不勾 = 不筛。
///
/// 实现见 [_AgeFilterItem]：**不给 `Navigator.pop`**，所以勾完菜单不关，
/// 可以连着勾两个 —— 这正是「三个复选框」该有的手感。复选框选中态从 provider
/// 现读，勾完立刻打勾，不用重开菜单。
///
/// 限高是为了安卓：竖屏高度有限，菜单不该顶到天花板。`PopupMenu` 的菜单体本来就是
/// `SingleChildScrollView`，所以给出 `maxHeight` 即获得滚动，不必自己实现。
///
/// 1.99.5 把绝对上限从 320 提到 400：菜单从 5 项涨到 8 项（+1 分隔线），
/// 内容约 336px —— 卡在 320 的话**第三行「全年龄」会被永久切在折线下方**
/// （桌面上也一样，因为 320 是硬上限、跟屏高无关）。提到 400 后：
/// 手机上生效的仍是 45% 那条（800px 屏 → 360，刚好装下），
/// 高屏/桌面则不再无意义地截断。
class OnlineSortMenu extends StatelessWidget {
  const OnlineSortMenu({
    super.key,
    required this.current,
    required this.onSelected,
    required this.onToggleAge,
  });

  final OnlineSort current;
  final Future<void> Function(OnlineSort sort) onSelected;
  final Future<void> Function(OnlineAgeCategory category) onToggleAge;

  /// min(400, 屏高 × 0.45)：小屏按比例缩，大屏封顶。
  /// 400 这个上限的来历见类注释（1.99.5 从 320 提上来）。
  static double _menuMaxHeight(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final scaled = screen * 0.45;
    return scaled < 400 ? scaled : 400;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<Object>(
      tooltip: '排序与分级筛选',
      constraints: BoxConstraints(
        minWidth: 200,
        maxWidth: 280,
        maxHeight: _menuMaxHeight(context),
      ),
      onSelected: (value) {
        if (value is OnlineSort) unawaited(onSelected(value));
      },
      itemBuilder: (_) => [
        for (final sort in OnlineSort.values)
          PopupMenuItem<Object>(
            value: sort,
            height: 38,
            child: SizedBox(
              // 固定宽度让条目里的 Expanded 有确定边界，菜单宽度也就可预期
              width: 168,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sort.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (sort == current)
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
        const PopupMenuDivider(),
        for (final category in OnlineAgeCategory.values)
          _AgeFilterItem(category: category, onToggle: onToggleAge),
      ],
      child: Chip(
        label: Text('排序：${current.label}', style: const TextStyle(fontSize: 11)),
        avatar: const Icon(Icons.swap_vert_rounded, size: 13),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 排序/分级菜单里的**分级复选框条目**（1.99.5 裁决 Q4=B）。
///
/// 与普通 `PopupMenuItem` 的**唯一**行为差异：`handleTap` **不 pop** ——
/// 菜单保持打开，用户能连着勾两个（三个复选框该有的手感）。
/// 其余（内边距、行高、`MergeSemantics`、`menuItem` 角色）全部继承父类实现，
/// 所以这三行与上面的排序条目在视觉上严丝合缝。
///
/// 为什么不用 `PopupMenuItem(enabled: false)` 来「留住菜单」：
/// 禁用条目会（M3）把 `DefaultTextStyle` 换成 onSurface@38% 灰、并套上
/// `Semantics(enabled: false)` —— 复选框本身是**可用**控件，被念成「已禁用」
/// 是错的，文字发灰也误导。覆写 `handleTap` 才是语义正确的做法。
///
/// 点击落点：整行（含「R18」文字）都是目标 —— 由父类的 `InkWell` 接住，
/// 所以里面的 `Checkbox` 包了 `IgnorePointer` 当纯指示器（避免两个 tap
/// recognizer 争抢同一个手势、把开关切成「开了又关」）。
class _AgeFilterItem extends PopupMenuItem<Object> {
  const _AgeFilterItem({required this.category, required this.onToggle})
      // child 是父类的必填参数，但内容由 buildChild() 覆写提供，这里给个占位
      : super(value: null, height: 38, child: const SizedBox.shrink());

  final OnlineAgeCategory category;
  final Future<void> Function(OnlineAgeCategory category) onToggle;

  @override
  PopupMenuItemState<Object, PopupMenuItem<Object>> createState() =>
      _AgeFilterItemState();
}

class _AgeFilterItemState extends PopupMenuItemState<Object, _AgeFilterItem> {
  @override
  void handleTap() {
    // 刻意不 Navigator.pop：菜单不关，可以连着勾多个分级
    unawaited(widget.onToggle(widget.category));
  }

  @override
  Widget? buildChild() {
    return SizedBox(
      // 与排序条目同宽，两组文字左对齐
      width: 168,
      child: Consumer(
        builder: (context, ref, _) {
          final selected = ref.watch(
            onlineBrowseProvider.select((s) => s.isAgeSelected(widget.category)),
          );
          return Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: IgnorePointer(
                  child: Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    // 非空 = 保持「可用」外观；实际点击由本条的 InkWell 接住
                    onChanged: (_) {},
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
