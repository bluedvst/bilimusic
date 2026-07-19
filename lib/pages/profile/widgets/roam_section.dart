import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/roam_style.dart';
import 'package:bilimusic/providers/playlist_providers.dart';

/// profile_page 上的"漫游模式"区块。
///
/// 设计要点：
/// - 完全独立于 [PlayMode]：`togglePlayMode` 不会进入 roam。
/// - 进入 roam = 清空当前队列并替换为所选歌单。
/// - 退出 roam = 仅停用懒加载，队列保留。
/// - 风格档位离散 3 档（相似 / 平衡 / 探索），默认平衡。
class RoamSection extends ConsumerStatefulWidget {
  const RoamSection({super.key});

  @override
  ConsumerState<RoamSection> createState() => _RoamSectionState();
}

class _RoamSectionState extends ConsumerState<RoamSection> {
  Future<void> _onStartTap() async {
    final settings = ref.read(settingsManagerProvider);
    final style = settings.roamStyle;
    await _showPlaylistPicker(style);
  }

  void _onStopTap() {
    ref.read(playerCoordinatorProvider).stopRoam();
    setState(() {});
  }

  Future<void> _onStyleChanged(Set<RoamStyle> selection) async {
    if (selection.isEmpty) return;
    final style = selection.first;
    await ref.read(settingsManagerProvider).setRoamStyle(style);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsManagerProvider);
    final coordinator = ref.read(playerCoordinatorProvider);
    final isRoaming = coordinator.isRoaming;
    final currentStyle = settings.roamStyle;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.explore_outlined,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '漫游模式',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isRoaming
                  ? '正在漫游：${_resolvePlaylistName(coordinator.roamPlaylistId)}'
                  : '从歌单出发，自动发现相似/探索的歌曲',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            // 风格档位（即便在漫游中也允许切换，影响下一次 refill）
            SegmentedButton<RoamStyle>(
              segments: const [
                ButtonSegment(
                  value: RoamStyle.similar,
                  label: Text('相似'),
                  icon: Icon(Icons.compare_arrows),
                ),
                ButtonSegment(
                  value: RoamStyle.balanced,
                  label: Text('平衡'),
                  icon: Icon(Icons.balance),
                ),
                ButtonSegment(
                  value: RoamStyle.explore,
                  label: Text('探索'),
                  icon: Icon(Icons.travel_explore),
                ),
              ],
              selected: {currentStyle},
              onSelectionChanged: _onStyleChanged,
            ),
            const SizedBox(height: 16),
            // 主操作按钮
            SizedBox(
              width: double.infinity,
              child: isRoaming
                  ? FilledButton.tonalIcon(
                      onPressed: _onStopTap,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('停止漫游'),
                      style: FilledButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _onStartTap,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('开始漫游'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 解析 playlistId → 显示用名称。
  String _resolvePlaylistName(String? id) {
    if (id == null) return '未知歌单';
    if (id == 'favorites') return DefaultPlaylists.favorites.name;
    final user = ref.read(userPlaylistsProvider).where((p) => p.id == id);
    if (user.isNotEmpty) return user.first.name;
    return id;
  }

  /// 弹出底部 sheet：顶部介绍 + 警告横幅，下方歌单列表。
  Future<void> _showPlaylistPicker(RoamStyle style) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _RoamPlaylistSheet(style: style),
    );
    // sheet 关闭后 refresh active 状态
    if (mounted) setState(() {});
  }
}

/// 底部 sheet 内容。
///
/// 顶部为介绍 + 警告横幅（必加，提醒"将清空当前队列"）。
/// 下半部为歌单列表：favorites + 用户自建歌单。
class _RoamPlaylistSheet extends ConsumerWidget {
  const _RoamPlaylistSheet({required this.style});

  final RoamStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final userPlaylists = ref.watch(userPlaylistsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Column(
          children: [
            // 顶部拖拽指示条
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择漫游种子歌单',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            // 介绍 + 警告横幅（必加）
            const _RoamBanner(),
            const SizedBox(height: 8),
            // 歌单列表
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  if (favorites.isNotEmpty)
                    _PlaylistTile(
                      playlistId: 'favorites',
                      name: DefaultPlaylists.favorites.name,
                      songCount: favorites.length,
                      style: style,
                      icon: Icons.favorite,
                      iconColor: Colors.red,
                    ),
                  for (final p in userPlaylists)
                    _PlaylistTile(
                      playlistId: p.id,
                      name: p.name,
                      songCount: p.songCount,
                      style: style,
                      icon: Icons.queue_music,
                      iconColor: Colors.blue,
                    ),
                  if (favorites.isEmpty && userPlaylists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          '暂无可用歌单\n请先收藏歌曲或创建歌单',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 介绍 + 警告横幅：出现在 sheet 内容顶部，不被裁剪。
class _RoamBanner extends StatelessWidget {
  const _RoamBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.amber[800], size: 20),
              const SizedBox(width: 8),
              Text(
                '全新功能：漫游模式',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '基于所选歌单无限发现相似音乐。',
            style: TextStyle(fontSize: 13, color: Colors.amber[900]),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.orange[700], size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '⚠ 进入后将清空当前播放队列',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 歌单列表项。点击后关闭 sheet 并启动 roam。
class _PlaylistTile extends ConsumerWidget {
  const _PlaylistTile({
    required this.playlistId,
    required this.name,
    required this.songCount,
    required this.style,
    required this.icon,
    required this.iconColor,
  });

  final String playlistId;
  final String name;
  final int songCount;
  final RoamStyle style;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      enabled: songCount > 0,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        name,
        style: TextStyle(
          color: songCount > 0 ? null : Colors.grey,
        ),
      ),
      subtitle: Text(songCount > 0 ? '$songCount 首歌曲' : '空歌单'),
      trailing: songCount > 0
          ? const Icon(Icons.arrow_forward_ios, size: 14)
          : null,
      onTap: songCount > 0
          ? () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context); // 关闭 sheet
              try {
                await ref
                    .read(playerCoordinatorProvider)
                    .startRoam(playlistId, style);
                messenger.showSnackBar(
                  SnackBar(content: Text('已开始从「$name」漫游')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('启动漫游失败: $e')),
                );
              }
            }
          : null,
    );
  }
}