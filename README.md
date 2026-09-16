# Pixel Bird · 像素小鸟

一款基于 **Flutter + Flame** 引擎的跨平台（iOS / Android）休闲游戏，完整复刻经典 Flappy Bird 玩法：点击屏幕控制小鸟飞行，穿越管道障碍，挑战更高分数。

## 特性

| 功能 | 实现说明 |
|---|---|
| 核心玩法 | 恒定重力 + 瞬时冲量物理模型，点击起飞 |
| 计分系统 | 管道右边缘越过小鸟判定线时得分，含防重复计分标志 |
| 难度递增 | 四段式曲线（教学 / 成长 / 挑战 / 巅峰），缝隙收窄 + 速度提升双杠杆，带可玩性硬边界 |
| 死亡重玩 | 四态状态机（待机 / 游玩 / 坠落 / 结算），含坠落演出与输入冷却 |
| 动画 | 小鸟三帧翅动 + 速度驱动的俯仰角；地面与远景三层视差滚动 |
| 音效 | 5 种音效（起飞 / 得分 / 撞击 / 死亡 / 切换），程序化合成 |
| 双平台适配 | 固定分辨率视口，保证不同机型手感一致 |
| 存档 | 最高分、游玩局数、音效开关本地持久化 |

## 快速开始

### 环境要求

| 依赖 | 版本 | 说明 |
|---|---|---|
| Flutter SDK | **3.35.0 – 3.46.x** | 需 Dart 3.9～3.10；**不要用 3.47+**（见下方说明） |
| Dart SDK | 3.9.0+ | 随 Flutter 附带 |
| JDK | 17+ | Android 构建需要（推荐 21） |
| Xcode | 15+ | iOS 构建需要，仅 macOS |
| Android SDK | API 34+ | Android 构建需要 |

> **⚠️ 版本约束说明（重要）**
>
> 本项目锁定 `flame: >=1.35.1 <1.36.0`，原因是 **flame 1.36.0 起要求
> Dart SDK >= 3.11**，而 Dart 3.11 需要 Flutter 3.47+。
> Flame 1.35.1 是最后一个支持 Dart 3.8/3.9 的版本。
>
> - 若你使用 **Flutter 3.35 ~ 3.46**：直接可用，无需改动。
> - 若你使用 **Flutter 3.47+**：可把 `pubspec.yaml` 中的 flame 改为
>   `^1.38.2` 并放宽 `environment.sdk` 至 `>=3.11.0`。代码层面
>   `FixedResolutionViewport` 的用法在两版之间保持兼容。

验证环境：

```bash
flutter doctor -v
```

### 安装依赖

```bash
cd 像素鸟
flutter pub get
```

> **若 `pub get` 报 `Proxy failed to establish tunnel (502)`**：
> 这是公司代理拦截了 pub.dev 导致的。解决办法是让 pub 绕过代理：
>
> ```bash
> # macOS / Linux
> unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
> export NO_PROXY="pub.dev,pub.flutter-io.cn,localhost,127.0.0.1"
> flutter pub get
> ```
>
> ```powershell
> # Windows PowerShell
> Remove-Item Env:http_proxy, Env:https_proxy, Env:HTTP_PROXY, Env:HTTPS_PROXY -ErrorAction SilentlyContinue
> $env:NO_PROXY = "pub.dev,pub.flutter-io.cn,localhost,127.0.0.1"
> flutter pub get
> ```
>
> 若仍不通，可改用国内镜像：
>
> ```bash
> export PUB_HOSTED_URL="https://pub.flutter-io.cn"
> export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
> ```

### 运行

```bash
# 查看可用设备
flutter devices

# 运行到指定设备
flutter run -d <device-id>

# 直接运行到当前唯一连接的设备
flutter run
```

### 构建发布包

