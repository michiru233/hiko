/// 音频增益 af 链构建（mpv lavfi 滤镜串，纯函数可单测）。
///
/// Windows：libavfilter 带 `volume`/`alimiter`，增益走 af 滤镜链浮点软增益 + 软限幅。
/// macOS：media_kit 预编译的 libavfilter 全系（v0.6.0 audio/video/default/full）只带
/// 缓冲/重采样滤镜，**没有** `volume`/`alimiter`，给 mpv 设任何 `af` 链都会解析失败
/// → 音频输出链建不起来 → 静音；mpv 0.36 又移除了内建 `af_volume`，故增益并入
/// mpv `volume` 属性在 ao 层承载（播放器初始化时已设 `volume-max=400` 放开钳制，
/// 见 HikoMediaKitPlayer）。>1.3x 属裸放大，高增益可能硬削波——与 Android
/// LoudnessEnhancer 的纯增益行为一致（1.79 待办曾验证 v0.7.2 `audio-encodersgpl`
/// 变体带全滤镜，可作为后续免削波升级路径）。
library;

import 'dart:math';

import 'package:universal_platform/universal_platform.dart';

double desktopGainCap() {
  return 4.0;
}

/// 桌面端合成后的有效音量（绝对值，0 ~ 上限）。
///
/// macOS：base×gain 合并进 mpv `volume` 属性（volume-max=400，1.80 起 cap=4.0）；
/// Windows：volume 只承载 base（gain 走 af 链），故此值即 base。
double desktopEffectiveVolume(double baseVolume, double gain) {
  if (UniversalPlatform.isWindows) return baseVolume.clamp(0.0, 1.0);
  final base = baseVolume.clamp(0.0, 1.0);
  final g = gain.clamp(1.0, desktopGainCap());
  return (base * g).clamp(0.0, desktopGainCap());
}

/// 供测试注入的平台判定，与 [desktopGainCap]/[desktopEffectiveVolume] 逻辑一致。
double desktopGainCapFor(bool isMac) => 4.0;

/// 供测试注入的平台判定，与 [desktopEffectiveVolume] 逻辑一致。
double desktopVolumeFor(bool isMac, double baseVolume, double gain) {
  if (!isMac) return baseVolume.clamp(0.0, 1.0);
  final base = baseVolume.clamp(0.0, 1.0);
  final g = gain.clamp(1.0, desktopGainCapFor(isMac));
  return (base * g).clamp(0.0, desktopGainCapFor(isMac));
}

/// 返回 gain 对应的 mpv `af` 属性值：
/// - gain ≤ 1.0：空串（清除滤镜链，原始电平直通）；
/// - gain > 1.0：lavfi `volume` 浮点增益 + `alimiter` 软限幅兜底
///   （limit=-1dB 防 0dBFS 削波，level=false 不做整体响度归一，asc 动态提前缓冲）。
///   ⚠️ 仅 Windows 可用；macOS 因缺滤镜必须改用 mpv volume 属性。
String gainAfChain(double gain) {
  if (gain <= 1.0) return '';
  final g = gain.toStringAsFixed(1);
  return 'lavfi=[volume=volume=$g,'
      'alimiter=level=false:limit=-1dB:attack=5:release=50:asc=1:asc_level=0.5]';
}

/// 增益倍率 → AndroidLoudnessEnhancer 目标增益(dB,纯函数)。
/// g ≤ 1.0 返回 0(旁路);2.0x → 6.02dB、4.0x → 12.04dB。
/// dart:math 只有自然对数,log10(g) = ln(g)/ln(10)。
double gainToDb(double gain) {
  if (gain <= 1.0) return 0.0;
  const ln10 = 2.302585092994046;
  return 20.0 * (log(gain) / ln10);
}
