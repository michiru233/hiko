import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dlsite_scraper.dart';
import '../../data/filter.dart';
import '../../data/import_service.dart';
import '../../data/library_provider.dart';
import '../../data/settings_store.dart';
import '../../models/album.dart';
import '../../platform/platform_service.dart';
import '../../utils/rj.dart';
import '../widgets/album_card.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/detail_drawer.dart';
import '../widgets/player_bar.dart';
import '../widgets/settings_dialog.dart';
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
  String _sort = 'recent';
  String _query = '';
  bool _multiMode = false;
  final Set<String> _multiIds = {};
  Album? _detailAlbum;
  bool _sidebarCollapsed = false;
  bool _drawerOpen = false;
  bool _importing = false;
  String _importLabel = '正在导入';
  double _importProgress = 0;
  int _importProcessed = 0;
  int _importTotal = 0;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(onImportRequested: _importFolder),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 3200),
        margin: const EdgeInsets.only(bottom: 96, left: 24, right: 24),
      ));
  }

  Future<void> _importFolder() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _importLabel = '正在导入';
      _importProcessed = 0;
      _importTotal = 0;
      _importProgress = 0;
    });
    final service = ImportService(ref.read(libraryStoreProvider));
    try {
      final platform = ref.read(platformServiceProvider);
      final isAndroid = Platform.isAndroid;
      List<Album> albums;
      if (isAndroid) {
        final android = platform as dynamic;
        albums = await android.importAudioFolder(onProgress: (p, t) {
          if (!mounted) return;
          setState(() {
            _importProcessed = p;
            _importTotal = t;
            _importProgress = t > 0 ? p / t : 0;
          });
        });
      } else {
        // 桌面：批量选择多个文件夹导入（macOS 原生多选；Windows 单选降级）
        final paths = await platform.pickDirectories();
        if (paths == null || paths.isEmpty) return;
        albums = await service.importFolders(paths, onProgress: (p) {
          if (!mounted) return;
          setState(() {
            _importProcessed = p.processed;
            _importTotal = p.total;
            _importProgress = p.total > 0 ? p.processed / p.total : 0;
          });
        });
      }
      if (!mounted) return;
      await ref.read(libraryProvider.notifier).mergeNew(albums);
      setState(() {
        _view = '全部音声';
        _filter = 'all';
        _query = '';
        _searchController.clear();
      });
      _showToast(albums.isEmpty
          ? '没有在所选文件夹中找到支持的音频文件'
          : '已导入 ${albums.length} 张专辑，已显示在全部音声');
    } catch (e) {
      _showToast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _scrapeSelected(Set<String> ids, {required bool force}) async {
    if (ids.isEmpty) return;
    setState(() {
      _importing = true;
      _importLabel = '正在刮削';
      _importProcessed = 0;
      _importTotal = 0;
      _importProgress = 0;
    });
    final scraper = ref.read(scraperProvider);
    try {
      final result = await scraper.scrape(ids, force: force, onProgress: (p, t) {
        if (!mounted) return;
        setState(() {
          _importProcessed = p;
          _importTotal = t;
          _importProgress = t > 0 ? p / t : 0;
        });
      });
      if (!mounted) return;
      await ref.read(libraryProvider.notifier).load();
      if (result.noRj == ids.length) {
        _showToast('所选专辑均未检测到 RJ 号');
        return;
      }
      _showToast(
          '刮削完成：${result.scraped} 张成功，${result.failed} 张失败'
          '${result.noRj > 0 ? '，${result.noRj} 张无 RJ 号' : ''}'
          '${result.skipped > 0 ? '，${result.skipped} 张已刮过跳过' : ''}');
    } catch (e) {
      _showToast('刮削失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final albums = ref.watch(libraryProvider);
    final filtered = filterAlbums(
      albums: albums,
      view: _view,
      filter: _filter,
      query: _query,
      sort: _sort,
    );
    final theme = Theme.of(context);
    // 移动布局仅 Android 触屏（≤1000px，与旧版桥接层一致）；桌面永远桌面布局
    final isMobile =
        Platform.isAndroid ? MediaQuery.sizeOf(context).width <= 1000 : false;

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
                                  onViewChanged: (view) => setState(() => _view = view),
                                  onOpenSettings: () => _openSettings(context),
                                ),
                              ),
                            ],
                            Expanded(child: _buildMain(filtered, theme, isMobile)),
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
                          GestureDetector(
                            onTap: () => setState(() => _drawerOpen = false),
                            child: Container(color: Colors.black.withValues(alpha: 0.35)),
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
                  // Stack hit test 短路保证上层抽屉命中时遮罩不参与）
                  if (_detailAlbum != null && !isMobile)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _detailAlbum = null),
                        behavior: HitTestBehavior.opaque,
                      ),
                    ),
                  // 详情：桌面右侧抽屉 / 移动全屏弹层
                  if (_detailAlbum != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: isMobile ? 118 : 0,
                      left: isMobile ? 0 : null,
                      width: isMobile ? null : 390,
                      child: DetailDrawer(
                        album: _detailAlbum!,
                        onClose: () => setState(() => _detailAlbum = null),
                      ),
                    ),
                  // 导入/刮削进度浮条
                  if (_importing)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: isMobile ? 178 : 92,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF292735),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 34, offset: const Offset(0, 14)),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_importLabel $_importProcessed / $_importTotal 张专辑',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 7),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 280,
                                  height: 4,
                                  child: LinearProgressIndicator(
                                    value: _importProgress,
                                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
                  BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: '全部'),
                  BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: '最近'),
                  BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline_rounded), label: '播放'),
                  BottomNavigationBarItem(icon: Icon(Icons.favorite_border_rounded), label: '收藏'),
                  BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '设置'),
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

  Widget _buildMain(List<Album> filtered, ThemeData theme, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopbar(theme, isMobile),
        _buildHero(theme, filtered.length, isMobile),
        _buildToolbar(theme, isMobile, filtered),
        _buildResultsLine(theme, filtered.length),
        Expanded(child: _buildGrid(filtered, theme, isMobile)),
      ],
    );
  }

  Widget _buildTopbar(ThemeData theme, bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 48, vertical: 14),
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
              icon: Icon(_sidebarCollapsed ? Icons.menu_open : Icons.menu, size: 18),
              tooltip: _sidebarCollapsed ? '显示侧栏' : '隐藏侧栏',
              onPressed: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            ),
          if (!isMobile) ...[
            Text(
              '音声库',
              style: TextStyle(fontSize: 13, color: theme.hintColor),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('/', style: TextStyle(color: theme.hintColor.withValues(alpha: 0.5))),
            ),
          ],
          Text(
            _view,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              ref.watch(settingsProvider).theme == 'dark' ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 18,
            ),
            tooltip: '切换主题',
            onPressed: () {
              final s = ref.read(settingsProvider);
              ref.read(settingsProvider.notifier).setTheme(s.theme == 'dark' ? 'light' : 'dark');
            },
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
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 48, isMobile ? 8 : 20, isMobile ? 16 : 48, isMobile ? 12 : 24),
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
                  style: TextStyle(fontSize: isMobile ? 24 : 30, fontWeight: FontWeight.w700, letterSpacing: -1.2),
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
                Text('已收藏', style: TextStyle(fontSize: 10, color: theme.hintColor)),
                Text(
                  '$favCount',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                    height: 1.1,
                  ),
                ),
                Text('张专辑', style: TextStyle(fontSize: 10, color: theme.hintColor)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme, bool isMobile, List<Album> filtered) {
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
                      hintStyle: TextStyle(fontSize: 13, color: theme.hintColor),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: isMobile
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: theme.dividerColor),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  Platform.isMacOS ? '⌘ K' : 'Ctrl K',
                                  style: TextStyle(fontSize: 10, color: theme.hintColor),
                                ),
                              ),
                            ),
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
                        borderSide: BorderSide(color: theme.colorScheme.primary),
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
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    for (final (key, label) in [('all', '全部'), ('unplayed', '未听完'), ('favorite', '已收藏')])
                      InkWell(
                        onTap: () => setState(() => _filter = key),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: _filter == key ? theme.colorScheme.surface : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _filter == key ? theme.colorScheme.onSurface : theme.hintColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // 排序
              Row(
                children: [
                  if (!isMobile) ...[
                    Text('排序', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                    const SizedBox(width: 8),
                  ],
                  DropdownButton<String>(
                    value: _sort,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
                    items: const [
                      DropdownMenuItem(value: 'recent', child: Text('最近添加')),
                      DropdownMenuItem(value: 'title', child: Text('标题 A-Z')),
                      DropdownMenuItem(value: 'duration', child: Text('时长')),
                    ],
                    onChanged: (v) => setState(() => _sort = v ?? 'recent'),
                  ),
                ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  backgroundColor: _multiMode ? theme.colorScheme.primary : null,
                  foregroundColor: _multiMode ? theme.colorScheme.onPrimary : null,
                  side: BorderSide(color: _multiMode ? theme.colorScheme.primary : theme.dividerColor),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                ),
                child: Text(_multiMode ? '退出多选' : '多选', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
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
                  Text('已选 ${_multiIds.length} 张', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: () {
                      setState(() => _multiIds.addAll(filtered.map((a) => a.id)));
                    },
                    child: const Text('全选', style: TextStyle(fontSize: 11)),
                  ),
                  FilledButton.tonal(
                    onPressed: _multiIds.isEmpty
                        ? null
                        : () => _scrapeSelected(Set.of(_multiIds), force: false),
                    child: const Text('刮削标签', style: TextStyle(fontSize: 11)),
                  ),
                  FilledButton.tonal(
                    onPressed: _multiIds.isEmpty ? null : () => _deleteSelected(false),
                    child: const Text('删除所选', style: TextStyle(fontSize: 11)),
                  ),
                  FilledButton.tonal(
                    onPressed: _multiIds.isEmpty ? null : () => _deleteSelected(true),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD34C44)),
                    child: const Text('删除所选及源文件', style: TextStyle(fontSize: 11)),
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
          Text('显示 $count 张专辑', style: TextStyle(fontSize: 11, color: theme.hintColor)),
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
    if (filtered.isEmpty) {
      final empty = ref.watch(libraryProvider).isEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              empty ? '还没有导入任何音声' : '没有找到匹配的音声',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.hintColor),
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
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 48, 16, isMobile ? 16 : 48, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
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
          album: album,
          multiMode: _multiMode,
          selected: isSelected,
          onTap: () {
            if (_multiMode) {
              setState(() {
                isSelected ? _multiIds.remove(album.id) : _multiIds.add(album.id);
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

  /// 右键/长按菜单：在触发位置（指针/手指）附近弹出，屏幕边缘自动收拢
  void _showContextMenu(Album album, Offset position) {
    // 以触发点为锚点（1x1 锚矩形），showMenu 会自动把菜单收在屏幕内
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final anchor = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: context,
      position: anchor,
      items: [
        if (albumRjCode(album) != null)
          const PopupMenuItem(value: 'scrape', child: Text('刮削 DLsite 标签')),
        if (album.hasLocalFiles)
          const PopupMenuItem(value: 'reveal', child: Text('打开所在文件夹')),
        const PopupMenuItem(value: 'delete-only', child: Text('从库中删除')),
        if (album.hasLocalFiles)
          const PopupMenuItem(
            value: 'delete-files',
            child: Text('删除专辑及源文件', style: TextStyle(color: Color(0xFFD34C44))),
          ),
      ],
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case 'scrape':
          _scrapeSelected({album.id}, force: true);
        case 'reveal':
          ref.read(platformServiceProvider).revealInFolder(album);
        case 'delete-only':
          _deleteSingle(album, false);
        case 'delete-files':
          _deleteSingle(album, true);
      }
    });
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
      _showToast(deleteFiles
          ? '已删除「${album.title}」及 $deletedFiles 个源文件'
          : '已将「${album.title}」从库中删除');
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
          deletedFiles += await ref.read(platformServiceProvider).removeAlbumFiles(a);
        }
      }
      await ref.read(libraryProvider.notifier).removeAlbums(ids);
      setState(() {
        _multiMode = false;
        _multiIds.clear();
      });
      _showToast(deleteFiles
          ? '已删除 $count 张专辑及 $deletedFiles 个源文件'
          : '已从库中删除 $count 张专辑');
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
