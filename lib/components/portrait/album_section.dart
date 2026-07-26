import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/utils/animations.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/components/landscape/apple_cover.dart';
import 'package:bilimusic/components/common/landscape_seek_bar.dart';
import 'package:bilimusic/components/common/playback_buttons.dart';
import 'package:bilimusic/providers/playback_providers.dart';

/// 竖屏详情页单面板：
/// 封面 + 歌曲信息 + 收藏/分享 + 进度条 + 5 个播放按钮 + 音量。
/// 切歌时，封面与歌曲信息行淡入 + 上滑，其余控件保持不动。
class PortraitAlbumSection extends ConsumerStatefulWidget {
  final String coverUrl;
  final String title;
  final String artist;
  final String album;
  final Color? dominantColor;
  final bool isFavorite;
  final String? trackId;
  final VoidCallback? onFavoritePressed;
  final VoidCallback? onSharePressed;
  final VoidCallback? onCoverTap;
  final VoidCallback? onShowLyrics;

  // 播放控制
  final bool isPlaying;
  final IconData playModeIcon;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPlayModeToggle;
  final VoidCallback? onPlaylist;

  const PortraitAlbumSection({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.artist,
    required this.album,
    this.dominantColor,
    this.isFavorite = false,
    this.trackId,
    this.onFavoritePressed,
    this.onSharePressed,
    this.onCoverTap,
    this.onShowLyrics,
    required this.isPlaying,
    required this.playModeIcon,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onPlayModeToggle,
    this.onPlaylist,
  });

  @override
  ConsumerState<PortraitAlbumSection> createState() =>
      _PortraitAlbumSectionState();
}

class _PortraitAlbumSectionState extends ConsumerState<PortraitAlbumSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  String? _previousTrackId;

  @override
  void initState() {
    super.initState();
    _previousTrackId = widget.trackId;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
          ),
        );

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(PortraitAlbumSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackId != null &&
        widget.trackId != _previousTrackId &&
        widget.trackId != oldWidget.trackId) {
      _previousTrackId = widget.trackId;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _animated(Widget child) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = PortraitBreakpoints.getHorizontalPadding(context);
    final coverSize = PortraitBreakpoints.getCoverSize(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 封面（带切歌过渡）
          _animated(
            AppleMusicCover(
              coverUrl: widget.coverUrl,
              dominantColor: widget.dominantColor,
              onTap: widget.onCoverTap,
              customSize: coverSize,
            ),
          ),
          SizedBox(height: coverSize * 0.2),
          // 歌曲信息 + 收藏/分享（带切歌过渡）
          _animated(_buildInfoRow(context)),
          SizedBox(height: coverSize * 0.15),
          // 进度条
          const LandscapeSeekBar(
            color: Colors.white,
            widgetHeight: 20,
            seekBarHeight: 10,
          ),
          SizedBox(height: coverSize * 0.1),
          // 5 个播放控制按钮
          _buildControlRow(context),
          SizedBox(height: coverSize * 0.1),
          // 音量调节
          _buildVolumeControl(context),
          SizedBox(height: coverSize * 0.1),
          // 「显示歌词」入口
          if (widget.onShowLyrics != null) _buildLyricsEntry(context),
        ],
      ),
    );
  }

  Widget _buildVolumeControl(BuildContext context) {
    final volume = ref.watch(volumeProvider);
    final commands = ref.read(playbackCommandsProvider.notifier);
    final isMuted = volume == 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TapScaleWidget(
          pressedScale: 0.9,
          onTap: () => commands.toggleMute(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 160,
          height: 20,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              trackShape: const FullWidthTrackShape(),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
              overlayColor: Colors.transparent,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              onChanged: commands.setVolume,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context) {
    final actionSize = PortraitBreakpoints.getCircleActionSize(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSongInfo(context)),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleIconButton(
              icon: widget.isFavorite ? Icons.favorite : Icons.favorite_border,
              iconColor: widget.isFavorite
                  ? (Colors.red[400] ?? Colors.red)
                  : Colors.white,
              size: actionSize,
              iconSize: actionSize * 0.5,
              onTap: widget.onFavoritePressed,
            ),
            const SizedBox(height: 10),
            CircleIconButton(
              icon: Icons.share_outlined,
              iconColor: Colors.white,
              size: actionSize,
              iconSize: actionSize * 0.5,
              onTap: widget.onSharePressed,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSongInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            height: 1.25,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 4),
        Text(
          widget.artist,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 2),
        Text(
          widget.album,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
      ],
    );
  }

  Widget _buildControlRow(BuildContext context) {
    final mainSize = PortraitBreakpoints.getMainPlayButtonSize(context);
    final smallSize = PortraitBreakpoints.getSideButtonSize(context);
    final smallIconSize = smallSize * 0.55;
    final mainIconSize = mainSize * 0.5;
    const gapMain = 22.0;
    const gapSide = 18.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PlaybackControlButton(
          icon: widget.playModeIcon,
          size: smallSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.7),
          onTap: widget.onPlayModeToggle,
        ),
        const SizedBox(width: gapSide),
        PlaybackControlButton(
          icon: Icons.skip_previous,
          size: smallSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.9),
          onTap: widget.onPrevious,
        ),
        const SizedBox(width: gapMain),
        PlaybackPlayPauseButton(
          isPlaying: widget.isPlaying,
          size: mainSize,
          iconSize: mainIconSize,
          onTap: widget.onPlayPause,
        ),
        const SizedBox(width: gapMain),
        PlaybackControlButton(
          icon: Icons.skip_next,
          size: smallSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.9),
          onTap: widget.onNext,
        ),
        const SizedBox(width: gapSide),
        PlaybackControlButton(
          icon: Icons.queue_music,
          size: smallSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.7),
          onTap: widget.onPlaylist,
        ),
      ],
    );
  }

  Widget _buildLyricsEntry(BuildContext context) {
    return TapScaleWidget(
      pressedScale: 0.95,
      onTap: widget.onShowLyrics,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              color: Colors.white.withValues(alpha: 0.85),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '查看歌词',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
