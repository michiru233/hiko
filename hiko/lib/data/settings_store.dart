import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/gain_chain.dart';
import 'online/online_models.dart';

/// 防社死隐私模糊全局开关（1.52）：内存态，每次启动默认开启、不持久化（防忘即安全）。
/// 覆盖面：AlbumCover 全部调用点（卡片/详情抽屉/播放条/统计/继续收听）、
/// 系统 Now Playing 中性化（audio_handler）、桌面歌词自动隐藏（home_screen 切换时）。
/// 用 ValueNotifier 而非 Riverpod：AlbumCover 保持不依赖 ProviderScope（可独立构造），
/// 播放层 audio_handler 也能直接监听。
final ValueNotifier<bool> privacyBlur = ValueNotifier(true);

/// 应用设置（对应旧版 localStorage 各项 + 刮削代理）
class AppSettings {
  final String theme; // light / dark
  final String accent; // 六色之一
  final double volume; // 0.0 - 1.0
  final double audioGain; // 1.0 - 4.0（音频增益倍率，默认 1.0 即 100% 不放大，最高 4.0x，经 af 链软限幅防破音）
  final String playMode; // list / single / shuffle / album
  final double playbackRate; // 播放倍速 0.5 - 2.0,步进 0.1,默认 1.0
  final String albumSort; // 专辑排序方式，默认 artist_asc
  final double seekStepSeconds; // 快进/快退步长（秒），白名单 3/5/10/30，默认 3
  final bool sidebarShown;
  final bool showScrapedTags; // 主界面卡片显示 DLsite 刮削标签，默认关闭（1.43）
  /// 在线卡片显示标签行，默认开启（1.94.0）。
  ///
  /// 与 [showScrapedTags] **刻意分开、默认值相反**：本地标签是刮削来的、偏噪声，
  /// 所以默认关；在线标签是 asmr.one 的正式元数据、而且是按标签筛选的入口，
  /// 所以默认开（用户裁决：在线的默认开启，也可以单独调节）。
  final bool showOnlineTags;
  final double gridColumns; // 主界面每行专辑数；0=自动（按宽度），档位 4/5/6/7/8/10/12（1.43）
  final double mobileGridColumns; // 移动端每行专辑数，档位 2/3/4，默认 2（1.54，与桌面独立）
  final double fontScale; // 字号缩放比例，档位 0.85/1.0/1.15/1.30，默认 1.0（1.56）
  final double lyricsFontScale; // 歌词字号缩放比例，档位 0.85/1.0/1.15/1.30/1.50，默认 1.0（1.61）
  final String scrapeProxy;
  final List<String> musicFolders; // 常驻音乐目录（桌面：路径；Android：SAF tree URI）
  final String backgroundPath; // 自定义背景图（已复制进应用数据目录的绝对路径，空=未启用，1.84）
  final double backgroundBlur; // 背景图模糊度 0-30px，默认 12
  final double backgroundOpacity; // 背景图不透明度 0-1（叠在主题底色上），默认 0.65
  final String onlineServer; // 在线服务器地址（Kikoeru 兼容，默认 asmr.one 官方实例，1.90）
  final double onlineCacheLimitGb; // 在线音频缓存上限（GB，0 = 不缓存，1.90）

  /// 标签胶囊字号（1.96.0 裁决 Q1=甲、Q2=甲、Q6=甲）。
  ///
  /// 这是**绝对字号**而不是倍率 —— 因为它是「三组缩放」里唯一的例外：
  /// 标签胶囊在视觉上是一块整体（本地卡面 / 本地详情 / 在线卡面 / 在线详情 /
  /// 黑名单管理对话框共用一个 `HikoTagChip`），给一处调等于给全部调，
  /// 所以用户要的是「把这块字变大」这个**绝对**结果，而不是「相对现在的我放大一点」。
  ///
  /// **全局生效、本地也一起变**（Q2=甲）：同一个组件一套字号，
  /// 否则本地与在线的标签会一边 9 一边 11，同屏对比时像两个应用。
  /// 最终渲染 = 本值 × 全局 `fontScale`（`main.dart` 根层 `TextScaler`）。
  final double tagFontSize;
  final double onlineCardTextScale; // 在线卡片标题/副标题的**相对**倍率（1.96.0）
  final double onlineDetailTextScale; // 在线详情面板文字的**相对**倍率（1.96.0）
  final double onlineGridColumns; // 在线网格每行列数；0=自动（按宽度），档位 3–8（1.96.0）

