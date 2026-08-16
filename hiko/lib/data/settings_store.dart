import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置（对应旧版 localStorage 各项 + 刮削代理）
class AppSettings {
  final String theme; // light / dark
  final String accent; // 六色之一
  final double volume; // 0.0 - 1.0
  final double audioGain; // 1.0 - 3.0（音频增益倍率，默认 1.0 即 100% 不放大，最高 3.0x / +9.5dB）
  final String playMode; // list / single / shuffle / album
  final bool sidebarShown;
  final String scrapeProxy;
  final List<String> musicFolders; // 常驻音乐目录（桌面：路径；Android：SAF tree URI）

  const AppSettings({
    this.theme = 'light',
    this.accent = defaultAccent,
    this.volume = 0.8,
    this.audioGain = 1.0,
    this.playMode = 'list',
    this.sidebarShown = true,
    this.scrapeProxy = '',
    this.musicFolders = const [],
  });

  static const defaultAccent = '#6559d8';
  static const accents = [
    '#6559d8', // 紫
    '#3b82c4', // 蓝
    '#2ea8a0', // 青
    '#4c9f70', // 绿
    '#d97b4d', // 橙
    '#c6577e', // 粉
  ];

  AppSettings copyWith({
    String? theme,
    String? accent,
    double? volume,
    double? audioGain,
    String? playMode,
    bool? sidebarShown,
    String? scrapeProxy,
    List<String>? musicFolders,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        accent: accent ?? this.accent,
        volume: volume ?? this.volume,
        audioGain: audioGain ?? this.audioGain,
        playMode: playMode ?? this.playMode,
        sidebarShown: sidebarShown ?? this.sidebarShown,
        scrapeProxy: scrapeProxy ?? this.scrapeProxy,
        musicFolders: musicFolders ?? this.musicFolders,
      );
}

/// 播放模式元数据
class PlayModeInfo {
  final String key;
  final String label; // 按钮文字
  final String name; // 完整名称
  final String desc; // 说明

  const PlayModeInfo(this.key, this.label, this.name, this.desc);
}

const playModes = [
  PlayModeInfo('list', '列表', '列表循环', '本专辑最后一首播完回到第一首'),
  PlayModeInfo('single', '单曲', '单曲循环', '当前曲目循环播放'),
  PlayModeInfo('shuffle', '随机', '随机播放', '当前专辑内随机切曲'),
  PlayModeInfo('album', '专辑', '专辑循环', '播完当前专辑自动接下一张'),
];

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  static const _kTheme = 'hiko-theme';
  static const _kAccent = 'hiko-accent';
  static const _kVolume = 'hiko-volume';
  static const _kAudioGain = 'hiko-audio-gain';
  static const _kMode = 'hiko-mode';
  static const _kSidebar = 'hiko-sidebar';
  static const _kProxy = 'hiko-scrape-proxy';
  static const _kMusicFolders = 'hiko-music-folders';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      theme: prefs.getString(_kTheme) ?? 'light',
      accent: prefs.getString(_kAccent) ?? AppSettings.defaultAccent,
      volume: (prefs.getDouble(_kVolume) ?? 0.8).clamp(0.0, 1.0),
      audioGain: (prefs.getDouble(_kAudioGain) ?? 1.0).clamp(1.0, 3.0),
      playMode: prefs.getString(_kMode) ?? 'list',
      sidebarShown: prefs.getBool(_kSidebar) ?? true,
      scrapeProxy: prefs.getString(_kProxy) ?? '',
      musicFolders: prefs.getStringList(_kMusicFolders) ?? const [],
    );
  }

  Future<void> setTheme(String theme) => _save(_kTheme, theme, state.copyWith(theme: theme));
  Future<void> setAccent(String accent) => _save(_kAccent, accent, state.copyWith(accent: accent));
  Future<void> setVolume(double volume) =>
      _save(_kVolume, volume.clamp(0.0, 1.0), state.copyWith(volume: volume.clamp(0.0, 1.0)));
  Future<void> setAudioGain(double gain) =>
      _save(_kAudioGain, gain.clamp(1.0, 3.0), state.copyWith(audioGain: gain.clamp(1.0, 3.0)));
  Future<void> setPlayMode(String mode) => _save(_kMode, mode, state.copyWith(playMode: mode));
  Future<void> setSidebarShown(bool shown) =>
      _save(_kSidebar, shown, state.copyWith(sidebarShown: shown));
  Future<void> setScrapeProxy(String proxy) =>
      _save(_kProxy, proxy, state.copyWith(scrapeProxy: proxy));

  /// 添加音乐目录（去重）并持久化
  Future<void> addMusicFolder(String path) {
    if (state.musicFolders.contains(path)) return Future.value();
    return _save(
      _kMusicFolders,
      [...state.musicFolders, path],
      state.copyWith(musicFolders: [...state.musicFolders, path]),
    );
  }

  Future<void> removeMusicFolder(String path) => _save(
        _kMusicFolders,
        state.musicFolders.where((p) => p != path).toList(),
        state.copyWith(
            musicFolders: state.musicFolders.where((p) => p != path).toList()),
      );

  Future<void> _save<T>(String key, T value, AppSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    if (value is List<String>) {
      await prefs.setStringList(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) => SettingsNotifier());
