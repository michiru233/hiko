import 'package:flutter/material.dart';
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
/// —— 那句是 1.99.17 的旧认识，1.99.18 起移动端也走通道（裸 push 出来的
/// 详情页没有筛选回调），落栈方式见下面的 [pushDetailAboveList]。

/// 请求打开本地专辑详情抽屉（消费方 HomeScreen）：值为 album.id
final localDetailRequestProvider = StateProvider<String?>((ref) => null);

/// 请求打开在线作品详情（消费方 OnlineScreen；HomeScreen 只借它切到在线视图）：
/// 值为 workId
final onlineDetailRequestProvider = StateProvider<int?>((ref) => null);

/// 移动端「播放页跳详情」的落栈方式（1.99.19 裁决 Q2=A）。
///
/// **详情页之上不留历史**：从「!」跳过去以后，一次返回必须回到列表 ——
/// 旧实现是裸 `push`，于是「详情页叠详情页」，用户要连按两次才回列表
/// （实机反馈：退了一次还在详情页）。
///
/// 播放页此刻已经在自己的 pop 动画里（`_openAlbumDetail` 先 pop 再发请求）：
/// 它不满足 `isFirst`，但 navigator 会把它留在历史里等动画播完 ——
/// 实测 `pushAndRemoveUntil` 不会打断它，交叉淡入的观感与旧实现逐帧一致，
/// 只是它上面/下面的旧详情页被摘掉了（回归锁见
/// `test/ui/player_detail_jump_test.dart`）。
///
/// 只用于**从播放页跳过去**的那一次 push：列表点卡片开详情、详情页之间
/// 的语言版本跳转（1.99.2 明确要「返回回原作品」）都保持普通压栈。
Future<T?> pushDetailAboveList<T>(NavigatorState navigator, Route<T> route) {
  return navigator.pushAndRemoveUntil<T>(route, (Route<dynamic> r) => r.isFirst);
}
