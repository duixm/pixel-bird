import 'dart:async';
import 'dart:math' as math;

// Vector2 / FlameGame 由 game.dart 导出；
// FixedResolutionViewport 位于 camera.dart（game.dart 不转发它）。
import 'package:flame/camera.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

// game_world.dart 位于 lib/game/，因此：
// - 回到 lib/ 用 '../'
// - 同级子目录用 'config/' 'components/'
import '../services/audio_service.dart';
import '../services/score_storage.dart';
import 'components/background_component.dart';
import 'components/bird_component.dart';
import 'components/ground_component.dart';
import 'components/pipe_pair.dart';
import 'config/difficulty_curve.dart';
import 'config/game_config.dart';
import 'game_state.dart';

/// 一次游玩结束后的结果快照，用于驱动结算 UI。
class RunResult {
  const RunResult({
    required this.score,
    required this.isNewBest,
    required this.bestScore,
  });

  /// 本局得分。
  final int score;

  /// 是否刷新了历史最高分。
  final bool isNewBest;

  /// 更新后的历史最高分。
  final int bestScore;
}

/// 游戏世界：整个玩法的核心编排者。
///
/// ## 职责划分
///
/// 本类**只做编排**，具体逻辑下放到各组件：
/// - 物理积分 → [BirdComponent.stepPhysics]
/// - 碰撞几何 → [PipePair.topRect] / [GroundComponent.groundRect]
/// - 难度数值 → [DifficultyCurve]
///
/// 这样划分的好处是核心循环可读性高，且每个组件都能被单独测试。
///
/// ## 固定步长积分
///
/// Flame 的 `update(dt)` 使用可变 dt（取决于设备帧率）。若直接用它积分物理，
/// 60Hz 与 120Hz 设备上的跳跃高度会不一致。因此本类累积真实时间，
/// 以 [GameConfig.fixedTimeStep] 为固定步长推进物理，余数留到下一帧——
/// 这是游戏开发中「固定时间步长」模式的标准实现（参考 Glenn Fiedler 的
/// 《Fix Your Timestep!》）。
///
/// 好处：
/// - 不同刷新率设备手感完全一致
/// - 高速下坠时不会穿透管道（每步位移有上限）
/// - 物理可复现，便于录制回放与自动化测试
class GameWorld extends FlameGame {
  /// 创建游戏世界。
  ///
  /// [seed] 可注入固定随机种子以复现同一组管道布局，便于自动化测试与调试。
  /// 缺省时使用时间种子。
  GameWorld({
    required this.audio,
    required this.scores,
    required this.onRunFinished,
    required this.onScoreChanged,
    required this.onStateChanged,
    int? seed,
  }) : _random = math.Random(seed);

  /// 音频服务（由外部注入）。
  ///
  /// 类型为 [AudioPlayerService] 接口而非具体实现，便于测试注入替身。
  final AudioPlayerService audio;

  /// 分数存档仓库（由外部注入）。
  final ScoreRepository scores;

  /// 一局结束时的回调。参数为本局结果。
  final void Function(RunResult result) onRunFinished;

  /// 分数变化回调，用于驱动 HUD 更新。
  final void Function(int score) onScoreChanged;

  /// 状态变化回调，用于驱动 UI 层（如隐藏/显示提示文字）。
  final void Function(GameState state) onStateChanged;

  // ---- 组件引用 ----
  late final BirdComponent _bird;
  late final BackgroundComponent _background;
  late final GroundComponent _ground;

  /// 当前在场的管道。用列表维护，回收时移除。
  final List<PipePair> _pipes = <PipePair>[];

  // ---- 运行时状态 ----
  GameState _state = GameState.ready;
  int _score = 0;
  int _bestScore = 0;

  /// 距离下一组管道生成还需移动的水平距离。
  double _distanceToNextPipe = 0;

  /// 上一组管道的缝隙中心 Y（用于限制相邻管道的高低跳变）。
  double _lastGapCenterY = 0;

  /// 固定步长累积器。
  double _accumulator = 0;

  /// 死亡后进入结算面板的倒计时。
  double _gameOverDelay = 0;

