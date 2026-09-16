import 'package:flutter/material.dart';

import '../game/config/game_palette.dart';

/// 待机状态的「点击开始」提示。
///
/// 包含一个上下跳动的手势图标与文字，通过 [AnimatedBuilder] 循环驱动，
/// 引导玩家第一次点击。这是新玩家上手的关键提示——Flappy Bird 类游戏
/// 没有教程关，全靠这个提示传达操作方式。
class TapToStartHint extends StatefulWidget {
  const TapToStartHint({required this.bestScore, super.key});

  /// 历史最高分。为 0 时不显示（首次游玩不必强调纪录）。
  final int bestScore;

  @override
  State<TapToStartHint> createState() => _TapToStartHintState();
}

class _TapToStartHintState extends State<TapToStartHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // ---- 顶部：历史最高分（仅在有纪录时展示）----
        if (widget.bestScore > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: GamePalette.panelOutline, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.emoji_events_rounded,
                  size: 16,
                  color: GamePalette.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  '最高 ${widget.bestScore}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: GamePalette.textPrimary,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 14),

        // ---- 中部：跳动的手势图标 ----
        AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            // 用正弦让位移更自然（而非线性往返）。
            final double t = _controller.value;
            final double offset = -6 * (1 - (2 * t - 1).abs());
            return Transform.translate(
              offset: Offset(0, offset),
              child: child,
            );
          },
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: GamePalette.panelOutline, width: 2.5),
            ),
            child: const Icon(
              Icons.touch_app_rounded,
              size: 32,
              color: GamePalette.textPrimary,
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ---- 底部：操作说明 ----
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: GamePalette.panelOutline, width: 2),
          ),
          child: const Text(
            '点击屏幕让小鸟飞起来',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: GamePalette.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// 难度提升提示条。分数跨过 10 的整数倍时短暂显示。
class DifficultyNotice extends StatelessWidget {
  const DifficultyNotice({required this.level, super.key});

  /// 当前难度等级。
  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: GamePalette.accent.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: GamePalette.panelOutline, width: 2),
      ),
      child: Text(
        '难度提升 · LV$level',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
