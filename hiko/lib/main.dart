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
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面端播放（macOS & Windows）：经 HikoJustAudioMediaKit（libmpv）路由以支持 64-bit 软增益与防死锁高质量渲染
  if (Platform.isWindows || Platform.isMacOS) {
    HikoJustAudioMediaKit.ensureInitialized(macOS: true, windows: true);
  }
  final container = ProviderContainer();
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

  runApp(UncontrolledProviderScope(
    container: container,
    child: const HikoApp(),
  ));
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

class HikoApp extends ConsumerWidget {
  const HikoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Hiko · 音声库',
      debugShowCheckedModeBanner: false,
      theme: buildHikoTheme(settings),
      home: const HomeScreen(),
    );
  }
}
