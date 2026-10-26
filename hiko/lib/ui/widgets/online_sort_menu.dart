/// 在线页第二行的「排序 + 分级筛选」下拉（1.99.5 从 `online_screen.dart` 抽出）。
///
/// 抽成公开组件同 1.97.1 抽筛选标记的理由：**可测**。这里有一条不显眼但
/// 容易在重构里丢掉的行为 —— 分级开关**不关菜单**（见 [_AgeFilterToggle]）。
/// 若哪天有人图省事改回「点一下就关」，功能仍「能用」，只是每勾一项都要
/// 重开菜单；没有回归锁这种退化不会被发现。
///
/// 形态对齐 asmr.one 的「排序」菜单：**一条扁平列表，方向写进条目名**
/// （「销量倒序」而不是「销量」+独立箭头），因此没有「再点一次反转」这种隐藏状态。
///
/// 1.99.5（裁决 Q4=B）：**分级（R18 / R15 / 全年龄）三个开关放在这里** ——
/// 用户点名的位置。勾选语义见 `OnlineBrowseState.ageTerm`：
/// 勾选 = 显示该分级，全勾或全不勾 = 不筛。
///
/// 1.99.40：从 `PopupMenuButton` 换成 `M3EMenu`（B1 第二件）。行为不变：
/// 排序项选了就关、分级项不关；菜单高度仍取 `min(400, 屏高 × 0.45)`，
/// 这个 400 的来历（320 会把第三行永久切在折线下方）记在 `M3EMenu`。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../m3e/m3e.dart';

/// 排序 + **分级筛选**的下拉（裁决 Q6=①，1.99.5 追加分级，1.99.40 换 M3EMenu）。
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

  @override
  Widget build(BuildContext context) {
    return M3EMenu(
      // 排序条目最长「销量倒序」+ 勾，280 够用且不至于在 360dp 上顶满整行
      maxWidth: 280,
      builder: (context, controller, child) => M3EChip(
        label: '排序：${current.label}',
        // 再点一次收起 —— `PopupMenuButton` 原来就是这个手感
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      children: <Widget>[
        for (final sort in OnlineSort.values)
          M3EMenuAction(
            label: sort.label,
            selected: sort == current,
            onPressed: () => unawaited(onSelected(sort)),
          ),
        const M3EMenuDivider(),
        // 8 个排序与 3 个分级是两类东西，给后者一个分区标题；
        // 原来的「禁用 PopupMenuItem」做不到这件事（会被读成「已禁用」）。
        const M3EMenuHeader(label: '分级'),
        for (final category in OnlineAgeCategory.values)
          _AgeFilterToggle(category: category, onToggle: onToggleAge),
      ],
    );
  }
}

/// 分级开关行：**不关菜单**，勾完还能接着勾。
///
/// 选中态从 provider 现读，开关本体是受控 + 乐观更新（见 [M3EMenuToggle]），
/// 所以勾完立刻打勾，不用重开菜单；别处改了分级状态（例如「取消分级筛选」
/// 标记）时，`didUpdateWidget` 也会把勾同步回来。
class _AgeFilterToggle extends ConsumerWidget {
  const _AgeFilterToggle({required this.category, required this.onToggle});

  final OnlineAgeCategory category;
  final Future<void> Function(OnlineAgeCategory category) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      onlineBrowseProvider.select((s) => s.isAgeSelected(category)),
    );
    return M3EMenuToggle(
      label: category.label,
      value: selected,
      // 传的是「点完之后的新值」，但语义仍是「切换」：provider 自己取反
      onChanged: (_) => unawaited(onToggle(category)),
    );
  }
}
