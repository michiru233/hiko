import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:universal_platform/universal_platform.dart';

import '../../data/library_provider.dart';
import '../../data/online/online_account.dart';
import '../../data/online/online_favorites.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import '../../data/update_checker.dart';
import '../../playback/gain_chain.dart';
import '../../playback/playback_controller.dart';
import '../../platform/platform_service.dart';
import '../background.dart';
import 'online_account_dialogs.dart';
import 'online_appearance.dart';
import 'online_tag_menu.dart';
import 'toast.dart';

/// 设置分类（1.85）：首页分类列表 → 点进二级页；key 对应各 _xxPage 方法
class _SettingsCategory {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;

  const _SettingsCategory(this.key, this.title, this.subtitle, this.icon);
}

const _categories = [
  _SettingsCategory('appearance', '外观', '主题 · 强调色 · 字号 · 背景图',
      Icons.palette_outlined),
  _SettingsCategory('audio', '音频与增益', '增益放大 · 输出重接 · 快进快退',
      Icons.graphic_eq_rounded),
  _SettingsCategory('home', '主界面', '刮削标签 · 每行专辑数',
      Icons.grid_view_outlined),
  // 1.93.0：在线相关设置从「数据」页集中到这里
  _SettingsCategory('online', '在线账号',
      '登录 asmr.one · 歌单收藏 · 卡片标签 · 黑名单 · 服务器 · 缓存',
      Icons.person_outline_rounded),
  // 1.96.0：外观类设置单开一页 —— 它只影响在线界面，塞进「外观」页
  // （那里管的是全局主题/字号/背景）会让「改这里到底影响谁」变得含糊
  _SettingsCategory('onlineAppearance', '在线外观',
      '标签字号 · 卡片与详情文字 · 曲目标题 · 列数 · 每页条数',
      Icons.text_fields_rounded),
  _SettingsCategory('data', '数据', '导入 · 整理 · 失效清理 · 刮削代理',
      Icons.storage_outlined),
  _SettingsCategory('folders', '音乐目录', '常驻目录 · 自动扫描',
      Icons.folder_outlined),
  _SettingsCategory('about', '关于', '版本信息 · 软件更新', Icons.info_outline),
];

