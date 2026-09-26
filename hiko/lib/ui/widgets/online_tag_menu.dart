/// 在线标签的右键菜单与黑名单管理（1.95.0）。
///
/// 两件事放在一个文件里，因为它们共用同一套词表：菜单里的「加入黑名单 / 移出黑名单」
/// 与管理列表里的那一行说的是同一句话，分开放必然漂移。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/online_blacklist.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import 'confirm_dialog.dart';
import 'context_menu.dart';
import 'detail_kit.dart';
import 'toast.dart';

/// 标签胶囊的三个动作（裁决 Q4=甲）
enum _TagAction { filter, block, unblock, copy }

/// 标签胶囊的右键（桌面）/ 长按（触屏）菜单。
///
/// 入口只挂在**标签胶囊**上（裁决 Q3=甲）—— 社团与声优胶囊不带这套动作，
/// 因为黑名单按裁决 Q1=甲 只支持标签。
///
/// 三个动作都是「就着这一个标签立刻能做完的事」：
/// - **按此标签筛选**：与左键点胶囊同一件事，右键菜单里再给一次是为了
///   「先看菜单、再决定」这种读法；[onFilter] 为空（详情页在某些视图下不可筛）时不出现
/// - **加入黑名单 / 移出黑名单**：跟着当前状态变，已屏蔽时不给「再加入」
/// - **复制标签名**：标签是日文/中文混排，手抄容易错，而「拿去别处搜同一个标签」
///   是很常见的下一步
///
/// 不可点的胶囊（服务端只给了名字、拿不到 `id`）**连菜单都不该有** ——
/// 既筛不了也屏蔽不了，给了菜单等于给了个死操作。这一点由调用方保证：
/// `HikoTagChip` 只在 `onTap != null` 时才把 `onContextMenu` 接上。
Future<void> showOnlineTagMenu({
  required BuildContext context,
  required WidgetRef ref,
  required OnlineTag tag,
  required Offset position,
  VoidCallback? onFilter,
}) async {
  final blocked = isTagBlocked(tag, ref.read(blockedTagIdsProvider));
  final action = await showHikoContextMenu<_TagAction>(
    context: context,
    position: position,
    items: [
      if (onFilter != null)
        const HikoContextMenuItem(
          value: _TagAction.filter,
          label: '按此标签筛选',
          icon: Icons.filter_alt_outlined,
        ),
      HikoContextMenuItem(
        value: blocked ? _TagAction.unblock : _TagAction.block,
        label: blocked ? '移出黑名单' : '加入黑名单',
        icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
      ),
      const HikoContextMenuItem(
        value: _TagAction.copy,
        label: '复制标签名',
        icon: Icons.content_copy_rounded,
      ),
    ],
  );
  if (action == null || !context.mounted) return;

  final notifier = ref.read(onlineBrowseProvider.notifier);
  final settings = ref.read(settingsProvider.notifier);

  switch (action) {
    case _TagAction.filter:
      onFilter?.call();

    case _TagAction.block:
      // 先算出这句提示该怎么说：屏蔽的若正是当前筛选标签，筛选会被一并退出
      // （见 `reloadAfterBlock`），不说清楚用户会以为结果页崩了
      final browse = ref.read(onlineBrowseProvider);
      final exitsFilter =
          browse.source == OnlineSource.tag && browse.tag?.id == tag.id;
      await settings.addBlockedTag(tag);
      if (!context.mounted) return;
      showHikoToast(
        context,
        exitsFilter
            ? '已屏蔽「${tag.name}」，按它的筛选已退出'
            : '已屏蔽标签「${tag.name}」',
      );
      await notifier.reloadAfterBlock(tagId: tag.id);

    case _TagAction.unblock:
      await settings.removeBlockedTag(tag.id);
      if (!context.mounted) return;
      showHikoToast(context, '已移出黑名单：「${tag.name}」');
      await notifier.reloadAfterUnblock(tagId: tag.id);

    case _TagAction.copy:
      await Clipboard.setData(ClipboardData(text: tag.name));
      if (context.mounted) showHikoToast(context, '已复制「${tag.name}」');
  }
}

