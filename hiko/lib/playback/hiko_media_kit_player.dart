import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:universal_platform/universal_platform.dart';

import 'audio_heal.dart';
import 'gain_chain.dart';
import 'mpv_diagnostic_log.dart';

/// 桌面端（macOS & Windows）增强版 MediaKit 音频播放引擎：
/// 1. 彻底解决原版 just_audio_media_kit 在高速本地文件 open 时的 load Completer 竞争死锁问题（导致卡在 0:00）；
/// 2. 继承 64-bit 浮点软增益（1.0x~3.0x）与高质量音频渲染支持；
/// 3. 提供毫秒级加载超时与就绪兜底保护，确保永远不会死锁挂起。
class HikoJustAudioMediaKit extends JustAudioPlatform {
  HikoJustAudioMediaKit();

  static final _players = HashMap<String, HikoMediaKitPlayer>();
  static final _disposingPlayers = HashMap<String, Future<void>>();

  /// 全局增益当前值：af 链软增益 + 软限幅（mpv volume 属性 clamp 130，
  /// >1.3x 硬削波，增益必须走 af 浮点域；volume 属性只留 0~1 常规音量）。
  static double _globalGain = 1.0;

  /// 设置全局增益并应用到当前所有实例；之后 init 的实例也会补挂。
  /// 相同值幂等跳过；单实例失败容忍（风格同 syncVolume）。
  static Future<void> setGlobalGain(double gain) async {
    final g = gain.clamp(1.0, 4.0).toDouble();
    if (g == _globalGain) return;
    _globalGain = g;
    for (final player in _players.values.toList()) {
      await player.applyGain(g);
    }
  }

  /// 平台初始化注册
  static void ensureInitialized({
    bool macOS = true,
    bool windows = true,
  }) {
    if ((UniversalPlatform.isMacOS && macOS) ||
        (UniversalPlatform.isWindows && windows)) {
      JustAudioPlatform.instance = HikoJustAudioMediaKit();
      MediaKit.ensureInitialized();
      unawaited(MpvDiagnosticLog.init());
    }
  }

  /// 对所有存活实例重接音频输出（手动逃生门，绕过防抖限流）。
  static Future<void> healAllOutputs() async {
    for (final player in _players.values.toList()) {
      await player.healAudioOutput();
    }
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    if (_players.containsKey(request.id)) {
      throw PlatformException(
          code: 'error', message: 'Player ${request.id} already exists!');
    }

    final player = HikoMediaKitPlayer(request.id);
    _players[request.id] = player;
    await player.ready();
    if (_globalGain != 1.0) {
      await player.applyGain(_globalGain);
    }
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
      DisposePlayerRequest request) async {
    if (_disposingPlayers.containsKey(request.id)) {
      await _disposingPlayers[request.id]!;
      return DisposePlayerResponse();
    }

    if (!_players.containsKey(request.id)) {
      return DisposePlayerResponse();
    }

    final future = _players[request.id]!.release();
    _players.remove(request.id);
    _disposingPlayers[request.id] = future;
    await future;
    _disposingPlayers.remove(request.id);

    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
      DisposeAllPlayersRequest request) async {
    if (_players.isNotEmpty) {
      await Future.wait(_players.values.map((e) => e.release()));
      _players.clear();
    }
    return DisposeAllPlayersResponse();
  }
}

