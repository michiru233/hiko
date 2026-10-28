import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/online/kikoeru_client.dart';
import '../../data/online/online_account.dart';
import '../../data/online/online_favorites.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import 'confirm_dialog.dart';
import '../m3e/m3e.dart';
import 'toast.dart';

/// asmr.one 网页版（注册只能去这里 —— 裁决 Q11=A：Hiko 不做注册）
const _asmrSite = 'https://www.asmr.one';

// ------------------------------------------------------------------ 登录

/// 登录对话框。返回 true 表示这次登录成功了。
Future<bool> showOnlineLoginDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _LoginDialog(),
  );
  return ok ?? false;
}

class _LoginDialog extends ConsumerStatefulWidget {
  const _LoginDialog();

  @override
  ConsumerState<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends ConsumerState<_LoginDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref.read(onlineAccountProvider.notifier).login(
          name: _name.text,
          password: _password.text,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return M3EDialog(
      maxWidth: 420,
      title: '登录 asmr.one',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(
              '登录后才能收藏作品、管理歌单。Hiko 只保存登录令牌（有效期 30 天），'
              '不会上传任何本地数据。',
              style: theme.type.bodySmall.copyWith(
                height: 1.6,
                color: theme.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '用户名',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: M3ETheme.of(context).type.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              onSubmitted: (_) => unawaited(_submit()),
              decoration: const InputDecoration(
                labelText: '密码',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: M3ETheme.of(context).type.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.type.bodySmall.copyWith(color: theme.colors.error),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: M3EButton(
                label: '还没有账号？去官网注册 →',
                variant: M3EButtonVariant.text,
                size: M3EButtonSize.small,
                onPressed: () => unawaited(
                  launchUrl(
                    Uri.parse(_asmrSite),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        M3EButton(
          label: '取消',
          variant: M3EButtonVariant.text,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        M3EButton(
          label: _busy ? '登录中…' : '登录',
          onPressed: _busy ? null : () => unawaited(_submit()),
        ),
      ],
    );
  }
}

/// 需要登录才能做的事的统一引导（裁决 Q5=A：未登录置灰 + 引导登录）
Future<void> showLoginRequiredDialog(
  BuildContext context, {
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = M3ETheme.of(dialogContext);
      return M3EDialog(
        maxWidth: 420,
        title: '需要登录',
        content: Text(
          '$action需要 asmr.one 账号。登录后收藏会同步到你的网页版账号，'
          '在手机、网页上打开都是同一份收藏。',
          style: theme.type.bodyMedium.copyWith(
            height: 1.7,
            color: theme.colors.onSurfaceVariant,
          ),
        ),
        actions: <Widget>[
          M3EButton(
            label: '暂不',
            variant: M3EButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          M3EButton(
            label: '去登录',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      );
    },
  );
  if (ok == true && context.mounted) {
    await showOnlineLoginDialog(context);
  }
}

// ------------------------------------------------------------------ 收藏到歌单

/// 多选歌单菜单（裁决 Q8=B）：勾选若干歌单 → 确认 → **只对差集发请求**。
///
/// 打开时先用本地索引立即出画面（不白屏），同时向服务端补一次权威值修正勾选 ——
/// 索引可能是几分钟前拉的，网页端期间的改动不该被这次操作覆盖掉。
Future<void> showPlaylistPicker(
  BuildContext context, {
  required OnlineWork work,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _PlaylistPickerDialog(work: work),
  );
}

class _PlaylistPickerDialog extends ConsumerStatefulWidget {
  const _PlaylistPickerDialog({required this.work});

  final OnlineWork work;

  @override
  ConsumerState<_PlaylistPickerDialog> createState() =>
      _PlaylistPickerDialogState();
}

class _PlaylistPickerDialogState extends ConsumerState<_PlaylistPickerDialog> {
  /// 打开时的勾选（差分基准）
  late Set<String> _origin;
  /// 当前勾选
  late Set<String> _selected;
  late List<OnlinePlaylist> _playlists;

  bool _loading = true;
  bool _busy = false;

  /// 用户是否已经动过勾选。
  ///
  /// 权威勾选是异步回来的：用户在等待期间取消了一个勾，回来的快照不能把它盖回去 ——
  /// 否则「取消」这个动作会被静默吞掉，而确认时按新快照算出的是**空差分**，
  /// 表现就是「点了确定什么都没发生」。
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    final index = ref.read(onlineFavoritesProvider).index;
    _playlists = [...index.playlists];
    _origin = {...index.playlistsOf(widget.work.id)};
    _selected = {..._origin};
    unawaited(_loadAuthoritative());
  }

  /// 服务端的权威勾选（`get-work-exist-status-in-my-playlists` 带 `exist`）
  Future<void> _loadAuthoritative() async {
    try {
      final client = ref.read(onlineClientProvider);
      final list = await client.fetchWorkPlaylistStatus(widget.work.id);
      if (!mounted) return;
      if (list.isEmpty) {
        // 一个歌单都没有：不该发生（至少系统歌单在），保守地保留本地值
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _playlists = list;
        _origin = {
          for (final p in list)
            if (p.exist == true) p.id,
        };
        if (!_touched) _selected = {..._origin};
        _loading = false;
      });
    } on KikoeruException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.isUnauthorized) {
        await ref.read(onlineAccountProvider.notifier).handleUnauthorized();
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      // 网络抖动：退回本地索引的勾选，用户照样能改
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createPlaylist() async {
    final name = await showPlaylistNameDialog(context);
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final client = ref.read(onlineClientProvider);
      // 刻意建**空歌单**：勾选交给主对话框的「确认」统一处理，
      // 这样用户在确认前取消，不会顺手把作品塞进新歌单。
      final created = await client.createPlaylist(name: name);
      if (!mounted) return;
      ref.read(onlineFavoritesProvider.notifier).addPlaylist(created);
      setState(() {
        _touched = true; // 新建后就地勾上，别被稍后回来的旧快照抹掉
        _playlists = [..._playlists, created];
        _selected.add(created.id);
        _busy = false;
      });
      showHikoToast(context, '已创建歌单「${created.displayName}」');
    } on KikoeruException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showHikoToast(context, '新建失败：${e.message}');
    }
  }

  Future<void> _confirm() async {
    final diff = planPlaylistDiff(current: _origin, desired: _selected);
    if (diff.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    final client = ref.read(onlineClientProvider);
    final workId = widget.work.id;
    try {
      for (final playlistId in diff.addTo) {
        await client.addWorksToPlaylist(playlistId, [workId]);
      }
      for (final playlistId in diff.removeFrom) {
        await client.removeWorksFromPlaylist(playlistId, [workId]);
      }
      if (!mounted) return;
      // 即时反馈 + 后台校准（顺带修正 works_count 与排序）
      ref
          .read(onlineFavoritesProvider.notifier)
          .applyLocal(work: widget.work, diff: diff);
      Navigator.of(context).pop();
    } on KikoeruException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.isUnauthorized) {
        await ref.read(onlineAccountProvider.notifier).handleUnauthorized();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      showHikoToast(context, '保存失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showHikoToast(context, '保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return M3EDialog(
      maxWidth: 460,
      title: '收藏到歌单',
      // 副标题（作品名）挂在正文第一行，标题只留动作名
      scrollable: false,
      contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Text(
                  widget.work.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.type.bodySmall.copyWith(
                    color: theme.colors.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                height: 2,
                child: _loading ? const M3EProgress.thin() : null,
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_playlists.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 8),
                          child: Text(
                            '还没有歌单，先新建一个吧',
                            style: theme.type.bodySmall.copyWith(
                              color: theme.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      for (final playlist in _playlists)
                        _PlaylistCheckRow(
                          playlist: playlist,
                          checked: _selected.contains(playlist.id),
                          enabled: !_busy,
                          onChanged: (value) => setState(() {
                            _touched = true;
                            if (value) {
                              _selected.add(playlist.id);
                            } else {
                              _selected.remove(playlist.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              M3EMenuDivider(),
              M3EListItem(
                title: '新建歌单',
                subtitle: '默认私享',
                leading: Icon(
                  Icons.add_rounded,
                  color: theme.colors.primary,
                ),
                enabled: !_busy,
                onTap: () => unawaited(_createPlaylist()),
              ),
          ],
        ),
      actions: <Widget>[
        M3EButton(
          label: '取消',
          variant: M3EButtonVariant.text,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        M3EButton(
          label: _busy ? '保存中…' : '确定',
          onPressed: _busy ? null : () => unawaited(_confirm()),
        ),
      ],
    );
  }
}

class _PlaylistCheckRow extends StatelessWidget {
  const _PlaylistCheckRow({
    required this.playlist,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  final OnlinePlaylist playlist;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    return M3EListItem(
      title: playlist.displayName,
      // 作品数原来挤在行尾；M3E 列表用副标题承载这类计数
      subtitle: '${playlist.worksCount} 个作品',
      selected: checked,
      enabled: enabled,
      leading: Icon(
        checked ? Icons.check_box_rounded : Icons.check_box_outline_blank,
        size: 20,
        color: checked
            ? theme.colors.primary
            : theme.colors.onSurfaceVariant,
      ),
      trailing: playlist.isSystem
          ? Tooltip(
              message:
                  playlist.isLiked ? '系统歌单（网页版爱心收藏落在里）' : '系统歌单',
              child: Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: theme.colors.onSurfaceVariant,
              ),
            )
          : null,
      onTap: enabled ? () => onChanged(!checked) : null,
    );
  }
}

// ------------------------------------------------------------------ 歌单名

/// 新建 / 改名共用的单行输入框。返回去空白后的名字，取消返回 null。
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  String? initial,
  String title = '新建歌单',
}) async {
  final controller = TextEditingController(text: initial ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final theme = M3ETheme.of(dialogContext);
      void submit() {
        final name = controller.text.trim();
        if (name.isEmpty) return;
        Navigator.of(dialogContext).pop(name);
      }

      return M3EDialog(
        maxWidth: 420,
        title: title,
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 40,
                onSubmitted: (_) => submit(),
                decoration: const InputDecoration(
                  labelText: '歌单名',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: M3ETheme.of(context).type.bodySmall,
              ),
              Text(
                '新建的歌单默认「私享」，只有你自己看得到。',
                style: theme.type.bodySmall.copyWith(
                  height: 1.5,
                  color: theme.colors.onSurfaceVariant,
                ),
              ),
            ],
        ),
        actions: <Widget>[
          M3EButton(
            label: '取消',
            variant: M3EButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          M3EButton(label: '确定', onPressed: submit),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

// ------------------------------------------------------------------ 歌单管理

/// 歌单的重命名 / 删除（裁决 Q13=A）。系统保留歌单没有这两个入口。
///
/// 返回 true 表示列表需要重画（调用方据此刷新）。
Future<bool> renamePlaylistFlow(
  BuildContext context,
  WidgetRef ref,
  OnlinePlaylist playlist,
) async {
  final name = await showPlaylistNameDialog(
    context,
    initial: playlist.name,
    title: '重命名歌单',
  );
  if (name == null || name == playlist.name) return false;
  try {
    await ref.read(onlineClientProvider).editPlaylistMetadata(
          playlist.id,
          name: name,
        );
    ref.read(onlineFavoritesProvider.notifier).renamePlaylist(playlist.id, name);
    return true;
  } on KikoeruException catch (e) {
    if (e.isUnauthorized) {
      await ref.read(onlineAccountProvider.notifier).handleUnauthorized();
    }
    if (context.mounted) showHikoToast(context, '重命名失败：${e.message}');
    return false;
  }
}

Future<bool> deletePlaylistFlow(
  BuildContext context,
  WidgetRef ref,
  OnlinePlaylist playlist,
) async {
  final ok = await showConfirmDialog(
    context,
    title: '删除歌单「${playlist.displayName}」',
    message: '歌单里的 ${playlist.worksCount} 个作品**不会被删除**，'
        '只是不再属于这个歌单（其他歌单里的记录也不受影响）。确定删除吗？',
    okLabel: '删除歌单',
  );
  if (!ok) return false;
  try {
    await ref.read(onlineClientProvider).deletePlaylist(playlist.id);
    ref.read(onlineFavoritesProvider.notifier).removePlaylist(playlist.id);
    if (context.mounted) {
      showHikoToast(context, '已删除歌单「${playlist.displayName}」');
    }
    return true;
  } on KikoeruException catch (e) {
    if (e.isUnauthorized) {
      await ref.read(onlineAccountProvider.notifier).handleUnauthorized();
    }
    if (context.mounted) showHikoToast(context, '删除失败：${e.message}');
    return false;
  }
}
