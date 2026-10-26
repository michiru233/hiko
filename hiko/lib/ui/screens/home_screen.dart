import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/categories_provider.dart';
import '../../data/dlsite_scraper.dart';
import '../../data/filter.dart';
import '../../data/import_service.dart';
import '../../data/library_provider.dart';
import '../../data/library_reorganizer.dart';
import '../../data/music_folder_scanner.dart';
import '../../data/online/online_account.dart';
import '../../data/online/online_favorites.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import '../../data/stats.dart';
import '../../data/update_checker.dart';
import '../../models/album.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_rules.dart';
import '../../platform/platform_service.dart';
import '../../utils/masonry_layout.dart';
import '../../utils/rj.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../widgets/album_card.dart';
import '../widgets/activity_overlay.dart';
import '../widgets/category_dialog.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/context_menu.dart';
import '../widgets/detail_drawer.dart';
import '../widgets/detail_kit.dart';
import '../m3e/m3e.dart';
import '../../platform/desktop_window.dart';
import '../widgets/category_chips.dart';
import '../widgets/hiko_nav_destinations.dart';
import '../widgets/online_appearance.dart';
import '../widgets/toast.dart';
import '../widgets/player_bar.dart';
import '../detail_jump_requests.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/stats_view.dart';
import 'album_detail_screen.dart';
import 'online_favorites_screen.dart';
import 'online_screen.dart';
import '../transitions/fullscreen_player_route.dart';

/// 启动后延迟多久再跑静默扫描（等首帧与库加载稳定，非动效）。
const Duration kPostLaunchScanDelay = Duration(milliseconds: 500);

/// 定位到某张卡后高亮保持多久（非动效：这是「看见」的时间）。
const Duration kLocateHighlightDuration = Duration(seconds: 2);