/// 针对 just_audio 进行深度优化的 MediaKitPlayer
class HikoMediaKitPlayer extends AudioPlayerPlatform {
  HikoMediaKitPlayer(super.id) {
    _player = Player(
      configuration: const PlayerConfiguration(
        // pitch:true 时 media_kit setRate 会整体覆盖 af 滤镜链（含增益）；
        // 本应用不用变速播放，改 false 根除隐患
        pitch: false,
        protocolWhitelist: [
          'udp',
          'rtp',
          'tcp',
          'tls',
          'data',
          'file',
          'http',
          'https',
          'crypto',
        ],
        title: 'HikoPlayer',
        bufferSize: 32 * 1024 * 1024,
        // warn 起才能在无声事故后从 hiko-mpv.log 看到 coreaudio/设备线索
        logLevel: MPVLogLevel.warn,
      ),
    );

    _streamSubscriptions = [
      _player.stream.duration.listen((duration) {
        if (_currentMedia?.extras?['overrideDuration'] != null) return;

        if (_setPosition != null && duration.inSeconds > 0) {
          unawaited(_player.seek(_setPosition!));
          _setPosition = null;
        }
        _updateDuration(duration);
        _maybeCompleteLoad();
        _updatePlaybackEvent();
      }),
      _player.stream.position.listen((position) {
        _position = position;
        final start = _currentMedia?.start;
        if (start != null) _position -= start;
        if (_position < Duration.zero) _position = Duration.zero;
        _updatePlaybackEvent();
      }),
      _player.stream.buffering.listen((isBuffering) {
        if (!isBuffering && _mediaOpened) {
          _maybeCompleteLoad();
        }
        _updatePlaybackEvent();
      }),
      _player.stream.completed.listen((completed) {
        if (completed) {
          _processingState = ProcessingStateMessage.completed;
          _updatePlaybackEvent();
        }
      }),
      _player.stream.error.listen((error) {
        _errorCode = 1;
        _errorMessage = error;
        _maybeCompleteLoad();
        _updatePlaybackEvent();
      }),
      _player.stream.log.listen((log) {
        unawaited(MpvDiagnosticLog.write(
            MpvDiagnosticLog.formatLine(DateTime.now(), log.level, log.prefix, log.text)));
        _onMpvLog(log.level, log.text);
      }),
    ];

    _readyCompleter.complete();
    unawaited(_observeAudioDevice());
  }

  late final Player _player;
  late final List<StreamSubscription> _streamSubscriptions;
  final _readyCompleter = Completer<void>();

  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  final _dataController = StreamController<PlayerDataMessage>.broadcast();

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  Duration _bufferedPosition = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  bool _mediaOpened = false;
  int? _errorCode;
  String? _errorMessage;
  Completer<Duration?>? _loadCompleter;

  int _currentIndex = 0;
  Duration? _setPosition;

  final _healDecider = AudioHealDecider();
  String? _lastDeviceListJson;

  /// mpv 日志事件 → 自愈判定（仅 warn/error 级别命中音频输出问题文本）。
  void _onMpvLog(String level, String text) {
    final severe = level == 'error' || level == 'warn' || level == 'fatal' || level == 'panic';
    _maybeHeal(
      logHit: severe && AudioHealDecider.logSuggestsDeadOutput(text),
      deviceListChanged: false,
    );
  }

  /// 观察 audio-device / audio-device-list：设备增删或输出设备变化即触发判定。
  Future<void> _observeAudioDevice() async {
    try {
      final platform = _player.platform;
      if (platform is! NativePlayer) return;
      await platform.observeProperty('audio-device-list', (value) async {
        final changed = _lastDeviceListJson != null && _lastDeviceListJson != value;
        _lastDeviceListJson = value;
        _maybeHeal(logHit: false, deviceListChanged: changed);
      });
      await platform.observeProperty('audio-device', (value) async {
        unawaited(MpvDiagnosticLog.write(MpvDiagnosticLog.formatLine(
            DateTime.now(), 'info', 'hiko', 'audio-device=$value')));
      });
    } catch (e) {
      debugPrint('[heal] observeProperty 失败（容忍）: $e');
    }
  }

  void _maybeHeal({required bool logHit, required bool deviceListChanged}) {
    if (!_healDecider.shouldHeal(
      playing: _playing,
      logHit: logHit,
      deviceListChanged: deviceListChanged,
    )) {
      return;
    }
    unawaited(healAudioOutput());
  }

