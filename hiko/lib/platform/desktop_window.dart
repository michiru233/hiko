import 'dart:io' show Platform;

import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;

/// 桌面窗口装饰内缩（1.99.33）。
///
/// macOS 窗口使用「标题栏透明 + fullSizeContentView」（MainFlutterWindow.swift），
/// 红绿灯占窗口顶部约 28pt —— UI 顶层（各 Scaffold body）统一让出，
/// 让应用自绘顶栏从红绿灯下方开始、内容色直接铺到窗口上缘。
/// 平台判断集中在本文件（D4：UI 层平台判断白名单）。
double windowTopInset(BuildContext context) {
  if (!Platform.isMacOS) return 0;
  // 全屏 / 展开到刘海下时系统会经 MediaQuery 报安全区，尊重之
  final safeTop = MediaQuery.paddingOf(context).top;
  return safeTop > 0 ? safeTop : 28;
}
