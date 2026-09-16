import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/game_screen.dart';
import 'services/audio_service.dart';
import 'services/score_storage.dart';

/// 应用入口。
///
/// ## 启动顺序（不可调换）
///
/// 1. `WidgetsFlutterBinding.ensureInitialized()` —— 之后才能使用插件
///    （`path_provider`、`shared_preferences`）。
/// 2. `ScoreStorage.load()` —— 读取存档。音频服务依赖它判断音效开关，
///    因此必须先行。
/// 3. `AudioService.initialize()` —— 解析音源（打包资源或运行时合成）。
/// 4. `Flame.images` 预热 —— 让首帧不必等待贴图生成。
///
/// 这些步骤都有磁盘 IO，因此用 [FutureBuilder] 展示加载状态，
/// 避免启动瞬间的白屏或卡顿。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 锁定竖屏。本游戏所有布局常量都基于 9:16 竖屏设计。
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  // 全屏沉浸：隐藏状态栏与导航栏，让游戏画面铺满。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const PixelBirdApp());
}

/// 应用根组件。负责执行异步初始化并切换到游戏页面。
class PixelBirdApp extends StatelessWidget {
  const PixelBirdApp({super.key});

  /// 执行全部启动初始化，返回初始化好的服务集合。
  Future<_BootstrapResult> _bootstrap() async {
    // 步骤 1：存档（后续步骤依赖它）
    final ScoreStorage storage = await ScoreStorage.load();

    // 步骤 2：音频
    final AudioService audio = await AudioService.initialize();

    // 步骤 3：清空 Flame 图片缓存，确保程序化生成的贴图从干净状态开始。
    Flame.images.clearCache();

    return _BootstrapResult(audio: audio, scores: storage);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Bird',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        // 关闭页面切换动画，避免游戏页面出现多余的过渡效果。
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: NoTransitionsBuilder(),
            TargetPlatform.iOS: NoTransitionsBuilder(),
          },
        ),
      ),
      home: FutureBuilder<_BootstrapResult>(
        future: _bootstrap(),
        builder: (BuildContext context, AsyncSnapshot<_BootstrapResult> snapshot) {
          if (snapshot.hasError) {
            return _BootstrapErrorScreen(error: '${snapshot.error}');
          }
          final _BootstrapResult? result = snapshot.data;
          if (result == null) {
            return const _LoadingScreen();
          }
          return GameScreen(audio: result.audio, scores: result.scores);
        },
      ),
    );
  }
}

/// 启动加载页。
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF4EC0CA),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(height: 16),
            Text(
              '正在准备…',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 启动失败页。把错误暴露出来而不是静默黑屏，便于排查。
class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4EC0CA),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, color: Colors.white, size: 46),
              const SizedBox(height: 14),
              const Text(
                '启动失败',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 无过渡动画的页面切换。
class NoTransitionsBuilder extends PageTransitionsBuilder {
  const NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

/// 启动初始化的产出集合。
///
/// 用一个类承载多个已就绪的服务，避免 FutureBuilder 泛型出现元组类型。
class _BootstrapResult {
  const _BootstrapResult({required this.audio, required this.scores});

  final AudioService audio;
  final ScoreStorage scores;
}