  /// 重接音频输出：audio-device 置回 auto 触发 mpv 音频链重初始化；
  /// 播放中时 pause→play 恢复发声。失败容忍（不能因自愈弄挂播放）。
  Future<void> healAudioOutput() async {
    try {
      final platform = _player.platform;
      if (platform is! NativePlayer) return;
      final current = await platform.getProperty('audio-device');
      debugPrint('[heal] 重接音频输出 audio-device=$current → auto (playing=$_playing)');
      unawaited(MpvDiagnosticLog.write(MpvDiagnosticLog.formatLine(
          DateTime.now(), 'heal', 'hiko', 'audio-device=$current → auto (playing=$_playing)')));
      await platform.setProperty('audio-device', 'auto');
      if (_playing && _mediaOpened) {
        await _player.pause();
        await _player.play();
      }
    } catch (e) {
      debugPrint('[heal] 重接失败（容忍）: $e');
      unawaited(MpvDiagnosticLog.write(MpvDiagnosticLog.formatLine(
          DateTime.now(), 'heal', 'hiko', '重接失败: $e')));
    }
  }

  Future<void> ready() => _readyCompleter.future;

  Media? get _currentMedia {
    final medias = _player.state.playlist.medias;
    if (medias.isEmpty) return null;
    final idx = _player.state.playlist.index;
    if (idx < 0 || idx >= medias.length) return null;
    return medias[idx];
  }

  void _updateDuration(Duration duration) {
    if (duration == Duration.zero) return;
    final start = _currentMedia?.start;
    final end = _currentMedia?.end;
    if (end != null) duration = end;
    if (start != null) duration -= start;
    _duration = duration;
  }

  void _maybeCompleteLoad() {
    if (_processingState == ProcessingStateMessage.loading && _mediaOpened) {
      _processingState = ProcessingStateMessage.ready;
      if (_loadCompleter?.isCompleted == false) {
        _loadCompleter?.complete(_duration ?? _player.state.duration);
      }
    }
  }

