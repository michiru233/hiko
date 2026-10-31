import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';

/// M3E 输入框的密度档。
///
/// - [compact]：32dp 高、`M3EShape.sm`(8) 圆角、`labelSmall` 文字。设置行的
///   trailing、翻页跳转这类「挤在一行里」的场景用它。
/// - [regular]：40dp 高、`M3EShape.md`(12) 圆角、`bodySmall` 文字。对话框表单用它。
enum M3ETextFieldSize { compact, regular }

/// M3E 输入框（1.99.60）。
///
/// 与 [M3ESearchBar] 的关系：搜索栏是「56dp 全圆 + 前置搜索图标」的搜索语义，
/// 这里是「填充底 + 圆角矩形 + 标签在上方」的表单语义。两者内部都还是
/// `TextField` —— 输入法、选区、快捷键、无障碍由框架负责，自绘输入框只会把
/// IME 行为做坏；这里统一的是**壳与排版**。
///
/// 三条排版决定，都是为了「行高固定」：
/// - 标签画在**框上方**（`labelSmall` + 6dp），不做 Material 那种框内浮动标签：
///   浮动标签在有/无内容之间会改变行高，设置行的 72dp 双行会跟着跳。
/// - 用 `isCollapsed` + 显式 `contentPadding` 控制高度，不让 `isDense` 的
///   平台默认值插进来（桌面与安卓的 `isDense` 结果不同）。
/// - 错误态把错误文案画在框**下方**、由本组件负责，调用点不再各写一份
///   `errorText` 样式。
class M3ETextField extends StatelessWidget {
  const M3ETextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    this.size = M3ETextFieldSize.compact,
    this.width,
    this.focusNode,
  });

  final TextEditingController controller;

  /// 框上方的标签；null 则不占位（不留空行）。
  final String? label;

  final String? hintText;

  /// 框下方的说明文案（错误态优先显示 [errorText]）。
  final String? helperText;

  /// 框下方的错误文案；非空即进入错误态（描边变 `error`）。
  final String? errorText;

  final Widget? prefixIcon;
  final Widget? suffixIcon;

  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final bool readOnly;
  final int maxLines;

  /// 超过 1 时 `TextField` 自带计数器会出现在框下方，与本组件的 [helperText]
  /// 同区域——两者都会显示，调用点二选一。
  final int? maxLength;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 点空白处收键盘；不传则完全不拦截（桌面点击无需收键盘）。
  final TapRegionCallback? onTapOutside;

  final M3ETextFieldSize size;

  /// 行内场景的固定宽度（设置行 trailing 220、翻页跳转 54）；null = 撑满父级。
  final double? width;

  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final compact = size == M3ETextFieldSize.compact;
    final radius = compact ? M3EShape.sm : M3EShape.md;
    final textStyle = (compact ? theme.type.labelSmall : theme.type.bodySmall)
        .copyWith(color: enabled ? colors.onSurface : colors.onSurfaceVariant);
    final hintStyle =
        (compact ? theme.type.labelSmall : theme.type.bodySmall).copyWith(
      color: colors.onSurfaceVariant,
    );
    final hasError = errorText != null && errorText!.isNotEmpty;
    final borderColor = hasError ? colors.error : colors.outlineVariant;

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      style: textStyle,
      cursorColor: colors.primary,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
      decoration: InputDecoration(
        isCollapsed: true,
        filled: true,
        fillColor: enabled ? colors.surfaceContainerHigh : colors.onSurface.withValues(alpha: 0.04),
        hintText: hintText,
        hintStyle: hintStyle,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        prefixIcon: prefixIcon,
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffixIcon,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: OutlineInputBorder(
          borderRadius: M3EShape.radius(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: M3EShape.radius(radius),
          borderSide: hasError
              ? BorderSide(color: borderColor)
              : BorderSide.none,
        ),
        // 面板底色本身就是填充块，focus 只用 1.5dp 主色描边标出来，
        // 不再叠一层 Material 的 focused 填充/发光。
        focusedBorder: OutlineInputBorder(
          borderRadius: M3EShape.radius(radius),
          borderSide: BorderSide(
            color: hasError ? colors.error : colors.primary,
            width: 1.5,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: M3EShape.radius(radius),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: M3EShape.radius(radius),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: M3EShape.radius(radius),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        counterStyle: theme.type.labelSmall.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    );

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label!,
            style: theme.type.labelSmall.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
        ],
        field,
        if (hasError) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: theme.type.bodySmall.copyWith(color: colors.error),
          ),
        ] else if (helperText != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            helperText!,
            style: theme.type.labelSmall.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );

    if (width == null) return column;
    return SizedBox(width: width, child: column);
  }
}
