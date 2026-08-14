import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/categories_provider.dart';
import '../../data/library_provider.dart';
import '../../models/category.dart';
import 'category_dialog.dart';
import 'confirm_dialog.dart';
import 'context_menu.dart';

/// 侧栏（对应旧版 aside.sidebar）：主导航 + 分类 + 偏好设置入口
class Sidebar extends ConsumerWidget {
  const Sidebar({
    super.key,
    required this.activeView,
    required this.onViewChanged,
    required this.onOpenSettings,
    this.collapsed = false,
  });

  final String activeView;
  final ValueChanged<String> onViewChanged;
  final VoidCallback onOpenSettings;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final albums = ref.watch(libraryProvider);
    final categories = ref.watch(categoriesProvider);

    final count = (String view) => switch (view) {
          '收藏夹' => albums.where((a) => a.favorite).length,
          '全部音声' => albums.length,
          _ => albums.where((a) => a.genre == view).length,
        };

    final navItems = [
      ('▦', '全部音声'),
      ('◷', '最近添加'),
      ('▶', '正在播放'),
      ('♡', '收藏夹'),
    ];

    Widget item({
      String? icon,
      int? dot,
      required String view,
      int? count,
      VoidCallback? onTap,
      void Function(Offset position)? onContextMenu,
    }) {
      final active = activeView == view;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap ?? () => onViewChanged(view),
          onSecondaryTapDown: onContextMenu == null
              ? null
              : (d) => onContextMenu(d.globalPosition),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? theme.colorScheme.surface
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (dot != null)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: Color(dot),
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  SizedBox(
                    width: 17,
                    child: Text(
                      icon ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        color: active ? theme.colorScheme.primary : theme.hintColor,
                      ),
                    ),
                  ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      view,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: active ? theme.colorScheme.primary : theme.hintColor,
                      ),
                    ),
                  ),
                  if (count != null)
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    void showCategoryMenu(CategoryItem cat, Offset position) {
      showHikoContextMenu<String>(
        context: context,
        position: position,
        items: const [
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
      ).then((action) async {
        if (action == null) return;
        if (action == 'edit') {
          final updated = await showCategoryEditDialog(context, initial: cat);
          if (updated != null) {
            await ref.read(categoriesProvider.notifier).updateCategory(cat.name, updated);
            if (activeView == cat.name) {
              onViewChanged(updated.name);
            }
          }
        } else if (action == 'delete') {
          final ok = await showConfirmDialog(
            context,
            title: '删除分类「${cat.name}」',
            message: '将删除此分类，该分类下的专辑将被重置为「未分类」（不会删除任何音频文件）。确定删除吗？',
            okLabel: '删除分类',
          );
          if (ok) {
            await ref.read(categoriesProvider.notifier).removeCategory(cat.name);
            if (activeView == cat.name) {
              onViewChanged('全部音声');
            }
          }
        }
      });
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 6 : 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!collapsed) ...[
            // 品牌区
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text('K', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 11),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hiko', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text('音声收藏室', style: TextStyle(fontSize: 10, color: Color(0xFF888B92))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 23),
          ],
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final (icon, view) in navItems)
                  item(
                    icon: icon,
                    view: view,
                    count: view == '全部音声' || view == '收藏夹' ? count(view) : null,
                  ),
                if (!collapsed) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 18, 6, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '我的分类',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w600,
                            color: theme.hintColor,
                          ),
                        ),
                        // 添加分类按钮
                        Tooltip(
                          message: '新建分类',
                          child: InkWell(
                            onTap: () async {
                              final newCat = await showCategoryEditDialog(context);
                              if (newCat != null) {
                                await ref.read(categoriesProvider.notifier).addCategory(newCat);
                              }
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.add,
                                size: 14,
                                color: theme.hintColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (categories.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Text(
                        '暂无分类，点击 + 添加',
                        style: TextStyle(fontSize: 11, color: theme.hintColor.withValues(alpha: 0.6)),
                      ),
                    )
                  else
                    for (final cat in categories)
                      item(
                        dot: cat.colorValue,
                        view: cat.name,
                        count: count(cat.name),
                        onContextMenu: (pos) => showCategoryMenu(cat, pos),
                      ),
                ],
              ],
            ),
          ),
          // 底部：设置 + 存储
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              item(icon: '⚙', view: '偏好设置', onTap: onOpenSettings),
              if (!collapsed) ...[
                const SizedBox(height: 20),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('本地存储', style: TextStyle(fontSize: 10, color: theme.hintColor)),
                      Text('—', style: TextStyle(fontSize: 10, color: theme.hintColor)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