```bash
# Android APK（单架构，便于分发测试）
flutter build apk --release

# Android App Bundle（上架 Google Play 用）
flutter build appbundle --release

# iOS（需 macOS + Xcode，产物为 .xcarchive / .ipa）
flutter build ipa --release
```

产物位置：

| 平台 | 路径 |
|---|---|
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Android AAB | `build/app/outputs/bundle/release/app-release.aab` |
| iOS Archive | `build/ios/archive/Runner.xcarchive` |

> **iOS 注意事项**：首次构建需在 `ios/Runner.xcworkspace` 中用 Xcode 配置
> 开发者签名（Signing & Capabilities → Team）。未配置签名时只能构建模拟器版本。

### 生成应用图标

```bash
# 1. 生成图标源文件（1024x1024 PNG）
flutter test tool/generate_icon_test.dart

# 2. 写入各平台工程
dart run flutter_launcher_icons
```

### 浏览器运行（快速预览）

若你暂时不想装 Android SDK / Xcode，可以直接在浏览器里玩：

```bash
# 双击项目根目录的 run_web.bat
```

脚本会依次完成：拉依赖 → 构建 web 产物 → 补编译内置 shader →
启动本地服务器（`http://127.0.0.1:8090`）→ 用 Edge 打开游戏。

打开后按 `F12`，再按 `Ctrl+Shift+M` 切换到手机模拟视图，选一个竖屏机型
（如 iPhone 12 Pro）就能体验真实手机手感。

> **为什么需要这个脚本，不能直接 `flutter run -d edge`？**
>
> 本项目开发机上有两个环境限制，与游戏代码无关：
>
> 1. **`flutter run` 的 dev-server 需要调用 `reg.exe`** 探测浏览器版本，
>    若该程序被安全策略拦截，命令会直接失败。脚本改用 Python 静态服务器托管。
> 2. **Release 构建时 `impellerc` 未能收到 `shader_lib` 的 include 路径**，
>    导致内置 `ink_sparkle.frag` 编译失败并中断构建。脚本在构建后
>    手动补编译这一个文件。
>
> 这两个问题都属于 Flutter 工具链在本机的环境故障，不影响游戏逻辑。
> 换一台环境正常的机器，直接 `flutter run -d chrome` 即可。

## 项目结构

```
像素鸟/
├── run_web.bat                      # ★ 一键在浏览器中运行（见「浏览器运行」章节）
├── lib/
│   ├── main.dart                    # 入口：初始化顺序 + 加载态 + 错误态
│   ├── assets/                      # 程序化资源生成（零二进制依赖）
│   │   ├── sprite_factory.dart      #   用 Canvas 绘制并缓存全部游戏贴图
│   │   └── sound_synth.dart         #   用方波/三角波合成 WAV 音效
│   ├── game/
│   │   ├── game_world.dart          # ★ 主循环编排：物理 / 生成 / 碰撞 / 计分
│   │   ├── game_state.dart          # 四态状态机定义
│   │   ├── config/
│   │   │   ├── game_config.dart     # ★ 全部手感参数集中调参
│   │   │   ├── game_palette.dart    # 配色定义
│   │   │   └── difficulty_curve.dart# ★ 难度曲线唯一数据源
│   │   └── components/
│   │       ├── bird_component.dart      # 小鸟：物理 + 翅动 + 俯仰角
│   │       ├── pipe_pair.dart           # 管道对：纹理平铺 + 碰撞矩形
│   │       ├── ground_component.dart    # 滚动地面（参与碰撞）
│   │       └── background_component.dart# 视差背景
│   ├── screens/
│   │   └── game_screen.dart         # Flame 画布 + Flutter UI 叠加
│   ├── widgets/
│   │   ├── score_display.dart       # 描边分数文字
│   │   ├── game_over_panel.dart     # 结算面板（分数滚动动画）
│   │   ├── start_hint.dart          # 待机提示 + 难度提示
│   │   └── settings_dialog.dart     # 设置（音效开关 / 重置存档）
│   └── services/
│       ├── score_storage.dart       # SharedPreferences 存档
│       └── audio_service.dart       # 音效池 + 音源自动回退
├── tool/
│   └── generate_icon_test.dart      # 应用图标生成器
├── test/
│   ├── difficulty_curve_test.dart   # 难度曲线不变量测试（13 个）
│   └── game_world_test.dart         # 游戏世界集成测试（12 个）
├── assets/
│   ├── images/                      # （可选）真实美术素材放这里
│   ├── audio/                       # （可选）真实音效放这里
│   └── fonts/                       # （可选）像素字体放这里
├── android/                         # Android 原生工程
├── ios/                             # iOS 原生工程
└── pubspec.yaml
```

