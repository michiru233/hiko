import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/semantic_color_tokens.dart';
import '../../tokens/shape_tokens.dart';

/// M3E 提示条材质（plan §8.8）——**全产品唯一的轻提示面**。
///
/// 1.99.57 之前「提示」有三套材质：`toast.dart` 的反色面（4 圆角）、
/// `activity_overlay` 的 `_ToastBanner`（8 圆角）、在线详情 8 处
/// `ScaffoldMessenger.showSnackBar`（跟 `theme.snackBarTheme`）。三套的差别
/// 小到「单独看都还行」，但同一个「已复制」动作在本地与在线的观感不同，
/// 这正是审计 C-08 记的那条债。
///
/// 现在只留这一个面：`M3ESemantic.toastSurface`（深色、明暗主题共用，
/// 保证任何背景上都读得清）+ `onToastSurface` 文字 + [M3EShape.sm] 圆角。
///
/// **本组件只画「面」**：定位（底部 96 / 居中 / 520 上限）由调用方决定。
/// 全局 toast 走 `showHikoToast`，活动进度条走 `activity_overlay`，
/// 两者都用这里的面，但一个在 Overlay、一个在根 Stack 里。
class M3ESnackbar extends StatelessWidget {
  const M3ESnackbar({super.key, required this.message, this.icon});

  final String message;

  /// 可选的 16dp 前导图标（成功 / 失败）。不给就是纯文字。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final type = M3ETheme.of(context).type;
    final icon = this.icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: M3ESemantic.toastSurface,
        borderRadius: M3EShape.radius(M3EShape.sm),
        boxShadow: <BoxShadow>[
          // 提示条是「临时浮起」而不是菜单层：沿用 1.99.30 起就在用的
          // 12blur / 4y 柔和投影，不套 `M3EElevation.shadow` —— 后者给的是
          // 双层硬投影（菜单/FAB 用），在窄条上会显出两条边。
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: M3ESemantic.onToastSurface),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: type.bodySmall.copyWith(
                color: M3ESemantic.onToastSurface,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
