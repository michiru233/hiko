import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../menus/m3e_menu.dart';
import '../motion/m3e_pressable.dart';

/// 一个下拉选项：值 + 显示名。
@immutable
class M3ESelectOption<T> {
  const M3ESelectOption(this.value, this.label);

  final T value;
  final String label;
}

/// M3E 下拉选择（1.99.43）。
///
/// 取代 `DropdownButton`：触发器是「当前值 + 展开箭头」的轻量按钮，
/// 菜单直接复用 [M3EMenu]（48dp 行、选中勾、圆角 4、海拔 3），
/// 所以设置页与服务端的排序菜单看起来是同一件东西。
///
/// 触发器不做容器底色：设置行的右侧本来就是一行控件，
/// 再套一层灰底会出现「行里套块」的层级噪音（Material 的 `DropdownButton`
/// 就是这么来的）。
class M3ESelect<T> extends StatelessWidget {
  const M3ESelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.minWidth = 140,
    this.maxWidth = 300,
  });

  final T value;
  final List<M3ESelectOption<T>> options;

  /// 传 null 即禁用。
  final ValueChanged<T>? onChanged;

  final bool enabled;
  final double minWidth;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final active = enabled && onChanged != null;

    final current = options.isEmpty
        ? null
        : options.firstWhere(
            (o) => o.value == value,
            orElse: () => options.first,
          );
    final label = current?.label ?? '';
    final foreground = active
        ? colors.onSurface
        : colors.onSurface.withValues(alpha: 0.38);

    return M3EMenu(
      minWidth: minWidth,
      maxWidth: maxWidth,
      builder: (context, controller, child) => M3EPressable(
        enabled: active,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        borderRadius: BorderRadius.circular(M3EShape.sm),
        pressScale: 0.97,
        semanticLabel: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.type.labelLarge.copyWith(color: foreground),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: active
                    ? colors.onSurfaceVariant
                    : colors.onSurface.withValues(alpha: 0.38),
              ),
            ],
          ),
        ),
      ),
      children: <Widget>[
        for (final option in options)
          M3EMenuAction(
            label: option.label,
            selected: option.value == value,
            onPressed: () => onChanged?.call(option.value),
          ),
      ],
    );
  }
}
