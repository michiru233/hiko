import 'package:flutter/material.dart';

/// 确认对话框（对应旧版 confirm-overlay）
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
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: Text(
          message,
          style: TextStyle(fontSize: 12, height: 1.7, color: theme.hintColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD34C44)),
            child: Text(okLabel, style: const TextStyle(fontSize: 12)),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
