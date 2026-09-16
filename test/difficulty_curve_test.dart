import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_bird/game/config/difficulty_curve.dart';
import 'package:pixel_bird/game/config/game_config.dart';

/// 难度曲线的单元测试。
///
/// 难度曲线是整个游戏可玩性的核心，必须有测试守住不变量——
/// 否则一次调参失误就可能让高分段变成「数学上无解」。
void main() {
  group('缝隙高度', () {
    test('初始分数返回起始缝隙', () {
      expect(
        DifficultyCurve.gapHeightForScore(0),
        equals(GameConfig.pipeGapStart),
      );
    });

    test('随分数单调递减', () {
      double previous = DifficultyCurve.gapHeightForScore(0);
      for (int score = 1; score <= 60; score++) {
        final double current = DifficultyCurve.gapHeightForScore(score);
        expect(
          current,
          lessThanOrEqualTo(previous),
          reason: '分数 $score 的缝隙不应大于上一分',
        );
        previous = current;
      }
    });

    test('永不低于可玩性下限（关键不变量）', () {
      // 即使分数极高，缝隙也不能小于配置的硬边界，
      // 否则会出现任何操作都无法通过的管道。
      for (int score = 0; score <= 500; score += 7) {
        expect(
          DifficultyCurve.gapHeightForScore(score),
          greaterThanOrEqualTo(GameConfig.pipeGapMin),
          reason: '分数 $score 的缝隙击穿了下限',
        );
      }
    });

    test('高分段收敛到下限而非继续收窄', () {
      final double at300 = DifficultyCurve.gapHeightForScore(300);
      final double at999 = DifficultyCurve.gapHeightForScore(999);
      expect(at300, equals(GameConfig.pipeGapMin));
      expect(at999, equals(GameConfig.pipeGapMin));
    });
  });

  group('管道速度', () {
    test('初始分数返回起始速度', () {
      expect(
        DifficultyCurve.pipeSpeedForScore(0),
        equals(GameConfig.pipeSpeedStart),
      );
    });

    test('随分数单调不减', () {
      double previous = DifficultyCurve.pipeSpeedForScore(0);
      for (int score = 1; score <= 200; score++) {
        final double current = DifficultyCurve.pipeSpeedForScore(score);
        expect(
          current,
          greaterThanOrEqualTo(previous - 1e-9),
          reason: '分数 $score 的速度不应下降',
        );
        previous = current;
      }
    });

    test('永不超过速度上限（关键不变量）', () {
      for (int score = 0; score <= 500; score++) {
        expect(
          DifficultyCurve.pipeSpeedForScore(score),
          lessThanOrEqualTo(GameConfig.pipeSpeedMax + 1e-9),
          reason: '分数 $score 的速度越过了上限',
        );
      }
    });

    test('速度确实比起点快（难度真的在提升）', () {
      expect(
        DifficultyCurve.pipeSpeedForScore(20),
        greaterThan(GameConfig.pipeSpeedStart),
      );
    });
  });

  group('管道间距', () {
    test('始终为正且不低于基准的合理比例', () {
      for (int score = 0; score <= 200; score += 3) {
        final double spacing = DifficultyCurve.pipeSpacingForScore(score);
        expect(spacing, greaterThan(0));
        expect(
          spacing,
          greaterThanOrEqualTo(GameConfig.pipeSpacing * 0.92 - 1e-9),
          reason: '分数 $score 的间距过小，反应时间不足',
        );
      }
    });
  });

  group('难度里程碑', () {
    test('仅在跨过 10 的整数倍时返回 true', () {
      expect(
        DifficultyCurve.crossedDifficultyMilestone(9, 10),
        isTrue,
      );
      expect(
        DifficultyCurve.crossedDifficultyMilestone(10, 11),
        isFalse,
      );
      expect(
        DifficultyCurve.crossedDifficultyMilestone(19, 20),
        isTrue,
      );
      expect(
        DifficultyCurve.crossedDifficultyMilestone(5, 6),
        isFalse,
      );
    });

    test('0 分不触发里程碑（开局不应提示难度提升）', () {
      expect(
        DifficultyCurve.crossedDifficultyMilestone(0, 0),
        isFalse,
      );
    });

    test('一次跨越多级也能正确识别（如调试跳分）', () {
      expect(
        DifficultyCurve.crossedDifficultyMilestone(5, 35),
        isTrue,
      );
    });
  });

  group('难度等级', () {
    test('等级随分数递增且覆盖全部四档', () {
      expect(DifficultyCurve.levelForScore(0), equals(1));
      expect(
        DifficultyCurve.levelForScore(DifficultyCurve.tutorialEndScore),
        equals(2),
      );
      expect(
        DifficultyCurve.levelForScore(DifficultyCurve.growthEndScore),
        equals(3),
      );
      expect(
        DifficultyCurve.levelForScore(DifficultyCurve.challengeEndScore),
        equals(4),
      );
      expect(DifficultyCurve.levelForScore(9999), equals(4));
    });
  });
}
