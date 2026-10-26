import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';

/// M3E 搜索框（1.99.45）。
///
/// 56dp 全圆、`surfaceContainerHigh` 底、无描边；前置搜索图标、后置清除钮
/// （有输入才出现）。**内部仍是 `TextField`** —— 输入法、选区、快捷键都由框架
/// 负责，重新造一个「自绘输入框」只会把 IME 行为做坏；这里统一的是壳与排版。
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
    this.height = 48,
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
        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(M3EShape.full),
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 8),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  textInputAction: TextInputAction.search,
                  style: theme.type.bodyMedium.copyWith(
                    color: colors.onSurface,
                  ),
                  cursorColor: colors.primary,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hintText,
                    hintStyle: theme.type.bodyMedium.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (hasText)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 18,
                  color: colors.onSurfaceVariant,
                  tooltip: '清除',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    controller.clear();
                    onClear?.call();
                  },
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        );
      },
    );
  }
}