  /// 在线标签**黑名单**（1.95.0）。命中的标签会从在线浏览 / 搜索 / 标签筛选结果里排除。
  ///
  /// 只在线生效 —— 本地刮削库不受影响（沿用 1.94.0 裁决 Q1=B）。
  /// 为什么存**名字**而不是只用 id：实测服务端的标签筛选语法只认名字
  /// （`$tag:222$` 返回 0 条，`$tag:幼なじみ$` 才是 1322 条）。
  /// [OnlineTag.id] 仍然存下来，用于去重、管理页展示，以及卡片上判断「这个标签被屏蔽了」。
  final List<OnlineTag> blockedTags;

  const AppSettings({
    this.theme = 'light',
    this.accent = defaultAccent,
    this.volume = 0.8,
    this.audioGain = 1.0,
    this.playMode = 'list',
    this.playbackRate = 1.0,
    this.albumSort = 'artist_asc',
    this.seekStepSeconds = 3,
    this.sidebarShown = true,
    this.showScrapedTags = false,
    this.showOnlineTags = true,
    this.gridColumns = 0,
    this.mobileGridColumns = 2,
    this.fontScale = 1.0,
    this.lyricsFontScale = 1.0,
    this.scrapeProxy = '',
    this.musicFolders = const [],
    this.backgroundPath = '',
    this.backgroundBlur = 12,
    this.backgroundOpacity = 0.65,
    this.onlineServer = defaultOnlineServer,
    this.onlineCacheLimitGb = 5.0,
    this.tagFontSize = 11,
    this.onlineCardTextScale = 1.0,
    this.onlineDetailTextScale = 1.0,
    this.onlineGridColumns = 0,
    this.blockedTags = const [],
  });

  /// 在线服务默认地址（Kikoeru 协议公共实例；可改成任意自建服务器）
  static const defaultOnlineServer = 'https://api.asmr.one';

  /// 在线缓存默认上限：桌面 5 GB / 移动 2 GB。
  /// 注意：不能直接用作 const 构造的默认值（getter 不是常量），
  /// 首次运行时由 [_normalizeOnlineCacheLimit] 在 load 阶段落到平台默认值。
  static double get defaultOnlineCacheLimitGb => Platform.isAndroid ? 2 : 5;

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
    double? playbackRate,
    String? albumSort,
    double? seekStepSeconds,
    bool? sidebarShown,
    bool? showScrapedTags,
    bool? showOnlineTags,
    double? gridColumns,
    double? mobileGridColumns,
    double? fontScale,
    double? lyricsFontScale,
    String? scrapeProxy,
    List<String>? musicFolders,
    String? backgroundPath,
    double? backgroundBlur,
    double? backgroundOpacity,
    String? onlineServer,
    double? onlineCacheLimitGb,
    double? tagFontSize,
    double? onlineCardTextScale,
    double? onlineDetailTextScale,
    double? onlineGridColumns,
    List<OnlineTag>? blockedTags,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        accent: accent ?? this.accent,
        volume: volume ?? this.volume,
        audioGain: audioGain ?? this.audioGain,
        playMode: playMode ?? this.playMode,
        playbackRate: playbackRate ?? this.playbackRate,
        albumSort: albumSort ?? this.albumSort,
        seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
        sidebarShown: sidebarShown ?? this.sidebarShown,
        showScrapedTags: showScrapedTags ?? this.showScrapedTags,
        showOnlineTags: showOnlineTags ?? this.showOnlineTags,
        gridColumns: gridColumns ?? this.gridColumns,
        mobileGridColumns: mobileGridColumns ?? this.mobileGridColumns,
        fontScale: fontScale ?? this.fontScale,
        lyricsFontScale: lyricsFontScale ?? this.lyricsFontScale,
        scrapeProxy: scrapeProxy ?? this.scrapeProxy,
        musicFolders: musicFolders ?? this.musicFolders,
        backgroundPath: backgroundPath ?? this.backgroundPath,
        backgroundBlur: backgroundBlur ?? this.backgroundBlur,
        backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
        onlineServer: onlineServer ?? this.onlineServer,
        onlineCacheLimitGb: onlineCacheLimitGb ?? this.onlineCacheLimitGb,
        tagFontSize: tagFontSize ?? this.tagFontSize,
        onlineCardTextScale: onlineCardTextScale ?? this.onlineCardTextScale,
        onlineDetailTextScale:
            onlineDetailTextScale ?? this.onlineDetailTextScale,
        onlineGridColumns: onlineGridColumns ?? this.onlineGridColumns,
        blockedTags: blockedTags ?? this.blockedTags,
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
  static const _kPlaybackRate = 'hiko-playback-rate';
  static const _kAlbumSort = 'hiko-album-sort';
  static const _kSeekStep = 'hiko-seek-step';
  static const _kSidebar = 'hiko-sidebar';
  static const _kShowScrapedTags = 'hiko-show-scraped-tags';
  static const _kShowOnlineTags = 'hiko-online-show-tags';
  static const _kGridColumns = 'hiko-grid-columns';
  static const _kMobileGridColumns = 'hiko-mobile-grid-columns';
  static const _kFontScale = 'hiko-font-scale';
  static const _kLyricsFontScale = 'hiko-lyrics-font-scale';
  static const _kProxy = 'hiko-scrape-proxy';
  static const _kMusicFolders = 'hiko-music-folders';
  static const _kBackgroundPath = 'hiko-background-path';
  static const _kBackgroundBlur = 'hiko-background-blur';
  static const _kBackgroundOpacity = 'hiko-background-opacity';
  static const _kOnlineServer = 'hiko-online-server';
  static const _kOnlineCacheLimit = 'hiko-online-cache-limit';
  static const _kTagFontSize = 'hiko-online-tag-font-size';
  static const _kOnlineCardTextScale = 'hiko-online-card-text-scale';
  static const _kOnlineDetailTextScale = 'hiko-online-detail-text-scale';
  static const _kOnlineGridColumns = 'hiko-online-grid-columns';
  static const _kBlockedTags = 'hiko-online-blocked-tags';