## 资源说明

### 设计取舍：程序化生成 vs 外部素材

本项目**默认不包含任何二进制素材文件**。所有贴图与音效都在运行时由代码生成：

| 资源 | 生成方式 | 代码位置 |
|---|---|---|
| 小鸟（3 帧翅膀） | `Canvas` 绘制椭圆/路径 | `sprite_factory.dart` |
| 管道（管身 + 管口） | `Canvas` 绘制渐变矩形 | `sprite_factory.dart` |
| 地面 / 远景剪影 | `Canvas` 绘制渐变 + 圆形树冠 | `sprite_factory.dart` |
| 5 种音效 | 方波/三角波 + 频率/音量包络合成 16-bit PCM WAV | `sound_synth.dart` |

**为什么这样设计：**

1. **克隆即跑** —— 无需下载或放置任何素材文件，`flutter run` 直接可玩。
2. **零版权风险** —— 不含任何来源不明的第三方素材。
3. **仓库轻量** —— 无二进制文件，Git 历史干净。

### 接入真实美术素材

每个资源都留有**同名文件覆盖通道**，接入素材**无需改动任何游戏代码**：

```bash
# 1. 把素材按下列文件名放入对应目录
assets/images/bird_wings_up.png      # 小鸟翅膀向上（建议 48x34）
assets/images/bird_wings_mid.png     # 小鸟翅膀水平
assets/images/bird_wings_down.png    # 小鸟翅膀向下
assets/images/pipe_body.png          # 管道管身（建议 64x32，纵向可平铺）
assets/images/pipe_cap.png           # 管道管口（建议 76x26）
assets/images/ground_tile.png        # 地面贴图（建议 32x96，横向可平铺）
assets/images/skyline_tile.png       # 远景剪影（建议 240x140，横向可平铺）
assets/images/app_icon.png           # 应用图标（1024x1024）
assets/images/app_icon_foreground.png# Android 自适应图标前景层

assets/audio/sfx_flap.wav            # 起飞
assets/audio/sfx_score.wav           # 得分
assets/audio/sfx_hit.wav             # 撞击
assets/audio/sfx_die.wav             # 死亡
assets/audio/sfx_swoosh.wav          # 界面切换
```

```bash
# 2. 重新生成平台资源
flutter pub get && flutter run
```

**回退机制说明**：`SpriteFactory` 对每个资源先尝试加载同名 PNG，加载失败才
程序化绘制；`AudioService` 会先探测 `assets/audio/` 下 5 个音效是否齐备，
**全部存在**才使用打包资源，否则整体回退到合成方案（避免出现一半真实音效、
一半合成音效的不一致表现）。

### 字体（可选）

默认**未声明**任何字体，游戏使用系统字体，功能完全正常。

若需像素风字体：把 `.ttf` 放到 `assets/fonts/` 下，然后在 `pubspec.yaml`
中取消 `fonts:` 段的注释。

> **注意**：不要在文件不存在的情况下声明字体。Flutter 会在构建时校验
> 字体路径，声明了不存在的文件会直接报
> `unable to locate asset entry in pubspec.yaml` 并中止构建。
> （这正是本项目默认注释掉该段的原因。）

