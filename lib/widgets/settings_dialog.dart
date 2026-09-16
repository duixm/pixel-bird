import 'package:flutter/material.dart';

import '../game/config/game_palette.dart';
import '../services/audio_service.dart';
import '../services/score_storage.dart';

/// 设置对话框。
///
/// 提供音效开关与存档重置。刻意保持极简——休闲游戏的设置面板
/// 每多一个选项都会增加玩家的决策负担。
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({required this.audio, required this.scores, super.key});

  final AudioPlayerService audio;

  /// 分数存档仓库（用于「清除最高分」操作）。
  final ScoreRepository scores;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late bool _soundEnabled = widget.audio.enabled;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: GamePalette.panelBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: GamePalette.panelOutline, width: 3),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '设置',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: GamePalette.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // ---- 音效开关 ----
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _soundEnabled,
              activeThumbColor: GamePalette.accent,
              title: const Text(
                '音效',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: GamePalette.textPrimary,
                ),
              ),
              subtitle: Text(
                _soundEnabled ? '已开启' : '已关闭',
                style: const TextStyle(
                  fontSize: 13,
                  color: GamePalette.textSecondary,
                ),
              ),
              onChanged: (bool value) async {
                final bool next = await widget.audio.toggleSound();
                if (!mounted) {
                  return;
                }
                setState(() => _soundEnabled = next);
              },
            ),

            const Divider(height: 20, color: GamePalette.panelOutline),

            // ---- 重置存档 ----
            TextButton.icon(
              onPressed: _confirmReset,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: const Text('清除最高分记录'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFC0392B),
                alignment: Alignment.centerLeft,
              ),
            ),

            const SizedBox(height: 4),

            // ---- 关闭 ----
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: GamePalette.accent,
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 二次确认后清空存档。破坏性操作必须确认。
  Future<void> _confirmReset() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: GamePalette.panelBackground,
        title: const Text('确认清除？'),
        content: const Text('最高分与游玩记录将被永久删除，此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC0392B),
            ),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await widget.scores.resetAll();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('记录已清除')),
    );
  }
}
