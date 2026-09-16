import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 程序化音效合成器。
///
/// ## 为什么在运行时生成音频
///
/// 与 [SpriteFactory] 同理：为了让项目「克隆即跑」且不引入来源不明的音频素材，
/// 本项目用纯 Dart 代码合成 WAV 文件，首次启动时写入应用文档目录。
/// 这样既零版权风险、零仓库体积，又能保证音效可用。
///
/// ## 换成真实音效
///
/// 把同名 `.wav` 文件放进 `assets/audio/` 并在 pubspec 中声明（已声明该目录），
/// [AudioService] 会优先加载打包资源，仅当资源不存在时才回退到运行时合成。
///
/// ## 合成原理
///
/// 每个音效由若干「音符段」拼接而成，每段包含：
/// - 频率包络：起始频率线性滑向结束频率（产生 chirp / 滑音效果）
/// - 音量包络：起始音量按指数衰减到结束音量（产生打击感）
/// - 方波 / 三角波振荡：8-bit 风格音色，符合像素游戏调性
/// - 线性淡入淡出：消除拼接处的爆音（click）
class SoundSynth {
  SoundSynth._();

  /// WAV 采样率。22050Hz 足以表现 8-bit 音效，且文件体积小（单个音效约 5-15KB）。
  static const int sampleRate = 22050;

  /// 生成全部音效文件到 [targetDirectory]。
  ///
  /// [targetDirectory] 通常是应用文档目录下的 `audio/` 子目录——
  /// 该路径运行时可写，且随应用卸载自动清理。
  static Future<void> generateAll(Directory targetDirectory) async {
    if (!targetDirectory.existsSync()) {
      targetDirectory.createSync(recursive: true);
    }

    // 音效定义：名称 -> 音符序列
    // 频率选择依据：跳跃音上行营造轻快感，撞击/掉落音下行营造失落感。
    final Map<String, List<_Tone>> soundBank = <String, List<_Tone>>{
      'sfx_flap': <_Tone>[
        _Tone.sweep(
          startFreq: 520,
          endFreq: 880,
          duration: 0.085,
          volume: 0.34,
          wave: _Wave.square,
        ),
      ],
      'sfx_score': <_Tone>[
        _Tone.sweep(
          startFreq: 988,
          endFreq: 988,
          duration: 0.055,
          volume: 0.30,
          wave: _Wave.square,
        ),
        _Tone.sweep(
          startFreq: 1319,
          endFreq: 1319,
          duration: 0.085,
          volume: 0.30,
          wave: _Wave.square,
          delay: 0.055,
        ),
      ],
      'sfx_hit': <_Tone>[
        // 低频噪声感撞击：用快速下滑的方波模拟
        _Tone.sweep(
          startFreq: 220,
          endFreq: 70,
          duration: 0.16,
          volume: 0.42,
          wave: _Wave.square,
        ),
      ],
      'sfx_die': <_Tone>[
        _Tone.sweep(
          startFreq: 660,
          endFreq: 660,
          duration: 0.07,
          volume: 0.30,
          wave: _Wave.triangle,
        ),
        _Tone.sweep(
          startFreq: 520,
          endFreq: 520,
          duration: 0.07,
          volume: 0.30,
          wave: _Wave.triangle,
          delay: 0.07,
        ),
        _Tone.sweep(
          startFreq: 400,
          endFreq: 180,
          duration: 0.26,
          volume: 0.32,
          wave: _Wave.triangle,
          delay: 0.14,
        ),
      ],
      'sfx_swoosh': <_Tone>[
        _Tone.sweep(
          startFreq: 300,
          endFreq: 140,
          duration: 0.14,
          volume: 0.18,
          wave: _Wave.triangle,
        ),
      ],
    };

    // 生成全部音效文件
    for (final MapEntry<String, List<_Tone>> entry in soundBank.entries) {
      final File file = File('${targetDirectory.path}/${entry.key}.wav');
      if (file.existsSync()) {
        continue; // 已生成则跳过，避免每次启动重复写盘
      }
      final Uint8List wav = _renderTones(entry.value);
      await file.writeAsBytes(wav, flush: true);
    }

    if (kDebugMode) {
      debugPrint('[SoundSynth] 音效已生成至 ${targetDirectory.path}');
    }
  }

  /// 将一组音符渲染为完整 WAV 字节流。
  static Uint8List _renderTones(List<_Tone> tones) {
    // 先算总时长（含各音符的延迟）
    double totalDuration = 0;
    for (final _Tone tone in tones) {
      totalDuration = math.max(totalDuration, tone.delay + tone.duration);
    }

    // 末尾追加 10ms 静音，防止播放器截断尾音
    const double tailSilence = 0.01;
    final int totalSamples = ((totalDuration + tailSilence) * sampleRate).ceil();
    final Float64List buffer = Float64List(totalSamples);

    for (final _Tone tone in tones) {
      _mixTone(buffer, tone);
    }

    return _encodeWav(buffer);
  }

