import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../game/config/game_palette.dart';

/// 程序化生成的精灵图缓存。
///
/// ## 为什么用代码画图而不是 PNG
///
/// 本项目的目标是「克隆下来就能跑」。若引用外部 PNG，仓库要么体积膨胀，
/// 要么依赖用户自行下载素材（素材版权也不明确）。因此所有视觉元素先用
/// `Canvas` 矢量绘制成 [ui.Image] 并缓存，做到**零外部图片依赖**。
///
/// ## 如何替换成美术素材
///
/// 每个 getter 内部都先尝试 [Flame.images.load] 读取 `assets/images/*.png`，
/// 加载失败才回退到程序化绘制。因此接入真实素材只需把同名 PNG 放进
/// `assets/images/` 即可，**无需改动任何游戏代码**。
///
/// 命名对应关系见 README 的「资源说明」章节。
class SpriteFactory {
  SpriteFactory._();

  static final Map<String, ui.Image> _cache = <String, ui.Image>{};

  /// 清空缓存。主要用于测试或热重载后需要重新生成贴图的场景。
  static void clearCache() => _cache.clear();

  /// 若存在同名资源文件则优先使用，否则调用 [draw] 程序化生成。
  ///
  /// [draw] 为同步绘制回调：所有绘制都是纯 Canvas 操作，无需异步。
  static Future<ui.Image> _resolve(
    String assetName,
    void Function(Canvas canvas) draw,
    int width,
    int height,
  ) async {
    final ui.Image? cached = _cache[assetName];
    if (cached != null) {
      return cached;
    }

    ui.Image? image = await _tryLoadAsset(assetName);
    if (image == null) {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      draw(canvas);
      final ui.Picture picture = recorder.endRecording();
      image = await picture.toImage(width, height);
      picture.dispose();
    }

    _cache[assetName] = image;
    return image;
  }

