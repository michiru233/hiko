import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/elevation_tokens.dart';
import '../../tokens/shape_tokens.dart';

/// M3E 对话框（B2，1.99.42）。
///
/// 替掉 21 处 `AlertDialog`。此前它们只共享 `dialogTheme` 的壳（28 圆角 /
/// `surfaceContainerHigh` / 24sp 标题），标题、正文、按钮各写各的
/// `TextStyle(fontSize: …)`，`category_dialog` 甚至把圆角覆写成 14
/// （审计 C-10）。这个组件把「壳 + 标题 + 正文 + 按钮」四段固定下来：
///
/// - 面板：`surfaceContainerHigh`、圆角 [M3EShape.xl]（28）、海拔
///   [M3EElevation.level3]、去 surfaceTint；
/// - 标题：`headlineSmall`（24），可带前导（色点 / 图标）；
/// - 正文：`bodyMedium` 由调用方给，外层统一加 24 边距 + 可滚动；
/// - 按钮：`M3EButton`（文字 / 填充 / 危险），右对齐，窄屏自动换行。
///
/// 不在组件里塞 `AlertDialog`：它的 `titlePadding` / `contentPadding` /
/// `actionsPadding` 三套内边距会让每个调用点又长出一份自己的数字。
class M3EDialog extends StatelessWidget {
  const M3EDialog({
    super.key,
    this.title,
    this.leading,
    this.content,
    this.actions = const <Widget>[],
    this.maxWidth = 520,
    this.contentPadding,
    this.titlePadding = const EdgeInsets.fromLTRB(24, 24, 24, 0),
    this.actionsPadding = const EdgeInsets.fromLTRB(24, 8, 24, 24),
    this.scrollable = true,
    this.semanticLabel,
  });

  final String? title;

  /// 标题前导（分类色点、状态图标）。给 24dp 见方的组件最合适。
  final Widget? leading;

  final Widget? content;

  /// 通常是 `M3EButton`；空表 = 不画按钮区。
  final List<Widget> actions;

  final double maxWidth;

  /// 默认 24 边距；列表类内容传 [EdgeInsets.zero] 让行自己贴边。
  final EdgeInsetsGeometry? contentPadding;

  final EdgeInsetsGeometry titlePadding;
  final EdgeInsetsGeometry actionsPadding;

  /// 正文是否由本组件包一层滚动视图。
  ///
  /// 传 false 用于**正文自带滚动**的对话框（例如分类选择列表），
  /// 否则会套出「竖向滚动套竖向滚动」，内层拿不到有界高度。
  final bool scrollable;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final hasActions = actions.isNotEmpty;
    final padding =
        contentPadding ?? EdgeInsets.fromLTRB(24, 12, 24, hasActions ? 0 : 24);

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Dialog(
        backgroundColor: colors.surfaceContainerHigh,
        // 不用 primary 染色：层深靠色阶（§3 原则 1）
        surfaceTintColor: Colors.transparent,
        elevation: M3EElevation.level3,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(M3EShape.xl),
        ),
        // M3 默认左右各 40，360dp 屏只剩 280；24 给表单留出余量
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (title != null)
                Padding(
                  padding: titlePadding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      if (leading != null) ...<Widget>[
                        leading!,
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.type.headlineSmall.copyWith(
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (content != null)
                Flexible(
                  child: Padding(
                    padding: padding,
                    child: scrollable
                        ? SingleChildScrollView(child: content)
                        : content,
                  ),
                ),
              if (hasActions)
                Padding(
                  padding: actionsPadding,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