## 调参指南

游戏手感高度依赖数值。所有参数集中在 **`lib/game/config/game_config.dart`**，
修改后热重载即可立即生效（`flutter run` 下按 `r`）。

### 关键参数与手感关系

| 参数 | 默认值 | 调大的效果 | 调小的效果 |
|---|---|---|---|
| `gravity` | 1400 | 下坠更快，更紧张 | 漂浮感强，更宽松 |
| `flapVelocity` | -420 | 每次点击升得更高 | 升幅小，操作更密集 |
| `birdHitboxRadius` | 11 | 判定严格，易死 | 判定宽容，易上手 |
| `pipeGapStart` | 165 | 开局更容易 | 开局即挑战 |
| `pipeSpeedStart` | 118 | 管道逼近更快 | 节奏舒缓 |
| `pipeSpacing` | 215 | 管道更稀疏，反应时间充裕 | 管道密集，压力大 |
| `launchGracePeriod` | 0.75 | 开局准备时间更充裕 | 开局更快进入紧张状态 |
| `firstPipeLeadIn` | 60 | 首组管道更晚出现 | 首组管道更早出现 |

**关键比例**：`flapVelocity / gravity` 决定单次点击的上升高度。
默认值下约为 168px，即屏幕高度的 26%。

### 起飞缓冲（`launchGracePeriod`）

这是本作对原版手感的一处重要修正，值得单独说明。

**问题**：若点击「开始」后小鸟立刻受重力下坠，而首组管道按常规间距（215px）
需要约 1.8 秒才进入视野——但小鸟从出生高度坠到地面只需约 0.65 秒。
结果是**玩家还没看到任何障碍就已经死了**，体验极差。

**解法**：点击开始后进入一段缓冲期，此时：

- 小鸟**悬停**（不受重力，`birdVelocityY == 0`）
- 管道与地面**照常滚动**，玩家能看清即将到来的障碍
- 玩家**随时可点击提前起飞**（`_launchGrace = 0`）

配合 `firstPipeLeadIn = 60`（首组管道用更短的生成距离），
保证首组管道一定在玩家可能坠地之前出现。

`test/game_world_test.dart` 中的「首组管道在小鸟坠地前进入视野」测试守住这条不变量。

### 难度曲线

曲线逻辑在 **`lib/game/config/difficulty_curve.dart`**。四段设计：

| 分数区间 | 缝隙 | 速度 | 设计意图 |
|---|---|---|---|
| 0–5 | 165 → 152 | 118 → 129 | 教学区：变化极缓，建立手感 |
| 6–20 | 152 → 113 | 129 → 162 | 成长区：稳定上升 |
| 21–40 | 113 → 110 | 162 → 206 | 挑战区：逼近缝隙下限 |
| 41+ | 110（锁死） | 206 → 225 | 巅峰区：仅速度缓慢增加 |

**两条硬边界不可移除：**

- `pipeGapMin = 110` —— 约为小鸟直径的 4.4 倍。低于此值会出现数学上无解的管道。
- `pipeSpeedMax = 225` —— 超过后管道单帧位移过大，且超出人类反应极限。

`test/difficulty_curve_test.dart` 中的测试会守住这两条边界。

## 架构说明

### 分层结构

```
┌──────────────────────────────────────────────┐
│  main.dart        初始化 + 加载态 + 错误态      │
├──────────────────────────────────────────────┤
│  screens/         game_screen.dart            │
│  ┌────────────────────────────────────────┐  │
│  │  UI 层（Flutter）                       │  │
│  │  分数 / 结算面板 / 提示 / 设置           │  │
│  │         ↑ 回调（单向数据流）             │  │
│  │  游戏层（Flame GameWidget）             │  │
│  │  物理 / 碰撞 / 渲染                     │  │
│  └────────────────────────────────────────┘  │
├──────────────────────────────────────────────┤
│  game_world.dart   编排者：只调度，不实现细节  │
├──────────────────────────────────────────────┤
│  components/      各司其职的游戏对象          │
│  config/          参数 / 配色 / 难度曲线      │
│  services/        存档 / 音频                 │
│  assets/          程序化资源生成              │
└──────────────────────────────────────────────┘
```

