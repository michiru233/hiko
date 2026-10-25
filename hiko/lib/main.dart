import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/categories_provider.dart';
import 'data/library_provider.dart';
import 'data/online/online_account.dart';
import 'data/settings_store.dart';
import 'playback/audio_handler.dart';
import 'playback/hiko_media_kit_player.dart';
import 'playback/playback_controller.dart';
import 'ui/covers/cover_cache.dart';
import 'ui/covers/cover_color.dart';
import 'ui/global_shortcuts.dart';
import 'ui/m3e/theme/m3e_theme.dart';
import 'ui/m3e/theme/m3e_theme_builder.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/activity_overlay.dart';
import 'ui/widgets/detail_kit.dart';

final GlobalKey<NavigatorState> hikoNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面端播放（macOS & Windows）：经 HikoJustAudioMediaKit（libmpv）路由以支持 64-bit 软增益与防死锁高质量渲染
  if (Platform.isWindows || Platform.isMacOS) {
    HikoJustAudioMediaKit.ensureInitialized(macOS: true, windows: true);
  }
  final container = ProviderContainer();
  // 封面磁盘缓存（Application Support/hiko/covers；失败静默降级纯内存，1.48）
  // 在线封面下载复用刮削代理设置（动态读取，改设置即刻生效，1.90）
  CoverCache.proxyResolver =
      () => container.read(settingsProvider).scrapeProxy;
  unawaited(CoverCache.instance.init());
  // 加载设置与音声库与分类
  await container.read(settingsProvider.notifier).load();
  await container.read(libraryProvider.notifier).load();
  await container.read(categoriesProvider.notifier).load();
  // 在线账号：读磁盘令牌并用它问一次服务端。**不 await** ——
  // 这是网络往返，不该挡住冷启动；UI 侧用 restoring 状态区分「还不知道」与「未登录」。
  unawaited(container.read(onlineAccountProvider.notifier).restore());

  // 音频会话（焦点管理）
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // Android & macOS：audio_service 系统通知、锁屏与右上角控制中心（Now Playing）桥接
  if (Platform.isAndroid || Platform.isMacOS) {
    final handler = HikoAudioHandler(container.read(playbackProvider.notifier));
    await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'top.voicehub.hiko.channel.audio',
        androidNotificationChannelName: '播放控制',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  // Android 13+：首启申请通知权限（已授予/低版本为 no-op,不阻塞启动）
  if (Platform.isAndroid) {
    unawaited(_requestNotificationPermission());
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const HikoApp()),
  );
}

/// 播放通知权限（Android 13+ 运行时申请;移植旧版 KikoeruPlugin 行为）
Future<void> _requestNotificationPermission() async {
  try {
    await const MethodChannel('top.voicehub.hiko/plugin')
        .invokeMethod('requestNotificationPermission');
  } catch (e) {
    debugPrint('[permission] 通知权限申请失败（容忍）: $e');
  }
}

class HikoApp extends ConsumerStatefulWidget {
  const HikoApp({super.key});

  @override
  ConsumerState<HikoApp> createState() => _HikoAppState();
}

class _HikoAppState extends ConsumerState<HikoApp> with WidgetsBindingObserver {
  /// M3E 主题缓存（1.99.26）：`builder` 会随 MediaQuery 变化（键盘、窗口缩放）
  /// 反复重建，而配色生成要跑一整套 HCT 色调板 —— 只有强调色/明暗变了才重算。
  String _m3eCacheKey = '';
  M3EThemeData? _m3eData;

  // 1.99.30 配色种子（plan §9.2）：custom 图片 / system 壁纸的解析是异步 IO，
  // 在这里解一层缓存；解析完成前用预设强调色兜底（§11.2 配色种子锁：静默回退）。
  String _seedRequestedKey = '';
  Color? _resolvedSeed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // 主题模式 = 跟随系统时，系统明暗切换要重建整树
    if (mounted) setState(() {});
  }

  /// 种子解析链：custom（自选图片）> system（macOS 桌面壁纸）> preset（强调色）。
  /// 任一档不可用返回 null，调用方回退强调色，不抛错。
  Future<void> _resolveSeed(AppSettings settings) async {
    Color? seed;
    if (settings.seedSource == 'custom' && settings.backgroundPath.isNotEmpty) {
      seed = await CoverColor.fromFile(settings.backgroundPath);
    } else if (settings.seedSource == 'system') {
      seed = await _systemSeedColor();
    }
    if (!mounted) return;
    setState(() => _resolvedSeed = seed);
  }

  /// 跟随系统：macOS 读当前桌面壁纸文件路径（原生侧 NSWorkspace），
  /// 复用图片取色管线；其余平台暂无来源（Android 动态取色 1.99.31）。
  Future<Color?> _systemSeedColor() async {
    if (!Platform.isMacOS) return null;
    try {
      final path = await const MethodChannel('hiko/system')
          .invokeMethod<String>('wallpaperPath');
      if (path == null || path.isEmpty) return null;
      return await CoverColor.fromFile(path);
    } catch (_) {
      return null;
    }
  }

  M3EThemeData _m3eTheme(AppSettings settings) {
    final key = m3eThemeCacheKey(settings, seed: _resolvedSeed);
    if (_m3eData == null || _m3eCacheKey != key) {
      _m3eCacheKey = key;
      _m3eData = buildM3EThemeData(settings, seed: _resolvedSeed);
    }
    return _m3eData!;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Hiko · 音声库',
      debugShowCheckedModeBanner: false,
      navigatorKey: hikoNavigatorKey,
      theme: buildHikoTheme(settings),
      builder: (context, child) {
        // 全局字号大小响应（1.56）：读取 settings.fontScale，应用 TextScaler 覆盖
        final mediaQuery = MediaQuery.of(context);
        final scaledMediaQuery = mediaQuery.copyWith(
          textScaler: TextScaler.linear(settings.fontScale),
        );
        // 1.99.30（D6）：背景图不再铺底，语义改为「配色种子」——
        // 图片只参与取色（_resolveSeed），根层不再渲染任何背景图层。
        Widget content = child ?? const SizedBox.shrink();
        final seedKey = '${settings.seedSource}|${settings.backgroundPath}';
        if (_seedRequestedKey != seedKey) {
          _seedRequestedKey = seedKey;
          _resolvedSeed = null; // 解析期间先用强调色，避免旧图颜色滞留
          unawaited(_resolveSeed(settings));
        }
        return M3ETheme(
          data: _m3eTheme(settings),
          child: MediaQuery(
            data: scaledMediaQuery,
            // 标签胶囊字号（1.96.0）：挂在根层，本地与在线一次生效 ——
            // `HikoTagChip` 共用一份实现，字号也必须只有一份（裁决 Q2=甲）
            child: HikoTagFontScope(
              fontSize: settings.tagFontSize,
              child: HikoGlobalShortcuts(
                navigatorKey: hikoNavigatorKey,
                child: ActivityOverlayHost(
                  controller: activityOverlayController,
                  child: content,
                ),
              ),
            ),
          ),
        );
      },
      home: const HomeScreen(),
    );
  }
}
