import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../assets/sound_synth.dart';
import 'score_storage.dart';

/// 音效标识。集中在枚举里，避免各处硬编码字符串导致的拼写错误。
enum Sfx {
  /// 点击起飞。
  flap('sfx_flap'),

  /// 得分。
  score('sfx_score'),

  /// 撞击管道或地面。
  hit('sfx_hit'),

  /// 死亡坠落。
  die('sfx_die'),

  /// 界面切换（如打开结算面板）。
  swoosh('sfx_swoosh');

  const Sfx(this.fileName);

  /// 不含扩展名的文件名，与 `assets/audio/` 下的资源名保持一致。
  final String fileName;
}

/// 音频能力的抽象接口。
///
/// 抽出接口的目的是**可测试性**：[GameWorld] 只依赖这个接口，
/// 因此在单元测试中可以注入一个不触碰平台通道与文件系统的替身，
/// 从而把测试范围严格限制在游戏逻辑上。
///
/// 生产环境使用 [AudioService] 实现；测试使用轻量 stub。
abstract interface class AudioPlayerService {
  /// 播放一次性音效。
  void play(Sfx sfx);

  /// 循环播放背景音乐。传入 null 表示停止。
  Future<void> playBgm(String? assetFileName);

  /// 音效是否启用。
  bool get enabled;

  /// 切换音效开关，返回切换后的状态。
  Future<bool> toggleSound();

  /// 释放全部音频资源。
  Future<void> dispose();
}

/// 音频服务（生产实现）。
///
/// ## 音源优先级
///
/// 1. **打包资源** `assets/audio/<name>.wav` —— 若开发者放入了真实音效则使用。
/// 2. **运行时合成** —— 资源缺失时由 [SoundSynth] 生成到应用支持目录。
///
/// ## 关键实现说明：为什么不用 `AudioCache.prefix`
///
/// `AudioCache` 的 `prefix` 只解析 Flutter 打包资源（`AssetSource`），
/// 无法寻址运行时写入磁盘的文件。因此运行时合成路径必须改用
/// `DeviceFileSource` 直接播放绝对路径。
///
/// 这一限制决定了 [play] 内部必须区分两条播放分支：
/// - 有打包资源：`AssetSource`（走 `AudioCache`，自动管理播放器池）
/// - 运行时文件：`DeviceFileSource` + 自维护的播放器池
///
/// ## 为什么需要播放器池
///
/// 「快速连点起飞」会在一秒内触发多次 `sfx_flap`。单个 `AudioPlayer`
/// 重复播放会互相打断（后一次截断前一次），听起来像丢音。
/// 因此维护 [poolSize] 个播放器轮转使用。
class AudioService implements AudioPlayerService {
  AudioService._();

  /// 播放器池大小。5 个足以覆盖人类连点频率（约每秒 10 次以内）。
  static const int poolSize = 5;

  /// 运行时合成音效的目录名。
  static const String _runtimeAudioFolder = 'audio';

  /// 打包资源目录。
  static const String _assetPrefix = 'assets/audio/';

  final AudioCache _assetCache = AudioCache.instance;

  /// 音频播放器池。轮转使用，索引循环推进。
  final List<AudioPlayer> _pool = <AudioPlayer>[];
  int _poolCursor = 0;

  AudioPlayer? _bgmPlayer;

  /// 运行时音效目录。为 null 表示走打包资源分支。
  String? _runtimeDir;

  /// 打包资源是否可用。
  bool _useAssetSource = false;

  /// 磁盘上实际存在的运行时音效文件路径表：音效名 -> 绝对路径。
  final Map<String, String> _runtimeFiles = <String, String>{};

  bool _initialized = false;
  bool _enabled = true;

  /// 初始化音频系统。必须在 `WidgetsFlutterBinding.ensureInitialized()` 之后调用。
  static Future<AudioService> initialize() async {
    final AudioService service = AudioService._().._assetCache.prefix = _assetPrefix;
    await service._setup();
    return service;
  }

  Future<void> _setup() async {
    _enabled = ScoreStorage.instance.soundEnabled;

    // --- 第一步：尝试解析打包资源是否齐备 ---
    _useAssetSource = await _probeAssetSounds();

    if (!_useAssetSource) {
      // --- 第二步：回退到运行时合成 ---
      final Directory dir = await _resolveRuntimeAudioDirectory();
      await SoundSynth.generateAll(dir);
      _runtimeDir = dir.path;

      // 记录每个音效的绝对路径，播放时直接寻址。
      for (final Sfx sfx in Sfx.values) {
        final String path =
            '${dir.path}${Platform.pathSeparator}${sfx.fileName}.wav';
        if (File(path).existsSync()) {
          _runtimeFiles[sfx.fileName] = path;
        }
      }
    }

    // --- 第三步：构建播放器池 ---
    for (int i = 0; i < poolSize; i++) {
      final AudioPlayer player = AudioPlayer();
      // 音效走「低延迟」语义：不申请音频焦点，避免打断用户正在播放的音乐。
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setReleaseMode(ReleaseMode.stop);
      _pool.add(player);
    }

    _initialized = true;

    if (kDebugMode) {
      debugPrint(
        '[AudioService] 音源=${_useAssetSource ? "打包资源" : "运行时合成(${_runtimeDir ?? "?"})"} '
        '已加载音效=${_useAssetSource ? Sfx.values.length : _runtimeFiles.length}',
      );
    }
  }