### 关键技术决策

**1. 固定步长积分（Fix Your Timestep）**

Flame 的 `update(dt)` 使用可变 dt。若直接积分，60Hz 与 120Hz 设备上的跳跃
高度会不一致。`GameWorld.update` 累积真实时间，以 `1/120` 秒为固定步长推进
物理，余数留到下一帧：

```dart
_accumulator += clampedDt;
while (_accumulator >= GameConfig.fixedTimeStep) {
  _stepFixed(GameConfig.fixedTimeStep);
  _accumulator -= GameConfig.fixedTimeStep;
}
```

收益：跨设备手感一致、高速下坠不穿模、物理可复现（便于测试）。

**2. 物理用「赋值」而非「叠加」**

点击时 `velocityY = flapVelocity`（直接赋值），而不是 `velocityY += impulse`。
叠加会导致连续点击时上升速度不断累加，出现「越点越快」的失控手感。
赋值保证每次点击精确对应固定升幅 —— 这是原版 Flappy Bird 的做法。

**3. 固定分辨率视口**

游戏使用 `FixedResolutionViewport(resolution: 360x640)`。若按屏幕实际尺寸
布局，iPad 上管道会显得极宽导致难度骤降。固定视口保证所有设备的**相对手感**
一致，多余区域留黑边。

**4. 碰撞用圆形近似而非贴图精确判定**

小鸟的碰撞体是半径 11px 的圆，**小于**贴图尺寸。这是刻意设计的宽容度 ——
视觉上蹭到边缘但实际不算撞，显著降低挫败感。

**5. 音源自动回退**

`AudioService` 维护 5 个 `AudioPlayer` 的池。单个播放器重复播放会互相打断
（后一次截断前一次），快速连点时会丢音。播放器池轮转解决了这个问题。

**6. 依赖注入而非单例直取**

`GameWorld` 不直接访问 `ScoreStorage.instance` 或 `AudioCache` 单例，而是
接收 `AudioPlayerService` 与 `ScoreRepository` 两个**接口**：

```dart
// 生产环境（main.dart）
GameScreen(audio: audioService, scores: scoreStorage)

// 测试环境（test/game_world_test.dart）
GameWorld(
  audio: StubAudioService(),      // 无操作的音频替身
  scores: StubScoreRepository(),  // 内存版存档
)
```

这样做的收益是**测试可以真正启动游戏世界**并推进数百帧物理，而不触碰
`SharedPreferences`、平台通道或文件系统。这直接让下面的 3 个 bug 被捕获：

- 开局小鸟立即下坠导致「还没看到管道就死了」（见「起飞缓冲」章节）
- 死亡后连点被误判为重开
- 管道组件未随世界重置而回收

**7. 死亡分两个状态**

`dying`（坠落演出）与 `gameOver`（结算面板）分离。撞击瞬间直接弹面板会很突兀，
0.75 秒的坠落缓冲让死亡有「过程感」，同时避免玩家误以为卡死。
此外 `dying` 状态设有兜底计时（`_gameOverDelay`），若因极端情况小鸟未能落地，
也会强制收束本局，不会卡住。

## 测试

```bash
# 全部测试（当前 25/25 通过）
flutter test

# 仅难度曲线不变量测试
flutter test test/difficulty_curve_test.dart

# 仅游戏世界集成测试
flutter test test/game_world_test.dart

# 生成应用图标
flutter test tool/generate_icon_test.dart
```