  void _updatePlaybackEvent() {
    _eventController.add(PlaybackEventMessage(
      processingState: _processingState,
      updateTime: DateTime.now(),
      updatePosition: _position,
      bufferedPosition: _bufferedPosition,
      duration: _duration,
      icyMetadata: null,
      currentIndex: _currentIndex,
      androidAudioSessionId: null,
      errorCode: _errorCode,
      errorMessage: _errorMessage,
    ));
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _eventController.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      _dataController.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _mediaOpened = false;
    _loadCompleter = Completer<Duration?>();
    _currentIndex = request.initialIndex ?? 0;
    _bufferedPosition = Duration.zero;
    _position = Duration.zero;
    _duration = null;
    _processingState = ProcessingStateMessage.loading;
    _errorCode = null;
    _errorMessage = null;
    _updatePlaybackEvent();

    try {
      if (request.audioSourceMessage is ConcatenatingAudioSourceMessage) {
        final audioSource =
            request.audioSourceMessage as ConcatenatingAudioSourceMessage;
        final playable = Playlist(
          audioSource.children.map(_convertAudioSourceIntoMediaKit).toList(),
          index: _currentIndex,
        );
        await _player.open(playable, play: _playing);
      } else {
        final playable =
            _convertAudioSourceIntoMediaKit(request.audioSourceMessage);
        await _player.open(playable, play: _playing);
      }
      _mediaOpened = true;

      if (request.initialPosition != null) {
        _setPosition = _position = request.initialPosition!;
      }

      // 关键修复：open 完毕后立即检查播放器是否已经就绪或已经获得时长
      if (!_player.state.buffering || _player.state.duration > Duration.zero) {
        _maybeCompleteLoad();
      }

      _updatePlaybackEvent();

      // 安全超时兜底：6 秒内若未收到事件，强行解锁返回已有状态，永不死锁
      final duration = await _loadCompleter?.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          _processingState = ProcessingStateMessage.ready;
          _updatePlaybackEvent();
          return _duration ?? _player.state.duration;
        },
      );
      return LoadResponse(duration: duration);
    } catch (e) {
      _processingState = ProcessingStateMessage.idle;
      _errorCode = 1;
      _errorMessage = e.toString();
      _updatePlaybackEvent();
      rethrow;
    }
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _playing = true;
    if (_mediaOpened) {
      await _player.play();
    }
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _playing = false;
    if (_mediaOpened) {
      await _player.pause();
    }
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    // request.volume 只传 0.0~1.0 常规音量；增益已整体搬进 af 链（见 setGlobalGain）
    await _player.setVolume(request.volume * 100.0);
    return SetVolumeResponse();
  }

  /// 应用 af 增益链并读回验证；失败容忍（引擎不可用时静默降级为直通）。
  /// 同时读回 mpv volume，验证增益改动不影响常规音量通道。
  Future<void> applyGain(double gain) async {
    try {
      final platform = _player.platform;
      if (platform is! NativePlayer) return;
      await platform.setProperty('af', gainAfChain(gain));
      final readBack = await platform.getProperty('af');
      final volume = await platform.getProperty('volume');
      debugPrint('[gain] af=$readBack (mpv volume=$volume)');
    } catch (e) {
      debugPrint('[gain] 应用增益失败（容忍）: $e');
    }
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    await _player.setRate(request.speed);
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    await _player.setPitch(request.pitch);
    return SetPitchResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    final mode = switch (request.loopMode) {
      LoopModeMessage.off => PlaylistMode.none,
      LoopModeMessage.one => PlaylistMode.single,
      LoopModeMessage.all => PlaylistMode.loop,
    };
    await _player.setPlaylistMode(mode);
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
      SetShuffleModeRequest request) async {
    final shuffling = request.shuffleMode != ShuffleModeMessage.none;
    await _player.setShuffle(shuffling);
    _dataController.add(PlayerDataMessage(
      shuffleMode:
          shuffling ? ShuffleModeMessage.all : ShuffleModeMessage.none,
    ));
    return SetShuffleModeResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    if (request.index != null) {
      await _player.jump(request.index!);
      if (!_playing) await _player.pause();
    }

    final position = request.position;
    if (position != null) {
      _position = position;
      final start = _currentMedia?.start;
      var nativePosition = position;
      if (start != null) nativePosition += start;
      if (_player.state.duration.inSeconds > 0) {
        await _player.seek(nativePosition);
      } else {
        _setPosition = nativePosition;
      }
    } else {
      _position = Duration.zero;
    }

    _updatePlaybackEvent();
    return SeekResponse();
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
      ConcatenatingInsertAllRequest request) async {
    for (final source in request.children) {
      await _player.add(_convertAudioSourceIntoMediaKit(source));
      final length = _player.state.playlist.medias.length;
      if (length <= 1) continue;
      if (request.index < (length - 1) && request.index >= 0) {
        await _player.move(length, request.index);
      }
    }
    return ConcatenatingInsertAllResponse();
  }

  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
      ConcatenatingRemoveRangeRequest request) async {
    for (var i = request.startIndex; i < request.endIndex; i++) {
      await _player.remove(request.startIndex);
    }
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<ConcatenatingMoveResponse> concatenatingMove(
      ConcatenatingMoveRequest request) async {
    await _player.move(
      request.currentIndex,
      request.currentIndex > request.newIndex
          ? request.newIndex
          : request.newIndex + 1,
    );
    return ConcatenatingMoveResponse();
  }

  Future<void> release() async {
    _mediaOpened = false;
    await _player.dispose();
    for (final subscription in _streamSubscriptions) {
      unawaited(subscription.cancel());
    }
    _streamSubscriptions.clear();
  }

  Media _convertAudioSourceIntoMediaKit(AudioSourceMessage audioSource) {
    switch (audioSource) {
      case final UriAudioSourceMessage uriSource:
        return Media(uriSource.uri, httpHeaders: audioSource.headers);
      case final ClippingAudioSourceMessage clippingSource:
        return Media(
          clippingSource.child.uri,
          start: clippingSource.start,
          end: clippingSource.end,
        );
      default:
        throw UnsupportedError(
            '${audioSource.runtimeType} is currently not supported');
    }
  }
}