/// 点标签准备按它筛选之前的一道守卫（1.95.0 裁决 Q5）。
///
/// 返回值就是这个标签该不该**放行**（即 `selectTag(bypassBlocklist:)` 的实参）：
/// - `null` —— 用户取消了，调用方什么都不该做
/// - `false` —— 正常筛选，黑名单照常生效
/// - `true` —— 用户选了「仍要查看」，把**这一个**标签从排除项里摘出去
///
/// 单独抽成函数的原因：两处入口（在线页卡面 / 在线收藏页卡面）说的是同一件事，
/// 各写一份确认文案必然一边改一边忘。
Future<bool?> resolveBlockedTagFilter(
  BuildContext context,
  WidgetRef ref,
  OnlineTag tag,
) async {
  if (!isTagBlocked(tag, ref.read(blockedTagIdsProvider))) return false;
  final ok = await showConfirmDialog(
    context,
    title: '「${tag.name}」在黑名单里',
    message: '按它筛选照常生效，只是这一次不套用黑名单里的这一条'
        '（其他被屏蔽的标签仍然生效）。要长期看它，就在标签上右键选「移出黑名单」。',
    okLabel: '仍要查看',
  );
  return ok ? true : null;
}

/// 黑名单管理对话框。
///
/// 两个入口指向同一处（裁决 Q1=甲 / Q3=按建议）：在线页状态行上那个
/// 「已屏蔽 N 个标签」标记，以及设置 → 在线账号页的「标签黑名单」行。
///
/// **刻意不提供「手动输入」**：黑名单要按 `id` 判断「这个标签被屏蔽了吗」
/// （见 [isTagBlocked]），而 id 只有从服务端响应里拿得到；手工敲一个名字进来
/// 会存成 `id = 0`，于是「能过滤、但胶囊不会变灰」，同一份名单里出现两种行为。
/// 所以唯一的添加入口就是标签胶囊的菜单。
Future<void> showOnlineBlacklistDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _BlacklistDialog(),
    );

class _BlacklistDialog extends ConsumerWidget {
  const _BlacklistDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final blocked = ref.watch(settingsProvider).blockedTags;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.block_rounded, size: 17, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('标签黑名单', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.46,
          ),
          child: blocked.isEmpty
              ? _emptyHint(theme)
              : _buildList(context, ref, blocked),
        ),
      ),
      actions: [
        if (blocked.isNotEmpty)
          TextButton(
            onPressed: () => unawaited(_clearAll(context, ref)),
            child: Text(
              '全部清空',
              style: TextStyle(fontSize: 12, color: hikoFavoriteColor),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _emptyHint(ThemeData theme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          '还没有屏蔽任何标签。\n在在线作品的标签上右键（触屏长按）就能加入黑名单。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.8, color: theme.hintColor),
        ),
      );

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<OnlineTag> blocked,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: blocked.length,
            itemBuilder: (context, index) {
              final tag = blocked[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    // 与被屏蔽的卡面标签同一件视觉件：灰 + 删除线，
                    // 让用户在管理页里看到的形态和列表页里的一致
                    HikoTagChip(tag: tag.name, blocked: true),
                    const SizedBox(width: 8),
                    // 显示 id 是为了让「名单里两条同名标签」可辨认，
                    // 也顺带说明这份名单是按 id 结构化的、不是一段文本
                    if (tag.id > 0)
                      Text(
                        '#${tag.id}',
                        style: TextStyle(fontSize: 10, color: theme.hintColor),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: '移出黑名单',
                      onPressed: () => unawaited(
                        ref
                            .read(settingsProvider.notifier)
                            .removeBlockedTag(tag.id),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 15),
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '按标签名在服务端过滤（asmr.one 的搜索语法），所以浏览、搜索、'
          '按标签筛选都不会再出现带这些标签的作品；在线收藏页不受影响。'
          '只作用于在线内容，本地音声库完全不受影响。\n'
          '服务端只回过滤后的总数，所以只能说「屏蔽了几个标签」，'
          '说不出「隐藏了多少件作品」。',
          style: TextStyle(fontSize: 10.5, height: 1.6, color: theme.hintColor),
        ),
      ],
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final count = ref.read(settingsProvider).blockedTags.length;
    final ok = await showConfirmDialog(
      context,
      title: '清空标签黑名单',
      message: '这会把 $count 个被屏蔽的标签全部移出黑名单，它们对应的作品会重新出现在'
          '浏览、搜索与标签筛选结果里。',
      okLabel: '全部清空',
    );
    if (!ok || !context.mounted) return;
    await ref.read(settingsProvider.notifier).clearBlockedTags();
    if (!context.mounted) return;
    await ref.read(onlineBrowseProvider.notifier).reloadAfterUnblock();
    if (context.mounted) showHikoToast(context, '已清空标签黑名单');
  }
}
