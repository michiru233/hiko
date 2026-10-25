import 'package:flutter/widgets.dart';

/// M3 窗口尺寸类（Window size class）。
///
/// 阈值与 Material 3 一致：compact < 600 ≤ medium < 840 ≤ expanded。
/// 壳层只认宽度，不认平台 —— 这是「一套断点、两套壳」的前提
/// （见 plan-hiko-m3e-redesign.md §6.1）。
enum HikoWindowSize { compact, medium, expanded }

/// 按可用宽度判定尺寸类。
HikoWindowSize hikoWindowSize(double width) {
  if (width < 600) return HikoWindowSize.compact;
  if (width < 840) return HikoWindowSize.medium;
  return HikoWindowSize.expanded;
}

/// 从 context 取当前尺寸类（会随窗口变化重建）。
HikoWindowSize hikoWindowSizeOf(BuildContext context) =>
    hikoWindowSize(MediaQuery.sizeOf(context).width);
