import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_platform/universal_platform.dart';

import '../../platform/desktop_window.dart';
import '../m3e/m3e.dart';
import '../../data/backup.dart';
import '../../data/categories_provider.dart';
import '../../data/library_provider.dart';
import '../../data/online/offline_downloads.dart';
import '../../data/online/online_account.dart';
import '../../data/online/online_favorites.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import '../../data/update_checker.dart';
import '../../playback/gain_chain.dart';
import '../../playback/playback_controller.dart';
import '../../platform/platform_service.dart';
import 'seed_image_picker.dart';
import 'online_account_dialogs.dart';
import 'online_appearance.dart';
import 'online_tag_menu.dart';
import 'toast.dart';

/// 设置分类（1.85）：首页分类列表 → 点进二级页；key 对应各 _xxPage 方法
/// 偏好设置页（1.99.32 壳重做，plan §8.7）：5 组 72dp 单页，
/// 桌面独立页路由 / 移动全屏页（入口 home_screen._openSettings）。
/// 1.85~1.99.30 曾是「分类首页 + 二级页」对话框，内容行全部保留摊平。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({
    super.key,
    this.onImportRequested,
    this.onIncrementalScanRequested,
    this.onFullScanRequested,
    this.onReorganizeRequested,
    this.onCleanMissingRequested,
    this.onDownloadUpdateRequested,
    this.autoCheckUpdate = false,
  });

  /// 数据区「导入音声」入口
  final VoidCallback? onImportRequested;

  /// 数据区「增量扫描」（1.99.11）：弹目录选择器，只解析新增/变化文件，不登记常驻目录
  final VoidCallback? onIncrementalScanRequested;

  /// 数据区「全量扫描」（1.99.11）：弹目录选择器，全部重新解析（修复存量封面/标题）
  final VoidCallback? onFullScanRequested;
  final VoidCallback? onReorganizeRequested;
  final VoidCallback? onCleanMissingRequested;
  final ValueChanged<GithubRelease>? onDownloadUpdateRequested;

  /// 打开即自动检查更新（菜单栏「检查更新」发现新版时跳转用）
  final bool autoCheckUpdate;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  double? _gainDrag; // 增益滑动条拖动中的临时值（松手才提交）

  /// 当前子页 id（1.99.58 抽屉化）：null = 索引页，其余见 [_routeTitle]。
  String? _route;

  // ---- 软件更新状态 ----
  String? _appVersion; // PackageInfo 异步加载
  bool _updateChecking = false;
  GithubRelease? _latestRelease; // 检查到的新版本(null=未检查/已是最新)

  @override
  void initState() {
    super.initState();
    _loadVersion();
    if (widget.autoCheckUpdate) {
      // 菜单栏「检查更新」跳进来时直接落在「关于」页：抽屉化之后结果卡片
      // 不再能顺手滑到，必须直达（1.99.58）。
      _route = 'about';
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  /// 检查 GitHub 最新 Release
  Future<void> _checkUpdate() async {
    if (_updateChecking) return;
    setState(() => _updateChecking = true);
    try {
      final current = _appVersion ?? (await PackageInfo.fromPlatform()).version;
      final release = await UpdateChecker.fetchLatestRelease();
      if (!mounted) return;
      if (UpdateChecker.isNewer(current, release.tagName)) {
        setState(() => _latestRelease = release);
      } else {
        setState(() => _latestRelease = null);
        _toast('已是最新版本($current)');
      }
    } catch (e) {
      if (mounted) _toast('检查更新失败:$e');
    } finally {
      if (mounted) setState(() => _updateChecking = false);
    }
  }

  void _toast(String message) => showHikoToast(context, message);

  /// 归一到一位小数并夹在 1.0~上限（macOS 因缺滤镜上限 1.3，Windows 4.0），
  /// 避免 divisions 步进的浮点尾差。
  double _snapGain(double v) =>
      ((v * 10).round() / 10).clamp(1.0, desktopGainCap()).toDouble();

  Future<void> _cleanMissing() async {
    widget.onCleanMissingRequested?.call();
  }

  Future<void> _reorganizeLibrary() async {
    widget.onReorganizeRequested?.call();
  }

  /// 备份导出（1.99.14）：库快照 + 分类 + 设置 → 单 JSON 文件
  Future<void> _exportBackup() async {
    try {
      final backup =
          await HikoBackup.capture(albums: ref.read(libraryProvider));
      final d = backup.createdAt;
      String two(int n) => n.toString().padLeft(2, '0');
      final name =
          'hiko-backup-v1-${d.year}${two(d.month)}${two(d.day)}.json';
      final saved = await ref.read(platformServiceProvider).exportBackup(
            defaultFileName: name,
            content: backup.encode(),
          );
      if (!mounted) return;
      _toast(saved == null
          ? '已取消导出'
          : '备份已导出（${backup.albums.length} 张专辑）');
    } catch (e) {
      if (mounted) _toast('导出失败：$e');
    }
  }

  /// 备份导入（1.99.14）：校验 → 二次确认 → 写回分类/设置/库 → 热重载
  Future<void> _importBackup() async {
    final content = await ref.read(platformServiceProvider).importBackup();
    if (content == null || !mounted) return;

    final HikoBackup backup;
    try {
      backup = HikoBackup.decode(content);
    } on BackupFormatException catch (e) {
      _toast('无法导入：${e.message}');
      return;
    } catch (e) {
      _toast('备份文件损坏或结构不正确');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = M3ETheme.of(ctx);
        return M3EDialog(
          title: '确认导入备份',
          content: Text(
            '备份包含 ${backup.albums.length} 张专辑'
            '（${backup.createdAt.toString().substring(0, 10)} 导出）。\n\n'
            '导入将覆盖当前的全部专辑记录、分类与设置（不删除源文件），'
            '无法撤销。确认继续？',
            style: theme.type.bodyMedium.copyWith(
              color: theme.colors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          actions: <Widget>[
            M3EButton(
              label: '取消',
              variant: M3EButtonVariant.text,
              onPressed: () => Navigator.pop(ctx, false),
            ),
            M3EButton(
              label: '确认导入',
              variant: M3EButtonVariant.destructive,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await backup.restoreToPrefs();
      await ref.read(settingsProvider.notifier).load();
      await ref.read(categoriesProvider.notifier).load();
      await ref.read(libraryProvider.notifier).replaceAll(backup.albums);
      if (!mounted) return;
      _toast('备份已导入（${backup.albums.length} 张专辑）');
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast('导入失败：$e');
    }
  }

  void _startIncrementalScan() {
    widget.onIncrementalScanRequested?.call();
  }

  void _startFullScan() {
    widget.onFullScanRequested?.call();
  }

  Future<void> _pickBackground() async {
    try {
      final path = await pickAndStoreBackgroundImage(
        ref.read(settingsProvider).backgroundPath,
      );
      if (path == null || !mounted) return;
      await ref.read(settingsProvider.notifier).setBackgroundImage(path);
      // 1.99.30：选图即把配色来源切到「自选图片」（plan §9.2）
      await ref.read(settingsProvider.notifier).setSeedSource('custom');
    } catch (e) {
      if (mounted) _toast('选择背景图失败:$e');
    }
  }


  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final route = _route;
    final content = Scaffold(
      // 1.99.33：macOS 红绿灯内缩
      body: Padding(
        padding: EdgeInsets.only(top: windowTopInset(context)),
        child: Column(
          children: [
            M3EAppBar.small(
              leading: M3EIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: route == null ? '返回' : '返回设置',
                onPressed: () {
                  if (route == null) {
                    Navigator.of(context).pop();
                  } else {
                    setState(() => _route = null);
                  }
                },
              ),
              title: Text(route == null ? '设置' : _routeTitle(route)),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: M3EButton(
                    label: '关闭',
                    variant: M3EButtonVariant.text,
                    size: M3EButtonSize.small,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                    children: route == null
                        ? _indexPage(settings)
                        : _routeChildren(route, settings),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // 安卓返回键：在子页先退回索引页，只在索引页才真的退出设置（1.99.58）
    return PopScope(
      canPop: route == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _route = null);
      },
      child: content,
    );
  }

  // ---- 索引页（1.99.58 抽屉化）----

  /// 索引页：4 组 7 个入口 + 1 个直达动作。
  ///
  /// 1.99.32 那版把 9 个二级页摊成一条 55 行的长列表，滑到底才知道有什么；
  /// 这里改回两层 —— 索引页只回答「去哪」，每格带一句范围说明。
  /// 「在线外观」不设独立子页：直接开在线页工具栏那颗 Aa 的同一个对话框
  /// （`showOnlineAppearanceDialog`），同一份设置不维护第二套 UI。
  List<Widget> _indexPage(AppSettings settings) {
    final theme = Theme.of(context);
    return [
      _sectionHeader(theme, '通用', first: true),
      _indexTile(
        icon: Icons.palette_outlined,
        title: '外观与显示',
        subtitle: '主题 · 配色来源 · 强调色 · 对比度 · 动效 · 字号',
        onTap: () => _open('appearance'),
      ),
      _indexTile(
        icon: Icons.graphic_eq_rounded,
        title: '播放与音频',
        subtitle: '默认增益 · 快进/快退秒数',
        onTap: () => _open('audio'),
      ),
      _indexTile(
        icon: Icons.dashboard_outlined,
        title: '主界面',
        subtitle: '每行专辑数 · 刮削标签 · 导航栏配置',
        onTap: () => _open('home'),
      ),
      _sectionHeader(theme, '在线'),
      _indexTile(
        icon: Icons.account_circle_outlined,
        title: '在线账号',
        subtitle: '登录 · 歌单同步 · 服务器 · 缓存',
        onTap: () => _open('online'),
      ),
      _indexTile(
        icon: Icons.text_fields_rounded,
        title: '在线外观',
        subtitle: '字号滑杆 · 每行卡片数 · 每页条数',
        onTap: () => showOnlineAppearanceDialog(context),
      ),
      _sectionHeader(theme, '库'),
      _indexTile(
        icon: Icons.folder_copy_outlined,
        title: '库与扫描',
        subtitle: '音乐目录 · 增量扫描 · 全量扫描',
        onTap: () => _open('library'),
      ),
      _indexTile(
        icon: Icons.storage_rounded,
        title: '数据与维护',
        subtitle: '导入 · 整理 · 清理 · 备份 · 重置 · 代理',
        onTap: () => _open('data'),
      ),
      _sectionHeader(theme, '关于'),
      _indexTile(
        icon: Icons.info_outline_rounded,
        title: '关于',
        subtitle: '版本 · 软件更新',
        onTap: () => _open('about'),
      ),
    ];
  }

  void _open(String route) => setState(() => _route = route);

  String _routeTitle(String route) => switch (route) {
        'appearance' => '外观与显示',
        'audio' => '播放与音频',
        'home' => '主界面',
        'nav' => '导航栏',
        'online' => '在线账号',
        'cache' => '缓存明细',
        'library' => '库与扫描',
        'data' => '数据与维护',
        'about' => '关于',
        _ => '设置',
      };

  /// 子页内容：只换行、不换内容 —— 每页仍是原 `_xxPage` 的那些行。
  List<Widget> _routeChildren(String route, AppSettings settings) {
    final theme = Theme.of(context);
    return switch (route) {
      'appearance' => _appearancePage(theme, settings),
      'audio' => _audioPage(theme, settings),
      'home' => _homePage(theme, settings),
      'nav' => _navPage(theme, settings),
      'online' => _onlineAccountPage(theme, settings),
      'cache' => _cachePage(theme, settings),
      'library' => _foldersPage(theme, settings),
      'data' => _dataPage(theme, settings),
      'about' => _aboutPage(theme, settings),
      _ => _indexPage(settings),
    };
  }

  /// 索引页的一格：72dp 双行 + 图标底 + 右侧箭头（排版交给 M3EListItem）。
  Widget _indexTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: M3EShape.radius(M3EShape.md),
        ),
        child: M3EListItem(
          title: title,
          subtitle: subtitle,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.35),
              borderRadius: M3EShape.radius(M3EShape.sm),
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title, {bool first = false}) =>
      Padding(
        padding: EdgeInsets.fromLTRB(0, first ? 4 : 24, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: M3ETheme.of(context).type.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 1,
              child: ColoredBox(color: theme.colorScheme.outlineVariant),
            ),
          ],
        ),
      );

  // ---- 外观 ----

  List<Widget> _appearancePage(ThemeData theme, AppSettings settings) => [
        _SettingRow(
          label: '主题',
          trailing: M3EButtonGroup(
            labels: const ['浅色', '深色', '跟随系统'],
            selectedIndex: const ['light', 'dark', 'system']
                .indexOf(settings.theme),
            onSelected: (i) => ref
                .read(settingsProvider.notifier)
                .setTheme(const ['light', 'dark', 'system'][i]),
          ),
        ),
        _SettingRow(
          label: '配色来源',
          subtitle: '用哪个颜色/图片生成整套配色',
          trailing: _SettingDropdown<String>(
            value: settings.seedSource,
            items: const [
              ('preset', '预设强调色'),
              ('custom', '自选图片'),
              ('system', '跟随系统'),
            ],
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setSeedSource(v),
          ),
        ),
        _SettingRow(
          label: '强调色',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final accent in AppSettings.accents)
                InkWell(
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setAccent(accent),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: M3EShape.radius(M3EShape.full),
                  child: Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: Color(
                          int.parse('FF${accent.substring(1)}', radix: 16)),
                      shape: BoxShape.circle,
                      border: settings.accent == accent
                          ? Border.all(
                              color: theme.colorScheme.onSurface,
                              width: 2,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _SettingRow(
          label: '对比度',
          subtitle: '提高正文与底色的对比（无障碍）',
          trailing: _SettingDropdown<String>(
            value: settings.contrast,
            items: const [
              ('standard', '标准'),
              ('medium', '中'),
              ('high', '高'),
            ],
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setContrast(v),
          ),
        ),
        _SettingRow(
          label: '动效',
          subtitle: '关闭后动画直达终态（性能与晕动症双保险）',
          trailing: _SettingDropdown<String>(
            value: settings.motionLevel,
            items: const [
              ('full', '完整'),
              ('reduced', '减弱'),
              ('off', '关闭'),
            ],
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setMotionLevel(v),
          ),
        ),
        _SettingRow(
          label: '字号大小',
          trailing: _SettingDropdown<double>(
            value: settings.fontScale,
            items: const [
              (0.85, '小'),
              (1.0, '标准'),
              (1.15, '大'),
              (1.30, '超大'),
            ],
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setFontScale(v),
          ),
        ),
        _SettingRow(
          label: '自选种子图',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.backgroundPath.isEmpty)
                M3EButton(
                  label: '选择图片',
                  variant: M3EButtonVariant.text,
                  size: M3EButtonSize.small,
                  icon: const Icon(Icons.image_outlined),
                  onPressed: _pickBackground,
                )
              else ...[
                ClipRRect(
                  borderRadius: M3EShape.radius(M3EShape.sm),
                  child: Image.file(
                    File(settings.backgroundPath),
                    width: 56,
                    height: 36,
                    fit: BoxFit.cover,
                    cacheWidth: 112,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 56, height: 36),
                  ),
                ),
                const SizedBox(width: 4),
                M3EButton(
                  label: '更换',
                  variant: M3EButtonVariant.text,
                  size: M3EButtonSize.small,
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: _pickBackground,
                ),
                M3EButton(
                  label: '清除',
                  variant: M3EButtonVariant.text,
                  size: M3EButtonSize.small,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    final old = settings.backgroundPath;
                    try {
                      File(old).deleteSync();
                    } catch (_) {}
                    ref
                        .read(settingsProvider.notifier)
                        .setBackgroundImage('');
                  },
                ),
              ],
            ],
          ),
        ),
      ];

  // ---- 音频与增益 ----

  List<Widget> _audioPage(ThemeData theme, AppSettings settings) => [
        _SettingRow(
          label: '默认增益放大',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                child: M3ESlider(
                  min: 1.0,
                  max: desktopGainCap(),
                  divisions: desktopGainCap() > 1.3 ? 30 : 3,
                  value: (_gainDrag ?? settings.audioGain).clamp(
                    1.0,
                    desktopGainCap(),
                  ),
                  label:
                      'x${(_gainDrag ?? settings.audioGain).toStringAsFixed(1)}',
                  onChanged: (v) =>
                      setState(() => _gainDrag = _snapGain(v)),
                  onChangeEnd: (v) {
                    final g = _snapGain(v);
                    setState(() => _gainDrag = null);
                    ref.read(settingsProvider.notifier).setAudioGain(g);
                    ref.read(playbackProvider.notifier).setAudioGain(g);
                  },
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  'x${(_gainDrag ?? settings.audioGain).toStringAsFixed(1)}',
                  textAlign: TextAlign.right,
                  style: context.m3eTheme.type.labelMedium.copyWith(
                    color: (_gainDrag ?? settings.audioGain) > 1.0
                        ? theme.colorScheme.primary
                        : context.m3eTheme.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Builder(builder: (context) {
            final cap = desktopGainCap();
            final isMac = UniversalPlatform.isMacOS;
            return Text(
              isMac
                  ? '此平台（macOS）因底层解码库未随附音量滤镜，增益并入主音量调节（上限 ${cap}x，过高会削波破音）。Windows 版走滤镜链软增益+软限幅，可到 4.0x 不削波。'
                  : '增益在音频滤镜链内以浮点精度放大，并经 -1dB 软限幅器兜底，高增益下不会削波破音。亦可在播放底栏音量图标处快捷调节。',
              style: context.hintText,
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '蓝牙耳机断连/切换后若出现「进度在走但没声音」，播放器检测到输出异常时会自动重接'
            '（1.99.58 起不再提供手动「立即重接」按钮）。',
            style: context.hintText,
          ),
        ),
        _SettingRow(
          label: '快进/快退秒数',
          trailing: _SettingDropdown<double>(
            value: settings.seekStepSeconds,
            items: const [
              (3.0, '3秒'),
              (5.0, '5秒'),
              (10.0, '10秒'),
              (15.0, '15秒'),
              (30.0, '30秒'),
              (60.0, '60秒'),
            ],
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setSeekStep(v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '键盘 ←→ 快退/快进的步长，播放底栏对应按钮同此步长。',
            style: context.hintText,
          ),
        ),
      ];

  // ---- 主界面 ----

  // ---- 导航栏（1.99.4，裁决 Q1=B / Q2=B / Q3=共用 / Q4=A / Q6=B） ----

  List<Widget> _navPage(ThemeData theme, AppSettings settings) {
    final notifier = ref.read(settingsProvider.notifier);
    final navViews = settings.navViews;
    final hidden = [
      for (final view in AppSettings.navViewsAll)
        if (!navViews.contains(view)) view,
    ];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Text(
          '桌面侧栏与安卓底部导航共用此配置：决定显示哪些一级入口及顺序。'
          '「本地音声」是根视图，始终显示；安卓底栏末尾还固定有'
          '「正在播放」（打开全屏播放页）与「设置」两格，不在此表内、无法隐藏；'
          '项较多时底栏可横向滑动。',
          style: context.hintText,
        ),
      ),
      // 显示中的视图：拖动排序 + 开关（根视图开关禁用）
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (oldIndex, newIndex) {
          // onReorderItem 已把 newIndex 调整为「移除旧位后」的插入位置
          final list = [...navViews];
          final view = list.removeAt(oldIndex);
          list.insert(newIndex, view);
          notifier.setNavViews(list);
        },
        children: [
          for (final (i, view) in navViews.indexed)
            Container(
              key: ValueKey('nav-$view'),
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.only(left: 4, right: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: M3EShape.radius(M3EShape.sm),
              ),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 9),
                      child: Icon(Icons.drag_handle_rounded,
                          size: 16, color: context.m3eTheme.colors.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      view,
                      style: context.m3eTheme.type.bodyMedium,
                    ),
                  ),
                  M3ESwitch(
                    value: true,
                    onChanged: view == AppSettings.navViewHome
                        ? null
                        : (v) => notifier.setNavViewVisible(view, v),
                  ),
                ],
              ),
            ),
        ],
      ),
      if (hidden.isNotEmpty) ...[
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Text(
            '已隐藏',
            style: context.m3eTheme.type.labelSmall.copyWith(
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
              color: context.m3eTheme.colors.onSurfaceVariant,
            ),
          ),
        ),
        for (final view in hidden)
          Container(
            key: ValueKey('nav-hidden-$view'),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.only(left: 28, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    view,
                    style: context.m3eTheme.type.bodyMedium.copyWith(
                      color: context.m3eTheme.colors.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
                M3ESwitch(
                  value: false,
                  onChanged: (v) => notifier.setNavViewVisible(view, v),
                ),
              ],
            ),
          ),
      ],
    ];
  }

  List<Widget> _homePage(ThemeData theme, AppSettings settings) => [
        _SettingRow(
          label: '显示刮削标签',
          trailing: M3ESwitch(
            value: settings.showScrapedTags,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .setShowScrapedTags(v),
          ),
        ),
        // 1.54：移动端独立档位 2/3/4（默认 2），与桌面互不影响
        if (Platform.isAndroid)
          _SettingRow(
            label: '每行专辑数',
            trailing: _SettingDropdown<double>(
              value: settings.mobileGridColumns,
              items: const [(2.0, '2'), (3.0, '3'), (4.0, '4')],
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setMobileGridColumns(v),
            ),
          )
        else
          _SettingRow(
            label: '每行专辑数',
            trailing: _SettingDropdown<double>(
              value: settings.gridColumns,
              // 0=自动（按窗口宽度），其余为固定每行数量；1.79 补 2/3 档
              items: const [
                (0.0, '自动'),
                (2.0, '2'),
                (3.0, '3'),
                (4.0, '4'),
                (5.0, '5'),
                (6.0, '6'),
                (7.0, '7'),
                (8.0, '8'),
                (10.0, '10'),
                (12.0, '12'),
              ],
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setGridColumns(v),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            Platform.isAndroid
                ? '移动端网格每行显示的专辑数，与桌面端档位独立。'
                : '「自动」按窗口宽度计算每行数量；固定档位在窗口缩放时保持不变。',
            style: context.hintText,
          ),
        ),
        const SizedBox(height: 8),
        _indexTile(
          icon: Icons.view_sidebar_outlined,
          title: '导航栏',
          subtitle: '拖动排序 · 隐藏不需要的入口',
          onTap: () => _open('nav'),
        ),
      ];

  // ---- 在线账号（1.93.0）----

  /// 在线账号页：登录态 + 歌单同步 + 服务器地址 + 音频缓存。
  ///
  /// 服务器与缓存两项是 1.90 加进来的，原先塞在「数据」页 —— 那时还没有在线分类。
  /// 现在在线的东西都在这一页，分散两处没道理（「数据」页留了一行指引）。
  List<Widget> _onlineAccountPage(ThemeData theme, AppSettings settings) {
    final account = ref.watch(onlineAccountProvider);
    final favorites = ref.watch(onlineFavoritesProvider);
    final index = favorites.index;

    return [
      _SettingRow(
        label: '登录状态',
        trailing: switch (account) {
          _ when account.restoring =>
            Text('检查中…', style: context.hintText),
          _ when account.loggedIn => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: M3ESemantic.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  account.displayName,
                  style: context.m3eTheme.type.labelMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          _ => Text(
              '未登录',
              style: context.hintText,
            ),
        },
      ),
      if (account.loggedIn) ...[
        _SettingRow(
          label: '我的歌单',
          trailing: Text(
            favorites.loading && index.playlists.isEmpty
                ? '同步中…'
                : '${index.playlists.length} 个 · ${index.countOf(null)} 个作品',
            style: context.m3eTheme.type.labelSmall,
          ),
        ),
        _SettingRow(
          label: '收藏同步',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                favorites.error ?? '与网页版共用同一份歌单',
                style: M3ETheme.of(context).type.bodySmall.copyWith(
                      color: favorites.error == null
                          ? M3ETheme.of(context).colors.onSurfaceVariant
                          : M3ETheme.of(context).colors.error,
                    ),
              ),
              const SizedBox(width: 8),
              M3EButton(
                label: '刷新',
                variant: M3EButtonVariant.outlined,
                size: M3EButtonSize.small,
                onPressed: favorites.loading
                    ? null
                    : () async {
                        await ref.read(onlineFavoritesProvider.notifier).refresh();
                        if (mounted) {
                          _toast(
                            ref.read(onlineFavoritesProvider).error == null
                                ? '收藏已刷新'
                                : '刷新失败，请检查网络',
                          );
                        }
                      },
              ),
            ],
          ),
        ),
        _SettingRow(
          label: '登录令牌',
          trailing: M3EButton(
            label: '退出登录',
            variant: M3EButtonVariant.outlined,
            size: M3EButtonSize.small,
            onPressed: () async {
              await ref.read(onlineAccountProvider.notifier).logout();
              if (mounted) _toast('已退出登录');
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Hiko 只保存 asmr.one 的登录令牌（有效期 30 天，服务端没有续期接口，'
            '过期后重新登录即可），不保存密码，也不会上传任何本地音声库信息。',
            style: context.hintText,
          ),
        ),
      ] else ...[
        _SettingRow(
          label: '登录',
          trailing: M3EButton(
            label: '登录 asmr.one',
            size: M3EButtonSize.small,
            onPressed: account.restoring
                ? null
                : () => unawaited(showOnlineLoginDialog(context)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '登录后才能收藏作品、管理歌单。收藏走 asmr.one 的歌单体系，'
            '所以可以建「未听」「已听」这类歌单来记录收听状态。'
            '没有账号的话去 www.asmr.one 注册（Hiko 不提供注册）。',
            style: context.hintText,
          ),
        ),
      ],
      // 1.94.0：纯显示项，与登录无关，所以放在账号区之后、服务器/缓存之前
      _SettingRow(
        label: '卡片显示标签',
        subtitle: '在作品卡片上直接显示标签，点击可按该标签筛选',
        trailing: M3ESwitch(
          value: settings.showOnlineTags,
          onChanged: (v) =>
              ref.read(settingsProvider.notifier).setShowOnlineTags(v),
        ),
      ),
      // 1.95.0：黑名单的第二个入口（第一个是在线页状态行上那个可点标记）。
      // 添加入口**只在标签胶囊的菜单里** —— 黑名单按 id 判定，手工敲名字只会
      // 存进一条 id=0 的记录，变成「能过滤但胶囊不变灰」，所以这里只做管理。
      _SettingRow(
        label: '标签黑名单',
        subtitle: '被屏蔽的标签不会出现在在线浏览、搜索与标签筛选结果里；'
            '只作用于在线内容，本地音声库不受影响',
        trailing: M3EButton(
          label: settings.blockedTags.isEmpty
              ? '管理'
              : '管理（${settings.blockedTags.length}）',
          variant: M3EButtonVariant.outlined,
          size: M3EButtonSize.small,
          onPressed: () => unawaited(showOnlineBlacklistDialog(context)),
        ),
      ),
      _SettingRow(
        label: '在线服务器',
        trailing: SizedBox(
          width: 220,
          child: TextField(
            controller: TextEditingController(text: settings.onlineServer),
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setOnlineServer(v),
            decoration: InputDecoration(
              hintText: 'api.asmr.one',
              hintStyle: context.hintText,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: M3EShape.radius(M3EShape.sm),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: M3EShape.radius(M3EShape.sm),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
            ),
            style: context.m3eTheme.type.labelSmall,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '在线音声服务地址（Kikoeru 兼容协议）。默认 asmr.one 官方实例，也可填写自建服务器地址；'
          '留空回退默认。在线浏览与播放无需登录；账号与歌单是 asmr.one 的私有能力，'
          '自建 Kikoeru 服务器上不可用。直连不通时请到「数据」页配置代理。',
          style: context.hintText,
        ),
      ),
      _SettingRow(
        label: '在线缓存上限',
        trailing: M3ESelect<double>(
          value: settings.onlineCacheLimitGb,
          options: [
            for (final gb in SettingsNotifier.onlineCacheLimitOptions)
              M3ESelectOption<double>(
                gb,
                gb == 0.0 ? '关闭（不缓存）' : _formatGb(gb),
              ),
          ],
          onChanged: (v) =>
              ref.read(settingsProvider.notifier).setOnlineCacheLimit(v),
        ),
      ),
      _indexTile(
        icon: Icons.cleaning_services_outlined,
        title: '缓存明细',
        subtitle: '占用统计 · 按作品清理',
        onTap: () => _open('cache'),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '在线播放在超过 20 秒后才开始后台缓存整首音频到本地，超出上限按最久未播放淘汰；'
          '占用统计与按作品清理在「缓存明细」里。',
          style: context.hintText,
        ),
      ),
    ];
  }

  /// 缓存明细（1.99.58）：原来塞在「在线账号」页里的两块统计挪出来单独成页 ——
  /// 日常调设置不看它，真要清缓存的时候才进来。
  List<Widget> _cachePage(ThemeData theme, AppSettings settings) => [
        _SettingRow(
          label: '在线缓存占用',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<int>(
                future: ref.read(onlineAudioCacheProvider).totalBytes(),
                builder: (context, snap) {
                  final bytes = snap.data;
                  return Text(
                    bytes == null ? '统计中…' : _formatBytes(bytes),
                    style: context.hintText,
                  );
                },
              ),
              const SizedBox(width: 8),
              M3EButton(
                label: '清理',
                variant: M3EButtonVariant.outlined,
                size: M3EButtonSize.small,
                onPressed: () async {
                  await ref.read(onlineAudioCacheProvider).clear();
                  if (mounted) setState(() {});
                  _toast('在线缓存已清空');
                },
              ),
            ],
          ),
        ),
        // 按作品清理（1.99.3）：LRU 静默淘汰用户无感，列出「谁占了多少」
        // 并允许单独删除。RJ 段 id 展示成 RJ 号便于对上作品；
        // 1000000xx 段是 BJ/VJ 等非 RJ 作品，退回 #id 展示。
        FutureBuilder<Map<int, int>>(
          future: ref.read(onlineAudioCacheProvider).bytesByWork(),
          builder: (context, snap) {
            final entries = (snap.data ?? const <int, int>{}).entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            if (entries.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '按作品清理',
                      style: context.hintText,
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: M3EShape.radius(M3EShape.sm),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final id = entry.key;
                        final label =
                            (id >= 10000000 && id < 100000000)
                                ? 'RJ${id.toString().padLeft(8, '0')}'
                                : '#$id';
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(label,
                              style: context.m3eTheme.type.bodyMedium),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatBytes(entry.value),
                                style: context.hintText,
                              ),
                              M3EIconButton(
                                tooltip: '清理该作品缓存',
                                icon: Icons.close_rounded,
                                size: M3EIconButtonSize.small,
                                onPressed: () async {
                                  await ref
                                      .read(onlineAudioCacheProvider)
                                      .removeWork(id);
                                  // 该作品若已离线，同步移除离线索引（1.99.16 一致性）
                                  await ref
                                      .read(offlineIndexListProvider.notifier)
                                      .remove(id);
                                  if (mounted) setState(() {});
                                  _toast('已清理 $label 的缓存');
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '在线播放在超过 20 秒后才开始后台缓存整首音频到本地（避免点开即退白耗流量），'
            '超出上限时按最久未播放淘汰。缓存独立存放，不写入本地音声库。',
            style: context.hintText,
          ),
        ),
      ];

  // ---- 数据 ----

  List<Widget> _dataPage(ThemeData theme, AppSettings settings) => [
        _SettingRow(
          label: '导入音声',
          trailing: _ActionButton(
            label: '导入文件夹',
            onTap: () => widget.onImportRequested?.call(),
          ),
        ),
        _SettingRow(
          label: '整理当前专辑',
          trailing: _ActionButton(
            label: '整理专辑元数据',
            onTap: _reorganizeLibrary,
          ),
        ),
        _SettingRow(
          label: '失效记录',
          trailing: _ActionButton(label: '清理失效记录', onTap: _cleanMissing),
        ),
        _SettingRow(
          label: '备份导出',
          trailing: _ActionButton(label: '导出备份文件', onTap: _exportBackup),
        ),
        _SettingRow(
          label: '备份导入',
          trailing: _ActionButton(label: '选择备份文件', onTap: _importBackup),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '备份包含全部专辑（收藏/评分/进度/刮削）、分类与设置；不含登录令牌、封面与本机路径。'
            '导入会覆盖当前库与设置，本地源文件路径失效时可用「清理失效记录」清理。',
            style: context.hintText,
          ),
        ),
        _SettingRow(
          label: '库文件位置',
          trailing: _ActionButton(
            label: '打开数据目录',
            onTap: () => ref.read(platformServiceProvider).openDataDir(),
          ),
        ),
        // 1.79 起全平台开放：重置数据库（清空所有专辑，不删除源文件）
        _SettingRow(
          label: '重置数据库',
          trailing: _ActionButton(
            label: '清空全部专辑',
            onTap: () async {
              // 二次确认对话框
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) {
                  final dialogTheme = M3ETheme.of(ctx);
                  return M3EDialog(
                    title: '确认重置数据库',
                    content: Text(
                      '将清空所有专辑记录，但不会删除源文件。\n'
                      '您的设置（主题、增益、音乐目录）将保留。\n\n'
                      '清空后需重新导入文件夹恢复专辑。\n\n'
                      '此操作无法撤销，确认继续？',
                      style: dialogTheme.type.bodyMedium.copyWith(
                        color: dialogTheme.colors.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    actions: <Widget>[
                      M3EButton(
                        label: '取消',
                        variant: M3EButtonVariant.text,
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                      M3EButton(
                        label: '确认清空',
                        variant: M3EButtonVariant.destructive,
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ],
                  );
                },
              );

              if (confirmed == true) {
                await ref.read(libraryProvider.notifier).clearAll();
                if (mounted) {
                  _toast('数据库已重置，请重新导入文件夹');
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
          ),
        ),
        _SettingRow(
          label: '刮削代理',
          trailing: SizedBox(
            width: 220,
            child: TextField(
              controller: TextEditingController(
                text: settings.scrapeProxy,
              ),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setScrapeProxy(v.trim()),
              decoration: InputDecoration(
                hintText: '留空使用系统代理',
                hintStyle: context.hintText,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: M3EShape.radius(M3EShape.sm),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: M3EShape.radius(M3EShape.sm),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
              style: context.m3eTheme.type.labelSmall,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '刮削代理用于访问 DLsite 元数据与封面，留空走系统代理。',
            style: context.hintText,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '在线音声服务地址与缓存设置已移到「在线账号」页（1.93.0 起在线相关设置集中在那里）。',
            style: context.hintText,
          ),
        ),
      ];

  /// 缓存上限展示：`0.5 GB` / `5 GB`
  static String _formatGb(double gb) =>
      gb == gb.roundToDouble() ? '${gb.toInt()} GB' : '$gb GB';

  /// 占用展示：`512 MB` / `1.2 GB`
  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mb = 1024 * 1024;
    const gb = 1024 * mb;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }

  // ---- 音乐目录 ----

  List<Widget> _foldersPage(ThemeData theme, AppSettings settings) => [
        if (settings.musicFolders.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '尚未设置音乐目录。导入音声文件夹时会自动记住；之后每次启动自动扫描新增内容。',
              style: context.hintText,
            ),
          ),
        for (final folder in settings.musicFolders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 15,
                  color: context.m3eTheme.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _displayFolder(folder),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.m3eTheme.type.labelSmall,
                  ),
                ),
                M3EIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '移除目录',
                  size: M3EIconButtonSize.small,
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .removeMusicFolder(folder),
                ),
              ],
            ),
          ),
        Row(
          children: [
            _ActionButton(label: '增量扫描', onTap: _startIncrementalScan),
            const SizedBox(width: 8),
            _ActionButton(label: '全量扫描', onTap: _startFullScan),
            if (settings.musicFolders.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '共 ${settings.musicFolders.length} 个常驻目录',
                style: context.hintText,
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '增量扫描只解析选中目录里新增/变化的文件；全量扫描重建全部元数据。'
              '两者不登记常驻目录，启动静默扫描仅覆盖「导入文件夹」登记的目录。',
              style: context.hintText,
          ),
        ),
      ];

  // ---- 关于 ----

  List<Widget> _aboutPage(ThemeData theme, AppSettings settings) => [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: M3EShape.radius(M3EShape.md),
              ),
              child: Center(
                child: Text(
                  'K',
                  style: context.m3eTheme.type.titleLarge.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hiko · 音声收藏室',
                    style: context.m3eTheme.type.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '版本 ${_appVersion ?? '…'} · 本地优先的音声库管理器',
                    style: context.hintText,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 软件更新(两端):检查 GitHub 最新 Release → 一键下载安装
        if (_latestRelease == null)
          _SettingRow(
            label: '软件更新',
            trailing: _ActionButton(
              label: _updateChecking ? '检查中...' : '检查更新',
              loading: _updateChecking,
              onTap: _updateChecking ? null : _checkUpdate,
            ),
          ),
        if (_latestRelease != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(
                alpha: 0.35,
              ),
              borderRadius: M3EShape.radius(M3EShape.sm),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.system_update_alt_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '发现新版本 ${_latestRelease!.tagName}',
                      style: context.m3eTheme.type.labelMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                if (_latestRelease!.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 110),
                    child: SingleChildScrollView(
                      child: Text(
                        _latestRelease!.body.trim(),
                        style: context.hintText,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ActionButton(
                      label: Platform.isAndroid ? '下载并安装' : '下载更新包',
                      onTap: () {
                        final release = _latestRelease;
                        if (release == null) return;
                        Navigator.pop(context);
                        widget.onDownloadUpdateRequested?.call(release);
                      },
                    ),
                    const SizedBox(width: 8),
                    M3EButton(
                      label: '暂不更新',
                      variant: M3EButtonVariant.text,
                      size: M3EButtonSize.small,
                      onPressed: () =>
                          setState(() => _latestRelease = null),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ];
}

/// 档位下拉选择（1.85）：替代原横排 chip 组，三端交互一致
class _SettingDropdown<T> extends StatelessWidget {
  const _SettingDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> items; // (值, 显示名)
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return M3ESelect<T>(
      value: value,
      options: [
        for (final (v, label) in items) M3ESelectOption<T>(v, label),
      ],
      onChanged: onChanged,
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.trailing,
    this.subtitle,
  });

  final String label;
  final Widget trailing;

  /// 可选的一行小字说明（1.94.0 起用）。放在标签下方，字号比标签小一档
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    // 1.99.32（plan §8.7）：项 72dp 双行，行内垂直居中
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.type.bodyLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.type.bodySmall.copyWith(
                      color: theme.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return M3EButton(
      label: loading ? '处理中…' : label,
      variant: M3EButtonVariant.outlined,
      size: M3EButtonSize.small,
      onPressed: loading ? null : onTap,
    );
  }
}

/// 音乐目录展示名：SAF tree URI 取最后一段，路径取文件名
String _displayFolder(String folder) {
  if (folder.startsWith('content://')) {
    final idx = folder.lastIndexOf('%2F');
    if (idx >= 0) {
      return Uri.decodeComponent(folder.substring(idx + 3));
    }
    return folder;
  }
  final parts = folder.split(RegExp(r'[/\\]'));
  return parts.where((p) => p.isNotEmpty).lastOrNull ?? folder;
}

/// 设置页的统一文案（1.99.43）。
///
/// 说明文字此前全是手写的 `fontSize: 10/10.5/11 + 旧主题中性灰`，
/// 同一页出现 5 档字号与 3 种灰度。这里收成一个入口：`bodySmall` +
/// `onSurfaceVariant`；行标题与分组标题分别在 `_SettingRow` / `_sectionHeader`。
extension _SettingsTypography on BuildContext {
  M3EThemeData get m3eTheme => M3ETheme.of(this);

  TextStyle get hintText => m3eTheme.type.bodySmall.copyWith(
        color: m3eTheme.colors.onSurfaceVariant,
      );
}
