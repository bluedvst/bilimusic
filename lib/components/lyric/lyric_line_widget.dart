import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:bilimusic/theme/app_tokens.dart';
import 'package:bilimusic/utils/lyric_parser.dart';

/// 单条歌词组件 —— 根据是否为当前行分流：
///
/// * **非当前行**：保留 [AnimatedDefaultTextStyle] 的尺寸/字重缓动 + 单层静态柔光。
/// * **当前行**：[_ActiveLyricLine] —— 壁钟插值做逐字填充与动态辉光。
///
/// 颜色统一从主题取（[Colors.white] 作字面色，辉光色跟随 [ThemeData.primaryColor]），
/// 避免硬编码白随主题切换漏出来。
class LyricLineWidget extends StatelessWidget {
  final LyricLine line;
  final bool isCurrentLine;
  final double currentFontSize;
  final double otherFontSize;
  final Duration animationDuration;
  final Curve animationCurve;
  final Function(Duration)? onTap;

  /// 仅当前行使用 —— 该行的区间 `[startTime, endTime)`。
  /// 非当前行忽略。
  final Duration startTime;
  final Duration endTime;

  /// 仅当前行使用 —— 当前播放位置（节流到 ~200ms 一次的 [Duration]）。
  /// 非当前行忽略。
  final Duration currentPosition;

