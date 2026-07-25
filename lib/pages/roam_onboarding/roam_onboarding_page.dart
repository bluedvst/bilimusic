import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/components/common/roam_style_segmented.dart';
import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/roam_style.dart';
import 'package:bilimusic/pages/roam_onboarding/widgets/import_config_dialog.dart';
import 'package:bilimusic/pages/roam_onboarding/widgets/roam_playlist_picker.dart';
import 'package:bilimusic/pages/roam_onboarding/widgets/seed_card.dart';
import 'package:bilimusic/providers/roam_onboarding_provider.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/services/roaming_service.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/theme/app_palette.dart';
import 'package:bilimusic/theme/app_tokens.dart';

/// 漫游引导主页（Apple 风格多步状态机）。
///
/// 步骤：
/// - [OnboardingStep.pickPlaylist]  → _PlaylistStep
/// - [OnboardingStep.prefetchLoading] → _PrefetchStep
/// - [OnboardingStep.pickSeeds]     → _SeedStep (PageView)
/// - [OnboardingStep.pickStyle]     → _StyleStep
/// - [OnboardingStep.finalLoading]  → _FinalLoadingStep
/// - [OnboardingStep.error]         → _ErrorStep
/// - [OnboardingStep.done]          → 立即触发 apply()
class RoamOnboardingPage extends ConsumerWidget {
  const RoamOnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roamOnboardingProvider);

    // 监听 step=done 触发 apply
    ref.listen<OnboardingState>(roamOnboardingProvider, (prev, next) {
      if (next.step == OnboardingStep.done) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(roamOnboardingProvider.notifier).apply();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('漫游模式'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => ShellPageManager.instance.pop(),
        ),
      ),
      body: PopScope(
        canPop: state.step != OnboardingStep.finalLoading,
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: AppTokens.standardDuration,
            switchInCurve: AppTokens.standardEasing,
            switchOutCurve: AppTokens.standardEasing,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(state.step),
              child: _buildStep(state, ref),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingState state, WidgetRef ref) {
    switch (state.step) {
      case OnboardingStep.pickPlaylist:
        return _PlaylistStep();
      case OnboardingStep.prefetchLoading:
        return _PrefetchStep(statusMessage: state.statusMessage);
      case OnboardingStep.pickSeeds:
        return _SeedStep();
      case OnboardingStep.pickStyle:
        return _StyleStep();
      case OnboardingStep.finalLoading:
        return _FinalLoadingStep(statusMessage: state.statusMessage);
      case OnboardingStep.error:
        return _ErrorStep(error: state.error ?? '未知错误');
      case OnboardingStep.done:
        return _PlayingStep();
    }
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [A] 选歌单
// ────────────────────────────────────────────────────────────

class _PlaylistStep extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PlaylistStep> createState() => _PlaylistStepState();
}

class _PlaylistStepState extends ConsumerState<_PlaylistStep> {
  Future<void> _onImportTap() async {
    final config = await showImportConfigDialog(context);
    if (config == null) return;
    if (!mounted) return;

    // 屏蔽背景交互的加载层
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final PlayerCoordinator coordinator;
    final RoamingService roaming;
    try {
      coordinator = ref.read(playerCoordinatorProvider);
      roaming = ref.read(roamingServiceProvider);

      // 1. 把 bvid 还原成完整的 Music，验证视频仍可访问
      final seeds = await Future.wait(
        config.seeds.map(roaming.resolveSeed),
      );

      // 2. 预取一批推荐，确保初始队列饱满
      final recs = await roaming.fetchMultiSeed(
        seeds: seeds,
        style: config.style,
        totalSize: 6,
      );

      // 3. 应用
      await coordinator.applyRoamPlaylist(
        songs: [...seeds, ...recs],
        style: config.style,
        seeds: seeds,
      );
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
      return;
    }

    // 成功路径：关闭加载层 + 退出 onboarding 页
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    ShellPageManager.instance.pop();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(roamOnboardingProvider.notifier);
    final state = ref.watch(roamOnboardingProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.content_paste_go, color: Colors.purple),
          title: const Text('导入配置'),
          subtitle: const Text('粘贴已保存的漫游配置直接开始'),
          onTap: _onImportTap,
        ),
        if (state.error != null) _ErrorBanner(message: state.error!),
        Expanded(
          child: RoamPlaylistPicker(
            showTitle: false,
            onPlaylistSelected: (id, name, count) {
              notifier.selectPlaylist(id, name);
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [A.5] 预取
// ────────────────────────────────────────────────────────────

class _PrefetchStep extends StatelessWidget {
  const _PrefetchStep({this.statusMessage});
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 3),
          const SizedBox(height: 24),
          Text(
            statusMessage ?? '正在准备漫游...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [B] 选种子（PageView）
// ────────────────────────────────────────────────────────────

class _SeedStep extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SeedStep> createState() => _SeedStepState();
}

class _SeedStepState extends ConsumerState<_SeedStep> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 同步外部 currentSectionIndex 变化（如 dot indicator 点击）
    ref.listen<OnboardingState>(roamOnboardingProvider, (prev, next) {
      if (prev?.currentSectionIndex != next.currentSectionIndex) {
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            next.currentSectionIndex,
            duration: AppTokens.standardDuration,
            curve: AppTokens.standardEasing,
          );
        }
      }
    });

    final state = ref.watch(roamOnboardingProvider);
    final notifier = ref.read(roamOnboardingProvider.notifier);

    return Column(
      children: [
        // 顶部标题
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选 ${state.roundsCount} 颗你想漫游的种子',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '每轮从歌单中挑出一些候选，你选 1 颗作为这轮漫游方向',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (state.roundsCount > 1) ...[
                const SizedBox(height: 8),
                _SwipeHint(),
              ],
            ],
          ),
        ),
        // PageView
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => notifier.setSectionIndex(i),
            itemCount: state.roundsCount,
            itemBuilder: (_, round) => _RoundPage(round: round),
          ),
        ),
        // dot indicator + 继续按钮
        _SeedBottomBar(),
      ],
    );
  }
}

