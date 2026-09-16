import 'package:shared_preferences/shared_preferences.dart';

/// 分数存档能力的抽象接口。
///
/// 与 [AudioPlayerService] 同理：抽出接口是为了让 [GameWorld] 不直接依赖
/// `SharedPreferences` 单例，从而能在单元测试中注入内存实现。
abstract interface class ScoreRepository {
  /// 历史最高分。
  int get bestScore;

  /// 累计游玩局数。
  int get gamesPlayed;

  /// 音效开关状态。
  bool get soundEnabled;

  /// 若 [score] 超过历史最高分则更新，返回是否刷新了纪录。
  Future<bool> submitScore(int score);

  /// 累加一局游玩记录，返回累加后的总局数。
  Future<int> incrementGamesPlayed();

  /// 更新音效开关。
  Future<void> setSoundEnabled({required bool enabled});

  /// 清空全部存档。
  Future<void> resetAll();
}

/// 本地持久化服务（生产实现）。
///
/// 只保存三类数据：历史最高分、游玩局数、音效开关。刻意不引入数据库——
/// `SharedPreferences` 对键值型轻量数据足够，且零原生额外配置。
///
/// 使用方式：应用启动时调用一次 [load]，之后通过 [instance] 访问。
/// 写入操作是「即发即忘」的内存更新 + 异步落盘，不会阻塞游戏循环。
class ScoreStorage implements ScoreRepository {
  ScoreStorage._();

  static ScoreStorage? _instance;

  /// 已加载的单例。未调用 [load] 前访问会抛异常，以便尽早暴露初始化顺序错误。
  static ScoreStorage get instance {
    final ScoreStorage? value = _instance;
    if (value == null) {
      throw StateError(
        'ScoreStorage 尚未初始化，请在 main() 中先 await ScoreStorage.load()。',
      );
    }
    return value;
  }

  /// 首次安装时的默认最高分。
  static const int defaultBestScore = 0;

  // 存储键名。加前缀便于日后排查设备上的残留数据。
  static const String _keyBestScore = 'pixel_bird.best_score';
  static const String _keySoundEnabled = 'pixel_bird.sound_enabled';
  static const String _keyGamesPlayed = 'pixel_bird.games_played';

  late final SharedPreferences _prefs;

  /// 读取磁盘数据并构造单例。
  static Future<ScoreStorage> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ScoreStorage storage = ScoreStorage._().._prefs = prefs;
    _instance = storage;
    return storage;
  }

  /// 历史最高分。
  @override
  int get bestScore => _prefs.getInt(_keyBestScore) ?? defaultBestScore;

  /// 累计游玩局数。用于在合适时机（如第 3 局结束后）展示评分引导。
  @override
  int get gamesPlayed => _prefs.getInt(_keyGamesPlayed) ?? 0;

  /// 音效开关状态。默认开启。
  @override
  bool get soundEnabled => _prefs.getBool(_keySoundEnabled) ?? true;

  /// 若 [score] 超过历史最高分则更新，并返回是否刷新了纪录。
  ///
  /// 返回值用于驱动「新纪录」UI 提示与音效。
  @override
  Future<bool> submitScore(int score) async {
    if (score <= bestScore) {
      return false;
    }
    await _prefs.setInt(_keyBestScore, score);
    return true;
  }

  /// 累加一局游玩记录。返回累加后的总局数。
  @override
  Future<int> incrementGamesPlayed() async {
    final int next = gamesPlayed + 1;
    await _prefs.setInt(_keyGamesPlayed, next);
    return next;
  }

  /// 更新音效开关。
  @override
  Future<void> setSoundEnabled({required bool enabled}) async {
    await _prefs.setBool(_keySoundEnabled, enabled);
  }

  /// 清空全部存档。仅用于「重置进度」这类明确的用户操作。
  @override
  Future<void> resetAll() async {
    await _prefs.remove(_keyBestScore);
    await _prefs.remove(_keyGamesPlayed);
  }
}