  /// 尝试从包资源加载图片；文件缺失时返回 null 而不抛异常。
  static Future<ui.Image?> _tryLoadAsset(String assetName) async {
    try {
      // Flame 内部对 resources 有缓存，重复调用开销很低。
      return await Flame.images.load(assetName);
    } on Exception {
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // 小鸟
  // ---------------------------------------------------------------------------

  /// 小鸟精灵图尺寸（像素）。宽高比约 1.4:1，符合原版体态。
  static const int birdSpriteWidth = 48;
  static const int birdSpriteHeight = 34;

  /// 小鸟「翅膀向上」帧。
  static Future<ui.Image> birdWingsUp() => _resolve(
        'bird_wings_up.png',
        (Canvas c) => _drawBird(c, wingAngle: -0.50),
        birdSpriteWidth,
        birdSpriteHeight,
      );

  /// 小鸟「翅膀水平」帧（滑翔姿势）。
  static Future<ui.Image> birdWingsMid() => _resolve(
        'bird_wings_mid.png',
        (Canvas c) => _drawBird(c, wingAngle: 0.0),
        birdSpriteWidth,
        birdSpriteHeight,
      );

  /// 小鸟「翅膀向下」帧。
  static Future<ui.Image> birdWingsDown() => _resolve(
        'bird_wings_down.png',
        (Canvas c) => _drawBird(c, wingAngle: 0.55),
        birdSpriteWidth,
        birdSpriteHeight,
      );

  /// 绘制单帧小鸟。[wingAngle] 为翅膀绕肩部的旋转弧度。
  static void _drawBird(Canvas canvas, {required double wingAngle}) {
    final double w = birdSpriteWidth.toDouble();
    final double h = birdSpriteHeight.toDouble();
    final Offset center = Offset(w / 2, h / 2);

    // --- 身体：椭圆 ---
    final Rect bodyRect = Rect.fromCenter(
      center: center,
      width: w * 0.76,
      height: h * 0.78,
    );
    canvas.drawOval(
      bodyRect,
      Paint()..color = GamePalette.birdBody,
    );

    // --- 腹部浅色渐变（下方受光较弱处用亮色表现体积感）---
    final Rect bellyRect = Rect.fromCenter(
      center: Offset(center.dx - w * 0.04, center.dy + h * 0.16),
      width: w * 0.50,
      height: h * 0.34,
    );
    canvas.drawOval(
      bellyRect,
      Paint()..color = GamePalette.birdBelly,
    );

    // --- 身体描边 ---
    canvas.drawOval(
      bodyRect,
      Paint()
        ..color = GamePalette.birdOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // --- 翅膀：以肩部为轴旋转 ---
    canvas.save();
    final Offset shoulder = Offset(center.dx - w * 0.10, center.dy + h * 0.02);
    canvas.translate(shoulder.dx, shoulder.dy);
    canvas.rotate(wingAngle);
    final Rect wingRect = Rect.fromCenter(
      center: Offset(-w * 0.06, h * 0.10),
      width: w * 0.38,
      height: h * 0.30,
    );
    canvas.drawOval(wingRect, Paint()..color = GamePalette.birdWing);
    canvas.drawOval(
      wingRect,
      Paint()
        ..color = GamePalette.birdWingOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.restore();

    // --- 喙：朝右的圆角三角 ---
    final Path beak = Path()
      ..moveTo(w * 0.74, center.dy - h * 0.10)
      ..lineTo(w * 1.00, center.dy + h * 0.06)
      ..lineTo(w * 0.74, center.dy + h * 0.18)
      ..close();
    canvas.drawPath(beak, Paint()..color = GamePalette.birdBeak);
    canvas.drawPath(
      beak,
      Paint()
        ..color = GamePalette.birdBeakDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // --- 眼睛：眼白 + 瞳孔 ---
    final Offset eyeCenter = Offset(center.dx + w * 0.16, center.dy - h * 0.14);
    canvas.drawCircle(
      eyeCenter,
      w * 0.115,
      Paint()..color = GamePalette.birdEye,
    );
    canvas.drawCircle(
      eyeCenter,
      w * 0.115,
      Paint()
        ..color = GamePalette.birdOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawCircle(
      Offset(eyeCenter.dx + w * 0.032, eyeCenter.dy),
      w * 0.055,
      Paint()..color = GamePalette.birdPupil,
    );
  }

  // ---------------------------------------------------------------------------
  // 管道
  // ---------------------------------------------------------------------------

  /// 管道管身纹理。沿竖直方向重复平铺以填充任意长度的管道。
  /// 尺寸取 [pipeBodyWidth] x 32，纵向可无缝衔接。
  static const int pipeBodyWidth = 64;
  static const int pipeBodyHeight = 32;

  static Future<ui.Image> pipeBody() => _resolve(
        'pipe_body.png',
        _drawPipeBody,
        pipeBodyWidth,
        pipeBodyHeight,
      );

  static void _drawPipeBody(Canvas canvas) {
    final double w = pipeBodyWidth.toDouble();
    final double h = pipeBodyHeight.toDouble();
    final Rect rect = Rect.fromLTWH(0, 0, w, h);

    // 主体
    canvas.drawRect(rect, Paint()..color = GamePalette.pipeBody);
    // 左侧高光带（约 26% 宽度）
    canvas.drawRect(
      Rect.fromLTWH(w * 0.12, 0, w * 0.26, h),
      Paint()..color = GamePalette.pipeHighlight,
    );
    // 右侧阴影带
    canvas.drawRect(
      Rect.fromLTWH(w * 0.78, 0, w * 0.14, h),
      Paint()..color = GamePalette.pipeShadow,
    );
    // 左右描边
    final Paint outline = Paint()
      ..color = GamePalette.pipeOutline
      ..strokeWidth = 2.0;
    canvas.drawLine(const Offset(1, 0), Offset(1, h), outline);
    canvas.drawLine(Offset(w - 1, 0), Offset(w - 1, h), outline);
  }

  /// 管道管口（比管身更宽的边缘段）。
  static const int pipeCapWidth = 76;
  static const int pipeCapHeight = 26;

  static Future<ui.Image> pipeCap() => _resolve(
        'pipe_cap.png',
        _drawPipeCap,
        pipeCapWidth,
        pipeCapHeight,
      );

  static void _drawPipeCap(Canvas canvas) {
    final double w = pipeCapWidth.toDouble();
    final double h = pipeCapHeight.toDouble();
    final Rect rect = Rect.fromLTWH(0, 0, w, h);

    canvas.drawRect(rect, Paint()..color = GamePalette.pipeCap);
    canvas.drawRect(
      Rect.fromLTWH(w * 0.10, h * 0.15, w * 0.24, h * 0.70),
      Paint()..color = GamePalette.pipeCapHighlight,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.80, h * 0.15, w * 0.12, h * 0.70),
      Paint()..color = GamePalette.pipeShadow,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = GamePalette.pipeOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  // ---------------------------------------------------------------------------
  // 地面
  // ---------------------------------------------------------------------------

  /// 地面贴图。横向可无缝平铺，纵向包含草地顶带与土壤纹理。
  static const int groundTileWidth = 32;
  static const int groundTileHeight = 96;

  static Future<ui.Image> groundTile() => _resolve(
        'ground_tile.png',
        _drawGroundTile,
        groundTileWidth,
        groundTileHeight,
      );

  static void _drawGroundTile(Canvas canvas) {
    final double w = groundTileWidth.toDouble();
    final double h = groundTileHeight.toDouble();

    // 土壤主体渐变
    final Rect soil = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      soil,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[GamePalette.groundTop, GamePalette.groundBottom],
        ).createShader(soil),
    );

    // 顶部草带（8px）
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, 8),
      Paint()..color = GamePalette.groundStripe,
    );
    // 草带下方的深色分界线
    canvas.drawRect(
      Rect.fromLTWH(0, 8, w, 3),
      Paint()..color = GamePalette.groundBottom,
    );

    // 斜向土壤纹理：让滚动时有明确的移动参照物
    final Paint texture = Paint()
      ..color = GamePalette.groundStripe.withValues(alpha: 0.45)
      ..strokeWidth = 2.0;
    for (double x = -h; x < w + h; x += 16) {
      canvas.drawLine(Offset(x, h), Offset(x + 24, 8), texture);
    }
  }

  // ---------------------------------------------------------------------------
  // 背景远景（云与树剪影）
  // ---------------------------------------------------------------------------

  /// 远景装饰条。横向平铺，配合视差滚动使用。
  static const int skylineTileWidth = 240;
  static const int skylineTileHeight = 140;

  static Future<ui.Image> skylineTile() => _resolve(
        'skyline_tile.png',
        _drawSkylineTile,
        skylineTileWidth,
        skylineTileHeight,
      );

  static void _drawSkylineTile(Canvas canvas) {
    final double w = skylineTileWidth.toDouble();
    final double h = skylineTileHeight.toDouble();
    // 剪影的基线即贴图底边。用 final 而非 const（h 是运行时值）。
    final double baseline = h;

    final Paint silhouette = Paint()..color = GamePalette.skyline;

    // 树冠：若干重叠圆形组成的小树丛
    void drawTree(double cx, double crownRadius, double trunkHeight) {
      canvas.drawRect(
        Rect.fromLTWH(cx - 3, baseline - trunkHeight, 6, trunkHeight),
        silhouette,
      );
      canvas.drawCircle(
        Offset(cx, baseline - trunkHeight - crownRadius * 0.5),
        crownRadius,
        silhouette,
      );
      canvas.drawCircle(
        Offset(cx - crownRadius * 0.7, baseline - trunkHeight - crownRadius * 0.2),
        crownRadius * 0.72,
        silhouette,
      );
      canvas.drawCircle(
        Offset(cx + crownRadius * 0.7, baseline - trunkHeight - crownRadius * 0.2),
        crownRadius * 0.72,
        silhouette,
      );
    }

    // 云朵
    void drawCloud(double cx, double cy, double scale) {
      final Paint cloudPaint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55);
      canvas.drawCircle(Offset(cx, cy), 14 * scale, cloudPaint);
      canvas.drawCircle(Offset(cx + 16 * scale, cy + 2 * scale), 18 * scale, cloudPaint);
      canvas.drawCircle(Offset(cx + 36 * scale, cy), 13 * scale, cloudPaint);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + 18 * scale, cy + 10 * scale),
          width: 54 * scale,
          height: 20 * scale,
        ),
        cloudPaint,
      );
    }

    drawCloud(w * 0.18, h * 0.22, 0.85);
    drawCloud(w * 0.70, h * 0.14, 0.62);

    // 底部树林剪影
    drawTree(w * 0.08, 17, 22);
    drawTree(w * 0.30, 23, 30);
    drawTree(w * 0.55, 14, 18);
    drawTree(w * 0.78, 20, 26);
    drawTree(w * 0.96, 16, 21);

    // 底部实心带，避免树根部悬空
    canvas.drawRect(
      Rect.fromLTWH(0, baseline - 8, w, 8),
      silhouette,
    );
  }
}
