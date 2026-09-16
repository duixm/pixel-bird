import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../assets/sprite_factory.dart';
import '../config/game_config.dart';

/// 一对管道（上管 + 下管 + 中间缝隙）。
///
/// ## 设计要点
///
/// 1. **配对成组**：上下两根管道必然同生同灭，因此作为一个组件管理，
///    避免两个独立组件间需要同步生命周期。
///
/// 2. **纹理平铺而非拉伸**：管道贴图（[SpriteFactory.pipeBody]）沿竖直方向
///    重复平铺。若直接拉伸，管道越长管身纹理越扁，视觉上会变形。
///
/// 3. **宽度与碰撞分离**：`size` 表示整组管道的包围盒（仅用于 Flame 组件树），
///    真正的碰撞矩形由 [topRect] / [bottomRect] 提供，只覆盖管身与管口。
///
/// ## 坐标系
///
/// 组件的 [position] 为左上角，[position].x 表示管道左边缘的 X 坐标。
/// 缝隙中心 Y 坐标由 [gapCenterY] 给出，据此推导上下管道的高度。
class PipePair extends PositionComponent {
  PipePair({
    required double leftX,
    required this.gapCenterY,
    required this.gapHeight,
  }) : super(
          position: Vector2(leftX, 0),
          size: Vector2(GameConfig.pipeWidth, GameConfig.designSize.height),
          anchor: Anchor.topLeft,
        );

  /// 缝隙中心点的 Y 坐标（逻辑像素）。
  double gapCenterY;

  /// 缝隙高度（逻辑像素）。随难度递增而收窄。
  double gapHeight;

  /// 是否已为本组管道计过分。
  ///
  /// 计分时机为「管道右边缘越过小鸟的 X 坐标」，只触发一次，
  /// 因此需要标志位防止重复计分。
  bool scored = false;

  /// 管身贴图。由 [onLoad] 异步加载。
  late ui.Image _bodyImage;

  /// 管口贴图。
  late ui.Image _capImage;

  bool _ready = false;

  // ---------------------------------------------------------------------------
  // 几何推导
  // ---------------------------------------------------------------------------

  /// 缝隙上边缘的 Y 坐标。
  double get gapTop => gapCenterY - gapHeight / 2;

  /// 缝隙下边缘的 Y 坐标。
  double get gapBottom => gapCenterY + gapHeight / 2;

  /// 地面顶部 Y 坐标。下管延伸到此处为止。
  double get _groundTopY => GameConfig.designSize.height - GameConfig.groundHeight;

  /// 上管碰撞矩形。仅覆盖管身（含管口），用于精确碰撞判定。
  Rect get topRect => Rect.fromLTWH(
        position.x,
        0,
        GameConfig.pipeWidth,
        gapTop,
      );

  /// 下管碰撞矩形。
  Rect get bottomRect => Rect.fromLTWH(
        position.x,
        gapBottom,
        GameConfig.pipeWidth,
        _groundTopY - gapBottom,
      );

  /// 管道右边缘的 X 坐标。用于判断是否已飞出屏幕及计分线。
  double get rightEdge => position.x + GameConfig.pipeWidth;

  /// 是否已完全移出屏幕左侧（可安全回收）。
  bool get isOffScreen => rightEdge < 0;

  // ---------------------------------------------------------------------------
  // 生命周期
  // ---------------------------------------------------------------------------

  @override
  Future<void> onLoad() async {
    _bodyImage = await SpriteFactory.pipeBody();
    _capImage = await SpriteFactory.pipeCap();
    _ready = true;
  }

  /// 以固定步长水平左移。
  void stepMovement({required double step, required double speed}) {
    position.x -= speed * step;
  }

  // ---------------------------------------------------------------------------
  // 渲染
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    if (!_ready) {
      return;
    }