/// 偏好设置弹窗（对应旧版 settings-overlay）
/// 1.85 起分类导航：首页列出全部分类，点进二级页（三端统一 drill-in）
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({
    super.key,
    this.onImportRequested,
    this.onRescanRequested,
    this.onReorganizeRequested,
    this.onCleanMissingRequested,
    this.onDownloadUpdateRequested,
    this.autoCheckUpdate = false,
  });

  /// 数据区「导入音声」入口
  final VoidCallback? onImportRequested;
  final VoidCallback? onRescanRequested;
  final VoidCallback? onReorganizeRequested;
  final VoidCallback? onCleanMissingRequested;
  final ValueChanged<GithubRelease>? onDownloadUpdateRequested;

  /// 打开即自动检查更新（菜单栏「检查更新」发现新版时跳转用）
  final bool autoCheckUpdate;

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  double? _gainDrag; // 增益滑动条拖动中的临时值（松手才提交）
  double? _bgBlurDrag; // 背景模糊度拖动中的临时值（松手才提交）
  double? _bgOpacityDrag; // 背景不透明度拖动中的临时值（松手才提交）
  String? _category; // 当前所在分类 key；null = 分类首页

  // ---- 软件更新状态 ----
  String? _appVersion; // PackageInfo 异步加载
  bool _updateChecking = false;
  GithubRelease? _latestRelease; // 检查到的新版本(null=未检查/已是最新)

  @override
  void initState() {
    super.initState();
    _loadVersion();
    if (widget.autoCheckUpdate) {
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

  void _startRescan() {
    widget.onRescanRequested?.call();
  }

  Future<void> _pickBackground() async {
    try {
      final path = await pickAndStoreBackgroundImage(
        ref.read(settingsProvider).backgroundPath,
      );
      if (path == null || !mounted) return;
      ref.read(settingsProvider.notifier).setBackgroundImage(path);
    } catch (e) {
      if (mounted) _toast('选择背景图失败:$e');
    }
  }

  void _openCategory(String key) => setState(() => _category = key);
  void _backToCategories() => setState(() => _category = null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _category == null
                ? _categoryListPage(theme)
                : _categoryPage(theme, settings),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '关闭',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  // ---- 分类首页 ----

  List<Widget> _categoryListPage(ThemeData theme) => [
        const SizedBox(height: 8),
        for (final cat in _categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: () => _openCategory(cat.key),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Icon(cat.icon, size: 18, color: theme.hintColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cat.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cat.subtitle,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: theme.hintColor),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ];

  List<Widget> _categoryPage(ThemeData theme, AppSettings settings) {
    switch (_category!) {
      case 'appearance':
        return _appearancePage(theme, settings);
      case 'audio':
        return _audioPage(theme, settings);
      case 'home':
        return _homePage(theme, settings);
      case 'online':
        return _onlineAccountPage(theme, settings);
      case 'onlineAppearance':
        return _onlineAppearancePage(theme, settings);
      case 'data':
        return _dataPage(theme, settings);
      case 'folders':
        return _foldersPage(theme, settings);
      case 'about':
        return _aboutPage(theme, settings);
    }
    return _categoryListPage(theme);
  }

  // ---- 二级页公共头 ----

  Widget _pageHeader(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 18),
              tooltip: '返回',
              visualDensity: VisualDensity.compact,
              onPressed: _backToCategories,
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  // ---- 外观 ----

  List<Widget> _appearancePage(ThemeData theme, AppSettings settings) => [
        _pageHeader(theme, '外观'),
        _SettingRow(
          label: '主题',
          trailing: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.6,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (key, label) in [
                  ('light', '浅色'),
                  ('dark', '深色'),
                ])
                  InkWell(
                    onTap: () =>
                        ref.read(settingsProvider.notifier).setTheme(key),
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: settings.theme == key
                            ? theme.colorScheme.surface
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
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
                  borderRadius: BorderRadius.circular(999),
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
          label: '自定义背景',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.backgroundPath.isEmpty)
                TextButton.icon(
                  onPressed: _pickBackground,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('选择图片'),
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
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
                TextButton.icon(
                  onPressed: _pickBackground,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('更换'),
                ),
                TextButton.icon(
                  onPressed: () {
                    final old = settings.backgroundPath;
                    try {
                      File(old).deleteSync();
                    } catch (_) {}
                    ref
                        .read(settingsProvider.notifier)
                        .setBackgroundImage('');
                  },
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('清除'),
                ),
              ],
            ],
          ),
        ),
        if (settings.backgroundPath.isNotEmpty) ...[
          _SettingRow(
            label: '模糊度',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 180,
                  child: Slider(
                    min: 0,
                    max: 30,
                    divisions: 30,
                    value:
                        (_bgBlurDrag ?? settings.backgroundBlur).clamp(0, 30),
                    label:
                        '${(_bgBlurDrag ?? settings.backgroundBlur).round()}',
                    mouseCursor: SystemMouseCursors.click,
                    onChanged: (v) => setState(() => _bgBlurDrag = v),
                    onChangeEnd: (v) {
                      setState(() => _bgBlurDrag = null);
                      ref
                          .read(settingsProvider.notifier)
                          .setBackgroundBlur(v);
                    },
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(_bgBlurDrag ?? settings.backgroundBlur).round()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: (_bgBlurDrag ?? settings.backgroundBlur) > 0
                          ? theme.colorScheme.primary
                          : theme.hintColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SettingRow(
            label: '不透明度',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 180,
                  child: Slider(
                    min: 0,
                    max: 1,
                    divisions: 20,
                    value: (_bgOpacityDrag ?? settings.backgroundOpacity)
                        .clamp(0, 1),
                    label:
                        '${(((_bgOpacityDrag ?? settings.backgroundOpacity) * 100).round())}%',
                    mouseCursor: SystemMouseCursors.click,
                    onChanged: (v) => setState(() => _bgOpacityDrag = v),
                    onChangeEnd: (v) {
                      setState(() => _bgOpacityDrag = null);
                      ref
                          .read(settingsProvider.notifier)
                          .setBackgroundOpacity(v);
                    },
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(((_bgOpacityDrag ?? settings.backgroundOpacity) * 100).round())}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '背景应用于主界面、专辑详情、全屏播放页等全部界面；不透明度调低会透出当前主题底色。',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: theme.hintColor,
              ),
            ),
          ),
        ],
      ];

  // ---- 音频与增益 ----

  List<Widget> _audioPage(ThemeData theme, AppSettings settings) => [
        _pageHeader(theme, '音频与增益'),
        _SettingRow(
          label: '默认增益放大',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                child: Slider(
                  min: 1.0,
                  max: desktopGainCap(),
                  divisions: desktopGainCap() > 1.3 ? 30 : 3,
                  value: (_gainDrag ?? settings.audioGain).clamp(
                    1.0,
                    desktopGainCap(),
                  ),
                  label:
                      'x${(_gainDrag ?? settings.audioGain).toStringAsFixed(1)}',
                  mouseCursor: SystemMouseCursors.click,
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: (_gainDrag ?? settings.audioGain) > 1.0
                        ? theme.colorScheme.primary
                        : theme.hintColor,
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
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: theme.hintColor,
              ),
            );
          }),
        ),
        _SettingRow(
          label: '重置音频输出',
          trailing: TextButton.icon(
            onPressed: () async {
              await ref.read(playbackProvider.notifier).resetAudioOutput();
              if (mounted) _toast('已重接音频输出（audio-device=auto）');
            },
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('立即重接'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '蓝牙耳机断连/切换后若出现「进度在走但没声音」，点此把音频输出重接回当前可用设备；播放中检测到输出异常时也会自动重接。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: theme.hintColor,
            ),
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
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: theme.hintColor,
            ),
          ),
        ),
      ];

  // ---- 主界面 ----

  List<Widget> _homePage(ThemeData theme, AppSettings settings) => [
        _pageHeader(theme, '主界面'),
        _SettingRow(
          label: '显示刮削标签',
          trailing: Switch(
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
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: theme.hintColor,
            ),
          ),
        ),
      ];

  // ---- 在线外观（1.96.0；1.97.0 起字号改滑杆）----

  /// 在线外观页：四组字号滑杆 + 网格列数 + 每页条数。
  ///
  /// 与在线页工具栏的「Aa」对话框共用同一批范围常量与滑杆组件
  /// （`online_appearance.dart` 的 `OnlineFontSliderRow`），两条路径写的是
  /// 同一份设置，不存在同步问题。1.97.0 裁决 Q2：字号从档位下拉改无极滑杆；
  /// 列数与每页条数保持下拉（都是离散档位）。
  List<Widget> _onlineAppearancePage(ThemeData theme, AppSettings settings) {
    final notifier = ref.read(settingsProvider.notifier);
    return [
      _pageHeader(theme, '在线外观'),
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
      _SettingRow(
        label: '每行卡片数',
        subtitle: '桌面与移动端共用；「自动」按窗口宽度计算',
        trailing: _SettingDropdown<double>(
          value: settings.onlineGridColumns,
          items: onlineGridColumnsChoices,
          onChanged: notifier.setOnlineGridColumns,
        ),
      ),
      _SettingRow(
        label: '每页条数',
        subtitle: '在线列表一次加载的作品数；选择会记住，重启后仍生效',
        trailing: _SettingDropdown<double>(
          value: settings.onlinePageSize,
          items: [
            for (final size in OnlineBrowseNotifier.pageSizeOptions)
              (size.toDouble(), '每页 $size 条'),
          ],
          onChanged: notifier.setOnlinePageSize,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '这几组缩放都叠在「外观 → 字号」之上：最终字号 = 元素基准字号 × '
          '这里的倍率 × 全局字号。想整体放大用全局字号，只想放大在线内容才用这里。',
          style: TextStyle(fontSize: 10.5, height: 1.5, color: theme.hintColor),
        ),
      ),
    ];
  }

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
      _pageHeader(theme, '在线账号'),
      _SettingRow(
        label: '登录状态',
        trailing: switch (account) {
          _ when account.restoring =>
            Text('检查中…', style: TextStyle(fontSize: 11, color: theme.hintColor)),
          _ when account.loggedIn => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  account.displayName,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          _ => Text(
              '未登录',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
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
            style: const TextStyle(fontSize: 11),
          ),
        ),
        _SettingRow(
          label: '收藏同步',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                favorites.error ?? '与网页版共用同一份歌单',
                style: TextStyle(
                  fontSize: 10.5,
                  color: favorites.error == null
                      ? theme.hintColor
                      : const Color(0xFFD34C44),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
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
                child: const Text('刷新', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        _SettingRow(
          label: '登录令牌',
          trailing: OutlinedButton(
            onPressed: () async {
              await ref.read(onlineAccountProvider.notifier).logout();
              if (mounted) _toast('已退出登录');
            },
            child: const Text('退出登录', style: TextStyle(fontSize: 11)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Hiko 只保存 asmr.one 的登录令牌（有效期 30 天，服务端没有续期接口，'
            '过期后重新登录即可），不保存密码，也不会上传任何本地音声库信息。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: theme.hintColor,
            ),
          ),
        ),
      ] else ...[
        _SettingRow(
          label: '登录',
          trailing: FilledButton(
            onPressed: account.restoring
                ? null
                : () => unawaited(showOnlineLoginDialog(context)),
            child: const Text('登录 asmr.one', style: TextStyle(fontSize: 11)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '登录后才能收藏作品、管理歌单。收藏走 asmr.one 的歌单体系，'
            '所以可以建「未听」「已听」这类歌单来记录收听状态。'
            '没有账号的话去 www.asmr.one 注册（Hiko 不提供注册）。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: theme.hintColor,
            ),
          ),
        ),
      ],
      // 1.94.0：纯显示项，与登录无关，所以放在账号区之后、服务器/缓存之前
      _SettingRow(
        label: '卡片显示标签',
        subtitle: '在作品卡片上直接显示标签，点击可按该标签筛选',
        trailing: Switch(
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
        trailing: OutlinedButton(
          onPressed: () => unawaited(showOnlineBlacklistDialog(context)),
          child: Text(
            settings.blockedTags.isEmpty
                ? '管理'
                : '管理（${settings.blockedTags.length}）',
            style: const TextStyle(fontSize: 11),
          ),
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
              hintStyle: TextStyle(fontSize: 11, color: theme.hintColor),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
            ),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '在线音声服务地址（Kikoeru 兼容协议）。默认 asmr.one 官方实例，也可填写自建服务器地址；'
          '留空回退默认。在线浏览与播放无需登录；账号与歌单是 asmr.one 的私有能力，'
          '自建 Kikoeru 服务器上不可用。直连不通时请到「数据」页配置代理。',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.5,
            color: theme.hintColor,
          ),
        ),
      ),
      _SettingRow(
        label: '在线缓存上限',
        trailing: DropdownButton<double>(
          value: settings.onlineCacheLimitGb,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: const TextStyle(fontSize: 11),
          items: [
            for (final gb in SettingsNotifier.onlineCacheLimitOptions)
              DropdownMenuItem(
                value: gb,
                child: Text(gb == 0.0 ? '关闭（不缓存）' : _formatGb(gb)),
              ),
          ],
          onChanged: (v) {
            if (v != null) {
              ref.read(settingsProvider.notifier).setOnlineCacheLimit(v);
            }
          },
        ),
      ),
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
                  style: TextStyle(fontSize: 11, color: theme.hintColor),
                );
              },
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                await ref.read(onlineAudioCacheProvider).clear();
                if (mounted) setState(() {});
                _toast('在线缓存已清空');
              },
              child: const Text('清理', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '在线播放在超过 20 秒后才开始后台缓存整首音频到本地（避免点开即退白耗流量），'
          '超出上限时按最久未播放淘汰。缓存独立存放，不写入本地音声库。',
          style: TextStyle(
            fontSize: 10.5,
            height: 1.5,
            color: theme.hintColor,
          ),
        ),
      ),
    ];
  }

  // ---- 数据 ----

  List<Widget> _dataPage(ThemeData theme, AppSettings settings) => [
        _pageHeader(theme, '数据'),
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
                builder: (ctx) => AlertDialog(
                  title: const Text('确认重置数据库'),
                  content: const Text(
                    '将清空所有专辑记录，但不会删除源文件。\n'
                    '您的设置（主题、增益、音乐目录）将保留。\n\n'
                    '清空后需重新导入文件夹恢复专辑。\n\n'
                    '此操作无法撤销，确认继续？',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        '确认清空',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
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
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: theme.hintColor,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '刮削代理用于访问 DLsite 元数据与封面，留空走系统代理。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: theme.hintColor,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '在线音声服务地址与缓存设置已移到「在线账号」页（1.93.0 起在线相关设置集中在那里）。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: theme.hintColor,
            ),
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
        _pageHeader(theme, '音乐目录'),
        if (settings.musicFolders.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '尚未设置音乐目录。导入音声文件夹时会自动记住；之后每次启动自动扫描新增内容。',
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: theme.hintColor,
              ),
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
                  color: theme.hintColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _displayFolder(folder),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  tooltip: '移除目录',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .removeMusicFolder(folder),
                ),
              ],
            ),
          ),
        Row(
          children: [
            _ActionButton(label: '立即重新扫描', onTap: _startRescan),
            if (settings.musicFolders.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '共 ${settings.musicFolders.length} 个目录',
                style: TextStyle(fontSize: 10, color: theme.hintColor),
              ),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '每次启动会静默扫描常驻目录同步新增专辑；目录被移动/删除后请更新此处设置。',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: theme.hintColor,
            ),
          ),
        ),
      ];

  // ---- 关于 ----

  List<Widget> _aboutPage(ThemeData theme, AppSettings settings) => [
        _pageHeader(theme, '关于'),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Center(
                child: Text(
                  'K',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hiko · 音声收藏室',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '版本 ${_appVersion ?? '…'} · 本地优先的音声库管理器',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.hintColor,
                    ),
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
              borderRadius: BorderRadius.circular(8),
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
                      style: TextStyle(
                        fontSize: 12,
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
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: theme.hintColor,
                        ),
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
                    TextButton(
                      onPressed: () =>
                          setState(() => _latestRelease = null),
                      child: Text(
                        '暂不更新',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.hintColor,
                        ),
                      ),
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        isDense: true,
        borderRadius: BorderRadius.circular(8),
        dropdownColor: theme.cardColor,
        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
        icon: Icon(Icons.arrow_drop_down, size: 18, color: theme.hintColor),
        items: [
          for (final (v, label) in items)
            DropdownMenuItem<T>(value: v, child: Text(label)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 10.5, color: theme.hintColor),
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
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: theme.dividerColor),
        foregroundColor: theme.colorScheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      child: loading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            )
          : Text(label, style: const TextStyle(fontSize: 11)),
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
