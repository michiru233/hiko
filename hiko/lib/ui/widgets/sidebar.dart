import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_provider.dart';

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
    final count = (String view) => switch (view) {
          '收藏夹' => albums.where((a) => a.favorite).length,
          'ASMR' => albums.where((a) => a.genre == 'ASMR').length,
          '剧情向' => albums.where((a) => a.genre == '剧情向').length,
          '治愈系' => albums.where((a) => a.genre == '治愈系').length,
          '环境音' => albums.where((a) => a.genre == '环境音').length,
          _ => albums.length,
        };

    final navItems = [
      ('▦', '全部音声'),
      ('◷', '最近添加'),
      ('▶', '正在播放'),
      ('♡', '收藏夹'),
    ];
    final collections = [
      (0xFF8E83E7, 'ASMR'),
      (0xFFEA8C79, '剧情向'),
      (0xFF70C6AA, '治愈系'),
      (0xFFE2B25F, '环境音'),
    ];

    Widget item({String? icon, int? dot, required String view, int? count, VoidCallback? onTap}) {
      final active = activeView == view;
      return InkWell(
        onTap: onTap ?? () => onViewChanged(view),
        borderRadius: BorderRadius.circular(8),
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
                Container(width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 5), decoration: BoxDecoration(color: Color(dot), shape: BoxShape.circle))
              else
                SizedBox(width: 17, child: Text(icon ?? '', style: TextStyle(fontSize: 16, color: active ? theme.colorScheme.primary : theme.hintColor))),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    view,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: active ? theme.colorScheme.primary : theme.hintColor,
                    ),
                  ),
                ),
                if (count != null)
                  Text('$count', style: TextStyle(fontSize: 11, color: theme.hintColor.withValues(alpha: 0.6))),
              ],
            ],
          ),
        ),
      );
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
                  item(icon: icon, view: view, count: view == '全部音声' || view == '收藏夹' ? count(view) : null),
                if (!collapsed) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 18, 10, 9),
                    child: Text(
                      '我的分类',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                  for (final (dot, view) in collections)
                    item(dot: dot, view: view, count: count(view)),
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
