import 'package:flutter/material.dart';

/// 导航视图 → 静息态图标。
///
/// 与选中态分开两张表：M3E 的导航选中态必须**换实心图标**，
/// 只改颜色在深色模式下会掉对比度（见 plan-hiko-m3e-redesign.md §8.1）。
const Map<String, IconData> hikoNavIcons = <String, IconData>{
  '本地音声': Icons.grid_view_outlined,
  '最近添加': Icons.schedule_outlined,
  '最近播放': Icons.history,
  '收藏夹': Icons.favorite_border,
  '在线': Icons.cloud_outlined,
  '在线收藏': Icons.cloud_done_outlined,
  '下载': Icons.download_outlined,
  '统计': Icons.bar_chart_outlined,
};

/// 导航视图 → 选中态图标（实心）。
const Map<String, IconData> hikoNavSelectedIcons = <String, IconData>{
  '本地音声': Icons.grid_view_rounded,
  '最近添加': Icons.schedule_rounded,
  '最近播放': Icons.history_rounded,
  '收藏夹': Icons.favorite,
  '在线': Icons.cloud,
  '在线收藏': Icons.cloud_done,
  '下载': Icons.download_rounded,
  '统计': Icons.bar_chart_rounded,
};

/// 未知视图的兜底图标（用户自定义分类走这条）。
const IconData hikoNavFallbackIcon = Icons.folder_outlined;
const IconData hikoNavFallbackSelectedIcon = Icons.folder;
