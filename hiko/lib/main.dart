import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/categories_provider.dart';
import 'data/library_provider.dart';
import 'data/settings_store.dart';
import 'playback/audio_handler.dart';
import 'playback/hiko_media_kit_player.dart';
import 'playback/playback_controller.dart';
import 'ui/background.dart';
import 'ui/covers/cover_cache.dart';
import 'ui/global_shortcuts.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/activity_overlay.dart';

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

class _HikoAppState extends ConsumerState<HikoApp> {
  String _bgPathRequested = '';

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
        // 自定义背景（1.84）：根层铺「底色 + 图片 + 薄纱」，Navigator 之下，
        // Scaffold 透明即透出（外观区里未启用时零开销）。
        // 背景图经 loadBackgroundImage 一次性解码常驻（1.86），路径变更时重载。
        Widget content = child ?? const SizedBox.shrink();
        if (_bgPathRequested != settings.backgroundPath) {
          _bgPathRequested = settings.backgroundPath;
          unawaited(loadBackgroundImage(settings.backgroundPath));
        }
        if (settings.backgroundPath.isNotEmpty) {
          content = Stack(
            children: [
              BackgroundLayer(settings: settings),
              Positioned.fill(child: content),
            ],
          );
        }
        return MediaQuery(
          data: scaledMediaQuery,
          child: HikoGlobalShortcuts(
            navigatorKey: hikoNavigatorKey,
            child: ActivityOverlayHost(
              controller: activityOverlayController,
              child: content,
            ),
          ),
        );
      },
      home: const HomeScreen(),
    );
  }
}
