import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../assets/sprite_factory.dart';
import '../config/game_config.dart';
import '../config/game_palette.dart';

/// 小鸟组件。
///
/// ## 物理模型
///
/// 采用最经典也最可控的「恒定重力 + 瞬时冲量」模型：
/// - 每帧速度 `v += gravity * dt`
/// - 点击时速度直接设为 [GameConfig.flapVelocity]（而非叠加冲量）
///
/// **为什么用赋值而不是叠加**：叠加会让连续点击的上升速度不断累加，
/// 出现「越点越快」的失控手感。直接赋值保证无论手速多快，
/// 每次点击都精确对应一个固定的上升速度，这是原版 Flappy Bird 的做法。
///
/// ## 子步积分
///
/// 物理推进由 [GameWorld] 以固定步长驱动（见 [GameConfig.fixedTimeStep]），
/// 本组件只负责在单步内更新速度与位置，保证不同刷新率下手感一致。
///
/// ## 动画
///
/// 三帧翅膀动画（上/中/下）循环播放，播放频率随状态变化：
/// - `ready`：慢速扇动，营造待机感
/// - `playing`：中速扇动
/// - 下坠中：固定为「翅膀向上」，模拟收翅下坠
class BirdComponent extends PositionComponent {
  BirdComponent({required Vector2 position})
      : super(
          position: position,
          size: Vector2(GameConfig.birdHitboxRadius * 2.4,
              GameConfig.birdHitboxRadius * 2.4),
          anchor: Anchor.center,
        );

  /// 当前竖直速度（逻辑像素/秒）。正为向下。
  double velocityY = 0;

  /// 当前俯仰角（弧度）。根据竖直速度映射，上升时仰头、下坠时低头。
  double _rotation = 0;

  /// 翅膀动画计时器。
  double _wingTimer = 0;

  /// 当前翅膀帧索引（0=上，1=中，2=下，3=中）。
  int _wingFrame = 0;

  /// 待机状态下的浮动相位（仅 `ready` 状态使用）。
  double _idlePhase = 0;

  /// 三帧翅膀贴图。初始化后不为 null。
  late List<ui.Image> _wingFrames;

  /// 是否已加载完成。
  bool _ready = false;

  /// 是否处于「收翅下坠」表现（死亡坠落阶段）。
  bool _isFalling = false;

  /// 渲染目标尺寸。由碰撞半径推导，并保持贴图原始宽高比。
  late final Vector2 _renderSize = Vector2(
    GameConfig.birdHitboxRadius * 2.6,
    GameConfig.birdHitboxRadius *
        2.6 *
        (SpriteFactory.birdSpriteHeight / SpriteFactory.birdSpriteWidth),
  );

  @override
  Future<void> onLoad() async {
    // 并行加载三帧贴图，减少首帧等待。
    _wingFrames = await Future.wait(<Future<ui.Image>>[
      SpriteFactory.birdWingsUp(),
      SpriteFactory.birdWingsMid(),
      SpriteFactory.birdWingsDown(),
    ]);
    _ready = true;
  }

  /// 施加一次点击冲量。由 [GameWorld] 在收到输入时调用。
  void flap() {
    velocityY = GameConfig.flapVelocity;
    _isFalling = false;
    // 立即切到「翅膀向上」帧，让点击有即时视觉反馈。
    _wingFrame = 0;
    _wingTimer = 0;
  }

  /// 重置到出生状态。重开游戏时调用。
  void reset(Vector2 position) {
    this.position = position;
    velocityY = 0;
    _rotation = 0;
    _wingTimer = 0;
    _wingFrame = 0;
    _idlePhase = 0;
    _isFalling = false;
  }

  /// 进入死亡坠落表现。
  void startFalling() {
    _isFalling = true;
    _wingFrame = 0; // 收翅
  }

  // ---------------------------------------------------------------------------
  // 物理推进
  // ---------------------------------------------------------------------------

