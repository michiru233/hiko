import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'data/categories_provider.dart';
import 'data/library_provider.dart';
import 'data/settings_store.dart';
import 'playback/audio_handler.dart';
import 'playback/playback_controller.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows 播放：just_audio 官方不支持，经 just_audio_media_kit（libmpv）路由
  if (Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized();
  }
  final container = ProviderContainer();
  // 加载设置与音声库与分类
  await container.read(settingsProvider.notifier).load();
  await container.read(libraryProvider.notifier).load();
  await container.read(categoriesProvider.notifier).load();

  // 音频会话（Android 焦点管理）
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // Android：audio_service 前台服务 + 通知 + 锁屏（对应旧版 KikoeruPlaybackService）
  if (Platform.isAndroid) {
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

  runApp(UncontrolledProviderScope(
    container: container,
    child: const HikoApp(),
  ));
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
