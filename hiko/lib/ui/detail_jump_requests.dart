import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「播放页跳详情」指令通道（1.99.17）。
///
/// 全屏播放页压在 home 之上，拿不到 HomeScreen / OnlineScreen 的 setState；
/// 桌面端的本地详情抽屉与在线详情面板又分别长在两处内部状态里，所以走这种
/// 单向 StateProvider 请求：播放页写、消费方读后**自行清空**（置 null），
/// 避免下次挂载时把旧请求再开一遍。清空会再触发一轮监听，消费方必须
/// 对 null 直接 return。
///
/// 移动端不走这里：详情是独立整页路由，播放页直接 pushReplacement 即可。

/// 请求打开本地专辑详情抽屉（消费方 HomeScreen）：值为 album.id
final localDetailRequestProvider = StateProvider<String?>((ref) => null);

/// 请求打开在线作品详情（消费方 OnlineScreen；HomeScreen 只借它切到在线视图）：
/// 值为 workId
final onlineDetailRequestProvider = StateProvider<int?>((ref) => null);
