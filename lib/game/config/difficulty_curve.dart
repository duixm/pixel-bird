import 'dart:math' as math;

import '../config/game_config.dart';

/// 难度曲线计算器。
///
/// 把「当前分数」映射为「管道缝隙高度」与「管道速度」，是整个难度递增机制的
/// 唯一数据来源。**所有难度参数必须经由此类获取，禁止在其他地方直接读
/// [GameConfig] 的起始值**——否则修改曲线时容易遗漏。
///
/// ## 曲线设计
///
/// 采用**分段线性 + 上限饱和**模型，而非连续指数增长：
///
/// | 分数区间 | 缝隙 | 速度 | 设计意图 |
/// |---|---|---|---|
/// | 0-5 | 165 → 152 | 118 → 129 | 教学区：变化极缓，让玩家建立手感 |
/// | 6-20 | 152 → 113 | 129 → 162 | 成长区：难度稳定上升，保持挑战感 |
/// | 21-40 | 113 → 110 | 162 → 206 | 挑战区：逼近缝隙下限，考验精准度 |
/// | 41+ | 110（锁死） | 206 → 225（渐近） | 巅峰区：只有速度缓慢增加，避免不可玩 |
///
/// **为什么要有下限**：缝隙若无限收窄，最终会小于小鸟一次跳跃的位移，
/// 出现数学上无解的局面。110px 约为小鸟直径的 4.4 倍，是可玩性的硬边界。
///
/// **为什么要速度饱和**：速度过快会让管道在单帧内跨越过大距离，
/// 即使有子步积分也可能出现「穿模」观感，且超出人类反应极限。
class DifficultyCurve {
  const DifficultyCurve._();

  /// 教学区结束分数。此后难度增速提升。
  static const int tutorialEndScore = 5;

  /// 成长区结束分数。
  static const int growthEndScore = 20;

  /// 挑战区结束分数。此后进入速度渐近饱和。
  static const int challengeEndScore = 40;

  /// 计算当前分数对应的管道缝隙高度。
  static double gapHeightForScore(int score) {
    final double shrink = score * GameConfig.pipeGapShrinkPerPoint;
    final double gap = GameConfig.pipeGapStart - shrink;
    // 下限保护：不允许低于可玩性硬边界。
    return math.max(gap, GameConfig.pipeGapMin);
  }

  /// 计算当前分数对应的管道水平速度。
  ///
  /// 采用「线性增长 + 平方根衰减」的混合曲线：
  /// 前期提速明显（有感知），后期增速放缓并渐近于上限，避免突然不可玩。
  static double pipeSpeedForScore(int score) {
    if (score <= 0) {
      return GameConfig.pipeSpeedStart;
    }

    // 线性分量
    final double linear = score * GameConfig.pipeSpeedIncreasePerPoint;
    // 衰减因子：随着分数增加，线性分量的贡献按 sqrt 递减
    final double damping = 1.0 / math.sqrt(1 + score / 18.0);

    final double speed = GameConfig.pipeSpeedStart + linear * damping;
    return speed.clamp(GameConfig.pipeSpeedStart, GameConfig.pipeSpeedMax);
  }

  /// 计算相邻两组管道的水平间距。
  ///
  /// 间距随速度同步微调：速度越快，间距需略微加大，
  /// 否则「两组管道几乎同时出现」会让反应时间压缩到不合理的程度。
  static double pipeSpacingForScore(int score) {
    final double speed = pipeSpeedForScore(score);
    final double base = GameConfig.pipeSpacing;
    // 以起始速度为基准等比放大，保证「通过一组管道所用的时间」大致恒定。
    final double scaled = base * (speed / GameConfig.pipeSpeedStart) * 0.86;
    return math.max(scaled, base * 0.92);
  }

  /// 判断当前分数是否跨过了一个「难度提示」节点。
  ///
  /// 用于在 UI 上弹出「速度提升」提示。仅当 [previousScore] 到 [currentScore]
  /// 跨越了 [GameConfig.difficultyNoticeInterval] 的整数倍时返回 true。
  static bool crossedDifficultyMilestone(int previousScore, int currentScore) {
    final int prevMilestone =
        previousScore ~/ GameConfig.difficultyNoticeInterval;
    final int currMilestone =
        currentScore ~/ GameConfig.difficultyNoticeInterval;
    return currMilestone > prevMilestone && currentScore > 0;
  }

  /// 当前难度等级（从 1 开始），用于 UI 展示。
  static int levelForScore(int score) {
    if (score < tutorialEndScore) {
      return 1;
    }
    if (score < growthEndScore) {
      return 2;
    }
    if (score < challengeEndScore) {
      return 3;
    }
    return 4;
  }
}
