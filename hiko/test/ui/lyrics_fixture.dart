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
