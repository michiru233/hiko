import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/album.dart';

/// 12 种兜底封面 SVG 生成（移植旧版 app.js coverSvg）。
/// 无内嵌/文件夹封面时用「渐变底色 + 形状」生成，离线可用。
String coverSvg(String id, List<String> color, String shape) {
  final c1 = color.isNotEmpty ? color[0] : '#c4b8e8';
  final c2 = color.length > 1 ? color[1] : '#4b416c';
  final shapes = <String, String>{
    'moon':
        '<circle cx="76" cy="76" r="30" fill="$c1"/><circle cx="87" cy="68" r="27" fill="$c2"/><circle cx="128" cy="34" r="2" fill="#fff"/><circle cx="110" cy="54" r="1.5" fill="#fff"/>',
    'window':
        '<rect x="34" y="25" width="84" height="104" rx="3" fill="#f4d7ca"/><path d="M76 25v104M34 76h84" stroke="$c2" stroke-width="3" opacity=".45"/>',
    'radio':
        '<rect x="38" y="46" width="76" height="55" rx="8" fill="#e6f4ec"/><circle cx="76" cy="73" r="16" fill="$c2"/><circle cx="76" cy="73" r="6" fill="#d2ecdc"/>',
    'cat':
        '<path d="M40 111L49 55l20 16 14-18 24 17 8 41z" fill="#fff1c8"/><circle cx="65" cy="82" r="3" fill="$c2"/><circle cx="91" cy="82" r="3" fill="$c2"/>',
    'star':
        '<path d="M76 27l10 30 31 1-24 19 8 30-25-17-25 17 8-30-24-19 31-1z" fill="#e9ddff"/><circle cx="76" cy="75" r="11" fill="$c2"/>',
    'herb':
        '<path d="M76 130V61M76 90C50 83 48 64 48 64s19-2 28 19M76 76c23-11 30-29 30-29s-21 2-30 19" fill="none" stroke="#f1f6d8" stroke-width="7" stroke-linecap="round"/>',
    'sea':
        '<path d="M0 102q30-22 60 0t60 0t60 0v60H0z" fill="#d4f0f1"/><path d="M0 115q30-22 60 0t60 0t60 0" fill="none" stroke="#fff" stroke-width="3"/><circle cx="135" cy="39" r="20" fill="#fff1ba"/>',
    'book':
        '<path d="M33 47q22-9 43 7v64q-21-15-43-5zM119 47q-22-9-43 7v64q21-15 43-5z" fill="#f8f2ed"/><path d="M76 54v63" stroke="$c2" stroke-width="3"/>',
    'heart':
        '<path d="M76 119C35 91 42 54 62 54c8 0 13 5 14 11 2-6 7-11 15-11 20 0 27 37-15 65z" fill="#ffe4df" stroke="$c2" stroke-width="3"/>',
    'pillow':
        '<rect x="38" y="49" width="76" height="51" rx="24" fill="#eee7ff" transform="rotate(-8 76 75)"/>',
    'fire':
        '<path d="M76 119c-20-16-14-34 0-48 2 12 10 15 9 25 10-13 14-25 7-39 24 22 24 45 1 62z" fill="#ffd7a6"/><path d="M76 115c-11-12-6-24 1-31 2 8 6 11 8 16 5-8 4-14 3-19 13 14 9 28-12 34z" fill="#e98062"/>',
    'sun':
        '<circle cx="76" cy="77" r="24" fill="#fff6ca"/><g stroke="#fff6ca" stroke-width="4" stroke-linecap="round"><path d="M76 31v13M76 110v13M30 77h13M109 77h13M43 44l9 9M100 101l9 9M109 44l-9 9M52 101l-9 9"/></g>',
  };
  final shapeBody = shapes[shape] ?? shapes['radio']!;
  return '<svg viewBox="0 0 152 152" xmlns="http://www.w3.org/2000/svg">'
      '<defs><linearGradient id="g$id" x1="0" y1="0" x2="1" y2="1">'
      '<stop stop-color="$c1"/><stop offset="1" stop-color="$c2"/></linearGradient></defs>'
      '<rect width="152" height="152" fill="url(#g$id)"/>'
      '<circle cx="128" cy="125" r="48" fill="#ffffff18"/>'
      '<circle cx="23" cy="18" r="36" fill="#ffffff10"/>'
      '$shapeBody'
      '<text x="12" y="142" fill="#ffffffb8" font-family="sans-serif" font-size="8" letter-spacing="1.6">HIKO · ${id.padLeft(2, '0')}</text>'
      '</svg>';
}

/// 专辑封面组件：data: 封面 → 内存图；file:/http(s) → 网络图；否则 SVG 兜底
class AlbumCover extends StatelessWidget {
  const AlbumCover({super.key, required this.album, this.fit = BoxFit.cover});

  final Album album;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final cover = album.currentCover ?? album.localCover;
    if (cover != null && cover.startsWith('data:')) {
      final bytes = base64Decode(cover.substring(cover.indexOf(',') + 1));
      return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    }
    if (cover != null && (cover.startsWith('http:') || cover.startsWith('https:'))) {
      return Image.network(cover, fit: fit, errorBuilder: (_, _, _) => _svg());
    }
    return _svg();
  }

  Widget _svg() => SvgPicture.string(
        coverSvg(album.id, album.color, album.shape),
        fit: fit,
      );
}
