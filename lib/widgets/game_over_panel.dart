import 'package:flutter/material.dart';

import '../game/config/game_palette.dart';
import '../game/game_world.dart';

/// 结算面板。
///
/// ## 出现动画
///
/// 用 [AnimatedScale] + [AnimatedOpacity] 做「弹出」效果：面板从 0.85 倍
/// 微缩状态放大到 1.0，同时淡入。这比直接出现更有「结果揭晓」的分量感，
/// 也是休闲游戏的通行做法。
///
/// ## 为什么用 StatefulWidget
///
/// 需要驱动一次性的入场动画（首帧后切换标志位触发 AnimatedXxx）。
class GameOverPanel extends StatefulWidget {
  const GameOverPanel({
    required this.result,
    required this.onRestart,
    required this.onOpenSettings,
    super.key,
  });

  /// 本局结果快照。
  final RunResult result;

  /// 点击「再来一局」的回调。
  final VoidCallback onRestart;

  /// 点击设置按钮的回调。
  final VoidCallback onOpenSettings;

  @override
  State<GameOverPanel> createState() => _GameOverPanelState();
}

class _GameOverPanelState extends State<GameOverPanel> {
  /// 入场动画开关。首帧置为 true 触发过渡。
  bool _visible = false;

  /// 分数数字的滚动计数动画值。
  int _displayedScore = 0;

  @override
  void initState() {
    super.initState();
    // 在首帧之后触发动画，确保 AnimatedXxx 能检测到状态变化。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _visible = true);
    });
    _runScoreCountUp();
  }

  /// 分数从 0 滚动到最终值，约 500ms。
  ///
  /// 若分数为 0 则直接显示，避免无意义的空转。
  void _runScoreCountUp() {
    final int target = widget.result.score;
    if (target <= 0) {
      return;
    }

    const Duration totalDuration = Duration(milliseconds: 520);
    final Stopwatch stopwatch = Stopwatch()..start();

    // 用重复的 Timer 驱动逐帧更新。相比 AnimationController，
    // 这里无需 TickerProvider，实现更轻量。
    void tick() {
      if (!mounted) {
        return;
      }
      final double progress =
          (stopwatch.elapsedMilliseconds / totalDuration.inMilliseconds)
              .clamp(0.0, 1.0);
      // easeOutCubic：先快后慢，数字停稳时有「刹车」感。
      final double eased = 1 - (1 - progress) * (1 - progress) * (1 - progress);
      final int next = (target * eased).round();

      if (next != _displayedScore) {
        setState(() => _displayedScore = next);
      }

      if (progress < 1.0) {
        // 每 16ms 更新一次，约等于 60fps。
        Future<void>.delayed(const Duration(milliseconds: 16), tick);
      } else if (_displayedScore != target) {
        setState(() => _displayedScore = target);
      }
    }

    tick();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _visible ? 1.0 : 0.85,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: _buildPanel(context),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final bool isNewBest = widget.result.isNewBest;

    return Center(
      child: Container(
        width: 280,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: GamePalette.panelBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: GamePalette.panelOutline, width: 3),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // ---- 标题 ----
            Text(
              isNewBest ? '新纪录！' : '游戏结束',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: isNewBest ? GamePalette.accent : GamePalette.textPrimary,
                letterSpacing: 1.0,
              ),
            ),

            const SizedBox(height: 18),

            // ---- 本局得分 ----
            _buildStatRow(
              label: '本局得分',
              value: '$_displayedScore',
              highlight: isNewBest,
            ),

            const SizedBox(height: 10),

            // ---- 历史最高 ----
            _buildStatRow(
              label: '历史最高',
              value: '${widget.result.bestScore}',
              highlight: false,
            ),

            const SizedBox(height: 22),

            // ---- 主操作按钮 ----
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: widget.onRestart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GamePalette.accent,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                    side: const BorderSide(
                      color: GamePalette.panelOutline,
                      width: 2,
                    ),
                  ),
                ),
                child: const Text(
                  '再来一局',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ---- 次级操作：设置 ----
            TextButton(
              onPressed: widget.onOpenSettings,
              style: TextButton.styleFrom(
                foregroundColor: GamePalette.textSecondary,
              ),
              child: const Text(
                '设置',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建一行「标签 + 数值」的统计展示。
  Widget _buildStatRow({
    required String label,
    required String value,
    required bool highlight,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: GamePalette.textSecondary,
          ),
        ),
        Row(
          children: <Widget>[
            if (highlight) ...<Widget>[
              const Icon(
                Icons.star_rounded,
                size: 20,
                color: GamePalette.accent,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color:
                    highlight ? GamePalette.accent : GamePalette.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