  /// 探测 `assets/audio/` 下是否提供了真实音效文件。
  ///
  /// 实现方式：尝试将每个音效加载进 `Flame.images` 之外的标准资源通道。
  /// 这里选用更轻量的判断——直接尝试 `rootBundle` 读取首个字节。
  /// 但为了避免引入 `services.dart` 依赖，改用 AudioCache 的 load 并捕获异常。
  Future<bool> _probeAssetSounds() async {
    // 至少要有一个音效资源存在才认为「开发者提供了素材」。
    // 逐个尝试加载全部音效，任一失败即视为未提供完整素材，整体回退到合成方案，
    // 以保证音效表现一致（不会出现一半真实音效、一半合成音效）。
    try {
      for (final Sfx sfx in Sfx.values) {
        await _assetCache.load('${sfx.fileName}.wav');
      }
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AudioService] 未检测到完整打包音效，改用运行时合成：$error');
      }
      return false;
    }
  }

  /// 确定运行时音效写入目录。
  ///
  /// 使用应用支持目录而非缓存目录：后者可能被系统在存储紧张时清理，
  /// 导致音效在下次启动时消失（虽会自动重建，但多发一次生成开销）。
  Future<Directory> _resolveRuntimeAudioDirectory() async {
    try {
      final Directory base = await getApplicationSupportDirectory();
      return Directory(
        '${base.path}${Platform.pathSeparator}$_runtimeAudioFolder',
      );
    } on Exception {
      final Directory temp = Directory.systemTemp;
      return Directory(
        '${temp.path}${Platform.pathSeparator}$_runtimeAudioFolder',
      );
    }
  }

  /// 播放音效。未初始化或用户已关闭音效时静默忽略。
  @override
  void play(Sfx sfx) {
    if (!_initialized || !_enabled) {
      return;
    }

    // 从池中取下一个播放器，循环轮转。
    final AudioPlayer player = _pool[_poolCursor];
    _poolCursor = (_poolCursor + 1) % _pool.length;

    // 播放是副作用，不阻塞游戏循环；错误仅记录，不影响玩法。
    unawaited(
      _playOn(player, sfx).catchError((Object error) {
        if (kDebugMode) {
          debugPrint('[AudioService] 播放 ${sfx.fileName} 失败：$error');
        }
      }),
    );
  }

  Future<void> _playOn(AudioPlayer player, Sfx sfx) async {
    final Source source;
    if (_useAssetSource) {
      source = AssetSource('${sfx.fileName}.wav');
    } else {
      final String? path = _runtimeFiles[sfx.fileName];
      if (path == null) {
        return; // 该音效未成功生成，静默跳过
      }
      source = DeviceFileSource(path);
    }

    // stop 后 play 可确保连点时从零开始播，而不是叠加在上一次的尾音上。
    await player.stop();
    await player.play(source);
  }

  /// 循环播放背景音乐。传入 null 停止当前 BGM。
  @override
  Future<void> playBgm(String? assetFileName) async {
    if (!_initialized || !_enabled) {
      return;
    }

    if (assetFileName == null) {
      await _bgmPlayer?.stop();
      return;
    }

    _bgmPlayer ??= AudioPlayer();
    await _bgmPlayer!.setReleaseMode(ReleaseMode.loop);
    await _bgmPlayer!.play(AssetSource(assetFileName));
  }

  /// 音效是否启用。
  @override
  bool get enabled => _enabled;

  /// 切换音效开关并持久化，返回切换后的状态。
  @override
  Future<bool> toggleSound() async {
    _enabled = !_enabled;
    await ScoreStorage.instance.setSoundEnabled(enabled: _enabled);

    if (_enabled) {
      play(Sfx.swoosh); // 给出即时可感知的反馈
    } else {
      // 关闭时立刻静音正在播放的 BGM（如果有）。
      await _bgmPlayer?.stop();
    }
    return _enabled;
  }

  /// 释放全部音频资源。应用退出或热重载时调用。
  @override
  Future<void> dispose() async {
    for (final AudioPlayer player in _pool) {
      await player.dispose();
    }
    _pool.clear();
    await _bgmPlayer?.dispose();
    _bgmPlayer = null;
    _initialized = false;
  }
}
