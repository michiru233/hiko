import 'package:flutter/material.dart';

/// 星级设置弹窗（1.48）：点星即选（1–5），可清除（0 = 未评分）。
/// 返回 null 表示取消；返回 0–5 由调用方落库。
Future<int?> showRatingDialog(
  BuildContext context, {
  required int initialRating,
  String title = '设置星级',
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _RatingDialog(initialRating: initialRating, title: title),
  );
}

class _RatingDialog extends StatelessWidget {
  const _RatingDialog({required this.initialRating, required this.title});

  final int initialRating;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = initialRating.clamp(0, 5);
    return AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 1; i <= 5; i++)
                InkWell(
                  onTap: () => Navigator.pop(context, i),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      i <= selected ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 34,
                      color: const Color(0xFFE8B33C),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selected > 0 ? '当前 $selected 星' : '未评分',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 16, 10),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 0),
          child: const Text('清除星级', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