  /// 输入冷却计时器，防止死亡连点被误判为重开。
  double _inputCooldown = 0;

  /// 起飞缓冲剩余时间（秒）。
  ///
  /// 大于 0 时小鸟悬停不受重力，管道正常滚动。详见
  /// [GameConfig.launchGracePeriod]。玩家在此期间点击会立即结束缓冲。
  double _launchGrace = 0;

  /// 随机数发生器。注入种子以便测试时复现。
  final math.Random _random;

  // ---------------------------------------------------------------------------
  // 公开状态访问
  // ---------------------------------------------------------------------------

  GameState get state => _state;
  int get score => _score;
  int get bestScore => _bestScore;
  bool get isPlaying => _state == GameState.playing;

  /// 小鸟当前的竖直速度。UI 层可能用于表现（如速度线）。
  double get birdVelocityY => _bird.velocityY;

  /// 世界尺寸。以设计基准为准，实际缩放由相机处理。
  Vector2 get worldSize =>
      Vector2(GameConfig.designSize.width, GameConfig.designSize.height);

  @override
  Color backgroundColor() => const Color(0xFF4EC0CA);

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  @override
  Future<void> onLoad() async {
    // 固定分辨率视口：无论屏幕实际尺寸如何，游戏世界始终按
    // GameConfig.designSize（360x640）呈现，视口自动等比缩放并居中。
    //
    // 这样做的意义：所有布局常量（管道间距、缝隙、重力）都以设计基准
    // 推导，因此在不同宽高比的手机上「相对手感」完全一致。
    // 代价是非 9:16 屏幕两侧会出现留边（由 backgroundColor 填充）。
    camera.viewport = FixedResolutionViewport(resolution: worldSize);

    _background = BackgroundComponent();
    _ground = GroundComponent();
    _bird = BirdComponent(
      position: Vector2(
        GameConfig.birdStartX,
        _readyBirdY,
      ),
    );

    // 添加顺序决定渲染层级（后添加的在上层）。
    await add(_background);
    await add(_ground);
    await add(_bird);

    _lastGapCenterY = _readyBirdY;
    _resetWorld();
    _setState(GameState.ready);
  }

  /// 待机时小鸟所处的竖直位置：屏幕垂直中点偏下。
  double get _readyBirdY => GameConfig.designSize.height * 0.45;

  /// 地面顶部 Y 坐标。
  double get _groundTopY =>
      GameConfig.designSize.height - GameConfig.groundHeight;

  // ---------------------------------------------------------------------------
  // 输入
  // ---------------------------------------------------------------------------