/// 主界面：桌面三栏布局（侧栏 | 网格 | 详情抽屉）+ 底部播放条；
/// Android 触屏（≤1000px）切换为移动布局：底部导航 + 抽屉侧栏 + 全屏详情 + 长按菜单 + 系统返回逐层关闭。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.debugMobileLayout});

  /// 仅供测试：widget 测试跑在 macOS 宿主上，`Platform.isAndroid` 恒为 false，
  /// 移动端（≤1000px 那套）布局与手势否则完全不可达。**生产代码永不传它。**
  @visibleForTesting
  final bool? debugMobileLayout;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _view = '本地音声';
  String _filter = 'all';
  // 1.77 详情页胶囊回传的社团/声优点选筛选（至多一个生效，kind: 'circle' | 'voice'）
  String? _personFilterKind;
  String? _personFilterName;
  final String _query = ''; // 保留空字符串以兼容 FilterAlbumsMemo，搜索功能已移除
  bool _multiMode = false;
  final Set<String> _multiIds = {};
  Album? _detailAlbum;
  bool _importing = false;
  final Set<String> _resumeDismissed = {}; // 本次会话内被 × 关掉的「继续收听」专辑
  final _filterMemo = FilterAlbumsMemo();

  /// 刮削标签点选筛选（1.99.15）：与视图/过滤叠加（AND），空 = 不筛选
  String? _tagFilter;
  // 1.49「定位当前播放」：网格滚动控制、目标卡 Key 与高亮状态
  final _gridScrollController = ScrollController();

  /// 1.99.32 M3EAppBar.large 折叠签名（plan §8.1）：移动端大标题滚出视口后，
  /// 顶栏浮现同名小标题。只在移动端本地视图消费（在线顶栏整行收起）。
  bool _mobileTopbarTitle = false;

  // 1.99.9 移动端本地视图：头部（hero + 筛选行 + 结果行 + 续播横幅）滚动收起
  // 的离屏测量锚点与测量值。滚动控制器沿用 [_gridScrollController]（定位当前
  // 播放的 jumpTo / 桌面抽屉滚轮转发都绑在它上），只是它现在驱动整个
  // CustomScrollView —— 定位偏移差一个头部高度，由事后的
  // Scrollable.ensureVisible 精确校正（见 _jumpToLocatedCard）。
  final _localHeaderMeasureKey = GlobalKey();
  double? _localHeaderExtent;
  final _locateCardKey = GlobalKey();
  String? _locateTargetId; // 需要定位的专辑 id（定位完成后清除）
  String? _highlightedAlbumId; // 高亮中的专辑 id
  Timer? _highlightTimer;
  // 1.54 移动端左边缘右滑呼出抽屉：起手点在左缘 ≤24dp 时累计横向位移
  // 1.99.6（裁决 Q1=B / Q8=A / Q9=A）：移动端从左往右划掉播放栏 = 收起 + 暂停；
  // 任何一次「从暂停变成播放」（含系统媒体键 / 锁屏 / 耳机键）都会把它还原。
  bool _playerBarDismissed = false;
  // 播放栏矩形（用于裁决 Q4=A：手势落在播放栏上时，播放栏的横划优先于左边缘呼出抽屉）
  final _playerBarKey = GlobalKey();

  @override
  void initState() {

    _gridScrollController.addListener(_onGridScroll);
    super.initState();
    // macOS 菜单栏动作转发（导入文件夹/设置/检查更新，1.48）
    if (Platform.isMacOS) {
      const MethodChannel('top.voicehub.hiko/menu')
          .setMethodCallHandler((call) async {
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
    Future.delayed(kPostLaunchScanDelay, () async {
      if (!mounted) return;
      final scanner = ref.read(musicFolderScannerProvider);
      final added = await scanner.scanAll(
        silent: true,
        onProgress: (p) {
          if (!mounted) return;
          activityOverlayController.start(
            label: p.phase == 'walk'
                ? '正在清点文件'
                : p.phase == 'files'
                    ? '正在快速同步音乐目录'
                    : '正在导入新增专辑',
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
    _gridScrollController.removeListener(_onGridScroll);
    _gridScrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _onGridScroll() {
    if (!_isMobileLocalView) return;
    final scrolled = _gridScrollController.hasClients &&
        _gridScrollController.offset > 120;
    if (scrolled != _mobileTopbarTitle) {
      setState(() => _mobileTopbarTitle = scrolled);
    }
  }

  /// 当前视图是否为「移动端本地内容视图」（本地音声/分类/最近播放/收藏夹等）。
  /// 与 build 的 isMobile 同源（Android 宽度断点 + 调试开关），避免第二处口径。
  bool get _isMobileLocalView {
    final isMobile = widget.debugMobileLayout ??
        (Platform.isAndroid
            ? MediaQuery.sizeOf(context).width <= 1000
            : false);
    return isMobile && !_isOnlineView && _view != '统计';
  }

  void _openSettings(BuildContext context, {bool autoCheckUpdate = false}) {
    // 1.99.32 设置壳重做（plan §8.7）：独立页路由（桌面/移动同构全屏页）。
    // 回调不再先 pop——选图/扫描等动作直接在设置页上层发生。
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          autoCheckUpdate: autoCheckUpdate,
          onImportRequested: _importFolder,
          onIncrementalScanRequested: () => _scanPicked(full: false),
          onFullScanRequested: () => _scanPicked(full: true),
          onReorganizeRequested: _reorganizeLibrary,
          onCleanMissingRequested: _cleanMissing,
          onDownloadUpdateRequested: _downloadUpdate,
        ),
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

  /// 防社死隐私模糊开关（1.52）：顶栏按钮与 Cmd/Ctrl+Shift+H 共用。
  ///
  /// 1.99.20 起实现提到 [togglePrivacyBlur]（`online_appearance.dart`）——
  /// Aa 菜单是第三个调用点，那段副作用（隐藏桌面歌词）不能有两份实现。
  void _togglePrivacyBlur() => togglePrivacyBlur(ref);

  Future<void> _importFolder() async {
    if (_importing || activityOverlayController.isActive) return;
    setState(() => _importing = true);
    activityOverlayController.start(label: '正在导入');
    final service = ImportService(ref.read(libraryStoreProvider));
    try {
      final platform = ref.read(platformServiceProvider);
      List<Album> albums;
      // Android:SAF 单树导入(接口方法,事件流式,增量跳过全已知目录);桌面:返回 null 走批量多选
      final knownUrls = <String>{
        for (final a in ref.read(libraryProvider))
          for (final t in a.tracks) t.url,
      };
      final saf = await platform.importAudioFolder(
        known: knownUrls,
        onProgress: (p, t, phase, unit) {
          activityOverlayController.update(
            label: phase == 'walk'
                ? '正在清点文件'
                : phase == 'files'
                    ? '正在扫描音频文件'
                    : '正在导入专辑',
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
      // 全轨无可用标签的专辑（metaFromFolder）：串行查 DLsite 补标题（失败维持文件夹名）。
      // 1.54：移动端跳过自动补全（串行网络拖慢导入），标题不对时手动刮削。
      if (!Platform.isAndroid &&
          ref.read(libraryProvider).any(DlsiteScraper.shouldBackfillTitle)) {
        activityOverlayController.update(label: '正在查询 DLsite 补全标题');
        final fixed = await ref
            .read(scraperProvider)
            .backfillTitles(ref.read(libraryProvider));
        if (fixed > 0) {
          await ref.read(libraryProvider.notifier).load();
        }
      }
      setState(() {
        _view = '本地音声';
        _filter = 'all';
      });
      _showToast(
        albums.isEmpty
            ? '没有在所选文件夹中找到支持的音频文件'
            : '已导入 ${albums.length} 张专辑，已显示在本地音声',
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

  /// 手动扫描用户选中的单个目录（1.99.11）：增量只解析新增/变化，全量重建。
  /// 选中的目录不登记常驻目录；启动静默扫描仍覆盖全部常驻目录。
  Future<void> _scanPicked({required bool full}) async {
    if (activityOverlayController.isActive) return;
    activityOverlayController.start(label: '准备扫描...');
    try {
      final added = await ref
          .read(musicFolderScannerProvider)
          .scanPicked(
            full: full,
            onProgress: (p) {
              activityOverlayController.update(
                label: p.phase == 'walk'
                    ? '正在清点文件'
                    : p.phase == 'files'
                        ? '正在扫描音频文件'
                        : '正在解析组装专辑',
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
    // 1.99.4（裁决 Q4=A）：当前视图在导航配置里被隐藏 → 立即回退到第一个
    // 仍显示的导航视图。只对内置导航视图生效；分类 / 搜索残留视图不受影响。
    final navViews = ref.watch(settingsProvider).navViews;
    if (AppSettings.navViewsAll.contains(_view) && !navViews.contains(_view)) {
      _view = navViews.first;
    }
    final currentSort = ref.watch(settingsProvider.select((s) => s.albumSort));
    // 1.48：排序/过滤走 memo——列表实例与参数不变时复用结果，大库重建不再全量重算；
    // 「统计」视图不走筛选（面板直接聚合全库）；「在线」「在线收藏」的数据来自远程
    // 服务，与本地库无关，同样跳过本地筛选（1.90 / 1.93）
    final filtered = _view == '统计' || _isOnlineView
        ? albums
        : _filterMemo.get(
            albums: albums,
            view: _view,
            filter: _filter,
            query: _query,
            sort: currentSort,
            circleFilter: _personFilterKind == 'circle' ? _personFilterName : null,
            voiceFilter: _personFilterKind == 'voice' ? _personFilterName : null,
            tagFilter: _tagFilter,
          );
    final theme = Theme.of(context);
    // 移动布局仅 Android 触屏（≤1000px，与旧版桥接层一致）；桌面永远桌面布局
    final isMobile = widget.debugMobileLayout ??
        (Platform.isAndroid
            ? MediaQuery.sizeOf(context).width <= 1000
            : false);

    // 1.99.6（裁决 Q8=A）：划掉播放栏后的**还原判据** = 任何一次「暂停 → 播放」的
    // 跳变（点歌、点播放条上的播放键、系统媒体键 / 通知栏 / 耳机线控都算）。
    // 必须用 ref.listen 的 prev/next：ref.watch 只给当前值，分不清「本来就在播」。
    ref.listen<bool>(playbackProvider.select((s) => s.playing), (prev, next) {
      if (prev == false && next == true && _playerBarDismissed) {
        setState(() => _playerBarDismissed = false);
      }
    });

    // 1.99.17 播放页「跳详情」指令；1.99.18 起移动端也走这里（播放页裸 push 的
    // 详情页没有筛选回调）。本地请求：桌面 = 打开详情抽屉；移动 = 走
    // [_openMobileDetail]（它负责处理详情页胶囊的筛选回传）。在线请求只负责
    // 切到在线视图 —— 消费与清空由 OnlineScreen 负责，两处都清会出现
    // 「消费方还没挂载、请求就被抹掉」的时序坑
    ref.listen<String?>(localDetailRequestProvider, (prev, next) {
      if (next == null) return;
      ref.read(localDetailRequestProvider.notifier).state = null;
      for (final a in ref.read(libraryProvider)) {
        if (a.id == next) {
          if (isMobile) {
            // resetStack：播放页那条路要清掉列表以上的历史（1.99.19 裁决 Q2=A），
            // 否则「!」跳过来的详情页会压在旧详情页上，退一次只回到旧详情页
            unawaited(_openMobileDetail(a.id, resetStack: true));
          } else {
            setState(() => _detailAlbum = a);
          }
          break;
        }
      }
    });
    ref.listen<int?>(onlineDetailRequestProvider, (prev, next) {
      if (next == null || _view == '在线') return;
      setState(() => _view = '在线');
    });

    // 播放栏当前是否可见：桌面恒定显示；移动端要求「有正在播放的专辑」且
    // 「没有被左划收起」。详情抽屉的底部留白必须跟着它走（否则收起后抽屉下方
    // 会留一条 58px 的空洞）。
    final playerBarVisible =
        !isMobile ||
        (ref.watch(playbackProvider).album != null && !_playerBarDismissed);

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
        } else if (_handleOnlineBack(allowExit: true)) {
          // 在线模块自己消费掉（清筛选 / 在线收藏退回在线 / 干净状态最小化）
        } else if (_view != '本地音声') {
          setState(() => _view = '本地音声');
        } else {
          SystemNavigator.pop(); // 无浮层 → 最小化/退出
        }
      },
      child: Scaffold(
        // 1.99.33：macOS 标题栏透明 + 全尺寸内容后，body 顶层让出红绿灯区
        body: Padding(
          padding: EdgeInsets.only(top: windowTopInset(context)),
          child: Shortcuts(
          shortcuts: {
            // ⌘O / Ctrl+O 导入（对应旧版菜单「导入音声文件夹」）
            const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
                const _ImportIntent(),
            const SingleActivator(LogicalKeyboardKey.keyO, control: true):
                const _ImportIntent(),
            // Esc 逐层退回：多选 → 详情页 → 抽屉 → 视图（无浮层不退出应用；
            // 空格/方向键播放类快捷键已上提至全局层，1.86）
            const SingleActivator(LogicalKeyboardKey.escape):
                const _CloseOverlayIntent(),
            // ⌘⇧H / Ctrl+Shift+H 防社死隐私模糊（1.52）
            const SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true):
                const _TogglePrivacyBlurIntent(),
            const SingleActivator(
              LogicalKeyboardKey.keyH,
              control: true,
              shift: true,
            ):
                const _TogglePrivacyBlurIntent(),
          },
          child: Actions(
            actions: {
              _ImportIntent: CallbackAction<_ImportIntent>(
                onInvoke: (_) {
                  _importFolder();
                  return null;
                },
              ),
              _CloseOverlayIntent: CallbackAction<_CloseOverlayIntent>(
                onInvoke: (_) {
                  if (_multiMode) {
                    setState(() {
                      _multiMode = false;
                      _multiIds.clear();
                    });
                  } else if (_detailAlbum != null) {
                    setState(() => _detailAlbum = null);
                  } else if (_handleOnlineBack(allowExit: isMobile)) {
                    // 在线模块自己消费掉；桌面 Esc 不退出应用（与旧行为一致）
                  } else if (_view != '本地音声') {
                    setState(() => _view = '本地音声');
                  }
                  return null;
                },
              ),
              _TogglePrivacyBlurIntent: CallbackAction<_TogglePrivacyBlurIntent>(
                onInvoke: (_) {
                  _togglePrivacyBlur();
                  return null;
                },
              ),
            },
            child: SafeArea(
              // 移动端：左边缘右滑呼出抽屉（1.54，安卓惯例）。用 Listener 直接跟踪指针
              //（不进手势竞技场，网格垂直滚动识别器不会吞掉水平拖动）；竖向位移大于
              // 横向即视为滚动放弃呼出。配合 MainActivity 的系统手势排除区使用。
              // 1.99.30：玻璃时代的「全局动态封面光晕」（σ80 氛围模糊）随玻璃
              // 一起退场（plan §9.1 滤波清零锁）；播放氛围由全屏播放页的
              // 封面主色渐变承担。
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: HikoShell(
                          rail: isMobile ? null : _buildRail(navViews),
                          child: _buildMain(
                            filtered,
                            theme,
                            isMobile,
                            currentSort,
                          ),
                        ),
                      ),
                      // 1.54 移动端：未播放任何专辑时整个播放条隐藏，底部导航贴底
                      // 1.99.6：移动端从左往右划掉（收起 + 暂停）后同样隐藏，
                      // 直到重新开始播放（见 build 开头的 ref.listen）
                      if (playerBarVisible)
                        PlayerBar(
                          key: _playerBarKey,
                          compact: isMobile,
                          onDismiss: isMobile ? _dismissPlayerBar : null,
                          onCoverTap: (_) {
                            // 1.79 桌面对齐移动端：点击播放条封面进入全屏播放页
                            // （详情抽屉仍可从专辑卡片/统计页进入）
                            // 1.99.29：从播放条封面形变进入（英雄时刻 B）
                            Navigator.of(context)
                                .push(FullscreenPlayerRoute(heroTag: 'bar-cover'));
                          },
                        ),
                    ],
                  ),
                  // 详情遮罩（桌面）：点击抽屉外区域关闭（不阻断抽屉内交互，
                  // Stack hit test 短路保证上层抽屉命中时遮罩不参与）；遮罩非按钮不加水波纹
                  if (_detailAlbum != null && !isMobile)
                    Positioned.fill(
                      child: Listener(
                        // 1.82 遮罩会吞掉滚轮命中（InkWell 不处理 PointerSignal），
                        // 转发给主网格：抽屉开着时指针悬停主界面仍可滚动专辑列表
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent) {
                            _gridScrollController.position
                                .pointerScroll(event.scrollDelta.dy);
                          }
                        },
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
                    ),
                  // 详情：桌面右侧面板（M3ESheet.side 480）/ 移动底部面板
                  if (_detailAlbum != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      // 移动端：播放条显示时留播放条+导航位，未播放/已划掉只留底部导航
                      // （1.54 / 1.99.6）
                      bottom: isMobile ? (playerBarVisible ? 118 : 60) : 0,
                      left: isMobile ? 0 : null,
                      // 桌面：面板宽 420（1.99.44 裁决，与在线详情统一），
                      // 窗口过窄时收缩，避免溢出右缘
                      width: isMobile
                          ? null
                          : MediaQuery.sizeOf(context).width
                                .clamp(200.0, kHikoDetailPanelWidth),
                      child: DetailDrawer(
                        album: _detailAlbum!,
                        onClose: () => setState(() => _detailAlbum = null),
                        sheetVariant: isMobile
                            ? M3ESheetVariant.bottom
                            : M3ESheetVariant.side,
                        // 1.81 抽屉社团/声优胶囊点选筛选（抽屉保持打开，结果线显示分色胶囊）
                        personFilterKind: _personFilterKind,
                        personFilterName: _personFilterName,
                        onPersonFilter: (kind, name) => setState(() {
                          _personFilterKind = kind;
                          _personFilterName = name;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ),
        // 移动端底部导航（M3E NavigationBar，1.99.27）
        bottomNavigationBar: isMobile ? _buildNavBar(navViews) : null,
      ),
    );
  }

  /// 数据全来自远程服务端的视图（不走本地库筛选，也不参与本地网格）
  bool get _isOnlineView => _view == '在线' || _view == '在线收藏';

  /// 当前 `_view` 是不是用户分类（决定分类条是否出现）。
  bool get _isCategoryView =>
      ref.watch(categoriesProvider).any((c) => c.name == _view);

  // ── 壳层（1.99.27）────────────────────────────────────────────────

  /// 导航目的地：一份数据，rail 与 bar 共用。
  List<M3ENavigationDestination> _navDestinations(List<String> navViews) {
    final albums = ref.watch(libraryProvider);
    final favoriteCount = albums.where((a) => a.favorite).length;
    final playedCount = albums.where((a) => a.lastPlayedAt != null).length;
    final onlineLoggedIn = ref.watch(onlineLoggedInProvider);
    final onlineFavoriteCount =
        ref.watch(onlineFavoritesProvider).index.countOf(null);
    return <M3ENavigationDestination>[
      for (final view in navViews)
        M3ENavigationDestination(
          label: view,
          icon: hikoNavIcons[view] ?? hikoNavFallbackIcon,
          selectedIcon:
              hikoNavSelectedIcons[view] ?? hikoNavFallbackSelectedIcon,
          badge: switch (view) {
            '本地音声' => albums.length,
            '收藏夹' => favoriteCount,
            '最近播放' => playedCount,
            '在线收藏' => onlineLoggedIn ? onlineFavoriteCount : null,
            _ => null,
          },
        ),
    ];
  }

  /// 桌面左侧导航栏。
  Widget _buildRail(List<String> navViews) => M3ENavRail(
        destinations: _navDestinations(navViews),
        selectedIndex: navViews.indexOf(_view),
        onSelected: (index) => setState(() => _view = navViews[index]),
        header: _railHeader(),
        trailing: M3ENavRailAction(
          icon: Icons.settings_outlined,
          label: '设置',
          onTap: () => _openSettings(context),
        ),
      );

  Widget _railHeader() {
    // 1.99.47（D-02）：全站最后一个写死字号与色值的导航块收进 M3E。
    // 品牌 mark 用 `primary` 圆角块 + `onPrimary` 字；`Hiko` 走 titleSmall，
    // 副标走 labelSmall + onSurfaceVariant（不再是 #888B92）。
    final theme = M3ETheme.of(context);
    final logo = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: theme.colors.primary,
        borderRadius: M3EShape.radius(M3EShape.sm),
      ),
      child: Center(
        child: Text(
          'K',
          style: theme.type.titleMedium.copyWith(
            color: theme.colors.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    if (hikoWindowSizeOf(context) != HikoWindowSize.expanded) return logo;
    return Row(
      children: <Widget>[
        logo,
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Hiko',
              style: theme.type.titleSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colors.onSurface,
              ),
            ),
            Text(
              '音声收藏室',
              style: theme.type.labelSmall.copyWith(
                color: theme.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 移动端底部导航。
  ///
  /// 折叠规则（1.99.27）：最多 5 格，其中「正在播放」常驻 1 格
  /// （1.99.6 裁决 Q7=A 的「一定找得回来」不能丢），末尾 1 格「更多」——
  /// 余下的目的地与「设置」都收进更多面板。所以可见导航项 =
  /// min(navViews, 3)。
  Widget _buildNavBar(List<String> navViews) {
    final all = _navDestinations(navViews);
    final folded = foldDestinations(all, reservedSlots: 1);
    final playerReady = ref.watch(playbackProvider).album != null;
    final items = <M3ENavigationDestination>[
      ...folded.visible,
      M3ENavigationDestination(
        label: '正在播放',
        icon: Icons.play_circle_outline,
        selectedIcon: Icons.play_circle,
        enabled: playerReady,
      ),
      const M3ENavigationDestination(
        label: '更多',
        icon: Icons.more_horiz,
        selectedIcon: Icons.more_horiz,
      ),
    ];
    var selectedIndex = -1;
    for (var i = 0; i < folded.visible.length; i++) {
      if (folded.visible[i].label == _view) {
        selectedIndex = i;
        break;
      }
    }
    return M3ENavBar(
      destinations: items,
      selectedIndex: selectedIndex,
      onSelected: (index) {
        if (index == items.length - 1) {
          unawaited(_openMoreSheet(folded.overflow));
          return;
        }
        if (index == items.length - 2) {
          // 「正在播放」：有播放条时从其封面形变进入，无播放条则普通转场
          //（目标 tag 无来源时 Hero 静默跳过，1.99.29）
          Navigator.of(context)
              .push(FullscreenPlayerRoute(heroTag: 'bar-cover'));
          return;
        }
        setState(() => _view = folded.visible[index].label);
      },
    );
  }

  /// 「更多」面板：放不下的目的地 + 设置。
  Future<void> _openMoreSheet(List<M3ENavigationDestination> overflow) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.m3e.colors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(M3EShape.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: M3EList(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: <Widget>[
            for (final destination in overflow)
              M3EListItem(
                title: destination.label,
                leading: Icon(destination.icon),
                selected: destination.label == _view,
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _view = destination.label);
                },
              ),
            M3EListItem(
              title: '设置',
              leading: const Icon(Icons.settings_outlined),
              onTap: () {
                Navigator.pop(sheetContext);
                _openSettings(context);
              },
            ),
          ],
        ),
      ),
    );
  }


  /// 从左往右划掉播放栏（1.99.6，裁决 Q1=B）：**收起 + 暂停**。
  ///
  /// 只收起不暂停会留下「音频在放、却没有任何停止入口」的状态，用户明确要暂停。
  /// 还原交给 [build] 里的 `ref.listen`：任何一次「暂停 → 播放」都还原，
  /// 所以暂停这一步本身也是还原路径的前提（见裁决 Q8=A）。
  void _dismissPlayerBar() {
    if (!_playerBarDismissed) setState(() => _playerBarDismissed = true);
    // 本来就没在播（例如已被系统 / 耳机键暂停）就别再发一次 pause
    if (ref.read(playbackProvider).playing) {
      unawaited(ref.read(playbackProvider.notifier).pause());
    }
  }

  /// 在线模块的「返回」语义（1.99.5，裁决 Q2=B）。
  ///
  /// 旧兜底是「不在本地音声就切回本地音声」—— 于是用户在**带着筛选的在线页**
  /// 右滑返回时，会直接被扔到本地专辑页（实机反馈的 bug，也说不清自己怎么过来的）。
  /// 现在：
  /// - `在线`：**只清筛选**（标签 / 社团 / 搜索词 / 字幕 / 分级 → 回最新榜），
  ///   本来就在「在线主界面」（最新榜 + 无筛选）时，若 [allowExit] 则最小化应用；
  /// - `在线收藏`：**退回在线**（它就是从在线进去的，同一模块内退一层，
  ///   而不是跳到本地音声）；
  /// - 其它视图：返回 false，交给调用点的旧兜底（本地视图的切换逻辑不变）。
  ///
  /// [allowExit] 的区别只在「干净状态下要不要退出应用」：安卓返回键与 Esc
  /// 共用这段逻辑，但 Esc 在桌面上不该关掉应用。
  bool _handleOnlineBack({required bool allowExit}) {
    if (_view == '在线') {
      if (!ref.read(onlineBrowseProvider).isAtOnlineHome) {
        unawaited(ref.read(onlineBrowseProvider.notifier).resetToLatest());
      } else if (allowExit) {
        SystemNavigator.pop();
      }
      return true;
    }
    if (_view == '在线收藏') {
      setState(() => _view = '在线');
      return true;
    }
    return false;
  }

  /// 移动端打开全屏详情页；详情页胶囊点选时回传 ('circle'|'voice', 名字) 应用为列表筛选。
  ///
  /// [resetStack] 只在「播放页跳详情」那一次为真（1.99.19 裁决 Q2=A）：
  /// 那次要求列表以上不留历史，一次返回回到列表；本地网格点卡片保持普通压栈。
  Future<void> _openMobileDetail(String albumId, {bool resetStack = false}) async {
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<(String, String)>(
      builder: (context) => AlbumDetailScreen(albumId: albumId),
    );
    final picked = await (resetStack
        ? pushDetailAboveList<(String, String)>(navigator, route)
        : navigator.push(route));
    if (picked != null && mounted) {
      setState(() {
        _personFilterKind = picked.$1;
        _personFilterName = picked.$2;
      });
    }
  }

  Widget _buildMain(
    List<Album> filtered,
    ThemeData theme,
    bool isMobile,
    String currentSort,
  ) {
    // 在线视图（1.90）：复用顶栏（面包屑/主题/隐私模糊等），
    // 中间区域完全交给在线页自己管理（入口切换 + 搜索 + 结果网格）。
    if (_view == '在线') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopbar(theme, isMobile),
          Expanded(
            child: OnlineScreen(
              isMobile: isMobile,
              // 账号菜单里的「在线收藏」入口（1.93.0）：视图归属在这个 State，
              // 在线页只上报意图
              onOpenFavorites: () => setState(() => _view = '在线收藏'),
            ),
          ),
        ],
      );
    }
    // 在线收藏（1.93.0，裁决 Q3=A）：同样是纯远程数据，只是换了一个数据源 ——
    // 服务端歌单而不是全站列表
    if (_view == '在线收藏') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopbar(theme, isMobile),
          Expanded(
            child: OnlineFavoritesScreen(
              isMobile: isMobile,
              // 收藏页点卡面标签 → 筛选结果在「在线」那一页，所以先切视图
              // （筛选本身由收藏页自己发起，这里只管视图归属，1.94.0 裁决 Q9=甲）
              onOpenBrowse: () => setState(() => _view = '在线'),
            ),
          ),
        ],
      );
    }
    // 1.99.9 移动端：本地网格视图（本地音声/最近添加/最近播放/收藏夹）的头部
    // 滚动收起 —— hero + 筛选行进滚动 sliver，向下滚走、上滑跟手滑回。
    // 统计视图有自己的滚动体，保持旧结构；桌面端全部不动。
    if (isMobile && _view != '统计') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopbar(theme, isMobile),
          Expanded(
            child: _buildLocalScrollable(filtered, theme, isMobile, currentSort),
          ),
        ],
      );
    }
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
                  onOpenAlbum: (album) {
                    if (isMobile) {
                      // 1.56 移动端：从统计页打开专辑全屏详情
                      _openMobileDetail(album.id);
                    } else {
                      // 桌面端：打开右侧抽屉
                      setState(() => _detailAlbum = album);
                    }
                  },
                )
              : _buildGrid(filtered, theme, isMobile),
        ),
      ],
    );
  }

  /// 移动端本地视图的滚动结构（1.99.9，与在线页同款模式）：
  ///
  /// ```
  /// Stack[
  ///   CustomScrollView[ floating 头部(hero+筛选行+结果行+续播横幅), 瀑布流 sliver ],
  ///   离屏头部副本（量自然高度喂 extent）,
  /// ]
  /// ```
  ///
  /// 与在线页的差别：网格是瀑布流（flutter_staggered_grid_view），sliver 形态
  /// 用同包的 [SliverMasonryGrid]；滚动控制器沿用 [_gridScrollController]，
  /// 「定位当前播放」的 jumpTo 偏移因此差一个头部高度，靠
  /// `Scrollable.ensureVisible` 在下一帧精确校正（跳完必然可见，误差只影响
  /// 一次粗跳的距离）。
  Widget _buildLocalScrollable(
    List<Album> filtered,
    ThemeData theme,
    bool isMobile,
    String currentSort,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _localHeaderMeasureKey.currentContext;
      final h = ctx?.size?.height;
      if (h != null && h > 0 && (h - (_localHeaderExtent ?? 0)).abs() > 0.5) {
        setState(() => _localHeaderExtent = h);
      }
    });

    final headerColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHero(theme, filtered.length, isMobile),
        _buildToolbar(theme, isMobile, filtered, currentSort),
        _buildResultsLine(theme, filtered.length),
        _buildResumeBanner(theme, isMobile),
      ],
    );

    final settings = ref.watch(settingsProvider);
    final fixedColumns = settings.mobileGridColumns.toInt();

    return Stack(
      children: [
        Positioned.fill(
          child: CustomScrollView(
            controller: _gridScrollController,
            slivers: [
              // 头部挂成浮层头部（1.99.25：`preferredSize` 必须声明 0 的理由
              // 见 M3EFloatingHeader 里的长注释，别改回去）
              M3EFloatingHeader(
                extent: _localHeaderExtent ?? 300,
                child: headerColumn,
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: _buildGridEmptyContent(theme)),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  sliver: SliverMasonryGrid(
                    gridDelegate: fixedColumns > 0
                        ? SliverSimpleGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: fixedColumns,
                          )
                        : const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 240,
                          ),
                    mainAxisSpacing: 25,
                    crossAxisSpacing: 18,
                    delegate: SliverChildBuilderDelegate(
                      childCount: filtered.length,
                      (context, index) =>
                          _buildAlbumCard(filtered[index], isMobile, settings),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Offstage(
            offstage: true,
            child: KeyedSubtree(
              key: _localHeaderMeasureKey,
              child: headerColumn,
            ),
          ),
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
    final trackNo =
        candidate.resumeTrackIndex.clamp(0, candidate.tracks.length - 1) + 1;
    return Padding(
      // 顶部留白：上一行是「显示 N 张专辑」（自带 0 底距），0 顶距会贴死
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 48,
        10,
        isMobile ? 16 : 48,
        12,
      ),
      child: M3ECard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () {
          ref
              .read(playbackProvider.notifier)
              .playAlbum(
                candidate,
                index: candidate.resumeTrackIndex,
                startPosition: candidate.resumePosition,
              );
          _showToast('已从上次断点继续播放');
        },
        semanticLabel: '继续收听 ${candidate.title}',
        child: Row(
          children: <Widget>[
            ClipRRect(
              // 卡片 16 圆角、内边距 8，按 inner = outer − padding 应取 8；
              // 封面只有 40dp，8 偏方，沿用详情卡的 md(12) 与本地/在线卡一致。
              borderRadius: M3EShape.radius(M3EShape.md),
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
                children: <Widget>[
                  Text(
                    '继续收听',
                    style: M3ETheme.of(context).type.labelSmall.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: M3ETheme.of(context).colors.primary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${candidate.title} · 上次听到第 $trackNo 轨 ${formatTime(candidate.resumePosition)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: M3ETheme.of(context).type.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: M3ETheme.of(context).colors.onSurface,
                        ),
                  ),
                ],
              ),
            ),
            M3EIconButton(
              icon: Icons.close_rounded,
              tooltip: '关闭',
              size: M3EIconButtonSize.small,
              onPressed: () =>
                  setState(() => _resumeDismissed.add(candidate.id)),
            ),
          ],
        ),
      ),
    );
  }

  /// 「最近播放」视图点卡续播（1.99.3）。断点缺失（旧数据播过但没落上断点）
  /// 时退化为从头播放，不空手而归。
  void _resumeAlbum(Album album) {
    if (album.tracks.isEmpty) return;
    final hasResume = album.resumeTrackIndex >= 0;
    ref.read(playbackProvider.notifier).playAlbum(
          album,
          index: hasResume ? album.resumeTrackIndex : 0,
          startPosition: hasResume ? album.resumePosition : 0,
        );
    _showToast(hasResume ? '已从上次断点继续播放' : '从头开始播放');
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
  /// 专辑不在当前列表（筛选/其它视图/统计）时先清筛选切回「本地音声」
  void _locatePlayingAlbum() {
    final target = ref.read(playbackProvider).album;
    if (target == null) return;
    final inCurrentView =
        _view != '统计' &&
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
        _filter = 'all';
        _view = '本地音声';
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
    final isMobile = Platform.isAndroid ? size.width <= 1000 : false;
    final result = locateAlbumInMasonry(
      albums: _filterMemo.get(
        albums: ref.read(libraryProvider),
        view: _view,
        filter: _filter,
        query: _query,
        sort: settings.albumSort,
        circleFilter: _personFilterKind == 'circle' ? _personFilterName : null,
        voiceFilter: _personFilterKind == 'voice' ? _personFilterName : null,
        tagFilter: _tagFilter,
      ),
      albumId: albumId,
      metrics: MasonryLayoutMetrics(
        // 与 _buildGrid 列数决策保持一致（1.54 移动端独立档位也参与定位估算）
        fixedCrossAxisCount: isMobile
            ? settings.mobileGridColumns.round()
            : (settings.gridColumns > 0 ? settings.gridColumns.round() : null),
        maxCrossAxisExtent: isMobile ? 240 : 260,
        viewportWidth: size.width,
        horizontalPadding:
            (isMobile ? 16 : 48) * 2 +
            (isMobile ? 0 : hikoRailWidthOf(context)),
        showScrapedTags: settings.showScrapedTags,
      ),
    );
    if (!result.found) {
      setState(() => _locateTargetId = null);
      return;
    }
    final position = _gridScrollController.position;
    // 1.99.9 移动端网格进了 CustomScrollView，网格自己的坐标前面还压着
    // 滚动收起的头部；桌面端恒为 0（_localHeaderExtent 不参与）
    final headerExtent = _localHeaderExtent ?? 0;
    _gridScrollController.jumpTo(
      (result.scrollOffset - 24 + headerExtent)
          .clamp(0.0, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _locateCardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: M3ETheme.of(context)
              .motion
              .duration(M3ESpringType.spatial, M3ESpringSpeed.fast),
          alignment: 0.15,
        );
      }
      _highlightTimer?.cancel();
      setState(() => _highlightedAlbumId = albumId);
      _highlightTimer = Timer(kLocateHighlightDuration, () {
        if (!mounted) return;
        setState(() {
          _highlightedAlbumId = null;
          _locateTargetId = null;
        });
      });
    });
  }

  Widget _buildTopbar(ThemeData theme, bool isMobile) {
    // 1.99.20（裁决「两个在线视图都收起」）：移动端在线视图（在线 / 在线收藏）
    // 顶栏整行收起 —— 那一排在移动端本来就只剩 4 个图标按钮，却是整屏最高处
    // 最占地的一行。其中「定位当前播放」「随机播放」都只作用于**本地库**
    // （随机播放是盲选一张本地专辑），在在线页毫无意义却各占一格；
    // 「切换主题」「防社死」有用，已并进 Aa 菜单（见 OnlineAaMenu）。
    // 整行返回零高度、不占空间（裁决：彻底不占高度）。
    // 桌面端宽度富裕，顶栏原样保留。
    if (isMobile && _isOnlineView) return const SizedBox.shrink();

    // 1.99.39：动作按钮统一 M3EIconButton（40dp 视觉 / 48dp 热区），
    // 桌面与移动同一套；原先移动端用 24dp IconButton、桌面 18dp，两套尺寸。
    final actionButtons = <Widget>[
      M3EIconButton(
        icon: Icons.center_focus_strong_rounded,
        tooltip: '定位当前播放',
        onPressed: ref.watch(playbackProvider).album == null
            ? null
            : _locatePlayingAlbum,
      ),
      M3EIconButton(
        icon: ref.watch(settingsProvider).theme == 'dark'
            ? Icons.dark_mode_outlined
            : Icons.light_mode_outlined,
        tooltip: '切换主题',
        onPressed: () {
          final s = ref.read(settingsProvider);
          ref
              .read(settingsProvider.notifier)
              .setTheme(s.theme == 'dark' ? 'light' : 'dark');
        },
      ),
      ValueListenableBuilder<bool>(
        valueListenable: privacyBlur,
        builder: (_, blurred, _) => M3EIconButton(
          icon: blurred
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          tooltip: blurred ? '关闭隐私模糊' : '隐私模糊（⌘⇧H）',
          onPressed: _togglePrivacyBlur,
        ),
      ),
      M3EIconButton(
        icon: Icons.shuffle_rounded,
        tooltip: '随机播放',
        onPressed: _playRandomAlbum,
      ),
      // 桌面端保留原有的导入按钮
      if (!isMobile) ...[
        const SizedBox(width: 4),
        M3EButton(
          label: '导入',
          variant: M3EButtonVariant.tonal,
          size: M3EButtonSize.small,
          icon: const Icon(Icons.upload),
          onPressed: _importFolder,
        ),
      ],
    ];

    if (!isMobile) {
      // 1.99.31 M3EAppBar.small：64dp，面包屑为中轴标题（plan §8.1）
      return M3EAppBar.small(
        title: Row(
          children: <Widget>[
            Text(
              '音声库',
              style: M3ETheme.of(context).type.labelLarge.copyWith(
                    color: M3ETheme.of(context).colors.onSurfaceVariant,
                  ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '/',
                style: M3ETheme.of(context).type.labelLarge.copyWith(
                      color: M3ETheme.of(context)
                          .colors
                          .onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
              ),
            ),
            Text(
              _view,
              style: M3ETheme.of(context).type.labelLargeEmphasized.copyWith(
                    color: M3ETheme.of(context).colors.onSurface,
                  ),
            ),
          ],
        ),
        actions: actionButtons,
      );
    }

    // 1.99.39：移动顶栏改用 M3EAppBar.small（64dp、titleMedium、48dp 动作热区）。
    // 外层保留 ColoredBox：顶栏必须垫与内容一致的不透明底色（1.99.24 锁定）。
    // 大标题滚出视口后浮现同名小标题（1.99.32 折叠签名），过渡走 M3EMotion。
    final motion = M3ETheme.of(context).motion;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: M3EAppBar.small(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        title: AnimatedOpacity(
          opacity: _mobileTopbarTitle ? 1 : 0,
          duration:
              motion.duration(M3ESpringType.effects, M3ESpringSpeed.normal),
          child: Text(_view),
        ),
        actions: actionButtons,
      ),
    );
  }
  Widget _buildHero(ThemeData theme, int resultCount, bool isMobile) {
    final m3e = M3ETheme.of(context);
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
                // 1.54 移动端精简：去掉眉题与描述文案，只留一行标题（省出列表可视区）
                if (!isMobile) ...[
                  Text(
                    'PERSONAL LIBRARY',
                    style: m3e.type.labelSmall.copyWith(
                      letterSpacing: 1.7,
                      fontWeight: FontWeight.w700,
                      color: m3e.colors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  _view,
                  style: (isMobile
                          ? m3e.type.headlineSmallEmphasized
                          : m3e.type.headlineLargeEmphasized)
                      .copyWith(color: m3e.colors.onSurface),
                ),
                if (!isMobile) ...[
                  const SizedBox(height: 6),
                  Text(
                    '把每一次心动、每一段陪伴，都放进自己的声音收藏室。',
                    style: m3e.type.bodyMedium
                        .copyWith(color: m3e.colors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (!isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '已收藏',
                  style: m3e.type.labelSmall
                      .copyWith(color: m3e.colors.onSurfaceVariant),
                ),
                Text(
                  '$favCount',
                  style: m3e.type.displaySmallEmphasized.copyWith(
                    color: m3e.colors.primary,
                  ),
                ),
                Text(
                  '张专辑',
                  style: m3e.type.labelSmall
                      .copyWith(color: m3e.colors.onSurfaceVariant),
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
          // 分类筛选条（1.99.27）：从侧栏迁到首页。只在「本地音声」或
          // 某个分类视图下出现 —— 它表达的是「同一目的地的视图切换」，
          // 与 rail 上的目的地是两层不同的东西（见 §8.2 裁决 P3）。
          if (_view == AppSettings.navViewHome || _isCategoryView) ...[
            HikoCategoryChips(
              activeView: _view,
              onSelected: (view) => setState(() => _view = view),
            ),
            const SizedBox(height: 10),
          ],
          // Wrap（1.99.15）：加标签入口后窄屏一行放不下，允许换行
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 筛选组（M3E 连通式按钮组，1.99.28）
              M3EButtonGroup(
                labels: const <String>['全部', '未听完', '已收藏'],
                selectedIndex: switch (_filter) {
                  'unplayed' => 1,
                  'favorite' => 2,
                  _ => 0,
                },
                onSelected: (index) => setState(() {
                  _filter = switch (index) {
                    1 => 'unplayed',
                    2 => 'favorite',
                    _ => 'all',
                  };
                }),
              ),
              // 标签筛选入口（1.99.28：M3E chip）
              M3EChip(
                label: _tagFilter ?? '标签',
                selected: _tagFilter != null,
                leading: const Icon(Icons.sell_outlined, size: 16),
                showCheckmark: false,
                onTap: _showTagFilterDialog,
              ),
              // 排序
              _SortSelector(
                currentSort: currentSort,
                isMobile: isMobile,
                onSelected: (val) =>
                    ref.read(settingsProvider.notifier).setAlbumSort(val),
              ),
              // 多选（1.99.28）
              M3EChip(
                label: _multiMode ? '退出多选' : '多选',
                selected: _multiMode,
                leading: Icon(
                  _multiMode ? Icons.close : Icons.checklist_rounded,
                  size: 16,
                ),
                showCheckmark: false,
                onTap: () {
                  setState(() {
                    _multiMode = !_multiMode;
                    _multiIds.clear();
                  });
                },
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
                    style: M3ETheme.of(context).type.bodyMedium.copyWith(
                          color: M3ETheme.of(context).colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 4),
                  M3EButton(
                    label: '全选',
                    variant: M3EButtonVariant.outlined,
                    size: M3EButtonSize.small,
                    onPressed: () {
                      setState(
                        () => _multiIds.addAll(filtered.map((a) => a.id)),
                      );
                    },
                  ),
                  M3EButton(
                    label: '设置分类',
                    variant: M3EButtonVariant.tonal,
                    size: M3EButtonSize.small,
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _setCategoryForSelected(Set.of(_multiIds)),
                  ),
                  M3EButton(
                    label: '刮削标签',
                    variant: M3EButtonVariant.tonal,
                    size: M3EButtonSize.small,
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () =>
                              _scrapeSelected(Set.of(_multiIds), force: false),
                  ),
                  M3EButton(
                    label: '设置星级',
                    variant: M3EButtonVariant.tonal,
                    size: M3EButtonSize.small,
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _setRatingForSelected(Set.of(_multiIds)),
                  ),
                  M3EButton(
                    label: '删除所选',
                    variant: M3EButtonVariant.tonal,
                    size: M3EButtonSize.small,
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _deleteSelected(false),
                  ),
                  M3EButton(
                    label: '删除所选及源文件',
                    variant: M3EButtonVariant.destructive,
                    size: M3EButtonSize.small,
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _deleteSelected(true),
                  ),
                  M3EButton(
                    label: '取消',
                    variant: M3EButtonVariant.text,
                    size: M3EButtonSize.small,
                    onPressed: () => setState(() {
                      _multiMode = false;
                      _multiIds.clear();
                    }),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsLine(ThemeData theme, int count) {
    final hasFilter = _filter != 'all' || _view != '本地音声';
    final hasPersonFilter = _personFilterName != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 8, 48, 0),
      child: Row(
        children: [
          if (hasPersonFilter) ...[
            _buildPersonFilterChip(theme),
            const SizedBox(width: 8),
          ],
          Text(
            '显示 $count 张专辑',
            style: M3ETheme.of(context).type.labelMedium.copyWith(
                  color: M3ETheme.of(context).colors.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          if (hasFilter || hasPersonFilter)
            M3EButton(
              label: '清除筛选',
              variant: M3EButtonVariant.text,
              size: M3EButtonSize.small,
              onPressed: () => setState(() {
                _filter = 'all';
                _view = '本地音声';
                _personFilterKind = null;
                _personFilterName = null;
              }),
            ),
        ],
      ),
    );
  }

  /// 1.77 详情页胶囊回传筛选的可关闭标记（社团紫 / 声优蓝）
  ///
  /// 1.99.47：色值改用 `M3ESemantic.circleTint` / `M3ESemantic.voiceTint`（页面里不再有字面 hex），
  /// 形状收到全圆 + `labelMedium`；关闭钮走 `M3EPressable`（原来是自己套 InkWell）。
  Widget _buildPersonFilterChip(ThemeData theme) {
    final isCircle = _personFilterKind == 'circle';
    final color = isCircle ? M3ESemantic.circleTint : M3ESemantic.voiceTint;
    final m3e = M3ETheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: M3EShape.radius(M3EShape.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${isCircle ? "社团" : "声优"}：$_personFilterName',
            style: m3e.type.labelMedium.copyWith(color: color),
          ),
          const SizedBox(width: 2),
          M3EPressable(
            onTap: () => setState(() {
              _personFilterKind = null;
              _personFilterName = null;
            }),
            borderRadius: M3EShape.radius(M3EShape.full),
            pressScale: 0.9,
            semanticLabel: '清除人物筛选',
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Album> filtered, ThemeData theme, bool isMobile) {
    // 1.43：每行专辑数设置仅桌面端生效；1.54：移动端用独立档位 2/3/4（默认 2）
    final settings = ref.watch(settingsProvider);
    final fixedColumns = isMobile
        ? settings.mobileGridColumns.toInt()
        : (settings.gridColumns > 0 ? settings.gridColumns.toInt() : 0);
    if (filtered.isEmpty) {
      return Center(child: _buildGridEmptyContent(theme));
    }
    return MasonryGridView.builder(
      controller: _gridScrollController,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 48,
        16,
        isMobile ? 16 : 48,
        24,
      ),
      gridDelegate: fixedColumns > 0
          ? SliverSimpleGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: fixedColumns,
            )
          : SliverSimpleGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: isMobile ? 240 : 260,
            ),
      mainAxisSpacing: 25,
      crossAxisSpacing: 18,
      itemCount: filtered.length,
      itemBuilder: (context, index) =>
          _buildAlbumCard(filtered[index], isMobile, settings),
    );
  }

  /// 单张专辑卡的装配（box 网格与移动端 sliver 网格共用，1.99.9）
  Widget _buildAlbumCard(Album album, bool isMobile, AppSettings settings) {
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
        } else if (_view == '最近播放') {
          // 最近播放视图（1.99.3）：点卡即从断点续播 —— 这个视图的意义
          // 就是少一次点击；详情走右键 / 长按菜单
          _resumeAlbum(album);
        } else if (isMobile) {
          // 1.56 移动端：点击卡片进入全屏详情页；1.77 接收胶囊回传筛选
          _openMobileDetail(album.id);
        } else {
          // 桌面端：打开右侧抽屉
          setState(() => _detailAlbum = album);
        }
      },
      onContextMenu: (position) => _showContextMenu(album, position),
    );
  }

  /// 网格空态文案（box 网格与移动端 sliver 共用，1.99.9）
  Widget _buildGridEmptyContent(ThemeData theme) {
    final empty = ref.watch(libraryProvider).isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          empty ? '还没有导入任何音声' : '没有找到匹配的音声',
          style: M3ETheme.of(context).type.titleSmall.copyWith(
                color: M3ETheme.of(context).colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          empty ? '点击右上角「导入」按钮，选择你的音声文件夹' : '试试其他关键词或清除筛选条件',
          style: M3ETheme.of(context).type.bodySmall.copyWith(
                color: M3ETheme.of(context).colors.onSurfaceVariant,
              ),
        ),
      ],
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
        const HikoContextMenuItem(
          value: 'edit',
          label: '编辑作品信息',
          icon: Icons.edit_outlined,
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
        case 'edit':
          _showEditAlbumDialog(album);
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

  /// 手动编辑作品信息（1.99.3）：刮削认错 RJ / 文件名脏数据时手改
  /// 标题、声优、社团。分类走「设置分类」入口（那里有现成的列表 UX）。
  /// 标签筛选对话框（1.99.15）：基准集 = 当前视图/过滤（不含标签筛选），
  /// 聚合刮削标签按使用数倒序，顶部搜索过滤，默认展示 Top 30。
  Future<void> _showTagFilterDialog() async {
    final albums = ref.read(libraryProvider);
    final settings = ref.read(settingsProvider);
    final base = _filterMemo.get(
      albums: albums,
      view: _view,
      filter: _filter,
      query: _query,
      sort: settings.albumSort,
      circleFilter: _personFilterKind == 'circle' ? _personFilterName : null,
      voiceFilter: _personFilterKind == 'voice' ? _personFilterName : null,
      tagFilter: null,
    );
    final tags = aggregateTags(base);
    var search = '';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
        final theme = M3ETheme.of(context);
        final filtered = tags
            .where(
              (e) =>
                  search.isEmpty ||
                  e.$1.toLowerCase().contains(search.toLowerCase()),
            )
            .take(30)
            .toList();
        return M3EDialog(
          maxWidth: 420,
          title: '按标签筛选',
          scrollable: false,
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '搜索标签',
                    prefixIcon: Icon(Icons.search, size: 16),
                  ),
                  onChanged: (v) => setDialogState(() => search = v),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    if (_tagFilter != null)
                      M3EListItem(
                        title: '清除标签筛选（当前：$_tagFilter）',
                        leading: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: theme.colors.error,
                        ),
                        onTap: () {
                          setState(() => _tagFilter = null);
                          Navigator.pop(context);
                        },
                      ),
                    for (final (name, count) in filtered)
                      M3EListItem(
                        title: name,
                        subtitle: '$count 张',
                        selected: name == _tagFilter,
                        onTap: () {
                          setState(() => _tagFilter = name);
                          Navigator.pop(context);
                        },
                      ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          albums.any((a) => a.tags.isNotEmpty)
                              ? '没有匹配的标签'
                              : '当前库还没有刮削标签',
                          textAlign: TextAlign.center,
                          style: theme.type.bodyMedium.copyWith(
                            color: theme.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
        },
      ),
    );
  }

  /// `updateAlbum` 写回后筛选、统计、详情页都读库，立刻生效。
  Future<void> _showEditAlbumDialog(Album album) async {
    final titleController = TextEditingController(text: album.title);
    final artistController = TextEditingController(text: album.artist);
    final circleController = TextEditingController(text: album.albumArtist);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => M3EDialog(
        maxWidth: 420,
        title: '编辑作品信息',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            TextField(
              controller: artistController,
              decoration: const InputDecoration(labelText: '声优'),
            ),
            TextField(
              controller: circleController,
              decoration: const InputDecoration(labelText: '社团（专辑艺术家）'),
            ),
          ],
        ),
        actions: <Widget>[
          M3EButton(
            label: '取消',
            variant: M3EButtonVariant.text,
            onPressed: () => Navigator.pop(context, false),
          ),
          M3EButton(
            label: '保存',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final title = titleController.text.trim();
    if (title.isEmpty) {
      _showToast('标题不能为空');
      return;
    }
    await ref.read(libraryProvider.notifier).updateAlbum(
          album.id,
          (a) => a.copyWith(
            title: title,
            artist: artistController.text.trim(),
            albumArtist: circleController.text.trim(),
          ),
        );
    _showToast('已更新作品信息');
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
      _showToast(
        rating > 0
            ? '已为 ${ids.length} 张专辑设为 $rating 星'
            : '已清除 ${ids.length} 张专辑的星级',
      );
    } catch (e) {
      _showToast('设置星级失败：$e');
    }
  }

  Future<void> _setCategoryForSelected(Set<String> ids) async {
    if (ids.isEmpty) return;
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

/// 快捷键 Intent：导入音声文件夹
class _ImportIntent extends Intent {
  const _ImportIntent();
}

/// 快捷键 Intent：Esc 逐层关闭主页内浮层（多选/详情/抽屉/视图）
class _CloseOverlayIntent extends Intent {
  const _CloseOverlayIntent();
}

/// 快捷键 Intent：防社死隐私模糊切换（⌘⇧H / Ctrl+Shift+H，1.52）
class _TogglePrivacyBlurIntent extends Intent {
  const _TogglePrivacyBlurIntent();
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

  @override
  Widget build(BuildContext context) {
    // 1.99.47：自绘胶囊 + `showHikoContextMenu` → `M3EChip` + `M3EMenu`，
    // 与在线排序入口同一件菜单/同一套选中勾（C-09 的「三种 chip」再少一种）。
    return M3EMenu(
      maxWidth: 260,
      builder: (context, controller, child) => M3EChip(
        label: isMobile ? _currentLabel : '排序 · $_currentLabel',
        leading: const Icon(Icons.swap_vert_rounded, size: 16),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      children: <Widget>[
        for (final opt in _sortOptions)
          M3EMenuAction(
            label: opt.$2,
            leadingIcon: opt.$3,
            selected: opt.$1 == currentSort,
            onPressed: () {
              if (opt.$1 != currentSort) onSelected(opt.$1);
            },
          ),
      ],
    );
  }
}