class _RoundPage extends ConsumerWidget {
  const _RoundPage({required this.round});
  final int round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roamOnboardingProvider);
    final options = state.roundOptions[round];
    final selectedIndex = state.selectedSeedIndex[round] ?? 0;
    final notifier = ref.read(roamOnboardingProvider.notifier);

    if (options.isEmpty) {
      return Center(
        child: Text(
          '这轮没有候选歌曲',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        return SeedCard(
          music: options[i],
          selected: i == selectedIndex,
          onTap: () => notifier.selectSeed(round, i),
        );
      },
    );
  }
}

class _SeedBottomBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roamOnboardingProvider);
    final notifier = ref.read(roamOnboardingProvider.notifier);
    final palette = context.appPalette;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: palette.panelSurface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // dot indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(state.roundsCount, (i) {
              final selected = i == state.currentSectionIndex;
              return GestureDetector(
                onTap: () => notifier.setSectionIndex(i),
                child: AnimatedContainer(
                  duration: AppTokens.standardDuration,
                  curve: AppTokens.standardEasing,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state.allSeedsPicked ? notifier.goToStyle : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('继续'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Apple 风格的小提示徽章：左右滑动切换轮次。
class _SwipeHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.swipe,
            size: 14,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 6),
          Text(
            '左右滑动切换轮次 · 点击卡片换种子',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [C] 选风格
// ────────────────────────────────────────────────────────────

class _StyleStep extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roamOnboardingProvider);
    final notifier = ref.read(roamOnboardingProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '选漫游风格',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '决定续杯时如何挑选新歌',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 32),
          RoamStyleSegmented(
            selected: state.style,
            onChanged: notifier.setStyle,
          ),
          const SizedBox(height: 24),
          _StyleDescription(style: state.style),
          const Spacer(),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () => notifier.goToFinalFetch(),
              child: const Text('开始漫游'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleDescription extends StatelessWidget {
  const _StyleDescription({required this.style});
  final RoamStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desc = switch (style) {
      RoamStyle.similar => '顺着当前方向走，每首都和上一首很像',
      RoamStyle.balanced => '在相似和探索之间随机挑选',
      RoamStyle.explore => '走相反的方向，每首都是新风格',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(desc, style: theme.textTheme.bodyMedium),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [D] 最终拉取
// ────────────────────────────────────────────────────────────

class _FinalLoadingStep extends StatelessWidget {
  const _FinalLoadingStep({this.statusMessage});
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 3),
          const SizedBox(height: 24),
          Text(
            statusMessage ?? '正在为你生成歌单...',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 错误步骤
// ────────────────────────────────────────────────────────────

class _ErrorStep extends ConsumerWidget {
  const _ErrorStep({required this.error});
  final String error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(roamOnboardingProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => ShellPageManager.instance.pop(),
                child: const Text('返回'),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: notifier.retryFinalFetch,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [F] 已开始漫游（成功落地页）
// ────────────────────────────────────────────────────────────

class _PlayingStep extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(roamOnboardingProvider);
    final songCount = state.finalPlaylist?.length ?? 0;
    final styleName = switch (state.style) {
      RoamStyle.similar => '相似',
      RoamStyle.balanced => '平衡',
      RoamStyle.explore => '探索',
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 成功图标
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              color: theme.colorScheme.onPrimary,
              size: 56,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '已开始漫游',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已为你生成 $songCount 首歌 · $styleName风格',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (state.playlistName != null) ...[
            const SizedBox(height: 4),
            Text(
              '基于歌单：${state.playlistName}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => ShellPageManager.instance.pop(),
              child: const Text('返回'),
            ),
          ),
        ],
      ),
    );
  }
}
