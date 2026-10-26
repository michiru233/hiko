import 'package:flutter/material.dart';

import '../m3e/m3e.dart';

/// 星级设置弹窗（1.48）：点星即选（1–5），可清除（0 = 未评分）。
/// 返回 null 表示取消；返回 0–5 由调用方落库。
///
/// 1.99.42 换 `M3EDialog` + `M3EPressable`（星星不再是 Material `InkWell`）。
Future<int?> showRatingDialog(
  BuildContext context, {
  required int initialRating,
  String title = '设置星级',
}) {
  return showDialog<int>(
    context: context,
    builder: (context) =>
        _RatingDialog(initialRating: initialRating, title: title),
  );
}

class _RatingDialog extends StatelessWidget {
  const _RatingDialog({required this.initialRating, required this.title});

  final int initialRating;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final selected = initialRating.clamp(0, 5);
    return M3EDialog(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 1; i <= 5; i++)
                M3EPressable(
                  onTap: () => Navigator.pop(context, i),
                  borderRadius: BorderRadius.circular(18),
                  pressScale: 0.94,
                  semanticLabel: '$i 星',
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      i <= selected
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 34,
                      // 品牌金黄：不随主题种子变（1.99.48 统一收口）
                      color: const Color(0xFFE8B33C),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selected > 0 ? '当前 $selected 星' : '未评分',
            style: theme.type.bodyMedium.copyWith(
              color: theme.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        M3EButton(
          label: '清除星级',
          variant: M3EButtonVariant.text,
          onPressed: () => Navigator.pop(context, 0),
        ),
        M3EButton(
          label: '取消',
          variant: M3EButtonVariant.text,
          onPressed: () => Navigator.pop(context, null),
        ),
      ],
    );
  }
}
