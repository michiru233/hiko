import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';

/// 歌词居中相关回归测试的共用夹具。
///
/// 合成 [lines] 行歌词、每行 2 秒，时长 [durationSeconds]。行数刻意远大于一屏，
/// 这样「跨行远跳」必然需要真实的粗定位 + 重试，而不是首屏内的微调。
String buildLyrics({int lines = 140}) {
  final buffer = StringBuffer('WEBVTT\n\n');
  for (var i = 0; i < lines; i++) {
    final start = i * 2;
    String ts(int s) =>
        '00:${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}.000';
    buffer.writeln('${ts(start)} --> ${ts(start + 2)}');
    buffer.writeln('第 $i 句');
    buffer.writeln();
  }
  return buffer.toString();
}

Album lyricsAlbum({int lines = 140, double durationSeconds = 300}) => Album(
      id: 'rj-test',
      sourcePath: '/tmp/rj-test',
      title: '测试专辑',
      date: DateTime(2026),
      tracks: [
        Track(
          index: 0,
          name: 'track01',
          url: 'file:///tmp/track01.mp3',
          duration: durationSeconds,
          lyricsText: buildLyrics(lines: lines),
        ),
      ],
    );

PlaybackState playingAt(Album album, double seconds) => PlaybackState(
      album: album,
      queue: [album.tracks.first],
      queueIndex: 0,
      playing: true,
      position: seconds,
      duration: album.tracks.first.duration,
    );

/// 会换行的「长句」歌词：每行 [charsPerLine] 个全角字。
///
/// 手机宽度（360dp − 24×2 边距）下 15px 字号约放得下 20 个字，所以 40 字折成 2 行、
/// 80 字折成 4 行，实测行高 70–130px，是 `lyricsEstimatedLineHeight`（45×scale）
/// 的 1.6–3 倍。真实库里 13% 的音轨平均每句超过 20 字（DLsite 音声字幕常见），
/// 这正是「粗定位按固定行高硬乘」撞车的现场。
String buildWrappedLyrics({int lines = 40, int charsPerLine = 80}) {
  final buffer = StringBuffer('WEBVTT\n\n');
  final sentence = 'あ' * charsPerLine;
  for (var i = 0; i < lines; i++) {
    final start = i * 2;
    String ts(int s) =>
        '00:${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}.000';
    buffer.writeln('${ts(start)} --> ${ts(start + 2)}');
    buffer.writeln('第 $i 句 $sentence');
    buffer.writeln();
  }
  return buffer.toString();
}

Album wrappedLyricsAlbum({int lines = 40, int charsPerLine = 80}) => Album(
      id: 'rj-wrapped',
      sourcePath: '/tmp/rj-wrapped',
      title: '长句专辑',
      date: DateTime(2026),
      tracks: [
        Track(
          index: 0,
          name: 'track01',
          url: 'file:///tmp/track01.mp3',
          duration: 300,
          lyricsText: buildWrappedLyrics(lines: lines, charsPerLine: charsPerLine),
        ),
      ],
    );
