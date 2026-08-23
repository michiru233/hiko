/// 音频增益 af 链构建（mpv lavfi 滤镜串，纯函数可单测）。
///
/// 破音根因：libmpv 的 volume 属性 clamp 130，>1.3x 部分被硬削波；
/// 增益必须在 af 滤镜链内以 64-bit 浮点域完成，volume 属性只承担 0~1 常规音量。
library;

/// 返回 gain 对应的 mpv `af` 属性值：
/// - gain ≤ 1.0：空串（清除滤镜链，原始电平直通）；
/// - gain > 1.0：lavfi `volume` 浮点增益 + `alimiter` 软限幅兜底
///   （limit=-1dB 防 0dBFS 削波，level=false 不做整体响度归一，asc 动态提前缓冲）。
String gainAfChain(double gain) {
  if (gain <= 1.0) return '';
  final g = gain.toStringAsFixed(1);
  return 'lavfi=[volume=volume=$g,'
      'alimiter=level=false:limit=-1dB:attack=5:release=50:asc=1:asc_level=0.5]';
}
