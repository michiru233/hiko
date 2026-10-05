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
/// 「不关菜单」的做法与 [OnlineSortMenu] 的分级条目同源：
/// `PopupMenuItem` 子类只覆写 `handleTap`（见 [_AaMenuToggleItemState]）。
class OnlineAaMenu extends ConsumerWidget {
  const OnlineAaMenu({super.key});

  /// min(320, 屏高 × 0.45)：三个条目其实很矮，但小屏仍按比例缩，别顶到天花板。
  /// 上限取 320（不是排序菜单的 400）—— 这里只有三项，不需要那么多。
  static double _menuMaxHeight(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final scaled = screen * 0.45;
    return scaled < 320 ? scaled : 320;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<Object>(
      tooltip: '在线外观 · 外观切换 · 防社死',
      constraints: BoxConstraints(
        minWidth: 200,
        maxWidth: 300,
        maxHeight: _menuMaxHeight(context),
      ),
      onSelected: (value) {
        if (value == 'appearance') {
          unawaited(showOnlineAppearanceDialog(context));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem<Object>(
          value: 'appearance',
          height: 42,
          child: SizedBox(
            width: 180,
            child: Row(
              children: [
                Icon(Icons.text_fields_rounded, size: 16),
                SizedBox(width: 10),
                Expanded(
                  child: Text('在线外观', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        // 捕获本次 build 的 ref：条目被点掉时 OnlineAaMenu 仍挂在树上，
        // 所以拿它读 notifier 是安全的（与「菜单不关」是同一前提）。
        _AaMenuToggleItem(
          onToggle: () => togglePrivacyBlur(ref),
          content: (context) => ValueListenableBuilder<bool>(
            valueListenable: privacyBlur,
            builder: (context, blurred, _) => _AaRow(
              icon: blurred
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              label: '防社死',
              status: blurred ? '已开启' : '已关闭',
              on: blurred,
            ),
          ),
        ),
        _AaMenuToggleItem(
          onToggle: () {
            final theme = ref.read(settingsProvider).theme;
            unawaited(
              ref
                  .read(settingsProvider.notifier)
                  .setTheme(theme == 'dark' ? 'light' : 'dark'),
            );
          },
          content: (context) => Consumer(
            builder: (context, innerRef, _) {
              final dark = innerRef.watch(
                settingsProvider.select((s) => s.theme == 'dark'),
              );
              return _AaRow(
                icon: dark
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                label: '外观切换',
                status: dark ? '深色' : '浅色',
                on: dark,
              );
            },
          ),
        ),
      ],
      child: const Chip(
        label: Text(
          'Aa',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Aa 菜单里的一行「图标 + 名称 + 当前状态」。
class _AaRow extends StatelessWidget {
  const _AaRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.on,
  });

  final IconData icon;
  final String label;
  final String status;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = on ? theme.colorScheme.primary : theme.hintColor;
    return Row(
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(status, style: TextStyle(fontSize: 11, color: accent)),
      ],
    );
  }
}

/// Aa 菜单里的**开关式**条目：`handleTap` **不 pop**，菜单保持打开（裁决 Q3=A）。
///
/// 与 [OnlineSortMenu] 的分级条目（`_AgeFilterItem`）同一套做法 ——
/// 覆写 `handleTap` 而不是用 `PopupMenuItem(enabled: false)`：
/// 后者在 M3 下会把文字压成 onSurface@38% 灰并套 `Semantics(enabled: false)`，
/// 而这两个开关明明是可用的。
///
/// 内容由 `content` 回调提供（里面各自挂 `ValueListenableBuilder` / `Consumer`），
/// 所以**菜单开着的时候切换能立刻把状态刷出来**，不用重开菜单。
class _AaMenuToggleItem extends PopupMenuItem<Object> {
  const _AaMenuToggleItem({required this.content, required this.onToggle})
      // child 是父类的必填参数，内容由 buildChild() 覆写提供，这里给个占位
      : super(value: null, height: 42, child: const SizedBox.shrink());

  final WidgetBuilder content;
  final VoidCallback onToggle;

  @override
  PopupMenuItemState<Object, PopupMenuItem<Object>> createState() =>
      _AaMenuToggleItemState();
}

class _AaMenuToggleItemState
    extends PopupMenuItemState<Object, _AaMenuToggleItem> {
  @override
  void handleTap() {
    // 刻意不 Navigator.pop：菜单不关，能连着把两个开关都调完
    widget.onToggle();
  }

  @override
  Widget? buildChild() =>
      SizedBox(width: 180, child: widget.content(context));
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
