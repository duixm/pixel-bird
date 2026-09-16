import 'package:flame/palette.dart';
import 'package:flutter/material.dart';

/// 游戏配色与视觉常量。
///
/// 保持经典 Flappy Bird 的「日间」色调：青蓝天空、草绿管道、暖沙地面。
/// 所有颜色集中定义，便于整体换肤（例如后续增加夜间模式）。
class GamePalette {
  GamePalette._();

  // ---- 天空与背景 ----
  /// 天空主色。取自经典 Flappy Bird 日间背景的中间调。
  static const Color skyTop = Color(0xFF4EC0CA);
  static const Color skyBottom = Color(0xFF7ED4DC);

  /// 远景城市/云层剪影色。
  static const Color skyline = Color(0xFF5AAE85);

  // ---- 地面 ----
  static const Color groundTop = Color(0xFFDED895);
  static const Color groundBottom = Color(0xFFC9C46F);
  static const Color groundStripe = Color(0xFF9CA84F);

  // ---- 管道 ----
  /// 管道主体绿色。
  static const Color pipeBody = Color(0xFF74BF2E);
  /// 管道高光侧（左侧受光面）。
  static const Color pipeHighlight = Color(0xFFA8E05F);
  /// 管道阴影侧。
  static const Color pipeShadow = Color(0xFF4F8A1C);
  /// 管道管口（较宽的边缘段）色。
  static const Color pipeCap = Color(0xFF5E9E22);
  static const Color pipeCapHighlight = Color(0xFF9BD655);
  /// 管道描边。
  static const Color pipeOutline = Color(0xFF3B6B14);

  // ---- 小鸟 ----
  static const Color birdBody = Color(0xFFF7D51D);
  static const Color birdBelly = Color(0xFFFDF0A8);
  static const Color birdWing = Color(0xFFF0F0F0);
  static const Color birdWingOutline = Color(0xFFBFBFBF);
  static const Color birdBeak = Color(0xFFF08020);
  static const Color birdBeakDark = Color(0xFFD9631A);
  static const Color birdEye = Color(0xFFFFFFFF);
  static const Color birdPupil = Color(0xFF2B2B2B);
  static const Color birdOutline = Color(0xFF8A6D0B);

  // ---- UI ----
  /// 分数文字填充色。
  static const Color scoreFill = Color(0xFFFFFFFF);
  /// 分数文字描边色，保证在浅色天空上依然清晰。
  static const Color scoreStroke = Color(0xFF2B3A42);
  static const Color panelBackground = Color(0xFFFDF6E3);
  static const Color panelOutline = Color(0xFF8A6D0B);
  static const Color accent = Color(0xFFE8A33D);
  static const Color textPrimary = Color(0xFF2B3A42);
  static const Color textSecondary = Color(0xFF6B7A82);

  /// 调试用半透明遮罩（显示碰撞体时使用）。
  static final Paint debugHitboxPaint = Paint()
    ..color = const Color(0xFFFF0000).withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  /// Flame 内置调色板中常用的透明画刷缓存。
  static final Paint transparentPaint = BasicPalette.white.paint()
    ..color = const Color(0x00000000);
}
