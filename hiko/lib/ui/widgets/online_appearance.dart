/// 在线外观设置（1.96.0；1.97.0 起字号改无极滑杆）。
///
/// 两处入口共用同一份范围定义与同一个滑杆行组件：
/// - 设置 → **在线外观**（二级页）
/// - 在线工具栏的 **Aa** 菜单（1.99.20 起是三合一下拉，见 [OnlineAaMenu]）
///
/// 1.96.0 是离散档位（RadioListTile）；1.97.0 裁决 Q2 改成**连续滑杆**：
/// 「各元素字号无极调，而不是选项」。值域常量只有一份（与
/// `SettingsNotifier` 的 clamp 归一化对齐），两处各写一份的话
/// 「这边拖得到、那边存不住」这种差异极难被当成 bug 报上来。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../lyrics/desktop_lyrics_service.dart';
import '../m3e/m3e.dart';

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

/// 防社死隐私模糊开关的统一实现（1.52；1.99.20 起 [OnlineAaMenu] 复用）。
///
/// 原先只在 `home_screen` 里作为私有方法存在（顶栏按钮与 ⌘⇧H 共用）。
/// 1.99.20 把「防社死」并进 Aa 菜单后，同一段逻辑有了第三个调用点 ——
/// 提到这里是因为**这段副作用不能有两份实现**：漏掉「隐藏桌面歌词」
/// 那一句，就把防社死开了个口子（浮动歌词裸奔曲名/台词）。
///
/// 开启时顺带隐藏 macOS 桌面歌词；解除模糊后不自动恢复，由用户自行再开。
void togglePrivacyBlur(WidgetRef ref) {
  privacyBlur.value = !privacyBlur.value;
  if (privacyBlur.value && ref.read(desktopLyricsProvider).isShowing) {
    ref.read(desktopLyricsProvider.notifier).hide();
  }
}

/// 在线工具栏的「Aa」三合一菜单（1.96.0 裁决 Q5=甲；1.99.20 升级）。
///
/// **为什么并进来**：移动端顶栏那一排快捷图标（定位播放 / 切换主题 /
/// 隐私模糊 / 随机播放）里，「定位播放」和「随机播放」都只作用于**本地库**
/// （随机播放是盲选一张本地专辑），在在线页毫无意义却各占一格；
/// 「切换主题」「隐私模糊」有用，但整排仍占掉一屏顶部。
/// 于是移动端在线视图把整排收起（见 `home_screen.dart` 的 `_buildTopbar`），
/// 两个有用的并进这里。
///
/// 三个条目：
/// - **在线外观** → 沿用 [showOnlineAppearanceDialog]（字号 · 每行卡片数）
/// - **防社死 / 外观切换** → **开关式**（裁决 Q3=A）：点一下就地切换、
///   **不关菜单**，条目右侧显示当前状态，能连着把两个开关都调完。
///
/// 不收 `Aa` 文字标签（裁决 Q5=A）：老用户认得这个入口，且这三项里
/// 「在线外观」仍是最常用的那个，换成图标反而认不出。
///
/// 桌面端顶栏图标照旧保留（那排不占地），于是桌面上这两项有两个入口 ——
/// 接受（裁决 Q4=A），换来的是菜单两端完全一致、不需要分叉。
///
/// 1.99.40：`PopupMenuButton` + 两个 `PopupMenuItem` 子类 → `M3EMenu`。
/// 「不关菜单」现在由 `M3EMenuToggle` 承担（它不调 `MenuController.close()`），
/// 不再需要覆写 `handleTap`；两个开关的状态分别由 `ValueListenableBuilder`
/// 与 `Consumer` 提供，菜单开着时切换能立刻刷新。
class OnlineAaMenu extends ConsumerWidget {
  const OnlineAaMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return M3EMenu(
      // 三个条目里最长的「外观切换」+ 状态 + 勾，300 足够
      maxWidth: 300,
      builder: (context, controller, child) => M3EChip(
        label: 'Aa',
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      children: <Widget>[
        M3EMenuAction(
          label: '在线外观',
          leadingIcon: Icons.text_fields_rounded,
          onPressed: () => unawaited(showOnlineAppearanceDialog(context)),
        ),
        const M3EMenuDivider(),
        // 捕获本次 build 的 ref：条目被点掉时 OnlineAaMenu 仍挂在树上，
        // 所以拿它读 notifier 是安全的（与「菜单不关」是同一前提）。
        ValueListenableBuilder<bool>(
          valueListenable: privacyBlur,
          builder: (context, blurred, _) => M3EMenuToggle(
            label: '防社死',
            leadingIcon: blurred
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            statusLabel: blurred ? '已开启' : '已关闭',
            value: blurred,
            onChanged: (_) => togglePrivacyBlur(ref),
          ),
        ),
        Consumer(
          builder: (context, innerRef, _) {
            final dark = innerRef.watch(
              settingsProvider.select((s) => s.theme == 'dark'),
            );
            return M3EMenuToggle(
              label: '外观切换',
              leadingIcon: dark
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              statusLabel: dark ? '深色' : '浅色',
              value: dark,
              // 切换是「读当前主题再取反」，不是直接写 onChanged 的新值
              onChanged: (_) {
                final theme = ref.read(settingsProvider).theme;
                unawaited(
                  ref
                      .read(settingsProvider.notifier)
                      .setTheme(theme == 'dark' ? 'light' : 'dark'),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

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
    final theme = M3ETheme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return M3EDialog(
      maxWidth: 460,
      leading: Icon(
        Icons.text_fields_rounded,
        size: 24,
        color: theme.colors.primary,
      ),
      title: '在线外观',
      contentPadding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      content: Column(
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
                  hint: '在线详情页里每首音频的标题基准字号；最终再乘「详情文字」倍率',
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
      actions: <Widget>[
        M3EButton(
          label: '关闭',
          variant: M3EButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

/// 一组档位：标题 + 说明 + 竖排单选（列数专用 —— 列数是整数，滑杆没有意义）。
///
/// 1.99.42 从 `RadioGroup` + `RadioListTile` 换成 `M3EListItem`：
/// 单选在 M3E 里就是「列表行 + 选中态」，不需要 Material 的单选框。
Widget _choiceGroup<T>({
  required BuildContext context,
  required String title,
  required String hint,
  required List<(T, String)> choices,
  required T value,
  required ValueChanged<T> onChanged,
}) {
  final theme = M3ETheme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: theme.type.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              style: theme.type.bodySmall.copyWith(
                color: theme.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      M3EList(
        children: <Widget>[
          for (final (optionValue, label) in choices)
            M3EListItem(
              title: label,
              selected: optionValue == value,
              onTap: () => onChanged(optionValue),
            ),
        ],
      ),
    ],
  );
}