> **注意**：`flutter test` 会启动 `flutter_tester` 进程并通过本地 WebSocket 回连。
> 若你的环境设置了 `http_proxy` / `https_proxy`，握手会被代理破坏并报
> `Invalid WebSocket upgrade request`。跑测试前先清掉代理：
>
> ```bash
> unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
> flutter test
> ```
>
> 同理，若 `flutter analyze` 或 `flutter test` 卡在 `Resolving dependencies`，
> 参考上方「安装依赖」中的代理绕过方案。

## 常见问题

**Q: 运行后没有声音？**

音效首次启动时合成并写入应用支持目录，首次运行略有延迟属正常。
若始终无声，检查系统媒体音量，以及应用内设置面板的音效开关。

**Q: iOS 构建报签名错误？**

`open ios/Runner.xcworkspace`，在 Signing & Capabilities 中选择你的
Apple Developer Team，并确保 Bundle Identifier 唯一。

**Q: Android 构建报 JDK 版本错误？**

本项目要求 JDK 17+。检查 `flutter doctor -v` 中 Java 版本，
必要时在 `android/app/build.gradle` 中调整 `compileOptions`。

**Q: 画面两侧有黑边？**

这是固定分辨率视口的设计取舍（见「关键技术决策 3」）。在 9:16 之外比例的
设备上会留边，但保证所有设备手感一致。若希望填满屏幕，可在
`game_world.dart` 的 `onLoad` 中改用 `MaxViewport`，但需自行处理布局适配。

**Q: 如何调整游戏难度？**

见上方「调参指南」与「难度曲线」章节。

**Q: 没有 Android SDK / Xcode，能验证代码是否正确吗？**

可以。`flutter analyze` 会做完整静态分析（本项目当前 **No issues found!**），
`flutter test` 会真实编译并运行全部 Dart 代码（当前 **25/25 通过**）。
两者都不需要平台工具链。真正的 APK/IPA 打包才需要 Android SDK / Xcode。

**Q: 哪些地方是"未验证"的？**

游戏逻辑、物理、难度曲线、状态机均已被测试覆盖。未经真机验证的部分只有：
触屏实际手感、音效在真机扬声器上的表现、iOS 签名配置。
建议首次上手时用 `flutter run` 在真机上跑，并按「调参指南」微调。

## 参考项目

调研了以下开源实现作为架构参考：

| 项目 | 星标 | 技术栈 | 借鉴内容 |
|---|---|---|---|
| [moha-b/Flappy-Bird](https://github.com/moha-b/Flappy-Bird) | 87 | Flutter 纯动画 + Hive | 目录分层、本地存档方案 |
| [g0rdan/Flutter.Bird](https://github.com/g0rdan/Flutter.Bird) | 139 | Flame 引擎 | Flame 组件化思路（项目已归档） |
| [Onnesok/flappy-bird](https://github.com/Onnesok/flappy-bird) | 9 | Flutter + Flame | flame_audio 集成方式 |

**与参考项目的主要差异：**

1. 使用**固定步长积分**，参考项目均直接用可变 `dt`。
2. 采用 **Flame 组件系统**统一管理游戏对象，而非手写渲染循环。
3. **程序化生成全部资源**，参考项目依赖外部素材文件。
4. 难度采用**分段曲线 + 硬边界**，参考项目多为线性递增。

## 依赖

| 包 | 版本 | 用途 |
|---|---|---|
| `flame` | `>=1.35.1 <1.36.0` | 游戏引擎（游戏循环、组件系统、视口） |
| `flame_audio` | ^2.11.7 | 音频播放（Flame 官方桥接） |
| `audioplayers` | 由 flame_audio 引入 | 底层音频播放器 |
| `shared_preferences` | ^2.5.3 | 最高分与设置持久化 |
| `wakelock_plus` | ^1.3.2 | 游戏时保持屏幕常亮 |

## 许可

本项目为学习与参考用途。Flappy Bird 的原始创意与美术风格归其原作者
Dong Nguyen 所有。本项目不包含任何原版素材，全部资源均为程序化生成。
