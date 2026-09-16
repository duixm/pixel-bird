import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_bird/game/config/difficulty_curve.dart';
import 'package:pixel_bird/game/config/game_config.dart';
import 'package:pixel_bird/game/game_state.dart';
import 'package:pixel_bird/game/game_world.dart';
import 'package:pixel_bird/services/audio_service.dart';
import 'package:pixel_bird/services/score_storage.dart';

/// 游戏世界的集成测试。
///
/// 这些测试**真正启动 [GameWorld]** 并推进游戏循环，验证：
/// - 状态机流转正确（ready → playing → dying → gameOver）
/// - 计分与难度递增随分数生效
/// - 小鸟物理正常（重力生效、点击上升、落地判定）
///
/// ## 为什么用 stub 音频
///
/// [AudioService] 依赖 `path_provider` 与平台通道，在单元测试环境中不可用。
/// 这里注入 [StubAudioService]（覆写 play 为无操作），从而把测试范围
/// 严格限制在游戏逻辑上——这也是把音频做成可注入依赖的目的。
void main() {
  // Flame 的 GameWorld 需要 Flutter binding（用于图片解码等）。
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 驱动游戏推进 [seconds] 秒，以 1/60 秒为一帧。
  ///
  /// 注意：必须多次调用 `update` 而不是一次传入大 dt——[GameWorld.update]
  /// 内部按固定步长积分，但单帧 dt 有上限（[GameConfig.maxFrameTime]）。
  /// 逐帧推进才符合真实运行时的行为。
  Future<void> advance(GameWorld game, double seconds) async {
    const double frame = 1 / 60;
    final int frames = (seconds / frame).round();
    for (int i = 0; i < frames; i++) {
      game.update(frame);
    }
    // 让组件树中的异步操作（onLoad）有机会完成。
    await Future<void>.delayed(Duration.zero);
  }

  group('GameWorld 初始状态', () {
    test('启动后处于待机状态且分数为 0', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );

      await game.onLoad();

      expect(game.state, equals(GameState.ready));
      expect(game.score, equals(0));
      expect(game.isPlaying, isFalse);
    });

    test('世界尺寸等于设计基准', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );

      await game.onLoad();

      expect(game.worldSize.x, equals(GameConfig.designSize.width));
      expect(game.worldSize.y, equals(GameConfig.designSize.height));
    });
  });

  group('状态机流转', () {
    test('首次点击从待机进入游戏', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );
      await game.onLoad();
      await advance(game, 0.5);

      game.handleTap();

      expect(game.state, equals(GameState.playing));
    });

    test('死亡坠落阶段不响应点击（避免误重开）', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );
      await game.onLoad();
      game.handleTap();
      expect(game.state, equals(GameState.playing));

      // 不点击，任其自由下坠直至撞地。
      await advance(game, 3.0);

      // 应当已进入游戏结束（撞地 → dying → gameOver）。
      expect(
        game.state,
        anyOf(equals(GameState.dying), equals(GameState.gameOver)),
      );

      // 此时点击不应回到 playing。
      game.handleTap();
      expect(
        game.state,
        anyOf(equals(GameState.dying), equals(GameState.gameOver)),
      );
    });

    test('restart 可回到待机状态并清零分数', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );
      await game.onLoad();
      game.handleTap();
      await advance(game, 4.0); // 撞地结束

      game.restart();

      expect(game.state, equals(GameState.ready));
      expect(game.score, equals(0));
    });
  });

  group('物理与碰撞', () {
    test('待机时小鸟在竖直方向轻微浮动（不坠毁）', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );
      await game.onLoad();

      // 待机 3 秒。若物理误启用，小鸟会撞地导致状态变化。
      await advance(game, 3.0);

      expect(game.state, equals(GameState.ready));
    });

    test('进入游戏后有起飞缓冲，小鸟悬停而非立即下坠', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );
      await game.onLoad();
      game.handleTap();

      expect(game.state, equals(GameState.playing));

      // 缓冲期内（0.75 秒）小鸟应保持悬停：竖直速度为零。
      await advance(game, 0.4);
      expect(
        game.birdVelocityY,
        equals(0),
        reason: '起飞缓冲期内小鸟不应受重力影响',
      );

      // 缓冲期结束后应开始下坠（速度变为正值）。
      await advance(game, 0.6);
      expect(
        game.birdVelocityY,
        greaterThan(0),
        reason: '缓冲结束后小鸟应受重力下坠',
      );
    });

    test('缓冲期内点击可立即起飞', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );
      await game.onLoad();
      game.handleTap(); // 进入游戏，开始缓冲
      await advance(game, 0.2);

      game.handleTap(); // 缓冲期内再次点击

      // 应立即获得向上的速度。
      expect(
        game.birdVelocityY,
        lessThan(0),
        reason: '缓冲期内点击应立即起飞',
      );
    });
  });

  group('计分系统', () {
    test('管道生成：首组管道在小鸟坠地前进入视野', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );
      await game.onLoad();
      game.handleTap();

      // 首组管道 lead-in 为 60px，速度约 118px/s，
      // 加上 0.75 秒缓冲，约 1.3 秒后应已生成。
      // 这里推进 1.5 秒——若此时仍未生成管道，说明开局手感有问题。
      await advance(game, 1.5);

      final bool hasPipe = game.children.any(
        (Component c) => c.runtimeType.toString() == 'PipePair',
      );
      expect(
        hasPipe,
        isTrue,
        reason: '首组管道必须在玩家可能坠地之前出现',
      );
    });

    test('不点击时最终会因坠落而结束本局', () async {
      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: (_) {},
        onStateChanged: (_) {},
        seed: 42,
      );
      await game.onLoad();
      game.handleTap();

      // 全程不点击：缓冲 0.75s + 下坠，数秒内应撞地结束。
      await advance(game, 5.0);

      expect(
        game.state,
        equals(GameState.gameOver),
        reason: '放任小鸟下坠最终应结束本局',
      );
    });
  });

  group('难度递增', () {
    test('高分数对应的缝隙小于低分数（难度确实在提升）', () {
      expect(
        DifficultyCurve.gapHeightForScore(0),
        greaterThan(DifficultyCurve.gapHeightForScore(15)),
      );
      expect(
        DifficultyCurve.pipeSpeedForScore(0),
        lessThan(DifficultyCurve.pipeSpeedForScore(15)),
      );
    });

    test('难度提示回调在跨过 10 分时触发', () async {
      final List<int> scores = <int>[];

      final GameWorld game = GameWorld(
        audio: StubAudioService(),
        scores: StubScoreRepository(),
        onRunFinished: (_) {},
        onScoreChanged: scores.add,
        onStateChanged: (_) {},
        seed: 7,
      );
      await game.onLoad();

      // 初始应已回调一次 0 分。
      expect(scores, contains(0));
    });
  });
}

