import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/dlsite_scraper.dart';
import '../../data/filter.dart';
import '../../data/import_service.dart';
import '../../data/library_provider.dart';
import '../../data/library_reorganizer.dart';
import '../../data/music_folder_scanner.dart';
import '../../data/settings_store.dart';
import '../../data/stats.dart';
import '../../data/update_checker.dart';
import '../../models/album.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_rules.dart';
import '../../platform/platform_service.dart';
import '../../utils/grid_locate.dart';
import '../../utils/rj.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../widgets/album_card.dart';
import '../widgets/activity_overlay.dart';
import '../widgets/category_dialog.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/context_menu.dart';
import '../widgets/detail_drawer.dart';
import '../widgets/toast.dart';
import '../widgets/player_bar.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/stats_view.dart';
import '../widgets/sidebar.dart';

/// 主界面：桌面三栏布局（侧栏 | 网格 | 详情抽屉）+ 底部播放条；
/// Android 触屏（≤1000px）切换为移动布局：底部导航 + 抽屉侧栏 + 全屏详情 + 长按菜单 + 系统返回逐层关闭。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _view = '全部音声';
  String _filter = 'all';
  String _query = '';
  bool _multiMode = false;
  final Set<String> _multiIds = {};
  Album? _detailAlbum;
  bool _sidebarCollapsed = false;
  bool _drawerOpen = false;
  bool _importing = false;
  final Set<String> _resumeDismissed = {}; // 本次会话内被 × 关掉的「继续收听」专辑
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _filterMemo = FilterAlbumsMemo();
  // 1.49「定位当前播放」：网格滚动控制、目标卡 Key 与高亮状态
  final _gridScrollController = ScrollController();
  final _locateCardKey = GlobalKey();
  String? _locateTargetId; // 需要定位的专辑 id（定位完成后清除）
  String? _highlightedAlbumId; // 高亮中的专辑 id
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    // macOS 菜单栏动作转发（导入文件夹/设置/检查更新，1.48）
    if (Platform.isMacOS) {
      const MethodChannel('top.voicehub.hiko/menu').setMethodCallHandler((call) async {
        if (!mounted) return;
        switch (call.method) {
          case 'importFolders':
            _importFolder();
          case 'openSettings':
            _openSettings(context);
          case 'checkUpdate':
            _checkUpdateFromMenu();
        }
      });
    }
    // 启动后执行静默扫描：由于有了快速增量 diff 检查，无新文件时 10ms 即可极速返回；
    // 有新文件时展示非阻塞轻量提示与进度浮条。
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final scanner = ref.read(musicFolderScannerProvider);
      final added = await scanner.scanAll(
        silent: true,
        onProgress: (p) {
          if (!mounted) return;
          activityOverlayController.start(
            label: p.phase == 'files' ? '正在快速同步音乐目录' : '正在导入新增专辑',
            processed: p.processed,
            total: p.total,
            progress: p.total > 0 ? p.processed / p.total : null,
          );
        },
      );
      if (!mounted) return;
      activityOverlayController.finish();
      if (added > 0) {
        _showToast('已自动同步，发现 $added 张新专辑');
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _gridScrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _openSettings(BuildContext context, {bool autoCheckUpdate = false}) {
    showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        autoCheckUpdate: autoCheckUpdate,
        onImportRequested: () {
          Navigator.pop(context);
          _importFolder();
        },
        onRescanRequested: () {
          Navigator.pop(context);
          _startRescan();
        },
        onReorganizeRequested: () {
          Navigator.pop(context);
          _reorganizeLibrary();
        },
        onCleanMissingRequested: () {
          Navigator.pop(context);
          _cleanMissing();
        },
        onDownloadUpdateRequested: (release) {
          _downloadUpdate(release);
        },
      ),
    );
  }

  /// 菜单栏「检查更新」：已是最新直接 toast；发现新版打开设置弹窗自动检查（那里有下载入口）
  Future<void> _checkUpdateFromMenu() async {
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final release = await UpdateChecker.fetchLatestRelease();
      if (!mounted) return;
      if (UpdateChecker.isNewer(current, release.tagName)) {
        if (!mounted) return;
        _openSettings(context, autoCheckUpdate: true);
      } else {
        _showToast('已是最新版本($current)');
      }
    } catch (e) {
      if (mounted) _showToast('检查更新失败：$e');
    }
  }

  void _showToast(String message) {
    // 根 Overlay toast：不会被打开中的对话框盖住（1.32）
    showHikoToast(context, message);
  }

  /// 输入框（搜索框等 EditableText）有焦点时为 true——
  /// 此时空格/方向键必须走打字与光标移动，不触发播放快捷键
  bool _typingFocusActive() => isFocusInsideEditable(
      FocusManager.instance.primaryFocus?.context);

  Future<void> _importFolder() async {
    if (_importing || activityOverlayController.isActive) return;
    setState(() => _importing = true);
    activityOverlayController.start(label: '正在导入');
    final service = ImportService(ref.read(libraryStoreProvider));
    try {
      final platform = ref.read(platformServiceProvider);
      List<Album> albums;
      // Android:SAF 单树导入(接口方法,事件流式);桌面:返回 null 走批量多选
      final saf = await platform.importAudioFolder(
        onProgress: (p, t, phase, unit) {
          activityOverlayController.update(
            label: phase == 'files' ? '正在扫描音频文件' : '正在导入专辑',
            processed: p,
            total: t,
            progress: t > 0 ? p / t : null,
          );
        },
      );
      if (saf != null) {
        albums = saf.albums;
        // 记住所选目录 → 常驻自动扫描
        final treeUri = saf.treeUri;
        if (treeUri != null) {
          await ref.read(settingsProvider.notifier).addMusicFolder(treeUri);
        }
      } else {
        // 桌面：批量选择多个文件夹导入（macOS 原生多选；Windows 单选降级）
        final paths = await platform.pickDirectories();
        if (paths == null || paths.isEmpty) return;
        albums = await service.importFolders(
          paths,
          onProgress: (p) {
            activityOverlayController.update(
              label: p.phase == 'files' ? '正在扫描音频文件' : '正在导入专辑',
              processed: p.processed,
              total: p.total,
              progress: p.total > 0 ? p.processed / p.total : null,
            );
          },
        );
        // 记住所选目录 → 常驻自动扫描
        for (final path in paths) {
          await ref.read(settingsProvider.notifier).addMusicFolder(path);
        }
      }
      if (!mounted) return;
      await ref.read(libraryProvider.notifier).mergeNew(albums);
      // 全轨无可用标签的专辑（metaFromFolder）：串行查 DLsite 补标题（失败维持文件夹名）
      if (ref.read(libraryProvider).any(DlsiteScraper.shouldBackfillTitle)) {
        activityOverlayController.update(label: '正在查询 DLsite 补全标题');
        final fixed = await ref
            .read(scraperProvider)
            .backfillTitles(ref.read(libraryProvider));
        if (fixed > 0) {
          await ref.read(libraryProvider.notifier).load();
        }
      }
      setState(() {
        _view = '全部音声';
        _filter = 'all';
        _query = '';
        _searchController.clear();
      });
      _showToast(
        albums.isEmpty
            ? '没有在所选文件夹中找到支持的音频文件'
            : '已导入 ${albums.length} 张专辑，已显示在全部音声',
      );
    } catch (e) {
      _showToast('导入失败：$e');
    } finally {
      activityOverlayController.finish();
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _scrapeSelected(Set<String> ids, {required bool force}) async {
    if (ids.isEmpty || activityOverlayController.isActive) return;
    setState(() => _importing = true);
    activityOverlayController.start(label: '正在刮削');
    final scraper = ref.read(scraperProvider);
    try {
      final result = await scraper.scrape(
        ids,
        force: force,
        onProgress: (p, t) {
          activityOverlayController.update(
            processed: p,
            total: t,
            progress: t > 0 ? p / t : null,
          );
        },
      );
      if (!mounted) return;
      await ref.read(libraryProvider.notifier).load();
      if (result.noRj == ids.length) {
        _showToast('所选专辑均未检测到 RJ 号');
        return;
      }
      _showToast(
        '刮削完成：${result.scraped} 张成功，${result.failed} 张失败'
        '${result.noRj > 0 ? '，${result.noRj} 张无 RJ 号' : ''}'
        '${result.skipped > 0 ? '，${result.skipped} 张已刮过跳过' : ''}',
      );
    } catch (e) {
      _showToast('刮削失败：$e');
    } finally {
      activityOverlayController.finish();
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _startRescan() async {
    if (activityOverlayController.isActive) return;
    activityOverlayController.start(label: '准备扫描...');
    try {
      final added = await ref
          .read(musicFolderScannerProvider)
          .scanAll(
            silent: false,
            onProgress: (p) {
              activityOverlayController.update(
                label: p.phase == 'files' ? '正在扫描音频文件' : '正在解析组装专辑',
                processed: p.processed,
                total: p.total,
                progress: p.total > 0 ? p.processed / p.total : null,
              );
            },
          );
      _showToast(added > 0 ? '扫描完成，新增 $added 张专辑' : '扫描完成，没有新内容');
    } catch (e) {
      _showToast('扫描失败：$e');
    } finally {
      activityOverlayController.finish();
    }
  }

  Future<void> _reorganizeLibrary() async {
    if (activityOverlayController.isActive) return;
    activityOverlayController.start(label: '正在整理专辑元数据');
    try {
      final result = await ref.read(libraryReorganizerProvider).reorganizeAll();
      final stats = result.stats;
      if (!stats.hasChanges) {
        _showToast('已检查全部专辑，元数据与曲目均与本地文件一致');
        return;
      }
      final parts = <String>[];
      if (stats.updatedAlbums > 0) parts.add('更新 ${stats.updatedAlbums} 张专辑');
      if (stats.removedAlbums > 0) parts.add('清理 ${stats.removedAlbums} 张空专辑');
      if (stats.tracksAdded > 0) parts.add('+${stats.tracksAdded} 首新增');
      if (stats.tracksRemoved > 0) parts.add('-${stats.tracksRemoved} 首删除');
      if (stats.tracksModified > 0) {
        parts.add('${stats.tracksModified} 首标签/信息更新');
      }
      _showToast('整理完成：${parts.join('，')}');
    } catch (e) {
      _showToast('整理失败：$e');
    } finally {
      activityOverlayController.finish();
    }
  }

  Future<void> _cleanMissing() async {
    if (activityOverlayController.isActive) return;
    activityOverlayController.start(label: '正在清理失效记录');
    try {
      final albums = ref.read(libraryProvider);
      final kept = await ref.read(platformServiceProvider).cleanMissing(albums);
      final removed = albums.length - kept.length;
      await ref.read(libraryProvider.notifier).replaceAll(kept);
      _showToast(removed > 0 ? '已清理 $removed 张失效专辑' : '库中暂无失效记录');
    } catch (e) {
      _showToast('清理失败：$e');
    } finally {
      activityOverlayController.finish();
    }
  }

  Future<void> _downloadUpdate(GithubRelease release) async {
    if (activityOverlayController.isActive) return;
    final asset = UpdateChecker.pickAsset(release, Platform.operatingSystem);
    if (asset == null) {
      _showToast('未找到适用于本平台的安装包,请前往 GitHub Releases 手动下载');
      return;
    }
    activityOverlayController.start(label: '正在下载更新包', total: asset.size);
    try {
      final dest = await UpdateChecker.suggestDestPath(asset);
      await UpdateChecker.downloadAsset(
        asset,
        dest,
        onProgress: (received, total) {
          activityOverlayController.update(
            processed: received,
            total: total > 0 ? total : asset.size,
            progress: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
          );
        },
      );
      await ref.read(platformServiceProvider).openDownloadedUpdate(dest);
      _showToast(
        Platform.isAndroid
            ? '下载完成,已调起系统安装器'
            : '已下载到 ${asset.name},请在文件管理器中解压并替换应用',
      );
    } catch (e) {
      _showToast('下载失败：$e');
    } finally {
      activityOverlayController.finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(libraryProvider);
    final currentSort = ref.watch(settingsProvider.select((s) => s.albumSort));
    // 1.48：排序/过滤走 memo——列表实例与参数不变时复用结果，大库重建不再全量重算；
    // 「统计」视图不走筛选（面板直接聚合全库）
    final filtered = _view == '统计'
        ? albums
        : _filterMemo.get(
            albums: albums,
            view: _view,
            filter: _filter,
            query: _query,
            sort: currentSort,
          );
    final theme = Theme.of(context);
    // 移动布局仅 Android 触屏（≤1000px，与旧版桥接层一致）；桌面永远桌面布局
    final isMobile = Platform.isAndroid
        ? MediaQuery.sizeOf(context).width <= 1000
        : false;

    return PopScope(
      canPop: !isMobile,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isMobile) return;
        // Android 返回键逐层关闭（对应旧版桥接层逻辑）
        if (_multiMode) {
          setState(() {
            _multiMode = false;
            _multiIds.clear();
          });
        } else if (_detailAlbum != null) {
          setState(() => _detailAlbum = null);
        } else if (_drawerOpen) {
          setState(() => _drawerOpen = false);
        } else if (_view != '全部音声') {
          setState(() => _view = '全部音声');
        } else {
          SystemNavigator.pop(); // 无浮层 → 最小化/退出
        }
      },
      child: Scaffold(
        body: Shortcuts(
          shortcuts: {
            // ⌘K / Ctrl+K 聚焦搜索（对应旧版快捷键）
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                const _FocusSearchIntent(),
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                const _FocusSearchIntent(),
            // ⌘O / Ctrl+O 导入（对应旧版菜单「导入音声文件夹」）
            const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
                const _ImportIntent(),
            const SingleActivator(LogicalKeyboardKey.keyO, control: true):
                const _ImportIntent(),
            // 空格播放/暂停；←→ 快退/快进；↑↓ 切曲（输入框聚焦时不触发）
            const SingleActivator(LogicalKeyboardKey.space):
                const _TogglePlaybackIntent(),
            const SingleActivator(LogicalKeyboardKey.arrowLeft):
                _SeekIntent(-1),
            const SingleActivator(LogicalKeyboardKey.arrowRight):
                _SeekIntent(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp):
                const _StepTrackIntent(-1),
            const SingleActivator(LogicalKeyboardKey.arrowDown):
                const _StepTrackIntent(1),
          },
          child: Actions(
            actions: {
              _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
                onInvoke: (_) {
                  _searchFocus.requestFocus();
                  return null;
                },
              ),
              _ImportIntent: CallbackAction<_ImportIntent>(
                onInvoke: (_) {
                  _importFolder();
                  return null;
                },
              ),
              _TogglePlaybackIntent: CallbackAction<_TogglePlaybackIntent>(
                onInvoke: (_) {
                  if (_typingFocusActive()) return null;
                  ref.read(playbackProvider.notifier).toggle();
                  return null;
                },
              ),
              _SeekIntent: CallbackAction<_SeekIntent>(
                onInvoke: (intent) {
                  if (_typingFocusActive()) return null;
                  final controller = ref.read(playbackProvider.notifier);
                  final pos = ref.read(playbackProvider).position;
                  final step = ref.read(settingsProvider).seekStepSeconds;
                  controller.seek(pos + intent.direction * step);
                  return null;
                },
              ),
              _StepTrackIntent: CallbackAction<_StepTrackIntent>(
                onInvoke: (intent) {
                  if (_typingFocusActive()) return null;
                  final controller = ref.read(playbackProvider.notifier);
                  if (intent.direction < 0) {
                    controller.prev();
                  } else {
                    controller.next();
                  }
                  return null;
                },
              ),
            },
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!isMobile) ...[
                              SizedBox(
                                width: _sidebarCollapsed ? 44 : 240,
                                child: Sidebar(
                                  activeView: _view,
                                  collapsed: _sidebarCollapsed,
                                  onViewChanged: (view) =>
                                      setState(() => _view = view),
                                  onOpenSettings: () => _openSettings(context),
                                ),
                              ),
                            ],
                            Expanded(
                              child: _buildMain(
                                filtered,
                                theme,
                                isMobile,
                                currentSort,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PlayerBar(
                        compact: isMobile,
                        onCoverTap: (a) => setState(() => _detailAlbum = a),
                      ),
                    ],
                  ),
                  // 移动端：抽屉侧栏
                  if (isMobile && _drawerOpen)
                    Positioned.fill(
                      child: Stack(
                        children: [
                          // 遮罩非按钮：NoSplash 防全屏水波纹（关抽屉本身即反馈）
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _drawerOpen = false),
                              splashFactory: NoSplash.splashFactory,
                              highlightColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 240,
                            child: Material(
                              elevation: 8,
                              child: Sidebar(
                                activeView: _view,
                                onViewChanged: (view) {
                                  setState(() {
                                    _view = view;
                                    _drawerOpen = false;
                                  });
                                },
                                onOpenSettings: () {
                                  setState(() => _drawerOpen = false);
                                  _openSettings(context);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // 详情遮罩（桌面）：点击抽屉外区域关闭（不阻断抽屉内交互，
                  // Stack hit test 短路保证上层抽屉命中时遮罩不参与）；遮罩非按钮不加水波纹
                  if (_detailAlbum != null && !isMobile)
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() => _detailAlbum = null),
                          splashFactory: NoSplash.splashFactory,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                        ),
                      ),
                    ),
                  // 详情：桌面右侧抽屉 / 移动全屏弹层
                  if (_detailAlbum != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: isMobile ? 118 : 0,
                      left: isMobile ? 0 : null,
                      // 桌面：抽屉宽 390，窗口过窄时收缩到窗口可用宽，避免抽屉本身溢出右缘
                      width: isMobile
                          ? null
                          : MediaQuery.sizeOf(context).width.clamp(200.0, 390.0),
                      child: DetailDrawer(
                        album: _detailAlbum!,
                        onClose: () => setState(() => _detailAlbum = null),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // 移动端底部导航（对应旧版 bottom-nav）
        bottomNavigationBar: isMobile
            ? BottomNavigationBar(
                currentIndex: _navIndex,
                onTap: (i) {
                  if (i == 4) {
                    _openSettings(context);
                    return;
                  }
                  setState(() => _view = _navViews[i]);
                },
                type: BottomNavigationBarType.fixed,
                backgroundColor: theme.colorScheme.surface,
                selectedItemColor: theme.colorScheme.primary,
                unselectedItemColor: theme.hintColor,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.grid_view_rounded),
                    label: '全部',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.history_rounded),
                    label: '最近',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.play_circle_outline_rounded),
                    label: '播放',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.favorite_border_rounded),
                    label: '收藏',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings_outlined),
                    label: '设置',
                  ),
                ],
              )
            : null,
      ),
    );
  }

  static const _navViews = ['全部音声', '最近添加', '正在播放', '收藏夹'];

  int get _navIndex {
    final i = _navViews.indexOf(_view);
    return i < 0 ? 0 : i;
  }

  Widget _buildMain(List<Album> filtered, ThemeData theme, bool isMobile, String currentSort) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopbar(theme, isMobile),
        _buildHero(theme, filtered.length, isMobile),
        _buildToolbar(theme, isMobile, filtered, currentSort),
        _buildResultsLine(theme, filtered.length),
        _buildResumeBanner(theme, isMobile),
        Expanded(
          child: _view == '统计'
              ? StatsView(
                  stats: computeLibraryStats(filtered),
                  onOpenAlbum: (album) =>
                      setState(() => _detailAlbum = album),
                )
              : _buildGrid(filtered, theme, isMobile),
        ),
      ],
    );
  }

  /// 「继续收听」横幅卡：最近播过的一张专辑 + 断点位置，点击断点起播
  Widget _buildResumeBanner(ThemeData theme, bool isMobile) {
    final playback = ref.watch(playbackProvider);
    final candidate = QueueRules.resumeCandidate(
      ref.watch(libraryProvider),
      playingAlbumId: playback.album?.id,
    );
    if (candidate == null ||
        candidate.tracks.isEmpty ||
        _resumeDismissed.contains(candidate.id)) {
      return const SizedBox.shrink();
    }
    final trackNo = candidate.resumeTrackIndex.clamp(0, candidate.tracks.length - 1) + 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 48, 0, isMobile ? 16 : 48, 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            ref.read(playbackProvider.notifier).playAlbum(
                  candidate,
                  index: candidate.resumeTrackIndex,
                  startPosition: candidate.resumePosition,
                );
            _showToast('已从上次断点继续播放');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: AlbumCover(album: candidate),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '继续收听',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${candidate.title} · 上次听到第 $trackNo 轨 ${formatTime(candidate.resumePosition)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  tooltip: '关闭',
                  onPressed: () =>
                      setState(() => _resumeDismissed.add(candidate.id)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 「随机播放」：盲选一张可播专辑从第 1 轨起播，不改当前播放模式
  void _playRandomAlbum() {
    final albums = ref.read(libraryProvider);
    final current = ref.read(playbackProvider).album;
    final picked = pickRandomPlayableAlbum(albums, current);
    if (picked == null) {
      _showToast('还没有可播放的专辑');
      return;
    }
    ref.read(playbackProvider.notifier).playAlbum(picked, index: 0);
  }

  /// 「定位当前播放」（1.49）：网格滚回正在播放的专辑卡并短暂高亮；
  /// 专辑不在当前列表（搜索/筛选/其它视图/统计）时先清筛选切回「全部音声」
  void _locatePlayingAlbum() {
    final target = ref.read(playbackProvider).album;
    if (target == null) return;
    final inCurrentView = _view != '统计' &&
        _filterMemo
            .get(
              albums: ref.read(libraryProvider),
              view: _view,
              filter: _filter,
              query: _query,
              sort: ref.read(settingsProvider).albumSort,
            )
            .any((a) => a.id == target.id);
    setState(() {
      if (!inCurrentView) {
        // 与「清除筛选」同语义
        _query = '';
        _searchController.clear();
        _filter = 'all';
        _view = '全部音声';
      }
      _locateTargetId = target.id;
    });
    // 等网格按（可能重置后的）列表完成一帧布局，再计算偏移跳转
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToLocatedCard(target.id);
    });
  }

  /// 按当前网格布局算出目标行偏移并 jumpTo（大库禁止动画长滚），
  /// 跳转后下一帧对目标卡精确微调并点亮高亮
  void _jumpToLocatedCard(String albumId) {
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final size = MediaQuery.sizeOf(context);
    final isMobile =
        Platform.isAndroid ? size.width <= 1000 : false;
    final result = locateAlbumInGrid(
      filtered: _filterMemo.get(
        albums: ref.read(libraryProvider),
        view: _view,
        filter: _filter,
        query: _query,
        sort: settings.albumSort,
      ),
      albumId: albumId,
      metrics: GridMetrics(
        useFixedCount: !isMobile && settings.gridColumns > 0,
        fixedCrossAxisCount: settings.gridColumns.round(),
        maxCrossAxisExtent: isMobile ? 240 : 190,
        viewportWidth: size.width,
        horizontalPadding: (isMobile ? 16 : 48) * 2 + (isMobile ? 0 : (_sidebarCollapsed ? 44.0 : 240.0)),
        topPadding: 16,
      ),
    );
    if (!result.found) {
      setState(() => _locateTargetId = null);
      return;
    }
    final position = _gridScrollController.position;
    _gridScrollController
        .jumpTo((result.scrollOffset - 24).clamp(0.0, position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _locateCardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 120),
          alignment: 0.15,
        );
      }
      _highlightTimer?.cancel();
      setState(() => _highlightedAlbumId = albumId);
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() {
          _highlightedAlbumId = null;
          _locateTargetId = null;
        });
      });
    });
  }

  Widget _buildTopbar(ThemeData theme, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: 14,
      ),
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu_rounded, size: 22),
              tooltip: '侧栏',
              onPressed: () => setState(() => _drawerOpen = true),
            )
          else
            IconButton(
              icon: Icon(
                _sidebarCollapsed ? Icons.menu_open : Icons.menu,
                size: 18,
              ),
              tooltip: _sidebarCollapsed ? '显示侧栏' : '隐藏侧栏',
              onPressed: () =>
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            ),
          if (!isMobile) ...[
            Text('音声库', style: TextStyle(fontSize: 13, color: theme.hintColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '/',
                style: TextStyle(color: theme.hintColor.withValues(alpha: 0.5)),
              ),
            ),
          ],
          Text(
            _view,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          // 1.49「定位当前播放」：无播放置灰
          IconButton(
            icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
            tooltip: '定位当前播放',
            onPressed: ref.watch(playbackProvider).album == null
                ? null
                : _locatePlayingAlbum,
          ),
          IconButton(
            icon: Icon(
              ref.watch(settingsProvider).theme == 'dark'
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              size: 18,
            ),
            tooltip: '切换主题',
            onPressed: () {
              final s = ref.read(settingsProvider);
              ref
                  .read(settingsProvider.notifier)
                  .setTheme(s.theme == 'dark' ? 'light' : 'dark');
            },
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: _playRandomAlbum,
            icon: const Icon(Icons.shuffle_rounded, size: 16),
            label: Text(isMobile ? '随机' : '随机播放'),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: _importFolder,
            icon: const Icon(Icons.upload, size: 16),
            label: Text(isMobile ? '导入' : '导入'),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(ThemeData theme, int resultCount, bool isMobile) {
    final favCount = ref.watch(libraryProvider).where((a) => a.favorite).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 48,
        isMobile ? 8 : 20,
        isMobile ? 16 : 48,
        isMobile ? 12 : 24,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PERSONAL LIBRARY',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.7,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  _view,
                  style: TextStyle(
                    fontSize: isMobile ? 24 : 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '把每一次心动、每一段陪伴，都放进自己的声音收藏室。',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ],
            ),
          ),
          if (!isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '已收藏',
                  style: TextStyle(fontSize: 10, color: theme.hintColor),
                ),
                Text(
                  '$favCount',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                    height: 1.1,
                  ),
                ),
                Text(
                  '张专辑',
                  style: TextStyle(fontSize: 10, color: theme.hintColor),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(
    ThemeData theme,
    bool isMobile,
    List<Album> filtered,
    String currentSort,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: '搜索标题、社团或声优',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: theme.hintColor,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      contentPadding: EdgeInsets.zero,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // 筛选组
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    for (final (key, label) in [
                      ('all', '全部'),
                      ('unplayed', '未听完'),
                      ('favorite', '已收藏'),
                    ])
                      InkWell(
                        onTap: () => setState(() => _filter = key),
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _filter == key
                                ? theme.colorScheme.surface
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _filter == key
                                  ? theme.colorScheme.onSurface
                                  : theme.hintColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // 排序
              _SortSelector(
                currentSort: currentSort,
                isMobile: isMobile,
                onSelected: (val) =>
                    ref.read(settingsProvider.notifier).setAlbumSort(val),
              ),
              const SizedBox(width: 14),
              // 多选
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _multiMode = !_multiMode;
                    _multiIds.clear();
                  });
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  backgroundColor: _multiMode
                      ? theme.colorScheme.primary
                      : null,
                  foregroundColor: _multiMode
                      ? theme.colorScheme.onPrimary
                      : null,
                  side: BorderSide(
                    color: _multiMode
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: Text(
                  _multiMode ? '退出多选' : '多选',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          // 多选操作条
          if (_multiMode)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '已选 ${_multiIds.length} 张',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: () {
                      setState(
                        () => _multiIds.addAll(filtered.map((a) => a.id)),
                      );
                    },
                    child: const Text('全选', style: TextStyle(fontSize: 11)),
                  ),
                  FilledButton.tonal(
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _setCategoryForSelected(Set.of(_multiIds)),
                    child: const Text('设置分类', style: TextStyle(fontSize: 11)),
                  ),
                  FilledButton.tonal(
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () =>
                              _scrapeSelected(Set.of(_multiIds), force: false),
                    child: const Text('刮削标签', style: TextStyle(fontSize: 11)),
                  ),
                  FilledButton.tonal(
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _setRatingForSelected(Set.of(_multiIds)),
                    child: const Text('设置星级', style: TextStyle(fontSize: 11)),
                  ),
                  FilledButton.tonal(
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _deleteSelected(false),
                    child: const Text('删除所选', style: TextStyle(fontSize: 11)),
                  ),
                  FilledButton.tonal(
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _deleteSelected(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD34C44),
                    ),
                    child: const Text(
                      '删除所选及源文件',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _multiMode = false;
                      _multiIds.clear();
                    }),
                    child: const Text('取消', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsLine(ThemeData theme, int count) {
    final hasFilter = _query.isNotEmpty || _filter != 'all' || _view != '全部音声';
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
      child: Row(
        children: [
          Text(
            '显示 $count 张专辑',
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
          const Spacer(),
          if (hasFilter)
            TextButton(
              onPressed: () => setState(() {
                _query = '';
                _filter = 'all';
                _view = '全部音声';
                _searchController.clear();
              }),
              child: const Text('清除筛选', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Album> filtered, ThemeData theme, bool isMobile) {
    // 1.43：每行专辑数设置仅桌面端生效，移动端保持按宽度自适应
    final settings = ref.watch(settingsProvider);
    final desktopGridColumns = isMobile ? 0.0 : settings.gridColumns;
    if (filtered.isEmpty) {
      final empty = ref.watch(libraryProvider).isEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              empty ? '还没有导入任何音声' : '没有找到匹配的音声',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              empty ? '点击右上角「导入」按钮，选择你的音声文件夹' : '试试其他关键词或清除筛选条件',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      controller: _gridScrollController,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 48,
        16,
        isMobile ? 16 : 48,
        24,
      ),
      gridDelegate: desktopGridColumns > 0
          ? SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: desktopGridColumns.toInt(),
              mainAxisSpacing: 25,
              crossAxisSpacing: 18,
              childAspectRatio: 0.60,
            )
          : SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: isMobile ? 240 : 190,
              mainAxisSpacing: 25,
              crossAxisSpacing: 18,
              childAspectRatio: 0.60,
            ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final album = filtered[index];
        final isSelected = _multiIds.contains(album.id);
        return AlbumCard(
          key: album.id == _locateTargetId ? _locateCardKey : null,
          album: album,
          multiMode: _multiMode,
          selected: isSelected,
          showScrapedTags: settings.showScrapedTags,
          highlighted: album.id == _highlightedAlbumId,
          onTap: () {
            if (_multiMode) {
              setState(() {
                isSelected
                    ? _multiIds.remove(album.id)
                    : _multiIds.add(album.id);
              });
            } else {
              setState(() => _detailAlbum = album);
            }
          },
          onContextMenu: (position) => _showContextMenu(album, position),
        );
      },
    );
  }

  /// 右键/长按菜单：弹出柔和圆角紧凑微动效上下文菜单
  void _showContextMenu(Album album, Offset position) {
    showHikoContextMenu<String>(
      context: context,
      position: position,
      items: [
        const HikoContextMenuItem(
          value: 'category',
          label: '设置分类',
          icon: Icons.label_outline,
        ),
        const HikoContextMenuItem(
          value: 'rating',
          label: '设置星级',
          icon: Icons.star_outline_rounded,
        ),
        if (albumRjCode(album) != null)
          const HikoContextMenuItem(
            value: 'scrape',
            label: '刮削 DLsite 标签',
            icon: Icons.auto_awesome_outlined,
          ),
        if (album.hasLocalFiles)
          const HikoContextMenuItem(
            value: 'reorganize',
            label: '整理专辑元数据',
            icon: Icons.sync_outlined,
          ),
        if (album.hasLocalFiles)
          const HikoContextMenuItem(
            value: 'reveal',
            label: '打开所在文件夹',
            icon: Icons.folder_open_outlined,
          ),
        const HikoContextMenuItem(
          value: 'delete-only',
          label: '从库中删除',
          icon: Icons.remove_circle_outline,
        ),
        if (album.hasLocalFiles)
          const HikoContextMenuItem(
            value: 'delete-files',
            label: '删除专辑及源文件',
            icon: Icons.delete_outline,
            isDestructive: true,
          ),
      ],
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case 'category':
          _setCategoryForSingle(album);
        case 'rating':
          _setRatingForSingle(album);
        case 'scrape':
          _scrapeSelected({album.id}, force: true);
        case 'reorganize':
          _reorganizeSingle(album);
        case 'reveal':
          ref.read(platformServiceProvider).revealInFolder(album);
        case 'delete-only':
          _deleteSingle(album, false);
        case 'delete-files':
          _deleteSingle(album, true);
      }
    });
  }

  Future<void> _setCategoryForSingle(Album album) async {
    final chosen = await showSelectCategoryDialog(
      context,
      currentGenre: album.genre,
      albumCount: 1,
    );
    if (chosen == null || chosen == album.genre) return;

    try {
      await ref
          .read(libraryProvider.notifier)
          .updateAlbum(album.id, (a) => a.copyWith(genre: chosen));
      if (_detailAlbum?.id == album.id) {
        setState(() => _detailAlbum = _detailAlbum?.copyWith(genre: chosen));
      }
      _showToast(
        chosen == '未分类'
            ? '已将「${album.title}」移出分类'
            : '已将「${album.title}」归入「$chosen」',
      );
    } catch (e) {
      _showToast('设置分类失败：$e');
    }
  }

  /// 单张设星（右键菜单 / 详情抽屉，1.48）
  Future<void> _setRatingForSingle(Album album) async {
    final rating = await showRatingDialog(context, initialRating: album.rating);
    if (rating == null || !mounted) return;
    try {
      await ref
          .read(libraryProvider.notifier)
          .updateAlbum(album.id, (a) => a.copyWith(rating: rating));
      if (_detailAlbum?.id == album.id) {
        setState(() => _detailAlbum = _detailAlbum?.copyWith(rating: rating));
      }
      _showToast(rating > 0 ? '已设为 $rating 星' : '已清除星级');
    } catch (e) {
      _showToast('设置星级失败：$e');
    }
  }

  /// 多选批量设星（1.48）
  Future<void> _setRatingForSelected(Set<String> ids) async {
    if (ids.isEmpty) return;
    final rating = await showRatingDialog(context, initialRating: 0);
    if (rating == null || !mounted) return;
    try {
      await ref
          .read(libraryProvider.notifier)
          .updateAlbums(ids, (a) => a.copyWith(rating: rating));
      if (_detailAlbum != null && ids.contains(_detailAlbum!.id)) {
        setState(() => _detailAlbum = _detailAlbum?.copyWith(rating: rating));
      }
      setState(() {
        _multiMode = false;
        _multiIds.clear();
      });
      _showToast(rating > 0 ? '已为 ${ids.length} 张专辑设为 $rating 星' : '已清除 ${ids.length} 张专辑的星级');
    } catch (e) {
      _showToast('设置星级失败：$e');
    }
  }

  Future<void> _setCategoryForSelected(Set<String> ids) async {    if (ids.isEmpty) return;
    final chosen = await showSelectCategoryDialog(
      context,
      currentGenre: '',
      albumCount: ids.length,
    );
    if (chosen == null) return;

    try {
      await ref
          .read(libraryProvider.notifier)
          .updateAlbums(ids, (a) => a.copyWith(genre: chosen));
      if (_detailAlbum != null && ids.contains(_detailAlbum!.id)) {
        setState(() => _detailAlbum = _detailAlbum?.copyWith(genre: chosen));
      }
      setState(() {
        _multiMode = false;
        _multiIds.clear();
      });
      _showToast(
        chosen == '未分类'
            ? '已将 ${ids.length} 张专辑移出分类'
            : '已将 ${ids.length} 张专辑批量归入「$chosen」',
      );
    } catch (e) {
      _showToast('批量设置分类失败：$e');
    }
  }

  Future<void> _reorganizeSingle(Album album) async {
    try {
      final result = await ref
          .read(libraryReorganizerProvider)
          .reorganizeSingleAlbum(album);
      if (result.albums.isNotEmpty) {
        final updated = result.albums.first;
        await ref
            .read(libraryProvider.notifier)
            .updateAlbum(album.id, (_) => updated);
        if (_detailAlbum?.id == album.id) {
          setState(() => _detailAlbum = updated);
        }
      }
      final stats = result.stats;
      final msg = stats.hasChanges
          ? '「${album.title}」已整理完成（变动已同步）'
          : '「${album.title}」文件与元数据已是最新';
      _showToast(msg);
    } catch (e) {
      _showToast('整理失败：$e');
    }
  }

  Future<void> _deleteSingle(Album album, bool deleteFiles) async {
    if (deleteFiles) {
      final ok = await showConfirmDialog(
        context,
        title: '删除专辑及源文件',
        message: '将永久删除「${album.title}」的全部音频文件与文件夹，此操作不可恢复。确定继续吗？',
        okLabel: '删除',
      );
      if (!ok) return;
    }
    try {
      final deletedFiles = deleteFiles
          ? await ref.read(platformServiceProvider).removeAlbumFiles(album)
          : 0;
      await ref.read(libraryProvider.notifier).removeAlbums({album.id});
      if (_detailAlbum?.id == album.id) setState(() => _detailAlbum = null);
      _showToast(
        deleteFiles
            ? '已删除「${album.title}」及 $deletedFiles 个源文件'
            : '已将「${album.title}」从库中删除',
      );
    } catch (e) {
      _showToast('删除失败：$e');
    }
  }

  Future<void> _deleteSelected(bool deleteFiles) async {
    final count = _multiIds.length;
    if (count == 0) return;
    final ok = await showConfirmDialog(
      context,
      title: deleteFiles ? '删除所选专辑及源文件' : '删除所选专辑',
      message: deleteFiles
          ? '将永久删除选中的 $count 张专辑的全部音频文件与文件夹，此操作不可恢复。确定继续吗？'
          : '确定从库中删除选中的 $count 张专辑吗？源文件不受影响。',
      okLabel: '删除',
    );
    if (!ok) return;
    try {
      final ids = Set.of(_multiIds);
      var deletedFiles = 0;
      if (deleteFiles) {
        final albums = ref.read(libraryProvider);
        for (final a in albums.where((a) => ids.contains(a.id))) {
          deletedFiles += await ref
              .read(platformServiceProvider)
              .removeAlbumFiles(a);
        }
      }
      await ref.read(libraryProvider.notifier).removeAlbums(ids);
      setState(() {
        _multiMode = false;
        _multiIds.clear();
      });
      _showToast(
        deleteFiles
            ? '已删除 $count 张专辑及 $deletedFiles 个源文件'
            : '已从库中删除 $count 张专辑',
      );
    } catch (e) {
      _showToast('删除失败：$e');
    }
  }
}

/// 快捷键 Intent：聚焦搜索框
class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// 快捷键 Intent：导入音声文件夹
class _ImportIntent extends Intent {
  const _ImportIntent();
}

/// 快捷键 Intent：播放/暂停
class _TogglePlaybackIntent extends Intent {
  const _TogglePlaybackIntent();
}

/// 快捷键 Intent：快退/快进（direction: -1 / 1，步长取设置 seekStepSeconds）
class _SeekIntent extends Intent {
  final int direction;
  const _SeekIntent(this.direction);
}

/// 快捷键 Intent：上一首/下一首（direction: -1 / 1）
class _StepTrackIntent extends Intent {
  final int direction;
  const _StepTrackIntent(this.direction);
}

/// 焦点落在输入框（EditableText 及其后代）内时返回 true。
/// 顶层的可单测守卫：Flutter 的 Shortcuts 在焦点链祖先上先于文本输入判定，
/// 不挡住的话搜索框里打空格会误触发播放/暂停。
bool isFocusInsideEditable(BuildContext? context) {
  if (context == null) return false;
  return context.findAncestorStateOfType<EditableTextState>() != null;
}

/// 与筛选栏视觉一致的精致排序下拉组件
class _SortSelector extends StatelessWidget {
  const _SortSelector({
    required this.currentSort,
    required this.isMobile,
    required this.onSelected,
  });

  final String currentSort;
  final bool isMobile;
  final ValueChanged<String> onSelected;

  static const _sortOptions = [
    ('recent_desc', '最近添加（新到旧）', Icons.schedule_outlined),
    ('recent_asc', '最早添加（旧到新）', Icons.history_rounded),
    ('title_asc', '标题 A → Z', Icons.sort_by_alpha_outlined),
    ('title_desc', '标题 Z → A', Icons.sort_by_alpha_outlined),
    ('artist_asc', '专辑艺术家（专辑多在前）', Icons.people_alt_outlined),
    ('duration_desc', '时长（长到短）', Icons.hourglass_bottom_outlined),
    ('duration_asc', '时长（短到长）', Icons.hourglass_top_outlined),
    ('rating_desc', '评分优先', Icons.star_rounded),
  ];

  String get _currentLabel {
    switch (currentSort) {
      case 'recent_asc':
        return '最早添加';
      case 'title':
      case 'title_asc':
        return '标题 A-Z';
      case 'title_desc':
        return '标题 Z-A';
      case 'artist_asc':
        return '专辑艺术家';
      case 'duration':
      case 'duration_desc':
        return '时长 (长→短)';
      case 'duration_asc':
        return '时长 (短→长)';
      case 'rating_desc':
        return '评分优先';
      case 'recent':
      case 'recent_desc':
      default:
        return '最近添加';
    }
  }

  void _openSortMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final position = Offset(offset.dx, offset.dy + size.height + 4);

    showHikoContextMenu<String>(
      context: context,
      position: position,
      items: [
        for (final opt in _sortOptions)
          HikoContextMenuItem(value: opt.$1, label: opt.$2, icon: opt.$3),
      ],
    ).then((val) {
      if (val != null && val != currentSort) {
        onSelected(val);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _openSortMenu(context),
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMobile) ...[
              Text(
                '排序',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              _currentLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: theme.hintColor,
            ),
          ],
        ),
      ),
    );
  }
}
