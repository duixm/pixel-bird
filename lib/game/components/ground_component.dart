import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../assets/sprite_factory.dart';
import '../config/game_config.dart';

/// 滚动地面组件。
///
/// ## 实现方式：单条无限滚动带
///
/// 维护一个持续左移的偏移量 [scrollOffset]，并在整个屏幕宽度上重复绘制
/// 地面贴图。偏移量对贴图宽度取模后即可无缝衔接——
/// 这是最省内存的滚动实现（只需一张贴图，无需创建/回收多个组件）。
///
/// ## 与小鸟的交互
///
/// 地面参与碰撞（小鸟触地即死亡）。碰撞矩形由 [groundRect] 提供。
class GroundComponent extends PositionComponent {
  GroundComponent()
      : super(
          position: Vector2(0, GameConfig.designSize.height - GameConfig.groundHeight),
          size: Vector2(GameConfig.designSize.width, GameConfig.groundHeight),
          anchor: Anchor.topLeft,
        );

  /// 滚动偏移量（逻辑像素）。累积后对贴图宽度取模。
  double _scrollOffset = 0;

  late ui.Image _tileImage;
  bool _ready = false;

  /// 地面的世界坐标碰撞矩形。
  Rect get groundRect => Rect.fromLTWH(
        position.x,
        position.y,
        size.x,
        size.y,
      );

  @override
  Future<void> onLoad() async {
    _tileImage = await SpriteFactory.groundTile();
    _ready = true;
  }

  /// 以固定步长推进滚动。
  void stepScroll({required double step, required double speed}) {
    _scrollOffset += speed * step;
    // 取模避免长时间游玩后浮点数精度损失。
    final double tileW = SpriteFactory.groundTileWidth.toDouble();
    if (_scrollOffset >= tileW) {
      _scrollOffset %= tileW;
    }
  }

  /// 重置滚动位置。重开时调用。
  void reset() => _scrollOffset = 0;

  @override
  void render(Canvas canvas) {
    if (!_ready) {
      return;
    }

    final double tileW = SpriteFactory.groundTileWidth.toDouble();
    final double tileH = size.y;
    final double imgW = _tileImage.width.toDouble();
    final double imgH = _tileImage.height.toDouble();
    final Rect srcFull = Rect.fromLTWH(0, 0, imgW, imgH);
    final Paint paint = Paint()..filterQuality = FilterQuality.low;

    // 从 -scrollOffset 开始，每 tileW 绘制一张，直到覆盖整个屏幕宽度。
    double x = -_scrollOffset;
    while (x < size.x) {
      canvas.drawImageRect(
        _tileImage,
        srcFull,
        Rect.fromLTWH(x, 0, tileW, tileH),
        paint,
      );
      x += tileW;
    }
  }
}