    // --- 上管 ---
    // 管身占据 [capHeight, gapTop] 区间，管口贴在 gapTop 处（朝下）。
    // 注意：管口比管身宽，需水平居中并向两侧各外扩 (capWidth - pipeWidth)/2。
    final double capWidth = GameConfig.pipeWidth *
        (SpriteFactory.pipeCapWidth / SpriteFactory.pipeBodyWidth);
    final double capHeight = SpriteFactory.pipeCapHeight.toDouble();
    final double capOverhang = (capWidth - GameConfig.pipeWidth) / 2;

    if (gapTop > capHeight) {
      // 管身：从顶部到管口上方
      _drawTiledBody(
        canvas: canvas,
        top: 0,
        bottom: gapTop - capHeight,
      );
      // 管口：贴在缝隙上边缘
      _drawCap(
        canvas: canvas,
        left: -capOverhang,
        top: gapTop - capHeight,
        width: capWidth,
        height: capHeight,
      );
    } else if (gapTop > 0) {
      // 缝隙过高导致上管极短：仅画管口，避免出现负高度。
      _drawCap(
        canvas: canvas,
        left: -capOverhang,
        top: 0,
        width: capWidth,
        height: capHeight,
      );
    }

    // --- 下管 ---
    final double bottomCapTop = gapBottom;
    final double bottomPipeBottom = _groundTopY;
    if (bottomPipeBottom - bottomCapTop > capHeight) {
      _drawCap(
        canvas: canvas,
        left: -capOverhang,
        top: bottomCapTop,
        width: capWidth,
        height: capHeight,
      );
      _drawTiledBody(
        canvas: canvas,
        top: bottomCapTop + capHeight,
        bottom: bottomPipeBottom,
      );
    } else if (bottomPipeBottom > bottomCapTop) {
      _drawCap(
        canvas: canvas,
        left: -capOverhang,
        top: bottomCapTop,
        width: capWidth,
        height: capHeight,
      );
    }
  }

  /// 沿竖直方向平铺管身贴图，填充 [top, bottom] 区间。
  ///
  /// 平铺而非拉伸：把贴图按原始高度反复绘制，最后一段允许裁切，
  /// 这样无论管道多长，管身纹理尺寸都保持一致。
  void _drawTiledBody({
    required Canvas canvas,
    required double top,
    required double bottom,
  }) {
    final double height = bottom - top;
    if (height <= 0) {
      return;
    }

    final double bodyW = GameConfig.pipeWidth;
    final double tileH = SpriteFactory.pipeBodyHeight.toDouble();
    final double imgW = _bodyImage.width.toDouble();
    final double imgH = _bodyImage.height.toDouble();
    final Rect srcFull = Rect.fromLTWH(0, 0, imgW, imgH);
    final Paint paint = Paint()..filterQuality = FilterQuality.medium;

    double y = top;
    while (y < bottom) {
      final double remaining = bottom - y;
      final double drawH = remaining < tileH ? remaining : tileH;

      // 绘制非满高度的最后一段时，需按比例裁切源图，保持纹理不压缩。
      final Rect src = drawH < tileH
          ? Rect.fromLTWH(0, 0, imgW, imgH * (drawH / tileH))
          : srcFull;

      canvas.drawImageRect(
        _bodyImage,
        src,
        Rect.fromLTWH(position.x, y, bodyW, drawH),
        paint,
      );
      y += tileH;
    }
  }

  /// 绘制管口（比管身宽的边缘段）。
  void _drawCap({
    required Canvas canvas,
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    canvas.drawImageRect(
      _capImage,
      Rect.fromLTWH(
        0,
        0,
        _capImage.width.toDouble(),
        _capImage.height.toDouble(),
      ),
      Rect.fromLTWH(position.x + left, top, width, height),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  /// 调试：绘制两个碰撞矩形。
  @override
  void renderDebugMode(Canvas canvas) {
    super.renderDebugMode(canvas);
    final Paint paint = Paint()
      ..color = const Color(0xFFFF5252).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 矩形坐标是世界坐标，需减去组件自身位置转换为局部坐标。
    canvas.drawRect(
      topRect.shift(Offset(-position.x, -position.y)),
      paint,
    );
    canvas.drawRect(
      bottomRect.shift(Offset(-position.x, -position.y)),
      paint,
    );
  }
}
