import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../actions/m3e_icon_button.dart';
import 'm3e_search_surface.dart';

/// M3E 搜索框（1.99.45，1.99.71 校准）。
///
/// 56dp 全圆、`surfaceContainerHigh` 底（可覆盖）、海拔 3、无描边；前置搜索图标、
/// 后置清除钮（有输入才出现）。壳与折叠胶囊共用 [M3ESearchSurface]。
/// **内部仍是 `TextField`** —— 输入法、选区、快捷键都交给框架。
///
/// 与 Material `SearchBar` 的区别：那个自带 elevation/overlay 与一整套
/// `SearchAnchor` 语义，而 Hiko 的搜索是「提交式」（回车/点历史才发请求），
/// 不需要随打随搜的锚点面板。
class M3ESearchBar extends StatelessWidget {
  const M3ESearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = '搜索',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.height = 56,
    this.fillColor,
    this.surfaceOpacity = 1,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 清除钮回调；不给则内部只清空 controller（调用方通常还要重置结果）。
  final VoidCallback? onClear;

  final bool autofocus;
  final double height;

  /// 覆盖填充色（浮层里用 `surfaceContainerHighest` 与面板拉开一档）。
  final Color? fillColor;

  /// 用户可调的搜索面不透明度（1.99.71）：只调填充与阴影，不做模糊。
  final double surfaceOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    // controller 变化要重画（清除钮显隐）；用 ValueListenableBuilder 而不是
    // 让调用方在 onChanged 里 setState —— 后者在移动端离屏副本里会漏。
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;
        return M3ESearchSurface(
          height: height,
          fillColor: fillColor,
          surfaceOpacity: surfaceOpacity,
          trailing: hasText
              ? M3EIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '清除',
                  size: M3EIconButtonSize.small,
                  onPressed: () {
                    controller.clear();
                    onClear?.call();
                  },
                )
              : null,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            textInputAction: TextInputAction.search,
            style: theme.type.bodyLarge.copyWith(color: colors.onSurface),
            cursorColor: colors.primary,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hintText,
              hintStyle: theme.type.bodyLarge.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}