  /// 处理屏幕点击。由上层 UI 的 GestureDetector 调用。
  void handleTap() {
    // 输入冷却：死亡后短时间内忽略点击，避免「误重开」。
    if (_inputCooldown > 0) {
      return;
    }

    switch (_state) {
      case GameState.ready:
        // 首次点击：从待机进入游戏。此时小鸟进入缓冲悬停阶段
        // （不立即施加冲量），让玩家有一段准备时间。
        _beginRun();
        audio.play(Sfx.flap);

      case GameState.playing:
        // 缓冲期内点击：立即结束悬停并起飞，手感上「点了就动」。
        if (_launchGrace > 0) {
          _launchGrace = 0;
        }
        _bird.flap();
        audio.play(Sfx.flap);

      case GameState.dying:
        // 死亡坠落中不响应输入。玩家需等待落地后主动重开。
        break;

      case GameState.gameOver:
        // 结算面板由 UI 层处理重开按钮；点击屏幕本身不重开，
        // 避免玩家想看分数时手一抖就重开了。
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 状态流转
  // ---------------------------------------------------------------------------

  void _beginRun() {
    _resetWorld();
    // 进入游戏但先进入缓冲悬停，不立即施加冲量。
    _launchGrace = GameConfig.launchGracePeriod;
    _setState(GameState.playing);
  }

  /// 把世界重置到新一局的初始状态。
  void _resetWorld() {
    _score = 0;
    _accumulator = 0;
    _gameOverDelay = 0;
    _launchGrace = 0;
    // 首组管道用较小的 lead-in 距离，确保在小鸟可能坠地之前就已进入视野。
    // 后续管道则使用完整的 pipeSpacing。
    _distanceToNextPipe = GameConfig.firstPipeLeadIn;

    // 回收所有在场管道。
    for (final PipePair pipe in _pipes) {
      pipe.removeFromParent();
    }
    _pipes.clear();

    _bird.reset(Vector2(GameConfig.birdStartX, _readyBirdY));
    _ground.reset();
    _background.reset();
    _lastGapCenterY = _readyBirdY;

    onScoreChanged(_score);
  }

  void _setState(GameState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    onStateChanged(next);
  }

  /// 撞到障碍物。记录分数并进入死亡坠落阶段。
  void _die() {
    if (_state == GameState.dying || _state == GameState.gameOver) {
      return;
    }

    audio.play(Sfx.hit);
    _bird.startFalling();
    _setState(GameState.dying);
    _gameOverDelay = 0.75; // 约 0.75 秒的坠落演出后弹出结算

    // 进入死亡状态后设置输入冷却，防止连点误触。
    _inputCooldown = GameConfig.inputCooldown;
  }

  /// 落地后结束本局。
  Future<void> _finishRun() async {
    _setState(GameState.gameOver);
    audio.play(Sfx.die);

    // 持久化：先提交分数（内部判断是否刷新纪录），再累加局数。
    // 通过注入的仓库操作，因此测试可替换为内存实现。
    final bool isNewBest = await scores.submitScore(_score);
    final int bestAfter = scores.bestScore;
    _bestScore = bestAfter;
    await scores.incrementGamesPlayed();

    onRunFinished(
      RunResult(
        score: _score,
        isNewBest: isNewBest,
        bestScore: bestAfter,
      ),
    );
  }

  /// 外部设置当前最高分（启动时从存档读取）。
  void setBestScore(int value) {
    _bestScore = value;
  }

  /// 供 UI 层请求重开。
  void restart() {
    _inputCooldown = 0;
    _resetWorld();
    _setState(GameState.ready);
  }

  /// 强制恢复到待机状态（如从后台返回时）。
  void goToReady() {
    _inputCooldown = 0;
    _resetWorld();
    _setState(GameState.ready);
  }

  // ---------------------------------------------------------------------------
  // 主循环
  // ---------------------------------------------------------------------------

  @override
  void update(double dt) {
    // 限制单帧时间上限：应用从后台切回前台时 dt 可能极大，
    // 不限幅会导致小鸟瞬移穿过管道。
    final double clampedDt = math.min(dt, GameConfig.maxFrameTime);

    if (_inputCooldown > 0) {
      _inputCooldown -= clampedDt;
      if (_inputCooldown < 0) {
        _inputCooldown = 0;
      }
    }

    // 死亡坠落的兜底计时：正常情况下小鸟落地会触发 _finishRun，
    // 但若因极端情况（如卡在管道缝隙内不落）长时间未结束，
    // 这里强制收束本局，避免游戏卡死在不响应输入的状态。
    if (_state == GameState.dying) {
      _gameOverDelay -= clampedDt;
      if (_gameOverDelay <= 0) {
        _finishRun();
      }
    }

    // 固定步长积分：把真实时间累积起来，按固定步长逐步推进物理。
    _accumulator += clampedDt;
    int steps = 0;
    // 设置步数上限，避免极端卡顿时单帧推进过多步造成「时间跳跃」。
    const int maxStepsPerFrame = 24;
    while (_accumulator >= GameConfig.fixedTimeStep && steps < maxStepsPerFrame) {
      _stepFixed(GameConfig.fixedTimeStep);
      _accumulator -= GameConfig.fixedTimeStep;
      steps++;
    }
    // 累积过多时丢弃余量，防止陷入「追帧」死循环。
    if (_accumulator > GameConfig.fixedTimeStep * maxStepsPerFrame) {
      _accumulator = 0;
    }

    super.update(dt);
  }

  /// 推进一个固定物理步。
  ///
  /// 所有与时间相关的状态变化都必须在**此处**发生，而不是在 [update] 里，
  /// 否则「物理步数」与「时间变化」会不一致，导致不同帧率下行为分歧。
  void _stepFixed(double step) {
    switch (_state) {
      case GameState.ready:
        _bird.stepIdle(step: step, baseY: _readyBirdY);
        _bird.stepAnimation(step: step, isIdle: true);
        // 待机时地面与背景也在滚动，营造「世界在运转」的氛围。
        _ground.stepScroll(
          step: step,
          speed: GameConfig.groundScrollSpeed,
        );
        _background.stepScroll(
          step: step,
          speed: GameConfig.backgroundScrollSpeed,
        );

      case GameState.playing:
        _stepPlaying(step);

      case GameState.dying:
        // 死亡坠落：仅小鸟受重力下落，世界静止（撞击后的「定格」感）。
        _bird.stepPhysics(step: step);
        _bird.stepAnimation(step: step, isIdle: false);
        _checkGroundCollisionOnly();

      case GameState.gameOver:
        // 世界完全静止，仅保留小鸟动画表现。
        _bird.stepAnimation(step: step, isIdle: false);
    }
  }

  /// 游戏进行中的单步逻辑。
  void _stepPlaying(double step) {
    // ---- 0. 起飞缓冲 ----
    // 缓冲期内小鸟悬停（不受重力、不下落），但世界照常滚动，
    // 让玩家看清障碍并自行决定何时起飞。
    if (_launchGrace > 0) {
      _launchGrace -= step;
      _bird.stepIdle(step: step, baseY: _readyBirdY);
      _bird.stepAnimation(step: step, isIdle: true);
      _stepWorldScrolling(step);
      return;
    }

    // ---- 1. 小鸟物理 ----
    _bird.stepPhysics(step: step);
    _bird.stepAnimation(step: step, isIdle: false);

    // ---- 2. 世界滚动（含难度参数）----
    _stepWorldScrolling(step);

    // ---- 3. 碰撞检测与计分 ----
    _checkCollisions();

    // ---- 4. 天花板限制 ----
    // 允许飞得略高于画面顶部，但不能无限飞出——否则看不清小鸟。
    final double minY = GameConfig.birdHitboxRadius;
    if (_bird.position.y < minY) {
      _bird.position.y = minY;
      // 撞顶后速度归零，产生「贴住天花板」的手感。
      if (_bird.velocityY < 0) {
        _bird.velocityY = 0;
      }
    }
  }

  /// 推进世界滚动：地面、背景、管道移动与生成。
  ///
  /// 抽成独立方法是因为它在「缓冲期」与「正常游玩」两种情况下都要执行，
  /// 而两者的小鸟物理处理不同。
  void _stepWorldScrolling(double step) {
    // 难度参数（本帧唯一取值点）
    final double pipeSpeed = DifficultyCurve.pipeSpeedForScore(_score);
    final double gapHeight = DifficultyCurve.gapHeightForScore(_score);

    // 世界滚动
    _ground.stepScroll(step: step, speed: pipeSpeed);
    _background.stepScroll(
      step: step,
      speed: GameConfig.backgroundScrollSpeed *
          (pipeSpeed / GameConfig.pipeSpeedStart),
    );

    // 管道移动与回收
    for (final PipePair pipe in _pipes) {
      pipe.stepMovement(step: step, speed: pipeSpeed);
    }
    _pipes.removeWhere((PipePair pipe) {
      // 移出屏幕后回收，防止列表无限增长。
      if (pipe.isOffScreen) {
        pipe.removeFromParent();
        return true;
      }
      return false;
    });

    // 生成新管道
    _distanceToNextPipe -= pipeSpeed * step;
    if (_distanceToNextPipe <= 0) {
      _spawnPipe(gapHeight: gapHeight);
      _distanceToNextPipe = DifficultyCurve.pipeSpacingForScore(_score);
    }
  }

  /// 生成一组新管道。
  void _spawnPipe({required double gapHeight}) {
    final double centerY = _pickGapCenter();

    final PipePair pipe = PipePair(
      leftX: GameConfig.designSize.width + 8, // 从右边界外一点进入，避免突然弹出
      gapCenterY: centerY,
      gapHeight: gapHeight,
    );
    _pipes.add(pipe);
    // 不等待：组件挂载是即时的，onLoad 内的贴图加载会异步完成。
    // 这里显式忽略返回的 Future 以表明「有意不等待」。
    unawaited(Future<void>.sync(() => add(pipe)));

    _lastGapCenterY = centerY;
  }

  /// 选择一个合法的缝隙中心 Y 坐标。
  ///
  /// 两条约束：
  /// 1. 缝隙完整落在屏幕内的安全区间（不贴天花板/地面）。
  /// 2. 与上一组管道的中心高度差不超过 [GameConfig.gapCenterMaxDeltaRatio]，
  ///    避免出现需要瞬间大幅爬升的「不可能通过」组合。
  double _pickGapCenter() {
    final double screenH = GameConfig.designSize.height;
    final double minCenter = screenH * GameConfig.gapCenterMinRatio;
    final double maxCenter = screenH * GameConfig.gapCenterMaxRatio;

    // 由上一组中心位置推导本组的允许范围。
    final double maxDelta = screenH * GameConfig.gapCenterMaxDeltaRatio;
    final double lowerBound = math.max(minCenter, _lastGapCenterY - maxDelta);
    final double upperBound = math.min(maxCenter, _lastGapCenterY + maxDelta);

    // 边界异常保护（理论上不会发生，因为 minCenter < maxCenter）。
    if (upperBound <= lowerBound) {
      return (minCenter + maxCenter) / 2;
    }

    return lowerBound + _random.nextDouble() * (upperBound - lowerBound);
  }

  /// 检测小鸟与管道/地面的碰撞，并处理计分。
  void _checkCollisions() {
    final Offset birdCenter = Offset(_bird.position.x, _bird.position.y);
    final double radius = _bird.collisionRadius;

    // --- 与管道碰撞 ---
    for (final PipePair pipe in _pipes) {
      // 圆与轴对齐矩形的相交检测：把圆心投影到矩形上求最近点，
      // 再比较距离与半径。这是最简洁的圆-矩形碰撞算法。
      if (_circleIntersectsRect(birdCenter, radius, pipe.topRect) ||
          _circleIntersectsRect(birdCenter, radius, pipe.bottomRect)) {
        _die();
        return;
      }

      // --- 计分 ---
      // 判定线为小鸟中心 X。管道右边缘越过该线时得 1 分。
      if (!pipe.scored && pipe.rightEdge < _bird.position.x) {
        pipe.scored = true;
        _onScored();
      }
    }

    // --- 与地面碰撞 ---
    if (birdCenter.dy + radius >= _groundTopY) {
      // 触地：先把小鸟对齐到地面，避免视觉上陷进地面。
      _bird.position.y = _groundTopY - radius;
      _die();
    }
  }

  /// 死亡坠落阶段只需检测是否落地。
  void _checkGroundCollisionOnly() {
    final double radius = _bird.collisionRadius;
    if (_bird.position.y + radius >= _groundTopY) {
      _bird.position.y = _groundTopY - radius;
      // 落地意味着本轮演出结束。
      if (_state == GameState.dying) {
        _finishRun();
      }
    }
  }

  /// 圆与轴对齐矩形是否相交。
  static bool _circleIntersectsRect(Offset center, double radius, Rect rect) {
    // 求矩形上距离圆心最近的点
    final double closestX = center.dx.clamp(rect.left, rect.right);
    final double closestY = center.dy.clamp(rect.top, rect.bottom);
    final double dx = center.dx - closestX;
    final double dy = center.dy - closestY;
    // 比较平方距离，避免开方
    return dx * dx + dy * dy <= radius * radius;
  }

  /// 处理一次得分。
  void _onScored() {
    final int previous = _score;
    _score++;
    audio.play(Sfx.score);
    onScoreChanged(_score);

    if (DifficultyCurve.crossedDifficultyMilestone(previous, _score)) {
      audio.play(Sfx.swoosh);
    }
  }
}
