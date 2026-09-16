import 'package:flutter/material.dart';

import '../game/config/game_palette.dart';

/// 分数显示组件。
///
/// ## 为什么用描边文字而不是直接绘制
///
/// 游戏背景是浅色天空，纯白数字会「糊」在一起。这里采用**深色描边 + 白色填充**
/// 的经典做法：先以 `PaintingStyle.stroke` 画一遍粗描边，再以
/// `PaintingStyle.fill` 画填充。这样数字在任何背景上都清晰可辨，
/// 且形成像素游戏特有的「卡通描边」质感。
class ScoreDisplay extends StatelessWidget {
  const ScoreDisplay({
    required this.score,
    this.fontSize = 62,
    this.showShadow = true,
    super.key,
  });

  /// 当前分数。
  final int score;

  /// 字号（逻辑像素）。结算面板中的大分数可传更大的值。
  final int fontSize;

  /// 是否绘制描边。结算面板内背景为浅色板，可关闭描边。
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    // 描边宽度随字号等比缩放，保证不同字号下观感一致。
    final double strokeWidth = fontSize * 0.075;

    return Text(
      '$score',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: fontSize.toDouble(),
        fontWeight: FontWeight.w900,
        height: 1.0,
        // letterSpacing 略为收紧，让大数字更紧凑有力。
        letterSpacing: -1.0,
        foreground: showShadow
            ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = GamePalette.scoreStroke)
            : null,
        color: showShadow ? null : GamePalette.textPrimary,
        shadows: showShadow
            ? <Shadow>[
                // 描边之外再加一层柔和投影，进一步强化可读性。
                Shadow(
                  color: GamePalette.scoreStroke.withValues(alpha: 0.35),
                  offset: Offset(0, fontSize * 0.045),
                  blurRadius: fontSize * 0.10,
                ),
              ]
            : null,
      ),
    );
  }
}

/// 带描边的数字（用于分数）。描边与填充分两层绘制。
///
/// 由于 Flutter 的 `TextStyle.foreground` 与 `color` 互斥，无法在同一个
/// `Text` 中同时表现描边和填充，因此这里采用 `Stack` 叠加两层的方案。
/// 这是 Flutter 中实现「描边文字」的标准做法。
class OutlinedScoreText extends StatelessWidget {
  const OutlinedScoreText({
    required this.score,
    this.fontSize = 62,
    super.key,
  });

  final int score;
  final int fontSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // 底层：描边
        ScoreDisplay(score: score, fontSize: fontSize, showShadow: true),
        // 上层：填充
        Text(
          '$score',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize.toDouble(),
            fontWeight: FontWeight.w900,
            height: 1.0,
            letterSpacing: -1.0,
            color: GamePalette.scoreFill,
          ),
        ),
      ],
    );
  }
}
