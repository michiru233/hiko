import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:universal_platform/universal_platform.dart';

/// 桌面端（macOS & Windows）增强版 MediaKit 音频播放引擎：
/// 1. 彻底解决原版 just_audio_media_kit 在高速本地文件 open 时的 load Completer 竞争死锁问题（导致卡在 0:00）；
/// 2. 继承 64-bit 浮点软增益（1.0x~3.0x）与高质量音频渲染支持；
/// 3. 提供毫秒级加载超时与就绪兜底保护，确保永远不会死锁挂起。
class HikoJustAudioMediaKit extends JustAudioPlatform {
  HikoJustAudioMediaKit();

  static final _players = HashMap<String, HikoMediaKitPlayer>();
  static final _disposingPlayers = HashMap<String, Future<void>>();

  /// 平台初始化注册
  static void ensureInitialized({
    bool macOS = true,
    bool windows = true,
  }) {
    if ((UniversalPlatform.isMacOS && macOS) ||
        (UniversalPlatform.isWindows && windows)) {
      JustAudioPlatform.instance = HikoJustAudioMediaKit();
      MediaKit.ensureInitialized();
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
        pitch: true,
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
        logLevel: MPVLogLevel.error,
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
    ];

    _readyCompleter.complete();
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
    // request.volume 传递的是 0.0~3.0（已包含增益）
    await _player.setVolume(request.volume * 100.0);
    return SetVolumeResponse();
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
