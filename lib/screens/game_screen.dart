import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../game/config/game_palette.dart';
import '../game/game_state.dart';
import '../game/game_world.dart';
import '../services/audio_service.dart';
import '../services/score_storage.dart';
import '../widgets/game_over_panel.dart';
import '../widgets/score_display.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/start_hint.dart';

/// 主游戏页面。
///
/// ## 架构：Flame 画布 + Flutter UI 叠加
///
/// 采用**关注点分离**的双层结构：
///
/// - **游戏层**（[GameWorld]，Flame 组件）：只负责玩法——物理、碰撞、渲染
///   游戏内元素（小鸟、管道、地面、背景）。它使用固定分辨率视口，
///   坐标系统一为 [GameConfig.designSize]，与屏幕尺寸解耦。
///
/// - **UI 层**（本 Widget，Flutter）：负责所有文字、按钮、面板。用
///   `Stack` 叠加在 `GameWidget` 之上。Flutter 的文字渲染与无障碍支持
///   远强于游戏引擎，且能直接使用 Material 组件。
///
/// 两层通过回调通信（`onScoreChanged` / `onRunFinished` / `onStateChanged`），
/// 单向数据流，[GameWorld] 不感知 UI 的存在。
///
/// ## 为什么用固定分辨率视口
///
/// 若游戏元素按屏幕实际尺寸布局，不同宽高比的手机上管道间距/缝隙的
/// **相对手感**会完全不同——iPad 上管道会显得极宽，导致难度骤降。
/// 固定视口 + 等比缩放保证所有设备上的游戏体验一致，多余区域留黑边。
class GameScreen extends StatefulWidget {
  const GameScreen({required this.audio, required this.scores, super.key});

  final AudioPlayerService audio;

  /// 分数存档仓库。由 main() 注入。
  final ScoreRepository scores;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameWorld _game;

  // ---- 由游戏层回调驱动的 UI 状态 ----
  int _score = 0;
  GameState _state = GameState.ready;
  RunResult? _lastResult;

  /// 难度提示的显示倒计时（秒）。
  double _noticeRemaining = 0;
  int _noticeLevel = 1;

  /// 难度提示的定时器。用 Timer 而非依赖游戏循环，避免与固定步长耦合。
  void Function()? _noticeTicker;

  @override
  void initState() {
    super.initState();

    final ScoreStorage storage = ScoreStorage.instance;

    _game = GameWorld(
      audio: widget.audio,
      scores: widget.scores,
      onScoreChanged: _handleScoreChanged,
      onRunFinished: _handleRunFinished,
      onStateChanged: _handleStateChanged,
    )..setBestScore(storage.bestScore);

    // 游戏过程中保持屏幕常亮，否则玩家读秒时屏幕会自动息屏。
    _enableWakelock();
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // 部分平台/测试环境不支持，忽略即可，不影响玩法。
    }
  }

  @override
  void dispose() {
    // 释放屏幕常亮，避免影响用户在应用外的正常使用。
    WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 游戏层回调
  // ---------------------------------------------------------------------------

  void _handleScoreChanged(int score) {
    if (!mounted) {
      return;
    }
    // 跨过 10 的整数倍时弹出难度提示。
    final int previousMilestone = _score ~/ 10;
    final int currentMilestone = score ~/ 10;

    setState(() => _score = score);

    if (currentMilestone > previousMilestone) {
      _showDifficultyNotice();
    }
  }

  void _handleStateChanged(GameState state) {
    if (!mounted) {
      return;
    }
    setState(() {
      _state = state;
      // 离开结算状态时清空上一局结果，避免残留面板闪现。
      if (state != GameState.gameOver) {
        _lastResult = null;
      }
    });
  }

  void _handleRunFinished(RunResult result) {
    if (!mounted) {
      return;
    }
    setState(() => _lastResult = result);
  }

  /// 短暂显示「难度提升」提示，1.4 秒后自动消失。
  void _showDifficultyNotice() {
    _noticeTicker?.call(); // 取消上一个尚未结束的定时器

    final int level = (_score ~/ 10) + 1;
    bool cancelled = false;

    setState(() {
      _noticeLevel = level;
      _noticeRemaining = 1.4;
    });

    _noticeTicker = () {
      cancelled = true;
    };

    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || cancelled) {
        return;
      }
      setState(() => _noticeRemaining = 0);
    });
  }

  // ---------------------------------------------------------------------------
  // 交互
  // ---------------------------------------------------------------------------

  void _handleTap() {
    // 仅在 ready / playing 时把点击转发给游戏层。
    // dying / gameOver 状态下点击不应触发起飞（结算面板需要独立按钮）。
    if (_state == GameState.gameOver) {
      return;
    }
    _game.handleTap();
  }

  void _handleRestart() {
    _game.restart();
    setState(() {
      _score = 0;
      _lastResult = null;
    });
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => SettingsDialog(
          audio: widget.audio,
          scores: widget.scores,
        ),
    );
    // 设置中可能清空了存档，回来后刷新最高分显示。
    if (!mounted) {
      return;
    }
    _game.setBestScore(ScoreStorage.instance.bestScore);
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool showStartHint = _state == GameState.ready;
    final bool showHud = _state != GameState.ready;
    final RunResult? result = _lastResult;

    return Scaffold(
      backgroundColor: Colors.black, // 视口留边处的底色
      body: GestureDetector(
        // behavior 设为 opaque 让整个区域（含透明部分）都能接收点击。
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // ================= 第 1 层：游戏画布 =================
            GameWidget<GameWorld>(game: _game),

            // ================= 第 2 层：顶部 HUD =================
            SafeArea(
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 8),

                  // ---- 分数 ----
                  if (showHud)
                    OutlinedScoreText(score: _score, fontSize: 58)
                  else
                    const SizedBox(height: 58),

                  const SizedBox(height: 8),

                  // ---- 难度提升提示 ----
                  AnimatedOpacity(
                    opacity: _noticeRemaining > 0 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: _noticeRemaining > 0
                        ? DifficultyNotice(level: _noticeLevel)
                        : const SizedBox(height: 34),
                  ),

                  const Spacer(),

                  // ---- 待机提示 ----
                  AnimatedOpacity(
                    opacity: showStartHint ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: showStartHint
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 28),
                            child: TapToStartHint(
                              bestScore: ScoreStorage.instance.bestScore,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // ================= 第 3 层：右上角设置入口 =================
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
                  child: _CircleIconButton(
                    icon: Icons.settings_rounded,
                    onPressed: _openSettings,
                  ),
                ),
              ),
            ),

            // ================= 第 4 层：结算面板 =================
            if (result != null)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: GameOverPanel(
                  result: result,
                  onRestart: _handleRestart,
                  onOpenSettings: _openSettings,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 圆形图标按钮。用于设置入口等低干扰的次级操作。
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.82),
      shape: const CircleBorder(
        side: BorderSide(color: GamePalette.panelOutline, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: GamePalette.textPrimary),
        ),
      ),
    );
  }
}