  static const _validSorts = {
    'recent_desc',
    'recent_asc',
    'title_asc',
    'title_desc',
    'artist_asc',
    'duration_desc',
    'duration_asc',
    'rating_desc', // 评分优先（1.48）
    // 兼容旧别名
    'recent',
    'title',
    'duration',
  };

  static String _normalizeSort(String? val) {
    if (val != null && _validSorts.contains(val)) {
      return val;
    }
    return 'artist_asc';
  }

  static const _validSeekSteps = [3.0, 5.0, 10.0, 15.0, 30.0, 60.0];

  static double _normalizeSeekStep(double? val) =>
      val != null && _validSeekSteps.contains(val) ? val : 3;

  /// 每行专辑数档位：0=自动，其余为固定列数（存 double 以走 _save 的 setDouble 分支）；1.79 补 2/3 档
  static const _validGridColumns = [0.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0, 12.0];

  static double _normalizeGridColumns(double? val) =>
      val != null && _validGridColumns.contains(val) ? val : 0;

  /// 移动端每行专辑数档位：2/3/4（1.54，与桌面档位独立）
  static const _validMobileGridColumns = [2.0, 3.0, 4.0];

  static double _normalizeMobileGridColumns(double? val) =>
      val != null && _validMobileGridColumns.contains(val) ? val : 2;

  /// 字号缩放档位：0.85 (小) / 1.0 (标准) / 1.15 (大) / 1.30 (超大)
  static const _validFontScales = [0.85, 1.0, 1.15, 1.30];

  static double _normalizeFontScale(double? val) =>
      val != null && _validFontScales.contains(val) ? val : 1.0;

  /// 歌词字号缩放档位：0.85 (小) / 1.0 (标准) / 1.15 (大) / 1.30 (超大) / 1.50 (巨大)
  static const _validLyricsFontScales = [0.85, 1.0, 1.15, 1.30, 1.50];

  static double _normalizeLyricsFontScale(double? val) =>
      val != null && _validLyricsFontScales.contains(val) ? val : 1.0;

  /// 在线服务器地址：空值回退 asmr.one 官方实例。
  /// 不做严格 URL 校验——自建 Kikoeru 的形态多样（内网 IP、端口、子路径），
  /// 统一交给 KikoeruClient.normalizeBase 在运行时补 scheme 与去尾斜杠。
  static String _normalizeOnlineServer(String? val) {
    final trimmed = val?.trim() ?? '';
    return trimmed.isEmpty ? AppSettings.defaultOnlineServer : trimmed;
  }

  /// 在线缓存上限档位（GB）：0 = 不缓存；非法值回退平台默认（桌面 5 / 移动 2）
  static const _validOnlineCacheLimits = [
    0.0,
    0.5,
    1.0,
    2.0,
    5.0,
    10.0,
    20.0,
    50.0,
  ];

