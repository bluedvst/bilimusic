import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/sync/peer_device.dart';
import 'package:bilimusic/services/sync/lan_sync_service.dart';

/// 对端列表流（已发现的所有设备，含未配对）。
final peersProvider = StreamProvider<List<PeerDevice>>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.peerList;
});

/// 当前对端推送的"现在播放"。
final remoteNowPlayingProvider = StreamProvider<RemoteNowPlaying?>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.remoteNowPlaying;
});

/// 被动方收到的 PIN 请求流。
final pinRequestsProvider = StreamProvider<PinRequest>((ref) {
  final svc = ref.watch(lanSyncServiceProvider);
  return svc.pinRequests;
});
