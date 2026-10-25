import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/categories_provider.dart';
import '../../data/settings_store.dart';
import '../../models/category.dart';
import '../m3e/m3e.dart';
import 'category_dialog.dart';
import 'confirm_dialog.dart';
import 'context_menu.dart';

/// 分类筛选条（1.99.27 从侧栏迁入首页）。
///
/// 为什么迁出来：M3E 的 nav rail 语义是「目的地列表」（3~7 个稳定入口），
/// 不是可增删的文件树；分类本质是**同一目的地的视图切换**，
/// 对应的是 chip，不是导航项（见 plan-hiko-m3e-redesign.md §8.2 裁决 P3）。
///
/// 交互与旧侧栏完全一致：点击切换、长按/右键编辑删除、末尾「新建分类」。
class HikoCategoryChips extends ConsumerWidget {
  const HikoCategoryChips({
    super.key,
    required this.activeView,
    required this.onSelected,
  });

  final String activeView;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          M3EChip(
            label: '全部',
            selected: activeView == AppSettings.navViewHome,
            onTap: () => onSelected(AppSettings.navViewHome),
          ),
          for (final category in categories) ...<Widget>[
            const SizedBox(width: 8),
            M3EChip(
              label: category.name,
              selected: activeView == category.name,
              leading: _CategoryDot(colorValue: category.colorValue),
              showCheckmark: false,
              onTap: () => onSelected(category.name),
              onLongPress: () =>
                  _openMenu(context, ref, category, null),
              onSecondaryTapDown: (position) =>
                  _openMenu(context, ref, category, position),
            ),
          ],
          const SizedBox(width: 8),
          M3EChip(
            label: '新建分类',
            leading: const Icon(Icons.add, size: 16),
            showCheckmark: false,
            onTap: () async {
              final created = await showCategoryEditDialog(context);
              if (created == null) return;
              await ref.read(categoriesProvider.notifier).addCategory(created);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    WidgetRef ref,
    CategoryItem category,
    Offset? position,
  ) async {
    final action = await showHikoContextMenu<String>(
      context: context,
      // 触摸长按没有坐标：用屏幕右下角附近作为锚点，菜单会自行夹取进屏
      position: position ??
          Offset(
            MediaQuery.sizeOf(context).width - 220,
            MediaQuery.sizeOf(context).height - 160,
          ),
      items: const <HikoContextMenuItem<String>>[
        HikoContextMenuItem(
          value: 'edit',
          label: '编辑分类',
          icon: Icons.edit_outlined,
        ),
        HikoContextMenuItem(
          value: 'delete',
          label: '删除分类',
          icon: Icons.delete_outline,
          isDestructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;

    if (action == 'edit') {
      final updated =
          await showCategoryEditDialog(context, initial: category);
      if (updated == null) return;
      await ref
          .read(categoriesProvider.notifier)
          .updateCategory(category.name, updated);
      if (activeView == category.name) onSelected(updated.name);
      return;
    }

    final confirmed = await showConfirmDialog(
      context,
      title: '删除分类「${category.name}」',
      message: '将删除此分类，该分类下的专辑将被重置为「未分类」（不会删除任何音频文件）。确定删除吗？',
      okLabel: '删除分类',
    );
    if (!confirmed) return;
    await ref.read(categoriesProvider.notifier).removeCategory(category.name);
    if (activeView == category.name) onSelected(AppSettings.navViewHome);
  }
}

class _CategoryDot extends StatelessWidget {
  const _CategoryDot({required this.colorValue});

  final int colorValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Color(colorValue),
        shape: BoxShape.circle,
      ),
    );
  }
}
