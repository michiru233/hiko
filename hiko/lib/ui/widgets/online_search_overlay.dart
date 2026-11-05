import 'package:flutter/material.dart';

import '../fonts/hiko_font_area.dart';
import '../m3e/m3e.dart';

/// 在线页的「放大搜索」浮层（1.99.70）。
///
/// 点折叠态的 [M3ESearchEntry] 打开：顶部居中、约 90% 宽、56dp 高的输入面板，
/// 自动聚焦、键盘弹起；提交后自动收起看结果。
///
/// 为什么用 `showGeneralDialog` 而不是页内 Overlay：
/// - 安卓返回键 / 桌面 Esc / 遮罩点击 / 焦点陷阱 都是 `PopupRoute` 白送的；
/// - 页内 Overlay 在 HomeScreen 的 `PopScope` 之下，返回键会先被它吃掉去清筛选；
/// - 过渡曲线要跟随「动效」设置，`showGeneralDialog` 可自定义，`showDialog` 不行。
Future<void> showOnlineSearchOverlay(
  BuildContext context, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required List<String> history,
  required ValueChanged<String> onSubmit,
  required Future<void> Function() onClearHistory,
}) {
  final theme = M3ETheme.of(context);
  final motion = theme.motion;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: theme.colors.scrim.withValues(alpha: 0.32),
    transitionDuration: motion.duration(
      M3ESpringType.spatial,
      M3ESpringSpeed.fast,
    ),
    routeSettings: const RouteSettings(name: 'online-search-overlay'),
    pageBuilder: (_, _, _) => OnlineSearchOverlay(
      controller: controller,
      focusNode: focusNode,
      history: history,
      onSubmit: onSubmit,
      onClearHistory: onClearHistory,
    ),
    transitionBuilder: (context, animation, _, child) {
      // 动效关闭：直接给终态，连曲线都不建
      if (!motion.enabled) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: motion.fallbackCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 搜索浮层本体。公开便于 widget 测试 `find.byType`。
class OnlineSearchOverlay extends StatefulWidget {
  const OnlineSearchOverlay({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.history,
    required this.onSubmit,
    required this.onClearHistory,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// 打开时快照，内部复制一份（清空历史只影响本次面板）。
  final List<String> history;

  /// 已在 `pop` 之后调用，调用方可以直接发请求。
  final ValueChanged<String> onSubmit;

  final Future<void> Function() onClearHistory;

  @override
  State<OnlineSearchOverlay> createState() => _OnlineSearchOverlayState();
}

class _OnlineSearchOverlayState extends State<OnlineSearchOverlay> {
  late List<String> _history;

  @override
  void initState() {
    super.initState();
    _history = List<String>.of(widget.history);
    // autofocus 在路由过渡期间偶发不生效；这里补一次，同时把已有草稿全选，
    // 直接输入即替换（用户裁决：打开时全选）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = widget.controller.text;
      if (text.isNotEmpty) {
        widget.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      }
      widget.focusNode.requestFocus();
    });
  }

  void _submit(String raw) {
    final word = raw.trim();
    final navigator = Navigator.of(context);
    if (word.isEmpty) {
      // 空词只关闭：不改结果、不回热门榜
      navigator.pop();
      return;
    }
    navigator.pop();
    widget.onSubmit(word);
  }

  void _useHistory(String term) {
    widget.controller.text = term;
    _submit(term);
  }

  Future<void> _clearHistory() async {
    await widget.onClearHistory();
    if (!mounted) return;
    setState(() => _history = const <String>[]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final muted = theme.type.bodySmall.copyWith(
      color: theme.colors.onSurfaceVariant,
    );
    return M3EDialog(
      // 路由在 Navigator 之上，页面级 HikoFontArea 覆盖不到 —— 显式沿用在线页字体
      fontArea: HikoFontAreaId.online,
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 56,
        16,
        16,
      ),
      maxWidth: 560,
      // 内容自带 ListView，不能再套一层滚动
      scrollable: false,
      semanticLabel: '搜索在线作品',
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          M3ESearchBar(
            key: const ValueKey('online-search-field'),
            height: 56,
            autofocus: true,
            controller: widget.controller,
            focusNode: widget.focusNode,
            hintText: '搜索在线作品',
            onSubmitted: _submit,
            // ✕ 只清输入（组件内部已 controller.clear），不发请求、不动筛选
            onClear: () {},
          ),
          const SizedBox(height: 8),
          Text('日文原关键词命中率最高', style: muted),
          if (_history.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '搜索历史',
                    style: theme.type.labelLarge.copyWith(
                      color: theme.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                M3EButton(
                  label: '清空',
                  variant: M3EButtonVariant.text,
                  size: M3EButtonSize.small,
                  onPressed: _clearHistory,
                ),
              ],
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final term in _history)
                    M3EListItem(
                      title: term,
                      leading: Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: theme.colors.onSurfaceVariant,
                      ),
                      onTap: () => _useHistory(term),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        M3EButton(
          label: '取消',
          variant: M3EButtonVariant.text,
          size: M3EButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
