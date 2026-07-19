import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:bilimusic/api/bili_client.dart';
import 'package:bilimusic/api/bili_exception.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/roam_style.dart';
import 'package:bilimusic/services/playlist_service.dart';
import 'package:bilimusic/utils/music_category.dart';
import 'package:bilimusic/utils/text_simhash.dart';

/// 漫游服务：根据 seed 歌拉相关音乐、按 simhash 排序、按 RoamStyle 挑选。
///
/// 由 PlayerCoordinator 在 `currentIndex` 接近队列末尾时调用。
/// 返回的 Music 列表会被 `addAllToPlaylist` 自动按 (bvid, cid) 去重。
class RoamingService {
  RoamingService({
    required BiliClient client,
    required PlaylistService playlistService,
    Random? random,
  })  : _client = client,
        _playlistService = playlistService,
        _random = random ?? Random();

  final BiliClient _client;
  final PlaylistService _playlistService;
  final Random _random;

  /// 拉一批候选候选。
  ///
  /// [size] 默认 3，避免一次性塞太多打断 crossfade 节奏。
  /// 失败或 0 候选时返回 `[]`，调用方据此降级。
  Future<List<Music>> fetchBatch({
    required Music seed,
    required RoamStyle style,
    int size = 3,
  }) async {
    try {
      final raw = await _client.get(
        '/x/web-interface/archive/related',
        query: {'bvid': seed.id},
      );
      if (raw is! List) return const [];

      final candidates = <Music>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final tid = item['tid'] as int?;
        if (!isMusicCategory(tid)) continue;

        final id = (item['bvid'] as String?) ??
            (item['aid']?.toString() ?? '');
        if (id.isEmpty) continue;

        candidates.add(Music(
          id: id,
          title: (item['title'] as String?) ?? '',
          artist: (item['owner']?['name'] as String?) ?? '未知艺术家',
          album: (item['tname'] as String?) ?? '未知专辑',
          coverUrl: '${item['pic'] ?? ''}@672w_378h',
          duration: item['duration'] is int
              ? Duration(seconds: item['duration'] as int)
              : null,
          audioUrl: '',
          pages: const [],
        ));
      }

      return _pick(candidates, seed: seed, style: style, size: size);
    } on BiliException catch (e) {
      debugPrint('[RoamingService] fetch failed for ${seed.id}: $e');
      return const [];
    } catch (e) {
      debugPrint('[RoamingService] unexpected error: $e');
      return const [];
    }
  }

  /// 按 (bvid, cid) 去重 + simhash 排序 + 按 style 挑选 size 个。
  List<Music> _pick(
    List<Music> candidates, {
    required Music seed,
    required RoamStyle style,
    required int size,
  }) {
    if (candidates.isEmpty) return const [];

    // dedup: 排除当前队列和播放历史
    final existing = <String>{
      for (final m in _playlistService.currentPlaylist.value)
        '${m.id}_${m.cid}',
      for (final m in _playlistService.playHistorySnapshot)
        '${m.id}_${m.cid}',
    };
    final fresh = candidates
        .where((m) => !existing.contains('${m.id}_${m.cid}'))
        .toList();
    if (fresh.isEmpty) return const [];

    // simhash 排序
    final seedHash = TextSimHash.simhash(TextSimHash.musicToText(seed));
    fresh.sort((a, b) {
      final ha = TextSimHash.simhash(TextSimHash.musicToText(a));
      final hb = TextSimHash.simhash(TextSimHash.musicToText(b));
      return TextSimHash.hammingFast(seedHash, ha)
          .compareTo(TextSimHash.hammingFast(seedHash, hb));
    });

    switch (style) {
      case RoamStyle.similar:
        return fresh.take(size).toList();
      case RoamStyle.balanced:
        // 随机洗牌后取 size 个，给相似/多样性都留点空间
        final shuffled = List<Music>.from(fresh)..shuffle(_random);
        return shuffled.take(size).toList();
      case RoamStyle.explore:
        // 反向排序后取 size 个（最不像的优先）
        return fresh.reversed.take(size).toList();
    }
  }
}