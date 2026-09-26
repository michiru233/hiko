/// 在线外观设置（1.96.0；1.97.0 起字号改无极滑杆）。
///
/// 两处入口共用同一份范围定义与同一个滑杆行组件：
/// - 设置 → **在线外观**（二级页）
/// - 在线页工具栏第二行的 **Aa** 按钮（对话框）
///
/// 1.96.0 是离散档位（RadioListTile）；1.97.0 裁决 Q2 改成**连续滑杆**：
/// 「各元素字号无极调，而不是选项」。值域常量只有一份（与
/// `SettingsNotifier` 的 clamp 归一化对齐），两处各写一份的话
/// 「这边拖得到、那边存不住」这种差异极难被当成 bug 报上来。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';

/// 在线网格每行卡片数。0 = 自动（按窗口宽度算），桌面与移动端共用这一个值。
/// 列数保持离散档位（列数天然是整数，滑杆没有意义）。
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

/// 与设置页共用的滑杆行：标题 + 当前值 + 重置 + 说明 + 滑杆本体。
///
/// 「重置」是滑杆化之后的必需品：档位时代「回到默认」是点默认那一项，
/// 连续值没有那个锚点，不给出手动的回去路径，用户拖远了就只能凭记忆找。
class OnlineFontSliderRow extends StatelessWidget {
  const OnlineFontSliderRow({
    super.key,
    required this.title,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.format,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final double value;
  final double min;
  final double max;
  final double defaultValue;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                format(value),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                tooltip: '重置为默认',
                visualDensity: VisualDensity.compact,
                onPressed: value == defaultValue ? null : () => onChanged(defaultValue),
                icon: const Icon(Icons.restart_alt_rounded, size: 15),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(hint, style: TextStyle(fontSize: 10.5, color: theme.hintColor)),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          // 无极调（裁决 Q2）：不给 divisions，连续取值
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// 与设置页共用同一批范围常量与 [onlineGridColumnsChoices]，
/// 所以两边永远给出同一个可选集。
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
          // 五组竖排会很高，矮屏要能滚 —— 与黑名单对话框同一套做法
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OnlineFontSliderRow(
                  title: '标签胶囊字号',
                  hint: '全局生效：本地卡面、本地详情、在线卡面与详情一起变',
                  value: settings.tagFontSize,
                  min: SettingsNotifier.tagFontSizeMin,
                  max: SettingsNotifier.tagFontSizeMax,
                  defaultValue: SettingsNotifier.tagFontSizeDefault,
                  format: (v) => '${v.toStringAsFixed(1)} pt',
                  onChanged: notifier.setTagFontSize,
                ),
                OnlineFontSliderRow(
                  title: '在线卡片文字',
                  hint: '列表里卡片的标题与副标题；卡片高度会跟着变',
                  value: settings.onlineCardTextScale,
                  min: SettingsNotifier.onlineTextScaleMin,
                  max: SettingsNotifier.onlineTextScaleMax,
                  defaultValue: SettingsNotifier.onlineTextScaleDefault,
                  format: (v) => '${v.toStringAsFixed(2)}×',
                  onChanged: notifier.setOnlineCardTextScale,
                ),
                OnlineFontSliderRow(
                  title: '在线详情文字',
                  hint: '详情面板内的全部文字（标题 · 信息行 · 目录 · 曲目）',
                  value: settings.onlineDetailTextScale,
                  min: SettingsNotifier.onlineTextScaleMin,
                  max: SettingsNotifier.onlineTextScaleMax,
                  defaultValue: SettingsNotifier.onlineTextScaleDefault,
                  format: (v) => '${v.toStringAsFixed(2)}×',
                  onChanged: notifier.setOnlineDetailTextScale,
                ),
                OnlineFontSliderRow(
                  title: '曲目标题字号',
                  hint: '在线详情页里每首音频的标题；不受「详情文字」倍率影响',
                  value: settings.onlineTrackTitleFontSize,
                  min: SettingsNotifier.trackTitleFontSizeMin,
                  max: SettingsNotifier.trackTitleFontSizeMax,
                  defaultValue: SettingsNotifier.trackTitleFontSizeDefault,
                  format: (v) => '${v.toStringAsFixed(1)} pt',
                  onChanged: notifier.setOnlineTrackTitleFontSize,
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

/// 一组档位：标题 + 说明 + 竖排单选（列数专用 —— 列数是整数，滑杆没有意义）。
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