  /// 把单个音符叠加（mix）进采样缓冲区。
  static void _mixTone(Float64List buffer, _Tone tone) {
    final int startSample = (tone.delay * sampleRate).round();
    final int toneSamples = (tone.duration * sampleRate).round();
    final int attackSamples = (0.004 * sampleRate).round(); // 4ms 淡入
    final int releaseSamples = (0.008 * sampleRate).round(); // 8ms 淡出

    // 相位累积器：必须逐样本累加而非直接代入 2πf·t。
    // 原因：当频率随时间变化时，直接用解析式会导致相位不连续，
    // 从而产生周期性的「爆音」。逐样本积分可保证相位连续。
    // 每个音符独立从 0 起算，因此声明在循环外、本音符作用域内。
    double phase = 0;

    for (int i = 0; i < toneSamples; i++) {
      final int index = startSample + i;
      if (index < 0 || index >= buffer.length) {
        continue;
      }

      final double progress = i / toneSamples;

      // --- 频率包络：起始频率线性滑向结束频率 ---
      final double freq = tone.startFreq + (tone.endFreq - tone.startFreq) * progress;

      phase += 2 * math.pi * freq / sampleRate;

      // --- 振荡器 ---
      final double raw = switch (tone.wave) {
        _Wave.square => math.sin(phase) >= 0 ? 1.0 : -1.0,
        _Wave.triangle => (2 / math.pi) * math.asin(math.sin(phase)),
      };

      // --- 音量包络：指数衰减 + 首尾淡入淡出 ---
      final double decay = math.pow(1 - progress, 1.6).toDouble();
      double envelope = tone.volume * decay;

      if (i < attackSamples) {
        envelope *= i / attackSamples;
      }
      final int samplesFromEnd = toneSamples - i;
      if (samplesFromEnd < releaseSamples) {
        envelope *= samplesFromEnd / releaseSamples;
      }

      buffer[index] += raw * envelope;
    }
  }

  /// 把 [-1, 1] 的浮点采样编码为 16-bit PCM 单声道 WAV。
  static Uint8List _encodeWav(Float64List samples) {
    const int bitsPerSample = 16;
    const int channels = 1;
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;
    final int dataSize = samples.length * blockAlign;

    // WAV 头固定 44 字节
    final ByteData header = ByteData(44);
    int offset = 0;

    void writeString(String s) {
      for (int i = 0; i < s.length; i++) {
        header.setUint8(offset++, s.codeUnitAt(i));
      }
    }

    void writeUint32(int v) {
      header.setUint32(offset, v, Endian.little);
      offset += 4;
    }

    void writeUint16(int v) {
      header.setUint16(offset, v, Endian.little);
      offset += 2;
    }

    writeString('RIFF');
    writeUint32(36 + dataSize); // ChunkSize
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16); // Subchunk1Size (PCM)
    writeUint16(1); // AudioFormat = PCM
    writeUint16(channels);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    writeString('data');
    writeUint32(dataSize);

    // 拼接头 + 采样数据
    final Uint8List result = Uint8List(44 + dataSize);
    result.setRange(0, 44, header.buffer.asUint8List());

    final ByteData payload = result.buffer.asByteData(44);
    for (int i = 0; i < samples.length; i++) {
      // 硬限幅防止叠加后溢出
      double v = samples[i];
      if (v > 1.0) {
        v = 1.0;
      } else if (v < -1.0) {
        v = -1.0;
      }
      payload.setInt16(i * 2, (v * 32767).round(), Endian.little);
    }

    return result;
  }
}

/// 波形类型。
enum _Wave { square, triangle }

/// 单个音符的合成参数。
///
/// 用工厂构造 [sweep] 而非命名参数列表，是为了在音效表里写得紧凑易读。
class _Tone {
  const _Tone({
    required this.startFreq,
    required this.endFreq,
    required this.duration,
    required this.volume,
    required this.wave,
    this.delay = 0,
  });

  factory _Tone.sweep({
    required double startFreq,
    required double endFreq,
    required double duration,
    required double volume,
    required _Wave wave,
    double delay = 0,
  }) {
    return _Tone(
      startFreq: startFreq,
      endFreq: endFreq,
      duration: duration,
      volume: volume,
      wave: wave,
      delay: delay,
    );
  }

  /// 起始频率（Hz）。
  final double startFreq;

  /// 结束频率（Hz）。与 [startFreq] 相同即为定音符。
  final double endFreq;

  /// 音符时长（秒）。
  final double duration;

  /// 峰值音量（0-1）。
  final double volume;

  final _Wave wave;

  /// 相对于音效开头的延迟（秒），用于编排音符序列。
  final double delay;
}