  const LyricLineWidget({
    super.key,
    required this.line,
    required this.isCurrentLine,
    this.currentFontSize = 24,
    this.otherFontSize = 16,
    this.animationDuration = const Duration(milliseconds: 300),
    this.animationCurve = Curves.easeOutCubic,
    this.onTap,
    this.startTime = Duration.zero,
    this.endTime = Duration.zero,
    this.currentPosition = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    const litTextColor = Colors.white;
    final dimTextColor = Colors.white.withValues(alpha: 0.45);
    final glowColor = Theme.of(context).primaryColor;
    final staticShadow = <Shadow>[
      Shadow(
        color: glowColor.withValues(alpha: 0.18),
        blurRadius: 4,
      ),
    ];

    return GestureDetector(
      onTap: () => onTap?.call(Duration(seconds: line.time.toInt())),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: AnimatedDefaultTextStyle(
          duration: animationDuration,
          curve: animationCurve,
          // 颜色由内层字符级渲染覆盖；外层只承担尺寸/字重的 300ms 缓动。
          style: TextStyle(
            fontSize: isCurrentLine ? currentFontSize : otherFontSize,
            fontWeight: isCurrentLine ? FontWeight.w700 : FontWeight.w500,
            color: Colors.transparent,
            height: 1.5,
          ),
          textAlign: TextAlign.left,
          child: isCurrentLine
              ? _ActiveLyricLine(
                  key: ValueKey<double>(line.time),
                  line: line,
                  startTime: startTime,
                  endTime: endTime,
                  currentPosition: currentPosition,
                  litColor: litTextColor,
                  dimColor: dimTextColor,
                  glowColor: glowColor,
                )
              : Text(
                  line.content,
                  style: TextStyle(
                    color: dimTextColor,
                    shadows: staticShadow,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 当前行 —— 逐字点亮 + 动态辉光。
///
/// 用 vsync [Ticker] 每帧推算墙钟估计的播放时间 `t`，借助「字符均分」的填充度公式
/// 给每个字形簇一个独立的 0→1 进度，叠 [AppTokens.standardEasing] 做 ease-out。
/// 外部位置样本（200ms）会重新播种 `_sampleTime`/`_sampleWall`，自然吸附跳转、消除
/// 长期漂移；播放暂停时（位置样本停滞）冻结推进，避免歌词继续走表。
class _ActiveLyricLine extends StatefulWidget {
  final LyricLine line;
  final Duration startTime;
  final Duration endTime;
  final Duration currentPosition;
  final Color litColor;
  final Color dimColor;
  final Color glowColor;

  const _ActiveLyricLine({
    super.key,
    required this.line,
    required this.startTime,
    required this.endTime,
    required this.currentPosition,
    required this.litColor,
    required this.dimColor,
    required this.glowColor,
  });

  @override
  State<_ActiveLyricLine> createState() => _ActiveLyricLineState();
}

class _ActiveLyricLineState extends State<_ActiveLyricLine>
    with SingleTickerProviderStateMixin {
  /// 借 [Ticker] 拿每帧回调 —— 不读取 [AnimationController.value]，仅用它做 vsync 调度。
  late final Ticker _ticker;
  Duration _sampleTime = Duration.zero;
  DateTime _sampleWall = DateTime.fromMillisecondsSinceEpoch(0);
  bool _stopped = false;

  /// 已拆好的字形簇（CJK 安全）。`content` 变化才会重建。
  List<String> _chars = const [];

  /// 多久未收到新位置样本时视为暂停/停止 —— 简单阈值，等同一次节流间隔。
  static const Duration _stallThreshold = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _chars = _splitGraphemes(widget.line.content);
    _reseed(widget.currentPosition);
    _ticker = createTicker(_onFrame)..start();
  }

  void _reseed(Duration position) {
    _sampleTime = position;
    _sampleWall = DateTime.now();
    _stopped = false;
  }

  @override
  void didUpdateWidget(_ActiveLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.content != widget.line.content) {
      _chars = _splitGraphemes(widget.line.content);
    }
    if (oldWidget.currentPosition != widget.currentPosition) {
      _reseed(widget.currentPosition);
      // 立即触发一次 setState 让新位置立刻可见（不再等下一帧）。
      if (mounted) setState(() {});
    }
    if (oldWidget.endTime != widget.endTime) {
      // 行尾短暂延长等场景不会自动重置样本；保持插值连续。
      _stopped = false;
    }
  }

  void _onFrame(Duration _) {
    if (_stopped) return;
    final spanSec = _spanSeconds();
    // 已收尾：保持最后一次 setState 显示，停止 ticker。
    final tSec = _estimatedTimeSeconds();
    final progress =
        spanSec <= 0 ? 1.0 : ((tSec - _startSeconds()) / spanSec).clamp(0.0, 1.0);
    if (progress >= 1.0) {
      _stopped = true;
      _ticker.stop();
      if (mounted) setState(() {});
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ===== Time helpers ===========================================================

  double _startSeconds() => widget.startTime.inMicroseconds / 1e6;

  double _endSeconds() => widget.endTime.inMicroseconds / 1e6;

  double _spanSeconds() => _endSeconds() - _startSeconds();

  /// 估算的当前播放时间（秒）。
  ///
  /// * 正常播放：`sampleTime` + 自上次播种以来的墙钟差。
  /// * 暂停/停止（位置样本长时间没更新）：回退到 `sampleTime` 本身，避免歌词继续走。
  double _estimatedTimeSeconds() {
    final sampleSec = _sampleTime.inMicroseconds / 1e6;
    final wallDelta = DateTime.now().difference(_sampleWall);
    if (wallDelta > _stallThreshold) {
      return sampleSec;
    }
    return sampleSec + wallDelta.inMicroseconds / 1e6;
  }

  /// 拆出用户可感知的字形簇（CJK / emoji / 组合字符安全）。
  static List<String> _splitGraphemes(String s) {
    return s.characters.toList();
  }

  // ===== Build ==================================================================

  @override
  Widget build(BuildContext context) {
    final spanSec = _spanSeconds();
    final tSec = _estimatedTimeSeconds();
    final lineProgress =
        spanSec <= 0 ? 1.0 : ((tSec - _startSeconds()) / spanSec).clamp(0.0, 1.0);
    final n = _chars.length;
    final revealed = lineProgress * n;

    final children = <TextSpan>[];
    for (var i = 0; i < n; i++) {
      final charProgress = (revealed - i).clamp(0.0, 1.0);
      final eased = AppTokens.standardEasing.transform(charProgress);
      final color = Color.lerp(widget.dimColor, widget.litColor, eased)!;
      // 辉光按字符相位调制 alpha —— 未点亮字符 alpha = 0（无 halo），已点亮字符吃满。
      // 等效于「光晕跟随卡拉OK扫光展开」。
      children.add(
        TextSpan(
          text: _chars[i],
          style: TextStyle(
            color: color,
            shadows: <Shadow>[
              Shadow(
                color: widget.glowColor.withValues(alpha: 0.35 * eased),
                blurRadius: 12,
              ),
              Shadow(
                color: widget.glowColor.withValues(alpha: 0.18 * eased),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
          children: children,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }
}