  /// 以固定步长推进一帧物理。
  ///
  /// [step] 为固定步长（秒）。位置只做竖直积分，水平方向恒为
  /// [GameConfig.birdStartX]（世界随之滚动，而非小鸟前进）。
  void stepPhysics({required double step}) {
    // 重力积分
    velocityY += GameConfig.gravity * step;

    // 限速：防止长时间下坠后速度过大导致穿过管道
    if (velocityY > GameConfig.maxFallVelocity) {
      velocityY = GameConfig.maxFallVelocity;
    }

    // 位置积分
    position.y += velocityY * step;
  }

  /// 待机浮动。仅 `ready` 状态调用，让小鸟原地轻轻上下浮动。
  void stepIdle({required double step, required double baseY}) {
    _idlePhase += step * 3.2;
    // 振幅 6px 的正弦浮动，比纯静止更有生气。
    position.y = baseY + math.sin(_idlePhase) * 6.0;
    velocityY = 0;
  }

  /// 更新俯仰角与翅膀动画。
  void stepAnimation({required double step, required bool isIdle}) {
    if (isIdle) {
      // 待机时保持水平，翅膀慢速扇动
      _rotation = 0;
      _advanceWing(step, frameDuration: 0.18);
      return;
    }

    // 俯仰角：把竖直速度映射到 [-25°, +85°] 区间。
    // 上升（velocityY < 0）时仰头，下坠时低头，是观感自然的关键。
    const double maxUpAngle = -0.44; // 约 -25°
    const double maxDownAngle = 1.48; // 约 +85°
    final double t = (velocityY / GameConfig.maxFallVelocity).clamp(-1.0, 1.0);
    final double targetAngle = t < 0
        ? t * -maxUpAngle // 上升：按比例仰头
        : t * maxDownAngle; // 下坠：按比例低头

    // 角度平滑插值，避免速度突变时角度跳变。
    _rotation = _lerpAngle(_rotation, targetAngle, math.min(1.0, step * 14.0));

    if (_isFalling) {
      // 死亡坠落：固定在收翅帧，不再扇动。
      _wingFrame = 0;
      return;
    }

    _advanceWing(step, frameDuration: 0.10);
  }

  /// 推进翅膀动画帧。
  void _advanceWing(double step, {required double frameDuration}) {
    _wingTimer += step;
    if (_wingTimer >= frameDuration) {
      _wingTimer -= frameDuration;
      // 循环序列：上 -> 中 -> 下 -> 中 -> 上 ...
      _wingFrame = (_wingFrame + 1) % 4;
    }
  }

  /// 角度线性插值，正确处理 -π/π 环绕。
  static double _lerpAngle(double from, double to, double t) {
    double delta = to - from;
    // 归一化到 [-π, π]，确保走最短弧
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    return from + delta * t;
  }

  /// 当前碰撞半径。以圆形近似判定，宽容度见 [GameConfig.birdHitboxRadius]。
  double get collisionRadius => GameConfig.birdHitboxRadius;

  // ---------------------------------------------------------------------------
  // 渲染
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    if (!_ready) {
      return;
    }

    // 解析当前应显示的贴图。帧序列 0/2/4 分别对应上/中/下，1/3 复用「中」。
    final ui.Image frame = switch (_wingFrame) {
      0 => _wingFrames[0],
      1 => _wingFrames[1],
      2 => _wingFrames[2],
      _ => _wingFrames[1],
    };

    canvas.save();
    // 以组件中心为原点旋转，再居中绘制贴图。
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(_rotation);

    final Rect dst = Rect.fromCenter(
      center: Offset.zero,
      width: _renderSize.x,
      height: _renderSize.y,
    );
    canvas.drawImageRect(
      frame,
      Rect.fromLTWH(
        0,
        0,
        frame.width.toDouble(),
        frame.height.toDouble(),
      ),
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );

    canvas.restore();
  }

  /// 调试：绘制碰撞圆。
  @override
  void renderDebugMode(Canvas canvas) {
    super.renderDebugMode(canvas);
    canvas.drawCircle(
      Offset(size.x / 2, size.y / 2),
      collisionRadius,
      GamePalette.debugHitboxPaint,
    );
  }
}