  static double _normalizeOnlineCacheLimit(double? val) =>
      (val != null && _validOnlineCacheLimits.contains(val))
          ? val
          : AppSettings.defaultOnlineCacheLimitGb;

  /// 缓存上限可选档位（设置页下拉用；0 = 关闭缓存）
  static const onlineCacheLimitOptions = _validOnlineCacheLimits;

  // ------------------------------------------------------------ 在线外观（1.96.0）

  /// 标签胶囊字号档位。默认 11（裁决 Q2=甲、Q6=甲：从 1.94.0 的硬编码 9 提到 11）。
  static const validTagFontSizes = [9.0, 10.0, 11.0, 12.0, 14.0];

  static double _normalizeTagFontSize(double? val) =>
      val != null && validTagFontSizes.contains(val) ? val : 11;

  /// 两组文字缩放档位。**值与全局 `fontScale` 相同，但刻意各自独立定义** ——
  /// 裁决要求「三组缩放互相独立」，共用一份常量会让将来单独调某一组时牵动另两组。
  static const _validOnlineTextScales = [0.85, 1.0, 1.15, 1.30];

  static double _normalizeOnlineTextScale(double? val) =>
      val != null && _validOnlineTextScales.contains(val) ? val : 1.0;

  /// 在线网格列数档位：0 = 自动（按可用宽度算），3–8 = 固定列数。
  ///
  /// **在线专属，桌面与移动端共用这一个值**（裁决 Q4=甲）——
  /// 主界面的 `gridColumns` / `mobileGridColumns` 是两端分开的，但在线页
  /// 移动端原本写死 2 列且用户从未抱怨过列数，再拆一份双端设置只是多一个旋钮。
  static const validOnlineGridColumns = [0.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];

  static double _normalizeOnlineGridColumns(double? val) =>
      val != null && validOnlineGridColumns.contains(val) ? val : 0;

