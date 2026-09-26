/// 在线外观设置（1.96.0）。
///
/// 两处入口共用同一份档位定义：
/// - 设置 → **在线外观**（二级页，行式下拉，与设置页其它项同一种形态）
/// - 在线页工具栏第二行的 **Aa** 按钮（对话框，`RadioListTile` 竖排）
///
/// 形态不同是刻意的 —— 行式贴合设置页，弹窗则是「就地改完接着看」。
/// 但**档位值只有一份**：两处各写一份的话，用户在两个地方会看到不同的可选集，
/// 而更糟的是「这边能选、那边选不到」这种差异极难被当成 bug 报上来。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';

/// 标签胶囊字号档位。**值必须与 `SettingsNotifier.validTagFontSizes` 逐位一致** ——
/// 归一化在那边做，这里只提供可选集。不一致的后果是「选了某档，存下去被归一化成
/// 别的值」，界面上表现为「选中项自己跳回去」，看起来像点了没反应。
/// `test/ui/online_appearance_test.dart` 用断言钉住了这一致性。
const tagFontSizeChoices = <(double, String)>[
  (9.0, '9'),
  (10.0, '10'),
  (11.0, '11（默认）'),
  (12.0, '12'),
  (14.0, '14'),
];

/// 卡片文字与详情文字共用的倍率档位（两组各自独立设置，值域相同）
const onlineTextScaleChoices = <(double, String)>[
  (0.85, '0.85×（小）'),
  (1.0, '1.0×（默认）'),
  (1.15, '1.15×（大）'),
  (1.30, '1.30×（超大）'),
];

/// 在线网格每行卡片数。0 = 自动（按窗口宽度算），桌面与移动端共用这一个值。
const onlineGridColumnsChoices = <(double, String)>[
  (0.0, '自动（按窗口宽度）'),
  (3.0, '3 列'),
  (4.0, '4 列'),
  (5.0, '5 列'),
  (6.0, '6 列'),
  (7.0, '7 列'),
  (8.0, '8 列'),
];

/// 在线页工具栏的「Aa」入口：就地调在线外观，不用绕回设置页。
///
/// 放在排序 chip 右边（裁决 Q5=甲）—— 那一行本来就是「这一页的显示选项」，
/// 而改字号多半发生在「正在看这个列表、觉得字小了」的时刻。
Future<void> showOnlineAppearanceDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const OnlineAppearanceDialog(),
    );

/// 与设置页共用同一批 [tagFontSizeChoices] / [onlineTextScaleChoices] /
/// [onlineGridColumnsChoices]，所以两边永远给出同一个可选集。
class OnlineAppearanceDialog extends ConsumerWidget {
  const OnlineAppearanceDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.text_fields_rounded,
            size: 17,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('在线外观', style: TextStyle(fontSize: 15)),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          // 四组竖排会很高，矮屏要能滚 —— 与黑名单对话框同一套做法
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _choiceGroup<double>(
                  context: context,
                  title: '标签胶囊字号',
                  hint: '全局生效：本地卡面、本地详情、在线卡面与详情一起变',
                  choices: tagFontSizeChoices,
                  value: settings.tagFontSize,
                  onChanged: notifier.setTagFontSize,
                ),
                _choiceGroup<double>(
                  context: context,
                  title: '在线卡片文字',
                  hint: '列表里卡片的标题与副标题；卡片高度会跟着变',
                  choices: onlineTextScaleChoices,
                  value: settings.onlineCardTextScale,
                  onChanged: notifier.setOnlineCardTextScale,
                ),
                _choiceGroup<double>(
                  context: context,
                  title: '在线详情文字',
                  hint: '详情面板内的全部文字（标题 · 信息行 · 目录 · 曲目）',
                  choices: onlineTextScaleChoices,
                  value: settings.onlineDetailTextScale,
                  onChanged: notifier.setOnlineDetailTextScale,
                ),
                _choiceGroup<double>(
                  context: context,
                  title: '每行卡片数',
                  hint: '桌面与移动端共用；自动 = 按窗口宽度',
                  choices: onlineGridColumnsChoices,
                  value: settings.onlineGridColumns,
                  onChanged: notifier.setOnlineGridColumns,
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

/// 一组档位：标题 + 说明 + 竖排单选。
///
/// 用 `RadioGroup` 而不是老的 `RadioListTile(groupValue:, onChanged:)` ——
/// 后者在 3.32 之后已废弃，继续用会给 `flutter analyze` 添两条 lint。
Widget _choiceGroup<T>({
  required BuildContext context,
  required String title,
  required String hint,
  required List<(T, String)> choices,
  required T value,
  required ValueChanged<T> onChanged,
}) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(hint, style: TextStyle(fontSize: 10.5, color: theme.hintColor)),
          ],
        ),
      ),
      RadioGroup<T>(
        groupValue: value,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (optionValue, label) in choices)
              RadioListTile<T>(
                value: optionValue,
                dense: true,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(label, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    ],
  );
}
