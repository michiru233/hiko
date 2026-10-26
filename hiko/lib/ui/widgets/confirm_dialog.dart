import 'package:flutter/material.dart';

import '../m3e/m3e.dart';

/// 确认对话框（对应旧版 confirm-overlay）。
///
/// 1.99.42 换 `M3EDialog`：标题 `headlineSmall`、正文 `bodyMedium`、
/// 按钮 `M3EButton`（取消 = text，确认 = destructive）。原来两处写死的
/// `fontSize: 12` 与 `#D34C44` 一并清掉。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = '删除',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      final theme = M3ETheme.of(context);
      return M3EDialog(
        title: title,
        content: Text(
          message,
          style: theme.type.bodyMedium.copyWith(
            color: theme.colors.onSurfaceVariant,
          ),
        ),
        actions: <Widget>[
          M3EButton(
            label: '取消',
            variant: M3EButtonVariant.text,
            onPressed: () => Navigator.pop(context, false),
          ),
          M3EButton(
            label: okLabel,
            variant: M3EButtonVariant.destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
