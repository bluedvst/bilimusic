import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/utils/animations.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/components/landscape/apple_cover.dart';
import 'package:bilimusic/components/common/landscape_seek_bar.dart';
import 'package:bilimusic/components/common/playback_buttons.dart';
import 'package:bilimusic/providers/playback_providers.dart';

/// 横屏左侧播放信息面板
/// Apple Music 风格：封面 + 歌曲信息 + 操作按钮 + 进度条 + 5 个播放控制按钮 + 音量
/// 切歌时，封面与歌曲信息行有淡入 + 上滑过渡；其余控件保持不动。
class LandscapeAlbumSection extends ConsumerStatefulWidget {
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

  // 播放控制
  final bool isPlaying;
  final IconData playModeIcon;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPlayModeToggle;
  final VoidCallback? onPlaylist;

  const LandscapeAlbumSection({
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
    required this.isPlaying,
    required this.playModeIcon,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onPlayModeToggle,
    this.onPlaylist,
  });

  @override
  ConsumerState<LandscapeAlbumSection> createState() =>
      _LandscapeAlbumSectionState();
}

class _LandscapeAlbumSectionState extends ConsumerState<LandscapeAlbumSection>
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
  void didUpdateWidget(LandscapeAlbumSection oldWidget) {
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
    final padding = LandscapeBreakpoints.getHorizontalPadding(context);
    final coverSize = LandscapeBreakpoints.getCoverSize(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
      child: SingleChildScrollView(
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
            _animated(_buildInfoRow(context, coverSize)),
            const SizedBox(height: 20),
            // 进度条（与横屏底栏同款的无白点条）
            const LandscapeSeekBar(
              color: Colors.white,
              widgetHeight: 20,
              seekBarHeight: 8,
            ),
            const SizedBox(height: 12),
            // 5 个播放控制按钮
            _buildControlRow(
              context,
              MediaQuery.of(context).size.width <
                  LandscapeBreakpoints.largeTabletMin,
            ),
            const SizedBox(height: 16),
            // 音量调节（Apple Music 风格：喇叭图标 + 细条）
            _buildVolumeControl(context),
            const SizedBox(height: 8),
          ],
        ),
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
        const SizedBox(width: 8),
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

  Widget _buildInfoRow(BuildContext context, double coverSize) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSongInfo(context, coverSize)),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleIconButton(
              icon: widget.isFavorite ? Icons.favorite : Icons.favorite_border,
              iconColor: widget.isFavorite
                  ? (Colors.red[400] ?? Colors.red)
                  : Colors.white,
              size: 44,
              iconSize: 22,
              onTap: widget.onFavoritePressed,
            ),
            const SizedBox(height: 12),
            CircleIconButton(
              icon: Icons.share_outlined,
              iconColor: Colors.white,
              size: 44,
              iconSize: 22,
              onTap: widget.onSharePressed,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSongInfo(BuildContext context, double coverSize) {
    // 标题字号跟随封面尺寸自适应
    final titleFontSize = (coverSize * 0.11).clamp(18.0, 26.0);
    final subtitleFontSize = (coverSize * 0.07).clamp(13.0, 17.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(
          widget.title,
          style: TextStyle(
            color: Colors.white,
            fontSize: titleFontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 4),
        // 艺术家
        Text(
          widget.artist,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 2),
        // 专辑
        Text(
          widget.album,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: subtitleFontSize * 0.9,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
      ],
    );
  }

  Widget _buildControlRow(BuildContext context, bool isSmall) {
    final mainSize = LandscapeBreakpoints.getMainPlayButtonSize(context);
    final smallSize = isSmall ? 32.0 : 36.0;
    final smallIconSize = isSmall ? 18.0 : 20.0;
    final mainIconSize = mainSize * 0.5;
    final gapMain = isSmall ? 16.0 : 20.0;
    final gapSide = isSmall ? 20.0 : 24.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 播放模式
        PlaybackControlButton(
          icon: widget.playModeIcon,
          size: smallSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.7),
          onTap: widget.onPlayModeToggle,
        ),
        SizedBox(width: gapSide),
        // 上一曲
        PlaybackControlButton(
          icon: Icons.skip_previous,
          size: smallSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.9),
          onTap: widget.onPrevious,
        ),
        SizedBox(width: gapMain),
        // 播放/暂停
        PlaybackPlayPauseButton(
          isPlaying: widget.isPlaying,
          size: mainSize,
          iconSize: mainIconSize,
          onTap: widget.onPlayPause,
        ),
        SizedBox(width: gapMain),
        // 下一曲
        PlaybackControlButton(
          icon: Icons.skip_next,
          size: smallSize,
          iconSize: smallIconSize,
          iconColor: Colors.white.withValues(alpha: 0.9),
          onTap: widget.onNext,
        ),
        SizedBox(width: gapSide),
        // 播放列表
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
}

/// 圆形图标按钮 —— 独立式，半透明白底 + 按压缩放。
/// 复用见 [lib/components/common/playback_buttons.dart] 中的 [CircleIconButton]。

/// 播放控制小按钮（TapScaleWidget + 图标）。
/// 复用见 [lib/components/common/playback_buttons.dart] 中的 [PlaybackControlButton]。

/// 主播放/暂停按钮（白色渐变圆形 + AnimatedSwitcher）。
/// 复用见 [lib/components/common/playback_buttons.dart] 中的 [PlaybackPlayPauseButton]。

/// 全宽度轨道形状 —— 圆角矩形，active 段按 thumbCenter 截断。
/// 复用见 [lib/components/common/playback_buttons.dart] 中的 [FullWidthTrackShape]。