  /// 黑名单的持久化形态：一个 JSON 数组字符串（`[{"id":1,"name":"…"}]`），
  /// 而不是 `List<String>` 多键 —— 单键写入天然原子，不会出现「写了一半」的中间态。
  ///
  /// 归一化必须是**宽容**的：这一项是用户数据（不像档位是枚举），
  /// 遇到坏数据只能丢坏的那几条，不能把整张表判无效 —— 否则一次序列化意外
  /// 就会把用户攒了很久的黑名单整份清空。
  static String _normalizeBlockedTags(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return '';
      final out = <OnlineTag>[];
      final seenIds = <int>{};
      final seenNames = <String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final tag = OnlineTag.fromJson(Map<String, dynamic>.from(item));
        if (tag.name.isEmpty) continue;
        // 没 id（老数据或手工编辑）时退化成按名字去重
        final dup = tag.id > 0 ? !seenIds.add(tag.id) : !seenNames.add(tag.name);
        if (dup) continue;
        seenNames.add(tag.name);
        out.add(tag);
      }
      return jsonEncode([for (final t in out) t.toJson()]);
    } catch (_) {
      return '';
    }
  }

  static List<OnlineTag> _decodeBlockedTags(String? raw) {
    final normalized = _normalizeBlockedTags(raw);
    if (normalized.isEmpty) return const [];
    try {
      final decoded = jsonDecode(normalized) as List;
      return [
        for (final item in decoded)
          OnlineTag.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      theme: prefs.getString(_kTheme) ?? 'light',
      accent: prefs.getString(_kAccent) ?? AppSettings.defaultAccent,
      volume: (prefs.getDouble(_kVolume) ?? 0.8).clamp(0.0, 1.0),
      audioGain: (prefs.getDouble(_kAudioGain) ?? 1.0)
          .clamp(1.0, desktopGainCap()),
      playMode: prefs.getString(_kMode) ?? 'list',
      playbackRate: (prefs.getDouble(_kPlaybackRate) ?? 1.0).clamp(0.5, 2.0),
      albumSort: _normalizeSort(prefs.getString(_kAlbumSort)),
      seekStepSeconds: _normalizeSeekStep(prefs.getDouble(_kSeekStep)),
      sidebarShown: prefs.getBool(_kSidebar) ?? true,
      showScrapedTags: prefs.getBool(_kShowScrapedTags) ?? false,
      showOnlineTags: prefs.getBool(_kShowOnlineTags) ?? true,
      gridColumns: _normalizeGridColumns(prefs.getDouble(_kGridColumns)),
      mobileGridColumns:
          _normalizeMobileGridColumns(prefs.getDouble(_kMobileGridColumns)),
      fontScale: _normalizeFontScale(prefs.getDouble(_kFontScale)),
      lyricsFontScale: _normalizeLyricsFontScale(prefs.getDouble(_kLyricsFontScale)),
      scrapeProxy: prefs.getString(_kProxy) ?? '',
      musicFolders: prefs.getStringList(_kMusicFolders) ?? const [],
      // 背景图文件若已被系统清理/卸载残留则静默回退默认背景
      backgroundPath: await _existingBackground(prefs.getString(_kBackgroundPath) ?? ''),
      backgroundBlur: (prefs.getDouble(_kBackgroundBlur) ?? 12).clamp(0.0, 30.0),
      backgroundOpacity: (prefs.getDouble(_kBackgroundOpacity) ?? 0.65).clamp(0.0, 1.0),
      onlineServer: _normalizeOnlineServer(prefs.getString(_kOnlineServer)),
      onlineCacheLimitGb:
          _normalizeOnlineCacheLimit(prefs.getDouble(_kOnlineCacheLimit)),
      tagFontSize: _normalizeTagFontSize(prefs.getDouble(_kTagFontSize)),
      onlineCardTextScale:
          _normalizeOnlineTextScale(prefs.getDouble(_kOnlineCardTextScale)),
      onlineDetailTextScale:
          _normalizeOnlineTextScale(prefs.getDouble(_kOnlineDetailTextScale)),
      onlineGridColumns:
          _normalizeOnlineGridColumns(prefs.getDouble(_kOnlineGridColumns)),
      blockedTags: _decodeBlockedTags(prefs.getString(_kBlockedTags)),
    );
  }

  Future<void> setTheme(String theme) => _save(_kTheme, theme, state.copyWith(theme: theme));
  Future<void> setAccent(String accent) => _save(_kAccent, accent, state.copyWith(accent: accent));
  Future<void> setVolume(double volume) =>
      _save(_kVolume, volume.clamp(0.0, 1.0), state.copyWith(volume: volume.clamp(0.0, 1.0)));
  Future<void> setAudioGain(double gain) =>
      _save(_kAudioGain, gain.clamp(1.0, desktopGainCap()),
          state.copyWith(audioGain: gain.clamp(1.0, desktopGainCap())));
  Future<void> setPlayMode(String mode) => _save(_kMode, mode, state.copyWith(playMode: mode));

  Future<void> setAlbumSort(String sort) {
    final validSort = _normalizeSort(sort);
    return _save(_kAlbumSort, validSort, state.copyWith(albumSort: validSort));
  }

  /// 快进/快退步长：白名单 3/5/10/30 秒，非法值回退 3
  Future<void> setSeekStep(double seconds) {
    final valid = _normalizeSeekStep(seconds);
    return _save(_kSeekStep, valid, state.copyWith(seekStepSeconds: valid));
  }

  /// 播放倍速:0.5 ~ 2.0(步进 0.1 由 UI Slider divisions 保证)
  Future<void> setPlaybackRate(double rate) => _save(
        _kPlaybackRate,
        rate.clamp(0.5, 2.0),
        state.copyWith(playbackRate: rate.clamp(0.5, 2.0)),
      );
  Future<void> setSidebarShown(bool shown) =>
      _save(_kSidebar, shown, state.copyWith(sidebarShown: shown));

  /// 主界面卡片是否显示刮削标签（1.43）
  Future<void> setShowScrapedTags(bool show) =>
      _save(_kShowScrapedTags, show, state.copyWith(showScrapedTags: show));

  /// 在线卡片是否显示标签行（1.94.0）
  Future<void> setShowOnlineTags(bool show) =>
      _save(_kShowOnlineTags, show, state.copyWith(showOnlineTags: show));

  /// 每行专辑数：0=自动，档位白名单 4/5/6/7/8/10/12，非法值回退自动（1.43）
  Future<void> setGridColumns(double columns) {
    final valid = _normalizeGridColumns(columns);
    return _save(_kGridColumns, valid, state.copyWith(gridColumns: valid));
  }

  /// 移动端每行专辑数：档位 2/3/4，默认 2（1.54）
  Future<void> setMobileGridColumns(double columns) {
    final valid = _normalizeMobileGridColumns(columns);
    return _save(_kMobileGridColumns, valid, state.copyWith(mobileGridColumns: valid));
  }

  /// 字号缩放比例：0.85/1.0/1.15/1.30（1.56）
  Future<void> setFontScale(double scale) {
    final valid = _normalizeFontScale(scale);
    return _save(_kFontScale, valid, state.copyWith(fontScale: valid));
  }

  /// 歌词字号缩放比例：0.85/1.0/1.15/1.30/1.50（1.61）
  Future<void> setLyricsFontScale(double scale) {
    final valid = _normalizeLyricsFontScale(scale);
    return _save(_kLyricsFontScale, valid, state.copyWith(lyricsFontScale: valid));
  }

  Future<void> setScrapeProxy(String proxy) =>
      _save(_kProxy, proxy, state.copyWith(scrapeProxy: proxy));

  /// 在线服务器地址（Kikoeru 兼容，默认 asmr.one，1.90）
  Future<void> setOnlineServer(String server) {
    final valid = _normalizeOnlineServer(server);
    return _save(_kOnlineServer, valid, state.copyWith(onlineServer: valid));
  }

  /// 在线音频缓存上限（GB，0 = 不缓存，1.90）
  Future<void> setOnlineCacheLimit(double gb) {
    final valid = _normalizeOnlineCacheLimit(gb);
    return _save(
        _kOnlineCacheLimit, valid, state.copyWith(onlineCacheLimitGb: valid));
  }

  /// 标签胶囊字号（全局生效，本地与在线一起变，1.96.0）
  Future<void> setTagFontSize(double size) {
    final valid = _normalizeTagFontSize(size);
    return _save(_kTagFontSize, valid, state.copyWith(tagFontSize: valid));
  }

  /// 在线卡片文字缩放倍率（1.96.0）
  Future<void> setOnlineCardTextScale(double scale) {
    final valid = _normalizeOnlineTextScale(scale);
    return _save(
        _kOnlineCardTextScale, valid, state.copyWith(onlineCardTextScale: valid));
  }

  /// 在线详情面板文字缩放倍率（1.96.0）
  Future<void> setOnlineDetailTextScale(double scale) {
    final valid = _normalizeOnlineTextScale(scale);
    return _save(_kOnlineDetailTextScale, valid,
        state.copyWith(onlineDetailTextScale: valid));
  }

  /// 在线网格每行列数：0=自动，档位 3–8，非法值回退自动（1.96.0）
  Future<void> setOnlineGridColumns(double columns) {
    final valid = _normalizeOnlineGridColumns(columns);
    return _save(
        _kOnlineGridColumns, valid, state.copyWith(onlineGridColumns: valid));
  }

  /// 整份替换标签黑名单（1.95.0）
  Future<void> setBlockedTags(List<OnlineTag> tags) {
    final encoded = _normalizeBlockedTags(jsonEncode([
      for (final t in tags) t.toJson(),
    ]));
    return _save(
      _kBlockedTags,
      encoded,
      state.copyWith(blockedTags: _decodeBlockedTags(encoded)),
    );
  }

  /// 把一个标签加入黑名单（按 id 去重；已在名单里则什么都不做）
  Future<void> addBlockedTag(OnlineTag tag) {
    if (tag.name.trim().isEmpty) return Future.value();
    if (state.blockedTags.any((t) => t.id == tag.id)) return Future.value();
    return setBlockedTags([...state.blockedTags, tag]);
  }

  /// 把一个标签移出黑名单
  Future<void> removeBlockedTag(int id) {
    if (!state.blockedTags.any((t) => t.id == id)) return Future.value();
    return setBlockedTags([
      for (final t in state.blockedTags)
        if (t.id != id) t,
    ]);
  }

  Future<void> clearBlockedTags() {
    if (state.blockedTags.isEmpty) return Future.value();
    return setBlockedTags(const []);
  }

  static Future<String> _existingBackground(String path) async {
    if (path.isEmpty) return '';
    try {
      return await File(path).exists() ? path : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> setBackgroundImage(String path) =>
      _save(_kBackgroundPath, path, state.copyWith(backgroundPath: path));
  Future<void> setBackgroundBlur(double blur) =>
      _save(_kBackgroundBlur, blur.clamp(0.0, 30.0),
          state.copyWith(backgroundBlur: blur.clamp(0.0, 30.0)));
  Future<void> setBackgroundOpacity(double opacity) =>
      _save(_kBackgroundOpacity, opacity.clamp(0.0, 1.0),
          state.copyWith(backgroundOpacity: opacity.clamp(0.0, 1.0)));

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