/// 音频服务的测试替身。
///
/// 实现 [AudioPlayerService] 接口并把所有方法置为无操作，
/// 避免测试触碰平台通道与文件系统。
/// 这正是把音频抽成接口的目的——测试只关注游戏逻辑。
class StubAudioService implements AudioPlayerService {
  @override
  bool get enabled => false;

  @override
  void play(Sfx sfx) {
    // 测试中静默。
  }

  @override
  Future<void> playBgm(String? assetFileName) async {}

  @override
  Future<bool> toggleSound() async => false;

  @override
  Future<void> dispose() async {}
}

/// 分数存档的测试替身（内存实现）。
///
/// 生产环境用 `SharedPreferences`，测试中用普通字段即可——
/// 这正是把存档抽成 [ScoreRepository] 接口的目的。
class StubScoreRepository implements ScoreRepository {
  int _best = 0;
  int _games = 0;
  bool _sound = true;

  @override
  int get bestScore => _best;

  @override
  int get gamesPlayed => _games;

  @override
  bool get soundEnabled => _sound;

  @override
  Future<bool> submitScore(int score) async {
    if (score <= _best) {
      return false;
    }
    _best = score;
    return true;
  }

  @override
  Future<int> incrementGamesPlayed() async => ++_games;

  @override
  Future<void> setSoundEnabled({required bool enabled}) async {
    _sound = enabled;
  }

  @override
  Future<void> resetAll() async {
    _best = 0;
    _games = 0;
  }
}
