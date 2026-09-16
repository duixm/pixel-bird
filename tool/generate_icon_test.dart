import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 应用图标生成器。
///
/// ## 为什么写成测试
///
/// 图标绘制依赖 `dart:ui` 的 `Canvas` / `Picture.toImage()`，这些 API
/// 只在 Flutter 引擎环境中可用——纯 `dart run` 无法解析 `dart:ui`。
/// 而 `flutter test` 会启动一个 headless Flutter 引擎，因此把生成逻辑
/// 放进测试是最省依赖的做法（无需引入 `image` 包，也无需单独的原生入口）。
///
/// ## 用法
///
/// ```bash
/// flutter test tool/generate_icon_test.dart
/// ```
///
/// 产出：
/// - `assets/images/app_icon.png`（1024x1024，iOS 与传统 Android 图标）
/// - `assets/images/app_icon_foreground.png`（Android 自适应图标前景层）
///
/// 之后运行 `dart run flutter_launcher_icons` 写入各平台工程。
///
/// ## 换成真实图标
///
/// 直接用同名 PNG 覆盖 `assets/images/` 下的文件即可。本脚本会跳过
/// 已存在的文件，不会覆盖你的美术资源。
void main() {
  test('生成应用图标', () async {
    final Directory outDir = Directory('assets/images');
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    final File mainIcon = File('${outDir.path}/app_icon.png');
    final File fgIcon = File('${outDir.path}/app_icon_foreground.png');

    if (!mainIcon.existsSync()) {
      await _writePng(mainIcon, await _renderMainIcon());
      // ignore: avoid_print
      print('已生成 ${mainIcon.path}');
    } else {
      // ignore: avoid_print
      print('跳过已存在的 ${mainIcon.path}');
    }

    if (!fgIcon.existsSync()) {
      await _writePng(fgIcon, await _renderForegroundIcon());
      // ignore: avoid_print
      print('已生成 ${fgIcon.path}');
    } else {
      // ignore: avoid_print
      print('跳过已存在的 ${fgIcon.path}');
    }

    expect(mainIcon.existsSync(), isTrue);
    expect(fgIcon.existsSync(), isTrue);
  });
}

/// 图标边长（像素）。
const int _iconSize = 1024;

/// 渲染主图标：青蓝渐变背景 + 居中金色小鸟 + 两侧管道剪影。
Future<ui.Image> _renderMainIcon() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  // 注意：不能用 const（toDouble() 是方法调用，无法在常量上下文中求值）。
  final double s = _iconSize.toDouble();

  // ---- 背景：与游戏天空同色的渐变 ----
  final Rect full = Rect.fromLTWH(0, 0, s, s);
  canvas.drawRect(
    full,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFF4EC0CA), Color(0xFF3A9FA9)],
      ).createShader(full),
  );

  // ---- 装饰云朵 ----
  final Paint cloud = Paint()..color = const Color(0x33FFFFFF);
  canvas.drawCircle(Offset(s * 0.20, s * 0.22), s * 0.075, cloud);
  canvas.drawCircle(Offset(s * 0.30, s * 0.20), s * 0.095, cloud);
  canvas.drawCircle(Offset(s * 0.78, s * 0.76), s * 0.065, cloud);
  canvas.drawCircle(Offset(s * 0.86, s * 0.74), s * 0.082, cloud);

  // ---- 主体小鸟 ----
  _drawBigBird(canvas, center: Offset(s / 2, s / 2), width: s * 0.46);

  // ---- 底部管道剪影，强化「游戏」语义 ----
  final Paint pipe = Paint()..color = const Color(0xE674BF2E);
  final Paint pipeCap = Paint()..color = const Color(0xE64F8A1C);

  // 左下
  canvas.drawRect(Rect.fromLTWH(s * 0.06, s * 0.72, s * 0.10, s * 0.28), pipe);
  canvas.drawRect(Rect.fromLTWH(s * 0.045, s * 0.69, s * 0.13, s * 0.055), pipeCap);
  // 右下
  canvas.drawRect(Rect.fromLTWH(s * 0.84, s * 0.72, s * 0.10, s * 0.28), pipe);
  canvas.drawRect(Rect.fromLTWH(s * 0.825, s * 0.69, s * 0.13, s * 0.055), pipeCap);

  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(_iconSize, _iconSize);
  picture.dispose();
  return image;
}

/// 渲染 Android 自适应图标前景层。
///
/// 自适应图标会被系统裁成各种形状（圆/方/水滴）并可能缩放，
/// 因此内容必须落在中心约 66% 的安全区内。这里缩到 58% 以确保安全。
Future<ui.Image> _renderForegroundIcon() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final double s = _iconSize.toDouble();

  // 前景层不含背景（背景由 adaptive_icon_background 提供）。
  _drawBigBird(canvas, center: Offset(s / 2, s / 2), width: s * 0.29);

  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(_iconSize, _iconSize);
  picture.dispose();
  return image;
}

/// 绘制放大版小鸟。[width] 为小鸟整体宽度（高度按 0.72 比例推导）。
void _drawBigBird(
  Canvas canvas, {
  required Offset center,
  required double width,
}) {
  final double w = width;
  final double h = width * 0.72;
  final Offset c = center;

  // 身体
  final Rect body =
      Rect.fromCenter(center: c, width: w * 0.80, height: h * 0.92);
  canvas.drawOval(body, Paint()..color = const Color(0xFFF7D51D));

  // 腹部高光
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(c.dx - w * 0.04, c.dy + h * 0.20),
      width: w * 0.52,
      height: h * 0.38,
    ),
    Paint()..color = const Color(0xFFFDF0A8),
  );

  // 身体描边
  canvas.drawOval(
    body,
    Paint()
      ..color = const Color(0xFF8A6D0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.030,
  );

  // 翅膀
  final Rect wing = Rect.fromCenter(
    center: Offset(c.dx - w * 0.10, c.dy + h * 0.06),
    width: w * 0.40,
    height: h * 0.34,
  );
  canvas.drawOval(wing, Paint()..color = const Color(0xFFF0F0F0));
  canvas.drawOval(
    wing,
    Paint()
      ..color = const Color(0xFFBFBFBF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.020,
  );

  // 喙
  final Path beak = Path()
    ..moveTo(c.dx + w * 0.30, c.dy - h * 0.12)
    ..lineTo(c.dx + w * 0.54, c.dy + h * 0.08)
    ..lineTo(c.dx + w * 0.30, c.dy + h * 0.22)
    ..close();
  canvas.drawPath(beak, Paint()..color = const Color(0xFFF08020));
  canvas.drawPath(
    beak,
    Paint()
      ..color = const Color(0xFFD9631A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.020,
  );

  // 眼睛
  final Offset eye = Offset(c.dx + w * 0.11, c.dy - h * 0.20);
  canvas.drawCircle(eye, w * 0.105, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawCircle(
    eye,
    w * 0.105,
    Paint()
      ..color = const Color(0xFF8A6D0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.018,
  );
  canvas.drawCircle(
    Offset(eye.dx + w * 0.030, eye.dy),
    w * 0.050,
    Paint()..color = const Color(0xFF2B2B2B),
  );
}

/// 把 [ui.Image] 编码为 PNG 并写入文件。
Future<void> _writePng(File file, ui.Image image) async {
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  if (data == null) {
    throw StateError('PNG 编码失败：${file.path}');
  }
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
}
