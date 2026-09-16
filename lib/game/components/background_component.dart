import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../assets/sprite_factory.dart';
import '../config/game_config.dart';
import '../config/game_palette.dart';

/// 视差背景组件。
///
/// ## 层次结构（由远及近）
///
/// 1. **天空渐变** —— 静态，不参与滚动。
/// 2. **远景剪影**（云与树林）—— 以 [GameConfig.backgroundScrollSpeed] 慢速滚动，
///    速度约为管道的 1/5，从而产生纵深感。
/// 3. **近景管道与地面** —— 由各自组件以管道速度滚动。
///
/// 三层速度差构成标准的视差（parallax）效果，是本类游戏「廉价但有质感」的关键。
class BackgroundComponent extends PositionComponent {
  BackgroundComponent()
      : super(
          position: Vector2.zero(),
          size: Vector2(GameConfig.designSize.width, GameConfig.designSize.height),
          anchor: Anchor.topLeft,
        );

  /// 远景滚动偏移量。
  double _scrollOffset = 0;

  late ui.Image _skylineImage;
  bool _ready = false;

  @override
  Future<void> onLoad() async {
    _skylineImage = await SpriteFactory.skylineTile();
    _ready = true;
  }

  void stepScroll({required double step, required double speed}) {
    _scrollOffset += speed * step;
    final double tileW = SpriteFactory.skylineTileWidth.toDouble();
    if (_scrollOffset >= tileW) {
      _scrollOffset %= tileW;
    }
  }

  void reset() => _scrollOffset = 0;

  @override
  void render(Canvas canvas) {
    // --- 第 1 层：天空渐变（静态）---
    final Rect full = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(
      full,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[GamePalette.skyTop, GamePalette.skyBottom],
        ).createShader(full),
    );

    // --- 第 2 层：远景剪影（慢速滚动）---
    if (!_ready) {
      return;
    }

    final double tileW = SpriteFactory.skylineTileWidth.toDouble();
    final double tileH = SpriteFactory.skylineTileHeight.toDouble();
    final double imgW = _skylineImage.width.toDouble();
    final double imgH = _skylineImage.height.toDouble();
    final Rect srcFull = Rect.fromLTWH(0, 0, imgW, imgH);
    final Paint paint = Paint()..filterQuality = FilterQuality.low;

    // 剪影底部对齐全屏底部，让树林「站」在地面线上被地面遮挡。
    final double baseY = size.y - tileH;

    double x = -_scrollOffset;
    while (x < size.x) {
      canvas.drawImageRect(
        _skylineImage,
        srcFull,
        Rect.fromLTWH(x, baseY, tileW, tileH),
        paint,
      );
      x += tileW;
    }
  }
}
