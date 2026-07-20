import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bilimusic/utils/lyric_parser.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/components/lyric/lyric_line_widget.dart';
import 'package:bilimusic/components/lyric/lyric_source.dart';

/// 统一歌词区域组件
/// 同时支持横屏和竖屏布局
class LyricSection extends StatefulWidget {
  final String? title;
  final String? artist;
  final String? album;
  final LyricParser? lyricParser;
  final Duration position;
  final List<LyricSource> lyricSources;
  final String? selectedLyricId;
  final bool isLoadingLyrics;
  final bool showHeader;
  final Function(String)? onLyricSourceChanged;
  final Function(Duration)? onLyricTap;

  const LyricSection({
    super.key,
    this.title,
    this.artist,
    this.album,
    this.lyricParser,
    required this.position,
    this.lyricSources = const [],
    this.selectedLyricId,
    this.isLoadingLyrics = false,
    this.showHeader = true,
    this.onLyricSourceChanged,
    this.onLyricTap,
  });

  @override
  State<LyricSection> createState() => _LyricSectionState();
}

class _LyricSectionState extends State<LyricSection> {
  late ScrollController _scrollController;
  LyricLine? _lastCurrentLine;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LyricSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _scrollToCurrentLyric();
    }
  }

  void _scrollToCurrentLyric() {
    if (widget.lyricParser == null ||
        widget.lyricParser!.lines.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }

    final currentLine = widget.lyricParser!.getCurrentLine(
      widget.position.inMilliseconds / 1000,
    );

    if (currentLine != null && currentLine != _lastCurrentLine) {
      _lastCurrentLine = currentLine;
      final index = widget.lyricParser!.lines.indexOf(currentLine);
      if (index != -1) {
        final isLandscape = _isLandscapeMode();
        final lineHeight = isLandscape ? 66.0 : 48.0;
        final viewportHeight = _scrollController.position.viewportDimension;
        final targetPosition =
            index * lineHeight - (viewportHeight * 0.35) + (lineHeight / 2);

        _scrollController.animateTo(
          targetPosition.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  bool _isLandscapeMode() {
    final size = MediaQuery.of(context).size;
    return size.width >= LandscapeBreakpoints.tabletLandscapeMin &&
        size.width > size.height;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscapeMode();

    if (isLandscape) {
      return _buildLandscapeLayout();
    } else {
      return _buildPortraitLayout();
    }
  }

  Widget _buildLandscapeLayout() {
    final padding = LandscapeBreakpoints.getHorizontalPadding(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showHeader) ...[
                _buildSongInfoHeader(),
                const SizedBox(height: 24),
                const SizedBox(height: 16),
              ],
              Expanded(child: _buildLyricContent()),
            ],
          ),
          if (!widget.isLoadingLyrics && widget.lyricSources.isNotEmpty)
            Positioned(
              right: 0,
              bottom: 16,
              child: _buildLyricSourceButton(),
            ),
        ],
      ),
    );
  }

  /// 歌词区右下角浮动玻璃材质的歌词源切换按钮。
  /// 横竖屏共用 —— 替代内嵌 Dropdown。
  Widget _buildLyricSourceButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: PopupMenuButton<String>(
          initialValue: widget.selectedLyricId,
          color: Colors.grey[900]!.withValues(alpha: 0.95),
          tooltip: '歌词来源',
          onSelected: (id) => widget.onLyricSourceChanged?.call(id),
          itemBuilder: (context) {
            return widget.lyricSources.map((source) {
              final selected = source.id == widget.selectedLyricId;
              return PopupMenuItem<String>(
                value: source.id,
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.check : null,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      source.name,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.lyrics_outlined,
              color: Colors.white.withValues(alpha: 0.7),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                _buildSongInfoHeader(),
                const SizedBox(height: 20),
                Expanded(child: _buildLyricContent()),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (!widget.isLoadingLyrics && widget.lyricSources.isNotEmpty)
            Positioned(
              right: 0,
              bottom: 24,
              child: _buildLyricSourceButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildSongInfoHeader() {
    final isLandscape = _isLandscapeMode();
    final titleSize = isLandscape ? 32.0 : 22.0;
    final artistSize = isLandscape ? 20.0 : 16.0;
    final albumSize = isLandscape ? 16.0 : 13.0;
    final alignment = isLandscape ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = isLandscape ? TextAlign.left : TextAlign.center;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          widget.title ?? '',
          style: TextStyle(
            color: Colors.white,
            fontSize: titleSize,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
        const SizedBox(height: 6),
        Text(
          widget.artist ?? '',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: artistSize,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
        const SizedBox(height: 4),
        Text(
          widget.album ?? '',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: albumSize,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
      ],
    );
  }

  Widget _buildLyricContent() {
    if (widget.isLoadingLyrics) {
      return _buildLoadingState();
    }

    if (widget.lyricParser == null) {
      return _buildEmptyState('选择歌词来源后显示歌词');
    }

    if (widget.lyricParser!.lines.isEmpty) {
      return _buildEmptyState('暂无歌词');
    }

    return _buildLyricList();
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(
        color: Colors.white.withValues(alpha: 0.6),
        strokeWidth: 2,
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lyrics_outlined,
            size: 48,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricList() {
    final lines = widget.lyricParser!.lines;
    final currentLine = widget.lyricParser!.getCurrentLine(
      widget.position.inMilliseconds / 1000,
    );
    final isLandscape = _isLandscapeMode();
    final currentFontSize = isLandscape
        ? LandscapeBreakpoints.getCurrentLyricFontSize(context)
        : 22.0;
    final otherFontSize = isLandscape
        ? LandscapeBreakpoints.getOtherLyricFontSize(context)
        : 16.0;

    // 当前行专用：endTime 取下一行的时间戳；末行给 fallback 4s 让填充走完。
    const endFallbackSec = 4.0;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.25,
      ),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final isCurrentLine = line == currentLine;

        Duration startTime = Duration.zero;
        Duration endTime = Duration.zero;
        if (isCurrentLine) {
          final startSec = line.time;
          final endSec = (index + 1 < lines.length)
              ? lines[index + 1].time
              : startSec + endFallbackSec;
          startTime = Duration(milliseconds: (startSec * 1000).round());
          endTime = Duration(milliseconds: (endSec * 1000).round());
        }

        return LyricLineWidget(
          line: line,
          isCurrentLine: isCurrentLine,
          currentFontSize: currentFontSize,
          otherFontSize: otherFontSize,
          onTap: widget.onLyricTap,
          startTime: startTime,
          endTime: endTime,
          currentPosition: widget.position,
        );
      },
    );
  }
}
